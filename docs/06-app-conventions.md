# 06 · 工程目录约定

## 核心规则

> **`apps/` 下每个子目录都是一个独立的、可单独构建的 Android 工程。**
> 新增应用 = 在 `apps/` 下新建一个工程目录,**不要**往已有工程里塞业务模块。

两条推论:

1. **每个工程自带 `settings.gradle.kts` + `gradlew` + `gradle/wrapper/`**,是独立 Gradle 构建,
   不是某个根工程下的 subproject。仓库根目录**没有** `settings.gradle.kts`。
2. **工程之间不共享代码**。要复用的东西放 `tools/`(脚本)或 `docs/`(知识),
   真要做共享库再另立 `libs/` 并说明理由。

## `apps/` 现状

| 目录 | 定位 |
|---|---|
| `apps/DualDemo` | **测试验证工程**。用于验证工具链、ADB 链路、设备兼容性。保持精简,**不要往里加业务功能**。 |

## 新建一个应用

```bash
bash tools/new-app.sh <AppName> <package.id>

# 例
bash tools/new-app.sh MyPlayer com.example.myplayer
```

脚本会以 `DualDemo` 为模板复制出一份,替换包名 / 应用名 / 工程名,并清掉构建产物。
生成后直接可构建:

```bash
cd apps/MyPlayer
./gradlew assembleDebug
```

### 手动创建时的清单

```
apps/<AppName>/
├── README.md                    必须写:这个应用做什么、怎么构建、怎么装
├── settings.gradle.kts          rootProject.name = "<AppName>"
├── build.gradle.kts             只说插件版本,apply false
├── gradle.properties
├── gradlew / gradlew.bat
├── gradle/wrapper/              gradle-wrapper.jar + .properties
├── local.properties             sdk.dir=...  (gitignore,不要提交)
└── app/
    ├── build.gradle.kts         namespace / applicationId / minSdk / targetSdk
    └── src/main/
        ├── AndroidManifest.xml
        ├── java/<package path>/
        └── res/
```

`gradle/wrapper/gradle-wrapper.jar` 是二进制。手写不出来,用 `gradle wrapper` 生成,
或者直接从 `apps/DualDemo/gradle/wrapper/` 拷。

## 命名与标识

| 项 | 约定 |
|---|---|
| 目录名 | 大驼峰,同 `rootProject.name`,如 `MyPlayer` |
| `applicationId` | 反域名,如 `com.example.myplayer`。**不同工程必须不同**,否则装到同一台设备会互相覆盖 |
| 应用显示名 | `app/src/main/res/values/strings.xml` 里的 `app_name` |
| Android 模块目录 | 统一叫 `app/`(除非一个工程里有多个模块) |

> `applicationId` 冲突是很容易踩的坑:两个工程用了同一个 id,后装的会覆盖先装的,
> 而且 `adb uninstall` 分不清是谁。新建工程时先确认一下。

## 版本号

**唯一来源是仓库根的 [`version.properties`](../version.properties)。**
工程里不写版本号字面量 —— 连界面上显示的版本也走 `BuildConfig.VERSION_NAME`。

```properties
version=0.0.1
```

各工程的 `app/build.gradle.kts` 从 `rootDir` **往上找第一个** `version.properties`
(不写死 `../..`,拆工程 / 挪目录都不会坏),然后:

| 值 | 怎么来 |
|---|---|
| `versionName` | 直接取 `version` |
| `versionCode` | `MAJOR*10000 + MINOR*100 + PATCH`,每段限 `0..99` |

`versionCode` 是推导出来的,不是手写 —— 免得出现「改了 `versionName` 忘了改 `versionCode`」。
Android 靠 `versionCode` 判断升级,漏改会导致新包装不上(或被当成同一版跳过)。

### 格式:严格 SemVer

只允许 `MAJOR.MINOR.PATCH`。**不支持** `-alpha.1` / `+build.7` 这类后缀 ——
`versionCode` 由数值段推导,带后缀会让两个不同版本算出同一个 `versionCode`,
`adb install -r` 会拒绝覆盖。预发布阶段就直接涨 `MINOR` / `PATCH`。

写错了构建**直接失败**,并说明原因:

```
version=1.0.0-alpha.1 不是严格 SemVer(MAJOR.MINOR.PATCH),见 docs/06-app-conventions.md
version=1.100.0 每段只能是 0..99(versionCode = MAJOR*10000 + MINOR*100 + PATCH)
version=01.0.0 的段 '01' 不合法(SemVer 不允许空段或前导零)
version=a.b.c 里有非数字段: a
```

### 改版本的流程

```bash
# 1. 涨版本号(只改唯一来源)
bash tools/tag-release.sh --bump patch    # 或 minor / major

# 2. 提交 + 推送
#    构建自检会把 APK 里的 versionName 和 version.properties 对一遍,
#    不一致就报错 —— 把「唯一来源」变成可执行约束,而不是只写在文档里
git commit -am "chore(release): 0.0.2 —— ..."
git push

# 3. 打 tag 并推送。tag 名 == version(不带 v 前缀),由脚本强制校验
#    这样任何时刻 `git checkout <tag>` 构出来的 APK 版本号都等于 tag 名
bash tools/tag-release.sh
```

第一个版本是 **`0.0.1`**(`git tag 0.0.1`)。`0.x` 表示对外行为还可能变。

### 发布正式版 APK(可选)

GitHub Release 默认只有源码 zip。要挂**可安装的 APK** 得先配好签名 ——
AGP 产出的 `app-release-unsigned.apk` **装不上设备**(Android 拒绝未签名包)。

**一次性准备**(每台机器/每个仓库一次):

```bash
bash tools/gen-keystore.sh
```

它生成两个文件,**都已 gitignore**:

| 文件 | 内容 |
|---|---|
| `tools/keystore/release.jks` | 密钥库 |
| `keystore.properties` | 密码与别名 |

> ⚠️ **这两个文件必须立刻备份。** 丢了 → 已装机的应用永远无法升级
> (Android 用签名判定「是不是同一个应用」,只能卸载重装,数据全丢)。
> 泄露了 → 别人能以你的名义发版。
>
> 工程里的 `app/build.gradle.kts` 从 `rootDir` 往上找 `keystore.properties` ——
> **找不到就不配 `signingConfig`**,`assembleRelease` 照样能跑(产出 unsigned 包),
> 所以别人 clone 下来不会因为缺密钥而构建失败。

**发版时顺带出包**:

```bash
bash tools/release-apk.sh 0.0.2 --upload
```

它会:

1. 校验 tag 存在、且 **tag 里那份 `version.properties` 就是这个版本**
2. 在**临时 git worktree 里 checkout 那个 tag** 再构建 —— 不用当前工作区,
   保证 Release 附件能从 tag 复现(工作区可能带着未提交改动或领先 tag 的提交)
3. 对 `apps/` 下每个工程跑 `assembleRelease`
4. 逐个校验:已签名、`versionName` == version、`versionCode` == 推导值、
   **且不含 debug 自截图钩子**
5. 产物拷到 `dist/<AppName>-<version>.apk`(`dist/` 已 gitignore)
6. `--upload` 时传给对应的 GitHub Release

`--with-debug` 会额外附上带自截图钩子的 debug 包(真机验收时有用)。

> ⚠️ **装机坑**:release 包用你的密钥签名,debug 包用 `debug.keystore`,**两者签名不同**。
> 同一台设备上从 debug 换装 release 会报
> `INSTALL_FAILED_UPDATE_INCOMPATIBLE`,必须先 `adb uninstall <applicationId>`。
> 全新设备没这个问题。

### 怎么验证版本号真的走的是这一个来源

两层,第一层不需要设备:

```bash
# 1) 编译产物层 —— 比对 APK 里的 versionName 与 version.properties
bash tools/verify-all.sh --build-only
#   ✅ 版本号与 version.properties 一致 (0.0.1)
```

第二层要设备。**只有电视能这么验**(Pico 读不到 UI 树,见 [04](04-pico4-notes.md)):

```bash
bash tools/verify-all.sh                              # 装到电视并启动
adb -s "$TV_ADDR" shell input keyevent 20 20 20 ...   # 滚到底
#   ⚠️ 版本文案是列表最后一项,而 LazyColumn 只组合可见项 ——
#     不滚到底,uiautomator 里根本读不到它
adb -s "$TV_ADDR" shell uiautomator dump /sdcard/_vc.xml
```

实测结果(2026-09,电视 Android 11):

```
dumpsys package com.example.dualdemo
  versionName=0.0.1
  versionCode=1

UI 树 → text="共 18 项 · 构建 v0.0.1"
```

一行文本同时证明了四件事:`version.properties` 被读到 → Gradle 写进了 `versionName` →
`BuildConfig.VERSION_NAME` 编译正确 → 界面没有字面量。

> 这个「最后一项要滚到底才读得到」的细节不只影响版本号。**LazyColumn / RecyclerView
> 里不在视口内的项在 `uiautomator` 里是不存在的** —— 写 UI 断言前先确认目标项已经进入视口,
> 否则会误判成「界面上没有这个元素」。

### 为什么放在仓库根,而不是每个工程一份

`apps/` 下每个工程都是独立 Gradle 构建,各放一份更利于独立演进。
但本仓库是**作为一个整体发**的(一个 tag、一套 `docs/`、一套 `tools/`),
所以版本也统一成一个 —— 免得再出现「tag 是 `0.0.1`、APK 里却是 `0.1.0`」这种漂移。

真需要让某个应用独立走版本线时,再把它拆成工程内一份,并在该工程 README 里写明。

## 版本组合

保持全仓库一致,避免每个工程各自漂移(这里是**工具链**版本,应用自己的版本号见上一节):

| 组件 | 版本 |
|---|---|
| AGP | 8.7.3 |
| Kotlin | 2.0.21 |
| compileSdk / targetSdk | 34 |
| minSdk | **29** |
| Compose BOM | 2024.12.01 |

`minSdk = 29` 是为了同时覆盖手上的设备(Android TV 是 API 30,Pico 4 是 API 29)。
换设备后按 [docs/02](02-adb-multi-device.md#设备规格对照) 重新核算。

## 目标设备兼容性

如果新应用要同时跑在 TV 和手机/VR 上,`AndroidManifest.xml` 里那三条不能少:

```xml
<uses-feature android:name="android.software.leanback" android:required="false" />
<uses-feature android:name="android.hardware.touchscreen" android:required="false" />
<intent-filter>
    <action android:name="android.intent.action.MAIN" />
    <category android:name="android.intent.category.LEANBACK_LAUNCHER" />
    <category android:name="android.intent.category.LAUNCHER" />
</intent-filter>
```

外加 `android:banner` 指向一张 **320×180** 的图。

细节和原因见 [apps/DualDemo/README.md](../apps/DualDemo/README.md#让一个-apk-同时上-tv-和-vr-的三个关键点)。

### 只跑单一设备时

如果应用只给电视用,可以把 `leanback` 设成 `required="true"` 并去掉 `LAUNCHER` category。
但**要在该工程的 README 里写明目标设备**,否则以后会有人拿它去装 Pico 然后困惑为什么装不上。

## 每个工程的 README 必须回答

1. 这个应用**做什么**
2. **目标设备**是哪台(或哪几台)
3. 怎么**构建**、怎么**安装**、怎么**验收**
4. 有哪些**已知限制**

如果该工程对版本号有特殊安排(比如拆了独立版本线),还要写明它跟
`version.properties` 的关系。

参考 [apps/DualDemo/README.md](../apps/DualDemo/README.md)。

## 验收要求

新工程至少要跑通一遍完整闭环,并在 README 里记下证据:

```bash
bash tools/devices.sh                                    # 设备在线
cd apps/<AppName> && ./gradlew assembleDebug             # 构建通过
bash ../../tools/tv-install.sh app/build/outputs/apk/debug/app-debug.apk
bash ../../tools/device-status.sh "$TV_ADDR" <applicationId>   # 装了、在前台、无崩溃
```

安装和验收的正确姿势见 [AGENTS.md](../AGENTS.md) —— 尤其是**不要对 TCL 电视用 `adb install`**。
