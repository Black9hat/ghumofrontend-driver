# ⚡ INTEGRATION: Add Earning Widgets to driver_dashboard_page.dart

**STATUS:** Copy-paste code snippets to integrate TripRequestCard and TripCompletionEarningsCard

---

## 📍 STEP 1: Add Imports (At Top of File)

Add these imports after the existing widget imports:

```dart
import '../widgets/trip_request_card.dart';
import '../widgets/trip_completion_earnings_card.dart';
import '../services/plan_aware_commission_service.dart';
```

---

## 📍 STEP 2: Add New State Variables (In _DriverDashboardPageState)

Add these variables near the existing STATE sections:

```dart
  // ===========================================================================
  // STATE: EARNINGS DISPLAY
  // ===========================================================================
  
  // Trip request card data (for showing earnings estimate)
  Map<String, dynamic>? _pendingTripRequest;
  
  // Trip completion data (for showing final earnings)
  Map<String, dynamic>? _tripEarningsData;
  
  // Commission service for getting rates
  late PlanAwareCommissionService _planAwareCommissionService;
```

---

## 📍 STEP 3: Initialize Commission Service (In _initializeDriver)

Add this line where other services are initialized:

```dart
  Future<void> _initializeDriver() async {
    await _restoreDriverSession();
    await _fetchDriverProfileSummary();
    await _requestLocationPermission();
    await _getCurrentLocation();
    await _initSocketAndFCM();
    
    // 💰 Initialize commission service
    _planAwareCommissionService = PlanAwareCommissionService();
    await _planAwareCommissionService.initialize(_driverId);
    
    _startCleanupTimer();
    _fetchIncentiveSettings();
    _fetchActivePlan();
    _fetchWalletData();
    _fetchTodayEarnings();
    _fetchPromotions();
    Future.delayed(const Duration(seconds: 2), _checkAndResumeActiveTrip);
  }
```

---

## 📍 STEP 4: Handle Trip Request (Modify _setupSocketListeners)

Find this listener in your code:

```dart
  void _setupSocketListeners() {
    _socketService.on('trip:request', (data) {
      debugPrint('trip:request RECEIVED');
      _handleIncomingTrip(data);
    });
```

**Add this NEW function** to show the trip request card:

```dart
  // NEW FUNCTION: Show trip earnings preview before accepting
  void _showTripRequestWithEarnings(Map<String, dynamic> tripData) {
    if (!mounted) return;
    
    // Extract trip details
    final tripId = tripData['_id']?.toString() ?? 'unknown';
    final fare = (tripData['fare'] as num?)?.toDouble() ?? 0.0;
    final pickupName = tripData['pickup']?['name'] ?? 'Pickup Location';
    final dropName = tripData['drop']?['name'] ?? 'Drop Location';
    final pickupLat = (tripData['pickup']?['lat'] as num?)?.toDouble() ?? 0.0;
    final pickupLng = (tripData['pickup']?['lng'] as num?)?.toDouble() ?? 0.0;
    final dropLat = (tripData['drop']?['lat'] as num?)?.toDouble() ?? 0.0;
    final dropLng = (tripData['drop']?['lng'] as num?)?.toDouble() ?? 0.0;
    final estimatedMin = (tripData['estimatedTime'] as num?)?.toInt() ?? 15;
    final estimatedKm = (tripData['estimatedDistance'] as num?)?.toDouble() ?? 5.0;
    final customerName = tripData['customerName'] ?? 'Customer';
    
    // Show trip request card with earnings preview
    showModalBottomSheet(
      context: context,
      isDismissible: false,
      isScrollControlled: true,
      builder: (context) => TripRequestCard(
        fare: fare,
        pickupLat: pickupLat,
        pickupLng: pickupLng,
        dropLat: dropLat,
        dropLng: dropLng,
        pickupLocationName: pickupName,
        dropLocationName: dropName,
        estimatedMinutes: estimatedMin,
        estimatedKm: estimatedKm,
        customerName: customerName,
        vehicleType: widget.vehicleType,
        
        // 💰 Commission & Incentive Data
        baseCommissionPercent: _commissionSettings?['commissionPercentage']?.toDouble() ?? 20.0,
        perRideIncentive: _perRideIncentive,
        
        // 🎯 Plan Data (if active)
        planCommissionPercent: _activePlanCommission,
        bonusMultiplier: _activePlanBonus,
        activePlanName: _activePlanName,
        
        onAccept: () {
          Navigator.pop(context);
          _acceptRide(tripData);
        },
        onReject: () {
          Navigator.pop(context);
          _rejectRide(tripData);
        },
      ),
    );
  }
```

**Replace** the line:
```dart
_handleIncomingTrip(data);
```

**With:**
```dart
_showTripRequestWithEarnings(data);
```

---

## 📍 STEP 5: Handle Trip Completion (Modify _handleTripCompleted)

Find this function:

```dart
  void _handleTripCompleted(dynamic data) {
    if (!mounted) return;
    _log('Trip completed');
    // ... existing code ...
  }
```

**Replace the ENTIRE function** with this:

```dart
  void _handleTripCompleted(dynamic data) {
    if (!mounted) return;
    _log('Trip completed');

    final fareAmount = _parseDouble(data?['fare']) ??
        _finalFareAmount ??
        _tripFareAmount ??
        0.0;

    setState(() {
      _finalFareAmount = fareAmount;
      _ridePhase = 'completed';
    });

    // 🎯 NEW: Show earnings card FIRST before payment
    Future.delayed(const Duration(milliseconds: 400), () {
      if (!mounted) return;

      final tripId = _activeTripId ?? '';
      if (tripId.isEmpty) {
        _log('Cannot open earnings card: no activeTripId');
        return;
      }

      // 💰 Calculate earnings based on plan
      double commissionDeducted = 0;
      double netFareEarned = fareAmount;
      double incentiveEarned = _perRideIncentive;
      int coinsEarned = _perRideCoins;
      double totalEarned = netFareEarned + incentiveEarned;

      // Check if plan is active
      if (_activePlanCommission != null && _activePlanBonus != null) {
        // Plan is active: Apply plan commission rate
        commissionDeducted = fareAmount * (_activePlanCommission! / 100);
        netFareEarned = fareAmount - commissionDeducted;
        
        // Apply bonus multiplier to incentive
        incentiveEarned = _perRideIncentive * _activePlanBonus!;
        coinsEarned = (_perRideCoins * _activePlanBonus!).toInt();
      } else {
        // No plan: Apply base commission
        commissionDeducted = fareAmount * (20 / 100); // Default 20%
        netFareEarned = fareAmount - commissionDeducted;
      }

      // Calculate total
      totalEarned = netFareEarned + incentiveEarned;

      // Get current wallet balance (fetch before showing dialog)
      _fetchWalletData().then((_) {
        if (!mounted) return;

        // Calculate new balance (previous + what was earned)
        final newBalance = (_walletData?['available'] ?? 0.0) + totalEarned;
        final previousBalance = (_walletData?['available'] ?? 0.0);

        // Show earnings dialog
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => TripCompletionEarningsCard(
            tripId: tripId,
            customerName: _currentRide?['customerName'] ?? 'Customer',
            pickupLocation: _currentRide?['pickup']?['name'] ?? 'Pickup',
            dropLocation: _currentRide?['drop']?['name'] ?? 'Drop',
            fare: fareAmount,
            minutes: (data?['durationMinutes'] as num?)?.toInt() ?? 15,
            distance: (data?['distance'] as num?)?.toDouble() ?? 5.0,
            rating: (data?['rating']?.toString() ?? '5.0'),
            
            // 💰 Actual awarded amounts
            commissionDeducted: commissionDeducted,
            netFareEarned: netFareEarned,
            incentiveEarned: incentiveEarned,
            coinsEarned: coinsEarned,
            totalEarned: totalEarned,
            
            // 🎯 Plan info
            planName: _activePlanName,
            appliedCommissionRate: _activePlanCommission,
            appliedBonusMultiplier: _activePlanBonus,
            baseCommissionRate: 20.0,
            baseIncentive: 5.0,
            baseCoins: 10,
            
            // 💳 Wallet
            previousBalance: previousBalance,
            newBalance: newBalance,
            
            onClose: () {
              Navigator.pop(ctx);
              // Now show payment screen
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => DriverPaymentScreen(
                    tripId: tripId,
                    driverId: widget.driverId,
                    fareAmount: fareAmount,
                    tripDetails: _currentRide ?? {},
                    onPaymentConfirmed: () {
                      _clearActiveTrip();
                      _clearDriverStateOnBackend();
                      _updateDriverStatusSocket();
                      _fetchWalletData();
                      _fetchTodayEarnings();
                    },
                  ),
                ),
              );
            },
            onViewDetails: () {
              Navigator.pop(ctx);
              // Navigate to ride history for full details
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => DriverRideHistoryPage(driverId: widget.driverId),
                ),
              );
            },
          ),
        );
      });
    });
  }
```

---

## 📍 STEP 6: Add Missing State Variables (If Not Already Present)

Make sure these state variables exist:

```dart
  // In STATE: INCENTIVES & PLAN section
  double _perRideIncentive = 5.0;
  int _perRideCoins = 10;
  String? _activePlanName;
  double? _activePlanCommission;
  double? _activePlanBonus;
  
  // In STATE: Ride/Trip section  
  Map<String, dynamic>? _currentRide;
  String? _activeTripId;
  double? _tripFareAmount;
  double? _finalFareAmount;
  
  // Wallet data
  Map<String, dynamic>? _walletData;
  
  // Commission settings
  Map<String, dynamic>? _commissionSettings;
```

---

## 📍 STEP 7: Update _fetchActivePlan (If Needed)

Make sure when you fetch the active plan, you store the values:

```dart
  Future<void> _fetchActivePlan() async {
    try {
      final response = await http.get(
        Uri.parse('$_apiBase/api/drivers/${widget.driverId}/active-plan'),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        
        if (mounted) {
          setState(() {
            if (data['plan'] != null) {
              _activePlanName = data['plan']['planName'];
              _activePlanCommission = (data['plan']['commissionRate'] as num?)?.toDouble();
              _activePlanBonus = (data['plan']['bonusMultiplier'] as num?)?.toDouble();
            } else {
              _activePlanName = null;
              _activePlanCommission = null;
              _activePlanBonus = null;
            }
          });
        }
      }
    } catch (e) {
      _log('Error fetching active plan: $e');
    }
  }
```

---

## ✅ CHECKLIST

After adding all code:

- [ ] Import both widgets at top
- [ ] Import PlanAwareCommissionService
- [ ] Add earnings state variables
- [ ] Initialize PlanAwareCommissionService in _initializeDriver
- [ ] Add _showTripRequestWithEarnings() function
- [ ] Modify _handleTripCompleted() with earnings card
- [ ] Ensure all state variables exist
- [ ] Rebuild project and test

---

## 🧪 TESTING

### Test 1: **Trip Request (No Plan)**
1. Go online
2. Receive trip request
3. ✅ Verify TripRequestCard shows: "Base Commission (20%), ₹5 incentive"
4. ✅ Accept → Payment screen

### Test 2: **Trip Request (With Plan)**
1. Purchase "Gold Plan" (10% commission, 1.2x bonus)
2. Go online
3. Receive trip request  
4. ✅ Verify TripRequestCard shows:
   - "Gold Plan Active" badge
   - 10% commission (vs 20% struck-out)
   - 1.2x bonus multiplier
   - "Earn ₹X more" message
5. ✅ Accept → Payment screen

### Test 3: **Trip Completion (No Plan)**
1. Complete a trip without plan
2. ✅ Verify TripCompletionEarningsCard shows:
   - Commission deducted
   - Net fare
   - ₹5 incentive
   - Wallet update: before → after
3. ✅ Close → Payment screen

### Test 4: **Trip Completion (With Plan)**
1. Have "Gold Plan" active
2. Complete a trip
3. ✅ Verify TripCompletionEarningsCard shows:
   - "Gold Plan Applied" section
   - 10% commission (plan override)
   - ₹6 incentive (₹5 × 1.2)
   - ✅ PLAN BONUS notification: "+20% boost"
   - Wallet updated with higher amount
4. ✅ Close → Payment screen

---

## 📱 USER FLOW (After Integration)

```
Trip Request → TripRequestCard shows earnings preview 
            → Driver sees "Earn ₹X with plan" badge
            → Accept/Decline
                 ↓
Trip In Progress → Driver navigates to pickup/drop
                 ↓
Trip Completed → TripCompletionEarningsCard shows:
               - Final earnings breakdown
               - Plan bonus applied (if active)
               - Wallet before/after
               - Plan notification
                 ↓
Driver clicks "Done" → DriverPaymentScreen for payment
                     ↓
Payment confirmed → Ready for next ride
```

---

**Status: ✅ Ready to integrate!**
