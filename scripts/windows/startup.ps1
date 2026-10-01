# One-shot Herdr startup hook for Windows. Discover QuickTUI, show the
# first-run toast once, and exit. Do not start a daemon.
# Compatible with Windows PowerShell 5.1 and PowerShell 7+. Pure ASCII, LF.

. (Join-Path $PSScriptRoot 'lib.ps1')
. (Join-Path $PSScriptRoot 'lib-onboarding.ps1')

Invoke-QtEntry { Invoke-QtStartupMain }
