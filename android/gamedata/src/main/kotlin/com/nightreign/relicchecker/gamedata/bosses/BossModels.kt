package com.nightreign.relicchecker.gamedata.bosses

// 「首领数据」页的基础模型：属性 / 异常、人数、深夜模式、缩放档位、变异个体、深度与游戏文本。
// 与 macOS 端 RelicCore/BossData.swift 的同名类型一一对应（数值口径以它为准）。

/** 四舍五入到最近整数，.5 远离 0（Swift 的 `.rounded()`）。 */
internal fun Double.roundHalfAway(): Int =
    if (this >= 0) kotlin.math.floor(this + 0.5).toInt() else -kotlin.math.floor(-this + 0.5).toInt()

enum class BossDamageKind(val key: String, val titleZh: String, val affinityCode: Int?) {
    STANDARD("standard", "标准", null),
    SLASH("slash", "斩击", null),
    STRIKE("strike", "打击", null),
    PIERCE("pierce", "突刺", null),
    MAGIC("magic", "魔力", 1),
    FIRE("fire", "火", 2),
    LIGHTNING("lightning", "雷", 3),
    HOLY("holy", "圣", 4),
    ;

    val isPhysical: Boolean get() = affinityCode == null
}

enum class BossAilmentKind(val key: String, val titleZh: String, val affinityCode: Int) {
    POISON("poison", "中毒", 5),
    ROT("rot", "猩红腐败", 6),
    BLEED("bleed", "出血", 7),
    FROST("frost", "冻伤", 9),
    SLEEP("sleep", "睡眠", 10),
    MADNESS("madness", "发狂", 11),
    DEATH("death", "死亡", 8),
}

data class BossDamageRates(
    val standard: Double = 1.0,
    val slash: Double = 1.0,
    val strike: Double = 1.0,
    val pierce: Double = 1.0,
    val magic: Double = 1.0,
    val fire: Double = 1.0,
    val lightning: Double = 1.0,
    val holy: Double = 1.0,
) {
    fun value(kind: BossDamageKind): Double = when (kind) {
        BossDamageKind.STANDARD -> standard
        BossDamageKind.SLASH -> slash
        BossDamageKind.STRIKE -> strike
        BossDamageKind.PIERCE -> pierce
        BossDamageKind.MAGIC -> magic
        BossDamageKind.FIRE -> fire
        BossDamageKind.LIGHTNING -> lightning
        BossDamageKind.HOLY -> holy
    }

    /** 倍率 > 1 的属性（按倍率降序，同倍率按声明顺序）。 */
    val weakKinds: List<BossDamageKind>
        get() = BossDamageKind.entries.filter { value(it) > 1 }
            .sortedWith(compareByDescending<BossDamageKind> { value(it) }.thenBy { it.ordinal })

    /** 倍率 < 1 的属性（按倍率升序，同倍率按声明顺序）。 */
    val resistantKinds: List<BossDamageKind>
        get() = BossDamageKind.entries.filter { value(it) < 1 }
            .sortedWith(compareBy<BossDamageKind> { value(it) }.thenBy { it.ordinal })

    companion object {
        val NEUTRAL = BossDamageRates()
    }
}

data class BossResistances(
    val poison: Int = 0,
    val rot: Int = 0,
    val bleed: Int = 0,
    val frost: Int = 0,
    val sleep: Int = 0,
    val madness: Int = 0,
    val death: Int = 0,
) {
    fun value(kind: BossAilmentKind): Int = when (kind) {
        BossAilmentKind.POISON -> poison
        BossAilmentKind.ROT -> rot
        BossAilmentKind.BLEED -> bleed
        BossAilmentKind.FROST -> frost
        BossAilmentKind.SLEEP -> sleep
        BossAilmentKind.MADNESS -> madness
        BossAilmentKind.DEATH -> death
    }

    fun isImmune(kind: BossAilmentKind): Boolean = value(kind) >= IMMUNE_THRESHOLD

    val immuneKinds: List<BossAilmentKind> get() = BossAilmentKind.entries.filter(::isImmune)

    companion object {
        /** 数据集里 999 表示免疫。 */
        const val IMMUNE_THRESHOLD = 999
    }
}

enum class BossPartySize(val players: Int) {
    SOLO(1),
    DUO(2),
    TRIO(3),
    ;

    val title: String get() = "$players 人"

    val shortTitle: String
        get() = when (this) {
            SOLO -> "单人"
            DUO -> "双人"
            TRIO -> "三人"
        }

    companion object {
        fun of(players: Int): BossPartySize = entries.firstOrNull { it.players == players } ?: SOLO
    }
}

data class BossAttackRates(
    val physical: Double = 1.0,
    val magic: Double = 1.0,
    val fire: Double = 1.0,
    val lightning: Double = 1.0,
    val holy: Double = 1.0,
) {
    val isUniform: Boolean
        get() = physical == magic && magic == fire && fire == lightning && lightning == holy

    fun scaled(factor: Double): BossAttackRates = BossAttackRates(
        physical * factor, magic * factor, fire * factor, lightning * factor, holy * factor,
    )

    companion object {
        val NEUTRAL = BossAttackRates()
    }
}

/** MultiPlayCorrectionParam 的一档（双人或三人）。 */
data class BossScalingTier(
    /** 血量倍率（maxHpRate）。 */
    val hp: Double,
    /** 承受削韧倍率（saReceiveDamageRate）。 */
    val poiseTaken: Double,
    /** 削韧恢复速度倍率。 */
    val poiseRecover: Double,
    /** 异常发动时的伤害倍率。 */
    val ailmentDamageRate: Double,
    /** 中毒 / 腐败的发动伤害倍率。 */
    val poisonRate: Double,
    /** Boss 承受的异常累积量倍率（越小越难打出异常）。 */
    val buildupRate: Double,
    /** 敌人攻击力倍率：7744 / 7753 / 7754 / 7758 四档双人 1.1、三人 1.2。 */
    val attackRate: Double = 1.0,
    val staminaAttackRate: Double = 1.0,
) {
    /** 该档位是否让敌人攻击力上浮（> 1）。 */
    val raisesAttack: Boolean get() = attackRate > 1.0001

    companion object {
        /** 单人（不做任何人数缩放）。 */
        val IDENTITY = BossScalingTier(1.0, 1.0, 1.0, 1.0, 1.0, 1.0)
    }
}

data class BossScalingPair(val duo: BossScalingTier?, val trio: BossScalingTier?) {
    /** 缺档时按单人（不缩放）处理。 */
    fun tier(players: BossPartySize): BossScalingTier = when (players) {
        BossPartySize.SOLO -> BossScalingTier.IDENTITY
        BossPartySize.DUO -> duo ?: BossScalingTier.IDENTITY
        BossPartySize.TRIO -> trio ?: BossScalingTier.IDENTITY
    }
}

/** 顶层 scalingTiers 的一项（带 Paramdex 分组名）。 */
data class BossScalingGroup(
    val id: Int,
    val group: String?,
    val duo: BossScalingTier?,
    val trio: BossScalingTier?,
) {
    val title: String get() = title(group)

    val pair: BossScalingPair get() = BossScalingPair(duo, trio)

    companion object {
        /** 档位分组的中文标签（group = null / 空串时为「其它档位」，未知分组原样显示）。 */
        fun title(group: String?): String = when {
            group == "Field Boss Threat" -> "野外首领威胁档"
            group == "Night Boss Threat" -> "守夜首领威胁档"
            group == "Final Boss Threat" -> "最终首领威胁档"
            !group.isNullOrEmpty() -> group
            else -> "其它档位"
        }
    }
}

/** 顶层 permanentScaling 的一项：常驻挂在 NpcParam 上的缩放 SpEffect。 */
data class BossPermanentEffect(
    val id: Int,
    val nameEn: String?,
    val nameZh: String,
    val hp: Double,
    val poiseTaken: Double,
    val poiseRecover: Double,
    val ailmentDamageRate: Double,
    val attackRate: Double,
    val attackRates: BossAttackRates,
    val staminaAttackRate: Double,
    /** true 表示只在「深夜」模式生效。 */
    val deepOfNight: Boolean,
) {
    val displayName: String
        get() = when {
            nameZh.isNotEmpty() -> nameZh
            !nameEn.isNullOrEmpty() -> nameEn
            else -> "常驻缩放 #$id"
        }

    /** 明细一行的各项倍率（与 macOS 的 BossPermanentEffectRow 同文案）；为空时页面写「无数值改动」。 */
    val factorParts: List<String>
        get() {
            val items = mutableListOf<String>()
            if (hp != 1.0) items += "血量 " + BossFormat.multiplier(hp, 4)
            if (attackRate != 1.0) items += "攻击力 " + BossFormat.multiplier(attackRate, 4)
            if (!attackRates.isUniform) {
                items += "（攻击力按属性分开：物 " + BossFormat.decimal(attackRates.physical, 4) +
                    " / 魔 " + BossFormat.decimal(attackRates.magic, 4) +
                    " / 火 " + BossFormat.decimal(attackRates.fire, 4) +
                    " / 雷 " + BossFormat.decimal(attackRates.lightning, 4) +
                    " / 圣 " + BossFormat.decimal(attackRates.holy, 4) + "）"
            }
            if (poiseTaken != 1.0) items += "承受削韧 " + BossFormat.multiplier(poiseTaken, 4)
            if (poiseRecover != 1.0) items += "削韧恢复 " + BossFormat.multiplier(poiseRecover, 4)
            if (ailmentDamageRate != 1.0) items += "异常发动伤害 " + BossFormat.multiplier(ailmentDamageRate, 4)
            if (staminaAttackRate != 1.0) items += "削玩家耐力 " + BossFormat.multiplier(staminaAttackRate, 4)
            return items
        }
}

/** 「深夜」模式下的同一组基准数值（不含深度倍率，深度在 depthStats 里）。 */
data class BossDeepOfNightStats(
    val hp: Int,
    val hpMultiplier: Double,
    val poiseTakenBase: Double,
    val poiseRecoverMultiplier: Double,
    val ailmentDamageRateBase: Double,
    val attackRateBase: Double,
    val permScalingIds: List<Int>,
)

/** 「深夜 · 深度 N」下的一组基准数值：hp 已含常驻威胁档位 × 深夜修正 × 深度 N 倍率。 */
data class BossDepthStats(
    val hp: Int,
    val hpMultiplier: Double,
    val poiseTakenBase: Double,
    val attackRateBase: Double,
)

/** 变异个体（游戏内简中正式叫法；社区俗称「红化」）的一档倍率。 */
data class BossMutation(
    /** SpEffectSetParam 行号（mutationPool 里存的就是它）。 */
    val id: Int,
    val nameZh: String,
    val nameEn: String,
    val setNameEn: String?,
    val vfxSpEffectIds: List<Int>,
    val vfxTier: Int?,
    /** 数值档位的 SpEffect 行号（7220 / 7230 / 7240 / 7241）。 */
    val statSpEffectId: Int?,
    val statNameEn: String?,
    val hp: Double,
    val attackRate: Double,
    val runeRate: Double,
) {
    /** 「血量 ×1.15 · 攻击 ×1.15 · 卢恩 ×1.35」。 */
    val summary: String
        get() = "血量 ×${BossFormat.decimal(hp)} · 攻击 ×${BossFormat.decimal(attackRate)}" +
            " · 卢恩 ×${BossFormat.decimal(runeRate)}"

    /** 「#113240 · 血量 ×1.15 · 攻击 ×1.15 · 卢恩 ×1.35」。 */
    val pickerTitle: String get() = "#$id · $summary"
}

/** ChaosMatchingMutationCategoryParam 的一行：某地图某类敌人在各深度有几只被变异（只数，不是概率）。 */
data class BossMutationCategory(
    val rowId: Int,
    val categoryId: Int,
    val categoryZh: String,
    val categoryEn: String,
    val mapId: Int,
    val mapZh: String,
    val mapEn: String,
    val mutatedCount: Map<Int, Int>,
) {
    fun count(depth: Int): Int = mutatedCount[depth] ?: 0

    val categoryTitle: String get() = categoryZh.ifEmpty { categoryEn }
    val mapTitle: String get() = mapZh.ifEmpty { mapEn }
}

data class BossMapChallengeWeight(val map: Double = 0.0, val nightlord: Double = 0.0, val none: Double = 0.0)

/** ChaosMatchingRankControlParam 的一行（深度 1…5 的全局控制，不含血量攻击倍率）。 */
data class BossDepthInfo(
    val rankId: Int,
    val paramdexName: String?,
    val labelZh: String,
    val labelEn: String,
    val cursedUncommonRate: Double,
    val cursedRareRate: Double,
    val mapChallengeWeight: BossMapChallengeWeight,
    val cataclysmWeight: Map<Int, Int>,
) {
    val title: String get() = labelZh.ifEmpty { labelEn }
}

data class BossDepthTierStats(
    val spEffectId: Int?,
    val nameEn: String?,
    val hp: Double,
    val attackRate: Double,
    val poiseTaken: Double,
    val staminaAttackRate: Double,
)

/** deepOfNightTiers 的一档：某个 ChaosMatchingCorrectParam 行号在 5 个深度上的倍率。 */
data class BossDepthTier(
    val id: Int,
    val group: String?,
    /** Paramdex 的档位名，如 "Tier 3f"。 */
    val tier: String?,
    val depths: Map<Int, BossDepthTierStats>,
) {
    val title: String get() = BossScalingGroup.title(group)
}

/** 一条游戏内文本（CL_MenuText）。 */
data class BossGameText(val zh: String, val en: String, val textId: Int?) {
    val display: String get() = zh.ifEmpty { en }
    val isEmpty: Boolean get() = zh.isEmpty() && en.isEmpty()

    companion object {
        val EMPTY = BossGameText("", "", null)
    }
}

/** 顶层 deepOfNightText：深夜 / 深度 / 变异个体的游戏内简中原文。 */
data class BossDeepOfNightText(
    val deepOfNight: BossGameText,
    val depth: BossGameText,
    val mutation: BossGameText,
    val mutationCount: BossGameText,
    val description: BossGameText,
) {
    val deepOfNightTitle: String get() = deepOfNight.display.ifEmpty { FALLBACK.deepOfNight.zh }
    val depthTitle: String get() = depth.display.ifEmpty { FALLBACK.depth.zh }

    /** 「变异个体」：游戏文本 338806 是「已打倒变异个体」这种整句，这里收敛成名词。 */
    val mutationTitle: String
        get() {
            val text = mutation.zh
            if (text.contains("变异个体")) return "变异个体"
            return text.ifEmpty { FALLBACK.mutation.zh }
        }

    companion object {
        val FALLBACK = BossDeepOfNightText(
            deepOfNight = BossGameText("深夜", "The Deep of Night", null),
            depth = BossGameText("深度", "Depth", null),
            mutation = BossGameText("变异个体", "Variant", null),
            mutationCount = BossGameText.EMPTY,
            description = BossGameText.EMPTY,
        )
    }
}

/** 页面顶部的模式选择：常规，或「深夜 · 深度 1…5」。 */
enum class BossNightMode(val depth: Int?) {
    NORMAL(null),
    DEPTH1(1),
    DEPTH2(2),
    DEPTH3(3),
    DEPTH4(4),
    DEPTH5(5),
    ;

    val isDeepOfNight: Boolean get() = this != NORMAL

    /** 数据集缺 deepOfNightText 时的兜底标题。 */
    val builtinTitle: String get() = title(depth, "深夜", "深度")

    companion object {
        fun depth(value: Int): BossNightMode = entries.firstOrNull { it.depth == value } ?: NORMAL

        fun title(depth: Int?, deepOfNight: String, depthWord: String): String =
            if (depth == null) "常规" else "$deepOfNight · $depthWord $depth"
    }
}

/** 削韧槽的三种语义：poise > 0 能算有效韧性；= 0 没有削韧槽；< 0 不吃削韧。 */
enum class BossPoiseKind(val placeholder: String) {
    VALUE("—"),
    ZERO("无削韧槽"),
    NONE("不吃削韧"),
}

/** 菜单参数标注的官方弱点。 */
data class BossWeakness(val code: Int, val zh: String, val en: String) {
    val display: String get() = zh.ifEmpty { en }
}

data class BossSource(
    val name: String,
    val url: String,
    val revision: String,
    val license: String,
    val usage: String,
)

/** 名字对照的证据：命中（或被挡下）的那条游戏文本词条。 */
data class BossNameEvidence(
    val fmg: String,
    val id: String,
    val en: String,
    val zh: String,
    val reason: String,
) {
    /** 「item/NpcName #905011000 · Golden Hippopotamus / 黄金河马」。 */
    val summary: String
        get() {
            var text = fmg.ifEmpty { "游戏文本" }
            if (id.isNotEmpty()) text += " #$id"
            val names = listOf(en, zh).filter { it.isNotEmpty() }.joinToString(" / ")
            if (names.isNotEmpty()) text += " · $names"
            return text
        }
}

data class BossUnmatchedName(val nameEn: String, val chrId: Int)

data class BossNotes(
    val unmatchedNames: List<BossUnmatchedName>,
    val nameCollisionCount: Int,
    /** 多人缩放的逐项核实结论（9 条中文）。 */
    val multiplayerScalingAudit: List<String>,
    /** 深夜 / 深度 / 变异个体的核实结论（11 条中文）。 */
    val deepOfNightAudit: List<String>,
    /** notes.roleAudit.summary（4 条中文）。 */
    val roleAuditSummary: List<String>,
)

data class BossRoleName(val zh: String, val en: String, val description: String)

data class BossRoleSummaryDetail(
    val groups: Int,
    val variants: Int,
    val rows: Int,
    val nightlords: Int,
    val fights: Int,
    val fightRows: Int,
)

/** placementMaps 的一项：地图的 Paramdex 名，或开放地块的地形名。 */
data class BossPlacementMap(val paramdexName: String?, val tileVariantZh: String) {
    val name: String get() = paramdexName?.takeIf { it.isNotEmpty() } ?: tileVariantZh
}
