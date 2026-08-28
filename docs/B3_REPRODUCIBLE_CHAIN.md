# B3-OPT 可复现链路（v51）

本文记录 2020 款 Audi Q5L、`MHI2Q_CN_AUG22_P1404` 上已经跑通的
`MMI Cockpit Mirror → START` 完整链路。目标是让后来者只依赖本仓库、
一张现成的 MIB2 Toolbox SD 卡和同版本实车，就能复原当前结果，而不必重走
B2/source16、source59、物理 display buffer share 等已经证伪的路线。

> 适用范围只包含 `MHI2Q_CN_AUG22_P1404`。本文中的显示尺寸、context、
> displayable、ABI、安装路径和校验值都不是跨固件通用参数。

## 1. 最终结果与边界

当前 B3-OPT 做的是“复制中控 MMI 最终合成画面”，不是只抓 CarPlay 导航数据：

```text
MMI 物理输出 1024×480 @ 59 Hz
  → QNX Screen screen_read_display()
  → renderer 进程内 BGRA/RGBA GPU 通道交换
  → GLES 1024×480 视频纹理（30 FPS draw clock）
  → displayable 58 的 1440×542 窗口
  → DisplayManager context 72 → 76
  → 虚拟座舱显示
```

因此，中控显示 CarPlay 时仪表显示 CarPlay；中控显示原生菜单、媒体或原生地图时，
仪表显示同一份 MMI 最终合成画面。

实车短时基准：

- 1360 帧约 45.4 秒；稳定在 `29.66–29.97 FPS`，最后一次统计为 `29.970 FPS`。
- `screen_read_display()` 通常 `2–7 ms`，观测最大值 `9 ms`。
- 颜色、80% 缩放、水平居中和向上偏移已经实车确认。
- VIEW/layout 切回原生 context 后，Java 控制器会重新进入 context 76。
- v48 修复了旧版常驻宿主仍固定 `sleep 420` 的问题。v51 保留已验证能启动
  native server 的 marker 跟随式 `/bin/sh -c` 宿主，并让 watchdog 只用记录
  PID 的 `kill -0` 检查存活，避开 P1404 `pidin` 截断造成的约 40 秒误恢复。
- 仍需继续验证数小时热稳定性；短时结果不等于完成长期寿命测试。

B3-OPT 不是物理零拷贝。P1404 已实车拒绝
`screen_share_display_buffers()`，所以当前最优解仍有一次 Screen 读回和一次 GLES
纹理上传，但已经去掉整帧 RFB/socket/zlib 传输。

## 2. 已验证拓扑与固定参数

| 项目 | P1404 实测值 | 用途 |
|---|---:|---|
| MMI 物理输出 | `1024×480 @ 59 Hz` | 被抓取的完整中控合成画面 |
| 虚拟座舱画布 | `1440×542 @ 60 Hz` | displayable 58 的目标窗口 |
| 实验 context | `76` | 镜像显示 context |
| 镜像 displayable | `58` | OpenGL renderer 窗口 |
| 过渡 context | `72` | 进入/离开 76 前的安全过渡 |
| 原生地图 context | `74` | B3 关闭或故障时恢复 |
| 目标帧率 | `30 FPS` | 每帧周期 `33,333 µs` |
| MMI 像素格式 | QNX `RGBA8888`，小端内存表现为 BGRA | GPU shader 交换 R/B |
| 目标几何 | 原画面 80%，水平居中，向上偏移 | 避让仪表覆盖层 |

`config.txt` 中当前几何为：

```text
windowWidth=1440
windowHeight=542
landscapeVertices=-0.568889 0.819188 0.0  0.568889 0.819188 0.0  0.568889 -0.597786 0.0  -0.568889 -0.597786 0.0
```

它对应约 `819×384` 的内容区域，水平边距约 `310 px`，顶部约 `49 px`、底部约
`109 px`。不要把 `1024×480` 拉满到 `1440×542`，否则会被虚拟座舱固定覆盖层遮挡。

## 3. 仓库内的唯一真源

### 3.1 原生源码

- `src/native/libcp_mirror.c`
  - B3 下仅由显式 `MIRROR_CLOCK_HOST=1` 的宿主拥有 localhost:5900。
  - 给 renderer 发送一次极小 RFB bootstrap/节拍，不传输完整画面。
  - 已常驻在 `smartphone_integrator` 的另一份 hook 在 B3 期间保持 inert，避免抢端口。
- `src/native/libdirect_upload.c`
  - 在 renderer 内创建 QNX Screen display-manager context。
  - 按尺寸选择精确的 `1024×480` 输出，不依赖 displays 数组下标。
  - `screen_read_display()` 后直接更新已建立的 `1024×480` GLES 纹理。
  - 替换视频 fragment shader，在 GPU 上交换 R/B，避免每帧约 1.9 MiB CPU 转换。
  - 挂接 `glDrawArrays(GL_TRIANGLE_FAN, 0, 4)`，以 `33,333 µs` 周期驱动刷新。
- `src/native/libdisplayinit_p1404.c`
  - P1404 的 displayable-58 窗口兼容层。
- `src/native/libegl_diag.c`
  - 只记录 EGL/GLES 建立和提交证据。
- `src/native/libport_waker.c`
  - 只唤醒项目遗留的 localhost:5900 accept；校验不通过时绝不 preload。

### 3.2 Java 控制链

- `src/java/com/luka/carplay/routeguidance/FullScreenMirrorController.java`
  - 从已验证的 RouteGuidance 插件生命周期取得 stock `Navigation` / `ClusterService`。
  - 只有 `ARMED`、`receiver_ready` 和变化中的 heartbeat 同时满足才进入 76。
  - 执行真正的 DisplayManager `72 → 76`，并确认
    `nativeContext=76 source=58 fps=30`。
  - VIEW/layout 落回 72/74 时进入 `SUSPENDED`，稳定两个 250ms 轮询后重新执行
    `72 → 76`。
  - marker 或 heartbeat 消失时恢复 context 74。

当前 Java JAR 依赖奥迪私有类，仓库没有一个干净、独立、可从零下载依赖的 Java
构建系统。因此可复现包把已验证 JAR 作为锁定构件，而不是声称它能脱离固件 SDK
重新编译。源代码用于审计和继续开发；部署时必须使用下文固定 SHA-256 的 JAR。

### 3.3 运行脚本

| 文件 | 责任 |
|---|---|
| `start_direct16_share_test.sh` | v41 兼容入口；立即转发到 B3-OPT 30FPS |
| `start_direct_upload_test.sh` | 固件、互斥状态、JAR、残留 B5、5900 端口前置检查 |
| `/bin/sh -c` clock host | 已实车验证的 marker 跟随宿主；承载 tiny-RFB preload，PID 写入 `direct_upload_capture.pid` |
| `direct_upload_test_worker.sh` | 校验构件、启动宿主/renderer、首帧门控、心跳、运行监控和正常恢复 |
| `direct_upload_restore_watchdog.sh` | 独立 2 秒轮询；worker/renderer/宿主/心跳异常时 fail closed |
| `check_direct_upload_test.sh` | 底层状态查看脚本；不再直接暴露在精简菜单中 |
| `record_b3_logs.sh` | 把状态、核心日志、marker、PID、构件校验和 DisplayManager 状态保存成一次快照 |
| `stop_direct_upload_test.sh` | 移除 marker，等待正常退出，并再次请求 72 → 74 |
| `stop_all_mirror_runtime.sh` | 清除所有历史 marker，只杀本项目 PID，恢复 74 的紧急兜底 |

独立 GEM 菜单入口位于
`sd-package/Toolbox/GEM/mqb-mmiCockpitMirror.esd`，菜单名称为
`MMI Cockpit Mirror`。该菜单刻意只公开 `START`、`STOP`、`LOG RECORD`
三个操作；安装、B5 和恢复工具仍留在原 CarPlay Route Guidance 页面。

## 4. 锁定构件与校验值

SD 运行目录是 `Toolbox/carplay_mirror_test/`。当前 v51 必须保留以下构件：

| 文件 | POSIX `cksum / size` | SHA-256 |
|---|---|---|
| `libcp_mirror.so` | `2128946334 16364` | `4B3A5A2DDFD7118988B3FE9BDE90DF48CA700AA028D228515FAFD44EF6137C30` |
| `libdirect_upload.so` | `2201151100 9064` | `50B63F23119A40DF93365461950B97E46E0318CB52138EA739A2A729BAC3135C` |
| `libport_waker.so` | `3375612677 2292` | `E4B221AE0A650DBC3DB61B66FB2C8D423D662307E307A84FA7EA97FE2B9327AF` |
| `opengl-render-qnx-audi` | `1309065104 107890` | `2DAEF16EC470779AD00F30079E1865677C4F928EA8E172626409CD0D98378C4C` |
| `libdisplayinit.so` | `1535898152 4956` | `E7DB229C417709E41BFF62519951C7B721E342263C27E0CCD8A90E8A765395B6` |
| `libegl_diag.so` | `4142780645 8484` | `B670A3B99254D64D64158B63DB2980343CEDF5FBCBAE24146D31B081B6B38C9E` |
| `Cockpit_Mirror.jar` | `140001591 112564` | `1DAEB0A42E0A1EF92031F7412ADDC9CB3A4527BAB312FA285B23DC1ECC49AB57` |

worker 在改变 cockpit context 前验证前五个直接运行构件；安装脚本分别验证 native
hook 和 Java JAR。SHA-256 用于电脑端发行包验收，车机端使用其可用的 POSIX
`cksum`。

## 5. 从源码构建原生组件

要求：Windows + WSL，WSL 中存在 `clang`、`lld`、`readelf`。仓库已包含 QNX
导入 stub；不需要在车机上编译。

在仓库根目录运行：

```powershell
wsl bash /mnt/d/littlethings/CarPlay/mirrordisplay/build-scripts/build_wsl.sh
```

脚本使用以下关键 ABI：

```text
target=armv7-linux-gnueabi
march=armv7-a
instruction-set=ARM
float-abi=softfp
shared-library hash=SYSV
QNX EABI5 e_flags bytes at ELF offset 0x24 = 02 00 00 05
```

输出位于 `mirrordisplay/build/`。构建脚本不会自动覆盖 SD 包；这是刻意的安全边界。
只有完成以下步骤后才允许替换：

1. 对新 `.so` 执行 `file`、`readelf -h -d -s` 和 SHA-256 检查。
2. 把明确需要的构件复制到
   `sd-package/Toolbox/carplay_mirror_test/`。
3. 更新 `direct_upload_test_worker.sh` 中相应 `EXPECTED_*` 的 POSIX `cksum`。
4. 更新本文、`MANIFEST.txt` 和 `HARDCODED_AND_NOTES.md` 中的校验值。
5. 不要因为只修改了某一个 `.so` 就同时替换 renderer 或 JAR。

## 6. 生成 SD 覆盖包

以 `mirrordisplay/sd-package/` 为 SD 根目录增量覆盖模板。复制时必须保留原 Toolbox
的其他目录，不要先清空 SD 卡：

```text
SD 根目录
├─ metainfo2.txt                      # 原 Toolbox 自带
└─ Toolbox
   ├─ GEM
   │  ├─ mqb-mmiCockpitMirror.esd
   │  └─ mqb-mmiCockpitMirror.esd
   ├─ scripts
   │  ├─ install_carplay_mirror_test.sh
   │  ├─ install_carplay_mirror_java.sh
   │  ├─ start_direct16_share_test.sh
   │  ├─ start_direct_upload_test.sh
   │  ├─ direct_upload_test_worker.sh
   │  ├─ direct_upload_restore_watchdog.sh
   │  ├─ check_direct_upload_test.sh
   │  ├─ stop_direct_upload_test.sh
   │  └─ stop_all_mirror_runtime.sh
   └─ carplay_mirror_test
      ├─ libcp_mirror.so
      ├─ libdirect_upload.so
      ├─ libport_waker.so
      ├─ libdisplayinit.so
      ├─ libegl_diag.so
      ├─ opengl-render-qnx-audi
      ├─ Cockpit_Mirror.jar
      └─ config.txt
```

GEM 执行的是车机安装后的 `/eso/hmi/engdefs/scripts/mqb/` 路径；Toolbox 更新安装
会把 SD 上的脚本同步到该路径。不要只替换 GEM 菜单而漏掉 scripts。

## 7. 一次性安装

以下操作只适用于驻车状态并保证供电稳定。

### 7.1 Native capture components

运行菜单：

```text
The B3 worker loads the native capture components directly from the SD card.
```

脚本做的唯一持久修改：

1. 备份现有 `/mnt/app/root/hooks/libcp_mirror.so`。
2. 安装锁定的 `libcp_mirror.so`。
3. 把 `smartphone_integrator.json` 的 preload 从
   `libcarplay_hook.so` 改为
   `libcp_mirror.so:libcarplay_hook.so`。
4. 任何一步失败即回滚；最后把分区恢复只读。

### 7.2 Cockpit controller

运行菜单：

```text
The first START installs or migrates the Java cockpit controller.
```

脚本备份并替换：

```text
/mnt/app/eso/hmi/lsd/jars/Cockpit_Mirror.jar
```

备份存放在：

```text
Backup/MHI2Q_CN_AUG22_P1404/MMI_Cockpit_Mirror/
```

### 7.3 真正重启

两项安装完成后至少等待 30 秒，再完整重启 MMI。普通短按黑屏/开屏不一定重载
`smartphone_integrator` 和 Java JAR；必须看到真实启动过程。没有安装文件变化时，
日常 B3 ON/OFF 不需要每次重启。

## 8. B3-OPT 启动状态机

进入 `MMI Cockpit Mirror`，选择：

```text
START - 30FPS persistent MMI cockpit mirror
```

严格执行顺序如下：

1. **前置互斥**：要求固件完全匹配；B5、旧 B3 和其他 direct marker 均不存在；
   已安装 Java JAR 存在。
2. **清理可证明残留**：只处理本项目记录的 B5 PID/状态，不按进程名全局杀进程。
3. **可选端口唤醒**：校验 `libport_waker.so` 后连接 localhost:5900，使旧 hook
   的阻塞 `accept()` 返回。校验不匹配就跳过，不加载未知二进制。
4. **建立 marker**：创建 `DIRECT_UPLOAD_TEST`、`FPS30`，启动每秒变化的
   `worker_heartbeat`。
5. **启动独立 watchdog**：它不依赖主 worker 的 trap，2 秒轮询一次。
6. **启动 clock host**：

   ```text
   MIRROR_CLOCK_HOST=1 LD_PRELOAD=libcp_mirror.so
     /bin/sh -c "while DIRECT_UPLOAD_TEST exists; sleep 30; done"
   ```

   它只在 marker 存活期间存在，并独占项目的 localhost:5900 bootstrap 监听。
   watchdog 读取 `direct_upload_capture.pid` 并用 `kill -0` 检查存活，不读取
   `pidin` 命令行，因此即使 P1404 截断 `sh -c` 参数也不会误判。
7. **启动 renderer**：

   ```text
   LD_PRELOAD=libdirect_upload.so:libegl_diag.so
     opengl-render-qnx-audi 127.0.0.1
   ```

8. **首帧门控**：奥迪原生地图仍保持显示，直到同时看到：
   - `mirror first direct-upload trigger sent`
   - `direct upload first MMI frame`
   - 至少一次成功 `eglSwapBuffers`
9. **仪表接管**：只有上述门控通过，worker 才创建 `ARMED` 和
   `receiver_ready`。Java 执行 `72 → 76`，并回报
   `nativeContext=76 source=58 fps=30`。
10. **持久运行**：`DURATION=0`，直到 STOP、MMI 重启或 watchdog 故障。
    worker 每秒检查 renderer、clock host、Java 状态和帧统计是否继续增长。

这套顺序的重要性在于：先证明真实画面和 EGL 输出，再切走奥迪地图；不要提前
进入 context 76 去赌 renderer 最终能成功。

## 9. 每帧数据路径

1. renderer 第一次建立 `1024×480` 视频纹理时，`libdirect_upload.so` 挂接
   `glTexImage2D()` 并初始化 Screen 抓取。
2. 它枚举物理显示并按 `SCREEN_PROPERTY_SIZE` 选择唯一 `1024×480` 输出。
3. 创建 `SCREEN_FORMAT_RGBA8888`、READ|NATIVE pixmap buffer。
4. renderer 的真实 60Hz draw loop 每次调用
   `glDrawArrays(GL_TRIANGLE_FAN, 0, 4)` 时进入 pump。
5. 到达下一个 `33,333 µs` 周期才调用 `screen_read_display()`；慢帧时以当前时间
   重新对齐，避免积压补帧形成延迟队列。
6. P1404 小端 RGBA8888 内存按 BGRA 解释。视频 fragment shader 输出
   `vec4(c.b, c.g, c.r, 1.0)`，在 GPU 纠正颜色。
7. 使用真实 GLES 的 `glTexSubImage2D()` 更新当前绑定纹理。
8. renderer 原有几何把纹理画入 displayable 58；RFB 后续整帧更新被忽略。

因此这条链没有“先积攒 60 帧再播放”的缓冲；30FPS 是约每 33.3ms 读取并提交
一帧，实际操作延迟由 Screen readback、当前 draw 时机和面板扫描共同决定。

## 10. VIEW/layout 抢回

方向盘 VIEW 会让原生策略短暂切到 context 72 或 74。B3 不拦截按键本身，也不
修改方向盘逻辑。Java 控制器观察到：

```text
ACTIVE(76) → SUSPENDED(72/74) → 两次稳定轮询 → 72 → 76 → ACTIVE
```

如果 `ClusterService` 在插件 lifecycle stop 中被释放，控制器会重新取得 stock
服务后再进入 76。这样比“每 0.5 秒盲目强制 dmdt”安全，也不会让 shell 与 Java
同时争抢 context。

## 11. 关闭、故障恢复和重启语义

### 11.1 正常关闭

进入 `MMI Cockpit Mirror`，运行：

```text
STOP - disable mirror and restore Audi map
```

顺序为：

1. 移除 `DIRECT_UPLOAD_TEST`、`ARMED`、`receiver_ready` 和 FPS marker。
2. Java 观察到请求消失，先回到 context 74。
3. worker 停 renderer 和 clock host。
4. shell 再执行 `dc 76 58`、`sc 1 72`、`sc 1 74` 作为兜底。

### 11.2 独立 watchdog

下列任一条件会 fail closed：

- worker heartbeat 约 20 秒未变化；
- worker、renderer 或记录 PID 对应的 clock host 不存在；
- worker 检测到连续超过 12 秒没有新的帧统计；
- Java 报 `FAILED`；
- 首帧、EGL 或 context 门控超时。

恢复动作总是先移除激活 marker，再终止 PID 记录且命令行匹配的本项目进程，最后
恢复 `76/source58 → 72 → 74`。

### 11.3 重启

B3 不跨 MMI 重启自动开启。安装的 native/Java hook 会保留，但没有 SD marker 和
变化中的 heartbeat 时保持 inert。这一点用于避免损坏的 SD 卡或陈旧状态形成启动
循环。

如果正常 OFF 没有完成，使用：

```text
EMERGENCY OFF Stop ALL mirror runtime and clear stale state
```

紧急关闭不会卸载 Toolbox、RGI 或本项目持久构件，只把运行态清空并恢复奥迪地图。

## 12. 日志与验收标准

运行日志在 SD：

```text
Log/CarPlayMirror/direct_upload_status.txt
Log/CarPlayMirror/direct_upload.log
Log/CarPlayMirror/direct_upload_renderer.log
Log/CarPlayMirror/direct_upload_capture_host.log
Log/CarPlayMirror/direct_upload_timeline.log
Log/CarPlayMirror/direct_upload_watchdog.log
Log/CarPlayMirror/java_mirror_state.txt
```

运行 `LOG RECORD - save current B3 status and logs` 会在
`Log/CarPlayMirror/Records/B3_<时间>_<PID>/` 保存一次不可覆盖的快照，并在屏幕上
显示当前状态和最近十条 FPS 统计。快照至少包含当时存在的核心日志、marker、项目
PID、锁定构件 `cksum` 以及 `dmdt gs/gd`。正常运行时应至少出现：

v51 每 10 秒输出一次窗口化 FPS 统计，避免 P1404 的 32 位累计乘法溢出，同时
保留 worker 的 12 秒失帧检测能力。每次
START 会截断上一轮活跃日志；watchdog 每分钟检查高频日志，单个文件超过 2 MiB
时覆盖一份 `.previous` 后截断当前文件。受控日志因此不会无限增长；手动
`LOG RECORD` 快照只在用户选择该菜单项时创建。

P1404 的预加载环境必须保持变量除法依赖为 `__aeabi_idiv`。不要把 FPS 公式改成
无符号变量除法；它会引入无法解析的 `__aeabi_uidiv`，表现为 renderer/EGL 正常
运行，但 `libdirect_upload` 没有进入纹理挂接点。

```text
state=ACTIVE
requested_fps=30
duration_seconds=0
direct upload first MMI frame ... 1024 480
direct draw-clock texture pump started 30 1024 480
direct upload measured fps_x1000 capture_ms frames 29xxx ...
[p1404-displayinit] window ready size=1440x542 requested=20 effective=58
[egl-diag] eglSwapBuffers ... out=1 err=0x3000
```

验收分四层：

1. **抓取层**：选择的是 1024×480 MMI，连续帧统计增长，capture 通常低于 10ms。
2. **渲染层**：EGL 初始化和 swap 成功，GPU BGRA swizzle 已启用。
3. **路由层**：Java 为 ACTIVE，明确报告 context 76/source58/fps30。
4. **实车层**：颜色正确、80% 居中、操作延迟可接受，VIEW 后能自动回来，OFF 后
   奥迪地图恢复。

`state=ACTIVE` 只证明软件门控通过，不能替代观察驾驶位屏幕。

## 13. 最小复现实车流程

1. 在电脑端确认 SD 为 FAT32 且能完整读取；把 `sd-package/` 增量覆盖到完整
   Toolbox SD 根目录。
2. 驻车、稳定供电、插入 SD1，进入 GEM → CarPlay Route Guidance。
3. 第一次部署或控制器更新：第一次 START 只安装/迁移 `Cockpit_Mirror.jar`；
   等待写入完成后完整重启 MMI，再次选择 START 才开始镜像。
4. 连接有线 CarPlay，使 RouteGuidance 插件生命周期存在；把希望镜像的中控页面
   留在屏幕上。
5. 确认 B5 已 OFF，进入 `MMI Cockpit Mirror` 运行 `START`，随后退出 GEM。
6. 观察驾驶位：应在首帧门控通过后从奥迪地图切到 80% 居中的 MMI 画面。
7. 测试中控切页、CarPlay、颜色和 VIEW 恢复。
8. 运行 `LOG RECORD`，保存上述日志、进程、marker 和 DisplayManager 快照。
9. 结束时运行 `STOP`；确认奥迪地图恢复后再拔 SD。

## 14. 故障定位速查

| 现象 | 先看 | 含义/处理 |
|---|---|---|
| `Controller installed...reboot` | 首次 START 安装了 JAR | 完整重启 MMI，不是只黑屏，然后再次 START |
| `Port-release helper checksum mismatch` | port waker cksum | helper 会安全跳过；若 5900 仍被占，先 EMERGENCY OFF 或重启 |
| `No renderer-local 1024x480 MMI frame` | `direct_upload.log` | Screen 权限、物理显示选择或 clock bootstrap 未建立 |
| `Renderer exited before first direct frame` | renderer/EGL 日志 | ABI、LD_PRELOAD、displayinit 或 renderer 构件不匹配 |
| `Java controller did not reach ACTIVE` | `java_mirror_state.txt` | 插件 lifecycle/ClusterService 未建立；确认有线 CarPlay 和 JAR |
| 仪表黑屏但 status ACTIVE | renderer、Java、驾驶位实屏 | 软件 context 已切换但 surface 无有效画面；立即 STOP |
| 红蓝互换 | `GPU BGRA swizzle enabled` | 不要恢复 CPU 色彩路径；确认 shader replacement 生效 |
| 画面在左边/过大 | `config.txt` 和 displayinit | 恢复本文固定 1440×542 + 80% vertices |
| VIEW 后回地图 | Java `SUSPENDED/ACTIVE` 变化 | 若未在数秒内重入 76，STOP 并检查 controller 日志 |
| FPS 统计变成负数 | `direct_upload.log` | v50 的 32 位累计计数溢出；覆盖 v51 构件，不代表画面链路曾崩溃 |
| 约40秒后自动恢复地图 | watchdog 与 clock host | 旧 v48 用被 `pidin` 截断的参数验身份；覆盖 v51 脚本并 Update Toolbox |
| 宿主存活但没有首帧 | clock host 启动形式 | v49 直接执行 shell 脚本未启动 native server；覆盖 v51 脚本并 Update Toolbox |
| 约7分钟后自己退出 | clock host 版本 | 旧 v47 固定 420 秒宿主；覆盖 v51 脚本并 Update Toolbox |

## 15. 不要重新尝试的旧 B3 分支

- `context76 → source16`：接近零延迟，但只得到原厂 HMI/地图链，不含 CarPlay。
- `context76 → source59`：能让奥迪地图消失，证明 context 生效；P1404 没有可消费帧，
  结果黑屏。
- `screen_share_display_buffers()`：count 0/1/2/3 都返回 `rc=-1`，errno 仍为 0。
- 独立窗口 GREEN 测试：只能证明中控 QNX window 创建成功，不能证明仪表能显示。
- 全帧 RFB 高频路线：B5 10FPS 可用，但 request/reply、socket 和解码使高帧率延迟
  明显；只保留为稳定保底。
- shell 高频强制 VIEW：多次切换会失效或与 Java 抢 context；当前只由 Java 状态机
  接管。

## 16. 复现完成定义

只有同时满足以下条件，才算复现当前 B3：

- 固件严格为 `MHI2Q_CN_AUG22_P1404`，构件 hash 与本文一致。
- 控制器安装有事务备份和回滚，完整 MMI 重启后 `Cockpit_Mirror.jar` 正常加载。
- B3 从原生地图门控切入，而不是先黑屏再等待画面。
- 仪表显示完整 MMI/CarPlay 最终画面，颜色正确、80% 居中。
- 实测持续接近 30FPS，帧统计连续增长，无大规模延迟队列。
- VIEW 后能重新进入 context 76。
- STOP、watchdog 故障和 MMI 重启三种路径都能回到奥迪 context 74。
- 至少完成一次长时运行并保存日志；当前仓库已有短时性能证据，但长期热稳定性仍
  是部署者需要继续补齐的验证项。
