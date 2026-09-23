package com.nightreign.relicchecker.gamedata.ranker

import com.nightreign.relicchecker.gamedata.ranker.RankerTestData.assertClose
import com.nightreign.relicchecker.gamedata.ranker.RankerTestData.shares
import com.nightreign.relicchecker.gamedata.ranker.RankerTestData.synthBuff
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

// 合成数据的精确口径（macOS 端 BuffRankerChecks.checkLoadoutSynthetic 的同一组断言）：去重的取舍顺序与原因文案、
// 提示的顺序与文案、stackSelf 多份、不同档位、叠层换算与越界提示、条件型护符、作用对象、切模式削减、推荐填满。
// 构成一律是「一半斩击、一半火」，期望值都能手算。
class LoadoutSyntheticTest {
    private val half = shares(DamageType.SLASH to 0.5, DamageType.FIRE to 0.5)

    private fun buff(
        id: Int,
        name: String,
        rates: Map<String, Double> = mapOf("physicsAttackRate" to 1.2),
        slot: String = "consumable",
        key: String = "sp10#$id",
        behavior: String = "stackSelf",
        priority: Int = 0,
        transform: (BuffEntry) -> BuffEntry = { it },
    ): BuffEntry = synthBuff(id) {
        transform(
            it.copy(
                displayNameZh = name,
                rates = rates,
                sourceSlot = slot,
                stacking = BuffStacking(spCategory = 10, spCategoryBehavior = behavior, categoryPriority = priority, exclusiveKey = key),
            ),
        )
    }

    private val buffs = listOf(
        // 同键：有效倍率高的留下。
        buff(905, "同键低", key = "sp1000", behavior = "none"),
        buff(906, "同键高", mapOf("physicsAttackRate" to 1.4), key = "sp1000", behavior = "none"),
        // applyHighest：categoryPriority 小的留下（哪怕倍率低）。
        buff(920, "优先度2", mapOf("physicsAttackRate" to 1.3), key = "sp1001", behavior = "applyHighest", priority = 2),
        buff(921, "优先度1", mapOf("physicsAttackRate" to 1.1), key = "sp1001", behavior = "applyHighest", priority = 1),
        // 局内武器词条：同一词条两档（行名去掉「 - Potency N」相同）、深夜专属、只给短剑的。
        buff(901, "提升物理1", mapOf("physicsAttackRate" to 1.1), slot = "weaponAffix") { it.copy(paramName = "[Weapon] 提升物理 - Potency 1") },
        buff(902, "提升物理2", mapOf("physicsAttackRate" to 1.2), slot = "weaponAffix") { it.copy(paramName = "[Weapon] 提升物理 - Potency 2") },
        buff(903, "深夜物理", mapOf("physicsAttackRate" to 1.3), slot = "weaponAffix") { it.copy(weaponAffixDeepOnlyPositive = true) },
        buff(904, "诅咒", mapOf("physicsAttackRate" to 1.5), slot = "weaponAffix"),
        buff(907, "短剑物理", mapOf("physicsAttackRate" to 1.15), slot = "weaponAffix"),
        // 叠层：阶梯（参数表 3 层、一局实际 2 层）与份数（每份 ×1.02）。
        buff(911, "阶梯叠层", mapOf("physicsAttackRate" to 1.05, "fireAttackRate" to 1.05), slot = "runStack") {
            it.copy(
                activation = "conditional",
                stackInput = BuffStackInput(
                    mode = "ladder", paramMaxStacks = 3, practicalMaxStacks = 2, practicalMaxSource = "实测：合成",
                    multiplierKey = "physicsAttackRate", appliesToRateKeys = listOf("physicsAttackRate", "fireAttackRate"),
                    tierMultipliers = listOf(1.05, 1.1025, 1.157625), perStackRatio = 1.05,
                ),
            )
        },
        buff(912, "份数叠层", mapOf("physicsAttackRate" to 1.02), slot = "runStack") {
            it.copy(
                activation = "conditional",
                stackInput = BuffStackInput(
                    mode = "copies", multiplierKey = "physicsAttackRate", appliesToRateKeys = listOf("physicsAttackRate"),
                    perStackMultiplier = 1.02, uiLabelMax = 10,
                ),
            )
        },
        // 条件型护符。
        buff(913, "条件护符效果", mapOf("physicsAttackRate" to 1.3), slot = "accessory") {
            it.copy(activation = "conditional", sources = listOf(BuffSourceRef(kind = "accessory", id = 5000, nameZh = "条件护符")))
        },
        // 只加火（对纯斩击构成 ×1）；作用于敌人（不进任何栏）。
        buff(914, "只加火", mapOf("fireAttackRate" to 1.2)),
        buff(915, "敌人身上", mapOf("physicsAttackRate" to 1.2)) { it.copy(target = "enemy") },
        // 作用对象：selfAllyPair 的 Allies 那一行不算施放者自己；普通 ally 照常。
        buff(928, "队友那一行", mapOf("physicsAttackRate" to 1.1)) { it.copy(target = "ally", selfAllyPair = BuffSelfAllyPair("ally", 929)) },
        buff(929, "自己那一行", mapOf("physicsAttackRate" to 1.1)) { it.copy(selfAllyPair = BuffSelfAllyPair("self", 928)) },
        buff(930, "队友增益", mapOf("fireAttackRate" to 1.1)) { it.copy(target = "ally") },
    )

    private val weaponAffixes = listOf(
        BuffWeaponAffixInfo(9001, "提升物理1", paramName = "X - Potency 1", roles = listOf("affix"), normalWepTypes = listOf(9), spEffectIds = listOf(901)),
        BuffWeaponAffixInfo(9002, "提升物理2", paramName = "X - Potency 2", roles = listOf("affix"), normalWepTypes = listOf(9, 1), spEffectIds = listOf(902)),
        BuffWeaponAffixInfo(9003, "深夜物理", roles = listOf("affix"), deepWepTypes = listOf(9), deepOnly = true, deepOnlyPositive = true, spEffectIds = listOf(903)),
        BuffWeaponAffixInfo(9004, "诅咒", roles = listOf("curse"), deepWepTypes = listOf(9), deepOnly = true, spEffectIds = listOf(904)),
        BuffWeaponAffixInfo(9005, "短剑物理", roles = listOf("affix"), normalWepTypes = listOf(1), spEffectIds = listOf(907)),
    )

    private val index: LoadoutIndex by lazy {
        LoadoutIndex(RankerTestData.miniIndex(buffs, weaponAffixes = weaponAffixes), emptyList())
    }

    private val evaluator: LoadoutEvaluator by lazy {
        index.evaluator(RankerOutput(OutputClass.SKILL, meansId = 77, weaponWepType = 9, shares = half))
    }

    private fun state(result: LoadoutEvaluation, id: Int): EntryState? = result.items.firstOrNull { it.id == id }?.state

    @Test
    fun `exclusive key keeps the higher multiplier, applyHighest keeps the smaller categoryPriority, with the desktop wording`() {
        val result = evaluator.evaluate(LoadoutConfig(others = setOf(905, 906, 920, 921)))
        assertEquals(EntryState.COUNTED, state(result, 906))
        assertEquals(EntryState.DUPLICATE, state(result, 905))
        assertEquals(EntryState.COUNTED, state(result, 921))
        assertEquals(EntryState.DUPLICATE, state(result, 920))
        assertEquals(listOf(RankerText.f("reasonDupKey", "同键高", "sp1000")), result.items.first { it.id == 905 }.reasons)
        assertEquals(listOf(RankerText.f("reasonDupPriority", "优先度1", "sp1001", 1, 2)), result.items.first { it.id == 920 }.reasons)
        assertEquals(listOf("duplicate", "priority"), result.warnings.map { it.kind })
        assertEquals(RankerText.f("warnDuplicateKey", "sp1000", 2, "同键高、同键低"), result.warnings[0].text)
        assertEquals(RankerText.f("warnPriority", "sp1001", "优先度1", "优先度2"), result.warnings[1].text)
        assertClose(0.5 * 1.4 * 1.1 + 0.5, result.totalMultiplier, 1e-12, "去重后逐类型连乘再加权")
        assertEquals(listOf(906, 921), result.counted.map { it.id }, "按互斥键第一次出现的顺序")
        assertEquals(906, result.duplicateWinner(result.items.first { it.id == 905 })?.id)
        // 同倍率同加算：取 spEffectId 小的。
        val tie = LoadoutEvaluator.dedupeItems(
            listOf(906, 905).map { id ->
                val entry = index.ranker.byId.getValue(id)
                evaluator.evaluateEntry(entry, LoadoutConfig(), source = EvalSource(autoConfirm = true))
                    .copy(table = List(DamageType.COUNT) { 1.2 }, multiplier = 1.2)
            },
        )
        assertEquals(listOf(905), tie.winners.map { it.id })
    }

    @Test
    fun `stackSelf copies multiply with a note and a warning, different tiers multiply with the family warning`() {
        var result = evaluator.evaluate(LoadoutConfig(weaponAffixes = mapOf(9001 to 2)))
        assertClose(0.5 * 1.1 * 1.1 + 0.5, result.totalMultiplier, 1e-12, "stackSelf 两份相乘")
        assertEquals(listOf("copiesStackSelf"), result.warnings.map { it.kind })
        assertEquals(RankerText.f("warnCopiesStackSelf", "提升物理1 ×2"), result.warnings[0].text)
        assertEquals(2, result.counted.single().countedCopies)
        assertEquals(listOf(RankerText.f("noteCopiesStackSelf", 2)), result.counted.single().notes)
        result = evaluator.evaluate(LoadoutConfig(weaponAffixes = mapOf(9001 to 1, 9002 to 1)))
        assertClose(0.5 * 1.1 * 1.2 + 0.5, result.totalMultiplier, 1e-12, "同一词条的不同档位按独立键相乘")
        assertTrue(result.warnings.any { it.kind == "tiers" && it.text.contains("参数推断，未实测") }, result.warnings.toString())
        assertEquals(listOf(listOf(9001, 9002)), index.selectedTierFamilies(LoadoutConfig(weaponAffixes = mapOf(9001 to 1, 9002 to 1))))
        // 不是 stackSelf 的（none）多份只算一份并提示。
        val single = index.ranker.byId.getValue(905)
        val once = evaluator.evaluateEntry(single, LoadoutConfig(), source = EvalSource(copies = 3, autoConfirm = true))
        assertEquals(1, once.countedCopies)
        assertEquals(listOf(RankerText.f("noteCopiesSingle", 3)), once.notes)
    }

    @Test
    fun `stack inputs default to zero, ladders take tierMultipliers, copies take perStack power, overflow is clamped with notes`() {
        var config = LoadoutConfig(others = setOf(911, 912))
        var result = evaluator.evaluate(config)
        assertTrue(result.items.all { it.state == EntryState.ZERO_STACKS }, "层数缺省 0，不计入")
        config = config.copy(stackCounts = mapOf(911 to 2, 912 to 5))
        result = evaluator.evaluate(config)
        assertClose(0.5 * 1.1025 * Math.pow(1.02, 5.0) + 0.5 * 1.1025, result.totalMultiplier, 1e-12, "阶梯第 2 层（物理+火），份数 5 份（只乘物理）")
        config = config.copy(stackCounts = mapOf(911 to 9))
        val ladder = evaluator.evaluate(config).items.first { it.id == 911 }
        assertEquals(3, ladder.stacks, "阶梯层数夹到参数表层数 3")
        assertEquals(listOf(RankerText.f("stackOverPractical", 3, 2, "实测"), RankerText.f("stackOverParam", 3)), ladder.notes)
        assertEquals(2, index.ranker.byId.getValue(911).stackInput!!.defaultStacks)
        assertEquals(1, index.ranker.byId.getValue(912).stackInput!!.defaultStacks)
        // 勾选时预填：一局实际上限，没有就 1。
        val ticked = evaluator.toggleOtherRow(evaluator.toggleOtherRow(LoadoutConfig(), 911, true), 912, true)
        assertEquals(mapOf(911 to 2, 912 to 1), ticked.stackCounts)
        // 份数型超过『＋N』标签数时提示外推。
        val many = evaluator.evaluate(LoadoutConfig(others = setOf(912), stackCounts = mapOf(912 to 12))).items.first { it.id == 912 }
        assertEquals(listOf(RankerText.f("stackOverLabel", 10)), many.stackWarnings)
        assertEquals(listOf(RankerText.t("badges.conditional"), RankerText.t("badges.ladder")), LoadoutText.entryBadges(index.ranker.byId.getValue(911)))
    }

    @Test
    fun `a conditional talisman is not counted until ticked and is never recommended`() {
        val config = LoadoutConfig(accessories = listOf(5000, null))
        var result = evaluator.evaluate(config)
        val line = result.items.single()
        assertEquals(EntryState.PENDING, line.state)
        assertEquals(listOf(RankerText.t("activationNeed.conditional")), line.needs)
        assertEquals(listOf("acc:0"), line.keys)
        result = evaluator.evaluate(config.withTick(913, true))
        assertClose(0.5 * 1.3 + 0.5, result.totalMultiplier, 1e-12, "勾「条件成立」后计入")
        val filled = evaluator.recommendFill(LoadoutConfig(), 9).config
        assertEquals(listOf(null, null), filled.accessories, "条件型护符不推荐")
        assertEquals(1, index.talismans.size)
        assertEquals("条件护符", index.talismans.single().nameZh)
    }

    @Test
    fun `targets - enemy entries are not listed, the Allies half of a self-ally pair is not counted, plain ally is`() {
        assertFalse(index.otherRows.values.flatten().any { row -> row.entries.any { it.id == 915 } }, "target = enemy 的条目不该进任何栏")
        val result = evaluator.evaluate(LoadoutConfig(others = setOf(928, 929, 930)))
        assertEquals(EntryState.NO, state(result, 928))
        assertEquals(listOf(RankerText.t("reasonAllyPair")), result.items.first { it.id == 928 }.reasons)
        assertEquals(EntryState.COUNTED, state(result, 929))
        assertEquals(EntryState.COUNTED, state(result, 930))
        assertTrue(LoadoutText.entryBadges(index.ranker.byId.getValue(928)).contains(RankerText.t("badges.allyPair")))
        assertTrue(LoadoutText.entryBadges(index.ranker.byId.getValue(930)).contains(RankerText.t("badges.ally")))
        // 只加火的条目对纯斩击构成没有增益（×1），状态是 neutral。
        val slashOnly = index.evaluator(RankerOutput(OutputClass.SKILL, meansId = 77, weaponWepType = 9, shares = shares(DamageType.SLASH to 1.0)))
        val neutral = slashOnly.evaluate(LoadoutConfig(others = setOf(914))).items.single()
        assertEquals(EntryState.NEUTRAL, neutral.state)
        assertEquals(listOf(RankerText.t("reasonNeutral")), neutral.reasons)
    }

    @Test
    fun `weapon affix slots - normal hides deep-only and curses, filters by weapon type, deep fill stops at 12 with 6 deep-only`() {
        assertNull(index.weaponAffixById[9004], "诅咒不进正面词条栏")
        val normalRows = evaluator.weaponAffixRows(LoadoutConfig(), null).map { it.affix.id }.toSet()
        assertEquals(setOf(9001, 9002, 9005), normalRows, "常规模式不列深夜专属词条与诅咒")
        assertFalse(evaluator.weaponAffixRows(LoadoutConfig(), 9).any { it.affix.id == 9005 }, "按当前武器类别（刀）过滤掉只给短剑的词条")
        assertTrue(evaluator.weaponAffixRows(LoadoutConfig(weaponAffixes = mapOf(9005 to 1)), 9).any { it.affix.id == 9005 && it.outsideFilter })

        val deep = evaluator.recommendFill(LoadoutConfig(runMode = RunMode.DEEP), null)
        val deepEval = evaluator.evaluate(deep.config)
        assertEquals(12, deepEval.slots.weaponAffix.used, "深夜推荐填满应正好填到 12 条")
        assertEquals(6, deepEval.slots.weaponAffix.deepOnlyUsed, "深夜专属正面词条被上限卡在 6 条")
        assertEquals(mapOf(9003 to 6, 9002 to 6), deep.config.weaponAffixes)
        assertEquals(12, deep.added.count { it.column == SummaryColumn.WEAPON_AFFIX })
        assertTrue(deepEval.violations.isEmpty())

        val normalFilled = evaluator.recommendFill(LoadoutConfig(), 9)
        assertEquals(mapOf(9002 to 6), normalFilled.config.weaponAffixes, "同一词条多份（stackSelf 各份相乘）：取 ×1.2 那条填满 6 份")
        assertEquals(normalFilled.config, evaluator.recommendFill(normalFilled.config, 9).config, "填满后再点一次不应再变")
        assertTrue(evaluator.evaluate(normalFilled.config).counted.all { it.entry.activation == "passive" }, "推荐填满只挑被动")

        var over = LoadoutConfig(runMode = RunMode.DEEP, weaponAffixes = mapOf(9003 to 7, 9001 to 6))
        val overEval = evaluator.evaluate(over)
        assertTrue(overEval.slots.weaponAffix.isOver && overEval.slots.weaponAffix.isDeepOnlyOver)
        assertEquals(
            listOf(RankerText.f("violationWeaponAffix", 13, "深夜", 12), RankerText.f("violationDeepOnly", 7, 6)),
            overEval.violations,
        )
        val back = index.applyRunMode(over, RunMode.NORMAL)
        assertEquals(mapOf(9001 to 6), back.weaponAffixes)
        assertEquals(7, index.trimmedCount(over, back))
        over = over.copy(weaponAffixes = mapOf(9003 to 1))
        assertEquals(RankerText.t("waDeepOnlyCapReached"), index.canAddWeaponAffix(over.copy(weaponAffixes = mapOf(9003 to 6)), 9003).reason)
        assertTrue(index.canAddWeaponAffix(over, 9003).ok)
    }

    @Test
    fun `sources are expanded in the desktop order and merged by spEffectId`() {
        val config = LoadoutConfig(
            weaponAffixes = mapOf(9002 to 1, 9001 to 2),
            accessories = listOf(null, 5000),
            others = setOf(930, 929),
        )
        val collected = evaluator.collectSources(config)
        assertEquals(listOf("wa:9001", "wa:9002", "acc:1", "other:929", "other:930"), collected.sources.map { it.key })
        assertEquals(listOf("提升物理1 ×2", "提升物理2"), collected.sources.take(2).map { it.label })
        assertEquals(RankerText.t("otherGroups.consumable"), collected.sources.last().label)
        assertTrue(collected.sources.filter { it.key.startsWith("other:") }.all { it.autoConfirm })
        assertEquals(3, collected.relicChecks.size)
        assertTrue(collected.relicChecks.all { it.status == RelicCheckStatus.EMPTY })
        val merged = LoadoutEvaluator.mergeSources(collected.sources + collected.sources.first())
        assertEquals(5, merged.size)
        assertEquals(4, merged.first().copies, "同一 spEffectId 份数相加")
        assertEquals(listOf("wa:9001"), merged.first().keys)
        // 按来源键移除。
        assertEquals(mapOf(9001 to 1, 9002 to 1), index.removeSource(config, "wa:9001").weaponAffixes)
        assertEquals(listOf(null, null), index.removeSource(config, "acc:1").accessories)
        assertEquals(setOf(930), index.removeSource(config, "other:929").others)
        assertEquals(config, index.removeSource(config, "bogus"))
    }
}
