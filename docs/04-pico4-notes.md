# 04 · Pico 4 开发约束

实测机型:Pico 4(`A8110` / Phoenix),PICO OS 5.13.7,Android 10 / API 29。

好消息:普通 `adb install` 就能装,不像 [TCL 电视](03-tcl-tv-sideload.md) 那样有固件封锁。
坏消息:**adb 看不到画面**。

---

## ⚠️ 截屏被系统禁止(`FLAG_SECURE`)

这是 Pico 上做 UI 验收最大的障碍。

### 现象

```bash
adb -s 192.0.2.29:5555 exec-out screencap -p > shot.png
# → 36 KB 的纯白图(分辨率 4320×2160,但内容全空)
```

### 原因:PICO 给每个应用建独立虚拟 display,且全部带 `FLAG_SECURE`

```bash
adb shell dumpsys display | grep DisplayDeviceInfo
```

```
DisplayDeviceInfo{"内置屏幕": 4320 x 2160, density 560, state OFF, FLAG_SECURE, ...}

DisplayDeviceInfo{"GlobalUI": 4320 x 4320, ...
    FLAG_SECURE, FLAG_PRIVATE, FLAG_NEVER_BLANK, FLAG_OWN_CONTENT_ONLY}
DisplayDeviceInfo{"NS_APP[com.pvr.home]": 2102 x 902, ...
    FLAG_SECURE, ...}
DisplayDeviceInfo{"NS_APP[com.example.dualdemo]": 1602 x 902, ...}   ← 我们的应用
DisplayDeviceInfo{"NS_APP[com.picovr.settings]": 1127 x 752, ...}
DisplayDeviceInfo{"NS_CAPTION_BAR_[双端演示]": 413 x 250, ...}
```

从 `mViewports` 里能拿到每个应用的 display id:

```
displayId=17, uniqueId='virtual:com.picovr.systemext,1000,NS_APP[com.example.dualdemo],0',
  logicalFrame=Rect(0, 0 - 1602, 902)
```

**`FLAG_SECURE` 意味着该 surface 被排除在截图之外。**
`scrcpy` 用的也是同一条链路,所以同样拿不到画面。
按 display id 单独截也一样:

```bash
adb shell screencap -d 17 -p    # → 0 字节
```

### 替代方案

| 方案 | 说明 |
|---|---|
| **应用自截图** ✅ 推荐 | 让应用画自己的 View 层级成 PNG,再用广播触发 + `adb pull`。**不受 `FLAG_SECURE` 影响**,见 [07-debug-ui-capture.md](07-debug-ui-capture.md) |
| PICO 自带投屏 | 设备上有 `com.pvr.picocast` / `com.picovr.picostreamassistant`,投到浏览器/PC 看 |
| 日志打点 | 在应用里自己把关键状态打进 logcat,纯文本验收 |

> 对比:TCL 电视的 `screencap` **完全正常**。所以「截图给 AI 看」这条路在电视上可行,
> 在 Pico 上不可行。跨设备做同一套 UI 时要注意这个不对称。

---

## `uiautomator dump` 基本没用

```bash
adb shell uiautomator dump /sdcard/ui.xml
# → 1799 字节,只有 1 个带文案的节点
```

VR 面板里的 UI 树读不到。原因和截屏一致:应用被渲染到独立的虚拟 display 上,
`uiautomator` 拿不到那个 display 的窗口层级。

所以下面这套在电视上很好用的验收手法,**在 Pico 上失效**:

```bash
# TV 上有效,能读出 98 个节点 / 26 条文案
adb -s $TV shell uiautomator dump /sdcard/ui.xml && adb -s $TV pull /sdcard/ui.xml /tmp/
```

---

## 其他约束

### ABI

```
ro.product.cpu.abi      = arm64-v8a
ro.product.cpu.abilist = arm64-v8a,armeabi-v7a,armeabi
```

**两个都支持**。所以如果为了迁就只有 32 位的设备(如那台 TCL 电视)只打 `armeabi-v7a`,
Pico 上也能跑,只是浪费了 XR2 的 64 位能力。要兼顾就两个 ABI 都打。

### 无线 ADB 不持久

见 [02-adb-multi-device.md](02-adb-multi-device.md#网络-adb-的持久性差异)。

`persist.adb.tcp.port` 写不进去(shell 权限不足,需 root),
PICO OS 5.x 也没有 Android 11 的「无线调试」界面 → **重启后必须重新走一次 USB 引导**。

```bash
bash tools/pico-usb.sh
```

日常规避:**别关机,用待机**,adbd 不会重启。

### USB 引导需要 Windows 侧 adb

WSL2 没有 USB 总线,WSL 里的 adb 看不见插在 Windows 上的设备。
见 [02](02-adb-multi-device.md#usb--tcp-引导的原理)。

### 平台特性

```bash
adb shell pm list features | grep -iE "vulkan|openxr|touchscreen"
```

- `android.hardware.touchscreen` **有**(和电视不同,电视是纯遥控)
- Vulkan 1.1(`reqGlEsVersion=0x30002` = OpenGL ES 3.2)
- 有 `com.pico.xr.openxr_runtime`(OpenXR runtime)
- 有 `uhid` 组权限(shell 身份里包含 `3011(uhid)`)

### 想在 Pico 上做真 VR

那是另一条技术栈:Unity / Unreal / 原生 OpenXR + PICO SDK,不是「同一套 Android 工具链」能覆盖的。
如果只是把普通 Android 应用装到 Pico 上跑 2D 面板,那本文这套就够了。

---

## 验证记录

装 + 起 + 确认前台 + 无崩溃(这套在 Pico 上是能跑的):

```
install   → Success
launch    → Status: ok
mFocusedApp = ActivityRecord{... com.example.dualdemo/.MainActivity t188}
logcat    → 无 FATAL / AndroidRuntime Exception
```

```bash
adb -s $PICO install -r app-debug.apk
adb -s $PICO shell am start -W -n com.example.dualdemo/.MainActivity
adb -s $PICO shell dumpsys window displays | grep -m1 mFocusedApp
adb -s $PICO logcat -d -t 300 | grep -iE 'FATAL|AndroidRuntime'
```
