// lib/screens/driver_payment_screen.dart
// ════════════════════════════════════════════════════════════════════════════════
// DRIVER PAYMENT SCREEN - UPDATED BEHAVIOR
// ────────────────────────────────────────────────────────────────────────────────
// 
// CHANGES FROM PREVIOUS:
// ✅ "Back to Dashboard" → "Ready for Next Ride" button (primary action)
// ✅ Remove wallet balance display from success card
// ✅ Cash collection confirmed → show "Payment Confirmed" dialog
// ✅ After dialog dismiss → auto-exit to dashboard
// ✅ Keep all payment path logic (QR + Cash)
//
// FLOW:
// 1. Driver completes trip → payment screen shown
// 2. Driver chooses QR or Cash
// 3. For CASH: driver collects cash → taps "Confirm Cash Received"
// 4. Backend processes & emits payment:confirmed socket
// 5. Screen shows success card with breakdown
// 6. Driver taps "Ready for Next Ride" → exits to dashboard
// ════════════════════════════════════════════════════════════════════════════════

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/payment_service.dart';  // ✅ Imports PaymentStatus enum
import '../services/socket_service.dart';

// ✅ DO NOT DEFINE PaymentStatus HERE
// It's imported from payment_service.dart above

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
  double? _commission;
  double? _pendingCommission;  double? _incentiveAmount;          // ✅ NEW: Incentive earned
  int? _incentiveCoins;             // ✅ NEW: Coins from incentive
  double? _incentiveMultiplier;     // ✅ NEW: Plan multiplier applied
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
        _commission = (data['commission'] as num?)?.toDouble();
        _pendingCommission = (data['pendingCommission'] as num?)?.toDouble();
        // ✅ NEW: Extract incentive data from response
        final incentive = data['incentive'] as Map<String, dynamic>?;
        if (incentive != null) {
          _incentiveAmount = (incentive['amount'] as num?)?.toDouble();
          _incentiveCoins = (incentive['coins'] as num?)?.toInt();
          _incentiveMultiplier = (incentive['multiplier'] as num?)?.toDouble();
        }
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

    // ── Payment confirmed (after cash collection) ────────────────────────
    socket.socket?.on('payment:confirmed', (data) {
      if (!mounted) return;
      if (data['tripId'] != widget.tripId) return;
      debugPrint('✅ Driver socket: payment:confirmed $data');
      setState(() {
        _status = PaymentStatus.success;
        _receivedAmount = (data['driverAmount'] as num?)?.toDouble();
        _commission = (data['commission'] as num?)?.toDouble();
        // ✅ NEW: Extract incentive data from cash collection response
        final incentive = data['incentive'] as Map<String, dynamic>?;
        if (incentive != null) {
          _incentiveAmount = (incentive['amount'] as num?)?.toDouble();
          _incentiveCoins = (incentive['coins'] as num?)?.toInt();
          _incentiveMultiplier = (incentive['multiplier'] as num?)?.toDouble();
        }
      });
      _showSuccessDialog();
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
          _commission = (result['commission'] as num?)?.toDouble();
        });
        _showSuccessDialog();
      },
      onTimeout: () {
        if (!mounted) return;
        setState(() => _errorMessage = 'QR scan timeout — please try again or collect cash manually');
      },
    );
  }

  /// ✅ Call confirmCashPayment (matches the actual method name in payment_service.dart)
  Future<void> _confirmCashCollection() async {
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
      setState(() {
        _status = PaymentStatus.success;
        _receivedAmount = (result.data?['driverAmount'] as num?)?.toDouble() ?? widget.fareAmount;
        _commission = (result.data?['commission'] as num?)?.toDouble();
      });
      _showSuccessDialog();
    } else {
      setState(() => _errorMessage = result.message ?? 'Failed to confirm cash collection');
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: const Color(0xFFB85F00),
        title: Text(
          'Payment Confirmation',
          style: GoogleFonts.plusJakartaSans(
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildFareCard(),
            const SizedBox(height: 24),

            if (_status == PaymentStatus.success) ...[
              _buildSuccessCard(),
              const SizedBox(height: 20),
              _buildContinueButton(),
            ] else if (_status == PaymentStatus.failed) ...[
              _buildErrorCard(),
              const SizedBox(height: 20),
              _buildRetryButton(),
            ] else ...[
              if (_errorMessage != null) ...[
                _buildErrorCard(),
                const SizedBox(height: 16),
              ],
              _buildPaymentOptions(),
            ],
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Widgets
  // ─────────────────────────────────────────────────────────────────────────

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
            color: const Color(0xFFB85F00).withOpacity(0.3),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          Text(
            'Trip Fare',
            style: GoogleFonts.plusJakartaSans(
              color: Colors.white70,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '₹${widget.fareAmount.toStringAsFixed(2)}',
            style: GoogleFonts.plusJakartaSans(
              color: Colors.white,
              fontSize: 40,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              'Trip: ${widget.tripId.substring(0, 8)}…',
              style: GoogleFonts.plusJakartaSans(
                color: Colors.white,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentOptions() {
    return Column(
      children: [
        // ── QR Payment Option ─────────────────────────────────────────
        _buildPaymentOption(
          icon: Icons.qr_code_2,
          title: 'Generate QR Code',
          subtitle: 'Customer scans with GPay, PhonePe, or Paytm',
          color: Colors.blue.shade700,
          onTap: _isBusy ? null : _generateQr,
        ),
        const SizedBox(height: 12),

        // ── Cash Payment Option ───────────────────────────────────────
        _buildPaymentOption(
          icon: Icons.currency_rupee,
          title: 'Collect Cash',
          subtitle: 'Customer will pay cash — confirm after collection',
          color: Colors.green.shade700,
          onTap: _isBusy ? null : _confirmCashCollection,
        ),

        if (_isBusy) ...[
          const SizedBox(height: 24),
          const Center(
            child: CircularProgressIndicator(color: Color(0xFFB85F00)),
          ),
          const SizedBox(height: 8),
          Text(
            'Processing…',
            textAlign: TextAlign.center,
            style: GoogleFonts.plusJakartaSans(
              color: Colors.grey[600],
              fontSize: 13,
            ),
          ),
        ],

        // ── QR Code Display ──────────────────────────────────────────
        if (_qrCodeUrl != null) ...[
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.blue.shade200),
            ),
            child: Column(
              children: [
                Text(
                  'Customer Scan',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.blue.shade800,
                  ),
                ),
                const SizedBox(height: 12),
                Image.network(
                  _qrCodeUrl!,
                  height: 250,
                  width: 250,
                  errorBuilder: (ctx, err, st) => const Text('QR load failed'),
                ),
                const SizedBox(height: 12),
                Text(
                  'Waiting for payment…',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    color: Colors.blue.shade700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildPaymentOption({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    VoidCallback? onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade200),
            boxShadow: [
              BoxShadow(
                color: Colors.grey.shade100,
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: Colors.grey[400]),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSuccessCard() {
    final comm = _commission;
    final received = _receivedAmount ?? widget.fareAmount;
    final incentive = _incentiveAmount ?? 0.0;
    final totalWithIncentive = received + incentive;

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
            _row('Platform Commission', comm, isDeduction: true),
          const Divider(height: 24),
          _row('Fare Earnings', received, isBold: true),
          // ✅ NEW: Show incentive if awarded
          if (incentive > 0) ...[_row('Incentive Bonus', incentive, isIncentive: true)],
          if (incentive > 0) const Divider(height: 24),
          _row('Total Earnings', totalWithIncentive > 0 ? totalWithIncentive : received, isBold: true),

          if (_pendingCommission != null && _pendingCommission! > 0) ...[
            const SizedBox(height: 12),
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
                      'Pending commission: ₹${_pendingCommission!.toStringAsFixed(2)}',
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
      {bool isDeduction = false, bool isBold = false, bool isIncentive = false}) {
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
              color: isDeduction ? Colors.red.shade700 : isIncentive ? Colors.orange.shade700 : null,
            ),
          ),
        ],
      ),
    );
  }

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

  // ✅ UPDATED: "Ready for Next Ride" instead of "Back to Dashboard"
  // ✅ REMOVED: Wallet balance display
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
          'Ready for Next Ride',
          style: GoogleFonts.plusJakartaSans(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: 15,
          ),
        ),
      ),
    );
  }

  Widget _buildRetryButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: () => setState(() => _status = PaymentStatus.idle),
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFFB85F00),
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        child: Text(
          'Try Again',
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
              '₹${(_receivedAmount ?? widget.fareAmount).toStringAsFixed(2)} earned',
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 15, color: Colors.grey[700]),
              textAlign: TextAlign.center,
            ),
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
}