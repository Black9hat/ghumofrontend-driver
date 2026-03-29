// lib/widgets/plan_aware_commission_card.dart
//
// ═══════════════════════════════════════════════════════════════════════════
// PLAN-AWARE COMMISSION CARD
// ─────────────────────────────────────────────────────────────────────────────
// Enhanced commission display that shows:
//   • Base rates (if no plan)
//   • Active plan rates (if plan is active)
//   • Bonus multiplier indicator (for plan earnings boost)
//   • Plan expiry countdown (if active)
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:drivergoo/services/plan_aware_commission_service.dart';

class PlanAwareCommissionCard extends StatefulWidget {
  const PlanAwareCommissionCard({Key? key}) : super(key: key);

  @override
  State<PlanAwareCommissionCard> createState() =>
      _PlanAwareCommissionCardState();
}

class _PlanAwareCommissionCardState extends State<PlanAwareCommissionCard> {
  late PlanAwareCommissionService _commissionService;
  PlanAwareCommissionConfig? _config;
  bool _isExpanded = false;

  @override
  void initState() {
    super.initState();
    _commissionService = PlanAwareCommissionService();
    _config = _commissionService.getConfig();

    _commissionService.onConfigUpdated = (newConfig) {
      if (mounted) {
        setState(() {
          _config = newConfig;
        });
      }
    };
  }

  @override
  Widget build(BuildContext context) {
    if (_config == null) {
      return _buildLoadingCard();
    }

    return _buildConfigCard();
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Collapsed View
  // ──────────────────────────────────────────────────────────────────────────

  Widget _buildConfigCard() {
    final hasActivePlan = _config!.activePlan?.isActive ?? false;

    return GestureDetector(
      onTap: () => setState(() => _isExpanded = !_isExpanded),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          gradient: hasActivePlan
              ? LinearGradient(
                  colors: [Color(0xFF7C3AED), Color(0xFF9F67FF)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : LinearGradient(
                  colors: [Color(0xFFFFA500), Color(0xFFFF8C00)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: hasActivePlan
                  ? Color(0xFF7C3AED).withOpacity(0.3)
                  : Color(0xFFFFA500).withOpacity(0.3),
              blurRadius: 8,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: _isExpanded ? _buildExpandedView() : _buildCollapsedView(),
        ),
      ),
    );
  }

  Widget _buildCollapsedView() {
    final hasActivePlan = _config!.activePlan?.isActive ?? false;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    hasActivePlan
                        ? '🎯 Your Active Plan'
                        : '💰 Base Commission',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.white70,
                      letterSpacing: 0.3,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (hasActivePlan) ...[
                    Text(
                      _config!.activePlan!.planName,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        _buildCommissionBadge(
                          _config!.effectiveCommissionPercent,
                        ),
                        const SizedBox(width: 8),
                        if (_config!.effectiveBonusMultiplier > 1.0)
                          _buildBonusBadge(
                              _config!.effectiveBonusMultiplier),
                      ],
                    ),
                  ] else ...[
                    Text(
                      '${_config!.baseCommissionPercent.toStringAsFixed(1)}% + ₹${_config!.basePerRideIncentive.toStringAsFixed(2)}<br/>per ride',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        letterSpacing: -0.5,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  _isExpanded ? Icons.expand_less : Icons.expand_more,
                  color: Colors.white,
                  size: 32,
                ),
                Text(
                  _isExpanded ? 'Close' : 'Details',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    color: Colors.white70,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 12),
        Divider(color: Colors.white30, height: 1),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildStatBadge(
                '💵',
                'Per-Ride',
                '₹${_config!.basePerRideIncentive.toStringAsFixed(2)}',
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildStatBadge(
                '⭐',
                'Coins',
                '${_config!.basePerRideCoins}',
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildCommissionBadge(double commission) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.2),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white30),
      ),
      child: Text(
        '${commission.toStringAsFixed(1)}% commission',
        style: GoogleFonts.plusJakartaSans(
          fontSize: 14,
          color: Colors.white,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildBonusBadge(double multiplier) {
    final bonusPercent = ((multiplier - 1.0) * 100).toStringAsFixed(0);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.amber.withOpacity(0.3),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.amber),
      ),
      child: Row(
        children: [
          Text(
            '🚀 +$bonusPercent% Boost',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 14,
              color: Colors.amber[100],
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatBadge(String icon, String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(icon, style: const TextStyle(fontSize: 16)),
          const SizedBox(height: 4),
          Text(
            label,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 10,
              color: Colors.white70,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 13,
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Expanded View
  // ──────────────────────────────────────────────────────────────────────────

  Widget _buildExpandedView() {
    final hasActivePlan = _config!.activePlan?.isActive ?? false;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              hasActivePlan ? '🎯 Plan Details' : '📊 Commission Breakdown',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: Colors.white,
                letterSpacing: -0.5,
              ),
            ),
            GestureDetector(
              onTap: () => setState(() => _isExpanded = false),
              child: Icon(Icons.expand_less, color: Colors.white, size: 28),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Divider(color: Colors.white30, height: 1),
        const SizedBox(height: 16),
        // Active Plan Section
        if (hasActivePlan) ...[
          _buildDetailRow(
            '🎯 Plan Name',
            _config!.activePlan!.planName,
            'Your current subscription',
          ),
          const SizedBox(height: 12),
        ],
        // Commission Section
        _buildDetailRow(
          '💼 Commission',
          hasActivePlan
              ? _config!.activePlan!.noCommission
                  ? '0% (Waived!)'
                  : '${_config!.activePlan!.commissionRate.toStringAsFixed(1)}%'
              : '${_config!.baseCommissionPercent.toStringAsFixed(1)}%',
          hasActivePlan
              ? 'Your plan rate'
              : 'Default rate (Base)',
        ),
        const SizedBox(height: 12),
        // Bonus Multiplier (Plan only)
        if (hasActivePlan && _config!.effectiveBonusMultiplier > 1.0) ...[
          _buildDetailRow(
            '🚀 Earning Boost',
            '${((_config!.effectiveBonusMultiplier - 1.0) * 100).toStringAsFixed(0)}% more earnings',
            'Plan bonus multiplier',
          ),
          const SizedBox(height: 12),
        ],
        // Per-Ride Incentive
        _buildDetailRow(
          '💰 Per-Ride Incentive',
          '₹${_config!.basePerRideIncentive.toStringAsFixed(2)} + ${_config!.basePerRideCoins} coins',
          'On every completed ride',
        ),
        const SizedBox(height: 12),
        // Platform Fee
        _buildDetailRow(
          '💵 Platform Fee',
          '₹${_config!.basePlatformFeeFlat.toStringAsFixed(2)}${_config!.basePlatformFeePercent > 0 ? " + ${_config!.basePlatformFeePercent.toStringAsFixed(1)}%" : ""}',
          'Per ride surcharge',
        ),
        // Plan Expiry Info
        if (hasActivePlan) ...[
          const SizedBox(height: 16),
          Divider(color: Colors.white30, height: 1),
          const SizedBox(height: 12),
          _buildExpiryInfo(_config!.activePlan!),
        ],
      ],
    );
  }

  Widget _buildDetailRow(String icon, String title, String subtitle) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Text(icon, style: const TextStyle(fontSize: 20)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 14,
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    color: Colors.white70,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExpiryInfo(ActivePlanInfo plan) {
    final daysLeft = plan.expiryDate.difference(DateTime.now()).inDays;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.amber.withOpacity(0.2),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.amber.withOpacity(0.5)),
      ),
      child: Row(
        children: [
          const Text('⏰', style: TextStyle(fontSize: 20)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Plan Expires In',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 14,
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  daysLeft > 0
                      ? '$daysLeft days remaining'
                      : 'Plan expired - renew to use benefits',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    color: daysLeft > 0 ? Colors.amber[100] : Colors.red[200],
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Loading State
  // ──────────────────────────────────────────────────────────────────────────

  Widget _buildLoadingCard() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFFB0B0B0), Color(0xFF808080)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Commission & Plan Details',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.white70,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 12),
          ShimmerLoader(),
        ],
      ),
    );
  }
}

// Simple shimmer loading placeholder
class ShimmerLoader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: double.infinity,
          height: 20,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.2),
            borderRadius: BorderRadius.circular(6),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Container(
                height: 16,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Container(
                height: 16,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
