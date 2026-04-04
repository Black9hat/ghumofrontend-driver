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
/// 🎯 DEBUG HELPER
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
/// 🔔 FCM BACKGROUND MESSAGE HANDLER
/// =====================================================
/// NOTE: This runs in a separate isolate - Method Channels DON'T WORK here!
/// The NATIVE MyFirebaseMessagingService.kt handles overlay display for trips.
/// For admin notifications the system handles display via notification block.
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  debugPrint('');
  debugPrint('=' * 70);
  debugPrint('🔔 BACKGROUND FCM (Dart Handler)');
  debugPrint('   Message ID: ${message.messageId}');
  debugPrint('   Data: ${message.data}');
  debugPrint('   Has notification block: ${message.notification != null}');
  debugPrint('=' * 70);
  debugPrint('');

  final String type = message.data['type'] ?? '';
  final bool isTripRequest =
      message.data.containsKey('tripId') && message.data['tripId'].isNotEmpty ||
      type == 'TRIP_REQUEST';

  if (isTripRequest) {
    debugPrint('🚕 Trip request in background — native overlay will handle');
  } else {
    // Admin / general notification — system shows it via notification block.
    // No extra action needed here; Android handles display automatically.
    debugPrint('📢 Admin/general notification in background — system will display');
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
  /// Driver app FCM messages are pure data-only (no notification block)
  /// for trip requests. Admin notifications now have a notification block
  /// for killed-app delivery but we still handle foreground manually here.
  FirebaseMessaging.onMessage.listen((RemoteMessage message) {
    debugPrint('');
    debugPrint('=' * 70);
    debugPrint('🔔 FCM FOREGROUND MESSAGE');
    debugPrint('   Has notification block: ${message.notification != null}');
    debugPrint('   notification.title: ${message.notification?.title}');
    debugPrint('   notification.body: ${message.notification?.body}');
    debugPrint('   Data: ${message.data}');
    debugPrint('=' * 70);
    debugPrint('');

    final String type = message.data['type'] ?? '';
    final bool isTripRequest =
        (message.data.containsKey('tripId') &&
            message.data['tripId'].isNotEmpty) ||
        type == 'TRIP_REQUEST';

    if (isTripRequest) {
      debugPrint('🚕 Trip request in FOREGROUND — not showing overlay');
      // Overlay only shows when app is closed (native handles it)
    } else {
      // ✅ FIX: For the driver app, admin notifications are pure data-only
      // FCM messages. Read title/body from message.data first,
      // then fall back to message.notification (for future-proofing).
      final String title = (message.data['title'] ?? '').isNotEmpty
          ? message.data['title']!
          : (message.notification?.title ?? 'New Notification');

      final String body = (message.data['body'] ?? '').isNotEmpty
          ? message.data['body']!
          : (message.notification?.body ?? '');

      debugPrint('📢 Showing local notification: $title');
      LocalNotificationService.showNotification(title: title, body: body);
    }

    // Always refresh notification list in UI
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

    if (message.data.containsKey('tripId') &&
        message.data['tripId'].isNotEmpty) {
      debugPrint('🚕 Opening app with trip: ${message.data['tripId']}');
      _storePendingTripAction(message.data);
    }
  });

  /// ---------- Check if app was opened from terminated state ----------
  final initialMessage = await FirebaseMessaging.instance.getInitialMessage();
  if (initialMessage != null) {
    debugPrint('📲 App launched from terminated state via notification');
    debugPrint('   Data: ${initialMessage.data}');

    if (initialMessage.data.containsKey('tripId') &&
        initialMessage.data['tripId'].isNotEmpty) {
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