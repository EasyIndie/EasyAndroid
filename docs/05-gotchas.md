# 05 · 踩坑速查

按「症状 → 原因 → 解法」组织。都是实际卡住过的问题。

---

## Windows 原生(Git Bash)跑脚本的四个坑

仓库脚本已跨平台(2026-09 起),`tools/_common.sh` 统一抹平了这些差异。
自己写新脚本时注意:

### 1. `timeout` 不是 GNU 那个

**症状**:`timeout 5 some-cmd` 报 `错误: 无效语法。默认选项不允许超过 '1' 次。`

**原因**:Git Bash 的 PATH 里 `C:\Windows\system32` 排在前面,`timeout` 命中的是
**Windows 自带的 timeout.exe**(语法是 `timeout /T 5`,而且它根本不是用来包命令的 ——
它是「等待 N 秒」的工具)。

**解法**:用 `_common.sh` 导出的 `run_timeout <秒> <命令>`。它只在确认拿到
coreutils 版(`/usr/bin/timeout` 或 `--version` 输出 coreutils)时才真的加超时,
否则退化为直接执行。

### 2. Windows 原生 python 不认 Git Bash 路径

**症状**:python 脚本报 `FileNotFoundError: '/e/EasyAndroid/...'`,
但 `ls /e/EasyAndroid/...` 明明存在。

**原因**:Git Bash 的 `/e/foo` 是 MSYS 虚拟路径,Windows 原生程序(python.exe、
aapt2.exe…)收到这种字符串按相对路径解析,必然失败。

**解法**:传给 python / 原生 exe 的路径一律过 `_common.sh` 的 `pyfile`(内部用
`cygpath -w` 转成 `E:\foo` 形式)。反过来,从 Windows 程序拿到的路径(`C:\...`)
在 bash 里用前先过 `posix_of`。

### 3. `mktemp` 报 Permission denied

**症状**:`mktemp` → `failed to create file via template '/tmp/tmp.XXXXXXXXXX'`。

**原因**:mktemp 的默认模板写死 `/tmp`,而部分 Windows 环境(沙箱/受限账号)下
`/tmp` 不可写。`TEMP` 变量指向的目录才是可写的。

**解法**:用 `_common.sh` 的 `mktmp` / `mktmpd`(它们以 `$TMP` 为模板前缀;
`$TMP` 的解析顺序是 `EASYANDROID_TMP` > 仓库 `.tmp/` > `$TEMP` > `/tmp`)。

### 4. sed 替换串里的 `&`

**症状**:想把 `com.example.dualdemo` 里的 `.` 转义,用了
`sed 's/[.[\*^$]/\\&/g'`,结果得到 `com&example&dualdemo`。

**原因**:sed 的**替换串**里 `&` 代表「整个匹配」,必须写成 `\&` 才是字面量。
匹配侧和替换侧的转义规则不同,混用必翻车。

**解法**:需要把字符串当正则用 → 用 `_common.sh` 的 `re_escape`(逐字符实现,
无歧义);需要**纯字面量替换** → 根本别用 sed,用 python 的 `str.replace`
(`new-app.sh` 里就是这么做的)。

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

### ⚠️ 反过来:`</dev/null` 会**覆盖**你要喂的 stdin

上面那条规则很容易被推成「凡是外部命令都加 `</dev/null`」—— 那就错了。
`< file` 和 `</dev/null` 都作用于 stdin,**后写的胜**:

```bash
$ cat < /tmp/in.txt </dev/null | wc -c
0                     ← 6 字节的文件被 /dev/null 盖掉了,而且不报错
$ cat < /tmp/in.txt | wc -c
6
```

实测踩到:把签名凭据写进 GitHub Secret 的那行

```bash
gh secret set KEYSTORE_B64 < "$tmpf" </dev/null    # ✗ secret 被设成空值
gh secret set KEYSTORE_B64 < "$tmpf"               # ✓
```

`gh` 安安静静读完 `/dev/null` 报成功,secret 却是空的 —— CI 只能通过**产物**才能发现
(产出的还是 `app-release-unsigned.apk`)。

**判断标准:这条命令需不需要从 stdin 拿数据?**

| 需要吗 | 例子 | 怎么办 |
|---|---|---|
| 不需要,只是会意外吞掉 | `adb shell` | 加 `</dev/null` |
| **需要**(从 stdin 读值 / 管道输入) | `gh secret set` / `tar -T -` / `patch` | **千万别加** |

拿不准就先不加,并在脚本里手动确认一次行为。

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
[03-tcl-tv-sideload.md](03-tcl-tv-sideload.md#怎么从-ui-树里取当前焦点项和文件版本)。

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

## 在 WSL 的 `/mnt/e` 上开发,文件可执行位会丢

**症状**:本地 `./gradlew` 跑得好好的,推到 CI 就 `./gradlew: Permission denied`。

**原因**:两层叠加。

1. drvfs(`/mnt/e` 这种 Windows 盘挂载)**不支持 chmod** —— 所有文件都显示 `-rwxrwxrwx`,
   `chmod +x` 是空操作。
2. 所以仓库里设了 `git config core.filemode false`(否则 git 会把每个文件都当成
   可执行,到处是噪音 diff)。但这样一来 **git 也永远不会检测到可执行位的变化**,
   于是 `gradlew` 是以 `100644`(非可执行)被提交的。

**症状确认**:

```bash
git ls-files -s | grep gradlew
# 100644 apps/DualDemo/gradlew     ← 644 就是没有可执行位
```

**解法**:显式告诉 git 哪些文件要可执行,不依赖文件系统。

```bash
git update-index --chmod=+x apps/DualDemo/gradlew tools/*.sh
```

之后 `git ls-files -s` 应该显示 `100755`。

**注意**:在 WSL 里 `ls -l` 看到的永远都是 `rwxrwxrwx`,不能作为判断依据 ——
**只看 `git ls-files -s` 的模式位**。

> 这条是 CI 第一次跑就炸出来的:本地一切正常,Ubuntu runner 上直接
> `Permission denied`。凡是新增 `.sh` 脚本或 wrapper,记得补一次 `--chmod=+x`。

## Pico:不戴头显时会在 10 秒后自动休眠

**症状**:上一秒 `am start` / 自截图都正常,下一秒 `tools/ui-dump.sh` 报
`没有处于 resumed 状态的 Activity —— 应用在前台吗?`。或者按键「返回成功但没反应」。

**原因**:接近传感器判定没戴 → `mWakefulness=Asleep`、内置屏幕和面板都 `state OFF`。
和电视的屏保是**同一类问题的不同外衣**。

**解法**:

```bash
adb shell input keyevent KEYCODE_WAKEUP
adb shell setprop pvr.factorytest.never.sleep 1     # 非持久,重启自动恢复,无副作用
```

`svc power stayon true` / `stay_on_while_plugged_in=7` / `persist.pvr.sleep_by_static=0` **都没用**,已逐个实测排除。

完整复现步骤见 [04-pico4-notes.md](04-pico4-notes.md#不戴头显时会在-10-秒后自动休眠)。

---

## Pico:裸 `input keyevent` 到不了你的应用,必须加 `-d`

**症状**:`adb shell input keyevent KEYCODE_DPAD_DOWN` 不报错,界面也毫无反应。

**原因**:Pico 给**每个应用**建独立虚拟 display,而 `input` 默认打到 display 0(`com.pvr.vrshell`)。
而且那个 displayId **每次启动应用都变**,不能缓存。

**确认**:

```bash
adb shell logcat -d | grep 'Dropping key targeting non-focused display'
#   W WindowManager: Dropping key targeting non-focused display #24 keyCode=KEYCODE_DPAD_DOWN
```

**解法**:先现取 displayId,再定向注入。用脚本:

```bash
bash tools/pico-panel.sh <pkg> awake
bash tools/pico-panel.sh <pkg> key KEYCODE_DPAD_DOWN
```

原理和取 id 的两种写法见 [04-pico4-notes.md](04-pico4-notes.md#输入必须定向到应用自己的虚拟-display)。

---

## 电视屏保:偶发「所有按键全被吞掉」,要发指针事件

**症状**:`mWakefulness=Dreaming`、焦点是 `com.tcl.appreciate.art/...DreamActivity`。
`KEYCODE_WAKEUP / BACK / HOME / DPAD_CENTER / POWER` 连发 15 秒**全部无效**,
`am start` 依然静默失败,`uiautomator dump` 只能拿到屏保自身那些没 `text` 的节点。
→ `tv-install.sh` 的列表匹配永远不中,报「安装失败」且「当前界面」为空。

**解法**:补一个**指针事件**(TCL 的遥控是 IR 触控,屏保只认指针,不认按键):

```bash
adb -s $TV shell input tap 960 540      # 960 540 = wm size 的一半
```

`tv-install.sh` 的 `reset_ui_state()` 已加上这个兜底(只在确实还是 Dream 时才发)。

> 更常见的屏保态下 `WAKEUP` + `HOME` 是**能**唤醒的 —— 静置到屏保 205 秒、
> 长按 `POWER` 再进屏保都复现不出那个卡死态,所以这是防御性代码。
> 完整记录见 [03-tcl-tv-sideload.md](03-tcl-tv-sideload.md#屏保还有第二种形态按键完全被吞掉)。

---

## 电视上「截图变了」不能当作「输入生效」的证据

**症状**:用 `screencap` 前后对比来验证按键/点击是否生效,发现**每次都“生效”**。

**原因**:TCL 桌面/设置里有时钟、天气、动效在自己跑。
实测停在设置页 **4 秒不发任何输入**,两张截图 md5 就不一样:

```
t0: UI 22 条 | e12da521   PNG 01a35984 (1406534B)
t1: UI 22 条 | e12da521   PNG ac333c80 (1518940B)   ← 无输入,md5 也变
```

**解法**:电视上判断「输入生效没」用 **UI 树的全量文案集合**(不是前几条),
不要用截图。

```bash
adb -s $DEV shell uiautomator dump /sdcard/x.xml
adb -s $DEV pull /sdcard/x.xml /tmp/x.xml
# 把全部 text/content-desc 拼成一个字符串取 md5,前后对比
```

| 操作 | 全量文案集合 | PNG md5 | 真实结果 |
|---|---|---|---|
| `input tap` 点「声音」 | **不变** | 变了 | ❌ 没生效 |
| `DPAD_DOWN` + `CENTER` | **变了** | 变了 | ✅ 生效 |

⚠️ **和 Pico 正好相反**:Pico 上文案集合拿不到(只能拿到 `com.pvr.vrshell` 的),
**只能**靠自截图的像素差。所以不要写一套「通用」的验收逻辑 —— 两台设备的信号是反的。
详见 [03](03-tcl-tv-sideload.md#电视上截图变了不能当作输入生效的证据)。

---

## 电视上的 `input tap` 基本不生效,一律用 `input keyevent`

实测(全量文案集合判定):TCL 桌面磁贴「我的应用」「设置」、设置左侧导航「声音」、
设置里的「高级设置」按钮 —— **四处 `input tap` 均无反应**,同位置用 `DPAD + CENTER` 均生效。

注意「高级设置」在 UI 树里**标了 `clickable="true"`**,照样没反应 ——
**不能靠 a11y 的 `clickable` 判断能不能 tap**。

> 但指针链路本身是通的:输入设备里有 `gIrTouch_Mouse`(IR 触控),
> 屏保就只认指针事件。只是 TCL 自有界面不把 touch 当 click。

## `uiautomator` 读不到不在视口里的列表项(LazyColumn / RecyclerView)

**症状**:界面上明明有的文案,`uiautomator dump` 出来的 XML 里就是找不到。
于是误以为「界面没渲染出来」或「这个元素不存在」,实际上它在屏幕下面。

**原因**:`LazyColumn` / `RecyclerView` **只组合当前视口附近的项**。
不在视口内的项压根没被创建,自然也不在无障碍节点树里 —— `uiautomator` 读的就是这棵树。

**症状确认**:同一界面按几下 D-pad 再 dump,次数会变。实测 DualDemo:

```
初始        : 24 条文案
按 25 次 ↓  : 25 条文案   ← 多出来的就是列表最后一项「共 18 项 · 构建 v0.0.1」
```

**解法**:先把目标项滚进视口,再 dump。批量按键一次发很快:

```bash
adb -s $DEV shell input keyevent 20 20 20 ... 20    # 20 = KEYCODE_DPAD_DOWN
adb -s $DEV shell uiautomator dump /sdcard/x.xml
```

> 这也会影响「用全量文案集合判变化」的做法:如果前后滚动了列表,
> 文案数量会变,那是**滚动**的功劳不是**输入生效**的功劳 —— 判断时要分清。

---

## 无线设备"睡醒后连不上"—— 要先 disconnect

**症状**:设备明明在线(ping 得通、5555 端口也开着),但 `adb devices` 里没有它,
或者状态是 `offline`。直接 `adb connect <addr>` 也没用。

**原因**:设备休眠/断网时 adb 里会留下一条过期记录。这时单发 `adb connect`
会被当成"已经连过了"而直接返回,状态并不会恢复正常。

**解法**:先断再连。

```bash
adb disconnect 192.0.2.29:5555
adb connect    192.0.2.29:5555
```

`tools/devices.sh` 已经这么做了 —— 状态不是 `device` 就先 disconnect 再 connect。
设备"连不上"时先跑它,而不是自己手敲 `adb connect`。

> 实测:Pico 4 休眠后就这样。ping 通、5555 开着,但 adb 那条记录是死的,
> 走一次 disconnect + connect 立刻恢复。

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

---

## Windows 上不要用 PowerShell 跑 `tools/` 的脚本

**症状**:

```powershell
PS E:\EasyAndroid\dist> bash tools/gen-keystore.sh --drill .\signing-bundle.b64 --record --label "飞书个人聊天(文件消息)"
/bin/bash: -c: line 1: syntax error near unexpected token `('
/bin/bash: -c: line 1: `/bin/bash tools/gen-keystore.sh --drill .\signing-bundle.b64 --record --label 飞书个人聊天(文件消息)'
```

**原因**:PowerShell 里的 `bash` 解析到的是 **WSL 启动器**
`C:\Windows\System32\bash.exe` —— 它**不是** Git 自带的
`C:\Program Files\Git\bin\bash.exe`。
启动器把收到的**所有参数拼成一整条 `bash -c` 字符串**再交给 WSL 解析。于是

- PowerShell 先把 `"…"` 的引号剥掉
- 启动器再把这些参数用空格拼起来,当作 shell 代码重新解析
- 括号、空格、`&`、`|`、`;`、`$()` 全部重新获得了 shell 语义

上面那条命令实际执行的是 `/bin/bash tools/gen-keystore.sh --drill … --label 飞书个人聊天(文件消息)`,
括号露在外面 → 语法错误。

**⚠️ 这不只是"报错",还是个注入面**:如果某个参数里有 `;` 或 `$(…)`,
**它会被真的执行**。

**还有第二个坑**:`.\signing-bundle.b64` 里的反斜杠在 bash 里是转义符,
`\.` 等于一个普通的 `.`,所以路径会变成 `.signing-bundle.b64`(少了斜杠),
报"找不到文件"。

### 怎么办

**首选:换一个真正的 bash 终端**,不要用 PowerShell。

- **WSL**:开始菜单 → Ubuntu,或者 `wsl` 命令进去,然后 `cd /mnt/e/EasyAndroid`
- **Git Bash**:右键 → Git Bash Here,然后 `cd /e/EasyAndroid`

两个终端里 `tools/` 的脚本都可以原样跑,路径用 `./` 或直接写文件名。

**非要在 PowerShell 里**:记住 `bash` 后面的东西会被重新当 shell 代码解析。实测的三条限制:

| 行为 | 实测结果 |
|---|---|
| `E:\EasyAndroid` 当工作目录 | ✅ 正确翻译成 `/mnt/e/EasyAndroid`(路径没问题) |
| 不带引号、**纯 ASCII** 的参数 | ✅ 可用 |
| 带引号 / 空格 / 括号的参数 | ❌ 语法错误(引号被剥掉) |
| 用 `$env:X` 传参给脚本 | ❌ **传不进 WSL**(实测为空),因为 WSL 默认只透传 `WSLENV` 里列出的变量 |
| **中文参数** | ❌ 被写成乱码(实测 `飞书文件消息` → `椋炰功鏂囦欢娑堟伅`) |

所以 PowerShell 里只有一种能用的写法:**参数全 ASCII、不加引号**。

```powershell
Set-Location E:\EasyAndroid
bash tools/gen-keystore.sh --drill dist/signing-bundle.b64 --record --label feishu-file
```

> ⚠️ 中文会被写成乱码而且**不报错**,只是安静地记错。`gen-keystore.sh`
> 现在会在 label 含非 ASCII 时提醒你确认显示是否正确,但根治办法是换终端。
> 跨 Windows shell 边界时,label 用 ASCII;要中文就开 WSL 或 Git Bash。

> 判断标准很简单:**参数里出现空格、括号、`&`、`;`、`$` 任何一个,就别在
> PowerShell 里跑。** 换终端比调引号省事,也更安全。
