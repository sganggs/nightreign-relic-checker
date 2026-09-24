package com.nightreign.relicchecker.gamedata.ranker

import com.nightreign.relicchecker.gamedata.GameDataFormatException
import com.nightreign.relicchecker.gamedata.ranker.RankerTestData.assertClose
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertNotEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

// skills 数据集与选段 / 构成（对应 windows/tests/ranker.test.mjs 的选段、伤害类型、伤害构成、输出手段、
// 「v3：局内战技池、TAE 核实、fpBoth」各节，以及 macOS BuffRankerChecks.swift 的 checkSkillDataset /
// checkSegmentSelection / checkSegmentChips / checkComposition）。
//
// 数据集 schemaVersion 3：weaponIds = 固定引用 ∪ 局内战技池；选段一律读 weapons[].skillVariants[战技 ID]
// （缺失时只对固定战技回退 skillVariant）；variants[].atkIds 已按 TAE 核实，hits[] 里打不出的段标 notInvoked；
// 取段规则是「hit.fpBoth 或 noFp 与开关同侧」；selfOrAllyOnly 段恒带 noDamage。
// v3 修订：spells[] 只收可施放的法术（8100 / 8101「风暴管束者」移出），每个法术带 casterWeaponIds / casterSources。
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
        id: Int = 1,
        swordArtsParamId: Int = -1,
        skillVariants: Map<String, Int> = emptyMap(),
    ) = SkillWeapon(
        id = id, attackBase = attackBase, atkAttribute = atkAttribute, atkAttribute2 = atkAttribute2,
        nameEn = nameEn, wepTypeEn = wepTypeEn, poiseDamageBase = poiseDamageBase, staminaBase = staminaBase,
        swordArtsParamId = swordArtsParamId, skillVariant = skillVariant, skillVariants = skillVariants,
    )

    private val allElements = listOf("physical", "magic", "fire", "lightning", "holy")

    /** 按「使用专注值不足版本」开关取一侧的带伤害段（页面默认勾选的口径：hit.fpBoth || noFp 与开关同侧）。 */
    private fun sideHits(skill: SkillEntry, weapon: SkillWeapon, useNoFp: Boolean): List<SkillHit> =
        skills.hits(skill, weapon).filter { !it.noDamage && it.isOnSide(useNoFp) }

    // ------------------------------------------------------------------ 数据集与固定事实

    @Test
    fun `dataset parses with version, usage boundary and fixed counts`() {
        assertEquals(3, dataset.schemaVersion)
        assertTrue(dataset.gameVersion.startsWith("v1.03.5"), dataset.gameVersion)
        assertEquals("regulation 10350000", dataset.dataVersion)
        assertNotNull(dataset.usage[SkillDataset.USAGE_SELECTION], "选段规则必须来自数据集")
        val boundary = assertNotNull(dataset.usage[SkillDataset.USAGE_BOUNDARY], "skills usage 应含「本数据集的边界」（页面要引用）")
        assertTrue(boundary.isNotBlank())
        assertNotNull(dataset.usage[SkillDataset.USAGE_WEAPON_SOURCES], "武器来源（固定 / 局内战技池）的读法来自数据集")
        assertNotNull(dataset.usage[SkillDataset.USAGE_TAE], "底部要引用「命中段已按 TAE 核实（v3）」这段")
        assertEquals(
            listOf(
                "选段（必读）", "近战武器段", "伤害类型（斩 / 打 / 突）", "法术 / 子弹段", "削韧", "本数据集的边界",
                "战技来源（v3）", "法术来源（v3）", "命中段已按 TAE 核实（v3）",
            ),
            dataset.usage.keys.toList(),
            "usage 的键按数据顺序（v3 多了三个：战技来源、法术来源（修订）、TAE 核实）",
        )
        assertNotNull(dataset.usage[SkillDataset.USAGE_SPELL_SOURCES], "法术来源（可施放口径）的读法来自数据集")
        assertEquals(11, dataset.caveats.size)
        assertEquals(3, dataset.sources.size)
        // 固定事实（与数据集 counts 一致）
        assertEquals(1793, dataset.weapons.size)
        assertEquals(187, dataset.skills.size)
        assertEquals(158, dataset.spells.size, "v3 修订：只收可施放的法术（去掉 8100 / 8101）")
        assertEquals(158, dataset.count("spells"))
        assertEquals(1793, dataset.count("weapons"))
        assertEquals(187, dataset.count("skills"))
        assertEquals(2197, dataset.count("hits"), "8100 / 8101 的 4 段随之移出")
        assertEquals(166, dataset.count("skillsWithHits"))
        assertEquals(166, dataset.skills.count { it.hits.isNotEmpty() })
        assertEquals(185, dataset.count("skillsWithWeapons"))
        assertEquals(185, dataset.skills.count { it.weaponIds.isNotEmpty() }, "v2 只有 133 个战技有武器")
        assertEquals(133, dataset.count("skillsWithFixedWeapons"))
        assertEquals(52, dataset.count("skillsPoolOnly"))
        assertEquals(
            52,
            dataset.skills.count { skill -> skill.weaponSources.isNotEmpty() && skill.weaponSources.none { it.fixed } },
            "只在局内战技池里出现的战技",
        )
        assertEquals(137, dataset.spells.count { it.hits.isNotEmpty() })
        assertEquals(dataset.count("spellsWithHits"), dataset.spells.count { it.hits.isNotEmpty() })
        assertEquals(65, dataset.spells.count { it.outputClass == OutputClass.SORCERY })
        assertEquals(93, dataset.spells.count { it.outputClass == OutputClass.INCANTATION })
        assertTrue(dataset.weapons.all { it.atkAttribute in 0..3 && it.atkAttribute2 in 0..3 })
        assertTrue(dataset.weapons.any { it.attackBase.isNotEmpty() })
        assertEquals("1793 把武器 · 187 个战技 · 158 个法术", skills.summary)

        // v3：TAE 核实与分侧标记的计数（counts 里混着布尔值 taeVerified）。
        assertTrue(dataset.taeVerified, "本版本的 variants 已按 TAE 核实")
        assertEquals(34, dataset.count("hitsNotInvoked"))
        assertEquals(24, dataset.count("hitsNotInvokedDamaging"))
        assertEquals(213, dataset.count("hitsNoFpByTae"))
        assertEquals(19, dataset.count("hitsFpBoth"))
        assertEquals(36, dataset.count("hitsSelfOrAllyOnly"))
        val skillHits = dataset.skills.flatMap { it.hits }
        assertEquals(34, skillHits.count { it.notInvoked })
        assertTrue(skillHits.filter { it.notInvoked }.all { !it.notInvokedReason.isNullOrEmpty() }, "notInvoked 段都带原因")
        assertEquals(213, skillHits.count { it.noFpSource == "tae" })
        assertEquals(19, skillHits.count { it.fpBoth })
        assertEquals(36, (skillHits + dataset.spells.flatMap { it.hits }).count { it.selfOrAllyOnly })
        assertEquals(listOf(400, 401, 404, 405, 406, 1169), dataset.skills.filter { it.taeUnmatched }.map { it.id }, "弓系战技匹配不到动画")

        // v3 新字段的结构：weaponSources 与 weaponIds 一一对应；每把武器都有 skillIds；战技池非空。
        dataset.skills.forEach { skill ->
            assertEquals(skill.weaponIds, skill.weaponSources.map { it.id }, "${skill.id} 的 weaponSources 与 weaponIds 一一对应")
        }
        assertTrue(dataset.weapons.all { it.skillIds.isNotEmpty() }, "每把武器都有 skillIds")
        assertEquals(1239, dataset.weapons.count { it.skillVariants.isNotEmpty() })
        assertEquals(dataset.count("weaponsWithSkillVariants"), dataset.weapons.count { it.skillVariants.isNotEmpty() })
        assertEquals(496, dataset.swordArtsPools.size)
        assertEquals(dataset.count("swordArtsPools"), dataset.swordArtsPools.size)
        assertEquals(dataset.count("swordArtsPoolEntries"), dataset.swordArtsPools.values.sumOf { it.size })
        assertEquals(1150, dataset.weapons.count { it.skillVariant != null }, "旧的 skillVariant 仍在（只指固定战技）")
    }

    @Test
    fun `wrong schema version is rejected`() {
        val error = assertFailsWith<GameDataFormatException> {
            RankerParsers.skills("""{"schemaVersion":1,"weapons":[],"skills":[],"spells":[]}""")
        }
        assertTrue(error.message!!.contains("nightreign-skills-v1.03.5.json"))
        // v2 缺 skillVariants / weaponSources / TAE 核实，选段口径不同，同样拒绝。
        val v2 = assertFailsWith<GameDataFormatException> {
            RankerParsers.skills("""{"schemaVersion":2,"weapons":[],"skills":[],"spells":[]}""")
        }
        assertTrue(v2.message!!.contains("只支持 3"), v2.message)
    }

    @Test
    fun `v3 revision - spells only lists castable spells, each with its caster weapons`() {
        // Magic 残留行 8100 / 8101「风暴管束者」没有任何施法器池引用（本作是战技 1200）：不在 spells[]，也不进输出手段列表
        // （修订前它们各带 2 段固定值，会被当成玩家法术参与排名）。
        listOf(8100, 8101).forEach { id ->
            assertNull(skills.spellsById[id], "$id 是 Magic 残留行，不在 spells[]")
            assertTrue(skills.outputs.none { !it.isSkill && it.entryId == id }, "$id 不可施放，不得进输出手段列表")
        }
        val stormRuler = assertNotNull(skills.skillsById[1200], "同名战技 1200 仍在")
        assertTrue(stormRuler.weaponIds.isNotEmpty(), "战技 1200 有武器")
        // coverage 不进模型：直接读原始 JSON，核对不可施放的恰好是这两行、都指向同名战技 1200。
        val coverage = Json.parseToJsonElement(RankerTestData.skillsText).jsonObject.getValue("coverage").jsonObject
        val dropped = coverage.getValue("spellsNotCastable").jsonArray.map { it.jsonObject }
        assertEquals(listOf(8100, 8101), dropped.map { it.getValue("id").jsonPrimitive.int })
        dropped.forEach { one ->
            assertEquals(listOf(1200), one.getValue("sameNameSkillIds").jsonArray.map { it.jsonPrimitive.int })
        }
        assertEquals(2, dataset.count("spellsDropped"))
        assertEquals(dataset.count("spellsCastable"), dataset.spells.size)

        // 每个法术都有施法器：魔法＝手杖（57）、祷告＝圣印记（61），与页面按施法器判定 attackWeaponTypes 的口径一致。
        dataset.spells.forEach { spell ->
            assertTrue(spell.casterWeaponIds.isNotEmpty(), "${spell.id} 缺 casterWeaponIds")
            assertEquals(spell.casterWeaponIds.sorted(), spell.casterWeaponIds, "${spell.id} 的施法器按 ID 升序")
            spell.casterWeaponIds.forEach { id ->
                val weapon = assertNotNull(skills.weaponsById[id], "${spell.id} 的施法器 $id 不在 weapons[]")
                assertEquals(spell.outputClass.casterWepType, weapon.wepType, "${spell.id} 的施法器 $id 类别不对")
            }
            // casterSources 与 casterWeaponIds 一一对应；每个池都真的含这个法术（权重相同、> 0），
            // 而且是这把施法器某个可达 custom 行的法术槽（customMagicTables 的 _1 / _2）。
            assertEquals(spell.casterWeaponIds, spell.casterSources.map { it.id }, "${spell.id} 的 casterSources 与 casterWeaponIds 一一对应")
            spell.casterSources.forEach { source ->
                assertTrue(source.draws.isNotEmpty(), "${spell.id} @ ${source.id} 没有池")
                val slots = skills.weaponsById.getValue(source.id).customMagicTables.flatMap { it.drop(1) }.toSet()
                source.draws.forEach { draw ->
                    val (own, total) = assertNotNull(dataset.magicPoolWeight(draw.poolId, spell.id), "池 ${draw.poolId} 应含 ${spell.id}")
                    assertEquals(draw.weight, own, "${spell.id} 在池 ${draw.poolId} 的权重")
                    assertTrue(own in 1..total, "${spell.id} 在池 ${draw.poolId} 的权重应为正")
                    assertTrue(draw.poolId in slots, "池 ${draw.poolId} 应是施法器 ${source.id} 某个 custom 行的法术槽")
                    assertTrue(draw.customRows >= 1)
                }
            }
        }
        // 施法器 28 把（圣印记 9、手杖 19）；计数与数据集 counts 一致。
        val casters = dataset.weapons.filter { it.customMagicTables.isNotEmpty() }
        assertEquals(28, casters.size)
        assertEquals(19, casters.count { it.wepType == OutputClass.SORCERY.casterWepType })
        assertEquals(9, casters.count { it.wepType == OutputClass.INCANTATION.casterWepType })
        assertEquals(dataset.count("casterWeapons"), dataset.spells.flatMap { it.casterWeaponIds }.toSet().size)
        assertEquals(dataset.count("spellWeaponPairs"), dataset.spells.sumOf { it.casterWeaponIds.size })
        assertEquals(dataset.count("magicPools"), dataset.magicPools.size)
        assertEquals(dataset.count("magicPoolEntries"), dataset.magicPools.values.sumOf { it.size })
        assertEquals(19, skills.spellsById.getValue(4021).casterWeaponIds.size, "帚星：19 把手杖都能带")
        assertNull(dataset.magicPoolWeight(-1, 4021), "没有这个池")
    }

    // ------------------------------------------------------------------ 输出手段列表

    /**
     * 参考实现：一个战技能不能进列表——不经被测代码，直接读 weapons[].skillVariants → variants[i].atkIds，
     * 任一把武器（固定或局内战技池）的任一段按「攻击力 × motion / 100 + flat（addBaseAtk 再加一份）」算得出非 0 即可
     * （Windows ranker_crosscheck.test.mjs 的 referenceSkillListable）。
     */
    private fun referenceListable(skill: SkillEntry): Boolean {
        if (skill.hits.isEmpty() || skill.weaponIds.isEmpty()) return false
        return skill.weaponIds.any { id ->
            val weapon = dataset.weapons.firstOrNull { it.id == id } ?: return@any false
            val position = weapon.skillVariants[skill.id.toString()] ?: return@any false
            val variant = skill.variants.getOrNull(position) ?: return@any false
            skill.hits.filter { it.atkId in variant.atkIds && !it.noDamage }.any { hit ->
                allElements.any { key ->
                    val attack = weapon.attackBase[key] ?: 0.0
                    val value = attack * (hit.motion[key] ?: 0.0) / 100 + (hit.flat[key] ?: 0.0) + (if (hit.addBaseAtk) attack else 0.0)
                    value > 0
                }
            }
        }
    }

    @Test
    fun `output list only takes skills and spells that can compute a composition`() {
        // 固定事实：战技 155 + 法术 119（魔法 58、祷告 61），与 Windows 对拍行 OUTPUTS 一致。
        // v3 把局内战技池算进 weaponIds，v2 里没有武器的 41 个战技进了列表（114 → 155）；
        // v3 修订的 spells[] 只收可施放的，8100 / 8101「风暴管束者」（各 2 段固定值）不再进列表（121 → 119）。
        assertEquals(155, skills.skillOutputCount)
        assertEquals(119, skills.spellOutputCount)
        assertEquals(58, skills.outputs.count { it.outputClass == OutputClass.SORCERY })
        assertEquals(61, skills.outputs.count { it.outputClass == OutputClass.INCANTATION })
        assertEquals(11, skills.skillsWithoutDamage, "纯增益 / 格挡类的战技")
        assertEquals(18, skills.spellsWithoutDamage, "恢复／庇佑类法术")
        assertEquals(21, skills.skillsWithoutHits)
        assertEquals(21, skills.spellsWithoutHits)
        assertEquals(0, skills.skillsWithoutWeapons, "v3：有命中段的战技都有武器（固定或局内战技池）")

        // 收录口径：有命中段 + （战技）至少一把武器（固定或局内战技池）+ 至少能算出一段非 0 相对值。
        val skillIds = skills.outputs.filter { it.isSkill }.map { it.entryId }.toSet()
        for (skill in dataset.skills) {
            val usable = skill.hits.isNotEmpty() && skill.weaponIds.isNotEmpty() && skills.skillHasDamage(skill)
            assertEquals(usable, skill.id in skillIds, "${skill.id} 的收录判定")
            assertEquals(referenceListable(skill), skill.id in skillIds, "${skill.id} 与参考实现不一致")
        }
        // 没有武器的只剩占位条目（1 无战技、9999 ？？？），它们也没有命中段；「有段但没有武器」的排除规则用合成数据钉住。
        val weaponless = dataset.skills.filter { it.weaponIds.isEmpty() }
        assertEquals(listOf(1, 9999), weaponless.map { it.id }, "没有武器的只剩两个占位条目")
        weaponless.forEach { assertTrue(it.hits.isEmpty(), "${it.id} 是占位条目，不该有命中段") }
        val orphanHit = SkillHit(atkId = 1, attribute = "Slash", motion = mapOf("physical" to 100.0))
        val synthetic = SkillDataIndex(
            SkillDataset(
                schemaVersion = 3,
                weapons = listOf(weapon(attackBase = mapOf("physical" to 100.0), id = 5, atkAttribute = 0, skillVariants = mapOf("71" to 0))),
                skills = listOf(
                    SkillEntry(id = 70, nameZh = "有段无武器", hits = listOf(orphanHit), variants = listOf(SkillVariant(atkIds = listOf(1)))),
                    SkillEntry(
                        id = 71, nameZh = "有段有武器", weaponIds = listOf(5), hits = listOf(orphanHit),
                        variants = listOf(SkillVariant(atkIds = listOf(1), weaponIds = listOf(5))),
                    ),
                ),
            ),
        )
        assertEquals(listOf(71), synthetic.outputs.map { it.entryId }, "有段但没有武器的战技选不出武器，不进列表")
        assertEquals(1, synthetic.skillsWithoutWeapons)
        assertEquals(0, synthetic.skillsWithoutDamage, "没有武器的不算「算不出构成」")

        // 只在局内战技池里出现的战技（v2 里一把武器都没有）现在能选：风暴刃 210、狩猎巨人 116。
        listOf(210 to 64, 116 to 50).forEach { (id, count) ->
            val skill = skills.skillsById.getValue(id)
            assertTrue(skill.weaponSources.all { !it.fixed && it.pool.isNotEmpty() }, "$id 只来自战技池")
            val output = assertNotNull(skills.output("skill-$id"), "$id 应当进输出手段列表")
            assertEquals(count, output.weaponCount)
            assertEquals("战技 · $count 把武器", output.subtitleZh)
        }

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
    fun `selectHits always follows skillVariants to variants atkIds, never a union`() {
        val multi = assertNotNull(dataset.skills.firstOrNull { it.variants.size > 1 }, "数据集里应当有多套动作的战技")
        val seen = HashSet<Int>()
        multi.variants.forEachIndexed { position, variant ->
            val weapon = skills.weaponsById.getValue(variant.weaponIds[0])
            assertEquals(position, weapon.skillVariants[multi.id.toString()], "variant 的下标必须就是武器的 skillVariants[战技 ID]")
            assertEquals(position, weapon.variantIndex(multi.id))
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

        // 全量：每个 (战技, 武器) 对（固定与局内战技池）都由 skillVariants 指到含这把武器的那一套。
        var pairs = 0
        for (skill in dataset.skills) {
            if (skill.variants.isEmpty()) continue
            for (id in skill.weaponIds) {
                val weapon = skills.weaponsById.getValue(id)
                val position = assertNotNull(weapon.variantIndex(skill.id), "${skill.id} × $id 找不到动作套")
                assertEquals(position, weapon.skillVariants[skill.id.toString()])
                assertTrue(id in skill.variants[position].weaponIds, "${skill.id} × $id 指错了套")
                val wanted = skill.variants[position].atkIds.toSet()
                assertEquals(skill.hits.filter { it.atkId in wanted }.map { it.atkId }, skills.hits(skill, weapon).map { it.atkId })
                if (weapon.swordArtsParamId == skill.id) assertEquals(weapon.skillVariant, position, "固定战技的旧 skillVariant 与 skillVariants 一致")
                pairs += 1
            }
        }
        assertEquals(6567, pairs, "局内战技池的武器也要逐对验到")
    }

    @Test
    fun `a skill drawn from the in-run pool never borrows the weapon's fixed skillVariant`() {
        // 1080000 蝎尾针：固定战技 109 连击（skillVariant=1），局内还能抽到 103 回旋斩（skillVariants["103"]=0）。
        // 旧写法拿 skillVariant 去套 103，会选到别的武器类别的那一套动作。
        val weapon = assertNotNull(skills.weaponsById[1080000])
        val pool = assertNotNull(skills.skillsById[103])
        assertEquals(109, weapon.swordArtsParamId)
        assertEquals(1, weapon.skillVariant)
        val own = assertNotNull(weapon.skillVariants["103"])
        assertNotEquals(own, weapon.skillVariant, "这个例子要能区分两种写法")
        assertNotEquals(pool.variants[own].atkIds.toSet(), pool.variants[weapon.skillVariant!!].atkIds.toSet())
        assertEquals(own, weapon.variantIndex(103))
        assertEquals(pool.variants[own], skills.selectVariant(pool, weapon))
        assertEquals(
            pool.hits.filter { it.atkId in pool.variants[own].atkIds }.map { it.atkId },
            skills.hits(pool, weapon).map { it.atkId },
        )
        assertEquals(WeaponSourceKind.POOL, skills.weaponSourceKind(pool, weapon))
        assertEquals(WeaponSourceKind.FIXED, skills.weaponSourceKind(skills.skillsById.getValue(109), weapon))

        // 回退规则：缺 skillVariants 条目时才用 skillVariant，而且只对武器的固定战技（swordArtsParamId）。
        val skill = SkillEntry(
            id = 7,
            hits = listOf(SkillHit(atkId = 1), SkillHit(atkId = 2)),
            variants = listOf(SkillVariant(atkIds = listOf(1), weaponIds = listOf(9)), SkillVariant(atkIds = listOf(2), weaponIds = listOf(9))),
        )
        assertEquals(1, weapon(id = 9, skillVariants = mapOf("7" to 1), skillVariant = 0, swordArtsParamId = 7).variantIndex(7), "skillVariants 优先")
        assertEquals(1, weapon(id = 9, skillVariant = 1, swordArtsParamId = 7).variantIndex(7), "缺条目时回退固定战技的 skillVariant")
        val notFixed = weapon(id = 9, skillVariant = 1, swordArtsParamId = 8)
        assertNull(notFixed.variantIndex(7), "skillVariant 只指固定战技，不能拿去套别的战技")
        assertEquals(emptyList(), SkillDataIndex.selectHits(skill, notFixed))
        assertEquals(listOf(2), SkillDataIndex.selectHits(skill, weapon(id = 9, skillVariants = mapOf("7" to 1))).map { it.atkId })
    }

    @Test
    fun `every skill and weapon pair selects a non-empty, in-variant set without noVariant or notInvoked hits`() {
        var checked = 0
        for (skill in dataset.skills) {
            if (skill.variants.isEmpty()) continue
            for (weapon in skills.weaponsFor(skill)) {
                val index = assertNotNull(weapon.variantIndex(skill.id), "${skill.id} × ${weapon.id}")
                checked += 1
                val allowed = skill.variants[index].atkIds.toSet()
                val hits = skills.hits(skill, weapon)
                assertTrue(hits.isNotEmpty(), "${skill.id} × ${weapon.id} 选不出段")
                assertTrue(hits.none { it.noVariant }, "${skill.id} × ${weapon.id} 选到了 noVariant 段")
                assertTrue(hits.none { it.notInvoked }, "${skill.id} × ${weapon.id} 选到了 TAE 判为打不出的段")
                assertTrue(hits.all { it.atkId in allowed }, "${skill.id} × ${weapon.id} 选段超出 variants[].atkIds")
            }
        }
        assertTrue(checked > 6000, "参与选段校验的 (战技, 武器) 对太少：$checked")
    }

    @Test
    fun `a weapon without a variant index for the skill hits nothing`() {
        val skill = dataset.skills.first { it.variants.isNotEmpty() }
        assertNull(skills.selectVariant(skill, weapon()))
        assertEquals(emptyList(), skills.hits(skill, weapon()))
        assertEquals(emptyList(), skills.hits(skill, null))
        assertEquals(emptyList(), SkillDataIndex.selectHits(SkillEntry(hits = emptyList()), weapon()))
        val outOfRange = weapon(skillVariants = mapOf(skill.id.toString() to skill.variants.size))
        assertNull(skills.selectVariant(skill, outOfRange), "越界的下标同样打不出段")
        assertEquals(emptyList(), skills.hits(skill, outOfRange))
    }

    @Test
    fun `without variants selectHits falls back to a single ctx - weapon name, then type, then missing ctx`() {
        val skill = SkillEntry(
            hits = listOf(SkillHit(atkId = 1, ctx = "Dagger"), SkillHit(atkId = 2, ctx = "Reduvia"), SkillHit(atkId = 3)),
        )
        assertEquals(listOf(2), SkillDataIndex.selectHits(skill, weapon(nameEn = "Reduvia", wepTypeEn = "Dagger")).map { it.atkId }, "武器名优先")
        assertEquals(listOf(1), SkillDataIndex.selectHits(skill, weapon(nameEn = "Misericorde", wepTypeEn = "Dagger")).map { it.atkId }, "退到武器类别")
        assertEquals(listOf(3), SkillDataIndex.selectHits(skill, weapon(nameEn = "X", wepTypeEn = "Y")).map { it.atkId }, "最后才用 ctx 缺失的那组")

        // 回退路径直接读 hits[]：TAE 判为打不出的段（notInvoked）与不带伤害的段（noDamage）一律剔掉。
        val tae = SkillEntry(
            hits = listOf(
                SkillHit(atkId = 11, ctx = "Dagger", notInvoked = true, notInvokedReason = "gated"),
                SkillHit(atkId = 12, ctx = "Dagger", noDamage = true),
                SkillHit(atkId = 13, ctx = "Dagger"),
                SkillHit(atkId = 14, notInvoked = true),
                SkillHit(atkId = 15),
            ),
        )
        assertEquals(listOf(13), SkillDataIndex.selectHits(tae, weapon(nameEn = "Misericorde", wepTypeEn = "Dagger")).map { it.atkId })
        assertEquals(listOf(15), SkillDataIndex.selectHits(tae, weapon(nameEn = "X", wepTypeEn = "Y")).map { it.atkId })
        val onlyDead = SkillEntry(hits = listOf(SkillHit(atkId = 21, ctx = "Dagger", notInvoked = true), SkillHit(atkId = 22)))
        assertEquals(listOf(22), SkillDataIndex.selectHits(onlyDead, weapon(wepTypeEn = "Dagger")).map { it.atkId }, "剔掉 notInvoked 之后这一类没有段，才往下退")
        assertEquals(listOf(12, 13, 15), SkillDataIndex.invokedHits(tae.hits).map { it.atkId })
        // 法术不做 TAE 过滤：真实数据里没有 notInvoked 的法术段，spellHits 原样返回。
        dataset.spells.forEach { spell -> assertEquals(spell.hits, skills.spellHits(spell), "${spell.id}") }
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

        // fpBoth：两侧动画都会打出的段，开关在哪一侧都勾上（取段规则 hit.fpBoth || noFp 同侧）。
        val shared = hits + SkillHit(atkId = 4, fpBoth = true)
        assertEquals(true, SkillDamageMath.hitOverridesFor(shared, HitAction.ALL, false)[4])
        assertEquals(true, SkillDamageMath.hitOverridesFor(shared, HitAction.ALL, true)[4], "专注值不足侧也要计入 fpBoth 段")
        assertEquals(setOf(1, 4), SkillDamageMath.defaultSelection(shared))
        assertEquals(setOf(2, 4), SkillDamageMath.defaultSelection(shared, useNoFp = true))
        assertTrue(SkillDamageMath.isHitEnabled(shared[3], emptyMap(), true))
        assertFalse(SkillDamageMath.isHitEnabled(shared[3], mapOf(4 to false), true), "手动勾掉照样生效")
        assertTrue(SkillHit(fpBoth = true).isOnSide(true) && SkillHit(fpBoth = true).isOnSide(false))
        assertFalse(SkillHit(noFp = true).isOnSide(false))
        assertFalse(SkillHit().isOnSide(true))

        // 真实数据：全选之后相对值合计不会翻倍（= 与默认勾选一致）。
        val pair = dataset.weapons.asSequence().filter { it.skillVariants.isNotEmpty() }.mapNotNull { weapon ->
            dataset.skills.firstOrNull { skill ->
                weapon.id in skill.weaponIds && skills.hits(skill, weapon).any { it.noFp }
            }?.let { weapon to it }
        }.firstOrNull()
        val (weapon, skill) = assertNotNull(pair, "数据集里应当有带专注值不足版本的战技")
        val picked = skills.hits(skill, weapon)
        val overrides = SkillDamageMath.hitOverridesFor(picked, HitAction.ALL, false)
        val chosen = picked.filter { overrides[it.atkId] == true }
        val fallback = picked.filter { !it.noDamage && (it.fpBoth || !it.noFp) }
        assertEquals(fallback.map { it.atkId }, chosen.map { it.atkId })
        assertEquals(
            SkillDamageMath.composition(fallback, weapon, false).total,
            SkillDamageMath.composition(chosen, weapon, false).total,
        )
        val normal = SkillDamageMath.defaultSelection(picked)
        val lowFocus = SkillDamageMath.defaultSelection(picked, useNoFp = true)
        assertTrue(lowFocus.isNotEmpty(), "专注值不足侧要有段")
        assertEquals(
            picked.filter { it.fpBoth && !it.noDamage }.map { it.atkId }.toSet(),
            normal.intersect(lowFocus),
            "正常版与专注值不足版必须互斥（两侧共用的 fpBoth 段除外）",
        )
    }

    // ------------------------------------------------------------------ v3：局内战技池、TAE 核实、fpBoth

    @Test
    fun `storm blade 210 is pool-only - 3 melee hits plus 1 bullet on the normal side, 3 on the low focus side`() {
        val skill = skills.skillsById.getValue(210)
        val weapons = skills.weaponsFor(skill)
        assertEquals(64, weapons.size)
        assertEquals(skill.weaponIds.size, weapons.size)
        weapons.forEach { weapon ->
            assertEquals(WeaponSourceKind.POOL, skills.weaponSourceKind(skill, weapon))
            val fp = sideHits(skill, weapon, false)
            val noFp = sideHits(skill, weapon, true)
            assertEquals(3, fp.count { !it.isBullet }, "${weapon.id} 正常侧应是 3 段近战")
            assertEquals(1, fp.count { it.isBullet }, "${weapon.id} 正常侧另有 1 段飞刃子弹")
            assertEquals(3, noFp.size, "${weapon.id} 专注值不足侧 3 段")
            assertTrue(noFp.all { it.noFp && !it.isBullet })
            val fpIds = fp.map { it.atkId }.toSet()
            assertTrue(noFp.none { it.atkId in fpIds }, "两侧互为替代，不共段")
        }
        // 411–413 是 TAE 补标的无 FP 段：行名没写 No FP，labelZh 补了「无FP版」，页面显示成「专注值不足版」。
        listOf(300000411, 300000412, 300000413).forEach { id ->
            val hit = skill.hits.first { it.atkId == id }
            assertTrue(hit.noFp)
            assertEquals("tae", hit.noFpSource)
            assertTrue(hit.labelZh.orEmpty().startsWith("无FP版"), hit.labelZh)
            assertTrue(hit.displayLabelZh.startsWith("专注值不足版"), hit.displayLabelZh)
        }
        val weapon = weapons[0]
        assertTrue(SkillDamageMath.composition(sideHits(skill, weapon, false), weapon, false).hasDamage)
        assertTrue(SkillDamageMath.composition(sideHits(skill, weapon, true), weapon, false).hasDamage)
    }

    @Test
    fun `hunt the giant 116 is pool-only with one hit per side`() {
        val skill = skills.skillsById.getValue(116)
        val weapons = skills.weaponsFor(skill)
        assertEquals(50, weapons.size)
        weapons.forEach { weapon ->
            assertEquals(WeaponSourceKind.POOL, skills.weaponSourceKind(skill, weapon))
            assertEquals(listOf(301700910), sideHits(skill, weapon, false).map { it.atkId }, "${weapon.id}")
            assertEquals(listOf(301700915), sideHits(skill, weapon, true).map { it.atkId }, "${weapon.id}")
        }
        assertEquals("tae", skill.hits.first { it.atkId == 301700915 }.noFpSource)
    }

    @Test
    fun `great-serpent hunt 1188 keeps only the two melee L2 hits and their low focus versions`() {
        val skill = skills.skillsById.getValue(1188)
        val weapon = skills.weaponsById.getValue(17030000)
        assertEquals(listOf(17030000), skill.weaponIds)
        val source = skill.weaponSources.single()
        assertTrue(source.fixed && source.pool.isNotEmpty(), "大蛇狩猎矛：固定战技，局内战技池也抽得到")
        assertEquals(WeaponSourceKind.FIXED, source.kind, "两者都成立时只标固定")
        assertEquals(WeaponSourceKind.FIXED, skills.weaponSourceKind(skill, weapon))
        val hits = skills.hits(skill, weapon)
        assertEquals(listOf(301703950, 301703951, 301703970, 301703971), hits.map { it.atkId })
        assertEquals(listOf(301703950, 301703951), sideHits(skill, weapon, false).map { it.atkId })
        assertEquals(listOf(301703970, 301703971), sideHits(skill, weapon, true).map { it.atkId })
        val dead = skill.hits.filter { it.notInvoked }
        assertEquals(listOf(301703900, 301703901, 301703905, 301703955, 301703975), dead.map { it.atkId })
        assertEquals(listOf("gated", "gated"), dead.take(2).map { it.notInvokedReason }, "光之束两段被玩家拿不到的 stateInfo 门控")
        dead.forEach { assertFalse(it in hits, "${it.atkId} 不该进选段") }
        assertEquals(setOf(301703950, 301703951), SkillDamageMath.defaultSelection(hits))
        assertEquals(setOf(301703970, 301703971), SkillDamageMath.defaultSelection(hits, useNoFp = true))
    }

    @Test
    fun `notInvoked hits never reach any selection and selfOrAllyOnly hits always carry noDamage`() {
        var notInvoked = 0
        var selfOrAlly = 0
        val full = weapon(attackBase = allElements.associateWith { 100.0 })
        for (skill in dataset.skills) {
            notInvoked += skill.hits.count { it.notInvoked }
            for (weapon in skills.weaponsFor(skill)) {
                skills.hits(skill, weapon).forEach { hit ->
                    assertFalse(hit.notInvoked, "${skill.id} × ${weapon.id} 选进了 ${hit.atkId}")
                }
            }
        }
        for (hit in dataset.skills.flatMap { it.hits } + dataset.spells.flatMap { it.hits }) {
            if (!hit.selfOrAllyOnly) continue
            selfOrAlly += 1
            assertTrue(hit.noDamage, "${hit.atkId} 只打自己 / 队友，必须带 noDamage")
            assertTrue(SkillDamageMath.hitContribution(hit, full, false).all { it == 0.0 })
            assertFalse(hit.atkId in SkillDamageMath.hitOverridesFor(listOf(hit), HitAction.ALL, false), "全选也不勾")
            assertFalse(SkillDamageMath.isHitEnabled(hit, mapOf(hit.atkId to true), false))
        }
        assertEquals(dataset.count("hitsNotInvoked"), notInvoked, "notInvoked 段数与数据集 counts 一致")
        assertEquals(dataset.count("hitsSelfOrAllyOnly"), selfOrAlly)
    }

    @Test
    fun `fpBoth hits count on both sides - the low focus side no longer drops them`() {
        var fpBoth = 0
        dataset.skills.forEach { skill ->
            skill.hits.filter { it.fpBoth }.forEach { hit ->
                fpBoth += 1
                assertFalse(hit.noFp, "${hit.atkId}：fpBoth 与 noFp 互斥")
            }
        }
        assertEquals(dataset.count("hitsFpBoth"), fpBoth)

        // 1024 唤矛仪式：全部带伤害的段都是两侧共用的子弹。旧写法（noFp 与开关同侧）在专注值不足侧一段都取不到。
        val ritual = skills.skillsById.getValue(1024)
        val spear = skills.weaponsById.getValue(ritual.weaponIds[0])
        val fp = sideHits(ritual, spear, false)
        val noFp = sideHits(ritual, spear, true)
        assertEquals(listOf(301612910, 301612911), fp.map { it.atkId })
        assertTrue(fp.all { it.fpBoth })
        assertEquals(fp.map { it.atkId }, noFp.map { it.atkId }, "两侧取到同一批段")
        assertTrue(SkillDamageMath.composition(noFp, spear, false).hasDamage, "专注值不足侧也算得出构成")
        val old = skills.hits(ritual, spear).filter { !it.noDamage && it.noFp }
        assertTrue(old.isEmpty(), "旧写法在这里会丢段，这个例子才有意义")

        // 1021 毁灭灵火：唯一一段就是两侧共用的。
        val flame = skills.skillsById.getValue(1021)
        val sword = skills.weaponsById.getValue(flame.weaponIds[0])
        assertEquals(listOf(303401400), sideHits(flame, sword, true).map { it.atkId })
        assertEquals(setOf(303401400), SkillDamageMath.defaultSelection(skills.hits(flame, sword), useNoFp = true))

        // 218 伟哉卡利亚：300200872 两侧共用，另外各有自己一侧的段；全部 52 把武器都这样。
        val glintblade = skills.skillsById.getValue(218)
        val weapons = skills.weaponsFor(glintblade)
        assertEquals(52, weapons.size)
        weapons.forEach { weapon ->
            val fpIds = sideHits(glintblade, weapon, false).map { it.atkId }
            val noFpIds = sideHits(glintblade, weapon, true).map { it.atkId }
            assertTrue(300200872 in fpIds && 300200872 in noFpIds, "${weapon.id}")
            assertTrue(fpIds.size > 1 && noFpIds.size > 1, "${weapon.id}")
        }
        assertEquals(true, SkillDamageMath.hitOverridesFor(skills.hits(glintblade, weapons[0]), HitAction.ALL, true)[300200872])
    }

    @Test
    fun `weapon sources - fixed marks exactly the weapons whose own skill it is, both sources count as fixed`() {
        var fixed = 0
        var pool = 0
        for (skill in dataset.skills) {
            for (source in skill.weaponSources) {
                val weapon = skills.weaponsById.getValue(source.id)
                val kind = assertNotNull(skills.weaponSourceKind(skill, weapon), "${skill.id} × ${source.id} 没有来源")
                assertEquals(source.kind, kind)
                assertEquals(kind == WeaponSourceKind.FIXED, weapon.swordArtsParamId == skill.id, "${skill.id} × ${source.id}")
                if (kind == WeaponSourceKind.FIXED) fixed += 1 else pool += 1
                // 池项的权重与顶层 swordArtsPools 对得上（概率 = 权重 / 池内权重之和）。
                source.draws.forEach { draw ->
                    val (own, total) = assertNotNull(dataset.poolWeight(draw.poolId, skill.id), "池 ${draw.poolId} 里没有 ${skill.id}")
                    assertEquals(draw.weight, own)
                    assertTrue(total >= own && draw.customRows > 0)
                }
            }
        }
        assertEquals(dataset.count("weaponSkillPairsFixed"), fixed)
        assertEquals(dataset.count("weaponSkillPairs") - fixed, pool)
        assertEquals(dataset.count("weaponSkillPairsBoth"), dataset.skills.sumOf { skill -> skill.weaponSources.count { it.fixed && it.pool.isNotEmpty() } })
        // 旧数据没有 weaponSources：按 swordArtsParamId 判固定，判不出的不标。
        val bare = SkillEntry(id = 5)
        assertEquals(WeaponSourceKind.FIXED, skills.weaponSourceKind(bare, weapon(swordArtsParamId = 5)))
        assertNull(skills.weaponSourceKind(bare, weapon(swordArtsParamId = 6)))
        // 三端同名同值的四条文案。
        assertEquals("固定战技", WeaponSourceKind.FIXED.title)
        assertEquals("局内可抽到", WeaponSourceKind.POOL.title)
        assertEquals("局内掉落的这把武器有机会抽到这个战技（按战技池权重）", RankerText.t("weaponSource.poolHint"))
        assertEquals("武器列表含固定带这个战技的武器与局内战技池能抽到它的武器；动作套按这一把武器实解。", RankerText.t("weaponSource.note"))
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
        assertTrue(pairs > 30000, "对照样本太少（本版本含局内战技池的武器，35564 对），实际 $pairs")
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
        val tae = assertNotNull(dataset.usage[SkillDataset.USAGE_TAE])
        assertTrue("FP" in tae && "FP" !in SkillTextZh.fpText(tae), "底部引用的 TAE 一节同样换成中文说法")
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
        assertTrue(SkillDamageMath.composition(hits.filter { it.isOnSide(false) }, weapon, false).hasDamage)
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
                w.attack(SkillElement.PHYSICAL) > 0 && w.variantIndex(w.swordArtsParamId) != null &&
                    listOf(SkillElement.MAGIC, SkillElement.FIRE, SkillElement.LIGHTNING, SkillElement.HOLY).any { w.attack(it) > 0 }
            },
        )
        val skill = assertNotNull(skills.skillsById[weapon.swordArtsParamId], "武器自己的固定战技")
        assertTrue(weapon.id in skill.weaponIds)
        val hits = skills.hits(skill, weapon).filter { it.isOnSide(false) }
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

    // ------------------------------------------------------------------ 武器列表与分组

    @Test
    fun `weapon list puts the fixed weapons first, then the pool ones by id`() {
        // 狮子斩 100：8 把大剑固定带它，另有 68 把武器局内战技池能抽到。
        val lion = skills.skillsById.getValue(100)
        val weapons = skills.weaponsFor(lion)
        assertEquals(76, weapons.size)
        assertEquals(lion.weaponIds.toSet(), weapons.map { it.id }.toSet())
        val kinds = weapons.map { skills.weaponSourceKind(lion, it) }
        val firstPool = kinds.indexOf(WeaponSourceKind.POOL)
        assertEquals(8, firstPool, "固定武器排前")
        assertEquals(lion.weaponSources.count { it.fixed }, firstPool)
        assertTrue(kinds.take(firstPool).all { it == WeaponSourceKind.FIXED })
        assertTrue(kinds.drop(firstPool).all { it == WeaponSourceKind.POOL })
        assertEquals(weapons.take(firstPool).sortedBy { it.id }, weapons.take(firstPool), "固定武器按 id 升序")
        assertEquals(weapons.drop(firstPool).sortedBy { it.id }, weapons.drop(firstPool), "其余按 id 升序")
        weapons.take(firstPool).forEach { assertEquals(100, it.swordArtsParamId) }
        assertEquals(listOf(3180000, 3180500, 3180600, 3180700, 3180800, 3180900, 3181000, 3181100), weapons.take(firstPool).map { it.id })

        // 分组：含固定武器的「大剑」组排第一，组内 8 把固定在前、10 把局内可抽到在后；默认武器是固定的 3180000。
        val groups = skills.weaponGroups(lion)
        assertEquals("大剑", groups[0].wepTypeZh)
        assertEquals(8, groups[0].fixedCount)
        assertEquals(18, groups[0].weapons.size)
        assertTrue(groups.drop(1).all { it.fixedCount == 0 })
        assertEquals(3180000, skills.defaultWeapon(lion)?.id)
        assertEquals(WeaponSourceKind.FIXED, skills.weaponSourceKind(lion, skills.defaultWeapon(lion)!!))

        // 只来自局内战技池的战技：没有固定武器，按类别大小排，组内按 id。
        val storm = skills.skillsById.getValue(210)
        assertTrue(skills.weaponGroups(storm).all { it.fixedCount == 0 })
        assertEquals(storm.weaponIds.sorted(), skills.weaponsFor(storm).map { it.id })
    }

    @Test
    fun `weapon groups follow the desktop ordering and cover every weapon`() {
        var checkedSkills = 0
        for (skill in dataset.skills) {
            if (skill.weaponIds.size <= 5) continue
            checkedSkills += 1
            val weapons = skills.weaponsFor(skill)
            assertEquals(skill.weaponIds.size, weapons.size)
            val groups = skills.weaponGroups(skill)
            assertTrue(groups.isNotEmpty())
            assertEquals(weapons.size, groups.sumOf { it.weapons.size })
            fun fixed(weapon: SkillWeapon) = skills.weaponSourceKind(skill, weapon) == WeaponSourceKind.FIXED
            groups.forEach { group ->
                assertTrue(group.weapons.all { it.typeLabel == group.wepTypeZh })
                assertEquals(group.weapons.count { fixed(it) }, group.fixedCount)
                assertEquals(
                    group.weapons.sortedWith(compareBy<SkillWeapon> { if (fixed(it)) 0 else 1 }.thenBy { it.id }),
                    group.weapons,
                    "${skill.id}：类别内固定武器在前、其余按武器 id 升序",
                )
            }
            groups.zipWithNext().forEach { (a, b) ->
                val aFixed = a.fixedCount > 0
                val bFixed = b.fixedCount > 0
                assertTrue(
                    (aFixed && !bFixed) ||
                        (aFixed == bFixed && (a.weapons.size > b.weapons.size || (a.weapons.size == b.weapons.size && a.wepTypeZh <= b.wepTypeZh))),
                    "${skill.id}：${a.wepTypeZh} 不该排在 ${b.wepTypeZh} 前",
                )
            }
            val default = skills.defaultWeapon(skill)
            assertEquals(groups[0].weapons[0], default)
            if (weapons.any { fixed(it) }) assertTrue(fixed(default!!), "${skill.id}：有固定武器时默认选固定武器")
        }
        assertTrue(checkedSkills > 50, "参与分组校验的战技太少：$checkedSkills")
    }
}
