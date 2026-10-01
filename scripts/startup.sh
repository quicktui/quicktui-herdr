#!/bin/sh
# One-shot Herdr startup hook. Discover QuickTUI, show the first-run toast once,
# and exit. Do not start a daemon.
set -eu

QT_SCRIPTS_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
# shellcheck disable=SC1091
. "$QT_SCRIPTS_DIR/lib.sh"
# shellcheck disable=SC1091
. "$QT_SCRIPTS_DIR/lib-onboarding.sh"

qt_require_herdr_runtime || exit $?
qt_discover
qt_finish_discovery
qt_maybe_first_run_toast
exit "$QT_OK"
