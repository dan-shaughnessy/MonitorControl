#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
# Pinned Rust core and licenses; never invokes AudioSync's installer.
(cd Vendor/AudioSync && ./scripts/build_core.sh)
build_dir=${DESK_BUILD_DIR:-/tmp/monitorcontrol-desk-release}
xcodebuild -project MonitorControl.xcodeproj -scheme MonitorControl \
  -configuration Release -derivedDataPath "$build_dir" \
  -clonedSourcePackagesDirPath /tmp/monitorcontrol-desk-packages \
  CODE_SIGNING_ALLOWED=NO MACOSX_DEPLOYMENT_TARGET=15.0 ARCHS=arm64 build
bundle="$build_dir/Build/Products/Release/MonitorControl.app"
mkdir -p "$bundle/Contents/Resources/AudioSync-Licenses"
cp Vendor/AudioSync/LICENSE Vendor/AudioSync/THIRD_PARTY_NOTICES.md "$bundle/Contents/Resources/AudioSync-Licenses/"
cp -R Vendor/AudioSync/core/target/universal-apple-darwin/release/licenses/rust "$bundle/Contents/Resources/AudioSync-Licenses/"
codesign --force --deep --sign - --timestamp=none "$bundle"
codesign --verify --deep --strict "$bundle"
echo "$bundle"
