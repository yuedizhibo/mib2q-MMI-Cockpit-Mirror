# MIB2Q MMI Cockpit Mirror

English | [简体中文](README.md)

Mirrors the **complete live MMI output** of an MIB2Q head unit to the Audi Virtual Cockpit.

This project is based on [jilleb/mib2-toolbox](https://github.com/jilleb/mib2-toolbox) and adds the Green Engineering Menu, the B3-OPT v52 renderer-local full-screen mirror path, fail-safe recovery, log recording, persistent AutoStart, and a complete uninstall/restore workflow.

It is not CarPlay AltScreen and it is not a turn-by-turn icon forwarder. When the center display shows CarPlay, the cockpit shows CarPlay; when the center display shows a native MMI page, the cockpit mirrors that page as well.

## In-vehicle result

![The MMI output mirrored on the center display and Audi Virtual Cockpit](docs/images/mmi-cockpit-mirror-demo.png)

> [!CAUTION]
> This is an experimental, firmware-specific modification that writes to the MMI system partition. A mistake can cause a black screen, service faults, or require head-unit recovery. Use it only while parked, with stable power and verified backups. No contributor or referenced project accepts liability for damage to a vehicle, head unit, data, or warranty.

## Supported target

- Tested vehicle: 2020 Audi Q5L
- Firmware: `MHI2Q_CN_AUG22_P1404`
- Destination: Audi Virtual Cockpit `context 76 / displayable 58`
- Input: the MMI renderer's internal 1024×480 frame
- Output: approximately 30 FPS, 80% scale, horizontally centered and shifted up
- B3 runtime: v52
- Lifetime: until STOP, a full MMI reboot, or watchdog recovery

The scripts reject other firmware versions. Do not remove that check to try an unknown model or train.

## Green Menu

```text
MQB Coding Toolbox
└─ Customization
   └─ MMI Cockpit Mirror
      ├─ START - 30FPS persistent MMI cockpit mirror
      ├─ STOP - disable mirror and restore Audi map
      ├─ AutoStart ON - start B3 automatically after MMI boot
      ├─ AutoStart OFF - disable automatic B3 startup
      ├─ UNINSTALL - remove mirror controller and restore stock state
      └─ LOG RECORD - save current B3 status and logs
```

### START

Manually starts the current B3 v52 path. START validates the firmware, Java controller, native components, and stale runtime state before launching the clock host and renderer. The cockpit route is changed only after a real MMI frame, EGL output, and Java `context 76 / displayable 58` activation are confirmed.

### STOP

Stops the current mirror session, removes the B3 markers, waits for the Java controller to return to IDLE, and restores the stock Audi `context 74`. STOP does not uninstall anything, so START can be used again later.

### AutoStart ON

Adds a dedicated MMI Cockpit Mirror block, wrapped in BEGIN/END markers, to `/etc/boot/startup.sh`. On every complete MMI boot, the boot runner eventually calls the same `start_direct_upload_test.sh`, so automatic and manual startup use the exact same B3 v52 path.

The boot runner waits for up to roughly 120 seconds for the MMI environment and Toolbox SD card. If prerequisites never become ready, AutoStart exits for that boot and leaves the stock Audi map untouched.

> [!IMPORTANT]
> The current B3 native runtime is still SD-owned. AutoStart therefore still requires the Toolbox SD card to remain inserted. Without the SD card, the mirror will not start automatically.

### AutoStart OFF

Disables future boot-time startup by removing only this project's startup block and persistent marker. It does not stop an already active B3 session; use STOP as well if the current mirror should stop immediately.

### UNINSTALL

Completely removes MMI Cockpit Mirror itself and restores the unit to the state before this mirror feature was installed:

- stops active B3/B5 runtime state and restores Audi `context 74`;
- removes the AutoStart startup hook and persistent marker;
- removes `/mnt/app/eso/hmi/lsd/jars/Cockpit_Mirror.jar`;
- removes any remaining legacy `carplay_hook.jar`;
- removes the mirror-specific Green Menu and B3/AutoStart scripts;
- keeps the base MIB2 Toolbox installed and leaves unrelated Toolbox functions untouched;
- stores pre-uninstall Java JAR snapshots on the SD card as an emergency rollback aid.

A **complete MMI reboot is required after UNINSTALL** so previously loaded Java classes are unloaded from the running JVM.

## Installation

1. Download or clone this repository and place its complete root on a healthy FAT32 SD card.
2. Follow the [original MIB2 Toolbox installation guide](https://github.com/jilleb/mib2-toolbox#how-to-install) and complete the Toolbox software update.
3. Insert the SD card and open the `MMI Cockpit Mirror` menu.
4. On the first `START` or `AutoStart ON`, the controller is checked:
   - if `Cockpit_Mirror.jar` is missing, the current state is backed up and the controller is installed;
   - if a legacy `carplay_hook.jar` exists, it is backed up before migration;
   - after the first controller write, perform one complete MMI reboot.
5. After reboot, select START for manual mirroring or let AutoStart run automatically if it was enabled.
6. The current mirror runtime and AutoStart both require the Toolbox SD card to remain inserted.

Controller, AutoStart, install, and uninstall backup/status files are stored under:

```text
Backup/MHI2Q_CN_AUG22_P1404/MMI_Cockpit_Mirror/
```

## Relationship to CarPlay RGI

The B3 video path no longer consumes RGI navigation messages and does not start `maneuver_render`:

- no navigation application is required;
- route, maneuver, and BAP RGI data are not used;
- the complete MMI output is captured, not a CarPlay-navigation-only surface;
- the SD-owned `libcp_mirror.so` explicitly starts the native capture clock.

The Java controller that switches the cockpit channel is still derived from the JAR/plugin structure in [luka-dev/mib2q-carplay-rgi](https://github.com/luka-dev/mib2q-carplay-rgi). The public artifact is named `Cockpit_Mirror.jar`. Mirror-only mode disables RGI messages, BAP takeover, and the maneuver renderer. See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

## Fail-safe behavior

- worker, renderer, clock host, and watchdog use separate recorded PIDs;
- the watchdog checks PIDs with `kill -0` instead of relying on command lines that P1404 truncates;
- a failed first-frame, EGL, Java-context, or frame-counter gate disarms the mirror before recovery;
- STOP and fault recovery restore Audi `context 74`;
- AutoStart timeout leaves the stock route untouched;
- UNINSTALL also removes the AutoStart hook so the system cannot keep trying to launch the mirror after removal.

Do not remove the SD card or power while a system file is being written.

## Logs

`LOG RECORD` creates snapshots under:

```text
Log/CarPlayMirror/Records/B3_<timestamp>_<pid>/
```

Typical files include:

- `direct_upload_status.txt`
- `direct_upload.log`
- `direct_upload_renderer.log`
- `direct_upload_capture_host.log`
- `direct_upload_watchdog.log`
- `direct_upload_worker.log`
- `java_mirror_state.txt`
- `SUMMARY.txt`

Persistent logs are bounded. Each START truncates the previous active logs, and the watchdog rotates high-volume logs when they exceed 2 MiB, retaining one `.previous` copy.

## Repository layout

```text
Toolbox/GEM/mqb-mmiCockpitMirror.esd        Green Menu screen
Toolbox/scripts/start_direct_upload_test.sh B3 START
Toolbox/scripts/stop_direct_upload_test.sh  B3 STOP
Toolbox/scripts/autostart_cockpit_mirror_*  AutoStart ON/OFF/boot runner
Toolbox/scripts/uninstall_cockpit_mirror.sh Complete mirror uninstall/restore
Toolbox/scripts/record_b3_logs.sh            B3 log snapshots
Toolbox/carplay_mirror_test/                 QNX runtime files and fixed config
Toolbox/apps/mmi-cockpit-mirror/             Cockpit_Mirror.jar
src/native/                                  native capture and renderer injection
src/java/                                    cockpit controller and compatibility code
build-scripts/                               build and renderer-patching scripts
docs/B3_REPRODUCIBLE_CHAIN.md                reproducible implementation record
docs/V52_CLOCK_HOST_FIX.md                   v52 long-run fix note
CHANGELOG.md                                 project change history
```

## Current status

- v50 was short-run tested near 30 FPS on `MHI2Q_CN_AUG22_P1404`;
- v51 fixed long-running FPS telemetry overflow and bounded runtime log usage;
- v52 fixed clock-host `LD_PRELOAD` inheritance while keeping the proven renderer-local B3 path;
- PID liveness checks removed the previous false watchdog recovery around 40 seconds;
- the 2026-09-05 management update adds complete UNINSTALL and AutoStart ON/OFF;
- AutoStart currently still depends on the Toolbox SD card;
- multi-hour thermal stability and other firmware trains are not claimed complete.

See [CHANGELOG.md](CHANGELOG.md) for detailed changes.

## Credits and references

- [jilleb/mib2-toolbox](https://github.com/jilleb/mib2-toolbox) — complete Toolbox base, SD layout, software-update workflow, and Green Menu framework.
- [luka-dev/mib2q-carplay-rgi](https://github.com/luka-dev/mib2q-carplay-rgi) — MHI2Q CarPlay/RGI research, Java plugin structure, QNX hooks, and cockpit rendering reference.
- [Lanye-z/mib2-toolbox-carplay-rgi](https://github.com/Lanye-z/mib2-toolbox-carplay-rgi) — earlier Toolbox/RGI integration and deployment reference.

The primary additions in this repository include renderer-local full-MMI texture capture, displayable-58 output, persistent 30-FPS control, VIEW recovery, PID watchdog behavior, in-car logging/rollback, AutoStart, and complete mirror uninstall management.

## License

The original MIB2 Toolbox retains its [MIT License](LICENSE). Newly authored scripts and source in this project are offered under the same MIT terms. Third-party-derived files, reverse-engineering material, and binaries do not automatically become MIT-licensed; see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
