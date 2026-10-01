import com.google.gms.googleservices.GoogleServicesPlugin.MissingGoogleServicesStrategy
import java.util.Properties

plugins {
    id("com.android.application")
    id("com.google.gms.google-services")
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
            manifestPlaceholders["appLabel"] = "RELIO"
        }
        // AGP 9 reserves flavor names that start with "test"; qa is the
        // internal Android variant name for the RELIO TEST environment.
        create("qa") {
            dimension = "environment"
            applicationIdSuffix = ".test"
            manifestPlaceholders["appLabel"] = "RELIO"
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
            // QA selects its dedicated TEST signing config at the flavor
            // level. DEV/PROD release signing remains intentionally unset
            // until their release keys are explicitly configured.
        }
    }
}

googleServices {
    // QA มี google-services.json จริง ส่วน DEV/PROD ใช้ Supabase และต้อง build ต่อได้
    missingGoogleServicesStrategy = MissingGoogleServicesStrategy.WARN
}

dependencies {
    // ใช้ตรวจสถานะ Google Play Services โดยไม่เพิ่ม Firebase service
    implementation("com.google.android.gms:play-services-base:18.3.0")
    // API-only is safe in every variant. It is a no-op when the full SDK is
    // absent, which keeps DEV and PROD free of self-update implementation.
    implementation("com.google.firebase:firebase-appdistribution-api:16.0.0-beta20")
    // The full SDK is intentionally QA-only. Never add this to PROD/Play.
    add("qaImplementation", "com.google.firebase:firebase-appdistribution:16.0.0-beta20")
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
