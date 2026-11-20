# 客户端仓外置:本仓库还剩什么、怎么跨仓复用

业务应用迁到各自的仓库以后(`OrzMusic` 已迁入
[`OrzGeeker/OrzMusic`](https://github.com/OrzGeeker/OrzMusic) 的 `clients/android/`),
本仓库的定位变成三件事:

1. **通用流程**(设备安装/验收、签名凭据、发版与上架的自检判据);
2. **`self-test/` + `template/`**(证明工具链没坏、给新应用起骨架);
3. **跨应用知识**(`docs/` 与 Agent Skills)。

`apps/` 现在是空的 —— 新应用请在自己的仓库里建,用 `tools/new-app.sh` 在本地起骨架再搬过去。

---

## 0. 交付:用 `handoff-app.sh`,别手工拷

```bash
bash tools/handoff-app.sh <App> --check                       # 先审计
bash tools/handoff-app.sh <App> --target ../<业务仓库> --prefix clients/android
```

它会:按 `git archive` 只导 tracked 文件 → 生成 `version.properties` / `CHANGELOG.md` /
`signing-manifest.txt` / `docs/migration-from-easyandroid.md` → 把文档里的
`../../docs/*` 与 `../../tools/*` 改写成跨仓可用的形式,并把做不了的事列成清单。

审计会挡住的四类问题(都是交付后才会炸的):

| 检查 | 为什么 |
|---|---|
| `gradlew` 的 git mode 不是 `100755` | Linux CI 直接 `Permission denied`(见 [05](05-gotchas.md)) |
| 脚本里有 CRLF | 同上,`bad interpreter` |
| 跟踪了 `local.properties` / `*.jks` / `build/` | 前者是别人的机器路径,后者是密钥/产物 |
| 代码里 `source ../../tools/...` | 交付后是死路径,构建直接失败 |

## 1. 设备流程:脚本吃路径,不需要复制

`tools/` 下的设备脚本**不假设应用在本仓库**:

| 脚本 | 入参 | 用在别的仓库时 |
|---|---|---|
| `tools/tv-install.sh` | APK 路径 | 直接传别的仓库构建出的 APK |
| `tools/ui-dump.sh` | `applicationId` + 可选设备 | 包名不变就能用 |
| `tools/pico-panel.sh` | `applicationId` + 动作 | 同上 |
| `tools/device-status.sh` | 设备 + 包名 | 同上 |
| `tools/devices.sh` | 无 | 看两台设备是否在线 |

```bash
EASYANDROID=/path/to/EasyAndroid
APK=/path/to/other-repo/app/build/outputs/apk/debug/app-debug.apk

bash "$EASYANDROID/tools/tv-install.sh" "$APK"
bash "$EASYANDROID/tools/pico-panel.sh" com.example.app awake
bash "$EASYANDROID/tools/ui-dump.sh" com.example.app
```

> 唯一要求是**设备上装的必须是 debug 包**(自截图钩子在 `src/debug/`),
> 见 [07](07-debug-ui-capture.md)。

## 2. 签名凭据:仍在这里生成,指纹跟着应用走

- 生成/导出/恢复演练:`tools/gen-keystore.sh`(见 [06](06-app-conventions.md#签名凭据存哪儿))。
- **每个应用一把别名**,同一个 `.jks` 里用 `alias.<App>` 区分。
- `signing-manifest.txt` 里只放公钥指纹 —— 应用迁走时,把对应那一行**复制到客户端仓库**
  (它自己的发版流程要拿产物指纹和它比对),本仓库保留原始记录即可。
- CI 用的密钥走客户端仓库的 secrets(base64 + 密码),**不要**把 `.jks` 或
  `keystore.properties` 入库到任何仓库。

## 3. 客户端仓库的推荐骨架

迁出去的应用按这个最小集合自洽(以 OrzMusic 为样板):

```
<client-repo>/
├── clients/android/            # 或直接放在仓库根,取决于目标仓库的整体布局
│   ├── gradlew (100755!)       # git 里必须是可执行位,否则 Linux CI 直接 Permission denied
│   ├── version.properties      # 客户端版本唯一来源(与服务端版本解耦)
│   ├── CHANGELOG.md            # 客户端变更,不与服务端混
│   ├── signing-manifest.txt    # 指纹,不是密钥
│   ├── scripts/
│   │   ├── android-release.sh  # 推导段位 → 写版本/CHANGELOG → 打 android-v* tag
│   │   ├── store-check.sh      # 上架前静态自检
│   │   └── sync-brand-assets.sh
│   └── store/                  # 商店人工清单 + 物料
└── .github/workflows/
    ├── android.yml             # PR 门禁(不要加 paths 过滤,会卡住 required check)
    └── android-release.yml     # android-v* → 签名 APK/AAB + 指纹校验
```

### 三条容易踩的判据

1. **版本号唯一来源要跟着代码走**。`version.properties` 放在客户端构建根目录,
   构建脚本用「向上找」而不是写死 `../..` 层级(拆目录、进 worktree 都不会坏)。
2. **tag 命名空间要分开**。服务端 `vX.Y.Z`、客户端 `android-vX.Y.Z`;
   同一个 tag 线会让两条发布互相阻塞。
3. **CI 的 `paths` 过滤**。只要 workflow 里有 required status check,就**不能**加
   `paths` —— 没触及路径的 PR 永远等不到该 check,永远合不进去。

## 4. 上架流程的归属

- **判据**以 [11](11-publishing.md) 为准(Play 的 targetSdk 门槛、国内商店的软著/备案、
  包名与签名不可变)。
- **执行**在客户端仓库:那里有自己的 `scripts/store-check.sh`(只查该应用),
  产物和密钥也在那边。
- 本仓库的 `tools/store-preflight.sh` 仍可用于**还在本仓库里构建**的应用
  (比如 `self-test/`),判据与客户端仓的瘦版保持一致。

## 5. 什么不该搬到客户端仓库

| 内容 | 为什么留下 |
|---|---|
| `tools/`(adb / 电视侧载 / Pico 注入 / 自截图) | 与具体应用无关,且要在开发机的 WSL/Windows 上跑 |
| `tools/gen-keystore.sh` | 密钥生命周期管理是跨应用的;客户端只消费导出的凭据 |
| `docs/01,03,04,05,07,08` | 环境与设备知识,所有 Android 项目共用 |
| `docs/06,11` 的判据 | 约定与上架规则;客户端仓库引用即可,不要各写一份 |
| `.agents/skills/` | Agent 协作配置,与仓库无关 |

---

## 迁移检查清单

**先跑 `bash tools/handoff-app.sh <App> --check`** —— 下面第 1~3 项它已经机械检查,
其余是需要人判断的。

- [ ] 客户端仓库里 `./gradlew` 能跑,且**没有**任何 `../../tools/*` 这类跨仓引用
- [ ] `git ls-files -s <client>/gradlew` 是 `100755`;`*.sh` 不是 CRLF
- [ ] `version.properties` 在客户端构建根目录;构建脚本用向上查找
- [ ] 文档里指向本仓库的链接改成绝对 URL,并注明「设备脚本不在本仓库」
- [ ] `signing-manifest.txt` 的对应指纹已复制到客户端仓库
- [ ] 客户端 CI 有 PR 门禁 + 独立 tag 线;没有给 job 加 `paths` 过滤
- [ ] 真机验收(电视 + Pico)在迁出后**再做一次**,确认产物一致
- [ ] 本仓库删除 `apps/<App>` 后跑 `bash tools/verify-all.sh`,文档无死链
