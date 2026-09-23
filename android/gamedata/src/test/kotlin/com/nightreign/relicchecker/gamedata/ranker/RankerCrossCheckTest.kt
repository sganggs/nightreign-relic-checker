package com.nightreign.relicchecker.gamedata.ranker

import com.nightreign.relicchecker.gamedata.ranker.RankerTestData.assertClose
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertTrue

// 三端对拍（windows/tests/ranker_crosscheck.test.mjs）：
//   ① 逐行比对 Windows 端打印的 CASE 行（test resources 的 ranker-crosscheck-dump.txt）：选段、九类构成占比、
//      一览生效条数、有效倍率 > 1 的条数与前 10 名（数值容差 1e-6）；OUTPUTS 行（输出手段条数）；
//   ② 与 Windows / macOS 两端一样，再用一份**独立重算的参考实现**（下方 Reference，不复用被测代码的分支）
//      逐条校对一览的生效判定与有效倍率（容差 1e-9）；
//   ③ 跨用例关系（构成相同 → 一览相同；换火属性武器只多出加火的条目；子弹段；法术只用 flat）。
// CONFIG 行（整套配置）与说明区摘要见 LoadoutCrossCheckTest。
class RankerCrossCheckTest {
    private val skills get() = RankerTestData.skills
    private val buffs get() = RankerTestData.buffs

    private val runs: Map<String, RankerCrossCheck.CaseRun> by lazy {
        RankerCrossCheck.CASES.associate { it.key to RankerCrossCheck.run(skills, buffs, it) }
    }

    private data class DumpCase(
        val key: String,
        val selected: List<Int>,
        val shares: List<Double>,
        val applicable: Int,
        val useful: Int,
        val top10: List<Pair<Int, Double>>,
    )

    private val dumpLines: List<String> by lazy {
        RankerTestData.readText("ranker-crosscheck-dump.txt").lines().map { it.trimEnd() }
            .filter { it.isNotEmpty() && !it.startsWith("#") }
    }

    private fun field(line: String, name: String): String {
        val token = line.split(' ').firstOrNull { it.startsWith("$name=") }
        return assertNotNull(token, "对拍行缺少 $name=：$line").substringAfter('=')
    }

    private fun parseCase(line: String): DumpCase {
        val parts = line.split(' ')
        return DumpCase(
            key = parts[1],
            selected = field(line, "selected").split(',').filter { it.isNotEmpty() }.map { it.toInt() },
            shares = field(line, "shares").split(',').map { it.toDouble() },
            applicable = field(line, "applicable").toInt(),
            useful = field(line, "useful").toInt(),
            top10 = field(line, "top10").split(',').filter { it.isNotEmpty() }.map {
                val (id, value) = it.split(':')
                id.toInt() to value.toDouble()
            },
        )
    }

    // ------------------------------------------------------------------ ① 对拍行

    @Test
    fun `every CASE line of the desktop dump matches field by field`() {
        val cases = dumpLines.filter { it.startsWith("CASE ") }.map { parseCase(it) }
        assertEquals(RankerCrossCheck.CASES.map { it.key }, cases.map { it.key }, "七组构成用例、同一顺序")
        for (expected in cases) {
            val run = runs.getValue(expected.key)
            val actual = parseCase(run.dumpLine)
            assertEquals(expected.selected, actual.selected, "${expected.key}：选段")
            assertEquals(DamageType.COUNT, expected.shares.size)
            expected.shares.forEachIndexed { i, share ->
                assertClose(share, actual.shares[i], 1e-6, "${expected.key}：${DamageType.entries[i].key} 占比")
                assertClose(share, run.composition.shares[i], 1e-6, "${expected.key}：${DamageType.entries[i].key} 占比（未格式化）")
            }
            assertEquals(expected.applicable, actual.applicable, "${expected.key}：一览生效条数")
            assertEquals(expected.useful, actual.useful, "${expected.key}：有效倍率 > 1 的条数")
            assertEquals(expected.top10.map { it.first }, actual.top10.map { it.first }, "${expected.key}：前 10 名")
            expected.top10.forEachIndexed { i, (id, value) ->
                val row = run.useful[i]
                assertEquals(id, row.id)
                assertClose(value, row.multiplier, 1e-6, "${expected.key}：#$id 的有效倍率")
            }
        }
    }

    @Test
    fun `OUTPUTS and TEXT lines of the desktop dump match`() {
        assertEquals(dumpLines.single { it.startsWith("OUTPUTS ") }, RankerCrossCheck.outputsDumpLine(skills))
        val text = dumpLines.single { it.startsWith("TEXT ") }
        assertEquals(RankerText.table.size.toString(), field(text, "count"), "文案条数")
        assertEquals(RankerCrossCheck.textTableDigest(), field(text, "digest"), "文案常量表摘要")
        assertEquals(3, dumpLines.count { it.startsWith("CONFIG ") }, "三组配置对拍行（LoadoutCrossCheckTest 逐字段比对）")
    }

    @Test
    fun `dump line format matches the desktop caseDumpLine exactly`() {
        val run = runs.getValue("corpse-piler-full")
        val line = run.dumpLine
        assertTrue(line.startsWith("CASE corpse-piler-full selected=303400300,303400301,303400302,303400303,303400304,303400305 shares=0.500000000,"), line)
        assertTrue(line.contains(" applicable=296 useful=200 top10=707214:3.550000000,707215:3.550000000,"), line)
        assertEquals(dumpLines.first { it.startsWith("CASE corpse-piler-full ") }, line, "整行逐字相同")
        // 本版本数据下七行全部逐字相同（比逐字段 1e-6 更严；数据集修订后以上一条测试的逐字段比对为准）。
        val expected = dumpLines.filter { it.startsWith("CASE ") }
        assertEquals(expected, RankerCrossCheck.CASES.map { runs.getValue(it.key).dumpLine })
    }

    // ------------------------------------------------------------------ ② 独立参考实现

    /** 独立重算（故意不复用被测代码的分支）：Windows ranker_crosscheck.test.mjs 的 referenceVerdict / referenceOverview。 */
    private class Reference(private val dataset: BuffDataset) {
        private val fields = dataset.rateFields.associateBy { it.key }
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

        fun countsAsDamage(buff: BuffEntry): Boolean = buff.rates.any { (key, value) ->
            val field = fields[key]
            field != null && field.countsAsDamage && value != field.default
        }

        fun listable(buff: BuffEntry): Boolean =
            countsAsDamage(buff) && (buff.target == "self" || buff.target == "ally") && buff.direction != "decrease"

        data class Verdict(val weight: Double, val restricted: DamageType?)

        fun verdict(buff: BuffEntry, out: RankerOutput): Verdict? {
            val cls = out.outputClass
            val value = buff.appliesTo?.get(cls)
            if (value != "yes" && value != "conditional") return null
            if (value == "yes") return Verdict(1.0, null)
            val requires = buff.appliesToDetail[cls]?.requires ?: return Verdict(1.0, null)
            var weight = 1.0
            var restricted: DamageType? = null
            requires.hand?.let { if (it != out.hand) return null }
            if (requires.attackWeaponTypes.isNotEmpty()) {
                val own = when (cls) {
                    OutputClass.SKILL -> out.weaponWepType
                    OutputClass.SORCERY -> 57
                    OutputClass.INCANTATION -> 61
                }
                if (own == null || own !in requires.attackWeaponTypes) return null
            }
            if (requires.subCategoriesAny.isNotEmpty()) {
                val table = if (cls == OutputClass.SKILL) dataset.attackIndex.skills else dataset.attackIndex.spells
                val sets = out.meansId?.let { table[it] }
                if (sets != null) {
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
            if (requires.attackContexts.isNotEmpty() && requires.attackContexts.none { it in out.attackContexts }) return null
            requires.physicalType?.let { code ->
                restricted = listOf(DamageType.SLASH, DamageType.BLOW, DamageType.THRUST, DamageType.NEUTRAL)[code]
                if (!(out.share(restricted!!) > 0.0)) return null
            }
            return Verdict(weight, restricted)
        }

        private fun paramMax(input: BuffStackInput): Int {
            if (input.mode != "ladder") return 99
            val tiers = input.tierMultipliers.size
            val param = input.paramMaxStacks ?: 0
            return if (param > 0) (if (tiers > 0) minOf(param, tiers) else param) else maxOf(tiers, 1)
        }

        private fun rates(buff: BuffEntry, stacks: Int?): Map<String, Double> {
            val input = buff.stackInput ?: return buff.rates
            val value = if (input.mode == "ladder") {
                input.tierMultipliers[minOf(stacks!!, input.tierMultipliers.size) - 1]
            } else {
                Math.pow(input.perStackMultiplier!!, stacks!!.toDouble())
            }
            val keys = input.appliesToRateKeys.ifEmpty { listOf(input.multiplierKey) }
            return buff.rates + keys.associateWith { value }
        }

        fun overview(buff: BuffEntry, out: RankerOutput): Double? {
            if (!listable(buff)) return null
            if (buff.selfAllyPair?.role == "ally") return null
            val verdict = verdict(buff, out) ?: return null
            val input = buff.stackInput
            val stacks = input?.let {
                val soft = (it.practicalMaxStacks ?: 0).takeIf { v -> v > 0 } ?: (it.uiLabelMax ?: 0).takeIf { v -> v > 0 } ?: 1
                minOf(soft, paramMax(it))
            }
            val table = DoubleArray(DamageType.COUNT) { 1.0 }
            for ((key, value) in rates(buff, stacks)) {
                val field = fields[key] ?: continue
                if (!field.countsAsDamage || !value.isFinite() || value == field.default) continue
                if (field.valueKind == "multiplier" && value > 0) {
                    fieldChannels[key]?.forEach { channel ->
                        if (verdict.restricted == null || channel == verdict.restricted) table[channel.ordinal] *= value
                    }
                }
            }
            if (verdict.weight < 1) for (i in table.indices) table[i] = 1 + (table[i] - 1) * verdict.weight
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
    }

    @Test
    fun `overview agrees with an independent reference for every row of every case`() {
        val reference = Reference(buffs.dataset)
        var checked = 0
        for ((key, run) in runs) {
            val listed = run.rows.map { it.id }.toSet()
            buffs.dataset.buffs.forEach { buff ->
                assertEquals(reference.listable(buff), buff.spEffectId in listed, "$key：#${buff.spEffectId} 进不进一览")
            }
            run.rows.forEach { row ->
                val expected = reference.overview(row.entry.buff, run.output)
                checked += 1
                if (expected == null) {
                    assertTrue(!row.applicable, "$key：#${row.id} 参考判不生效，实际是 ${row.state}")
                    if (row.entry.pairRole == "ally") assertEquals(RankerText.t("reasonAllyPair"), row.reasons[0])
                } else {
                    assertTrue(row.applicable, "$key：#${row.id} 参考判生效，实际是 ${row.state}")
                    assertClose(expected, row.multiplier, 1e-9, "$key：#${row.id} 的有效倍率")
                }
            }
            val top = run.useful.take(10)
            assertTrue(top.isNotEmpty(), "$key 应有生效条目")
            top.zipWithNext().forEach { (a, b) -> assertTrue(a.multiplier!! >= b.multiplier!! - 1e-12, "$key：前 10 名按有效倍率降序") }
        }
        assertTrue(checked > 100 * runs.size, "逐条比对的样本太少")
    }

    @Test
    fun `composition shares agree with an independent recomputation`() {
        for ((key, run) in runs) {
            val selected = run.selected.map { it.atkId }.toSet()
            val amounts = DoubleArray(DamageType.COUNT)
            for (hit in run.hits) {
                if (hit.atkId !in selected || hit.noDamage) continue
                val physType = when (hit.attribute) {
                    "Slash" -> DamageType.SLASH
                    "Strike" -> DamageType.BLOW
                    "Pierce" -> DamageType.THRUST
                    "Standard" -> DamageType.NEUTRAL
                    "WeaponAtkAttribute" -> DamageType.physical(run.weapon?.atkAttribute ?: -1)
                    "WeaponAtkAttribute2" -> DamageType.physical(run.weapon?.atkAttribute2 ?: -1)
                    else -> DamageType.PHYS_NONE
                }
                for (element in SkillElement.entries) {
                    val base = run.weapon?.attackBase?.get(element.key) ?: 0.0
                    val motion = if (run.weapon != null) hit.motion[element.key] ?: 0.0 else 0.0
                    var amount = base * motion / 100 + (hit.flat[element.key] ?: 0.0)
                    if (hit.addBaseAtk) amount += base
                    if (!(amount > 0)) continue
                    val type = if (element == SkillElement.PHYSICAL) physType else DamageType.entries.first { it.element == element }
                    amounts[type.ordinal] += amount
                }
            }
            val total = amounts.sum()
            assertClose(total, run.composition.total, 1e-9, "$key：相对伤害总量")
            DamageType.entries.forEach { assertClose(amounts[it.ordinal] / total, run.composition.share(it), 1e-9, "$key：${it.key}") }
            assertClose(1.0, run.composition.shares.sum(), 1e-9, "$key：占比之和")
            assertTrue(run.selected.none { it.noDamage })
            if (run.case.only == null) assertTrue(run.selected.none { it.noFp }, "默认勾选只取正常版这一侧")
        }
    }

    // ------------------------------------------------------------------ ③ 跨用例关系

    @Test
    fun `same composition from different selections gives the same overview`() {
        val full = runs.getValue("corpse-piler-full")
        val last = runs.getValue("corpse-piler-last")
        assertTrue(full.selected.size > last.selected.size)
        DamageType.entries.forEach { assertClose(full.composition.share(it), last.composition.share(it), 1e-9, it.key) }
        assertEquals(full.useful.take(10).map { it.id }, last.useful.take(10).map { it.id }, "构成相同 → 前 10 名必须完全相同")
    }

    @Test
    fun `a fire weapon on the same skill only adds fire-only entries`() {
        val plain = runs.getValue("lions-claw-greatsword")
        val flame = runs.getValue("lions-claw-flame-greatsword")
        assertEquals(0.0, plain.composition.share(DamageType.FIRE))
        assertTrue(flame.composition.share(DamageType.FIRE) > 0)
        assertEquals(plain.selected.map { it.atkId }, flame.selected.map { it.atkId }, "同一战技同一套段，换武器不该改变选段")
        val fireOnly = flame.useful.filter { row ->
            row.item.table[DamageType.FIRE.ordinal] > 1 &&
                DamageType.entries.all { it == DamageType.FIRE || Math.abs(row.item.table[it.ordinal] - 1) < 1e-9 }
        }
        assertTrue(fireOnly.isNotEmpty(), "火焰大剑下应能进来只加火的条目")
        val plainIds = plain.useful.map { it.id }.toSet()
        fireOnly.forEach { assertTrue(it.id !in plainIds, "只加火的条目对纯物理构成没有收益（#${it.id}）") }
    }

    @Test
    fun `skill bullet hits still use attack x motion and skill attack buffs apply to them`() {
        val run = runs.getValue("firebreather")
        val bullets = run.hits.filter { it.isBullet }
        assertTrue(bullets.isNotEmpty(), "喷火应有子弹段")
        assertTrue(bullets.any { hit -> SkillDamageMath.hitContribution(hit, run.weapon, false).any { it > 0 } }, "战技的子弹段不得被整段归零")
        assertTrue(run.hits.any { it.noDamage }, "喷火里应有 noDamage 段（精力消耗）")
        assertTrue(run.selected.none { it.noDamage })
        assertEquals(VerdictState.YES, buffs.verdict(buffs.byId.getValue(8350000), run.output).state, "带 112 的「提升战技攻击力」对子弹段生效")
    }

    @Test
    fun `spell compositions come only from flat values`() {
        listOf("death-lightning", "comet").forEach { key ->
            val run = runs.getValue(key)
            DamageType.PHYSICAL.forEach { assertEquals(0.0, run.composition.share(it), "$key 是法术，${it.key} 占比必须为 0") }
            assertTrue(run.useful.isNotEmpty())
            // 「提升战技攻击力」对法术不生效（appliesTo.sorcery / incantation = no）。
            assertTrue(run.rows.first { it.id == 8350000 }.applicable.not(), "$key：祷告／魔法不吃提升战技攻击力")
        }
        assertEquals(OutputClass.INCANTATION, runs.getValue("death-lightning").output.outputClass)
        assertEquals(OutputClass.SORCERY, runs.getValue("comet").output.outputClass)
    }

    @Test
    fun `the listed outputs are exactly those that compute a non-zero composition`() {
        skills.outputs.filter { it.isSkill }.forEach { output ->
            val skill = skills.skillsById.getValue(output.entryId)
            val playable = skill.weaponIds.any { id ->
                val weapon = skills.weaponsById[id] ?: return@any false
                SkillDamageMath.hasAnyDamage(skills.hits(skill, weapon), weapon, false)
            }
            assertTrue(playable, "列表里的战技「${output.nameZh}」必须至少有一把武器算得出构成")
        }
        skills.outputs.filter { !it.isSkill }.forEach { output ->
            assertTrue(SkillDamageMath.hasAnyDamage(skills.spellsById.getValue(output.entryId).hits, null, true))
        }
        assertEquals(7, RankerCrossCheck.CASES.size)
        assertEquals(setOf(OutputClass.SKILL, OutputClass.SORCERY, OutputClass.INCANTATION), RankerCrossCheck.CASES.map { it.outputClass }.toSet())
        assertEquals(7, buffs.variants.size, "多档词条 7 组（数据 affixVariant）")
    }
}
