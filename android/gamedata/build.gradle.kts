plugins {
    id("org.jetbrains.kotlin.jvm")
    id("org.jetbrains.kotlin.plugin.serialization")
    id("java-library")
}

kotlin {
    compilerOptions {
        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
    }
}

java {
    sourceCompatibility = JavaVersion.VERSION_17
    targetCompatibility = JavaVersion.VERSION_17
}

sourceSets {
    // 与 :catalog 相同：测试直接读仓库根 data/，不在工程里复制 JSON
    named("test") {
        resources.srcDirs("../../data")
    }
}

dependencies {
    api(project(":rules"))    // 各页的解析结果会引用 Affix / CheckMode 等规则类型
    api(project(":catalog"))  // 词条反查、增伤排名要与词条库对照
    // GameDataJson.lenient 的类型是 Json，属于公开 API
    api("org.jetbrains.kotlinx:kotlinx-serialization-json:1.9.0")

    testImplementation(kotlin("test-junit"))
}

tasks.test {
    useJUnit()
}
