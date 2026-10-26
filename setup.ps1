<#
.SYNOPSIS
    Adds a second Claude Desktop profile on Windows, so two Claude accounts can run side by side.

.DESCRIPTION
    Creates a separate profile for Claude Desktop and for the Claude Code sessions it starts:

        %USERPROFILE%\claude-desktop-<name>   Claude Desktop app data (login, preferences, extensions)
        %USERPROFILE%\.claude-<name>          Claude Code config (settings, plugins, memory, session history)

    plus two Desktop shortcuts: "Claude A" for your normal app and "Claude <Name>" for the new profile.

    Unless you pass -Empty, your current setup is copied into the new profile: Claude Code settings,
    plugins, user-level CLAUDE.md / skills / agents / commands, per-project memory, Desktop extensions
    and the Desktop preferences that are not tied to an account. Logins, session history and anything
    account-specific are not copied.

    Your existing profile is only read, never changed.

.PARAMETER Name
    Name of the new profile, used in folder names and the shortcut label. Default: B

.PARAMETER Empty
    Start the new profile empty instead of copying your current setup.

.PARAMETER NoMemory
    Copy your setup but leave out per-project memory.

.PARAMETER Launch
    Open the new profile when setup is done.

.EXAMPLE
    .\setup.ps1

.EXAMPLE
    .\setup.ps1 -Name Work -Launch
#>
[CmdletBinding()]
param(
    [ValidatePattern('^[A-Za-z0-9_-]{1,20}$')]
    [string]$Name = 'B',
    [switch]$Empty,
    [switch]$NoMemory,
    [switch]$Launch
)

$ErrorActionPreference = 'Stop'
function Fail([string]$message) { Write-Host $message -ForegroundColor Red; exit 1 }
if ($Name -eq 'A') { Fail '"A" is the label for your normal profile. Pick another name, e.g. -Name B or -Name Work.' }

$id      = $Name.ToLower()
$srcCode = Join-Path $env:USERPROFILE '.claude'
$srcApp  = Join-Path $env:APPDATA 'Claude'
$dstCode = Join-Path $env:USERPROFILE ".claude-$id"
$dstApp  = Join-Path $env:USERPROFILE "claude-desktop-$id"
$alias   = Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\claude-desktop.exe'
$iconDir = Join-Path $env:LOCALAPPDATA 'ClaudeShortcuts'
$desktop = [Environment]::GetFolderPath('Desktop')
$utf8    = New-Object System.Text.UTF8Encoding $false
$guid    = '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}'

function Step($text) { Write-Host "  $text" }
function Read-Json($path) { [IO.File]::ReadAllText($path) | ConvertFrom-Json }
function Write-Json($path, $value) { [IO.File]::WriteAllText($path, ($value | ConvertTo-Json -Depth 30), $utf8) }

# True when a preference is keyed to, or mentions, an account / session / org id.
function Test-AccountSpecific($prop) {
    if ($prop.Name -match $guid) { return $true }
    if ($null -eq $prop.Value) { return $false }
    return (ConvertTo-Json -InputObject $prop.Value -Depth 30 -Compress) -match $guid
}

function New-ClaudeIcon([string]$assets, [string]$path, [switch]$Grey) {
    $big = Join-Path $assets 'Square44x44Logo.targetsize-256_altform-unplated.png'
    if (-not (Test-Path $big)) { return $false }
    Add-Type -AssemblyName System.Drawing
    $sizes = 16, 20, 24, 32, 40, 48, 64, 96, 128, 256
    $src256 = [System.Drawing.Bitmap]::FromFile($big)
    $frames = foreach ($s in $sizes) {
        # use the app's hand-tuned art for this size when there is one
        $f = Join-Path $assets "Square44x44Logo.targetsize-${s}_altform-unplated.png"
        $src = if (Test-Path $f) { [System.Drawing.Bitmap]::FromFile($f) } else { $src256 }
        $bmp = New-Object System.Drawing.Bitmap $s, $s, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
        $g = [System.Drawing.Graphics]::FromImage($bmp)
        $g.InterpolationMode = 'HighQualityBicubic'; $g.PixelOffsetMode = 'HighQuality'; $g.CompositingQuality = 'HighQuality'
        $attr = New-Object System.Drawing.Imaging.ImageAttributes
        if ($Grey) {
            $m = New-Object System.Drawing.Imaging.ColorMatrix
            $m.Matrix00 = 0.299; $m.Matrix01 = 0.299; $m.Matrix02 = 0.299
            $m.Matrix10 = 0.587; $m.Matrix11 = 0.587; $m.Matrix12 = 0.587
            $m.Matrix20 = 0.114; $m.Matrix21 = 0.114; $m.Matrix22 = 0.114
            $attr.SetColorMatrix($m)
        }
        $g.DrawImage($src, (New-Object System.Drawing.Rectangle 0, 0, $s, $s), 0, 0, $src.Width, $src.Height, 'Pixel', $attr)
        $g.Dispose(); if ($src -ne $src256) { $src.Dispose() }
        $ms = New-Object System.IO.MemoryStream
        $bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()
        , $ms.ToArray()
    }
    $src256.Dispose()
    # .ico layout: 6-byte header, one 16-byte entry per size, then the PNG data
    $fs = [IO.File]::Create($path); $w = New-Object IO.BinaryWriter $fs
    $w.Write([uint16]0); $w.Write([uint16]1); $w.Write([uint16]$sizes.Count)
    $offset = 6 + 16 * $sizes.Count
    for ($i = 0; $i -lt $sizes.Count; $i++) {
        $s = $sizes[$i] % 256   # 256 is stored as 0
        $w.Write([byte]$s); $w.Write([byte]$s); $w.Write([byte]0); $w.Write([byte]0)
        $w.Write([uint16]1); $w.Write([uint16]32); $w.Write([uint32]$frames[$i].Length); $w.Write([uint32]$offset)
        $offset += $frames[$i].Length
    }
    foreach ($f in $frames) { $w.Write($f) }
    $w.Close()
    return $true
}

function New-Shortcut($path, $target, $icon, $description, [int]$windowStyle = 1) {
    $s = (New-Object -ComObject WScript.Shell).CreateShortcut($path)
    $s.TargetPath = $target
    $s.WorkingDirectory = $env:USERPROFILE
    $s.WindowStyle = $windowStyle
    $s.Description = $description
    if ($icon) { $s.IconLocation = "$icon,0" }
    $s.Save()
}

# --- checks ------------------------------------------------------------------
$pkg = Get-AppxPackage -Name Claude | Sort-Object { [version]$_.Version } -Descending | Select-Object -First 1
if (-not $pkg -or -not (Test-Path $alias)) {
    Fail 'Claude Desktop (the Windows app from claude.ai/download) was not found. Only the current MSIX build is supported.'
}
foreach ($p in $dstCode, $dstApp) {
    if (Test-Path $p) { Fail "Profile '$Name' already exists ($p). Use another name, or remove it first with uninstall.ps1 -Name $Name." }
}

Write-Host "Setting up Claude profile '$Name'"
New-Item -ItemType Directory -Path $dstCode, $dstApp | Out-Null

# --- copy Claude Code setup ----------------------------------------------------
if (-not $Empty -and (Test-Path $srcCode)) {
    foreach ($item in 'settings.json', 'CLAUDE.md', 'keybindings.json', 'skills', 'agents', 'commands', 'output-styles', 'hooks') {
        $from = Join-Path $srcCode $item
        if (Test-Path $from) { Copy-Item $from (Join-Path $dstCode $item) -Recurse; Step "copied $item" }
    }

    $plugins = Join-Path $srcCode 'plugins'
    if (Test-Path $plugins) {
        Copy-Item $plugins (Join-Path $dstCode 'plugins') -Recurse
        # the plugin index files hold absolute paths into .claude\plugins
        Get-ChildItem (Join-Path $dstCode 'plugins') -File -Filter *.json | ForEach-Object {
            $text = [IO.File]::ReadAllText($_.FullName)
            $new = $text.Replace('\\.claude\\', "\\.claude-$id\\").Replace('/.claude/', "/.claude-$id/")
            if ($new -ne $text) { [IO.File]::WriteAllText($_.FullName, $new, $utf8) }
        }
        Step 'copied plugins'
    }

    $projects = Join-Path $srcCode 'projects'
    if (-not $NoMemory -and (Test-Path $projects)) {
        $count = 0
        Get-ChildItem $projects -Directory | ForEach-Object {
            $mem = Join-Path $_.FullName 'memory'
            if ((Test-Path $mem) -and @(Get-ChildItem $mem -File -Recurse).Count) {
                $to = Join-Path $dstCode "projects\$($_.Name)"
                New-Item -ItemType Directory -Path $to -Force | Out-Null
                Copy-Item $mem (Join-Path $to 'memory') -Recurse
                $count++
            }
        }
        Step "copied memory for $count projects"
    }
}

# --- copy Claude Desktop setup ---------------------------------------------------
if (-not $Empty -and (Test-Path $srcApp)) {
    foreach ($item in 'Claude Extensions', 'Claude Extensions Settings', 'extensions-installations.json') {
        $from = Join-Path $srcApp $item
        if (Test-Path $from) { Copy-Item $from (Join-Path $dstApp $item) -Recurse }
    }
    if (Test-Path (Join-Path $srcApp 'Claude Extensions')) { Step 'copied Desktop extensions' }

    $cfgPath = Join-Path $srcApp 'claude_desktop_config.json'
    if (Test-Path $cfgPath) {
        $cfg = Read-Json $cfgPath
        $prefs = $cfg.preferences
        if ($prefs) {
            # drop anything tied to an account, a session or this device
            foreach ($p in @($prefs.PSObject.Properties)) {
                if ($p.Name -eq 'epitaxyPrefs') { continue }
                if ((Test-AccountSpecific $p) -or $p.Name -like '*ByAccount' -or $p.Name -in 'remoteSessionFolderGrants', 'remoteToolsDeviceName') {
                    $prefs.PSObject.Properties.Remove($p.Name)
                }
            }
            if ($prefs.epitaxyPrefs) {
                foreach ($p in @($prefs.epitaxyPrefs.PSObject.Properties)) {
                    if (Test-AccountSpecific $p) { $prefs.epitaxyPrefs.PSObject.Properties.Remove($p.Name) }
                }
            }
        }
        if ($cfg.PSObject.Properties['coworkUserFilesPath']) {
            $cfg.coworkUserFilesPath = Join-Path $env:USERPROFILE "Claude-$Name"
            New-Item -ItemType Directory -Path $cfg.coworkUserFilesPath -Force | Out-Null
        }
        Write-Json (Join-Path $dstApp 'claude_desktop_config.json') $cfg
        Step 'copied Desktop preferences (without account-specific ones)'
    }

    $appCfg = Join-Path $srcApp 'config.json'
    if (Test-Path $appCfg) {
        # config.json also holds the login token cache, so only the look-and-feel keys are copied
        $c = Read-Json $appCfg
        $keep = [ordered]@{}
        foreach ($k in 'locale', 'userThemeMode') { if ($c.PSObject.Properties[$k]) { $keep[$k] = $c.$k } }
        Write-Json (Join-Path $dstApp 'config.json') ([pscustomobject]$keep)
    }
}

# --- launcher, icons, shortcuts --------------------------------------------------
$bat = Join-Path $dstApp "claude-$id.bat"
$batText = @"
@echo off
rem Opens the "$Name" Claude Desktop profile (made by claude-desktop-multi-account).
rem Uses the app's claude-desktop.exe alias, which keeps working across app updates.
set "CLAUDE_CONFIG_DIR=%USERPROFILE%\.claude-$id"
set "CLAUDE_APP=%LOCALAPPDATA%\Microsoft\WindowsApps\claude-desktop.exe"
if not exist "%CLAUDE_APP%" (
  echo Claude Desktop not found. Is it installed?
  pause
  exit /b 1
)
start "" "%CLAUDE_APP%" --user-data-dir="%USERPROFILE%\claude-desktop-$id"
"@
[IO.File]::WriteAllText($bat, ($batText -replace "`r?`n", "`r`n"), [Text.Encoding]::ASCII)
Step "launcher: $bat"

# icons are made from the installed app's own artwork: colour for A, grey for extra profiles.
# Existing icon files are left alone, since Explorer caches them by path.
New-Item -ItemType Directory -Path $iconDir -Force | Out-Null
$assets = Join-Path $pkg.InstallLocation 'assets'
$iconA = Join-Path $iconDir 'claude-a.ico'
$iconP = Join-Path $iconDir "claude-$id.ico"
if (-not (Test-Path $iconA) -and -not (New-ClaudeIcon $assets $iconA)) { $iconA = $null }
if (-not (Test-Path $iconP) -and -not (New-ClaudeIcon $assets $iconP -Grey)) { $iconP = $null }

$lnkA = Join-Path $desktop 'Claude A.lnk'
$lnkP = Join-Path $desktop "Claude $Name.lnk"
if (-not (Test-Path $lnkA)) { New-Shortcut $lnkA $alias $iconA 'Claude Desktop - your normal profile' }
New-Shortcut $lnkP $bat $iconP "Claude Desktop - profile $Name" 7   # 7 = start minimized, hides the console flash
Add-Type -Namespace ClaudeProfiles -Name Shell -MemberDefinition '[DllImport("shell32.dll", CharSet=CharSet.Unicode)] public static extern void SHChangeNotify(int e, uint f, string a, System.IntPtr b);'
foreach ($l in $lnkA, $lnkP) { [ClaudeProfiles.Shell]::SHChangeNotify(0x2000, 5, $l, [IntPtr]::Zero) }   # tell Explorer to redraw them
Step "Desktop shortcuts: Claude A, Claude $Name"

Write-Host ''
Write-Host "Done. Next:"
Write-Host "  1. Double-click 'Claude $Name' on your Desktop and sign in with your other account."
Write-Host "  2. Optional: close it, then run copy-folder-modes.ps1 -Name $Name to copy your per-folder permission modes."
Write-Host "  3. Optional: start a Code session in it, then run verify.ps1 -Name $Name."

if ($Launch) { Start-Process explorer.exe -ArgumentList "`"$lnkP`"" }
