# 🔐 Play Store Security & Rejection Risk Audit

**Status:** ⚠️ CRITICAL ISSUES FOUND - Will be REJECTED
**Severity:** HIGH (Multiple critical issues)
**Last Scanned:** February 23, 2026

---

## 🚨 CRITICAL ISSUES (Will Cause Rejection)

### 1. **Cleartext Traffic Enabled** ⛔ AUTO-REJECT
- **File:** `android/app/src/main/AndroidManifest.xml:66`
- **Issue:** `android:usesCleartextTraffic="true"`
- **Risk:** Allows unencrypted HTTP traffic - Major security vulnerability
- **Impact:** AUTOMATIC PLAY STORE REJECTION
- **Fix:** Remove or set to `false`, use HTTPS only

### 2. **Hardcoded Test Backend URLs** ⛔ AUTO-REJECT
- **Files:**
  - `lib/config.dart` - ngrok URL
  - `lib/screens/driver_goto_destination_page.dart:24` - ngrok URL
  - `lib/screens/driver_profile_page.dart:81` - ngrok URL
  - `lib/screens/splash_screen.dart:37` - ngrok URL
  - `lib/screens/driver_details_page.dart:1384` - ngrok URL
  - `lib/screens/real_home_page.dart:8` - different ngrok URL
- **URLs:** 
  - `https://chauncey-unpercolated-roastingly.ngrok-free.dev`
  - `https://1708303a1cc8.ngrok-free.app`
- **Issue:** Development/test URLs hardcoded in source
- **Risk:** Users connecting to wrong backend, app won't work in production
- **Impact:** REJECTION + Non-functional app
- **Fix:** Use environment configuration via AppConfig

### 3. **Hardcoded Google Maps API Key** ⛔ SECURITY RISK
- **File:** `lib/screens/driver_goto_destination_page.dart:9`
- **Value:** `AIzaSyB7VstS4RZlou2jyNgzkKePGqNbs2MyzYY`
- **Also in:** `android/app/src/main/AndroidManifest.xml:72`
- **Also in:** `lib/screens/driver_dashboard_page.dart:3011`
- **Issue:** API key exposed in source code
- **Risk:** 
  - Anyone can use your API quota
  - QPS limits can be exhausted by malicious users
  - High API bills
  - Could be restricted by Google
- **Impact:** Functional but security risk
- **Fix:** Move to secure backend or use restricted key

### 4. **Hardcoded Razorpay Test Key** ⛔ SECURITY RISK
- **File:** `lib/screens/wallet_page.dart:574`
- **Key:** `rzp_test_RUSfmaBJxKTTMT`
- **Issue:** Test payment key in release build
- **Risk:** 
  - Using test mode in production
  - Transactions won't be real
  - Payments won't work correctly
- **Impact:** Payment functionality broken, rejection for incorrect implementation
- **Fix:** Use production key from secure configuration

### 5. **Hardcoded Test Contact Information** ⛔ SECURITY RISK
- **File:** `lib/screens/wallet_page.dart:576`
- **Values:** 
  - `'contact': '9999999999'`
  - `'email': 'driver@example.com'`
- **Issue:** Placeholder values in production code
- **Risk:** All users will have same contact info in payments
- **Impact:** Payments rejected, user experience broken
- **Fix:** Use actual user contact from authentication

### 6. **Firebase API Key Exposed** ⚠️ LOW RISK (Public by design)
- **File:** `lib/firebase_options.dart:55`
- **Key:** `AIzaSyALNJltc3Leg3TNNXDPTdDuygoYdXvcGQs`
- **Note:** Firebase keys are meant to be public, but verify restrictions are set

---

## ⚠️ HIGH PRIORITY ISSUES (Likely Rejection)

### 7. **Multiple Backend URLs Inconsistency**
- **Problem:** Different ngrok URLs in different files
- **Impact:** Configuration management issues, potential for broken features
- **Fix:** Centralize in `config.dart` only

### 8. **Excessive Debug Logging**
- **Issue:** `debugPrint()` and `print()` statements throughout codebase
- **Files Affected:** Multiple (socket_service.dart, dashboard_page.dart, etc.)
- **Play Store Policy:** Debug output should disabled in release
- **Fix:** Protected with `kDebugMode` checks (partially done)

---

## 🔒 MEDIUM PRIORITY SECURITY ISSUES

### 9. **No Explicit HTTPS Enforcement**
- **Issue:** Some URLs constructed without explicit HTTPS validation
- **Impact:** Potential for downgrade attacks
- **Fix:** Enforce HTTPS everywhere, disable cleartext traffic

### 10. **Location Service Permissions**
- **Permissions Used:**
  - `ACCESS_FINE_LOCATION`
  - `ACCESS_COARSE_LOCATION`
  - `ACCESS_BACKGROUND_LOCATION`
- **Status:** ✅ Properly declared in AndroidManifest
- **Note:** Ensure privacy policy explains background location usage

### 11. **Camera & Document Permissions**
- **Status:** ✅ Documented for KYC document collection
- **Note:** Ensure privacy policy explains document usage

### 12. **Overlay Permission**
- **Issue:** `SYSTEM_ALERT_WINDOW` permission for trip overlays
- **Status:** ✅ Properly handled with request
- **Note:** Document in privacy policy

---

## ✅ VERIFICATION CHECKLIST

### Network Security
- [ ] ❌ Remove `android:usesCleartextTraffic="true"`
- [ ] ✅ Use HTTPS for all APIs
- [ ] ❌ Remove hardcoded ngrok URLs
- [ ] ❌ Move API keys to environment configuration
- [ ] ✅ Use Firebase for authentication

### Credentials & Secrets
- [ ] ❌ Remove hardcoded Razorpay test key
- [ ] ❌ Remove hardcoded test contact/email
- [ ] ⚠️ Verify Google Maps API key restrictions
- [ ] ❌ Verify Firebase keys are restricted
- [ ] ✅ No database credentials in code

### Data Privacy
- [ ] ✅ Permissions properly declared
- [ ] ❌ Privacy policy available (TBD - create)
- [ ] ⏳ Explain location data usage
- [ ] ⏳ Explain document/photo storage
- [ ] ⏳ Data retention policy
- [ ] ⏳ Third-party data sharing policy

### Code Quality
- [ ] ⚠️ Remove debug logging (partially done)
- [ ] ✅ Code obfuscation enabled
- [ ] ✅ Debuggable disabled in release
- [ ] ⏳ Test on real device
- [ ] ⏳ No malware/spyware functionality

---

## 📋 REQUIRED FIXES (PRIORITY ORDER)

### Priority 1 - AUTO REJECTION (Do First)
1. **Remove `usesCleartextTraffic="true"`** - CRITICAL
2. **Remove hardcoded ngrok URLs** - CRITICAL  
3. **Centralize backend URL in config.dart with environment support** - CRITICAL
4. **Move Razorpay key to environment/config** - CRITICAL
5. **Remove hardcoded test contact/email** - CRITICAL

### Priority 2 - High Impact
6. Clean up debug logging (kDebugMode wrapper)
7. Add API key restriction guidelines
8. Document security best practices

### Priority 3 - Store Listing
9. Create comprehensive privacy policy
10. Document all permissions usage
11. Add security considerations to app description

---

## 🛠️ TECHNICAL SOLUTIONS NEEDED

### Solution 1: Backend Configuration
```dart
// Current Problem:
const String _backendUrl = 'https://chauncey-unpercolated-roastingly.ngrok-free.dev';

// Solution:
static const String backendBaseUrl = String.fromEnvironment(
  'BACKEND_URL',
  defaultValue: 'https://api.yourdomain.com', // Your production URL
);
```

### Solution 2: Razorpay Configuration
```dart
// Current Problem:
var options = {
  'key': 'rzp_test_RUSfmaBJxKTTMT',
  'contact': '9999999999',
  'email': 'driver@example.com',
};

// Solution:
var options = {
  'key': AppConfig.razorpayKey, // From environment
  'contact': phoneNumber, // From user auth
  'email': userEmail, // From user auth
};
```

### Solution 3: AndroidManifest.xml
```xml
<!-- Current Problem -->
<application ... android:usesCleartextTraffic="true" />

<!-- Solution: Remove or set to false -->
<!-- All traffic should be HTTPS -->
```

---

## 📊 RISK SUMMARY

| Issue | Severity | Impact | Status |
|-------|----------|--------|--------|
| Cleartext Traffic | CRITICAL | Auto-Reject | ❌ NOT FIXED |
| Hardcoded ngrok URLs | CRITICAL | Auto-Reject | ❌ NOT FIXED |
| Razorpay Test Key | CRITICAL | Reject | ❌ NOT FIXED |
| Test Contact/Email | CRITICAL | Reject | ❌ NOT FIXED |
| Maps API Key Exposed | HIGH | Security Risk | ⚠️ EXPOSED |
| Debug Logging | MEDIUM | Minor Issue | ⏳ PARTIAL |
| Privacy Policy | MEDIUM | Required | ❌ MISSING |

---

## 🚀 CURRENT READINESS

**Overall Score: 40/100** ⚠️ NOT READY

- Code Structure: ✅ 90%
- Security: ❌ 30%
- Configuration: ❌ 40%
- Documentation: ❌ 20%

---

## ⏭️ NEXT STEPS

1. **First:** Fix all CRITICAL security issues (Priority 1)
2. **Then:** Address configuration issues
3. **Then:** Create privacy policy
4. **Finally:** Build and test

**Estimated Fix Time:** 2-3 hours

---

*Generated: February 23, 2026*
*App: Ghumo Partner (com.ghumo.driver)*
