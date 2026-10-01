# Action entry for Windows: open a plugin pane. Herdr actions have no console
# input, so pairing and install run in the declared pane instead.
# Compatible with Windows PowerShell 5.1 and PowerShell 7+. Pure ASCII, LF.

param([string]$Entry = '')

. (Join-Path $PSScriptRoot 'lib.ps1')

Invoke-QtEntry { Invoke-QtOpenPaneMain $Entry }
