#!/bin/sh
export PATH=/proc/boot:/bin:/usr/bin:/usr/sbin:/sbin:/mnt/app/armle/bin:/mnt/app/armle/usr/bin:$PATH
if [ "$_" = "/bin/on" ]; then BASE="$0"; else BASE="$_"; fi
SCRIPTDIR=$( cd -P -- "$(dirname -- "$(command -v -- "$BASE")")" && pwd -P )
STARTUP="/etc/boot/startup.sh"
MARKER="${SCRIPTDIR}/.mmi_cockpit_mirror_autostart"
BEGIN_MARK="# MMI COCKPIT MIRROR AUTOSTART BEGIN"

[ -f "$STARTUP" ] || { echo "Missing $STARTUP"; exit 1; }

echo "AutoStart OFF: disabling persistent B3 startup..."
mount -uw /mnt/system 2>/dev/null || { echo "Could not mount /mnt/system read-write"; exit 1; }
if grep -qF "$BEGIN_MARK" "$STARTUP" 2>/dev/null; then
    sed -i '/# MMI COCKPIT MIRROR AUTOSTART BEGIN/,/# MMI COCKPIT MIRROR AUTOSTART END/d' "$STARTUP" || {
        mount -ur /mnt/system 2>/dev/null
        echo "Could not remove AutoStart block from startup.sh"
        exit 1
    }
fi
sync
mount -ur /mnt/system 2>/dev/null || { echo "Could not remount /mnt/system read-only"; exit 1; }
[ ! -f "$STARTUP" ] || ! grep -qF "$BEGIN_MARK" "$STARTUP" 2>/dev/null || {
    echo "AutoStart block still present after removal"
    exit 1
}

mount -uw /mnt/app 2>/dev/null || { echo "Could not mount /mnt/app read-write"; exit 1; }
rm -f "$MARKER"
sync
mount -ur /mnt/app 2>/dev/null || { echo "Could not remount /mnt/app read-only"; exit 1; }

rm -f /tmp/mmi_cockpit_mirror_autostart_bootstrap.log \
      /tmp/mmi_cockpit_mirror_autostart_runner.log

# Preserve an OFF record on the Toolbox SD when it is present, but never make
# disabling AutoStart depend on the SD card being available.
VOLUME=""
[ -d /net/mmx/fs/sda0/Toolbox ] && VOLUME="/net/mmx/fs/sda0"
[ -z "$VOLUME" ] && [ -d /net/mmx/fs/sdb0/Toolbox ] && VOLUME="/net/mmx/fs/sdb0"
if [ -n "$VOLUME" ]; then
    mount -uw "$VOLUME" 2>/dev/null || :
    AUTOLOGDIR="${VOLUME}/Log/CarPlayMirror/AutoStart"
    mkdir -p "$AUTOLOGDIR" 2>/dev/null
    if [ -d "$AUTOLOGDIR" ]; then
        {
            echo "version=autostart-config-v2"
            echo "state=DISABLED"
            echo "detail=AutoStart startup block and persistent marker removed"
            echo "startup=${STARTUP}"
            echo "marker=${MARKER}"
            date
        } > "${AUTOLOGDIR}/autostart_config_status.txt"
        sync
    fi
fi

echo "AutoStart OFF: disabled."
echo "Future MMI boots will stay on the normal Audi route until START is selected manually."
echo "If B3 is currently active, it keeps running; use STOP if you also want to stop the current session."
exit 0
