package com.example.drivergo.fcm

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

        Log.d(TAG, "═".repeat(50))
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
        
        Log.d(TAG, "═".repeat(50))

        val data = message.data

        // Check if it's a trip request
        val type = data["type"]
        val tripId = data["tripId"]
        val isTripRequest = type == "TRIP_REQUEST" && !tripId.isNullOrEmpty()

        Log.d(TAG, "🔍 Type: $type")
        Log.d(TAG, "🔍 TripId: $tripId")
        Log.d(TAG, "🔍 Is trip request: $isTripRequest")

        if (isTripRequest) {
            Log.d(TAG, "✅ TRIP REQUEST CONFIRMED - Starting overlay service")
            showTripOverlay(data)
        } else {
            Log.d(TAG, "⚠️ NOT a trip request - ignoring")
        }
    }

    private fun showTripOverlay(data: Map<String, String>) {
        try {
            Log.d(TAG, "━".repeat(50))
            Log.d(TAG, "🎯 showTripOverlay() CALLED")
            Log.d(TAG, "━".repeat(50))

            // 🔥 CRITICAL: FCM data is FLAT - no nested objects!
            // Everything comes as strings at root level
            
            val tripData = HashMap<String, Any?>()
            
            // Core trip data
            tripData["tripId"] = data["tripId"] ?: ""
            tripData["fare"] = data["fare"] ?: "0"
            tripData["vehicleType"] = data["vehicleType"]?.uppercase() ?: "BIKE"
            tripData["isDestinationMatch"] = data["isDestinationMatch"] ?: "false"
            tripData["customerId"] = data["customerId"] ?: ""
            tripData["paymentMethod"] = data["paymentMethod"] ?: "cash"
            
            // 🔥 CRITICAL: Extract flat pickup/drop fields
            tripData["pickupAddress"] = data["pickupAddress"] ?: "Pickup Location"
            tripData["pickupLat"] = data["pickupLat"] ?: "0"
            tripData["pickupLng"] = data["pickupLng"] ?: "0"
            
            tripData["dropAddress"] = data["dropAddress"] ?: "Drop Location"
            tripData["dropLat"] = data["dropLat"] ?: "0"
            tripData["dropLng"] = data["dropLng"] ?: "0"

            Log.d(TAG, "📦 Prepared trip data:")
            tripData.forEach { (key, value) ->
                Log.d(TAG, "   $key = $value")
            }

            Log.d(TAG, "🚀 Creating intent for OverlayService...")
            
            val intent = Intent(this, OverlayService::class.java)
            intent.action = "SHOW"
            intent.putExtra("tripData", tripData)

            Log.d(TAG, "🚀 Starting service...")
            
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                startForegroundService(intent)
                Log.d(TAG, "✅ startForegroundService() called (Android O+)")
            } else {
                startService(intent)
                Log.d(TAG, "✅ startService() called (pre-O)")
            }

            Log.d(TAG, "━".repeat(50))
            Log.d(TAG, "✅ OverlayService should now be starting...")
            Log.d(TAG, "━".repeat(50))

        } catch (e: Exception) {
            Log.e(TAG, "❌❌❌ CRITICAL ERROR in showTripOverlay ❌❌❌")
            Log.e(TAG, "Error: ${e.message}")
            Log.e(TAG, "Stack trace:")
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