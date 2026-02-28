import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:intl/intl.dart';
import 'package:drivergoo/config.dart';

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

class AppTextStyles {
  static TextStyle get heading1 => GoogleFonts.plusJakartaSans(
    fontSize: 32,
    fontWeight: FontWeight.w800,
    color: AppColors.onSurface,
    letterSpacing: -0.5,
  );

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

  static TextStyle get button => GoogleFonts.plusJakartaSans(
    fontSize: 16,
    fontWeight: FontWeight.w700,
    color: AppColors.onSurface,
  );
}

class DriverRideHistoryPage extends StatefulWidget {
  final String driverId;

  const DriverRideHistoryPage({Key? key, required this.driverId})
    : super(key: key);

  @override
  _DriverRideHistoryPageState createState() => _DriverRideHistoryPageState();
}

class _DriverRideHistoryPageState extends State<DriverRideHistoryPage> {
  // ✅ FIX: Use getter so it always reads the latest value from AppConfig
  String get apiBase => AppConfig.backendBaseUrl;

  List<Map<String, dynamic>> rideHistory = [];
  bool isLoading = true;
  String? errorMessage; // ✅ FIX: Track error state separately so UI shows it
  String selectedFilter = 'All';

  Map<String, dynamic>? summaryStats;

  @override
  void initState() {
    super.initState();
    // ✅ FIX: Ensure driverId is not empty before fetching
    if (widget.driverId.isEmpty) {
      setState(() {
        isLoading = false;
        errorMessage = 'Driver ID is missing. Please login again.';
      });
      return;
    }
    _fetchRideHistory();
  }

  Future<void> _fetchRideHistory() async {
    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    try {
      // ✅ FIX: Added includeUnpaid=true so rides where cash hasn't been
      // marked collected still show up. This is the #1 reason history was empty.
      final url =
          '$apiBase/api/driver/ride-history/${widget.driverId}?includeUnpaid=true';

      print('📊 Fetching ride history');
      print('   Driver ID: ${widget.driverId}');
      print('   URL: $url');

      final response = await http
          .get(Uri.parse(url), headers: {'Content-Type': 'application/json'})
          .timeout(
            const Duration(seconds: 15),
            onTimeout: () {
              throw TimeoutException('Request timed out');
            },
          );

      print('📡 Response status: ${response.statusCode}');
      print('📄 Response body: ${response.body}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (data['success'] == true) {
          // ✅ FIX: Safely cast each element — prevents "type cast" crashes
          final rawRides = data['rides'] as List<dynamic>? ?? [];
          final parsedRides = rawRides
              .map((r) => Map<String, dynamic>.from(r as Map))
              .toList();

          setState(() {
            rideHistory = parsedRides;
            summaryStats = data['summary'] != null
                ? Map<String, dynamic>.from(data['summary'])
                : null;
            isLoading = false;
          });

          print('✅ Fetched ${rideHistory.length} rides');

          if (mounted && rideHistory.isNotEmpty) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Loaded ${rideHistory.length} rides'),
                backgroundColor: AppColors.success,
                duration: const Duration(seconds: 2),
                behavior: SnackBarBehavior.floating,
              ),
            );
          } else if (mounted && rideHistory.isEmpty) {
            // ✅ FIX: Tell user explicitly when no rides exist instead of blank screen
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'No completed rides found yet. Rides will appear here once you complete trips.',
                ),
                duration: Duration(seconds: 4),
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        } else {
          throw Exception(data['message'] ?? 'Server returned success=false');
        }
      } else if (response.statusCode == 404) {
        // ✅ FIX: 404 could mean wrong driverId — give a useful message
        throw Exception(
          'Driver not found (ID: ${widget.driverId}). Check if this ID exists in the database.',
        );
      } else if (response.statusCode == 401 || response.statusCode == 403) {
        throw Exception('Authentication error. Please login again.');
      } else if (response.statusCode == 500) {
        // ✅ FIX: Print body on 500 to help debug server errors
        print('❌ Server 500 error body: ${response.body}');
        throw Exception(
          'Server error (500). Check your backend logs for details.',
        );
      } else {
        throw Exception(
          'Unexpected response: ${response.statusCode}\n${response.body}',
        );
      }
    } on SocketException catch (e) {
      print('❌ SocketException: $e');
      setState(() {
        isLoading = false;
        errorMessage = 'No internet connection. Check your network.';
      });
      if (mounted) _showErrorSnackBar('No internet connection');
    } on TimeoutException catch (e) {
      print('❌ Timeout: $e');
      setState(() {
        isLoading = false;
        errorMessage = 'Request timed out. Is your backend running?';
      });
      if (mounted)
        _showErrorSnackBar('Request timed out — is the server running?');
    } on FormatException catch (e) {
      // ✅ FIX: Catch JSON decode errors separately — often happens when
      // server returns HTML error page instead of JSON
      print('❌ JSON parse error: $e');
      setState(() {
        isLoading = false;
        errorMessage =
            'Invalid response from server (not JSON). Check backend URL.';
      });
      if (mounted)
        _showErrorSnackBar('Invalid server response — check your API URL');
    } catch (e) {
      print('❌ Error fetching ride history: $e');
      setState(() {
        isLoading = false;
        errorMessage = e.toString();
      });
      if (mounted) {
        _showErrorSnackBar('Failed to load rides: ${e.toString()}');
      }
    }
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 14,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: AppColors.error,
        duration: const Duration(seconds: 5),
        behavior: SnackBarBehavior.floating,
        action: SnackBarAction(
          label: 'RETRY',
          textColor: Colors.white,
          onPressed: _fetchRideHistory,
        ),
      ),
    );
  }

  List<Map<String, dynamic>> _getFilteredRides() {
    final now = DateTime.now();

    switch (selectedFilter) {
      case 'Today':
        return rideHistory.where((ride) {
          try {
            final completedAtStr = ride['completedAt'] ?? ride['createdAt'];
            if (completedAtStr == null) return false;
            final rideDate = DateTime.parse(completedAtStr).toLocal();
            return rideDate.year == now.year &&
                rideDate.month == now.month &&
                rideDate.day == now.day;
          } catch (e) {
            return false;
          }
        }).toList();

      case 'Week':
        final weekAgo = now.subtract(const Duration(days: 7));
        return rideHistory.where((ride) {
          try {
            final completedAtStr = ride['completedAt'] ?? ride['createdAt'];
            if (completedAtStr == null) return false;
            final rideDate = DateTime.parse(completedAtStr).toLocal();
            return rideDate.isAfter(weekAgo);
          } catch (e) {
            return false;
          }
        }).toList();

      case 'Month':
        return rideHistory.where((ride) {
          try {
            final completedAtStr = ride['completedAt'] ?? ride['createdAt'];
            if (completedAtStr == null) return false;
            final rideDate = DateTime.parse(completedAtStr).toLocal();
            return rideDate.year == now.year && rideDate.month == now.month;
          } catch (e) {
            return false;
          }
        }).toList();

      default:
        return rideHistory;
    }
  }

  Map<String, dynamic> _calculateFilteredStats(
    List<Map<String, dynamic>> rides,
  ) {
    double totalFares = 0;
    double totalCommission = 0;
    double totalEarnings = 0;

    for (var ride in rides) {
      // ✅ FIX: Use num cast before toDouble() to handle both int and double from JSON
      totalFares += (ride['fare'] as num? ?? 0).toDouble();
      totalCommission += (ride['commission'] as num? ?? 0).toDouble();
      totalEarnings += (ride['driverEarning'] as num? ?? 0).toDouble();
    }

    return {
      'totalRides': rides.length,
      'totalFares': totalFares,
      'totalCommission': totalCommission,
      'totalEarnings': totalEarnings,
    };
  }

  @override
  Widget build(BuildContext context) {
    final filteredRides = _getFilteredRides();
    final stats = _calculateFilteredStats(filteredRides);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 1,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.onSurface),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('Ride History', style: AppTextStyles.heading3),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: AppColors.primary),
            onPressed: _fetchRideHistory,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: isLoading
          ? const Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
              ),
            )
          // ✅ FIX: Show error state in body so user always sees what went wrong
          : errorMessage != null
          ? _buildErrorState()
          : RefreshIndicator(
              onRefresh: _fetchRideHistory,
              color: AppColors.primary,
              child: CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: _buildSummaryCard(stats),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: _buildFilterChips(),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        '${filteredRides.length} ${filteredRides.length == 1 ? 'Ride' : 'Rides'}',
                        style: AppTextStyles.body2,
                      ),
                    ),
                  ),
                  filteredRides.isEmpty
                      ? SliverToBoxAdapter(child: _buildEmptyState())
                      : SliverList(
                          delegate: SliverChildBuilderDelegate(
                            (context, index) =>
                                _buildRideCard(filteredRides[index]),
                            childCount: filteredRides.length,
                          ),
                        ),
                ],
              ),
            ),
    );
  }

  // ✅ NEW: Full-screen error widget so errors are visible — not just snackbars
  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.wifi_off, size: 64, color: AppColors.error),
            const SizedBox(height: 16),
            Text('Something went wrong', style: AppTextStyles.heading3),
            const SizedBox(height: 8),
            Text(
              errorMessage ?? 'Unknown error',
              style: AppTextStyles.body2,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _fetchRideHistory,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.onPrimary,
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryCard(Map<String, dynamic> stats) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.primary, AppColors.primary.withOpacity(0.8)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withOpacity(0.3),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.local_taxi,
                color: AppColors.onPrimary,
                size: 24,
              ),
              const SizedBox(width: 8),
              Text(
                '${stats['totalRides']} Completed Rides',
                style: AppTextStyles.heading3.copyWith(
                  color: AppColors.onPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: _buildStatItem(
                  'Total Fares',
                  '₹${(stats['totalFares'] as double).toStringAsFixed(2)}',
                  Icons.payments,
                ),
              ),
              Container(
                width: 1,
                height: 60,
                color: AppColors.onPrimary.withOpacity(0.3),
              ),
              Expanded(
                child: _buildStatItem(
                  'Commission',
                  '₹${(stats['totalCommission'] as double).toStringAsFixed(2)}',
                  Icons.percent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(height: 1, color: AppColors.onPrimary.withOpacity(0.3)),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.account_balance_wallet,
                color: AppColors.onPrimary,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                'Net Earnings: ',
                style: AppTextStyles.body1.copyWith(
                  color: AppColors.onPrimary.withOpacity(0.9),
                ),
              ),
              Text(
                '₹${(stats['totalEarnings'] as double).toStringAsFixed(2)}',
                style: AppTextStyles.heading2.copyWith(
                  color: AppColors.onPrimary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, String value, IconData icon) {
    return Column(
      children: [
        Icon(icon, color: AppColors.onPrimary.withOpacity(0.9), size: 20),
        const SizedBox(height: 8),
        Text(
          label,
          style: AppTextStyles.caption.copyWith(
            color: AppColors.onPrimary.withOpacity(0.9),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: AppTextStyles.body1.copyWith(
            color: AppColors.onPrimary,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildFilterChips() {
    final filters = ['All', 'Today', 'Week', 'Month'];

    return SizedBox(
      height: 50,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: filters.length,
        itemBuilder: (context, index) {
          final filter = filters[index];
          final isSelected = selectedFilter == filter;

          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(filter),
              selected: isSelected,
              onSelected: (_) => setState(() => selectedFilter = filter),
              backgroundColor: AppColors.surface,
              selectedColor: AppColors.primary,
              labelStyle: AppTextStyles.body2.copyWith(
                color: isSelected ? AppColors.onPrimary : AppColors.onSurface,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            ),
          );
        },
      ),
    );
  }

  Widget _buildRideCard(Map<String, dynamic> ride) {
    // ✅ FIX: Use num cast to handle both int and double values from JSON
    final fare = (ride['fare'] as num? ?? 0).toDouble();
    final commission = (ride['commission'] as num? ?? 0).toDouble();
    final driverEarning = (ride['driverEarning'] as num? ?? 0).toDouble();
    final commissionPercent = (ride['commissionPercentage'] as num? ?? 15)
        .toInt();

    DateTime dateTime;
    try {
      final completedAtStr = ride['completedAt'] ?? ride['createdAt'];
      dateTime = completedAtStr != null
          ? DateTime.parse(completedAtStr).toLocal()
          : DateTime.now();
    } catch (e) {
      dateTime = DateTime.now();
    }

    final formattedDate = DateFormat('MMM dd, yyyy').format(dateTime);
    final formattedTime = DateFormat('hh:mm a').format(dateTime);

    // ✅ FIX: Safely read nested address — handle both String and Map structures
    final pickupAddress = _extractAddress(ride['pickup']);
    final dropAddress = _extractAddress(ride['drop']);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _showRideDetails(ride),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Date & Time header
              Row(
                children: [
                  const Icon(
                    Icons.calendar_today,
                    size: 14,
                    color: AppColors.onSurfaceSecondary,
                  ),
                  const SizedBox(width: 6),
                  Text(formattedDate, style: AppTextStyles.body2),
                  const SizedBox(width: 16),
                  const Icon(
                    Icons.access_time,
                    size: 14,
                    color: AppColors.onSurfaceSecondary,
                  ),
                  const SizedBox(width: 6),
                  Text(formattedTime, style: AppTextStyles.caption),
                ],
              ),
              const SizedBox(height: 16),

              // Route
              Row(
                children: [
                  Column(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: const BoxDecoration(
                          color: AppColors.success,
                          shape: BoxShape.circle,
                        ),
                      ),
                      Container(width: 2, height: 30, color: AppColors.divider),
                      Container(
                        width: 10,
                        height: 10,
                        decoration: const BoxDecoration(
                          color: AppColors.error,
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
                        Text(
                          pickupAddress,
                          style: AppTextStyles.body2,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 24),
                        Text(
                          dropAddress,
                          style: AppTextStyles.body2,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Divider(color: AppColors.divider),
              const SizedBox(height: 12),

              // Fare breakdown
              Column(
                children: [
                  _buildFareRow('Trip Fare', fare, isBold: true),
                  const SizedBox(height: 8),
                  _buildFareRow(
                    'Commission ($commissionPercent%)',
                    commission,
                    isNegative: true,
                    color: AppColors.warning,
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      vertical: 8,
                      horizontal: 12,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.success.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: AppColors.success.withOpacity(0.3),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.account_balance_wallet,
                              size: 16,
                              color: AppColors.success,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Your Earning',
                              style: AppTextStyles.body1.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        Text(
                          '₹${driverEarning.toStringAsFixed(2)}',
                          style: AppTextStyles.heading3.copyWith(
                            color: AppColors.success,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ✅ FIX: Helper to safely extract address from either a Map or plain String
  String _extractAddress(dynamic locationField) {
    if (locationField == null) return 'N/A';
    if (locationField is String) return locationField;
    if (locationField is Map) {
      return locationField['address']?.toString() ??
          locationField['name']?.toString() ??
          'N/A';
    }
    return 'N/A';
  }

  Widget _buildFareRow(
    String label,
    double amount, {
    bool isBold = false,
    bool isNegative = false,
    Color? color,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: isBold ? AppTextStyles.body1 : AppTextStyles.body2),
        Text(
          '${isNegative ? '-' : ''}₹${amount.toStringAsFixed(2)}',
          style: (isBold ? AppTextStyles.body1 : AppTextStyles.body2).copyWith(
            color: color,
            fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.history,
              size: 80,
              color: AppColors.onSurfaceTertiary,
            ),
            const SizedBox(height: 16),
            Text('No rides found', style: AppTextStyles.heading3),
            const SizedBox(height: 8),
            Text(
              selectedFilter == 'All'
                  ? 'Complete a ride and it will appear here'
                  : 'No rides found for "$selectedFilter" filter.\nTry selecting "All" to see everything.',
              style: AppTextStyles.body2,
              textAlign: TextAlign.center,
            ),
            if (selectedFilter != 'All') ...[
              const SizedBox(height: 16),
              TextButton(
                onPressed: () => setState(() => selectedFilter = 'All'),
                child: const Text(
                  'Show All Rides',
                  style: TextStyle(color: AppColors.primary),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _showRideDetails(Map<String, dynamic> ride) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _buildRideDetailsSheet(ride),
    );
  }

  Widget _buildRideDetailsSheet(Map<String, dynamic> ride) {
    final fare = (ride['fare'] as num? ?? 0).toDouble();
    final commission = (ride['commission'] as num? ?? 0).toDouble();
    final driverEarning = (ride['driverEarning'] as num? ?? 0).toDouble();
    final commissionPercent = (ride['commissionPercentage'] as num? ?? 15)
        .toInt();

    DateTime dateTime;
    try {
      final completedAtStr = ride['completedAt'] ?? ride['createdAt'];
      dateTime = completedAtStr != null
          ? DateTime.parse(completedAtStr).toLocal()
          : DateTime.now();
    } catch (e) {
      dateTime = DateTime.now();
    }

    final formattedDateTime = DateFormat(
      'MMM dd, yyyy • hh:mm a',
    ).format(dateTime);

    final pickupAddress = _extractAddress(ride['pickup']);
    final dropAddress = _extractAddress(ride['drop']);

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.85,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.all(24),
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.divider,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  const Icon(Icons.receipt_long, color: AppColors.primary),
                  const SizedBox(width: 12),
                  Text('Ride Details', style: AppTextStyles.heading2),
                ],
              ),
              const SizedBox(height: 8),
              Text(formattedDateTime, style: AppTextStyles.body2),
              const SizedBox(height: 24),

              // Route
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    _buildDetailRow(Icons.location_on, 'Pickup', pickupAddress),
                    const SizedBox(height: 16),
                    _buildDetailRow(Icons.flag, 'Drop', dropAddress),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Fare breakdown
              Text('Fare Breakdown', style: AppTextStyles.heading3),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.divider),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    _buildFareRow('Base Fare', fare, isBold: true),
                    const SizedBox(height: 12),
                    _buildFareRow(
                      'Platform Commission ($commissionPercent%)',
                      commission,
                      isNegative: true,
                      color: AppColors.warning,
                    ),
                    const SizedBox(height: 12),
                    Divider(color: AppColors.divider),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Your Earning', style: AppTextStyles.heading3),
                        Text(
                          '₹${driverEarning.toStringAsFixed(2)}',
                          style: AppTextStyles.heading2.copyWith(
                            color: AppColors.success,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDetailRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: AppColors.onSurfaceSecondary),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: AppTextStyles.caption),
              const SizedBox(height: 4),
              Text(value, style: AppTextStyles.body1),
            ],
          ),
        ),
      ],
    );
  }
}
