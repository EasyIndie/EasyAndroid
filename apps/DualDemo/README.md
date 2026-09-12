# DualDemo · 双端设备自检

> **定位:测试验证工程。** 它不属于任何业务应用,作用是验证工具链和 ADB 链路。
> **不要往这里加业务功能** —— 新应用请用 `bash tools/new-app.sh <AppName> <package.id>`
> 在 `apps/` 下另建独立工程(见 [../../docs/06-app-conventions.md](../../docs/06-app-conventions.md))。
>
> 这个工程同时也被 `new-app.sh` 当作**脚手架模板**,改动它会影响所有新工程。

一个 **APK 同时跑在 Android TV 和 Pico 4 上**的最小 Compose 工程。

存在的目的:

1. 验证「无 IDE 纯命令行」的完整闭环(构建 → 安装 → 启动 → 读 UI 树)
2. 验证同一个 APK 能覆盖两台差异极大的设备(32 位 TV / 64 位 VR)
3. 把设备真实规格直接渲染到屏幕上,换设备时一眼能看出差异
4. 作为 `tools/new-app.sh` 的模板

---

## 构建

```bash
cd apps/DualDemo
./gradlew assembleDebug
# → app/build/outputs/apk/debug/app-debug.apk
```

`local.properties` 里的 SDK 路径是机器相关的(已在根 `.gitignore` 里排除):

```properties
sdk.dir=/opt/android-sdk
```

首次构建约 3 分钟。若遇到 TLS 握手失败见
[../../docs/05-gotchas.md](../../docs/05-gotchas.md#gradle-并发拉依赖时报-tls-握手失败)。

## 版本号

`versionName` / `versionCode` **不在本工程里写**,而是从仓库根的
[`version.properties`](../../version.properties) 推导(界面上的版本也用
`BuildConfig.VERSION_NAME`,同样没有字面量):

```properties
version=0.0.1        # versionName=0.0.1  versionCode=1
```

改版本只改那一个文件,然后 `bash ../../tools/tag-release.sh`。完整约定(含为什么
`versionCode` 要推导、为什么不支持 `-alpha.1` 后缀)见
[../../docs/06-app-conventions.md](../../docs/06-app-conventions.md#版本号)。

## 安装

```bash
# TCL 电视 —— 必须走专用脚本,原因见 docs/03
bash ../../tools/tv-install.sh app/build/outputs/apk/debug/app-debug.apk

# Pico 4 —— 普通 adb install 即可
adb -s 192.0.2.29:5555 install -r app/build/outputs/apk/debug/app-debug.apk
```

## 运行

```bash
adb -s $DEV shell am start -n com.example.dualdemo/.MainActivity
```

界面上是一个可 D-pad 导航的列表,直接显示当前设备的:

型号 / 产品代号 / Android 版本 / 构建指纹 / CPU 架构 / 屏幕分辨率与密度 / 逻辑 dp 尺寸 /
内存 / 存储 / 是否 Android TV / 是否触摸屏 / HDMI-CEC / Vulkan / OpenGL ES / VR 头显模式

不用截图也能读值(用 `uiautomator` 读 UI 树):

```bash
adb -s $DEV shell uiautomator dump /sdcard/ui.xml
adb -s $DEV pull /sdcard/ui.xml /tmp/ui.xml
```

---

## 技术选型

| 项 | 取值 | 理由 |
|---|---|---|
| `minSdk` | **29** | 电视是 30,Pico 是 29,取低者 |
| `compileSdk` / `targetSdk` | **34** | 侧载场景不用迁就 Play 商店的最高要求 |
| UI | `androidx.tv:tv-material:1.0.0` | TV 优先;它只是 Compose UI,在 Pico 上也能正常渲染 |
| `abiFilters` | **不配** | 工程无 native 代码;传递依赖带的 `.so` AGP 会为所有 ABI 打包 |
| 版本组合 | AGP 8.7.3 + Kotlin 2.0.21 + Compose BOM 2024.12.01 | 实测可用 |

## 目录

```
apps/DualDemo/
├── settings.gradle.kts
├── build.gradle.kts            根构建脚本(插件版本在此声明)
├── gradle.properties
├── gradlew / gradlew.bat
├── gradle/wrapper/
├── local.properties            机器相关,已 gitignore
└── app/
    ├── build.gradle.kts
    ├── proguard-rules.pro
    └── src/main/
        ├── AndroidManifest.xml
        ├── java/com/example/dualdemo/MainActivity.kt
        └── res/
            ├── drawable/banner.png          320×180,TV 桌面必需
            ├── drawable/ic_launcher_foreground.xml
            ├── mipmap-anydpi-v26/ic_launcher.xml
            └── values/{strings,colors,themes}.xml
```

---

## 让一个 APK 同时上 TV 和 VR 的三个关键点

### 1. `leanback` 不能声明为必需

```xml
<uses-feature android:name="android.software.leanback" android:required="false" />
<uses-feature android:name="android.hardware.touchscreen" android:required="false" />
```

写 `required="true"` 的话,没有 leanback 的设备(Pico)**会拒绝安装**。

### 2. 两个 launcher category 都要注册

```xml
<intent-filter>
    <action android:name="android.intent.action.MAIN" />
    <category android:name="android.intent.category.LEANBACK_LAUNCHER" />  <!-- TV 桌面 -->
    <category android:name="android.intent.category.LAUNCHER" />           <!-- 手机/VR 应用列表 -->
</intent-filter>
```

### 3. TV banner 必须是 320×180

```xml
<application android:banner="@drawable/banner" ...>
```

尺寸不对的话,TV 桌面那一行会显示成空白块。

> `banner.png` 是用 Python 手写 PNG 字节流生成的(不依赖 PIL),原理就是拼
> `IHDR` + `IDAT(zlib)` + `IEND` 三个 chunk —— 环境准备见
> [../../docs/01-headless-android-build.md](../../docs/01-headless-android-build.md)。

---

## debug 自截图钩子

`app/src/debug/` 下带了一套**只在 debug 构建里**生效的自截图钩子 ——
它让 `screencap` 被 `FLAG_SECURE` 挡掉的设备(比如 Pico 4)也能被 `adb` 看见。

```bash
bash ../../tools/ui-dump.sh com.example.dualdemo --launch
```

这套钩子同时是 `tools/new-app.sh` 的模板,新工程会自带。原理见
[../../docs/07-debug-ui-capture.md](../../docs/07-debug-ui-capture.md)。

## 已知限制

- **Pico 上看不到画面** —— 这是系统级限制,不是本工程的问题:
  `screencap` 被 `FLAG_SECURE` 挡成纯白图,`uiautomator` 也只能读到 `com.pvr.vrshell` 的节点。
  解法就是上面那套**自截图钩子**(`tools/ui-dump.sh`),它能拿到真实渲染的 PNG。
  细节和替代方案见 [docs/04](../../docs/04-pico4-notes.md)、[docs/07](../../docs/07-debug-ui-capture.md)。
- **电视上屏保会干扰自动化** —— 屏保期间 `am start` 返回成功但不生效;
  偶发还会把之后的所有按键全吞掉。`tools/tv-install.sh` 已内置处理。见 [docs/03](../../docs/03-tcl-tv-sideload.md)。
- 界面文案目前是硬编码中文,没有做 i18n。
