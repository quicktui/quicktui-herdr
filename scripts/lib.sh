# Shared POSIX helpers for quicktui-herdr. Source only. Do not execute.
# All process launches use argv. Do not evaluate strings as a shell.

QT_OK=0
QT_USAGE=2
QT_INVALID=3
QT_NOT_READY=4
QT_CLI_FAILED=5

QT_DEFAULT_LISTEN=0.0.0.0:8022
QT_CAPABILITY_PATH=/.well-known/quicktui-server-capability
QT_INSTALL_GLOBAL='curl -fsSL https://quicktui.ai/q.sh | sh'
QT_INSTALL_CN='curl -fsSL https://dl.quicktui.cn/q.sh | sh'

qt_log() {
	printf 'quicktui-herdr: %s\n' "$1"
}

qt_err() {
	printf 'quicktui-herdr: %s\n' "$1" >&2
}

qt_awk_check() {
	# $1 env value, $2 awk program using ENVIRON["QT_CHECK"]
	QT_CHECK=$1 awk "$2"
}

qt_has_control_chars() {
	# POSIX character class so GNU awk and BSD awk agree.
	qt_awk_check "$1" 'BEGIN {
		v = ENVIRON["QT_CHECK"]
		if (v ~ /[[:cntrl:]]/) exit 1
		exit 0
	}'
}

qt_is_safe_text() {
	_qt_value=$1
	_qt_max=$2
	if [ -z "$_qt_value" ]; then
		return 1
	fi
	if [ "${#_qt_value}" -gt "$_qt_max" ]; then
		return 1
	fi
	qt_has_control_chars "$_qt_value"
}

qt_is_safe_path() {
	qt_is_safe_text "$1" 4096
}

qt_is_abs_path() {
	case $1 in
	/*) return 0 ;;
	*) return 1 ;;
	esac
}

qt_is_executable_file() {
	[ -f "$1" ] && [ -x "$1" ]
}

qt_is_safe_plugin_id() {
	qt_awk_check "$1" 'BEGIN {
		v = ENVIRON["QT_CHECK"]
		if (v ~ /^[A-Za-z0-9._:-]+$/ && length(v) <= 120) exit 0
		exit 1
	}'
}

qt_is_digits() {
	qt_awk_check "$1" 'BEGIN {
		v = ENVIRON["QT_CHECK"]
		if (v ~ /^[0-9]+$/) exit 0
		exit 1
	}'
}

qt_is_safe_host() {
	qt_awk_check "$1" 'BEGIN {
		v = ENVIRON["QT_CHECK"]
		if (length(v) == 0 || length(v) > 253) exit 1
		if (v == "localhost") exit 0
		if (v ~ /^[0-9]+(\.[0-9]+){3}$/) exit 0
		if (v ~ /^[0-9A-Fa-f:]+$/) exit 0
		if (v ~ /^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])$/) exit 0
		exit 1
	}'
}

qt_is_numeric_ip() {
	# IPv4 needs four 0-255 octets. IPv6 must contain a colon.
	# Hex labels such as deadbeef are hostnames, not addresses.
	qt_awk_check "$1" 'BEGIN {
		v = ENVIRON["QT_CHECK"]
		if (v ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/) {
			n = split(v, oct, ".")
			if (n != 4) exit 1
			for (i = 1; i <= 4; i++) {
				if (length(oct[i]) > 3 || oct[i] + 0 > 255) exit 1
			}
			exit 0
		}
		if (index(v, ":") && v ~ /^[0-9A-Fa-f:]+$/) exit 0
		exit 1
	}'
}

qt_shell_quote() {
	# POSIX single-quote encoding for copy/paste commands.
	QT_CHECK=$1 awk 'BEGIN {
		v = ENVIRON["QT_CHECK"]
		gsub(/\047/, "\047\\\047\047", v)
		printf "\047%s\047", v
	}'
}

qt_env_or_empty() {
	# Allowlisted env lookup. Do not take untrusted names.
	case $1 in
	HERDR_BIN_PATH) printf '%s' "${HERDR_BIN_PATH-}" ;;
	HERDR_PLUGIN_ID) printf '%s' "${HERDR_PLUGIN_ID-}" ;;
	HERDR_PLUGIN_ROOT) printf '%s' "${HERDR_PLUGIN_ROOT-}" ;;
	HERDR_SOCKET_PATH) printf '%s' "${HERDR_SOCKET_PATH-}" ;;
	HERDR_PLUGIN_STATE_DIR) printf '%s' "${HERDR_PLUGIN_STATE_DIR-}" ;;
	HERDR_PLUGIN_CONFIG_DIR) printf '%s' "${HERDR_PLUGIN_CONFIG_DIR-}" ;;
	QUICKTUI_SERVER_BIN) printf '%s' "${QUICKTUI_SERVER_BIN-}" ;;
	QUICKTUI_CONFIG) printf '%s' "${QUICKTUI_CONFIG-}" ;;
	HOME) printf '%s' "${HOME-}" ;;
	*) return 1 ;;
	esac
}

qt_require_herdr_runtime() {
	QT_BIN=$(qt_env_or_empty HERDR_BIN_PATH)
	if [ -z "$QT_BIN" ]; then
		qt_err 'HERDR_BIN_PATH is required'
		return "$QT_USAGE"
	fi
	if ! qt_is_safe_path "$QT_BIN" || ! qt_is_abs_path "$QT_BIN"; then
		qt_err 'HERDR_BIN_PATH must be an absolute path without control characters'
		return "$QT_USAGE"
	fi
	if ! qt_is_executable_file "$QT_BIN"; then
		qt_err 'HERDR_BIN_PATH is not an executable file'
		return "$QT_USAGE"
	fi

	QT_ID=$(qt_env_or_empty HERDR_PLUGIN_ID)
	if [ -z "$QT_ID" ]; then
		qt_err 'HERDR_PLUGIN_ID is required'
		return "$QT_USAGE"
	fi
	if ! qt_is_safe_plugin_id "$QT_ID"; then
		qt_err 'HERDR_PLUGIN_ID is invalid'
		return "$QT_USAGE"
	fi

	QT_ROOT=$(qt_env_or_empty HERDR_PLUGIN_ROOT)
	if [ -n "$QT_ROOT" ]; then
		if ! qt_is_safe_path "$QT_ROOT" || ! qt_is_abs_path "$QT_ROOT"; then
			qt_err 'HERDR_PLUGIN_ROOT must be an absolute path without control characters'
			return "$QT_USAGE"
		fi
	fi

	QT_SOCKET=$(qt_env_or_empty HERDR_SOCKET_PATH)
	if [ -n "$QT_SOCKET" ]; then
		if ! qt_is_safe_path "$QT_SOCKET"; then
			qt_err 'HERDR_SOCKET_PATH contains control characters'
			return "$QT_USAGE"
		fi
	fi

	QT_STATE_DIR=$(qt_env_or_empty HERDR_PLUGIN_STATE_DIR)
	if [ -n "$QT_STATE_DIR" ]; then
		if ! qt_is_safe_path "$QT_STATE_DIR" || ! qt_is_abs_path "$QT_STATE_DIR"; then
			qt_err 'HERDR_PLUGIN_STATE_DIR must be an absolute path without control characters'
			return "$QT_USAGE"
		fi
	fi

	QT_CONFIG_DIR=$(qt_env_or_empty HERDR_PLUGIN_CONFIG_DIR)
	if [ -n "$QT_CONFIG_DIR" ]; then
		if ! qt_is_safe_path "$QT_CONFIG_DIR" || ! qt_is_abs_path "$QT_CONFIG_DIR"; then
			qt_err 'HERDR_PLUGIN_CONFIG_DIR must be an absolute path without control characters'
			return "$QT_USAGE"
		fi
	fi

	# Context JSON and workspace labels are untrusted. Never interpolate them.
	return 0
}

qt_find_cmd() {
	_qt_resolved=$(command -v "$1" 2>/dev/null) || return 1
	if ! qt_is_safe_path "$_qt_resolved" || ! qt_is_abs_path "$_qt_resolved"; then
		return 1
	fi
	if ! qt_is_executable_file "$_qt_resolved"; then
		return 1
	fi
	printf '%s\n' "$_qt_resolved"
}

qt_home_dir() {
	_qt_home=$(qt_env_or_empty HOME)
	if [ -z "$_qt_home" ]; then
		return 1
	fi
	if ! qt_is_safe_path "$_qt_home" || ! qt_is_abs_path "$_qt_home"; then
		return 1
	fi
	printf '%s\n' "$_qt_home"
}

qt_default_config_path() {
	_qt_home=$(qt_home_dir) || return 1
	printf '%s\n' "$_qt_home/.config/quicktui-server-v2/config.toml"
}

qt_find_server_bin() {
	_qt_override=$(qt_env_or_empty QUICKTUI_SERVER_BIN)
	if [ -n "$_qt_override" ]; then
		if ! qt_is_safe_path "$_qt_override" || ! qt_is_abs_path "$_qt_override"; then
			qt_err 'QUICKTUI_SERVER_BIN must be an absolute path without control characters'
			return "$QT_INVALID"
		fi
		if ! qt_is_executable_file "$_qt_override"; then
			qt_err 'QUICKTUI_SERVER_BIN is not an executable file'
			return "$QT_INVALID"
		fi
		printf '%s\n' "$_qt_override"
		return 0
	fi
	if _qt_from_path=$(qt_find_cmd quicktui-server); then
		printf '%s\n' "$_qt_from_path"
		return 0
	fi
	_qt_home=$(qt_home_dir || true)
	if [ -n "$_qt_home" ] && qt_is_executable_file "$_qt_home/.local/bin/quicktui-server"; then
		printf '%s\n' "$_qt_home/.local/bin/quicktui-server"
		return 0
	fi
	if qt_is_executable_file /usr/local/bin/quicktui-server; then
		printf '%s\n' /usr/local/bin/quicktui-server
		return 0
	fi
	return 1
}

qt_resolve_config_path() {
	_qt_override=$(qt_env_or_empty QUICKTUI_CONFIG)
	if [ -n "$_qt_override" ]; then
		if ! qt_is_safe_path "$_qt_override" || ! qt_is_abs_path "$_qt_override"; then
			qt_err 'QUICKTUI_CONFIG must be an absolute path without control characters'
			return "$QT_INVALID"
		fi
		printf '%s\n' "$_qt_override"
		return 0
	fi
	qt_default_config_path
}

qt_read_toml_addr() {
	# Read a simple addr = "host:port" assignment. No interpolation or includes.
	_qt_file=$1
	if [ ! -f "$_qt_file" ] || [ ! -r "$_qt_file" ]; then
		return 1
	fi
	awk '
		BEGIN { status = 1 }
		{
			line = $0
			sub(/[ \t]*#.*$/, "", line)
			if (line !~ /^[ \t]*addr[ \t]*=[ \t]*/) next
			sub(/^[ \t]*addr[ \t]*=[ \t]*/, "", line)
			if (index(line, "\"\"\"") == 1) { status = 2; exit }
			if (line ~ /^"/) {
				if (line !~ /^"[^"]*"[ \t]*$/) { status = 2; exit }
				gsub(/^"/, "", line)
				gsub(/"[ \t]*$/, "", line)
			} else if (line ~ /^'\''/) {
				if (line !~ /^'\''[^'\'']*'\''[ \t]*$/) { status = 2; exit }
				gsub(/^'\''/, "", line)
				gsub(/'\''[ \t]*$/, "", line)
			} else {
				gsub(/[ \t]*$/, "", line)
			}
			if (line == "" || line ~ /[[:cntrl:]]/) { status = 2; exit }
			print line
			status = 0
			exit
		}
		END { exit status }
	' "$_qt_file"
}

qt_strip_listen_scheme() {
	# Official config accepts optional http(s)://. Probe stays plaintext HTTP.
	_qt_raw=$1
	case $_qt_raw in
	[hH][tT][tT][pP][sS]://* | [hH][tT][tT][pP]://*)
		printf '%s\n' "${_qt_raw#*://}"
		;;
	*)
		printf '%s\n' "$_qt_raw"
		;;
	esac
}

qt_split_listen_addr() {
	_qt_addr=$(qt_strip_listen_scheme "$1")
	if ! qt_is_safe_text "$_qt_addr" 253; then
		return 1
	fi
	QT_PROBE_HOST=
	QT_PROBE_PORT=
	case $_qt_addr in
	\[*\]:*)
		QT_PROBE_PORT=${_qt_addr##*\]:}
		QT_PROBE_HOST=${_qt_addr#\[}
		QT_PROBE_HOST=${QT_PROBE_HOST%\]:*}
		;;
	*:*)
		QT_PROBE_PORT=${_qt_addr##*:}
		QT_PROBE_HOST=${_qt_addr%:*}
		;;
	*)
		return 1
		;;
	esac
	if ! qt_is_digits "$QT_PROBE_PORT"; then
		return 1
	fi
	if [ "$QT_PROBE_PORT" -lt 1 ] || [ "$QT_PROBE_PORT" -gt 65535 ]; then
		return 1
	fi
	if [ -z "$QT_PROBE_HOST" ] || [ "$QT_PROBE_HOST" = "0.0.0.0" ] || [ "$QT_PROBE_HOST" = "localhost" ]; then
		QT_PROBE_HOST=127.0.0.1
	fi
	if [ "$QT_PROBE_HOST" = "::" ] || [ "$QT_PROBE_HOST" = "::0" ]; then
		QT_PROBE_HOST=::1
	fi
	if ! qt_is_safe_host "$QT_PROBE_HOST"; then
		return 1
	fi
	return 0
}

qt_http_probe_url() {
	_qt_host=$1
	_qt_port=$2
	case $_qt_host in
	*:*)
		printf 'http://[%s]:%s%s' "$_qt_host" "$_qt_port" "$QT_CAPABILITY_PATH"
		;;
	*)
		printf 'http://%s:%s%s' "$_qt_host" "$_qt_port" "$QT_CAPABILITY_PATH"
		;;
	esac
}

qt_probe_capability() {
	_qt_host=$1
	_qt_port=$2
	_qt_url=$(qt_http_probe_url "$_qt_host" "$_qt_port")
	_qt_curl=$(qt_find_cmd curl || true)
	if [ -n "$_qt_curl" ]; then
		"$_qt_curl" \
			--silent \
			--show-error \
			--fail \
			--output /dev/null \
			--max-time 2 \
			--connect-timeout 1 \
			--max-redirs 0 \
			--proto '=http' \
			--noproxy '*' \
			--url "$_qt_url" >/dev/null 2>&1
		return $?
	fi
	_qt_python=$(qt_find_cmd python3 || true)
	if [ -n "$_qt_python" ]; then
		if ! qt_is_numeric_ip "$_qt_host"; then
			# Avoid unbounded DNS in the curl-less fallback.
			return 2
		fi
		QT_PROBE_HOST=$_qt_host QT_PROBE_PORT=$_qt_port "$_qt_python" - <<'PY'
import ipaddress
import os
import socket
import sys

host = os.environ.get("QT_PROBE_HOST", "")
port_raw = os.environ.get("QT_PROBE_PORT", "")
if not host or not port_raw.isdigit():
    sys.exit(1)
port = int(port_raw)
if port < 1 or port > 65535:
    sys.exit(1)
try:
    ip = ipaddress.ip_address(host)
except ValueError:
    sys.exit(2)
family = socket.AF_INET6 if ip.version == 6 else socket.AF_INET
request = (
    b"GET /.well-known/quicktui-server-capability HTTP/1.1\r\n"
    + "Host: {}:{}\r\n".format(host, port).encode("ascii", "strict")
    + b"Connection: close\r\n\r\n"
)
try:
    sock = socket.socket(family, socket.SOCK_STREAM)
    sock.settimeout(2)
    sock.connect((host, port))
except OSError:
    sys.exit(1)
try:
    sock.sendall(request)
    data = sock.recv(64)
finally:
    sock.close()
if data.startswith(b"HTTP/1.1 200") or data.startswith(b"HTTP/1.0 200"):
    sys.exit(0)
sys.exit(1)
PY
		return $?
	fi
	return 2
}

qt_herdr_session_probe() {
	# Use the official CLI plus injected HERDR_SOCKET_PATH. Do not invent sockets.
	QT_HERDR_CLI=unavailable
	if [ -z "${HERDR_BIN_PATH-}" ]; then
		return 1
	fi
	_qt_python=$(qt_find_cmd python3 || true)
	if [ -n "$_qt_python" ]; then
		if HERDR_BIN_PATH=$HERDR_BIN_PATH "$_qt_python" - <<'PY'
import os
import subprocess
import sys

cmd = os.environ.get("HERDR_BIN_PATH", "")
if not cmd:
    sys.exit(1)
try:
    result = subprocess.run(
        [cmd, "session", "list", "--json"],
        timeout=2,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
    )
except (OSError, subprocess.TimeoutExpired):
    sys.exit(1)
sys.exit(0 if result.returncode == 0 else 1)
PY
		then
			QT_HERDR_CLI=ok
			return 0
		fi
		return 1
	fi
	# Session listing is best-effort. Without a bounded runner, skip it.
	return 1
}

qt_now_utc() {
	date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || printf 'unknown\n'
}

qt_write_state() {
	_qt_status=$1
	_qt_server_present=$2
	_qt_config_present=$3
	_qt_herdr_cli=$4
	case $_qt_status in
	missing | not_running | ready | unknown | invalid_config | invalid_bin) ;;
	*)
		_qt_status=unknown
		;;
	esac
	_qt_dir=$(qt_env_or_empty HERDR_PLUGIN_STATE_DIR)
	if [ -z "$_qt_dir" ]; then
		return 0
	fi
	if [ ! -d "$_qt_dir" ]; then
		umask 077
		mkdir -p "$_qt_dir" || return 0
	fi
	_qt_tmp=$_qt_dir/discovery.env.tmp.$$
	_qt_dest=$_qt_dir/discovery.env
	umask 077
	# Local status only. No paths, codes, tokens, or identity.
	if printf 'status=%s\nserver_present=%s\nconfig_present=%s\nherdr_cli=%s\nprobed_at=%s\n' \
		"$_qt_status" "$_qt_server_present" "$_qt_config_present" "$_qt_herdr_cli" "$(qt_now_utc)" \
		>"$_qt_tmp"; then
		mv "$_qt_tmp" "$_qt_dest" || rm -f "$_qt_tmp"
	else
		rm -f "$_qt_tmp"
	fi
}

qt_print_install_guide() {
	cat <<EOF
QuickTUI Server is not installed on this machine.

This plugin is only a Herdr entry point. It does not download or run the
installer, and it does not start a second server.

Official install (run it yourself if you want QuickTUI):

  Global: $QT_INSTALL_GLOBAL
  China:  $QT_INSTALL_CN

Docs: https://quicktui.ai/install/
EOF
}

qt_print_start_guide() {
	cat <<EOF
QuickTUI Server is installed but not ready for pairing.

Start the existing service, then retry QuickTUI Setup. This plugin will not
launch an unsupervised daemon.

  macOS: launchctl print gui/\$(id -u)/ai.quicktui
  Linux: systemctl --user status quicktui

If you use a custom config, start the server with that file and set
QUICKTUI_CONFIG to the same path before invoking this plugin.
EOF
}

qt_print_headless_ready_guide() {
	_qt_bin=$1
	_qt_config=$2
	_qt_bin_q=$(qt_shell_quote "$_qt_bin")
	printf '%s\n' 'QuickTUI Server is ready. stdin is not a TTY, so this plugin will not issue a pairing code.'
	printf '%s\n' 'Run one of these commands in an interactive terminal:'
	printf '\n'
	if [ -n "$_qt_config" ]; then
		_qt_config_q=$(qt_shell_quote "$_qt_config")
		printf '  %s pairing welcome --config %s\n' "$_qt_bin_q" "$_qt_config_q"
		printf '  %s pairing qrcode --config %s\n' "$_qt_bin_q" "$_qt_config_q"
	else
		printf '  %s pairing welcome\n' "$_qt_bin_q"
		printf '  %s pairing qrcode\n' "$_qt_bin_q"
	fi
}

qt_discover() {
	# Sets QT_STATUS, QT_SERVER_BIN, QT_CONFIG_PATH, QT_SERVER_PRESENT,
	# QT_CONFIG_PRESENT, QT_HERDR_CLI. Safe to re-run.
	QT_STATUS=missing
	QT_SERVER_BIN=
	QT_CONFIG_PATH=
	QT_SERVER_PRESENT=0
	QT_CONFIG_PRESENT=0
	QT_HERDR_CLI=unavailable

	qt_herdr_session_probe || true

	_qt_find_rc=0
	QT_SERVER_BIN=$(qt_find_server_bin) || _qt_find_rc=$?
	if [ "$_qt_find_rc" -ne 0 ]; then
		if [ "$_qt_find_rc" -eq "$QT_INVALID" ]; then
			QT_STATUS=invalid_bin
			return 0
		fi
		QT_STATUS=missing
		_qt_cfg_rc=0
		QT_CONFIG_PATH=$(qt_resolve_config_path) || _qt_cfg_rc=$?
		if [ "$_qt_cfg_rc" -ne 0 ]; then
			QT_CONFIG_PATH=
		elif [ -f "$QT_CONFIG_PATH" ]; then
			QT_CONFIG_PRESENT=1
		fi
		return 0
	fi
	QT_SERVER_PRESENT=1

	_qt_cfg_rc=0
	QT_CONFIG_PATH=$(qt_resolve_config_path) || _qt_cfg_rc=$?
	if [ "$_qt_cfg_rc" -ne 0 ]; then
		if [ "$_qt_cfg_rc" -eq "$QT_INVALID" ]; then
			QT_STATUS=invalid_config
			return 0
		fi
		QT_CONFIG_PATH=
	fi

	_qt_listen=$QT_DEFAULT_LISTEN
	if [ -n "$QT_CONFIG_PATH" ] && [ -f "$QT_CONFIG_PATH" ]; then
		QT_CONFIG_PRESENT=1
		_qt_addr=
		_qt_addr_rc=0
		_qt_addr=$(qt_read_toml_addr "$QT_CONFIG_PATH") || _qt_addr_rc=$?
		if [ "$_qt_addr_rc" -eq 2 ]; then
			QT_STATUS=invalid_config
			return 0
		fi
		if [ "$_qt_addr_rc" -eq 0 ]; then
			_qt_listen=$_qt_addr
		fi
	fi

	if ! qt_split_listen_addr "$_qt_listen"; then
		QT_STATUS=invalid_config
		return 0
	fi

	_qt_probe_rc=0
	qt_probe_capability "$QT_PROBE_HOST" "$QT_PROBE_PORT" || _qt_probe_rc=$?
	if [ "$_qt_probe_rc" -eq 0 ]; then
		QT_STATUS=ready
		return 0
	fi
	if [ "$_qt_probe_rc" -eq 2 ]; then
		QT_STATUS=unknown
		return 0
	fi
	QT_STATUS=not_running
	return 0
}

qt_finish_discovery() {
	qt_write_state "$QT_STATUS" "$QT_SERVER_PRESENT" "$QT_CONFIG_PRESENT" "$QT_HERDR_CLI"
	qt_log "status=$QT_STATUS"
}

qt_exec_server() {
	_qt_bin=$1
	shift
	exec "$_qt_bin" "$@"
}

qt_stdin_is_tty() {
	[ -t 0 ]
}

qt_run_pairing() {
	# $1 server bin, $2 subcommand (welcome|qrcode), $3 optional config path
	_qt_bin=$1
	_qt_sub=$2
	_qt_config=$3
	_qt_override=$(qt_env_or_empty QUICKTUI_CONFIG)
	if [ -n "$_qt_override" ] || { [ -n "$_qt_config" ] && [ -f "$_qt_config" ]; }; then
		qt_exec_server "$_qt_bin" pairing "$_qt_sub" --config "$_qt_config"
	else
		qt_exec_server "$_qt_bin" pairing "$_qt_sub"
	fi
}

qt_open_plugin_pane() {
	# Actions run without a TTY. Open the declared pane so pairing is visible.
	_qt_entry=$1
	case $_qt_entry in
	setup | pair-qrcode) ;;
	*)
		qt_err 'unknown pane entrypoint'
		return "$QT_USAGE"
		;;
	esac
	_qt_plugin=$(qt_env_or_empty HERDR_PLUGIN_ID)
	if [ -z "$_qt_plugin" ]; then
		qt_err 'HERDR_PLUGIN_ID is required'
		return "$QT_USAGE"
	fi
	qt_exec_server "$HERDR_BIN_PATH" plugin pane open --plugin "$_qt_plugin" --entrypoint "$_qt_entry"
}
