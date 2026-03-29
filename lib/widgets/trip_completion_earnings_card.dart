// lib/widgets/trip_completion_earnings_card.dart - Detailed earnings after trip completion
// SHOWS COMPLETE BREAKDOWN: Commission, Incentive, Coins, Plan Bonus, Wallet

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class TripCompletionEarningsCard extends StatelessWidget {
  final String tripId;                    // Trip ID
  final String customerName;              // "Raj Kumar"
  final String pickupLocation;            // "Railway Station"
  final String dropLocation;              // "Airport"
  final double fare;                      // Base fare ₹200
  final int minutes;                      // 15 minutes
  final double distance;                  // 5 km
  final String rating;                    // "5.0"
  
  // 💰 Earnings breakdown
  final double commissionDeducted;        // ₹20 or ₹10 (if plan)
  final double netFareEarned;             // ₹180 or ₹190 (after commission)
  final double incentiveEarned;           // ₹5 or ₹6 (if plan boosted)
  final int coinsEarned;                  // 10 or 12 (if plan boosted)
  final double totalEarned;               // Sum of all
  
  // 🎯 Plan data (if applied)
  final String? planName;                 // "Gold Plan"
  final double? appliedCommissionRate;    // 10% (if plan)
  final double? appliedBonusMultiplier;   // 1.2x (if plan)
  final double? baseCommissionRate;       // 20% (base)
  final double? baseIncentive;            // ₹5 (base)
  final int? baseCoins;                   // 10 (base)
  
  // 💳 Wallet data
  final double previousBalance;           // ₹1000
  final double newBalance;                // ₹1245.50
  
  // 🎯 State
  final VoidCallback onClose;
  final VoidCallback? onViewDetails;

  const TripCompletionEarningsCard({
    Key? key,
    required this.tripId,
    required this.customerName,
    required this.pickupLocation,
    required this.dropLocation,
    required this.fare,
    required this.minutes,
    required this.distance,
    required this.rating,
    required this.commissionDeducted,
    required this.netFareEarned,
    required this.incentiveEarned,
    required this.coinsEarned,
    required this.totalEarned,
    this.planName,
    this.appliedCommissionRate,
    this.appliedBonusMultiplier,
    this.baseCommissionRate,
    this.baseIncentive,
    this.baseCoins,
    required this.previousBalance,
    required this.newBalance,
    required this.onClose,
    this.onViewDetails,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final hasPlan = planName != null;
    final bonusMultiplier = appliedBonusMultiplier ?? 1.0;

    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
      ),
      elevation: 0,
      backgroundColor: Colors.transparent,
      child: SingleChildScrollView(
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.15),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ✅ SUCCESS HEADER
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.green.shade400,
                      Colors.green.shade600,
                    ],
                  ),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(24),
                    topRight: Radius.circular(24),
                  ),
                ),
                child: Column(
                  children: [
                    // Checkmark animation
                    Container(
                      width: 70,
                      height: 70,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.3),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.check,
                        color: Colors.white,
                        size: 40,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Ride Completed!',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Thanks for the ride! Earnings added to wallet',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 13,
                        color: Colors.white.withOpacity(0.9),
                      ),
                    ),
                  ],
                ),
              ),

              // 👤 TRIP SUMMARY
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Customer & Rating
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              customerName,
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: Colors.black87,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '📍 $pickupLocation → $dropLocation',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 12,
                                color: Colors.black54,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                        // Rating badge
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.amber.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.star,
                                color: Colors.amber,
                                size: 16,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                rating,
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.amber,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),

                    // Trip details row
                    Row(
                      children: [
                        Expanded(
                          child: _buildDetailBox(
                            icon: '⏱️',
                            label: 'Duration',
                            value: '$minutes min',
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildDetailBox(
                            icon: '📏',
                            label: 'Distance',
                            value: '${distance.toStringAsFixed(1)} km',
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildDetailBox(
                            icon: '₹',
                            label: 'Base Fare',
                            value: '₹${fare.toStringAsFixed(0)}',
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 20),

                    // 💰 EARNINGS BREAKDOWN SECTION
                    _buildEarningsSection(hasPlan, bonusMultiplier),

                    const SizedBox(height: 20),

                    // 💳 WALLET UPDATE
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.blue.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.blue.withOpacity(0.2),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '💳 Wallet Updated',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Colors.blue,
                              letterSpacing: 0.3,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Previous Balance',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 13,
                                  color: Colors.black54,
                                ),
                              ),
                              Text(
                                '₹${previousBalance.toStringAsFixed(2)}',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.black87,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'This Ride Earnings',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 13,
                                  color: Colors.black54,
                                ),
                              ),
                              Text(
                                '+₹${totalEarned.toStringAsFixed(2)}',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.green,
                                ),
                              ),
                            ],
                          ),
                          const Divider(height: 16),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'New Balance',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.blue,
                                ),
                              ),
                              Text(
                                '₹${newBalance.toStringAsFixed(2)}',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.blue,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    // 🏆 PLAN BONUS NOTIFICATION (if applicable)
                    if (hasPlan)
                      Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.purple.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Colors.purple.withOpacity(0.3),
                            ),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.emoji_events,
                                color: Colors.purple,
                                size: 20,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  '🎯 Bonus: Your ${planName!} plan boosted earnings by ${((bonusMultiplier - 1) * 100).toStringAsFixed(0)}%!',
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.purple,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),

              // ✅ ACTION BUTTONS
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                child: Column(
                  children: [
                    if (onViewDetails != null)
                      SizedBox(
                        width: double.infinity,
                        height: 44,
                        child: OutlinedButton(
                          onPressed: onViewDetails,
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(
                              color: Color.fromARGB(255, 212, 120, 0),
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: Text(
                            'View Full Details',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: const Color.fromARGB(255, 212, 120, 0),
                            ),
                          ),
                        ),
                      ),
                    if (onViewDetails != null) const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        onPressed: onClose,
                        style: ElevatedButton.styleFrom(
                          backgroundColor:
                              const Color.fromARGB(255, 212, 120, 0),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text(
                          'Done',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 📊 BUILD EARNINGS SECTION
  Widget _buildEarningsSection(bool hasPlan, double bonusMultiplier) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '💰 Earnings Breakdown',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 12),

        if (hasPlan)
          // 🎯 PLAN SECTION (highlighted)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.purple.withOpacity(0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: Colors.purple.withOpacity(0.3),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.verified_user,
                      color: Colors.purple,
                      size: 16,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '$planName Applied',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Colors.purple,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                // Fare breakdown
                _buildEarningRow(
                  'Base Fare',
                  '₹${fare.toStringAsFixed(0)}',
                  Colors.black87,
                ),
                _buildEarningRow(
                  'Commission (${appliedCommissionRate?.toStringAsFixed(0)}%)',
                  '-₹${commissionDeducted.toStringAsFixed(2)}',
                  Colors.red,
                ),
                _buildEarningRow(
                  'Net Fare',
                  '₹${netFareEarned.toStringAsFixed(2)}',
                  Colors.black87,
                  isBold: true,
                ),
                const SizedBox(height: 8),
                // Incentive with bonus
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.amber.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Column(
                    children: [
                      _buildEarningRow(
                        'Per-ride Incentive (${bonusMultiplier}x bonus)',
                        '+₹${incentiveEarned.toStringAsFixed(2)}',
                        Colors.amber,
                        fontSize: 12,
                      ),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Coins Earned (${bonusMultiplier}x bonus)',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 12,
                              color: Colors.black54,
                            ),
                          ),
                          Row(
                            children: [
                              Icon(
                                Icons.monetization_on,
                                size: 14,
                                color: Colors.amber[700],
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '$coinsEarned',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.amber[700],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          )
        else
          // 📊 NO PLAN SECTION (regular)
          Column(
            children: [
              _buildEarningRow(
                'Base Fare',
                '₹${fare.toStringAsFixed(0)}',
                Colors.black87,
              ),
              _buildEarningRow(
                'Commission (${baseCommissionRate?.toStringAsFixed(0)}%)',
                '-₹${commissionDeducted.toStringAsFixed(2)}',
                Colors.red,
              ),
              _buildEarningRow(
                'Net Fare',
                '₹${netFareEarned.toStringAsFixed(2)}',
                Colors.black87,
                isBold: true,
              ),
              const SizedBox(height: 8),
              _buildEarningRow(
                'Per-ride Incentive',
                '+₹${incentiveEarned.toStringAsFixed(2)}',
                Colors.green,
              ),
              _buildEarningRow(
                'Coins Earned',
                '$coinsEarned',
                Colors.amber,
              ),
            ],
          ),

        const SizedBox(height: 12),

        // 💵 TOTAL EARNED
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 12,
          ),
          decoration: BoxDecoration(
            color: Colors.green.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: Colors.green.withOpacity(0.3),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '✅ Total Earnings',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: Colors.green,
                ),
              ),
              Text(
                '₹${totalEarned.toStringAsFixed(2)}',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: Colors.green,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // Helper: Detail box
  Widget _buildDetailBox({
    required String icon,
    required String label,
    required String value,
  }) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.grey.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            icon,
            style: const TextStyle(fontSize: 18),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 10,
              color: Colors.black54,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Colors.black87,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  // Helper: Earning row
  Widget _buildEarningRow(
    String label,
    String value,
    Color valueColor, {
    bool isBold = false,
    double fontSize = 13,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: GoogleFonts.plusJakartaSans(
              fontSize: fontSize,
              color: Colors.black54,
              fontWeight: isBold ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
          Text(
            value,
            style: GoogleFonts.plusJakartaSans(
              fontSize: fontSize,
              fontWeight: isBold ? FontWeight.w700 : FontWeight.w600,
              color: valueColor,
            ),
          ),
        ],
      ),
    );
  }
}
