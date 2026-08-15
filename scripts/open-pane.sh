#!/bin/sh
# Action entry: open a plugin pane. Herdr actions have no TTY.
set -eu

QT_SCRIPTS_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
# shellcheck disable=SC1091
. "$QT_SCRIPTS_DIR/lib.sh"

qt_require_herdr_runtime || exit $?
if [ "${1-}" = "" ]; then
	qt_err 'pane entrypoint is required'
	exit "$QT_USAGE"
fi
qt_open_plugin_pane "$1"
exit "$QT_CLI_FAILED"
