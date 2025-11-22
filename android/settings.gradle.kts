pluginManagement {
    val flutterSdkPath = run {
        val properties = java.util.Properties()
        File(rootDir.parentFile, "android/local.properties").inputStream().use {
            properties.load(it)
        }
        val flutterSdkPathValue = properties.getProperty("flutter.sdk")
        require(flutterSdkPathValue != null) { "flutter.sdk not specified in local.properties" }
        flutterSdkPathValue
    }

    plugins {
        id("dev.flutter.flutter-plugin-loader") version "1.0.0"
        // These versions must be declared here (and not in build.gradle.kts)
        id("com.android.application") version "8.7.3"
        id("com.android.library") version "8.7.3"
        id("org.jetbrains.kotlin.android") version "2.1.0"
    }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

// NOTE: The outer 'plugins' block should be empty or omitted if possible,
// but since Flutter often includes it, ensure it's clean if present.
// If it's present, it should look like this:
plugins {
    // Empty
}

include(":app")