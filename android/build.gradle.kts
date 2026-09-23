plugins {
    id("com.android.application") version "8.13.2" apply false
    id("org.jetbrains.kotlin.android") version "2.2.20" apply false
    id("org.jetbrains.kotlin.jvm") version "2.2.20" apply false
    id("org.jetbrains.kotlin.plugin.serialization") version "2.2.20" apply false
    id("org.jetbrains.kotlin.plugin.compose") version "2.2.20" apply false
}

tasks.register("testDebugUnitTest") {
    group = "verification"
    description = "Runs JVM rule/catalog/gamedata tests and Android debug unit tests."
    dependsOn(":rules:test", ":catalog:test", ":gamedata:test", ":app:testDebugUnitTest")
}
