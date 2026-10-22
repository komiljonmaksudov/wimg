plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
    id("org.jetbrains.kotlin.plugin.serialization")
}

android {
    namespace = "com.wimg.app"
    compileSdk = 35

    defaultConfig {
        applicationId = "com.wimg.app"
        minSdk = 26
        targetSdk = 35
        // Bumped by scripts/release.sh alongside package.json and project.yml.
        // Play requires a strictly increasing versionCode for every upload, so
        // CI overrides it with a timestamp (-PwimgVersionCode), the same trick
        // the iOS job uses for CURRENT_PROJECT_VERSION.
        versionCode = (project.findProperty("wimgVersionCode") as String?)?.toInt() ?: 1
        versionName = "0.9.6"

        ndk {
            abiFilters += "arm64-v8a"
        }
        ndkVersion = "30.0.14904198"
    }

    // Play upload signing. Credentials come from the environment so nothing
    // secret lands in the repo; CI supplies them from GitHub secrets and a
    // local build can export the same four vars. When they're absent the
    // release build simply stays unsigned (fine for `assembleDebug`).
    val keystorePath = System.getenv("WIMG_KEYSTORE_FILE")
    signingConfigs {
        if (keystorePath != null) {
            create("release") {
                storeFile = file(keystorePath)
                storePassword = System.getenv("WIMG_KEYSTORE_PASSWORD")
                keyAlias = System.getenv("WIMG_KEY_ALIAS")
                keyPassword = System.getenv("WIMG_KEY_PASSWORD")
            }
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
            if (keystorePath != null) {
                signingConfig = signingConfigs.getByName("release")
            }
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

    externalNativeBuild {
        cmake {
            path = file("src/main/cpp/CMakeLists.txt")
            version = "3.22.1"
        }
    }
}

dependencies {
    // Compose
    implementation(platform("androidx.compose:compose-bom:2025.03.00"))
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.material:material-icons-extended")
    implementation("androidx.compose.ui:ui-tooling-preview")
    implementation("androidx.activity:activity-compose:1.10.0")
    implementation("androidx.navigation:navigation-compose:2.8.0")

    // JSON parsing for C ABI results
    implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.7.3")

    // OkHttp for sync + FinTS HTTP callback
    implementation("com.squareup.okhttp3:okhttp:4.12.0")

    // Glance widgets
    implementation("androidx.glance:glance-appwidget:1.1.1")
    implementation("androidx.glance:glance-material3:1.1.1")

    // Biometric auth (Face / Fingerprint / device credential)
    implementation("androidx.biometric:biometric:1.2.0-alpha05")

    // WorkManager — periodic background FinTS refresh (BackgroundRefresh.kt)
    implementation("androidx.work:work-runtime-ktx:2.9.1")

    debugImplementation("androidx.compose.ui:ui-tooling")
}
