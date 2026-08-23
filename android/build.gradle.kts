plugins {
    id("com.android.application") version "8.13.2" apply false
    id("org.jetbrains.kotlin.android") version "2.2.20" apply false
    id("org.jetbrains.kotlin.jvm") version "2.2.20" apply false
    id("org.jetbrains.kotlin.plugin.serialization") version "2.2.20" apply false
    id("org.jetbrains.kotlin.plugin.compose") version "2.2.20" apply false
}

tasks.register("testDebugUnitTest") {
    group = "verification"
    description = "Runs JVM rule/catalog tests and Android debug unit tests."
    dependsOn(":rules:test", ":catalog:test", ":app:testDebugUnitTest")
}
