package com.nightreign.relicchecker.gamedata.ranker

import com.nightreign.relicchecker.gamedata.ranker.RankerTestData.assertClose
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.double
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

// skills schemaVersion 4（usage「蓄力段（v4）」，fieldNotes.subCategories / charged / chargeBranch / notInvoked）：
// 「蓄力」开关的分侧、派生的三项攻击情境、法术段的 notInvoked、子类别限定按勾选的段逐段判定。
// 对应 windows/tests/ranker.test.mjs 的「v4：…」各节。
class ChargedSegmentsTest {
    private val skills get() = RankerTestData.skills
    private val dataset get() = skills.dataset
    private val buffs get() = RankerTestData.buffs

    private fun ids(hits: Collection<SkillHit>): List<Int> = hits.map { it.atkId }

    /** 页面对一个法术的取段：先剔掉 notInvoked，再按两个开关取默认勾选的段（按数据顺序）。 */
    private fun spellSelection(id: Int, charged: Boolean, noFp: Boolean = false): List<Int> {
        val hits = skills.spellHits(skills.spellsById.getValue(id))
        val picked = SkillDamageMath.defaultSelection(hits, noFp, charged)
        return hits.filter { it.atkId in picked }.map { it.atkId }
    }

    /** 与页面同一口径的输出（RankerCrossCheck.compose：构成与逐段判定用同一批段，三项蓄力情境由开关派生）。 */
    private fun output(outputClass: OutputClass, id: Int, charged: Boolean, weaponId: Int? = null): RankerOutput =
        RankerCrossCheck.compose(skills, RankerCrossCheck.CompositionCase("t", outputClass, id, weaponId, charged = charged)).output

    private val rawSkills by lazy { Json.parseToJsonElement(RankerTestData.skillsText).jsonObject }

    // ------------------------------------------------------------------ 数据集

    @Test
    fun `v4 dataset carries per-hit subCategories and chargeBranch`() {
        assertEquals(4, dataset.schemaVersion)
        val chargedSubs = rawSkills.getValue("enums").jsonObject.getValue("chargedSubCategories").jsonArray.map { it.jsonPrimitive.int }
        assertEquals(listOf(100, 110, 111), chargedSubs)
        val hits = dataset.skills.flatMap { it.hits } + dataset.spells.flatMap { it.hits }
        assertEquals(
            setOf(ChargeBranch.BOTH, ChargeBranch.CHARGED, ChargeBranch.PARTIAL, ChargeBranch.UNCHARGED),
            hits.mapNotNull { it.chargeBranch }.toSet(),
            "chargeBranch 的取值",
        )
        hits.forEach { hit ->
            assertEquals(hit.subCategories.sorted().distinct(), hit.subCategories, "${hit.atkId} 的 subCategories 去重升序")
            assertEquals(hit.subCategories.any { it in chargedSubs }, hit.charged, "${hit.atkId}：charged ⇔ 子类别带蓄力")
        }
        assertEquals(dataset.count("hitsWithSubCategories"), hits.count { it.subCategories.isNotEmpty() })
        assertEquals(dataset.count("hitsCharged"), hits.count { it.charged })
        assertEquals(dataset.count("hitsChargeBranch"), hits.count { it.chargeBranch != null })
        assertEquals(dataset.count("hitsChargeBranchCharged"), hits.count { it.chargeBranch == ChargeBranch.CHARGED })
        assertEquals(dataset.count("hitsChargeBranchUncharged"), hits.count { it.chargeBranch == ChargeBranch.UNCHARGED })
        assertEquals(dataset.count("hitsChargeBranchBoth"), hits.count { it.chargeBranch == ChargeBranch.BOTH })
        assertEquals(2, hits.count { it.chargeBranch == ChargeBranch.PARTIAL })
        // 法术段的 notInvoked（施法动画没有槽位会发射）与 counts 一致。
        val spellDead = dataset.spells.sumOf { spell -> spell.hits.count { it.notInvoked } }
        assertEquals(dataset.count("spellHitsNotInvoked"), spellDead)
        assertEquals(dataset.count("hitsNotInvokedAll"), spellDead + dataset.count("hitsNotInvoked"))
        dataset.spells.flatMap { it.hits }.filter { it.notInvoked }.forEach { assertEquals("noCastSlot", it.notInvokedReason) }
    }

    // ------------------------------------------------------------------ 蓄力开关（合成）

    @Test
    fun `charge toggle splits by chargeBranch after the fp side and never takes partial`() {
        val hits = listOf(
            SkillHit(atkId = 1, chargeBranch = "uncharged"),
            SkillHit(atkId = 2, chargeBranch = "charged", charged = true),
            SkillHit(atkId = 3, chargeBranch = "both"),
            SkillHit(atkId = 4, chargeBranch = "partial"),
            SkillHit(atkId = 5, chargeBranch = "charged", noDamage = true),
            SkillHit(atkId = 6, chargeBranch = "uncharged", noFp = true),
            SkillHit(atkId = 7, chargeBranch = "both", noFp = true),
            SkillHit(atkId = 8),
        )
        assertEquals(ChargeInfo(applicable = true, onlyCharged = false), SkillDamageMath.chargeInfo(hits, false))
        assertEquals(listOf(2, 3), SkillDamageMath.defaultSelection(hits, false, charged = true).toList(), "开：charged + both")
        assertEquals(listOf(1, 3), SkillDamageMath.defaultSelection(hits, false, charged = false).toList(), "关：uncharged + both；partial 与缺 chargeBranch 的段两侧都不取")
        // 专注值不足侧没有 charged 段：开关不适用，开 / 关都取 ② 的全部段（在 ② 之后判，否则一段不剩）。
        assertEquals(ChargeInfo.NOT_APPLICABLE, SkillDamageMath.chargeInfo(hits, true))
        assertEquals(listOf(6, 7), SkillDamageMath.defaultSelection(hits, true, charged = true).toList())
        assertEquals(listOf(6, 7), SkillDamageMath.defaultSelection(hits, true, charged = false).toList())
        assertFalse(SkillDamageMath.chargeInfo(hits, true).effective(true), "不适用 → 蓄力情境不成立")
        assertFalse(SkillDamageMath.chargeInfo(hits, true).switchable)
        assertTrue(SkillDamageMath.chargeInfo(hits, false).switchable)
        // 只有蓄力段：强制打开。
        val only = listOf(
            SkillHit(atkId = 1, chargeBranch = "charged"),
            SkillHit(atkId = 2, chargeBranch = "charged"),
            SkillHit(atkId = 3, chargeBranch = "partial"),
        )
        val onlyInfo = SkillDamageMath.chargeInfo(only, false)
        assertEquals(ChargeInfo(applicable = true, onlyCharged = true), onlyInfo)
        assertTrue(onlyInfo.effective(false))
        assertFalse(onlyInfo.switchable)
        assertEquals(listOf(1, 2), SkillDamageMath.defaultSelection(only, false, charged = false).toList())
        // v3 数据（没有 chargeBranch）：不适用，取全部带伤害的段——与旧口径相同。
        val v3 = listOf(SkillHit(atkId = 1), SkillHit(atkId = 2, noFp = true), SkillHit(atkId = 3, fpBoth = true), SkillHit(atkId = 4, noDamage = true))
        assertEquals(listOf(1, 3), SkillDamageMath.defaultSelection(v3, false, charged = true).toList())
        assertEquals(listOf(2, 3), SkillDamageMath.defaultSelection(v3, true, charged = false).toList())
        // 「全选」只勾当前两侧都对的段；「全不选」「恢复默认」不看开关。
        val all = SkillDamageMath.hitOverridesFor(hits, HitAction.ALL, false, charged = true)
        assertEquals(listOf(2, 3), all.filterValues { it }.keys.toList())
        assertFalse(5 in all, "noDamage 段不参与")
        assertEquals(listOf(1, 3), SkillDamageMath.hitOverridesFor(hits, HitAction.ALL, false, charged = false).filterValues { it }.keys.toList())
        assertEquals(emptyMap(), SkillDamageMath.hitOverridesFor(hits, HitAction.RESET, false, charged = true))
        assertTrue(SkillDamageMath.hitOverridesFor(hits, HitAction.NONE, false, charged = true).values.none { it })
        // 显式的保留集：partial 不在任何一侧。
        assertEquals(setOf("charged", "both"), ChargeBranch.ON_SIDE)
        assertEquals(setOf("uncharged", "both"), ChargeBranch.OFF_SIDE)
        assertFalse(ChargeBranch.keeps("partial", true) || ChargeBranch.keeps("partial", false) || ChargeBranch.keeps(null, false))
    }

    @Test
    fun `the three charged attack contexts are derived from the toggle and cannot be ticked alone`() {
        assertEquals(listOf("chargedHeavyAttack", "chargedSkill", "chargedSpell"), SkillDamageMath.CHARGED_CONTEXTS)
        SkillDamageMath.CHARGED_CONTEXTS.forEach { key -> assertTrue(key in buffs.dataset.enums.attackContext, key) }
        val picked = setOf("criticalHit", "chargedSpell")
        assertEquals(setOf("criticalHit"), SkillDamageMath.chargedContexts(picked, false), "单独勾的蓄力情境不算数")
        assertEquals(
            setOf("criticalHit", "chargedHeavyAttack", "chargedSkill", "chargedSpell"),
            SkillDamageMath.chargedContexts(picked, true),
        )
        // 页面：三项不接受单独勾选；读回旧状态时去掉。
        val selection = MeansSelection.initial(skills)
        assertEquals(selection, selection.toggleContext("chargedSpell"))
        val old = selection.copy(attackContexts = setOf("criticalHit", "chargedSkill"))
        assertEquals(setOf("criticalHit"), old.sanitized(skills).attackContexts)
        // 情境门控：蓄力开＝三项成立，关＝都不成立（哪怕状态里留着单独勾过的）。
        val chargedOnly = RankerTestData.synth(-60) {
            it.copy(
                appliesTo = BuffAppliesTo(skill = "conditional", sorcery = "conditional", incantation = "conditional"),
                appliesToDetail = BuffAppliesDetails(
                    incantation = BuffAppliesDetail(reason = "蓄力法术", requires = BuffRequirement(attackContexts = listOf("chargedSpell"))),
                ),
            )
        }
        val on = RankerTestData.out(OutputClass.INCANTATION, contexts = SkillDamageMath.chargedContexts(emptySet(), true))
        val off = RankerTestData.out(OutputClass.INCANTATION, contexts = SkillDamageMath.chargedContexts(setOf("chargedSpell"), false))
        assertEquals(VerdictState.YES, buffs.verdict(chargedOnly, on).state)
        assertEquals(VerdictState.CONTEXT, buffs.verdict(chargedOnly, off).state)
    }

    // ------------------------------------------------------------------ 真实数据

    @Test
    fun `spell hits drop notInvoked - beast claw keeps 68200 and 68205, death lightning drops 50402 and 50407`() {
        val claw = skills.spellsById.getValue(6820)
        assertEquals(listOf(68201, 68206), ids(claw.hits.filter { it.notInvoked }))
        assertEquals(listOf(68200, 68205), ids(skills.spellHits(claw)))
        assertEquals(listOf(68205), spellSelection(6820, charged = true), "蓄力开：只打蓄力子弹")
        assertEquals(listOf(68200), spellSelection(6820, charged = false), "蓄力关：只打普通子弹")
        assertEquals(listOf(50405, 50406), spellSelection(5040, charged = true))
        assertEquals(listOf(50400, 50401), spellSelection(5040, charged = false))
        // 熔炉百相之尾：75000 两种放法都打（both），75005 只在蓄力时打。
        assertEquals(listOf(75000, 75005), spellSelection(7500, charged = true))
        assertEquals(listOf(75000), spellSelection(7500, charged = false))
        // 没有一段 notInvoked 进默认勾选；输出手段的段数也只数打得出的段。
        dataset.spells.forEach { spell ->
            val hits = skills.spellHits(spell)
            listOf(true, false).forEach { charged ->
                val picked = SkillDamageMath.defaultSelection(hits, false, charged)
                assertTrue(spell.hits.filter { it.notInvoked }.none { it.atkId in picked }, "${spell.id}")
            }
            skills.output("${spell.outputClass.key}-${spell.id}")?.let { assertEquals(hits.size, it.segmentCount, "${spell.id} 的段数") }
        }
        assertEquals(4, skills.spellsById.getValue(6820).hits.size)
    }

    @Test
    fun `charged spell buff on beast claw - x1_18 x1_13 x1_09 in full when charged, none when uncharged`() {
        val rates = mapOf(8330302 to 1.18, 8330301 to 1.13, 8330300 to 1.09)
        val onOut = output(OutputClass.INCANTATION, 6820, charged = true)
        val offOut = output(OutputClass.INCANTATION, 6820, charged = false)
        val loadout = RankerTestData.loadout
        rates.forEach { (id, rate) ->
            val entry = buffs.byId.getValue(id)
            val verdictOn = buffs.verdict(entry, onOut)
            assertEquals(VerdictState.YES, verdictOn.state)
            assertEquals(1.0, verdictOn.weight)
            assertNull(verdictOn.typeShares, "$id：勾选的段全部带 110，全额")
            assertEquals(RankerText.t("verdict.conditionalMet"), verdictOn.label, "不再标「部分段生效」")
            val config = LoadoutConfig(weaponAffixes = mapOf(id to 1))
            assertEquals(rate, loadout.evaluator(onOut).evaluate(config).totalMultiplier, "$id 蓄力开：总倍率正好是参数值")
            val offResult = loadout.evaluator(offOut).evaluate(config)
            assertEquals(1.0, offResult.totalMultiplier, "$id 蓄力关：不生效")
            assertEquals(EntryState.NO, offResult.items.single().state)
            assertEquals(RankerText.t("verdict.no"), buffs.verdict(entry, offOut).label)
            // 武器词条栏的这一行：开时分数就是参数值，关时判为不生效。
            val rowOn = loadout.evaluator(onOut).weaponAffixRows(LoadoutConfig(), null).first { row -> row.affix.id == id }
            assertClose(rate, rowOn.score.score, 1e-12, "$id 武器词条栏分数")
            assertTrue(rowOn.score.applicable)
            val rowOff = loadout.evaluator(offOut).weaponAffixRows(LoadoutConfig(), null).first { row -> row.affix.id == id }
            assertFalse(rowOff.score.applicable)
            assertEquals(EntryState.NO, rowOff.score.state)
        }
    }

    @Test
    fun `per-segment judging reproduces the three numbers in diagnostics chargeBranch examples`() {
        val examples = rawSkills.getValue("diagnostics").jsonObject.getValue("chargeBranch").jsonObject
            .getValue("examples").jsonObject.mapValues { it.value.jsonPrimitive.double }
        val loadout = RankerTestData.loadout
        fun spellTotal(id: Int): Double =
            loadout.evaluator(output(OutputClass.INCANTATION, id, charged = true))
                .evaluate(LoadoutConfig(weaponAffixes = mapOf(8330302 to 1))).totalMultiplier!!
        assertClose(examples.getValue("6820"), spellTotal(6820), 5e-7, "兽爪")
        assertClose(examples.getValue("7500"), spellTotal(7500), 5e-7, "熔炉百相之尾：(270 + 274 × 1.18) / 544")
        // 突击 105：蓄力开取 301701900–904（900–903 [112, 130]，904 [111, 112, 130]）→「强化魔法、祷告、战技的蓄力使用」330900
        // 只乘 904 → (140 + 145 × 1.18) / 285，部分段生效。
        val charge = skills.skillsById.getValue(105)
        val weapon = assertNotNull(skills.defaultWeapon(charge))
        val onHits = SkillDamageMath.defaultSelection(skills.hits(charge, weapon), false, charged = true)
        assertEquals(listOf(301701900, 301701901, 301701902, 301701903, 301701904), onHits.toList())
        val chargeOut = output(OutputClass.SKILL, 105, charged = true, weaponId = weapon.id)
        val item = buffs.evaluate(buffs.byId.getValue(330900), chargeOut, EntrySelections.NONE, EvalOptions(assumeAll = true))
        assertClose(examples.getValue("105"), item.multiplier, 5e-7, "突击")
        assertEquals(RankerText.t("verdict.partial"), item.label, "突击的冲刺段不带 111：部分段生效")
        // 关：只打 903 + 905，都不带 110 / 111。
        val offHits = SkillDamageMath.defaultSelection(skills.hits(charge, weapon), false, charged = false)
        assertEquals(listOf(301701903, 301701905), offHits.toList())
        val offOut = output(OutputClass.SKILL, 105, charged = false, weaponId = weapon.id)
        assertEquals(VerdictState.NO, buffs.verdict(buffs.byId.getValue(330900), offOut).state)
    }

    @Test
    fun `roar 1031 has no charged hits on the low focus side and glintstone 218 never takes its partial hits`() {
        val roar = skills.skillsById.getValue(1031)
        val roarWeapon = assertNotNull(
            skills.weaponsFor(roar).firstOrNull { SkillDamageMath.chargeInfo(skills.hits(roar, it), false).applicable },
            "王者嘶吼有武器能蓄力",
        )
        val roarHits = skills.hits(roar, roarWeapon)
        assertFalse(SkillDamageMath.chargeInfo(roarHits, true).applicable, "无 FP 侧只剩吼叫本体")
        val noFpSide = roarHits.filter { !it.noDamage && it.isOnSide(true) }
        assertTrue(noFpSide.isNotEmpty())
        assertEquals(ids(noFpSide), SkillDamageMath.defaultSelection(roarHits, true, charged = true).toList(), "蓄力开也不会一段不剩")

        val glint = skills.skillsById.getValue(218)
        val glintHits = skills.hits(glint, skills.weaponsFor(glint)[0])
        assertEquals(listOf(300200872), SkillDamageMath.defaultSelection(glintHits, false, charged = true).toList())
        assertEquals(listOf(300200870), SkillDamageMath.defaultSelection(glintHits, false, charged = false).toList())
        assertEquals(listOf(300200872, 300200877), SkillDamageMath.defaultSelection(glintHits, true, charged = true).toList())
        assertEquals(listOf(300200875), SkillDamageMath.defaultSelection(glintHits, true, charged = false).toList())
        val partials = glintHits.filter { it.chargeBranch == ChargeBranch.PARTIAL }
        assertEquals(listOf(300200871, 300200876), ids(partials).sorted())
        for (noFp in listOf(true, false)) {
            for (charged in listOf(true, false)) {
                val picked = SkillDamageMath.defaultSelection(glintHits, noFp, charged)
                partials.forEach { assertFalse(it.atkId in picked, "${it.atkId} 是 partial，不该默认勾上") }
            }
        }
    }

    @Test
    fun `every chargeable move has hits on both sides and the two sides only share chargeBranch both`() {
        var checked = 0
        fun check(label: String, hits: List<SkillHit>) {
            for (noFp in listOf(false, true)) {
                val info = SkillDamageMath.chargeInfo(hits, noFp)
                if (!info.applicable) continue
                checked += 1
                assertFalse(info.onlyCharged, "$label noFp=$noFp：本版本没有只有蓄力段的招")
                val on = SkillDamageMath.defaultSelection(hits, noFp, charged = true)
                val off = SkillDamageMath.defaultSelection(hits, noFp, charged = false)
                assertTrue(on.isNotEmpty() && off.isNotEmpty(), "$label noFp=$noFp 两侧都要有段")
                val byId = hits.associateBy { it.atkId }
                on.intersect(off).forEach { assertEquals(ChargeBranch.BOTH, byId.getValue(it).chargeBranch, "$label 两侧共用的 $it") }
                (on + off).forEach { assertTrue(byId.getValue(it).chargeBranch != ChargeBranch.PARTIAL) }
            }
        }
        dataset.skills.forEach { skill ->
            skills.weaponsFor(skill).forEach { weapon ->
                val hits = skills.hits(skill, weapon)
                if (hits.isNotEmpty()) check("${skill.id} × ${weapon.id}", hits)
            }
        }
        dataset.spells.forEach { spell -> check("法术 ${spell.id}", skills.spellHits(spell)) }
        assertTrue(checked > 100, "可蓄力的（招, 武器, 专注值侧）组合太少：$checked")
    }

    // ------------------------------------------------------------------ 页面状态

    @Test
    fun `means selection - charged toggle picks a side, resets on switching moves and derives contexts`() {
        val claw = MeansSelection().select(skills, assertNotNull(skills.output("incantation-6820")))
        val off = claw.resolve(skills)
        assertTrue(off.chargeInfo.applicable && off.chargeInfo.switchable)
        assertFalse(off.chargedOn)
        assertEquals(listOf(68200, 68205), ids(off.hits), "notInvoked 段不列出")
        assertEquals(2, off.spellNotInvokedCount)
        assertEquals(listOf(68200), ids(off.selectedHits))
        assertTrue(off.rankerOutput().attackContexts.isEmpty())

        val touched = claw.withHit(off.hits.first { it.atkId == 68205 }, true)
        assertEquals(listOf(68200, 68205), ids(touched.resolve(skills).selectedHits), "手动勾选照样生效")
        val onSel = touched.withCharged(true)
        assertTrue(onSel.hitOverrides.isEmpty(), "切换时手动勾选清掉")
        val on = onSel.resolve(skills)
        assertTrue(on.chargedOn)
        assertEquals(listOf(68205), ids(on.selectedHits))
        assertEquals(SkillDamageMath.CHARGED_CONTEXTS.toSet(), on.rankerOutput().attackContexts)
        assertEquals(listOf(68205), on.rankerOutput().segments!!.map { it.atkId })
        assertEquals(RankerCrossCheck.compose(skills, RankerCrossCheck.CASES.first { it.key == "beast-claw-charged" }).output, on.rankerOutput())
        // 全选只勾当前两侧都对的段。
        assertEquals(listOf(68205), ids(onSel.withHitAction(on.hits, HitAction.ALL).resolve(skills).selectedHits))
        // 换招 / 换武器：开关关掉。
        val lion = onSel.select(skills, assertNotNull(skills.output("skill-100")))
        assertFalse(lion.charged)
        assertFalse(lion.resolve(skills).chargeInfo.applicable, "狮子斩没有蓄力段")
        assertEquals(onSel, MeansSelection.decode(onSel.encode()), "蓄力开关随状态存取")
        assertFalse(MeansSelection(outputId = "skill-100", weaponId = 3180000, charged = true).withWeapon(3180500).charged)
        // 没有蓄力段的招：开关拨到开也不改选段、不派生情境。
        val lionOn = lion.withCharged(true).resolve(skills)
        assertFalse(lionOn.chargedOn)
        assertEquals(ids(lion.resolve(skills).selectedHits), ids(lionOn.selectedHits))
        assertTrue(lionOn.rankerOutput().attackContexts.isEmpty())
    }
}
