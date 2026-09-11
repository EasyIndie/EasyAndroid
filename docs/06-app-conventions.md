# 06 · 工程目录约定

## 核心规则

> **`apps/` 下每个子目录都是一个独立的、可单独构建的 Android 工程。**
> 新增应用 = 在 `apps/` 下新建一个工程目录,**不要**往已有工程里塞业务模块。

两条推论:

1. **每个工程自带 `settings.gradle.kts` + `gradlew` + `gradle/wrapper/`**,是独立 Gradle 构建,
   不是某个根工程下的 subproject。仓库根目录**没有** `settings.gradle.kts`。
2. **工程之间不共享代码**。要复用的东西放 `tools/`(脚本)或 `docs/`(知识),
   真要做共享库再另立 `libs/` 并说明理由。

## `apps/` 现状

| 目录 | 定位 |
|---|---|
| `apps/DualDemo` | **测试验证工程**。用于验证工具链、ADB 链路、设备兼容性。保持精简,**不要往里加业务功能**。 |

## 新建一个应用

```bash
bash tools/new-app.sh <AppName> <package.id>

# 例
bash tools/new-app.sh MyPlayer com.example.myplayer
```

脚本会以 `DualDemo` 为模板复制出一份,替换包名 / 应用名 / 工程名,并清掉构建产物。
生成后直接可构建:

```bash
cd apps/MyPlayer
./gradlew assembleDebug
```

### 手动创建时的清单

```
apps/<AppName>/
├── README.md                    必须写:这个应用做什么、怎么构建、怎么装
├── settings.gradle.kts          rootProject.name = "<AppName>"
├── build.gradle.kts             只说插件版本,apply false
├── gradle.properties
├── gradlew / gradlew.bat
├── gradle/wrapper/              gradle-wrapper.jar + .properties
├── local.properties             sdk.dir=...  (gitignore,不要提交)
└── app/
    ├── build.gradle.kts         namespace / applicationId / minSdk / targetSdk
    └── src/main/
        ├── AndroidManifest.xml
        ├── java/<package path>/
        └── res/
```

`gradle/wrapper/gradle-wrapper.jar` 是二进制。手写不出来,用 `gradle wrapper` 生成,
或者直接从 `apps/DualDemo/gradle/wrapper/` 拷。

## 命名与标识

| 项 | 约定 |
|---|---|
| 目录名 | 大驼峰,同 `rootProject.name`,如 `MyPlayer` |
| `applicationId` | 反域名,如 `com.example.myplayer`。**不同工程必须不同**,否则装到同一台设备会互相覆盖 |
| 应用显示名 | `app/src/main/res/values/strings.xml` 里的 `app_name` |
| Android 模块目录 | 统一叫 `app/`(除非一个工程里有多个模块) |

> `applicationId` 冲突是很容易踩的坑:两个工程用了同一个 id,后装的会覆盖先装的,
> 而且 `adb uninstall` 分不清是谁。新建工程时先确认一下。

## 版本组合

保持全仓库一致,避免每个工程各自漂移:

| 组件 | 版本 |
|---|---|
| AGP | 8.7.3 |
| Kotlin | 2.0.21 |
| compileSdk / targetSdk | 34 |
| minSdk | **29** |
| Compose BOM | 2024.12.01 |

`minSdk = 29` 是为了同时覆盖手上的设备(Android TV 是 API 30,Pico 4 是 API 29)。
换设备后按 [docs/02](02-adb-multi-device.md#设备规格对照) 重新核算。

## 目标设备兼容性

如果新应用要同时跑在 TV 和手机/VR 上,`AndroidManifest.xml` 里那三条不能少:

```xml
<uses-feature android:name="android.software.leanback" android:required="false" />
<uses-feature android:name="android.hardware.touchscreen" android:required="false" />
<intent-filter>
    <action android:name="android.intent.action.MAIN" />
    <category android:name="android.intent.category.LEANBACK_LAUNCHER" />
    <category android:name="android.intent.category.LAUNCHER" />
</intent-filter>
```

外加 `android:banner` 指向一张 **320×180** 的图。

细节和原因见 [apps/DualDemo/README.md](../apps/DualDemo/README.md#让一个-apk-同时上-tv-和-vr-的三个关键点)。

### 只跑单一设备时

如果应用只给电视用,可以把 `leanback` 设成 `required="true"` 并去掉 `LAUNCHER` category。
但**要在该工程的 README 里写明目标设备**,否则以后会有人拿它去装 Pico 然后困惑为什么装不上。

## 每个工程的 README 必须回答

1. 这个应用**做什么**
2. **目标设备**是哪台(或哪几台)
3. 怎么**构建**、怎么**安装**、怎么**验收**
4. 有哪些**已知限制**

参考 [apps/DualDemo/README.md](../apps/DualDemo/README.md)。

## 验收要求

新工程至少要跑通一遍完整闭环,并在 README 里记下证据:

```bash
bash tools/devices.sh                                    # 设备在线
cd apps/<AppName> && ./gradlew assembleDebug             # 构建通过
bash ../../tools/tv-install.sh app/build/outputs/apk/debug/app-debug.apk
bash ../../tools/device-status.sh "$TV_ADDR" <applicationId>   # 装了、在前台、无崩溃
```

安装和验收的正确姿势见 [AGENTS.md](../AGENTS.md) —— 尤其是**不要对 TCL 电视用 `adb install`**。
