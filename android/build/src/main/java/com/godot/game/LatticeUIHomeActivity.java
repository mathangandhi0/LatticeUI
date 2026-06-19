package com.godot.game;

public class LatticeUIHomeActivity extends GodotApp {
    @Override
    protected void onNewIntent(android.content.Intent intent) {
        super.onNewIntent(intent);
        if (intent != null && intent.hasCategory(android.content.Intent.CATEGORY_HOME)) {
            android.util.Log.d("LatticeUIHomeActivity", "Home Button Pressed! Broadcasting...");
            android.content.Intent broadcast = new android.content.Intent("com.example.godotlauncher.HOME_PRESSED");
            sendBroadcast(broadcast);
        }
    }
}
