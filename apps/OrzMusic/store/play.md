# Google Play 上架清单 —— OrzMusic

> 机器能查的项由 `bash tools/store-preflight.sh <version> --target play` 检查;
> 这份文件记录**只能人工确认**的材料。`TODO:` 提交前必须清掉。

## 应用身份

| 项 | 值 |
|---|---|
| 包名 | `com.jokerhub.orzmusic.android` |
| 应用名(≤30 字符) | OrzMusic |
| 类别 | 音乐与音频(Music & Audio) |
| 定价 | 免费 |
| 广告 | 无 |
| 应用内购买 | 无 |
| 登录 | 无(后端本身无鉴权) |

## 商店资料

| 项 | 状态 |
|---|---|
| 简短说明(≤80 字符) | TODO:例「浏览与播放 KeyGen / 芯片音乐曲库」 |
| 完整说明(≤4000 字符) | TODO:功能列表 + 自建服务器说明 + 后台播放/通知权限声明 |
| 应用图标 512×512 PNG(32 位) | TODO:从 `ic_launcher` 导出 |
| 特色图片 1024×500 PNG | TODO |
| 手机截图(至少 2 张) | TODO:用 `tools/ui-dump.sh` 或 Roborazzi |
| 7 寸 / 10 寸平板截图 | TODO(建议) |
| Android TV 截图(至少 1 张) | TODO:电视 D-pad 验收后自截图 |
| TV banner 320×180 | 已有 `app/src/main/res/drawable/banner.png`,确认尺寸 |

## 政策与表单

| 项 | 状态 |
|---|---|
| 隐私政策 URL | TODO:必须可公开访问;要说明「服务器地址可配置、搜索词会发给所选服务器」 |
| 数据安全表单 | ⚠️ 需要判断:客户端无账号/无广告/无分析 SDK,但**搜索词与曲目 ID 会发往用户配置的服务器**。若官方实例会记录 IP/请求,建议如实勾「应用活动 · 应用内搜索历史」;自建服务器则由部署者负责 |
| 内容分级问卷 | 音乐类;无 UGC、无社交。按实际曲库内容填写 |
| 目标受众 | TODO:建议 13+(音乐内容,无 UGC) |
| 应用访问权限 | 全部功能无需登录 |
| 政府/新闻/COVID | 否 |
| 数据删除请求 | 不适用(无账号) |

## 内容版权(重要)

这是一个**客户端**,曲库来自 OrzMusic 服务端(KeyGen / 芯片 / 模块音乐)。
Play 对音乐/流媒体类会关注版权。提交前确认:

- [ ] 官方实例的曲库有权分发,或
- [ ] 商店描述里明确「本应用是客户端,内容由用户配置的服务器提供」,并让用户自建

## 技术门槛(机器会查)

- [x] `targetSdk` = 36
- [x] 包名不是 `com.example.*`
- [x] AAB 已签名(`jarsigner -verify`),含 `arm64-v8a`
- [x] 非 debuggable、无 debug 自截图钩子
- [x] 权限:网络、前台媒体播放、通知;不含 `RECORD_AUDIO` / 定位 / 存储

## 提交流程

1. `bash tools/release-apk.sh <version> --app OrzMusic --format both`
2. `bash tools/store-preflight.sh <version> --target play`
3. Play Console → 创建应用 → 填资料 → 上传 `.aab` 到**内部测试**
4. 内部测试装一遍:手机 + TV 各验一次(曲库 / 搜索 / mp3 或 ogg 播放)
5. 逐级 promoted:closed → open → production

> ⚠️ Play **没有 VR 轨道**。Pico 用同一个 APK,走 Pico 自己的商店/侧载。
