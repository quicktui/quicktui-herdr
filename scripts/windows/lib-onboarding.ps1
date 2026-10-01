# First-run Herdr toast for Windows. Dot-source after lib.ps1. Do not execute.
# The marker file name and format are shared with the Unix entry points:
#   $HERDR_PLUGIN_STATE_DIR/onboarding.env
#   toast_shown_at=<UTC ISO-8601>
# It holds only that line. No paths, codes, tokens, or identity.

$script:QtOnboardingMarker = 'onboarding.env'
$script:QtToastTimeoutSeconds = 3

function Test-QtMarkerPresent([string]$Path) {
    # A dangling link still counts as present, like `[ -e ] || [ -L ]` on Unix.
    if (Test-Path -LiteralPath $Path) {
        return $true
    }
    return $null -ne (Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue)
}

function Show-QtFirstRunToast {
    # Show one toast per plugin state dir. Mark only after Herdr accepted it.
    # Never changes the caller's exit status.
    $dir = Get-QtEnv 'HERDR_PLUGIN_STATE_DIR'
    if ($dir -eq '') {
        return
    }
    if (Test-QtMarkerPresent (Join-Path $dir $script:QtOnboardingMarker)) {
        return
    }
    switch ($script:QtStatus) {
        'missing' {
            $body = 'Use your terminal from iPhone or Android. Run the QuickTUI Install action to set it up.'
        }
        'ready' {
            $body = 'QuickTUI is ready. Run the QuickTUI Pairing QR action to pair your phone.'
        }
        default {
            $body = 'Run the QuickTUI Setup action to finish setting up QuickTUI.'
        }
    }
    $herdr = Get-QtEnv 'HERDR_BIN_PATH'
    $toastArgs = @('notification', 'show', 'QuickTUI', '--body', $body, '--sound', 'none')
    if (-not (Invoke-QtBounded $herdr $toastArgs $script:QtToastTimeoutSeconds)) {
        return
    }
    try {
        Write-QtPrivateFile $dir $script:QtOnboardingMarker "toast_shown_at=$(Get-QtNowUtc)`n"
    } catch {
        Write-QtErr 'could not write the onboarding marker'
    }
}

function Invoke-QtStartupMain {
    # Startup hook: discover, write status, toast once, exit 0.
    $script:QtExitCode = Test-QtHerdrRuntime
    if ($script:QtExitCode -ne $script:QtOk) {
        return
    }
    Invoke-QtDiscover
    Complete-QtDiscovery
    Show-QtFirstRunToast
    $script:QtExitCode = $script:QtOk
}
