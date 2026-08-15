#!/bin/sh
# Isolated real-Herdr plugin link smoke. Never touches the user Herdr registry.
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
HERDR_BIN=${HERDR_BIN:-${HERDR_SMOKE_BIN:-}}
if [ -z "$HERDR_BIN" ]; then
	printf '%s\n' 'usage: HERDR_BIN=/path/to/herdr sh tests/smoke-herdr-link.sh' >&2
	exit 2
fi
if [ ! -x "$HERDR_BIN" ]; then
	printf '%s\n' "HERDR_BIN is not executable: $HERDR_BIN" >&2
	exit 2
fi

# Keep HOME short. macOS sockaddr_un.sun_path is 104 bytes; a long TMPDIR
# under the remote Apple cache would make herdr.sock unusable.
WORKDIR=$(mktemp -d /tmp/qth-XXXXXX)
cleanup() {
	if [ -n "${WORKDIR-}" ] && [ -d "$WORKDIR" ]; then
		rm -rf "$WORKDIR"
	fi
}
trap cleanup EXIT INT TERM

export HOME=$WORKDIR/home
export XDG_CONFIG_HOME=$HOME/.config
export XDG_STATE_HOME=$HOME/.local/state
export XDG_DATA_HOME=$HOME/.local/share
mkdir -p "$HOME" "$XDG_CONFIG_HOME" "$XDG_STATE_HOME" "$XDG_DATA_HOME"

printf 'linking %s with %s\n' "$ROOT" "$HERDR_BIN"
"$HERDR_BIN" plugin link "$ROOT"
"$HERDR_BIN" plugin list --plugin ai.quicktui
# Unlink talks to a running server in v0.8.0 and has no offline fallback.
# Isolated HOME is deleted on exit, so a leftover registry cannot escape.
if ! "$HERDR_BIN" plugin unlink ai.quicktui >/dev/null 2>&1; then
	printf 'unlink skipped: no herdr server in the isolated HOME (expected)\n'
fi
printf 'herdr plugin link smoke passed\n'
