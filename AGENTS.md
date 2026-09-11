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

---

## 1. 仓库结构

```
docs/            知识沉淀(踩坑、结论、绕行方案)
apps/<Name>/     可运行的 Android 工程
tools/           设备连接 / 安装 / 引导脚本
  _common.sh             共用的配置载入逻辑(所有脚本 source 它)
  device.env.example     设备地址模板 → 复制成 device.env(不入库)
```

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

### 什么时候截图也不行

**Pico 上截屏被系统禁止**。PICO 给每个应用建独立虚拟 display 且全部带 `FLAG_SECURE`:

```bash
adb -s "$PICO_ADDR" exec-out screencap -p > shot.png
# → 36 KB 的纯白图,没用。scrcpy 同理
```

Pico 上只能靠日志打点或它自带的投屏。详见 [docs/04-pico4-notes.md](docs/04-pico4-notes.md)。

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

### ⚠️ 电视会自动进屏保

屏保期间 `am start` **返回成功但什么都不会发生**,日志里连 `ActivityTaskManager` 记录都没有。

```bash
adb -s "$TV_ADDR" shell input keyevent KEYCODE_WAKEUP
adb -s "$TV_ADDR" shell input keyevent KEYCODE_HOME
# 确认:前台不是 com.tcl.appreciate.art/...DreamActivity
```

排查任何「`am start` 没反应」的问题,先查屏保。

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

### 加一个新示例工程

```
apps/NewApp/
├── README.md            说明它验证什么、怎么构建、怎么装
├── settings.gradle.kts
├── build.gradle.kts
├── gradlew / gradle/wrapper/
└── app/
```

要让一个 APK 同时支持 TV 和其他设备,注意 [apps/DualDemo/README.md](apps/DualDemo/README.md) 里那三个关键点
(leanback 不设 required、注册两个 launcher category、banner 必须 320×180)。

### 加一篇文档

放 `docs/NN-kebab-case.md`,并在 [docs/README.md](docs/README.md) 的表格里加一行。

写「怎么验证的」而不只是结论 —— 环境会变,以后需要复现。

---

## 9. 环境速查

| 组件 | 版本 / 路径 |
|---|---|
| JDK | Temurin 17,`/opt/jdk/jdk-17.0.20.1+1` |
| Android SDK | `/opt/android-sdk`(platform-34 / build-tools 34.0.0) |
| Gradle | 8.11.1(wrapper 在工程里,不用全局装) |
| 构建组合 | AGP 8.7.3 + Kotlin 2.0.21 + Compose BOM 2024.12.01 + tv-material 1.0.0 |
| Python | 3.x(脚本用它解析 XML,平台自带) |

设备地址、SDK 路径等本机相关配置全部走 `tools/device.env`。
