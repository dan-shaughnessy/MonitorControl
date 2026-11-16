#!/bin/sh
# Install the merged app per-user. Retire the old companion from Automation settings after launch.
set -eu
source_app=${1:?Usage: scripts/install-monitorcontrol.sh /path/to/MonitorControl.app}
identity=$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$source_app/Contents/Info.plist")
[ "$identity" = app.monitorcontrol.MonitorControl ] || { echo 'This is not the MonitorControl app bundle.' >&2; exit 1; }
codesign --verify --deep --strict "$source_app"
if pgrep -x MonitorControl >/dev/null; then
  echo 'Quit MonitorControl before installing this build. The companion can stay running until migration.' >&2
  exit 1
fi
install_dir="$HOME/Applications"
target_app="$install_dir/MonitorControl.app"
mkdir -p "$install_dir"
if [ -e "$target_app" ]; then
  backup="$install_dir/MonitorControl-before-automation-$(date +%Y%m%d-%H%M%S).app"
  mv "$target_app" "$backup"
  echo "Previous app retained at $backup"
fi
ditto "$source_app" "$target_app"
codesign --verify --deep --strict "$target_app"
echo "Installed $target_app"
echo 'Open it, allow Bluetooth access, then open Settings > Automation > Retire Old Companion.'
echo 'Saved devices/inputs are migrated automatically. Migration and app launch do not switch inputs.'
