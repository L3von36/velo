import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// ---------------------------------------------------------------------------
// Release signing
// - CI:       ANDROID_KEYSTORE_PATH / ANDROID_KEYSTORE_PASSWORD / ANDROID_KEY_ALIAS
//             / ANDROID_KEY_PASSWORD environment variables (set from GitHub secrets)
// - Local:    android/key.properties (storeFile, storePassword, keyAlias, keyPassword)
// - Fallback: debug key so the project always builds out of the box.
// ---------------------------------------------------------------------------
val keystoreProperties = Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.exists()) load(FileInputStream(f))
}
val keystorePath = System.getenv("ANDROID_KEYSTORE_PATH")
    ?: keystoreProperties["storeFile"]?.toString()
val keystoreFile = keystorePath?.let { file(it) }

android {
    namespace = "com.velo.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        applicationId = "com.velo.app"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            if (keystoreFile != null && keystoreFile.exists()) {
                storeFile = keystoreFile
                storePassword = System.getenv("ANDROID_KEYSTORE_PASSWORD")
                    ?: (keystoreProperties["storePassword"] as String?)
                keyAlias = System.getenv("ANDROID_KEY_ALIAS")
                    ?: (keystoreProperties["keyAlias"] as String?)
                keyPassword = System.getenv("ANDROID_KEY_PASSWORD")
                    ?: (keystoreProperties["keyPassword"] as String?)
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (keystoreFile != null && keystoreFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

flutter {
    source = "../.."
}
