import java.util.Properties
plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}
android {
    signingConfigs {
        create("release") {
            val props = Properties()
            val lp = rootProject.file("local.properties")
            if (lp.exists()) lp.inputStream().use { props.load(it) }
            fun pick(key: String, def: String): String = props.getProperty(key) ?: System.getenv(key) ?: def
            storeFile = rootProject.file(pick("KEYSTORE_FILE", "release.keystore"))
            storePassword = pick("KEYSTORE_PASSWORD", "android")
            keyAlias = pick("KEY_ALIAS", "android")
            keyPassword = pick("KEY_PASSWORD", "android")
        }
    }
    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
            isMinifyEnabled = false
        }
    }
    lint {
        checkReleaseBuilds = false
        abortOnError = false
    }
    namespace = "com.example.schedule"
    compileSdk = 34
    defaultConfig {
        applicationId = "com.example.schedule"
        minSdk = 30
        targetSdk = 34
        versionCode = (System.getenv("VERSION_CODE") ?: "1").toInt()
        versionName = System.getenv("VERSION_NAME") ?: "1.0"
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions { jvmTarget = "17" }
    buildFeatures { compose = true; buildConfig = true }
    composeOptions { kotlinCompilerExtensionVersion = "1.5.14" }
}
dependencies {
    implementation(platform("androidx.compose:compose-bom:2024.06.00"))
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.foundation:foundation")
    implementation("androidx.compose.material:material-icons-extended")
    implementation("androidx.wear.compose:compose-material:1.4.0")
    implementation("androidx.wear.compose:compose-foundation:1.4.0")
    implementation("androidx.activity:activity-compose:1.9.0")
    implementation("com.google.android.gms:play-services-wearable:18.2.0")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.8.1")
}
