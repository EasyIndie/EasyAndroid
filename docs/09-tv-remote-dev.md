# 把电视当远程开发终端:两套方案

在 TCL 电视(Android 11 / **无 Google Play** / 只有遥控)上远程连到开发机干活。
两套方案**都已在本仓库的实机上跑通**,互相补充:

| | **方案 A:自建 PWA** | **方案 B:Termux + SSH** |
|---|---|---|
| 跑什么 | [ColliePWA](https://colliepwa.dev)(herdr 的手机客户端) | Termux 里的 `ssh` + `tmux`/herdr 的 TUI |
| 电视上装什么 | **TV Bro**(带 GeckoView 的构建) | **Termux** + `openssh` + `tmux` |
| 开发机上要什么 | 起一个 Collie 实例(自建 Web 应用) | **什么都不用装**(只要有 sshd) |
| 打字 | 网页输入框 → 搜狗 TV 输入法 | 终端 → 搜狗 TV 输入法(**实测可用**) |
| 实体键盘 | 不需要 | 不需要,但强烈建议 |
| 屏幕利用 | 卡片/按钮式 UI,**为遥控优化** | 真终端,TUI 原样渲染 —— 信息密度高 |
| 装一次耗时 | ~90 s(143 MB 包) | ~330 s(32 MB 包 + apt) |
| 适合 | "看哪个 agent 在等我、回一句话" | "真的要敲命令、看日志、改代码" |

> **建议两个都装。** A 用来快速瞥一眼 + 回话(遥控友好),B 用来干正事。
> 它们共用同一套安装通道、输入法和验收手段,见下面「对齐体验」。

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

**已经被证明可用 —— 一台蓝牙键盘(K380)接上就直接出输入设备。**

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

# ③ ★ 最硬的一条:屏幕上真的出现光标、动鼠标它跟着动
adb -s "$TV_ADDR" exec-out screencap -p > mouse.png
```

实测罗技 2.4G 鼠标的结果:①②全过(X/Y 到 1919×1079、`Sources: 0x01002313` 含
`0x2000`、有 `Cursor Input Mapper`);③ 未做终确认——**用户反馈实际可用**。

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

## 对齐体验

两套的**操作习惯是同一套**,不用分别学:

| 环节 | 两套共用 |
|---|---|
| 键入文字 | 电视的搜狗 TV 输入法(遥控 D-pad);需要长打字就上「跨屏输入」或实体键盘 |
| 回车/确认 | 遥控 OK 键(在输入法上是 ⏎) |
| 翻页/滚动 | Termux 用功能键行的 `PGUP/PGDN`;PWA 用遥控方向键 |
| 返回 | `BACK` 在 Termux = 收输入法;在 TV Bro = 呼出工具栏 |
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
