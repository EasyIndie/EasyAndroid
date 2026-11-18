# 后台播放、通知栏、声场与 Pico 焦点

本文记录 Android 端三个和 Web 端差异最大的部分:后台播放链路、PCM 声场取样、
以及 Pico 上 BACK/焦点问题的定位与处理。

## 1. 后台播放 / MediaSession

```
Activity / ViewModel
  └─ PlaybackController(MediaController 代理)
        │  bind / 异步连接
        ▼
PlaybackService : MediaSessionService
  ├─ ExoPlayer(真正持有播放器)
  ├─ MediaSession(通知栏 / 锁屏 / 耳机线控)
  ├─ OrzMediaNotificationProvider(上一首 / 播放暂停 / 下一首)
  └─ OrzRenderersFactory
        └─ VisualizerAudioProcessor(PCM 取样)
```

- **ExoPlayer 归 service 所有**,Activity 销毁不会停止播放。
- `PlaybackController` 首次连接是异步的;连接前的命令会排队,连接后按顺序补发。
- 通知栏默认由 Media3 管理;自定义 `OrzMediaNotificationProvider` 额外提供
  上一首 / 下一首,通过 `SessionCommand` 转给 `PlaybackCommandBridge`,
  再调用 ViewModel 的 `playNext()` / `playPrevious()`。
- **权限**:
  - `FOREGROUND_SERVICE`
  - `FOREGROUND_SERVICE_MEDIA_PLAYBACK`(Android 14+)
  - `POST_NOTIFICATIONS`(Android 13+;拒绝时播放继续,只是没有通知)
  - `WAKE_LOCK`
  - **不需要** `RECORD_AUDIO`
- 从最近任务划掉后:当前曲目继续播;通知栏的上一首/下一首需要 App 进程里的
  ViewModel,Activity 被销毁后这两个按钮会变成 no-op。

### 验证

```bash
# 播放后按 HOME,位置仍应前进
adb shell dumpsys media_session | grep 'state=PlaybackState'
adb shell dumpsys activity services com.jokerhub.orzmusic.android | grep -E 'isForeground|foregroundNoti'
```

实测通知：`category=transport actions=3`(上一首/播放暂停/下一首)。

## 2. 真实 PCM 声场

没有用 `android.media.audiofx.Visualizer`(那需要 `RECORD_AUDIO`),而是在
Media3 的播放管线里插入 `VisualizerAudioProcessor`:

- 通过 `DefaultRenderersFactory.buildAudioSink()` 注入;
- 在 `AudioTrack` 写入前拿到 PCM16 / float;
- 按 48 段计算 RMS、平滑后推到 `VisualizerBus`(StateFlow);
- Compose 的 `VisualizerBars` 同时用于播放坞和全屏正在播放页。

暂停/切歌时 service 会调用 `VisualizerBus.reset()`,不会停在最后一帧。

## 3. Pico BACK / 焦点问题

### 现象

Pico 上按 BACK 后,下一次按键可能完全不生效;`uiautomator` 里没有任何
`focused=true` 的节点。

### 实测原因

`dumpsys input` 在异常时是这样:

```
FocusedDisplayId: 0
FocusedWindows:
  displayId=64, name='...OrzMusic.../MainActivity'
  displayId=0,  name='Window{... PicoXR_CustomDialog}'
```

- App 的窗口在虚拟 display(64/66/68…),但 **`hasFocus=false`**;
- `PicoXR_CustomDialog`(`com.pvr.vrshell`, display 0)持有焦点;
- 它是 `canReceiveKeys=false` 的系统层窗口,所以按键既到不了 App,
  也不会被它自己处理 —— 表现为“BACK/方向键偶发失灵”;
- 触发点是 Pico 的系统 IME / VRSHELL 面板在 BACK 后把焦点收回 display 0。
  App 无法直接给别的 display 设置焦点。

### App 侧修复/兜底

1. App 收到 BACK 时由 `BackHandler` / Activity `dispatchKeyEvent` 先处理覆盖层;
   (但 VRSHELL 仍可能在系统层把焦点收回 display 0,App 侧无法阻止。);
2. 覆盖层关闭后 `moveFocus` + 显式 `FocusRequester` 重选焦点;
3. `ON_RESUME` 时清 IME、清焦点、重新请求当前层焦点;
4. **Pico 使用应用内键盘**(只读输入卡片 + `InAppKeyboardDialog`),
   不再启动 `PicoXR_CustomDialog` 系统 IME;
5. 所有覆盖层都有屏幕上的「关闭/完成/返回」;`Esc` 也可以关闭。
   这些路径不会触发 VRSHELL 的 BACK 处理。

### 仍需知道的限制

Pico 把 BACK 作为面板级系统键处理,**无法保证 App 收到每一次 BACK**。
这是 VRSHELL 行为,不是 Compose 的 `BackHandler` 漏写。真机验收时
建议优先用屏幕上的关闭按钮 / `Esc`;TV 的 BACK 正常由 `BackHandler` 处理。
