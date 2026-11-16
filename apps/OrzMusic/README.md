# OrzMusic · Android 客户端

[OrzGeeker/OrzMusic](https://github.com/OrzGeeker/OrzMusic) 的 Android 客户端。
后端是一个 **KeyGen Music / 芯片音乐 / 模块音乐**的曲库与播放服务(Swift Vapor),
这个工程消费它的 HTTP API。

> ⚠️ 仓库地址是 `OrzGeeker/OrzMusic`。GitHub 上**不存在** `OrzMC/OrzMusic`
> (OrzMC 是 Minecraft 插件组织;OrzGeeker 才是音乐项目)。

| | |
|---|---|
| 包名(Android) | `com.jokerhub.orzmusic.android` |
| 包名(Apple,预留) | `com.jokerhub.orzmusic.apple` |
| 目标设备 | **手机 / 平板 / TV / VR(Pico 2D 面板)** 同一 APK |
| minSdk / targetSdk | 29 / **36** |
| 权限 | `INTERNET`(仅此一项) |
| 默认服务器 | `https://music.jokerhub.cn`(设置页可改自建地址) |
| 版本号 | 仓库根 [`version.properties`](../../version.properties)(唯一来源) |
| 发布渠道 | 见 [`publish.properties`](publish.properties) |

## 功能(当前实现)

- **曲库**:5533+ 首,按格式筛选(`xm` / `mod` / `it` / `mp3` / `ogg` …),分页加载
- **艺术家**:列表 + 某位艺术家的全部曲目
- **歌单**:后端歌单列表 + 详情
- **搜索**:歌曲名 / 艺术家名(输入防抖)
- **播放**:Media3/ExoPlayer 播放 `directFile` 与 `serverDecode` 的曲目
- **设置**:切换服务器地址、测试连接(`/api/health`)
- **自适应**:手机单栏 / 平板与 TV 左侧导航 / 宽屏列表+详情两栏
- **TV**:`leanback` 启动入口、banner、D-pad 可走(`tv-material3` 的 Card)
- **VR**:Pico 的 2D 面板按宽屏渲染,触摸与遥控都能操作

## 芯片格式怎么播

后端把曲目分成三种播放策略:

| 策略 | 格式 | 服务端返回 | 本客户端 |
|---|---|---|---|
| `directFile` | mp3 / ogg / flac / m4a / aac / PCM WAV | 原始文件 | ✅ ExoPlayer 直接放 |
| `serverDecode` | sc68、压缩 WAV | 服务端转好的 PCM WAV | ✅ ExoPlayer 直接放 |
| `wasmDecode` | xm / mod / it / s3m / nsf / sid … | 原始模块文件 | ✅ 原生解码(OrzAudioCore + libopenmpt),部分格式回落网页 |

`wasmDecode` 的服务端按设计只给原始文件。本项目用 **NDK 把
[OrzAudioCore](https://github.com/OrzGeeker/OrzAudioCore) + libopenmpt 编成
`liborzaudio.so`**,JNI 解成 16-bit PCM WAV,再交给 ExoPlayer:

```
/api/songs/:id/raw → cache/raw/<id>.mod
        ↓ JNI (OrzAudioCore + libopenmpt)
   cache/pcm/<id>.wav (48kHz stereo PCM)
        ↓
     ExoPlayer
```

已编入:`xm` `mod` `it` `s3m` `mo3` `mtm` `fc13` `fc14`(libopenmpt)
+ `ym` `mid` `bp`(OrzAudioCore builtin)。

`nsf` `spc` `sid` `ahx` `sap` `v2m` `rad` `d00` `hsc` `amd` 等没有编进来,
点播时会明确提示并给出「在网页播放器打开」。

### 重新编译 native 库

`.so` 已提交在 `audio-kit/src/main/jniLibs/`,**普通构建不需要 NDK**。
只有改了 `audio-kit/native/cpp/` 或升级 libopenmpt/OrzAudioCore 时才需要:

```bash
sdkmanager "ndk;27.0.12077973" "cmake;3.22.1"
bash apps/OrzMusic/audio-kit/scripts/build-android.sh          # 两个 ABI
```

细节、版本约束、许可证见 [`audio-kit/native/README.md`](audio-kit/native/README.md)。

## 架构

分层与跨端复用(Web / Apple / Desktop)见
[**docs/architecture.md**](docs/architecture.md)。

- `core/` —— **平台无关**(纯 Kotlin):DTO / `OrzMusicTransport` /
  `PlaybackQueue` / `PlaybackPolicy` / `OrzAudioPlayer` 契约 /
  `DecoderManifest` / `CacheKey`
- `app/` —— Android:Compose、Media3、文件缓存
- `audio-kit/` —— **平台解码 SDK(OrzAudioCore)**:JNI + 流式 AudioDecoder + WavFile + OrzAudioCore 源码 + `decoder-profile.json`;
  可发布为 `com.orzgeeker:audio-core-android:1.2.4`(见 [`audio-kit/README.md`](audio-kit/README.md))

规则:**业务语义写在 `core/`;不要在 UI/Player 里手写格式白名单或队列逻辑。**

解码清单由 `audio-kit/native/decoder-profile.json` 生成:

```bash
python3 apps/OrzMusic/scripts/gen-core-manifest.py          # core 的策略清单
python3 apps/OrzMusic/audio-kit/scripts/gen-manifest.py                  # SDK 的 DecoderManifest.generated.kt
python3 apps/OrzMusic/audio-kit/scripts/gen-manifest.py --check          # CI 校验是否漂移
```

## 构建

```bash
cd apps/OrzMusic
./gradlew assembleDebug
# → app/build/outputs/apk/debug/app-debug.apk

# 纯核心单测(队列 / 策略 / URL,不碰 Android)
./gradlew :core:test

# JVM 截图测试(TV / 手机两种尺寸,不碰设备)
./gradlew testDebugUnitTest
# → app/build/outputs/roborazzi/orzmusic-tv.png / orzmusic-phone.png
```

> native 解码库已提交在 `audio-kit/src/main/jniLibs/{arm64-v8a,armeabi-v7a}/liborzaudio.so`,
> 所以普通构建不需要 NDK。重编方法见上面的「重新编译 native 库」。

## 安装 / 验收

```bash
# TCL 电视(必须走专用脚本,原因见 [docs/03](../../docs/03-tcl-tv-sideload.md))
bash ../../tools/tv-install.sh app/build/outputs/apk/debug/app-debug.apk

# Pico 4 / 手机 / 平板
adb -s "$PICO_ADDR" install -r app/build/outputs/apk/debug/app-debug.apk

# 自截图(Pico 的 screencap 被 FLAG_SECURE 挡住)
bash ../../tools/ui-dump.sh com.jokerhub.orzmusic.android --launch
```

TV 上 D-pad 验收:进「曲库」→ 上下走格式筛选和歌曲列表 → 确认能播放 mp3/ogg 曲目。

### 验收记录(2026-11-16)

| 设备 | 系统 | 结果 |
|---|---|---|
| TCL 电视 | Android 11 / API 30 / armeabi-v7a | ✅ 装、启动、曲库 5533 首加载、D-pad 焦点、MP3 播放;MOD 原生解码播放(`Car Mechanic Simulator 2015`,WAV 实测 76.9s / 48kHz / stereo) |
| Pico 4 | Android 10 / API 29 / arm64-v8a | ✅ `adb install`、宽屏左导航 + 列表、曲库加载;MOD 原生解码播放(进度 0:02 / 1:16) |

> 电视验收时 Clash Meta 的代理把 `music.jokerhub.cn` 拦成 timeout,
> 屏保也会抢输入 —— 都是电视环境问题,不是 App 的 bug。
> 处理办法记在 [docs/backend-api.md](docs/backend-api.md#7-实机验收2026-11-16)。

## 服务器

默认连官方实例 `https://music.jokerhub.cn`。设置页可改成自建:

```
https://你的域名/            # 必须能被设备访问
http://192.0.2.10:8080/      # 局域网调试(清单里允许了 cleartext)
```

后端仓库的部署方式见它自己的 `Docs/deployment.md`。

## 已知限制

- **其余芯片格式**(`nsf` / `spc` / `sid` / `ahx` / `sap` / `v2m` / adplug 系)没有编进
  native 库,点播时回落到「网页播放器」。已编入的格式见上面的表。
- 歌单只读:后端有 CRUD API,客户端暂未做创建/编辑。
- 专辑页未做:后端当前库 `totalAlbums = 0`,没有真实数据可验。
- 没有登录/账号:后端本身无鉴权。
- 没有后台播放 / MediaSession / 通知栏控制 —— 后续加。
- 没有封面图:后端专辑无 artwork,界面用格式徽标代替。

## 上架

```bash
bash tools/release-apk.sh <version> --app OrzMusic --format both
bash tools/store-preflight.sh <version> --target play
bash tools/store-preflight.sh <version> --target cn
```

人工资料清单见 [`store/play.md`](store/play.md) / [`store/cn.md`](store/cn.md),
完整流程见 [`docs/11-publishing.md`](../../docs/11-publishing.md)。
