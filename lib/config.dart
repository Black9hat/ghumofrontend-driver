// lib/config.dart

class AppConfig {
  /// 🔐 PRODUCTION: Use --dart-define=BACKEND_URL=https://ghumobackend.onrender.com
  /// For development, set environment variable: export BACKEND_URL=https://...
  /// Default points to your production API - MUST BE HTTPS
  static const String backendBaseUrl = String.fromEnvironment(
    'BACKEND_URL',
    defaultValue:
        'https://ghumobackend.onrender.com', // ✅ Production backend (Render)
  );

  /// 🎫 Razorpay API Key (Production key from environment)
  /// Use: flutter build --dart-define=RAZORPAY_KEY=rzp_live_xxxxxx
  static const String razorpayKey = String.fromEnvironment(
  'RAZORPAY_KEY',
  defaultValue: 'rzp_live_SNEMiHQ1wFR2Tw', // ← paste your rzp_live_ key here
);

  /// 🗺️ Google Maps API Key (from environment or use embedded key)
  /// This key is already in AndroidManifest; restrict it in Google Cloud Console
  static const String googleMapsApiKey = String.fromEnvironment(
    'GOOGLE_MAPS_API_KEY',
    defaultValue: 'AIzaSyB7VstS4RZlou2jyNgzkKePGqNbs2MyzYY',
  );

  // Timeout for API requests (seconds)
  static const int requestTimeoutSeconds = 60;

  /// Verify that production settings are valid
  static void validateProductionSettings() {
    if (backendBaseUrl.isEmpty || !backendBaseUrl.startsWith('https://')) {
      throw Exception('❌ CRITICAL: Invalid backendBaseUrl - must be HTTPS URL');
    }
    if (razorpayKey.isEmpty) {
      throw Exception(
        '❌ CRITICAL: RAZORPAY_KEY not set - required for payments',
      );
    }
  }
}
