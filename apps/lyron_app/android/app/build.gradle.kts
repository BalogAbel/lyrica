import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keyProps = Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.exists()) load(f.inputStream())
}

android {
    namespace = "com.lyron.lyron_app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    signingConfigs {
        create("release") {
            keyAlias = keyProps["keyAlias"] as String? ?: System.getenv("ANDROID_KEY_ALIAS") ?: ""
            keyPassword = keyProps["keyPassword"] as String? ?: System.getenv("ANDROID_KEY_PASSWORD") ?: ""
            storeFile = (keyProps["storeFile"] as String? ?: System.getenv("ANDROID_KEYSTORE_PATH"))
                ?.let { file(it) }
            storePassword = keyProps["storePassword"] as String? ?: System.getenv("ANDROID_KEYSTORE_PASSWORD") ?: ""
        }
    }

    defaultConfig {
        applicationId = "io.lyron.chords"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
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
