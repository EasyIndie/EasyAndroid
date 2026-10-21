# `.agents/skills/`

本目录是 EasyAndroid 维护的 Android Agent Skills 集合。

- **本地技能**：目录名登记在 `.agents/skills.config.json` 的 `localSkills` 里
  （当前是 `android-device-ops`）。可以手工编辑。
- **上游技能**：其余目录由 `bash tools/update-agent-skills.sh` 从
  `sources` 同步而来，**不要手改**；下次更新会覆盖。
  来源、commit 和许可证记录在 `.agents/skills-sources.lock.json`。

安装到用户级共享目录（所有 Android 项目可用）：

```bash
bash tools/install-agent-skills.sh              # 默认 core -> ~/.agents/skills
bash tools/install-agent-skills.sh --list       # 看全部 profile
bash tools/verify-all.sh --skills-only          # 校验配置 / lock / 目录
```

选型、profile 和自动更新流程见 [docs/10-agent-skills.md](../../docs/10-agent-skills.md)。
