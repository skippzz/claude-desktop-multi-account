# Two Claude accounts side by side on Windows

Run a second Claude Desktop window signed in to a different Claude account, for example work and personal, at the same time. Each window has its own login, settings and Claude Code history.

> **Unofficial.** Not made by or affiliated with Anthropic. It relies on app behaviour that isn't a documented feature, so a future app update could break it.

## What you get

- **Claude A** on your Desktop: your normal Claude app, unchanged.
- **Claude B**: a second, separate Claude window that you sign in to with your other account.
- Both can be open at the same time.

| | Normal profile (A) | New profile (B) |
|---|---|---|
| Desktop app data: login, preferences, extensions | the app's package folder* | `%USERPROFILE%\claude-desktop-b` |
| Claude Code data: settings, plugins, memory, session history | `%USERPROFILE%\.claude` | `%USERPROFILE%\.claude-b` |

\* `%LOCALAPPDATA%\Packages\Claude_<id>\LocalCache\Roaming\Claude`. Inside the app this folder also appears as `%APPDATA%\Claude`, but from a normal terminal or Explorer it only exists at the package path.

## Requirements

- Windows 10 or 11
- Claude Desktop installed from [claude.ai/download](https://claude.ai/download) (the current MSIX build)

Tested on Windows 10 22H2 with Claude Desktop 3.6556.2.0 and Claude Code 2.1.308.

## Setup

1. Download this repo (**Code > Download ZIP**) and unzip it, or `git clone` it.
2. Double-click **`Setup.cmd`**.
3. Double-click **Claude B** on your Desktop and sign in with your other account.

That's it. Your normal profile is only read during setup, never changed.

To use another name than B, run it from a terminal:

```bat
Setup.cmd -Name Work
```

`setup.ps1` options:

| Option | What it does |
|---|---|
| `-Name <name>` | Profile name, used in folder names and the shortcut label. Default `B`. |
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
- **Icons** are made at setup time from your installed app's own artwork: colour for A, grey for B. They're stored in `%USERPROFILE%\.claude-shortcuts`. No Anthropic artwork is included in this repo.
- **Nothing is written under AppData.** Programs running inside the Claude app, including Claude Code sessions, have their AppData writes redirected into the app's package folder, where Explorer can't see them. Keeping everything in your user folder means you can run these scripts from a normal terminal or ask Claude to run them for you.

## Things to know

- Both windows are called "Claude" on the taskbar. The account name at the bottom of the sidebar shows which is which.
- Closing the B window may leave it running in the tray.
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
