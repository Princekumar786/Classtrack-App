plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    id("com.google.firebase.crashlytics")
    // END: FlutterFire Configuration
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

import java.util.Properties
import java.io.FileInputStream

// Load release signing credentials from android/key.properties when present.
// This file is gitignored; if it's absent (e.g. a fresh clone or CI without
// secrets) we fall back to debug signing so `flutter run` still works.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val hasReleaseSigning = keystorePropertiesFile.exists()
if (hasReleaseSigning) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.classtrack.classtrack"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // Store-facing Application ID — locked before publishing.
        applicationId = "com.classtracks.app"
        // Firebase Auth/Firestore require a minSdk of 23+.
        minSdk = maxOf(flutter.minSdkVersion, 23)
        // Google Play requires new apps/updates to target Android 16 (API 36).
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        multiDexEnabled = true
    }

    signingConfigs {
        if (hasReleaseSigning) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String?
                keyPassword = keystoreProperties["keyPassword"] as String?
                storeFile = (keystoreProperties["storeFile"] as String?)?.let { file(it) }
                storePassword = keystoreProperties["storePassword"] as String?
            }
        }
    }

    buildTypes {
        release {
            // Use the real upload key when key.properties is present, otherwise
            // fall back to debug signing for local release runs.
            signingConfig = if (hasReleaseSigning) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
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

dependencies {
    // Required by flutter_local_notifications for core library desugaring.
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")

    // Force a fixed Google Sign-In backend. google_sign_in_android 6.2.1 pins
    // play-services-auth 21.0.0, whose SignInHubActivity.onCreate crashes with
    // a NullPointerException ("...getClass() on a null object reference") when
    // the sign-in activity is recreated after process death. That bug is fixed
    // in 21.2.0+, so we pin the newer, backward-compatible release. Gradle
    // resolves to the highest version, so this overrides the transitive 21.0.0.
    implementation("com.google.android.gms:play-services-auth:21.3.0")
}
