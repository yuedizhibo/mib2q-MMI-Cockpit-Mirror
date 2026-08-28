#!/bin/sh
export PATH=/proc/boot:/bin:/usr/bin:/usr/sbin:/sbin:$PATH
if [ "$_" = "/bin/on" ]; then BASE="$0"; else BASE="$_"; fi
SCRIPTDIR=$( cd -P -- "$(dirname -- "$(command -v -- "$BASE")")" && pwd -P )
. "${SCRIPTDIR}/util_mountsd.sh"
[ -n "$VOLUME" ] || { echo "No SD-card found"; exit 1; }

STATE="${VOLUME}/Log/CarPlayMirror"
APP="${VOLUME}/Toolbox/carplay_mirror_test"
LOG="${STATE}/mirror_renderer.log"
STATUS="${STATE}/mirror_test_status.txt"
WORKERPID="${STATE}/worker.pid"

safe_kill_owned() {
    PID_PATH="$1"
    NEEDLE="$2"
    [ -f "$PID_PATH" ] || return 0
    PID_VALUE=$(cat "$PID_PATH" 2>/dev/null)
    case "$PID_VALUE" in *[!0-9]*|'') return 0 ;; esac
    if pidin ar 2>/dev/null | grep -E "^[[:space:]]*${PID_VALUE}[[:space:]].*${NEEDLE}" >/dev/null 2>&1; then
        kill "$PID_VALUE" 2>/dev/null
    fi
}

echo "===== B5-OFF: graceful persistent-mirror shutdown ====="
if [ -f "${APP}/DIRECT16_TEST" ] && [ ! -f "${APP}/ARMED" ]; then
    echo "B3 direct-source test is active. Use B3-OFF instead."
    exit 1
fi
if [ -f "${APP}/DIRECT_UPLOAD_TEST" ]; then
    echo "B3-OPT direct-upload test is active. Use B3-OFF instead."
    exit 1
fi

# ARMED is the single shutdown request. The worker owns renderer/capture
# teardown and waits for Java IDLE first; OFF must not kill the same processes
# on a competing fixed timer.
rm -f "${APP}/ARMED" "${APP}/PREVIEW58_TEST" \
      "${APP}/FPS10" "${APP}/FPS20" "${APP}/FPS30" \
      "${APP}/FPS40" "${APP}/FPS50" "${APP}/FPS60"
sync

N=0
while [ "$N" -lt 16 ]; do
    if grep -q '^state=DISABLED' "$STATUS" 2>/dev/null && \
       grep -q '^state=IDLE' "${STATE}/java_mirror_state.txt" 2>/dev/null; then
        break
    fi
    if [ ! -f "$WORKERPID" ] && grep -q '^state=IDLE' "${STATE}/java_mirror_state.txt" 2>/dev/null; then
        break
    fi
    sleep 1
    N=$((N + 1))
done

FORCED=0
if [ -f "$WORKERPID" ]; then
    FORCED=1
    echo "Graceful worker shutdown timed out; applying recorded-PID fallback."
    safe_kill_owned "$WORKERPID" "carplay_mirror_test_worker.sh"
    safe_kill_owned "${STATE}/renderer.pid" "opengl-render-qnx-audi"
    safe_kill_owned "${STATE}/capture_host.pid" "/bin/sleep"
fi
safe_kill_owned "${STATE}/persistent_watchdog.pid" "persistent_mirror_watchdog.sh"

export IPL_CONFIG_DIR=/etc/eso/production
/eso/bin/apps/dmdt dc 76 58 >>"$LOG" 2>&1
/eso/bin/apps/dmdt sc 1 72 >>"$LOG" 2>&1
sleep 1
/eso/bin/apps/dmdt sc 1 74 >>"$LOG" 2>&1
rm -f "${STATE}/renderer.pid" "${STATE}/capture_host.pid" "$WORKERPID" \
      "${STATE}/persistent_watchdog.pid" "${STATE}/receiver_ready" \
      "${STATE}/worker_heartbeat"
{
    echo "state=DISABLED"
    if [ "$FORCED" -eq 0 ]; then
        echo "detail=B5 stopped gracefully; Java IDLE confirmed before source58 teardown"
    else
        echo "detail=B5 graceful stop timed out; recorded-PID fallback and context74 restore completed"
    fi
    echo "mode=off"
    date
} > "$STATUS"
sync
cat "$STATUS"
exit 0
