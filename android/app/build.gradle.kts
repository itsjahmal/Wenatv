import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// ─── Signing: read from android/key.properties ────────────────────────────
val keyPropsFile = rootProject.file("key.properties")
val keyProps = Properties()
if (keyPropsFile.exists()) {
    keyPropsFile.inputStream().use { keyProps.load(it) }
}

android {
    namespace = "tv.wena.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "tv.wena.app"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Wena v2.1 Beta
        versionCode = 3
        versionName = "2.1"
    }

    applicationVariants.all {
        val variant = this
        variant.outputs.all {
            val output = this as com.android.build.gradle.internal.api.BaseVariantOutputImpl
            output.outputFileName = "wena-v${variant.versionName}.apk"
        }
    }

    signingConfigs {
        create("release") {
            val sf = keyProps.getProperty("storeFile") ?: ""
            storeFile = if (sf.isNotBlank()) rootProject.file("app/$sf") else null
            storePassword = keyProps.getProperty("storePassword") ?: ""
            keyAlias = keyProps.getProperty("keyAlias") ?: ""
            keyPassword = keyProps.getProperty("keyPassword") ?: ""
        }
    }

    buildTypes {
        release {
            // Performance Fix 8: minification + resource shrinking for smaller APK
            isMinifyEnabled = true
            isShrinkResources = true
            signingConfig = signingConfigs.getByName("release")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    implementation("androidx.tvprovider:tvprovider:1.0.0")
    // Performance Fix 8: ExoPlayer upgraded 1.4.1 -> 1.6.0 for better TV buffering
    implementation("androidx.media3:media3-exoplayer:1.6.0")
    implementation("androidx.media3:media3-exoplayer-hls:1.6.0")
    implementation("androidx.media3:media3-exoplayer-dash:1.6.0")
    implementation("androidx.media3:media3-ui:1.6.0")
}
