#!/bin/sh
# Stops and removes LG Input Companion. Pass --purge to also delete saved settings.
set -eu
label=io.github.dan-shaughnessy.lg-input-companion
support="$HOME/Library/Application Support/LGInputCompanion"
launchctl bootout "gui/$(id -u)/$label" 2>/dev/null || true
rm -f "$HOME/Library/LaunchAgents/$label.plist"
rm -rf "$support/LGInputCompanion.app"
if [ "${1:-}" = "--purge" ]; then rm -rf "$support"; fi
echo "Removed LaunchAgent $label and the app${1:+ and settings}"
