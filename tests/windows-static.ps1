# Static and unit checks for the Windows PowerShell entry points.
# Prints one "ok <name>" or "not ok <name>" line per check for tests/run.sh.
# usage: pwsh -NoProfile -File tests/windows-static.ps1 <repo root>
param([string]$Root)

$scripts = Join-Path $Root 'scripts/windows'
. (Join-Path $scripts 'lib.ps1')
. (Join-Path $scripts 'lib-install.ps1')
$ErrorActionPreference = 'Continue'

function Report([string]$Name, [bool]$Ok) {
    if ($Ok) {
        [Console]::Out.WriteLine("ok $Name")
    } else {
        [Console]::Out.WriteLine("not ok $Name")
    }
}

$files = @(Get-ChildItem -LiteralPath $scripts -Filter '*.ps1' | Sort-Object Name)
Report 'windows scripts exist' ($files.Count -ge 8)

# --- encoding: pure ASCII, LF, no BOM (PowerShell 5.1 reads BOM-less as ANSI) ---
foreach ($file in $files) {
    $bytes = [System.IO.File]::ReadAllBytes($file.FullName)
    $bad = @($bytes | Where-Object { $_ -ge 0x80 -or $_ -eq 0x0d })
    Report "$($file.Name) is pure ASCII with LF" ($bad.Count -eq 0)
}

# --- AST: no string evaluation, no shell launches ---
# The AST sees commands only, so the displayed manual command text
# 'irm https://quicktui.ai/q.ps1 | iex' (a string literal) is not a command.
$forbiddenCommands = @('iex', 'Invoke-Expression', 'Invoke-Command', 'Start-Process', 'Add-Type', 'cmd', 'cmd.exe')
$forbiddenMembers = @('Create', 'InvokeScript', 'NewScriptBlock')
$allText = ''
foreach ($file in $files) {
    $tokens = $null
    $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$errors)
    Report "$($file.Name) parses" ($errors.Count -eq 0)
    $allText += [System.IO.File]::ReadAllText($file.FullName)
    $commands = $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.CommandAst] }, $true)
    $badCommands = @($commands | Where-Object { $forbiddenCommands -contains $_.GetCommandName() })
    Report "$($file.Name) has no Invoke-Expression, iex, or shell launches" ($badCommands.Count -eq 0)
    $members = $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.InvokeMemberExpressionAst] }, $true)
    $badMembers = @($members | Where-Object {
            $name = $_.Member.Extent.Text
            ($forbiddenMembers -contains $name) -and ($_.Expression.Extent.Text -match '(?i)scriptblock|ExecutionContext|InvokeCommand')
        })
    Report "$($file.Name) creates no script blocks from strings" ($badMembers.Count -eq 0)
}
Report 'manual install text still mentions iex (string only)' ($allText.Contains('irm https://quicktui.ai/q.ps1 | iex'))

# --- installer runs as argv with -File ---
$installAst = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $scripts 'lib-install.ps1'), [ref]$null, [ref]$null)
$installerCalls = @($installAst.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.CommandAst] -and
            $node.InvocationOperator -eq [System.Management.Automation.Language.TokenKind]::Ampersand -and
            $node.CommandElements[0].Extent.Text -eq '(Get-QtInstallerHost)'
        }, $true))
$argvText = ''
if ($installerCalls.Count -eq 1) {
    $argvText = (@($installerCalls[0].CommandElements | Select-Object -Skip 1 | ForEach-Object { $_.Extent.Text })) -join ' '
}
Report 'installer argv is -NoProfile -ExecutionPolicy Bypass -File <file>' ($argvText -eq '-NoProfile -ExecutionPolicy Bypass -File $file.Path')
Report 'installer URL is the fixed HTTPS q.ps1' ($script:QtInstallUrl -ceq 'https://quicktui.ai/q.ps1')

# --- argv encoding used on Windows PowerShell 5.1 ---
$python = (Get-Command -Name python3 -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1)
$samples = @('plain', 'a b', 'tail\', 'q"uote', '', 'back\\"x', 'C:\Program Files\x\', '; touch pwned')
if ($null -ne $python) {
    $info = New-Object System.Diagnostics.ProcessStartInfo
    $info.FileName = $python.Source
    $info.Arguments = (@('-c', 'import json,sys; print(json.dumps(sys.argv[1:]))') + $samples | ForEach-Object { ConvertTo-QtArgument $_ }) -join ' '
    $info.UseShellExecute = $false
    $info.RedirectStandardOutput = $true
    $process = [System.Diagnostics.Process]::Start($info)
    $decoded = $process.StandardOutput.ReadToEnd() | ConvertFrom-Json
    $process.WaitForExit()
    $same = ($decoded.Count -eq $samples.Count)
    for ($i = 0; $same -and $i -lt $samples.Count; $i++) {
        $same = ($decoded[$i] -ceq $samples[$i])
    }
    Report 'Windows argv encoding round-trips' $same
} else {
    Report 'Windows argv encoding round-trips (python3 missing)' $false
}

# --- download refuses anything but HTTPS before connecting ---
$listener = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Loopback, 0)
$listener.Start()
$port = $listener.LocalEndpoint.Port
$refused = $false
try {
    [void](Read-QtInstallerBytes "http://127.0.0.1:$port/q.ps1")
} catch {
    $refused = $_.Exception.Message -match 'non-HTTPS'
}
Start-Sleep -Milliseconds 200
$contacted = $listener.Pending()
$listener.Stop()
Report 'download refuses an HTTP URL' $refused
Report 'download does not connect for an HTTP URL' (-not $contacted)
Report 'redirect check rejects http' (-not (Test-QtHttpsUri (New-Object System.Uri('http://quicktui.ai/q.ps1'))))
Report 'redirect check rejects file' (-not (Test-QtHttpsUri (New-Object System.Uri('file:///tmp/q.ps1'))))
Report 'redirect check accepts https' (Test-QtHttpsUri (New-Object System.Uri('https://github.com/x')))

# --- temp file: .ps1, private, locked, removed by the caller ---
$file = New-QtInstallerFile ([System.Text.Encoding]::ASCII.GetBytes("exit 0`n"))
Report 'installer temp file ends with .ps1' ($file.Path.EndsWith('.ps1'))
if ($script:QtIsWindows) {
    # Share modes are enforced by Windows only; .NET on Unix maps them to
    # advisory locks that do not stop a ReadWrite-shared opener.
    $writable = $true
    try {
        $probe = [System.IO.File]::Open($file.Path, 'Open', 'ReadWrite', 'ReadWrite')
        $probe.Dispose()
    } catch {
        $writable = $false
    }
    Report 'installer temp file is locked against writers' (-not $writable)
} else {
    $mode = [System.IO.File]::GetUnixFileMode($file.Path)
    Report 'installer temp file is owner-only' ($mode -eq [System.IO.UnixFileMode]'UserRead, UserWrite')
}
$file.Lock.Dispose()
Remove-Item -LiteralPath $file.Path -Force

# --- listen address parsing parity with the Unix scripts ---
function Format-Target($Target) {
    if ($null -eq $Target) {
        return 'invalid'
    }
    return "$($Target.Host)|$($Target.Port)"
}
$cases = [ordered]@{
    '0.0.0.0:8022'           = '127.0.0.1|8022'
    ':8022'                  = '127.0.0.1|8022'
    'localhost:1'            = '127.0.0.1|1'
    '[::]:8022'              = '::1|8022'
    '[::ffff:127.0.0.1]:9'   = '::ffff:127.0.0.1|9'
    'HTTPS://10.0.0.2:443'   = '10.0.0.2|443'
    'deadbeef:65531'         = 'deadbeef|65531'
    '127.0.0.1:0'            = 'invalid'
    '127.0.0.1:65536'        = 'invalid'
    '127.0.0.1'              = 'invalid'
    '127.0.0.1:80; touch x'  = 'invalid'
}
foreach ($key in $cases.Keys) {
    $got = Format-Target (Split-QtListenAddr $key)
    Report "listen addr '$key' -> $($cases[$key])" ($got -eq $cases[$key])
}
