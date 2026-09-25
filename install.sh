#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

./build.sh

PLIST="$HOME/Library/LaunchAgents/local.himanshu.GrokUsage.plist"
mkdir -p "$(dirname "$PLIST")"
cat > "$PLIST" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key>
	<string>local.himanshu.GrokUsage</string>
	<key>ProgramArguments</key>
	<array>
		<string>/usr/bin/open</string>
		<string>-g</string>
		<string>-a</string>
		<string>${HOME}/Applications/Grok Usage.app</string>
	</array>
	<key>RunAtLoad</key>
	<true/>
	<key>LimitLoadToSessionType</key>
	<string>Aqua</string>
</dict>
</plist>
EOF

UID_NUM="$(id -u)"
launchctl bootout "gui/${UID_NUM}" "$PLIST" 2>/dev/null || true
killall GrokUsage 2>/dev/null || true
launchctl bootstrap "gui/${UID_NUM}" "$PLIST"
echo "menu bar item installed"
