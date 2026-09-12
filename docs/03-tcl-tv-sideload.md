# 03 · TCL 电视固件级侧载封锁与绕行

实测机型:TCL `tcl_mt5879_cn`(MT9952),Android 11 / API 30,固件 `2026012200`。

**结论先行**:`adb install` 全面被封,唯一可用通道是 **TGuard 的图形化安装器**
(`安全卫士 → 应用管理 → 应用安装`)。已封装成 `tools/tv-install.sh`,可全自动执行。

---

## 现象

```bash
$ adb -s 192.0.2.11:5555 install -r app-debug.apk
Performing Streamed Install
adb: failed to install app-debug.apk: Failure [INSTALL_FAILED_VERIFICATION_FAILURE]
```

**与包内容无关**。为了确认是全局封锁而不是针对我们的包,拿官方的 F-Droid APK 做对照:

```bash
curl -sL -o fdroid.apk https://f-droid.org/F-Droid.apk
adb -s $TV install -r -t fdroid.apk
# → 同样 INSTALL_FAILED_VERIFICATION_FAILURE
```

## 根因

抓安装时的日志,能定位到拦截者:

```
D/OverseasAppConfig(571): Verifying begin
D/OverseasAppConfig(571): pkgName = com.example.dualdemo
I/AppRecordJni(1208): getAppInstallEvent with event: 16, package: com.example.dualdemo
W/RuleEvaluation(571): Integrity rule files are not available.
I/PackageManager(571): Integrity check passed for file:///data/app/vmdl880486418.tmp
→ INSTALL_FAILED_VERIFICATION_FAILURE
```

PID 571 是 **system_server**。也就是说 TCL 在 `PackageManagerService` 里打了补丁,
类名 `OverseasAppConfig`。注意「Integrity check passed」之后仍然失败 —— 它不走 AOSP 的 verifier 流程。

验证:这个类**不在** `/system/framework/services.jar` 里(已把它拉下来 grep 确认),
应该在 TCL 自己的 boot image(`/system/framework/arm/boot-tcl.*`)或其它框架 jar 中。

### 为什么常规解法全部无效

网上流传的解法是关掉 AOSP 的包校验开关:

```bash
adb shell settings put global verifier_verify_adb_installs 0
adb shell settings put global package_verifier_enable 0
```

在这台电视上**完全无效**,因为 TCL 的补丁绕过了 `isVerificationEnabled()` 那套逻辑。

> 顺带一提:这台电视上插的 U 盘里有个前任留下的 `readme.txt`(上一台飞利浦电视的笔记),
> 里面记的正是这个 `verifier_verify_adb_installs 0` 方案 —— 那是飞利浦的解,不是 TCL 的。

---

## 已尝试且全部失败的方案

| 手段 | 结果 |
|---|---|
| `settings put global verifier_verify_adb_installs 0` | ❌ |
| `settings put global package_verifier_enable 0` | ❌ |
| `settings put global package_verifier_user_consent 1` | ❌ |
| 改完设置后**重启电视** | ❌ |
| `adb install -i com.tcl.appmarket2`(伪造 TCL 商店身份) | ❌ |
| `adb install -i com.android.vending` | ❌ |
| `adb push` + `pm install` | ❌ |
| `pm install --user 0` | ❌ |
| `pm install-create --skip-verification` + `install-write` + `install-commit` | ❌ |
| `pm install` 从 `/sdcard/` 或 U 盘路径 | ❌ 报 `Can't open file`(shell 的 SELinux 域读不了 removable volume,`pm install` 只认 `/data/local/tmp/`) |
| `am start -a VIEW -d file:///sdcard/x.apk -t application/vnd.android.package-archive` | 无 activity 可解析 |
| `am start -n com.android.packageinstaller/.InstallStart -d file://...` | 静默失败(原因见下) |
| 直接拉起 `com.tcl.appmarket2/...InstallationActivity` | `SecurityException: not exported from uid 10048` |
| 借商店里**导出的**活动转发 | 探测发现那些活动其实也都没导出 |
| `sm unmount/mount <volId>` 重挂 U 盘触发 TCL 的挂载弹窗 | shell 下 `sm` 只支持 `list-*` |

### 两个关键的机制性发现

**1. 系统安装器只接受 `content://`,不接受 `file://`**

```
com.android.packageinstaller/.InstallStart
    Action: "android.intent.action.VIEW"
    Action: "android.intent.action.INSTALL_PACKAGE"
    Category: "android.intent.category.DEFAULT"
    Scheme: "content"          ← 只有 content
    StaticType: "application/vnd.android.package-archive"
```

所以任何 `file://` 的尝试都会被静默丢弃。而 shell(uid 2000)又**没法为自己不拥有的
provider URI 授权**(试 `content://com.android.externalstorage.documents/...` 会得到
`UID 2000 does not have permission ... you could obtain access using ACTION_OPEN_DOCUMENT`)。

用 MediaStore 的 URI 也走不通 —— 文件确实能进库(`content://media/external/file/14679`),
但 `am start` 之后连一条 `ActivityTaskManager` 日志都没有。

**2. 电视上没有任何文件管理器**

```
$ adb shell cmd package query-activities -a android.intent.action.VIEW \
    -c android.intent.category.DEFAULT -t application/vnd.android.package-archive \
    -d file:///sdcard/x.apk
No activities found
```

`pm list packages` 里只有 `com.tcl.ui_mediaCenter`(媒体播放器)和 `com.tcl.profilemanager`,
没有 DocumentsUI / 文件管理器。所以「用文件管理器打开 APK」这条最常见的路也不存在。

---

## 破解路径是怎么找到的

### 线索一:`installerPackageName` 暴露了历史安装方式

```bash
adb shell pm list packages -3        # 第三方应用
adb shell dumpsys package <pkg> | grep installerPackageName
```

结果:

| 包 | installerPackageName |
|---|---|
| `com.quark.yun.tv` | `com.tcl.appmarket2`(商店装的) |
| `com.amazon.firetv.youtube` | `com.tcl.guard`(TGuard 装的) |
| `org.courville.nova` | **`com.android.packageinstaller`** |
| `tv.emby.embyatv` | **`com.android.packageinstaller`** |
| `com.github.metacubex.clash.meta` | **`com.android.packageinstaller`** |

**说明图形化安装通道是通的。** 更关键的是安装时间:

```bash
adb shell dumpsys package org.courville.nova | grep firstInstallTime
# → 2026-04-12 18:24:00
```

固件构建是 **2026-01-22**,而这几个应用是 **2026-04-12** 装的 —— **在当前固件之后**。
所以不是「老固件能装、新固件封了」,路确实还通,只是我没找对入口。

### 线索二:MediaStore 里有 U 盘快照

排查 MediaStore 时顺带把 U 盘内容暴露了出来:

```bash
adb shell content query --uri content://media/external/file \
  --projection _id:_data --where "_data LIKE '%.apk'"
```

```
Row: 1 _id=14598, _data=/storage/8465-1701/AndroidTV/com.amazon.firetv.youtube.apk
Row: 5 _id=14604, _data=/storage/8465-1701/AndroidTV/emby-android-google-arm64-v8a-release.apk
Row: 13 _id=14614, _data=/storage/8465-1701/AndroidTV/org.courville.nova-...-release.apk
```

`8465-1701` 是插在电视上的 U 盘。**`AndroidTV/` 这个目录名就是 TCL 约定的侧载目录**
(这是 TCL 电视的通用玩法:U 盘里建 `AndroidTV` 文件夹放 APK)。

### 最终入口:TGuard 的应用管理器

```bash
adb shell am start -n com.tcl.guard/.appmanager.activity.AppManagerActivity
```

界面里有三个标签:**应用管理 / 应用卸载 / 应用安装**。

进「应用安装」→ 选存储源 `SDCARD` → 扫描完成后列出所有 APK → 选中 → 弹系统安装器两次确认:

```
① 应用未被认证，是否继续安装？        [取 消] [继 续]
② 要安装此应用吗？                    [取 消] [安 装]
→ com.android.packageinstaller/.InstallSuccess
```

装完 `installerPackageName=com.android.packageinstaller`,和当初 Nova / Emby 那批一致。

---

## ⚠️ 三个必须知道的机制

这三条都是踩过才知道的,不搞清就无法自动化。

### 1. 列表里的 `SDCARD` 其实是【可移动存储】,不是 `/sdcard`

存储源页显示的是一一

```
SDCARD   可用57.83 GB/共58.27 GB
```

但电视的**内建存储只有 50 GB**(`/data` 是 `mmcblk0p38`,50G)。
58.27 GB 对应的是插在电视上的 **U 盘**。也就是说这个源扫的是可移动卷。

**所以 APK 要放到 `<U盘>/AndroidTV/`**,而不是 `adb push /sdcard/`。

```
adb push app-debug.apk /storage/<volId>/AndroidTV/
```

`<volId>` 用 `adb shell ls /storage` 看(排除 `emulated` 和 `self`)。
`AndroidTV/` 这个目录名是 TCL 的约定,shell 对该目录可写。

### 2. TGuard 会缓存扫描结果

往 U 盘里新放一个 APK,**列表不会更新**。实测:

| 操作 | 是否刷新列表 |
|---|---|
| 重新打开应用管理器(`am start -S`) | ❌ |
| 退出存储源再进入 | ❌ |
| `am broadcast MEDIA_SCANNER_SCAN_FILE`(文件已进 MediaStore) | ❌ |
| 重启电视 | ✅ |
| **`pm clear com.tcl.guard`** | ✅(秒级,比重启快)|

需要刷新列表时用 `pm clear com.tcl.guard`。副作用是 TGuard 自己的设置会被重置
(应用自动卸载、定期清理等)。

### 3. 缓存以【文件路径】为键

往同一个路径推不同的包,列表里会一直显示**旧的应用名和旧版本号**。

所以文件名必须唯一,带上包名和版本:

```
<U盘>/AndroidTV/com.example.myapp-1.2.0.apk
```

反过来也有个坑:如果 U 盘上同时存在两个同名应用的不同版本(比如手工拷进去的旧副本),
列表里就会出现**两个相同标签的条目**。只按标签匹配会选错,必须同时对比详情面板里的「版本号」。

---

## 自动化脚本

```bash
bash tools/tv-install.sh apps/<Name>/app/build/outputs/apk/debug/app-debug.apk
```

```
==> 目标: ScaffoldCheck  (com.example.scaffoldcheck v0.1.1)  @ 192.0.2.11:5555
==> 推送 APK 到 /storage/8465-1701/AndroidTV/com.example.scaffoldcheck-0.1.1.apk
==> 打开 安全卫士 / 应用管理器
   焦点已落在「ScaffoldCheck」 v0.1.1

==> 结果
  已安装
  primaryCpuAbi=armeabi-v7a
  versionName=0.1.1
  lastUpdateTime=2026-09-12 07:04:08
  installerPackageName=com.android.packageinstaller
```

> 上面这段是当时的真实输出,所以里面的 `v0.1.1` 反映的是**当时**的命名习惯。
> 现在版本号有统一约定(唯一来源 `version.properties`、从 `0.0.1` 起、严格 SemVer),
> 当时那种 `0.1.1` 不会再出现了 —— 见 [06-app-conventions.md#版本号](06-app-conventions.md#版本号)。

### 脚本里几个必要的细节

| 细节 | 原因 |
|---|---|
| 推送到 `<U盘>/AndroidTV/`,文件名带包名+版本 | 见上面机制 1 和 3 |
| 进列表前先 `WAKEUP` + `HOME`,并确认不在屏保 | **屏保期间 `am start` 返回成功但什么都不发生**,见下面「第二种形态」 |
| 进列表前 `BACK` 清掉残留弹窗 | 上一次安装的「应用安装已完成」弹窗会留在屏幕上,把后续按键全带偏 |
| `am start -S` 强停应用管理器 | 否则会复用上次残留的页面状态 |
| 左侧栏 `LEFT` → `UP`×5 → `DOWN`×2 | `UP` 到顶会截断,所以先归顶再下移两位 |
| **按标签 + 版本号双重匹配** | 列表里混着 `._xxx.apk`(macOS 苹果资源叉文件,4KB,不是合法 APK)和可能的同名旧副本 |
| 装完校验 `versionName` | 防止匹配到陈旧条目后“看起来成功了” |
| 版本不对时清缓存重试一次 | 见机制 2 |
| 装完 `BACK` 关掉完成弹窗 | 否则影响下一次运行 |
| 全程用 `uiautomator dump` 读文本 | 不用截图,不消耗多模态 token |

### 屏保还有第二种形态:按键完全被吞掉

[AGENTS.md](../AGENTS.md) 里写的解法是「`WAKEUP` + `HOME`」,实测**大多数时候有效**,
但撞到过一次例外 —— 值得记下来,因为它会让整个安装链路挂掉。

**症状**:`mWakefulness=Dreaming`、焦点是 `com.tcl.appreciate.art/...DreamActivity`,
此时 `KEYCODE_WAKEUP / BACK / HOME / DPAD_CENTER / POWER` 连发 15 秒**全部无效**,
`am start` 依然静默失败,`uiautomator dump` 只能拿到屏保自身的节点(没有 `text`)——
于是 `tv-install.sh` 的 `match_here()` 永远不匹配,报「安装失败」且「当前界面」为空。

**解法:发一个指针事件。** 实测 `input tap <屏幕中心>` 立刻恢复:

```
起点                              wake=Dreaming   focus=...DreamActivity
① WAKEUP BACK BACK HOME           wake=Dreaming   ← 无效
② 只发 WAKEUP + 等 3s             wake=Dreaming   ← 无效
③ 只发 HOME + 等 3s               wake=Dreaming   ← 无效
④ DPAD_CENTER                     wake=Dreaming   ← 无效
⑤ WAKEUP + HOME + 等 3s           wake=Dreaming   ← 无效
   input tap 960 540              wake=Awake      focus=com.tcl.cyberui/... ← ✓
```

合理:这台电视的遥控走的是 **IR 触控**(`gIrTouch_Mouse`,Source 含
`SOURCE_MOUSE|SOURCE_TOUCHPAD`),屏保只认指针,不认按键。
`tv-install.sh` 的 `reset_ui_state()` 已加上这个兜底(只在确实还是 `Dream` 时才发,
避免误点界面)。

> **没能稳定复现**:静置到屏保 205 秒、长按 `POWER` 再进屏保,两种情况下按键都能唤醒。
> 所以这是一段**防御性代码**,不是已知必现路径。备着是因为它值一次偶发失败。

### 怎么判断「屏保是不是真的卡住了」

```bash
# 110ms,比 dump 便宜
adb -s $TV shell dumpsys window | grep -m1 mCurrentFocus
#   ... com.tcl.appreciate.art/android.service.dreams.DreamActivity   ← 在屏保
```

真正的屏保态和那个卡死态**看起来一样**(都是 `DreamActivity`),区别只是按键管不管用。
所以脚本里的判断是「还是 Dream 就补一个指针事件」,而不是去区分两种状态。

### 怎么从 UI 树里取「当前焦点项」和「文件版本」

列表项容器本身没有 `text`,应用名是它的子节点。所以要在 UI 树里找
**bounds 落在 focused 节点内部的文本**,并排除日期和状态标记:

```python
# 焦点项标签
if focused_node_bounds contains (label_bounds):
    if not re.fullmatch(r'\d{4}\.\d{2}\.\d{2}', txt) and txt != '本机已安装':
        candidates.append(txt)
label = candidates[0]
```

右侧详情面板里是「版本号 → <值>」两个相邻节点,取 `版本号` 后面那个即可:

```python
for i, t in enumerate(texts):
    if t.strip() in ('版本号', '版本') and i + 1 < len(texts):
        version = texts[i + 1].strip()
```

> **一个复盘教训**:调试时我曾把新 APK 推到 U 盘上【已经被缓存的旧文件名】下做实验,
> 结果留下了一个同名不同版本的文件,导致后面排查了很久“为什么总是装成旧版本”。
> 调试用的临时文件要及时清掉,并且脚本要能容忍同名条目。

---

## 电视上「截图变了」不能当作「输入生效」的证据

这条和 Pico 正好相反,跨设备写验收脚本时最容易搞错。

**对照实验**:电视停在 TCL 设置页,4 秒内**不发任何输入**,连拍两张:

```
  t0: UI 22 条 | e12da521   PNG 01a35984 (1406534B)
  t1: UI 22 条 | e12da521   PNG ac333c80 (1518940B)   ← md5 变了!
```

文案集合完全一致,但 PNG 变了 —— TCL 的桌面上有**时钟、天气、动效**在自己跑。
所以「截图 md5 变了」在电视上是**假阳性**。

改成用 **UI 树的全量文案集合**判定,就干净了。同一个操作用的两种判定对比:

| 操作 | 全量文案集合 | PNG md5 | 真实结果 |
|---|---|---|---|
| `input tap` 点左侧导航「声音」 | **不变**(22 条 / e12da521) | 变了 | ❌ 没生效 |
| `DPAD_DOWN` + `CENTER` 选「声音」 | **变了**(22 → 23 条 / 30b90e2e) | 变了 | ✅ 生效 |

### 跨设备的验收信号是对称的

| | TCL 电视 | Pico 4 |
|---|---|---|
| UI 树(`uiautomator dump`) | ✅ 可靠(但要拿**全量文案集合**,不是前几条) | ❌ 只能拿到 `com.pvr.vrshell` 的 |
| 截图 | ✅ 能抓,但**不能用来判变化**(UI 自走) | 只能靠应用自截图,但像素差**可靠** |
| 结论 | 判断输入用 **dump 文案集** | 判断输入用 **自截图像素差** |

**所以不要写一套“通用”的验收逻辑。** 两台设备的信号是反的:
电视上可靠的那个在 Pico 上拿不到,反之亦然。

---

## 触摸在电视上到底管不管用

**结论:不要用 `input tap`,一律用 `input keyevent`。** 这是量化验证过的:

| 测试点 | `input tap` | 说明 |
|---|---|---|
| TCL 桌面磁贴「我的应用」(203,539) | ❌ | 前台/文案集合均不变 |
| TCL 桌面磁贴「设置」(180,860) | ❌ | 同上 |
| TCL 设置左侧导航「声音」(152,196) | ❌ | 文案集合不变;按键则变 |
| TCL 设置里的「高级设置」(408,376) | ❌ | 该节点在 UI 树里**标了 `clickable="true"`**,照样没反应 |

最后一行值得留意:**不能靠 a11y 的 `clickable` 判断能不能 tap**。
TCL 那些界面是按遥控焦点模型建的,`clickable` 标记和触摸响应不是一回事。

反过来,指针链路本身是通的 —— 否则屏保也不会只认 `tap`。输入设备里有
`gIrTouch_Mouse`(`SOURCE_MOUSE|SOURCE_TOUCHPAD`),这是 TCL 给 IR 遥控做的一套指针模拟。
只是 TCL 自有界面不把 touch 当 click。

> 用标准 AOSP 控件(如系统安装器的 AlertDialog 按钮)能不能 tap 没测(需要触发安装流程)。
> 但本项目在电视上只驱动 TCL 自有界面 + 自己的应用,结论「一律用按键」已经够用。

---

## 其他结论

### `installerPackageName` 是个好用的诊断入口

| installer | 含义 |
|---|---|
| `com.android.packageinstaller` | 图形化安装通道(在这台电视上**可用**) |
| `com.tcl.appmarket2` | TCL 应用商店 |
| `com.tcl.guard` | TGuard(U 盘自动弹窗走这条) |
| 空 / `com.android.shell` | `adb install` |

想知道某台设备上「应用是怎么装进去的」,查这个字段最快。

### U 盘是 TCL 认可的侧载介质

- 目录:`<U盘>/AndroidTV/`(细节见上面的机制 1)
- 电视会在**挂载时**扫描;TGuard 的 `appmanager.receiver.UsbMountedReceiver` 处理卸载/拔出事件
- 实测 `adb push` 到 `/storage/<volId>/AndroidTV/` 是可写的(shell 对该目录有权限)
- 但**想通过 adb 模拟「插入」事件做不到**:`MEDIA_MOUNTED` 是保护广播,shell 发不了

### 残留改动(已还原)

排查过程中试过把电视的这两个设置改成 0。**实测对 TCL 的拦截完全无效**
(拦截发生在 `OverseasAppConfig` 里,不走 AOSP 这套 verifier 逻辑),
所以排查结束后已经改回 1,把设备恢复原状:

```bash
adb -s $TV shell settings put global verifier_verify_adb_installs 1
adb -s $TV shell settings put global package_verifier_enable 1
```

> 记在这里是为了说明"这两条路已经排除过了",不是建议你去设它们。
>
> 另外排查中多次执行过 `pm clear com.tcl.guard` 来重建扫描缓存,
> 会重置 TGuard 自己的设置(应用自动卸载、定期清理等),这个没法还原,
> 影响仅限于那个安全卫士应用自身的偏好项。

---

## 安装耗时:为什么快不起来

`adb install` 被固件封死,唯一通道是图形化安装器,所以**必然慢**。实测各操作开销
(2026-09 复测,原值列在括号里):

| 操作 | 耗时 | 说明 |
|---|---|---|
| `input keyevent` | **1.0~1.1 s/次**(原 ~0.9) | `input` 是 Java 程序,每次都要启动 ART 进程 |
| `uiautomator dump` | **2.1 s/次**(原 ~2.5) | 读界面文本的唯一手段 |
| `exec-out screencap -p` | **2.9~3.3 s/次** | 比 dump 还慢,而且不能用来判变化(UI 自己在动) |
| `dumpsys` | **0.11 s**(原 ~0.12) | 界面状态、包信息都用它 |
| `pm clear com.tcl.guard` | ~0.2 s | 重建扫描缓存 |

据此做的优化(相对最初的写法提速约一倍):

- **按键批量发送**:`input keyevent 20 20 20 ...` 一次传一串,13 个键从 11.7 s 降到 ~1 s
  (2026-09 复测:分 13 次 **12.29 s** vs 一次发 **1.01 s**,12 倍)
- **状态判断改用 `dumpsys`**:不在 `uiautomator` 上花时间
- **对话框盲过 + 事后校验**:两个确认框的默认焦点固定在「取消」,直接 `RIGHT`+`OK`,装完用 `versionName` 校验兜底,省掉两次 dump
- **位置缓存**:列表顺序稳定,把上次找到的序号记在 `tools/.tv-pos-<pkg>`(不入库),下次一次批量按过去,省掉十几轮 dump

结果:**首次 ~80 s,之后 ~60 s**。

### 想更快,只能换设备

- **Pico 4 接受普通 `adb install`,只要 2~3 秒。**
- 但 Pico 的 `screencap` 被 `FLAG_SECURE` 挡掉、`uiautomator` 也读不到 VR 面板
  (见 [04-pico4-notes.md](04-pico4-notes.md))。
- 可行的做法是在**调试构建里加一个自截图钩子**:应用渲染自己的 View 层级到 PNG
  (`View.draw(Canvas)` / `PixelCopy` 不受 `FLAG_SECURE` 影响,因为那是应用自己的 surface),
  再用广播触发 + `adb pull`。这样 Pico 就变成「装得快 + 看得到」的迭代设备,
  电视只在里程碑做验收。
