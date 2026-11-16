# Google Play 上架清单 —— EasyInfo

> 机器能查的部分由 `bash tools/store-preflight.sh <version> --target play` 检查;
> 这份文件记录**只能人工确认**的东西。`TODO:` 是没填的项,提交前必须清掉。

## 应用身份

| 项 | 值 |
|---|---|
| 包名 | `com.easyindie.easyinfo` |
| 默认语言 | 中文(简体) |
| 应用名(≤30 字符) | 设备信息 |
| 应用类别 | 工具(Tools) |
| 定价 | 免费 |
| 广告 | 无 |
| 应用内购买 | 无 |

## 商店资料

| 项 | 状态 |
|---|---|
| 简短说明(≤80 字符) | TODO: 一句话说明(例:查看设备型号、屏幕、CPU、内存与 TV 能力) |
| 完整说明(≤4000 字符) | TODO: 功能列表 + 使用方式 + 无权限/不联网声明 |
| 应用图标 512×512 PNG(32 位) | TODO: 从 `ic_launcher` 导出 |
| 特色图片 1024×500 PNG | TODO |
| 手机截图(至少 2 张) | TODO: 用 `tools/ui-dump.sh` 或 Roborazzi 出图 |
| 7 寸 / 10 寸平板截图 | TODO(可选,但建议) |
| Android TV 截图(至少 1 张) | TODO: 电视上 `input keyevent` 后自截图 |
| TV banner 320×180 | 已有 `app/src/main/res/drawable/banner.png`,确认尺寸 |

## 政策与表单

| 项 | 状态 |
|---|---|
| 隐私政策 URL | TODO: 必须可公开访问(GitHub Pages 即可) |
| 数据安全表单 | 选「不收集任何数据」;无账号、无分析 SDK、无广告 SDK |
| 内容分级问卷 | 工具类,无暴力/色情/赌博/用户生成内容 |
| 目标受众 | 13 岁以上(设备信息类工具) |
| 应用访问权限 | 全部功能无需登录 |
| 政府应用 | 否 |
| 新闻应用 | 否 |
| 数据删除请求 | 不适用(不收集数据) |

## 签名

| 项 | 值 |
|---|---|
| 上传密钥别名 | `alias.EasyInfo`(`CN=EasyInfo Release`) |
| 签名模式 | Play App Signing(由 Google 保管应用签名密钥) |
| 上传密钥指纹 | `5451e4a6...`(见仓库根 `signing-manifest.txt`) |
| ⚠️ 上传密钥本体 | 只在 `tools/keystore/release.jks` + `keystore.properties`,**不能入库** |

## 技术门槛(机器会查)

- [x] `targetSdk` = 36(已装 `platforms;android-36` + `build-tools;36.0.0`)
- [ ] AAB 已生成且 `jarsigner -verify` 通过
- [ ] 包含 `arm64-v8a`(Compose 的 `libandroidx.graphics.path.so` 已带)
- [ ] 非 debuggable、无 debug 自截图钩子
- [ ] 包名不以 `com.example.` 开头 ✅

## 提交流程

1. `bash tools/release-apk.sh <version> --format both`
2. `bash tools/store-preflight.sh <version> --target play`
3. Play Console → 创建应用 → 填写上面的资料 → 上传 `.aab` 到**内部测试**轨道
4. 内部测试通过后逐级 promoted(closed → open → production)
5. 提交前再跑一次 `bash tools/store-preflight.sh <version> --target play`。
