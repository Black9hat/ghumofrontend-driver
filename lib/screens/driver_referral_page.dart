import 'dart:convert';

import 'package:drivergoo/config.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _D {
  static const Color primary = Color.fromARGB(255, 212, 120, 0);
  static const Color background = Color(0xFFF5F7FA);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color text = Color(0xFF111827);
  static const Color textSub = Color(0xFF6B7280);
  static const Color divider = Color(0xFFE5E7EB);
  static const Color success = Color(0xFF15803D);
  static const Color warning = Color(0xFFF59E0B);
  static const Color error = Color(0xFFDC2626);
}

class DriverReferralData {
  final String referralCode;
  final String shareLink;
  final String deepLink;
  final int successfulCount;
  final int required;
  final int remaining;
  final bool milestoneReached;
  final bool rewardClaimed;
  final bool pendingClaim;
  final int pendingAmount;
  final List<Map<String, dynamic>> successfulFriends;
  final List<Map<String, dynamic>> pendingFriends;
  final bool systemEnabled;
  final int currentCycle;
  final int maxCycles;
  final bool cyclesExhausted;
  final int successfulTotal;
  final int rewardAmount;
  final int ridesToComplete;

  DriverReferralData({
    required this.referralCode,
    required this.shareLink,
    required this.deepLink,
    required this.successfulCount,
    required this.required,
    required this.remaining,
    required this.milestoneReached,
    required this.rewardClaimed,
    required this.pendingClaim,
    required this.pendingAmount,
    required this.successfulFriends,
    required this.pendingFriends,
    required this.systemEnabled,
    required this.currentCycle,
    required this.maxCycles,
    required this.cyclesExhausted,
    required this.successfulTotal,
    required this.rewardAmount,
    required this.ridesToComplete,
  });

  factory DriverReferralData.fromJson(Map<String, dynamic> json) {
    final progress = json['progress'] as Map<String, dynamic>? ?? {};
    final reward = json['reward'] as Map<String, dynamic>? ?? {};
    final referrals = json['referrals'] as Map<String, dynamic>? ?? {};
    final cycle = json['cycle'] as Map<String, dynamic>? ?? {};

    return DriverReferralData(
      referralCode: json['referralCode']?.toString() ?? '',
      shareLink: json['shareLink']?.toString() ?? '',
      deepLink: json['deepLink']?.toString() ?? '',
      successfulCount: (progress['successful'] as num?)?.toInt() ?? 0,
      required: (progress['required'] as num?)?.toInt() ?? 5,
      remaining: (progress['remaining'] as num?)?.toInt() ?? 5,
      milestoneReached: progress['milestoneReached'] == true,
      rewardClaimed: progress['rewardClaimed'] == true,
      pendingClaim: progress['pendingClaim'] == true,
      pendingAmount: (progress['pendingAmount'] as num?)?.toInt() ?? 0,
      successfulFriends: List<Map<String, dynamic>>.from(
        referrals['successful'] ?? const [],
      ),
      pendingFriends: List<Map<String, dynamic>>.from(
        referrals['pending'] ?? const [],
      ),
      systemEnabled: json['systemEnabled'] == true,
      currentCycle: (cycle['current'] as num?)?.toInt() ?? 0,
      maxCycles: (cycle['max'] as num?)?.toInt() ?? 3,
      cyclesExhausted: cycle['exhausted'] == true,
      successfulTotal: (cycle['successfulTotal'] as num?)?.toInt() ?? 0,
      rewardAmount: (reward['amount'] as num?)?.toInt() ?? 0,
      ridesToComplete: (reward['ridesToComplete'] as num?)?.toInt() ?? 1,
    );
  }
}

class DriverReferralPage extends StatefulWidget {
  const DriverReferralPage({super.key});

  @override
  State<DriverReferralPage> createState() => _DriverReferralPageState();
}

class _DriverReferralPageState extends State<DriverReferralPage> {
  final String _api = AppConfig.backendBaseUrl;
  static const String _playStoreUrl =
      'https://play.google.com/store/apps/details?id=com.ghumodriver.app';
  DriverReferralData? _data;
  bool _loading = true;
  bool _claiming = false;
  String? _error;
  bool _codeCopied = false;

  Future<String?> _token() async {
    try {
      return await FirebaseAuth.instance.currentUser?.getIdToken(true);
    } catch (_) {
      return null;
    }
  }

  Future<String?> _driverId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('driverId');
  }

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final driverId = await _driverId();
      if (driverId == null || driverId.isEmpty) {
        throw Exception('Driver ID missing. Please log in again.');
      }

      final token = await _token();
      if (token == null) {
        throw Exception('Session expired. Please log in again.');
      }

      final response = await http
          .get(
            Uri.parse('$_api/api/driver/referral/status/$driverId'),
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        if (body['success'] != true) {
          throw Exception(body['error'] ?? 'Failed to load referral data');
        }

        setState(() {
          _data = DriverReferralData.fromJson(body);
          _loading = false;
        });
      } else {
        final body = jsonDecode(response.body) as Map<String, dynamic>?;
        throw Exception(
          body?['error'] ?? 'Server error (${response.statusCode})',
        );
      }
    } catch (e) {
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  Future<void> _claimReward() async {
    if (_claiming) return;
    setState(() => _claiming = true);

    try {
      final driverId = await _driverId();
      final token = await _token();
      if (driverId == null || token == null) {
        throw Exception('Authentication error');
      }

      final response = await http
          .post(
            Uri.parse('$_api/api/driver/referral/claim/$driverId'),
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
          )
          .timeout(const Duration(seconds: 15));

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode == 200 && body['success'] == true) {
        HapticFeedback.heavyImpact();
        if (mounted) {
          await _showSuccessDialog(
            amount: (body['amountAwarded'] as num?)?.toInt() ?? 0,
            cyclesExhausted: body['cyclesExhausted'] == true,
          );
        }
        await _fetch();
      } else {
        throw Exception(body['error'] ?? 'Claim failed');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceFirst('Exception: ', '')),
            backgroundColor: _D.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _claiming = false);
    }
  }

  Future<void> _showSuccessDialog({
    required int amount,
    required bool cyclesExhausted,
  }) async {
    await showDialog(
      context: context,
      builder: (_) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('🎉', style: TextStyle(fontSize: 56)),
              const SizedBox(height: 12),
              Text(
                'Reward Claimed!',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: _D.text,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Wallet payout processed successfully',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  color: _D.textSub,
                ),
              ),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: _D.success.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  '₹$amount added to your driver wallet',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: _D.success,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                cyclesExhausted
                    ? 'Referral rewards are currently paused.'
                    : 'Keep referring more drivers to unlock the next payout.',
                textAlign: TextAlign.center,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  color: _D.textSub,
                ),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _D.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: Text(
                    'Nice!',
                    style: GoogleFonts.plusJakartaSans(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _copyCode() {
    if (_data == null) return;
    Clipboard.setData(ClipboardData(text: _data!.referralCode));
    HapticFeedback.lightImpact();
    setState(() => _codeCopied = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _codeCopied = false);
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Referral code copied'),
        backgroundColor: _D.primary,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _share() {
    if (_data == null) return;
    final data = _data!;
    final code = data.referralCode.trim();
    final installReferrer = Uri.encodeComponent('referralCode=$code');
    final driverStoreLink =
      '$_playStoreUrl&referrer=$installReferrer';
    final text =
      'Join me on GoIndia as a driver!\n\n'
      'Use my referral code $code when you sign up.\n\n'
      'Complete ${data.ridesToComplete} ride(s) after signup to help unlock referral reward.\n\n'
      'Download app: $driverStoreLink';
    Share.share(text, subject: 'Join Go India as a driver');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _D.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: Text(
          'Driver Referrals',
          style: GoogleFonts.plusJakartaSans(
            fontWeight: FontWeight.w700,
            color: _D.text,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: _D.text, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: _D.primary),
            onPressed: _fetch,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _D.primary))
          : _error != null
          ? _errorView()
          : RefreshIndicator(
              color: _D.primary,
              onRefresh: _fetch,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: Column(
                  children: [
                    _heroBanner(),
                    const SizedBox(height: 16),
                    _codeCard(),
                    const SizedBox(height: 16),
                    _progressCard(),
                    const SizedBox(height: 16),
                    _howItWorks(),
                    if ((_data!.successfulFriends + _data!.pendingFriends)
                        .isNotEmpty) ...[
                      const SizedBox(height: 16),
                      _friendsList(),
                    ],
                    const SizedBox(height: 28),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _errorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 36, color: _D.error),
            const SizedBox(height: 10),
            Text(
              'Could not load referral data',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: _D.text,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _error ?? '',
              textAlign: TextAlign.center,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                color: _D.textSub,
              ),
            ),
            const SizedBox(height: 18),
            ElevatedButton(
              onPressed: _fetch,
              style: ElevatedButton.styleFrom(
                backgroundColor: _D.primary,
                foregroundColor: Colors.white,
              ),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _heroBanner() {
    final data = _data!;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1A1A2E), Color(0xFF16213E)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: _D.primary.withOpacity(0.18),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              'Driver Referral Program',
              style: GoogleFonts.plusJakartaSans(
                color: _D.primary,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'Invite drivers,',
            style: GoogleFonts.plusJakartaSans(
              color: Colors.white,
              fontSize: 26,
              fontWeight: FontWeight.w800,
            ),
          ),
          Text(
            'Earn wallet rewards!',
            style: GoogleFonts.plusJakartaSans(
              color: _D.primary,
              fontSize: 26,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _badge('₹${data.rewardAmount}', 'Base reward'),
              const SizedBox(width: 10),
              _badge(
                data.remaining > 0 ? '${data.remaining}' : 'Done',
                'Drivers needed',
                color: data.remaining > 0 ? Colors.white : _D.success,
              ),
              const SizedBox(width: 10),
              _badge('${data.ridesToComplete}', 'Rides each'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _badge(String value, String label, {Color? color}) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color != null ? color.withOpacity(0.2) : Colors.white.withOpacity(0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: color != null ? color.withOpacity(0.4) : Colors.white.withOpacity(0.12),
          ),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: GoogleFonts.plusJakartaSans(
                color: color ?? Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: GoogleFonts.plusJakartaSans(
                color: color != null ? color.withOpacity(0.8) : Colors.white70,
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _codeCard() {
    final data = _data!;
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Your Driver Referral Code',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 13,
              color: _D.textSub,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 16),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF3E8),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: _D.primary.withOpacity(0.25),
                width: 1.5,
              ),
            ),
            child: Center(
              child: Text(
                data.referralCode,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  color: _D.primary,
                  letterSpacing: 4,
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: _copyCode,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    decoration: BoxDecoration(
                      color: _codeCopied ? _D.success : const Color(0xFFF3F4F6),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          _codeCopied ? Icons.check : Icons.copy_outlined,
                          size: 16,
                          color: _codeCopied ? Colors.white : _D.textSub,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _codeCopied ? 'Copied!' : 'Copy Code',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: _codeCopied ? Colors.white : _D.textSub,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: GestureDetector(
                  onTap: _data?.cyclesExhausted == true ? null : _share,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    decoration: BoxDecoration(
                      color: _data?.cyclesExhausted == true ? _D.divider : _D.primary,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          _data?.cyclesExhausted == true ? Icons.lock : Icons.share,
                          size: 16,
                          color: _data?.cyclesExhausted == true ? _D.textSub : Colors.white,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _data?.cyclesExhausted == true ? 'Program Paused' : 'Share',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: _data?.cyclesExhausted == true ? _D.textSub : Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _progressCard() {
    final data = _data!;
    final progressColor = data.pendingClaim
        ? _D.warning
        : data.milestoneReached
        ? _D.success
        : _D.primary;
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  'Your Progress',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: data.cyclesExhausted
                    ? _statusBadge('Program paused', _D.textSub, Icons.emoji_events)
                    : data.pendingClaim
                    ? _statusBadge('Claim ready', _D.warning, Icons.card_giftcard)
                    : data.milestoneReached
                    ? _statusBadge('Target reached', _D.success, Icons.check_circle)
                    : const SizedBox.shrink(),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: List.generate(data.required, (index) {
              final completed = index < data.successfulCount;
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Container(
                    height: 8,
                    decoration: BoxDecoration(
                      color: completed ? progressColor : _D.divider,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${data.successfulCount} / ${data.required} completed',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  color: _D.textSub,
                ),
              ),
              Text(
                data.milestoneReached ? 'Done' : '${data.remaining} left',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: progressColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (!data.cyclesExhausted)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF3E8),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '${data.ridesToComplete} ride(s) needed per referred driver',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: _D.primary,
                    ),
                  ),
                ),
                Text(
                  'Total referred: ${data.successfulTotal}',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    color: _D.textSub,
                  ),
                ),
              ],
            ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: data.cyclesExhausted
                  ? const Color(0xFFF3F4F6)
                  : data.pendingClaim
                  ? _D.warning.withOpacity(0.08)
                  : data.milestoneReached
                  ? _D.success.withOpacity(0.08)
                  : const Color(0xFFFFF3E8),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: progressColor.withOpacity(0.18)),
            ),
            child: Row(
              children: [
                Text(
                  data.cyclesExhausted
                      ? '🏁'
                      : data.pendingClaim
                      ? '🎁'
                      : data.milestoneReached
                      ? '✅'
                      : '🎯',
                  style: const TextStyle(fontSize: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        data.cyclesExhausted
                            ? 'Driver referral reward is currently paused.'
                            : data.pendingClaim
                            ? 'Target reached. Claim your wallet reward.'
                            : data.milestoneReached
                            ? 'Reward claimed. Keep referring more drivers.'
                            : 'Refer ${data.required} driver(s). Each must complete ${data.ridesToComplete} ride(s).',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: _D.text,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '₹${data.rewardAmount} driver wallet reward',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 12,
                          color: _D.textSub,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (data.pendingClaim && !data.cyclesExhausted) ...[
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _claiming ? null : _claimReward,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _D.warning,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: _claiming
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.wallet, size: 18),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              'Claim ₹${data.rewardAmount}',
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.plusJakartaSans(
                                fontWeight: FontWeight.w800,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _howItWorks() {
    final data = _data!;
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'How It Works',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 14),
          _step(
            Icons.share,
            _D.primary,
            'Share your code',
            'Send your referral code to another driver',
          ),
          _connector(),
          _step(
            Icons.person_add_outlined,
            Colors.blue,
            'Driver signs up',
            'They register using your code',
          ),
          _connector(),
          _step(
            Icons.directions_car_outlined,
            _D.primary,
            '${data.ridesToComplete} rides completed',
            'The referral counts only after each referred driver completes ${data.ridesToComplete} ride(s)',
          ),
          _connector(),
          _step(
            Icons.wallet_outlined,
            _D.warning,
            'Claim reward',
            'Claim the wallet payout from this page once the milestone is ready',
          ),
        ],
      ),
    );
  }

  Widget _friendsList() {
    final data = _data!;

    // Sort successful friends by potential earnings (descending)
    final sortedSuccessful = List<Map<String, dynamic>>.from(data.successfulFriends)
      ..sort((a, b) => (b['earnedAmount'] as num?)?.compareTo(a['earnedAmount'] as num? ?? 0) ?? 0);

    // Sort pending friends by rides progress (those closer to completion first)
    final sortedPending = List<Map<String, dynamic>>.from(data.pendingFriends)
      ..sort((a, b) {
        final aProgress = (a['ridesCompleted'] as num?)?.toInt() ?? 0;
        final bProgress = (b['ridesCompleted'] as num?)?.toInt() ?? 0;
        return bProgress.compareTo(aProgress);
      });

    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Referred Drivers',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                '${sortedSuccessful.length + sortedPending.length} total',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  color: _D.textSub,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (sortedSuccessful.isNotEmpty) ...[
            Text(
              'Completed (${sortedSuccessful.length})',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: _D.success,
              ),
            ),
            const SizedBox(height: 8),
            ...sortedSuccessful.map(
              (friend) {
                final earnedAmount = (friend['earnedAmount'] as num?)?.toInt() ?? data.rewardAmount;
                return _friendRow(
                  _getDisplayName(friend),
                  'Earned ₹$earnedAmount',
                  _D.success,
                  Icons.check_circle,
                  earnedAmount: earnedAmount,
                );
              },
            ),
          ],
          if (sortedPending.isNotEmpty) ...[
            if (sortedSuccessful.isNotEmpty) const SizedBox(height: 12),
            Text(
              'In Progress (${sortedPending.length})',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: _D.warning,
              ),
            ),
            const SizedBox(height: 8),
            ...sortedPending.map(
              (friend) {
                final ridesCompleted = (friend['ridesCompleted'] as num?)?.toInt() ?? 0;
                final ridesRequired = (friend['ridesRequired'] as num?)?.toInt() ?? data.ridesToComplete;
                final progressPercent = (ridesCompleted / ridesRequired * 100).toInt();
                return _friendRow(
                  _getDisplayName(friend),
                  'Rides $ridesCompleted/$ridesRequired ($progressPercent%)',
                  _D.warning,
                  Icons.schedule,
                  progressPercent: progressPercent,
                );
              },
            ),
          ],
          if (sortedSuccessful.isEmpty && sortedPending.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: Text(
                  'No drivers referred yet. Share your code to get started!',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    color: _D.textSub,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _card({required Widget child}) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _D.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _D.divider),
      ),
      child: child,
    );
  }

  String _getDisplayName(Map<String, dynamic> friend) {
    final name = friend['name']?.toString().trim() ?? '';
    final phone = friend['phone']?.toString() ?? '';

    if (name.isEmpty || name == 'New User' || name == 'Driver') {
      return phone.isNotEmpty ? '+91 $phone' : 'Driver';
    }

    if (phone.isNotEmpty) {
      return '$name (+91 $phone)';
    }

    return name;
  }

  Widget _statusBadge(String label, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 14),
          const SizedBox(width: 4),
          Text(
            label,
            style: GoogleFonts.plusJakartaSans(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _step(IconData icon, Color color, String title, String subtitle) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: _D.text,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    color: _D.textSub,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _connector() {
    return Padding(
      padding: const EdgeInsets.only(left: 17, top: 2, bottom: 2),
      child: Container(width: 2, height: 16, color: _D.divider),
    );
  }

  Widget _friendRow(
    String name,
    String status,
    Color color,
    IconData icon, {
    int? earnedAmount,
    int? progressPercent,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.16)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: _D.text,
                      ),
                    ),
                    Text(
                      status,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        color: _D.textSub,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (progressPercent != null) ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progressPercent / 100,
                minHeight: 4,
                backgroundColor: color.withOpacity(0.2),
                valueColor: AlwaysStoppedAnimation<Color>(color),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
