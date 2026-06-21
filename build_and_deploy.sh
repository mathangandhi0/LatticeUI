#!/bin/bash
# PureLauncher Pro Build and Deploy Script V1.4 (Bash Edition)
# This version ensures Gradle and ADB logs are streamed correctly to the screen and file.

export JAVA_HOME="/home/g-mathan/java"
export ANDROID_HOME="/home/g-mathan/Android/Sdk"
export PATH="$JAVA_HOME/bin:/home/g-mathan/.local/bin:$ANDROID_HOME/platform-tools:$PATH"
LOG_FILE="build_log.txt"

ADB_PATH="adb -s 192.168.1.3:36205"

# Helper to log and display headers
function write_header() {
    local message="$1"
    local ts=$(date +"%Y-%m-%d %H:%M:%S")
    echo -e "\n\033[1;33m[$ts] $message\033[0m"
    echo "[$ts] $message" | tee -a "$LOG_FILE"
}

# Check for flags
FAST=false
DEPLOY_ONLY=false
if [[ "$*" == *"--fast"* ]]; then
    FAST=true
fi
if [[ "$*" == *"--deploy-only"* ]]; then
    DEPLOY_ONLY=true
fi

# Initialize Log
echo "======================================================" > "$LOG_FILE"
echo "  PureLauncher Pro Build Session: $(date)" >> "$LOG_FILE"
echo "======================================================" > "$LOG_FILE"

if [ "$DEPLOY_ONLY" = false ]; then
    write_header "Starting Build and Deploy Workflow (Bash Edition - Optimized)..."

    # Pre-Build Optimization: Only kill java if not a fast build
    if [ "$FAST" = false ]; then
        echo -e "\033[1;36mProactively cleaning up build environment...\033[0m"
        pkill -f 'java.*gradle' || true
        sleep 2

        # Cleanup build directories manually to ensure a truly clean state
        echo -e "\033[1;30mClearing stale build intermediates and plugins...\033[0m"
        rm -rf android/build/build android_plugin/build
    else
        echo -e "\033[1;32mFast Build: Skipping environment cleanup...\033[0m"
    fi

    # V4.76f: Robust Library Management
    DEBUG_LIB_DIR="android/build/libs/debug"
    RELEASE_LIB_DIR="android/build/libs/release"
    DEBUG_LIB_FILE="$DEBUG_LIB_DIR/godot-lib.template_debug.aar"
    RELEASE_LIB_FILE="$RELEASE_LIB_DIR/godot-lib.template_release.aar"

    # 1. Kill stale plugin but PRESERVE the engine template
    rm -f "$RELEASE_LIB_DIR/AppLoader.aar"

    # 2. Safety Check: If we lost the release template, abort clearly
    if [ ! -f "$RELEASE_LIB_FILE" ]; then
        echo -e "\033[1;31mERROR: Release template missing: $RELEASE_LIB_FILE\033[0m"
        echo -e "\033[1;31mPlease export a release template from the Godot editor first.\033[0m"
        exit 1
    fi

    # 0. Build Android Plugin (Kotlin Recompilation)
    write_header "[0/6] Rebuilding Kotlin Android Plugin (AppLoader)..."
    cd android_plugin || exit 1
    chmod +x ./gradlew

    if [ "$FAST" = true ]; then
        ./gradlew assembleRelease 2>&1 | tee -a "../$LOG_FILE"
    else
        ./gradlew clean assembleRelease 2>&1 | tee -a "../$LOG_FILE"
    fi

    if [ ${PIPESTATUS[0]} -eq 0 ]; then
        echo -e "\033[1;32mRebuild Success. Syncing AppLoader.aar...\033[0m"
        cp -f build/outputs/aar/android_plugin-release.aar ../android/build/libs/release/AppLoader.aar 2>&1 | tee -a "../$LOG_FILE"
    else
        write_header "[CRITICAL ERROR] Kotlin Plugin Build Failed. Stopping."
        cd ..
        exit 1
    fi
    cd ..

    # NOTE: Kotlin source is NOT synced here — AppLoader is compiled into the AAR above.
    # Syncing source AND including the AAR causes duplicate class errors at dex merge time.

    # 2. Sync Godot Assets
    write_header "[2/7] Synchronizing Scripts and Scenes..."
    mkdir -p android/build/src/main/assets/scripts
    mkdir -p android/build/assets/scripts
    mkdir -p android/build/src/main/assets/assets
    mkdir -p android/build/assets/assets

    # Purge ghost/stale packs that cause launch errors
    echo -e "\033[1;30mPurging stale .pck files...\033[0m"
    rm -f android/build/assets/*.pck android/build/assets/*.sparsepck

    # Run copy operations and stream output
    echo -e "\033[1;30mSyncing Project Assets...\033[0m"

    # Root files
    cp -f project.godot android/build/src/main/assets/ 2>&1 | tee -a "$LOG_FILE"
    cp -f project.godot android/build/assets/ 2>&1 | tee -a "$LOG_FILE"

    shopt -s nullglob
    for f in *.tscn *.png *.png.import; do
        cp -f "$f" android/build/src/main/assets/ 2>&1 | tee -a "$LOG_FILE"
        cp -f "$f" android/build/assets/ 2>&1 | tee -a "$LOG_FILE"
    done
    shopt -u nullglob

    # Godot 4 Script Cache (Crucial for launch)
    CACHE_DIR="android/build/assets/.godot"
    CACHE_DIR_SRC="android/build/src/main/assets/.godot"
    mkdir -p "$CACHE_DIR" "$CACHE_DIR_SRC"

    if [ -f .godot/global_script_class_cache.cfg ]; then
        cp -f .godot/global_script_class_cache.cfg "$CACHE_DIR/" 2>&1 | tee -a "$LOG_FILE"
        cp -f .godot/global_script_class_cache.cfg "$CACHE_DIR_SRC/" 2>&1 | tee -a "$LOG_FILE"
    fi

    # Script and Asset directories
    if ls scripts/*.gd 1> /dev/null 2>&1; then
        cp -f scripts/*.gd android/build/src/main/assets/scripts/ 2>&1 | tee -a "$LOG_FILE"
        cp -f scripts/*.gd android/build/assets/scripts/ 2>&1 | tee -a "$LOG_FILE"
    fi

    if [ -d assets ]; then
        cp -rf assets android/build/src/main/assets/ 2>&1 | tee -a "$LOG_FILE"
        cp -rf assets android/build/ 2>&1 | tee -a "$LOG_FILE"
    fi

    # 3. Build
    write_header "[3/7] Performing Gradle Build..."
    cd android/build || exit 1

    # Run Gradle and ensure output is streamed
    chmod +x ./gradlew

    KEYSTORE_PATH="/home/g-mathan/latticeui-main/lattice_release.jks"
    KEYSTORE_PASS="Lattice@2025#Secure"
    KEY_ALIAS="lattice_key"

    if [ "$FAST" = true ]; then
        ./gradlew assembleRelease -Pperform_signing=true \
            -Prelease_keystore_file="$KEYSTORE_PATH" \
            -Prelease_keystore_password="$KEYSTORE_PASS" \
            -Prelease_keystore_alias="$KEY_ALIAS" \
            -Pexport_package_name="com.example.latticeui" \
            -Pexport_version_code="1" \
            -Pexport_version_name="1.0" \
            -Pexport_version_min_sdk="24" \
            -Pexport_version_target_sdk="36" \
            -x lintVitalAnalyzeMonoRelease -x lintVitalAnalyzeStandardRelease \
            2>&1 | tee -a "../../$LOG_FILE"
    else
        ./gradlew clean assembleRelease -Pperform_signing=true \
            -Prelease_keystore_file="$KEYSTORE_PATH" \
            -Prelease_keystore_password="$KEYSTORE_PASS" \
            -Prelease_keystore_alias="$KEY_ALIAS" \
            -Pexport_package_name="com.example.latticeui" \
            -Pexport_version_code="1" \
            -Pexport_version_name="1.0" \
            -Pexport_version_min_sdk="24" \
            -Pexport_version_target_sdk="36" \
            -x lintVitalAnalyzeMonoRelease -x lintVitalAnalyzeStandardRelease \
            2>&1 | tee -a "../../$LOG_FILE"
    fi

    if [ ${PIPESTATUS[0]} -ne 0 ]; then
        write_header "[CRITICAL ERROR] Build failed even after retry. Stopping."
        cd ../..
        exit 1
    fi
    cd ../..
else
    write_header "Deploy Only Mode: Skipping all build and sync steps..."
fi

# 3. ADB Setup
if [[ "$*" == *"--build-only"* ]]; then
    write_header "Build Successful. Skipping deployment as requested."
    exit 0
fi

write_header "[4/7] Preparing Device Environment..."
APP_ID="com.example.latticeui"
MAIN_ACTIVITY="com.godot.game.LatticeUIHomeActivity"
APK_PATH="android/build/build/outputs/apk/standard/release/android_release.apk"

# 4. Uninstall existing app to guarantee fresh install
write_header "[5/7] Deploying APK to Device (Clean Install)..."
echo "Uninstalling existing app to guarantee a clean install..."
$ADB_PATH uninstall "$APP_ID" 2>/dev/null
$ADB_PATH install -r "$APK_PATH" || exit 1

write_header "[6/7] Launching PureLauncher..."
# Send launch intent
$ADB_PATH shell am start -n "$APP_ID/$MAIN_ACTIVITY" || exit 1

write_header "[7/7] Capturing Startup logs (1500 lines)..."
# Stream logs directly to the user's terminal
$ADB_PATH logcat -d -t 1500 > build_log.txt

write_header "======================================================"
echo -e "\033[1;32m  SUCCESS: Build Deployed and Launched!\033[0m"
echo -e "\033[1;32m  Review full logs in: $LOG_FILE\033[0m"
write_header "======================================================"
