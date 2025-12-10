enableFeaturePreview("TYPESAFE_PROJECT_ACCESSORS")

pluginManagement {
    fun flutterSdkPath(): String {
        val properties = java.util.Properties()
        val localPath = try {
            file("local.properties").inputStream().use { properties.load(it) }
            properties.getProperty("flutter.sdk")
        } catch (_: Exception) {
            System.getenv("FLUTTER_SDK")
        }
        require(localPath != null) { "flutter.sdk not set" }
        return localPath
    }

    includeBuild("${flutterSdkPath()}/packages/flutter_tools/gradle")

    repositories {
        google {
            content {
                includeGroupByRegex("com\\.android.*")
                includeGroupByRegex("com\\.google.*")
                includeGroupByRegex("androidx.*")
            }
        }
        mavenCentral()
        gradlePluginPortal()
        maven { url = uri("https://storage.googleapis.com/download.flutter.io") }
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0" apply true
    id("com.android.application") version "8.11.1" apply false
    id("org.jetbrains.kotlin.android") version "2.2.20" apply false
}

@Suppress("INCUBATING_API")  // kill incubating: lint zero, 9.0 ready
dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.PREFER_SETTINGS)
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
        maven { url = uri("https://storage.googleapis.com/download.flutter.io") }
    }
}

rootProject.name = "iranian_pro_vpn"
include(":app")