// lib/pages/incentivespage.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:drivergoo/config.dart';

// --- COLOR PALETTE ---
class AppColors {
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
  static const Color warning = Color(0xFFF57C00);
  static const Color error = Color(0xFFD32F2F);
}

// --- TYPOGRAPHY ---
class AppTextStyles {
  static TextStyle get heading1 => GoogleFonts.plusJakartaSans(
    fontSize: 28,
    fontWeight: FontWeight.w700,
    color: AppColors.onSurface,
    letterSpacing: -0.5,
  );

  static TextStyle get heading2 => GoogleFonts.plusJakartaSans(
    fontSize: 20,
    fontWeight: FontWeight.w600,
    color: AppColors.onSurface,
    letterSpacing: -0.3,
  );

  static TextStyle get body1 => GoogleFonts.plusJakartaSans(
    fontSize: 15,
    fontWeight: FontWeight.w500,
    color: AppColors.onSurface,
  );

  static TextStyle get body2 => GoogleFonts.plusJakartaSans(
    fontSize: 13,
    fontWeight: FontWeight.w400,
    color: AppColors.onSurfaceSecondary,
  );

  static TextStyle get caption => GoogleFonts.plusJakartaSans(
    fontSize: 11,
    fontWeight: FontWeight.w500,
    color: AppColors.onSurfaceTertiary,
    letterSpacing: 0.3,
  );

  static TextStyle get button => GoogleFonts.plusJakartaSans(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    color: AppColors.onPrimary,
  );
}

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
  final String apiBase = AppConfig.backendBaseUrl;

  bool isLoading = true;
  bool isRefreshing = false;

  List<String> todayOffers = [];
  List<String> yesterdayOffers = [];

  late TabController _tabController;
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();

    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        HapticFeedback.selectionClick();
        setState(() {});
      }
    });

    _animationController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOutCubic),
    );
    _animationController.forward();

    _fetchBannerImages();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _fetchBannerImages() async {
    if (!isRefreshing) {
      setState(() => isLoading = true);
    }

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('User not authenticated');

      final token = await user.getIdToken();
      if (token == null) throw Exception('Token not available');

      final response = await http.get(
        Uri.parse('$apiBase/api/driver/incentives'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final jsonResponse = jsonDecode(response.body);
        final data = jsonResponse['data'] ?? jsonResponse;

        setState(() {
          if (data['todayOffers'] != null) {
            todayOffers = List<String>.from(data['todayOffers']);
          } else if (data['images'] != null) {
            todayOffers = List<String>.from(data['images']);
          } else {
            todayOffers = [];
          }

          if (data['yesterdayOffers'] != null) {
            yesterdayOffers = List<String>.from(data['yesterdayOffers']);
          } else if (data['yesterdayImages'] != null) {
            yesterdayOffers = List<String>.from(data['yesterdayImages']);
          } else {
            yesterdayOffers = [];
          }

          isLoading = false;
          isRefreshing = false;
        });
      } else {
        throw Exception('Failed to load banner images');
      }
    } catch (e) {
      debugPrint('❌ Error fetching banner images: $e');
      setState(() {
        isLoading = false;
        isRefreshing = false;
      });
      _showSnackBar('Failed to load offers', isError: true);
    }
  }

  Future<void> _onRefresh() async {
    HapticFeedback.mediumImpact();
    setState(() => isRefreshing = true);
    await _fetchBannerImages();
  }

  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              isError ? Icons.error : Icons.check_circle,
              color: AppColors.onPrimary,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: AppTextStyles.body1.copyWith(color: AppColors.onPrimary),
              ),
            ),
          ],
        ),
        backgroundColor: isError ? AppColors.error : AppColors.success,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  String _getFullImageUrl(String url) {
    if (url.startsWith('http')) return url;
    return '$apiBase$url';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: isLoading
            ? _buildLoadingState()
            : FadeTransition(
                opacity: _fadeAnimation,
                child: Column(
                  children: [
                    _buildHeader(),
                    _buildTabBar(),
                    Expanded(
                      child: TabBarView(
                        controller: _tabController,
                        children: [
                          _buildTodayOffersTab(),
                          _buildYesterdayOffersTab(),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildLoadingState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
          ),
          const SizedBox(height: 16),
          Text('Loading offers...', style: AppTextStyles.body2),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      child: Row(
        children: [
          GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              Navigator.pop(context);
            },
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppColors.primary.withOpacity(0.25),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withOpacity(0.1),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: const Icon(
                Icons.arrow_back,
                color: AppColors.onSurface,
                size: 22,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Text("Incentives", style: AppTextStyles.heading1),
          const Spacer(),
          GestureDetector(
            onTap: isRefreshing ? null : _onRefresh,
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppColors.primary.withOpacity(0.25),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withOpacity(0.1),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: isRefreshing
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.primary,
                      ),
                    )
                  : const Icon(
                      Icons.refresh,
                      color: AppColors.onSurface,
                      size: 22,
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider, width: 1),
      ),
      child: TabBar(
        controller: _tabController,
        indicator: BoxDecoration(
          color: AppColors.primary,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withOpacity(0.3),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        indicatorPadding: const EdgeInsets.all(4),
        dividerColor: Colors.transparent,
        labelColor: AppColors.onPrimary,
        unselectedLabelColor: AppColors.onSurfaceSecondary,
        labelStyle: AppTextStyles.body1.copyWith(fontWeight: FontWeight.w600),
        unselectedLabelStyle: AppTextStyles.body2,
        tabs: [
          Tab(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.local_offer, size: 18),
                const SizedBox(width: 8),
                const Text("Today"),
                if (todayOffers.isNotEmpty) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: _tabController.index == 0
                          ? AppColors.onPrimary.withOpacity(0.2)
                          : AppColors.primary.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${todayOffers.length}',
                      style: AppTextStyles.caption.copyWith(
                        color: _tabController.index == 0
                            ? AppColors.onPrimary
                            : AppColors.primary,
                        fontWeight: FontWeight.w700,
                        fontSize: 10,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          Tab(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.history, size: 18),
                const SizedBox(width: 8),
                const Text("Yesterday"),
                if (yesterdayOffers.isNotEmpty) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: _tabController.index == 1
                          ? AppColors.onPrimary.withOpacity(0.2)
                          : AppColors.onSurfaceTertiary.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${yesterdayOffers.length}',
                      style: AppTextStyles.caption.copyWith(
                        color: _tabController.index == 1
                            ? AppColors.onPrimary
                            : AppColors.onSurfaceTertiary,
                        fontWeight: FontWeight.w700,
                        fontSize: 10,
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

  // ==================== TODAY'S OFFERS TAB ====================
  Widget _buildTodayOffersTab() {
    return RefreshIndicator(
      onRefresh: _onRefresh,
      color: AppColors.primary,
      child: todayOffers.isEmpty
          ? _buildEmptyState(
              title: "No Offers Today",
              subtitle: "Check back later for exciting new offers!",
              icon: Icons.local_offer_outlined,
              isToday: true,
            )
          : _buildTodayOffersList(),
    );
  }

  Widget _buildTodayOffersList() {
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
      itemCount: todayOffers.length,
      itemBuilder: (context, index) {
        return _buildOfferCard(todayOffers[index], isToday: true);
      },
    );
  }

  // ==================== YESTERDAY'S OFFERS TAB ====================
  Widget _buildYesterdayOffersTab() {
    return RefreshIndicator(
      onRefresh: _onRefresh,
      color: AppColors.primary,
      child: yesterdayOffers.isEmpty
          ? _buildEmptyState(
              title: "No Offers Yesterday",
              subtitle: "There were no offers from yesterday",
              icon: Icons.history_outlined,
              isToday: false,
            )
          : _buildYesterdayOffersList(),
    );
  }

  Widget _buildYesterdayOffersList() {
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
      itemCount: yesterdayOffers.length,
      itemBuilder: (context, index) {
        return _buildOfferCard(yesterdayOffers[index], isToday: false);
      },
    );
  }

  // ==================== UNIFIED OFFER CARD ====================
  Widget _buildOfferCard(String imageUrl, {required bool isToday}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isToday
              ? AppColors.primary.withOpacity(0.15)
              : AppColors.divider,
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: isToday
                ? AppColors.primary.withOpacity(0.08)
                : Colors.black.withOpacity(0.05),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: isToday
            ? _buildTodayImage(imageUrl)
            : _buildYesterdayImage(imageUrl),
      ),
    );
  }

  Widget _buildTodayImage(String imageUrl) {
    return Image.network(
      '${_getFullImageUrl(imageUrl)}?v=${DateTime.now().millisecondsSinceEpoch}',
      fit: BoxFit.cover,
      width: double.infinity,
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) return child;
        return Container(
          height: 200,
          color: AppColors.surface,
          child: Center(
            child: CircularProgressIndicator(
              color: AppColors.primary,
              value: loadingProgress.expectedTotalBytes != null
                  ? loadingProgress.cumulativeBytesLoaded /
                        loadingProgress.expectedTotalBytes!
                  : null,
            ),
          ),
        );
      },
      errorBuilder: (context, error, stackTrace) {
        return Container(
          height: 200,
          color: AppColors.surface,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.image_not_supported_outlined,
                color: AppColors.onSurfaceTertiary,
                size: 48,
              ),
              const SizedBox(height: 8),
              Text('Image not available', style: AppTextStyles.caption),
            ],
          ),
        );
      },
    );
  }

  Widget _buildYesterdayImage(String imageUrl) {
    return Stack(
      children: [
        // Grayscale image
        ColorFiltered(
          colorFilter: ColorFilter.mode(
            Colors.grey.withOpacity(0.4),
            BlendMode.saturation,
          ),
          child: Image.network(
            '${_getFullImageUrl(imageUrl)}?v=${DateTime.now().millisecondsSinceEpoch}',
            fit: BoxFit.cover,
            width: double.infinity,
            loadingBuilder: (context, child, loadingProgress) {
              if (loadingProgress == null) return child;
              return Container(
                height: 200,
                color: AppColors.surface,
                child: Center(
                  child: CircularProgressIndicator(
                    color: AppColors.primary,
                    value: loadingProgress.expectedTotalBytes != null
                        ? loadingProgress.cumulativeBytesLoaded /
                              loadingProgress.expectedTotalBytes!
                        : null,
                  ),
                ),
              );
            },
            errorBuilder: (context, error, stackTrace) {
              return Container(
                height: 200,
                color: AppColors.surface,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.image_not_supported_outlined,
                      color: AppColors.onSurfaceTertiary,
                      size: 48,
                    ),
                    const SizedBox(height: 8),
                    Text('Image not available', style: AppTextStyles.caption),
                  ],
                ),
              );
            },
          ),
        ),
        // Dark overlay
        Positioned.fill(
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withOpacity(0.05),
                  Colors.black.withOpacity(0.2),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ==================== EMPTY STATE ====================
  Widget _buildEmptyState({
    required String title,
    required String subtitle,
    required IconData icon,
    required bool isToday,
  }) {
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      child: SizedBox(
        height: MediaQuery.of(context).size.height - 250,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(40),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(28),
                  decoration: BoxDecoration(
                    color: isToday ? AppColors.primaryLight : AppColors.surface,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isToday
                          ? AppColors.primary.withOpacity(0.2)
                          : AppColors.divider,
                      width: 2,
                    ),
                  ),
                  child: Icon(
                    icon,
                    size: 56,
                    color: isToday
                        ? AppColors.primary
                        : AppColors.onSurfaceTertiary,
                  ),
                ),
                const SizedBox(height: 28),
                Text(
                  title,
                  style: AppTextStyles.heading2,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
                Text(
                  subtitle,
                  style: AppTextStyles.body2,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                GestureDetector(
                  onTap: _onRefresh,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 28,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primary.withOpacity(0.3),
                          blurRadius: 12,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.refresh,
                          color: AppColors.onPrimary,
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        Text('Refresh', style: AppTextStyles.button),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.swipe,
                      size: 16,
                      color: AppColors.onSurfaceTertiary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      isToday
                          ? 'Swipe left to see yesterday\'s offers'
                          : 'Swipe right to see today\'s offers',
                      style: AppTextStyles.caption,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
