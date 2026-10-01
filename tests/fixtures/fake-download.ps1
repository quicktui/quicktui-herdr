# Runs a shipped Windows entry with only the network download replaced.
# usage: pwsh -File fake-download.ps1 <setup|install>
param([string]$Entry)

$scripts = Join-Path $env:QT_TEST_ROOT 'scripts/windows'
. (Join-Path $scripts 'lib.ps1')
. (Join-Path $scripts 'lib-install.ps1')

function Read-QtInstallerBytes([string]$Url) {
    Add-Content -LiteralPath $env:FAKE_DOWNLOAD_LOG -Value ('url=' + $Url)
    if ($env:FAKE_DOWNLOAD_FAIL) {
        throw 'simulated download failure'
    }
    return , [System.IO.File]::ReadAllBytes($env:FAKE_DOWNLOAD_PAYLOAD)
}

switch ($Entry) {
    'setup' { Invoke-QtEntry { Invoke-QtSetupMain } }
    'install' { Invoke-QtEntry { Invoke-QtInstallMain } }
}
exit 99
