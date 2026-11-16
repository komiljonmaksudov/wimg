plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
    id("org.jetbrains.kotlin.plugin.serialization")
}

android {
    namespace = "com.wimg.app"
    compileSdk = 36

    defaultConfig {
        applicationId = "com.wimg.app"
        minSdk = 26
        targetSdk = 36
        // Bumped by scripts/release.sh alongside package.json and project.yml.
        // Play requires a strictly increasing versionCode for every upload, so
        // CI overrides it with a timestamp (-PwimgVersionCode), the same trick
        // the iOS job uses for CURRENT_PROJECT_VERSION.
        versionCode = (project.findProperty("wimgVersionCode") as String?)?.toInt() ?: 1
        versionName = "0.9.9"
        manifestPlaceholders["appLabel"] = "wimg"

        ndk {
            abiFilters += "arm64-v8a"
        }
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
        // Release code (R8, not debuggable: Android compiles it) with the debug
        // key, so it installs over a debug build and keeps the data. For judging
        // smoothness on a phone: debug builds run Compose uncompiled.
        create("bench") {
            initWith(getByName("release"))
            signingConfig = signingConfigs.getByName("debug")
            matchingFallbacks += listOf("release")
        }
        // Like bench, but its own app ("wimg Test", com.wimg.app.tester): installs
        // next to the real one and starts empty, as a new tester sees it.
        create("preview") {
            initWith(getByName("bench"))
            applicationIdSuffix = ".tester"
            manifestPlaceholders["appLabel"] = "wimg Test"
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    // libwimg.so + libwimg-jni.so are prebuilt by scripts/build-android.sh
    // (Zig) into src/main/jniLibs; Gradle only packages them.
    buildFeatures {
        compose = true
    }
}

dependencies {
    // Compose
    implementation(platform("androidx.compose:compose-bom:2025.03.00"))
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.material3:material3")
    // QR code for showing the sync key (encoder only, no camera).
    implementation("com.google.zxing:core:3.5.3")
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

    // Biometric auth (Face / Fingerprint / device credential)
    implementation("androidx.biometric:biometric:1.2.0-alpha05")
    // biometric pulls in androidx.fragment 1.2.x, whose FragmentActivity rejects the
    // request codes of the Activity Result API ("Can only use lower 16 bits for
    // requestCode") and crashes on any permission request. MainActivity is a
    // FragmentActivity, so pin a fragment version that supports it (>= 1.3).
    implementation("androidx.fragment:fragment-ktx:1.8.5")

    // WorkManager — periodic background FinTS refresh (BackgroundRefresh.kt)
    implementation("androidx.work:work-runtime-ktx:2.9.1")

    debugImplementation("androidx.compose.ui:ui-tooling")
}
