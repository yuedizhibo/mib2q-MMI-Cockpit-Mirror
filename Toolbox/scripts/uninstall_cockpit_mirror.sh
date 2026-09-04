#!/bin/sh
export PATH=/proc/boot:/bin:/usr/bin:/usr/sbin:/sbin:/mnt/app/armle/bin:/mnt/app/armle/usr/bin:$PATH
if [ "$_" = "/bin/on" ]; then BASE="$0"; else BASE="$_"; fi
SCRIPTDIR=$( cd -P -- "$(dirname -- "$(command -v -- "$BASE")")" && pwd -P )
. "${SCRIPTDIR}/util_info.sh"
. "${SCRIPTDIR}/util_mountsd.sh"
[ -n "$VOLUME" ] || { echo "No SD-card found"; exit 1; }

APP="${VOLUME}/Toolbox/carplay_mirror_test"
STATE="${VOLUME}/Log/CarPlayMirror"
BACKUP="${VOLUME}/Backup/${VERSION}/MMI_Cockpit_Mirror"
TARGET="/mnt/app/eso/hmi/lsd/jars/Cockpit_Mirror.jar"
LEGACY="/mnt/app/eso/hmi/lsd/jars/carplay_hook.jar"
TARGET_SNAPSHOT="${BACKUP}/Cockpit_Mirror.pre_uninstall.jar"
LEGACY_SNAPSHOT="${BACKUP}/carplay_hook.pre_uninstall.jar"
LOG="${BACKUP}/uninstall_controller.log"
STATUS="${BACKUP}/uninstall_status.txt"
MENU="/mnt/app/eso/hmi/engdefs/mqb-mmiCockpitMirror.esd"
INSTALLED_SCRIPTS="/mnt/app/eso/hmi/engdefs/scripts/mqb"
STARTUP="/etc/boot/startup.sh"
AUTOSTART_MARKER="${INSTALLED_SCRIPTS}/.mmi_cockpit_mirror_autostart"
AUTOSTART_BEGIN="# MMI COCKPIT MIRROR AUTOSTART BEGIN"
TARGET_EXISTED=0
LEGACY_EXISTED=0
ACTIVE=0

mkdir -p "$BACKUP" || exit 1
exec 3>&1
exec >>"$LOG" 2>&1
log() { echo "$*"; echo "$*" >&3; }
remount_ro() { mount -ur /mnt/app 2>/dev/null; }

safe_kill_file() {
    FILE="$1"
    [ -f "$FILE" ] || return 0
    PID_VALUE=$(cat "$FILE" 2>/dev/null)
    case "$PID_VALUE" in *[!0-9]*|'') return 0 ;; esac
    kill -0 "$PID_VALUE" 2>/dev/null && kill "$PID_VALUE" 2>/dev/null
}

restore_stock_route() {
    export IPL_CONFIG_DIR=/etc/eso/production
    /eso/bin/apps/dmdt dc 76 58 >>"$LOG" 2>&1
    /eso/bin/apps/dmdt sc 1 72 >>"$LOG" 2>&1
    sleep 1
    /eso/bin/apps/dmdt sc 1 74 >>"$LOG" 2>&1
}

remove_autostart() {
    [ -f "$STARTUP" ] || return 0
    mount -uw /mnt/system 2>/dev/null || return 1
    if grep -qF "$AUTOSTART_BEGIN" "$STARTUP" 2>/dev/null; then
        sed -i '/# MMI COCKPIT MIRROR AUTOSTART BEGIN/,/# MMI COCKPIT MIRROR AUTOSTART END/d' "$STARTUP" || {
            mount -ur /mnt/system 2>/dev/null
            return 1
        }
    fi
    sync
    mount -ur /mnt/system 2>/dev/null || return 1
    ! grep -qF "$AUTOSTART_BEGIN" "$STARTUP" 2>/dev/null
}

rollback() {
    trap - 1 2 15
    [ "$ACTIVE" -eq 1 ] || return 0
    log "Rolling back uninstall because a write step failed"
    mount -uw /mnt/app 2>/dev/null || return 1
    if [ "$TARGET_EXISTED" -eq 1 ] && [ -f "$TARGET_SNAPSHOT" ]; then
        cp "$TARGET_SNAPSHOT" "${TARGET}.rollback" || return 1
        chmod 644 "${TARGET}.rollback" || return 1
        mv "${TARGET}.rollback" "$TARGET" || return 1
    fi
    if [ "$LEGACY_EXISTED" -eq 1 ] && [ -f "$LEGACY_SNAPSHOT" ]; then
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
    {
        echo "state=FAILED"
        echo "detail=$*"
        date
    } > "$STATUS"
    sync
    exit 1
}
trap 'fail "Uninstall interrupted"' 1 2 15

log "===== MMI Cockpit Mirror complete uninstall ====="
log "Firmware reported by unit: ${VERSION}"
log "Stopping B3/B5 runtime and restoring the stock Audi cockpit route first."

if [ -x "${SCRIPTDIR}/stop_direct_upload_test.sh" ]; then
    "${SCRIPTDIR}/stop_direct_upload_test.sh" >/dev/null 2>&1 || :
fi
if [ -f "${APP}/ARMED" ] && [ -x "${SCRIPTDIR}/stop_carplay_mirror_test.sh" ]; then
    "${SCRIPTDIR}/stop_carplay_mirror_test.sh" >/dev/null 2>&1 || :
fi

rm -f "${APP}/DIRECT_UPLOAD_TEST" "${APP}/DIRECT16_SHARE_TEST" \
      "${APP}/DIRECT16_TEST" "${APP}/ARMED" "${APP}/FPS10" \
      "${APP}/FPS20" "${APP}/FPS30" "${STATE}/receiver_ready" \
      "${STATE}/worker_heartbeat"
safe_kill_file "${STATE}/direct_upload_renderer.pid"
safe_kill_file "${STATE}/direct_upload_capture.pid"
safe_kill_file "${STATE}/direct_upload_worker.pid"
safe_kill_file "${STATE}/direct_upload_watchdog.pid"
restore_stock_route
sync

log "Removing persistent AutoStart hook from startup.sh."
remove_autostart || fail "Could not remove MMI Cockpit Mirror AutoStart block"

if [ -f "$TARGET" ]; then
    TARGET_EXISTED=1
    cp "$TARGET" "$TARGET_SNAPSHOT" || fail "Could not back up Cockpit_Mirror.jar before removal"
fi
if [ -f "$LEGACY" ]; then
    LEGACY_EXISTED=1
    cp "$LEGACY" "$LEGACY_SNAPSHOT" || fail "Could not back up legacy carplay_hook.jar before removal"
fi

ACTIVE=1
mount -uw /mnt/app || fail "Could not mount /mnt/app read-write"

rm -f "$AUTOSTART_MARKER" || fail "Could not remove AutoStart marker"
rm -f "$TARGET" "${TARGET}.tmp" "${TARGET}.rollback" || fail "Could not remove Cockpit_Mirror.jar"
rm -f "$LEGACY" "${LEGACY}.tmp" "${LEGACY}.rollback" || fail "Could not remove legacy carplay_hook.jar"
[ ! -e "$TARGET" ] || fail "Cockpit_Mirror.jar still exists after removal"
[ ! -e "$LEGACY" ] || fail "carplay_hook.jar still exists after removal"

rm -f "$MENU" || fail "Could not remove MMI Cockpit Mirror GEM menu"
for NAME in \
    start_direct_upload_test.sh \
    stop_direct_upload_test.sh \
    direct_upload_test_worker.sh \
    direct_upload_restore_watchdog.sh \
    record_b3_logs.sh \
    ensure_cockpit_mirror_controller.sh \
    autostart_cockpit_mirror_boot.sh \
    autostart_cockpit_mirror_on.sh \
    autostart_cockpit_mirror_off.sh \
    toggle_cockpit_mirror_autostart.sh
 do
    rm -f "${INSTALLED_SCRIPTS}/${NAME}" || fail "Could not remove installed script ${NAME}"
 done

rm -f "${INSTALLED_SCRIPTS}/uninstall_cockpit_mirror.sh" || fail "Could not remove installed uninstall script"

sync || fail "sync failed"
remount_ro || fail "Could not remount /mnt/app read-only"
ACTIVE=0
trap - 1 2 15

rm -f "${STATE}/direct_upload_worker.pid" "${STATE}/direct_upload_renderer.pid" \
      "${STATE}/direct_upload_capture.pid" "${STATE}/direct_upload_watchdog.pid"
{
    echo "state=REBOOT_REQUIRED"
    echo "cockpit_mirror_jar=REMOVED"
    echo "legacy_carplay_hook_jar=REMOVED"
    echo "autostart=REMOVED"
    echo "mirror_menu=REMOVED"
    echo "mirror_scripts=REMOVED"
    echo "stock_route=context74"
    date
} > "$STATUS"
sync

log "MMI Cockpit Mirror persistent files and AutoStart hook were removed from the unit."
log "Cockpit route was restored to Audi context 74."
log "Perform one COMPLETE MMI reboot now to unload the previously loaded Java classes."
log "After reboot the unit is back to the pre-mirror state; the base MIB2 Toolbox is left intact."
exit 0
