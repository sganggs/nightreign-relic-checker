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

/** 战技的武器选择：按武器类别分组；[fixedCount] 是组里固定带这个战技的武器数（它们排在组内最前）。 */
data class SkillWeaponGroup(val wepTypeZh: String, val weapons: List<SkillWeapon>, val fixedCount: Int = 0)

/**
 * skills 数据集的索引（一次建好、不可变）：按 id 查表、可选的输出手段列表、武器来源、选段与分段换算。
 * 收录条件与 Windows 端 buildMeansItems、macOS 端 SkillDataIndex 一致：
 * 战技要有命中段 + 至少一把能带它的武器（v3：固定或局内战技池）+ 至少一种选法算得出非 0 相对值；
 * 法术要有命中段且至少一段带固定值。顺序：战技（数据顺序）在前，法术（数据顺序）在后。
 */
class SkillDataIndex(val dataset: SkillDataset) {
    val weaponsById: Map<Int, SkillWeapon> = dataset.weapons.associateByFirst { it.id }
    val skillsById: Map<Int, SkillEntry> = dataset.skills.associateByFirst { it.id }
    val spellsById: Map<Int, SpellEntry> = dataset.spells.associateByFirst { it.id }

    /** 战技 ID → {武器 ID → 来源}（skills[].weaponSources；两者都成立时只记固定，Windows weaponSourceMap）。 */
    private val sourceKinds: Map<Int, Map<Int, WeaponSourceKind>> = dataset.skills.associate { skill ->
        val map = HashMap<Int, WeaponSourceKind>(skill.weaponSources.size * 2)
        for (source in skill.weaponSources) {
            val kind = source.kind ?: continue
            if (map[source.id] != WeaponSourceKind.FIXED) map[source.id] = kind
        }
        skill.id to map
    }

    val outputs: List<SkillOutput>
    private val outputsById: Map<String, SkillOutput>

    /** 有命中段但本作没有任何武器能带的战技数（v3 把局内战技池算进 weaponIds 后为 0）。 */
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
                segmentCount = skill.hits.count { !it.notInvoked },
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
            if (!SkillDamageMath.hasAnyDamage(spellHits(spell), null, isSpell = true)) {
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
                segmentCount = spell.hits.count { !it.notInvoked },
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

    /** 至少有一把能带它的武器（固定或局内战技池）能打出非 0 相对值（Windows 端 skillHasDamage）。 */
    fun skillHasDamage(skill: SkillEntry): Boolean = skill.weaponIds.any { id ->
        val weapon = weaponsById[id] ?: return@any false
        SkillDamageMath.hasAnyDamage(hits(skill, weapon), weapon, isSpell = false)
    }

    // ---- 武器 --------------------------------------------------------------

    /**
     * 这把武器带这个战技的来源（usage「战技来源（v3）」读 skills[].weaponSources）：固定 / 局内可抽到，
     * 两者都成立时只算固定。weaponSources 里没有这把武器（旧数据）时按 swordArtsParamId 判固定，判不出为 null
     * （Windows weaponSourceOf）。
     */
    fun weaponSourceKind(skill: SkillEntry, weapon: SkillWeapon): WeaponSourceKind? =
        sourceKinds[skill.id]?.get(weapon.id)
            ?: if (weapon.swordArtsParamId == skill.id) WeaponSourceKind.FIXED else null

    /** 这把武器是这个战技的固定武器吗（排序用）。 */
    private fun isFixed(skill: SkillEntry, weapon: SkillWeapon): Boolean =
        weaponSourceKind(skill, weapon) == WeaponSourceKind.FIXED

    /**
     * 能带这个战技的武器（skills[].weaponIds = 固定引用 ∪ 局内战技池，查不到的跳过）：
     * 固定带这个战技的武器排前，其余按武器 id 升序（Windows weaponsForSkill）。
     */
    fun weaponsFor(skill: SkillEntry): List<SkillWeapon> =
        skill.weaponIds.mapNotNull { weaponsById[it] }
            .sortedWith(compareBy<SkillWeapon> { if (isFixed(skill, it)) 0 else 1 }.thenBy { it.id })

    /**
     * 按武器类别分组（macOS 端 weaponGroups(for:)）：类别内固定武器排前、其余按武器 id 升序；
     * 类别之间先排含固定武器的，再按武器数量降序、同数按类别名。默认武器因此总是固定武器（有的话）。
     */
    fun weaponGroups(skill: SkillEntry): List<SkillWeaponGroup> {
        val grouped = LinkedHashMap<String, MutableList<SkillWeapon>>()
        for (weapon in weaponsFor(skill)) grouped.getOrPut(weapon.typeLabel) { ArrayList() } += weapon
        return grouped.map { (label, weapons) ->
            SkillWeaponGroup(label, weapons, fixedCount = weapons.count { isFixed(skill, it) })
        }.sortedWith(
            compareBy<SkillWeaponGroup> { if (it.fixedCount > 0) 0 else 1 }
                .thenByDescending { it.weapons.size }
                .thenBy { it.wepTypeZh },
        )
    }

    /** 默认武器：分组后第一组的第一把（有固定武器时就是固定武器）。 */
    fun defaultWeapon(skill: SkillEntry): SkillWeapon? = weaponGroups(skill).firstOrNull()?.weapons?.firstOrNull()

    // ---- 选段 --------------------------------------------------------------

    /**
     * 武器在这个战技里用的那一套动作：下标读 weapons[].skillVariants[战技 ID]（缺失时只对固定战技回退
     * skillVariant，见 [SkillWeapon.variantIndex]）；找不到 / 越界 = 这把武器用这个战技没有命中段。
     */
    fun selectVariant(skill: SkillEntry, weapon: SkillWeapon?): SkillVariant? {
        if (skill.variants.isEmpty()) return null
        val index = weapon?.variantIndex(skill.id) ?: return null
        return skill.variants.getOrNull(index)
    }

    /**
     * 这把武器实际会打出的段（usage.选段（必读））：variants 存在时一律走
     * `variants[weapon.skillVariants[战技 ID]].atkIds`（已按 TAE 核实），缺失 / 越界就是「打不出段」，
     * 不按 weaponIds 回查、也不退回 ctx 逻辑；variants 缺失时才退回 ctx 单选（武器名 → 武器类别 → ctx 缺失），
     * 任何情况下都不取并集。
     */
    fun hits(skill: SkillEntry, weapon: SkillWeapon?): List<SkillHit> = selectHits(skill, weapon)

    fun segments(skill: SkillEntry, weapon: SkillWeapon?): List<SkillSegment> =
        hits(skill, weapon).map { SkillDamageMath.segment(it, weapon, isSpell = false) }

    /** 法术的段：没有 variants，全部段都会打出（法术不做 TAE 过滤，剔 notInvoked 只是防御）。 */
    fun spellHits(spell: SpellEntry): List<SkillHit> = invokedHits(spell.hits)

    /** 法术：只用 flat 做配比。 */
    fun segments(spell: SpellEntry): List<SkillSegment> =
        spellHits(spell).map { SkillDamageMath.segment(it, null, isSpell = true) }

    /** 「1793 把武器 · 187 个战技 · 158 个法术」（v3 修订：spells[] 只收可施放的法术）。 */
    val summary: String
        get() = "${dataset.weapons.size} 把武器 · ${dataset.skills.size} 个战技 · ${dataset.spells.size} 个法术"

    companion object {
        /**
         * 直接从 hits[] 取段时先剔掉 TAE 判定为永远打不出的段（hits[].notInvoked，v3）：它们不在任何
         * variants[].atkIds 里，只留在 hits[] 备查（Windows invokedHits）。
         */
        fun invokedHits(hits: List<SkillHit>): List<SkillHit> =
            if (hits.none { it.notInvoked }) hits else hits.filter { !it.notInvoked }

        /** 与 [hits] 同一口径的纯函数（测试与合成数据用）。 */
        fun selectHits(skill: SkillEntry, weapon: SkillWeapon?): List<SkillHit> {
            if (skill.hits.isEmpty()) return emptyList()
            if (skill.variants.isNotEmpty()) {
                val index = weapon?.variantIndex(skill.id) ?: return emptyList()
                val variant = skill.variants.getOrNull(index) ?: return emptyList()
                val wanted = variant.atkIds.toHashSet()
                return skill.hits.filter { it.atkId in wanted }
            }
            // 退回路径直接读 hits[]：TAE 判为打不出的段（notInvoked）与不带伤害的段（noDamage）一律剔掉。
            val pool = skill.hits.filter { !it.notInvoked && !it.noDamage }
            if (weapon != null && weapon.nameEn.isNotEmpty()) {
                val byName = pool.filter { it.ctx == weapon.nameEn }
                if (byName.isNotEmpty()) return byName
            }
            if (weapon != null && weapon.wepTypeEn.isNotEmpty()) {
                val byType = pool.filter { it.ctx == weapon.wepTypeEn }
                if (byType.isNotEmpty()) return byType
            }
            return pool.filter { it.ctx.isNullOrEmpty() }
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
