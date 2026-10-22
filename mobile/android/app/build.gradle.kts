import java.util.Base64
import java.util.Properties
import java.net.URI

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val defines = (project.findProperty("dart-defines") as String? ?: "").split(",")
    .filter { it.isNotEmpty() }.map { String(Base64.getDecoder().decode(it)) }
    .associate { val pair = it.split("=", limit = 2); pair[0] to pair.getOrElse(1) { "" } }
val cloudBuild = defines["USE_EMULATORS"] == "false"
val signingFile = file(System.getenv("PMS_ANDROID_KEY_PROPERTIES") ?: "../key.properties")
val signingValues = Properties().apply { if (signingFile.exists()) signingFile.inputStream().use { load(it) } }

android {
    namespace = "com.crompton.pms.frontend"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.crompton.pms.frontend"
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
        // Native FCM cold starts need resources matching the explicit Dart app.
        if (cloudBuild) {
            val config = groovy.json.JsonSlurper().parse(file("google-services.json")) as Map<*, *>
            val info = config["project_info"] as Map<*, *>
            val client = (config["client"] as List<*>).first() as Map<*, *>
            val clientInfo = client["client_info"] as Map<*, *>
            val apiKey = ((client["api_key"] as List<*>).first() as Map<*, *>)["current_key"].toString()
            require(defines["FIREBASE_PROJECT_ID"] == info["project_id"]) { "Native Firebase project mismatch" }
            require(defines["FIREBASE_APP_ID"] == clientInfo["mobilesdk_app_id"]) { "Native Firebase app mismatch" }
            require(defines["FIREBASE_API_KEY"] == apiKey) { "Native Firebase API key mismatch" }
            resValue("string", "google_app_id", clientInfo["mobilesdk_app_id"].toString())
            resValue("string", "google_api_key", apiKey)
            resValue("string", "gcm_defaultSenderId", info["project_number"].toString())
            resValue("string", "project_id", info["project_id"].toString())
            resValue("string", "google_storage_bucket", info["storage_bucket"].toString())
        }
    }

    signingConfigs {
        create("configuredRelease") {
            if (signingFile.exists()) {
                storeFile = file(signingValues.getProperty("storeFile"))
                storePassword = signingValues.getProperty("storePassword")
                keyAlias = signingValues.getProperty("keyAlias")
                keyPassword = signingValues.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("configuredRelease")
        }
    }
}

val verifyReleaseConfiguration by tasks.registering {
    doLast {
        require(cloudBuild && signingFile.exists()) { "Release requires explicit cloud configuration and private signing properties" }
        val apiUrl = defines["BASE_URL"] ?: ""
        require(apiUrl.startsWith("https://") && URI(apiUrl).host?.endsWith(".invalid") == false) { "Release API must use a configured HTTPS origin" }
    }
}

tasks.configureEach {
    if (name == "preReleaseBuild" || name.startsWith("validateSigningRelease")) dependsOn(verifyReleaseConfiguration)
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies { coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4") }
