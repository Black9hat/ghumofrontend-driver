import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:drivergoo/config.dart';

// 🔐 Google Maps API Key from config (set in environment or manifest)
const String GOOGLE_MAPS_API_KEY = AppConfig.googleMapsApiKey;

class DriverGoToDestinationPage extends StatefulWidget {
  const DriverGoToDestinationPage({Key? key}) : super(key: key);

  @override
  State<DriverGoToDestinationPage> createState() =>
      _DriverGoToDestinationPageState();
}

class _DriverGoToDestinationPageState extends State<DriverGoToDestinationPage> {
  // ============================================
  // ✅ BACKEND URL FROM CONFIGURATION (HTTPS ONLY)
  // ============================================
  static String _backendUrl = AppConfig.backendBaseUrl;

  static const Duration _apiTimeout = Duration(seconds: 15);

  // ============================================
  // STATE VARIABLES
  // ============================================

  LatLng? _currentLocation;
  LatLng? _selectedDestination;
  bool _isLoading = false;
  bool _isDestinationEnabled = false;

  // 🔍 SEARCH VARIABLES
  final TextEditingController _searchController = TextEditingController();
  List<dynamic> _placeSuggestions = [];
  bool _isSearching = false;

  // 📍 SELECTED DESTINATION DETAILS
  double? _selectedLat;
  double? _selectedLng;
  String? _selectedPlaceName;

  // MAP & MARKERS
  GoogleMapController? _mapController;
  final Set<Marker> _markers = {};

  @override
  void initState() {
    super.initState();
    _loadCurrentLocation();
    _checkCurrentDestinationStatus();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _mapController?.dispose();
    super.dispose();
  }

  // ============================================
  // LOCATION FUNCTIONS
  // ============================================

  Future<void> _loadCurrentLocation() async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          _showSnackBar('Location permission denied', Colors.red);
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        _showSnackBar('Location permission permanently denied', Colors.red);
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      setState(() {
        _currentLocation = LatLng(position.latitude, position.longitude);
      });
    } catch (e) {
      debugPrint('Error getting location: $e');
      _showSnackBar('Failed to get current location', Colors.red);
    }
  }

  // ============================================
  // CHECK EXISTING DESTINATION STATUS
  // ============================================

  Future<void> _checkCurrentDestinationStatus() async {
    try {
      // 🔐 1️⃣ AUTHENTICATION
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw Exception("User not authenticated");
      }

      final token = await user.getIdToken();
      if (!mounted) return;

      if (token!.isEmpty) {
        throw Exception("Failed to get authentication token");
      }

      final headers = {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      };

      // 🌐 2️⃣ API CALL
      final response = await http
          .get(
            Uri.parse('$_backendUrl/api/driver/go-to-destination/status'),
            headers: headers,
          )
          .timeout(_apiTimeout);

      // ✅ 3️⃣ HANDLE RESPONSE
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (data['success'] == true) {
          setState(() {
            // 🔥 SINGLE SOURCE OF TRUTH
            _isDestinationEnabled = data['enabled'] == true;
          });
        }
      } else {
        debugPrint("❌ Status check failed: ${response.statusCode}");
        debugPrint("❌ Body: ${response.body}");
      }
    } catch (e) {
      debugPrint('❌ Error checking destination status: $e');
      // Silent fail – do not disturb driver for background status check
    }
  }

  // ============================================
  // 🔍 SEARCH PLACES (GOOGLE PLACES API)
  // ============================================

  Future<void> _searchPlaces(String query) async {
    if (query.isEmpty) {
      setState(() => _placeSuggestions = []);
      return;
    }

    // Don't search if query is too short
    if (query.length < 3) return;

    setState(() => _isSearching = true);

    try {
      // Google Places Autocomplete API
      final url =
          'https://maps.googleapis.com/maps/api/place/autocomplete/json'
          '?input=${Uri.encodeComponent(query)}'
          '&key=$GOOGLE_MAPS_API_KEY'
          '&components=country:in'
          '&types=geocode|establishment';

      final response = await http.get(Uri.parse(url)).timeout(_apiTimeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (data['status'] == 'OK') {
          setState(() {
            _placeSuggestions = data['predictions'] ?? [];
            _isSearching = false;
          });
        } else {
          debugPrint('Google Places API status: ${data['status']}');
          setState(() {
            _placeSuggestions = [];
            _isSearching = false;
          });
        }
      } else {
        debugPrint('Google Places API error: ${response.statusCode}');
        setState(() => _isSearching = false);
      }
    } catch (e) {
      debugPrint('Error searching places: $e');
      setState(() => _isSearching = false);
    }
  }

  // ============================================
  // SELECT PLACE FROM SUGGESTIONS (GET PLACE DETAILS)
  // ============================================

  Future<void> _selectPlace(dynamic place) async {
    final placeId = place['place_id'];
    final description = place['description'] ?? 'Selected Location';

    // Show loading
    setState(() {
      _isSearching = true;
      _placeSuggestions = [];
      _searchController.text = description;
    });

    // Hide keyboard
    FocusScope.of(context).unfocus();

    try {
      // Get place details to get coordinates
      final detailsUrl =
          'https://maps.googleapis.com/maps/api/place/details/json'
          '?place_id=$placeId'
          '&key=$GOOGLE_MAPS_API_KEY'
          '&fields=geometry,formatted_address,name';

      final response = await http
          .get(Uri.parse(detailsUrl))
          .timeout(_apiTimeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (data['status'] == 'OK' && data['result'] != null) {
          final result = data['result'];
          final location = result['geometry']['location'];

          setState(() {
            _selectedLat = location['lat'].toDouble();
            _selectedLng = location['lng'].toDouble();
            _selectedPlaceName = result['formatted_address'] ?? description;
            _selectedDestination = LatLng(_selectedLat!, _selectedLng!);
            _searchController.text = _selectedPlaceName!;
            _isSearching = false;
          });

          // Update marker and move camera
          _updateMarker(_selectedDestination!);
          _moveMapToLocation(_selectedLat!, _selectedLng!);
        } else {
          debugPrint('Place details error: ${data['status']}');
          _showSnackBar('Failed to get place details', Colors.orange);
          setState(() => _isSearching = false);
        }
      } else {
        _showSnackBar('Failed to get place details', Colors.orange);
        setState(() => _isSearching = false);
      }
    } catch (e) {
      debugPrint('Error getting place details: $e');
      _showSnackBar('Error getting place details', Colors.red);
      setState(() => _isSearching = false);
    }
  }

  // ============================================
  // MAP FUNCTIONS
  // ============================================

  void _updateMarker(LatLng point) {
    setState(() {
      _markers
        ..clear()
        ..add(
          Marker(
            markerId: const MarkerId('goto_destination'),
            position: point,
            icon: BitmapDescriptor.defaultMarkerWithHue(
              BitmapDescriptor.hueOrange,
            ),
            infoWindow: const InfoWindow(title: '🧡 Go To Destination'),
          ),
        );
    });
  }

  void _moveMapToLocation(double lat, double lng) {
    _mapController?.animateCamera(
      CameraUpdate.newLatLngZoom(LatLng(lat, lng), 15),
    );
  }

  // Select destination on map tap
  void _selectDestinationOnMap(LatLng point) {
    setState(() {
      _selectedLat = point.latitude;
      _selectedLng = point.longitude;
      _selectedDestination = point;
      _selectedPlaceName = 'Selected Location';
      _searchController.text =
          'Lat: ${point.latitude.toStringAsFixed(4)}, Lng: ${point.longitude.toStringAsFixed(4)}';
      _placeSuggestions = [];
    });
    _updateMarker(point);

    // Optionally: Reverse geocode to get address
    _reverseGeocode(point.latitude, point.longitude);
  }

  // ============================================
  // 🔄 REVERSE GEOCODE (GET ADDRESS FROM COORDINATES)
  // ============================================

  Future<void> _reverseGeocode(double lat, double lng) async {
    try {
      final url =
          'https://maps.googleapis.com/maps/api/geocode/json'
          '?latlng=$lat,$lng'
          '&key=$GOOGLE_MAPS_API_KEY';

      final response = await http.get(Uri.parse(url)).timeout(_apiTimeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (data['status'] == 'OK' && data['results'].isNotEmpty) {
          final address = data['results'][0]['formatted_address'];
          setState(() {
            _selectedPlaceName = address;
            _searchController.text = address;
          });
        }
      }
    } catch (e) {
      debugPrint('Reverse geocode error: $e');
      // Silent fail - keep the lat/lng display
    }
  }

  // ============================================
  // 🧡 ENABLE GO TO DESTINATION - API CALL
  // ✅ STEP 1, 3, 4 — EXACT SAME PATTERN AS PROFILE PAGE
  // ============================================

  Future<void> _enableGoToDestination() async {
    // Validate selection
    if (_selectedLat == null || _selectedLng == null) {
      _showSnackBar(
        'Please select a destination from suggestions or tap on the map',
        Colors.orange,
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      // ✅ STEP 1 — COPY TOKEN + HEADERS LOGIC (EXACT SAME AS PROFILE PAGE)
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw Exception("User not authenticated");
      }

      final token = await user.getIdToken();
      if (!mounted) return;

      if (token == null || token.isEmpty) {
        throw Exception("Failed to get authentication token");
      }

      final headers = {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      };

      // ✅ STEP 3 — DESTINATION API CALL (SAME _backendUrl)
      final response = await http
          .post(
            Uri.parse('$_backendUrl/api/driver/go-to-destination'),
            headers: headers,
            body: jsonEncode({
              'lat': _selectedLat,
              'lng': _selectedLng,
              'enabled': true,
            }),
          )
          .timeout(_apiTimeout);

      // ✅ STEP 4 — HANDLE RESPONSE LIKE PROFILE PAGE
      if (response.statusCode == 200) {
        setState(() {
          _isDestinationEnabled = true;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Go To Destination enabled")),
        );

        Navigator.pop(context, {
          'enabled': true,
          'lat': _selectedLat,
          'lng': _selectedLng,
          'address': _selectedPlaceName,
        });
      } else {
        debugPrint("❌ Status: ${response.statusCode}");
        debugPrint("❌ Body: ${response.body}");
        throw Exception("Failed (${response.statusCode}): ${response.body}");
      }
    } catch (e) {
      debugPrint('Error enabling destination: $e');

      String errorMessage = 'Network error. Please try again.';
      if (e.toString().contains('User not authenticated')) {
        errorMessage = 'Session expired. Please login again.';
      } else if (e.toString().contains('Failed to get authentication')) {
        errorMessage = 'Authentication error. Please login again.';
      } else if (e is Exception) {
        errorMessage = e.toString().replaceAll('Exception: ', '');
      }

      _showSnackBar(errorMessage, Colors.red);
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // ============================================
  // 🔴 DISABLE GO TO DESTINATION - API CALL
  // ✅ STEP 1, 3, 4 — EXACT SAME PATTERN AS PROFILE PAGE
  // ============================================

  Future<void> _disableGoToDestination() async {
    setState(() => _isLoading = true);

    try {
      // ✅ STEP 1 — COPY TOKEN + HEADERS LOGIC (EXACT SAME AS PROFILE PAGE)
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw Exception("User not authenticated");
      }

      final token = await user.getIdToken();
      if (!mounted) return;

      if (token == null || token.isEmpty) {
        throw Exception("Failed to get authentication token");
      }

      final headers = {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      };

      // ✅ STEP 3 — DESTINATION API CALL (SAME _backendUrl)
      final response = await http
          .post(
            Uri.parse('$_backendUrl/api/driver/go-to-destination'),
            headers: headers,
            body: jsonEncode({'enabled': false}),
          )
          .timeout(_apiTimeout);

      // ✅ STEP 4 — HANDLE RESPONSE LIKE PROFILE PAGE
      if (response.statusCode == 200) {
        setState(() {
          _isDestinationEnabled = false;
          _selectedDestination = null;
          _selectedLat = null;
          _selectedLng = null;
          _selectedPlaceName = null;
          _searchController.clear();
          _markers.clear();
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Go To Destination disabled")),
        );

        Navigator.pop(context, {'enabled': false});
      } else {
        debugPrint("❌ Status: ${response.statusCode}");
        debugPrint("❌ Body: ${response.body}");
        throw Exception("Failed (${response.statusCode}): ${response.body}");
      }
    } catch (e) {
      debugPrint('Error disabling destination: $e');

      String errorMessage = 'Network error. Please try again.';
      if (e.toString().contains('User not authenticated')) {
        errorMessage = 'Session expired. Please login again.';
      } else if (e is Exception) {
        errorMessage = e.toString().replaceAll('Exception: ', '');
      }

      _showSnackBar(errorMessage, Colors.red);
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // ============================================
  // HELPER: SHOW SNACKBAR
  // ============================================

  void _showSnackBar(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  // ============================================
  // BUILD UI
  // ============================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,

      // 🔹 APP BAR
      appBar: AppBar(
        title: const Text(
          'Go To Destination',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        actions: [
          // Show status indicator
          if (_isDestinationEnabled)
            Container(
              margin: const EdgeInsets.only(right: 16),
              child: const Row(
                children: [
                  Icon(Icons.favorite, color: Colors.orange, size: 20),
                  SizedBox(width: 4),
                  Text(
                    'ON',
                    style: TextStyle(
                      color: Colors.orange,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),

      body: Column(
        children: [
          // 🔍 SEARCH SECTION
          _buildSearchSection(),

          // 🗺️ MAP
          Expanded(
            child: _currentLocation == null
                ? const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(color: Colors.orange),
                        SizedBox(height: 16),
                        Text('Getting your location...'),
                      ],
                    ),
                  )
                : Stack(
                    children: [
                      GoogleMap(
                        initialCameraPosition: CameraPosition(
                          target: _currentLocation!,
                          zoom: 14,
                        ),
                        myLocationEnabled: true,
                        myLocationButtonEnabled: false,
                        markers: _markers,
                        onTap: _isDestinationEnabled
                            ? null
                            : _selectDestinationOnMap,
                        onMapCreated: (controller) {
                          _mapController = controller;
                        },
                        mapToolbarEnabled: false,
                        zoomControlsEnabled: false,
                      ),

                      // ℹ️ HELP TEXT
                      Positioned(
                        top: 12,
                        left: 12,
                        right: 12,
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: _isDestinationEnabled
                                ? Colors.orange.withOpacity(0.9)
                                : Colors.black.withOpacity(0.7),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                _isDestinationEnabled
                                    ? Icons.favorite
                                    : Icons.touch_app,
                                color: Colors.white,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _isDestinationEnabled
                                      ? 'Destination mode is active! Trips on your way will be shown with 🧡'
                                      : 'Search for a place or tap on the map to select your destination',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      // 📍 MY LOCATION BUTTON
                      Positioned(
                        right: 16,
                        bottom: 16,
                        child: FloatingActionButton.small(
                          heroTag: 'myLocation',
                          backgroundColor: Colors.white,
                          onPressed: () {
                            if (_currentLocation != null) {
                              _mapController?.animateCamera(
                                CameraUpdate.newLatLngZoom(
                                  _currentLocation!,
                                  15,
                                ),
                              );
                            }
                          },
                          child: const Icon(
                            Icons.my_location,
                            color: Colors.black87,
                          ),
                        ),
                      ),
                    ],
                  ),
          ),

          // ✅ ACTION BAR
          _buildActionBar(),
        ],
      ),
    );
  }

  // ============================================
  // 🔍 SEARCH SECTION WIDGET
  // ============================================

  Widget _buildSearchSection() {
    return Container(
      color: Colors.white,
      child: Column(
        children: [
          // 🔍 SEARCH INPUT FIELD
          Padding(
            padding: const EdgeInsets.all(16),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: _placeSuggestions.isNotEmpty
                      ? Colors.orange
                      : Colors.grey.shade300,
                ),
              ),
              child: TextField(
                controller: _searchController,
                enabled: !_isDestinationEnabled,
                decoration: InputDecoration(
                  prefixIcon: Icon(Icons.search, color: Colors.grey.shade600),
                  hintText: 'Search destination...',
                  hintStyle: TextStyle(color: Colors.grey.shade500),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 20),
                          onPressed: () {
                            _searchController.clear();
                            setState(() {
                              _placeSuggestions = [];
                              _selectedLat = null;
                              _selectedLng = null;
                              _selectedPlaceName = null;
                              _selectedDestination = null;
                              _markers.clear();
                            });
                          },
                        )
                      : null,
                ),
                onChanged: _searchPlaces,
              ),
            ),
          ),

          // 🔄 LOADING INDICATOR
          if (_isSearching)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.orange,
                ),
              ),
            ),

          // 📍 SUGGESTIONS LIST (GOOGLE PLACES FORMAT)
          if (_placeSuggestions.isNotEmpty)
            Container(
              constraints: const BoxConstraints(maxHeight: 200),
              margin: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ListView.builder(
                shrinkWrap: true,
                physics: const BouncingScrollPhysics(),
                itemCount: _placeSuggestions.length,
                itemBuilder: (context, index) {
                  final place = _placeSuggestions[index];

                  // Google Places API format
                  final mainText =
                      place['structured_formatting']?['main_text'] ??
                      place['description'] ??
                      'Unknown';
                  final secondaryText =
                      place['structured_formatting']?['secondary_text'] ?? '';

                  return ListTile(
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.orange.withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.location_on,
                        color: Colors.orange,
                        size: 20,
                      ),
                    ),
                    title: Text(
                      mainText,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: secondaryText.isNotEmpty
                        ? Text(
                            secondaryText,
                            style: TextStyle(
                              color: Colors.grey.shade600,
                              fontSize: 12,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          )
                        : null,
                    onTap: () => _selectPlace(place),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                  );
                },
              ),
            ),

          // Add spacing after suggestions
          if (_placeSuggestions.isNotEmpty) const SizedBox(height: 8),
        ],
      ),
    );
  }

  // ============================================
  // ✅ ACTION BAR WIDGET
  // ============================================

  Widget _buildActionBar() {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 12,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ℹ️ INFO ROW (when destination selected but not enabled)
            if (_selectedDestination != null && !_isDestinationEnabled)
              Container(
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.favorite, color: Colors.orange.shade700),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Go To Mode',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _selectedPlaceName ?? 'Selected Location',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          const Text(
                            'You\'ll receive rides that drop off near your destination',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.black54,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

            // 🟢 IF ENABLED - SHOW ACTIVE STATUS & DISABLE BUTTON
            if (_isDestinationEnabled) ...[
              Container(
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.green.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.check_circle, color: Colors.green.shade700),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Go To Destination is active',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                          if (_selectedPlaceName != null) ...[
                            const SizedBox(height: 4),
                            Text(
                              _selectedPlaceName!,
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                          const SizedBox(height: 4),
                          const Text(
                            'Matching trips will show 🧡',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.black54,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // DISABLE BUTTON
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.grey.shade700,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: _isLoading ? null : _disableGoToDestination,
                  child: _isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Text(
                          'Disable Go To Mode',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                ),
              ),
            ]
            // 🟠 IF NOT ENABLED - SHOW ENABLE BUTTON
            else
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _selectedDestination != null
                        ? Colors.orange
                        : Colors.grey.shade400,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: _selectedDestination != null ? 2 : 0,
                  ),
                  onPressed: _selectedDestination == null || _isLoading
                      ? null
                      : _enableGoToDestination,
                  child: _isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              _selectedDestination != null
                                  ? Icons.favorite
                                  : Icons.search,
                              color: Colors.white,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _selectedDestination == null
                                  ? 'Search or Tap Map to Select'
                                  : 'Start Go To Mode',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
