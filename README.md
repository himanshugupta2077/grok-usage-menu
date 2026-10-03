# Grok Usage

A small macOS menu-bar item for Grok Build weekly usage. It shows the Grok mark, the percent used, and the time left until the weekly reset.

```
45% [4D]
```

Days are rounded to the nearest day: `[7D]`, `[6D]`, and so on. Under 24 hours it switches to hours, such as `[5H]`. Under one hour it switches to minutes, such as `[40M]`.

Click the item for the exact time left, **Refresh**, or **Quit**.

This is an unofficial menu-bar app. It is not affiliated with xAI.

## Requirements

- macOS 13 or later
- Xcode Command Line Tools (`swiftc`)
- A Grok login from `grok login`

Grok does not have to stay open. The item reads the session in `~/.grok/auth.json`.

## Install

```bash
git clone https://github.com/himanshugupta2077/grok-usage-menu.git
cd grok-usage-menu
./install.sh
```

`install.sh` builds `~/Applications/Grok Usage.app`, signs it for local use, and opens it. The menu bar has no Dock icon. It does not add a login item. On this Mac, `~/.local/bin/login-apps.sh` opens it after login, with the other menu-bar apps.

To build and open it yourself:

```bash
./build.sh
open -g -a "$HOME/Applications/Grok Usage.app"
```

## Remove

Quit it from the menu, then:

```bash
launchctl bootout "gui/$(id -u)" "$HOME/Library/LaunchAgents/local.himanshu.GrokUsage.plist"
rm -f "$HOME/Library/LaunchAgents/local.himanshu.GrokUsage.plist"
rm -rf "$HOME/Applications/Grok Usage.app"
```

## What it reads

The percent is the weekly `creditUsagePercent` from the same billing call Grok Build uses for `/usage`:

```
GET https://cli-chat-proxy.grok.com/v1/billing?format=credits
```

The bracketed time is the time left until `currentPeriod.end`. The menu shows that remainder exactly, for example `3d 20h left`.

The item refreshes about every five minutes, and again when the menu opens if the last fetch is more than a minute old. The last good reading is saved in `~/Library/Application Support/Grok Usage/reading.json` (percent and reset time only) so the bar can show a number before the network returns. If the first fetch fails, it retries about every 15 seconds until one succeeds. If the Grok access token is near expiry, or the billing call returns 401, it refreshes the token and writes the new session back to `~/.grok/auth.json` so `grok` stays logged in.

A terminal check, without opening the menu bar:

```bash
"./Grok Usage.app/Contents/MacOS/GrokUsage" --dump
```

Run that from `~/Applications` after building. It prints the menu-bar label and the exact time left.

## Privacy

The only session file it reads and writes is `~/.grok/auth.json`. It also writes the last percent and reset time to `~/Library/Application Support/Grok Usage/reading.json`. The only network calls are the Grok token refresh and the billing request. It does not send usage anywhere else.
