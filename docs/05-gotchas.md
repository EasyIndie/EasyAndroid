# 05 · 踩坑速查

按「症状 → 原因 → 解法」组织。都是实际卡住过的问题。

---

## adb shell 会吞掉后续命令的输出

**症状**:脚本里连续写多条 `adb shell`,只有第一条有输出,后面全部消失;甚至 `echo` 都不打印。

**原因**:`adb shell` 在非交互环境下会占用 stdin,把脚本的输入流吃掉。

**解法**:每条 `adb shell` 都加 `</dev/null`。

```bash
# ✗ 会出问题
adb shell wm size
adb shell wm density

# ✓
adb shell wm size </dev/null
adb shell wm density </dev/null
```

封装成函数时也一样:

```bash
A(){ adb -s "$TV" shell "$@" </dev/null 2>&1; }
```

**另一个相关坑**:命令里带管道或分号时,`adb shell 'a; b | c'` 这种写法容易踩到
引用和转义问题。建议一条命令只做一件事,或者写成脚本 `adb push` 上去再执行。

---

## Gradle 并发拉依赖时报 TLS 握手失败

**症状**:首次构建失败,日志里大量

```
Could not resolve androidx.compose.ui:ui-text:1.7.6.
  > Could not GET 'https://dl.google.com/dl/android/maven2/...'
     > The server may not support the client's requested TLS protocol versions
        > Remote host terminated the handshake
```

**原因**:不是网络不通。同一时刻用 `curl` 和 `java` 直接请求同一个 URL 都是 **HTTP 200**。
是高并发拉取时被对端断连(限流)。

**解法**:降并发重跑,失败的部分会续上。

```bash
./gradlew assembleDebug --no-daemon --console=plain --max-workers=2
```

---

## cmdline-tools / platform-tools 解压后没有执行权限

**症状**:`sdkmanager: Permission denied`。

**原因**:`python3 -m zipfile`(以及某些解压方式)**不保留 Unix 可执行位**。

**解法**:

```bash
chmod +x /opt/android-sdk/cmdline-tools/latest/bin/*
chmod +x /opt/android-sdk/platform-tools/*
```

---

## cmdline-tools 目录结构摆错

**症状**:`sdkmanager` 找不到。

**原因**:zip 解压出来是 `cmdline-tools/{bin,lib,...}`,
但 sdkmanager 要求 `<sdk>/cmdline-tools/latest/bin/sdkmanager`。

**解法**:注意别把 `bin` 直接改名成 `latest`(会少一层)。

```bash
rm -rf /opt/android-sdk/cmdline-tools
mkdir -p /opt/android-sdk/cmdline-tools
mv cmdline-tools /opt/android-sdk/cmdline-tools/latest   # 正确
ls /opt/android-sdk/cmdline-tools/latest                 # 应看到 bin/ lib/ NOTICE.txt source.properties
```

---

## `apt install openjdk-17-jdk` 慢到超时

**症状**:`apt-get install` 跑了 900 秒被超时截断,`/usr/lib/jvm` 根本没建出来。

**解法**:别用 apt。直接从 Adoptium 下 tarball(实测 2.4 MB/s,190MB 约 80 秒)。

```bash
curl -L -o jdk17.tar.gz \
  "https://api.adoptium.net/v3/binary/latest/17/ga/linux/x64/jdk/hotspot/normal/eclipse"
```

---

## WSL2 mirrored 网络下 Windows adb server 起不来

**症状**:

```
* daemon not running; starting now at tcp:5037
could not read ok from ADB server
* failed to start daemon
error: cannot connect to daemon
```

而且**时好时坏** —— 因为那时它其实连到了 WSL 侧已有的 server。

**原因**:`.wslconfig` 里 `networkingMode=mirrored`,Windows 和 WSL 共享 localhost,
两边抢同一个 `127.0.0.1:5037`。

**解法**:Windows 侧固定用别的端口。

```bash
"$WINADB" -P 15037 start-server
```

详见 [02-adb-multi-device.md](02-adb-multi-device.md#-核心坑wsl2-mirrored-网络下只能有一个-adb-server)。

---

## `adb install` 收的是主机路径,`pm install` 收的是设备路径

**症状**:

```bash
adb install /data/local/tmp/t.apk
# adb: failed to stat /data/local/tmp/t.apk: No such file or directory
```

**原因**:`adb install` 的参数是**运行 adb 的那台机器**上的文件路径,它会自己 push 过去。
`/data/local/tmp/...` 是设备路径,主机上没有。

**解法**:

```bash
adb install -r ./local.apk                       # 主机路径
adb shell pm install -r /data/local/tmp/t.apk    # 设备路径(需先 push)
```

---

## 电视会自动进屏保,期间 `am start` 毫无反应

**症状**:`am start -n <某个 Activity>` 返回成功,但前台一直是
`com.tcl.appreciate.art/android.service.dreams.DreamActivity`,且**日志里没有任何 `ActivityTaskManager` 记录**。

**原因**:电视进了屏保(Dream)。

**解法**:先唤醒。

```bash
adb shell input keyevent KEYCODE_WAKEUP
adb shell input keyevent KEYCODE_HOME
```

判断是否在屏保:

```bash
adb shell dumpsys activity activities | grep -m1 mResumedActivity
# 看到 DreamActivity 就是在屏保
```

---

## 「解析包时出现问题」—— U 盘里的 macOS 资源叉文件

**症状**:在 TCL 的「应用安装」列表里选中一项后,安装器报 `解析包时出现问题 / 知道了`。

**原因**:列表里混进了 `._xxx.apk`。这是 macOS 在 FAT/exFAT 上生成的 **AppleDouble 资源叉文件**,
大小只有 4KB,不是合法 APK。

**解法**:不要盲按。**按应用标签匹配焦点项**再确认。实现见
[03-tcl-tv-sideload.md](03-tcl-tv-sideload.md#焦点项标签怎么取)。

---

## `/mnt/e` 下用 `mv` 搬目录导致 drvfs 缓存损坏

**症状**:搬完之后 `ls -la` 里那个目录显示成

```
d????????? ? ?    ?       ?            ? app
```

`cd`/`find` 全部报 `No such file or directory`,但**从 Windows 侧看文件完好无损**。

**原因**:WSL 的 drvfs 在跨目录 move(其实是 copy+delete)时的目录缓存失效。

**解法**(任选,都不用重启 WSL):

1. **改名刷新**(最轻):
   ```bash
   cmd.exe /c "move E:\path\app E:\path\appx"
   cmd.exe /c "move E:\path\appx E:\path\app"
   ```
   注意:改成新名字后 WSL 立刻能看见;但改回原名可能再次触发缓存,所以**如果反复出现,就换个名字用**。

2. **重挂挂载点**:
   ```bash
   umount -l /mnt/e && mount -t drvfs E: /mnt/e
   ```
   `-l` 是懒卸载,能在当前 shell 的 cwd 还在这个挂载点里时也成功。

3. **临时挂到别处绕开**(最安全,不动现有挂载):
   ```bash
   mkdir -p /mnt/e2 && mount -t drvfs E: /mnt/e2
   ```

**预防**:大目录不要 `mv`,用 `cp -r` + 校验 + `rm -rf`。

---

## Windows 上的 exe 被占用导致 `rm` 失败

**症状**:`rm: cannot remove 'adb.exe': Input/output error`。

**原因**:Windows 侧的 adb server 进程还开着,锁着 `adb.exe`。

**解法**:先杀进程。

```bash
cmd.exe /c "E:\path\adb.exe -P 15037 kill-server"
powershell.exe -NoProfile -Command "Stop-Process -Name adb -Force -ErrorAction SilentlyContinue"
```

---

## Activity 没导出 → shell 拉不起来

**症状**:

```
java.lang.SecurityException: Permission Denial: starting Intent { ... }
  from null (pid=9188, uid=2000) not exported from uid 10048
```

**原因**:`android:exported="false"` 的组件,即使带 intent-filter,外部 uid 也起不来。
`dumpsys package <pkg>` 里列出的组件**不代表它们是导出的** —— 要单独看 filter 定义。

**解法**:找同应用里**真正导出**的入口,或者走图形化路径(键控模拟用户操作)。

---

## Android 11+ 上 shell 读不了 `/sdcard/Android/data/`

**症状**:

```bash
adb -s $TV shell ls /sdcard/Android/data/com.example.app/files/
# ls: /sdcard/Android/data/com.example.app/files/: Permission denied
```

连 `run-as <pkg> ls /sdcard/Android/data/<pkg>/files/` 也是拒绝的。

**原因**:scoped storage。Android 11 起应用专属外部目录不再对其他 uid 开放,
`run-as` 虽然把 uid 切成了应用,但 SELinux 域是 `runas_app`,同样进不去。

**解法**:让应用**同时写一份到内部私有目录**,用 `run-as` 读:

```bash
adb exec-out run-as <pkg> cat files/out.png > out.png
```

应用私有目录 `/data/data/<pkg>/files/` 走 `run-as` 是通的(debuggable 应用)。
Pico 4 是 Android 10,外部目录可以直接 `adb pull`,所以两边行为不一样 ——
写代码时两个位置都写一份最省事。

## 用 `content query` 反查设备上的文件

排查时很有用的一招 —— 当 shell 不方便遍历目录时,通过 MediaStore 看文件:

```bash
adb shell content query --uri content://media/external/file \
  --projection _id:_data:mime_type --where "_data LIKE '%.apk'"
```

强制让新文件进库:

```bash
adb shell am broadcast -a android.intent.action.MEDIA_SCANNER_SCAN_FILE \
  -d file:///storage/XXXX-XXXX/AndroidTV/app.apk
```

> TCL 电视上正是靠这招发现了 U 盘的 `AndroidTV/` 目录,从而找到侧载通道。
