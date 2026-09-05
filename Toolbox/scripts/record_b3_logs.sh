#!/bin/sh
export PATH=/proc/boot:/bin:/usr/bin:/usr/sbin:/sbin:$PATH
if [ "$_" = "/bin/on" ]; then BASE="$0"; else BASE="$_"; fi
SCRIPTDIR=$( cd -P -- "$(dirname -- "$(command -v -- "$BASE")")" && pwd -P )
. "${SCRIPTDIR}/util_mountsd.sh"
[ -n "$VOLUME" ] || { echo "No SD-card found"; exit 1; }

APP="${VOLUME}/Toolbox/carplay_mirror_test"
STATE="${VOLUME}/Log/CarPlayMirror"
AUTOSTART="${STATE}/AutoStart"
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

# AutoStart now keeps its own boot/config/verification evidence on the SD card.
# Include that directory wholesale in a manual LOG RECORD so one snapshot is
# sufficient to diagnose both manual START and boot-time START failures.
if [ -d "$AUTOSTART" ]; then
    mkdir -p "${DEST}/AutoStart"
    for FILE in "${AUTOSTART}"/*; do
        [ -f "$FILE" ] && cp "$FILE" "${DEST}/AutoStart/$(basename "$FILE")"
    done
fi

{
    echo "version=b3-log-record-v3"
    echo "record_path=${DEST}"
    echo "firmware_expected=MHI2Q_CN_AUG22_P1404"
    echo "mode=30fps-persistent"
    echo "direct_upload_marker=$([ -f "${APP}/DIRECT_UPLOAD_TEST" ] && echo present || echo absent)"
    echo "armed_marker=$([ -f "${APP}/ARMED" ] && echo present || echo absent)"
    echo "fps30_marker=$([ -f "${APP}/FPS30" ] && echo present || echo absent)"
    echo "autostart_marker=$([ -f "${SCRIPTDIR}/.mmi_cockpit_mirror_autostart" ] && echo present || echo absent)"
    if [ -f "${AUTOSTART}/autostart_status.txt" ]; then
        echo "autostart_state=$(sed -n 's/^state=//p' "${AUTOSTART}/autostart_status.txt" 2>/dev/null | head -1)"
        echo "autostart_detail=$(sed -n 's/^detail=//p' "${AUTOSTART}/autostart_status.txt" 2>/dev/null | head -1)"
    fi
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
[ -d "${DEST}/AutoStart" ] && {
    echo "AutoStart files:"
    ls -l "${DEST}/AutoStart"
}
echo "----- current status -----"
[ -f "${STATE}/direct_upload_status.txt" ] && cat "${STATE}/direct_upload_status.txt" \
    || echo "No B3 status exists yet."
echo "----- AutoStart status -----"
[ -f "${AUTOSTART}/autostart_status.txt" ] && cat "${AUTOSTART}/autostart_status.txt" \
    || echo "No AutoStart boot status exists yet."
echo "----- latest measured FPS -----"
grep '^direct upload measured fps_x1000 capture_ms frames ' \
    "${STATE}/direct_upload.log" 2>/dev/null | tail -10
exit 0
