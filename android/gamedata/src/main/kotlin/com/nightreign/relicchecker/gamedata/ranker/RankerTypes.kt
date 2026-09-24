package com.nightreign.relicchecker.gamedata.ranker

// 「增伤排名」两份数据集（skills / buffs）共用的基础类型：五个攻击力属性、九类伤害类型、三类输出手段。
//
// 口径与桌面端逐项对应：
//   · macOS：RelicCore/SkillData.swift 的 SkillElement / SkillDamageChannel，BuffLoadout.swift 的 LoadoutOutputClass；
//   · Windows：renderer/pages/ranker.js 的 ELEMENTS / TYPE_KEYS / TYPE_INFO / CASTER_WEP_TYPE。
// 伤害类型的顺序即展示顺序，也是各处「按类型索引的 9 格表」的下标（DamageType.ordinal）。

/** 五个攻击力属性槽（参数里的 dark 槽位在本作即「圣」，数据集已改名为 holy）。 */
enum class SkillElement(val key: String, val titleZh: String) {
    PHYSICAL("physical", "物理"),
    MAGIC("magic", "魔力"),
    FIRE("fire", "火"),
    LIGHTNING("lightning", "雷"),
    HOLY("holy", "圣"),
    ;

    /** 这个属性落在哪几类伤害上（物理＝五个物理子类型）。 */
    val damageTypes: List<DamageType>
        get() = DamageType.entries.filter { it.element == this }

    companion object {
        fun fromKey(key: String): SkillElement? = entries.firstOrNull { it.key == key }
    }
}

/**
 * 伤害构成的九类：物理按攻击类型细分成斩 / 打 / 突 / 标准，另留一个「物理（无类型）」给 attribute=None 的段，
 * 再加四种属性。[key] 与 Windows 端 TYPE_KEYS 逐字相同（对拍行按这个顺序打印占比）。
 */
enum class DamageType(
    val key: String,
    val titleZh: String,
    val shortZh: String,
    val element: SkillElement,
) {
    SLASH("slash", "斩击", "斩", SkillElement.PHYSICAL),
    BLOW("blow", "打击", "打", SkillElement.PHYSICAL),
    THRUST("thrust", "突刺", "突", SkillElement.PHYSICAL),
    NEUTRAL("neutral", "标准", "标准", SkillElement.PHYSICAL),
    PHYS_NONE("physNone", "物理（无类型）", "物理", SkillElement.PHYSICAL),
    MAGIC("magic", "魔力", "魔力", SkillElement.MAGIC),
    FIRE("fire", "火", "火", SkillElement.FIRE),
    LIGHTNING("lightning", "雷", "雷", SkillElement.LIGHTNING),
    HOLY("holy", "圣", "圣", SkillElement.HOLY),
    ;

    val isPhysical: Boolean get() = element == SkillElement.PHYSICAL

    companion object {
        /** 九类的个数（各处 9 格表的长度）。 */
        const val COUNT: Int = 9

        /** 五个物理子类型（physicsAttackRate 这类字段铺满它们）。 */
        val PHYSICAL: List<DamageType> = listOf(SLASH, BLOW, THRUST, NEUTRAL, PHYS_NONE)

        fun fromKey(key: String): DamageType? = entries.firstOrNull { it.key == key }

        /**
         * `enums.atkAttribute` 的 0…3（斩 / 打 / 突 / 标准）；其余取值落到「物理（无类型）」。
         * 与 Windows 端 `PHYS_BY_INDEX[code] || "physNone"`、macOS 端 `SkillDamageChannel.physical(code:)` 同一口径。
         */
        fun physical(code: Int?): DamageType = when (code) {
            0 -> SLASH
            1 -> BLOW
            2 -> THRUST
            3 -> NEUTRAL
            else -> PHYS_NONE
        }

        /** 0…3 以外返回 null（requires.physicalType / scope.atkAttribute 只认这四种）。 */
        fun physicalOrNull(code: Int?): DamageType? = when (code) {
            0 -> SLASH
            1 -> BLOW
            2 -> THRUST
            3 -> NEUTRAL
            else -> null
        }
    }
}

/**
 * appliesTo 的输出类别（本页只有这三类输出手段）。战技射出的子弹段同样按 [SKILL]。
 * [casterWepType]：法术的「出手武器」——魔法由手杖（57）施放，祷告由圣印记（61）施放（notes.userQuestions.Q2）。
 */
enum class OutputClass(val key: String, val casterWepType: Int?) {
    SKILL("skill", null),
    SORCERY("sorcery", 57),
    INCANTATION("incantation", 61),
    ;

    val isSpell: Boolean get() = this != SKILL

    /** 「战技」「魔法」「祷告」（文案常量表 outputClass.*）。 */
    val titleZh: String get() = RankerText.t("outputClass.$key")

    companion object {
        fun fromKey(key: String): OutputClass? = entries.firstOrNull { it.key == key }
    }
}

/**
 * 输出手段类型开关的三档（展示顺序即声明顺序，默认第一档「战技」；Windows 端 MEANS_KINDS）：游戏里魔法与祷告是两类，
 * 开关分成战技 / 魔法 / 祷告，抽屉的列表只列当前档（[SkillDataIndex.outputsOfKind]）。
 * 只是界面层的过滤：输出手段条目（[SkillOutput]）、所选的 [MeansSelection] 与生效判定（appliesTo 的 skill / sorcery /
 * incantation）都不变；法术按 spells[].kind 落在魔法或祷告一档（[SpellEntry.outputClass]）。文案取 meansKind.*。
 */
enum class MeansKind(val key: String, val outputClass: OutputClass) {
    SKILL("skill", OutputClass.SKILL),
    SORCERY("sorcery", OutputClass.SORCERY),
    INCANTATION("incantation", OutputClass.INCANTATION),
    ;

    /** 「战技」「魔法」「祷告」（文案常量表 meansKind.*，三端同名同值）。 */
    val titleZh: String get() = RankerText.t("meansKind.$key")

    /** 这条输出手段落在这一档吗。 */
    fun includes(output: SkillOutput): Boolean = output.outputClass == outputClass

    companion object {
        /** 默认档：战技。 */
        val DEFAULT: MeansKind = SKILL

        fun of(outputClass: OutputClass): MeansKind = entries.first { it.outputClass == outputClass }

        /** 输出手段所在的档；没有选中时为默认的「战技」。 */
        fun of(output: SkillOutput?): MeansKind = output?.let { of(it.outputClass) } ?: DEFAULT

        /** 按键读回（抽屉的 rememberSaveable 存键）：只认三档，其余（含旧的二档取值 spell）回落到默认的「战技」。 */
        fun fromKey(key: String?): MeansKind = entries.firstOrNull { it.key == key } ?: DEFAULT
    }
}

/** 9 格表（按 [DamageType.ordinal] 索引）的小工具。内部计算用 DoubleArray，对外一律给只读 List。 */
internal object TypeTables {
    fun filled(value: Double): DoubleArray = DoubleArray(DamageType.COUNT) { value }

    fun freeze(values: DoubleArray): List<Double> = values.copyOf().asList()

    /**
     * 按当前构成加权：Σ 占比 × 表 / Σ 占比。没有构成（占比全 0）时返回 null（算不出）。
     * 与 Windows 端 weightedMultiplier、macOS 端 BuffRankerIndex.effectiveMultiplier 同一口径。
     */
    fun weighted(table: List<Double>, shares: List<Double>): Double? {
        var sum = 0.0
        var weight = 0.0
        for (index in 0 until DamageType.COUNT) {
            val share = shares.getOrElse(index) { 0.0 }
            if (!(share > 0.0)) continue
            weight += share
            sum += share * table[index]
        }
        return if (weight > 0.0) sum / weight else null
    }

    /** 攻击力加算按占比加权；没有构成时为 0（与 Windows weightedFlat、macOS weightedFlat 同一口径）。 */
    fun weightedFlat(flat: List<Double>, shares: List<Double>): Double = weighted(flat, shares) ?: 0.0
}
