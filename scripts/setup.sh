#!/bin/sh
# Interactive QuickTUI setup / pairing entry. Does not start a daemon.
set -eu

QT_SCRIPTS_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
# shellcheck disable=SC1091
. "$QT_SCRIPTS_DIR/lib.sh"

qt_require_herdr_runtime || exit $?
qt_discover
qt_finish_discovery

case $QT_STATUS in
missing)
	qt_print_install_guide
	exit "$QT_OK"
	;;
invalid_bin | invalid_config)
	qt_err "cannot open pairing because discovery status is $QT_STATUS"
	exit "$QT_INVALID"
	;;
not_running | unknown)
	qt_print_start_guide
	exit "$QT_NOT_READY"
	;;
ready)
	if ! qt_stdin_is_tty; then
		qt_print_headless_ready_guide "$QT_SERVER_BIN" "$QT_CONFIG_PATH"
		exit "$QT_OK"
	fi
	qt_run_pairing "$QT_SERVER_BIN" welcome "$QT_CONFIG_PATH"
	exit "$QT_CLI_FAILED"
	;;
*)
	qt_err "unexpected discovery status"
	exit "$QT_CLI_FAILED"
	;;
esac
