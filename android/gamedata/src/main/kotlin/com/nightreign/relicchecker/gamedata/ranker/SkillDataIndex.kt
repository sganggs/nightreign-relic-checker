package com.nightreign.relicchecker.gamedata.ranker

import com.nightreign.relicchecker.gamedata.GameDataFormatException
import com.nightreign.relicchecker.rules.foldedForSearch

/** 搜索框里的一条「输出手段」：战技或法术。 */
data class SkillOutput(
    val outputClass: OutputClass,
    val entryId: Int,
    val nameZh: String,
    val nameEn: String,
    /** 徽标：「战技」／「魔法」／「祷告」。 */
    val badgeZh: String,
    /** 法术为「魔法 · 专注值 7」，战技为「战技 · N 把武器」（macOS 端 SkillOutput.subtitleZh）。 */
    val subtitleZh: String,
    val weaponCount: Int,
    val segmentCount: Int,
    /** 法术的专注值消耗；战技为 null。 */
    val mp: Int?,
    internal val searchKey: String,
) {
    /** 稳定键：`skill-1177`、`sorcery-4021`（列表 key / rememberSaveable 用）。 */
    val id: String get() = "${outputClass.key}-$entryId"
    val displayName: String get() = nameZh.ifEmpty { nameEn }
    val isSkill: Boolean get() = outputClass == OutputClass.SKILL

    /** 纯数字按 id 前缀匹配，其余按折叠后的「中文名 英文名 类别」子串匹配（macOS 端 SkillOutput.matches）。 */
    fun matches(foldedQuery: String): Boolean {
        if (foldedQuery.isEmpty()) return true
        if (foldedQuery.all { it in '0'..'9' }) return entryId.toString().startsWith(foldedQuery)
        return searchKey.contains(foldedQuery)
    }
}

/** 战技的武器选择：按武器类别分组。 */
data class SkillWeaponGroup(val wepTypeZh: String, val weapons: List<SkillWeapon>)

/**
 * skills 数据集的索引（一次建好、不可变）：按 id 查表、可选的输出手段列表、选段与分段换算。
 * 收录条件与 Windows 端 buildMeansItems、macOS 端 SkillDataIndex 一致：
 * 战技要有命中段 + 至少一把引用它的武器 + 至少一种选法算得出非 0 相对值；法术要有命中段且至少一段带固定值。
 * 顺序：战技（数据顺序）在前，法术（数据顺序）在后。
 */
class SkillDataIndex(val dataset: SkillDataset) {
    val weaponsById: Map<Int, SkillWeapon> = dataset.weapons.associateByFirst { it.id }
    val skillsById: Map<Int, SkillEntry> = dataset.skills.associateByFirst { it.id }
    val spellsById: Map<Int, SpellEntry> = dataset.spells.associateByFirst { it.id }

    val outputs: List<SkillOutput>
    private val outputsById: Map<String, SkillOutput>

    /** 有命中段但本作没有任何武器引用的战技数。 */
    val skillsWithoutWeapons: Int

    /** 完全没有命中段的战技 / 法术数（纯增益、格挡、附魔一类）。 */
    val skillsWithoutHits: Int
    val spellsWithoutHits: Int

    /** 有命中段、也有武器，但每一段都算不出伤害的战技数（Windows meansWithoutDamage.skills）。 */
    val skillsWithoutDamage: Int

    /** 有命中段但一段固定值都没有的法术数（恢复／庇佑／附魔类；Windows meansWithoutDamage.spells）。 */
    val spellsWithoutDamage: Int

    init {
        val list = ArrayList<SkillOutput>()
        var withoutWeapons = 0
        var skillsNoHits = 0
        var skillsNoDamage = 0
        for (skill in dataset.skills) {
            if (skill.hits.isEmpty()) {
                skillsNoHits += 1
                continue
            }
            if (skill.weaponIds.isEmpty()) {
                withoutWeapons += 1
                continue
            }
            if (!skillHasDamage(skill)) {
                skillsNoDamage += 1
                continue
            }
            val weapons = skill.weaponIds.size
            list += SkillOutput(
                outputClass = OutputClass.SKILL,
                entryId = skill.id,
                nameZh = skill.nameZh,
                nameEn = skill.nameEn,
                badgeZh = "战技",
                subtitleZh = "战技 · $weapons 把武器",
                weaponCount = weapons,
                segmentCount = skill.hits.size,
                mp = null,
                searchKey = "${skill.nameZh} ${skill.nameEn} 战技".foldedForSearch(),
            )
        }
        var spellsNoHits = 0
        var spellsNoDamage = 0
        for (spell in dataset.spells) {
            if (spell.hits.isEmpty()) {
                spellsNoHits += 1
                continue
            }
            // 法术没有武器，构成只来自 flat；一个 flat 都没有的（冰雾、各种恢复／庇佑／防护）排除。
            if (!SkillDamageMath.hasAnyDamage(spell.hits, null, isSpell = true)) {
                spellsNoDamage += 1
                continue
            }
            val kindZh = spell.kindLabelZh
            list += SkillOutput(
                outputClass = spell.outputClass,
                entryId = spell.id,
                nameZh = spell.nameZh,
                nameEn = spell.nameEn,
                badgeZh = kindZh,
                subtitleZh = "$kindZh · 专注值 ${spell.mp}",
                weaponCount = 0,
                segmentCount = spell.hits.size,
                mp = spell.mp,
                searchKey = "${spell.nameZh} ${spell.nameEn} $kindZh".foldedForSearch(),
            )
        }
        if (list.isEmpty()) throw GameDataFormatException("战技数据里没有任何可计算的战技或法术")
        outputs = list
        outputsById = list.associateBy { it.id }
        skillsWithoutWeapons = withoutWeapons
        skillsWithoutHits = skillsNoHits
        spellsWithoutHits = spellsNoHits
        skillsWithoutDamage = skillsNoDamage
        spellsWithoutDamage = spellsNoDamage
    }

    val skillOutputCount: Int get() = outputs.count { it.isSkill }
    val spellOutputCount: Int get() = outputs.count { !it.isSkill }

    fun output(id: String): SkillOutput? = outputsById[id]

    /** 搜索（显示层过滤）：查询词按 :rules 的 foldedForSearch 归一化。 */
    fun outputsMatching(query: String, outputClass: OutputClass? = null): List<SkillOutput> {
        val needle = query.foldedForSearch()
        return outputs.filter { (outputClass == null || it.outputClass == outputClass) && it.matches(needle) }
    }

    /** 至少有一把引用它的武器能打出非 0 相对值（Windows 端 skillHasDamage）。 */
    fun skillHasDamage(skill: SkillEntry): Boolean = skill.weaponIds.any { id ->
        val weapon = weaponsById[id] ?: return@any false
        SkillDamageMath.hasAnyDamage(hits(skill, weapon), weapon, isSpell = false)
    }

    // ---- 武器 --------------------------------------------------------------

    /** 引用这个战技的武器（weaponIds 的数据顺序，查不到的跳过）。 */
    fun weaponsFor(skill: SkillEntry): List<SkillWeapon> = skill.weaponIds.mapNotNull { weaponsById[it] }

    /** 按武器类别分组（类别内按武器 id 升序，类别按武器数量降序、同数按类别名；macOS 端 weaponGroups(for:)）。 */
    fun weaponGroups(skill: SkillEntry): List<SkillWeaponGroup> {
        val grouped = LinkedHashMap<String, MutableList<SkillWeapon>>()
        for (weapon in weaponsFor(skill)) grouped.getOrPut(weapon.typeLabel) { ArrayList() } += weapon
        return grouped.map { (label, weapons) -> SkillWeaponGroup(label, weapons.sortedBy { it.id }) }
            .sortedWith(compareByDescending<SkillWeaponGroup> { it.weapons.size }.thenBy { it.wepTypeZh })
    }

    /** 默认武器：分组后第一组的第一把。 */
    fun defaultWeapon(skill: SkillEntry): SkillWeapon? = weaponGroups(skill).firstOrNull()?.weapons?.firstOrNull()

    // ---- 选段 --------------------------------------------------------------

    /** 武器在这个战技里用的那一套动作；缺 skillVariant / 越界 = 这把武器的战技没有命中段。 */
    fun selectVariant(skill: SkillEntry, weapon: SkillWeapon?): SkillVariant? {
        if (skill.variants.isEmpty()) return null
        val index = weapon?.skillVariant ?: return null
        return skill.variants.getOrNull(index)
    }

    /**
     * 这把武器实际会打出的段（usage.选段（必读））：variants 存在时一律走 `variants[weapon.skillVariant].atkIds`，
     * 缺失 / 越界就是「打不出段」，不按 weaponIds 回查、也不退回 ctx 逻辑；variants 缺失时才退回 ctx 单选
     * （武器名 → 武器类别 → ctx 缺失），任何情况下都不取并集。
     */
    fun hits(skill: SkillEntry, weapon: SkillWeapon?): List<SkillHit> = selectHits(skill, weapon)

    fun segments(skill: SkillEntry, weapon: SkillWeapon?): List<SkillSegment> =
        hits(skill, weapon).map { SkillDamageMath.segment(it, weapon, isSpell = false) }

    /** 法术：没有 variants，全部段都会打出；只用 flat 做配比。 */
    fun segments(spell: SpellEntry): List<SkillSegment> =
        spell.hits.map { SkillDamageMath.segment(it, null, isSpell = true) }

    /** 「1793 把武器 · 187 个战技 · 160 个法术」。 */
    val summary: String
        get() = "${dataset.weapons.size} 把武器 · ${dataset.skills.size} 个战技 · ${dataset.spells.size} 个法术"

    companion object {
        /** 与 [hits] 同一口径的纯函数（测试与合成数据用）。 */
        fun selectHits(skill: SkillEntry, weapon: SkillWeapon?): List<SkillHit> {
            if (skill.hits.isEmpty()) return emptyList()
            if (skill.variants.isNotEmpty()) {
                val index = weapon?.skillVariant ?: return emptyList()
                val variant = skill.variants.getOrNull(index) ?: return emptyList()
                val wanted = variant.atkIds.toHashSet()
                return skill.hits.filter { it.atkId in wanted }
            }
            if (weapon != null && weapon.nameEn.isNotEmpty()) {
                val byName = skill.hits.filter { it.ctx == weapon.nameEn }
                if (byName.isNotEmpty()) return byName
            }
            if (weapon != null && weapon.wepTypeEn.isNotEmpty()) {
                val byType = skill.hits.filter { it.ctx == weapon.wepTypeEn }
                if (byType.isNotEmpty()) return byType
            }
            return skill.hits.filter { it.ctx.isNullOrEmpty() }
        }
    }
}

/** 按 id 建表，重复 id 取第一个（与 macOS `uniquingKeysWith: { first, _ in first }` 一致）。 */
internal inline fun <T, K> List<T>.associateByFirst(key: (T) -> K): Map<K, T> {
    val map = LinkedHashMap<K, T>(size * 2)
    for (item in this) {
        val k = key(item)
        if (!map.containsKey(k)) map[k] = item
    }
    return map
}
