// lib/services/payment_service.dart
//
// ═══════════════════════════════════════════════════════════════════════════════
// PRODUCTION PAYMENT SERVICE
// ─────────────────────────────────────────────────────────────────────────────
// Handles:
//   • Razorpay QR Code creation (driver shows → customer scans with UPI app)
//   • Cash payment confirmation (idempotent, atomic)
//   • Payment status polling (fallback when webhook is late)
//   • Socket event wiring for real-time updates
//
// RACE-CONDITION SAFETY STRATEGY
// ─────────────────────────────────────────────────────────────────────────────
//  1. All writes use optimistic locking on the backend:
//        db.Payment.findOneAndUpdate(
//          { tripId, status: 'pending' },     // ← only match if still pending
//          { $set: { status: 'processing' } } // ← atomic compare-and-swap
//        )
//     If a second request arrives while the first is processing, the DB
//     returns null and the backend returns 409 → client ignores it.
//
//  2. Client-side: _paymentLock bool prevents double-taps from sending two
//     requests before the first one returns.
//
//  3. Idempotency key: tripId is used as the unique payment key.  The backend
//     rejects any request where a payment document already exists for that
//     tripId with status != 'pending'.
//
//  4. Webhooks: Backend verifies Razorpay-Signature, then does the same atomic
//     findOneAndUpdate before crediting wallet.  Even if webhook fires twice,
//     the second call finds status != 'pending' and returns 200 immediately
//     (idempotent response — Razorpay requires this).
// ═══════════════════════════════════════════════════════════════════════════════

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Models
// ─────────────────────────────────────────────────────────────────────────────

enum PaymentStatus { idle, creatingQr, qrReady, polling, success, failed, alreadyPaid }

class PaymentResult {
  final bool success;
  final String? message;
  final Map<String, dynamic>? data;

  const PaymentResult({required this.success, this.message, this.data});
}

class QrPaymentData {
  final String qrCodeUrl;   // Razorpay-hosted QR image URL (show in driver app)
  final String qrId;        // Razorpay QR code ID (for status polling)
  final double amount;
  final String tripId;

  const QrPaymentData({
    required this.qrCodeUrl,
    required this.qrId,
    required this.amount,
    required this.tripId,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// PaymentService singleton
// ─────────────────────────────────────────────────────────────────────────────

class PaymentService {
  static final PaymentService _instance = PaymentService._internal();
  factory PaymentService() => _instance;
  PaymentService._internal();

  static const String _apiBase = 'https://ghumobackend.onrender.com';

  // ── Guards ─────────────────────────────────────────────────────────────────
  bool _paymentLock = false;        // prevent double-tap race condition
  Timer? _pollTimer;
  int _pollCount = 0;
  static const int _maxPolls = 24; // 2 min at 5s interval

  // ── State callbacks ────────────────────────────────────────────────────────
  void Function(PaymentStatus status)? onStatusChange;
  void Function(double driverAmount, double walletBalance)? onPaymentSuccess;
  void Function(String message)? onError;

  // ── Auth helper ────────────────────────────────────────────────────────────
  Future<String?> _getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('auth_token');
  }

  Future<Map<String, String>> _authHeaders() async {
    final token = await _getToken();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  // ══════════════════════════════════════════════════════════════════════════
  // 1) CREATE RAZORPAY QR CODE  (driver side)
  //
  // Flow:
  //   Driver app  ──POST /api/payment/qr/create──▶  Backend
  //   Backend     ──POST /v1/payments/qr_codes──▶   Razorpay
  //   Razorpay    ──◀── { id, image_url }  ─────── Backend
  //   Backend     ──◀── { qrId, qrCodeUrl } ─────  Driver app
  //   Driver app displays QR image (or renders qrCodeUrl as QrImage widget)
  //   Customer scans with any UPI app (GPay, PhonePe, Paytm…)
  //   Razorpay    ──POST /api/webhooks/razorpay──▶  Backend  (payment.captured)
  //   Backend     credits driver wallet  +  emits socket events to both sides
  // ══════════════════════════════════════════════════════════════════════════

  Future<QrPaymentData?> createQrCode({
    required String tripId,
    required String driverId,
    required double fareAmount,
  }) async {
    if (_paymentLock) {
      debugPrint('⚠️ PaymentService: createQrCode blocked — lock active');
      return null;
    }
    _paymentLock = true;
    onStatusChange?.call(PaymentStatus.creatingQr);

    try {
      final headers = await _authHeaders();
      final response = await http
          .post(
            Uri.parse('$_apiBase/api/payment/qr/create'),
            headers: headers,
            body: jsonEncode({
              'tripId': tripId,
              'driverId': driverId,
              'amount': fareAmount,
            }),
          )
          .timeout(const Duration(seconds: 15));

      final data = jsonDecode(response.body) as Map<String, dynamic>;

      if (response.statusCode == 200 && data['success'] == true) {
        final qr = QrPaymentData(
          qrCodeUrl: data['qrCodeUrl'] as String,
          qrId: data['qrId'] as String,
          amount: (data['amount'] as num).toDouble(),
          tripId: tripId,
        );
        onStatusChange?.call(PaymentStatus.qrReady);
        debugPrint('✅ QR created: ${qr.qrId}');
        return qr;
      }

      // Already paid?
      if (data['alreadyPaid'] == true) {
        onStatusChange?.call(PaymentStatus.alreadyPaid);
        return null;
      }

      throw Exception(data['message'] ?? 'QR creation failed');
    } catch (e) {
      debugPrint('❌ createQrCode error: $e');
      onStatusChange?.call(PaymentStatus.failed);
      onError?.call(e.toString());
      return null;
    } finally {
      _paymentLock = false;
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // 2) POLL QR PAYMENT STATUS  (fallback if webhook is delayed)
  //
  // Razorpay webhooks usually arrive in < 5 s on good networks.
  // If the app is in background or webhook fails, poll /api/payment/qr/status
  // every 5 s for up to 2 minutes.
  // ══════════════════════════════════════════════════════════════════════════

  void startPollingQrStatus({
    required String tripId,
    required String qrId,
    required void Function(Map<String, dynamic> result) onCaptured,
    required void Function() onTimeout,
  }) {
    _pollCount = 0;
    _pollTimer?.cancel();
    onStatusChange?.call(PaymentStatus.polling);

    _pollTimer = Timer.periodic(const Duration(seconds: 5), (timer) async {
      _pollCount++;
      if (_pollCount > _maxPolls) {
        timer.cancel();
        onTimeout();
        return;
      }

      try {
        final headers = await _authHeaders();
        final response = await http
            .get(
              Uri.parse('$_apiBase/api/payment/qr/status?tripId=$tripId&qrId=$qrId'),
              headers: headers,
            )
            .timeout(const Duration(seconds: 8));

        final data = jsonDecode(response.body) as Map<String, dynamic>;

        if (data['status'] == 'captured') {
          timer.cancel();
          onStatusChange?.call(PaymentStatus.success);
          onCaptured(data);
        }
      } catch (e) {
        debugPrint('⚠️ QR poll error (attempt $_pollCount): $e');
      }
    });
  }

  void stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
    _pollCount = 0;
  }

  // ══════════════════════════════════════════════════════════════════════════
  // 3) CASH PAYMENT CONFIRMATION  (driver side)
  //
  // Atomic flow on backend:
  //   1. findOneAndUpdate({tripId, paymentStatus:'pending'}, {status:'processing'})
  //   2. Calculate: driverAmount = fare * (1 - commissionRate)
  //   3. If wallet.balance >= commission:
  //        wallet.balance += driverAmount   (net credit)
  //      Else:
  //        wallet.balance += fare           (full credit)
  //        wallet.pendingCommission += commission
  //   4. Update payment.status = 'captured'
  //   5. Emit socket events to driver + customer
  //
  // Driver wallet is NEVER double-credited because step 1 uses atomic CAS.
  // ══════════════════════════════════════════════════════════════════════════

  Future<PaymentResult> confirmCashPayment({
    required String tripId,
    required String driverId,
    required double fareAmount,
  }) async {
    if (_paymentLock) {
      return const PaymentResult(success: false, message: 'Please wait…');
    }
    _paymentLock = true;

    try {
      final headers = await _authHeaders();
      final response = await http
          .post(
            Uri.parse('$_apiBase/api/payment/cash/confirm'),
            headers: headers,
            body: jsonEncode({
              'tripId': tripId,
              'driverId': driverId,
              'amount': fareAmount,
            }),
          )
          .timeout(const Duration(seconds: 15));

      final data = jsonDecode(response.body) as Map<String, dynamic>;

      if (response.statusCode == 200 && data['success'] == true) {
        onStatusChange?.call(PaymentStatus.success);
        onPaymentSuccess?.call(
          (data['driverAmount'] as num?)?.toDouble() ?? fareAmount,
          (data['walletBalance'] as num?)?.toDouble() ?? 0.0,
        );
        return PaymentResult(success: true, data: data);
      }

      // 409 = already processed (idempotent — treat as success)
      if (response.statusCode == 409) {
        onStatusChange?.call(PaymentStatus.alreadyPaid);
        return PaymentResult(success: true, message: 'Already confirmed', data: data);
      }

      return PaymentResult(
        success: false,
        message: data['message'] ?? 'Confirmation failed',
      );
    } catch (e) {
      debugPrint('❌ confirmCash error: $e');
      return PaymentResult(success: false, message: e.toString());
    } finally {
      _paymentLock = false;
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // 4) INITIATE CASH FROM CUSTOMER SIDE
  //    Customer taps "Pay Cash" → backend marks trip as cash_pending
  //    Driver gets socket event 'cash:payment:pending'
  // ══════════════════════════════════════════════════════════════════════════

  Future<PaymentResult> initiateCashPayment({
    required String tripId,
    required String customerId,
    required String driverId,
    required double fareAmount,
  }) async {
    if (_paymentLock) {
      return const PaymentResult(success: false, message: 'Please wait…');
    }
    _paymentLock = true;

    try {
      final headers = await _authHeaders();
      final response = await http
          .post(
            Uri.parse('$_apiBase/api/payment/cash/initiate'),
            headers: headers,
            body: jsonEncode({
              'tripId': tripId,
              'customerId': customerId,
              'driverId': driverId,
              'amount': fareAmount,
            }),
          )
          .timeout(const Duration(seconds: 15));

      final data = jsonDecode(response.body) as Map<String, dynamic>;

      if (response.statusCode == 200 && data['success'] == true) {
        return PaymentResult(success: true, data: data);
      }
      return PaymentResult(success: false, message: data['message'] ?? 'Failed');
    } catch (e) {
      return PaymentResult(success: false, message: e.toString());
    } finally {
      _paymentLock = false;
    }
  }

  void dispose() {
    stopPolling();
    _paymentLock = false;
  }
}