import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../config.dart';

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
}

class DriverPrivacySecurityPage extends StatefulWidget {
  const DriverPrivacySecurityPage({super.key});

  @override
  State<DriverPrivacySecurityPage> createState() =>
      _DriverPrivacySecurityPageState();
}

class _DriverPrivacySecurityPageState extends State<DriverPrivacySecurityPage>
    with SingleTickerProviderStateMixin {
  bool _isLoading = false;
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _initAnimations();
  }

  void _initAnimations() {
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOutCubic,
    );
    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: Stack(
        children: [
          CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              _buildSliverAppBar(),
              SliverToBoxAdapter(
                child: FadeTransition(
                  opacity: _fadeAnimation,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildSecurityHeader(),
                        const SizedBox(height: 24),

                        // 1. Account & Security
                        _buildAccountSecuritySection(),
                        const SizedBox(height: 24),

                        // 2. Location & Activity
                        _buildLocationActivitySection(),
                        const SizedBox(height: 24),

                        // 3. Documents & Verification
                        _buildDocumentsSection(),
                        const SizedBox(height: 24),

                        // 4. Earnings & Payments
                        _buildEarningsPaymentsSection(),
                        const SizedBox(height: 24),

                        // 5. Data & Privacy
                        _buildDataPrivacySection(),
                        const SizedBox(height: 24),

                        // 6. App Permissions
                        _buildPermissionsSection(),
                        const SizedBox(height: 24),

                        // 7. Legal
                        _buildLegalSection(),
                        const SizedBox(height: 24),

                        // 8. Danger Zone
                        _buildDangerZoneSection(),
                        const SizedBox(height: 32),

                        // Footer
                        _buildFooter(),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (_isLoading) _buildLoadingOverlay(),
        ],
      ),
    );
  }

  // ===== APP BAR =====
  Widget _buildSliverAppBar() {
    return SliverAppBar(
      expandedHeight: 120,
      floating: false,
      pinned: true,
      elevation: 0,
      backgroundColor: AppColors.background,
      surfaceTintColor: Colors.transparent,
      leading: IconButton(
        icon: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(
            Icons.arrow_back_ios_new_rounded,
            size: 18,
            color: AppColors.onSurface,
          ),
        ),
        onPressed: () => Navigator.pop(context),
      ),
      flexibleSpace: FlexibleSpaceBar(
        titlePadding: const EdgeInsets.only(left: 20, bottom: 16),
        title: const Text(
          "Privacy & Security",
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: AppColors.onSurface,
            letterSpacing: -0.5,
          ),
        ),
        background: Container(
          decoration: const BoxDecoration(
            color: AppColors.background,
            border: Border(bottom: BorderSide(color: AppColors.divider)),
          ),
        ),
      ),
      iconTheme: const IconThemeData(color: AppColors.onSurface),
    );
  }

  // ===== SECURITY HEADER =====
  Widget _buildSecurityHeader() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.primary, AppColors.primary.withOpacity(0.8)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withOpacity(0.3),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: AppColors.onPrimary.withOpacity(0.2),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Center(
              child: Icon(
                Icons.shield_rounded,
                color: AppColors.onPrimary,
                size: 28,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Your Privacy Matters",
                  style: TextStyle(
                    color: AppColors.onPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  "We protect your data with industry-standard security measures",
                  style: TextStyle(
                    color: AppColors.onPrimary.withOpacity(0.85),
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ===== 1. ACCOUNT & SECURITY SECTION =====
  Widget _buildAccountSecuritySection() {
    return _buildSection(
      title: "Account & Security",
      icon: Icons.lock_rounded,
      iconColor: AppColors.primary,
      children: [
        // Login Method
        _buildInfoTile(
          icon: Icons.phonelink_lock_rounded,
          iconColor: AppColors.success,
          title: "Login Method",
          subtitle: "OTP-based secure authentication",
          onTap: () => _showLoginMethodSheet(),
        ),
        _buildDivider(),

        // Phone Number
        _buildSettingsTile(
          icon: Icons.phone_android_rounded,
          iconColor: AppColors.primary,
          title: "Phone Number",
          subtitle: _getPhoneNumber(),
          trailing: _buildVerifiedBadge(),
        ),
        _buildDivider(),

        // Active Sessions
        _buildInfoTile(
          icon: Icons.devices_rounded,
          iconColor: AppColors.warning,
          title: "Active Sessions",
          subtitle: "Manage logged-in devices",
          onTap: () => _showSessionsSheet(),
        ),
      ],
    );
  }

  // ===== 2. LOCATION & ACTIVITY SECTION =====
  Widget _buildLocationActivitySection() {
    return _buildSection(
      title: "Location & Activity",
      icon: Icons.location_on_rounded,
      iconColor: AppColors.success,
      children: [
        // Live Location Usage
        _buildInfoTile(
          icon: Icons.my_location_rounded,
          iconColor: AppColors.success,
          title: "Live Location Usage",
          subtitle: "Real-time tracking when online",
          trailing: _buildActiveBadge(),
          onTap: () => _showLiveLocationSheet(),
        ),
        _buildDivider(),

        // Background Location
        _buildInfoTile(
          icon: Icons.location_searching_rounded,
          iconColor: AppColors.warning,
          title: "Background Location",
          subtitle: "Location access while app is minimized",
          onTap: () => _showBackgroundLocationSheet(),
        ),
        _buildDivider(),

        // Trip History
        _buildInfoTile(
          icon: Icons.history_rounded,
          iconColor: AppColors.onSurfaceSecondary,
          title: "Trip History",
          subtitle: "Your ride history is stored securely",
          onTap: () => _showTripHistoryInfoSheet(),
        ),
      ],
    );
  }

  // ===== 3. DOCUMENTS & VERIFICATION SECTION =====
  Widget _buildDocumentsSection() {
    return _buildSection(
      title: "Documents & Verification",
      icon: Icons.folder_rounded,
      iconColor: AppColors.warning,
      children: [
        // Document Storage
        _buildInfoTile(
          icon: Icons.description_rounded,
          iconColor: AppColors.primary,
          title: "Document Storage",
          subtitle: "DL, RC, Insurance, Vehicle details",
          onTap: () => _showDocumentStorageSheet(),
        ),
        _buildDivider(),

        // Document Security
        _buildInfoTile(
          icon: Icons.security_rounded,
          iconColor: AppColors.success,
          title: "Document Security",
          subtitle: "Encrypted storage & verification only",
          onTap: () => _showDocumentSecuritySheet(),
        ),
        _buildDivider(),

        // Verification Status
        _buildInfoTile(
          icon: Icons.verified_user_rounded,
          iconColor: AppColors.success,
          title: "Verification Status",
          subtitle: "View your document verification status",
          trailing: _buildStatusDot(true),
          onTap: () => _showVerificationStatusSheet(),
        ),
      ],
    );
  }

  // ===== 4. EARNINGS & PAYMENTS SECTION =====
  Widget _buildEarningsPaymentsSection() {
    return _buildSection(
      title: "Earnings & Payments",
      icon: Icons.account_balance_wallet_rounded,
      iconColor: AppColors.success,
      children: [
        // Bank Details Protection
        _buildInfoTile(
          icon: Icons.account_balance_rounded,
          iconColor: AppColors.primary,
          title: "Bank Details Protection",
          subtitle: "Your payment info is encrypted",
          onTap: () => _showBankProtectionSheet(),
        ),
        _buildDivider(),

        // Payment History
        _buildInfoTile(
          icon: Icons.receipt_long_rounded,
          iconColor: AppColors.onSurfaceSecondary,
          title: "Payment History",
          subtitle: "Transaction records stored securely",
          onTap: () => _showPaymentHistoryInfoSheet(),
        ),
      ],
    );
  }

  // ===== 5. DATA & PRIVACY SECTION =====
  Widget _buildDataPrivacySection() {
    return _buildSection(
      title: "Data & Privacy",
      icon: Icons.privacy_tip_rounded,
      iconColor: AppColors.primary,
      children: [
        // Data Collection
        _buildInfoTile(
          icon: Icons.data_usage_rounded,
          iconColor: AppColors.primary,
          title: "Data Collection",
          subtitle: "What information we collect",
          onTap: () => _showDataCollectionSheet(),
        ),
        _buildDivider(),

        // Data Sharing
        _buildInfoTile(
          icon: Icons.share_rounded,
          iconColor: AppColors.warning,
          title: "Data Sharing",
          subtitle: "How your data is shared",
          onTap: () => _showDataSharingSheet(),
        ),
        _buildDivider(),

        // Data Retention
        _buildInfoTile(
          icon: Icons.access_time_rounded,
          iconColor: AppColors.onSurfaceSecondary,
          title: "Data Retention",
          subtitle: "How long we keep your data",
          onTap: () => _showDataRetentionSheet(),
        ),
        _buildDivider(),

        // Download Your Data
        _buildInfoTile(
          icon: Icons.download_rounded,
          iconColor: AppColors.success,
          title: "Download Your Data",
          subtitle: "Export your personal information",
          onTap: () => _showDownloadDataSheet(),
        ),
      ],
    );
  }

  // ===== 6. APP PERMISSIONS SECTION =====
  Widget _buildPermissionsSection() {
    return _buildSection(
      title: "App Permissions",
      icon: Icons.app_settings_alt_rounded,
      iconColor: AppColors.onSurfaceSecondary,
      children: [
        _buildPermissionTile(
          icon: Icons.location_on_rounded,
          title: "Location",
          description: "Ride matching & navigation",
          isGranted: true,
        ),
        _buildDivider(),
        _buildPermissionTile(
          icon: Icons.camera_alt_rounded,
          title: "Camera",
          description: "Document upload & verification",
          isGranted: true,
        ),
        _buildDivider(),
        _buildPermissionTile(
          icon: Icons.folder_rounded,
          title: "Storage",
          description: "Document storage & caching",
          isGranted: true,
        ),
        _buildDivider(),
        _buildPermissionTile(
          icon: Icons.notifications_rounded,
          title: "Notifications",
          description: "Ride alerts & updates",
          isGranted: true,
        ),
        _buildDivider(),
        _buildPermissionTile(
          icon: Icons.phone_rounded,
          title: "Phone",
          description: "OTP auto-read & calling",
          isGranted: true,
        ),
      ],
    );
  }

  // ===== 7. LEGAL SECTION =====
  Widget _buildLegalSection() {
    return _buildSection(
      title: "Legal",
      icon: Icons.gavel_rounded,
      iconColor: AppColors.onSurfaceSecondary,
      children: [
        _buildSettingsTile(
          icon: Icons.privacy_tip_outlined,
          iconColor: AppColors.primary,
          title: "Privacy Policy",
          subtitle: "Read our privacy policy",
          trailing: _buildExternalLinkIcon(),
          onTap: () =>
              _launchURL("${AppConfig.backendBaseUrl}/driver-privacy.html"),
        ),
        _buildDivider(),
        _buildSettingsTile(
          icon: Icons.assignment_outlined,
          iconColor: AppColors.primary,
          title: "Terms & Conditions",
          subtitle: "Read our terms of service",
          trailing: _buildExternalLinkIcon(),
          onTap: () =>
              _launchURL("${AppConfig.backendBaseUrl}/driver-terms.html"),
        ),
        _buildDivider(),
        _buildInfoTile(
          icon: Icons.https_rounded,
          iconColor: AppColors.success,
          title: "Security Practices",
          subtitle: "HTTPS encryption & secure servers",
          onTap: () => _showSecurityPracticesSheet(),
        ),
      ],
    );
  }

  // ===== 8. DANGER ZONE SECTION =====
  Widget _buildDangerZoneSection() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.error.withOpacity(0.05),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.error.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.error.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.warning_amber_rounded,
                    color: AppColors.error,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                const Text(
                  "Account Actions",
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.error,
                    letterSpacing: -0.3,
                  ),
                ),
              ],
            ),
          ),
          _buildDangerTile(
            icon: Icons.logout_rounded,
            title: "Logout From All Devices",
            subtitle: "End all active sessions",
            onTap: () => _showLogoutAllSheet(),
          ),
          Divider(
            height: 1,
            indent: 72,
            endIndent: 20,
            color: AppColors.error.withOpacity(0.1),
          ),
          _buildDangerTile(
            icon: Icons.delete_forever_rounded,
            title: "Delete Account",
            subtitle: "Permanently remove your account and data",
            onTap: () => _showDeleteAccountSheet(),
          ),
        ],
      ),
    );
  }

  // ===== FOOTER =====
  Widget _buildFooter() {
    return Column(
      children: [
        // Contact Support
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.primary.withOpacity(0.1),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              const Icon(Icons.support_agent_rounded, color: AppColors.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text(
                      "Need Help?",
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: AppColors.onSurface,
                      ),
                    ),
                    Text(
                      "Contact our privacy & security team",
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.onSurfaceSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: () => _launchURL("mailto:privacy@ghumodriver.com"),
                style: TextButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: AppColors.onPrimary,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: const Text(
                  "Contact",
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Security Badge
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.success.withOpacity(0.1),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.success.withOpacity(0.2)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.success.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.verified_user_rounded,
                  color: AppColors.success,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text(
                      "We Do Not Sell Your Data",
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: AppColors.success,
                        fontSize: 14,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      "Your personal information is never sold to third parties",
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.onSurfaceSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // App Version
        const Text(
          "App Version 2.1.0",
          style: TextStyle(fontSize: 12, color: AppColors.onSurfaceTertiary),
        ),
        const SizedBox(height: 4),
        const Text(
          "Last updated: January 2025",
          style: TextStyle(fontSize: 11, color: AppColors.onSurfaceTertiary),
        ),
      ],
    );
  }

  // ===== HELPER WIDGETS =====

  Widget _buildSection({
    required String title,
    required IconData icon,
    required Color iconColor,
    required List<Widget> children,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 12),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: iconColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 16, color: iconColor),
              ),
              const SizedBox(width: 10),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.onSurface,
                  letterSpacing: -0.3,
                ),
              ),
            ],
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.divider),
            boxShadow: [
              BoxShadow(
                color: AppColors.onSurface.withOpacity(0.04),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Column(children: children),
          ),
        ),
      ],
    );
  }

  Widget _buildSettingsTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    Widget? trailing,
    VoidCallback? onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap?.call();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: iconColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: iconColor, size: 22),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppColors.onSurface,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.onSurfaceSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              trailing ??
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: AppColors.divider,
                    size: 22,
                  ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    Widget? trailing,
    VoidCallback? onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap?.call();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: iconColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: iconColor, size: 22),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppColors.onSurface,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.onSurfaceSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              trailing ??
                  Icon(
                    Icons.info_outline_rounded,
                    color: AppColors.onSurfaceTertiary,
                    size: 20,
                  ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPermissionTile({
    required IconData icon,
    required String title,
    required String description,
    required bool isGranted,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: AppColors.primary, size: 22),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.onSurface,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.onSurfaceSecondary,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: isGranted
                  ? AppColors.success.withOpacity(0.1)
                  : AppColors.error.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isGranted ? Icons.check_circle_rounded : Icons.cancel_rounded,
                  size: 14,
                  color: isGranted ? AppColors.success : AppColors.error,
                ),
                const SizedBox(width: 4),
                Text(
                  isGranted ? "Granted" : "Denied",
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isGranted ? AppColors.success : AppColors.error,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDangerTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          HapticFeedback.mediumImpact();
          onTap();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.error.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: AppColors.error, size: 22),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppColors.error,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.error.withOpacity(0.7),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: AppColors.error.withOpacity(0.5),
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDivider() {
    return const Divider(
      height: 1,
      indent: 72,
      endIndent: 20,
      color: AppColors.divider,
    );
  }

  Widget _buildVerifiedBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.success.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: const [
          Icon(Icons.verified_rounded, color: AppColors.success, size: 14),
          SizedBox(width: 4),
          Text(
            "Verified",
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.success,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActiveBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.primary.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: const BoxDecoration(
              color: AppColors.primary,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          const Text(
            "Active",
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.primary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusDot(bool active) {
    final color = active ? AppColors.success : AppColors.warning;
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.4),
            blurRadius: 6,
            spreadRadius: 1,
          ),
        ],
      ),
    );
  }

  Widget _buildExternalLinkIcon() {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Icon(
        Icons.open_in_new_rounded,
        size: 16,
        color: AppColors.onSurfaceSecondary,
      ),
    );
  }

  Widget _buildLoadingOverlay() {
    return Container(
      color: AppColors.onSurface.withOpacity(0.4),
      child: Center(
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: AppColors.onSurface.withOpacity(0.1),
                blurRadius: 20,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: const [
              CircularProgressIndicator(color: AppColors.primary),
              SizedBox(height: 16),
              Text(
                "Please wait...",
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: AppColors.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ===== BOTTOM SHEETS =====

  void _showBottomSheet({
    required String title,
    required IconData icon,
    required Widget content,
    List<Widget>? actions,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        decoration: const BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.divider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(24),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(icon, color: AppColors.primary, size: 24),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: AppColors.onSurface,
                        letterSpacing: -0.5,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(ctx),
                    icon: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.close_rounded,
                        size: 18,
                        color: AppColors.onSurfaceSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: content,
              ),
            ),
            if (actions != null)
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Row(children: _buildActionButtons(actions)),
                ),
              ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildActionButtons(List<Widget> actions) {
    List<Widget> result = [];
    for (int i = 0; i < actions.length; i++) {
      result.add(Expanded(child: actions[i]));
      if (i < actions.length - 1) {
        result.add(const SizedBox(width: 12));
      }
    }
    return result;
  }

  Widget _buildInfoCard({
    required IconData icon,
    required String title,
    required String description,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    color: AppColors.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.onSurfaceSecondary,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBulletPoint(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 6),
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 14,
                color: AppColors.onSurface,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ===== LOGIN METHOD SHEET =====
  void _showLoginMethodSheet() {
    _showBottomSheet(
      title: "Login Method",
      icon: Icons.phonelink_lock_rounded,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildInfoCard(
            icon: Icons.sms_rounded,
            title: "OTP-Based Authentication",
            description:
                "We use One-Time Password (OTP) sent to your registered phone number for secure login.",
            color: AppColors.success,
          ),
          const SizedBox(height: 16),
          const Text(
            "How it works:",
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: AppColors.onSurface,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 12),
          _buildBulletPoint("Enter your registered phone number"),
          _buildBulletPoint("Receive a 6-digit OTP via SMS"),
          _buildBulletPoint("Enter the OTP to verify your identity"),
          _buildBulletPoint("Access granted upon successful verification"),
          const SizedBox(height: 16),
          _buildInfoCard(
            icon: Icons.security_rounded,
            title: "Why OTP is Secure",
            description:
                "OTPs expire quickly and can only be used once, making unauthorized access extremely difficult.",
            color: AppColors.primary,
          ),
          const SizedBox(height: 24),
        ],
      ),
      actions: [
        ElevatedButton(
          onPressed: () => Navigator.pop(context),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: AppColors.onPrimary,
            padding: const EdgeInsets.symmetric(vertical: 16),
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          child: const Text(
            "Got It",
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }

  // ===== SESSIONS SHEET =====
  void _showSessionsSheet() {
    _showBottomSheet(
      title: "Active Sessions",
      icon: Icons.devices_rounded,
      content: Column(
        children: [
          _buildSessionItem(
            device: "This Device",
            info: "Android • Active now",
            icon: Icons.smartphone_rounded,
            isCurrentDevice: true,
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.warning.withOpacity(0.1),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.warning.withOpacity(0.3)),
            ),
            child: Row(
              children: const [
                Icon(Icons.info_outline_rounded, color: AppColors.warning),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    "Sign out from devices you don't recognize for better security.",
                    style: TextStyle(fontSize: 13, color: AppColors.onSurface),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
      actions: [
        OutlinedButton(
          onPressed: () => Navigator.pop(context),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
            side: const BorderSide(color: AppColors.divider),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          child: const Text(
            "Close",
            style: TextStyle(
              color: AppColors.onSurfaceSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        ElevatedButton(
          onPressed: () {
            Navigator.pop(context);
            _showLogoutAllSheet();
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.error,
            foregroundColor: AppColors.onPrimary,
            padding: const EdgeInsets.symmetric(vertical: 16),
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          child: const Text(
            "Sign Out All",
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }

  Widget _buildSessionItem({
    required String device,
    required String info,
    required IconData icon,
    required bool isCurrentDevice,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isCurrentDevice
            ? AppColors.success.withOpacity(0.1)
            : AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isCurrentDevice
              ? AppColors.success.withOpacity(0.3)
              : AppColors.divider,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: isCurrentDevice
                  ? AppColors.success.withOpacity(0.2)
                  : AppColors.background,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              icon,
              color: isCurrentDevice
                  ? AppColors.success
                  : AppColors.onSurfaceSecondary,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      device,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        color: AppColors.onSurface,
                      ),
                    ),
                    if (isCurrentDevice) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.success,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          "Current",
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: AppColors.onPrimary,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  info,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.onSurfaceSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ===== LIVE LOCATION SHEET =====
  void _showLiveLocationSheet() {
    _showBottomSheet(
      title: "Live Location Usage",
      icon: Icons.my_location_rounded,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.success.withOpacity(0.1),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.success.withOpacity(0.2)),
            ),
            child: Row(
              children: const [
                Icon(Icons.info_rounded, color: AppColors.success),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    "Your location is only tracked when you are ONLINE and available for rides.",
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: AppColors.success,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            "When we use your location:",
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: AppColors.onSurface,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 12),
          _buildInfoCard(
            icon: Icons.wifi_tethering_rounded,
            title: "When You're Online",
            description:
                "Your location is used to match you with nearby ride requests.",
            color: AppColors.primary,
          ),
          const SizedBox(height: 12),
          _buildInfoCard(
            icon: Icons.route_rounded,
            title: "During Active Trips",
            description:
                "Real-time tracking for navigation, ETA calculation, and customer visibility.",
            color: AppColors.success,
          ),
          const SizedBox(height: 12),
          _buildInfoCard(
            icon: Icons.shield_rounded,
            title: "For Safety",
            description:
                "Location data helps in emergency situations and dispute resolution.",
            color: AppColors.warning,
          ),
          const SizedBox(height: 12),
          _buildInfoCard(
            icon: Icons.cloud_off_rounded,
            title: "When You Go Offline",
            description:
                "Location tracking stops immediately when you go offline.",
            color: AppColors.onSurfaceSecondary,
          ),
          const SizedBox(height: 24),
        ],
      ),
      actions: [
        ElevatedButton(
          onPressed: () => Navigator.pop(context),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: AppColors.onPrimary,
            padding: const EdgeInsets.symmetric(vertical: 16),
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          child: const Text(
            "Understood",
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }

  // ===== BACKGROUND LOCATION SHEET =====
  void _showBackgroundLocationSheet() {
    _showBottomSheet(
      title: "Background Location",
      icon: Icons.location_searching_rounded,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.warning.withOpacity(0.1),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.warning.withOpacity(0.2)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Icon(Icons.warning_amber_rounded, color: AppColors.warning),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    "Location is collected even when the app is running in the background while you are ONLINE.",
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: AppColors.warning,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            "Why we need background location:",
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: AppColors.onSurface,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 12),
          _buildBulletPoint(
            "To keep you visible for ride requests when app is minimized",
          ),
          _buildBulletPoint(
            "To provide accurate navigation during ongoing trips",
          ),
          _buildBulletPoint(
            "To ensure continuous service without interruptions",
          ),
          _buildBulletPoint("For safety monitoring during active rides"),
          const SizedBox(height: 16),
          _buildInfoCard(
            icon: Icons.battery_saver_rounded,
            title: "Battery Optimization",
            description:
                "We use efficient location tracking to minimize battery drain.",
            color: AppColors.success,
          ),
          const SizedBox(height: 12),
          _buildInfoCard(
            icon: Icons.power_off_rounded,
            title: "Auto-Stop",
            description:
                "Background location stops automatically when you go offline or close the app.",
            color: AppColors.primary,
          ),
          const SizedBox(height: 24),
        ],
      ),
      actions: [
        ElevatedButton(
          onPressed: () => Navigator.pop(context),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: AppColors.onPrimary,
            padding: const EdgeInsets.symmetric(vertical: 16),
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          child: const Text(
            "Understood",
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }

  // ===== TRIP HISTORY INFO SHEET =====
  void _showTripHistoryInfoSheet() {
    _showBottomSheet(
      title: "Trip History",
      icon: Icons.history_rounded,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildInfoCard(
            icon: Icons.storage_rounded,
            title: "Secure Storage",
            description:
                "Your trip history is stored securely on our encrypted servers.",
            color: AppColors.primary,
          ),
          const SizedBox(height: 16),
          const Text(
            "What we store:",
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: AppColors.onSurface,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 12),
          _buildBulletPoint("Pickup and drop-off locations"),
          _buildBulletPoint("Trip date, time, and duration"),
          _buildBulletPoint("Fare and payment details"),
          _buildBulletPoint("Customer ratings and feedback"),
          _buildBulletPoint("Route taken during the trip"),
          const SizedBox(height: 16),
          const Text(
            "Why we keep this data:",
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: AppColors.onSurface,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 12),
          _buildBulletPoint("For your earnings calculation and history"),
          _buildBulletPoint("To resolve disputes if they arise"),
          _buildBulletPoint("For regulatory and legal compliance"),
          _buildBulletPoint("To improve our services"),
          const SizedBox(height: 24),
        ],
      ),
      actions: [
        ElevatedButton(
          onPressed: () => Navigator.pop(context),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: AppColors.onPrimary,
            padding: const EdgeInsets.symmetric(vertical: 16),
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          child: const Text(
            "Got It",
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }

  // ===== DOCUMENT STORAGE SHEET =====
  void _showDocumentStorageSheet() {
    _showBottomSheet(
      title: "Document Storage",
      icon: Icons.description_rounded,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Documents we collect and store:",
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: AppColors.onSurface,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 16),
          _buildDocumentItem(
            icon: Icons.badge_rounded,
            title: "Driving License (DL)",
            description: "For identity and driving eligibility verification",
          ),
          const SizedBox(height: 12),
          _buildDocumentItem(
            icon: Icons.directions_car_rounded,
            title: "Registration Certificate (RC)",
            description: "For vehicle ownership verification",
          ),
          const SizedBox(height: 12),
          _buildDocumentItem(
            icon: Icons.security_rounded,
            title: "Insurance Documents",
            description: "For valid insurance verification",
          ),
          const SizedBox(height: 12),
          _buildDocumentItem(
            icon: Icons.car_repair_rounded,
            title: "Vehicle Details",
            description: "Make, model, color, and registration number",
          ),
          const SizedBox(height: 12),
          _buildDocumentItem(
            icon: Icons.person_rounded,
            title: "Profile Photo",
            description: "For identity verification by customers",
          ),
          const SizedBox(height: 24),
        ],
      ),
      actions: [
        ElevatedButton(
          onPressed: () => Navigator.pop(context),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: AppColors.onPrimary,
            padding: const EdgeInsets.symmetric(vertical: 16),
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          child: const Text(
            "Got It",
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }

  Widget _buildDocumentItem({
    required IconData icon,
    required String title,
    required String description,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: AppColors.primary, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    color: AppColors.onSurface,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.onSurfaceSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ===== DOCUMENT SECURITY SHEET =====
  void _showDocumentSecuritySheet() {
    _showBottomSheet(
      title: "Document Security",
      icon: Icons.security_rounded,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildInfoCard(
            icon: Icons.lock_rounded,
            title: "Encrypted Storage",
            description:
                "All your documents are encrypted using industry-standard AES-256 encryption.",
            color: AppColors.success,
          ),
          const SizedBox(height: 12),
          _buildInfoCard(
            icon: Icons.verified_user_rounded,
            title: "Verification Only",
            description:
                "Your documents are used solely for verification purposes and regulatory compliance.",
            color: AppColors.primary,
          ),
          const SizedBox(height: 12),
          _buildInfoCard(
            icon: Icons.visibility_off_rounded,
            title: "Not Publicly Shared",
            description:
                "Your sensitive documents are never shared publicly or with third parties for marketing.",
            color: AppColors.warning,
          ),
          const SizedBox(height: 12),
          _buildInfoCard(
            icon: Icons.admin_panel_settings_rounded,
            title: "Restricted Access",
            description:
                "Only authorized personnel can access your documents for verification.",
            color: AppColors.onSurfaceSecondary,
          ),
          const SizedBox(height: 24),
        ],
      ),
      actions: [
        ElevatedButton(
          onPressed: () => Navigator.pop(context),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: AppColors.onPrimary,
            padding: const EdgeInsets.symmetric(vertical: 16),
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          child: const Text(
            "Got It",
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }

  // ===== VERIFICATION STATUS SHEET =====
  void _showVerificationStatusSheet() {
    _showBottomSheet(
      title: "Verification Status",
      icon: Icons.verified_user_rounded,
      content: Column(
        children: [
          _buildVerificationItem(
            name: "Driving License",
            status: "Verified",
            expiry: "Valid until Dec 2025",
            icon: Icons.badge_rounded,
            isVerified: true,
          ),
          const SizedBox(height: 12),
          _buildVerificationItem(
            name: "Vehicle RC",
            status: "Verified",
            expiry: "Valid until Mar 2025",
            icon: Icons.directions_car_rounded,
            isVerified: true,
          ),
          const SizedBox(height: 12),
          _buildVerificationItem(
            name: "Insurance",
            status: "Expiring Soon",
            expiry: "Expires in 2 months",
            icon: Icons.security_rounded,
            isVerified: false,
            isWarning: true,
          ),
          const SizedBox(height: 12),
          _buildVerificationItem(
            name: "Profile Photo",
            status: "Verified",
            expiry: "Updated 3 months ago",
            icon: Icons.person_rounded,
            isVerified: true,
          ),
          const SizedBox(height: 24),
        ],
      ),
      actions: [
        ElevatedButton(
          onPressed: () => Navigator.pop(context),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: AppColors.onPrimary,
            padding: const EdgeInsets.symmetric(vertical: 16),
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          child: const Text(
            "Done",
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }

  Widget _buildVerificationItem({
    required String name,
    required String status,
    required String expiry,
    required IconData icon,
    required bool isVerified,
    bool isWarning = false,
  }) {
    final color = isWarning
        ? AppColors.warning
        : (isVerified ? AppColors.success : AppColors.error);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    color: AppColors.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  expiry,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.onSurfaceSecondary,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              status,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ===== BANK PROTECTION SHEET =====
  void _showBankProtectionSheet() {
    _showBottomSheet(
      title: "Bank Details Protection",
      icon: Icons.account_balance_rounded,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildInfoCard(
            icon: Icons.lock_rounded,
            title: "Encrypted Storage",
            description:
                "Your bank account details are encrypted using bank-grade security protocols.",
            color: AppColors.success,
          ),
          const SizedBox(height: 12),
          _buildInfoCard(
            icon: Icons.payments_rounded,
            title: "Used Only for Payouts",
            description:
                "Bank details are used exclusively for transferring your earnings.",
            color: AppColors.primary,
          ),
          const SizedBox(height: 12),
          _buildInfoCard(
            icon: Icons.visibility_off_rounded,
            title: "Never Shared",
            description:
                "Your bank information is never shared with third parties or customers.",
            color: AppColors.warning,
          ),
          const SizedBox(height: 16),
          const Text(
            "Security measures:",
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: AppColors.onSurface,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 12),
          _buildBulletPoint("256-bit SSL encryption for all transactions"),
          _buildBulletPoint("PCI DSS compliant payment processing"),
          _buildBulletPoint("Regular security audits and monitoring"),
          _buildBulletPoint("Fraud detection and prevention systems"),
          const SizedBox(height: 24),
        ],
      ),
      actions: [
        ElevatedButton(
          onPressed: () => Navigator.pop(context),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: AppColors.onPrimary,
            padding: const EdgeInsets.symmetric(vertical: 16),
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          child: const Text(
            "Got It",
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }

  // ===== PAYMENT HISTORY INFO SHEET =====
  void _showPaymentHistoryInfoSheet() {
    _showBottomSheet(
      title: "Payment History",
      icon: Icons.receipt_long_rounded,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildInfoCard(
            icon: Icons.history_rounded,
            title: "Transaction Records",
            description:
                "All your earnings and payouts are recorded securely for your reference.",
            color: AppColors.primary,
          ),
          const SizedBox(height: 16),
          const Text(
            "What we record:",
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: AppColors.onSurface,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 12),
          _buildBulletPoint("Trip earnings and commissions"),
          _buildBulletPoint("Bonus and incentive payments"),
          _buildBulletPoint("Payout dates and amounts"),
          _buildBulletPoint("Tax-related information"),
          const SizedBox(height: 16),
          const Text(
            "Why we keep this data:",
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: AppColors.onSurface,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 12),
          _buildBulletPoint("For your financial records and tax purposes"),
          _buildBulletPoint("To resolve payment disputes"),
          _buildBulletPoint("For regulatory compliance"),
          const SizedBox(height: 24),
        ],
      ),
      actions: [
        ElevatedButton(
          onPressed: () => Navigator.pop(context),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: AppColors.onPrimary,
            padding: const EdgeInsets.symmetric(vertical: 16),
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          child: const Text(
            "Got It",
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }

  // ===== DATA COLLECTION SHEET =====
  void _showDataCollectionSheet() {
    _showBottomSheet(
      title: "Data Collection",
      icon: Icons.data_usage_rounded,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Information we collect:",
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: AppColors.onSurface,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 16),
          _buildDataCollectionItem(
            Icons.phone_rounded,
            "Phone Number",
            "For account verification and communication",
          ),
          _buildDataCollectionItem(
            Icons.email_rounded,
            "Email Address",
            "For receipts and important notifications",
          ),
          _buildDataCollectionItem(
            Icons.person_rounded,
            "Personal Details",
            "Name, photo for profile identification",
          ),
          _buildDataCollectionItem(
            Icons.directions_car_rounded,
            "Vehicle Info",
            "Make, model, registration for ride matching",
          ),
          _buildDataCollectionItem(
            Icons.location_on_rounded,
            "Live Location",
            "Real-time tracking when online",
          ),
          _buildDataCollectionItem(
            Icons.history_rounded,
            "Trip History",
            "Completed rides and earnings",
          ),
          _buildDataCollectionItem(
            Icons.phone_android_rounded,
            "Device Information",
            "For app optimization and security",
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.success.withOpacity(0.1),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.success.withOpacity(0.2)),
            ),
            child: Row(
              children: const [
                Icon(Icons.verified_user_rounded, color: AppColors.success),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    "We do NOT sell your personal data to third parties.",
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.success,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
      actions: [
        ElevatedButton(
          onPressed: () => Navigator.pop(context),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: AppColors.onPrimary,
            padding: const EdgeInsets.symmetric(vertical: 16),
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          child: const Text(
            "Understood",
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }

  Widget _buildDataCollectionItem(
    IconData icon,
    String title,
    String description,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: AppColors.primary, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    color: AppColors.onSurface,
                    fontSize: 14,
                  ),
                ),
                Text(
                  description,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.onSurfaceSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ===== DATA SHARING SHEET =====
  void _showDataSharingSheet() {
    _showBottomSheet(
      title: "Data Sharing",
      icon: Icons.share_rounded,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "How your data is shared:",
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: AppColors.onSurface,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 16),
          _buildInfoCard(
            icon: Icons.person_pin_circle_rounded,
            title: "With Customers During Rides",
            description:
                "Your name, photo, vehicle details, and live location are shared with customers during active rides for safety and identification.",
            color: AppColors.primary,
          ),
          const SizedBox(height: 12),
          _buildInfoCard(
            icon: Icons.gavel_rounded,
            title: "With Authorities (If Required)",
            description:
                "Data may be shared with law enforcement or regulatory bodies when required by law or court order.",
            color: AppColors.warning,
          ),
          const SizedBox(height: 12),
          _buildInfoCard(
            icon: Icons.block_rounded,
            title: "NOT Shared for Advertising",
            description:
                "Your personal data is never shared with third parties for advertising or marketing purposes.",
            color: AppColors.success,
          ),
          const SizedBox(height: 12),
          _buildInfoCard(
            icon: Icons.support_agent_rounded,
            title: "With Service Providers",
            description:
                "Limited data shared with payment processors and map services to provide core functionality.",
            color: AppColors.onSurfaceSecondary,
          ),
          const SizedBox(height: 24),
        ],
      ),
      actions: [
        ElevatedButton(
          onPressed: () => Navigator.pop(context),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: AppColors.onPrimary,
            padding: const EdgeInsets.symmetric(vertical: 16),
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          child: const Text(
            "Understood",
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }

  // ===== DATA RETENTION SHEET =====
  void _showDataRetentionSheet() {
    _showBottomSheet(
      title: "Data Retention",
      icon: Icons.access_time_rounded,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "How long we keep your data:",
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: AppColors.onSurface,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 16),
          _buildRetentionItem(
            title: "Account Information",
            duration: "Until account deletion",
            description: "Name, phone, email, profile photo",
          ),
          const SizedBox(height: 12),
          _buildRetentionItem(
            title: "Trip History",
            duration: "7 years",
            description: "Required for tax and legal compliance",
          ),
          const SizedBox(height: 12),
          _buildRetentionItem(
            title: "Payment Records",
            duration: "7 years",
            description: "Required for financial regulations",
          ),
          const SizedBox(height: 12),
          _buildRetentionItem(
            title: "Location Data",
            duration: "90 days",
            description: "After trip completion for dispute resolution",
          ),
          const SizedBox(height: 12),
          _buildRetentionItem(
            title: "Documents",
            duration: "Until account deletion + 1 year",
            description: "For regulatory compliance",
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Icon(Icons.info_outline_rounded, color: AppColors.primary),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    "After deletion request, most data is removed within 30 days. Some data may be retained longer for legal compliance.",
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.onSurface,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
      actions: [
        ElevatedButton(
          onPressed: () => Navigator.pop(context),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: AppColors.onPrimary,
            padding: const EdgeInsets.symmetric(vertical: 16),
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          child: const Text(
            "Got It",
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }

  Widget _buildRetentionItem({
    required String title,
    required String duration,
    required String description,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.schedule_rounded,
              color: AppColors.primary,
              size: 20,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    color: AppColors.onSurface,
                    fontSize: 14,
                  ),
                ),
                Text(
                  description,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.onSurfaceSecondary,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: AppColors.warning.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              duration,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppColors.warning,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ===== DOWNLOAD DATA SHEET =====
  void _showDownloadDataSheet() {
    _showBottomSheet(
      title: "Download Your Data",
      icon: Icons.download_rounded,
      content: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppColors.primary.withOpacity(0.1),
                  AppColors.primary.withOpacity(0.05),
                ],
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: const [
                Icon(
                  Icons.folder_zip_rounded,
                  size: 48,
                  color: AppColors.primary,
                ),
                SizedBox(height: 16),
                Text(
                  "Export Your Data",
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppColors.onSurface,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  "We'll prepare a copy of your data and send it to your registered email within 7 days.",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: AppColors.onSurfaceSecondary,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const Align(
            alignment: Alignment.centerLeft,
            child: Text(
              "What's included:",
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: AppColors.onSurface,
              ),
            ),
          ),
          const SizedBox(height: 12),
          _buildBulletPoint("Profile information"),
          _buildBulletPoint("Complete trip history"),
          _buildBulletPoint("Earnings and payment records"),
          _buildBulletPoint("Ratings and reviews"),
          _buildBulletPoint("Account activity log"),
          const SizedBox(height: 24),
        ],
      ),
      actions: [
        OutlinedButton(
          onPressed: () => Navigator.pop(context),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
            side: const BorderSide(color: AppColors.divider),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          child: const Text(
            "Cancel",
            style: TextStyle(
              color: AppColors.onSurfaceSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        ElevatedButton(
          onPressed: () {
            Navigator.pop(context);
            _requestDataExport();
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: AppColors.onPrimary,
            padding: const EdgeInsets.symmetric(vertical: 16),
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          child: const Text(
            "Request Export",
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }

  // ===== SECURITY PRACTICES SHEET =====
  void _showSecurityPracticesSheet() {
    _showBottomSheet(
      title: "Security Practices",
      icon: Icons.https_rounded,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildInfoCard(
            icon: Icons.https_rounded,
            title: "HTTPS Encryption",
            description:
                "All data transmitted between your device and our servers is encrypted using HTTPS/TLS protocols.",
            color: AppColors.success,
          ),
          const SizedBox(height: 12),
          _buildInfoCard(
            icon: Icons.storage_rounded,
            title: "Secure Servers",
            description:
                "Your data is stored on secure, encrypted servers with restricted access controls.",
            color: AppColors.primary,
          ),
          const SizedBox(height: 12),
          _buildInfoCard(
            icon: Icons.security_rounded,
            title: "Regular Audits",
            description:
                "We conduct regular security audits and vulnerability assessments.",
            color: AppColors.warning,
          ),
          const SizedBox(height: 12),
          _buildInfoCard(
            icon: Icons.password_rounded,
            title: "Access Controls",
            description:
                "Strict access controls ensure only authorized personnel can access sensitive data.",
            color: AppColors.onSurfaceSecondary,
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.success.withOpacity(0.1),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.success.withOpacity(0.2)),
            ),
            child: Row(
              children: const [
                Icon(Icons.verified_rounded, color: AppColors.success),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    "We follow industry best practices for data security and privacy.",
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: AppColors.success,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
      actions: [
        ElevatedButton(
          onPressed: () => Navigator.pop(context),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: AppColors.onPrimary,
            padding: const EdgeInsets.symmetric(vertical: 16),
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          child: const Text(
            "Got It",
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }

  // ===== LOGOUT ALL SHEET =====
  void _showLogoutAllSheet() {
    _showBottomSheet(
      title: "Logout From All Devices",
      icon: Icons.logout_rounded,
      content: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppColors.error.withOpacity(0.08),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.error.withOpacity(0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.devices_rounded,
                    size: 40,
                    color: AppColors.error,
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  "End all active sessions?",
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppColors.onSurface,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  "This will sign you out from all devices including this one. You'll need to sign in again.",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: AppColors.onSurfaceSecondary,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
      actions: [
        OutlinedButton(
          onPressed: () => Navigator.pop(context),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
            side: const BorderSide(color: AppColors.divider),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          child: const Text(
            "Cancel",
            style: TextStyle(
              color: AppColors.onSurfaceSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        ElevatedButton(
          onPressed: () {
            Navigator.pop(context);
            _logoutAllDevices();
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.error,
            foregroundColor: AppColors.onPrimary,
            padding: const EdgeInsets.symmetric(vertical: 16),
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          child: const Text(
            "Logout All",
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }

  // ===== DELETE ACCOUNT SHEET =====
  void _showDeleteAccountSheet() {
    final confirmController = TextEditingController();

    _showBottomSheet(
      title: "Delete Account",
      icon: Icons.delete_forever_rounded,
      content: StatefulBuilder(
        builder: (context, setSheetState) => Column(
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.error.withOpacity(0.08),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.error.withOpacity(0.2)),
              ),
              child: Column(
                children: const [
                  Icon(
                    Icons.warning_amber_rounded,
                    size: 48,
                    color: AppColors.error,
                  ),
                  SizedBox(height: 16),
                  Text(
                    "This action cannot be undone!",
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AppColors.error,
                    ),
                  ),
                  SizedBox(height: 12),
                  Text(
                    "Deleting your account will permanently remove:",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      color: AppColors.onSurfaceSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _buildBulletPoint("Your profile and personal information"),
            _buildBulletPoint("All trip history and earnings data"),
            _buildBulletPoint("Uploaded documents and verifications"),
            _buildBulletPoint("Ratings and reviews"),
            _buildBulletPoint("Access to pending payouts"),
            const SizedBox(height: 20),
            TextField(
              controller: confirmController,
              onChanged: (value) => setSheetState(() {}),
              decoration: InputDecoration(
                labelText: 'Type "DELETE" to confirm',
                labelStyle: const TextStyle(
                  color: AppColors.onSurfaceSecondary,
                ),
                filled: true,
                fillColor: AppColors.surface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(
                    color: AppColors.error,
                    width: 2,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
      actions: [
        OutlinedButton(
          onPressed: () => Navigator.pop(context),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
            side: const BorderSide(color: AppColors.divider),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          child: const Text(
            "Cancel",
            style: TextStyle(
              color: AppColors.onSurfaceSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        ElevatedButton(
          onPressed: () {
            if (confirmController.text == "DELETE") {
              Navigator.pop(context);
              _deleteAccount();
            } else {
              _showSnackBar("Please type DELETE to confirm", isError: true);
            }
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.error,
            foregroundColor: AppColors.onPrimary,
            padding: const EdgeInsets.symmetric(vertical: 16),
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          child: const Text(
            "Delete Account",
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }

  // ===== API METHODS =====

  String _getPhoneNumber() {
    try {
      final user = FirebaseAuth.instance.currentUser;
      return user?.phoneNumber ?? "Not verified";
    } catch (e) {
      return "Error loading";
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              isError
                  ? Icons.error_outline_rounded
                  : Icons.check_circle_rounded,
              color: AppColors.onPrimary,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: isError ? AppColors.error : AppColors.success,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  Future<void> _logoutAllDevices() async {
    setState(() => _isLoading = true);
    try {
      await FirebaseAuth.instance.signOut();
      _showSnackBar("Signed out from all devices");
    } catch (e) {
      _showSnackBar("Error: $e", isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _requestDataExport() async {
    setState(() => _isLoading = true);
    try {
      await Future.delayed(const Duration(seconds: 1));
      debugPrint('Data export requested');
      _showSnackBar("Check your email for the download link");
    } catch (e) {
      _showSnackBar("Error: $e", isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _deleteAccount() async {
    setState(() => _isLoading = true);
    try {
      await FirebaseAuth.instance.currentUser?.delete();
      await FirebaseAuth.instance.signOut();
      _showSnackBar("Account deleted permanently");
    } catch (e) {
      _showSnackBar("Error: $e", isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _launchURL(String url) async {
    try {
      final Uri uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      _showSnackBar("Cannot open link", isError: true);
    }
  }
}
