package com.nightreign.relicchecker.gamedata.ranker

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertSame
import kotlin.test.assertTrue

// 页面上半部分的选择状态（MeansSelection / ResolvedMeans）：与对拍用的 RankerCrossCheck.compose 同一口径
// （选段 → 默认勾选正常版这一侧 → 构成 → 输出手段），外加页面交互的固定事实（换招 / 换武器 / 专注值不足版 /
// 分段工具条 / 攻击情境过滤 / 保存与读回）。
class MeansSelectionTest {
    private val skills get() = RankerTestData.skills

    private fun select(case: RankerCrossCheck.CompositionCase): MeansSelection {
        val output = assertNotNull(skills.output("${case.outputClass.key}-${case.id}"), "找不到输出手段 ${case.key}")
        var selection = MeansSelection().select(skills, output)
        case.weaponId?.let { selection = selection.withWeapon(it) }
        val only = case.only
        if (only != null) {
            val resolved = selection.resolve(skills)
            selection = selection.withHitAction(resolved.hits, HitAction.NONE)
            for (hit in resolved.hits) if (hit.atkId in only) selection = selection.withHit(hit, true)
        }
        return selection
    }

    @Test
    fun `页面的输出手段与对拍用例逐项相同（七组构成用例）`() {
        for (case in RankerCrossCheck.CASES) {
            val composed = RankerCrossCheck.compose(skills, case)
            val resolved = select(case).resolve(skills)
            assertEquals(composed.output, resolved.rankerOutput(), case.key)
            assertEquals(composed.selected.map { it.atkId }, resolved.selectedHits.map { it.atkId }, case.key)
            assertEquals(composed.hits.map { it.atkId }, resolved.hits.map { it.atkId }, case.key)
            assertEquals(resolved.hits.size, resolved.segments.size, case.key)
            RankerTestData.assertClose(composed.composition.total, resolved.composition.total, message = case.key)
        }
    }

    @Test
    fun `默认选第一条战技与它的默认武器`() {
        val initial = MeansSelection.initial(skills)
        val first = skills.outputs.first()
        assertTrue(first.isSkill, "输出手段列表战技在前")
        assertEquals(first.id, initial.outputId)
        val skill = assertNotNull(skills.skillsById[first.entryId])
        assertEquals(skills.defaultWeapon(skill)?.id, initial.weaponId)
        assertEquals(1, initial.hand)
        assertFalse(initial.useNoFp)
        val resolved = initial.resolve(skills)
        assertTrue(resolved.composition.hasDamage, "默认输出手段勾选后要有伤害构成")
        assertEquals(OutputClass.SKILL, resolved.outputClass)
    }

    @Test
    fun `战技带武器类别，法术按施法器，换招保留手与攻击情境`() {
        val corpse = select(RankerCrossCheck.CASES[0]).withHand(2).toggleContext("criticalHit")
        val resolved = corpse.resolve(skills)
        assertEquals(9040000, resolved.weapon?.id)
        assertEquals(resolved.weapon?.wepType, resolved.rankerOutput().attackWepType)
        assertEquals(2, resolved.rankerOutput().hand)
        assertTrue(resolved.weaponGroups.isNotEmpty())
        assertTrue(resolved.weaponGroups.flatMap { it.weapons }.any { it.id == 9040000 })

        val comet = corpse.select(skills, assertNotNull(skills.output("sorcery-4021")))
        assertNull(comet.weaponId)
        assertEquals(2, comet.hand)
        assertEquals(setOf("criticalHit"), comet.attackContexts)
        val spell = comet.resolve(skills)
        assertEquals(OutputClass.SORCERY, spell.outputClass)
        assertNull(spell.weapon)
        assertTrue(spell.weaponGroups.isEmpty())
        assertEquals(57, spell.rankerOutput().attackWepType)
        assertEquals(61, select(RankerCrossCheck.CASES[5]).resolve(skills).rankerOutput().attackWepType)
    }

    @Test
    fun `专注值不足版整体切换，换武器时关掉`() {
        val base = select(RankerCrossCheck.CASES[0])
        val normal = base.resolve(skills)
        assertTrue(normal.hasNoFpVariant, "尸横遍野有专注值不足版的段")
        assertEquals(12, normal.hits.size)
        assertEquals(6, normal.selectedHits.size)
        assertTrue(normal.selectedHits.none { it.noFp })

        val noFp = base.withNoFp(true)
        val resolved = noFp.resolve(skills)
        assertEquals(6, resolved.selectedHits.size)
        assertTrue(resolved.selectedHits.all { it.noFp })
        assertTrue(resolved.composition.hasDamage)

        // 手动勾过的段在切换时清掉
        val touched = base.withHit(normal.hits.first { it.noFp }, true)
        assertEquals(7, touched.resolve(skills).selectedHits.size)
        assertTrue(touched.withNoFp(true).hitOverrides.isEmpty())

        assertEquals(listOf(9040000), resolved.weaponGroups.flatMap { it.weapons }.map { it.id }, "尸横遍野只有尸山血海一把")
        assertSame(noFp, noFp.withWeapon(9040000), "同一把武器原样返回")

        // 狮子斩有很多把武器：换武器时专注值不足版开关与手动勾选一起清掉
        val lion = select(RankerCrossCheck.CASES[2])
        val lionHits = lion.resolve(skills).hits
        val dirty = lion.copy(useNoFp = true).withHit(lionHits.first(), false)
        val other = lion.resolve(skills).weaponGroups.flatMap { it.weapons }.first { it.id != 3180000 }
        val switched = dirty.withWeapon(other.id)
        assertFalse(switched.useNoFp)
        assertTrue(switched.hitOverrides.isEmpty())
        assertEquals(other.id, switched.resolve(skills).weapon?.id)
    }

    @Test
    fun `分段工具条：全选只勾当前这一侧、全不选没有构成、恢复默认`() {
        val base = select(RankerCrossCheck.CASES[0])
        val hits = base.resolve(skills).hits
        val none = base.withHitAction(hits, HitAction.NONE).resolve(skills)
        assertTrue(none.selectedHits.isEmpty())
        assertFalse(none.composition.hasDamage)
        assertFalse(none.rankerOutput().hasComposition)

        val all = base.withHitAction(hits, HitAction.ALL).resolve(skills)
        assertEquals(hits.filter { !it.noDamage && !it.noFp }.map { it.atkId }, all.selectedHits.map { it.atkId })
        val allNoFp = base.withNoFp(true).withHitAction(hits, HitAction.ALL).resolve(skills)
        assertTrue(allNoFp.selectedHits.all { it.noFp })

        val reset = base.withHitAction(hits, HitAction.NONE).withHitAction(hits, HitAction.RESET)
        assertTrue(reset.hitOverrides.isEmpty())
        assertEquals(base.resolve(skills).selectedIds, reset.resolve(skills).selectedIds)
    }

    @Test
    fun `只挂状态的段不可勾`() {
        val skill = skills.dataset.skills.firstOrNull { entry ->
            entry.weaponIds.isNotEmpty() && skills.weaponsFor(entry).any { weapon -> skills.hits(entry, weapon).any { it.noDamage } }
        }
        val entry = assertNotNull(skill, "数据里至少有一个战技带 noDamage 段")
        val weapon = skills.weaponsFor(entry).first { weapon -> skills.hits(entry, weapon).any { it.noDamage } }
        val output = skills.output("skill-${entry.id}") ?: return // 整个战技算不出伤害时不在输出手段列表里
        val selection = MeansSelection().select(skills, output).withWeapon(weapon.id)
        val resolved = selection.resolve(skills)
        val dead = resolved.hits.first { it.noDamage }
        assertSame(selection, selection.withHit(dead, true))
        assertFalse(resolved.isEnabled(dead))
        assertFalse(dead.atkId in resolved.selectedIds)
    }

    @Test
    fun `攻击情境只把当前输出类别要求过的交给计算器`() {
        val selection = select(RankerCrossCheck.CASES[0]).toggleContext("criticalHit").toggleContext("notAContext")
        val resolved = selection.resolve(skills)
        assertEquals(setOf("criticalHit", "notAContext"), resolved.rankerOutput().attackContexts)
        val valid = RankerTestData.buffs.attackContextOptions(OutputClass.SKILL).map { it.key }.toSet()
        val filtered = resolved.rankerOutput(valid).attackContexts
        assertFalse("notAContext" in filtered)
        assertEquals(if ("criticalHit" in valid) setOf("criticalHit") else emptySet(), filtered)
        assertEquals(selection, selection.toggleContext("x").toggleContext("x"))
    }

    @Test
    fun `保存与读回，对不上数据时改回可用的值`() {
        val selection = select(RankerCrossCheck.CASES[0]).withHand(2).withNoFp(true).toggleContext("criticalHit")
        val touched = selection.withHit(selection.resolve(skills).hits.first(), false)
        val text = touched.encode()
        assertEquals(touched, MeansSelection.decode(text))
        assertEquals(touched, touched.sanitized(skills))
        assertNull(MeansSelection.decode(""))
        assertNull(MeansSelection.decode("{not json"))
        assertNull(MeansSelection.decode(null))

        val unknown = MeansSelection(outputId = "skill-999999999", hand = 2).sanitized(skills)
        assertEquals(MeansSelection.initial(skills).outputId, unknown.outputId)
        assertEquals(2, unknown.hand)

        val wrongWeapon = MeansSelection(outputId = "skill-1177", weaponId = 3180000).sanitized(skills)
        assertNotEquals(3180000, wrongWeapon.weaponId)
        val corpse = assertNotNull(skills.skillsById[1177])
        assertEquals(skills.defaultWeapon(corpse)?.id, wrongWeapon.weaponId)

        val spellWithWeapon = MeansSelection(outputId = "sorcery-4021", weaponId = 9040000).sanitized(skills)
        assertNull(spellWithWeapon.weaponId)
    }
}
