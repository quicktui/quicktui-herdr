# Confirmed official QuickTUI install flow. Source after lib.sh. Do not execute.
# The installer is downloaded into a private 0700 temp directory and run with
# argv (sh <file>). Never pipe it into a shell or evaluate it as a string.

QT_DOWNLOAD_FAILED=6
QT_INSTALL_FAILED=7

QT_INSTALL_URL=https://quicktui.ai/q.sh
QT_INSTALL_SHELL=/bin/sh
QT_READY_WAIT_SECONDS=10
QT_INSTALL_DIR=
QT_INSTALL_TMP=

qt_install_cleanup() {
	if [ -n "$QT_INSTALL_TMP" ]; then
		rm -f "$QT_INSTALL_TMP"
		QT_INSTALL_TMP=
	fi
	if [ -n "$QT_INSTALL_DIR" ]; then
		rmdir "$QT_INSTALL_DIR" 2>/dev/null || true
		QT_INSTALL_DIR=
	fi
}

qt_install_on_signal() {
	_qt_status=$1
	trap - HUP INT TERM EXIT
	qt_install_cleanup
	exit "$_qt_status"
}

qt_is_safe_dir_entry() {
	# $1 directory. Safe when no other user can rename or replace entries in
	# it: owned by the current user or root, and either not group/other
	# writable or sticky.
	_qt_ls=$(ls -ldn "$1" 2>/dev/null) || return 1
	QT_LS=$_qt_ls QT_UID=$(id -u) awk 'BEGIN {
		split(ENVIRON["QT_LS"], f, " ")
		mode = f[1]
		uid = f[3]
		if (substr(mode, 1, 1) != "d") exit 1
		if (uid != ENVIRON["QT_UID"] && uid != "0") exit 1
		group_w = substr(mode, 6, 1) == "w"
		other_w = substr(mode, 9, 1) == "w"
		sticky = substr(mode, 10, 1) ~ /[tT]/
		if ((group_w || other_w) && !sticky) exit 1
		exit 0
	}'
}

qt_is_safe_tmp_parent() {
	# $1 canonical absolute directory. Every component up to / must be safe,
	# or another user could rename a whole directory between download and run.
	_qt_walk=$1
	while :; do
		qt_is_safe_dir_entry "$_qt_walk" || return 1
		if [ "$_qt_walk" = / ]; then
			return 0
		fi
		_qt_walk=$(dirname -- "$_qt_walk")
	done
}

qt_canonical_dir() {
	(CDPATH= cd -P -- "$1" 2>/dev/null && pwd -P)
}

qt_install_tmp_dir() {
	# TMPDIR when it and its ancestors are safe, else /tmp under the same rule.
	for _qt_candidate in "${TMPDIR-}" /tmp; do
		if [ -z "$_qt_candidate" ] || ! qt_is_safe_path "$_qt_candidate" || ! qt_is_abs_path "$_qt_candidate"; then
			continue
		fi
		_qt_canonical=$(qt_canonical_dir "$_qt_candidate") || continue
		if qt_is_safe_path "$_qt_canonical" && qt_is_safe_tmp_parent "$_qt_canonical"; then
			printf '%s\n' "$_qt_canonical"
			return 0
		fi
	done
	return 1
}

qt_print_install_prompt() {
	cat <<EOF
QuickTUI Server is not installed on this machine.

QuickTUI Install downloads the official installer and runs it as your user:

  URL:  $QT_INSTALL_URL
  Runs: sh <downloaded file>
        (same installer as: $QT_INSTALL_GLOBAL)

The installer sets up quicktui-server and its user service. Nothing is
downloaded or run unless you type y or yes.

EOF
	printf 'Install QuickTUI now? [y/N] '
}

qt_confirm_install() {
	# Only an explicit y/yes typed on a TTY confirms. EOF and empty input decline.
	_qt_answer=
	if ! IFS= read -r _qt_answer; then
		_qt_answer=
	fi
	case $_qt_answer in
	[yY] | [yY][eE][sS]) return 0 ;;
	*) return 1 ;;
	esac
}

qt_download_installer() {
	# $1 private destination file. Fixed HTTPS URL; curl fails on HTTP errors.
	_qt_dest=$1
	_qt_curl=$(qt_find_cmd curl || true)
	if [ -z "$_qt_curl" ]; then
		qt_err 'curl is required to download the official installer'
		return 1
	fi
	# -q must come first: ignore ~/.curlrc so user curl options such as
	# --insecure or a proxy cannot weaken this download.
	"$_qt_curl" \
		-q \
		--fail \
		--silent \
		--show-error \
		--location \
		--proto '=https' \
		--proto-redir '=https' \
		--max-redirs 5 \
		--connect-timeout 10 \
		--max-time 300 \
		--output "$_qt_dest" \
		--url "$QT_INSTALL_URL" || return 1
	[ -s "$_qt_dest" ]
}

qt_wait_until_ready() {
	# Bounded wait: one discovery per second until ready or the deadline.
	_qt_deadline=$(($(date +%s) + QT_READY_WAIT_SECONDS))
	while :; do
		qt_discover
		if [ "$QT_STATUS" = ready ]; then
			return 0
		fi
		if [ "$(date +%s)" -ge "$_qt_deadline" ]; then
			return 1
		fi
		sleep 1
	done
}

qt_print_installed_not_found_guide() {
	cat <<EOF
The installer finished, but quicktui-server was not found in PATH,
~/.local/bin, or /usr/local/bin. Open a new terminal and retry QuickTUI Setup,
or set QUICKTUI_SERVER_BIN to the installed binary.
EOF
}

qt_run_install_flow() {
	# Confirm, download, run the official installer, then wait for readiness.
	# Returns an exit code, or execs pairing welcome when the server is ready.
	if ! qt_stdin_is_tty; then
		qt_print_install_guide
		return "$QT_OK"
	fi
	qt_print_install_prompt
	if ! qt_confirm_install; then
		printf '\n'
		qt_log 'install cancelled; nothing was downloaded'
		return "$QT_OK"
	fi

	# Arm cleanup before creating anything so an early signal leaves no file.
	trap qt_install_cleanup EXIT
	trap 'qt_install_on_signal 129' HUP
	trap 'qt_install_on_signal 130' INT
	trap 'qt_install_on_signal 143' TERM
	_qt_dir=$(qt_install_tmp_dir) || {
		trap - HUP INT TERM EXIT
		qt_err 'no safe temporary directory: TMPDIR and /tmp are writable by other users'
		return "$QT_DOWNLOAD_FAILED"
	}
	# A private 0700 directory under a parent chain no other user can rename
	# into: the payload cannot be replaced between download and execution.
	QT_INSTALL_DIR=$(mktemp -d "$_qt_dir/quicktui-install.XXXXXX") || {
		QT_INSTALL_DIR=
		qt_install_cleanup
		trap - HUP INT TERM EXIT
		qt_err 'cannot create a private temporary directory for the installer'
		return "$QT_DOWNLOAD_FAILED"
	}
	QT_INSTALL_TMP=$QT_INSTALL_DIR/q.sh

	qt_log "downloading $QT_INSTALL_URL"
	if ! qt_download_installer "$QT_INSTALL_TMP"; then
		qt_install_cleanup
		qt_err 'download failed; the installer was not run'
		return "$QT_DOWNLOAD_FAILED"
	fi

	qt_log 'running the official QuickTUI installer'
	_qt_install_rc=0
	"$QT_INSTALL_SHELL" "$QT_INSTALL_TMP" || _qt_install_rc=$?
	qt_install_cleanup
	trap - HUP INT TERM EXIT
	if [ "$_qt_install_rc" -ne 0 ]; then
		qt_err "installer exited with status $_qt_install_rc"
		return "$QT_INSTALL_FAILED"
	fi

	qt_log "installer finished; waiting up to ${QT_READY_WAIT_SECONDS}s for QuickTUI Server"
	if qt_wait_until_ready; then
		qt_finish_discovery
		qt_run_pairing "$QT_SERVER_BIN" welcome "$QT_CONFIG_PATH"
		return "$QT_CLI_FAILED"
	fi
	qt_finish_discovery
	case $QT_STATUS in
	missing)
		qt_print_installed_not_found_guide
		return "$QT_NOT_READY"
		;;
	invalid_bin | invalid_config)
		qt_err "cannot open pairing because discovery status is $QT_STATUS"
		return "$QT_INVALID"
		;;
	esac
	qt_print_start_guide
	return "$QT_NOT_READY"
}
