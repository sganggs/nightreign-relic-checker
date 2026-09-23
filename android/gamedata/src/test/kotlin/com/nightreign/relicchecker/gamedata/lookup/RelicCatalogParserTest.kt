package com.nightreign.relicchecker.gamedata.lookup

import com.nightreign.relicchecker.gamedata.GameDataFormatException
import com.nightreign.relicchecker.gamedata.GameDataJson
import com.nightreign.relicchecker.gamedata.lookup.LookupFixtures.catalog
import com.nightreign.relicchecker.gamedata.lookup.LookupFixtures.relicData
import com.nightreign.relicchecker.gamedata.lookup.LookupFixtures.relicsJson
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonObject
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class RelicCatalogParserTest {
    @Test
    fun `relic catalog decodes the real file with its counts`() {
        assertEquals(1, relicData.relicsSchemaVersion)
        assertTrue(relicData.gameVersion.startsWith("v1.03.4"), relicData.gameVersion)
        assertEquals("Param 0d2ad149", relicData.dataVersion)
        assertEquals(1397, relicData.relics.size)
        assertEquals(598, relicData.pools.size)
        assertEquals(1552, relicData.extraAffixes.size)
        assertEquals(13_496, relicData.pools.values.sumOf { it.size })
        assertEquals(listOf("Elden Ring Nightreign Save Editor"), relicData.sources.map { it.name })
        assertTrue(relicData.sources.single().license == "MIT")

        // 词条库仍是 527 条（由 :catalog 载入，本页直接复用）
        assertEquals(527, catalog.affixes.size)
        // 物品表补充与词条库没有重叠：索引条目 = 527 + 1552
        val catalogIds = catalog.affixes.map { it.effectId }.toSet()
        assertTrue(relicData.extraAffixes.none { it.effectId in catalogIds })

        val shop = relicData.relics.first { it.id == 202 }
        assertEquals(RelicInfo(202, "辽阔的火燃情景", 0, false, listOf(310, 210, 110), listOf(-1, -1, -1)), shop)
        val deep = relicData.relics.first { it.id == 2_000_002 }
        assertEquals(listOf(2_000_000, 2_100_000, 2_100_000), deep.slots)
        assertEquals(listOf(3_000_000, -1, -1), deep.curseSlots)
        assertTrue(deep.deep)
    }

    @Test
    fun `missing or mismatched schema version is rejected so the page degrades`() {
        // Windows：buildLookupIndex 在物品表缺失 / 版本不符时抛错，页面据此降级
        assertFailsWith<GameDataFormatException> { RelicCatalogParser.parse("""{"relics":[]}""") }
        assertFailsWith<GameDataFormatException> { RelicCatalogParser.parse("""{"relicsSchemaVersion":2,"relics":[]}""") }
        assertFailsWith<GameDataFormatException> { RelicCatalogParser.parse("""{"relicsSchemaVersion":""") }
        val error = assertFailsWith<GameDataFormatException> { RelicCatalogParser.parse("""{"relicsSchemaVersion":0}""") }
        assertTrue(error.message!!.contains("nightreign-relics-v1.03.4.json"))
    }

    @Test
    fun `non numeric pool keys are skipped and missing fields fall back to defaults`() {
        val parsed = RelicCatalogParser.parse(
            """{"relicsSchemaVersion":1,"pools":{"x":[1],"12":[7000000,7000000]},
               "relics":[{"id":5,"slots":[12]}],"extraAffixes":[{"effectId":9}]}""",
        )
        assertEquals(mapOf(12 to listOf(7_000_000, 7_000_000)), parsed.pools)
        assertEquals(RelicInfo(5, "", -1, false, listOf(12), emptyList()), parsed.relics.single())
        assertEquals(ExtraAffix(9, "", 0, -1), parsed.extraAffixes.single())

        // 重复成员去重、缺失的槽位按 -1 处理
        val index = AffixLookupIndex(catalog, parsed)
        assertEquals(listOf(7_000_000), index.poolMembers[12])
        assertEquals(listOf(12, -1, -1), index.relic(5)!!.slots.map { it.poolId })
    }

    @Test
    fun `datasets carry no caveats block`() {
        // Windows datasetCaveats：两份数据集都没有 caveats 字段，页面不需要渲染这一块
        val relicsRoot = GameDataJson.lenient.parseToJsonElement(relicsJson).jsonObject
        assertFalse(relicsRoot.containsKey("caveats"))
        assertNull((relicsRoot as JsonObject)["caveats"])
    }

    @Test
    fun `relic labels follow the audit id ranges`() {
        // Windows isUniqueRelicId：与 core.js 的唯一遗物 ID 区间一致
        assertTrue(isUniqueRelicId(1000))
        assertTrue(isUniqueRelicId(2100))
        assertFalse(isUniqueRelicId(2101))
        assertTrue(isUniqueRelicId(10000))
        assertTrue(isUniqueRelicId(19999))
        assertFalse(isUniqueRelicId(202))

        assertEquals("商店遗物（旧版）", relicKindLabel(150, null))
        assertEquals("商店遗物", relicKindLabel(202, null))
        assertEquals("唯一遗物", relicKindLabel(1000, null))
        assertEquals("对局奖励", relicKindLabel(1_000_000, null))
        assertEquals("遗物", relicKindLabel(20_000, null))
        assertEquals("深夜遗物", relicKindLabel(1000, RelicInfo(1000, "x", 0, true, emptyList(), emptyList())))
        assertEquals(listOf("红", "蓝", "黄", "绿", "白", "未知"), listOf(0, 1, 2, 3, 4, 9).map(::relicColorLabel))
        assertEquals("未知遗物 #7", relicDisplayName(7, null))
        assertEquals("未命名遗物 #7", relicDisplayName(7, RelicInfo(7, "", 0, false, emptyList(), emptyList())))
    }
}
