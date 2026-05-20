import 'dart:convert';

import 'package:drivergoo/config.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class HelpSettingsService {
  static const String defaultSupportPhone = '+917337298393';

  static const String _supportPhoneKey = 'supportPhone';
  static const String _supportPhoneFetchedAtKey = 'supportPhoneFetchedAt';

  static Future<String> getSupportPhone({bool forceRefresh = false}) async {
    final prefs = await SharedPreferences.getInstance();
    final cachedPhone = prefs.getString(_supportPhoneKey);

    final phoneFromApi = await _fetchSupportPhoneFromApi();
    if (phoneFromApi != null && phoneFromApi.isNotEmpty) {
      await prefs.setString(_supportPhoneKey, phoneFromApi);
      await prefs.setInt(
        _supportPhoneFetchedAtKey,
        DateTime.now().millisecondsSinceEpoch,
      );
      return phoneFromApi;
    }

    if (cachedPhone != null && cachedPhone.isNotEmpty) {
      return cachedPhone;
    }

    return defaultSupportPhone;
  }

  static Future<String?> _fetchSupportPhoneFromApi() async {
    try {
      final response = await http
          .get(
            Uri.parse('${AppConfig.backendBaseUrl}/api/help/settings'),
            headers: const {
              'Content-Type': 'application/json',
              'ngrok-skip-browser-warning': 'true',
            },
          )
          .timeout(const Duration(seconds: 8));

      if (response.statusCode != 200) {
        return null;
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        return null;
      }

      final settings = decoded['settings'];
      if (settings is! Map<String, dynamic>) {
        return null;
      }

      final rawPhone = settings['supportPhone']?.toString() ?? '';
      final normalized = normalizePhone(rawPhone);

      if (normalized.isEmpty) {
        return null;
      }

      return normalized;
    } catch (_) {
      return null;
    }
  }

  static String normalizePhone(String rawPhone) {
    final trimmed = rawPhone.trim();
    if (trimmed.isEmpty) {
      return '';
    }

    final keepPlus = trimmed.startsWith('+');
    final digitsOnly = trimmed.replaceAll(RegExp(r'[^0-9]'), '');

    if (digitsOnly.isEmpty) {
      return '';
    }

    return keepPlus ? '+$digitsOnly' : digitsOnly;
  }
}
