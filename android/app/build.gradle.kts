// add these imports at the very top of the file
import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

android {
    namespace = "com.eitan.chorebid"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "27.0.12077973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    defaultConfig {
        applicationId = "com.eitan.chorebid"
        minSdk = 23
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // --- load keystore props from android/key.properties ---
    val keystoreProperties = Properties()
    val keystorePropertiesFile = rootProject.file("key.properties")
    if (keystorePropertiesFile.exists()) {
        keystoreProperties.load(FileInputStream(keystorePropertiesFile))
    }

    signingConfigs {
        create("release") {
            // only set if key.properties exists
            if (keystoreProperties.isNotEmpty()) {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storePassword = keystoreProperties["storePassword"] as String
                val storeFilePath = keystoreProperties["storeFile"] as String
                storeFile = file(storeFilePath)  // absolute path, no ~
            }
        }
    }

    buildTypes {
        getByName("release") {
            // IMPORTANT: use the release signing config (not debug)
            signingConfig = signingConfigs.getByName("release")

            // optional optimizations
            // isMinifyEnabled = true
            // isShrinkResources = true
            // proguardFiles(
            //     getDefaultProguardFile("proguard-android-optimize.txt"),
            //     "proguard-rules.pro"
            // )
        }

        // getByName("debug") { } // leave as-is
    }
}

flutter {
    source = "../.."
}

dependencies {
    implementation(platform("com.google.firebase:firebase-bom:33.16.0"))
    implementation("com.google.firebase:firebase-functions")
    implementation("com.google.firebase:firebase-auth")
    implementation("com.google.firebase:firebase-firestore")
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.2")
}
