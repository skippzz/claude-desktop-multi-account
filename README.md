# Several Claude accounts side by side on Windows

Run extra Claude Desktop windows, each signed in to a different Claude account, for example work and personal, at the same time. Each window has its own login, settings and Claude Code history, and its own coloured icon and taskbar button so you can tell them apart.

> **Unofficial.** Not made by or affiliated with Anthropic. It relies on app behaviour that isn't a documented feature, so a future app update could break it.

## What you get

- **Claude A** on your Desktop: your normal Claude app, unchanged.
- **Claude B**: a second, separate Claude window that you sign in to with your other account.
- **Claude C, D, ...**: run setup again for each further account. It takes the next free letter.
- All of them can be open at the same time.
- **Each extra profile looks different.** Its icon is the app's logo in its own colour (B blue, C green, D purple, E teal, F pink, G gold, H red, then round again) with the profile's letter on it, and its windows get their own taskbar button with that icon instead of stacking on the normal Claude button. The same icon shows in Alt+Tab.
- **Each extra profile's window has a coloured frame.** A thin border in the profile's colour runs around the window, with the profile name on a small tab at the top centre, so you can see which account you are in while you type.

For profile C the folders are `claude-desktop-c` and `.claude-c`, and so on.

| | Normal profile (A) | New profile (B) |
|---|---|---|
| Desktop app data: login, preferences, extensions | the app's package folder* | `%USERPROFILE%\claude-desktop-b` |
| Claude Code data: settings, plugins, memory, session history | `%USERPROFILE%\.claude` | `%USERPROFILE%\.claude-b` |

\* `%LOCALAPPDATA%\Claude-Data\claude_<id>` on current builds, `%LOCALAPPDATA%\Packages\Claude_<id>\LocalCache\Roaming\Claude` on older ones. The scripts check both.

## Requirements

- Windows 10 or 11
- Claude Desktop installed from [claude.ai/download](https://claude.ai/download) (the current MSIX build)

Tested on Windows 10 22H2 with Claude Desktop 3.6556.2.0 and Claude Code 2.1.308.

## Setup

1. Download this repo (**Code > Download ZIP**) and unzip it, or `git clone` it.
2. Double-click **`Setup.cmd`**.
3. Double-click **Claude B** on your Desktop and sign in with your other account.

That's it. Your normal profile is only read during setup, never changed.

**For a third or fourth account, double-click `Setup.cmd` again.** Each run makes the next free letter: B, then C, then D.

To pick the name or colour yourself, run it from a terminal:

```bat
Setup.cmd -Name Work -Color Green
```

If you made profiles with an older version of these scripts, give them the new icons and taskbar buttons with:

```bat
Setup.cmd -Refresh
```

`setup.ps1` options:

| Option | What it does |
|---|---|
| `-Name <name>` | Profile name, used in folder names and the shortcut label. Default: the next free letter. |
| `-Color <colour>` | Icon colour: `Blue`, `Green`, `Purple`, `Teal`, `Pink`, `Gold`, `Red` or `Grey`. Default: by profile letter. |
| `-Frame <pixels>` | Thickness of the coloured window frame, 0 to 12. Default `3`. `0` turns the frame and its name tab off. |
| `-Refresh` | Re-make the launcher, icon and shortcut of an existing profile (`-Name`), or of all of them. Add `-Color` or `-Frame` to change a profile's colour or frame. Logins, settings and history are not touched. |
| `-Empty` | Start the new profile empty instead of copying your current setup. |
| `-NoMemory` | Copy your setup but leave out per-project memory. |
| `-Launch` | Open the new profile when setup is done. |

## What gets copied into the new profile

| Copied | Not copied |
|---|---|
| Claude Code `settings.json` and plugins | Logins and tokens |
| User-level `CLAUDE.md`, skills, agents, commands, output styles, hooks | Chat history and Code session history |
| Per-project memory | Anything tied to an account, session or this device |
| Desktop extensions and whether each is on or off | Session presets and default model/effort (set these in the new window) |
| Desktop preferences that aren't tied to an account (theme, language, browser tools, ...) | |

After setup the two profiles don't sync. A setting or memory you add in one won't show up in the other.

## After you sign in (optional)

**Copy your per-folder permission modes.** Claude Desktop remembers the permission mode you picked for each folder, per account. To give the new account the same ones:

```powershell
powershell -ExecutionPolicy Bypass -File .\copy-folder-modes.ps1 -Name B
```

Claude B has to be closed for this. The script offers to close it.

**Check that it's really separate.** Start one Code session in Claude B, send a message, then:

```powershell
powershell -ExecutionPolicy Bypass -File .\verify.ps1 -Name B
```

It checks that B is signed in to a different account and that B's Code sessions are stored in `.claude-b`, not `.claude`.

## How it works

- **`--user-data-dir`** gives the second window its own app data, so it has its own login and preferences.
- **`CLAUDE_CONFIG_DIR`** is set in the launcher. The Claude Code sessions that the window starts inherit it, so they use `.claude-b`.
- **Code sessions log in through the window that started them**, so each window's Code sessions run on that window's account.
- **The MSIX install blocks starting `Claude.exe` directly** ("Access is denied"). The app ships an alias, `claude-desktop.exe`, which accepts these flags and keeps working across updates. The launcher uses it.
- **Icons** are made at setup time from your installed app's own artwork: unchanged for A, re-coloured with a letter badge for the others. They're stored in `%USERPROFILE%\.claude-shortcuts`. No Anthropic artwork is included in this repo.
- **Separate taskbar buttons** come from `tag-window.ps1`, which each launcher starts hidden next to the app. It finds the profile's windows and, from the outside, gives them their own taskbar identity, icon and label ("Claude C"). It changes nothing inside the app and exits when the profile is closed. If you pin that taskbar button, it starts the same profile.
- **The coloured frame** is drawn by the same script. It is a separate, hollow window that Windows keeps directly above the Claude window it belongs to, follows it when it moves or resizes, and lets every click through. It covers the outermost few pixels of the app, and nothing inside the app is changed.
- **Nothing is written under AppData.** Programs running inside the Claude app, including Claude Code sessions, have their AppData writes redirected into the app's package folder, where Explorer can't see them. Keeping everything in your user folder means you can run these scripts from a normal terminal or ask Claude to run them for you.

## Things to know

- Extra profiles get their own taskbar button and icon only when started from their shortcut (or their pinned taskbar button). It can take a second or two after the window appears. The window title still says "Claude", and the tray icons all look the same.
- Each open extra profile has one hidden PowerShell process for this (about 90 MB of memory, no measurable CPU while idle). If you end it, the profile keeps working and only its frame and window icon go away.
- The frame can trail the window by a moment while you drag it. Only the app's main, resizable windows get one; small helper windows don't. If the name tab sits on something you need in the title bar, turn the frame off with `Setup.cmd -Refresh -Frame 0`.
- Closing a profile's window may leave it running in the tray.
- Tested with Claude Desktop 4.23118.1.0, which keeps the normal profile's data in `%LOCALAPPDATA%\Claude-Data`. Older builds that keep it in the package folder are still supported.
- If your `settings.json` has hooks or a status line that point at files inside `.claude`, the new profile keeps using those same files.
- On a Team or Enterprise account, your organization's managed settings apply to that profile and win over the copied ones.
- Sign-in from the second window worked normally in testing. If yours finishes in the wrong window, please open an issue.
- If an app update changes how this works, Claude B could open as your normal profile. Run `verify.ps1` after big updates.

## Remove a profile

```powershell
powershell -ExecutionPolicy Bypass -File .\uninstall.ps1 -Name B
```

This asks before deleting anything. Add `-WhatIf` to see what would be deleted. It removes the profile's folders, shortcut and icon. Your normal profile and the Claude A shortcut stay.

## Use it responsibly

This is for keeping separate accounts apart: work and personal, or different clients. Don't use it to get around usage limits, and follow [Anthropic's Usage Policy](https://www.anthropic.com/legal/aup) and the terms of each account.

## License

[MIT](LICENSE)
