# Fake official Windows installer payload. Runs as:
#   <powershell> -NoProfile -ExecutionPolicy Bypass -File <downloaded temp file>
$log = $env:FAKE_INSTALLER_LOG
Add-Content -LiteralPath $log -Value ('path=' + $PSCommandPath + ' argc=' + $args.Count)
Add-Content -LiteralPath $log -Value ('cmdline=' + (([Environment]::GetCommandLineArgs() | Select-Object -Skip 1) -join '|'))
if (-not [Console]::IsInputRedirected) {
    Add-Content -LiteralPath $log -Value 'stdin=console'
}
if ($env:FAKE_INSTALLER_SERVER_SRC) {
    $dir = Join-Path $env:LOCALAPPDATA 'QuickTUI'
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    $dest = Join-Path $dir 'quicktui-server.exe'
    Copy-Item -LiteralPath $env:FAKE_INSTALLER_SERVER_SRC -Destination $dest
    & chmod 0755 $dest
}
if ($env:FAKE_INSTALLER_EXIT) {
    exit ([int]$env:FAKE_INSTALLER_EXIT)
}
exit 0
