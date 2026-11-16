package com.easyindie.easyinfo

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
 * JVM 截图测试 —— 不碰设备,~20 秒出图。
 *
 * ```bash
 * ./gradlew testDebugUnitTest
 * # → app/build/outputs/roborazzi/easyinfo-tv.png / easyinfo-phone.png
 * ```
 *
 * `w1280dp-h720dp-240dpi` = TCL 电视的逻辑尺寸(1920x1080 @240dpi)。
 * ⚠️ 它验不了 D-pad 焦点(Robolectric 窗口没有焦点),焦点必须上真机验。
 */
@OptIn(ExperimentalTestApi::class)
@RunWith(AndroidJUnit4::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(qualifiers = "w1280dp-h720dp-240dpi")
class EasyInfoScreenshotTest {

    @get:Rule
    val rule = createComposeRule()

    @Test
    fun rendersOnTvSize() {
        rule.setContent {
            MaterialTheme(colorScheme = darkColorScheme()) { AppRoot() }
        }
        rule.onNodeWithText("设备").assertIsDisplayed()
        rule.onNodeWithText("品牌 / 型号").assertIsDisplayed()
        rule.onRoot().captureRoboImage("build/outputs/roborazzi/easyinfo-tv.png")
    }

    @Test
    @Config(qualifiers = "w411dp-h891dp-420dpi")
    fun rendersOnPhoneSize() {
        rule.setContent {
            MaterialTheme(colorScheme = darkColorScheme()) { AppRoot() }
        }
        rule.onRoot().captureRoboImage("build/outputs/roborazzi/easyinfo-phone.png")
    }
}
