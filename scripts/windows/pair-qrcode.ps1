# Official pairing QR entry for Windows. Issues a code only by running
# quicktui-server pairing qrcode.
# Compatible with Windows PowerShell 5.1 and PowerShell 7+. Pure ASCII, LF.

. (Join-Path $PSScriptRoot 'lib.ps1')

Invoke-QtEntry { Invoke-QtPairQrcodeMain }
