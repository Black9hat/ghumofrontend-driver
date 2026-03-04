package com.example.drivergo

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

class BootReceiver : BroadcastReceiver() {
    
    companion object {
        private const val TAG = "BootReceiver"
    }
    
    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            Intent.ACTION_BOOT_COMPLETED,
            "android.intent.action.QUICKBOOT_POWERON",
            Intent.ACTION_MY_PACKAGE_REPLACED -> {
                Log.d(TAG, "📱 Boot/Update received - checking driver state...")
                
                // Check if driver was online before reboot
                val prefs = context.getSharedPreferences(
                    "FlutterSharedPreferences", 
                    Context.MODE_PRIVATE
                )
                
                val isOnline = prefs.getBoolean("flutter.isOnline", false)
                val driverId = prefs.getString("flutter.driverId", null)
                
                if (isOnline && driverId != null) {
                    Log.d(TAG, "✅ Driver was online - will restore when app opens")
                    // The app will handle restoration when opened
                    // Or you can start a service here to reconnect socket
                } else {
                    Log.d(TAG, "ℹ️ Driver was offline - no action needed")
                }
            }
        }
    }
}