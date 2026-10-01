# First-run Herdr toast. Source after lib.sh. Do not execute.
# The marker file name and format are shared with the Windows entry points:
#   $HERDR_PLUGIN_STATE_DIR/onboarding.env
#   toast_shown_at=<UTC ISO-8601>
# It holds only that line. No paths, codes, tokens, or identity.

QT_ONBOARDING_MARKER=onboarding.env
QT_TOAST_TIMEOUT_SECONDS=3

qt_run_bounded_quiet() {
	# $1 timeout seconds, then argv. Needs python3 for a bounded child; without
	# it, skip instead of risking an unbounded startup hook.
	_qt_timeout=$1
	shift
	_qt_python=$(qt_find_cmd python3 || true)
	if [ -z "$_qt_python" ]; then
		return 1
	fi
	"$_qt_python" - "$_qt_timeout" "$@" <<'PY'
import os
import signal
import subprocess
import sys

timeout = float(sys.argv[1])
argv = sys.argv[2:]
if not argv:
    sys.exit(1)
try:
    # Own process group so a timeout also stops grandchildren.
    child = subprocess.Popen(
        argv,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
except OSError:
    sys.exit(1)
try:
    rc = child.wait(timeout=timeout)
except subprocess.TimeoutExpired:
    try:
        os.killpg(child.pid, signal.SIGKILL)
    except OSError:
        pass
    child.wait()
    sys.exit(1)
sys.exit(0 if rc == 0 else 1)
PY
}

qt_write_onboarding_marker() {
	_qt_marker_dir=$1
	_qt_marker_tmp=$_qt_marker_dir/$QT_ONBOARDING_MARKER.tmp.$$
	umask 077
	if printf 'toast_shown_at=%s\n' "$(qt_now_utc)" >"$_qt_marker_tmp"; then
		mv "$_qt_marker_tmp" "$_qt_marker_dir/$QT_ONBOARDING_MARKER" || rm -f "$_qt_marker_tmp"
	else
		rm -f "$_qt_marker_tmp"
	fi
}

qt_maybe_first_run_toast() {
	# Show one toast per plugin state dir. Mark only after Herdr accepted it.
	# Never changes the caller's exit status.
	_qt_marker_dir=$(qt_env_or_empty HERDR_PLUGIN_STATE_DIR)
	if [ -z "$_qt_marker_dir" ]; then
		return 0
	fi
	if [ -e "$_qt_marker_dir/$QT_ONBOARDING_MARKER" ] || [ -L "$_qt_marker_dir/$QT_ONBOARDING_MARKER" ]; then
		return 0
	fi
	if [ ! -d "$_qt_marker_dir" ]; then
		umask 077
		mkdir -p "$_qt_marker_dir" || return 0
	fi
	case $QT_STATUS in
	missing)
		_qt_toast_body='Use your terminal from iPhone or Android. Run the QuickTUI Install action to set it up.'
		;;
	ready)
		_qt_toast_body='QuickTUI is ready. Run the QuickTUI Pairing QR action to pair your phone.'
		;;
	*)
		_qt_toast_body='Run the QuickTUI Setup action to finish setting up QuickTUI.'
		;;
	esac
	if qt_run_bounded_quiet "$QT_TOAST_TIMEOUT_SECONDS" \
		"$HERDR_BIN_PATH" notification show QuickTUI --body "$_qt_toast_body" --sound none; then
		qt_write_onboarding_marker "$_qt_marker_dir"
	fi
	return 0
}
