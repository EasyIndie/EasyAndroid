package com.example.dualdemo

import androidx.compose.foundation.background
import androidx.compose.foundation.focusable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.key.Key
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.test.ExperimentalTestApi
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertIsFocused
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.onRoot
import androidx.compose.ui.test.performKeyInput
import androidx.compose.ui.test.pressKey
import androidx.compose.ui.unit.dp
import androidx.tv.material3.MaterialTheme
import androidx.tv.material3.darkColorScheme
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.github.takahirom.roborazzi.captureRoboImage
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/**
 * JVM 截图测试 —— **不需要设备,也不需要模拟器**。
 *
 * Robolectric 在 JVM 上跑 Android 框架,Roborazzi 把 Compose 的渲染结果落成 PNG。
 * 这是 UI 迭代最快的一档:秒级出图,而且能在 CI 上跑。
 *
 * ```bash
 * # 出图(结果在 app/build/outputs/roborazzi/)
 * ./gradlew testDebugUnitTest -Proborazzi.test.record=true
 *
 * # 只跑测试不出图(CI / 本地断言)
 * ./gradlew testDebugUnitTest
 * ```
 *
 * `@Config(qualifiers = ...)` 决定模拟成什么屏幕。
 * **`w1280dp-h720dp-240dpi` 正好是那台 TCL 电视的逻辑尺寸**
 * (1920x1080 @240dpi → 1280x720 dp,见 docs/02)。
 * 换个 qualifier 就能看同一界面在别的屏幕上的样子 —— 不用改代码、不用换设备。
 */
@RunWith(AndroidJUnit4::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(qualifiers = "w1280dp-h720dp-240dpi")
class DeviceInspectorScreenshotTest {

    @get:Rule
    val rule = createComposeRule()

    @Test
    fun rendersOnTvSize() {
        rule.setContent {
            MaterialTheme(colorScheme = darkColorScheme()) { DeviceInspector() }
        }
        // 先断言渲染出来了,再看图 —— 否则截到一张空白图也没人知道
        rule.onNodeWithText("双端真机自检").assertIsDisplayed()
        rule.onRoot().captureRoboImage("build/outputs/roborazzi/device-inspector-tv.png")
    }

    /** 同一个界面在手机尺寸下的样子。 */
    @Test
    @Config(qualifiers = "w411dp-h891dp-420dpi")
    fun rendersOnPhoneSize() {
        rule.setContent {
            MaterialTheme(colorScheme = darkColorScheme()) { DeviceInspector() }
        }
        rule.onRoot().captureRoboImage("build/outputs/roborazzi/device-inspector-phone.png")
    }
}

/*
 * ── 关于 D-pad 焦点测试 ──────────────────────────────────────────────
 *
 * 焦点行为是 TV 开发最容易翻车的地方,但它**没法在这个环境里可靠地断言**:
 * Robolectric 下 Activity 的窗口默认拿不到焦点,Compose 的 FocusOwner 因此
 * 不会派发焦点,`assertIsFocused()` 一律失败(实测 Semantics 里
 * `Focused = 'false'`,只有 `Actions = [RequestFocus]`)。
 *
 * 想验焦点有两条路:
 *   · 真机上用 `adb shell input keyevent` + `uiautomator dump` 看 focused 节点
 *     (tools/device-status.sh 的最后一段就是这个)
 *   · 或者额外搭一套让 Robolectric 窗口获得焦点的脚手架(要自己起
 *     AndroidComposeTestRule + 手动 requestFocus),成本不低
 *
 * 所以这里只保留"渲染成图"这一类测试 —— 它不需要窗口焦点,稳定且够快。
 */
