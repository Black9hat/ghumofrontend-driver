import 'dart:async';
import 'dart:convert';
import 'dart:ui';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:geolocator/geolocator.dart';
import 'socket_service.dart';
import 'package:logging/logging.dart';

final Logger _logger = Logger('TripBackgroundService');

void print(Object? object) {
  _logger.info(object);
}

class TripBackgroundService {
  static const MethodChannel _overlayChannel = MethodChannel('overlay_service');

  static final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  /// ✅ Initialize background service
  static Future<void> initializeService() async {
    final service = FlutterBackgroundService();

    // Create notification channels
    const AndroidNotificationChannel activeTripChannel =
        AndroidNotificationChannel(
          'active_trip_channel',
          'Active Trip',
          description: 'Shows when you have an active trip',
          importance: Importance.high,
        );

    const AndroidNotificationChannel onlineChannel = AndroidNotificationChannel(
      'driver_online_channel',
      'Driver Online',
      description: 'Shows when driver is online and ready for trips',
      importance: Importance.low,
    );

    final androidPlugin = _notifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();

    await androidPlugin?.createNotificationChannel(activeTripChannel);
    await androidPlugin?.createNotificationChannel(onlineChannel);

    await service.configure(
      iosConfiguration: IosConfiguration(
        autoStart: false,
        onForeground: onStart,
        onBackground: onIosBackground,
      ),
      androidConfiguration: AndroidConfiguration(
        onStart: onStart,
        isForegroundMode: true,
        autoStart: false,
        autoStartOnBoot: true,
      ),
    );

    print('✅ Background service initialized');
  }

  /// Check overlay permission
  static Future<bool> checkOverlayPermission() async {
    try {
      final result = await _overlayChannel.invokeMethod('checkPermission');
      return result == true;
    } catch (e) {
      print('❌ Error checking overlay permission: $e');
      return false;
    }
  }

  /// Request overlay permission from native side
  static Future<void> requestOverlayPermission() async {
    try {
      await _overlayChannel.invokeMethod('requestPermissions');
    } catch (e) {
      print('❌ Error requesting permissions: $e');
    }
  }

  /// ✅ Start service when driver goes ONLINE
  static Future<void> startOnlineService({
    required String driverId,
    required String vehicleType,
    required bool isOnline,
  }) async {
    final service = FlutterBackgroundService();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('driverId', driverId);
    await prefs.setString('vehicleType', vehicleType);
    await prefs.setBool('isOnline', isOnline);
    await prefs.setBool('bg_online_service_running', true);

    // Get and store FCM token
    final fcmToken = await FirebaseMessaging.instance.getToken();
    if (fcmToken != null) {
      await prefs.setString('fcmToken', fcmToken);
    }

    final isRunning = await service.isRunning();
    if (!isRunning) {
      await service.startService();
      print('🚀 Online service started');
    }

    service.invoke('update_online_status', {
      'driverId': driverId,
      'vehicleType': vehicleType,
      'isOnline': isOnline,
      'fcmToken': fcmToken,
    });

    print('✅ Driver online service active - Driver: $driverId');
  }

  /// ✅ Stop online service when driver goes offline
  static Future<void> stopOnlineService() async {
    final service = FlutterBackgroundService();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isOnline', false);
    await prefs.setBool('bg_online_service_running', false);

    service.invoke('update_online_status', {'isOnline': false});

    // Only stop service if no active trip
    final hasActiveTrip = prefs.getBool('hasActiveTrip') ?? false;
    if (!hasActiveTrip) {
      service.invoke('stop');
      print('🛑 Online service stopped - driver offline');
    } else {
      print('⚠️ Service continues - active trip in progress');
    }
  }

  /// ✅ Show overlay when trip request comes
  /// NOTE: This is called from FOREGROUND Flutter only
  /// Background FCM is handled by native MyFirebaseMessagingService
  static Future<void> showTripOverlay(Map<String, dynamic> tripData) async {
    try {
      String pickupAddress = 'Pickup Location';
      String dropAddress = 'Drop Location';

      // Parse pickup address
      if (tripData['pickupAddress'] != null) {
        pickupAddress = tripData['pickupAddress'].toString();
      } else if (tripData['pickup'] != null) {
        if (tripData['pickup'] is Map) {
          pickupAddress =
              tripData['pickup']['address']?.toString() ?? 'Pickup Location';
        } else if (tripData['pickup'] is String) {
          try {
            final pickup = jsonDecode(tripData['pickup']);
            pickupAddress = pickup['address']?.toString() ?? 'Pickup Location';
          } catch (_) {
            pickupAddress = tripData['pickup'].toString();
          }
        }
      }

      // Parse drop address
      if (tripData['dropAddress'] != null) {
        dropAddress = tripData['dropAddress'].toString();
      } else if (tripData['drop'] != null) {
        if (tripData['drop'] is Map) {
          dropAddress =
              tripData['drop']['address']?.toString() ?? 'Drop Location';
        } else if (tripData['drop'] is String) {
          try {
            final drop = jsonDecode(tripData['drop']);
            dropAddress = drop['address']?.toString() ?? 'Drop Location';
          } catch (_) {
            dropAddress = tripData['drop'].toString();
          }
        }
      }

      final overlayData = {
        'tripId': tripData['tripId']?.toString() ?? '',
        'fare': tripData['fare']?.toString() ?? '0',
        'vehicleType': tripData['vehicleType']?.toString() ?? 'BIKE',
        'pickup': tripData['pickup'], // Keep as map
        'drop': tripData['drop'], // Keep as map
        'isDestinationMatch':
            tripData['isDestinationMatch']?.toString() ?? 'false',
        'pickupAddress': pickupAddress, // For overlay display
        'dropAddress': dropAddress, // For overlay display
        'pickupLat': tripData['pickup']?['lat']?.toString() ?? '0',
        'pickupLng': tripData['pickup']?['lng']?.toString() ?? '0',
        'dropLat': tripData['drop']?['lat']?.toString() ?? '0',
        'dropLng': tripData['drop']?['lng']?.toString() ?? '0',
      };

      print('📱 Showing overlay with data: $overlayData');

      await _overlayChannel.invokeMethod('show', {'tripData': overlayData});

      print('✅ Overlay shown for trip: ${tripData['tripId']}');
    } catch (e) {
      print('❌ Error showing overlay: $e');
    }
  }

  /// ✅ Hide overlay - ONLY call when user accepts/rejects trip
  /// ❌ DO NOT call this when app goes to background!
  static Future<void> hideOverlay() async {
    try {
      print('🙈 Hiding overlay (user action)');
      await _overlayChannel.invokeMethod('hide');
    } catch (e) {
      print('❌ Error hiding overlay: $e');
    }
  }

  /// ✅ Start background service for active trip
  static Future<void> startTripService({
    required String tripId,
    required String driverId,
    required String customerName,
  }) async {
    await WakelockPlus.enable();
    final service = FlutterBackgroundService();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('bg_tripId', tripId);
    await prefs.setString('bg_driverId', driverId);
    await prefs.setString('bg_customerName', customerName);
    await prefs.setBool('bg_service_running', true);
    await prefs.setBool('hasActiveTrip', true);
    await prefs.setString('activeTripId', tripId);

    final isRunning = await service.isRunning();
    if (!isRunning) {
      await service.startService();
    }

    service.invoke('start_trip', {
      'tripId': tripId,
      'driverId': driverId,
      'customerName': customerName,
    });

    print('🚀 Background service started for trip: $tripId');
  }

  /// ✅ Stop background service
  static Future<void> stopTripService() async {
    await WakelockPlus.disable();

    final service = FlutterBackgroundService();

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('bg_tripId');
    await prefs.remove('bg_driverId');
    await prefs.remove('bg_customerName');
    await prefs.setBool('bg_service_running', false);
    await prefs.setBool('hasActiveTrip', false);
    await prefs.remove('activeTripId');

    final isOnline = prefs.getBool('isOnline') ?? false;

    if (!isOnline) {
      service.invoke('stop');
      print('🛑 Background service completely stopped');
    } else {
      service.invoke('trip_completed');
      print('✅ Trip service stopped - driver still online');
    }
  }

  /// ✅ Check if service is running
  static Future<bool> isServiceRunning() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('bg_service_running') ?? false;
  }

  /// ✅ Background service entry point
  @pragma('vm:entry-point')
  static void onStart(ServiceInstance service) async {
    DartPluginRegistrant.ensureInitialized();

    final prefs = await SharedPreferences.getInstance();

    String? tripId = prefs.getString('bg_tripId');
    String? driverId =
        prefs.getString('bg_driverId') ?? prefs.getString('driverId');
    String? customerName = prefs.getString('bg_customerName');

    final isOnline = prefs.getBool('isOnline') ?? false;
    final vehicleType = prefs.getString('vehicleType') ?? 'bike';

    final socketService = DriverSocketService();

    // Get location
    Position? position;
    try {
      position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
    } catch (e) {
      final lastLat = double.tryParse(prefs.getString('lastLat') ?? '') ?? 0.0;
      final lastLng = double.tryParse(prefs.getString('lastLng') ?? '') ?? 0.0;
      position = Position(
        latitude: lastLat,
        longitude: lastLng,
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

    // Connect socket
    if (driverId != null && driverId.isNotEmpty) {
      socketService.connect(
        driverId,
        position.latitude,
        position.longitude,
        vehicleType: vehicleType,
        isOnline: isOnline,
      );

      // NOTE: Trip requests in background are handled by native FCM service
      // This is only for socket-based requests when app is in foreground service
      socketService.onRideRequest = (tripData) {
        print('📩 Trip request via socket: ${tripData['tripId']}');
        // Emit event to main app if running
        service.invoke('trip_request', tripData);
      };

      socketService.onActiveTripRestored = (tripData) {
        print('🔄 Active trip restored: ${tripData['tripId']}');
        final tid = tripData['tripId']?.toString();
        if (tid != null) {
          prefs.setString('restoredTripId', tid);
          prefs.setString('restoredTripData', jsonEncode(tripData));
        }
      };
    }

    // Show notification
    if (tripId != null && customerName != null) {
      await _showNotification(
        channelId: 'active_trip_channel',
        title: 'Active Trip',
        body: 'Trip with $customerName is in progress',
        ongoing: true,
      );
    } else if (isOnline) {
      await _showNotification(
        channelId: 'driver_online_channel',
        title: "You're Online",
        body: 'Ready to receive trip requests',
        ongoing: true,
      );
    }

    // Listen for commands
    service.on('stop').listen((event) {
      socketService.disconnect();
      service.stopSelf();
      WakelockPlus.disable();
      print('🛑 Service stopped via command');
    });

    service.on('update_online_status').listen((event) async {
      if (event != null) {
        final data = event;
        final newOnlineStatus = data['isOnline'] as bool? ?? false;

        if (newOnlineStatus) {
          await _showNotification(
            channelId: 'driver_online_channel',
            title: "You're Online",
            body: 'Ready to receive trip requests',
            ongoing: true,
          );
        }
      }
    });

    service.on('start_trip').listen((event) async {
      if (event != null) {
        final data = event;
        final newCustomerName = data['customerName'] as String;

        await _showNotification(
          channelId: 'active_trip_channel',
          title: 'Active Trip',
          body: 'Trip with $newCustomerName is in progress',
          ongoing: true,
        );
      }
    });

    service.on('trip_completed').listen((event) async {
      final stillOnline = prefs.getBool('isOnline') ?? false;
      if (stillOnline) {
        await _showNotification(
          channelId: 'driver_online_channel',
          title: "You're Online",
          body: 'Ready for next trip',
          ongoing: true,
        );
      }
    });

    // Periodic keep-alive
    Timer.periodic(const Duration(seconds: 30), (timer) async {
      if (service is AndroidServiceInstance) {
        if (!(await service.isForegroundService())) {
          timer.cancel();
          return;
        }
      }

      final stillOnline = prefs.getBool('isOnline') ?? false;
      final hasActiveTrip = prefs.getBool('hasActiveTrip') ?? false;

      if (!stillOnline && !hasActiveTrip) {
        print('⚠️ Driver offline and no active trip - stopping service');
        timer.cancel();
        socketService.disconnect();
        service.stopSelf();
        await WakelockPlus.disable();
        return;
      }

      if ((stillOnline || hasActiveTrip) && driverId != null) {
        try {
          final newPosition = await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.high,
          );

          // Send location update via socket
          if (socketService.socket.connected) {
            if (hasActiveTrip && tripId != null) {
              // For active trip: send driver:location event
              socketService.socket.emit('driver:location', {
                'tripId': tripId,
                'driverId': driverId,
                'latitude': newPosition.latitude,
                'longitude': newPosition.longitude,
                'sequence': DateTime.now().millisecondsSinceEpoch,
                'timestamp': DateTime.now().toIso8601String(),
              });
              print(
                '📍 Trip location update sent: ${newPosition.latitude}, ${newPosition.longitude}',
              );
            } else if (stillOnline) {
              // For online status: send updateDriverStatus
              socketService.updateLocation(
                newPosition.latitude,
                newPosition.longitude,
              );
            }
          }

          await prefs.setString('lastLat', newPosition.latitude.toString());
          await prefs.setString('lastLng', newPosition.longitude.toString());
        } catch (e) {
          print('⚠️ Location update error: $e');
        }
      }

      print('💚 Service alive - Online: $stillOnline, Trip: $hasActiveTrip');
    });
  }

  @pragma('vm:entry-point')
  static Future<bool> onIosBackground(ServiceInstance service) async {
    WidgetsFlutterBinding.ensureInitialized();
    DartPluginRegistrant.ensureInitialized();
    return true;
  }

  static Future<void> _showNotification({
    required String channelId,
    required String title,
    required String body,
    bool ongoing = false,
  }) async {
    final AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
          channelId,
          channelId == 'active_trip_channel' ? 'Active Trip' : 'Driver Online',
          channelDescription: channelId == 'active_trip_channel'
              ? 'Shows when you have an active trip'
              : 'Shows when driver is online',
          importance: channelId == 'active_trip_channel'
              ? Importance.high
              : Importance.low,
          priority: channelId == 'active_trip_channel'
              ? Priority.high
              : Priority.low,
          ongoing: ongoing,
          autoCancel: false,
          icon: '@mipmap/ic_launcher',
        );

    final NotificationDetails details = NotificationDetails(
      android: androidDetails,
    );
    await _notifications.show(888, title, body, details);
  }
}
