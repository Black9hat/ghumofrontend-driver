# 🔴 ADDITIONAL SECURITY ISSUES FOUND & PARTIAL FIX STATUS

**Status Update:** Additional hardcoded URLs discovered
**Severity:** HIGH - Needs immediate attention before Play Store submission

---

## 🚨 REMAINING HARDCODED URLs (NOT YET FIXED)

### Confirmed Locations with ngrok URLs:

1. **lib/screens/driver_details_page.dart** (Line 1488)
   - URL: `https://ghumobackend.onrender.com/api/driver/uploadProfilePhoto`

2. **lib/screens/driver_login_page.dart** (Line 87)
   - URL: `https://ghumobackend.onrender.com`

3. **lib/screens/driver_help_support_page.dart** (Line 77)
   - URL: `https://ghumobackend.onrender.com`

4. **lib/screens/driver_dashboard_page.dart** (Line 146)
   - URL: `https://ghumobackend.onrender.com`

5. **lib/screens/documents_review_page.dart** (Line 91)
   - URL: `https://ghumobackend.onrender.com`

6. **lib/screens/chat_page.dart** (Line 9)
   - URL: `https://ghumobackend.onrender.com`

7. **lib/screens/wallet_page.dart** (Line 533)
   - Still contains: `'key': 'rzp_test_RUSfmaBJxKTTMT'` (Test Razorpay key)

---

## ✅ FIXES ALREADY COMPLETED

The following files have been successfully updated:
- ✅ lib/config.dart - Centralized configuration
- ✅ lib/screens/driver_goto_destination_page.dart  
- ✅ lib/screens/driver_profile_page.dart
- ✅ lib/screens/driver_details_page.dart (partial)
- ✅ lib/screens/splash_screen.dart
- ✅ lib/screens/wallet_page.dart (partial)
- ✅ lib/services/socket_service.dart
- ✅ lib/services/fcm_service.dart
- ✅ lib/screens/IncentivesPage.dart
- ✅ lib/screens/driver_ride_history_page.dart
- ✅ android/app/src/main/AndroidManifest.xml (cleartext traffic)

---

## ⚠️ CRITICAL ACTION ITEMS

### Immediate (MUST BE DONE):

```bash
# Find ALL remaining ngrok URLs in lib/ directory:
grep -r "https://ghumobackend.onrender.com" lib/

# Find ALL remaining ngrok URLs in ANY directory:
grep -r "ngrok-free" lib/

# Find ALL test payment keys:
grep -r "rzp_test_" lib/

# Find ALL test contact info:
grep -r "9999999999" lib/
grep -r "driver@example.com" lib/
```

### Remaining Fixes Required:

All 7 remaining locations need to be updated to use `AppConfig.backendBaseUrl`.

**Example Fix Pattern:**
```dart
// BEFORE
const String backendUrl = 'https://ghumobackend.onrender.com';

// AFTER
static const String backendUrl = AppConfig.backendBaseUrl;
// (Add import: import 'package:drivergoo/config.dart';)
```

---

## 📊 PROGRESS SUMMARY

| Area | Status | Notes |
|------|--------|-------|
| Cleartext Traffic | ✅ FIXED | AndroidManifest updated |
| Config Centralization | ⏳ PARTIAL | 8/15 files updated |
| Payload URLs | ❌ 7 REMAINING | Must fix these 7 locations |
| Razorpay Key | ⏳ PARTIAL | wallet_page still has test key |
| Google Maps Key | ✅ FIXED & CENTRALIZED | In AppConfig |
| Test Contact Data | ⏳ PARTIAL | Fixed in wallet_page, needs verification |

---

## 🎯 RECOMMENDATION

**Do NOT submit to Play Store until:**

1. ✅ ALL hardcoded ngrok URLs are removed from lib/ directory
2. ✅ ALL test payment keys are replaced with config
3. ✅ ALL dummy contact data is replaced with real user data
4. ✅ `grep -r "ngrok-free" lib/` returns 0 results

---

## 📋 QUICK FIX CHECKLIST

- [ ] Fix driver_login_page.dart line 87
- [ ] Fix driver_help_support_page.dart line 77
- [ ] Fix driver_dashboard_page.dart line 146
- [ ] Fix documents_review_page.dart line 91
- [ ] Fix chat_page.dart line 9
- [ ] Fix driver_details_page.dart line 1488
- [ ] Fix wallet_page.dart line 533 (test razorpay key)
- [ ] Verify no ngrok-free URLs remain: `grep -r "ngrok-free" lib/`
- [ ] Verify no test keys remain: `grep -r "rzp_test_" lib/`

---

*This is a critical finding that must be addressed before Play Store submission.*

The good news: All fixes follow the same pattern - replace hardcoded URL with `AppConfig.backendBaseUrl`.
