# Changelog

All notable project changes are documented here.

## 2026-09-05 — AutoStart boot-chain hardening and SD diagnostics

### Fixed

- Hardened the complete boot-time path from `/etc/boot/startup.sh` to a verified B3 `ACTIVE` state.
- `AutoStart ON` now replaces any older project-marked startup block with a delayed bootstrap loop. This avoids losing AutoStart when `startup.sh` reaches the hook before `/mnt/app` and the installed runner are ready.
- The boot runner now waits for the Toolbox SD card, firmware shared-memory information, the verified installed `Cockpit_Mirror.jar`, the absence of the legacy duplicate controller, and a responsive DisplayManager before launching B3.
- AutoStart no longer treats the synchronous exit code of `start_direct_upload_test.sh` as proof that mirroring succeeded. It now requires the live B3 marker, worker/renderer/capture PIDs, Java `ACTIVE`, `nativeContext=76 source=58 fps=30`, and a real `dmdt` report of context 76.
- A failed boot-time attempt saves the failure evidence, requests the normal STOP/stock-route recovery, waits briefly, and performs at most one controlled retry. Package/checksum failures are treated as non-transient and are not retried.
- If all attempts fail, the runner requests the stock Audi route and records a final `FAILED` AutoStart state instead of silently exiting after a launcher-level success.

### AutoStart diagnostics

- AutoStart boot diagnostics are now persisted to the Toolbox SD card under:

```text
Log/CarPlayMirror/AutoStart/
```

- The directory can contain:
  - `autostart_config_status.txt`
  - `autostart_bootstrap.log`
  - `autostart_boot.log`
  - `autostart_boot.previous.log`
  - `autostart_status.txt`
  - `b3_active_status.txt`
  - `java_active_status.txt`
  - `dmdt_active.txt`
  - per-attempt failure snapshots and `dmdt_after_failure.txt` when startup fails.
- `/tmp` is used only as an unavoidable early-boot buffer before the SD card exists; the runner copies that evidence to the SD as soon as the Toolbox volume is writable.
- `LOG RECORD` now includes the complete `Log/CarPlayMirror/AutoStart/` directory in its snapshot, so one manual log record contains both normal B3 and boot-time AutoStart evidence.
- `AutoStart OFF` records a disabled configuration status to the SD when the Toolbox card is available, but disabling itself does not depend on the SD card.

### Update note

- Existing AutoStart users should re-sync/install the latest Toolbox scripts and select `AutoStart ON` once again. This replaces the old startup block with the delayed-bootstrap version; no UNINSTALL is required.

## 2026-09-05 — AutoStart controller verification fix

### Fixed

- Fixed `AutoStart ON` failing with `Cockpit_Mirror.jar checksum mismatch` even when the head unit already had the exact verified controller installed and manual START worked normally.
- `AutoStart ON` now preflights the persistent controller on the head unit before invoking controller installation logic.
- `ensure_cockpit_mirror_controller.sh` now checks the persistent controller on the head unit first, matching START behavior.
- If `/mnt/app/eso/hmi/lsd/jars/Cockpit_Mirror.jar` already matches the locked checksum and no legacy `carplay_hook.jar` is present, controller preparation succeeds without requiring the SD-card source JAR to match.
- The SD-card source JAR is still strictly checksum-verified whenever an install or legacy migration is actually required, so an unverified JAR is never written to `/mnt/app`.
- Added explicit detection for a Git LFS pointer accidentally copied to `Toolbox/apps/mmi-cockpit-mirror/Cockpit_Mirror.jar`; this now reports a clear LFS/source-file error instead of a generic checksum mismatch.

### Update note

- This hotfix does **not** require UNINSTALL. Re-sync/install the latest Toolbox scripts so the updated `autostart_cockpit_mirror_on.sh` and `ensure_cockpit_mirror_controller.sh` replace the installed copies.
- A full Java reinstall/reboot is only required when the controller itself actually changes or is missing. An already verified installed controller is left untouched.

## 2026-09-05 — Full-chain Compatibility CHECK

### Added

- New Green Menu `CHECK` action backed by `check_cockpit_mirror_compatibility.sh`.
- CHECK does not decide support from the vehicle model or firmware train name alone. It runs a short, real B3 v52 compatibility probe using the same production worker as START.
- The probe requires evidence for every critical stage:
  - locked native artifact validation;
  - real tiny-RFB clock-host startup;
  - renderer-local `1024×480` MMI capture;
  - real EGL submission;
  - Java controller `ACTIVE` state;
  - explicit `nativeContext=76 source=58 fps=30` confirmation;
  - a finite stable ACTIVE window;
  - Java return to `IDLE` and stock-route recovery.
- A complete pass prints `CHECK RESULT: CAN USE THIS PROJECT`.
- Any missing critical stage prints `CHECK RESULT: CANNOT USE CURRENT BUILD` together with the failed stage and reason.
- Detailed output is saved to `Log/CarPlayMirror/compatibility_check.txt` plus worker/ACTIVE snapshots.

### Changed

- `direct_upload_test_worker.sh` now accepts an optional third argument for a finite run duration. Normal START still omits it and remains persistent; CHECK uses the finite mode.
- UNINSTALL also removes the compatibility checker script.

### Safety behavior

- CHECK briefly runs the real cockpit mirror path and must be used while parked.
- On the validated P1404 train, if the verified Java controller is not installed yet, the first CHECK may install it using the same safe installer as START and return `REBOOT REQUIRED`; the post-reboot CHECK performs the final full-chain decision.
- On unknown firmware trains CHECK does not write the Java controller merely to experiment. If no already verified controller path exists, the current build is not declared compatible.
- Any probe failure requests the stock Audi route again before exiting.

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
CHECK
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
