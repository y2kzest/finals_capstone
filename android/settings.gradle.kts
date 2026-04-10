pluginManagement {
    val flutterSdkPath = run {
        val properties = java.util.Properties()
        File(rootDir, "local.properties").inputStream().use {
            properties.load(it)
        }
        val flutterSdkPathValue = properties.getProperty("flutter.sdk")
        require(flutterSdkPathValue != null) { "flutter.sdk not specified in local.properties" }
        flutterSdkPathValue
    }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "8.9.1" apply false
    id("com.android.library") version "8.9.1" apply false
    id("org.jetbrains.kotlin.android") version "2.1.0" apply false
}

include(":app")