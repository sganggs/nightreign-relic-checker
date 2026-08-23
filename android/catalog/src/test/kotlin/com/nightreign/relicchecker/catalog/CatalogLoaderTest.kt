package com.nightreign.relicchecker.catalog

import com.nightreign.relicchecker.rules.CheckMode
import com.nightreign.relicchecker.rules.CheckStatus
import com.nightreign.relicchecker.rules.LegalityChecker
import com.nightreign.relicchecker.rules.matchesSearch
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertNotNull
import kotlin.test.assertTrue
import kotlin.random.Random

class CatalogLoaderTest {
    private val catalog by lazy {
        val stream = assertNotNull(javaClass.classLoader.getResourceAsStream(CatalogLoader.ASSET_FILE_NAME))
        CatalogLoader.parse(stream.bufferedReader().use { it.readText() })
    }

    @Test
    fun `real authoritative catalog metadata and counts are stable`() {
        assertEquals(1, catalog.schemaVersion)
        assertEquals("v1.03.4 + DLC1", catalog.gameVersion)
        assertEquals("Param 0d2ad149", catalog.dataVersion)
        assertEquals(527, catalog.affixes.size)
        assertEquals(503, catalog.affixes.count { !it.isCurse })
        assertEquals(24, catalog.affixes.count { it.isCurse })
        assertEquals(340, catalog.affixes.count { 110 in it.poolIds })
        assertEquals(290, catalog.affixes.count { 100 in it.poolIds })
        assertEquals(19, catalog.affixes.count { it.popularity != null })
        assertEquals(527, catalog.affixes.map { it.effectId }.toSet().size)
    }

    @Test
    fun `real current and legacy candidates occupy every normal slot pool`() {
        val current = catalog.affixes.filter { 110 in it.poolIds }
        val legacy = catalog.affixes.filter { 100 in it.poolIds }

        assertTrue(current.all { 210 in it.poolIds && 310 in it.poolIds })
        assertTrue(legacy.all { 200 in it.poolIds && 300 in it.poolIds })
    }

    @Test
    fun `real deep pool facts and reported AAA sample are preserved`() {
        val deepUnion = catalog.affixes.filter {
            it.poolIds.any(setOf(2_000_000, 2_100_000, 2_200_000)::contains)
        }
        assertEquals(332, deepUnion.size)
        assertEquals(49, catalog.affixes.count { 2_000_000 in it.poolIds })
        assertEquals(277, catalog.affixes.count { 2_100_000 in it.poolIds })
        assertEquals(283, catalog.affixes.count { 2_200_000 in it.poolIds })

        val ids = listOf(6_005_601, 6_610_400, 6_611_002)
        val sample = ids.map { id -> catalog.affixes.single { it.effectId == id } }
        assertTrue(sample.all { it.poolIds == listOf(2_000_000) && it.requiresCurse })
        val result = LegalityChecker().check(sample, CheckMode.DEEP_POSITIVE)
        assertEquals(com.nightreign.relicchecker.rules.CheckStatus.VALID, result.status)
        assertTrue(result.message.contains("不等同"))
    }

    @Test
    fun `real catalog search finds aliases full width text category and id`() {
        val life = catalog.affixes.single { it.effectId == 7_000_000 }
        assertTrue(life.matchesSearch("生命 力+1"))
        assertTrue(life.matchesSearch("能力"))
        assertTrue(life.matchesSearch("7000000"))

        val aliasOnly = catalog.affixes.single { it.effectId == 6_030_800 }
        assertTrue(aliasOnly.matchesSearch("加快累积绝招量表+1"))
    }

    @Test
    fun `random combinations from the real catalog are canonical and legal`() {
        val checker = LegalityChecker()
        CheckMode.entries.forEachIndexed { index, mode ->
            val combination = assertNotNull(
                checker.randomCombination(catalog.affixes, mode, Random(100 + index)),
                "mode=$mode",
            )
            assertEquals(3, combination.map { it.effectId }.toSet().size)
            assertEquals(checker.canonicalOrder(combination), combination)
            assertEquals(CheckStatus.VALID, checker.check(combination, mode).status)
        }
    }

    @Test
    fun `catalog rejects unsupported schema and duplicate ids`() {
        val unsupported = minimalJson(schema = 2)
        assertFailsWith<CatalogFormatException> { CatalogLoader.parse(unsupported) }

        val duplicate = catalogJson(
            fullAffix(effectId = 1, name = "a"),
            fullAffix(effectId = 1, name = "b"),
            fullAffix(effectId = 2, name = "c"),
        )
        assertFailsWith<CatalogFormatException> { CatalogLoader.parse(duplicate) }
    }

    @Test
    fun `catalog rejects fewer than three positive affixes`() {
        // 与桌面端 validateCatalog / CatalogLoader.swift 一致
        val tooFew = catalogJson(
            fullAffix(effectId = 1, name = "a"),
            fullAffix(effectId = 2, name = "b"),
            fullAffix(effectId = 3, name = "curse", isCurse = true),
        )
        assertFailsWith<CatalogFormatException> { CatalogLoader.parse(tooFew) }
    }

    @Test
    fun `catalog rejects affixes with missing required fields`() {
        // 必填字段缺失（如缺 poolIds/isCurse）应与桌面端一样在加载期拒绝
        val missingFields = """
            {
              "schemaVersion": 1,
              "gameVersion": "test",
              "dataVersion": "test",
              "generatedAt": "now",
              "sources": [],
              "affixes": [
                {"effectId":1,"name":"a","sortId":1},
                {"effectId":2,"name":"b","sortId":2},
                {"effectId":3,"name":"c","sortId":3}
              ]
            }
        """.trimIndent()
        assertFailsWith<CatalogFormatException> { CatalogLoader.parse(missingFields) }
    }

    private fun fullAffix(effectId: Int, name: String, isCurse: Boolean = false) = """
        {"effectId":$effectId,"name":"$name","aliases":[],"category":"测试","explanation":"",
         "superposability":"未知","compatibilityId":-1,"sortId":$effectId,"poolIds":[110],
         "isCurse":$isCurse,"requiresCurse":false,"popularity":null,"source":"test"}
    """.trimIndent()

    private fun catalogJson(vararg affixes: String) = """
        {
          "schemaVersion": 1,
          "gameVersion": "test",
          "dataVersion": "test",
          "generatedAt": "now",
          "sources": [],
          "affixes": [${affixes.joinToString(",")}]
        }
    """.trimIndent()

    private fun minimalJson(schema: Int) = """
        {
          "schemaVersion": $schema,
          "gameVersion": "test",
          "dataVersion": "test",
          "generatedAt": "now",
          "sources": [],
          "affixes": [${fullAffix(1, "a")},${fullAffix(2, "b")},${fullAffix(3, "c")}]
        }
    """.trimIndent()
}
