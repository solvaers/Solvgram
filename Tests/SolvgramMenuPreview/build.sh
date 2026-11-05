#!/bin/zsh
set -eu
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
STAGE="${1:-/tmp/SolvgramMenuPreview}"
APP="$STAGE/SolvgramMenuPreview.app"
mkdir -p "$APP"
SDK="$(xcrun --sdk iphonesimulator --show-sdk-path)"
xcrun --sdk iphonesimulator clang -target arm64-apple-ios17.0-simulator -isysroot "$SDK" \
  -fobjc-arc -fmodules -fmodules-cache-path=/tmp/solvgram-preview-modules \
  "$ROOT/Tests/SolvgramMenuPreview/main.m" \
  "$ROOT/Solvgram/SolvgramMenu/Sources/SolvgramIcons.m" \
  -framework UIKit -framework Foundation -framework CoreGraphics -framework MapKit \
  -framework CoreLocation -framework UserNotifications -o "$APP/SolvgramMenuPreview"
cp "$ROOT"/Solvgram/SolvgramMenu/Resources/*.png "$APP/"
cat > "$APP/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>app.solvgram.menu-preview</string>
<key>CFBundleName</key><string>Menu Preview</string>
<key>CFBundleExecutable</key><string>SolvgramMenuPreview</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>MinimumOSVersion</key><string>17.0</string>
<key>UILaunchScreen</key><dict/>
<key>UISupportedInterfaceOrientations</key><array><string>UIInterfaceOrientationPortrait</string><string>UIInterfaceOrientationLandscapeLeft</string><string>UIInterfaceOrientationLandscapeRight</string></array>
<key>UIDeviceFamily</key><array><integer>1</integer><integer>2</integer></array>
</dict></plist>
PLIST
codesign --force --sign - "$APP"
echo "$APP"
