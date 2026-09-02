# v52 Clock Host 长时退出修复 / Long-run Clock Host Fix

## 中文

### 现象

镜像启动正常并稳定在约 30 FPS，但一次实车运行在约 19 分半后自动恢复奥迪地图。
最终状态为：

```text
state=FAILED
detail=Clock host exited during direct-upload test; cockpit route restored
```

退出前 renderer、EGL 和帧采集均正常；最后记录约 35087 帧。故障日志中只有一个
clock server、一个 client 和一次 bootstrap trigger，却出现 4610 次
`mirror worker stopped`。

### 根因

v51 使用带 `LD_PRELOAD=libcp_mirror.so` 的 `/bin/sh` 作为 clock host。shell
已经正确加载镜像库，但它启动的每一个 `/bin/sleep 30` 也继承了 `LD_PRELOAD`，
因此 sleep 子进程不断重复加载镜像库并创建额外 worker。持续的线程/进程抖动
最终让 clock-host shell 退出，主 worker 随后按 fail-closed 规则恢复奥迪地图。

### v52 修复

主 shell 启动并完成预加载后，立即清除传给子进程的 `LD_PRELOAD`：

```sh
MIRROR_CLOCK_HOST=1 LD_PRELOAD="${APP}/libcp_mirror.so" \
    /bin/sh -c "unset LD_PRELOAD; while [ -f '${MARKER}' ]; do /bin/sleep 30; done"
```

`unset` 不会卸载主 shell 中已经加载的 `libcp_mirror`，只会阻止后续 sleep
子进程重复加载它。renderer、首帧门控、Java context 76 和 watchdog 逻辑不变。

### 实车验收

1. 状态保持 `ACTIVE` 超过 30 分钟。
2. `direct_upload.log` 持续报告约 30 FPS。
3. `mirror_hook.log` 只出现一个 server/client/bootstrap 生命周期，不再快速累积
   `mirror worker stopped`。
4. STOP 后奥迪地图正常恢复。

## English

### Symptom

Mirroring started normally and remained near 30 FPS, but one captured in-car
run returned to the Audi map after roughly 19.5 minutes. The final status was
`Clock host exited during direct-upload test`. Renderer, EGL, and frame capture
remained healthy up to about frame 35087. The hook log contained one server,
one client, and one bootstrap trigger, but 4610 `mirror worker stopped` lines.

### Root cause

The v51 `/bin/sh` clock host was launched with `LD_PRELOAD=libcp_mirror.so`.
The shell correctly loaded the mirror library, but every `/bin/sleep 30` child
inherited the same preload and created another mirror worker. Continuous
process/thread churn eventually terminated the clock-host shell, after which
the main worker correctly failed closed and restored the Audi map.

### v52 fix

After the main shell has loaded the library, it immediately unsets
`LD_PRELOAD` before entering its keepalive loop. This leaves the already-loaded
clock server intact while preventing child sleep processes from loading the
library again. Renderer, first-frame gating, Java context 76, and watchdog
behavior are unchanged.

### In-car acceptance criteria

1. Remain `ACTIVE` for more than 30 minutes.
2. Keep reporting approximately 30 FPS in `direct_upload.log`.
3. Observe one server/client/bootstrap lifecycle without rapid repeated
   `mirror worker stopped` entries.
4. Confirm STOP restores the Audi map.
