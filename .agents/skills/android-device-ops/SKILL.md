---
name: android-device-ops
description: 在真实 Android 设备(TCL Android TV / Pico 4)上构建、安装、验收、迭代应用。当需要把 APK 装到真机、检查应用是否运行正常、排查安装失败或界面不渲染、用遥控按键驱动 TV 界面时使用。
---

# 真机操作循环

适用于本仓库的任何 `apps/*` 工程。核心约束:**TCL 电视禁用了 `adb install`**,
必须走专用脚本;验收**优先用文本,不要截图**(Pico 上截屏还是无效的)。

## 0. 先看仓库根目录的 AGENTS.md

那里有硬性规则(哪些文件不能提交、哪些命令不能用)。本 skill 只讲操作流程。

## 1. 设备连通性

```bash
bash tools/devices.sh
```

两台都要是 `device`。若是 `unauthorized` → 设备上需要人工点授权弹窗,**不要尝试绕过**。

设备地址来自 `tools/device.env`(不入库)。第一次用:

```bash
cp tools/device.env.example tools/device.env   # 然后填真实地址
```

## 2. 构建

```bash
cd apps/<Name>
./gradlew assembleDebug --no-daemon --console=plain --max-workers=2
```

`--max-workers=2` 不是可选项 —— 并发拉依赖会被对端断连,报 TLS 握手失败。

## 3. 安装

```bash
# Android TV —— 只能走这个
bash tools/tv-install.sh apps/<Name>/app/build/outputs/apk/debug/app-debug.apk

# 其他设备
adb -s "$PICO_ADDR" install -r apps/<Name>/app/build/outputs/apk/debug/app-debug.apk
```

**不要对 TCL 电视用 `adb install`,也不要试图用 `settings put global` 关校验。**
已经排除过的方案清单见 `docs/03-tcl-tv-sideload.md`,改 `tv-install.sh` 前必读。

### 识别某台设备该怎么装

```bash
adb -s "$DEV" shell dumpsys package <pkg> | grep installerPackageName
```

| 值 | 含义 |
|---|---|
| `com.android.packageinstaller` | 图形化通道(TCL 上**可用**) |
| `com.tcl.guard` / `com.tcl.appmarket2` | 厂商商店/TGuard |
| 空 / `com.android.shell` | `adb install`(Pico 走这条,3 秒) |

## 4. 验收

```bash
bash tools/device-status.sh "$TV_ADDR" com.example.dualdemo
```

一次拿到:型号/API/ABI、包是否安装及版本、当前前台、最近崩溃、当前界面全部文案。

想单独做某一步:

```bash
# 启动
adb -s "$DEV" shell am start -W -n <pkg>/.MainActivity

# ⚠️ 如果 am start "成功但没反应",先怀疑屏保
adb -s "$DEV" shell input keyevent KEYCODE_WAKEUP
adb -s "$DEV" shell input keyevent KEYCODE_HOME
adb -s "$DEV" shell dumpsys activity activities | grep -m1 mResumedActivity
#   前台是 ...DreamActivity 就是在屏保

# 兵底:实测撞到过一种屏保把【所有按键】全吞掉的状态(连发 15 秒都没用)。
# 这时只能发指针事件 —— TCL 遥控是 IR 触控,屏保只认指针。
adb -s "$DEV" shell input tap 960 540      # 屏幕中心

# 看崩溃
adb -s "$DEV" logcat -d -t 300 | grep -iE 'FATAL|AndroidRuntime'

# 抓实时日志
adb -s "$DEV" logcat -v time | grep -iE '<你的tag>|FATAL'
```

**不要用截图验收。** 用 `uiautomator dump` 拿 UI 树 —— 信息量更大且零多模态成本。
`device-status.sh` 最后一段就是干这个的。

⚠️ **电视上更要命的是「截图变了」根本不是证据**:TCL 桌面/设置里的时钟、天气、动效一直在跑,
停在设置页 **4 秒不发任何输入**,两张 `screencap` 的 md5 就不同了。
判断「输入生效没」要用 **UI 树的全量文案集合**(所有 `text`/`content-desc` 拼起来取 md5),
不是截图,也不是只看前几条文案:

```
input tap 点「声音」       → 文案集合不变(❌ 没生效),但 PNG md5 变了
DPAD_DOWN + CENTER 选它   → 文案集合变了(✅ 生效)
```

(`screencap` 在电视上还要 3 秒,比 `uiautomator dump` 的 2.1 秒更慢。)

Pico 例外:`screencap` 被 `FLAG_SECURE` 挡住(纯白图),`uiautomator` 也读不到 VR 面板
(dump 出来的 1799 字节其实是 `com.pvr.vrshell` 的,跟你的应用无关)。改用**应用自截图**:

```bash
bash tools/pico-panel.sh <pkg> awake    # 不戴头显 ~10 秒就休眠,先把应用拉起并顶住
bash tools/ui-dump.sh <pkg>             # 1 秒拿到真实渲染的 PNG
```

⚠️ **自截图前提是应用处于 resumed**。如果报「没有处于 resumed 状态的 Activity」,
九成是头显睡了,不是应用出了问题 —— 先 `awake`。
详见 `docs/04-pico4-notes.md` / `docs/07-debug-ui-capture.md`。

## 5. 驱动 TV 界面

TV 没有触摸,`input tap` 在很多 TCL 界面里**不生效**。用按键:

> 实测得很彻底:TCL 桌面磁贴「我的应用」「设置」、设置左侧导航、设置里的
> 「高级设置」按钮 —— 四处 `input tap` 均无反应,同位置 `DPAD + CENTER` 均生效。
> 注意「高级设置」在 UI 树里标了 `clickable="true"` 却照样不行,所以
> **不能靠 a11y 的 `clickable` 判断能不能 tap**。一律用按键。

```bash
adb -s "$DEV" shell input keyevent KEYCODE_DPAD_DOWN
adb -s "$DEV" shell input keyevent KEYCODE_DPAD_CENTER
adb -s "$DEV" shell input keyevent KEYCODE_BACK
```

导航策略:**不要靠固定次数的盲按**。每按一步就 `uiautomator dump` 一次,看 `focused="true"`
落在哪个节点上,再决定下一步。参考 `tools/tv-install.sh` 里 `focused_label()` 的写法 ——
它会取「bounds 落在 focused 节点内部的文本」作为当前项标签。

### Pico 上不是这套:必须定向注入

```bash
bash tools/pico-panel.sh <pkg> awake                          # 顺带拉起应用
bash tools/pico-panel.sh <pkg> key   KEYCODE_DPAD_DOWN
bash tools/pico-panel.sh <pkg> key   KEYCODE_DPAD_DOWN KEYCODE_DPAD_CENTER   # 一次多个
bash tools/pico-panel.sh <pkg> swipe 800 700 800 200 300      # 触摸注入有效
```

Pico 给**每个应用**建独立虚拟 display,裸 `input` 打到的是 display 0(`com.pvr.vrshell`),
**不报错、不生效**。而且那个 displayId **每次启动应用都变**(实测见过 24/36/38/40/42/44/46/50),
不能缓存。`pico-panel.sh` 每次现取,并在面板不是 `state ON` 时直接报错。

送达怎么验证(Pico 上读不了 UI 树,只能靠图):

```bash
bash tools/ui-dump.sh <pkg> "$PICO_ADDR" /tmp/a.png
bash tools/pico-panel.sh <pkg> key KEYCODE_DPAD_DOWN
bash tools/ui-dump.sh <pkg> "$PICO_ADDR" /tmp/b.png
md5sum /tmp/a.png /tmp/b.png     # 不一样 = 送达了
adb -s "$PICO_ADDR" logcat -d | grep 'Dropping key targeting non-focused display'
```

## 6. 写脚本时

**每条 `adb shell` 都要加 `</dev/null`**,否则它会吞掉脚本后续命令的输出:

```bash
A(){ timeout 30 adb -s "$DEV" shell "$@" </dev/null 2>&1; }
```

所有脚本都要 source 共用配置:

```bash
. "$(dirname "${BASH_SOURCE[0]}")/_common.sh"
```

改完做语法检查:

```bash
for f in tools/*.sh; do bash -n "$f" || echo "FAIL: $f"; done
```

## 7. 收尾

```bash
# 泄漏自检(都应零输出;git grep 只扫被跟踪文件,自然跳过 device.env)
git grep -nE '192\.168\.[0-9]+\.[0-9]+'
git grep -nE 'ghp_[A-Za-z0-9]{20,}|gho_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|x-access-token:[A-Za-z0-9]'
git ls-files | grep -E 'device\.env$|tools/platform-tools/'
```

如果这次踩到了新坑,**顺手补进 `docs/05-gotchas.md`**(症状 → 原因 → 解法),
并在 `docs/README.md` 索引里加行。
