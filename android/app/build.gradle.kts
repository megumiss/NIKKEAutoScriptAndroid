import java.util.Properties
import java.net.URI
import java.security.MessageDigest

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.megumiss.nkas.mobile"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "28.2.13676358"

    packaging {
        resources.excludes += setOf(
            "META-INF/LICENSE.md",
            "META-INF/NOTICE.md",
            "META-INF/DEPENDENCIES",
        )
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.megumiss.nkas.mobile"
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
        create("release") {
            val rootProperties = Properties()
            val rootPropertiesFile = rootProject.file("../keystore.properties")
            if (rootPropertiesFile.exists()) {
                rootPropertiesFile.inputStream().use(rootProperties::load)
                storeFile = rootProject.file("../${rootProperties.getProperty("storeFile")}")
                storePassword = rootProperties.getProperty("storePassword")
                keyAlias = rootProperties.getProperty("keyAlias")
                keyPassword = rootProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
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
    implementation(files("../../native/android/nkas-tsnet.aar"))
    implementation("androidx.core:core-ktx:1.13.1")
    implementation("org.bouncycastle:bcpkix-jdk18on:1.85")
    implementation("org.conscrypt:conscrypt-android:2.7.0")
    testImplementation("junit:junit:4.13.2")
}

val scrcpyServerAssetDir = "${project.projectDir}/src/main/assets/bin"
val scrcpyServerAssetFile = "$scrcpyServerAssetDir/scrcpy-server-v4.1"
val scrcpyServerDownloadUrl = "https://github.com/Genymobile/scrcpy/releases/download/v4.1/scrcpy-server-v4.1"
val scrcpyServerSha256 = "deacb991ed2509715160ffdc7907e47b4160eb30d1566217e9047fd5b8850cae"

val downloadScrcpyServer by tasks.registering {
    description = "Download and verify the scrcpy server used by the native launcher"
    group = "build setup"
    outputs.file(scrcpyServerAssetFile)
    doLast {
        val file = outputs.files.singleFile
        if (!file.parentFile.exists()) file.parentFile.mkdirs()
        fun sha256(target: java.io.File): String = target.inputStream().use { input ->
            val digest = MessageDigest.getInstance("SHA-256")
            val buffer = ByteArray(8192)
            var count: Int
            while (input.read(buffer).also { count = it } >= 0) digest.update(buffer, 0, count)
            digest.digest().joinToString("") { "%02x".format(it) }
        }
        if (!file.exists() || sha256(file) != scrcpyServerSha256) {
            URI(scrcpyServerDownloadUrl).toURL().openStream().use { input ->
                file.outputStream().use { output -> input.copyTo(output) }
            }
            check(sha256(file) == scrcpyServerSha256) { "scrcpy-server-v4.1 SHA-256 mismatch" }
        }
    }
}

tasks.named("preBuild") { dependsOn(downloadScrcpyServer) }

val verifyTsnetBinding by tasks.registering {
    doLast {
        check(file("../../native/android/nkas-tsnet.aar").isFile) {
            "Missing native tsnet binding. Run python tool/build_tsnet.py android from the repository root first."
        }
    }
}
tasks.named("preBuild") { dependsOn(verifyTsnetBinding) }
