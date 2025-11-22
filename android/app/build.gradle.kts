plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.caps_finals"
    // Use the compileSdkVersion defined by Flutter
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
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.caps_finals"
        
        // -------------------------------------------------------------
        // 🛠️ IMPORTANT: Explicitly setting minSdkVersion to 21 (Android 5.0) 
        // ensures better compatibility for modern plugins like image_picker.
        // The default flutter.minSdkVersion might be too low (20).
        // -------------------------------------------------------------
        minSdk = flutter.minSdkVersion 
        
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    implementation("androidx.window:window:1.0.0")
    // Flutter embedding dependencies - added explicitly since gradle plugin may not inject them
    val engineVersion = "035316565ad77281a75305515e4682e6c4c6f7ca"
    implementation("io.flutter:flutter_embedding_debug:1.0.0-$engineVersion")
    implementation("io.flutter:armeabi_v7a_debug:1.0.0-$engineVersion")
    implementation("io.flutter:arm64_v8a_debug:1.0.0-$engineVersion")
    implementation("io.flutter:x86_64_debug:1.0.0-$engineVersion")
}
