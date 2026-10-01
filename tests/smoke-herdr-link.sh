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
# Text output in current Herdr lists only the plugin. Read the linked entry
# points through --json and print them as "action <id>" / "pane <id>" lines.
"$HERDR_BIN" plugin list --plugin ai.quicktui --json >"$WORKDIR/list.json"
python3 - "$WORKDIR/list.json" >"$WORKDIR/entries.txt" <<'PY'
import json
import sys


def find_plugin(node):
    if isinstance(node, dict):
        if node.get("plugin_id") == "ai.quicktui" and "actions" in node:
            return node
        values = node.values()
    elif isinstance(node, list):
        values = node
    else:
        return None
    for value in values:
        found = find_plugin(value)
        if found:
            return found
    return None


with open(sys.argv[1]) as fh:
    plugin = find_plugin(json.load(fh))
if plugin is None:
    sys.exit("ai.quicktui not found in plugin list --json")
for action in plugin["actions"]:
    print("action", action["id"])
for pane in plugin["panes"]:
    print("pane", pane["id"])
PY
cat "$WORKDIR/entries.txt"
for entry in 'action install' 'pane install' 'action setup' 'pane setup' 'action pair-qrcode' 'pane pair-qrcode' \
	'action install-windows' 'pane install-windows' 'action setup-windows' 'pane setup-windows' \
	'action pair-qrcode-windows' 'pane pair-qrcode-windows'; do
	if ! grep -Fx -e "$entry" "$WORKDIR/entries.txt" >/dev/null; then
		printf 'missing linked entry: %s\n' "$entry" >&2
		exit 1
	fi
done
# Unlink talks to a running server in v0.8.0 and has no offline fallback.
# Isolated HOME is deleted on exit, so a leftover registry cannot escape.
if ! "$HERDR_BIN" plugin unlink ai.quicktui >/dev/null 2>&1; then
	printf 'unlink skipped: no herdr server in the isolated HOME (expected)\n'
fi
printf 'herdr plugin link smoke passed\n'
