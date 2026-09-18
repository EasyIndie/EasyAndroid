# tools

设备连接 / 安装 / 引导脚本。**跨平台:Windows 原生(Git Bash)/ WSL2 / Linux 都能跑。**

路径都用 `$(dirname "${BASH_SOURCE[0]}")` 解析,可以从任意目录调用。
平台差异(adb 解析、超时命令、临时目录、python)统一在 `_common.sh` 里抹平,
详见它的头部注释。

## 跨平台速记

| | Windows 原生(Git Bash) | WSL2 / Linux |
|---|---|---|
| adb | `tools/platform-tools/adb.exe`(脚本自动解析) | 系统 PATH 里的 adb |
| USB 引导 Pico | 直接跑 `pico-usb.sh` | 同样跑 `pico-usb.sh`(它内部会调 Windows 侧 adb) |
| 构建应用 | 需自装 JDK 17 + Android SDK,设 `ANDROID_HOME` | `/opt/android-sdk`(见 docs/01) |
| 脚本临时文件 | `$TMP`(默认仓库 `.tmp/`,可用 `EASYANDROID_TMP` 覆盖) | `/tmp` |
| 侧载到电视 | `tv-install.sh` 直接可用(需 aapt2) | 同左 |

**别直接调 `timeout`** —— Git Bash 的 PATH 里 `C:\Windows\system32` 常排在前面,
`timeout` 命中的是 Windows 自带那个(语法是 `timeout /T 5`,不接受 GNU 写法)。
脚本里一律用 `_common.sh` 导出的 `run_timeout`。

**Windows 原生 python 的路径** —— Git Bash 的 `/e/foo` 对 Windows python 是
不存在的路径。把路径传给 python 前过 `pyfile`(在 `_common.sh` 里)。

**`win_of` 是「按需转换」,`winpath` 是「无条件转换」,`gitpath` 是「按需 + 混合形式」** ——
三者服务不同场景:

- **`win_of`**:只在 Windows 原生 shell 里转。它服务 `$ADB` / `$PY`,而那两个在
  WSL 上就是 Linux 版,**POSIX 路径才对** —— 在 WSL 上原样返回不是漏了 `wslpath`,
  而是这样才对。同类的还有 `new-app.sh` 写 `sdk.dir`。
- **`winpath`**:不做平台判断,**无条件**转成 Windows 路径。服务那些「无论如何
  都是 Windows 原生程序」的消费方,典型是 Windows 版 `gh.exe` 从 WSL 里调。
  踩过:把 `/mnt/e/.../x.apk` 直接传给 gh 上传,报 `no matches found for /mnt/e/...`。
- **`gitpath`**:和 `win_of` 一样按平台判断(git 在 WSL 上是 Linux 程序),但给的是
  **混合形式** `E:/EasyAndroid`(cygpath `-m`)而不是反斜杠。因为 `$REPO` 除了喂
  `git -C`,还大量用于 `"$REPO/version.properties"` 这类 **bash 侧**拼接 ——
  反斜杠会拼出 `E:\EasyAndroid/version.properties`,能用但很脆。

判断标准就两句话:**消费路径的那个程序,会不会随平台换实现?** 会 → `win_of` / `gitpath`;
不会 → `winpath`。**转出来的路径还要不要给 bash 用?** 要 → 用 `gitpath` 的混合形式,
避免反斜杠。

**为什么必须显式转,不能靠 Git Bash 的自动转换**:平时 Git Bash 会把 POSIX 路径自动
转成 Windows 路径再交给原生程序,但这个转换**可以被关掉**
(`MSYS_NO_PATHCONV=1` + `MSYS2_ARG_CONV_EXCL=*` —— WorkBuddy 的沙箱就设了这两个)。
关掉之后 bash 自带命令照样认 `/e/...`,而 `adb.exe` / `git.exe` 全都不认。
**所以「原生程序不认 `/e/...`」是条件成立的** —— 你自己的 Git Bash 窗口里其实认,
但在沙箱/部分 CI 里不认,报错还会指错方向(`git -C /e/...` 会让人以为仓库坏了)。

## 脚本

### `devices.sh` — 连接并列出设备

```bash
bash tools/devices.sh
```

对目录里的两台设备(电视 + Pico)逐个 `adb connect`,然后打印状态表。
日常开工第一条命令。

### `new-app.sh` — 新建独立工程

```bash
bash tools/new-app.sh <AppName> <package.id>
bash tools/new-app.sh MyPlayer com.example.myplayer
```

以 `apps/DualDemo` 为模板生成 `apps/<AppName>/`,并完成:

- 替换包名(`namespace` / `applicationId` / 源码目录结构)
- 设置 `rootProject.name` 和 `app_name`
- 清掉构建产物与旧 `local.properties`
- 根据 `$ANDROID_HOME` 重新生成 `local.properties`(Windows 上自动转成本机路径格式)
- 生成 README 骨架
- 检查 `applicationId` 与已有工程是否冲突

约定见 [../docs/06-app-conventions.md](../docs/06-app-conventions.md)。

### `ui-dump.sh` — 触发应用自截图并拉回 PNG

```bash
bash tools/ui-dump.sh <applicationId>                # 默认设备 = PICO_ADDR
bash tools/ui-dump.sh <applicationId> "$TV_ADDR"     # 指定设备
bash tools/ui-dump.sh <applicationId> --launch       # 先拉起应用
```

给 `FLAG_SECURE` 设备(如 Pico 4)用的 —— 那种设备 `screencap` 只能抓到纯白图。
要求应用集成了 debug 自截图钩子(`apps/DualDemo/app/src/debug/`),
原理见 [../docs/07-debug-ui-capture.md](../docs/07-debug-ui-capture.md)。

取图有两条路径,脚本自动选择:Android ≤10 直接 `adb pull` 外部目录;
**Android 11+ 上 shell 读不了 `/sdcard/Android/data/`**,改用
`adb exec-out run-as <pkg> cat files/ui-dump.png`。

### `gen-keystore.sh` — release 签名凭据:生成 / 查看 / 导出 / 导入 / 核对

```bash
bash tools/gen-keystore.sh                       # 首次生成(已存在则拒绝)
bash tools/gen-keystore.sh --status              # 路径 / 别名 / 指纹 / 有效期(不打印密码)
bash tools/gen-keystore.sh --add-alias <AppName> # 给单个应用加一把专用密钥(推荐)
bash tools/gen-keystore.sh --manifest            # 对仓里 signing-manifest.txt 自检指纹
bash tools/gen-keystore.sh --manifest --write    # 更新那个文件(加了别名之后跑)
bash tools/gen-keystore.sh --drill <凭据包>      # 恢复演练:临时目录里真跑一遍导入 + 核对指纹
bash tools/gen-keystore.sh --drill f --record --label "在哪"   # 记日期 + 位置进 manifest
bash tools/gen-keystore.sh --scan [目录]         # 扫出所有密钥材料副本(改名/换扩展名也躲不掉)
bash tools/gen-keystore.sh --export [文件]       # 导出单个自包含凭据包 → 存密码管理器 / CI Secret
bash tools/gen-keystore.sh --push-secret         # 直接把凭据包写进仓库的 Actions secret
bash tools/gen-keystore.sh --import <文件>       # 换机器 / 灾后恢复(先验后写,会核对指纹)
bash tools/gen-keystore.sh --verify-against <apk># 本机密钥与某个已发布 APK 是不是同一把
bash tools/gen-keystore.sh --force               # ⚠️ 覆盖重建 = 换签名,老用户升不了级
```

产出 `tools/keystore/release.jks` + 仓库根 `keystore.properties`(都已 gitignore)。
密码默认随机 28 位,只落进 properties,不打印到控制台。

**多应用:同一个 `.jks` 里每个应用一个别名**,而不是所有应用共用一把 ——
同签名下的应用可互信(能取得对方 `signature` 级权限保护的组件),
而分开的代价只是多一个别名(仍然只备份一个文件)。
已发布过的应用不要改别名(等于换签名)。

**为什么需要密钥**:AGP 默认产出的 `app-release-unsigned.apk` **装不上设备**,
要发正式版 APK 就得有 release 密钥。它等同私钥 ——
丢 = 已装机应用永远无法升级,泄露 = 别人能以你的名义发版。

没有密钥时工程也能构建(只是产出 unsigned 包),
因为 `app/build.gradle.kts` 是「找到 `keystore.properties` 才配 `signingConfig`」。

> ⚠️ 核对指纹时别用眼睛比:`keytool` 是大写带冒号,`apksigner` 是小写无冒号。
> 用 `--verify-against` / `--manifest` / `--drill`,它们归一化后机械比对。
>
> **凭据本体不能入库,但 `signing-manifest.txt`(只有指纹)可以,而且应该** ——
> `release-apk.sh` 会查它:签名不在清单里就直接拒绝发布。
>
> ⚠️ **凭据包不要用「终端粘贴」当传输方式**:Linux 终端规范模式单行上限 4096
> (`MAX_CANON`)。导出默认折行 76 列就是为这个 —— 折行后实测完整无损;
> 单行长行会被静默截断(探针会认出来并提示)。文件传输没有这个限制。
>
> **从聊天/邮件里粘回来的文本可以直接验。** 解析器宽容处理折行、发送者、
> 时间戳、末尾粘在负载上的「已读」、BOM/CRLF;但**验证是严格的** ——
> 完整解压 + 确认 tar 里有 `release.jks` 和 `keystore.properties`,不是只看格式。
> 截断或被改动会明确报出来。实测覆盖了 7 种粘贴形态(含折到 20 列)。
>
> **备份会悄悄过期**,所以除了「存」还得能「验」:
>
> | 问题 | 命令 |
> |---|---|
> | 这份备份**能恢复**吗? | `--drill <凭据包> --record` |
> | 本机这把**对不对**? | `--manifest` |
> | 我到底**有几份副本**? | `--scan` |
>
> `--scan` 比内容哈希,所以改名、换扩展名、去掉扩展名都躲不掉;
> **任何多出来的副本都算失败**(会进 `verify-all.sh`)。
> 实测靠它发现 `--push-secret` 每次都在 `.tmp/` 漏一份完整凭据包。
>
> 存哪儿 / 什么能入库 / 怎么保证半年后还找得到,
> 见 [../docs/06-app-conventions.md](../docs/06-app-conventions.md#签名凭据存哪儿--什么能入库什么不能)。

### `release-apk.sh` — 构建正式版 APK 并挂到 Release

```bash
bash tools/release-apk.sh <version>              # 构建,产物落 dist/
bash tools/release-apk.sh <version> --upload     # 顺便上传到 GitHub Release
bash tools/release-apk.sh <version> --with-debug # 额外附上 debug 包(带自截图钩子)
```

关键点:**它不用当前工作区构建**,而是在临时 git worktree 里 checkout 那个 tag ——
Release 附件必须能从 tag 复现。逐个校验已签名 / `versionName` / `versionCode` /
不含 debug 钩子,不过关就不上传。

> ⚠️ release 包与 debug 包签名不同,同一台设备上换装要先 `adb uninstall`。

### `release.sh` — 发版(推荐入口,一条命令)

版本号从提交信息推导,CHANGELOG 自动生成,CI 接手出包。**日常发版只需要它。**

```bash
bash tools/release.sh             # 推导 → 写 CHANGELOG → 提交 → 打 tag → 推
bash tools/release.sh --dry-run   # 先看将要发生什么(一个字节都不改)
bash tools/release.sh --check     # 只校验(提交规范 / 工作区干净 / 已推送)
bash tools/release.sh --title "…" # 覆盖自动生成的版本标题
bash tools/release.sh --as patch  # 强制段位(该发但推导说不用发时)
bash tools/release.sh --version 1.0.0
bash tools/release.sh --no-verify        # 跳过构建自检
bash tools/release.sh --check-commits    # 只校验提交信息规范(CI 里跑的就是它)
bash tools/release.sh --backfill         # 从所有 tag 重建 CHANGELOG.md
```

段位推导:`feat`→MINOR,`fix`/`perf`→PATCH,`!`/`BREAKING CHANGE`→MAJOR
(`0.x` 阶段升 MINOR),其余类型不发版。完整约定见
[docs/06-app-conventions.md](../docs/06-app-conventions.md#发版流程)。

> 提交信息里 `type(scope)!: 描述` 的 `!` 是**不兼容变更**的标记,会传染版本号,
> 所以别随手加。类型列表(规范里可用的):
> `feat` `fix` `perf` `docs` `refactor` `test` `style` `ci` `build` `chore`。

---

### `tag-release.sh` — 打发布 tag(tag 名 = version.properties 的 version)

> 这是**机制层**:只保证「tag 名 == version.properties 的 version」。
> 日常发版用上面的 [`release.sh`](#releasesh--发版推荐入口一条命令),它会调这个脚本。

```bash
bash tools/tag-release.sh --check          # 只校验,不改动任何东西(可放 CI)
bash tools/tag-release.sh --bump patch     # 把 version 涨一格(major|minor|patch)
bash tools/tag-release.sh                  # 校验 + 构建自检 + 打 tag + 推送
```

**为什么需要它**:本仓库出现过 tag=`0.0.1` 而 APK 里 `versionName=0.1.0` 的漂移。
tag 名只能来自 [`version.properties`](../version.properties),脚本把这条约束变成机械检查:
工作区是否干净、是否已推送、`apps/` 下有没有残留版本字面量,
以及**构建出来的 APK 里的 `versionName` 是不是就是那个版本**(它内部会跑
`verify-all.sh --build-only`)。

默认会跑构建自检(约 1~2 分钟)。已经单独跑过 `verify-all.sh` 时用 `--no-verify` 跳过。

完整约定见 [../docs/06-app-conventions.md](../docs/06-app-conventions.md#版本号)。

### `verify-all.sh` — 工具链自检

```bash
bash tools/verify-all.sh                # 环境 → 构建 → Pico → 电视 → 汇总
bash tools/verify-all.sh --build-only   # 只验环境 + 构建(不需要设备)
```

换机器、升级 SDK 之后跑一次就知道有没有坏。设备不在线会自动跳过并标 SKIP,
不算失败,所以 CI 上也能跑。缺什么(比如 Windows 上没装 JDK/SDK)会明确列出来。

### `device-status.sh` — 设备状态一次性报告

```bash
bash tools/device-status.sh                          # 默认 TV
bash tools/device-status.sh "$PICO_ADDR"             # 指定设备
bash tools/device-status.sh "$TV_ADDR" com.example.dualdemo   # 顺带查某个包
```

一次输出:型号 / 系统 / ABI → 目标包是否安装及版本 → 当前前台 → 最近崩溃 → 当前界面全部文案。

全部是纯文本,**不消耗多模态 token**。写自动化或排查问题时先跑这个。
(Pico 上最后一段「界面文案」会失败,那是系统限制,见 docs/04。)

### `pico-panel.sh` — 给 Pico 的 2D 面板定向注入按键/触摸

```bash
bash tools/pico-panel.sh <pkg> awake                  # 拉起应用 + 保持头显不睡
bash tools/pico-panel.sh <pkg> display                # 只打印解析出的面板 displayId
bash tools/pico-panel.sh <pkg> key   KEYCODE_DPAD_DOWN
bash tools/pico-panel.sh <pkg> tap   800 300
bash tools/pico-panel.sh <pkg> swipe 800 700 800 200 300
```

**为什么需要它**:Pico 给每个应用建一个独立虚拟 display,而 `adb shell input` 默认打到
display 0(`com.pvr.vrshell`)—— 所以裸 `input keyevent` **到不了你的应用**,而且不报错。
必须加 `-d <该应用的 displayId>`,那个 id 还**每次启动都变**。脚本负责现取 id、
校验面板是不是 `state ON`(头显睡了会静默失败),并在失败时给出提示。

原理与实测数据见 [../docs/04-pico4-notes.md](../docs/04-pico4-notes.md#输入必须定向到应用自己的虚拟-display)。

> 验证有没有送达:**不要看命令是否报错**,要对比前后两张自截图。
> 若被丢弃,`logcat` 里会有 `Dropping key targeting non-focused display`。

### `tv-install.sh` — 装到 TCL 电视

```bash
bash tools/tv-install.sh apps/DualDemo/app/build/outputs/apk/debug/app-debug.apk
LABEL=双端演示 TV=192.0.2.11:5555 bash tools/tv-install.sh <apk>   # 手动指定
```

**为什么需要它**:TCL 在固件里封掉了 `adb install`(`INSTALL_FAILED_VERIFICATION_FAILURE`),
唯一可用通道是 TGuard 的图形化安装器。脚本用 `adb input keyevent` + `uiautomator dump`
模拟走完那条路径,不消耗多模态 token。

**耗时约 60~80 秒**(按键批量化 + 位置缓存后,比最初实现快一倍)。
装完会**自动启动并截一张图**(调 `ui-dump.sh`),所以一次命令就能同时确认
「装好了」和「长这样」。用 `--no-shot` 关掉,`--shot-out <path>` 改输出路径。

需要 aapt2 读 APK 信息(脚本自动找 `aapt2` 和 `aapt2.exe`)。**没装 Android SDK 的
机器上 aapt2 是可选的**:用环境变量手动给元信息即可,

```bash
PKG=com.example.dualdemo VER=0.0.1 ACTIVITY=com.example.dualdemo.MainActivity \
  bash tools/tv-install.sh apps/DualDemo/app/build/outputs/apk/debug/app-debug.apk
```

(PKG 必须给;VER 缺省则跳过装后版本校验;ACTIVITY 缺省则装完不自动启动。)

需要高频迭代时优先用 Pico —— 它接受普通 `adb install`,只要 2~3 秒。

完整背景见 [../docs/03-tcl-tv-sideload.md](../docs/03-tcl-tv-sideload.md)。

变量:

| 变量 | 默认 | 说明 |
|---|---|---|
| `TV` | `192.0.2.11:5555` | 设备 serial |
| `LABEL` | 从 APK 里读 `application-label` | 在安装列表里匹配的标签 |

### `pico-usb.sh` — Pico 重启后恢复无线调试

```bash
bash tools/pico-usb.sh        # USB 线插在本机
```

Pico 的 `persist.adb.tcp.port` 写不进去(需 root),所以**每次重启后**都要重新
`adb tcpip 5555` 一次。这个脚本做这件事,约 10 秒。

Windows 原生上直接用当前 adb.exe;WSL2 上自动找 `tools/platform-tools/adb.exe`
(WSL2 没有 USB 总线,这一步必须由 Windows 侧 adb 完成)。

日常规避:**别关机,用待机**,adbd 不会重启。

见 [../docs/02-adb-multi-device.md](../docs/02-adb-multi-device.md#pico-的规避方式)。

### `fetch-platform-tools.sh` — 拉 Windows 版 platform-tools

```bash
bash tools/fetch-platform-tools.sh
```

**WSL2 上必需**(给 `pico-usb.sh` 用)。Windows 原生上通常**不需要** ——
你本地的 adb 本来就是 adb.exe,脚本会直接复用;只有机器上完全没装
platform-tools 时才需要拉一份。产物落在 `tools/platform-tools/`(**已 gitignore**,不入库)。

---

## 前置条件

### 设备地址配置

脚本不硬编码任何设备地址。第一次用先建本地配置(已 gitignore):

```bash
cp tools/device.env.example tools/device.env
# 编辑填入你的设备地址
```

| 变量 | 说明 |
|---|---|
| `TV_ADDR` | 电视 serial,如 `192.0.2.11:5555` |
| `PICO_ADDR` | 第二台设备 |
| `ADB` | 覆盖 adb 可执行文件路径(默认自动解析,一般不用设) |
| `ANDROID_SDK_DIR` / `ANDROID_HOME` | SDK 位置(构建类脚本用;Windows 上也会自动探测 `%LOCALAPPDATA%\Android\Sdk`) |
| `EASYANDROID_TMP` | 覆盖临时目录(默认:Windows 上仓库 `.tmp/`,Linux 上 `/tmp`) |
| `WINADB` | Windows 版 adb 路径(WSL2 上 USB 引导用,自动探测) |
| `WINADB_PORT` | Windows 侧 adb server 端口(仅 WSL2 需要错开,默认 `15037`) |

统一由 [`_common.sh`](_common.sh) 载入,所以换设备不用改代码。

### 其他

| | 要求 |
|---|---|
| adb | 自动解析:`$ADB` > `tools/platform-tools/` > 系统 PATH |
| JDK 17 | `tv-install.sh` / 构建需要;`JAVA_HOME` 或常见安装位置自动探测 |
| aapt2 | `$ANDROID_HOME/build-tools/<版本>/aapt2[.exe]`,脚本自动找 |
| Python 3 | 解析 `uiautomator` 的 XML(`python3` 或 `python` 都行) |

## 为什么 WSL2 还需要一份 Windows 版 adb

WSL2 **没有 USB 总线**(`/dev/bus/usb` 不存在,也没有 `usbip` 内核模块),
插在 Windows 上的设备 WSL 看不见。

所以「USB 引导 Pico」这一步必须由 **Windows 侧** 的 adb 完成。
Windows 那份固定跑在 **15037** 端口 —— 因为 `.wslconfig` 是 `networkingMode=mirrored`,
两边共享 localhost,抢同一个 5037 会起不来。

Windows 原生环境没有这个问题(只有一个 adb,直接用默认端口)。

详见 [../docs/02-adb-multi-device.md](../docs/02-adb-multi-device.md#-核心坑wsl2-mirrored-网络下只能有一个-adb-server)。
