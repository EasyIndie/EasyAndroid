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

## 自动化脚本

```bash
bash tools/tv-install.sh app/build/outputs/apk/debug/app-debug.apk
```

```
==> 目标: 双端演示  (com.example.dualdemo)  @ 192.0.2.11:5555
==> 推送 APK 到 /sdcard
==> 打开 安全卫士 / 应用管理器
==> 切到「应用安装」
==> 进入存储源并扫描
==> 在列表里定位「双端演示」
  焦点已落在「双端演示」
==> 触发安装 + 过两道确认框
  安装流程已结束

==> 结果
  已安装
  primaryCpuAbi=armeabi-v7a
  installerPackageName=com.android.packageinstaller
```

### 脚本里几个必要的细节

| 细节 | 原因 |
|---|---|
| 先 `KEYCODE_HOME` 再 `am start` | **电视会自动进屏保(DreamActivity)**,屏保期间 `am start` 什么反应都没有 |
| `am start -S` 强停应用管理器 | 否则会复用上次残留的页面状态,导航起点不确定 |
| 左侧栏导航 `LEFT` → `UP`×5 → `DOWN`×2 | `UP` 到顶会截断,所以先归顶再下移两位 |
| **按应用标签匹配焦点项**,而不是盲按 | 列表里混着 `._xxx.apk`(**macOS 苹果资源叉文件**,只有 4KB,不是合法 APK),盲按会选中它并报「解析包时出现问题」 |
| 全程用 `uiautomator dump` 读文本 | 不用截图,不消耗多模态 token |

### 焦点项标签怎么取

列表项容器本身没有 `text`,应用名是它的子节点。所以要在 UI 树里找
**bounds 落在 focused 节点内部的文本**,并排除日期和状态标记:

```python
# 伪代码
if focused_node_bounds contains (label_bounds):
    if not re.fullmatch(r'\d{4}\.\d{2}\.\d{2}', txt) and txt != '本机已安装':
        candidates.append(txt)
label = candidates[0]
```

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

- 目录:`<U盘>/AndroidTV/`
- 电视会在挂载时扫描;TGuard 的 `appmanager.receiver.UsbMountedReceiver` 处理卸载/拔出事件
- 实测把 APK 直接 `adb push` 到 `/storage/<volId>/AndroidTV/` 也是可写的(shell 对该目录有权限)
- 但**想通过 adb 模拟「插入」事件做不到**:`MEDIA_MOUNTED` 是保护广播,shell 发不了

### 残留改动

排查过程中把电视的这两个设置改成了 0(**对设备的持久改动**,虽然实测无效):

```bash
adb -s $TV shell settings put global verifier_verify_adb_installs 1
adb -s $TV shell settings put global package_verifier_enable 1
```
