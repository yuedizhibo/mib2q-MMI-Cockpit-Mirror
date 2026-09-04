#!/bin/sh
export PATH=/proc/boot:/bin:/usr/bin:/usr/sbin:/sbin:$PATH
SCRIPTDIR="/mnt/app/eso/hmi/engdefs/scripts/mqb"
MARKER="${SCRIPTDIR}/.mmi_cockpit_mirror_autostart"
START="${SCRIPTDIR}/start_direct_upload_test.sh"
LOG="/tmp/mmi_cockpit_mirror_autostart.log"

exec >>"$LOG" 2>&1
echo "===== MMI Cockpit Mirror AutoStart boot runner ====="
date

# startup.sh runs before every MMI service and filesystem is necessarily ready.
# Wait for the Toolbox SD and the installed B3 entry point rather than racing
# the renderer/Java stack during early boot. If readiness never arrives, leave
# the stock Audi map untouched and simply give up for this boot.
N=0
while [ "$N" -lt 60 ]; do
    [ -f "$MARKER" ] || { echo "AutoStart marker removed; exiting"; exit 0; }

    if [ -x "$START" ] && [ -x /eso/bin/apps/dmdt ] && \
       { [ -d /net/mmx/fs/sda0/Toolbox/carplay_mirror_test ] || \
         [ -d /net/mmx/fs/sdb0/Toolbox/carplay_mirror_test ]; }; then
        echo "B3 prerequisites ready after $((N * 2)) seconds"
        /bin/sh "$START"
        RESULT=$?
        echo "B3 START exited with code ${RESULT}"
        date
        exit "$RESULT"
    fi

    sleep 2
    N=$((N + 1))
done

echo "AutoStart timed out waiting for Toolbox SD/MMI readiness; stock route left unchanged"
date
exit 0
