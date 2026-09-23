package com.nightreign.relicchecker.gamedata.heroes

import com.nightreign.relicchecker.gamedata.GameDataFormatException
import com.nightreign.relicchecker.gamedata.GameDataHeader
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertNotEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * windows/tests/heroes.test.mjs 逐条对应（测试名就是需求清单）。JS 独有的口径（字符串 id、
 * `evalGrowthGraph(hp, "x")`、DOM 注册）在 Kotlin 的类型系统里不存在，改为断言等价的约束；
 * 「双端对照基线」「COPY」几条在 HeroStatsCrossEndTest 里。
 */
class HeroStatsWindowsParityTest {
    private val index get() = HeroesTestData.index
    private val names get() = index.statNames
    private val attributeKeys get() = HeroesTestData.attributeKeys
    private val derivedKeys get() = HeroesTestData.derivedKeys

    private fun modsOf(heroKey: String) = index.modifiers(heroKey)

    @Test
    fun `模块注册：解析器标识全应用唯一且符合约定`() {
        assertEquals("heroes.page.v1", HeroesParser.PARSER_ID)
        assertTrue(Regex("^[a-z]+\\.[a-z]+\\.v\\d+$").matches(HeroesParser.PARSER_ID))
        assertNotEquals(GameDataHeader.PARSER_ID, HeroesParser.PARSER_ID)
    }

    @Test
    fun `数据集本身是 schema 1，10 个角色 × 15 级，20 条转职遗物、5 套利普拉交易`() {
        assertEquals(1, index.dataset.schemaVersion)
        assertEquals(10, index.heroes.size)
        assertEquals(20, index.dataset.statModifiers.size)
        assertEquals(5, index.libraRespecs.size)
        index.heroes.forEach { hero ->
            assertEquals(15, hero.levels.size)
            assertEquals(HeroesTestData.levels, hero.levels.map { it.level })
        }
        assertTrue(index.dataset.caveats.isNotEmpty())
        assertTrue(index.dataset.interpolation.baseRule.isNotEmpty())
    }

    @Test
    fun `属性 ／ 派生值的中文名与顺序一律读数据集 statNames`() {
        assertEquals(listOf("生命力", "集中力", "耐力", "力气", "灵巧", "智力", "信仰", "感应"), names.orderedAttributes.map { it.zh })
        assertEquals(listOf("血量", "专注值", "精力", "负重上限"), names.orderedDerived.map { it.zh })
        assertEquals(false, names.derivedEntry("equipLoad")?.integer)
        assertEquals(true, names.derivedEntry("hp")?.integer)
    }

    @Test
    fun `派生值重算：每个角色每一级都必须等于数据集的 derived`() {
        var checked = 0
        index.heroes.forEach { hero ->
            hero.levels.forEach { row ->
                assertEquals(row.derived, index.derivedValues(row.stats), "${hero.key} ${row.level} 级派生值与数据集不一致")
                checked += derivedKeys.size
            }
        }
        assertEquals(10 * 15 * 4, checked)
    }

    @Test
    fun `派生值重算：利普拉 5 套替换表同样逐格一致`() {
        var checked = 0
        index.libraRespecs.forEach { deal ->
            assertEquals(15, deal.levels.size)
            deal.levels.forEach { row ->
                assertEquals(row.derived, index.derivedValues(row.stats), "利普拉（${deal.key}）${row.level} 级")
                checked += derivedKeys.size
            }
        }
        assertEquals(5 * 15 * 4, checked)
    }

    @Test
    fun `派生值只吃对应的那一项属性：改别的属性不动它`() {
        val base = mapOf("vigor" to 20, "mind" to 10, "endurance" to 12, "strength" to 30, "dexterity" to 30, "intelligence" to 5, "faith" to 5, "arcane" to 5)
        val before = index.derivedValues(base)
        assertEquals(before, index.derivedValues(base + mapOf("strength" to 60, "dexterity" to 60, "arcane" to 40)))
        val moreVigor = index.derivedValues(base + ("vigor" to 21))
        assertEquals(before.getValue("hp") + 20, moreVigor["hp"])
        assertEquals(before["fp"], moreVigor["fp"])
        assertEquals(before["stamina"], moreVigor["stamina"])
    }

    @Test
    fun `growthGraphs 的分段公式：端点钳位 + 数据集自述的三条直线`() {
        val hp = assertNotNull(index.dataset.growthGraphs[100])
        val fp = assertNotNull(index.dataset.growthGraphs[101])
        val stamina = assertNotNull(index.dataset.growthGraphs[104])
        assertEquals(100.0, hp.value(1))
        assertEquals(100.0, hp.value(0), "低于最低锚点钳到端点")
        assertEquals(2060.0, hp.value(99))
        assertEquals(2060.0, hp.value(150), "高于最高锚点钳到端点")
        (1..99).forEach { stat ->
            assertEquals((20 * stat + 80).toDouble(), kotlin.math.floor(hp.value(stat)), "血量 = 20 × 生命力 + 80")
            assertEquals((5 * stat + 45).toDouble(), kotlin.math.floor(fp.value(stat)), "专注值 = 5 × 集中力 + 45")
            if (stat <= 75) assertEquals((2 * stat + 48).toDouble(), kotlin.math.floor(stamina.value(stat)), "精力 = 2 × 耐力 + 48")
        }
        // JS 里的 evalGrowthGraph(null) / (hp, "x") 在 Kotlin 的类型系统里不存在；等价约束是「不可用图表不编数字」
        assertTrue(HeroStatsMath.derivedValues(mapOf("vigor" to 10), names, emptyMap()).isEmpty())
    }

    @Test
    fun `转职遗物 12 级锚点：叠加结果 = 基础 stats + delta，派生值按叠加后的属性重算`() {
        var checked = 0
        index.dataset.statModifiers.forEach { mod ->
            val hero = assertNotNull(index.hero(mod.heroKey))
            val baseRow = assertNotNull(hero.level(12))
            val modRow = assertNotNull(mod.level(12))
            assertTrue(modRow.isAnchor, "12 级必须是转职遗物的参数锚点")
            val computed = index.snap(mod.heroKey, 12, listOf(mod.affixId))
            assertTrue(computed.hasModifier)
            attributeKeys.forEach { key ->
                assertEquals(baseRow.stats.getValue(key) + (modRow.delta[key] ?: 0), computed.finalStats[key], "${mod.nameZh} 的 $key")
                checked += 1
            }
            assertEquals(baseRow.stats, computed.baseStats)
            assertEquals(baseRow.derived, computed.baseDerived)
            assertEquals(index.derivedValues(computed.finalStats), computed.finalDerived)
            assertEquals("词条锚点", computed.modifierSource?.label)
            assertEquals(HeroModifierSource.ANCHOR, computed.modifierSource?.source)
        }
        assertEquals(20 * 8, checked)
    }

    @Test
    fun `转职遗物 1 级锚点同样成立，且 anchors 与 levels 对得上`() {
        index.dataset.statModifiers.forEach { mod ->
            val anchor1 = assertNotNull(mod.anchors.firstOrNull { it.level == 1 })
            val anchor12 = assertNotNull(mod.anchors.firstOrNull { it.level == 12 })
            assertEquals(anchor1.delta, mod.level(1)?.delta)
            assertEquals(anchor12.delta, mod.level(12)?.delta)
            val baseRow = assertNotNull(index.hero(mod.heroKey)?.level(1))
            val computed = index.snap(mod.heroKey, 1, listOf(mod.affixId))
            attributeKeys.forEach { key ->
                assertEquals(maxOf(1, baseRow.stats.getValue(key) + (anchor1.delta[key] ?: 0)), computed.finalStats[key])
            }
        }
    }

    @Test
    fun `13–15 级沿用 12 级锚点：delta 逐项相同，且带「沿用 12 级锚点」标记`() {
        index.dataset.statModifiers.forEach { mod ->
            val at12 = assertNotNull(mod.level(12)).delta
            listOf(13, 14, 15).forEach { level ->
                val row = assertNotNull(mod.level(level))
                assertEquals(at12, row.delta, "${mod.nameZh} $level 级应沿用 12 级 delta")
                assertFalse(row.isAnchor)
                assertTrue(row.inferred)
                assertEquals("词条沿用 12 级锚点", index.modifierLevelNote(level)?.label)
                assertEquals(HeroModifierSource.CARRIED, index.modifierLevelNote(level)?.source)
            }
        }
    }

    @Test
    fun `2–11 级是推算：数据集标了 inferred，页面给「词条推算」标记`() {
        (2..11).forEach { level ->
            assertEquals("词条推算", index.modifierLevelNote(level)?.label)
            assertEquals(HeroModifierSource.INFERRED, index.modifierLevelNote(level)?.source)
        }
        listOf(1, 12).forEach { level ->
            assertEquals("词条锚点", index.modifierLevelNote(level)?.label)
            assertEquals(HeroModifierSource.ANCHOR, index.modifierLevelNote(level)?.source)
        }
        index.dataset.statModifiers.forEach { mod ->
            mod.levels.forEach { row ->
                val isAnchorLevel = row.level == 1 || row.level == 12
                assertEquals(isAnchorLevel, row.isAnchor)
                assertEquals(!isAnchorLevel, row.inferred)
            }
        }
    }

    @Test
    fun `锚点等级读数据集而不是写死 1 ／ 12：换一组锚点，标记跟着走`() {
        assertEquals(listOf(1, 12), index.modifierAnchorLevels)
        assertEquals(listOf(1, 2, 12, 15), index.baseAnchorLevels)
        assertEquals(15, index.maxLevel)
        assertEquals("词条沿用 8 级锚点", HeroStatsText.modifierSource(9, listOf(1, 8))?.label)
        assertEquals("词条锚点", HeroStatsText.modifierSource(8, listOf(1, 8))?.label)
        assertEquals("词条推算", HeroStatsText.modifierSource(5, listOf(1, 8))?.label)
        assertNull(HeroStatsText.modifierSource(3, emptyList()))
        assertNull(HeroStatsIndex(HeroDataset()).modifierLevelNote(3), "数据集没给锚点信息时什么都不标")
        assertEquals(
            "锚点只有 1 / 12 级：中间等级是线性插值后向零取整的推算值，12 级之后沿用 12 级锚点" +
                "（沿用这一条已由多组 15 级实测确认）。",
            index.modifierRuleHint,
        )
        assertEquals("数据集没有给出转职遗物的参数锚点等级，本页不另立说法。", HeroStatsCopy.modifierRuleHint(emptyList(), 15))
    }

    @Test
    fun `两条词条可同时勾选：增减量相加，派生值按合计后的属性重算`() {
        index.heroes.forEach { hero ->
            val mods = modsOf(hero.key)
            assertEquals(2, mods.size, "${hero.key} 应恰好有 2 条转职遗物词条")
            val baseRow = assertNotNull(hero.level(12))
            val computed = index.snap(hero.key, 12, mods.map { it.affixId })
            assertEquals(2, computed.activeModifiers.size)
            attributeKeys.forEach { key ->
                val sum = mods.sumOf { it.level(12)?.delta?.get(key) ?: 0 }
                assertEquals(sum, computed.requestedDelta[key] ?: 0)
                assertEquals(maxOf(1, baseRow.stats.getValue(key) + sum), computed.finalStats[key])
            }
            assertEquals(index.derivedValues(computed.finalStats), computed.finalDerived)
        }
    }

    @Test
    fun `钳位：叠加后小于 1 的属性钳到 1，钳位前的原值记在 clamped 里`() {
        val base = mapOf("vigor" to 10, "mind" to 2, "endurance" to 10, "strength" to 10, "dexterity" to 1, "intelligence" to 10, "faith" to 10, "arcane" to 10)
        val applied = HeroStatsMath.apply(listOf(mapOf("mind" to -5, "dexterity" to -1, "vigor" to -9)), base, attributeKeys)
        assertEquals(1, applied.stats["mind"], "2 − 5 = −3 → 钳到 1")
        assertEquals(1, applied.stats["dexterity"], "1 − 1 = 0 → 钳到 1")
        assertEquals(1, applied.stats["vigor"], "10 − 9 = 1 → 正好 1，不算钳位")
        assertEquals(-3, applied.clampedFrom["mind"])
        assertEquals(0, applied.clampedFrom["dexterity"])
        assertFalse("vigor" in applied.clampedFrom)
        assertEquals(listOf("mind", "dexterity"), applied.clamped, "钳位列表按属性展示顺序")
        assertEquals(index.derivedValues(mapOf("mind" to 1))["fp"], index.derivedValues(applied.stats)["fp"])
    }

    @Test
    fun `钳位在真实组合里会发生：利普拉（力气）+ 铁之眼的降灵巧词条`() {
        val mod = assertNotNull(modsOf("ironeye").firstOrNull { (it.level(12)?.delta?.get("dexterity") ?: 0) < 0 })
        val libra = assertNotNull(index.libra("strength"))
        val computed = index.snap("ironeye", 12, listOf(mod.affixId), "strength")
        val baseRow = assertNotNull(libra.level(12))
        assertEquals(baseRow.stats, computed.baseStats, "选了利普拉交易后基础表应整套换成 libraRespecs 的表")
        val raw = baseRow.stats.getValue("dexterity") + assertNotNull(mod.level(12)?.delta?.get("dexterity"))
        assertTrue(raw < 1, "这一组合叠加后确实会小于 1")
        assertEquals(1, computed.finalStats["dexterity"])
        assertEquals(raw, computed.clampedFrom["dexterity"])
        assertEquals(index.derivedValues(computed.finalStats), computed.finalDerived)
    }

    @Test
    fun `利普拉的交易是整套替换：基础表换成 libraRespecs，且与角色原表不同`() {
        index.libraRespecs.forEach { deal ->
            val computed = index.snap("wylder", 15, libraKey = deal.key)
            assertEquals(deal.key, computed.libraKey)
            assertEquals(assertNotNull(deal.level(15)).stats, computed.baseStats)
            assertEquals(index.derivedValues(computed.baseStats), computed.baseDerived)
            assertFalse(computed.hasModifier, "没勾词条时不产生修改后的表")
            assertEquals(computed.baseStats, computed.finalStats)
        }
        val plain = index.snap("wylder", 15)
        val swapped = index.snap("wylder", 15, libraKey = "faith")
        assertNotEquals(plain.baseStats, swapped.baseStats)
        assertEquals(swapped.baseStats, index.snap("recluse", 15, libraKey = "faith").baseStats, "5 套表不分角色")
    }

    @Test
    fun `全部等级表：15 行，锚点标记与数据集 isAnchor 一致，每行派生值可复算`() {
        val rows = index.snapshots("guardian")
        assertEquals(15, rows.size)
        val hero = assertNotNull(index.hero("guardian"))
        rows.forEachIndexed { i, row ->
            val source = hero.levels[i]
            assertEquals(source.level, row.level)
            assertEquals(source.isAnchor, row.isAnchorLevel)
            assertEquals(source.derived, row.baseDerived)
        }
        assertEquals(listOf(1, 2, 12, 15), rows.filter { it.isAnchorLevel }.map { it.level }, "基础表的参数锚点是 1 / 2 / 12 / 15 级")
    }

    @Test
    fun `computeLevel 的兜底：未知角色返回 null，等级越界钳进 1–15`() {
        assertNull(index.snapshot("不存在", 15))
        assertEquals(1, index.clampLevel(0))
        assertEquals(15, index.clampLevel(99))
        assertEquals(7, index.clampLevel(7))
        assertEquals(15, index.clampLevel(null))
        assertEquals(15, index.snap("wylder", index.clampLevel(99)).level)
        val foreign = modsOf("recluse").first().affixId
        assertFalse(index.snap("wylder", 12, listOf(foreign)).hasModifier, "勾了别的角色的词条不会生效")
    }

    @Test
    fun `同级对比：10 行，数值等于各角色本级基础表（不含利普拉与转职遗物）`() {
        val rows = index.comparisonRows(15)
        assertEquals(10, rows.size)
        rows.forEach { row ->
            val hero = assertNotNull(index.hero(row.heroKey))
            val source = assertNotNull(hero.level(15))
            assertEquals(source.stats, row.stats)
            assertEquals(source.derived, row.derived)
            assertEquals(hero.nameZh, row.nameZh)
            assertEquals(hero.nameEn, row.nameEn)
        }
        assertEquals(List(10) { 1 }, index.comparisonRows(1).map { it.level })
    }

    @Test
    fun `同级对比排序：点列头升降序切换，不修改入参，同值按角色原顺序兜底`() {
        val rows = index.comparisonRows(15)
        val snapshot = rows.map { it.heroKey }
        val desc = HeroComparison.sorted(rows, HeroComparisonColumn.Stat("vigor"), false)
        desc.zipWithNext().forEach { (a, b) -> assertTrue(a.stats.getValue("vigor") >= b.stats.getValue("vigor")) }
        val asc = HeroComparison.sorted(rows, HeroComparisonColumn.Stat("vigor"), true)
        assertEquals(asc.map { it.stats.getValue("vigor") }.sorted(), asc.map { it.stats.getValue("vigor") })
        assertEquals(rows.maxOf { it.stats.getValue("vigor") }, desc.first().stats["vigor"])
        assertEquals(desc.map { it.heroKey }, HeroComparison.sorted(rows, HeroComparisonColumn.Derived("hp"), false).map { it.heroKey })
        assertEquals(index.heroes.map { it.key }, HeroComparison.sorted(rows, HeroComparisonColumn.Hero, true).map { it.heroKey })
        assertEquals(snapshot, rows.map { it.heroKey }, "排序不得修改入参")
        assertNull(rows.first().value(HeroComparisonColumn.Stat("不存在的列")))
        assertNull(rows.first().value(HeroComparisonColumn.Hero))
    }

    @Test
    fun `同值时按角色原顺序兜底，排序结果稳定`() {
        val flat = index.comparisonRows(1).map { it.copy(stats = it.stats + ("arcane" to 10)) }
        val sorted = HeroComparison.sorted(flat, HeroComparisonColumn.Stat("arcane"), false)
        assertEquals(flat.map { it.heroId }.sorted(), sorted.map { it.heroId })
    }

    @Test
    fun `文案：属性名取数据集 zh，增减量摘要按属性顺序且带正负号`() {
        val mod = index.modifier(6_640_000)
        assertEquals("生命力 -5、集中力 +10", HeroStatsCopy.deltaSummary(assertNotNull(mod.level(12)).delta, names))
        assertEquals("", HeroStatsCopy.deltaSummary(emptyMap(), names))
        assertEquals("+3", HeroStatsText.signed(3))
        assertEquals("-3", HeroStatsText.signed(-3))
        assertEquals("0", HeroStatsText.signed(0))
        assertEquals(HeroDeltaTone.UP, HeroDeltaTone.of(2))
        assertEquals(HeroDeltaTone.DOWN, HeroDeltaTone.of(-2))
        assertEquals(HeroDeltaTone.FLAT, HeroDeltaTone.of(0))
        assertEquals(HeroDeltaTone.FLAT, HeroDeltaTone.of(0.00001))
        assertEquals(HeroDeltaTone.UP, HeroDeltaTone.of(3.2))
    }

    @Test
    fun `格式化：血量 ／ 专注值 ／ 精力是整数，负重上限保留 1 位小数，缺值显示破折号`() {
        val hp = assertNotNull(names.derivedEntry("hp"))
        val equip = assertNotNull(names.derivedEntry("equipLoad"))
        assertEquals("1280", HeroStatsText.derivedText(1280.0, hp.integer))
        assertEquals("72.0", HeroStatsText.derivedText(72.0, equip.integer))
        assertEquals("46.6", HeroStatsText.derivedText(46.6, equip.integer))
        assertEquals("—", HeroStatsText.derivedText(null, hp.integer))
        assertEquals("52", HeroStatsText.statText(52))
        assertEquals("—", HeroStatsText.statText(null))
    }

    @Test
    fun `数据未内置的判定：占位 JSON ／ 缺 growthGraphs 一律走降级分支`() {
        assertTrue(index.hasHeroData)
        assertFailsWith<GameDataFormatException> { HeroesParser.parse("[]") }
        assertFailsWith<GameDataFormatException> { HeroesParser.parse("""{"placeholder": true}""") }
        val empty = assertFailsWith<GameDataFormatException> { HeroesParser.parse("""{"schemaVersion": 1, "heroes": []}""") }
        assertTrue(empty.message!!.contains("没有任何角色记录"))
        assertTrue(empty.message!!.contains("nightreign-heroes-v1.03.5.json"))
        val noGraphs = HeroesParser.parse("""{"schemaVersion": 1, "heroes": [{"key": "x"}]}""")
        assertFalse(noGraphs.hasHeroData, "缺 growthGraphs 就没法重算派生值")
        assertTrue(HeroesParser.parse("""{"schemaVersion": 1, "growthGraphs": {}, "heroes": [{"key": "x"}]}""").hasHeroData)
        assertFailsWith<GameDataFormatException> { HeroesParser.parse("""{"schemaVersion": 2, "heroes": [{"key": "x"}]}""") }
    }

    @Test
    fun `与 wiki 的差异按 crossChecks 提示：女爵有差异、追踪者没有`() {
        val duchess = assertNotNull(index.crossCheck("duchess"), "女爵的灵巧列与两个 wiki 对不上，页面要提示")
        assertTrue(duchess.mismatchCount > 0)
        assertEquals("params", duchess.authoritative)
        assertTrue(duchess.mismatches.all { it.field == "dexterity" })
        assertNull(index.crossCheck("wylder"))
        assertNull(index.crossCheck("executor"))
        assertNull(index.crossCheckNote("wylder", null))
    }

    @Test
    fun `转职遗物的遗物出处与池信息完整：每条都有 relicItems 与池号`() {
        index.dataset.statModifiers.forEach { mod ->
            assertTrue(mod.relicItems.isNotEmpty(), "${mod.nameZh} 应有携带它的遗物")
            mod.relicItems.forEach { item ->
                assertTrue(item.nameZh.isNotEmpty())
                assertTrue(item.color in 0..3, "颜色下标应落在 红/蓝/黄/绿 之内")
                assertTrue(item.colorZh.isNotEmpty())
            }
            assertTrue(mod.rollablePoolIds.isNotEmpty())
        }
        val dlcOnly = index.dataset.statModifiers.filter { it.dlcOnly }
        assertEquals(index.dataset.counts["dlcOnlyStatModifiers"], dlcOnly.size)
        assertEquals(listOf("scholar", "scholar", "undertaker", "undertaker"), dlcOnly.map { it.heroKey }.sorted())
    }

    @Test
    fun `selectedModifiers 只认本角色的词条，且按传入的 id 过滤`() {
        val mods = modsOf("recluse")
        val picked = index.selectedModifiers("recluse", listOf(mods[0].affixId))
        assertEquals(listOf(mods[0].affixId), picked.map { it.affixId })
        assertEquals(1, index.selectedModifiers("recluse", setOf(mods[1].affixId)).size)
        assertEquals(0, index.selectedModifiers("recluse", emptyList()).size)
        assertEquals(0, index.selectedModifiers("recluse", listOf(modsOf("wylder")[0].affixId)).size)
        assertTrue(index.modifiers("不存在").isEmpty())
    }

    @Test
    fun `数据版本块：5 行标签与「收录」口径按数据集实算`() {
        val rows = index.versionRows()
        assertEquals(HeroStatsCopy.versionLabels, rows.map { it.first })
        assertEquals(index.dataset.gameVersion, rows[0].second)
        assertEquals(index.dataset.dataVersion, rows[1].second)
        assertEquals(index.dataset.generatedAt, rows[2].second)
        assertEquals("schemaVersion 1", rows[3].second)
        assertEquals("10 位渡夜者 × 15 级 · 20 条转职遗物词条 · 5 笔利普拉交易", rows[4].second)
        val bare = HeroDataset().versionRows(15)
        assertEquals("—", bare[0].second)
        assertEquals("—", bare[2].second)
    }

    @Test
    fun `负重上限是遗留列：两张表的列头都带星号注记，且只有它带`() {
        assertEquals(false, names.derivedEntry("equipLoad")?.inGameLabel)
        assertEquals(true, names.derivedEntry("hp")?.inGameLabel)
        assertEquals("负重上限 *", names.derivedHeader("equipLoad"))
        assertEquals("血量", names.derivedHeader("hp"))
        assertTrue(names.hasLegacyDerived)
        assertFalse(HeroStatNames(derived = names.derived.filter { it.inGameLabel }).hasLegacyDerived)
        assertEquals(listOf("equipLoad"), names.legacyDerivedKeys)
    }

    @Test
    fun `选了利普拉后不再报该角色与 wiki 的差异，改写成一句说明`() {
        val duchess = assertNotNull(index.crossCheck("duchess"))
        assertEquals(14, duchess.mismatchCount)
        assertEquals("与外部 wiki 有 14 格差异，本页以参数为准：" + duchess.note, index.crossCheckNote("duchess", null))
        assertEquals(HeroStatsCopy.LIBRA_CROSS_CHECK_NOTE, index.crossCheckNote("duchess", "strength"))
        assertTrue(HeroStatsCopy.LIBRA_CROSS_CHECK_NOTE.contains("整套替换"))
        assertNotEquals(index.snap("duchess", 12).baseStats, index.snap("duchess", 12, libraKey = "strength").baseStats)
        // 不存在的利普拉 key 视为没选
        assertEquals(index.crossCheckNote("duchess", null), index.crossCheckNote("duchess", "不存在"))
    }

    @Test
    fun `全部等级视图的钳位汇总按行聚合：15 行里哪几级被钳都列出来`() {
        val rows = index.snapshots("ironeye", setOf(6_642_000), "strength")
        assertEquals(15, rows.size)
        val clamped = index.clampedByLevel(rows)
        assertTrue(clamped.size > 1)
        val expected = rows.filter { it.clampedFrom.isNotEmpty() }
            .map { HeroClampedLevel(it.level, attributeKeys.filter { key -> key in it.clampedFrom }.map(names::attributeTitle)) }
        assertEquals(expected, clamped)
        clamped.forEach { entry ->
            assertTrue(entry.names.isNotEmpty())
            entry.names.forEach { name -> assertTrue(names.orderedAttributes.any { it.zh == name }) }
        }
        val summary = HeroStatsCopy.clampSummaryByLevel(clamped, index.maxLevel)
        assertTrue(summary.startsWith("1–15 级里有 ${clamped.size} 级叠加后不足 1："))
        clamped.forEach { assertTrue(summary.contains("${it.level} 级 " + it.names.joinToString("、"))) }
        assertTrue(index.clampedByLevel(index.snapshots("ironeye")).isEmpty())
    }

    @Test
    fun `派生值取整：整数段走精确整数除法，与 normalize + floor 逐格一致`() {
        val graphs = index.dataset.growthGraphs
        (1..99).forEach { stat ->
            listOf(100, 101, 104).forEach { id ->
                val graph = assertNotNull(graphs[id])
                assertEquals(kotlin.math.floor(HeroStatsMath.normalize(graph.value(stat))).toInt(), graph.integerValue(stat))
            }
        }
        assertEquals(74.1, HeroStatsMath.round(74.149999, 1))
        assertEquals(74.2, HeroStatsMath.round(74.15, 1))
        assertEquals(-74.2, HeroStatsMath.round(-74.15, 1), "四舍五入应远离零")
        val equip = assertNotNull(graphs[220])
        assertEquals(HeroStatsMath.round(equip.value(27), 1), index.derivedValues(mapOf("endurance" to 27))["equipLoad"])
    }

    @Test
    fun `数据缺失降级：缺 growthGraph ／ 缺来源属性给破折号，不退回 0`() {
        val partial = index.derivedValues(mapOf("vigor" to 20))
        assertEquals(480.0, partial["hp"])
        assertNull(partial["fp"], "缺集中力时专注值应缺省")
        assertEquals("—", HeroStatsText.derivedText(partial["fp"], true))
        val noGraphs = HeroStatsMath.derivedValues(mapOf("vigor" to 20, "mind" to 10), names, emptyMap())
        derivedKeys.forEach { assertNull(noGraphs[it]) }
        assertEquals("0", HeroStatsText.derivedText(0.0, true))
        assertEquals("0", HeroStatsText.statText(0))
        assertEquals("—", HeroStatsText.statText(null))
    }

    @Test
    fun `同级对比：某一级缺行的角色整行丢掉，而不是摆一行 0`() {
        val dataset = index.dataset
        val shrunk = HeroStatsIndex(
            dataset.copy(heroes = listOf(dataset.heroes[0], dataset.heroes[1].copy(levels = dataset.heroes[1].levels.filter { it.level != 10 }))),
        )
        val rows = shrunk.comparisonRows(10)
        assertEquals(1, rows.size, "缺 10 级的角色应从对比表消失")
        assertEquals(dataset.heroes[0].key, rows[0].heroKey)
        assertEquals(2, shrunk.comparisonRows(9).size)
        (1..15).forEach { assertEquals(10, index.comparisonRows(it).size) }
    }

    @Test
    fun `卡片上的增减量是生效值：钳位时大数字写 -8、小字写「词条请求 -9」`() {
        listOf(6_642_000 to -9, 6_642_100 to -13).forEach { (affixId, requested) ->
            val computed = index.snap("ironeye", 15, listOf(affixId), "strength")
            assertEquals(9, computed.baseStats["dexterity"])
            assertEquals(requested, computed.requestedDelta["dexterity"], "请求值仍保留在 requestedDelta 里")
            assertEquals(1, computed.finalStats["dexterity"])
            assertEquals(-8, computed.effectiveDelta("dexterity"), "卡片上显示的一律是生效值")
            assertEquals("词条请求 $requested，已钳到最低 1", HeroStatsCopy.clampRequestedNote(computed.requestedDelta.getValue("dexterity")))
        }
        val plain = index.snap("wylder", 15, listOf(6_640_000))
        attributeKeys.forEach { assertEquals(plain.requestedDelta[it] ?: 0, plain.effectiveDelta(it)) }
        assertNull(index.snap("wylder", 15).effectiveDelta("vigor"), "没勾词条时没有可显示的增减量")
    }

    @Test
    fun `「插值与验证口径」：两端渲染同一组 10 条说明，标题里的 N 就是这 10`() {
        val notes = index.dataset.interpolation.notes
        assertEquals(10, notes.size)
        assertEquals(
            listOf("参数锚点", "基础属性插值", "基础表验证", "派生值换算", "转职遗物插值", "转职遗物锚点验证", "转职遗物中间等级", "取整方向", "兼容字段说明", "利普拉的交易"),
            notes.map { it.title },
        )
        assertEquals(HeroStatsCopy.interpolationNoteTitles, notes.map { it.title })
        assertEquals("基础属性表只有 1 / 2 / 12 / 15 级是参数原值，转职遗物只有 1 / 12 级是参数原值。", notes[0].text)
        assertEquals(index.dataset.interpolation.baseRule, notes[1].text)
        assertEquals(index.dataset.interpolation.baseVerification, notes[2].text)
        assertEquals(index.dataset.interpolation.libraRule, notes[9].text)
        assertTrue(notes[7].text.startsWith("基础属性表按向下取整（floor）"))
        assertTrue(notes[7].text.contains("转职遗物增减量按向零取整（trunc）"))
        assertTrue(notes[7].text.contains("两种取整只在负的增减量上差 1；"))
        assertEquals(listOf("基础属性插值"), HeroInterpolation(baseRule = "x").notes.map { it.title })
        assertTrue(HeroInterpolation().notes.isEmpty())
    }

    @Test
    fun `词条来源三档三色：source → 配色两端钉同一张表`() {
        assertEquals(mapOf(HeroModifierSource.ANCHOR to "green", HeroModifierSource.INFERRED to "amber", HeroModifierSource.CARRIED to "blue"),
            HeroModifierSource.entries.associateWith { it.colorToken })
        assertNotEquals(HeroModifierSource.CARRIED.colorToken, HeroModifierSource.ANCHOR.colorToken)
        assertEquals("green", index.modifierLevelNote(1)?.source?.colorToken)
        assertEquals("amber", index.modifierLevelNote(6)?.source?.colorToken)
        assertEquals("blue", index.modifierLevelNote(15)?.source?.colorToken)
    }

    @Test
    fun `属性缺失同样给破折号：缺项不写成 0，也不编最终值`() {
        val dataset = index.dataset
        val hero = dataset.heroes[0]
        val holed = HeroStatsIndex(
            dataset.copy(
                heroes = listOf(hero.copy(levels = hero.levels.map { it.copy(stats = it.stats - "arcane") })),
                statModifiers = dataset.statModifiers.filter { it.heroKey == hero.key },
            ),
        )
        val mod = holed.modifiers(hero.key).first()
        val computed = holed.snap(hero.key, 12, listOf(mod.affixId))
        assertNull(computed.baseStats["arcane"])
        assertNull(computed.finalStats["arcane"], "没有基础值就不编一个最终值")
        assertNull(computed.effectiveDelta("arcane"))
        assertFalse("arcane" in computed.clampedFrom, "缺项不记钳位")
        assertEquals("—", HeroStatsText.statText(computed.finalStats["arcane"]))
        val rows = holed.snapshots(hero.key, setOf(mod.affixId))
        assertEquals(15, rows.size)
        rows.forEach { assertEquals("—", HeroStatsText.statText(it.baseStats["arcane"])) }
        assertEquals("—", HeroStatsText.statText(holed.comparisonRows(12)[0].stats["arcane"]))
        assertEquals(hero.level(12)?.stats?.get("vigor"), computed.baseStats["vigor"])
    }

    @Test
    fun `growthGraph 可用性两端同一条：三个数组必须等长`() {
        assertTrue(assertNotNull(index.dataset.growthGraphs[100]).isUsable)
        assertFalse(HeroGrowthGraph(1, "", listOf(1.0), listOf(1.0), listOf(1.0)).isUsable, "至少两段")
        assertFalse(HeroGrowthGraph(1, "", listOf(1.0, 10.0), listOf(1.0, 10.0, 20.0), listOf(1.0, 1.0)).isUsable, "ys 比 xs 长也不可用")
        val shortAdj = HeroGrowthGraph(1, "", listOf(1.0, 10.0), listOf(0.0, 90.0), listOf(1.0))
        assertFalse(shortAdj.isUsable, "adjPt 残缺同样不可用")
        assertEquals(0.0, shortAdj.value(5))
        assertEquals(0, shortAdj.integerValue(5))
        assertFalse(HeroGrowthGraph(1, "", listOf(1.0, 10.0), listOf(0.0, 90.0), emptyList()).isUsable, "整个 adjPt 缺失也不可用")
        val derived = HeroStatsMath.derivedValues(mapOf("vigor" to 20, "mind" to 10), names, mapOf(100 to shortAdj))
        derivedKeys.forEach { assertNull(derived[it], "图表不可用时派生值一律缺省（破折号），不编数字") }
    }

    @Test
    fun `宽容解码：未知字段忽略、缺字段退默认值、null 视为没有、等级排序`() {
        val decoded = HeroesParser.parse(
            """
            {
              "schemaVersion": 1,
              "brandNewTopLevelField": {"whatever": true},
              "statNames": {
                "attributeOrder": ["vigor", "mind"],
                "derivedOrder": ["hp"],
                "attributes": [
                  {"key": "vigor", "zh": "生命力", "en": "Vigor", "futureField": 1},
                  {"key": "mind", "zh": "集中力", "en": "Mind"}
                ],
                "derived": [{"key": "hp", "zh": "血量", "en": "HP", "fromStat": "vigor", "graphId": 100, "integer": true, "textId": null}]
              },
              "growthGraphs": {
                "100": {"id": 100, "name": "HP", "stageMaxVal": [1, 25], "stageMaxGrowVal": [100, 580], "adjPt": [1, 1], "linear": true, "usedFor": ["hp"]}
              },
              "heroes": [
                {"id": 1, "key": "wylder", "nameZh": "追踪者", "nameEn": "Wylder", "unknown": [1, 2],
                 "levels": [
                   {"level": 2, "isAnchor": true, "stats": {"vigor": 16, "mind": null}, "derived": {"hp": 400}},
                   {"level": 1, "isAnchor": true, "stats": {"vigor": 8.0, "mind": 4}, "derived": {"hp": 240}}
                 ]}
              ],
              "statModifiers": [
                {"affixId": 6640000, "nameZh": "【追踪者】提升集中力，但降低生命力", "heroKey": "wylder",
                 "affectedStats": ["vigor", "mind"],
                 "levels": [{"level": 1, "isAnchor": true, "delta": {"vigor": -1, "mind": 1}}]}
              ],
              "libraRespecs": [],
              "caveats": null
            }
            """.trimIndent(),
        )
        assertEquals(1, decoded.heroes.size)
        assertEquals(listOf(1, 2), decoded.heroes[0].levels.map { it.level }, "等级应按 level 排序")
        assertEquals(8, decoded.heroes[0].level(1)?.stats?.get("vigor"), "写成浮点的属性取整")
        assertNull(decoded.heroes[0].level(2)?.stats?.get("mind"), "写成 null 的属性视为没有")
        assertEquals("生命力", decoded.statNames.attributeTitle("vigor"))
        assertEquals("nope", decoded.statNames.attributeTitle("nope"), "数据集没有的属性原样回显 key")
        assertEquals(1, decoded.dataset.growthGraphs.size)
        assertTrue(decoded.dataset.libraRespecs.isEmpty())
        assertEquals("", decoded.dataset.gameVersion)
        assertTrue(decoded.dataset.caveats.isEmpty(), "null 的 caveats 退回空数组")
        assertEquals(0, decoded.dataset.interpolation.maxLevel, "缺 interpolation 不该假装声明了最大等级")
        assertTrue(decoded.dataset.interpolation.notes.isEmpty())
        assertEquals(2, decoded.maxLevel, "缺 interpolation 时退回角色表的最大等级")
        assertEquals(listOf(1, 2), decoded.levelRange)
        assertEquals(false, decoded.dataset.statModifiers[0].levels[0].inferred, "缺 inferred 时按「非锚点即推算」补")

        val derived = decoded.derivedValues(mapOf("vigor" to 8, "mind" to 4))
        assertEquals(240.0, derived["hp"])
        assertNull(derived["equipLoad"], "没有 220 行时不应编出负重上限")

        val level1 = decoded.snap("wylder", 1, listOf(6_640_000))
        val level2 = decoded.snap("wylder", 2, listOf(6_640_000))
        assertEquals(7, level1.finalStats["vigor"])
        assertEquals(5, level1.finalStats["mind"])
        assertEquals(level2.baseStats, level2.finalStats, "缺少 2 级 delta 时应保持基础值")
        assertEquals(1, level2.activeModifiers.size, "词条仍算生效（只是没有该级数据）")
        assertNull(level2.modifierSource, "数据集没给锚点信息时不标来源")

        val broken = HeroGrowthGraph(1, "broken", listOf(1.0), emptyList(), emptyList())
        assertFalse(broken.isUsable)
        assertTrue(broken.value(10) == 0.0 && broken.integerValue(10) == 0)
    }
}
