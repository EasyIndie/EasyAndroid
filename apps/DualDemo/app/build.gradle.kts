plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
}

android {
    namespace = "com.example.dualdemo"
    compileSdk = 34

    defaultConfig {
        applicationId = "com.example.dualdemo"
        minSdk = 29
        targetSdk = 34
        versionCode = 1
        versionName = "0.1.0"
    }

    buildTypes {
        release {
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
