# 08 · JVM 截图测试:不碰设备看 UI

## 为什么需要它

前面几篇解决了"怎么在真机上看界面",但真机终究有成本:

| 档位 | 单轮耗时 | 适合 |
|---|---|---|
| **JVM 截图测试(本篇)** | **~20 秒**(增量) | 布局、主题、状态、换屏幕规格 |
| Pico + 自截图 | ~10 秒 + 3 秒装 | 真实字号/密度、VR 面板表现 |
| TCL 电视 + 自截图 | ~85 秒 | 遥控 D-pad、TV 输入、最终验收 |

改个 padding、换个颜色、调个文案 —— 这类改动占日常的绝大多数,而它们
**根本不需要真机**。用真机跑这些,时间全花在安装上。

## 它是怎么工作的

- **Robolectric** 在 JVM 上跑 Android 框架(不需要模拟器,不需要设备)
- **Roborazzi** 把 Compose 的渲染结果落成 PNG

```
app/src/test/java/<pkg>/*ScreenshotTest.kt   ← 测试
app/build/outputs/roborazzi/*.png            ← 产物
```

## 用法

```bash
cd apps/DualDemo

# 出图(默认行为)
./gradlew testDebugUnitTest

# 只要断言、不要图(CI 用)
./gradlew testDebugUnitTest -Proborazzi.test.record=false
```

## 换屏幕规格只要改一行

这是 JVM 截图相对真机的核心优势。`@Config(qualifiers = ...)` 决定模拟成什么屏幕:

```kotlin
@Config(qualifiers = "w1280dp-h720dp-240dpi")   // 那台 TCL 电视的逻辑尺寸
@Config(qualifiers = "w411dp-h891dp-420dpi")    // 普通手机
```

电视是 1920x1080 @240dpi → **逻辑 1280x720 dp**(见 [02](02-adb-multi-device.md)),
所以 `w1280dp-h720dp-240dpi` 出来的图就是电视上真实的样子。

**改个 qualifier 就能看同一个界面在别的屏幕上的表现,不用换设备、不用改代码。**

## 配置要点(踩过的坑)

### 1. Roborazzi 版本必须和工程的 Kotlin 对齐

```
e: roborazzi-core.kotlin_module Module was compiled with an incompatible
   version of Kotlin. The binary version of its metadata is 2.3.0,
   expected version is 2.0.0.
```

**Roborazzi 1.66+ 是用 Kotlin 2.1+/2.3 编的**,元数据版本比工程的 Kotlin 2.0.21
编译器的预期新,直接编译不过。

**注意 POM 里的 `kotlin-stdlib` 版本不能作为判断依据** —— 实测 1.65.0 声明
的是 `2.0.21`,但 jar 的元数据是 2.3.0(它用高版本 Kotlin 编译、把 stdlib 的
API 版本压低了)。

工程在 Kotlin 2.0.21 下,**用 Roborazzi 1.30.0**:

```kotlin
testImplementation("io.github.takahirom.roborazzi:roborazzi:1.30.0")
testImplementation("io.github.takahirom.roborazzi:roborazzi-compose:1.30.0")
```

> 升级 Kotlin/Compose 之后可以同步升级 Roborazzi。升级链路见
> [09-upgrading-the-stack.md](09-upgrading-the-stack.md)(待补)。

### 2. `-P` 传的 Gradle 属性不会自动进测试 JVM

Roborazzi 靠**系统属性**决定"出图还是只断言"。命令行用 `-P` 传只是 Gradle 属性,
必须显式转发:

```kotlin
testOptions {
    unitTests {
        isIncludeAndroidResources = true   // 不设的话截图里没有主题/字体
        all { test ->
            test.systemProperty(
                "roborazzi.test.record",
                project.findProperty("roborazzi.test.record")?.toString() ?: "true"
            )
        }
    }
}
```

## ⚠️ 它验不了什么:D-pad 焦点

**焦点行为在 Robolectric 下没法可靠断言。** Robolectric 里 Activity 的窗口默认
拿不到焦点,Compose 的 `FocusOwner` 因此不会派发焦点事件,`assertIsFocused()`
一律失败:

```
Failed to assert the following: (Focused = 'true')
Semantics of the node: ... Focused = 'false' Actions = [RequestFocus]
```

而 TV 开发**最容易翻车的恰恰就是焦点**。所以:

- **焦点验证仍然要上真机**:`adb shell input keyevent` + `uiautomator dump`,
  看哪个节点是 `focused="true"`(`tools/device-status.sh` 最后一段就是这个)
- 想让它在这里也能跑,得额外搭一套让 Robolectric 窗口获得焦点的脚手架
  (`createAndroidComposeRule` + 手动 `requestFocus`),成本不低,本仓库没做

**能在这里验的**:布局对不对、有没有渲染出来、主题/颜色/字号、换屏幕规格后的表现、
数据驱动的文案。**验不了的**:焦点顺序、遥控按键响应、真实设备特有行为。

## CI 上跑

`testDebugUnitTest` 已经在 [CI](../.github/workflows/ci.yml) 里了。产物会作为
artifact 上传 —— **推送一次就能在 Actions 页面下载到渲染出来的界面**,
不需要本地环境。

CI 里可以把出图关掉(只断言):

```yaml
- run: ./gradlew testDebugUnitTest -Proborazzi.test.record=false
```

## 当前覆盖

`apps/DualDemo/app/src/test/java/com/example/dualdemo/DeviceInspectorScreenshotTest.kt`

| 测试 | 验的东西 |
|---|---|
| `rendersOnTvSize` | 电视尺寸(1280x720dp)下渲染成功,标题可见 |
| `rendersOnPhoneSize` | 同一界面在手机尺寸下的样子 |
