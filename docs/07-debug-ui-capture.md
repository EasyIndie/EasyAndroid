# 07 · 应用自截图:让 FLAG_SECURE 设备也能被"看见"

## 问题

**Pico 4 上用 `adb` 看不到画面。** 它给每个应用建独立虚拟 display,且全部带 `FLAG_SECURE`:

```bash
adb exec-out screencap -p > shot.png     # → 36 KB 的纯白图
adb shell screencap -d 17 -p             # → 0 字节
# scrcpy 同理
```

`uiautomator dump` 也读不到 VR 面板里的 UI 树(只有 1 个节点)。
于是 Pico 上做 UI 只能靠日志打点 —— 而有视觉模型时,看图远比读日志高效。

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

产物在设备上的位置:

```
/sdcard/Android/data/<applicationId>/files/ui-dump.png
```

手动触发也可以:

```bash
adb shell am broadcast -a com.example.dualdemo.DUMP_UI -p com.example.dualdemo
adb pull /sdcard/Android/data/com.example.dualdemo/files/ui-dump.png
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
  1602x900, 102732 bytes
```

抓出来的图内容完整 —— 型号、API、ABI、屏幕密度、内存、存储全部可读,
这些是之前 `screencap` / `uiautomator` 一条都拿不到的。

## 限制

| 限制 | 说明 |
|---|---|
| **只能抓 View 层级** | `SurfaceView` / `TextureView` / `VideoView` 是独立 surface,不走 `View.draw` 的软件绘制路径,截出来是黑的。**Compose 没问题**(它就是一个 `AndroidComposeView`) |
| **应用必须在前台** | 后台时 View 不再重绘,抓到的是过期画面 |
| **多窗口/多 display 只抓当前 resumed 的那个** | 需要抓别的窗口得自己扩展 |
| **需要 debug 构建** | 钩子在 `src/debug/`,release 里没有 |

## 配套的快速迭代循环

把它和 Pico 的 3 秒安装组合起来:

```bash
cd apps/<Name>
./gradlew assembleDebug                                  # 增量构建
adb -s "$PICO_ADDR" install -r app/build/outputs/apk/debug/app-debug.apk   # 3 秒
bash ../../tools/ui-dump.sh <applicationId> --launch     # 截图
# → 把 PNG 交给支持视觉的模型判断 UI 对不对
```

对比 TCL 电视那条路(见 [03](03-tcl-tv-sideload.md#安装耗时为什么快不起来)),
一次安装要 60~80 秒。**建议:高频迭代用 Pico + 自截图,电视只在里程碑做验收。**
