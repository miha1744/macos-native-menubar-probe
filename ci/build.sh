#!/bin/bash
set -euo pipefail
umask 077
QB_BASE=$(cd "$(dirname "$0")" && pwd)
QB_DEST=${1:-"$QB_BASE/build"}
/bin/mkdir -p "$QB_DEST/QuietBarCaptureProbe.app/Contents/MacOS"
/usr/bin/xcrun swiftc -parse-as-library -swift-version 5 -O -target "$(/usr/bin/uname -m)-apple-macosx14.0" \
  -framework AppKit -framework ScreenCaptureKit -framework CoreMedia -framework CoreImage \
  "$QB_BASE/CaptureProbe.swift" -o "$QB_DEST/QuietBarCaptureProbe.app/Contents/MacOS/QuietBarCaptureProbe"
cat > "$QB_DEST/QuietBarCaptureProbe.app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>local.quietbar.ci.captureprobe</string>
<key>CFBundleName</key><string>QuietBarCaptureProbe</string>
<key>CFBundleExecutable</key><string>QuietBarCaptureProbe</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
/usr/bin/codesign --force --sign - "$QB_DEST/QuietBarCaptureProbe.app"
printf '%s\n' "$QB_DEST/QuietBarCaptureProbe.app"
