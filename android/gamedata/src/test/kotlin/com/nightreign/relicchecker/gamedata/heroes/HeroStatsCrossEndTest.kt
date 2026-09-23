package com.nightreign.relicchecker.gamedata.heroes

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * 「双端对照基线」三端化：macOS HeroStatsChecks.swift ⑩–⑬ 与 Windows heroes.test.mjs 的 FIXTURES /
 * COPY 用例钉的是同一张表、同一批期望值，这里照抄一遍。任何一端的纯逻辑或文案漂了，三端各自红。
 */
class HeroStatsCrossEndTest {
    private val index get() = HeroesTestData.index
    private val names get() = index.statNames

    private data class Fixture(
        val name: String,
        val heroKey: String,
        val level: Int,
        val modifierIds: List<Int>,
        val libraKey: String?,
        val isAnchor: Boolean,
        /** 按 statNames.attributeOrder 排的 8 项。 */
        val baseStats: List<Int>,
        val baseDerived: Map<String, Double>,
        val delta: Map<String, Int> = emptyMap(),
        /** 卡片 / 表格里显示的那个数：**生效**增减量（最终 − 基础）。 */
        val cardDelta: Map<String, Int> = emptyMap(),
        /** null = 没勾词条。 */
        val finalStats: List<Int>? = null,
        val finalDerived: Map<String, Double>? = null,
        val clampedFrom: Map<String, Int> = emptyMap(),
        val clampSummary: String? = null,
        val clampRequestedText: String? = null,
        val floorAlt: Map<String, Int>? = null,
        val floorAltText: String? = null,
        val sourceLabel: String? = null,
        val source: HeroModifierSource? = null,
    )

    private val fixtures = listOf(
        Fixture(
            name = "追踪者 15 级：两条词条全勾",
            heroKey = "wylder", level = 15, modifierIds = listOf(6_640_000, 6_640_100), libraKey = null,
            isAnchor = true,
            baseStats = listOf(52, 19, 27, 50, 40, 15, 15, 10),
            baseDerived = mapOf("hp" to 1120.0, "fp" to 140.0, "stamina" to 102.0, "equipLoad" to 74.1),
            delta = mapOf("vigor" to -5, "mind" to 10, "strength" to -7, "dexterity" to -5, "intelligence" to 15, "faith" to 15),
            cardDelta = mapOf("vigor" to -5, "mind" to 10, "strength" to -7, "dexterity" to -5, "intelligence" to 15, "faith" to 15),
            finalStats = listOf(47, 29, 27, 43, 35, 30, 30, 10),
            finalDerived = mapOf("hp" to 1020.0, "fp" to 190.0, "stamina" to 102.0, "equipLoad" to 74.1),
            sourceLabel = "词条沿用 12 级锚点", source = HeroModifierSource.CARRIED,
        ),
        Fixture(
            name = "铁之眼 15 级：利普拉（力气）+ 降灵巧词条（会钳位）",
            heroKey = "ironeye", level = 15, modifierIds = listOf(6_642_000), libraKey = "strength",
            isAnchor = true,
            baseStats = listOf(47, 6, 23, 73, 9, 3, 3, 3),
            baseDerived = mapOf("hp" to 1020.0, "fp" to 75.0, "stamina" to 94.0, "equipLoad" to 68.8),
            delta = mapOf("dexterity" to -9, "arcane" to 15),
            cardDelta = mapOf("dexterity" to -8, "arcane" to 15),
            finalStats = listOf(47, 6, 23, 73, 1, 3, 3, 18),
            finalDerived = mapOf("hp" to 1020.0, "fp" to 75.0, "stamina" to 94.0, "equipLoad" to 68.8),
            clampedFrom = mapOf("dexterity" to 0),
            clampSummary = "灵巧 叠加后不足 1，已钳到最低 1（游戏里属性不会低于 1）",
            clampRequestedText = "词条请求 -9，已钳到最低 1",
            sourceLabel = "词条沿用 12 级锚点", source = HeroModifierSource.CARRIED,
        ),
        Fixture(
            name = "学者 5 级：第 2 条词条（有 deltaFloorAlt）",
            heroKey = "scholar", level = 5, modifierIds = listOf(6_647_300), libraKey = null,
            isAnchor = false,
            baseStats = listOf(20, 9, 10, 5, 7, 12, 6, 50),
            baseDerived = mapOf("hp" to 480.0, "fp" to 90.0, "stamina" to 68.0, "equipLoad" to 48.2),
            delta = mapOf("endurance" to 2, "dexterity" to 18, "intelligence" to -2, "arcane" to -10),
            cardDelta = mapOf("endurance" to 2, "dexterity" to 18, "intelligence" to -2, "arcane" to -10),
            finalStats = listOf(20, 9, 12, 5, 25, 10, 6, 40),
            finalDerived = mapOf("hp" to 480.0, "fp" to 90.0, "stamina" to 72.0, "equipLoad" to 51.4),
            floorAlt = mapOf("intelligence" to -3, "arcane" to -11),
            floorAltText = "若按 floor 取整，负向项改为：智力 -3、感应 -11（其余项不变）",
            sourceLabel = "词条推算", source = HeroModifierSource.INFERRED,
        ),
        Fixture(
            name = "女爵 12 级：不勾词条",
            heroKey = "duchess", level = 12, modifierIds = emptyList(), libraKey = null,
            isAnchor = true,
            baseStats = listOf(35, 24, 14, 9, 38, 36, 24, 11),
            baseDerived = mapOf("hp" to 780.0, "fp" to 165.0, "stamina" to 76.0, "equipLoad" to 54.5),
        ),
        Fixture(
            name = "送葬者 1 级：不勾词条",
            heroKey = "undertaker", level = 1, modifierIds = emptyList(), libraKey = null,
            isAnchor = true,
            baseStats = listOf(7, 4, 3, 5, 2, 2, 5, 10),
            baseDerived = mapOf("hp" to 220.0, "fp" to 65.0, "stamina" to 54.0, "equipLoad" to 45.0),
        ),
    )

    @Test
    fun `双端对照基线：5 组单角色快照逐格钉死（属性 ／ 派生值 ／ 钳位 ／ 标记）`() {
        val keys = names.attributeKeys
        fixtures.forEach { fixture ->
            val snapshot = index.snap(fixture.heroKey, fixture.level, fixture.modifierIds, fixture.libraKey)
            assertEquals(fixture.isAnchor, snapshot.isAnchorLevel, "${fixture.name}：基础表锚点标记")
            assertEquals(fixture.baseStats, keys.map { snapshot.baseStats[it] }, "${fixture.name}：基础属性")
            names.derivedKeys.forEach { assertClose(fixture.baseDerived.getValue(it), snapshot.baseDerived[it], "${fixture.name}：基础 $it") }

            val expectedFinal = fixture.finalStats
            val expectedFinalDerived = fixture.finalDerived
            if (expectedFinal == null || expectedFinalDerived == null) {
                assertFalse(snapshot.hasModifier, "${fixture.name}：没勾词条就不该有生效词条")
                assertNull(snapshot.modifierSource, "${fixture.name}：没勾词条就不该有来源标记")
                assertEquals(snapshot.baseStats, snapshot.finalStats)
                assertTrue(snapshot.requestedDelta.isEmpty())
                assertTrue(snapshot.clampedStats.isEmpty() && snapshot.clampedFrom.isEmpty())
                keys.forEach { assertNull(snapshot.effectiveDelta(it), "${fixture.name}：没勾词条就没有可显示的增减量") }
                return@forEach
            }

            keys.forEach { key ->
                assertEquals(fixture.delta[key] ?: 0, snapshot.requestedDelta[key] ?: 0, "${fixture.name}：$key 请求增减量")
                assertEquals(fixture.cardDelta[key] ?: 0, snapshot.effectiveDelta(key) ?: 0, "${fixture.name}：$key 卡片上的生效增减量")
            }
            assertEquals(expectedFinal, keys.map { snapshot.finalStats[it] }, "${fixture.name}：最终属性")
            names.derivedKeys.forEach { assertClose(expectedFinalDerived.getValue(it), snapshot.finalDerived[it], "${fixture.name}：最终 $it") }
            assertEquals(fixture.clampedFrom, snapshot.clampedFrom, "${fixture.name}：钳位前原值")
            assertEquals(keys.filter { it in fixture.clampedFrom }, snapshot.clampedStats, "${fixture.name}：钳位列表按属性展示顺序")

            val tag = HeroStatsText.modifierSource(fixture.level, index.modifierAnchorLevels)
            assertEquals(fixture.sourceLabel, tag?.label, "${fixture.name}：增减量来源文案")
            assertEquals(fixture.source, tag?.source, "${fixture.name}：增减量来源分类")
            assertEquals(tag, snapshot.modifierSource, "${fixture.name}：快照上的来源标记与判定函数一致")

            keys.forEach { key ->
                val raw = snapshot.baseStats.getValue(key) + (snapshot.requestedDelta[key] ?: 0)
                assertEquals(maxOf(HeroStatsMath.MINIMUM_STAT, raw), snapshot.finalStats[key], "${fixture.name}：$key 钳位口径")
                assertEquals(raw < HeroStatsMath.MINIMUM_STAT, key in snapshot.clampedFrom, "${fixture.name}：$key 是否记为钳位")
            }
            assertEquals(index.derivedValues(snapshot.finalStats), snapshot.finalDerived, "${fixture.name}：派生值按钳位后的属性重算")

            fixture.clampRequestedText?.let { expected ->
                assertEquals(1, snapshot.clampedStats.size)
                val clampedKey = snapshot.clampedStats.first()
                assertEquals(expected, HeroStatsCopy.clampRequestedNote(snapshot.requestedDelta.getValue(clampedKey)))
                assertNotEquals(snapshot.requestedDelta[clampedKey], snapshot.effectiveDelta(clampedKey))
            }
            fixture.clampSummary?.let { expected ->
                assertEquals(expected, HeroStatsCopy.clampSummary(snapshot.clampedStats.map(names::attributeTitle)))
            }
            if (fixture.floorAlt != null && fixture.floorAltText != null) {
                val row = assertNotNull(index.modifier(fixture.modifierIds.first()).level(fixture.level))
                assertEquals(fixture.floorAlt, row.deltaFloorAlt)
                assertEquals(fixture.floorAltText, HeroStatsCopy.floorAlt(HeroStatsCopy.deltaSummary(row.deltaFloorAlt, names)))
                row.deltaFloorAlt.forEach { (key, value) ->
                    assertTrue(value < 0, "deltaFloorAlt 只会出现在负向项上")
                    assertEquals((row.delta[key] ?: 0) - 1, value)
                }
            }
        }
    }

    @Test
    fun `双端对照基线⑥：同级对比 10 级按血量降序，前三名与兜底顺序钉死`() {
        val rows = index.comparisonRows(10)
        assertEquals(10, rows.size)
        val byHP = HeroComparison.sorted(rows, HeroComparisonColumn.Derived("hp"), false)
        assertEquals(listOf("守护者", "无赖", "追踪者"), byHP.take(3).map { it.nameZh })
        assertEquals(listOf(1020.0, 940.0, 880.0), byHP.take(3).map { it.derived["hp"] })
        assertEquals(listOf(47, 43, 40), byHP.take(3).map { it.stats["vigor"] })
        val hpValues = byHP.map { it.derived.getValue("hp") }
        assertEquals(hpValues.sortedDescending(), hpValues)
        byHP.forEach { assertClose((20 * it.stats.getValue("vigor") + 80).toDouble(), it.derived["hp"], "${it.nameZh} 血量 = 20 × 生命力 + 80") }

        // 全平手时升降序都按数据集顺序（不是严格反序）
        val flat = rows.map { it.copy(stats = it.stats + ("arcane" to 7)) }
        val asc = HeroComparison.sorted(flat, HeroComparisonColumn.Stat("arcane"), true).map { it.heroId }
        val desc = HeroComparison.sorted(flat, HeroComparisonColumn.Stat("arcane"), false).map { it.heroId }
        assertEquals(asc, desc)
        assertEquals(flat.map { it.heroId }.sorted(), asc)
    }

    @Test
    fun `双端共用文案 COPY：逐字钉死`() {
        assertEquals("—", HeroStatsCopy.MISSING)
        assertEquals("数据未内置", HeroStatsCopy.EMPTY_DATA)
        assertEquals("单角色", HeroStatsCopy.VIEW_SINGLE)
        assertEquals("同级对比", HeroStatsCopy.VIEW_COMPARE)

        assertEquals("15 级是参数锚点", HeroStatsCopy.baseLevelBadge(15, true))
        assertEquals("7 级为插值推算", HeroStatsCopy.baseLevelBadge(7, false))
        assertEquals("参数锚点", HeroStatsCopy.BASE_ANCHOR_TAG)
        assertEquals("插值推算", HeroStatsCopy.BASE_INTERPOLATED_TAG)
        assertEquals(
            "加粗行是参数表里的锚点（1 / 2 / 12 / 15 级），其余等级按相邻锚点线性插值后向下取整。",
            HeroStatsCopy.allLevelsCaption(listOf(1, 2, 12, 15)),
        )

        assertEquals("转职遗物 2 条", HeroStatsCopy.modifierCountBadge(2))
        assertEquals("勾选后在基础属性上加减（可同时勾选，效果相加）；派生值按 CalcCorrectGraph 重算", HeroStatsCopy.MODIFIER_SUBTITLE)
        assertEquals("仅 DLC 池可掉", HeroStatsCopy.DLC_ONLY_TAG)
        assertEquals("本级无增减", HeroStatsCopy.NO_DELTA_AT_LEVEL)
        assertEquals("数据未内置该角色的转职遗物词条", HeroStatsCopy.NO_MODIFIER_DATA)
        assertEquals("若按 floor 取整，负向项改为：智力 -3、感应 -11（其余项不变）", HeroStatsCopy.floorAlt("智力 -3、感应 -11"))

        assertEquals("钳", HeroStatsCopy.CLAMP_CELL_TAG)
        assertEquals("已钳位", HeroStatsCopy.CLAMP_ROW_TAG)
        assertEquals("原为 0，已钳到最低 1", HeroStatsCopy.clampedFromNote(0))
        assertEquals("原为 -3，已钳到最低 1", HeroStatsCopy.clampedFromNote(-3))
        assertEquals("词条请求 -9，已钳到最低 1", HeroStatsCopy.clampRequestedNote(-9))
        assertEquals("词条请求 -13，已钳到最低 1", HeroStatsCopy.clampRequestedNote(-13))
        assertEquals("生命力、集中力 叠加后不足 1，已钳到最低 1（游戏里属性不会低于 1）", HeroStatsCopy.clampSummary(listOf("生命力", "集中力")))
        assertEquals(
            "1–15 级里有 2 级叠加后不足 1：13 级 灵巧；15 级 灵巧、感应；已钳到最低 1（游戏里属性不会低于 1）",
            HeroStatsCopy.clampSummaryByLevel(listOf(HeroClampedLevel(13, listOf("灵巧")), HeroClampedLevel(15, listOf("灵巧", "感应"))), 15),
        )
        assertEquals("", HeroStatsCopy.clampSummaryByLevel(emptyList(), 15))

        assertEquals("整套替换", HeroStatsCopy.LIBRA_SWAP_TAG)
        assertEquals("利普拉的交易把整套基础属性表替换掉；能否与转职遗物叠加是按参数字段结构推断的，未实测", HeroStatsCopy.LIBRA_HINT)
        assertEquals("选中后基础表整套换成对应的替换表，转职遗物仍可叠加。", HeroStatsCopy.LIBRA_EMPTY_HINT)
        assertEquals("利普拉：力气", HeroStatsCopy.libraBadge("力气"))
        assertEquals("已做利普拉的交易，基础表整套替换，与外部 wiki 的角色原表差异不再适用", HeroStatsCopy.LIBRA_CROSS_CHECK_NOTE)
        assertEquals("与外部 wiki 有 14 格差异，本页以参数为准：补丁 1.02.2", HeroStatsCopy.crossCheckNote(14, "补丁 1.02.2"))
        assertEquals("与外部 wiki 有 14 格差异，本页以参数为准", HeroStatsCopy.crossCheckNote(14, ""))

        assertEquals("*", HeroStatsCopy.LEGACY_MARK)
        assertEquals("负重上限 *", HeroStatsCopy.legacyHeader("负重上限"))
        assertEquals("本作装备没有重量，负重上限是《艾尔登法环》继承下来的遗留列，未经实测", HeroStatsCopy.EQUIP_LOAD_HINT)
        assertEquals(
            "* 负重上限是《艾尔登法环》继承下来的遗留列：本作装备没有重量、界面也没有负重条，未经实测，仅供参考。",
            HeroStatsCopy.EQUIP_LOAD_FOOTNOTE,
        )
        assertEquals(
            "对比表只用各角色的基础表：利普拉的交易不分角色（叠上去每行都一样），转职遗物是逐角色的词条，都不进对比。",
            HeroStatsCopy.COMPARE_CAPTION,
        )

        assertEquals("插值与验证口径（10 条）", HeroStatsCopy.interpolationTitle(10))
        assertEquals("插值与验证口径（10 条）", HeroStatsCopy.interpolationTitle(index.dataset.interpolation.notes.size))
        assertEquals("已知取舍（13 条）", HeroStatsCopy.caveatsTitle(13))
        assertEquals("已知取舍（13 条）", HeroStatsCopy.caveatsTitle(index.dataset.caveats.size))
        assertEquals("数据出处（10 条）与外部对照", HeroStatsCopy.sourcesTitle(10))
        assertEquals("数据出处（10 条）与外部对照", HeroStatsCopy.sourcesTitle(index.dataset.sources.size))
        assertEquals(listOf("游戏版本", "数据版本", "生成时间", "数据集结构版本", "收录"), HeroStatsCopy.versionLabels)
        assertEquals("10 位夜行者 × 15 级 · 20 条转职遗物词条 · 5 笔利普拉交易", HeroStatsCopy.contentSummary(10, 15, 20, 5))

        val row12 = assertNotNull(index.modifier(6_640_000).level(12))
        assertEquals("生命力 -5、集中力 +10", HeroStatsCopy.deltaSummary(row12.delta, names))
        assertEquals("", HeroStatsCopy.deltaSummary(emptyMap(), names))
        assertEquals("集中力 +3", HeroStatsCopy.deltaSummary(mapOf("vigor" to 0, "mind" to 3), names))

        assertEquals(listOf("equipLoad"), names.legacyDerivedKeys, "遗留列当前只有负重上限，靠 inGameLabel 判定")

        assertEquals(14, index.crossCheck("duchess")?.mismatchCount)
        assertEquals("params", index.crossCheck("duchess")?.authoritative)
        assertNull(index.crossCheck("wylder"))
        assertNull(index.crossCheck("executor"))
        assertNull(index.crossCheck("不存在"))

        val snapshots = index.snapshots("ironeye", setOf(6_642_000), "strength")
        assertEquals(15, snapshots.size)
        val clampedRows = index.clampedByLevel(snapshots)
        assertTrue(clampedRows.size > 1)
        val expectedRows = snapshots.filter { it.clampedStats.isNotEmpty() }
        assertEquals(expectedRows.map { it.level }, clampedRows.map { it.level })
        clampedRows.zip(expectedRows).forEach { (aggregated, snapshot) ->
            assertEquals(snapshot.clampedStats.map(names::attributeTitle), aggregated.names)
        }
        val summary = HeroStatsCopy.clampSummaryByLevel(clampedRows, index.maxLevel)
        assertTrue(summary.startsWith("1–15 级里有 ${clampedRows.size} 级叠加后不足 1："))
        clampedRows.forEach { assertTrue(summary.contains("${it.level} 级 " + it.names.joinToString("、"))) }
        assertTrue(index.clampedByLevel(index.snapshots("ironeye")).isEmpty())
    }

    @Test
    fun `三端对称断言：插值说明、最大等级读数据集、来源配色、缺项破折号、图表可用性`() {
        val dataset = index.dataset
        // ① 插值说明 10 条，同序同文
        val notes = dataset.interpolation.notes
        assertEquals(10, notes.size)
        assertEquals(HeroStatsCopy.interpolationNoteTitles, notes.map { it.title })
        assertEquals("基础属性表只有 1 / 2 / 12 / 15 级是参数原值，转职遗物只有 1 / 12 级是参数原值。", notes[0].text)
        assertEquals(
            "基础属性表只有 1 / 8 级是参数原值，转职遗物只有 1 / 6 级是参数原值。",
            HeroStatsCopy.interpolationAnchorNote(listOf(1, 8), listOf(1, 6)),
        )
        assertEquals(dataset.interpolation.baseRule, notes[1].text)
        assertEquals(dataset.interpolation.baseVerification, notes[2].text)
        assertEquals(dataset.interpolation.libraRule, notes[9].text)
        assertTrue(notes[7].text.startsWith("基础属性表按向下取整（floor）"))
        assertTrue(notes[7].text.contains("转职遗物增减量按向零取整（trunc）"))
        assertTrue(notes[7].text.contains("两种取整只在负的增减量上差 1；"))
        assertTrue(notes[7].text.contains("deltaFloorAlt"))
        assertEquals("向下取整（floor）", HeroStatsCopy.roundingTerm("floor"))
        assertEquals("四舍五入（round）", HeroStatsCopy.roundingTerm("round"))
        assertEquals("别的", HeroStatsCopy.roundingTerm("别的"))
        assertEquals("", HeroStatsCopy.interpolationRoundingNote("", ""))
        assertEquals(listOf("基础属性插值"), HeroInterpolation(baseRule = "x").notes.map { it.title })
        assertTrue(HeroInterpolation.EMPTY.notes.isEmpty())

        // ② 最大等级读数据集（走真实解码路径）
        val big = HeroesParser.parse(levelsDataset(levels = 20, declaredMaxLevel = 20))
        assertEquals(20, big.maxLevel)
        assertEquals((1..20).toList(), big.levelRange)
        assertEquals(20, big.snapshots("wylder").size)
        assertEquals(25, big.snapshot("wylder", 20)?.baseStats?.get("vigor"))
        assertTrue(big.summary.contains("1–20 级"))
        assertEquals(20, big.clampLevel(99), "钳位上限跟着数据集走")
        assertEquals(
            "1–20 级里有 1 级叠加后不足 1：20 级 灵巧；已钳到最低 1（游戏里属性不会低于 1）",
            HeroStatsCopy.clampSummaryByLevel(listOf(HeroClampedLevel(20, listOf("灵巧"))), big.maxLevel),
        )
        assertEquals("1 位夜行者 × 20 级 · 0 条转职遗物词条 · 0 笔利普拉交易", HeroStatsCopy.contentSummary(1, big.maxLevel, 0, 0))
        assertEquals("1 位夜行者 × 20 级 · 0 条转职遗物词条 · 0 笔利普拉交易", big.versionRows()[4].second)
        val undeclared = HeroesParser.parse(levelsDataset(levels = 20, declaredMaxLevel = null))
        assertEquals(0, undeclared.dataset.interpolation.maxLevel, "没声明时不该假装声明了 15")
        assertEquals(20, undeclared.maxLevel)
        assertEquals(20, undeclared.levelRange.size)
        val declaredShort = HeroesParser.parse(levelsDataset(levels = 20, declaredMaxLevel = 12))
        assertEquals(12, declaredShort.maxLevel, "声明值与角色表不一致时以声明为准")
        assertEquals(12, declaredShort.snapshots("wylder").size)
        assertEquals(15, index.maxLevel)
        assertEquals(HeroStatsIndex.FALLBACK_MAX_LEVEL, HeroStatsIndex(HeroDataset()).maxLevel, "连角色表都没有时才退回常量")
        assertEquals(15, HeroStatsIndex.FALLBACK_MAX_LEVEL)

        // ③ 来源三档三色（图标也各不相同）
        assertEquals("green", HeroModifierSource.ANCHOR.colorToken)
        assertEquals("amber", HeroModifierSource.INFERRED.colorToken)
        assertEquals("blue", HeroModifierSource.CARRIED.colorToken)
        assertNotEquals(HeroModifierSource.ANCHOR.colorToken, HeroModifierSource.CARRIED.colorToken)
        assertEquals(3, HeroModifierSource.entries.map { it.glyph }.toSet().size)
        listOf(1 to "green", 6 to "amber", 15 to "blue").forEach { (level, token) ->
            assertEquals(token, HeroStatsText.modifierSource(level, index.modifierAnchorLevels)?.source?.colorToken)
        }

        // ④ 属性缺失给破折号，且不编一个最终值出来
        val holed = names.attributeKeys.filter { it != "arcane" }.associateWith { 10 }
        val applied = HeroStatsMath.apply(listOf(mapOf("arcane" to -20, "vigor" to -20)), holed, names.attributeKeys)
        assertNull(applied.stats["arcane"])
        assertFalse("arcane" in applied.clamped)
        assertNull(applied.clampedFrom["arcane"])
        assertEquals(HeroStatsMath.MINIMUM_STAT, applied.stats["vigor"])
        assertEquals(HeroStatsCopy.MISSING, HeroStatsText.statText(applied.stats["arcane"]))
        assertEquals("0", HeroStatsText.statText(0))

        // ⑤ growthGraph 可用性：三个数组必须等长
        val shortAdj = HeroGrowthGraph(9001, "adjPt 残缺", listOf(1.0, 10.0), listOf(0.0, 90.0), listOf(1.0))
        assertFalse(shortAdj.isUsable)
        assertEquals(0.0, shortAdj.value(5))
        assertEquals(0, shortAdj.integerValue(5))
        val longY = HeroGrowthGraph(9002, "ys 偏长", listOf(1.0, 10.0), listOf(0.0, 90.0, 100.0), listOf(1.0, 1.0))
        assertFalse(longY.isUsable)
        assertNull(HeroStatsMath.derivedValues(mapOf("vigor" to 20), names, mapOf(100 to shortAdj))["hp"])
    }

    @Test
    fun `整数求值的两条路径：精确整数除法与 normalize + floor 逐格一致`() {
        val graphs = index.dataset.growthGraphs
        listOf(100, 101, 104).forEach { id ->
            val graph = assertNotNull(graphs[id])
            (1..99).forEach { stat ->
                val expected = kotlin.math.floor(HeroStatsMath.normalize(graph.value(stat))).toInt()
                assertEquals(expected, graph.integerValue(stat), "CalcCorrectGraph $id @ $stat")
            }
        }
        val fractional = HeroGrowthGraph(9101, "端点非整数", listOf(1.0, 10.0), listOf(0.5, 100.25), listOf(1.0, 1.0))
        assertTrue(fractional.isUsable)
        (1..12).forEach { stat ->
            assertEquals(kotlin.math.floor(HeroStatsMath.normalize(fractional.value(stat))).toInt(), fractional.integerValue(stat))
        }
        assertEquals(44, fractional.integerValue(5))
        val curved = HeroGrowthGraph(9102, "带指数", listOf(1.0, 9.0), listOf(0.0, 240.0), listOf(2.0, 2.0))
        assertFalse(curved.linear)
        assertEquals(60, curved.integerValue(5))
        (1..9).forEach { stat ->
            assertEquals(kotlin.math.floor(HeroStatsMath.normalize(curved.value(stat))).toInt(), curved.integerValue(stat))
        }
        assertEquals(60.0, kotlin.math.floor(HeroStatsMath.normalize(59.9999999999)))
        assertEquals(59.0, kotlin.math.floor(HeroStatsMath.normalize(59.99)))
    }

    /** macOS datasetJSON(levels:declaredMaxLevel:) 的同构版本。 */
    private fun levelsDataset(levels: Int, declaredMaxLevel: Int?): String {
        val rows = (1..levels).joinToString(",") { level ->
            val anchor = level == 1 || level == levels
            """{"level": $level, "isAnchor": $anchor, "stats": {"vigor": ${level + 5}}}"""
        }
        val declared = declaredMaxLevel?.let { """, "maxLevel": $it""" } ?: ""
        return """
            {"schemaVersion": 1,
             "statNames": {"attributeOrder": ["vigor"], "derivedOrder": [], "derived": [],
                           "attributes": [{"key": "vigor", "zh": "生命力", "en": "Vigor"}]},
             "interpolation": {"baseAnchorLevels": [1, 2]$declared},
             "heroes": [{"id": 1, "key": "wylder", "nameZh": "追踪者", "nameEn": "Wylder", "levels": [$rows]}]}
        """.trimIndent()
    }
}
