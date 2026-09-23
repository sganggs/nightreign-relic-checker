package com.nightreign.relicchecker.gamedata.ranker

// 排名核心的输入与输出模型：当前输出手段（RankerOutput）、appliesTo 判定（AppliesVerdict）、
// 单条评估（EvaluatedEntry）与「全部增益一览」的一行（OverviewRow）。
// 与 macOS 端 BuffLoadout.swift 的 LoadoutOutput / LoadoutVerdict / LoadoutEvaluator.Work / LoadoutOverviewRow、
// Windows 端 ranker.js 的 makeOutput / appliesVerdict / evaluateEntry 返回的 item 一一对应。

/** 「这条真的增伤吗」的阈值：差在小数第七位的只是加权求和的浮点噪音（两端同值）。 */
const val USEFUL_EPSILON: Double = 1.0000001

/** 比较倍率时的容差（两端同值）：两个倍率相差不超过它就算相同。 */
const val RANK_EPSILON: Double = 1e-9

/**
 * 当前的输出手段（决定 appliesTo 走哪一类、conditional 怎么判）。
 *
 * @property meansId 战技 / 法术的 id（查 attackIndex 的子类别用）。
 * @property weaponWepType 战技所用武器的 wepType；法术为 null（出手武器类别按施法器取，见 [attackWepType]）。
 * @property hand 1 右手 / 2 左手（其它值按右手）。
 * @property shares 按 [DamageType.ordinal] 索引的伤害占比（和为 1；全 0 表示没有勾选任何带伤害的段）。
 * @property attackContexts 用户勾选的攻击情境（enums.attackContext 的键）。
 */
data class RankerOutput(
    val outputClass: OutputClass,
    val meansId: Int?,
    val weaponId: Int? = null,
    val weaponWepType: Int? = null,
    val hand: Int = 1,
    val shares: List<Double> = List(DamageType.COUNT) { 0.0 },
    val attackContexts: Set<String> = emptySet(),
) {
    val normalizedHand: Int get() = if (hand == 2) 2 else 1

    val hasComposition: Boolean get() = shares.any { it > 0.0 }

    fun share(type: DamageType): Double = shares.getOrElse(type.ordinal) { 0.0 }

    /** 出手武器类别：战技＝所选武器的 wepType；魔法＝手杖（57）；祷告＝圣印记（61）。 */
    val attackWepType: Int? get() = if (outputClass == OutputClass.SKILL) weaponWepType else outputClass.casterWepType

    companion object {
        fun skill(
            skillId: Int,
            weapon: SkillWeapon?,
            composition: DamageComposition,
            hand: Int = 1,
            attackContexts: Set<String> = emptySet(),
        ): RankerOutput = RankerOutput(
            outputClass = OutputClass.SKILL,
            meansId = skillId,
            weaponId = weapon?.id,
            weaponWepType = weapon?.wepType,
            hand = hand,
            shares = composition.shares,
            attackContexts = attackContexts,
        )

        fun spell(
            spell: SpellEntry,
            composition: DamageComposition,
            hand: Int = 1,
            attackContexts: Set<String> = emptySet(),
        ): RankerOutput = RankerOutput(
            outputClass = spell.outputClass,
            meansId = spell.id,
            hand = hand,
            shares = composition.shares,
            attackContexts = attackContexts,
        )
    }
}

/** 数据里的 appliesTo 取值（缺失时为 MISSING）。 */
enum class VerdictValue(val key: String) { YES("yes"), NO("no"), CONDITIONAL("conditional"), MISSING("missing") }

/** 判定结果：YES 生效 / NO 不生效 / CONTEXT 要勾选攻击情境 / PENDING 要用户确认。 */
enum class VerdictState(val key: String) { YES("yes"), NO("no"), CONTEXT("context"), PENDING("pending") }

enum class RequirementState { MET, UNMET, PARTIAL, NEEDS_USER }

/** 逐项条件（详情展示用）。[share] 只在 PARTIAL 时有值（命中段占比）。 */
data class Requirement(val key: String, val text: String, val state: RequirementState, val share: Double? = null)

/** 一条 buff 对当前输出手段的 appliesTo 判定。 */
data class AppliesVerdict(
    val value: VerdictValue,
    val state: VerdictState,
    /** 不生效（NO / CONTEXT）的原因；PENDING 时是 appliesToDetail.reason。 */
    val reasons: List<String>,
    /** 要用户确认的条件（imbuedWeaponOnly、需同时使用道具、认不出的键…）。 */
    val needs: List<String>,
    /** 部分段命中的近似说明。 */
    val notes: List<String>,
    /** 1 = 全部生效；(0, 1) = 子类别只有部分段命中、按段数近似折算。 */
    val weight: Double,
    /** requires.physicalType：倍率只落在这一个物理通道。 */
    val restrictedType: DamageType?,
    val requirements: List<Requirement>,
    /** CONTEXT 时：要勾选的攻击情境键。 */
    val contexts: List<String>,
    val activation: String,
    /** activation ≠ passive 时的说明（条件型 / 发动型 / 装备中有 N 把以上 X）。 */
    val activationNote: String?,
) {
    val isApplicable: Boolean get() = state == VerdictState.YES || state == VerdictState.PENDING
    val isPartial: Boolean get() = isApplicable && weight < 1.0
    val needsConfirmation: Boolean get() = needs.isNotEmpty() || activationNote != null

    /** 不生效时给用户看的原因。 */
    val blockedReason: String?
        get() = if (isApplicable) null else reasons.firstOrNull() ?: RankerText.t("verdictNoFallback")

    /** 生效判定的短标签（两端同一口径）：不生效 → 部分段生效 → 要确认 → 条件已满足 → 生效。 */
    val label: String
        get() = when {
            !isApplicable -> RankerText.t("verdict.no")
            weight < 1.0 -> RankerText.t("verdict.partial")
            needs.isNotEmpty() || activation != "passive" -> RankerText.t("verdict.needsUser")
            value == VerdictValue.CONDITIONAL -> RankerText.t("verdict.conditionalMet")
            else -> RankerText.t("verdict.yes")
        }
}

/** 单条评估后的状态（键与 Windows 端 item.state、文案常量表 states.* 一致）。 */
enum class EntryState(val key: String) {
    COUNTED("counted"),
    DUPLICATE("duplicate"),
    PENDING("pending"),
    CONTEXT("context"),
    NO("no"),
    ZERO_STACKS("zeroStacks"),
    TIER_OFF("tierOff"),
    VARIANT_OFF("variantOff"),
    RELIC_INVALID("relicInvalid"),
    NO_DAMAGE("noDamage"),
    NEUTRAL("neutral"),
    ;

    /** 短标签（「计入」「同键不叠加」「条件未确认」…）。 */
    val label: String get() = RankerText.t("states.$key")

    companion object {
        fun fromKey(key: String): EntryState? = entries.firstOrNull { it.key == key }
    }
}

/** 汇总的四栏（小计按这四栏算；「其它增益」含当前武器固有），与 Windows 端 COLUMN_ORDER 同序。 */
enum class SummaryColumn(val key: String) {
    WEAPON_AFFIX("weaponAffix"),
    RELIC("relic"),
    ACCESSORY("accessory"),
    OTHER("other"),
    ;

    val titleZh: String get() = RankerText.t("columns.$key")

    /** 占槽位的三栏：放进来 ≠ 条件成立，要勾「条件成立」。 */
    val isSlotted: Boolean get() = this != OTHER
}

/**
 * 评估口径（Windows makeEnv 的开关）。
 * - [strict]：推荐口径——条件型、发动型、要确认的、叠层与累积阶梯一律不计入（不看用户的确认）；
 * - [assumeAll]：「条件全部成立」口径——要确认的都当成立，叠层取一局实际上限（没有就 1 层），累积阶梯取最高层；
 * - [ownTier] / [ownVariant]：累积阶梯与多档词条按这一条自己的层／档算（一览用）。
 */
data class EvalOptions(
    val strict: Boolean = false,
    val assumeAll: Boolean = false,
    val ownTier: Boolean = false,
    val ownVariant: Boolean = false,
) {
    companion object {
        val STANDARD = EvalOptions()
        val STRICT = EvalOptions(strict = true)

        /** 「全部增益一览」的口径。 */
        val OVERVIEW = EvalOptions(assumeAll = true, ownTier = true, ownVariant = true)
    }
}

/**
 * 这一条是从哪里来的（配置引擎展开来源时填）。
 * [autoConfirm]：不占槽位的「其它增益」栏里用户亲手勾选的——勾选即确认；[auto]：当前武器固有，自动列入。
 */
data class EvalSource(
    val column: SummaryColumn = SummaryColumn.OTHER,
    val copies: Int = 1,
    val autoConfirm: Boolean = false,
    val auto: Boolean = false,
    val labels: List<String> = emptyList(),
    val keys: List<String> = emptyList(),
)

/**
 * 用户在配置里做的选择（由 LoadoutConfig 实现）：叠层层数、累积阶梯选中的那一层、多档词条选中的那一档、
 * 勾了「条件成立」的条目。[NONE] 表示一样都没选（一览与测试用）。
 */
interface EntrySelections {
    /** 用户填的层数（缺省 0：叠层要用户自己填，填层数即视为条件成立）。 */
    fun stacks(spEffectId: Int): Int = 0

    /** 累积阶梯（阶梯 id＝第 1 层的 spEffectId）选中的那一层的 spEffectId；没选为 null。 */
    fun ladderChoice(ladderId: Int): Int? = null

    /** 多档词条（组键 affixVariant.key）选中的那一档的 spEffectId；没选为 null（按第 1 档）。 */
    fun variantChoice(groupKey: String): Int? = null

    /** 用户勾了「条件成立」。 */
    fun isConfirmed(spEffectId: Int): Boolean = false

    companion object {
        val NONE: EntrySelections = object : EntrySelections {}
    }
}

/** 累积阶梯的层 / 多档词条的档：选中的那一条（null＝没选）、第几层／档、共几层／档。 */
data class TierPick(val id: Int?, val tier: Int, val tiers: Int)

/** 单条评估的结果（Windows evaluateEntry 返回的 item）。 */
data class EvaluatedEntry(
    val entry: BuffRankerEntry,
    val column: SummaryColumn,
    val labels: List<String>,
    val keys: List<String>,
    val copies: Int,
    /** 实际按几份计（stackSelf 且按 ID 互斥的各份相乘，其余只算一份）。 */
    val countedCopies: Int,
    val autoConfirm: Boolean,
    val auto: Boolean,
    val verdict: AppliesVerdict,
    /** 生效判定的短标签（[AppliesVerdict.label]）。 */
    val label: String,
    val activationNote: String?,
    /** 计入前还要用户确认的条件（发动条件在前）。 */
    val needs: List<String>,
    /** 用户已勾「条件成立」（或「其它增益」栏勾选即确认）。 */
    val ticked: Boolean,
    /** 叠层层数（已按参数表上限截断）；不是叠层条目为 null。 */
    val stacks: Int?,
    val stackWarnings: List<String>,
    /** 「条件全部成立」口径下叠层条目没有实际上限、也没填层数，只按 1 层算。 */
    val assumedOneStack: Boolean,
    val tier: TierPick?,
    val variant: TierPick?,
    val state: EntryState,
    val reasons: List<String>,
    val notes: List<String>,
    /** 这一条在九类伤害上的倍率（按 [DamageType.ordinal]）。不计入的也给出「单独看这一条」的值，列表展示用。 */
    val table: List<Double>,
    /** 攻击力加算（点数）。 */
    val flatTable: List<Double>,
    /** 按当前构成加权的有效倍率；没有构成时为 null（算不出）。 */
    val multiplier: Double?,
    /** 按占比加权的攻击力加算；没有构成时为 0。 */
    val flat: Double,
) {
    val id: Int get() = entry.id
    val isCounted: Boolean get() = state == EntryState.COUNTED
}

/** 「全部增益一览」的一行：条件全部成立时单独这一条的有效倍率（未去重、未连乘，只供查阅）。 */
data class OverviewRow(
    val item: EvaluatedEntry,
    /** 这一条对当前输出生效（不是「不生效」也不是「需勾选攻击情境」）。 */
    val applicable: Boolean,
    /** 生效时＝有效倍率；不生效时＝1（没有构成时为 null）。 */
    val multiplier: Double?,
) {
    val entry: BuffRankerEntry get() = item.entry
    val id: Int get() = item.entry.id
    val state: EntryState get() = item.state
    val reasons: List<String> get() = item.reasons

    /** 叠层条目没有实际上限，倍率只按 1 层算（行上要写明「按 1 层」）。 */
    val assumesOneStack: Boolean get() = applicable && item.assumedOneStack

    /** 对拍行与页面默认列表的口径：生效且有效倍率 > [USEFUL_EPSILON]。 */
    val isUseful: Boolean get() = applicable && (multiplier ?: 1.0) > USEFUL_EPSILON
}

/** 「攻击情境」勾选项（当前输出类别下 requires.attackContexts 里真正要求过的情境）。 */
data class AttackContextOption(val key: String, val zh: String, val count: Int)
