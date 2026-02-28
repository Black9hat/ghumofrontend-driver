// driver_profile_page.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:drivergoo/screens/driver_login_page.dart';
import 'package:drivergoo/config.dart';
import 'driver_privacy_security_page.dart';

// ============================================================================
// APP COLORS - Unchanged
// ============================================================================
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

// ============================================================================
// APP TEXT STYLES - Unchanged
// ============================================================================
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

  static TextStyle get button => GoogleFonts.plusJakartaSans(
    fontSize: 16,
    fontWeight: FontWeight.w700,
    color: AppColors.onSurface,
  );
}

// ============================================================================
// DRIVER PROFILE PAGE
// ============================================================================
class DriverProfilePage extends StatefulWidget {
  final String driverId;

  const DriverProfilePage({Key? key, required this.driverId}) : super(key: key);

  @override
  State<DriverProfilePage> createState() => _DriverProfilePageState();
}

class _DriverProfilePageState extends State<DriverProfilePage> {
  // ---- Constants ----
  static String _backendUrl = AppConfig.backendBaseUrl;
  static const Duration _apiTimeout = Duration(seconds: 15);

  // ---- State Variables ----
  bool _isLoading = true;
  bool _isLoggingOut = false;
  bool _isSavingEmail = false;
  Map<String, dynamic>? _driverData;
  List<Map<String, dynamic>> _documents = [];
  String? _errorMessage;

  // Email controller for editable email field
  late TextEditingController _emailController;

  // ---- Lifecycle ----
  @override
  void initState() {
    super.initState();
    _emailController = TextEditingController();
    _fetchDriverProfile();
  }

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  // ====================================================================
  // SAFE UTILITIES
  // ====================================================================

  /// Safe setState that checks if widget is still mounted
  void _safeSetState(VoidCallback fn) {
    if (mounted) {
      setState(fn);
    }
  }

  String _getString(
    Map<String, dynamic>? map,
    String key, [
    String defaultValue = '',
  ]) {
    if (map == null) return defaultValue;
    final value = map[key];
    if (value == null) return defaultValue;
    return value.toString();
  }

  // ====================================================================
  // API CALLS
  // ====================================================================

  Future<void> _fetchDriverProfile() async {
    _safeSetState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw Exception("User not authenticated");
      }

      final token = await user.getIdToken();
      if (!mounted) return;

      if (token == null || token.isEmpty) {
        throw Exception("Failed to get authentication token");
      }

      final headers = {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      };

      final profileResponse = await http
          .get(Uri.parse('$_backendUrl/api/driver/profile'), headers: headers)
          .timeout(_apiTimeout);

      if (!mounted) return;

      http.Response? docsResponse;
      try {
        docsResponse = await http
            .get(
              Uri.parse('$_backendUrl/api/driver/documents/${widget.driverId}'),
              headers: headers,
            )
            .timeout(_apiTimeout);
      } catch (e) {
        debugPrint('Documents fetch error (non-critical): $e');
      }

      if (!mounted) return;

      if (profileResponse.statusCode == 200) {
        Map<String, dynamic>? profileData;
        try {
          final decoded = jsonDecode(profileResponse.body);
          if (decoded is Map<String, dynamic>) {
            profileData = decoded;
          }
        } catch (e) {
          debugPrint('Profile JSON parsing error: $e');
          throw Exception("Failed to parse profile data");
        }

        List<Map<String, dynamic>> docsList = [];
        if (docsResponse != null && docsResponse.statusCode == 200) {
          try {
            final decoded = jsonDecode(docsResponse.body);
            if (decoded is Map<String, dynamic>) {
              final rawDocs = decoded['docs'];
              if (rawDocs is List) {
                docsList = rawDocs
                    .where((item) => item is Map<String, dynamic>)
                    .map((item) => item as Map<String, dynamic>)
                    .toList();
              }
            }
          } catch (e) {
            debugPrint('Documents JSON parsing error (non-critical): $e');
          }
        }

        // Deduplicate documents: keep one per (docType, vehicleType), prefer best status
        final Map<String, Map<String, dynamic>> uniqueMap = {};
        int statusRank(String? s) {
          if (s == null) return 2;
          final t = s.toLowerCase();
          if (t == 'approved' || t == 'verified') return 4;
          if (t == 'pending') return 3;
          if (t == 'rejected') return 1;
          return 2;
        }

        for (final doc in docsList) {
          final rawType = doc['docType'] ?? doc['type'] ?? '';
          final docType = rawType.toString().trim();
          final vehicleRaw = doc['vehicleType'] ?? doc['vehicle'] ?? '';
          final vehicleType = vehicleRaw.toString().trim();
          final key = '${docType.toLowerCase()}::${vehicleType.toLowerCase()}';

          if (!uniqueMap.containsKey(key)) {
            uniqueMap[key] = doc;
          } else {
            final existing = uniqueMap[key]!;
            final existingRank = statusRank(existing['status']?.toString());
            final currentRank = statusRank(doc['status']?.toString());
            if (currentRank > existingRank) {
              uniqueMap[key] = doc;
            }
          }
        }

        final deduped = uniqueMap.values
            .map((e) => Map<String, dynamic>.from(e))
            .toList();

        _safeSetState(() {
          final driverRaw = profileData?['driver'];
          _driverData = driverRaw is Map<String, dynamic> ? driverRaw : null;
          _documents = deduped;
          _emailController.text = _getString(_driverData, 'email', '');
          _isLoading = false;
        });
      } else {
        throw Exception(
          "Failed to load profile (Status: ${profileResponse.statusCode})",
        );
      }
    } on TimeoutException {
      _safeSetState(() {
        _isLoading = false;
        _errorMessage = 'Request timed out. Please check your connection.';
      });
    } on FormatException {
      _safeSetState(() {
        _isLoading = false;
        _errorMessage = 'Invalid response from server.';
      });
    } catch (e) {
      _safeSetState(() {
        _isLoading = false;
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  // ====================================================================
  // HELPER METHODS
  // ====================================================================

  Color _getStatusColor(String? status) {
    final statusLower = (status ?? 'pending').toLowerCase().trim();
    switch (statusLower) {
      case 'approved':
      case 'verified':
        return AppColors.success;
      case 'rejected':
        return AppColors.error;
      default:
        return AppColors.warning;
    }
  }

  IconData _getStatusIcon(String? status) {
    final statusLower = (status ?? 'pending').toLowerCase().trim();
    switch (statusLower) {
      case 'approved':
      case 'verified':
        return Icons.check_circle;
      case 'rejected':
        return Icons.cancel;
      default:
        return Icons.pending;
    }
  }

  IconData _getVehicleIcon(String? vehicleType) {
    final type = (vehicleType ?? 'bike').toLowerCase().trim();
    switch (type) {
      case 'bike':
      case 'motorbike':
      case 'motorcycle':
        return Icons.two_wheeler;
      case 'auto':
      case 'autorickshaw':
      case 'rickshaw':
        return Icons.electric_rickshaw;
      case 'car':
      case 'taxi':
      case 'auto_car':
        return Icons.directions_car;
      default:
        return Icons.directions_car;
    }
  }

  Future<void> _saveEmail() async {
    final newEmail = _emailController.text.trim();
    if (newEmail.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Email cannot be empty')));
      return;
    }

    _safeSetState(() => _isSavingEmail = true);

    try {
      _safeSetState(() {
        if (_driverData == null) _driverData = {};
        _driverData!['email'] = newEmail;
      });

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Email saved')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to save email: $e')));
    } finally {
      _safeSetState(() => _isSavingEmail = false);
    }
  }

  // ====================================================================
  // LOGOUT FLOW
  // ====================================================================

  Future<void> _performLogout() async {
    if (_isLoggingOut) return;

    _safeSetState(() => _isLoggingOut = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
      debugPrint("✅ SharedPreferences cleared");

      try {
        await FirebaseAuth.instance.signOut();
        debugPrint("✅ Firebase signed out");
      } catch (e) {
        debugPrint("⚠️ Firebase sign-out error (non-critical): $e");
      }

      await Future.delayed(const Duration(milliseconds: 250));

      if (!mounted) return;

      try {
        Navigator.of(context, rootNavigator: true).pop();
      } catch (_) {}

      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const DriverLoginPage()),
        (route) => false,
      );

      debugPrint("✅ Navigated to DriverLoginPage (logout complete)");
    } catch (e) {
      debugPrint("❌ Logout error: $e");

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Logout failed: ${e.toString()}'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      _safeSetState(() => _isLoggingOut = false);
    }
  }

  void _showLogoutDialog() {
    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(Icons.logout, color: AppColors.error),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Logout',
                style: AppTextStyles.heading3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        content: Text(
          'Are you sure you want to logout?',
          style: AppTextStyles.body1,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(
              'Cancel',
              style: AppTextStyles.button.copyWith(
                color: AppColors.onSurfaceSecondary,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(dialogContext);

              if (!mounted) return;

              showDialog(
                context: context,
                barrierDismissible: false,
                builder: (_) => Dialog(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Padding(
                    padding: EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 16),
                        Text("Logging out...", style: TextStyle(fontSize: 16)),
                      ],
                    ),
                  ),
                ),
              );

              await _performLogout();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: AppColors.onPrimary,
            ),
            child: Text(
              'Logout',
              style: AppTextStyles.button.copyWith(color: AppColors.onPrimary),
            ),
          ),
        ],
      ),
    );
  }

  // ====================================================================
  // BUILD METHODS
  // ====================================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        slivers: [
          _buildSliverAppBar(),
          SliverToBoxAdapter(
            child: _isLoading
                ? const SizedBox()
                : _errorMessage != null
                ? _buildErrorWidget()
                : _buildProfileContent(),
          ),
        ],
      ),
    );
  }

  // ✅ STEP 1: Increased expandedHeight from 220 to 260
  Widget _buildSliverAppBar() {
    return SliverAppBar(
      expandedHeight: 260, // ⬅️ STEP 1: Increased from 220
      pinned: true,
      backgroundColor: AppColors.primary,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back, color: AppColors.onPrimary),
        onPressed: () => Navigator.pop(context),
      ),
      flexibleSpace: FlexibleSpaceBar(
        background: _isLoading
            ? const Center(
                child: CircularProgressIndicator(color: AppColors.onPrimary),
              )
            : _buildProfileHeader(),
      ),
    );
  }

  // ✅ STEP 2, 3, 4: Complete profile header with all fixes
  Widget _buildProfileHeader() {
    final photoUrl = _getString(_driverData, 'photoUrl');
    final name = _getString(_driverData, 'name', 'Driver Name');
    final phone = _getString(_driverData, 'phone', '');

    // ✅ STEP 4: Calculate adaptive avatar size
    final screenWidth = MediaQuery.of(context).size.width;
    final avatarSize = (screenWidth * 0.25).clamp(80.0, 110.0);

    return Container(
      decoration: const BoxDecoration(
        image: DecorationImage(
          image: AssetImage('assets/images/banner_profile.png'),
          fit: BoxFit.cover,
        ),
      ),
      child: Container(
        // ✅ STEP 3: Reduced top padding from 60 to 40
        padding: const EdgeInsets.fromLTRB(20, 40, 20, 20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.white.withOpacity(0.05),
              Colors.black.withOpacity(0.12),
            ],
          ),
        ),
        // ✅ STEP 2: LayoutBuilder with SingleChildScrollView wrapper
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              physics: const NeverScrollableScrollPhysics(),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // ✅ STEP 4: ADAPTIVE PROFILE IMAGE with constraints
                    Container(
                      constraints: const BoxConstraints(
                        maxWidth: 110,
                        maxHeight: 110,
                      ),
                      width: avatarSize,
                      height: avatarSize,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 3),
                      ),
                      child: ClipOval(
                        child: photoUrl.isNotEmpty
                            ? Image.network(
                                photoUrl,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) =>
                                    _buildDefaultAvatar(avatarSize),
                              )
                            : _buildDefaultAvatar(avatarSize),
                      ),
                    ),

                    const SizedBox(height: 12),

                    // NAME (BIG + BOLD) - with overflow handling
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 6),

                    // PHONE NUMBER - with overflow handling using FittedBox
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          phone.isNotEmpty ? phone : 'Phone not available',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Colors.white.withOpacity(0.9),
                          ),
                        ),
                      ),
                    ),

                    // Add some bottom spacing for safety
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  // ✅ STEP 4: Updated default avatar to accept dynamic size
  Widget _buildDefaultAvatar([double? size]) {
    final avatarSize = size ?? 100.0;
    final iconSize = avatarSize * 0.6;

    return Container(
      width: avatarSize,
      height: avatarSize,
      color: AppColors.surface,
      child: Icon(
        Icons.person,
        size: iconSize,
        color: AppColors.onSurfaceSecondary,
      ),
    );
  }

  Widget _buildErrorWidget() {
    return Container(
      padding: const EdgeInsets.all(32),
      child: Column(
        children: [
          const Icon(Icons.error_outline, size: 64, color: AppColors.error),
          const SizedBox(height: 16),
          Text('Failed to load profile', style: AppTextStyles.heading3),
          const SizedBox(height: 8),
          Text(
            _errorMessage ?? 'Unknown error',
            style: AppTextStyles.body2,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _fetchDriverProfile,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.onPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileContent() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildPersonalInfoCard(),
          const SizedBox(height: 16),
          _buildVehicleInfoCard(),
          const SizedBox(height: 16),
          _buildDocumentsSection(),
          const SizedBox(height: 24),
          const SizedBox(height: 16),
          _buildPrivacyButton(),
          _buildLogoutButton(),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildPersonalInfoCard() {
    final email = _getString(_driverData, 'email', '');
    final phone = _getString(_driverData, 'phone', 'Not available');

    return _buildSectionCard(
      title: 'Personal Information',
      icon: Icons.person_outline,
      children: [
        // PHONE NUMBER ROW - with overflow handling
        _buildInfoRowFixed(Icons.phone, 'Phone Number', phone),
        const SizedBox(height: 12),

        // Email row with edit functionality - with overflow handling
        GestureDetector(
          onTap: () => _showEditEmailDialog(),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(
                Icons.email_outlined,
                size: 20,
                color: AppColors.onSurfaceSecondary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Email', style: AppTextStyles.caption),
                    const SizedBox(height: 4),
                    Text(
                      email.isNotEmpty ? email : 'Not provided',
                      style: AppTextStyles.body1,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(left: 8.0),
                child: Icon(
                  Icons.edit,
                  size: 18,
                  color: AppColors.onSurfaceTertiary,
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 12),
      ],
    );
  }

  Future<void> _showEditEmailDialog() async {
    if (!mounted) return;

    _emailController.text = _getString(_driverData, 'email', '');

    await showDialog(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              title: const Text('Edit Email'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      hintText: 'Enter email',
                      isDense: true,
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.of(dialogCtx).pop();
                  },
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () async {
                    setStateDialog(() {});
                    _safeSetState(() => _isSavingEmail = true);
                    try {
                      await _saveEmail();
                    } finally {
                      _safeSetState(() => _isSavingEmail = false);
                    }
                    if (!mounted) return;
                    Navigator.of(dialogCtx).pop();
                  },
                  child: _isSavingEmail
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildVehicleInfoCard() {
    final vehicleType = _getString(_driverData, 'vehicleType', 'bike');
    final vehicleNumber = _getString(_driverData, 'vehicleNumber', '');

    final vehicleIcon = _getVehicleIcon(vehicleType);

    return _buildSectionCard(
      title: 'Vehicle Information',
      icon: Icons.directions_car_outlined,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(vehicleIcon, size: 32, color: AppColors.primary),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Vehicle Type', style: AppTextStyles.caption),
                  const SizedBox(height: 4),
                  Text(
                    vehicleType.toUpperCase(),
                    style: AppTextStyles.heading3.copyWith(
                      color: AppColors.primary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),

        const SizedBox(height: 12),
        _buildInfoRowFixed(
          Icons.confirmation_number_outlined,
          'Vehicle Number',
          vehicleNumber.isNotEmpty ? vehicleNumber : 'Not provided',
        ),
      ],
    );
  }

  Widget _buildDocumentsSection() {
    return _buildSectionCard(
      title: 'Documents',
      icon: Icons.description_outlined,
      children: [
        if (_documents.isEmpty)
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Center(
              child: Column(
                children: [
                  const Icon(
                    Icons.description_outlined,
                    size: 48,
                    color: AppColors.onSurfaceTertiary,
                  ),
                  const SizedBox(height: 8),
                  Text('No documents uploaded', style: AppTextStyles.body2),
                ],
              ),
            ),
          )
        else
          Column(
            children: _documents.map((doc) {
              final docType = _getString(
                doc,
                'docType',
                _getString(doc, 'type', 'Document'),
              );
              final vehicleType = _getString(
                doc,
                'vehicleType',
                _getString(doc, 'vehicle', ''),
              );
              final status = _getString(doc, 'status', 'pending');
              final displayTitle = docType.toUpperCase();
              final subtitle = vehicleType.isNotEmpty
                  ? vehicleType.toUpperCase()
                  : null;

              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: _getStatusColor(status).withOpacity(0.3),
                    width: 2,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: _getStatusColor(status).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        _getStatusIcon(status),
                        color: _getStatusColor(status),
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            displayTitle,
                            style: AppTextStyles.body1,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          if (subtitle != null)
                            Text(
                              subtitle,
                              style: AppTextStyles.caption,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          Text(
                            status.toUpperCase(),
                            style: AppTextStyles.caption.copyWith(
                              color: _getStatusColor(status),
                              fontWeight: FontWeight.bold,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Icon(
                      Icons.arrow_forward_ios,
                      size: 16,
                      color: AppColors.onSurfaceTertiary,
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
      ],
    );
  }

  Widget _buildPrivacyButton() {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const DriverPrivacySecurityPage(),
            ),
          );
        },
        icon: const Icon(Icons.security),
        label: const Text('Privacy & Security'),
      ),
    );
  }

  Widget _buildLogoutButton() {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: _showLogoutDialog,
        icon: const Icon(Icons.logout),
        label: const Text('Logout'),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.error,
          side: const BorderSide(color: AppColors.error, width: 2),
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }

  Widget _buildSectionCard({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider),
        boxShadow: [
          BoxShadow(
            color: AppColors.onSurface.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
            ),
            child: Row(
              children: [
                Icon(icon, color: AppColors.primary, size: 24),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: AppTextStyles.heading3,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          // Content
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: children,
            ),
          ),
        ],
      ),
    );
  }

  /// Fixed info row that handles overflow properly for all devices
  Widget _buildInfoRowFixed(
    IconData icon,
    String label,
    String value, {
    Color? valueColor,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(icon, size: 20, color: AppColors.onSurfaceSecondary),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: AppTextStyles.caption,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              LayoutBuilder(
                builder: (context, constraints) {
                  return ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: constraints.maxWidth),
                    child: Text(
                      value,
                      style: AppTextStyles.body1.copyWith(color: valueColor),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      softWrap: true,
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}
