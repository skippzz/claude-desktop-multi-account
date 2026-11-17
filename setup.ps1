<#
.SYNOPSIS
    Adds another Claude Desktop profile on Windows, so several Claude accounts can run side by side.

.DESCRIPTION
    Creates a separate profile for Claude Desktop and for the Claude Code sessions it starts:

        %USERPROFILE%\claude-desktop-<name>   Claude Desktop app data (login, preferences, extensions)
        %USERPROFILE%\.claude-<name>          Claude Code config (settings, plugins, memory, session history)

    plus two Desktop shortcuts: "Claude A" for your normal app and "Claude <Name>" for the new profile.

    Run it again for each extra account. Without -Name it takes the next free letter: B, then C,
    then D, and so on. Every profile gets its own colour and its letter on the icon, and its
    windows get their own taskbar button with that icon, so you can tell the accounts apart.

    Unless you pass -Empty, your current setup is copied into the new profile: Claude Code settings,
    plugins, user-level CLAUDE.md / skills / agents / commands, per-project memory, Desktop extensions
    and the Desktop preferences that are not tied to an account. Logins, session history and anything
    account-specific are not copied.

    Your existing profile is only read, never changed.

.PARAMETER Name
    Name of the new profile, used in folder names and the shortcut label. Default: the next free
    letter (B, C, D, ...).

.PARAMETER Color
    Icon colour. Default: the next one in the list, by profile letter.

.PARAMETER Frame
    Thickness in pixels of the coloured frame drawn around the profile's windows, with the profile
    name on a small tab at the top. Default: 3. Use 0 for no frame.

.PARAMETER Empty
    Start the new profile empty instead of copying your current setup.

.PARAMETER NoMemory
    Copy your setup but leave out per-project memory.

.PARAMETER Launch
    Open the new profile when setup is done.

.PARAMETER Refresh
    Don't create anything new. Re-make the launcher, icon and shortcut of an existing profile
    (-Name), or of all of them. Use it after updating these scripts, or with -Color to change a
    profile's colour. Logins, settings and history are not touched.

.EXAMPLE
    .\setup.ps1

.EXAMPLE
    .\setup.ps1 -Name Work -Color Green -Launch

.EXAMPLE
    .\setup.ps1 -Refresh
#>
[CmdletBinding()]
param(
    [ValidatePattern('^[A-Za-z0-9_-]{1,20}$')]
    [string]$Name,
    [ValidateSet('Blue', 'Green', 'Purple', 'Teal', 'Pink', 'Gold', 'Red', 'Grey')]
    [string]$Color,
    [ValidateRange(0, 12)]
    [int]$Frame = 3,
    [switch]$Empty,
    [switch]$NoMemory,
    [switch]$Launch,
    [switch]$Refresh
)

$ErrorActionPreference = 'Stop'
function Fail([string]$message) { Write-Host $message -ForegroundColor Red; exit 1 }
if ($Name -eq 'A') { Fail '"A" is the label for your normal profile. Pick another name, e.g. -Name B or -Name Work.' }

$srcCode = Join-Path $env:USERPROFILE '.claude'
$alias   = Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\claude-desktop.exe'
# Not under AppData: when this runs inside the Claude app (e.g. from a Claude Code session), Windows
# redirects AppData writes into the app's package folder, where Explorer can't find the icons.
$iconDir = Join-Path $env:USERPROFILE '.claude-shortcuts'
$desktop = [Environment]::GetFolderPath('Desktop')
$utf8    = New-Object System.Text.UTF8Encoding $false
$guid    = '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}'

# Icon colours: hue in degrees, then saturation and lightness relative to the app's own artwork.
# New profiles walk this list in order (Grey is only used when asked for).
$palette = [ordered]@{
    Blue   = 214, 1.0, 0.92
    Green  = 145, 0.9, 0.72
    Purple = 268, 0.9, 0.95
    Teal   = 182, 1.0, 0.68
    Pink   = 330, 1.0, 0.95
    Gold   = 44,  1.1, 0.78
    Red    = 356, 1.1, 0.80
    Grey   = 0,   0.0, 0.85
}

function Step($text) { Write-Host "  $text" }
function Read-Json($path) { [IO.File]::ReadAllText($path) | ConvertFrom-Json }
function Write-Json($path, $value) { [IO.File]::WriteAllText($path, ($value | ConvertTo-Json -Depth 30), $utf8) }

# True when a preference is keyed to, or mentions, an account / session / org id.
function Test-AccountSpecific($prop) {
    if ($prop.Name -match $guid) { return $true }
    if ($null -eq $prop.Value) { return $false }
    return (ConvertTo-Json -InputObject $prop.Value -Depth 30 -Compress) -match $guid
}

# ids (lower-case names) of the profiles that exist now
function Get-ProfileIds {
    Get-ChildItem $env:USERPROFILE -Directory -Filter 'claude-desktop-*' -ErrorAction SilentlyContinue |
        ForEach-Object { $_.Name.Substring('claude-desktop-'.Length) } |
        Where-Object { Test-Path (Join-Path $env:USERPROFILE ".claude-$_") }
}

function Get-DefaultColor([string]$profileName) {
    $auto = @($palette.Keys | Where-Object { $_ -ne 'Grey' })
    $n = if ($profileName -match '^[B-Zb-z]$') { [int][char]$profileName.ToUpper() - [int][char]'B' } else { @(Get-ProfileIds).Count }
    $auto[$n % $auto.Count]
}

Add-Type -AssemblyName System.Drawing
Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition @'
using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;

namespace ClaudeProfiles {
    public static class Art {
        static double Channel(double p, double q, double t) {
            if (t < 0) t += 1; if (t > 1) t -= 1;
            if (t < 1.0 / 6) return p + (q - p) * 6 * t;
            if (t < 1.0 / 2) return q;
            if (t < 2.0 / 3) return p + (q - p) * (2.0 / 3 - t) * 6;
            return p;
        }

        // One colour moved to another hue, keeping its shading.
        public static Color Tint(Color c, double hue, double satScale, double lightScale) {
            double s = Math.Min(1, c.GetSaturation() * satScale);
            double l = c.GetBrightness();
            // darken in proportion to how coloured the pixel is, so the white mark stays white
            double chroma = (Math.Max(c.R, Math.Max(c.G, c.B)) - Math.Min(c.R, Math.Min(c.G, c.B))) / 255.0;
            l *= 1 - (1 - lightScale) * Math.Max(0, Math.Min(1, (chroma - 0.1) / 0.3));
            double q = l < 0.5 ? l * (1 + s) : l + s - l * s, p = 2 * l - q, h = hue / 360.0;
            return Color.FromArgb(
                (int)Math.Round(255 * Channel(p, q, h + 1.0 / 3)),
                (int)Math.Round(255 * Channel(p, q, h)),
                (int)Math.Round(255 * Channel(p, q, h - 1.0 / 3)));
        }

        // Moves every pixel to one hue. Near-white stays near-white.
        public static void Recolor(Bitmap bmp, double hue, double satScale, double lightScale) {
            var area = new Rectangle(0, 0, bmp.Width, bmp.Height);
            BitmapData data = bmp.LockBits(area, ImageLockMode.ReadWrite, PixelFormat.Format32bppArgb);
            var px = new byte[data.Stride * data.Height];
            Marshal.Copy(data.Scan0, px, 0, px.Length);
            for (int i = 0; i < px.Length; i += 4) {
                if (px[i + 3] == 0) continue;
                Color c = Tint(Color.FromArgb(px[i + 2], px[i + 1], px[i]), hue, satScale, lightScale);
                px[i + 2] = c.R; px[i + 1] = c.G; px[i] = c.B;
            }
            Marshal.Copy(px, 0, data.Scan0, px.Length);
            bmp.UnlockBits(data);
        }
    }
}
'@

# Builds an .ico from the installed app's artwork. With a colour it is re-tinted; with a letter it
# gets a badge in the corner (left out at 16px, where it would be a smudge).
function New-ClaudeIcon([string]$assets, [string]$path, [string]$color, [string]$letter) {
    $big = Join-Path $assets 'Square44x44Logo.targetsize-256_altform-unplated.png'
    if (-not (Test-Path $big)) { return $false }
    $sizes = 16, 20, 24, 32, 40, 48, 64, 96, 128, 256
    $src256 = [System.Drawing.Bitmap]::FromFile($big)
    $frames = foreach ($s in $sizes) {
        # use the app's hand-tuned art for this size when there is one
        $f = Join-Path $assets "Square44x44Logo.targetsize-${s}_altform-unplated.png"
        $src = if (Test-Path $f) { [System.Drawing.Bitmap]::FromFile($f) } else { $src256 }
        $bmp = New-Object System.Drawing.Bitmap $s, $s, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
        $g = [System.Drawing.Graphics]::FromImage($bmp)
        $g.InterpolationMode = 'HighQualityBicubic'; $g.PixelOffsetMode = 'HighQuality'; $g.CompositingQuality = 'HighQuality'
        $g.DrawImage($src, (New-Object System.Drawing.Rectangle 0, 0, $s, $s), 0, 0, $src.Width, $src.Height, 'Pixel')
        if ($src -ne $src256) { $src.Dispose() }
        if ($color) {
            $h, $sat, $light = $palette[$color]
            $g.Flush(); [ClaudeProfiles.Art]::Recolor($bmp, $h, $sat, $light)
        }
        if ($letter -and $s -ge 20) {
            $g.SmoothingMode = 'AntiAlias'; $g.TextRenderingHint = 'AntiAlias'
            $d = [float][Math]::Round($s * 0.56); $o = [float]($s - $d)
            $ring = [float][Math]::Max(1, $s / 32)
            $dark = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 24, 24, 27))
            $pen = New-Object System.Drawing.Pen ([System.Drawing.Color]::White), $ring
            $g.FillEllipse($dark, $o, $o, $d - $ring / 2, $d - $ring / 2)
            $g.DrawEllipse($pen, $o, $o, $d - $ring / 2, $d - $ring / 2)
            $font = New-Object System.Drawing.Font 'Segoe UI', ([float]($d * 0.62)), ([System.Drawing.FontStyle]::Bold), ([System.Drawing.GraphicsUnit]::Pixel)
            $fmt = New-Object System.Drawing.StringFormat; $fmt.Alignment = 'Center'; $fmt.LineAlignment = 'Center'
            $box = New-Object System.Drawing.RectangleF $o, ($o + $d * 0.02), ($d - $ring / 2), ($d - $ring / 2)
            $g.DrawString($letter, $font, [System.Drawing.Brushes]::White, $box, $fmt)
            $font.Dispose(); $pen.Dispose(); $dark.Dispose(); $fmt.Dispose()
        }
        $g.Dispose()
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

# Launcher, icon and shortcuts for one profile. Safe to run again on an existing profile.
function Install-Launcher([string]$profileName, [string]$profileColor, [int]$frameWidth) {
    $id     = $profileName.ToLower()
    # the window frame gets the same colour as the icon: the app's own orange, moved to the profile's hue
    $h, $sat, $light = $palette[$profileColor]
    $tint   = [ClaudeProfiles.Art]::Tint([System.Drawing.Color]::FromArgb(217, 119, 87), $h, $sat, $light)
    $hex    = '#{0:X2}{1:X2}{2:X2}' -f $tint.R, $tint.G, $tint.B
    $dstApp = Join-Path $env:USERPROFILE "claude-desktop-$id"
    $label  = "Claude $profileName"
    New-Item -ItemType Directory -Path $iconDir -Force | Out-Null

    # the icon: the app's own artwork in the profile's colour, with the profile's initial on it.
    # The colour is part of the file name because Explorer caches icons by path.
    $assets = Join-Path $pkg.InstallLocation 'assets'
    $icon = Join-Path $iconDir "claude-$id.$($profileColor.ToLower()).ico"
    if (-not (New-ClaudeIcon $assets $icon $profileColor $profileName.Substring(0, 1).ToUpper())) { $icon = $null }
    Get-ChildItem $iconDir -Filter "claude-$id.*ico" | Where-Object { $_.FullName -ne $icon } | Remove-Item -Force

    # tag-window.ps1 gives the profile's windows their own taskbar button. The launcher uses a copy
    # kept next to the icons, so this repo folder can be moved or deleted afterwards.
    $tagger = Join-Path $iconDir 'tag-window.ps1'
    Copy-Item (Join-Path $PSScriptRoot 'tag-window.ps1') $tagger -Force
    $pinLnk = Join-Path $iconDir "$label.lnk"   # what a pinned taskbar button starts

    $bat = Join-Path $dstApp "claude-$id.bat"
    $batText = @"
@echo off
rem Opens the "$profileName" Claude Desktop profile (made by claude-desktop-multi-account).
rem Uses the app's claude-desktop.exe alias, which keeps working across app updates.
set "CLAUDE_CONFIG_DIR=%USERPROFILE%\.claude-$id"
set "CLAUDE_APP=%LOCALAPPDATA%\Microsoft\WindowsApps\claude-desktop.exe"
if not exist "%CLAUDE_APP%" (
  echo Claude Desktop not found. Is it installed?
  pause
  exit /b 1
)
start "" "%CLAUDE_APP%" --user-data-dir="%USERPROFILE%\claude-desktop-$id"
rem Gives this profile's windows their own taskbar button, icon and coloured frame. Stays hidden until the profile is closed.
set "TAGGER=%USERPROFILE%\.claude-shortcuts\tag-window.ps1"
if exist "%TAGGER%" powershell -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "%TAGGER%" -DataDir "%USERPROFILE%\claude-desktop-$id" -Label "$label" -Icon "$icon" -Launcher "$pinLnk" -Color "$hex" -Frame $frameWidth -Tab "$profileName"
"@
    [IO.File]::WriteAllText($bat, ($batText -replace "`r?`n", "`r`n"), [Text.Encoding]::ASCII)
    Write-Json (Join-Path $dstApp 'profile.json') ([pscustomobject]@{ name = $profileName; color = $profileColor; frame = $frameWidth })
    Step "launcher: $bat"

    # Claude A keeps the app's normal icon. An existing icon file is left alone.
    $iconA = Join-Path $iconDir 'claude-a.ico'
    if (-not (Test-Path $iconA) -and -not (New-ClaudeIcon $assets $iconA)) { $iconA = $null }
    $lnkA = Join-Path $desktop 'Claude A.lnk'
    $lnkP = Join-Path $desktop "$label.lnk"
    if (-not (Test-Path $lnkA)) { New-Shortcut $lnkA $alias $iconA 'Claude Desktop - your normal profile' }
    foreach ($l in $lnkP, $pinLnk) { New-Shortcut $l $bat $icon "Claude Desktop - profile $profileName" 7 }   # 7 = start minimized, hides the console flash
    foreach ($l in $lnkA, $lnkP) { [ClaudeProfiles.Shell]::SHChangeNotify(0x2000, 5, $l, [IntPtr]::Zero) }   # tell Explorer to redraw them
    Step "Desktop shortcut: $label ($profileColor icon, $(if ($frameWidth) { "$frameWidth px window frame" } else { 'no window frame' }))"
    return $lnkP
}

# --- checks ------------------------------------------------------------------
$pkg = Get-AppxPackage -Name Claude | Sort-Object { [version]$_.Version } -Descending | Select-Object -First 1
if (-not $pkg -or -not (Test-Path $alias)) {
    Fail 'Claude Desktop (the Windows app from claude.ai/download) was not found. Only the current MSIX build is supported.'
}
Add-Type -Namespace ClaudeProfiles -Name Shell -MemberDefinition '[DllImport("shell32.dll", CharSet=CharSet.Unicode)] public static extern void SHChangeNotify(int e, uint f, string a, System.IntPtr b);'

# --- refresh existing profiles -------------------------------------------------
if ($Refresh) {
    $ids = @(if ($Name) { $Name.ToLower() } else { Get-ProfileIds })
    if (-not $ids.Count) { Fail 'No profiles to refresh. Run setup.ps1 without -Refresh to make one.' }
    foreach ($id in $ids) {
        $dir = Join-Path $env:USERPROFILE "claude-desktop-$id"
        if (-not (Test-Path $dir)) { Fail "Profile '$id' not found ($dir)." }
        # name and colour as saved at setup; profiles from before that was saved fall back to their shortcut's name
        $meta = Join-Path $dir 'profile.json'
        $saved = if (Test-Path $meta) { Read-Json $meta }
        $lnk = Get-ChildItem $desktop -Filter "Claude $id.lnk" -ErrorAction SilentlyContinue | Select-Object -First 1
        $n = if ($saved.name) { $saved.name } elseif ($lnk) { $lnk.BaseName.Substring('Claude '.Length) } elseif ($Name) { $Name } else { $id.ToUpper() }
        $c = if ($Color) { $Color } elseif ($saved.color) { $saved.color } else { Get-DefaultColor $n }
        $f = if ($PSBoundParameters.ContainsKey('Frame') -or $null -eq $saved.frame) { $Frame } else { [int]$saved.frame }
        Write-Host "Refreshing Claude profile '$n'"
        [void](Install-Launcher $n $c $f)
    }
    Write-Host ''
    Write-Host 'Done. A profile that is open now picks up the change the next time you start it from its shortcut.'
    return
}

# --- new profile ---------------------------------------------------------------
if (-not $Name) {
    $taken = @(Get-ProfileIds)
    $Name = [string](66..90 | ForEach-Object { [char]$_ } | Where-Object { $taken -notcontains "$_".ToLower() -and -not (Test-Path (Join-Path $env:USERPROFILE ".claude-$("$_".ToLower())")) } | Select-Object -First 1)
    if (-not $Name) { Fail 'Letters B to Z are all taken. Pick a name with -Name.' }
}
if (-not $Color) { $Color = Get-DefaultColor $Name }
$id      = $Name.ToLower()
$dstCode = Join-Path $env:USERPROFILE ".claude-$id"
$dstApp  = Join-Path $env:USERPROFILE "claude-desktop-$id"

# Where the normal profile's app data is depends on the app version: newer builds use
# %LOCALAPPDATA%\Claude-Data\<package>, older ones the package folder (which %APPDATA%\Claude only
# leads to from inside the app). Take the first that holds a config.
$srcApp = @(
    (Join-Path $env:LOCALAPPDATA "Claude-Data\$($pkg.PackageFamilyName)"),
    (Join-Path $env:LOCALAPPDATA "Packages\$($pkg.PackageFamilyName)\LocalCache\Roaming\Claude"),
    (Join-Path $env:APPDATA 'Claude')
) | Where-Object { Test-Path (Join-Path $_ 'config.json') } | Select-Object -First 1
if (-not $srcApp) { $srcApp = Join-Path $env:APPDATA 'Claude' }
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

# --- launcher, icon, shortcuts ---------------------------------------------------
$lnkP = Install-Launcher $Name $Color $Frame

Write-Host ''
Write-Host "Done. Next:"
Write-Host "  1. Double-click 'Claude $Name' on your Desktop and sign in with your other account."
Write-Host "  2. Optional: close it, then run copy-folder-modes.ps1 -Name $Name to copy your per-folder permission modes."
Write-Host "  3. Optional: start a Code session in it, then run verify.ps1 -Name $Name."
Write-Host "  For another account, run setup again: it will make the next letter."

if ($Launch) { Start-Process explorer.exe -ArgumentList "`"$lnkP`"" }
