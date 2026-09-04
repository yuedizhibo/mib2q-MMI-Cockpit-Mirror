#!/bin/sh
export PATH=/proc/boot:/bin:/usr/bin:/usr/sbin:/sbin:/mnt/app/armle/bin:/mnt/app/armle/usr/bin:$PATH
if [ "$_" = "/bin/on" ]; then BASE="$0"; else BASE="$_"; fi
SCRIPTDIR=$( cd -P -- "$(dirname -- "$(command -v -- "$BASE")")" && pwd -P )
. "${SCRIPTDIR}/util_info.sh"
. "${SCRIPTDIR}/util_mountsd.sh"
[ -n "$VOLUME" ] || { echo "No SD-card found"; exit 1; }

EXPECTED_VERSION="MHI2Q_CN_AUG22_P1404"
STARTUP="/etc/boot/startup.sh"
MARKER="${SCRIPTDIR}/.mmi_cockpit_mirror_autostart"
RUNNER="${SCRIPTDIR}/autostart_cockpit_mirror_boot.sh"
BEGIN_MARK="# MMI COCKPIT MIRROR AUTOSTART BEGIN"
BACKUP="${VOLUME}/Backup/${VERSION}/MMI_Cockpit_Mirror"
STARTUP_BACKUP="${BACKUP}/startup.pre_cockpit_autostart.sh"
STATUS="${BACKUP}/autostart_status.txt"
CONTROLLER_RESULT=0

mkdir -p "$BACKUP" || exit 1
[ "$VERSION" = "$EXPECTED_VERSION" ] || { echo "Wrong firmware: $VERSION"; exit 1; }
[ -f "$STARTUP" ] || { echo "Missing $STARTUP"; exit 1; }
[ -f "$RUNNER" ] || { echo "Missing autostart boot runner"; exit 1; }

"${SCRIPTDIR}/ensure_cockpit_mirror_controller.sh"
CONTROLLER_RESULT=$?
case "$CONTROLLER_RESULT" in
    0|10) ;;
    *) echo "Controller preparation failed: $CONTROLLER_RESULT"; exit "$CONTROLLER_RESULT" ;;
esac

if [ ! -f "$STARTUP_BACKUP" ]; then
    cp "$STARTUP" "$STARTUP_BACKUP" || { echo "Could not back up startup.sh"; exit 1; }
fi

mount -uw /mnt/system 2>/dev/null || { echo "Could not mount /mnt/system read-write"; exit 1; }
if ! grep -qF "$BEGIN_MARK" "$STARTUP" 2>/dev/null; then
    cat >> "$STARTUP" <<'EOF'

# MMI COCKPIT MIRROR AUTOSTART BEGIN
if [ -f /mnt/app/eso/hmi/engdefs/scripts/mqb/.mmi_cockpit_mirror_autostart ] && \
   [ -f /mnt/app/eso/hmi/engdefs/scripts/mqb/autostart_cockpit_mirror_boot.sh ]; then
    /bin/sh /mnt/app/eso/hmi/engdefs/scripts/mqb/autostart_cockpit_mirror_boot.sh &
fi
# MMI COCKPIT MIRROR AUTOSTART END
EOF
fi
sync
mount -ur /mnt/system 2>/dev/null || { echo "Could not remount /mnt/system read-only"; exit 1; }
grep -qF "$BEGIN_MARK" "$STARTUP" 2>/dev/null || { echo "AutoStart boot block verification failed"; exit 1; }

mount -uw /mnt/app 2>/dev/null || { echo "Could not mount /mnt/app read-write"; exit 1; }
touch "$MARKER" || { mount -ur /mnt/app 2>/dev/null; echo "Could not create AutoStart marker"; exit 1; }
sync
mount -ur /mnt/app 2>/dev/null || { echo "Could not remount /mnt/app read-only"; exit 1; }

{
    echo "state=ENABLED"
    echo "startup=${STARTUP}"
    echo "requires_sd_card=1"
    date
} > "$STATUS"
sync

echo "AutoStart ON: enabled."
echo "Every complete MMI boot will automatically execute the B3 START chain."
echo "Keep the Toolbox SD card inserted because the current B3 native runtime is SD-owned."
if [ "$CONTROLLER_RESULT" -eq 10 ]; then
    echo "Cockpit_Mirror.jar was installed. Perform one COMPLETE MMI reboot now."
else
    echo "The setting takes effect on the next complete MMI boot."
fi
exit 0
