# 10 · Android 开发 Agent Skills 的集中管理

> 状态：已落地；调研与首版技能集快照：2026-10-22。
>
> 目标：**在这台机器上装一次，所有 Android 项目都能用**同一套经过筛选的
> Android 开发技能；上游变化可以自动检查、以 PR 形式审阅，而不是每个项目
> 各复制一份、各自过期。

## 为什么需要它

Agent Skills 是「给 AI 编码智能体看的操作手册」：一个目录里放 `SKILL.md`，
agent 启动时只加载 `name` / `description`，命中任务时才读正文和 `references/`。
格式是开放的，见 [agentskills.io](https://agentskills.io/)。

问题在于**技能放哪儿、谁来更新**。如果每个 Android 项目都往自己的
`.agents/skills/` 里抄一份，就会出现：

- 同一个技能在不同项目里版本不同，修好的坑在新项目里又出现；
- 上游更新了 API / 最佳实践，没人知道；
- 技能目录里混进项目私有的设备地址、脚本和约定，没法复用。

所以这里采用和 [EasyApple](https://github.com/EasyIndie/EasyApple) 相同的思路：
**仓库集中维护 → 安装到用户级共享目录 → 所有项目复用**。区别是 Android
这边官方已经有一个高质量技能库，我们不需要从零写。

## 调研与选型

### 判据

不是按 star 数直接收，而是同时看五件事：

1. **来源可信**：优先 Google / Android 官方组织，其次是长期维护的社区库；
2. **许可明确**：必须能合法复制和再分发（Apache-2.0 / MIT）；
3. **仍在维护**：2026 年有提交，不是归档项目；
4. **不重复**：同一主题优先官方技能，社区技能只补官方明确不覆盖的部分；
5. **可独立安装**：符合 Agent Skills 格式（有 `SKILL.md` + frontmatter），
   不依赖某个特定 IDE 或私有运行时。

> star 数只是「社区认可度」的信号，不是质量证明。下表是 2026-10-22 的快照，
> 以后会变；复核命令在文末。

### 候选对比

| 候选 | 认可度信号（2026-10-22） | 许可 | 结论 |
|---|---|---|---|
| [android/skills](https://github.com/android/skills) | Google / Android 官方；9.1k star；33 个技能；2026-10-21 仍在更新 | Apache-2.0 | ✅ **全量收录**，作为官方层 |
| [new-silvermoon/awesome-android-agent-skills](https://github.com/new-silvermoon/awesome-android-agent-skills) | 984 star；17 个技能；2026-07 更新 | Apache-2.0 | ✅ **收录 13 个**，补架构 / 协程 / 网络 / Gradle / 无障碍 |
| [Kotlin/kotlin-agent-skills](https://github.com/Kotlin/kotlin-agent-skills) | Kotlin 官方组织；1.1k star；2026-10 更新 | Apache-2.0 | ❌ 不收录：偏 Kotlin 工具链迁移，和本仓库锁定的 AGP/Kotlin 组合冲突；AGP 升级已由官方 `agp-9-upgrade` 覆盖 |
| [skydoves/compose-performance-skills](https://github.com/skydoves/compose-performance-skills) | 517 star；25 个 Compose 性能技能；2026-06 更新 | Apache-2.0 | ❌ 不收录：与官方 `jetpack-compose-performance` 重叠；需要更深的 Compose 性能时可单独装 |
| [aldefy/compose-skill](https://github.com/aldefy/compose-skill) | 597 star；单技能 3.7 MB | MIT（GitHub 标 NOASSERTION） | ❌ 不收录：体量大且与官方 Compose 技能重叠 |
| [dpconde/claude-android-skill](https://github.com/dpconde/claude-android-skill) | 346 star；2025-12 更新 | MIT | ❌ 不收录：架构内容与已收录的 3 个 awesome 架构技能重叠 |
| [SimoneAvogadro/android-reverse-engineering-skill](https://github.com/SimoneAvogadro/android-reverse-engineering-skill) | 8.2k star | Apache-2.0 | ❌ 不收录：逆向工程不在本仓库「开发实践」的范围 |
| [google/skills](https://github.com/google/skills) | Google 官方通用技能库；21k star | 见仓库 | ➖ 只作为交叉参考：Android 专用技能以 `android/skills` 为准 |

### 为什么是这 46 个上游技能

`android/skills` 的 33 个技能覆盖了官方认为「LLM 容易做不好」的领域：AGP 9 升级、
CameraX、Media3 Cast、Navigation 3、边缘到边缘、权限 / Intent 安全、R8、
ANR、Profiler、Compose 性能、TV / Wear / XR / Auto、端侧 AI、Play 等。
它们本身就是**按任务拆分的**，不是一份大文档，适合直接作为集合维护。

社区层只补官方明确不覆盖的日常工程能力。`awesome-android-agent-skills`
有 17 个技能，我们排除了 4 个与官方重叠的：

| 排除的社区技能 | 被谁覆盖 |
|---|---|
| `android-testing` | 官方 `testing-setup` |
| `compose-performance-audit` | 官方 `jetpack-compose-performance` |
| `navigation3`（目录名 `compose-navigation`） | 官方 `navigation-3` |
| `xml-to-compose-migration` | 官方 `migrate-xml-views-to-jetpack-compose` |

最终：**33 个官方 + 13 个社区 + 1 个本仓库维护 = 47 个技能**。
本仓库维护的是 [`android-device-ops`](../.agents/skills/android-device-ops/SKILL.md)，
它绑定 `tools/` 里的真机脚本，不属于通用集合，所以单独放在 `localSkills` 里。

## 目录与配置

```
.agents/
├── skills.config.json           # 唯一配置：sources / profiles / agents / localSkills
├── skills-sources.lock.json     # 生成文件：每个上游技能对应的 repository + commit
└── skills/
    ├── android-device-ops/      # 本仓库维护（localSkills）
    ├── android-cli/             # 上游复制（android/skills）
    ├── android-architecture/    # 上游复制（awesome-android）
    └── ...
```

规则：

- **`skills.config.json` 是唯一入口。** 要加/减上游技能，改 `sources` 的
  `include` / `exclude`，然后跑更新脚本；不要手工往 `.agents/skills/` 里拷。
- **`skills-sources.lock.json` 是生成文件。** 它记录每个技能的来源仓库、
  相对路径、许可证和 commit，用来回答「这个技能是从哪一版来的」。
- **上游技能目录不要手改。** 下一次更新会覆盖。项目特定的内容写到
  `localSkills` 里的本地技能目录。
- 每个上游技能目录都带一份 `LICENSE` / `LICENSE.txt`，复制时一并保留。

## 安装：一次装好，所有项目可用

```bash
# 默认：profile=core -> ~/.agents/skills
bash tools/install-agent-skills.sh

# 换集合
bash tools/install-agent-skills.sh --profile tv
bash tools/install-agent-skills.sh --profile easyandroid

# 看有哪些集合 / 每个集合多少个技能
bash tools/install-agent-skills.sh --list

# 只检查，不写文件（适合收尾 / CI）
bash tools/install-agent-skills.sh --check

# 移除本脚本创建的链接或副本（不会碰别人装的同名技能）
bash tools/install-agent-skills.sh --profile core --uninstall
```

同名技能已存在且不是本脚本建的链接/副本时**拒绝覆盖**；`--force` 也只替换链接或
本脚本的副本，不会删真实目录。如果之前用 `android skills add` 装过官方技能，先清掉
`~/.agents/skills/<name>` 里的同名真实目录，或改用 `--target` 装到另一个目录。

`~/.agents/skills` 是 Agent Skills 的标准位置，**Codex / pi / VS Code Copilot /
Cursor 都会发现它**；这也是默认只装一份的原因。需要额外装给 Claude Code、
Gemini / Antigravity 时：

```bash
bash tools/install-agent-skills.sh --agent claude
bash tools/install-agent-skills.sh --agent antigravity
bash tools/install-agent-skills.sh --agent all
```

agent 路径写在 `skills.config.json` 的 `agents` 里，可用 `--target` 覆盖。
不同版本的 agent 可能改目录，遇到「装了但没发现」先用 `--target` 指到它实际
读取的目录。

### 项目级安装

有些项目希望把技能版本钉在仓库里（而不是跟着用户级目录漂移）：

```bash
cd /path/to/android-app
bash /path/to/EasyAndroid/tools/install-agent-skills.sh \
  --scope project --profile core
# -> /path/to/android-app/.agents/skills/
```

项目级目录里的 `.agents/skills` 会被提交到那个项目自己的仓库，适合团队统一。
注意：安装脚本默认做**符号链接**，项目级安装会链接回 EasyAndroid 的路径；
如果不希望项目依赖 EasyAndroid 的位置，加 `--copy`。

### 链接、junction 与副本

| 平台 | 默认行为 |
|---|---|
| WSL2 / Linux / macOS | `ln -s` 符号链接 |
| Windows 原生（Git Bash） | 先试目录 junction（`mklink /J`，不需要管理员）；失败再试 `ln -s`；都失败则复制 |
| 复制模式 | 目录里写 `.easyandroid-skill` 标记；重跑 install 会刷新副本 |

> ⚠️ **WSL 和 Windows 的 `$HOME` 不是同一个目录。** 在 WSL 里跑默认装到
> `/home/<user>/.agents/skills`，Windows 上的 agent 看不到。想让 Windows 侧的
> pi / Copilot 用，请在 Git Bash 里跑，或用 `--target` 指到
> `C:\Users\<你>\.agents\skills` 对应的路径。

## profile：默认不要装「全部」

agent 启动时会加载每个技能的 `name` + `description`。47 个技能全装不是不能跑，
但会占掉不必要的上下文，也更容易触发相近技能。所以默认 `core` 只装 17 个
日常最常用的：

| profile | 内容 | 适合 |
|---|---|---|
| `core`（默认） | 架构、Compose、协程、网络、测试、安全、性能、构建 | 任意 Android 项目 |
| `compose` | core + 样式、XML 迁移、Navigation 3、Coil | Compose 为主的项目 |
| `perf` | core + Profiler | 性能排查 |
| `kotlin` | core + Kotlin 协程、RxJava 迁移、Gradle 逻辑 | Kotlin 工程化 |
| `devices` | core + 真机操作 + 官方模拟器技能 | 需要装包 / 验收 |
| `tv` | core + Leanback 迁移 + Media3 Cast + 真机操作 | Android TV |
| `xr` | core + Glimmer Compose + 投射硬件 | XR / 智能眼镜 |
| `wear` / `cars` / `media` / `ai` / `identity` / `play` / `build` / `system` | 对应官方技能包 | 对应领域 |
| `easyandroid` | `devices` + 电视 / Media3 | 本仓库 |
| `all` | 47 个全部 | 探索 / 审查，不建议日常 |

完整列表和每个集合的技能数：`bash tools/install-agent-skills.sh --list`。

> 本仓库自己的 `.agents/skills/` 是完整目录，所以**在 EasyAndroid 仓库里**工作的
> agent 会看到全部 47 个技能；其他 Android 项目通过安装脚本只拿 profile 选中的子集。
> 这是有意的：维护技能集的人需要看到全部，日常项目不需要。

## 自动更新

### 本地

```bash
bash tools/update-agent-skills.sh             # 同步到当前工作树
bash tools/update-agent-skills.sh --dry-run   # 只拉上游、报告数量，不写盘
bash tools/update-agent-skills.sh --check     # 上游有变化时退出码 1
```

它做四件事：

1. 按 `sources` 克隆每个上游的默认分支；
2. 按 `include` / `exclude` 挑技能；
3. 复制到 `.agents/skills/<name>/`（带许可证）；
4. 写 `skills-sources.lock.json`（每个技能的 commit）。

如果上游删除了某个技能，旧目录会从工作树移除；本地技能（`localSkills`）不会被碰。
上游技能重名、本地技能与上游重名、缺少 `SKILL.md` / 许可证，都会在落盘前报错。

### GitHub Actions

[`.github/workflows/update-agent-skills.yml`](../.github/workflows/update-agent-skills.yml)
每周一检查一次。有变化时它：

- 更新 `.agents/skills/` 和 lock；
- 跑 `bash tools/verify-all.sh --skills-only`；
- **创建一个待审 PR**（分支 `automation/update-android-agent-skills`），不直接改 `main`。

合并前请人工看 diff —— 尤其注意上游是否新增了可执行脚本；
本仓库的安装脚本不会执行技能里的脚本，但 agent 在任务中可能会。

> 首次使用需要在仓库 **Settings → Actions → General → Workflow permissions**
> 允许 GitHub Actions 创建 Pull Request，否则 `GITHUB_TOKEN` 只能推分支、
> 不能开 PR。这个流程不需要额外 secret。

## 验证

```bash
# 只验 CI 配置 + 技能集（不碰 JDK / SDK / 设备，CI 和本机同一份判据）
bash tools/verify-all.sh --skills-only
```

> Windows 原生如果只有 `python` 没有 `python3`，把下面手工命令里的 `python3`
> 换成 `python`；三个脚本内部都用 `_common.sh` 探测，不受影响。

`skills_config.py validate` 会检查：

- `skills.config.json` 能解析，profile 引用的技能都存在；
- `defaultProfile` / `defaultAgents` 指向已登记项；
- 每个 `.agents/skills/<name>/SKILL.md` 的 frontmatter `name` **等于目录名**，
  且 `description` 非空；
- 上游技能有 `LICENSE*`，lock 里的 source / repository / license 与 config 一致；
- 目录集合 == `localSkills` + lock 里的上游技能（防止「拷进来忘了登记」）；
- 没有重名技能、没有 `../` 路径。

`verify-all.sh --build-only`（CI 现有流程）也会跑这段，所以技能集坏了不会等到
发版才发现。

## 已知限制

- **默认只装 `core`。** 需要某个领域时显式 `--profile`，不要图省事装 `all`。
- **上游是「复制」不是「子模块」。** 复制才能让每个技能目录独立、可直接链接；
  代价是更新要在本仓库产生一次 diff，由 PR 审阅。
- **不自动合并上游更新。** 技能正文会影响 agent 的行为，必须有人看。
- **Windows 的链接可能退化成副本。** 副本不会自动跟随 `git pull`；重跑
  `install-agent-skills.sh` 会刷新。`--check` 会把「副本」标成 OK 并提醒。
- **agent 目录名会变。** `~/.agents/skills` 是目前覆盖面最广的约定；Claude /
  Gemini / Antigravity 的路径写在 config 里，版本不同就用 `--target`。
- **不收录逆向工程、破解类技能。** 不是本仓库的定位。

## 怎么复核

```bash
# 上游 HEAD 与 lock 是否一致（会联网）
bash tools/update-agent-skills.sh --check

# 本地配置 / lock / 目录是否自洽（不联网）
python3 tools/skills_config.py validate
bash tools/verify-all.sh --skills-only

# 看当前装了哪些 profile / agent
bash tools/install-agent-skills.sh --list
bash tools/install-agent-skills.sh --check

# 上游仓库的 HEAD（文档里的快照过期时用）
git ls-remote https://github.com/android/skills.git HEAD
git ls-remote https://github.com/new-silvermoon/awesome-android-agent-skills.git HEAD
```

## 更新记录

| 日期 | 变更 |
|---|---|
| 2026-10-22 | 初版：调研 8 个候选；收录 `android/skills` 33 个 + awesome 13 个 + 本地 1 个；加入 profile / 安装 / 周更 PR 流程 |
