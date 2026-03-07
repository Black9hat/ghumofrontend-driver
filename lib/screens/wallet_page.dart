// ════════════════════════════════════════════════════════════════════════════
// 💰 FLUTTER DRIVER SIDE - lib/screens/wallet_page.dart
// Display wallet balance, earnings, and transaction history
// ════════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:drivergoo/config.dart';
import '../services/socket_service.dart';

class WalletPage extends StatefulWidget {
  final String driverId;

  const WalletPage({Key? key, required this.driverId}) : super(key: key);

  @override
  _WalletPageState createState() => _WalletPageState();
}

class _WalletPageState extends State<WalletPage> with WidgetsBindingObserver {
  final String apiBase = AppConfig.backendBaseUrl;

  Map<String, dynamic>? walletData;
  List<dynamic> transactions = [];
  List<dynamic> paymentProofs = [];
  bool isLoading = true;
  bool isProcessingPayment = false;
  String? errorMessage;

  // ✅ Auth token for API requests
  String? _authToken;

  // ✅ Track pending payment for app-resume verification
  String? _pendingPaymentId;
  String? _pendingOrderId;
  String? _pendingSignature;
  bool _paymentJustCompleted = false;

  // ✅ Socket for realtime wallet updates
  final DriverSocketService _socketService = DriverSocketService();

  // ✅ Guard against double success dialog (verify API + socket arriving simultaneously)
  bool _successDialogShowing = false;

  // ✅ Guard against calling verify twice (success handler + lifecycle resume)
  bool _verifyInProgress = false;

  late Razorpay _razorpay;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeRazorpay();
    _initializeAndFetch();
    _listenToSocketEvents();
  }

  // ✅ Use onCommissionPaid callback — reliable even before socket connects
  void _listenToSocketEvents() {
    // onCommissionPaid is registered directly in DriverSocketService.connect()
    // so it works regardless of when wallet_page initializes
    _socketService.onCommissionPaid = (data) {
      debugPrint('🔔 commission:paid received: \$data');
      if (!mounted) return;
      _fetchWalletData();
      final paidAmount = data['paidAmount'] ?? 0;
      final pendingAmount = data['pendingAmount'] ?? 0;
      if ((paidAmount as num) > 0 && !isProcessingPayment && !_successDialogShowing) {
        _showPaymentSuccessDialog(paidAmount, pendingAmount);
      }
    };

    _socketService.onPaymentFailed = (data) {
      debugPrint('❌ payment:failed received: \$data');
      if (!mounted) return;
      setState(() => isProcessingPayment = false);
      _showSnackBar(
        data['message'] ?? 'Payment failed',
        isError: true,
        icon: Icons.error,
      );
    };
  }

  // ✅ Called when app resumes from background (e.g. after UPI payment)
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Small delay — let Razorpay SDK fire EVENT_PAYMENT_SUCCESS first if it can
      // If it fires, _handlePaymentSuccess will clear _paymentJustCompleted
      Future.delayed(const Duration(milliseconds: 1500), () {
        if (!mounted) return;
        // If Razorpay already handled it, _paymentJustCompleted is false — skip
        if (_paymentJustCompleted) {
          _paymentJustCompleted = false;
          debugPrint('📱 App resumed — Razorpay event not fired, checking SharedPrefs...');
          _checkAndVerifyPendingPayment();
        }
      });
    }
  }

  // ✅ Check SharedPreferences for any pending payment on resume
  Future<void> _checkAndVerifyPendingPayment() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final pendingOrderId = prefs.getString('pending_commission_orderId');
      final pendingPaymentId = _pendingPaymentId;
      final pendingSignature = _pendingSignature;

      if (pendingPaymentId != null && pendingPaymentId.isNotEmpty &&
          pendingSignature != null && pendingSignature.isNotEmpty) {
        // We have full payment details from Razorpay success event — verify
        debugPrint('📱 Verifying from memory: $pendingPaymentId');
        _verifyPaymentWithBackend(pendingPaymentId, _pendingOrderId ?? '', pendingSignature);
        _pendingPaymentId = null;
        _pendingOrderId = null;
        _pendingSignature = null;
      } else if (pendingOrderId != null) {
        // Razorpay event didn't fire but we have an orderId — payment may have
        // been captured by webhook already. Just refresh wallet.
        debugPrint('📱 No Razorpay event received — refreshing wallet (webhook may have handled it)');
        await _clearPendingPayment();
        await _fetchWalletData();
        if (mounted) {
          _showSnackBar(
            'Checking payment status...',
            isError: false,
            icon: Icons.info_outline,
          );
        }
      }
    } catch (e) {
      debugPrint('❌ _checkAndVerifyPendingPayment error: $e');
      _fetchWalletData();
    }
  }

  Future<void> _savePendingPayment(String orderId, int amountInPaise) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('pending_commission_orderId', orderId);
      await prefs.setInt('pending_commission_amount', amountInPaise);
    } catch (e) {
      debugPrint('⚠️ Could not save pending payment: $e');
    }
  }

  Future<void> _clearPendingPayment() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('pending_commission_orderId');
      await prefs.remove('pending_commission_amount');
    } catch (e) {
      debugPrint('⚠️ Could not clear pending payment: $e');
    }
  }

  // ✅ NEW: Initialize auth and fetch data
  Future<void> _initializeAndFetch() async {
    await _loadAuthToken();
    await _fetchWalletData();
    await _fetchPaymentProofs();
    // ✅ Check if app was killed mid-payment and relaunched
    await _checkStalePendingPayment();
  }

  // Checks SharedPrefs for any payment initiated but never verified
  // e.g. app was force-killed while in GPay
  Future<void> _checkStalePendingPayment() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stalePendingOrderId = prefs.getString('pending_commission_orderId');
      if (stalePendingOrderId != null && stalePendingOrderId.isNotEmpty) {
        debugPrint('⚠️ Stale pending payment found: $stalePendingOrderId');
        // We don't have paymentId/signature (app was killed), so just refresh wallet
        // Webhook should have already updated pendingAmount on the backend
        await _clearPendingPayment();
        await _fetchWalletData();
        if (mounted) {
          _showSnackBar(
            'Checking previous payment status...',
            isError: false,
            icon: Icons.info_outline,
          );
        }
      }
    } catch (e) {
      debugPrint('⚠️ Stale payment check error: $e');
    }
  }

  // ✅ NEW: Load auth token from SharedPreferences
  Future<void> _loadAuthToken() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _authToken = prefs.getString('auth_token');
      
      // If no stored token, try Firebase
      if (_authToken == null || _authToken!.isEmpty) {
        final user = FirebaseAuth.instance.currentUser;
        if (user != null) {
          _authToken = await user.getIdToken();
        }
      }
      
      debugPrint('🔑 Auth token loaded: ${_authToken != null ? "YES" : "NO"}');
    } catch (e) {
      debugPrint('❌ Error loading auth token: $e');
    }
  }

  // ✅ NEW: Get headers with auth
  Map<String, String> _getHeaders() {
    return {
      'Content-Type': 'application/json',
      if (_authToken != null && _authToken!.isNotEmpty)
        'Authorization': 'Bearer $_authToken',
    };
  }

  void _initializeRazorpay() {
    _razorpay = Razorpay();
    _razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, _handlePaymentSuccess);
    _razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, _handlePaymentError);
    _razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, _handleExternalWallet);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // ✅ Clear callbacks to prevent memory leaks (not direct socket.off)
    _socketService.onCommissionPaid = null;
    _socketService.onPaymentFailed = null;
    _razorpay.clear();
    super.dispose();
  }

  void _handlePaymentSuccess(PaymentSuccessResponse response) {
    debugPrint('✅ Payment Success: ${response.paymentId}');

    // ✅ Store in memory for lifecycle fallback
    _pendingPaymentId = response.paymentId;
    _pendingOrderId = response.orderId;
    _pendingSignature = response.signature;
    _paymentJustCompleted = false; // Razorpay handled it — cancel lifecycle fallback

    setState(() => isProcessingPayment = true);

    _verifyPaymentWithBackend(
      response.paymentId ?? '',
      response.orderId ?? '',
      response.signature ?? '',
    );
  }

  void _handlePaymentError(PaymentFailureResponse response) {
    debugPrint('❌ Payment Error: ${response.code} - ${response.message}');

    setState(() => isProcessingPayment = false);

    String errorMessage = 'Payment failed';

    if (response.code == Razorpay.PAYMENT_CANCELLED) {
      errorMessage = 'Payment cancelled by user';
    } else if (response.code == Razorpay.NETWORK_ERROR) {
      errorMessage = 'Network error. Please check your connection';
    } else if (response.message != null) {
      errorMessage = response.message!;
    }

    _showSnackBar(errorMessage, isError: true, icon: Icons.error);
  }

  void _handleExternalWallet(ExternalWalletResponse response) {
    debugPrint('📱 External Wallet: ${response.walletName}');

    _showSnackBar(
      'Redirecting to ${response.walletName}...',
      backgroundColor: Colors.blue,
      icon: Icons.account_balance_wallet,
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 📥 FETCH WALLET DATA - FIXED
  // ═══════════════════════════════════════════════════════════════════════

  Future<void> _fetchWalletData() async {
    if (!mounted) return;
    
    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    try {
      final url = '$apiBase/api/wallet/${widget.driverId}';
      debugPrint('📡 Fetching wallet from: $url');

      final response = await http.get(
        Uri.parse(url),
        headers: _getHeaders(),
      ).timeout(const Duration(seconds: 15));

      debugPrint('📥 Wallet Response Status: ${response.statusCode}');
      debugPrint('📥 Wallet Response Body: ${response.body}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        
        if (data['success'] == true) {
          if (mounted) {
            setState(() {
              walletData = data['wallet'];
              final rawTxns = (data['recentTransactions'] ??
                               data['transactions'] ??
                               walletData?['transactions'] ??
                               []) as List<dynamic>;
              // Sort newest first so latest payments (incl. commission paid) appear at top
              rawTxns.sort((a, b) {
                try {
                  final da = DateTime.parse(a['createdAt']);
                  final db = DateTime.parse(b['createdAt']);
                  return db.compareTo(da);
                } catch (_) { return 0; }
              });
              transactions = rawTxns;
              isLoading = false;
            });
          }
          debugPrint('✅ Wallet loaded successfully');
          debugPrint('   Total Earnings: ${walletData?['totalEarnings']}');
          debugPrint('   Pending Amount: ${walletData?['pendingAmount']}');
          debugPrint('   Transactions: ${transactions.length}');
        } else {
          throw Exception(data['message'] ?? 'Failed to load wallet');
        }
      } else if (response.statusCode == 404) {
        // Wallet not found - might need to be created
        debugPrint('⚠️ Wallet not found, creating default...');
        if (mounted) {
          setState(() {
            walletData = {
              'totalEarnings': 0.0,
              'pendingAmount': 0.0,
              'totalCommission': 0.0,
              'availableBalance': 0.0,
            };
            transactions = [];
            isLoading = false;
          });
        }
      } else {
        throw Exception('Server error: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('❌ Error fetching wallet: $e');
      if (mounted) {
        setState(() {
          isLoading = false;
          errorMessage = e.toString();
          // Set default wallet data so UI doesn't break
          walletData ??= {
            'totalEarnings': 0.0,
            'pendingAmount': 0.0,
            'totalCommission': 0.0,
            'availableBalance': 0.0,
          };
        });
      }
    }
  }

  Future<void> _fetchPaymentProofs() async {
    try {
      final url = '$apiBase/api/wallet/payment-proof/${widget.driverId}';
      debugPrint('📡 Fetching payment proofs from: $url');

      final response = await http.get(
        Uri.parse(url),
        headers: _getHeaders(),
      ).timeout(const Duration(seconds: 15));

      debugPrint('📥 Payment Proofs Status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && mounted) {
          setState(() {
            paymentProofs = data['proofs'] ?? [];
          });
          debugPrint('✅ Payment proofs loaded: ${paymentProofs.length}');
        }
      }
    } catch (e) {
      debugPrint('❌ Error fetching payment proofs: $e');
      // Don't show error for payment proofs - not critical
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 🎨 BUILD UI
  // ═══════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: Text(
          'My Wallet',
          style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
        ),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              _fetchWalletData();
              _fetchPaymentProofs();
            },
          ),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : errorMessage != null && walletData == null
              ? _buildErrorWidget()
              : RefreshIndicator(
                  onRefresh: () async {
                    await _fetchWalletData();
                    await _fetchPaymentProofs();
                  },
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Show error banner if there was an error but we have cached data
                        if (errorMessage != null) _buildErrorBanner(),
                        
                        _buildWalletCard(),
                        const SizedBox(height: 24),
                        _buildStatsCards(),

                        if (paymentProofs.any((p) => p['status'] == 'pending')) ...[
                          const SizedBox(height: 24),
                          _buildPendingPaymentsSection(),
                        ],

                        const SizedBox(height: 24),
                        Text(
                          'Recent Transactions',
                          style: GoogleFonts.poppins(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 12),
                        _buildTransactionsList(),
                        
                        const SizedBox(height: 32),
                      ],
                    ),
                  ),
                ),
    );
  }

  // ✅ NEW: Error widget for complete failure
  Widget _buildErrorWidget() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'Failed to load wallet',
              style: GoogleFonts.poppins(
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              errorMessage ?? 'Unknown error',
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                fontSize: 14,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () {
                _fetchWalletData();
                _fetchPaymentProofs();
              },
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1565C0),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ✅ NEW: Error banner for partial failure
  Widget _buildErrorBanner() {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.orange.shade200),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber, color: Colors.orange.shade700, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Could not refresh data. Showing cached information.',
              style: GoogleFonts.poppins(
                fontSize: 12,
                color: Colors.orange.shade800,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            onPressed: () => setState(() => errorMessage = null),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }

  Widget _buildWalletCard() {
    final totalEarnings = _parseDouble(walletData?['totalEarnings']);
    final pendingAmount = _parseDouble(walletData?['pendingAmount']);
    final hasPendingProof = paymentProofs.any((p) => p['status'] == 'pending');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1E88E5), Color(0xFF1565C0)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.blue.withOpacity(0.3),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Total Earnings',
                style: GoogleFonts.poppins(color: Colors.white70, fontSize: 14),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'Active',
                  style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '₹${totalEarnings.toStringAsFixed(2)}',
            style: GoogleFonts.poppins(
              color: Colors.white,
              fontSize: 36,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white12,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Pending Commission',
                          style: GoogleFonts.poppins(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '₹${pendingAmount.toStringAsFixed(2)}',
                          style: GoogleFonts.poppins(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const Icon(
                      Icons.account_balance_wallet,
                      color: Colors.white70,
                      size: 40,
                    ),
                  ],
                ),

                if (pendingAmount > 0) ...[
                  const SizedBox(height: 16),
                  if (hasPendingProof || isProcessingPayment)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.orange.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.orange, width: 1),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.pending,
                            color: Colors.orange,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              isProcessingPayment
                                  ? 'Processing payment...'
                                  : 'Payment verification pending...',
                              style: GoogleFonts.poppins(
                                color: Colors.white,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () => _showPaymentBottomSheet(pendingAmount),
                        icon: const Icon(Icons.payment, size: 20),
                        label: Text(
                          'Pay ₹${pendingAmount.toStringAsFixed(2)}',
                          style: GoogleFonts.poppins(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: const Color(0xFF1565C0),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 0,
                        ),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ✅ Helper to safely parse double
  double _parseDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0.0;
    return 0.0;
  }

  void _showPaymentBottomSheet(double amount) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Pay Commission',
              style: GoogleFonts.poppins(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '₹${amount.toStringAsFixed(2)}',
              style: GoogleFonts.poppins(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: const Color(0xFF1565C0),
              ),
            ),
            const SizedBox(height: 24),

            _buildPaymentOptionButton(
              icon: Icons.account_balance,
              label: 'Pay with UPI',
              subtitle: 'Google Pay, PhonePe, Paytm & more',
              color: const Color(0xFF1565C0),
              onTap: () {
                Navigator.pop(context);
                _initiateUPIPayment(amount);
              },
            ),

            const SizedBox(height: 12),

            _buildPaymentOptionButton(
              icon: Icons.credit_card,
              label: 'Card / Net Banking',
              subtitle: 'Debit Card, Credit Card, Net Banking',
              color: Colors.purple,
              onTap: () {
                Navigator.pop(context);
                _initiateCardPayment(amount);
              },
            ),

            const SizedBox(height: 12),

            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                'Cancel',
                style: GoogleFonts.poppins(
                  color: Colors.grey[600],
                  fontSize: 16,
                ),
              ),
            ),
            SizedBox(height: MediaQuery.of(context).padding.bottom),
          ],
        ),
      ),
    );
  }

  Widget _buildPaymentOptionButton({
    required IconData icon,
    required String label,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey[300]!),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 28),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: GoogleFonts.poppins(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey[400]),
          ],
        ),
      ),
    );
  }

  Future<void> _initiateUPIPayment(double amount) async {
    setState(() => isProcessingPayment = true);

    try {
      final response = await http.post(
        Uri.parse('$apiBase/api/wallet/create-commission-order'),
        headers: _getHeaders(),
        body: jsonEncode({'driverId': widget.driverId, 'amount': amount}),
      );

      if (response.statusCode != 200) {
        throw Exception('Failed to create order');
      }

      final data = jsonDecode(response.body);
      if (!data['success']) {
        throw Exception(data['message'] ?? 'Order creation failed');
      }

      final orderId = data['orderId'];
      final amountInPaise = (amount * 100).toInt();

      // ✅ Key comes from backend - no dart-define needed
      final razorpayKey = (data['razorpayKeyId'] as String? ?? '').isNotEmpty
          ? data['razorpayKeyId'] as String
          : AppConfig.razorpayKey;
      if (razorpayKey.isEmpty) {
        throw Exception('Razorpay key not configured. Contact support.');
      }

      final userPhone = FirebaseAuth.instance.currentUser?.phoneNumber ?? '';
      // Strip +91 prefix if present — Razorpay prefill expects 10-digit number
      final phoneForPrefill = userPhone.startsWith('+91')
          ? userPhone.substring(3)
          : userPhone;

      var options = {
        'key': razorpayKey,
        'amount': amountInPaise,
        'name': 'Platform Commission',
        'order_id': orderId,
        'description': 'Commission Payment',
        'prefill': {'contact': phoneForPrefill, 'email': ''},
        'method': {
          'upi': true,
          'card': false,
          'netbanking': false,
          'wallet': false,
        },
        'config': {
          'display': {
            'blocks': {
              'utib': {
                'name': 'Pay via UPI',
                'instruments': [
                  {'method': 'upi', 'flows': ['qr', 'collect', 'intent']},
                ],
              },
            },
            'sequence': ['block.utib'],
            'preferences': {'show_default_blocks': false},
          },
        },
        'theme': {'color': '#1565C0'},
      };

      // ✅ Persist payment details to SharedPreferences BEFORE opening
      // This survives widget disposal if Android kills the activity
      await _savePendingPayment(orderId, amountInPaise);
      _paymentJustCompleted = true;
      _razorpay.open(options);
    } catch (e) {
      setState(() => isProcessingPayment = false);
      debugPrint('❌ Error initiating UPI payment: $e');
      _showSnackBar('Error: $e', isError: true);
    }
  }

  Future<void> _initiateCardPayment(double amount) async {
    setState(() => isProcessingPayment = true);

    try {
      final response = await http.post(
        Uri.parse('$apiBase/api/wallet/create-commission-order'),
        headers: _getHeaders(),
        body: jsonEncode({'driverId': widget.driverId, 'amount': amount}),
      );

      if (response.statusCode != 200) {
        throw Exception('Failed to create order');
      }

      final data = jsonDecode(response.body);
      if (!data['success']) {
        throw Exception(data['message'] ?? 'Order creation failed');
      }

      final orderId = data['orderId'];
      final amountInPaise = (amount * 100).toInt();

      final currentUser = FirebaseAuth.instance.currentUser;
      final userEmail = currentUser?.email ?? '';
      final userPhone = currentUser?.phoneNumber ?? '';

      // ✅ Key comes from backend - no dart-define needed
      final razorpayKey = (data['razorpayKeyId'] as String? ?? '').isNotEmpty
          ? data['razorpayKeyId'] as String
          : AppConfig.razorpayKey;
      if (razorpayKey.isEmpty) {
        throw Exception('Razorpay key not configured. Contact support.');
      }

      var options = {
        'key': razorpayKey,
        'amount': amountInPaise,
        'name': 'Ghumo Partner - Commission Payment',
        'order_id': orderId,
        'description': 'Commission Payment',
        'prefill': {
          'contact': userPhone.isNotEmpty ? userPhone : '',
          'email': userEmail.isNotEmpty ? userEmail : '',
        },
        'method': {
          'card': true,
          'netbanking': true,
          'wallet': true,
          'upi': true,
        },
        'theme': {'color': '#D47800'},
      };

      // ✅ Persist payment details to SharedPreferences BEFORE opening
      await _savePendingPayment(orderId, amountInPaise);
      _paymentJustCompleted = true;
      _razorpay.open(options);
    } catch (e) {
      setState(() => isProcessingPayment = false);
      debugPrint('❌ Error initiating card payment: $e');
      _showSnackBar('Error: $e', isError: true);
    }
  }

  Future<void> _verifyPaymentWithBackend(
    String paymentId,
    String orderId,
    String signature,
  ) async {
    if (!mounted) return;
    // ✅ Prevent double-verify from success handler + lifecycle resume firing together
    if (_verifyInProgress) {
      debugPrint('⚠️ Verify already in progress — skipping duplicate call');
      return;
    }
    _verifyInProgress = true;
    setState(() => isProcessingPayment = true);

    try {
      // Refresh token before verify (in case it expired while in UPI app)
      await _loadAuthToken();

      final response = await http.post(
        Uri.parse('$apiBase/api/wallet/verify-commission'),
        headers: _getHeaders(),
        body: jsonEncode({
          'driverId': widget.driverId,
          'paymentId': paymentId,
          'orderId': orderId,
          'signature': signature,
        }),
      ).timeout(const Duration(seconds: 20));

      if (!mounted) return;
      final data = jsonDecode(response.body);
      setState(() => isProcessingPayment = false);

      if (response.statusCode == 200 && data['success'] == true) {
        await _fetchWalletData();
        await _fetchPaymentProofs();

        final paidAmount = data['paidAmount'] ?? 0;
        final pendingNow = data['pendingAmount'] ?? 0;

        // ✅ Show success dialog — more visible than snackbar
        if (mounted) {
          _showPaymentSuccessDialog(paidAmount, pendingNow);
        }

        _verifyInProgress = false;
        _paymentJustCompleted = false;
        await _clearPendingPayment(); // ✅ Clear persisted pending payment
        // Poll again after 3s to catch any delayed webhook updates
        Future.delayed(const Duration(seconds: 3), () {
          if (mounted) _fetchWalletData();
        });

      } else if (data['alreadyProcessed'] == true) {
        await _fetchWalletData();
        if (mounted) {
          _showSnackBar('Commission already cleared ✅', isError: false, icon: Icons.check_circle);
        }
      } else {
        throw Exception(data['message'] ?? 'Payment verification failed');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => isProcessingPayment = false);
      _verifyInProgress = false;
      debugPrint('❌ Verification Error: $e');
      // Even on error, refresh wallet — webhook may have already updated it
      await _fetchWalletData();
      _showSnackBar('Verifying payment... Please check your wallet.', isError: false, icon: Icons.info);
    }
  }

  void _showPaymentSuccessDialog(dynamic paidAmount, dynamic pendingNow) {
    if (_successDialogShowing) return;  // ✅ Prevent duplicate dialogs
    _successDialogShowing = true;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.check_circle, color: Colors.green.shade600, size: 56),
            ),
            const SizedBox(height: 16),
            const Text(
              'Payment Successful!',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              '₹${paidAmount.toString()} commission paid',
              style: TextStyle(fontSize: 16, color: Colors.grey[700]),
            ),
            if ((pendingNow as num) > 0) ...[
              const SizedBox(height: 4),
              Text(
                'Remaining pending: ₹${pendingNow.toString()}',
                style: TextStyle(fontSize: 13, color: Colors.orange[700]),
              ),
            ] else ...[
              const SizedBox(height: 4),
              Text(
                'No pending commission 🎉',
                style: TextStyle(fontSize: 13, color: Colors.green[700]),
              ),
            ],
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  _successDialogShowing = false;
                  Navigator.of(ctx).pop();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green.shade600,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: const Text('OK', style: TextStyle(color: Colors.white, fontSize: 16)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showSnackBar(
    String message, {
    bool isError = false,
    IconData? icon,
    Color? backgroundColor,
  }) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              icon ?? (isError ? Icons.error : Icons.info),
              color: Colors.white,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(message, style: GoogleFonts.poppins(fontSize: 13)),
            ),
          ],
        ),
        backgroundColor:
            backgroundColor ?? (isError ? Colors.red : Colors.green),
        duration: const Duration(seconds: 4),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Widget _buildPendingPaymentsSection() {
    final pending = paymentProofs
        .where((p) => p['status'] == 'pending')
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Pending Verifications',
          style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        ...pending.map((proof) {
          final amount = _parseDouble(proof['amount']);
          final transactionId =
              proof['razorpayPaymentId'] ?? proof['upiTransactionId'] ?? '';
          
          DateTime? submittedAt;
          try {
            submittedAt = DateTime.parse(proof['submittedAt']).toLocal();
          } catch (_) {}

          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.orange.withOpacity(0.3)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.pending,
                    color: Colors.orange,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Payment of ₹${amount.toStringAsFixed(2)}',
                        style: GoogleFonts.poppins(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Txn: $transactionId',
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                      ),
                      if (submittedAt != null)
                        Text(
                          'Submitted: ${submittedAt.day}/${submittedAt.month}/${submittedAt.year}',
                          style: GoogleFonts.poppins(
                            fontSize: 11,
                            color: Colors.grey[500],
                          ),
                        ),
                    ],
                  ),
                ),
                Text(
                  'PENDING',
                  style: GoogleFonts.poppins(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Colors.orange,
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ],
    );
  }

  Widget _buildStatsCards() {
    final totalCommission = _parseDouble(walletData?['totalCommission']);
    final totalEarnings = _parseDouble(walletData?['totalEarnings']);

    return Row(
      children: [
        Expanded(
          child: _buildStatCard(
            'Total Commission',
            '₹${totalCommission.toStringAsFixed(2)}',
            Icons.payments,
            Colors.orange,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildStatCard(
            'Net Earnings',
            '₹${totalEarnings.toStringAsFixed(2)}',
            Icons.trending_up,
            Colors.green,
          ),
        ),
      ],
    );
  }

  Widget _buildStatCard(
    String title,
    String value,
    IconData icon,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 30),
          const SizedBox(height: 12),
          Text(
            title,
            style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey[600]),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: GoogleFonts.poppins(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }


  // ── Copyable chip for payment IDs ──────────────────────────────────────
  Widget _buildDetailChip(
    IconData icon, String label, String value, Color color, {bool copyable = false}
  ) {
    return Row(
      children: [
        Icon(icon, size: 12, color: color.withOpacity(0.7)),
        const SizedBox(width: 5),
        Text(
          '$label: ',
          style: GoogleFonts.poppins(fontSize: 10, color: Colors.grey[500]),
        ),
        Expanded(
          child: Text(
            value,
            style: GoogleFonts.poppins(
              fontSize: 10, fontWeight: FontWeight.w600, color: color,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (copyable)
          GestureDetector(
            onTap: () {
              _showSnackBar('Copied: $value', isError: false, icon: Icons.copy);
            },
            child: Icon(Icons.copy, size: 12, color: Colors.grey[400]),
          ),
      ],
    );
  }

  // ── Full transaction detail bottom sheet ───────────────────────────────
  void _showTransactionDetail(Map<String, dynamic> txn) {
    final type          = txn['type']?.toString() ?? 'credit';
    final amount        = _parseDouble(txn['amount']);
    final description   = txn['description']?.toString() ?? '';
    final razorpayPaymentId = txn['razorpayPaymentId']?.toString();
    final razorpayOrderId   = txn['razorpayOrderId']?.toString();
    final paymentMethod     = txn['paymentMethod']?.toString();
    final status            = txn['status']?.toString() ?? 'completed';
    final tripId            = txn['tripId']?.toString();

    DateTime? date;
    try { date = DateTime.parse(txn['createdAt']).toLocal(); } catch (_) {}

    final Color color = type == 'credit'
        ? Colors.green
        : type == 'commission'
            ? Colors.orange
            : Colors.red;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    type == 'credit' ? Icons.arrow_downward
                        : type == 'commission' ? Icons.percent
                        : Icons.arrow_upward,
                    color: color,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        description,
                        style: GoogleFonts.poppins(
                          fontSize: 15, fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (date != null)
                        Text(
                          '${date.day}/${date.month}/${date.year}  ${date.hour}:${date.minute.toString().padLeft(2, '0')}',
                          style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey[500]),
                        ),
                    ],
                  ),
                ),
                Text(
                  '${(type == 'debit' || type == 'commission') ? '-' : '+'}\u20b9${amount.toStringAsFixed(2)}',
                  style: GoogleFonts.poppins(
                    fontSize: 20, fontWeight: FontWeight.w800, color: color,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            const Divider(),
            const SizedBox(height: 12),
            Text(
              'PAYMENT DETAILS',
              style: GoogleFonts.poppins(
                fontSize: 10, fontWeight: FontWeight.w700,
                color: Colors.grey[400], letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 10),
            _detailRow('Status', status.toUpperCase(), color: color),
            if (paymentMethod != null && paymentMethod != 'unknown')
              _detailRow('Payment Method', paymentMethod.toUpperCase()),
            if (razorpayPaymentId != null)
              _detailRow('Payment ID (UPI Ref)', razorpayPaymentId, copyable: true),
            if (razorpayOrderId != null)
              _detailRow('Order ID', razorpayOrderId, copyable: true),
            if (tripId != null)
              _detailRow('Trip ID', tripId, copyable: true),
            _detailRow('Type', type.toUpperCase()),
            if (date != null)
              _detailRow('Date & Time',
                '${date.day}/${date.month}/${date.year}  ${date.hour}:${date.minute.toString().padLeft(2, '0')}'
              ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value, {Color? color, bool copyable = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 150,
            child: Text(
              label,
              style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey[500]),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: GoogleFonts.poppins(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: color ?? Colors.black87,
              ),
            ),
          ),
          if (copyable)
            GestureDetector(
              onTap: () => _showSnackBar('Copied: $value', isError: false, icon: Icons.copy),
              child: Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Icon(Icons.copy, size: 14, color: Colors.grey[400]),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTransactionsList() {
    if (transactions.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(40),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Center(
          child: Column(
            children: [
              Icon(Icons.receipt_long, size: 64, color: Colors.grey[300]),
              const SizedBox(height: 16),
              Text(
                'No transactions yet',
                style: GoogleFonts.poppins(
                  color: Colors.grey[500],
                  fontSize: 16,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: transactions.map((transaction) {
        final type = transaction['type']?.toString() ?? 'credit';
        final amount = _parseDouble(transaction['amount']);
        final description = transaction['description']?.toString() ?? '';
        
        DateTime? date;
        try {
          date = DateTime.parse(transaction['createdAt']).toLocal();
        } catch (_) {}

        IconData icon;
        Color color;
        String prefix;

        if (type == 'credit') {
          icon = Icons.arrow_downward;
          color = Colors.green;
          prefix = '+';
        } else if (type == 'commission') {
          icon = Icons.percent;
          color = Colors.orange;
          prefix = '-';
        } else {
          icon = Icons.arrow_upward;
          color = Colors.red;
          prefix = '-';
        }

        // ── Payment detail fields ────────────────────────────────
        final razorpayPaymentId = transaction['razorpayPaymentId']?.toString();
        final razorpayOrderId   = transaction['razorpayOrderId']?.toString();
        final paymentMethod     = transaction['paymentMethod']?.toString();
        final status            = transaction['status']?.toString() ?? 'completed';

        // Derive UPI Ref Number from paymentId (pay_XXXXX)
        final upiRef = razorpayPaymentId != null && razorpayPaymentId.startsWith('pay_')
            ? razorpayPaymentId
            : null;

        return GestureDetector(
          onTap: () => _showTransactionDetail(transaction),
          child: Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: color.withOpacity(0.15)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 5,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(icon, color: color, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            description,
                            style: GoogleFonts.poppins(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 2),
                          if (date != null)
                            Text(
                              '${date.day}/${date.month}/${date.year}  ${date.hour}:${date.minute.toString().padLeft(2, '0')}',
                              style: GoogleFonts.poppins(
                                fontSize: 11,
                                color: Colors.grey[500],
                              ),
                            ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '$prefix₹${amount.toStringAsFixed(2)}',
                          style: GoogleFonts.poppins(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: color,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: status == 'completed'
                                ? Colors.green.withOpacity(0.1)
                                : Colors.orange.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            status.toUpperCase(),
                            style: GoogleFonts.poppins(
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              color: status == 'completed' ? Colors.green[700] : Colors.orange[700],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                // ── Payment details strip ──────────────────────────
                if (upiRef != null || paymentMethod != null || razorpayOrderId != null) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.grey[50],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey[200]!),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (paymentMethod != null && paymentMethod != 'unknown')
                          _buildDetailChip(
                            Icons.credit_card,
                            'Method',
                            paymentMethod.toUpperCase(),
                            Colors.blue,
                          ),
                        if (upiRef != null) ...[
                          const SizedBox(height: 4),
                          _buildDetailChip(
                            Icons.receipt_long,
                            'Payment ID',
                            upiRef,
                            Colors.purple,
                            copyable: true,
                          ),
                        ],
                        if (razorpayOrderId != null) ...[
                          const SizedBox(height: 4),
                          _buildDetailChip(
                            Icons.tag,
                            'Order ID',
                            razorpayOrderId,
                            Colors.teal,
                            copyable: true,
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}