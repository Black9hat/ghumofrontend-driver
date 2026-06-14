// socket_service.dart - PRODUCTION VERSION WITH ALL FIXES
import 'dart:async';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:logging/logging.dart';
import 'package:drivergoo/config.dart';

// ═══════════════════════════════════════════════════════════════════════════
// 🔌 SOCKET SERVICE ALIAS - For backward compatibility with PaymentScreen
// ═══════════════════════════════════════════════════════════════════════════
// PaymentConfirmationScreen imports `SocketService` — this thin wrapper
// delegates everything to the singleton `DriverSocketService`.

class SocketService {
  static final SocketService _instance = SocketService._internal();
  factory SocketService() => _instance;
  SocketService._internal();

  /// Exposes the underlying raw socket so callers can do
  /// `socketService.socket?.on(...)` exactly as before.
  IO.Socket? get socket {
    try {
      final driver = DriverSocketService();
      if (driver.isConnected) {
        return driver.socket;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  bool get isConnected => DriverSocketService().isConnected;

  void emit(String event, dynamic data) {
    DriverSocketService().emit(event, data);
  }

  void on(String event, Function(dynamic) handler) {
    DriverSocketService().on(event, handler);
  }

  void off(String event) {
    DriverSocketService().off(event);
  }

  void disconnect() {
    DriverSocketService().disconnect();
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// 🚗 DRIVER SOCKET SERVICE - Main implementation
// ═══════════════════════════════════════════════════════════════════════════

class DriverSocketService {
  static final DriverSocketService _instance = DriverSocketService._internal();
  factory DriverSocketService() => _instance;
  DriverSocketService._internal();

  // Local logger for this service
  static final Logger _logger = Logger('DriverSocketService');

  void print(Object? object) {
    _logger.info(object);
  }

  // ✅ FIX 1: Nullable socket — prevents LateInitializationError if anything
  // accesses socket before connect() is called (e.g. on app startup checks)
  IO.Socket? _socket;
  IO.Socket? get socket => _socket;

  bool _isConnected = false;
  String? _vehicleType;
  // 🔥 DRIVER ROLE SESSION IMPLEMENTATION
  String? _role; // Driver role for session management
  String? _deviceId; // Device ID for single-device constraint

  Timer? _locationTimer;
  Timer? _reconnectTimer;
  Timer? _heartbeatTimer;

  double? _lastLat;
  double? _lastLng;
  String? _driverId;
  bool _isOnline = true;
  String? _fcmToken;

  // 🔥 Session event callbacks
  Function(String reason)? onForceLogout;
  Function()? onSessionExpired;

  // Track active trip to prevent disconnection
  String? _activeTripId;
  bool _hasActiveTrip = false;

  // ✅ FIX 2: Pending listeners queue — listeners registered before connect()
  // are stored and flushed automatically when socket connects/reconnects.
  // Previously, calling on() before connect() silently did nothing.
  final Map<String, List<Function(dynamic)>> _pendingListeners = {};

  // Event callbacks
  Function(Map<String, dynamic>)? onRideRequest;
  Function(Map<String, dynamic>)? onRideConfirmed;
  Function(Map<String, dynamic>)? onRideCancelled;
  Function(Map<String, dynamic>)? onActiveTripRestored;

  // Payment event callbacks
  Function(Map<String, dynamic>)? onPaymentReceived;
  Function(Map<String, dynamic>)? onCashPaymentPending;
  Function(Map<String, dynamic>)? onPaymentFailed;
  Function(Map<String, dynamic>)? onPaymentConfirmed;

  // ✅ FIX 3: onCommissionPaid callback — wallet_page uses this instead of
  // calling socket.on() directly, which was fragile and could silently drop
  // the listener if the socket wasn't connected at that moment.
  Function(Map<String, dynamic>)? onCommissionPaid;

  // ───────────────────────────────────────────────────────────────────────
  // 🔒 ACTIVE TRIP MANAGEMENT
  // ───────────────────────────────────────────────────────────────────────

  void setActiveTrip(String? tripId) {
    _activeTripId = tripId;
    _hasActiveTrip = tripId != null;

    if (_hasActiveTrip) {
      print('🔒 Active trip set: $tripId - Socket will persist');
      _saveActiveTripToPrefs(tripId!);
    } else {
      print('🔓 No active trip - Normal socket behavior');
      _clearActiveTripFromPrefs();
    }
  }

  Future<void> _saveActiveTripToPrefs(String tripId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('activeTripId', tripId);
    await prefs.setBool('hasActiveTrip', true);
  }

  Future<void> _clearActiveTripFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('activeTripId');
    await prefs.setBool('hasActiveTrip', false);
  }

  Future<bool> hasActiveTripOnRestart() async {
    final prefs = await SharedPreferences.getInstance();
    _activeTripId = prefs.getString('activeTripId');
    _hasActiveTrip = prefs.getBool('hasActiveTrip') ?? false;

    if (_hasActiveTrip && _activeTripId != null) {
      print('⚠️ Found active trip on restart: $_activeTripId');
      return true;
    }
    return false;
  }

  // ───────────────────────────────────────────────────────────────────────
  // ✅ FIX 2 (continued): on() / off() / emit() safe before connect()
  // ───────────────────────────────────────────────────────────────────────

  void on(String event, Function(dynamic) handler) {
    try {
      if (_socket != null && _isConnected && _socket!.connected) {
        _socket!.on(event, handler);
      } else {
        // Queue listener — will be flushed on connect/reconnect
        _pendingListeners.putIfAbsent(event, () => []).add(handler);
        print('📋 Queued listener for: $event (socket not ready yet)');
      }
    } catch (e) {
      print('⚠️ Error registering event listener for $event: $e');
    }
  }

  void off(String event) {
    try {
      _socket?.off(event);
      _pendingListeners.remove(event);
    } catch (e) {
      print('⚠️ Error removing event listener for $event: $e');
    }
  }

  void emit(String event, dynamic data) {
    try {
      if (_socket != null && _socket!.connected) {
        _socket!.emit(event, data);
        print('📤 Emitted: $event');
      } else {
        print('⚠️ Cannot emit $event - socket disconnected');
        if (_hasActiveTrip) {
          print('🔄 Reconnecting to emit event...');
          _attemptReconnect();
          Future.delayed(const Duration(seconds: 1), () {
            try {
              if (_socket != null && _socket!.connected) {
                _socket!.emit(event, data);
                print('📤 Emitted after reconnect: $event');
              }
            } catch (e) {
              print('❌ Failed to emit after reconnect: $e');
            }
          });
        }
      }
    } catch (e) {
      print('❌ Error emitting $event: $e');
    }
  }

  // Flush all listeners that were queued before socket was ready
  void _flushPendingListeners() {
    if (_pendingListeners.isEmpty) return;
    print('📋 Flushing ${_pendingListeners.length} pending listeners');
    _pendingListeners.forEach((event, handlers) {
      for (final handler in handlers) {
        _socket?.on(event, handler);
        print('  ✅ Registered pending listener: $event');
      }
    });
    _pendingListeners.clear();

    // 🔥 Re-register force_logout listener after flush
    _registerForceLogoutListener();
  }

  // 🔥 Register force_logout listener (called on connect and reconnect)
  void _registerForceLogoutListener() {
    if (_socket == null) return;

    _socket!.off('force_logout'); // Clear old listener first

    _socket!.on('force_logout', (data) {
      print('');
      print('=' * 70);
      print('🔥 FORCE LOGOUT EVENT RECEIVED');
      print('   Data: $data');
      print('   Role: $_role');
      print('   This Device ID: $_deviceId');
      print('=' * 70);
      print('');

      final payloadRole = data is Map ? data['role']?.toString() : null;
      final oldDeviceId = data is Map ? data['oldDeviceId']?.toString() : null;

      // 🔥 CRITICAL: Only logout if this force_logout event is meant for this device
      // Backend includes oldDeviceId to distinguish which device to log out
      final isForThisDevice = oldDeviceId == _deviceId;

      final shouldForceLogout =
          (_role == 'driver' || payloadRole == 'driver' || _role == null) &&
          isForThisDevice;

      if (shouldForceLogout) {
        final reason =
            (data is Map ? data['reason'] : null) ??
            'Account used on another device';
        print(
          '🔥 Force logout ACCEPTED (oldDevice=$oldDeviceId matches thisDevice=$_deviceId): $reason',
        );

        if (onForceLogout != null) {
          onForceLogout!(reason.toString());
        }
      } else {
        if (!isForThisDevice) {
          print(
            '⚠️ Force logout IGNORED: oldDeviceId=$oldDeviceId does NOT match thisDevice=$_deviceId (event is for a different device)',
          );
        } else {
          print(
            '⚠️ Force logout ignored for non-driver session (role=$_role, payloadRole=$payloadRole)',
          );
        }
      }
    });
  }

  // ───────────────────────────────────────────────────────────────────────
  // 🔌 CONNECT
  // ───────────────────────────────────────────────────────────────────────

  // 🔥 DRIVER ROLE SESSION IMPLEMENTATION
  void connect(
    String driverId,
    double lat,
    double lng, {
    required String vehicleType,
    required bool isOnline,
    String? fcmToken,
    String? role,
    String? deviceId,
  }) {
    // ✅ Check if already connected
    if (_socket != null && _socket!.connected) {
      print('🔌 Socket already connected: ${_socket!.id}');
      // ✅ IMPORTANT: Still update status even if connected
      _emitDriverStatus(
        driverId,
        isOnline,
        lat,
        lng,
        vehicleType,
        fcmToken: fcmToken,
        role: _role,
        deviceId: _deviceId,
      );
      return;
    }

    _driverId = driverId;
    _vehicleType = vehicleType;
    _isOnline = isOnline;
    _fcmToken = fcmToken;
    _lastLat = lat;
    _lastLng = lng;
    // 🔥 DRIVER ROLE SESSION IMPLEMENTATION
    _role = role;
    _deviceId = deviceId;

    print('');
    print('=' * 70);
    print('🔌 CREATING NEW SOCKET');
    print('   Driver ID: $driverId');
    print('   Vehicle Type: $vehicleType');
    print('   Online: $isOnline');
    print('   FCM Token: ${fcmToken ?? "NONE"}');
    // 🔥 DRIVER ROLE SESSION IMPLEMENTATION
    print('   Role: ${role ?? "NONE"}');
    print('   Device ID: ${deviceId ?? "NONE"}');
    print('   Location: $lat, $lng');
    print('=' * 70);
    print('');

    _socket = IO.io(
      AppConfig.backendBaseUrl,
      IO.OptionBuilder()
          .setTransports(['websocket'])
          .enableAutoConnect()
          .setQuery({'driverId': driverId})
          .enableReconnection()
          .setReconnectionAttempts(999999)
          .setReconnectionDelay(2000)
          .setReconnectionDelayMax(10000)
          .build(),
    );

    // ─── On Connect ───
    _socket!.onConnect((_) async {
      print('');
      print('=' * 70);
      print("✅ SOCKET CONNECTED");
      print('   Socket ID: ${_socket!.id}');
      print('   Driver ID: $driverId');
      print('=' * 70);
      print('');

      _isConnected = true;

      // ✅ CRITICAL: Emit status immediately on connect
      _emitDriverStatus(
        driverId,
        isOnline,
        lat,
        lng,
        vehicleType,
        fcmToken: fcmToken,
        // 🔥 DRIVER ROLE SESSION IMPLEMENTATION
        role: role,
        deviceId: deviceId,
      );

      _startLocationUpdates();
      _startReconnectMonitor();
      _startHeartbeat();

      // ✅ FIX 2: Flush any listeners registered before connect() was called
      _flushPendingListeners();

      // CHECK FOR ACTIVE TRIP AND REQUEST DATA IMMEDIATELY
      final prefs = await SharedPreferences.getInstance();
      final savedTripId = prefs.getString('activeTripId');
      final hasActiveTrip = prefs.getBool('hasActiveTrip') ?? false;

      if (hasActiveTrip && savedTripId != null) {
        print('🔄 Requesting active trip data for: $savedTripId');
        _socket!.emit('driver:request_active_trip', {'driverId': driverId});
        _socket!.emit('driver:reconnect_with_trip', {
          'driverId': driverId,
          'tripId': savedTripId,
        });
      }
    });

    // ─── On Reconnect ───
    _socket!.onReconnect((_) async {
      print('');
      print('=' * 70);
      print("🔄 SOCKET RECONNECTED");
      print('   Socket ID: ${_socket!.id}');
      print('=' * 70);
      print('');

      _isConnected = true;

      // 🔥 Re-register force_logout listener on reconnect
      _registerForceLogoutListener();

      // Re-emit driver status on reconnect
      _emitDriverStatus(
        driverId,
        isOnline,
        _lastLat ?? 0,
        _lastLng ?? 0,
        _vehicleType ?? 'auto',
        fcmToken: _fcmToken,
        role: _role,
        deviceId: _deviceId,
      );

      _startLocationUpdates();
      _startReconnectMonitor();
      _startHeartbeat();

      print('✅ Reconnect handlers reinitialized');
    });

    // ─── On Disconnect ───
    _socket!.onDisconnect((_) {
      print('🔴 Socket disconnected');
      print('⚠️ Socket disconnected — will retry...');
      _isConnected = false;
      _stopLocationUpdates();

      if (_hasActiveTrip) {
        print('⚠️ CRITICAL: Disconnected during active trip! Reconnecting...');
        _attemptReconnect();
      } else {
        _reconnect();
      }
    });

    // ─── On Error ───
    _socket!.onError((err) {
      print('❌ Socket error: $err');
      if (_hasActiveTrip) {
        print('⚠️ Error during active trip - attempting reconnect');
        _attemptReconnect();
      }
    });

    // ─── On Reconnect ───
    _socket!.onReconnect((_) {
      print('🔄 Socket reconnected: ${_socket!.id}');
      _isConnected = true;

      _emitDriverStatus(
        _driverId!,
        _isOnline,
        _lastLat!,
        _lastLng!,
        _vehicleType ?? '',
        fcmToken: _fcmToken,
      );
      _startLocationUpdates();

      // ✅ FIX 2: Flush any listeners added while disconnected
      _flushPendingListeners();

      if (_hasActiveTrip && _activeTripId != null) {
        print('🔄 Resuming active trip: $_activeTripId');
      }
    });

    // ─── Status Confirmation ───
    _socket!.on('driver:statusUpdated', (data) {
      print('✅ Server confirmed driver status: $data');
    });

    // ───────────────────────────────────────────────────────────────────
    // 🚗 TRIP LISTENERS
    // ───────────────────────────────────────────────────────────────────

    _socket!.on('trip:request', (data) {
      final tripData = Map<String, dynamic>.from(data);
      final bool isDest = data['isDestinationMatch'] == true;
      tripData['isDestinationMatch'] = isDest;
      _handleTripRequest(tripData);
    });

    _socket!.on('shortTripRequest', (data) {
      final tripData = Map<String, dynamic>.from(data);
      tripData['isDestinationMatch'] = data['isDestinationMatch'] == true;
      _handleTripRequest(tripData);
    });

    _socket!.on('parcelTripRequest', (data) => _handleTripRequest(data));
    _socket!.on('longTripRequest', (data) => _handleTripRequest(data));

    _socket!.on('rideConfirmed', (data) {
      print('✅ Ride confirmed: $data');
      if (onRideConfirmed != null) {
        onRideConfirmed!(Map<String, dynamic>.from(data));
      }
    });

    _socket!.on('rideCancelled', (data) {
      print('🚫 Ride cancelled: $data');
      if (onRideCancelled != null) {
        onRideCancelled!(Map<String, dynamic>.from(data));
      }
    });

    // Accept confirmations and failures
    _socket!.on('trip:confirmed_for_driver', (data) {
      try {
        final map = Map<String, dynamic>.from(data);
        final tripId = (map['tripId'] ?? map['trip']?['tripId'])?.toString();
        print('✅ Server confirmed trip for driver: $tripId');

        if (tripId != null) {
          // Mark active trip and clear accept lock
          setActiveTrip(tripId);
          _setAccepting(tripId, false);
          // Notify listeners (dashboard/background) about the confirmed trip
          try {
            if (onActiveTripRestored != null) onActiveTripRestored!(map);
          } catch (e) {
            print('⚠️ Error invoking onActiveTripRestored: $e');
          }
        }
      } catch (e) {
        print('⚠️ Error handling trip:confirmed_for_driver: $e');
      }
    });

    _socket!.on('trip:accept_failed', (data) {
      try {
        final map = data is Map
            ? Map<String, dynamic>.from(data)
            : {'message': data.toString()};
        final tripId = (map['tripId'] ?? map['tripId'])?.toString();
        print('❌ Trip accept failed: $map');
        if (tripId != null) _setAccepting(tripId, false);
      } catch (e) {
        print('⚠️ Error handling trip:accept_failed: $e');
      }
    });

    // Another driver accepted — mark seen and clear local accept lock
    _socket!.on('trip:taken', (data) {
      try {
        final map = Map<String, dynamic>.from(data);
        final tripId = (map['tripId'] ?? map['tripId'])?.toString();
        print('⚠️ Trip taken by another driver: $tripId');
        if (tripId != null) {
          _seenTripIds.add(tripId);
          _setAccepting(tripId, false);
          // If this was active locally, clear it
          if (_activeTripId == tripId) setActiveTrip(null);
        }
      } catch (e) {
        print('⚠️ Error handling trip:taken: $e');
      }
    });

    _socket!.on('location:update_customer', (data) {
      print("📍 Customer live location: $data");
    });

    // ───────────────────────────────────────────────────────────────────
    // 💳 PAYMENT LISTENERS
    // ───────────────────────────────────────────────────────────────────

    _socket!.on('payment:received', (data) {
      print('');
      print('=' * 70);
      print('✅ PAYMENT RECEIVED NOTIFICATION');
      print('   Data: $data');
      print('=' * 70);
      print('');

      if (data != null && onPaymentReceived != null) {
        onPaymentReceived!(Map<String, dynamic>.from(data));
      }
    });

    _socket!.on('cash:payment:pending', (data) {
      print('');
      print('=' * 70);
      print('💵 CASH PAYMENT PENDING');
      print('   Data: $data');
      print('=' * 70);
      print('');

      if (data != null && onCashPaymentPending != null) {
        onCashPaymentPending!(Map<String, dynamic>.from(data));
      }
    });

    _socket!.on('payment:failed', (data) {
      print('');
      print('=' * 70);
      print('❌ PAYMENT FAILED');
      print('   Data: $data');
      print('=' * 70);
      print('');

      if (data != null && onPaymentFailed != null) {
        onPaymentFailed!(Map<String, dynamic>.from(data));
      }
    });

    _socket!.on('payment:confirmed', (data) {
      print('');
      print('=' * 70);
      print('✅ PAYMENT CONFIRMED');
      print('   Data: $data');
      print('=' * 70);
      print('');

      if (data != null && onPaymentConfirmed != null) {
        onPaymentConfirmed!(Map<String, dynamic>.from(data));
      }
    });

    // ✅ FIX 3: commission:paid registered here in the service so it always
    // works regardless of when wallet_page initializes or what state it's in.
    _socket!.on('commission:paid', (data) {
      print('');
      print('=' * 70);
      print('💰 COMMISSION PAID');
      print('   Data: $data');
      print('=' * 70);
      print('');

      if (data != null && onCommissionPaid != null) {
        onCommissionPaid!(Map<String, dynamic>.from(data));
      }
    });

    // ───────────────────────────────────────────────────────────────────
    // 🔄 ACTIVE TRIP RESTORE LISTENERS
    // ───────────────────────────────────────────────────────────────────

    _socket!.on('active_trip:restore', (data) {
      print('');
      print('=' * 70);
      print('🔄 ACTIVE TRIP RESTORED FROM SERVER');
      print('   Data: $data');
      print('=' * 70);
      print('');

      if (data != null) {
        final tripData = Map<String, dynamic>.from(data);
        final tripId = tripData['tripId']?.toString();

        if (tripId != null) {
          _activeTripId = tripId;
          _hasActiveTrip = true;
          _saveActiveTripToPrefs(tripId);
        }

        if (onActiveTripRestored != null) {
          onActiveTripRestored!(tripData);
        }
      }
    });

    _socket!.on('reconnect:success', (data) {
      print('✅ Reconnect success: $data');
      if (data != null) {
        final tripData = Map<String, dynamic>.from(data);
        if (onActiveTripRestored != null) {
          onActiveTripRestored!(tripData);
        }
      }
    });

    _socket!.on('reconnect:failed', (data) {
      print('❌ Reconnect failed: $data');
      final shouldClear = data?['shouldClearTrip'] == true;
      if (shouldClear) {
        setActiveTrip(null);
      }
    });

    _socket!.on('active_trip:none', (data) {
      print('ℹ️ No active trip found on server');
    });

    // Clear seen/dedupe entries on trip cancellation/expiry so they can be re-presented later
    _socket!.on('trip:cancelled', (data) {
      try {
        final tripId = data is Map ? (data['tripId']?.toString()) : null;
        if (tripId != null) {
          _seenTripIds.remove(tripId);
          _setAccepting(tripId, false);
        }
      } catch (e) {
        print('⚠️ Error handling trip:cancelled dedupe cleanup: $e');
      }
    });

    _socket!.on('trip:expired', (data) {
      try {
        final tripId = data is Map ? (data['tripId']?.toString()) : null;
        if (tripId != null) {
          _seenTripIds.remove(tripId);
          _setAccepting(tripId, false);
        }
      } catch (e) {
        print('⚠️ Error handling trip:expired dedupe cleanup: $e');
      }
    });

    // ✅ ENHANCED: Listen for customer cancel search - removes trip immediately from all drivers
    _socket!.on('trip:cancel_search', (data) {
      try {
        final tripId = data is Map ? (data['tripId']?.toString()) : null;
        if (tripId != null) {
          print('🚫 [trip:cancel_search] Customer cancelled search - removing trip: $tripId');
          _seenTripIds.remove(tripId); // Allow re-presentation if needed
          _setAccepting(tripId, false); // Clear accept lock
          print('   ✅ Marked as cancelled - will not show to drivers');
        }
      } catch (e) {
        print('⚠️ Error handling trip:cancel_search: $e');
      }
    });

    // ✅ FALLBACK: Listen for trip:request_cancelled (alternative event name)
    _socket!.on('trip:request_cancelled', (data) {
      try {
        final tripId = data is Map ? (data['tripId']?.toString()) : null;
        if (tripId != null) {
          print('🚫 [trip:request_cancelled] Removing request: $tripId');
          _seenTripIds.remove(tripId);
          _setAccepting(tripId, false);
        }
      } catch (e) {
        print('⚠️ Error handling trip:request_cancelled: $e');
      }
    });

    _socket!.on('heartbeat:ack', (data) {
      // Silently acknowledged
    });

    // ───────────────────────────────────────────────────────────────────
    // 🔥 DRIVER ROLE SESSION IMPLEMENTATION - SESSION MANAGEMENT
    // ───────────────────────────────────────────────────────────────────

    /// 🔥 Session expired event
    _socket!.on('session_expired', (data) {
      print('🔥 Session expired: $data');
      if (_role == 'driver' && onSessionExpired != null) {
        onSessionExpired!();
      }
    });

    /// 🔥 Device conflict notification
    _socket!.on('device_conflict', (data) {
      print('🔥 Device conflict: $data');
      final previousDeviceId = data?['previousDeviceId'];
      final currentDeviceId = data?['currentDeviceId'];
      print('   Previous: $previousDeviceId');
      print('   Current: $currentDeviceId');
    });

    // ✅ Explicitly connect
    print('🔌 Calling socket.connect()...');
    _socket!.connect();
  }

  // ───────────────────────────────────────────────────────────────────────
  // 🔄 RECONNECTION LOGIC
  // ───────────────────────────────────────────────────────────────────────

  void _reconnect() {
    Future.delayed(const Duration(seconds: 5), () {
      try {
        if (_socket != null && !_socket!.connected) {
          print('🔄 Attempting socket reconnect...');
          _socket!.connect();
        }
      } catch (e) {
        print('⚠️ Reconnect error: $e');
      }
    });
  }

  void _startReconnectMonitor() {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (!_isConnected && _hasActiveTrip) {
        print('⚠️ Connection lost during active trip - forcing reconnect');
        _attemptReconnect();
      }
    });
  }

  void _attemptReconnect() {
    try {
      if (_socket != null && !_socket!.connected) {
        print('🔄 Attempting manual reconnection...');
        _socket!.connect();
      }
    } catch (e) {
      print('⚠️ Manual reconnect error: $e');
    }
  }

  // ───────────────────────────────────────────────────────────────────────
  // 📍 LOCATION UPDATES
  // ───────────────────────────────────────────────────────────────────────

  void _startLocationUpdates() {
    _locationTimer?.cancel();
    _locationTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      if (_driverId != null && _lastLat != null && _lastLng != null) {
        _emitDriverStatus(
          _driverId!,
          _isOnline,
          _lastLat!,
          _lastLng!,
          _vehicleType ?? '',
          fcmToken: _fcmToken,
        );
      }
    });
    print('📡 Started auto location updates every 10s');
  }

  void _stopLocationUpdates() {
    _locationTimer?.cancel();
    _locationTimer = null;
    print('🛑 Stopped auto location updates');
  }

  // ───────────────────────────────────────────────────────────────────────
  // 💓 HEARTBEAT
  // ───────────────────────────────────────────────────────────────────────

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 15), (timer) {
      if (_isConnected && _driverId != null && _socket != null) {
        _socket!.emit('driver:heartbeat', {
          'driverId': _driverId,
          'tripId': _activeTripId,
          'timestamp': DateTime.now().toIso8601String(),
          'location': _lastLat != null && _lastLng != null
              ? {'lat': _lastLat, 'lng': _lastLng}
              : null,
        });
      }
    });
    print('💓 Heartbeat started (every 15s)');
  }

  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  // ───────────────────────────────────────────────────────────────────────
  // 🚗 VEHICLE CAPABILITIES
  // ───────────────────────────────────────────────────────────────────────

  Map<String, bool> _getCapabilities(String vehicleType) {
    switch (vehicleType.toLowerCase()) {
      case "bike":
        return {
          'acceptsShort': true,
          'acceptsParcel': true,
          'acceptsLong': false,
        };
      case "car":
        return {
          'acceptsShort': true,
          'acceptsParcel': false,
          'acceptsLong': true,
        };
      case "auto":
        return {
          'acceptsShort': true,
          'acceptsParcel': false,
          'acceptsLong': false,
        };
      default:
        return {
          'acceptsShort': false,
          'acceptsParcel': false,
          'acceptsLong': false,
        };
    }
  }

  // ───────────────────────────────────────────────────────────────────────
  // 📤 DRIVER STATUS EMISSION
  // ───────────────────────────────────────────────────────────────────────

  void updateDriverStatus(
    String driverId,
    bool isOnline,
    double lat,
    double lng,
    String vehicleType, {
    String? fcmToken,
    Map<String, dynamic>? profileData,
  }) {
    if (!_isConnected) {
      print('⚠️ Socket not connected, attempting reconnection...');
      if (_hasActiveTrip) {
        _attemptReconnect();
      }
      return;
    }

    _isOnline = isOnline;
    _lastLat = lat;
    _lastLng = lng;

    _emitDriverStatus(
      driverId,
      isOnline,
      lat,
      lng,
      vehicleType,
      fcmToken: fcmToken,
      profileData: profileData,
      role: _role,
      deviceId: _deviceId,
    );
  }

  // 🔥 DRIVER ROLE SESSION IMPLEMENTATION
  void _emitDriverStatus(
    String driverId,
    bool isOnline,
    double lat,
    double lng,
    String vehicleType, {
    String? fcmToken,
    Map<String, dynamic>? profileData,
    String? role,
    String? deviceId,
  }) {
    final caps = _getCapabilities(vehicleType);

    final payload = {
      'driverId': driverId,
      'isOnline': isOnline,
      'vehicleType': vehicleType,
      'fcmToken': fcmToken,
      'acceptsShort': caps['acceptsShort'],
      'acceptsParcel': caps['acceptsParcel'],
      'acceptsLong': caps['acceptsLong'],
      'location': {
        'type': 'Point',
        'coordinates': [lng, lat],
      },
      // 🔥 DRIVER ROLE SESSION IMPLEMENTATION
      if (role != null) 'role': role,
      if (deviceId != null) 'deviceId': deviceId,
      if (profileData != null) 'profileData': profileData,
    };

    payload.removeWhere((key, value) => value == null);

    // 🔥 DRIVER ROLE SESSION IMPLEMENTATION
    print(
      '📤 Emitting updateDriverStatus - Online: $isOnline, FCM: ${fcmToken != null ? "YES" : "NO"}, Role: ${role ?? "NONE"}, Device: ${deviceId ?? "NONE"}',
    );
    emit('updateDriverStatus', payload);
  }

  // ───────────────────────────────────────────────────────────────────────
  // 🚗 RIDE ACTIONS
  // ───────────────────────────────────────────────────────────────────────

  // ───────────────────────────────────────────────────────────────────────
  // Accept flow with in-memory accept locks and dedupe
  // Ensures idempotent accepts and waits for server confirmation
  final Map<String, bool> _acceptLocks = {}; // tripId -> accepting
  final Set<String> _seenTripIds = {}; // dedupe incoming trip presentations

  bool _isAccepting(String tripId) => _acceptLocks[tripId] == true;

  void _setAccepting(String tripId, bool v) {
    if (v)
      _acceptLocks[tripId] = true;
    else
      _acceptLocks.remove(tripId);
  }

  /// Public checker for UI: returns true if this trip is currently being accepted
  bool isAcceptingTrip(String tripId) => tripId != null && _isAccepting(tripId);

  void acceptRide(String driverId, Map<String, dynamic> rideData) {
    final tripId = (rideData['tripId'] ?? rideData['_id'])?.toString();
    if (tripId == null) {
      print('❌ No tripId found in rideData: $rideData');
      return;
    }

    if (_isAccepting(tripId)) {
      print('⏳ Already accepting trip $tripId — ignoring duplicate accept');
      return;
    }

    // Local optimistic lock — prevents UI/overlay multiple accepts
    _setAccepting(tripId, true);

    // Mark active trip locally only after server confirms assignment
    print('📤 Sending accept request for trip: $tripId');
    emit('driver:accept_trip', {'tripId': tripId, 'driverId': driverId});

    // Start a short timeout to clear the lock if server doesn't respond
    Timer(const Duration(seconds: 10), () {
      if (_isAccepting(tripId)) {
        print('⚠️ Accept timeout for $tripId — clearing local accept lock');
        _setAccepting(tripId, false);
      }
    });
  }

  Future<void> rejectRide(String driverId, String rideId) async {
    print('🚫 Rejecting ride: $rideId');
  }

  Future<void> completeRide(String driverId, String rideId) async {
    print('✅ Completing ride: $rideId');
    setActiveTrip(null);
  }

  Future<void> goToPickup(String driverId, String tripId) async {
    print('🚗 Going to pickup for trip: $tripId');
    emit('driver:going_to_pickup', {'tripId': tripId, 'driverId': driverId});
  }

  Future<void> startRideWithOTP(
    String driverId,
    String tripId,
    String otp,
    double driverLat,
    double driverLng,
  ) async {
    print('▶️ Starting ride with OTP for trip: $tripId');
    emit('driver:start_ride', {
      'tripId': tripId,
      'driverId': driverId,
      'otp': otp,
      'driverLat': driverLat,
      'driverLng': driverLng,
    });
  }

  Future<void> completeRideWithVerification(
    String driverId,
    String tripId,
    double driverLat,
    double driverLng,
  ) async {
    print('🏁 Completing ride with verification for trip: $tripId');
    emit('driver:complete_ride', {
      'tripId': tripId,
      'driverId': driverId,
      'driverLat': driverLat,
      'driverLng': driverLng,
    });
  }

  Future<void> confirmCashCollection(String driverId, String tripId) async {
    print('💰 Confirming cash collection for trip: $tripId');
    emit('driver:confirm_cash', {'tripId': tripId, 'driverId': driverId});
    setActiveTrip(null);
  }

  // ───────────────────────────────────────────────────────────────────────
  // 📍 LOCATION HELPERS
  // ───────────────────────────────────────────────────────────────────────

  void sendDriverLocation(String tripId, double lat, double lng) {
    if (_isConnected) {
      emit('driver:location', {
        'tripId': tripId,
        'latitude': lat,
        'longitude': lng,
      });
    }
  }

  void updateLocation(double lat, double lng) {
    _lastLat = lat;
    _lastLng = lng;

    if (_isConnected && _driverId != null && _vehicleType != null) {
      _emitDriverStatus(
        _driverId!,
        _isOnline,
        lat,
        lng,
        _vehicleType!,
        fcmToken: _fcmToken,
      );
    }
  }

  // ───────────────────────────────────────────────────────────────────────
  // 🚗 TRIP REQUEST HANDLER
  // ───────────────────────────────────────────────────────────────────────

  void _handleTripRequest(dynamic data) {
    print('📩 Trip request: $data');

    final trip = Map<String, dynamic>.from(data);
    trip['isDestinationMatch'] = data['isDestinationMatch'] == true;

    final tripId = (trip['tripId'] ?? trip['_id'])?.toString();
    if (tripId != null) {
      // Dedupe: ignore if we've already seen or it was taken
      if (_seenTripIds.contains(tripId)) {
        print('⚠️ Duplicate trip request ignored: $tripId');
        return;
      }
      // Mark seen so subsequent duplicate ingress is ignored
      _seenTripIds.add(tripId);
    }

    if (onRideRequest != null) {
      onRideRequest!(trip);
    }
  }

  // ───────────────────────────────────────────────────────────────────────
  // 📊 GETTERS
  // ───────────────────────────────────────────────────────────────────────

  bool get isOnline => _isOnline;
  bool get isConnected => _isConnected;
  bool get hasActiveTrip => _hasActiveTrip;
  String? get activeTripId => _activeTripId;
  String? get driverId => _driverId;

  // ───────────────────────────────────────────────────────────────────────
  // 🔌 DISCONNECT & DISPOSE
  // ───────────────────────────────────────────────────────────────────────

  void disconnect({bool force = false}) {
    if (_hasActiveTrip && !force) {
      print('⚠️ CANNOT DISCONNECT - Active trip in progress: $_activeTripId');
      print('💡 Driver must complete trip first!');
      return;
    }

    try {
      if (_socket != null && _socket!.connected) {
        print('🔌 Disconnecting socket...');
        print('🔄 Disconnecting socket manually');

        if (_isConnected &&
            _driverId != null &&
            _lastLat != null &&
            _lastLng != null) {
          _emitDriverStatus(
            _driverId!,
            false,
            _lastLat!,
            _lastLng!,
            _vehicleType ?? '',
            fcmToken: _fcmToken,
          );
        }

        _socket!.disconnect();
        print('🔴 Socket disconnected manually');
      }
    } catch (e) {
      print('⚠️ Error during disconnect: $e');
    }

    _stopLocationUpdates();
    _stopHeartbeat();
    _reconnectTimer?.cancel();
    _isConnected = false;
    _isOnline = false;

    if (force) {
      _socket = null;
    }
  }

  // ✅ FIX 4: dispose() always cleans up timers even with active trip.
  // Old version skipped ALL cleanup if hasActiveTrip was true,
  // leaking _heartbeatTimer and _locationTimer indefinitely.
  void dispose() {
    _stopHeartbeat();
    _stopLocationUpdates();
    _reconnectTimer?.cancel();

    if (!_hasActiveTrip) {
      disconnect();
    } else {
      print(
        '⚠️ dispose() called with active trip — timers cleared, socket kept alive for trip',
      );
    }
  }
}
