#!/bin/sh
export PATH=/proc/boot:/bin:/usr/bin:/usr/sbin:/sbin:$PATH
if [ "$_" = "/bin/on" ]; then BASE="$0"; else BASE="$_"; fi
SCRIPTDIR=$( cd -P -- "$(dirname -- "$(command -v -- "$BASE")")" && pwd -P )
. "${SCRIPTDIR}/util_mountsd.sh"
[ -n "$VOLUME" ] || { echo "No SD-card found"; exit 1; }
APP="${VOLUME}/Toolbox/carplay_mirror_test"
STATE="${VOLUME}/Log/CarPlayMirror"
echo "===== B3-OPT OFF: graceful persistent 30-FPS stop ====="
rm -f "${APP}/DIRECT_UPLOAD_TEST" "${APP}/DIRECT16_SHARE_TEST" \
      "${APP}/DIRECT16_TEST" "${APP}/ARMED" "${STATE}/receiver_ready" \
      "${APP}/FPS10" "${APP}/FPS20" "${APP}/FPS30"
sync
N=0
while [ "$N" -lt 18 ]; do
    grep -Eq '^state=(DISABLED|FINISHED_SAFE|FAILED)' "${STATE}/direct_upload_status.txt" 2>/dev/null && break
    sleep 1
    N=$((N + 1))
done
export IPL_CONFIG_DIR=/etc/eso/production
/eso/bin/apps/dmdt dc 76 58 >>"${STATE}/direct_upload_timeline.log" 2>&1
/eso/bin/apps/dmdt sc 1 72 >>"${STATE}/direct_upload_timeline.log" 2>&1
sleep 1
/eso/bin/apps/dmdt sc 1 74 >>"${STATE}/direct_upload_timeline.log" 2>&1
[ -f "${STATE}/direct_upload_status.txt" ] && cat "${STATE}/direct_upload_status.txt"
echo "B3-OPT stopped; Audi map restore requested."
exit 0
