import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:logging/logging.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'firebase_options.dart';
import 'package:drivergoo/screens/splash_screen.dart';
import 'package:drivergoo/services/background_service.dart';
import 'package:drivergoo/services/local_notification_service.dart';

/// =====================================================
/// � DEBUG HELPER
/// =====================================================
void logDebug(String message) {
  if (kDebugMode) {
    debugPrint(message);
  }
}

void logInfo(String message) {
  if (kDebugMode) {
    debugPrint('ℹ️ $message');
  }
}

/// =====================================================
/// �🔔 FCM BACKGROUND MESSAGE HANDLER
/// =====================================================
/// NOTE: This runs in a separate isolate - Method Channels DON'T WORK here!
/// The NATIVE MyFirebaseMessagingService.kt handles overlay display.
/// This is just for logging/fallback notification.
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  debugPrint('');
  debugPrint('=' * 70);
  debugPrint('🔔 BACKGROUND FCM (Dart Handler)');
  debugPrint('   Message ID: ${message.messageId}');
  debugPrint('   Data: ${message.data}');
  debugPrint('=' * 70);
  debugPrint('');

  // NOTE: Native MyFirebaseMessagingService.kt will show the overlay
  // This Dart handler is just for logging. The native code runs first.

  if (message.data.containsKey('tripId') ||
      message.data['type'] == 'TRIP_REQUEST') {
    debugPrint('🚕 Trip request detected - Native overlay should be showing');
  }
}

/// =====================================================
/// 🌍 GLOBAL NAVIGATOR KEY
/// =====================================================
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

/// =====================================================
/// 📢 OVERLAY CHANNEL
/// =====================================================
const MethodChannel overlayChannel = MethodChannel('overlay_service');

/// =====================================================
/// 🔔 GLOBAL NOTIFICATION EVENT BUS
/// =====================================================
class NotificationEventBus {
  static final StreamController<void> _controller =
      StreamController<void>.broadcast();

  static Stream<void> get stream => _controller.stream;

  static void refresh() {
    if (!_controller.isClosed) {
      _controller.add(null);
    }
  }

  static void dispose() {
    _controller.close();
  }
}

/// =====================================================
/// 🔋 Battery optimization exemption
/// =====================================================
Future<void> requestBatteryOptimizationExemption() async {
  if (Platform.isAndroid) {
    await Permission.ignoreBatteryOptimizations.request();
  }
}

/// =====================================================
/// 📱 Request Overlay Permission
/// =====================================================
Future<bool> checkAndRequestOverlayPermission() async {
  if (!Platform.isAndroid) return true;

  try {
    final hasPermission = await overlayChannel.invokeMethod('checkPermission');
    debugPrint('📱 Overlay permission: $hasPermission');
    return hasPermission == true;
  } catch (e) {
    debugPrint('⚠️ Error checking overlay permission: $e');
    return false;
  }
}

Future<void> requestOverlayPermission() async {
  if (!Platform.isAndroid) return;

  try {
    await overlayChannel.invokeMethod('requestPermissions');
    debugPrint('📱 Overlay permission requested');
  } catch (e) {
    debugPrint('⚠️ Error requesting overlay permission: $e');
  }
}

/// =====================================================
/// 🚀 MAIN
/// =====================================================
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  /// ---------- Local Notifications ----------
  await LocalNotificationService.initialize();

  /// ---------- Logging ----------
  Logger.root.level = Level.ALL;
  Logger.root.onRecord.listen((record) {
    debugPrint(
      '${record.level.name}: ${record.time.toIso8601String()} '
      '${record.loggerName} - ${record.message}',
    );
  });

  /// ---------- Notification permission ----------
  await FirebaseMessaging.instance.requestPermission(
    alert: true,
    badge: true,
    sound: true,
    criticalAlert: true,
  );

  /// 🔥 Register background message handler
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  /// ---------- Foreground FCM messages ----------
  FirebaseMessaging.onMessage.listen((RemoteMessage message) {
    debugPrint('');
    debugPrint('=' * 70);
    debugPrint('🔔 FCM FOREGROUND MESSAGE');
    debugPrint('   Title: ${message.notification?.title}');
    debugPrint('   Body: ${message.notification?.body}');
    debugPrint('   Data: ${message.data}');
    debugPrint('=' * 70);
    debugPrint('');

    // Check if it's a trip request
    if (message.data.containsKey('tripId') ||
        message.data['type'] == 'TRIP_REQUEST') {
      debugPrint('🚕 Trip request in foreground - showing overlay!');

      // ❌ DON'T show notification - it brings app to foreground
      // LocalNotificationService.showNotification(...);

      // ✅ ONLY show the native overlay
      _handleForegroundTripRequest(message.data);
    } else {
      // Regular notification (non-trip)
      final title = message.notification?.title ?? 'New Notification';
      final body = message.notification?.body ?? '';
      LocalNotificationService.showNotification(title: title, body: body);
    }

    NotificationEventBus.refresh();
  });

  /// ---------- App opened from notification ----------
  FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
    debugPrint('');
    debugPrint('=' * 70);
    debugPrint('📲 APP OPENED FROM NOTIFICATION');
    debugPrint('   Data: ${message.data}');
    debugPrint('=' * 70);
    debugPrint('');

    NotificationEventBus.refresh();

    if (message.data.containsKey('tripId')) {
      debugPrint('🚕 Opening app with trip: ${message.data['tripId']}');
      // Store for splash screen to pick up
      _storePendingTripAction(message.data);
    }
  });

  /// ---------- Check if app was opened from terminated state ----------
  final initialMessage = await FirebaseMessaging.instance.getInitialMessage();
  if (initialMessage != null) {
    debugPrint('📲 App launched from terminated state via notification');
    debugPrint('   Data: ${initialMessage.data}');

    if (initialMessage.data.containsKey('tripId')) {
      _storePendingTripAction(initialMessage.data);
    }
  }

  /// ---------- Background service ----------
  TripBackgroundService.initializeService();

  /// ---------- Battery optimization ----------
  requestBatteryOptimizationExemption();

  /// ---------- Check overlay permission ----------
  final hasOverlay = await checkAndRequestOverlayPermission();
  if (!hasOverlay) {
    debugPrint('⚠️ Overlay permission not granted - will request later');
  }

  runApp(const IndianRideDriverApp());
}

/// =====================================================
/// 🧪 TEST OVERLAY FUNCTION (for debugging)
/// =====================================================
Future<void> testOverlay() async {
  debugPrint('🧪 Testing overlay...');

  try {
    final testTripData = {
      'tripId': 'TEST_${DateTime.now().millisecondsSinceEpoch}',
      'fare': '150',
      'vehicleType': 'bike',
      'pickupAddress': 'Test Pickup Location',
      'dropAddress': 'Test Drop Location',
      'pickupLat': '17.3850',
      'pickupLng': '78.4867',
      'dropLat': '17.4065',
      'dropLng': '78.4492',
      'customerId': 'test_customer',
      'paymentMethod': 'cash',
      'isDestinationMatch': 'false',
    };

    await overlayChannel.invokeMethod('show', {'tripData': testTripData});
    debugPrint('✅ Test overlay invoked');
  } catch (e) {
    debugPrint('❌ Error testing overlay: $e');
  }
}

/// Handle foreground trip request
void _handleForegroundTripRequest(Map<String, dynamic> data) async {
  try {
    debugPrint('📱 _handleForegroundTripRequest called');

    // Parse addresses
    String pickupAddress =
        data['pickupAddress']?.toString() ?? 'Pickup Location';
    String dropAddress = data['dropAddress']?.toString() ?? 'Drop Location';

    if (data['pickup'] != null) {
      if (data['pickup'] is String) {
        try {
          final pickup = jsonDecode(data['pickup']);
          pickupAddress = pickup['address']?.toString() ?? pickupAddress;
        } catch (_) {}
      } else if (data['pickup'] is Map) {
        pickupAddress = data['pickup']['address']?.toString() ?? pickupAddress;
      }
    }

    if (data['drop'] != null) {
      if (data['drop'] is String) {
        try {
          final drop = jsonDecode(data['drop']);
          dropAddress = drop['address']?.toString() ?? dropAddress;
        } catch (_) {}
      } else if (data['drop'] is Map) {
        dropAddress = data['drop']['address']?.toString() ?? dropAddress;
      }
    }

    final overlayData = {
      'tripId': data['tripId']?.toString() ?? '',
      'fare': data['fare']?.toString() ?? '0',
      'vehicleType': data['vehicleType']?.toString() ?? 'BIKE',
      'pickupAddress': pickupAddress,
      'dropAddress': dropAddress,
      'pickupLat': data['pickupLat']?.toString() ?? '0',
      'pickupLng': data['pickupLng']?.toString() ?? '0',
      'dropLat': data['dropLat']?.toString() ?? '0',
      'dropLng': data['dropLng']?.toString() ?? '0',
      'customerId': data['customerId']?.toString() ?? '',
      'paymentMethod': data['paymentMethod']?.toString() ?? 'cash',
      'isDestinationMatch': data['isDestinationMatch']?.toString() ?? 'false',
    };

    debugPrint('📱 Invoking native overlay with data: $overlayData');

    // Show overlay via method channel
    await overlayChannel.invokeMethod('show', {'tripData': overlayData});

    debugPrint('✅ Overlay invoked successfully');
  } catch (e) {
    debugPrint('❌ Error showing overlay in foreground: $e');
  }
}

/// Store pending trip action for splash screen
void _storePendingTripAction(Map<String, dynamic> data) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('pending_trip_id', data['tripId']?.toString() ?? '');
    await prefs.setString('pending_trip_action', 'OPEN');
    await prefs.setInt(
      'pending_trip_time',
      DateTime.now().millisecondsSinceEpoch,
    );
  } catch (e) {
    debugPrint('Error storing pending trip: $e');
  }
}

/// =====================================================
/// 🎨 APP ROOT
/// =====================================================
class IndianRideDriverApp extends StatelessWidget {
  const IndianRideDriverApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'Ghumo Partner',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.indigo,
        scaffoldBackgroundColor: const Color(0xFFF5F7FA),
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: const SplashScreen(),
    );
  }
}
