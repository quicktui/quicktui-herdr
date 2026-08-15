#!/bin/sh
# Official pairing QR entry. Issues a code only by execing quicktui-server.
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
	qt_err 'QuickTUI Server is not ready; pairing code was not issued'
	qt_print_start_guide
	exit "$QT_NOT_READY"
	;;
ready)
	qt_run_pairing "$QT_SERVER_BIN" qrcode "$QT_CONFIG_PATH"
	exit "$QT_CLI_FAILED"
	;;
*)
	qt_err "unexpected discovery status"
	exit "$QT_CLI_FAILED"
	;;
esac
