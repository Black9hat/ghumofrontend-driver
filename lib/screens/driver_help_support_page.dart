import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

// --- COLOR PALETTE ---
class AppColors {
  static const Color primary = Color.fromARGB(255, 212, 120, 0);
  static const Color background = Colors.white;
  static const Color onSurface = Colors.black;
  static const Color surface = Color(0xFFF5F5F5);
  static const Color onPrimary = Colors.white;
  static const Color onSurfaceSecondary = Colors.black54;
  static const Color onSurfaceTertiary = Colors.black38;
  static const Color divider = Color(0xFFEEEEEE);
  static const Color success = Color.fromARGB(255, 0, 66, 3);
  static const Color warning = Color(0xFFFFA000);
  static const Color error = Color(0xFFD32F2F);
}

// --- TYPOGRAPHY ---
class AppTextStyles {
  static TextStyle get heading2 => GoogleFonts.plusJakartaSans(
    fontSize: 24,
    fontWeight: FontWeight.w700,
    color: AppColors.onSurface,
    letterSpacing: -0.3,
  );

  static TextStyle get heading3 => GoogleFonts.plusJakartaSans(
    fontSize: 18,
    fontWeight: FontWeight.w600,
    color: AppColors.onSurface,
  );

  static TextStyle get body1 => GoogleFonts.plusJakartaSans(
    fontSize: 16,
    fontWeight: FontWeight.w500,
    color: AppColors.onSurface,
  );

  static TextStyle get body2 => GoogleFonts.plusJakartaSans(
    fontSize: 14,
    fontWeight: FontWeight.w500,
    color: AppColors.onSurfaceSecondary,
  );

  static TextStyle get caption => GoogleFonts.plusJakartaSans(
    fontSize: 12,
    fontWeight: FontWeight.w500,
    color: AppColors.onSurfaceTertiary,
    letterSpacing: 0.5,
  );
}

class DriverHelpSupportPage extends StatefulWidget {
  final String driverId;

  const DriverHelpSupportPage({Key? key, required this.driverId})
    : super(key: key);

  @override
  State<DriverHelpSupportPage> createState() => _DriverHelpSupportPageState();
}

class _DriverHelpSupportPageState extends State<DriverHelpSupportPage>
    with SingleTickerProviderStateMixin {
  // ✅ Constants - Change these anytime
  static const String supportPhone = '8341132728';
  static const String whatsappNumber = '8341132728';

  // ✅ Backend base - PRODUCTION setup (no development URLs)
  // Uses AppConfig.backendBaseUrl for environment-based configuration
  // Prevents hardcoded ngrok/localhost URLs that cause Play Store rejection
  static const String _apiBase =
      "https://api.ghumopartner.com"; // ← Set to your production domain

  // Controllers
  final TextEditingController _faqSearchController = TextEditingController();
  final TextEditingController _ticketMessageController =
      TextEditingController();
  final ScrollController _scrollController = ScrollController();
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  String _faqSearchText = '';
  String _selectedIssueType = 'App Issue';
  bool _submitting = false;
  bool _isCollapsed = false;
  final FocusNode _searchFocusNode = FocusNode();

  // ✅ NEW: Ticket tracking state
  String? _activeTicketId;
  String? _activeTicketIssue;
  DateTime? _activeTicketCreatedAt;

  final List<String> _issueTypes = const [
    'App Issue',
    'Payment Issue',
    'Trip Issue',
    'Account Issue',
    'Documents Issue',
    'Safety Issue',
    'Other',
  ];

  // ✅ Driver FAQs
  final List<Map<String, String>> _faqs = const [
    {
      'q': 'Not getting rides',
      'a':
          '✅ Check these:\n'
          '1) Go ON DUTY\n'
          '2) GPS ON + Location permission allowed\n'
          '3) Internet stable\n'
          '4) Vehicle type matches\n'
          '5) Restart app once',
    },
    {
      'q': 'Customer not responding at pickup',
      'a':
          '1) Call customer 2 times\n'
          '2) Wait 2–3 minutes\n'
          '3) If no response, cancel safely and go ON DUTY',
    },
    {
      'q': 'Pickup location is wrong',
      'a':
          'Confirm correct pickup point by call/chat.\n'
          'If pickup is too far/unsafe, cancel and report.',
    },
    {
      'q': 'Drop location changed',
      'a':
          'Confirm new drop location.\n'
          'Continue only if safe.\n'
          'If major change, contact support.',
    },
    {
      'q': 'Customer cancelled after I accepted',
      'a':
          'No action needed.\n'
          'Trip removes automatically.\n'
          'Stay ON DUTY for new requests.',
    },
    {
      'q': 'Wallet not updated',
      'a':
          '✅ Try this:\n'
          '1) Confirm cash collection (cash trips)\n'
          '2) Refresh wallet\n'
          '3) Restart app\n'
          'If still not updated, raise a ticket.',
    },
    {
      'q': 'Pending commission is high',
      'a':
          'High pending commission can reduce rides.\n'
          'Pay from Wallet → Pay Now via UPI.',
    },
    {
      'q': 'Ride request disappeared quickly',
      'a':
          'Ride requests expire fast.\n'
          'Accept quickly (especially peak hours).',
    },
    {
      'q': 'App slow / stuck / crash',
      'a':
          '✅ Fix steps:\n'
          '1) Close app → open again\n'
          '2) ON/OFF internet\n'
          '3) GPS ON\n'
          '4) Clear cache / reinstall',
    },
    {
      'q': 'How to increase earnings',
      'a':
          '✅ Best tips:\n'
          '1) Drive peak hours\n'
          '2) Avoid cancellations\n'
          '3) Complete incentives\n'
          '4) Maintain ratings',
    },
  ];

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOut,
    );
    _animationController.forward();

    _scrollController.addListener(_onScroll);

    _faqSearchController.addListener(() {
      setState(() {
        _faqSearchText = _faqSearchController.text.trim().toLowerCase();
      });
    });

    // ✅ Load active tickets on init
    _loadActiveTickets();
  }

  void _onScroll() {
    final isCollapsed =
        _scrollController.hasClients &&
        _scrollController.offset > (120 - kToolbarHeight);
    if (isCollapsed != _isCollapsed) {
      setState(() {
        _isCollapsed = isCollapsed;
      });
    }
  }

  @override
  void dispose() {
    _faqSearchController.dispose();
    _ticketMessageController.dispose();
    _animationController.dispose();
    _searchFocusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // ===========================================================================
  // ✅ NEW: LOAD ACTIVE TICKETS FOR THIS DRIVER
  // ===========================================================================
  Future<void> _loadActiveTickets() async {
    debugPrint('Loading tickets...');

    try {
      final prefs = await SharedPreferences.getInstance();
      final jwt = prefs.getString('token');

      final headers = <String, String>{'Content-Type': 'application/json'};
      if (jwt != null) headers['Authorization'] = 'Bearer $jwt';

      final response = await http
          .get(
            Uri.parse(
              '$_apiBase/api/support/driver/my-tickets/${widget.driverId}',
            ),
            headers: headers,
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true &&
            data['tickets'] != null &&
            (data['tickets'] as List).isNotEmpty) {
          final ticket = data['tickets'][0]; // Get most recent active ticket
          setState(() {
            _activeTicketId = ticket['_id'];
            _activeTicketIssue = ticket['issueType'];
            _activeTicketCreatedAt = DateTime.parse(ticket['createdAt']);
          });
        }
      }
    } catch (e) {
      print('Error loading active tickets: $e');
    } finally {
      debugPrint('Finished loading tickets');
    }
  }

  // ===========================================================================
  // CALL / WHATSAPP
  // ===========================================================================

  Future<void> _makePhoneCall(String phone) async {
    HapticFeedback.lightImpact();
    final uri = Uri(scheme: 'tel', path: phone);
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  Future<void> _openWhatsApp(String number) async {
    HapticFeedback.lightImpact();
    final uri = Uri.parse("https://wa.me/$number");
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  // ===========================================================================
  // ✅ ENHANCED: TICKET SUBMIT WITH DUPLICATE CHECK
  // ===========================================================================

  Future<void> _submitTicket() async {
    final msg = _ticketMessageController.text.trim();

    if (msg.isEmpty) {
      _showSnack('Please describe your issue', isError: true);
      return;
    }

    // ✅ Check if there's already an active ticket for this issue
    if (_activeTicketId != null && _activeTicketIssue != null) {
      final normalizedActive = _normalizeIssueType(_activeTicketIssue!);
      final normalizedNew = _normalizeIssueType(_selectedIssueType);

      if (normalizedActive == normalizedNew) {
        _showActiveTicketDialog();
        return;
      }
    }

    if (_submitting) return;
    setState(() => _submitting = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      final jwt = prefs.getString('token');

      final headers = <String, String>{'Content-Type': 'application/json'};
      if (jwt != null) headers['Authorization'] = 'Bearer $jwt';

      final response = await http
          .post(
            Uri.parse('$_apiBase/api/support/driver/ticket'),
            headers: headers,
            body: jsonEncode({
              'driverId': widget.driverId,
              'issueType': _selectedIssueType,
              'message': msg,
            }),
          )
          .timeout(const Duration(seconds: 12));

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body);
        final ticketId = data['ticketId'] ?? data['_id'] ?? '';

        HapticFeedback.mediumImpact();

        final savedIssueType = _selectedIssueType;

        setState(() {
          _selectedIssueType = 'App Issue';
          _ticketMessageController.clear();
          _activeTicketId = ticketId;
          _activeTicketIssue = savedIssueType;
          _activeTicketCreatedAt = DateTime.now();
        });

        _showTicketSuccessDialog(ticketId);
      } else {
        final errorData = jsonDecode(response.body);
        _showSnack(
          errorData['message'] ?? 'Failed to submit ticket',
          isError: true,
        );
      }
    } catch (e) {
      _showSnack('Network error. Please check your connection.', isError: true);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  // ===========================================================================
  // ✅ NEW: NORMALIZE ISSUE TYPE FOR COMPARISON
  // ===========================================================================
  String _normalizeIssueType(String issueType) {
    return issueType
        .toLowerCase()
        .replaceAll(' ', '_')
        .replaceAll('issue', '')
        .trim();
  }

  // ===========================================================================
  // ✅ NEW: DISPLAY ISSUE TYPE IN READABLE FORMAT
  // ===========================================================================
  String _displayIssueType(String issueType) {
    return issueType
        .replaceAll('_', ' ')
        .split(' ')
        .map(
          (word) => word.isNotEmpty
              ? word[0].toUpperCase() + word.substring(1)
              : word,
        )
        .join(' ');
  }

  // ===========================================================================
  // ✅ NEW: SHOW TICKET SUCCESS DIALOG
  // ===========================================================================
  void _showTicketSuccessDialog(String ticketId) {
    final displayTicketId = ticketId.length >= 8
        ? ticketId.toUpperCase().substring(ticketId.length - 8)
        : ticketId.toUpperCase();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        contentPadding: const EdgeInsets.all(24),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.success.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.check_circle_rounded,
                color: AppColors.success,
                size: 48,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Ticket Created!',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: AppColors.success,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.primary.withOpacity(0.3)),
              ),
              child: Column(
                children: [
                  Text(
                    'Your Ticket ID',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.onSurfaceSecondary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  SelectableText(
                    displayTicketId,
                    style: GoogleFonts.robotoMono(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary,
                      letterSpacing: 2,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '✅ Your issue is under review',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AppColors.onSurface,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Our support team will review and resolve your ticket within 24 hours.',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: AppColors.onSurfaceSecondary,
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.warning.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.warning.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.phone_in_talk_rounded,
                    color: AppColors.warning,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Need urgent help? Call support with your ticket ID',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.warning,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: ticketId));
                      _showSnack('Ticket ID copied!');
                    },
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      side: const BorderSide(color: AppColors.primary),
                    ),
                    child: Text(
                      'Copy ID',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      'Got it',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.onPrimary,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // ✅ NEW: SHOW ACTIVE TICKET DIALOG
  // ===========================================================================
  void _showActiveTicketDialog() {
    final ticketAge = DateTime.now().difference(_activeTicketCreatedAt!);
    final hoursRemaining = 24 - ticketAge.inHours;

    final displayTicketId = _activeTicketId!.length >= 8
        ? _activeTicketId!.toUpperCase().substring(_activeTicketId!.length - 8)
        : _activeTicketId!.toUpperCase();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        contentPadding: const EdgeInsets.all(24),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.warning.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.info_rounded,
                color: AppColors.warning,
                size: 48,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Active Ticket Found',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: AppColors.warning,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  Text(
                    'Ticket ID',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppColors.onSurfaceSecondary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  SelectableText(
                    displayTicketId,
                    style: GoogleFonts.robotoMono(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary,
                      letterSpacing: 2,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'You already have an active ticket for "${_displayIssueType(_activeTicketIssue!)}"',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.onSurface,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              hoursRemaining > 0
                  ? 'Expected resolution: ~$hoursRemaining hours'
                  : 'Review in progress',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: AppColors.onSurfaceSecondary,
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.phone_rounded,
                    color: AppColors.primary,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Call $supportPhone with your ticket ID for immediate assistance',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      Navigator.pop(context);
                      _makePhoneCall(supportPhone);
                    },
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      side: const BorderSide(color: AppColors.primary),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.phone,
                          size: 18,
                          color: AppColors.primary,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Call Now',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: AppColors.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      'Okay',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.onPrimary,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showSnack(String text, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              isError ? Icons.error_outline : Icons.check_circle_outline,
              color: AppColors.onPrimary,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                text,
                style: GoogleFonts.plusJakartaSans(
                  fontWeight: FontWeight.w600,
                  color: AppColors.onPrimary,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: isError ? AppColors.error : AppColors.success,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filteredFaqs = _faqs.where((item) {
      final q = (item['q'] ?? '').toLowerCase();
      final a = (item['a'] ?? '').toLowerCase();
      return q.contains(_faqSearchText) || a.contains(_faqSearchText);
    }).toList();

    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        controller: _scrollController,
        slivers: [
          _buildSliverAppBar(),
          SliverToBoxAdapter(
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHeaderCard(),
                    const SizedBox(height: 28),
                    _buildQuickActionsSection(),
                    const SizedBox(height: 32),
                    _buildFAQSection(filteredFaqs),
                    const SizedBox(height: 32),
                    _buildTicketSection(),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // SLIVER APP BAR
  // ===========================================================================

  Widget _buildSliverAppBar() {
    return SliverAppBar(
      expandedHeight: 120,
      floating: false,
      pinned: true,
      elevation: 0,
      scrolledUnderElevation: 0.5,
      backgroundColor: AppColors.background,
      surfaceTintColor: Colors.transparent,
      leading: IconButton(
        icon: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(
            Icons.arrow_back_ios_new,
            size: 18,
            color: AppColors.onSurface,
          ),
        ),
        onPressed: () => Navigator.pop(context),
      ),
      title: AnimatedOpacity(
        opacity: _isCollapsed ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 200),
        child: Text(
          'Help & Support',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: AppColors.onSurface,
          ),
        ),
      ),
      flexibleSpace: FlexibleSpaceBar(
        collapseMode: CollapseMode.pin,
        background: SafeArea(
          child: Padding(
            padding: const EdgeInsets.only(left: 20, bottom: 16, top: 50),
            child: Align(
              alignment: Alignment.bottomLeft,
              child: AnimatedOpacity(
                opacity: _isCollapsed ? 0.0 : 1.0,
                duration: const Duration(milliseconds: 200),
                child: Text(
                  'Help & Support',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: AppColors.onSurface,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
      actions: [
        Container(
          margin: const EdgeInsets.only(right: 16),
          child: IconButton(
            icon: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.headset_mic_outlined,
                size: 20,
                color: AppColors.primary,
              ),
            ),
            onPressed: () => _makePhoneCall(supportPhone),
          ),
        ),
      ],
    );
  }

  // ===========================================================================
  // HEADER CARD
  // ===========================================================================

  Widget _buildHeaderCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.primary, AppColors.primary.withOpacity(0.85)],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withOpacity(0.3),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Need Help?',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: AppColors.onPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'We\'re here 24/7 to assist you with any issues or questions.',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: AppColors.onPrimary.withOpacity(0.9),
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.onPrimary.withOpacity(0.2),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.support_agent_rounded,
              size: 36,
              color: AppColors.onPrimary,
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // QUICK ACTIONS SECTION
  // ===========================================================================

  Widget _buildQuickActionsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(
          title: 'Quick Actions',
          subtitle: 'Get instant support',
          icon: Icons.flash_on_rounded,
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _buildActionCard(
                icon: Icons.phone_in_talk_rounded,
                title: 'Call Support',
                subtitle: supportPhone,
                gradientColors: [const Color(0xFFFF6B35), AppColors.primary],
                onTap: () => _makePhoneCall(supportPhone),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: _buildActionCard(
                icon: Icons.chat_rounded,
                title: 'WhatsApp',
                subtitle: whatsappNumber,
                gradientColors: [
                  const Color(0xFF25D366),
                  const Color(0xFF128C7E),
                ],
                onTap: () => _openWhatsApp(whatsappNumber),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildActionCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required List<Color> gradientColors,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.divider, width: 1.5),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: gradientColors),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: gradientColors.first.withOpacity(0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Icon(icon, color: AppColors.onPrimary, size: 24),
              ),
              const SizedBox(height: 14),
              Text(
                title,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.onSurface,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: AppTextStyles.caption,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // FAQ SECTION
  // ===========================================================================

  Widget _buildFAQSection(List<Map<String, String>> filteredFaqs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(
          title: 'Frequently Asked',
          subtitle: 'Find quick answers',
          icon: Icons.help_outline_rounded,
        ),
        const SizedBox(height: 16),
        _buildSearchBar(),
        const SizedBox(height: 18),
        if (filteredFaqs.isEmpty)
          _buildEmptyFaqWidget()
        else
          ...filteredFaqs.asMap().entries.map(
            (entry) =>
                _buildFaqTile(entry.value['q']!, entry.value['a']!, entry.key),
          ),
      ],
    );
  }

  Widget _buildSearchBar() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _searchFocusNode.hasFocus
              ? AppColors.primary.withOpacity(0.5)
              : Colors.transparent,
          width: 2,
        ),
      ),
      child: TextField(
        controller: _faqSearchController,
        focusNode: _searchFocusNode,
        style: AppTextStyles.body1,
        decoration: InputDecoration(
          prefixIcon: const Icon(
            Icons.search_rounded,
            color: AppColors.onSurfaceTertiary,
            size: 22,
          ),
          suffixIcon: _faqSearchText.isNotEmpty
              ? IconButton(
                  icon: const Icon(
                    Icons.close_rounded,
                    size: 20,
                    color: AppColors.onSurfaceTertiary,
                  ),
                  onPressed: () {
                    _faqSearchController.clear();
                    _searchFocusNode.unfocus();
                  },
                )
              : null,
          hintText: 'Search for help...',
          hintStyle: GoogleFonts.plusJakartaSans(
            fontSize: 15,
            fontWeight: FontWeight.w500,
            color: AppColors.onSurfaceTertiary,
          ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 16,
          ),
        ),
        onTap: () => setState(() {}),
        onSubmitted: (_) => setState(() {}),
      ),
    );
  }

  Widget _buildEmptyFaqWidget() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.warning.withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.warning.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.warning.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.search_off_rounded,
              color: AppColors.warning,
              size: 24,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'No results found',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Try different keywords or raise a ticket',
                  style: AppTextStyles.caption,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFaqTile(String question, String answer, int index) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
          childrenPadding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
          leading: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Center(
              child: Text(
                '${index + 1}',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primary,
                ),
              ),
            ),
          ),
          iconColor: AppColors.primary,
          collapsedIconColor: AppColors.onSurfaceTertiary,
          title: Text(
            question,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.onSurface,
            ),
          ),
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                answer,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: AppColors.onSurfaceSecondary,
                  height: 1.6,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // ✅ ENHANCED: TICKET SECTION WITH ACTIVE TICKET INDICATOR
  // ===========================================================================

  Widget _buildTicketSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(
          title: 'Raise a Ticket',
          subtitle: 'We\'ll call you back',
          icon: Icons.confirmation_number_outlined,
        ),

        // ✅ Show active ticket banner if exists
        if (_activeTicketId != null) ...[
          const SizedBox(height: 12),
          _buildActiveTicketBanner(),
        ],

        const SizedBox(height: 8),
        Text(
          'If support line is busy, submit a ticket and our team will contact you shortly.',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: AppColors.onSurfaceTertiary,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 20),
        _buildTicketForm(),
      ],
    );
  }

  // ===========================================================================
  // ✅ NEW: BUILD ACTIVE TICKET BANNER
  // ===========================================================================
  Widget _buildActiveTicketBanner() {
    final ticketAge = DateTime.now().difference(_activeTicketCreatedAt!);
    final isOverdue = ticketAge.inHours > 24;

    final displayTicketId = _activeTicketId!.length >= 8
        ? _activeTicketId!.toUpperCase().substring(_activeTicketId!.length - 8)
        : _activeTicketId!.toUpperCase();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isOverdue
              ? [
                  AppColors.warning.withOpacity(0.1),
                  AppColors.warning.withOpacity(0.05),
                ]
              : [
                  AppColors.primary.withOpacity(0.1),
                  AppColors.primary.withOpacity(0.05),
                ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isOverdue
              ? AppColors.warning.withOpacity(0.3)
              : AppColors.primary.withOpacity(0.3),
          width: 2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isOverdue
                    ? Icons.schedule_rounded
                    : Icons.pending_actions_rounded,
                color: isOverdue ? AppColors.warning : AppColors.primary,
                size: 24,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Active Ticket',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.onSurface,
                      ),
                    ),
                    Text(
                      _displayIssueType(_activeTicketIssue!),
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: AppColors.onSurfaceSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Text(
                  'ID: ',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.onSurfaceSecondary,
                  ),
                ),
                Expanded(
                  child: Text(
                    displayTicketId,
                    style: GoogleFonts.robotoMono(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary,
                      letterSpacing: 1,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.content_copy, size: 16),
                  color: AppColors.primary,
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: _activeTicketId!));
                    _showSnack('Ticket ID copied!');
                  },
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          ),
          if (isOverdue) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(
                  Icons.info_outline,
                  size: 16,
                  color: AppColors.warning,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Taking longer than expected? Call support',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppColors.warning,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTicketForm() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildFormLabel('Issue Type', Icons.category_outlined),
          const SizedBox(height: 10),
          Container(
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.divider),
            ),
            child: DropdownButtonFormField<String>(
              value: _selectedIssueType,
              items: _issueTypes.map((e) {
                return DropdownMenuItem(
                  value: e,
                  child: Text(
                    e,
                    style: AppTextStyles.body2.copyWith(
                      color: AppColors.onSurface,
                    ),
                  ),
                );
              }).toList(),
              onChanged: (v) {
                if (v != null) setState(() => _selectedIssueType = v);
              },
              decoration: const InputDecoration(
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
              ),
              icon: const Icon(
                Icons.keyboard_arrow_down_rounded,
                color: AppColors.onSurfaceTertiary,
              ),
              dropdownColor: AppColors.background,
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          const SizedBox(height: 20),
          _buildFormLabel('Describe Your Issue', Icons.edit_note_rounded),
          const SizedBox(height: 10),
          Container(
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.divider),
            ),
            child: TextField(
              controller: _ticketMessageController,
              maxLines: 5,
              style: AppTextStyles.body2.copyWith(color: AppColors.onSurface),
              decoration: InputDecoration(
                hintText: 'Please provide details about your issue...',
                hintStyle: GoogleFonts.plusJakartaSans(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: AppColors.onSurfaceTertiary,
                ),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.all(16),
              ),
            ),
          ),
          const SizedBox(height: 24),
          _buildSubmitButton(),
        ],
      ),
    );
  }

  Widget _buildFormLabel(String label, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppColors.primary),
        const SizedBox(width: 8),
        Text(
          label,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: AppColors.onSurface,
          ),
        ),
      ],
    );
  }

  Widget _buildSubmitButton() {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.onPrimary,
          elevation: 0,
          shadowColor: AppColors.primary.withOpacity(0.3),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        onPressed: _submitting ? null : _submitTicket,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: _submitting
              ? Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: AppColors.onPrimary,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Submitting...',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.onPrimary,
                      ),
                    ),
                  ],
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.send_rounded, size: 20),
                    const SizedBox(width: 10),
                    Text(
                      'Submit Ticket',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.onPrimary,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  // ===========================================================================
  // HELPER WIDGETS
  // ===========================================================================

  Widget _buildSectionHeader({
    required String title,
    required String subtitle,
    required IconData icon,
  }) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppColors.primary.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, size: 20, color: AppColors.primary),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: AppTextStyles.heading3),
              const SizedBox(height: 2),
              Text(subtitle, style: AppTextStyles.caption),
            ],
          ),
        ),
      ],
    );
  }
}
