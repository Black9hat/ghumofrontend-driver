// lib/services/plan_aware_commission_service.dart
//
// ═══════════════════════════════════════════════════════════════════════════
// PLAN-AWARE COMMISSION SERVICE
// ─────────────────────────────────────────────────────────────────────────────
// Enhanced commission service that:
// 1. Checks if driver has ACTIVE plan
// 2. Uses PLAN rates if active (lower commission, bonus multiplier)
// 3. Falls back to BASE rates if no active plan
// 4. Subscribes to both socket events AND plan updates
//
// COMMISSION HIERARCHY (Priority Order):
//   1. Active Plan rates (if driver purchased & within validity)
//   2. Base CommissionSetting rates (fallback)
//   3. Hard defaults (if neither available)
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:drivergoo/services/socket_service.dart';
import 'package:drivergoo/config.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Active Plan Model (from backend DriverPlan)
// ─────────────────────────────────────────────────────────────────────────────

class ActivePlanInfo {
  final String planId;
  final String planName;
  final double commissionRate;    // Base rate (e.g., 10%)
  final double bonusMultiplier;   // Earning boost (e.g., 1.2x = 20% more)
  final bool noCommission;        // If true, commission is 0%
  final DateTime expiryDate;

  ActivePlanInfo({
    required this.planId,
    required this.planName,
    required this.commissionRate,
    required this.bonusMultiplier,
    required this.noCommission,
    required this.expiryDate,
  });

  factory ActivePlanInfo.fromJson(Map<String, dynamic> json) {
    return ActivePlanInfo(
      planId: json['_id'] as String? ?? json['planId'] as String? ?? '',
      planName: json['planName'] as String? ?? 'Unknown Plan',
      commissionRate: (json['commissionRate'] as num?)?.toDouble() ?? 20.0,
      bonusMultiplier: (json['bonusMultiplier'] as num?)?.toDouble() ?? 1.0,
      noCommission: json['noCommission'] as bool? ?? false,
      expiryDate: DateTime.tryParse(json['expiryDate'] as String? ?? '') ?? DateTime.now(),
    );
  }

  bool get isExpired => DateTime.now().isAfter(expiryDate);
  bool get isActive => !isExpired;

  @override
  String toString() => 'ActivePlan($planName: ${noCommission ? "0%" : "$commissionRate%"} + ${bonusMultiplier}x)';
}

// ─────────────────────────────────────────────────────────────────────────────
// Commission Configuration (Base + Plan overlay)
// ─────────────────────────────────────────────────────────────────────────────

class PlanAwareCommissionConfig {
  // Base rates (from CommissionSetting)
  final double baseCommissionPercent;
  final double basePlatformFeeFlat;
  final double basePlatformFeePercent;
  final double basePerRideIncentive;
  final int basePerRideCoins;

  // Active plan (if any)
  final ActivePlanInfo? activePlan;

  // Effective rates (plan overrides base)
  late final double effectiveCommissionPercent;
  late final double effectiveBonusMultiplier;

  PlanAwareCommissionConfig({
    required this.baseCommissionPercent,
    required this.basePlatformFeeFlat,
    required this.basePlatformFeePercent,
    required this.basePerRideIncentive,
    required this.basePerRideCoins,
    this.activePlan,
  }) {
    // Calculate effective commission (plan overrides base if active)
    if (activePlan != null && activePlan!.isActive) {
      effectiveCommissionPercent =
          activePlan!.noCommission ? 0.0 : activePlan!.commissionRate;
      effectiveBonusMultiplier = activePlan!.bonusMultiplier;
    } else {
      effectiveCommissionPercent = baseCommissionPercent;
      effectiveBonusMultiplier = 1.0; // No bonus if no active plan
    }
  }

  /// Get actual driver earnings after commission & fees
  /// Usage: driverEarnings = calculateDriverEarning(100) with 20% commission
  /// = 100 * (1 - 0.20) = ₹80
  double calculateDriverEarning(double fareAmount) {
    final earning = fareAmount * (1 - (effectiveCommissionPercent / 100));
    return earning * effectiveBonusMultiplier; // Apply plan bonus if active
  }

  /// Get per-ride incentive (same for all, plan doesn't override)
  double getPerRideIncentive() => basePerRideIncentive;

  /// Get per-ride coins (same for all, plan doesn't override)
  int getPerRideCoins() => basePerRideCoins;

  /// Human-readable summary
  @override
  String toString() {
    if (activePlan != null && activePlan!.isActive) {
      return '${activePlan!.planName}: ${activePlan!.noCommission ? "0%" : "${activePlan!.commissionRate}%"} + ${activePlan!.bonusMultiplier}x bonus + ₹${basePerRideIncentive}/ride';
    }
    return 'Base: ${baseCommissionPercent.toStringAsFixed(1)}% + ₹${basePerRideIncentive.toStringAsFixed(2)}/ride';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Plan-Aware Commission Service
// ─────────────────────────────────────────────────────────────────────────────

class PlanAwareCommissionService {
  static final PlanAwareCommissionService _instance =
      PlanAwareCommissionService._internal();

  factory PlanAwareCommissionService() => _instance;
  PlanAwareCommissionService._internal();

  // Storage
  static const String _baseConfigKey = 'base_commission_config';
  static const String _activePlanKey = 'active_plan_info';

  PlanAwareCommissionConfig? _currentConfig;
  bool _isInitialized = false;
  String? _driverId;

  // Callbacks
  void Function(PlanAwareCommissionConfig newConfig)? onConfigUpdated;
  void Function(String message)? onError;

  // ──────────────────────────────────────────────────────────────────────────
  // Initialization
  // ──────────────────────────────────────────────────────────────────────────

  /// Initialize service: load both base config and active plan
  Future<void> initialize(String driverId, String apiBase) async {
    if (_isInitialized) return;

    _driverId = driverId;
    print('💰 PlanAwareCommissionService: Initializing...');

    try {
      // Load cached base config
      await _loadCachedBaseConfig();

      // Load cached active plan
      await _loadCachedActivePlan();

      // Subscribe to socket updates
      _subscribeToSocketUpdates();

      // Fetch fresh data from server (non-blocking)
      Future.microtask(() => _fetchFreshDataFromServer(apiBase, driverId));

      _isInitialized = true;
      print('✅ PlanAwareCommissionService: Ready');
    } catch (e) {
      print('❌ PlanAwareCommissionService init error: $e');
      onError?.call('Failed to initialize plan-aware commission service: $e');
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Socket Subscription
  // ──────────────────────────────────────────────────────────────────────────

  void _subscribeToSocketUpdates() {
    final socket = DriverSocketService();

    // When admin updates base commission rates
    socket.on('config:updated', (data) {
      print('📡 Socket: Received config:updated event');
      try {
        if (data is Map<String, dynamic>) {
          _updateBaseConfig(data);
        }
      } catch (e) {
        print('❌ Error parsing config:updated: $e');
      }
    });

    // When driver's plan changes (purchased/expired)
    socket.on('plan:activated', (data) {
      print('📡 Socket: Received plan:activated event');
      try {
        if (data is Map<String, dynamic>) {
          _updateActivePlan(data);
        }
      } catch (e) {
        print('❌ Error parsing plan:activated: $e');
      }
    });

    socket.on('plan:expired', (data) {
      print('📡 Socket: Received plan:expired event');
      _clearActivePlan();
    });

    print('🔌 PlanAwareCommissionService: Subscribed to socket events');
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Config Management
  // ──────────────────────────────────────────────────────────────────────────

  void _updateBaseConfig(Map<String, dynamic> baseData) async {
    // Save base config
    await _saveBaseConfig(baseData);

    // Recalculate effective config
    _rebuildConfig();

    print('💾 Updated base commission config');
  }

  void _updateActivePlan(Map<String, dynamic> planData) async {
    // Save active plan
    final plan = ActivePlanInfo.fromJson(planData);
    await _savePlan(plan);

    // Recalculate effective config
    _rebuildConfig();

    print('💾 Updated active plan: ${plan.planName}');
  }

  void _clearActivePlan() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_activePlanKey);
    _rebuildConfig();

    print('🧹 Cleared active plan (expired)');
  }

  void _rebuildConfig() {
    if (_currentConfig == null) {
      print('⚠️ Cannot rebuild config - base config not loaded yet');
      return;
    }

    // Create new config with same base but updated plan
    _currentConfig = PlanAwareCommissionConfig(
      baseCommissionPercent: _currentConfig!.baseCommissionPercent,
      basePlatformFeeFlat: _currentConfig!.basePlatformFeeFlat,
      basePlatformFeePercent: _currentConfig!.basePlatformFeePercent,
      basePerRideIncentive: _currentConfig!.basePerRideIncentive,
      basePerRideCoins: _currentConfig!.basePerRideCoins,
      activePlan: _currentConfig!.activePlan,
    );

    print('📊 Config recalculated: $_currentConfig');
    onConfigUpdated?.call(_currentConfig!);
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Getters for UI
  // ──────────────────────────────────────────────────────────────────────────

  PlanAwareCommissionConfig? getConfig() => _currentConfig;

  double getEffectiveCommissionPercent() =>
      _currentConfig?.effectiveCommissionPercent ?? 20.0;

  double getEffectiveBonusMultiplier() =>
      _currentConfig?.effectiveBonusMultiplier ?? 1.0;

  bool hasActivePlan() => _currentConfig?.activePlan?.isActive ?? false;

  String? getActivePlanName() => _currentConfig?.activePlan?.planName;

  double calculateEarning(double fare) =>
      _currentConfig?.calculateDriverEarning(fare) ?? fare * 0.8;

  String getSummaryText() => _currentConfig?.toString() ?? 'Loading...';

  // ──────────────────────────────────────────────────────────────────────────
  // Persistence
  // ──────────────────────────────────────────────────────────────────────────

  Future<void> _loadCachedBaseConfig() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString(_baseConfigKey);

      if (json != null && json.isNotEmpty) {
        final data = jsonDecode(json) as Map<String, dynamic>;
        _currentConfig = PlanAwareCommissionConfig(
          baseCommissionPercent:
              (data['baseCommissionPercent'] as num?)?.toDouble() ?? 20.0,
          basePlatformFeeFlat:
              (data['basePlatformFeeFlat'] as num?)?.toDouble() ?? 0.0,
          basePlatformFeePercent:
              (data['basePlatformFeePercent'] as num?)?.toDouble() ?? 0.0,
          basePerRideIncentive:
              (data['basePerRideIncentive'] as num?)?.toDouble() ?? 5.0,
          basePerRideCoins: data['basePerRideCoins'] as int? ?? 10,
        );

        // Load active plan if exists
        final planJson = prefs.getString(_activePlanKey);
        if (planJson != null && planJson.isNotEmpty) {
          final planData = jsonDecode(planJson) as Map<String, dynamic>;
          final plan = ActivePlanInfo.fromJson(planData);
          if (plan.isActive) {
            _currentConfig = PlanAwareCommissionConfig(
              baseCommissionPercent: _currentConfig!.baseCommissionPercent,
              basePlatformFeeFlat: _currentConfig!.basePlatformFeeFlat,
              basePlatformFeePercent: _currentConfig!.basePlatformFeePercent,
              basePerRideIncentive: _currentConfig!.basePerRideIncentive,
              basePerRideCoins: _currentConfig!.basePerRideCoins,
              activePlan: plan,
            );
          }
        }

        print('📂 Loaded cached config: $_currentConfig');
      }
    } catch (e) {
      print('⚠️ Failed to load cached config: $e');
    }
  }

  Future<void> _loadCachedActivePlan() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString(_activePlanKey);

      if (json != null && json.isNotEmpty) {
        final data = jsonDecode(json) as Map<String, dynamic>;
        final plan = ActivePlanInfo.fromJson(data);
        if (!plan.isExpired) {
          print('📂 Loaded cached active plan: $plan');
        }
      }
    } catch (e) {
      print('⚠️ Failed to load cached plan: $e');
    }
  }

  Future<void> _saveBaseConfig(Map<String, dynamic> data) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = jsonEncode(data);
      await prefs.setString(_baseConfigKey, json);
    } catch (e) {
      print('⚠️ Failed to persist base config: $e');
    }
  }

  Future<void> _savePlan(ActivePlanInfo plan) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final data = {
        '_id': plan.planId,
        'planName': plan.planName,
        'commissionRate': plan.commissionRate,
        'bonusMultiplier': plan.bonusMultiplier,
        'noCommission': plan.noCommission,
        'expiryDate': plan.expiryDate.toIso8601String(),
      };
      await prefs.setString(_activePlanKey, jsonEncode(data));
    } catch (e) {
      print('⚠️ Failed to persist active plan: $e');
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Fresh Data Fetch
  // ──────────────────────────────────────────────────────────────────────────

  Future<void> _fetchFreshDataFromServer(String apiBase, String driverId) async {
    try {
      // Fetch active plan
      final planResponse = await http
          .get(
            Uri.parse('$apiBase/api/driver/plan/current'),
          )
          .timeout(const Duration(seconds: 5));

      if (planResponse.statusCode == 200) {
        final body = jsonDecode(planResponse.body);
        if (body['data'] != null) {
          _updateActivePlan(body['data'] as Map<String, dynamic>);
        }
      }
    } catch (e) {
      print('⚠️ Failed to fetch fresh plan data: $e');
    }
  }

  Future<void> clear() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_baseConfigKey);
      await prefs.remove(_activePlanKey);
      _currentConfig = null;
      _isInitialized = false;
      print('🧹 PlanAwareCommissionService: Cleared');
    } catch (e) {
      print('⚠️ Failed to clear plan-aware commission service: $e');
    }
  }
}
