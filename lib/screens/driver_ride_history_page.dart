// ════════════════════════════════════════════════════════════════════════════
// 🚗  lib/screens/driver_ride_history_page.dart
//
// DATA SOURCES:
//   • Ride metadata (pickup, drop, datetime) → GET /api/driver/ride-history
//     (no auth needed)
//   • Earnings (fare, commission, plan, earning) → GET /api/wallet/:driverId
//     (requires Bearer token — loaded from SharedPreferences, same as wallet_page.dart)
//
// MATCHING: wallet txn ↔ ride via tripId (exact), then time+fare, then time±45m
// ════════════════════════════════════════════════════════════════════════════

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:drivergoo/config.dart';

// ─── Palette ─────────────────────────────────────────────────────────────────
class _C {
  static const Color primary   = Color(0xFF1565C0);
  static const Color green     = Color(0xFF00C853);
  static const Color blue      = Color(0xFF1E88E5);
  static const Color red       = Color(0xFFE53935);
  static const Color orange    = Color(0xFFD47800);
  static const Color bg        = Colors.white;
  static const Color surface   = Color(0xFFF8F9FA);
  static const Color border    = Color(0xFFE9ECEF);
  static const Color text      = Color(0xFF1A1A2E);
  static const Color textSec   = Color(0xFF6B7280);
  static const Color textTert  = Color(0xFF9CA3AF);
}

TextStyle _t(double size, FontWeight w, Color c, {double ls = 0}) =>
    GoogleFonts.poppins(fontSize: size, fontWeight: w, color: c, letterSpacing: ls);

// ════════════════════════════════════════════════════════════════════════════

class DriverRideHistoryPage extends StatefulWidget {
  final String driverId;
  const DriverRideHistoryPage({Key? key, required this.driverId}) : super(key: key);

  @override
  _DriverRideHistoryPageState createState() => _DriverRideHistoryPageState();
}

class _DriverRideHistoryPageState extends State<DriverRideHistoryPage>
    with SingleTickerProviderStateMixin {

  String get _api => AppConfig.backendBaseUrl;

  List<Map<String, dynamic>> _rides = [];   // from ride-history API, enriched with _walletTxn
  bool    _loading = true;
  String? _error;
  late TabController _tabs;

  // Week tab PageView
  late PageController _weekPageCtrl;
  int _weekPageIndex = 0;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _weekPageCtrl = PageController();
    if (widget.driverId.isEmpty) {
      setState(() { _loading = false; _error = 'Driver ID missing.'; });
      return;
    }
    _fetch();
  }

  @override
  void dispose() {
    _tabs.dispose();
    _weekPageCtrl.dispose();
    super.dispose();
  }

  // ── Load auth token (identical to wallet_page.dart) ─────────────────────────
  // 1) SharedPreferences 'auth_token' (may be empty)
  // 2) Firebase ID token (always works while signed-in)
  Future<String?> _loadAuthToken() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString('auth_token');
      if (stored != null && stored.isNotEmpty) {
        debugPrint('🔑 Auth: from SharedPreferences');
        return stored;
      }
    } catch (_) {}
    // Fallback: Firebase Auth ID token — same as wallet_page.dart
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final idToken = await user.getIdToken();
        debugPrint('🔑 Auth: from Firebase (uid=${user.uid})');
        return idToken;
      }
    } catch (e) {
      debugPrint('⚠️ Firebase getIdToken failed: $e');
    }
    debugPrint('⚠️ Auth: no token available');
    return null;
  }

  // ── Fetch both APIs in parallel ────────────────────────────────────────────
  Future<void> _fetch() async {
    setState(() { _loading = true; _error = null; });
    try {
      final authToken = await _loadAuthToken();
      final authHeaders = <String, String>{
        'Content-Type': 'application/json',
        if (authToken != null && authToken.isNotEmpty)
          'Authorization': 'Bearer $authToken',
      };
      const noAuthHeaders = {'Content-Type': 'application/json'};

      final results = await Future.wait([
        // Ride history — no auth needed
        http.get(
          Uri.parse('$_api/api/driver/ride-history/${widget.driverId}?includeUnpaid=true'),
          headers: noAuthHeaders,
        ).timeout(const Duration(seconds: 15)),
        // Wallet — requires auth (same as wallet_page.dart)
        http.get(
          Uri.parse('$_api/api/wallet/${widget.driverId}'),
          headers: authHeaders,
        ).timeout(const Duration(seconds: 15)),
      ]);

      // ── Parse rides ──────────────────────────────────────────────────────
      final rideResp = results[0];
      if (rideResp.statusCode != 200) {
        throw Exception('Ride API returned ${rideResp.statusCode}');
      }
      final rideBody = jsonDecode(rideResp.body) as Map<String, dynamic>;
      if (rideBody['success'] != true) {
        throw Exception(rideBody['message']?.toString() ?? 'Failed to load rides');
      }
      final rides = (rideBody['rides'] as List<dynamic>? ?? [])
          .map((r) => Map<String, dynamic>.from(r as Map))
          .toList();

      // ── Parse wallet credits ─────────────────────────────────────────────
      final credits = _parseCredits(results[1]);
      credits.sort((a, b) {
        try {
          return DateTime.parse(b['createdAt'].toString())
              .compareTo(DateTime.parse(a['createdAt'].toString()));
        } catch (_) { return 0; }
      });

      debugPrint('📊 Rides: ${rides.length} | Wallet credits: ${credits.length} | Auth: ${authToken != null ? "YES" : "NO"}');

      // ── Pre-join: embed wallet txn into each ride ────────────────────────
      for (final ride in rides) {
        final txn = _findTxn(ride, credits);
        if (txn != null) ride['_walletTxn'] = txn;
      }

      setState(() {
        _rides   = rides;
        _loading = false;
      });
    } on SocketException {
      setState(() { _loading = false; _error = 'No internet connection.'; });
    } on TimeoutException {
      setState(() { _loading = false; _error = 'Request timed out.'; });
    } on FormatException {
      setState(() { _loading = false; _error = 'Invalid server response.'; });
    } catch (e) {
      setState(() { _loading = false; _error = e.toString(); });
    }
  }

  // ── Parse wallet API response to extract credit txns ──────────────────────
  List<Map<String, dynamic>> _parseCredits(http.Response r) {
    if (r.statusCode != 200) {
      debugPrint('⚠️ Wallet API: ${r.statusCode}');
      return [];
    }
    try {
      final body = jsonDecode(r.body) as Map<String, dynamic>;
      final raw  = _resolveList(body);
      final credits = raw
          .map((e) => Map<String, dynamic>.from(e as Map))
          .where((t) => t['type'] == 'credit' && _pd(t['amount']) > 0)
          .toList();
      debugPrint('💳 Wallet credits parsed: ${credits.length}');
      return credits;
    } catch (e) {
      debugPrint('❌ Wallet parse error: $e');
      return [];
    }
  }

  List<dynamic> _resolveList(Map<String, dynamic> data) {
    for (final k in ['recentTransactions', 'transactions', 'walletTransactions']) {
      if (data[k] is List) return data[k] as List;
    }
    for (final k in ['wallet', 'data']) {
      final nested = data[k];
      if (nested is Map<String, dynamic>) {
        final l = _resolveList(nested);
        if (l.isNotEmpty) return l;
      }
    }
    return [];
  }

  // ── Match ride → wallet txn ────────────────────────────────────────────────
  Map<String, dynamic>? _findTxn(
      Map<String, dynamic> ride, List<Map<String, dynamic>> credits) {

    // Collect all IDs from the ride object
    final rideIds = <String>{};
    for (final k in ['tripId', 'rideId', '_id', 'id']) {
      final v = ride[k]?.toString().replaceAll(RegExp(r'[^a-f0-9]', caseSensitive: false), '');
      if (v != null && v.length == 24) rideIds.add(v.toLowerCase());
      final raw = ride[k]?.toString();
      if (raw != null && raw.isNotEmpty) rideIds.add(raw);
    }

    // Pass 1 — exact ID match
    for (final txn in credits) {
      for (final k in ['tripId', 'rideId', '_id', 'id', 'transactionId', 'referenceId']) {
        final v = txn[k]?.toString();
        if (v != null && rideIds.contains(v)) return txn;
      }
      // Also check inside metadata
      for (final mk in ['metadata', 'meta', 'trip']) {
        final n = txn[mk];
        if (n is Map) {
          for (final k in ['tripId', 'rideId', '_id']) {
            final v = n[k]?.toString();
            if (v != null && rideIds.contains(v)) return txn;
          }
        }
      }
    }

    // Pass 2 — time + fare match (±2h, ≤₹2 diff)
    final rDate = _rideDate(ride);
    final rFare = _pd(ride['fare']);
    if (rDate.year > 2000) {
      for (final txn in credits) {
        try {
          final tDate = DateTime.parse(txn['createdAt'].toString()).toLocal();
          final tFare = _pd(txn['originalFare']);
          final diff  = tDate.difference(rDate).inMinutes.abs();
          if (diff <= 120 && tFare > 0 && rFare > 0 && (tFare - rFare).abs() <= 2) return txn;
        } catch (_) {}
      }
      // Pass 2b — wider window ±6h
      for (final txn in credits) {
        try {
          final tDate = DateTime.parse(txn['createdAt'].toString()).toLocal();
          final tFare = _pd(txn['originalFare']);
          final diff  = tDate.difference(rDate).inMinutes.abs();
          if (diff <= 360 && tFare > 0 && rFare > 0 && (tFare - rFare).abs() <= 2) return txn;
        } catch (_) {}
      }
      // Pass 3 — time-only ±45 min (catches txns where originalFare is missing)
      for (final txn in credits) {
        try {
          final tDate = DateTime.parse(txn['createdAt'].toString()).toLocal();
          if (tDate.difference(rDate).inMinutes.abs() <= 45) return txn;
        } catch (_) {}
      }
    }
    return null;
  }

  // ── Earnings accessors — WALLET TXN IS SOURCE OF TRUTH ───────────────────

  double _pd(dynamic v) {
    if (v == null) return 0;
    if (v is num)    return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0;
    return 0;
  }

  DateTime _rideDate(Map<String, dynamic> ride) {
    try {
      final s = ride['completedAt'] ?? ride['createdAt'];
      return s != null ? DateTime.parse(s.toString()).toLocal() : DateTime(0);
    } catch (_) { return DateTime(0); }
  }

  Map<String, dynamic>? _walletTxn(Map<String, dynamic> ride) =>
      ride['_walletTxn'] as Map<String, dynamic>?;

  bool hasWallet(Map<String, dynamic> ride) => _walletTxn(ride) != null;

  // Earning from wallet txn (amount field = what driver actually got credited)
  // Fallback to ride API's driverEarning if no wallet match
  double earning(Map<String, dynamic> ride) {
    final t = _walletTxn(ride);
    if (t != null) {
      final a = _pd(t['amount']);
      if (a > 0) return a;
    }
    return _pd(ride['driverEarning']);
  }

  // Fare from wallet txn's originalFare; fallback to ride API fare
  double fare(Map<String, dynamic> ride) {
    final t = _walletTxn(ride);
    if (t != null) {
      final f = _pd(t['originalFare']);
      if (f > 0) return f;
    }
    return _pd(ride['fare']);
  }

  // Commission from wallet txn; fallback to ride API commission
  double commission(Map<String, dynamic> ride) {
    final t = _walletTxn(ride);
    if (t != null) return _pd(t['commissionDeducted']);
    return _pd(ride['commission']);
  }

  int commPct(Map<String, dynamic> ride) {
    final t = _walletTxn(ride);
    if (t != null && t['planCommissionRate'] != null) {
      return _pd(t['planCommissionRate']).round();
    }
    return _pd(ride['commissionPercentage']).round();
  }

  bool planApplied(Map<String, dynamic> ride) =>
      _walletTxn(ride)?['planApplied'] == true;

  String planName(Map<String, dynamic> ride) =>
      _walletTxn(ride)?['planName']?.toString() ?? '';

  double incentive(Map<String, dynamic> ride) {
    final t = _walletTxn(ride);
    if (t == null) return 0;
    final f    = _pd(t['originalFare']);
    final comm = _pd(t['commissionDeducted']);
    final amt  = _pd(t['amount']);
    if (f <= 0) return 0;
    final base = f - comm;
    final inc  = amt - base;
    return inc > 0 ? inc : 0;
  }

  // ── Filter & group ─────────────────────────────────────────────────────────

  List<Map<String, dynamic>> _recent() {
    final cutoff = DateTime.now().subtract(const Duration(days: 120));
    return _rides.where((r) => !_rideDate(r).isBefore(cutoff)).toList();
  }

  List<Map<String, dynamic>> _todayRides() {
    final now = DateTime.now();
    return _recent().where((r) {
      final d = _rideDate(r);
      return d.year == now.year && d.month == now.month && d.day == now.day;
    }).toList();
  }

  List<Map<String, dynamic>> _allRides() {
    final all = _recent();
    all.sort((a, b) => _rideDate(b).compareTo(_rideDate(a)));
    return all;
  }

  DateTime _weekStart(DateTime d) {
    final l = DateTime(d.year, d.month, d.day);
    return l.subtract(Duration(days: l.weekday - 1));
  }

  List<MapEntry<DateTime, List<Map<String, dynamic>>>> _groupByWeek(
      List<Map<String, dynamic>> rides) {
    final map = <DateTime, List<Map<String, dynamic>>>{};
    for (final r in rides) map.putIfAbsent(_weekStart(_rideDate(r)), () => []).add(r);
    final entries = map.entries.toList()..sort((a, b) => b.key.compareTo(a.key));
    for (final e in entries) e.value.sort((a, b) => _rideDate(b).compareTo(_rideDate(a)));
    return entries;
  }

  Map<String, dynamic> _stats(List<Map<String, dynamic>> rides) {
    double total = 0;
    for (final r in rides) total += earning(r);
    return { 'rides': rides.length, 'earnings': total };
  }

  // ══════════════════════════════════════════════════════════════════════════
  // BUILD
  // ══════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: _C.surface,
    appBar: _appBar(),
    body: _loading
        ? const Center(child: CircularProgressIndicator(color: _C.primary))
        : _error != null
            ? _errorState()
            : RefreshIndicator(onRefresh: _fetch, color: _C.primary, child: _buildBody()),
  );

  AppBar _appBar() => AppBar(
    backgroundColor: _C.bg, elevation: 0, surfaceTintColor: Colors.transparent,
    leading: IconButton(
      icon: const Icon(Icons.arrow_back_ios_new_rounded, color: _C.text, size: 20),
      onPressed: () => Navigator.pop(context)),
    title: Text('Ride History', style: _t(18, FontWeight.w700, _C.text)),
    actions: [IconButton(icon: const Icon(Icons.refresh_rounded, color: _C.primary), onPressed: _fetch)],
    bottom: PreferredSize(
      preferredSize: const Size.fromHeight(48),
      child: Container(color: _C.bg,
        child: TabBar(
          controller: _tabs,
          labelStyle: _t(14, FontWeight.w700, _C.primary),
          unselectedLabelStyle: _t(14, FontWeight.w500, _C.textSec),
          labelColor: _C.primary, unselectedLabelColor: _C.textSec,
          indicatorColor: _C.primary, indicatorWeight: 3,
          tabs: const [Tab(text: 'Today'), Tab(text: 'This Week')],
        )),
    ),
  );

  Widget _buildBody() {
    final today  = _todayRides();
    final all    = _allRides();
    final groups = _groupByWeek(all);
    return TabBarView(controller: _tabs, children: [
      _todayTab(stats: _stats(today), rides: today),
      _weekTab(groups: groups),
    ]);
  }

  // ── Today tab ─────────────────────────────────────────────────────────────

  Widget _todayTab({required Map<String,dynamic> stats, required List<Map<String,dynamic>> rides}) =>
    CustomScrollView(physics: const AlwaysScrollableScrollPhysics(), slivers: [
      SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.fromLTRB(16,16,16,10),
          child: _todayBanner(stats))),
      rides.isEmpty
          ? SliverToBoxAdapter(child: _emptyState('today'))
          : SliverList(delegate: SliverChildBuilderDelegate(
              (_, i) => _rideCard(rides[i]), childCount: rides.length)),
      const SliverToBoxAdapter(child: SizedBox(height: 32)),
    ]);

  // ── Week tab — swipeable PageView ─────────────────────────────────────────

  Widget _weekTab({required List<MapEntry<DateTime, List<Map<String,dynamic>>>> groups}) {
    if (groups.isEmpty) {
      return Center(child: _emptyState('in the past 4 months'));
    }
    return Column(children: [
      // ── Navigation header ─────────────────────────────────────────────
      _weekNavBar(groups),
      // ── Sliding weeks ─────────────────────────────────────────────────
      Expanded(
        child: PageView.builder(
          controller: _weekPageCtrl,
          itemCount: groups.length,
          onPageChanged: (i) => setState(() => _weekPageIndex = i),
          physics: const BouncingScrollPhysics(),
          itemBuilder: (ctx, i) {
            final entry = groups[i];
            final ws = _stats(entry.value);
            return _weekPage(weekStart: entry.key, rides: entry.value, stats: ws);
          },
        ),
      ),
    ]);
  }

  // ── Week nav bar (← Week label dots →) ────────────────────────────────────

  Widget _weekNavBar(List<MapEntry<DateTime, List<Map<String,dynamic>>>> groups) {
    final entry   = groups[_weekPageIndex];
    final weekEnd = entry.key.add(const Duration(days: 6));
    final isCurr  = _weekStart(DateTime.now()) == entry.key;
    final label   = isCurr
        ? 'This Week'
        : '${DateFormat('dd MMM').format(entry.key)} – ${DateFormat('dd MMM, yy').format(weekEnd)}';
    final canPrev = _weekPageIndex < groups.length - 1;
    final canNext = _weekPageIndex > 0;
    return Container(
      color: _C.bg,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Row(children: [
        // ← swipe to older
        IconButton(
          onPressed: canPrev
              ? () => _weekPageCtrl.nextPage(
                    duration: const Duration(milliseconds: 320),
                    curve: Curves.easeInOut)
              : null,
          icon: Icon(Icons.chevron_left_rounded,
              color: canPrev ? _C.primary : _C.textTert, size: 26)),
        Expanded(child: Column(children: [
          Text(label,
              style: _t(14, FontWeight.w700, _C.text), textAlign: TextAlign.center),
          const SizedBox(height: 4),
          // Dot indicator
          Row(mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(groups.length > 8 ? 8 : groups.length, (i) {
                // If more than 8 weeks, show relative dots around current
                final dotIdx = groups.length > 8
                    ? (_weekPageIndex - 3 + i).clamp(0, groups.length - 1)
                    : i;
                final active = dotIdx == _weekPageIndex;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  width: active ? 18 : 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: active ? _C.primary : _C.textTert.withOpacity(0.4),
                    borderRadius: BorderRadius.circular(3)));
              })),
        ])),
        // → swipe to newer
        IconButton(
          onPressed: canNext
              ? () => _weekPageCtrl.previousPage(
                    duration: const Duration(milliseconds: 320),
                    curve: Curves.easeInOut)
              : null,
          icon: Icon(Icons.chevron_right_rounded,
              color: canNext ? _C.primary : _C.textTert, size: 26)),
      ]),
    );
  }

  // ── Single week page ───────────────────────────────────────────────────────

  Widget _weekPage({
    required DateTime weekStart,
    required List<Map<String,dynamic>> rides,
    required Map<String,dynamic> stats,
  }) {
    return RefreshIndicator(
      onRefresh: _fetch, color: _C.primary,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: _weekPageBanner(weekStart: weekStart, stats: stats))),
          if (rides.isEmpty)
            SliverToBoxAdapter(child: _emptyState('this week'))
          else
            SliverList(delegate: SliverChildBuilderDelegate(
              (_, i) => _rideCard(rides[i]), childCount: rides.length)),
          const SliverToBoxAdapter(child: SizedBox(height: 32)),
        ],
      ),
    );
  }

  // ── Per-week banner ────────────────────────────────────────────────────────

  Widget _weekPageBanner({
    required DateTime weekStart,
    required Map<String,dynamic> stats,
  }) {
    final weekEnd = weekStart.add(const Duration(days: 6));
    final isCurr  = _weekStart(DateTime.now()) == weekStart;
    final rides   = stats['rides'] as int;
    final earnings = stats['earnings'] as double;
    final label   = isCurr ? "This Week's Earnings" : 'Week Earnings';
    final sub     = isCurr
        ? DateFormat('dd MMM').format(weekStart) +
          ' – ' + DateFormat('dd MMM yyyy').format(weekEnd)
        : DateFormat('dd MMM').format(weekStart) +
          ' – ' + DateFormat('dd MMM yyyy').format(weekEnd);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1565C0), Color(0xFF0A2540)],
          begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [BoxShadow(
          color: const Color(0xFF1565C0).withOpacity(0.25),
          blurRadius: 14, offset: const Offset(0, 5))]),
      child: Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: _t(12, FontWeight.w600, Colors.white60)),
          const SizedBox(height: 4),
          Text('₹${earnings.toStringAsFixed(0)}',
              style: _t(32, FontWeight.w800, Colors.white)),
          const SizedBox(height: 2),
          Text(sub, style: _t(11, FontWeight.w400, Colors.white54)),
        ])),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.14),
            borderRadius: BorderRadius.circular(12)),
          child: Column(children: [
            Text('$rides', style: _t(24, FontWeight.w800, Colors.white)),
            Text(rides == 1 ? 'ride' : 'rides',
                style: _t(11, FontWeight.w500, Colors.white70)),
          ]),
        ),
      ]),
    );
  }

  // ── Banners ───────────────────────────────────────────────────────────────

  Widget _todayBanner(Map<String,dynamic> stats) => _banner(
    label: "Today's Earnings",
    sub: DateFormat('dd MMMM yyyy').format(DateTime.now()),
    earnings: stats['earnings'] as double,
    rides: stats['rides'] as int,
    colors: const [Color(0xFF1E88E5), Color(0xFF1565C0)],
    icon: Icons.today_rounded,
  );

  // (week banner removed — replaced by per-page _weekPageBanner)

  Widget _banner({
    required String label, required String sub,
    required double earnings, required int rides,
    required List<Color> colors, required IconData icon,
  }) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      gradient: LinearGradient(colors: colors,
          begin: Alignment.topLeft, end: Alignment.bottomRight),
      borderRadius: BorderRadius.circular(20),
      boxShadow: [BoxShadow(color: colors.last.withOpacity(0.30),
          blurRadius: 18, offset: const Offset(0,7))]),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Container(padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.18), shape: BoxShape.circle),
          child: Icon(icon, color: Colors.white, size: 16)),
        const SizedBox(width: 8),
        Text(label, style: _t(13, FontWeight.w600, Colors.white70)),
        const Spacer(),
        Text(sub, style: _t(11, FontWeight.w400, Colors.white54)),
      ]),
      const SizedBox(height: 14),
      Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('₹${earnings.toStringAsFixed(0)}',
              style: _t(38, FontWeight.w800, Colors.white)),
          Text('total earned', style: _t(12, FontWeight.w400, Colors.white60)),
        ])),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              borderRadius: BorderRadius.circular(14)),
          child: Column(children: [
            Text('$rides', style: _t(26, FontWeight.w800, Colors.white)),
            Text(rides == 1 ? 'Ride' : 'Rides',
                style: _t(11, FontWeight.w500, Colors.white70)),
          ]),
        ),
      ]),
    ]),
  );



  Widget _pill(String text, Color fg, Color bg) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
    child: Text(text, style: _t(12, FontWeight.w600, fg)));

  // ── Ride card ─────────────────────────────────────────────────────────────

  Widget _rideCard(Map<String,dynamic> ride) {
    final earn   = earning(ride);
    final f      = fare(ride);
    final comm   = commission(ride);
    final pct    = commPct(ride);
    final plan   = planApplied(ride);
    final planNm = planName(ride);
    final date   = _rideDate(ride);
    final pickup = _addr(ride['pickup']);
    final drop   = _addr(ride['drop']);

    return GestureDetector(
      onTap: () => _showDetails(ride),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: BoxDecoration(
          color: _C.bg, borderRadius: BorderRadius.circular(18),
          border: Border.all(color: _C.border),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04),
              blurRadius: 10, offset: const Offset(0,3))]),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

            // Header
            Row(children: [
              Container(padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                    color: _C.green.withOpacity(0.1), shape: BoxShape.circle),
                child: const Icon(Icons.local_taxi_rounded,
                    color: _C.green, size: 18)),
              const SizedBox(width: 10),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(DateFormat('dd MMM yyyy').format(date),
                    style: _t(13, FontWeight.w700, _C.text)),
                Text(DateFormat('hh:mm a').format(date),
                    style: _t(11, FontWeight.w500, _C.textSec)),
              ]),
              const Spacer(),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text('+₹${earn.toStringAsFixed(0)}',
                    style: _t(22, FontWeight.w800, _C.green)),
                Text('earned', style: _t(10, FontWeight.w500, _C.textTert)),
              ]),
            ]),

            const SizedBox(height: 12),
            const Divider(height: 1, color: _C.border),
            const SizedBox(height: 12),

            // Route
            Row(children: [
              Column(children: [
                Container(width: 8, height: 8,
                    decoration: const BoxDecoration(color: _C.green, shape: BoxShape.circle)),
                Container(width: 2, height: 26, color: _C.border),
                Container(width: 8, height: 8,
                    decoration: BoxDecoration(color: _C.red, borderRadius: BorderRadius.circular(2))),
              ]),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(pickup, style: _t(13, FontWeight.w500, _C.text),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 12),
                Text(drop, style: _t(13, FontWeight.w500, _C.textSec),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
              ])),
            ]),

            const SizedBox(height: 12),
            const Divider(height: 1, color: _C.border),
            const SizedBox(height: 10),

            // Earnings summary row
            Row(children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _iRow('Trip Fare', '₹${f.toStringAsFixed(0)}', _C.text, bold: true),
                const SizedBox(height: 4),
                _iRow(
                  plan && planNm.isNotEmpty
                      ? 'Commission ($pct% · $planNm)'
                      : pct > 0 ? 'Commission ($pct%)' : 'Commission',
                  comm == 0 ? '₹0 (zero fee)' : '−₹${comm.toStringAsFixed(0)}',
                  comm == 0 ? _C.green : _C.orange,
                ),
              ])),
              const Icon(Icons.chevron_right_rounded, color: _C.textTert, size: 20),
            ]),
          ]),
        ),
      ),
    );
  }

  Widget _iRow(String label, String val, Color valColor, {bool bold = false}) =>
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Expanded(child: Text(label,
            style: _t(12, bold ? FontWeight.w600 : FontWeight.w400, _C.textSec),
            overflow: TextOverflow.ellipsis)),
        Text(val, style: _t(12, bold ? FontWeight.w700 : FontWeight.w600, valColor)),
      ]);

  // ── Details bottom sheet ───────────────────────────────────────────────────

  void _showDetails(Map<String,dynamic> ride) => showModalBottomSheet(
    context: context, isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _detailsSheet(ride));

  Widget _detailsSheet(Map<String,dynamic> ride) {
    final earn   = earning(ride);
    final f      = fare(ride);
    final comm   = commission(ride);
    final pct    = commPct(ride);
    final inc    = incentive(ride);
    final plan   = planApplied(ride);
    final planNm = planName(ride);
    final date   = _rideDate(ride);
    final pickup = _addr(ride['pickup']);
    final drop   = _addr(ride['drop']);
    final payM   = ride['paymentMethod']?.toString() ?? 'Cash';
    final hasTxn = hasWallet(ride);

    // Savings vs 20% baseline (only meaningful if plan reduced commission)
    final baseComm   = f * 20 / 100;
    final planSaving = plan ? (baseComm - comm).clamp(0.0, double.infinity) : 0.0;

    return DraggableScrollableSheet(
      initialChildSize: 0.70, minChildSize: 0.45, maxChildSize: 0.92,
      builder: (ctx, scroll) => Container(
        decoration: const BoxDecoration(color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
        child: ListView(controller: scroll, children: [

          Center(child: Container(width: 40, height: 4,
            decoration: BoxDecoration(color: const Color(0xFFE0E0E0),
                borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 22),

          // Header
          Row(children: [
            Container(padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                  color: _C.green.withOpacity(0.12), shape: BoxShape.circle),
              child: const Icon(Icons.local_taxi_rounded, color: _C.green, size: 22)),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Trip Details', style: _t(16, FontWeight.w700, Colors.black87)),
              Text(DateFormat('dd MMM yyyy  hh:mm a').format(date),
                  style: _t(11, FontWeight.w400, Colors.grey.shade500)),
            ])),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text('+₹${earn.toStringAsFixed(0)}',
                  style: _t(26, FontWeight.w800, _C.green)),
              Text(hasTxn ? 'credited' : 'earned',
                  style: _t(10, FontWeight.w400, Colors.grey.shade500)),
            ]),
          ]),

          const SizedBox(height: 20),

          // Route
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: _C.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _C.border)),
            child: Column(children: [
              _dRow(Icons.trip_origin_rounded, 'Pickup', pickup, _C.green),
              Container(margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                  width: 1.5, height: 18, color: _C.border),
              _dRow(Icons.location_on_rounded, 'Drop', drop, _C.red),
            ]),
          ),

          const SizedBox(height: 18),

          // Earnings breakdown
          Text('EARNINGS BREAKDOWN',
              style: _t(10, FontWeight.w700, Colors.grey.shade400, ls: 1.2)),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(color: _C.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _C.border)),
            child: Column(children: [
              _eRow('Trip fare', '₹${f.toStringAsFixed(0)}', Colors.black87, bold: true),
              const SizedBox(height: 12),
              _eRow(
                plan && planNm.isNotEmpty
                    ? 'Commission ($pct% — $planNm)'
                    : pct > 0 ? 'Commission ($pct%)' : 'Commission',
                comm == 0 ? '−₹0 (zero fee)' : '−₹${comm.toStringAsFixed(0)}',
                comm == 0 ? _C.green : Colors.redAccent,
                labelColor: Colors.grey.shade600, fontSize: 13,
              ),
              if (inc > 0) ...[
                const SizedBox(height: 12),
                _eRow('Per-ride incentive', '+₹${inc.toStringAsFixed(0)}',
                    _C.blue, labelColor: Colors.grey.shade600, fontSize: 13),
              ],
              const SizedBox(height: 14),
              const Divider(height: 1, color: _C.border),
              const SizedBox(height: 14),
              _eRow('You Earned', '+₹${earn.toStringAsFixed(0)}',
                  _C.green, bold: true, fontSize: 15),
            ]),
          ),

          // Plan savings banner
          if (plan && planSaving > 0.5) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF0A2540), Color(0xFF1565C0)],
                  begin: Alignment.centerLeft, end: Alignment.centerRight),
                borderRadius: BorderRadius.circular(14)),
              child: Row(children: [
                Container(padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.15), shape: BoxShape.circle),
                  child: const Icon(Icons.verified_rounded,
                      color: Colors.white, size: 18)),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Plan Active — $planNm',
                      style: _t(11, FontWeight.w600, Colors.white70)),
                  const SizedBox(height: 3),
                  Text('You saved ₹${planSaving.toStringAsFixed(0)} on commission',
                      style: _t(13, FontWeight.w700, Colors.white)),
                ])),
                Text('₹${planSaving.toStringAsFixed(0)}',
                    style: _t(24, FontWeight.w800, Colors.white)),
              ]),
            ),
          ],

          const SizedBox(height: 14),

          // Payment badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: _C.primary.withOpacity(0.07),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _C.primary.withOpacity(0.15))),
            child: Row(children: [
              Icon(
                payM.toLowerCase() == 'cash'
                    ? Icons.payments_rounded : Icons.credit_card_rounded,
                color: _C.primary, size: 18),
              const SizedBox(width: 10),
              Text('Payment: $payM', style: _t(13, FontWeight.w600, _C.primary)),
            ]),
          ),

          SizedBox(height: MediaQuery.of(context).padding.bottom + 32),
        ]),
      ),
    );
  }

  Widget _dRow(IconData icon, String label, String value, Color iconColor) =>
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 18, color: iconColor),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: _t(10, FontWeight.w600, Colors.grey.shade500, ls: 0.5)),
          const SizedBox(height: 2),
          Text(value, style: _t(13, FontWeight.w600, Colors.black87)),
        ])),
      ]);

  Widget _eRow(String label, String value, Color valColor,
      {bool bold = false, Color? labelColor, double fontSize = 14}) =>
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Expanded(child: Text(label,
            style: _t(fontSize, bold ? FontWeight.w700 : FontWeight.w400,
                labelColor ?? Colors.black87),
            overflow: TextOverflow.ellipsis)),
        Text(value, style: _t(bold ? fontSize + 1 : fontSize,
            bold ? FontWeight.w800 : FontWeight.w600, valColor)),
      ]);

  // ── Empty / error ──────────────────────────────────────────────────────────

  Widget _emptyState(String label) => Center(child: Padding(
    padding: const EdgeInsets.all(40),
    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      const SizedBox(height: 60),
      Container(padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(color: _C.surface, shape: BoxShape.circle,
            border: Border.all(color: _C.border)),
        child: const Icon(Icons.history_rounded, size: 48, color: _C.textTert)),
      const SizedBox(height: 20),
      Text('No rides $label', style: _t(16, FontWeight.w700, _C.text)),
      const SizedBox(height: 8),
      Text('Completed rides appear here.\nHistory limited to the last 4 months.',
          style: _t(13, FontWeight.w400, _C.textSec), textAlign: TextAlign.center),
    ]),
  ));

  Widget _errorState() => Center(child: Padding(
    padding: const EdgeInsets.all(32),
    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      const Icon(Icons.wifi_off_rounded, size: 56, color: _C.red),
      const SizedBox(height: 16),
      Text('Something went wrong', style: _t(17, FontWeight.w700, _C.text)),
      const SizedBox(height: 8),
      Text(_error ?? 'Unknown error',
          style: _t(13, FontWeight.w400, _C.textSec), textAlign: TextAlign.center),
      const SizedBox(height: 24),
      ElevatedButton.icon(
        onPressed: _fetch,
        icon: const Icon(Icons.refresh_rounded), label: const Text('Retry'),
        style: ElevatedButton.styleFrom(
          backgroundColor: _C.primary, foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
      ),
    ]),
  ));

  // ── Helpers ────────────────────────────────────────────────────────────────

  String _addr(dynamic v) {
    if (v == null) return 'N/A';
    if (v is String) return v.isEmpty ? 'N/A' : v;
    if (v is Map) {
      return v['address']?.toString() ??
          v['name']?.toString() ??
          v['fullAddress']?.toString() ?? 'N/A';
    }
    return 'N/A';
  }
}