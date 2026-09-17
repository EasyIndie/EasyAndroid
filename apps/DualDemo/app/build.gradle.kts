// ⚠️ 这两个 import 必须在 plugins {} 之前:否则 `java.io.File` / `java.util.Properties`
// 里的 `java` 会被 Gradle 的 java 插件扩展(java { })遮蔽,报 Unresolved reference: io。
import java.io.File
import java.util.Properties

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
}

// ─────────────────────────────────────────────────────────────
// 向上查找仓库根的配置文件
//
// 本工程是独立 Gradle 构建(rootDir = apps/<Name>),所以不能写死 "../.." 这种
// 层级 —— 抽成函数往上找,拆工程 / 挪目录都不会坏。
// (写成 `while (dir != null && !File(dir, ...)) dir = dir.parentFile` 会踩 Kotlin
//  的智能转换限制:不能对可能被闭包捕获的 var 做 smart cast。)
// ─────────────────────────────────────────────────────────────
fun findUpward(name: String): File? {
    var d: File? = rootDir
    while (d != null) {
        val f = File(d, name)
        if (f.isFile) return f
        d = d.parentFile
    }
    return null
}

// ─────────────────────────────────────────────────────────────
// 版本号:唯一来源是仓库根的 version.properties(见 docs/06-app-conventions.md)
// ─────────────────────────────────────────────────────────────
val versionFile: File = findUpward("version.properties")
    ?: error("找不到 version.properties —— 它是本仓库版本号的唯一来源,应该在仓库根目录")

val appVersion: String = run {
    val props = Properties()
    versionFile.inputStream().use { props.load(it) }
    val v = props.getProperty("version")?.trim().orEmpty()
    if (v.isEmpty()) error("${versionFile.path} 里缺少 version=<MAJOR.MINOR.PATCH>")
    v
}

// SemVer -> versionCode:MAJOR*10000 + MINOR*100 + PATCH(每段 0..99)
// Android 要求 versionCode 单调递增。由 SemVer 推导就不会出现「改了 versionName 忘记改 versionCode」。
val appVersionCode: Int = run {
    val parts = appVersion.split(".")
    if (parts.size != 3) error("version=$appVersion 不是严格 SemVer(MAJOR.MINOR.PATCH),见 docs/06-app-conventions.md")
    parts.forEach {
        if (it.isEmpty() || (it.length > 1 && it.startsWith("0"))) {
            error("version=$appVersion 的段 '$it' 不合法(SemVer 不允许空段或前导零)")
        }
    }
    val nums = parts.map { p -> p.toIntOrNull() ?: error("version=$appVersion 里有非数字段: $p") }
    require(nums.all { it in 0..99 }) {
        "version=$appVersion 每段只能是 0..99(versionCode = MAJOR*10000 + MINOR*100 + PATCH)"
    }
    nums[0] * 10000 + nums[1] * 100 + nums[2]
}

// ─────────────────────────────────────────────────────────────
// 发布签名:同样向上找仓库根的 keystore.properties。
//
// **找不到就不配 signingConfig** —— release 仍能构建(产出 app-release-unsigned.apk),
// 保证任何人 clone 下来都能跑 assembleRelease;只是那种包装不上设备。
// 要发正式包先跑一次: bash tools/gen-keystore.sh
// ─────────────────────────────────────────────────────────────
// 存绝对路径:构建可能在 git worktree 里进行(tools/release-apk.sh 就是这么做的),
// 那时 worktree 到密钥库的相对关系和工作区不同。
val keystoreProps: Properties? = findUpward("keystore.properties")?.let { f ->
    Properties()
        .apply { f.inputStream().use { load(it) } }
        .also { it.setProperty("__file", f.absolutePath) }
}

android {
    namespace = "com.example.dualdemo"
    compileSdk = 34

    defaultConfig {
        applicationId = "com.example.dualdemo"
        minSdk = 29
        targetSdk = 34
        versionCode = appVersionCode
        versionName = appVersion
    }

    // ⚠️ signingConfigs 必须在 buildTypes 之前 —— buildTypes 里要用
    // `signingConfigs.getByName("release")`,而 DSL 是按书写顺序执行的。
    // 有密钥才建;没有就跳过(见上面 keystoreProps 的说明)
    if (keystoreProps != null) {
        signingConfigs {
            create("release") {
                // storeFile 相对仓库根;__file 是 keystore.properties 的绝对路径
                val propsDir = File(keystoreProps.getProperty("__file")).parentFile
                storeFile = File(propsDir, keystoreProps.getProperty("storeFile"))
                storePassword = keystoreProps.getProperty("storePassword")
                keyAlias = keystoreProps.getProperty("keyAlias")
                keyPassword = keystoreProps.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            if (keystoreProps != null) signingConfig = signingConfigs.getByName("release")
            isMinifyEnabled = false
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    buildFeatures {
        compose = true
        // 界面上显示的版本号来自 BuildConfig.VERSION_NAME,不再硬编码字面量
        buildConfig = true
    }

    // Robolectric 需要能读到编译后的资源,否则截图里没有主题/字体
    testOptions {
        unitTests {
            isIncludeAndroidResources = true
            // Roborazzi 靠系统属性决定"出图还是只断言"。
            // 用 -P 传的 Gradle 属性不会自动进测试 JVM,必须在这里转发。
            // 默认出图(这是"看 UI"用的);CI 想只断言就传
            //   -Proborazzi.test.record=false
            all { test ->
                test.systemProperty(
                    "roborazzi.test.record",
                    project.findProperty("roborazzi.test.record")?.toString() ?: "true"
                )
            }
        }
    }
}

dependencies {
    implementation(platform("androidx.compose:compose-bom:2024.12.01"))
    implementation("androidx.core:core-ktx:1.13.1")
    implementation("androidx.activity:activity-compose:1.9.3")
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.ui:ui-graphics")
    implementation("androidx.compose.foundation:foundation")
    implementation("androidx.tv:tv-material:1.0.0")

    // ---- JVM 截图测试(不需要设备/模拟器)----
    // 用 Robolectric 在 JVM 上渲染 Compose,Roborazzi 把结果落成 PNG。
    // 这是最快的 UI 迭代手段:几秒出图,能断言焦点态,也能在 CI 上跑。
    // 版本要和工程的 Kotlin 对齐:Roborazzi 1.66+ 是用 Kotlin 2.1+ 编的,
    // 元数据版本比编译器的 2.0 新,会直接编译不过。
    // 1.65.0 的 kotlin-stdlib 是 2.0.21,正好匹配。
    // 用法见 docs/08-jvm-screenshot-testing.md
    testImplementation("junit:junit:4.13.2")
    testImplementation("org.robolectric:robolectric:4.17")
    testImplementation("androidx.test.ext:junit:1.2.1")
    testImplementation("androidx.test:core-ktx:1.6.1")
    testImplementation(platform("androidx.compose:compose-bom:2024.12.01"))
    testImplementation("androidx.compose.ui:ui-test-junit4")
    testImplementation("io.github.takahirom.roborazzi:roborazzi:1.30.0")
    testImplementation("io.github.takahirom.roborazzi:roborazzi-compose:1.30.0")
    debugImplementation("androidx.compose.ui:ui-test-manifest")
}
