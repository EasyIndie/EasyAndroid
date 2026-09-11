# tools

设备连接 / 安装 / 引导脚本。按 WSL2 + Linux 版 adb 编写。

路径都用 `$(dirname "$0")` 解析,可以从任意目录调用。

## 脚本

### `devices.sh` — 连接并列出设备

```bash
bash tools/devices.sh
```

对目录里的两台设备(电视 + Pico)逐个 `adb connect`,然后打印状态表。
日常开工第一条命令。

### `device-status.sh` — 设备状态一次性报告

```bash
bash tools/device-status.sh                          # 默认 TV
bash tools/device-status.sh "$PICO_ADDR"             # 指定设备
bash tools/device-status.sh "$TV_ADDR" com.example.dualdemo   # 顺带查某个包
```

一次输出:型号 / 系统 / ABI → 目标包是否安装及版本 → 当前前台 → 最近崩溃 → 当前界面全部文案。

全部是纯文本,**不消耗多模态 token**。写自动化或排查问题时先跑这个。

### `tv-install.sh` — 装到 TCL 电视

```bash
bash tools/tv-install.sh apps/DualDemo/app/build/outputs/apk/debug/app-debug.apk
LABEL=双端演示 TV=192.0.2.11:5555 bash tools/tv-install.sh <apk>   # 手动指定
```

**为什么需要它**:TCL 在固件里封掉了 `adb install`(`INSTALL_FAILED_VERIFICATION_FAILURE`),
唯一可用通道是 TGuard 的图形化安装器。脚本用 `adb input keyevent` + `uiautomator dump`
模拟走完那条路径,不消耗多模态 token。

完整背景见 [../docs/03-tcl-tv-sideload.md](../docs/03-tcl-tv-sideload.md)。

变量:

| 变量 | 默认 | 说明 |
|---|---|---|
| `TV` | `192.0.2.11:5555` | 设备 serial |
| `LABEL` | 从 APK 里读 `application-label` | 在安装列表里匹配的标签 |

### `pico-usb.sh` — Pico 重启后恢复无线调试

```bash
bash tools/pico-usb.sh        # 需要 USB 线插在 Windows 主机上
```

Pico 的 `persist.adb.tcp.port` 写不进去(需 root),所以**每次重启后**都要重新
`adb tcpip 5555` 一次。这个脚本做这件事,约 10 秒。

日常规避:**别关机,用待机**,adbd 不会重启。

见 [../docs/02-adb-multi-device.md](../docs/02-adb-multi-device.md#pico-的规避方式)。

### `fetch-platform-tools.sh` — 拉 Windows 版 platform-tools

```bash
bash tools/fetch-platform-tools.sh
```

只在 `pico-usb.sh` 需要。产物落在 `tools/platform-tools/`(**已 gitignore**,不入库)。

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
| `ANDROID_SDK_DIR` | SDK 位置,默认 `/opt/android-sdk` |
| `WINADB` | Windows 版 adb 路径 |
| `WINADB_PORT` | Windows 侧 adb server 端口,默认 `15037` |

统一由 [`_common.sh`](_common.sh) 载入,所以换设备不用改代码。

### 其他

| | 要求 |
|---|---|
| Linux 版 adb | `/opt/android-sdk/platform-tools`,并在 PATH 里 |
| JDK 17 | `tv-install.sh` 用 `aapt2` 读 APK 信息,需要 `JAVA_HOME` |
| aapt2 | `/opt/android-sdk/build-tools/<version>` |
| Python 3 | 解析 `uiautomator` 的 XML |

如果不是装在默认路径,改脚本顶部的 PATH 或 `WINADB` 变量。

---

## 为什么有 Windows 版 adb

WSL2 **没有 USB 总线**(`/dev/bus/usb` 不存在,也没有 `usbip` 内核模块),
插在 Windows 上的设备 WSL 看不见。

所以「USB 引导 Pico」这一步必须由 **Windows 侧** 的 adb 完成。
Windows 那份固定跑在 **15037** 端口 —— 因为 `.wslconfig` 是 `networkingMode=mirrored`,
两边共享 localhost,抢同一个 5037 会起不来。

详见 [../docs/02-adb-multi-device.md](../docs/02-adb-multi-device.md#-核心坑wsl2-mirrored-网络下只能有一个-adb-server)。
