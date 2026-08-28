#!/bin/sh
export PATH=/proc/boot:/bin:/usr/bin:/usr/sbin:/sbin:$PATH
if [ "$_" = "/bin/on" ]; then BASE="$0"; else BASE="$_"; fi
SCRIPTDIR=$( cd -P -- "$(dirname -- "$(command -v -- "$BASE")")" && pwd -P )
. "${SCRIPTDIR}/util_info.sh"
. "${SCRIPTDIR}/util_mountsd.sh"
[ -n "$VOLUME" ] || { echo "No SD-card found"; exit 1; }
APP="${VOLUME}/Toolbox/carplay_mirror_test"
STATE="${VOLUME}/Log/CarPlayMirror"
STATUS="${STATE}/direct_upload_status.txt"
CONTROLLER="/mnt/app/eso/hmi/lsd/jars/Cockpit_Mirror.jar"
EXPECTED_CONTROLLER="140001591 112564"
FPS="${MIRROR_DIRECT_FPS:-30}"
case "$FPS" in
    30) ;;
    *) echo "Unsupported B3-OPT FPS: $FPS"; exit 1 ;;
esac
echo "===== MMI Cockpit Mirror v51: persistent 30-FPS renderer-local upload ====="
[ "$VERSION" = "MHI2Q_CN_AUG22_P1404" ] || { echo "Wrong firmware: $VERSION"; exit 1; }
[ ! -f "${APP}/ARMED" ] || [ -f "${APP}/DIRECT_UPLOAD_TEST" ] || \
    { echo "B5 is active. Run B5-OFF first."; exit 1; }

# A complete MMI reboot terminates every B3 process but cannot remove a marker
# stored on the SD card. Treat DIRECT_UPLOAD_TEST as live only when its
# recorded worker PID still belongs to this project. START can therefore heal
# stale reboot state without exposing a separate cleanup menu item.
if [ -f "${APP}/DIRECT_UPLOAD_TEST" ]; then
    OLD_PID=$(cat "${STATE}/direct_upload_worker.pid" 2>/dev/null)
    case "$OLD_PID" in
        *[!0-9]*|'') OLD_LIVE=0 ;;
        *)
            if pidin -p "$OLD_PID" ar 2>/dev/null | grep -q 'direct_upload_test_worker.sh'; then
                OLD_LIVE=1
            else
                OLD_LIVE=0
            fi
            ;;
    esac
    [ "$OLD_LIVE" -eq 0 ] || { echo "B3-OPT is already active."; exit 1; }
    echo "Clearing stale B3 state left by an MMI reboot."
    rm -f "${APP}/DIRECT_UPLOAD_TEST" "${APP}/DIRECT16_SHARE_TEST" \
          "${APP}/DIRECT16_TEST" "${APP}/ARMED" "${STATE}/receiver_ready" \
          "${STATE}/worker_heartbeat" "${APP}/FPS10" "${APP}/FPS20" "${APP}/FPS30" \
          "${STATE}/direct_upload_worker.pid" "${STATE}/direct_upload_renderer.pid" \
          "${STATE}/direct_upload_capture.pid" "${STATE}/direct_upload_watchdog.pid"
    export IPL_CONFIG_DIR=/etc/eso/production
    /eso/bin/apps/dmdt dc 76 58 >/dev/null 2>&1
    /eso/bin/apps/dmdt sc 1 72 >/dev/null 2>&1
    sleep 1
    /eso/bin/apps/dmdt sc 1 74 >/dev/null 2>&1
    sync
fi
[ ! -f "${APP}/DIRECT16_TEST" ] || { echo "Another direct test is active."; exit 1; }
[ ! -f "${APP}/DIRECT16_SHARE_TEST" ] || { echo "Old B3 marker is active. Run B3-OFF first."; exit 1; }
CONTROLLER_OK=0
if [ -f "$CONTROLLER" ]; then
    set -- $(cksum "$CONTROLLER" 2>/dev/null)
    [ "$1 $2" = "$EXPECTED_CONTROLLER" ] && CONTROLLER_OK=1
fi
if [ "$CONTROLLER_OK" -ne 1 ] || [ -f "/mnt/app/eso/hmi/lsd/jars/carplay_hook.jar" ]; then
    "${SCRIPTDIR}/ensure_cockpit_mirror_controller.sh"
    RESULT=$?
    if [ "$RESULT" -eq 10 ]; then
        echo "Controller installed. Fully reboot the MMI, then select START again."
        exit 0
    fi
    [ "$RESULT" -eq 0 ] || exit "$RESULT"
fi
mkdir -p "$STATE" || exit 1

# A forced reboot or SD removal can leave only PID/status files behind.  If no
# ARMED marker is live, use the proven graceful B5 OFF path to terminate only
# recorded project PIDs before the new renderer tries to connect to port 5900.
if [ -f "${STATE}/worker.pid" ] || [ -f "${STATE}/renderer.pid" ] || \
   [ -f "${STATE}/capture_host.pid" ] || [ -f "${STATE}/persistent_watchdog.pid" ]; then
    echo "Cleaning recorded B5 runtime state before B3-OPT."
    "${SCRIPTDIR}/stop_carplay_mirror_test.sh" >/dev/null 2>&1
fi

# An older hook loaded in smartphone_integrator can remain blocked in accept()
# after ARMED disappears. Wake that one project-owned loopback listener so it
# observes the disarmed state and releases 5900 before the v43 clock starts.
if [ -f "${APP}/libport_waker.so" ]; then
    set -- $(cksum "${APP}/libport_waker.so" 2>/dev/null)
    if [ "$1 $2" = "3375612677 2292" ]; then
        export LD_LIBRARY_PATH="${APP}:/eso/lib:/armle/lib:/armle/usr/lib:/lib"
        LD_PRELOAD="${APP}/libport_waker.so" /bin/sleep 0 >/dev/null 2>&1
        echo "Port-release helper completed."
        sleep 2
    else
        # The helper is optional: it only wakes a stale project-owned accept()
        # listener.  Some P1404 QNX builds report a different cksum dialect.
        # Never preload an unverified file; let the worker's normal bind check
        # decide whether port 5900 is already available instead.
        echo "Port-release helper skipped (reported cksum: $1 $2)."
    fi
else
    echo "Port-release helper absent; continuing with normal port check."
fi
"${SCRIPTDIR}/direct_upload_test_worker.sh" "$VOLUME" "$FPS" \
    >"${STATE}/direct_upload_worker.log" 2>&1 &
sleep 2
[ -f "$STATUS" ] && cat "$STATUS" || { echo "B3-OPT worker did not create status"; exit 1; }
echo "Leave GEM and keep the desired MMI/CarPlay screen visible."
echo "The Audi map stays active until a real renderer-local frame is confirmed."
echo "Persistent mode stays active until B3-OPT OFF or a watchdog fault."
exit 0
