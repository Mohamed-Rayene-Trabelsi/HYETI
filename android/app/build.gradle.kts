import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// The release key: android/key.properties and the keystore it names (both kept out of git), or the HYETI_KEYSTORE,
// HYETI_KEYSTORE_PASSWORD and HYETI_KEY_ALIAS environment variables (for a build server). It is the key that signed every
// release since 1.1.1, so APKs signed with it install over the app on phones; any other key cannot.
val releaseKey: Map<String, String>? = run {
    val file = rootProject.file("key.properties")
    if (file.exists()) {
        val props = Properties().apply { file.inputStream().use { load(it) } }
        mapOf(
            "storeFile" to rootProject.file(props.getProperty("storeFile")).path,
            "storePassword" to props.getProperty("storePassword"),
            "keyAlias" to props.getProperty("keyAlias"),
            "keyPassword" to props.getProperty("keyPassword"),
        )
    } else {
        System.getenv("HYETI_KEYSTORE")?.let { store ->
            val password = System.getenv("HYETI_KEYSTORE_PASSWORD") ?: ""
            mapOf(
                "storeFile" to store,
                "storePassword" to password,
                "keyAlias" to (System.getenv("HYETI_KEY_ALIAS") ?: "hyeti"),
                "keyPassword" to password,
            )
        }
    }
}

android {
    namespace = "dev.personalapp.personal_mobile_app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // flutter_local_notifications (reminders) uses java.time, which older Androids get through desugaring.
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "dev.personalapp.personal_mobile_app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (releaseKey != null) {
            create("release") {
                storeFile = file(releaseKey.getValue("storeFile"))
                storePassword = releaseKey.getValue("storePassword")
                keyAlias = releaseKey.getValue("keyAlias")
                keyPassword = releaseKey.getValue("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            // Without the release key (a fresh clone, another computer) the build still works but is signed with that
            // computer's debug key, and the APK will not install over the app on a phone.
            signingConfig = signingConfigs.getByName(if (releaseKey != null) "release" else "debug")
            if (releaseKey == null) logger.warn("HYETI: android/key.properties not found; signing the release APK with the debug key.")
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }
}

// The released APK is for 64-bit ARM phones only; without this the receipt text reader ships three copies
// of itself (about 18 MB more).
androidComponents {
    onVariants(selector().withBuildType("release")) { variant ->
        variant.packaging.jniLibs.excludes.addAll("lib/x86_64/**", "lib/x86/**", "lib/armeabi-v7a/**")
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
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
