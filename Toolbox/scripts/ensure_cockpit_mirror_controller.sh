#!/bin/sh
export PATH=/proc/boot:/bin:/usr/bin:/usr/sbin:/sbin:/mnt/app/armle/bin:/mnt/app/armle/usr/bin:$PATH
if [ "$_" = "/bin/on" ]; then BASE="$0"; else BASE="$_"; fi
SCRIPTDIR=$( cd -P -- "$(dirname -- "$(command -v -- "$BASE")")" && pwd -P )
. "${SCRIPTDIR}/util_info.sh"
. "${SCRIPTDIR}/util_mountsd.sh"
[ -n "$VOLUME" ] || { echo "No SD-card found"; exit 1; }

EXPECTED_VERSION="MHI2Q_CN_AUG22_P1404"
EXPECTED_JAR="140001591 112564"
SOURCE="${VOLUME}/Toolbox/apps/mmi-cockpit-mirror/Cockpit_Mirror.jar"
TARGET="/mnt/app/eso/hmi/lsd/jars/Cockpit_Mirror.jar"
LEGACY="/mnt/app/eso/hmi/lsd/jars/carplay_hook.jar"
BACKUP="${VOLUME}/Backup/${VERSION}/MMI_Cockpit_Mirror"
TARGET_SNAPSHOT="${BACKUP}/Cockpit_Mirror.pre_install.jar"
LEGACY_SNAPSHOT="${BACKUP}/carplay_hook.pre_migration.jar"
ORIGINAL_LEGACY="${BACKUP}/carplay_hook.original.jar"
LOG="${BACKUP}/install_controller.log"
STATUS="${BACKUP}/controller_status.txt"
ACTIVE=0
TARGET_EXISTED=0
LEGACY_EXISTED=0

mkdir -p "$BACKUP" || exit 1
exec 3>&1
exec >>"$LOG" 2>&1
log() { echo "$*"; echo "$*" >&3; }
remount_ro() { mount -ur /mnt/app 2>/dev/null; }

rollback() {
    trap - 1 2 15
    [ "$ACTIVE" -eq 1 ] || return 0
    log "Rolling back Cockpit Mirror controller installation"
    mount -uw /mnt/app 2>/dev/null || return 1
    if [ "$TARGET_EXISTED" -eq 1 ]; then
        cp "$TARGET_SNAPSHOT" "${TARGET}.rollback" || return 1
        chmod 644 "${TARGET}.rollback" || return 1
        mv "${TARGET}.rollback" "$TARGET" || return 1
    else
        rm -f "$TARGET" "${TARGET}.tmp"
    fi
    if [ "$LEGACY_EXISTED" -eq 1 ]; then
        cp "$LEGACY_SNAPSHOT" "${LEGACY}.rollback" || return 1
        chmod 644 "${LEGACY}.rollback" || return 1
        mv "${LEGACY}.rollback" "$LEGACY" || return 1
    fi
    sync
    remount_ro
}

fail() {
    log "ERROR: $*"
    rollback || log "ROLLBACK INCOMPLETE: do not reboot"
    exit 1
}
trap 'fail "Installation interrupted"' 1 2 15

log "===== MMI Cockpit Mirror controller check ====="
[ "$VERSION" = "$EXPECTED_VERSION" ] || fail "This build is only for ${EXPECTED_VERSION}"
[ -f "$SOURCE" ] || fail "Missing Toolbox/apps/mmi-cockpit-mirror/Cockpit_Mirror.jar"
set -- $(cksum "$SOURCE")
[ "$1 $2" = "$EXPECTED_JAR" ] || fail "Cockpit_Mirror.jar checksum mismatch"

TARGET_OK=0
if [ -f "$TARGET" ]; then
    set -- $(cksum "$TARGET" 2>/dev/null)
    [ "$1 $2" = "$EXPECTED_JAR" ] && TARGET_OK=1
fi
if [ "$TARGET_OK" -eq 1 ] && [ ! -f "$LEGACY" ]; then
    log "Cockpit_Mirror.jar is already installed and verified."
    exit 0
fi

if [ -f "$TARGET" ]; then
    TARGET_EXISTED=1
    cp "$TARGET" "$TARGET_SNAPSHOT" || fail "Could not snapshot existing Cockpit_Mirror.jar"
fi
if [ -f "$LEGACY" ]; then
    LEGACY_EXISTED=1
    cp "$LEGACY" "$LEGACY_SNAPSHOT" || fail "Could not snapshot legacy carplay_hook.jar"
    if [ ! -f "$ORIGINAL_LEGACY" ]; then
        cp "$LEGACY" "$ORIGINAL_LEGACY" || fail "Could not create permanent legacy JAR backup"
    fi
fi

ACTIVE=1
mount -uw /mnt/app || fail "Could not mount /mnt/app read-write"
cp "$SOURCE" "${TARGET}.tmp" || fail "Could not stage Cockpit_Mirror.jar"
chmod 644 "${TARGET}.tmp" || fail "Could not chmod staged controller"
mv "${TARGET}.tmp" "$TARGET" || fail "Could not install Cockpit_Mirror.jar"
set -- $(cksum "$TARGET")
[ "$1 $2" = "$EXPECTED_JAR" ] || fail "Installed controller verification failed"

# Do not leave two JARs exporting the same CarPlay/Cluster classes. The legacy
# file is preserved on the SD card first, and rollback restores it on failure.
rm -f "$LEGACY" || fail "Could not remove duplicate legacy carplay_hook.jar"
sync || fail "sync failed"
remount_ro || fail "Could not remount /mnt/app read-only"
ACTIVE=0
rm -f "$TARGET_SNAPSHOT" "$LEGACY_SNAPSHOT"
trap - 1 2 15
{
    echo "state=REBOOT_REQUIRED"
    echo "installed=${TARGET}"
    echo "legacy_removed=${LEGACY_EXISTED}"
    date
} > "$STATUS"
sync
log "Cockpit_Mirror.jar installed and verified."
log "Perform one complete MMI reboot, then select START again."
exit 10
