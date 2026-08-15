#!/bin/sh
# Fixture tests for quicktui-herdr. Uses fake Herdr/QuickTUI binaries.
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
FIXTURES=$ROOT/tests/fixtures
FAILED=0
RAN=0

pass() {
	RAN=$((RAN + 1))
	printf 'ok %s\n' "$1"
}

fail() {
	RAN=$((RAN + 1))
	FAILED=$((FAILED + 1))
	printf 'not ok %s\n' "$1" >&2
}

assert_eq() {
	_name=$1
	_got=$2
	_want=$3
	if [ "$_got" = "$_want" ]; then
		pass "$_name"
	else
		fail "$_name (got=$_got want=$_want)"
	fi
}

assert_file_contains() {
	_name=$1
	_file=$2
	_needle=$3
	if grep -F "$_needle" "$_file" >/dev/null 2>&1; then
		pass "$_name"
	else
		fail "$_name (missing $_needle in $_file)"
	fi
}

assert_file_not_contains() {
	_name=$1
	_file=$2
	_needle=$3
	if grep -F "$_needle" "$_file" >/dev/null 2>&1; then
		fail "$_name (found $_needle in $_file)"
	else
		pass "$_name"
	fi
}

free_port() {
	python3 - <<'PY'
import socket
s = socket.socket()
s.bind(("127.0.0.1", 0))
print(s.getsockname()[1])
s.close()
PY
}

start_capability() {
	_port=$1
	python3 "$FIXTURES/capability-server.py" "$_port" &
	QT_CAP_PID=$!
	_tries=0
	while [ "$_tries" -lt 50 ]; do
		if python3 - "$_port" <<'PY'
import socket, sys
s = socket.socket()
s.settimeout(0.1)
try:
    s.connect(("127.0.0.1", int(sys.argv[1])))
except OSError:
    sys.exit(1)
finally:
    s.close()
PY
		then
			return 0
		fi
		_tries=$((_tries + 1))
		sleep 0.05
	done
	return 1
}

stop_capability() {
	if [ -n "${QT_CAP_PID-}" ]; then
		kill "$QT_CAP_PID" >/dev/null 2>&1 || true
		wait "$QT_CAP_PID" >/dev/null 2>&1 || true
		QT_CAP_PID=
	fi
}

new_case() {
	CASE=$(mktemp -d "${TMPDIR:-/tmp}/quicktui-herdr-test.XXXXXX")
	mkdir -p "$CASE/home" "$CASE/bin" "$CASE/state" "$CASE/config" "$CASE/path space"
	cp "$FIXTURES/fake-herdr" "$CASE/bin/herdr"
	cp "$FIXTURES/fake-quicktui-server" "$CASE/bin/quicktui-server"
	chmod 0755 "$CASE/bin/herdr" "$CASE/bin/quicktui-server"
	export HOME=$CASE/home
	export PATH=$CASE/bin:/usr/bin:/bin
	export HERDR_BIN_PATH=$CASE/bin/herdr
	export HERDR_SOCKET_PATH=$CASE/herdr.sock
	export HERDR_PLUGIN_ID=ai.quicktui
	export HERDR_PLUGIN_ROOT=$ROOT
	export HERDR_PLUGIN_STATE_DIR=$CASE/state
	export HERDR_PLUGIN_CONFIG_DIR=$CASE/config
	export FAKE_HERDR_LOG=$CASE/herdr.log
	export FAKE_QT_LOG=$CASE/qt.log
	unset QUICKTUI_SERVER_BIN QUICKTUI_CONFIG FAKE_QT_ISSUE_CODE FAKE_HERDR_EXIT FAKE_QT_EXIT
	: >"$FAKE_HERDR_LOG"
	: >"$FAKE_QT_LOG"
}

cleanup_case() {
	stop_capability
	if [ -n "${CASE-}" ] && [ -d "$CASE" ]; then
		rm -rf "$CASE"
	fi
}

run_startup() {
	set +e
	"$ROOT/scripts/startup.sh" >"$CASE/out" 2>"$CASE/err"
	RC=$?
	set -e
}

run_setup() {
	set +e
	"$ROOT/scripts/setup.sh" >"$CASE/out" 2>"$CASE/err"
	RC=$?
	set -e
}

run_qr() {
	set +e
	"$ROOT/scripts/pair-qrcode.sh" >"$CASE/out" 2>"$CASE/err"
	RC=$?
	set -e
}

# --- static checks ---
if python3 - <<PY
import pathlib
import tomllib
root = pathlib.Path("$ROOT")
manifest = tomllib.loads((root / "herdr-plugin.toml").read_text())
assert manifest["id"] == "ai.quicktui"
assert manifest["min_herdr_version"] == "0.8.0"
assert manifest["platforms"] == ["linux", "macos"]
assert manifest["startup"][0]["command"] == ["./scripts/startup.sh"]
actions = {item["id"]: item for item in manifest["actions"]}
assert actions["setup"]["command"] == ["./scripts/open-pane.sh", "setup"]
assert actions["pair-qrcode"]["command"] == ["./scripts/open-pane.sh", "pair-qrcode"]
assert "workspace" in actions["setup"]["contexts"]
assert "global" in actions["setup"]["contexts"]
panes = {item["id"]: item for item in manifest["panes"]}
assert panes["setup"]["command"] == ["./scripts/setup.sh"]
assert panes["setup"]["placement"] == "popup"
assert panes["pair-qrcode"]["command"] == ["./scripts/pair-qrcode.sh"]
print("ok")
PY
then
	pass "manifest validates required v0.8.0 fields"
else
	fail "manifest validates required v0.8.0 fields"
fi

if awk '
	FNR == 1 { file = FILENAME }
	$0 ~ /^[ \t]*#/ { next }
	$0 ~ /(^|[^A-Za-z_])eval[ \t]|sh -c|bash -c/ {
		printf "%s:%d:%s\n", file, FNR, $0
		bad = 1
	}
	END { exit bad ? 1 : 0 }
' "$ROOT/scripts"/*.sh >/dev/null 2>&1; then
	pass "scripts contain no eval or sh -c"
else
	fail "scripts contain no eval or sh -c"
fi

for _script in startup.sh setup.sh pair-qrcode.sh open-pane.sh; do
	if [ -x "$ROOT/scripts/$_script" ]; then
		pass "scripts/$_script is executable"
	else
		fail "scripts/$_script is executable"
	fi
done

# --- missing env ---
new_case
unset HERDR_BIN_PATH
run_startup
assert_eq "startup missing HERDR_BIN_PATH exits 2" "$RC" 2
cleanup_case

new_case
unset HERDR_PLUGIN_ID
run_startup
assert_eq "startup missing HERDR_PLUGIN_ID exits 2" "$RC" 2
cleanup_case

new_case
export HERDR_BIN_PATH=$(printf '/tmp/herdr\nbad')
run_startup
assert_eq "startup rejects HERDR_BIN_PATH with newline" "$RC" 2
cleanup_case

# --- path with spaces ---
new_case
spaced=$CASE/path\ space
mkdir -p "$spaced"
cp "$CASE/bin/herdr" "$spaced/herdr bin"
cp "$CASE/bin/quicktui-server" "$spaced/quicktui server"
chmod 0755 "$spaced/herdr bin" "$spaced/quicktui server"
export HERDR_BIN_PATH=$spaced/herdr\ bin
export QUICKTUI_SERVER_BIN=$spaced/quicktui\ server
export QUICKTUI_CONFIG=$spaced/config.toml
printf 'addr = "127.0.0.1:65534"\n' >"$QUICKTUI_CONFIG"
run_startup
assert_eq "startup accepts paths with spaces" "$RC" 0
assert_file_contains "startup space path status" "$CASE/out" "status=not_running"
cleanup_case

# --- QuickTUI missing ---
new_case
rm -f "$CASE/bin/quicktui-server"
run_startup
assert_eq "startup missing QuickTUI exits 0" "$RC" 0
assert_file_contains "startup missing status" "$CASE/out" "status=missing"
assert_file_contains "startup missing state" "$CASE/state/discovery.env" "status=missing"
run_setup </dev/null
assert_eq "setup missing QuickTUI exits 0" "$RC" 0
assert_file_contains "setup prints official install" "$CASE/out" "https://quicktui.ai/q.sh"
assert_file_not_contains "setup missing does not call pairing" "$CASE/qt.log" "pairing"
cleanup_case

# --- installed, not running ---
new_case
export QUICKTUI_SERVER_BIN=$CASE/bin/quicktui-server
export QUICKTUI_CONFIG=$CASE/closed.toml
printf 'addr = "127.0.0.1:%s"\n' "$(free_port)" >"$QUICKTUI_CONFIG"
run_startup
assert_eq "startup not_running exits 0" "$RC" 0
assert_file_contains "startup not_running status" "$CASE/out" "status=not_running"
run_qr </dev/null
assert_eq "qrcode refuses when not ready" "$RC" 4
assert_file_not_contains "qrcode not ready does not exec pairing" "$CASE/qt.log" "pairing"
assert_file_not_contains "state has no pairing code" "$CASE/state/discovery.env" "SECRET-PAIRING-CODE"
cleanup_case

# --- custom config + ready ---
new_case
PORT=$(free_port)
start_capability "$PORT"
export QUICKTUI_SERVER_BIN=$CASE/bin/quicktui-server
export QUICKTUI_CONFIG=$CASE/path\ space/config.toml
printf 'addr = "127.0.0.1:%s"\n' "$PORT" >"$QUICKTUI_CONFIG"
run_startup
assert_eq "startup ready with custom config exits 0" "$RC" 0
assert_file_contains "startup ready status" "$CASE/out" "status=ready"
assert_file_not_contains "startup does not persist fingerprint" "$CASE/state/discovery.env" "SHOULD_NOT_LEAK_FINGERPRINT"
assert_file_not_contains "startup stdout has no fingerprint" "$CASE/out" "SHOULD_NOT_LEAK_FINGERPRINT"
assert_file_not_contains "startup state has no socket path" "$CASE/state/discovery.env" "$HERDR_SOCKET_PATH"
# handoff rerun
run_startup
assert_eq "startup handoff rerun exits 0" "$RC" 0
assert_file_contains "handoff state remains ready" "$CASE/state/discovery.env" "status=ready"
# headless setup must not issue a code
export FAKE_QT_ISSUE_CODE=1
run_setup </dev/null
assert_eq "headless setup ready exits 0" "$RC" 0
assert_file_not_contains "headless setup does not exec pairing" "$CASE/qt.log" "pairing"
assert_file_contains "headless setup prints manual commands" "$CASE/out" "pairing welcome"
assert_file_contains "headless quotes spaced config" "$CASE/out" "'$QUICKTUI_CONFIG'"
# pairing qrcode when ready
: >"$CASE/qt.log"
run_qr </dev/null
assert_eq "qrcode ready execs official CLI" "$RC" 0
assert_file_contains "qrcode argv" "$CASE/qt.log" "pairing qrcode --config $QUICKTUI_CONFIG"
assert_file_not_contains "qrcode does not use --print-code" "$CASE/qt.log" "--print-code"
assert_file_not_contains "state still has no pairing code" "$CASE/state/discovery.env" "SECRET-PAIRING-CODE"
stop_capability
cleanup_case

# --- TTY setup execs welcome ---
new_case
PORT=$(free_port)
start_capability "$PORT"
export QUICKTUI_SERVER_BIN=$CASE/bin/quicktui-server
export QUICKTUI_CONFIG=$CASE/config.toml
printf 'addr = "127.0.0.1:%s"\n' "$PORT" >"$QUICKTUI_CONFIG"
export FAKE_QT_ISSUE_CODE=1
python3 - "$ROOT/scripts/setup.sh" "$CASE/out" "$CASE/err" <<'PY'
import os
import pty
import sys

script, out_path, err_path = sys.argv[1:]
pid, fd = pty.fork()
if pid == 0:
    os.execv(script, [script])
os.waitpid(pid, 0)
# Drain PTY so the child is not blocked; output already went to the PTY.
try:
    os.close(fd)
except OSError:
    pass
PY
assert_file_contains "TTY setup execs pairing welcome" "$CASE/qt.log" "pairing welcome --config $QUICKTUI_CONFIG"
assert_file_not_contains "TTY setup state has no pairing code" "$CASE/state/discovery.env" "SECRET-PAIRING-CODE"
stop_capability
cleanup_case

# --- malicious context / workspace label ---
new_case
PWN=$CASE/pwned
export HERDR_PLUGIN_CONTEXT_JSON='{"workspace_label":"; touch '"$PWN"'; echo pwned $(reboot)"}'
export HERDR_WORKSPACE_ID='$(touch '"$PWN"')'
export HERDR_PLUGIN_EVENT_JSON='{"on":"`touch '"$PWN"'`"}'
export QUICKTUI_SERVER_BIN=$CASE/bin/quicktui-server
run_startup
assert_eq "malicious context startup exits 0" "$RC" 0
if [ -e "$PWN" ]; then
	fail "malicious context did not create files"
else
	pass "malicious context did not create files"
fi
assert_file_not_contains "state ignores workspace label" "$CASE/state/discovery.env" "touch"
assert_file_not_contains "stdout ignores workspace label" "$CASE/out" "pwned"
cleanup_case

# --- malicious addr is not executed ---
new_case
PWN=$CASE/pwned
export QUICKTUI_SERVER_BIN=$CASE/bin/quicktui-server
export QUICKTUI_CONFIG=$CASE/evil.toml
printf 'addr = "127.0.0.1:8022; touch %s"\n' "$PWN" >"$QUICKTUI_CONFIG"
run_startup
assert_eq "malicious addr stays invalid_config" "$RC" 0
assert_file_contains "malicious addr status" "$CASE/out" "status=invalid_config"
if [ -e "$PWN" ]; then
	fail "malicious addr did not execute"
else
	pass "malicious addr did not execute"
fi
run_qr </dev/null
assert_eq "qrcode refuses invalid config" "$RC" 3
assert_file_not_contains "invalid config does not exec pairing" "$CASE/qt.log" "pairing"
cleanup_case

# --- invalid overrides keep explicit status ---
new_case
export QUICKTUI_SERVER_BIN=relative/bad
run_startup
assert_eq "relative QUICKTUI_SERVER_BIN exits 0" "$RC" 0
assert_file_contains "relative bin is invalid_bin" "$CASE/out" "status=invalid_bin"
run_setup </dev/null
assert_eq "setup invalid_bin exits 3" "$RC" 3
cleanup_case

new_case
export QUICKTUI_SERVER_BIN=$CASE/bin/quicktui-server
export QUICKTUI_CONFIG=relative/config.toml
run_startup
assert_eq "relative QUICKTUI_CONFIG exits 0" "$RC" 0
assert_file_contains "relative config is invalid_config" "$CASE/out" "status=invalid_config"
run_qr </dev/null
assert_eq "qrcode invalid_config exits 3" "$RC" 3
assert_file_not_contains "invalid config does not exec pairing" "$CASE/qt.log" "pairing"
cleanup_case

# --- official scheme listen addresses ---
new_case
PORT=$(free_port)
start_capability "$PORT"
export QUICKTUI_SERVER_BIN=$CASE/bin/quicktui-server
export QUICKTUI_CONFIG=$CASE/http.toml
printf 'addr = "http://127.0.0.1:%s"\n' "$PORT" >"$QUICKTUI_CONFIG"
run_startup
assert_eq "http scheme config is ready" "$RC" 0
assert_file_contains "http scheme status" "$CASE/out" "status=ready"
stop_capability
cleanup_case

new_case
PORT=$(free_port)
start_capability "$PORT"
export QUICKTUI_SERVER_BIN=$CASE/bin/quicktui-server
export QUICKTUI_CONFIG=$CASE/https.toml
printf 'addr = "https://127.0.0.1:%s"\n' "$PORT" >"$QUICKTUI_CONFIG"
run_startup
assert_eq "https scheme config still probes http locally" "$RC" 0
assert_file_contains "https scheme status" "$CASE/out" "status=ready"
stop_capability
cleanup_case

# --- actions open panes instead of pairing without a TTY ---
new_case
set +e
"$ROOT/scripts/open-pane.sh" setup >"$CASE/out" 2>"$CASE/err"
RC=$?
set -e
assert_eq "open-pane setup exits 0" "$RC" 0
assert_file_contains "open-pane setup argv" "$CASE/herdr.log" "plugin pane open --plugin ai.quicktui --entrypoint setup"
set +e
"$ROOT/scripts/open-pane.sh" pair-qrcode >"$CASE/out" 2>"$CASE/err"
RC=$?
set -e
assert_file_contains "open-pane qrcode argv" "$CASE/herdr.log" "plugin pane open --plugin ai.quicktui --entrypoint pair-qrcode"
set +e
"$ROOT/scripts/open-pane.sh" 'setup;touch-pwned' >"$CASE/out" 2>"$CASE/err"
RC=$?
set -e
assert_eq "open-pane rejects unknown entrypoint" "$RC" 2
assert_file_not_contains "unknown entrypoint is not passed through" "$CASE/herdr.log" "touch-pwned"
cleanup_case

# --- hostname without curl stays bounded ---
new_case
mkdir -p "$CASE/rbin"
ln -s "$(command -v python3)" "$CASE/rbin/python3"
ln -s "$(command -v awk)" "$CASE/rbin/awk"
ln -s "$(command -v date)" "$CASE/rbin/date"
ln -s "$(command -v mkdir)" "$CASE/rbin/mkdir"
ln -s "$(command -v dirname)" "$CASE/rbin/dirname"
ln -s "$(command -v mv)" "$CASE/rbin/mv"
ln -s "$(command -v rm)" "$CASE/rbin/rm"
export PATH=$CASE/bin:$CASE/rbin
export QUICKTUI_SERVER_BIN=$CASE/bin/quicktui-server
export QUICKTUI_CONFIG=$CASE/host.toml
printf 'addr = "stuck.example:65531"\n' >"$QUICKTUI_CONFIG"
run_startup
export PATH=$CASE/bin:/usr/bin:/bin
assert_eq "hostname without curl exits 0" "$RC" 0
assert_file_contains "hostname without curl is unknown" "$CASE/out" "status=unknown"
cleanup_case

# --- leftover children ---
new_case
export QUICKTUI_SERVER_BIN=$CASE/bin/quicktui-server
export QUICKTUI_CONFIG=$CASE/closed.toml
printf 'addr = "127.0.0.1:%s"\n' "$(free_port)" >"$QUICKTUI_CONFIG"
before=$(pgrep -c -P $$ || true)
run_startup
after=$(pgrep -c -P $$ || true)
assert_eq "startup leftover child count unchanged" "$after" "$before"
cleanup_case

# --- herdr CLI is invoked via HERDR_BIN_PATH ---
new_case
rm -f "$CASE/bin/quicktui-server"
run_startup
assert_file_contains "startup calls herdr session list" "$CASE/herdr.log" "session list --json"
cleanup_case

# --- remote installer is never invoked ---
if awk '
	$0 ~ /^[ \t]*#/ { next }
	$0 ~ /^[ \t]*(curl|wget)[ \t].*q\.sh/ { bad = 1 }
	END { exit bad ? 1 : 0 }
' "$ROOT/scripts"/*.sh >/dev/null 2>&1; then
	pass "scripts do not download q.sh"
else
	fail "scripts do not download q.sh"
fi

if [ "$FAILED" -ne 0 ]; then
	printf '%s\n' "$FAILED failed / $RAN checks" >&2
	exit 1
fi
printf '%s\n' "all $RAN checks passed"
