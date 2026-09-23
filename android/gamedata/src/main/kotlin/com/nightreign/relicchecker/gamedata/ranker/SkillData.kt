package com.nightreign.relicchecker.gamedata.ranker

import kotlinx.serialization.Serializable

// 「增伤排名」页上半部分的数据模型：武器 / 战技 / 法术与它们的分段命中（data/nightreign-skills-v1.03.5.json，
// schemaVersion 2）。直接解码成下面这些不可变模型，只声明页面用到的字段：coverage / fieldNotes / enums
// 等说明块不声明，解码时跳过。所有字段带默认值（配合 GameDataJson.lenient 的 coerceInputValues）。
//
// 权威实现：macOS RelicCore/SkillData.swift；Windows renderer/pages/ranker.js（selectHits / hitContribution …）。
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
    val swordArtsParamId: Int = -1,
    /** EquipParamWeapon.atkAttribute / atkAttribute2（0 斩 / 1 打 / 2 突 / 3 标准）。 */
    val atkAttribute: Int = 3,
    val atkAttributeZh: String = "",
    val atkAttribute2: Int = 3,
    val atkAttribute2Zh: String = "",
    /** 该武器在「它的战技」variants 数组里的下标；缺失表示这把武器的战技没有命中段。 */
    val skillVariant: Int? = null,
) {
    val displayName: String get() = nameZh.ifEmpty { nameEn }

    fun attack(element: SkillElement): Double = attackBase[element.key]?.takeIf { it.isFinite() } ?: 0.0

    val totalAttack: Double get() = SkillElement.entries.sumOf { attack(it) }

    /** 分组用的类别名（中文优先）。 */
    val typeLabel: String get() = wepTypeZh.ifEmpty { wepTypeEn }
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
    val noFp: Boolean = false,
    val noDamage: Boolean = false,
    /** 该段所属动作套在本作没有任何武器会用到，按选段算法永远取不到。 */
    val noVariant: Boolean = false,
    val addBaseAtk: Boolean = false,
) {
    /** 数据里声明过的动作值（0 视为没声明，与 macOS 端 elementMap 同一口径）。 */
    fun motionOf(element: SkillElement): Double? = motion[element.key]?.takeIf { it.isFinite() && it != 0.0 }

    fun flatOf(element: SkillElement): Double? = flat[element.key]?.takeIf { it.isFinite() && it != 0.0 }

    /** 段名：labelZh → label → 「单段」（数据集原文，未做 FP 替换）。 */
    val displayLabel: String
        get() = labelZh?.takeIf { it.isNotEmpty() } ?: label?.takeIf { it.isNotEmpty() } ?: "单段"

    /** 展示层的段名：把「无FP版」换成「专注值不足版」（见 [SkillTextZh.fpText]）。 */
    val displayLabelZh: String get() = SkillTextZh.fpText(displayLabel)
}

/** 一套实际会打出的段。`atkIds` 是本战技 hits 里的 atkId 子集。 */
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

@Serializable
data class SkillEntry(
    val id: Int = -1,
    val nameZh: String = "",
    val nameEn: String = "",
    /** 训练场可用。 */
    val sparring: Boolean = false,
    val weaponIds: List<Int> = emptyList(),
    val hits: List<SkillHit> = emptyList(),
    val variants: List<SkillVariant> = emptyList(),
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
    /** counts：weapons / skills / spells / hits … 页面底部「数据版本与来源」用。 */
    val counts: Map<String, Double> = emptyMap(),
    /** 数据集自带的算法说明（选段（必读）/ 近战武器段 / … / 本数据集的边界），键的顺序即数据顺序。 */
    val usage: Map<String, String> = emptyMap(),
    /** 已知取舍（展示前要过一遍 [SkillTextZh.fpText]）。 */
    val caveats: List<String> = emptyList(),
    val weapons: List<SkillWeapon> = emptyList(),
    val skills: List<SkillEntry> = emptyList(),
    val spells: List<SpellEntry> = emptyList(),
) {
    fun count(key: String): Int = counts[key]?.toInt() ?: 0

    companion object {
        /** usage 里「本数据集的边界」的键：页面要引用（绝对伤害不在范围内）。 */
        const val USAGE_BOUNDARY = "本数据集的边界"

        /** usage 里选段规则的键。 */
        const val USAGE_SELECTION = "选段（必读）"
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
