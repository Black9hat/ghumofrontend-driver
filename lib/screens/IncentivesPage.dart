import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:razorpay_flutter/razorpay_flutter.dart';
import '../config.dart';
import '../services/commission_service.dart';
import '../widgets/commission_card.dart';

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
      planName: json['planName'] as String? ?? 'Plan',
      planType: (json['planType'] as String? ?? 'basic').toLowerCase(),
      price: (json['price'] as num? ?? json['planPrice'] as num? ?? 0)
          .toDouble(),
      duration: json['duration'] as int? ?? json['durationDays'] as int? ?? 30,
      commissionRate: (json['commissionRate'] as num? ?? 0).toDouble(),
      bonusMultiplier: (json['bonusMultiplier'] as num? ?? 1.0).toDouble(),
      benefits:
          (json['benefits'] as List<dynamic>?)
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
      benefits:
          (json['benefits'] as List<dynamic>?)
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
      status:
          json['status'] as String? ??
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

  // Colors
  static const Color _kBg = Color(0xFFF7F8FC);
  static const Color _kCard = Color(0xFFFFFFFF);
  static const Color _kPrimary = Color(0xFFD97706);
  static const Color _kPrimaryDark = Color(0xFFB45309);
  static const Color _kPrimarySoft = Color(0xFFFFF5E8);
  static const Color _kText = Color(0xFF101828);
  static const Color _kSubText = Color(0xFF667085);
  static const Color _kBorder = Color(0xFFE4E7EC);

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

  // ── Razorpay ──

  void _initRazorpay() {
    _razorpay = Razorpay();
    _razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, _onPaymentSuccess);
    _razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, _onPaymentError);
    _razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, _onExternalWallet);
  }

  void _onPaymentSuccess(PaymentSuccessResponse response) {
    final planId = _pendingPurchasePlanId;
    if (planId == null) {
      setState(() {
        _isBuying = false;
        _buyingPlanId = null;
      });
      _showSnackBar(
        'Payment received but could not verify — contact support.',
        isError: true,
      );
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
    setState(() {
      _isBuying = false;
      _buyingPlanId = null;
      _pendingPurchasePlanId = null;
    });
    if (response.code == Razorpay.PAYMENT_CANCELLED) {
      _showSnackBar('Payment cancelled', isError: false);
    } else {
      _showSnackBar(
        response.message ?? 'Payment failed. Please try again.',
        isError: true,
      );
    }
  }

  void _onExternalWallet(ExternalWalletResponse response) {
    debugPrint('📱 External wallet: ${response.walletName}');
  }

  // ── Auth helpers ──

  Future<String> _getToken() async {
    final token = await FirebaseAuth.instance.currentUser?.getIdToken();
    if (token == null) throw Exception('Not authenticated');
    return token;
  }

  Map<String, String> _headers(String token) => {
    'Content-Type': 'application/json',
    'Authorization': 'Bearer $token',
  };

  // ── Data loading ──

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final token = await _getToken();
      final h = _headers(token);
      final results = await Future.wait([
        http.get(Uri.parse('$_apiBase/api/driver/plans/available'), headers: h),
        http.get(Uri.parse('$_apiBase/api/driver/plan/current'), headers: h),
      ]);

      List<AvailablePlan> plans = [];
      if (results[0].statusCode == 200) {
        final body = jsonDecode(results[0].body) as Map<String, dynamic>;
        if (body['success'] == true && body['data'] is List) {
          plans = (body['data'] as List)
              .map((p) => AvailablePlan.fromJson(p as Map<String, dynamic>))
              .toList();
        }
      }

      ActivePlan? current;
      if (results[1].statusCode == 200) {
        final body = jsonDecode(results[1].body) as Map<String, dynamic>;
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

  // ── Purchase flow ──

  Future<void> _buyPlan(AvailablePlan plan) async {
    if (_isBuying) return;
    HapticFeedback.mediumImpact();
    setState(() {
      _isBuying = true;
      _buyingPlanId = plan.id;
    });
    try {
      final token = await _getToken();
      final response = await http.post(
        Uri.parse('$_apiBase/api/driver/plans/${plan.id}/create-order'),
        headers: _headers(token),
        body: jsonEncode({}),
      );

      final body = jsonDecode(response.body) as Map<String, dynamic>;

      if (response.statusCode == 400) {
        final msg = body['message'] as String? ?? '';
        if (msg.toLowerCase().contains('already have an active plan')) {
          _showSnackBar(
            'You already have an active plan. Wait for it to expire.',
            isError: true,
          );
        } else {
          _showSnackBar(
            msg.isNotEmpty ? msg : 'Could not create order.',
            isError: true,
          );
        }
        setState(() {
          _isBuying = false;
          _buyingPlanId = null;
        });
        return;
      }

      if (response.statusCode == 404) {
        _showSnackBar('This plan is no longer available.', isError: true);
        setState(() {
          _isBuying = false;
          _buyingPlanId = null;
        });
        return;
      }

      if (response.statusCode != 200 && response.statusCode != 201) {
        _showSnackBar('Server error. Please try again.', isError: true);
        setState(() {
          _isBuying = false;
          _buyingPlanId = null;
        });
        return;
      }

      final data = body['data'] as Map<String, dynamic>;
      final orderId = data['orderId'] as String? ?? '';
      final amount = (data['amount'] as num? ?? 0).toDouble();
      final razorpayKey =
          data['razorpayKey'] as String? ?? AppConfig.razorpayKey;

      _pendingPurchasePlanId = plan.id;

      final options = {
        'key': razorpayKey,
        'amount': (amount * 100).toInt(),
        'order_id': orderId,
        'name': 'Ghumo Driver Plan',
        'description': plan.planName,
        'theme': {'color': '#B85F00'},
      };

      _razorpay.open(options);
    } catch (e) {
      debugPrint('Error creating order: $e');
      _showSnackBar(
        'Failed to initiate payment. Please try again.',
        isError: true,
      );
      setState(() {
        _isBuying = false;
        _buyingPlanId = null;
        _pendingPurchasePlanId = null;
      });
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
      );

      setState(() {
        _isBuying = false;
        _buyingPlanId = null;
        _pendingPurchasePlanId = null;
      });

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode == 200 && body['success'] == true) {
        _showSnackBar('🎉 Plan activated successfully!', isError: false);
        _historyLoaded = false;
        await _loadData();
      } else {
        final msg =
            body['message'] as String? ?? 'Payment verification failed.';
        _showSnackBar(msg, isError: true);
      }
    } catch (e) {
      debugPrint('Error verifying payment: $e');
      setState(() {
        _isBuying = false;
        _buyingPlanId = null;
        _pendingPurchasePlanId = null;
      });
      _showSnackBar(
        'Payment verification failed. Contact support with your payment ID.',
        isError: true,
      );
    }
  }

  // ── UI helpers ──

  void _showSnackBar(String msg, {required bool isError}) {
    if (!mounted) return;

    if (!isError) return;

    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.fromLTRB(14, 0, 14, 14),
          duration: const Duration(seconds: 3),
          content: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFFEF2F2),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFFCA5A5)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.08),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 1),
                  child: Icon(
                    Icons.error_outline_rounded,
                    color: Color(0xFFB42318),
                    size: 20,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Action Failed',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFFB42318),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        msg,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: const Color(0xFF7A271A),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
  }

  Color _typeBadgeColor(String type) {
    switch (type) {
      case 'premium':
        return const Color(0xFF7C3AED);
      case 'standard':
        return const Color(0xFFB85F00);
      default:
        return const Color(0xFF1D4ED8);
    }
  }

  String _formatDate(DateTime? dt) {
    if (dt == null) return '—';
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${dt.day} ${months[dt.month - 1]} ${dt.year}';
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: _kCard,
        elevation: 0,
        centerTitle: true,
        title: Text(
          'Incentive Plans',
          style: GoogleFonts.plusJakartaSans(
            color: _kText,
            fontWeight: FontWeight.w800,
            fontSize: 19,
          ),
        ),
        iconTheme: const IconThemeData(color: _kText),
        surfaceTintColor: Colors.transparent,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: _kPrimary,
          indicatorWeight: 3,
          labelColor: _kPrimaryDark,
          unselectedLabelColor: _kSubText,
          labelStyle: GoogleFonts.plusJakartaSans(
            fontWeight: FontWeight.w700,
            fontSize: 14,
          ),
          unselectedLabelStyle: GoogleFonts.plusJakartaSans(
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
          tabs: const [
            Tab(text: 'Plans'),
            Tab(text: 'History'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [_buildPlansTab(), _buildHistoryTab()],
      ),
    );
  }

  // ── Plans Tab ──

  Widget _buildPlansTab() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: _kPrimary));
    }

    return RefreshIndicator(
      color: _kPrimary,
      backgroundColor: _kCard,
      onRefresh: _loadData,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
        children: [
          _buildPageIntro(),
          const SizedBox(height: 14),
          // 💰 Commission display card
          const CommissionCard(),
          const SizedBox(height: 18),
          if (_activePlan != null) ...[
            _buildActivePlanCard(_activePlan!),
            const SizedBox(height: 14),
            _buildNoMorePlansMessage(),
          ] else ...[
            if (_availablePlans.isEmpty)
              _buildEmptyState()
            else ...[
              Text(
                'Available Plans',
                style: GoogleFonts.plusJakartaSans(
                  color: _kText,
                  fontWeight: FontWeight.w800,
                  fontSize: 19,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Choose one plan to reduce commission and boost earnings.',
                style: GoogleFonts.plusJakartaSans(
                  color: _kSubText,
                  fontWeight: FontWeight.w500,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 12),
              ..._availablePlans.map(
                (p) => Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: _buildPlanCard(p),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildActivePlanCard(ActivePlan plan) {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFFF8EF), Color(0xFFFFF3E2)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFF8D9AB)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0F101828),
            blurRadius: 16,
            offset: Offset(0, 8),
          ),
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.verified, color: Color(0xFF10B981), size: 20),
              const SizedBox(width: 8),
              Text(
                'Active Plan',
                style: GoogleFonts.plusJakartaSans(
                  color: const Color(0xFF10B981),
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            plan.planName,
            style: GoogleFonts.plusJakartaSans(
              color: _kText,
              fontWeight: FontWeight.w800,
              fontSize: 22,
            ),
          ),
          const SizedBox(height: 8),
          _buildInfoRow(
            Icons.calendar_today_outlined,
            'Valid Till',
            _formatDate(plan.expiryDate),
          ),
          const SizedBox(height: 4),
          _buildInfoRow(
            Icons.timelapse,
            'Days Remaining',
            '${plan.daysRemaining} days',
          ),
          const SizedBox(height: 4),
          _buildInfoRow(
            Icons.currency_rupee,
            'Amount Paid',
            '₹${plan.amountPaid.toStringAsFixed(0)}',
          ),
          if (plan.benefits.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              'Benefits',
              style: GoogleFonts.plusJakartaSans(
                color: _kSubText,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            ...plan.benefits.map(
              (b) => Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Row(
                  children: [
                    const Icon(
                      Icons.check_circle_outline,
                      color: Color(0xFF10B981),
                      size: 14,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        b,
                        style: GoogleFonts.plusJakartaSans(
                          color: _kText,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, color: _kSubText, size: 14),
        const SizedBox(width: 6),
        Text(
          '$label: ',
          style: GoogleFonts.plusJakartaSans(
            color: _kSubText,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
        Flexible(
          child: Text(
            value,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.plusJakartaSans(
              color: _kText,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildNoMorePlansMessage() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _kBorder),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, color: _kPrimary, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'You have an active plan. You can purchase a new plan once this one expires.',
              style: GoogleFonts.plusJakartaSans(
                color: _kSubText,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlanCard(AvailablePlan plan) {
    final isBuyingThis = _isBuying && _buyingPlanId == plan.id;
    final badgeColor = _typeBadgeColor(plan.planType);

    return Container(
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _kBorder),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A101828),
            blurRadius: 18,
            offset: Offset(0, 10),
          ),
        ],
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('⭐', style: TextStyle(fontSize: 18)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  plan.planName,
                  style: GoogleFonts.plusJakartaSans(
                    color: _kText,
                    fontWeight: FontWeight.w800,
                    fontSize: 17,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: badgeColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: badgeColor.withOpacity(0.4)),
                ),
                child: Text(
                  plan.planType.toUpperCase(),
                  style: GoogleFonts.plusJakartaSans(
                    color: badgeColor,
                    fontWeight: FontWeight.w700,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '₹${plan.price.toStringAsFixed(0)} / ${plan.duration} days',
            style: GoogleFonts.plusJakartaSans(
              color: _kPrimaryDark,
              fontWeight: FontWeight.w800,
              fontSize: 20,
            ),
          ),
          if (plan.description != null && plan.description!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              plan.description!,
              style: GoogleFonts.plusJakartaSans(
                color: _kSubText,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
          if (plan.benefits.isNotEmpty) ...[
            const SizedBox(height: 10),
            ...plan.benefits.map(
              (b) => Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Row(
                  children: [
                    const Icon(Icons.circle, color: Color(0xFFB85F00), size: 6),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        b,
                        style: GoogleFonts.plusJakartaSans(
                          color: _kText,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildChip(
                'Commission: ${plan.commissionRate == 0 ? "0%" : "${plan.commissionRate.toStringAsFixed(0)}%"}',
              ),
              _buildChip('Bonus: ${plan.bonusMultiplier}x'),
              if (plan.isTimeBasedPlan && plan.timeWindow != null) ...[
                _buildChip('⏰ ${plan.timeWindow}'),
              ],
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: (_isBuying) ? null : () => _buyPlan(plan),
              style: ElevatedButton.styleFrom(
                backgroundColor: _kPrimary,
                disabledBackgroundColor: _kPrimary.withOpacity(0.4),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                elevation: 0,
              ),
              child: isBuyingThis
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : Text(
                      'Buy Plan →',
                      style: GoogleFonts.plusJakartaSans(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: _kPrimarySoft,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFFF6D7AA)),
      ),
      child: Text(
        label,
        style: GoogleFonts.plusJakartaSans(
          color: _kPrimaryDark,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildPageIntro() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFFF6EB), Color(0xFFFFEFD8)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFF6D7AA)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: _kPrimary.withOpacity(0.14),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.auto_awesome, color: _kPrimaryDark),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Upgrade Your Earnings',
                  style: GoogleFonts.plusJakartaSans(
                    color: _kText,
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Activate one plan at a time to reduce commission and earn more per ride.',
                  style: GoogleFonts.plusJakartaSans(
                    color: _kSubText,
                    fontWeight: FontWeight.w500,
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 60),
        child: Column(
          children: [
            const Icon(Icons.local_offer_outlined, color: _kBorder, size: 64),
            const SizedBox(height: 16),
            Text(
              'No plans available right now',
              style: GoogleFonts.plusJakartaSans(
                color: _kText,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Check back later for new plans.',
              style: GoogleFonts.plusJakartaSans(
                color: _kSubText,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── History Tab ──

  Widget _buildHistoryTab() {
    if (_historyLoading) {
      return const Center(child: CircularProgressIndicator(color: _kPrimary));
    }
    if (_history.isEmpty && _historyLoaded) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.history, color: _kBorder, size: 64),
            const SizedBox(height: 16),
            Text(
              'No plan history yet',
              style: GoogleFonts.plusJakartaSans(
                color: _kText,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      );
    }
    if (!_historyLoaded) {
      return const Center(child: CircularProgressIndicator(color: _kPrimary));
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
      itemCount: _history.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) => _buildHistoryItem(_history[i]),
    );
  }

  Widget _buildHistoryItem(PlanHistoryItem item) {
    final isActive = item.status == 'active';
    return Container(
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _kBorder),
        boxShadow: const [
          BoxShadow(
            color: Color(0x08101828),
            blurRadius: 12,
            offset: Offset(0, 6),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.planName,
                  style: GoogleFonts.plusJakartaSans(
                    color: _kText,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Purchased: ${_formatDate(item.purchaseDate)}',
                  style: GoogleFonts.plusJakartaSans(
                    color: _kSubText,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  'Expired: ${_formatDate(item.expiryDate)}',
                  style: GoogleFonts.plusJakartaSans(
                    color: _kSubText,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '₹${item.amountPaid.toStringAsFixed(0)}',
                style: GoogleFonts.plusJakartaSans(
                  color: _kPrimaryDark,
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: isActive
                      ? const Color(0xFF10B981).withOpacity(0.15)
                      : const Color(0xFFEF4444).withOpacity(0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  isActive ? 'Active' : 'Expired',
                  style: GoogleFonts.plusJakartaSans(
                    color: isActive
                        ? const Color(0xFF10B981)
                        : const Color(0xFFEF4444),
                    fontWeight: FontWeight.w600,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
