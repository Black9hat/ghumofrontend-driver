package com.example.drivergo.overlay

import android.app.*
import android.content.Context
import android.content.Intent
import android.graphics.PixelFormat
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.provider.Settings
import android.util.Log
import android.view.Gravity
import android.view.LayoutInflater
import android.view.View
import android.view.WindowManager
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView
import android.widget.Toast
import androidx.core.app.NotificationCompat
import com.example.drivergo.MainActivity
import com.example.drivergo.R
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONObject
import java.util.concurrent.TimeUnit

class OverlayService : Service() {

    companion object {
        private const val TAG = "OverlayService"
        const val CHANNEL_ID = "trip_overlay_channel"
        const val NOTIFICATION_ID = 999
        
        // 🔥 CRITICAL: Your backend URL
        private const val BACKEND_URL = "https://chauncey-unpercolated-roastingly.ngrok-free.dev"

        @Volatile
        var isShowing = false
        
        @Volatile
        var currentTripId: String? = null
    }

    private var windowManager: WindowManager? = null
    private var overlayView: View? = null
    private var mediaPlayer: MediaPlayer? = null
    private var vibrator: Vibrator? = null
    private var countdownHandler: Handler? = null
    private var countdownRunnable: Runnable? = null
    private var secondsRemaining = 30
    private var tripData: HashMap<String, Any?>? = null
    
    // 🔥 NEW: HTTP client for API calls
    private val httpClient = OkHttpClient.Builder()
        .connectTimeout(10, TimeUnit.SECONDS)
        .readTimeout(10, TimeUnit.SECONDS)
        .writeTimeout(10, TimeUnit.SECONDS)
        .build()

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        Log.d(TAG, "╔═══════════════════════════════════════════════════")
        Log.d(TAG, "🔧 OverlayService onCreate")
        Log.d(TAG, "╚═══════════════════════════════════════════════════")
        
        createNotificationChannel()
        windowManager = getSystemService(WINDOW_SERVICE) as WindowManager

        vibrator = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val vibratorManager = getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as VibratorManager
            vibratorManager.defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            getSystemService(VIBRATOR_SERVICE) as Vibrator
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val action = intent?.action
        
        Log.d(TAG, "╔═══════════════════════════════════════════════════")
        Log.d(TAG, "🚀 onStartCommand")
        Log.d(TAG, "   Action: $action")
        Log.d(TAG, "   isShowing: $isShowing")
        Log.d(TAG, "   currentTripId: $currentTripId")
        Log.d(TAG, "╚═══════════════════════════════════════════════════")

        when (action) {
            "SHOW" -> {
                @Suppress("UNCHECKED_CAST")
                val newTripData = intent.getSerializableExtra("tripData") as? HashMap<String, Any?>
                val newTripId = newTripData?.get("tripId")?.toString()
                
                Log.d(TAG, "📦 SHOW action received")
                Log.d(TAG, "   New Trip ID: $newTripId")
                Log.d(TAG, "   Trip Data: $newTripData")
                
                if (newTripData != null && !newTripId.isNullOrEmpty()) {
                    tripData = newTripData
                    currentTripId = newTripId
                    
                    startForeground(NOTIFICATION_ID, createNotification())
                    
                    if (hasOverlayPermission()) {
                        Log.d(TAG, "✅ Has overlay permission - showing overlay")
                        showOverlay()
                    } else {
                        Log.e(TAG, "❌ No overlay permission!")
                        showFallbackNotification()
                    }
                } else {
                    Log.e(TAG, "❌ Invalid trip data - ignoring SHOW")
                }
            }
            "HIDE" -> {
                Log.d(TAG, "🙈 HIDE action received")
                hideOverlay()
                stopSelf()
            }
            null -> {
                Log.d(TAG, "⚠️ NULL action received - ignoring")
            }
            else -> {
                Log.d(TAG, "⚠️ Unknown action: $action")
            }
        }

        return START_NOT_STICKY
    }

    private fun hasOverlayPermission(): Boolean {
        val hasPermission = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            Settings.canDrawOverlays(this)
        } else {
            true
        }
        Log.d(TAG, "🔐 Overlay permission: $hasPermission")
        return hasPermission
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Trip Requests Overlay",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Incoming trip request overlay"
                setSound(null, null)
                enableVibration(false)
                lockscreenVisibility = Notification.VISIBILITY_PUBLIC
            }

            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(channel)
            Log.d(TAG, "✅ Notification channel created")
        }
    }

    private fun createNotification(): Notification {
        val fare = tripData?.get("fare")?.toString() ?: "0"
        val pickup = tripData?.get("pickupAddress")?.toString() ?: "Pickup"

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("🚗 New Trip Request!")
            .setContentText("₹$fare - $pickup")
            .setSmallIcon(R.mipmap.ic_launcher)
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setCategory(NotificationCompat.CATEGORY_CALL)
            .setOngoing(true)
            .setAutoCancel(false)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .build()
    }

    private fun showFallbackNotification() {
        Log.d(TAG, "📱 Showing fallback notification")
        
        val fare = tripData?.get("fare")?.toString() ?: "0"
        val pickup = tripData?.get("pickupAddress")?.toString() ?: "Pickup"

        val notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("🚗 New Trip Request - ₹$fare")
            .setContentText(pickup)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setCategory(NotificationCompat.CATEGORY_CALL)
            .setAutoCancel(true)
            .build()

        val manager = getSystemService(NotificationManager::class.java)
        manager.notify(NOTIFICATION_ID + 1, notification)
    }

    private fun showOverlay() {
        Log.d(TAG, "╔═══════════════════════════════════════════════════")
        Log.d(TAG, "📱 showOverlay() called")
        Log.d(TAG, "   isShowing: $isShowing")
        Log.d(TAG, "   tripData: $tripData")
        Log.d(TAG, "╚═══════════════════════════════════════════════════")

        if (isShowing) {
            Log.d(TAG, "⚠️ Overlay already showing - updating content")
            updateOverlayContent()
            return
        }

        isShowing = true
        secondsRemaining = 30

        val layoutType = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        } else {
            @Suppress("DEPRECATION")
            WindowManager.LayoutParams.TYPE_SYSTEM_OVERLAY
        }

        val layoutParams = WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            layoutType,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                    WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
                    WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or
                    WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                    WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON,
            PixelFormat.TRANSLUCENT
        )

        layoutParams.gravity = Gravity.TOP or Gravity.CENTER_HORIZONTAL
        layoutParams.y = 50

        try {
            overlayView = LayoutInflater.from(this).inflate(R.layout.trip_overlay, null)
            
            if (overlayView == null) {
                Log.e(TAG, "❌ Failed to inflate overlay layout!")
                isShowing = false
                return
            }
            
            setupOverlayContent()
            setupClickListeners()
            
            windowManager?.addView(overlayView, layoutParams)

            startCountdown()
            startVibrationAndSound()

            Log.d(TAG, "✅ Overlay banner successfully added to WindowManager!")
            
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error adding overlay: ${e.message}")
            e.printStackTrace()
            isShowing = false
        }
    }

    private fun setupOverlayContent() {
        val fare = tripData?.get("fare")?.toString() ?: "0"
        var pickupAddress = tripData?.get("pickupAddress")?.toString() ?: "Pickup Location"
        var dropAddress = tripData?.get("dropAddress")?.toString() ?: "Drop Location"
        
        pickupAddress = extractMainArea(pickupAddress)
        dropAddress = extractMainArea(dropAddress)
        
        val vehicleType = tripData?.get("vehicleType")?.toString()?.uppercase() ?: "BIKE"

        Log.d(TAG, "🎨 Setting up overlay card content")
        Log.d(TAG, "   Fare: ₹$fare")
        Log.d(TAG, "   Vehicle: $vehicleType")
        Log.d(TAG, "   Pickup: $pickupAddress")
        Log.d(TAG, "   Drop: $dropAddress")

        overlayView?.let { view ->
            (view.findViewById(R.id.tvTimer) as TextView?)?.text = "$secondsRemaining"
            (view.findViewById(R.id.tvFare) as TextView?)?.text = "₹$fare"
            (view.findViewById(R.id.tvPickup) as TextView?)?.text = pickupAddress
            (view.findViewById(R.id.tvDrop) as TextView?)?.text = dropAddress

            val pickupLat = tripData?.get("pickupLat")?.toString()?.toDoubleOrNull()
            val pickupLng = tripData?.get("pickupLng")?.toString()?.toDoubleOrNull()
            val dropLat = tripData?.get("dropLat")?.toString()?.toDoubleOrNull()
            val dropLng = tripData?.get("dropLng")?.toString()?.toDoubleOrNull()

            val distanceSection = view.findViewById(R.id.distanceSection) as LinearLayout?
            if (pickupLat != null && pickupLng != null && dropLat != null && dropLng != null) {
                val tripDistance = calculateDistance(pickupLat, pickupLng, dropLat, dropLng)
                (view.findViewById(R.id.tvTripDistance) as TextView?)?.text = "${"%.1f".format(tripDistance)} km trip"
                distanceSection?.visibility = View.VISIBLE
            } else {
                distanceSection?.visibility = View.GONE
            }
        }
    }

    private fun setupClickListeners() {
        overlayView?.let { view ->
            (view.findViewById(R.id.btnAccept) as Button?)?.setOnClickListener {
                Log.d(TAG, "✅ Accept button clicked!")
                handleAccept()
            }

            (view.findViewById(R.id.btnReject) as Button?)?.setOnClickListener {
                Log.d(TAG, "❌ Reject button clicked!")
                handleReject()
            }
        }
    }
    
    private fun updateOverlayContent() {
        Log.d(TAG, "🔄 Updating overlay content")
        setupOverlayContent()
    }

    private fun startCountdown() {
        Log.d(TAG, "⏱️ Starting countdown from $secondsRemaining seconds")
        
        countdownHandler?.removeCallbacksAndMessages(null)
        countdownHandler = Handler(Looper.getMainLooper())
        
        countdownRunnable = object : Runnable {
            override fun run() {
                secondsRemaining--
                overlayView?.findViewById<TextView>(R.id.tvTimer)?.text = "$secondsRemaining"

                if (secondsRemaining <= 0) {
                    Log.d(TAG, "⏰ Countdown finished - timeout!")
                    handleTimeout()
                } else {
                    countdownHandler?.postDelayed(this, 1000)
                }
            }
        }
        countdownHandler?.postDelayed(countdownRunnable!!, 1000)
    }

    private fun startVibrationAndSound() {
        Log.d(TAG, "📳🔊 Starting vibration and sound")
        
        val pattern = longArrayOf(0, 500, 200, 500, 200, 500)

        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                vibrator?.vibrate(VibrationEffect.createWaveform(pattern, 0))
            } else {
                @Suppress("DEPRECATION")
                vibrator?.vibrate(pattern, 0)
            }
            Log.d(TAG, "📳 Vibration started")
        } catch (e: Exception) {
            Log.e(TAG, "Vibration error: ${e.message}")
        }

        try {
            val resId = resources.getIdentifier("notification", "raw", packageName)
            if (resId != 0) {
                val soundUri = Uri.parse("android.resource://${packageName}/$resId")
                mediaPlayer = MediaPlayer().apply {
                    setDataSource(this@OverlayService, soundUri)
                    setAudioAttributes(
                        AudioAttributes.Builder()
                            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                            .setUsage(AudioAttributes.USAGE_NOTIFICATION_RINGTONE)
                            .build()
                    )
                    isLooping = true
                    prepare()
                    start()
                }
                Log.d(TAG, "🔊 Sound started")
            } else {
                Log.w(TAG, "⚠️ notification.mp3 not found in res/raw/")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Sound error: ${e.message}")
        }
    }

    private fun stopVibrationAndSound() {
        Log.d(TAG, "🔇 Stopping vibration and sound")
        
        vibrator?.cancel()
        
        try {
            mediaPlayer?.apply {
                if (isPlaying) stop()
                release()
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error stopping media: ${e.message}")
        }
        mediaPlayer = null
    }

    // 🔥 NEW: Accept via HTTP API (like socket accept)
// Only showing the CHANGED parts - update handleAccept() and handleReject()

// 🔥 FIXED: Accept via HTTP API (CORRECT ENDPOINT)
private fun handleAccept() {
    Log.d(TAG, "══════════════════════════════════")
    Log.d(TAG, "✅ ACCEPT CLICKED (OVERLAY)")
    Log.d(TAG, "TripId: $currentTripId")
    Log.d(TAG, "══════════════════════════════════")

    stopVibrationAndSound()
    countdownHandler?.removeCallbacksAndMessages(null)

    val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
    val driverId = prefs.getString("flutter.driverId", null)

    if (driverId.isNullOrEmpty() || currentTripId.isNullOrEmpty()) {
        Log.e(TAG, "❌ Missing driverId or tripId")
        Toast.makeText(this, "Accept failed", Toast.LENGTH_SHORT).show()
        hideOverlay()
        stopSelf()
        return
    }

    CoroutineScope(Dispatchers.IO).launch {
        try {
            val url = "$BACKEND_URL/api/trip/$currentTripId/accept"

            val json = JSONObject().apply {
                put("tripId", currentTripId)
                put("driverId", driverId)
            }

            val body = json.toString()
                .toRequestBody("application/json".toMediaType())

            val request = Request.Builder()
                .url(url)
                .post(body)
                .build()

            Log.d(TAG, "🌐 Calling ACCEPT API → $url")
            Log.d(TAG, "📦 Payload → $json")

            val response = httpClient.newCall(request).execute()
            val responseBody = response.body?.string()

            Log.d(TAG, "📥 Response Code: ${response.code}")
            Log.d(TAG, "📥 Response Body: $responseBody")

            withContext(Dispatchers.Main) {
                if (response.isSuccessful && responseBody != null) {
                    Log.d(TAG, "✅ Trip accepted successfully")

                    try {
                        // ✅ FIXED: Parse complete response
                        val responseJson = JSONObject(responseBody)
                        val dataObj = responseJson.optJSONObject("data")
                        
                        if (dataObj == null) {
                            Log.e(TAG, "❌ No data object in response")
                            Toast.makeText(this@OverlayService, "Invalid response", Toast.LENGTH_SHORT).show()
                            hideOverlay()
                            stopSelf()
                            return@withContext
                        }
                        
                        val tripObj = dataObj.optJSONObject("trip")
                        val customerObj = dataObj.optJSONObject("customer")
                        val otp = dataObj.optString("otp", "")
                        val rideCode = dataObj.optString("rideCode", otp)
                        val status = dataObj.optString("status", "driver_assigned")
                        
                        // ✅ FIXED: Build complete data
                        val completeTripData = JSONObject().apply {
                            put("tripId", currentTripId)
                            put("otp", rideCode)
                            put("rideCode", rideCode)
                            put("status", status)
                            
                            if (tripObj != null) {
                                put("trip", tripObj)
                                Log.d(TAG, "📦 Trip data: $tripObj")
                            }
                            
                            if (customerObj != null) {
                                put("customer", customerObj)
                                Log.d(TAG, "👤 Customer data: $customerObj")
                            }
                        }

                        // ✅ FIXED: Store complete data
                        prefs.edit().apply {
                            putString("flutter.overlay_action", "ACCEPT")
                            putString("flutter.overlay_trip_id", currentTripId)
                            putString("flutter.overlay_trip_data", completeTripData.toString())
                            putLong("flutter.overlay_action_time", System.currentTimeMillis())
                            apply()
                        }
                        
                        Log.d(TAG, "📝 Stored complete trip data")
                        Log.d(TAG, "📦 Data: $completeTripData")

                    } catch (e: Exception) {
                        Log.e(TAG, "❌ Parse error: ${e.message}", e)
                        Toast.makeText(this@OverlayService, "Error parsing response", Toast.LENGTH_SHORT).show()
                        hideOverlay()
                        stopSelf()
                        return@withContext
                    }

                    hideOverlay()

                    val intent = Intent(this@OverlayService, MainActivity::class.java).apply {
                        flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                                Intent.FLAG_ACTIVITY_CLEAR_TOP or
                                Intent.FLAG_ACTIVITY_SINGLE_TOP
                        putExtra("OPEN_ACTIVE_TRIP", true)
                    }
                    startActivity(intent)

                } else {
                    Log.e(TAG, "❌ Accept failed - HTTP ${response.code}")
                    Toast.makeText(
                        this@OverlayService,
                        if (response.code == 400) "Trip already taken" else "Request failed",
                        Toast.LENGTH_SHORT
                    ).show()
                    hideOverlay()
                }

                stopSelf()
            }

        } catch (e: Exception) {
            Log.e(TAG, "🔥 Accept API error: ${e.message}", e)

            withContext(Dispatchers.Main) {
                Toast.makeText(
                    this@OverlayService,
                    "Network error",
                    Toast.LENGTH_SHORT
                ).show()
                hideOverlay()
                stopSelf()
            }
        }
    }
}



// 🔥 Reject via HTTP API (CORRECT ENDPOINT)
private fun handleReject() {
    Log.d(TAG, "╔═══════════════════════════════════════════════════")
    Log.d(TAG, "❌ HANDLING REJECT VIA API")
    Log.d(TAG, "   Trip ID: $currentTripId")
    Log.d(TAG, "╚═══════════════════════════════════════════════════")
    
    stopVibrationAndSound()
    countdownHandler?.removeCallbacksAndMessages(null)

    val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
    val driverId = prefs.getString("flutter.driverId", null)
    
    if (driverId == null || currentTripId == null) {
        hideOverlay()
        stopSelf()
        return
    }

    // 🔥 Call backend API to reject trip (CORRECT ENDPOINT)
    CoroutineScope(Dispatchers.IO).launch {
        try {
            Log.d(TAG, "🌐 Calling /api/trip/reject-trip...")
            
            val jsonBody = JSONObject().apply {
                put("tripId", currentTripId)
                put("driverId", driverId)
            }
            
            val requestBody = jsonBody.toString()
                .toRequestBody("application/json".toMediaType())
            
            val request = Request.Builder()
                .url("$BACKEND_URL/api/trip/reject-trip")  // 🔥 FIXED: Correct endpoint
                .post(requestBody)
                .addHeader("Content-Type", "application/json")
                .build()
            
            httpClient.newCall(request).execute().use { response ->
                Log.d(TAG, "📡 Reject API Response: ${response.code}")
                
                withContext(Dispatchers.Main) {
                    // Store overlay action for Flutter to detect
                    val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                    prefs.edit().apply {
                        putString("flutter.overlay_action", "REJECT")
                        putString("flutter.overlay_trip_id", currentTripId)
                        putLong("flutter.overlay_action_time", System.currentTimeMillis())
                        apply()
                    }
                    Log.d(TAG, "📝 Stored reject overlay action in SharedPreferences")
                    
                    Toast.makeText(this@OverlayService, "Trip Rejected", Toast.LENGTH_SHORT).show()
                    hideOverlay()
                    stopSelf()
                }
            }
            
        } catch (e: Exception) {
            Log.e(TAG, "❌ Reject API error: ${e.message}")
            
            withContext(Dispatchers.Main) {
                hideOverlay()
                stopSelf()
            }
        }
    }
}
    private fun handleTimeout() {
        Log.d(TAG, "╔═══════════════════════════════════════════════════")
        Log.d(TAG, "⏰ HANDLING TIMEOUT")
        Log.d(TAG, "   Trip ID: $currentTripId")
        Log.d(TAG, "╚═══════════════════════════════════════════════════")
        
        stopVibrationAndSound()

        val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        prefs.edit().apply {
            putString("flutter.overlay_action", "TIMEOUT")
            putString("flutter.overlay_trip_id", currentTripId)
            putLong("flutter.overlay_action_time", System.currentTimeMillis())
            apply()
        }

        hideOverlay()
        stopSelf()
    }

    private fun hideOverlay() {
        Log.d(TAG, "╔═══════════════════════════════════════════════════")
        Log.d(TAG, "🙈 hideOverlay() called")
        Log.d(TAG, "   isShowing: $isShowing")
        Log.d(TAG, "╚═══════════════════════════════════════════════════")
        
        stopVibrationAndSound()
        countdownHandler?.removeCallbacksAndMessages(null)

        try {
            overlayView?.let {
                windowManager?.removeView(it)
                Log.d(TAG, "✅ Overlay removed from window")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error removing overlay: ${e.message}")
        }
        
        overlayView = null
        isShowing = false
        currentTripId = null
    }

    override fun onDestroy() {
        Log.d(TAG, "╔═══════════════════════════════════════════════════")
        Log.d(TAG, "🔧 OverlayService onDestroy")
        Log.d(TAG, "╚═══════════════════════════════════════════════════")
        
        hideOverlay()
        super.onDestroy()
    }

    private fun calculateDistance(lat1: Double, lng1: Double, lat2: Double, lng2: Double): Double {
        val earthRadius = 6371.0

        val dLat = Math.toRadians(lat2 - lat1)
        val dLng = Math.toRadians(lng2 - lng1)

        val a = Math.sin(dLat / 2) * Math.sin(dLat / 2) +
                Math.cos(Math.toRadians(lat1)) * Math.cos(Math.toRadians(lat2)) *
                Math.sin(dLng / 2) * Math.sin(dLng / 2)

        val c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a))

        return earthRadius * c
    }

    private fun extractMainArea(fullAddress: String?): String {
        if (fullAddress == null || fullAddress.isEmpty()) return "Location"
        
        val parts = fullAddress.split(",")
        return when {
            parts.size >= 2 -> "${parts[0].trim()}, ${parts[1].trim()}"
            parts.size == 1 -> {
                val trimmed = parts[0].trim()
                if (trimmed.length > 40) "${trimmed.substring(0, 40)}..." else trimmed
            }
            else -> if (fullAddress.length > 40) "${fullAddress.substring(0, 40)}..." else fullAddress
        }
    }
}