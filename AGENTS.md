# AGENTS.md

给 AI 编码智能体的仓库说明。人类读者请看 [README.md](README.md)。

本仓库是 **Android 真机开发实践的沉淀库**,同时也是一个可直接构建/部署的工程仓库。

---

## 0. 硬性规则

1. **不要提交 `tools/device.env`** —— 里面有真实设备地址,已在 `.gitignore`。
   需要新增配置项时改 `tools/device.env.example`。
2. **不要提交 `tools/platform-tools/`** —— 上游二进制,用 `tools/fetch-platform-tools.sh` 拉取。
3. **不要把真实内网 IP 写进任何被跟踪的文件**。文档里统一用 `192.0.2.x`(RFC 5737 文档保留段)。
4. **不要跑 `adb install` 去装 TCL 电视** —— 必然失败,见第 3 节。
5. **优先用文本手段验收 UI,不要截图** —— 见第 4 节。
6. **不要在代码里写版本号字面量** —— 唯一来源是仓库根的 `version.properties`
   (严格 SemVer,第一个版本 `0.0.1`)。`versionName` / `versionCode` / 界面上显示的版本
   全部从它推导。**发版是一条命令:`bash tools/release.sh`** —— 它从提交信息推导段位,
   自动写 version.properties 与 CHANGELOG.md,然后提交、打 tag、推,CI 接手出包。
   见 [docs/06](docs/06-app-conventions.md#发版流程)。
   由此:**提交信息必须写 `type(scope): 描述`**(Conventional Commits)——
   版本号是从它机械推导的,CI 会校验。
7. **签名密钥绝对不能入库** —— `tools/keystore/`、`keystore.properties`、`*.jks` 已在
   `.gitignore`。往仓库里放任何密钥文件前先确认 `.gitignore` 拦得住。
   ⚠️ **`gen-keystore.sh --export` 出来的凭据包文件名不在黑名单里,得自己注意** ——
   它是 base64(不是加密),解出来就是密钥库 + 明文密码。
   ✅ 但**指纹可以入库**:仓库根的 `signing-manifest.txt` 是故意的 —— 它不是秘密,
   而且任何机器靠它能自检「手里这把是不是发布用的那把」;发版时会查它。
   要发带 APK 的 Release 见 [docs/06](docs/06-app-conventions.md) 的「发布正式版 APK」一节,
   存哪儿 / 什么能入库见「签名凭据:存哪儿」。
   ⚠️ **debug 签名不要「统一」—— 保持每环境各自一把,这是有意的。** `~/.android/debug.keystore`
   不存在就现生成,所以同一台机器上 WSL 一份、Windows 一份,换环境装包必然撞签名。
   别为省这一步把它入库或共享,**尤其别用 `release.jks` 签 debug**(debug 包带
   `debuggable` 且会外发)。撞上就 `adb uninstall` 重装,判据与取舍见
   [docs/06](docs/06-app-conventions.md) 的「debug 凭据」一节。
8. **开发/验收全程用 debug 包,只有发版才出正式包 + 加签。**
   `tools/verify-all.sh` / `tv-install.sh` / `ui-dump.sh` 这条循环里装的、验的都是
   debug 包(它带自截图钩子,`screencap` 拿不到画面的设备靠它才能验收)。
   构建正式包的**唯一**入口是 `tools/release-apk.sh`,它会校验产物
   「非 debuggable / 无 debug 钩子」—— 防止把 debug 包装成正式包发出去。

   两者签名不同,同一台设备上换装要先 `adb uninstall`。
   **在真机上验收过正式包之后,记得把 debug 包装回去** —— 否则下次 `ui-dump.sh`
   会失败(自截图钩子只在 debug 包里)。这个失败现在能自解释:`ui-dump.sh` 会认出
   「设备上装的是正式包」并直接给出换装命令,不需要你去猜是不是「没集成钩子」。
   见 [docs/06](docs/06-app-conventions.md) 的「构建与发布」一节。
9. **`tools/` 下的脚本是跨平台的**(Windows 原生 Git Bash / WSL2 / Linux)。
   ⚠️ **但不包括 PowerShell。** PowerShell 里的 `bash` 是 WSL 启动器
   (`C:\Windows\System32\bash.exe`,不是 Git 自带的那个),它把参数
   **拼成一条 `bash -c` 字符串**重新解析 —— 引号被剥掉,空格/括号/`;`/`$()`
   全部重新获得 shell 语义(既是语法错误的来源,也是注入面);`./x` 里的
   反斜杠还会被当转义符,路径静默变错。要用 bash 就开 WSL 或 Git Bash 终端。
   见 [docs/05](docs/05-gotchas.md) 的「Windows 上不要用 PowerShell 跑」一节。
   写新脚本或改现有脚本时:
   - 不要直接调 `timeout` / `mktemp` / `adb` / `python3`,用 `_common.sh` 导出的
     `run_timeout` / `mktmp` / `$ADB` / `$PY`;
   - 路径传给 python 或其他 Windows 原生程序前过 `pyfile`;
   - 需要正则转义用 `re_escape`,纯字面量替换用 python `str.replace`(别用 sed);
   - 脚本开头调一次 `adb_connect_all`(沙箱/CI 里 daemon 不跨进程存活);
   - 判断设备在线用 `adb_online`,别手写 `adb devices | awk`。
   平台差异全表见 `tools/_common.sh` 头部注释和 [tools/README.md](tools/README.md) 的「跨平台速记」。
10. **改 CI 时:runner 保持显式 pin,action 主版本不要往下调。**
   `.github/workflows/` 里的 `runs-on` 写的是具体的 `ubuntu-24.04`,**不要换回
   `ubuntu-latest`** —— 它 2026-10-19 起会迁到 Ubuntu 26.04,而两个 runner 镜像的
   Android SDK 差别恰好落在 `cmdline-tools`(12.0 → 20.0),正是 `verify-all.sh` 会查的
   东西。换 OS 等于换构建环境,要单独开一次、先在 CI 上验过,别夹在功能开发里。
   同理,action 主版本要留在「跑 Node 24」的那一档(`checkout@v7` / `setup-java@v6` /
   `upload-artifact@v7`);停在 Node 20 的旧主版本会让每次 CI 都刷一条弃用警告。
   理由与迁移判据都写在 `.github/workflows/ci.yml` 的注释里,升级前先读那份 `action.yml`
   确认用到的输入还在。

---

## 1. 仓库结构

```
docs/            知识沉淀(踩坑、结论、绕行方案)
apps/            可运行的 Android 工程(每个子目录是一个独立 Gradle 构建)
tools/           设备连接 / 安装 / 引导脚本 / 发版
CHANGELOG.md     版本历史 —— 由 tools/release.sh 自动生成,不要手改
version.properties  版本号唯一来源
  _common.sh             共用的配置载入逻辑(所有脚本 source 它)
  device.env.example     设备地址模板 → 复制成 device.env(不入库)
```

### 新增应用必须遵守

> **在 `apps/` 下新建独立工程目录,不要往已有工程里塞业务模块。**

```bash
bash tools/new-app.sh <AppName> <package.id>
# 例: bash tools/new-app.sh MyPlayer com.example.myplayer
```

- 每个工程自带 `settings.gradle.kts` + `gradlew` + `gradle/wrapper/`,**仓库根目录没有** `settings.gradle.kts`
- 工程之间**不共享代码**;要复用的放 `tools/` 或 `docs/`
- `apps/DualDemo` 是**测试验证工程**,保持精简,**不要往里加业务功能**
- `applicationId` 每个工程必须不同(否则装到同一台设备会互相覆盖)

完整约定(目录清单、命名、**版本号与发版流程**、版本组合、README 要求)见
[docs/06-app-conventions.md](docs/06-app-conventions.md) —— **动手前先读它**。

写文档前先看 [docs/README.md](docs/README.md) 的索引,不要重复已有内容。

---

## 2. 构建

```bash
cd apps/DualDemo
./gradlew assembleDebug
# → app/build/outputs/apk/debug/app-debug.apk
```

| 情况 | 处理 |
|---|---|
| 首次构建 | 要拉 AGP/Kotlin/Compose,约 3 分钟,属正常 |
| 报 TLS 握手失败 / "Remote host terminated the handshake" | **不是网络问题**,是并发拉依赖被限流。加 `--no-daemon --console=plain --max-workers=2` 重跑 |
| `sdk.dir` 找不到 | `apps/*/local.properties` 是机器相关的,已 gitignore。内容: `sdk.dir=/opt/android-sdk` |
| `local.properties` 缺失且无 `ANDROID_HOME` | 导出 `ANDROID_HOME=/opt/android-sdk` 也可以 |

环境搭建全流程见 [docs/01-headless-android-build.md](docs/01-headless-android-build.md)。

---

## 3. 安装到设备

### 第一步永远是连设备

```bash
bash tools/devices.sh
```

输出里两台都是 `device` 才能继续。若是 `unauthorized`,说明设备上还没点授权弹窗 —— 需要人工确认,不要尝试绕过。

### TCL 电视:必须用专用脚本

```bash
bash tools/tv-install.sh apps/DualDemo/app/build/outputs/apk/debug/app-debug.apk
```

**不要用 `adb install`**,一定会得到:

```
Failure [INSTALL_FAILED_VERIFICATION_FAILURE]
```

TCL 在 system_server 里打了 `OverseasAppConfig` 补丁,**绕过了 AOSP 的 verifier 逻辑**,
所以 `settings put global verifier_verify_adb_installs 0` 之类的常规解法全部无效。

`tv-install.sh` 走的是 TGuard 的图形化安装器(`安全卫士 → 应用管理 → 应用安装`),
用 `adb input keyevent` + `uiautomator dump` 模拟走完,不消耗多模态 token。

它会自动把 APK 推到 **U 盘的 `AndroidTV/` 目录**(安装器只扫可移动存储,不扫 `/sdcard`),
并重建 TGuard 的扫描缓存。**前提是电视上插着一个可写的 U 盘。**

> **耗时约 60~80 秒**,这是固件限制下的下限,不是脚本没优化。
> 需要高频迭代时优先用 Pico(普通 `adb install`,2~3 秒),
> 电视只在里程碑做验收。详见 [docs/03](docs/03-tcl-tv-sideload.md#安装耗时为什么快不起来)。
>
> 脚本装完会**自动启动并截一张图**(等价于 `tools/ui-dump.sh`),
> 所以一次命令就能确认「装好了 + 长这样」。`--no-shot` 可关。

完整分析(含所有失败尝试的清单)见 [docs/03-tcl-tv-sideload.md](docs/03-tcl-tv-sideload.md)。
**改动这个脚本前先读那篇文档**,否则会重复踩已经排除过的坑。

### Pico / 普通设备

```bash
adb -s "$PICO_ADDR" install -r app/build/outputs/apk/debug/app-debug.apk
```

Pico 重启后无线 ADB 会失效(持久属性写不进去),需要:

```bash
bash tools/pico-usb.sh    # 需要 USB 线插在 Windows 主机上
```

**在 Pico 上干活前必须先记住这两条,否则所有命令都会「返回成功但什么都没发生」:**

1. **不戴头显 ~10 秒就休眠**,应用会被 `onPause`,之后的 `am start` / 自截图全部静默失败
   (自截图会报「没有处于 resumed 状态的 Activity」)。先跑
   `bash tools/pico-panel.sh <pkg> awake`。
2. **裸 `input keyevent` 到不了你的应用**。Pico 给每个应用建独立虚拟 display,
   而 `input` 默认打到 display 0(`com.pvr.vrshell`)。必须定向注入:
   `bash tools/pico-panel.sh <pkg> key KEYCODE_DPAD_DOWN`。

完整原理见 [docs/04-pico4-notes.md](docs/04-pico4-notes.md)。

---

## 4. 验收:优先文本,别截图

**这是本仓库最重要的效率约定。**

```bash
# ✅ 首选:读 UI 树。信息量比截图大,且不吃多模态 token
adb -s "$TV_ADDR" shell uiautomator dump /sdcard/ui.xml
adb -s "$TV_ADDR" pull /sdcard/ui.xml /tmp/ui.xml

# ✅ 判断当前前台
adb -s "$TV_ADDR" shell dumpsys activity activities | grep -m1 mResumedActivity

# ✅ 看崩溃
adb -s "$TV_ADDR" logcat -d -t 300 | grep -iE 'FATAL|AndroidRuntime'
```

`uiautomator` 的 XML 里有 `text` / `content-desc` / `bounds` / `focused` / `focusable` / `clickable`,
够判断界面渲染对不对、焦点在哪。**对 TV 的 D-pad 焦点问题,这比截图还准。**

⚠️ **电视上不要用截图判「输入生效没」。** TCL 桌面/设置里的时钟、天气、动效一直在跑 ——
实测停在设置页**4 秒不发任何输入**,两张 `screencap` 的 md5 就不一样了(假阳性)。
判断变化要用 **UI 树的全量文案集合**(把全部 `text`/`content-desc` 拼起来取 md5),
不是截图,也不是只看前几条文案。

> 两台设备的验收信号是**相反**的:电视上可靠的是文案集合(截图不可靠),
> Pico 上只能靠自截图像素差(文案集合拿不到)。所以别写「通用」的验收逻辑。

⚠️ **列表里不在视口内的项在 UI 树里是不存在的。** `LazyColumn` / `RecyclerView`
只组合可见范围,没进视口就压根没被创建。写断言前先把目标项用 D-pad 滚进视口,
否则会把「在屏幕下面」误判成「界面没渲染」。实测同一界面 dump 到的文案数会从 24 变 25。

### 什么时候截图也不行 —— 改用「应用自截图」

**Pico 上 `screencap` 被系统禁止**。PICO 给每个应用建独立虚拟 display 且全部带 `FLAG_SECURE`:

```bash
adb -s "$PICO_ADDR" exec-out screencap -p > shot.png
# → 36 KB 的纯白图,没用。scrcpy 同理
```

**解法是让应用截自己**(`FLAG_SECURE` 只挡别的进程):

```bash
bash tools/ui-dump.sh <applicationId> --launch
# → 拉回一张真实渲染的 PNG
```

钩子在 `apps/<Name>/app/src/debug/`,**只在 debug 构建里**。`tools/new-app.sh`
生成的新工程自带。原理和限制见 [docs/07-debug-ui-capture.md](docs/07-debug-ui-capture.md)。

> 有了它,Pico 变成「装得快(3 秒)+ 看得见」的迭代设备。
> **高频改 UI 用 Pico + `ui-dump.sh`;电视一次装 60~80 秒,留给里程碑验收。**
> 但 Pico 上前提是**头显没睡**:先 `bash tools/pico-panel.sh <pkg> awake`,否则自截图必报
> 「没有处于 resumed 状态的 Activity」。

### 更快的一档:JVM 截图测试(不碰设备)

改布局/颜色/文案这类改动,**先跑这个**,不要动设备:

```bash
cd apps/<Name> && ./gradlew testDebugUnitTest
# → app/build/outputs/roborazzi/*.png
```

Robolectric + Roborazzi 在 JVM 上渲染 Compose,~20 秒出图。
`@Config(qualifiers = ...)` 换屏幕规格(`w1280dp-h720dp-240dpi` 就是那台电视)。

**⚠️ 它验不了 D-pad 焦点** —— Robolectric 下窗口没有焦点,`assertIsFocused()` 必然失败。
焦点必须上真机验(`input keyevent` + `uiautomator dump`)。
详见 [docs/08](docs/08-jvm-screenshot-testing.md)。

---

## 5. 交互:TV 没有触摸

电视全靠遥控 D-pad。用 `input keyevent`:

```bash
adb -s "$TV_ADDR" shell input keyevent KEYCODE_DPAD_UP      # 19
adb -s "$TV_ADDR" shell input keyevent KEYCODE_DPAD_DOWN    # 20
adb -s "$TV_ADDR" shell input keyevent KEYCODE_DPAD_LEFT    # 21
adb -s "$TV_ADDR" shell input keyevent KEYCODE_DPAD_RIGHT   # 22
adb -s "$TV_ADDR" shell input keyevent KEYCODE_DPAD_CENTER  # 23 确认
adb -s "$TV_ADDR" shell input keyevent KEYCODE_BACK         # 4
adb -s "$TV_ADDR" shell input keyevent KEYCODE_HOME         # 3
```

**`input tap` 在 TCL 的很多界面里不生效**(那些界面不是触摸式的),优先用按键。

### ⚠️ Pico 不是这样:必须定向到应用自己的虚拟 display

```bash
bash tools/pico-panel.sh <pkg> awake                     # 先确保头显没睡
bash tools/pico-panel.sh <pkg> key KEYCODE_DPAD_DOWN
bash tools/pico-panel.sh <pkg> swipe 800 700 800 200 300 # 触摸注入可用
```

Pico 给每个应用建独立虚拟 display,裸 `input` 默认打到 display 0(**不是你的应用**),
而且不报错。加了 `-d` 但 display id 是过期的同样不行 —— 日志里会有
`Dropping key targeting non-focused display`。**不要缓存 display id,每次现取**。

### ⚠️ 电视会自动进屏保

屏保期间 `am start` **返回成功但什么都不会发生**,日志里连 `ActivityTaskManager` 记录都没有。

```bash
adb -s "$TV_ADDR" shell input keyevent KEYCODE_WAKEUP
adb -s "$TV_ADDR" shell input keyevent KEYCODE_HOME
# 确认:前台不是 com.tcl.appreciate.art/...DreamActivity
```

排查任何「`am start` 没反应」的问题,先查屏保。

**两种形态**:常规屏保下上面这套能唤醒;但实测撞到过一种「屏保把之后**所有按键**全吞掉」
的状态(WAKEUP/BACK/HOME/CENTER/POWER 连发 15 秒都没用)。这时唯一有效的是
补一个**指针事件**—— TCL 遥控是 IR 触控,屏保只认指针:

```bash
adb -s "$TV_ADDR" shell input tap 960 540     # 屏幕中心
```

`tv-install.sh` 里已经内置了这个兜底。复现条件没定位到,当防御性代码看。

---

## 6. 写脚本时的必知事项

### `adb shell` 会吞掉后续命令的输出

非交互环境下 `adb shell` 占用 stdin,把脚本的输入流吃掉。**每条都要加 `</dev/null`**:

```bash
# ✗ 第二条开始全部无输出
adb shell wm size
adb shell wm density

# ✓
A(){ adb -s "$DEV" shell "$@" </dev/null 2>&1; }
```

### 所有脚本都要 source `_common.sh`

它负责载入 `device.env`、补 PATH、解析 `WINADB`:

```bash
# shellcheck disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/_common.sh"
```

不要硬编码设备地址或 SDK 路径。

### 原生程序的路径必须人工转换

**不只有 adb。** `git.exe` / `java.exe` / Windows 版 `gh.exe` 都是原生程序,
在 Git Bash 里拿到 `/e/foo` 这种 POSIX 路径**要么静默失败、要么报一个指错方向的
错**;而 bash 自己的重定向/`test`/`cd` 反而只认 POSIX 形式:

```bash
"$ADB" -s "$TV" pull /sdcard/x "$(win_of "$TMP/x")"   # ✓ 转换
something > "$TMP/x.log"                              # ✓ 保持 POSIX
```

规则:凡是**传给原生程序的本机路径**都要转,凡是 **bash 内部使用**(重定向、
`[ -f ]`、`cat`、`cd`)保持 POSIX。两处不能混。按消费方选转换函数:

| 消费方 | 用哪个 | 为什么 |
|---|---|---|
| `$ADB` / `$PY` / python | `win_of`(WSL 上是恒等) | 它们在 WSL 上就是 Linux 版,POSIX 才对。⚠️ **要转的是喂给它的路径参数**:`adb install "$apk"`、`adb pull <设备路径> <本机目标>` 里那个**本机**路径(别把设备路径也转了)。漏转时 `adb install` 只回一句 `failed to stat ...: No such file or directory` |
| Windows 版 `gh.exe`(从 WSL 调) | `winpath`(无条件) | 消费方不随平台变 |
| **`git`** | **`gitpath`**(WSL 上是恒等) | 同 adb:Win 原生 / WSL 是 Linux 版;且给**混合形式** `E:/...`,因为 `$REPO` 还要用于 bash 拼路径 |
| **JDK 工具(`keytool`)** | **`win_of`** | 同 adb:Win 上是原生 exe / WSL 上是 Linux 版。`gen-keystore.sh` 在唯一的入口 `kt()` 里按**参数名**(`-keystore`/`-srckeystore`/`-destkeystore`/`-file`)统一转,以后新增调用点不用各自操心 |
| **SDK build-tools 工具(`aapt2` / `apksigner`)** | **`win_of`** + **`bt_run`** | 同 adb:Win 上 `aapt2` 是 `.exe`、`apksigner` 是 `.bat`,都不认 `/e/...`;WSL/Linux 上是无后缀的 Linux 程序。⚠️ 要转的是**喂给它们的路径参数**(如 `dump badging <apk>` 里的那个 APK),不是工具自身的路径。调 `apksigner` 走 `bt_run apksigner ...` —— `.bat` 还会硬校验 `JAVA_HOME`,`bt_run` 顺带把它转成 Windows 形式 |
| 调 Windows 原生 python 时 | `pyfile`(= `win_of`) | — |

为什么会有这个坑:Git Bash 平时会把 POSIX 路径**自动**转成 Windows 路径再交给
原生程序,但这个转换**可以被关掉**(`MSYS_NO_PATHCONV=1` / `MSYS2_ARG_CONV_EXCL=*`,
WorkBuddy 的沙箱就设了这两个)。所以「不认 `/e/...`」是**条件成立**的 ——
在你自己的 Git Bash 窗口里 adb 和 git 其实都认,但**在自动转换被关掉的环境里
(agent 沙箱、部分 CI shim)全都认不得**,而且报错长这样:

```
$ git -C /e/EasyAndroid rev-parse HEAD
fatal: cannot change to '/e/EasyAndroid': No such file or directory
$ bash tools/release.sh --check
!! 不是 git 仓库?          ← 方向完全指错
```

显式转换过的路径(不管 `E:/...` 还是 `E:\...`)**两种环境都对** —— 所以一律显式转,
不要依赖那个开关。踩过的实例:`release.sh` / `tag-release.sh` / `release-apk.sh`
早期用 `git -C "$REPO"`($REPO 是 POSIX),在上述环境里三个脚本直接不可用。

### Windows 上不要用 `[ -x ]` 判断工具在不在

Git Bash 只给 `.exe` 打可执行位,**`.bat` 一律是 `-rw-r--r--`** —— 而 SDK 的
`cmdline-tools`(`sdkmanager.bat`)和 `build-tools` 里的 `apksigner` 恰好都是 `.bat`。

踩过(2026-09-18,装完 SDK 才暴露):`verify-all.sh` 用 `[ -x .../sdkmanager.bat ]`
判 cmdline-tools、`_common.sh` 的 `bt_tool` 用 `[ -x "$c" ]` 找 apksigner —— 两个都报
「缺失 / 找不到」,而文件就在那儿。这两处以前一直走 skip 分支(机器上压根没装 SDK),
装上之后才第一次真正执行到。

判断「工具在不在」一律用 `[ -f ]`;真正的可执行性让调用时的失败去暴露。

### 别在脚本运行时编辑它

bash 是**边读文件边执行**的,不是先把整个脚本读进内存。所以在长脚本(比如
`verify-all.sh`,要跑几分钟)执行期间编辑同一个文件,后半段就可能读到改写后的
内容,报出 `syntax error near unexpected token ...` 这类**跟真实语法无关**的错。

本次实测:同一份脚本 `bash -n` 完全通过,但构建期间顺手改了行注释就复现了一次 ——
很容易被当成「自己改坏了」而去乱改代码。要改就跑完再改(或改副本),然后重跑。

### 同一文件的几处修改要串行,改完回读核对

并行对**同一个文件**发多处修改,**只有最后写入的那处会留下**,其余会**静默消失**,
而每一处都会回报「成功」。原因是它们各自基于同一份旧内容计算,后写覆盖前写。

本次实测:对 `AGENTS.md` 一次发了两处修改(相隔几百行),两处都报成功,但只有一处
真正落盘 —— 直到发现 `git diff --stat` 只显示 1 处改动(预期 2 处)才察觉。

→ 同一文件改多处:**串行**做。批量改完**回读核对**(`grep` 一下改动里的锚点,
或看 `git diff` 的 hunk 数对不对),别只信「修改成功」的回报。

### 调 `.bat` 工具用 `bt_run`

`apksigner`(以及 cmdline-tools 的 `sdkmanager`)是**批处理脚本**,开头就硬校验
`%JAVA_HOME%\bin\java.exe` 在不在 —— 而基座的 `$JAVA_HOME` 是 POSIX 形式
(`/c/Program Files/...`),批处理认不出,直接报:

    ERROR: JAVA_HOME is set to an invalid directory: /c/Program Files/Eclipse Adoptium/jdk-17.0.20.101-hotspot

`java.exe` / `keytool.exe` **不会**暴露这个问题:它们是原生启动器,`JAVA_HOME`
无效时会安静地回落注册表,所以看起来「一切正常」。只有 `.bat` 会硬报错。

所以调 build-tools 的 `.bat` 一律走 `bt_run` —— 它只在**这一次子进程**里把
`JAVA_HOME` 转成 Windows 形式,不影响 bash 侧(gradlew 继续用 POSIX 的那份):

```bash
bt_run apksigner verify --print-certs "$(win_of "$apk")"
```

### 改完脚本至少做语法检查

```bash
for f in tools/*.sh; do bash -n "$f" || echo "FAIL: $f"; done
```

---

## 7. 提交前检查

```bash
# 1. 确认真实 IP 没进入被跟踪文件
#    用 git grep —— 它只扫被跟踪的文件,自然跳过 gitignore 的 tools/device.env
git grep -nE '192\.168\.[0-9]+\.[0-9]+'

# 2. 确认没有凭据
#    模式后面要求跟真实的 token 字符,这样不会匹配到文档里的示例文本
git grep -nE 'ghp_[A-Za-z0-9]{20,}|gho_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|x-access-token:[A-Za-z0-9]|BEGIN [A-Z ]*PRIVATE KEY'

# 3. 确认敏感文件没被跟踪
git ls-files | grep -E 'device\.env$|tools/platform-tools/'
```

三条都应该**零输出**。

> 推送时不要用 `git push "https://x-access-token:$TOKEN@github.com/..."` 配 `-u` —— token 会被写进
> `.git/config` 的 upstream 里。本仓库已配置好凭据助手(复用 Windows 上的 `gh`),直接 `git push` 即可。

---

## 8. 扩展指引

### 新建一个应用

用脚手架,不要手工拷:

```bash
bash tools/new-app.sh <AppName> <package.id>
```

它会以 `DualDemo` 为模板生成 `apps/<AppName>/`,替换包名/应用名/工程名,并清掉构建产物。
生成后记得:

1. 写 `apps/<AppName>/README.md`(做什么、目标设备、构建/安装/验收、已知限制)
2. 改 `app/src/main/res/values/strings.xml` 里的 `app_name`
3. 确认 `applicationId` 与其它工程不重复
4. 确认没在工程里写版本号字面量(版本唯一来源是仓库根的 `version.properties`)
5. 按第 7 节验证一遍完整闭环(构建 → 安装 → 验收)

完整约定见 [docs/06-app-conventions.md](docs/06-app-conventions.md)。

### 加一篇文档

放 `docs/NN-kebab-case.md`,并在 [docs/README.md](docs/README.md) 的表格里加一行。

写「怎么验证的」而不只是结论 —— 环境会变,以后需要复现。

---

## 9. 开工 / 收尾

### 开工

```bash
git pull
bash tools/devices.sh        # 两台都要是 device 才能继续
```

Pico 不在线通常是**休眠**了(它重启后无线调试会失效):让它亮一下,
或者 `bash tools/pico-usb.sh`(需要 USB 线插在 Windows 主机上)。

### 收尾

```bash
bash tools/verify-all.sh     # 环境 → 构建 → 双设备,确认工具链没坏
```

然后:

1. 跑一遍第 7 节的泄漏自检(都应该零输出)
2. **把这次踩到的坑补进文档** —— 新坑进 [docs/05](docs/05-gotchas.md),
   agent 必须知道的约束进本文件。判断标准:**不知道会不会做错事 → 这里;
   知道更省事 → docs/**。
   这些经验一旦写下来就永久生效,不写就每次重新踩。
3. 设备侧别留临时文件(推到 `/sdcard` 的 APK、下载目录里的测试文件)

**不要顺手升级 Kotlin / AGP / Compose**。现在这套组合是在真机上验证过的,
升级会连带 Compose 编译器、Compose BOM、tv-material 一起动,升完必须重新
在设备上验证。真要升单独开一次,别夹在功能开发中间。

### 受管沙箱里 git 写不进远端跟踪引用 —— 别误判成仓库坏了

某些托管环境(如 WorkBuddy 的沙箱)对**工作区路径**的写入有拦截:`git` 写
`refs/remotes/<remote>/<branch>` 会**静默失败** —— rc=0、不留文件,还会把已存在的
`<remote>` 目录一起删掉。症状是 `git fetch` 之后 `git status -sb` 一直显示 `[gone]`。

判据(2026-09-18 实测):`refs/heads/*`、`refs/tags/*`、`refs/remotes/<一级名>` 全都正常;
同一个操作在 C 盘、或在工作区**之外**都能成功 → **是环境拦截,不是仓库 / 磁盘问题,
用户自己的终端不受影响**。

> ⚠️ **不要为了「修」它去跑 `git pull --rebase` / `git reset`。** `[gone]` 只表示本地
> 没有那个远端跟踪引用,**不代表本地落后**;破坏性命令才是真会丢东西的。

需要那个引用时手写即可(git 立刻认):

```bash
printf '%s\n' "$(git rev-parse HEAD)" > .git/refs/remotes/origin/main
```

一般规律:命令**报成功但结果不存在** → 先怀疑环境,用对照实验(换盘符 / 换目录 /
换进程类型 / 手写一份)定位,确认是环境问题就别改仓库。

## 10. 环境速查

| 组件 | 版本 / 路径 |
|---|---|
| JDK | Temurin 17 —— Linux/CI: `/opt/jdk/jdk-17.0.20.1+1`;Windows 本机: `C:\Program Files\Eclipse Adoptium\jdk-17*`(`%JAVA_HOME%` 由 MSI 写入系统环境) |
| Android SDK | Linux/CI: `/opt/android-sdk`;Windows 本机: `%LOCALAPPDATA%\Android\Sdk`(platform-34 / build-tools 34.0.0,基座自动探测,装法见 docs/01) |
| CI runner | `ubuntu-24.04` —— **显式 pin,不用 `ubuntu-latest`**(理由与升 26.04 的判据见 `.github/workflows/ci.yml` 注释) |
| Gradle | 8.11.1(wrapper 在工程里,不用全局装) |
| 构建组合 | AGP 8.7.3 + Kotlin 2.0.21 + Compose BOM 2024.12.01 + tv-material 1.0.0 |
| Python | 3.x(脚本用它解析 XML,平台自带) |

设备地址、SDK 路径等本机相关配置全部走 `tools/device.env`。
