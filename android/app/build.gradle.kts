plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
}

android {
    namespace = "com.nightreign.relicchecker"
    compileSdk = 36

    defaultConfig {
        applicationId = "com.nightreign.relicchecker"
        minSdk = 26
        targetSdk = 36
        versionCode = 2
        versionName = "0.3.0"

        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }

    sourceSets {
        named("main") {
            assets.srcDirs("../../data")
        }
    }

    androidResources {
        // data/ 是唯一权威数据源，六个数据集（词条库、遗物物品表与四个 v1.03.5 参数表数据集）
        // 全部打进 APK：词条反查 / 存档检查要用遗物物品表，数据页各读自己的数据集。
        // 只排除系统杂项文件。
        ignoreAssetsPattern = "!.ds_store:!*~"
    }

    buildFeatures {
        compose = true
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    packaging {
        resources.excludes += "/META-INF/{AL2.0,LGPL2.1}"
    }
}

kotlin {
    compilerOptions {
        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
    }
}

dependencies {
    implementation(project(":rules"))
    implementation(project(":catalog"))
    implementation(project(":gamedata"))

    // Newer AndroidX releases require API 37 / AGP 9.1; keep the API 36-compatible line.
    implementation(platform("androidx.compose:compose-bom:2025.08.01"))
    implementation("androidx.activity:activity-compose:1.10.1")
    implementation("androidx.core:core-ktx:1.16.0")
    implementation("androidx.datastore:datastore-preferences:1.2.1")
    implementation("androidx.compose.foundation:foundation")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.ui:ui-tooling-preview")

    debugImplementation("androidx.compose.ui:ui-tooling")
    testImplementation("junit:junit:4.13.2")
}
