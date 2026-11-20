# `apps/` —— 孵化区(当前为空)

应用在这里**创建 → 跑通 → 验收**,然后交付给业务仓库做后续迭代。
本仓库只负责孵化,不承担交付后的日常发版。

| 阶段 | 命令 | 说明 |
|---|---|---|
| 创建 | `bash tools/new-app.sh <App> <package.id>` | 从 `template/` 生成 `apps/<App>/` |
| 孵化 | `cd apps/<App> && ./gradlew assembleDebug` + `tools/` 的设备脚本 | 版本号暂取仓库根 `version.properties` |
| 交付 | `bash tools/handoff-app.sh <App> --check` | 审计跨仓引用 / gradlew 可执行位 / CRLF / 密钥泄漏 |
| 交付 | `bash tools/handoff-app.sh <App> --target <业务仓库> --prefix <子目录>` | 导出并补齐客户端必需的文件 |

已交付:

| 应用 | 仓库 | 客户端目录 |
|---|---|---|
| OrzMusic | [`OrzGeeker/OrzMusic`](https://github.com/OrzGeeker/OrzMusic) | `clients/android/` |

只是一次性验证 / 共用脚手架 → 放 `self-test/`,不要放这里(测试工程带
`selftest.properties`,`verify-all.sh` 会自动发现它们)。

> 本目录参与 `tools/release-apk.sh` 的扫描(`apps/*/publish.properties`),
> 所以留一个说明文件、不建空工程 —— 空目录不会被打包脚本误认成应用。
