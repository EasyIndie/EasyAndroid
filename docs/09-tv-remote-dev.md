# 把电视当远程开发终端:三套方案

在 TCL 电视(Android 11 / **无 Google Play** / 只有遥控)上远程连到开发机干活。
三套方案**都已在本仓库的实机上跑通**,互相补充:

| | **方案 A:自建 PWA** | **方案 B:Termux + SSH** | **方案 C:herdr WebUI + 隧道** |
|---|---|---|---|
| 跑什么 | [ColliePWA](https://colliepwa.dev)(herdr 的手机客户端) | Termux 里的 `ssh` + `tmux`/herdr 的 TUI | [herdr-web-ui](https://github.com/devswha/herdr-web-ui)(官方生态的浏览器客户端) |
| 电视上装什么 | **TV Bro**(带 GeckoView 的构建) | **Termux** + `openssh` + `tmux` | 复用已有的 **TV Bro + Termux**(Termux 只用来起隧道) |
| 开发机上要什么 | 起一个 Collie 实例(自建 Web 应用) | **什么都不用装**(只要有 sshd) | herdr ≥0.9 + Bun + 源码版 herdr-web-ui |
| 打字 | 网页输入框 → 搜狗 TV 输入法 | 终端 → 搜狗 TV 输入法(软键盘**实测可用**) | 网页输入框 / 终端(xterm.js) |
| **实体键盘打中文** | 未实测 | ❌ **不行**(Termux 上游 bug [#5290](https://github.com/termux/termux-app/issues/5290)) | ✅ **实测通过** |
| 屏幕利用 | 卡片/按钮式 UI,**为遥控优化** | 真终端,TUI 原样渲染 —— 信息密度高 | 工作区 + 聊天卡片 + 真终端,**信息密度最高** |
| 装一次耗时 | ~90 s(143 MB 包) | ~330 s(32 MB 包 + apt) | 开发机上 ~5 分钟 + 电视侧 **0** |
| 适合 | "看哪个 agent 在等我、回一句话" | "真的要敲命令、看日志、改代码" | **长期主力**(尤其要打中文时) |

> **建议:A 和 C 都装,B 视需要。**
> A 用来快速瞥一眼 + 回话(遥控友好);C 用来长期干活(中文输入 + 字号/滚动都好);
> B 是"开发机上什么都不能装"时的兜底 —— 但**它打不了中文**,见下面的死结。
> 它们共用同一套安装通道、输入法和验收手段,见「对齐体验」。

---

## 共同前提

### 电视的能力(选方案前先对一遍)

| 能力 | 值 | 影响 |
|---|---|---|
| ABI | `armeabi-v7a, armeabi` —— **`abilist64` 为空** | **只能装 32 位 APK**,arm64-only 的直接装不上 |
| Android | 11 / API 30,`user` 构建 | 无 root;`targetSdk 28` 的老应用也能装 |
| Google Play / GMS | **没有** | 一切靠侧载,别考虑 Play |
| `android.software.leanback_only` | 是 | 没有 `LEANBACK_LAUNCHER` 的**不会出现在 TV 桌面**(但能用 `am start` 拉起) |
| 输入法 | `com.sohu.inputmethod.sogou.tv`(搜狗 TV 输入法) | 遥控 D-pad 就能打字,应用走标准 `InputConnection` 就吃得到 |
| 遥控 | `gIrTouch_Mouse`,`SOURCE_MOUSE\|SOURCE_TOUCHPAD\|SOURCE_POINTER` | 带**指针**能力,标准控件可以 tap |
| 触摸屏 | 没有 | TCL 自有界面不把 touch 当 click |
| 外设 | `android.hardware.usb.host` ✅、蓝牙 ON ✅ | 见下面「键盘 / 鼠标」 |

### 键盘 / 鼠标:接哪种、接哪个口

实测过三种输入设备(2026-09-18)。**结论:长期用选蓝牙。**

#### USB:能用,但有两个坑

**坑 ①:不是每个 USB 口都是主机口。** 实测把 2.4G 接收器插在
U 盘那个口上 → 立刻枚举成功;插在另一个口上 →
`dumpsys usb` 的 host_manager 里**一个设备都没多**。

怎么判断当前用的是不是主机口(不需要 root):

```bash
adb -s "$TV_ADDR" shell "dumpsys usb" | grep -A40 host_manager
# 主机口:会列出 name=/dev/bus/usb/... + 厂商/产品名
# 非主机口:列表里什么都没有
```

判据不是 `/sys/bus/usb/devices/`(**shell 读不了,是 Permission denied,
不是空**;别把它当成"没有设备"),也不是 `dumpsys usb` 的
`device_manager.connected`(那是**设备模式** = 电视当从设备接电脑,和主机模式无关)。

**坑 ②:2.4G 接收器距离短。** 实测离开一两米就不工作 —— 电视场景下基本不好用。
而且那个主机口就是 U 盘侧载要用的口,两个设备互斥(要 Hub,而且电视的 USB 口
供电常常带不动 Hub + U 盘,得用**带供电的** Hub)。

驱动侧完全具备,不是"声称支持但没实现":

```
/sys/bus/usb/drivers/ 里有: usbhid(U 键盘/鼠标) hub(U 扩展坞) xpad(Xbox 手柄)
```

`xpad` 在,说明厂商确实考虑过 "USB 输入类外设" 这个场景。

#### 蓝牙:推荐

**已被证明可用** —— 蓝牙键盘(K380)和蓝牙鼠标(M585/M590)接上就直接出输入设备。

```
Profile: HidHostService                                 ← 蓝牙 HID 主机功能在
HID_HOST=100                                            ← 已配对设备被当作 HID 接纳
feature:android.hardware.bluetooth_le                    ← BLE 鼠标也支持
```

配对:电视 `设置 → 蓝牙 → 添加设备`,鼠标先进配对模式。

#### 怎么确认「接上了」(三层证据,都不需要 root)

```bash
# ① 内核认到设备了吗 —— 看设备名和能力
adb -s "$TV_ADDR" shell "getevent -pl" | grep -E 'add device|name:'
#    鼠标的特征:REL_X / REL_Y / WHEEL + BTN_LEFT/RIGHT/MIDDLE

# ② framework 认成鼠标了吗 —— 看 Sources 和 Cursor Input Mapper
adb -s "$TV_ADDR" shell "dumpsys input" | grep -A24 'Device [0-9]*: <设备名>'
#    ★ Sources 里要含 0x00002000(SOURCE_MOUSE)
#    ★ 而且应该有 `Cursor Input Mapper:` 这一段 —— 只有鼠标才会有

# ③ ★★ 最硬的一条:SurfaceFlinger 里真的有一个「光标图层」
adb -s "$TV_ADDR" shell "dumpsys SurfaceFlinger" | grep -A14 'Sprite#0' \
  | grep -E 'type=CURSOR|geomLayerBounds|alpha='
#   要看到 `composition type=CURSOR` —— 这是 SurfaceFlinger 的光标层,做不了假
```

#### ⚠️ 为什么「截图看光标」不可靠(重要)

**Android 的光标会在静止几秒后自动淡出**,淡到几乎全透明。实测:

```
* Layer 0xf2ce5000 (Sprite#0)
      composition type=CURSOR (4)        ← 光标层确实在
      geomLayerBounds=[0 0 33 42]        ← 33x42 的箭头
      transform: (81.29, 775.49)         ← 当前坐标
      alpha=0.017197                     ← 但只有 1.7% 不透明 = 已淡出
```

所以**静止时截图里根本看不见光标**,而你会误判成「鼠标没生效」。
`alpha` 会在鼠标移动时回到 1.0,停一会儿又掉回 ~0.02 —— 我连采 5 次
`screencap` + 反复读这个图层,只要没人碰鼠标,`alpha` 就一直是 0.017197。

**判据要选不依赖「画面上看得见」的那一条**:`composition type=CURSOR` 在,
就说明光标系统在跑、鼠标被当作指针设备。**让用户自己看屏幕比截图可靠。**

#### 实测结果(两轮)

| 设备 | 结果 |
|---|---|
| **罗技 2.4G(B330/M330/M3)** | ①②③ 全过。`Sources: 0x01002313` 含 `0x2000`;有 `Cursor Input Mapper`;光标层 `type=CURSOR` 在 (81,775)。**但接收距离短,一两米就失效** |
| **罗技蓝牙(M585/M590)** | ①②③ 全过,`UniqueId: d2:be:b4:bd:58:0c`,`bus=0x0005`(= 蓝牙总线),`Sources: 0x00002303` 含 `0x2000`,有 `Cursor Input Mapper`。**推荐** |

> 换一个口/换一种连接方式,**要重新跑一遍 ①②③** —— 我这次就是靠
> 「host_manager 里一个设备都没多」才发现另一个 USB 口不是主机口。

> ⚠️ **不能靠 `sendevent` 代你动鼠标来验。** 鼠标的 event 节点是
> `crw-rw---- root input`,而 Android 11 的 SELinux 不允许 shell 写输入设备
> (`sendevent: Permission denied`)——shell 虽然在 `input` 组里也没用。
> 这一步必须物理动一下鼠标。

> 另一个容易搞混的:系统里原本就有一个鼠标类设备 `gIrTouch_Mouse`
> (`REL_X/REL_Y/WHEEL` + `SOURCE_MOUSE|TOUCHPAD|POINTER`),那是**遥控的红外指针**。
> 所以"电视上有鼠标类设备"不等于"插的鼠标被认了",要看**设备名**。

### 装法:只有一条路

`adb install` 被固件硬拦(`OverseasAppConfig`,AOSP 的 verifier 开关无效),
唯一通道是 **U 盘 + TGuard 图形安装器**,也就是 `tools/tv-install.sh`。
细节见 [03-tcl-tv-sideload.md](03-tcl-tv-sideload.md)。

```bash
bash tools/tv-install.sh <apk>          # 约 90 s;U 盘越干净越快
```

> 💡 **用蓝牙键鼠的另一个好处:U 盘那个主机口就空出来了。** 如果用 2.4G 接收器,
> 它和 U 盘抢**同一个**主机口 —— 装应用时得把鼠标拔下来。蓝牙不占口。

> ⚠️ 安装器扫的是**整个可移动卷、而且是递归的** —— 把 APK 挪到二级目录
> 或 `AndroidTV/` 外面都躲不掉(实测两面都验过)。唯一有效的是**不让名字以 `.apk` 结尾**:
> 用不到的改成 `xxx.apk.disabled`,它们就不再被当成安装源。
> 细节和「僵尸条目」那个坑见 [03](03-tcl-tv-sideload.md#u-盘卫生两件真正会咬人的事)。

---

## 方案 A:TV Bro + GeckoView → 自建 PWA

### 为什么不能用自带浏览器

| 项 | 值 |
|---|---|
| `com.tcl.browser` | 3.0.880,连 CSS 都不解析(整页裸 HTML) |
| `com.quark.yun.tv` | 夸克**网盘** App 顺带的浏览器,要扫码登录 |
| 系统 WebView | **`com.android.webview` 83.0.4103.120 = Chromium 83(2020-06)** |

Chromium 83 遇到 Tailwind v4 产出的 `@layer`(需要 **Chrome 99**)会**以整块为单位丢弃**
—— 而 Tailwind v4 把所有样式都包在 `@layer` 里,于是**一个字节的样式都不生效**。
症状是「裸 HTML + 卡在 Loading…」,非常容易被误判成网站坏了/网络不通。

### 步骤

**1. 装带 Gecko 的 TV Bro 构建**(普通构建不含新引擎)

| 构建 | 大小 | 引擎 |
|---|---|---|
| `tvbro-<ver>-generic-geckoExcluded.apk` | 6.8 MB | 只有系统 WebView |
| `tvbro-<ver>-generic-geckoIncluded-armeabi-v7a.apk` | 142.9 MB | **自带 GeckoView** |

```bash
bash tools/tv-install.sh tvbro-2.1.6-generic-geckoIncluded-armeabi-v7a.apk
```

**2. ⚠️ 把引擎切成 GeckoView —— 最容易漏的一步**

TV Bro **装了 Gecko 也默认用 WebView**。

```
打开任意网页 → 按 BACK 呼出工具栏 → 点最右的「设置」
  → 浏览器引擎 = WebView          ← 默认值
  → 点它 → 选 GeckoView
  → 「…加载速度比 WebView 稍慢。你想继续吗?」→ OK
  → 「需要重启应用 / 重新启动应用以应用此更改」→ 退出
```

**3. 打开你的 Collie 实例**

```
TV Bro 打开  http://<开发机>:<端口>/          或经 Tailscale 的地址
```

### 怎么判断当下用的是哪个引擎(最省时间的分叉点)

**看错误页的措辞。** Chromium 报 `net::ERR_ACCESS_DENIED` / `net::ERR_EMPTY_RESPONSE`
这类 `net::ERR_*`;**Gecko 不用这套命名**。看到 `net::ERR_*` 就说明还在用 WebView。

### 实测证据

电视上打开 `https://colliepwa.dev/demo`,GeckoView 引擎下完整渲染:

```
Collie shows the agents in your terminal.
6 panes, 1 needs you          This device can type
WHAT YOU CAN DO HERE
  Read the live pane, colour and all. / Answer a prompt by tapping its card.
  Type a reply, or send Esc, Tab and Ctrl keys.
[Open the pane that needs you]                     1.21.3  Demo — dummy data
```

引擎里 `libxul.so` 的 UA 版本是 **Firefox/147.0**。

---

## 方案 B:Termux + SSH → 终端复用器 TUI

[herdr](https://herdr.dev) 是跑在开发机上的终端复用器/agent 编排器(TUI)。
客户端只要有 **ssh + 终端** 就行。

### 步骤

```bash
# 1. 装 Termux(必须 arm 32 位那份)
bash tools/tv-install.sh termux-app_v0.118.3+github-debug_armeabi-v7a.apk
```

APK 自带 bootstrap(`lib/armeabi-v7a/libtermux-bootstrap.so`,26.5 MB),
**首次启动不需要联网**。

```bash
# 2. 在电视上打开 Termux,然后(可以照抄,也可以走 run-as 自动化)
pkg install -y openssh tmux

# 3. ssh 到开发机,attach 到 herdr / tmux
ssh -t <开发机> 'herdr attach'        # 或 tmux new -A -s work
```

> Termux 的 apt 源 `packages-cf.termux.dev` **在国内可达**(实测 62 kB/s),
> 装 openssh + tmux 大约 15 分钟(网络慢,一次性)。

### 在电视上怎么打字

**三条路,按推荐顺序:**

1. **电视的搜狗 TV 输入法直接能打进 Termux** —— 实测可行。
   Termux 走标准 `InputConnection`,所以遥控 D-pad 在搜狗键盘上选字母就行。
   慢,但能用。
2. **Termux 的「跨屏输入」** —— 键盘左侧有个「点击后扫码 · 手机输入更方便」,
   用手机扫码变键盘。**日常最舒服的一条。**
3. **USB / 蓝牙键盘** —— 电视有 `android.hardware.usb.host`,蓝牙也是开的。
   真要长时间敲命令,这是唯一不难受的选择。

Termux 自带的**功能键行**(`ESC / CTRL / ALT / ←↓→ / HOME / END / PGUP / PGDN`)
正好补上遥控没有的键 —— 配合第 2 条很好用。

### 终端字号:能改 —— 但有两条不能踩的坑

电视上默认字号很小(1920×1080、240dpi 下 `stty size` = 43×173)。Termux 支持改,
**三条路,只有在电视上能用的那条最省事**:

#### ① 键盘快捷键(推荐)—— `Ctrl + Alt + +` / `Ctrl + Alt + -`

源码(`TermuxTerminalViewClient.onKeyDown`)里写得很清楚:

```java
} else if (!...areHardwareKeyboardShortcutsDisabled() &&
    e.isCtrlPressed() && e.isAltPressed()) {
    int unicodeChar = e.getUnicodeChar(0);
    ...
    } else if (unicodeChar == '+' || e.getUnicodeChar(KeyEvent.META_SHIFT_ON) == '+') {
        changeFontSize(true);      // 放大
    } else if (unicodeChar == '-') {
        changeFontSize(false);     // 缩小
    }
```

**步进 2、实时生效、自动持久。** 有硬件键盘(USB / 蓝牙)就能用 —— 这也是
电视上唯一顺手的方式。同一段里还有 `Ctrl+Alt+` 加别的键:`k` 开关软键盘、
`m` 菜单、`r` 重命名会话、`c` 新会话、`v` 粘贴、`1`~`9` 切会话。

#### ② 两指捏合 —— 电视用不了

`onScale()` 里判断缩放系数 → `changeFontSize()`。**但这台电视没有触摸屏**,
鼠标也做不了捏合。

#### ③ 直接改偏好 —— ⚠️ 必须存成 `<string>`,不是 `<int>`

**这是最容易白费半小时的坑。** 源码里是:

```java
int fontSize = SharedPreferenceUtils.getIntStoredAsString(
        mSharedPreferences, TERMUX_APP.KEY_FONTSIZE, DEFAULT_FONTSIZE);
```

名字叫 `getIntStoredAsString` —— **值是以字符串形式存的**。写成 `<int>` 会被
完全忽略,而且**一点报错都没有**,表现就是「改了没用」:

```xml
<!-- ✗ 无效,静默忽略 -->
<int name="fontsize" value="40" />
<!-- ✓ 正确 -->
<string name="fontsize">40</string>
```

实测(量文字行距,同一段欢迎横幅):

| 写法 | 文字行数 | 平均行距 | 文字块总高 |
|---|---|---|---|
| 不写(默认) | 18 | 27.26 px | 464 px |
| `<int name="fontsize" value="40"/>` | 18 | 27.26 px | 464 px |
| `<string name="fontsize">40</string>` | 10 | 68.39 px | 616 px |

`fontsize` 的可用范围由 `MIN_FONTSIZE`/`MAX_FONTSIZE` 夹住(从资源读),
`changeFontSize()` 每次步进 2。**默认大约 20**(默认行距 27.26px ≈ fontsize 20)。

在电视上直接写(需要 `run-as`,Termux 的 GitHub 构建是 debuggable):

```bash
D=/data/data/com.termux
# 停应用 → 改 → 起应用(不停应用会被它回写覆盖)
adb -s "$TV_ADDR" shell "am force-stop com.termux"
adb -s "$TV_ADDR" shell "run-as com.termux sed -i \
  's#<int name=\"fontsize\" value=\"[0-9]*\" />#<string name=\"fontsize\">24</string>#' \
  $D/shared_prefs/com.termux_preferences.xml"
adb -s "$TV_ADDR" shell "am start -n com.termux/com.termux.app.TermuxActivity"
```

> 更简单:先按一次 `Ctrl+Alt++` 让 Termux **自己把 `<string>` 那条写进去**,
> 之后再用 sed 改数字就不会踩格式的坑了。

#### 走不通的(别再试)

| 尝试 | 结果 |
|---|---|
| `~/.termux/termux.properties` 里的字号 | ❌ 支持的键里**没有**字号(只有 `font-family` / `font-woff2`) |
| `settings put system font_scale 1.5` | ❌ 行距与文字块高度**完全不变**(只有功能键行的字变大 —— 这点骗到过我) |
| 界面菜单 | ❌ 没有(它不进菜单,只走快捷键和捏合) |

#### 最后手段:`wm density`(有效,但**整机生效**)

```bash
adb -s "$TV_ADDR" shell "wm density 320"     # 240 → 320
adb -s "$TV_ADDR" shell "wm density reset"   # 还原
```

实测行距 27.26 → 33.89 px,`reset` 后精确回到 27.26 px;写在
`settings secure display_density_forced` 里,**重启不丢**。
代价是**整个电视 UI 都变大**(TCL 桌面也一样)—— 只想改终端就不要用这个。

> ❗ **别靠肉眼判字号变化。** 本机没有 PIL/numpy,而截图内容是会变的 ——
> 我先后被「功能键行的字变大」和「前后画面内容不同」各骗了一次。
> 可靠做法是**先控住内容**(删掉 `current_session` 逼出固定内容的欢迎横幅)
> 再量文字行距:用 [`tools/png-rowpitch.py`](../tools/README.md)
> —— `python3 tools/png-rowpitch.py 截图.png 0 700` 会给出
> **文字行数 / 平均行距 / 文字块总高** 三个数,一样就是没变,不用猜。
> (它自带 `--selftest`,已接进 `verify-all.sh`。)

### 实测证据

```
apt update  : Get https://packages-cf.termux.dev/...  Fetched 572 kB in 9s
openssh     : OpenSSH_10.6p1, OpenSSL 3.4.1
tmux        : tmux 3.8
ssh 客户端   : CLIENT-SSH-OK / 远端看到: localhost armv8l
ssh + tmux  : demo: 1 windows (created ...)        ← 就是 herdr 的用法
跨机 sshd    : 从 WSL 连电视的 8022 → TV-SSH-OK / uid=10092(u0_a92)
屏幕上的 TUI : [demo] 0:sleep*   "localhost" 22:12 16-Oct-2026   ← 1920x1080 正常渲染
```

---

## 方案 C:herdr 的 WebUI + SSH 隧道(**要打中文就用这个**)

方案 A 的短板是"Collie 要自建实例";方案 B 的死结是 **Termux 里实体键盘打不了中文**。
方案 C 用 herdr 生态里现成的 **herdr-web-ui**(浏览器客户端),把这两件事一起解决:

```
[电视]   TV Bro (GeckoView) → http://127.0.0.1:7317
                                 ↑  SSH 隧道(Termux 里起)
[开发机]                       herdr-web-ui(只绑 127.0.0.1)
                                 ↓
                               herdr server(同一批 pane,TUI 仍可 attach)
```

### 为什么是它(三个硬理由)

1. **中文输入真的能用** —— 实测 `ni'hao` → 候选「你好」→ 上屏 → 回车发送。
   方案 B 的死结是 Termux 把硬件键直接喂 PTY(上游 bug 仍 open),不是电视的问题。
2. **电视上不用装新东西** —— 复用已有的 TV Bro + Termux(Termux 只用来起隧道)。
3. **顺手解决字号/滚动/选中** —— 浏览器缩放一键搞定,不用 `wm density` 去动整机。

### 步骤 1. 开发机上起服务

先跑这组**只读**体检:

```bash
uname -m                 # 需要 x86_64 或 aarch64；armv7l 官方没有构建
bun --version            # 需要 ≥1.4(没有就先装：curl -fsSL https://bun.sh/install | bash)
node --version           # 需要 ≥18(终端 attach 的 sidecar 用)
herdr --version          # 需要 ≥0.9.0
herdr status server      # 需要 running
git --version
```

> ⚠️ **别用 `herdr plugin install`,除非 herdr 是用完整 PATH 启动的。**
> 实测坑:herdr server 从 GUI 终端(Ghostty)启动时,PATH 是
> `/usr/bin:/bin:/usr/sbin:/sbin:/Applications/Ghostty.app/Contents/MacOS` ——
> **`~/.local/bin`(herdr 自己)、`~/.bun/bin`、`~/.n/bin` 全都不在**。
> 插件的 build 步骤用的是 **herdr 自己的环境** ⇒ 必然报 `bun not found`,
> 而官方 INSTALL.md 又明确"不要重启用户的 herdr server"。

所以走源码安装(官方 INSTALL.md 的方法 3B),它只依赖你**当前 shell** 的 PATH:

```bash
git clone https://github.com/devswha/herdr-web-ui.git ~/herdr-web-ui
cd ~/herdr-web-ui && bun install

# 起服务：只绑 127.0.0.1，且把 herdr 和 node 放进 PATH
export PATH="$HOME/.local/bin:$HOME/.n/bin:$HOME/.bun/bin:$PATH"
export HERDR_WEB_HERDR_BIN="$HOME/.local/bin/herdr"
HOST=127.0.0.1 PORT=7317 bun run start
```

自检(必须看到 `"ok":true`):

```bash
curl -s http://127.0.0.1:7317/api/health
# {"ok":true,"herdr":{"version":"0.9.3",...,"terminal_attach":true},
#  "auth":{"required":false,"authenticated":true,"via":"local","role":"drive"},...}
```

> **`via":"local"` 是隧道路线的关键** —— 隧道进来的连接会被服务端当成"本机",
> 所以**不需要配对码、不需要 token**,局域网也完全不暴露。
> 反过来如果选 `HOST=0.0.0.0`:必须配 `HERDR_WEB_TOKEN`,而**明文 http 上的
> token 会被同网段任何人嗅到**(官方明说)。这就是隧道优于直连的理由。

### 步骤 2. 电视上建隧道

```bash
# 生成专用密钥(一次)
mkdir -p ~/.ssh && chmod 700 ~/.ssh
ssh-keygen -t ed25519 -N "" -C "tv-termux@tcl" -f ~/.ssh/id_ed25519
cat ~/.ssh/id_ed25519.pub        # 把这行加到开发机的 ~/.ssh/authorized_keys

# 起隧道
termux-wake-lock
setsid nohup ssh -N -L 7317:127.0.0.1:7317 \
  -o BatchMode=yes -o StrictHostKeyChecking=accept-new \
  -o ExitOnForwardFailure=yes -o ServerAliveInterval=20 \
  -i ~/.ssh/id_ed25519 bot@192.0.2.35 > ~/.ssh/tunnel.log 2>&1 &
```

然后 TV Bro 打开 `http://127.0.0.1:7317`。

### 步骤 3. 让它开机/开 Termux 就在

**开发机(macOS 用 launchd,Linux 用 `systemctl --user`)**:

两个用户级单元(或合并成一个启动器脚本):

- `dev.herdr.server` —— 跑 `herdr server`。启动器先探 `herdr status server`,
  **已在跑就 `exit 0`**;配合 `KeepAlive { SuccessfulExit: false }`,
  这样**不需要立刻重启用户正在跑的 herdr**,下次登录/重启才接管。
  ⚠️ **要给 daemon 套一个 PTY**:`exec script -q /dev/null herdr server`。
  直接用 launchd 跑 `herdr server` 时,它自报的能力里**没有 `direct_terminal_attach`**
  (且 `detached_server_daemon:false`)⇒ web ui 只能降级到 mirror 模式。
  套上 `script` 后两个都恢复(见下面实测评据)。
- `dev.herdr.webui` —— 等 herdr 就绪后跑 `bun run server/managed.ts`。
  ⚠️ 它的**能力探测是启动时只算一次**(`sidecarAvailable()` 有缓存),
  所以改完 herdr 那边必须**重启 web ui**才能看到 `terminal_attach:true`。

两个单元的环境里 **`PATH` 必须写全**(`~/.local/bin` + `~/.bun/bin` + `~/.n/bin`),
原因见上面那个坑。

**电视(Termux)** —— 用**守护脚本**,而不是一次性 ssh

一次性 `ssh -N -L` **不会自己重连**:开发机一重启,隧道就静默死掉(实测)。
`~/.termux/herdr-tunnel.sh`:

```sh
#!/data/data/com.termux/files/usr/bin/sh
H=/data/data/com.termux/files/home
PREFIX=/data/data/com.termux/files/usr
PATH=$PREFIX/bin:$PATH; export PATH
PIDFILE=$H/.ssh/herdr-tunnel.pid
# 单实例 —— Android 的 ps -A 只显示进程名、不显示完整命令行,
# 所以不能用 `ps -A | grep herdr-tunnel` 判重,必须用 pidfile + kill -0
if [ -f "$PIDFILE" ]; then
  old=$(cat "$PIDFILE" 2>/dev/null)
  [ -n "$old" ] && kill -0 "$old" 2>/dev/null && { echo "已在运行 ($old)"; exit 0; }
fi
echo $$ > "$PIDFILE"; trap 'rm -f "$PIDFILE"' EXIT INT TERM
"$PREFIX/bin/termux-wake-lock" 2>/dev/null
while :; do
  ssh -N -L 7317:127.0.0.1:7317 \
    -o BatchMode=yes -o StrictHostKeyChecking=accept-new \
    -o ExitOnForwardFailure=yes \
    -o ServerAliveInterval=15 -o ServerAliveCountMax=3 -o ConnectTimeout=10 \
    -i "$H/.ssh/id_ed25519" bot@192.0.2.35
  echo "[$(date '+%F %T')] ssh 退出 rc=$?，5 秒后重连" >> "$H/.ssh/tunnel.log"
  sleep 5
done
```

拉起它的一处或两处:

- `~/.bashrc` —— **不需要 Termux:Boot**,打开 Termux 就起(同样用 pidfile 判重)。
  记得 `~/.bash_profile` 里加 `. ~/.bashrc`,
  否则 **login shell 不会加载 .bashrc**(实测这台 Termux 没有 .bash_profile)。
- `~/.termux/boot/10-herdr-tunnel.sh` —— `ping` 等网络后 `exec` 同一个守护脚本。
  **需要装 [`Termux:Boot`](https://f-droid.org/packages/com.termux.boot/) 并启动一次**才生效
  (纯 Java 包,**不受 32 位限制**)。

### ⚠️ 实测踩到的坑

| 坑 | 现象 | 真因 / 修法 |
|---|---|---|
| **插件装不上** | `bun not found` | herdr server 的 PATH 里没有 bun。走源码安装,或先把 herdr 改成带完整 PATH 的 launchd/systemd 启动 |
| **终端报「服务器无法启动 herdr」** | 聊天能看、终端连不上 | 起服务时 PATH 少了 `~/.local/bin`。补上,或设 `HERDR_WEB_HERDR_BIN` |
| **隧道"起不来"** | 反复 `Address already in use` | ①`ps -A` 在 Android 上**不显示 ssh 的完整命令行**(只显示 `ssh`),据此判断会误判;②`pkill -f "ssh -N -L"` **匹配不到 `ssh -v -N -L`**(中间多一个 `-v`)。清场用 `pkill -9 -f ssh` |
| **密钥在但 `Permission denied`** | 隧道秒退 | 密钥被写到了 `/data/data/com.termux/.ssh/` 而不是 `files/home/.ssh/` —— 见下面 $HOME 那个坑 |
| **开发机重启后隧道不恢复** | 电视上页面打不开,`ssh` 进程数 0 | 一次性 `ssh -N -L` **不会自己重连**。改成守护循环(见步骤 3),配 `ServerAliveInterval=15 / ServerAliveCountMax=3` |
| **`ps -A \| grep` 判重永远匹配不到** | 每开一次 Termux 就多一个守护 | Android 的 `ps -A` **只显示进程名**,不显示完整命令行。用 **pidfile + `kill -0`** |
| **`pkill -f ssh` 会把自己杀掉** | 命令只打一行 `Killed`,后面全不执行 | `pkill -f` 匹配**整条命令行**,而 `sh -c '...pkill -f ssh...'` 自己就含 `ssh`。用 `[s]sh` 括号技巧,或按 pidfile 精确 `kill` |
| **launchd 起的 herdr 丢能力** | `terminal_attach:false`,终端降级成 mirror | launchd 起的 `herdr server` **不报 `direct_terminal_attach`**(也没 `detached_server_daemon`)。启动器改成 `exec script -q /dev/null herdr server` 套 PTY 就恢复 |
| **改完 herdr 那边没生效** | 仍是 `terminal_attach:false` | web ui 的能力探测**启动时只算一次**。重启 **web ui**(不是 herdr server)就会重新探测 |

### 电视上跑命令的三个 bash 限制(写脚本必先知道)

在 `run-as com.termux` 下:

1. **heredoc 会失败** —— `can't create temporary file /data/local/xxx.tmp: Permission denied`
   (它要往 `/data/local/` 写临时文件)。改成**主机侧 base64 后内联**:
   ```bash
   B=$(base64 -w0 file)
   adb shell "run-as com.termux sh -c 'export PATH=/data/data/com.termux/files/usr/bin:\$PATH; printf %s $B | base64 -d > files/home/xxx'"
   ```
   `PATH` 必须显式给,否则 `base64`/`mkdir` 这些外部程序找不到,**管道会静默失败**。
2. **`$HOME` 是 `/data/user/0/com.termux`,不是 Termux 的家目录 `files/home/`。**
   用 `$HOME` 拼路径会把密钥/配置写到错误位置(实测把密钥写到了
   `/data/data/com.termux/.ssh/`,导致后来隧道一直 `Permission denied`)。
   **一律用绝对路径**,或显式 `HOME=/data/data/com.termux/files/home`。
3. **`adb shell` 不转发 stdin 到 `run-as`** —— `adb shell 'run-as ...' < file` 拿不到内容。
4. **每条 `adb shell` 都要 `</dev/null`** —— 非交互环境下 adb 会占住 stdin,
   **把脚本后续命令的输入流吃掉**(现象很误导:第一条命令有输出,后面全部静默无输出)。
   这个坑仓库 AGENTS.md §6 早就记了,但这里还是踩了一次。

### 实测证据

```
机器        : x86_64 / macOS 13.7.8(Ventura) · herdr 0.9.3 running · node v24.18.0 · bun 1.4.3
健康检查    : {"ok":true,"herdr":{"terminal_attach":true},"auth":{"via":"local","role":"drive"}}
渲染        : TV Bro(GeckoView)→ 「EasyXAgentOPS · herdr」「OrzMC · /Users/bot/OrzMC」
终端 attach : 修好 PATH 后终端格不再报错,接上 pi 代理
中文输入    : 实体键盘 nihao → ni'hao → 候选「你好 你号 泥嚎 拟好 倪好」→ 上屏 → 回车发送 ✅
持久化      : launchd 两单元(herdr server 已在跑时自动跳过,不动用户的 3 个 pane)+ Termux 守护脚本
```

### 重启后的复验(实测)

```
开发机 reboot 后 2 分钟:
  launchctl  : 491 dev.herdr.server / 495 dev.herdr.webui   ← 两个都在运行
  herdr server: pid 491, PPID=1 ← 由 launchd 起,已脱离终端
  它的 PATH  : ~/.local/bin:~/.bun/bin:~/.n/bin:...        ← 完整(这就是为什么要写全)
  health     : {"ok":true,...}

电视侧:
  一次性 ssh  → bot 重启后进程数变 0,页面打不开(不重连)← 这就是加守护脚本的原因
  守护脚本后 → 杀 ssh 子进程,12 秒内自动重连并发新页 ✅
  终端里中文  → ni'hao → 候选「你好」→ 上屏(重启后依然成立)
```

把 herdr 交给 launchd 后补上的一步(实测):

```
直接 launchd 跑    : capabilities 里无 direct_terminal_attach · detached_server_daemon=false
                     → health {"terminal_attach":false} ⇒ web ui 降级 mirror 模式
套 script PTY 后  : detached_server_daemon=true
重启 web ui 后    : health {"terminal_attach":true} ✅
                     终端提示符也从 bot@localhost 变成 bot@bot(真 PTY 的证据)
```

> ⚠️ **重启会丢掉 herdr 的所有 pane** —— 这是重启本身的后果,不是持久化方案的问题。
> 想要"重启也保留工作区",那要另外做(把 herdr 的 session 落盘/恢复),不在本文范围。

### 和"PC 一样"到什么程度

- **单按 `Shift` 切中英** ✅(IME 层行为,全平台一致)
- **回车**:候选栏还在时第一次回车是「上屏」,第二次才是发送 ——
  这是**标准 IME 语义,PC 上一样**。正常习惯是 `空格/数字选词 → 回车发送`。
  (Termux 里这个感觉更糟:它的"发送"绑在 `imeOptions=actionSend` 上,
  第一次回车会把**英文原码**上屏,看起来就像"没发出去"。)
- **切输入法**(多个 IME 之间):**Android 没有这个快捷键** ——
  `Ctrl+Space` 在 `PhoneWindowManager` 里就被吃掉了,用来切的是**物理键盘布局**。
  要的话得上 `Key Mapper` 这类按键映射应用。

---

## herdr 的操作方式(接上之后怎么用)

### 最重要的一条:Herdr 是**鼠标原生**的

官方 Keyboard 指南第一句:

> Herdr is mouse-native. You can click panes, tabs, workspaces, and agents,
> drag split borders, and use right-click menus **without learning a single
> keybinding. Keyboard control is optional.**

所以**电视上有鼠标就已经能用了**,键盘快捷键是加成。这条直接决定了电视上的体验
下限 —— 不用背键位也能干活。

### 前缀模型(像 tmux)

默认前缀 `ctrl+b`。`prefix+c` = 按 `ctrl+b` 松开,再按 `c`。

**`prefix+?` 随时弹出帮助面板列出所有生效键位**,里面按 `/` 还能过滤动作 ——
这是最好的发现途径,**不用记本文这张表**。

**官方建议先学这五个:**

| 动作 | 键 |
|---|---|
| 新标签页 | `prefix+c` |
| 向右 / 向下分屏 | `prefix+v` / `prefix+minus` |
| 在 pane 间移动 | `prefix+h/j/k/l` |
| 工作区导航 | `prefix+w` |
| Detach(全都留着继续跑) | `prefix+q` |

**其余按任务分:**

| 分类 | 键 |
|---|---|
| Pane | `prefix+z` 缩放 · `prefix+x` 关闭 · `prefix+shift+h/j/k/l` 交换 · `prefix+r` 调大小 · `prefix+[` 复制模式 |
| Tab | `prefix+n` / `prefix+p` 上/下一个 · `prefix+1..9` 跳转 · `prefix+shift+t` 重命名 · `prefix+shift+x` 关闭 |
| 工作区 / 会话 | `prefix+shift+n` 新建 · `prefix+shift+w` 重命名 · `prefix+shift+d` 关闭 · `prefix+g` Goto 面板 · `prefix+b` 侧栏 |

**Goto 面板(`prefix+g`)在电视上特别值得记** —— 它把每个 agent/终端列成一行、
按工作区分组:`/` 搜索(名字 / agent 类型 / tab / 工作区 / 分支 / 路径),
`j/k` 或上下移动,左右跳到上/下一个工作区分组(不绕回),
`b/w/i/d` 过滤 阻塞 / 工作中 / 空闲 / 完成,`a` 全显示。**鼠标滚轮/拖滚动条也能滚。**

**复制模式(`prefix+[`)**:`h/j/k/l` + tmux 风格 `w/b/e`、`{}`、`PageUp/Down`、
`/` `?` 前后搜索、`n`/`N` 重复、`v` 或 Space 选区、`y` 或 Enter 复制、`q`/Esc 退出。
**鼠标拖选直接复制,根本不进复制模式。**

### ⚠️ 在 Termux 里跑 herdr:`ctrl+alt` 会和 Termux 抢键

herdr 官方推荐的「免 prefix」方案**全用 `ctrl+alt` 家族** —— 它把 Ghostty / iTerm2 /
kitty / WezTerm / Alacritty / GNOME Terminal / Konsole 以及 GNOME/KDE 的默认键位
都过了一遍,结论是 `ctrl+alt` 几乎没人占。

**但 Termux 自己就占了一大片**(从 `TermuxTerminalViewClient.onKeyDown` 抄出来的):

| Termux 占用的 `ctrl+alt+…` | 干什么 |
|---|---|
| `n` / `↓` | 下一个会话 |
| `p` / `↑` | 上一个会话 |
| `→` / `←` | 开 / 关抽屉 |
| `k` | 开关软键盘 |
| `m` | 菜单 |
| `r` | 重命名会话 |
| `c` | 新会话 |
| `u` | URL 选择 |
| `v` | 粘贴 |
| **`+` / `-`** | **终端字号** |
| `1`~`9` | 切到第 N 个会话 |

所以 herdr 那份「免 prefix」配置里 `ctrl+alt+c`(新标签页)、`ctrl+alt+n/p`、
`ctrl+alt+arrows` 等等**根本到不了 herdr**。两条出路:

**① 用 prefix 模型(推荐)。** herdr 默认走 `ctrl+b`,和 Termux 的 `ctrl+alt` 不冲突,
上面那几张表照用就行。

**② 让 Termux 把 `ctrl+alt` 让出来。** `~/.termux/termux.properties`:

```properties
disable-hardware-keyboard-shortcuts = true
```

代价是**连 `ctrl+alt+= / -` 调字号也一起没了**(它和那些会话快捷键在源码里受
同一个开关管),那就改用 `fontsize` 偏好设字号(见上一节)。
`shortcut.create-session` / `shortcut.next-session` / `shortcut.previous-session` /
`shortcut.rename-session` 只能重绑那四个会话快捷键,**不解决 `+`/`-`**。

> ⚠️ 上面这两条**来自源码,未在真机上实测** —— 没有能注入 Ctrl+Alt 组合键的手段
> (Android 的 `input` 不支持 `keycombination`),得用手按着验。

## 对齐体验

两套的**操作习惯是同一套**,不用分别学:

| 环节 | 两套共用 |
|---|---|
| 键入文字 | 电视的搜狗 TV 输入法(遥控 D-pad);需要长打字就上「跨屏输入」或实体键盘 |
| 回车/确认 | 遥控 OK 键(在输入法上是 ⏎) |
| 翻页/滚动 | Termux 用功能键行的 `PGUP/PGDN`;PWA 用遥控方向键 |
| 返回 | `BACK` 在 Termux = 收输入法;在 TV Bro = 呼出工具栏 |
| **键盘快捷键** | Termux:`ctrl+alt+=` / `ctrl+alt+-` 调字号,`ctrl+alt+k/m/r/c/v` 开关键盘/菜单/重命名/新会话/粘贴 |
| herdr 键位 | `prefix`(默认 `ctrl+b`)后跟一个键;**`prefix+?` 弹出全部键位**;没鼠标也能 `prefix+h/j/k/l` 移动 |
| 切换 | 两个应用都在 TV 桌面(`LEANBACK_LAUNCHER` 都有),直接切 |
| 装 / 卸 | 都是 `tools/tv-install.sh`;卸载 `adb uninstall <包名>`(卸载不受 TCL 拦截) |

**一个建议的分工**:A 挂在电视上常驻(看谁在等我),B 需要动手时切过去。
两者指向**同一台开发机上的同一个 herdr 会话** —— Collie 读的是 panes,
Termux 是直接 attach,看到的是同一批会话。

---

## 自动化技巧(给以后维护的人 / agent)

### 驱动 Termux 不用跟交互式输入较劲

Termux 的 GitHub 构建是 **debuggable** 的,所以 `run-as` 可以直接在它里面跑命令:

```bash
# 把任务写成脚本再推过去执行 —— 避免 adb shell→run-as→sh→bash 四层引号地狱
cat > /tmp/t.sh <<'EOS'
export PREFIX=/data/data/com.termux/files/usr
export HOME=/data/data/com.termux/files/home
export LD_LIBRARY_PATH="$PREFIX/lib"; export PATH="$PREFIX/bin:$PREFIX/bin/applets"
cd "$HOME"
"$PREFIX/bin/apt" update
EOS
"$ADB" -s "$TV" push "$(win_of /tmp/t.sh)" /data/local/tmp/t.sh
"$ADB" -s "$TV" shell "run-as com.termux cp /data/local/tmp/t.sh files/home/t.sh"
"$ADB" -s "$TV" shell "run-as com.termux sh files/home/t.sh"
```

### 往 Termux 里「打字」的两个坑

- `input text 'echo hi'` **能用**(空格正常),但**送不了换行** ——
  写 `'...\n'` 会变成字面的 `\n`(实测屏幕上出现 `B-OKn`)。
- 回车要单独发 `input keyevent KEYCODE_ENTER`,而且**每次输入之间要留 1.5 s 以上**,
  否则几次输入会粘成一条命令(实测 `echo HELLO-FROM-ADBuname -aecho $SHELL; id`)。
- 输入法会挡住半屏,先 `input keyevent KEYCODE_BACK` 收掉再截图。

### 装包时会被 TGuard 的三个坑绊到(已修进 `tv-install.sh`)

1. **确认框的按钮 `focused=false`** —— `input keyevent` 完全打不动,必须 `input tap` 点坐标
2. **`application-label` 里有空格** —— 旧的 `badging_field` 会截到第一个空格(`TV Bro: …` → `TV`),
   于是列表里永远找不到;而且列表显示的是**本地化**名字(`TV Bro: 电视网络浏览器`)
3. **TGuard 缓存以文件路径为键** —— 上一版 APK 删了,条目还在,而且**永远解析不出应用名**;
   匹配到它就会「点了没反应」而版本号校验照样通过

前两条见 [03-tcl-tv-sideload.md](03-tcl-tv-sideload.md);第 3 条脚本里会自动把新版
**改名叫缓存里的那个路径**让条目重新生效,并在装完比一次**落地字节数**
(同一个 `versionName` 可以有天差地别的体积)。

---

## 排查时走过的弯路(别重走)

| 我以为 | 实际 |
|---|---|
| 换浏览器就行 | 两个浏览器**共用系统 WebView 83**,表现完全一样 |
| 引擎太老 —— 对,但只对了一半 | 换了 Gecko 还是不行:**TV Bro 默认仍用 WebView** |
| 服务端给电视的是不同页面 | 拿电视 UA / `Accept-Language` 复验,字节数一模一样(155654) |
| MIME 类型不对 | 实测 `text/css`、`application/javascript`,全对 |
| CSS 取不到 | 在电视上直接打开那个 `.css` URL,**能取到**(满屏 CSS 文本) |
| 网站坏了 / 需要登录 | 同浏览器开**百度完全正常** —— 「能渲染 CSS」≠「能渲染**现代** CSS」 |
| Termux 要实体键盘 | 搜狗 TV 输入法**能直接打进 Termux**(走标准 `InputConnection`) |
| `input keyevent` 送不了回车 | 能送,是我 sleep 太短导致多次输入粘在一起 |

**最省时间的两个判据**:

- 错误页是不是 `net::ERR_*` 措辞 → 是则还在用 WebView(方案 A 的唯一分叉点)
- 装完对不上时先比**落地字节数**,别只比 `versionName`
