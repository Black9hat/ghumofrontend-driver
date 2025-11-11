import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';

// Import your pages
import 'driver_login_page.dart';
import 'driver_details_page.dart';
import 'documents_review_page.dart';
import 'driver_dashboard_page.dart';

class AppColors {
  static const Color primary = Color.fromARGB(255, 212, 120, 0);
  static const Color background = Colors.white;
  static const Color onSurface = Colors.black;
  static const Color onPrimary = Colors.white;
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({Key? key}) : super(key: key);

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  final String backendUrl = "https://1708303a1cc8.ngrok-free.app";
  
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  
  String _statusMessage = "Initializing...";
  bool _showError = false;

  @override
  void initState() {
    super.initState();
    
    // Setup animation
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeIn),
    );
    
    _animationController.forward();
    
    // Start the session check process
    _initializeApp();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  /// 🚀 MAIN INITIALIZATION FLOW
  Future<void> _initializeApp() async {
    try {
      await Future.delayed(const Duration(seconds: 1)); // Minimum splash duration
      
      // STEP 1: Check if user is logged in
      final sessionData = await _checkLoginSession();
      
      if (sessionData == null) {
        _navigateToLogin();
        return;
      }
      
      // STEP 2: Verify session with backend & check documents
      final verificationResult = await _verifySessionAndDocuments(sessionData);
      
      if (verificationResult == null) {
        _navigateToLogin();
        return;
      }
      
      // STEP 3: Navigate based on status
      _navigateBasedOnStatus(verificationResult);
      
    } catch (e) {
      print("❌ Initialization error: $e");
      _showErrorAndRetry("Failed to initialize app: $e");
    }
  }

  /// ✅ STEP 1: Check Local Session
  Future<Map<String, dynamic>?> _checkLoginSession() async {
    _updateStatus("Checking login status...");
    
    try {
      final prefs = await SharedPreferences.getInstance();
      
      final driverId = prefs.getString("driverId");
      final phoneNumber = prefs.getString("phoneNumber");
      final isLoggedIn = prefs.getBool("isLoggedIn") ?? false;
      final vehicleType = prefs.getString("vehicleType");
      
      print("");
      print("=" * 70);
      print("📋 LOCAL SESSION CHECK");
      print("=" * 70);
      print("   Driver ID: $driverId");
      print("   Phone: $phoneNumber");
      print("   Is Logged In: $isLoggedIn");
      print("   Vehicle Type: $vehicleType");
      print("=" * 70);
      print("");
      
      if (!isLoggedIn || driverId == null || driverId.isEmpty) {
        print("❌ No valid local session found");
        return null;
      }
      
      // Also check Firebase auth
      final firebaseUser = FirebaseAuth.instance.currentUser;
      if (firebaseUser == null) {
        print("⚠️ No Firebase user found - clearing session");
        await prefs.clear();
        return null;
      }
      
      return {
        'driverId': driverId,
        'phoneNumber': phoneNumber,
        'vehicleType': vehicleType,
      };
      
    } catch (e) {
      print("❌ Error checking login session: $e");
      return null;
    }
  }

  /// ✅ STEP 2: Verify with Backend & Check Documents
  Future<Map<String, dynamic>?> _verifySessionAndDocuments(
    Map<String, dynamic> sessionData,
  ) async {
    _updateStatus("Verifying your account...");
    
    try {
      final driverId = sessionData['driverId'];
      
      // Get Firebase token
      final token = await FirebaseAuth.instance.currentUser?.getIdToken();
      if (token == null) {
        print("❌ No Firebase token - session invalid");
        return null;
      }
      
      // Check documents status
      _updateStatus("Checking documents...");
      
      print("");
      print("=" * 70);
      print("🌐 API REQUEST");
      print("=" * 70);
      print("   URL: $backendUrl/api/driver/documents/$driverId");
      print("   Driver ID: $driverId");
      print("   Token: ${token.substring(0, 20)}...");
      print("=" * 70);
      print("");
      
      final response = await http.get(
        Uri.parse('$backendUrl/api/driver/documents/$driverId'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      ).timeout(const Duration(seconds: 10));
      
      print("");
      print("=" * 70);
      print("📄 DOCUMENT VERIFICATION RESPONSE");
      print("=" * 70);
      print("   Status Code: ${response.statusCode}");
      print("   Body: ${response.body}");
      print("=" * 70);
      print("");
      
      if (response.statusCode == 404) {
        // No documents uploaded yet - THIS IS EXPECTED FOR NEW DRIVERS
        print("ℹ️  404 Response - No documents found (Expected for new drivers)");
        print("➡️  Redirecting to document upload page");
        return {
          'driverId': driverId,
          'status': 'no_documents',
          'vehicleType': sessionData['vehicleType'],
        };
      }
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        
        // Check if message indicates no documents
        if (data.containsKey('message') && 
            data['message'].toString().toLowerCase().contains('no documents')) {
          print("ℹ️  Message indicates no documents");
          return {
            'driverId': driverId,
            'status': 'no_documents',
            'vehicleType': sessionData['vehicleType'],
          };
        }
        
        final docs = List<Map<String, dynamic>>.from(data["docs"] ?? []);
        final vehicleType = data["vehicleType"]?.toString() ?? sessionData['vehicleType'];
        
        // ⚠️ CRITICAL CHECK: Must have documents
        if (docs.isEmpty) {
          print("ℹ️  No documents found in response array");
          return {
            'driverId': driverId,
            'status': 'no_documents',
            'vehicleType': vehicleType,
          };
        }
        
        // 🔍 DETAILED DOCUMENT STATUS CHECK
        print("");
        print("=" * 70);
        print("🔍 ANALYZING DOCUMENT STATUSES");
        print("=" * 70);
        
        int approvedCount = 0;
        int verifiedCount = 0;
        int pendingCount = 0;
        int rejectedCount = 0;
        int otherCount = 0;
        
        for (var doc in docs) {
          final docType = doc['documentType'] ?? doc['docType'] ?? 'Unknown';
          final status = doc['status']?.toString().toLowerCase() ?? 'unknown';
          
          print("   📄 $docType: $status");
          
          switch (status) {
            case 'approved':
              approvedCount++;
              break;
            case 'verified':
              verifiedCount++;
              break;
            case 'pending':
            case 'under_review':
            case 'submitted':
              pendingCount++;
              break;
            case 'rejected':
            case 'declined':
              rejectedCount++;
              break;
            default:
              otherCount++;
              print("   ⚠️  Unknown status: $status");
          }
        }
        
        print("   ─────────────────────────");
        print("   ✅ Approved: $approvedCount");
        print("   ✅ Verified: $verifiedCount");
        print("   ⏳ Pending: $pendingCount");
        print("   ❌ Rejected: $rejectedCount");
        print("   ⚠️  Other: $otherCount");
        print("   ─────────────────────────");
        print("   📊 Total Documents: ${docs.length}");
        
        // ✅ STRICT APPROVAL CHECK
        // ALL documents must be either 'approved' OR 'verified'
        // AND at least one document must exist
        final totalApproved = approvedCount + verifiedCount;
        final allDocsApproved = (totalApproved == docs.length) && (docs.length > 0);
        
        print("   🎯 All Approved Check: $allDocsApproved ($totalApproved/${docs.length})");
        print("=" * 70);
        print("");
        
        if (allDocsApproved) {
          // ✅ ALL APPROVED - Check for active trip
          print("✅ ALL DOCUMENTS APPROVED - Granting dashboard access");
          _updateStatus("Checking active trips...");
          final activeTripId = await _checkForActiveTrip(driverId);
          
          return {
            'driverId': driverId,
            'status': 'approved',
            'vehicleType': vehicleType,
            'activeTripId': activeTripId,
          };
        } else {
          // ❌ NOT ALL APPROVED - Keep in review
          if (rejectedCount > 0) {
            print("❌ SOME DOCUMENTS REJECTED - Redirecting to review");
          } else if (pendingCount > 0) {
            print("⏳ SOME DOCUMENTS PENDING - Redirecting to review");
          } else if (otherCount > 0) {
            print("⚠️ DOCUMENTS WITH UNKNOWN STATUS - Redirecting to review");
          } else {
            print("⚠️ NOT ALL DOCUMENTS APPROVED - Redirecting to review");
          }
          
          return {
            'driverId': driverId,
            'status': 'pending_review',
            'vehicleType': vehicleType,
            'documents': docs,
          };
        }
      }
      
      // Unexpected response
      print("⚠️ Unexpected response: ${response.statusCode}");
      print("⚠️ Response body: ${response.body}");
      
      // For other error codes, assume no documents
      if (response.statusCode >= 400 && response.statusCode < 500) {
        print("ℹ️  Client error - treating as no documents");
        return {
          'driverId': driverId,
          'status': 'no_documents',
          'vehicleType': sessionData['vehicleType'],
        };
      }
      
      return null;
      
    } catch (e) {
      print("❌ Error verifying session: $e");
      print("Stack trace: ${StackTrace.current}");
      return null;
    }
  }

  /// ✅ STEP 2.5: Check for Active Trip
  Future<String?> _checkForActiveTrip(String driverId) async {
    try {
      print("");
      print("=" * 70);
      print("🔍 CHECKING FOR ACTIVE TRIP");
      print("=" * 70);
      
      final response = await http.get(
        Uri.parse('$backendUrl/api/trip/driver/active/$driverId'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        
        if (data['success'] && data['hasActiveTrip']) {
          final tripId = data['trip']['tripId'];
          print("⚠️ ACTIVE TRIP FOUND: $tripId");
          print("=" * 70);
          print("");
          return tripId;
        }
      }
      
      print("✅ No active trip found");
      print("=" * 70);
      print("");
      return null;
      
    } catch (e) {
      print("❌ Error checking active trip: $e");
      print("=" * 70);
      print("");
      return null;
    }
  }

  /// ✅ STEP 3: Navigate Based on Status
  void _navigateBasedOnStatus(Map<String, dynamic> result) {
    final status = result['status'];
    final driverId = result['driverId'];
    final vehicleType = result['vehicleType'];
    
    print("");
    print("=" * 70);
    print("🎯 NAVIGATION DECISION");
    print("=" * 70);
    print("   Status: $status");
    print("   Driver ID: $driverId");
    print("   Vehicle Type: $vehicleType");
    print("=" * 70);
    print("");
    
    switch (status) {
      case 'no_documents':
        print("➡️  NAVIGATING TO: Document Upload Page");
        _updateStatus("Redirecting to document upload...");
        Future.delayed(const Duration(milliseconds: 500), () {
          _navigateToDocumentUpload(driverId);
        });
        break;
        
      case 'pending_review':
        print("➡️  NAVIGATING TO: Documents Review Page");
        _updateStatus("Documents under review...");
        Future.delayed(const Duration(milliseconds: 500), () {
          _navigateToDocumentReview(driverId);
        });
        break;
        
      case 'approved':
        // ⚠️ EXTRA SAFETY CHECK
        if (vehicleType == null || vehicleType.isEmpty) {
          print("⚠️ CRITICAL: Vehicle type missing for approved driver!");
          print("➡️  NAVIGATING TO: Document Upload Page (Missing Vehicle Type)");
          _navigateToDocumentUpload(driverId);
        } else {
          print("✅ ALL CHECKS PASSED");
          print("➡️  NAVIGATING TO: Driver Dashboard");
          _updateStatus("Loading dashboard...");
          Future.delayed(const Duration(milliseconds: 500), () {
            _navigateToDashboard(driverId, vehicleType);
          });
        }
        break;
        
      default:
        print("⚠️ Unknown status: $status");
        print("➡️  NAVIGATING TO: Login Page (Unknown Status)");
        _navigateToLogin();
    }
  }

  /// 📱 NAVIGATION METHODS
  void _navigateToLogin() {
    if (!mounted) return;
    print("🔄 Navigating to Login Page...");
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const DriverLoginPage()),
    );
  }

  void _navigateToDocumentUpload(String driverId) {
    if (!mounted) return;
    print("🔄 Navigating to Document Upload Page...");
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => DriverDocumentUploadPage(driverId: driverId),
      ),
    );
  }

  void _navigateToDocumentReview(String driverId) {
    if (!mounted) return;
    print("🔄 Navigating to Document Review Page...");
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => DocumentsReviewPage(driverId: driverId),
      ),
    );
  }

  void _navigateToDashboard(String driverId, String vehicleType) {
    if (!mounted) return;
    print("🔄 Navigating to Dashboard...");
    print("   Driver ID: $driverId");
    print("   Vehicle Type: $vehicleType");
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => DriverDashboardPage(
          driverId: driverId,
          vehicleType: vehicleType,
        ),
      ),
    );
  }

  /// 🔄 HELPER METHODS
  void _updateStatus(String message) {
    if (mounted) {
      setState(() {
        _statusMessage = message;
        _showError = false;
      });
    }
    print("📱 Status: $message");
  }

  void _showErrorAndRetry(String error) {
    if (mounted) {
      setState(() {
        _statusMessage = error;
        _showError = true;
      });
    }
  }

  void _retry() {
    setState(() {
      _statusMessage = "Retrying...";
      _showError = false;
    });
    _initializeApp();
  }

  /// 🎨 UI BUILD
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(32.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // App Logo/Icon
                  Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.local_taxi,
                      size: 60,
                      color: AppColors.primary,
                    ),
                  ),
                  
                  const SizedBox(height: 32),
                  
                  // App Name
                  Text(
                    "Driver App",
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: AppColors.onSurface,
                    ),
                  ),
                  
                  const SizedBox(height: 48),
                  
                  // Loading Indicator
                  if (!_showError) ...[
                    const SizedBox(
                      width: 40,
                      height: 40,
                      child: CircularProgressIndicator(
                        strokeWidth: 3,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          AppColors.primary,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                  
                  // Status Message
                  Text(
                    _statusMessage,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: _showError ? Colors.red : AppColors.onSurface,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  
                  // Retry Button
                  if (_showError) ...[
                    const SizedBox(height: 24),
                    ElevatedButton.icon(
                      onPressed: _retry,
                      icon: const Icon(Icons.refresh),
                      label: const Text("Retry"),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: AppColors.onPrimary,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 32,
                          vertical: 16,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
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
}