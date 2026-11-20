# `apps/` —— 业务应用(当前为空)

业务应用已经迁到各自的仓库:

| 应用 | 仓库 | 客户端目录 |
|---|---|---|
| OrzMusic | [`OrzGeeker/OrzMusic`](https://github.com/OrzGeeker/OrzMusic) | `clients/android/` |

**新应用不要默认往这里放。** 两种做法:

- 应用有自己的产品仓库 → 在那里建 Android 工程(推荐,见
  [docs/12](../docs/12-client-repos.md) 的「客户端仓库的推荐骨架」);
- 只是一次性验证 / 共用脚手架 → 放 `self-test/`,或用
  `bash tools/new-app.sh <Name> <package.id>` 在本地起一个工程再搬走。

本目录仍然参与 `tools/release-apk.sh` 的扫描(`apps/*/publish.properties`),
所以留一个说明文件、不建空工程 —— 空目录不会被打包脚本误认成应用。
