package com.nightreign.relicchecker.gamedata.ranker

import kotlinx.serialization.KSerializer
import kotlinx.serialization.Serializable
import kotlinx.serialization.SerializationException
import kotlinx.serialization.descriptors.SerialDescriptor
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonDecoder
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.doubleOrNull

// 增伤手段数据集（data/nightreign-buffs-v1.03.5.json，schemaVersion 6）的模型。
//
// 直接解码成下面这些不可变模型，只声明页面与配置引擎要用的字段：diagnostics / schemaChangelog / sources /
// conditionFields / chainFields / weaponAffixPools，以及 buffs[] 里的 rollableWeaponTypes、conditions、triggered、
// statusLabelsEn、chainSpEffectId 之类一律不声明，解码时跳过（3 MB 的文件里它们占了一大半）。
// appliesTo / appliesToDetail 只取本页三类输出（skill / sorcery / incantation），melee / ranged / throw 跳过。
//
// 字段含义见数据集 notes.sourceSlot / notes.appliesTo / notes.weaponAffix / notes.relicAffix / notes.stackInput /
// notes.accumulatorLadder / notes.affixVariant / notes.selfAllyPair 与 slotRules.*.zh；
// 权威实现：macOS RelicCore/BuffRanker.swift（v6 数据结构）、Windows renderer/pages/ranker.js（indexBuff）。

// ============================================================ 字段表

@Serializable
data class BuffRateField(
    val key: String = "",
    val zh: String = "",
    val en: String = "",
    /** 字段默认值（数据集只列非默认值；等于默认值的不参与乘算）。 */
    val default: Double? = null,
    val group: String = "",
    /** multiplier / flat / flag / special。 */
    val valueKind: String = "",
    val countsAsDamage: Boolean = false,
    /** 特攻（weakness）、致命一击（critical）等：只在特定条件下才乘，不进通用乘积。 */
    val conditionalDamage: Boolean = false,
    val lowerIsBetter: Boolean = false,
    val appliesTo: String = "",
) {
    /** 进通用伤害乘积的字段：countsAsDamage 且是乘数。 */
    val isRankingMultiplier: Boolean get() = countsAsDamage && valueKind == "multiplier"

    /** 攻击力加算：countsAsDamage，但必须先加进攻击力再乘倍率，只按占比加权展示。 */
    val isRankingFlat: Boolean get() = countsAsDamage && valueKind == "flat"
}

@Serializable
data class BuffRateFieldGroup(
    val key: String = "",
    val zh: String = "",
    val countsAsDamage: Boolean = false,
    val conditionalDamage: Boolean = false,
    val qualifies: Boolean = false,
    val note: String = "",
)

// ============================================================ buff 条目

@Serializable
data class BuffSourceRef(
    val kind: String = "other",
    /** inferred = true 的条目 id 恒为 null，不得联表（sourceIdContract）。 */
    val id: Int? = null,
    val nameZh: String? = null,
    val nameEn: String? = null,
    val effectNameZh: String? = null,
    val via: String = "",
    val inferred: Boolean = false,
    val paramRowCategory: String? = null,
    /** AoW 推断来源上写出的战技名（ArtsName）与战技 id。 */
    val artsNameZh: String? = null,
    val artsId: Int? = null,
    val attachEffectId: Int? = null,
) {
    val displayName: String
        get() = nameZh?.takeIf { it.isNotEmpty() }
            ?: nameEn?.takeIf { it.isNotEmpty() }
            ?: paramRowCategory?.takeIf { it.isNotEmpty() }
            ?: "未命名来源"
}

/** scope.weaponTypes：「装备 N 把 X 类武器」（equippedCount）或「用 X 类武器发动」（attackWith）。 */
@Serializable
data class BuffWeaponTypes(
    val mode: String = "",
    val wepTypes: List<Int> = emptyList(),
    val namesZh: List<String> = emptyList(),
    val field: String = "",
    val count: Int? = null,
)

@Serializable
data class BuffScope(
    val affectsSorcery: Boolean = false,
    val affectsIncantation: Boolean = false,
    val affectsShaman: Boolean = false,
    val affectsThrow: Boolean = false,
    /** wepParamChange：1 右手 / 2 左手 / 3 自身 / 4 踢击；缺失 = 不限。 */
    val weaponSlot: Int? = null,
    /** 只作用于某个物理攻击类型（0 斩 / 1 打 / 2 突 / 3 标准）；本版本 0 实例。 */
    val atkAttribute: Int? = null,
    /** 只作用于带某个特殊属性（魔 / 火 / 雷 / 圣 / 各种异常）的攻击。 */
    val spAttribute: Int? = null,
    /** magicSubCategoryChange1..3：攻击子类别过滤（112 战技攻击、123 绝招…）。 */
    val subCategories: List<Int> = emptyList(),
    /** v4：这条倍率只在列出的攻击情境（致命一击 / 突刺反击 / 蓄力战技…）下才吃得到。 */
    val attackContexts: List<String> = emptyList(),
    val weaponTypes: BuffWeaponTypes? = null,
)

@Serializable
data class BuffStacking(
    val stateInfo: Int = 0,
    val spCategory: Int = 0,
    /** none / persistThroughDeath / stackSelf / resetOnApply / removePrevious / applyHighest / applyFirst / unknown。 */
    val spCategoryBehavior: String = "unknown",
    val categoryPriority: Int = 0,
    val saveCategory: Int = -1,
    /** 分组键：stackSelf / none 时是 "sp<category>#<spEffectId>"，其余是 "sp<category>"。 */
    val group: String = "",
    /** v6：互斥键（同键只留一份，不同键相乘）。缺失时退回 group（见 [BuffEntry.exclusiveKey]）。 */
    val exclusiveKey: String = "",
    /** perSpEffect / category / categoryPriority / accumulatorLadder / affixVariant。 */
    val exclusiveScope: String = "",
)

/** buffs[].appliesTo：只取本页三类输出（skill / sorcery / incantation）；yes / no / conditional。 */
@Serializable
data class BuffAppliesTo(
    val skill: String? = null,
    val sorcery: String? = null,
    val incantation: String? = null,
) {
    operator fun get(outputClass: OutputClass): String? = when (outputClass) {
        OutputClass.SKILL -> skill
        OutputClass.SORCERY -> sorcery
        OutputClass.INCANTATION -> incantation
    }
}

/**
 * appliesToDetail.<类别>.requires：conditional 的机读条件。
 * 由 [BuffRequirementSerializer] 从原始对象解出：认得的键取值，认不出的键记进 [unknownKeys]（一律交给用户确认）。
 */
@Serializable(with = BuffRequirementSerializer::class)
data class BuffRequirement(
    /** 1 右手 / 2 左手。 */
    val hand: Int? = null,
    /** 出手武器的 wepType。 */
    val attackWeaponTypes: List<Int> = emptyList(),
    /** 只对带这条词条的那把武器生效。 */
    val attachedWeaponOnly: Boolean = false,
    /** 只对被附加属性（附魔／油脂／属性变化）的那把武器生效。 */
    val imbuedWeaponOnly: Boolean = false,
    /** 只作用于某个物理攻击类型（0 斩 / 1 打 / 2 突 / 3 标准）。 */
    val physicalType: Int? = null,
    /** 只在这些攻击情境下成立（enums.attackContext 的键）。 */
    val attackContexts: List<String> = emptyList(),
    /** 命中段的子类别与它有交集才吃得到（attackIndex 判定）。 */
    val subCategoriesAny: List<Int> = emptyList(),
    /** 本页认不出的键（数据集以后新增的条件），按字母序。 */
    val unknownKeys: List<String> = emptyList(),
) {
    /**
     * requires 里至少有一个有意义的条件（没有机读条件的 conditional 要用户确认）。
     * 与 macOS 端 BuffAppliesRequirement.hasAnyKey 同一口径。
     */
    val hasAnyKey: Boolean
        get() = hand != null || attackWeaponTypes.isNotEmpty() || attachedWeaponOnly || imbuedWeaponOnly ||
            physicalType != null || attackContexts.isNotEmpty() || subCategoriesAny.isNotEmpty() ||
            unknownKeys.isNotEmpty()

    companion object {
        val KNOWN_KEYS: Set<String> = setOf(
            "hand", "attackWeaponTypes", "attachedWeaponOnly", "imbuedWeaponOnly",
            "physicalType", "attackContexts", "subCategoriesAny",
        )
    }
}

/** appliesToDetail.<类别>：非 yes 的类别的理由与条件。 */
@Serializable
data class BuffAppliesDetail(
    val reason: String = "",
    val requires: BuffRequirement? = null,
    /** 按人口实测的命中比例（只展示）。 */
    val matchShare: Double? = null,
)

@Serializable
data class BuffAppliesDetails(
    val skill: BuffAppliesDetail? = null,
    val sorcery: BuffAppliesDetail? = null,
    val incantation: BuffAppliesDetail? = null,
) {
    operator fun get(outputClass: OutputClass): BuffAppliesDetail? = when (outputClass) {
        OutputClass.SKILL -> skill
        OutputClass.SORCERY -> sorcery
        OutputClass.INCANTATION -> incantation
    }
}

/** buffs[].relicAffixes[]：这条 buff 来自哪条遗物词条（对齐词条库）。 */
@Serializable
data class BuffRelicAffixRef(
    val attachEffectId: Int = -1,
    /** 词条库 effectId；只出现在固定遗物上的特殊词条为 null（在 relics.json 的 extraAffixes 里）。 */
    val catalogEffectId: Int? = null,
    val catalog: String = "affixes",
    val isDeepRelicAffix: Boolean = false,
    val requiresCurse: Boolean = false,
    val isCurse: Boolean = false,
    val compatibilityId: Int = -1,
    val inNormalRelicPools: Boolean = false,
    val fixedRelicOnly: Boolean = false,
    /** AttachEffectParam.exclusivityId：已装备的几件遗物之间是否互斥（-1＝没有）。 */
    val exclusivityId: Int = -1,
)

/** buffs[].weaponInnate：武器自带、不随机的效果。 */
@Serializable
data class BuffWeaponInnate(
    val attachEffectIds: List<Int> = emptyList(),
    val weaponIds: List<Int> = emptyList(),
    val wepTypes: List<Int> = emptyList(),
    /** weaponIds 为空、只能靠行名前缀归类（页面只能让用户手动勾选）。 */
    val inferredFromRowName: Boolean = false,
    val rowCategory: String? = null,
)

/** buffs[].stackInput：需要用户填层数的叠层增益（notes.stackInput）。 */
@Serializable
data class BuffStackInput(
    /** ladder（叠层阶梯，第 n 层取 tierMultipliers[n-1]）/ copies（同一效果 N 份，perStackMultiplier^N）。 */
    val mode: String = "copies",
    val paramMaxStacks: Int? = null,
    val practicalMaxStacks: Int? = null,
    val practicalMaxSource: String? = null,
    val multiplierKey: String = "",
    /** 层数换算出来的倍率要替换进 rates 的哪些字段。 */
    val appliesToRateKeys: List<String> = emptyList(),
    val tierMultipliers: List<Double> = emptyList(),
    val perStackRatio: Double? = null,
    val perStackMultiplier: Double? = null,
    /** 游戏文本备好的『＋1』到『＋N』标签数。 */
    val uiLabelMax: Int? = null,
) {
    val isLadder: Boolean get() = mode == "ladder"

    /**
     * 输入框允许的最大层数：阶梯＝参数表层数（与 tierMultipliers 长度取小）；份数型参数表无上限，
     * 页面按 [COPIES_CEILING] 截断误输入。与 Windows stackParamMax、macOS maxAllowedStacks 同一口径。
     */
    val paramMax: Int
        get() {
            if (!isLadder) return COPIES_CEILING
            val tiers = tierMultipliers.size
            val param = paramMaxStacks
            if (param != null && param > 0) return if (tiers > 0) minOf(param, tiers) else param
            return maxOf(tiers, 1)
        }

    /** 「一局实际能叠到」的上限：practicalMaxStacks，没有就退『＋N』标签数；都没有为 null。 */
    val softMax: Int?
        get() = practicalMaxStacks?.takeIf { it > 0 } ?: uiLabelMax?.takeIf { it > 0 }

    /** 勾选不占槽位的叠层条目时预填的层数：一局实际上限（没有实测上限的填 1），不超过参数表层数。 */
    val defaultStacks: Int
        get() = minOf(practicalMaxStacks?.takeIf { it > 0 } ?: 1, paramMax)

    /** 层数替换的字段：appliesToRateKeys，缺失时退回 multiplierKey。 */
    val rateKeys: List<String>
        get() = appliesToRateKeys.ifEmpty { if (multiplierKey.isNotEmpty()) listOf(multiplierKey) else emptyList() }

    /** n 层对应的倍率；n ≤ 0 或算不出时为 null（rates 保持原样）。 */
    fun multiplier(stacks: Int): Double? {
        if (stacks <= 0) return null
        val value = if (isLadder) {
            if (tierMultipliers.isNotEmpty()) {
                tierMultipliers[minOf(stacks, tierMultipliers.size) - 1]
            } else {
                perStackRatio?.takeIf { it > 0.0 }?.let { Math.pow(it, stacks.toDouble()) }
            }
        } else {
            perStackMultiplier?.takeIf { it > 0.0 }?.let { Math.pow(it, stacks.toDouble()) }
        }
        return value?.takeIf { it.isFinite() }
    }

    companion object {
        /** 份数型输入框的硬上限（参数表无上限，页面只拦住明显的误输入）。 */
        const val COPIES_CEILING: Int = 99
    }
}

/** buffs[].accumulatorLadder：连续攻击类累积阶梯（各档共用一个互斥键，用户选一档）。 */
@Serializable
data class BuffAccumulatorLadder(
    val key: String = "",
    val tier: Int = 1,
    val tiers: Int = 1,
    val tierSpEffectIds: List<Int> = emptyList(),
    val accumulatorSpEffectIds: List<Int> = emptyList(),
    val thresholds: List<Double> = emptyList(),
) {
    /** 阶梯身份（第 1 层的 spEffectId）：同一阶梯的各层共用它，选层状态按它存；没有时为 null。 */
    val ladderId: Int? get() = tierSpEffectIds.firstOrNull()
}

/** buffs[].affixVariant：同一条遗物词条下互为替代的档位（按出击武器类别只生效一档）。 */
@Serializable
data class BuffAffixVariant(
    val key: String = "",
    val attachEffectId: Int = -1,
    /** 第几档（按 spEffectId 升序，从 1 开始）。 */
    val variant: Int = 0,
    val variants: Int = 0,
    val variantSpEffectIds: List<Int> = emptyList(),
) {
    /** 组键：数据的 key，缺失时退「affix#<词条 id>」。 */
    val groupKey: String get() = key.ifEmpty { "affix#$attachEffectId" }
}

/** buffs[].selfAllyPair：同一战技成对的 Self／Allies 两行（算施放者自己只计 Self 那一行）。 */
@Serializable
data class BuffSelfAllyPair(
    /** self / ally（与 target 一致）。 */
    val role: String = "",
    val counterpartSpEffectId: Int = -1,
)

@Serializable
data class BuffEntry(
    val spEffectId: Int = -1,
    val nameZh: String? = null,
    val nameEn: String? = null,
    /** 列表一律显示它（生成时已保证全表唯一）。 */
    val displayNameZh: String? = null,
    val displayNameEn: String? = null,
    val paramName: String? = null,
    val suggestedNameZh: String? = null,
    val sources: List<BuffSourceRef> = emptyList(),
    val rates: Map<String, Double> = emptyMap(),
    /** increase / decrease / mixed。 */
    val direction: String = "increase",
    val scope: BuffScope = BuffScope(),
    val stacking: BuffStacking = BuffStacking(),
    /** 秒；-1 表示永久。 */
    val duration: Double = -1.0,
    val permanent: Boolean = false,
    /** self / ally / summon / enemy。 */
    val target: String = "self",
    /** passive / conditional / activated。 */
    val activation: String = "passive",
    val activationSource: String = "",
    val descZh: String? = null,
    /** nameZh 借用了同族词条的名字（同一条词条的不同档位）。 */
    val inferredName: Boolean = false,
    /** v5：status 组的加算点数是累在玩家自己身上的自伤（伤害乘积不受影响，只打标）。 */
    val selfInflictedStatus: Boolean = false,
    /** 这条 buff 该放进配置页的哪一栏（enums.sourceSlot）。 */
    val sourceSlot: String = "other",
    /** 全部槽位（[0] 就是 sourceSlot）。 */
    val sourceSlots: List<String> = emptyList(),
    val sourceSlotReason: String? = null,
    val appliesTo: BuffAppliesTo? = null,
    val appliesToDetail: BuffAppliesDetails = BuffAppliesDetails(),
    /** 局内武器词条：AttachEffect id、角色（affix / curse / blessing / fixed）、是否只在深夜池出现。 */
    val weaponAffixIds: List<Int> = emptyList(),
    val weaponAffixRoles: List<String> = emptyList(),
    val weaponAffixDeepOnly: Boolean = false,
    /** 正面的深夜专属词条（深夜每把武器最多 1 条、合计最多 6 条的计数口径）。 */
    val weaponAffixDeepOnlyPositive: Boolean = false,
    val relicAffixes: List<BuffRelicAffixRef> = emptyList(),
    val weaponInnate: BuffWeaponInnate? = null,
    val stackInput: BuffStackInput? = null,
    val accumulatorLadder: BuffAccumulatorLadder? = null,
    /** 只在使用这些道具（GoodsName id）时才成立。 */
    val requiresGoodsIds: List<Int> = emptyList(),
    val affixVariant: BuffAffixVariant? = null,
    val selfAllyPair: BuffSelfAllyPair? = null,
) {
    /** 显示名：displayNameZh → nameZh → displayNameEn → nameEn → paramName → #id（两端 buffDisplayName 同一口径）。 */
    val displayName: String
        get() = displayNameZh?.takeIf { it.isNotEmpty() }
            ?: nameZh?.takeIf { it.isNotEmpty() }
            ?: displayNameEn?.takeIf { it.isNotEmpty() }
            ?: nameEn?.takeIf { it.isNotEmpty() }
            ?: paramName?.takeIf { it.isNotEmpty() }
            ?: "#$spEffectId"

    val isPassive: Boolean get() = activation == "passive"

    /** 来源全靠 Paramdex 行名推断（物品归属未经验证，倍率数值本身仍是原始值；macOS isInferredSource）。 */
    val isInferredSource: Boolean get() = sources.isNotEmpty() && sources.all { it.inferred }

    /** 至少一个来源是推断出来的（Windows indexBuff 的 inferred）。 */
    val hasInferredSource: Boolean get() = sources.any { it.inferred }

    /** 去重后的来源类型，按数据集里的出现顺序。 */
    val sourceKinds: List<String> get() = sources.map { it.kind }.distinct()

    /** 互斥键：exclusiveKey，缺失时退回 stacking.group，再退回 sp<cat>#<id>（Windows exclusiveKeyOf）。 */
    val exclusiveKey: String
        get() = stacking.exclusiveKey.ifEmpty { stacking.group.ifEmpty { "sp${stacking.spCategory}#$spEffectId" } }
}

// ============================================================ 顶层清单

/** weaponAffixes[]：有增伤 buff 的局内武器词条（按 AttachEffect id）。 */
@Serializable
data class BuffWeaponAffixInfo(
    val attachEffectId: Int = -1,
    val nameZh: String = "",
    val nameEn: String = "",
    val paramName: String? = null,
    /** 档位 1 / 2 / 3（没有档位的为 null）。 */
    val potency: Int? = null,
    val roles: List<String> = emptyList(),
    val isDebuff: Boolean = false,
    val compatibilityId: Int = -1,
    val normalWepTypes: List<Int> = emptyList(),
    val deepWepTypes: List<Int> = emptyList(),
    val deepOnly: Boolean = false,
    val deepOnlyPositive: Boolean = false,
    val tableIds: List<Int> = emptyList(),
    val spEffectIds: List<Int> = emptyList(),
) {
    val isCurse: Boolean get() = "curse" in roles
    val isBlessing: Boolean get() = "blessing" in roles
    val isFixed: Boolean get() = "fixed" in roles && "affix" !in roles
    val displayName: String get() = nameZh.ifEmpty { nameEn.ifEmpty { "#$attachEffectId" } }
}

/** fixedRelics[]：官方固定词条遗物（整件占一个遗物格）。 */
@Serializable
data class BuffFixedRelic(
    val relicIds: List<Int> = emptyList(),
    val nameZh: String = "",
    val nameEn: String = "",
    /** 0 红 / 1 蓝 / 2 黄 / 3 绿 / 4 白。 */
    val color: Int = -1,
    val isDeepRelic: Boolean = false,
    val attachEffectIds: List<Int> = emptyList(),
    val curseAttachEffectIds: List<Int> = emptyList(),
    /** 与 attachEffectIds 一一对应；没有中文名的位置为 null。 */
    val attachEffectNamesZh: List<String?> = emptyList(),
    val spEffectIds: List<Int> = emptyList(),
) {
    val relicId: Int get() = relicIds.firstOrNull() ?: -1

    /** 配置里标识这件遗物的键（relicIds 用「-」连接；Windows fixedRelicByKey 同一口径）。 */
    val key: String get() = relicIds.joinToString("-").ifEmpty { nameZh }
}

/** attackIndex 里一组命中段的子类别集合与段数（近战／射击人口里是 rows）。 */
@Serializable
data class BuffSubCategorySet(
    val subs: List<Int> = emptyList(),
    val hits: Int = 0,
    val rows: Int = 0,
)

@Serializable
data class BuffAttackIndexEntry(
    val nameZh: String = "",
    val subCategorySets: List<BuffSubCategorySet> = emptyList(),
)

// ============================================================ slotRules

@Serializable
data class BuffSlotModeRule(
    val zh: String = "",
    val weaponAffixesPerWeapon: Int = 1,
    val relicSlots: Int = 3,
    val weaponCursesPerWeapon: Int = 0,
    val deepOnlyAffixesPerWeapon: Int = 0,
)

@Serializable
data class BuffSlotModes(
    val normal: BuffSlotModeRule = BuffSlotModeRule(),
    val deep: BuffSlotModeRule = BuffSlotModeRule(
        weaponAffixesPerWeapon = 2, relicSlots = 6, weaponCursesPerWeapon = 1, deepOnlyAffixesPerWeapon = 1,
    ),
    val zh: String = "",
)

@Serializable
data class BuffDuplicateRule(
    val status: String = "unknown",
    val likelyKey: String = "",
    val zh: String = "",
)

@Serializable
data class BuffWeaponAffixRules(
    val maxWeapons: Int = 6,
    val normalPerWeapon: Int = 1,
    val deepPerWeapon: Int = 2,
    val deepCursePerWeapon: Int = 1,
    val maxAffixesNormal: Int = 6,
    val maxAffixesDeep: Int = 12,
    val deepOnlyPerWeaponMax: Int = 1,
    val maxDeepOnlyAffixes: Int = 6,
    val deepOnlyCapField: String = "weaponAffixDeepOnlyPositive",
    val deepOnlyCapCountsCurses: Boolean = false,
    val duplicateWithinWeapon: BuffDuplicateRule = BuffDuplicateRule(),
    val zh: String = "",
)

@Serializable
data class BuffRelicRules(
    val normal: Int = 3,
    val deepExtra: Int = 3,
    val affixesPerRelic: Int = 3,
    val curseAffixesPerDeepRelic: Int = 3,
    val zh: String = "",
)

@Serializable
data class BuffAccessoryRules(
    val slots: Int = 2,
    val measured: Boolean = false,
    val zh: String = "",
)

@Serializable
data class BuffZhNote(val zh: String = "")

/** slotRules：常规／深夜的武器词条、遗物、护符槽位；缺字段时退回与桌面端同值的兜底。 */
@Serializable
data class BuffSlotRules(
    val modes: BuffSlotModes = BuffSlotModes(),
    val weaponAffix: BuffWeaponAffixRules = BuffWeaponAffixRules(),
    val relic: BuffRelicRules = BuffRelicRules(),
    val accessory: BuffAccessoryRules = BuffAccessoryRules(),
    val consumable: BuffZhNote? = null,
    val spellBuff: BuffZhNote? = null,
    val weaponSkill: BuffZhNote? = null,
    val weaponInnate: BuffZhNote? = null,
    val character: BuffZhNote? = null,
    val permanent: BuffZhNote? = null,
    val runStack: BuffZhNote? = null,
) {
    /** consumable / spellBuff / … 这些不限数量的栏目的说明（没有的不列）。 */
    val slotlessZh: Map<String, String>
        get() = linkedMapOf(
            "consumable" to consumable, "spellBuff" to spellBuff, "weaponSkill" to weaponSkill,
            "weaponInnate" to weaponInnate, "character" to character, "permanent" to permanent,
            "runStack" to runStack,
        ).mapNotNull { (key, note) -> note?.zh?.takeIf { it.isNotEmpty() }?.let { key to it } }.toMap()
}

// ============================================================ 自定义解码

/**
 * requires 是一个开放的对象：认得的键按类型取值（数字 / 布尔 / 数字字符串都收），认不出的键记下来交给用户确认。
 * 只在 [BuffRequirement] 上用，对象很小，建 JsonElement 不影响性能。
 */
object BuffRequirementSerializer : KSerializer<BuffRequirement> {
    override val descriptor: SerialDescriptor = JsonObject.serializer().descriptor

    override fun deserialize(decoder: Decoder): BuffRequirement {
        val json = decoder as? JsonDecoder ?: throw SerializationException("requires 只支持 JSON 解码")
        val element = json.decodeJsonElement() as? JsonObject ?: return BuffRequirement()
        return BuffRequirement(
            hand = element["hand"].intValue(),
            attackWeaponTypes = element["attackWeaponTypes"].intList(),
            attachedWeaponOnly = element["attachedWeaponOnly"].boolValue(),
            imbuedWeaponOnly = element["imbuedWeaponOnly"].boolValue(),
            physicalType = element["physicalType"].intValue(),
            attackContexts = element["attackContexts"].stringList(),
            subCategoriesAny = element["subCategoriesAny"].intList(),
            unknownKeys = element.keys.filter { it !in BuffRequirement.KNOWN_KEYS }.sorted(),
        )
    }

    override fun serialize(encoder: Encoder, value: BuffRequirement) {
        throw SerializationException("BuffRequirement 只用于解码")
    }

    private fun JsonElement?.number(): Double? {
        val primitive = this as? JsonPrimitive ?: return null
        if (primitive is JsonNull) return null
        primitive.doubleOrNull?.let { return it.takeIf { value -> value.isFinite() } }
        primitive.booleanOrNull?.let { return if (it) 1.0 else 0.0 }
        return null
    }

    private fun JsonElement?.intValue(): Int? = number()?.let { Math.round(it).toInt() }

    private fun JsonElement?.boolValue(): Boolean {
        val primitive = this as? JsonPrimitive ?: return false
        if (primitive is JsonNull) return false
        primitive.booleanOrNull?.let { return it }
        return (primitive.doubleOrNull ?: 0.0) != 0.0
    }

    private fun JsonElement?.intList(): List<Int> =
        (this as? JsonArray)?.mapNotNull { it.number()?.let { value -> Math.round(value).toInt() } } ?: emptyList()

    private fun JsonElement?.stringList(): List<String> =
        (this as? JsonArray)?.mapNotNull { (it as? JsonPrimitive)?.takeIf { p -> p.isString }?.content } ?: emptyList()
}
