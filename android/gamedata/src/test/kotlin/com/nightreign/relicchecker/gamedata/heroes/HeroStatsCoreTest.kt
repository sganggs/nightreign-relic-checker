package com.nightreign.relicchecker.gamedata.heroes

import com.nightreign.relicchecker.gamedata.GameDataKey
import kotlin.math.abs
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * 与 macOS RelicCoreChecks/HeroStatsChecks.swift 的 ①–⑧ 段逐条对应：数据集骨架、派生值重算、
 * 词条锚点叠加、逐级 delta 结构、钳位扫描、利普拉、同级对比、页面文案。另加车道要求的「固定事实」。
 */
class HeroStatsCoreTest {
    private val index get() = HeroesTestData.index
    private val names get() = index.statNames

    // ------------------------------------------------------------------ 固定事实（车道要求）

    @Test
    fun `固定事实：10 角色 × 15 级、20 条转职遗物、5 套利普拉`() {
        assertEquals(1, index.dataset.schemaVersion)
        assertEquals(GameDataKey.HEROES.expectedVersion, index.dataset.schemaVersion)
        assertEquals(10, index.heroes.size)
        index.heroes.forEach { hero ->
            assertEquals(15, hero.levels.size, "${hero.display} 应有 15 级")
            assertEquals(HeroesTestData.levels, hero.levels.map { it.level })
        }
        assertEquals(20, index.dataset.statModifiers.size)
        assertEquals(5, index.libraRespecs.size)
        assertEquals(15, index.maxLevel)
        assertEquals("10 位夜行者 · 1–15 级", index.summary)
    }

    @Test
    fun `固定事实：女爵 10 级 + 提升生命力、力气但降低集中力`() {
        val modifier = index.modifier(6_643_000)
        assertEquals("【女爵】提升生命力、力气，但降低集中力", modifier.nameZh)
        assertEquals("duchess", modifier.heroKey)

        val snapshot = index.snap("duchess", 10, listOf(modifier.affixId))
        assertEquals(30, snapshot.baseStats["vigor"])
        assertEquals(32, snapshot.finalStats["vigor"], "生命力 30→32")
        assertEquals(21, snapshot.baseStats["mind"])
        assertEquals(10, snapshot.finalStats["mind"], "集中力 21→10")
        assertEquals(8, snapshot.baseStats["strength"])
        assertEquals(28, snapshot.finalStats["strength"], "力气 8→28")
        assertClose(680.0, snapshot.baseDerived["hp"], "血量基础 680")
        assertClose(720.0, snapshot.finalDerived["hp"], "血量 680→720")
        assertTrue(snapshot.clampedStats.isEmpty(), "不选利普拉时不钳位")
        assertEquals(HeroModifierSource.INFERRED, snapshot.modifierSource?.source)
        assertEquals("词条推算", snapshot.modifierSource?.label)
        // 派生值按叠加后的属性重算
        assertEquals(index.derivedValues(snapshot.finalStats), snapshot.finalDerived)

        // 再选利普拉「力气」：替换表 10 级集中力只有 4，4 − 11 = −7 → 钳到 1 并标「已钳位」
        val swapped = index.snap("duchess", 10, listOf(modifier.affixId), "strength")
        assertEquals(4, swapped.baseStats["mind"])
        assertEquals(-11, swapped.requestedDelta["mind"])
        assertEquals(1, swapped.finalStats["mind"], "集中力钳到 1")
        assertEquals(listOf("mind"), swapped.clampedStats)
        assertEquals(mapOf("mind" to -7), swapped.clampedFrom)
        assertEquals(-3, swapped.effectiveDelta("mind"), "卡片上的生效增减量 = 1 − 4")
        assertEquals("词条请求 -11，已钳到最低 1", HeroStatsCopy.clampRequestedNote(swapped.requestedDelta.getValue("mind")))
        assertEquals("原为 -7，已钳到最低 1", HeroStatsCopy.clampedFromNote(swapped.clampedFrom.getValue("mind")))
        assertEquals("已钳位", HeroStatsCopy.CLAMP_ROW_TAG)
        assertEquals(
            "集中力 叠加后不足 1，已钳到最低 1（游戏里属性不会低于 1）",
            HeroStatsCopy.clampSummary(swapped.clampedStats.map(names::attributeTitle)),
        )
        assertEquals(index.derivedValues(swapped.finalStats), swapped.finalDerived, "派生值按钳位后的属性重算")
        assertClose(50.0, swapped.finalDerived["fp"], "集中力 1 → 专注值 50")
        // 全部等级表的「已钳位」行标：10 级这一行一定在里面
        val clampedRows = index.clampedByLevel(index.snapshots("duchess", setOf(modifier.affixId), "strength"))
        assertTrue(clampedRows.any { it.level == 10 && it.names == listOf("集中力") })
    }

    @Test
    fun `固定事实：13–15 级沿用 12 级锚点、2–11 级 inferred`() {
        index.dataset.statModifiers.forEach { modifier ->
            val at12 = assertNotNull(modifier.level(12)).delta
            modifier.levels.forEach { row ->
                when (row.level) {
                    1, 12 -> assertTrue(row.isAnchor && !row.inferred, "${modifier.display} ${row.level} 级应是锚点")
                    in 2..11 -> assertTrue(!row.isAnchor && row.inferred, "${modifier.display} ${row.level} 级应是推算")
                    else -> {
                        assertTrue(!row.isAnchor && row.inferred, "${modifier.display} ${row.level} 级数据集标 inferred")
                        assertEquals(at12, row.delta, "${modifier.display} ${row.level} 级应沿用 12 级 delta")
                    }
                }
            }
        }
        (2..11).forEach { assertEquals("词条推算", index.modifierLevelNote(it)?.label) }
        (13..15).forEach { assertEquals("词条沿用 12 级锚点", index.modifierLevelNote(it)?.label) }
        listOf(1, 12).forEach { assertEquals("词条锚点", index.modifierLevelNote(it)?.label) }
    }

    // ------------------------------------------------------------------ ① 数据集骨架

    @Test
    fun `数据集骨架：元数据、statNames、锚点、growthGraphs 与插值口径`() {
        val dataset = index.dataset
        assertEquals("heroes", dataset.datasetId)
        assertTrue(dataset.gameVersion.isNotEmpty() && dataset.dataVersion.isNotEmpty() && dataset.generatedAt.isNotEmpty())
        assertEquals("v1.03.5 + DLC1", dataset.gameVersion)
        assertEquals("regulation 10350000", dataset.dataVersion)
        assertTrue(dataset.caveats.isNotEmpty())
        assertEquals(13, dataset.caveats.size)
        assertEquals(10, dataset.sources.size)
        assertTrue(index.hasHeroData)

        assertEquals(listOf("vigor", "mind", "endurance", "strength", "dexterity", "intelligence", "faith", "arcane"), names.attributeKeys)
        assertEquals(listOf("hp", "fp", "stamina", "equipLoad"), names.derivedKeys)
        names.attributeKeys.forEach { assertTrue(names.attributeTitle(it).isNotEmpty() && names.attributeTitle(it) != it) }
        names.derivedKeys.forEach { assertTrue(names.derivedTitle(it).isNotEmpty() && names.derivedTitle(it) != it) }
        assertEquals("生命力", names.attributeTitle("vigor"))
        assertEquals("集中力", names.attributeTitle("mind"))
        assertEquals("感应", names.attributeTitle("arcane"))
        assertEquals("专注值", names.derivedTitle("fp"))
        assertEquals("血量", names.derivedTitle("hp"))
        assertEquals("负重上限", names.derivedTitle("equipLoad"))

        index.heroes.forEach { hero ->
            assertEquals(listOf(1, 2, 12, 15), hero.anchorLevels, hero.display)
            assertTrue(hero.nameZh.isNotEmpty() && hero.nameEn.isNotEmpty())
            assertEquals(4, hero.anchors.size, "${hero.display} 应有 4 行参数锚点")
            hero.levels.forEach { row -> assertEquals(names.attributeKeys.toSet(), row.stats.keys, "${hero.display} ${row.level} 级 8 项属性") }
            assertEquals(2, index.modifiers(hero.key).size, "${hero.display} 应有 2 条转职遗物词条")
        }

        names.orderedDerived.forEach { entry ->
            val graph = assertNotNull(dataset.growthGraphs[entry.graphId], "缺少 CalcCorrectGraph ${entry.graphId}")
            assertTrue(graph.isUsable)
            assertTrue(entry.key in graph.usedFor)
            assertTrue(entry.fromStat in names.attributeKeys)
        }
        assertEquals(true, dataset.growthGraphs[100]?.linear)
        assertEquals(true, dataset.growthGraphs[101]?.linear)
        assertEquals(true, dataset.growthGraphs[104]?.linear)
        assertEquals(false, dataset.growthGraphs[220]?.linear)

        val interpolation = dataset.interpolation
        assertEquals(listOf(1, 2, 12, 15), interpolation.baseAnchorLevels)
        assertEquals(listOf(1, 12), interpolation.modifierAnchorLevels)
        assertTrue(interpolation.baseVerified)
        assertTrue(interpolation.modifierAnchorVerified)
        assertFalse(interpolation.modifierMidLevelsVerified)
        assertTrue(interpolation.notes.size >= 6)
        assertTrue(interpolation.libraRule.isNotEmpty())
        assertEquals("floor", interpolation.baseRounding)
        assertEquals("trunc", interpolation.modifierRounding)
        val rounding = assertNotNull(interpolation.notes.firstOrNull { it.title == "取整方向" })
        assertTrue(rounding.text.contains("floor") && rounding.text.contains("trunc"))
        assertTrue(rounding.text.contains("deltaFloorAlt"))
        assertTrue(HeroInterpolation(baseRule = "x").notes.none { it.title == "取整方向" }, "取整字段缺失时不硬造说明")
    }

    // ------------------------------------------------------------------ ② 派生值重算

    @Test
    fun `派生值重算：10 角色 × 15 级 × 4 与 5 套利普拉 × 15 级 × 4 逐格等于数据集`() {
        var cells = 0
        index.heroes.forEach { hero ->
            hero.levels.forEach { row ->
                val recomputed = index.derivedValues(row.stats)
                names.derivedKeys.forEach { key ->
                    assertClose(assertNotNull(row.derived[key]), recomputed[key], "${hero.display} ${row.level} 级 $key")
                    cells += 1
                }
            }
        }
        assertEquals(600, cells)
        var libraCells = 0
        index.libraRespecs.forEach { respec ->
            respec.levels.forEach { row ->
                val recomputed = index.derivedValues(row.stats)
                names.derivedKeys.forEach { key ->
                    assertClose(assertNotNull(row.derived[key]), recomputed[key], "利普拉 ${respec.shortTitle} ${row.level} 级 $key")
                    libraCells += 1
                }
            }
        }
        assertEquals(300, libraCells)
    }

    @Test
    fun `派生值手算常数与 floorDivide`() {
        val graphs = index.dataset.growthGraphs
        val hp = assertNotNull(graphs[100])
        val fp = assertNotNull(graphs[101])
        val stamina = assertNotNull(graphs[104])
        val load = assertNotNull(graphs[220])
        listOf(1, 8, 25, 40, 52, 60).forEach { assertEquals(20 * it + 80, hp.integerValue(it), "血量 @ 生命力 $it") }
        listOf(1, 4, 19, 31, 45).forEach { assertEquals(5 * it + 45, fp.integerValue(it), "专注值 @ 集中力 $it") }
        listOf(1, 3, 21, 24, 27, 40).forEach { assertEquals(2 * it + 48, stamina.integerValue(it), "精力 @ 耐力 $it") }

        val wylder12 = assertNotNull(index.hero("wylder")?.level(12))
        assertClose(96.0, index.derivedValues(wylder12.stats)["stamina"], "追踪者 12 级精力 96（wiki 写 92）")
        assertClose(1000.0, index.derivedValues(wylder12.stats)["hp"], "追踪者 12 级血量 1000")
        assertClose(45.0, HeroStatsMath.round(load.value(3), 1), "耐力 3 负重上限 45")
        assertClose(45.0, HeroStatsMath.round(load.value(8), 1), "耐力 8 负重上限 45")
        val wylder15 = assertNotNull(index.hero("wylder")?.level(15))
        assertClose(74.1, index.derivedValues(wylder15.stats)["equipLoad"], "追踪者 15 级负重上限 74.1")

        assertEquals(3, HeroStatsMath.floorDivide(7, 2))
        assertEquals(-4, HeroStatsMath.floorDivide(-7, 2))
        assertEquals(-3, HeroStatsMath.floorDivide(-6, 2))
        assertEquals(0, HeroStatsMath.floorDivide(5, 0))
    }

    // ------------------------------------------------------------------ ③ 词条锚点叠加

    @Test
    fun `词条锚点：1 与 12 级叠加结果 = 基础 + 参数 delta，派生值按改后属性重算`() {
        index.dataset.statModifiers.forEach { modifier ->
            val hero = assertNotNull(index.hero(modifier.heroKey), "${modifier.display} 指向不存在的角色")
            assertTrue(modifier.affectedStats.isNotEmpty())
            assertTrue(modifier.affectedStats.all { it in names.attributeKeys })
            assertTrue(modifier.relicItems.isNotEmpty())
            modifier.relicItems.forEach { item ->
                assertTrue(item.display.isNotEmpty())
                assertEquals(HeroRelicItem.relicColorLabel(item.color) + "色", item.colorText, "遗物颜色文案应是「红色」而不是「红」")
            }
            assertEquals(2, modifier.anchors.size)
            assertTrue(modifier.nameZh.startsWith("【") && modifier.shortName != modifier.display)
            assertFalse(modifier.shortName.contains("】"))

            modifier.anchors.forEach { anchor ->
                val baseRow = assertNotNull(hero.level(anchor.level))
                val snapshot = index.snap(hero.key, anchor.level, listOf(modifier.affixId))
                names.attributeKeys.forEach { key ->
                    val expected = maxOf(HeroStatsMath.MINIMUM_STAT, baseRow.stats.getValue(key) + (anchor.delta[key] ?: 0))
                    assertEquals(expected, snapshot.finalStats[key], "${modifier.display} ${anchor.level} 级 $key")
                }
                val row = assertNotNull(modifier.level(anchor.level))
                assertEquals(anchor.delta, row.delta, "逐级 delta 应等于参数锚点行")
                assertTrue(row.isAnchor && !row.inferred)
                assertEquals(index.derivedValues(snapshot.finalStats), snapshot.finalDerived)
            }
        }
    }

    @Test
    fun `手算：复仇者 15 级提升生命力耐力降低集中力 → 880 ／ 145 ／ 100`() {
        val revenant = assertNotNull(index.modifiers("revenant").firstOrNull { (it.anchors.last().delta["mind"] ?: 0) < 0 })
        val snapshot = index.snap("revenant", 15, listOf(revenant.affixId))
        assertEquals(40, snapshot.finalStats["vigor"])
        assertEquals(20, snapshot.finalStats["mind"])
        assertEquals(26, snapshot.finalStats["endurance"])
        assertClose(880.0, snapshot.finalDerived["hp"], "血量")
        assertClose(145.0, snapshot.finalDerived["fp"], "专注值")
        assertClose(100.0, snapshot.finalDerived["stamina"], "精力")
        assertTrue(snapshot.carriesAnchorDelta)
        assertFalse(snapshot.hasInferredDelta)
    }

    @Test
    fun `追踪者 12 级双词条：增减量相加`() {
        val both = index.modifiers("wylder")
        assertEquals(2, both.size)
        val combined = index.snap("wylder", 12, both.map { it.affixId })
        val wylder12 = assertNotNull(index.hero("wylder")?.level(12))
        names.attributeKeys.forEach { key ->
            val sum = both.sumOf { it.level(12)?.delta?.get(key) ?: 0 }
            assertEquals(maxOf(1, wylder12.stats.getValue(key) + sum), combined.finalStats[key])
            assertEquals(sum, combined.requestedDelta[key] ?: 0)
        }
        assertEquals(2, combined.activeModifiers.size)
        assertTrue(combined.isAnchorLevel)
    }

    // ------------------------------------------------------------------ ④ 逐级 delta 的结构

    @Test
    fun `逐级 delta：15 级连续、锚点标记、沿用、单调、deltaFloorAlt 只在推算等级且恰好小 1`() {
        val anchors = index.dataset.interpolation.modifierAnchorLevels
        val lastAnchor = anchors.max()
        index.dataset.statModifiers.forEach { modifier ->
            assertEquals(HeroesTestData.levels, modifier.levels.map { it.level })
            val anchorDelta = assertNotNull(modifier.level(lastAnchor)).delta
            modifier.levels.forEach { row ->
                val shouldBeAnchor = row.level in anchors
                assertEquals(shouldBeAnchor, row.isAnchor)
                assertEquals(!shouldBeAnchor, row.inferred)
                assertTrue(modifier.affectedStats.containsAll(row.delta.keys))
                if (row.level > lastAnchor) assertEquals(anchorDelta, row.delta)
                if (row.level in 2..lastAnchor) {
                    row.delta.forEach { (key, value) ->
                        val previous = modifier.level(row.level - 1)?.delta?.get(key) ?: 0
                        assertTrue(
                            abs(value) >= abs(previous) && (value == 0 || previous == 0 || (value > 0) == (previous > 0)),
                            "${modifier.display} $key 在 ${row.level} 级应同号且绝对值不减",
                        )
                    }
                }
                if (row.deltaFloorAlt.isNotEmpty()) {
                    assertTrue(row.inferred)
                    row.deltaFloorAlt.forEach { (key, alt) ->
                        assertNotEquals(row.delta[key] ?: 0, alt)
                        assertEquals((row.delta[key] ?: 0) - 1, alt)
                    }
                }
            }
            listOf(1, 6, 12, 15).forEach { level ->
                val snapshot = index.snap(modifier.heroKey, level, listOf(modifier.affixId))
                val expectInferred = level != 1 && level != lastAnchor && level < lastAnchor
                assertEquals(expectInferred, snapshot.hasInferredDelta, "${modifier.display} $level 级推算标记")
                assertEquals(level > lastAnchor, snapshot.carriesAnchorDelta, "${modifier.display} $level 级沿用标记")
            }
        }
        index.heroes.forEach { hero ->
            listOf(1, 7, 15).forEach { level ->
                val snapshot = index.snap(hero.key, level)
                assertEquals(snapshot.baseStats, snapshot.finalStats)
                assertTrue(snapshot.requestedDelta.isEmpty())
                assertTrue(!snapshot.hasModifier && !snapshot.carriesAnchorDelta && !snapshot.hasInferredDelta)
                assertNull(snapshot.modifierSource)
                assertTrue(snapshot.clampedStats.isEmpty())
            }
        }
    }

    // ------------------------------------------------------------------ ⑤ 钳位

    private data class ClampScan(var combinations: Int = 0, var clampedCombinations: Int = 0, var clampedCells: Int = 0)

    private fun scan(libraKey: String?, groups: (HeroEntry) -> List<Set<Int>>): ClampScan {
        val result = ClampScan()
        index.heroes.forEach { hero ->
            groups(hero).forEach { ids ->
                index.levelRange.forEach { level ->
                    val snapshot = index.snap(hero.key, level, ids, libraKey)
                    result.combinations += 1
                    val place = "${hero.display} $level 级 · 利普拉 $libraKey · $ids"
                    val expectedStats = LinkedHashMap(snapshot.baseStats)
                    val expectedClampedFrom = LinkedHashMap<String, Int>()
                    snapshot.requestedDelta.forEach { (key, change) ->
                        val raw = (snapshot.baseStats[key] ?: 0) + change
                        expectedStats[key] = maxOf(1, raw)
                        if (raw < 1) expectedClampedFrom[key] = raw
                    }
                    assertEquals(expectedStats, snapshot.finalStats, "$place 最终属性 = max(1, 基础 + 增减量)")
                    assertEquals(names.attributeKeys.filter { it in expectedClampedFrom }, snapshot.clampedStats, "$place 钳位列表按属性展示顺序")
                    assertEquals(expectedClampedFrom, snapshot.clampedFrom, "$place 钳位前原值")
                    assertTrue(snapshot.finalStats.values.all { it >= 1 }, "$place 最终属性不低于 1")
                    assertTrue(snapshot.finalDerived.values.all { it >= 0 }, "$place 派生值不为负")
                    assertEquals(index.derivedValues(snapshot.finalStats), snapshot.finalDerived, "$place 派生值按钳位后的属性重算")
                    if (snapshot.clampedStats.isNotEmpty()) {
                        result.clampedCombinations += 1
                        result.clampedCells += snapshot.clampedStats.size
                    }
                }
            }
        }
        return result
    }

    @Test
    fun `钳位：纯函数层`() {
        val applied = HeroStatsMath.apply(listOf(mapOf("vigor" to -3, "mind" to -5, "endurance" to -2)), mapOf("vigor" to 3, "mind" to 1, "endurance" to 10))
        assertEquals(1, applied.stats["vigor"])
        assertEquals(1, applied.stats["mind"])
        assertEquals(8, applied.stats["endurance"])
        assertEquals(listOf("mind", "vigor"), applied.clamped, "未给展示顺序时退回 key 字典序")
        assertEquals(-3, applied.requested["vigor"])

        val stacked = HeroStatsMath.apply(listOf(mapOf("vigor" to -2), mapOf("vigor" to -2)), mapOf("vigor" to 3))
        assertEquals(-4, stacked.requested["vigor"])
        assertEquals(1, stacked.stats["vigor"])
        assertEquals(listOf("vigor"), stacked.clamped)

        val exact = HeroStatsMath.apply(listOf(mapOf("vigor" to -2)), mapOf("vigor" to 3))
        assertTrue(exact.stats["vigor"] == 1 && exact.clamped.isEmpty(), "结果正好为 1 时不算钳位")
    }

    @Test
    fun `钳位：真实数据扫描（不选利普拉从不触发，选了利普拉是常态）`() {
        val both: (HeroEntry) -> List<Set<Int>> = { hero -> listOf(index.modifiers(hero.key).map { it.affixId }.toSet()) }
        val single: (HeroEntry) -> List<Set<Int>> = { hero -> index.modifiers(hero.key).map { setOf(it.affixId) } }
        val plainBoth = scan(null, both)
        val plainSingle = scan(null, single)
        val libraBoth = ClampScan()
        val libraSingle = ClampScan()
        index.libraRespecs.forEach { respec ->
            scan(respec.key, both).let {
                libraBoth.combinations += it.combinations
                libraBoth.clampedCombinations += it.clampedCombinations
                libraBoth.clampedCells += it.clampedCells
            }
            scan(respec.key, single).let {
                libraSingle.combinations += it.combinations
                libraSingle.clampedCombinations += it.clampedCombinations
                libraSingle.clampedCells += it.clampedCells
            }
        }
        assertEquals(150, plainBoth.combinations)
        assertEquals(300, plainSingle.combinations)
        assertEquals(750, libraBoth.combinations)
        assertEquals(1500, libraSingle.combinations)
        assertEquals(0, plainBoth.clampedCombinations)
        assertEquals(0, plainSingle.clampedCombinations)
        assertEquals(313, libraBoth.clampedCombinations)
        assertEquals(389, libraBoth.clampedCells)
        assertEquals(458, libraSingle.clampedCombinations)
        assertEquals(512, libraSingle.clampedCells)
    }

    @Test
    fun `钳位：铁之眼 15 级 + 利普拉（力气）+ 降灵巧，生效 -8、请求 -9`() {
        val ironeye = index.modifier(6_642_000)
        val libraRow = assertNotNull(index.libra("strength")?.level(15))
        assertEquals(9, libraRow.stats["dexterity"])
        assertEquals(-9, ironeye.level(15)?.delta?.get("dexterity"))
        val snapshot = index.snap("ironeye", 15, listOf(ironeye.affixId), "strength")
        assertEquals(-9, snapshot.requestedDelta["dexterity"])
        assertEquals(1, snapshot.finalStats["dexterity"])
        assertEquals(listOf("dexterity"), snapshot.clampedStats)
        assertEquals(-8, snapshot.effectiveDelta("dexterity"))
    }

    // ------------------------------------------------------------------ ⑥ 利普拉

    @Test
    fun `利普拉：5 笔交易、整套替换、与转职遗物同时生效`() {
        assertEquals(setOf("strength", "dexterity", "intelligence", "faith", "arcane"), index.libraRespecs.map { it.key }.toSet())
        index.libraRespecs.forEach { respec ->
            assertTrue(respec.dealLineZh.isNotEmpty())
            assertTrue(respec.nameZh.isNotEmpty())
            assertEquals(names.attributeTitle(respec.statKey), respec.shortTitle)
            assertEquals(HeroesTestData.levels, respec.levels.map { it.level })
            assertEquals(respec.dealLineZh, respec.display)
            listOf("wylder", "recluse").forEach { hero ->
                listOf(1, 8, 15).forEach { level ->
                    val snapshot = index.snap(hero, level, libraKey = respec.key)
                    assertEquals(assertNotNull(respec.level(level)).stats, snapshot.baseStats)
                    assertEquals(respec.key, snapshot.libraKey)
                    assertTrue(snapshot.isModified)
                }
            }
        }
        assertEquals("“我想要力气变得更大”", index.libra("strength")?.dealLineZh)
        assertEquals("扭曲的重生（力气）", index.libra("strength")?.nameZh)

        val respec = assertNotNull(index.libra("strength"))
        val modifier = index.modifiers("guardian").first()
        val snapshot = index.snap("guardian", 12, listOf(modifier.affixId), "strength")
        val libraRow = assertNotNull(respec.level(12))
        val delta = assertNotNull(modifier.level(12)).delta
        names.attributeKeys.forEach { key ->
            assertEquals(maxOf(1, libraRow.stats.getValue(key) + (delta[key] ?: 0)), snapshot.finalStats[key])
        }
        assertEquals(index.derivedValues(snapshot.finalStats), snapshot.finalDerived)

        val plain = index.snap("guardian", 12)
        assertEquals(assertNotNull(index.hero("guardian")?.level(12)).stats, plain.baseStats)
        assertNull(plain.libraKey)
        assertNull(index.libra(null))
        assertNull(index.libra("不存在"))
    }

    // ------------------------------------------------------------------ ⑦ 同级对比

    @Test
    fun `同级对比：10 行、等于数据集、各列单调、角色列可严格反序、平手按数据集顺序`() {
        listOf(1, 12, 15).forEach { level ->
            val rows = index.comparisonRows(level)
            assertEquals(10, rows.size)
            assertTrue(rows.all { it.level == level })
            assertEquals(10, rows.map { it.heroKey }.toSet().size)
            rows.forEach { row ->
                val expected = assertNotNull(index.hero(row.heroKey)?.level(level))
                assertEquals(expected.stats, row.stats)
                names.derivedKeys.forEach { assertClose(expected.derived.getValue(it), row.derived[it], "${row.nameZh} $level 级 $it") }
            }
            names.attributeKeys.forEach { key ->
                val column = HeroComparisonColumn.Stat(key)
                val ascending = HeroComparison.sorted(rows, column, true)
                val descending = HeroComparison.sorted(rows, column, false)
                assertEquals(rows.size, ascending.size)
                assertEquals(rows.map { it.heroKey }.toSet(), ascending.map { it.heroKey }.toSet())
                val ascValues = ascending.mapNotNull { it.value(column) }
                val descValues = descending.mapNotNull { it.value(column) }
                assertEquals(ascValues.sorted(), ascValues)
                assertEquals(descValues.sortedDescending(), descValues)
            }
            names.derivedKeys.forEach { key ->
                val column = HeroComparisonColumn.Derived(key)
                val values = HeroComparison.sorted(rows, column, false).mapNotNull { it.value(column) }
                assertEquals(values.sortedDescending(), values)
            }
            assertEquals(index.heroes.map { it.id }, HeroComparison.sorted(rows, HeroComparisonColumn.Hero, true).map { it.heroId })
            assertEquals(index.heroes.map { it.id }.reversed(), HeroComparison.sorted(rows, HeroComparisonColumn.Hero, false).map { it.heroId })
        }

        val rows = index.comparisonRows(15)
        val arcane = HeroComparison.sorted(rows, HeroComparisonColumn.Stat("arcane"), true)
        arcane.zipWithNext().filter { (a, b) -> a.stats["arcane"] == b.stats["arcane"] }.forEach { (a, b) ->
            assertTrue(a.heroId < b.heroId, "平手时应按数据集顺序排（${a.nameZh} / ${b.nameZh}）")
        }
        val mind = HeroComparisonColumn.Stat("mind")
        val mindAsc = HeroComparison.sorted(rows, mind, true)
        val mindDesc = HeroComparison.sorted(rows, mind, false)
        assertNotEquals(mindAsc.map { it.heroKey }, mindDesc.reversed().map { it.heroKey }, "有平手时降序不是升序的严格反转")
        listOf(mindAsc, mindDesc).forEach { direction ->
            val tied = direction.filter { it.stats["mind"] == 14 }
            assertEquals(listOf("守护者", "铁之眼", "送葬者"), tied.map { it.nameZh }, "15 级集中力 14 的三人在两个方向上都保持数据集顺序")
        }
        assertEquals(index.heroes.map { it.id }, HeroComparison.sorted(rows, HeroComparisonColumn.Stat("nope"), false).map { it.heroId })

        assertTrue(index.comparisonRows(99).isEmpty())
        assertNull(index.snapshot("wylder", 99))
        assertNull(index.snapshot("不存在", 1))
        assertEquals(15, index.snapshots("wylder").size)
    }

    @Test
    fun `同级对比：列最大值与列标识的往返`() {
        val rows = index.comparisonRows(15)
        val maxima = HeroComparison.columnMaxima(rows, names)
        assertEquals(rows.maxOf { it.stats.getValue("vigor") }.toDouble(), maxima[HeroComparisonColumn.Stat("vigor")])
        assertEquals(rows.maxOf { it.derived.getValue("hp") }, maxima[HeroComparisonColumn.Derived("hp")])
        listOf(HeroComparisonColumn.Hero, HeroComparisonColumn.Stat("mind"), HeroComparisonColumn.Derived("equipLoad")).forEach {
            assertEquals(it, HeroComparisonColumn.fromToken(it.token))
        }
    }

    // ------------------------------------------------------------------ ⑧ 页面文案

    @Test
    fun `格式化：正负号、小数、来源标记、破折号`() {
        assertEquals("+5", HeroStatsText.signed(5))
        assertEquals("-3", HeroStatsText.signed(-3))
        assertEquals("0", HeroStatsText.signed(0))
        assertEquals("+2.5", HeroStatsText.signed(2.5))
        assertEquals("-0.5", HeroStatsText.signed(-0.5))
        assertEquals("74.1", HeroStatsText.decimal(74.1))
        assertEquals("45", HeroStatsText.decimal(45.0))
        assertEquals("1120", HeroStatsText.decimal(1120.0))

        val anchors = index.dataset.interpolation.modifierAnchorLevels
        assertEquals(HeroModifierSource.ANCHOR, HeroStatsText.modifierSource(1, anchors)?.source)
        assertEquals("词条锚点", HeroStatsText.modifierSource(1, anchors)?.label)
        assertEquals("词条锚点", HeroStatsText.modifierSource(12, anchors)?.label)
        assertEquals(HeroModifierSource.INFERRED, HeroStatsText.modifierSource(6, anchors)?.source)
        assertEquals("词条推算", HeroStatsText.modifierSource(6, anchors)?.label)
        assertEquals(HeroModifierSource.CARRIED, HeroStatsText.modifierSource(15, anchors)?.source)
        assertEquals("词条沿用 12 级锚点", HeroStatsText.modifierSource(15, anchors)?.label)
        assertNull(HeroStatsText.modifierSource(3, emptyList()))
        assertEquals("词条沿用 8 级锚点", HeroStatsText.modifierSource(9, listOf(1, 8))?.label)

        assertEquals(HeroStatsCopy.MISSING, HeroStatsText.statText(null))
        assertEquals("0", HeroStatsText.statText(0))
        assertEquals(HeroStatsCopy.MISSING, HeroStatsText.derivedText(null, true))
        assertEquals("0", HeroStatsText.derivedText(0.0, true))
        assertEquals("74.1", HeroStatsText.derivedText(74.1, false))
        assertEquals("45.0", HeroStatsText.derivedText(45.0, false))
        assertEquals("72.0", HeroStatsText.derivedText(72.0, false))
        assertEquals("1120", HeroStatsText.derivedText(1120.0, true))

        assertTrue(index.summary.contains("10 位夜行者"))
        assertTrue(index.summary.contains("1–15 级"))
    }

    @Test
    fun `四舍五入远离零与定点格式化`() {
        assertEquals(3.0, HeroStatsMath.roundHalfAwayFromZero(2.5))
        assertEquals(-3.0, HeroStatsMath.roundHalfAwayFromZero(-2.5))
        assertEquals(2.0, HeroStatsMath.roundHalfAwayFromZero(2.4999999))
        assertEquals(0.0, HeroStatsMath.roundHalfAwayFromZero(0.49999999999999994), "不能像 floor(x + 0.5) 那样进位")
        assertEquals(74.1, HeroStatsMath.round(74.149999, 1))
        assertEquals(74.2, HeroStatsMath.round(74.15, 1))
        assertEquals(-74.2, HeroStatsMath.round(-74.15, 1))
        assertEquals("60", HeroStatsMath.fixed(59.9999999999, 0))
        assertEquals("0.1", HeroStatsMath.fixed(0.15, 1), "按精确二进制值舍入（0.15 实为 0.1499…），与 printf 同口径")
    }

    @Test
    fun `数据集原文的粗体标记拆成片段而不是原样显示星号`() {
        assertEquals(
            listOf("因此" to false, "绝对伤害无法还原" to true, "；支持 (a) 相对比较" to false),
            HeroStatsText.boldSegments("因此**绝对伤害无法还原**；支持 (a) 相对比较"),
        )
        assertEquals(listOf("落单的 ** 不配对" to false), HeroStatsText.boldSegments("落单的 ** 不配对"))
        assertEquals(listOf("开头" to true, "中间" to false, "**结尾" to false), HeroStatsText.boldSegments("**开头**中间**结尾"))
        assertEquals(listOf("没有标记" to false), HeroStatsText.boldSegments("没有标记"))
        // 真实 caveats 里有粗体标记：拆完之后正文不再含成对的星号
        index.dataset.caveats.forEach { caveat ->
            val segments = HeroStatsText.boldSegments(caveat)
            assertEquals(caveat.replace("**", ""), segments.joinToString("") { it.first }.replace("**", ""))
        }
        assertTrue(index.dataset.caveats.any { caveat -> HeroStatsText.boldSegments(caveat).any { it.second } })
        assertTrue(index.dataset.interpolation.notes.any { note -> HeroStatsText.boldSegments(note.text).any { it.second } })
    }
}
