<#
.SYNOPSIS
    Copies your per-folder permission modes (e.g. "Auto" for a project folder) from your normal
    Claude account to the account signed in to another profile.

.DESCRIPTION
    Claude Desktop remembers the permission mode you picked for each folder, per account. A new
    profile starts without them. Sign in to the profile once, then run this to give it the same
    modes as your normal account.

    The profile must be closed while this runs. A backup of its config is saved as
    claude_desktop_config.json.bak.

.PARAMETER Name
    The profile to copy to. Default: B

.PARAMETER Close
    Close the profile without asking if it is running.

.PARAMETER SourceDataDir
    App data folder of your normal profile. Default: the Claude app's own data folder.

.PARAMETER ProfileDataDir
    App data folder of the target profile. Default: %USERPROFILE%\claude-desktop-<name>

.EXAMPLE
    .\copy-folder-modes.ps1 -Name B
#>
[CmdletBinding()]
param(
    [ValidatePattern('^[A-Za-z0-9_-]{1,20}$')]
    [string]$Name = 'B',
    [switch]$Close,
    [string]$SourceDataDir,
    [string]$ProfileDataDir
)

$ErrorActionPreference = 'Stop'
function Fail([string]$message) { Write-Host $message -ForegroundColor Red; exit 1 }
if (-not $SourceDataDir) {
    # the MSIX app keeps its data in its package folder; %APPDATA%\Claude only leads there from inside the app
    $pkg = Get-AppxPackage -Name Claude | Select-Object -First 1
    if ($pkg) { $SourceDataDir = Join-Path $env:LOCALAPPDATA "Packages\$($pkg.PackageFamilyName)\LocalCache\Roaming\Claude" }
    if (-not $SourceDataDir -or -not (Test-Path $SourceDataDir)) { $SourceDataDir = Join-Path $env:APPDATA 'Claude' }
}
if (-not $ProfileDataDir) { $ProfileDataDir = Join-Path $env:USERPROFILE "claude-desktop-$($Name.ToLower())" }
$utf8 = New-Object System.Text.UTF8Encoding $false
function Read-Json($path) { [IO.File]::ReadAllText($path) | ConvertFrom-Json }

if (-not (Test-Path $ProfileDataDir)) { Fail "Profile '$Name' not found ($ProfileDataDir). Run setup.ps1 first." }

# the profile overwrites its config on exit, so it has to be closed
$running = @(Get-CimInstance Win32_Process -Filter "Name='Claude.exe'" | Where-Object { $_.CommandLine -and $_.CommandLine.Contains($ProfileDataDir) })
if ($running.Count) {
    if (-not $Close) {
        $answer = Read-Host "Claude $Name is running and has to be closed first. Close it now? (y/n)"
        if ($answer -notmatch '^(y|yes)$') { Write-Host 'Cancelled.'; return }
    }
    $main = $running | Where-Object { $_.CommandLine -notmatch '--type=' } | Select-Object -First 1
    if ($main) { taskkill /PID $main.ProcessId /T /F | Out-Null }
    Start-Sleep -Seconds 2
}

$srcConfig = Join-Path $SourceDataDir 'config.json'
$dstConfig = Join-Path $ProfileDataDir 'config.json'
$srcAccount = if (Test-Path $srcConfig) { (Read-Json $srcConfig).lastKnownAccountUuid }
$dstAccount = if (Test-Path $dstConfig) { (Read-Json $dstConfig).lastKnownAccountUuid }
if (-not $srcAccount) { Fail 'Your normal Claude profile has no signed-in account.' }
if (-not $dstAccount) { Fail "Claude $Name has no signed-in account yet. Open it, sign in, close it, then run this again." }
if ($srcAccount -eq $dstAccount) { Fail "Claude $Name is signed in to the same account as your normal profile, so there is nothing to copy." }

$srcPrefs = Join-Path $SourceDataDir 'claude_desktop_config.json'
$dstPrefs = Join-Path $ProfileDataDir 'claude_desktop_config.json'
$src = Read-Json $srcPrefs
$dst = if (Test-Path $dstPrefs) { Read-Json $dstPrefs } else { [pscustomobject]@{} }
if (-not $dst.PSObject.Properties['preferences']) { $dst | Add-Member preferences ([pscustomobject]@{}) }
if (-not $dst.preferences.PSObject.Properties['epitaxyPrefs']) { $dst.preferences | Add-Member epitaxyPrefs ([pscustomobject]@{}) }

$copied = 0
foreach ($key in 'epitaxy-folder-permission-mode-v2', 'epitaxy-perm-mode-acks-v2') {
    $value = $src.preferences.epitaxyPrefs."$key.$srcAccount"
    if ($null -ne $value) {
        $dst.preferences.epitaxyPrefs | Add-Member -NotePropertyName "$key.$dstAccount" -NotePropertyValue $value -Force
        $copied++
    }
}
if (-not $copied) { Write-Host 'Your normal account has no per-folder permission modes saved. Nothing to copy.'; return }

if (Test-Path $dstPrefs) { Copy-Item $dstPrefs "$dstPrefs.bak" -Force }
[IO.File]::WriteAllText($dstPrefs, ($dst | ConvertTo-Json -Depth 30), $utf8)
$folders = @($src.preferences.epitaxyPrefs."epitaxy-folder-permission-mode-v2.$srcAccount".PSObject.Properties).Count
Write-Host "Copied permission modes for $folders folders to Claude $Name. Open it again with its Desktop shortcut."
