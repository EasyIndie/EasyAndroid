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

### 签名凭据:存哪儿 —— 什么能入库,什么不能

**结论:凭据本体绝对不能入库;但「指纹」可以,而且应该。**

#### ❌ 不能入库的

`tools/keystore/release.jks`、`keystore.properties`、`--export` 出来的凭据包。

`.gitignore` 拦住了前两个,但**凭据包要靠自觉** —— 它的文件名不在黑名单里。

> ⚠️ 别以为 base64 就等于加密。它就是编码,一条命令还原:
> ```bash
> sed '/^#/d' 凭据包.b64 | tr -d '\r\n' | base64 -d | tar tzf -
> # → release.jks
> # → keystore.properties   ← 里面密码是**明文**
> ```

为什么后果不可逆:

- **Git 历史是永久的。** 以后 `git rm` 只删最新提交里的文件,历史里还在
  (GitHub 的 API 在一段时间内仍能按 SHA 取到不可达对象)。
- **fork / 克隆会带走。** 一旦公开过,别人手里就有了,收不回来。
- **权限是扩散的。** 现在的协作者、以后的公开仓库、CI 日志、第三方安全扫描器都会看到。
- 后果不是「密钥泄露」这么抽象 —— 是**别人能签出可以升级你已安装应用的包**。
  同包名 + 同签名 = Android 认可的合法升级,不需要任何额外权限。

#### ✅ 可以入库:[`signing-manifest.txt`](../signing-manifest.txt)

仓库根有这个文件,里面只有别名和**证书 SHA-256 指纹**:

```
default_alias=release
alias.release=eb3bfaf6847264a0e696996fb02a91fa7e034ec3c42ef9a85c68168d4d573dbd
```

指纹是公钥的哈希,**不是秘密** —— 公开它,别人既反推不出私钥,也签不出能被安装的包。
而它的价值恰恰在于可以公开:任何机器拿到一份凭据后,能立刻回答
**「我手里这把,是不是这个仓库发布时用的那把?」**

```bash
bash tools/gen-keystore.sh --manifest          # 对仓里的期望值自检
bash tools/gen-keystore.sh --manifest --write  # 加了别名之后更新它
```

`release-apk.sh` 也会查这一条:产物签名**不在** manifest 里就直接拒绝发布。

#### 存哪儿(按推荐度)

| 方式 | 适合 | 注意 |
|---|---|---|
| **密码管理器**(1Password / Bitwarden / KeePass) | 个人、小团队 | 存 `--export` 的**整个文件**。自带同步、访问审计、设备丢失后的恢复 |
| GitHub Actions secret(已配) | 给 CI 用 | ⚠️ **不能当备份** —— 值只能写、永远读不回来 |
| 加密后入库(git-crypt / SOPS / age) | 团队协作、想版本化 | 多一层口令;口令忘了同样全丢,而且**必须用强口令**,否则等于明文入库 |
| 离线介质(加密容器 / 保险柜) | 灾备 | 防「密码管理器账号也登不了」这种叠加失效 |
| 云盘直放 | ❌ 不推荐 | base64 不是加密 |

**至少要能回答这个问题**:「如果这台机器明天坏了、密码管理器账号也登不上,我从哪拿到这把密钥?」
答不出来就是没备份。

#### 用什么统一管理

**一个密码管理器,当唯一权威库。** 不要「一部分在这、一部分在那」——
分散是「以后找不到」的头号原因,比加密强度重要得多。

| 选它 | 为什么 |
|---|---|
| **1Password** | 文件附件、多 vault、访问记录。付费,但存凭据包最省心 |
| **Bitwarden** | 免费额度够用,可自建 |
| **KeePassXC** | 完全离线,一个 `.kdbx` 文件。代价是**那个文件本身也要备份**,别只留一份 |

存法:**把凭据包当文件附件存**,别复制成文本笔记 —— 笔记编辑器会重排换行、可能截断,
而附件是逐字节保存的。(解码能容忍换行,但容忍不了截断;真截断了 `--drill` 测得出。)

条目名带上仓库名和指纹前缀,这样以后**搜得到**:

```
EasyAndroid 签名凭据 (release, SHA eb3bfaf6)
```

#### 「凭据在哪」—— 位置记在仓库里(没有秘密)

分散放置是「找不到」的主因,所以把**位置**写下来。位置不是秘密,可以入库:

| 位置 | 是什么 | 谁能拿到 |
|---|---|---|
| 本机 `tools/keystore/release.jks` | 日常用的原件 | 只有这台机器 |
| 密码管理器 `〈待填:vault / 条目名〉` | **权威备份** | 只有你 |
| GitHub Secret `KEYSTORE_B64`(EasyIndie/EasyAndroid) | 给 CI 用 | 仓库管理员 |
| `〈待填:有没有冷备、在哪〉` | 灾备 | 只有你 |

> ⚠️ 这张表里带「待填」的行**只能由你填**。别人替你猜没有意义 ——
> 半年后你要找的是「我当时到底放哪了」。
>
> 另外:GitHub Secret **不算备份**。它的值只能写、永远读不回来,所以它只是
> 「CI 能用」而不是「你还能拿到」。

#### 怎么确认「以后还找得到、还开得了」

三个命令,回答三个不同的问题:

| 问题 | 命令 |
|---|---|
| 这份备份**能恢复**吗? | `gen-keystore.sh --drill <凭据包> --record` |
| 本机这把**对不对**? | `gen-keystore.sh --manifest`(或 `--status`) |
| 我到底**有几份副本**? | `gen-keystore.sh --scan` |

`--drill` 在临时目录里走一遍**完整的导入路径**(解码 → 解包 → 读密码 → 算指纹 → 对期望值),
全程不碰本机凭据;通过后把日期记进 `signing-manifest.txt`。

**为什么要 `--record`**:备份会**悄悄过期** —— 文件被邮件客户端改了行、当时设的口令忘了、
存进去的是更早那次的旧版本。不演练就不知道。记下日期后 `--status` 会显示
「上次恢复演练 N 天前」,超过半年直接提醒重跑。

`--scan` 扫工作目录里所有密钥材料的副本(改名、换扩展名都躲不掉 —— 它比内容哈希),
并且**任何多出来的副本都算失败**。这一项已进 `verify-all.sh`:

```
════════════════ 1.5/4 签名凭据卫生 ════════════════
  ✅ 本机有签名凭据
  ✅ 指纹与 signing-manifest.txt 一致
  ✅ 没有游离的密钥副本
```

> 这一节不是凭空写的:实测发现 `--push-secret` **每跑一次就在 `.tmp/` 漏一份完整凭据包**
> (明文,含私钥)。原因是 `write_bundle` 重新赋值了全局临时目录变量,把调用者的目录孤立了,
> 而退出时的 trap 只删最后一个。跑一次 `--scan` 就全看见了。

### 签名凭据:获取、配置、核对

**先纠正一个直觉:签名凭据不是“申请”来的,是你自己生成一份。**
自签名应用不需要 CA,任意一把 RSA 密钥都能签。关键在于**必须一直用同一把** ——
Android 用签名判定「是不是同一个应用」:

| 情况 | 后果 |
|---|---|
| **丢了** | 已装机的用户**永远无法升级**,只能卸载重装(数据全丢) |
| **换了** | 同上,新包装不上,报 `INSTALL_FAILED_UPDATE_INCOMPATIBLE` |
| **泄露** | 别人能以你的名义发版 |

所以它等同私钥:**不入库、不贴聊天、不进 issue**。`.gitignore` 已经拦住了
`tools/keystore/`、`keystore.properties`、`*.jks`、`*.keystore`。

#### 凭据长什么样

两个文件(都已 gitignore):

| 文件 | 内容 |
|---|---|
| `tools/keystore/release.jks` | 密钥库(RSA 4096,有效期 30 年) |
| `keystore.properties`(仓库根) | `storeFile` / `storePassword` / `keyAlias` / `keyPassword` |

各工程的 `app/build.gradle.kts` 从 `rootDir` 往上找 `keystore.properties`,**找到才配
`signingConfig`**;找不到时 `assembleRelease` 照样能跑,只是产出 unsigned 包。

#### 三个场景

**① 本机首次** —— 生成,然后**立刻导出保管**:

```bash
bash tools/gen-keystore.sh            # 生成(幂等:已存在则拒绝,不会误覆盖)
bash tools/gen-keystore.sh --export   # 导出一个自包含的凭据包 → 存进密码管理器
```

密码默认随机 28 位,只落进 `keystore.properties`,**不打印到控制台**。
想自己定就 `KS_PASSWORD=xxx bash tools/gen-keystore.sh`。

**② 换机器 / 灾后恢复** —— 从凭据包还原:

```bash
bash tools/gen-keystore.sh --import <凭据包文件>
```

导入时会核对包头部记录的指纹,不一致直接报错(避免拿错包)。

**③ CI** —— 把凭据包写进仓库的 Actions secret,一条命令:

```bash
bash tools/gen-keystore.sh --push-secret            # 自动推导 owner/repo
bash tools/gen-keystore.sh --push-secret owner/repo # 或显式指定
```

它内部就是 `gh secret set KEYSTORE_B64 < <凭据包>`。手工也行:

```
Settings → Secrets and variables → Actions → New repository secret
  名字:KEYSTORE_B64   值:--export 产物的全部内容(含 # 头部注释)
```

> **为什么不能让它自动跑在 CI 里**:secret 是只写的,而且能让 CI 自己创建 secret
> 等于允许 CI 自赋权限 —— GitHub 从设计上就不支持。所以这一步必须从
> **已认证的本机**跑一次。之后 secret 值就存住了,不用每次发版都推。

配了它,CI 的 `assembleRelease` 就产出**已签名**的包;没配就是 unsigned(装不上设备,
只能当编译检查)。GitHub 会自动在日志里给 secret 打码。

#### 怎么确认 secret 真的生效

secret 读不回值(`gh secret list` 只给名字和更新时间),所以只能看**产物**:

```bash
# 推一次提交 → 等 CI 跑完 → 下载 CI 上传的 APK → 对比指纹
bash tools/gen-keystore.sh --verify-against <CI 产出的 apk>
```

同一个指纹 → ✅ CI 用的是同一把密钥。
或者更省事:看 CI 日志里有没有这句 notice ——

```
::notice::未配置 KEYSTORE_B64 —— 跳过,assembleRelease 将产出 unsigned 包
```

**有这句 = secret 没生效**(名字拼错?仓库不对?),那种情况 CI 产的是 unsigned 包。

> ## ⚠️ CI 用**同一把**,不要重新生成
>
> 这是一个很容易犯的错:以为「CI 是另一台机器,应该有自己的一份密钥」。
> **不行。** 签名不是环境的属性,是**密钥**的属性 ——
> Android 拿新包的签名和**已安装应用**的签名比,一致才允许覆盖安装。
>
> 所以在 CI 上跑 `gen-keystore.sh`(不带 `--import`)等于换密钥,
> 结果是 **CI 发出来的包任何人都装不上**(已装机的会报
> `INSTALL_FAILED_UPDATE_INCOMPATIBLE`,新装的装完又变成另一个应用)。
>
> 正确做法只有一个:本机 `--export` → 存 secret → CI `--import`。
> 密钥**只在一处生成一次**,之后到处都是拷贝。

CI 侧的行为要点:

- 还原步骤用 `--import`,且**失败就直接让 job 挂掉**(不要 `|| true`)——
  宁可构建失败,也不要静默产出一个 unsigned 包冒充正式包。
- 还原成功后 `keystore.properties` 落在 checkout 目录的仓库根,
  `app/build.gradle.kts` 从 `rootDir` 往上找就能找到。
- 只在 job 内存在,跑完随 runner 一起销毁。

#### 多个应用:共用一把,还是各用一把

**推荐:一个密钥库文件,每个应用一个别名。**

同一个签名下的应用之间是**可互信**的 —— 能访问对方 `protectionLevel="signature"`
保护的组件、能共享 `sharedUserId` 进程。所以共一把密钥 = 共一个信任域:

| | 共用一把(所有应用) | 各用一把(同一 .jks 里多个别名) |
|---|---|---|
| 备份 | 一个文件 | **同样一个文件** |
| 隔离性 | 无 —— 任一把泄露/被替换,全部受影响 | 每把独立,影响面限于单个应用 |
| 轮换密钥 | 得**所有应用一起换**,每个都要用户卸载重装 | 可以单个换 |
| 以后单独转交 / 上架某个应用 | 很难看 | 干净 |

代价几乎为零 —— 因为密钥都在**同一个 `.jks` 文件**里,只多一个别名。

```bash
# 新建应用后,给它一把专用密钥(密钥库文件不变)
bash tools/gen-keystore.sh --add-alias MyPlayer
```

各工程的 `app/build.gradle.kts` 已经有了取别名的逻辑,不用改:

```kotlin
keyAlias = keystoreProps.getProperty("alias." + rootProject.name)  // 优先:按工程名
    ?: keystoreProps.getProperty("keyAlias")                        // 回落到默认
```

实测两个应用签出来确实是两把:

```
DualDemo   eb3bfaf6...   DN=CN=EasyAndroid Release    ← 默认别名 release,未改动
MyPlayer   e0a85a85...   DN=CN=MyPlayer Release       ← alias.MyPlayer
```

> ⚠️ **已经发布过的应用不要改别名。** 那等于换签名,老用户升不了级。
> 所以引入这套时:新应用用 `--add-alias` 拿自己的,**老应用继续用默认那把**。
> 实测 DualDemo 改完配置后 `--verify-against` 已发布的 `0.2.0` 仍然是 ✅。

> 💡 一个内幕:**PKCS12 密钥库会把别名转成小写。** 传 `-alias MyPlayer` 进去,
> `keytool -list` 显示的是 `myplayer`。Java 查 PKCS12 时大小写不敏感,所以用
> 哪个写法都能签;但配置里写 `MyPlayer`、列表里显示 `myplayer` 看着像对不上,
> 而且换成 JKS 就会真找不到。所以 `--add-alias` 会**回读实际别名**再写进配置。

#### 核对:本机这把是不是线上发布那把

**这是最容易搞错的一步。** `keytool` 输出大写带冒号(`EB:3B:FA:...`),
`apksigner` 输出小写无冒号(`eb3bfaf6...`)—— 直接字符串比会得出**假的不一致**。
所以别靠眼睛,用子命令比:

```bash
# 拿任意一个已发布的 Release 附件比
bash tools/gen-keystore.sh --verify-against <某个已发布的 apk>

# 同一把 → ✅ exit 0;不同把 → ❌ exit 1 并告诉你后果
```

`--status` 会同时打出两种写法,并提示该比对命令。

#### 备份怎么做

- `--export` 出来的凭据包是**单个文本文件** —— 直接存密码管理器(或 Secret),不用分别保管两个文件。
- 别把副本长期放在 `dist/` —— 那是构建产物目录,可能被清掉。导出后**立刻挪走**。
- 至少要能回答:「如果这台机器明天坏了,我从哪拿到这把密钥?」答不出来就是没备份。

> 密钥库里有 30 年有效期(证书 2056 年到期),`--status` 会提示剩余天数。
> 真到期前需要换密钥 —— 那是个**发布事件**(老用户必须卸载重装),别当成日常操作。

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

## 构建与发布

### 开发用 debug,发布才出正式包

**一条线:开发 / 验收 / 装机全部用 debug 包;只有发版才构建正式包并加签。**

为什么开发阶段不能换成正式包:

| | debug 包 | 正式包 |
|---|---|---|
| 签名 | `~/.android/debug.keystore`(自动生成) | 你的 release 密钥 |
| `application-debuggable` | **有** | 无 |
| 自截图钩子 `UiDumpReceiver` | **有**(`src/debug/`) | 无 |
| 能不能做 UI 验收 | ✅ | ❌ 没有钩子,`screencap` 又被 `FLAG_SECURE` 挡 |
| 用途 | 日常迭代、真机验收 | 对外发布 |

最后两行是关键:**自截图钩子只在 debug 构建里**,而 Pico 那类设备
`screencap` / `uiautomator` 拿不到画面(见 [04](04-pico4-notes.md))——
换成正式包等于自断验收手段。

### 各自是谁在用

| 入口 | 构建 | 装/验 |
|---|---|---|
| `tools/verify-all.sh` | `assembleDebug` | debug |
| `tools/tv-install.sh` | —（装你传的包） | 开发时传 debug |
| `tools/ui-dump.sh` | — | 需要 debug 包才有钩子 |
| CI `assembleRelease` | release | 只做**编译检查**,不签名不发布 —— 保留它能提前暴露 R8 / proguard 这类 release-only 的问题 |
| **`tools/release-apk.sh`** | `assembleRelease` + 加签 | 发版唯一的正式包入口 |

`release-apk.sh` 会逐个校验产物,把「不小心把 debug 包装成正式包」变成构建期错误:

```
✅ DualDemo-0.2.0.apk 已签名  (CN=EasyAndroid Release)
✅ DualDemo-0.2.0.apk versionName=0.2.0 versionCode=200
✅ DualDemo-0.2.0.apk 非 debuggable(正式包)
```

判据是 `aapt2 dump badging` 里的 `application-debuggable` —— debug 包多这一行,
正式包没有。实测两个包:

```
app-debug.apk          → application-debuggable 在    UiDumpReceiver=1   → 拒绝
DualDemo-0.2.0.apk     → 不在                       UiDumpReceiver=0   → 放行
```

> ⚠️ **签名不同 → 同一台设备上换装要先卸载**:
> `adb uninstall <applicationId>`,否则 `INSTALL_FAILED_UPDATE_INCOMPATIBLE`。
> 真机验收结束后记得把 debug 包装回去,不然下次 `ui-dump.sh` 会失败。

### 发布正式版 APK

GitHub Release 默认只有源码 zip。要挂**可安装的 APK** 得先配好签名 ——
AGP 产出的 `app-release-unsigned.apk` **装不上设备**(Android 拒绝未签名包)。

#### 一条线:推 tag → CI 全自动(推荐)

```bash
# 1. 涨版本(只改唯一来源)
bash tools/tag-release.sh --bump minor

# 2. 提交推送
git commit -am "chore(release): 0.3.0 —— ..." && git push

# 3. 打个 tag 推上去 —— 剩下的事 CI 干
bash tools/tag-release.sh
```

推完 tag,`.github/workflows/release.yml` 会自动:

```
校验 tag 与 version.properties 一致
还原签名凭据(从 secret KEYSTORE_B64;没配就报错退出,不会发 unsigned 包)
从 tag 检出构建 assembleRelease(逐个 app)
逐个校验:已签名 / versionName==tag / versionCode==推导值 / 非 debuggable / 无 debug 钩子
建 Release(说明自动生成)+ 挂上 APK
```

你只需看一眼结果:https://github.com/EasyIndie/EasyAndroid/releases

> **CI 发版而不是本地发版的好处**:构建环境干净、产物来自 tag 而非工作区、
> 每次发版都有日志留痕。本地仍然保留 `release-apk.sh`,用于补发历史版本或离线场景。

#### 发布说明怎么来

优先用 [`docs/releases/<version>.md`](releases/README.md)(想写清楚就写一份,
跟着版本一起提交);没有就自动拼:附件表 + **签名指纹** + 安装命令 +
`<上一个 tag>..<version>` 的变更列表。

本地预览自动生成的说明(不碰 GitHub):

```bash
bash tools/release-apk.sh <version> --print-notes
```

#### 本地手动发(补发历史版本时用)

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
