#!/bin/zsh
set -eu
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
STAGE="/tmp/SolvgramFilePickerAudit"
python3 "$ROOT/Tests/SolvgramFilePickerAudit/adapt.py" "$STAGE"
SDK="$(xcrun --sdk iphonesimulator --show-sdk-path)"
xcrun --sdk iphonesimulator swiftc -swift-version 5 -parse-as-library -target arm64-apple-ios17.0-simulator -sdk "$SDK" -module-cache-path /tmp/solvgram-live-swift-cache "$STAGE/main.swift" -framework UIKit -framework AVFoundation -o "$STAGE/FilePickerAudit.app/FilePickerAudit"
xcrun actool --compile "$STAGE/FilePickerAudit.app" --platform iphonesimulator --minimum-deployment-target 17.0 --target-device iphone --output-partial-info-plist "$STAGE/icons.plist" "$STAGE/AuditIcons.xcassets"
codesign --force --sign - "$STAGE/FilePickerAudit.app"
