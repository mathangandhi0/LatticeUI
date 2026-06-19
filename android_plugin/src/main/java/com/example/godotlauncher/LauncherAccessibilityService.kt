package com.example.godotlauncher

import android.accessibilityservice.AccessibilityService
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.hardware.HardwareBuffer
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.Display
import android.view.accessibility.AccessibilityEvent
import java.io.File
import java.io.FileOutputStream
import java.util.concurrent.Executors

class LauncherAccessibilityService : AccessibilityService() {

    companion object {
        var instance: LauncherAccessibilityService? = null
        const val MANAGED_WP_FILENAME = "managed_wallpaper.jpg"

        fun lockScreen(): Boolean {
            val service = instance
            if (service != null) {
                return service.performGlobalAction(GLOBAL_ACTION_LOCK_SCREEN)
            }
            return false
        }

        /**
         * V4.78: Take a screenshot of the entire display.
         * Requires API 30+ and the accessibility service must be enabled.
         * The screenshot captures everything on screen including the wallpaper.
         * 
         * @param onComplete Called on the main thread when capture finishes (true=success, false=fail)
         */
        fun captureScreen(onComplete: (Boolean) -> Unit) {
            val service = instance
            if (service == null) {
                Log.e("GodotAppLoader", "V4.78: Accessibility service is NOT connected — cannot capture")
                onComplete(false)
                return
            }

            if (Build.VERSION.SDK_INT < 30) {
                Log.e("GodotAppLoader", "V4.78: takeScreenshot requires API 30+, current: ${Build.VERSION.SDK_INT}")
                onComplete(false)
                return
            }

            Log.e("GodotAppLoader", "V4.78: Taking accessibility screenshot...")
            val executor = Executors.newSingleThreadExecutor()

            service.takeScreenshot(
                Display.DEFAULT_DISPLAY,
                executor,
                object : TakeScreenshotCallback {
                    override fun onSuccess(screenshotResult: ScreenshotResult) {
                        Log.e("GodotAppLoader", "V4.78: Screenshot SUCCESS! Processing...")
                        try {
                            val hardwareBuffer = screenshotResult.hardwareBuffer
                            val colorSpace = screenshotResult.colorSpace

                            val bitmap = Bitmap.wrapHardwareBuffer(hardwareBuffer, colorSpace)
                            hardwareBuffer.close()

                            if (bitmap == null) {
                                Log.e("GodotAppLoader", "V4.78: wrapHardwareBuffer returned NULL")
                                Handler(Looper.getMainLooper()).post { onComplete(false) }
                                return
                            }

                            // Convert to software bitmap for JPEG compression
                            val softBitmap = bitmap.copy(Bitmap.Config.ARGB_8888, false)
                            bitmap.recycle()

                            if (softBitmap == null) {
                                Log.e("GodotAppLoader", "V4.78: Failed to copy to software bitmap")
                                Handler(Looper.getMainLooper()).post { onComplete(false) }
                                return
                            }

                            // Save to app's internal storage
                            val outFile = File(service.filesDir, MANAGED_WP_FILENAME)
                            FileOutputStream(outFile).use { output ->
                                softBitmap.compress(Bitmap.CompressFormat.JPEG, 95, output)
                            }
                            softBitmap.recycle()

                            Log.e("GodotAppLoader", "V4.78: *** WALLPAPER CAPTURED AND SAVED *** -> ${outFile.absolutePath} (${outFile.length()} bytes)")
                            Handler(Looper.getMainLooper()).post { onComplete(true) }
                        } catch (e: Exception) {
                            Log.e("GodotAppLoader", "V4.78: Screenshot process error: ${e.javaClass.name}: ${e.message}")
                            e.printStackTrace()
                            Handler(Looper.getMainLooper()).post { onComplete(false) }
                        }
                    }

                    override fun onFailure(errorCode: Int) {
                        Log.e("GodotAppLoader", "V4.78: Screenshot FAILED with errorCode=$errorCode")
                        Handler(Looper.getMainLooper()).post { onComplete(false) }
                    }
                }
            )
        }
    }

    override fun onCreate() {
        super.onCreate()
        Log.e("GodotAppLoader", "ACCESSIBILITY: Service onCreate")
    }

    override fun onServiceConnected() {
        super.onServiceConnected()
        instance = this
        Log.e("GodotAppLoader", "ACCESSIBILITY: Service Connected! Instance set to $this")
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        // Not used, but required to override
    }

    override fun onInterrupt() {
        instance = null
        Log.d("GodotAppLoader", "Accessibility Service Interrupted")
    }
    
    override fun onDestroy() {
        super.onDestroy()
        instance = null
    }
}
