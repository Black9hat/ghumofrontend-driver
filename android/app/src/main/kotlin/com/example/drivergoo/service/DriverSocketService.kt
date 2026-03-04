package com.example.drivergo.service

import android.app.*
import android.content.Context
import android.content.Intent
import android.location.Location
import android.os.Build
import android.os.IBinder
import android.util.Log
import androidx.core.app.NotificationCompat
import com.example.drivergo.MainActivity
import com.example.drivergo.R
import com.example.drivergo.overlay.OverlayService
import io.socket.client.IO
import io.socket.client.Socket
import org.json.JSONObject
import java.util.*

class DriverSocketService : Service() {

    companion object {
        private const val TAG = "DriverSocketService"
        private const val NOTIFICATION_ID = 101
        private const val CHANNEL_ID = "driver_socket_channel"
        
        // 🔥 UPDATE THIS TO YOUR BACKEND URL
        private const val BACKEND_URL = "https://ghumobackend.onrender.com"
    }

    private var socket: Socket? = null
    private var driverId: String? = null
    private var vehicleType: String? = null
    private var isConnected = false

    override fun onCreate() {
        super.onCreate()
        Log.d(TAG, "🚀 DriverSocketService onCreate")
        createNotificationChannel()
        startForeground(NOTIFICATION_ID, createNotification("Connecting..."))
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Log.d(TAG, "🔄 onStartCommand - Action: ${intent?.action}")
        
        when (intent?.action) {
            "STOP" -> {
                Log.d(TAG, "🛑 Stopping service")
                disconnect()
                stopForeground(STOP_FOREGROUND_REMOVE)
                stopSelf()
                return START_NOT_STICKY
            }
            else -> {
                driverId = intent?.getStringExtra("driverId")
                vehicleType = intent?.getStringExtra("vehicleType")
                
                Log.d(TAG, "   Driver ID: $driverId")
                Log.d(TAG, "   Vehicle Type: $vehicleType")
                
                if (!driverId.isNullOrEmpty()) {
                    connectSocket()
                } else {
                    Log.e(TAG, "❌ No driver ID provided!")
                }
            }
        }
        
        return START_STICKY
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Driver Online Status",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Shows when driver is online and available for rides"
                setShowBadge(false)
            }
            
            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(channel)
        }
    }

    private fun connectSocket() {
        if (socket?.connected() == true) {
            Log.d(TAG, "⚠️ Socket already connected")
            return
        }
        
        try {
            Log.d(TAG, "🔌 Connecting to socket: $BACKEND_URL")
            
            val opts = IO.Options().apply {
                reconnection = true
                reconnectionAttempts = Int.MAX_VALUE
                reconnectionDelay = 2000
                reconnectionDelayMax = 10000
                timeout = 20000
                transports = arrayOf("websocket")
                query = "driverId=$driverId&vehicleType=$vehicleType"
            }

            socket = IO.socket(BACKEND_URL, opts)

            socket?.on(Socket.EVENT_CONNECT) {
                Log.d(TAG, "✅ Socket CONNECTED")
                isConnected = true
                updateNotification("Online - Ready for trips")
                emitOnlineStatus(true)
            }

            socket?.on(Socket.EVENT_CONNECT_ERROR) { args ->
                Log.e(TAG, "❌ Socket connection error: ${args.firstOrNull()}")
                isConnected = false
                updateNotification("Connection error - Retrying...")
            }

            socket?.on(Socket.EVENT_DISCONNECT) { args ->
                Log.d(TAG, "🔌 Socket DISCONNECTED: ${args.firstOrNull()}")
                isConnected = false
                updateNotification("Disconnected - Reconnecting...")
            }

            socket?.on("trip:request") { args ->
                Log.d(TAG, "")
                Log.d(TAG, "=" .repeat(50))
                Log.d(TAG, "🚗 TRIP REQUEST RECEIVED VIA SOCKET!")
                Log.d(TAG, "=" .repeat(50))
                
                try {
                    val tripData = args[0] as JSONObject
                    Log.d(TAG, "   Trip Data: $tripData")
                    showOverlay(tripData)
                } catch (e: Exception) {
                    Log.e(TAG, "❌ Error parsing trip request: ${e.message}")
                }
            }
            
            // Also listen for these event names (backend might use different names)
            socket?.on("tripRequest") { args ->
                Log.d(TAG, "🚗 tripRequest event received")
                try {
                    val tripData = args[0] as JSONObject
                    showOverlay(tripData)
                } catch (e: Exception) {
                    Log.e(TAG, "Error: ${e.message}")
                }
            }
            
            socket?.on("newTripRequest") { args ->
                Log.d(TAG, "🚗 newTripRequest event received")
                try {
                    val tripData = args[0] as JSONObject
                    showOverlay(tripData)
                } catch (e: Exception) {
                    Log.e(TAG, "Error: ${e.message}")
                }
            }

            socket?.connect()
            Log.d(TAG, "🔄 Socket connecting...")

        } catch (e: Exception) {
            Log.e(TAG, "❌ Socket connection error: ${e.message}")
            e.printStackTrace()
        }
    }

    private fun emitOnlineStatus(isOnline: Boolean) {
        try {
            val payload = JSONObject().apply {
                put("driverId", driverId)
                put("isOnline", isOnline)
                put("vehicleType", vehicleType)
            }
            
            socket?.emit("driver:online", payload)
            socket?.emit("updateDriverStatus", payload)
            
            Log.d(TAG, "📤 Emitted online status: $isOnline")
        } catch (e: Exception) {
            Log.e(TAG, "Error emitting status: ${e.message}")
        }
    }

    fun sendLocation(latitude: Double, longitude: Double) {
        if (!isConnected) return
        
        try {
            val data = JSONObject().apply {
                put("driverId", driverId)
                put("latitude", latitude)
                put("longitude", longitude)
                put("timestamp", System.currentTimeMillis())
            }
            
            socket?.emit("driver:location", data)
            Log.d(TAG, "📍 Location sent: $latitude, $longitude")
        } catch (e: Exception) {
            Log.e(TAG, "Error sending location: ${e.message}")
        }
    }

    private fun showOverlay(tripData: JSONObject) {
        try {
            Log.d(TAG, "🖥️ Showing overlay for trip...")
            
            // Parse trip data
            val tripId = tripData.optString("tripId", tripData.optString("_id", ""))
            val fare = tripData.optString("fare", "0")
            val vehicleType = tripData.optString("vehicleType", "BIKE")
            val isDestinationMatch = tripData.optBoolean("isDestinationMatch", false)
            
            // Parse pickup address
            var pickupAddress = "Pickup Location"
            if (tripData.has("pickup")) {
                val pickup = tripData.optJSONObject("pickup")
                pickupAddress = pickup?.optString("address", pickupAddress) ?: pickupAddress
            }
            if (tripData.has("pickupAddress")) {
                pickupAddress = tripData.optString("pickupAddress", pickupAddress)
            }
            
            // Parse drop address
            var dropAddress = "Drop Location"
            if (tripData.has("drop")) {
                val drop = tripData.optJSONObject("drop")
                dropAddress = drop?.optString("address", dropAddress) ?: dropAddress
            }
            if (tripData.has("dropAddress")) {
                dropAddress = tripData.optString("dropAddress", dropAddress)
            }
            
            Log.d(TAG, "   Trip ID: $tripId")
            Log.d(TAG, "   Fare: ₹$fare")
            Log.d(TAG, "   Pickup: $pickupAddress")
            Log.d(TAG, "   Drop: $dropAddress")
            
            // Create HashMap for overlay
            val overlayData = HashMap<String, Any?>().apply {
                put("tripId", tripId)
                put("fare", fare)
                put("vehicleType", vehicleType.uppercase())
                put("pickupAddress", pickupAddress)
                put("dropAddress", dropAddress)
                put("isDestinationMatch", isDestinationMatch.toString())
                put("customerId", tripData.optString("customerId", ""))
                put("paymentMethod", tripData.optString("paymentMethod", "cash"))
            }
            
            // Start overlay service
            val intent = Intent(this, OverlayService::class.java).apply {
                action = "SHOW"  // 🔥 Fixed: was "SHOW_OVERLAY", should be "SHOW"
                putExtra("tripData", overlayData)
            }
            
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                startForegroundService(intent)
            } else {
                startService(intent)
            }
            
            Log.d(TAG, "✅ Overlay service started!")
            
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error showing overlay: ${e.message}")
            e.printStackTrace()
        }
    }

    private fun createNotification(text: String): Notification {
        val intent = Intent(this, MainActivity::class.java)
        intent.setFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
        
        val pendingIntent = PendingIntent.getActivity(
            this, 0, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Ghumo Driver")
            .setContentText(text)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setOngoing(true)
            .setContentIntent(pendingIntent)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .build()
    }
    
    private fun updateNotification(text: String) {
        val notification = createNotification(text)
        val manager = getSystemService(NotificationManager::class.java)
        manager.notify(NOTIFICATION_ID, notification)
    }

    private fun disconnect() {
        try {
            emitOnlineStatus(false)
            socket?.disconnect()
            socket?.off()
            socket = null
            isConnected = false
            Log.d(TAG, "🔌 Socket disconnected and cleaned up")
        } catch (e: Exception) {
            Log.e(TAG, "Error disconnecting: ${e.message}")
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        Log.d(TAG, "💀 DriverSocketService onDestroy")
        disconnect()
        super.onDestroy()
    }
}