plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.plugin.compose")
}

// Release signing: apps/android/keystore.properties (not in git) with storeFile, storePassword, keyAlias, keyPassword.
// Without it, assembleRelease still builds, but the APK is unsigned.
val keystoreProps: Map<String, String> = rootProject.file("keystore.properties").let { f ->
    if (!f.exists()) emptyMap()
    else f.readLines().filter { "=" in it && !it.startsWith("#") }.associate { it.substringBefore("=").trim() to it.substringAfter("=").trim() }
}

android {
    namespace = "app.kartei"
    compileSdk = 36
    defaultConfig {
        applicationId = "pro.geist.bergmoench"
        minSdk = 26
        targetSdk = 36
        versionCode = 1
        versionName = "0.1.0"
        ndk { abiFilters += "arm64-v8a" }
    }
    signingConfigs {
        if ("storeFile" in keystoreProps) {
            create("release") {
                storeFile = file(keystoreProps.getValue("storeFile"))
                storePassword = keystoreProps.getValue("storePassword")
                keyAlias = keystoreProps.getValue("keyAlias")
                keyPassword = keystoreProps.getValue("keyPassword")
            }
        }
    }
    buildTypes {
        release {
            isMinifyEnabled = false
            signingConfig = signingConfigs.findByName("release")
        }
    }
    buildFeatures { compose = true }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    sourceSets["main"].java.srcDirs("../../../core/gen/java")
    sourceSets["main"].kotlin.srcDirs("../../../core/gen/kotlin")
    packaging { jniLibs { useLegacyPackaging = false } }
}

dependencies {
    implementation(platform("androidx.compose:compose-bom:2025.05.00"))
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.foundation:foundation")
    implementation("androidx.activity:activity-compose:1.10.1")
    implementation("androidx.lifecycle:lifecycle-viewmodel-compose:2.9.0")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.10.2")
    // Must match the protoc that generated core/gen/java (protoc 36.x -> 4.36.x).
    implementation("com.google.protobuf:protobuf-javalite:4.36.2")
    testImplementation("junit:junit:4.13.2")
}
