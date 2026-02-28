import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:drivergoo/config.dart';

class DriverNotificationService {
  static const String baseUrl = '${AppConfig.backendBaseUrl}/api/admin';

  /// 🔔 Fetch driver notifications
  static Future<Map<String, dynamic>> fetchNotifications() async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      throw Exception('Driver not authenticated');
    }

    final firebaseToken = await user.getIdToken();

    final response = await http.get(
      Uri.parse('$baseUrl/notifications/user'),
      headers: {
        'Authorization': 'Bearer $firebaseToken',
        'Content-Type': 'application/json',
      },
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to load notifications (${response.statusCode})');
    }

    return jsonDecode(response.body);
  }

  /// 👁 Mark single notification as read
  static Future<void> markAsRead(String notificationId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final firebaseToken = await user.getIdToken();

    await http.put(
      Uri.parse('$baseUrl/notifications/$notificationId/read'),
      headers: {'Authorization': 'Bearer $firebaseToken'},
    );
  }

  /// 👁👁 Mark all notifications as read
  static Future<void> markAllAsRead() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final firebaseToken = await user.getIdToken();

    await http.put(
      Uri.parse('$baseUrl/notifications/user/read-all'),
      headers: {'Authorization': 'Bearer $firebaseToken'},
    );
  }

  /// 🗑 Delete notification
  static Future<void> deleteNotification(String notificationId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final firebaseToken = await user.getIdToken();

    await http.delete(
      Uri.parse('$baseUrl/notifications/$notificationId'),
      headers: {'Authorization': 'Bearer $firebaseToken'},
    );
  }
}
