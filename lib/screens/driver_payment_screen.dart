// lib/screens/driver_payment_screen.dart
//
// ═══════════════════════════════════════════════════════════════════════════════
// DRIVER PAYMENT SCREEN
// ─────────────────────────────────────────────────────────────────────────────
// This screen is shown to the DRIVER after a trip completes.
//
// Two payment paths:
//
//  PATH A — QR / UPI  (recommended)
//  ─────────────────────────────────
//  1. Driver taps "Generate QR"
//  2. Backend creates Razorpay QR Code (see PaymentService.createQrCode)
//  3. Screen shows QR image — customer scans with GPay / PhonePe / Paytm
//  4. Razorpay webhook hits backend → backend emits socket 'payment:received'
//  5. Screen auto-updates to "Payment Received" with wallet balance
//  6. If webhook is late: polling every 5 s (up to 2 min) as fallback
//
//  PATH B — Cash
//  ─────────────
//  1. Customer taps "Pay Cash" in *their* app → emits socket 'cash:payment:pending'
//     — OR —
//     Driver taps "Customer will pay cash" below
//  2. After collecting cash, driver taps "Confirm Cash Received"
//  3. Backend atomically:
//       • Deducts commission from wallet (or adds to pendingCommission)
//       • Credits net amount to wallet
//       • Emits 'payment:confirmed' to customer socket room
//  4. Screen shows breakdown + updated wallet balance
// ═══════════════════════════════════════════════════════════════════════════════

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/payment_service.dart';
import '../services/socket_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Widget
// ─────────────────────────────────────────────────────────────────────────────

class DriverPaymentScreen extends StatefulWidget {
  final String tripId;
  final String driverId;
  final double fareAmount;
  final Map<String, dynamic> tripDetails;

  /// Called after payment is fully confirmed so the dashboard can reset state.
  final VoidCallback onPaymentConfirmed;

  const DriverPaymentScreen({
    Key? key,
    required this.tripId,
    required this.driverId,
    required this.fareAmount,
    required this.tripDetails,
    required this.onPaymentConfirmed,
  }) : super(key: key);

  @override
  State<DriverPaymentScreen> createState() => _DriverPaymentScreenState();
}

class _DriverPaymentScreenState extends State<DriverPaymentScreen>
    with SingleTickerProviderStateMixin {
  // ── Services ───────────────────────────────────────────────────────────────
  final _paymentService = PaymentService();

  // ── State ──────────────────────────────────────────────────────────────────
  PaymentStatus _status = PaymentStatus.idle;
  String? _qrCodeUrl;
  String? _qrId;
  bool _cashSelected = false;
  bool _isBusy = false;

  double? _receivedAmount;
  double? _walletBalance;
  double? _commission;
  double? _pendingCommission;

  String? _errorMessage;

  late AnimationController _pulseController;
  late Animation<double> _pulseAnim;

  // ─────────────────────────────────────────────────────────────────────────
  // Lifecycle
  // ─────────────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();

    _pulseController =
        AnimationController(duration: const Duration(seconds: 1), vsync: this)
          ..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _wirePaymentService();
    _wireSocketEvents();
  }

  void _wirePaymentService() {
    _paymentService.onStatusChange = (s) {
      if (!mounted) return;
      setState(() => _status = s);
    };

    _paymentService.onPaymentSuccess = (driverAmount, walletBalance) {
      if (!mounted) return;
      setState(() {
        _receivedAmount = driverAmount;
        _walletBalance = walletBalance;
      });
    };

    _paymentService.onError = (msg) {
      if (!mounted) return;
      setState(() => _errorMessage = msg);
    };
  }

  void _wireSocketEvents() {
    final socket = DriverSocketService();

    // ── Razorpay webhook confirmed (backend re-broadcasts via socket) ─────
    socket.socket?.on('payment:received', (data) {
      if (!mounted) return;
      if (data['tripId'] != widget.tripId) return;
      debugPrint('✅ Driver socket: payment:received $data');

      _paymentService.stopPolling();
      setState(() {
        _status = PaymentStatus.success;
        _receivedAmount = (data['driverAmount'] as num?)?.toDouble();
        _walletBalance = (data['walletBalance'] as num?)?.toDouble();
        _commission = (data['commission'] as num?)?.toDouble();
        _pendingCommission = (data['pendingCommission'] as num?)?.toDouble();
      });
      _showSuccessDialog();
    });

    // ── Customer selected cash in their app ───────────────────────────────
    socket.socket?.on('cash:payment:pending', (data) {
      if (!mounted) return;
      if (data['tripId'] != widget.tripId) return;
      debugPrint('💵 Driver socket: cash:payment:pending $data');
      setState(() => _cashSelected = true);
    });

    // ── Payment confirmed (after cash or webhook) ─────────────────────────
    socket.socket?.on('payment:confirmed', (data) {
      if (!mounted) return;
      if (data['tripId'] != widget.tripId) return;
      setState(() {
        _status = PaymentStatus.success;
        _walletBalance = (data['walletBalance'] as num?)?.toDouble();
      });
    });

    // ── Payment failed ────────────────────────────────────────────────────
    socket.socket?.on('payment:failed', (data) {
      if (!mounted) return;
      if (data['tripId'] != widget.tripId) return;
      setState(() {
        _status = PaymentStatus.failed;
        _errorMessage = data['message'] ?? 'Payment failed';
      });
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _paymentService.stopPolling();
    _paymentService.onStatusChange = null;
    _paymentService.onPaymentSuccess = null;
    _paymentService.onError = null;

    final socket = DriverSocketService();
    socket.socket?.off('payment:received');
    socket.socket?.off('cash:payment:pending');
    socket.socket?.off('payment:confirmed');
    socket.socket?.off('payment:failed');
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Actions
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _generateQr() async {
    setState(() {
      _isBusy = true;
      _errorMessage = null;
    });

    final qr = await _paymentService.createQrCode(
      tripId: widget.tripId,
      driverId: widget.driverId,
      fareAmount: widget.fareAmount,
    );

    if (!mounted) return;

    if (qr != null) {
      setState(() {
        _qrCodeUrl = qr.qrCodeUrl;
        _qrId = qr.qrId;
        _isBusy = false;
      });
      _startPolling(qr.qrId);
    } else {
      setState(() => _isBusy = false);
    }
  }

  void _startPolling(String qrId) {
    _paymentService.startPollingQrStatus(
      tripId: widget.tripId,
      qrId: qrId,
      onCaptured: (result) {
        if (!mounted) return;
        setState(() {
          _receivedAmount = (result['driverAmount'] as num?)?.toDouble();
          _walletBalance = (result['walletBalance'] as num?)?.toDouble();
          _commission = (result['commission'] as num?)?.toDouble();
        });
        _showSuccessDialog();
      },
      onTimeout: () {
        if (!mounted) return;
        setState(() => _errorMessage = 'Payment not received yet. Ask customer to retry or pay cash.');
      },
    );
  }

  Future<void> _confirmCash() async {
    if (_isBusy) return;
    setState(() {
      _isBusy = true;
      _errorMessage = null;
    });

    final result = await _paymentService.confirmCashPayment(
      tripId: widget.tripId,
      driverId: widget.driverId,
      fareAmount: widget.fareAmount,
    );

    if (!mounted) return;
    setState(() => _isBusy = false);

    if (result.success) {
      final d = result.data ?? {};
      setState(() {
        _receivedAmount = (d['driverAmount'] as num?)?.toDouble();
        _walletBalance = (d['walletBalance'] as num?)?.toDouble();
        _commission = (d['commission'] as num?)?.toDouble();
        _pendingCommission = (d['pendingAmount'] as num?)?.toDouble();
      });
      _showCashConfirmedDialog();
    } else {
      setState(() => _errorMessage = result.message ?? 'Failed to confirm');
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // UI
  // ─────────────────────────────────────────────────────────────────────────

  static const _orange = Color(0xFFB85F00);

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        // Only allow back once payment is done or if truly idle
        if (_status == PaymentStatus.success ||
            _status == PaymentStatus.alreadyPaid ||
            _status == PaymentStatus.idle) {
          return true;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please complete or confirm payment first')),
        );
        return false;
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: _orange,
          title: Text(
            'Collect Payment',
            style: GoogleFonts.plusJakartaSans(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
          automaticallyImplyLeading:
              _status == PaymentStatus.success || _status == PaymentStatus.idle,
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildFareCard(),
              const SizedBox(height: 20),

              // ── Success state ──────────────────────────────────────────
              if (_status == PaymentStatus.success ||
                  _status == PaymentStatus.alreadyPaid) ...[
                _buildSuccessCard(),
                const SizedBox(height: 20),
                _buildContinueButton(),
              ]

              // ── QR shown / polling ─────────────────────────────────────
              else if (_qrCodeUrl != null) ...[
                _buildQrCard(),
                const SizedBox(height: 16),
                if (_status == PaymentStatus.polling)
                  _buildPollingIndicator(),
                const SizedBox(height: 16),
                _buildCashDivider(),
                const SizedBox(height: 16),
                _buildCashConfirmButton(),
              ]

              // ── Idle: show both options ────────────────────────────────
              else ...[
                if (_errorMessage != null) ...[
                  _buildErrorCard(),
                  const SizedBox(height: 16),
                ],
                _buildGenerateQrButton(),
                const SizedBox(height: 16),
                _buildCashDivider(),
                const SizedBox(height: 16),
                if (_cashSelected)
                  _buildCashPendingBanner(),
                _buildCashConfirmButton(),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ── Fare Card ────────────────────────────────────────────────────────────

  Widget _buildFareCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFB85F00), Color(0xFF8B4513)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: _orange.withOpacity(0.35),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          Text(
            'Collect from Customer',
            style: GoogleFonts.plusJakartaSans(color: Colors.white70, fontSize: 13),
          ),
          const SizedBox(height: 6),
          Text(
            '₹${widget.fareAmount.toStringAsFixed(2)}',
            style: GoogleFonts.plusJakartaSans(
              color: Colors.white,
              fontSize: 44,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Trip: ${widget.tripId.substring(0, 8)}…',
            style: GoogleFonts.plusJakartaSans(color: Colors.white60, fontSize: 11),
          ),
        ],
      ),
    );
  }

  // ── Generate QR Button ───────────────────────────────────────────────────

  Widget _buildGenerateQrButton() {
    return ElevatedButton.icon(
      onPressed: _isBusy ? null : _generateQr,
      style: ElevatedButton.styleFrom(
        backgroundColor: _orange,
        padding: const EdgeInsets.symmetric(vertical: 18),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        elevation: 3,
      ),
      icon: _isBusy
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
            )
          : const Icon(Icons.qr_code_2, color: Colors.white, size: 26),
      label: Text(
        _isBusy ? 'Generating QR…' : 'Show QR for Customer to Scan',
        style: GoogleFonts.plusJakartaSans(
          color: Colors.white,
          fontSize: 15,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  // ── QR Code Card ─────────────────────────────────────────────────────────
  // Shows Razorpay-hosted QR image — customer scans with any UPI app.
  // No Razorpay SDK needed on driver side for UPI QR flow.

  Widget _buildQrCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _orange.withOpacity(0.3), width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.shade200,
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Text(
            'Show this QR to Customer',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: _orange,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Customer scans with GPay / PhonePe / Paytm',
            style: GoogleFonts.plusJakartaSans(fontSize: 12, color: Colors.grey[600]),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),

          // ── QR Image (loaded from Razorpay CDN) ──
          ScaleTransition(
            scale: _pulseAnim,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _orange.withOpacity(0.2), width: 3),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.network(
                  _qrCodeUrl!,
                  width: 220,
                  height: 220,
                  fit: BoxFit.contain,
                  loadingBuilder: (ctx, child, progress) {
                    if (progress == null) return child;
                    return const SizedBox(
                      width: 220,
                      height: 220,
                      child: Center(child: CircularProgressIndicator()),
                    );
                  },
                  errorBuilder: (ctx, err, _) => const SizedBox(
                    width: 220,
                    height: 220,
                    child: Center(
                      child: Icon(Icons.broken_image_outlined, size: 60, color: Colors.grey),
                    ),
                  ),
                ),
              ),
            ),
          ),

          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: _orange.withOpacity(0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.currency_rupee, color: Color(0xFFB85F00), size: 18),
                Text(
                  '${widget.fareAmount.toStringAsFixed(2)}',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: _orange,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Polling Indicator ────────────────────────────────────────────────────

  Widget _buildPollingIndicator() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(color: Color(0xFFB85F00), strokeWidth: 2),
        ),
        const SizedBox(width: 10),
        Text(
          'Waiting for payment…',
          style: GoogleFonts.plusJakartaSans(color: Colors.grey[700], fontSize: 13),
        ),
      ],
    );
  }

  // ── Divider ──────────────────────────────────────────────────────────────

  Widget _buildCashDivider() {
    return Row(
      children: [
        const Expanded(child: Divider()),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            'OR',
            style: GoogleFonts.plusJakartaSans(
              color: Colors.grey[500],
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const Expanded(child: Divider()),
      ],
    );
  }

  // ── Cash Pending Banner ───────────────────────────────────────────────────

  Widget _buildCashPendingBanner() {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.amber.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.amber.shade300),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, color: Colors.amber.shade800, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Customer has selected cash payment — collect ₹${widget.fareAmount.toStringAsFixed(2)} and confirm below.',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                color: Colors.amber.shade900,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Confirm Cash Button ───────────────────────────────────────────────────

  Widget _buildCashConfirmButton() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.amber.shade50,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.amber.shade200),
          ),
          child: Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.amber.shade800, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Tap below ONLY after receiving cash',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    color: Colors.amber.shade900,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _isBusy ? null : _confirmCash,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green.shade600,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            icon: _isBusy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                  )
                : const Icon(Icons.check_circle, color: Colors.white),
            label: Text(
              _isBusy ? 'Confirming…' : 'Cash Received — Confirm',
              style: GoogleFonts.plusJakartaSans(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ── Success Card ─────────────────────────────────────────────────────────

  Widget _buildSuccessCard() {
    final comm = _commission;
    final pending = _pendingCommission;
    final received = _receivedAmount ?? widget.fareAmount;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.green.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.green.shade200),
      ),
      child: Column(
        children: [
          Icon(Icons.check_circle, color: Colors.green.shade600, size: 64),
          const SizedBox(height: 12),
          Text(
            'Payment Received! 🎉',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: Colors.green.shade700,
            ),
          ),
          const SizedBox(height: 16),

          // ── Breakdown ─────────────────────────────────────────────────
          _row('Collected from Customer', widget.fareAmount),
          if (comm != null && comm > 0)
            _row('Platform Commission (20%)', comm, isDeduction: true),
          const Divider(height: 24),
          _row('Added to Wallet', received, isBold: true),

          if (_walletBalance != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.green.shade100,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Wallet Balance',
                      style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600)),
                  Text(
                    '₹${_walletBalance!.toStringAsFixed(2)}',
                    style: GoogleFonts.plusJakartaSans(
                      fontWeight: FontWeight.w800,
                      color: Colors.green.shade800,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            ),
          ],

          if (pending != null && pending > 0) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.schedule, color: Colors.orange.shade700, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Pending commission: ₹${pending.toStringAsFixed(2)} — will be deducted from future earnings.',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        color: Colors.orange.shade800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _row(String label, double amount,
      {bool isDeduction = false, bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: GoogleFonts.plusJakartaSans(
              fontSize: isBold ? 15 : 14,
              fontWeight: isBold ? FontWeight.w700 : FontWeight.w400,
            ),
          ),
          Text(
            '${isDeduction ? '−' : ''}₹${amount.toStringAsFixed(2)}',
            style: GoogleFonts.plusJakartaSans(
              fontSize: isBold ? 16 : 14,
              fontWeight: isBold ? FontWeight.w800 : FontWeight.w500,
              color: isDeduction ? Colors.red.shade700 : null,
            ),
          ),
        ],
      ),
    );
  }

  // ── Error Card ────────────────────────────────────────────────────────────

  Widget _buildErrorCard() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.red.shade200),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: Colors.red.shade700, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _errorMessage!,
              style: GoogleFonts.plusJakartaSans(
                color: Colors.red.shade700,
                fontSize: 13,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            onPressed: () => setState(() => _errorMessage = null),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }

  // ── Continue Button ───────────────────────────────────────────────────────

  Widget _buildContinueButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: () {
          widget.onPaymentConfirmed();
          Navigator.of(context).pop();
        },
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.green.shade600,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        child: Text(
          'Done — Back to Dashboard',
          style: GoogleFonts.plusJakartaSans(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: 15,
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Dialogs
  // ─────────────────────────────────────────────────────────────────────────

  void _showSuccessDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle, color: Colors.green.shade600, size: 70),
            const SizedBox(height: 12),
            Text(
              'Payment Confirmed!',
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 20, fontWeight: FontWeight.w700),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              '₹${(_receivedAmount ?? widget.fareAmount).toStringAsFixed(2)} added to wallet',
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 15, color: Colors.grey[700]),
              textAlign: TextAlign.center,
            ),
            if (_walletBalance != null) ...[
              const SizedBox(height: 8),
              Text(
                'Balance: ₹${_walletBalance!.toStringAsFixed(2)}',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Colors.green.shade700,
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showCashConfirmedDialog() {
    _showSuccessDialog(); // reuse same dialog, data already set in state
  }
}