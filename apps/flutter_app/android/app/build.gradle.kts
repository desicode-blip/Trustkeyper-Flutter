import java.util.Properties
import java.util.Base64

val uiTest = providers.gradleProperty("dart-defines").orNull
    ?.split(",")
    ?.any { String(Base64.getDecoder().decode(it)) == "TRUSTKEYPER_UI_TEST=true" } == true

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystorePropertiesFile.inputStream().use(keystoreProperties::load)
}

val uploadStoreFile = System.getenv("TRUSTKEYPER_UPLOAD_STORE_FILE")
val uploadStorePassword = System.getenv("TRUSTKEYPER_UPLOAD_STORE_PASSWORD")
val uploadKeyAlias = System.getenv("TRUSTKEYPER_UPLOAD_KEY_ALIAS")
val uploadKeyPassword = System.getenv("TRUSTKEYPER_UPLOAD_KEY_PASSWORD")
val hasEnvironmentSigning = listOf(
    uploadStoreFile,
    uploadStorePassword,
    uploadKeyAlias,
    uploadKeyPassword,
).all { !it.isNullOrBlank() }

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services") apply false
    id("com.google.firebase.crashlytics") apply false
    // END: FlutterFire Configuration
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

if (!uiTest) {
    apply(plugin = "com.google.gms.google-services")
    apply(plugin = "com.google.firebase.crashlytics")
}

tasks.matching { it.name.startsWith("uploadCrashlytics") }.configureEach {
    onlyIf { System.getenv("TRUSTKEYPER_SKIP_CRASHLYTICS_UPLOAD") != "true" }
}

if (!hasEnvironmentSigning && !keystorePropertiesFile.exists() &&
    gradle.startParameter.taskNames.any { it.contains("release", ignoreCase = true) }
) {
    throw GradleException("Release signing is required. Configure the TrustKeyper upload key before building a release.")
}

android {
    namespace = "com.trustkeyper.mobile"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = if (uiTest) "com.trustkeyper.mobile.uitest" else "com.trustkeyper.mobile"
        manifestPlaceholders["appLabel"] = if (uiTest) "TrustKeyper UI Test" else "TrustKeyper"
        manifestPlaceholders["appLinkScheme"] = if (uiTest) "trustkeyper-uitest" else "trustkeyper"
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
        if (hasEnvironmentSigning) {
            create("release") {
                keyAlias = uploadKeyAlias
                keyPassword = uploadKeyPassword
                storeFile = file(uploadStoreFile!!)
                storePassword = uploadStorePassword
            }
        } else if (keystorePropertiesFile.exists()) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasEnvironmentSigning || keystorePropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                null
            }
        }
    }

    if (uiTest) {
        if (gradle.startParameter.taskNames.any { it.contains("release", ignoreCase = true) }) {
            throw GradleException("The isolated UI-test app is debug-only.")
        }
        sourceSets.getByName("debug").manifest.srcFile("src/uiTest/AndroidManifest.xml")
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
