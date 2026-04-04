import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class IncentivesPage extends StatelessWidget {
  final String? customerId;
  final String? driverId;

  const IncentivesPage({Key? key, this.customerId, this.driverId})
    : super(key: key);

  static const Color _kBg = Color(0xFFF7F8FC);
  static const Color _kCard = Color(0xFFFFFFFF);
  static const Color _kPrimary = Color(0xFFD97706);
  static const Color _kText = Color(0xFF101828);
  static const Color _kSubText = Color(0xFF667085);
  static const Color _kBorder = Color(0xFFE4E7EC);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: _kCard,
        elevation: 0,
        centerTitle: true,
        iconTheme: const IconThemeData(color: _kText),
        surfaceTintColor: Colors.transparent,
        title: Text(
          'Incentives',
          style: GoogleFonts.plusJakartaSans(
            color: _kText,
            fontWeight: FontWeight.w800,
            fontSize: 19,
          ),
        ),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Container(
            width: double.infinity,
            constraints: const BoxConstraints(maxWidth: 460),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 22),
            decoration: BoxDecoration(
              color: _kCard,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _kBorder),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x0A101828),
                  blurRadius: 16,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    color: _kPrimary.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.local_offer_outlined,
                    color: _kPrimary,
                    size: 28,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'Incentive Data Coming Soon',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.plusJakartaSans(
                    color: _kText,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Plan details are now available on the Plans page. Incentive details from backend will be shown here once ready.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.plusJakartaSans(
                    color: _kSubText,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
