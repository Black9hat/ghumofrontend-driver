// ============================================================================
// driver_dashboard_page.dart - Part 1 of 2
// Production-ready driver dashboard for ride-sharing app
// ============================================================================
import 'dart:async';
import 'dart:convert';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:drivergoo/services/fcm_service.dart';
import 'package:drivergoo/screens/driver_help_support_page.dart';
import 'package:lottie/lottie.dart' hide Marker;
import 'driver_notification_page.dart';
import '../services/driver_notification_service.dart';
import 'package:drivergoo/screens/driver_goto_destination_page.dart';
import '../services/overlay_permission_service.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../screens/chat_page.dart';
import '../services/background_service.dart' hide print;
import '../services/socket_service.dart';
import '../services/commission_service.dart';
import 'driver_profile_page.dart';
import 'driver_ride_history_page.dart';
import 'incentivespage.dart';
import 'plans_page.dart';
import 'wallet_page.dart';
import '../config.dart';
import 'driver_payment_screen.dart';
// ============================================================================
// THEME CLASSES
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

  static TextStyle get button => GoogleFonts.plusJakartaSans(
    fontSize: 16,
    fontWeight: FontWeight.w700,
    color: AppColors.onSurface,
  );
}

// ============================================================================
// LOGGER SETUP
// ============================================================================

final Logger _logger = Logger('DriverDashboardPage');

void _log(String message, {Level level = Level.INFO}) {
  _logger.log(level, message);
}

// ============================================================================
// MAIN WIDGET
// ============================================================================

class DriverDashboardPage extends StatefulWidget {
  final String driverId;
  final String vehicleType;
  final Map<String, dynamic>?
  activeTrip; // 🔥 Optional active trip from splash/login

  const DriverDashboardPage({
    Key? key,
    required this.driverId,
    required this.vehicleType,
    this.activeTrip, // 🔥 Optional parameter
  }) : super(key: key);

  @override
  _DriverDashboardPageState createState() => _DriverDashboardPageState();
}

class _DriverDashboardPageState extends State<DriverDashboardPage>
    with WidgetsBindingObserver {
  // ⏱ Track last time a trip was shown (for 10-second retry logic)
  final Map<String, DateTime> _lastSeenTrips = {};
  // ===========================================================================
  // CONSTANTS
  // ===========================================================================

  // 🔐 Backend API URL - PRODUCTION configuration (Render)
  // For development: Uses AppConfig.backendBaseUrl
  // For release: Set via flutter build --dart-define=BACKEND_URL=https://ghumobackend.onrender.com
  // NO HARDCODED DEVELOPMENT URLs - prevents auto-rejection from Play Store
  static const String _apiBase =
      'https://ghumobackend.onrender.com'; // ✅ Production backend (Render)
  static const double _proximityThreshold = 200.0;
  static const Duration _locationUpdateInterval = Duration(seconds: 2);
  static const Duration _heartbeatInterval = Duration(seconds: 30);
  static const Duration _cleanupInterval = Duration(minutes: 5);

  // STATE: DRIVER PROFILE (for drawer header)
  String? _driverName;
  String? _driverPhotoUrl;

  // ===========================================================================
  // SERVICES
  // ===========================================================================

  final DriverSocketService _socketService = DriverSocketService();
  final AudioPlayer _audioPlayer = AudioPlayer();

  // ===========================================================================
  // CONTROLLERS
  // ===========================================================================

  final TextEditingController _otpController = TextEditingController();
  // 🔥 4-box OTP input controllers & focus nodes (Rapido/Uber style)
  final List<TextEditingController> _otpBoxControllers = List.generate(
    4,
    (_) => TextEditingController(),
  );
  final List<FocusNode> _otpBoxFocusNodes = List.generate(
    4,
    (_) => FocusNode(),
  );
  GoogleMapController? _mapController;
  bool _isProcessingOverlayAccept = false;

  // ===========================================================================
  // STATE: DRIVER STATUS
  // ===========================================================================

  late String _driverId;
  bool _isOnline = false;
  bool _acceptsLong = false;
  String? _driverFcmToken;
  bool _isGoToActive = false; // ❤️ Go To mode toggle
  Map<String, dynamic>? _goToDestination;

  // ===========================================================================
  // STATE: LOCATION
  // ===========================================================================

  LatLng? _currentPosition;
  LatLng? _customerPickup;

  // ===========================================================================
  // STATE: RIDE/TRIP
  // ===========================================================================

  String _ridePhase = 'none';
  String? _activeTripId;
  String? _customerOtp;
  double? _tripFareAmount;
  double? _finalFareAmount;

  List<Map<String, dynamic>> _rideRequests = [];
  Map<String, dynamic>? _currentRide;
  Map<String, dynamic>? _activeTripDetails;

  // ===========================================================================
  // STATE: WALLET & EARNINGS
  // ===========================================================================

  Map<String, dynamic>? _walletData;
  Map<String, dynamic>? _todayEarnings;
  bool _isLoadingWallet = false;
  bool _isLoadingToday = false;

  // ===========================================================================
  // STATE: VERSION GUARD & ACTION PROTECTION (NEW)
  // ===========================================================================

  int _lastTripVersion = 0; // 🔥 Socket version guard - ignore old events
  bool _actionInProgress = false; // 🔥 Prevent double-tap on action buttons

  // ===========================================================================
  // STATE: INCENTIVES & PLAN
  // ===========================================================================
  double _perRideIncentive = 0.0;
  int _perRideCoins = 0;
  String? _activePlanName; // e.g. "Gold Plan"
  double? _activePlanCommission; // e.g. 10.0 (%)
  double? _activePlanBonus; // bonusMultiplier e.g. 1.2

  // ===========================================================================
  // STATE: MAP ELEMENTS
  // ===========================================================================

  final Set<Marker> _markers = {};
  final Set<Polyline> _polylines = {};

  // ===========================================================================
  // STATE: DEDUPLICATION
  // ===========================================================================

  // ===========================================================================
  // TIMERS
  // ===========================================================================

  Timer? _locationUpdateTimer;
  Timer? _heartbeatTimer;
  Timer? _cleanupTimer;
  int _unreadNotificationCount = 0;
  Timer? _notificationPollTimer;

  // ===========================================================================
  // LIFECYCLE: initState
  // ===========================================================================

  @override
  void initState() {
    super.initState();
    _driverId = widget.driverId;
    WidgetsBinding.instance.addObserver(this);
    Future.delayed(Duration(milliseconds: 500), () {
      _checkForOverlayAction();
    });

    TripBackgroundService.initializeService();
    _fetchUnreadNotificationCount();

    // ✅ Setup background service listener
    _setupBackgroundServiceListener();

    _notificationPollTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _fetchUnreadNotificationCount(),
    );

    _initializeDriver();
    _startPromoAutoScroll();

    if (widget.activeTrip != null) {
      _log('Active trip passed from splash/login - restoring...');
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _restoreActiveTripFromWidget(widget.activeTrip!);
      });
    }
  }

  // ===========================================================================
  // STATE: PROMOTIONS (NEW)
  // ===========================================================================
  List<Map<String, dynamic>> _promotions = [];
  bool _isLoadingPromotions = true;
  int _currentPromoIndex = 0;
  Timer? _promoAutoScrollTimer;
  final PageController _promoPageController = PageController(
    viewportFraction: 0.9,
  );

  // Fallback promo data (used when API fails or no promotions)
  final List<Map<String, dynamic>> _promoCards = [
    {
      'title': 'Drive more, Earn more!',
      'subtitle': 'Complete 10 rides today',
      'icon': Icons.local_taxi,
      'color': AppColors.primary,
      'gradient': [Color(0xFFB85F00), Color(0xFFD97706)],
    },
    {
      'title': 'Bonus Incentive!',
      'subtitle': 'Extra ₹50 per ride',
      'icon': Icons.attach_money,
      'color': AppColors.success,
      'gradient': [Color(0xFF2E7D32), Color(0xFF43A047)],
    },
    {
      'title': 'Peak Hours',
      'subtitle': 'Earn 1.5x during rush hours',
      'icon': Icons.schedule,
      'color': Color(0xFF7C3AED),
      'gradient': [Color(0xFF7C3AED), Color(0xFF9F67FF)],
    },
  ];
  Future<void> _initializeDriver() async {
    await _restoreDriverSession();

    // ðŸ"¹ Load name & photo for drawer
    await _fetchDriverProfileSummary();

    await _requestLocationPermission();
    await _getCurrentLocation();
    await _initSocketAndFCM();

    // 💰 Initialize commission service for real-time rate updates
    await _initializeCommissionService();

    _startCleanupTimer();
    _fetchTripRequestIncentive(); // fetch preview from same source as completion wallet incentive
    _fetchActivePlan(); // 🔥 Fetch active plan from correct endpoint
    // 348: Fetch wallet data and await the result for startup safety check
    await _fetchWalletData();
    _fetchTodayEarnings();

    // 🛑 STRICT ACTION: Startup commission check
    final pendingStart = _parseDouble(_walletData?['pendingAmount'] ?? 0);
    if (pendingStart > 100 && (_isOnline || _isGoToActive)) {
      _log(
        'Startup block: Pending commission ₹$pendingStart > 100. Forcing offline.',
      );

      // Stop Go-To mode if active
      if (_isGoToActive) {
        setState(() {
          _isGoToActive = false;
          _goToDestination = null;
        });
      }

      // If online, force offline via toggle handler
      if (_isOnline) {
        await _handleOnlineToggle(false);
      }

      // Show blocking dialog
      _showCommissionLimitDialog(pendingStart);
    }

    // 🔥 NEW: Fetch promotions
    _fetchPromotions();

    Future.delayed(const Duration(seconds: 2), _checkAndResumeActiveTrip);
  }

  // ===========================================================================
  // LIFECYCLE: didChangeAppLifecycleState
  // ===========================================================================

  // ===========================================================================
  // LIFECYCLE: dispose
  // ===========================================================================

  @override
  void dispose() {
    _otpController.dispose();
    for (final c in _otpBoxControllers) c.dispose();
    for (final f in _otpBoxFocusNodes) f.dispose();
    _cancelAllTimers();
    _mapController?.dispose();
    _audioPlayer.dispose();
    _notificationPollTimer?.cancel();
    _promoAutoScrollTimer?.cancel();
    _promoPageController.dispose();

    // ✅ Only disconnect socket if offline AND no active trip
    if (!_isOnline && !_socketService.hasActiveTrip) {
      _socketService.disconnect();
      _log('Socket disconnected - driver offline');
    } else {
      _log('Socket kept alive - driver online or active trip');
    }

    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Add this method to listen for background service events:

  void _setupBackgroundServiceListener() {
    final service = FlutterBackgroundService();

    service.on('trip_accepted').listen((event) {
      if (event != null) {
        final tripId = event['tripId'] as String?;
        _log('Trip accepted via overlay: $tripId');

        // Handle acceptance in main app
        final trip = _rideRequests.firstWhere(
          (req) => _getTripId(req) == tripId,
          orElse: () => {},
        );

        if (trip.isNotEmpty && mounted) {
          setState(() => _currentRide = trip);
          _acceptRide();
        }
      }
    });

    service.on('trip_rejected').listen((event) {
      if (event != null) {
        final tripId = event['tripId'] as String?;
        _log('Trip rejected via overlay: $tripId');
        _rejectRide();
      }
    });
  }
  // ===========================================================================
  // PROMOTIONS FETCHING & AUTO-SCROLL
  // ===========================================================================

  void _startPromoAutoScroll() {
    _promoAutoScrollTimer = Timer.periodic(const Duration(seconds: 4), (timer) {
      if (_promoPageController.hasClients) {
        final itemCount = _promotions.isNotEmpty
            ? _promotions.length
            : _promoCards.length;
        if (itemCount > 0) {
          int nextPage = (_currentPromoIndex + 1) % itemCount;
          _promoPageController.animateToPage(
            nextPage,
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeInOut,
          );
        }
      }
    });
  }

  Future<void> _fetchPromotions() async {
    debugPrint('📄 Fetching promotions for driver dashboard...');

    try {
      setState(() => _isLoadingPromotions = true);

      // ✅ Changed endpoint to driver-specific
      final response = await http
          .get(Uri.parse('$_apiBase/api/promotions/active/driver'))
          .timeout(const Duration(seconds: 10));

      debugPrint('Response: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (data['promotions'] != null) {
          final promoList = data['promotions'] as List;
          debugPrint('✅ Loaded ${promoList.length} driver promotions');

          if (mounted) {
            setState(() {
              _promotions = List<Map<String, dynamic>>.from(promoList);
              _isLoadingPromotions = false;
            });
          }
        } else {
          debugPrint('⚠️ No promotions field in response');
          setState(() {
            _promotions = [];
            _isLoadingPromotions = false;
          });
        }
      } else {
        debugPrint('❌ Failed to fetch promotions: ${response.statusCode}');
        setState(() {
          _promotions = [];
          _isLoadingPromotions = false;
        });
      }
    } catch (e) {
      debugPrint('❌ Error fetching promotions: $e');
      setState(() {
        _promotions = [];
        _isLoadingPromotions = false;
      });
    }
  }

  Future<void> _trackPromotionClick(String promotionId) async {
    try {
      await http.post(Uri.parse('$_apiBase/api/promotions/$promotionId/click'));
      debugPrint('✅ Promotion click tracked: $promotionId');
    } catch (e) {
      debugPrint('❌ Error tracking promotion click: $e');
    }
  }

  // ===========================================================================
  // COMMISSION SERVICE INITIALIZATION
  // ===========================================================================

  Future<void> _initializeCommissionService() async {
    try {
      final commissionService = CommissionService();
      commissionService.onConfigUpdated = (config) {
        if (!mounted) return;
        if (config.perRideIncentive < 0) return;

        setState(() {
          _perRideIncentive = config.perRideIncentive;
          _perRideCoins = config.perRideCoins;
        });
        _log(
          'CommissionService sync: ₹$_perRideIncentive + $_perRideCoins coins (${config.vehicleType}/${config.city})',
        );
      };

      // Note: vehicleType is null - will use default 'all' config
      // Once driver profile fetches vehicle type, this can be updated
      await commissionService.initialize(_driverId, null);

      final cachedConfig = commissionService.getConfig();
      if (mounted &&
          cachedConfig != null &&
          cachedConfig.perRideIncentive >= 0) {
        setState(() {
          _perRideIncentive = cachedConfig.perRideIncentive;
          _perRideCoins = cachedConfig.perRideCoins;
        });
        _log(
          'CommissionService cached sync: ₹$_perRideIncentive + $_perRideCoins coins (${cachedConfig.vehicleType}/${cachedConfig.city})',
        );
      }

      debugPrint('✅ CommissionService initialized');
    } catch (e) {
      debugPrint('❌ Error initializing commission service: $e');
    }
  }

  void _cancelAllTimers() {
    _locationUpdateTimer?.cancel();
    _heartbeatTimer?.cancel();
    _cleanupTimer?.cancel();
    _locationUpdateTimer = null;
    _heartbeatTimer = null;
    _cleanupTimer = null;
  }

  void _startCleanupTimer() {
    _cleanupTimer?.cancel();
    _cleanupTimer = Timer.periodic(_cleanupInterval, (_) {
      // Clean up old entries older than 2 minutes
      final now = DateTime.now();
      _lastSeenTrips.removeWhere((tripId, lastSeen) {
        return now.difference(lastSeen).inMinutes > 2;
      });
      _log('Cleaned up trip tracking, remaining: ${_lastSeenTrips.length}');
    });
  }

  /// ✅ Called every time driver tries to go online - checks and asks if needed
  Future<bool> _ensureOverlayPermissionForOnline() async {
    try {
      final hasPermission = await OverlayPermissionService.hasPermission();

      if (hasPermission) {
        return true; // Permission granted, proceed
      }

      // Permission not granted - show dialog
      if (mounted) {
        final userWantsToGrant = await _showOverlayPermissionDialogForOnline();

        if (userWantsToGrant) {
          await OverlayPermissionService.requestPermission();

          // Wait a bit and check again (user might have granted)
          await Future.delayed(const Duration(seconds: 2));
          return await OverlayPermissionService.hasPermission();
        }
      }

      return false; // User declined or cancelled
    } catch (e) {
      _log('Error ensuring overlay permission: $e');
      return false;
    }
  }

  /// ✅ Show overlay permission dialog when going online
  Future<bool> _showOverlayPermissionDialogForOnline() async {
    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.error.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.warning_amber,
                    color: AppColors.error,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Permission Required',
                    style: AppTextStyles.heading3,
                  ),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'You cannot go online without enabling "Display over other apps" permission.',
                  style: AppTextStyles.body1,
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.error.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.error_outline,
                        color: AppColors.error,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Without this, you will miss trip requests when app is in background!',
                          style: AppTextStyles.body2.copyWith(
                            color: AppColors.error,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppColors.primary.withOpacity(0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        color: AppColors.primary,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'This ensures you never miss a ride request!',
                          style: AppTextStyles.body2.copyWith(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(
                  'Stay Offline',
                  style: AppTextStyles.button.copyWith(
                    color: AppColors.onSurfaceSecondary,
                  ),
                ),
              ),
              ElevatedButton.icon(
                onPressed: () => Navigator.pop(context, true),
                icon: const Icon(Icons.settings, size: 18),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: AppColors.onPrimary,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                label: Text('Grant Permission', style: AppTextStyles.button),
              ),
            ],
          ),
        ) ??
        false;
  }

  // ===========================================================================

  // ===========================================================================

  // ===========================================================================
  // SESSION RESTORATION
  // ===========================================================================

  Future<void> _restoreDriverSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      setState(() {
        _isOnline = prefs.getBool('isOnline') ?? false;
        _acceptsLong = prefs.getBool('acceptsLong') ?? false;

        // ✅ NEW: Load saved profile data (if you store it)
        _driverName = prefs.getString('driverName');
        _driverPhotoUrl = prefs.getString('driverPhotoUrl');
      });

      await prefs.setString('vehicleType', widget.vehicleType);
      _log('Session restored: online=$_isOnline, acceptsLong=$_acceptsLong');
    } catch (e) {
      _log('Failed to restore session: $e', level: Level.WARNING);
    }
  }

  // ===========================================================================
  // notification
  // ===========================================================================

  Future<void> _fetchUnreadNotificationCount() async {
    try {
      final data = await DriverNotificationService.fetchNotifications();

      final int unread = data['unreadCount'] ?? 0;

      if (mounted) {
        setState(() {
          _unreadNotificationCount = unread;
        });
      }
    } catch (e) {
      debugPrint('Unread notification fetch error: $e');
    }
  }

  // ===========================================================================
  // SOCKET & FCM INITIALIZATION
  // ===========================================================================

  Future<void> _initSocketAndFCM() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // 🔥 Get FCM token and ensure it's sent to server
      _driverFcmToken = await FCMService.sendTokenToServer(_driverId);

      // 🔥 Listen for token refresh
      FCMService.listenForTokenRefresh(_driverId);

      final position = await _getSafeCurrentPosition();

      _socketService.connect(
        _driverId,
        position.latitude,
        position.longitude,
        vehicleType: prefs.getString('vehicleType') ?? widget.vehicleType,
        isOnline: _isOnline,
        fcmToken: _driverFcmToken,
      );

      _setupSocketListeners();
      _setupFCMListeners();
      _setupRideCancelledCallback();
      _setupActiveTripRestoreListener();

      // Start background service if online
      if (_isOnline) {
        await TripBackgroundService.startOnlineService(
          driverId: _driverId,
          vehicleType: widget.vehicleType,
          isOnline: true,
        );
      }

      _log('Socket and FCM initialized');
    } catch (e) {
      _log('Socket/FCM init error: $e', level: Level.SEVERE);
    }
  }

  @override
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _log('App lifecycle: $state');

    switch (state) {
      case AppLifecycleState.paused:
        if (_isOnline) {
          _log('App backgrounded - Socket kept alive, service running');
        }
        break;

      case AppLifecycleState.resumed:
        _log('App resumed - checking state...');

        // ✅ Check for overlay actions FIRST, before anything else
        _checkOverlayActions().then((_) {
          // Only proceed with normal resume logic if not processing overlay
          if (!_isProcessingOverlayAccept) {
            if (!_socketService.isConnected && _isOnline) {
              _log('Reconnecting socket...');
              _initSocketAndFCM();
            } else if (_socketService.isConnected) {
              _socketService.emit('driver:request_active_trip', {
                'driverId': _driverId,
              });
            }

            _getCurrentLocation();
            _checkAndResumeActiveTrip();
          }
        });
        break;

      default:
        break;
    }
  }

  // 5️⃣ ADDITIONAL: Clear pending variables in _clearActiveTrip
  void _clearActiveTrip() {
    _log('Clearing active trip state');

    setState(() {
      _activeTripDetails = null;
      _activeTripId = null;
      _ridePhase = 'none';
      _customerOtp = null;
      _customerPickup = null;
      _finalFareAmount = null;
      _tripFareAmount = null;
      _polylines.clear();
      _markers.clear();
      _otpController.clear();
      for (final c in _otpBoxControllers) c.clear();

      // 🔥 Reset action and version states
      _actionInProgress = false;
      _lastTripVersion = 0;

      // ✅ NEW: Clear pending overlay variables
      _pendingOverlayAction = null;
      _pendingTripId = null;
      _isProcessingOverlayAccept = false;
    });
    _locationUpdateTimer?.cancel();
    _locationUpdateTimer = null;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;

    _socketService.setActiveTrip(null);
  }

  // Add this new method to check overlay actions:

  /// ✅ ENHANCED: Better logging and error handling
  /// ✅ FIXED: Clear trip from queue BEFORE processing accept
  /// ✅ SIMPLIFIED: Just restore UI - backend already accepted the trip
  Future<void> _checkOverlayActions() async {
    print('');
    print('╔═══════════════════════════════════════════════════');
    print('📱 CHECKING OVERLAY ACTIONS');
    print('╚═══════════════════════════════════════════════════');

    try {
      final prefs = await SharedPreferences.getInstance();

      final overlayAction = prefs.getString('flutter.overlay_action');
      final overlayTripId = prefs.getString('flutter.overlay_trip_id');
      final overlayTripDataString = prefs.getString(
        'flutter.overlay_trip_data',
      );
      final actionTime = prefs.getInt('flutter.overlay_action_time');

      print('   Overlay Action: $overlayAction');
      print('   Trip ID: $overlayTripId');

      if (overlayAction == null || overlayTripId == null) {
        print('   ❌ No pending overlay actions');
        return;
      }

      // ✅ SET PENDING VARIABLES IMMEDIATELY
      _pendingOverlayAction = overlayAction;
      _pendingTripId = overlayTripId;

      // ✅ SET FLAG IMMEDIATELY to block incoming trips
      if (overlayAction == 'ACCEPT' && mounted) {
        setState(() {
          _isProcessingOverlayAccept = true;
        });
        print('   🚫 SET FLAG: Blocking new trip requests');
      }

      // Clear stored action
      print('   🧹 Clearing stored overlay action...');
      await prefs.remove('flutter.overlay_action');
      await prefs.remove('flutter.overlay_trip_id');
      await prefs.remove('flutter.overlay_trip_data');
      await prefs.remove('flutter.overlay_action_time');
      print('   ✅ Cleared successfully');

      // Check if action is recent
      if (actionTime != null) {
        final now = DateTime.now().millisecondsSinceEpoch;
        final ageSeconds = (now - actionTime) ~/ 1000;
        print('   ⏱️ Action age: ${ageSeconds}s');

        if (now - actionTime > 30000) {
          print('   ⏰ Action too old (${ageSeconds}s), ignoring');
          if (mounted) {
            setState(() {
              _isProcessingOverlayAccept = false;
              _pendingOverlayAction = null;
              _pendingTripId = null;
            });
          }
          return;
        }
      }

      // Parse trip data
      Map<String, dynamic>? overlayTripData;
      if (overlayTripDataString != null) {
        try {
          overlayTripData =
              jsonDecode(overlayTripDataString) as Map<String, dynamic>;
          print('   ✅ Parsed overlay trip data');
        } catch (e) {
          print('   ❌ Failed to parse overlay trip data: $e');
        }
      }

      // ✅ CRITICAL: Remove trip from queue BEFORE processing
      if (overlayAction == 'ACCEPT' && mounted) {
        print('   🚫 REMOVING TRIP FROM QUEUE IMMEDIATELY');
        setState(() {
          _rideRequests.removeWhere((req) => _getTripId(req) == overlayTripId);
          _currentRide = null;
          print('   ✅ Removed. Remaining: ${_rideRequests.length}');
        });

        await Future.delayed(const Duration(milliseconds: 100));
      }

      // Handle the action
      if (overlayAction == 'ACCEPT') {
        print('');
        print('   ✅ PROCESSING ACCEPT - TRIP ALREADY ACCEPTED BY API');
        print('   ═══════════════════════════════════════════════');

        try {
          // Backend already accepted - just restore UI
          if (mounted) {
            setState(() {
              _activeTripId = overlayTripId;
              _ridePhase = 'going_to_pickup';
              if (overlayTripData != null) {
                _tripFareAmount = _parseDouble(overlayTripData['fare']);
                _finalFareAmount = _tripFareAmount;
              }
            });
          }

          _socketService.setActiveTrip(overlayTripId);

          // Start services
          print('   🚀 Starting background services...');
          await TripBackgroundService.startTripService(
            tripId: overlayTripId,
            driverId: _driverId,
            customerName: 'Customer',
          );
          await WakelockPlus.enable();
          print('   ✅ Services started');

          _startHeartbeat();
          _showSnackBar(
            'Trip accepted! Loading details...',
            color: AppColors.success,
          );

          // Wait for socket to connect
          int retries = 0;
          while (!_socketService.isConnected && retries < 10) {
            print('   ⏳ Waiting for socket... ($retries/10)');
            await Future.delayed(const Duration(milliseconds: 500));
            retries++;
          }

          if (_socketService.isConnected) {
            print('   ✅ Socket connected - requesting trip details');

            // Request trip details from backend
            _socketService.emit('driver:request_active_trip', {
              'driverId': _driverId,
            });

            // Listen for trip details
            _socketService.socket?.once('active_trip:restore', (data) {
              print('   ✅ Trip details received from backend!');

              if (mounted) {
                setState(() {
                  _isProcessingOverlayAccept = false;
                  _pendingOverlayAction = null;
                  _pendingTripId = null;
                  _activeTripDetails = data;
                  final lat = data['trip']?['pickup']?['lat'];
                  final lng = data['trip']?['pickup']?['lng'];
                  if (lat != null && lng != null) {
                    _customerPickup = LatLng(lat, lng);
                  }
                  _customerOtp = data['otp']?.toString();
                });
                _drawRouteToCustomer();
                _startLiveLocationUpdates();
              }
            });
          } else {
            print('   ⚠️ Socket not connected - will restore when connected');
          }

          // Clear flag after short delay
          Future.delayed(const Duration(seconds: 2), () {
            if (mounted) {
              setState(() {
                _isProcessingOverlayAccept = false;
                _pendingOverlayAction = null;
                _pendingTripId = null;
              });
            }
          });
        } catch (e) {
          print('   ❌ Error: $e');

          if (mounted) {
            setState(() {
              _isProcessingOverlayAccept = false;
              _pendingOverlayAction = null;
              _pendingTripId = null;
            });
          }
        }
      } else if (overlayAction == 'REJECT') {
        print('   ❌ Trip was rejected');
        _showSnackBar('Trip rejected', color: AppColors.warning);

        if (mounted) {
          setState(() {
            _isProcessingOverlayAccept = false;
            _pendingOverlayAction = null;
            _pendingTripId = null;
          });
        }
      } else if (overlayAction == 'TIMEOUT') {
        print('   ⏰ Trip timed out in overlay');
        _showSnackBar('Trip request timed out', color: AppColors.warning);

        if (mounted) {
          setState(() {
            _isProcessingOverlayAccept = false;
            _pendingOverlayAction = null;
            _pendingTripId = null;
          });
        }
      }

      print('╚═══════════════════════════════════════════════════');
      print('');
    } catch (e, stackTrace) {
      print('❌ ERROR checking overlay actions: $e');
      print('Stack trace: $stackTrace');

      if (mounted) {
        setState(() {
          _isProcessingOverlayAccept = false;
          _pendingOverlayAction = null;
          _pendingTripId = null;
        });
      }

      _showSnackBar(
        'Error processing overlay action: $e',
        color: AppColors.error,
      );
    }
  }

  Future<Position> _getSafeCurrentPosition() async {
    try {
      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
    } catch (e) {
      return Position(
        latitude: _currentPosition?.latitude ?? 0.0,
        longitude: _currentPosition?.longitude ?? 0.0,
        timestamp: DateTime.now(),
        accuracy: 0.0,
        altitude: 0.0,
        heading: 0.0,
        speed: 0.0,
        speedAccuracy: 0.0,
        altitudeAccuracy: 0.0,
        headingAccuracy: 0.0,
      );
    }
  }

  void _setupSocketListeners() {
    // ✅ FIX: socket is now nullable — use _socketService.on() which is null-safe
    // and queues listeners if socket not yet connected
    _log('🔌 Setting up socket listeners...');
    debugPrint('🔌 Socket connected: ${_socketService.isConnected}');
    debugPrint('🔌 Socket ID: ${_socketService.socket?.id}');

    _socketService.on('trip:cancelled', _handleTripCancelled);
    _socketService.on('trip:taken', _handleTripTaken);
    _socketService.on('trip:confirmed_for_driver', _handleTripConfirmed);
    _socketService.on('trip:otp_generated', _handleOtpGenerated);
    _socketService.on('trip:ride_started', _handleRideStarted);
    _socketService.on('trip:completed', _handleTripCompleted);
    _socketService.on('trip:expired', _handleTripExpired);
    _socketService.on('tripRequest', _handleIncomingTrip); // Legacy support

    // ✅ SINGLE trip:request listener with debugging
    _socketService.on('trip:request', (data) {
      debugPrint('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      debugPrint('🚕 SOCKET EVENT: trip:request RECEIVED!');
      debugPrint('📦 Raw data type: ${data.runtimeType}');
      debugPrint('📦 Raw data: $data');
      debugPrint('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');

      _handleIncomingTrip(data);
    });

    // Version-guarded trip update listener
    _socketService.on('trip:update', _handleVersionedTripUpdate);
    _socketService.on('trip:status_changed', _handleVersionedTripUpdate);
    // 🆕 Listen for active trip restore directly in dashboard too
    _socketService.on('active_trip:restore', (data) {
      print('📦 active_trip:restore received in dashboard listener');
      if (data != null && mounted) {
        _handleActiveTripRestore(Map<String, dynamic>.from(data));
      }
    });

    _socketService.on('reconnect:success', (data) {
      print('📦 reconnect:success received in dashboard listener');
      if (data != null && mounted) {
        _handleActiveTripRestore(Map<String, dynamic>.from(data));
      }
    });

    // 💰 NEW: Listen for plan-related events
    _socketService.on('plan:activated', _handlePlanActivated);
    _socketService.on('plan:expired', _handlePlanExpired);
    // 🔍 DEBUG: Catch-all to see ANY socket events
    _socketService.socket?.onAny((event, data) {
      debugPrint('📡 SOCKET EVENT: $event');
    });

    _log('✅ Socket listeners set up complete');
  }

  void _setupFCMListeners() {
    FirebaseMessaging.onMessage.listen((message) {
      _log('FCM foreground message received');
      _handleFCMMessage(message, delaySeconds: 2);
    });

    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      _log('FCM notification tapped');
      _playNotificationSound();
      _handleFCMMessage(message, delaySeconds: 1);
    });
  }

  // 🆕 Handle active trip restore from socket
  void _handleActiveTripRestore(Map<String, dynamic> data) {
    final tripId = data['tripId']?.toString();
    if (tripId == null) return;

    // Don't restore if we already have this trip active
    if (_activeTripId == tripId && _activeTripDetails != null) {
      _log('Trip $tripId already active - skipping restore');
      return;
    }

    final status = (data['status']?.toString() ?? '').toLowerCase();
    final tripData = data['trip'] as Map<String, dynamic>?;
    final customerData = data['customer'] as Map<String, dynamic>?;
    final paymentInfo = data['paymentInfo'] as Map<String, dynamic>?;

    // ✅ If cash already collected — clean up and go to idle, don't restore cash screen
    final bool cashAlreadyCollected =
        paymentInfo?['paymentCollected'] == true ||
        tripData?['paymentCollected'] == true;
    if (cashAlreadyCollected) {
      _log('Cash already collected for trip $tripId — cleaning up');
      _clearActiveTrip();
      _socketService.setActiveTrip(null);
      return;
    }

    String newPhase = 'going_to_pickup';
    switch (status) {
      case 'driver_assigned':
      case 'driver_going_to_pickup':
        newPhase = 'going_to_pickup';
        break;
      case 'driver_at_pickup':
        newPhase = 'at_pickup';
        break;
      case 'ride_started':
      case 'in_progress':
        newPhase = 'going_to_drop';
        break;
      case 'awaiting_payment':
        // Driver tapped Complete Ride — show collect cash screen
        newPhase = 'completed';
        break;
      case 'completed':
        newPhase = 'completed';
        break;
    }

    setState(() {
      _activeTripId = tripId;
      _ridePhase = newPhase;
      _customerOtp = data['otp']?.toString() ?? data['rideCode']?.toString();

      if (tripData != null) {
        _tripFareAmount = _parseDouble(tripData['fare']);
        _finalFareAmount = _tripFareAmount;

        final pickupLat = tripData['pickup']?['lat'];
        final pickupLng = tripData['pickup']?['lng'];
        if (pickupLat != null && pickupLng != null) {
          _customerPickup = LatLng(pickupLat, pickupLng);
        }
      }

      _activeTripDetails = {
        'tripId': tripId,
        'trip': tripData ?? {},
        'customer': customerData ?? {},
      };
    });

    _socketService.setActiveTrip(tripId);
    _startLiveLocationUpdates();
    _startHeartbeat();

    if (newPhase == 'going_to_pickup') {
      _drawRouteToCustomer();
    }

    _log('✅ Trip restored via socket: $tripId, phase: $newPhase');
  }

  void _handleFCMMessage(RemoteMessage message, {int delaySeconds = 0}) {
    Future.delayed(Duration(seconds: delaySeconds), () {
      final tripId = message.data['tripId']?.toString();
      if (tripId != null && !_isDuplicateTrip(tripId)) {
        final tripData = _parseFCMData(message.data);
        _handleIncomingTrip(tripData);
      }
    });
  }

  Map<String, dynamic> _parseFCMData(Map<String, dynamic> data) {
    debugPrint('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    debugPrint('📨 _parseFCMData called');
    debugPrint('   Raw FCM data: $data');

    // ✅ Just return as-is - conversion happens in _parseIncomingTrip
    final parsed = Map<String, dynamic>.from(data);

    debugPrint('   Parsed keys: ${parsed.keys.toList()}');
    debugPrint('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');

    return parsed;
  }

  void _setupRideCancelledCallback() {
    _socketService.onRideCancelled = (data) {
      _log('Ride cancelled callback: $data');
      if (mounted) {
        _playNotificationSound();
        _showSnackBar('Ride cancelled.');
      }
    };
  }

  // 🆕 SETUP ACTIVE TRIP RESTORE LISTENER
  void _setupActiveTripRestoreListener() {
    _socketService.onActiveTripRestored = (data) {
      print('');
      print('🔄 ═══════════════════════════════════════════════════');
      print('🔄 ACTIVE TRIP RESTORED IN DASHBOARD');
      print('   Data: $data');
      print('🔄 ═══════════════════════════════════════════════════');
      print('');

      if (!mounted) return;

      final tripId = data['tripId']?.toString();
      final status = (data['status']?.toString() ?? '').toLowerCase();
      final tripData = data['trip'] as Map<String, dynamic>?;
      final customerData = data['customer'] as Map<String, dynamic>?;
      final paymentInfo = data['paymentInfo'] as Map<String, dynamic>?;

      if (tripId == null) {
        _log('No tripId in restored data');
        return;
      }

      // Determine ride phase from status
      String newPhase = 'going_to_pickup';
      switch (status) {
        case 'driver_assigned':
        case 'driver_going_to_pickup':
          newPhase = 'going_to_pickup';
          break;
        case 'driver_at_pickup':
          newPhase = 'at_pickup';
          break;
        case 'ride_started':
        case 'in_progress':
        case 'on_trip':
          newPhase = 'going_to_drop';
          break;
        case 'awaiting_payment':
          // Driver tapped Complete Ride — show collect cash screen
          newPhase = 'completed';
          break;
        case 'completed':
          newPhase = 'completed';
          break;
      }

      setState(() {
        _activeTripId = tripId;
        _ridePhase = newPhase;
        _customerOtp = data['otp']?.toString() ?? data['rideCode']?.toString();

        if (tripData != null) {
          _tripFareAmount = _parseDouble(tripData['fare']);
          _finalFareAmount = _tripFareAmount;

          final pickupLat = tripData['pickup']?['lat'];
          final pickupLng = tripData['pickup']?['lng'];
          if (pickupLat != null && pickupLng != null) {
            _customerPickup = LatLng(pickupLat, pickupLng);
          }
        }

        // ✅ If cash already collected — don't restore cash screen, clean up
        final bool cashAlreadyCollected2 =
            paymentInfo?['paymentCollected'] == true ||
            tripData?['paymentCollected'] == true;
        if (cashAlreadyCollected2 && newPhase == 'completed') {
          _log(
            'Cash already collected (HTTP restore) — cleaning up trip $tripId',
          );
          // Don't setState with completed phase — just clean up
          Future.microtask(() {
            _clearActiveTrip();
            _socketService.setActiveTrip(null);
          });
          return;
        }

        // Handle payment info for completed trips
        if (paymentInfo != null && newPhase == 'completed') {
          _finalFareAmount = _parseDouble(paymentInfo['fare']);
        }

        _activeTripDetails = {
          'tripId': tripId,
          'trip': tripData ?? {},
          'customer': customerData ?? {},
        };
      });

      // Start background services
      _socketService.setActiveTrip(tripId);

      TripBackgroundService.startTripService(
        tripId: tripId,
        driverId: widget.driverId,
        customerName: customerData?['name'] ?? 'Customer',
      );

      WakelockPlus.enable();
      _startLiveLocationUpdates();
      _startHeartbeat();

      if (newPhase == 'going_to_pickup' || newPhase == 'at_pickup') {
        _drawRouteToCustomer();
      }

      _log('✅ Trip restored: $tripId, phase: $newPhase');

      // Keep restore silent for a production-like uninterrupted flow.
    };
  }
  // ===========================================================================
  // SOCKET EVENT HANDLERS
  // ===========================================================================

  void _handleTripCancelled(dynamic data) {
    if (!mounted) return;

    final tripId = data['tripId']?.toString();
    if (tripId == null) return;

    _log('🚫 Trip cancelled: $data');
    _stopNotificationSound();

    // 🔥 REMOVE FROM REQUEST QUEUE
    _rideRequests.removeWhere((req) => _getTripId(req) == tripId);

    // 🔥 RESET CURRENT REQUEST CARD
    if (_currentRide != null && _getTripId(_currentRide!) == tripId) {
      _currentRide = _rideRequests.isNotEmpty ? _rideRequests.first : null;
    }

    // ❌ Customer cancelled - never show again (remove from tracking)
    _lastSeenTrips.remove(tripId);

    // 🔥 CLEAR ACTIVE TRIP IF ANY
    if (_activeTripId == tripId) {
      _clearActiveTrip();
      TripBackgroundService.stopTripService();
      WakelockPlus.disable();
      _socketService.setActiveTrip(null);
    }

    setState(() {});
  }

  void _handleTripTaken(dynamic data) {
    if (!mounted) return;

    final takenTripId = data['tripId']?.toString();
    _log('Trip taken by another driver: $takenTripId');

    setState(() {
      _rideRequests.removeWhere((req) => _getTripId(req) == takenTripId);
      _currentRide = _rideRequests.isNotEmpty ? _rideRequests.first : null;
    });

    _showSnackBar(
      'Trip accepted by ${data['acceptedBy']}',
      color: AppColors.warning,
    );
    _stopNotificationSound();
  }

  void _handleTripConfirmed(dynamic data) {
    if (!mounted) return;
    _log('Trip confirmed for driver');

    setState(() {
      _activeTripDetails = data;
      final lat = data['trip']?['pickup']?['lat'];
      final lng = data['trip']?['pickup']?['lng'];
      if (lat != null && lng != null) {
        _customerPickup = LatLng(lat, lng);
      }
    });

    _drawRouteToCustomer();
    _startLiveLocationUpdates();
  }

  void _handleOtpGenerated(dynamic data) {
    if (!mounted) return;
    _log('OTP generated');

    setState(() {
      _customerOtp = data['otp']?.toString();
    });
    // OTP message intentionally silent to avoid unnecessary popup noise.
  }

  void _handleRideStarted(dynamic data) {
    if (!mounted) return;
    _log('Ride started');

    setState(() {
      _ridePhase = 'going_to_drop';
    });
  }

  void _handleTripCompleted(dynamic data) {
    if (!mounted) return;
    _log('Trip completed');

    final fareAmount =
        _parseDouble(data?['fare']) ??
        _finalFareAmount ??
        _tripFareAmount ??
        0.0;

    setState(() {
      _finalFareAmount = fareAmount;
      _ridePhase = 'completed';
    });

    // Skip earnings card - go directly to payment screen
    Future.delayed(const Duration(milliseconds: 400), () {
      if (!mounted) return;

      final tripId = _activeTripId ?? '';
      if (tripId.isEmpty) {
        _log('Cannot proceed: no activeTripId');
        return;
      }

      // Show payment screen directly
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => DriverPaymentScreen(
            tripId: tripId,
            driverId: widget.driverId,
            fareAmount: fareAmount,
            tripDetails: _currentRide ?? {},
            onPaymentConfirmed: () {
              _clearActiveTrip();
              _clearDriverStateOnBackend();
              _updateDriverStatusSocket();
              _fetchWalletData();
              _fetchTodayEarnings();
            },
          ),
        ),
      );
    });
  }

  // ===========================================================================
  // TRIP EXPIRY HANDLING
  // ===========================================================================

  void _handleTripExpired(dynamic data) {
    if (!mounted) return;

    final expiredTripId = data['tripId']?.toString();
    _log('Trip expired: $expiredTripId');

    setState(() {
      _rideRequests.removeWhere((req) => _getTripId(req) == expiredTripId);
      _currentRide = _rideRequests.isNotEmpty ? _rideRequests.first : null;
    });

    if (Navigator.canPop(context)) Navigator.pop(context);
    _stopNotificationSound();
  }

  // ===========================================================================
  // INCOMING TRIP HANDLING
  // ===========================================================================

  /// ✅ FIXED: Don't add trip if it's being accepted from overlay
  void _handleIncomingTrip(dynamic rawData) {
    debugPrint('╔═══════════════════════════════════════════════════');
    debugPrint('🚕 _handleIncomingTrip CALLED');

    // 🔥 CRITICAL: Block ALL incoming trips during overlay accept
    if (_isProcessingOverlayAccept) {
      debugPrint('🚫 BLOCKED: Processing overlay accept - ignoring new trips');
      debugPrint('╚═══════════════════════════════════════════════════');
      return;
    }

    final request = _parseIncomingTrip(rawData);
    if (request == null) {
      debugPrint('❌ FAILED: _parseIncomingTrip returned null');
      return;
    }

    final tripId = _getTripId(request);
    if (tripId == null) {
      debugPrint('❌ FAILED: No tripId in request');
      return;
    }

    // ✅ NEW: Check if this trip is being accepted from overlay right now
    final isBeingAcceptedFromOverlay = _checkIfTripBeingAcceptedFromOverlaySync(
      tripId,
    );

    if (isBeingAcceptedFromOverlay) {
      debugPrint('🚫 BLOCKED: Trip is being accepted from overlay');
      debugPrint('╚═══════════════════════════════════════════════════');
      return;
    }

    // Check if already active
    if (_activeTripId == tripId) {
      debugPrint('🚫 BLOCKED: Trip is already active');
      return;
    }

    // Check for duplicates
    if (_isDuplicateTrip(tripId)) {
      debugPrint('❌ BLOCKED: Duplicate trip: $tripId');
      return;
    }

    // Validate driver status
    if (!_isOnline) {
      debugPrint('❌ BLOCKED: Driver is offline');
      return;
    }

    // Validate vehicle type
    final requestVehicle = (request['vehicleType'] ?? '')
        .toString()
        .toLowerCase()
        .trim();
    final driverVehicle = widget.vehicleType.toLowerCase().trim();

    if (requestVehicle.isNotEmpty &&
        requestVehicle != 'undefined' &&
        requestVehicle != 'null' &&
        requestVehicle != driverVehicle) {
      debugPrint('❌ BLOCKED: Vehicle mismatch');
      return;
    }

    // Mark last seen
    _lastSeenTrips[tripId] = DateTime.now();

    setState(() {
      _rideRequests.add(request);
      _currentRide = _rideRequests.first;
    });

    debugPrint('✅ Trip added to queue! Total: ${_rideRequests.length}');
    debugPrint('╚═══════════════════════════════════════════════════');

    _playNotificationSound();
    _log('Trip added to queue: $tripId');
  }

  // 2️⃣ NEW: Synchronous check for overlay action (no async needed)
  bool _checkIfTripBeingAcceptedFromOverlaySync(String tripId) {
    try {
      // Use cached prefs if available, or check the pending action variables
      if (_pendingOverlayAction == 'ACCEPT' && _pendingTripId == tripId) {
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('Error checking overlay action: $e');
      return false;
    }
  }

  String? _pendingOverlayAction;
  String? _pendingTripId;

  Future _checkForOverlayAction() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final overlayAction = prefs.getString('flutter.overlay_action');
      final overlayTripId = prefs.getString('flutter.overlay_trip_id');
      final overlayTripDataStr = prefs.getString('flutter.overlay_trip_data');
      final overlayActionTime =
          prefs.getInt('flutter.overlay_action_time') ?? 0;

      if (overlayAction == 'ACCEPT' &&
          overlayTripId != null &&
          overlayTripDataStr != null) {
        final timeDiff =
            DateTime.now().millisecondsSinceEpoch - overlayActionTime;

        if (timeDiff < 30000) {
          debugPrint('🎯 Processing overlay ACCEPT: $overlayTripId');

          final overlayTripData = jsonDecode(overlayTripDataStr) as Map;

          setState(() {
            _activeTripId = overlayTripId;
            _ridePhase = 'going_to_pickup';
            _customerOtp =
                overlayTripData['otp']?.toString() ??
                overlayTripData['rideCode']?.toString();

            if (overlayTripData['trip'] != null) {
              final tripData = overlayTripData['trip'] as Map;
              _tripFareAmount = _parseDouble(tripData['fare']);
              _finalFareAmount = _tripFareAmount;

              final pickupData = tripData['pickup'];
              if (pickupData != null) {
                final pickupLat = pickupData['lat'];
                final pickupLng = pickupData['lng'];
                if (pickupLat != null && pickupLng != null) {
                  _customerPickup = LatLng(
                    _parseDouble(pickupLat),
                    _parseDouble(pickupLng),
                  );
                }
              }
            }

            _activeTripDetails = {
              'tripId': overlayTripId,
              'trip': overlayTripData['trip'] ?? {},
              'customer': overlayTripData['customer'] ?? {},
              'otp': overlayTripData['otp'] ?? overlayTripData['rideCode'],
              'rideCode': overlayTripData['rideCode'] ?? overlayTripData['otp'],
              'status': overlayTripData['status'] ?? 'driver_assigned',
            };
          });

          await prefs.remove('flutter.overlay_action');
          await prefs.remove('flutter.overlay_trip_id');
          await prefs.remove('flutter.overlay_trip_data');
          await prefs.remove('flutter.overlay_action_time');

          _socketService.setActiveTrip(overlayTripId);
          _startLiveLocationUpdates();
          _startHeartbeat();

          if (_customerPickup != null) {
            _drawRouteToCustomer();
          }

          debugPrint('✅ Overlay trip activated');
        } else {
          await prefs.remove('flutter.overlay_action');
          await prefs.remove('flutter.overlay_trip_id');
          await prefs.remove('flutter.overlay_trip_data');
          await prefs.remove('flutter.overlay_action_time');
        }
      }
    } catch (e) {
      debugPrint('❌ Error checking overlay: $e');
    }
  }

  double _parseDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0.0;
    return 0.0;
  }

  Map<String, dynamic>? _parseIncomingTrip(dynamic rawData) {
    try {
      Map<String, dynamic> request;

      if (rawData is String) {
        request = jsonDecode(rawData) as Map<String, dynamic>;
      } else if (rawData is Map) {
        request = Map<String, dynamic>.from(rawData);
      } else {
        _log('Unsupported trip data format', level: Level.WARNING);
        return null;
      }

      debugPrint('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      debugPrint('🔍 _parseIncomingTrip called');
      debugPrint('   Raw keys: ${request.keys.toList()}');
      debugPrint('   pickupLat: ${request['pickupLat']}');
      debugPrint('   pickupLng: ${request['pickupLng']}');
      debugPrint('   dropLat: ${request['dropLat']}');
      debugPrint('   dropLng: ${request['dropLng']}');

      // ✅ HANDLE FLAT FCM STRUCTURE
      if (request.containsKey('pickupLat') && !request.containsKey('pickup')) {
        debugPrint('🔧 Converting FLAT FCM structure');

        final pickupLat = _parseDouble(request['pickupLat']);
        final pickupLng = _parseDouble(request['pickupLng']);
        final dropLat = _parseDouble(request['dropLat']);
        final dropLng = _parseDouble(request['dropLng']);

        debugPrint('   Parsed pickupLat: $pickupLat');
        debugPrint('   Parsed pickupLng: $pickupLng');
        debugPrint('   Parsed dropLat: $dropLat');
        debugPrint('   Parsed dropLng: $dropLng');

        if (pickupLat == 0 || pickupLng == 0) {
          debugPrint('❌ WARNING: Invalid pickup coordinates!');
        }

        request['pickup'] = {
          'lat': pickupLat,
          'lng': pickupLng,
          'address': request['pickupAddress'] ?? 'Pickup Location',
        };

        request['drop'] = {
          'lat': dropLat,
          'lng': dropLng,
          'address': request['dropAddress'] ?? 'Drop Location',
        };

        debugPrint(
          '✅ Converted: pickup=${request['pickup']}, drop=${request['drop']}',
        );
      }
      // ✅ HANDLE NESTED SOCKET STRUCTURE
      else if (request['pickup'] is String) {
        try {
          request['pickup'] = jsonDecode(request['pickup']);
        } catch (_) {}
      }

      if (request['drop'] is String) {
        try {
          request['drop'] = jsonDecode(request['drop']);
        } catch (_) {}
      }

      // Parse fare
      if (request['fare'] is String) {
        request['fare'] = double.tryParse(request['fare'].toString().trim());
      }

      // Preserve destination match flag
      request['isDestinationMatch'] =
          request['isDestinationMatch'] == true ||
          request['isDestinationMatch'] == 'true';

      debugPrint('✅ FINAL REQUEST:');
      debugPrint('   tripId: ${request['tripId']}');
      debugPrint('   fare: ${request['fare']}');
      debugPrint('   pickup: ${request['pickup']}');
      debugPrint('   drop: ${request['drop']}');
      debugPrint('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');

      return request;
    } catch (e, stack) {
      debugPrint('❌ Parse error: $e');
      debugPrint('Stack: $stack');
      _log('Failed to parse trip data: $e', level: Level.WARNING);
      return null;
    }
  }

  bool _isDuplicateTrip(String tripId) {
    // If already visible in UI → block
    if (_rideRequests.any((req) => _getTripId(req) == tripId)) {
      return true;
    }

    final lastSeen = _lastSeenTrips[tripId];
    if (lastSeen == null) return false;

    final diffSeconds = DateTime.now().difference(lastSeen).inSeconds;

    // 🔁 Allow retry after 10 seconds
    return diffSeconds < 10;
  }

  String? _getTripId(Map<String, dynamic> request) {
    return (request['tripId'] ?? request['_id'])?.toString();
  }

  // ===========================================================================
  // ACCEPT / REJECT RIDES
  // ===========================================================================

  Future<void> _acceptRide() async {
    print('');
    print('╔═══════════════════════════════════════════');
    print('🚗 _acceptRide() CALLED');
    print('╚═══════════════════════════════════════════');

    if (_currentRide == null) {
      print('   ❌ ERROR: _currentRide is NULL!');
      _showSnackBar('No ride selected', color: AppColors.error);
      return;
    }

    print('   Current Ride: $_currentRide');

    _stopNotificationSound();

    final tripId = _getTripId(_currentRide!);
    if (tripId == null || tripId.isEmpty) {
      print('   ❌ ERROR: No tripId found in currentRide');
      _log('No tripId found in currentRide', level: Level.WARNING);
      _showSnackBar('Invalid trip data', color: AppColors.error);
      return;
    }

    print('   Trip ID: $tripId');

    final fareAmount = _parseDouble(_currentRide!['fare']);
    print('   Fare: ₹$fareAmount');
    _log('Accepting ride: $tripId, fare: $fareAmount');

    try {
      // Check socket connection
      if (!_socketService.isConnected) {
        print('   ❌ Socket not connected!');
        _showSnackBar(
          'Not connected. Please check internet.',
          color: AppColors.error,
        );
        return;
      }

      print('   ✅ Socket connected: ${_socketService.socket?.id}');
      print('   📡 Emitting driver:accept_trip...');

      _socketService.emit('driver:accept_trip', {
        'tripId': tripId,
        'driverId': _driverId,
      });

      print('   ✅ Emit successful');
      print('   Payload: {tripId: $tripId, driverId: $_driverId}');

      _socketService.setActiveTrip(tripId);

      print('   🚀 Starting background trip service...');
      await TripBackgroundService.startTripService(
        tripId: tripId,
        driverId: _driverId,
        customerName: 'Customer',
      );
      print('   ✅ Background service started');

      print('   🔒 Enabling wakelock...');
      await WakelockPlus.enable();
      print('   ✅ Wakelock enabled');

      setState(() {
        _activeTripId = tripId;
        _ridePhase = 'going_to_pickup';
        _tripFareAmount = fareAmount;
        _finalFareAmount = fareAmount;
        _rideRequests.removeWhere((req) => _getTripId(req) == tripId);
        _currentRide = _rideRequests.isNotEmpty ? _rideRequests.first : null;
      });

      print('   ✅ State updated:');
      print('      _activeTripId: $_activeTripId');
      print('      _ridePhase: $_ridePhase');
      print('      Remaining requests: ${_rideRequests.length}');

      _startHeartbeat();
      print('   ✅ Heartbeat started');

      if (_currentRide != null) _playNotificationSound();

      _showSnackBar(
        'Ride Accepted! App will stay alive in background',
        color: AppColors.success,
      );
      _log('Ride accepted successfully: $tripId');

      print('╚═══════════════════════════════════════════');
      print('');
    } catch (e, stackTrace) {
      print('   ❌ ERROR in _acceptRide: $e');
      print('   Stack trace: $stackTrace');
      _log('Error accepting ride: $e', level: Level.SEVERE);
      _showSnackBar('Failed to accept: $e', color: AppColors.error);
    }
  }

  void _rejectRide() {
    if (_currentRide == null) return;

    _stopNotificationSound();

    final tripId = _getTripId(_currentRide!) ?? '';
    _log('Rejecting ride: $tripId');

    _socketService.rejectRide(_driverId, tripId);

    setState(() {
      _rideRequests.removeWhere((req) => _getTripId(req) == tripId);
      _currentRide = _rideRequests.isNotEmpty ? _rideRequests.first : null;
    });

    // 🔁 Allow retry after 10 seconds - remove from cooldown tracking
    _lastSeenTrips.remove(tripId);

    if (_currentRide != null) _playNotificationSound();
    _showSnackBar('Ride Rejected.');
  }
  // ===========================================================================
  // CHECK & RESUME ACTIVE TRIP
  // ===========================================================================

  Future<void> _checkAndResumeActiveTrip() async {
    try {
      _log('Checking for active trip on restart');

      final response = await http.get(
        Uri.parse('$_apiBase/api/trip/driver/active/${widget.driverId}'),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode != 200) {
        _log('Failed to check active trip: ${response.statusCode}');
        return;
      }

      final data = jsonDecode(response.body);

      if (!data['success'] || !data['hasActiveTrip']) {
        _log('No active trip found');
        await _clearDriverStateOnBackend();
        return;
      }

      final tripData = data['trip'];
      final customerData = data['customer'];
      final paymentCollected = tripData['paymentCollected'] ?? false;

      _log(
        'Active trip detected: ${tripData['tripId']}, status: ${tripData['status']}',
      );

      // If payment already collected, clean up
      if (paymentCollected == true) {
        _log('Payment already collected - cleaning up stale data');
        await _cleanupCompletedTrip();
        return;
      }

      // Resume the active trip
      await _resumeActiveTrip(tripData, customerData);
    } catch (e) {
      _log('Error checking active trip: $e', level: Level.SEVERE);
    }
  }

  Future<void> _cleanupCompletedTrip() async {
    await _clearDriverStateOnBackend();
    _clearActiveTrip();
    _socketService.setActiveTrip(null);
    await TripBackgroundService.stopTripService();
    await WakelockPlus.disable();
  }

  Future<void> _resumeActiveTrip(
    Map<String, dynamic> tripData,
    Map<String, dynamic>? customerData,
  ) async {
    // 🔥 ridePhase comes from backend now for all states including 'completed'
    final resumedPhase = tripData['ridePhase'] ?? 'going_to_pickup';

    // 🔥 Safely extract pickup/drop — backend now always sends them,
    //    but guard here so a bad response never crashes the app.
    final pickupMap = tripData['pickup'] as Map<String, dynamic>?;
    final dropMap = tripData['drop'] as Map<String, dynamic>?;

    final double? pickupLat = _parseDouble(pickupMap?['lat']);
    final double? pickupLng = _parseDouble(pickupMap?['lng']);

    setState(() {
      _activeTripId = tripData['tripId'];
      _ridePhase = resumedPhase;
      _customerOtp =
          tripData['rideCode']?.toString() ?? tripData['otp']?.toString();
      _tripFareAmount = _parseDouble(tripData['fare']);
      _finalFareAmount = _parseDouble(
        tripData['finalFare'] ?? tripData['fare'],
      );

      _activeTripDetails = {
        'tripId': tripData['tripId'],
        'trip': {
          'pickup': pickupMap ?? {},
          'drop': dropMap ?? {},
          'fare': tripData['fare'],
        },
        'customer': customerData,
      };

      // Only set pickup marker if we have valid coordinates
      if (pickupLat != null &&
          pickupLng != null &&
          pickupLat != 0.0 &&
          pickupLng != 0.0) {
        _customerPickup = LatLng(pickupLat, pickupLng);
      }
    });

    _socketService.setActiveTrip(tripData['tripId'] ?? '');

    await TripBackgroundService.startTripService(
      tripId: tripData['tripId'] ?? '',
      driverId: widget.driverId,
      customerName: customerData?['name'] ?? 'Customer',
    );

    await WakelockPlus.enable();
    _startLiveLocationUpdates();
    _startHeartbeat();

    if (_ridePhase == 'going_to_pickup' || _ridePhase == 'at_pickup') {
      _drawRouteToCustomer();
    }

    _log('Trip resumed: ${tripData['tripId']}, phase: $_ridePhase');

    // Silent resume to avoid repeated restore toasts.
  }

  // ===========================================================================
  // CLEAR ACTIVE TRIP
  // ===========================================================================

  // ===========================================================================
  // 🔥 NEW: BACKEND VERIFICATION HELPERS
  // ===========================================================================

  /// 🔥 Fetch trip details from backend for verification
  Future<Map<String, dynamic>?> _fetchTripFromBackend(String tripId) async {
    try {
      _log('Fetching trip from backend: $tripId');

      final token = await FirebaseAuth.instance.currentUser?.getIdToken();

      final headers = <String, String>{'Content-Type': 'application/json'};

      if (token != null) {
        headers['Authorization'] = 'Bearer $token';
      }

      final response = await http
          .get(Uri.parse('$_apiBase/api/trip/$tripId'), headers: headers)
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['trip'] != null) {
          _log('Trip fetched successfully: ${data['trip']['status']}');
          return data['trip'] as Map<String, dynamic>;
        }
      } else if (response.statusCode == 404) {
        _log('Trip not found (404)');
      } else {
        _log('Failed to fetch trip: ${response.statusCode}');
      }

      return null;
    } catch (e) {
      _log('Error fetching trip from backend: $e', level: Level.WARNING);
      return null;
    }
  }

  /// 🔥 Update UI based on trip status from backend (SINGLE SOURCE OF TRUTH)
  void _updateUIFromTripStatus(Map<String, dynamic> trip) {
    final status = (trip['status']?.toString() ?? '').toLowerCase();
    final tripId = trip['tripId']?.toString() ?? trip['_id']?.toString() ?? '';

    _log('Updating UI from trip status: $status (tripId: $tripId)');

    switch (status) {
      case 'driver_assigned':
      case 'driver_going_to_pickup':
        setState(() {
          _ridePhase = 'going_to_pickup';
          _activeTripId = tripId;
        });
        _drawRouteToCustomer();
        break;

      case 'driver_at_pickup':
        setState(() {
          _ridePhase = 'at_pickup';
          _activeTripId = tripId;
        });
        break;

      case 'ride_started':
      case 'in_progress':
      case 'on_trip':
        setState(() {
          _ridePhase = 'going_to_drop';
          _activeTripId = tripId;
        });
        break;

      case 'awaiting_payment':
        // Driver finished ride, waiting to collect cash
        setState(() {
          _ridePhase = 'completed';
          _finalFareAmount = _tripFareAmount ?? 0.0;
        });
        break;

      case 'completed':
        setState(() {
          _ridePhase = 'completed';
          _finalFareAmount = _tripFareAmount ?? 0.0;
        });
        break;

      case 'cancelled':
      case 'timeout':
      case 'payment_done':
      case 'payment_collected':
        _log('Trip is $status - clearing local state');
        _clearActiveTrip();
        TripBackgroundService.stopTripService();
        WakelockPlus.disable();
        _socketService.setActiveTrip(null);
        break;

      default:
        _log('Unknown trip status: $status');
    }
  }

  /// 🔥 Restore active trip from widget (passed from splash/login)
  Future<void> _restoreActiveTripFromWidget(
    Map<String, dynamic> tripData,
  ) async {
    try {
      final tripId =
          tripData['tripId']?.toString() ?? tripData['_id']?.toString() ?? '';

      if (tripId.isEmpty) {
        _log('No tripId in widget.activeTrip - skipping restore');
        return;
      }

      _log('Restoring active trip from widget: $tripId');

      // 🔥 The splash already passed full verified data (pickup, drop, ridePhase, otp).
      //    Use it directly — the splash already called getDriverActiveTrip which is
      //    now the source of truth. Only fall back to a raw fetch if key fields missing.
      final hasFullData =
          tripData['pickup'] != null && tripData['ridePhase'] != null;

      if (hasFullData) {
        _log('Using full trip data from splash widget');
        final inactiveStatuses = [
          'completed',
          'cancelled',
          'timeout',
          'payment_done',
          'payment_collected',
          'finished',
          'ended',
        ];
        final status = (tripData['status']?.toString() ?? '').toLowerCase();
        if (inactiveStatuses.contains(status)) {
          _log('Trip is $status - not restoring');
          return;
        }
        await _resumeActiveTrip(
          tripData,
          tripData['customer'] as Map<String, dynamic>?,
        );
        return;
      }

      // Fallback: re-fetch from backend if splash didn't include full data
      _log('Falling back to backend fetch for trip $tripId');
      final verifiedTrip = await _fetchTripFromBackend(tripId);

      if (verifiedTrip == null) {
        _log('Trip not found on backend - not restoring');
        return;
      }

      final status = (verifiedTrip['status']?.toString() ?? '').toLowerCase();

      final inactiveStatuses = [
        'completed',
        'cancelled',
        'timeout',
        'payment_done',
        'payment_collected',
        'finished',
        'ended',
      ];

      if (inactiveStatuses.contains(status)) {
        _log('Trip is $status - not restoring');
        return;
      }

      // Merge: prefer verifiedTrip fields but fill in pickup/drop from widget if missing
      final merged = Map<String, dynamic>.from(verifiedTrip);
      if (merged['pickup'] == null)
        merged['pickup'] = tripData['trip']?['pickup'];
      if (merged['drop'] == null) merged['drop'] = tripData['trip']?['drop'];
      if (merged['ridePhase'] == null) {
        // Map status → ridePhase (Dart 2 compatible)
        String mappedPhase;
        if (status == 'ride_started') {
          mappedPhase = 'going_to_drop';
        } else if (status == 'driver_at_pickup') {
          mappedPhase = 'at_pickup';
        } else if (status == 'awaiting_payment') {
          mappedPhase = 'completed';
        } else {
          mappedPhase = 'going_to_pickup';
        }
        merged['ridePhase'] = mappedPhase;
      }

      await _resumeActiveTrip(
        merged,
        tripData['customer'] as Map<String, dynamic>?,
      );
    } catch (e) {
      _log('Error restoring trip from widget: $e', level: Level.WARNING);
    }
  }

  /// 🔥 Version-guarded socket event handler
  void _handleVersionedTripUpdate(dynamic data) {
    final int version = data['version'] ?? 0;

    if (version <= _lastTripVersion) {
      _log('Ignoring old socket event (version $version <= $_lastTripVersion)');
      return;
    }

    _lastTripVersion = version;
    _log('Processing socket event (version $version)');

    final trip = data['trip'] as Map<String, dynamic>?;
    if (trip != null) {
      _updateUIFromTripStatus(trip);
    }
  }
  // ===========================================================================
  // HEARTBEAT & LOCATION UPDATES
  // ===========================================================================

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(_heartbeatInterval, (_) {
      if (_activeTripId != null) {
        _socketService.emit('driver:heartbeat', {
          'tripId': _activeTripId,
          'driverId': widget.driverId,
          'timestamp': DateTime.now().toIso8601String(),
        });
      }
    });
  }

  void _startLiveLocationUpdates() {
    _locationUpdateTimer?.cancel();
    _locationUpdateTimer = Timer.periodic(_locationUpdateInterval, (_) async {
      if (_currentPosition == null) return;

      try {
        final pos = await Geolocator.getCurrentPosition();
        _currentPosition = LatLng(pos.latitude, pos.longitude);
        _updateDriverStatusSocket();
        _sendLocationToBackend(pos.latitude, pos.longitude);
      } catch (e) {
        _log('Location update error: $e', level: Level.WARNING);
      }
    });
  }

  Future<void> _sendLocationToBackend(double lat, double lng) async {
    try {
      await http.post(
        Uri.parse('$_apiBase/api/location/updateDriver'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'driverId': _driverId,
          'latitude': lat,
          'longitude': lng,
          'tripId': _activeTripId,
        }),
      );

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('lastLat', lat.toString());
      await prefs.setString('lastLng', lng.toString());

      _socketService.emit('driver:location', {
        'tripId': _activeTripId,
        'latitude': lat,
        'longitude': lng,
      });
    } catch (e) {
      _log('Error sending location: $e', level: Level.WARNING);
    }
  }

  // ===========================================================================
  // DRIVER STATUS UPDATE
  // ===========================================================================

  Future<void> _updateDriverStatusSocket() async {
    final lat = _currentPosition?.latitude ?? 0.0;
    final lng = _currentPosition?.longitude ?? 0.0;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('lastLat', lat.toString());
    await prefs.setString('lastLng', lng.toString());
    await prefs.setBool('isOnline', _isOnline);
    await prefs.setString('vehicleType', widget.vehicleType);
    await prefs.setBool('acceptsLong', _acceptsLong);

    _socketService.updateDriverStatus(
      _driverId,
      _isOnline,
      lat,
      lng,
      widget.vehicleType,
      fcmToken: _driverFcmToken,
      profileData: null,
    );

    _log('Driver status updated: ${_isOnline ? 'ONLINE' : 'OFFLINE'}');
  }

  // ===========================================================================
  // BACKEND API CALLS
  // ===========================================================================

  Future<void> _clearDriverStateOnBackend() async {
    try {
      final token = await FirebaseAuth.instance.currentUser?.getIdToken();
      if (token == null) {
        _log('No Firebase token for clear-state', level: Level.WARNING);
        return;
      }

      final response = await http.post(
        Uri.parse('$_apiBase/api/driver/clear-state'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'driverId': widget.driverId}),
      );

      if (response.statusCode == 200) {
        _log('Backend state cleared successfully');
      } else {
        _log('Failed to clear backend state: ${response.statusCode}');
      }
    } catch (e) {
      _log('Error clearing backend state: $e', level: Level.WARNING);
    }
  }

  // ── Shared auth-token helper (mirrors ride_history & wallet_page pattern) ──
  Future<String?> _loadAuthToken() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString('auth_token');
      if (stored != null && stored.isNotEmpty) return stored;
    } catch (_) {}
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final idToken = await user.getIdToken();
        return idToken;
      }
    } catch (e) {
      _log('Firebase getIdToken failed: $e', level: Level.WARNING);
    }
    return null;
  }

  Future<void> _fetchWalletData() async {
    setState(() => _isLoadingWallet = true);

    try {
      final token = await _loadAuthToken();
      final response = await http.get(
        Uri.parse('$_apiBase/api/wallet/${widget.driverId}'),
        headers: {
          'Content-Type': 'application/json',
          if (token != null && token.isNotEmpty)
            'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && mounted) {
          setState(() {
            _walletData = data['wallet'];
            _isLoadingWallet = false;
          });
        } else {
          setState(() => _isLoadingWallet = false);
        }
      } else {
        _log(
          'Wallet fetch failed: ${response.statusCode}',
          level: Level.WARNING,
        );
        setState(() => _isLoadingWallet = false);
      }
    } catch (e) {
      _log('Error fetching wallet: $e', level: Level.WARNING);
      setState(() => _isLoadingWallet = false);
    }
  }

  Future<void> _fetchTodayEarnings() async {
    setState(() => _isLoadingToday = true);

    try {
      final token = await _loadAuthToken();
      final response = await http.get(
        Uri.parse('$_apiBase/api/wallet/today/${widget.driverId}'),
        headers: {
          'Content-Type': 'application/json',
          if (token != null && token.isNotEmpty)
            'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && mounted) {
          setState(() {
            _todayEarnings = data['todayStats'];
            _isLoadingToday = false;
          });
        } else {
          setState(() => _isLoadingToday = false);
        }
      } else {
        _log(
          'Today earnings fetch failed: ${response.statusCode}',
          level: Level.WARNING,
        );
        setState(() => _isLoadingToday = false);
      }
    } catch (e) {
      _log('Error fetching today earnings: $e', level: Level.WARNING);
      setState(() => _isLoadingToday = false);
    }
  }

  // Fetches perRideIncentive/perRideCoins from the same backend endpoint used
  // to preview the exact amount awarded during trip completion.
  Future<void> _fetchTripRequestIncentive() async {
    try {
      final response = await http.get(
        Uri.parse('$_apiBase/api/trips/incentives/${widget.driverId}'),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final payload = (data['data'] is Map)
            ? Map<String, dynamic>.from(data['data'])
            : data;

        final fetchedIncentive = _parseDouble(payload['perRideIncentive']);
        final fetchedCoins = _parseDouble(payload['perRideCoins']).round();

        if (mounted && fetchedIncentive >= 0) {
          final shouldKeepExisting =
              fetchedIncentive == 0 && _perRideIncentive > 0;
          setState(() {
            if (!shouldKeepExisting) {
              _perRideIncentive = fetchedIncentive;
            }
            _perRideCoins = fetchedCoins >= 0 ? fetchedCoins : 0;
          });
          _log(
            shouldKeepExisting
                ? 'Trip incentive preview returned 0, keeping cached ₹$_perRideIncentive'
                : 'Trip incentive preview fetched: ₹$_perRideIncentive + $_perRideCoins coins (${widget.vehicleType})',
          );
        }
      } else {
        _log(
          'Trip incentive preview API failed: HTTP ${response.statusCode}. Falling back to commission preview.',
          level: Level.WARNING,
        );
        await _fetchTripRequestIncentiveFallback();
      }
    } catch (e) {
      _log('Error fetching trip incentive preview: $e', level: Level.WARNING);
      await _fetchTripRequestIncentiveFallback();
    }
  }

  // Fallback for environments where /api/trips/incentives/:driverId may be unavailable.
  Future<void> _fetchTripRequestIncentiveFallback() async {
    try {
      final response = await http.get(
        Uri.parse(
          '$_apiBase/api/commission/incentive-preview?vehicleType=${widget.vehicleType}',
        ),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode != 200) {
        _log(
          'Commission incentive fallback failed: HTTP ${response.statusCode}',
          level: Level.WARNING,
        );
        return;
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final payload = (data['data'] is Map)
          ? Map<String, dynamic>.from(data['data'])
          : data;

      final fetchedIncentive = _parseDouble(payload['perRideIncentive']);
      final fetchedCoins = _parseDouble(payload['perRideCoins']).round();

      if (mounted && fetchedIncentive >= 0) {
        final shouldKeepExisting =
            fetchedIncentive == 0 && _perRideIncentive > 0;
        setState(() {
          if (!shouldKeepExisting) {
            _perRideIncentive = fetchedIncentive;
          }
          _perRideCoins = fetchedCoins >= 0 ? fetchedCoins : _perRideCoins;
        });
        _log(
          shouldKeepExisting
              ? 'Fallback incentive returned 0, keeping cached ₹$_perRideIncentive'
              : 'Fallback incentive fetched: ₹$_perRideIncentive + $_perRideCoins coins (${widget.vehicleType})',
        );
      }
    } catch (e) {
      _log('Fallback incentive fetch error: $e', level: Level.WARNING);
    }
  }

  // 🔥 Fetch active plan from the correct endpoint (same one IncentivesPage uses)
  Future<void> _fetchActivePlan() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final token = await user.getIdToken();
      if (token == null) return;

      final response = await http
          .get(
            Uri.parse('$_apiBase/api/driver/plan/current'),
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        if (body['success'] == true && body['data'] != null) {
          final data = body['data'] as Map<String, dynamic>;
          final isActive = data['isActive'] as bool? ?? false;

          if (mounted) {
            setState(() {
              if (isActive) {
                _activePlanName = data['planName']?.toString();
                _activePlanCommission = (data['commissionRate'] as num?)
                    ?.toDouble();
                _activePlanBonus = (data['bonusMultiplier'] as num?)
                    ?.toDouble();
              } else {
                // Plan expired or inactive — clear so UI doesn't show stale data
                _activePlanName = null;
                _activePlanCommission = null;
                _activePlanBonus = null;
              }
            });
            _log(
              'Active plan fetched: $_activePlanName, commission: $_activePlanCommission%',
            );
          }
        } else {
          // No active plan
          if (mounted) {
            setState(() {
              _activePlanName = null;
              _activePlanCommission = null;
              _activePlanBonus = null;
            });
          }
        }
      }
    } catch (e) {
      _log('Error fetching active plan: $e', level: Level.WARNING);
    }
  }

  // ===========================================================================
  // PLAN EVENT HANDLERS: SOCKET EVENTS
  // ===========================================================================

  void _handlePlanActivated(dynamic data) {
    if (!mounted) return;

    try {
      final planData = data as Map<String, dynamic>? ?? {};

      final planName = planData['planName']?.toString();
      final commissionRate = (planData['commissionRate'] as num?)?.toDouble();
      final bonusMultiplier = (planData['bonusMultiplier'] as num?)?.toDouble();

      if (planName != null &&
          commissionRate != null &&
          bonusMultiplier != null) {
        setState(() {
          _activePlanName = planName;
          _activePlanCommission = commissionRate;
          _activePlanBonus = bonusMultiplier;
        });

        _log(
          'Plan activated: $planName (Commission: ${commissionRate}%, Bonus: ${bonusMultiplier}x)',
        );

        // Show notification
        _showSnackBar(
          '🎉 $planName activated! Earn ${(bonusMultiplier * 100 - 100).toStringAsFixed(0)}% more with each ride',
          color: AppColors.success,
        );
      }
    } catch (e) {
      _log('Error handling plan:activated event: $e', level: Level.WARNING);
    }
  }

  void _handlePlanExpired(dynamic data) {
    if (!mounted) return;

    try {
      final planName =
          (data as Map<String, dynamic>? ?? {})['planName']?.toString() ??
          'Plan';

      setState(() {
        _activePlanName = null;
        _activePlanCommission = null;
        _activePlanBonus = null;
      });

      _log('Plan expired: $planName');

      // Show notification
      _showSnackBar(
        '$planName has expired. Using base commission rates.',
        color: AppColors.warning,
      );
    } catch (e) {
      _log('Error handling plan:expired event: $e', level: Level.WARNING);
    }
  }

  Future<void> _fetchDriverProfileSummary() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        _log('No Firebase user for profile summary', level: Level.WARNING);
        return;
      }

      final token = await user.getIdToken();

      final response = await http.get(
        Uri.parse('$_apiBase/api/driver/profile'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final profileData = jsonDecode(response.body);

        final driver = profileData['driver'] ?? profileData;

        if (mounted) {
          setState(() {
            _driverName = driver['name']?.toString();
            _driverPhotoUrl = driver['photoUrl']?.toString();
          });
        }

        _log('Driver profile summary loaded for drawer');
      } else {
        _log(
          'Profile summary error: ${response.statusCode}',
          level: Level.WARNING,
        );
      }
    } catch (e) {
      _log('Error fetching profile summary: $e', level: Level.WARNING);
    }
  }
  // ===========================================================================
  // LOCATION PERMISSION & CURRENT LOCATION
  // ===========================================================================

  Future<void> _requestLocationPermission() async {
    final status = await Permission.location.request();
    if (!status.isGranted && mounted) {
      _showSnackBar('Location permission is required to use map.');
    }
  }

  Future<void> _getCurrentLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        await Geolocator.openLocationSettings();
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          _showSnackBar('Location permissions are denied');
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        _showSnackBar('Location permissions are permanently denied');
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      setState(() {
        _currentPosition = LatLng(position.latitude, position.longitude);
      });

      _mapController?.animateCamera(CameraUpdate.newLatLng(_currentPosition!));
    } catch (e) {
      _log('Error getting location: $e', level: Level.WARNING);
    }
  }

  // ===========================================================================
  // AUDIO HELPERS
  // ===========================================================================

  Future<void> _playNotificationSound() async {
    try {
      await _audioPlayer.play(AssetSource('sounds/notification.mp3'));
    } catch (e) {
      _log('Error playing sound: $e', level: Level.WARNING);
    }
  }

  Future<void> _stopNotificationSound() async {
    try {
      await _audioPlayer.stop();
    } catch (_) {}
  }

  // ===========================================================================
  // UTILITY HELPERS
  // ===========================================================================

  double _calculateDistance(LatLng point1, LatLng point2) {
    return Geolocator.distanceBetween(
      point1.latitude,
      point1.longitude,
      point2.latitude,
      point2.longitude,
    );
  }

  bool _isHardErrorMessage(String message) {
    final m = message.toLowerCase();
    const hardErrorKeywords = [
      'error',
      'failed',
      'invalid',
      'denied',
      'not found',
      'not available',
      'required',
      'cannot',
      'unable',
      'timeout',
      'timed out',
      'not connected',
      'permission',
      'incorrect otp',
      'no active trip',
      'trip fare not available',
    ];

    return hardErrorKeywords.any((k) => m.contains(k));
  }

  void _showSnackBar(String message, {Color? color}) {
    if (!mounted) return;

    final isHardError =
        color == AppColors.error || _isHardErrorMessage(message);
    if (!isHardError) return;

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
                        message,
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

  // ============================================================================
  // END OF PART 1 - Continue with Part 2 for remaining methods and UI builders
  // ============================================================================
  // ============================================================================
  // driver_dashboard_page.dart - Part 2 of 2
  // Trip actions, route drawing, UPI payment, and UI builders
  // ============================================================================

  // ===========================================================================
  // TRIP ACTIONS: GO TO PICKUP
  // ===========================================================================

  Future<void> _goToPickup() async {
    // 🔥 PREVENT DOUBLE-TAP
    if (_actionInProgress) {
      _log('Action already in progress - ignoring');
      return;
    }

    if (_activeTripId == null) return;

    setState(() => _actionInProgress = true);

    try {
      // 🔥 VERIFY BACKEND STATE BEFORE ACTION
      final trip = await _fetchTripFromBackend(_activeTripId!);

      if (trip == null) {
        _showSnackBar('Trip not found. Please try again.');
        return;
      }

      final tripStatus = (trip['status']?.toString() ?? '').toLowerCase();

      // 🔥 Only allow if status is correct
      if (tripStatus != 'driver_assigned' &&
          tripStatus != 'driver_going_to_pickup') {
        _showStatusCard(
          icon: Icons.error_outline,
          title: 'Invalid Trip State',
          message: 'Cannot mark arrived. Current status: $tripStatus',
          color: AppColors.error,
        );
        return;
      }

      // Proceed with the action
      final response = await http.post(
        Uri.parse('$_apiBase/api/trip/going-to-pickup'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'tripId': _activeTripId, 'driverId': _driverId}),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200 && data['success']) {
        setState(() => _ridePhase = 'at_pickup');
        _log('Arrived at pickup');
      } else {
        _showSnackBar(data['message'] ?? 'Failed to update status');
      }
    } catch (e) {
      _log('Error in goToPickup: $e', level: Level.SEVERE);
      _showSnackBar('Error: $e');
    } finally {
      // 🔥 ALWAYS RESET ACTION STATE
      if (mounted) {
        setState(() => _actionInProgress = false);
      }
    }
  }

  // ===========================================================================
  // TRIP ACTIONS: START RIDE
  // ===========================================================================

  Future<void> _startRide() async {
    // 🔥 PREVENT DOUBLE-TAP
    if (_actionInProgress) {
      _log('Action already in progress - ignoring');
      return;
    }

    if (_activeTripId == null || _currentPosition == null) return;

    // 🔥 Read OTP from 4-box controllers (fallback to legacy single field)
    final enteredOtp =
        _otpBoxControllers.map((c) => c.text.trim()).join().isNotEmpty
        ? _otpBoxControllers.map((c) => c.text.trim()).join()
        : _otpController.text.trim();
    if (enteredOtp.isEmpty) {
      _showStatusCard(
        icon: Icons.lock_outline,
        title: 'OTP Required',
        message: 'Please enter the 4-digit code from customer',
        color: AppColors.error,
      );
      return;
    }

    setState(() => _actionInProgress = true);

    try {
      // 🔥 VERIFY BACKEND STATE BEFORE ACTION
      final trip = await _fetchTripFromBackend(_activeTripId!);

      if (trip == null) {
        _showSnackBar('Trip not found. Please try again.');
        return;
      }

      final tripStatus = trip['status']?.toString().toLowerCase() ?? '';

      // 🔥 Only allow if status is 'driver_at_pickup'
      if (tripStatus != 'driver_at_pickup') {
        _showStatusCard(
          icon: Icons.error_outline,
          title: 'Cannot Start Ride',
          message:
              'You must be at pickup location first. Current status: $tripStatus',
          color: AppColors.error,
        );
        return;
      }

      _showLoadingDialog('Starting ride...');

      _socketService.emit('trip:start_ride', {
        'tripId': _activeTripId,
        'driverId': _driverId,
        'otp': enteredOtp,
      });

      final response = await http.post(
        Uri.parse('$_apiBase/api/trip/start-ride'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'tripId': _activeTripId,
          'driverId': _driverId,
          'otp': enteredOtp,
          'driverLat': _currentPosition!.latitude,
          'driverLng': _currentPosition!.longitude,
        }),
      );

      _dismissLoadingDialog();

      final data = jsonDecode(response.body);

      if (response.statusCode == 200 && data['success']) {
        setState(() {
          _ridePhase = 'going_to_drop';
          _otpController.clear();
        });

        _sendLocationToBackend(
          _currentPosition!.latitude,
          _currentPosition!.longitude,
        );

        _log('Ride started successfully');
      } else {
        final backendMessage =
            (data['message']?.toString().trim().isNotEmpty ?? false)
            ? data['message'].toString().trim()
            : 'Unable to start ride. Please try again.';
        final normalizedMessage = backendMessage.toLowerCase();

        final isProximityError =
            normalizedMessage.contains('too far') ||
            normalizedMessage.contains('pickup location') ||
            normalizedMessage.contains('not at pickup');
        final isOtpError =
            normalizedMessage.contains('otp') ||
            normalizedMessage.contains('code') ||
            normalizedMessage.contains('invalid');

        _showStatusCard(
          icon: isProximityError
              ? Icons.location_off_outlined
              : Icons.error_outline,
          title: isProximityError
              ? 'Not at Pickup Location'
              : (isOtpError ? 'Incorrect Ride Code' : 'Unable to Start Ride'),
          message: isProximityError
              ? backendMessage
              : (isOtpError
                    ? 'Ride code is incorrect. Please verify with customer and try again.'
                    : backendMessage),
          color: isProximityError ? AppColors.warning : AppColors.error,
          duration: const Duration(seconds: 4),
        );
      }
    } catch (e) {
      _dismissLoadingDialog();
      _log('Error starting ride: $e', level: Level.SEVERE);
      _showStatusCard(
        icon: Icons.error_outline,
        title: 'Error',
        message: 'Failed to start ride. Please try again.',
        color: AppColors.error,
      );
    } finally {
      // 🔥 ALWAYS RESET ACTION STATE
      if (mounted) {
        setState(() => _actionInProgress = false);
      }
    }
  }
  // ===========================================================================
  // TRIP ACTIONS: COMPLETE RIDE
  // ===========================================================================

  Future<void> _completeRide() async {
    // 🔥 PREVENT DOUBLE-TAP
    if (_actionInProgress) {
      _log('Action already in progress - ignoring');
      return;
    }

    if (_activeTripId == null || _currentPosition == null) return;

    setState(() => _actionInProgress = true);

    try {
      // 🔥 VERIFY BACKEND STATE BEFORE ACTION
      final trip = await _fetchTripFromBackend(_activeTripId!);

      if (trip == null) {
        _showSnackBar('Trip not found. Please try again.');
        return;
      }

      final tripStatus = trip['status']?.toString().toLowerCase() ?? '';

      // 🔥 Only allow if status is 'ride_started' or 'awaiting_payment' (resume after restart)
      if (tripStatus != 'ride_started' &&
          tripStatus != 'in_progress' &&
          tripStatus != 'on_trip' &&
          tripStatus != 'awaiting_payment') {
        _showStatusCard(
          icon: Icons.error_outline,
          title: 'Cannot Complete Ride',
          message: 'Ride is not active. Current status: $tripStatus',
          color: AppColors.error,
        );
        return;
      }

      _showLoadingDialog('Completing ride...', color: AppColors.success);

      _socketService.emit('trip:complete_ride', {
        'tripId': _activeTripId,
        'driverId': _driverId,
      });

      final response = await http.post(
        Uri.parse('$_apiBase/api/trip/complete-ride'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'tripId': _activeTripId,
          'driverId': _driverId,
          'driverLat': _currentPosition!.latitude,
          'driverLng': _currentPosition!.longitude,
        }),
      );

      _dismissLoadingDialog();

      final data = jsonDecode(response.body);

      if (response.statusCode == 200 && data['success']) {
        setState(() {
          _ridePhase = 'completed';
          _finalFareAmount = _tripFareAmount ?? 0.0;
        });
        _log('Ride completed successfully');
      } else {
        _showStatusCard(
          icon: Icons.error_outline,
          title: 'Failed',
          message: data['message'] ?? 'Could not complete ride',
          color: AppColors.error,
        );
      }
    } catch (e) {
      _dismissLoadingDialog();
      _log('Error completing ride: $e', level: Level.SEVERE);
      _showStatusCard(
        icon: Icons.error_outline,
        title: 'Error',
        message: 'Failed to complete ride. Please try again.',
        color: AppColors.error,
      );
    } finally {
      // 🔥 ALWAYS RESET ACTION STATE
      if (mounted) {
        setState(() => _actionInProgress = false);
      }
    }
  }
  // ===========================================================================
  // TRIP ACTIONS: CONFIRM CASH COLLECTION
  // ===========================================================================

  Future<void> _confirmCashCollection() async {
    // 🔥 PREVENT DOUBLE-TAP
    if (_actionInProgress) {
      _log('Action already in progress - ignoring');
      return;
    }

    if (_activeTripId == null) {
      _showSnackBar('No active trip found');
      return;
    }

    setState(() => _actionInProgress = true);

    if (_tripFareAmount == null || _tripFareAmount! <= 0) {
      if (mounted)
        setState(
          () => _actionInProgress = false,
        ); // 🔥 FIXED: was missing reset
      _showSnackBar('Trip fare not available. Please try again.');
      return;
    }

    _log('Confirming cash collection: $_activeTripId, fare: ₹$_tripFareAmount');

    try {
      final response = await http.post(
        Uri.parse('$_apiBase/api/trip/confirm-cash'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'tripId': _activeTripId,
          'driverId': _driverId,
          'fare': _tripFareAmount,
        }),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200 && data['success']) {
        _socketService.setActiveTrip(null);
        await TripBackgroundService.stopTripService();
        await WakelockPlus.disable();

        _log('Cash collection confirmed, background service stopped');

        // 🔥 FIX: Clear isBusy on backend + broadcast driver available so new
        //         trip requests are dispatched immediately (no splash restart needed)
        await _clearDriverStateOnBackend();
        _updateDriverStatusSocket();

        if (mounted) {
          await _showCashCollectionSuccessDialog(data);
        }
      } else {
        _showSnackBar(data['message'] ?? 'Failed to confirm cash collection');
      }
    } catch (e) {
      _log('Error confirming cash: $e', level: Level.SEVERE);
      _showSnackBar('Error: $e');
    } finally {
      // 🔥 ALWAYS RESET ACTION STATE
      if (mounted) {
        setState(() => _actionInProgress = false);
      }
    }
  }

  Future<void> _showCashCollectionSuccessDialog(
    Map<String, dynamic> data,
  ) async {
    final fareBreakdown = data['fareBreakdown'];
    final walletInfo = data['wallet'];

    // 🔥 FIX: Check if fareBreakdown is null
    if (fareBreakdown == null) {
      _log('Warning: fareBreakdown is null in response', level: Level.WARNING);
      _showSnackBar('Trip completed but fare details unavailable');
      _clearActiveTrip();
      _fetchWalletData();
      _fetchTodayEarnings();
      return;
    }

    await showModalBottomSheet(
      context: context,
      isDismissible: false,
      enableDrag: false,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _buildEarningsBottomSheet(
        ctx,
        fareBreakdown: fareBreakdown,
        walletInfo: walletInfo,
      ),
    );
  }

  Widget _buildEarningsBottomSheet(
    BuildContext ctx, {
    required Map<String, dynamic> fareBreakdown,
    Map<String, dynamic>? walletInfo,
  }) {
    final tripFare = _parseDouble(fareBreakdown['tripFare'] ?? 0) ?? 0.0;
    final commission = _parseDouble(fareBreakdown['commission'] ?? 0) ?? 0.0;
    final driverEarning =
        _parseDouble(fareBreakdown['driverEarning'] ?? 0) ?? 0.0;
    final commissionPctValue =
        _parseDouble(fareBreakdown['commissionPercentage'] ?? 20) ?? 20.0;
    final commissionPctLabel = commissionPctValue % 1 == 0
        ? commissionPctValue.toStringAsFixed(0)
        : commissionPctValue.toStringAsFixed(2);
    final baseCommissionRate =
        _parseDouble(
          fareBreakdown['baseCommissionRate'] ??
              fareBreakdown['commissionPercentage'] ??
              0,
        ) ??
        0.0;
    final baseCommissionRateLabel = baseCommissionRate % 1 == 0
        ? baseCommissionRate.toStringAsFixed(0)
        : baseCommissionRate.toStringAsFixed(2);

    // ✅ NEW: read incentive fields sent by the updated backend
    final incentiveAwarded =
        _parseDouble(fareBreakdown['incentiveAwarded'] ?? 0) ?? 0.0;
    final totalEarnings =
        _parseDouble(fareBreakdown['totalEarnings'] ?? 0) ?? 0.0;
    final commissionPart =
        _parseDouble(fareBreakdown['commissionPart']) ??
        (tripFare * (baseCommissionRate / 100));
    final platformFeeFlat =
        _parseDouble(fareBreakdown['platformFeeFlat'] ?? 0) ?? 0.0;
    final platformFeePercent =
        _parseDouble(fareBreakdown['platformFeePercent'] ?? 0) ?? 0.0;
    final platformFeePercentAmount =
        _parseDouble(fareBreakdown['platformFeePercentAmount']) ??
        (tripFare * (platformFeePercent / 100));
    final planAppliedFromBackend = fareBreakdown['planApplied'] == true;
    final backendPlanName = fareBreakdown['planName']?.toString();
    final planBonusMultiplier =
        _parseDouble(fareBreakdown['planBonusMultiplier'] ?? 1.0) ?? 1.0;

    // heroAmount = what the driver actually pockets this ride
    // Falls back to driverEarning for older backend versions
    final heroAmount = totalEarnings > 0 ? totalEarnings : driverEarning;

    final hasPlan =
        planAppliedFromBackend ||
        (backendPlanName != null && backendPlanName.trim().isNotEmpty);
    final effectivePlanName =
        (backendPlanName != null && backendPlanName.trim().isNotEmpty)
        ? backendPlanName.trim()
        : (_activePlanName ?? 'Plan Active');
    final planLabel = effectivePlanName.length > 16
        ? '${effectivePlanName.substring(0, 16)}…'
        : effectivePlanName;
    final planCommissionPct = baseCommissionRateLabel;
    final hasBonusBoost = planBonusMultiplier > 1.0;
    final platformFeePercentLabel = platformFeePercent % 1 == 0
        ? platformFeePercent.toStringAsFixed(0)
        : platformFeePercent.toStringAsFixed(2);
    final hasDetailedPlatformFee =
        commissionPart > 0 || platformFeeFlat > 0 || platformFeePercent > 0;

    // ── helper: one breakdown row ─────────────────────────────────────────
    // ignore: prefer_function_declarations_over_variables
    final Widget Function(String, String, {Color? valueColor, bool bold})
    feeRow =
        (String label, String value, {Color? valueColor, bool bold = false}) {
          return Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: bold ? 14 : 13,
                    fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
                    color: bold ? Colors.black87 : Colors.grey[600],
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                value,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: bold ? 15 : 13,
                  fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
                  color:
                      valueColor ??
                      (bold ? const Color(0xFF1B5E20) : Colors.black87),
                ),
              ),
            ],
          );
        };

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(ctx).size.height * 0.90,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(32),
          topRight: Radius.circular(32),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Drag handle ───────────────────────────────────────────────
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(top: 12, bottom: 4),
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            // ── Scrollable body ───────────────────────────────────────────
            Flexible(
              child: SingleChildScrollView(
                physics: const ClampingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // ── Hero earning section ──────────────────────────────
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        vertical: 24,
                        horizontal: 20,
                      ),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [
                            Color(0xFF1B5E20),
                            Color(0xFF2E7D32),
                            Color(0xFF388E3C),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF2E7D32).withOpacity(0.30),
                            blurRadius: 24,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          Container(
                            width: 52,
                            height: 52,
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.20),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.check_rounded,
                              color: Colors.white,
                              size: 30,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Trip Completed!',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: Colors.white.withOpacity(0.85),
                              letterSpacing: 0.4,
                            ),
                          ),
                          const SizedBox(height: 6),
                          // ✅ FIXED: heroAmount includes incentive
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              '₹${heroAmount.toStringAsFixed(0)}',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 56,
                                fontWeight: FontWeight.w900,
                                color: Colors.white,
                                height: 1.0,
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'You earned this ride',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 12,
                              fontWeight: FontWeight.w400,
                              color: Colors.white.withOpacity(0.75),
                            ),
                          ),

                          // ── Plan badge (inside hero) ──────────────────
                          if (hasPlan) ...[
                            const SizedBox(height: 14),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.18),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: Colors.white.withOpacity(0.35),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.workspace_premium_rounded,
                                    color: Colors.white,
                                    size: 13,
                                  ),
                                  const SizedBox(width: 5),
                                  Flexible(
                                    child: Text(
                                      '$planLabel · $planCommissionPct% fee',
                                      style: GoogleFonts.plusJakartaSans(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.white,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                      maxLines: 1,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // ── Fare breakdown card ───────────────────────────────
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8F9FA),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: const Color(0xFFEEEEEE)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'FARE BREAKDOWN',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: Colors.grey[400],
                              letterSpacing: 1.2,
                            ),
                          ),
                          const SizedBox(height: 12),

                          // Trip fare
                          feeRow(
                            'Trip Fare',
                            '₹${tripFare.toStringAsFixed(2)}',
                          ),

                          const SizedBox(height: 8),

                          // Platform fee split into DB-driven component lines
                          if (hasDetailedPlatformFee) ...[
                            if (commissionPart > 0) ...[
                              feeRow(
                                hasPlan
                                    ? 'Plan Commission ($baseCommissionRateLabel%)'
                                    : 'Commission ($baseCommissionRateLabel%)',
                                '-₹${commissionPart.toStringAsFixed(2)}',
                                valueColor: Colors.orange[700],
                              ),
                              const SizedBox(height: 6),
                            ],
                            if (platformFeeFlat > 0) ...[
                              feeRow(
                                'Platform Fee Flat',
                                '-₹${platformFeeFlat.toStringAsFixed(2)}',
                                valueColor: Colors.orange[700],
                              ),
                              const SizedBox(height: 6),
                            ],
                            if (platformFeePercent > 0) ...[
                              feeRow(
                                'Platform Fee ($platformFeePercentLabel%)',
                                '-₹${platformFeePercentAmount.toStringAsFixed(2)}',
                                valueColor: Colors.orange[700],
                              ),
                              const SizedBox(height: 6),
                            ],
                            feeRow(
                              'Total Platform Fee',
                              commission == 0
                                  ? '₹0.00'
                                  : '-₹${commission.toStringAsFixed(2)}',
                              valueColor: commission == 0
                                  ? const Color(0xFF16A34A)
                                  : Colors.orange[700],
                            ),
                            if (hasPlan) ...[
                              const SizedBox(height: 4),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  planLabel,
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w500,
                                    color: AppColors.primary.withOpacity(0.8),
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 1,
                                ),
                              ),
                            ],
                          ] else
                            feeRow(
                              'Platform Fee ($commissionPctLabel%)',
                              commission == 0
                                  ? '₹0.00'
                                  : '-₹${commission.toStringAsFixed(2)}',
                              valueColor: commission == 0
                                  ? const Color(0xFF16A34A)
                                  : Colors.orange[700],
                            ),

                          // ✅ NEW: Per-ride incentive row
                          if (incentiveAwarded > 0) ...[
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    'Per-ride incentive',
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                      color: Colors.grey[600],
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  '+₹${incentiveAwarded.toStringAsFixed(2)}',
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: const Color(0xFF16A34A),
                                  ),
                                ),
                              ],
                            ),
                          ],

                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 10),
                            child: Divider(height: 1, color: Color(0xFFE0E0E0)),
                          ),

                          // ✅ FIXED: Your Earnings = heroAmount (base + incentive)
                          feeRow(
                            'Your Earnings',
                            '₹${heroAmount.toStringAsFixed(2)}',
                            bold: true,
                            valueColor: const Color(0xFF1B5E20),
                          ),
                        ],
                      ),
                    ),

                    // ── Plan bonus explainer strip ────────────────────────
                    if (hasPlan) ...[
                      const SizedBox(height: 10),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF0FFF4),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFBBF7D0)),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.trending_up_rounded,
                              color: Color(0xFF16A34A),
                              size: 16,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                hasBonusBoost
                                    ? '$planLabel gives you ${((planBonusMultiplier - 1) * 100).toStringAsFixed(0)}% bonus per ride!'
                                    : '$planLabel active — you save on every ride.',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                  color: const Color(0xFF15803D),
                                ),
                                overflow: TextOverflow.ellipsis,
                                maxLines: 2,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    // ✅ NEW: Incentive explainer (when no plan but incentive given)
                    if (incentiveAwarded > 0 && !hasPlan) ...[
                      const SizedBox(height: 10),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF0FFF4),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFBBF7D0)),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.star_rounded,
                              color: Color(0xFF16A34A),
                              size: 16,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '₹${incentiveAwarded.toStringAsFixed(0)} per-ride incentive added to your earnings!',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                  color: const Color(0xFF15803D),
                                ),
                                overflow: TextOverflow.ellipsis,
                                maxLines: 2,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),

            // ── CTA — pinned to bottom ─────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _clearActiveTrip();
                    _fetchWalletData();
                    _fetchTodayEarnings();
                    _fetchActivePlan();
                    _updateDriverStatusSocket();
                  },
                  icon: const Icon(
                    Icons.arrow_forward_rounded,
                    size: 20,
                    color: Colors.white,
                  ),
                  label: Text(
                    'Ready for Next Ride',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2E7D32),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWalletSummaryCard(Map<String, dynamic> walletInfo) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.primary.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.primary.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Wallet Summary', style: AppTextStyles.body1),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Total Earnings:', style: AppTextStyles.body2),
              Text(
                '₹${(walletInfo['totalEarnings'] as num).toStringAsFixed(2)}',
                style: AppTextStyles.body1,
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Pending Commission:', style: AppTextStyles.body2),
              Text(
                '₹${(walletInfo['pendingAmount'] as num).toStringAsFixed(2)}',
                style: AppTextStyles.body1.copyWith(color: AppColors.warning),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // ROUTE DRAWING & NAVIGATION
  // ===========================================================================

  Future<void> _drawRouteToCustomer() async {
    if (_currentPosition == null || _customerPickup == null) return;

    final url = Uri.parse(
      'https://maps.googleapis.com/maps/api/directions/json'
      '?origin=${_currentPosition!.latitude},${_currentPosition!.longitude}'
      '&destination=${_customerPickup!.latitude},${_customerPickup!.longitude}'
      '&key=${AppConfig.googleMapsApiKey}',
    );

    try {
      final response = await http.get(url);
      if (response.statusCode != 200) {
        _log('Failed to get directions: ${response.statusCode}');
        return;
      }

      final data = jsonDecode(response.body);
      if (data['status'] != 'OK' || (data['routes'] as List).isEmpty) {
        _log('No routes found: ${data['status']}');
        return;
      }

      final encodedPolyline = data['routes'][0]['overview_polyline']['points'];
      final polylinePoints = _decodePolyline(encodedPolyline);

      setState(() {
        _polylines
          ..clear()
          ..add(
            Polyline(
              polylineId: const PolylineId('routeToCustomer'),
              points: polylinePoints,
              color: AppColors.primary,
              width: 5,
            ),
          );
      });

      _mapController?.animateCamera(
        CameraUpdate.newLatLngBounds(
          _calculateBounds(_currentPosition!, _customerPickup!),
          80,
        ),
      );
    } catch (e) {
      _log('Error drawing route: $e', level: Level.WARNING);
    }
  }

  List<LatLng> _decodePolyline(String encoded) {
    List<LatLng> points = [];
    int index = 0, lat = 0, lng = 0;

    while (index < encoded.length) {
      int b, shift = 0, result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      lat += ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));

      shift = 0;
      result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      lng += ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));

      points.add(LatLng(lat / 1e5, lng / 1e5));
    }
    return points;
  }

  LatLngBounds _calculateBounds(LatLng p1, LatLng p2) {
    return LatLngBounds(
      southwest: LatLng(
        p1.latitude < p2.latitude ? p1.latitude : p2.latitude,
        p1.longitude < p2.longitude ? p1.longitude : p2.longitude,
      ),
      northeast: LatLng(
        p1.latitude > p2.latitude ? p1.latitude : p2.latitude,
        p1.longitude > p2.longitude ? p1.longitude : p2.longitude,
      ),
    );
  }

  void _launchGoogleMaps(double lat, double lng) async {
    final googleMapsAppUrl = Uri.parse('google.navigation:q=$lat,$lng&mode=d');
    final googleMapsWebUrl = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng&travelmode=driving',
    );

    try {
      if (await canLaunchUrl(googleMapsAppUrl)) {
        await launchUrl(googleMapsAppUrl, mode: LaunchMode.externalApplication);
      } else if (await canLaunchUrl(googleMapsWebUrl)) {
        await launchUrl(googleMapsWebUrl, mode: LaunchMode.externalApplication);
      } else {
        _log('Could not launch Google Maps');
      }
    } catch (e) {
      _log('Error launching Google Maps: $e', level: Level.WARNING);
    }
  }

  // ===========================================================================
  // UPI PAYMENT
  // ===========================================================================

  Future<void> _payCommissionViaUPI() async {
    final pendingAmount = _parseDouble(_walletData?['pendingAmount'] ?? 0);

    if (pendingAmount <= 0) {
      _showSnackBar('No pending commission to pay', color: AppColors.warning);
      return;
    }

    const upiId = '8341132728@mbk';
    const receiverName = 'Platform Commission';
    final amount = pendingAmount.toStringAsFixed(2);
    final transactionNote = 'Commission Payment - Driver: $_driverId';

    final upiUrl =
        'upi://pay?pa=$upiId&pn=${Uri.encodeComponent(receiverName)}&am=$amount&cu=INR&tn=${Uri.encodeComponent(transactionNote)}';

    try {
      final uri = Uri.parse(upiUrl);

      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) _showPaymentConfirmationDialog(pendingAmount);
        });
      } else {
        _showManualPaymentDialog(upiId, pendingAmount);
      }
    } catch (e) {
      _log('Error launching UPI: $e', level: Level.WARNING);
      _showManualPaymentDialog(upiId, pendingAmount);
    }
  }

  void _showPaymentConfirmationDialog(double amount) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(Icons.payment, color: AppColors.primary),
            const SizedBox(width: 12),
            Text('Payment Confirmation', style: AppTextStyles.heading3),
          ],
        ),
        content: Text(
          'Have you completed the payment of ₹${amount.toStringAsFixed(2)}?',
          style: AppTextStyles.body1,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Not Yet',
              style: AppTextStyles.button.copyWith(color: AppColors.error),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _showSnackBar(
                'Payment recorded. It will be verified shortly.',
                color: AppColors.success,
              );
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.success),
            child: Text(
              'Yes, Paid',
              style: AppTextStyles.button.copyWith(color: AppColors.onPrimary),
            ),
          ),
        ],
      ),
    );
  }

  void _showManualPaymentDialog(String upiId, double amount) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(Icons.qr_code, color: AppColors.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Text('Pay Manually', style: AppTextStyles.heading3),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Pay using any UPI app:', style: AppTextStyles.body1),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.divider),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('UPI ID:', style: AppTextStyles.body2),
                              const SizedBox(height: 4),
                              Text(
                                upiId,
                                style: AppTextStyles.body1.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: Icon(
                            Icons.copy,
                            size: 20,
                            color: AppColors.primary,
                          ),
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: upiId));
                            _showSnackBar(
                              'UPI ID copied!',
                              color: AppColors.success,
                            );
                          },
                        ),
                      ],
                    ),
                    const Divider(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Amount:', style: AppTextStyles.body2),
                        Text(
                          '₹${amount.toStringAsFixed(2)}',
                          style: AppTextStyles.heading3.copyWith(
                            color: AppColors.success,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _buildInfoCard(
                icon: Icons.info_outline,
                text: 'Open any UPI app and pay to this UPI ID',
                color: AppColors.primary,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Cancel',
              style: AppTextStyles.button.copyWith(
                color: AppColors.onSurfaceSecondary,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _showSnackBar(
                'After payment, verification takes 24 hours',
                color: AppColors.success,
              );
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
            child: Text(
              'Got It',
              style: AppTextStyles.button.copyWith(color: AppColors.onPrimary),
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // PHONE & CHAT
  // ===========================================================================

  Future<void> _makePhoneCall(String phoneNumber) async {
    if (phoneNumber.isEmpty) {
      _showSnackBar('Phone number not available');
      return;
    }
    final phoneUri = Uri(scheme: 'tel', path: phoneNumber);
    if (await canLaunchUrl(phoneUri)) {
      await launchUrl(phoneUri);
    }
  }

  void _openChat(Map<String, dynamic> customer) {
    if (_activeTripDetails == null) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatPage(
          tripId: _activeTripDetails!['tripId'],
          senderId: widget.driverId,
          receiverId: customer['id'],
          receiverName: customer['name'] ?? 'Customer',
          isDriver: true,
        ),
      ),
    );
  }

  // ===========================================================================
  // DIALOGS & STATUS CARDS
  // ===========================================================================

  void _showLoadingDialog(String message, {Color? color}) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Center(
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(
                  color ?? AppColors.primary,
                ),
              ),
              const SizedBox(height: 16),
              Text(message, style: AppTextStyles.body1),
            ],
          ),
        ),
      ),
    );
  }

  void _dismissLoadingDialog() {
    if (Navigator.canPop(context)) Navigator.pop(context);
  }

  void _showStatusCard({
    required IconData icon,
    required String title,
    required String message,
    required Color color,
    Duration duration = const Duration(seconds: 3),
  }) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: Colors.white, size: 24),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        message,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: Colors.white.withOpacity(0.9),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          backgroundColor: color,
          duration: duration,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.all(16),
        ),
      );
  }

  void _showProximityWarning(double distance, String locationType) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(Icons.location_off, color: AppColors.warning, size: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Text('Not at Location', style: AppTextStyles.heading3),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.warning.withOpacity(0.1),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.warning),
              ),
              child: Column(
                children: [
                  Text(
                    '${distance.toStringAsFixed(0)}m',
                    style: AppTextStyles.heading1.copyWith(
                      color: AppColors.warning,
                      fontSize: 48,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'away from $locationType',
                    style: AppTextStyles.body1.copyWith(
                      color: AppColors.warning,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Please move closer to the $locationType to proceed.',
              style: AppTextStyles.body2,
              textAlign: TextAlign.center,
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.onPrimary,
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text(
              'Got it',
              style: AppTextStyles.button.copyWith(color: AppColors.onPrimary),
            ),
          ),
        ],
      ),
    );
  }

  void _showTripResumeDialog(
    Map<String, dynamic> tripData,
    Map<String, dynamic>? customerData,
  ) {
    String phaseMessage;
    IconData phaseIcon;
    Color phaseColor;

    switch (_ridePhase) {
      case 'going_to_pickup':
        phaseMessage = 'You were on your way to pick up the customer';
        phaseIcon = Icons.navigation;
        phaseColor = AppColors.primary;
        break;
      case 'at_pickup':
        phaseMessage = 'You were at pickup location waiting to start the ride';
        phaseIcon = Icons.location_on;
        phaseColor = AppColors.warning;
        break;
      case 'going_to_drop':
        phaseMessage = 'You were heading to drop location';
        phaseIcon = Icons.flag;
        phaseColor = AppColors.success;
        break;
      case 'completed':
        phaseMessage = 'Trip completed - PLEASE COLLECT CASH NOW!';
        phaseIcon = Icons.payments;
        phaseColor = AppColors.error;
        break;
      default:
        phaseMessage = 'Resuming active trip';
        phaseIcon = Icons.local_taxi;
        phaseColor = AppColors.primary;
    }

    showDialog(
      context: context,
      barrierDismissible: _ridePhase != 'completed',
      builder: (context) => WillPopScope(
        onWillPop: () async => _ridePhase != 'completed',
        child: AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Row(
            children: [
              Icon(phaseIcon, color: phaseColor, size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _ridePhase == 'completed' ? 'Collect Cash!' : 'Trip Resumed',
                  style: AppTextStyles.heading3.copyWith(
                    color: _ridePhase == 'completed' ? AppColors.error : null,
                    fontWeight: _ridePhase == 'completed'
                        ? FontWeight.bold
                        : FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  phaseMessage,
                  style: AppTextStyles.body1.copyWith(
                    fontWeight: _ridePhase == 'completed'
                        ? FontWeight.bold
                        : FontWeight.normal,
                    color: _ridePhase == 'completed' ? AppColors.error : null,
                  ),
                ),
                if (_ridePhase == 'completed') ...[
                  const SizedBox(height: 16),
                  _buildWarningBanner(
                    'You cannot accept new trips until you confirm cash collection!',
                  ),
                ],
                const SizedBox(height: 16),
                Divider(color: AppColors.divider),
                const SizedBox(height: 12),
                if (customerData != null) _buildCustomerInfoRow(customerData),
                const SizedBox(height: 16),
                _buildTripDetailsCard(tripData),
                const SizedBox(height: 16),
                if (_ridePhase != 'completed')
                  _buildInfoCard(
                    icon: Icons.info_outline,
                    text: 'App will stay awake until trip is completed',
                    color: AppColors.warning,
                  ),
              ],
            ),
          ),
          actions: [
            if (_ridePhase == 'completed')
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    Future.delayed(
                      const Duration(milliseconds: 300),
                      _confirmCashCollection,
                    );
                  },
                  icon: const Icon(Icons.payments, size: 20),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.success,
                    foregroundColor: AppColors.onPrimary,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  label: Text(
                    'Collect ₹${_tripFareAmount?.toStringAsFixed(2)} Now',
                    style: AppTextStyles.button.copyWith(
                      color: AppColors.onPrimary,
                      fontSize: 16,
                    ),
                  ),
                ),
              )
            else
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: phaseColor,
                  foregroundColor: AppColors.onPrimary,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 12,
                  ),
                ),
                child: Text(
                  'Continue Trip',
                  style: AppTextStyles.button.copyWith(
                    color: AppColors.onPrimary,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildWarningBanner(String text) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.error.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.error, width: 2),
      ),
      child: Row(
        children: [
          Icon(Icons.warning, color: AppColors.error, size: 24),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: AppTextStyles.body2.copyWith(
                color: AppColors.error,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCustomerInfoRow(Map<String, dynamic> customerData) {
    return Row(
      children: [
        CircleAvatar(
          radius: 20,
          backgroundImage: customerData['photoUrl'] != null
              ? NetworkImage(customerData['photoUrl'])
              : const AssetImage('assets/default_avatar.png') as ImageProvider,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                customerData['name'] ?? 'Customer',
                style: AppTextStyles.body1.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(customerData['phone'] ?? '', style: AppTextStyles.caption),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTripDetailsCard(Map<String, dynamic> tripData) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          _buildDetailRow(
            Icons.location_on,
            'Pickup',
            tripData['pickup']?['address'] ?? 'Pickup Location',
          ),
          const SizedBox(height: 8),
          _buildDetailRow(
            Icons.flag,
            'Drop',
            tripData['drop']?['address'] ?? 'Drop Location',
          ),
          const SizedBox(height: 8),
          _buildDetailRow(
            Icons.payments,
            'Fare',
            '₹${_tripFareAmount?.toStringAsFixed(2) ?? '0.00'}',
            valueColor: _ridePhase == 'completed'
                ? AppColors.error
                : AppColors.primary,
          ),
          if (_customerOtp != null && _ridePhase != 'completed') ...[
            const SizedBox(height: 8),
            _buildDetailRow(
              Icons.lock,
              'Ride Code',
              _customerOtp!,
              valueColor: AppColors.primary,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDetailRow(
    IconData icon,
    String label,
    String value, {
    Color? valueColor,
  }) {
    return Row(
      children: [
        Icon(icon, size: 16, color: AppColors.onSurfaceSecondary),
        const SizedBox(width: 8),
        Text('$label:', style: AppTextStyles.caption),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            style: AppTextStyles.body2.copyWith(
              color: valueColor,
              fontWeight: valueColor != null
                  ? FontWeight.bold
                  : FontWeight.normal,
            ),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }

  // ===========================================================================
  // MAIN BUILD METHOD
  // ===========================================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      drawer: _buildDrawer(),
      appBar: _buildAppBar(),
      body: Stack(
        children: [
          Column(
            children: [
              _buildGoToInfoBanner(), // 👈 ADD THIS
              Expanded(
                child: _activeTripDetails != null
                    ? _buildActiveTripUI(_activeTripDetails!)
                    : (_isOnline ? _buildGoogleMap() : _buildOffDutyUI()),
              ),
            ],
          ),
          _buildRideQueueOverlay(),
        ],
      ),
    );
  }

  // ===========================================================================
  // APP BAR
  // ===========================================================================

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: AppColors.background,
      elevation: 1,
      iconTheme: IconThemeData(color: AppColors.onSurface),
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              _activeTripDetails != null
                  ? "En Route"
                  : (_isOnline ? "ON DUTY" : "OFF DUTY"),
              style: AppTextStyles.heading3.copyWith(
                color: _activeTripDetails != null
                    ? AppColors.primary
                    : (_isOnline ? AppColors.success : AppColors.error),
                fontSize: 16,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
          if (_activeTripDetails == null) ...[
            const SizedBox(width: 8),
            Switch(
              value: _isOnline,
              activeColor: AppColors.primary,
              inactiveThumbColor: AppColors.onSurfaceSecondary,
              onChanged: _handleOnlineToggle,
            ),
          ],
        ],
      ),
      actions: [
        // ❤️ GO TO ICON — ADD FIRST
        IconButton(
          icon: Icon(
            _isGoToActive ? Icons.favorite : Icons.favorite_border,
            color: _isGoToActive ? Colors.orange : AppColors.onSurface,
          ),
          onPressed: () async {
            // ❤️ TURN OFF
            if (_isGoToActive) {
              setState(() {
                _isGoToActive = false;
                _goToDestination = null;
              });
              return;
            }

            // ❤️ TURN ON → OPEN GO TO PAGE
            // 🛑 STRICT ACTION: Check commission limit first!
            _log('Checking wallet balance before activation of Go-To mode...');
            await _fetchWalletData();
            final pendingAmount = _parseDouble(
              _walletData?['pendingAmount'] ?? 0,
            );

            if (pendingAmount > 100) {
              _log(
                'Go-To mode BLOCKED: Pending commission ₹$pendingAmount exceeds ₹100 limit',
              );
              _showCommissionLimitDialog(pendingAmount);
              return;
            }

            final result = await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const DriverGoToDestinationPage(),
              ),
            );

            if (result != null && result is Map<String, dynamic>) {
              setState(() {
                _isGoToActive = true;
                _goToDestination = result;
              });
            }
          },
        ),

        // 🔔 NOTIFICATION ICON — KEEP EXISTING LOGIC
        Stack(
          children: [
            IconButton(
              icon: const Icon(Icons.notifications_none),
              onPressed: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => DriverNotificationPage()),
                );

                // refresh after coming back
                _fetchUnreadNotificationCount();
              },
            ),

            // 🔴 Red dot
            if (_unreadNotificationCount > 0)
              Positioned(
                right: 10,
                top: 10,
                child: Container(
                  width: 10,
                  height: 10,
                  decoration: const BoxDecoration(
                    color: Colors.red,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildGoToInfoBanner() {
    if (!_isGoToActive || _goToDestination == null) {
      return const SizedBox.shrink();
    }

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orange.withOpacity(0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange),
      ),
      child: Row(
        children: [
          const Icon(Icons.favorite, color: Colors.orange),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Go To active: ${_goToDestination!['address'] ?? 'Selected destination'}',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handleOnlineToggle(bool value) async {
    // Trying to go OFFLINE
    if (!value) {
      if (_socketService.hasActiveTrip) {
        _showSnackBar(
          'Cannot go offline while a trip is active. Complete the trip first.',
          color: AppColors.warning,
        );
        setState(() => _isOnline = true);
        return;
      }

      setState(() => _isOnline = false);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('isOnline', false);

      await TripBackgroundService.stopOnlineService();
      _log('Driver OFFLINE - Background service stopped');

      await Future.delayed(const Duration(milliseconds: 100));
      _updateDriverStatusSocket();
      return;
    }

    // ✅ Trying to go ONLINE - 1. Fetch latest wallet data first (STRICT)
    _log('Checking wallet balance before going online...');
    await _fetchWalletData();
    final pendingAmount = _parseDouble(_walletData?['pendingAmount'] ?? 0);

    if (pendingAmount > 100) {
      _log(
        'Go Online BLOCKED: Pending commission ₹$pendingAmount exceeds ₹100 limit',
      );
      _showCommissionLimitDialog(pendingAmount);
      setState(() => _isOnline = false);
      return;
    }

    // ✅ 2. Check overlay permission first!
    final hasOverlayPermission = await _ensureOverlayPermissionForOnline();

    if (!hasOverlayPermission) {
      // User declined permission - don't go online
      _showSnackBar(
        'Overlay permission is required to receive trip requests',
        color: AppColors.warning,
      );
      setState(() => _isOnline = false);
      return;
    }

    // ✅ Permission granted - proceed to go online
    setState(() => _isOnline = true);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isOnline', true);

    // Start background service
    await TripBackgroundService.startOnlineService(
      driverId: _driverId,
      vehicleType: widget.vehicleType,
      isOnline: true,
    );

    _log('Driver ONLINE - Background service started');
    _updateDriverStatusSocket();
  }

  /// 🚫 STRICT ACTION: User blocked from going online if pending >= 100
  void _showCommissionLimitDialog(double amount) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: AppColors.error, size: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'High Commission Due',
                style: AppTextStyles.heading3.copyWith(color: AppColors.error),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Your pending commission is ₹${amount.toStringAsFixed(2)}.',
              style: AppTextStyles.body1.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Text(
              'To continue receiving ride requests, please pay the due amount. The limit for pending commission is ₹100.00.',
              style: AppTextStyles.body2,
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.error.withOpacity(0.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.error.withOpacity(0.2)),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, size: 20, color: AppColors.error),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Payment will be verified instantly via UPI.',
                      style: AppTextStyles.caption.copyWith(
                        color: AppColors.error,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => WalletPage(driverId: _driverId),
                ),
              );
            },
            child: Text(
              'View History',
              style: AppTextStyles.button.copyWith(
                color: AppColors.onSurfaceSecondary,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _payCommissionViaUPI();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.onPrimary,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text(
              'Pay Now via UPI',
              style: AppTextStyles.button.copyWith(color: AppColors.onPrimary),
            ),
          ),
        ],
      ),
    );
  }
  // ===========================================================================
  // GOOGLE MAP
  // ===========================================================================

  Widget _buildGoogleMap() {
    final center = _currentPosition ?? const LatLng(17.385044, 78.486671);

    return GoogleMap(
      initialCameraPosition: CameraPosition(target: center, zoom: 14),
      myLocationEnabled: true,
      myLocationButtonEnabled: true,
      zoomControlsEnabled: false,
      markers: _markers,
      polylines: _polylines,
      onMapCreated: (controller) => _mapController = controller,
    );
  }

  // ===========================================================================
  // ACTIVE TRIP UI
  // ===========================================================================

  Widget _buildActiveTripUI(Map<String, dynamic> tripData) {
    return Stack(
      children: [
        // Full-screen map
        Positioned.fill(
          child: GoogleMap(
            initialCameraPosition: CameraPosition(
              target: _currentPosition ?? const LatLng(17.385044, 78.486671),
              zoom: 14,
            ),
            myLocationEnabled: true,
            myLocationButtonEnabled: true,
            zoomControlsEnabled: false,
            markers: _markers,
            polylines: _polylines,
            onMapCreated: (controller) => _mapController = controller,
          ),
        ),
        // Bottom card anchored to bottom
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: _buildCustomerCard(
            tripData['customer'] ?? {},
            tripData['trip'] ?? {},
          ),
        ),
      ],
    );
  }

  Widget _buildCustomerCard(
    Map<String, dynamic> customer,
    Map<String, dynamic> trip,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.onSurface.withOpacity(0.12),
            blurRadius: 24,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.55,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Drag handle
                Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(
                    color: AppColors.divider,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                // Phase badge + customer header in one row
                _buildCustomerHeader(customer),
                const SizedBox(height: 10),
                // Divider
                Container(height: 1, color: AppColors.divider),
                const SizedBox(height: 12),
                _buildTripInfoCard(trip),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCustomerHeader(Map<String, dynamic> customer) {
    // Phase pill data — Dart 2 compatible (no destructuring/expression switch)
    String phaseLabel;
    Color phaseColor;
    IconData phaseIcon;

    switch (_ridePhase) {
      case 'going_to_pickup':
        phaseLabel = 'Going to Pickup';
        phaseColor = AppColors.primary;
        phaseIcon = Icons.navigation_rounded;
        break;
      case 'at_pickup':
        phaseLabel = 'At Pickup · Enter OTP';
        phaseColor = AppColors.warning;
        phaseIcon = Icons.lock_outline;
        break;
      case 'going_to_drop':
        phaseLabel = 'On Trip';
        phaseColor = AppColors.success;
        phaseIcon = Icons.local_taxi_rounded;
        break;
      case 'completed':
        phaseLabel = 'Collect Cash';
        phaseColor = AppColors.error;
        phaseIcon = Icons.payments_rounded;
        break;
      default:
        phaseLabel = 'Active Trip';
        phaseColor = AppColors.primary;
        phaseIcon = Icons.local_taxi;
    }

    return Row(
      children: [
        // Avatar — smaller, cleaner
        CircleAvatar(
          radius: 26,
          backgroundColor: AppColors.surface,
          backgroundImage:
              customer['photoUrl'] != null &&
                  customer['photoUrl'].toString().isNotEmpty
              ? NetworkImage(customer['photoUrl'])
              : const AssetImage('assets/default_avatar.png') as ImageProvider,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                customer['name'] ?? 'Customer',
                style: AppTextStyles.body1.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              // Phase pill
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: phaseColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(phaseIcon, size: 11, color: phaseColor),
                    const SizedBox(width: 4),
                    Text(
                      phaseLabel,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: phaseColor,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        // Action buttons — smaller, cleaner
        _buildSmallIconButton(
          Icons.call_rounded,
          AppColors.success,
          () => _makePhoneCall(customer['phone']?.toString() ?? ''),
        ),
        const SizedBox(width: 8),
        _buildSmallIconButton(
          Icons.chat_bubble_outline_rounded,
          AppColors.primary,
          () => _openChat(customer),
        ),
      ],
    );
  }

  Widget _buildSmallIconButton(
    IconData icon,
    Color color,
    VoidCallback onPressed,
  ) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: color.withOpacity(0.10),
          shape: BoxShape.circle,
          border: Border.all(color: color.withOpacity(0.25)),
        ),
        child: Icon(icon, color: color, size: 18),
      ),
    );
  }

  /// Extracts the main locality/area from a Google Maps address.
  /// Google Maps addresses typically follow:
  ///   [House/Plot], [Landmark/Near], [Locality], [Sub-area], [City], [State]
  /// We want the first well-known locality (usually part index 2 or first part
  /// that looks like a place name — not a number, not "near/beside").
  String _extractMainAreaFromAddress(String? fullAddress) {
    if (fullAddress == null || fullAddress.isEmpty) return 'Location';
    final parts = fullAddress
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (parts.isEmpty) return 'Location';
    if (parts.length == 1) {
      final t = parts[0];
      return t.length > 35 ? '${t.substring(0, 35)}...' : t;
    }

    // Things to skip — not useful to a driver
    final skipPrefixes = [
      'near ',
      'beside ',
      'opp ',
      'opposite ',
      'behind ',
      'next to ',
    ];
    final genericPlaces = {
      'india',
      'telangana',
      'andhra pradesh',
      'karnataka',
      'maharashtra',
      'tamil nadu',
      'kerala',
      'hyderabad',
      'bangalore',
      'bengaluru',
      'mumbai',
      'chennai',
      'delhi',
      'pune',
      'kolkata',
      'secunderabad',
      'vijayawada',
      'visakhapatnam',
      'warangal',
    };

    int mainIdx = -1;
    for (int i = 0; i < parts.length; i++) {
      final p = parts[i].toLowerCase().trim();
      final isHouseNum = RegExp(r'^[#\d]').hasMatch(parts[i]);
      final isLandmarkPrefix = skipPrefixes.any(
        (prefix) => p.startsWith(prefix),
      );
      final isCityOrState = genericPlaces.contains(p);
      final isPin = RegExp(r'^\d{5,6}$').hasMatch(parts[i]);
      if (!isHouseNum &&
          !isLandmarkPrefix &&
          !isCityOrState &&
          !isPin &&
          parts[i].length >= 3) {
        mainIdx = i;
        break;
      }
    }

    if (mainIdx == -1) mainIdx = 0;

    final main = parts[mainIdx];
    if (mainIdx + 1 < parts.length) {
      final next = parts[mainIdx + 1];
      final isPin = RegExp(r'^\d{5,6}$').hasMatch(next);
      final isGeneric = genericPlaces.contains(next.toLowerCase());
      if (!isPin && !isGeneric) {
        return '$main, $next';
      }
    }
    return main;
  }

  /// Returns remaining address parts as a compact sub-line.
  String _extractSubAddress(String? fullAddress) {
    if (fullAddress == null || fullAddress.isEmpty) return '';
    final parts = fullAddress
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (parts.length <= 2) return '';

    // Sub address: everything not already shown in main area
    // We showed mainIdx and mainIdx+1 → show mainIdx+2 onwards (max 2 more parts)
    final skipPrefixes = [
      'near ',
      'beside ',
      'opp ',
      'opposite ',
      'behind ',
      'next to ',
    ];
    int mainIdx = 0;
    for (int i = 0; i < parts.length && i < 4; i++) {
      final p = parts[i].toLowerCase();
      final isHouseNum = RegExp(r'^[#\d]').hasMatch(parts[i]);
      final isLandmark = skipPrefixes.any((prefix) => p.startsWith(prefix));
      if (!isHouseNum && !isLandmark && parts[i].length >= 3) {
        mainIdx = i;
        break;
      }
      mainIdx = i;
    }

    final subStart = mainIdx + 2;
    if (subStart >= parts.length) return '';
    return parts
        .sublist(subStart, (subStart + 3).clamp(0, parts.length))
        .where((e) => !RegExp(r'^\d{5,6}$').hasMatch(e))
        .join(', ');
  }

  Widget _buildRapidoAddressRow({
    required IconData icon,
    required Color iconColor,
    required Color iconBgColor,
    required String label,
    required String? fullAddress,
  }) {
    final mainArea = _extractMainAreaFromAddress(fullAddress);
    final subAddress = _extractSubAddress(fullAddress);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: iconBgColor, shape: BoxShape.circle),
          child: Icon(icon, color: iconColor, size: 16),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: AppColors.onSurfaceTertiary,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                mainArea,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.onSurface,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (subAddress.isNotEmpty)
                Text(
                  subAddress,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                    color: AppColors.onSurfaceSecondary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTripInfoCard(Map<String, dynamic> trip) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          // Pickup address - Rapido style
          _buildRapidoAddressRow(
            icon: Icons.my_location_rounded,
            iconColor: AppColors.primary,
            iconBgColor: AppColors.primary.withOpacity(0.12),
            label: 'PICKUP',
            fullAddress:
                (trip['pickup'] as Map<String, dynamic>?)?['address']
                    as String?,
          ),
          Padding(
            padding: const EdgeInsets.only(left: 16, top: 4, bottom: 4),
            child: Row(
              children: [
                Container(
                  width: 2,
                  height: 20,
                  margin: const EdgeInsets.only(left: 7),
                  decoration: BoxDecoration(
                    color: AppColors.divider,
                    borderRadius: BorderRadius.circular(1),
                  ),
                ),
              ],
            ),
          ),
          // Drop address - Rapido style
          _buildRapidoAddressRow(
            icon: Icons.flag_rounded,
            iconColor: AppColors.error,
            iconBgColor: AppColors.error.withOpacity(0.12),
            label: 'DROP',
            fullAddress:
                (trip['drop'] as Map<String, dynamic>?)?['address'] as String?,
          ),
          const SizedBox(height: 16),
          _buildActionButtons(trip),
        ],
      ),
    );
  }

  // ===========================================================================
  // ACTION BUTTONS BY PHASE
  // ===========================================================================

  Widget _buildActionButtons(Map<String, dynamic> trip) {
    switch (_ridePhase) {
      case 'going_to_pickup':
        return _buildGoingToPickupActions(trip);
      case 'at_pickup':
        return _buildAtPickupActions();
      case 'going_to_drop':
        return _buildGoingToDropActions(trip);
      case 'completed':
        return _buildCompletedActions();
      default:
        return _buildLoadingState();
    }
  }

  Widget _buildGoingToPickupActions(Map<String, dynamic> trip) {
    return Column(
      children: [
        _buildPrimaryActionButton(
          icon: Icons.navigation_rounded,
          label: 'Start Navigation',
          onPressed: () =>
              _launchGoogleMaps(trip['pickup']['lat'], trip['pickup']['lng']),
        ),
        const SizedBox(height: 12),
        // 🔥 Disable button when action in progress
        _actionInProgress
            ? _buildLoadingButton("Updating...")
            : _buildSecondaryActionButton(
                icon: Icons.check_circle_outline,
                label: "I've Arrived",
                onPressed: () => _handleArrivedAtPickup(trip),
              ),
        const SizedBox(height: 16),
        _buildInfoCard(
          icon: Icons.info_outline,
          text: 'Tap "I\'ve Arrived" when you reach the pickup location',
          color: AppColors.primary,
        ),
      ],
    );
  }

  void _handleArrivedAtPickup(Map<String, dynamic> trip) {
    if (_currentPosition == null) {
      _showStatusCard(
        icon: Icons.gps_not_fixed,
        title: 'Getting Location',
        message: 'Please wait while we fetch your current location...',
        color: AppColors.warning,
      );
      return;
    }

    final pickupLocation = LatLng(trip['pickup']['lat'], trip['pickup']['lng']);
    final distance = _calculateDistance(_currentPosition!, pickupLocation);

    if (distance <= _proximityThreshold) {
      _goToPickup();
    } else {
      _showProximityWarning(distance, 'pickup location');
    }
  }

  Widget _buildAtPickupActions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Compact OTP prompt row
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.primary.withOpacity(0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.primary.withOpacity(0.2)),
          ),
          child: Row(
            children: [
              Icon(Icons.lock_outline, color: AppColors.primary, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Enter Ride Code',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary,
                      ),
                    ),
                    Text(
                      'Ask customer for their 4-digit code',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 11,
                        fontWeight: FontWeight.w400,
                        color: AppColors.onSurfaceSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _buildOtpInput(),
        const SizedBox(height: 20),
        // 🔥 Disable button when action in progress
        _actionInProgress
            ? _buildLoadingButton("Starting Ride...")
            : _buildPrimaryActionButton(
                icon: Icons.play_arrow_rounded,
                label: 'Start Ride',
                onPressed: _startRide,
                gradient: LinearGradient(
                  colors: [
                    AppColors.primary,
                    AppColors.primary.withOpacity(0.82),
                  ],
                ),
              ),
      ],
    );
  }

  Widget _buildOtpHeader() {
    return Container(
      padding: const EdgeInsets.all(16),
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
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.2),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.lock_outline, color: AppColors.primary, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Verify Customer",
                  style: AppTextStyles.heading3.copyWith(fontSize: 18),
                ),
                const SizedBox(height: 4),
                Text(
                  "Ask for the 4-digit ride code",
                  style: AppTextStyles.body2,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOtpInput() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: List.generate(4, (i) {
        return SizedBox(
          width: 58,
          height: 62,
          child: TextFormField(
            controller: _otpBoxControllers[i],
            focusNode: _otpBoxFocusNodes[i],
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            maxLength: 1,
            autofocus: i == 0,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: AppColors.onSurface,
            ),
            decoration: InputDecoration(
              counterText: '',
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: Color(0xFFD0D5DD), width: 1.5),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: AppColors.primary, width: 2),
              ),
              contentPadding: const EdgeInsets.symmetric(vertical: 14),
            ),
            onChanged: (val) {
              if (val.length == 1 && i < 3) {
                _otpBoxFocusNodes[i + 1].requestFocus();
              } else if (val.isEmpty && i > 0) {
                _otpBoxFocusNodes[i - 1].requestFocus();
              }
              // Sync to legacy controller for _startRide compatibility
              _otpController.text = _otpBoxControllers
                  .map((c) => c.text)
                  .join();
              // Auto-submit when all 4 filled
              if (_otpBoxControllers.every((c) => c.text.isNotEmpty)) {
                FocusScope.of(context).unfocus();
              }
            },
          ),
        );
      }),
    );
  }

  Widget _buildGoingToDropActions(Map<String, dynamic> trip) {
    return Column(
      children: [
        _buildPrimaryActionButton(
          icon: Icons.navigation_rounded,
          label: 'Navigate to Drop Location',
          onPressed: () =>
              _launchGoogleMaps(trip['drop']['lat'], trip['drop']['lng']),
        ),
        const SizedBox(height: 12),
        // 🔥 Disable button when action in progress
        _actionInProgress
            ? _buildLoadingButton("Completing...")
            : _buildSecondaryActionButton(
                icon: Icons.flag_outlined,
                label: 'Complete Ride',
                onPressed: () => _handleCompleteRide(trip),
              ),
        const SizedBox(height: 16),
        _buildInfoCard(
          icon: Icons.directions_car,
          text: 'Take customer to destination safely',
          color: AppColors.primary,
        ),
      ],
    );
  }

  void _handleCompleteRide(Map<String, dynamic> trip) {
    if (_currentPosition == null) {
      _showStatusCard(
        icon: Icons.gps_not_fixed,
        title: 'Getting Location',
        message: 'Please wait while we fetch your current location...',
        color: AppColors.warning,
      );
      return;
    }

    final dropLocation = LatLng(trip['drop']['lat'], trip['drop']['lng']);
    final distance = _calculateDistance(_currentPosition!, dropLocation);

    if (distance <= _proximityThreshold) {
      _completeRide();
    } else {
      _showProximityWarning(distance, 'drop location');
    }
  }

  Widget _buildCompletedActions() {
    return Column(
      children: [
        _buildSuccessHeader(),
        const SizedBox(height: 20),
        _buildFareDisplay(),
        const SizedBox(height: 20),
        // 🔥 Disable button when action in progress
        _actionInProgress
            ? _buildLoadingButton("Processing...")
            : _buildPrimaryActionButton(
                icon: Icons.payments_rounded,
                label: 'Cash Collected - Complete',
                onPressed: _confirmCashCollection,
                gradient: LinearGradient(
                  colors: [
                    AppColors.primary,
                    AppColors.primary.withOpacity(0.82),
                  ],
                ),
              ),
        const SizedBox(height: 12),
        _buildInfoCard(
          icon: Icons.warning_amber_rounded,
          text: 'Confirm only after receiving payment from customer',
          color: AppColors.warning,
        ),
      ],
    );
  }

  Widget _buildSuccessHeader() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.primary.withOpacity(0.12), Colors.white],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: AppColors.primary.withOpacity(0.35),
          width: 1.5,
        ),
      ),
      child: Column(
        children: [
          Icon(Icons.check_circle, color: AppColors.primary, size: 64),
          const SizedBox(height: 12),
          Text(
            "Trip Completed Successfully!",
            style: AppTextStyles.heading3.copyWith(
              color: AppColors.onSurface,
              fontSize: 20,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text("Collect cash from customer", style: AppTextStyles.body2),
        ],
      ),
    );
  }

  Widget _buildFareDisplay() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("Total Fare", style: AppTextStyles.body2),
              const SizedBox(height: 4),
              Text("To Collect", style: AppTextStyles.caption),
            ],
          ),
          Text(
            "₹${_finalFareAmount?.toStringAsFixed(2) ?? '0.00'}",
            style: AppTextStyles.heading1.copyWith(
              color: AppColors.primary,
              fontSize: 36,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingState() {
    return Container(
      height: 100,
      alignment: Alignment.center,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
          ),
          const SizedBox(height: 12),
          Text('Loading trip details...', style: AppTextStyles.body2),
        ],
      ),
    );
  }

  // ===========================================================================
  // REUSABLE BUTTON WIDGETS
  // ===========================================================================

  Widget _buildPrimaryActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
    Gradient? gradient,
  }) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient:
            gradient ??
            LinearGradient(
              colors: [AppColors.primary, AppColors.primary.withOpacity(0.8)],
            ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withOpacity(0.3),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ElevatedButton.icon(
        icon: Icon(icon, size: 24),
        label: Text(
          label,
          style: AppTextStyles.button.copyWith(
            color: AppColors.onPrimary,
            fontSize: 16,
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          foregroundColor: AppColors.onPrimary,
          padding: const EdgeInsets.symmetric(vertical: 18),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        onPressed: onPressed,
      ),
    );
  }

  Widget _buildSecondaryActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
  }) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primary, width: 2),
      ),
      child: ElevatedButton.icon(
        icon: Icon(icon, size: 22),
        label: Text(
          label,
          style: AppTextStyles.button.copyWith(
            color: AppColors.primary,
            fontSize: 15,
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          foregroundColor: AppColors.primary,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        onPressed: onPressed,
      ),
    );
  }

  /// 🔥 NEW: Loading button for action in progress
  Widget _buildLoadingButton(String label) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider, width: 2),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              label,
              style: AppTextStyles.button.copyWith(
                color: AppColors.onSurfaceSecondary,
                fontSize: 15,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoCard({
    required IconData icon,
    required String text,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: AppTextStyles.body2.copyWith(
                color: color,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFareRow(
    String label,
    dynamic amount, {
    bool bold = false,
    bool isNegative = false,
    Color? color,
  }) {
    final displayAmount = amount is num
        ? amount.toDouble()
        : double.tryParse(amount.toString()) ?? 0.0;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              label,
              style: bold ? AppTextStyles.body1 : AppTextStyles.body2,
            ),
          ),
          Text(
            '${isNegative ? '-' : ''}₹${displayAmount.toStringAsFixed(2)}',
            style: (bold ? AppTextStyles.heading3 : AppTextStyles.body1)
                .copyWith(color: color ?? AppColors.onSurface),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // RIDE QUEUE OVERLAY
  // ===========================================================================

  Widget _buildRideQueueOverlay() {
    // 🔥 Don't show queue overlay during overlay accept processing
    if (_isProcessingOverlayAccept) {
      return const SizedBox.shrink();
    }

    if (_rideRequests.isEmpty) return const SizedBox.shrink();

    return Positioned.fill(
      child: Container(
        color: AppColors.background,
        child: Column(
          children: [
            _buildQueueHeader(),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                itemCount: _rideRequests.length,
                itemBuilder: (context, index) {
                  final request = _rideRequests[index];
                  final bool isDestinationTrip =
                      request['isDestinationMatch'] == true;

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: RideRequestCard(
                      request: request,
                      position: index,
                      driverLocation: _currentPosition,
                      perRideIncentive: _perRideIncentive,
                      perRideCoins: _perRideCoins,
                      isDestinationMatch: isDestinationTrip,
                      onAccept: () {
                        setState(() => _currentRide = request);
                        _acceptRide();
                      },
                      onReject: _rejectRide,
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQueueHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: AppColors.primary,
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withOpacity(0.3),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: SafeArea(
        bottom: false,
        child: Row(
          children: [
            Icon(
              Icons.notifications_active,
              color: AppColors.onPrimary,
              size: 28,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Incoming Ride Requests",
                    style: AppTextStyles.heading3.copyWith(
                      color: AppColors.onPrimary,
                    ),
                  ),
                  Text(
                    "${_rideRequests.length} ${_rideRequests.length == 1 ? 'request' : 'requests'} waiting",
                    style: AppTextStyles.caption.copyWith(
                      color: AppColors.onPrimary.withOpacity(0.9),
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.onPrimary,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '${_rideRequests.length}',
                style: AppTextStyles.heading3.copyWith(
                  color: AppColors.primary,
                  fontSize: 18,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // OFF DUTY UI
  // ===========================================================================

  Widget _buildOffDutyUI() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildEarningsCard(),
        const SizedBox(height: 16),
        _buildWalletCard(),

        // 🔥 NEW: Add promotions section here
        _buildPromotionsSection(),

        const SizedBox(height: 16),
        _buildRideHistoryTile(),
        SizedBox(height: 16),
        // 🔽 New pencil bike animation (replaces the old mobile.png image)
        SizedBox(
          height: 160,
          child: Lottie.asset(
            'assets/animations/bike_pencil.json',
            repeat: true,
          ),
        ),

        const SizedBox(height: 0),
        Center(
          child: Text(
            "Start the engine, chase the earnings!",
            style: AppTextStyles.body1,
          ),
        ),
        const SizedBox(height: 10),
        Center(
          child: Text(
            "Go ON DUTY to start earning",
            style: AppTextStyles.heading3,
          ),
        ),
      ],
    );
  }

  Widget _buildEarningsCard() {
    final todayTotal = _parseDouble(_todayEarnings?['totalFares'] ?? 0);
    final todayNet = _parseDouble(_todayEarnings?['netEarnings'] ?? 0);
    final tripsCount =
        (_todayEarnings?['tripsCompleted'] as num?)?.toInt() ?? 0;

    return GestureDetector(
      onTap: _fetchTodayEarnings,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.divider),
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.calendar_today,
                      color: AppColors.primary,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text("Today's Earnings", style: AppTextStyles.heading3),
                  ],
                ),
                if (_isLoadingToday)
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        AppColors.primary,
                      ),
                    ),
                  )
                else
                  Icon(
                    Icons.refresh,
                    color: AppColors.onSurfaceSecondary,
                    size: 20,
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Total Fares', style: AppTextStyles.body2),
                    const SizedBox(height: 4),
                    Text(
                      '₹${todayTotal.toStringAsFixed(2)}',
                      style: AppTextStyles.heading1.copyWith(
                        fontSize: 32,
                        color: AppColors.success,
                      ),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: AppColors.primary.withOpacity(0.3),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.local_taxi,
                        color: AppColors.primary,
                        size: 16,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '$tripsCount ${tripsCount == 1 ? 'trip' : 'trips'}',
                        style: AppTextStyles.caption.copyWith(
                          color: AppColors.primary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(height: 1, color: AppColors.divider),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildEarningsBreakdownItem(
                    'Net Earning',
                    todayNet,
                    Icons.account_balance_wallet,
                    AppColors.success,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEarningsBreakdownItem(
    String label,
    double amount,
    IconData icon,
    Color color, {
    bool isNegative = false,
  }) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 16),
            const SizedBox(width: 4),
            Text(label, style: AppTextStyles.caption),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          '${isNegative ? '-' : ''}₹${amount.toStringAsFixed(2)}',
          style: AppTextStyles.body1.copyWith(
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildWalletCard() {
    final totalEarnings = _parseDouble(_walletData?['totalEarnings'] ?? 0);
    final pendingAmount = _parseDouble(_walletData?['pendingAmount'] ?? 0);
    return GestureDetector(
      onTap: _fetchWalletData,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [AppColors.primary, AppColors.primary.withOpacity(0.7)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withOpacity(0.3),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        padding: const EdgeInsets.all(18), // 🔥 Reduced from 20
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Wallet Balance',
                      style: AppTextStyles.body2.copyWith(
                        color: AppColors.onPrimary.withOpacity(0.9),
                        fontSize: 13, // 🔥 Reduced font
                      ),
                    ),
                    const SizedBox(height: 6), // 🔥 Reduced from 8
                    Text(
                      '₹${totalEarnings.toStringAsFixed(2)}',
                      style: AppTextStyles.heading2.copyWith(
                        color: AppColors.onPrimary,
                        fontWeight: FontWeight.bold,
                        fontSize: 22, // 🔥 Reduced from 24
                      ),
                    ),
                  ],
                ),
                if (_isLoadingWallet)
                  SizedBox(
                    width: 24, // 🔥 Reduced from 28
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        AppColors.onPrimary,
                      ),
                    ),
                  )
                else
                  Container(
                    padding: const EdgeInsets.all(10), // 🔥 Reduced from 12
                    decoration: BoxDecoration(
                      color: AppColors.onPrimary.withOpacity(0.2),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.account_balance_wallet,
                      color: AppColors.onPrimary,
                      size: 24, // 🔥 Reduced from 28
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12), // 🔥 Reduced from 16
            Container(height: 1, color: AppColors.onPrimary.withOpacity(0.2)),
            const SizedBox(height: 12), // 🔥 Reduced from 16
            _buildWalletSummarySection(),
          ],
        ),
      ),
    );
  }

  Widget _buildWalletSummarySection() {
    return Row(
      children: [
        Icon(Icons.info_outline, color: AppColors.onPrimary.withOpacity(0.9)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'Wallet details are available in Earnings.',
            style: AppTextStyles.body2.copyWith(
              color: AppColors.onPrimary.withOpacity(0.9),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPromotionsSection() {
    debugPrint('🎯 Building promotions section');
    debugPrint('   Loading: $_isLoadingPromotions');
    debugPrint('   Promotions count: ${_promotions.length}');

    // Show loading state
    if (_isLoadingPromotions) {
      return Container(
        margin: const EdgeInsets.only(top: 16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.divider),
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Special Offers", style: AppTextStyles.heading3),
            const SizedBox(height: 16),
            const SizedBox(
              height: 120,
              child: Center(
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
                ),
              ),
            ),
          ],
        ),
      );
    }

    // If API promotions are available, show them
    if (_promotions.isNotEmpty) {
      debugPrint('✅ Displaying ${_promotions.length} promotions from API');

      return Container(
        margin: const EdgeInsets.only(top: 16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.divider),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text("Special Offers", style: AppTextStyles.heading3),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.success,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${_promotions.length} active',
                    style: AppTextStyles.caption.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            SizedBox(
              height: 130,
              child: PageView.builder(
                controller: _promoPageController,
                onPageChanged: (index) {
                  setState(() {
                    _currentPromoIndex = index;
                  });
                },
                itemCount: _promotions.length,
                itemBuilder: (context, index) {
                  final promo = _promotions[index];
                  return _PromotionImageCard(
                    imageUrl: promo['imageUrl'] ?? '',
                    title: promo['title'] ?? 'Untitled',
                    promotionId: promo['_id'] ?? '',
                    onTap: () => _trackPromotionClick(promo['_id'] ?? ''),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),

            // Page indicators
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(_promotions.length, (index) {
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  height: 5,
                  width: _currentPromoIndex == index ? 16 : 5,
                  decoration: BoxDecoration(
                    color: _currentPromoIndex == index
                        ? AppColors.primary
                        : AppColors.divider,
                    borderRadius: BorderRadius.circular(3),
                  ),
                );
              }),
            ),
          ],
        ),
      );
    }

    // Fallback to static promo cards
    debugPrint('ℹ️ No API promotions, showing fallback cards');
    return Container(
      margin: const EdgeInsets.only(top: 16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("Special Offers", style: AppTextStyles.heading3),
          const SizedBox(height: 12),

          SizedBox(
            height: 110,
            child: PageView.builder(
              controller: _promoPageController,
              onPageChanged: (index) {
                setState(() {
                  _currentPromoIndex = index;
                });
              },
              itemCount: _promoCards.length,
              itemBuilder: (context, index) {
                final promo = _promoCards[index];
                return _BigPromoCard(
                  title: promo['title'] as String,
                  subtitle: promo['subtitle'] as String,
                  icon: promo['icon'] as IconData,
                  gradientColors: promo['gradient'] as List<Color>,
                );
              },
            ),
          ),
          const SizedBox(height: 8),

          // Page indicators
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(_promoCards.length, (index) {
              return AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                margin: const EdgeInsets.symmetric(horizontal: 3),
                height: 5,
                width: _currentPromoIndex == index ? 16 : 5,
                decoration: BoxDecoration(
                  color: _currentPromoIndex == index
                      ? AppColors.primary
                      : AppColors.divider,
                  borderRadius: BorderRadius.circular(3),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildPendingCommissionSection(double pendingAmount) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.onPrimary.withOpacity(0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.schedule,
                    color: AppColors.onPrimary.withOpacity(0.9),
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Pending Commission',
                        style: AppTextStyles.caption.copyWith(
                          color: AppColors.onPrimary.withOpacity(0.9),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '₹${pendingAmount.toStringAsFixed(2)}',
                        style: AppTextStyles.heading3.copyWith(
                          color: AppColors.onPrimary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
          if (pendingAmount > 0) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _payCommissionViaUPI,
                    icon: const Icon(Icons.payment, size: 18),
                    label: Text(
                      'Pay Now via UPI',
                      style: AppTextStyles.button.copyWith(
                        fontSize: 14,
                        color: AppColors.primary,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.onPrimary,
                      foregroundColor: AppColors.primary,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      elevation: 0,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => WalletPage(driverId: _driverId),
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.onPrimary.withOpacity(0.3),
                    foregroundColor: AppColors.onPrimary,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    elevation: 0,
                  ),
                  child: const Icon(Icons.arrow_forward, size: 20),
                ),
              ],
            ),
          ] else
            ElevatedButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => WalletPage(driverId: _driverId),
                ),
              ),
              icon: const Icon(Icons.arrow_forward, size: 16),
              label: Text(
                'View Details',
                style: AppTextStyles.button.copyWith(
                  fontSize: 12,
                  color: AppColors.primary,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.onPrimary,
                foregroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                elevation: 0,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildRideHistoryTile() {
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => DriverRideHistoryPage(driverId: _driverId),
        ),
      ),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [AppColors.success, AppColors.success.withOpacity(0.8)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: AppColors.success.withOpacity(0.3),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.onPrimary.withOpacity(0.2),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.history, color: AppColors.onPrimary, size: 28),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Ride History',
                    style: AppTextStyles.heading3.copyWith(
                      color: AppColors.onPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'View all completed rides',
                    style: AppTextStyles.body2.copyWith(
                      color: AppColors.onPrimary.withOpacity(0.9),
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios, color: AppColors.onPrimary, size: 20),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // DRAWER
  // ===========================================================================

  Widget _buildDrawer() {
    return Drawer(
      backgroundColor: AppColors.background,
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          _buildDrawerHeader(),

          _buildDrawerItem(
            Icons.account_balance_wallet,
            "Earnings",
            "Transfer Money to Bank, History",
            iconColor: AppColors.primary,
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => WalletPage(driverId: _driverId),
                ),
              );
            },
          ),

          _buildDrawerItem(
            Icons.history,
            "Ride History",
            "View completed rides & earnings",
            iconColor: AppColors.success,
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => DriverRideHistoryPage(driverId: _driverId),
                ),
              );
            },
          ),

          _buildDrawerItem(
            Icons.card_giftcard,
            "Rewards & Incentives",
            "Earn money and coins per ride",
            iconColor: AppColors.primary,
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => IncentivesPage(driverId: _driverId),
                ),
              );
            },
          ),

          _buildDrawerItem(
            Icons.workspace_premium,
            "Plans",
            "View and purchase driver plans",
            iconColor: AppColors.warning,
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => PlansPage(driverId: _driverId),
                ),
              );
            },
          ),

          _buildDrawerItem(
            Icons.notifications_none,
            'Notifications',
            'View alerts & updates',
            iconColor: AppColors.primary,
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const DriverNotificationPage(),
                ),
              );
            },
          ),

          // ❌ REMOVED:
          // _buildDrawerItem(Icons.local_offer, "Rewards & Benefits", ...)
          // _buildDrawerItem(Icons.view_module, "Service Manager", ...)
          // _buildDrawerItem(Icons.map, "Demand Planner", ...)
          _buildDrawerItem(
            Icons.headset_mic,
            "Help",
            "Support & FAQs",
            iconColor: AppColors.primary,
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => DriverHelpSupportPage(driverId: _driverId),
                ),
              );
            },
          ),

          Divider(color: AppColors.divider),

          _buildReferralBanner(),
        ],
      ),
    );
  }

  Widget _buildDrawerHeader() {
    final displayName = _driverName ?? 'My Profile';
    final subtitleText = _driverName != null
        ? 'View & edit your profile'
        : 'Tap to view details';

    ImageProvider avatarImage;
    if (_driverPhotoUrl != null && _driverPhotoUrl!.isNotEmpty) {
      avatarImage = NetworkImage(_driverPhotoUrl!);
    } else {
      // fallback image
      avatarImage = const AssetImage('assets/profile.jpg');
    }
    return DrawerHeader(
      decoration: BoxDecoration(
        image: DecorationImage(
          image: const AssetImage('assets/images/banner_profile.png'),
          fit: BoxFit.cover,
          colorFilter: ColorFilter.mode(
            AppColors.primary.withOpacity(0.75), // keeps orange tone
            BlendMode.overlay,
          ),
        ),
      ),
      child: InkWell(
        onTap: () {
          Navigator.pop(context);
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => DriverProfilePage(driverId: _driverId),
            ),
          );
        },
        child: Row(
          children: [
            CircleAvatar(backgroundImage: avatarImage, radius: 30),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    displayName,
                    style: AppTextStyles.heading3.copyWith(
                      color: AppColors.onPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitleText,
                    style: AppTextStyles.caption.copyWith(
                      color: AppColors.onPrimary.withOpacity(0.8),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios, color: AppColors.onPrimary, size: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildDrawerItem(
    IconData icon,
    String title,

    String subtitle, {
    Color iconColor = Colors.black54,
    VoidCallback? onTap,
  }) {
    return ListTile(
      leading: Icon(icon, color: iconColor),
      title: Text(title, style: AppTextStyles.body1),
      subtitle: Text(subtitle, style: AppTextStyles.caption),
      onTap: onTap ?? () {},
    );
  }

  Widget _buildReferralBanner() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.primary.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        child: Row(
          children: [
            Icon(Icons.emoji_people, color: AppColors.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                "Refer friends & Earn up to ₹",
                style: AppTextStyles.body1,
              ),
            ),
            TextButton(
              onPressed: () {},
              style: TextButton.styleFrom(foregroundColor: AppColors.primary),
              child: Text(
                "Refer Now",
                style: AppTextStyles.button.copyWith(
                  color: AppColors.primary,
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// RIDE REQUEST CARD WIDGET
// =============================================================================

class RideRequestCard extends StatefulWidget {
  final Map<String, dynamic> request;
  final VoidCallback onAccept;
  final VoidCallback onReject;
  final int position;
  final LatLng? driverLocation;
  final double perRideIncentive;
  final int perRideCoins;
  final bool isDestinationMatch;

  const RideRequestCard({
    Key? key,
    required this.request,
    required this.onAccept,
    required this.onReject,
    required this.position,
    this.driverLocation,
    this.perRideIncentive = 5.0,
    this.perRideCoins = 10,
    this.isDestinationMatch = false,
  }) : super(key: key);

  @override
  State<RideRequestCard> createState() => _RideRequestCardState();
}

class _RideRequestCardState extends State<RideRequestCard> {
  late int _secondsRemaining;
  Timer? _timer;
  double? _pickupDistance;
  double? _tripDistance;
  bool _calculatingDistances = true;

  // ... rest of _RideRequestCardState continues as-is ...
  @override
  void initState() {
    super.initState();
    _secondsRemaining = 10;
    _startTimer();
    _calculateDistances();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_secondsRemaining > 0) {
        if (mounted) setState(() => _secondsRemaining--);
      } else {
        _timer?.cancel();
        if (mounted) widget.onReject();
      }
    });
  }

  void _calculateDistances() async {
    try {
      final pickup = widget.request['pickup'];
      final drop = widget.request['drop'];

      if (pickup != null && drop != null) {
        final pickupLat = pickup['lat'] as double?;
        final pickupLng = pickup['lng'] as double?;
        final dropLat = drop['lat'] as double?;
        final dropLng = drop['lng'] as double?;

        if (pickupLat != null &&
            pickupLng != null &&
            widget.driverLocation != null) {
          _pickupDistance =
              Geolocator.distanceBetween(
                widget.driverLocation!.latitude,
                widget.driverLocation!.longitude,
                pickupLat,
                pickupLng,
              ) /
              1000;
        }

        if (pickupLat != null &&
            pickupLng != null &&
            dropLat != null &&
            dropLng != null) {
          _tripDistance =
              Geolocator.distanceBetween(
                pickupLat,
                pickupLng,
                dropLat,
                dropLng,
              ) /
              1000;
        }
      }
    } catch (e) {
      debugPrint('Error calculating distances: $e');
    }

    if (mounted) setState(() => _calculatingDistances = false);
  }

  /// Smart Google Maps address extraction — finds the main locality.
  /// Skips house numbers (#3-4-62), landmark prefixes (Near, Opp, etc.)
  /// Returns the locality + next part (e.g. "Kachiguda, Hyderabad")
  String _extractMainArea(String? fullAddress) {
    if (fullAddress == null || fullAddress.isEmpty) return 'Location';
    final parts = fullAddress
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (parts.isEmpty) return 'Location';
    if (parts.length == 1) {
      final t = parts[0];
      return t.length > 30 ? '${t.substring(0, 30)}...' : t;
    }

    final skipPrefixes = [
      'near ',
      'beside ',
      'opp ',
      'opposite ',
      'behind ',
      'next to ',
    ];
    int mainIdx = 0;
    for (int i = 0; i < parts.length && i < 4; i++) {
      final p = parts[i].toLowerCase();
      final isHouseNum = RegExp(r'^[#\d]').hasMatch(parts[i]);
      final isLandmark = skipPrefixes.any((prefix) => p.startsWith(prefix));
      if (!isHouseNum && !isLandmark && parts[i].length >= 3) {
        mainIdx = i;
        break;
      }
      mainIdx = i;
    }

    final main = parts[mainIdx];
    if (mainIdx + 1 < parts.length) {
      final next = parts[mainIdx + 1];
      final isPin = RegExp(r'^\d{5,6}$').hasMatch(next);
      final isGeneric = [
        'india',
        'telangana',
        'andhra pradesh',
        'karnataka',
        'maharashtra',
        'tamil nadu',
        'kerala',
      ].contains(next.toLowerCase());
      if (!isPin && !isGeneric) {
        return '$main, $next';
      }
    }
    return main;
  }

  double? _parseDouble(dynamic v) {
    if (v == null) return null;
    if (v is double) return v;
    if (v is int) return v.toDouble();
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v.trim());
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final fare = widget.request['fare'];
    final fareAmount = _parseDouble(fare);

    const platformCommission = 0.12;
    final driverBaseEarning = fareAmount != null
        ? fareAmount * (1 - platformCommission)
        : null;
    final totalDriverGets = driverBaseEarning != null
        ? driverBaseEarning + widget.perRideIncentive
        : null;

    final pickupMainArea = _extractMainArea(
      widget.request['pickup']?['address'],
    );
    final dropMainArea = _extractMainArea(widget.request['drop']?['address']);

    final isUrgent = _secondsRemaining <= 3;

    // Destination match changes border and theme
    final Color borderColor = widget.isDestinationMatch
        ? Colors.orange
        : (isUrgent ? AppColors.error : AppColors.primary);

    return Container(
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: borderColor.withOpacity(0.2),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          _buildHeader(isUrgent),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              children: [
                if (!_calculatingDistances) _buildDistanceInfo(),

                _buildLocationRow(
                  Icons.location_on,
                  AppColors.success,
                  pickupMainArea,
                  isPickup: true,
                ),

                const SizedBox(height: 8),

                _buildDropLocationRow(dropMainArea),

                const SizedBox(height: 16),
                if (fareAmount != null) _buildFareSection(fareAmount),
                const SizedBox(height: 16),
                _buildActionButtons(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(bool isUrgent) {
    final Color themeColor = widget.isDestinationMatch
        ? Colors.orange
        : (isUrgent ? AppColors.error : AppColors.primary);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: themeColor.withOpacity(0.12),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(14),
          topRight: Radius.circular(14),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: themeColor.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    widget.isDestinationMatch
                        ? Icons.favorite
                        : Icons.local_taxi,
                    color: themeColor,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.isDestinationMatch ? "On Your Way!" : "New Ride",
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: themeColor,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (widget.isDestinationMatch)
                        Text(
                          "Drop near destination",
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                            color: themeColor.withOpacity(0.8),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: isUrgent ? AppColors.error : AppColors.warning,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.timer, color: AppColors.onPrimary, size: 14),
                const SizedBox(width: 4),
                Text(
                  '${_secondsRemaining}s',
                  style: TextStyle(
                    color: AppColors.onPrimary,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDistanceInfo() {
    if (_pickupDistance == null && _tripDistance == null) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (_pickupDistance != null) ...[
            Icon(Icons.my_location, color: AppColors.primary, size: 18),
            const SizedBox(width: 6),
            Text(
              '${_pickupDistance!.toStringAsFixed(1)} km',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppColors.primary,
              ),
            ),
          ],
          if (_pickupDistance != null && _tripDistance != null) ...[
            const SizedBox(width: 12),
            Container(width: 1.5, height: 18, color: AppColors.divider),
            const SizedBox(width: 12),
          ],
          if (_tripDistance != null) ...[
            Icon(Icons.route, color: AppColors.success, size: 18),
            const SizedBox(width: 6),
            Text(
              '${_tripDistance!.toStringAsFixed(1)} km trip',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppColors.success,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Extracts sub-area (everything after first 2 parts) from address
  String _getSubArea(String? full) {
    if (full == null || full.isEmpty) return '';
    final parts = full
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (parts.length <= 2) return '';

    // Find mainIdx same way as _extractMainArea
    final skipPrefixes = [
      'near ',
      'beside ',
      'opp ',
      'opposite ',
      'behind ',
      'next to ',
    ];
    int mainIdx = 0;
    for (int i = 0; i < parts.length && i < 4; i++) {
      final p = parts[i].toLowerCase();
      final isHouseNum = RegExp(r'^[#\d]').hasMatch(parts[i]);
      final isLandmark = skipPrefixes.any((prefix) => p.startsWith(prefix));
      if (!isHouseNum && !isLandmark && parts[i].length >= 3) {
        mainIdx = i;
        break;
      }
      mainIdx = i;
    }

    // Sub starts after main+1
    final subStart = mainIdx + 2;
    if (subStart >= parts.length) return '';
    return parts
        .sublist(subStart, (subStart + 3).clamp(0, parts.length))
        .where((e) => !RegExp(r'^\d{5,6}$').hasMatch(e))
        .join(', ');
  }

  Widget _buildLocationRow(
    IconData icon,
    Color color,
    String address, {
    bool isPickup = false,
  }) {
    String? fullAddr;
    if (isPickup) {
      final pickup = widget.request['pickup'];
      fullAddr = pickup != null ? pickup['address'] as String? : null;
    }
    final subArea = _getSubArea(fullAddr);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Icon bubble
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: color.withOpacity(0.12),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: color, size: 14),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Address + distance badge on the same line ─────────────────
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Text(
                      address,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.onSurface,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              if (subArea.isNotEmpty)
                Text(
                  subArea,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    fontWeight: FontWeight.w400,
                    color: AppColors.onSurfaceSecondary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
        ),
      ],
    );
  }

  // ─── 3. DROP LOCATION ROW ─────────────────────────────────────────────────
  // Added: trip-distance badge shown inline beside the drop address

  Widget _buildDropLocationRow(String address) {
    final drop = widget.request['drop'];
    final fullAddr = drop != null ? drop['address'] as String? : null;
    final subArea = _getSubArea(fullAddr);
    final Color color = widget.isDestinationMatch
        ? Colors.orange
        : AppColors.error;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Icon bubble
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: color.withOpacity(0.12),
            shape: BoxShape.circle,
          ),
          child: Icon(
            widget.isDestinationMatch ? Icons.favorite : Icons.flag_rounded,
            color: color,
            size: 14,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Address + trip-distance badge on the same line ────────────
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Text(
                      address,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.onSurface,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              if (subArea.isNotEmpty)
                Text(
                  subArea,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    fontWeight: FontWeight.w400,
                    color: AppColors.onSurfaceSecondary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFareSection(double fareAmount) {
    final hasIncentive = widget.perRideIncentive > 0;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF0FFF4),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFBBF7D0)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Fare + incentive inline, same font size ───────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                '₹${fareAmount.toStringAsFixed(0)}',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF16A34A),
                ),
              ),
              if (hasIncentive) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Text(
                    '+',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: Colors.grey[500],
                    ),
                  ),
                ),
                Text(
                  '₹${widget.perRideIncentive.toStringAsFixed(0)}',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    color: AppColors.primary,
                  ),
                ),
              ],
            ],
          ),

          // ── "Per-ride incentive" label, same as complete trip ─────────────
          if (hasIncentive) ...[
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.star_rounded,
                  color: AppColors.primary,
                  size: 12,
                ),
                const SizedBox(width: 4),
                Text(
                  'Per-ride incentive',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: AppColors.primary.withOpacity(0.8),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildActionButtons() {
    return Row(
      children: [
        Expanded(
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: AppColors.onPrimary,
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              elevation: 2,
            ),
            onPressed: widget.onReject,
            child: Text(
              "Reject",
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: AppColors.onPrimary,
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          flex: 2,
          child: ElevatedButton.icon(
            icon: Icon(
              widget.isDestinationMatch
                  ? Icons.favorite
                  : Icons.check_circle, // ✅ FIXED
              size: 18,
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor:
                  widget
                      .isDestinationMatch // ✅ FIXED
                  ? Colors.orange
                  : AppColors.success,
              foregroundColor: AppColors.onPrimary,
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              elevation: 3,
            ),
            onPressed: widget.onAccept,
            label: Text(
              widget.isDestinationMatch ? "Accept 🧡" : "Accept", // ✅ FIXED
              style: GoogleFonts.plusJakartaSans(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: AppColors.onPrimary,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
// =============================================================================
// PROMOTION CARD WIDGETS
// =============================================================================

class _PromotionImageCard extends StatelessWidget {
  final String imageUrl;
  final String title;
  final String promotionId;
  final VoidCallback onTap;

  const _PromotionImageCard({
    required this.imageUrl,
    required this.title,
    required this.promotionId,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withOpacity(0.15),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.network(
                imageUrl,
                fit: BoxFit.cover,
                loadingBuilder: (context, child, loadingProgress) {
                  if (loadingProgress == null) return child;

                  final progress = loadingProgress.expectedTotalBytes != null
                      ? loadingProgress.cumulativeBytesLoaded /
                            loadingProgress.expectedTotalBytes!
                      : null;

                  return Container(
                    color: AppColors.surface,
                    child: Center(
                      child: CircularProgressIndicator(
                        value: progress,
                        strokeWidth: 2,
                        valueColor: const AlwaysStoppedAnimation<Color>(
                          AppColors.primary,
                        ),
                      ),
                    ),
                  );
                },
                errorBuilder: (context, error, stackTrace) {
                  return Container(
                    color: AppColors.surface,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.broken_image_outlined,
                          size: 40,
                          color: AppColors.error,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Failed to load',
                          style: AppTextStyles.caption.copyWith(
                            color: AppColors.error,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
              // Overlay with title
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.black.withOpacity(0.7),
                      ],
                    ),
                  ),
                  child: Text(
                    title,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BigPromoCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final List<Color> gradientColors;

  const _BigPromoCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.gradientColors,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: gradientColors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: gradientColors[0].withOpacity(0.25),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Stack(
        children: [
          // Background pattern
          Positioned(
            right: -30,
            bottom: -30,
            child: Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
            ),
          ),
          // Content
          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        title,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 11,
                          fontWeight: FontWeight.w400,
                          color: Colors.white.withOpacity(0.85),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, size: 28, color: Colors.white),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
