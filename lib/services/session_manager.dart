// 🔥 DRIVER ROLE SESSION IMPLEMENTATION
// session_manager.dart - Manages role-based sessions and device control

import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:drivergoo/config.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'socket_service.dart';

class SessionManager {
  static final SessionManager _instance = SessionManager._internal();
  factory SessionManager() => _instance;
  SessionManager._internal();

  // Role-based session variables
  String? _driverId;
  String? _role;
  String? _deviceId;
  String? _phoneNumber;
  bool _isSessionActive = false;

  // Callbacks for session events
  Function(String message)? onForceLogout;
  Function()? onSessionExpired;

  // Getters
  String? get driverId => _driverId;
  String? get role => _role;
  String? get deviceId => _deviceId;
  String? get phoneNumber => _phoneNumber;
  bool get isSessionActive => _isSessionActive;

  /// 🔥 Initialize session on login
  /// Stores role = "driver", deviceId (Firebase UID), and manages single-device constraint
  Future<void> initializeSession({
    required String driverId,
    required String role,
    required String phoneNumber,
    String? firebaseUid,
  }) async {
    try {
      _driverId = driverId;
      _role = role;
      _phoneNumber = phoneNumber;

      // Use Firebase UID as device ID (fallback to phone number)
      _deviceId = firebaseUid ?? "phone_$phoneNumber";

      final prefs = await SharedPreferences.getInstance();

      // Save session data with role
      await prefs.setString('driverId', driverId);
      await prefs.setString('role', role); // 🔥 Store role = "driver"
      await prefs.setString('phoneNumber', phoneNumber);
      await prefs.setString('deviceId', _deviceId!);
      await prefs.setBool('isSessionActive', true);
      await prefs.setInt(
        'sessionStartTime',
        DateTime.now().millisecondsSinceEpoch,
      );

      _isSessionActive = true;

      debugPrint(
        '🔥 Session initialized: role=$role, deviceId=$_deviceId, driverId=$driverId',
      );

      // 🔥 Register this device + role with backend for device control
      await _registerDeviceWithBackend(driverId, role, _deviceId!);

      // 🔥 Connect socket early to receive force_logout events
      // This ensures that if another device logs in, this device will receive
      // the force_logout event and can log out immediately
      _initializeSocketEarly();
    } catch (e) {
      debugPrint('❌ Session initialization error: $e');
      rethrow;
    }
  }

  /// 🔥 Initialize socket early (non-blocking)
  /// Allows force_logout events to be received from backend
  void _initializeSocketEarly() {
    try {
      DriverSocketService();
      // Fire and forget - don't wait for socket to connect
      // The socket will connect in the background
      debugPrint('🔌 Initializing socket for force_logout listening');
    } catch (e) {
      debugPrint('⚠️ Socket early initialization error (non-critical): $e');
    }
  }

  /// 🔥 Register device with backend for single-device control
  /// This allows backend to track which device the driver is on
  /// and enforce logout on other devices
  Future<void> _registerDeviceWithBackend(
    String driverId,
    String role,
    String deviceId,
  ) async {
    try {
      final token = await FirebaseAuth.instance.currentUser?.getIdToken();
      if (token == null) {
        debugPrint('⚠️ No Firebase token for device registration');
        return;
      }

      final response = await http
          .post(
            Uri.parse('${AppConfig.backendBaseUrl}/api/driver/register-device'),
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'driverId': driverId,
              'role': role, // 🔥 Include role for backend device control
              'deviceId': deviceId,
              'timestamp': DateTime.now().toIso8601String(),
            }),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final isNewDevice = data['newDevice'] ?? false;
        final previousDeviceId = data['previousDeviceId'];

        debugPrint(
          '✅ Device registered: newDevice=$isNewDevice, previousDevice=$previousDeviceId',
        );

        if (isNewDevice && previousDeviceId != null) {
          debugPrint(
            '⚠️ Driver logged in on new device. Previous device: $previousDeviceId',
          );
          // Backend will send force_logout to old device
        }
      } else if (response.statusCode == 409) {
        // Device already registered but needs to clear previous session
        debugPrint('⚠️ Device conflict - old device should logout');
      } else {
        debugPrint(
          '⚠️ Device registration failed: ${response.statusCode} - ${response.body}',
        );
      }
    } catch (e) {
      debugPrint('⚠️ Device registration error (non-critical): $e');
      // Don't fail login if device registration fails
    }
  }

  /// 🔥 Handle force logout from server
  /// Called when another device logs in with same driver account
  /// Shows dialog to user explaining they've been logged out
  Future<void> handleForceLogout({required String reason}) async {
    debugPrint('🔥 Force logout triggered: role=$_role, reason=$reason');

    // Only logout if this is a driver role
    if (_role != 'driver') {
      debugPrint('⚠️ Force logout ignored: role is not driver (role=$_role)');
      return;
    }

    // Clear session
    await clearSession();

    // Call callback
    if (onForceLogout != null) {
      onForceLogout!(
        'You have been logged out because your account was used on another device',
      );
    }
  }

  /// 🔥 Clear session on logout
  /// Removes all role-related session data
  Future<void> clearSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Clear session data
      await prefs.remove('driverId');
      await prefs.remove('role');
      await prefs.remove('phoneNumber');
      await prefs.remove('deviceId');
      await prefs.remove('isSessionActive');
      await prefs.remove('sessionStartTime');

      _driverId = null;
      _role = null;
      _phoneNumber = null;
      _deviceId = null;
      _isSessionActive = false;

      debugPrint('✅ Session cleared');
    } catch (e) {
      debugPrint('❌ Session clear error: $e');
    }
  }

  /// 🔥 Restore session from SharedPreferences
  /// Called on app startup to restore previous session
  Future<bool> restoreSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      _driverId = prefs.getString('driverId');
      _role = prefs.getString('role');
      _phoneNumber = prefs.getString('phoneNumber');
      _deviceId = prefs.getString('deviceId');
      _isSessionActive = prefs.getBool('isSessionActive') ?? false;

      if (_isSessionActive && _role == 'driver' && _driverId != null) {
        debugPrint('🔥 Session restored: role=$_role, deviceId=$_deviceId');
        return true;
      }

      return false;
    } catch (e) {
      debugPrint('❌ Session restore error: $e');
      return false;
    }
  }

  /// 🔥 Validate session is still active
  Future<bool> validateSession() async {
    if (!_isSessionActive || _role != 'driver' || _driverId == null) {
      return false;
    }

    try {
      final token = await FirebaseAuth.instance.currentUser?.getIdToken();
      if (token == null) return false;

      final response = await http
          .get(
            Uri.parse('${AppConfig.backendBaseUrl}/api/driver/session-status'),
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final isValid = data['isValid'] ?? false;
        final currentDeviceId = data['currentDeviceId'];

        // Check if this device ID is still active
        if (isValid && currentDeviceId == _deviceId) {
          debugPrint('✅ Session valid on current device');
          return true;
        } else if (!isValid || currentDeviceId != _deviceId) {
          debugPrint(
            '🔥 Session invalid: different device logged in (currentDevice=$currentDeviceId, thisDevice=$_deviceId)',
          );
          return false;
        }
      }

      return false;
    } catch (e) {
      debugPrint('⚠️ Session validation error: $e');
      return false;
    }
  }

  /// 🔥 Get device info for debugging
  Map<String, String?> getDeviceInfo() {
    return {
      'driverId': _driverId,
      'role': _role,
      'deviceId': _deviceId,
      'phoneNumber': _phoneNumber,
      'isSessionActive': _isSessionActive.toString(),
    };
  }
}
