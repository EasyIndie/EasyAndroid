# 知识库索引

按主题分文件。每条结论都标注了「怎么验证的」,方便以后环境变了能重新确认。

| 文档 | 主题 |
|---|---|
| [01-headless-android-build.md](01-headless-android-build.md) | 不装 Android Studio,纯命令行搭 Android 构建环境(WSL2 + JDK 17 + cmdline-tools + Gradle) |
| [02-adb-multi-device.md](02-adb-multi-device.md) | ADB 多设备管理:WSL2 mirrored 网络的端口冲突、网络 ADB 持久性差异、USB→TCP 引导 |
| [03-tcl-tv-sideload.md](03-tcl-tv-sideload.md) | TCL 电视固件级侧载封锁(`OverseasAppConfig`)的分析与绕行方案 |
| [04-pico4-notes.md](04-pico4-notes.md) | Pico 4 开发约束:`FLAG_SECURE` 截屏限制、ABI、虚拟 display 机制 |
| [05-gotchas.md](05-gotchas.md) | 踩坑速查:adb shell 吞 stdin、Gradle 并发拉依赖 TLS 失败、drvfs 目录缓存损坏… |

## 实测设备

所有结论基于以下两台设备,系统版本见 [02-adb-multi-device.md](02-adb-multi-device.md#设备规格对照):

| | TCL 电视 | Pico 4 |
|---|---|---|
| 地址 | `192.0.2.11:5555` | `192.0.2.29:5555` |
| 型号 | `tcl_mt5879_cn` | `A8110` / Phoenix |
| 系统 | Android 11 / API 30 | Android 10 / API 29 (PICO OS 5.13.7) |
| ABI | **仅 armeabi-v7a** | arm64-v8a + armeabi-v7a |

## 写法约定

- 命令默认在 WSL2 里执行
- `$TV` / `$TV_ADDR` = 电视 serial,`$PICO_ADDR` = 第二台设备
- 「✅ 已验证」= 真机跑通过;「⚠️ 推测」= 有依据但没实测

## 关于设备地址

文档里出现的 `192.0.2.x` 是 **RFC 5737 文档保留地址段**(TEST-NET-1),
**不是真实地址**,仅用于让示例命令保持可读、可直接复制。

真实地址放在 `tools/device.env`(已 gitignore),模板见 `tools/device.env.example`:

```bash
cp tools/device.env.example tools/device.env
# 然后填入你的设备地址
```

脚本都从 `tools/_common.sh` 载入这个配置,所以换设备不用改代码。
