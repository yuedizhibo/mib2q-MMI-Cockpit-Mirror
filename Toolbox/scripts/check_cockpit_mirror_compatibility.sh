#!/bin/sh
export PATH=/proc/boot:/bin:/usr/bin:/usr/sbin:/sbin:/mnt/app/armle/bin:/mnt/app/armle/usr/bin:$PATH
if [ "$_" = "/bin/on" ]; then BASE="$0"; else BASE="$_"; fi
SCRIPTDIR=$( cd -P -- "$(dirname -- "$(command -v -- "$BASE")")" && pwd -P )
. "${SCRIPTDIR}/util_info.sh"
. "${SCRIPTDIR}/util_mountsd.sh"
[ -n "$VOLUME" ] || { echo "No SD-card found"; exit 1; }

APP="${VOLUME}/Toolbox/carplay_mirror_test"
STATE="${VOLUME}/Log/CarPlayMirror"
WORKER="${SCRIPTDIR}/direct_upload_test_worker.sh"
STOP="${SCRIPTDIR}/stop_direct_upload_test.sh"
CONTROLLER="/mnt/app/eso/hmi/lsd/jars/Cockpit_Mirror.jar"
LEGACY_CONTROLLER="/mnt/app/eso/hmi/lsd/jars/carplay_hook.jar"
EXPECTED_CONTROLLER="140001591 112564"
KNOWN_INSTALL_TRAIN="MHI2Q_CN_AUG22_P1404"
CHECK_DURATION="${MIRROR_CHECK_SECONDS:-12}"
RESULT_FILE="${STATE}/compatibility_check.txt"
CHECK_LOG="${STATE}/compatibility_check_worker.log"
ACTIVE_SNAPSHOT="${STATE}/compatibility_check_active_status.txt"
JAVA_ACTIVE_SNAPSHOT="${STATE}/compatibility_check_java_active.txt"
DMDT_DISPLAYABLES="${STATE}/compatibility_check_dmdt_displayables.txt"
DMDT_CONTEXTS="${STATE}/compatibility_check_dmdt_contexts.txt"
DMDT_ACTIVE="${STATE}/compatibility_check_dmdt_active.txt"
DMDT_AFTER="${STATE}/compatibility_check_dmdt_after.txt"
STATUS="${STATE}/direct_upload_status.txt"
JAVA_STATE="${STATE}/java_mirror_state.txt"
HOOKLOG="${STATE}/mirror_hook.log"
UPLOADLOG="${STATE}/direct_upload.log"
RENDERLOG="${STATE}/direct_upload_renderer.log"

case "$CHECK_DURATION" in
    *[!0-9]*|'') echo "Invalid compatibility check duration"; exit 1 ;;
esac
[ "$CHECK_DURATION" -ge 5 ] || CHECK_DURATION=5
[ "$CHECK_DURATION" -le 30 ] || CHECK_DURATION=30
mkdir -p "$STATE" || exit 1

write_result() {
    RESULT="$1"
    STAGE="$2"
    DETAIL="$3"
    FPS_VALUE="$4"
    {
        echo "version=b3-full-chain-compat-check-v2"
        echo "result=${RESULT}"
        echo "stage=${STAGE}"
        echo "detail=${DETAIL}"
        echo "firmware=${VERSION}"
        echo "brand=${BRAND}"
        echo "fazit=${FAZIT}"
        echo "probe_seconds=${CHECK_DURATION}"
        echo "displayable58_definition=$([ -f "$DMDT_DISPLAYABLES" ] && grep -q '^[[:space:]]*58[[:space:]]' "$DMDT_DISPLAYABLES" 2>/dev/null && echo PASS || echo FAIL)"
        echo "context76_definition=$([ -f "$DMDT_CONTEXTS" ] && grep -q '^[[:space:]]*76[[:space:]].*|' "$DMDT_CONTEXTS" 2>/dev/null && echo PASS || echo FAIL)"
        echo "clock_trigger=$([ -f "$HOOKLOG" ] && grep -q '^mirror first direct-upload trigger sent ' "$HOOKLOG" 2>/dev/null && echo PASS || echo FAIL)"
        echo "mmi_1024x480_frame=$([ -f "$UPLOADLOG" ] && grep -q '^direct upload first MMI frame ' "$UPLOADLOG" 2>/dev/null && echo PASS || echo FAIL)"
        echo "egl_submit=$([ -f "$RENDERLOG" ] && grep -q '\[egl-diag\] eglSwapBuffers' "$RENDERLOG" 2>/dev/null && echo PASS || echo FAIL)"
        echo "java_active=$([ -f "$JAVA_ACTIVE_SNAPSHOT" ] && echo PASS || echo FAIL)"
        echo "context76_source58=$([ -f "$JAVA_ACTIVE_SNAPSHOT" ] && grep -q 'nativeContext=76 source=58 fps=30' "$JAVA_ACTIVE_SNAPSHOT" 2>/dev/null && echo PASS || echo FAIL)"
        echo "dmdt_context76=$([ -f "$DMDT_ACTIVE" ] && grep -q 'context id: 76' "$DMDT_ACTIVE" 2>/dev/null && echo PASS || echo FAIL)"
        echo "worker_active=$([ -f "$ACTIVE_SNAPSHOT" ] && echo PASS || echo FAIL)"
        echo "java_return_idle=$([ -f "$JAVA_STATE" ] && grep -q '^state=IDLE' "$JAVA_STATE" 2>/dev/null && echo PASS || echo FAIL)"
        echo "dmdt_context74=$([ -f "$DMDT_AFTER" ] && grep -q 'context id: 74' "$DMDT_AFTER" 2>/dev/null && echo PASS || echo FAIL)"
        echo "measured_fps_x1000=${FPS_VALUE}"
        date
    } > "$RESULT_FILE"
    sync
}

print_pass() {
    echo ""
    echo "============================================"
    echo " CHECK RESULT: CAN USE THIS PROJECT"
    echo " Full B3 chain: PASS"
    echo "============================================"
    echo "DisplayManager 58 / 76 definitions: PASS"
    echo "1024x480 MMI capture: PASS"
    echo "renderer / EGL: PASS"
    echo "Java controller: PASS"
    echo "live context 76 / displayable 58: PASS"
    echo "restore to context 74: PASS"
    [ -n "$1" ] && echo "measured fps_x1000: $1"
    echo "Detailed result: ${RESULT_FILE}"
}

print_fail() {
    echo ""
    echo "============================================"
    echo " CHECK RESULT: CANNOT USE CURRENT BUILD"
    echo " Full B3 chain: FAIL"
    echo "============================================"
    echo "Failed stage: $1"
    echo "Reason: $2"
    echo "The check requested the stock Audi route again before exiting."
    echo "Detailed result: ${RESULT_FILE}"
}

pid_file_alive() {
    FILE="$1"
    [ -f "$FILE" ] || return 1
    VALUE=$(cat "$FILE" 2>/dev/null)
    case "$VALUE" in *[!0-9]*|'') return 1 ;; esac
    kill -0 "$VALUE" 2>/dev/null
}

echo "===== MMI Cockpit Mirror FULL-CHAIN CHECK ====="
echo "This is not a model-name whitelist check."
echo "It performs a short real B3 run and automatically restores the Audi route."
echo "Firmware reported by unit: ${VERSION}"
echo ""

export IPL_CONFIG_DIR=/etc/eso/production
/eso/bin/apps/dmdt gd >"$DMDT_DISPLAYABLES" 2>&1
GD_RC=$?
/eso/bin/apps/dmdt gc >"$DMDT_CONTEXTS" 2>&1
GC_RC=$?
if [ "$GD_RC" -ne 0 ] || ! grep -q '^[[:space:]]*58[[:space:]]' "$DMDT_DISPLAYABLES" 2>/dev/null; then
    write_result "NOT_COMPATIBLE" "displaymanager-displayable58" "DisplayManager does not expose required displayable 58" ""
    print_fail "displaymanager-displayable58" "Required displayable 58 is not available."
    exit 1
fi
if [ "$GC_RC" -ne 0 ] || ! grep -q '^[[:space:]]*76[[:space:]].*|' "$DMDT_CONTEXTS" 2>/dev/null; then
    write_result "NOT_COMPATIBLE" "displaymanager-context76" "DisplayManager does not expose required context 76" ""
    print_fail "displaymanager-context76" "Required context 76 is not available."
    exit 1
fi
echo "[CHECK] DisplayManager exposes displayable 58 and context 76"

if [ -f "${APP}/DIRECT_UPLOAD_TEST" ]; then
    if grep -q '^state=ACTIVE' "$STATUS" 2>/dev/null && \
       grep -q '^state=ACTIVE' "$JAVA_STATE" 2>/dev/null && \
       grep -q 'nativeContext=76 source=58 fps=30' "$JAVA_STATE" 2>/dev/null && \
       pid_file_alive "${STATE}/direct_upload_worker.pid" && \
       pid_file_alive "${STATE}/direct_upload_renderer.pid" && \
       pid_file_alive "${STATE}/direct_upload_capture.pid"; then
        /eso/bin/apps/dmdt gs >"$DMDT_ACTIVE" 2>&1
        if grep -q 'context id: 76' "$DMDT_ACTIVE" 2>/dev/null; then
            cp "$STATUS" "$ACTIVE_SNAPSHOT" 2>/dev/null || :
            cp "$JAVA_STATE" "$JAVA_ACTIVE_SNAPSHOT" 2>/dev/null || :
            FPS_VALUE=""
            LINE=$(grep '^direct upload measured fps_x1000 capture_ms frames ' "$UPLOADLOG" 2>/dev/null | tail -1)
            if [ -n "$LINE" ]; then
                set -- $LINE
                FPS_VALUE="$7"
            fi
            write_result "COMPATIBLE" "already-active" "Existing B3 session is healthy and already proves the complete chain" "$FPS_VALUE"
            print_pass "$FPS_VALUE"
            exit 0
        fi
    fi

    echo "Stale or unhealthy B3 state detected; restoring stock route before CHECK."
    [ -x "$STOP" ] && "$STOP" >/dev/null 2>&1
    sleep 2
fi

if [ -f "${APP}/ARMED" ] && [ ! -f "${APP}/DIRECT_UPLOAD_TEST" ]; then
    write_result "NOT_COMPATIBLE" "runtime-conflict" "Another mirror runtime is ARMED; stop it before compatibility testing" ""
    print_fail "runtime-conflict" "Another mirror runtime is active. Stop it first, then run CHECK again."
    exit 1
fi

[ -x "$WORKER" ] || {
    write_result "NOT_COMPATIBLE" "package" "Missing direct_upload_test_worker.sh" ""
    print_fail "package" "Missing B3 worker script."
    exit 1
}

CONTROLLER_OK=0
if [ -f "$CONTROLLER" ]; then
    set -- $(cksum "$CONTROLLER" 2>/dev/null)
    [ "$1 $2" = "$EXPECTED_CONTROLLER" ] && CONTROLLER_OK=1
fi

if [ "$CONTROLLER_OK" -ne 1 ] || [ -f "$LEGACY_CONTROLLER" ]; then
    if [ "$VERSION" = "$KNOWN_INSTALL_TRAIN" ]; then
        echo "Verified Java controller is not ready; preparing it with the normal safe installer."
        "${SCRIPTDIR}/ensure_cockpit_mirror_controller.sh"
        INSTALL_RC=$?
        if [ "$INSTALL_RC" -eq 10 ]; then
            write_result "REBOOT_REQUIRED" "java-controller" "Verified controller installed; complete MMI reboot required before full-chain CHECK" ""
            echo ""
            echo "============================================"
            echo " CHECK RESULT: REBOOT REQUIRED"
            echo "============================================"
            echo "Cockpit_Mirror.jar was installed safely."
            echo "Perform one COMPLETE MMI reboot, then run CHECK again."
            echo "Only the second run can produce the final CAN USE / CANNOT USE result."
            exit 10
        fi
        if [ "$INSTALL_RC" -ne 0 ]; then
            write_result "NOT_COMPATIBLE" "java-controller" "Controller preparation failed with rc=${INSTALL_RC}" ""
            print_fail "java-controller" "Could not prepare the verified Java controller."
            exit 1
        fi
    else
        write_result "NOT_COMPATIBLE" "java-controller" "Verified Cockpit_Mirror.jar is not installed; CHECK refuses to modify unknown firmware ${VERSION}" ""
        print_fail "java-controller" "No verified Java controller is installed for this running firmware. CHECK will not write an unknown train just to experiment."
        exit 1
    fi
fi

rm -f "$ACTIVE_SNAPSHOT" "$JAVA_ACTIVE_SNAPSHOT" "$DMDT_ACTIVE" "$DMDT_AFTER" "$CHECK_LOG"

echo "Starting real B3 compatibility probe (${CHECK_DURATION}s ACTIVE window)..."
echo "The cockpit may briefly show the mirrored MMI during this test."
/bin/sh "$WORKER" "$VOLUME" 30 "$CHECK_DURATION" >"$CHECK_LOG" 2>&1 &
CHECK_PID=$!
SEEN_ACTIVE=0
SEEN_JAVA_ACTIVE=0
SEEN_DMDT_ACTIVE=0

while kill -0 "$CHECK_PID" 2>/dev/null; do
    if [ "$SEEN_ACTIVE" -eq 0 ] && grep -q '^state=ACTIVE' "$STATUS" 2>/dev/null; then
        cp "$STATUS" "$ACTIVE_SNAPSHOT" 2>/dev/null || :
        SEEN_ACTIVE=1
        echo "[CHECK] B3 worker reached ACTIVE"
    fi
    if [ "$SEEN_JAVA_ACTIVE" -eq 0 ] && grep -q '^state=ACTIVE' "$JAVA_STATE" 2>/dev/null && \
       grep -q 'nativeContext=76 source=58 fps=30' "$JAVA_STATE" 2>/dev/null; then
        cp "$JAVA_STATE" "$JAVA_ACTIVE_SNAPSHOT" 2>/dev/null || :
        SEEN_JAVA_ACTIVE=1
        echo "[CHECK] Java confirmed context76 / source58"
    fi
    if [ "$SEEN_DMDT_ACTIVE" -eq 0 ] && [ "$SEEN_JAVA_ACTIVE" -eq 1 ]; then
        /eso/bin/apps/dmdt gs >"$DMDT_ACTIVE" 2>&1
        if grep -q 'context id: 76' "$DMDT_ACTIVE" 2>/dev/null; then
            SEEN_DMDT_ACTIVE=1
            echo "[CHECK] DisplayManager reports live context 76"
        fi
    fi
    sleep 1
done
wait "$CHECK_PID"
CHECK_RC=$?

/eso/bin/apps/dmdt gs >"$DMDT_AFTER" 2>&1
DMDT_RC=$?

FINAL_STATE=$(sed -n 's/^state=//p' "$STATUS" 2>/dev/null | head -1)
FINAL_DETAIL=$(sed -n 's/^detail=//p' "$STATUS" 2>/dev/null | head -1)
FPS_VALUE=""
LINE=$(grep '^direct upload measured fps_x1000 capture_ms frames ' "$UPLOADLOG" 2>/dev/null | tail -1)
if [ -n "$LINE" ]; then
    set -- $LINE
    FPS_VALUE="$7"
fi

CLOCK_OK=0
FRAME_OK=0
EGL_OK=0
JAVA_OK=0
ACTIVE_OK=0
DMDT_ACTIVE_OK=0
IDLE_OK=0
STOCK_CONTEXT_OK=0
[ -f "$HOOKLOG" ] && grep -q '^mirror first direct-upload trigger sent ' "$HOOKLOG" 2>/dev/null && CLOCK_OK=1
[ -f "$UPLOADLOG" ] && grep -q '^direct upload first MMI frame ' "$UPLOADLOG" 2>/dev/null && FRAME_OK=1
[ -f "$RENDERLOG" ] && grep -q '\[egl-diag\] eglSwapBuffers' "$RENDERLOG" 2>/dev/null && EGL_OK=1
[ -f "$JAVA_ACTIVE_SNAPSHOT" ] && grep -q 'nativeContext=76 source=58 fps=30' "$JAVA_ACTIVE_SNAPSHOT" 2>/dev/null && JAVA_OK=1
[ -f "$ACTIVE_SNAPSHOT" ] && ACTIVE_OK=1
[ -f "$DMDT_ACTIVE" ] && grep -q 'context id: 76' "$DMDT_ACTIVE" 2>/dev/null && DMDT_ACTIVE_OK=1
[ -f "$JAVA_STATE" ] && grep -q '^state=IDLE' "$JAVA_STATE" 2>/dev/null && IDLE_OK=1
[ -f "$DMDT_AFTER" ] && grep -q 'context id: 74' "$DMDT_AFTER" 2>/dev/null && STOCK_CONTEXT_OK=1

if [ "$CHECK_RC" -eq 0 ] && [ "$FINAL_STATE" = "FINISHED_SAFE" ] && \
   [ "$CLOCK_OK" -eq 1 ] && [ "$FRAME_OK" -eq 1 ] && [ "$EGL_OK" -eq 1 ] && \
   [ "$JAVA_OK" -eq 1 ] && [ "$ACTIVE_OK" -eq 1 ] && [ "$DMDT_ACTIVE_OK" -eq 1 ] && \
   [ "$IDLE_OK" -eq 1 ] && [ "$STOCK_CONTEXT_OK" -eq 1 ] && [ "$DMDT_RC" -eq 0 ]; then
    write_result "COMPATIBLE" "complete" "Full B3 capture, EGL, Java context76/source58, live DisplayManager context76 and context74 restore all passed" "$FPS_VALUE"
    print_pass "$FPS_VALUE"
    exit 0
fi

FAILED_STAGE="unknown"
case "$FINAL_DETAIL" in
    *Missing*|*Checksum*mismatch*) FAILED_STAGE="package-integrity" ;;
    *)
        if [ "$CLOCK_OK" -ne 1 ]; then FAILED_STAGE="clock-host"
        elif [ "$FRAME_OK" -ne 1 ]; then FAILED_STAGE="mmi-capture-1024x480"
        elif [ "$EGL_OK" -ne 1 ]; then FAILED_STAGE="renderer-egl"
        elif [ "$JAVA_OK" -ne 1 ]; then FAILED_STAGE="java-displaymanager-context76"
        elif [ "$DMDT_ACTIVE_OK" -ne 1 ]; then FAILED_STAGE="displaymanager-live-context76"
        elif [ "$ACTIVE_OK" -ne 1 ]; then FAILED_STAGE="b3-activation"
        elif [ "$IDLE_OK" -ne 1 ] || [ "$STOCK_CONTEXT_OK" -ne 1 ] || [ "$DMDT_RC" -ne 0 ] || [ "$FINAL_STATE" != "FINISHED_SAFE" ]; then FAILED_STAGE="safe-restore-context74"
        fi
        ;;
esac

[ -n "$FINAL_DETAIL" ] || FINAL_DETAIL="Full-chain probe did not finish with all required evidence"
[ -x "$STOP" ] && "$STOP" >/dev/null 2>&1
write_result "NOT_COMPATIBLE" "$FAILED_STAGE" "$FINAL_DETAIL" "$FPS_VALUE"
print_fail "$FAILED_STAGE" "$FINAL_DETAIL"
exit 1
