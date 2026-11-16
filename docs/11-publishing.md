# 上架:GitHub Release / Google Play / 国内商店

本文讲**同一个应用怎么发到三条渠道**。构建/签名的底层约定在
[docs/06](06-app-conventions.md),这里只讲「上架」这一段。

三条链路的能力边界:

| 渠道 | 产物 | 谁审核 | 能自动化到哪一步 |
|---|---|---|---|
| **A. GitHub Release** | APK(+ AAB) | 无 | 全自动:`release.sh` → tag → CI 构建 → 挂附件 |
| **B. Google Play** | AAB | Google(1~7 天) | 构建 + 静态自检自动;上传/审核在 Play Console 人工 |
| **C. 国内商店** | APK | 各商店(1~7 天) | 构建 + 静态自检自动;上传/资质在各自后台人工 |

> 机器能查的东西都收在 `tools/store-preflight.sh` 里了。它**不联网**,
> 只回答「产物和配置够不够交上去」;查不了的(隐私政策、软著、备案、截图)
> 写在 `apps/<App>/store/*.md` 里,逐条人工确认。

---

## 0. 一次性准备

### 0.1 新应用先拿一把专用签名密钥

```bash
bash tools/gen-keystore.sh --add-alias <AppName>
bash tools/gen-keystore.sh --manifest --write     # 更新入库的期望值文件
```

`app/build.gradle.kts` 会自动取 `alias.<工程名>`(见 docs/06「多个应用」)。
**首次上架之后不能再改别名** —— 等于换签名,老用户升不了级。

### 0.2 包名不能是 `com.example.*`

Google Play 明确拒收,国内商店也不接受。用真实反域名,比如
`<package.id>`(例:`com.example.myapp`)。

> 包名在**首次上架后不可改**(等于换应用)。上架前改是免费的:
> 改 `applicationId` + 重新 `--add-alias` + 清掉旧的 `dist/` 即可。

### 0.3 targetSdk 跟商店政策

| 渠道 | 门槛 | 依据 |
|---|---|---|
| Google Play | **target API 36**(2026-08-31 起) | Play 每年 8 月底强制适配上一代 Android |
| 国内商店 | 通常 ≥ 30,华为/小米新应用常见 33+ | 各商店后台为准 |

`store-preflight.sh` 的门槛可以通过环境变量覆盖(政策变了不用改脚本):

```bash
PLAY_MIN_TARGET_SDK=36 CN_MIN_TARGET_SDK=30 bash tools/store-preflight.sh <version>
```

升级 SDK 平台(本机已装 `platforms;android-36` + `build-tools;36.0.0`):

```bash
sdkmanager --sdk_root="$ANDROID_HOME" "platforms;android-36" "build-tools;36.0.0"
```

然后只改**要上架的那个工程**的 `compileSdk` / `targetSdk`。
模板和测试工程不上商店,保持低版本即可 —— 不要为了一个应用把仓库全升了。

> ⚠️ **AGP 8.7.3 对 `compileSdk = 36` 会打一条 warning**
> (`We recommend using a newer Android Gradle plugin`)。实测能正常构建、
> 签名、出 AAB。要彻底消除得升 AGP(会连带 Kotlin/Compose 一起动),
> 属于「单独开一次、上真机重验」的事,别夹在功能开发里。

### 0.4 JVM 截图测试要钉 SDK

Robolectric 4.17 跑 **SDK 36 需要 JDK 21**,而仓库统一 JDK 17。应用
`targetSdk = 36` 时,截图测试会直接失败:

```
java.lang.UnsupportedOperationException: Failed to create a Robolectric sandbox:
Android SDK 36 requires Java 21 (have Java 17)
```

解法是给该应用的测试加 `app/src/test/resources/robolectric.properties`:

```properties
sdk=35
```

截图测试只验布局/颜色/文案,API 35 与 36 没区别;真机才是最真实的 targetSdk 环境。
仓库整体升 JDK 21 之后删掉这行即可。

---

## 1. 版本号与构建

版本号唯一来源是仓库根 `version.properties`,构建产物按它命名:

```
dist/<AppName>-<version>.apk
dist/<AppName>-<version>.aab
```

### 构建

```bash
# 全部应用,只出 APK(GitHub Release 用)
bash tools/release-apk.sh <version>

# 只出一个应用,同时出 APK + AAB(商店用)
bash tools/release-apk.sh <version> --app <AppName> --format both

# 本地预览 Release 说明(不碰 GitHub)
bash tools/release-apk.sh <version> --print-notes
```

| 参数 | 作用 |
|---|---|
| `--app <Name>` | 只构建 `apps/<Name>` |
| `--format apk` | 只出 APK(默认) |
| `--format aab` | 出 APK + AAB |
| `--format both` | 同上(语义更明确) |
| `--upload` | 上传到 GitHub Release |

> `--format aab` **一定也会出 APK**:AAB 里的清单是 protobuf,`aapt2` 读不了;
> 版本号/包名/ABI/签名这些事实要从同一版本的 APK 上取。
> `store-preflight.sh` 就是这么做的。

### 发布渠道登记

每个应用用 `apps/<App>/publish.properties` 声明发到哪:

```properties
# github / play / cn,逗号分隔;缺省 = github
targets=github,play,cn
alias=<AppName>
```

`release-apk.sh` 和 `store-preflight.sh` 都读这一行。带 `selftest.properties` 的测试工程,
只写 `targets=github` —— 不参与商店构建。

---

## 2. A. GitHub Release(已有链路)

```bash
bash tools/release.sh          # 推导版本 + 写 CHANGELOG + 打 tag + 推
```

推 tag 后 `.github/workflows/release.yml` 自动:还原签名凭据 → 从 tag 构建 →
逐个校验(已签名 / versionName / versionCode / 非 debuggable / 无 debug 钩子)→
建 Release → 挂附件。详见 docs/06「发布正式版 APK」。

**唯一入口**是 `release.sh`;本地补发历史版本才用 `release-apk.sh`。

---

## 3. B. Google Play

### 3.1 构建 + 自检

```bash
bash tools/release-apk.sh <version> --app <AppName> --format both
bash tools/store-preflight.sh <version> --target play
```

`store-preflight.sh` 对 Play 检查:

- [x] 包名不是 `com.example.*`
- [x] `targetSdk ≥ 36`
- [x] `versionName` == 版本号,`versionCode` == 推导值
- [x] 非 debuggable、无 debug 自截图钩子
- [x] AAB 结构完整(`BundleConfig.pb` / `base/manifest` / `base/dex`)
- [x] AAB **已签名**(`jarsigner -verify`)
- [x] AAB 含 `arm64-v8a`(有 native 库时)
- [x] `store/play.md` 没有 `TODO:`

### 3.2 Play App Signing

- 上传的 AAB 用**上传密钥**(upload key)签名;本仓库里就是
  `keystore.properties` 的 `alias.<AppName>`。
- 首次在 Play Console 创建应用时选择 **Play App Signing**,Google 保管
  应用签名密钥,之后所有安装包由它重签。
- 上传密钥指纹见仓库根 `signing-manifest.txt`;核对:
  ```bash
  bash tools/gen-keystore.sh --verify-against <某个线上 APK>
  ```
- ⚠️ 上传密钥丢了可以申请重置;应用签名密钥丢了只能换包名(数据全丢)。

### 3.3 Play Console 人工步骤

1. 创建应用 → 默认语言 / 应用名 / 类型(工具)/ 免费
2. 填写 `store/play.md` 里的资料:简短说明、完整说明、图标 512×512、
   特色图 1024×500、截图(手机 ≥2、TV ≥1)
3. 隐私政策 URL(必须可公开访问;GitHub Pages 即可)
4. **数据安全表单**:按应用实际填写(例如无账号 / 无广告 / 无分析 SDK → 「不收集」)
5. 内容分级问卷、目标受众、广告声明
6. 上传 `.aab` 到**内部测试**轨道,先自己装一遍
7. 逐级 promoted:closed → open → production

### 3.4 Android TV 轨道

TV 应用的清单需要三件套(见 docs/06「让一个 APK 同时上 TV 和 VR」):

```xml
<uses-feature android:name="android.software.leanback" android:required="false" />
<uses-feature android:name="android.hardware.touchscreen" android:required="false" />
<category android:name="android.intent.category.LEANBACK_LAUNCHER" />
```

外加 `android:banner` 和 D-pad 可操作的 UI(`tv-material`)。Play 里要单独
勾选 **Android TV** 形态因子并上传 TV 截图。

---

## 4. C. 国内应用商店

### 4.1 构建 + 自检

```bash
bash tools/release-apk.sh <version> --app <AppName> --format apk
bash tools/store-preflight.sh <version> --target cn
```

对国内商店检查:

- [x] 包名不是 `com.example.*`
- [x] `targetSdk ≥ 30`
- [x] 含 `armeabi-v7a`(TCL 等 32 位 TV)
- [x] release 签名(不是 debug)
- [x] APK ≤ 100 MB(部分商店的硬线)
- [x] `store/cn.md` 没有 `TODO:`

### 4.2 共同资质

| 项 | 说明 |
|---|---|
| 开发者实名 / 企业认证 | 个人可上部分商店,企业更稳 |
| 软件著作权证书(软著) | 应用名要和软著一致或能说明关系 |
| APP 备案 | 2023 起国内分发普遍要求 |
| ICP 备案 | 联网应用必需;不联网应用多数可豁免,以商店后台为准 |
| 隐私政策 URL | 必须可公开访问 |

### 4.3 各商店

| 商店 | 备注 |
|---|---|
| TCL 应用商店 | TV 场景最匹配;要 banner、横屏截图、D-pad 可操作 |
| 华为 AppGallery | 新应用通常要 `targetSdk ≥ 33`;权限说明按实际填写,无敏感权限就填「无」 |
| 小米 / OPPO / vivo | 独立后台;「设备信息」类要说明用途,避免被判仿冒系统工具 |

完整清单见 `apps/<App>/store/cn.md`。

### 4.4 32 位 / 64 位

- TCL 电视只有 `armeabi-v7a`,所以 APK 必须含 32 位。
- 手机商店要求 64 位;Compose 的 `libandroidx.graphics.path.so` 已同时带
  `arm64-v8a` / `armeabi-v7a` / x86 / x86_64,默认 universal APK 就够。
- 如果某个商店只收「32 位包」或对体积有硬限制,再考虑按 ABI 拆包
  (需要给 `build.gradle.kts` 加 `splits.abi`,目前**没有默认开启**)。

---

## 5. 常见拒收原因(按出现频率)

| 现象 | 原因 | 本地怎么提前发现 |
|---|---|---|
| Play 直接拒绝上传 | `targetSdk` 低于当年门槛 | `store-preflight.sh --target play` |
| 上传报「包名无效」 | `com.example.*` | 同上 |
| 装不上/覆盖失败 | 签名和线上不一致 | `gen-keystore.sh --verify-against <apk>` |
| AAB 上传被拒 | 未签名 / 缺 64 位 | `jarsigner -verify` + preflight |
| 审核要隐私政策 | 没填 URL / URL 打不开 | `store/play.md` 的 TODO |
| 国内商店要软著/备案 | 资质没备齐 | `store/cn.md` 的 TODO |
| TV 商店不收 | 缺 banner / 横屏 / D-pad | 真机 `tv-install.sh` + 遥控遍历 |

---

## 6. 回归检查

每次上架前至少跑:

```bash
bash tools/store-preflight.sh <version>            # 技术项
cd apps/<App> && ./gradlew testDebugUnitTest       # 布局回归
bash tools/verify-all.sh --build-only              # 工具链没坏
```

真机验收(TV / Pico)按 [AGENTS.md](../AGENTS.md) §4 的文本验收流程做 ——
**不要用截图判电视界面变化**(原因见 docs/03)。
