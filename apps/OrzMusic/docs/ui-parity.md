# Android 界面与 Web 播放器对齐

参考实现是 `OrzGeeker/OrzMusic` 仓库里的 Web 播放器：

| Web | 作用 |
|---|---|
| `Resources/Views/player.leaf` | 页面结构：侧栏 / 顶栏 / 歌曲表 / 播放坞 / 队列抽屉 |
| `Resources/Public/audio/app.css` | 深色配色、间距、响应式断点 |
| `Resources/Public/audio/app.js` | 队列、搜索、歌单、定位、快捷键、格式分组 |
| `Resources/Public/audio/visualizer.js` | 声场可视化 |

Android 端不是逐像素照搬，而是把同一套信息架构翻译成 Compose，
并补上 TV D-pad / Pico 2D 面板需要的焦点与返回键行为。

## 组件映射

| Web | Android | 说明 |
|---|---|---|
| `.sidebar` + `.format-group` | `AppRoot.Sidebar` + `FormatCatalog` | 按模块/复古/合成/常规/其他分组，显示数量 |
| `.topbar` 搜索 | `TopBar` + `SearchField` | 全局搜索，防抖 300ms；`/` 聚焦 |
| `.queue-trigger` | 顶栏「队列 N」 | 打开右侧队列抽屉 |
| `.song-table` | `LibraryContent` + `SongRow` | 宽屏显示专辑/大小，窄屏自动减列 |
| `.song-row .row-play` | `SongRow` 左侧播放态 | 当前曲目显示薄荷色波形柱 |
| `.player-dock` | `PlayerDock` | 进度、上一首/播放/下一首、时间、音量、静音 |
| `.seek-wrap` | `SeekBar` | 点击/拖动；获得焦点后 D-pad 左右 ±5s |
| `.queue-panel` | `QueueDrawer` | 队列、移除、保存当前队列、加载/删除歌单 |
| `player.js` 的队列 | `PlaybackQueue`（core） | UI 不拥有队列语义 |
| Media Session | `PlaybackService`（MediaSessionService） | 后台播放 / 通知栏 / 锁屏 / 耳机控制 |
| `<audio>` 输出 | ExoPlayer（service 内） | Activity 只通过 `MediaController` 控制 |
| `visualizer.js` | `VisualizerBars` + `VisualizerAudioProcessor` | 真实 PCM 电平，不申请录音权限 |
| `L` 定位 | 「正在播放」页「定位」/ `L` | 调 `/api/songs/{id}/location` 后滚动到该行 |
| `? / H` | 顶栏「?」 | 键盘 / 遥控快捷键说明 |

## 自适应规则

- `< 760dp`：顶部品牌 + 搜索 + 标签行 + 单栏；格式筛选用横向 chips。
- `>= 760dp`：220dp 左侧栏 + 主内容 + 底部播放坞。
- `>= 800dp`：歌曲表额外显示专辑、大小列。
- 队列抽屉在窄屏接近全宽；在宽屏是 390dp 右侧浮层。
- 播放坞在 `< 620dp` 时拆成两行，避免把控制按钮挤出去。

## 平台差异 / 有意没搬的部分

| Web 功能 | Android 处理 | 原因 |
|---|---|---|
| 管理员目录导入 | 未移植 | 浏览器 `webkitdirectory` + 管理令牌是 Web 管理端能力，不是播放器必需功能 |
| 无限滚动 | 「加载更多」按钮 | TV 上比滚动触发更可控，也避免 D-pad 滚到底时误触发 |
| 键盘方向键调节音量 | 音量条获得焦点后 D-pad 上下调；`M` 静音 | 避免全局拦截方向键破坏 TV 焦点导航 |
| 系统 IME（Pico） | 应用内键盘 | Pico 的 `PicoXR_CustomDialog` 会抢 display 焦点，见 [playback.md](playback.md) |

## 验收

```bash
cd apps/OrzMusic
./gradlew :core:test
./gradlew :app:testDebugUnitTest
# → app/build/outputs/roborazzi/orzmusic-{tv,phone,queue,nowplaying}.png

# Pico（自截图）
bash ../../tools/pico-panel.sh com.jokerhub.orzmusic.android awake
bash ../../tools/ui-dump.sh com.jokerhub.orzmusic.android "$PICO_ADDR" --launch
```

TV 用 D-pad 验收：进入曲库 → 上下走格式/歌曲 → OK 播放 → 顶栏「正在播放」→
进度条获得焦点后左右 seek；BACK 关闭覆盖层。
