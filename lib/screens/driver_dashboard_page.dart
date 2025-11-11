import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import '../services/background_service.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/socket_service.dart';
import 'incentivespage.dart'; // ✅ ADD THIS

import 'package:firebase_messaging/firebase_messaging.dart';
import '../screens/chat_page.dart';
import 'wallet_page.dart';
import 'package:flutter/services.dart'; // ✅ ADD THIS LINE
import 'package:flutter/foundation.dart'; // ✅ ADD THIS for kDebugMode
import 'driver_profile_page.dart'; // ✅ Add this
import 'driver_ride_history_page.dart'; // ✅ ADD THIS
// ✅ ADD YOUR THEME CLASSES HERE
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
    static const Color gold = Color(0xFFFFD700); // ✅ ADD THIS LINE

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

class DriverDashboardPage extends StatefulWidget {
  final String driverId;
  final String vehicleType;

  const DriverDashboardPage({
    Key? key,
    required this.driverId,
    required this.vehicleType,
  }) : super(key: key);

  @override
  _DriverDashboardPageState createState() => _DriverDashboardPageState();
}

class _DriverDashboardPageState extends State<DriverDashboardPage> with WidgetsBindingObserver {
  final String apiBase = 'https://1708303a1cc8.ngrok-free.app';
  final DriverSocketService _socketService = DriverSocketService();
  String ridePhase = 'none';
  String? customerOtp;
  TextEditingController otpController = TextEditingController();
  double? finalFareAmount;
  double? tripFareAmount;

  bool isOnline = false;
  bool acceptsLong = false;
  List<Map<String, dynamic>> rideRequests = [];
  Map<String, dynamic>? currentRide;
  Map<String, dynamic>? activeTripDetails;

  GoogleMapController? _googleMapController;
  late String driverId;

  GoogleMapController? _mapController;
  LatLng? _currentPosition;
  LatLng? _customerPickup;
  Timer? _locationUpdateTimer;
  Timer? _cleanupTimer;
  Timer? _heartbeatTimer;  // ✅ NEW

  final Set<String> _seenTripIds = {};

  final Set<Marker> _markers = {};
  final Set<Polyline> _polylines = {};
  final AudioPlayer _audioPlayer = AudioPlayer();
  String? driverFcmToken;
  String? _activeTripId;
  Map<String, dynamic>? walletData;
bool isLoadingWallet = false;
Map<String, dynamic>? todayEarnings;
bool isLoadingToday = false;
// ✅ INCENTIVE SETTINGS
double perRideIncentive = 5.0;
int perRideCoins = 10;
@override
void initState() {
  super.initState();
  driverId = widget.driverId;

  TripBackgroundService.initializeService();
  WidgetsBinding.instance.addObserver(this);

  _restoreDriverSessionAndInit();
    _fetchIncentiveSettings(); // ✅ ADD THIS LINE

  _cleanupTimer = Timer.periodic(const Duration(minutes: 5), (timer) {
    if (_seenTripIds.length > 100) {
      final recentIds = _seenTripIds.toList().sublist(_seenTripIds.length - 50);
      _seenTripIds.clear();
      _seenTripIds.addAll(recentIds);
      print("🧹 Cleaned up old trip IDs, kept ${_seenTripIds.length} recent ones");
    }
  });

  // ✅ CHECK FOR ACTIVE TRIP AFTER INITIALIZATION
  Future.microtask(() async {
    await Future.delayed(const Duration(seconds: 2)); // Wait for socket connection
    await _checkAndResumeActiveTrip();
  });
}

Future<void> _restoreDriverSessionAndInit() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    // restore previous online state (default: false)
    final savedOnline = prefs.getBool('isOnline') ?? false;
    final savedAcceptsLong = prefs.getBool('acceptsLong') ?? false;
    final savedVehicleType = prefs.getString('vehicleType') ?? widget.vehicleType;

    setState(() {
      isOnline = savedOnline;
      acceptsLong = savedAcceptsLong;
    });

    // Ensure vehicleType stays in sync (persisted may override)
    // If you want widget.vehicleType immutable, skip setting it here
    // but we'll keep it consistent in prefs.
    await prefs.setString('vehicleType', savedVehicleType);

    // Request location permissions and get initial location
    await _requestLocationPermission();
    await _getCurrentLocation();

    // Initialize socket + FCM with restored isOnline & vehicle type
    await _initSocketAndFCM();
  } catch (e) {
    print('⚠️ Failed to restore session: $e');
    // fallback to normal init
    await _requestLocationPermission();
    await _getCurrentLocation();
    await _initSocketAndFCM();
  }
}

Future<void> _checkAndResumeActiveTrip() async {
  try {
    print('');
    print('=' * 70);
    print('🔍 CHECKING FOR ACTIVE TRIP ON APP RESTART');
    print('=' * 70);
    
    final response = await http.get(
      Uri.parse('$apiBase/api/trip/driver/active/${widget.driverId}'),
      headers: {'Content-Type': 'application/json'},
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      
      if (data['success'] && data['hasActiveTrip']) {
        print('⚠️ ACTIVE TRIP DETECTED - RESUMING');
        
        final tripData = data['trip'];
        final customerData = data['customer'];
        
        print('   Trip ID: ${tripData['tripId']}');
        print('   Status: ${tripData['status']}');
        print('   RidePhase from backend: ${tripData['ridePhase']}');
        
        final String resumedPhase = tripData['ridePhase'] ?? 'going_to_pickup';
        
        // ✅ CRITICAL FIX: Check paymentCollected from API response first
        final paymentCollected = tripData['paymentCollected'] ?? false;
        
        if (paymentCollected == true) {
          print('');
          print('✅ PAYMENT ALREADY COLLECTED - CLEANING UP');
          print('   Trip ID: ${tripData['tripId']}');
          print('   This is stale data from backend - clearing it now');
          print('');
          
          // ✅ CRITICAL: Clear driver state on BACKEND
          await _clearDriverStateOnBackend();
          
          // ✅ Clear local state
          _clearActiveTrip();
          
          // ✅ Clear socket service
          _socketService.setActiveTrip(null);
          
          // ✅ Stop any background services
          await TripBackgroundService.stopTripService();
          await WakelockPlus.disable();
          
          print('✅ Cleanup complete - driver is now FREE');
          print('=' * 70);
          print('');
          
          // Show success message
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Row(
                  children: [
                    Icon(Icons.check_circle, color: Colors.white),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Ready for new trips!',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
                backgroundColor: AppColors.success,
                duration: const Duration(seconds: 3),
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
          
          return; // ✅ Exit - don't show any UI
        }
        
        // ✅ ADDITIONAL CHECK: If phase is completed, double-verify
        if (resumedPhase == 'completed') {
          // Double-check with direct trip fetch
          final verifyResponse = await http.get(
            Uri.parse('$apiBase/api/trip/${tripData['tripId']}'),
            headers: {'Content-Type': 'application/json'},
          );
          
          if (verifyResponse.statusCode == 200) {
            final verifyData = jsonDecode(verifyResponse.body);
            
            if (verifyData['success']) {
              final actualTrip = verifyData['trip'];
              
              // ✅ Check if payment is already collected
              if (actualTrip['paymentCollected'] == true) {
                print('');
                print('✅ PAYMENT ALREADY COLLECTED - CLEANING UP');
                print('   Trip ID: ${tripData['tripId']}');
                print('   This is stale data - clearing it now');
                print('');
                
                // ✅ CRITICAL: Clear driver state on BACKEND
                await _clearDriverStateOnBackend();
                
                // ✅ Clear local state
                _clearActiveTrip();
                
                // ✅ Clear socket service
                _socketService.setActiveTrip(null);
                
                // ✅ Stop any background services
                await TripBackgroundService.stopTripService();
                await WakelockPlus.disable();
                
                print('✅ Cleanup complete - driver is now FREE');
                print('=' * 70);
                print('');
                
                // Show success message
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Row(
                        children: [
                          Icon(Icons.check_circle, color: Colors.white),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Ready for new trips!',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                      backgroundColor: AppColors.success,
                      duration: const Duration(seconds: 3),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
                
                return; // ✅ Exit - don't show collect cash button
              }
            }
          }
        }
        
        // ✅ If we reach here, trip is truly active - restore it
        print('⚠️ Trip is TRULY ACTIVE - resuming');
        
        setState(() {
          _activeTripId = tripData['tripId'];
          ridePhase = resumedPhase;
          customerOtp = tripData['rideCode'];
          tripFareAmount = _parseDouble(tripData['fare']);
          finalFareAmount = tripFareAmount;
          
          activeTripDetails = {
            'tripId': tripData['tripId'],
            'trip': {
              'pickup': {
                'lat': tripData['pickup']['lat'],
                'lng': tripData['pickup']['lng'],
                'address': tripData['pickup']['address'],
              },
              'drop': {
                'lat': tripData['drop']['lat'],
                'lng': tripData['drop']['lng'],
                'address': tripData['drop']['address'],
              },
              'fare': tripData['fare'],
            },
            'customer': customerData,
          };
          
          _customerPickup = LatLng(
            tripData['pickup']['lat'],
            tripData['pickup']['lng'],
          );
        });
        
        // ✅ Reconnect socket with active trip
        _socketService.setActiveTrip(tripData['tripId']);
        
        // ✅ Restart background service
        await TripBackgroundService.startTripService(
          tripId: tripData['tripId'],
          driverId: widget.driverId,
          customerName: customerData?['name'] ?? 'Customer',
        );
        
        await WakelockPlus.enable();
        _startLiveLocationUpdates();
        _startHeartbeat();
        
        if (ridePhase == 'going_to_pickup' || ridePhase == 'at_pickup') {
          _drawRouteToCustomer();
        }
        
        print('✅ Trip resumed successfully');
        print('=' * 70);
        print('');
        
        if (mounted) {
          _showTripResumeDialog(tripData, customerData);
        }
      } else {
        print('✅ No active trip found - driver is free');
        
        // ✅ Extra safety: Clear backend state just in case
        await _clearDriverStateOnBackend();
        
        print('=' * 70);
        print('');
      }
    } else {
      print('⚠️ Failed to check active trip: ${response.statusCode}');
    }
  } catch (e) {
    print('❌ Error checking active trip: $e');
    print('Stack trace: ${StackTrace.current}');
  }
}

// ✅ UPDATED: Complete _showTripResumeDialog function with cash collection handling

void _showTripResumeDialog(Map<String, dynamic> tripData, Map<String, dynamic>? customerData) {
  String phaseMessage = '';
  IconData phaseIcon = Icons.local_taxi;
  Color phaseColor = AppColors.primary;
  
  switch (ridePhase) {
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
      // ✅ CRITICAL: Show urgent cash collection message
      phaseMessage = 'Trip completed - PLEASE COLLECT CASH NOW!';
      phaseIcon = Icons.payments;  // ✅ Money icon
      phaseColor = AppColors.error;  // ✅ Red for urgency
      break;
    default:
      phaseMessage = 'Resuming active trip';
  }
  
  showDialog(
    context: context,
    barrierDismissible: ridePhase != 'completed', // ✅ Can't dismiss if awaiting cash
    builder: (context) => WillPopScope(
      onWillPop: () async => ridePhase != 'completed', // ✅ Prevent back button if awaiting cash
      child: AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(phaseIcon, color: phaseColor, size: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                ridePhase == 'completed' ? 'Collect Cash!' : 'Trip Resumed',
                style: AppTextStyles.heading3.copyWith(
                  color: ridePhase == 'completed' ? AppColors.error : null,
                  fontWeight: ridePhase == 'completed' ? FontWeight.bold : FontWeight.w600,
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
                  fontWeight: ridePhase == 'completed' ? FontWeight.bold : FontWeight.normal,
                  color: ridePhase == 'completed' ? AppColors.error : null,
                ),
              ),
              
              // ✅ CRITICAL WARNING for completed trips
              if (ridePhase == 'completed') ...[
                const SizedBox(height: 16),
                Container(
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
                          'You cannot accept new trips until you confirm cash collection!',
                          style: AppTextStyles.body2.copyWith(
                            color: AppColors.error,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              
              const SizedBox(height: 16),
              Divider(color: AppColors.divider),
              const SizedBox(height: 12),
              
              // Customer info
              if (customerData != null) ...[
                Row(
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
                          Text(
                            customerData['phone'] ?? '',
                            style: AppTextStyles.caption,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
              ],
              
              // Trip details
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    _buildResumeDetailRow(
                      Icons.location_on,
                      'Pickup',
                      tripData['pickup']['address'] ?? 'Pickup Location',
                    ),
                    const SizedBox(height: 8),
                    _buildResumeDetailRow(
                      Icons.flag,
                      'Drop',
                      tripData['drop']['address'] ?? 'Drop Location',
                    ),
                    const SizedBox(height: 8),
                    _buildResumeDetailRow(
                      Icons.payments,
                      'Fare',
                      '₹${tripFareAmount?.toStringAsFixed(2) ?? '0.00'}',
                      valueColor: ridePhase == 'completed' ? AppColors.error : AppColors.primary,
                    ),
                    if (customerOtp != null && ridePhase != 'completed') ...[
                      const SizedBox(height: 8),
                      _buildResumeDetailRow(
                        Icons.lock,
                        'Ride Code',
                        customerOtp!,
                        valueColor: AppColors.primary,
                      ),
                    ],
                  ],
                ),
              ),
              
              const SizedBox(height: 16),
              
              // Warning (only show for non-completed trips)
              if (ridePhase != 'completed')
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.warning.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.warning),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, color: AppColors.warning, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'App will stay awake until trip is completed',
                          style: AppTextStyles.caption.copyWith(
                            color: AppColors.warning,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        actions: [
          if (ridePhase == 'completed')
            // ✅ For completed trips, show ONLY collect cash button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  // Trigger cash collection immediately
                  Future.delayed(const Duration(milliseconds: 300), () {
                    _confirmCashCollection();
                  });
                },
                icon: Icon(Icons.payments, size: 20),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.success,
                  foregroundColor: AppColors.onPrimary,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                label: Text(
                  'Collect ₹${tripFareAmount?.toStringAsFixed(2)} Now',
                  style: AppTextStyles.button.copyWith(
                    color: AppColors.onPrimary,
                    fontSize: 16,
                  ),
                ),
              ),
            )
          else
            // For active trips, show continue button
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: phaseColor,
                foregroundColor: AppColors.onPrimary,
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
              ),
              child: Text(
                'Continue Trip',
                style: AppTextStyles.button.copyWith(color: AppColors.onPrimary),
              ),
            ),
        ],
      ),
    ),
  );
}

// ✅ Helper function (keep as is)
Widget _buildResumeDetailRow(IconData icon, String label, String value, {Color? valueColor}) {
  return Row(
    children: [
      Icon(icon, size: 16, color: AppColors.onSurfaceSecondary),
      const SizedBox(width: 8),
      Text(
        '$label:',
        style: AppTextStyles.caption,
      ),
      const SizedBox(width: 8),
      Expanded(
        child: Text(
          value,
          style: AppTextStyles.body2.copyWith(
            color: valueColor,
            fontWeight: valueColor != null ? FontWeight.bold : FontWeight.normal,
          ),
          textAlign: TextAlign.right,
        ),
      ),
    ],
  );
}

Future<void> _checkForResumedTrip() async {
  final hasActive = await _socketService.hasActiveTripOnRestart();
  
  if (hasActive) {
    print('⚠️ Resuming from active trip!');
    
    // Show dialog to user
    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: Row(
            children: [
              Icon(Icons.warning, color: AppColors.warning),
              const SizedBox(width: 12),
              Text('Active Trip Detected', style: AppTextStyles.heading3),
            ],
          ),
          content: Text(
            'You have an active trip in progress. Please complete it before going offline.',
            style: AppTextStyles.body1,
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
              ),
              child: Text('OK', style: AppTextStyles.button.copyWith(color: AppColors.onPrimary)),
            ),
          ],
        ),
      );
    }
  }
}

 double? _parseDouble(dynamic v) {
  if (v == null) return null;
  if (v is double) return v;
  if (v is int) return v.toDouble();
  if (v is num) return v.toDouble();
  if (v is String) {
    final s = v.trim();
    if (s.isEmpty) return null;
    return double.tryParse(s);
  }
  return null;
}

  double _calculateDistance(LatLng point1, LatLng point2) {
    return Geolocator.distanceBetween(
      point1.latitude,
      point1.longitude,
      point2.latitude,
      point2.longitude,
    );
  }
Future<void> _fetchTodayEarnings() async {
  setState(() => isLoadingToday = true);
  
  try {
    final response = await http.get(
      Uri.parse('$apiBase/api/wallet/today/${widget.driverId}'),
      headers: {'Content-Type': 'application/json'},
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      if (data['success'] && mounted) {
        setState(() {
          todayEarnings = data['todayStats'];
          isLoadingToday = false;
        });
      }
    } else {
      setState(() => isLoadingToday = false);
    }
  } catch (e) {
    print('❌ Error fetching today earnings: $e');
    setState(() => isLoadingToday = false);
  }
}
Future<void> _fetchIncentiveSettings() async {
  try {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      print('⚠️ No authenticated user');
      return;
    }

    final token = await user.getIdToken();
    if (token == null) {
      print('⚠️ No Firebase token');
      return;
    }

    // ✅ USE SAME ENDPOINT AS INCENTIVES PAGE
    final response = await http.get(
      Uri.parse('$apiBase/api/incentives/${widget.driverId}'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );

    if (response.statusCode == 200) {
      final jsonResponse = jsonDecode(response.body);
      final data = jsonResponse['data'] ?? jsonResponse;
      
      if (mounted) {
        setState(() {
          // ✅ FETCH FROM BACKEND (SAME AS INCENTIVES PAGE)
          perRideIncentive = _parseDouble(data['perRideIncentive']) ?? 5.0;
          perRideCoins = (data['perRideCoins'] as num?)?.toInt() ?? 10;
        });
        
        print('');
        print('=' * 70);
        print('💰 INCENTIVE SETTINGS FETCHED FROM BACKEND');
        print('=' * 70);
        print('   Endpoint: /api/incentives/${widget.driverId}');
        print('   Per Ride Cash: ₹$perRideIncentive');
        print('   Per Ride Coins: $perRideCoins');
        print('=' * 70);
        print('');
      }
    } else {
      print('⚠️ Failed to fetch incentive settings: ${response.statusCode}');
      print('   Response: ${response.body}');
    }
  } catch (e) {
    print('❌ Error fetching incentive settings: $e');
  }
}
Future<void> _fetchWalletData() async {
  setState(() => isLoadingWallet = true);
  
  try {
    final response = await http.get(
      Uri.parse('$apiBase/api/wallet/${widget.driverId}'),
      headers: {'Content-Type': 'application/json'},
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      if (data['success'] && mounted) {
        setState(() {
          walletData = data['wallet'];
          isLoadingWallet = false;
        });
        print('✅ Wallet data fetched: $walletData');
      }
    } else {
      setState(() => isLoadingWallet = false);
      print('⚠️ Wallet fetch failed: ${response.statusCode}');
    }
  } catch (e) {
    print('❌ Error fetching wallet data: $e');
    setState(() => isLoadingWallet = false);
  }
}

 Future<void> _sendLocationToBackend(double lat, double lng) async {
  try {
    await http.post(
      Uri.parse('$apiBase/api/location/updateDriver'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'driverId': driverId,
        'latitude': lat,
        'longitude': lng,
        'tripId': _activeTripId,
      }),
    );

    // persist last location for background service
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('lastLat', lat.toString());
    await prefs.setString('lastLng', lng.toString());

    _socketService.socket.emit('driver:location', {
      'tripId': _activeTripId,
      'latitude': lat,
      'longitude': lng,
    });
  } catch (e) {
    print('Error sending driver location: $e');
  }
}

  Future<void> _initSocketAndFCM() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final persistedIsOnline = prefs.getBool('isOnline') ?? isOnline;
    final persistedVehicleType = prefs.getString('vehicleType') ?? widget.vehicleType;

    // fetch fcm token
    driverFcmToken = await FirebaseMessaging.instance.getToken();

    // get position if not already fetched
    Position pos;
    try {
      pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      setState(() {
        _currentPosition = LatLng(pos.latitude, pos.longitude);
      });
    } catch (e) {
      print('⚠️ Could not get position: $e');
      pos = Position(latitude: _currentPosition?.latitude ?? 0.0, longitude: _currentPosition?.longitude ?? 0.0, timestamp: DateTime.now(), accuracy: 0.0, altitude: 0.0, heading: 0.0, speed: 0.0, speedAccuracy: 0.0, altitudeAccuracy: 0.0, headingAccuracy: 0.0);
    }

    // Use persisted values for initial connection
    isOnline = persistedIsOnline;
    widget.vehicleType.toLowerCase();
    await prefs.setString('vehicleType', persistedVehicleType);

    _socketService.connect(
      driverId,
      pos.latitude,
      pos.longitude,
      vehicleType: persistedVehicleType,
      isOnline: isOnline,
      fcmToken: driverFcmToken,
    );
_socketService.socket.on('trip:cancelled', (data) {
  if (!mounted) return;
  
  print('');
  print('=' * 70);
  print('🚫 TRIP CANCELLED EVENT RECEIVED');
  print('   Trip ID: ${data['tripId']}');
  print('   Cancelled By: ${data['cancelledBy']}');
  print('   Message: ${data['message']}');
  print('=' * 70);
  print('');
  
  final tripId = data['tripId']?.toString();
  final cancelledBy = data['cancelledBy'] ?? 'unknown';
  final message = data['message'] ?? 'Trip has been cancelled';
  
  // ✅ CRITICAL: Clear active trip if it matches
  if (_activeTripId == tripId) {
    setState(() {
      _clearActiveTrip(); // Clear all trip-related state
    });
    
    // ✅ Stop background service
    TripBackgroundService.stopTripService();
    WakelockPlus.disable();
    
    // ✅ Clear socket service active trip
    _socketService.setActiveTrip(null);
    
    print('✅ Active trip cleared - driver is now free');
  }
  
  // ✅ Close any open dialogs
  if (Navigator.canPop(context)) {
    Navigator.pop(context);
  }
  
  // ✅ Show cancellation message
  final displayMessage = cancelledBy == 'customer' 
      ? 'Customer cancelled the trip'
      : 'Trip has been cancelled';
  
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Row(
        children: [
          Icon(Icons.cancel, color: Colors.white),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              displayMessage,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
      backgroundColor: AppColors.warning,
      duration: const Duration(seconds: 4),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
    ),
  );
  
  print('📢 Driver notified of cancellation');
});

    _socketService.socket.on('trip:taken', (data) {
      print("🚫 Trip taken by another driver: $data");
      if (mounted) {
        final takenTripId = data['tripId']?.toString();
        
        setState(() {
          rideRequests.removeWhere((req) {
            final id = (req['tripId'] ?? req['_id'])?.toString();
            return id == takenTripId;
          });
          
          currentRide = rideRequests.isNotEmpty ? rideRequests.first : null;
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Trip accepted by ${data['acceptedBy']}'),
            backgroundColor: AppColors.warning,
            duration: const Duration(seconds: 2),
          ),
        );
        
        _stopNotificationSound();
      }
    });

    _socketService.socket.on('trip:confirmed_for_driver', (data) {
      print("✅ [SOCKET-PRIMARY] trip:confirmed_for_driver received: $data");
      if (mounted) {
        setState(() {
          activeTripDetails = data;
          final lat = data['trip']['pickup']['lat'];
          final lng = data['trip']['pickup']['lng'];
          _customerPickup = LatLng(lat, lng);
        });
        _drawRouteToCustomer();
        _startLiveLocationUpdates();
      }
    });

    _socketService.socket.on('trip:otp_generated', (data) {
      print("🔢 OTP Generated: $data");
      if (mounted) {
        setState(() {
          customerOtp = data['otp']?.toString();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('OTP sent to customer: ${data['otp']}')),
        );
      }
    });

    _socketService.socket.on('trip:ride_started', (data) {
      print("🚗 Ride Started: $data");
      if (mounted) {
        setState(() {
          ridePhase = 'going_to_drop';
        });
      }
    });

    _socketService.socket.on('trip:completed', (data) {
      print("✅ Trip Completed: $data");
      if (mounted) {
        setState(() {
          finalFareAmount = tripFareAmount ?? 0.0;
          ridePhase = 'completed';
        });
      }
    });

    _socketService.socket.on('trip:request', (data) {
      print("📥 [SOCKET-PRIMARY] trip:request received: $data");
      _handleIncomingTrip(data);
    });
_socketService.socket.on('trip:expired', (data) {
  print("⏰ Trip expired: $data");
  if (mounted) {
    final expiredTripId = data['tripId']?.toString();
    
    setState(() {
      rideRequests.removeWhere((req) {
        final id = (req['tripId'] ?? req['_id'])?.toString();
        return id == expiredTripId;
      });
      
      currentRide = rideRequests.isNotEmpty ? rideRequests.first : null;
    });
    
    // Close popup if it's showing the expired trip
    if (Navigator.canPop(context)) {
      Navigator.pop(context);
    }
    
    _stopNotificationSound();
  }
});
    _socketService.socket.on('tripRequest', (data) {
      print("📥 [SOCKET-PRIMARY] tripRequest received: $data (legacy)");
      _playNotificationSound();
      _handleIncomingTrip(data);
    });

    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      print("📩 [FCM-BACKUP] Foreground FCM received: ${message.data}");

      Future.delayed(const Duration(seconds: 2), () {
        final tripId = message.data['tripId']?.toString();
        if (tripId != null && !_seenTripIds.contains(tripId)) {
          final Map<String, dynamic> tripData = message.data.map((key, value) {
            try {
              return MapEntry(key, jsonDecode(value));
            } catch (e) {
              return MapEntry(key, value);
            }
          });

          _handleIncomingTrip(tripData);
        } else if (tripId != null) {
          print("⚠️ [FCM-BACKUP] Duplicate trip ignored (already handled by socket): $tripId");
        }
      });
    });

    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      print("📩 [FCM-BACKUP] Notification tapped: ${message.data}");

      Future.delayed(const Duration(seconds: 1), () {
        final tripId = message.data['tripId']?.toString();
        if (tripId != null && !_seenTripIds.contains(tripId)) {
          _playNotificationSound();

          final Map<String, dynamic> tripData = message.data.map((key, value) {
            try {
              return MapEntry(key, jsonDecode(value));
            } catch (e) {
              return MapEntry(key, value);
            }
          });

          _handleIncomingTrip(tripData);
        } else if (tripId != null) {
          print("⚠️ [FCM-BACKUP] Duplicate trip ignored (already handled): $tripId");
        }
      });
    });

    _socketService.onRideCancelled = (data) {
      print('❌ Ride cancelled: $data');
      if (mounted) {
        _playNotificationSound();
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Ride cancelled.')));
      }
    };
  } catch (e) {
    print('❌ _initSocketAndFCM error: $e');
  }
}
  void _handleIncomingTrip(dynamic rawData) {
    print("===========================================");
    print("🔥 Raw incoming trip DATA RECEIVED!");
    print("Type: ${rawData.runtimeType}");
    print("Content: $rawData");
    print("isOnline: $isOnline");
    print("vehicleType: ${widget.vehicleType}");
    print("===========================================");
    
    Map<String, dynamic> request;

    try {
      if (rawData is String) {
        request = jsonDecode(rawData) as Map<String, dynamic>;
      } else if (rawData is Map) {
        request = Map<String, dynamic>.from(rawData);
      } else {
        print("❌ Unsupported trip data format: $rawData");
        return;
      }

      if (request['pickup'] is String) {
        try {
          request['pickup'] = jsonDecode(request['pickup']);
        } catch (e) {
          print("⚠️ Could not parse pickup as JSON: ${request['pickup']}");
        }
      }
      
      if (request['drop'] is String) {
        try {
          request['drop'] = jsonDecode(request['drop']);
        } catch (e) {
          print("⚠️ Could not parse drop as JSON: ${request['drop']}");
        }
      }
      
      if (request['fare'] is String) {
        try {
          final fareString = request['fare'].toString().trim();
          if (fareString.isNotEmpty) {
            request['fare'] = double.parse(fareString);
            print("✅ Parsed fare from string: ${request['fare']}");
          }
        } catch (e) {
          print("⚠️ Could not parse fare as number: ${request['fare']} - Error: $e");
        }
      }
      
    } catch (e) {
      print("❌ Failed to parse trip data: $e");
      return;
    }

    final tripId = request['tripId']?.toString() ?? request['_id']?.toString();
    if (tripId == null) {
      print("❌ No tripId found in request");
      return;
    }

    final fare = request['fare'];
    final fareAmount = fare != null ? _parseDouble(fare) : null;
    
    print("===========================================");
    print("💰 TRIP FARE DETAILS:");
    print("   Raw fare value: $fare");
    print("   Fare type: ${fare.runtimeType}");
    print("   Parsed amount: ${fareAmount != null ? '₹${fareAmount.toStringAsFixed(2)}' : 'NOT AVAILABLE'}");
    print("===========================================");

    final isDuplicate = _seenTripIds.contains(tripId) ||
        rideRequests.any((req) {
          final existingTripId =
              req['tripId']?.toString() ?? req['_id']?.toString();
          return existingTripId == tripId;
        });

    if (isDuplicate) {
      print("⚠️ Duplicate trip ignored: $tripId");
      return;
    }
    
    _playNotificationSound();

    _seenTripIds.add(tripId);
    print("✅ Added trip to seen IDs: $tripId");

    print("✅ Normalized trip request: $request");

    if (!isOnline) {
      print("❌ Ignored because driver is off duty");
      return;
    }

    String requestVehicleType =
        (request['vehicleType'] ?? '').toString().toLowerCase().trim();
    String driverVehicleType = widget.vehicleType.toLowerCase().trim();

    if (requestVehicleType != driverVehicleType) {
      print("🚫 Vehicle type mismatch. Expected: $driverVehicleType, Got: $requestVehicleType");
      return;
    }

    if (fareAmount == null || fareAmount <= 0) {
      print("⚠️ WARNING: Trip $tripId has no valid fare amount!");
      print("   This trip will be added to requests but may cause issues later.");
    }

    setState(() {
      rideRequests.add(request);
      currentRide = rideRequests.isNotEmpty ? rideRequests.first : null;
    });

    _playNotificationSound();
    _showIncomingTripPopup(request);
  }


void _showIncomingTripPopup(Map<String, dynamic> request) {
  // Just add to queue and play sound - display is handled by overlay
  _playNotificationSound();
}
  void _playNotificationSound() async {
    await _audioPlayer.play(AssetSource('sounds/notification.mp3'));
  }
  
  void _launchGoogleMaps(double lat, double lng) async {
    final Uri googleMapsAppUrl = Uri.parse('google.navigation:q=$lat,$lng&mode=d');
    final Uri googleMapsWebUrl = Uri.parse(
        'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng&travelmode=driving');

    try {
      if (await canLaunchUrl(googleMapsAppUrl)) {
        await launchUrl(
          googleMapsAppUrl,
          mode: LaunchMode.externalApplication,
        );
        print('✅ Opened Google Maps app with navigation');
      } 
      else if (await canLaunchUrl(googleMapsWebUrl)) {
        await launchUrl(
          googleMapsWebUrl,
          mode: LaunchMode.externalApplication,
        );
        print('🌐 Opened Google Maps in browser');
      } 
      else {
        print('❌ Could not launch Google Maps.');
      }
    } catch (e) {
      print('🚨 Error launching Google Maps: $e');
    }
  }

  Future<void> _goToPickup() async {
    if (_activeTripId == null) return;

    try {
      final response = await http.post(
        Uri.parse('$apiBase/api/trip/going-to-pickup'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'tripId': _activeTripId,
          'driverId': driverId,
        }),
      );

      final data = jsonDecode(response.body);
      
      if (response.statusCode == 200 && data['success']) {
        setState(() {
          ridePhase = 'at_pickup';
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('You have arrived. Please enter the ride code from the customer.')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(data['message'] ?? 'Failed to update status')),
        );
      }
    } catch (e) {
      print('❌ Error in goToPickup: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  Future<void> _startRide() async {
  if (_activeTripId == null || _currentPosition == null) return;

  final enteredOtp = otpController.text.trim();
  if (enteredOtp.isEmpty) {
    _showStatusCard(
      icon: Icons.lock_outline,
      title: 'OTP Required',
      message: 'Please enter the 4-digit code from customer',
      color: AppColors.error,
    );
    return;
  }

  try {
    // Show loading indicator
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
                valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
              ),
              const SizedBox(height: 16),
              Text(
                'Starting ride...',
                style: AppTextStyles.body1,
              ),
            ],
          ),
        ),
      ),
    );

    _socketService.socket.emit('trip:start_ride', {
      'tripId': _activeTripId,
      'driverId': driverId,
      'otp': enteredOtp,
    });

    final response = await http.post(
      Uri.parse('$apiBase/api/trip/start-ride'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'tripId': _activeTripId,
        'driverId': driverId,
        'otp': enteredOtp,
        'driverLat': _currentPosition!.latitude,
        'driverLng': _currentPosition!.longitude,
      }),
    );

    final data = jsonDecode(response.body);
    
    // Close loading dialog
    if (Navigator.canPop(context)) Navigator.pop(context);
    
    if (response.statusCode == 200 && data['success']) {
      setState(() {
        ridePhase = 'going_to_drop';
        otpController.clear();
      });
      
      if (_currentPosition != null) {
        _sendLocationToBackend(_currentPosition!.latitude, _currentPosition!.longitude);
      }
      
      // ✅ Silent success - no snackbar
    } else {
      _showStatusCard(
        icon: Icons.error_outline,
        title: 'Incorrect OTP',
        message: data['message'] ?? 'Please check the code and try again',
        color: AppColors.error,
        duration: const Duration(seconds: 4),
      );
    }
  } catch (e) {
    if (Navigator.canPop(context)) Navigator.pop(context);
    
    _showStatusCard(
      icon: Icons.error_outline,
      title: 'Error',
      message: 'Failed to start ride. Please try again.',
      color: AppColors.error,
    );
  }
}
 void _clearActiveTrip() {
  print('');
  print('=' * 70);
  print('🧹 CLEARING ACTIVE TRIP STATE');
  print('=' * 70);
  
  setState(() {
    // Clear trip details
    activeTripDetails = null;
    _activeTripId = null;
    
    // Reset ride phase
    ridePhase = 'none';
    
    // Clear customer info
    customerOtp = null;
    _customerPickup = null;
    
    // Clear fare info
    finalFareAmount = null;
    tripFareAmount = null;
    
    // Clear UI elements
    _polylines.clear();
    _markers.clear();
    
    // Clear OTP input
    otpController.clear();
  });
  
  // Stop timers
  _locationUpdateTimer?.cancel();
  _locationUpdateTimer = null;
  
  _heartbeatTimer?.cancel();
  _heartbeatTimer = null;
  
  // Clear socket service
  _socketService.setActiveTrip(null);
  
  print('✅ All trip state cleared');
  print('   - activeTripDetails: null');
  print('   - ridePhase: none');
  print('   - _activeTripId: null');
  print('   - Timers: stopped');
  print('=' * 70);
  print('');
}

  Future<void> _completeRideNew() async {
  if (_activeTripId == null || _currentPosition == null) return;

  try {
    // Show loading
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
                valueColor: AlwaysStoppedAnimation<Color>(AppColors.success),
              ),
              const SizedBox(height: 16),
              Text(
                'Completing ride...',
                style: AppTextStyles.body1,
              ),
            ],
          ),
        ),
      ),
    );

    _socketService.socket.emit('trip:complete_ride', {
      'tripId': _activeTripId,
      'driverId': driverId,
    });

    final response = await http.post(
      Uri.parse('$apiBase/api/trip/complete-ride'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'tripId': _activeTripId,
        'driverId': driverId,
        'driverLat': _currentPosition!.latitude,
        'driverLng': _currentPosition!.longitude,
      }),
    );

    final data = jsonDecode(response.body);
    
    // Close loading
    if (Navigator.canPop(context)) Navigator.pop(context);
    
    if (response.statusCode == 200 && data['success']) {
      setState(() {
        ridePhase = 'completed';
        finalFareAmount = tripFareAmount ?? 0.0;
      });
      
      // ✅ Silent success - no snackbar
    } else {
      _showStatusCard(
        icon: Icons.error_outline,
        title: 'Failed',
        message: data['message'] ?? 'Could not complete ride',
        color: AppColors.error,
      );
    }
  } catch (e) {
    if (Navigator.canPop(context)) Navigator.pop(context);
    
    _showStatusCard(
      icon: Icons.error_outline,
      title: 'Error',
      message: 'Failed to complete ride. Please try again.',
      color: AppColors.error,
    );
  }
}

  void _startHeartbeat() {
  _heartbeatTimer?.cancel();
  _heartbeatTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
    if (_activeTripId != null) {
      _socketService.socket.emit('driver:heartbeat', {
        'tripId': _activeTripId,
        'driverId': widget.driverId,
        'timestamp': DateTime.now().toIso8601String(),
      });
      print('💓 Heartbeat sent for trip $_activeTripId');
    }
  });
}

void _stopHeartbeat() {
  _heartbeatTimer?.cancel();
  _heartbeatTimer = null;
}

Future<void> _confirmCashCollection() async {
  if (_activeTripId == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('No active trip found')),
    );
    return;
  }

  if (tripFareAmount == null || tripFareAmount! <= 0) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Trip fare not available. Please try again.')),
    );
    return;
  }

  try {
    print('💰 Confirming cash collection:');
    print('   Trip ID: $_activeTripId');
    print('   Driver ID: $driverId');
    print('   Fare: ₹$tripFareAmount');

    final response = await http.post(
      Uri.parse('$apiBase/api/trip/confirm-cash'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'tripId': _activeTripId,
        'driverId': driverId,
        'fare': tripFareAmount,
      }),
    );

    final data = jsonDecode(response.body);
    
    print('🔥 Cash collection response: $data');
    
    if (response.statusCode == 200 && data['success']) {
      // ✅ Clear socket service active trip
      _socketService.setActiveTrip(null);
      
      // ✅ STOP BACKGROUND SERVICE
      await TripBackgroundService.stopTripService();
      await WakelockPlus.disable();
      
      print('🔕 Background service stopped - app can sleep now');
      
      final fareBreakdown = data['fareBreakdown'];
      final walletInfo = data['wallet'];
      
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          backgroundColor: AppColors.background,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              Icon(Icons.check_circle, color: AppColors.success, size: 32),
              const SizedBox(width: 12),
              Expanded(child: Text('Cash Collected ✅', style: AppTextStyles.heading3)),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Divider(color: AppColors.divider),
                _buildFareRow('Trip Fare', fareBreakdown['tripFare'], bold: true),
                const SizedBox(height: 8),
                _buildFareRow(
                  'Platform Commission (${fareBreakdown['commissionPercentage']}%)',
                  fareBreakdown['commission'],
                  isNegative: true,
                  color: AppColors.warning,
                ),
                Divider(thickness: 2, color: AppColors.divider),
                _buildFareRow(
                  'Your Earning',
                  fareBreakdown['driverEarning'],
                  bold: true,
                  color: AppColors.success,
                ),
                const SizedBox(height: 16),
                Container(
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
                            '₹${walletInfo['totalEarnings'].toStringAsFixed(2)}',
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
                            '₹${walletInfo['pendingAmount'].toStringAsFixed(2)}',
                            style: AppTextStyles.body1.copyWith(color: AppColors.warning),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => WalletPage(driverId: driverId),
                  ),
                );
              },
              child: Text('View Wallet', style: AppTextStyles.button.copyWith(color: AppColors.primary)),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                
                // ✅ CRITICAL: Clear all trip state
                _clearActiveTrip();
                
                // ✅ Refresh wallet data
                _fetchWalletData();
                _fetchTodayEarnings();

                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Ready for next ride!'),
                    backgroundColor: Colors.green,
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.success,
                foregroundColor: AppColors.onPrimary,
              ),
              child: Text('Done', style: AppTextStyles.button.copyWith(color: AppColors.onPrimary)),
            ),
          ],
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(data['message'] ?? 'Failed to confirm cash collection')),
      );
    }
  } catch (e) {
    print('❌ Error confirming cash: $e');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Error: $e')),
    );
  }
}

  void _stopNotificationSound() async {
    await _audioPlayer.stop();
  }

  void _completeRide() {
    try {
      final String tripId = activeTripDetails?['tripId'] ?? '';
      if (tripId.isEmpty) {
        print('❌ Cannot complete ride: Missing ride ID');
        return;
      }
      _socketService.completeRide(driverId, tripId);
      print('✅ Called completeRide for tripId: $tripId');
      
      _clearActiveTrip();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ride completed successfully')),
      );
    } catch (e) {
      print('❌ Error completing ride: $e');
    }
  }

  void _cancelRide() {
    try {
      _clearActiveTrip();
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Ride cancelled')));
    } catch (e) {
      print('❌ Error cancelling ride: $e');
    }
  }

  Future<void> _requestLocationPermission() async {
    final status = await Permission.location.request();
    if (!status.isGranted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Location permission is required to use map.'),
        ),
      );
    }
  }

  Future<void> _getCurrentLocation() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      await Geolocator.openLocationSettings();
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Location permissions are denied')),
        );
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Location permissions are permanently denied'),
        ),
      );
      return;
    }

    final position = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );
    setState(() {
      _currentPosition = LatLng(position.latitude, position.longitude);
      _mapController?.animateCamera(CameraUpdate.newLatLng(_currentPosition!));
    });
  }

void acceptRide() async {
  if (currentRide == null) return;

  _stopNotificationSound();

  final String? tripId = (currentRide!['tripId'] ?? currentRide!['_id'])?.toString();
  if (tripId == null || tripId.isEmpty) {
    print('❌ No tripId found in currentRide: $currentRide');
    return;
  }

  final fare = currentRide!['fare'];
  final fareAmount = fare != null ? _parseDouble(fare) : null;

  print('✅ Driver accepting ride: $tripId with fare: $fareAmount');

  try {
    _socketService.socket.emit('driver:accept_trip', {
      'tripId': tripId,
      'driverId': driverId,
    });
    
    // ✅ Mark trip as active
    _socketService.setActiveTrip(tripId);
    
    // ✅ START BACKGROUND SERVICE
    await TripBackgroundService.startTripService(
      tripId: tripId,
      driverId: driverId,
      customerName: 'Customer', // Get from activeTripDetails if available
    );
    
    // ✅ Enable wake lock
    await WakelockPlus.enable();
    
    print('🔒 Background service started - app will stay alive');
    
  } catch (e) {
    print('❌ Error emitting driver:accept_trip: $e');
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Accept failed: $e')),
      );
    }
    return;
  }

  setState(() {
    _activeTripId = tripId;
    ridePhase = 'going_to_pickup';
    tripFareAmount = fareAmount;
    finalFareAmount = fareAmount;
  });

  _startHeartbeat();

  if (mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Ride Accepted! App will stay alive in background")),
    );
  }

  setState(() {
    rideRequests.removeWhere((req) {
      final id = (req['tripId'] ?? req['_id'])?.toString();
      return id == tripId;
    });
    currentRide = rideRequests.isNotEmpty ? rideRequests.first : null;
    if (currentRide != null) _playNotificationSound();
  });
}

  void _startLiveLocationUpdates() {
    _locationUpdateTimer?.cancel();
    
    _locationUpdateTimer = Timer.periodic(const Duration(seconds: 2), (timer) async {
      if (_currentPosition == null) return;
      final pos = await Geolocator.getCurrentPosition();
      _currentPosition = LatLng(pos.latitude, pos.longitude);
      _updateDriverStatusSocket();
      _sendLocationToBackend(pos.latitude, pos.longitude);
    });
  }

  Future<void> _drawRouteToCustomer() async {
    if (_currentPosition == null || _customerPickup == null) return;

    final url = Uri.parse(
      'https://maps.googleapis.com/maps/api/directions/json'
      '?origin=${_currentPosition!.latitude},${_currentPosition!.longitude}'
      '&destination=${_customerPickup!.latitude},${_customerPickup!.longitude}'
      '&key=AIzaSyB7VstS4RZlou2jyNgzkKePGqNbs2MyzYY',
    );

    List<LatLng> polylinePoints = [];

    try {
      final response = await http.get(url);
      if (response.statusCode != 200) {
        print("❌ Failed to get directions: ${response.statusCode}");
        return;
      }

      final data = jsonDecode(response.body);
      if (data['status'] != 'OK' || data['routes'].isEmpty) {
        print("❌ No routes found: ${data['status']}");
        return;
      }

      final encodedPolyline = data['routes'][0]['overview_polyline']['points'];
      polylinePoints = _decodePolyline(encodedPolyline);
    } catch (e) {
      print("❌ Error drawing route: $e");
      return;
    }

    setState(() {
      _polylines.clear();
      _polylines.add(
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
@override
void didChangeAppLifecycleState(AppLifecycleState state) {
  print('📱 App lifecycle changed: $state');
  
  switch (state) {
    case AppLifecycleState.paused:
      print('⏸️ App paused');
      if (_socketService.hasActiveTrip) {
        print('🔒 Keeping socket alive - active trip in progress');
      }
      break;
      
    case AppLifecycleState.resumed:
      print('▶️ App resumed');
      
      // Reconnect socket if needed
      if (!_socketService.isConnected) {
        print('🔄 Reconnecting socket...');
        _initSocketAndFCM();
      }
      
      // Refresh location
      _getCurrentLocation();
      
      // ✅ CHECK FOR ACTIVE TRIP ON RESUME
      Future.delayed(const Duration(seconds: 1), () {
        _checkAndResumeActiveTrip();
      });
      break;
      
    case AppLifecycleState.inactive:
      print('💤 App inactive');
      break;
      
    case AppLifecycleState.detached:
      print('🚪 App detached');
      break;
      
    default:
      break;
  }
}


@override
void dispose() {
  otpController.dispose();

  _cleanupTimer?.cancel();
  _locationUpdateTimer?.cancel();
  _heartbeatTimer?.cancel();
  _mapController?.dispose();
  _stopNotificationSound();

  // Only disconnect socket if no active trip (socket service already handles this guard)
  if (!_socketService.hasActiveTrip) {
    _socketService.disconnect();
    print('🔴 Socket disconnected - no active trip');
  } else {
    print('⚠️ Socket kept alive - active trip in progress');
  }

  WidgetsBinding.instance.removeObserver(this);
  super.dispose();
}

  void rejectRide() {
    if (currentRide == null) return;

    _stopNotificationSound();

    final String tripId =
        (currentRide!['tripId'] ?? currentRide!['_id'] ?? '').toString();

    _socketService.rejectRide(driverId, tripId);

    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text("Ride Rejected.")));

    setState(() {
      rideRequests.removeWhere((req) {
        final id = (req['tripId'] ?? req['_id'])?.toString();
        return id == tripId;
      });
      currentRide = rideRequests.isNotEmpty ? rideRequests.first : null;
      if (currentRide != null) _playNotificationSound();
    });
  }

@override
Widget build(BuildContext context) {
  return Scaffold(
    backgroundColor: AppColors.background,
    drawer: buildDrawer(),
    appBar: AppBar(
      backgroundColor: AppColors.background,
      elevation: 1,
      iconTheme: IconThemeData(color: AppColors.onSurface),
      title: Row(
        children: [
          Text(
            activeTripDetails != null
                ? "En Route to Customer"
                : (isOnline ? "ON DUTY" : "OFF DUTY"),
            style: AppTextStyles.heading3.copyWith(
              color: activeTripDetails != null
                  ? AppColors.primary
                  : (isOnline ? AppColors.success : AppColors.error),
            ),
          ),
          const SizedBox(width: 10),
          if (activeTripDetails == null)
            Switch(
              value: isOnline,
              activeColor: AppColors.primary,
              inactiveThumbColor: AppColors.onSurfaceSecondary,
              onChanged: (value) async {
                if (!value && _socketService.hasActiveTrip) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Cannot go offline while a trip is active. Complete the trip first.'),
                      backgroundColor: Colors.orange,
                    ),
                  );
                  setState(() => isOnline = true);
                  return;
                }

                setState(() => isOnline = value);

                final prefs = await SharedPreferences.getInstance();
                await prefs.setBool('isOnline', isOnline);

                await Future.delayed(const Duration(milliseconds: 100));
                _updateDriverStatusSocket();

                print('📘 Switch changed: ${value ? 'ONLINE' : 'OFFLINE'}');
              },
            ),
        ],
      ),
      actions: activeTripDetails == null
          ? [
              IconButton(
                icon: Icon(Icons.location_on_outlined, color: AppColors.onSurface),
                onPressed: () {},
              ),
              IconButton(
                icon: Icon(Icons.notifications_none, color: AppColors.onSurface),
                onPressed: () {},
              ),
              const SizedBox(width: 10),
            ]
          : null,
    ),
    body: Stack(
      children: [
        if (activeTripDetails != null)
          buildActiveTripUI(activeTripDetails!)
        else if (isOnline)
          buildGoogleMap()
        else
          buildOffDutyUI(),

        // ✅ ADD THE RIDE QUEUE OVERLAY HERE
        _buildRideQueueOverlay(),
      ],
    ),
  );
}
  Widget _buildActionButtons(Map<String, dynamic> trip) {
  const double proximityThreshold = 200.0;

  switch (ridePhase) {
    case 'going_to_pickup':
      return Column(
        children: [
          // Primary Action - Navigate
          _buildPrimaryActionButton(
            icon: Icons.navigation_rounded,
            label: 'Start Navigation',
            onPressed: () => _launchGoogleMaps(
              trip['pickup']['lat'],
              trip['pickup']['lng'],
            ),
            gradient: LinearGradient(
              colors: [AppColors.primary, AppColors.primary.withOpacity(0.8)],
            ),
          ),
          
          const SizedBox(height: 12),
          
          // Secondary Action - Arrived
          _buildSecondaryActionButton(
            icon: Icons.check_circle_outline,
            label: "I've Arrived",
            onPressed: () {
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

              if (distance <= proximityThreshold) {
                _goToPickup();
              } else {
                _showProximityWarning(distance, 'pickup location');
              }
            },
          ),
          
          const SizedBox(height: 16),
          
          // Distance Info Card
          _buildInfoCard(
            icon: Icons.info_outline,
            text: 'Tap "I\'ve Arrived" when you reach the pickup location',
            color: AppColors.primary,
          ),
        ],
      );

    case 'at_pickup':
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // OTP Header Card
          Container(
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
          ),
          
          const SizedBox(height: 20),
          
          // OTP Input Field
          TextField(
            controller: otpController,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            maxLength: 4,
            autofocus: true,
            style: AppTextStyles.heading1.copyWith(
              letterSpacing: 24,
              fontSize: 36,
              fontWeight: FontWeight.bold,
            ),
            decoration: InputDecoration(
              hintText: '- - - -',
              hintStyle: TextStyle(
                color: AppColors.onSurfaceSecondary.withOpacity(0.3),
                letterSpacing: 24,
              ),
              counterText: "",
              filled: true,
              fillColor: AppColors.surface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: AppColors.divider, width: 2),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: AppColors.primary, width: 2),
              ),
              contentPadding: const EdgeInsets.symmetric(vertical: 24),
            ),
            onChanged: (value) {
              if (value.length == 4) {
                // Auto-submit when 4 digits entered
                FocusScope.of(context).unfocus();
              }
            },
          ),
          
          const SizedBox(height: 20),
          
          // Start Ride Button
          _buildPrimaryActionButton(
            icon: Icons.play_arrow_rounded,
            label: 'Start Ride',
            onPressed: _startRide,
            gradient: LinearGradient(
              colors: [AppColors.success, AppColors.success.withOpacity(0.8)],
            ),
          ),
        ],
      );
        
    case 'going_to_drop':
      return Column(
        children: [
          // Primary Action - Navigate to Drop
          _buildPrimaryActionButton(
            icon: Icons.navigation_rounded,
            label: 'Navigate to Drop Location',
            onPressed: () => _launchGoogleMaps(
              trip['drop']['lat'],
              trip['drop']['lng'],
            ),
            gradient: LinearGradient(
              colors: [AppColors.primary, AppColors.primary.withOpacity(0.8)],
            ),
          ),
          
          const SizedBox(height: 12),
          
          // Secondary Action - Complete Ride
          _buildSecondaryActionButton(
            icon: Icons.flag_outlined,
            label: 'Complete Ride',
            onPressed: () {
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

              if (distance <= proximityThreshold) {
                _completeRideNew();
              } else {
                _showProximityWarning(distance, 'drop location');
              }
            },
          ),
          
          const SizedBox(height: 16),
          
          // Ride in Progress Info
          _buildInfoCard(
            icon: Icons.directions_car,
            text: 'Take customer to destination safely',
            color: AppColors.success,
          ),
        ],
      );
        
    case 'completed':
      return Column(
        children: [
          // Success Header
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppColors.success.withOpacity(0.15),
                  AppColors.success.withOpacity(0.05),
                ],
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.success, width: 2),
            ),
            child: Column(
              children: [
                Icon(
                  Icons.check_circle,
                  color: AppColors.success,
                  size: 64,
                ),
                const SizedBox(height: 12),
                Text(
                  "Trip Completed Successfully!",
                  style: AppTextStyles.heading3.copyWith(
                    color: AppColors.success,
                    fontSize: 20,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  "Collect cash from customer",
                  style: AppTextStyles.body2,
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 20),
          
          // Fare Display
          Container(
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
                    Text(
                      "Total Fare",
                      style: AppTextStyles.body2,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      "To Collect",
                      style: AppTextStyles.caption,
                    ),
                  ],
                ),
                Text(
                  "₹${finalFareAmount?.toStringAsFixed(2) ?? '0.00'}",
                  style: AppTextStyles.heading1.copyWith(
                    color: AppColors.success,
                    fontSize: 36,
                  ),
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 20),
          
          // Confirm Cash Collection Button
          _buildPrimaryActionButton(
            icon: Icons.payments_rounded,
            label: 'Cash Collected - Complete',
            onPressed: _confirmCashCollection,
            gradient: LinearGradient(
              colors: [AppColors.success, AppColors.success.withOpacity(0.8)],
            ),
          ),
          
          const SizedBox(height: 12),
          
          // Warning Card
          _buildInfoCard(
            icon: Icons.warning_amber_rounded,
            text: 'Confirm only after receiving payment from customer',
            color: AppColors.warning,
          ),
        ],
      );
        
    default:
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
            Text(
              'Loading trip details...',
              style: AppTextStyles.body2,
            ),
          ],
        ),
      );
  }
}

// ✅ NEW: Primary Action Button Widget
Widget _buildPrimaryActionButton({
  required IconData icon,
  required String label,
  required VoidCallback onPressed,
  Gradient? gradient,
}) {
  return Container(
    width: double.infinity,
    decoration: BoxDecoration(
      gradient: gradient ?? LinearGradient(
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

// ✅ NEW: Secondary Action Button Widget
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

// ✅ NEW: Info Card Widget
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

// ✅ NEW: Status Card for Location/Proximity Warnings
void _showStatusCard({
  required IconData icon,
  required String title,
  required String message,
  required Color color,
  Duration duration = const Duration(seconds: 3),
}) {
  ScaffoldMessenger.of(context).clearSnackBars();
  ScaffoldMessenger.of(context).showSnackBar(
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

// ✅ NEW: Proximity Warning Dialog
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
            child: Text(
              'Not at Location',
              style: AppTextStyles.heading3,
            ),
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
Widget _buildRideQueueOverlay() {
  if (rideRequests.isEmpty) return const SizedBox.shrink();

  return Positioned(
    top: 0,
    left: 0,
    right: 0,
    bottom: 0,
    child: Container(
      color: AppColors.background, // White/theme background
      child: Column(
        children: [
          // Header
          Container(
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
                  Icon(Icons.notifications_active, color: AppColors.onPrimary, size: 28),
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
                          "${rideRequests.length} ${rideRequests.length == 1 ? 'request' : 'requests'} waiting",
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
                      '${rideRequests.length}',
                      style: AppTextStyles.heading3.copyWith(
                        color: AppColors.primary,
                        fontSize: 18,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Scrollable queue
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: rideRequests.length,
              itemBuilder: (context, index) {
                final request = rideRequests[index];
                return RideRequestCard(
  request: request,
  position: index,
  driverLocation: _currentPosition, // ✅ ADD
  perRideIncentive: perRideIncentive, // ✅ ADD
  perRideCoins: perRideCoins, // ✅ ADD
  onAccept: () {
    setState(() {
      currentRide = request;
    });
    acceptRide();
  },
  onReject: () {
    rejectRide();
  },
);
              },
            ),
          ),
        ],
      ),
    ),
  );
}


  Widget buildActiveTripUI(Map<String, dynamic> tripData) {
    return Stack(
      children: [
        GoogleMap(
          initialCameraPosition: CameraPosition(
            target: _currentPosition ?? const LatLng(17.385044, 78.486671),
            zoom: 14,
          ),
          myLocationEnabled: true,
          myLocationButtonEnabled: true,
          markers: _markers,
          polylines: _polylines,
          onMapCreated: (controller) {
            _mapController = controller;
            _googleMapController = controller;
          },
        ),
        _buildCustomerCard(tripData['customer'], tripData['trip']),
      ],
    );
  }

  Widget _buildCustomerCard(Map<String, dynamic> customer, Map<String, dynamic> trip) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(32),
            topRight: Radius.circular(32),
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.onSurface.withOpacity(0.2),
              blurRadius: 20,
              offset: const Offset(0, -5),
            )
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 35,
                    backgroundImage: customer['photoUrl'] != null && customer['photoUrl'].isNotEmpty
                        ? NetworkImage(customer['photoUrl'])
                        : const AssetImage('assets/default_avatar.png') as ImageProvider,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          customer['name'] ?? 'Customer',
                          style: AppTextStyles.heading3,
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(Icons.star, color: AppColors.warning, size: 18),
                            const SizedBox(width: 4),
                            Text(
                              (customer['rating'] ?? 5.0).toString(),
                              style: AppTextStyles.body1,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  _buildCircleButton(
                    Icons.call,
                    () => _makePhoneCall(customer['phone']?.toString() ?? ''),
                  ),
                  const SizedBox(width: 12),
                  _buildCircleButton(
                    Icons.chat_bubble_outline,
                    () => _openChat(customer, trip),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Icon(Icons.location_on, color: AppColors.primary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('PICKUP LOCATION', style: AppTextStyles.caption),
                              const SizedBox(height: 4),
                              Text(
                                trip['pickup']['address'] ?? 'Customer Location',
                                style: AppTextStyles.body1,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _buildActionButtons(trip),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
Future<void> _payCommissionViaUPI() async {
  final pendingAmount = _parseDouble(walletData?['pendingAmount']) ?? 0.0;
  
  if (pendingAmount <= 0) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('No pending commission to pay'),
        backgroundColor: AppColors.warning,
      ),
    );
    return;
  }

  // UPI payment details
  const upiId = '8341132728@mbk';
  const receiverName = 'Platform Commission';
  final amount = pendingAmount.toStringAsFixed(2);
  final transactionNote = 'Commission Payment - Driver: $driverId';

  // Create UPI payment URL
  final upiUrl = 'upi://pay?pa=$upiId&pn=${Uri.encodeComponent(receiverName)}&am=$amount&cu=INR&tn=${Uri.encodeComponent(transactionNote)}';

  try {
    final uri = Uri.parse(upiUrl);
    
    if (await canLaunchUrl(uri)) {
      await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      
      // Show confirmation dialog after payment attempt
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) {
          _showPaymentConfirmationDialog(pendingAmount);
        }
      });
    } else {
      // Fallback: Show UPI ID for manual payment
      _showManualPaymentDialog(upiId, pendingAmount);
    }
  } catch (e) {
    print('❌ Error launching UPI: $e');
    _showManualPaymentDialog(upiId, pendingAmount);
  }
}
Future<void> _clearDriverStateOnBackend() async {
  try {
    print('🧹 Clearing driver state on backend...');
    
    final response = await http.post(
      Uri.parse('$apiBase/api/driver/clear-state'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'driverId': widget.driverId,
      }),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      if (data['success']) {
        print('✅ Backend state cleared successfully');
      }
    }
  } catch (e) {
    print('⚠️ Error clearing backend state: $e');
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
          child: Text('Not Yet', style: AppTextStyles.button.copyWith(color: AppColors.error)),
        ),
        ElevatedButton(
          onPressed: () {
            Navigator.pop(context);
            // Refresh wallet data
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Payment recorded. It will be verified shortly.'),
                backgroundColor: AppColors.success,
              ),
            );
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.success,
          ),
          child: Text('Yes, Paid', style: AppTextStyles.button.copyWith(color: AppColors.onPrimary)),
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
          Expanded( // ✅ ADD Expanded
            child: Text('Pay Manually', style: AppTextStyles.heading3),
          ),
        ],
      ),
      content: SingleChildScrollView( // ✅ ADD ScrollView
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
                  // ✅ FIXED: UPI ID Row
                  Row(
                    children: [
                      Expanded( // ✅ ADD Expanded
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
                        icon: Icon(Icons.copy, size: 20, color: AppColors.primary),
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: upiId));
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('UPI ID copied!'),
                              backgroundColor: AppColors.success,
                            ),
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
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: AppColors.primary, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Open any UPI app and pay to this UPI ID',
                      style: AppTextStyles.body2.copyWith(
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(
            'Cancel',
            style: AppTextStyles.button.copyWith(color: AppColors.onSurfaceSecondary),
          ),
        ),
        ElevatedButton(
          onPressed: () {
            Navigator.pop(context);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('After payment, verification takes 24 hours'),
                backgroundColor: AppColors.success,
              ),
            );
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
          ),
          child: Text('Got It', style: AppTextStyles.button.copyWith(color: AppColors.onPrimary)),
        ),
      ],
    ),
  );
}

  Future<void> _makePhoneCall(String phoneNumber) async {
    if (phoneNumber.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Phone number not available')),
      );
      return;
    }
    final Uri phoneUri = Uri(scheme: 'tel', path: phoneNumber);
    if (await canLaunchUrl(phoneUri)) {
      await launchUrl(phoneUri);
    }
  }

  void _openChat(Map<String, dynamic> customer, Map<String, dynamic> trip) {
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (context) => ChatPage(
        tripId: activeTripDetails!['tripId'],
        senderId: widget.driverId,
        receiverId: customer['id'],
        receiverName: customer['name'] ?? 'Customer',
        isDriver: true, // ✅ DRIVER SIDE
      ),
    ),
  );
}
  Widget _buildCircleButton(IconData icon, VoidCallback onPressed) {
    return CircleAvatar(
      backgroundColor: AppColors.surface,
      child: IconButton(
        icon: Icon(icon, color: AppColors.onSurface),
        onPressed: onPressed,
      ),
    );
  }

  Widget buildGoogleMap() {
    LatLng center = _currentPosition != null
        ? LatLng(_currentPosition!.latitude, _currentPosition!.longitude)
        : const LatLng(17.385044, 78.486671);

    return GoogleMap(
      initialCameraPosition: CameraPosition(
        target: center,
        zoom: 14,
      ),
      myLocationEnabled: true,
      myLocationButtonEnabled: true,
      zoomControlsEnabled: false,
      markers: _markers,
      polylines: _polylines,
      onMapCreated: (controller) {
        _googleMapController = controller;
        _mapController = controller;
      },
    );
  }

  Widget buildOffDutyUI() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        buildEarningsCard(),
        const SizedBox(height: 16),
              buildWalletCard(), 
               const SizedBox(height: 16),
      GestureDetector(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => DriverRideHistoryPage(driverId: driverId),
            ),
          );
        },
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                AppColors.success,
                AppColors.success.withOpacity(0.8),
              ],
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
                child: Icon(
                  Icons.history,
                  color: AppColors.onPrimary,
                  size: 28,
                ),
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
              Icon(
                Icons.arrow_forward_ios,
                color: AppColors.onPrimary,
                size: 20,
              ),
            ],
          ),
        ),
      ),// ✅ CHANGED FROM buildPerformanceCard()

        const SizedBox(height: 30),
        Image.asset('assets/images/mobile.png', height: 140),
        const SizedBox(height: 20),
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

  Widget _buildFareRow(String label, dynamic amount, {
    bool bold = false,
    bool isNegative = false,
    Color? color,
  }) {
    final displayAmount = amount is num ? amount.toDouble() : double.tryParse(amount.toString()) ?? 0.0;
    
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
            style: (bold ? AppTextStyles.heading3 : AppTextStyles.body1).copyWith(
              color: color ?? AppColors.onSurface,
            ),
          ),
        ],
      ),
    );
  }

Widget buildDrawer() {
  return Drawer(
    backgroundColor: AppColors.background,
    child: ListView(
      padding: EdgeInsets.zero,
      children: [
        DrawerHeader(
          decoration: BoxDecoration(
            color: AppColors.primary,
          ),
          child: InkWell(
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => DriverProfilePage(driverId: driverId),
                ),
              );
            },
            child: Row(
              children: [
                const CircleAvatar(
                  backgroundImage: AssetImage('assets/profile.jpg'),
                  radius: 30,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        "My Profile",
                        style: AppTextStyles.heading3.copyWith(color: AppColors.onPrimary),
                      ),
                      Text(
                        "Tap to view details",
                        style: AppTextStyles.caption.copyWith(color: AppColors.onPrimary.withOpacity(0.8)),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.arrow_forward_ios,
                  color: AppColors.onPrimary,
                  size: 16,
                ),
              ],
            ),
          ),
        ),
        
        buildDrawerItem(
          Icons.account_balance_wallet,
          "Earnings",
          "Transfer Money to Bank, History",
          iconColor: AppColors.primary,
          onTap: () {
            Navigator.pop(context);
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => WalletPage(driverId: driverId),
              ),
            );
          },
        ),
        
        buildDrawerItem(
          Icons.history,
          "Ride History",
          "View completed rides & earnings",
          iconColor: AppColors.success,
          onTap: () {
            Navigator.pop(context);
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => DriverRideHistoryPage(driverId: driverId),
              ),
            );
          },
        ),

        // ✅ UPDATED: Incentives with navigation
        buildDrawerItem(
          Icons.card_giftcard,
          "Rewards & Incentives",
          "Earn money and coins per ride",
          iconColor: Color(0xFFFFD700), // Gold color for incentives
          onTap: () {
            Navigator.pop(context);
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => IncentivesPage(driverId: driverId),
              ),
            );
          },
        ),
        
        buildDrawerItem(
          Icons.local_offer,
          "Rewards & Benefits",
          "Insurance and Discounts",
          iconColor: AppColors.primary,
        ),
        
        Divider(color: AppColors.divider),
        
        buildDrawerItem(
          Icons.view_module,
          "Service Manager",
          "Food Delivery & more",
          iconColor: AppColors.primary,
        ),
        
        buildDrawerItem(
          Icons.map,
          "Demand Planner",
          "Past High Demand Areas",
          iconColor: AppColors.primary,
        ),
        
        buildDrawerItem(
          Icons.headset_mic,
          "Help",
          "Support, Accident Insurance",
          iconColor: AppColors.primary,
        ),
        
        Padding(
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
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.primary,
                  ),
                  child: Text("Refer Now", style: AppTextStyles.button.copyWith(color: AppColors.primary, fontSize: 14)),
                ),
              ],
            ),
          ),
        ),
        
        if (widget.vehicleType.toLowerCase() == 'car')
          ListTile(
            title: Text("Accept Long Trips", style: AppTextStyles.body1),
            trailing: Switch(
              activeColor: AppColors.primary,
              value: acceptsLong,
              onChanged: isOnline
                  ? (value) async {
                      setState(() => acceptsLong = value);
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.setBool('acceptsLong', acceptsLong);
                      _updateDriverStatusSocket();
                    }
                  : null,
            ),
          ),
      ],
    ),
  );
}
  Widget buildDrawerItem(
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

  void _updateDriverStatusSocket() async {
  final lat = _currentPosition?.latitude ?? 0.0;
  final lng = _currentPosition?.longitude ?? 0.0;

  // persist online/offline flag
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString('lastLat', lat.toString());
await prefs.setString('lastLng', lng.toString());
  await prefs.setBool('isOnline', isOnline);

  // persist vehicleType & acceptsLong (if changed somewhere)
  await prefs.setString('vehicleType', widget.vehicleType);
  await prefs.setBool('acceptsLong', acceptsLong);

  _socketService.updateDriverStatus(
    driverId,
    isOnline,
    lat,
    lng,
    widget.vehicleType,
    fcmToken: driverFcmToken,
    profileData: null,
  );

  print('🚗 Driver status updated: ${isOnline ? 'ONLINE' : 'OFFLINE'}');
}

  
  Widget buildEarningsCard() {
  // ✅ USE _parseDouble() to safely convert int/double
  final todayTotal = _parseDouble(todayEarnings?['totalFares']) ?? 0.0;
  final todayCommission = _parseDouble(todayEarnings?['totalCommission']) ?? 0.0;
  final todayNet = _parseDouble(todayEarnings?['netEarnings']) ?? 0.0;
  final tripsCount = (todayEarnings?['tripsCompleted'] as num?)?.toInt() ?? 0;
  
  return GestureDetector(
    onTap: _fetchTodayEarnings, // Tap to refresh
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
          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(Icons.calendar_today, 
                    color: AppColors.primary, 
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    "Today's Earnings",
                    style: AppTextStyles.heading3,
                  ),
                ],
              ),
              if (isLoadingToday)
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
                  ),
                )
              else
                Icon(Icons.refresh, 
                  color: AppColors.onSurfaceSecondary, 
                  size: 20,
                ),
            ],
          ),
          
          const SizedBox(height: 16),
          
          // Total Fares (Big Number)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Total Fares',
                    style: AppTextStyles.body2,
                  ),
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
              // Trips Badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.primary.withOpacity(0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.local_taxi, 
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
          
          // Divider
          Container(
            height: 1,
            color: AppColors.divider,
          ),
          
          const SizedBox(height: 12),
          
          // Breakdown
          Row(
            children: [
              Expanded(
                child: _buildEarningsBreakdownItem(
                  'Commission',
                  todayCommission,
                  Icons.percent,
                  AppColors.warning,
                  isNegative: true,
                ),
              ),
              Container(
                width: 1,
                height: 40,
                color: AppColors.divider,
              ),
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
// Helper widget for breakdown items
Widget _buildEarningsBreakdownItem(
  String label, 
  double amount, 
  IconData icon, 
  Color color, 
  {bool isNegative = false}
) {
  return Column(
    children: [
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 4),
          Text(
            label,
            style: AppTextStyles.caption,
          ),
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
 Widget buildWalletCard() {
  // ✅ USE _parseDouble() to safely convert int/double
  final totalEarnings = _parseDouble(walletData?['totalEarnings']) ?? 0.0;
  final pendingAmount = _parseDouble(walletData?['pendingAmount']) ?? 0.0;
  
  return GestureDetector(
    onTap: _fetchWalletData, // ✅ ADD TAP TO REFRESH
    child: Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.primary,
            AppColors.primary.withOpacity(0.7),
          ],
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
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          // Wallet Balance Section
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
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '₹${totalEarnings.toStringAsFixed(2)}',
                    style: AppTextStyles.heading2.copyWith(
                      color: AppColors.onPrimary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              // ✅ ADD LOADING INDICATOR
              if (isLoadingWallet)
                SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(AppColors.onPrimary),
                  ),
                )
              else
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.onPrimary.withOpacity(0.2),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.account_balance_wallet,
                    color: AppColors.onPrimary,
                    size: 28,
                  ),
                ),
            ],
          ),
          
          const SizedBox(height: 16),
          
          // Divider
          Container(
            height: 1,
            color: AppColors.onPrimary.withOpacity(0.2),
          ),
          
          const SizedBox(height: 16),
          
          // Pending Commission Section
          Container(
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
                
                // ✅ PAYMENT BUTTON (only show if pending > 0)
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
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => WalletPage(driverId: driverId),
                            ),
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.onPrimary.withOpacity(0.3),
                          foregroundColor: AppColors.onPrimary,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          elevation: 0,
                        ),
                        child: Icon(Icons.arrow_forward, size: 20),
                      ),
                    ],
                  ),
                ] else
                  ElevatedButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => WalletPage(driverId: driverId),
                        ),
                      );
                    },
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
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                      elevation: 0,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}}
class RideRequestCard extends StatefulWidget {
  final Map<String, dynamic> request;
  final VoidCallback onAccept;
  final VoidCallback onReject;
  final int position;
  final LatLng? driverLocation;
  final double perRideIncentive;
  final int perRideCoins;

  const RideRequestCard({
    Key? key,
    required this.request,
    required this.onAccept,
    required this.onReject,
    required this.position,
    this.driverLocation,
    this.perRideIncentive = 5.0,
    this.perRideCoins = 10,
  }) : super(key: key);

  @override
  _RideRequestCardState createState() => _RideRequestCardState();
}

class _RideRequestCardState extends State<RideRequestCard> {
  late int _secondsRemaining;
  Timer? _timer;
  double? _pickupDistance;
  double? _tripDistance;
  bool _calculatingDistances = true;

  @override
  void initState() {
    super.initState();
    _secondsRemaining = 10;
    _startTimer();
    _calculateDistances();
  }

  void _calculateDistances() async {
    try {
      final pickup = widget.request['pickup'];
      final drop = widget.request['drop'];
      
      if (pickup != null && drop != null) {
        final pickupLat = pickup['lat'];
        final pickupLng = pickup['lng'];
        final dropLat = drop['lat'];
        final dropLng = drop['lng'];
        
        if (widget.driverLocation != null) {
          _pickupDistance = Geolocator.distanceBetween(
            widget.driverLocation!.latitude,
            widget.driverLocation!.longitude,
            pickupLat,
            pickupLng,
          ) / 1000;
        }
        
        _tripDistance = Geolocator.distanceBetween(
          pickupLat,
          pickupLng,
          dropLat,
          dropLng,
        ) / 1000;
        
        if (mounted) {
          setState(() {
            _calculatingDistances = false;
          });
        }
      }
    } catch (e) {
      print('Error calculating distances: $e');
      if (mounted) {
        setState(() {
          _calculatingDistances = false;
        });
      }
    }
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_secondsRemaining > 0) {
        if (mounted) {
          setState(() {
            _secondsRemaining--;
          });
        }
      } else {
        timer.cancel();
        if (mounted) {
          widget.onReject();
        }
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  // ✅ EXTRACT MAIN AREA FROM FULL ADDRESS
  String _extractMainArea(String? fullAddress) {
    if (fullAddress == null || fullAddress.isEmpty) return 'Location';
    
    final parts = fullAddress.split(',');
    
    if (parts.length >= 2) {
      return '${parts[0].trim()}, ${parts[1].trim()}';
    } else if (parts.length == 1) {
      return parts[0].trim().length > 40 
          ? '${parts[0].trim().substring(0, 40)}...'
          : parts[0].trim();
    }
    
    return fullAddress.length > 40 
        ? '${fullAddress.substring(0, 40)}...'
        : fullAddress;
  }

  @override
  Widget build(BuildContext context) {
    final fare = widget.request['fare'];
    final fareAmount = fare != null ? (fare is double ? fare : double.tryParse(fare.toString())) : null;
    
    const platformCommission = 0.12;
    final driverBaseEarning = fareAmount != null ? fareAmount * (1 - platformCommission) : null;
    final totalDriverGets = driverBaseEarning != null ? driverBaseEarning + widget.perRideIncentive : null;

    final pickupMainArea = _extractMainArea(widget.request['pickup']?['address']);
    final dropMainArea = _extractMainArea(widget.request['drop']?['address']);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _secondsRemaining <= 3 ? AppColors.error : AppColors.primary,
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: (_secondsRemaining <= 3 ? AppColors.error : AppColors.primary).withOpacity(0.2),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // Header with timer
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: (_secondsRemaining <= 3 ? AppColors.error : AppColors.primary).withOpacity(0.1),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(14),
                topRight: Radius.circular(14),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(Icons.local_taxi, color: AppColors.primary, size: 18),
                    const SizedBox(width: 8),
                    Text(
                      "New Ride",
                      style: AppTextStyles.body1.copyWith(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: _secondsRemaining <= 3 ? AppColors.error : AppColors.warning,
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
          ),

          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              children: [
                // ✅ DISTANCE INFO - BIGGER TEXT
                if (!_calculatingDistances && (_pickupDistance != null || _tripDistance != null))
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), // ✅ Increased padding
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.divider),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (_pickupDistance != null) ...[
                          Icon(Icons.my_location, color: AppColors.primary, size: 18), // ✅ Increased from 14
                          const SizedBox(width: 6), // ✅ Increased from 4
                          Text(
                            '${_pickupDistance!.toStringAsFixed(1)} km',
                            style: GoogleFonts.plusJakartaSans( // ✅ Using GoogleFonts
                              fontSize: 14, // ✅ Increased from 11
                              fontWeight: FontWeight.w700, // ✅ Made bolder
                              color: AppColors.primary,
                            ),
                          ),
                        ],
                        if (_pickupDistance != null && _tripDistance != null) ...[
                          const SizedBox(width: 12), // ✅ Increased from 8
                          Container(width: 1.5, height: 18, color: AppColors.divider), // ✅ Bigger divider
                          const SizedBox(width: 12), // ✅ Increased from 8
                        ],
                        if (_tripDistance != null) ...[
                          Icon(Icons.route, color: AppColors.success, size: 18), // ✅ Increased from 14
                          const SizedBox(width: 6), // ✅ Increased from 4
                          Text(
                            '${_tripDistance!.toStringAsFixed(1)} km trip',
                            style: GoogleFonts.plusJakartaSans( // ✅ Using GoogleFonts
                              fontSize: 14, // ✅ Increased from 11
                              fontWeight: FontWeight.w700, // ✅ Made bolder
                              color: AppColors.success,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                
                // PICKUP ADDRESS
                Row(
                  children: [
                    Icon(Icons.location_on, color: AppColors.success, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        pickupMainArea,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: AppColors.onSurface,
                          height: 1.3,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                
                const SizedBox(height: 8),
                
                // DROP ADDRESS
                Row(
                  children: [
                    Icon(Icons.flag, color: AppColors.error, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        dropMainArea,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: AppColors.onSurface,
                          height: 1.3,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                
                const SizedBox(height: 16),
                
                // ✅ BIG FARE NUMBER
                if (totalDriverGets != null) ...[
                  Text(
                    '₹${totalDriverGets.toStringAsFixed(0)}',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 48,
                      fontWeight: FontWeight.w900,
                      color: AppColors.success,
                      height: 1,
                    ),
                  ),
                  
                  const SizedBox(height: 4), // ✅ Reduced spacing
                  
                  // ✅ "ADDED" LABEL
                  Text(
                    'Added',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.onSurfaceSecondary,
                      letterSpacing: 0.5,
                    ),
                  ),
                  
                  const SizedBox(height: 10), // ✅ Spacing before badges
                  
                  // ✅ INCENTIVE BADGES
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Cash Incentive Badge
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppColors.success.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: AppColors.success.withOpacity(0.3)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.attach_money, color: AppColors.success, size: 16),
                            Text(
                              '+₹${widget.perRideIncentive.toStringAsFixed(0)}',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: AppColors.success,
                              ),
                            ),
                          ],
                        ),
                      ),
                      
                      const SizedBox(width: 10),
                      
                      // Coins Badge
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppColors.gold.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: AppColors.gold.withOpacity(0.3)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.monetization_on, color: AppColors.gold, size: 16),
                            Text(
                              '+${widget.perRideCoins}',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: AppColors.gold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
                
                const SizedBox(height: 16),
                
                // Action Buttons
                Row(
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
                        icon: Icon(Icons.check_circle, size: 18),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.success,
                          foregroundColor: AppColors.onPrimary,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          elevation: 3,
                        ),
                        onPressed: widget.onAccept,
                        label: Text(
                          "Accept",
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: AppColors.onPrimary,
                          ),
                        ),
                      ),
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
}

  // ✅ COMPACT LOCATION WIDGET
  Widget _buildCompactLocation(IconData icon, Color color, String label, String address) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: color, size: 14),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: AppTextStyles.caption.copyWith(
                  color: color,
                  fontWeight: FontWeight.bold,
                  fontSize: 9,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                address,
                style: AppTextStyles.caption.copyWith(
                  fontSize: 11,
                  height: 1.2,
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


class _CountdownTimer extends StatefulWidget {
  final Duration duration;
  final VoidCallback onComplete;

  const _CountdownTimer({
    Key? key,
    required this.duration,
    required this.onComplete,
  }) : super(key: key);

  @override
  _CountdownTimerState createState() => _CountdownTimerState();
}

class _CountdownTimerState extends State<_CountdownTimer> {
  late int _secondsRemaining;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _secondsRemaining = widget.duration.inSeconds;
    _startTimer();
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_secondsRemaining > 0) {
        setState(() {
          _secondsRemaining--;
        });
      } else {
        timer.cancel();
        widget.onComplete();
      }
    });
  }

  @override
  void dispose() {
    TripBackgroundService.stopTripService();
  WakelockPlus.disable();
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: _secondsRemaining <= 3 
            ? AppColors.error.withOpacity(0.2) 
            : AppColors.warning.withOpacity(0.2),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: _secondsRemaining <= 3 ? AppColors.error : AppColors.warning,
          width: 2,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.timer,
            color: _secondsRemaining <= 3 ? AppColors.error : AppColors.warning,
            size: 16,
          ),
          const SizedBox(width: 4),
          Text(
            '${_secondsRemaining}s',
            style: AppTextStyles.caption.copyWith(
              color: _secondsRemaining <= 3 ? AppColors.error : AppColors.warning,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}