package com.nightreign.relicchecker.gamedata.ranker

import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.doubleOrNull

// 「增伤排名」页上半部分的数据模型：武器 / 战技 / 法术与它们的分段命中（data/nightreign-skills-v1.03.5.json，
// schemaVersion 3）。直接解码成下面这些不可变模型，只声明页面用到的字段：coverage / fieldNotes / enums /
// diagnostics 等说明块不声明，解码时跳过。所有字段带默认值（配合 GameDataJson.lenient 的 coerceInputValues；
// 数据集按「省略即默认值」省掉等于默认值的字段）。
//
// schemaVersion 3 的变化（见数据集 schemaChangelog、usage「战技来源（v3）」「命中段已按 TAE 核实（v3）」）：
//   · skills[].weaponIds = 固定引用 ∪ 局内战技池能抽到的基础武器；skills[].weaponSources 逐把给来源（fixed / pool）；
//   · weapons[].skillIds（该武器局内可能出现的全部战技）、skillVariants（{战技 ID: variants 下标}，逐 (战技, 武器)
//     对实解）、customWeapons；旧的 skillVariant 只对武器的固定战技（swordArtsParamId）有效——
//     选段一律读 [SkillWeapon.variantIndex]；
//   · variants[].atkIds 已剔除 TAE 判定打不出的段，hits[] 里这些段仍在、标 notInvoked——页面只从 variants 取段，
//     任何直接读 hits[] 的路径都要过滤 notInvoked（与 noDamage）；
//   · hits[].noFp 按 TAE 分侧，fpBoth 段两侧都计（[SkillHit.isOnSide]）；selfOrAllyOnly 段恒带 noDamage；
//   · v3 修订（usage「法术来源（v3）」）：spells[] 只收可施放的法术——可达施法器 custom 行的 magicTableId_1/_2
//     指向的 MagicTableParam 池里 chanceWeight>0 的 magicId；Magic 残留行 8100 / 8101「风暴管束者」（本作是战技 1200）
//     移到 coverage.spellsNotCastable，不在 spells[]。每个法术带 casterWeaponIds / casterSources（结构仿
//     weaponSources，没有 fixed），施法器的 custom 行见 weapons[].customMagicTables，池见顶层 magicPools。
//
// 权威实现：macOS RelicCore/SkillData.swift；Windows renderer/pages/ranker.js（variantIndexFor / selectHits /
// hitOnSide / weaponSourceOf / hitContribution …）。
// 本数据集不含强化倍率与能力值补正曲线，因此这里算出来的一律是**相对构成**，不是绝对伤害
// （见 usage「本数据集的边界」）。

@Serializable
data class SkillSource(
    val name: String = "",
    val detail: String = "",
    val url: String = "",
    val license: String = "",
    val use: String = "",
)

@Serializable
data class SkillWeapon(
    val id: Int = -1,
    val nameZh: String = "",
    val nameEn: String = "",
    val wepType: Int = -1,
    val wepTypeZh: String = "",
    val wepTypeEn: String = "",
    val rarityZh: String = "",
    /** 五属性基础攻击力（键为 physical / magic / fire / lightning / holy，缺失 = 0；**未含强化与词条加成**）。 */
    val attackBase: Map<String, Double> = emptyMap(),
    val staminaBase: Double = 0.0,
    val poiseDamageBase: Double = 0.0,
    /** 固定战技（EquipParamWeapon.swordArtsParamId）。 */
    val swordArtsParamId: Int = -1,
    /** 该武器局内可能出现的全部战技 ID（固定 + 可达 custom 行的战技池成员，升序；v3）。 */
    val skillIds: List<Int> = emptyList(),
    /** EquipParamWeapon.atkAttribute / atkAttribute2（0 斩 / 1 打 / 2 突 / 3 标准）。 */
    val atkAttribute: Int = 3,
    val atkAttributeZh: String = "",
    val atkAttribute2: Int = 3,
    val atkAttribute2Zh: String = "",
    /**
     * 该武器在「它的固定战技」variants 数组里的下标；缺失表示固定战技没有命中段。
     * **只对 swordArtsParamId 指向的战技有效**，拿去套局内战技池抽到的战技会选错套（见 [variantIndex]）。
     */
    val skillVariant: Int? = null,
    /** {战技 ID（字符串）: 该战技 variants 的下标}（v3，覆盖 skillIds 里每个有命中段、能解出动作套的战技）。 */
    val skillVariants: Map<String, Int> = emptyMap(),
    /** 可达的 EquipParamCustomWeapon 行：[customId, swordArtsTableId]（v3；-1 = 该行不抽池）。 */
    val customWeapons: List<List<Int>> = emptyList(),
    /**
     * 施法器可达的 EquipParamCustomWeapon 行：[customId, magicTableId_1, magicTableId_2]（v3 修订；-1 = 该槽不抽法术）。
     * 一局里拿到的施法器每个槽从对应的池（[SkillDataset.magicPools]）里各抽一个法术。
     */
    val customMagicTables: List<List<Int>> = emptyList(),
) {
    val displayName: String get() = nameZh.ifEmpty { nameEn }

    fun attack(element: SkillElement): Double = attackBase[element.key]?.takeIf { it.isFinite() } ?: 0.0

    val totalAttack: Double get() = SkillElement.entries.sumOf { attack(it) }

    /** 分组用的类别名（中文优先）。 */
    val typeLabel: String get() = wepTypeZh.ifEmpty { wepTypeEn }

    /**
     * 这把武器用战技 [skillId] 时的 variants 下标（usage「选段（必读）」）：一律读 skillVariants[战技 ID]；
     * 缺这一项时才回退 skillVariant，而且只在 [skillId] 就是武器的固定战技时（Windows variantIndexFor）。
     * null = 这把武器用这个战技打不出段。
     */
    fun variantIndex(skillId: Int): Int? =
        skillVariants[skillId.toString()] ?: skillVariant?.takeIf { swordArtsParamId == skillId }
}

@Serializable
data class SkillHit(
    val atkId: Int = -1,
    val ctx: String? = null,
    val ctxZh: String? = null,
    val ctxKind: String? = null,
    val label: String? = null,
    val labelZh: String? = null,
    /** 动作值（%），键同 attackBase。 */
    val motion: Map<String, Double> = emptyMap(),
    /** 固定值，键同 attackBase。 */
    val flat: Map<String, Double> = emptyMap(),
    val poise: Double = 0.0,
    val poiseMv: Double = 0.0,
    val stamina: Double = 0.0,
    val staminaMv: Double = 0.0,
    /** Slash / Strike / Pierce / Standard / None / WeaponAtkAttribute / WeaponAtkAttribute2。 */
    val attribute: String = "None",
    val attributeZh: String = "",
    val isBullet: Boolean = false,
    /** 专注值不足时打出的弱化版分支（与带 FP 版互为替代，按开关同侧取段）。 */
    val noFp: Boolean = false,
    /** "tae"＝noFp 由 TAE 动画号判出（行名没写 No FP，labelZh 前补了「无FP版」）；缺失＝来自行名（v3）。 */
    val noFpSource: String? = null,
    /** 带 FP 与无 FP 两侧动画都会打出这一段：开关在哪一侧都计入（noFp 恒为 false；v3）。 */
    val fpBoth: Boolean = false,
    val noDamage: Boolean = false,
    /** 只打自己 / 队友（如祈祷一击的自疗子弹），数据恒同时标 noDamage（v3）。 */
    val selfOrAllyOnly: Boolean = false,
    /** 该段所属动作套在本作没有任何武器会用到，按选段算法永远取不到。 */
    val noVariant: Boolean = false,
    /** TAE 判定在所有武器上都打不出（已从 variants 移除，只留在 hits[] 备查；v3）。 */
    val notInvoked: Boolean = false,
    /** notInvoked 的原因（enums.notInvokedReason：gated / notInvoked / elsewhere / roarR2Only …）。 */
    val notInvokedReason: String? = null,
    val addBaseAtk: Boolean = false,
) {
    /** 数据里声明过的动作值（0 视为没声明，与 macOS 端 elementMap 同一口径）。 */
    fun motionOf(element: SkillElement): Double? = motion[element.key]?.takeIf { it.isFinite() && it != 0.0 }

    fun flatOf(element: SkillElement): Double? = flat[element.key]?.takeIf { it.isFinite() && it != 0.0 }

    /**
     * 这一段在「使用专注值不足版本」开关的这一侧吗（Windows hitOnSide）：fpBoth 段两侧都在，其余 noFp 与开关同侧。
     * 只看 noFp 会在专注值不足侧丢掉两侧共用的段（如 1024 唤矛仪式、1021 毁灭灵火、218 伟哉卡利亚）。
     */
    fun isOnSide(useNoFp: Boolean): Boolean = fpBoth || noFp == useNoFp

    /** 段名：labelZh → label → 「单段」（数据集原文，未做 FP 替换）。 */
    val displayLabel: String
        get() = labelZh?.takeIf { it.isNotEmpty() } ?: label?.takeIf { it.isNotEmpty() } ?: "单段"

    /** 展示层的段名：把「无FP版」换成「专注值不足版」（见 [SkillTextZh.fpText]）。 */
    val displayLabelZh: String get() = SkillTextZh.fpText(displayLabel)
}

/** 一套实际会打出的段。`atkIds` 是本战技 hits 里的 atkId 子集（v3 起已按 TAE 核实）。 */
@Serializable
data class SkillVariant(
    val atkIds: List<Int> = emptyList(),
    val ctx: String? = null,
    val ctxZh: String? = null,
    val ctxKind: String? = null,
    val via: String = "",
    val weaponIds: List<Int> = emptyList(),
) {
    val displayContext: String? get() = ctxZh?.takeIf { it.isNotEmpty() } ?: ctx?.takeIf { it.isNotEmpty() }
}

/** 这把武器带某个战技的来源（v3 skills[].weaponSources）。同一把武器两者都成立时只算固定。 */
enum class WeaponSourceKind(val key: String) {
    /** EquipParamWeapon.swordArtsParamId 就是这个战技。 */
    FIXED("fixed"),

    /** 只在局内战技池（EquipParamCustomWeapon → SwordArtsTableParam）里抽得到。 */
    POOL("pool"),
    ;

    /** 文案键（RANKER_TEXT_TABLE：weaponSource.fixed / weaponSource.pool，三端同名同值）。 */
    val textKey: String get() = "weaponSource.$key"

    /** 页面上的标记：「固定战技」「局内可抽到」。 */
    val title: String get() = RankerText.t(textKey)
}

/** skills[].weaponSources[].pool 的一项：[swordArtsTableId, chanceWeight, customRows]。 */
data class SkillPoolDraw(val poolId: Int, val weight: Int, val customRows: Int)

/** skills[].weaponSources 的一项（与 weaponIds 一一对应、同序）：{id, fixed?, pool?}。 */
@Serializable
data class SkillWeaponSource(
    val id: Int = -1,
    val fixed: Boolean = false,
    /** [[swordArtsTableId, chanceWeight, customRows], …]（按池 ID 升序）；缺失 = 不经由战技池。 */
    val pool: List<List<Int>> = emptyList(),
) {
    val draws: List<SkillPoolDraw>
        get() = pool.mapNotNull { row -> if (row.size >= 2) SkillPoolDraw(row[0], row[1], row.getOrElse(2) { 0 }) else null }

    /** 页面标记：fixed 优先；只有池来源时为 POOL；两者都没有（数据异常）为 null。 */
    val kind: WeaponSourceKind?
        get() = when {
            fixed -> WeaponSourceKind.FIXED
            pool.isNotEmpty() -> WeaponSourceKind.POOL
            else -> null
        }
}

/**
 * spells[].casterSources 的一项（与 casterWeaponIds 一一对应、同序；v3 修订）：{id, pool}。结构仿 [SkillWeaponSource]，
 * 但法术没有「固定」来源——施法器的每个法术槽都从 MagicTableParam 池里抽。
 */
@Serializable
data class SpellCasterSource(
    val id: Int = -1,
    /** [[magicTableId, chanceWeight, customRows], …]（按池 ID 升序；chanceWeight 恒 > 0）。 */
    val pool: List<List<Int>> = emptyList(),
) {
    val draws: List<SkillPoolDraw>
        get() = pool.mapNotNull { row -> if (row.size >= 2) SkillPoolDraw(row[0], row[1], row.getOrElse(2) { 0 }) else null }
}

@Serializable
data class SkillEntry(
    val id: Int = -1,
    val nameZh: String = "",
    val nameEn: String = "",
    /** 训练场可用。 */
    val sparring: Boolean = false,
    /** 能带这个战技的武器（v3：固定引用 ∪ 局内战技池）。 */
    val weaponIds: List<Int> = emptyList(),
    /** 与 weaponIds 一一对应的来源（v3）。 */
    val weaponSources: List<SkillWeaponSource> = emptyList(),
    val hits: List<SkillHit> = emptyList(),
    val variants: List<SkillVariant> = emptyList(),
    /** 战技动画匹配不到（弓系战技）：hits / variants 没有经 TAE 过滤（v3）。 */
    val taeUnmatched: Boolean = false,
) {
    val displayName: String get() = nameZh.ifEmpty { nameEn }
}

@Serializable
data class SpellEntry(
    val id: Int = -1,
    val nameZh: String = "",
    val nameEn: String = "",
    /** sorcery / incantation（pyromancy 按祷告算，与 macOS 端 isIncantation 同一口径）。 */
    val kind: String = "",
    val kindZh: String = "",
    val mp: Int = 0,
    val sparring: Boolean = false,
    val hits: List<SkillHit> = emptyList(),
    /**
     * 能携带这个法术的施法器（基础武器 ID，升序；v3 修订）：魔法全是手杖（wepType 57）、祷告全是圣印记（61），
     * 与页面按施法器判定 requires.attackWeaponTypes 的口径（[OutputClass.casterWepType]）一致。
     */
    val casterWeaponIds: List<Int> = emptyList(),
    /** 与 casterWeaponIds 一一对应的抽取来源（v3 修订）。 */
    val casterSources: List<SpellCasterSource> = emptyList(),
) {
    val displayName: String get() = nameZh.ifEmpty { nameEn }
    val isSorcery: Boolean get() = kind == "sorcery"
    val isIncantation: Boolean get() = kind == "incantation" || kind == "pyromancy"

    /** 输出类别：魔法以外一律按祷告（macOS：`spell.isSorcery ? .sorcery : .incantation`）。 */
    val outputClass: OutputClass get() = if (isSorcery) OutputClass.SORCERY else OutputClass.INCANTATION

    /** 「魔法」「祷告」：数据集的 kindZh，缺失时按类别补上。 */
    val kindLabelZh: String get() = kindZh.ifEmpty { if (isSorcery) "魔法" else "祷告" }
}

/** skills 数据集（只含页面用到的字段）。 */
@Serializable
data class SkillDataset(
    val schemaVersion: Int? = null,
    val gameVersion: String = "",
    val dataVersion: String = "",
    val generatedAt: String = "",
    val sources: List<SkillSource> = emptyList(),
    /**
     * counts：weapons / skills / spells / hits … 页面底部「数据版本与来源」用。v3 起混有布尔值（taeVerified），
     * 所以按原始 JSON 标量存，数值用 [count]、布尔用 [flag] 取。
     */
    val counts: Map<String, JsonPrimitive> = emptyMap(),
    /**
     * 数据集自带的算法说明（选段（必读）/ 近战武器段 / … / 战技来源（v3）/ 法术来源（v3）/ 命中段已按 TAE 核实（v3）），
     * 键的顺序即数据顺序。
     */
    val usage: Map<String, String> = emptyMap(),
    /** 已知取舍（展示前要过一遍 [SkillTextZh.fpText]）。 */
    val caveats: List<String> = emptyList(),
    /** 局内战技池：{SwordArtsTableParam 池 ID: [[战技 ID, chanceWeight], …]}（v3）。 */
    val swordArtsPools: Map<String, List<List<Int>>> = emptyMap(),
    /**
     * 施法器的法术池：{MagicTableParam 池 ID: [[magicId, chanceWeight], …]}（v3 修订；只收被可达施法器 custom 行引用的池、
     * chanceWeight>0 的条目；同一个 ID 的全部行 = 一个池）。
     */
    val magicPools: Map<String, List<List<Int>>> = emptyMap(),
    val weapons: List<SkillWeapon> = emptyList(),
    /** 全部战技（含没有武器的占位条目）。 */
    val skills: List<SkillEntry> = emptyList(),
    /** 本作玩家能施放的全部法术（v3 修订后只收可施放的；不可施放的残留行在 coverage.spellsNotCastable，本模型不解码）。 */
    val spells: List<SpellEntry> = emptyList(),
) {
    fun count(key: String): Int = counts[key]?.doubleOrNull?.toInt() ?: 0

    fun flag(key: String): Boolean = counts[key]?.booleanOrNull == true

    /** variants 已按 TAE 动画事件核实（counts.taeVerified）。 */
    val taeVerified: Boolean get() = flag("taeVerified")

    /** 池 [poolId] 里战技 [skillId] 的权重与池内权重之和（没有这个池 / 战技时 null）。 */
    fun poolWeight(poolId: Int, skillId: Int): Pair<Int, Int>? {
        val entries = swordArtsPools[poolId.toString()] ?: return null
        val own = entries.firstOrNull { it.size >= 2 && it[0] == skillId }?.get(1) ?: return null
        return own to entries.sumOf { it.getOrElse(1) { 0 } }
    }

    /** 法术池 [poolId] 里法术 [magicId] 的权重与池内权重之和（没有这个池 / 法术时 null）。 */
    fun magicPoolWeight(poolId: Int, magicId: Int): Pair<Int, Int>? {
        val entries = magicPools[poolId.toString()] ?: return null
        val own = entries.firstOrNull { it.size >= 2 && it[0] == magicId }?.get(1) ?: return null
        return own to entries.sumOf { it.getOrElse(1) { 0 } }
    }

    companion object {
        /** usage 里「本数据集的边界」的键：页面要引用（绝对伤害不在范围内）。 */
        const val USAGE_BOUNDARY = "本数据集的边界"

        /** usage 里选段规则的键。 */
        const val USAGE_SELECTION = "选段（必读）"

        /** usage 里武器来源（固定 / 局内战技池）的读法（v3）。 */
        const val USAGE_WEAPON_SOURCES = "战技来源（v3）"

        /** usage 里法术来源（可施放口径、施法器与法术池）的读法（v3 修订）。 */
        const val USAGE_SPELL_SOURCES = "法术来源（v3）"

        /** usage 里「命中段已按 TAE 核实」一节（v3）：页面底部引用。 */
        const val USAGE_TAE = "命中段已按 TAE 核实（v3）"
    }
}

/** 展示层的中文口径工具。**只换展示，不动数据集、不动字段名。** */
object SkillTextZh {
    // 与 Windows 端 FP_TEXT_RULES、macOS 端 SkillTextZh.fpRules 逐条相同。顺序有意义：先认长的写法，
    // 最后才把剩下的孤零零 FP 换成「专注值」。空白按 JS 的 \s（含全角空格 U+3000）匹配，见 [RankerRegex]
    // ——数据集写成「无　FP版」也不会只有一端替换掉；不用 `(?U)`（Android 的 ICU 正则不支持，会在初始化时抛异常）。
    private val rules: List<Pair<Regex, String>> = listOf(
        Regex("无${RankerRegex.WS}*FP${RankerRegex.WS}*版") to "专注值不足版",
        Regex("${RankerRegex.WS}*[Nn]o${RankerRegex.WS}*FP(?:${RankerRegex.WS}*版)?") to "专注值不足版",
        Regex("带${RankerRegex.WS}*FP(?:${RankerRegex.WS}*版)?") to "正常版",
        Regex("FP") to "专注值",
    )

    /**
     * 数据集原文里还留着英文的 FP——hits[].labelZh 的「无FP版」、caveats 里的「6 段带 FP + 6 段 No FP」——
     * 页面一律说中文的「专注值」。只对这两处**说明文字**用：buffs 数据集里的英文参数表原名不要套。
     */
    fun fpText(text: String?): String {
        val value = text ?: return ""
        if (!value.contains("FP")) return value
        var out: String = value
        for ((pattern, replacement) in rules) out = pattern.replace(out, replacement)
        return out
    }
}
