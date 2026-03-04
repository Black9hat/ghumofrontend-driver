package com.example.drivergo

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.util.Log
import android.content.Context
import android.os.PowerManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    
    companion object {
        private const val TAG = "MainActivity"
        private const val OVERLAY_CHANNEL = "overlay_service"
        private const val OVERLAY_PERMISSION_REQUEST = 1234
        private const val BATTERY_OPTIMIZATION_REQUEST = 1235
    }
    
    private var methodChannel: MethodChannel? = null
    
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        Log.d(TAG, "🔧 Configuring Flutter Engine")
        
        methodChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger, 
            OVERLAY_CHANNEL
        )
        
        methodChannel?.setMethodCallHandler { call, result ->
            Log.d(TAG, "📞 Method call received: ${call.method}")
            
            when (call.method) {
                "requestPermissions" -> {
                    Log.d(TAG, "🔐 Requesting overlay permission")
                    requestOverlayPermission()
                    result.success(true)
                }
                "show" -> {
                    Log.d(TAG, "📱 Show overlay requested")
                    try {
                        @Suppress("UNCHECKED_CAST")
                        val tripData = call.argument<HashMap<String, Any?>>("tripData")
                        if (tripData != null) {
                            showOverlay(tripData)
                            result.success(true)
                        } else {
                            Log.e(TAG, "❌ No trip data provided")
                            result.error("NO_DATA", "Trip data is null", null)
                        }
                    } catch (e: Exception) {
                        Log.e(TAG, "❌ Error showing overlay: ${e.message}")
                        result.error("SHOW_ERROR", e.message, null)
                    }
                }
                "hide" -> {
                    Log.d(TAG, "🙈 Hide overlay requested")
                    hideOverlay()
                    result.success(true)
                }
                "checkPermission" -> {
                    val hasPermission = hasOverlayPermission()
                    Log.d(TAG, "🔍 Check permission: $hasPermission")
                    result.success(hasPermission)
                }
                "requestBatteryOptimization" -> {
                    Log.d(TAG, "🔋 Requesting battery optimization exemption")
                    requestBatteryOptimizationExemption()
                    result.success(true)
                }
                else -> {
                    Log.w(TAG, "⚠️ Unknown method: ${call.method}")
                    result.notImplemented()
                }
            }
        }
        
        Log.d(TAG, "✅ Method channel configured")
    }
    
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        Log.d(TAG, "🚀 MainActivity onCreate")
        
        handleIntent(intent)
        checkBatteryOptimization()
    }
    
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        Log.d(TAG, "🔄 onNewIntent")
        setIntent(intent)
        handleIntent(intent)
    }
    
    private fun handleIntent(intent: Intent?) {
        val tripAction = intent?.getStringExtra("tripAction")
        val tripId = intent?.getStringExtra("tripId")
        
        Log.d(TAG, "📦 Intent received - Action: $tripAction, TripId: $tripId")
        
        if (tripAction != null && tripId != null) {
            val prefs = getSharedPreferences("FlutterSharedPreferences", MODE_PRIVATE)
            prefs.edit().apply {
                putString("flutter.overlay_action", tripAction)
                putString("flutter.overlay_trip_id", tripId)
                putLong("flutter.overlay_action_time", System.currentTimeMillis())
                apply()
            }
            Log.d(TAG, "✅ Saved overlay action to SharedPreferences")
        }
    }
    
    private fun hasOverlayPermission(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            Settings.canDrawOverlays(this)
        } else {
            true
        }
    }
    
    private fun requestOverlayPermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            if (!Settings.canDrawOverlays(this)) {
                Log.d(TAG, "🔐 Opening overlay permission settings")
                val intent = Intent(
                    Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                    Uri.parse("package:$packageName")
                )
                startActivityForResult(intent, OVERLAY_PERMISSION_REQUEST)
            } else {
                Log.d(TAG, "✅ Overlay permission already granted")
            }
        }
    }
    
    private fun checkBatteryOptimization() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
            val packageName = packageName
            
            if (!pm.isIgnoringBatteryOptimizations(packageName)) {
                Log.d(TAG, "⚠️ Battery optimization is enabled - should request exemption")
            } else {
                Log.d(TAG, "✅ Battery optimization already disabled")
            }
        }
    }
    
    private fun requestBatteryOptimizationExemption() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val intent = Intent()
            val packageName = packageName
            val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
            
            if (!pm.isIgnoringBatteryOptimizations(packageName)) {
                intent.action = Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS
                intent.data = Uri.parse("package:$packageName")
                startActivityForResult(intent, BATTERY_OPTIMIZATION_REQUEST)
                Log.d(TAG, "🔋 Battery optimization exemption requested")
            } else {
                Log.d(TAG, "✅ Battery optimization already disabled")
            }
        }
    }
    
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        
        when (requestCode) {
            OVERLAY_PERMISSION_REQUEST -> {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    val granted = Settings.canDrawOverlays(this)
                    Log.d(TAG, "🔐 Overlay permission result: $granted")
                    methodChannel?.invokeMethod("permissionResult", granted)
                }
            }
            BATTERY_OPTIMIZATION_REQUEST -> {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
                    val granted = pm.isIgnoringBatteryOptimizations(packageName)
                    Log.d(TAG, "🔋 Battery optimization exemption result: $granted")
                }
            }
        }
    }
    
    private fun showOverlay(tripData: HashMap<String, Any?>) {
        Log.d(TAG, "📱 Starting OverlayService")
        Log.d(TAG, "   Trip data: $tripData")
        
        val intent = Intent(this, com.example.drivergo.overlay.OverlayService::class.java).apply {
            action = "SHOW"
            putExtra("tripData", tripData)
        }
        
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                startForegroundService(intent)
                Log.d(TAG, "✅ OverlayService started (foreground)")
            } else {
                startService(intent)
                Log.d(TAG, "✅ OverlayService started")
            }
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error starting OverlayService: ${e.message}")
            e.printStackTrace()
        }
    }
    
    private fun hideOverlay() {
        Log.d(TAG, "🙈 Hiding overlay")
        val intent = Intent(this, com.example.drivergo.overlay.OverlayService::class.java).apply {
            action = "HIDE"
        }
        try {
            startService(intent)
            Log.d(TAG, "✅ Hide overlay command sent")
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error hiding overlay: ${e.message}")
        }
    }
    
    override fun onDestroy() {
        Log.d(TAG, "💀 MainActivity onDestroy")
        methodChannel?.setMethodCallHandler(null)
        methodChannel = null
        super.onDestroy()
    }
    
    override fun onResume() {
        super.onResume()
        Log.d(TAG, "▶️ MainActivity onResume")
    }
    
    override fun onPause() {
        super.onPause()
        Log.d(TAG, "⏸️ MainActivity onPause")
    }
}
// ✅ NOTHING AFTER THIS LINE - NO OTHER CLASSES!