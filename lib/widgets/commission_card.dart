// lib/widgets/commission_card.dart
//
// ═══════════════════════════════════════════════════════════════════════════
// Commission Display Card - Shows current earnings structure
// ─────────────────────────────────────────────────────────────────────────────
// Displays:
//   • Commission % (what platform takes)
//   • Platform fees (flat + percentage)
//   • Per-ride incentives (cash + coins)
//   • "Last updated" timestamp
//
// Features:
//   • Real-time updates via CommissionService callbacks
//   • Graceful offline fallback (shows cached values)
//   • Expandable detail view
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:drivergoo/services/commission_service.dart';
import 'package:intl/intl.dart';

class CommissionCard extends StatefulWidget {
  const CommissionCard({Key? key}) : super(key: key);

  @override
  State<CommissionCard> createState() => _CommissionCardState();
}

class _CommissionCardState extends State<CommissionCard> {
  static const Color _cardBg = Color(0xFFFFFFFF);
  static const Color _accent = Color(0xFFD97706);
  static const Color _accentSoft = Color(0xFFFFF4E5);
  static const Color _textPrimary = Color(0xFF111827);
  static const Color _textSecondary = Color(0xFF6B7280);
  static const Color _border = Color(0xFFF3D3A4);

  late CommissionService _commissionService;
  CommissionConfig? _config;
  bool _isExpanded = false;

  @override
  void initState() {
    super.initState();
    _commissionService = CommissionService();
    _config = _commissionService.getConfig();

    // Listen for config updates
    _commissionService.onConfigUpdated = (newConfig) {
      if (mounted) {
        setState(() {
          _config = newConfig;
        });
      }
    };
  }

  @override
  void dispose() {
    // Clean up listener when widget is disposed
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_config == null) {
      return _buildLoadingCard();
    }

    return _buildConfigCard();
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Collapsed View - Quick Summary
  // ──────────────────────────────────────────────────────────────────────────

  Widget _buildConfigCard() {
    return GestureDetector(
      onTap: () => setState(() => _isExpanded = !_isExpanded),
      child: Container(
        margin: EdgeInsets.zero,
        decoration: BoxDecoration(
          color: _cardBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _border),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF111827).withOpacity(0.06),
              blurRadius: 16,
              offset: const Offset(0, 8),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Your Earnings Structure',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: _textSecondary,
                      letterSpacing: 0.3,
                    ),
                  ),
                  const SizedBox(height: 8),
                  RichText(
                    text: TextSpan(
                      style: GoogleFonts.plusJakartaSans(color: _textPrimary),
                      children: [
                        TextSpan(
                          text:
                              '${_config!.commissionPercent.toStringAsFixed(1)}% commission\n',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.2,
                            color: _textPrimary,
                          ),
                        ),
                        TextSpan(
                          text:
                              '+ ₹${_config!.perRideIncentive.toStringAsFixed(2)} incentive per ride',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: _accent,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: _accentSoft,
                    borderRadius: BorderRadius.circular(17),
                  ),
                  child: Icon(
                    _isExpanded ? Icons.expand_less : Icons.expand_more,
                    color: _accent,
                    size: 24,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _isExpanded ? 'Collapse' : 'Details',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    color: _textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 12),
        Divider(color: _border, height: 1),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildStatBadge(
                Icons.account_balance_wallet_rounded,
                'Platform Fee',
                '₹${_config!.platformFeeFlat.toStringAsFixed(2)}',
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildStatBadge(
                Icons.stars_rounded,
                'Coins/Ride',
                '${_config!.perRideCoins}',
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildStatBadge(IconData icon, String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: _accentSoft,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _border),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(icon, size: 16, color: _accent),
          const SizedBox(height: 4),
          Text(
            label,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 10,
              color: _textSecondary,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 14,
              color: _textPrimary,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Expanded View - Full Details
  // ──────────────────────────────────────────────────────────────────────────

  Widget _buildExpandedView() {
    final lastUpdated = _config!.fetchedAt != null
        ? DateFormat('MMM d, h:mm a').format(_config!.fetchedAt!)
        : 'Unknown';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Commission Breakdown',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: _textPrimary,
                letterSpacing: -0.5,
              ),
            ),
            GestureDetector(
              onTap: () => setState(() => _isExpanded = false),
              child: Icon(Icons.expand_less, color: _accent, size: 28),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Divider(color: _border, height: 1),
        const SizedBox(height: 16),
        _buildDetailRow(
          Icons.work_outline_rounded,
          'Commission',
          '${_config!.commissionPercent.toStringAsFixed(1)}% of fare',
          'Platform takes this percentage',
        ),
        const SizedBox(height: 12),
        _buildDetailRow(
          Icons.account_balance_wallet_outlined,
          'Flat Fee',
          '₹${_config!.platformFeeFlat.toStringAsFixed(2)} per ride',
          'Fixed charge per completed ride',
        ),
        const SizedBox(height: 12),
        if (_config!.platformFeePercent > 0)
          Column(
            children: [
              _buildDetailRow(
                Icons.insert_chart_outlined_rounded,
                'Fee %',
                '${_config!.platformFeePercent.toStringAsFixed(1)}% additional',
                'Applied on top of fare',
              ),
              const SizedBox(height: 12),
            ],
          ),
        _buildDetailRow(
          Icons.card_giftcard_outlined,
          'Per-Ride Bonus',
          '₹${_config!.perRideIncentive.toStringAsFixed(2)} + ${_config!.perRideCoins} coins',
          'Paid on every completed ride',
        ),
        const SizedBox(height: 16),
        Divider(color: _border, height: 1),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Last Updated',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                color: _textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              lastUpdated,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                color: _textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildDetailRow(
    IconData icon,
    String title,
    String value,
    String description,
  ) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _accentSoft,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _border),
      ),
      child: Row(
        children: [
          Icon(icon, color: _accent, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 14,
                    color: _textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    color: _textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    color: _textSecondary,
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

  // ──────────────────────────────────────────────────────────────────────────
  // Loading State
  // ──────────────────────────────────────────────────────────────────────────

  Widget _buildLoadingCard() {
    return Container(
      margin: EdgeInsets.zero,
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _border),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Your Earnings Structure',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: _textSecondary,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Container(
                width: 80,
                height: 24,
                decoration: BoxDecoration(
                  color: _accentSoft,
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 80,
                height: 24,
                decoration: BoxDecoration(
                  color: _accentSoft,
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Loading commission rates...',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 12,
              color: _textSecondary,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }
}
