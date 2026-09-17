# 更新日志

本仓库的版本号与变更记录。**这个文件由 `tools/release.sh` 生成,不要手改** ——
内容来自 Conventional Commits 格式的提交历史。

版本号规则见 [docs/06-app-conventions.md](docs/06-app-conventions.md#版本号);
发版流程见 [README.md](README.md#发版)。

格式参考 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)。

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

