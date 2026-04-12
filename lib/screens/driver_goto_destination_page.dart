import 'dart:convert';
import 'dart:ui';
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
  String? _activeLocationId; // Track which location is active

  // 🏠 SAVED LOCATIONS
  List<Map<String, dynamic>> _savedLocations = [];
  final List<String> _locationCategories = [
    'Home',
    'Office',
    'Hotel',
    'Gym',
    'Other',
  ];
  String _selectedCategory = 'Home';
  String _filterCategory = 'All'; // For filtering saved locations

  // 📝 EDIT STATE
  String? _editingLocationId;
  late TextEditingController _editNameController;

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

  // UI STATE MANAGEMENT
  bool _isMapView = false;

  @override
  void initState() {
    super.initState();
    _editNameController = TextEditingController();
    _loadCurrentLocation();
    _loadSavedLocations();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _editNameController.dispose();
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
  // 🏠 LOAD SAVED LOCATIONS
  // ============================================

  Future<void> _loadSavedLocations() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final token = await user.getIdToken();
      if (!mounted) return;

      final headers = {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      };

      // Preferred route: backend-correct full saved locations list.
      final savedLocationsResponse = await http
          .get(
            Uri.parse(
              '$_backendUrl/api/driver/go-to-destination/saved-locations',
            ),
            headers: headers,
          )
          .timeout(_apiTimeout);

      if (savedLocationsResponse.statusCode == 200) {
        final data = jsonDecode(savedLocationsResponse.body);
        final locations = _parseLocationsArray(data['locations']);
        _applyLocations(locations);
        return;
      }

      // Legacy fallback path used by some builds.
      if (savedLocationsResponse.statusCode == 404) {
        final legacyResponse = await http
            .get(
              Uri.parse('$_backendUrl/api/driver/go-to-destination/locations'),
              headers: headers,
            )
            .timeout(_apiTimeout);

        if (legacyResponse.statusCode == 200) {
          final data = jsonDecode(legacyResponse.body);
          final locations = _parseLocationsArray(data['locations']);
          _applyLocations(locations);
          return;
        }

        debugPrint(
          'Saved-locations endpoint missing, trying status fallback...',
        );

        final statusResponse = await http
            .get(
              Uri.parse('$_backendUrl/api/driver/go-to-destination/status'),
              headers: headers,
            )
            .timeout(_apiTimeout);

        if (statusResponse.statusCode == 200) {
          final data = jsonDecode(statusResponse.body);
          final fallbackLocations = _parseLocationFromStatus(data);
          _applyLocations(fallbackLocations);
          return;
        }

        debugPrint(
          'Status fallback failed: ${statusResponse.statusCode} ${statusResponse.body}',
        );
      } else {
        debugPrint(
          'Failed to load saved locations: ${savedLocationsResponse.statusCode} ${savedLocationsResponse.body}',
        );
      }
    } catch (e) {
      debugPrint('Error loading saved locations: $e');
    }
  }

  void _applyLocations(List<Map<String, dynamic>> locations) {
    if (!mounted) return;

    setState(() {
      _savedLocations = locations;
      _activeLocationId = null;
      _isDestinationEnabled = false;

      for (final loc in _savedLocations) {
        if (loc['isActive'] == true) {
          _activeLocationId = loc['id']?.toString();
          _isDestinationEnabled = true;
          break;
        }
      }
    });
  }

  List<Map<String, dynamic>> _parseLocationsArray(dynamic rawLocations) {
    if (rawLocations is! List) return [];

    return rawLocations
        .map<Map<String, dynamic>>((loc) {
          if (loc is! Map) return <String, dynamic>{};

          final map = Map<String, dynamic>.from(loc);
          return {
            'id':
                (map['_id'] ??
                        map['id'] ??
                        map['locationId'] ??
                        DateTime.now().millisecondsSinceEpoch)
                    .toString(),
            'name': (map['name'] ?? 'Saved destination').toString(),
            'category': (map['category'] ?? 'Other').toString(),
            'lat': _toDoubleSafe(map['lat']),
            'lng': _toDoubleSafe(map['lng']),
            'address': (map['address'] ?? map['formattedAddress'] ?? '')
                .toString(),
            'isActive': map['isActive'] == true,
          };
        })
        .where((loc) => loc['lat'] != null && loc['lng'] != null)
        .toList();
  }

  List<Map<String, dynamic>> _parseLocationFromStatus(dynamic rawData) {
    if (rawData is! Map) return [];

    final data = Map<String, dynamic>.from(rawData);
    final bool enabled =
        data['enabled'] == true ||
        data['isActive'] == true ||
        data['goToEnabled'] == true;

    final dynamic nested =
        data['destination'] ?? data['location'] ?? data['goToDestination'];
    final map = nested is Map
        ? Map<String, dynamic>.from(nested)
        : <String, dynamic>{};

    final lat = _toDoubleSafe(map['lat'] ?? data['lat']);
    final lng = _toDoubleSafe(map['lng'] ?? data['lng']);

    if (!enabled || lat == null || lng == null) {
      return [];
    }

    return [
      {
        'id': (map['_id'] ?? map['id'] ?? data['locationId'] ?? 'active_go_to')
            .toString(),
        'name': (map['name'] ?? data['name'] ?? 'Saved destination').toString(),
        'category': (map['category'] ?? data['category'] ?? 'Other').toString(),
        'lat': lat,
        'lng': lng,
        'address': (map['address'] ?? data['address'] ?? '').toString(),
        'isActive': true,
      },
    ];
  }

  double? _toDoubleSafe(dynamic value) {
    if (value == null) return null;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
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
  // 🧡 SAVE GO TO DESTINATION LOCATION
  // ============================================

  Future<void> _enableGoToDestination() async {
    if (_selectedLat == null || _selectedLng == null) {
      _showSnackBar('Please select a destination', Colors.orange);
      return;
    }

    setState(() => _isLoading = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception("User not authenticated");

      final token = await user.getIdToken();
      if (!mounted) return;

      if (token == null || token.isEmpty) {
        throw Exception("Failed to get authentication token");
      }

      final headers = {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      };

      // Save location with category (DO NOT auto-activate)
      final response = await http
          .post(
            Uri.parse('$_backendUrl/api/driver/go-to-destination/save'),
            headers: headers,
            body: jsonEncode({
              'name': _selectedPlaceName ?? 'Location',
              'category': _selectedCategory,
              'lat': _selectedLat,
              'lng': _selectedLng,
              'address': _selectedPlaceName,
              'isActive': false,
            }),
          )
          .timeout(_apiTimeout);

      if (response.statusCode == 200) {
        setState(() {
          _isMapView = false;
          _searchController.clear();
          _selectedDestination = null;
          _selectedLat = null;
          _selectedLng = null;
          _selectedPlaceName = null;
          _markers.clear();
          _selectedCategory = 'Home'; // Reset to default
        });

        // Reload saved locations
        await _loadSavedLocations();

        if (mounted) {
          _showSnackBar('✅ Destination saved', Colors.green);
        }
      } else {
        throw Exception("Failed (${response.statusCode}): ${response.body}");
      }
    } catch (e) {
      debugPrint('Error saving destination: $e');
      String errorMessage = 'Failed to save location';
      if (e is Exception) {
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
  // 🔄 TOGGLE LOCATION ACTIVE/INACTIVE
  // ============================================

  Future<void> _toggleLocationActive(String locationId, bool activate) async {
    setState(() => _isLoading = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception("User not authenticated");

      final token = await user.getIdToken();
      if (!mounted) return;

      final headers = {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      };

      // If activating, deactivate all others first
      if (activate) {
        for (var loc in _savedLocations) {
          if (loc['id'] != locationId && loc['isActive'] == true) {
            try {
              await http
                  .post(
                    Uri.parse(
                      '$_backendUrl/api/driver/go-to-destination/toggle/${loc['id']}',
                    ),
                    headers: headers,
                    body: jsonEncode({'isActive': false}),
                  )
                  .timeout(_apiTimeout);
            } catch (e) {
              debugPrint('Error deactivating other location: $e');
            }
          }
        }
      }

      // Toggle the selected location
      final response = await http
          .post(
            Uri.parse(
              '$_backendUrl/api/driver/go-to-destination/toggle/$locationId',
            ),
            headers: headers,
            body: jsonEncode({'isActive': activate}),
          )
          .timeout(_apiTimeout);

      if (response.statusCode == 200) {
        await _loadSavedLocations();
        if (mounted) {
          _showSnackBar(
            activate ? '✅ Destination activated' : '✅ Destination deactivated',
            Colors.green,
          );
        }
      } else {
        throw Exception("Failed to toggle");
      }
    } catch (e) {
      debugPrint('Error toggling location: $e');
      _showSnackBar('Failed to update location', Colors.red);
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // ============================================
  // 🗑️ DELETE SAVED LOCATION
  // ============================================

  Future<void> _deleteLocation(String locationId) async {
    setState(() => _isLoading = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception("User not authenticated");

      final token = await user.getIdToken();
      if (!mounted) return;

      final headers = {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      };

      final response = await http
          .delete(
            Uri.parse(
              '$_backendUrl/api/driver/go-to-destination/location/$locationId',
            ),
            headers: headers,
          )
          .timeout(_apiTimeout);

      if (response.statusCode == 200) {
        await _loadSavedLocations();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ Location deleted'),
              backgroundColor: Color(0xFFEF4444),
              duration: Duration(seconds: 2),
            ),
          );
        }
      } else {
        throw Exception("Failed to delete");
      }
    } catch (e) {
      debugPrint('Error deleting location: $e');
      _showSnackBar('Failed to delete location', Colors.red);
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // ============================================
  // 🏠 GET ICON FOR CATEGORY
  // ============================================

  IconData _getIconForCategory(String category) {
    switch (category.toLowerCase()) {
      case 'home':
        return Icons.home_rounded;
      case 'office':
        return Icons.business_rounded;
      case 'hotel':
        return Icons.hotel_rounded;
      case 'gym':
        return Icons.fitness_center_rounded;
      default:
        return Icons.location_on_rounded;
    }
  }

  Color _getColorForCategory(String category) {
    switch (category.toLowerCase()) {
      case 'home':
        return const Color(0xFFFF7A00);
      case 'office':
        return const Color(0xFF3B82F6);
      case 'hotel':
        return const Color(0xFFA855F7);
      case 'gym':
        return const Color(0xFFEC4899);
      default:
        return const Color(0xFF6B7280);
    }
  }

  // ============================================
  // ✏️ UPDATE LOCATION NAME
  // ============================================

  Future<void> _updateLocationName(String locationId, String newName) async {
    if (newName.isEmpty) return;

    setState(() => _isLoading = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception("User not authenticated");

      final token = await user.getIdToken();
      if (!mounted) return;

      final headers = {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      };

      // Update location name via backend
      final response = await http
          .put(
            Uri.parse(
              '$_backendUrl/api/driver/go-to-destination/location/$locationId',
            ),
            headers: headers,
            body: jsonEncode({'name': newName}),
          )
          .timeout(_apiTimeout);

      if (response.statusCode == 200) {
        // Update local state
        setState(() {
          final index = _savedLocations.indexWhere(
            (loc) => loc['id'] == locationId,
          );
          if (index != -1) {
            _savedLocations[index]['name'] = newName;
          }
          _editingLocationId = null;
        });

        _showSnackBar('✅ Location updated', Colors.green);
      } else {
        throw Exception("Failed to update");
      }
    } catch (e) {
      debugPrint('Error updating location: $e');
      _showSnackBar('Failed to update location', Colors.red);
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // ============================================
  // HELPER: SHOW SNACKBAR
  // ============================================

  bool _isHardErrorMessage(String message) {
    final m = message.toLowerCase();
    return m.contains('error') ||
        m.contains('failed') ||
        m.contains('denied') ||
        m.contains('network') ||
        m.contains('session') ||
        m.contains('authentication') ||
        m.contains('cannot') ||
        m.contains('unable');
  }

  void _showSnackBar(String message, Color color) {
    final isError = color == Colors.red;

    if (isError) {
      final isHardError = _isHardErrorMessage(message);
      if (!isHardError) return;
    }

    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.fromLTRB(14, 0, 14, 14),
          duration: const Duration(seconds: 3),
          content: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: isError
                  ? const Color(0xFFFEF2F2)
                  : const Color(0xFFF0FDF4),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isError
                    ? const Color(0xFFFCA5A5)
                    : const Color(0xFBBBF7),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.08),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  isError
                      ? Icons.error_outline_rounded
                      : Icons.check_circle_rounded,
                  color: isError
                      ? const Color(0xFFB42318)
                      : const Color(0xFF059669),
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isError ? 'Action Failed' : 'Success',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: isError
                              ? const Color(0xFFB42318)
                              : const Color(0xFF059669),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        message,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: isError
                              ? const Color(0xFF7A271A)
                              : const Color(0xFF065F46),
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

  // ============================================
  // BUILD UI
  // ============================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: const Color(0xFFF8F9FB),
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Go To Destination',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
            ),
            const SizedBox(height: 2),
            Text(
              'Get trips towards your destination',
              style: TextStyle(
                fontWeight: FontWeight.w400,
                fontSize: 12,
                color: Colors.grey.shade600,
              ),
            ),
          ],
        ),
        centerTitle: false,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: Colors.grey.shade200),
        ),
        actions: [
          if (_isDestinationEnabled && !_isMapView)
            Container(
              margin: const EdgeInsets.only(right: 16, top: 8, bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFF22C55E),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.white, size: 16),
                  SizedBox(width: 4),
                  Text(
                    'ACTIVE',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 400),
        transitionBuilder: (child, animation) =>
            FadeTransition(opacity: animation, child: child),
        child: _isMapView ? _buildMapUI() : _buildSavedLocationsOverviewUI(),
      ),
    );
  }

  // ============================================
  // 📍 GET FILTERED LOCATIONS
  // ============================================

  List<Map<String, dynamic>> _getFilteredLocations() {
    if (_filterCategory == 'All') {
      return _savedLocations;
    }
    return _savedLocations
        .where(
          (loc) =>
              (loc['category'] ?? '').toString().toLowerCase() ==
              _filterCategory.toLowerCase(),
        )
        .toList();
  }

  // ============================================
  // 📍 SAVED LOCATIONS OVERVIEW UI (GRID)
  // ============================================

  Widget _buildSavedLocationsOverviewUI() {
    final filteredLocations = _getFilteredLocations();

    return SafeArea(
      key: const ValueKey('savedLocationsOverview'),
      child: Column(
        children: [
          Expanded(
            child: filteredLocations.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(28),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                const Color(0xFFFF7A00).withOpacity(0.15),
                                const Color(0xFFFF9C40).withOpacity(0.1),
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(24),
                          ),
                          child: const Icon(
                            Icons.location_on_rounded,
                            size: 64,
                            color: Color(0xFFFF7A00),
                          ),
                        ),
                        const SizedBox(height: 28),
                        const Text(
                          'No Saved Destinations',
                          style: TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w700,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 32),
                          child: Text(
                            _filterCategory == 'All'
                                ? 'Save your frequently visited places for quick access'
                                : 'No $_filterCategory locations saved yet',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 15,
                              color: Colors.grey.shade600,
                              fontWeight: FontWeight.w400,
                              height: 1.6,
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                    children: [
                      // HEADER & FILTER SECTION
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Your Destinations',
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                              color: Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 16),
                          // CATEGORY FILTER TABS
                          SizedBox(
                            height: 48,
                            child: ListView(
                              physics: const BouncingScrollPhysics(),
                              scrollDirection: Axis.horizontal,
                              children: [
                                _buildFilterTab('All', Icons.layers_rounded),
                                _buildFilterTab('Home', Icons.home_rounded),
                                _buildFilterTab(
                                  'Office',
                                  Icons.business_rounded,
                                ),
                                _buildFilterTab('Hotel', Icons.hotel_rounded),
                                _buildFilterTab(
                                  'Gym',
                                  Icons.fitness_center_rounded,
                                ),
                                _buildFilterTab(
                                  'Other',
                                  Icons.location_on_rounded,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 20),
                        ],
                      ),
                      // LOCATIONS GRID
                      GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2,
                              childAspectRatio: 0.9,
                              crossAxisSpacing: 12,
                              mainAxisSpacing: 12,
                            ),
                        itemCount: filteredLocations.length,
                        itemBuilder: (context, index) {
                          final location = filteredLocations[index];
                          final isActive = location['id'] == _activeLocationId;
                          return _buildDestinationCard(location, isActive);
                        },
                      ),
                    ],
                  ),
          ),

          // ➕ ADD BUTTON
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            child: SizedBox(
              width: double.infinity,
              height: 56,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFFF7A00), Color(0xFFFF9C40)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFFF7A00).withOpacity(0.3),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => setState(() => _isMapView = true),
                    borderRadius: BorderRadius.circular(16),
                    splashColor: Colors.white.withOpacity(0.2),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.add_location_rounded,
                          color: Colors.white,
                          size: 24,
                        ),
                        const SizedBox(width: 12),
                        const Text(
                          'Add New Destination',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================
  //  ️ BUILD FILTER TAB
  // ============================================

  Widget _buildFilterTab(String category, IconData icon) {
    final isSelected = _filterCategory == category;
    final categoryColor = category == 'All'
        ? Colors.grey.shade400
        : _getColorForCategory(category);

    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: GestureDetector(
        onTap: () => setState(() => _filterCategory = category),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            gradient: isSelected
                ? LinearGradient(
                    colors: [categoryColor, categoryColor.withOpacity(0.8)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  )
                : LinearGradient(
                    colors: [Colors.grey.shade100, Colors.grey.shade100],
                  ),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? Colors.transparent : Colors.grey.shade300,
              width: 1.5,
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: categoryColor.withOpacity(0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : [],
          ),
          child: Row(
            children: [
              Icon(
                icon,
                color: isSelected ? Colors.white : categoryColor,
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                category,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: isSelected ? Colors.white : Colors.black87,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ============================================
  //  🎴 DESTINATION CARD (GRID)
  // ============================================

  Widget _buildDestinationCard(Map<String, dynamic> location, bool isActive) {
    final category = location['category'] ?? 'Other';
    final icon = _getIconForCategory(category);
    final color = _getColorForCategory(category);

    return GestureDetector(
      onTap: _isLoading
          ? null
          : () => _toggleLocationActive(location['id'], !isActive),
      child: AnimatedScale(
        scale: isActive ? 1.0 : 0.95,
        duration: const Duration(milliseconds: 200),
        child: Container(
          decoration: BoxDecoration(
            color: isActive ? color.withOpacity(0.08) : Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: isActive ? color : Colors.grey.shade200,
              width: isActive ? 2.5 : 1.5,
            ),
            boxShadow: [
              if (isActive)
                BoxShadow(
                  color: color.withOpacity(0.25),
                  blurRadius: 16,
                  offset: const Offset(0, 8),
                )
              else
                BoxShadow(
                  color: Colors.black.withOpacity(0.08),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
            ],
          ),
          child: Stack(
            children: [
              Column(
                children: [
                  // HEADER WITH ICON & MENU
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: color.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(icon, color: color, size: 20),
                        ),
                        const Spacer(),
                        PopupMenuButton(
                          onSelected: (value) {
                            if (value == 'edit') {
                              _showEditModal(location);
                            } else if (value == 'delete') {
                              _deleteLocation(location['id']);
                            } else if (value == 'change_location') {
                              setState(() => _isMapView = true);
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(
                              Icons.more_vert,
                              size: 18,
                              color: Colors.grey.shade600,
                            ),
                          ),
                          itemBuilder: (context) => [
                            const PopupMenuItem(
                              value: 'edit',
                              child: Row(
                                children: [
                                  Icon(Icons.edit_rounded, size: 18),
                                  SizedBox(width: 12),
                                  Text('Edit Name'),
                                ],
                              ),
                            ),
                            const PopupMenuItem(
                              value: 'change_location',
                              child: Row(
                                children: [
                                  Icon(Icons.location_on_rounded, size: 18),
                                  SizedBox(width: 12),
                                  Text('Change Location'),
                                ],
                              ),
                            ),
                            const PopupMenuItem(
                              value: 'delete',
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.delete_rounded,
                                    size: 18,
                                    color: Colors.red,
                                  ),
                                  SizedBox(width: 12),
                                  Text(
                                    'Delete',
                                    style: TextStyle(color: Colors.red),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // CONTENT
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            location['name'] ?? 'Unnamed',
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: Colors.black87,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            location['address'] ?? 'No address',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey.shade600,
                              fontWeight: FontWeight.w400,
                              height: 1.3,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ),

                  // STATUS INDICATOR
                  if (isActive)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.15),
                        borderRadius: const BorderRadius.only(
                          bottomLeft: Radius.circular(16),
                          bottomRight: Radius.circular(16),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: color,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'ACTIVE',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: color,
                              letterSpacing: 0.5,
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

  // ============================================
  // ✏️ EDIT MODAL
  // ============================================

  void _showEditModal(Map<String, dynamic> location) {
    _editNameController.text = location['name'] ?? '';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return SingleChildScrollView(
          child: Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(24),
                topRight: Radius.circular(24),
              ),
            ),
            padding: EdgeInsets.fromLTRB(
              16,
              20,
              16,
              16 + MediaQuery.of(context).viewInsets.bottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // HEADER
                Row(
                  children: [
                    const Text(
                      'Edit Destination',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: Colors.black87,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // NAME INPUT
                const Text(
                  'Destination Name',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _editNameController,
                  decoration: InputDecoration(
                    hintText: 'Enter destination name',
                    hintStyle: TextStyle(color: Colors.grey.shade400),
                    prefixIcon: const Icon(
                      Icons.edit_rounded,
                      color: Color(0xFFFF7A00),
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                        color: Color(0xFFFF7A00),
                        width: 2,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // SAVE BUTTON
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: _isLoading
                        ? null
                        : () {
                            _updateLocationName(
                              location['id'],
                              _editNameController.text,
                            );
                            Navigator.pop(context);
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFF7A00),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text(
                            'Save Changes',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ============================================
  // 🗺️ MAP UI (DESTINATION SELECTION)
  // ============================================

  // ============================================
  // 🗺️ MAP UI (DESTINATION SELECTION)
  // ============================================

  Widget _buildMapUI() {
    return SafeArea(
      key: const ValueKey('mapView'),
      child: Column(
        children: [
          // 🔍 SEARCH SECTION - Limited Height for keyboard
          LimitedBox(
            maxHeight: 280,
            child: Container(
              color: Colors.white,
              padding: const EdgeInsets.only(bottom: 4),
              child: SingleChildScrollView(
                physics: const ClampingScrollPhysics(),
                child: Column(
                  children: [
                    // 📍 DESTINATION LABEL
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          '📍 Destination',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey.shade600,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ),
                    ),

                    // 🔍 SEARCH INPUT FIELD
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: _placeSuggestions.isNotEmpty
                                ? const Color(0xFFFF7A00)
                                : Colors.grey.shade200,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.04),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: TextField(
                          controller: _searchController,
                          enabled: true,
                          decoration: InputDecoration(
                            prefixIcon: Icon(
                              Icons.location_on_outlined,
                              color: Colors.grey.shade500,
                            ),
                            hintText: 'Where are you going?',
                            hintStyle: TextStyle(
                              color: Colors.grey.shade400,
                              fontWeight: FontWeight.w500,
                            ),
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 15,
                            ),
                            suffixIcon: _searchController.text.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.close, size: 20),
                                    color: Colors.grey.shade600,
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
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: Color(0xFFFF7A00),
                          ),
                        ),
                      ),

                    // 📍 SUGGESTIONS LIST - Smaller height
                    if (_placeSuggestions.isNotEmpty)
                      Container(
                        constraints: const BoxConstraints(maxHeight: 160),
                        margin: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.08),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: ListView.separated(
                          shrinkWrap: true,
                          physics: const BouncingScrollPhysics(),
                          itemCount: _placeSuggestions.length,
                          separatorBuilder: (context, index) => Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: Divider(
                              height: 1,
                              color: Colors.grey.shade100,
                            ),
                          ),
                          itemBuilder: (context, index) {
                            final place = _placeSuggestions[index];
                            final mainText =
                                place['structured_formatting']?['main_text'] ??
                                place['description'] ??
                                'Unknown';
                            final secondaryText =
                                place['structured_formatting']?['secondary_text'] ??
                                '';

                            return Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap: () => _selectPlace(place),
                                splashColor: const Color(
                                  0xFFFF7A00,
                                ).withOpacity(0.1),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 12,
                                  ),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: const Color(
                                            0xFFFF7A00,
                                          ).withOpacity(0.1),
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                        ),
                                        child: const Icon(
                                          Icons.location_on,
                                          color: Color(0xFFFF7A00),
                                          size: 18,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              mainText,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w600,
                                                fontSize: 14,
                                                color: Colors.black87,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            if (secondaryText.isNotEmpty) ...[
                                              const SizedBox(height: 3),
                                              Text(
                                                secondaryText,
                                                style: TextStyle(
                                                  color: Colors.grey.shade500,
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w400,
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),

                    // Empty state
                    if (_placeSuggestions.isEmpty &&
                        !_isSearching &&
                        _searchController.text.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        child: Column(
                          children: [
                            Icon(
                              Icons.search_rounded,
                              size: 32,
                              color: Colors.grey.shade300,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Search for a destination',
                              style: TextStyle(
                                color: Colors.grey.shade400,
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),

          // 🗺️ MAP
          Expanded(
            child: _currentLocation == null
                ? const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(color: Color(0xFFFF7A00)),
                        SizedBox(height: 16),
                        Text(
                          'Getting your location...',
                          style: TextStyle(fontSize: 15),
                        ),
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
                        onTap: _selectDestinationOnMap,
                        onMapCreated: (controller) {
                          _mapController = controller;
                        },
                        mapToolbarEnabled: false,
                        zoomControlsEnabled: false,
                      ),

                      // 🎨 GRADIENT OVERLAY
                      Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        child: Container(
                          height: 80,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.black.withOpacity(0.3),
                                Colors.transparent,
                              ],
                            ),
                          ),
                        ),
                      ),

                      // ℹ️ GLASSMORPHISM HELP TEXT
                      Positioned(
                        top: 12,
                        left: 12,
                        right: 12,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: Colors.white.withOpacity(0.3),
                                ),
                              ),
                              child: const Row(
                                children: [
                                  Icon(
                                    Icons.touch_app,
                                    color: Colors.white,
                                    size: 20,
                                  ),
                                  SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'Search or tap map to select',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
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
                          elevation: 6,
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
                            size: 22,
                          ),
                        ),
                      ),
                    ],
                  ),
          ),

          // ✅ MAP BOTTOM CARD
          _buildMapBottomCard(),
        ],
      ),
    );
  }

  // ============================================
  // 📍 MAP BOTTOM CARD
  // ============================================

  Widget _buildMapBottomCard() {
    return SafeArea(
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(24),
            topRight: Radius.circular(24),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.12),
              blurRadius: 20,
              offset: const Offset(0, -8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 🔹 DRAG HANDLE
            Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 16),
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // 📍 CATEGORY SELECTION
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Save As',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 40,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: _locationCategories.length,
                      itemBuilder: (context, index) {
                        final category = _locationCategories[index];
                        final isSelected = _selectedCategory == category;
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: GestureDetector(
                            onTap: () {
                              setState(() => _selectedCategory = category);
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? const Color(0xFFFF7A00)
                                    : Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: isSelected
                                      ? const Color(0xFFFF7A00)
                                      : Colors.grey.shade300,
                                ),
                              ),
                              child: Text(
                                category,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: isSelected
                                      ? Colors.white
                                      : Colors.grey.shade700,
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),

            // ℹ️ SELECTED LOCATION INFO
            if (_selectedDestination != null)
              Container(
                padding: const EdgeInsets.all(14),
                margin: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF5E6),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFFFD699)),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFFF7A00).withOpacity(0.08),
                      blurRadius: 8,
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF7A00).withOpacity(0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.favorite_outline,
                        color: Color(0xFFFF7A00),
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _selectedCategory,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                              color: Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            _selectedPlaceName ?? 'Selected Location',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade600,
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Tap Save to add this location 📍',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.black54,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Column(
                  children: [
                    Icon(
                      Icons.info_outline_rounded,
                      color: Colors.grey.shade400,
                      size: 28,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Select destination from search or tap map',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade600,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),

            // SAVE BUTTON
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              height: 56,
              decoration: BoxDecoration(
                gradient: _selectedDestination != null
                    ? const LinearGradient(
                        colors: [Color(0xFFFF7A00), Color(0xFFFF9C40)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      )
                    : LinearGradient(
                        colors: [Colors.grey.shade400, Colors.grey.shade500],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: _selectedDestination != null
                    ? [
                        BoxShadow(
                          color: const Color(0xFFFF7A00).withOpacity(0.3),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ]
                    : [],
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: _selectedDestination == null || _isLoading
                      ? null
                      : _enableGoToDestination,
                  borderRadius: BorderRadius.circular(16),
                  splashColor: Colors.white.withOpacity(0.3),
                  child: Center(
                    child: _isLoading
                        ? const SizedBox(
                            height: 22,
                            width: 22,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2.5,
                            ),
                          )
                        : Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                _selectedDestination != null
                                    ? Icons.save_rounded
                                    : Icons.location_on_outlined,
                                color: Colors.white,
                                size: 22,
                              ),
                              const SizedBox(width: 10),
                              Text(
                                _selectedDestination == null
                                    ? 'Select Destination'
                                    : 'Save Location',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                  letterSpacing: 0.3,
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
              ),
            ),

            // BACK BUTTON
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: SizedBox(
                width: double.infinity,
                height: 44,
                child: TextButton(
                  onPressed: () => setState(() => _isMapView = false),
                  child: Text(
                    'Cancel',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
