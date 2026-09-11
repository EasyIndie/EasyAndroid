# 02 · ADB 多设备管理(WSL2 + 网络调试)

场景:两台 Android 设备(TCL 电视 / Pico 4)都走**无线 ADB**,adbd 跑在 WSL2 里,
需要时用 Windows 侧的 adb 做 USB 引导。

---

## 设备规格对照

| | **TCL 电视** | **Pico 4** |
|---|---|---|
| 地址 | `192.0.2.11:5555` | `192.0.2.29:5555` |
| 型号 / 代号 | `tcl_mt5879_cn` (product `tcl_mt5879_cn_db`) | `A8110`,代号 Phoenix |
| 系统 | Android **11** / API **30** | Android **10** / API **29** (PICO OS 5.13.7) |
| 固件构建 | `2026012200` (2026-01-22) | `smartcm.1761755159` |
| 安全补丁 | 2022-09-05 | 2021-04-05 |
| SoC | MediaTek `mt9952`,4 核 | Qualcomm `kona` (XR2),8 核 |
| **ABI** | **仅 armeabi-v7a(32 位)** ⚠️ | arm64-v8a + armeabi-v7a |
| 内存 | 3.8 GB | 8 GB |
| 存储 | 50 GB | 225 GB |
| 屏幕 | 1920×1080 @240dpi → 逻辑 **1280×720 dp** | 4320×2160 @560dpi |
| 刷新率 | 50 / 60 / 100 / 120 Hz | — |
| HDR | 类型 [1,2,3,4](HDR10 / HLG / Dolby Vision / HDR10+) | — |
| 平台标识 | `leanback_only` `television` `hdmi.cec` | `openxr_runtime` + Vulkan 1.1 |
| shell 身份 | uid=2000,无 root | uid=2000,无 root |

复现这些数据的命令:

```bash
A(){ adb -s "$1" shell "$2" </dev/null; }
A $TV 'getprop ro.build.version.release; getprop ro.build.version.sdk'
A $TV 'getprop ro.product.cpu.abilist'      # ← 选型前必查
A $TV 'wm size; wm density'
A $TV 'pm list features | grep -i leanback'
A $TV 'cat /proc/meminfo | head -1'
```

> **选型影响**:电视只有 32 位 ARM。依赖里如果有只发 `arm64-v8a` 的 native SDK
> (部分 AI 推理库、某些 DRM 库),这台电视直接不可用。`minSdk` 取 **29** 可以同时覆盖两台。

---

## ⚠️ 核心坑:WSL2 mirrored 网络下只能有一个 adb server

`.wslconfig`:

```ini
[wsl2]
networkingMode=mirrored
autoProxy=true
```

`mirrored` 模式下 **Windows 和 WSL 共享 localhost**。所以:

- WSL 的 adb server 监听 `127.0.0.1:5037`
- Windows 的 adb server 想监听同一个 `127.0.0.1:5037` → **冲突**

症状:从 WSL 里调 `adb.exe` 会看到

```
* daemon not running; starting now at tcp:5037
could not read ok from ADB server
* failed to start daemon
error: cannot connect to daemon
```

更迷惑的是它**有时又能跑** —— 因为那时 Windows adb.exe 其实连上了 WSL 侧已有的 server,
打印出的是同一份设备列表。等你 `kill-server` 后就再也起不来了。

### 解法:Windows 侧固定用非默认端口

```bash
WINADB="/mnt/e/EasyAndroid/tools/platform-tools/adb.exe"
"$WINADB" -P 15037 start-server
"$WINADB" -P 15037 devices -l
```

- **日常开发只用 WSL 的 adb**(网络连接两台设备完全够用)
- **Windows 的 adb 只负责 USB 操作**(给 Pico 开无线调试)

见 `tools/pico-usb.sh`。

---

## 网络 ADB 的持久性差异

这是最容易掉进去的坑:**两台设备行为完全不同**。

| | TCL 电视 | Pico 4 |
|---|---|---|
| `service.adb.tcp.port` | `5555`(运行时) | `5555`(运行时) |
| `persist.adb.tcp.port` | **`5555`** ✅ | 空 ❌ |
| 重启后仍能无线连? | **能** | **不能** |
| 能否自己写入 persist | — | 不能,`setprop` 返回 `rc=1`,需 root |

```bash
adb -s $DEV shell getprop persist.adb.tcp.port
```

- **电视**:`persist.adb.tcp.port=5555`,只要开发者选项里 ADB 开着,重启后自动监听,永久无线。
- **Pico**:只有运行时的 `service.adb.tcp.port`,重启就丢。

### Pico 的规避方式

**排查结论**:PICO OS 5.x(Android 10)**没有**「无线调试」开关。
Android 11 才引入的那套无线调试配对界面它没有 —— 这一点是反查
`/system/priv-app/PvrDevelopmentSettings/PvrDevelopmentSettings.apk` 确认的,
里面搜 `wireless` / `tcpip` / `无线` 零命中。

三个选择:

1. **别关机,用待机**(最省事)—— adbd 不重启,`tcpip 5555` 一直有效。日常开发根本碰不到。
2. **重启后跑一次 USB 引导**(约 10 秒):
   ```bash
   bash tools/pico-usb.sh     # 插上 USB,跑完拔掉
   ```
3. root —— 不建议。`ro.adb.secure=1`、`ro.debuggable=0`,解锁 bootloader 要走 PICO 官方流程。

---

## USB → TCP 引导的原理

```bash
"$WINADB" -P 15037 tcpip 5555    # 让 adbd 在 5555 上监听
"$WINADB" -P 15037 disconnect
adb connect 192.0.2.29:5555    # 之后走网络
```

**为什么必须用 Windows 侧的 adb**:WSL2 里没有 USB 总线
(`/dev/bus/usb` 不存在,也没有 `usbip` 内核模块),插在 Windows 上的设备 WSL 看不见。
要么用 `usbipd-win` 转发(重),要么就用 Windows 侧那份 adb 做这一次操作(轻)。

---

## 首次授权

网络 ADB 首次连接时设备上会弹「允许 USB 调试吗?」,需要人工点确认并勾选「一律允许」。

```bash
adb connect 192.0.2.11:5555
# failed to authenticate  → 设备上还没点确认
# unauthorized            → 同上
# device                  → 可以了
```

排查弹窗不出现:

- 先按 HOME 让设备回桌面,弹窗可能被切到后台
- 到「开发者选项」把 **USB 调试** 关掉再打开,同时保持 `adb connect` 在重试
- 部分 TCL 机型除了「USB 调试」还有一个 **「网络调试 / ADB over network」** 开关,**两个都要开**

主机密钥指纹(用于和弹窗里显示的比对):

```bash
python3 - <<'PY'
import base64,hashlib
raw=base64.b64decode(open('/root/.android/adbkey.pub','rb').read().split()[0])
print(base64.b64encode(hashlib.sha256(raw).digest()).decode().rstrip('='))
PY
```

---

## 一键连接脚本

```bash
bash tools/devices.sh
```

```
SERIAL                   STATE      MODEL
------------------------ ---------- --------------------
192.0.2.11:5555        device     tcl_mt5879_cn
192.0.2.29:5555        device     A8110
```

指定设备用 `adb -s <serial>`。

---

## 日常操作速查

```bash
# 装 / 起 / 看日志
adb -s $DEV install -r app.apk
adb -s $DEV shell am start -n com.example.app/.MainActivity
adb -s $DEV logcat -v time | grep -iE 'MyApp|FATAL'

# 当前前台是什么
adb -s $DEV shell dumpsys activity activities | grep -m1 mResumedActivity

# 遥控键控(TV 没有触摸,全靠 D-pad)
adb -s $TV shell input keyevent 19   # UP
adb -s $TV shell input keyevent 20   # DOWN
adb -s $TV shell input keyevent 21   # LEFT
adb -s $TV shell input keyevent 22   # RIGHT
adb -s $TV shell input keyevent 23   # CENTER
adb -s $TV shell input keyevent 4    # BACK

# UI 树(比截图便宜得多的验收手段)
adb -s $DEV shell uiautomator dump /sdcard/ui.xml
adb -s $DEV pull /sdcard/ui.xml /tmp/ui.xml
```

> TV 开发强烈建议**以 `uiautomator` 的 UI 树为主要验收手段**:98 个节点、文案、坐标、
> 焦点状态全都有文本。对 D-pad 焦点问题来说,这比看截图更精确,而且不吃多模态 token。
