# 更新日志

本仓库的版本号与变更记录。**这个文件由 `tools/release.sh` 生成,不要手改** ——
内容来自 Conventional Commits 格式的提交历史。

版本号规则见 [docs/06-app-conventions.md](docs/06-app-conventions.md#版本号);
发版流程见 [README.md](README.md#发版)。

格式参考 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)。

## [0.6.0](https://github.com/EasyIndie/EasyAndroid/compare/0.5.0...0.6.0) - 2026-11-20

### 新增

- **apps**: OrzMusic 品牌图标、TV banner 与商店物料 ([596ce32](https://github.com/EasyIndie/EasyAndroid/commit/596ce32))
- **apps**: OrzMusic 10-foot 视觉与输入重做 —— 自绘图标、独立声场面板、系统输入法 ([282431d](https://github.com/EasyIndie/EasyAndroid/commit/282431d))
- **apps**: 接入 MediaSession 后台播放、真实 PCM 声场并兜底 Pico 焦点 ([5d86780](https://github.com/EasyIndie/EasyAndroid/commit/5d86780))
- **apps**: 新增 OrzMusic Android 客户端 ([5a1085d](https://github.com/EasyIndie/EasyAndroid/commit/5a1085d))
- **apps**: 新增正式应用 EasyInfo 与 A/B/C 上架链路 ([d95f696](https://github.com/EasyIndie/EasyAndroid/commit/d95f696))
- **skills**: 集中管理 Android 开发技能集合并支持自动更新 ([369a78f](https://github.com/EasyIndie/EasyAndroid/commit/369a78f))
- **tools**: png-rowpitch.py —— 从截图量文字行距,把「字号有没有变」变成数字 ([692959c](https://github.com/EasyIndie/EasyAndroid/commit/692959c))
- **verify-all**: 新增仓库自检段,盯 CI 的 action 主版本与 runner pin ([c8cb46d](https://github.com/EasyIndie/EasyAndroid/commit/c8cb46d))

### 修复

- **tools**: ui-dump 在电视上取到截断的 PNG —— 等到 IEND 再 pull ([8d7ed21](https://github.com/EasyIndie/EasyAndroid/commit/8d7ed21))
- **docs**: U 盘「二级目录」挡不住安装器扫描;要改的是后缀不是位置 ([22b688a](https://github.com/EasyIndie/EasyAndroid/commit/22b688a))
- **tv-install**: 缓存里的失效条目会让人「装了个寂寞」;装完还要比字节数 ([38857bd](https://github.com/EasyIndie/EasyAndroid/commit/38857bd))
- **tv-install**: 安装确认框的按钮没有焦点,盲按键必然装不上;标签匹配漏掉中文名 ([a9d7355](https://github.com/EasyIndie/EasyAndroid/commit/a9d7355))
- **tv-install**: 给「等列表稳定」加墙钟上界,屏保下不再磨 36 分钟且不报原因 ([e3d6263](https://github.com/EasyIndie/EasyAndroid/commit/e3d6263))
- **ui-dump**: 取到空图时换通路重试并报出设备端大小,不再只说'文件是空的' ([18aa0bc](https://github.com/EasyIndie/EasyAndroid/commit/18aa0bc))
- **tools**: Pico 段漏转路径 + 电视安装失败被误报成「装到旧版」 ([3c630fc](https://github.com/EasyIndie/EasyAndroid/commit/3c630fc))
- **tools**: 装好 Android SDK 后才暴露的 5 处问题 ([f610ac3](https://github.com/EasyIndie/EasyAndroid/commit/f610ac3))
- **tools**: keytool 的路径参数要转换,证书到期时间解析忽略时区 ([c2c64d7](https://github.com/EasyIndie/EasyAndroid/commit/c2c64d7))
- **tools**: release-apk 写 local.properties 时没转 SDK 路径,Windows 上会构建失败 ([c2be768](https://github.com/EasyIndie/EasyAndroid/commit/c2be768))
- **tools**: 原生程序的路径必须显式转换 —— 新增 gitpath,修发版脚本 ([c1de196](https://github.com/EasyIndie/EasyAndroid/commit/c1de196))
- **keystore,ci**: 缺 JDK 时的三处误报,以及 --scan 在 Windows 上的全盘误报 ([fdda0a5](https://github.com/EasyIndie/EasyAndroid/commit/fdda0a5))

### 其他

- 文档按应用拆分，README/docs 完全通用化 ([eeeb98d](https://github.com/EasyIndie/EasyAndroid/commit/eeeb98d))
- **tools**: 测试应用移到 self-test，自检应用自动发现 ([b596155](https://github.com/EasyIndie/EasyAndroid/commit/b596155))
- **apps**: 删除 EasyInfo 原型 ([c2e109a](https://github.com/EasyIndie/EasyAndroid/commit/c2e109a))
- **publishing**: 补充上架流程索引与仓库约束 ([7fdcb07](https://github.com/EasyIndie/EasyAndroid/commit/7fdcb07))
- **template**: 把公共应用模板从 DualDemo 抽到 template/ ([069660b](https://github.com/EasyIndie/EasyAndroid/commit/069660b))
- **gotchas**: Session 0 读不到 Session 1 的凭据 —— gh 和 git push 会一起哑 ([d3fc2fd](https://github.com/EasyIndie/EasyAndroid/commit/d3fc2fd))
- **tv**: 页面改由 TV Bro 主页负责，去掉 .bashrc 里的自动打开 ([23d9ce1](https://github.com/EasyIndie/EasyAndroid/commit/23d9ce1))
- **tv**: 精炼方案 C 与全文结构 —— 剔掉过程残留，只留方案本身 ([c579a2a](https://github.com/EasyIndie/EasyAndroid/commit/c579a2a))
- **tv**: 日常操作一页纸 —— 打开 Termux 就把隧道和页面一起带出来 ([f202463](https://github.com/EasyIndie/EasyAndroid/commit/f202463))
- **tv**: launchd 起 herdr 会丢 direct_terminal_attach —— 用 script 套 PTY 恢复 ([e086b13](https://github.com/EasyIndie/EasyAndroid/commit/e086b13))
- **tv**: 重启实测后的三处修正 —— 隧道要自愈、ps -A 不能判重、pkill -f 会自杀 ([8563e6a](https://github.com/EasyIndie/EasyAndroid/commit/8563e6a))
- **tv**: 方案 C —— herdr 的 WebUI 走 SSH 隧道，实体键盘打中文实测打通 ([83a2f57](https://github.com/EasyIndie/EasyAndroid/commit/83a2f57))
- **dualdemo**: 加一个 debug-only 的 IME 探针,用来判断实体键有没有被交给输入法 ([bb654d5](https://github.com/EasyIndie/EasyAndroid/commit/bb654d5))
- **tv**: 更正 Termux 字号那节 —— 不是「设不了」,是必须存成字符串 ([219196b](https://github.com/EasyIndie/EasyAndroid/commit/219196b))
- **tv**: Termux 字号在电视上设不了 —— 五条路全部实测无效,能用的只有 wm density ([4c78ac5](https://github.com/EasyIndie/EasyAndroid/commit/4c78ac5))
- **tv**: 鼠标结论定案 —— 判据改成 SurfaceFlinger 的 type=CURSOR,截图不可靠 ([4b76f2c](https://github.com/EasyIndie/EasyAndroid/commit/4b76f2c))
- **tv**: 修掉重复的代码围栏 ([04c8a40](https://github.com/EasyIndie/EasyAndroid/commit/04c8a40))
- **tv**: 补「键盘 / 鼠标:接哪种、接哪个口」——实机验过三层证据 ([5a92cab](https://github.com/EasyIndie/EasyAndroid/commit/5a92cab))
- **gotchas**: 「命令报成功但结果不存在」的最阴一种 —— 设备掉线 + 输出被 /dev/null 吃掉 ([d95cd7f](https://github.com/EasyIndie/EasyAndroid/commit/d95cd7f))
- **docs**: 归档后缀 .apk.off → .apk.disabled(更自解释) ([8b2fd61](https://github.com/EasyIndie/EasyAndroid/commit/8b2fd61))
- **readme**: 「已沉淀的主题」加一行,指向 docs/09(电视当远程开发终端) ([779c5fd](https://github.com/EasyIndie/EasyAndroid/commit/779c5fd))
- **tv**: 把两套远程开发方案合写成 09-tv-remote-dev.md ([3ca9ca4](https://github.com/EasyIndie/EasyAndroid/commit/3ca9ca4))
- **tcl**: adb install 的拦截再验一遍;确认框必须用 tap;U 盘太肥才是「慢」的真因 ([c4f1c24](https://github.com/EasyIndie/EasyAndroid/commit/c4f1c24))
- **agents**: 补 D-pad 遍历的判据 —— 不 settle 会把「还在滚」误判成「焦点卡住」 ([1bdd00f](https://github.com/EasyIndie/EasyAndroid/commit/1bdd00f))
- 把 sort/find 抢 PATH 与 sed 单引号两个坑补进「Windows 原生跑脚本的坑」 ([b2c44c9](https://github.com/EasyIndie/EasyAndroid/commit/b2c44c9))
- **agents**: 补一条坑 —— 同一文件的多处修改并行发会静默丢改动 ([9517a0d](https://github.com/EasyIndie/EasyAndroid/commit/9517a0d))
- **agents**: 把 CI 的 runner 与 action 版本约束写进硬性规则 ([bd394ad](https://github.com/EasyIndie/EasyAndroid/commit/bd394ad))
- action 升到 Node 24 主版本,并把 runner 显式 pin 到 ubuntu-24.04 ([45d4f52](https://github.com/EasyIndie/EasyAndroid/commit/45d4f52))
- **agents**: 补沙箱里 git 写不进远端跟踪引用,并补全环境速查的两侧路径 ([c607e43](https://github.com/EasyIndie/EasyAndroid/commit/c607e43))
- 明确 debug 签名为「有意按环境各自持有」,不是待办 ([2970c2e](https://github.com/EasyIndie/EasyAndroid/commit/2970c2e))
- 补「debug 签名跨环境不一致」这一坑 ([9e54625](https://github.com/EasyIndie/EasyAndroid/commit/9e54625))
- 补 Windows 装 SDK、.bat 调用,以及三条「装了才暴露」的教训 ([3f8780a](https://github.com/EasyIndie/EasyAndroid/commit/3f8780a))
- 补 Windows 原生装 JDK 17 的方式 ([9ab8ea6](https://github.com/EasyIndie/EasyAndroid/commit/9ab8ea6))

## [0.5.0](https://github.com/EasyIndie/EasyAndroid/compare/0.4.4...0.5.0) - 2026-09-18

### 新增

- **keystore**: --label @文件 —— 绕开传不了中文的 shell 边界 ([529e83b](https://github.com/EasyIndie/EasyAndroid/commit/529e83b))
- **keystore**: --label 支持环境变量传入,并查清 PowerShell 里的真凶 ([b4815db](https://github.com/EasyIndie/EasyAndroid/commit/b4815db))
- **keystore**: --drill - 从 stdin 读,可以直接从聊天窗口粘进终端 ([8414d25](https://github.com/EasyIndie/EasyAndroid/commit/8414d25))
- **keystore**: 凭据包可以从聊天/邮件里粘回来直接验,并记录「那一份在哪」 ([633b4f4](https://github.com/EasyIndie/EasyAndroid/commit/633b4f4))

### 修复

- **keystore**: --scan 的「预期内」写死了文件名,与「导出用带日期的名字」这条建议矛盾 ([10920b7](https://github.com/EasyIndie/EasyAndroid/commit/10920b7))
- **keystore**: --manifest --write 不该抹掉 drill.* 演练记录 ([b7fcd1b](https://github.com/EasyIndie/EasyAndroid/commit/b7fcd1b))
- **keystore**: --scan 会漏掉改了名的凭据包;脚本退出码被最后一条命令吞掉 ([35448cd](https://github.com/EasyIndie/EasyAndroid/commit/35448cd))
- **keystore**: 更正 PowerShell 那节 —— 环境变量传不进 WSL,中文参数会变乱码 ([12cef35](https://github.com/EasyIndie/EasyAndroid/commit/12cef35))
- **keystore**: 导出折行 76 列 —— 单行长行粘进终端会被 MAX_CANON 静默截断 ([0036b73](https://github.com/EasyIndie/EasyAndroid/commit/0036b73))

### 其他

- **release**: 0.5.0 的发布说明(手写)—— 凭据可用性:演练/扫描/传输 ([84c37c8](https://github.com/EasyIndie/EasyAndroid/commit/84c37c8))
- **keystore**: 恢复 manifest 里的演练记录被测试覆盖掉的内容 ([9d8af8b](https://github.com/EasyIndie/EasyAndroid/commit/9d8af8b))
- **agents**: 明确 tools/ 的跨平台不含 PowerShell(WSL 启动器会把参数拼成 bash -c 重新解析) ([059062d](https://github.com/EasyIndie/EasyAndroid/commit/059062d))
- **keystore**: 飞书那份是**文件消息**形式,不是粘贴文本 —— 更正风险画像与验证步骤 ([75f3cba](https://github.com/EasyIndie/EasyAndroid/commit/75f3cba))

## [0.4.4](https://github.com/EasyIndie/EasyAndroid/compare/0.4.3...0.4.4) - 2026-09-17

### 修复

- **tools**: --print-notes 把进度和说明混在同一个 stdout,据此生成的 Release 正文是脏的 ([726579c](https://github.com/EasyIndie/EasyAndroid/commit/726579c))

## [0.4.3](https://github.com/EasyIndie/EasyAndroid/compare/0.4.2...0.4.3) - 2026-09-17

### 修复

- **tools**: 发布说明里的签名指纹在 CI 上是空的 —— 而且守护检查被空值骗过了 ([10a75a3](https://github.com/EasyIndie/EasyAndroid/commit/10a75a3))

## [0.4.2](https://github.com/EasyIndie/EasyAndroid/compare/0.4.1...0.4.2) - 2026-09-17

### 修复

- **changelog**: 归一化条目之间的空行,让 --backfill 真正幂等 ([ab3389e](https://github.com/EasyIndie/EasyAndroid/commit/ab3389e))
- **tools**: release.sh 重复打印了一次「✅ version.properties」 ([410a363](https://github.com/EasyIndie/EasyAndroid/commit/410a363))

## [0.4.1](https://github.com/EasyIndie/EasyAndroid/compare/0.4.0...0.4.1) - 2026-09-17

### 修复

- **tools**: 版本历史插入改为纯 bash,并补上写盘前后的校验 ([33f4750](https://github.com/EasyIndie/EasyAndroid/commit/33f4750))
- **tools**: --backfill 与发版插入的条目格式不一致(条目之间少一个空行) ([a6ff0ab](https://github.com/EasyIndie/EasyAndroid/commit/a6ff0ab))
- **tools**: 版本历史插错了位置(新条目落在列表最上面,而列表是旧→新) ([4a1a69c](https://github.com/EasyIndie/EasyAndroid/commit/4a1a69c))

## [0.4.0](https://github.com/EasyIndie/EasyAndroid/compare/0.3.0...0.4.0) - 2026-09-17

### 新增

- **tools**: 发版收成一条命令 —— 版本号从提交信息推导,CHANGELOG 自动生成 ([59d7d83](https://github.com/EasyIndie/EasyAndroid/commit/59d7d83))
- **tools**: 签名期望值文件 —— 指纹可以入库,而且应该 ([deff678](https://github.com/EasyIndie/EasyAndroid/commit/deff678))

### 修复

- **tools**: --push-secret 每跑一次都把一份完整凭据包漏在 .tmp/(+ 恢复演练/副本扫描) ([02ab23e](https://github.com/EasyIndie/EasyAndroid/commit/02ab23e))

## [0.3.0](https://github.com/EasyIndie/EasyAndroid/compare/0.2.0...0.3.0) - 2026-09-17

### 新增

- **ci**: 全自动发版 —— 推 tag 就由 CI 构建签名包并建 Release + 挂附件 ([db73d0c](https://github.com/EasyIndie/EasyAndroid/commit/db73d0c))
- **tools**: gen-keystore.sh --push-secret —— 一条命令配好 CI 的签名 secret ([d2656c8](https://github.com/EasyIndie/EasyAndroid/commit/d2656c8))
- **tools**: 支持「一个密钥库 + 每应用一个别名」,默认不再共用一把 ([5b2e258](https://github.com/EasyIndie/EasyAndroid/commit/5b2e258))
- **tools**: 签名凭据补全「获取 / 配置 / 核对」——导出、导入、机械比对 ([e586a2f](https://github.com/EasyIndie/EasyAndroid/commit/e586a2f))
- **tools**: 把「开发用 debug、发版才出正式包」变成机器校验 ([febe7e4](https://github.com/EasyIndie/EasyAndroid/commit/febe7e4))

### 修复

- **tools**: gh secret set 不能加 </dev/null,否则 secret 被设成空值 ([2719820](https://github.com/EasyIndie/EasyAndroid/commit/2719820))
- **tools**: gen-keystore 的 --import 改为「先验后写」,并统一指纹归一化 ([fc9c5b0](https://github.com/EasyIndie/EasyAndroid/commit/fc9c5b0))
- **tools**: ui-dump 认出「装的是正式包」,并直接给出换装命令 ([7c9faa3](https://github.com/EasyIndie/EasyAndroid/commit/7c9faa3))
- **tools**: ui-dump 的头显提示只在 Pico 上显示 ([ad9e0cf](https://github.com/EasyIndie/EasyAndroid/commit/ad9e0cf))
- **tools**: release-apk 的两个真 bug + 更正 win_of/winpath 的区分 ([cb1cdd2](https://github.com/EasyIndie/EasyAndroid/commit/cb1cdd2))

### 其他

- **tools**: new-app.sh 的「接下来」提示补上「首次发布前加签名别名」 ([1a535ed](https://github.com/EasyIndie/EasyAndroid/commit/1a535ed))

## [0.2.0](https://github.com/EasyIndie/EasyAndroid/compare/0.1.0...0.2.0) - 2026-09-17

### 新增

- **tools**: 正式版 APK 发布链路 —— release 签名 + 按 tag 构建 + 挂到 Release ([6ee194c](https://github.com/EasyIndie/EasyAndroid/commit/6ee194c))

### 修复

- **tools**: new-app.sh 拒绝多余参数,不再静默忽略 ([8f26ada](https://github.com/EasyIndie/EasyAndroid/commit/8f26ada))

### 其他

- **release**: 补 0.2.0 的版本历史注记;--bump 提醒同步更新它 ([8a428ac](https://github.com/EasyIndie/EasyAndroid/commit/8a428ac))
- 发版流程补「发布正式版 APK」;修正改版本流程里的错误命令 ([3972f80](https://github.com/EasyIndie/EasyAndroid/commit/3972f80))

## [0.1.0](https://github.com/EasyIndie/EasyAndroid/compare/0.0.1...0.1.0) - 2026-09-16

### 新增

- **tools**: 脚本跨平台改造,Windows 原生可用并真机全链路验证 ([8a28451](https://github.com/EasyIndie/EasyAndroid/commit/8a28451))

### 修复

- 补许可段、说清 win_of 的按需转换语义、device-status 清理改走 trap ([9e0f301](https://github.com/EasyIndie/EasyAndroid/commit/9e0f301))
- **ci**: 修正 build-tools 探测回归,设备项在 --build-only 下降级为警告 ([84e5ee6](https://github.com/EasyIndie/EasyAndroid/commit/84e5ee6))

### 其他

- add MIT LICENSE ([47106e2](https://github.com/EasyIndie/EasyAndroid/commit/47106e2))

## [0.0.1] - 2026-09-13

### 新增

- **tools**: tag-release.sh —— tag 名强制等于 version.properties 的 version ([e49e693](https://github.com/EasyIndie/EasyAndroid/commit/e49e693))
- 版本号唯一来源改为仓库根的 version.properties(SemVer) ([972ed06](https://github.com/EasyIndie/EasyAndroid/commit/972ed06))
- **tools**: pico-panel.sh —— 给 Pico 的 2D 面板定向注入按键/触摸 ([89049bf](https://github.com/EasyIndie/EasyAndroid/commit/89049bf))
- **test**: JVM 截图测试 —— 不碰设备看 UI ([391945e](https://github.com/EasyIndie/EasyAndroid/commit/391945e))
- 工具链自检脚本 + CI ([76bf19b](https://github.com/EasyIndie/EasyAndroid/commit/76bf19b))
- **tools**: tv-install.sh 装完自动截图;修复 Android 11 上取不到图 ([c088a1c](https://github.com/EasyIndie/EasyAndroid/commit/c088a1c))
- **debug**: 应用自截图钩子,让 FLAG_SECURE 设备也能被看见 ([dee13ba](https://github.com/EasyIndie/EasyAndroid/commit/dee13ba))
- 新工程约定 + 脚手架,并修正 TCL 安装链路 ([d75fcce](https://github.com/EasyIndie/EasyAndroid/commit/d75fcce))
- **agents**: 增加 AGENTS.md 与 android-device-ops skill ([a58c413](https://github.com/EasyIndie/EasyAndroid/commit/a58c413))
- **tools**: 新增 device-status.sh ([73f24cf](https://github.com/EasyIndie/EasyAndroid/commit/73f24cf))

### 修复

- **tools**: tag-release 的构建自检输出去重 ([cc9af60](https://github.com/EasyIndie/EasyAndroid/commit/cc9af60))
- **tools**: tv-install 收尾时清掉设备上的 /sdcard/_ui.xml ([76b2add](https://github.com/EasyIndie/EasyAndroid/commit/76b2add))
- **tools**: tv-install 的屏保唤醒加指针事件兜底 ([00f9cc4](https://github.com/EasyIndie/EasyAndroid/commit/00f9cc4))
- **tools**: verify-all 的 Pico 步骤漏了 --launch;devices 先 disconnect 再 connect ([a17787a](https://github.com/EasyIndie/EasyAndroid/commit/a17787a))
- **ci**: 补上 gradlew 和 tools/*.sh 的可执行位 ([42a59e1](https://github.com/EasyIndie/EasyAndroid/commit/42a59e1))
- **tools**: tv-install.sh 提速一倍,并查清哪些快速通道确实不存在 ([79f042d](https://github.com/EasyIndie/EasyAndroid/commit/79f042d))

### 其他

- 记录版本号的真机验证方法;补「列表项不在视口就等于不存在」 ([92eb933](https://github.com/EasyIndie/EasyAndroid/commit/92eb933))
- 版本号约定(唯一来源 / 严格 SemVer / 发版流程) ([5bddc13](https://github.com/EasyIndie/EasyAndroid/commit/5bddc13))
- 双设备能力摸底 —— Pico 输入定向/自动休眠,电视屏保吞键/tap 失效/截图不可信 ([bcd8dfe](https://github.com/EasyIndie/EasyAndroid/commit/bcd8dfe))
- 补开工/收尾清单;记录电视侧设置的还原 ([cd480da](https://github.com/EasyIndie/EasyAndroid/commit/cd480da))
- 修掉 docs/02 表格里被误解析成链接的 HDR 类型说明 ([da5ead8](https://github.com/EasyIndie/EasyAndroid/commit/da5ead8))
- 修掉 docs/08 里指向未创建文件的死链 ([f2ec557](https://github.com/EasyIndie/EasyAndroid/commit/f2ec557))
- 设备地址外置到 device.env,清除仓库内内网地址 ([3bc3497](https://github.com/EasyIndie/EasyAndroid/commit/3bc3497))
- 初始化 EasyAndroid 仓库 ([ef90b0c](https://github.com/EasyIndie/EasyAndroid/commit/ef90b0c))

