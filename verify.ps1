<#
.SYNOPSIS
    Checks that a profile made by setup.ps1 is really separate from your normal Claude profile.

.DESCRIPTION
    Read-only. Checks that the profile exists, is signed in to a different account, and that its
    Claude Code sessions are stored in .claude-<name> and not in your normal .claude folder.
    Start at least one Code session in the profile before running it.

.PARAMETER Name
    The profile to check. Default: B

.EXAMPLE
    .\verify.ps1 -Name B
#>
[CmdletBinding()]
param(
    [ValidatePattern('^[A-Za-z0-9_-]{1,20}$')]
    [string]$Name = 'B'
)

$ErrorActionPreference = 'Stop'
$id      = $Name.ToLower()
$codeA   = Join-Path $env:USERPROFILE '.claude'
$appA    = Join-Path $env:APPDATA 'Claude'
$codeP   = Join-Path $env:USERPROFILE ".claude-$id"
$appP    = Join-Path $env:USERPROFILE "claude-desktop-$id"
$problems = 0

function Report([string]$level, [string]$text) {
    $color = @{ PASS = 'Green'; WARN = 'Yellow'; FAIL = 'Red'; INFO = 'Gray' }[$level]
    Write-Host ("[{0}] {1}" -f $level, $text) -ForegroundColor $color
    if ($level -eq 'FAIL') { $script:problems++ }
}
function Get-Account($dir) {
    $f = Join-Path $dir 'config.json'
    if (Test-Path $f) { ([IO.File]::ReadAllText($f) | ConvertFrom-Json).lastKnownAccountUuid }
}

Write-Host "Checking Claude profile '$Name'"

if ((Test-Path $codeP) -and (Test-Path $appP)) { Report PASS "profile folders exist ($codeP, $appP)" }
else { Report FAIL "profile folders missing. Run setup.ps1 -Name $Name first."; exit 1 }

$accA = Get-Account $appA; $accP = Get-Account $appP
if (-not $accP)          { Report WARN "Claude $Name is not signed in yet." }
elseif ($accP -eq $accA) { Report FAIL "Claude $Name is signed in to the SAME account as your normal profile." }
else                     { Report PASS "Claude $Name is signed in to a different account than your normal profile." }

$sessions = @()
if (Test-Path (Join-Path $codeP 'projects')) {
    $sessions = @(Get-ChildItem (Join-Path $codeP 'projects') -Recurse -Filter *.jsonl -File | Where-Object { $_.FullName -notmatch '\\memory\\' })
}
if (-not $sessions.Count) {
    Report WARN "no Code sessions found in $codeP yet. Start one in Claude $Name, send a message, then run this again."
} else {
    $names = $sessions | ForEach-Object Name
    $leaked = @()
    if (Test-Path (Join-Path $codeA 'projects')) {
        $leaked = @(Get-ChildItem (Join-Path $codeA 'projects') -Recurse -Filter *.jsonl -File | Where-Object { $names -contains $_.Name })
    }
    if ($leaked.Count) { Report FAIL "$($leaked.Count) of Claude $Name's sessions were also written to $codeA." }
    else { Report PASS "$($sessions.Count) Code session(s) stored in $codeP, none in $codeA." }
}

if (Test-Path (Join-Path $codeP 'policy-limits.json')) { Report INFO "Claude $Name keeps its own copy of its organization's policy settings." }

$procs = @(Get-CimInstance Win32_Process -Filter "Name='Claude.exe'")
$runP = @($procs | Where-Object { $_.CommandLine -and $_.CommandLine.Contains($appP) }).Count
$runA = @($procs | Where-Object { $_.CommandLine -and -not $_.CommandLine.Contains('--user-data-dir') }).Count
Report INFO ("running now: normal profile {0}, Claude {1} {2}" -f ($(if ($runA) { 'yes' } else { 'no' })), $Name, ($(if ($runP) { 'yes' } else { 'no' })))

if ($problems) { exit 1 }
