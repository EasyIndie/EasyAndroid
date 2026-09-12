# EasyAndroid

Android 开发实践沉淀。

这里记录的不是「Android 官方文档的搬运」,而是**实际踩过的坑、验证过的结论、可直接复用的脚本**。
所有内容都来自真机实践(Debug 真机:TCL Android TV + Pico 4),不是纸面推演。

## 目录

| 路径 | 内容 |
|---|---|
| [`docs/`](docs/) | 知识沉淀:环境搭建、ADB 技巧、厂商限制与绕行方案、踩坑速查 |
| [`apps/`](apps/) | 可运行的 Android 工程(**每个子目录是一个独立工程**) |
| [`tools/`](tools/) | 设备连接 / 安装 / 引导 / 新建工程脚本 |
| [`AGENTS.md`](AGENTS.md) | 给 AI 编码智能体的仓库说明与硬性约束 |

## 已沉淀的主题

- **无 IDE 的纯命令行 Android 开发**:WSL2 + JDK + cmdline-tools + Gradle,不装 Android Studio
- **ADB 多设备管理**:WSL2 mirrored 网络下的端口冲突、网络 ADB 的持久性差异、USB→TCP 引导
- **厂商侧载封锁**:TCL 电视固件级 `INSTALL_FAILED_VERIFICATION_FAILURE` 的完整分析与绕行
- **Pico 4 开发约束**:`FLAG_SECURE` 截屏限制、ABI、无线调试持久性

## 示例工程

| 工程 | 定位 |
|---|---|
| [`apps/DualDemo`](apps/DualDemo/) | **测试验证工程**:一个 APK 同时跑在 Android TV 和 Pico 4 上的最小 Compose 工程,内置设备自检页 |

> `apps/` 下每个子目录都是**独立 Gradle 构建**。新增应用请用脚手架:
>
> ```bash
> bash tools/new-app.sh MyPlayer com.example.myplayer
> ```
>
> 完整约定见 [`docs/06-app-conventions.md`](docs/06-app-conventions.md)。

### 版本号

**唯一来源是仓库根的 [`version.properties`](version.properties)**,工程里不写版本字面量。
格式是严格 SemVer(`MAJOR.MINOR.PATCH`),第一个版本 `0.0.1`;`versionCode` 由它推导,
tag 名也取它。

```bash
bash tools/tag-release.sh --bump patch   # 0.0.1 -> 0.0.2
bash tools/tag-release.sh                # 校验 + 构建自检 + 打 tag + 推送
```

为什么、以及 `versionCode` 怎么算,见 [`docs/06`](docs/06-app-conventions.md#版本号)。

## 快速开始

```bash
# 1. 连接设备(见 docs/02)
bash tools/devices.sh

# 2. 构建
cd apps/DualDemo && ./gradlew assembleDebug

# 3. 安装
bash ../../tools/tv-install.sh app/build/outputs/apk/debug/app-debug.apk   # TCL 电视
adb -s 192.0.2.29:5555 install -r app/build/outputs/apk/debug/app-debug.apk  # Pico
```

## 环境假设

脚本按 WSL2 (Ubuntu) + Linux 版 adb 编写。Windows 原生环境需要把 `tools/*.sh` 里的
`/opt/android-sdk/platform-tools` 换成自己的 SDK 路径。

具体环境搭建步骤见 [`docs/01-headless-android-build.md`](docs/01-headless-android-build.md)。
