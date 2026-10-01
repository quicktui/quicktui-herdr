#!/bin/sh
# Interactive install entry. Runs the official installer only after the user
# confirms on a TTY. The plugin itself starts no daemon.
set -eu

QT_SCRIPTS_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
# shellcheck disable=SC1091
. "$QT_SCRIPTS_DIR/lib.sh"
# shellcheck disable=SC1091
. "$QT_SCRIPTS_DIR/lib-install.sh"

qt_require_herdr_runtime || exit $?
qt_discover
qt_finish_discovery

case $QT_STATUS in
missing)
	_qt_rc=0
	qt_run_install_flow || _qt_rc=$?
	exit "$_qt_rc"
	;;
invalid_bin | invalid_config)
	qt_err "cannot install because discovery status is $QT_STATUS"
	exit "$QT_INVALID"
	;;
*)
	qt_log 'QuickTUI Server is already installed. Run QuickTUI Setup to pair a device.'
	exit "$QT_OK"
	;;
esac
