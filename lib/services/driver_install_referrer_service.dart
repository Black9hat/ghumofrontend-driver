import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DriverInstallReferrerService {
  static const String _pendingCodeKey = 'pending_driver_referral_code';
  static const MethodChannel _channel =
      MethodChannel('com.ghumodriver.app/install_referrer');

  static final Completer<void> _readCompleter = Completer<void>();
  static bool _started = false;
  static const List<String> _possibleCodeKeys = <String>[
    'referralCode',
    'referral_code',
    'ref',
    'code',
    'referrerCode',
  ];

  static Future<void> checkAndSave() async {
    _started = true;
    debugPrint('🔄 DriverInstallReferrerService.checkAndSave() called');
    
    try {
      final prefs = await SharedPreferences.getInstance();
      final existingDriverId = prefs.getString('driverId') ?? '';
      final isLoggedIn = prefs.getBool('isLoggedIn') ?? false;

      if (isLoggedIn && existingDriverId.isNotEmpty) {
        debugPrint(
          '⏭️ Already logged in (driverId + isLoggedIn) - skipping referrer read',
        );
        _complete();
        return;
      }

      final existing = prefs.getString(_pendingCodeKey) ?? '';
      if (existing.isNotEmpty) {
        debugPrint('✅ Referral code already exists in cache: $existing - skipping read');
        _complete();
        return;
      }

      debugPrint('📱 Calling native getReferrer() via MethodChannel...');
      
      final String referrerString = await _channel
          .invokeMethod<String>('getReferrer')
          .timeout(
            const Duration(seconds: 6),
            onTimeout: () {
              debugPrint('⏱️ getReferrer() timed out after 6 seconds');
              return '';
            },
          ) ?? '';

      debugPrint('📦 Received referrer string from native: "$referrerString"');

      if (referrerString.isNotEmpty) {
        debugPrint('🔍 Parsing referrer: $referrerString');

        final code = _extractReferralCode(referrerString);
        debugPrint('   Extracted referral code: $code');

        if (code != null && code.length >= 4) {
          await prefs.setString(_pendingCodeKey, code);
          debugPrint('✅ Driver referral code saved to SharedPreferences: $code');
        } else {
          debugPrint(
            '⚠️ Referral code invalid or missing (length: ${code?.length ?? 0})',
          );
        }
      } else {
        debugPrint('⚠️ No referrer string received from native - app may not have been installed via referral link');
      }
    } catch (e) {
      debugPrint('❌ DriverInstallReferrer error (non-fatal): $e');
    } finally {
      _complete();
    }
  }

  static Future<void> waitUntilDone() async {
    if (!_started) {
      debugPrint('⏭️ waitUntilDone() called but service not started yet - returning immediately');
      return;
    }
    
    try {
      debugPrint('⏳ Waiting for install referrer read to complete...');
      await _readCompleter.future.timeout(const Duration(seconds: 4));
      debugPrint('✅ Install referrer read completed');
    } catch (e) {
      debugPrint('⏱️ waitUntilDone() timed out: $e');
    }
  }

  static Future<String?> consumePendingReferralCode() async {
    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString(_pendingCodeKey);
    
    if (code != null && code.isNotEmpty) {
      debugPrint('🎁 Consuming referral code: $code');
      await prefs.remove(_pendingCodeKey);
      return code;
    } else {
      debugPrint('❌ No pending referral code found in SharedPreferences');
      return null;
    }
  }

  static Future<String?> peekPendingReferralCode() async {
    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString(_pendingCodeKey);
    
    if (code != null && code.isNotEmpty) {
      debugPrint('👀 Peeking pending referral code: $code');
    } else {
      debugPrint('👀 No pending referral code in SharedPreferences');
    }
    
    return code;
  }

  static void _complete() {
    if (!_readCompleter.isCompleted) {
      _readCompleter.complete();
      debugPrint('✅ DriverInstallReferrerService completed');
    }
  }

  static String? _extractReferralCode(String rawValue) {
    if (rawValue.trim().isEmpty) return null;

    final decodedRaw = _safeDecode(rawValue.trim());

    final candidates = <String>[rawValue, decodedRaw];

    for (final candidate in candidates) {
      final params = _tryParseParams(candidate);
      final code = _pickCode(params);
      if (code != null) return code;

      final nestedReferrer = params['referrer'];
      if (nestedReferrer != null && nestedReferrer.isNotEmpty) {
        final nestedDecoded = _safeDecode(nestedReferrer);
        final nestedParams = _tryParseParams(nestedDecoded);
        final nestedCode = _pickCode(nestedParams);
        if (nestedCode != null) return nestedCode;
      }
    }

    return null;
  }

  static Map<String, String> _tryParseParams(String input) {
    try {
      if (input.contains('://')) {
        final uri = Uri.parse(input);
        if (uri.queryParameters.isNotEmpty) {
          return uri.queryParameters;
        }
      }
      return Uri.splitQueryString(input);
    } catch (_) {
      return <String, String>{};
    }
  }

  static String _safeDecode(String value) {
    try {
      return Uri.decodeComponent(value);
    } catch (_) {
      try {
        return utf8.decode(value.codeUnits, allowMalformed: true);
      } catch (_) {
        return value;
      }
    }
  }

  static String? _pickCode(Map<String, String> params) {
    for (final key in _possibleCodeKeys) {
      final value = params[key];
      if (value != null && value.trim().isNotEmpty) {
        return value.trim().toUpperCase();
      }
    }
    return null;
  }
}
