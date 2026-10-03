#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

./build.sh

# Login is owned by ~/.local/bin/login-apps.sh so this app does not start
# in the same instant as everything else. Drop the old agent if it is still there.
PLIST="$HOME/Library/LaunchAgents/local.himanshu.GrokUsage.plist"
UID_NUM="$(id -u)"
if [[ -f "$PLIST" ]]; then
  launchctl bootout "gui/${UID_NUM}" "$PLIST" 2>/dev/null || true
  rm -f "$PLIST"
fi
killall GrokUsage 2>/dev/null || true
sleep 0.4
open -g -a "${HOME}/Applications/Grok Usage.app"
echo "menu bar item rebuilt"
