# MIB2Q MMI Cockpit Mirror

[English](README_EN.md) | 简体中文

把 MIB2Q 中控当前输出的完整 MMI 画面实时镜像到 Audi Virtual Cockpit。

本仓库以 [jilleb/mib2-toolbox](https://github.com/jilleb/mib2-toolbox) 为完整
基础，直接加入了 Green Engineering Menu、B3-OPT v50 运行链路、故障恢复、
日志采集和可复现源码。它不是 CarPlay AltScreen，也不是仅转发导航箭头；它
采集的是整个 MMI 画面，因此中控显示 CarPlay 时仪表显示 CarPlay，中控显示
原生菜单时仪表也显示原生菜单。

> [!CAUTION]
> 这是针对特定车机固件的实验性修改，会写入 MMI 系统分区。操作错误可能造成
> 黑屏、服务故障或需要恢复车机。只在车辆静止、供电稳定且已经保存备份时使用。
> 作者和参考项目作者均不对车辆、车机、数据或保修损失承担责任。

## 当前支持范围

- 实车：2020 Audi Q5L
- 固件：`MHI2Q_CN_AUG22_P1404`
- 目标：Audi Virtual Cockpit `context 76 / displayable 58`
- 输入：MMI renderer 内部 1024×480 画面
- 输出：约 30 FPS，80% 缩放、水平居中并向上校正
- 生命周期：持续运行到 STOP、MMI 完整重启或 watchdog 故障恢复

脚本会拒绝其他固件。不要通过删除固件检查来尝试未知车型或版本。

## 与 CarPlay RGI 的关系

当前 B3 画面链路已经不消费 RGI 导航消息，也不启动 `maneuver_render`：

- 不要求导航应用正在运行；
- 不依赖路线、转向或 BAP RGI 数据；
- 捕获整个 MMI 输出，而不是只捕获 CarPlay 导航画面；
- native 采集时钟由 SD 卡上的 `libcp_mirror.so` 显式启动。

仪表通道的 Java 控制器仍派生自
[luka-dev/mib2q-carplay-rgi](https://github.com/luka-dev/mib2q-carplay-rgi) 的
JAR/插件结构。公开构件已改名为 `Cockpit_Mirror.jar`，镜像模式会禁用 RGI
消息、BAP 接管和 maneuver renderer，但这次改名不等于相关历史代码被重新
授权或完全重写。详见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。

## 菜单

安装后进入：

```text
MQB Coding Toolbox
└─ Customization
   └─ MMI Cockpit Mirror
      ├─ START - 30FPS persistent MMI cockpit mirror
      ├─ STOP - disable mirror and restore Audi map
      └─ LOG RECORD - save current B3 status and logs
```

## 安装

1. 下载或克隆本仓库，把仓库根目录的全部文件放到健康的 FAT32 SD 卡根目录。
2. 按 [MIB2 Toolbox 原始安装说明](https://github.com/jilleb/mib2-toolbox#how-to-install)
   执行软件更新，确保 Toolbox 完整安装。
3. 插入 SD 卡并进入上面的 `MMI Cockpit Mirror` 菜单。
4. 第一次选择 `START` 时，脚本会检查 `Cockpit_Mirror.jar`：
   - 未安装时，先备份并安装控制器；
   - 检测到旧的 `carplay_hook.jar` 时，先备份到 SD，再迁移为新文件名；
   - 此次只完成安装，屏幕会要求完整重启 MMI。
5. 等待写入完成后完整重启 MMI。重新进入菜单，再次选择 `START` 才会启动镜像。
6. 镜像期间保持 SD 卡插入。需要退出时选择 `STOP`。

控制器备份和安装日志保存在：

```text
Backup/MHI2Q_CN_AUG22_P1404/MMI_Cockpit_Mirror/
```

## 安全恢复

- worker、renderer、clock host 和 watchdog 都记录独立 PID；
- watchdog 使用 `kill -0` 检查 PID，不依赖 P1404 会截断的进程命令行；
- 首帧、EGL、Java context 或帧计数任一门控失败都会先撤销镜像标记；
- STOP 或故障会恢复 Audi `context 74`；
- 镜像不会在 MMI 重启后自动启动。

如果 MMI 无响应，先使用车辆已验证的完整 MMI 强制重启方式。不要在写入系统
文件时断电或拔卡。

## 日志

选择 `LOG RECORD` 后，快照保存在：

```text
Log/CarPlayMirror/Records/B3_<timestamp>_<pid>/
```

主要文件：

- `direct_upload_status.txt`
- `direct_upload.log`
- `direct_upload_renderer.log`
- `direct_upload_capture_host.log`
- `direct_upload_watchdog.log`
- `direct_upload_worker.log`
- `java_mirror_state.txt`
- `SUMMARY.txt`

## 项目结构

```text
Toolbox/GEM/mqb-mmiCockpitMirror.esd       Green Menu 子菜单
Toolbox/scripts/                           START / STOP / watchdog / 日志脚本
Toolbox/carplay_mirror_test/               QNX 运行构件和固定配置
Toolbox/apps/mmi-cockpit-mirror/           Cockpit_Mirror.jar
src/native/                                native 采集与 renderer 注入源码
src/java/                                  仪表控制器及兼容源码
build-scripts/                             构建与 renderer 修补脚本
docs/B3_REPRODUCIBLE_CHAIN.md              完整可复现链路
```

## 当前状态

- v50 已在 `MHI2Q_CN_AUG22_P1404` 上验证约 30 FPS 的短时运行；
- v50 恢复了已验证能启动 native server 的 `sh -c` clock host；
- 看门狗已改为 PID 存活检测，消除了旧版约 40 秒误恢复；
- `Cockpit_Mirror.jar` 新文件名和首次 START 迁移流程需要继续实车验证；
- 数小时热稳定性和其他固件兼容性尚未声明完成。

## 参考与致谢

- [jilleb/mib2-toolbox](https://github.com/jilleb/mib2-toolbox)：完整 Toolbox、
  SD 部署结构、软件更新流程和 Green Menu 框架。
- [luka-dev/mib2q-carplay-rgi](https://github.com/luka-dev/mib2q-carplay-rgi)：
  MHI2Q CarPlay/RGI 研究、Java 插件结构、QNX hook 与仪表渲染参考。
- [Lanye-z/mib2-toolbox-carplay-rgi](https://github.com/Lanye-z/mib2-toolbox-carplay-rgi)：
  Toolbox 与 RGI 的早期整合和部署参考。

感谢上述作者和社区公开的研究。本项目的核心增量是 renderer-local 全 MMI
纹理读取、displayable 58 输出、持久化 30 FPS 控制、VIEW 恢复、PID watchdog
以及完整的实车日志/回滚流程。

## 许可证

原始 MIB2 Toolbox 保留其 [MIT License](LICENSE)。本项目新增的原创脚本和
源码按同一 MIT 条款提供；第三方派生文件、逆向材料和二进制不因此自动获得
MIT 授权，其权利和限制见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。
