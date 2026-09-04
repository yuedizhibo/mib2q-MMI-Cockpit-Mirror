# Changelog

All notable project changes are documented here.

## 2026-09-05 — AutoStart and Complete Uninstall

This update keeps the proven B3 renderer-local runtime at **v52** and adds a persistent management layer around it.

### Added

- `AutoStart ON`
  - persists an MMI Cockpit Mirror boot block in `/etc/boot/startup.sh`;
  - uses project-specific BEGIN/END markers so unrelated startup customizations are not overwritten;
  - installs/checks `Cockpit_Mirror.jar` before enabling boot-time launch;
  - calls the existing `start_direct_upload_test.sh`, so automatic and manual startup share the same B3 v52 chain;
  - waits up to roughly 120 seconds for MMI services and the Toolbox SD card before giving up safely for that boot.

- `AutoStart OFF`
  - removes only the MMI Cockpit Mirror startup block and persistent AutoStart marker;
  - does not stop an already active B3 session; STOP remains the runtime stop control.

- `UNINSTALL`
  - gracefully stops active B3/B5 mirror runtime when possible;
  - restores Audi `context 74` before removing persistent components;
  - removes the AutoStart hook and marker;
  - removes `Cockpit_Mirror.jar` and any legacy `carplay_hook.jar` residue;
  - removes the mirror-specific Green Menu and installed B3/AutoStart scripts;
  - saves pre-uninstall Java JAR snapshots to the SD card for emergency rollback;
  - keeps the base MIB2 Toolbox and unrelated Toolbox functions installed;
  - requires one complete MMI reboot after completion to unload Java classes already loaded in the JVM.

### Changed

- Green Menu now exposes:

```text
START
STOP
AutoStart ON
AutoStart OFF
UNINSTALL
LOG RECORD
```

- README documentation now separates runtime STOP from full persistent UNINSTALL.
- README documentation now explains the AutoStart boot path and its fail-safe behavior.
- UNINSTALL also removes AutoStart state so the unit cannot keep attempting to launch B3 after the mirror feature is removed.

### Current limitation

- AutoStart is persistent in the head unit, but the current B3 native runtime remains SD-owned. A Toolbox SD card containing `Toolbox/carplay_mirror_test` must remain inserted for automatic mirroring to start.
- If the SD card or required MMI services are not ready within the AutoStart wait window, the boot runner exits without taking over the cockpit route.

## 2026-09-02 — B3-OPT v52

### Fixed

- Prevented `LD_PRELOAD` inheritance from the clock-host shell into child `/bin/sleep` processes.
- The main `/bin/sh` loads `libcp_mirror.so` once, then unsets `LD_PRELOAD` before running the persistent sleep loop.
- Prevented duplicate mirror workers from accumulating during long-running sessions.
- Preserved the proven `sh -c` clock-host form required to start the native server on P1404.
- Watchdog process checks use recorded PIDs with `kill -0` instead of truncated P1404 command-line text.

## 2026-08-28 — B3 stability updates

### Fixed

- Preserved the P1404 signed-division ABI used by the native renderer path.
- Bounded runtime logs and long-running FPS telemetry.
- Added log rotation with one `.previous` copy for controlled high-volume logs.

### Added

- In-vehicle mirror preview documentation.
- Initial integrated MMI Cockpit Mirror Green Menu and B3 deployment flow on top of MIB2 Toolbox.

## Runtime baseline

The current validated target remains:

- Vehicle: 2020 Audi Q5L
- Firmware: `MHI2Q_CN_AUG22_P1404`
- MMI source: renderer-local 1024×480 frame
- Cockpit destination: `context 76 / displayable 58`
- Target rate: approximately 30 FPS
