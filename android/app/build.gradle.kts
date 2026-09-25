import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.relio.relio_mobile"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    flavorDimensions += "environment"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.relio.relio_mobile"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        manifestPlaceholders["appLabel"] = "RELIO"
    }

    signingConfigs {
        val testKeyPropertiesFile = rootProject.file("key.properties")
        if (testKeyPropertiesFile.exists()) {
            val testKeyProperties = Properties()
            testKeyPropertiesFile.inputStream().use { testKeyProperties.load(it) }
            create("test") {
                keyAlias = testKeyProperties.getProperty("keyAlias")
                keyPassword = testKeyProperties.getProperty("keyPassword")
                storeFile = rootProject.file(
                    testKeyProperties.getProperty("storeFile"),
                )
                storePassword = testKeyProperties.getProperty("storePassword")
            }
        }
    }

    productFlavors {
        create("dev") {
            dimension = "environment"
            applicationIdSuffix = ".dev"
            manifestPlaceholders["appLabel"] = "RELIO Dev"
        }
        // AGP 9 reserves flavor names that start with "test"; qa is the
        // internal Android variant name for the RELIO TEST environment.
        create("qa") {
            dimension = "environment"
            applicationIdSuffix = ".test"
            manifestPlaceholders["appLabel"] = "RELIO Test"
            val testSigningConfig = signingConfigs.findByName("test")
            if (testSigningConfig != null) signingConfig = testSigningConfig
        }
        create("prod") {
            dimension = "environment"
            manifestPlaceholders["appLabel"] = "RELIO"
        }
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
