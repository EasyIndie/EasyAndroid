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

### 开发循环

从「改一行代码」到「发布」的完整路径。每层都比上一层快,所以**先用快的**:

| 层 | 命令 | 耗时 | 能验什么 |
|---|---|---|---|
| 1. JVM 截图测试 | `cd apps/<Name> && ./gradlew testDebugUnitTest` | ~20 s | 布局/颜色/文案。不碰设备 |
| 2. Pico 4 | `bash tools/ui-dump.sh <pkg> --launch` | ~3 s 装 + 截图 | 真机渲染、交互、D-pad 焦点 |
| 3. TCL 电视 | `bash tools/tv-install.sh <apk>` | **60~80 s** | 里程碑验收(走 TGuard 图形安装器) |

约束(不看会做错事,细节在 [`AGENTS.md`](AGENTS.md) 和 [`docs/`](docs/README.md)):

- **开发/验收全程用 debug 包**,只有发版才出正式包 —— 自截图钩子只在 debug 里。
- **Pico 输入必须定向**到应用自己的 display(`tools/pico-panel.sh`),且它十几秒不戴
  就休眠,先 `awake`。电视的 `input tap` 基本失效,用 D-pad 按键。
- **优先用文本验收**(`uiautomator dump` 读 UI 树),别截图:电视截图 md5 因 UI 自走
  而不可靠,Pico 截图被 `FLAG_SECURE` 挡。
- **提交信息写 `type(scope): 描述`** —— 版本号从它推导(见下)。

### 发版

**一条命令。** 版本号从提交信息机械推导,CHANGELOG 自动生成,CI 接手出包:

```bash
bash tools/release.sh
```

就这样。它会:读「上一个 tag..HEAD」的提交 → 推导段位 → 写 `version.properties`
和 [`CHANGELOG.md`](CHANGELOG.md) → 提交 → 打 tag → 推 → **CI 构建签名包并建 Release**。

```bash
bash tools/release.sh --dry-run    # 先看将要发生什么,一个字节都不改
```

| 提交信息 | 效果 |
|---|---|
| `feat: …` | MINOR |
| `fix: …` / `perf: …` | PATCH |
| `feat!: …` 或正文含 `BREAKING CHANGE` | MAJOR(`0.x` 阶段升 MINOR) |
| `docs:` / `chore:` / `refactor:` / `test:` … | 不发版 |

> **版本号是从提交信息推导的,所以提交信息是规范的一部分**,不是风格偏好 ——
> 写成 `type(scope): 描述`。CI 会校验(`tools/release.sh --check-commits`)。
> 一条 `feat`/`fix` 都没有时 `release.sh` 会告诉你**不该发版**,这是对的:
> 版本号是给使用者看的「有什么变了」,不是「仓库动过」。

**版本号的唯一来源**是 [`version.properties`](version.properties),工程里不写版本字面量;
格式是严格 SemVer,`versionCode` 与 tag 名都从它推导。

为什么这么定、`versionCode` 怎么算、以及需要人工介入时的逃生门
(`--as` / `--version` / `--backfill`),见
[`docs/06-app-conventions.md`](docs/06-app-conventions.md#发版流程)。

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

**脚本已跨平台**(2026-09 起):Windows 原生(Git Bash)、WSL2、Linux 都能跑。
adb、超时命令、临时目录、python 的平台差异统一在 `tools/_common.sh` 里抹平,
平台速查表见 [`tools/README.md`](tools/README.md) 的「跨平台速记」。

- **Windows 原生**:adb 自动解析到 `tools/platform-tools/adb.exe`;构建应用需要
  自装 JDK 17 + Android SDK(脚本会探测 `%LOCALAPPDATA%\Android\Sdk`)。
- **WSL2**:按 [docs/01](docs/01-headless-android-build.md) 搭 `/opt/android-sdk`;
  USB 引导 Pico 仍走 Windows 侧 adb(WSL2 没有 USB 总线)。

具体环境搭建步骤见 [`docs/01-headless-android-build.md`](docs/01-headless-android-build.md),
Windows 侧的坑见 [`docs/05-gotchas.md`](docs/05-gotchas.md) 的第一节。

## 许可

[MIT](LICENSE) © 2026 wangzhizhou
