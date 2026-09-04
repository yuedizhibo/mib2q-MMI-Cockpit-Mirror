# MIB2Q MMI Cockpit Mirror

[English](README_EN.md) | 简体中文

把 MIB2Q 中控当前输出的**完整 MMI 画面**实时镜像到 Audi Virtual Cockpit。

项目基于 [jilleb/mib2-toolbox](https://github.com/jilleb/mib2-toolbox)，加入了 Green Engineering Menu、B3-OPT v52 renderer-local 全画面镜像链路、故障恢复、日志采集、AutoStart 开机自动投屏和完整卸载恢复流程。

它不是 CarPlay AltScreen，也不是只转发导航箭头：中控显示 CarPlay 时仪表显示 CarPlay，中控显示原生 MMI 菜单时仪表也同步显示原生画面。

## 实车效果

![MMI 画面同步显示在中控与 Audi Virtual Cockpit](docs/images/mmi-cockpit-mirror-demo.png)

> [!CAUTION]
> 这是针对特定车机固件的实验性修改，会写入 MMI 系统分区。操作错误可能造成黑屏、服务故障或需要恢复车机。只在车辆静止、供电稳定且已经保存备份时使用。作者和参考项目作者均不对车辆、车机、数据或保修损失承担责任。

## 当前支持范围

- 实车：2020 Audi Q5L
- 固件：`MHI2Q_CN_AUG22_P1404`
- 目标：Audi Virtual Cockpit `context 76 / displayable 58`
- 输入：MMI renderer 内部 1024×480 画面
- 输出：约 30 FPS，80% 缩放、水平居中并向上校正
- B3 runtime：v52
- 生命周期：持续运行到 STOP、MMI 完整重启或 watchdog 故障恢复

脚本会拒绝其他固件。不要通过删除固件检查来尝试未知车型或版本。

## Green Menu

安装后进入：

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

手动启动当前 B3 v52 链路。START 会先验证固件、Java controller、native 构件和旧运行状态，然后启动 clock host 与 renderer。只有确认真实 MMI 首帧、EGL 输出和 Java `context 76 / displayable 58` 均正常后，才切换仪表显示。

### STOP

停止当前镜像会话，撤销 B3 marker，等待 Java controller 回到 IDLE，并恢复 Audi 原生 `context 74`。STOP 不删除任何安装文件，下次仍可再次 START。

### AutoStart ON

把一个独立、带 BEGIN/END 标记的 MMI Cockpit Mirror 启动块写入 `/etc/boot/startup.sh`。以后每次完整 MMI 启动都会调用同一个 `start_direct_upload_test.sh`，因此自动启动与手动 START 使用完全相同的 B3 v52 链路。

开机 runner 最多等待约 120 秒，让 MMI 服务和 Toolbox SD 卡就绪。如果条件未满足，本次自动启动会安全退出并保留 Audi 原生地图。

> [!IMPORTANT]
> 当前 B3 native runtime 仍由 SD 卡提供，因此启用 AutoStart 后仍需要保持包含本仓库 Toolbox 文件的 SD 卡插入。没有 SD 卡时不会自动投屏。

### AutoStart OFF

只关闭未来开机自动启动：删除 `/etc/boot/startup.sh` 中属于本项目的 AutoStart block 和持久 marker，不影响当前已经运行的 B3 会话。如果当前正在投屏，需要同时停止当前会话时再选择 STOP。

### UNINSTALL

完整移除 MMI Cockpit Mirror 本身并恢复到安装本功能之前的状态：

- 先停止 B3/B5 残留运行并恢复 Audi `context 74`；
- 删除 AutoStart startup hook 与持久 marker；
- 删除 `/mnt/app/eso/hmi/lsd/jars/Cockpit_Mirror.jar`；
- 删除可能残留的旧版 `carplay_hook.jar`；
- 删除本项目专属 Green Menu 和 B3/AutoStart 脚本；
- 保留基础 MIB2 Toolbox，不影响其余 Toolbox 功能；
- 卸载前把现有 Java JAR 保存到 SD 卡作为紧急回滚副本。

UNINSTALL 完成后必须执行一次**完整 MMI 重启**，以卸载 JVM 中已经加载的 Java 类。

## 安装

1. 下载或克隆本仓库，把仓库根目录的全部文件放到健康的 FAT32 SD 卡根目录。
2. 按 [MIB2 Toolbox 原始安装说明](https://github.com/jilleb/mib2-toolbox#how-to-install)执行软件更新，确保 Toolbox 完整安装。
3. 插入 SD 卡并进入 `MMI Cockpit Mirror` 菜单。
4. 第一次选择 `START` 或 `AutoStart ON` 时会检查 `Cockpit_Mirror.jar`：
   - 未安装时先备份并安装控制器；
   - 检测到旧 `carplay_hook.jar` 时先保存备份，再迁移到新控制器；
   - 首次写入完成后需要完整重启 MMI。
5. 重启后选择 START 手动投屏，或在已启用 AutoStart 时等待系统自动进入 B3。
6. 当前版本镜像运行和 AutoStart 都需要 Toolbox SD 卡保持插入。

控制器备份、AutoStart 备份和安装/卸载状态保存在：

```text
Backup/MHI2Q_CN_AUG22_P1404/MMI_Cockpit_Mirror/
```

## 与 CarPlay RGI 的关系

当前 B3 画面链路已经不消费 RGI 导航消息，也不启动 `maneuver_render`：

- 不要求导航应用正在运行；
- 不依赖路线、转向或 BAP RGI 数据；
- 捕获整个 MMI 输出，而不是只捕获 CarPlay 导航画面；
- native 采集时钟由 SD 卡上的 `libcp_mirror.so` 显式启动。

仪表通道的 Java 控制器仍派生自 [luka-dev/mib2q-carplay-rgi](https://github.com/luka-dev/mib2q-carplay-rgi) 的 JAR/插件结构。公开构件已改名为 `Cockpit_Mirror.jar`，镜像模式会禁用 RGI 消息、BAP 接管和 maneuver renderer。详见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。

## 安全恢复

- worker、renderer、clock host 和 watchdog 都记录独立 PID；
- watchdog 使用 `kill -0` 检查 PID，不依赖 P1404 会截断的进程命令行；
- 首帧、EGL、Java context 或帧计数任一门控失败都会先撤销镜像标记；
- STOP 或故障会恢复 Audi `context 74`；
- AutoStart 启动条件超时会保持 stock route，不强制接管仪表；
- UNINSTALL 会同步移除 AutoStart hook，避免卸载后仍在开机尝试启动。

如果 MMI 无响应，先使用车辆已验证的完整 MMI 强制重启方式。不要在写入系统文件时断电或拔卡。

## 日志

选择 `LOG RECORD` 后，快照保存在：

```text
Log/CarPlayMirror/Records/B3_<timestamp>_<pid>/
```

主要文件包括：

- `direct_upload_status.txt`
- `direct_upload.log`
- `direct_upload_renderer.log`
- `direct_upload_capture_host.log`
- `direct_upload_watchdog.log`
- `direct_upload_worker.log`
- `java_mirror_state.txt`
- `SUMMARY.txt`

常驻日志不会无限增长：每次 START 会清空上一轮活跃日志；运行期间 watchdog 定期检查高频日志，单个文件超过 2 MiB 时只保留一份 `.previous` 后重新记录。

## 项目结构

```text
Toolbox/GEM/mqb-mmiCockpitMirror.esd       Green Menu 子菜单
Toolbox/scripts/start_direct_upload_test.sh  B3 START
Toolbox/scripts/stop_direct_upload_test.sh   B3 STOP
Toolbox/scripts/autostart_cockpit_mirror_*   AutoStart ON/OFF/boot runner
Toolbox/scripts/uninstall_cockpit_mirror.sh  完整卸载恢复
Toolbox/scripts/record_b3_logs.sh             日志快照
Toolbox/carplay_mirror_test/                  QNX runtime 与固定配置
Toolbox/apps/mmi-cockpit-mirror/              Cockpit_Mirror.jar
src/native/                                   native 采集与 renderer 注入源码
src/java/                                     仪表控制器及兼容源码
build-scripts/                                构建与 renderer 修补脚本
docs/B3_REPRODUCIBLE_CHAIN.md                 完整可复现链路
docs/V52_CLOCK_HOST_FIX.md                    v52 长时退出修复说明
CHANGELOG.md                                  项目更新日志
```

## 当前状态

- v50 已在 `MHI2Q_CN_AUG22_P1404` 上验证约 30 FPS 的短时运行；
- v51 修复长时间 FPS 统计溢出并限制日志占用；
- v52 修复 clock host 的 `LD_PRELOAD` 继承问题，并保留实车验证过的 B3 renderer-local 链路；
- watchdog 已改为 PID 存活检测，消除了旧版约 40 秒误恢复；
- 2026-09-05 新增完整 UNINSTALL 和 AutoStart ON/OFF 管理流程；
- AutoStart 当前仍依赖 Toolbox SD 卡；
- 数小时热稳定性和其他固件兼容性尚未声明完成。

详细变更见 [CHANGELOG.md](CHANGELOG.md)。

## 参考与致谢

- [jilleb/mib2-toolbox](https://github.com/jilleb/mib2-toolbox)：完整 Toolbox、SD 部署结构、软件更新流程和 Green Menu 框架。
- [luka-dev/mib2q-carplay-rgi](https://github.com/luka-dev/mib2q-carplay-rgi)：MHI2Q CarPlay/RGI 研究、Java 插件结构、QNX hook 与仪表渲染参考。
- [Lanye-z/mib2-toolbox-carplay-rgi](https://github.com/Lanye-z/mib2-toolbox-carplay-rgi)：Toolbox 与 RGI 的早期整合和部署参考。

本项目的核心增量包括 renderer-local 全 MMI 纹理读取、displayable 58 输出、持久化 30 FPS 控制、VIEW 恢复、PID watchdog、实车日志/回滚流程，以及 AutoStart / 完整卸载管理能力。

## 许可证

原始 MIB2 Toolbox 保留其 [MIT License](LICENSE)。本项目新增的原创脚本和源码按同一 MIT 条款提供；第三方派生文件、逆向材料和二进制不因此自动获得 MIT 授权，其权利和限制见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。
