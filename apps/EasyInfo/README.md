# EasyInfo · 设备信息

一个**零权限、不联网、不采集数据**的 Android 设备信息工具。同一个 APK 可跑在
Android TV、手机、平板和 Pico 4 上(清单里 `leanback` / `touchscreen` 都声明为非必需)。

它是本仓库的**第一个正式应用**,用途有两个:

1. 真实用户可用的设备信息工具(型号、系统、屏幕、CPU、内存、存储、TV/触摸/VR 能力)
2. 跑通 A(GitHub Release)/ B(Google Play)/ C(国内应用商店)三条上架链路

| | |
|---|---|
| 包名 | `com.easyindie.easyinfo` |
| 目标设备 | Android TV / 手机 / 平板 / Pico 4 |
| minSdk / targetSdk | 29 / 36(36 是 Google Play 2026 年的门槛) |
| 权限 | **无** |
| 版本号 | 仓库根 [`version.properties`](../../version.properties)(唯一来源) |
| 发布渠道 | 见 [`publish.properties`](publish.properties) |

## 构建

```bash
cd apps/EasyInfo
./gradlew assembleDebug          # → app/build/outputs/apk/debug/app-debug.apk
./gradlew testDebugUnitTest      # JVM 截图测试,出图到 app/build/outputs/roborazzi/
```

## 安装 / 验收

```bash
# TCL 电视(必须走专用脚本,原因见 docs/03)
bash ../../tools/tv-install.sh app/build/outputs/apk/debug/app-debug.apk

# Pico 4 / 其他设备
adb -s "$PICO_ADDR" install -r app/build/outputs/apk/debug/app-debug.apk

# 自截图(Pico 的 screencap 被 FLAG_SECURE 挡住)
bash ../../tools/ui-dump.sh com.easyindie.easyinfo --launch
```

## 上架

```bash
# 1. 构建产物(APK + AAB)并校验
bash tools/release-apk.sh <version> --format both

# 2. 按渠道做静态自检(不联网)
bash tools/store-preflight.sh <version> --target play
bash tools/store-preflight.sh <version> --target cn

# 3. 按 docs/11-publishing.md 的清单,在对应后台人工上传
```

完整流程、各商店的差异和资质要求见
[`docs/11-publishing.md`](../../docs/11-publishing.md)。

## 已知限制

- `compileSdk = 36` 在 **AGP 8.7.3** 上会打一条「建议升级 AGP」的 warning。
  实测构建/签名/出 AAB 都正常;彻底消除要升 AGP(会连带 Kotlin/Compose),
  属于单独一次、上真机重验的事。
- JVM 截图测试钉在 API 35(`app/src/test/resources/robolectric.properties`):
  Robolectric 4.17 跑 SDK 36 需要 JDK 21,仓库统一 JDK 17。真机验收才是
  targetSdk 36 的真实环境。
- 设备信息在不同厂商 ROM 上可能有取舍(Build 字段不保证准确),界面里已尽量
  用系统 API 的公开值,不读隐藏接口。
- 国内商店需要软件著作权证书、APP 备案、隐私政策 URL;本应用不联网,
  ICP 备案要求视商店而定。
