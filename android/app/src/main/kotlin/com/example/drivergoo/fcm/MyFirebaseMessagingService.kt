package com.example.drivergo.fcm

import android.app.ActivityManager
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import com.example.drivergo.overlay.OverlayService
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage

class MyFirebaseMessagingService : FirebaseMessagingService() {

    companion object {
        private const val TAG = "FCMService"
    }

    override fun onCreate() {
        super.onCreate()
        Log.d(TAG, "🔧 MyFirebaseMessagingService CREATED")
    }

    override fun onMessageReceived(message: RemoteMessage) {
        super.onMessageReceived(message)

        Log.d(TAG, "═".repeat(60))
        Log.d(TAG, "🔔 FCM MESSAGE RECEIVED (NATIVE)")
        Log.d(TAG, "   MessageId: ${message.messageId}")
        Log.d(TAG, "   From: ${message.from}")
        Log.d(TAG, "   SentTime: ${message.sentTime}")
        Log.d(TAG, "   Priority: ${message.priority}")
        Log.d(TAG, "   OriginalPriority: ${message.originalPriority}")
        Log.d(TAG, "   Notification: ${message.notification}")
        Log.d(TAG, "   Data size: ${message.data.size}")
        Log.d(TAG, "   Data keys: ${message.data.keys}")
        
        message.data.forEach { (key, value) ->
            Log.d(TAG, "      [$key] = $value")
        }
        
        Log.d(TAG, "═".repeat(60))

        val data = message.data

        // Check if it's a trip request
        val type = data["type"]
        val tripId = data["tripId"]
        
        Log.d(TAG, "🔍 Type received: $type")
        Log.d(TAG, "🔍 TripId: $tripId")

        // ✅ FIX: Accept all trip types (short, long, parcel, TRIP_REQUEST)
        val isTripRequest = !tripId.isNullOrEmpty() && when(type?.lowercase()) {
            "trip_request" -> true      // Old format
            "short" -> true             // ✅ Your format!
            "long" -> true              // For long trips
            "parcel" -> true            // For parcel trips
            else -> false
        }

        Log.d(TAG, "✅ Is trip request: $isTripRequest")

        if (isTripRequest) {
            // ✅ NEW CHECK: Only show overlay if app is NOT in foreground
            if (isAppInForeground()) {
                Log.d(TAG, "⚠️ APP IS IN FOREGROUND - Skipping overlay display")
                Log.d(TAG, "   (Overlay only shows when app is closed)")
            } else {
                Log.d(TAG, "✅ APP IS IN BACKGROUND/CLOSED - Starting overlay service")
                showTripOverlay(data)
            }
        } else {
            Log.d(TAG, "⚠️ NOT a trip request (type=$type) - ignoring")
        }
    }

    /// ✅ NEW FUNCTION: Check if app is in foreground
    private fun isAppInForeground(): Boolean {
        val activityManager = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        val appProcesses = activityManager.runningAppProcesses ?: return false
        
        val packageName = packageName
        
        for (appProcess in appProcesses) {
            if (appProcess.importance == ActivityManager.RunningAppProcessInfo.IMPORTANCE_FOREGROUND &&
                appProcess.processName == packageName) {
                Log.d(TAG, "✅ App is in FOREGROUND")
                return true
            }
        }
        
        Log.d(TAG, "⚠️ App is in BACKGROUND or CLOSED")
        return false
    }

    private fun showTripOverlay(data: Map<String, String>) {
        try {
            Log.d(TAG, "━".repeat(60))
            Log.d(TAG, "🎯 showTripOverlay() - Extracting all fields")
            Log.d(TAG, "━".repeat(60))

            val tripData = HashMap<String, Any?>()
            
            // ✅ Core fields
            tripData["tripId"] = data["tripId"] ?: ""
            tripData["fare"] = data["fare"] ?: "0"
            tripData["vehicleType"] = data["vehicleType"]?.uppercase() ?: "BIKE"
            tripData["type"] = data["type"] ?: ""
            tripData["isDestinationMatch"] = data["isDestinationMatch"] ?: "false"
            tripData["customerId"] = data["customerId"] ?: ""
            tripData["paymentMethod"] = data["paymentMethod"] ?: "cash"
            
            // ✅ FIX: Get pickup address - Check multiple sources
            val pickupAddress = when {
                !data["pickupAddress"].isNullOrEmpty() && data["pickupAddress"] != "Pickup Location" -> {
                    Log.d(TAG, "✅ Using pickup address from data: ${data["pickupAddress"]}")
                    data["pickupAddress"]!!
                }
                !data["pickup"].isNullOrEmpty() -> {
                    Log.d(TAG, "ℹ️ Pickup address not available, using placeholder")
                    data["pickup"]!!
                }
                else -> {
                    Log.d(TAG, "⚠️ No pickup address found, using default")
                    "Pickup Location"
                }
            }
            
            val pickupLat = data["pickupLat"] ?: "0"
            val pickupLng = data["pickupLng"] ?: "0"
            
            // ✅ FIX: Get drop address - Check multiple sources
            val dropAddress = when {
                !data["dropAddress"].isNullOrEmpty() && data["dropAddress"] != "Drop Location" -> {
                    Log.d(TAG, "✅ Using drop address from data: ${data["dropAddress"]}")
                    data["dropAddress"]!!
                }
                !data["drop"].isNullOrEmpty() -> {
                    Log.d(TAG, "ℹ️ Drop address not available, using placeholder")
                    data["drop"]!!
                }
                else -> {
                    Log.d(TAG, "⚠️ No drop address found, using default")
                    "Drop Location"
                }
            }
            
            val dropLat = data["dropLat"] ?: "0"
            val dropLng = data["dropLng"] ?: "0"
            
            tripData["pickupAddress"] = pickupAddress
            tripData["pickupLat"] = pickupLat
            tripData["pickupLng"] = pickupLng
            tripData["dropAddress"] = dropAddress
            tripData["dropLat"] = dropLat
            tripData["dropLng"] = dropLng

            Log.d(TAG, "✅ EXTRACTED DATA:")
            Log.d(TAG, "   Fare: ${tripData["fare"]}")
            Log.d(TAG, "   Type: ${tripData["type"]}")
            Log.d(TAG, "   Pickup Address: $pickupAddress")
            Log.d(TAG, "   Pickup Coords: ($pickupLat, $pickupLng)")
            Log.d(TAG, "   Drop Address: $dropAddress")
            Log.d(TAG, "   Drop Coords: ($dropLat, $dropLng)")

            Log.d(TAG, "📦 Creating intent with tripData")
            val intent = Intent(this, OverlayService::class.java)
            intent.action = "SHOW"
            intent.putExtra("tripData", tripData)

            Log.d(TAG, "🚀 Starting OverlayService...")
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                startForegroundService(intent)
                Log.d(TAG, "✅ startForegroundService() called")
            } else {
                startService(intent)
                Log.d(TAG, "✅ startService() called")
            }

            Log.d(TAG, "━".repeat(60))
            Log.d(TAG, "✅ OverlayService should now be starting...")
            Log.d(TAG, "━".repeat(60))

        } catch (e: Exception) {
            Log.e(TAG, "❌ CRITICAL ERROR in showTripOverlay")
            Log.e(TAG, "Error: ${e.message}")
            e.printStackTrace()
        }
    }

    override fun onNewToken(token: String) {
        super.onNewToken(token)
        Log.d(TAG, "🔄 New FCM token: ${token.take(30)}...")
        
        val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        prefs.edit().apply {
            putString("flutter.fcmToken", token)
            putBoolean("flutter.fcmTokenRefreshed", true)
            apply()
        }
    }

    override fun onDestroy() {
        Log.d(TAG, "💀 MyFirebaseMessagingService DESTROYED")
        super.onDestroy()
    }
}