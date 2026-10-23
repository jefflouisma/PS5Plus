#!/bin/sh
# Install the nightly upstream merge as a LaunchAgent. It runs daily at HOUR (default 03:00);
# launchd runs a missed job when the Mac wakes. Usage: install-nightly.sh [HOUR]
set -eu
root="$(cd "$(dirname "$0")/.." && pwd)"
label=com.jefflouisma.ps5plus.nightly
plist="$HOME/Library/LaunchAgents/$label.plist"
hour="${1:-3}"
case "$hour" in [0-9]|1[0-9]|2[0-3]) ;; *) echo "HOUR must be 0-23" >&2; exit 1;; esac

mkdir -p "$(dirname "$plist")"
cat > "$plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$label</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/sh</string>
        <string>$root/scripts/nightly-sync.sh</string>
    </array>
    <key>StartCalendarInterval</key>
    <dict>
        <key>Hour</key>
        <integer>$hour</integer>
        <key>Minute</key>
        <integer>0</integer>
    </dict>
    <key>Nice</key>
    <integer>10</integer>
    <key>LowPriorityIO</key>
    <true/>
</dict>
</plist>
EOF
plutil -lint "$plist" > /dev/null
launchctl bootout "gui/$(id -u)/$label" 2> /dev/null || true
launchctl bootstrap "gui/$(id -u)" "$plist"
echo "Installed $label for $hour:00 daily. Run it now with: launchctl kickstart gui/$(id -u)/$label"
