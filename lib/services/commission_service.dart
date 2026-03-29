// lib/services/commission_service.dart
//
// ═══════════════════════════════════════════════════════════════════════════
// COMMISSION SERVICE - Real-time commission & incentive tracking
// ─────────────────────────────────────────────────────────────────────────────
// Handles:
//   • Listening to socket 'config:updated' events from admin
//   • Persisting commission config to SharedPreferences (offline fallback)
//   • Providing getters for UI to display current commission rates
//   • Notifying UI components when rates change
//
// ARCHITECTURE:
//   • Singleton service (thread-safe)
//   • Listens to DriverSocketService for config updates
//   • Auto-loads from SharedPreferences on init
//   • Exposes callbacks for UI listeners
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:drivergoo/services/socket_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Commission Configuration Model
// ─────────────────────────────────────────────────────────────────────────────

class CommissionConfig {
  final String vehicleType;           // 'bike', 'auto', 'car', 'premium', 'xl'
  final double commissionPercent;     // 0-100 (platform takes this % of fare)
  final double platformFeeFlat;       // ₹ flat fee per ride
  final double platformFeePercent;    // 0-100% additional on top of commission
  final double perRideIncentive;      // ₹ bonus per ride
  final int perRideCoins;             // coins bonus per ride
  final String city;                  // 'all', or specific city code
  final DateTime? fetchedAt;          // when we got this from server

  CommissionConfig({
    required this.vehicleType,
    this.commissionPercent = 20.0,
    this.platformFeeFlat = 0.0,
    this.platformFeePercent = 0.0,
    this.perRideIncentive = 5.0,
    this.perRideCoins = 10,
    this.city = 'all',
    this.fetchedAt,
  });

  /// Parse from socket 'config:updated' or API response
  factory CommissionConfig.fromJson(Map<String, dynamic> json) {
    return CommissionConfig(
      vehicleType: json['vehicleType'] as String? ?? 'all',
      commissionPercent: (json['commissionPercent'] as num?)?.toDouble() ?? 20.0,
      platformFeeFlat: (json['platformFeeFlat'] as num?)?.toDouble() ?? 0.0,
      platformFeePercent: (json['platformFeePercent'] as num?)?.toDouble() ?? 0.0,
      perRideIncentive: (json['perRideIncentive'] as num?)?.toDouble() ?? 5.0,
      perRideCoins: json['perRideCoins'] as int? ?? 10,
      city: json['city'] as String? ?? 'all',
      fetchedAt: DateTime.tryParse(json['fetchedAt'] as String? ?? ''),
    );
  }

  /// Serialize to JSON for persistence
  Map<String, dynamic> toJson() => {
    'vehicleType': vehicleType,
    'commissionPercent': commissionPercent,
    'platformFeeFlat': platformFeeFlat,
    'platformFeePercent': platformFeePercent,
    'perRideIncentive': perRideIncentive,
    'perRideCoins': perRideCoins,
    'city': city,
    'fetchedAt': fetchedAt?.toIso8601String(),
  };

  /// Human-readable string for logging
  @override
  String toString() =>
      'CommissionConfig($vehicleType: ${commissionPercent}% + ₹${platformFeeFlat} + ${platformFeePercent}% | ₹${perRideIncentive}/ride + $perRideCoins coins)';
}

// ─────────────────────────────────────────────────────────────────────────────
// Commission Service Singleton
// ─────────────────────────────────────────────────────────────────────────────

class CommissionService {
  static final CommissionService _instance = CommissionService._internal();

  factory CommissionService() => _instance;
  CommissionService._internal();

  // Storage and caching
  static const String _prefsKey = 'commission_config';
  CommissionConfig? _currentConfig;
  bool _isInitialized = false;

  // State callbacks for UI listeners
  void Function(CommissionConfig newConfig)? onConfigUpdated;
  void Function(String message)? onError;

  // ──────────────────────────────────────────────────────────────────────────
  // Initialization and Socket Setup
  // ──────────────────────────────────────────────────────────────────────────

  /// Initialize the service on app startup
  /// Loads cached config from SharedPreferences and subscribes to socket updates
  Future<void> initialize(String? driverId, String? vehicleType) async {
    if (_isInitialized) return;

    print('💰 CommissionService: Initializing...');

    try {
      // Load cached config from local storage
      await _loadCachedConfig();

      // Subscribe to socket config:updated events
      _subscribeToSocketUpdates(vehicleType);

      _isInitialized = true;
      print('✅ CommissionService: Ready');
    } catch (e) {
      print('❌ CommissionService init error: $e');
      onError?.call('Failed to initialize commission service: $e');
    }
  }

  /// Subscribe to 'config:updated' events from socket
  void _subscribeToSocketUpdates(String? vehicleType) {
    final socket = DriverSocketService();

    // Listen for config:updated events broadcast by admin
    socket.on('config:updated', (data) {
      print('📡 Socket: Received config:updated event');
      try {
        if (data is Map<String, dynamic>) {
          final config = CommissionConfig.fromJson(data);
          _updateConfig(config);
        } else {
          print('⚠️ Unexpected config:updated format: $data');
        }
      } catch (e) {
        print('❌ Error parsing config:updated: $e');
      }
    });

    print('🔌 CommissionService: Subscribed to config:updated');
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Config Management
  // ──────────────────────────────────────────────────────────────────────────

  /// Update local config and notify listeners
  void _updateConfig(CommissionConfig config) async {
    _currentConfig = config;
    await _saveConfig(config);

    print('💾 Saved commission config: $config');

    // Notify all UI listeners
    onConfigUpdated?.call(config);
  }

  /// Get current commission config (with fallback to cached value)
  CommissionConfig? getConfig() => _currentConfig;

  /// Get commission percentage only
  double getCommissionPercent() => _currentConfig?.commissionPercent ?? 20.0;

  /// Get platform fee (flat + percentage calculation)
  /// Usage: totalFee = getCommissionPercent() + getPlatformFeeAmount(fareAmount)
  double getPlatformFeeAmount(double fareAmount) {
    if (_currentConfig == null) return 0.0;
    final flatFee = _currentConfig!.platformFeeFlat;
    final percentFee = fareAmount * (_currentConfig!.platformFeePercent / 100);
    return flatFee + percentFee;
  }

  /// Get per-ride incentive (always paid once per completed ride)
  double getPerRideIncentive() => _currentConfig?.perRideIncentive ?? 5.0;

  /// Get per-ride coins (always paid once per completed ride)
  int getPerRideCoins() => _currentConfig?.perRideCoins ?? 10;

  /// Human-readable summary for UI
  String getSummaryText() {
    if (_currentConfig == null) {
      return 'Commission rates not loaded';
    }
    return '${_currentConfig!.commissionPercent.toStringAsFixed(1)}% commission + ₹${_currentConfig!.perRideIncentive.toStringAsFixed(2)}/ride';
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Persistence
  // ──────────────────────────────────────────────────────────────────────────

  /// Load cached config from SharedPreferences
  Future<void> _loadCachedConfig() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString(_prefsKey);

      if (json != null && json.isNotEmpty) {
        final data = jsonDecode(json) as Map<String, dynamic>;
        _currentConfig = CommissionConfig.fromJson(data);
        print('📂 Loaded cached config: $_currentConfig');
      } else {
        print('📂 No cached commission config found, will use server defaults');
      }
    } catch (e) {
      print('⚠️ Failed to load cached config: $e');
      // Continue gracefully - wait for socket update
    }
  }

  /// Save config to SharedPreferences
  Future<void> _saveConfig(CommissionConfig config) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = jsonEncode(config.toJson());
      await prefs.setString(_prefsKey, json);
    } catch (e) {
      print('⚠️ Failed to persist config: $e');
      // Non-critical - we still have in-memory copy
    }
  }

  /// Clear cached config (e.g., on logout)
  Future<void> clear() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefsKey);
      _currentConfig = null;
      _isInitialized = false;
      print('🧹 CommissionService: Cleared');
    } catch (e) {
      print('⚠️ Failed to clear commission config: $e');
    }
  }
}
