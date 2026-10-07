plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val releaseSigning = listOf("WGMFA_KEYSTORE", "WGMFA_STORE_PASSWORD", "WGMFA_KEY_ALIAS", "WGMFA_KEY_PASSWORD")
    .associateWith { System.getenv(it) }
val hasReleaseSigning = releaseSigning.values.all { !it.isNullOrBlank() }

gradle.taskGraph.whenReady {
    if (allTasks.any { it.project == project && it.name.contains("release", ignoreCase = true) }) {
        check(hasReleaseSigning) { "Release signing required: use tool/build_android_release.ps1." }
    }
}

android {
    namespace = "jp.co.fairway.wireguard_mfa_client"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "jp.co.fairway.wireguard_mfa_client"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseSigning) {
            create("release") {
                storeFile = file(releaseSigning.getValue("WGMFA_KEYSTORE")!!)
                storePassword = releaseSigning.getValue("WGMFA_STORE_PASSWORD")
                keyAlias = releaseSigning.getValue("WGMFA_KEY_ALIAS")
                keyPassword = releaseSigning.getValue("WGMFA_KEY_PASSWORD")
            }
        }
    }

    buildTypes {
        release {
            // Credentials are supplied only by the release build process.
            if (hasReleaseSigning) signingConfig = signingConfigs.getByName("release")
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
    implementation("com.wireguard.android:tunnel:1.0.20260102")
}
