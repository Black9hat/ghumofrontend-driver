// lib/widgets/trip_request_card.dart - Trip request card with earnings preview
// SHOWS: Estimated earnings with plan vs without plan comparison

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class TripRequestCard extends StatelessWidget {
  final double fare; // Trip fare (₹200)
  final double pickupLat;
  final double pickupLng;
  final double dropLat;
  final double dropLng;
  final String pickupLocationName; // "Bangalore Station"
  final String dropLocationName; // "Airport"
  final int estimatedMinutes; // 15 min
  final double estimatedKm; // 5 km
  final String customerName; // "Raj Kumar"
  final String vehicleType; // "auto", "bike"
  final VoidCallback onAccept;
  final VoidCallback onReject;

  // 🎯 NEW: Plan & Commission data
  final double? baseCommissionPercent; // 20%
  final double? planCommissionPercent; // 10% (if plan active)
  final double? bonusMultiplier; // 1.2x (if plan active)
  final double? perRideIncentive; // ₹5
  final String? activePlanName; // "Gold Plan"

  const TripRequestCard({
    Key? key,
    required this.fare,
    required this.pickupLat,
    required this.pickupLng,
    required this.dropLat,
    required this.dropLng,
    required this.pickupLocationName,
    required this.dropLocationName,
    required this.estimatedMinutes,
    required this.estimatedKm,
    required this.customerName,
    required this.vehicleType,
    required this.onAccept,
    required this.onReject,
    this.baseCommissionPercent,
    this.planCommissionPercent,
    this.bonusMultiplier,
    this.perRideIncentive,
    this.activePlanName,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.12),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 🎯 HEADER: Customer name & pickup location
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color.fromARGB(255, 212, 120, 0).withOpacity(0.05),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(20),
                  topRight: Radius.circular(20),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Customer name & pickup
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color.fromARGB(255, 212, 120, 0),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.person,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
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
                            Text(
                              '📍 $pickupLocationName',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 13,
                                color: Colors.black54,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      // ⏱️ Time badge
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.black12),
                        ),
                        child: Text(
                          '$estimatedMinutes min',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: const Color.fromARGB(255, 212, 120, 0),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // 🛣️ ROUTE: Pickup → Drop
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Pickup dot
                      Column(
                        children: [
                          Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                              color: const Color.fromARGB(255, 212, 120, 0),
                              shape: BoxShape.circle,
                            ),
                          ),
                          // Vertical line
                          Container(
                            width: 2,
                            height: 40,
                            color: Colors.black12,
                          ),
                          // Drop dot
                          Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                              color: const Color.fromARGB(255, 212, 120, 0),
                              shape: BoxShape.circle,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Pickup
                            Text(
                              pickupLocationName,
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Colors.black87,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 40),
                            // Drop
                            Text(
                              dropLocationName,
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Colors.black87,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      // 📏 Distance badge
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.blue.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '$estimatedKm km',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.blue,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // 💰 EARNINGS CARD - Simplified (Fare + Incentive only)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.purple.withOpacity(0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.purple.withOpacity(0.3)),
              ),
              child: _buildSimplifiedEarnings(),
            ),

            // ✅ ACTION BUTTONS
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  // ❌ Reject button
                  Expanded(
                    child: SizedBox(
                      height: 50,
                      child: OutlinedButton(
                        onPressed: onReject,
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Colors.red, width: 1.5),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text(
                          'Decline',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.red,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // ✅ Accept button
                  Expanded(
                    child: SizedBox(
                      height: 50,
                      child: ElevatedButton(
                        onPressed: onAccept,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color.fromARGB(
                            255,
                            212,
                            120,
                            0,
                          ),
                          foregroundColor: Colors.white,
                          elevation: 2,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text(
                          'Accept',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
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
    );
  }

  // 💰 BUILD EARNINGS BREAKDOWN - Simplified as per requirement
  Widget _buildSimplifiedEarnings() {
    final baseIncentive = perRideIncentive ?? 5.0;
    final planBonus = bonusMultiplier ?? 1.0;
    final incentiveAmount = activePlanName != null
        ? baseIncentive * planBonus
        : baseIncentive;

    final extraEarning = activePlanName != null
        ? (baseIncentive * planBonus) - baseIncentive
        : 0.0;

    final totalEarnings = fare + incentiveAmount;

    return Stack(
      children: [
        // Main earnings info
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ONE LINE: Earnings label with total and breakdown
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  'Earning',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: Colors.black54,
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    // Big total amount
                    Text(
                      '₹${totalEarnings.toStringAsFixed(0)}',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF16A34A),
                      ),
                    ),
                    // Small breakdown text
                    Text(
                      '${fare.toStringAsFixed(0)} + ${incentiveAmount.toStringAsFixed(0)} incentive',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: Colors.black54,
                      ),
                    ),
                  ],
                ),
              ],
            ),

            // Extra earning notification (if plan active)
            if (extraEarning > 0) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF3E0),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.trending_up,
                      size: 14,
                      color: Color(0xFFE65100),
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        "You're earning ₹${extraEarning.toStringAsFixed(0)} extra!",
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFFE65100),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),

        // Plan badge at TOP RIGHT CORNER
        if (activePlanName != null)
          Positioned(
            top: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: const Color(0xFFE8F5E9),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFC8E6C9)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.check_circle,
                    size: 12,
                    color: Color(0xFF2E7D32),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '$activePlanName Active',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF2E7D32),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
