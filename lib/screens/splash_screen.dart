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

  // Pending overlay action
  String? _pendingOverlayAction;
  String? _pendingTripId;

  // ✅ Track if we should hide overlay (only after processing action)
  bool _shouldHideOverlay = false;

  @override
  void initState() {
    super.initState();

    // ✅ DON'T hide overlay here! Let the user see it first.
    // _hideOverlay();  // ❌ REMOVE THIS LINE

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

  /// ✅ Only hide overlay after user action is processed
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

  /// 🚀 MAIN INITIALIZATION FLOW
  Future<void> _initializeApp() async {
    if (_isInitializing) return;
    _isInitializing = true;

    try {
      // Small delay for splash animation
      await Future.delayed(const Duration(milliseconds: 800));

      // Check for pending overlay actions (accept/reject from native overlay)
      await _checkOverlayActions();

      // Check overlay permission
      await _checkOverlayPermission();

      await _decideNavigationFromServer();
    } catch (e) {
      print("❌ Initialization error: $e");
      _showErrorAndRetry("Failed to initialize app. Please try again.");
    } finally {
      _isInitializing = false;
    }
  }

  /// Check for pending overlay actions from native
  Future<void> _checkOverlayActions() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Check native overlay action
      final action = prefs.getString('flutter.overlay_action');
      final tripId = prefs.getString('flutter.overlay_trip_id');
      final actionTime = prefs.getInt('flutter.overlay_action_time') ?? 0;

      // Check if action is recent (within last 60 seconds)
      final now = DateTime.now().millisecondsSinceEpoch;
      final isRecent = (now - actionTime) < 60000;

      if (action != null && tripId != null && isRecent) {
        print('');
        print('=' * 70);
        print('📱 PENDING OVERLAY ACTION FOUND');
        print('   Action: $action');
        print('   Trip ID: $tripId');
        print('   Age: ${(now - actionTime) / 1000}s');
        print('=' * 70);
        print('');

        _pendingOverlayAction = action;
        _pendingTripId = tripId;

        // ✅ Mark that we should hide overlay after processing
        _shouldHideOverlay = true;

        // Clear the action so it's not processed again
        await prefs.remove('flutter.overlay_action');
        await prefs.remove('flutter.overlay_trip_id');
        await prefs.remove('flutter.overlay_action_time');
      }

      // Also check Flutter-side pending trip
      final pendingTripId = prefs.getString('pending_trip_id');
      final pendingAction = prefs.getString('pending_trip_action');
      final pendingTime = prefs.getInt('pending_trip_time') ?? 0;

      if (pendingTripId != null && (now - pendingTime) < 60000) {
        print(
          '📱 Pending Flutter trip action: $pendingAction for $pendingTripId',
        );
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

  /// Check and request overlay permission
  Future<void> _checkOverlayPermission() async {
    try {
      final hasPermission = await _overlayChannel.invokeMethod(
        'checkPermission',
      );

      if (hasPermission != true) {
        print('⚠️ Overlay permission not granted');
      } else {
        print('✅ Overlay permission granted');
      }
    } catch (e) {
      print('Error checking overlay permission: $e');
    }
  }

  /// 🔍 Reads Firebase user + calls /api/driver/profile and decides next screen
  Future<void> _decideNavigationFromServer() async {
    _updateStatus("Checking your session...");

    final prefs = await SharedPreferences.getInstance();

    try {
      // 1) Check Firebase user
      final fbUser = FirebaseAuth.instance.currentUser;
      if (fbUser == null) {
        print("⚠️ No Firebase user → go to login");
        await prefs.clear();
        await _hideOverlayIfNeeded(); // ✅ Hide overlay before navigation
        _navigateToLogin();
        return;
      }

      // 2) Get ID token
      final token = await fbUser.getIdToken();
      if (token == null) {
        print("❌ No Firebase token → session invalid");
        await prefs.clear();
        await _hideOverlayIfNeeded();
        _navigateToLogin();
        return;
      }

      _updateStatus("Loading your profile...");

      print("");
      print("=" * 70);
      print("🌐 PROFILE API REQUEST");
      print("=" * 70);
      print("   URL: $backendUrl/api/driver/profile");
      print("   Firebase UID: ${fbUser.uid}");
      print("   Token (first 20): ${token.substring(0, 20)}...");
      print("=" * 70);
      print("");

      // 3) Call /api/driver/profile
      final response = await http
          .get(
            Uri.parse('$backendUrl/api/driver/profile'),
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
          )
          .timeout(const Duration(seconds: 10));

      print("");
      print("=" * 70);
      print("📄 PROFILE RESPONSE");
      print("=" * 70);
      print("   Status Code: ${response.statusCode}");
      print("   Body: ${response.body}");
      print("=" * 70);
      print("");

      // 4) Handle unauthorized / not found
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
          "Unable to contact server.\nPlease check your internet.",
        );
        _scheduleAutoRetry();
        return;
      }

      // 5) Parse profile
      final data = jsonDecode(response.body);
      final Map<String, dynamic> driver =
          (data['driver'] ?? data) as Map<String, dynamic>;

      final String driverId = driver['_id']?.toString() ?? "";
      final String role = driver['role']?.toString() ?? "";
      final bool isDriver = driver['isDriver'] == true;
      final String rawStatus = (driver['documentStatus'] ?? 'not_uploaded')
          .toString();
      final String status = rawStatus.toLowerCase().trim();
      final String vehicleTypeFromServer =
          driver['vehicleType']?.toString() ?? "";

      final bool docsApprovedFromServer = status == 'approved';

      print("");
      print("=" * 70);
      print("🧾 DRIVER PROFILE ANALYSIS");
      print("=" * 70);
      print("   driverId: $driverId");
      print("   role: $role");
      print("   isDriver: $isDriver");
      print("   documentStatus: $status");
      print("   vehicleType: $vehicleTypeFromServer");
      print("   docsApprovedFromServer: $docsApprovedFromServer");
      if (_pendingOverlayAction != null) {
        print(
          "   ⚡ PENDING ACTION: $_pendingOverlayAction for $_pendingTripId",
        );
      }
      print("=" * 70);
      print("");

      // 6) Persist basic info
      if (driverId.isNotEmpty) {
        await prefs.setString('driverId', driverId);

        // Register FCM token
        final fcmToken = await FCMService.sendTokenToServer(driverId);
        if (fcmToken != null) {
          print('✅ FCM token registered: ${fcmToken.substring(0, 20)}...');
        }

        FCMService.listenForTokenRefresh(driverId);
      }

      await prefs.setBool('isLoggedIn', true);
      await prefs.setString('driverDocumentStatus', status);
      await prefs.setBool('docsApproved', docsApprovedFromServer);
      if (vehicleTypeFromServer.isNotEmpty) {
        await prefs.setString('vehicleType', vehicleTypeFromServer);
      }

      // 7) Decide navigation
      final bool hasVehicleDetails = vehicleTypeFromServer.isNotEmpty;

      if (!isDriver ||
          role != 'driver' ||
          driverId.isEmpty ||
          !hasVehicleDetails) {
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

        // Check active trip
        Map<String, dynamic>? activeTripData;
        try {
          _updateStatus("Checking active trips...");
          activeTripData = await _checkForActiveTrip(driverId);

          if (activeTripData != null) {
            final tripId = activeTripData['tripId']?.toString();
            print("⚠️ Active trip found: $tripId");

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

        // ✅ Handle pending overlay action
        if (_pendingOverlayAction == 'ACCEPT' && _pendingTripId != null) {
          print("⚡ Processing ACCEPT action for $_pendingTripId");
          _updateStatus("Accepting trip...");

          // Accept the trip via API
          await _acceptTripFromOverlay(_pendingTripId!, driverId);

          // Refresh active trip
          activeTripData = await _checkForActiveTrip(driverId);

          // ✅ Now hide the overlay since we processed the action
          await _hideOverlayIfNeeded();
        } else if (_pendingOverlayAction == 'REJECT' &&
            _pendingTripId != null) {
          print("⚡ Trip $_pendingTripId was rejected from overlay");
          // ✅ Hide overlay since user rejected
          await _hideOverlayIfNeeded();
        } else if (_pendingOverlayAction == 'TIMEOUT' &&
            _pendingTripId != null) {
          print("⚡ Trip $_pendingTripId timed out");
          // ✅ Hide overlay since it timed out
          await _hideOverlayIfNeeded();
        }
        // ✅ If no pending action, DON'T hide the overlay - it might still be showing!

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

      print(
        "➡️ Status = $status → DriverDocumentUploadPage (to continue onboarding)",
      );
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
      print("📴 Offline / SocketException: $e");
      _showErrorAndRetry(
        "No internet connection.\nPlease connect to the internet to continue.",
      );
      _scheduleAutoRetry();
    } on TimeoutException catch (e) {
      print("⏰ Timeout: $e");
      _showErrorAndRetry(
        "Server is taking too long to respond.\nPlease check your internet.",
      );
      _scheduleAutoRetry();
    } catch (e) {
      print("❌ Error: $e");
      print("Stack trace: ${StackTrace.current}");
      _showErrorAndRetry("Something went wrong.\nPlease try again.");
    }
  }

  /// Accept trip from overlay action
  Future<void> _acceptTripFromOverlay(String tripId, String driverId) async {
    try {
      print("🚀 Accepting trip $tripId from overlay...");

      final response = await http
          .post(
            Uri.parse('$backendUrl/api/trip/accept'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'tripId': tripId, 'driverId': driverId}),
          )
          .timeout(const Duration(seconds: 10));

      print("Accept response: ${response.statusCode} - ${response.body}");

      if (response.statusCode == 200) {
        print("✅ Trip accepted successfully from overlay!");
      } else {
        print("⚠️ Trip accept failed: ${response.body}");
      }
    } catch (e) {
      print("❌ Error accepting trip from overlay: $e");
    }
  }

  void _scheduleAutoRetry() {
    Future.delayed(const Duration(seconds: 4), () {
      if (!mounted) return;
      final msg = _statusMessage.toLowerCase();
      final stillOfflineMsg =
          msg.contains('no internet') ||
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
      print("");
      print("=" * 70);
      print("🔍 CHECKING FOR ACTIVE TRIP");
      print("=" * 70);

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

            print("⚠️ ACTIVE TRIP FOUND: $tripId");
            print("   Status: ${tripData['status']}");
            print("=" * 70);
            print("");

            return {
              'tripId': tripId,
              'status': tripData['status'],
              'otp': tripData['rideCode'] ?? tripData['otp'],
              'rideCode': tripData['rideCode'] ?? tripData['otp'],
              'rideStatus': tripData['rideStatus'],
              'trip': {
                'pickup': tripData['pickup'],
                'drop': tripData['drop'],
                'fare': tripData['fare'],
                'type': tripData['type'],
              },
              'customer': customerData,
              'paymentInfo': tripData['status'] == 'completed'
                  ? {
                      'fare': tripData['finalFare'] ?? tripData['fare'],
                      'paymentCollected': tripData['paymentCollected'] ?? false,
                    }
                  : null,
            };
          }
        }
      }

      print("✅ No active trip found");
      print("=" * 70);
      print("");
      return null;
    } catch (e) {
      print("❌ Error checking active trip: $e");
      print("=" * 70);
      print("");
      return null;
    }
  }

  // NAVIGATION METHODS
  void _navigateToLogin() {
    if (!mounted) return;
    print("🔄 Navigating to Login Page...");
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const DriverLoginPage()),
    );
  }

  void _navigateToDriverDetails(String driverId) {
    if (!mounted) return;
    print("🔄 Navigating to Driver Document Upload Page...");
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => DriverDocumentUploadPage(driverId: driverId),
      ),
    );
  }

  void _navigateToDocumentReview(String driverId) {
    if (!mounted) return;
    print("🔄 Navigating to Document Review Page...");
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => DocumentsReviewPage(driverId: driverId),
      ),
    );
  }

  void _navigateToDashboard(
    String driverId,
    String vehicleType, [
    Map<String, dynamic>? activeTrip,
  ]) {
    if (!mounted) return;
    print("🔄 Navigating to Dashboard...");
    print("   Driver ID: $driverId");
    print("   Vehicle Type: $vehicleType");
    print(
      "   Active Trip: ${activeTrip != null ? 'YES - ${activeTrip['tripId']}' : 'NO'}",
    );
    print("   Pending Action: $_pendingOverlayAction");

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
    final bool isOfflineMessage =
        msgLower.contains('no internet') ||
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
                    child: Image.asset(
                      'assets/images/logo.png',
                      fit: BoxFit.contain,
                    ),
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
                          AppColors.primary,
                        ),
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
                          horizontal: 32,
                          vertical: 16,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
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
