#!/bin/sh
# Builds LGInputCompanion.app with Command Line Tools only (no Xcode, storyboard or asset catalog).
# Usage: scripts/build-companion.sh [output-dir]   (default: /tmp/lg-input-companion-build)
set -eu
cd "$(dirname "$0")/.."
out=${1:-/tmp/lg-input-companion-build}
app="$out/LGInputCompanion.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS"
swiftc -O -target arm64-apple-macos12.0 \
  -import-objc-header MonitorControl/Support/Bridging-Header.h \
  MonitorControl/Model/DDCInputSource.swift MonitorControl/Support/Arm64DDC.swift \
  Companion/Sources/*.swift \
  -F /System/Library/PrivateFrameworks -framework CoreDisplay -framework IOBluetooth -framework AppKit \
  -o "$app/Contents/MacOS/LGInputCompanion" 2>&1 | grep -v -E 'warning:|note:|^\s*[0-9]* \||^\s*\||^\s*$|^\[#|^\s*`-' || true
test -x "$app/Contents/MacOS/LGInputCompanion"
version=$(git rev-parse --short HEAD 2>/dev/null || echo dev)
cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>io.github.dan-shaughnessy.LGInputCompanion</string>
  <key>CFBundleName</key><string>LG Input Companion</string>
  <key>CFBundleExecutable</key><string>LGInputCompanion</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>$version</string>
  <key>LSMinimumSystemVersion</key><string>12.0</string>
  <key>LSUIElement</key><true/>
  <key>NSBluetoothAlwaysUsageDescription</key><string>Detects when your selected Bluetooth keyboard connects or disconnects, to switch the monitor input. Key presses are never read.</string>
</dict>
</plist>
PLIST
codesign --force --sign - --identifier io.github.dan-shaughnessy.LGInputCompanion "$app" >/dev/null 2>&1
echo "$app"
