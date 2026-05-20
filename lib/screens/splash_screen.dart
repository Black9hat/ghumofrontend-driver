import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter/services.dart';
import 'package:drivergoo/services/fcm_service.dart';
import 'package:drivergoo/config.dart';
// 🔥 DRIVER ROLE SESSION IMPLEMENTATION
import 'package:drivergoo/services/session_manager.dart';

// Import your pages
import 'driver_login_page.dart';
import 'driver_details_page.dart';
import 'documents_review_page.dart';
import 'driver_dashboard_page.dart';

const MethodChannel _overlayChannel = MethodChannel('overlay_service');

class AppColors {
  static const Color primary = Color.fromARGB(255, 212, 120, 0);
  static const Color background = Colors.white;
  static const Color onSurface = Colors.black;
  static const Color onPrimary = Colors.white;
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({Key? key}) : super(key: key);

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  final String backendUrl = AppConfig.backendBaseUrl;

  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  String _statusMessage = "Initializing...";
  bool _showError = false;
  bool _isInitializing = false;

  String? _pendingOverlayAction;
  String? _pendingTripId;
  bool _shouldHideOverlay = false;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeIn),
    );
    _animationController.forward();
    _initializeApp();
  }

  Future<void> _hideOverlayIfNeeded() async {
    if (_shouldHideOverlay) {
      try {
        await _overlayChannel.invokeMethod('hide');
        print('🙈 Overlay hidden after processing action');
      } catch (e) {
        print('Could not hide overlay: $e');
      }
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  bool _isPlaceholderDriverName(String? name) {
    final normalized = name?.trim().toLowerCase() ?? '';
    return normalized.isEmpty ||
        normalized == 'new user' ||
        normalized == 'driver';
  }

  Future<void> _initializeApp() async {
    if (_isInitializing) return;
    _isInitializing = true;

    try {
      await Future.delayed(const Duration(milliseconds: 800));
      await _restoreDriverSession();
      await _checkOverlayActions();
      await _checkOverlayPermission();
      await _decideNavigationFromServer();
    } catch (e) {
      print("❌ Initialization error: $e");
      _showErrorAndRetry("Failed to initialize app. Please try again.");
    } finally {
      _isInitializing = false;
    }
  }

  Future<void> _restoreDriverSession() async {
    try {
      print('🔥 Restoring driver session...');
      final sessionRestored = await SessionManager().restoreSession();
      if (sessionRestored) {
        print('✅ Driver session restored successfully');
      } else {
        print('ℹ️ No previous session to restore');
      }
    } catch (e) {
      print('⚠️ Session restore error (non-critical): $e');
    }
  }

  Future<void> _checkOverlayActions() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final action = prefs.getString('flutter.overlay_action');
      final tripId = prefs.getString('flutter.overlay_trip_id');
      final actionTime = prefs.getInt('flutter.overlay_action_time') ?? 0;
      final now = DateTime.now().millisecondsSinceEpoch;
      final isRecent = (now - actionTime) < 60000;

      if (action != null && tripId != null && isRecent) {
        _pendingOverlayAction = action;
        _pendingTripId = tripId;
        _shouldHideOverlay = true;
        await prefs.remove('flutter.overlay_action');
        await prefs.remove('flutter.overlay_trip_id');
        await prefs.remove('flutter.overlay_action_time');
      }

      final pendingTripId = prefs.getString('pending_trip_id');
      final pendingAction = prefs.getString('pending_trip_action');
      final pendingTime = prefs.getInt('pending_trip_time') ?? 0;

      if (pendingTripId != null && (now - pendingTime) < 60000) {
        _pendingTripId ??= pendingTripId;
        _pendingOverlayAction ??= pendingAction;
        _shouldHideOverlay = true;
        await prefs.remove('pending_trip_id');
        await prefs.remove('pending_trip_action');
        await prefs.remove('pending_trip_time');
      }
    } catch (e) {
      print('Error checking overlay actions: $e');
    }
  }

  Future<void> _checkOverlayPermission() async {
    try {
      final hasPermission =
          await _overlayChannel.invokeMethod('checkPermission');
      if (hasPermission != true) {
        print('⚠️ Overlay permission not granted');
      } else {
        print('✅ Overlay permission granted');
      }
    } catch (e) {
      print('Error checking overlay permission: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 🔥 Session check using profile response — no new backend route needed.
  // Profile already returns currentDeviceId + sessionActive.
  // Compare with locally stored deviceId to detect force_logout.
  // Reliable fallback for Vivo/Xiaomi/OnePlus that block FCM to killed apps.
  // ═══════════════════════════════════════════════════════════════════════
  Future<bool> _isThisDeviceStillActive(Map<String, dynamic> driverData) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final myDeviceId = prefs.getString('deviceId') ??
          prefs.getString('appDeviceId') ?? '';

      if (myDeviceId.isEmpty) {
        print('⚠️ No local deviceId — skipping session check');
        return true; // first login, no device stored yet
      }

      final serverDeviceId = driverData['currentDeviceId']?.toString() ?? '';
      final sessionActive = driverData['sessionActive'] == true;

      print('🔍 Session check:');
      print('   My deviceId:     $myDeviceId');
      print('   Server deviceId: $serverDeviceId');
      print('   Session active:  $sessionActive');

      // If session is active but on a DIFFERENT device — we were force logged out
      if (sessionActive &&
          serverDeviceId.isNotEmpty &&
          serverDeviceId != myDeviceId) {
        print('🚨 Different device is now active — this device was force logged out');
        return false;
      }

      print('✅ This device is still the active session');
      return true;
    } catch (e) {
      print('⚠️ Session check error (non-critical): $e');
      return true; // never force logout on error
    }
  }

  Future<void> _decideNavigationFromServer() async {
    _updateStatus("Checking your session...");

    final prefs = await SharedPreferences.getInstance();

    try {
      final fbUser = FirebaseAuth.instance.currentUser;
      if (fbUser == null) {
        print("⚠️ No Firebase user → go to login");
        await prefs.clear();
        await _hideOverlayIfNeeded();
        _navigateToLogin();
        return;
      }

      final token = await fbUser.getIdToken();
      if (token == null) {
        print("❌ No Firebase token → session invalid");
        await prefs.clear();
        await _hideOverlayIfNeeded();
        _navigateToLogin();
        return;
      }

      _updateStatus("Loading your profile...");

      final response = await http
          .get(
            Uri.parse('$backendUrl/api/driver/profile'),
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 401 ||
          response.statusCode == 403 ||
          response.statusCode == 404) {
        print("❌ Session invalid / driver not found. Clearing local state.");
        await prefs.clear();
        await _hideOverlayIfNeeded();
        _navigateToLogin();
        return;
      }

      if (response.statusCode != 200) {
        print("⚠️ Unexpected profile response: ${response.statusCode}");
        _showErrorAndRetry(
            "Unable to contact server.\nPlease check your internet.");
        _scheduleAutoRetry();
        return;
      }

      final data = jsonDecode(response.body);
      final Map<String, dynamic> driver =
          (data['driver'] ?? data) as Map<String, dynamic>;

      final String driverId = driver['_id']?.toString() ?? "";
      final String role = driver['role']?.toString() ?? "";
      final bool isDriver = driver['isDriver'] == true;
      final String rawStatus =
          (driver['documentStatus'] ?? 'not_uploaded').toString();
      final String status = rawStatus.toLowerCase().trim();
      final String vehicleTypeFromServer =
          driver['vehicleType']?.toString() ?? "";
      final String nameFromServer =
          driver['name']?.toString().trim() ?? "";
      final String vehicleNumberFromServer =
          driver['vehicleNumber']?.toString().trim() ?? "";
      final bool docsApprovedFromServer = status == 'approved';

      // 🔥 SESSION CHECK — uses currentDeviceId from profile response
      // No new backend route needed — profile already has this field.
      // Catches force_logout on Vivo/Xiaomi/OnePlus where FCM is blocked.
      if (driverId.isNotEmpty && status == 'approved') {
        _updateStatus("Verifying session...");
        final deviceStillActive = await _isThisDeviceStillActive(driver);
        if (!deviceStillActive) {
          print('🚨 This device was logged out — redirecting to login');
          await prefs.clear();
          await FirebaseAuth.instance.signOut();
          await _hideOverlayIfNeeded();
          if (mounted) {
            _showForceLogoutDialog();
          }
          return;
        }
      }

      if (driverId.isNotEmpty) {
        await prefs.setString('driverId', driverId);
        final fcmToken = await FCMService.sendTokenToServer(driverId);
        if (fcmToken != null) {
          print('✅ FCM token registered: ${fcmToken.substring(0, 20)}...');
        }
        FCMService.listenForTokenRefresh(driverId);
      }

      await prefs.setBool('isLoggedIn', true);
      await prefs.setString('driverDocumentStatus', status);
      await prefs.setBool('docsApproved', docsApprovedFromServer);
      await prefs.setString('role', 'driver');
      if (vehicleTypeFromServer.isNotEmpty) {
        await prefs.setString('vehicleType', vehicleTypeFromServer);
      }
      if (!_isPlaceholderDriverName(nameFromServer)) {
        await prefs.setString('driverName', nameFromServer);
      }
      if (vehicleNumberFromServer.isNotEmpty) {
        await prefs.setString('vehicleNumber', vehicleNumberFromServer);
      }

      final String cachedVehicleType =
          prefs.getString('vehicleType')?.toString().trim() ?? '';
      final bool hasVehicleType =
          vehicleTypeFromServer.isNotEmpty || cachedVehicleType.isNotEmpty;
      final bool hasProfileDetails =
          nameFromServer.isNotEmpty && vehicleNumberFromServer.isNotEmpty;

      if (!isDriver ||
          driverId.isEmpty ||
          !hasVehicleType ||
          !hasProfileDetails) {
        print("➡️ Not a complete driver profile → DriverDocumentUploadPage");
        _updateStatus("Let's complete your driver profile...");
        await _hideOverlayIfNeeded();
        Future.delayed(const Duration(milliseconds: 500), () {
          if (driverId.isEmpty) {
            _navigateToLogin();
          } else {
            _navigateToDriverDetails(driverId);
          }
        });
        return;
      }

      if (status == 'approved') {
        print("✅ Driver docs APPROVED → Dashboard");

        Map<String, dynamic>? activeTripData;
        try {
          _updateStatus("Checking active trips...");
          activeTripData = await _checkForActiveTrip(driverId);
          if (activeTripData != null) {
            final tripId = activeTripData['tripId']?.toString();
            if (tripId != null && tripId.isNotEmpty) {
              await prefs.setString('activeTripId', tripId);
              await prefs.setBool('hasActiveTrip', true);
            }
          } else {
            await prefs.remove('activeTripId');
            await prefs.setBool('hasActiveTrip', false);
          }
        } catch (e) {
          print("⚠️ Failed to check active trip: $e");
          activeTripData = null;
        }

        if (_pendingOverlayAction == 'ACCEPT' && _pendingTripId != null) {
          print("⚡ Processing ACCEPT action for $_pendingTripId");
          _updateStatus("Accepting trip...");
          await _acceptTripFromOverlay(_pendingTripId!, driverId);
          activeTripData = await _checkForActiveTrip(driverId);
          await _hideOverlayIfNeeded();
        } else if (_pendingOverlayAction == 'REJECT' &&
            _pendingTripId != null) {
          await _hideOverlayIfNeeded();
        } else if (_pendingOverlayAction == 'TIMEOUT' &&
            _pendingTripId != null) {
          await _hideOverlayIfNeeded();
        }

        _updateStatus("Loading dashboard...");
        Future.delayed(const Duration(milliseconds: 500), () {
          _navigateToDashboard(driverId, vehicleTypeFromServer, activeTripData);
        });
        return;
      }

      if (status == 'pending' ||
          status == 'under_review' ||
          status == 'pending_review') {
        print("➡️ Docs under review → DocumentsReviewPage");
        _updateStatus("Your documents are under review...");
        await _hideOverlayIfNeeded();
        Future.delayed(const Duration(milliseconds: 500), () {
          _navigateToDocumentReview(driverId);
        });
        return;
      }

      if (status == 'rejected') {
        print("➡️ Docs rejected → DocumentsReviewPage");
        _updateStatus("Some documents were rejected. Please re-upload.");
        await _hideOverlayIfNeeded();
        Future.delayed(const Duration(milliseconds: 500), () {
          _navigateToDocumentReview(driverId);
        });
        return;
      }

      print("➡️ Status = $status → DriverDocumentUploadPage");
      _updateStatus("Let's complete your details...");
      await _hideOverlayIfNeeded();
      Future.delayed(const Duration(milliseconds: 500), () {
        if (driverId.isEmpty) {
          _navigateToLogin();
        } else {
          _navigateToDriverDetails(driverId);
        }
      });
    } on SocketException catch (e) {
      print("📴 Offline: $e");
      _showErrorAndRetry(
          "No internet connection.\nPlease connect to the internet to continue.");
      _scheduleAutoRetry();
    } on TimeoutException catch (e) {
      print("⏰ Timeout: $e");
      _showErrorAndRetry(
          "Server is taking too long to respond.\nPlease check your internet.");
      _scheduleAutoRetry();
    } catch (e) {
      print("❌ Error: $e");
      _showErrorAndRetry("Something went wrong.\nPlease try again.");
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 🔥 Force logout dialog — shown when session check fails on startup
  // ═══════════════════════════════════════════════════════════════════════
  void _showForceLogoutDialog() {
    if (!mounted) {
      _navigateToLogin();
      return;
    }
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.orange[100],
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.security, color: Colors.orange[700], size: 24),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text('Security Alert',
                  style:
                      TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ),
          ]),
          content: const Text(
            'Your account was logged in on another device. You have been logged out for security.',
            style: TextStyle(fontSize: 15, height: 1.5),
          ),
          actions: [
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.of(ctx).pop();
                  _navigateToLogin();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange[700],
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                child: const Text('Login Again',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _acceptTripFromOverlay(String tripId, String driverId) async {
    try {
      final response = await http
          .post(
            Uri.parse('$backendUrl/api/trip/accept'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'tripId': tripId, 'driverId': driverId}),
          )
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        print("✅ Trip accepted from overlay");
      }
    } catch (e) {
      print("❌ Error accepting trip from overlay: $e");
    }
  }

  void _scheduleAutoRetry() {
    Future.delayed(const Duration(seconds: 4), () {
      if (!mounted) return;
      final msg = _statusMessage.toLowerCase();
      final stillOfflineMsg = msg.contains('no internet') ||
          msg.contains('connect to the internet') ||
          msg.contains('taking too long') ||
          msg.contains('unable to contact server');
      if (stillOfflineMsg) {
        setState(() {
          _showError = false;
          _statusMessage = "Reconnecting...";
        });
        _initializeApp();
      }
    });
  }

  Future<Map<String, dynamic>?> _checkForActiveTrip(String driverId) async {
    try {
      final response = await http
          .get(
            Uri.parse('$backendUrl/api/trip/driver/active/$driverId'),
            headers: {'Content-Type': 'application/json'},
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['hasActiveTrip'] == true) {
          final tripData = data['trip'] as Map<String, dynamic>?;
          final customerData = data['customer'] as Map<String, dynamic>?;
          if (tripData != null) {
            final tripId =
                tripData['tripId']?.toString() ?? tripData['_id']?.toString();
            final tripStatus = tripData['status']?.toString() ?? '';
            final bool cashCollected = tripData['paymentCollected'] == true ||
                (tripData['payment'] is Map &&
                    tripData['payment']['collected'] == true);

            if ((tripStatus == 'awaiting_payment' ||
                    tripStatus == 'completed') &&
                cashCollected) {
              return null;
            }

            Map<String, dynamic>? paymentInfo;
            if (tripStatus == 'awaiting_payment' ||
                tripStatus == 'completed') {
              paymentInfo = {
                'fare': tripData['finalFare'] ?? tripData['fare'],
                'paymentCollected': cashCollected,
                'awaitingCashCollection': !cashCollected,
              };
            }

            return {
              'tripId': tripId,
              'status': tripStatus,
              'ridePhase': tripData['ridePhase']?.toString() ?? '',
              'otp': tripData['otp'] ?? tripData['rideCode'],
              'rideCode': tripData['rideCode'] ?? tripData['otp'],
              'rideStatus': tripData['rideStatus'],
              'trip': {
                'pickup': tripData['pickup'],
                'drop': tripData['drop'],
                'fare': tripData['fare'],
                'finalFare': tripData['finalFare'],
                'type': tripData['type'],
              },
              'pickup': tripData['pickup'],
              'drop': tripData['drop'],
              'fare': tripData['fare'],
              'finalFare': tripData['finalFare'],
              'customer': customerData,
              'paymentInfo': paymentInfo,
            };
          }
        }
      }
      return null;
    } catch (e) {
      print("❌ Error checking active trip: $e");
      return null;
    }
  }

  void _navigateToLogin() {
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const DriverLoginPage()),
    );
  }

  void _navigateToDriverDetails(String driverId) {
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
          builder: (_) => DriverDocumentUploadPage(driverId: driverId)),
    );
  }

  void _navigateToDocumentReview(String driverId) {
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
          builder: (_) => DocumentsReviewPage(driverId: driverId)),
    );
  }

  void _navigateToDashboard(String driverId, String vehicleType,
      [Map<String, dynamic>? activeTrip]) {
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => DriverDashboardPage(
          driverId: driverId,
          vehicleType: vehicleType,
          activeTrip: activeTrip,
        ),
      ),
    );
  }

  void _updateStatus(String message) {
    if (mounted) {
      setState(() {
        _statusMessage = message;
        _showError = false;
      });
    }
    print("📱 Status: $message");
  }

  void _showErrorAndRetry(String error) {
    if (mounted) {
      setState(() {
        _statusMessage = error;
        _showError = true;
      });
    }
  }

  void _retry() {
    setState(() {
      _statusMessage = "Retrying...";
      _showError = false;
    });
    _initializeApp();
  }

  @override
  Widget build(BuildContext context) {
    final msgLower = _statusMessage.toLowerCase();
    final bool isOfflineMessage = msgLower.contains('no internet') ||
        msgLower.contains('connect to the internet') ||
        msgLower.contains('taking too long') ||
        msgLower.contains('unable to contact server');

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(32.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 180,
                    height: 180,
                    child: Image.asset('assets/images/logo.png',
                        fit: BoxFit.contain),
                  ),
                  const SizedBox(height: 32),
                  Text(
                    "Ghumo Partner",
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 32,
                      fontWeight: FontWeight.w800,
                      color: AppColors.onSurface,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 40),
                  if (!_showError) ...[
                    const SizedBox(
                      width: 40,
                      height: 40,
                      child: CircularProgressIndicator(
                        strokeWidth: 3,
                        valueColor: AlwaysStoppedAnimation<Color>(
                            AppColors.primary),
                      ),
                    ),
                  ] else ...[
                    Icon(
                      isOfflineMessage
                          ? Icons.wifi_off_rounded
                          : Icons.error_outline,
                      size: 44,
                      color: AppColors.primary,
                    ),
                  ],
                  const SizedBox(height: 24),
                  Text(
                    _statusMessage,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: AppColors.onSurface.withOpacity(0.9),
                    ),
                    textAlign: TextAlign.center,
                  ),
                  if (isOfflineMessage) ...[
                    const SizedBox(height: 8),
                    Text(
                      "We're waiting for your internet connection.\nIt will continue automatically once you're online.",
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 13,
                        fontWeight: FontWeight.w400,
                        color: AppColors.onSurface.withOpacity(0.65),
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                  if (_showError && !isOfflineMessage) ...[
                    const SizedBox(height: 24),
                    ElevatedButton.icon(
                      onPressed: _retry,
                      icon: const Icon(Icons.refresh),
                      label: const Text("Retry"),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: AppColors.onPrimary,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 32, vertical: 16),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}