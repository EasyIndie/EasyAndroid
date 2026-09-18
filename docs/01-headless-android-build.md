# 01 · 无 IDE 的 Android 构建环境

结论:**Android Studio 不是必需的**。它没有提供任何拿不到的工具,内部调用的就是下面这套。
以 AI 为主力写代码时,命令行链路反而更顺。

代价是你会失去三样东西,需要知道怎么补:

| 失去的能力 | 替代方案 |
|---|---|
| 交互式断点调试器 / Layout Inspector | `adb logcat` 看堆栈;真要断点得手工 `adb jdwp` + `jdb`,很痛苦 |
| Compose/XML 实时预览 | **Roborazzi / Paparazzi**(JVM 上无设备渲染成 PNG);或 `adb exec-out screencap -p` 截真机 |
| Profiler | `adb shell dumpsys meminfo` / `am profile` |

---

## 1. 装 JDK 17

AGP 8.x 硬性要求 JDK 17。

```bash
mkdir -p /opt/jdk && cd /opt/jdk
curl -L -o jdk17.tar.gz \
  "https://api.adoptium.net/v3/binary/latest/17/ga/linux/x64/jdk/hotspot/normal/eclipse"
tar xzf jdk17.tar.gz && rm jdk17.tar.gz
ls -d /opt/jdk/jdk-17*          # → /opt/jdk/jdk-17.0.20.1+1
```

**不要走 `apt install openjdk-17-jdk`** —— 实测在部分环境里 apt 源很慢,一次 900s 超时都没装完,
而 Adoptium 直连稳定在 2.4 MB/s 左右。

### Windows 原生(Git Bash)

```powershell
winget install --id EclipseAdoptium.Temurin.17.JDK --exact
```

装到 `C:\Program Files\Eclipse Adoptium\jdk-17.0.20.101-hotspot`,和上面 Linux 侧是**同一个
版本号**(17.0.20.1+1)。MSI 会自动把 `JAVA_HOME` 与 `Path` 写进**系统**环境变量,所以:

- `JAVA_HOME` 的值末尾带一个反斜杠(`...\hotspot\`),这是 MSI 的习惯 —— 拼
  `"$JAVA_HOME/bin/keytool"` 照常可用,不用自己修。
- **已经开着的终端要重开**才能拿到新变量(进程环境是启动时的快照)。`tools/` 脚本对此有兜底:
  先看 `$JAVA_HOME`,再退回 PATH 里的 `keytool`,都没有就去 Windows 上的常见安装位置
  (`C:\Program Files\Eclipse Adoptium\jdk-17*` 等)自己找 —— 所以在没重开的终端里也能跑通。
  但直接敲 `java -version` 仍会失败,别被这个误导成「没装 JDK」。
- 装完自己验一下:
  ```bash
  keytool -help | head -2                                  # → 密钥和证书管理工具
  bash tools/gen-keystore.sh --status                      # → 应列出别名与 SHA-256 指纹
  ```

## 2. 装 Android cmdline-tools

```bash
cd /opt/android-sdk
curl -L -o ct.zip \
  https://dl.google.com/android/repository/commandlinetools-linux-16111833_latest.zip
python3 -c "import zipfile;zipfile.ZipFile('ct.zip').extractall('.')"
```

### ⚠️ 目录结构必须摆对

zip 解压出来是 `cmdline-tools/{bin,lib,NOTICE.txt,source.properties}`,
但 sdkmanager 要求的是 **`cmdline-tools/latest/bin/sdkmanager`**:

```bash
rm -rf /opt/android-sdk/cmdline-tools
mkdir -p /opt/android-sdk/cmdline-tools
mv cmdline-tools /opt/android-sdk/cmdline-tools/latest
chmod +x /opt/android-sdk/cmdline-tools/latest/bin/*   # ← 别忘这步
chmod +x /opt/android-sdk/platform-tools/*
```

**两个必踩的坑:**

1. **`python3 -m zipfile` 不保留 Unix 可执行位** → 不 `chmod +x` 就会 `Permission denied`。
2. 如果你把 `bin` 目录 `mv` 成了 `latest`,结构就变成 `latest/sdkmanager`(少一层),sdkmanager 找不到自己的 lib 会报错。
   正确结构是 `latest/bin/sdkmanager` + `latest/lib/`。

### Windows 原生(Git Bash)

```bash
SDK="/c/Users/<你>/AppData/Local/Android/Sdk"     # 就是 %LOCALAPPDATA%\Android\Sdk
mkdir -p "$SDK" && cd "$SDK"
curl -L -o ct.zip \
  https://dl.google.com/android/repository/commandlinetools-win-11076708_latest.zip
unzip -q ct.zip && rm ct.zip
# 同上的结构要求:bin/lib 必须落在 latest/ 里面
mkdir -p cmdline-tools/latest
mv cmdline-tools/bin cmdline-tools/lib cmdline-tools/NOTICE.txt cmdline-tools/source.properties \
   cmdline-tools/latest/
```

装到 `%LOCALAPPDATA%\Android\Sdk` 之后**不用设任何环境变量** —— `tools/_common.sh`
会自动探到它(见第 4 节)。

和 Linux 侧的三点不同:

- **用 `unzip` 解,别用 python** —— 不存在可执行位问题,也就不需要 `chmod +x`。
- **`--sdk_root` 必须写 Windows 形式**。`.bat` 是批处理脚本,认不得 `/c/...`:
  ```bash
  export JAVA_HOME='C:\Program Files\Eclipse Adoptium\jdk-17.0.20.101-hotspot'
  "$SDK/cmdline-tools/latest/bin/sdkmanager.bat" \
      --sdk_root='C:\Users\<你>\AppData\Local\Android\Sdk' \
      "platform-tools" "platforms;android-34" "build-tools;34.0.0"
  ```
  同一类坑在脚本里由 `bt_run` 统一兜住(它会把 `JAVA_HOME` 转成 Windows 形式),
  但**手工敲命令时得自己转**。
- **别绕 `cmd.exe /c`**:`MSYS_NO_PATHCONV=1` 下 `//c` 不会折成 `/c`(会当成路径)。
  从 Git Bash 里**直接执行 `*.bat`** 即可,路径给 POSIX 形式也行。

### sdkmanager 已被标记废弃

新版 cmdline-tools 启动时会警告:

```
WARNING: The SDK Manager CLI tool (sdkmanager) is deprecated.
Android CLI will be used instead. 'android sdk' is the replacement for 'sdkmanager'.
```

功能仍可用。想跟新版就用 `android sdk`。

```bash
yes | sdkmanager --licenses
sdkmanager "platform-tools" "platforms;android-34" "build-tools;34.0.0"
sdkmanager --list_installed
```

## 3. 装 Gradle

只需要**全局装一次**用来生成 wrapper,之后项目里用 `./gradlew` 即可。

```bash
mkdir -p /opt/gradle && cd /opt/gradle
curl -L -o g.zip https://services.gradle.org/distributions/gradle-8.11.1-bin.zip
python3 -c "import zipfile;zipfile.ZipFile('g.zip').extractall('.')"
chmod +x /opt/gradle/gradle-8.11.1/bin/*
```

在项目里生成 wrapper:

```bash
cd <project> && gradle wrapper --gradle-version 8.11.1 --no-daemon
```

## 4. 环境变量

放 `/etc/profile.d/android.sh`,并且挂到 `~/.bashrc`(否则非登录 shell 读不到):

```bash
export JAVA_HOME=/opt/jdk/jdk-17.0.20.1+1
export ANDROID_HOME=/opt/android-sdk
export ANDROID_SDK_ROOT=/opt/android-sdk
export PATH=/opt/android-sdk/cmdline-tools/latest/bin:/opt/android-sdk/platform-tools:$JAVA_HOME/bin:$PATH
```

```bash
echo '[ -f /etc/profile.d/android.sh ] && . /etc/profile.d/android.sh' >> ~/.bashrc
```

## 5. 项目骨架要点

版本组合(实测可用):AGP 8.7.3 + Kotlin 2.0.21 + Compose BOM 2024.12.01 + `androidx.tv:tv-material:1.0.0`。

`local.properties` 写 SDK 路径(且要 gitignore,因为它是机器相关的):

```properties
sdk.dir=/opt/android-sdk
```

### 一个 APK 同时上 TV 和手机/VR

`AndroidManifest.xml` 的关键三点:

```xml
<!-- 不强制要求 leanback,否则 Pico 装不上 -->
<uses-feature android:name="android.software.leanback" android:required="false" />
<uses-feature android:name="android.hardware.touchscreen" android:required="false" />

<application android:banner="@drawable/banner" ...>
    <activity android:name=".MainActivity" android:exported="true">
        <intent-filter>
            <action android:name="android.intent.action.MAIN" />
            <!-- TV 桌面靠这条才会列出应用 -->
            <category android:name="android.intent.category.LEANBACK_LAUNCHER" />
            <!-- 手机/VR 的应用列表靠这条 -->
            <category android:name="android.intent.category.LAUNCHER" />
        </intent-filter>
    </activity>
</application>
```

- `android:banner` 必须是 **320×180** 的图片,否则 TV 桌面那一行会显示成空白
- `leanback` 写 `required="true"` 会让没有 leanback 的设备(如 Pico)拒绝安装

### 关于 ABI

如果工程里**没有 native 代码**,APK 是架构无关的,不需要配 `abiFilters`。
但注意传递依赖可能带 `.so` —— 例如 `androidx.compose.foundation` 会带进来
`libandroidx.graphics.path.so`,AGP 默认会把**所有** ABI 都打进去:

```
lib/arm64-v8a/libandroidx.graphics.path.so
lib/armeabi-v7a/libandroidx.graphics.path.so
lib/x86/...
lib/x86_64/...
```

只要目标设备所需的 ABI 在里面就能跑。想瘦身可以在打包后用 `--abi` 或 `splits` 处理。

**反过来要注意**:如果某台设备只支持 32 位(见 [02](02-adb-multi-device.md) 里的 TCL 电视),
而你依赖的某个 SDK **只发布了 arm64-v8a**,那台设备就直接出局了 —— 这个必须在选型阶段确认。

## 6. 构建

```bash
./gradlew assembleDebug
# → app/build/outputs/apk/debug/app-debug.apk
```

**首次构建会拉 AGP / Kotlin / Compose,约 3 分钟。**

如果遇到 TLS 握手失败(见 [05-gotchas](05-gotchas.md#gradle-并发拉依赖时报-tls-握手失败)),降低并发:

```bash
./gradlew assembleDebug --no-daemon --console=plain --max-workers=2
```

## 7. 网络

实测在国内直连 `dl.google.com` 和 `services.gradle.org` 都是 200 且很快

| 源 | 结果 |
|---|---|
| `dl.google.com/android/repository/...` | 200,0.28s |
| `services.gradle.org/distributions/` | 200,1.38s |

**不需要配国内镜像**。如果哪天不通了,再考虑
`mirrors.cloud.tencent.com/gradle/` 和 `maven.aliyun.com/repository/google`。
