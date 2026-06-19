package com.example.godotlauncher

import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.drawable.BitmapDrawable
import android.graphics.drawable.Drawable
import android.util.Base64
import android.util.Log
import android.widget.Toast
import android.net.Uri
import android.provider.Settings
import android.content.Context
import android.view.WindowManager
import android.view.Display
import android.os.Vibrator
import java.util.concurrent.ConcurrentHashMap
import android.os.VibrationEffect
import android.os.Build
import android.app.WallpaperManager
import org.godotengine.godot.Godot
import org.godotengine.godot.GodotLib
import org.godotengine.godot.plugin.GodotPlugin
import org.godotengine.godot.plugin.UsedByGodot
import org.json.JSONArray
import org.json.JSONObject
import android.renderscript.Allocation
import android.renderscript.Element
import android.renderscript.RenderScript
import android.renderscript.ScriptIntrinsicBlur
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.FileOutputStream
import java.io.InputStream
import android.graphics.LinearGradient
import android.graphics.Shader
import android.graphics.Color
import android.app.WallpaperColors

import android.view.View
import android.graphics.Rect
import android.util.DisplayMetrics
import org.godotengine.godot.plugin.SignalInfo

import android.content.BroadcastReceiver
import android.content.IntentFilter

import android.accessibilityservice.AccessibilityService
import android.app.usage.UsageStats
import android.app.usage.UsageStatsManager
import java.util.Collections
import java.util.Comparator
import java.util.Calendar

// V4.77: MediaProjection Wallpaper Capture
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.media.ImageReader
import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
import android.graphics.PixelFormat
import android.os.Handler
import android.os.Looper


class AppLoader(godot: Godot) : GodotPlugin(godot) {

    init {
        Log.e("GodotAppLoader", "V4.76j PLUGIN INITIALIZED - Discovery Start")
        try {
            for (m in this.javaClass.methods) {
                if (m.isAnnotationPresent(UsedByGodot::class.java)) {
                    Log.e("GodotAppLoader", "V4.76j Discovery: Method '${m.name}' is correctly marked @UsedByGodot")
                }
            }
        } catch (e: Exception) {
            Log.e("GodotAppLoader", "V4.76j Reflection Error", e)
        }
    }

    override fun getPluginName(): String {
        Log.e("GodotAppLoader", "getPluginName called")
        return "AppLoader"
    }

    override fun getPluginSignals(): Set<SignalInfo> {
        Log.e("GodotAppLoader", "getPluginSignals called")
        return setOf(
            SignalInfo("package_changed", String::class.java), 
            SignalInfo("home_pressed"),
            SignalInfo("on_wallpaper_changed")
        )
    }

    override fun getPluginMethods(): List<String> {
        Log.e("GodotAppLoader", "V4.76j: getPluginMethods() called")
        return listOf(
            "vibrate",
            "make_toast",
            "get_installed_apps",
            "get_installed_icon_packs",
            "set_active_icon_pack",
            "set_active_icon_shape",
            "get_blurred_wallpaper",
            "get_unblurred_wallpaper",
            "get_wp_id_v2",
            "ping",
            "get_plugin_methods",
            "pick_launcher_wallpaper",
            "request_usage_permission",
            "check_usage_permission",
            "select_default_launcher",
            "open_app_info",
            "launch_app",
            "get_long_press_time_ms",
            "get_keyboard_height",
            "fetch_usage_stats",
            "set_system_bars_visibility",
            "update_system_ui",
            "refresh_frame_pacing",
            "capture_wallpaper"
        )
    }

    // V4.76d: Renamed to avoid any potential collision



    // Reliance on @UsedByGodot reflection for Godot 4.x
    
    private var isAppInForeground = false
    private var lastFramePacingTriggerTime = 0L
    private var hasTriggeredStartupFix = false
    private var isFramePacingInProgress = false
    private var forceBounceOnResume = false
    private val PICK_WALLPAPER_REQ_CODE = 46301
    private val SCREEN_CAPTURE_REQ_CODE = 46302  // V4.77
    private val MANAGED_WP_FILENAME = "managed_wallpaper.jpg"
    private var lastProcessedIntent: Intent? = null
    private var mediaProjection: MediaProjection? = null  // V4.77
    private var lastKnownWpId: Int = -1  // V4.77: Track wallpaper changes on resume

    private val receiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            val action = intent?.action
            Log.d("GodotAppLoader", "Broadcast received: $action")
            
            if (action == "com.example.godotlauncher.HOME_PRESSED") {
                Log.d("GodotAppLoader", "Home signal -> Emitting Signal")
                emitSignal("home_pressed")
            } else if (action == Intent.ACTION_WALLPAPER_CHANGED) {
                Log.e("GodotAppLoader", "CRITICAL: ACTION_WALLPAPER_CHANGED Caught!")
                // V4.78: Removed toast to prevent screen pollution during capture
                importSystemWallpaper()
                emitSignal("on_wallpaper_changed")
            } else {
                val pkgName = intent?.data?.schemeSpecificPart
                if (pkgName == context?.packageName) {
                    Log.d("GodotAppLoader", "Package change for SELF -> Ignoring to prevent flicker")
                    return
                }
                
                // V14.28: Selective Cache Clearing
                // Instead of wiping everything, we only remove the package that changed.
                // This preserves the rest of the icons for a much faster refresh.
                if (pkgName != null && pkgName.isNotEmpty()) {
                    Log.d("GodotAppLoader", "Selective Cache Clear for: $pkgName")
                    val keysToRemove = processedIconCache.keys.filter { it.startsWith("$pkgName:") || it == pkgName }
                    keysToRemove.forEach { processedIconCache.remove(it) }
                } else {
                    Log.d("GodotAppLoader", "Package change (Unknown) -> Full cache clear")
                    processedIconCache.clear()
                }
                
                emitSignal("package_changed", pkgName ?: "")
            }
        }
    }

    override fun onMainResume() {
        super.onMainResume()
        isAppInForeground = true
        Log.d("GodotAppLoader", "LIFECYCLE: onMainResume called. Foreground = true")
        // Enforce Transparency on Resume
        update_system_ui()
        
        // V4.68: Re-check intent in case we were resumed with a new wallpaper intent
        activity?.intent?.let { 
            if (it != lastProcessedIntent) {
                handleWallpaperIntent(it)
            }
        }
        
        Log.d("GodotAppLoader", "STABILITY: Bounce/Phoenix logic disabled to fix blank screen loop")

        // V4.78: Detect wallpaper change on resume (broadcast may not work on all devices)
        try {
            val wallpaperManager = WallpaperManager.getInstance(activity)
            val currentWpId = try { wallpaperManager.getWallpaperId(WallpaperManager.FLAG_SYSTEM) } catch(e: Exception) { -1 }
            
            if (lastKnownWpId != -1 && currentWpId != lastKnownWpId) {
                Log.e("GodotAppLoader", "V4.78: Wallpaper ID changed on resume ($lastKnownWpId -> $currentWpId)")
                
                if (Build.VERSION.SDK_INT >= 30 && LauncherAccessibilityService.instance != null) {
                    // V4.78: Use AccessibilityService screenshot — no consent dialog needed
                    Log.e("GodotAppLoader", "V4.78: Accessibility service available — taking screenshot")
                    val act = activity!!

                    // Step 1: Hide the ENTIRE window content (total invisibility to screenshot)
                    act.runOnUiThread {
                        val params = act.window.attributes
                        params.alpha = 0f
                        act.window.attributes = params
                    }

                    // Step 2: Wait for UI to hide and animations (like wallpaper picker close) to finish
                    // 1.5s is safe for most system transitions
                    Handler(Looper.getMainLooper()).postDelayed({
                        Log.e("GodotAppLoader", "V4.78: Taking screenshot NOW")
                        LauncherAccessibilityService.captureScreen { success ->
                            // Step 3: Restore window visibility
                            act.runOnUiThread {
                                val params = act.window.attributes
                                params.alpha = 1f
                                act.window.attributes = params
                            }

                            if (success) {
                                Log.e("GodotAppLoader", "V4.78: *** Wallpaper capture SUCCESS — emitting signal ***")
                                make_toast("Wallpaper synced!")
                                emitSignal("on_wallpaper_changed")
                            } else {
                                Log.e("GodotAppLoader", "V4.78: Capture failed — falling back to import")
                                importSystemWallpaper()
                                emitSignal("on_wallpaper_changed")
                            }
                        }
                    }, 1500)
                } else if (Build.VERSION.SDK_INT >= 30) {
                    // Accessibility not enabled — prompt user
                    Log.e("GodotAppLoader", "V4.78: Accessibility service NOT connected — prompting user")
                    make_toast("Enable Lattice Accessibility in Settings for wallpaper blur sync")
                    importSystemWallpaper()
                    emitSignal("on_wallpaper_changed")
                } else {
                    // Older Android: Direct import works
                    importSystemWallpaper()
                    emitSignal("on_wallpaper_changed")
                }
            }
            lastKnownWpId = currentWpId
            Log.d("GodotAppLoader", "V4.78: Current wallpaper ID: $currentWpId")
        } catch (e: Exception) {
            Log.e("GodotAppLoader", "V4.77: Wallpaper ID check failed", e)
        }
    }

    fun onNewIntent(intent: Intent) {
        Log.d("GodotAppLoader", "LIFECYCLE: onNewIntent called")
        handleWallpaperIntent(intent)
        
        if (intent.action == Intent.ACTION_MAIN && intent.hasCategory(Intent.CATEGORY_HOME)) {
            Log.d("GodotAppLoader", "HOME BUTTON PRESSED (NewIntent)")
            emitSignal("home_pressed")
        }
    }

    override fun onMainPause() {
        super.onMainPause()
        isAppInForeground = false
        Log.d("GodotAppLoader", "LIFECYCLE: onMainPause called. Foreground = false")
    }

    @UsedByGodot
    fun refresh_frame_pacing() {
        val now = System.currentTimeMillis()
        if (now - lastFramePacingTriggerTime < 2000) {
            Log.d("GodotAppLoader", "FRAME_PACING: Throttled (last was ${(now - lastFramePacingTriggerTime)}ms ago)")
            return 
        }
        lastFramePacingTriggerTime = now
        
        Log.d("GodotAppLoader", "FRAME_PACING: refresh_frame_pacing executing")
        activity?.let { act ->
            try {
                act.runOnUiThread {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        val display = act.windowManager?.defaultDisplay
                        val modes = display?.supportedModes
                        if (modes != null && modes.isNotEmpty()) {
                            val highestMode = modes.maxByOrNull { it.refreshRate }
                            if (highestMode != null) {
                                val params = act.window.attributes
                                if (params.preferredDisplayModeId != highestMode.modeId) {
                                    params.preferredDisplayModeId = highestMode.modeId
                                    act.window.attributes = params
                                    Log.d("GodotAppLoader", "Set display mode to: ${highestMode.refreshRate}Hz")
                                }
                            }
                        }
                    }
                }
                
                GodotLib.calldeferred(0, "window_set_vsync_mode", arrayOf<Any>(1))
            } catch (e: Exception) {
                Log.e("GodotAppLoader", "Error refreshing frame pacing", e)
            }
        }
    }

    override fun onMainCreate(activity: Activity?): View? {
        try {
            // Filter 1: Package Changes (Requires "package" data scheme)
            val pkgFilter = IntentFilter().apply {
                addAction(Intent.ACTION_PACKAGE_ADDED)
                addAction(Intent.ACTION_PACKAGE_REMOVED)
                addAction(Intent.ACTION_PACKAGE_CHANGED)
                addDataScheme("package")
            }
            
            // Filter 2: Global Signals (Must NOT have a data scheme)
            val signalFilter = IntentFilter().apply {
                addAction(Intent.ACTION_WALLPAPER_CHANGED)
                addAction("com.example.godotlauncher.HOME_PRESSED")
            }

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                activity?.registerReceiver(receiver, pkgFilter, Context.RECEIVER_EXPORTED)
                activity?.registerReceiver(receiver, signalFilter, Context.RECEIVER_EXPORTED)
            } else {
                activity?.registerReceiver(receiver, pkgFilter)
                activity?.registerReceiver(receiver, signalFilter)
            }
            Log.d("GodotAppLoader", "V4.66: Receivers registered separately (Package vs Signals)")
            
            // V4.63: Check for incoming 3rd party wallpaper intent
            activity?.intent?.let { handleWallpaperIntent(it) }

            // Apply Immersive Mode (Transparent Bars)
            update_system_ui()
            
        } catch (e: Exception) {
            Log.e("GodotAppLoader", "Error registering receiver", e)
        }
        return null
    }

    @UsedByGodot
    fun set_system_bars_visibility(showStatus: Boolean, showNav: Boolean) {
        activity?.runOnUiThread {
            try {
                val window = activity?.window ?: return@runOnUiThread
                val decorView = window.decorView
                
                if (Build.VERSION.SDK_INT >= 30) {
                    val controller = window.insetsController
                    if (controller != null) {
                        // Status Bar
                        if (showStatus) {
                            controller.show(android.view.WindowInsets.Type.statusBars())
                        } else {
                            controller.hide(android.view.WindowInsets.Type.statusBars())
                        }
                        
                        // Nav Bar
                        if (showNav) {
                            controller.show(android.view.WindowInsets.Type.navigationBars())
                        } else {
                            controller.hide(android.view.WindowInsets.Type.navigationBars())
                        }
                        
                        // Behavior: System bars are revealed by a swipe, and then hide again
                        controller.systemBarsBehavior = android.view.WindowInsetsController.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
                    }
                } else {
                    // Legacy for older Android
                    var flags = decorView.systemUiVisibility
                    
                    if (showStatus) {
                        flags = flags and android.view.View.SYSTEM_UI_FLAG_FULLSCREEN.inv()
                    } else {
                        flags = flags or android.view.View.SYSTEM_UI_FLAG_FULLSCREEN
                    }
                    
                    if (showNav) {
                        flags = flags and android.view.View.SYSTEM_UI_FLAG_HIDE_NAVIGATION.inv()
                    } else {
                        flags = flags or android.view.View.SYSTEM_UI_FLAG_HIDE_NAVIGATION
                    }
                    
                    flags = flags or android.view.View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY
                    decorView.systemUiVisibility = flags
                }
                Log.d("GodotAppLoader", "Set System Bars: status=$showStatus, nav=$showNav")
            } catch (e: Exception) {
                Log.e("GodotAppLoader", "Error setting System Bars visibility", e)
            }
        }
    }

    @UsedByGodot
    fun update_system_ui() {
        activity?.runOnUiThread {
            try {
                val window = activity?.window
                if (window != null) {
                    // 1. Extend content behind bars (Immersive)
                    window.setFlags(
                        WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
                        WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS
                    )
                    
                    // 2. Force Transparent Colors (API 21+)
                    window.addFlags(WindowManager.LayoutParams.FLAG_DRAWS_SYSTEM_BAR_BACKGROUNDS)
                    window.statusBarColor = 0x00000000 // Transparent
                    window.navigationBarColor = 0x00000000 // Transparent
                    
                    // 3. Ensure we don't have conflicting flags
                    // window.clearFlags(WindowManager.LayoutParams.FLAG_TRANSLUCENT_STATUS)
                    // window.clearFlags(WindowManager.LayoutParams.FLAG_TRANSLUCENT_NAVIGATION)
                    
                    // 4. Set Decor Fits System Windows (API 30+)
                    if (Build.VERSION.SDK_INT >= 30) {
                        // We can't use WindowCompat without AndroidX easily if not imported,
                        // but we can try the native method setDecorFitsSystemWindows(false) via the WindowController or just Window.
                         window.setDecorFitsSystemWindows(false)
                    }

                    // 5. Handle Display Cutout (Notch) - Critical for Status Bar
                    if (Build.VERSION.SDK_INT >= 28) {
                        val params = window.attributes
                        params.layoutInDisplayCutoutMode = WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
                        window.attributes = params
                    }
                    
                    Log.d("GodotAppLoader", "Applied Transparent System UI (Aggressive)")
                }
            } catch (e: Exception) {
                Log.e("GodotAppLoader", "Error updating System UI", e)
            }
        }
    }

    @UsedByGodot
    fun force_high_refresh_rate() {
        activity?.runOnUiThread {
            try {
                if (Build.VERSION.SDK_INT >= 23) {
                    val window = activity?.window
                    val windowManager = activity?.windowManager
                    val display = windowManager?.defaultDisplay 
                    
                    if (display != null && window != null) {
                        val supportedModes = display.supportedModes
                        var bestMode = display.mode
                        var maxRate = 0f
                        
                        // Find the mode with the highest refresh rate matching our resolution
                        for (mode in supportedModes) {
                            if (mode.physicalWidth == bestMode.physicalWidth && 
                                mode.physicalHeight == bestMode.physicalHeight) {
                                
                                if (mode.refreshRate > maxRate) {
                                    maxRate = mode.refreshRate
                                    bestMode = mode
                                }
                            }
                        }
                        
                        if (maxRate > 60.1f) {
                            Log.d("GodotAppLoader", "Force High Refresh: Requesting Mode ID " + bestMode.modeId + " (" + maxRate + "Hz)")
                            val params = window.attributes
                            params.preferredDisplayModeId = bestMode.modeId
                            window.attributes = params
                        } else {
                            Log.d("GodotAppLoader", "Force High Refresh: No high refresh rate mode found (Max: " + maxRate + ")")
                        }
                    }
                }
            } catch (e: Exception) {
                Log.e("GodotAppLoader", "Error forcing high refresh rate", e)
            }
        }
    }


    @UsedByGodot
    fun test_ping(): Int {
        return 123
    }

    @UsedByGodot
    fun test_ping_str(): String {
        return "PONG"
    }

    @UsedByGodot
    fun test_ping_dict(): org.godotengine.godot.Dictionary {
        val dict = org.godotengine.godot.Dictionary()
        dict.put("pong", "true")
        return dict
    }

    private var initialContentHeight = 0
    
    @UsedByGodot
    fun get_keyboard_height(): Int {
        try {
            val rootView = activity?.window?.decorView ?: return 0
            
            // API 30+ (Android 11+): Use WindowInsets for IME height
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                val insets = rootView.rootWindowInsets
                if (insets != null) {
                    val imeInsets = insets.getInsets(android.view.WindowInsets.Type.ime())
                    val imeHeight = imeInsets.bottom
                    Log.d("GodotAppLoader", "Keyboard detection (Insets API 30+): imeHeight=$imeHeight")
                    return if (imeHeight > 100) imeHeight else 0
                }
            }
            
            // API 23-29: Use getInsets with ime() type via reflection fallback
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                val insets = rootView.rootWindowInsets
                if (insets != null) {
                    // Try system window insets as fallback
                    val bottom = insets.systemWindowInsetBottom
                    Log.d("GodotAppLoader", "Keyboard detection (Insets API 23-29): systemBottom=$bottom")
                    // This includes nav bar, so only return if > 300 (likely keyboard)
                    return if (bottom > 400) bottom else 0
                }
            }
            
            // Fallback for older APIs: Use visible display frame
            val visibleRect = Rect()
            rootView.getWindowVisibleDisplayFrame(visibleRect)
            val dm = DisplayMetrics()
            @Suppress("DEPRECATION")
            activity?.windowManager?.defaultDisplay?.getRealMetrics(dm)
            val keyboardHeight = dm.heightPixels - visibleRect.bottom
            Log.d("GodotAppLoader", "Keyboard detection (Legacy): screen=${dm.heightPixels}, visibleBottom=${visibleRect.bottom}, keyboard=$keyboardHeight")
            return if (keyboardHeight > 200) keyboardHeight else 0
            
        } catch (e: Exception) {
            Log.e("GodotAppLoader", "Error getting keyboard height", e)
            return 0
        }
    }

    @UsedByGodot
    fun get_battery_level(): Int {
        try {
            val act = getActivity()
            if (act == null) return -1
            
            // Method 1: BatteryManager (API 21+)
            if (android.os.Build.VERSION.SDK_INT >= 21) {
                val bm = act.getSystemService(Context.BATTERY_SERVICE) as android.os.BatteryManager
                val level = bm.getIntProperty(android.os.BatteryManager.BATTERY_PROPERTY_CAPACITY)
                if (level > 0) return level
            }
        } catch (e: Exception) {
             Log.e("GodotAppLoader", "BatteryManager failed", e)
        }

        try {
            val act = getActivity()
            if (act == null) return -1
            
            // Method 2: Sticky Intent (Fallback)
            val intentFilter = IntentFilter(Intent.ACTION_BATTERY_CHANGED)
            val batteryStatus = act.registerReceiver(null, intentFilter)
            val level = batteryStatus?.getIntExtra(android.os.BatteryManager.EXTRA_LEVEL, -1) ?: -1
            val scale = batteryStatus?.getIntExtra(android.os.BatteryManager.EXTRA_SCALE, -1) ?: -1
            
            if (level != -1 && scale != -1) {
                return (level * 100 / scale.toFloat()).toInt()
            }
        } catch (e: Exception) {
            Log.e("GodotAppLoader", "Sticky Intent failed", e)
        }
        
        return -2 // Code for total failure
    }

    @UsedByGodot
    fun is_charging(): Boolean {
        try {
            val act = getActivity()
            if (act == null) return false
            
            val intentFilter = IntentFilter(Intent.ACTION_BATTERY_CHANGED)
            val batteryStatus = act.registerReceiver(null, intentFilter)
            val status = batteryStatus?.getIntExtra(android.os.BatteryManager.EXTRA_STATUS, -1) ?: -1
            return status == android.os.BatteryManager.BATTERY_STATUS_CHARGING || 
                   status == android.os.BatteryManager.BATTERY_STATUS_FULL
        } catch (e: Exception) {
            Log.e("GodotAppLoader", "Error getting charging status", e)
            return false
        }
    }

    override fun onMainDestroy() {

        super.onMainDestroy()
        try {
            activity?.unregisterReceiver(receiver)
        } catch (e: Exception) {
            Log.e("GodotAppLoader", "Error unregistering receiver", e)
        }
    }

    @UsedByGodot
    fun get_installed_apps(): String {
        val act = getActivity()
        if (act == null) {
            Log.e("GodotAppLoader", "get_installed_apps ABORT: activity is null")
            return "{}"
        }
        val packageManager = act.packageManager
        val appsList = JSONArray()
        Log.e("GodotAppLoader", "get_installed_apps called. packageManager=${packageManager != null}")
        val intent = Intent(Intent.ACTION_MAIN, null)
        intent.addCategory(Intent.CATEGORY_LAUNCHER)

        val availableActivities = packageManager.queryIntentActivities(intent, 0)
        
        Log.e("GodotAppLoader", "Found ${availableActivities.size} apps in system")
        
        // V62 DEBUG: Log the first few apps to verify JNI return
        if (availableActivities.isNotEmpty()) {
            Log.e("GodotAppLoader", "V62 DEBUG: Sample App: ${availableActivities[0].activityInfo.packageName}")
        }

        for (ri in availableActivities) {
            val appObj = JSONObject()
            val packageName = ri.activityInfo.packageName
            val className = ri.activityInfo.name
            val label = ri.loadLabel(packageManager).toString()
            val componentName = "ComponentInfo{$packageName/$className}"
            
            /* // REMOVED SYNC ICON LOADING
            var iconBase64 = ""
            val cacheKey = if (activeIconPackPkg.isNotEmpty()) "$packageName:$activeIconPackPkg" else packageName
            
            if (processedIconCache.containsKey(cacheKey)) {
                iconBase64 = processedIconCache[cacheKey]!!
            } else {
                if (activeIconPackPkg.isNotEmpty()) {
                    iconBase64 = get_icon_from_pack_internal(packageName, componentName, activeIconPackPkg)
                }
                
                if (iconBase64.isEmpty()) {
                    val iconDrawable = ri.loadIcon(packageManager)
                    iconBase64 = if (activeIconPackPkg.isNotEmpty() && (iconPackMask != null || iconPackBacks.isNotEmpty())) {
                        applyIconPackEffects(iconDrawable)
                    } else {
                        drawableToBase64(iconDrawable)
                    }
                }
                processedIconCache[cacheKey] = iconBase64
            }
            */

            appObj.put("name", label)
            appObj.put("pkg", packageName)
            // appObj.put("icon", iconBase64) // REMOVED: Icons are lazy-loaded now
            
            // Get PackageInfo for firstInstallTime
            try {
                val pi = packageManager.getPackageInfo(packageName, 0)
                appObj.put("firstInstallTime", pi.firstInstallTime)
            } catch (e: Exception) {
                appObj.put("firstInstallTime", 0)
            }
            
            // Category API added in Android O (API 26)
            if (android.os.Build.VERSION.SDK_INT >= 26) {
                appObj.put("category", ri.activityInfo.applicationInfo.category)
            } else {
                appObj.put("category", -1)
            }

            appsList.put(appObj)
        }

        val result = JSONObject()
        result.put("apps", appsList)
        result.put("battery_level", get_battery_level())
        result.put("is_charging", is_charging())
        
        val finalJson = result.toString()
        Log.e("GodotAppLoader", "get_installed_apps returning JSON length: ${finalJson.length}")
        return finalJson
    }

    @UsedByGodot
    fun get_app_icon(packageName: String): String {
        Log.e("GodotAppLoader", "DEBUG: get_app_icon called for $packageName")
        val cacheKey = if (activeIconPackPkg.isNotEmpty()) "$packageName:$activeIconPackPkg" else packageName
        
        if (processedIconCache.containsKey(cacheKey)) {
            Log.e("GodotAppLoader", "DEBUG: Returning cached icon for $packageName")
            return processedIconCache[cacheKey]!!
        }

        try {
            val act = getActivity() ?: return ""
            val pm = act.packageManager
            var iconBase64 = ""

            val myPkg = get_package_name()
            val isMainApp = packageName == myPkg || packageName == "com.lattice.ui" || packageName == "com.godot.game"
            val isVirtual = packageName.startsWith("virtual:")

            val launchIntent = pm.getLaunchIntentForPackage(packageName)
            val ri = if (launchIntent != null) pm.resolveActivity(launchIntent, 0) else null
            val componentName = if (ri != null) "ComponentInfo{${ri.activityInfo.packageName}/${ri.activityInfo.name}}" else ""

            // 1. ALWAYS try Icon Pack themed replacement first (Even for internal app)
            if (activeIconPackPkg.isNotEmpty() && componentName.isNotEmpty()) {
                iconBase64 = get_icon_from_pack_internal(packageName, componentName, activeIconPackPkg)
            }

            // 2. Main App / Virtual Logic (Fallback if not themed by pack)
            if (iconBase64.isEmpty() && (isMainApp || isVirtual)) {
                Log.d("GodotAppLoader", "V4.23: Internal Path for $packageName")
                var assetBytes = loadAsset("app_logo.png")
                if (assetBytes == null) assetBytes = loadAsset("icon.png")
                
                if (assetBytes != null) {
                    val originalBitmap = BitmapFactory.decodeByteArray(assetBytes, 0, assetBytes.size)
                    if (originalBitmap != null) {
                        // Check if we should apply Icon Pack Masking even to internal icons
                        if (activeIconPackPkg.isNotEmpty() && (iconPackMask != null || iconPackBacks.isNotEmpty())) {
                             val drawable = android.graphics.drawable.BitmapDrawable(act.resources, originalBitmap)
                             iconBase64 = applyIconPackEffects(drawable)
                        } else {
                            val targetScale = 1.20f
                            iconBase64 = mask_bitmap_internal(originalBitmap, targetScale)
                        }
                        originalBitmap.recycle()
                        if (iconBase64.isNotEmpty()) {
                            processedIconCache[cacheKey] = iconBase64
                            return iconBase64
                        }
                    }
                }
                if (packageName == "virtual:settings") return get_app_icon("com.android.settings")
            }

            // 3. App-Specific Recovery (Standard Apps)
            if (ri == null) return ""

            if (activeIconPackPkg.isNotEmpty()) {
                // If we didn't get a themed icon above, apply the mask to the original
                if (iconBase64.isEmpty()) {
                    val iconDrawable = ri.loadIcon(pm) 
                    if (iconDrawable != null) {
                        iconBase64 = applyIconPackEffects(iconDrawable)
                        Log.d("GodotAppLoader", "V4.23: Applied Icon Pack mask to $packageName")
                    }
                }
            } else {
                // No Icon Pack -> Force system shape on ALL apps
                val iconDrawable = ri.loadIcon(pm) 
                if (iconDrawable != null) {
                    iconBase64 = drawableToBase64WithShape(iconDrawable, activeIconShape)
                }
            }
            
            processedIconCache[cacheKey] = iconBase64
            return iconBase64
        } catch (e: Exception) {
            return ""
        }
    }

    private fun mask_bitmap_internal(originalBitmap: Bitmap, scale: Float): String {
        try {
            val targetSize = 256
            val bitmap = Bitmap.createBitmap(targetSize, targetSize, Bitmap.Config.ARGB_8888)
            val canvas = Canvas(bitmap)
            
            val path = createPathByName(activeIconShape, targetSize)
            
            // V4.17: PATH CLAMPING - Transform path to match icon scale
            // V4.21 FIX: Only clamp/shrink the mask if scale < 1.0. 
            // If scale > 1.0 (Bloom), we KEEP the mask at 1.0f to actually CLIP the zoomed icon.
            val maskScale = if (scale < 1.0f) scale else 1.0f
            val scaledSize = (targetSize * maskScale).toInt()
            val offset = (targetSize - scaledSize).toFloat() / 2f
            
            val matrix = android.graphics.Matrix()
            matrix.setScale(maskScale, maskScale)
            matrix.postTranslate(offset, offset)
            path.transform(matrix) 
            
            canvas.clipPath(path)
            
            // Plate color: Vibrant Lattice Blue
            val platePaint = android.graphics.Paint(android.graphics.Paint.ANTI_ALIAS_FLAG)
            platePaint.color = android.graphics.Color.parseColor("#232F4D") 
            canvas.drawPath(path, platePaint)
            
            val srcRect = android.graphics.Rect(0, 0, originalBitmap.width, originalBitmap.height)
            val dstRect = android.graphics.Rect(offset.toInt(), offset.toInt(), (offset + scaledSize).toInt(), (offset + scaledSize).toInt())
            
            canvas.drawBitmap(originalBitmap, srcRect, dstRect, android.graphics.Paint(android.graphics.Paint.FILTER_BITMAP_FLAG or android.graphics.Paint.ANTI_ALIAS_FLAG))
            
            // V4.72: Restore Icon Borders
            val borderPaint = android.graphics.Paint(android.graphics.Paint.ANTI_ALIAS_FLAG)
            borderPaint.color = android.graphics.Color.parseColor("#A0FFFFFF") // Subtle white border
            borderPaint.style = android.graphics.Paint.Style.STROKE
            borderPaint.strokeWidth = 5f
            canvas.drawPath(path, borderPaint)
            
            val outputStream = ByteArrayOutputStream()
            bitmap.compress(Bitmap.CompressFormat.PNG, 100, outputStream)
            val result = Base64.encodeToString(outputStream.toByteArray(), Base64.NO_WRAP)
            bitmap.recycle()
            return result
        } catch (e: Exception) {
            return ""
        }
    }

    @UsedByGodot
    fun get_installed_apps_with_shape(shape: String): String {
        val packageManager = activity!!.packageManager
        val appsList = JSONArray()

        val intent = Intent(Intent.ACTION_MAIN, null)
        intent.addCategory(Intent.CATEGORY_LAUNCHER)

        val availableActivities = packageManager.queryIntentActivities(intent, 0)
        
        Log.d("GodotAppLoader", "Found ${availableActivities.size} apps with shape: $shape")

        for (ri in availableActivities) {
            val appObj = JSONObject()
            val packageName = ri.activityInfo.packageName
            val label = ri.loadLabel(packageManager).toString()
            
            // Icon Handling with shape
            val iconDrawable = ri.loadIcon(packageManager)
            val iconBase64 = drawableToBase64WithShape(iconDrawable, shape)

            appObj.put("name", label)
            appObj.put("pkg", packageName)
            appObj.put("icon", iconBase64)
            
            // Category API added in Android O (API 26)
            if (android.os.Build.VERSION.SDK_INT >= 26) {
                appObj.put("category", ri.activityInfo.applicationInfo.category)
            } else {
                appObj.put("category", -1)
            }

            appsList.put(appObj)
        }

        return appsList.toString()
    }

    @UsedByGodot
    fun launch_app(packageName: String) {
        try {
            val intent = activity!!.packageManager.getLaunchIntentForPackage(packageName)
            if (intent != null) {
                // CRITICAL: Ensure app launches in its own task, not the launcher's task
                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED)
                activity!!.startActivity(intent)
            } else {
                Log.e("GodotAppLoader", "Could not find launch intent for $packageName")
                runOnUiThread {
                     Toast.makeText(activity, "Cannot launch $packageName", Toast.LENGTH_SHORT).show()
                }
            }
        } catch (e: Exception) {
            Log.e("GodotAppLoader", "Error launching app", e)
        }
    }

    @UsedByGodot
    fun open_accessibility_settings() {
        val intent = Intent(android.provider.Settings.ACTION_ACCESSIBILITY_SETTINGS)
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        activity?.startActivity(intent)
    }

    @UsedByGodot
    fun launch_wallpaper_settings() {
        Log.d("GodotAppLoader", "Launching wallpaper settings...")
        forceBounceOnResume = true
        activity?.runOnUiThread {
             Toast.makeText(activity, "Opening Wallpaper...", Toast.LENGTH_SHORT).show()
        }

        try {
            val intent = Intent(Intent.ACTION_SET_WALLPAPER)
            val chooser = Intent.createChooser(intent, "Select Wallpaper")
            chooser.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            activity!!.startActivity(chooser)
        } catch (e: Exception) {
             Log.e("GodotAppLoader", "Error launching wallpaper settings", e)
             activity?.runOnUiThread {
                 Toast.makeText(activity, "Error: No wallpaper app found", Toast.LENGTH_SHORT).show()
             }
        }
    }

    @UsedByGodot
    fun open_app_info(packageName: String) {
        forceBounceOnResume = true
        try {
            val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
            val uri = Uri.fromParts("package", packageName, null)
            intent.data = uri
            activity!!.startActivity(intent)
        } catch (e: Exception) {
            Log.e("GodotAppLoader", "Error opening app info", e)
        }
    }

    @UsedByGodot
    fun get_package_name(): String {
        return activity?.packageName ?: "unknown"
    }

    @UsedByGodot
    fun uninstall_app(packageName: String) {
        val cleanPkg = packageName.trim()
        Log.e("GodotAppLoader", "UNINSTALL: Requesting for [$cleanPkg]")
        try {
            val intent = Intent(Intent.ACTION_DELETE)
            intent.data = Uri.parse("package:$cleanPkg")
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            
            Log.e("GodotAppLoader", "UNINSTALL: Launching Intent for $cleanPkg")
            activity!!.startActivity(intent)
        } catch (e: Exception) {
            Log.e("GodotAppLoader", "UNINSTALL: Failed for $cleanPkg", e)
            activity?.runOnUiThread {
                Toast.makeText(activity, "Uninstall Error: ${e.message}", Toast.LENGTH_LONG).show()
            }
        }
    }

    @UsedByGodot
    fun vibrate(durationMs: Int) {
        try {
            val vibrator = activity!!.getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
            if (Build.VERSION.SDK_INT >= 26) {
                vibrator.vibrate(VibrationEffect.createOneShot(durationMs.toLong(), VibrationEffect.DEFAULT_AMPLITUDE))
            } else {
                @Suppress("DEPRECATION")
                vibrator.vibrate(durationMs.toLong())
            }
        } catch (e: Exception) {
            Log.e("GodotAppLoader", "Error vibrating", e)
        }
    }

    @UsedByGodot
    fun select_default_launcher() {
        forceBounceOnResume = true
        try {
            val intent = Intent(Settings.ACTION_HOME_SETTINGS)
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            activity!!.startActivity(intent)
        } catch (e: Exception) {
            // Fallback for older/newer versions if ACTION_HOME_SETTINGS fails
            try {
                val intent = Intent(Settings.ACTION_MANAGE_DEFAULT_APPS_SETTINGS)
                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                activity!!.startActivity(intent)
            } catch (e2: Exception) {
                Log.e("GodotAppLoader", "Error opening home settings", e2)
            }
        }
    }

    private var activeIconPackPkg: String = ""
    private var iconPackCache = mutableMapOf<String, Map<String, String>>()
    private var processedIconCache = ConcurrentHashMap<String, String>() // (AppPkg + PackPkg) -> Base64
    
    // Icon Pack Configuration (Masking)
    private var iconPackMask: Drawable? = null
    private var iconPackBacks = mutableListOf<Drawable>()
    private var iconPackUpon: Drawable? = null
    private var iconPackScale = 1.0f
    private var calendarMapping = mutableMapOf<String, String>() // prefix -> component
    private var activeIconShape = "Circle"

    @UsedByGodot
    fun set_active_icon_pack(pkgName: String) {
        // V30: CRITICAL DEEP RESET
        iconPackMask = null
        iconPackUpon = null
        iconPackBacks.clear()
        iconPackScale = 1.0f
        
        activeIconPackPkg = pkgName
        processedIconCache.clear() 
        iconPackCache.remove(pkgName) 
        loadIconPackMapping(pkgName)
        Log.d("GodotAppLoader", "V30: Active icon pack set to: $pkgName (Deep Reset & Cache Cleared)")
    }

    @UsedByGodot
    fun set_active_icon_shape(shape: String) {
        activeIconShape = shape
        processedIconCache.clear() // Refresh icons
        Log.d("GodotAppLoader", "Icon shape set to: $shape")
    }

    @UsedByGodot
    fun mask_bitmap_base64(inputBase64: String, scale: Float): String {
        // Takes a base64-encoded PNG and applies the current activeIconShape mask
        // Scale parameter allows per-asset padding (0.0 to 1.0)
        try {
            val bytes = Base64.decode(inputBase64, Base64.DEFAULT)
            val originalBitmap = BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
            if (originalBitmap == null) {
                Log.e("GodotAppLoader", "mask_bitmap_base64: Failed to decode input bitmap")
                return ""
            }
            
            val targetSize = 256
            val bitmap = Bitmap.createBitmap(targetSize, targetSize, Bitmap.Config.ARGB_8888)
            val canvas = Canvas(bitmap)
            
            // Create shape path using activeIconShape
            val path = createPathByName(activeIconShape, targetSize)
            canvas.clipPath(path)
            
            // Use the provided scale (fallback to 0.5f if invalid)
            val finalScale = if (scale <= 0f || scale > 2f) 0.5f else scale
            val scaledSize = (targetSize * finalScale).toInt()
            val offset = (targetSize - scaledSize) / 2
            
            val srcRect = android.graphics.Rect(0, 0, originalBitmap.width, originalBitmap.height)
            val dstRect = android.graphics.Rect(offset, offset, offset + scaledSize, offset + scaledSize)
            
            Log.d("GodotAppLoader", "V4.12: Masking icon at scale=$finalScale with shape=$activeIconShape")
            
            // Draw a background "plate" of the mask color
            // This ensures the mask is visible even if the icon is shrunk
            val platePaint = android.graphics.Paint(android.graphics.Paint.ANTI_ALIAS_FLAG)
            platePaint.color = android.graphics.Color.parseColor("#151D29") // Lattice Dark Blue
            platePaint.style = android.graphics.Paint.Style.FILL
            canvas.drawPath(path, platePaint)
            
            canvas.drawBitmap(originalBitmap, srcRect, dstRect, android.graphics.Paint(android.graphics.Paint.FILTER_BITMAP_FLAG or android.graphics.Paint.ANTI_ALIAS_FLAG))

            // V4.76: Border Removed (Masking preserved above)
            
            // Encode to base64
            val outputStream = ByteArrayOutputStream()
            bitmap.compress(Bitmap.CompressFormat.PNG, 100, outputStream)
            val resultBytes = outputStream.toByteArray()
            
            originalBitmap.recycle()
            bitmap.recycle()
            
            Log.d("GodotAppLoader", "mask_bitmap_base64: SUCCESS - masked with scale $scale and shape $activeIconShape")
            return Base64.encodeToString(resultBytes, Base64.NO_WRAP)
        } catch (e: Exception) {
            Log.e("GodotAppLoader", "Error in mask_bitmap_base64", e)
            return ""
        }
    }



    @UsedByGodot
    fun get_installed_icon_packs(): String {
        val packageManager = activity!!.packageManager
        val packs = JSONArray()
        
        val actions = listOf(
            "org.adw.launcher.THEMES",
            "com.gau.go.launcherex.theme",
            "com.fede.launcher.THEME_ICONPACK",
            "com.teslacoilsw.launcher.THEME"
        )
        
        val foundPackages = mutableSetOf<String>()
        
        for (action in actions) {
            val intent = Intent(action)
            val activities = packageManager.queryIntentActivities(intent, PackageManager.GET_META_DATA)
            for (ri in activities) {
                val pkg = ri.activityInfo.packageName
                if (foundPackages.contains(pkg)) continue
                
                val obj = JSONObject()
                obj.put("pkg", pkg)
                obj.put("name", ri.loadLabel(packageManager).toString())
                
                // Add icon for the pack itself
                val icon = ri.loadIcon(packageManager)
                obj.put("icon", drawableToBase64(icon))
                
                packs.put(obj)
                foundPackages.add(pkg)
            }
        }
        
        return packs.toString()
    }

    @UsedByGodot
    fun get_long_press_time_ms(): Int {
        try {
            return android.view.ViewConfiguration.getLongPressTimeout()
        } catch (e: Exception) {
            Log.e("GodotAppLoader", "Error getting long press timeout", e)
            return 400 // Default fallback
        }
    }

    @UsedByGodot
    fun check_usage_permission(): Boolean {
        try {
            val appOps = activity!!.getSystemService(Context.APP_OPS_SERVICE) as android.app.AppOpsManager
            val mode = appOps.checkOpNoThrow(android.app.AppOpsManager.OPSTR_GET_USAGE_STATS, 
                android.os.Process.myUid(), activity!!.packageName)
            return mode == android.app.AppOpsManager.MODE_ALLOWED
        } catch (e: Exception) {
            return false
        }
    }

    @UsedByGodot
    fun request_usage_permission() {
        forceBounceOnResume = true
        activity!!.runOnUiThread {
            try {
                val intent = Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS)
                // Try to link directly to this app's page
                val uri = Uri.fromParts("package", activity!!.packageName, null)
                intent.data = uri
                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                activity!!.startActivity(intent)
            } catch (e: Exception) {
                // Fallback to general list
                try {
                     val intent = Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS)
                     intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                     activity!!.startActivity(intent)
                } catch (e2: Exception) {
                     Log.e("GodotAppLoader", "Error opening usage settings", e2)
                }
            }
        }
    }

    @UsedByGodot
    fun fetch_usage_stats(): String {
        Log.d("GodotAppLoader", "Recents: Entering fetch_usage_stats")
        val limit = 15
        if (!check_usage_permission()) {
             Log.d("GodotAppLoader", "Recents: Permission check FAILED inside method")
             return "PERMISSION_DENIED"
        }
        Log.d("GodotAppLoader", "Recents: Permission check PASSED")
        
        try {
            val usm = activity!!.getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
            val calendar = Calendar.getInstance()
            val endTime = calendar.timeInMillis
            calendar.add(Calendar.YEAR, -1) // Look back 1 year
            val startTime = calendar.timeInMillis
            
            // Use queryAndAggregateUsageStats to get unique per-package stats merged over the time range
            val statsMap = usm.queryAndAggregateUsageStats(startTime, endTime)
            
            if (statsMap == null || statsMap.isEmpty()) {
                Log.e("GodotAppLoader", "Recents: Query returned empty map")
                return "[]"
            }

            val queryUsageStats = ArrayList(statsMap.values)
            Log.d("GodotAppLoader", "Recents: Found " + queryUsageStats.size + " stats entries")
            
            // Sort by Last Used
            Collections.sort(queryUsageStats, object : Comparator<UsageStats> {
                override fun compare(o1: UsageStats, o2: UsageStats): Int {
                    return o2.lastTimeUsed.compareTo(o1.lastTimeUsed)
                }
            })
            
            val jsonArray = JSONArray()
            val seenPkgs = mutableSetOf<String>()
            
            // Exclude ourselves and system
            seenPkgs.add(activity!!.packageName)
            seenPkgs.add("com.android.settings")
            seenPkgs.add("com.android.systemui")
            
            for (us in queryUsageStats) {
                if (jsonArray.length() >= limit) break
                
                val pkg = us.packageName
                // Filter out apps not used recently (e.g. within last 48 hours) strictly? 
                // Or just show whatever is sorted.
                // Let's ensure lastTimeUsed is > 0
                if (us.lastTimeUsed <= 0) continue

                if (pkg != null && !seenPkgs.contains(pkg)) {
                     val obj = JSONObject()
                     obj.put("pkg", pkg)
                     obj.put("lastTimeUsed", us.lastTimeUsed)
                     jsonArray.put(obj)
                     seenPkgs.add(pkg)
                }
            }
            return jsonArray.toString()
            
        } catch (e: Exception) {
            Log.e("GodotAppLoader", "Error fetching usage stats", e)
            return "[]"
        }
    }







    private fun loadIconPackMapping(packPackage: String): Map<String, String> {
        if (iconPackCache.containsKey(packPackage)) {
            return iconPackCache[packPackage]!!
        }

        val mapping = mutableMapOf<String, String>()
        iconPackMask = null
        iconPackBacks.clear()
        iconPackUpon = null
        iconPackScale = 1.0f
        calendarMapping.clear()

        try {
            val pm = activity!!.packageManager
            val res = pm.getResourcesForApplication(packPackage)
            
            // Use findAppFilterXml strategy from KISS research
            val parser = findAppFilterXml(res, packPackage)

            if (parser != null) {
                var eventType = parser.eventType
                while (eventType != org.xmlpull.v1.XmlPullParser.END_DOCUMENT) {
                    if (eventType == org.xmlpull.v1.XmlPullParser.START_TAG) {
                        when (parser.name) {
                            "item" -> {
                                val component = parser.getAttributeValue(null, "component")
                                val drawable = parser.getAttributeValue(null, "drawable")
                                if (component != null && drawable != null) {
                                    mapping[component] = drawable
                                    // Fallback mapping for package name
                                    val pkgMatch = Regex("\\{(.*?)/").find(component)
                                    if (pkgMatch != null) {
                                        mapping[pkgMatch.groupValues[1]] = drawable
                                    }
                                }
                            }
                            "iconback" -> {
                                for (i in 0 until parser.attributeCount) {
                                    if (parser.getAttributeName(i).startsWith("img")) {
                                        val drawableName = parser.getAttributeValue(i)
                                        val resId = res.getIdentifier(drawableName, "drawable", packPackage)
                                        if (resId != 0) iconPackBacks.add(res.getDrawable(resId, null))
                                    }
                                }
                            }
                            "iconmask" -> {
                                val maskName = parser.getAttributeValue(null, "img1")
                                if (maskName != null) {
                                    val resId = res.getIdentifier(maskName, "drawable", packPackage)
                                    if (resId != 0) {
                                        iconPackMask = res.getDrawable(resId, null)
                                        Log.d("GodotAppLoader", "V30: Mask detected: $maskName")
                                    }
                                }
                            }
                            "iconupon" -> {
                                val uponName = parser.getAttributeValue(null, "img1")
                                if (uponName != null) {
                                    val resId = res.getIdentifier(uponName, "drawable", packPackage)
                                    if (resId != 0) {
                                        iconPackUpon = res.getDrawable(resId, null)
                                        Log.d("GodotAppLoader", "V30: Upon detected: $uponName")
                                    }
                                }
                            }
                            "scale" -> {
                                val factorStr = parser.getAttributeValue(null, "factor") ?: parser.getAttributeValue(0)
                                iconPackScale = factorStr?.toFloatOrNull() ?: 1.0f
                                Log.d("GodotAppLoader", "V30: Scale detected: $iconPackScale")
                            }
                            "calendar" -> {
                                val component = parser.getAttributeValue(null, "component")
                                val prefix = parser.getAttributeValue(null, "prefix")
                                if (component != null && prefix != null) {
                                    calendarMapping[prefix] = component
                                }
                            }
                        }
                    }
                    eventType = parser.next()
                }
            }
        } catch (e: Exception) {
            Log.e("GodotAppLoader", "Error parsing appfilter.xml for $packPackage", e)
        }

        iconPackCache[packPackage] = mapping
        return mapping
    }

    private fun findAppFilterXml(res: android.content.res.Resources, pkg: String): org.xmlpull.v1.XmlPullParser? {
        // 1. Try res/xml/appfilter.xml
        val resId = res.getIdentifier("appfilter", "xml", pkg)
        if (resId != 0) return res.getXml(resId)
        
        // 2. Try res/raw/appfilter.xml
        val rawId = res.getIdentifier("appfilter", "raw", pkg)
        if (rawId != 0) {
            val factory = org.xmlpull.v1.XmlPullParserFactory.newInstance()
            val parser = factory.newPullParser()
            parser.setInput(res.openRawResource(rawId), "UTF-8")
            return parser
        }
        
        // 3. Try assets/appfilter.xml
        return try {
            val factory = org.xmlpull.v1.XmlPullParserFactory.newInstance()
            val parser = factory.newPullParser()
            parser.setInput(res.assets.open("appfilter.xml"), "UTF-8")
            parser
        } catch (e: Exception) { null }
    }

    @UsedByGodot
    fun get_icon_from_pack(appPackage: String, packPackage: String): String {
        return get_icon_from_pack_internal(appPackage, "", packPackage)
    }

    private fun get_icon_from_pack_internal(appPackage: String, componentName: String, packPackage: String): String {
        try {
            val pm = activity!!.packageManager
            val res = pm.getResourcesForApplication(packPackage)
            val mapping = loadIconPackMapping(packPackage)
            
            var drawableName: String? = null
            
            // 1. Try exact component match
            if (componentName.isNotEmpty()) {
                drawableName = mapping[componentName]
                
                // CALENDAR CHECK
                if (drawableName == null) {
                    for ((prefix, comp) in calendarMapping) {
                        if (comp == componentName) {
                            val day = Calendar.getInstance().get(Calendar.DAY_OF_MONTH)
                            drawableName = "$prefix$day"
                            break
                        }
                    }
                }
            }
            
            // 2. Try package match from mapping
            if (drawableName == null) {
                drawableName = mapping[appPackage]
            }
            
            // 3. Try common naming conventions
            if (drawableName == null) {
                drawableName = appPackage.replace(".", "_").lowercase()
            }
            
            var resId = res.getIdentifier(drawableName, "drawable", packPackage)
            
            // 4. Try last part of package
            if (resId == 0) {
                val shortName = appPackage.substringAfterLast(".").lowercase()
                resId = res.getIdentifier(shortName, "drawable", packPackage)
            }
            
            if (resId != 0) {
                val drawable = res.getDrawable(resId, null)
                return drawableToBase64(drawable)
            }
        } catch (e: Exception) {
            Log.e("GodotAppLoader", "Error fetching icon from pack", e)
        }
        return ""
    }

    private fun applyIconPackEffects(icon: Drawable): String {
        val targetSize = 256
        val finalBitmap = Bitmap.createBitmap(targetSize, targetSize, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(finalBitmap)
        
        // V30: Intelligent Stencil Engine
        canvas.drawColor(android.graphics.Color.TRANSPARENT, android.graphics.PorterDuff.Mode.CLEAR)

        // 1. Draw Backgrounds (Always first)
        if (iconPackBacks.isNotEmpty()) {
            val back = iconPackBacks[java.util.Random().nextInt(iconPackBacks.size)]
            back.setBounds(0, 0, targetSize, targetSize)
            back.draw(canvas)
        }

        // 2. Prepare Masked Icon using Auto-Detected Pattern
        val iconLayer = Bitmap.createBitmap(targetSize, targetSize, Bitmap.Config.ARGB_8888)
        val iconCanvas = Canvas(iconLayer)
        
        // A. Draw ICON onto isolated layer
        val iconBmp = drawableToBitmap(icon, targetSize, targetSize)
        
        val scaledSize = (targetSize * iconPackScale).toInt()
        val offset = (targetSize - scaledSize).toFloat() / 2f
        
        // V14.36: Targetted Icon Shaping
        // Instead of cropping the source, we crop the CANVAS at the exact placement
        // This handles cases where reconstructed adaptive icons have white backgrounds filling the frame.
        val path = createPathByName(activeIconShape, targetSize)
        val matrix = android.graphics.Matrix()
        matrix.setScale(iconPackScale, iconPackScale, targetSize / 2f, targetSize / 2f)
        path.transform(matrix)
        iconCanvas.clipPath(path)

        val scaledBitmap = Bitmap.createScaledBitmap(iconBmp, scaledSize, scaledSize, true)
        iconCanvas.drawBitmap(scaledBitmap, offset, offset, null)
        iconBmp.recycle()
        
        // B. Apply MASK with Intelligence
        if (iconPackMask != null) {
            val maskBmp = drawableToBitmap(iconPackMask!!, targetSize, targetSize)
            
            // Auto-detect Mask Type: Check center transparency
            val centerX = targetSize / 2
            val centerY = targetSize / 2
            val centerAlpha = android.graphics.Color.alpha(maskBmp.getPixel(centerX, centerY))
            
            val alphaStencil = maskBmp.extractAlpha() 
            val paint = android.graphics.Paint(android.graphics.Paint.ANTI_ALIAS_FLAG)
            
            if (centerAlpha < 50) {
                // Center is transparent -> Frame Mask (e.g. Verticons) -> Use DST_OUT
                paint.xfermode = android.graphics.PorterDuffXfermode(android.graphics.PorterDuff.Mode.DST_OUT)
                Log.d("GodotAppLoader", "V30: Detected FRAME mask (Center transparent), using DST_OUT")
            } else {
                // Center is opaque -> Shape Mask -> Use DST_IN
                paint.xfermode = android.graphics.PorterDuffXfermode(android.graphics.PorterDuff.Mode.DST_IN)
                Log.d("GodotAppLoader", "V30: Detected SHAPE mask (Center opaque), using DST_IN")
            }
            
            iconCanvas.drawBitmap(alphaStencil, 0f, 0f, paint)
        }

        // 3. Composite icon layer onto final canvas
        canvas.drawBitmap(iconLayer, 0f, 0f, null)
        
        // V4.72: Restore Icon Borders (REMOVED V4.76)

        // 4. Draw Overlay (Upon)
        if (iconPackUpon != null) {
            iconPackUpon!!.setBounds(0, 0, targetSize, targetSize)
            iconPackUpon!!.draw(canvas)
            Log.d("GodotAppLoader", "V30: Drew overlay layer")
        }

        val outputStream = ByteArrayOutputStream()
        finalBitmap.compress(Bitmap.CompressFormat.PNG, 100, outputStream)
        return Base64.encodeToString(outputStream.toByteArray(), Base64.NO_WRAP)
    }

    private fun drawableToBitmap(drawable: Drawable, w: Int, h: Int): Bitmap {
        val bitmap = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        canvas.drawColor(android.graphics.Color.TRANSPARENT, android.graphics.PorterDuff.Mode.CLEAR)
        
        // V4.23: Reconstruction Engine
        // Detect Adaptive Icons and extract raw layers to bypass system masking
        if (Build.VERSION.SDK_INT >= 26 && drawable is android.graphics.drawable.AdaptiveIconDrawable) {
            try {
                // Draw background layer (un-clipped)
                val bg = drawable.background
                if (bg != null) {
                    bg.setBounds(0, 0, w, h)
                    bg.draw(canvas)
                }
                // Draw foreground layer (un-clipped)
                val fg = drawable.foreground
                if (fg != null) {
                    fg.setBounds(0, 0, w, h)
                    fg.draw(canvas)
                }
                Log.d("GodotAppLoader", "V4.76j: RECONSTRUCTED AdaptiveIcon (Bypassed system mask)")
                return bitmap
            } catch (e: Exception) {
                Log.e("GodotAppLoader", "Error reconstructing adaptive icon", e)
            }
        }
        
        // Legacy or Fallback: Draw as-is
        drawable.setBounds(0, 0, w, h)
        drawable.draw(canvas)
        return bitmap
    }

    @UsedByGodot
    fun get_wp_id_v2(): String {
        Log.e("GodotAppLoader", "V4.76j: get_wp_id_v2() called")
        try {
            val act = getActivity() ?: return "-1"
            val wallpaperManager = WallpaperManager.getInstance(act)
            val id = wallpaperManager.getWallpaperId(WallpaperManager.FLAG_SYSTEM)
            return id.toString()
        } catch (e: Exception) {
            return "-1"
        }
    }

    @UsedByGodot
    fun ping(): String {
        return "pong"
    }

    @UsedByGodot
    fun get_plugin_methods(): List<String> {
        return getPluginMethods()
    }

    @UsedByGodot
    fun get_unblurred_wallpaper(): String {
        Log.e("GodotAppLoader", "V4.78: get_unblurred_wallpaper called")
        try {
            val act = getActivity() ?: return ""
            val managedFile = java.io.File(act.filesDir, MANAGED_WP_FILENAME)
            
            if (managedFile.exists()) {
                val bytes = managedFile.readBytes()
                val result = Base64.encodeToString(bytes, Base64.NO_WRAP)
                Log.e("GodotAppLoader", "V4.78: Successfully returned unblurred wallpaper (Length: ${result.length})")
                return result
            } else {
                Log.e("GodotAppLoader", "V4.78: Managed wallpaper file not found")
                return ""
            }
        } catch (e: Exception) {
            Log.e("GodotAppLoader", "Error getting unblurred wallpaper", e)
            return ""
        }
    }

    @UsedByGodot
    fun get_blurred_wallpaper(blurRadius: Float): String {
        Log.e("GodotAppLoader", "V4.76j: get_blurred_wallpaper called (radius=$blurRadius)")
        try {
            Log.d("GodotAppLoader", "Fetching blurred wallpaper (radius: $blurRadius)")
            
            val act = getActivity()
            if (act == null) {
                Log.e("GodotAppLoader", "CRITICAL: Activity is NULL. Cannot fetch wallpaper.")
                return ""
            }

            // Log Permission Status
            val hasPermission = if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.TIRAMISU) {
                act.checkSelfPermission(android.Manifest.permission.READ_MEDIA_IMAGES) == android.content.pm.PackageManager.PERMISSION_GRANTED
            } else if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.M) {
                act.checkSelfPermission(android.Manifest.permission.READ_EXTERNAL_STORAGE) == android.content.pm.PackageManager.PERMISSION_GRANTED
            } else true
            Log.d("GodotAppLoader", "Wallpaper Read Permission granted: $hasPermission")

            // V4.53: DIAGNOSTIC - CHECK IF DEFAULT LAUNCHER
            val intent = Intent(Intent.ACTION_MAIN)
            intent.addCategory(Intent.CATEGORY_HOME)
            val resolveInfo = act.packageManager.resolveActivity(intent, PackageManager.MATCH_DEFAULT_ONLY)
            val currentHomePkg = resolveInfo?.activityInfo?.packageName
            val isDefault = (currentHomePkg == act.packageName)
            Log.e("GodotAppLoader", "V4.76j: Is Default Launcher: $isDefault (Current: $currentHomePkg)")

            val wallpaperManager = WallpaperManager.getInstance(act)
            val wpInfo = wallpaperManager.getWallpaperInfo()
            val isLive = (wpInfo != null)
            val wpId = try { wallpaperManager.getWallpaperId(WallpaperManager.FLAG_SYSTEM) } catch(e: Exception) { -1 }
            
            Log.i("GodotAppLoader", "V4.76j: Fetch Start. ID: $wpId | IsLive: $isLive | Component: ${wpInfo?.component ?: "STATIC"}")
            
            // Priority 1: Managed Wallpaper (App-Internal)
            var drawable: Drawable? = null
            val managedFile = java.io.File(act.filesDir, MANAGED_WP_FILENAME)
            if (managedFile.exists()) {
                try {
                    val bmp = BitmapFactory.decodeFile(managedFile.absolutePath)
                    if (bmp != null) {
                        Log.i("GodotAppLoader", "V4.76j: Using MANAGED Wallpaper")
                        drawable = BitmapDrawable(act.resources, bmp)
                    }
                } catch (e: Exception) {
                    Log.e("GodotAppLoader", "Managed load fail: ${e.message}")
                }
            }

            // Priority 2: System Wallpaper Retrieval (Fallback Chain)
            if (drawable == null) {
                // A. FD Retrieval (Often bypasses SecurityException)
                try {
                    val pfd = wallpaperManager.getWallpaperFile(WallpaperManager.FLAG_SYSTEM)
                    if (pfd != null) {
                        val bmp = BitmapFactory.decodeFileDescriptor(pfd.fileDescriptor)
                        pfd.close()
                        if (bmp != null) {
                            Log.d("GodotAppLoader", "V4.63: FD Retrieval Success")
                            drawable = BitmapDrawable(act.resources, bmp)
                        }
                    }
                } catch (e: Exception) { Log.d("GodotAppLoader", "FD fail: ${e.message}") }
                
                // B. peekDrawable (Permissive)
                if (drawable == null) {
                    try { drawable = wallpaperManager.peekDrawable() } catch (e: Exception) {}
                }
                
                // C. fastDrawable
                if (drawable == null) {
                    try { drawable = wallpaperManager.fastDrawable } catch (e: Exception) {}
                }
                
                // D. getDrawable (Standard)
                if (drawable == null) {
                    try { drawable = wallpaperManager.getDrawable(WallpaperManager.FLAG_SYSTEM) } catch (e: Exception) {}
                }
            }

            // Phase 10: BRUTE-FORCE RENDER or COLOR FALLBACK
            val originalBitmap: Bitmap = try {
                if (drawable == null || (isLive && !managedFile.exists())) {
                    Log.i("GodotAppLoader", "V4.63: No pixels or Live WP. Generating Smart Gradient.")
                    generateSmartGradient(wallpaperManager)
                } else {
                    val dw = drawable!!
                    if (dw.intrinsicWidth <= 0 || dw.intrinsicHeight <= 0) {
                        generateSmartGradient(wallpaperManager)
                    } else {
                        val bmp = Bitmap.createBitmap(dw.intrinsicWidth, dw.intrinsicHeight, Bitmap.Config.ARGB_8888)
                        val canvas = Canvas(bmp)
                        dw.setBounds(0, 0, canvas.width, canvas.height)
                        dw.draw(canvas)
                        bmp
                    }
                }
            } catch (e: Exception) {
                Log.e("GodotAppLoader", "Render logic crash: ${e.message}")
                generateSmartGradient(wallpaperManager)
            }

            Log.d("GodotAppLoader", "Original Bitmap: ${originalBitmap.width}x${originalBitmap.height}")

            // V4.51: SHADERLESS - BLUR AT END + TINT
            // 1. Initial Scale (Small for performance)
            val downScale = 0.1f 
            val w = (originalBitmap.width * downScale).toInt().coerceAtLeast(1)
            val h = (originalBitmap.height * downScale).toInt().coerceAtLeast(1)
            var currentBitmap = Bitmap.createScaledBitmap(originalBitmap, w, h, true)
            
            // 2. Scale to Final Size (1024px for high-res glass) -- V4.78
            val maxDim = 1024
            val upFactor = maxDim.toFloat() / Math.max(w, h)
            val finalW = (w * upFactor).toInt()
            val finalH = (h * upFactor).toInt()
            var finalBitmap = Bitmap.createScaledBitmap(currentBitmap, finalW, finalH, true)
            
            Log.i("GodotAppLoader", "V4.56: EXTRACTION SUCCESS ($finalW x $finalH). Radius: $blurRadius")
            
            // 3. APPLY BLUR AT THE VERY END
            finalBitmap = applySoftwareBlur(finalBitmap, blurRadius)
            
            // 4. PREPARE OUTPUT
            val outputStream = ByteArrayOutputStream()
            finalBitmap.compress(Bitmap.CompressFormat.JPEG, 85, outputStream) 
            val byteArray = outputStream.toByteArray()
            
            currentBitmap.recycle()
            finalBitmap.recycle()

            val result = Base64.encodeToString(byteArray, Base64.NO_WRAP)
            Log.d("GodotAppLoader", "V4.62: Final B64 Length: ${result.length}")
            return result
        } catch (e: Exception) {
            Log.e("GodotAppLoader", "Error getting blurred wallpaper", e)
            return ""
        }
    }

    private fun generateSmartGradient(wallpaperManager: WallpaperManager): Bitmap {
        val width = 512
        val height = 512
        val bmp = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bmp)

        // Default colors (Dark Gray / Blueish)
        var c1 = 0xFF212121.toInt()
        var c2 = 0xFF424242.toInt()
        var c3 = 0xFF1A237E.toInt()

        if (Build.VERSION.SDK_INT >= 27) {
            try {
                val colors = wallpaperManager.getWallpaperColors(WallpaperManager.FLAG_SYSTEM)
                if (colors != null) {
                    c1 = colors.primaryColor.toArgb()
                    c2 = colors.secondaryColor?.toArgb() ?: c1
                    c3 = colors.tertiaryColor?.toArgb() ?: c2
                    Log.i("GodotAppLoader", "V4.62: Gradient generated from system colors")
                }
            } catch (e: Exception) {
                Log.e("GodotAppLoader", "Could not get system colors: ${e.message}")
            }
        }

        val gradient = LinearGradient(
            0f, 0f, width.toFloat(), height.toFloat(),
            intArrayOf(c1, c2, c3),
            null,
            Shader.TileMode.CLAMP
        )

        val paint = android.graphics.Paint()
        paint.shader = gradient
        canvas.drawRect(0f, 0f, width.toFloat(), height.toFloat(), paint)
        
        return bmp
    }

    private fun applySoftwareBlur(bitmap: Bitmap, radius: Float): Bitmap {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.JELLY_BEAN_MR1) {
            try {
                val rs = RenderScript.create(godot.getActivity())
                
                // V4.74: SUPPORT RADIUS > 25
                // ScriptIntrinsicBlur is hard-capped at 25.0 in the Android framework.
                // To achieve a "50" level blur, we downscale the bitmap, apply 25, then upscale.
                var finalBitmap = bitmap
                var effectiveRadius = radius.coerceIn(1f, 100f) // Allow high numbers
                
                if (effectiveRadius > 25f) {
                    val scale = if (effectiveRadius > 50f) 0.25f else 0.5f // V4.75: More aggressive for high blur
                    val w = (bitmap.width * scale).toInt().coerceAtLeast(1)
                    val h = (bitmap.height * scale).toInt().coerceAtLeast(1)
                    val smallBmp = Bitmap.createScaledBitmap(bitmap, w, h, true)
                    
                    val input = Allocation.createFromBitmap(rs, smallBmp)
                    val output = Allocation.createTyped(rs, input.type)
                    val script = ScriptIntrinsicBlur.create(rs, Element.U8_4(rs))
                    script.setRadius((effectiveRadius * scale).coerceIn(1f, 25f))
                    script.setInput(input)
                    script.forEach(output)
                    output.copyTo(smallBmp)
                    
                    finalBitmap = Bitmap.createScaledBitmap(smallBmp, bitmap.width, bitmap.height, true)
                    smallBmp.recycle()
                    Log.d("GodotAppLoader", "Extreme Blur Success (Radius $radius via aggressive downscaling)")
                } else {
                    val input = Allocation.createFromBitmap(rs, bitmap)
                    val output = Allocation.createTyped(rs, input.type)
                    val script = ScriptIntrinsicBlur.create(rs, Element.U8_4(rs))
                    script.setRadius(effectiveRadius)
                    script.setInput(input)
                    script.forEach(output)
                    output.copyTo(bitmap)
                    Log.d("GodotAppLoader", "Standard Blur Success (Radius $radius)")
                }
                
                rs.destroy()
                return finalBitmap
            } catch (e: Exception) {
                Log.w("GodotAppLoader", "RenderScript failed, falling back to manual blur: ${e.message}")
            }
        }
        return manualBoxBlur(bitmap, 15) // V4.52: 15 iterations (Faster, still mushy)
    }

    private fun manualBoxBlur(bitmap: Bitmap, iterations: Int): Bitmap {
        val width = bitmap.width
        val height = bitmap.height
        val pixels = IntArray(width * height)
        bitmap.getPixels(pixels, 0, width, 0, 0, width, height)
        
        for (i in 0 until iterations) {
            for (y in 1 until height - 1) {
                for (x in 1 until width - 1) {
                    val index = y * width + x
                    var r = 0; var g = 0; var b = 0
                    for (dy in -1..1) {
                        for (dx in -1..1) {
                            val neighbor = pixels[(y + dy) * width + (x + dx)]
                            r += (neighbor shr 16) and 0xFF
                            g += (neighbor shr 8) and 0xFF
                            b += neighbor and 0xFF
                        }
                    }
                    r /= 9; g /= 9; b /= 9
                    pixels[index] = (0xFF shl 24) or (r shl 16) or (g shl 8) or b
                }
            }
        }
        bitmap.setPixels(pixels, 0, width, 0, 0, width, height)
        return bitmap
    }

    @UsedByGodot
    fun get_system_wallpaper(): String {
        try {
            Log.d("GodotAppLoader", "Fetching system wallpaper...")
            val wallpaperManager = WallpaperManager.getInstance(activity)
            val drawable = wallpaperManager.drawable
            if (drawable == null) {
                Log.e("GodotAppLoader", "Wallpaper drawable is NULL. Permission missing?")
                return ""
            }
            Log.d("GodotAppLoader", "Wallpaper drawable found: ${drawable.javaClass.simpleName}")
            
            val bitmap = if (drawable is BitmapDrawable) {
                drawable.bitmap
            } else {
                 if (drawable.intrinsicWidth <= 0 || drawable.intrinsicHeight <= 0) {
                     // Fallback for solid colors or gradients with no size
                     Bitmap.createBitmap(1, 1, Bitmap.Config.ARGB_8888)
                 } else {
                     val bmp = Bitmap.createBitmap(drawable.intrinsicWidth, drawable.intrinsicHeight, Bitmap.Config.ARGB_8888)
                     val canvas = Canvas(bmp)
                     drawable.setBounds(0, 0, canvas.width, canvas.height)
                     drawable.draw(canvas)
                     bmp
                 }
            }
            
            // Resize if too massive (optional, but good for safety)
            // For now, let's keep it full quality or maybe max 1080p width to save memory transfer
            val maxDimension = 2048
            var finalBitmap = bitmap
            if (bitmap.width > maxDimension || bitmap.height > maxDimension) {
                val scale = maxDimension.toFloat() / Math.max(bitmap.width, bitmap.height)
                finalBitmap = Bitmap.createScaledBitmap(bitmap, 
                    (bitmap.width * scale).toInt(), 
                    (bitmap.height * scale).toInt(), 
                    true)
            }

            val byteArrayOutputStream = ByteArrayOutputStream()
            finalBitmap.compress(Bitmap.CompressFormat.JPEG, 90, byteArrayOutputStream)
            val byteArray = byteArrayOutputStream.toByteArray()
            return Base64.encodeToString(byteArray, Base64.NO_WRAP)
        } catch (e: Exception) {
            Log.e("GodotAppLoader", "Error getting wallpaper", e)
            return ""
        }
    }

    private fun drawableToBase64(drawable: Drawable): String {
        val targetSize = 256
        val bitmap = Bitmap.createBitmap(targetSize, targetSize, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        
        // Draw the drawable as is, preserving transparency
        drawable.setBounds(0, 0, targetSize, targetSize)
        drawable.draw(canvas)
        
        val outputStream = ByteArrayOutputStream()
        bitmap.compress(Bitmap.CompressFormat.PNG, 100, outputStream)
        return Base64.encodeToString(outputStream.toByteArray(), Base64.NO_WRAP)
    }

    private fun drawableToBase64WithCircle(drawable: Drawable): String {
        val targetSize = 256
        val bitmap = Bitmap.createBitmap(targetSize, targetSize, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)

        val path = android.graphics.Path()
        path.addCircle(targetSize / 2f, targetSize / 2f, targetSize / 2f, android.graphics.Path.Direction.CW)
        canvas.clipPath(path)

        if (Build.VERSION.SDK_INT >= 26 && drawable is android.graphics.drawable.AdaptiveIconDrawable) {
            drawable.setBounds(0, 0, targetSize, targetSize)
            drawable.draw(canvas)
        } else {
            // Legacy Icon: Draw onto a subtle background ONLY if we are forcing circular mode
            val paint = android.graphics.Paint()
            paint.color = android.graphics.Color.parseColor("#33FFFFFF") // Very subtle transparent white
            paint.style = android.graphics.Paint.Style.FILL
            canvas.drawCircle(targetSize / 2f, targetSize / 2f, targetSize / 2f, paint)

            val padding = (targetSize * 0.1f).toInt()
            drawable.setBounds(padding, padding, targetSize - padding, targetSize - padding)
            drawable.draw(canvas)
        }

        val outputStream = ByteArrayOutputStream()
        bitmap.compress(Bitmap.CompressFormat.PNG, 100, outputStream)
        return Base64.encodeToString(outputStream.toByteArray(), Base64.NO_WRAP)
    }

    private fun drawableToBase64WithShape(drawable: Drawable, shape: String): String {
        try {
            val targetSize = 256
            val bitmap = Bitmap.createBitmap(targetSize, targetSize, Bitmap.Config.ARGB_8888)
            val canvas = Canvas(bitmap)

        // Create shape-specific path
        val path = createPathByName(shape, targetSize)
        canvas.clipPath(path)

        // Render icon
        if (Build.VERSION.SDK_INT >= 26 && drawable is android.graphics.drawable.AdaptiveIconDrawable) {
            // Adaptive icon - draw with shape
            drawable.setBounds(0, 0, targetSize, targetSize)
            drawable.draw(canvas)
        } else {
            // Legacy icon - draw plate background then icon
            val paint = android.graphics.Paint()
            paint.color = android.graphics.Color.parseColor("#E0E0E0")
            paint.style = android.graphics.Paint.Style.FILL
            canvas.drawPath(path, paint)

            // V4.13: Aggressive 0.45f scale for legacy icons to prevent clipping
            // This is the fallback if Icon.gd doesn't catch the main app
            val padding = (targetSize * 0.275f).toInt() // results in approx 0.45 scale
            drawable.setBounds(padding, padding, targetSize - padding, targetSize - padding)
            drawable.draw(canvas)
            Log.d("GodotAppLoader", "V4.13: Rendered legacy icon with padding $padding")
        }
        
        // V4.72: Restore Icon Borders (REMOVED V4.76)

        val outputStream = ByteArrayOutputStream()
        bitmap.compress(Bitmap.CompressFormat.PNG, 100, outputStream)
        val byteArray = outputStream.toByteArray()
        return Base64.encodeToString(byteArray, Base64.NO_WRAP)
        } catch (e: Exception) {
            Log.e("GodotAppLoader", "Error generating icon shape", e)
            return ""
        }
    }

    private fun createPathByName(shapeName: String, size: Int): android.graphics.Path {
        return when (shapeName.lowercase().replace(" ", "")) {
            "circle" -> createCirclePath(size)
            "squircle" -> createSquirclePath(size)
            "roundedsquare" -> createRoundedSquarePath(size)
            "teardrop" -> createTeardropPath(size)
            else -> createCirclePath(size)
        }
    }

    private fun createCirclePath(size: Int): android.graphics.Path {
        val path = android.graphics.Path()
        path.addCircle(size / 2f, size / 2f, size / 2f, android.graphics.Path.Direction.CW)
        return path
    }

    private fun createSquirclePath(size: Int): android.graphics.Path {
        // Squircle: iOS-like smooth rounded square using superellipse formula
        val path = android.graphics.Path()
        val center = size / 2f
        val radius = size / 2f
        val n = 3.0f // Superellipse parameter (3.0 for softer, more curved squircle)
        
        val points = 100
        path.moveTo(center + radius, center)
        
        for (i in 0..points) {
            val angle = (i * 2 * Math.PI / points).toFloat()
            val cosT = Math.cos(angle.toDouble()).toFloat()
            val sinT = Math.sin(angle.toDouble()).toFloat()
            
            val x = center + radius * Math.pow(Math.abs(cosT).toDouble(), 2.0 / n).toFloat() * Math.signum(cosT)
            val y = center + radius * Math.pow(Math.abs(sinT).toDouble(), 2.0 / n).toFloat() * Math.signum(sinT)
            
            if (i == 0) path.moveTo(x, y) else path.lineTo(x, y)
        }
        path.close()
        return path
    }

    private fun createRoundedSquarePath(size: Int): android.graphics.Path {
        val path = android.graphics.Path()
        val rect = android.graphics.RectF(0f, 0f, size.toFloat(), size.toFloat())
        val cornerRadius = size * 0.15f // 15% corner radius
        path.addRoundRect(rect, cornerRadius, cornerRadius, android.graphics.Path.Direction.CW)
        return path
    }

    private fun createTeardropPath(size: Int): android.graphics.Path {
        // Official Android Teardrop: Circle with a rounded corner (bottom-right)
        val path = android.graphics.Path()
        val s = size.toFloat()
        val rect = android.graphics.RectF(0f, 0f, s, s)
        
        // 3 Corners are circular (50% radius), 1 corner is sharp/tapered (approx 12-25% radius)
        val corner_radius = s / 2f
        val small_radius = s * 0.12f 
        
        val radii = floatArrayOf(
            corner_radius, corner_radius, // top-left
            corner_radius, corner_radius, // top-right
            small_radius, small_radius,   // bottom-right (The "point")
            corner_radius, corner_radius  // bottom-left
        )
        
        path.addRoundRect(rect, radii, android.graphics.Path.Direction.CW)
        return path
    }

    private fun createWaterdropPath(size: Int): android.graphics.Path {
        // This is the vertical "droplet" shape requested (Pointy top, round bottom)
        val path = android.graphics.Path()
        val center = size / 2f
        val radius = size / 2f
        
        path.moveTo(center, size.toFloat()) // bottom center
        path.cubicTo(size.toFloat(), size.toFloat(), size.toFloat(), center, center, 0f) // right side to top point
        path.cubicTo(0f, center, 0f, size.toFloat(), center, size.toFloat()) // left side to bottom center
        
        path.close()
        return path
    }

    private fun createFixedSquarePath(size: Int): android.graphics.Path {
        // To cut out the rounded parts of adaptive icons, the square needs to be slightly smaller
        // than the full 192px bounds if the icon provider uses extreme rounding.
        val path = android.graphics.Path()
        val inset = size * 0.08f // 8% inset to "bite" into rounded corners
        val rect = android.graphics.RectF(inset, inset, size - inset, size - inset)
        path.addRect(rect, android.graphics.Path.Direction.CW)
        return path
    }

    private fun createPentagonPath(size: Int): android.graphics.Path {
        val path = android.graphics.Path()
        val center = size / 2f
        val radius = size / 2f
        for (i in 0 until 5) {
            val angle = Math.toRadians((i * 360 / 5 - 90).toDouble())
            val x = center + radius * Math.cos(angle).toFloat()
            val y = center + radius * Math.sin(angle).toFloat()
            if (i == 0) path.moveTo(x, y) else path.lineTo(x, y)
        }
        path.close()
        return path
    }

    private fun createHexagonPath(size: Int): android.graphics.Path {
        val path = android.graphics.Path()
        val center = size / 2f
        val radius = size / 2f
        for (i in 0 until 6) {
            val angle = Math.toRadians((i * 360 / 6 - 90).toDouble())
            val x = center + radius * Math.cos(angle).toFloat()
            val y = center + radius * Math.sin(angle).toFloat()
            if (i == 0) path.moveTo(x, y) else path.lineTo(x, y)
        }
        path.close()
        return path
    }

    private fun createPebblePath(size: Int): android.graphics.Path {
        // Enlarge the pebble to fill more space
        val path = android.graphics.Path()
        val center = size / 2f
        val radius = size / 2f
        
        // Define 4 organic corners with larger radii
        val r1 = radius * 0.98f
        val r2 = radius * 1.05f // Slightly exceeds bounds on sides for organic effect
        val r3 = radius * 1.0f
        val r4 = radius * 1.02f
        
        path.moveTo(center, center - r1)
        path.cubicTo(center + r2, center - r1, center + r2, center + r3, center, center + r3)
        path.cubicTo(center - r4, center + r3, center - r4, center - r1, center, center - r1)
        
        path.close()
        return path
    }

    private fun createCloudPath(size: Int): android.graphics.Path {
        val path = android.graphics.Path()
        val s = size.toFloat()
        // Simple 3-bump cloud
        path.moveTo(s * 0.25f, s * 0.8f)
        path.cubicTo(s * 0.05f, s * 0.8f, s * 0.05f, s * 0.5f, s * 0.25f, s * 0.5f)
        path.cubicTo(s * 0.25f, s * 0.2f, s * 0.75f, s * 0.2f, s * 0.75f, s * 0.5f)
        path.cubicTo(s * 0.95f, s * 0.5f, s * 0.95f, s * 0.8f, s * 0.75f, s * 0.8f)
        path.close()
        return path
    }

    private fun createHeartPath(size: Int): android.graphics.Path {
        val path = android.graphics.Path()
        val s = size.toFloat()
        path.moveTo(s * 0.5f, s * 0.25f)
        path.cubicTo(s * 0.2f, s * 0.05f, 0f, s * 0.25f, 0f, s * 0.5f)
        path.cubicTo(0f, s * 0.8f, s * 0.3f, s * 0.95f, s * 0.5f, s)
        path.cubicTo(s * 0.7f, s * 0.95f, s, s * 0.8f, s, s * 0.5f)
        path.cubicTo(s, s * 0.25f, s * 0.8f, s * 0.05f, s * 0.5f, s * 0.25f)
        path.close()
        return path
    }

    private fun createStarPath(size: Int): android.graphics.Path {
        val path = android.graphics.Path()
        val center = size / 2f
        val outerRadius = size / 2f
        val innerRadius = size * 0.22f
        val points = 5
        for (i in 0 until points * 2) {
            val radius = if (i % 2 == 0) outerRadius else innerRadius
            val angle = Math.toRadians((i * 360 / (points * 2) - 90).toDouble())
            val x = center + radius * Math.cos(angle).toFloat()
            val y = center + radius * Math.sin(angle).toFloat()
            if (i == 0) path.moveTo(x, y) else path.lineTo(x, y)
        }
        path.close()
        return path
    }

    private fun createTrianglePath(size: Int): android.graphics.Path {
        val path = android.graphics.Path()
        val s = size.toFloat()
        // Triangle with slightly rounded appearance via path order or manual points
        path.moveTo(s * 0.5f, s * 0.05f) // Top
        path.lineTo(s * 0.95f, s * 0.9f) // Bottom right
        path.lineTo(s * 0.05f, s * 0.9f) // Bottom left
        path.close()
        return path
    }

    @UsedByGodot
    fun loadAsset(path: String): ByteArray? {
        return try {
            val assetManager = activity?.assets
            if (assetManager == null) {
                Log.e("GodotAppLoader", "loadAsset: AssetManager is null")
                return null
            }
            val inputStream = assetManager.open(path)
            val bytes = inputStream.readBytes()
            inputStream.close()
            Log.d("GodotAppLoader", "loadAsset: Successfully loaded $path (${bytes.size} bytes)")
            bytes
        } catch (e: Exception) {
            Log.e("GodotAppLoader", "loadAsset: Failed to load $path", e)
            null
        }
    }

    @UsedByGodot
    fun loadAssetBase64(path: String): String {
        return try {
            val assetManager = activity?.assets ?: return ""
            val inputStream = assetManager.open(path)
            val bytes = inputStream.readBytes()
            inputStream.close()
            Log.d("GodotAppLoader", "loadAssetBase64: Successfully loaded $path (${bytes.size} bytes)")
            Base64.encodeToString(bytes, Base64.NO_WRAP)
        } catch (e: Exception) {
            Log.e("GodotAppLoader", "loadAssetBase64: Failed to load $path", e)
            try {
                val am = activity?.assets
                if (am != null) {
                     Log.e("GodotAppLoader", "--- ASSET DEBUG ---")
                     am.list("")?.forEach { Log.e("GodotAppLoader", "ROOT: $it") }
                     am.list("assets")?.forEach { Log.e("GodotAppLoader", "SUB: $it") }
                }
            } catch (ex: Exception) { }
            ""
        }
    }

    @UsedByGodot
    fun is_service_connected(): Int {
        if (LauncherAccessibilityService.instance != null) return 1
        return 0
    }

    @UsedByGodot
    fun lock_screen() {
        val service = LauncherAccessibilityService.instance
        if (service == null) {
            Log.d("GodotAppLoader", "lock_screen: Service instance is NULL in AppLoader.")
            make_toast("Service not connected. Please re-enable 'Lattice Ui' in Accessibility Settings.")
            
            val intent = Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS)
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            activity?.startActivity(intent)
        } else {
            if (Build.VERSION.SDK_INT >= 28) {
                val success = service.performGlobalAction(AccessibilityService.GLOBAL_ACTION_LOCK_SCREEN)
                if (success) {
                    // Success silently
                    Log.d("GodotAppLoader", "lock_screen: Lock command sent successfully.")
                } else {
                    make_toast("Request Failed: System returned false")
                    Log.e("GodotAppLoader", "lock_screen: performGlobalAction returned false.")
                }
            } else {
                make_toast("Error: API Level ${Build.VERSION.SDK_INT} too old (Need 28+)")
            }
        }
    }

    @UsedByGodot
    fun make_toast(message: String) {
        activity?.runOnUiThread {
            Toast.makeText(activity, message, Toast.LENGTH_SHORT).show()
        }
    }

    @UsedByGodot
    fun expand_notifications() {
        val service = LauncherAccessibilityService.instance
        if (service != null) {
            val success = service.performGlobalAction(AccessibilityService.GLOBAL_ACTION_NOTIFICATIONS)
            if (success) {
                Log.d("GodotAppLoader", "expand_notifications: Notification panel opened.")
            } else {
                Log.e("GodotAppLoader", "expand_notifications: performGlobalAction returned false.")
            }
        } else {
            Log.d("GodotAppLoader", "expand_notifications: Service instance is NULL.")
        }
    }

    @UsedByGodot
    fun pick_launcher_wallpaper() {
        Log.i("GodotAppLoader", "Starting System Wallpaper Picker")
        activity?.let { act ->
            val intent = Intent(Intent.ACTION_SET_WALLPAPER)
            act.startActivity(Intent.createChooser(intent, "Set Wallpaper"))
        }
    }

    @UsedByGodot
    fun clear_managed_wallpaper() {
        activity?.let { act ->
            val file = File(act.filesDir, MANAGED_WP_FILENAME)
            if (file.exists()) {
                file.delete()
                Log.i("GodotAppLoader", "Managed wallpaper deleted. Reverting to system.")
                emitSignal("on_wallpaper_changed")
            }
        }
    }

    override fun onMainActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onMainActivityResult(requestCode, resultCode, data)
        if (requestCode == PICK_WALLPAPER_REQ_CODE && resultCode == Activity.RESULT_OK) {
            data?.data?.let { uri ->
                saveManagedWallpaper(uri)
            }
        } else if (requestCode == SCREEN_CAPTURE_REQ_CODE) {
            if (resultCode == Activity.RESULT_OK && data != null) {
                Log.i("GodotAppLoader", "V4.77: Screen capture consent GRANTED")
                performScreenCapture(resultCode, data)
            } else {
                Log.w("GodotAppLoader", "V4.77: Screen capture consent DENIED")
                make_toast("Wallpaper sync requires screen capture permission")
            }
        }
    }

    // V4.77: Launch the MediaProjection consent dialog
    @UsedByGodot
    fun capture_wallpaper() {
        Log.e("GodotAppLoader", "V4.77: ===== capture_wallpaper() ENTRY =====")
        val act = activity ?: run {
            Log.e("GodotAppLoader", "V4.77: Activity is NULL, cannot capture")
            return
        }
        Log.e("GodotAppLoader", "V4.77: Activity is valid: ${act.javaClass.name}")
        try {
            val projectionManager = act.getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
            Log.e("GodotAppLoader", "V4.77: Got MediaProjectionManager, creating intent...")
            val captureIntent = projectionManager.createScreenCaptureIntent()
            Log.e("GodotAppLoader", "V4.77: Intent created, calling startActivityForResult with code $SCREEN_CAPTURE_REQ_CODE")
            act.startActivityForResult(captureIntent, SCREEN_CAPTURE_REQ_CODE)
            Log.e("GodotAppLoader", "V4.77: startActivityForResult called SUCCESSFULLY (dialog should appear)")
        } catch (e: Exception) {
            Log.e("GodotAppLoader", "V4.77: EXCEPTION in capture_wallpaper: ${e.javaClass.name}: ${e.message}")
            e.printStackTrace()
            make_toast("Screen capture unavailable: ${e.message}")
        }
    }

    // V4.77b: Delegate capture to ScreenCaptureService (fixes Android 14 crash)
    // The service must call startForeground() BEFORE getMediaProjection()
    private fun performScreenCapture(resultCode: Int, data: Intent) {
        val act = activity ?: return
        Log.e("GodotAppLoader", "V4.77b: performScreenCapture — passing consent to service")
        
        try {
            // Set up callback for when capture completes
            ScreenCaptureService.onCaptureComplete = {
                Log.e("GodotAppLoader", "V4.77b: Capture complete callback — emitting signal")
                act.runOnUiThread {
                    make_toast("Wallpaper synced successfully!")
                    emitSignal("on_wallpaper_changed")
                }
            }
            
            // Pass consent result to the service via intent extras
            val serviceIntent = Intent(act, ScreenCaptureService::class.java).apply {
                putExtra(ScreenCaptureService.EXTRA_RESULT_CODE, resultCode)
                putExtra(ScreenCaptureService.EXTRA_RESULT_DATA, data)
            }
            
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                act.startForegroundService(serviceIntent)
            } else {
                act.startService(serviceIntent)
            }
            Log.e("GodotAppLoader", "V4.77b: Service started with consent data")
        } catch (e: Exception) {
            Log.e("GodotAppLoader", "V4.77b: FAILED to start capture service: ${e.javaClass.name}: ${e.message}")
            e.printStackTrace()
            make_toast("Capture failed: ${e.message}")
        }
    }


    private fun handleWallpaperIntent(intent: Intent) {
        if (intent == lastProcessedIntent) return
        lastProcessedIntent = intent
        
        val action = intent.action
        Log.i("GodotAppLoader", "V4.71: handleWallpaperIntent Action=$action")
        
        if (action == Intent.ACTION_ATTACH_DATA || action == Intent.ACTION_SET_WALLPAPER) {
            intent.data?.let { uri ->
                Log.i("GodotAppLoader", "V4.71: Incoming URI: $uri")
                saveManagedWallpaper(uri)
            }
        } else if (action == Intent.ACTION_SEND) {
            val uri = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
            } else {
                @Suppress("DEPRECATION")
                intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)
            }
            
            if (uri != null) {
                Log.i("GodotAppLoader", "V4.71: Incoming SHARE URI: $uri")
                saveManagedWallpaper(uri)
            } else {
                Log.e("GodotAppLoader", "V4.71: SHARE Intent received but URI was NULL")
            }
        }
    }

    private fun saveManagedWallpaper(uri: Uri) {
        val act = activity ?: return
        try {
            Log.i("GodotAppLoader", "Attempting to save wallpaper from URI: $uri")
            
            // Critical for Share intents: Open stream immediately before permission might expire
            act.contentResolver.openInputStream(uri)?.use { input ->
                val outFile = File(act.filesDir, MANAGED_WP_FILENAME)
                FileOutputStream(outFile).use { output ->
                    input.copyTo(output)
                }
                Log.i("GodotAppLoader", "Managed Wallpaper SAVED successfully to filesDir")
                
                // Signal to Godot that it should re-fetch everything
                emitSignal("on_wallpaper_changed")
                
                // Show confirmation on UI thread safely
                act.runOnUiThread {
                    Toast.makeText(act, "Launcher Wallpaper Updated", Toast.LENGTH_SHORT).show()
                }
            } ?: Log.e("GodotAppLoader", "InputStream was NULL for URI: $uri")
            
        } catch (e: SecurityException) {
            Log.e("GodotAppLoader", "SecurityException: Permission denied for URI: $uri", e)
            make_toast("Permission Denied: Could not read wallpaper file")
        } catch (e: Exception) {
            Log.e("GodotAppLoader", "Failed to save managed wallpaper", e)
            make_toast("Error saving wallpaper: ${e.message}")
        }
    }

    private fun importSystemWallpaper() {
        val act = activity ?: return
        try {
            val wallpaperManager = WallpaperManager.getInstance(act)
            var bitmap: Bitmap? = null

            // A. Try FD Retrieval (High quality, bypasses some issues)
            try {
                val pfd = wallpaperManager.getWallpaperFile(WallpaperManager.FLAG_SYSTEM)
                if (pfd != null) {
                    bitmap = BitmapFactory.decodeFileDescriptor(pfd.fileDescriptor)
                    pfd.close()
                }
            } catch (e: Exception) { Log.d("GodotAppLoader", "Import: FD fail: ${e.message}") }

            // B. Fallback to peek/getDrawable
            if (bitmap == null) {
                val drawable = wallpaperManager.peekDrawable() ?: wallpaperManager.drawable
                if (drawable != null) {
                    bitmap = if (drawable is BitmapDrawable) {
                        drawable.bitmap
                    } else {
                        val bmp = Bitmap.createBitmap(drawable.intrinsicWidth.coerceAtLeast(1), 
                                                    drawable.intrinsicHeight.coerceAtLeast(1), 
                                                    Bitmap.Config.ARGB_8888)
                        val canvas = Canvas(bmp)
                        drawable.setBounds(0, 0, canvas.width, canvas.height)
                        drawable.draw(canvas)
                        bmp
                    }
                }
            }

            if (bitmap != null) {
                val outFile = File(act.filesDir, MANAGED_WP_FILENAME)
                FileOutputStream(outFile).use { output ->
                    bitmap.compress(Bitmap.CompressFormat.JPEG, 95, output)
                }
                Log.i("GodotAppLoader", "System Wallpaper IMPORTED successfully to managed storage")
            } else {
                Log.e("GodotAppLoader", "System Wallpaper Import FAILED: No bitmap found")
                // V4.77: On Android 13+, direct access is blocked. Auto-trigger screen capture.
                if (Build.VERSION.SDK_INT >= 33) {
                    Log.i("GodotAppLoader", "V4.77: API 33+ detected — triggering MediaProjection capture")
                    capture_wallpaper()
                }
            }
        } catch (e: Exception) {
            Log.e("GodotAppLoader", "Failed to import system wallpaper", e)
        }
    }
}
