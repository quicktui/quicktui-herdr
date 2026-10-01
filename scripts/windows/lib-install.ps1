# Confirmed official QuickTUI install flow for Windows. Dot-source after
# lib.ps1. Do not execute.
#
# The installer is downloaded over HTTPS into memory, written to a private
# .ps1 temp file, and run with argv:
#   powershell.exe -NoProfile -ExecutionPolicy Bypass -File <temp file>
# Never evaluate downloaded text, and never build a command line string.

$script:QtDownloadFailed = 6
$script:QtInstallFailed = 7

$script:QtInstallUrl = 'https://quicktui.ai/q.ps1'
$script:QtInstallMaxBytes = 4MB
$script:QtInstallMaxRedirects = 5
$script:QtReadyWaitSeconds = 10

function Write-QtInstallPrompt {
    Write-QtText @"
QuickTUI Server is not installed on this machine.

QuickTUI Install downloads the official installer and runs it as your user:

  URL:  $($script:QtInstallUrl)
  Runs: powershell.exe -NoProfile -ExecutionPolicy Bypass -File <downloaded file>
        (same installer as: $($script:QtInstallGlobal))

The installer sets up quicktui-server and its sign-in task. Nothing is
downloaded or run unless you type y or yes.

"@
    Write-QtText 'Install QuickTUI now? [y/N] '
}

function Read-QtConfirm {
    # Only an explicit y/yes confirms. EOF and empty input decline.
    $answer = [Console]::In.ReadLine()
    if ($null -eq $answer) {
        return $false
    }
    return $answer -match '^(?i:y|yes)$'
}

function Test-QtHttpsUri([System.Uri]$Uri) {
    return $Uri.IsAbsoluteUri -and $Uri.Scheme -ceq 'https'
}

function Read-QtInstallerBytes([string]$Url) {
    # Fixed HTTPS URL. Follows at most QtInstallMaxRedirects redirects, each of
    # which must stay HTTPS. Throws on any failure; nothing is retried.
    if ($PSVersionTable.PSVersion.Major -lt 6) {
        # Windows PowerShell 5.1 on older Windows 10 may not enable TLS 1.2.
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12
    }
    $current = New-Object System.Uri($Url)
    for ($hop = 0; $hop -le $script:QtInstallMaxRedirects; $hop++) {
        if (-not (Test-QtHttpsUri $current)) {
            throw 'refusing a non-HTTPS installer URL'
        }
        $request = [System.Net.WebRequest]::Create($current)
        $request.AllowAutoRedirect = $false
        $request.Timeout = 30000
        $request.ReadWriteTimeout = 300000
        $request.UserAgent = 'quicktui-herdr'
        try {
            $response = $request.GetResponse()
        } catch [System.Net.WebException] {
            if ($null -eq $_.Exception.Response) {
                throw
            }
            $response = $_.Exception.Response
        }
        try {
            $code = [int]$response.StatusCode
            if ($code -ge 300 -and $code -lt 400) {
                $location = $response.Headers['Location']
                if ([string]::IsNullOrEmpty($location)) {
                    throw "HTTP $code without a Location header"
                }
                $current = New-Object System.Uri($current, $location)
                continue
            }
            if ($code -ne 200) {
                throw "HTTP $code"
            }
            $body = $response.GetResponseStream()
            $buffer = New-Object System.IO.MemoryStream
            $chunk = New-Object byte[] 65536
            while (($read = $body.Read($chunk, 0, $chunk.Length)) -gt 0) {
                if ($buffer.Length + $read -gt $script:QtInstallMaxBytes) {
                    throw 'installer is larger than expected'
                }
                $buffer.Write($chunk, 0, $read)
            }
            if ($buffer.Length -eq 0) {
                throw 'installer download is empty'
            }
            return , $buffer.ToArray()
        } finally {
            $response.Close()
        }
    }
    throw 'too many redirects'
}

function Get-QtInstallerHost {
    # Windows PowerShell 5.1 ships with every supported Windows and q.ps1
    # supports it. Prefer the System32 path over a PATH lookup.
    if ($script:QtIsWindows) {
        $root = Get-QtEnv 'SystemRoot'
        if ((Test-QtSafePath $root) -and (Test-QtAbsPath $root)) {
            $candidate = Join-Path $root 'System32\WindowsPowerShell\v1.0\powershell.exe'
            if (Test-QtFile $candidate) {
                return $candidate
            }
        }
        return 'powershell.exe'
    }
    # Non-Windows hosts only run the fixture tests: reuse the current pwsh.
    return [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
}

function New-QtInstallerFile([byte[]]$Content) {
    # Create a new private .ps1 file (-File requires the extension), write the
    # installer, and return @{ Path; Lock }. Lock is a read handle that denies
    # writers and deletion until the caller disposes it, so the file cannot
    # change between the hash check and the installer reading it.
    $dir = [System.IO.Path]::GetTempPath()
    if (-not (Test-QtSafePath $dir) -or -not (Test-QtAbsPath $dir) -or -not (Test-Path -LiteralPath $dir -PathType Container)) {
        throw 'temporary directory is not usable'
    }
    $path = Join-Path $dir ('quicktui-q-' + [System.Guid]::NewGuid().ToString('N') + '.ps1')
    $writer = New-Object System.IO.FileStream($path, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
    $lock = $null
    try {
        try {
            if (-not $script:QtIsWindows -and $null -ne [System.IO.File].GetMethod('SetUnixFileMode', [type[]]@([string], [System.IO.UnixFileMode]))) {
                [System.IO.File]::SetUnixFileMode($path, [System.IO.UnixFileMode]'UserRead, UserWrite')
            }
            $writer.Write($Content, 0, $Content.Length)
        } finally {
            $writer.Dispose()
        }
        $lock = New-Object System.IO.FileStream($path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read)
        $sha = [System.Security.Cryptography.SHA256]::Create()
        try {
            $want = [System.BitConverter]::ToString($sha.ComputeHash($Content))
            $got = [System.BitConverter]::ToString($sha.ComputeHash($lock))
        } finally {
            $sha.Dispose()
        }
        if ($want -ne $got) {
            throw 'installer temp file changed after it was written'
        }
        return @{ Path = $path; Lock = $lock }
    } catch {
        if ($null -ne $lock) {
            $lock.Dispose()
        }
        Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
        throw
    }
}

function Wait-QtReady {
    # Bounded wait: one discovery per second until ready or the deadline.
    $deadline = [DateTime]::UtcNow.AddSeconds($script:QtReadyWaitSeconds)
    while ($true) {
        Invoke-QtDiscover
        if ($script:QtStatus -eq 'ready') {
            return $true
        }
        if ([DateTime]::UtcNow -ge $deadline) {
            return $false
        }
        Start-Sleep -Seconds 1
    }
}

function Write-QtInstalledNotFoundGuide {
    Write-QtText @'
The installer finished, but quicktui-server was not found in PATH or
%LOCALAPPDATA%\QuickTUI. Open a new terminal and retry QuickTUI Setup, or set
QUICKTUI_SERVER_BIN to the installed binary.

'@
}

function Invoke-QtInstallFlow {
    # Confirm, download, run the official installer, then wait for readiness.
    # Sets QtExitCode, or hands the console to pairing welcome when ready.
    if ([Console]::IsInputRedirected) {
        Write-QtInstallGuide
        $script:QtExitCode = $script:QtOk
        return
    }
    Write-QtInstallPrompt
    if (-not (Read-QtConfirm)) {
        [Console]::Out.WriteLine()
        Write-QtLog 'install cancelled; nothing was downloaded'
        $script:QtExitCode = $script:QtOk
        return
    }

    Write-QtLog "downloading $($script:QtInstallUrl)"
    try {
        $content = Read-QtInstallerBytes $script:QtInstallUrl
    } catch {
        Write-QtErr ('download failed (' + $_.Exception.Message + '); the installer was not run')
        $script:QtExitCode = $script:QtDownloadFailed
        return
    }

    $file = $null
    $installRc = 0
    try {
        try {
            $file = New-QtInstallerFile $content
        } catch {
            Write-QtErr 'cannot create a private temporary file for the installer'
            $script:QtExitCode = $script:QtDownloadFailed
            return
        }
        Write-QtLog 'running the official QuickTUI installer'
        # Statement-level call: assigning the output would take the console
        # away from the installer.
        try {
            & (Get-QtInstallerHost) -NoProfile -ExecutionPolicy Bypass -File $file.Path
            $installRc = $LASTEXITCODE
        } catch {
            Write-QtErr 'could not start Windows PowerShell for the installer'
            $installRc = -1
        }
    } finally {
        if ($null -ne $file) {
            $file.Lock.Dispose()
            Remove-Item -LiteralPath $file.Path -Force -ErrorAction SilentlyContinue
        }
    }
    if ($installRc -ne 0) {
        Write-QtErr "installer exited with status $installRc"
        $script:QtExitCode = $script:QtInstallFailed
        return
    }

    Write-QtLog "installer finished; waiting up to $($script:QtReadyWaitSeconds)s for QuickTUI Server"
    if (Wait-QtReady) {
        Complete-QtDiscovery
        Invoke-QtPairing $script:QtServerBin 'welcome' $script:QtConfigPath
        return
    }
    Complete-QtDiscovery
    switch ($script:QtStatus) {
        'missing' {
            Write-QtInstalledNotFoundGuide
            $script:QtExitCode = $script:QtNotReady
            return
        }
        { $_ -eq 'invalid_bin' -or $_ -eq 'invalid_config' } {
            Write-QtErr "cannot open pairing because discovery status is $($script:QtStatus)"
            $script:QtExitCode = $script:QtInvalid
            return
        }
    }
    Write-QtStartGuide
    $script:QtExitCode = $script:QtNotReady
}

function Invoke-QtSetupMain {
    # setup pane: confirmed install when missing, start guide, or pairing welcome.
    $script:QtExitCode = Test-QtHerdrRuntime
    if ($script:QtExitCode -ne $script:QtOk) {
        return
    }
    Invoke-QtDiscover
    Complete-QtDiscovery
    switch ($script:QtStatus) {
        'missing' {
            Invoke-QtInstallFlow
        }
        { $_ -eq 'invalid_bin' -or $_ -eq 'invalid_config' } {
            Write-QtErr "cannot open pairing because discovery status is $($script:QtStatus)"
            $script:QtExitCode = $script:QtInvalid
        }
        { $_ -eq 'not_running' -or $_ -eq 'unknown' } {
            Write-QtStartGuide
            $script:QtExitCode = $script:QtNotReady
        }
        'ready' {
            if ([Console]::IsInputRedirected) {
                Write-QtHeadlessReadyGuide $script:QtServerBin $script:QtConfigPath
                $script:QtExitCode = $script:QtOk
            } else {
                Invoke-QtPairing $script:QtServerBin 'welcome' $script:QtConfigPath
            }
        }
        default {
            Write-QtErr 'unexpected discovery status'
            $script:QtExitCode = $script:QtCliFailed
        }
    }
}

function Invoke-QtInstallMain {
    # install pane: confirmed official install when QuickTUI is missing.
    $script:QtExitCode = Test-QtHerdrRuntime
    if ($script:QtExitCode -ne $script:QtOk) {
        return
    }
    Invoke-QtDiscover
    Complete-QtDiscovery
    switch ($script:QtStatus) {
        'missing' {
            Invoke-QtInstallFlow
        }
        { $_ -eq 'invalid_bin' -or $_ -eq 'invalid_config' } {
            Write-QtErr "cannot install because discovery status is $($script:QtStatus)"
            $script:QtExitCode = $script:QtInvalid
        }
        default {
            Write-QtLog 'QuickTUI Server is already installed. Run QuickTUI Setup to pair a device.'
            $script:QtExitCode = $script:QtOk
        }
    }
}
