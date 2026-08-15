#!/bin/sh
# Run startup/setup/qrcode against the current tree with isolated Herdr env.
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
HERDR_BIN=${HERDR_BIN:-}
if [ -z "$HERDR_BIN" ] || [ ! -x "$HERDR_BIN" ]; then
	printf '%s\n' 'usage: HERDR_BIN=/path/to/herdr sh tests/smoke-entries.sh' >&2
	exit 2
fi

WORKDIR=$(mktemp -d /tmp/qth-e-XXXXXX)
cleanup() {
	rm -rf "$WORKDIR"
}
trap cleanup EXIT INT TERM

export HOME=$WORKDIR/home
export PATH=/usr/bin:/bin
export HERDR_BIN_PATH=$HERDR_BIN
export HERDR_SOCKET_PATH=$WORKDIR/herdr.sock
export HERDR_PLUGIN_ID=ai.quicktui
export HERDR_PLUGIN_ROOT=$ROOT
export HERDR_PLUGIN_STATE_DIR=$WORKDIR/state
export HERDR_PLUGIN_CONFIG_DIR=$WORKDIR/config
mkdir -p "$HOME" "$HERDR_PLUGIN_STATE_DIR" "$HERDR_PLUGIN_CONFIG_DIR"

printf 'running entrypoints with %s\n' "$HERDR_BIN"
"$ROOT/scripts/startup.sh"
"$ROOT/scripts/setup.sh" </dev/null
set +e
"$ROOT/scripts/pair-qrcode.sh" </dev/null
qr_rc=$?
set -e
printf 'qr_rc=%s\n' "$qr_rc"
cat "$HERDR_PLUGIN_STATE_DIR/discovery.env"
# missing or not_running are both valid on a machine without a ready server
case $qr_rc in
0 | 4) ;;
*)
	printf '%s\n' "unexpected pair-qrcode exit: $qr_rc" >&2
	exit 1
	;;
esac
printf 'entrypoint smoke passed\n'
