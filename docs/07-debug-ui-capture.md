# 07 · 应用自截图:让 FLAG_SECURE 设备也能被"看见"

## 问题

**Pico 4 上用 `adb` 看不到画面。** 它给每个应用建独立虚拟 display,且全部带 `FLAG_SECURE`:

```bash
adb exec-out screencap -p > shot.png     # → 36 KB 的纯白图
adb shell screencap -d 17 -p             # → 0 字节
# scrcpy 同理
```

`uiautomator dump` 也读不到 VR 面板里的 UI 树(只有 1 个节点,而且是 `com.pvr.vrshell` 的)。
于是 Pico 上做 UI 只能靠日志打点 —— 而有视觉模型时,看图远比读日志高效。

> 另有一条同样容易误判的坑:**不戴头显 ~10 秒就会休眠**,应用被 `onPause`,
> 自截图会报「没有处于 resumed 状态的 Activity」。见 [04](04-pico4-notes.md#不戴头显时会在-10-秒后自动休眠)。

## 解法:让应用截自己

`FLAG_SECURE` 只阻止**别的进程**抓屏。应用把**自己的** View 层级画到一张 Bitmap 上,
用的是它自己的 surface,完全不受影响:

```kotlin
val root = activity.window.decorView
val bmp = Bitmap.createBitmap(root.width, root.height, ARGB_8888)
root.draw(Canvas(bmp))          // 软件绘制,不碰系统截屏链路
bmp.compress(PNG, 100, file)
```

再用广播触发、`adb pull` 取走。这样 Pico 就变成**装得快(3 秒)+ 看得见**的迭代设备。

## 模板位置

```
apps/DualDemo/app/src/debug/
├── AndroidManifest.xml                  声明下面两个组件
└── java/com/example/dualdemo/debug/
    ├── DebugHooks.kt                    共享状态(当前 Activity)
    ├── DebugHooksInitProvider.kt        零侵入地跟踪当前 Activity
    └── UiDumpReceiver.kt                收广播 → 截图 → 落盘
```

**把它拷到你的工程里即可。** 三个 `.kt` 放到 `<module>/src/debug/java/<你的包名>/debug/`,
清单里的 `xmlns` 和 `${applicationId}` 占位符照抄,`android:name` 改成你的包名。

> `tools/new-app.sh` 生成的新工程已经自带这套钩子(它以 `DualDemo` 为模板,
> 包名会被自动改写)。

### 为什么需要一个 ContentProvider

截图需要拿到「当前是哪个 Activity」,而业务代码里通常没有全局引用。
常规做法是改 `Application` 或每个 `Activity`,那是侵入式的。

`ContentProvider` 会在 `Application.onCreate` 之后、任何 `Activity` 之前被创建,
借这个时机拿到 `Application` 注册 `ActivityLifecycleCallbacks` 就行 ——
**业务代码一行都不用改**。

## 用法

```bash
# 触发 + 拉回(默认设备取 device.env 里的 PICO_ADDR)
bash tools/ui-dump.sh com.example.dualdemo

# 指定设备 / 输出路径 / 先拉起应用
bash tools/ui-dump.sh com.example.dualdemo "$TV_ADDR" /tmp/tv.png
bash tools/ui-dump.sh com.example.dualdemo --launch
```

脚本做的事:

1. 删掉设备上的旧图(这样"文件出现"就等于本次截图成功)
2. `am broadcast -a <applicationId>.DUMP_UI -p <applicationId>`
3. 轮询等 PNG 落地(最多 10 秒)
4. `adb pull` 回来,并打印分辨率

产物会**在两个位置各写一份**:

```
/data/data/<applicationId>/files/ui-dump.png            ← 主力
/sdcard/Android/data/<applicationId>/files/ui-dump.png  ← Android ≤10 可直接 pull
```

**为什么要写两份:Android 11+ 上 shell 读不了 `/sdcard/Android/data/`**(scoped storage)。
电视(Android 11)上 `adb shell ls /sdcard/Android/data/<pkg>/files/` 直接
`Permission denied`,连 `run-as` 进去看也是拒绝的。所以主力取图方式是:

```bash
adb exec-out run-as <applicationId> cat files/ui-dump.png > out.png
```

`run-as` 对 debuggable(debug 构建)应用可用。`ui-dump.sh` 会自动先试外部目录、
失败再走 `run-as`,你不用管用的是哪条。

截图失败时应用还会往 `/data/data/<applicationId>/files/ui-dump.error`
写一行原因(比如"没有处于 resumed 状态的 Activity"),`ui-dump.sh` 会把它读出来。

手动触发也可以:

```bash
adb shell am broadcast -a com.example.dualdemo.DUMP_UI -p com.example.dualdemo
adb exec-out run-as com.example.dualdemo cat files/ui-dump.png > ui.png
```

## 只在 debug 构建里

钩子全部放在 `src/debug/`,**release 包里不含这些代码,也不含清单声明**。
验证方式:

```bash
./gradlew assembleDebug assembleRelease
aapt2 dump xmltree --file AndroidManifest.xml app/build/outputs/apk/debug/app-debug.apk \
  | grep -c UiDumpReceiver          # → 1
aapt2 dump xmltree --file AndroidManifest.xml app/build/outputs/apk/release/app-release-unsigned.apk \
  | grep -c UiDumpReceiver          # → 0
```

`UiDumpReceiver` 声明为 `exported="true"`(shell 是另一个 uid,必须导出),
因为只在 debug 构建里存在,不会把攻击面带到线上。

## 实测效果

Pico 4,`com.example.dualdemo`:

```
$ bash tools/ui-dump.sh com.example.dualdemo --launch
==> 广播触发自截图
  Broadcast completed: result=0
  /tmp/ui-dump-com_example_dualdemo.png
  1600x900, 102732 bytes
```

> 面板 display 是 1602x902,但 `decorView` 比它小 2px(window frame `[1,1][1601,901]`),
> 所以抓出来是 1600x900。

抓出来的图内容完整 —— 型号、API、ABI、屏幕密度、内存、存储全部可读,
这些是之前 `screencap` / `uiautomator` 一条都拿不到的。

TCL 电视(Android 11)上同样可用,走 `run-as` 取图:

```
==> 自截图
  /tmp/ui-dump-com_example_dualdemo.png
  1920x1080, 125297 bytes
```

`tv-install.sh` 已经把它接上了 —— 装完自动截一张,一次命令同时拿到「装好了」和「长这样」。

## 限制

| 限制 | 说明 |
|---|---|
| **只能抓 View 层级** | `SurfaceView` / `TextureView` / `VideoView` 是独立 surface,不走 `View.draw` 的软件绘制路径,截出来是黑的。**Compose 没问题**(它就是一个 `AndroidComposeView`) |
| **应用必须在前台** | 后台时 View 不再重绘,抓到的是过期画面。**Pico 上还额外要头显不处于休眠**,否则同样报这个错 —— 见 [04](04-pico4-notes.md#不戴头显时会在-10-秒后自动休眠) |
| **多窗口/多 display 只抓当前 resumed 的那个** | 需要抓别的窗口得自己扩展 |
| **需要 debug 构建** | 钩子在 `src/debug/`,release 里没有 |

## 配套的快速迭代循环

把它和 Pico 的 3 秒安装组合起来:

```bash
cd apps/<Name>
./gradlew assembleDebug                                  # 增量构建
adb -s "$PICO_ADDR" install -r app/build/outputs/apk/debug/app-debug.apk   # 3 秒
bash ../../tools/pico-panel.sh <applicationId> awake     # 拉起 + 解除自动休眠(必需)
bash ../../tools/ui-dump.sh <applicationId>              # 1 秒出图
# → 把 PNG 交给支持视觉的模型判断 UI 对不对

# 要看交互(焦点、滑动),再加一步定向注入 + 对比图:
bash ../../tools/pico-panel.sh <applicationId> key KEYCODE_DPAD_DOWN
bash ../../tools/ui-dump.sh <applicationId> /tmp/b.png   # 和上一张比 md5
```

> 第一步的 `awake` 不能省。头显不戴在头上时 ~10 秒就休眠,应用被 `onPause`,
> 自截图会直接报「没有处于 resumed 状态的 Activity」。详见
> [04](04-pico4-notes.md#不戴头显时会在-10-秒后自动休眠)。

对比 TCL 电视那条路(见 [03](03-tcl-tv-sideload.md#安装耗时为什么快不起来)),
一次安装要 60~80 秒。**建议:高频迭代用 Pico + 自截图,电视只在里程碑做验收。**
