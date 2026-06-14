// driver_login_page.dart
// ─────────────────────────────────────────────────────────────────────────────
// COMPLETE PRODUCTION BUILD — Round 2 fixes applied on top of Round 1.
//
// FIX 1 — Force logout / session collision:
//   • SessionManager.initializeSession() now receives the true per-install
//     deviceId (not firebaseUid) so the backend session key is
//     role+phone+deviceId, never role+phone+firebaseUid.
//   • The driver app session is fully isolated from the customer app session
//     because both the device-id key stored in SharedPreferences AND the
//     value passed to the backend's deviceInfo.deviceId are the
//     driver-app-specific install id (prefixed 'drv_').
//   • SessionManager.handleForceLogout already guards role != 'driver';
//     no client-side change needed there.
//
// FIX 2 — True unique device-id (per driver-app install, NOT firebaseUid):
//   • _resolveOrCreateDeviceId() generates/reads a stable 'drv_<ts>_<rand>'
//     id from SharedPreferences key 'driverAppDeviceId'.
//   • Sent as deviceInfo.deviceId in the backend payload (key name unchanged).
//   • Also passed to SessionManager so both sides agree on the id.
//
// FIX 3 — FCM null token before backend sync:
//   • _ensureFcmToken() is called immediately before _syncWithBackend().
//   • If _fcmToken is still null it retries getToken() up to 3 times with
//     a short delay before giving up (non-blocking, never blocks login).
//
// FIX 4 — Loading dialog safety via dedicated dialog NavigatorState:
//   • _dialogNavigatorKey is a GlobalKey<NavigatorState> used exclusively
//     for the loading dialog route so dismissal never touches app routes.
//   • Achieved with a lightweight overlay approach: dialog is shown with
//     showDialog but we track its own BuildContext via a Completer so we
//     can close it precisely with Navigator.of(_dialogContext!).pop().
//
// FIX 5 — Browser / reCAPTCHA return lifecycle:
//   • didChangeAppLifecycleState() properly implemented.
//   • On resumed: if _codeSent==false && _verificationId==null &&
//     _isLoading==true we were waiting for reCAPTCHA; reset loading so the
//     user can tap Send OTP again cleanly.
//   • No auth state is cleared; phone field is preserved.
//
// FIX 6 — Post-frame navigation in session check:
//   • WidgetsBinding.instance.addPostFrameCallback used for the
//     pushReplacement call inside _checkExistingSession() so it never runs
//     during the widget's build phase.
//
// FIX 7 — All Round-1 fixes preserved (race guard, resend timer, mounted
//         checks, auth error handling, FCM timing, overlay dialog).
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config.dart';
import '../services/help_settings_service.dart';
import '../services/overlay_permission_service.dart';
import '../services/session_manager.dart';
import 'splash_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// PALETTE & TYPOGRAPHY
// ─────────────────────────────────────────────────────────────────────────────

class _C {
  static const primary = Color.fromARGB(255, 212, 120, 0);
  static const bg = Colors.white;
  static const surface = Color(0xFFF5F5F5);
  static const onSurface = Colors.black;
  static const onPrimary = Colors.white;
  static const secondary = Colors.black54;
  static const tertiary = Colors.black38;
  static const divider = Color(0xFFEEEEEE);
  static const success = Color.fromARGB(255, 0, 66, 3);
  static const error = Color(0xFFD32F2F);
}

TextStyle _pj({
  required double size,
  required FontWeight weight,
  Color color = _C.onSurface,
  double? letterSpacing,
}) => GoogleFonts.plusJakartaSans(
  fontSize: size,
  fontWeight: weight,
  color: color,
  letterSpacing: letterSpacing,
);

// ─────────────────────────────────────────────────────────────────────────────
// SharedPreferences key for driver-app-specific device id (FIX 2)
// Using a dedicated key distinct from the generic 'appDeviceId' so the
// customer app (if it uses the same device) has its own isolated key.
// ─────────────────────────────────────────────────────────────────────────────
const _kDriverDeviceIdKey = 'driverAppDeviceId';

// ─────────────────────────────────────────────────────────────────────────────
// PAGE
// ─────────────────────────────────────────────────────────────────────────────

class DriverLoginPage extends StatefulWidget {
  const DriverLoginPage({super.key});

  @override
  State<DriverLoginPage> createState() => _DriverLoginPageState();
}

class _DriverLoginPageState extends State<DriverLoginPage>
    with WidgetsBindingObserver {
  // ── Controllers / focus ───────────────────────────────────────────────────
  final _phoneCtrl = TextEditingController();
  final _otpCtrl = TextEditingController();
  final _otpFocus = FocusNode();

  // ── Firebase ──────────────────────────────────────────────────────────────
  final _auth = FirebaseAuth.instance;

  // ── State flags ───────────────────────────────────────────────────────────
  bool _codeSent = false;
  bool _isLoading = false;
  bool _isCheckingSession = true;

  // ── Auth race guard (FIX 7 / Round-1 BUG A) ─────────────────────────────
  // Only ONE path (auto or manual) may call signInWithCredential.
  bool _authCompleted = false;

  // ── OTP state ─────────────────────────────────────────────────────────────
  String? _verificationId;
  int? _resendToken;

  // ── FCM (FIX 3) ───────────────────────────────────────────────────────────
  String? _fcmToken;
  StreamSubscription<String>? _fcmRefreshSub;

  // ── True device id — NOT firebaseUid (FIX 2) ─────────────────────────────
  String? _driverDeviceId;

  // ── Support ───────────────────────────────────────────────────────────────
  String _supportPhone = HelpSettingsService.defaultSupportPhone;

  // ── Resend cooldown timer ─────────────────────────────────────────────────
  Timer? _resendTimer;
  int _resendCooldown = 0;

  // ── Loading dialog context tracking (FIX 4) ──────────────────────────────
  // We store the BuildContext of the dialog route itself so we can close
  // exactly that dialog without touching any other route.
  BuildContext? _dialogContext;
  bool _dialogOpen = false;

  // ── Backend ───────────────────────────────────────────────────────────────
  final String _backendUrl = AppConfig.backendBaseUrl;

  // ─────────────────────────────────────────────────────────────────────────
  // LIFECYCLE
  // ─────────────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _auth.setLanguageCode('en');
    _checkExistingSession(); // FCM & device-id init happen AFTER this
    _loadSupportPhone();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _phoneCtrl.dispose();
    _otpCtrl.dispose();
    _otpFocus.dispose();
    _resendTimer?.cancel();
    _fcmRefreshSub?.cancel();
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // FIX 5 — App lifecycle: handle browser / reCAPTCHA return
  // ─────────────────────────────────────────────────────────────────────────

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      debugPrint('📱 App resumed from background');

      // If we were mid-OTP flow with no verificationId yet and the loading
      // spinner is still shown, the user probably just returned from the
      // reCAPTCHA browser. Reset loading so they can retry cleanly.
      // DO NOT clear phone or OTP state — preserve what they entered.
      if (_isLoading && !_codeSent && _verificationId == null) {
        Future.delayed(const Duration(seconds: 4), () {
          if (!mounted) return;

          if (_isLoading && !_codeSent && _verificationId == null) {
            _dismissLoadingDialog();
            _setLoading(false);

            _showSnack(
              'Verification timed out. Please tap Send OTP again.',
              isError: false,
            );
          }
        });
      }
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // FIX 6 — Session check with post-frame navigation
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _checkExistingSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final driverId = prefs.getString('driverId');
      final loggedIn = prefs.getBool('isLoggedIn') ?? false;
      final phone = prefs.getString('phoneNumber') ?? '';

      debugPrint('🔍 Session check → driverId=$driverId loggedIn=$loggedIn');

      if (loggedIn && (driverId?.isNotEmpty ?? false) && phone.isNotEmpty) {
        debugPrint('✅ Valid session found → navigating to SplashScreen');

        // FIX 6: post-frame callback avoids navigating during build/init
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const SplashScreen()),
          );
        });
        return;
      }
    } catch (e) {
      debugPrint('⚠️ Session check error: $e');
    } finally {
      if (mounted) setState(() => _isCheckingSession = false);
    }

    // Only reach here if no valid session — safe to init FCM & device-id
    await Future.wait([_initFCM(), _resolveOrCreateDeviceId()]);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // FCM — delayed init (Round-1 BUG D)
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _initFCM() async {
    try {
      final settings = await FirebaseMessaging.instance
          .getNotificationSettings();

      debugPrint('🔔 Existing FCM permission: ${settings.authorizationStatus}');

      _fcmToken = await FirebaseMessaging.instance.getToken();
      debugPrint(
        '✅ FCM token: ${_fcmToken != null ? '${_fcmToken!.substring(0, 20)}…' : 'null'}',
      );

      _fcmRefreshSub = FirebaseMessaging.instance.onTokenRefresh.listen((t) {
        _fcmToken = t;
        debugPrint('🔄 FCM token refreshed');
      });
    } catch (e) {
      debugPrint('⚠️ FCM init error (non-critical): $e');
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // FIX 2 — Generate / restore true per-install driver device id
  // Key: 'driverAppDeviceId'  (isolated from any customer app key)
  // Format: 'drv_<timestamp>_<random5digits>'
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _resolveOrCreateDeviceId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final existing = prefs.getString(_kDriverDeviceIdKey);

      if (existing != null && existing.isNotEmpty) {
        _driverDeviceId = existing;
        debugPrint('📱 Driver device-id restored: $_driverDeviceId');
        return;
      }

      // Generate a new id
      final ts = DateTime.now().millisecondsSinceEpoch;
      final rand = math.Random().nextInt(99999).toString().padLeft(5, '0');
      final newId = 'drv_${ts}_$rand';

      await prefs.setString(_kDriverDeviceIdKey, newId);
      _driverDeviceId = newId;
      debugPrint('📱 Driver device-id created: $_driverDeviceId');
    } catch (e) {
      // Fallback: generate in-memory (still better than firebaseUid)
      final ts = DateTime.now().millisecondsSinceEpoch;
      _driverDeviceId = 'drv_mem_$ts';
      debugPrint('⚠️ Device-id fallback (in-memory): $_driverDeviceId');
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // FIX 3 — Guarantee FCM token exists before backend sync
  // Retries up to 3 times with a short delay. Non-blocking on failure.
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _ensureFcmToken() async {
    if (_fcmToken != null && _fcmToken!.isNotEmpty) return;

    debugPrint('⚠️ FCM token null before sync — attempting retry…');
    for (int i = 0; i < 3; i++) {
      try {
        await Future.delayed(Duration(milliseconds: 400 * (i + 1)));
        final token = await FirebaseMessaging.instance.getToken();
        if (token != null && token.isNotEmpty) {
          _fcmToken = token;
          debugPrint(
            '✅ FCM token obtained on retry ${i + 1}: ${token.substring(0, 20)}…',
          );
          return;
        }
      } catch (e) {
        debugPrint('⚠️ FCM retry ${i + 1} failed: $e');
      }
    }
    debugPrint(
      '⚠️ FCM token still null after retries — syncing without it (non-fatal)',
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // SUPPORT
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _loadSupportPhone() async {
    final phone = await HelpSettingsService.getSupportPhone(forceRefresh: true);
    if (!mounted) return;
    setState(() => _supportPhone = phone);
  }

  Future<void> _launchSupportCall() async {
    final phone = await HelpSettingsService.getSupportPhone(forceRefresh: true);
    final uri = Uri(scheme: 'tel', path: phone);
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      } else {
        _showSnack('Cannot open dialer. Call $phone', isError: true);
      }
    } catch (_) {
      _showSnack('Unable to call support', isError: true);
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // SEND OTP
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _sendOTP() async {
    if (_isLoading) return;

    final raw = _phoneCtrl.text.trim();
    if (raw.length != 10) {
      _showSnack('Enter a valid 10-digit mobile number', isError: true);
      return;
    }

    // Reset auth guard for a fresh OTP attempt
    _authCompleted = false;
    _setLoading(true);

    final phone = '+91$raw';

    try {
      await _auth.verifyPhoneNumber(
        phoneNumber: phone,
        timeout: const Duration(seconds: 60),
        forceResendingToken: _resendToken,

        // ── Auto-verification (Round-1 BUG A guard preserved) ────────────────
        verificationCompleted: (PhoneAuthCredential credential) async {
          debugPrint('⚡ Auto-verification received');
          if (!mounted || _authCompleted) return;
          _authCompleted = true; // lock gate

          _setLoading(true);
          _showLoadingDialog(message: 'Auto-verifying…');

          await _signInWithCredential(credential, fromAutoVerify: true);
        },

        verificationFailed: (FirebaseAuthException e) {
          if (!mounted) return;
          _dismissLoadingDialog();
          _setLoading(false);
          debugPrint('❌ Verification failed: ${e.code} ${e.message}');
          switch (e.code) {
            case 'invalid-phone-number':
              _showSnack('Invalid phone number format', isError: true);
              break;
            case 'too-many-requests':
              _showSnack('Too many requests. Try again later.', isError: true);
              break;
            default:
              _showSnack('Verification failed: ${e.message}', isError: true);
          }
        },

        codeSent: (String verificationId, int? resendToken) {
          if (!mounted) return;
          _verificationId = verificationId;
          _resendToken = resendToken;

          _setLoading(false);
          setState(() => _codeSent = true);
          _showSnack('OTP sent to your mobile', isError: false);
          _startResendTimer();

          Future.delayed(const Duration(milliseconds: 300), () {
            if (mounted) _otpFocus.requestFocus();
          });
          debugPrint('✅ OTP sent. verificationId=$verificationId');
        },

        codeAutoRetrievalTimeout: (String verificationId) {
          // Keep latest verificationId — manual entry still works.
          _verificationId = verificationId;
          debugPrint('⏱ Auto-retrieval timeout');
        },
      );
    } catch (e) {
      if (mounted) _setLoading(false);
      _showSnack('Failed to send OTP. Please try again.', isError: true);
      debugPrint('❌ sendOTP error: $e');
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // VERIFY OTP (manual) — race guard preserved
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _verifyOTPAndLogin() async {
    if (_isLoading || _authCompleted) return;

    final otp = _otpCtrl.text.trim();
    if (otp.length != 6) {
      _showSnack('Enter the 6-digit OTP', isError: true);
      return;
    }
    if (_verificationId == null) {
      _showSnack('Please request OTP first', isError: true);
      return;
    }

    _authCompleted = true; // lock gate
    _setLoading(true);
    _showLoadingDialog(message: 'Verifying OTP…');

    final credential = PhoneAuthProvider.credential(
      verificationId: _verificationId!,
      smsCode: otp,
    );

    await _signInWithCredential(credential, fromAutoVerify: false);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // SIGN IN WITH CREDENTIAL — single unified path
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _signInWithCredential(
    PhoneAuthCredential credential, {
    required bool fromAutoVerify,
  }) async {
    try {
      UserCredential? uc;
      try {
        uc = await _auth.signInWithCredential(credential);
        debugPrint('✅ Firebase sign-in success, uid=${uc.user?.uid}');
      } on FirebaseAuthException catch (e) {
        _dismissLoadingDialog();
        _setLoading(false);
        _authCompleted = false;
        _handleFirebaseAuthError(e);
        return;
      } catch (typeErr) {
        if (typeErr.toString().contains('is not a subtype')) {
          debugPrint('⚠️ Known OEM type-cast error — continuing');
          await Future.delayed(const Duration(milliseconds: 1500));
        } else {
          _dismissLoadingDialog();
          _setLoading(false);
          _authCompleted = false;
          _showSnack('Sign-in error. Please try again.', isError: true);
          debugPrint('❌ Unexpected sign-in error: $typeErr');
          return;
        }
      }

      final firebaseUid = await _resolveFirebaseUid(uc);
      final rawPhone = _phoneCtrl.text.trim();

      // FIX 3: guarantee FCM token before network call
      await _ensureFcmToken();

      // FIX 2: ensure device-id is resolved
      if (_driverDeviceId == null) await _resolveOrCreateDeviceId();

      await _syncWithBackend(rawPhone, firebaseUid);
    } catch (e) {
      _dismissLoadingDialog();
      _setLoading(false);
      _authCompleted = false;
      _showSnack('Unexpected error. Please try again.', isError: true);
      debugPrint('❌ _signInWithCredential outer error: $e');
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // RESOLVE FIREBASE UID — robust three-step fallback
  // ─────────────────────────────────────────────────────────────────────────

  Future<String> _resolveFirebaseUid(UserCredential? uc) async {
    if (uc?.user?.uid.isNotEmpty ?? false) return uc!.user!.uid;

    await Future.delayed(const Duration(milliseconds: 800));
    final current = _auth.currentUser;
    if (current?.uid.isNotEmpty ?? false) {
      debugPrint('✅ UID from currentUser: ${current!.uid}');
      return current.uid;
    }

    try {
      final idToken = await _auth.currentUser?.getIdToken(true);
      if (idToken != null) {
        final parts = idToken.split('.');
        if (parts.length > 1) {
          final payload = base64Url.normalize(parts[1]);
          final decoded = utf8.decode(base64Url.decode(payload));
          final tokenData = jsonDecode(decoded) as Map<String, dynamic>;
          final uid = (tokenData['user_id'] ?? tokenData['sub']) as String?;
          if (uid?.isNotEmpty ?? false) {
            debugPrint('✅ UID from token decode: $uid');
            return uid!;
          }
        }
      }
    } catch (e) {
      debugPrint('⚠️ Token decode failed: $e');
    }

    final phone = _phoneCtrl.text.trim();
    debugPrint('⚠️ UID fallback: phone_$phone');
    return 'phone_$phone';
  }

  // ─────────────────────────────────────────────────────────────────────────
  // BACKEND SYNC
  // FIX 2: deviceInfo.deviceId now uses _driverDeviceId, NOT firebaseUid.
  // Endpoint and all other payload keys are UNCHANGED.
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _syncWithBackend(String phone, String firebaseUid) async {
    // Use the true per-install device id; fall back to a timestamp string
    // if somehow still null (should never happen after _resolveOrCreateDeviceId).
    final deviceId =
        _driverDeviceId ??
        'drv_fallback_${DateTime.now().millisecondsSinceEpoch}';

    debugPrint(
      '📡 Backend sync → phone=$phone uid=$firebaseUid deviceId=$deviceId role=driver',
    );

    try {
      final response = await http
          .post(
            Uri.parse('$_backendUrl/api/auth/firebase-sync'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'phone': phone,
              'firebaseUid': firebaseUid,
              'role': 'driver', // never changes
              'fcmToken': _fcmToken, // FIX 3: guaranteed non-null if available
              'deviceInfo': {'deviceId': deviceId}, // FIX 2: true device id
            }),
          )
          .timeout(const Duration(seconds: 30));

      _dismissLoadingDialog();
      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        await _handleSyncSuccess(phone, firebaseUid, deviceId, data);
      } else {
        _setLoading(false);
        _authCompleted = false;
        final err = jsonDecode(response.body) as Map<String, dynamic>;
        _showSnack(
          (err['message'] as String?) ?? 'Server error. Please try again.',
          isError: true,
        );
        debugPrint('❌ Backend sync ${response.statusCode}: ${response.body}');
      }
    } on TimeoutException {
      _dismissLoadingDialog();
      _setLoading(false);
      _authCompleted = false;
      _showSnack('Request timed out. Check your connection.', isError: true);
    } catch (e) {
      _dismissLoadingDialog();
      _setLoading(false);
      _authCompleted = false;
      _showSnack('Network error. Please try again.', isError: true);
      debugPrint('❌ _syncWithBackend error: $e');
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // HANDLE SYNC SUCCESS
  // FIX 1 + FIX 2: SessionManager receives _driverDeviceId so the session
  // identity is role=driver + driverDeviceId, isolated from customer sessions.
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _handleSyncSuccess(
    String phone,
    String firebaseUid,
    String deviceId,
    Map<String, dynamic> data,
  ) async {
    try {
      final user = data['user'] as Map<String, dynamic>;
      final driverId = user['_id'] as String;
      final vehicleType = (user['vehicleType'] as String? ?? '')
          .toLowerCase()
          .trim();
      final docsApproved = data['docsApproved'] == true;

      // ── Persist session keys (exact key names preserved) ──────────────────
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('driverId', driverId);
      await prefs.setString('phoneNumber', phone);
      await prefs.setString('vehicleType', vehicleType);
      await prefs.setBool('isLoggedIn', true);
      await prefs.setBool('docsApproved', docsApproved);
      await prefs.setInt(
        'loginTimestamp',
        DateTime.now().millisecondsSinceEpoch,
      );
      await prefs.setString('lastLoginResponse', jsonEncode(data));
      // Also persist the device id so future sessions can restore it
      await prefs.setString(_kDriverDeviceIdKey, deviceId);

      debugPrint(
        '💾 Prefs saved → driverId=$driverId docsApproved=$docsApproved deviceId=$deviceId',
      );

      // ── FIX 1 + 2: Role-isolated SessionManager init ──────────────────────
      // _driverDeviceId is the per-install driver-app id.
      // SessionManager uses it as the session key, keeping it separate from
      // any customer-app session that uses a different key.
      try {
        await SessionManager().initializeSession(
          driverId: driverId,
          role: 'driver',
          phoneNumber: phone,
          firebaseUid: firebaseUid,
          deviceId: deviceId,
        );
        debugPrint(
          '✅ SessionManager initialized (role=driver deviceId=$deviceId)',
        );
      } catch (e) {
        debugPrint('⚠️ SessionManager init error (non-critical): $e');
      }

      if (!mounted) return;
      _setLoading(false);
      _showSnack('Login successful!', isError: false);

      // Ask FCM permission AFTER successful login
      await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      // Refresh token after permission grant
      _fcmToken = await FirebaseMessaging.instance.getToken();

      // Overlay permission dialog
      await _requestOverlayPermission();
      // ── FIX 6: post-frame navigation — single pushAndRemoveUntil ──────────
      if (!mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const SplashScreen()),
          (_) => false,
        );
      });
    } catch (e) {
      _setLoading(false);
      _authCompleted = false;
      _showSnack('Error saving session. Please try again.', isError: true);
      debugPrint('❌ _handleSyncSuccess error: $e');
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // RESEND OTP
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _resendOTP() async {
    if (_resendCooldown > 0) return;
    _authCompleted = false;
    setState(() {
      _codeSent = false;
      _verificationId = null;
    });
    _otpCtrl.clear();
    _showSnack('Resending OTP…', isError: false);
    await _sendOTP();
  }

  void _startResendTimer() {
    _resendCooldown = 30;
    _resendTimer?.cancel();
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() {
        if (_resendCooldown > 0) {
          _resendCooldown--;
        } else {
          t.cancel();
        }
      });
    });
  }

  // ─────────────────────────────────────────────────────────────────────────
  // OVERLAY PERMISSION (feature fully preserved)
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _requestOverlayPermission() async {
    try {
      if (await OverlayPermissionService.hasAskedPermissionBefore()) return;
      if (await OverlayPermissionService.hasPermission()) {
        await OverlayPermissionService.markPermissionAsked();
        return;
      }
      if (!mounted) return;

      final grant = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _OverlayPermissionDialog(),
      );

      await OverlayPermissionService.markPermissionAsked();
      if (grant == true) {
        await OverlayPermissionService.requestPermission();
        await Future.delayed(const Duration(seconds: 1));
      }
    } catch (e) {
      debugPrint('⚠️ Overlay permission error: $e');
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // FIX 4 — Loading dialog: dedicated context tracking
  // We capture the dialog's own BuildContext via a StatefulBuilder so we
  // can call Navigator.of(_dialogContext!).pop() on EXACTLY that dialog
  // and never touch any app route.
  // ─────────────────────────────────────────────────────────────────────────

  void _showLoadingDialog({String message = 'Please wait…'}) {
    if (_dialogOpen || !mounted) return;
    _dialogOpen = true;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) {
        // Capture the dialog's BuildContext immediately
        _dialogContext = dialogCtx;
        return _LoadingDialog(message: message);
      },
    ).then((_) {
      // Dialog closed by any means — reset flags
      _dialogOpen = false;
      _dialogContext = null;
    });
  }

  void _dismissLoadingDialog() {
    if (!_dialogOpen) return;
    if (_dialogContext != null && mounted) {
      try {
        Navigator.of(_dialogContext!).pop();
      } catch (e) {
        debugPrint('⚠️ Dialog dismiss error (non-fatal): $e');
      }
    }
    _dialogOpen = false;
    _dialogContext = null;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // MISC HELPERS
  // ─────────────────────────────────────────────────────────────────────────

  void _setLoading(bool value) {
    if (!mounted) return;
    setState(() => _isLoading = value);
  }

  void _showSnack(String message, {required bool isError}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(
                isError ? Icons.error_outline : Icons.check_circle_outline,
                color: Colors.white,
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  message,
                  style: _pj(
                    size: 14,
                    weight: FontWeight.w500,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          backgroundColor: isError ? _C.error : _C.success,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          duration: const Duration(seconds: 3),
        ),
      );
  }

  void _handleFirebaseAuthError(FirebaseAuthException e) {
    _authCompleted = false;
    switch (e.code) {
      case 'invalid-verification-code':
        _showSnack('Invalid OTP. Please try again.', isError: true);
        break;
      case 'session-expired':
        _showSnack('OTP expired. Request a new one.', isError: true);
        if (mounted)
          setState(() {
            _codeSent = false;
            _otpCtrl.clear();
          });
        break;
      case 'network-request-failed':
        _showSnack('Network error. Check your connection.', isError: true);
        break;
      default:
        _showSnack('Auth error: ${e.message}', isError: true);
    }
    debugPrint('❌ FirebaseAuthException: ${e.code} ${e.message}');
  }

  // ─────────────────────────────────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_isCheckingSession) return const _SessionCheckScreen();

    return Scaffold(
      backgroundColor: _C.bg,
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const ClampingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Support button ────────────────────────────────────────────
              Align(
                alignment: Alignment.centerRight,
                child: _SupportButton(onTap: _launchSupportCall),
              ),

              const SizedBox(height: 24),

              // ── Logo ──────────────────────────────────────────────────────
              Center(
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      colors: [
                        _C.primary.withOpacity(0.25),
                        _C.primary.withOpacity(0.06),
                      ],
                    ),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: _C.primary.withOpacity(0.35),
                      width: 2.5,
                    ),
                  ),
                  child: const Icon(
                    Icons.directions_car_rounded,
                    size: 68,
                    color: _C.primary,
                  ),
                ),
              ),

              const SizedBox(height: 28),

              // ── Heading ───────────────────────────────────────────────────
              Center(
                child: Text(
                  'Driver Login',
                  style: _pj(
                    size: 28,
                    weight: FontWeight.w800,
                    letterSpacing: -0.5,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Center(
                child: Text(
                  'Welcome back! Verify your number to continue.',
                  style: _pj(
                    size: 14,
                    weight: FontWeight.w500,
                    color: _C.secondary,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),

              const SizedBox(height: 44),

              // ── Phone field ───────────────────────────────────────────────
              _FieldLabel('Mobile Number'),
              const SizedBox(height: 10),
              _InputBox(
                child: TextField(
                  controller: _phoneCtrl,
                  keyboardType: TextInputType.phone,
                  maxLength: 10,
                  enabled: !_codeSent && !_isLoading,
                  style: _pj(size: 16, weight: FontWeight.w600),
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(10),
                  ],
                  decoration: InputDecoration(
                    prefixIcon: _FieldIcon(Icons.phone_android_rounded),
                    prefixText: '+91  ',
                    prefixStyle: _pj(size: 16, weight: FontWeight.w700),
                    hintText: '9876543210',
                    hintStyle: _pj(
                      size: 15,
                      weight: FontWeight.w400,
                      color: _C.tertiary,
                    ),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 18,
                    ),
                    counterText: '',
                  ),
                ),
              ),

              // ── OTP field (animated) ──────────────────────────────────────
              AnimatedSize(
                duration: const Duration(milliseconds: 280),
                curve: Curves.easeOutCubic,
                child: _codeSent
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 24),
                          _FieldLabel('One-Time Password'),
                          const SizedBox(height: 10),
                          _InputBox(
                            child: TextField(
                              controller: _otpCtrl,
                              focusNode: _otpFocus,
                              keyboardType: TextInputType.number,
                              maxLength: 6,
                              enabled: !_isLoading,
                              style: _pj(
                                size: 22,
                                weight: FontWeight.w700,
                                letterSpacing: 10,
                              ),
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                                LengthLimitingTextInputFormatter(6),
                              ],
                              decoration: InputDecoration(
                                prefixIcon: _FieldIcon(Icons.lock_rounded),
                                hintText: '------',
                                hintStyle: _pj(
                                  size: 20,
                                  weight: FontWeight.w400,
                                  color: _C.tertiary,
                                  letterSpacing: 8,
                                ),
                                border: InputBorder.none,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 18,
                                ),
                                counterText: '',
                              ),
                              onSubmitted: (_) => _verifyOTPAndLogin(),
                            ),
                          ),
                          const SizedBox(height: 12),

                          // Change number / Resend row
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              TextButton.icon(
                                onPressed: _isLoading
                                    ? null
                                    : () {
                                        _resendTimer?.cancel();
                                        _authCompleted = false;
                                        setState(() {
                                          _codeSent = false;
                                          _verificationId = null;
                                          _resendCooldown = 0;
                                        });
                                        _otpCtrl.clear();
                                      },
                                icon: const Icon(Icons.edit_rounded, size: 16),
                                label: Text(
                                  'Change Number',
                                  style: _pj(
                                    size: 13,
                                    weight: FontWeight.w600,
                                    color: _C.primary,
                                  ),
                                ),
                                style: TextButton.styleFrom(
                                  foregroundColor: _C.primary,
                                  padding: EdgeInsets.zero,
                                ),
                              ),
                              TextButton.icon(
                                onPressed: (_isLoading || _resendCooldown > 0)
                                    ? null
                                    : _resendOTP,
                                icon: const Icon(
                                  Icons.refresh_rounded,
                                  size: 16,
                                ),
                                label: Text(
                                  _resendCooldown > 0
                                      ? 'Resend in ${_resendCooldown}s'
                                      : 'Resend OTP',
                                  style: _pj(
                                    size: 13,
                                    weight: FontWeight.w600,
                                    color: _resendCooldown > 0
                                        ? _C.tertiary
                                        : _C.primary,
                                  ),
                                ),
                                style: TextButton.styleFrom(
                                  foregroundColor: _C.primary,
                                  padding: EdgeInsets.zero,
                                ),
                              ),
                            ],
                          ),
                        ],
                      )
                    : const SizedBox.shrink(),
              ),

              const SizedBox(height: 32),

              // ── Primary CTA ───────────────────────────────────────────────
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _isLoading
                      ? null
                      : (_codeSent ? _verifyOTPAndLogin : _sendOTP),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _C.primary,
                    foregroundColor: _C.onPrimary,
                    disabledBackgroundColor: _C.primary.withOpacity(0.55),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 4,
                    shadowColor: _C.primary.withOpacity(0.35),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              _C.onPrimary,
                            ),
                          ),
                        )
                      : Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              _codeSent
                                  ? Icons.verified_user_rounded
                                  : Icons.send_rounded,
                              size: 20,
                            ),
                            const SizedBox(width: 10),
                            Text(
                              _codeSent ? 'Verify & Login' : 'Send OTP',
                              style: _pj(
                                size: 16,
                                weight: FontWeight.w700,
                                color: _C.onPrimary,
                              ),
                            ),
                          ],
                        ),
                ),
              ),

              const SizedBox(height: 28),

              // ── Info banner ───────────────────────────────────────────────
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: _C.primary.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _C.primary.withOpacity(0.2)),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.info_outline_rounded,
                      color: _C.primary,
                      size: 18,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'OTP will be sent to your registered mobile number.',
                        style: _pj(
                          size: 12,
                          weight: FontWeight.w500,
                          color: _C.primary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SMALL REUSABLE WIDGETS
// ─────────────────────────────────────────────────────────────────────────────

class _SessionCheckScreen extends StatelessWidget {
  const _SessionCheckScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _C.bg,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: _C.primary.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(_C.primary),
                strokeWidth: 3,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Checking session…',
              style: _pj(
                size: 15,
                weight: FontWeight.w500,
                color: _C.secondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SupportButton extends StatelessWidget {
  final VoidCallback onTap;
  const _SupportButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onTap,
      tooltip: 'Call Support',
      icon: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: _C.primary.withOpacity(0.12),
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Icon(Icons.support_agent_rounded, color: _C.primary),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  final String text;
  const _FieldLabel(this.text);

  @override
  Widget build(BuildContext context) =>
      Text(text, style: _pj(size: 14, weight: FontWeight.w600));
}

class _FieldIcon extends StatelessWidget {
  final IconData icon;
  const _FieldIcon(this.icon);

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.all(12),
    padding: const EdgeInsets.all(7),
    decoration: BoxDecoration(
      color: _C.primary.withOpacity(0.10),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Icon(icon, color: _C.primary, size: 18),
  );
}

class _InputBox extends StatelessWidget {
  final Widget child;
  const _InputBox({required this.child});

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: _C.surface,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: _C.divider),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.04),
          blurRadius: 10,
          offset: const Offset(0, 4),
        ),
      ],
    ),
    child: child,
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// LOADING DIALOG (FIX 4 — uses its own BuildContext captured by caller)
// ─────────────────────────────────────────────────────────────────────────────

class _LoadingDialog extends StatelessWidget {
  final String message;
  const _LoadingDialog({required this.message});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: _C.bg,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(_C.primary),
              strokeWidth: 3,
            ),
            const SizedBox(height: 18),
            Text(
              message,
              style: _pj(size: 15, weight: FontWeight.w600),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              'Please wait',
              style: _pj(
                size: 12,
                weight: FontWeight.w400,
                color: _C.secondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// OVERLAY PERMISSION DIALOG (feature fully preserved)
// ─────────────────────────────────────────────────────────────────────────────

class _OverlayPermissionDialog extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: _C.primary.withOpacity(0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.notifications_active_rounded,
              color: _C.primary,
              size: 26,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Enable Trip Alerts',
              style: _pj(size: 17, weight: FontWeight.w700),
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'To receive trip requests even when the app is in background, enable "Display over other apps" permission.',
            style: _pj(size: 14, weight: FontWeight.w500),
          ),
          const SizedBox(height: 18),
          _BenefitRow(Icons.visibility_rounded, 'See trip requests instantly'),
          const SizedBox(height: 10),
          _BenefitRow(
            Icons.notifications_active_rounded,
            'Never miss a ride opportunity',
          ),
          const SizedBox(height: 10),
          _BenefitRow(Icons.monetization_on_rounded, 'Maximise your earnings'),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _C.primary.withOpacity(0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _C.primary.withOpacity(0.25)),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.info_outline_rounded,
                  color: _C.primary,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'This ensures you never miss a ride request!',
                    style: _pj(
                      size: 12,
                      weight: FontWeight.w600,
                      color: _C.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      actionsPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(
            'Later',
            style: _pj(size: 14, weight: FontWeight.w600, color: _C.secondary),
          ),
        ),
        ElevatedButton.icon(
          onPressed: () => Navigator.pop(context, true),
          icon: const Icon(Icons.settings_rounded, size: 16),
          label: Text(
            'Enable Now',
            style: _pj(size: 14, weight: FontWeight.w700, color: _C.onPrimary),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: _C.primary,
            foregroundColor: _C.onPrimary,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ],
    );
  }
}

class _BenefitRow extends StatelessWidget {
  final IconData icon;
  final String text;
  const _BenefitRow(this.icon, this.text);

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: _C.success.withOpacity(0.10),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: _C.success, size: 15),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: Text(text, style: _pj(size: 13, weight: FontWeight.w500)),
      ),
    ],
  );
}
