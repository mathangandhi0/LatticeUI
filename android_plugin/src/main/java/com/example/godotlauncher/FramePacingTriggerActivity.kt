package com.example.godotlauncher

import android.app.Activity
import android.os.Bundle
import android.util.Log

/**
 * A transparent dummy activity that immediately finishes.
 * Used to simulate an app transition which triggers Swappy/frame pacing reinit.
 */
class FramePacingTriggerActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Log.d("FramePacingTrigger", "Triggering frame pacing via dummy activity transition")
        
        // Show Toast to confirm execution
        android.widget.Toast.makeText(this, "Resetting Frame Pacing...", android.widget.Toast.LENGTH_SHORT).show()
        
        // Delay finish to ensure the activity is actually "seen" by the system lifecycle
        android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
            finish()
        }, 100)
    }
    
    override fun finish() {
        super.finish()
        // No animation on exit to keep it invisible
        overridePendingTransition(0, 0)
    }
}
