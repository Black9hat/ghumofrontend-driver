package com.ghumodriver.app.fcm

import android.app.ActivityManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.os.Build
import android.os.PowerManager
import android.util.Log
import androidx.core.app.NotificationCompat
import com.ghumodriver.app.R
import com.ghumodriver.app.overlay.OverlayService
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage
import java.net.URL

class MyFirebaseMessagingService : FirebaseMessagingService() {

    companion object {
        private const val TAG = "FCMService"
        private const val ADMIN_CHANNEL_ID = "high_importance_channel_v3"
    }

    override fun onCreate() {
        super.onCreate()
        Log.d(TAG, "🔧 MyFirebaseMessagingService CREATED")
        ensureAdminChannel()
    }

    override fun onMessageReceived(message: RemoteMessage) {
        super.onMessageReceived(message)

        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
        val wakeLock = pm.newWakeLock(
            PowerManager.PARTIAL_WAKE_LOCK,
            "drivergo:FCMWakeLock"
        )
        wakeLock.acquire(20_000L)

        try {
            Log.d(TAG, "═".repeat(60))
            Log.d(TAG, "🔔 FCM MESSAGE RECEIVED (NATIVE)")
            Log.d(TAG, "   MessageId: ${message.messageId}")
            Log.d(TAG, "   From: ${message.from}")
            Log.d(TAG, "   Notification: ${message.notification}")
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
                if (isAppUiVisible()) {
                    Log.d(TAG, "⚠️ APP UI IS VISIBLE — Skipping overlay display")
                } else {
                    Log.d(TAG, "✅ APP IS IN BACKGROUND/CLOSED — Starting overlay service")
                    showTripOverlay(data)
                }
            } else {
                // ✅ FIX: Admin/broadcast notifications — show with image
                // Previously this branch just logged "ignoring" and dropped the message.
                // Now we build a proper BigPictureStyle notification with the image.
                Log.d(TAG, "📢 Non-trip message (type=$type) — showing admin notification")
                showAdminNotification(data, message.notification)
            }

        } finally {
            if (wakeLock.isHeld) wakeLock.release()
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // ✅ Create the admin channel once — safe to call repeatedly (no-op if exists)
    // ─────────────────────────────────────────────────────────────────────────
    private fun ensureAdminChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                ADMIN_CHANNEL_ID,
                "Admin Notifications",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Promotions and admin broadcasts"
                enableVibration(true)
            }
            val nm = getSystemService(NotificationManager::class.java)
            nm.createNotificationChannel(channel)
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // ✅ Show admin/broadcast notification with BigPictureStyle image
    // ─────────────────────────────────────────────────────────────────────────
    private fun showAdminNotification(
        data: Map<String, String>,
        notification: RemoteMessage.Notification?
    ) {
        try {
            // Prefer data payload fields; fall back to notification block
            val title = data["title"]?.takeIf { it.isNotEmpty() }
                ?: notification?.title
                ?: "New Notification"
            val body = data["body"]?.takeIf { it.isNotEmpty() }
                ?: notification?.body
                ?: ""
            val imageUrl = data["imageUrl"]?.takeIf { it.isNotEmpty() }
                ?: data["image"]?.takeIf { it.isNotEmpty() }
                ?: notification?.imageUrl?.toString()

            Log.d(TAG, "📢 showAdminNotification — title=$title")
            Log.d(TAG, "   imageUrl=$imageUrl")

            val notificationManager =
                getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

            ensureAdminChannel()

            val builder = NotificationCompat.Builder(this, ADMIN_CHANNEL_ID)
                .setSmallIcon(R.mipmap.ic_launcher)
                .setContentTitle(title)
                .setContentText(body)
                .setPriority(NotificationCompat.PRIORITY_HIGH)
                .setAutoCancel(true)
                // BigTextStyle as default — replaced by BigPictureStyle if image loads
                .setStyle(NotificationCompat.BigTextStyle().bigText(body))

            val notifId = System.currentTimeMillis().toInt()

            if (!imageUrl.isNullOrEmpty()) {
                // Download image on background thread — show immediately on success,
                // fall back to text-only notification if download fails
                Thread {
                    try {
                        Log.d(TAG, "⬇️ Downloading notification image...")
                        val bitmap: Bitmap = BitmapFactory.decodeStream(
                            URL(imageUrl).openConnection().apply {
                                connectTimeout = 8_000
                                readTimeout    = 8_000
                            }.getInputStream()
                        )
                        builder
                            .setLargeIcon(bitmap)
                            .setStyle(
                                NotificationCompat.BigPictureStyle()
                                    .bigPicture(bitmap)
                                    .bigLargeIcon(null as Bitmap?) // hide icon when expanded
                            )
                        notificationManager.notify(notifId, builder.build())
                        Log.d(TAG, "✅ Admin notification shown WITH image")
                    } catch (e: Exception) {
                        Log.w(TAG, "⚠️ Image download failed — showing without image: ${e.message}")
                        notificationManager.notify(notifId, builder.build())
                    }
                }.start()
            } else {
                notificationManager.notify(notifId, builder.build())
                Log.d(TAG, "✅ Admin notification shown WITHOUT image (no imageUrl in payload)")
            }

        } catch (e: Exception) {
            Log.e(TAG, "❌ showAdminNotification error: ${e.message}")
        }
    }

    private fun isAppUiVisible(): Boolean {
        val activityManager = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager

        try {
            @Suppress("DEPRECATION")
            val tasks = activityManager.getRunningTasks(1)
            if (!tasks.isNullOrEmpty()) {
                val topActivity = tasks[0].topActivity
                val isOurApp = topActivity?.packageName == packageName
                Log.d(TAG, "📋 Top activity package: ${topActivity?.packageName}")
                Log.d(TAG, "📋 isOurApp at top: $isOurApp")
                if (isOurApp) {
                    val isProcessForeground = isProcessInForeground()
                    Log.d(TAG, "📋 Process is foreground: $isProcessForeground")
                    return isProcessForeground
                }
                return false
            }
        } catch (e: Exception) {
            Log.w(TAG, "⚠️ getRunningTasks failed: ${e.message} — falling back")
        }

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
                    data["pickupAddress"]!!
                }
                !data["pickup"].isNullOrEmpty() -> data["pickup"]!!
                else -> "Pickup Location"
            }

            val dropAddress = when {
                !data["dropAddress"].isNullOrEmpty() && data["dropAddress"] != "Drop Location" -> {
                    data["dropAddress"]!!
                }
                !data["drop"].isNullOrEmpty() -> data["drop"]!!
                else -> "Drop Location"
            }

            tripData["pickupAddress"] = pickupAddress
            tripData["pickupLat"]     = data["pickupLat"] ?: "0"
            tripData["pickupLng"]     = data["pickupLng"] ?: "0"
            tripData["dropAddress"]   = dropAddress
            tripData["dropLat"]       = data["dropLat"] ?: "0"
            tripData["dropLng"]       = data["dropLng"] ?: "0"

            Log.d(TAG, "✅ Pickup: $pickupAddress | Drop: $dropAddress")

            val intent = Intent(this, OverlayService::class.java)
            intent.action = "SHOW"
            intent.putExtra("tripData", tripData)

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                startForegroundService(intent)
            } else {
                startService(intent)
            }

            Log.d(TAG, "✅ OverlayService started")
            Log.d(TAG, "━".repeat(60))

        } catch (e: Exception) {
            Log.e(TAG, "❌ CRITICAL ERROR in showTripOverlay: ${e.message}")
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