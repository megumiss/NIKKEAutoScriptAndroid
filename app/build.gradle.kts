import java.util.Properties

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

val appVersionName = "0.3.30"
val keystorePropertiesFile = rootProject.file("keystore.properties")
val keystoreProperties = Properties().apply {
    if (keystorePropertiesFile.exists()) load(keystorePropertiesFile.inputStream())
}

android {
    namespace = "com.megumiss.nkas"
    compileSdk = 35

    defaultConfig {
        applicationId = "com.megumiss.nkas.mobile"
        minSdk = 30
        targetSdk = 35
        versionCode = 41
        versionName = appVersionName
    }

    signingConfigs {
        create("release") {
            if (keystorePropertiesFile.exists()) {
                storeFile = rootProject.file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            if (keystorePropertiesFile.exists()) {
                signingConfig = signingConfigs.getByName("release")
            }
        }
    }

    lint {
        checkReleaseBuilds = false
    }

    splits {
        abi {
            isEnable = true
            reset()
            include("armeabi-v7a", "arm64-v8a", "x86", "x86_64")
            isUniversalApk = true
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions { jvmTarget = "17" }
    packaging { resources.excludes += "/META-INF/{AL2.0,LGPL2.1}" }
}

fun registerVersionedApks(variant: String) = tasks.register("versioned${variant.replaceFirstChar { it.uppercase() }}Apks") {
    doLast {
        val outputDir = layout.buildDirectory.dir("outputs/apk/$variant").get().asFile
        outputDir.listFiles { file -> file.extension == "apk" && !file.name.startsWith("nkas-mobile-v") }
            ?.forEach { apk ->
                val abi = when {
                    apk.name.contains("x86_64", ignoreCase = true) -> "x86_64"
                    apk.name.contains("x86", ignoreCase = true) -> "x86"
                    apk.name.contains("arm64-v8a", ignoreCase = true) -> "arm64-v8a"
                    apk.name.contains("armeabi-v7a", ignoreCase = true) -> "armeabi-v7a"
                    else -> "universal"
                }
                apk.copyTo(File(outputDir, "nkas-mobile-v$appVersionName-$abi.apk"), overwrite = true)
            }
    }
}

val versionedDebugApks = registerVersionedApks("debug")
val versionedReleaseApks = registerVersionedApks("release")

afterEvaluate {
    tasks.named("assembleDebug") { finalizedBy(versionedDebugApks) }
    tasks.named("assembleRelease") { finalizedBy(versionedReleaseApks) }
}

dependencies {
    implementation("androidx.core:core-ktx:1.13.1")
    implementation("androidx.drawerlayout:drawerlayout:1.2.0")
}
