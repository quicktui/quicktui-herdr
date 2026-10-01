# Install flow and first-run toast cases. Sourced by tests/run.sh, which
# provides new_case, cleanup_case, the assert helpers, and the capability server.

new_install_case() {
	new_case
	cp "$FIXTURES/fake-curl" "$CASE/bin/curl"
	chmod 0755 "$CASE/bin/curl"
	rm -f "$CASE/bin/quicktui-server"
	export FAKE_REAL_CURL=$REAL_CURL
	export FAKE_CURL_LOG=$CASE/curl.log
	export FAKE_CURL_PAYLOAD=$FIXTURES/fake-q.sh
	export FAKE_INSTALLER_LOG=$CASE/installer.log
	export TMPDIR=$CASE/tmp
	: >"$FAKE_CURL_LOG"
	: >"$FAKE_INSTALLER_LOG"
}

run_in_pty() {
	# $1 typed line ("" sends EOF), $2 script name under scripts/
	set +e
	python3 "$FIXTURES/run-in-pty.py" "$1" "$CASE/out" "$ROOT/scripts/$2"
	RC=$?
	set -e
}

assert_file_empty() {
	if [ -s "$2" ]; then
		fail "$1 ($2 is not empty)"
	else
		pass "$1"
	fi
}

assert_tmp_clean() {
	if [ -z "$(find "$CASE/tmp" -mindepth 1 -print)" ]; then
		pass "$1"
	else
		fail "$1 (leftover files in $CASE/tmp)"
	fi
}

installer_argv0() {
	sed -n 's/^argv0=\([^ ]*\) argc=.*$/\1/p' "$CASE/installer.log"
}

assert_installer_ran_from_temp_file() {
	_argv0=$(installer_argv0)
	case $_argv0 in
	"$CASE/tmp/quicktui-q.sh."*) pass "$1 runs sh <private temp file>" ;;
	*) fail "$1 runs sh <private temp file> (argv0=$_argv0)" ;;
	esac
	assert_file_contains "$1 passes no installer args" "$CASE/installer.log" "argc=0"
	if [ -n "$_argv0" ] && [ ! -e "$_argv0" ]; then
		pass "$1 removes the temp file"
	else
		fail "$1 removes the temp file"
	fi
	assert_tmp_clean "$1 leaves no temp files"
}

# --- static: install path never pipes into a shell ---
if awk '
	$0 ~ /^[ \t]*#/ { next }
	$0 ~ /^QT_INSTALL_GLOBAL=/ { next }
	$0 ~ /\|[ \t]*(\/bin\/)?(ba|da|z)?sh([ \t;)]|$)/ {
		printf "%s:%d:%s\n", FILENAME, FNR, $0
		bad = 1
	}
	END { exit bad ? 1 : 0 }
' "$ROOT/scripts"/*.sh >/dev/null 2>&1; then
	pass "scripts never pipe into a shell"
else
	fail "scripts never pipe into a shell"
fi

if grep -R -F -e dl.quicktui.cn "$ROOT/README.md" "$ROOT/scripts" >/dev/null 2>&1; then
	fail "README and scripts have no CN mirror"
else
	pass "README and scripts have no CN mirror"
fi

_missing_images=
for _image in $(grep -oE 'docs/images/[A-Za-z0-9._-]+' "$ROOT/README.md"); do
	if [ ! -s "$ROOT/$_image" ]; then
		_missing_images="$_missing_images $_image"
	fi
done
if [ -z "$_missing_images" ] && grep -F -e 'docs/images/' "$ROOT/README.md" >/dev/null; then
	pass "README images exist in the repository"
else
	fail "README images exist in the repository (missing:$_missing_images)"
fi

# --- confirmed install, server becomes ready, pairing welcome ---
new_install_case
PORT=$(free_port)
start_capability "$PORT"
export QUICKTUI_CONFIG=$CASE/config.toml
printf 'addr = "127.0.0.1:%s"\n' "$PORT" >"$QUICKTUI_CONFIG"
export FAKE_INSTALLER_SERVER_SRC=$FIXTURES/fake-quicktui-server
run_in_pty y install.sh
assert_eq "install confirmed exits 0 after pairing" "$RC" 0
assert_file_contains "install prompt shows official URL" "$CASE/out" "https://quicktui.ai/q.sh"
assert_file_contains "install prompt asks for confirmation" "$CASE/out" "Install QuickTUI now? [y/N]"
assert_file_contains "install downloads fixed URL" "$CASE/curl.log" "--url https://quicktui.ai/q.sh"
assert_file_contains "install download is https only" "$CASE/curl.log" "--proto =https --proto-redir =https"
assert_file_contains "install download fails on HTTP errors" "$CASE/curl.log" "--fail"
assert_file_contains "install downloads to a temp file" "$CASE/curl.log" "--output $CASE/tmp/quicktui-q.sh."
assert_installer_ran_from_temp_file "confirmed install"
assert_file_contains "installer keeps the pane TTY" "$CASE/installer.log" "stdin=tty"
assert_file_contains "ready after install execs pairing welcome" "$CASE/qt.log" "pairing welcome --config $QUICKTUI_CONFIG"
assert_file_contains "ready after install updates state" "$CASE/state/discovery.env" "status=ready"
stop_capability
cleanup_case

# --- Setup with QuickTUI missing enters the same flow ---
new_install_case
PORT=$(free_port)
start_capability "$PORT"
export QUICKTUI_CONFIG=$CASE/config.toml
printf 'addr = "127.0.0.1:%s"\n' "$PORT" >"$QUICKTUI_CONFIG"
export FAKE_INSTALLER_SERVER_SRC=$FIXTURES/fake-quicktui-server
run_in_pty YES setup.sh
assert_eq "setup missing install exits 0 after pairing" "$RC" 0
assert_file_contains "setup missing shows the install prompt" "$CASE/out" "Install QuickTUI now? [y/N]"
assert_installer_ran_from_temp_file "setup install"
assert_file_contains "setup install then pairing welcome" "$CASE/qt.log" "pairing welcome --config $QUICKTUI_CONFIG"
stop_capability
cleanup_case

# --- declined, empty, and headless input never download ---
for _answer in n no "" maybe; do
	new_install_case
	run_in_pty "$_answer" install.sh
	assert_eq "install answer '$_answer' exits 0" "$RC" 0
	assert_file_empty "install answer '$_answer' does not download" "$CASE/curl.log"
	assert_file_empty "install answer '$_answer' does not run installer" "$CASE/installer.log"
	assert_file_contains "install answer '$_answer' says cancelled" "$CASE/out" "install cancelled"
	assert_tmp_clean "install answer '$_answer' creates no temp file"
	cleanup_case
done

new_install_case
run_in_pty n setup.sh
assert_eq "setup missing declined exits 0" "$RC" 0
assert_file_empty "setup missing declined does not download" "$CASE/curl.log"
cleanup_case

new_install_case
set +e
printf 'y\n' | "$ROOT/scripts/install.sh" >"$CASE/out" 2>"$CASE/err"
RC=$?
set -e
assert_eq "install without TTY exits 0" "$RC" 0
assert_file_empty "install without TTY ignores piped yes" "$CASE/curl.log"
assert_file_empty "install without TTY does not run installer" "$CASE/installer.log"
assert_file_contains "install without TTY prints official command" "$CASE/out" "curl -fsSL https://quicktui.ai/q.sh | sh"
assert_file_contains "install without TTY names the install action" "$CASE/out" "ai.quicktui.install"
assert_file_not_contains "install guide has no CN mirror" "$CASE/out" "dl.quicktui.cn"
cleanup_case

new_install_case
set +e
"$ROOT/scripts/setup.sh" </dev/null >"$CASE/out" 2>"$CASE/err"
RC=$?
set -e
assert_eq "setup missing without TTY exits 0" "$RC" 0
assert_file_empty "setup missing without TTY does not download" "$CASE/curl.log"
cleanup_case

# --- download failure ---
new_install_case
export FAKE_CURL_EXIT=22
run_in_pty y install.sh
assert_eq "install download failure exits 6" "$RC" 6
assert_file_contains "install download failure is reported" "$CASE/out" "download failed"
assert_file_empty "install download failure does not run installer" "$CASE/installer.log"
assert_tmp_clean "install download failure removes the temp file"
if [ "$(grep -c 'quicktui.ai/q.sh' "$CASE/curl.log")" = 1 ]; then
	pass "install download failure does not retry"
else
	fail "install download failure does not retry"
fi
cleanup_case

# --- installer non-zero exit ---
new_install_case
export FAKE_INSTALLER_EXIT=9
run_in_pty y install.sh
assert_eq "installer failure exits 7" "$RC" 7
assert_file_contains "installer failure is reported" "$CASE/out" "installer exited with status 9"
assert_installer_ran_from_temp_file "failed install"
assert_file_not_contains "installer failure does not pair" "$CASE/qt.log" "pairing"
if [ "$(grep -c '^argv0=' "$CASE/installer.log")" = 1 ]; then
	pass "installer failure does not retry"
else
	fail "installer failure does not retry"
fi
cleanup_case

# --- installed but not ready: bounded wait, then start guide ---
new_install_case
export QUICKTUI_CONFIG=$CASE/closed.toml
printf 'addr = "127.0.0.1:%s"\n' "$(free_port)" >"$QUICKTUI_CONFIG"
export FAKE_INSTALLER_SERVER_SRC=$FIXTURES/fake-quicktui-server
_started=$(date +%s)
run_in_pty y install.sh
_elapsed=$(($(date +%s) - _started))
assert_eq "install ready timeout exits 4" "$RC" 4
assert_file_contains "install ready timeout prints start guide" "$CASE/out" "not ready for pairing"
assert_file_not_contains "install ready timeout does not pair" "$CASE/qt.log" "pairing"
if [ "$_elapsed" -ge 10 ] && [ "$_elapsed" -le 16 ]; then
	pass "install ready wait is bounded (${_elapsed}s)"
else
	fail "install ready wait is bounded (${_elapsed}s)"
fi
cleanup_case

# --- install pane when QuickTUI is already installed ---
new_install_case
cp "$FIXTURES/fake-quicktui-server" "$CASE/bin/quicktui-server"
chmod 0755 "$CASE/bin/quicktui-server"
export QUICKTUI_CONFIG=$CASE/closed.toml
printf 'addr = "127.0.0.1:%s"\n' "$(free_port)" >"$QUICKTUI_CONFIG"
run_in_pty y install.sh
assert_eq "install when already installed exits 0" "$RC" 0
assert_file_contains "install when already installed points to Setup" "$CASE/out" "already installed"
assert_file_empty "install when already installed does not download" "$CASE/curl.log"
cleanup_case

# --- first-run toast ---
new_case
rm -f "$CASE/bin/quicktui-server"
run_startup
assert_eq "first startup with toast exits 0" "$RC" 0
assert_file_contains "first startup shows install toast" "$CASE/herdr.log" "notification show QuickTUI --body"
assert_file_contains "missing toast names the install action" "$CASE/herdr.log" "QuickTUI Install action"
if grep -Eq '^toast_shown_at=[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]{8}Z$' "$CASE/state/onboarding.env" &&
	[ "$(grep -c '' "$CASE/state/onboarding.env")" = 1 ]; then
	pass "toast marker holds only the shown time"
else
	fail "toast marker holds only the shown time"
fi
run_startup
assert_eq "second startup exits 0" "$RC" 0
if [ "$(grep -c 'notification show' "$CASE/herdr.log")" = 1 ]; then
	pass "second startup does not toast again"
else
	fail "second startup does not toast again"
fi
cleanup_case

new_case
export FAKE_HERDR_NOTIFY_EXIT=1
rm -f "$CASE/bin/quicktui-server"
run_startup
assert_eq "toast failure keeps startup exit 0" "$RC" 0
assert_file_contains "toast failure keeps discovery status" "$CASE/out" "status=missing"
if [ -e "$CASE/state/onboarding.env" ]; then
	fail "toast failure writes no marker"
else
	pass "toast failure writes no marker"
fi
unset FAKE_HERDR_NOTIFY_EXIT
run_startup
assert_file_contains "toast retried after failure writes marker" "$CASE/state/onboarding.env" "toast_shown_at="
cleanup_case

new_case
PORT=$(free_port)
start_capability "$PORT"
export QUICKTUI_SERVER_BIN=$CASE/bin/quicktui-server
export QUICKTUI_CONFIG=$CASE/config.toml
printf 'addr = "127.0.0.1:%s"\n' "$PORT" >"$QUICKTUI_CONFIG"
run_startup
assert_eq "ready startup with toast exits 0" "$RC" 0
assert_file_contains "ready toast names the pairing action" "$CASE/herdr.log" "QuickTUI Pairing QR action"
assert_file_not_contains "toast marker has no paths" "$CASE/state/onboarding.env" "$CASE"
assert_file_not_contains "toast has no fingerprint" "$CASE/herdr.log" "SHOULD_NOT_LEAK_FINGERPRINT"
stop_capability
cleanup_case

new_case
# Unique sleep argument so concurrent suites on this host cannot collide.
_sleep_arg=37.$$
printf '%s\n' '#!/bin/sh' "if [ \"\${1-}\" = notification ]; then sleep $_sleep_arg & wait; fi" 'exit 0' >"$CASE/bin/herdr"
chmod 0755 "$CASE/bin/herdr"
rm -f "$CASE/bin/quicktui-server"
before=$(pgrep -c -P $$ || true)
_started=$(date +%s)
run_startup
_elapsed=$(($(date +%s) - _started))
after=$(pgrep -c -P $$ || true)
assert_eq "hanging toast keeps startup exit 0" "$RC" 0
assert_eq "hanging toast leaves no child" "$after" "$before"
if [ "$_elapsed" -le 8 ]; then
	pass "hanging toast is bounded (${_elapsed}s)"
else
	fail "hanging toast is bounded (${_elapsed}s)"
fi
if [ -e "$CASE/state/onboarding.env" ]; then
	fail "hanging toast writes no marker"
else
	pass "hanging toast writes no marker"
fi
if pgrep -f "^sleep $_sleep_arg$" >/dev/null 2>&1 || pgrep -f "$CASE/bin/herdr" >/dev/null 2>&1; then
	fail "hanging toast process group is killed"
else
	pass "hanging toast process group is killed"
fi
cleanup_case
