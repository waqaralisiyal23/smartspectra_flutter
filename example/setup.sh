#!/usr/bin/env bash
# Generates the example's android/ and ios/ folders and applies the settings
# the SmartSpectra SDK needs. Run once from the example/ directory:
#   cd example && ./setup.sh
set -euo pipefail
cd "$(dirname "$0")"

flutter create --platforms=android,ios --org dev.waqar --project-name smartspectra_flutter_example .
# flutter create adds a counter-app test that does not apply to this example.
rm -f test/widget_test.dart

# --- Android -------------------------------------------------------------
GRADLE=android/app/build.gradle.kts
# SmartSpectra needs minSdk 28.
perl -pi -e 's/minSdk = flutter\.minSdkVersion/minSdk = 28/' "$GRADLE"
# Use Flutter's built-in Kotlin (the plugin relies on it; Flutter 3.47+).
perl -pi -e 's/^android\.builtInKotlin=false/android.builtInKotlin=true/' android/gradle.properties

# --- iOS -----------------------------------------------------------------
PLIST=ios/Runner/Info.plist
/usr/libexec/PlistBuddy -c "Delete :NSCameraUsageDescription" "$PLIST" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :NSCameraUsageDescription string 'The camera measures pulse and breathing on this device. No video is recorded.'" "$PLIST"
# SmartSpectra needs iOS 17.
perl -pi -e 's/IPHONEOS_DEPLOYMENT_TARGET = [0-9.]+;/IPHONEOS_DEPLOYMENT_TARGET = 17.0;/g' ios/Runner.xcodeproj/project.pbxproj

flutter pub get

cat <<'EOF'

Done. Check that:
  - android/app/build.gradle.kts has minSdk = 28 and compileSdk >= 36
  - android/settings.gradle.kts uses AGP >= 8.10.1
  - android/gradle.properties has android.builtInKotlin=true
Then run on a physical device:
  cp api_keys.example.json api_keys.json   # then paste your key
  flutter run --dart-define-from-file=api_keys.json
EOF
