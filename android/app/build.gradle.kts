import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("dev.flutter.flutter-gradle-plugin")
}

// Load release signing credentials from key.properties (kept out of VCS).
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val hasKeyProperties = keystorePropertiesFile.exists()
if (hasKeyProperties) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.visor.app"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.visor.app"
        minSdk = flutter.minSdkVersion
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasKeyProperties) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = rootProject.file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            // Falling back to the debug key silently would ship an APK that
            // cannot be updated over a real release, so the fallback is loud
            // and only survives until the release build is actually assembled.
            signingConfig = if (hasKeyProperties) {
                signingConfigs.getByName("release")
            } else {
                logger.warn(
                    "WARNING: android/key.properties not found - release will " +
                        "be signed with the DEBUG key. Do not distribute this APK."
                )
                signingConfigs.getByName("debug")
            }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    // Solana Mobile Wallet Adapter (Kotlin) for Seed Vault connect.
    // agp9 build is built for AGP 9; plain 2.2.0 pulls androidx.core 1.19 → compileSdk 37.
    implementation("com.solanamobile:mobile-wallet-adapter-clientlib-ktx:2.2.0-agp9-beta1")
}

flutter {
    source = "../.."
}

// Hard stop: a release artifact must never leave this machine debug-signed.
// Set -PallowDebugSignedRelease=true only for a local smoke test.
gradle.taskGraph.whenReady {
    val assemblingRelease = allTasks.any {
        it.project == project && it.name.contains("Release") &&
            (it.name.startsWith("assemble") || it.name.startsWith("bundle"))
    }
    val override = project.findProperty("allowDebugSignedRelease") == "true"
    if (assemblingRelease && !hasKeyProperties && !override) {
        throw GradleException(
            "Release build requested but android/key.properties is missing. " +
                "Add the signing config, or pass -PallowDebugSignedRelease=true " +
                "to build a debug-signed release for local testing only."
        )
    }
}