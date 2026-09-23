package com.nightreign.relicchecker.gamedata.ranker

import com.nightreign.relicchecker.gamedata.GameDataFormatException
import com.nightreign.relicchecker.gamedata.ranker.RankerTestData.assertClose
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertNotEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

// skills 数据集与选段 / 构成（对应 windows/tests/ranker.test.mjs 的选段、伤害类型、伤害构成、输出手段各节，
// 以及 macOS BuffRankerChecks.swift 的 checkSkillDataset / checkSegmentSelection / checkSegmentChips / checkComposition）。
class SkillDataTest {
    private val skills get() = RankerTestData.skills
    private val dataset get() = skills.dataset

    private fun weapon(
        attackBase: Map<String, Double> = emptyMap(),
        atkAttribute: Int = 3,
        atkAttribute2: Int = 3,
        nameEn: String = "",
        wepTypeEn: String = "",
        poiseDamageBase: Double = 0.0,
        staminaBase: Double = 0.0,
        skillVariant: Int? = null,
    ) = SkillWeapon(
        id = 1, attackBase = attackBase, atkAttribute = atkAttribute, atkAttribute2 = atkAttribute2,
        nameEn = nameEn, wepTypeEn = wepTypeEn, poiseDamageBase = poiseDamageBase, staminaBase = staminaBase,
        skillVariant = skillVariant,
    )

    private val allElements = listOf("physical", "magic", "fire", "lightning", "holy")

    // ------------------------------------------------------------------ 数据集与固定事实

    @Test
    fun `dataset parses with version, usage boundary and fixed counts`() {
        assertEquals(2, dataset.schemaVersion)
        assertTrue(dataset.gameVersion.startsWith("v1.03.5"), dataset.gameVersion)
        assertEquals("regulation 10350000", dataset.dataVersion)
        assertNotNull(dataset.usage[SkillDataset.USAGE_SELECTION], "选段规则必须来自数据集")
        val boundary = assertNotNull(dataset.usage[SkillDataset.USAGE_BOUNDARY], "skills usage 应含「本数据集的边界」（页面要引用）")
        assertTrue(boundary.isNotBlank())
        assertEquals(
            listOf("选段（必读）", "近战武器段", "伤害类型（斩 / 打 / 突）", "法术 / 子弹段", "削韧", "本数据集的边界"),
            dataset.usage.keys.toList(),
            "usage 的键按数据顺序",
        )
        assertEquals(6, dataset.caveats.size)
        assertEquals(3, dataset.sources.size)
        // 固定事实（与数据集 counts 一致）
        assertEquals(1793, dataset.weapons.size)
        assertEquals(187, dataset.skills.size)
        assertEquals(160, dataset.spells.size)
        assertEquals(1793, dataset.count("weapons"))
        assertEquals(2201, dataset.count("hits"))
        assertEquals(166, dataset.skills.count { it.hits.isNotEmpty() })
        assertEquals(139, dataset.spells.count { it.hits.isNotEmpty() })
        assertEquals(67, dataset.spells.count { it.outputClass == OutputClass.SORCERY })
        assertEquals(93, dataset.spells.count { it.outputClass == OutputClass.INCANTATION })
        assertTrue(dataset.weapons.all { it.atkAttribute in 0..3 && it.atkAttribute2 in 0..3 })
        assertTrue(dataset.weapons.any { it.attackBase.isNotEmpty() })
        assertEquals("1793 把武器 · 187 个战技 · 160 个法术", skills.summary)
    }

    @Test
    fun `wrong schema version is rejected`() {
        val error = assertFailsWith<GameDataFormatException> {
            RankerParsers.skills("""{"schemaVersion":1,"weapons":[],"skills":[],"spells":[]}""")
        }
        assertTrue(error.message!!.contains("nightreign-skills-v1.03.5.json"))
    }

    // ------------------------------------------------------------------ 输出手段列表

    @Test
    fun `output list only takes skills and spells that can compute a composition`() {
        // 固定事实：战技 114 + 法术 121（魔法 60、祷告 61），与 Windows 对拍行 OUTPUTS 一致。
        assertEquals(114, skills.skillOutputCount)
        assertEquals(121, skills.spellOutputCount)
        assertEquals(60, skills.outputs.count { it.outputClass == OutputClass.SORCERY })
        assertEquals(61, skills.outputs.count { it.outputClass == OutputClass.INCANTATION })
        assertEquals(6, skills.skillsWithoutDamage, "纯增益的战技")
        assertEquals(18, skills.spellsWithoutDamage, "恢复／庇佑类法术")
        assertEquals(21, skills.skillsWithoutHits)
        assertEquals(21, skills.spellsWithoutHits)
        assertEquals(46, skills.skillsWithoutWeapons)

        // 收录口径：有命中段 + （战技）至少一把武器引用 + 至少能算出一段非 0 相对值。
        val skillIds = skills.outputs.filter { it.isSkill }.map { it.entryId }.toSet()
        for (skill in dataset.skills) {
            val usable = skill.hits.isNotEmpty() && skill.weaponIds.isNotEmpty() && skills.skillHasDamage(skill)
            assertEquals(usable, skill.id in skillIds, "${skill.id} 的收录判定")
        }
        assertTrue(dataset.skills.any { it.hits.isNotEmpty() && it.weaponIds.isEmpty() }, "数据集里应当有『有段但没有武器引用』的战技")
        val spellIds = skills.outputs.filter { !it.isSkill }.map { it.entryId }.toSet()
        val dead = dataset.spells.filter { it.hits.isNotEmpty() && !SkillDamageMath.hasAnyDamage(it.hits, null, true) }
        assertEquals(18, dead.size)
        dead.forEach { assertFalse(it.id in spellIds, "${it.nameZh} 选中后构成恒为 0，不该进列表") }
        skills.outputs.filter { !it.isSkill }.forEach { output ->
            assertTrue(SkillDamageMath.hasAnyDamage(skills.spellsById.getValue(output.entryId).hits, null, true))
        }
        // 顺序：战技在前、法术在后，各自保持数据顺序。
        val firstSpell = skills.outputs.indexOfFirst { !it.isSkill }
        assertTrue(skills.outputs.drop(firstSpell).none { it.isSkill })
        assertEquals(
            dataset.skills.map { it.id }.filter { it in skillIds },
            skills.outputs.filter { it.isSkill }.map { it.entryId },
        )
        assertTrue(skills.outputs.all { it.displayName.isNotEmpty() })
        assertTrue(skills.outputs.filter { it.isSkill }.all { it.weaponCount > 0 && it.subtitleZh == "战技 · ${it.weaponCount} 把武器" })
        val comet = assertNotNull(skills.output("sorcery-4021"))
        assertEquals("魔法", comet.badgeZh)
        assertEquals("魔法 · 专注值 ${comet.mp}", comet.subtitleZh)
        assertEquals(OutputClass.INCANTATION, skills.output("incantation-5040")?.outputClass)
    }

    @Test
    fun `output search matches chinese, english ignoring case, and id prefix`() {
        val sample = skills.outputs.first { it.isSkill && it.nameZh.isNotEmpty() && it.nameEn.isNotEmpty() }
        assertTrue(skills.outputsMatching(sample.nameZh).any { it.id == sample.id })
        assertTrue(skills.outputsMatching(sample.nameEn.uppercase()).any { it.id == sample.id }, "英文搜索要忽略大小写")
        assertTrue(skills.outputsMatching("1177").any { it.entryId == 1177 }, "纯数字按 id 前缀")
        assertTrue(skills.outputsMatching("", OutputClass.SKILL).all { it.isSkill })
        assertTrue(skills.outputsMatching("", OutputClass.INCANTATION).all { it.outputClass == OutputClass.INCANTATION })
        assertEquals(skills.outputs.size, skills.outputsMatching("").size)
        val spell = skills.outputs.first { !it.isSkill && it.nameEn.isNotEmpty() }
        assertTrue(skills.outputsMatching(spell.nameEn).any { it.id == spell.id })
    }

    // ------------------------------------------------------------------ 选段

    @Test
    fun `selectHits always follows skillVariant to variants atkIds, never a union`() {
        val multi = assertNotNull(dataset.skills.firstOrNull { it.variants.size > 1 }, "数据集里应当有多套动作的战技")
        val seen = HashSet<Int>()
        multi.variants.forEachIndexed { position, variant ->
            val weapon = skills.weaponsById.getValue(variant.weaponIds[0])
            assertEquals(position, weapon.skillVariant, "variant 的下标必须就是武器的 skillVariant")
            assertEquals(variant, skills.selectVariant(multi, weapon))
            val hits = skills.hits(multi, weapon)
            assertEquals(variant.atkIds.size, hits.size)
            hits.forEach { assertTrue(it.atkId in variant.atkIds) }
            assertTrue(hits.size < multi.hits.size, "取并集会把段数撑到全表")
            hits.forEach { seen += it.atkId }
        }
        assertTrue(seen.size <= multi.hits.size)
        // 不同动作套的武器选出的段必须不同（macOS checkSegmentSelection）。
        val first = skills.hits(multi, skills.weaponsById[multi.variants[0].weaponIds[0]]).map { it.atkId }.toSet()
        val second = skills.hits(multi, skills.weaponsById[multi.variants[1].weaponIds[0]]).map { it.atkId }.toSet()
        assertNotEquals(first, second)
    }

    @Test
    fun `every weapon with a skillVariant selects a non-empty, in-variant set without noVariant hits`() {
        var checked = 0
        for (weapon in dataset.weapons) {
            val index = weapon.skillVariant ?: continue
            val skill = skills.skillsById[weapon.swordArtsParamId] ?: continue
            if (index !in skill.variants.indices) continue
            checked += 1
            val allowed = skill.variants[index].atkIds.toSet()
            val hits = skills.hits(skill, weapon)
            assertTrue(hits.isNotEmpty(), "${weapon.id} 选不出段")
            assertTrue(hits.none { it.noVariant }, "${weapon.id} 选到了 noVariant 段")
            assertTrue(hits.all { it.atkId in allowed }, "${weapon.id} 选段超出 variants[].atkIds")
        }
        assertTrue(checked > 500, "参与选段校验的武器太少：$checked")
    }

    @Test
    fun `a weapon without skillVariant hits nothing`() {
        val skill = dataset.skills.first { it.variants.isNotEmpty() }
        assertNull(skills.selectVariant(skill, weapon()))
        assertEquals(emptyList(), skills.hits(skill, weapon()))
        assertEquals(emptyList(), skills.hits(skill, null))
        assertEquals(emptyList(), SkillDataIndex.selectHits(SkillEntry(hits = emptyList()), weapon()))
    }

    @Test
    fun `without variants selectHits falls back to a single ctx - weapon name, then type, then missing ctx`() {
        val skill = SkillEntry(
            hits = listOf(SkillHit(atkId = 1, ctx = "Dagger"), SkillHit(atkId = 2, ctx = "Reduvia"), SkillHit(atkId = 3)),
        )
        assertEquals(listOf(2), SkillDataIndex.selectHits(skill, weapon(nameEn = "Reduvia", wepTypeEn = "Dagger")).map { it.atkId }, "武器名优先")
        assertEquals(listOf(1), SkillDataIndex.selectHits(skill, weapon(nameEn = "Misericorde", wepTypeEn = "Dagger")).map { it.atkId }, "退到武器类别")
        assertEquals(listOf(3), SkillDataIndex.selectHits(skill, weapon(nameEn = "X", wepTypeEn = "Y")).map { it.atkId }, "最后才用 ctx 缺失的那组")
    }

    @Test
    fun `hit overrides select only the current side, normal and low focus never both count`() {
        val hits = listOf(SkillHit(atkId = 1), SkillHit(atkId = 2, noFp = true), SkillHit(atkId = 3, noDamage = true))
        val all = SkillDamageMath.hitOverridesFor(hits, HitAction.ALL, useNoFp = false)
        assertEquals(true, all[1])
        assertEquals(false, all[2], "专注值不足版与正常版互为替代，一起勾会把同一击算两遍")
        assertFalse(3 in all, "noDamage 段不参与")
        val allNoFp = SkillDamageMath.hitOverridesFor(hits, HitAction.ALL, useNoFp = true)
        assertEquals(false, allNoFp[1])
        assertEquals(true, allNoFp[2])
        assertEquals(mapOf(1 to false, 2 to false), SkillDamageMath.hitOverridesFor(hits, HitAction.NONE, false))
        assertEquals(emptyMap(), SkillDamageMath.hitOverridesFor(hits, HitAction.RESET, false), "恢复默认＝清空 override")
        assertEquals(setOf(1), SkillDamageMath.defaultSelection(hits))
        assertEquals(setOf(2), SkillDamageMath.defaultSelection(hits, useNoFp = true))
        assertEquals(listOf(2), SkillDamageMath.selectedHits(hits, mapOf(1 to false, 2 to true), false).map { it.atkId })
        assertFalse(SkillDamageMath.isHitEnabled(hits[2], mapOf(3 to true), false), "noDamage 段怎么勾都不计入")

        // 真实数据：全选之后相对值合计不会翻倍（= 与默认勾选一致）。
        val pair = dataset.weapons.asSequence().filter { it.skillVariant != null }.mapNotNull { weapon ->
            dataset.skills.firstOrNull { skill ->
                weapon.id in skill.weaponIds && skills.hits(skill, weapon).any { it.noFp }
            }?.let { weapon to it }
        }.firstOrNull()
        val (weapon, skill) = assertNotNull(pair, "数据集里应当有带专注值不足版本的战技")
        val picked = skills.hits(skill, weapon)
        val overrides = SkillDamageMath.hitOverridesFor(picked, HitAction.ALL, false)
        val chosen = picked.filter { overrides[it.atkId] == true }
        val fallback = picked.filter { !it.noDamage && !it.noFp }
        assertEquals(fallback.map { it.atkId }, chosen.map { it.atkId })
        assertEquals(
            SkillDamageMath.composition(fallback, weapon, false).total,
            SkillDamageMath.composition(chosen, weapon, false).total,
        )
        val normal = SkillDamageMath.defaultSelection(picked)
        val lowFocus = SkillDamageMath.defaultSelection(picked, useNoFp = true)
        assertTrue(lowFocus.isNotEmpty() && normal.intersect(lowFocus).isEmpty(), "正常版与专注值不足版必须互斥")
    }

    // ------------------------------------------------------------------ 伤害类型

    @Test
    fun `physical type resolves WeaponAtkAttribute and WeaponAtkAttribute2 from the weapon`() {
        val w = weapon(atkAttribute = 2, atkAttribute2 = 1)
        assertEquals(DamageType.THRUST, SkillDamageMath.physicalTypeFor(SkillHit(attribute = "WeaponAtkAttribute"), w))
        assertEquals(DamageType.BLOW, SkillDamageMath.physicalTypeFor(SkillHit(attribute = "WeaponAtkAttribute2"), w))
        assertEquals(DamageType.SLASH, SkillDamageMath.physicalTypeFor(SkillHit(attribute = "Slash"), w))
        assertEquals(DamageType.BLOW, SkillDamageMath.physicalTypeFor(SkillHit(attribute = "Strike"), w))
        assertEquals(DamageType.THRUST, SkillDamageMath.physicalTypeFor(SkillHit(attribute = "Pierce"), w))
        assertEquals(DamageType.NEUTRAL, SkillDamageMath.physicalTypeFor(SkillHit(attribute = "Standard"), w))
        assertEquals(DamageType.PHYS_NONE, SkillDamageMath.physicalTypeFor(SkillHit(attribute = "None"), w))
        assertEquals(DamageType.PHYS_NONE, SkillDamageMath.physicalTypeFor(SkillHit(attribute = "WeaponAtkAttribute"), null))
        // 数据集里确实有大量走 Weapon* 间接引用的段（页面必须走这一步）。
        val indirect = dataset.skills.sumOf { skill ->
            skill.hits.count { it.attribute == "WeaponAtkAttribute" || it.attribute == "WeaponAtkAttribute2" }
        }
        assertTrue(indirect > 0)
    }

    // ------------------------------------------------------------------ 单段相对伤害与芯片

    @Test
    fun `only spell hits ignore motion, skill bullets still multiply weapon attack`() {
        assertTrue(SkillDamageMath.usesMotion(isSpell = false))
        assertFalse(SkillDamageMath.usesMotion(isSpell = true), "法术段不得把 motion 乘到施法器攻击力上")
    }

    @Test
    fun `hit contribution is attack x motion over 100 plus flat, addBaseAtk adds one more attack`() {
        val w = weapon(attackBase = mapOf("physical" to 100.0, "fire" to 50.0))
        val hit = SkillHit(attribute = "Slash", motion = mapOf("physical" to 200.0, "fire" to 100.0), flat = mapOf("fire" to 7.0))
        val plain = SkillDamageMath.hitContribution(hit, w, false)
        assertEquals(200.0, plain[DamageType.SLASH.ordinal])
        assertEquals(57.0, plain[DamageType.FIRE.ordinal])
        assertEquals(300.0, SkillDamageMath.hitContribution(hit.copy(addBaseAtk = true), w, false)[DamageType.SLASH.ordinal])
        // 子弹段走同一条路：motion 与 addBaseAtk 都算。
        val bullet = SkillDamageMath.hitContribution(hit.copy(isBullet = true, addBaseAtk = true), w, false)
        assertEquals(300.0, bullet[DamageType.SLASH.ordinal])
        assertEquals(107.0, bullet[DamageType.FIRE.ordinal])
        // 同一段当成法术段来算：motion 被忽略，只剩 flat。
        val asSpell = SkillDamageMath.hitContribution(hit, w, true)
        assertEquals(0.0, asSpell[DamageType.SLASH.ordinal])
        assertEquals(7.0, asSpell[DamageType.FIRE.ordinal])
        // noDamage 段（只挂 spEffect）完全不计入。
        assertTrue(SkillDamageMath.hitContribution(hit.copy(noDamage = true), w, false).all { it == 0.0 })
    }

    @Test
    fun `segment chips only keep channels that really contribute for the current weapon`() {
        val w = weapon(attackBase = mapOf("physical" to 100.0, "fire" to 50.0), atkAttribute = 0, atkAttribute2 = 0)
        val hit = SkillHit(attribute = "Slash", motion = allElements.associateWith { 99.0 })
        val seg = SkillDamageMath.segment(hit, w, isSpell = false)
        assertEquals(listOf(DamageType.SLASH, DamageType.FIRE), seg.visibleComponents.map { it.type })
        assertEquals(3, seg.hiddenZeroComponentCount, "被隐藏的三项要数出来，行末才补得上那句小字")

        val withFlat = SkillDamageMath.segment(hit.copy(flat = mapOf("holy" to 20.0)), w, isSpell = false)
        assertEquals(listOf(DamageType.SLASH, DamageType.FIRE, DamageType.HOLY), withFlat.visibleComponents.map { it.type })
        assertEquals(2, withFlat.hiddenZeroComponentCount)

        val full = weapon(attackBase = allElements.associateWith { 10.0 }, atkAttribute = 0, atkAttribute2 = 0)
        assertEquals(
            listOf(DamageType.SLASH, DamageType.MAGIC, DamageType.FIRE, DamageType.LIGHTNING, DamageType.HOLY),
            SkillDamageMath.segment(hit, full, isSpell = false).visibleComponents.map { it.type },
            "顺序固定为 物理子类型 → 魔力 → 火 → 雷 → 圣",
        )

        // 法术段只用 flat：motion 一项都不显示，也不算「被隐藏」。
        val spellHit = SkillHit(
            attribute = "None",
            motion = mapOf("physical" to 100.0, "magic" to 100.0, "fire" to 100.0),
            flat = mapOf("magic" to 152.0),
        )
        val spellSeg = SkillDamageMath.segment(spellHit, null, isSpell = true)
        assertEquals(listOf(DamageType.MAGIC), spellSeg.visibleComponents.map { it.type })
        assertEquals(0, spellSeg.hiddenZeroComponentCount)

        val dead = SkillDamageMath.segment(SkillHit(attribute = "Slash", motion = mapOf("magic" to 99.0)), w, isSpell = false)
        assertTrue(dead.visibleComponents.isEmpty())
        assertFalse(dead.hasDamage)

        val noDamage = SkillDamageMath.segment(hit.copy(noDamage = true), w, isSpell = false)
        assertTrue(noDamage.components.isEmpty())
        assertEquals(0, noDamage.hiddenZeroComponentCount)
    }

    @Test
    fun `channels coming only from addBaseAtk still get a chip`() {
        // 113 主教冲锋 + 雷电主教大火槌 #30000831 的形状：数据里只有 flat.fire = 55。
        val w = weapon(attackBase = mapOf("physical" to 82.0, "lightning" to 82.0), atkAttribute = 1, atkAttribute2 = 1)
        val hit = SkillHit(attribute = "Standard", addBaseAtk = true, flat = mapOf("fire" to 55.0))
        val seg = SkillDamageMath.segment(hit, w, isSpell = false)
        assertEquals(listOf(DamageType.NEUTRAL, DamageType.FIRE, DamageType.LIGHTNING), seg.visibleComponents.map { it.type })
        assertEquals(0, seg.hiddenZeroComponentCount)
        val physical = seg.visibleComponents[0]
        assertNull(physical.motionPercent)
        assertNull(physical.flat)
        assertEquals(82.0, physical.baseAttack)
        assertEquals(219.0, seg.total)
        assertEquals(219.0, SkillDamageMath.hitContribution(hit, w, false).sum())
        assertEquals(
            listOf(DamageType.NEUTRAL, DamageType.LIGHTNING),
            SkillDamageMath.segment(SkillHit(attribute = "Standard", addBaseAtk = true), w, false).visibleComponents.map { it.type },
        )
        assertTrue(SkillDamageMath.segment(SkillHit(attribute = "Standard", addBaseAtk = true), weapon(), false).components.isEmpty())
    }

    @Test
    fun `real data - visible chips always sum to the hit total`() {
        var pairs = 0
        var withHidden = 0
        var onlyBaseAtk = 0
        fun check(hit: SkillHit, weapon: SkillWeapon?, isSpell: Boolean) {
            pairs += 1
            val seg = SkillDamageMath.segment(hit, weapon, isSpell)
            val total = SkillDamageMath.hitContribution(hit, weapon, isSpell).sum()
            val visible = seg.visibleComponents.sumOf { it.amount }
            assertClose(total, visible, 1e-9, "段 ${hit.atkId}：可见芯片之和应当等于整段总量")
            assertEquals(seg.visibleComponents.isEmpty(), !(total > 0.0), "段 ${hit.atkId}：有伤害就必须至少有一个芯片")
            if (seg.hiddenZeroComponentCount > 0) withHidden += 1
            if (seg.visibleComponents.any { it.motionPercent == null && it.flat == null }) onlyBaseAtk += 1
        }
        for (skill in dataset.skills) {
            for (weapon in skills.weaponsFor(skill)) {
                for (hit in skills.hits(skill, weapon)) check(hit, weapon, false)
            }
        }
        for (spell in dataset.spells) for (hit in spell.hits) check(hit, null, true)
        assertTrue(pairs > 8000, "对照样本太少（本版本 8540 对），实际 $pairs")
        assertTrue(withHidden > 0)
        assertTrue(onlyBaseAtk > 0)
    }

    @Test
    fun `real data - corpse piler on rivers of blood shows only slash and fire`() {
        val weapon = assertNotNull(skills.weaponsById[9040000])
        val skill = assertNotNull(skills.skillsById[1177])
        assertTrue(weapon.attack(SkillElement.PHYSICAL) > 0 && weapon.attack(SkillElement.FIRE) > 0)
        listOf(SkillElement.MAGIC, SkillElement.LIGHTNING, SkillElement.HOLY).forEach { assertEquals(0.0, weapon.attack(it)) }
        val hits = skills.hits(skill, weapon)
        // 固定事实：12 段，其中 6 段是专注值不足版；第一段削韧 3.75、削精力 33.75、斩击与火各 45.54。
        assertEquals(12, hits.size)
        assertEquals(6, hits.count { it.noFp })
        skills.segments(skill, weapon).forEach { seg ->
            assertEquals(listOf(DamageType.SLASH, DamageType.FIRE), seg.visibleComponents.map { it.type }, "段 ${seg.atkId}")
            assertEquals(3, seg.hiddenZeroComponentCount)
        }
        val first = hits.first { it.atkId == 303400300 }
        assertClose(3.75, SkillDamageMath.hitPoise(first, weapon), 1e-12, "削韧")
        assertClose(33.75, SkillDamageMath.hitStamina(first, weapon), 1e-12, "削精力")
        val contribution = SkillDamageMath.hitContribution(first, weapon, false)
        assertClose(45.54, contribution[DamageType.SLASH.ordinal], 1e-9, "斩击")
        assertClose(45.54, contribution[DamageType.FIRE.ordinal], 1e-9, "火")
        val segment = skills.segments(skill, weapon).first { it.atkId == 303400300 }
        assertEquals(DamageType.SLASH, segment.physicalType)
        assertEquals(3.75, segment.poise)
        assertEquals("L2 第1段-第1击", segment.displayLabelZh)
        val lowFocus = skills.segments(skill, weapon).first { it.noFp }
        assertTrue(lowFocus.displayLabelZh.startsWith("专注值不足版"), lowFocus.displayLabelZh)
    }

    @Test
    fun `real data - a spell hit only shows attributes that carry flat damage`() {
        val spell = assertNotNull(skills.spellsById[4021], "帚星（4021）必须在数据集里")
        val hit = assertNotNull(spell.hits.firstOrNull { !it.noDamage && it.flat.isNotEmpty() })
        val seg = SkillDamageMath.segment(hit, null, isSpell = true)
        assertTrue(seg.visibleComponents.isNotEmpty())
        assertEquals(0, seg.hiddenZeroComponentCount)
        assertEquals(hit.flat.count { it.value > 0 }, seg.visibleComponents.size)
        seg.visibleComponents.forEach {
            assertTrue((it.flat ?: 0.0) > 0.0)
            assertNull(it.motionPercent)
            assertNull(it.baseAttack)
        }
    }

    @Test
    fun `fpText replaces FP in labels and caveats with the chinese wording`() {
        assertEquals("专注值不足版 L2 第1段-第1击", SkillTextZh.fpText("无FP版 L2 第1段-第1击"))
        assertEquals("专注值不足版 R2", SkillTextZh.fpText("无 FP 版 R2"))
        assertEquals("L2 第3段", SkillTextZh.fpText("L2 第3段"))
        assertEquals("", SkillTextZh.fpText(null))
        assertEquals("专注值不足版 R2", SkillTextZh.fpText("无　FP版 R2"), "全角空格也要吃下")
        assertEquals("12 段（6 段正常版 + 6 段专注值不足版）就是全部", SkillTextZh.fpText("12 段（6 段带 FP + 6 段 No FP）就是全部"))
        assertTrue(dataset.caveats.any { "FP" in it }, "数据集原文里确实还有 FP")
        dataset.caveats.forEach { assertFalse("FP" in SkillTextZh.fpText(it), "页面上不该再出现英文 FP") }
        val raw = skills.skillsById.getValue(1177).hits.filter { it.noFp }
        assertTrue(raw.isNotEmpty() && raw.all { it.labelZh.orEmpty().startsWith("无FP版") }, "数据集原文保持不变")
    }

    // ------------------------------------------------------------------ 伤害构成

    @Test
    fun `real data - reachable bullet hits compute a composition`() {
        var sample: Triple<SkillWeapon, List<SkillHit>, List<SkillHit>>? = null
        outer@ for (skill in dataset.skills) {
            if (skill.hits.isEmpty()) continue
            for (weapon in skills.weaponsFor(skill)) {
                val hits = skills.hits(skill, weapon)
                val bullets = hits.filter { hit ->
                    hit.isBullet && !hit.noDamage &&
                        SkillElement.entries.any { (hit.motionOf(it) ?: 0.0) > 0.0 && weapon.attack(it) > 0.0 }
                }
                if (bullets.isNotEmpty()) {
                    sample = Triple(weapon, hits, bullets)
                    break@outer
                }
            }
        }
        val (weapon, hits, bullets) = assertNotNull(sample, "数据集里应当有可达的、带 motion 的战技子弹段")
        assertTrue(SkillDamageMath.composition(bullets, weapon, false).hasDamage, "子弹段自己就应当算得出非 0 相对值")
        assertTrue(SkillDamageMath.composition(hits.filter { !it.noFp }, weapon, false).hasDamage)
        var motionOnly = 0
        for (skill in dataset.skills) {
            val seen = HashSet<Int>()
            for (w in skills.weaponsFor(skill)) {
                for (hit in skills.hits(skill, w)) {
                    if (!hit.isBullet || !seen.add(hit.atkId)) continue
                    if (hit.motion.isNotEmpty() && hit.flat.isEmpty()) motionOnly += 1
                }
            }
        }
        assertTrue(motionOnly > 0, "可达的子弹段里应当有『只有 motion 没有 flat』的")
    }

    @Test
    fun `composition shares sum to one and noDamage hits never count`() {
        val w = weapon(attackBase = mapOf("physical" to 100.0, "fire" to 100.0), atkAttribute = 0)
        val comp = SkillDamageMath.composition(
            listOf(
                SkillHit(attribute = "WeaponAtkAttribute", motion = mapOf("physical" to 100.0)),
                SkillHit(attribute = "None", motion = mapOf("fire" to 100.0)),
                SkillHit(attribute = "Slash", motion = mapOf("physical" to 999.0), noDamage = true),
            ),
            w, false,
        )
        assertTrue(comp.hasDamage)
        assertClose(1.0, comp.shares.sum(), 1e-9, "占比之和")
        assertEquals(0.5, comp.share(DamageType.SLASH))
        assertEquals(0.5, comp.share(DamageType.FIRE))
        assertEquals(listOf(DamageType.SLASH, DamageType.FIRE), comp.breakdown.map { it.type })
        assertEquals(0.5, comp.physicalShare)
        val empty = SkillDamageMath.composition(emptyList(), w, false)
        assertFalse(empty.hasDamage)
        assertEquals(0.0, empty.total)
        assertTrue(empty.shares.all { it == 0.0 })
    }

    @Test
    fun `real data - a physical plus elemental weapon has both shares above zero`() {
        val weapon = assertNotNull(
            dataset.weapons.firstOrNull { w ->
                w.attack(SkillElement.PHYSICAL) > 0 && w.skillVariant != null &&
                    listOf(SkillElement.MAGIC, SkillElement.FIRE, SkillElement.LIGHTNING, SkillElement.HOLY).any { w.attack(it) > 0 }
            },
        )
        val skill = assertNotNull(dataset.skills.firstOrNull { weapon.id in it.weaponIds })
        val hits = skills.hits(skill, weapon).filter { !it.noFp }
        assertTrue(hits.isNotEmpty())
        val comp = SkillDamageMath.composition(hits, weapon, false)
        assertTrue(comp.hasDamage)
        assertTrue(comp.physicalShare > 0)
        assertTrue(DamageType.entries.filter { !it.isPhysical }.sumOf { comp.share(it) } > 0)
        // 按段换算后汇总（macOS 口径）与按命中直接汇总（Windows 口径）一致。
        val segments = skills.segments(skill, weapon)
        val viaSegments = SkillDamageMath.composition(segments, SkillDamageMath.defaultSelection(skills.hits(skill, weapon)))
        DamageType.entries.forEach { assertClose(comp.share(it), viaSegments.share(it), 1e-12, it.key) }
    }

    @Test
    fun `real data - spell composition only comes from flat values, never physical`() {
        val spell = assertNotNull(dataset.spells.firstOrNull { s -> s.hits.any { (it.flatOf(SkillElement.MAGIC) ?: 0.0) > 0 } })
        val comp = SkillDamageMath.composition(spell.hits, null, true)
        assertTrue(comp.share(DamageType.MAGIC) > 0)
        assertEquals(0.0, comp.physicalShare, "辉石杖的 attackBase 只有 physical，乘上去会凭空造出物理伤害")
    }

    @Test
    fun `poise and stamina are base plus weapon base times mv over 100`() {
        val w = weapon(poiseDamageBase = 10.0, staminaBase = 40.0)
        assertEquals(25.0, SkillDamageMath.hitPoise(SkillHit(poise = 5.0, poiseMv = 200.0), w))
        assertEquals(22.0, SkillDamageMath.hitStamina(SkillHit(stamina = 2.0, staminaMv = 50.0), w))
        assertEquals(0.0, SkillDamageMath.hitPoise(SkillHit(), w))
        assertEquals(5.0, SkillDamageMath.hitPoise(SkillHit(poise = 5.0, poiseMv = 200.0), null), "法术没有武器，只剩段自己的削韧")
    }

    // ------------------------------------------------------------------ 武器分组

    @Test
    fun `weapon groups follow the desktop ordering and cover every weapon`() {
        val multi = assertNotNull(dataset.skills.firstOrNull { it.weaponIds.size > 5 })
        val weapons = skills.weaponsFor(multi)
        assertEquals(multi.weaponIds.size, weapons.size)
        val groups = skills.weaponGroups(multi)
        assertTrue(groups.isNotEmpty())
        assertEquals(weapons.size, groups.sumOf { it.weapons.size })
        groups.forEach { group ->
            assertTrue(group.weapons.all { it.typeLabel == group.wepTypeZh })
            assertEquals(group.weapons.sortedBy { it.id }, group.weapons, "类别内按武器 id 升序")
        }
        groups.zipWithNext().forEach { (a, b) ->
            assertTrue(a.weapons.size > b.weapons.size || (a.weapons.size == b.weapons.size && a.wepTypeZh <= b.wepTypeZh))
        }
        assertEquals(groups[0].weapons[0], skills.defaultWeapon(multi))
    }
}
