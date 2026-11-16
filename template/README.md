# template —— 公共应用模板

**这不是一个可直接上架的应用,也不在 `apps/` 下。**

它是 `bash tools/new-app.sh <AppName> <package.id>` 复制的起点:

- 包名占位是 `com.example.template`,脚本会替换成目标包名并移动源码目录
- 应用名占位是 `TemplateApp`
- 主题名是通用的 `Theme.App`

## 里面有什么

| 文件 | 作用 |
|---|---|
| `app/src/main/.../MainActivity.kt` | 最小启动页:`AppRoot()` 里三个可聚焦的 tv-material `Card`,遥控上下键能切焦点 |
| `app/src/debug/` | **自截图钩子**(`ui-dump.sh` 依赖它,只在 debug 构建里)。原理见 [docs/07](../docs/07-debug-ui-capture.md) |
| `app/src/test/.../TemplateScreenshotTest.kt` | Roborazzi JVM 截图测试,TV / 手机两种尺寸。见 [docs/08](../docs/08-jvm-screenshot-testing.md) |
| `app/build.gradle.kts` | 版本号从仓库根 `version.properties` 推导;release 签名从 `keystore.properties` 取每应用别名 |
| `app/src/main/AndroidManifest.xml` | `leanback` / `touchscreen` 都声明为 `required=false`,同一 APK 可跑 TV 与手机/VR |
| `app/src/main/res/drawable/banner.png` | TV 桌面用的 banner |
| `build.gradle.kts` | 插件版本(AGP / Kotlin / Compose) |

## 改这个目录要注意

0. **模板默认 `targetSdk = 34`**(仓库在真机上验证过的组合)。新应用要上
   Google Play 时,按 [docs/11](../docs/11-publishing.md) §0.3 把它升到 36,
   并给该应用的测试加 `app/src/test/resources/robolectric.properties`(`sdk=35`)——
   原因是 Robolectric 4.17 跑 SDK 36 需要 JDK 21,而仓库统一 JDK 17。
1. **它是所有新工程的源头。** 改完至少跑一次:
   ```bash
   bash tools/new-app.sh TemplateCheck com.example.templatecheck
   cd apps/TemplateCheck && ./gradlew assembleDebug && ./gradlew testDebugUnitTest
   rm -rf ../../apps/TemplateCheck
   ```
2. **不要放业务代码、不要放设备自检页。** 那些属于 `apps/DualDemo` 或具体应用。
3. **不要在这里写版本号、包名、应用名的字面量**(占位值除外)—— 新工程靠
   `new-app.sh` 替换,写死会漏改。
4. 模板目录里不要留 `local.properties`、`build/`、`.gradle/`;`new-app.sh`
   会清一遍,但留在这里会污染仓库(`.gitignore` 已覆盖,但仍应保持干净)。
