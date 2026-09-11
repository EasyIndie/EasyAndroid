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
| 空 / `com.android.shell` | `adb install` |

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

# 看崩溃
adb -s "$DEV" logcat -d -t 300 | grep -iE 'FATAL|AndroidRuntime'

# 抓实时日志
adb -s "$DEV" logcat -v time | grep -iE '<你的tag>|FATAL'
```

**不要用截图验收。** 用 `uiautomator dump` 拿 UI 树 —— 信息量更大且零多模态成本。
`device-status.sh` 最后一段就是干这个的。

Pico 例外:`screencap` 被 `FLAG_SECURE` 挡住(纯白图),`uiautomator` 也读不到 VR 面板,
只能靠日志打点或它自带的投屏。详见 `docs/04-pico4-notes.md`。

## 5. 驱动 TV 界面

TV 没有触摸,`input tap` 在很多 TCL 界面里**不生效**。用按键:

```bash
adb -s "$DEV" shell input keyevent KEYCODE_DPAD_DOWN
adb -s "$DEV" shell input keyevent KEYCODE_DPAD_CENTER
adb -s "$DEV" shell input keyevent KEYCODE_BACK
```

导航策略:**不要靠固定次数的盲按**。每按一步就 `uiautomator dump` 一次,看 `focused="true"`
落在哪个节点上,再决定下一步。参考 `tools/tv-install.sh` 里 `focused_label()` 的写法 ——
它会取「bounds 落在 focused 节点内部的文本」作为当前项标签。

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
