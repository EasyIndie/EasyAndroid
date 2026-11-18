# OrzMusic 文档

应用专属文档放在这里。跨应用通用的知识(环境、设备、发版、上架流程)在仓库根
[`docs/`](../../../docs/)。

| 文档 | 内容 |
|---|---|
| [backend-api.md](backend-api.md) | OrzMusic 后端 API、三种播放策略、Android 客户端结构、实机验收记录 |
| [architecture.md](architecture.md) | 跨端架构:C/C++ / Swift / Web / Android 的 SDK 形态、`:core` / `:audio-kit` / `:app` 分层、server/clients 拆分与迁移计划 |
| [ui-parity.md](ui-parity.md) | 参考 Web 播放器的界面/功能映射、自适应规则、有意未搬的功能与验收方式 |
| [playback.md](playback.md) | MediaSession/后台播放/通知栏、PCM 声场、Pico BACK 焦点问题的定位与兜底 |

相关:

- [../README.md](../README.md) —— 构建 / 安装 / 功能 / 已知限制
- [../store/play.md](../store/play.md) / [../store/cn.md](../store/cn.md) —— 商店人工清单
- [../audio-kit/README.md](../audio-kit/README.md) —— Android 解码 SDK(AAR / JNI / manifest)
- [../THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md) —— 第三方许可证
