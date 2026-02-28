//documents_review_page.dart
import 'dart:convert';
import 'dart:async';
import 'package:drivergoo/screens/driver_dashboard_page.dart';
import 'package:drivergoo/screens/driver_details_page.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../config.dart'; // ✅ Import AppConfig for production URLs

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

class DocumentsReviewPage extends StatefulWidget {
  final String? driverId;

  const DocumentsReviewPage({super.key, this.driverId});

  @override
  State<DocumentsReviewPage> createState() => _DocumentsReviewPageState();
}

class _DocumentsReviewPageState extends State<DocumentsReviewPage> {
  bool isLoading = true;
  bool allDocsApproved = false;
  bool allDocsUploaded = false;
  List<Map<String, dynamic>> uploadedDocuments = [];
  List<String> missingDocuments = [];
  String? errorMessage;
  String? vehicleType;
  // 🔐 Backend URL - uses AppConfig for production environment configuration
  // No hardcoded development URLs to prevent Play Store rejection
  late final String backendUrl = AppConfig.backendBaseUrl;
  Timer? _autoRefreshTimer;

  // 👇 ADD SUPPORT PHONE NUMBER HERE - Change this to your actual support number
  static const String _supportPhoneNumber = '+911234567890';

  @override
  void dispose() {
    _stopAutoRefresh();
    super.dispose();
  }

  final Map<String, List<String>> requiredDocsByVehicle = {
    'bike': ['profile', 'license', 'rc', 'pan', 'aadhaar'],
    'auto': [
      'profile',
      'license',
      'rc',
      'pan',
      'aadhaar',
      'fitnesscertificate',
    ],
    'car': [
      'profile',
      'license',
      'rc',
      'pan',
      'aadhaar',
      'fitnesscertificate',
      'permit',
      'insurance',
    ],
  };

  final Map<String, String> docDisplayNames = {
    'profile': 'Profile Photo',
    'license': 'Driving License',
    'aadhaar': 'Aadhaar Card',
    'pan': 'PAN Card',
    'rc': 'Vehicle RC',
    'permit': 'Permit',
    'insurance': 'Insurance',
    'fitnesscertificate': 'Fitness Certificate',
  };

  // 👇 METHOD FOR CALL SUPPORT
  Future<void> _launchSupportCall() async {
    final Uri phoneUri = Uri(scheme: 'tel', path: _supportPhoneNumber);

    try {
      if (await canLaunchUrl(phoneUri)) {
        await launchUrl(phoneUri);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  Icon(Icons.error_outline, color: Colors.white),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Could not launch phone dialer. Please call $_supportPhoneNumber',
                    ),
                  ),
                ],
              ),
              backgroundColor: AppColors.error,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              duration: Duration(seconds: 4),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Error launching phone call: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  // 👇 METHOD FOR SHOWING CALL CONFIRMATION DIALOG
  void _showCallSupportDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.support_agent, color: AppColors.primary),
            ),
            SizedBox(width: 12),
            Text("Call Support", style: AppTextStyles.heading3),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Need help with your documents?", style: AppTextStyles.body1),
            SizedBox(height: 8),
            Text(
              "Our support team is available 24/7 to assist you.",
              style: AppTextStyles.body2,
            ),
            SizedBox(height: 16),
            Container(
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.phone, color: AppColors.primary, size: 20),
                  SizedBox(width: 8),
                  Text(
                    _supportPhoneNumber,
                    style: AppTextStyles.body1.copyWith(
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              "Cancel",
              style: AppTextStyles.button.copyWith(
                color: AppColors.onSurfaceSecondary,
              ),
            ),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(context);
              _launchSupportCall();
            },
            icon: Icon(Icons.call, size: 18),
            label: Text(
              "Call Now",
              style: AppTextStyles.button.copyWith(color: AppColors.onPrimary),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.success,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<String?> getToken() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        return await user.getIdToken(true);
      }
      return null;
    } catch (e) {
      debugPrint("❌ Error getting token: $e");
      return null;
    }
  }

  DateTime _extractDocTime(Map<String, dynamic> d) {
    final updated = d['updatedAt']?.toString();
    final created = d['createdAt']?.toString();
    return DateTime.tryParse(updated ?? created ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0);
  }

  Map<String, int> _computeDocumentSummary(
    Map<String, List<Map<String, dynamic>>> groupedDocs,
  ) {
    int uploaded = groupedDocs.length;
    int verified = 0;
    int pending = 0;

    groupedDocs.forEach((docType, docsForType) {
      final sortedDocsForType = List<Map<String, dynamic>>.from(docsForType);

      sortedDocsForType.sort(
        (a, b) => _extractDocTime(a).compareTo(_extractDocTime(b)),
      );

      final Map<String, Map<String, dynamic>> latestBySide = {};
      for (var d in sortedDocsForType) {
        final side = (d['side'] ?? 'front').toString().toLowerCase();
        latestBySide[side] = d;
      }

      final latestDocs = latestBySide.values.toList();
      if (latestDocs.isEmpty) return;

      final bool allApproved = latestDocs.every((doc) {
        final status = doc['status']?.toString().toLowerCase() ?? '';
        return status == 'approved' || status == 'verified';
      });

      if (allApproved) {
        verified++;
      } else {
        pending++;
      }
    });

    return {'uploaded': uploaded, 'verified': verified, 'pending': pending};
  }

  @override
  void initState() {
    super.initState();
    _loadVehicleTypeAndFetchDocuments();
  }

  Future<void> _loadVehicleTypeAndFetchDocuments() async {
    final prefs = await SharedPreferences.getInstance();
    vehicleType = prefs.getString('vehicleType')?.toLowerCase();
    print("📋 Local Vehicle Type (prefs): $vehicleType");
    _fetchDriverDocuments();
  }

  Future<void> _fetchDriverDocuments() async {
    final driverIdLocal =
        widget.driverId ?? FirebaseAuth.instance.currentUser?.uid;

    if (driverIdLocal == null) {
      setState(() {
        isLoading = false;
        errorMessage = "Driver ID is missing. Please sign-in again.";
      });
      return;
    }

    try {
      setState(() {
        isLoading = true;
        errorMessage = null;
      });

      final token = await getToken();
      if (token == null) {
        setState(() {
          isLoading = false;
          errorMessage = "Authentication failed. Please login again.";
        });
        return;
      }

      debugPrint("🔍 Fetching documents for driver: $driverIdLocal");

      final uri = Uri.parse('$backendUrl/api/driver/documents/$driverIdLocal');

      final response = await http
          .get(
            uri,
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
          )
          .timeout(const Duration(seconds: 12));

      debugPrint("📊 Documents API Response: ${response.statusCode}");

      if (response.statusCode == 200) {
        final dataRaw = json.decode(response.body);

        if (dataRaw is Map<String, dynamic>) {
          final data = dataRaw;

          final backendVehicleType = data['vehicleType']
              ?.toString()
              .toLowerCase();
          if (backendVehicleType != null && backendVehicleType.isNotEmpty) {
            vehicleType = backendVehicleType;
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString('vehicleType', vehicleType!);
          }

          if (data.containsKey('message') &&
              data['message'].toString().toLowerCase().contains(
                'no documents',
              )) {
            _handleNoDocuments();
            return;
          }

          final docsRaw = data['docs'];
          if (docsRaw is! List) {
            _handleNoDocuments();
            return;
          }

          final docs = <Map<String, dynamic>>[];
          for (var item in docsRaw) {
            if (item is Map) {
              docs.add(Map<String, dynamic>.from(item));
            }
          }

          if (docs.isEmpty) {
            _handleNoDocuments();
            return;
          }

          _analyzeDocuments(docs);
          return;
        } else {
          setState(() {
            isLoading = false;
            errorMessage = "Unexpected response from server.";
          });
          return;
        }
      } else if (response.statusCode == 404) {
        _handleNoDocuments();
        return;
      } else {
        try {
          final errorData = json.decode(response.body);
          if (errorData is Map && errorData.containsKey('message')) {
            setState(() {
              isLoading = false;
              errorMessage =
                  errorData['message']?.toString() ??
                  "Failed to fetch documents";
            });
          } else {
            setState(() {
              isLoading = false;
              errorMessage =
                  "Failed to fetch documents (${response.statusCode})";
            });
          }
        } catch (_) {
          setState(() {
            isLoading = false;
            errorMessage = "Failed to fetch documents (${response.statusCode})";
          });
        }
        return;
      }
    } on TimeoutException catch (e) {
      debugPrint("❌ Timeout fetching documents: $e");
      setState(() {
        isLoading = false;
        errorMessage =
            "Connection timed out. Please check your internet and try again.";
      });
    } catch (e) {
      debugPrint("❌ Error fetching documents: $e");
      setState(() {
        isLoading = false;
        errorMessage = "Connection error: $e";
      });
    }
  }

  void _handleNoDocuments() {
    final required = requiredDocsByVehicle[vehicleType] ?? [];
    setState(() {
      uploadedDocuments = [];
      missingDocuments = required;
      allDocsUploaded = false;
      allDocsApproved = false;
      isLoading = false;
      errorMessage = null;
    });
    _startAutoRefresh();
  }

  void _analyzeDocuments(List<Map<String, dynamic>> docs) {
    debugPrint("\n" + "=" * 70);
    debugPrint("📋 ANALYZING DOCUMENTS");
    debugPrint("=" * 70);

    final requiredDocs = requiredDocsByVehicle[vehicleType] ?? [];
    debugPrint("   Required: $requiredDocs");

    final uploadedDocTypes = <String>{};
    for (var doc in docs) {
      final docType = doc['docType']?.toString().toLowerCase();
      if (docType != null && docType.isNotEmpty) {
        uploadedDocTypes.add(docType);
      }
    }

    debugPrint("   Uploaded: $uploadedDocTypes");

    final missing = requiredDocs
        .where((docType) => !uploadedDocTypes.contains(docType))
        .toList();

    debugPrint("   Missing: $missing");

    final allApproved =
        docs.isNotEmpty &&
        docs.every((doc) {
          final status = doc['status']?.toString().toLowerCase() ?? '';
          return status == 'approved' || status == 'verified';
        });

    debugPrint("   All Approved: $allApproved");
    debugPrint("=" * 70 + "\n");

    setState(() {
      uploadedDocuments = docs;
      missingDocuments = missing;
      allDocsUploaded = missing.isEmpty;
      allDocsApproved = allApproved && allDocsUploaded;
      isLoading = false;
      errorMessage = null;
    });

    if (allDocsApproved) {
      _stopAutoRefresh();
    } else {
      _startAutoRefresh();
    }
  }

  void _retryFetch() {
    setState(() {
      isLoading = true;
      errorMessage = null;
    });
    _fetchDriverDocuments();
  }

  void _goToDocumentUpload() async {
    final uploadedDocTypes = <String>{};
    for (var doc in uploadedDocuments) {
      final docType = doc['docType']?.toString().toLowerCase();
      if (docType != null && docType.isNotEmpty) {
        uploadedDocTypes.add(docType);
      }
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('uploadedDocTypes', uploadedDocTypes.toList());

    if (!mounted) return;

    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => DriverDocumentUploadPage(
          driverId:
              widget.driverId ?? FirebaseAuth.instance.currentUser?.uid ?? '',
          uploadedDocTypes: uploadedDocTypes.toList(),
        ),
      ),
    );

    if (result == true && mounted) {
      _fetchDriverDocuments();
    }
  }

  Map<String, List<Map<String, dynamic>>> _groupDocumentsByType() {
    final grouped = <String, List<Map<String, dynamic>>>{};

    for (var doc in uploadedDocuments) {
      final docType = doc['docType']?.toString().toLowerCase() ?? 'unknown';
      if (!grouped.containsKey(docType)) {
        grouped[docType] = [];
      }
      grouped[docType]!.add(doc);
    }

    return grouped;
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case "approved":
      case "verified":
        return AppColors.success;
      case "rejected":
        return AppColors.error;
      default:
        return AppColors.warning;
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status.toLowerCase()) {
      case "approved":
      case "verified":
        return Icons.check_circle_rounded;
      case "rejected":
        return Icons.cancel_rounded;
      default:
        return Icons.schedule_rounded;
    }
  }

  IconData _getVehicleIcon() {
    final type = (vehicleType ?? '').toLowerCase();

    if (type == 'bike') {
      return Icons.two_wheeler;
    } else if (type == 'auto') {
      return Icons.electric_rickshaw;
    } else if (type == 'car') {
      return Icons.directions_car;
    } else {
      return Icons.directions_car;
    }
  }

  String _getStatusText(String status) {
    switch (status.toLowerCase()) {
      case "approved":
      case "verified":
        return "Verified";
      case "rejected":
        return "Rejected";
      default:
        return "Under Review";
    }
  }

  void _startAutoRefresh() {
    _autoRefreshTimer?.cancel();

    _autoRefreshTimer = Timer.periodic(const Duration(seconds: 30), (
      timer,
    ) async {
      if (!mounted) {
        timer.cancel();
        return;
      }

      if (allDocsApproved) {
        timer.cancel();
        return;
      }

      if (!isLoading) {
        await _fetchDriverDocuments();
      }
    });
  }

  void _stopAutoRefresh() {
    _autoRefreshTimer?.cancel();
    _autoRefreshTimer = null;
  }

  Future<bool> _onWillPop() async {
    return Future.value(allDocsApproved);
  }

  @override
  Widget build(BuildContext context) {
    final groupedDocs = _groupDocumentsByType();
    final summaryCounts = _computeDocumentSummary(groupedDocs);

    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          automaticallyImplyLeading: false,

          // ❌ REMOVED - leading property (was on left side)
          // leading: Container(...)
          title: Text(
            "Document Verification",
            style: AppTextStyles.heading3.copyWith(color: AppColors.onPrimary),
          ),
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.onPrimary,
          elevation: 0,

          // ✅ ADDED - Call Support Icon on RIGHT SIDE using actions
          actions: [
            Container(
              margin: const EdgeInsets.only(right: 8),
              child: IconButton(
                icon: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: AppColors.onPrimary.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.support_agent, size: 22),
                ),
                color: AppColors.onPrimary,
                tooltip: 'Call Support',
                onPressed: _showCallSupportDialog,
              ),
            ),
          ],
        ),
        body: SafeArea(
          child: isLoading
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircularProgressIndicator(
                        color: AppColors.primary,
                        strokeWidth: 3,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        "Loading your documents...",
                        style: AppTextStyles.body1,
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  color: AppColors.primary,
                  onRefresh: () async {
                    await _fetchDriverDocuments();
                  },
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Show error message card if present
                        if (errorMessage != null) ...[
                          Container(
                            padding: const EdgeInsets.all(12),
                            margin: const EdgeInsets.only(bottom: 12),
                            decoration: BoxDecoration(
                              color: AppColors.error.withOpacity(0.08),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: AppColors.error.withOpacity(0.16),
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.error_outline,
                                  color: AppColors.error,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    errorMessage!,
                                    style: AppTextStyles.body2.copyWith(
                                      color: AppColors.error,
                                    ),
                                  ),
                                ),
                                TextButton(
                                  onPressed: _retryFetch,
                                  child: Text(
                                    'Retry',
                                    style: AppTextStyles.body2.copyWith(
                                      color: AppColors.primary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],

                        // Header
                        Center(
                          child: Column(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(20),
                                decoration: BoxDecoration(
                                  color: AppColors.primary.withOpacity(0.1),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  Icons.verified_user_rounded,
                                  size: 60,
                                  color: AppColors.primary,
                                ),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                "Document Verification",
                                style: AppTextStyles.heading2,
                              ),
                              const SizedBox(height: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.primary.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      _getVehicleIcon(),
                                      size: 16,
                                      color: AppColors.primary,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      vehicleType?.toUpperCase() ?? 'UNKNOWN',
                                      style: AppTextStyles.body1.copyWith(
                                        color: AppColors.primary,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 32),

                        // Progress Summary Card
                        Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: allDocsApproved
                                  ? [
                                      AppColors.success,
                                      AppColors.success.withOpacity(0.8),
                                    ]
                                  : allDocsUploaded
                                  ? [
                                      AppColors.warning,
                                      AppColors.warning.withOpacity(0.8),
                                    ]
                                  : [
                                      AppColors.error.withOpacity(0.7),
                                      AppColors.error.withOpacity(0.5),
                                    ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(
                                color:
                                    (allDocsApproved
                                            ? AppColors.success
                                            : allDocsUploaded
                                            ? AppColors.warning
                                            : AppColors.error)
                                        .withOpacity(0.3),
                                blurRadius: 16,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: Column(
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    allDocsApproved
                                        ? Icons.verified_rounded
                                        : allDocsUploaded
                                        ? Icons.pending_actions_rounded
                                        : Icons.warning_amber_rounded,
                                    color: AppColors.onPrimary,
                                    size: 48,
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          "Status",
                                          style: AppTextStyles.caption.copyWith(
                                            color: AppColors.onPrimary
                                                .withOpacity(0.9),
                                            fontSize: 13,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          allDocsApproved
                                              ? "All Verified ✓"
                                              : allDocsUploaded
                                              ? "Under Review"
                                              : "Action Required",
                                          style: AppTextStyles.heading3
                                              .copyWith(
                                                color: AppColors.onPrimary,
                                                fontSize: 22,
                                              ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 20),
                              Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceAround,
                                  children: [
                                    _buildStatusMetric(
                                      "Uploaded",
                                      "${summaryCounts['uploaded']}",
                                      Icons.cloud_done_rounded,
                                    ),
                                    Container(
                                      width: 1,
                                      height: 40,
                                      color: Colors.white.withOpacity(0.3),
                                    ),
                                    _buildStatusMetric(
                                      "Pending",
                                      "${summaryCounts['pending']}",
                                      Icons.pending_outlined,
                                    ),
                                    Container(
                                      width: 1,
                                      height: 40,
                                      color: Colors.white.withOpacity(0.3),
                                    ),
                                    _buildStatusMetric(
                                      "Verified",
                                      "${summaryCounts['verified']}",
                                      Icons.verified_rounded,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 32),

                        // Missing Documents Alert
                        if (missingDocuments.isNotEmpty) ...[
                          Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: AppColors.error.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: AppColors.error.withOpacity(0.3),
                                width: 2,
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      Icons.info_outline_rounded,
                                      color: AppColors.error,
                                      size: 28,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        "Missing ${missingDocuments.length} Document${missingDocuments.length > 1 ? 's' : ''}",
                                        style: AppTextStyles.heading3.copyWith(
                                          color: AppColors.error,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                ...missingDocuments.map((docType) {
                                  return Container(
                                    margin: const EdgeInsets.only(bottom: 8),
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: AppColors.error.withOpacity(0.2),
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.description_outlined,
                                          size: 20,
                                          color: AppColors.error,
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Text(
                                            docDisplayNames[docType] ?? docType,
                                            style: AppTextStyles.body1.copyWith(
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                        Icon(
                                          Icons.arrow_forward_ios_rounded,
                                          size: 16,
                                          color: AppColors.onSurfaceTertiary,
                                        ),
                                      ],
                                    ),
                                  );
                                }).toList(),
                                const SizedBox(height: 16),
                                SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton.icon(
                                    onPressed: _goToDocumentUpload,
                                    icon: const Icon(Icons.upload_file_rounded),
                                    label: Text(
                                      "Upload Documents",
                                      style: AppTextStyles.button.copyWith(
                                        color: AppColors.onPrimary,
                                      ),
                                    ),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppColors.error,
                                      foregroundColor: AppColors.onPrimary,
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 16,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      elevation: 2,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 24),
                        ],

                        // Uploaded Documents Section
                        if (groupedDocs.isNotEmpty) ...[
                          Text("Your Documents", style: AppTextStyles.heading3),
                          const SizedBox(height: 16),
                          ListView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: groupedDocs.length,
                            itemBuilder: (context, index) {
                              final docType = groupedDocs.keys.elementAt(index);

                              final allDocsForType =
                                  List<Map<String, dynamic>>.from(
                                    groupedDocs[docType]!,
                                  );

                              allDocsForType.sort(
                                (a, b) => _extractDocTime(
                                  a,
                                ).compareTo(_extractDocTime(b)),
                              );

                              final Map<String, Map<String, dynamic>>
                              latestBySide = {};
                              for (var d in allDocsForType) {
                                final side = (d['side'] ?? 'front')
                                    .toString()
                                    .toLowerCase();
                                latestBySide[side] = d;
                              }

                              final docs = latestBySide.values.toList();

                              String overallStatus = 'approved';
                              for (var d in docs) {
                                final status =
                                    d['status']?.toString().toLowerCase() ??
                                    'pending';
                                if (status == 'rejected') {
                                  overallStatus = 'rejected';
                                  break;
                                } else if (status == 'pending' &&
                                    overallStatus != 'rejected') {
                                  overallStatus = 'pending';
                                }
                              }

                              final rejectedDocs = docs.where((d) {
                                final s =
                                    d['status']?.toString().toLowerCase() ??
                                    'pending';
                                return s == 'rejected';
                              }).toList();

                              final bool hasRejected = rejectedDocs.isNotEmpty;

                              final String combinedRemarks = rejectedDocs
                                  .map(
                                    (d) =>
                                        d['remarks']?.toString().trim() ?? '',
                                  )
                                  .where((r) => r.isNotEmpty)
                                  .toSet()
                                  .join('\n');

                              final String preselectSide = hasRejected
                                  ? (rejectedDocs.first['side']
                                            ?.toString()
                                            .toLowerCase() ??
                                        'front')
                                  : (docs.first['side']
                                            ?.toString()
                                            .toLowerCase() ??
                                        'front');

                              return Container(
                                margin: const EdgeInsets.only(bottom: 12),
                                decoration: BoxDecoration(
                                  color: AppColors.background,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: _getStatusColor(
                                      overallStatus,
                                    ).withOpacity(0.2),
                                    width: 1.5,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: AppColors.onSurface.withOpacity(
                                        0.04,
                                      ),
                                      blurRadius: 10,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: ExpansionTile(
                                  tilePadding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 8,
                                  ),
                                  collapsedIconColor: _getStatusColor(
                                    overallStatus,
                                  ),
                                  iconColor: _getStatusColor(overallStatus),
                                  leading: Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: _getStatusColor(
                                        overallStatus,
                                      ).withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Icon(
                                      Icons.description_rounded,
                                      color: _getStatusColor(overallStatus),
                                      size: 28,
                                    ),
                                  ),
                                  title: Text(
                                    docDisplayNames[docType.toLowerCase()] ??
                                        docType.toUpperCase(),
                                    style: AppTextStyles.body1.copyWith(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  subtitle: Padding(
                                    padding: const EdgeInsets.only(top: 6),
                                    child: Row(
                                      children: [
                                        Icon(
                                          _getStatusIcon(overallStatus),
                                          size: 16,
                                          color: _getStatusColor(overallStatus),
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          _getStatusText(overallStatus),
                                          style: AppTextStyles.body2.copyWith(
                                            color: _getStatusColor(
                                              overallStatus,
                                            ),
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  children: [
                                    ...docs.map<Widget>((doc) {
                                      final status =
                                          doc['status']
                                              ?.toString()
                                              .toLowerCase() ??
                                          'pending';
                                      String? fileUrl =
                                          doc['imageUrl']?.toString() ??
                                          doc['url']?.toString();

                                      if (fileUrl != null &&
                                          fileUrl.isNotEmpty) {
                                        if (!fileUrl.startsWith('http')) {
                                          final cleaned = fileUrl.replaceFirst(
                                            RegExp(r'^/+'),
                                            '',
                                          );
                                          fileUrl = '$backendUrl/$cleaned';
                                        }

                                        final cacheKey =
                                            doc['updatedAt']?.toString() ??
                                            doc['createdAt']?.toString() ??
                                            doc['_id']?.toString();

                                        if (cacheKey != null &&
                                            cacheKey.isNotEmpty) {
                                          final separator =
                                              fileUrl.contains('?') ? '&' : '?';
                                          fileUrl =
                                              '$fileUrl${separator}v=$cacheKey';
                                        }
                                      }

                                      return Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 16.0,
                                          vertical: 10,
                                        ),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Container(
                                                  width: 86,
                                                  height: 66,
                                                  decoration: BoxDecoration(
                                                    color: Colors.grey[100],
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          10,
                                                        ),
                                                    border: Border.all(
                                                      color: Colors.grey
                                                          .withOpacity(0.12),
                                                    ),
                                                  ),
                                                  child:
                                                      fileUrl != null &&
                                                          fileUrl.isNotEmpty
                                                      ? ClipRRect(
                                                          borderRadius:
                                                              BorderRadius.circular(
                                                                10,
                                                              ),
                                                          child: Image.network(
                                                            fileUrl,
                                                            width: 86,
                                                            height: 66,
                                                            fit: BoxFit.cover,
                                                            errorBuilder:
                                                                (
                                                                  _,
                                                                  __,
                                                                  ___,
                                                                ) => Center(
                                                                  child: Icon(
                                                                    Icons
                                                                        .broken_image_rounded,
                                                                    color: Colors
                                                                        .grey[500],
                                                                  ),
                                                                ),
                                                          ),
                                                        )
                                                      : Center(
                                                          child: Icon(
                                                            Icons
                                                                .insert_drive_file,
                                                            color: Colors
                                                                .grey[400],
                                                          ),
                                                        ),
                                                ),
                                                const SizedBox(width: 12),
                                                Expanded(
                                                  child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                      Text(
                                                        (doc['side']
                                                                    ?.toString()
                                                                    .toLowerCase() ==
                                                                'back'
                                                            ? "Back"
                                                            : "Front"),
                                                        style: AppTextStyles
                                                            .body1
                                                            .copyWith(
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w700,
                                                              fontSize: 16,
                                                            ),
                                                      ),
                                                      const SizedBox(height: 6),
                                                      Row(
                                                        children: [
                                                          Icon(
                                                            _getStatusIcon(
                                                              status,
                                                            ),
                                                            size: 14,
                                                            color:
                                                                _getStatusColor(
                                                                  status,
                                                                ),
                                                          ),
                                                          const SizedBox(
                                                            width: 6,
                                                          ),
                                                          Text(
                                                            status == 'rejected'
                                                                ? 'Rejected'
                                                                : status ==
                                                                          'approved' ||
                                                                      status ==
                                                                          'verified'
                                                                ? 'Verified'
                                                                : 'Under Review',
                                                            style: AppTextStyles
                                                                .caption
                                                                .copyWith(
                                                                  color:
                                                                      _getStatusColor(
                                                                        status,
                                                                      ),
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w700,
                                                                ),
                                                          ),
                                                        ],
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                                IconButton(
                                                  icon: const Icon(
                                                    Icons.open_in_full_rounded,
                                                  ),
                                                  onPressed: () {
                                                    if (fileUrl != null &&
                                                        fileUrl.isNotEmpty) {
                                                      Navigator.push(
                                                        context,
                                                        MaterialPageRoute(
                                                          builder: (_) => Scaffold(
                                                            appBar: AppBar(
                                                              backgroundColor:
                                                                  AppColors
                                                                      .primary,
                                                              title: const Text(
                                                                "Preview",
                                                              ),
                                                            ),
                                                            body: Center(
                                                              child: InteractiveViewer(
                                                                child: Image.network(
                                                                  fileUrl!,
                                                                  errorBuilder:
                                                                      (
                                                                        _,
                                                                        __,
                                                                        ___,
                                                                      ) => const Icon(
                                                                        Icons
                                                                            .broken_image_rounded,
                                                                        size:
                                                                            64,
                                                                      ),
                                                                ),
                                                              ),
                                                            ),
                                                          ),
                                                        ),
                                                      );
                                                    } else {
                                                      ScaffoldMessenger.of(
                                                        context,
                                                      ).showSnackBar(
                                                        const SnackBar(
                                                          content: Text(
                                                            "No file to preview",
                                                          ),
                                                        ),
                                                      );
                                                    }
                                                  },
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 12),
                                            const Divider(),
                                          ],
                                        ),
                                      );
                                    }).toList(),
                                    if (hasRejected) ...[
                                      if (combinedRemarks.isNotEmpty)
                                        Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 16,
                                            vertical: 4,
                                          ),
                                          child: Container(
                                            width: double.infinity,
                                            padding: const EdgeInsets.all(12),
                                            decoration: BoxDecoration(
                                              color: AppColors.error
                                                  .withOpacity(0.06),
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                              border: Border.all(
                                                color: AppColors.error
                                                    .withOpacity(0.12),
                                              ),
                                            ),
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  "Reason for rejection:",
                                                  style: AppTextStyles.body2
                                                      .copyWith(
                                                        color: AppColors.error,
                                                        fontWeight:
                                                            FontWeight.w700,
                                                      ),
                                                ),
                                                const SizedBox(height: 6),
                                                Text(
                                                  combinedRemarks,
                                                  style: AppTextStyles.body2
                                                      .copyWith(
                                                        color: AppColors.error,
                                                      ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      const SizedBox(height: 10),
                                      Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 16,
                                          vertical: 4,
                                        ),
                                        child: SizedBox(
                                          width: double.infinity,
                                          child: ElevatedButton.icon(
                                            onPressed: isLoading
                                                ? null
                                                : () async {
                                                    final confirm = await showDialog<bool>(
                                                      context: context,
                                                      builder: (ctx) => AlertDialog(
                                                        title: const Text(
                                                          "Re-upload Document?",
                                                        ),
                                                        content: const Text(
                                                          "You will be taken to the upload screen where you can re-upload this document (front & back). Continue?",
                                                        ),
                                                        actions: [
                                                          TextButton(
                                                            onPressed: () =>
                                                                Navigator.pop(
                                                                  ctx,
                                                                  false,
                                                                ),
                                                            child: const Text(
                                                              "Cancel",
                                                            ),
                                                          ),
                                                          TextButton(
                                                            onPressed: () =>
                                                                Navigator.pop(
                                                                  ctx,
                                                                  true,
                                                                ),
                                                            child: const Text(
                                                              "Yes, continue",
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    );

                                                    if (confirm != true) return;

                                                    final uploadedDocTypes =
                                                        <String>{};
                                                    for (var d
                                                        in uploadedDocuments) {
                                                      final t = d['docType']
                                                          ?.toString()
                                                          .toLowerCase();
                                                      if (t != null &&
                                                          t.isNotEmpty) {
                                                        uploadedDocTypes.add(t);
                                                      }
                                                    }

                                                    if (docType.toLowerCase() ==
                                                        'profile') {
                                                      final result = await Navigator.push<bool>(
                                                        context,
                                                        MaterialPageRoute(
                                                          builder: (context) =>
                                                              DriverDocumentUploadPage(
                                                                driverId:
                                                                    widget
                                                                        .driverId ??
                                                                    FirebaseAuth
                                                                        .instance
                                                                        .currentUser
                                                                        ?.uid ??
                                                                    '',
                                                                isReuploadingProfile:
                                                                    true,
                                                              ),
                                                        ),
                                                      );

                                                      if (result == true &&
                                                          mounted) {
                                                        await _fetchDriverDocuments();
                                                      }
                                                      return;
                                                    }

                                                    final result = await Navigator.push<bool>(
                                                      context,
                                                      MaterialPageRoute(
                                                        builder: (context) =>
                                                            DriverDocumentUploadPage(
                                                              driverId:
                                                                  widget
                                                                      .driverId ??
                                                                  FirebaseAuth
                                                                      .instance
                                                                      .currentUser
                                                                      ?.uid ??
                                                                  '',
                                                              uploadedDocTypes:
                                                                  uploadedDocTypes
                                                                      .toList(),
                                                              preselectDocType:
                                                                  docType,
                                                              preselectDocSide:
                                                                  preselectSide,
                                                            ),
                                                      ),
                                                    );

                                                    if (result == true &&
                                                        mounted) {
                                                      await _fetchDriverDocuments();
                                                    }
                                                  },
                                            icon: const Icon(
                                              Icons.refresh_rounded,
                                            ),
                                            label: Text(
                                              isLoading
                                                  ? "Processing..."
                                                  : "Re-upload document",
                                              style: AppTextStyles.button
                                                  .copyWith(
                                                    color: AppColors.onPrimary,
                                                  ),
                                            ),
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor:
                                                  AppColors.primary,
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    vertical: 14,
                                                  ),
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ] else
                                      Padding(
                                        padding: const EdgeInsets.fromLTRB(
                                          16,
                                          0,
                                          16,
                                          12,
                                        ),
                                        child: Text(
                                          overallStatus == 'approved'
                                              ? "All files for this document are verified by admin."
                                              : "This document is under review by admin.",
                                          style: AppTextStyles.caption,
                                        ),
                                      ),
                                  ],
                                ),
                              );
                            },
                          ),
                          const SizedBox(height: 32),
                        ],

                        // Action Button
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: allDocsApproved
                                ? () async {
                                    final prefs =
                                        await SharedPreferences.getInstance();
                                    await prefs.setBool(
                                      'hasSeenApprovalPage',
                                      true,
                                    );

                                    debugPrint(
                                      "✅ Setting hasSeenApprovalPage = true",
                                    );

                                    if (!mounted) return;

                                    Navigator.pushReplacement(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) =>
                                            DriverDashboardPage(
                                              driverId:
                                                  widget.driverId ??
                                                  FirebaseAuth
                                                      .instance
                                                      .currentUser
                                                      ?.uid ??
                                                  '',
                                              vehicleType:
                                                  vehicleType ?? 'bike',
                                            ),
                                      ),
                                    );
                                  }
                                : null,
                            icon: Icon(
                              allDocsApproved
                                  ? Icons.dashboard_rounded
                                  : Icons.hourglass_empty_rounded,
                              size: 24,
                            ),
                            label: Text(
                              allDocsApproved
                                  ? "Go to Dashboard"
                                  : allDocsUploaded
                                  ? "Waiting for Approval"
                                  : "Complete Document Upload",
                              style: AppTextStyles.button.copyWith(
                                color: AppColors.onPrimary,
                                fontSize: 18,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: allDocsApproved
                                  ? AppColors.success
                                  : AppColors.onSurfaceSecondary,
                              foregroundColor: AppColors.onPrimary,
                              padding: const EdgeInsets.symmetric(vertical: 18),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              elevation: allDocsApproved ? 4 : 0,
                            ),
                          ),
                        ),

                        if (!allDocsApproved) ...[
                          const SizedBox(height: 16),
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withOpacity(0.05),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: AppColors.primary.withOpacity(0.2),
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.lightbulb_outline_rounded,
                                  color: AppColors.primary,
                                  size: 22,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    allDocsUploaded
                                        ? "We're reviewing your documents. You'll be notified once approved."
                                        : "Upload all required documents to proceed with verification.",
                                    style: AppTextStyles.body2.copyWith(
                                      color: AppColors.primary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
        ),
      ),
    );
  }

  Widget _buildStatusMetric(String label, String value, IconData icon) {
    return Column(
      children: [
        Icon(icon, color: Colors.white, size: 24),
        const SizedBox(height: 6),
        Text(
          value,
          style: AppTextStyles.heading3.copyWith(
            color: Colors.white,
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: AppTextStyles.caption.copyWith(
            color: Colors.white.withOpacity(0.9),
            fontSize: 11,
          ),
        ),
      ],
    );
  }
}
