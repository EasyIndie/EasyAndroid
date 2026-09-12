# 04 · Pico 4 开发约束

实测机型:Pico 4(`A8110` / Phoenix),PICO OS 5.13.7,Android 10 / API 29。

好消息:普通 `adb install` 就能装(实测 **3 秒**),不像 [TCL 电视](03-tcl-tv-sideload.md)
那样有固件封锁。
坏消息:`screencap` 和 `uiautomator` 都拿不到画面和 UI 树,而且还有两条隐藏的坑:
**不戴头显时 ~10 秒自动休眠**(应用会被 `onPause`)、**输入必须定向注入到应用自己的
虚拟 display**(裸 `input keyevent` 到不了你)。三条里任意一条都能让现象变成
「命令返回成功,但什么都没发生」。

能跑通的闭环长这样(下面每一句都实测过):

```bash
bash tools/pico-panel.sh com.example.dualdemo awake                     # 拉起 + 解除自动休眠
bash tools/ui-dump.sh    com.example.dualdemo                           # 1 秒拿到真实渲染的 PNG
bash tools/pico-panel.sh com.example.dualdemo key KEYCODE_DPAD_DOWN     # 定向按键
bash tools/ui-dump.sh    com.example.dualdemo /tmp/b.png                # 对比 PNG 确认焦点真的动了
```

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
| **应用自截图** ✅ 唯一可靠 | 让应用画自己的 View 层级成 PNG,再用广播触发 + `adb pull`。**不受 `FLAG_SECURE` 影响**,见 [07-debug-ui-capture.md](07-debug-ui-capture.md) |
| PICO 自带投屏 | 设备上有 `com.pvr.picocast`(接收端)和 `com.picovr.picostreamassistant`(PC 串流助手,把 PC 画面投到头显)。**都不是「把头显画面弄出来」的通道** |
| 日志打点 | 在应用里自己把关键状态打进 logcat,纯文本验收 |

> 对比:TCL 电视的 `screencap` **完全正常**,所以电视上截图可直接交给视觉模型。
> Pico 上必须先让应用**自己**截自己 —— 多一步,但拿到的是同一份东西。
> 跨设备做同一套 UI 时要注意这个不对称(`tools/ui-dump.sh` 两边都能用)。

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

Pico 上 dump 出来的内容其实来自 **默认 display**(`com.pvr.vrshell`),跟你的应用无关:

```
$ adb -s $PICO_ADDR shell uiautomator dump /sdcard/u.xml; wc -c /sdcard/u.xml
UI hierchary dumped to: /sdcard/u.xml
1799 /sdcard/u.xml          # 只有 1 个节点: package="com.pvr.vrshell"
```

`uiautomator dump` **没有**指定 display 的参数(`--help` 都不认,直接当成文件名再 dump 一次),
`UiAutomation` 也只连默认 display。所以 Pico 上读 UI 树这条路是死的 —— 用
[应用自截图](07-debug-ui-capture.md) 代替。

---

## 输入:必须定向到应用自己的虚拟 display

在电视上 `adb shell input keyevent KEYCODE_DPAD_DOWN` 就完事了,**在 Pico 上完全没用**。

### 原因:`input` 默认打到 display 0,而你的应用在别的 display 上

Pico 给**每个应用**建一个独立虚拟 display:

```
$ adb -s $PICO_ADDR shell dumpsys display | grep NS_APP
DisplayDeviceInfo{"NS_APP[com.example.dualdemo]": uniqueId="virtual:com.picovr.systemext,1000,NS_APP[com.example.dualdemo],0",
    1602 x 902, density 200, touch VIRTUAL, type VIRTUAL, state ON,
    owner com.picovr.systemext (uid 1000), FLAG_SECURE, FLAG_PRIVATE,
    FLAG_NEVER_BLANK, FLAG_OWN_CONTENT_ONLY}
```

而 `input` 的行为是:

```
$ adb shell input
Usage: input [<source>] [-d DISPLAY_ID] <command> [<arg>...]
-d: specify the display ID.
      (Default: -1 for key event, 0 for motion event if not specified.)
```

默认 display 0 是 `com.pvr.vrshell`。所以裸按键全都喂给了 Pico 的系统外壳,**你的应用一个字节都收不到**。
而且它**不报错** —— 除非你去翻 WindowManager 的日志:

```
W WindowManager: Dropping key targeting non-focused display #24 keyCode=KEYCODE_DPAD_DOWN
```

看到 `Dropping key targeting non-focused display #N`,就说明 display id 写错了或者是过期的。

### 关键:displayId 每次启动应用都会变

实测同一个包在一轮会话里依次拿到过 **24 / 36 / 38 / 40 / 42 / 44 / 46 / 50** ——
`am force-stop` 再起来就换一个号。**不能缓存复用**,必须每次现取。

另外被杀掉的进程会留下**幽灵 display**:老的 `NS_APP[同包名]` 条目仍在列表里,
但它的 `DisplayDeviceInfo` 是 `state OFF`、窗口 `visible=false`。按包名 grep 会同时命中它和活的那个。

取 displayId(两条等价,取最后一条 = 最新建的):

```bash
# 推荐:直接读 mViewports
adb shell dumpsys display \
  | grep -oE "displayId=[0-9]+, uniqueId='virtual:[^']*NS_APP\[com.example.dualdemo\]," \
  | tail -1

# 也可以:
adb shell dumpsys input | grep 'NS_APP\[com.example.dualdemo\]'
#   Viewport VIRTUAL: displayId=46, uniqueId=virtual:...,NS_APP[com.example.dualdemo],0, ...
```

### 能用 / 不能用

```bash
D=46   # 上一步查出来的

# ✗ 给了 -d,但 display id 是过期的 → 被静默丢弃
adb shell input -d 24 keyevent KEYCODE_DPAD_DOWN

# ✗ 参数顺序错了 —— `input [<source>] [-d ID] <command>`,
#    所以 `-d` 必须在子命令之前、source 之后。这样写会报 Unknown command: dpad
adb shell input -d 46 dpad keyevent KEYCODE_DPAD_DOWN

# ✓ 按键(显式指定 display)
adb shell input -d $D keyevent KEYCODE_DPAD_DOWN

# ✓ 触摸也通。swipe 能让 Compose 的 LazyColumn 真的滚起来
adb shell input -d $D tap   800 300
adb shell input -d $D swipe 800 700 800 200 300
```

> `input -d <id> tap/swipe` 默认 source 是 `touchscreen`,面板的
> `DisplayDeviceInfo` 里 `touch VIRTUAL`,两边对得上,所以触摸注入有效。

### 怎么确认真的送达了

**不要靠感觉**(「命令没报错」什么都不能说明)。用自截图前后对比:

```bash
bash tools/ui-dump.sh com.example.dualdemo "$PICO_ADDR" /tmp/a.png
bash tools/pico-panel.sh com.example.dualdemo key KEYCODE_DPAD_DOWN KEYCODE_DPAD_DOWN
bash tools/ui-dump.sh com.example.dualdemo "$PICO_ADDR" /tmp/b.png
md5sum /tmp/a.png /tmp/b.png     # 不一样 = 送达了
```

本次实测:`DPAD_DOWN ×3` 后两张 PNG 的差异像素占比 **1.8% ~ 3.9%**,
差异区域的 bounding box 正好落在卡片行区间(如 `y[149..412]`),与「焦点下移 3 行」完全吻合。

`tools/pico-panel.sh` 把上面这套封装好了,直接用:

```bash
bash tools/pico-panel.sh <pkg> awake
bash tools/pico-panel.sh <pkg> key   KEYCODE_DPAD_DOWN
bash tools/pico-panel.sh <pkg> tap   800 300
bash tools/pico-panel.sh <pkg> swipe 800 700 800 200 300
```

---

## 不戴头显时会在 10 秒后自动休眠

这条是最容易误判的坑:它会让 `tools/ui-dump.sh` 报
**「没有处于 resumed 状态的 Activity —— 应用在前台吗?」**,
看起来像应用崩了或者没起来,其实是头显睡了。

### 现象

```bash
$ adb -s $PICO_ADDR shell input keyevent KEYCODE_WAKEUP
$ adb -s $PICO_ADDR shell dumpsys power | grep mWakefulness
    mWakefulness=Awake            # 醒着的
# …… 等 10 秒 ……
    mWakefulness=Asleep
$ adb -s $PICO_ADDR shell dumpsys display | grep -m1 内置屏幕 | grep -oE 'state [A-Z]+'
    state OFF
```

「睡」之后连面板的 `DisplayDeviceInfo` 也变成 `state OFF`,应用被 `onPause` 到后台。
戴在头上当然不会发生 —— 触发条件是**接近传感器判定没戴**(`stk_stk3x1x_prox`,
`com.pvr.sensormanager.ProximitySensorManager`)。

### 靠电源设置顶不住

实测这些都**无效**(设备明明接着电源、`mStayOn=true`、`stay_on_while_plugged_in=7`,
照样 10 秒睡):

```bash
adb shell svc power stayon true
adb shell settings put global stay_on_while_plugged_in 7
adb shell setprop persist.pvr.sleep_by_static 0     # 无效,已排除
```

### 有效解法

```bash
adb shell setprop pvr.factorytest.never.sleep 1
```

实测置 1 之后 60 秒以上持续 `Awake`、面板一直 `state ON`、应用一直 resumed。

> 好处:这个属性**没有 `persist.` 前缀**,重启就恢复成 `0`,不会留下后遗症,
> 也不需要记得改回去。
> `tools/pico-panel.sh <pkg> awake` 会顺手把它设上。

排查顺序建议:任何「Pico 上 am start / 按键没反应」,先 `input keyevent KEYCODE_WAKEUP`
再设这个属性,最后才去怀疑代码。

### 对迭代节奏的影响

休眠不会让安装变慢(装还是 3 秒),但会让**上一条命令截图成功、下一条命令截图失败**,
从而浪费一整个来回。所以要么全程保持唤醒,要么把「唤醒 → 启动 → 截图」压进 10 秒内。

---

## 2D 面板的几何

别按头显的物理分辨率去设计布局 —— 普通 Android 应用在 Pico 上跑在**面板**里,
它看到的是一个独立的小 display:

| display | 尺寸 | density | 相当于 |
|---|---|---|---|
| 内置屏幕(双眼合成) | 4320 x 2160 | 560 | 头显本体,每眼 2160 x 2160;90 / 72 Hz |
| `NS_APP[com.example.dualdemo]` | **1602 x 902** | 200 | 我们的应用,**801 x 451 dp** |
| `NS_APP[com.pvr.home]` | 2102 x 902 | 200 | 系统桌面(21:9) |
| `NS_APP[com.picovr.settings]` | 1127 x 752 | 200 | 设置 |
| `NS_CAPTION_BAR_[双端演示]` | 413 x 250 | 200 | 面板上方的标题条(自动建,**每个应用一个**) |

几点结论:

- **面板尺寸由 Pico 按应用自己声明的方向/比例算出来**,不是你能直接指定的。
  我们的 `MainActivity` 声明了 `android:screenOrientation="landscape"`,拿到 16:9 的 1602x902。
- 应用看到的 `displayMetrics` 就是面板尺寸(1602x902 @200dpi),**不是** 4320x2160。
- 一个显示细节:`decorView` 比 display 小 2px(window frame 是 `[1,1][1601,901]`),
  所以自截图拿到的是 **1600x900**,而不是 1602x902。
- 面板尺寸用户可以在系统设置里缩放(`pvr.app.data.2d_app_zoom_tips_enable`),
  所以**不要**把布局写死成某个像素宽。

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

- `android.hardware.touchscreen` **有**(和电视不同,电视是纯遥控),
  而且支持 `multitouch.distinct` / `jazzhand` —— 这也是 `-d <id> tap/swipe` 能生效的前提
- Vulkan 1.1(`reqGlEsVersion=0x30002` = OpenGL ES 3.2)
- 有 `com.pico.xr.openxr_runtime`(Android 10,minSdk 29)
- 有 `uhid` 组权限(shell 身份里包含 `3011(uhid)`)
- **没有** `android.hardware.vr.headtracking` 这个 feature
  (`pm list features | grep -i vr` 零输出)。所以用 `PackageManager.hasSystemFeature`
  去探测「我是不是在 VR 头显上」**不可行** —— 得改用 `Build.MANUFACTURER`/`ro.pvr.*`

系统里对外可见的原生 XR 库(`/system/lib64`,应用可以直接 `System.loadLibrary`):

```
libopenxr_api.so            libopenxr_forwardloader.so
libPxr_PlatformSDK3.so      libPxr_PlatformSDK4.so
libPvr_UnitySDKExt14.so     libPvr_UESDKExt5.so
libeyetrackingclient.pxr.so libmrsystemservice_client.pxr.so
libhmdserviceclient.pxr.so  libcontrollerjni.pxr.so
libCVControllerClient.pxr.so libSlamTools.pxr.so
```

配套的系统包:`com.pico.xr.openxr_runtime`(runtime)、`com.pico.mrservice`(MR/透视)、
`com.pvr.scenemanager`(场景理解)、`com.pvr.roomcapture`、`com.pvr.swift`(体感追踪器)、
`com.picoxr.xrshell`、`com.pvr.vrshell`、`com.picovr.systemext`(管所有面板的那个)。

### 设备侧其他可用能力(shell 视角)

| 能力 | 状态 |
|---|---|
| `adb root` | ✗ `adbd cannot run as root in production builds`(虽然 `persist.pvr.adb.root=1`) |
| `adb reverse` | ✓ 实测 `reverse tcp:18080 tcp:18080` 成功(可给应用回连本机开发服务器) |
| `run-as <pkg>` | ✓(debuggable 应用,自截图取图就靠它) |
| 写 `/sdcard` | ✓ |
| `pm install-multiple` / `create-session` | ✓ 子命令存在(普通单 APK 用不上) |
| 投屏 | `com.pvr.picocast` 是 **sink**(接收投屏),`com.picovr.picostreamassistant` 是 PC 串流助手。想「看头显画面」用应用自截图,别折腾投屏 |
| 温度 | 空闲时 CPU 69~77 ℃ / GPU 63 ℃ / 电池 29 ℃,`Thermal Status: 0` |
| 内存 / 存储 | 8 GB RAM,225 GB 存储(可用 211 GB) |

### 想在 Pico 上做真 VR

那是另一条技术栈:Unity / Unreal / 原生 OpenXR + PICO SDK,不是「同一套 Android 工具链」能覆盖的。
如果只是把普通 Android 应用装到 Pico 上跑 2D 面板,那本文这套就够了。

---

## 验证记录

### 完整的 Pico 迭代闭环(实测耗时)

| 步骤 | 命令 | 耗时 |
|---|---|---|
| 安装 | `adb -s $PICO_ADDR install -r app-debug.apk` | **3 s** |
| 启动 | `am start -W -n com.example.dualdemo/.MainActivity` | **0.9 s** |
| 自截图 | `bash tools/ui-dump.sh com.example.dualdemo` | **1 s** |
| 定向按键 + 再截图 | `tools/pico-panel.sh ... key` + `ui-dump.sh` | **2 s** |

对比 TCL 电视一次安装 60~80 秒(见 [03](03-tcl-tv-sideload.md#安装耗时为什么快不起来))——
**高频迭代用 Pico,电视只在里程碑做验收**。这条结论经过本次重测依然成立。

```
install   → Success (Performing Streamed Install)
launch    → Status: ok
面板      → displayId=46, state ON, 1602x902 @200dpi
自截图    → 1600x900, 102555 bytes
按键注入  → 无 "Dropping key targeting" ;前后 PNG 有 1.8%~3.9% 像素变化
logcat    → 无 FATAL / AndroidRuntime Exception
```

```bash
adb -s $PICO_ADDR install -r app-debug.apk
bash tools/pico-panel.sh com.example.dualdemo awake
bash tools/ui-dump.sh com.example.dualdemo
adb -s $PICO_ADDR logcat -d -t 300 | grep -iE 'FATAL|AndroidRuntime'
```

### 休眠复现实验

```bash
# never.sleep=1:静置 60 秒
+10s..+60s  mWakefulness=Awake   面板 state ON   应用 resumed

# never.sleep=0:静置 25 秒
            mWakefulness=Asleep  面板 state OFF  应用 paused(自截图报「没有处于 resumed 状态的 Activity」)
```

### 输入送达复现实验

```bash
# 关闭 never.sleep 后静置到睡着,再注入(故意用错 display) → 被丢弃
W WindowManager: Dropping key targeting non-focused display #24 keyCode=KEYCODE_DPAD_DOWN

# 醒来 + 用正确的 display 注入 → 无该告警,且画面变化
# 盲按(不给 -d) → 既不报错也不生效,面板照常 resumed(它打给了 com.pvr.vrshell)
```
