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

    // ------------------------------------------------------------------ 类型开关三档（战技 / 魔法 / 祷告）

    @Test
    fun `类型开关三档：战技、魔法、祷告各自只列本类，三档合起来正好是整张列表`() {
        val byKind = MeansKind.entries.associateWith { skills.outputsOfKind(it) }
        MeansKind.entries.forEach { kind ->
            val listed = byKind.getValue(kind)
            assertTrue(listed.isNotEmpty(), "${kind.key} 一档应当有条目")
            assertTrue(listed.all { it.outputClass == kind.outputClass && kind.includes(it) && MeansKind.of(it) == kind }, "${kind.key} 一档只列同类")
        }
        assertEquals(skills.skillOutputCount, byKind.getValue(MeansKind.SKILL).size)
        assertEquals(skills.spellOutputCount, byKind.getValue(MeansKind.SORCERY).size + byKind.getValue(MeansKind.INCANTATION).size)

        // 魔法／祷告两档按 spells[].kind 分开，徽标取数据集的 kindZh（魔法／祷告），不出现「法术」。
        byKind.getValue(MeansKind.SORCERY).forEach { output ->
            val spell = assertNotNull(skills.spellsById[output.entryId])
            assertEquals("sorcery", spell.kind, "${output.displayName} 不该出现在魔法档")
            assertEquals(spell.kindZh.ifEmpty { "魔法" }, output.badgeZh)
            assertEquals("魔法", output.badgeZh)
        }
        byKind.getValue(MeansKind.INCANTATION).forEach { output ->
            val spell = assertNotNull(skills.spellsById[output.entryId])
            assertEquals("incantation", spell.kind, "${output.displayName} 不该出现在祷告档")
            assertEquals(spell.kindZh.ifEmpty { "祷告" }, output.badgeZh)
            assertEquals("祷告", output.badgeZh)
        }
        assertTrue(byKind.getValue(MeansKind.SKILL).all { it.badgeZh == "战技" && it.isSkill })
        assertTrue(skills.outputs.none { it.badgeZh.contains("法术") })

        // 三档不重不漏，保持数据顺序。
        val union = MeansKind.entries.flatMap { byKind.getValue(it) }.map { it.id }
        assertEquals(union.size, union.toSet().size, "同一条不会出现在两档")
        assertEquals(skills.outputs.map { it.id }.sorted(), union.sorted(), "三档合起来是整张列表")
        MeansKind.entries.forEach { kind ->
            assertEquals(skills.outputs.filter { it.outputClass == kind.outputClass }.map { it.id }, byKind.getValue(kind).map { it.id })
        }

        // 已知条目落在该落的档：帚星（魔法 4021）、死亡雷击（祷告 5040，对拍用例）、尸横遍野（战技 1177）。
        fun has(kind: MeansKind, query: String, id: String) = skills.outputsOfKind(kind, query).any { it.id == id }
        assertTrue(has(MeansKind.SORCERY, "帚星", "sorcery-4021"))
        assertFalse(has(MeansKind.INCANTATION, "帚星", "sorcery-4021"))
        assertFalse(has(MeansKind.SKILL, "帚星", "sorcery-4021"))
        assertTrue(has(MeansKind.INCANTATION, "", "incantation-5040"), "死亡雷击在祷告档")
        assertFalse(has(MeansKind.SORCERY, "", "incantation-5040"), "死亡雷击不在魔法档")
        assertTrue(has(MeansKind.SKILL, "尸横遍野", "skill-1177"))
        assertFalse(has(MeansKind.SORCERY, "尸横遍野", "skill-1177"))

        // 搜索只在当前档里搜：拿一条祷告的英文名，祷告档搜得到（忽略大小写），魔法／战技档搜不到。
        val incant = byKind.getValue(MeansKind.INCANTATION).first { it.nameEn.isNotEmpty() }
        assertTrue(has(MeansKind.INCANTATION, incant.nameEn.lowercase(), incant.id))
        assertFalse(has(MeansKind.SORCERY, incant.nameEn, incant.id))
        assertFalse(has(MeansKind.SKILL, incant.nameEn, incant.id))
        // 类别名本身也能搜：魔法档搜「魔法」列出整档，搜「祷告」一条都没有。
        assertEquals(byKind.getValue(MeansKind.SORCERY), skills.outputsOfKind(MeansKind.SORCERY, "魔法"))
        assertTrue(skills.outputsOfKind(MeansKind.SORCERY, "祷告").isEmpty())
    }

    @Test
    fun `类型开关只是界面层的过滤：选中的输出手段、对拍口径与生效类别不变`() {
        // 选中后所在的档就是它的输出类别；MeansSelection 不带档位，编码不变。
        for (case in RankerCrossCheck.CASES) {
            val selection = select(case)
            val output = assertNotNull(skills.output(assertNotNull(selection.outputId)))
            val kind = MeansKind.of(output)
            assertEquals(case.outputClass, kind.outputClass, case.key)
            assertTrue(skills.outputsOfKind(kind).any { it.id == output.id }, case.key)
            assertEquals(case.outputClass, selection.resolve(skills).rankerOutput().outputClass, case.key)
            assertFalse("kind" in selection.encode(), "状态编码里没有档位")
        }
        assertEquals(MeansKind.SKILL, MeansKind.of(skills.output(assertNotNull(MeansSelection.initial(skills).outputId))), "默认选中的是战技，开关默认战技档")
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

        // 局内战技池的武器同样属于这个战技（weaponIds = 固定 ∪ 战技池），读回时保留。
        val lion = assertNotNull(skills.skillsById[100])
        val poolWeapon = skills.weaponsFor(lion).first { skills.weaponSourceKind(lion, it) == WeaponSourceKind.POOL }
        val kept = MeansSelection(outputId = "skill-100", weaponId = poolWeapon.id)
        assertSame(kept, kept.sanitized(skills))
    }

    // ------------------------------------------------------------------ skills schemaVersion 3

    @Test
    fun `武器列表：固定战技与局内可抽到的武器都能选，固定武器排前、默认选固定武器`() {
        val lion = select(RankerCrossCheck.CASES[2]).resolve(skills)
        val weapons = lion.weaponGroups.flatMap { it.weapons }
        assertEquals(76, weapons.size, "狮子斩：8 把固定 + 68 把局内战技池")
        assertEquals(mapOf(WeaponSourceKind.FIXED to 8, WeaponSourceKind.POOL to 68), lion.weaponSourceCounts)
        assertEquals(WeaponSourceKind.FIXED, lion.weaponSource(lion.weapon!!))
        assertEquals(3180000, skills.defaultWeapon(lion.skill!!)?.id)
        assertEquals(WeaponSourceKind.FIXED, lion.weaponSource(weapons.first()), "第一组的第一把是固定武器")

        // 换成局内战技池的武器：动作套按这一把武器实解（skillVariants[战技 ID]），不借用它固定战技的 skillVariant。
        val poolWeapon = weapons.first { lion.weaponSource(it) == WeaponSourceKind.POOL }
        assertNotEquals(100, poolWeapon.swordArtsParamId)
        val switched = select(RankerCrossCheck.CASES[2]).withWeapon(poolWeapon.id).resolve(skills)
        assertEquals(poolWeapon.id, switched.weapon?.id)
        val index = assertNotNull(poolWeapon.skillVariants["100"])
        assertEquals(lion.skill!!.variants[index], switched.variant)
        assertEquals(skills.hits(lion.skill!!, poolWeapon).map { it.atkId }, switched.hits.map { it.atkId })
        assertTrue(switched.composition.hasDamage)
        assertEquals(poolWeapon.wepType, switched.rankerOutput().attackWepType)

        // 只来自局内战技池的战技（风暴刃 210）：默认武器就是池里的，照样算得出构成。
        val storm = MeansSelection().select(skills, assertNotNull(skills.output("skill-210"))).resolve(skills)
        val stormWeapon = assertNotNull(storm.weapon)
        assertEquals(WeaponSourceKind.POOL, storm.weaponSource(stormWeapon))
        assertEquals(mapOf(WeaponSourceKind.POOL to 64), storm.weaponSourceCounts)
        assertTrue(storm.hasNoFpVariant)
        assertEquals(4, storm.selectedHits.size, "正常侧 3 段近战 + 1 段飞刃")
        assertEquals(3, MeansSelection().select(skills, skills.output("skill-210")!!).withNoFp(true).resolve(skills).selectedHits.size)

        // 法术没有武器来源。
        val comet = MeansSelection().select(skills, assertNotNull(skills.output("sorcery-4021"))).resolve(skills)
        assertTrue(comet.weaponSourceCounts.isEmpty())
        assertNull(comet.weaponSource(stormWeapon))
    }

    @Test
    fun `专注值不足版：两侧共用的 fpBoth 段在哪一侧都勾上`() {
        // 218 伟哉卡利亚：300200872 两侧共用；正常侧 870/871/872，专注值不足侧 872/875/876/877。
        val base = MeansSelection().select(skills, assertNotNull(skills.output("skill-218")))
        val normal = base.resolve(skills)
        assertTrue(normal.hasNoFpVariant)
        assertEquals(listOf(300200870, 300200871, 300200872), normal.selectedHits.map { it.atkId })
        val lowFocus = base.withNoFp(true).resolve(skills)
        assertEquals(listOf(300200872, 300200875, 300200876, 300200877), lowFocus.selectedHits.map { it.atkId })
        val shared = normal.hits.first { it.atkId == 300200872 }
        assertTrue(shared.fpBoth && normal.isEnabled(shared) && lowFocus.isEnabled(shared))
        // 全选（当前这一侧）同样带上 fpBoth 段。
        val all = base.withNoFp(true).let { it.withHitAction(it.resolve(skills).hits, HitAction.ALL) }.resolve(skills)
        assertEquals(lowFocus.selectedIds, all.selectedIds)

        // 1024 唤矛仪式：带伤害的两段都是 fpBoth 子弹，专注值不足侧也有构成（旧写法这里一段都不剩）。
        val ritual = MeansSelection().select(skills, assertNotNull(skills.output("skill-1024")))
        assertEquals(listOf(301612910, 301612911), ritual.resolve(skills).selectedHits.map { it.atkId })
        val ritualLow = ritual.withNoFp(true).resolve(skills)
        assertEquals(listOf(301612910, 301612911), ritualLow.selectedHits.map { it.atkId })
        assertTrue(ritualLow.composition.hasDamage)
    }

    @Test
    fun `狩猎大蛇：TAE 判为打不出的段不进分段列表`() {
        val serpent = MeansSelection().select(skills, assertNotNull(skills.output("skill-1188"))).resolve(skills)
        assertEquals(17030000, serpent.weapon?.id)
        assertEquals(WeaponSourceKind.FIXED, serpent.weaponSource(serpent.weapon!!), "固定且在战技池里：只标固定")
        assertEquals(listOf(301703950, 301703951, 301703970, 301703971), serpent.hits.map { it.atkId })
        assertTrue(serpent.hits.none { it.notInvoked })
        assertEquals(serpent.hits.size, serpent.segments.size)
        assertEquals(listOf(301703950, 301703951), serpent.selectedHits.map { it.atkId })
    }
}
