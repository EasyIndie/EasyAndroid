package com.jokerhub.orzmusic.android

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.test.ExperimentalTestApi
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.onRoot
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.tv.material3.MaterialTheme
import androidx.tv.material3.darkColorScheme
import com.github.takahirom.roborazzi.captureRoboImage
import com.jokerhub.orzmusic.core.model.Artist
import com.jokerhub.orzmusic.core.model.FormatCount
import com.jokerhub.orzmusic.core.model.Song
import com.jokerhub.orzmusic.android.ui.screens.LibraryContent
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/**
 * JVM 截图测试 —— 不碰设备。
 *
 * 只渲染曲库页(无状态 composable),不碰网络 / ViewModel;
 * 这样 CI 和本地都能稳定出图。
 *
 * ```bash
 * ./gradlew testDebugUnitTest
 * # → app/build/outputs/roborazzi/orzmusic-tv.png / orzmusic-phone.png
 * ```
 */
@OptIn(ExperimentalTestApi::class)
@RunWith(AndroidJUnit4::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(qualifiers = "w1280dp-h720dp-240dpi")
class OrzMusicScreenshotTest {

    @get:Rule
    val rule = createComposeRule()

    private val songs = listOf(
        Song(
            id = "1",
            title = "Car Mechanic Simulator 2015",
            artist = Artist(id = "a", name = "UPLiNK"),
            fileFormat = "mod",
            fileSize = 15_630,
            duration = 76.8,
            playStrategy = "wasmDecode"
        ),
        Song(
            id = "2",
            title = "Half Side Products",
            artist = Artist(id = "a", name = "UPLiNK"),
            fileFormat = "xm",
            fileSize = 37_104,
            duration = 35.8,
            playStrategy = "wasmDecode"
        ),
        Song(
            id = "3",
            title = "Demo Track",
            artist = Artist(id = "b", name = "Nelly"),
            fileFormat = "mp3",
            fileSize = 3_200_000,
            duration = 201.0,
            playStrategy = "directFile"
        )
    )

    private val formats = listOf(
        FormatCount("xm", 3396),
        FormatCount("mod", 1093),
        FormatCount("it", 254),
        FormatCount("mp3", 15),
        FormatCount("ogg", 41)
    )

    private fun render() {
        rule.setContent {
            MaterialTheme(colorScheme = darkColorScheme()) {
                LibraryContent(
                    songs = songs,
                    formats = formats,
                    selectedFormat = null,
                    totalSongs = 5533,
                    totalArtists = 713,
                    loading = false,
                    onFormat = {},
                    onSong = { _, _ -> },
                    onLoadMore = {},
                    modifier = Modifier.fillMaxSize().background(Color(0xFF080C10))
                )
            }
        }
    }

    @Test
    fun rendersOnTvSize() {
        render()
        rule.onNodeWithText("曲库").assertIsDisplayed()
        rule.onNodeWithText("Car Mechanic Simulator 2015").assertIsDisplayed()
        rule.onRoot().captureRoboImage("build/outputs/roborazzi/orzmusic-tv.png")
    }

    @Test
    @Config(qualifiers = "w411dp-h891dp-420dpi")
    fun rendersOnPhoneSize() {
        render()
        rule.onRoot().captureRoboImage("build/outputs/roborazzi/orzmusic-phone.png")
    }
}
