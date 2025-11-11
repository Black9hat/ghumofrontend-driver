import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';

class AppColors {
  static const Color primary = Color.fromARGB(255, 212, 120, 0);
  static const Color background = Colors.white;
  static const Color onSurface = Colors.black;
  static const Color surface = Color(0xFFF5F5F5);
  static const Color onPrimary = Colors.white;
  static const Color onSurfaceSecondary = Colors.black54;
  static const Color onSurfaceTertiary = Colors.black38;
  static const Color divider = Color(0xFFEEEEEE);
  static const Color success = Color.fromARGB(255, 0, 66, 3);
  static const Color warning = Color(0xFFFFA000);
  static const Color error = Color(0xFFD32F2F);
  static const Color gold = Color(0xFFFFD700);
}

class AppTextStyles {
  static TextStyle get heading1 => GoogleFonts.plusJakartaSans(
        fontSize: 32,
        fontWeight: FontWeight.w800,
        color: AppColors.onSurface,
        letterSpacing: -0.5,
      );

  static TextStyle get heading2 => GoogleFonts.plusJakartaSans(
        fontSize: 24,
        fontWeight: FontWeight.w700,
        color: AppColors.onSurface,
        letterSpacing: -0.3,
      );

  static TextStyle get heading3 => GoogleFonts.plusJakartaSans(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: AppColors.onSurface,
      );

  static TextStyle get body1 => GoogleFonts.plusJakartaSans(
        fontSize: 16,
        fontWeight: FontWeight.w500,
        color: AppColors.onSurface,
      );

  static TextStyle get body2 => GoogleFonts.plusJakartaSans(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: AppColors.onSurfaceSecondary,
      );

  static TextStyle get caption => GoogleFonts.plusJakartaSans(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: AppColors.onSurfaceTertiary,
        letterSpacing: 0.5,
      );
}

class IncentivesPage extends StatefulWidget {
  final String? customerId;
  final String? driverId;

  const IncentivesPage({
    Key? key,
    this.customerId,
    this.driverId,
  }) : super(key: key);

  @override
  State<IncentivesPage> createState() => _IncentivesPageState();
}

class _IncentivesPageState extends State<IncentivesPage>
    with TickerProviderStateMixin {
  final String apiBase = 'https://1708303a1cc8.ngrok-free.app';

  bool isLoading = true;
  bool isWithdrawing = false;

  late TabController _tabController;
  
  // Incentive Data
  double perRideIncentive = 0.0;
  int perRideCoins = 0;
  int totalCoinsCollected = 0;
  double totalIncentiveEarned = 0.0;
  int totalRidesCompleted = 0;
  
  // Wallet Balance
  double walletBalance = 0.0;
  
  // Today's Data
  int todayRidesCompleted = 0;
  double todayIncentiveEarned = 0.0;
  int todayCoinsEarned = 0;

  late AnimationController _coinAnimationController;
  late Animation<double> _coinBounceAnimation;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _initAnimations();
    _fetchIncentiveData();
  }

  void _initAnimations() {
    _coinAnimationController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );
    _coinBounceAnimation = Tween<double>(begin: 0.0, end: 10.0).animate(
      CurvedAnimation(
        parent: _coinAnimationController,
        curve: Curves.elasticOut,
      ),
    );
    _coinAnimationController.repeat(reverse: true);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _coinAnimationController.dispose();
    super.dispose();
  }

  // ✅ Helper methods for safe type conversion
  int _toInt(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    if (value is double) return value.toInt();
    return int.tryParse(value.toString()) ?? 0;
  }

  double _toDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    return double.tryParse(value.toString()) ?? 0.0;
  }

  Future<void> _fetchIncentiveData() async {
    setState(() => isLoading = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('User not authenticated');

      final token = await user.getIdToken();
      if (token == null) throw Exception('Token not available');

      final userId = widget.customerId ?? widget.driverId;
      if (userId == null) throw Exception('No user ID provided');

      final response = await http.get(
        Uri.parse('$apiBase/api/incentives/$userId'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final jsonResponse = jsonDecode(response.body);
        final data = jsonResponse['data'] ?? jsonResponse;
        
        // ✅ Safe type conversions
        setState(() {
          perRideIncentive = _toDouble(data['perRideIncentive']);
          perRideCoins = _toInt(data['perRideCoins']);
          totalCoinsCollected = _toInt(data['totalCoinsCollected']);
          totalIncentiveEarned = _toDouble(data['totalIncentiveEarned']);
          totalRidesCompleted = _toInt(data['totalRidesCompleted']);
          walletBalance = _toDouble(data['wallet']);
          
          todayRidesCompleted = _toInt(data['todayRidesCompleted']);
          todayIncentiveEarned = _toDouble(data['todayIncentiveEarned']);
          todayCoinsEarned = _toInt(data['todayCoinsEarned']);
          
          isLoading = false;
        });
      } else {
        throw Exception('Failed to load incentive data');
      }
    } catch (e) {
      debugPrint('❌ Error fetching incentives: $e');
      setState(() => isLoading = false);
      _showSnackBar('Failed to load incentives', isError: true);
    }
  }

  Future<void> _withdrawCoins() async {
    if (totalCoinsCollected < 100) {
      _showSnackBar('You need at least 100 coins to withdraw', isError: true);
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(Icons.account_balance_wallet, color: AppColors.primary),
            const SizedBox(width: 12),
            Text('Withdraw Coins', style: AppTextStyles.heading3),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.gold.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.gold, width: 2),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.monetization_on, color: AppColors.gold, size: 32),
                      const SizedBox(width: 8),
                      Text('100 Coins', style: AppTextStyles.heading2.copyWith(color: AppColors.gold)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Icon(Icons.arrow_downward, color: AppColors.onSurfaceSecondary),
                  const SizedBox(height: 8),
                  Text('₹50', style: AppTextStyles.heading1.copyWith(color: AppColors.success)),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Convert 100 coins to ₹50 in your wallet?',
              style: AppTextStyles.body1,
              textAlign: TextAlign.center,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: AppTextStyles.body1),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: Text('Withdraw', style: AppTextStyles.body1.copyWith(color: AppColors.onPrimary)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => isWithdrawing = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('User not authenticated');

      final token = await user.getIdToken();
      if (token == null) throw Exception('Token not available');

      final userId = widget.customerId ?? widget.driverId;
      
      final response = await http.post(
        Uri.parse('$apiBase/api/incentives/withdraw-earnings'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'userId': userId}),
      );

      if (response.statusCode == 200) {
        final jsonResponse = jsonDecode(response.body);
        final data = jsonResponse['data'] ?? jsonResponse;
        
        // ✅ FIX: Properly convert types to avoid int/double errors
        setState(() {
          // Handle remainingCoins - ensure it's an int
          if (data['remainingCoins'] != null) {
            totalCoinsCollected = _toInt(data['remainingCoins']);
          } else {
            totalCoinsCollected = totalCoinsCollected - 100;
          }
          
          // Handle newWalletBalance - ensure it's a double
          if (data['newWalletBalance'] != null) {
            walletBalance = _toDouble(data['newWalletBalance']);
          }
          
          isWithdrawing = false;
        });

        // Handle rupeeAmount - ensure it's a double
        double withdrawnAmount = 50.0;
        if (data['rupeeAmount'] != null) {
          withdrawnAmount = _toDouble(data['rupeeAmount']);
        }

        _showSuccessDialog(withdrawnAmount);
      } else {
        final errorData = jsonDecode(response.body);
        throw Exception(errorData['error'] ?? 'Withdrawal failed');
      }
    } catch (e) {
      debugPrint('❌ Error withdrawing coins: $e');
      setState(() => isWithdrawing = false);
      _showSnackBar('Withdrawal failed: ${e.toString().replaceAll('Exception: ', '')}', isError: true);
    }
  }

  void _showSuccessDialog(double amount) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.success.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.check_circle, color: AppColors.success, size: 64),
            ),
            const SizedBox(height: 24),
            Text('Withdrawal Successful!', style: AppTextStyles.heading3.copyWith(color: AppColors.success)),
            const SizedBox(height: 12),
            Text('₹${amount.toStringAsFixed(2)} has been added to your wallet', style: AppTextStyles.body2, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.gold.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.gold),
              ),
              child: Column(
                children: [
                  Text('New Wallet Balance', style: AppTextStyles.caption),
                  const SizedBox(height: 4),
                  Text('₹${walletBalance.toStringAsFixed(2)}', style: AppTextStyles.heading2.copyWith(color: AppColors.success)),
                ],
              ),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _fetchIncentiveData();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.success,
              minimumSize: const Size(double.infinity, 48),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: Text('Great!', style: AppTextStyles.body1.copyWith(color: AppColors.onPrimary)),
          ),
        ],
      ),
    );
  }

  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(isError ? Icons.error : Icons.check_circle, color: AppColors.onPrimary),
            const SizedBox(width: 12),
            Expanded(child: Text(message, style: AppTextStyles.body2.copyWith(color: AppColors.onPrimary))),
          ],
        ),
        backgroundColor: isError ? AppColors.error : AppColors.success,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: AppColors.onPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Rewards & Incentives',
          style: AppTextStyles.heading3.copyWith(color: AppColors.onPrimary),
        ),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 16),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.onPrimary.withOpacity(0.2),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              children: [
                Icon(Icons.account_balance_wallet, color: AppColors.onPrimary, size: 18),
                const SizedBox(width: 6),
                Text(
                  '₹${walletBalance.toStringAsFixed(2)}',
                  style: AppTextStyles.body2.copyWith(
                    color: AppColors.onPrimary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppColors.onPrimary,
          indicatorWeight: 3,
          labelColor: AppColors.onPrimary,
          unselectedLabelColor: AppColors.onPrimary.withOpacity(0.6),
          labelStyle: AppTextStyles.body1.copyWith(fontWeight: FontWeight.bold),
          unselectedLabelStyle: AppTextStyles.body1,
          tabs: const [
            Tab(
              icon: Icon(Icons.attach_money),
              text: 'Earnings',
            ),
            Tab(
              icon: Icon(Icons.monetization_on),
              text: 'Coins Wallet',
            ),
          ],
        ),
      ),
      body: isLoading
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: AppColors.primary),
                  const SizedBox(height: 16),
                  Text('Loading your rewards...', style: AppTextStyles.body2),
                ],
              ),
            )
          : TabBarView(
              controller: _tabController,
              children: [
                _buildEarningsSection(),
                _buildCoinsSection(),
              ],
            ),
    );
  }

  // ==================== SECTION 1: EARNINGS ====================
  Widget _buildEarningsSection() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildTodayPerformanceCard(),
          const SizedBox(height: 24),
          Text('💰 Per Ride Rewards', style: AppTextStyles.heading2),
          const SizedBox(height: 12),
          _buildPerRideBreakdownCard(),
          const SizedBox(height: 24),
          Text('📊 All Time Summary', style: AppTextStyles.heading2),
          const SizedBox(height: 12),
          _buildTotalSummaryCard(),
          const SizedBox(height: 24),
          _buildHowItWorksCard(),
        ],
      ),
    );
  }

  Widget _buildTodayPerformanceCard() {
    final totalTodayValue = todayIncentiveEarned + (todayCoinsEarned * 0.5);
    
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.primary, AppColors.primary.withOpacity(0.7)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withOpacity(0.3),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.onPrimary.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.today, color: AppColors.onPrimary, size: 28),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Today\'s Performance',
                        style: AppTextStyles.heading3.copyWith(color: AppColors.onPrimary),
                      ),
                      Text(
                        '${DateTime.now().day}/${DateTime.now().month}/${DateTime.now().year}',
                        style: AppTextStyles.caption.copyWith(color: AppColors.onPrimary.withOpacity(0.9)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          
          Container(
            margin: const EdgeInsets.all(20),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.onPrimary.withOpacity(0.15),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.local_taxi, color: AppColors.onPrimary, size: 24),
                        const SizedBox(width: 12),
                        Text(
                          'Rides Completed',
                          style: AppTextStyles.body1.copyWith(color: AppColors.onPrimary),
                        ),
                      ],
                    ),
                    Text(
                      '$todayRidesCompleted',
                      style: AppTextStyles.heading2.copyWith(
                        color: AppColors.onPrimary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                
                const SizedBox(height: 16),
                Divider(color: AppColors.onPrimary.withOpacity(0.3)),
                const SizedBox(height: 16),
                
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        children: [
                          Text(
                            'Cash/Ride',
                            style: AppTextStyles.caption.copyWith(color: AppColors.onPrimary.withOpacity(0.8)),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '₹${perRideIncentive.toStringAsFixed(0)}',
                            style: AppTextStyles.heading3.copyWith(color: AppColors.onPrimary),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      width: 1,
                      height: 40,
                      color: AppColors.onPrimary.withOpacity(0.3),
                    ),
                    Expanded(
                      child: Column(
                        children: [
                          Text(
                            'Coins/Ride',
                            style: AppTextStyles.caption.copyWith(color: AppColors.onPrimary.withOpacity(0.8)),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.monetization_on, color: AppColors.gold, size: 20),
                              const SizedBox(width: 4),
                              Text(
                                '$perRideCoins',
                                style: AppTextStyles.heading3.copyWith(color: AppColors.onPrimary),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                
                const SizedBox(height: 16),
                Divider(color: AppColors.onPrimary.withOpacity(0.3)),
                const SizedBox(height: 16),
                
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.success.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.onPrimary.withOpacity(0.3)),
                  ),
                  child: Column(
                    children: [
                      Text(
                        'Today\'s Total Earned',
                        style: AppTextStyles.caption.copyWith(color: AppColors.onPrimary.withOpacity(0.9)),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            '₹${todayIncentiveEarned.toStringAsFixed(2)}',
                            style: AppTextStyles.heading1.copyWith(
                              color: AppColors.onPrimary,
                              fontSize: 36,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text('+', style: AppTextStyles.heading3.copyWith(color: AppColors.onPrimary)),
                          const SizedBox(width: 4),
                          Icon(Icons.monetization_on, color: AppColors.gold, size: 24),
                          Text(
                            ' $todayCoinsEarned',
                            style: AppTextStyles.heading3.copyWith(color: AppColors.gold),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '(Total Value: ₹${totalTodayValue.toStringAsFixed(2)})',
                        style: AppTextStyles.caption.copyWith(color: AppColors.onPrimary.withOpacity(0.9)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPerRideBreakdownCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.divider),
        boxShadow: [
          BoxShadow(
            color: AppColors.onSurface.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.calculate, color: AppColors.primary, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('What You Earn Per Ride', style: AppTextStyles.heading3),
                    Text('Breakdown of your rewards', style: AppTextStyles.caption),
                  ],
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 20),
          
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [AppColors.success.withOpacity(0.1), AppColors.success.withOpacity(0.05)],
              ),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.success.withOpacity(0.3)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.success.withOpacity(0.2),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.attach_money, color: AppColors.success, size: 24),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Cash Incentive', style: AppTextStyles.body2),
                      Text('Added to wallet immediately', style: AppTextStyles.caption),
                    ],
                  ),
                ),
                Text(
                  '₹${perRideIncentive.toStringAsFixed(2)}',
                  style: AppTextStyles.heading2.copyWith(color: AppColors.success),
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 12),
          
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [AppColors.gold.withOpacity(0.1), AppColors.gold.withOpacity(0.05)],
              ),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.gold.withOpacity(0.3)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.gold.withOpacity(0.2),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.monetization_on, color: AppColors.gold, size: 24),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Coins Reward', style: AppTextStyles.body2),
                      Text('Collect 100 to withdraw ₹50', style: AppTextStyles.caption),
                    ],
                  ),
                ),
                Row(
                  children: [
                    Icon(Icons.monetization_on, color: AppColors.gold, size: 20),
                    Text(
                      ' $perRideCoins',
                      style: AppTextStyles.heading2.copyWith(color: AppColors.gold),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTotalSummaryCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildSummaryItem(
                'Total Rides',
                '$totalRidesCompleted',
                Icons.local_taxi,
                AppColors.primary,
              ),
              Container(width: 1, height: 60, color: AppColors.divider),
              _buildSummaryItem(
                'Total Earned',
                '₹${totalIncentiveEarned.toStringAsFixed(0)}',
                Icons.account_balance_wallet,
                AppColors.success,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryItem(String label, String value, IconData icon, Color color) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, color: color, size: 32),
          const SizedBox(height: 8),
          Text(value, style: AppTextStyles.heading2.copyWith(color: color)),
          const SizedBox(height: 4),
          Text(label, style: AppTextStyles.caption, textAlign: TextAlign.center),
        ],
      ),
    );
  }

  Widget _buildHowItWorksCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline, color: AppColors.primary),
              const SizedBox(width: 12),
              Text('How It Works', style: AppTextStyles.heading3),
            ],
          ),
          const SizedBox(height: 16),
          _buildInfoRow(
            '1',
            'Complete rides and earn cash + coins instantly',
            Icons.directions_car,
          ),
          const SizedBox(height: 12),
          _buildInfoRow(
            '2',
            'Cash incentive added to wallet immediately',
            Icons.account_balance_wallet,
          ),
          const SizedBox(height: 12),
          _buildInfoRow(
            '3',
            'Coins accumulate - withdraw when you reach 100',
            Icons.monetization_on,
          ),
          const SizedBox(height: 12),
          _buildInfoRow(
            '4',
            'Rewards are set by admin and may change',
            Icons.settings,
          ),
        ],
      ),
    );
  }

  // ==================== SECTION 2: COINS WALLET ====================
  Widget _buildCoinsSection() {
    final canWithdraw = totalCoinsCollected >= 100;
    final coinsNeeded = 100 - totalCoinsCollected;
    final progressPercentage = (totalCoinsCollected / 100).clamp(0.0, 1.0);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Coins Balance Card
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [AppColors.gold, AppColors.gold.withOpacity(0.7)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: AppColors.gold.withOpacity(0.3),
                  blurRadius: 15,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              children: [
                Text(
                  'Your Coins Balance',
                  style: AppTextStyles.body2.copyWith(color: AppColors.onSurface),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    AnimatedBuilder(
                      animation: _coinBounceAnimation,
                      builder: (context, child) {
                        return Transform.translate(
                          offset: Offset(0, -_coinBounceAnimation.value),
                          child: Icon(
                            Icons.monetization_on,
                            color: AppColors.onSurface,
                            size: 48,
                          ),
                        );
                      },
                    ),
                    const SizedBox(width: 12),
                    Text(
                      '$totalCoinsCollected',
                      style: AppTextStyles.heading1.copyWith(
                        color: AppColors.onSurface,
                        fontSize: 56,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Value: ₹${(totalCoinsCollected * 0.5).toStringAsFixed(2)}',
                  style: AppTextStyles.body1.copyWith(color: AppColors.onSurface),
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 24),
          
          // Progress to Withdrawal
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.divider),
              boxShadow: [
                BoxShadow(
                  color: AppColors.onSurface.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.flag, color: AppColors.primary, size: 24),
                        const SizedBox(width: 12),
                        Text(
                          'Withdrawal Progress',
                          style: AppTextStyles.heading3,
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: canWithdraw 
                            ? AppColors.success.withOpacity(0.1) 
                            : AppColors.warning.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: canWithdraw ? AppColors.success : AppColors.warning,
                        ),
                      ),
                      child: Text(
                        canWithdraw ? 'Ready!' : '$coinsNeeded more',
                        style: AppTextStyles.caption.copyWith(
                          color: canWithdraw ? AppColors.success : AppColors.warning,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                
                const SizedBox(height: 20),
                
                // Progress Bar
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '$totalCoinsCollected / 100 Coins',
                          style: AppTextStyles.body1,
                        ),
                        Text(
                          '${(progressPercentage * 100).toInt()}%',
                          style: AppTextStyles.body1.copyWith(
                            color: AppColors.gold,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: LinearProgressIndicator(
                        value: progressPercentage,
                        minHeight: 16,
                        backgroundColor: AppColors.gold.withOpacity(0.2),
                        valueColor: AlwaysStoppedAnimation<Color>(AppColors.gold),
                      ),
                    ),
                  ],
                ),
                
                const SizedBox(height: 20),
                
                // Conversion Info
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.divider),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: AppColors.gold.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppColors.gold),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.monetization_on, color: AppColors.gold, size: 20),
                            const SizedBox(width: 4),
                            Text('100', style: AppTextStyles.body1.copyWith(color: AppColors.gold)),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      Icon(Icons.arrow_forward, color: AppColors.onSurfaceSecondary, size: 20),
                      const SizedBox(width: 16),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: AppColors.success.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppColors.success),
                        ),
                        child: Text('₹50', style: AppTextStyles.body1.copyWith(color: AppColors.success)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 24),
          
          // Withdraw Button
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton.icon(
              onPressed: canWithdraw && !isWithdrawing
                  ? () {
                      HapticFeedback.mediumImpact();
                      _withdrawCoins();
                    }
                  : null,
              icon: isWithdrawing
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.onPrimary,
                      ),
                    )
                  : Icon(
                      canWithdraw ? Icons.account_balance_wallet : Icons.lock,
                      size: 24,
                    ),
              label: Text(
                isWithdrawing
                    ? 'Processing...'
                    : canWithdraw
                        ? 'Withdraw ₹50 to Wallet'
                        : 'Need 100 coins to withdraw',
                style: AppTextStyles.body1.copyWith(
                  color: AppColors.onPrimary,
                  fontWeight: FontWeight.bold,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: canWithdraw ? AppColors.success : AppColors.onSurfaceSecondary,
                disabledBackgroundColor: AppColors.onSurfaceSecondary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                elevation: canWithdraw ? 6 : 0,
              ),
            ),
          ),
          
          const SizedBox(height: 24),
          
          // Coins History/Stats
          Text('📊 Coins Statistics', style: AppTextStyles.heading2),
          const SizedBox(height: 12),
          
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.divider),
            ),
            child: Column(
              children: [
                _buildCoinsStatRow(
                  'Total Coins Earned',
                  '$totalCoinsCollected',
                  Icons.stars,
                  AppColors.gold,
                ),
                const SizedBox(height: 16),
                Divider(color: AppColors.divider),
                const SizedBox(height: 16),
                _buildCoinsStatRow(
                  'Today\'s Coins',
                  '$todayCoinsEarned',
                  Icons.today,
                  AppColors.primary,
                ),
                const SizedBox(height: 16),
                Divider(color: AppColors.divider),
                const SizedBox(height: 16),
                _buildCoinsStatRow(
                  'Coins per Ride',
                  '$perRideCoins',
                  Icons.monetization_on,
                  AppColors.warning,
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 24),
          
          // How Coins Work
          _buildCoinsInfoCard(),
        ],
      ),
    );
  }

  Widget _buildCoinsStatRow(String label, String value, IconData icon, Color color) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: color, size: 24),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Text(label, style: AppTextStyles.body1),
        ),
        Text(
          value,
          style: AppTextStyles.heading3.copyWith(color: color),
        ),
      ],
    );
  }

  Widget _buildCoinsInfoCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.primary.withOpacity(0.1),
            AppColors.primary.withOpacity(0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primary.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.lightbulb, color: AppColors.primary, size: 24),
              const SizedBox(width: 12),
              Text('How Coins Work', style: AppTextStyles.heading3),
            ],
          ),
          const SizedBox(height: 16),
          _buildInfoRow('1', 'Earn $perRideCoins coins per completed ride', Icons.local_taxi),
          const SizedBox(height: 12),
          _buildInfoRow('2', 'Collect 100 coins to unlock withdrawal', Icons.lock_open),
          const SizedBox(height: 12),
          _buildInfoRow('3', '100 coins = ₹50 added to wallet', Icons.account_balance_wallet),
          const SizedBox(height: 12),
          _buildInfoRow('4', 'Coin value: 1 coin = ₹0.50', Icons.calculate),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String number, String text, IconData icon) {
    return Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: AppColors.primary.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Center(
            child: Text(
              number,
              style: AppTextStyles.body1.copyWith(
                color: AppColors.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(text, style: AppTextStyles.body2),
        ),
        Icon(icon, color: AppColors.onSurfaceTertiary, size: 20),
      ],
    );
  }
}