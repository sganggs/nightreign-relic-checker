package com.nightreign.relicchecker.gamedata

import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertNotNull
import kotlin.test.assertTrue

class GameDataFilesTest {
    private fun readText(key: GameDataKey): String {
        val stream = assertNotNull(
            javaClass.classLoader.getResourceAsStream(key.fileName),
            "data/ 下缺少 ${key.fileName}",
        )
        return stream.bufferedReader(Charsets.UTF_8).use { it.readText() }
    }

    private val roots: Map<GameDataKey, JsonObject> by lazy {
        GameDataKey.entries.associateWith { key ->
            GameDataJson.lenient.parseToJsonElement(readText(key)).jsonObject
        }
    }

    @Test
    fun `file name constants match the data directory exactly`() {
        assertEquals("nightreign-bosses-v1.03.5.json", GameDataFiles.BOSSES)
        assertEquals("nightreign-skills-v1.03.5.json", GameDataFiles.SKILLS)
        assertEquals("nightreign-buffs-v1.03.5.json", GameDataFiles.BUFFS)
        assertEquals("nightreign-heroes-v1.03.5.json", GameDataFiles.HEROES)
        assertEquals("nightreign-relics-v1.03.4.json", GameDataFiles.RELICS)
        assertEquals(GameDataFiles.all, GameDataKey.entries.map(GameDataKey::fileName))
    }

    @Test
    fun `every dataset parses and declares the expected schema version`() {
        val expected = mapOf(
            GameDataKey.BOSSES to ("bossesSchemaVersion" to 4),
            GameDataKey.SKILLS to ("schemaVersion" to 2),
            GameDataKey.BUFFS to ("schemaVersion" to 6),
            GameDataKey.HEROES to ("schemaVersion" to 1),
            GameDataKey.RELICS to ("relicsSchemaVersion" to 1),
        )
        GameDataKey.entries.forEach { key ->
            val (field, version) = expected.getValue(key)
            assertEquals(field, key.versionField, key.name)
            assertEquals(version, key.expectedVersion, key.name)
            val root = roots.getValue(key)
            assertEquals(version, root[field]?.jsonPrimitive?.int, "${key.fileName} 的 $field")
            GameDataJson.requireVersion(key, root[field]?.jsonPrimitive?.int)
        }
    }

    @Test
    fun `datasets carry the game versions the pages describe`() {
        listOf(GameDataKey.BOSSES, GameDataKey.SKILLS, GameDataKey.BUFFS, GameDataKey.HEROES).forEach { key ->
            val version = roots.getValue(key)["gameVersion"]?.jsonPrimitive?.content.orEmpty()
            assertTrue(version.startsWith("v1.03.5"), "${key.fileName} gameVersion=$version")
        }
        val relics = roots.getValue(GameDataKey.RELICS)["gameVersion"]?.jsonPrimitive?.content.orEmpty()
        assertTrue(relics.startsWith("v1.03.4"), "relics gameVersion=$relics")
    }

    @Test
    fun `top level collections the pages rely on are present`() {
        val expectedArrays = mapOf(
            GameDataKey.BOSSES to listOf("nightlords", "nightBosses"),
            GameDataKey.SKILLS to listOf("weapons", "skills", "spells"),
            GameDataKey.BUFFS to listOf("buffs", "weaponAffixes", "fixedRelics"),
            GameDataKey.HEROES to listOf("heroes", "statModifiers", "libraRespecs"),
            GameDataKey.RELICS to listOf("relics", "extraAffixes"),
        )
        expectedArrays.forEach { (key, fields) ->
            val root = roots.getValue(key)
            fields.forEach { field ->
                val array = root[field] as? JsonArray
                assertNotNull(array, "${key.fileName} 缺少数组 $field")
                assertTrue(array.isNotEmpty(), "${key.fileName} 的 $field 为空")
            }
        }
        assertTrue(roots.getValue(GameDataKey.RELICS)["pools"] is JsonObject)
        assertTrue(roots.getValue(GameDataKey.BUFFS)["slotRules"] is JsonObject)
    }

    @Test
    fun `lenient json decodes only declared fields of a real dataset`() {
        // 推荐写法：根 DTO 只声明要用的字段，大文件其余部分被跳过
        val probe = GameDataJson.decode<HeroesProbe>(GameDataKey.HEROES, readText(GameDataKey.HEROES))
        GameDataJson.requireVersion(GameDataKey.HEROES, probe.schemaVersion)
        assertEquals(10, probe.heroes.size)
        assertTrue(probe.heroes.all { it.id > 0 && it.nameZh.isNotBlank() })
        assertEquals("追踪者", probe.heroes.first().nameZh)
    }

    @Test
    fun `shared header parses every dataset and checks its version`() {
        GameDataKey.entries.forEach { key ->
            val header = GameDataHeader.parse(key, readText(key))
            assertEquals(key.expectedVersion, header.versionOf(key), key.name)
            assertTrue(header.generatedAt.isNotBlank(), key.name)
        }
        listOf(GameDataKey.BOSSES, GameDataKey.SKILLS, GameDataKey.BUFFS, GameDataKey.HEROES).forEach { key ->
            assertEquals("regulation 10350000", GameDataHeader.parse(key, readText(key)).dataVersion, key.name)
        }
        assertEquals("Param 0d2ad149", GameDataHeader.parse(GameDataKey.RELICS, readText(GameDataKey.RELICS)).dataVersion)

        // 版本键不对的文件应被拒绝，而不是按错误口径展示
        assertFailsWith<GameDataFormatException> {
            GameDataHeader.parse(GameDataKey.BOSSES, """{"schemaVersion":4,"gameVersion":"x"}""")
        }
    }

    @Test
    fun `lenient json ignores unknown keys and coerces nulls to defaults`() {
        val decoded = GameDataJson.lenient.decodeFromString<Probe>(
            """{"schemaVersion":6,"label":null,"extra":{"nested":[1,2,3]}}""",
        )
        assertEquals(Probe(schemaVersion = 6, label = "默认"), decoded)
    }

    @Test
    fun `version and format errors are reported with the file name`() {
        val mismatch = assertFailsWith<GameDataFormatException> {
            GameDataJson.requireVersion(GameDataKey.BUFFS, 5)
        }
        assertTrue(mismatch.message!!.contains(GameDataFiles.BUFFS))

        val missing = assertFailsWith<GameDataFormatException> {
            GameDataJson.requireVersion(GameDataKey.BOSSES, null)
        }
        assertTrue(missing.message!!.contains("bossesSchemaVersion"))

        val broken = assertFailsWith<GameDataFormatException> {
            GameDataJson.decode<Probe>(GameDataKey.SKILLS, """{"schemaVersion":"""")
        }
        assertTrue(broken.message!!.contains(GameDataFiles.SKILLS))
    }

    @Serializable
    private data class Probe(val schemaVersion: Int = 0, val label: String = "默认")

    @Serializable
    private data class HeroesProbe(val schemaVersion: Int? = null, val heroes: List<HeroProbe> = emptyList())

    @Serializable
    private data class HeroProbe(val id: Int = 0, val nameZh: String = "")
}
