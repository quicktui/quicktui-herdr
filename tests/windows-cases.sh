# Windows PowerShell entry cases, run under pwsh on this host. Sourced by
# tests/run.sh, which provides new_case, cleanup_case, the assert helpers, and
# the capability server. Linux pwsh proves script logic only: Windows
# PowerShell 5.1, Windows paths, and ConPTY need a real Windows host.

PWSH=$(command -v pwsh || true)
if [ -z "$PWSH" ]; then
	if [ "${QT_REQUIRE_PWSH-}" = 1 ]; then
		fail "pwsh is available for the Windows fixture tests"
	else
		printf '%s\n' 'skip Windows fixture tests: pwsh not found (set QT_REQUIRE_PWSH=1 to fail instead)'
	fi
	return 0
fi

WIN=$ROOT/scripts/windows

new_win_case() {
	new_case
	export USERPROFILE=$CASE/home
	export LOCALAPPDATA=$CASE/localappdata
	export TMPDIR=$CASE/tmp
	unset FAKE_DOWNLOAD_FAIL
	mkdir -p "$LOCALAPPDATA"
}

run_ps() {
	# $1 script name under scripts/windows, then script args. stdin is /dev/null.
	_script=$1
	shift
	set +e
	"$PWSH" -NoProfile -File "$WIN/$_script" "$@" </dev/null >"$CASE/out" 2>"$CASE/err"
	RC=$?
	set -e
}

run_ps_pty() {
	# $1 typed line ("" sends EOF), $2 script name under scripts/windows
	set +e
	python3 "$FIXTURES/run-in-pty.py" "$1" "$CASE/out" "$PWSH" -NoProfile -File "$WIN/$2"
	RC=$?
	set -e
}

new_win_install_case() {
	new_win_case
	rm -f "$CASE/bin/quicktui-server"
	export QT_TEST_ROOT=$ROOT
	export FAKE_DOWNLOAD_LOG=$CASE/download.log
	export FAKE_DOWNLOAD_PAYLOAD=$FIXTURES/fake-q.ps1
	export FAKE_INSTALLER_LOG=$CASE/installer.log
	: >"$FAKE_DOWNLOAD_LOG"
	: >"$FAKE_INSTALLER_LOG"
}

run_fake_download_pty() {
	# Shipped setup/install code with only the HTTPS download replaced.
	# $1 typed line, $2 setup|install
	set +e
	python3 "$FIXTURES/run-in-pty.py" "$1" "$CASE/out" "$PWSH" -NoProfile -File "$FIXTURES/fake-download.ps1" "$2"
	RC=$?
	set -e
}

assert_win_tmp_clean() {
	if [ -z "$(find "$CASE/tmp" -mindepth 1 -print)" ]; then
		pass "$1"
	else
		fail "$1 (leftover files in $CASE/tmp)"
	fi
}

assert_win_installer_ran() {
	_path=$(sed -n 's/^path=\(.*\) argc=.*$/\1/p' "$CASE/installer.log")
	case $_path in
	"$CASE/tmp/quicktui-q-"*.ps1) pass "$1 runs a private .ps1 temp file" ;;
	*) fail "$1 runs a private .ps1 temp file (path=$_path)" ;;
	esac
	assert_file_contains "$1 passes no installer args" "$CASE/installer.log" "argc=0"
	assert_file_contains "$1 uses -File argv" "$CASE/installer.log" "cmdline=-NoProfile|-ExecutionPolicy|Bypass|-File|$_path"
	if [ -n "$_path" ] && [ ! -e "$_path" ]; then
		pass "$1 removes the temp file"
	else
		fail "$1 removes the temp file"
	fi
	assert_win_tmp_clean "$1 leaves no temp files"
}

# --- static checks, argv encoding, download and temp file units ---
_static_out=$(mktemp "$TEST_TMP_ROOT/quicktui-herdr-static.XXXXXX")
if TMPDIR=$TEST_TMP_ROOT "$PWSH" -NoProfile -File "$ROOT/tests/windows-static.ps1" "$ROOT" >"$_static_out" 2>&1; then
	pass "windows static checks ran"
else
	fail "windows static checks ran"
fi
while IFS= read -r _line; do
	case $_line in
	"ok "*) pass "windows ${_line#ok }" ;;
	"not ok "*) fail "windows ${_line#not ok }" ;;
	*) fail "windows static unexpected output: $_line" ;;
	esac
done <"$_static_out"
rm -f "$_static_out"

# --- missing env ---
new_win_case
unset HERDR_BIN_PATH
run_ps startup.ps1
assert_eq "win startup missing HERDR_BIN_PATH exits 2" "$RC" 2
cleanup_case

new_win_case
unset HERDR_PLUGIN_ID
run_ps startup.ps1
assert_eq "win startup missing HERDR_PLUGIN_ID exits 2" "$RC" 2
cleanup_case

new_win_case
export HERDR_BIN_PATH=$(printf '/tmp/herdr\nbad')
run_ps startup.ps1
assert_eq "win startup rejects HERDR_BIN_PATH with newline" "$RC" 2
cleanup_case

# --- path with spaces ---
new_win_case
spaced=$CASE/path\ space
cp "$CASE/bin/herdr" "$spaced/herdr bin"
cp "$CASE/bin/quicktui-server" "$spaced/quicktui server"
chmod 0755 "$spaced/herdr bin" "$spaced/quicktui server"
export HERDR_BIN_PATH=$spaced/herdr\ bin
export QUICKTUI_SERVER_BIN=$spaced/quicktui\ server
export QUICKTUI_CONFIG=$spaced/config.toml
printf 'addr = "127.0.0.1:%s"\n' "$(free_port)" >"$QUICKTUI_CONFIG"
run_ps startup.ps1
assert_eq "win startup accepts paths with spaces" "$RC" 0
assert_file_contains "win startup space path status" "$CASE/out" "status=not_running"
assert_file_contains "win startup calls herdr session list" "$CASE/herdr.log" "session list --json"
assert_file_contains "win state records herdr cli" "$CASE/state/discovery.env" "herdr_cli=ok"
cleanup_case

# --- QuickTUI missing ---
new_win_case
rm -f "$CASE/bin/quicktui-server"
run_ps startup.ps1
assert_eq "win startup missing QuickTUI exits 0" "$RC" 0
assert_file_contains "win startup missing status" "$CASE/out" "status=missing"
assert_file_contains "win startup missing state" "$CASE/state/discovery.env" "status=missing"
run_ps setup.ps1
assert_eq "win setup missing without console exits 0" "$RC" 0
assert_file_contains "win setup prints official PowerShell install" "$CASE/out" "irm https://quicktui.ai/q.ps1 | iex"
assert_file_contains "win setup names the Windows install action" "$CASE/out" "ai.quicktui.install-windows"
assert_file_not_contains "win setup missing does not call pairing" "$CASE/qt.log" "pairing"
run_ps pair-qrcode.ps1
assert_eq "win qrcode missing exits 0" "$RC" 0
assert_file_contains "win qrcode missing prints install guide" "$CASE/out" "https://quicktui.ai/q.ps1"
cleanup_case

# --- default Windows layout: %LOCALAPPDATA%\QuickTUI and %USERPROFILE%\.config ---
new_win_case
rm -f "$CASE/bin/quicktui-server"
mkdir -p "$LOCALAPPDATA/QuickTUI" "$USERPROFILE/.config/quicktui-server-v2"
cp "$FIXTURES/fake-quicktui-server" "$LOCALAPPDATA/QuickTUI/quicktui-server.exe"
chmod 0755 "$LOCALAPPDATA/QuickTUI/quicktui-server.exe"
printf 'addr = "127.0.0.1:%s"\n' "$(free_port)" >"$USERPROFILE/.config/quicktui-server-v2/config.toml"
run_ps startup.ps1
assert_eq "win default layout exits 0" "$RC" 0
assert_file_contains "win finds LOCALAPPDATA server and default config" "$CASE/out" "status=not_running"
assert_file_contains "win default config is present" "$CASE/state/discovery.env" "config_present=1"
cleanup_case

new_win_case
rm -f "$CASE/bin/quicktui-server"
unset LOCALAPPDATA
mkdir -p "$USERPROFILE/AppData/Local/QuickTUI"
cp "$FIXTURES/fake-quicktui-server" "$USERPROFILE/AppData/Local/QuickTUI/quicktui-server.exe"
chmod 0755 "$USERPROFILE/AppData/Local/QuickTUI/quicktui-server.exe"
export QUICKTUI_CONFIG=$CASE/closed.toml
printf 'addr = "127.0.0.1:%s"\n' "$(free_port)" >"$QUICKTUI_CONFIG"
run_ps startup.ps1
assert_file_contains "win falls back to USERPROFILE AppData Local" "$CASE/out" "status=not_running"
cleanup_case

# --- installed, not running ---
new_win_case
export QUICKTUI_SERVER_BIN=$CASE/bin/quicktui-server
export QUICKTUI_CONFIG=$CASE/closed.toml
printf 'addr = "127.0.0.1:%s"\n' "$(free_port)" >"$QUICKTUI_CONFIG"
run_ps pair-qrcode.ps1
assert_eq "win qrcode refuses when not ready" "$RC" 4
assert_file_contains "win not ready prints the scheduled task" "$CASE/out" "schtasks /Run /TN QuickTUI"
assert_file_not_contains "win qrcode not ready does not run pairing" "$CASE/qt.log" "pairing"
run_ps setup.ps1
assert_eq "win setup not ready exits 4" "$RC" 4
cleanup_case

# --- custom config + ready ---
new_win_case
PORT=$(free_port)
start_capability "$PORT"
export QUICKTUI_SERVER_BIN=$CASE/bin/quicktui-server
export QUICKTUI_CONFIG=$CASE/path\ space/config.toml
printf 'addr = "127.0.0.1:%s"\n' "$PORT" >"$QUICKTUI_CONFIG"
run_ps startup.ps1
assert_eq "win startup ready exits 0" "$RC" 0
assert_file_contains "win startup ready status" "$CASE/out" "status=ready"
assert_file_not_contains "win state has no fingerprint" "$CASE/state/discovery.env" "SHOULD_NOT_LEAK_FINGERPRINT"
assert_file_not_contains "win stdout has no fingerprint" "$CASE/out" "SHOULD_NOT_LEAK_FINGERPRINT"
assert_file_not_contains "win state has no paths" "$CASE/state/discovery.env" "$CASE"
export FAKE_QT_ISSUE_CODE=1
run_ps setup.ps1
assert_eq "win headless setup ready exits 0" "$RC" 0
assert_file_not_contains "win headless setup does not run pairing" "$CASE/qt.log" "pairing"
assert_file_contains "win headless setup prints manual commands" "$CASE/out" "pairing welcome --config '$QUICKTUI_CONFIG'"
: >"$CASE/qt.log"
run_ps pair-qrcode.ps1
assert_eq "win qrcode ready runs official CLI" "$RC" 0
assert_file_contains "win qrcode argv" "$CASE/qt.log" "pairing qrcode --config $QUICKTUI_CONFIG"
assert_file_not_contains "win state has no pairing code" "$CASE/state/discovery.env" "SECRET-PAIRING-CODE"
export FAKE_QT_EXIT=9
run_ps pair-qrcode.ps1
assert_eq "win qrcode passes the CLI exit status" "$RC" 9
unset FAKE_QT_EXIT
stop_capability
cleanup_case

# --- console setup runs pairing welcome on the console ---
new_win_case
PORT=$(free_port)
start_capability "$PORT"
export QUICKTUI_SERVER_BIN=$CASE/bin/quicktui-server
export QUICKTUI_CONFIG=$CASE/config.toml
printf 'addr = "127.0.0.1:%s"\n' "$PORT" >"$QUICKTUI_CONFIG"
run_ps_pty "" setup.ps1
assert_eq "win console setup exits 0" "$RC" 0
assert_file_contains "win console setup runs pairing welcome" "$CASE/qt.log" "pairing welcome --config $QUICKTUI_CONFIG"
assert_file_contains "win pairing keeps the console" "$CASE/qt.log" "stdout=tty"
stop_capability
cleanup_case

# --- malicious context, workspace label, and addr ---
new_win_case
PWN=$CASE/pwned
export HERDR_PLUGIN_CONTEXT_JSON='{"workspace_label":"; touch '"$PWN"'; $(touch '"$PWN"')"}'
export HERDR_WORKSPACE_ID='$(New-Item '"$PWN"')'
export QUICKTUI_SERVER_BIN=$CASE/bin/quicktui-server
export QUICKTUI_CONFIG=$CASE/evil.toml
printf 'addr = "127.0.0.1:8022; New-Item %s"\n' "$PWN" >"$QUICKTUI_CONFIG"
run_ps startup.ps1
assert_eq "win malicious input startup exits 0" "$RC" 0
assert_file_contains "win malicious addr is invalid_config" "$CASE/out" "status=invalid_config"
if [ -e "$PWN" ]; then
	fail "win malicious input did not create files"
else
	pass "win malicious input did not create files"
fi
assert_file_not_contains "win state ignores workspace label" "$CASE/state/discovery.env" "touch"
run_ps pair-qrcode.ps1
assert_eq "win qrcode refuses invalid config" "$RC" 3
assert_file_not_contains "win invalid config does not run pairing" "$CASE/qt.log" "pairing"
cleanup_case

# --- invalid overrides keep explicit status ---
new_win_case
export QUICKTUI_SERVER_BIN=relative/bad
run_ps startup.ps1
assert_file_contains "win relative bin is invalid_bin" "$CASE/out" "status=invalid_bin"
run_ps setup.ps1
assert_eq "win setup invalid_bin exits 3" "$RC" 3
run_ps install.ps1
assert_eq "win install invalid_bin exits 3" "$RC" 3
cleanup_case

new_win_case
export QUICKTUI_SERVER_BIN=$CASE/bin/quicktui-server
export QUICKTUI_CONFIG=relative/config.toml
run_ps startup.ps1
assert_file_contains "win relative config is invalid_config" "$CASE/out" "status=invalid_config"
cleanup_case

new_win_case
export QUICKTUI_SERVER_BIN=$CASE/bin/missing-server
run_ps startup.ps1
assert_file_contains "win missing override bin is invalid_bin" "$CASE/out" "status=invalid_bin"
cleanup_case

# --- official scheme listen addresses ---
for _scheme in http https; do
	new_win_case
	PORT=$(free_port)
	start_capability "$PORT"
	export QUICKTUI_SERVER_BIN=$CASE/bin/quicktui-server
	export QUICKTUI_CONFIG=$CASE/scheme.toml
	printf 'addr = "%s://127.0.0.1:%s"\n' "$_scheme" "$PORT" >"$QUICKTUI_CONFIG"
	run_ps startup.ps1
	assert_file_contains "win $_scheme scheme config probes http locally" "$CASE/out" "status=ready"
	stop_capability
	cleanup_case
done

# --- actions open the -windows panes ---
new_win_case
for _entry in setup pair-qrcode install; do
	run_ps open-pane.ps1 "$_entry"
	assert_eq "win open-pane $_entry exits 0" "$RC" 0
	assert_file_contains "win open-pane $_entry argv" "$CASE/herdr.log" "plugin pane open --plugin ai.quicktui --entrypoint $_entry-windows"
done
run_ps open-pane.ps1 'setup;touch-pwned'
assert_eq "win open-pane rejects unknown entrypoint" "$RC" 2
assert_file_not_contains "win unknown entrypoint is not passed through" "$CASE/herdr.log" "touch-pwned"
run_ps open-pane.ps1
assert_eq "win open-pane requires an entrypoint" "$RC" 2
cleanup_case

# --- install: declined, empty, and headless input never download ---
# .NET console line editing on Linux does not turn Ctrl+D into EOF, so the
# empty answer is an empty line here; EOF on Windows reads as null and declines.
for _answer in n no "<enter>" maybe; do
	new_win_install_case
	run_ps_pty "$_answer" install.ps1
	assert_eq "win install answer '$_answer' exits 0" "$RC" 0
	assert_file_contains "win install answer '$_answer' shows the q.ps1 URL" "$CASE/out" "https://quicktui.ai/q.ps1"
	assert_file_contains "win install answer '$_answer' says cancelled" "$CASE/out" "install cancelled"
	assert_file_empty "win install answer '$_answer' does not run installer" "$CASE/installer.log"
	assert_win_tmp_clean "win install answer '$_answer' creates no temp file"
	cleanup_case
done

new_win_install_case
set +e
printf 'y\n' | "$PWSH" -NoProfile -File "$WIN/install.ps1" >"$CASE/out" 2>"$CASE/err"
RC=$?
set -e
assert_eq "win install without console exits 0" "$RC" 0
assert_file_contains "win install without console prints official command" "$CASE/out" "irm https://quicktui.ai/q.ps1 | iex"
assert_file_not_contains "win install without console does not prompt" "$CASE/out" "Install QuickTUI now?"
assert_file_empty "win install without console does not run installer" "$CASE/installer.log"
assert_win_tmp_clean "win install without console creates no temp file"
cleanup_case

# --- install: confirmed, server becomes ready, pairing welcome ---
new_win_install_case
PORT=$(free_port)
start_capability "$PORT"
export QUICKTUI_CONFIG=$CASE/config.toml
printf 'addr = "127.0.0.1:%s"\n' "$PORT" >"$QUICKTUI_CONFIG"
export FAKE_INSTALLER_SERVER_SRC=$FIXTURES/fake-quicktui-server
run_fake_download_pty y install
assert_eq "win install confirmed exits 0 after pairing" "$RC" 0
assert_file_contains "win install prompt asks for confirmation" "$CASE/out" "Install QuickTUI now? [y/N]"
assert_file_contains "win install prompt shows the argv" "$CASE/out" "powershell.exe -NoProfile -ExecutionPolicy Bypass -File <downloaded file>"
assert_file_contains "win install downloads the fixed URL" "$CASE/download.log" "url=https://quicktui.ai/q.ps1"
assert_win_installer_ran "win confirmed install"
assert_file_contains "win installer keeps the console" "$CASE/installer.log" "stdin=console"
assert_file_contains "win ready after install runs pairing welcome" "$CASE/qt.log" "pairing welcome --config $QUICKTUI_CONFIG"
assert_file_contains "win ready after install updates state" "$CASE/state/discovery.env" "status=ready"
stop_capability
cleanup_case

new_win_install_case
PORT=$(free_port)
start_capability "$PORT"
export QUICKTUI_CONFIG=$CASE/config.toml
printf 'addr = "127.0.0.1:%s"\n' "$PORT" >"$QUICKTUI_CONFIG"
export FAKE_INSTALLER_SERVER_SRC=$FIXTURES/fake-quicktui-server
run_fake_download_pty YES setup
assert_eq "win setup missing install exits 0 after pairing" "$RC" 0
assert_win_installer_ran "win setup install"
assert_file_contains "win setup install then pairing welcome" "$CASE/qt.log" "pairing welcome --config $QUICKTUI_CONFIG"
stop_capability
cleanup_case

# --- install: download failure ---
new_win_install_case
export FAKE_DOWNLOAD_FAIL=1
run_fake_download_pty y install
assert_eq "win install download failure exits 6" "$RC" 6
assert_file_contains "win install download failure is reported" "$CASE/out" "download failed"
assert_file_empty "win install download failure does not run installer" "$CASE/installer.log"
assert_win_tmp_clean "win install download failure leaves no temp file"
if [ "$(grep -c '^url=' "$CASE/download.log")" = 1 ]; then
	pass "win install download failure does not retry"
else
	fail "win install download failure does not retry"
fi
cleanup_case

# --- install: installer non-zero exit ---
new_win_install_case
export FAKE_INSTALLER_EXIT=9
run_fake_download_pty y install
assert_eq "win installer failure exits 7" "$RC" 7
assert_file_contains "win installer failure is reported" "$CASE/out" "installer exited with status 9"
assert_win_installer_ran "win failed install"
assert_file_not_contains "win installer failure does not pair" "$CASE/qt.log" "pairing"
if [ "$(grep -c '^path=' "$CASE/installer.log")" = 1 ]; then
	pass "win installer failure does not retry"
else
	fail "win installer failure does not retry"
fi
cleanup_case

# --- install: installed but not ready, bounded wait, then start guide ---
new_win_install_case
export QUICKTUI_CONFIG=$CASE/closed.toml
printf 'addr = "127.0.0.1:%s"\n' "$(free_port)" >"$QUICKTUI_CONFIG"
export FAKE_INSTALLER_SERVER_SRC=$FIXTURES/fake-quicktui-server
_started=$(date +%s)
run_fake_download_pty y install
_elapsed=$(($(date +%s) - _started))
assert_eq "win install ready timeout exits 4" "$RC" 4
assert_file_contains "win install ready timeout prints start guide" "$CASE/out" "not ready for pairing"
assert_file_contains "win install recheck finds the installed server" "$CASE/state/discovery.env" "server_present=1"
assert_file_not_contains "win install ready timeout does not pair" "$CASE/qt.log" "pairing"
if [ "$_elapsed" -ge 10 ] && [ "$_elapsed" -le 18 ]; then
	pass "win install ready wait is bounded (${_elapsed}s)"
else
	fail "win install ready wait is bounded (${_elapsed}s)"
fi
cleanup_case

# --- install: installer succeeds but no server appears ---
new_win_install_case
run_fake_download_pty y install
assert_eq "win install without server exits 4" "$RC" 4
assert_file_contains "win install without server explains where it looked" "$CASE/out" "LOCALAPPDATA"
cleanup_case

# --- install pane when QuickTUI is already installed ---
new_win_install_case
cp "$FIXTURES/fake-quicktui-server" "$CASE/bin/quicktui-server"
chmod 0755 "$CASE/bin/quicktui-server"
export QUICKTUI_CONFIG=$CASE/closed.toml
printf 'addr = "127.0.0.1:%s"\n' "$(free_port)" >"$QUICKTUI_CONFIG"
run_ps_pty y install.ps1
assert_eq "win install when already installed exits 0" "$RC" 0
assert_file_contains "win install when already installed points to Setup" "$CASE/out" "already installed"
assert_file_empty "win install when already installed does not run installer" "$CASE/installer.log"
cleanup_case

# --- first-run toast, shared marker with the Unix entry points ---
new_win_case
rm -f "$CASE/bin/quicktui-server"
run_ps startup.ps1
assert_eq "win first startup with toast exits 0" "$RC" 0
assert_file_contains "win first startup shows install toast" "$CASE/herdr.log" "notification show QuickTUI --body"
assert_file_contains "win missing toast names the install action" "$CASE/herdr.log" "QuickTUI Install action"
if grep -Eq '^toast_shown_at=[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]{8}Z$' "$CASE/state/onboarding.env" &&
	[ "$(grep -c '' "$CASE/state/onboarding.env")" = 1 ]; then
	pass "win toast marker holds only the shown time"
else
	fail "win toast marker holds only the shown time"
fi
run_ps startup.ps1
if [ "$(grep -c 'notification show' "$CASE/herdr.log")" = 1 ]; then
	pass "win second startup does not toast again"
else
	fail "win second startup does not toast again"
fi
run_startup
if [ "$(grep -c 'notification show' "$CASE/herdr.log")" = 1 ]; then
	pass "unix startup honors the Windows toast marker"
else
	fail "unix startup honors the Windows toast marker"
fi
cleanup_case

new_win_case
export FAKE_HERDR_NOTIFY_EXIT=1
rm -f "$CASE/bin/quicktui-server"
run_ps startup.ps1
assert_eq "win toast failure keeps startup exit 0" "$RC" 0
if [ -e "$CASE/state/onboarding.env" ]; then
	fail "win toast failure writes no marker"
else
	pass "win toast failure writes no marker"
fi
unset FAKE_HERDR_NOTIFY_EXIT
run_ps startup.ps1
assert_file_contains "win toast retried after failure writes marker" "$CASE/state/onboarding.env" "toast_shown_at="
cleanup_case

new_win_case
PORT=$(free_port)
start_capability "$PORT"
export QUICKTUI_SERVER_BIN=$CASE/bin/quicktui-server
export QUICKTUI_CONFIG=$CASE/config.toml
printf 'addr = "127.0.0.1:%s"\n' "$PORT" >"$QUICKTUI_CONFIG"
run_ps startup.ps1
assert_file_contains "win ready toast names the pairing action" "$CASE/herdr.log" "QuickTUI Pairing QR action"
assert_file_not_contains "win toast marker has no paths" "$CASE/state/onboarding.env" "$CASE"
stop_capability
cleanup_case

new_win_case
printf '%s\n' '#!/bin/sh' 'if [ "${1-}" = notification ]; then sleep 41 & wait; fi' 'exit 0' >"$CASE/bin/herdr"
chmod 0755 "$CASE/bin/herdr"
rm -f "$CASE/bin/quicktui-server"
_started=$(date +%s)
run_ps startup.ps1
_elapsed=$(($(date +%s) - _started))
assert_eq "win hanging toast keeps startup exit 0" "$RC" 0
if [ "$_elapsed" -le 9 ]; then
	pass "win hanging toast is bounded (${_elapsed}s)"
else
	fail "win hanging toast is bounded (${_elapsed}s)"
fi
if [ -e "$CASE/state/onboarding.env" ]; then
	fail "win hanging toast writes no marker"
else
	pass "win hanging toast writes no marker"
fi
if pgrep -f "^sleep 41$" >/dev/null 2>&1; then
	fail "win hanging toast process tree is killed"
else
	pass "win hanging toast process tree is killed"
fi
cleanup_case
