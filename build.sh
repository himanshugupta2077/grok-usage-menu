#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

APP="$HOME/Applications/Grok Usage.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

swiftc -O -o "$APP/Contents/MacOS/GrokUsage" main.swift -framework AppKit
swiftc -o /tmp/render-grok-icon render-icon.swift -framework AppKit
/tmp/render-grok-icon "$PWD/grok.png"
cp Info.plist "$APP/Contents/Info.plist"
cp grok.png "$APP/Contents/Resources/grok.png"
codesign --force --sign - --identifier local.himanshu.GrokUsage "$APP"
xattr -cr "$APP" 2>/dev/null || true
echo "built $APP"
