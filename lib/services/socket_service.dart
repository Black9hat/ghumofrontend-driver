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

  Timer? _locationTimer;
  Timer? _reconnectTimer;
  Timer? _heartbeatTimer;

  double? _lastLat;
  double? _lastLng;
  String? _driverId;
  bool _isOnline = true;
  String? _fcmToken;

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
  }

  // ───────────────────────────────────────────────────────────────────────
  // 🔌 CONNECT
  // ───────────────────────────────────────────────────────────────────────

  void connect(
    String driverId,
    double lat,
    double lng, {
    required String vehicleType,
    required bool isOnline,
    String? fcmToken,
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
      );
      return;
    }

    _driverId = driverId;
    _vehicleType = vehicleType;
    _isOnline = isOnline;
    _fcmToken = fcmToken;
    _lastLat = lat;
    _lastLng = lng;

    print('');
    print('=' * 70);
    print('🔌 CREATING NEW SOCKET');
    print('   Driver ID: $driverId');
    print('   Vehicle Type: $vehicleType');
    print('   Online: $isOnline');
    print('   FCM Token: ${fcmToken ?? "NONE"}');
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

    _socket!.on('heartbeat:ack', (data) {
      // Silently acknowledged
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
    );
  }

  void _emitDriverStatus(
    String driverId,
    bool isOnline,
    double lat,
    double lng,
    String vehicleType, {
    String? fcmToken,
    Map<String, dynamic>? profileData,
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
      if (profileData != null) 'profileData': profileData,
    };

    payload.removeWhere((key, value) => value == null);

    print(
      '📤 Emitting updateDriverStatus - Online: $isOnline, FCM: ${fcmToken != null ? "YES" : "NO"}',
    );
    emit('updateDriverStatus', payload);
  }

  // ───────────────────────────────────────────────────────────────────────
  // 🚗 RIDE ACTIONS
  // ───────────────────────────────────────────────────────────────────────

  void acceptRide(String driverId, Map<String, dynamic> rideData) {
    final tripId = rideData['tripId'] ?? rideData['_id'];
    if (tripId == null) {
      print('❌ No tripId found in rideData: $rideData');
      return;
    }

    print('📤 Accepting trip: $tripId');
    setActiveTrip(tripId.toString());

    emit('driver:accept_trip', {
      'tripId': tripId.toString(),
      'driverId': driverId,
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

  void disconnect() {
    if (_hasActiveTrip) {
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
      print('⚠️ dispose() called with active trip — timers cleared, socket kept alive for trip');
    }
  }
}