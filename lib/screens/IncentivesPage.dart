import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/api_service.dart';

class IncentivesPage extends StatefulWidget {
  final String? customerId;
  final String? driverId;

  const IncentivesPage({Key? key, this.customerId, this.driverId})
    : super(key: key);

  @override
  State<IncentivesPage> createState() => _IncentivesPageState();
}

class _IncentivesPageState extends State<IncentivesPage> {
  static const Color _background = Color(0xFFF5F2EA);
  static const Color _surface = Colors.white;
  static const Color _ink = Color(0xFF111827);
  static const Color _muted = Color(0xFF6B7280);
  static const Color _line = Color(0xFFE7DED2);
  static const Color _gold = Color(0xFFD97706);
  static const Color _goldDark = Color(0xFFB45309);
  static const Color _green = Color(0xFF16A34A);
  static const Color _blue = Color(0xFF2563EB);

  late List<_TimingSlot> _todaySlots = [];
  late List<_TimingSlot> _yesterdaySlots = [];

  bool _isLoading = true;
  String? _errorMessage;
  bool _todayIsActive = true;
  bool _yesterdayIsActive = true;

  bool get _activeDayIsEnabled =>
      _carouselIndex == 0 ? _todayIsActive : _yesterdayIsActive;

  bool _slotHasIncentiveData(_TimingSlot slot) {
    return slot.milestones.any((m) => m.ridesTarget > 0 && m.reward > 0);
  }

  bool _hasIncentiveData(List<_TimingSlot> slots) {
    return slots.any(_slotHasIncentiveData);
  }

  bool get _activeDayHasIncentives => _hasIncentiveData(_activeSlots);

  bool get _shouldShowIncentiveContent =>
      _activeDayIsEnabled && _activeDayHasIncentives;

  final PageController _pageController = PageController();
  int _carouselIndex = 0;

  // Default fallback slots
  static List<_TimingSlot> _getDefaultSlots(String dayType) {
    if (dayType == 'today') {
      return [
        const _TimingSlot(
          timeLabel: '06:00 AM - 11:59 AM',
          milestones: [
            _MilestoneTier(ridesTarget: 2, reward: 30),
            _MilestoneTier(ridesTarget: 5, reward: 30),
            _MilestoneTier(ridesTarget: 10, reward: 40),
          ],
        ),
        const _TimingSlot(
          timeLabel: '12:00 PM - 05:59 PM',
          milestones: [
            _MilestoneTier(ridesTarget: 2, reward: 30),
            _MilestoneTier(ridesTarget: 5, reward: 30),
            _MilestoneTier(ridesTarget: 10, reward: 40),
          ],
        ),
        const _TimingSlot(
          timeLabel: '06:00 PM - 11:59 PM',
          milestones: [
            _MilestoneTier(ridesTarget: 2, reward: 30),
            _MilestoneTier(ridesTarget: 5, reward: 30),
            _MilestoneTier(ridesTarget: 10, reward: 40),
          ],
        ),
      ];
    } else {
      return [
        const _TimingSlot(
          timeLabel: '06:00 AM - 11:59 AM',
          milestones: [
            _MilestoneTier(ridesTarget: 2, reward: 25),
            _MilestoneTier(ridesTarget: 5, reward: 30),
            _MilestoneTier(ridesTarget: 10, reward: 35),
          ],
        ),
        const _TimingSlot(
          timeLabel: '12:00 PM - 05:59 PM',
          milestones: [
            _MilestoneTier(ridesTarget: 2, reward: 20),
            _MilestoneTier(ridesTarget: 5, reward: 30),
            _MilestoneTier(ridesTarget: 10, reward: 40),
          ],
        ),
        const _TimingSlot(
          timeLabel: '06:00 PM - 11:59 PM',
          milestones: [
            _MilestoneTier(ridesTarget: 2, reward: 20),
            _MilestoneTier(ridesTarget: 5, reward: 20),
            _MilestoneTier(ridesTarget: 10, reward: 30),
          ],
        ),
      ];
    }
  }

  List<_TimingSlot> get _activeSlots =>
      _carouselIndex == 0 ? _todaySlots : _yesterdaySlots;

  String get _activeTitle => 'Daily';

  int get _activeTarget =>
      _activeSlots.fold<int>(0, (sum, slot) => sum + slot.maxRidesTarget);

  int get _activeReward =>
      _activeSlots.fold<int>(0, (sum, slot) => sum + slot.totalReward);

  @override
  void initState() {
    super.initState();
    _fetchIncentiveData();
  }

  Future<void> _fetchIncentiveData() async {
    try {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });

      final apiService = ApiService.instance;
      // Use UTC date to match backend/admin date storage (ISO date semantics).
      // This avoids day-shift issues where local time and server date differ.
      final nowUtc = DateTime.now().toUtc();
      final queryDate =
          '${nowUtc.year.toString().padLeft(4, '0')}-${nowUtc.month.toString().padLeft(2, '0')}-${nowUtc.day.toString().padLeft(2, '0')}';
      // Fetch timing slot incentives from backend
      final response = await apiService.getJson(
        '/api/driver/incentives/timing?date=$queryDate',
      );

      final responseData = jsonDecode(response.body);

      if (responseData['success'] == true && responseData['data'] != null) {
        final data = responseData['data'];

        // Parse today's incentives
        if (data['today'] != null) {
          final todaySlots = _parseTimingSlots(
            data['today']['timingSlots'] ?? [],
          );
          final todayHasIncentiveData = _hasIncentiveData(todaySlots);
          _todayIsActive =
              _readIsActiveFlag(data['today']) &&
              !_readIsDefaultFlag(data['today']) &&
              todayHasIncentiveData;
          _todaySlots = _todayIsActive ? todaySlots : <_TimingSlot>[];
        } else {
          _todaySlots = <_TimingSlot>[];
          _todayIsActive = false;
        }

        // Parse yesterday's incentives
        if (data['yesterday'] != null) {
          final yesterdaySlots = _parseTimingSlots(
            data['yesterday']['timingSlots'] ?? [],
          );
          final yesterdayHasIncentiveData = _hasIncentiveData(yesterdaySlots);
          _yesterdayIsActive =
              _readIsActiveFlag(data['yesterday']) &&
              !_readIsDefaultFlag(data['yesterday']) &&
              yesterdayHasIncentiveData;
          _yesterdaySlots = _yesterdayIsActive
              ? yesterdaySlots
              : <_TimingSlot>[];
        } else {
          _yesterdaySlots = <_TimingSlot>[];
          _yesterdayIsActive = false;
        }

        setState(() {
          _isLoading = false;
        });
      } else {
        throw Exception('Invalid response format');
      }
    } catch (e) {
      print('Error fetching incentive data: $e');
      setState(() {
        _isLoading = false;
        _errorMessage = 'Failed to load incentives: ${e.toString()}';
        // Keep incentives hidden on API failure to avoid stale/wrong payouts.
        _todaySlots = <_TimingSlot>[];
        _yesterdaySlots = <_TimingSlot>[];
        _todayIsActive = false;
        _yesterdayIsActive = false;
      });
    }
  }

  bool _readIsActiveFlag(dynamic dayData) {
    if (dayData is! Map) return false;
    final map = Map<String, dynamic>.from(dayData as Map);

    final dynamic isActive =
        map['isActive'] ??
        map['enabled'] ??
        map['active'] ??
        map['isEnabled'] ??
        map['toggle'];

    if (isActive is bool) return isActive;
    if (isActive is num) return isActive != 0;
    if (isActive is String) {
      final normalized = isActive.trim().toLowerCase();
      return normalized == 'true' || normalized == '1' || normalized == 'on';
    }

    return false;
  }

  bool _readIsDefaultFlag(dynamic dayData) {
    if (dayData is! Map) return false;
    final map = Map<String, dynamic>.from(dayData as Map);

    final dynamic isDefault = map['isDefault'] ?? map['default'] ?? false;

    if (isDefault is bool) return isDefault;
    if (isDefault is num) return isDefault != 0;
    if (isDefault is String) {
      final normalized = isDefault.trim().toLowerCase();
      return normalized == 'true' || normalized == '1' || normalized == 'yes';
    }

    return false;
  }

  /// Parse timing slots from JSON response
  List<_TimingSlot> _parseTimingSlots(List<dynamic> slotsJson) {
    return slotsJson.map((slotData) {
      final milestones = slotData['milestones'] ?? [];
      return _TimingSlot(
        timeLabel: slotData['timeLabel'] ?? 'Unknown Time',
        milestones: (milestones as List)
            .map(
              (m) => _MilestoneTier(
                ridesTarget: m['ridesTarget'] ?? 0,
                reward: m['reward'] ?? 0,
              ),
            )
            .toList(),
      );
    }).toList();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _background,
      body: SafeArea(
        child: _isLoading
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(height: 24),
                    const CircularProgressIndicator(color: _goldDark),
                    const SizedBox(height: 16),
                    Text(
                      'Loading incentives...',
                      style: GoogleFonts.plusJakartaSans(
                        color: _ink,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              )
            : CustomScrollView(
                slivers: [
                  if (_shouldShowIncentiveContent)
                    SliverToBoxAdapter(child: _buildHeader(context)),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (_errorMessage != null) ...[
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFEBEE),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: const Color(0xFFEF5350),
                                ),
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.warning_amber_rounded,
                                    color: Color(0xFFC62828),
                                    size: 18,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      _errorMessage!,
                                      style: GoogleFonts.plusJakartaSans(
                                        color: const Color(0xFFC62828),
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                  GestureDetector(
                                    onTap: _fetchIncentiveData,
                                    child: const Icon(
                                      Icons.refresh,
                                      color: Color(0xFFC62828),
                                      size: 18,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                          ],
                          _buildCarouselHeader(),
                          const SizedBox(height: 14),
                          if (!_shouldShowIncentiveContent)
                            _buildNoIncentivesMessage()
                          else
                            _buildIncentivePager(),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFFFFD86B), Color(0xFFF2B94B), Color(0xFFE58B1E)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
        child: Column(
          children: [
            Row(
              children: [
                _roundIconButton(
                  icon: Icons.arrow_back_ios_new_rounded,
                  onTap: () => Navigator.of(context).maybePop(),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Incentives',
                    textAlign: TextAlign.left,
                    style: GoogleFonts.plusJakartaSans(
                      color: _ink,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                _helpButton(),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              constraints: const BoxConstraints(maxWidth: 520),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF27272A),
                borderRadius: BorderRadius.circular(28),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x22000000),
                    blurRadius: 18,
                    offset: Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF1C2),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: const Icon(
                          Icons.emoji_events_rounded,
                          color: _goldDark,
                          size: 28,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Earn up to ₹$_activeReward',
                              style: GoogleFonts.plusJakartaSans(
                                color: Colors.white,
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'by completing $_activeTarget rides',
                              style: GoogleFonts.plusJakartaSans(
                                color: const Color(0xFFD1D5DB),
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: LinearProgressIndicator(
                      minHeight: 10,
                      value: 0.58,
                      backgroundColor: const Color(0xFF3F3F46),
                      valueColor: const AlwaysStoppedAnimation<Color>(_gold),
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

  Widget _buildCarouselHeader() {
    return Row(
      children: [
        Expanded(
          child: _carouselTab(
            label: 'Today',
            subtitle: 'Live incentive values',
            selected: _carouselIndex == 0,
            onTap: () => _jumpToPage(0),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _carouselTab(
            label: 'Yesterday',
            subtitle: 'Previous incentive values',
            selected: _carouselIndex == 1,
            onTap: () => _jumpToPage(1),
          ),
        ),
      ],
    );
  }

  Widget _carouselTab({
    required String label,
    required String subtitle,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected ? _surface : const Color(0xFFF9F5EF),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: selected ? _gold : _line,
            width: selected ? 1.4 : 1,
          ),
          boxShadow: selected
              ? const [
                  BoxShadow(
                    color: Color(0x1AB45309),
                    blurRadius: 18,
                    offset: Offset(0, 8),
                  ),
                ]
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: GoogleFonts.plusJakartaSans(
                color: selected ? _goldDark : _muted,
                fontSize: 14,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: GoogleFonts.plusJakartaSans(
                color: selected ? _ink : _muted,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIncentivePager() {
    final textScale = MediaQuery.of(context).textScaler.scale(1.0);
    final todayHeight = _estimateSlideHeight(_todaySlots, textScale);
    final yesterdayHeight = _estimateSlideHeight(_yesterdaySlots, textScale);
    final pagerHeight = todayHeight > yesterdayHeight
        ? todayHeight
        : yesterdayHeight;

    return Column(
      children: [
        SizedBox(
          height: pagerHeight,
          child: PageView(
            controller: _pageController,
            onPageChanged: (index) => setState(() => _carouselIndex = index),
            children: [
              _buildIncentiveSlide(
                dayTitle: 'Today',
                daySubtitle: 'Swipe for yesterday',
                slots: _todaySlots,
                amountColor: _goldDark,
                footer: 'Current incentive values',
              ),
              _buildIncentiveSlide(
                dayTitle: 'Yesterday',
                daySubtitle: 'Swipe back for today',
                slots: _yesterdaySlots,
                amountColor: _blue,
                footer: 'Past incentive values',
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(2, (index) {
            final selected = _carouselIndex == index;

            return AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              margin: const EdgeInsets.symmetric(horizontal: 4),
              width: selected ? 22 : 8,
              height: 8,
              decoration: BoxDecoration(
                color: selected ? _goldDark : const Color(0xFFD6C7B5),
                borderRadius: BorderRadius.circular(999),
              ),
            );
          }),
        ),
      ],
    );
  }

  double _estimateSlideHeight(List<_TimingSlot> slots, double textScale) {
    final maxMilestones = slots.fold<int>(
      0,
      (maxValue, slot) =>
          slot.milestones.length > maxValue ? slot.milestones.length : maxValue,
    );

    // Summary + reward + title/footer + per-slot cards + gaps.
    final base = 190.0 + 210.0 + 140.0;
    final perSlot = 120.0 + (maxMilestones * 62.0);
    final slotGaps = (slots.length - 1) * 14.0;
    final total = base + (slots.length * perSlot) + slotGaps;

    return (total * textScale).clamp(980.0, 2200.0);
  }

  Widget _buildIncentiveSlide({
    required String dayTitle,
    required String daySubtitle,
    required List<_TimingSlot> slots,
    required Color amountColor,
    required String footer,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Column(
        children: [
          _daySummaryCard(
            title: dayTitle,
            subtitle: daySubtitle,
            value:
                '₹${slots.fold<int>(0, (sum, slot) => sum + slot.totalReward)}',
            accent: amountColor,
            footer: footer,
          ),
          const SizedBox(height: 14),
          _buildRewardCard(slots),
          const SizedBox(height: 14),
          _buildMilestoneCard(slots),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _daySummaryCard({
    required String title,
    required String subtitle,
    required String value,
    required Color accent,
    required String footer,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _line),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A000000),
            blurRadius: 14,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            style: GoogleFonts.plusJakartaSans(
              color: _muted,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: GoogleFonts.plusJakartaSans(
              color: accent,
              fontSize: 22,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: GoogleFonts.plusJakartaSans(
              color: _ink,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _line),
            ),
            child: Text(
              footer,
              style: GoogleFonts.plusJakartaSans(
                color: _muted,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRewardCard(List<_TimingSlot> slots) {
    final targetRides = slots.fold<int>(
      0,
      (sum, slot) => sum + slot.maxRidesTarget,
    );
    final totalReward = slots.fold<int>(
      0,
      (sum, slot) => sum + slot.totalReward,
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _line),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0F000000),
            blurRadius: 16,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF1C2),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(
                  Icons.receipt_long_rounded,
                  color: _goldDark,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$_activeTitle incentive summary',
                      style: GoogleFonts.plusJakartaSans(
                        color: _ink,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Values will be populated from your backend admin panel later.',
                      style: GoogleFonts.plusJakartaSans(
                        color: _muted,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _metricTile(
                  label: 'Target rides',
                  value: '$targetRides',
                  accent: _blue,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _metricTile(
                  label: 'Total reward',
                  value: '₹$totalReward',
                  accent: _green,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _metricTile({
    required String label,
    required String value,
    required Color accent,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFAFAF9),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: GoogleFonts.plusJakartaSans(
              color: _muted,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: GoogleFonts.plusJakartaSans(
              color: accent,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMilestoneCard(List<_TimingSlot> slots) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _line),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0F000000),
            blurRadius: 16,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Milestones',
            style: GoogleFonts.plusJakartaSans(
              color: _ink,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Each milestone can later be connected to the admin backend.',
            style: GoogleFonts.plusJakartaSans(
              color: _muted,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 18),
          ...List.generate(slots.length, (index) {
            final slot = slots[index];
            final isLast = index == slots.length - 1;

            return Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 14),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: index == 0
                      ? const Color(0xFFFFFBF2)
                      : const Color(0xFFFAFAF9),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: index == 0 ? const Color(0xFFFFE4A3) : _line,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            slot.timeLabel,
                            style: GoogleFonts.plusJakartaSans(
                              color: _ink,
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        Text(
                          '₹${slot.totalReward}',
                          style: GoogleFonts.plusJakartaSans(
                            color: index == 0 ? _goldDark : _green,
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${slot.maxRidesTarget} rides total for this time block',
                      style: GoogleFonts.plusJakartaSans(
                        color: _muted,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 10),
                    ...List.generate(slot.milestones.length, (milestoneIndex) {
                      final tier = slot.milestones[milestoneIndex];
                      final tierIsLast =
                          milestoneIndex == slot.milestones.length - 1;

                      return Container(
                        margin: EdgeInsets.only(bottom: tierIsLast ? 0 : 8),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: _line),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${tier.ridesTarget} rides milestone',
                                style: GoogleFonts.plusJakartaSans(
                                  color: _ink,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            Text(
                              '₹${tier.reward}',
                              style: GoogleFonts.plusJakartaSans(
                                color: _goldDark,
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                ),
              ),
            );
          }),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: _line),
            ),
            child: Row(
              children: [
                const Icon(Icons.schedule_rounded, color: _goldDark, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Date, time, and per-ride values will be connected from backend admin later.',
                    style: GoogleFonts.plusJakartaSans(
                      color: _muted,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _jumpToPage(int index) {
    if (!mounted) return;

    setState(() => _carouselIndex = index);

    if (_pageController.hasClients) {
      _pageController.jumpToPage(index);
    }
  }

  Widget _buildNoIncentivesMessage() {
    final isTodayTab = _carouselIndex == 0;
    final dayLabel = isTodayTab ? 'today' : 'yesterday';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFEF3C7), Color(0xFFFCD34D)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(
            color: Color(0x15000000),
            blurRadius: 16,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.celebration_rounded, color: _goldDark, size: 56),
          const SizedBox(height: 20),
          Text(
            'Rest & Recharge! 🎉',
            style: GoogleFonts.plusJakartaSans(
              color: _ink,
              fontSize: 22,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'No special incentives for $dayLabel.',
            textAlign: TextAlign.center,
            style: GoogleFonts.plusJakartaSans(
              color: _ink,
              fontSize: 14,
              fontWeight: FontWeight.w600,
              height: 1.6,
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.7),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.arrow_forward_rounded, color: _goldDark, size: 18),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    isTodayTab
                        ? 'Check Yesterday tab for past incentives'
                        : 'Try Today tab for live incentives',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.plusJakartaSans(
                      color: _ink,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _roundIconButton({
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.white.withOpacity(0.25),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: 42,
          height: 42,
          alignment: Alignment.center,
          child: Icon(icon, color: _ink, size: 18),
        ),
      ),
    );
  }

  Widget _helpButton() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.92),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFF0E0C3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.support_agent_rounded, color: _ink, size: 18),
          const SizedBox(width: 6),
          Text(
            'Help',
            style: GoogleFonts.plusJakartaSans(
              color: _ink,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _TimingSlot {
  final String timeLabel;
  final List<_MilestoneTier> milestones;

  int get totalReward =>
      milestones.fold<int>(0, (sum, tier) => sum + tier.reward);

  int get maxRidesTarget =>
      milestones.isEmpty ? 0 : milestones.last.ridesTarget;

  const _TimingSlot({required this.timeLabel, required this.milestones});
}

class _MilestoneTier {
  final int ridesTarget;
  final int reward;

  const _MilestoneTier({required this.ridesTarget, required this.reward});
}
