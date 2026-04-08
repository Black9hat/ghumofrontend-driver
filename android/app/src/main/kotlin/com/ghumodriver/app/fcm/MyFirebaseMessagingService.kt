package com.ghumodriver.app.fcm
import android.app.ActivityManager
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.PowerManager
import android.util.Log
import com.ghumodriver.app.overlay.OverlayService
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

        // ✅ WAKELOCK: Prevent CPU from sleeping before OverlayService starts.
        // Critical on deep-sleeping devices (Xiaomi, Oppo, Vivo, Realme, Samsung).
        // ✅ FIX: Increased to 20s (was 10s). startForegroundService + overlay
        //    inflation can take >10s on low-end devices under battery saver.
        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
        val wakeLock = pm.newWakeLock(
            PowerManager.PARTIAL_WAKE_LOCK,
            "drivergo:FCMWakeLock"
        )
        wakeLock.acquire(20_000L) // Hold for max 20 seconds

        try {
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
            val type = data["type"]
            val tripId = data["tripId"]
            
            Log.d(TAG, "🔍 Type received: $type")
            Log.d(TAG, "🔍 TripId: $tripId")

            val isTripRequest = !tripId.isNullOrEmpty() && when (type?.lowercase()) {
                "trip_request" -> true
                "short"        -> true
                "long"         -> true
                "parcel"       -> true
                else           -> false
            }

            Log.d(TAG, "✅ Is trip request: $isTripRequest")

            if (isTripRequest) {
                // ✅ FIX: Use the improved foreground check that correctly detects
                //    whether the app's UI is actually visible (not just process alive).
                if (isAppUiVisible()) {
                    Log.d(TAG, "⚠️ APP UI IS VISIBLE — Skipping overlay display")
                    Log.d(TAG, "   (Overlay only shows when app is closed/backgrounded)")
                } else {
                    Log.d(TAG, "✅ APP IS IN BACKGROUND/CLOSED — Starting overlay service")
                    showTripOverlay(data)
                }
            } else {
                Log.d(TAG, "⚠️ NOT a trip request (type=$type) — ignoring")
            }

        } finally {
            if (wakeLock.isHeld) wakeLock.release()
        }
    }

    /**
     * ✅ FIX: Improved foreground detection.
     *
     * The old check used IMPORTANCE_FOREGROUND on the process, but the app
     * PROCESS stays IMPORTANCE_FOREGROUND for several seconds after the user
     * swipes it away (it's being garbage-collected). This caused the overlay
     * to be skipped even when the app was already closed.
     *
     * This new check looks at whether any Activity of our package is actually
     * in the RESUMED state by inspecting running tasks, which is more reliable.
     */
    private fun isAppUiVisible(): Boolean {
        val activityManager = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager

        // Primary check: running tasks (works on Android 5+, returns top activity)
        try {
            @Suppress("DEPRECATION")
            val tasks = activityManager.getRunningTasks(1)
            if (!tasks.isNullOrEmpty()) {
                val topActivity = tasks[0].topActivity
                val isOurApp = topActivity?.packageName == packageName
                Log.d(TAG, "📋 Top activity package: ${topActivity?.packageName}")
                Log.d(TAG, "📋 Our package: $packageName")
                Log.d(TAG, "📋 isOurApp at top: $isOurApp")
                // If our activity is on top AND the process importance is foreground,
                // then the UI is actually visible.
                if (isOurApp) {
                    val isProcessForeground = isProcessInForeground()
                    Log.d(TAG, "📋 Process is foreground: $isProcessForeground")
                    return isProcessForeground
                }
                // Our app is not the top activity → treat as backgrounded
                return false
            }
        } catch (e: Exception) {
            Log.w(TAG, "⚠️ getRunningTasks failed: ${e.message} — falling back")
        }

        // Fallback: process importance check
        return isProcessInForeground()
    }

    private fun isProcessInForeground(): Boolean {
        val activityManager = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        val appProcesses = activityManager.runningAppProcesses ?: return false
        for (appProcess in appProcesses) {
            if (appProcess.importance == ActivityManager.RunningAppProcessInfo.IMPORTANCE_FOREGROUND &&
                appProcess.processName == packageName
            ) {
                return true
            }
        }
        return false
    }

    private fun showTripOverlay(data: Map<String, String>) {
        try {
            Log.d(TAG, "━".repeat(60))
            Log.d(TAG, "🎯 showTripOverlay() — Extracting all fields")
            Log.d(TAG, "━".repeat(60))

            val tripData = HashMap<String, Any?>()
            
            tripData["tripId"]             = data["tripId"] ?: ""
            tripData["fare"]               = data["fare"] ?: "0"
            tripData["vehicleType"]        = data["vehicleType"]?.uppercase() ?: "BIKE"
            tripData["type"]               = data["type"] ?: ""
            tripData["isDestinationMatch"] = data["isDestinationMatch"] ?: "false"
            tripData["customerId"]         = data["customerId"] ?: ""
            tripData["paymentMethod"]      = data["paymentMethod"] ?: "cash"
            
            val pickupAddress = when {
                !data["pickupAddress"].isNullOrEmpty() && data["pickupAddress"] != "Pickup Location" -> {
                    Log.d(TAG, "✅ Using pickupAddress: ${data["pickupAddress"]}")
                    data["pickupAddress"]!!
                }
                !data["pickup"].isNullOrEmpty() -> {
                    Log.d(TAG, "ℹ️ Using pickup field as address")
                    data["pickup"]!!
                }
                else -> {
                    Log.d(TAG, "⚠️ No pickup address — using default")
                    "Pickup Location"
                }
            }

            val pickupLat = data["pickupLat"] ?: "0"
            val pickupLng = data["pickupLng"] ?: "0"
            
            val dropAddress = when {
                !data["dropAddress"].isNullOrEmpty() && data["dropAddress"] != "Drop Location" -> {
                    Log.d(TAG, "✅ Using dropAddress: ${data["dropAddress"]}")
                    data["dropAddress"]!!
                }
                !data["drop"].isNullOrEmpty() -> {
                    Log.d(TAG, "ℹ️ Using drop field as address")
                    data["drop"]!!
                }
                else -> {
                    Log.d(TAG, "⚠️ No drop address — using default")
                    "Drop Location"
                }
            }

            val dropLat = data["dropLat"] ?: "0"
            val dropLng = data["dropLng"] ?: "0"
            
            tripData["pickupAddress"] = pickupAddress
            tripData["pickupLat"]     = pickupLat
            tripData["pickupLng"]     = pickupLng
            tripData["dropAddress"]   = dropAddress
            tripData["dropLat"]       = dropLat
            tripData["dropLng"]       = dropLng

            Log.d(TAG, "✅ EXTRACTED DATA:")
            Log.d(TAG, "   Fare: ${tripData["fare"]}")
            Log.d(TAG, "   Type: ${tripData["type"]}")
            Log.d(TAG, "   Pickup: $pickupAddress ($pickupLat, $pickupLng)")
            Log.d(TAG, "   Drop:   $dropAddress ($dropLat, $dropLng)")

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