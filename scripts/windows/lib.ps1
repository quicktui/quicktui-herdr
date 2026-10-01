# Shared PowerShell helpers for the quicktui-herdr Windows entry points.
# Dot-source only. Do not execute.
#
# Compatible with Windows PowerShell 5.1 and PowerShell 7+. Keep this file pure
# ASCII with LF line endings: PowerShell 5.1 reads BOM-less scripts as ANSI.
# All process launches use argv. Never evaluate strings as code.

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$script:QtOk = 0
$script:QtUsage = 2
$script:QtInvalid = 3
$script:QtNotReady = 4
$script:QtCliFailed = 5

$script:QtExitCode = 0
$script:QtDefaultListen = '0.0.0.0:8022'
$script:QtCapabilityPath = '/.well-known/quicktui-server-capability'
# Display text only. The install flow never evaluates downloaded text.
$script:QtInstallGlobal = 'irm https://quicktui.ai/q.ps1 | iex'
$script:QtIsWindows = ($PSVersionTable.PSEdition -eq 'Desktop') -or ((Test-Path -Path 'variable:IsWindows') -and $IsWindows)

$script:QtAllowedEnv = @(
    'HERDR_BIN_PATH', 'HERDR_PLUGIN_ID', 'HERDR_PLUGIN_ROOT', 'HERDR_SOCKET_PATH',
    'HERDR_PLUGIN_STATE_DIR', 'HERDR_PLUGIN_CONFIG_DIR', 'QUICKTUI_SERVER_BIN',
    'QUICKTUI_CONFIG', 'USERPROFILE', 'LOCALAPPDATA', 'SystemRoot'
)

function Write-QtLog([string]$Message) {
    [Console]::Out.WriteLine('quicktui-herdr: ' + $Message)
}

function Write-QtErr([string]$Message) {
    [Console]::Error.WriteLine('quicktui-herdr: ' + $Message)
}

function Write-QtText([string]$Text) {
    [Console]::Out.Write($Text)
}

function Get-QtEnv([string]$Name) {
    # Allowlisted env lookup. Do not take untrusted names.
    if ($script:QtAllowedEnv -cnotcontains $Name) {
        throw "environment name is not allowlisted: $Name"
    }
    $value = [Environment]::GetEnvironmentVariable($Name)
    if ($null -eq $value) {
        return ''
    }
    return $value
}

function Test-QtSafeText([string]$Value, [int]$Max) {
    if ([string]::IsNullOrEmpty($Value)) {
        return $false
    }
    if ($Value.Length -gt $Max) {
        return $false
    }
    return -not ($Value -match '[\x00-\x1f\x7f]')
}

function Test-QtSafePath([string]$Value) {
    # Double quotes are invalid in Windows paths and are mangled by Windows
    # PowerShell 5.1 native argument passing, so reject them outright.
    if (-not (Test-QtSafeText $Value 4096)) {
        return $false
    }
    return -not $Value.Contains('"')
}

function Test-QtAbsPath([string]$Value) {
    if ($script:QtIsWindows) {
        # Drive-absolute (C:\x) or UNC (\\server\share). Drive-relative and
        # rooted-without-drive paths are not absolute.
        return ($Value -match '^[A-Za-z]:[\\/]') -or ($Value -match '^\\\\[^\\]')
    }
    return $Value.StartsWith('/')
}

function Test-QtFile([string]$Path) {
    return Test-Path -LiteralPath $Path -PathType Leaf
}

function Test-QtPluginId([string]$Value) {
    return ($Value.Length -le 120) -and ($Value -cmatch '^[A-Za-z0-9._:-]+$')
}

function Test-QtRuntimePath([string]$Name) {
    # Optional absolute Herdr path. Empty is allowed.
    $value = Get-QtEnv $Name
    if ($value -eq '') {
        return $true
    }
    return (Test-QtSafePath $value) -and (Test-QtAbsPath $value)
}

function Test-QtHerdrRuntime {
    # Returns an exit code: QtOk when the injected Herdr env is usable.
    $bin = Get-QtEnv 'HERDR_BIN_PATH'
    if ($bin -eq '') {
        Write-QtErr 'HERDR_BIN_PATH is required'
        return $script:QtUsage
    }
    if (-not (Test-QtSafePath $bin) -or -not (Test-QtAbsPath $bin)) {
        Write-QtErr 'HERDR_BIN_PATH must be an absolute path without control characters'
        return $script:QtUsage
    }
    if (-not (Test-QtFile $bin)) {
        Write-QtErr 'HERDR_BIN_PATH is not an executable file'
        return $script:QtUsage
    }
    $id = Get-QtEnv 'HERDR_PLUGIN_ID'
    if ($id -eq '') {
        Write-QtErr 'HERDR_PLUGIN_ID is required'
        return $script:QtUsage
    }
    if (-not (Test-QtPluginId $id)) {
        Write-QtErr 'HERDR_PLUGIN_ID is invalid'
        return $script:QtUsage
    }
    foreach ($name in @('HERDR_PLUGIN_ROOT', 'HERDR_PLUGIN_STATE_DIR', 'HERDR_PLUGIN_CONFIG_DIR')) {
        if (-not (Test-QtRuntimePath $name)) {
            Write-QtErr "$name must be an absolute path without control characters"
            return $script:QtUsage
        }
    }
    # On Windows this is a named pipe name, not a file path. The plugin never
    # connects to it; Herdr is always called through HERDR_BIN_PATH.
    $socket = Get-QtEnv 'HERDR_SOCKET_PATH'
    if ($socket -ne '' -and -not (Test-QtSafeText $socket 4096)) {
        Write-QtErr 'HERDR_SOCKET_PATH contains control characters'
        return $script:QtUsage
    }
    # Context JSON and workspace labels are untrusted. Never interpolate them.
    return $script:QtOk
}

function ConvertTo-QtArgument([string]$Value) {
    # Encode one argv element for the Windows command line parser
    # (CommandLineToArgvW rules). Used only where .NET has no ArgumentList.
    if ($Value.Length -gt 0 -and $Value -notmatch '[\s"]') {
        return $Value
    }
    $builder = New-Object System.Text.StringBuilder
    [void]$builder.Append('"')
    $slashes = 0
    foreach ($ch in $Value.ToCharArray()) {
        if ($ch -eq [char]'\') {
            $slashes++
            continue
        }
        if ($ch -eq [char]'"') {
            [void]$builder.Append([char]'\', 2 * $slashes + 1)
        } elseif ($slashes -gt 0) {
            [void]$builder.Append([char]'\', $slashes)
        }
        $slashes = 0
        [void]$builder.Append($ch)
    }
    [void]$builder.Append([char]'\', 2 * $slashes)
    [void]$builder.Append('"')
    return $builder.ToString()
}

function Stop-QtProcessTree([System.Diagnostics.Process]$Process) {
    # Best effort: the caller already treats the command as failed.
    try {
        if ($null -ne $Process.GetType().GetMethod('Kill', [type[]]@([bool]))) {
            $Process.Kill($true)
        } elseif ($script:QtIsWindows) {
            $taskkill = Join-Path (Join-Path (Get-QtEnv 'SystemRoot') 'System32') 'taskkill.exe'
            & $taskkill /PID $Process.Id /T /F 2>&1 | Out-Null
        } else {
            $Process.Kill()
        }
        [void]$Process.WaitForExit(2000)
    } catch {
        Write-QtErr 'could not stop a timed-out child process'
    }
}

function Invoke-QtBounded([string]$FilePath, [string[]]$ArgumentList, [int]$TimeoutSeconds) {
    # Run argv quietly with stdin closed. Kill the process tree on timeout.
    # Returns $true only when the command exits 0 in time.
    $info = New-Object System.Diagnostics.ProcessStartInfo
    $info.FileName = $FilePath
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardInput = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    if ($null -ne $info.PSObject.Properties['ArgumentList']) {
        foreach ($arg in $ArgumentList) {
            [void]$info.ArgumentList.Add($arg)
        }
    } else {
        $info.Arguments = (($ArgumentList | ForEach-Object { ConvertTo-QtArgument $_ }) -join ' ')
    }
    try {
        $process = [System.Diagnostics.Process]::Start($info)
    } catch {
        return $false
    }
    try {
        $process.StandardInput.Close()
        # Drain both pipes so a chatty child cannot block on a full buffer.
        [void]$process.StandardOutput.ReadToEndAsync()
        [void]$process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
            Stop-QtProcessTree $process
            return $false
        }
        return ($process.ExitCode -eq 0)
    } finally {
        $process.Dispose()
    }
}

function Get-QtHomeDir {
    # quicktui-server uses Go os.UserHomeDir(), which is %USERPROFILE% on Windows.
    $homeDir = Get-QtEnv 'USERPROFILE'
    if ((Test-QtSafePath $homeDir) -and (Test-QtAbsPath $homeDir)) {
        return $homeDir
    }
    return ''
}

function Get-QtInstallDir {
    # Mirrors the QuickTUI installer windows_install_dir():
    # %LOCALAPPDATA%\QuickTUI, else %USERPROFILE%\AppData\Local\QuickTUI.
    $base = Get-QtEnv 'LOCALAPPDATA'
    if ($base.Trim() -ne '') {
        if ((Test-QtSafePath $base) -and (Test-QtAbsPath $base)) {
            return Join-Path $base 'QuickTUI'
        }
        return ''
    }
    $homeDir = Get-QtHomeDir
    if ($homeDir -eq '') {
        return ''
    }
    return Join-Path (Join-Path (Join-Path $homeDir 'AppData') 'Local') 'QuickTUI'
}

function Get-QtDefaultConfigPath {
    # Mirrors quicktui-server config.FilePath(): <home>\.config\quicktui-server-v2\config.toml.
    $homeDir = Get-QtHomeDir
    if ($homeDir -eq '') {
        return ''
    }
    return Join-Path (Join-Path (Join-Path $homeDir '.config') 'quicktui-server-v2') 'config.toml'
}

function Find-QtServerBin {
    # Returns @{ Status = 'found' | 'missing' | 'invalid'; Path = <absolute path> }.
    $override = Get-QtEnv 'QUICKTUI_SERVER_BIN'
    if ($override -ne '') {
        if (-not (Test-QtSafePath $override) -or -not (Test-QtAbsPath $override)) {
            Write-QtErr 'QUICKTUI_SERVER_BIN must be an absolute path without control characters'
            return @{ Status = 'invalid'; Path = '' }
        }
        if (-not (Test-QtFile $override)) {
            Write-QtErr 'QUICKTUI_SERVER_BIN is not an executable file'
            return @{ Status = 'invalid'; Path = '' }
        }
        return @{ Status = 'found'; Path = $override }
    }
    $fromPath = Get-Command -Name 'quicktui-server' -CommandType Application -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($null -ne $fromPath) {
        $resolved = [string]$fromPath.Source
        if ((Test-QtSafePath $resolved) -and (Test-QtAbsPath $resolved) -and (Test-QtFile $resolved)) {
            return @{ Status = 'found'; Path = $resolved }
        }
    }
    $installDir = Get-QtInstallDir
    if ($installDir -ne '') {
        $candidate = Join-Path $installDir 'quicktui-server.exe'
        if (Test-QtFile $candidate) {
            return @{ Status = 'found'; Path = $candidate }
        }
    }
    return @{ Status = 'missing'; Path = '' }
}

function Resolve-QtConfigPath {
    # Returns @{ Status = 'ok' | 'invalid' | 'none'; Path = <path> }.
    $override = Get-QtEnv 'QUICKTUI_CONFIG'
    if ($override -ne '') {
        if (-not (Test-QtSafePath $override) -or -not (Test-QtAbsPath $override)) {
            Write-QtErr 'QUICKTUI_CONFIG must be an absolute path without control characters'
            return @{ Status = 'invalid'; Path = '' }
        }
        return @{ Status = 'ok'; Path = $override }
    }
    $default = Get-QtDefaultConfigPath
    if ($default -eq '') {
        return @{ Status = 'none'; Path = '' }
    }
    return @{ Status = 'ok'; Path = $default }
}

function Read-QtTomlAddr([string]$Path) {
    # Read a simple addr = "host:port" assignment. No interpolation or includes.
    # Returns @{ Status = 0 found | 1 absent | 2 invalid; Value = <addr> }.
    try {
        $lines = [System.IO.File]::ReadAllLines($Path)
    } catch {
        return @{ Status = 1; Value = '' }
    }
    foreach ($raw in $lines) {
        $line = $raw -replace '[ \t]*#.*$', ''
        if ($line -cnotmatch '^[ \t]*addr[ \t]*=[ \t]*') {
            continue
        }
        $line = $line -creplace '^[ \t]*addr[ \t]*=[ \t]*', ''
        if ($line.StartsWith('"""')) {
            return @{ Status = 2; Value = '' }
        }
        if ($line.StartsWith('"')) {
            if ($line -notmatch '^"[^"]*"[ \t]*$') {
                return @{ Status = 2; Value = '' }
            }
            $line = $line -replace '^"', '' -replace '"[ \t]*$', ''
        } elseif ($line.StartsWith("'")) {
            if ($line -notmatch "^'[^']*'[ \t]*$") {
                return @{ Status = 2; Value = '' }
            }
            $line = $line -replace "^'", '' -replace "'[ \t]*$", ''
        } else {
            $line = $line -replace '[ \t]*$', ''
        }
        if ($line -eq '' -or $line -match '[\x00-\x1f\x7f]') {
            return @{ Status = 2; Value = '' }
        }
        return @{ Status = 0; Value = $line }
    }
    return @{ Status = 1; Value = '' }
}

function Test-QtSafeHost([string]$Value) {
    if ($Value.Length -eq 0 -or $Value.Length -gt 253) {
        return $false
    }
    if ($Value -ceq 'localhost') {
        return $true
    }
    if ($Value -match '^[0-9]+(\.[0-9]+){3}$') {
        return $true
    }
    if ($Value -match '^[0-9A-Fa-f:]+$') {
        return $true
    }
    if ($Value.Contains(':') -and $Value -match '^[0-9A-Fa-f:.]+$') {
        return $true
    }
    return $Value -match '^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])$'
}

function Split-QtListenAddr([string]$Addr) {
    # Returns @{ Host = <probe host>; Port = <int> } or $null when invalid.
    # Official config accepts optional http(s)://. The probe stays plaintext HTTP.
    $value = $Addr -replace '^(?i:https?://)', ''
    if (-not (Test-QtSafeText $value 253)) {
        return $null
    }
    if ($value -match '^\[(.*)\]:([^\]]*)$') {
        $probeHost = $Matches[1]
        $port = $Matches[2]
    } elseif ($value -match '^(.*):([^:]*)$') {
        $probeHost = $Matches[1]
        $port = $Matches[2]
    } else {
        return $null
    }
    if ($port -notmatch '^[0-9]{1,5}$') {
        return $null
    }
    $portNumber = [int]$port
    if ($portNumber -lt 1 -or $portNumber -gt 65535) {
        return $null
    }
    if ($probeHost -eq '' -or $probeHost -eq '0.0.0.0' -or $probeHost -eq 'localhost') {
        $probeHost = '127.0.0.1'
    }
    if ($probeHost -eq '::' -or $probeHost -eq '::0') {
        $probeHost = '::1'
    }
    if (-not (Test-QtSafeHost $probeHost)) {
        return $null
    }
    return @{ Host = $probeHost; Port = $portNumber }
}

function Test-QtCapability([string]$ProbeHost, [int]$Port) {
    # Plain HTTP GET of the capability path over a raw socket: no proxy, no
    # redirects, at most 1s DNS, 1s connect, and 2s read. $true means ready.
    $address = $null
    if (-not [System.Net.IPAddress]::TryParse($ProbeHost, [ref]$address)) {
        try {
            $lookup = [System.Net.Dns]::GetHostAddressesAsync($ProbeHost)
            if (-not $lookup.Wait(1000) -or $lookup.Result.Length -eq 0) {
                return $false
            }
            $address = $lookup.Result[0]
        } catch {
            return $false
        }
    }
    $client = New-Object System.Net.Sockets.TcpClient($address.AddressFamily)
    try {
        $connect = $client.ConnectAsync($address, $Port)
        if (-not $connect.Wait(1000)) {
            return $false
        }
        $stream = $client.GetStream()
        $stream.ReadTimeout = 2000
        $stream.WriteTimeout = 2000
        if ($address.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetworkV6) {
            $hostHeader = '[' + $ProbeHost + ']:' + $Port
        } else {
            $hostHeader = $ProbeHost + ':' + $Port
        }
        $request = 'GET ' + $script:QtCapabilityPath + " HTTP/1.1`r`nHost: " + $hostHeader + "`r`nConnection: close`r`n`r`n"
        $bytes = [System.Text.Encoding]::ASCII.GetBytes($request)
        $stream.Write($bytes, 0, $bytes.Length)
        $buffer = New-Object byte[] 64
        $count = $stream.Read($buffer, 0, $buffer.Length)
        $status = [System.Text.Encoding]::ASCII.GetString($buffer, 0, $count)
        return $status.StartsWith('HTTP/1.1 200') -or $status.StartsWith('HTTP/1.0 200')
    } catch {
        return $false
    } finally {
        $client.Close()
    }
}

function Get-QtNowUtc {
    return [DateTime]::UtcNow.ToString("yyyy-MM-dd'T'HH:mm:ss'Z'", [System.Globalization.CultureInfo]::InvariantCulture)
}

function Write-QtPrivateFile([string]$Dir, [string]$Name, [string]$Text) {
    # Write through a temp file in the same directory, then replace. The plugin
    # state dir is per-user (Herdr creates it under the user profile).
    if (-not (Test-Path -LiteralPath $Dir -PathType Container)) {
        [void](New-Item -ItemType Directory -Path $Dir -Force)
    }
    $tmp = Join-Path $Dir ($Name + '.tmp.' + $PID)
    $dest = Join-Path $Dir $Name
    try {
        [System.IO.File]::WriteAllText($tmp, $Text, (New-Object System.Text.UTF8Encoding($false)))
        Move-Item -LiteralPath $tmp -Destination $dest -Force
    } catch {
        Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
        throw
    }
}

function Write-QtState {
    $status = $script:QtStatus
    if (@('missing', 'not_running', 'ready', 'unknown', 'invalid_config', 'invalid_bin') -cnotcontains $status) {
        $status = 'unknown'
    }
    $dir = Get-QtEnv 'HERDR_PLUGIN_STATE_DIR'
    if ($dir -eq '') {
        return
    }
    # Local status only. No paths, codes, tokens, or identity.
    $text = "status=$status`nserver_present=$($script:QtServerPresent)`nconfig_present=$($script:QtConfigPresent)`nherdr_cli=$($script:QtHerdrCli)`nprobed_at=$(Get-QtNowUtc)`n"
    try {
        Write-QtPrivateFile $dir 'discovery.env' $text
    } catch {
        Write-QtErr 'could not write the discovery status file'
    }
}

function Write-QtInstallGuide {
    Write-QtText @"
QuickTUI Server is not installed on this machine.

Open the QuickTUI Install action (ai.quicktui.install-windows) in Herdr. It asks
for confirmation, then runs the official installer. Or run it yourself in
PowerShell:

  $($script:QtInstallGlobal)

Docs: https://quicktui.ai/install/?ref=herdr

"@
}

function Write-QtStartGuide {
    Write-QtText @'
QuickTUI Server is installed but not ready for pairing.

Start the existing service, then retry QuickTUI Setup. This plugin will not
launch an unsupervised daemon.

  schtasks /Run /TN QuickTUI

If that task does not exist, sign out and sign in again so the QuickTUI
sign-in entry starts the server.

If you use a custom config, start the server with that file and set
QUICKTUI_CONFIG to the same path before invoking this plugin.

'@
}

function ConvertTo-QtPsQuoted([string]$Value) {
    # PowerShell single-quote encoding for copy/paste commands.
    return "'" + $Value.Replace("'", "''") + "'"
}

function Write-QtHeadlessReadyGuide([string]$ServerBin, [string]$ConfigPath) {
    $bin = ConvertTo-QtPsQuoted $ServerBin
    [Console]::Out.WriteLine('QuickTUI Server is ready. stdin is not a TTY, so this plugin will not issue a pairing code.')
    [Console]::Out.WriteLine('Run one of these commands in an interactive PowerShell:')
    [Console]::Out.WriteLine()
    if ($ConfigPath -ne '') {
        $config = ConvertTo-QtPsQuoted $ConfigPath
        [Console]::Out.WriteLine("  & $bin pairing welcome --config $config")
        [Console]::Out.WriteLine("  & $bin pairing qrcode --config $config")
    } else {
        [Console]::Out.WriteLine("  & $bin pairing welcome")
        [Console]::Out.WriteLine("  & $bin pairing qrcode")
    }
}

function Invoke-QtDiscover {
    # Sets QtStatus, QtServerBin, QtConfigPath, QtServerPresent,
    # QtConfigPresent, QtHerdrCli. Safe to re-run.
    $script:QtStatus = 'missing'
    $script:QtServerBin = ''
    $script:QtConfigPath = ''
    $script:QtServerPresent = 0
    $script:QtConfigPresent = 0
    $script:QtHerdrCli = 'unavailable'

    # Session listing is best-effort and bounded. Herdr owns its named pipe.
    if (Invoke-QtBounded (Get-QtEnv 'HERDR_BIN_PATH') @('session', 'list', '--json') 2) {
        $script:QtHerdrCli = 'ok'
    }

    $server = Find-QtServerBin
    if ($server.Status -eq 'invalid') {
        $script:QtStatus = 'invalid_bin'
        return
    }
    if ($server.Status -eq 'missing') {
        $config = Resolve-QtConfigPath
        if ($config.Status -eq 'ok') {
            $script:QtConfigPath = $config.Path
            if (Test-QtFile $config.Path) {
                $script:QtConfigPresent = 1
            }
        }
        return
    }
    $script:QtServerBin = $server.Path
    $script:QtServerPresent = 1

    $config = Resolve-QtConfigPath
    if ($config.Status -eq 'invalid') {
        $script:QtStatus = 'invalid_config'
        return
    }
    $script:QtConfigPath = $config.Path

    $listen = $script:QtDefaultListen
    if ($script:QtConfigPath -ne '' -and (Test-QtFile $script:QtConfigPath)) {
        $script:QtConfigPresent = 1
        $addr = Read-QtTomlAddr $script:QtConfigPath
        if ($addr.Status -eq 2) {
            $script:QtStatus = 'invalid_config'
            return
        }
        if ($addr.Status -eq 0) {
            $listen = $addr.Value
        }
    }

    $target = Split-QtListenAddr $listen
    if ($null -eq $target) {
        $script:QtStatus = 'invalid_config'
        return
    }
    if (Test-QtCapability $target.Host $target.Port) {
        $script:QtStatus = 'ready'
    } else {
        $script:QtStatus = 'not_running'
    }
}

function Complete-QtDiscovery {
    Write-QtState
    Write-QtLog "status=$($script:QtStatus)"
}

function Invoke-QtPairing([string]$ServerBin, [string]$Subcommand, [string]$ConfigPath) {
    # Hand the console to the official CLI. Sets QtExitCode to its exit status.
    $override = Get-QtEnv 'QUICKTUI_CONFIG'
    try {
        if ($override -ne '' -or ($ConfigPath -ne '' -and (Test-QtFile $ConfigPath))) {
            & $ServerBin pairing $Subcommand --config $ConfigPath
        } else {
            & $ServerBin pairing $Subcommand
        }
        $script:QtExitCode = $LASTEXITCODE
    } catch {
        Write-QtErr 'could not start quicktui-server'
        $script:QtExitCode = $script:QtCliFailed
    }
}

function Invoke-QtEntry([scriptblock]$Main) {
    # Run an entry point and exit with QtExitCode. Unexpected errors exit 5.
    try {
        & $Main
    } catch {
        Write-QtErr ('unexpected error: ' + $_.Exception.Message)
        $script:QtExitCode = $script:QtCliFailed
    }
    exit $script:QtExitCode
}

function Invoke-QtPairQrcodeMain {
    # pair-qrcode pane: issue a code only through quicktui-server pairing qrcode.
    $script:QtExitCode = Test-QtHerdrRuntime
    if ($script:QtExitCode -ne $script:QtOk) {
        return
    }
    Invoke-QtDiscover
    Complete-QtDiscovery
    switch ($script:QtStatus) {
        'missing' {
            Write-QtInstallGuide
            $script:QtExitCode = $script:QtOk
        }
        { $_ -eq 'invalid_bin' -or $_ -eq 'invalid_config' } {
            Write-QtErr "cannot open pairing because discovery status is $($script:QtStatus)"
            $script:QtExitCode = $script:QtInvalid
        }
        { $_ -eq 'not_running' -or $_ -eq 'unknown' } {
            Write-QtErr 'QuickTUI Server is not ready; pairing code was not issued'
            Write-QtStartGuide
            $script:QtExitCode = $script:QtNotReady
        }
        'ready' {
            Invoke-QtPairing $script:QtServerBin 'qrcode' $script:QtConfigPath
        }
        default {
            Write-QtErr 'unexpected discovery status'
            $script:QtExitCode = $script:QtCliFailed
        }
    }
}

function Invoke-QtOpenPaneMain([string]$Entry) {
    # Action entry: open the matching Windows pane. Actions have no console input.
    $script:QtExitCode = Test-QtHerdrRuntime
    if ($script:QtExitCode -ne $script:QtOk) {
        return
    }
    if ($Entry -eq '') {
        Write-QtErr 'pane entrypoint is required'
        $script:QtExitCode = $script:QtUsage
        return
    }
    # Windows pane ids carry a -windows suffix: Herdr rejects duplicate ids
    # even when their platforms differ.
    if (@('setup', 'pair-qrcode', 'install') -cnotcontains $Entry) {
        Write-QtErr 'unknown pane entrypoint'
        $script:QtExitCode = $script:QtUsage
        return
    }
    $herdr = Get-QtEnv 'HERDR_BIN_PATH'
    $plugin = Get-QtEnv 'HERDR_PLUGIN_ID'
    & $herdr plugin pane open --plugin $plugin --entrypoint ($Entry + '-windows')
    $script:QtExitCode = $LASTEXITCODE
}
