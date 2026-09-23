package com.nightreign.relicchecker.gamedata.bosses

import com.nightreign.relicchecker.gamedata.GameDataFiles
import com.nightreign.relicchecker.gamedata.GameDataFormatException
import com.nightreign.relicchecker.gamedata.GameDataJson
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * 宽容解码（macOS BossDataChecks 第 13、14 节）：未知字段忽略、缺字段退默认值、null 退默认值、
 * 带引号的数字照读；读不懂的数据报带文件名的错误而不是崩溃。
 *
 * 坏元素只丢它自己（macOS BossFailable 同口径）：快路径是流式解码到 DTO（不建 JSON 树），
 * 失败时才走 BossesTolerant 的逐项回退，把坏元素 / 坏字典项 / 类型不对的字段丢掉后重新解码。
 */
class BossLenientTest {
    private val lenientJson = """
    {
      "bossesSchemaVersion": 2,
      "futureTopLevelField": {"whatever": [1, 2, 3]},
      "caveats": ["测试"],
      "scalingTiers": {"7760": {"group": "X", "duo": {"hp": 2}}, "not-a-number": {"group": "Y"}},
      "permanentScaling": {"7767": {"nameZh": "测试缩放", "hp": 1.5, "deepOfNight": true}},
      "nightlords": [
        {
          "menuId": 1,
          "nameZh": "测试夜王",
          "brandNewField": "忽略我",
          "fights": [
            {"npcId": 1, "labelZh": "甲", "hp": "4200", "poise": 100, "unknown": true,
             "damageRates": {"holy": 2}, "resist": {"madness": 999},
             "scaling": {"duo": {"hp": 2, "poiseTaken": 0.5}}}
          ]
        }
      ],
      "nightBosses": [
        {"nameEn": "Test Boss", "chrIds": [4500], "tier": "field",
         "variants": [{"npcId": 9, "labelZh": "乙"}]}
      ]
    }
    """.trimIndent()

    @Test
    fun `未知字段忽略 缺字段退默认值 带引号的数字照读`() {
        val index = BossesParser.parseUnchecked(lenientJson)
        val dataset = index.dataset
        assertEquals(2, dataset.schemaVersion)
        assertEquals(listOf("测试"), dataset.caveats)
        assertEquals(1, dataset.nightlords.size)
        val lord = dataset.nightlords.single()
        val fight = lord.fights.single()
        assertTrue(lord.nameEn.isEmpty() && lord.expeditionZh.isEmpty(), "缺失的字符串字段应退为空串")
        assertTrue(lord.weakness.isEmpty() && lord.variantKey == "normal", "缺失的数组 / 变体字段应有默认值")
        assertEquals(4200, fight.hp, "字符串形式的数字也应能解出")
        assertEquals(8400, fight.hp(BossPartySize.DUO), "缺档的字段不应影响换算")
        assertEquals(4200, fight.hp(BossPartySize.TRIO), "缺 trio 档时按单人处理")
        assertEquals(200.0, fight.effectivePoise(BossPartySize.DUO), "poiseTakenBase 缺失时应按 1 处理")
        assertEquals(1.0, fight.damageRates.standard, "缺失的承伤倍率应退为 1")
        assertEquals(2.0, fight.damageRates.holy)
        assertTrue(fight.resist.isImmune(BossAilmentKind.MADNESS), "只给一项的 resist 也应能解出")
        assertEquals(listOf(BossAilmentKind.MADNESS), fight.immuneKinds(), "immune 缺失时应按 999 回推免疫列表")
        assertNull(fight.deepOfNight)
        assertFalse(fight.hasDeepOfNight)
        assertEquals(listOf(1), fight.npcIds, "npcIds 缺失时退为 [npcId]")
        assertEquals(2.0, dataset.scalingGroup(7760)?.duo?.hp, "scalingTiers 应能按 ID 反查")
        assertEquals(1, dataset.scalingTiers.size, "转不成数字的键丢掉")
        assertEquals(true, dataset.permanentEffect(7767)?.deepOfNight, "permanentScaling 应能按 ID 反查")
        assertEquals("Test Boss@4500", dataset.nightBosses.single().id, "缺 id 时应按 nameEn@chrId 回填")
        assertEquals("field", dataset.nightBosses.single().tier)
        val card = index.cards.first { it.id == "boss-Test Boss@4500" }
        assertFalse(card.hasRoles)
        assertEquals(listOf(BossGroup.OTHER), card.groups, "没有 roles 的组归「其它场合」，不退回按 tier 分组")
        assertFalse(card.isHiddenByDefault)
        assertTrue(index.cards(BossGroup.FIELD).isEmpty(), "tier = field 却没有 roles 的组不进「场景头目」")
        assertEquals(listOf(BossGroup.NIGHTLORD), index.cards.first { it.isNightlord }.groups)
        assertEquals(BossDeepOfNightText.FALLBACK, dataset.deepOfNightText)
        assertTrue(dataset.mutations.isEmpty() && dataset.roleNames.isEmpty())
        assertEquals("未知", dataset.gameVersion)
    }

    @Test
    fun `null 退默认值 数据里真实的 0 照原样用`() {
        val row = BossesParser.parseFight(
            """{"npcId":1,"labelZh":null,"hp":1000,"hpMultiplier":null,"poise":null,"poiseTakenBase":0,
               "threat":null,"roles":null,"depthStats":null,"scaling":{"duo":null}}""",
        )
        assertEquals("", row.labelZh)
        assertEquals("行 1", row.displayLabel)
        assertEquals(1.0, row.hpMultiplier)
        assertEquals(-1.0, row.poise, "poise 为 null 时退回 -1（不吃削韧）")
        assertEquals(0.0, row.poiseTakenBase)
        assertNull(row.threat)
        assertTrue(row.roles.isEmpty() && row.depthStats.isEmpty())
        assertEquals(BossScalingTier.IDENTITY, row.tier(BossPartySize.DUO))
    }

    @Test
    fun `读不懂的数据报带文件名的错误而不是崩溃`() {
        val notObject = assertFailsWith<GameDataFormatException> { BossesParser.parseUnchecked("[]") }
        assertTrue(notObject.message!!.contains(GameDataFiles.BOSSES))
        val empty = assertFailsWith<GameDataFormatException> { BossesParser.parseUnchecked("{}") }
        assertEquals("首领数据里没有任何首领记录", empty.message)
        val truncated = assertFailsWith<GameDataFormatException> { BossesParser.parseUnchecked("""{"nightlords": [""") }
        assertTrue(truncated.message!!.contains(GameDataFiles.BOSSES), "截断的 JSON 应带上文件名与原始错误说明")
        assertFailsWith<GameDataFormatException> { BossesParser.parse(lenientJson) }.also {
            assertTrue(it.message!!.contains("bossesSchemaVersion"), "版本号不对时拒绝按错误口径展示")
        }
        // 回退也救不回来：顶层根本不是对象 / JSON 语法错时，报快路径的原始错误（带文件名）
        assertFailsWith<GameDataFormatException> { BossesParser.parseUnchecked("\"nightlords\"") }.also {
            assertTrue(it.message!!.contains(GameDataFiles.BOSSES))
        }
        // 坏元素全丢光之后没有首领记录：照常报「没有任何首领记录」
        assertEquals(
            "首领数据里没有任何首领记录",
            assertFailsWith<GameDataFormatException> { BossesParser.parseUnchecked("""{"nightlords":[1,2],"nightBosses":"x"}""") }.message,
        )
    }

    /** macOS BossDataChecks 第 13 节的宽容样本原样照搬（含三处坏元素），断言与那边同值。 */
    private val macSampleJson = """
    {
      "bossesSchemaVersion": 2,
      "futureTopLevelField": {"whatever": [1, 2, 3]},
      "caveats": ["测试"],
      "scalingTiers": {"7760": {"group": "X", "duo": {"hp": 2}}},
      "permanentScaling": {"7767": {"nameZh": "测试缩放", "hp": 1.5, "deepOfNight": true}},
      "nightlords": [
        12345,
        {
          "menuId": 1,
          "nameZh": "测试夜王",
          "brandNewField": "忽略我",
          "fights": [
            {"npcId": 1, "labelZh": "甲", "hp": "4200", "poise": 100, "unknown": true,
             "damageRates": {"holy": 2}, "resist": {"madness": 999},
             "scaling": {"duo": {"hp": 2, "poiseTaken": 0.5}}},
            "这一行不是对象"
          ]
        }
      ],
      "nightBosses": [
        {"nameEn": "Test Boss", "chrIds": [4500], "tier": "field",
         "variants": [{"npcId": 9, "labelZh": "乙"}]},
        {"nameEn": "Dual Boss", "chrIds": [4600], "tier": "night", "tiers": ["field", "night"],
         "npcNameId": 12345,
         "variants": [{"npcId": 10, "labelZh": "丙", "threat": "night", "roles": ["tower", "night", "night"],
                       "roleEvidence": {"night": [{"npcId": 10, "msb": "m49_24_00_00", "table": "LotResultPlayAreaParam",
                                                   "row": "bossId1 = 4924", "note": "测试"}, 42]},
                       "rowRoles": {"10": ["night", "tower"], "x": ["field"]}},
                      {"npcId": 11, "npcIds": [11, 12], "labelZh": "丁", "threat": "night",
                       "roles": ["unplaced", "field"], "rowRoles": {"11": ["field"], "12": ["unplaced"]}},
                      {"npcId": 13, "labelZh": "戊", "threat": "field", "roles": ["unplaced"]},
                      {"npcId": 14, "labelZh": "己", "roles": ["futureRole"]}]}
      ]
    }
    """.trimIndent()

    @Test
    fun `坏元素只丢它自己 与 macOS 宽容样本同值`() {
        val index = BossesParser.parseUnchecked(macSampleJson)
        val dataset = index.dataset
        assertEquals(1, dataset.nightlords.size, "坏的 nightlord 元素应被跳过")
        val lord = dataset.nightlords.single()
        assertEquals(1, lord.fights.size, "坏的 fight 元素应被跳过")
        val fight = lord.fights.single()
        assertEquals("测试夜王", lord.nameZh)
        assertEquals(4200, fight.hp, "字符串形式的数字也应能解出")
        assertEquals(8400, fight.hp(BossPartySize.DUO))
        assertEquals(200.0, fight.effectivePoise(BossPartySize.DUO))
        assertEquals(2.0, dataset.scalingGroup(7760)?.duo?.hp)
        assertEquals(true, dataset.permanentEffect(7767)?.deepOfNight)
        assertEquals(listOf("Test Boss@4500", "Dual Boss@4600"), dataset.nightBosses.map { it.id })
        val dual = index.cards.first { it.id == "boss-Dual Boss@4600" }
        assertEquals(listOf("night", "field", "tower", "unplaced", "futureRole"), dual.roles)
        assertEquals(listOf(BossGroup.NIGHT, BossGroup.FIELD, BossGroup.OTHER, BossGroup.UNPLACED), dual.groups)
        val row10 = dual.rows.first { it.npcId == 10 }
        assertEquals(1, row10.evidence("night").size, "roleEvidence 的坏元素跳过")
        assertTrue(row10.evidence("tower").isEmpty(), "缺出处的场合返回空数组")
        assertEquals("LotResultPlayAreaParam bossId1 = 4924 · m49_24_00_00", row10.evidence("night").single().summary)
        assertEquals(mapOf(10 to listOf("night", "tower")), row10.rowRoles, "rowRoles 里转不成 npcId 的键丢掉")
        assertEquals(listOf(10, 11, 14), dual.displayRows(false).map { it.npcId })
        assertTrue(index.cards(BossGroup.FIELD, "12345").any { it.id == dual.id }, "npcNameId 也应能搜到")
    }

    @Test
    fun `回退只拆坏掉的那条路径 类型不对的字段退默认值 字典里的坏项只丢那一项`() {
        val index = BossesParser.parseUnchecked(
            """{"caveats":["留下",5,"也留下"],"sources":"不是数组","gameVersion":1.03,
                "scalingTiers":{"7760":{"group":"X","duo":{"hp":2}},"7761":"坏项","7762":{"duo":{"hp":"两倍"}}},
                "nightBosses":[
                  {"id":"A","nameEn":"A","chrIds":[1,"x",2],"roles":["field"],
                   "variants":[{"npcId":1,"hp":true,"poise":50,"roles":["field"],"immune":["poison",7]},
                               null,
                               {"npcId":2,"hp":10,"roles":["field"],"damageRates":{"holy":"强"}}]},
                  {"id":"B","nameEn":"B","roles":["field"],"variants":[{"npcId":3,"hp":30,"roles":["field"]}],"hidden":"是"}
                ]}""",
        )
        val dataset = index.dataset
        assertEquals(listOf("留下", "也留下"), dataset.caveats, "数组里的坏元素只丢它自己")
        assertTrue(dataset.sources.isEmpty(), "类型不对的顶层字段退回默认值")
        assertEquals("未知", dataset.gameVersion, "数字写进字符串字段时退回默认值（macOS 会读成 \"1.03\"，见 BossesTolerant 注释）")
        assertEquals(2.0, dataset.scalingGroup(7760)?.duo?.hp, "字典里好的项照常保留")
        assertEquals(null, dataset.scalingGroup(7761), "字典里的坏项丢掉")
        assertEquals(1.0, dataset.scalingGroup(7762)?.duo?.hp, "字典项里类型不对的字段退回默认值，这一项本身保留")
        val a = dataset.nightBosses.first { it.id == "A" }
        assertEquals(listOf(1, 2), a.chrIds)
        assertEquals(listOf(1, 2), a.variants.map { it.npcId }, "null 行丢掉，其余两行保留")
        val row1 = a.variants.first { it.npcId == 1 }
        assertEquals(0, row1.hp, "hp 类型不对退回默认值 0，这一行照常保留")
        assertEquals(50.0, row1.poise)
        assertEquals(listOf("poison"), row1.immune)
        assertEquals(1.0, a.variants.first { it.npcId == 2 }.damageRates.holy, "承伤倍率里类型不对的一项退回 1")
        val b = dataset.nightBosses.first { it.id == "B" }
        assertFalse(b.hidden, "布尔字段类型不对退回 false")
        assertEquals(listOf("A", "B"), dataset.nightBosses.map { it.id })
    }

    @Test
    fun `随包数据集走快路径 不经过回退`() {
        // 快路径（流式解码）能直接解出随包数据集；回退只在它失败时才会被调用
        val strict = GameDataJson.lenient.decodeFromString(BossesFileDto.serializer(), BossTestData.text)
        assertEquals(4, strict.bossesSchemaVersion)
        assertEquals(strict.nightlords.size, BossTestData.dataset.nightlords.size)
        assertEquals(strict.nightBosses.size, BossTestData.dataset.nightBosses.size)
    }
}
