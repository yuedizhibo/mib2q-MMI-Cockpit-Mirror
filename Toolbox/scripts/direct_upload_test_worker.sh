#!/bin/sh
export PATH=/proc/boot:/bin:/usr/bin:/usr/sbin:/sbin:$PATH
VOLUME="$1"
FPS="${2:-30}"
[ "$FPS" -eq 30 ] || exit 1
DURATION=0
APP="${VOLUME}/Toolbox/carplay_mirror_test"
STATE="${VOLUME}/Log/CarPlayMirror"
MARKER="${APP}/DIRECT_UPLOAD_TEST"
ARMED="${APP}/ARMED"
READY="${STATE}/receiver_ready"
HEARTBEAT="${STATE}/worker_heartbeat"
JAVA_STATE="${STATE}/java_mirror_state.txt"
STATUS="${STATE}/direct_upload_status.txt"
HOOKLOG="${STATE}/mirror_hook.log"
UPLOADLOG="${STATE}/direct_upload.log"
RENDERLOG="${STATE}/direct_upload_renderer.log"
HOSTLOG="${STATE}/direct_upload_capture_host.log"
TIMELINE="${STATE}/direct_upload_timeline.log"
WORKERPID="${STATE}/direct_upload_worker.pid"
RENDERPID="${STATE}/direct_upload_renderer.pid"
CAPTUREPID="${STATE}/direct_upload_capture.pid"
WATCHDOGPID="${STATE}/direct_upload_watchdog.pid"
EXPECTED_HOOK="2128946334 16364"
EXPECTED_UPLOAD="2201151100 9064"
EXPECTED_RENDERER="1309065104 107890"
EXPECTED_DISPLAY_SHIM="1535898152 4956"
EXPECTED_EGL_DIAG="4142780645 8484"
RENDER_PID=""
CAPTURE_PID=""
HEARTBEAT_N=0

write_status() {
    {
        echo "version=direct-upload-v51"
        echo "state=$1"
        echo "detail=$2"
        echo "source=screen-read-display-in-renderer-process"
        echo "transport=tiny-rfb-clock-no-full-frame-rfb"
        echo "destination=context76-displayable58"
        echo "requested_fps=${FPS}"
        echo "duration_seconds=${DURATION}"
        echo "renderer_pid=${RENDER_PID}"
        echo "capture_pid=${CAPTURE_PID}"
        date
    } > "$STATUS"
    sync
}

pulse() {
    echo "direct-upload-live-${HEARTBEAT_N}" > "$HEARTBEAT"
    HEARTBEAT_N=$((HEARTBEAT_N + 1))
}

safe_kill() {
    case "$1" in *[!0-9]*|'') return 0 ;; esac
    kill "$1" 2>/dev/null
}

restore_and_cleanup() {
    trap - 1 2 15
    rm -f "$MARKER" "$ARMED" "$READY" "$HEARTBEAT" "${APP}/FPS10" "${APP}/FPS20" "${APP}/FPS30"
    sync
    WAIT_IDLE=0
    while [ "$WAIT_IDLE" -lt 10 ]; do
        grep -q '^state=IDLE' "$JAVA_STATE" 2>/dev/null && break
        sleep 1
        WAIT_IDLE=$((WAIT_IDLE + 1))
    done
    safe_kill "$RENDER_PID"
    safe_kill "$CAPTURE_PID"
    export IPL_CONFIG_DIR=/etc/eso/production
    /eso/bin/apps/dmdt dc 76 58 >>"$TIMELINE" 2>&1
    /eso/bin/apps/dmdt sc 1 72 >>"$TIMELINE" 2>&1
    sleep 1
    /eso/bin/apps/dmdt sc 1 74 >>"$TIMELINE" 2>&1
    rm -f "$WORKERPID" "$RENDERPID" "$CAPTUREPID"
    sync
}

fail_test() {
    write_status "FAILED" "$1; cockpit route restored"
    restore_and_cleanup
    exit 1
}

trap 'write_status "INTERRUPTED" "Worker interrupted; restoring Audi map"; restore_and_cleanup; exit 0' 1 2 15
mkdir -p "$STATE" || exit 1
echo $$ > "$WORKERPID"
: > "$HOOKLOG"
: > "$UPLOADLOG"
: > "$RENDERLOG"
: > "$HOSTLOG"
: > "$TIMELINE"
rm -f "$ARMED" "$READY" "$HEARTBEAT" "$JAVA_STATE" "${APP}/FPS10" "${APP}/FPS20" "${APP}/FPS30"
date > "$MARKER" || exit 1
sync

"$(dirname "$0")/direct_upload_restore_watchdog.sh" "$VOLUME" "$FPS" \
    >"${STATE}/direct_upload_watchdog.log" 2>&1 &
echo $! > "$WATCHDOGPID"

write_status "VALIDATING" "Checking v51 persistent 30-FPS draw-clock components"
for SPEC in \
    "libcp_mirror.so:${EXPECTED_HOOK}" \
    "libdirect_upload.so:${EXPECTED_UPLOAD}" \
    "opengl-render-qnx-audi:${EXPECTED_RENDERER}" \
    "libdisplayinit.so:${EXPECTED_DISPLAY_SHIM}" \
    "libegl_diag.so:${EXPECTED_EGL_DIAG}"
do
    NAME=${SPEC%%:*}
    EXPECTED=${SPEC#*:}
    [ -f "${APP}/${NAME}" ] || fail_test "Missing ${NAME}"
    set -- $(cksum "${APP}/${NAME}")
    [ "$1 $2" = "$EXPECTED" ] || fail_test "Checksum mismatch for ${NAME}"
done

chmod 755 "${APP}/opengl-render-qnx-audi" || fail_test "Could not chmod renderer"
touch "${APP}/FPS${FPS}" || fail_test "Could not create test clock marker"
pulse
sync
export IPL_CONFIG_DIR=/etc/eso/production
export LD_LIBRARY_PATH="${APP}:/eso/lib:/armle/lib:/armle/usr/lib:/lib"
cd "$APP" || fail_test "Could not enter app directory"

# The clock host sends only a four-byte zlib pacing payload. The actual MMI
# frame is read by libdirect_upload inside the renderer immediately before each
# GLES texture update.  Keep the proven v48 /bin/sh -c preload host: on P1404
# this form starts libcp_mirror's tiny-RFB constructor, while launching a shell
# script directly can leave the shell alive without starting the native server.
# The v51 watchdog validates the recorded PID with kill -0 and therefore no
# longer depends on P1404's truncated pidin command-line text.
MIRROR_CLOCK_HOST=1 LD_PRELOAD="${APP}/libcp_mirror.so" \
    /bin/sh -c "while [ -f '${MARKER}' ]; do /bin/sleep 30; done" \
    >>"$HOSTLOG" 2>&1 &
CAPTURE_PID=$!
echo "$CAPTURE_PID" > "$CAPTUREPID"
sleep 1
kill -0 "$CAPTURE_PID" 2>/dev/null || fail_test "Clock host exited during startup"

LD_PRELOAD="${APP}/libdirect_upload.so:${APP}/libegl_diag.so" \
    "${APP}/opengl-render-qnx-audi" 127.0.0.1 >>"$RENDERLOG" 2>&1 &
RENDER_PID=$!
echo "$RENDER_PID" > "$RENDERPID"
write_status "WAITING_FRAME" "Audi map remains active until a direct MMI texture is confirmed"

N=0
while [ "$N" -lt 20 ]; do
    pulse
    kill -0 "$RENDER_PID" 2>/dev/null || fail_test "Renderer exited before first direct frame"
    kill -0 "$CAPTURE_PID" 2>/dev/null || fail_test "Clock host exited before first direct frame"
    grep -q '^direct upload first MMI frame ' "$UPLOADLOG" 2>/dev/null && break
    sleep 1
    N=$((N + 1))
done
grep -q '^mirror first direct-upload trigger sent ' "$HOOKLOG" 2>/dev/null || \
    fail_test "Tiny renderer clock did not start"
grep -q '^direct upload first MMI frame ' "$UPLOADLOG" 2>/dev/null || \
    fail_test "No renderer-local 1024x480 MMI frame within 20 seconds"
grep -q '\[egl-diag\] eglSwapBuffers' "$RENDERLOG" 2>/dev/null || \
    fail_test "Renderer did not submit an EGL frame"

# Only now expose ARMED to the already-installed Java/legacy hook.  The v41
# SD-owned clock already owns port 5900, so an older installed capture hook can
# no longer steal the only renderer connection.
touch "$ARMED" || fail_test "Could not arm Java after direct texture gate"
touch "$READY" || fail_test "Could not request Java context76 activation"
pulse
sync
write_status "WAITING_JAVA" "Direct texture ready; waiting for context76/displayable58"
N=0
while [ "$N" -lt 15 ]; do
    pulse
    kill -0 "$RENDER_PID" 2>/dev/null || fail_test "Renderer exited during Java hand-off"
    grep -q '^state=ACTIVE' "$JAVA_STATE" 2>/dev/null && break
    if grep -q '^state=FAILED' "$JAVA_STATE" 2>/dev/null; then
        DETAIL=$(sed -n 's/^detail=//p' "$JAVA_STATE" | head -1)
        fail_test "Java hand-off failed: ${DETAIL}"
    fi
    sleep 1
    N=$((N + 1))
done
grep -q '^state=ACTIVE' "$JAVA_STATE" 2>/dev/null || fail_test "Java controller did not reach ACTIVE"
grep -q "nativeContext=76 source=58 fps=${FPS}" "$JAVA_STATE" 2>/dev/null || \
    fail_test "Java ACTIVE did not confirm context76/source58"
write_status "ACTIVE" "v51 recommended persistent 30-FPS renderer-local full-MMI upload active until STOP"

N=0
LAST_COUNT=$(grep -c '^direct upload measured fps_x1000 capture_ms frames ' "$UPLOADLOG" 2>/dev/null)
case "$LAST_COUNT" in *[!0-9]*|'') LAST_COUNT=0 ;; esac
STALE=0
while [ "$DURATION" -eq 0 ] || [ "$N" -lt "$DURATION" ]; do
    pulse
    [ -f "$MARKER" ] || {
        write_status "STOPPING" "B3-OFF requested"
        restore_and_cleanup
        write_status "DISABLED" "B3 direct-upload test stopped safely; Audi map restored"
        exit 0
    }
    kill -0 "$RENDER_PID" 2>/dev/null || fail_test "Renderer exited during direct-upload test"
    kill -0 "$CAPTURE_PID" 2>/dev/null || fail_test "Clock host exited during direct-upload test"
    if grep -q '^state=FAILED' "$JAVA_STATE" 2>/dev/null; then
        DETAIL=$(sed -n 's/^detail=//p' "$JAVA_STATE" | head -1)
        fail_test "Java controller failed during direct-upload test: ${DETAIL}"
    fi
    CURRENT_COUNT=$(grep -c '^direct upload measured fps_x1000 capture_ms frames ' "$UPLOADLOG" 2>/dev/null)
    case "$CURRENT_COUNT" in *[!0-9]*|'') CURRENT_COUNT=0 ;; esac
    if [ "$CURRENT_COUNT" -gt "$LAST_COUNT" ]; then
        LAST_COUNT="$CURRENT_COUNT"
        STALE=0
    else
        STALE=$((STALE + 1))
    fi
    [ "$STALE" -le 12 ] || fail_test "Direct MMI frame counter stopped for more than 12 seconds"
    sleep 1
    N=$((N + 1))
done

restore_and_cleanup
write_status "FINISHED_SAFE" "Finite compatibility run completed; Audi map restored"
exit 0
