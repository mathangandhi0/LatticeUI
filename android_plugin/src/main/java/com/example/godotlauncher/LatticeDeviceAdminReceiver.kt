package com.example.godotlauncher

import android.app.admin.DeviceAdminReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

class LatticeDeviceAdminReceiver : DeviceAdminReceiver() {
    override fun onEnabled(context: Context, intent: Intent) {
        super.onEnabled(context, intent)
        Log.i("GodotAppLoader", "LatticeDeviceAdminReceiver: Device Admin enabled for lock screen")
    }

    override fun onDisabled(context: Context, intent: Intent) {
        super.onDisabled(context, intent)
        Log.i("GodotAppLoader", "LatticeDeviceAdminReceiver: Device Admin disabled")
    }
}
