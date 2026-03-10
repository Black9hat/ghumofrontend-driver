// lib/screens/IncentivesPage.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import 'package:drivergoo/config.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Color Palette (matches existing app theme)
// ─────────────────────────────────────────────────────────────────────────────
class _AppColors {
  static const Color background = Color(0xFFFFFFFF);
  static const Color surface = Color(0xFFF8F9FA);
  static const Color cardBackground = Color(0xFFFFFFFF);
  static const Color onSurface = Color(0xFF1A1A1A);
  static const Color onSurfaceSecondary = Color(0xFF4A4A4A);
  static const Color onSurfaceTertiary = Color(0xFF8A8A8A);
  static const Color primary = Color(0xFFB85F00);
  static const Color primaryLight = Color(0xFFFFF3E8);
  static const Color onPrimary = Color(0xFFFFFFFF);
  static const Color divider = Color(0xFFE8E8E8);
  static const Color success = Color(0xFF2E7D32);
  static const Color successLight = Color(0xFFE8F5E9);
  static const Color error = Color(0xFFD32F2F);
}

// ─────────────────────────────────────────────────────────────────────────────
// Models
// ─────────────────────────────────────────────────────────────────────────────

class AvailablePlan {
  final String id;
  final String planName;
  final String planType;
  final double price;
  final int duration;
  final double commissionRate;
  final double bonusMultiplier;
  final List<String> benefits;
  final bool isTimeBasedPlan;
  final String? timeWindow;
  final String? description;

  const AvailablePlan({
    required this.id,
    required this.planName,
    required this.planType,
    required this.price,
    required this.duration,
    required this.commissionRate,
    required this.bonusMultiplier,
    required this.benefits,
    required this.isTimeBasedPlan,
    this.timeWindow,
    this.description,
  });

  factory AvailablePlan.fromJson(Map<String, dynamic> json) {
    return AvailablePlan(
      id: json['_id'] as String? ?? '',
      planName: json['planName'] as String? ?? 'Unnamed Plan',
      planType: (json['planType'] as String? ?? 'basic').toLowerCase(),
      price: (json['price'] as num? ?? 0).toDouble(),
      duration: json['duration'] as int? ?? 30,
      commissionRate: (json['commissionRate'] as num? ?? 0).toDouble(),
      bonusMultiplier: (json['bonusMultiplier'] as num? ?? 1.0).toDouble(),
      benefits: (json['benefits'] as List<dynamic>?)
              ?.map((b) => b.toString())
              .toList() ??
          [],
      isTimeBasedPlan: json['isTimeBasedPlan'] as bool? ?? false,
      timeWindow: json['timeWindow'] as String?,
      description: json['description'] as String?,
    );
  }
}

class ActivePlan {
  final String id;
  final String planName;
  final String type;
  final double commissionRate;
  final double bonusMultiplier;
  final List<String> benefits;
  final DateTime? activatedDate;
  final DateTime? expiryDate;
  final int daysRemaining;
  final bool isActive;
  final double amountPaid;

  const ActivePlan({
    required this.id,
    required this.planName,
    required this.type,
    required this.commissionRate,
    required this.bonusMultiplier,
    required this.benefits,
    this.activatedDate,
    this.expiryDate,
    required this.daysRemaining,
    required this.isActive,
    required this.amountPaid,
  });

  factory ActivePlan.fromJson(Map<String, dynamic> json) {
    DateTime? parseDate(dynamic v) {
      if (v == null) return null;
      try {
        return DateTime.parse(v.toString()).toLocal();
      } catch (_) {
        return null;
      }
    }

    return ActivePlan(
      id: json['_id'] as String? ?? '',
      planName: json['planName'] as String? ?? 'Active Plan',
      type: (json['type'] as String? ?? 'basic').toLowerCase(),
      commissionRate: (json['commissionRate'] as num? ?? 0).toDouble(),
      bonusMultiplier: (json['bonusMultiplier'] as num? ?? 1.0).toDouble(),
      benefits: (json['benefits'] as List<dynamic>?)
              ?.map((b) => b.toString())
              .toList() ??
          [],
      activatedDate: parseDate(json['activatedDate']),
      expiryDate: parseDate(json['expiryDate']),
      daysRemaining: json['daysRemaining'] as int? ?? 0,
      isActive: json['isActive'] as bool? ?? false,
      amountPaid: (json['amountPaid'] as num? ?? 0).toDouble(),
    );
  }
}

class PlanHistoryItem {
  final String id;
  final String planName;
  final DateTime? purchaseDate;
  final DateTime? expiryDate;
  final double amountPaid;
  final String status;

  const PlanHistoryItem({
    required this.id,
    required this.planName,
    this.purchaseDate,
    this.expiryDate,
    required this.amountPaid,
    required this.status,
  });

  factory PlanHistoryItem.fromJson(Map<String, dynamic> json) {
    DateTime? parseDate(dynamic v) {
      if (v == null) return null;
      try {
        return DateTime.parse(v.toString()).toLocal();
      } catch (_) {
        return null;
      }
    }

    final plan = json['plan'] as Map<String, dynamic>? ?? {};
    return PlanHistoryItem(
      id: json['_id'] as String? ?? '',
      planName:
          plan['planName'] as String? ?? json['planName'] as String? ?? 'Plan',
      purchaseDate: parseDate(json['activatedDate'] ?? json['purchaseDate']),
      expiryDate: parseDate(json['expiryDate']),
      amountPaid: (json['amountPaid'] as num? ?? 0).toDouble(),
      status: json['status'] as String? ??
          (json['isActive'] == true ? 'active' : 'expired'),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Page Widget
// ─────────────────────────────────────────────────────────────────────────────

class IncentivesPage extends StatefulWidget {
  final String? customerId;
  final String? driverId;

  const IncentivesPage({Key? key, this.customerId, this.driverId})
      : super(key: key);

  @override
  State<IncentivesPage> createState() => _IncentivesPageState();
}

class _IncentivesPageState extends State<IncentivesPage>
    with TickerProviderStateMixin {
  final String _apiBase = AppConfig.backendBaseUrl;

  bool _isLoading = true;
  bool _isBuying = false;
  String? _buyingPlanId;

  List<AvailablePlan> _availablePlans = [];
  ActivePlan? _activePlan;
  List<PlanHistoryItem> _history = [];
  bool _historyLoaded = false;
  bool _historyLoading = false;

  String? _pendingPurchasePlanId;

  late Razorpay _razorpay;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(_onTabChanged);
    _initRazorpay();
    _loadData();
  }

  void _onTabChanged() {
    if (!_tabController.indexIsChanging && _tabController.index == 1) {
      if (!_historyLoaded) _loadHistory();
    }
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    _razorpay.clear();
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Razorpay Handlers
  // ─────────────────────────────────────────────────────────────────────────

  void _initRazorpay() {
    _razorpay = Razorpay();
    _razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, _onPaymentSuccess);
    _razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, _onPaymentError);
    _razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, _onExternalWallet);
  }

  void _onPaymentSuccess(PaymentSuccessResponse response) {
    final planId = _pendingPurchasePlanId;
    if (planId == null) {
      setState(() { _isBuying = false; _buyingPlanId = null; });
      _showSnackBar('Payment received but could not verify — contact support.', isError: true);
      return;
    }
    _verifyPayment(
      planId: planId,
      paymentId: response.paymentId ?? '',
      orderId: response.orderId ?? '',
      signature: response.signature ?? '',
    );
  }

  void _onPaymentError(PaymentFailureResponse response) {
    setState(() { _isBuying = false; _buyingPlanId = null; _pendingPurchasePlanId = null; });
    if (response.code == Razorpay.PAYMENT_CANCELLED) {
      _showSnackBar('Payment cancelled', isError: false);
    } else {
      _showSnackBar(response.message ?? 'Payment failed. Please try again.', isError: true);
    }
  }

  void _onExternalWallet(ExternalWalletResponse response) {
    debugPrint('📱 External wallet: ${response.walletName}');
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Auth
  // ─────────────────────────────────────────────────────────────────────────

  Future<String> _getToken() async {
    final token = await FirebaseAuth.instance.currentUser?.getIdToken();
    if (token == null) throw Exception('Not authenticated');
    return token;
  }

  Map<String, String> _headers(String token) => {
    'Content-Type': 'application/json',
    'Authorization': 'Bearer $token',
  };

  // ─────────────────────────────────────────────────────────────────────────
  // Data Loading
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final token = await _getToken();
      final h = _headers(token);
      final results = await Future.wait([
        http.get(Uri.parse('$_apiBase/api/driver/plans/available'), headers: h),
        http.get(Uri.parse('$_apiBase/api/driver/plan/current'), headers: h),
      ]);

      final plansResp = results[0];
      final currentResp = results[1];

      List<AvailablePlan> plans = [];
      if (plansResp.statusCode == 200) {
        final body = jsonDecode(plansResp.body) as Map<String, dynamic>;
        if (body['success'] == true && body['data'] is List) {
          plans = (body['data'] as List)
              .map((p) => AvailablePlan.fromJson(p as Map<String, dynamic>))
              .toList();
        }
      }

      ActivePlan? current;
      if (currentResp.statusCode == 200) {
        final body = jsonDecode(currentResp.body) as Map<String, dynamic>;
        if (body['success'] == true && body['data'] != null) {
          current = ActivePlan.fromJson(body['data'] as Map<String, dynamic>);
        }
      }

      if (mounted) {
        setState(() {
          _availablePlans = plans;
          _activePlan = current;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading plan data: $e');
      if (mounted) {
        setState(() => _isLoading = false);
        _showSnackBar('Failed to load plans. Pull to refresh.', isError: true);
      }
    }
  }

  Future<void> _loadHistory() async {
    if (_historyLoading) return;
    setState(() => _historyLoading = true);
    try {
      final token = await _getToken();
      final response = await http.get(
        Uri.parse('$_apiBase/api/driver/plan/history'),
        headers: _headers(token),
      );
      if (response.statusCode == 200) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        if (body['success'] == true && body['data'] is List) {
          final list = (body['data'] as List)
              .map((h) => PlanHistoryItem.fromJson(h as Map<String, dynamic>))
              .toList();
          if (mounted) {
            setState(() {
              _history = list;
              _historyLoaded = true;
              _historyLoading = false;
            });
          }
          return;
        }
      }
      if (mounted) setState(() => _historyLoading = false);
    } catch (e) {
      debugPrint('Error loading history: $e');
      if (mounted) setState(() => _historyLoading = false);
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Purchase Flow
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _buyPlan(AvailablePlan plan) async {
    if (_isBuying) return;
    HapticFeedback.mediumImpact();
    setState(() { _isBuying = true; _buyingPlanId = plan.id; });

    try {
      final token = await _getToken();
      final response = await http.post(
        Uri.parse('$_apiBase/api/driver/plans/${plan.id}/create-order'),
        headers: _headers(token),
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 400) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        final msg = body['message'] as String? ?? '';
        if (msg.toLowerCase().contains('active plan') || msg.toLowerCase().contains('already')) {
          _showSnackBar('You already have an active plan. Wait for it to expire.', isError: true);
        } else {
          _showSnackBar(msg.isNotEmpty ? msg : 'Cannot create order.', isError: true);
        }
        setState(() { _isBuying = false; _buyingPlanId = null; });
        return;
      }

      if (response.statusCode == 404) {
        _showSnackBar('This plan is no longer available.', isError: true);
        setState(() { _isBuying = false; _buyingPlanId = null; });
        return;
      }

      if (response.statusCode != 200 && response.statusCode != 201) {
        throw Exception('Server error ${response.statusCode}');
      }

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      if (body['success'] != true) {
        throw Exception(body['message'] ?? 'Order creation failed');
      }

      final data = body['data'] as Map<String, dynamic>;
      final orderId = data['orderId'] as String? ?? '';
      final amount = (data['amount'] as num? ?? plan.price).toDouble();
      final planName = data['planName'] as String? ?? plan.planName;

      final razorpayKey =
          (data['razorpayKey'] as String? ?? '').isNotEmpty
              ? data['razorpayKey'] as String
              : AppConfig.razorpayKey;

      if (orderId.isEmpty) throw Exception('Invalid order received');

      _pendingPurchasePlanId = plan.id;

      final phone = FirebaseAuth.instance.currentUser?.phoneNumber ?? '';

      final options = {
        'key': razorpayKey,
        'amount': (amount * 100).toInt(),
        'order_id': orderId,
        'name': 'Ghumo Driver Plan',
        'description': planName,
        'prefill': {'contact': phone, 'email': ''},
        'theme': {'color': '#B85F00'},
      };

      _razorpay.open(options);
    } catch (e) {
      debugPrint('Error creating plan order: $e');
      if (mounted) {
        setState(() { _isBuying = false; _buyingPlanId = null; });
        _showSnackBar('Error: ${e.toString()}', isError: true);
      }
    }
  }

  Future<void> _verifyPayment({
    required String planId,
    required String paymentId,
    required String orderId,
    required String signature,
  }) async {
    try {
      final token = await _getToken();
      final response = await http.post(
        Uri.parse('$_apiBase/api/driver/plans/$planId/verify-payment'),
        headers: _headers(token),
        body: jsonEncode({
          'razorpayPaymentId': paymentId,
          'razorpayOrderId': orderId,
          'razorpaySignature': signature,
        }),
      ).timeout(const Duration(seconds: 30));

      final body = jsonDecode(response.body) as Map<String, dynamic>;

      if (response.statusCode == 200 && body['success'] == true) {
        if (mounted) {
          final plan = _availablePlans.firstWhere(
            (p) => p.id == planId,
            orElse: () => AvailablePlan(
              id: planId, planName: 'Plan', planType: 'basic',
              price: 0, duration: 30, commissionRate: 0, bonusMultiplier: 1,
              benefits: [], isTimeBasedPlan: false,
            ),
          );
          setState(() { _isBuying = false; _buyingPlanId = null; _pendingPurchasePlanId = null; });
          _showSnackBar('✅ Plan activated! Valid for ${plan.duration} days.', isError: false);
          _loadData();
        }
      } else {
        throw Exception(body['message'] ?? 'Payment verification failed');
      }
    } catch (e) {
      debugPrint('Payment verification error: $e');
      if (mounted) {
        setState(() { _isBuying = false; _buyingPlanId = null; _pendingPurchasePlanId = null; });
        _showSnackBar('Payment received but verification failed. Contact support.', isError: true);
      }
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Helpers
  // ─────────────────────────────────────────────────────────────────────────

  void _showSnackBar(String message, {required bool isError}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              isError ? Icons.error_outline : Icons.check_circle_outline,
              color: Colors.white,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13, fontWeight: FontWeight.w500, color: Colors.white),
              ),
            ),
          ],
        ),
        backgroundColor: isError ? _AppColors.error : _AppColors.success,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  String _formatDate(DateTime? date) {
    if (date == null) return '—';
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${date.day} ${months[date.month - 1]} ${date.year}';
  }

  Color _typeBadgeColor(String type) {
    switch (type.toLowerCase()) {
      case 'premium': return const Color(0xFF6A1B9A);
      case 'standard': return const Color(0xFFE65100);
      default: return const Color(0xFF1565C0);
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            _buildTabBar(),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [_buildPlansTab(), _buildHistoryTab()],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: _AppColors.background,
        border: Border(bottom: BorderSide(color: _AppColors.divider, width: 0.5)),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.of(context).maybePop(),
            child: Container(
              width: 38, height: 38,
              decoration: BoxDecoration(
                color: _AppColors.surface,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.arrow_back_ios_new_rounded,
                  size: 16, color: _AppColors.onSurface),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Driver Plans',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 18, fontWeight: FontWeight.w700, color: _AppColors.onSurface),
            ),
          ),
          if (!_isLoading)
            GestureDetector(
              onTap: () { HapticFeedback.lightImpact(); _loadData(); },
              child: Container(
                width: 38, height: 38,
                decoration: BoxDecoration(
                  color: _AppColors.surface,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.refresh_rounded, size: 18, color: _AppColors.primary),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      color: _AppColors.background,
      child: TabBar(
        controller: _tabController,
        indicatorColor: _AppColors.primary,
        indicatorWeight: 2.5,
        labelColor: _AppColors.primary,
        unselectedLabelColor: _AppColors.onSurfaceTertiary,
        labelStyle: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w600),
        unselectedLabelStyle: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w500),
        tabs: const [Tab(text: 'Plans'), Tab(text: 'History')],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Plans Tab
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildPlansTab() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: _AppColors.primary));
    }

    return RefreshIndicator(
      color: _AppColors.primary,
      onRefresh: _loadData,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_activePlan != null) ...[
              _buildActivePlanCard(_activePlan!),
              const SizedBox(height: 20),
            ],

            Text(
              _activePlan != null ? 'Available Plans' : 'Choose a Plan',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 16, fontWeight: FontWeight.w700, color: _AppColors.onSurface),
            ),

            if (_activePlan != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: _AppColors.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _AppColors.divider),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline_rounded,
                        size: 18, color: _AppColors.onSurfaceTertiary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'You have an active plan. You can browse plans below, but cannot purchase until your current plan expires.',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 12, color: _AppColors.onSurfaceSecondary),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 12),

            if (_availablePlans.isEmpty)
              _buildEmptyState(
                icon: Icons.local_offer_outlined,
                message: 'No plans available right now.',
                subMessage: 'Check back later for new plans.',
              )
            else
              ..._availablePlans.map((plan) => Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: _buildPlanCard(plan),
              )),
          ],
        ),
      ),
    );
  }

  Widget _buildActivePlanCard(ActivePlan plan) {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFB85F00), Color(0xFFD47800)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: _AppColors.primary.withOpacity(0.25),
            blurRadius: 12, offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.check_circle_rounded, size: 14, color: Colors.white),
                    const SizedBox(width: 5),
                    Text('Active Plan',
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white)),
                  ],
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  plan.type.toUpperCase(),
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(plan.planName,
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white)),
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(Icons.calendar_today_rounded, size: 14, color: Colors.white70),
              const SizedBox(width: 6),
              Text('Valid till: ${_formatDate(plan.expiryDate)}',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 13, fontWeight: FontWeight.w500, color: Colors.white)),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              const Icon(Icons.timer_outlined, size: 14, color: Colors.white70),
              const SizedBox(width: 6),
              Text('${plan.daysRemaining} days remaining',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 13, fontWeight: FontWeight.w500, color: Colors.white)),
            ],
          ),
          if (plan.benefits.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Divider(color: Colors.white24, height: 1),
            const SizedBox(height: 12),
            Text('Benefits',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 11, fontWeight: FontWeight.w600,
                    color: Colors.white70, letterSpacing: 0.5)),
            const SizedBox(height: 6),
            ...plan.benefits.map((b) => Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Row(
                children: [
                  const Icon(Icons.check_rounded, size: 13, color: Colors.white70),
                  const SizedBox(width: 6),
                  Expanded(child: Text(b,
                      style: GoogleFonts.plusJakartaSans(fontSize: 12, color: Colors.white))),
                ],
              ),
            )),
          ],
          const SizedBox(height: 12),
          const Divider(color: Colors.white24, height: 1),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Amount Paid',
                  style: GoogleFonts.plusJakartaSans(fontSize: 12, color: Colors.white70)),
              Text('₹${plan.amountPaid.toStringAsFixed(0)}',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPlanCard(AvailablePlan plan) {
    final badgeColor = _typeBadgeColor(plan.planType);
    final isBuyingThis = _isBuying && _buyingPlanId == plan.id;
    final hasActivePlan = _activePlan != null;

    return Container(
      decoration: BoxDecoration(
        color: _AppColors.cardBackground,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _AppColors.divider),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2)),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(
                    color: _AppColors.primaryLight,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.star_rounded, size: 20, color: _AppColors.primary),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(plan.planName,
                          style: GoogleFonts.plusJakartaSans(
                              fontSize: 15, fontWeight: FontWeight.w700, color: _AppColors.onSurface)),
                      if (plan.description != null && plan.description!.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(plan.description!,
                              style: GoogleFonts.plusJakartaSans(
                                  fontSize: 12, color: _AppColors.onSurfaceTertiary),
                              maxLines: 2, overflow: TextOverflow.ellipsis),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: badgeColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(plan.planType.toUpperCase(),
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 10, fontWeight: FontWeight.w700,
                          color: badgeColor, letterSpacing: 0.3)),
                ),
              ],
            ),

            const SizedBox(height: 14),

            Row(
              children: [
                Text('₹${plan.price.toStringAsFixed(0)}',
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 22, fontWeight: FontWeight.w700, color: _AppColors.primary)),
                Text(' / ${plan.duration} days',
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 13, color: _AppColors.onSurfaceTertiary)),
              ],
            ),

            if (plan.benefits.isNotEmpty) ...[
              const SizedBox(height: 12),
              ...plan.benefits.map((b) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    const Icon(Icons.circle, size: 5, color: _AppColors.primary),
                    const SizedBox(width: 8),
                    Expanded(child: Text(b,
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 13, color: _AppColors.onSurfaceSecondary))),
                  ],
                ),
              )),
            ],

            const SizedBox(height: 12),

            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: _AppColors.surface,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  _buildStatChip(label: 'Commission', value: '${plan.commissionRate.toStringAsFixed(0)}%'),
                  Container(height: 24, width: 1, color: _AppColors.divider, margin: const EdgeInsets.symmetric(horizontal: 12)),
                  _buildStatChip(label: 'Bonus', value: '${plan.bonusMultiplier}x'),
                  if (plan.isTimeBasedPlan && plan.timeWindow != null) ...[
                    Container(height: 24, width: 1, color: _AppColors.divider, margin: const EdgeInsets.symmetric(horizontal: 12)),
                    _buildStatChip(label: 'Window', value: plan.timeWindow!),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 14),

            if (!hasActivePlan)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: (isBuyingThis || _isBuying) ? null : () => _buyPlan(plan),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _AppColors.primary,
                    foregroundColor: _AppColors.onPrimary,
                    disabledBackgroundColor: _AppColors.primary.withOpacity(0.5),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                  ),
                  child: isBuyingThis
                      ? const SizedBox(
                          height: 18, width: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ))
                      : Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text('Buy Plan',
                                style: GoogleFonts.plusJakartaSans(
                                    fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white)),
                            const SizedBox(width: 6),
                            const Icon(Icons.arrow_forward_rounded, size: 16, color: Colors.white),
                          ],
                        ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatChip({required String label, required String value}) {
    return Expanded(
      child: Column(
        children: [
          Text(value,
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 13, fontWeight: FontWeight.w700, color: _AppColors.onSurface)),
          const SizedBox(height: 2),
          Text(label,
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 10, color: _AppColors.onSurfaceTertiary)),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // History Tab
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildHistoryTab() {
    if (_historyLoading) {
      return const Center(child: CircularProgressIndicator(color: _AppColors.primary));
    }

    if (!_historyLoaded) {
      return _buildEmptyState(
        icon: Icons.history_rounded,
        message: 'Loading history...',
        subMessage: 'Please wait.',
      );
    }

    if (_history.isEmpty) {
      return _buildEmptyState(
        icon: Icons.receipt_long_outlined,
        message: 'No plan history yet.',
        subMessage: 'Plans you purchase will appear here.',
      );
    }

    return RefreshIndicator(
      color: _AppColors.primary,
      onRefresh: () async {
        setState(() { _historyLoaded = false; });
        await _loadHistory();
      },
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _history.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, index) => _buildHistoryCard(_history[index]),
      ),
    );
  }

  Widget _buildHistoryCard(PlanHistoryItem item) {
    final isActive = item.status.toLowerCase() == 'active';
    final statusColor = isActive ? _AppColors.success : _AppColors.onSurfaceTertiary;

    return Container(
      decoration: BoxDecoration(
        color: _AppColors.cardBackground,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _AppColors.divider),
      ),
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Container(
            width: 42, height: 42,
            decoration: BoxDecoration(
              color: isActive ? _AppColors.successLight : _AppColors.surface,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              isActive ? Icons.check_circle_rounded : Icons.history_rounded,
              size: 20, color: statusColor,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.planName,
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 14, fontWeight: FontWeight.w600, color: _AppColors.onSurface)),
                const SizedBox(height: 3),
                Text('Purchased: ${_formatDate(item.purchaseDate)}',
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 11, color: _AppColors.onSurfaceTertiary)),
                if (item.expiryDate != null)
                  Text('Expires: ${_formatDate(item.expiryDate)}',
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 11, color: _AppColors.onSurfaceTertiary)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('₹${item.amountPaid.toStringAsFixed(0)}',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 15, fontWeight: FontWeight.w700, color: _AppColors.onSurface)),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(item.status.toUpperCase(),
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 9, fontWeight: FontWeight.w700,
                        color: statusColor, letterSpacing: 0.3)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState({required IconData icon, required String message, String? subMessage}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 72, height: 72,
              decoration: const BoxDecoration(color: _AppColors.surface, shape: BoxShape.circle),
              child: Icon(icon, size: 32, color: _AppColors.onSurfaceTertiary),
            ),
            const SizedBox(height: 16),
            Text(message,
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 15, fontWeight: FontWeight.w600, color: _AppColors.onSurfaceSecondary),
                textAlign: TextAlign.center),
            if (subMessage != null) ...[
              const SizedBox(height: 6),
              Text(subMessage,
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 12, color: _AppColors.onSurfaceTertiary),
                  textAlign: TextAlign.center),
            ],
          ],
        ),
      ),
    );
  }
}
