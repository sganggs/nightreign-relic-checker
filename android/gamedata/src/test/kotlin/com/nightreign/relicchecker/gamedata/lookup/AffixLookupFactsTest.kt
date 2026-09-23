package com.nightreign.relicchecker.gamedata.lookup

import com.nightreign.relicchecker.gamedata.lookup.LookupFixtures.DEEP_A_EFFECT
import com.nightreign.relicchecker.gamedata.lookup.LookupFixtures.catalog
import com.nightreign.relicchecker.gamedata.lookup.LookupFixtures.index
import com.nightreign.relicchecker.gamedata.lookup.LookupFixtures.relicData
import com.nightreign.relicchecker.rules.CheckMode
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * 词条反查的固定事实（数值口径以 macOS RelicCore/AffixLookup.swift 为准），以及与
 * macOS `AffixLookupChecks.swift` / Windows `lookup_index.test.mjs` 两端同一张对照表。
 * 表里任何一格改动都要三端一起改。
 */
class AffixLookupFactsTest {
    @Test
    fun `fixed facts - catalog size and obtainable relics`() {
        assertEquals(527, catalog.affixes.size, "词条库 527 条")
        assertEquals(768, index.obtainableRelicCount, "可查遗物 768 件")
        assertEquals(768, index.searchRelics("").size)
        assertEquals(527 + 1552, index.affixes.size, "词条条目 = 词条库 ∪ extraAffixes")
        assertEquals(1397, index.relics.size)
        assertEquals(222, index.relics.count { it.deep }, "物品表里的深夜遗物")
        assertEquals(216, index.searchRelics("", onlyDeep = true).size, "其中可查的深夜遗物")
        assertEquals(120, index.relics.count { it.isUnique }, "唯一遗物")
        assertTrue(index.relics.filter { it.isUnique }.all { it.fixedEffectIds != null }, "每件唯一遗物都能算出固定词条")
    }

    @Test
    fun `fixed facts - 7006700 drops nowhere at random and is fixed only on relics 2070 and 2071`() {
        val report = assertNotNull(index.report(7_006_700))
        assertEquals("提升战技攻击力", report.affix.name)
        assertTrue(report.affix.inCatalog)
        // 普通 1.03 / 普通旧池 / 深夜正面都不掉落
        assertEquals(listOf(false, false, false), report.modeHits.map { it.isAvailable })
        assertTrue(report.deepHits.none { it.contains })
        assertFalse(report.cursePoolHit.contains)
        // 固定出处只有 2070、2071（单词条固定池 707006700），没有随机池出处
        assertEquals(listOf(707_006_700), report.poolIds)
        assertEquals(listOf(2070, 2071), report.fixedRelics.map { it.relicId })
        assertEquals(listOf("安定者的遗志", "安定的遗志"), report.fixedRelics.map { it.relicName })
        assertTrue(report.fixedRelics.all { it.isFixed && it.poolIds == listOf(707_006_700) && it.kindLabel == "唯一遗物" })
        assertTrue(report.randomRelics.isEmpty())
        assertEquals(1, report.hiddenRelicCount, "池 707006700 另有一条不可获得的参数行")
        assertEquals(1, report.livePoolCount)
        // 三种口径都不可出、却有遗物固定带：页面会补一句 NOT_IN_NORMAL_POOLS_NOTE
        assertTrue(report.modeHits.none { it.isAvailable } && report.totalRelicCount > 0)
        assertEquals("这条词条不在任何深夜词条池里，深夜遗物不会出它。", report.deepNote)
        assertEquals(AffixConflictBranch.NO_GROUP, report.conflictBranch)
    }

    @Test
    fun `fixed facts - 6500000 sits in conflict group 900 of 68 and two live slot pools`() {
        val report = assertNotNull(index.report(6_500_000))
        assertEquals("【追踪者】技艺会附加引发异常状态出血的效果", report.affix.name)
        assertEquals(900, report.affix.compatibilityId)
        // 互斥组 900 共 68 条（含自己；页面写「共 68 条」），列出的同伴 67 条
        assertEquals(67, report.conflicts.size)
        assertEquals(68, report.conflicts.size + 1)
        assertEquals("同组词条不能出现在同一件遗物上，共 68 条", LookupCopy.conflictCardSubtitle(report.conflicts.size + 1, 0))
        assertTrue(report.conflicts.all { it.compatibilityId == 900 && it.appearsOnRelic && it.inCatalog })
        assertEquals(AffixConflictBranch.PEERS, report.conflictBranch)
        // 所在槽位池 2 个：深夜 B / C 池（另一个同名单条池只被超范围参数行引用，不算）
        assertEquals(listOf(2_100_000, 2_200_000, 6_500_000), report.poolIds)
        assertEquals(2, report.livePoolCount)
        assertEquals("2 个", LookupCopy.livePoolValue(report.livePoolCount))
        assertEquals(listOf(false, false, true), report.modeHits.map { it.isAvailable })
        assertEquals(listOf(false, true, true), report.deepHits.map { it.contains })
        assertTrue(report.fixedRelics.isEmpty())
        assertEquals(144, report.randomRelics.size)
        assertEquals(1, report.hiddenRelicCount)
    }

    @Test
    fun `fixed facts - deep A B C and curse pool sizes and relic counts`() {
        val expected = mapOf(
            2_000_000 to (49 to 144),
            2_100_000 to (277 to 72),
            2_200_000 to (283 to 72),
            3_000_000 to (24 to 144),
        )
        expected.forEach { (poolId, counts) ->
            assertEquals(counts.first, index.poolMembers.getValue(poolId).size, "池 $poolId 的条数")
            assertEquals(counts.second, index.relicCountByPool.getValue(poolId), "池 $poolId 的遗物数")
        }
        // 报告里的池命中用的是同一组数
        val report = index.report(DEEP_A_EFFECT)!!
        assertEquals(listOf(49, 277, 283), report.deepHits.map { it.memberCount })
        assertEquals(listOf(144, 72, 72), report.deepHits.map { it.relicCount })
        assertEquals(24, report.cursePoolHit.memberCount)
        assertEquals(144, report.cursePoolHit.relicCount)
        assertEquals("池 2000000 · 49 条 · 144 件遗物", LookupCopy.poolRowMeta(2_000_000, 49, 144))
        // 普通孔数层池
        assertEquals(listOf(340, 340, 340, 290, 290, 290), listOf(110, 210, 310, 100, 200, 300).map { index.poolMembers.getValue(it).size })
        assertEquals(listOf(36, 24, 12), listOf(110, 210, 310).map { index.relicCountByPool.getValue(it) })
    }

    // MARK: 深夜 A 池与诅咒配对（macOS checkAffixLookupDeepPoolA / checkDeepCursePairing）

    @Test
    fun `deep pool A affix 6001400 requires a curse and never drops from normal relics`() {
        val report = index.report(DEEP_A_EFFECT)!!
        assertEquals("提升物理攻击力＋３", report.affix.name)
        assertTrue(report.affix.requiresCurse)
        assertFalse(report.affix.isCurse)
        val modes = report.modeHits.associate { it.mode to it.isAvailable }
        assertEquals(true, modes[CheckMode.DEEP_POSITIVE])
        assertEquals(false, modes[CheckMode.CURRENT_NORMAL])
        assertEquals(false, modes[CheckMode.LEGACY_NORMAL])
        assertTrue(report.fixedRelics.isEmpty())
        assertTrue(report.randomRelics.isNotEmpty() && report.randomRelics.all { it.deep && it.role == RelicSlotRole.POSITIVE })
        assertTrue(report.hiddenRelicCount > 0)
        assertEquals(listOf(2_000_000, 6_001_400), report.poolIds)
        val rawPools = relicData.pools.filterValues { DEEP_A_EFFECT in it }.keys.sorted()
        assertEquals(rawPools, report.poolIds)

        val poolA = index.poolMembers.getValue(2_000_000)
        assertEquals(49, poolA.size)
        assertTrue(poolA.all { index.affix(it)!!.requiresCurse })
        assertTrue(index.poolMembers.getValue(2_100_000).all { !index.affix(it)!!.requiresCurse })
        assertTrue(index.poolMembers.getValue(2_200_000).all { !index.affix(it)!!.requiresCurse })

        // 深夜遗物模板：某一行有诅咒槽 ⇔ 该行的正面槽是 A 池
        relicData.relics.filter { it.deep }.forEach { relic ->
            for (row in 0 until 3) {
                val slot = relic.slots.getOrElse(row) { -1 }
                val curse = relic.curseSlots.getOrElse(row) { -1 }
                assertEquals(slot == 2_000_000, curse != -1, "深夜遗物 ${relic.id} 第 ${row + 1} 行")
                if (curse != -1) assertEquals(3_000_000, curse)
            }
        }
    }

    @Test
    fun `unique relic 1000 and affix 7121100 resolve in both directions`() {
        val entry = index.relic(1000)!!
        assertTrue(entry.isUnique)
        assertEquals("唯一遗物", entry.kindLabel)
        assertEquals("细腻的火燃情景", entry.displayName)
        assertTrue(entry.slots[0].poolId == 707_121_100 && entry.slots[0].isFixed)
        assertEquals(listOf(7_121_100, -1, -1), entry.fixedEffectIds)

        val report = index.report(7_121_100)!!
        assertEquals("出击时，会持有“火焰壶”", report.affix.name)
        assertTrue(report.fixedRelics.any { it.relicId == 1000 })
        assertTrue(report.randomRelics.any { it.relicId == 202 })
        assertTrue(report.fixedRelics.all { it.isFixed })
        assertTrue(report.randomRelics.none { it.isFixed })
        assertTrue(report.kindCounts.isNotEmpty())
        assertEquals(report.totalRelicCount, report.kindCounts.sumOf { it.count })
        report.kindCounts.zipWithNext { a, b -> assertTrue(a.count > b.count || (a.count == b.count && a.kind < b.kind)) }
    }

    // MARK: 双端对照表（macOS checkWindowsParitySamples ⇔ Windows 双端对照）

    private data class AffixSample(
        val effectId: Int,
        val name: String,
        val modes: List<Boolean>,
        val deepPools: List<Boolean>,
        val inCursePool: Boolean,
        val requiresCurse: Boolean,
        val isCurse: Boolean,
        val fixedRelicIds: List<Int>,
        val randomRelicCount: Int,
        val hiddenCount: Int,
        val conflictGroupSize: Int,
    )

    private data class RelicSample(
        val relicId: Int,
        val name: String,
        val kindLabel: String,
        val colorLabel: String,
        val deep: Boolean,
        val isUnique: Boolean,
        val slotCount: Int,
        val curseSlotCount: Int,
        val slotPools: List<Int>,
        val slotLabels: List<String>,
        val slotSizes: List<Int>,
        val deepGroups: List<List<Int>>?,
        val fixedEffectIds: List<Int>?,
    )

    @Test
    fun `parity - five affixes give the same conclusions as macOS and Windows`() {
        val samples = listOf(
            AffixSample(7_000_000, "生命力＋１", listOf(true, true, false), listOf(false, false, false), false, false, false, listOf(10002, 11003), 432, 1, 4),
            AffixSample(6_001_400, "提升物理攻击力＋３", listOf(false, false, true), listOf(true, false, false), false, true, false, emptyList(), 144, 1, 102),
            AffixSample(6_003_000, "提升对中毒的抵抗力＋１", listOf(false, false, true), listOf(false, true, true), false, false, false, emptyList(), 144, 1, 3),
            AffixSample(6_820_000, "受到损伤时，会累积中毒量表", listOf(false, false, false), listOf(false, false, false), true, false, true, emptyList(), 144, 1, 1),
            AffixSample(7_121_100, "出击时，会持有“火焰壶”", listOf(true, true, false), listOf(false, false, false), false, false, false, listOf(1000), 432, 2, 1),
        )
        samples.forEach { sample ->
            val report = assertNotNull(index.report(sample.effectId))
            val id = sample.effectId
            assertEquals(sample.name, report.affix.name, "$id 名称")
            assertEquals(sample.modes, report.modeHits.map { it.isAvailable }, "$id 三口径可掉落判定")
            assertEquals(sample.deepPools, report.deepHits.map { it.contains }, "$id 深夜 A/B/C 归属")
            assertEquals(sample.inCursePool, report.cursePoolHit.contains, "$id 诅咒池归属")
            assertEquals(sample.requiresCurse, report.affix.requiresCurse)
            assertEquals(sample.isCurse, report.affix.isCurse)
            assertEquals(sample.fixedRelicIds, report.fixedRelics.map { it.relicId }, "$id 固定出处")
            assertEquals(sample.randomRelicCount, report.randomRelics.size, "$id 随机池出处件数")
            assertEquals(sample.hiddenCount, report.hiddenRelicCount, "$id 被剔除的不可正常获得条目数")
            val groupSize = if (report.affix.compatibilityId == -1) 0 else report.conflicts.size + 1
            assertEquals(sample.conflictGroupSize, groupSize, "$id 互斥组条数")
            (report.fixedRelics + report.randomRelics).forEach { hit ->
                assertTrue(index.relic(hit.relicId)!!.isObtainable, "$id 列出了不会正常获得的遗物 ${hit.relicId}")
            }
        }
    }

    @Test
    fun `parity - three relics give the same slot pool conclusions as macOS and Windows`() {
        val samples = listOf(
            RelicSample(
                202, "辽阔的火燃情景", "商店遗物", "红", false, false, 3, 0,
                listOf(310, 210, 110), listOf("1.03 · 3 孔层", "1.03 · 2 孔层", "1.03 · 1 孔层"),
                listOf(340, 340, 340), null, null,
            ),
            RelicSample(
                1000, "细腻的火燃情景", "唯一遗物", "红", false, true, 1, 0,
                listOf(707_121_100, -1, -1), listOf("池 707121100", "", ""),
                listOf(1, 0, 0), null, listOf(7_121_100),
            ),
            RelicSample(
                2_000_002, "辽阔的火燃暗淡情景", "深夜遗物", "红", true, false, 3, 1,
                listOf(2_000_000, 2_100_000, 2_100_000), listOf("深夜 A 池", "深夜 B 池", "深夜 B 池"),
                listOf(49, 277, 277), listOf(listOf(2_000_000, 1), listOf(2_100_000, 2)), null,
            ),
        )
        samples.forEach { sample ->
            val entry = assertNotNull(index.relic(sample.relicId))
            val id = sample.relicId
            assertEquals(sample.name, entry.displayName, "遗物 $id 名称")
            assertEquals(sample.kindLabel, entry.kindLabel)
            assertEquals(sample.colorLabel, entry.colorLabel)
            assertEquals(sample.deep, entry.deep)
            assertEquals(sample.isUnique, entry.isUnique)
            assertTrue(entry.isObtainable, "遗物 $id 应判为正常可获得")
            assertEquals(sample.slotCount, entry.slotCount)
            assertEquals(sample.curseSlotCount, entry.curseSlotCount)
            assertEquals(sample.slotPools, entry.slots.map { it.poolId })
            assertEquals(sample.slotLabels, entry.slots.map { if (it.isEmpty) "" else affixPoolLabel(it.poolId) })
            assertEquals(sample.slotSizes, entry.slots.map { it.poolSize })
            assertEquals(sample.fixedEffectIds, entry.fixedEffectIds?.filter { it != -1 })
            if (sample.deepGroups != null) {
                assertEquals(sample.deepGroups, entry.deepPoolGroups!!.map { listOf(it.poolId, it.count) })
                assertEquals(sample.curseSlotCount, entry.slots.count { it.poolId == 2_000_000 })
            } else {
                assertNull(entry.deepPoolGroups)
            }
        }
        assertEquals(768, index.searchRelics("").size, "两端的「可查遗物」件数都应是 768 件")
    }

    @Test
    fun `copy table matches the desktop strings`() {
        assertEquals("共 432 件遗物：固定 0 件 · 随机池 432 件", LookupCopy.whereSubtitle(432, 0, 432))
        assertEquals(LookupCopy.WHERE_NONE, LookupCopy.whereSubtitle(0, 0, 0))
        assertEquals("-1（不互斥）", LookupCopy.compatibilityValue(-1))
        assertEquals("无", LookupCopy.livePoolValue(0))
        assertEquals("展开全部 101 条", LookupCopy.conflictExpandButton(false, 101, 24))
        assertEquals("收起（只看前 24 条）", LookupCopy.conflictExpandButton(true, 101, 24))
        assertEquals("还有 77 条未列出", LookupCopy.conflictExpandHint(false, 101, 24))
        assertEquals("已列出全部 101 条互斥词条", LookupCopy.conflictExpandHint(true, 101, 24))
        assertEquals("展开全部 432 件", LookupCopy.hitExpandButton(false, 432, 120))
        assertEquals("收起（只看前 120 件）", LookupCopy.hitExpandButton(true, 432, 120))
        assertEquals(
            "另有 2 条不会正常获得的物品表条目未列出：超出合法 ID 区间 / 没有名称的参数行（调试、未启用条目），以及 20000–30035 作弊器区段的遗物。",
            LookupCopy.hiddenRelicsNote(2),
        )
        assertEquals("同组词条不能出现在同一件遗物上，共 5 条（其中 2 条只见于遗物物品表）", LookupCopy.conflictCardSubtitle(5, 2))
        assertEquals("遗物物品表载入失败：坏了。", LookupCopy.relicDataDetail("坏了。"))
        assertEquals("没有内置 relics.json。", LookupCopy.relicDataDetail(null))
        // 物品表缺失时两种标题与 macOS 逐字一致：页头小标签 / 按遗物查说明卡用「未内置」，词条详情说明卡用「不可用」
        assertEquals("遗物物品表未内置", LookupCopy.RELIC_DATA_NOT_BUNDLED)
        assertEquals("遗物物品表不可用", LookupCopy.RELIC_DATA_UNAVAILABLE)
        assertEquals("池内另有 330 条词条，可在「按词条查」里逐条反查。", LookupCopy.previewMore(330))
        assertEquals("配诅咒 · 24 条", LookupCopy.curseSlotPill(24))
        assertEquals(listOf("全部", "词条库", "物品表补充"), AffixLookupScope.entries.map { it.title })
    }
}
