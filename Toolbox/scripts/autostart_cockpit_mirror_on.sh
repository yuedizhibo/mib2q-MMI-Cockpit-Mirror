#!/bin/sh
export PATH=/proc/boot:/bin:/usr/bin:/usr/sbin:/sbin:/mnt/app/armle/bin:/mnt/app/armle/usr/bin:$PATH
if [ "$_" = "/bin/on" ]; then BASE="$0"; else BASE="$_"; fi
SCRIPTDIR=$( cd -P -- "$(dirname -- "$(command -v -- "$BASE")")" && pwd -P )
. "${SCRIPTDIR}/util_info.sh"
. "${SCRIPTDIR}/util_mountsd.sh"
[ -n "$VOLUME" ] || { echo "No SD-card found"; exit 1; }

EXPECTED_VERSION="MHI2Q_CN_AUG22_P1404"
EXPECTED_CONTROLLER="140001591 112564"
CONTROLLER="/mnt/app/eso/hmi/lsd/jars/Cockpit_Mirror.jar"
LEGACY_CONTROLLER="/mnt/app/eso/hmi/lsd/jars/carplay_hook.jar"
STARTUP="/etc/boot/startup.sh"
MARKER="${SCRIPTDIR}/.mmi_cockpit_mirror_autostart"
RUNNER="${SCRIPTDIR}/autostart_cockpit_mirror_boot.sh"
BEGIN_MARK="# MMI COCKPIT MIRROR AUTOSTART BEGIN"
BACKUP="${VOLUME}/Backup/${VERSION}/MMI_Cockpit_Mirror"
STARTUP_BACKUP="${BACKUP}/startup.pre_cockpit_autostart.sh"
AUTOLOGDIR="${VOLUME}/Log/CarPlayMirror/AutoStart"
CONFIG_STATUS="${AUTOLOGDIR}/autostart_config_status.txt"
CONTROLLER_RESULT=0

mkdir -p "$BACKUP" "$AUTOLOGDIR" || exit 1
[ "$VERSION" = "$EXPECTED_VERSION" ] || { echo "Wrong firmware: $VERSION"; exit 1; }
[ -f "$STARTUP" ] || { echo "Missing $STARTUP"; exit 1; }
[ -f "$RUNNER" ] || { echo "Missing autostart boot runner"; exit 1; }

write_config_status() {
    {
        echo "version=autostart-config-v2"
        echo "state=$1"
        echo "detail=$2"
        echo "startup=${STARTUP}"
        echo "marker=${MARKER}"
        echo "log_dir=${AUTOLOGDIR}"
        echo "requires_sd_card=1"
        date
    } > "$CONFIG_STATUS"
    sync
}

remove_boot_block_best_effort() {
    mount -uw /mnt/system 2>/dev/null || return 1
    sed -i '/# MMI COCKPIT MIRROR AUTOSTART BEGIN/,/# MMI COCKPIT MIRROR AUTOSTART END/d' "$STARTUP" 2>/dev/null
    sync
    mount -ur /mnt/system 2>/dev/null
}

# Match manual START behavior: if the persistent controller already installed
# on the head unit is the exact verified build and no legacy duplicate exists,
# AutoStart does not need to inspect or reinstall the SD-card source JAR.
CONTROLLER_OK=0
if [ -f "$CONTROLLER" ]; then
    set -- $(cksum "$CONTROLLER" 2>/dev/null)
    [ "$1 $2" = "$EXPECTED_CONTROLLER" ] && CONTROLLER_OK=1
fi
if [ "$CONTROLLER_OK" -eq 1 ] && [ ! -f "$LEGACY_CONTROLLER" ]; then
    echo "Cockpit_Mirror.jar is already installed and verified."
    CONTROLLER_RESULT=0
else
    "${SCRIPTDIR}/ensure_cockpit_mirror_controller.sh"
    CONTROLLER_RESULT=$?
    case "$CONTROLLER_RESULT" in
        0|10) ;;
        *)
            write_config_status "FAILED" "Controller preparation failed: ${CONTROLLER_RESULT}"
            echo "Controller preparation failed: $CONTROLLER_RESULT"
            exit "$CONTROLLER_RESULT"
            ;;
    esac
fi

if [ ! -f "$STARTUP_BACKUP" ]; then
    cp "$STARTUP" "$STARTUP_BACKUP" || {
        write_config_status "FAILED" "Could not back up startup.sh"
        echo "Could not back up startup.sh"
        exit 1
    }
fi

# Always replace our marked block, even when AutoStart was enabled by an older
# project revision. This upgrades existing installations to the delayed
# bootstrap form instead of leaving a one-shot early-boot race in startup.sh.
mount -uw /mnt/system 2>/dev/null || {
    write_config_status "FAILED" "Could not mount /mnt/system read-write"
    echo "Could not mount /mnt/system read-write"
    exit 1
}
sed -i '/# MMI COCKPIT MIRROR AUTOSTART BEGIN/,/# MMI COCKPIT MIRROR AUTOSTART END/d' "$STARTUP" || {
    mount -ur /mnt/system 2>/dev/null
    write_config_status "FAILED" "Could not remove previous AutoStart block"
    echo "Could not remove previous AutoStart block"
    exit 1
}
cat >> "$STARTUP" <<'EOF'

# MMI COCKPIT MIRROR AUTOSTART BEGIN
(
    N=0
    while [ "$N" -lt 120 ]; do
        if [ -f /mnt/app/eso/hmi/engdefs/scripts/mqb/.mmi_cockpit_mirror_autostart ] && \
           [ -f /mnt/app/eso/hmi/engdefs/scripts/mqb/autostart_cockpit_mirror_boot.sh ]; then
            /bin/sh /mnt/app/eso/hmi/engdefs/scripts/mqb/autostart_cockpit_mirror_boot.sh
            exit $?
        fi
        /bin/sleep 1
        N=$((N + 1))
    done
    echo "AutoStart bootstrap timed out waiting for /mnt/app runner/marker"
) >/tmp/mmi_cockpit_mirror_autostart_bootstrap.log 2>&1 &
# MMI COCKPIT MIRROR AUTOSTART END
EOF
sync
mount -ur /mnt/system 2>/dev/null || {
    write_config_status "FAILED" "Could not remount /mnt/system read-only"
    echo "Could not remount /mnt/system read-only"
    exit 1
}

grep -qF "$BEGIN_MARK" "$STARTUP" 2>/dev/null || {
    write_config_status "FAILED" "AutoStart boot block verification failed"
    echo "AutoStart boot block verification failed"
    exit 1
}

mount -uw /mnt/app 2>/dev/null || {
    remove_boot_block_best_effort
    write_config_status "FAILED" "Could not mount /mnt/app read-write"
    echo "Could not mount /mnt/app read-write"
    exit 1
}
touch "$MARKER" || {
    mount -ur /mnt/app 2>/dev/null
    remove_boot_block_best_effort
    write_config_status "FAILED" "Could not create AutoStart marker"
    echo "Could not create AutoStart marker"
    exit 1
}
sync
mount -ur /mnt/app 2>/dev/null || {
    write_config_status "FAILED" "Could not remount /mnt/app read-only"
    echo "Could not remount /mnt/app read-only"
    exit 1
}

write_config_status "ENABLED" "Delayed bootstrap installed; next complete MMI boot will verify B3 ACTIVE"

echo "AutoStart ON: enabled."
echo "Every complete MMI boot will automatically execute and verify the B3 START chain."
echo "AutoStart diagnostics will be saved under Log/CarPlayMirror/AutoStart on the Toolbox SD card."
echo "Keep the Toolbox SD card inserted because the current B3 native runtime is SD-owned."
if [ "$CONTROLLER_RESULT" -eq 10 ]; then
    echo "Cockpit_Mirror.jar was installed. Perform one COMPLETE MMI reboot now."
else
    echo "The setting takes effect on the next complete MMI boot."
fi
exit 0
