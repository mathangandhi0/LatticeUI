package com.example.godotlauncher

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.PixelFormat
import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
import android.media.ImageReader
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.util.DisplayMetrics
import android.util.Log
import android.view.WindowManager
import java.io.File
import java.io.FileOutputStream

/**
 * V4.77b: Foreground Service for MediaProjection wallpaper capture.
 * 
 * On Android 14+, startForeground() MUST be called BEFORE getMediaProjection().
 * This service handles the entire capture lifecycle:
 *   1. Starts as foreground service
 *   2. Creates MediaProjection from consent result
 *   3. Captures one frame via VirtualDisplay + ImageReader
 *   4. Saves as managed_wallpaper.jpg
 *   5. Stops itself
 */
class ScreenCaptureService : Service() {

    companion object {
        const val CHANNEL_ID = "wallpaper_capture_channel"
        const val NOTIFICATION_ID = 7701
        const val EXTRA_RESULT_CODE = "result_code"
        const val EXTRA_RESULT_DATA = "result_data"
        const val MANAGED_WP_FILENAME = "managed_wallpaper.jpg"
        
        // Callback to notify AppLoader when capture is complete
        var onCaptureComplete: (() -> Unit)? = null
    }

    private var mediaProjection: MediaProjection? = null
    private var virtualDisplay: VirtualDisplay? = null
    private var imageReader: ImageReader? = null

    override fun onCreate() {
        super.onCreate()
        Log.e("ScreenCaptureService", "V4.77b: onCreate")
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Log.e("ScreenCaptureService", "V4.77b: onStartCommand — starting foreground FIRST")
        
        // CRITICAL: startForeground() MUST be called BEFORE getMediaProjection()
        val notification = buildNotification()
        startForeground(NOTIFICATION_ID, notification)
        Log.e("ScreenCaptureService", "V4.77b: startForeground called successfully")
        
        // Now get the consent result data
        val resultCode = intent?.getIntExtra(EXTRA_RESULT_CODE, -1) ?: -1
        val resultData = intent?.getParcelableExtra<Intent>(EXTRA_RESULT_DATA)
        
        if (resultCode == -1 || resultData == null) {
            Log.e("ScreenCaptureService", "V4.77b: Missing result data — stopping")
            stopSelf()
            return START_NOT_STICKY
        }
        
        Log.e("ScreenCaptureService", "V4.77b: Got consent result, creating MediaProjection...")
        
        // NOW safe to call getMediaProjection (after startForeground)
        try {
            val projectionManager = getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
            mediaProjection = projectionManager.getMediaProjection(resultCode, resultData)
            
            if (mediaProjection == null) {
                Log.e("ScreenCaptureService", "V4.77b: MediaProjection is NULL!")
                stopSelf()
                return START_NOT_STICKY
            }
            
            Log.e("ScreenCaptureService", "V4.77b: MediaProjection created successfully — starting capture")
            performCapture()
        } catch (e: Exception) {
            Log.e("ScreenCaptureService", "V4.77b: EXCEPTION creating MediaProjection: ${e.javaClass.name}: ${e.message}")
            e.printStackTrace()
            stopSelf()
        }
        
        return START_NOT_STICKY
    }

    private fun performCapture() {
        try {
            // Get screen dimensions
            val displayMetrics = DisplayMetrics()
            val windowManager = getSystemService(Context.WINDOW_SERVICE) as WindowManager
            @Suppress("DEPRECATION")
            windowManager.defaultDisplay.getRealMetrics(displayMetrics)
            val screenWidth = displayMetrics.widthPixels
            val screenHeight = displayMetrics.heightPixels
            val screenDensity = displayMetrics.densityDpi

            Log.e("ScreenCaptureService", "V4.77b: Screen: ${screenWidth}x${screenHeight} @ ${screenDensity}dpi")

            // Create ImageReader
            imageReader = ImageReader.newInstance(screenWidth, screenHeight, PixelFormat.RGBA_8888, 2)

            // Create VirtualDisplay
            virtualDisplay = mediaProjection!!.createVirtualDisplay(
                "WallpaperCapture",
                screenWidth, screenHeight, screenDensity,
                DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR,
                imageReader!!.surface,
                null, null
            )

            Log.e("ScreenCaptureService", "V4.77b: VirtualDisplay created — waiting 800ms for frame...")

            // Wait for a frame to be rendered, then capture
            Handler(Looper.getMainLooper()).postDelayed({
                try {
                    val image = imageReader?.acquireLatestImage()
                    if (image != null) {
                        Log.e("ScreenCaptureService", "V4.77b: Got image! Processing...")
                        
                        val planes = image.planes
                        val buffer = planes[0].buffer
                        val pixelStride = planes[0].pixelStride
                        val rowStride = planes[0].rowStride
                        val rowPadding = rowStride - pixelStride * screenWidth

                        val bitmap = Bitmap.createBitmap(
                            screenWidth + rowPadding / pixelStride,
                            screenHeight,
                            Bitmap.Config.ARGB_8888
                        )
                        bitmap.copyPixelsFromBuffer(buffer)
                        image.close()

                        // Crop to exact screen size
                        val croppedBitmap = Bitmap.createBitmap(bitmap, 0, 0, screenWidth, screenHeight)
                        if (croppedBitmap != bitmap) bitmap.recycle()

                        // Save as managed wallpaper
                        val outFile = File(filesDir, MANAGED_WP_FILENAME)
                        FileOutputStream(outFile).use { output ->
                            croppedBitmap.compress(Bitmap.CompressFormat.JPEG, 95, output)
                        }
                        croppedBitmap.recycle()

                        Log.e("ScreenCaptureService", "V4.77b: *** WALLPAPER CAPTURED AND SAVED! *** -> ${outFile.absolutePath}")
                        
                        // Notify AppLoader
                        onCaptureComplete?.invoke()
                    } else {
                        Log.e("ScreenCaptureService", "V4.77b: acquireLatestImage returned NULL — no frame captured")
                    }
                } catch (e: Exception) {
                    Log.e("ScreenCaptureService", "V4.77b: Frame processing error: ${e.javaClass.name}: ${e.message}")
                    e.printStackTrace()
                } finally {
                    cleanup()
                }
            }, 800)
        } catch (e: Exception) {
            Log.e("ScreenCaptureService", "V4.77b: Capture setup error: ${e.javaClass.name}: ${e.message}")
            e.printStackTrace()
            cleanup()
        }
    }

    private fun cleanup() {
        Log.e("ScreenCaptureService", "V4.77b: Cleanup — releasing resources")
        try { virtualDisplay?.release() } catch (e: Exception) {}
        try { imageReader?.close() } catch (e: Exception) {}
        try { mediaProjection?.stop() } catch (e: Exception) {}
        mediaProjection = null
        virtualDisplay = null
        imageReader = null
        stopSelf()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        super.onDestroy()
        Log.e("ScreenCaptureService", "V4.77b: onDestroy — service stopped")
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Wallpaper Sync",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Captures wallpaper for blur effect"
                setShowBadge(false)
            }
            val manager = getSystemService(NotificationManager::class.java)
            manager?.createNotificationChannel(channel)
        }
    }

    private fun buildNotification(): Notification {
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        return builder
            .setContentTitle("Syncing Wallpaper")
            .setContentText("Capturing wallpaper for blur effect...")
            .setSmallIcon(android.R.drawable.ic_menu_gallery)
            .build()
    }
}
