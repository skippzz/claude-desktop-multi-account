<#
.SYNOPSIS
    Removes a profile made by setup.ps1.

.DESCRIPTION
    Deletes the profile's folders (its login, settings, memory and Code session history), its
    Desktop shortcut and its icon. Your normal Claude profile, the "Claude A" shortcut and the
    profile's Cowork files folder (Claude-<name>) are left alone.

.PARAMETER Name
    The profile to remove. Default: B

.PARAMETER Yes
    Don't ask for confirmation.

.EXAMPLE
    .\uninstall.ps1 -Name B

.EXAMPLE
    .\uninstall.ps1 -Name B -WhatIf
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [ValidatePattern('^[A-Za-z0-9_-]{1,20}$')]
    [string]$Name = 'B',
    [switch]$Yes
)

$ErrorActionPreference = 'Stop'
function Fail([string]$message) { Write-Host $message -ForegroundColor Red; exit 1 }
if ($Name -eq 'A') { Fail '"A" is your normal profile. This script only removes extra profiles.' }

$id = $Name.ToLower()
$appP = Join-Path $env:USERPROFILE "claude-desktop-$id"
$targets = @(
    (Join-Path $env:USERPROFILE ".claude-$id"),
    $appP,
    (Join-Path ([Environment]::GetFolderPath('Desktop')) "Claude $Name.lnk"),
    (Join-Path $env:USERPROFILE ".claude-shortcuts\claude-$id.ico")
) | Where-Object { Test-Path $_ }

if (-not $targets) { Write-Host "Nothing to remove for profile '$Name'."; return }

# -WhatIf off for this lookup only, so the preview lists just the files below
$whatIf = $WhatIfPreference; $WhatIfPreference = $false
$running = @(Get-CimInstance Win32_Process -Filter "Name='Claude.exe'" | Where-Object { $_.CommandLine -and $_.CommandLine.Contains($appP) })
$WhatIfPreference = $whatIf
if ($running.Count) { Fail "Claude $Name is running. Close it (and quit it from the tray if it stays there), then run this again." }

Write-Host "This permanently deletes profile '$Name', including its login, settings, memory and Code session history:"
$targets | ForEach-Object { Write-Host "  $_" }
if (-not $Yes -and -not $WhatIfPreference) {
    $answer = Read-Host "Type $Name to confirm"
    if ($answer -ne $Name) { Write-Host 'Cancelled.'; return }
}
foreach ($t in $targets) {
    if ($PSCmdlet.ShouldProcess($t, 'Delete')) { Remove-Item $t -Recurse -Force }
}
if (-not $WhatIfPreference) { Write-Host "Removed profile '$Name'." }
