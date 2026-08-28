#!/bin/sh
export PATH=/proc/boot:/bin:/usr/bin:/usr/sbin:/sbin:$PATH
if [ "$_" = "/bin/on" ]; then BASE="$0"; else BASE="$_"; fi
SCRIPTDIR=$( cd -P -- "$(dirname -- "$(command -v -- "$BASE")")" && pwd -P )
. "${SCRIPTDIR}/util_mountsd.sh"
[ -n "$VOLUME" ] || { echo "No SD-card found"; exit 1; }

APP="${VOLUME}/Toolbox/carplay_mirror_test"
STATE="${VOLUME}/Log/CarPlayMirror"
RECORDS="${STATE}/Records"
STAMP=$(date +%Y%m%d_%H%M%S 2>/dev/null)
[ -n "$STAMP" ] || STAMP="unknown_time"
DEST="${RECORDS}/B3_${STAMP}_$$"

mkdir -p "$DEST" || { echo "Could not create B3 log record directory"; exit 1; }

for NAME in \
    direct_upload_status.txt \
    direct_upload.log \
    direct_upload_renderer.log \
    direct_upload_capture_host.log \
    direct_upload_timeline.log \
    direct_upload_watchdog.log \
    direct_upload_worker.log \
    java_mirror_state.txt
do
    [ -f "${STATE}/${NAME}" ] && cp "${STATE}/${NAME}" "${DEST}/${NAME}"
done

{
    echo "version=b3-log-record-v2"
    echo "record_path=${DEST}"
    echo "firmware_expected=MHI2Q_CN_AUG22_P1404"
    echo "mode=30fps-persistent"
    echo "direct_upload_marker=$([ -f "${APP}/DIRECT_UPLOAD_TEST" ] && echo present || echo absent)"
    echo "armed_marker=$([ -f "${APP}/ARMED" ] && echo present || echo absent)"
    echo "fps30_marker=$([ -f "${APP}/FPS30" ] && echo present || echo absent)"
    date
    echo "----- locked artifacts cksum -----"
    for NAME in libcp_mirror.so libdirect_upload.so libport_waker.so \
                opengl-render-qnx-audi libdisplayinit.so libegl_diag.so Cockpit_Mirror.jar
    do
        [ -f "${APP}/${NAME}" ] && cksum "${APP}/${NAME}"
    done
    echo "----- project pid files -----"
    for PIDFILE in "${STATE}"/*.pid; do
        [ -f "$PIDFILE" ] && echo "$(basename "$PIDFILE")=$(cat "$PIDFILE" 2>/dev/null)"
    done
    echo "----- recorded B3 processes -----"
    for PIDFILE in \
        "${STATE}/direct_upload_worker.pid" \
        "${STATE}/direct_upload_renderer.pid" \
        "${STATE}/direct_upload_capture.pid" \
        "${STATE}/direct_upload_watchdog.pid"
    do
        [ -f "$PIDFILE" ] || continue
        PID_VALUE=$(cat "$PIDFILE" 2>/dev/null)
        echo "### $(basename "$PIDFILE")=${PID_VALUE}"
        case "$PID_VALUE" in
            *[!0-9]*|'') echo "invalid pid" ;;
            *) pidin -p "$PID_VALUE" ar 2>/dev/null || echo "process not alive" ;;
        esac
    done
    echo "----- DisplayManager current state -----"
    export IPL_CONFIG_DIR=/etc/eso/production
    /eso/bin/apps/dmdt gs 2>&1
    echo "----- DisplayManager definitions -----"
    /eso/bin/apps/dmdt gd 2>&1
} > "${DEST}/SUMMARY.txt"

sync
echo "===== B3 LOG RECORD SAVED ====="
echo "$DEST"
echo "Files:"
ls -l "$DEST"
echo "----- current status -----"
[ -f "${STATE}/direct_upload_status.txt" ] && cat "${STATE}/direct_upload_status.txt" \
    || echo "No B3 status exists yet."
echo "----- latest measured FPS -----"
grep '^direct upload measured fps_x1000 capture_ms frames ' \
    "${STATE}/direct_upload.log" 2>/dev/null | tail -10
exit 0
