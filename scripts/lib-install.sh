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

qt_install_tmp_dir() {
	_qt_tmp_dir=${TMPDIR-}
	if [ -n "$_qt_tmp_dir" ] && qt_is_safe_path "$_qt_tmp_dir" && qt_is_abs_path "$_qt_tmp_dir" && [ -d "$_qt_tmp_dir" ]; then
		printf '%s\n' "${_qt_tmp_dir%/}"
		return 0
	fi
	printf '%s\n' /tmp
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
	_qt_dir=$(qt_install_tmp_dir)
	# A private 0700 directory: other users cannot replace or symlink the
	# payload between download and execution, even when TMPDIR is shared and
	# not sticky.
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
