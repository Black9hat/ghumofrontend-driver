import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:logging/logging.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:drivergoo/config.dart';

final Logger _logger = Logger('FCMService');

class FCMService {
  static const String _apiBase = AppConfig.backendBaseUrl;

  /// Initialize FCM and get token
  static Future<String?> sendTokenToServer(String driverId) async {
    try {
      // Request permission
      await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        criticalAlert: true,
      );

      final fcmToken = await FirebaseMessaging.instance.getToken();

      if (fcmToken == null) {
        _logger.warning('❌ FCM token is null');
        return null;
      }

      _logger.info('📱 FCM Token obtained: ${fcmToken.substring(0, 30)}...');

      // Save token locally
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('fcmToken', fcmToken);

      // Send to server
      final response = await http.post(
        Uri.parse('$_apiBase/api/user/update-fcm'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'driverId': driverId, 'fcmToken': fcmToken}),
      );

      if (response.statusCode == 200) {
        _logger.info('✅ FCM token saved to server');
        return fcmToken;
      } else {
        _logger.severe('❌ Failed to save FCM token: ${response.body}');
        return fcmToken; // Still return token even if server save fails
      }
    } catch (e) {
      _logger.severe('❌ FCM error: $e');
      return null;
    }
  }

  /// Listen for token refresh
  static void listenForTokenRefresh(String driverId) {
    FirebaseMessaging.instance.onTokenRefresh.listen((newToken) async {
      _logger.info('🔄 FCM token refreshed');

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('fcmToken', newToken);

      try {
        await http.post(
          Uri.parse('$_apiBase/api/user/update-fcm'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'driverId': driverId, 'fcmToken': newToken}),
        );
        _logger.info('✅ Refreshed FCM token saved to server');
      } catch (e) {
        _logger.severe('❌ FCM token refresh error: $e');
      }
    });
  }

  /// Get saved FCM token
  static Future<String?> getSavedToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('fcmToken');
  }

  /// Delete FCM token from server (on logout)
  static Future<void> deleteTokenFromServer(String driverId) async {
    try {
      await http.post(
        Uri.parse('$_apiBase/api/user/delete-fcm'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'driverId': driverId}),
      );

      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('fcmToken');

      _logger.info('✅ FCM token deleted');
    } catch (e) {
      _logger.severe('❌ FCM deletion error: $e');
    }
  }
}
