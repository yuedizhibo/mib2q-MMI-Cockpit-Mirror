#!/bin/sh
export PATH=/proc/boot:/bin:/usr/bin:/usr/sbin:/sbin:$PATH
VOLUME="$1"
FPS="${2:-30}"
APP="${VOLUME}/Toolbox/carplay_mirror_test"
STATE="${VOLUME}/Log/CarPlayMirror"
MARKER="${APP}/DIRECT_UPLOAD_TEST"
HEARTBEAT="${STATE}/worker_heartbeat"
LOG="${STATE}/direct_upload_watchdog.log"
PIDFILE="${STATE}/direct_upload_watchdog.pid"
LAST_HEARTBEAT=""
STALE_POLLS=0
POLLS=0

safe_kill_recorded() {
    FILE="$1"
    [ -f "$FILE" ] || return 0
    PID_VALUE=$(cat "$FILE" 2>/dev/null)
    case "$PID_VALUE" in *[!0-9]*|'') return 0 ;; esac
    kill -0 "$PID_VALUE" 2>/dev/null && kill "$PID_VALUE" 2>/dev/null
}

pid_is_alive() {
    FILE="$1"
    [ -f "$FILE" ] || return 1
    PID_VALUE=$(cat "$FILE" 2>/dev/null)
    case "$PID_VALUE" in *[!0-9]*|'') return 1 ;; esac
    kill -0 "$PID_VALUE" 2>/dev/null
}

restore_stock() {
    export IPL_CONFIG_DIR=/etc/eso/production
    /eso/bin/apps/dmdt dc 76 58 >>"$LOG" 2>&1
    /eso/bin/apps/dmdt sc 1 72 >>"$LOG" 2>&1
    sleep 1
    /eso/bin/apps/dmdt sc 1 74 >>"$LOG" 2>&1
}

fail_closed() {
    REASON="$1"
    echo "watchdog_fault=${REASON}" >>"$LOG"
    date >>"$LOG"
    rm -f "$MARKER" "${APP}/ARMED" "${STATE}/receiver_ready" "$HEARTBEAT" \
          "${APP}/FPS10" "${APP}/FPS20" "${APP}/FPS30"
    sync
    sleep 3
    safe_kill_recorded "${STATE}/direct_upload_renderer.pid"
    safe_kill_recorded "${STATE}/direct_upload_capture.pid"
    safe_kill_recorded "${STATE}/direct_upload_worker.pid"
    restore_stock
    {
        echo "version=direct-upload-v50"
        echo "state=WATCHDOG_RESTORED"
        echo "detail=Independent watchdog restored Audi map: ${REASON}"
        echo "requested_fps=${FPS}"
        date
    } >"${STATE}/direct_upload_status.txt"
    rm -f "$PIDFILE"
    sync
    exit 1
}

echo "version=direct-upload-watchdog-v50 fps=${FPS}" >"$LOG"
while [ -f "$MARKER" ]; do
    CURRENT_HEARTBEAT=$(cat "$HEARTBEAT" 2>/dev/null)
    if [ -n "$CURRENT_HEARTBEAT" ] && [ "$CURRENT_HEARTBEAT" != "$LAST_HEARTBEAT" ]; then
        LAST_HEARTBEAT="$CURRENT_HEARTBEAT"
        STALE_POLLS=0
    else
        STALE_POLLS=$((STALE_POLLS + 1))
    fi

    if [ "$POLLS" -ge 20 ]; then
        [ "$STALE_POLLS" -lt 10 ] || fail_closed "worker heartbeat unchanged for at least 20 seconds"
        for SPEC in \
            "${STATE}/direct_upload_worker.pid:worker" \
            "${STATE}/direct_upload_renderer.pid:renderer" \
            "${STATE}/direct_upload_capture.pid:clock-host"
        do
            FILE=${SPEC%%:*}
            ROLE=${SPEC#*:}
            [ -f "$FILE" ] || fail_closed "required pid file missing: ${FILE}"
            PID_VALUE=$(cat "$FILE" 2>/dev/null)
            case "$PID_VALUE" in *[!0-9]*|'') fail_closed "invalid pid file: ${FILE}" ;; esac
            pid_is_alive "$FILE" || fail_closed "required process exited: ${ROLE} pid=${PID_VALUE}"
        done
    fi

    sleep 2
    POLLS=$((POLLS + 1))
done

echo "watchdog_exit=marker removed by normal B3-OFF/worker cleanup" >>"$LOG"
rm -f "$PIDFILE"
exit 0
