# Fake official installer payload. Runs as: sh <downloaded temp file>.
set -eu
log=${FAKE_INSTALLER_LOG:-/dev/null}
printf 'argv0=%s argc=%s\n' "$0" "$#" >>"$log"
# Mode of the directory holding this payload, e.g. drwx------.
printf 'dirmode=%s\n' "$(ls -ld "$(dirname "$0")" | cut -c1-10)" >>"$log"
if [ -t 0 ]; then
	printf 'stdin=tty\n' >>"$log"
fi
if [ -n "${FAKE_INSTALLER_SERVER_SRC-}" ]; then
	mkdir -p "$HOME/.local/bin"
	cp "$FAKE_INSTALLER_SERVER_SRC" "$HOME/.local/bin/quicktui-server"
	chmod 0755 "$HOME/.local/bin/quicktui-server"
fi
exit "${FAKE_INSTALLER_EXIT:-0}"
