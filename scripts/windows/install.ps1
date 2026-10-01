# Interactive install entry for Windows. Runs the official installer only after
# the user confirms on a console. The plugin itself starts no daemon.
# Compatible with Windows PowerShell 5.1 and PowerShell 7+. Pure ASCII, LF.

. (Join-Path $PSScriptRoot 'lib.ps1')
. (Join-Path $PSScriptRoot 'lib-install.ps1')

Invoke-QtEntry { Invoke-QtInstallMain }
