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

    @Override
    public void setPictureInPictureParams(android.app.PictureInPictureParams params) {
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
            try {
                super.setPictureInPictureParams(params);
            } catch (IllegalStateException e) {
                android.util.Log.w("LatticeUIHomeActivity", "Failed to set PictureInPictureParams: " + e.getMessage());
            }
        }
    }
}

