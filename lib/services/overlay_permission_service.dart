import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class OverlayPermissionService {
  static const MethodChannel _channel = MethodChannel('overlay_service');
  
  /// Check if overlay permission is granted
  static Future<bool> hasPermission() async {
    try {
      final result = await _channel.invokeMethod('checkPermission');
      return result == true;
    } catch (e) {
      print('Error checking overlay permission: $e');
      return false;
    }
  }
  
  /// Request overlay permission (opens system settings)
  static Future<void> requestPermission() async {
    try {
      await _channel.invokeMethod('requestPermissions');
    } catch (e) {
      print('Error requesting overlay permission: $e');
    }
  }
  
  /// Check if we've already asked for permission on this device
  static Future<bool> hasAskedPermissionBefore() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('overlay_permission_asked') ?? false;
  }
  
  /// Mark that we've asked for permission
  static Future<void> markPermissionAsked() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('overlay_permission_asked', true);
  }
  
  /// Reset the asked flag (useful for testing or re-login)
  static Future<void> resetPermissionAsked() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('overlay_permission_asked');
  }
}