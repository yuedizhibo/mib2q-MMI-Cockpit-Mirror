#!/bin/sh
export PATH=/proc/boot:/bin:/usr/bin:/usr/sbin:/sbin:/mnt/app/armle/bin:/mnt/app/armle/usr/bin:$PATH
SCRIPTDIR="/mnt/app/eso/hmi/engdefs/scripts/mqb"
MARKER="${SCRIPTDIR}/.mmi_cockpit_mirror_autostart"
START="${SCRIPTDIR}/start_direct_upload_test.sh"
STOP="${SCRIPTDIR}/stop_direct_upload_test.sh"
CONTROLLER="/mnt/app/eso/hmi/lsd/jars/Cockpit_Mirror.jar"
LEGACY_CONTROLLER="/mnt/app/eso/hmi/lsd/jars/carplay_hook.jar"
EXPECTED_CONTROLLER="140001591 112564"
EXPECTED_VERSION="MHI2Q_CN_AUG22_P1404"
TMPLOG="/tmp/mmi_cockpit_mirror_autostart_runner.log"
BOOTSTRAP_TMP="/tmp/mmi_cockpit_mirror_autostart_bootstrap.log"
VOLUME=""
STATE=""
AUTOLOGDIR=""
LOG=""
STATUS=""
B3_STATUS=""
JAVA_STATE=""

: > "$TMPLOG"
exec >>"$TMPLOG" 2>&1

echo "===== MMI Cockpit Mirror AutoStart boot runner ====="
date

find_volume() {
    if [ -d /net/mmx/fs/sda0/Toolbox/carplay_mirror_test ]; then
        VOLUME="/net/mmx/fs/sda0"
        return 0
    fi
    if [ -d /net/mmx/fs/sdb0/Toolbox/carplay_mirror_test ]; then
        VOLUME="/net/mmx/fs/sdb0"
        return 0
    fi
    return 1
}

pid_alive() {
    FILE="$1"
    [ -f "$FILE" ] || return 1
    VALUE=$(cat "$FILE" 2>/dev/null)
    case "$VALUE" in *[!0-9]*|'') return 1 ;; esac
    kill -0 "$VALUE" 2>/dev/null
}

write_status() {
    [ -n "$STATUS" ] || return 0
    {
        echo "version=autostart-v3"
        echo "state=$1"
        echo "attempt=$2"
        echo "detail=$3"
        echo "volume=${VOLUME}"
        echo "b3_state=$(sed -n 's/^state=//p' "$B3_STATUS" 2>/dev/null | head -1)"
        echo "java_state=$(sed -n 's/^state=//p' "$JAVA_STATE" 2>/dev/null | head -1)"
        date
    } > "$STATUS"
    sync
}

b3_is_active() {
    [ -f "${VOLUME}/Toolbox/carplay_mirror_test/DIRECT_UPLOAD_TEST" ] || return 1
    grep -q '^state=ACTIVE' "$B3_STATUS" 2>/dev/null || return 1
    grep -q '^state=ACTIVE' "$JAVA_STATE" 2>/dev/null || return 1
    grep -q 'nativeContext=76 source=58 fps=30' "$JAVA_STATE" 2>/dev/null || return 1
    pid_alive "${STATE}/direct_upload_worker.pid" || return 1
    pid_alive "${STATE}/direct_upload_renderer.pid" || return 1
    pid_alive "${STATE}/direct_upload_capture.pid" || return 1
    export IPL_CONFIG_DIR=/etc/eso/production
    /eso/bin/apps/dmdt gs 2>/dev/null | grep -q 'context id: 76'
}

# startup.sh may run before the SD card is mounted. Keep the local /tmp log as
# an early-boot fallback, but move all useful AutoStart diagnostics to the SD
# card as soon as the Toolbox volume becomes available.
N=0
while [ "$N" -lt 60 ]; do
    [ -f "$MARKER" ] || { echo "AutoStart marker removed; exiting"; exit 0; }
    find_volume && break
    sleep 2
    N=$((N + 1))
done

if [ -z "$VOLUME" ]; then
    echo "AutoStart timed out waiting for Toolbox SD; stock route left unchanged"
    date
    exit 1
fi

mount -uw "$VOLUME" 2>/dev/null || {
    echo "Could not mount Toolbox SD writable; cannot persist AutoStart diagnostics"
    exit 1
}
STATE="${VOLUME}/Log/CarPlayMirror"
AUTOLOGDIR="${STATE}/AutoStart"
LOG="${AUTOLOGDIR}/autostart_boot.log"
STATUS="${AUTOLOGDIR}/autostart_status.txt"
B3_STATUS="${STATE}/direct_upload_status.txt"
JAVA_STATE="${STATE}/java_mirror_state.txt"
mkdir -p "$AUTOLOGDIR" || exit 1
rm -f "${AUTOLOGDIR}/autostart_boot.previous.log"
[ -f "$LOG" ] && mv "$LOG" "${AUTOLOGDIR}/autostart_boot.previous.log"
[ -f "$BOOTSTRAP_TMP" ] && cp "$BOOTSTRAP_TMP" "${AUTOLOGDIR}/autostart_bootstrap.log" 2>/dev/null
cat "$TMPLOG" >> "$LOG" 2>/dev/null
exec >>"$LOG" 2>&1
rm -f "$TMPLOG"

echo "AutoStart diagnostics moved to SD: ${AUTOLOGDIR}"
write_status "WAITING_PREREQUISITES" 0 "Waiting for MMI services and verified controller"

# Wait for the parts that START assumes are already available. This prevents a
# one-shot early-boot race where START launches before DisplayManager or the
# firmware-version shared memory is ready.
N=0
READY=0
while [ "$N" -lt 60 ]; do
    [ -f "$MARKER" ] || { write_status "DISABLED" 0 "AutoStart marker removed"; exit 0; }

    VERSION=""
    if [ -f /net/rcc/dev/shmem/version.txt ]; then
        VERSION=$(grep 'Current train' /net/rcc/dev/shmem/version.txt 2>/dev/null | sed 's/Current train = //g' | sed -e 's|["'\'']||g' | sed 's/\r//')
    fi

    CONTROLLER_OK=0
    if [ -f "$CONTROLLER" ]; then
        set -- $(cksum "$CONTROLLER" 2>/dev/null)
        [ "$1 $2" = "$EXPECTED_CONTROLLER" ] && CONTROLLER_OK=1
    fi

    if [ "$VERSION" = "$EXPECTED_VERSION" ] && [ "$CONTROLLER_OK" -eq 1 ] && \
       [ ! -f "$LEGACY_CONTROLLER" ] && [ -x "$START" ] && [ -x /eso/bin/apps/dmdt ] && \
       /eso/bin/apps/dmdt gs >/dev/null 2>&1; then
        READY=1
        break
    fi

    sleep 2
    N=$((N + 1))
done

if [ "$READY" -ne 1 ]; then
    write_status "FAILED" 0 "Prerequisites not ready within 120 seconds"
    echo "AutoStart prerequisites did not become ready; stock route left unchanged"
    date
    exit 1
fi

echo "B3 prerequisites ready after boot stabilization"
sleep 3

ATTEMPT=1
while [ "$ATTEMPT" -le 2 ]; do
    [ -f "$MARKER" ] || { write_status "DISABLED" "$ATTEMPT" "AutoStart marker removed"; exit 0; }

    if b3_is_active; then
        write_status "ACTIVE" "$ATTEMPT" "B3 was already active and verified"
        cp "$B3_STATUS" "${AUTOLOGDIR}/b3_active_status.txt" 2>/dev/null
        cp "$JAVA_STATE" "${AUTOLOGDIR}/java_active_status.txt" 2>/dev/null
        echo "B3 already ACTIVE and verified."
        exit 0
    fi

    echo "===== AutoStart B3 attempt ${ATTEMPT}/2 ====="
    write_status "STARTING" "$ATTEMPT" "Launching production B3 START chain"
    rm -f "$B3_STATUS"
    /bin/sh "$START"
    START_RC=$?
    echo "B3 START command exited with code ${START_RC}"

    WAIT=0
    ACTIVE=0
    FAILED=0
    DETAIL=""
    while [ "$WAIT" -lt 50 ]; do
        [ -f "$MARKER" ] || { write_status "DISABLED" "$ATTEMPT" "AutoStart marker removed while starting"; exit 0; }
        if b3_is_active; then
            ACTIVE=1
            break
        fi
        if grep -q '^state=FAILED' "$B3_STATUS" 2>/dev/null; then
            FAILED=1
            DETAIL=$(sed -n 's/^detail=//p' "$B3_STATUS" 2>/dev/null | head -1)
            break
        fi
        sleep 1
        WAIT=$((WAIT + 1))
    done

    if [ "$ACTIVE" -eq 1 ]; then
        cp "$B3_STATUS" "${AUTOLOGDIR}/b3_active_status.txt" 2>/dev/null
        cp "$JAVA_STATE" "${AUTOLOGDIR}/java_active_status.txt" 2>/dev/null
        /eso/bin/apps/dmdt gs >"${AUTOLOGDIR}/dmdt_active.txt" 2>&1
        write_status "ACTIVE" "$ATTEMPT" "B3 reached verified ACTIVE context76/source58"
        echo "AutoStart SUCCESS: B3 reached verified ACTIVE state."
        date
        exit 0
    fi

    [ -n "$DETAIL" ] || DETAIL="B3 did not reach verified ACTIVE state within 50 seconds"
    echo "AutoStart attempt ${ATTEMPT} failed: ${DETAIL}"
    cp "$B3_STATUS" "${AUTOLOGDIR}/b3_failed_attempt_${ATTEMPT}.txt" 2>/dev/null
    cp "$JAVA_STATE" "${AUTOLOGDIR}/java_failed_attempt_${ATTEMPT}.txt" 2>/dev/null
    write_status "RETRYING" "$ATTEMPT" "$DETAIL"

    [ -x "$STOP" ] && /bin/sh "$STOP" >/dev/null 2>&1

    case "$DETAIL" in
        *Checksum*mismatch*|*Missing*)
            echo "Non-transient package/integrity failure; not retrying."
            break
            ;;
    esac

    ATTEMPT=$((ATTEMPT + 1))
    [ "$ATTEMPT" -le 2 ] && sleep 8
done

[ -x "$STOP" ] && /bin/sh "$STOP" >/dev/null 2>&1
export IPL_CONFIG_DIR=/etc/eso/production
/eso/bin/apps/dmdt gs >"${AUTOLOGDIR}/dmdt_after_failure.txt" 2>&1
write_status "FAILED" "$ATTEMPT" "$DETAIL"
echo "AutoStart FAILED after controlled startup attempts; stock route requested."
date
exit 1
