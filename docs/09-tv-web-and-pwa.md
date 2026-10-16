# 在电视上跑现代 Web 应用(TV Bro + GeckoView)

TCL 电视上**没有 Google Play / GMS**,自带浏览器是老引擎。想在电视上用现代 Web 应用
(比如 [ColliePWA](https://colliepwa.dev) 这类驱动 AI agent 的自建 PWA,见
[电视上驱动 herdr](#电视上驱动-herdr一条能走通的路径)),需要下面这套组合。

一句话结论:**装 [TV Bro](https://github.com/truefedex/tv-bro) 的 gecko 构建,
并且必须把引擎从默认的 `WebView` 改成 `GeckoView`** —— 只改一半会得到
「页面能打开但完全没样式、JS 不执行」,而且看起来像网站坏了。

---

## 为什么自带浏览器不行

| 项 | 值 |
|---|---|
| `com.tcl.browser` | 3.0.880 —— 连 CSS 都不解析(实测:整页裸 HTML) |
| `com.quark.yun.tv` | 夸克**网盘** App 顺带带的浏览器,要扫码登录 |
| 系统 WebView | **`com.android.webview` 83.0.4103.120 = Chromium 83(2020 年 6 月)** |

TV Bro 的 `geckoExcluded` 构建也走系统 WebView,所以**换浏览器本身没用** ——
只要引擎是那个 WebView 83,结果一样。

### Chromium 83 会静默丢掉整份样式表

实测目标站点的 CSS(Tailwind v4.3.3 产出):

```
需要 Chrome 99+  的 @layer        : 1 处
需要 Chrome 111+ 的 :has()        : 1 处
需要 Chrome 105+ 的 oklch/color-mix: 1 处
```

`@layer` 是 **Chrome 99 / Firefox 97** 才有的 at-rule。Chromium 83 遇到它以**外层块**为单位
整块丢弃 —— Tailwind v4 把**所有**样式都包在 `@layer theme/base/components/utilities` 里,
于是**一个字节的样式都不生效**。页面表现成「裸 HTML + 卡在 Loading…」,
很容易被误判成「网站坏了 / 网络不通 / 需要登录」。

> 判据对比:同一个浏览器开百度**完全正常**(百度用的是老式 CSS + 内联样式)。
> 所以「浏览器能不能渲染 CSS」和「能不能渲染**现代** CSS」是两件事,
> 别用前者证明后者。

---

## 怎么做

### 1. 装 TV Bro 的 gecko 构建

必须选**带 Gecko 的那个 APK**(它的文件名里有 `geckoIncluded`),普通构建不含新引擎:

| 构建 | 大小 | 引擎 |
|---|---|---|
| `tvbro-<ver>-generic-geckoExcluded.apk` | 6.8 MB | 只有系统 WebView |
| `tvbro-<ver>-generic-geckoIncluded-armeabi-v7a.apk` | 142.9 MB | **自带 GeckoView** |

这台电视是 `armeabi-v7a`(`ro.product.cpu.abilist64` 为空),所以下 `armeabi-v7a` 那份。
实测 `libxul.so` 里的 UA 版本是 **Firefox/147.0** —— 现代浏览器该有的一样不缺。

装法见 [03-tcl-tv-sideload.md](03-tcl-tv-sideload.md)(U 盘 + TGuard,`tools/tv-install.sh`)。

### 2. ⚠️ 把引擎切成 GeckoView —— **这一步最容易漏**

TV Bro **装了 Gecko 也默认用 WebView**。不切就会出现上面那种「没样式」现象,
而菜单里那一项看起来只是个无关的偏好设置。

```
打开网页 → 按 BACK 呼出工具栏 → 点「设置」(工具栏最右)
  → 浏览器引擎 = WebView          ← 默认值,要改
  → 点它 → 选 GeckoView
  → 弹「GeckoView 的加载速度比 WebView 稍慢。你想继续吗?」→ OK
  → 弹「需要重启应用 / 重新启动应用以应用此更改」→ 退出
```

重启后 `设置 → 浏览器引擎` 显示 `GeckoView` 才算生效。

> 这些对话框**没有 D-pad 焦点**,必须用 `input tap` 点按钮坐标。
> 细节见 [03-tcl-tv-sideload.md](03-tcl-tv-sideload.md#-但系统安装器的-alertdialog-必须用-tap2026-09-18-实测)。

### 3. 验证

```
打开 https://colliepwa.dev/demo  →  应看到深色主题、等宽字体、分节的卡片布局
```

### 怎么判断当前用的是哪个引擎

**看错误页的措辞。** Chromium 报 `net::ERR_ACCESS_DENIED` / `net::ERR_EMPTY_RESPONSE`
这种 `net::ERR_*` 形式;**Gecko 不用这套命名**。看到 `net::ERR_*` 就说明还在用 WebView。

---

## 电视上驱动 herdr:一条能走通的路径

[herdr](https://herdr.dev) 是跑在开发机上的终端复用器/agent 编排器(终端 UI)。
客户端**不需要**是终端模拟器 —— 它的手机客户端
[ColliePWA](https://colliepwa.dev)(MIT)是个**自建 PWA**:

> *Herdr mobile client for iPhone and Android. A self-hosted PWA ... **no app store**.*

所以电视这条路是:**开发机上跑 Collie → 电视用 TV Bro(GeckoView)打开它**。

```bash
# 开发机:起 Collie(默认走 Tailscale;局域网内直接访问其监听端口也行)
# 电视:   TV Bro 打开 http://<开发机>:<端口>/
```

三点值得注意:

- **它不是商店应用。** Google Play 上**没有** "Herdr Mobile"(搜出来的是无关的模糊匹配),
  而且这台电视连 Play / GMS 都没有。别在这上面浪费时间。
- **打字没问题。** 电视上有系统的搜狗 TV 输入法
  (`com.sohu.inputmethod.sogou.tv/.SogouIME`),遥控器 D-pad 就能输入 ——
  Collie 的输入框是标准 `text field`,吃得到这个输入法。
  这是它比 Termux 强的地方(Termux 用自己的键盘,遥控几乎没法用)。
- **另一种选择是 Termux + ssh**,装在电视上是可行的(实测
  `com.termux` 0.118.3:`minSdk 24` ✅ / `native-code: armeabi-v7a` ✅ /
  有 `LEANBACK_LAUNCHER` ✅,会出现在 TV 桌面),而且能拿到 herdr 的完整 TUI。
  **但它需要实体键盘**(USB 或蓝牙),否则没法输入。
  电视有 `android.hardware.usb.host`,蓝牙也是开的。

### 顺带:电视的能力清单(选方案时要用的几个)

| 能力 | 值 |
|---|---|
| ABI | `armeabi-v7a, armeabi`(**`abilist64` 为空** —— 只能装 32 位 APK) |
| Android | 11 / API 30,`user` 构建,**无 root** |
| Google Play / GMS | **没有** |
| leanback_only | 是 —— 没有 `LEANBACK_LAUNCHER` 的应用**不会出现在 TV 桌面** |
| 输入 | IR 遥控(`gIrTouch_Mouse`,带 `MOUSE|TOUCHPAD|POINTER`)+ 搜狗 TV 输入法 |
| 触摸屏 | 没有 |
| 外设 | `android.hardware.usb.host` ✅、蓝牙 ON ✅ |

---

## 排查时踩过的弯路(留着,别重走)

| 我以为是 | 实际是 |
|---|---|
| 换浏览器就行 | 两个浏览器共用系统 WebView 83,表现**完全一样** |
| 引擎太老(WebView 83) | —— 这条**对**,但只对了一半:换了 Gecko 还是不行 |
| Gecko 构建已经用上 Gecko 了 | **没有**,默认还是 WebView(靠 `net::ERR_*` 认出来) |
| 网络/服务端给电视的是不同页面 | 拿电视 UA / `Accept-Language` 复验,字节数一模一样(155654) |
| MIME 类型不对 | 实测 `text/css`、`application/javascript`,全对 |
| CSS 取不到 | 在电视上直接打开那个 `.css` URL,**能取到**(满屏 CSS 文本) |
| 页面被 CDN 缓存了旧版 | `cache-control` 正常 |

**最省时间的判据**:错误页是不是 `net::ERR_*` 措辞 → 是则还在 WebView →
这是唯一一个能立刻定位的分叉点。
