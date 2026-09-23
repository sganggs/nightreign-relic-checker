package com.nightreign.relicchecker.gamedata.ranker

import com.nightreign.relicchecker.gamedata.ranker.RankerTestData.assertClose
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertTrue

// 配置引擎的三端对拍（windows/tests/ranker_crosscheck.test.mjs 的「三组配置对照」与文末摘要）：
//   ① 逐字段比对 Windows 端打印的 CONFIG 行（test resources 的 ranker-crosscheck-dump.txt）：模式、总倍率、
//      四栏小计（容差 1e-6）、配置本身（武器词条 / 遗物 / 护符）与计入条目集合（含份数，逐字相同）；
//   ② 与两端一样，再用一份**独立重算的参考实现**（ConfigReference，不复用被测代码的分支）校对总倍率、
//      各栏小计与计入条目集合（容差 1e-9）；
//   ③ 口径细节：槽位不越界、遗物合法、同键不重复、推荐确定性、只选被动；C 组的逐条状态；
//   ④ TEXT 行：说明区（口径说明）的摘要 brief=ad04314d，与条数、诅咒池、子类别这些现算的数字。
class LoadoutCrossCheckTest {
    private val skills get() = RankerTestData.skills
    private val index get() = RankerTestData.loadout
    private val dataset get() = RankerTestData.buffs.dataset

    private val runs: Map<String, RankerCrossCheck.ConfigRun> by lazy {
        RankerCrossCheck.CONFIG_CASES.associate { it.key to RankerCrossCheck.runConfig(skills, index, it) }
    }

    private val dumpLines: List<String> by lazy {
        RankerTestData.readText("ranker-crosscheck-dump.txt").lines().map { it.trimEnd() }
            .filter { it.isNotEmpty() && !it.startsWith("#") }
    }

    private data class DumpConfig(
        val key: String,
        val mode: String,
        val total: Double,
        val sub: Map<String, Double>,
        val weaponAffixes: String,
        val relics: String,
        val accessories: String,
        val counted: String,
    )

    private fun field(line: String, name: String): String {
        val token = line.split(' ').firstOrNull { it.startsWith("$name=") }
        return assertNotNull(token, "对拍行缺少 $name=：$line").substringAfter('=')
    }

    private fun parseConfig(line: String): DumpConfig = DumpConfig(
        key = line.split(' ')[1],
        mode = field(line, "mode"),
        total = field(line, "total").toDouble(),
        sub = field(line, "sub").split(',').associate { part ->
            val (column, value) = part.split(':')
            column to value.toDouble()
        },
        weaponAffixes = field(line, "weaponAffixes"),
        relics = field(line, "relics"),
        accessories = field(line, "accessories"),
        counted = field(line, "counted"),
    )

    // ------------------------------------------------------------------ ① CONFIG 行

    @Test
    fun `every CONFIG line of the desktop dump matches field by field`() {
        val expectedLines = dumpLines.filter { it.startsWith("CONFIG ") }
        assertEquals(RankerCrossCheck.CONFIG_CASES.map { it.key }, expectedLines.map { it.split(' ')[1] }, "三组配置、同一顺序")
        for (line in expectedLines) {
            val expected = parseConfig(line)
            val run = runs.getValue(expected.key)
            val actual = parseConfig(run.dumpLine)
            assertEquals(expected.mode, actual.mode, "${expected.key}：模式")
            assertClose(expected.total, run.result.totalMultiplier, 1e-6, "${expected.key}：总倍率")
            assertEquals(SummaryColumn.entries.map { it.key }, expected.sub.keys.toList(), "四栏同序")
            SummaryColumn.entries.forEach { column ->
                assertClose(expected.sub.getValue(column.key), run.result.column(column).multiplier, 1e-6, "${expected.key}：${column.key} 小计")
            }
            assertEquals(expected.weaponAffixes, actual.weaponAffixes, "${expected.key}：武器词条")
            assertEquals(expected.relics, actual.relics, "${expected.key}：遗物")
            assertEquals(expected.accessories, actual.accessories, "${expected.key}：护符")
            assertEquals(expected.counted, actual.counted, "${expected.key}：计入条目集合（含份数）")
        }
        // 本版本数据下三行逐字相同（比逐字段 1e-6 更严；数据集修订后以上面的逐字段比对为准）。
        assertEquals(expectedLines, RankerCrossCheck.CONFIG_CASES.map { runs.getValue(it.key).dumpLine })
    }

    @Test
    fun `the three CONFIG cases pin the documented facts`() {
        val a = runs.getValue("corpse-piler-normal-fill")
        assertClose(6.073732827, a.result.totalMultiplier, 1e-6, "A 总倍率")
        assertEquals(mapOf(8350002 to 6), a.config.weaponAffixes, "A：提升战技攻击力（档位3）×6")
        assertEquals(listOf("2070", "2071", "2051"), a.config.relics.take(3).map { it.fixedKey }, "A：三件固定遗物")
        assertEquals(listOf(1230, 2020), a.config.accessories)
        val b = runs.getValue("death-lightning-deep-fill")
        assertClose(16.658968943, b.result.totalMultiplier, 1e-6, "B 总倍率")
        assertEquals(mapOf(8100302 to 12), b.config.weaponAffixes, "B：深夜 12 条")
        assertEquals(6, b.result.caps.relics)
        val c = runs.getValue("lions-claw-2fixed-1custom-2talismans-evergaol7")
        assertClose(2.169951652, c.result.totalMultiplier, 1e-6, "C 总倍率")
        assertClose(1.886914480, c.result.column(SummaryColumn.RELIC).multiplier, 1e-6, "C 遗物小计")
        assertClose(1.15, c.result.column(SummaryColumn.ACCESSORY).multiplier, 1e-6, "C 护符小计（战士壶碎片）")
    }

    // ------------------------------------------------------------------ ② 独立参考实现

    /**
     * 独立重算（故意不复用被测代码的分支）：Windows ranker_crosscheck.test.mjs 的 referenceConfig。从配置展开
     * spEffectId（同一 ID 合并份数），按 多档只留选中的一档 / 作用对象 / appliesTo / 累积阶梯选层 / 叠层层数 /
     * 确认 过滤，份数按 stackSelf 且按 ID 互斥的相乘，×1 且没有正加算的不算，按 exclusiveKey 去重，逐类型连乘后加权。
     */
    private class ConfigReference(private val dataset: BuffDataset) {
        private val fields = dataset.rateFields.associateBy { it.key }
        private val byId = dataset.buffs.associateBy { it.spEffectId }
        private val phys = listOf(DamageType.SLASH, DamageType.BLOW, DamageType.THRUST, DamageType.NEUTRAL, DamageType.PHYS_NONE)
        private val fieldChannels: Map<String, List<DamageType>> = buildMap {
            listOf("Rate", "PowerRate").forEach { tail ->
                put("physicsAttack$tail", phys)
                put("magicAttack$tail", listOf(DamageType.MAGIC))
                put("fireAttack$tail", listOf(DamageType.FIRE))
                put("thunderAttack$tail", listOf(DamageType.LIGHTNING))
                put("darkAttack$tail", listOf(DamageType.HOLY))
                put("slashAttack$tail", listOf(DamageType.SLASH))
                put("blowAttack$tail", listOf(DamageType.BLOW))
                put("thrustAttack$tail", listOf(DamageType.THRUST))
                put("neutralAttack$tail", listOf(DamageType.NEUTRAL))
            }
        }
        private val flatChannels: Map<String, List<DamageType>> = mapOf(
            "physicsAttackPower" to phys, "magicAttackPower" to listOf(DamageType.MAGIC),
            "fireAttackPower" to listOf(DamageType.FIRE), "thunderAttackPower" to listOf(DamageType.LIGHTNING),
            "darkAttackPower" to listOf(DamageType.HOLY),
        )

        fun listable(buff: BuffEntry): Boolean {
            val counts = buff.rates.any { (key, value) ->
                val field = fields[key]
                field != null && field.countsAsDamage && value != field.default
            }
            return counts && (buff.target == "self" || buff.target == "ally") && buff.direction != "decrease"
        }

        class Verdict(val weight: Double, val manual: Boolean, val restricted: DamageType?)

        fun verdict(buff: BuffEntry, out: RankerOutput): Verdict? {
            val cls = out.outputClass
            val value = buff.appliesTo?.get(cls)
            if (value != "yes" && value != "conditional") return null
            var manual = buff.requiresGoodsIds.isNotEmpty()
            if (value == "yes") return Verdict(1.0, manual, null)
            val requires = buff.appliesToDetail[cls]?.requires ?: return Verdict(1.0, true, null)
            var weight = 1.0
            var restricted: DamageType? = null
            var any = false
            requires.hand?.let {
                any = true
                if (it != out.hand) return null
            }
            if (requires.attackWeaponTypes.isNotEmpty()) {
                any = true
                val own = when (cls) {
                    OutputClass.SKILL -> out.weaponWepType
                    OutputClass.SORCERY -> 57
                    OutputClass.INCANTATION -> 61
                }
                if (own == null || own !in requires.attackWeaponTypes) return null
            }
            if (requires.subCategoriesAny.isNotEmpty()) {
                any = true
                val table = if (cls == OutputClass.SKILL) dataset.attackIndex.skills else dataset.attackIndex.spells
                val sets = out.meansId?.let { table[it] }
                if (sets.isNullOrEmpty()) {
                    manual = true
                } else {
                    var matched = 0
                    var total = 0
                    sets.forEach { set ->
                        total += set.hits
                        if (set.subs.any { it in requires.subCategoriesAny }) matched += set.hits
                    }
                    if (matched == 0) return null
                    weight = matched.toDouble() / total
                }
            }
            if (requires.attackContexts.isNotEmpty()) {
                any = true
                if (requires.attackContexts.none { it in out.attackContexts }) return null
            }
            requires.physicalType?.let { code ->
                any = true
                val type = listOf(DamageType.SLASH, DamageType.BLOW, DamageType.THRUST, DamageType.NEUTRAL)[code]
                restricted = type
                if (!(out.share(type) > 0.0)) return null
            }
            if (requires.imbuedWeaponOnly || requires.attachedWeaponOnly || requires.unknownKeys.isNotEmpty()) {
                any = true
                manual = true
            }
            if (!any) manual = true
            return Verdict(weight, manual, restricted)
        }

        private fun paramMax(input: BuffStackInput): Int {
            if (input.mode != "ladder") return 99
            val tiers = input.tierMultipliers.size
            val param = input.paramMaxStacks ?: 0
            return if (param > 0) (if (tiers > 0) minOf(param, tiers) else param) else maxOf(tiers, 1)
        }

        private fun tables(buff: BuffEntry, verdict: Verdict, stacks: Int?, copies: Int): Pair<DoubleArray, DoubleArray> {
            val table = DoubleArray(DamageType.COUNT) { 1.0 }
            val flat = DoubleArray(DamageType.COUNT)
            var rates = buff.rates
            val input = buff.stackInput
            if (input != null && stacks != null) {
                val value = if (input.mode == "ladder") {
                    input.tierMultipliers[minOf(stacks, input.tierMultipliers.size) - 1]
                } else {
                    Math.pow(input.perStackMultiplier!!, stacks.toDouble())
                }
                rates = rates + input.appliesToRateKeys.ifEmpty { listOf(input.multiplierKey) }.associateWith { value }
            }
            for ((key, value) in rates) {
                val field = fields[key] ?: continue
                if (!field.countsAsDamage || !value.isFinite() || value == field.default) continue
                if (field.valueKind == "multiplier" && value > 0) {
                    fieldChannels[key]?.forEach { channel ->
                        if (verdict.restricted == null || channel == verdict.restricted) table[channel.ordinal] *= value
                    }
                } else if (field.valueKind == "flat") {
                    flatChannels[key]?.forEach { flat[it.ordinal] += value }
                }
            }
            for (i in table.indices) {
                if (verdict.weight < 1) {
                    table[i] = 1 + (table[i] - 1) * verdict.weight
                    flat[i] *= verdict.weight
                }
                if (copies > 1) {
                    table[i] = Math.pow(table[i], copies.toDouble())
                    flat[i] *= copies
                }
            }
            return table to flat
        }

        private fun weighted(table: DoubleArray, out: RankerOutput): Double {
            var sum = 0.0
            var weight = 0.0
            DamageType.entries.forEach { type ->
                val share = out.share(type)
                if (share > 0) {
                    sum += share * table[type.ordinal]
                    weight += share
                }
            }
            return if (weight > 0) sum / weight else 1.0
        }

        private class Candidate(
            val id: Int, val key: String, val value: Double, val flat: Double, val table: DoubleArray,
            val column: SummaryColumn, val copies: Int, val highest: Boolean, val priority: Int,
        )

        class Result(val total: Double, val subtotals: Map<SummaryColumn, Double>, val ids: List<String>)

        fun config(config: LoadoutConfig, out: RankerOutput, weapon: SkillWeapon?): Result {
            val deep = config.runMode == RunMode.DEEP
            val rules = dataset.slotRules!!
            val relicSlots = if (deep) rules.modes.deep.relicSlots else rules.modes.normal.relicSlots
            data class Source(val id: Int, val copies: Int, val column: SummaryColumn)
            val sources = ArrayList<Source>()
            config.weaponAffixes.entries.sortedBy { it.key }.forEach { (id, count) ->
                val raw = dataset.weaponAffixes.first { it.attachEffectId == id }
                raw.spEffectIds.filter { byId[it]?.let(::listable) == true }.forEach { sources += Source(it, count, SummaryColumn.WEAPON_AFFIX) }
            }
            config.relics.take(relicSlots).forEach { card ->
                when (card.type) {
                    RelicCardType.FIXED -> {
                        val relic = dataset.fixedRelics.first { it.relicIds.joinToString("-") == card.fixedKey }
                        relic.spEffectIds.filter { byId[it]?.let(::listable) == true }.forEach { sources += Source(it, 1, SummaryColumn.RELIC) }
                    }
                    RelicCardType.CUSTOM -> card.affixIds.filterNotNull().forEach { affixId ->
                        dataset.buffs.filter { buff -> listable(buff) && buff.relicAffixes.any { it.catalogEffectId == affixId } }
                            .forEach { sources += Source(it.spEffectId, 1, SummaryColumn.RELIC) }
                    }
                    RelicCardType.EMPTY -> Unit
                }
            }
            config.accessories.filterNotNull().forEach { talismanId ->
                dataset.buffs.filter { buff ->
                    listable(buff) && buff.sourceSlot == "accessory" &&
                        buff.sources.any { it.kind == "accessory" && it.id == talismanId }
                }.forEach { sources += Source(it.spEffectId, 1, SummaryColumn.ACCESSORY) }
            }
            if (out.outputClass == OutputClass.SKILL && weapon != null) {
                dataset.buffs.filter { listable(it) && it.weaponInnate?.weaponIds?.contains(weapon.id) == true }
                    .forEach { sources += Source(it.spEffectId, 1, SummaryColumn.OTHER) }
            }
            val merged = LinkedHashMap<Int, Source>()
            sources.forEach { source ->
                val one = merged[source.id]
                merged[source.id] = if (one == null) source else one.copy(copies = one.copies + source.copies)
            }
            fun variantPick(buff: BuffEntry): Int {
                val variant = buff.affixVariant!!
                val key = variant.key.ifEmpty { "affix#${variant.attachEffectId}" }
                config.variants[key]?.let { return it }
                return dataset.buffs.first { other ->
                    val own = other.affixVariant
                    own != null && own.key.ifEmpty { "affix#${own.attachEffectId}" } == key && own.variant == 1
                }.spEffectId
            }
            val candidates = ArrayList<Candidate>()
            for (one in merged.values) {
                val buff = byId.getValue(one.id)
                if (buff.affixVariant != null && variantPick(buff) != buff.spEffectId) continue
                if (buff.selfAllyPair?.role == "ally") continue
                val verdict = verdict(buff, out) ?: continue
                var stacks: Int? = null
                var selected = false
                buff.accumulatorLadder?.let { ladder ->
                    if (config.tiers[ladder.tierSpEffectIds[0]] != buff.spEffectId) continue
                    selected = true
                }
                buff.stackInput?.let { input ->
                    val n = minOf(maxOf(0, config.stackCounts[buff.spEffectId] ?: 0), paramMax(input))
                    if (n <= 0) continue
                    stacks = n
                    selected = true
                }
                val needs = !selected && (verdict.manual || buff.activation != "passive")
                if (needs && buff.spEffectId !in config.ticks) continue
                val multiply = buff.stacking.spCategoryBehavior == "stackSelf" &&
                    (buff.stacking.exclusiveScope.isEmpty() || buff.stacking.exclusiveScope == "perSpEffect")
                val copies = if (multiply) one.copies else 1
                val (table, flatTable) = tables(buff, verdict, stacks, copies)
                val value = weighted(table, out)
                val flat = weighted(flatTable, out).let { if (out.hasComposition) it else 0.0 }
                if (Math.abs(value - 1) <= 1e-9 && flat <= 1e-9) continue
                candidates += Candidate(
                    buff.spEffectId, buff.stacking.exclusiveKey, value, flat, table, one.column, copies,
                    buff.stacking.spCategoryBehavior == "applyHighest", buff.stacking.categoryPriority,
                )
            }
            val winners = LinkedHashMap<String, Candidate>()
            for (one in candidates) {
                val current = winners[one.key]
                val better = when {
                    current == null -> true
                    one.highest && current.highest && one.priority != current.priority -> one.priority < current.priority
                    Math.abs(one.value - current.value) > 1e-9 -> one.value > current.value
                    Math.abs(one.flat - current.flat) > 1e-9 -> one.flat > current.flat
                    else -> one.id < current.id
                }
                if (better) winners[one.key] = one
            }
            fun product(list: Collection<Candidate>): Double {
                val table = DoubleArray(DamageType.COUNT) { 1.0 }
                list.forEach { one -> for (i in table.indices) table[i] *= one.table[i] }
                return weighted(table, out)
            }
            val list = winners.values
            return Result(
                total = product(list),
                subtotals = SummaryColumn.entries.associateWith { column -> product(list.filter { it.column == column }) },
                ids = list.sortedBy { it.id }.map { it.id.toString() + if (it.copies > 1) "x${it.copies}" else "" },
            )
        }
    }

    @Test
    fun `each CONFIG case agrees with an independent reference - total, subtotals, counted set`() {
        val reference = ConfigReference(dataset)
        for (case in RankerCrossCheck.CONFIG_CASES) {
            val run = runs.getValue(case.key)
            val weapon = run.output.weaponId?.let { skills.weaponsById[it] }
            val expected = reference.config(run.config, run.output, weapon)
            assertClose(expected.total, run.result.totalMultiplier, 1e-9, "${case.key}：总倍率")
            SummaryColumn.entries.forEach { column ->
                assertClose(expected.subtotals.getValue(column), run.result.column(column).multiplier, 1e-9, "${case.key}：${column.key} 小计")
            }
            assertEquals(
                expected.ids,
                run.result.counted.sortedBy { it.id }.map { it.id.toString() + if (it.countedCopies > 1) "x${it.countedCopies}" else "" },
                "${case.key}：计入条目集合（含份数）",
            )
            assertTrue(run.result.totalMultiplier!! > 1, "${case.key}：这套配置应当增伤")
            // 总倍率＝计入条目逐类型连乘后按构成加权（独立再算一遍）；各栏小计同法只算本栏。
            fun weighted(items: List<EvaluatedEntry>): Double {
                val table = DoubleArray(DamageType.COUNT) { 1.0 }
                items.forEach { item -> for (i in table.indices) table[i] *= item.table[i] }
                return DamageType.entries.sumOf { run.output.share(it) * table[it.ordinal] } /
                    DamageType.entries.sumOf { run.output.share(it) }
            }
            assertClose(weighted(run.result.counted), run.result.totalMultiplier, 1e-9, "${case.key}：连乘加权")
            SummaryColumn.entries.forEach { column ->
                val own = run.result.counted.filter { it.column == column }
                assertClose(weighted(own), run.result.column(column).multiplier, 1e-9, "${case.key}：${column.key} 本栏连乘")
                assertEquals(own.size, run.result.column(column).count)
            }
        }
    }

    // ------------------------------------------------------------------ ③ 口径细节

    @Test
    fun `each CONFIG case stays within slots, has only legal relics and no repeated exclusive key`() {
        for ((key, run) in runs) {
            val slots = run.result.slots
            assertTrue(slots.weaponAffix.used <= slots.weaponAffix.cap, "$key 武器词条越界")
            assertTrue(slots.weaponAffix.deepOnlyUsed <= slots.weaponAffix.deepOnlyCap, "$key 深夜专属越界")
            assertTrue(slots.relic.used <= slots.relic.cap, "$key 遗物越界")
            assertTrue(slots.accessory.used <= slots.accessory.cap, "$key 护符越界")
            run.result.relicChecks.forEach { assertFalse(it.isInvalid, "$key：${it.issues}") }
            assertEquals(emptyList<String>(), run.result.violations)
            val keys = run.result.counted.map { it.entry.key }
            assertEquals(keys.size, keys.toSet().size, "$key 同一互斥键只能计入一份")
        }
    }

    @Test
    fun `filled cases are deterministic and only pick passive entries that need no confirmation`() {
        for (case in RankerCrossCheck.CONFIG_CASES.filter { it.filled }) {
            val run = runs.getValue(case.key)
            val again = run.evaluator.recommendFill(run.config, run.output.attackWepType)
            assertEquals(0, again.added.size, "${case.key}：已满不再加东西")
            assertEquals(run.config, again.config)
            assertEquals(case.build(index, run.evaluator), run.config, "${case.key}：推荐填满必须是确定性的")
            run.result.counted.forEach { item ->
                assertEquals("passive", item.entry.activation, "${item.id} 不是被动")
                assertEquals(null, item.entry.stackInput)
                assertEquals(null, item.entry.accLadder)
                assertTrue(item.needs.isEmpty())
            }
            assertTrue(run.config.weaponAffixes.isNotEmpty())
            val fixedKeys = run.config.relics.mapNotNull { card -> card.fixedKey.takeIf { card.type == RelicCardType.FIXED } }
            assertEquals(fixedKeys.size, fixedKeys.toSet().size, "同一件固定遗物不放进两格")
            val talismans = run.config.accessories.filterNotNull()
            assertEquals(talismans.size, talismans.toSet().size, "同一护符不装两个")
        }
        val a = runs.getValue("corpse-piler-normal-fill")
        assertEquals(dataset.slotRules!!.weaponAffix.maxAffixesNormal, a.result.slots.weaponAffix.used, "常规填满 6 条")
        val b = runs.getValue("death-lightning-deep-fill")
        assertEquals(RunMode.DEEP, b.config.runMode)
        assertEquals(dataset.slotRules!!.modes.deep.relicSlots, b.result.caps.relics)
        assertEquals(dataset.slotRules!!.weaponAffix.maxAffixesDeep, b.result.slots.weaponAffix.used, "深夜填满 12 条")
        b.result.counted.forEach { assertTrue(it.id != 8350000, "祷告不吃提升战技攻击力") }
        b.result.counted.forEach { assertTrue(it.entry.buff.appliesTo?.incantation != "no", "${it.id} 对祷告不生效却计入了") }
        for (card in b.config.relics.filter { it.type == RelicCardType.CUSTOM }) {
            for (row in 0 until RelicCard.ROWS) {
                val id = card.affixAt(row) ?: continue
                val affix = RankerTestData.catalog.affixes.first { it.effectId == id }
                assertEquals(affix.requiresCurse, card.curseAt(row) != null, "需诅咒的配诅咒、不需要的不带（${affix.name}）")
            }
        }
    }

    @Test
    fun `case C counts ticked and stacked entries but not the unticked conditional ones`() {
        val run = runs.getValue("lions-claw-2fixed-1custom-2talismans-evergaol7")
        assertEquals(
            listOf(RelicCheckStatus.FIXED, RelicCheckStatus.FIXED, RelicCheckStatus.VALID),
            run.result.relicChecks.map { it.status },
            "两件固定遗物 + 一件合法自组",
        )
        val counted = run.result.counted.map { it.id }.toSet()
        assertTrue(counted.containsAll(listOf(7006700, 7035902, 7069001, 312300)), counted.toString())
        assertFalse(7035703 in counted, "王的黑夜里没勾的条件型不计入")
        assertFalse(320400 in counted, "红羽七刃剑是条件型，放进护符栏≠条件成立")
        val evergaol = run.result.items.first { it.id == 7069001 }
        assertEquals(7, evergaol.stacks)
        assertClose(dataset.buffs.first { it.spEffectId == 7069001 }.stackInput!!.tierMultipliers[6], evergaol.multiplier, 1e-9, "封印监牢 7 层")
        assertClose(1.4072, evergaol.multiplier, 1e-9, "封印监牢 7 层 ×1.4072")
        val fire = run.result.items.filter { it.entry.variantGroup == "affix#7120100" }
        val chosen = fire.filter { it.state != EntryState.VARIANT_OFF }
        assertEquals(1, chosen.size, "多档词条只留第 1 档")
        assertEquals(EntryState.PENDING, chosen.single().state, "imbuedWeaponOnly 要确认")
    }

    @Test
    fun `same composition from different selections gives the same recommended loadout, spells fill above x1`() {
        val full = RankerCrossCheck.compose(skills, RankerCrossCheck.CASES[0])
        val last = RankerCrossCheck.compose(skills, RankerCrossCheck.CASES[1])
        val fillFull = index.evaluator(full.output).recommendFill(LoadoutConfig(), full.weapon!!.wepType).config
        val fillLast = index.evaluator(last.output).recommendFill(LoadoutConfig(), last.weapon!!.wepType).config
        assertEquals(fillFull, fillLast, "构成相同 → 推荐配置完全相同")
        listOf(RankerCrossCheck.CASES[5], RankerCrossCheck.CASES[6]).forEach { case ->
            val output = RankerCrossCheck.compose(skills, case).output
            val evaluator = index.evaluator(output)
            val filled = evaluator.recommendFill(LoadoutConfig(), output.attackWepType).config
            assertTrue(evaluator.evaluate(filled).totalMultiplier!! > 1, "${case.key} 应能给出增伤配置")
        }
    }

    // ------------------------------------------------------------------ ④ 说明区

    @Test
    fun `brief notes match the desktop digest and carry the numbers computed from data`() {
        val text = dumpLines.single { it.startsWith("TEXT ") }
        val notes = LoadoutText.briefNotes(index)
        assertEquals(field(text, "brief"), RankerCrossCheck.briefDigest(notes), "说明区摘要（两端 BRIEF_DIGEST）")
        assertEquals("ad04314d", RankerCrossCheck.briefDigest(notes))
        val all = notes.joinToString("\n")
        val decreases = RankerTestData.buffs.entries.count { it.countsAsDamage && it.direction == "decrease" }
        assertTrue(all.contains("direction=decrease 的 $decreases 条"), "减益条数照数据现算")
        assertTrue(all.contains("7 组 28 条"), "多档词条 7 组 28 条")
        assertTrue(all.contains(index.catalog.cursePoolId.toString()))
        assertTrue(all.contains("子类别 112 战技攻击／111 蓄力战技攻击"))
        assertFalse(all.contains("{"), "格式串都填满了")
        assertEquals(listOf("112 战技攻击", "111 蓄力战技攻击"), LoadoutText.skillOnlySubCategories(dataset))
        dataset.buffs.filter { it.stackInput != null }.forEach { assertTrue(all.contains(it.displayName), "${it.displayName} 的叠层说明") }
        // 任何一处措辞改动都会让摘要分叉（数字不影响）。
        assertEquals(RankerCrossCheck.briefDigest(notes), RankerCrossCheck.briefDigest(notes.map { it.replace("7", "9") }))
        assertFalse(RankerCrossCheck.briefDigest(notes.dropLast(1) + (notes.last() + "。")) == "ad04314d")
    }
}
