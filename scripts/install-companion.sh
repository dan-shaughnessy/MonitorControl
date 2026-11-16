#!/bin/sh
# Builds and installs LG Input Companion for the current user, and loads its LaunchAgent.
# Needs no sudo. Saved settings in ~/Library/Application Support/LGInputCompanion/config.json are kept.
set -eu
cd "$(dirname "$0")/.."
label=io.github.dan-shaughnessy.lg-input-companion
support="$HOME/Library/Application Support/LGInputCompanion"
agent="$HOME/Library/LaunchAgents/$label.plist"
build=$(mktemp -d "${TMPDIR:-/tmp}/lg-input-companion.XXXXXX")
trap 'rm -rf "$build"' EXIT
scripts/build-companion.sh "$build" >/dev/null
launchctl bootout "gui/$(id -u)/$label" 2>/dev/null || true
mkdir -p "$support" "$HOME/Library/LaunchAgents" "$HOME/Library/Logs"
rm -rf "$support/LGInputCompanion.app"
ditto "$build/LGInputCompanion.app" "$support/LGInputCompanion.app"
cat > "$agent" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$label</string>
  <key>ProgramArguments</key><array><string>$support/LGInputCompanion.app/Contents/MacOS/LGInputCompanion</string></array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><dict><key>SuccessfulExit</key><false/></dict>
  <key>LimitLoadToSessionType</key><string>Aqua</string>
  <key>ProcessType</key><string>Interactive</string>
  <key>StandardOutPath</key><string>$HOME/Library/Logs/LGInputCompanion.log</string>
  <key>StandardErrorPath</key><string>$HOME/Library/Logs/LGInputCompanion.log</string>
</dict>
</plist>
PLIST
launchctl bootstrap "gui/$(id -u)" "$agent"
echo "Installed $support/LGInputCompanion.app"
echo "LaunchAgent $label loaded from $agent"
