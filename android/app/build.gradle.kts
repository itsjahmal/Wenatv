plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
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
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "tv.wena.app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            val storeFilePath = System.getenv("MYAPP_UPLOAD_STORE_FILE")
            if (!storeFilePath.isNullOrBlank()) {
                val candidate = file(storeFilePath)
                storeFile = if (candidate.isAbsolute) {
                    candidate
                } else {
                    rootProject.projectDir.parentFile.resolve(storeFilePath)
                }
            }
            storePassword = System.getenv("MYAPP_UPLOAD_STORE_PASSWORD")
            keyAlias = System.getenv("MYAPP_UPLOAD_KEY_ALIAS")
            keyPassword = System.getenv("MYAPP_UPLOAD_KEY_PASSWORD")
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
        }
    }
}

flutter {
    source = "../.."
}
