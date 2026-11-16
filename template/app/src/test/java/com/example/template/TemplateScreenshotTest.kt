package com.example.template

import androidx.compose.ui.test.ExperimentalTestApi
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.onRoot
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
 * `w1280dp-h720dp-240dpi` 是那台 TCL 电视的逻辑尺寸(1920x1080 @240dpi)。
 *
 * ⚠️ **它验不了 D-pad 焦点**:Robolectric 下窗口没有焦点,`assertIsFocused()`
 * 必然失败。焦点必须上真机验(`input keyevent` + `uiautomator dump`)。
 * 原理与边界见 docs/08-jvm-screenshot-testing.md。
 */
@OptIn(ExperimentalTestApi::class)
@RunWith(AndroidJUnit4::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(qualifiers = "w1280dp-h720dp-240dpi")
class TemplateScreenshotTest {

    @get:Rule
    val rule = createComposeRule()

    @Test
    fun rendersOnTvSize() {
        rule.setContent {
            MaterialTheme(colorScheme = darkColorScheme()) { AppRoot() }
        }
        // 先断言渲染出来了,再看图 —— 否则截到一张空白图也没人知道
        rule.onNodeWithText("第一项").assertIsDisplayed()
        rule.onRoot().captureRoboImage("build/outputs/roborazzi/app-tv.png")
    }

    /** 同一个界面在手机尺寸下的样子。 */
    @Test
    @Config(qualifiers = "w411dp-h891dp-420dpi")
    fun rendersOnPhoneSize() {
        rule.setContent {
            MaterialTheme(colorScheme = darkColorScheme()) { AppRoot() }
        }
        rule.onRoot().captureRoboImage("build/outputs/roborazzi/app-phone.png")
    }
}
