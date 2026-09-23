package com.nightreign.relicchecker.gamedata.bosses

// 一条数值行（夜王 fight / 守夜·野外 variant）与它的换算。
//
// 数值口径（与 macOS 端 BossFight 逐项一致）：
//   * 1 人常规血量直接取 hp（已含常驻缩放），多人 × scaling.<duo|trio>.hp；
//   * 深夜 · 深度 N 取 depthStats[N]（hp / poiseTakenBase / attackRateBase 已含常驻 × 深夜修正 ×
//     深度倍率），再乘人数；削韧恢复倍率 / 异常发动基准 / 常驻 SpEffect 清单取 deepOfNight 那组，
//     没有就用常规值；请求了深度但该行没有 depthStats 时整组退回常规值并标 depthMissing；
//   * 变异个体（spCategory 203）在其它缩放之上再乘一层（按参数结构推断），只动血量 / 攻击 / 卢恩；
//   * 有效韧性 = poise /（poiseTakenBase × 人数档承受削韧），poise ≤ 0 或分母不是正的有限数时为 null；
//   * 血量最后一次取整（.5 远离 0）。

/** 一条战斗记录换算到指定人数 / 模式后的结果。 */
data class BossComputedStats(
    /** 玩家真正要打掉的血量。 */
    val hp: Int,
    /** 有效韧性；null 表示算不出（见 poiseKind）。 */
    val effectivePoise: Double?,
    val poiseKind: BossPoiseKind,
    /** 削韧恢复速度 = poiseRecover × poiseRecoverMultiplier × tier.poiseRecover。 */
    val poiseRecover: Double,
    /** 异常发动伤害倍率 = ailmentDamageRateBase × tier.ailmentDamageRate。 */
    val ailmentDamageRate: Double,
    /** Boss 承受的异常累积量倍率（只来自人数缩放）。 */
    val ailmentBuildupRate: Double,
    val poisonDamageRate: Double,
    val tier: BossScalingTier,
    val permScalingIds: List<Int>,
    val hpMultiplier: Double,
    val poiseTakenBase: Double,
    /** 敌人攻击力倍率 = 基准 × 人数档 × 变异档。 */
    val attackRate: Double,
    /** 卢恩倍率（只有变异个体会动它）。 */
    val runeRate: Double,
    val mode: BossNightMode,
    /** 选深度但该行没有 depthStats 时为 true，页面写「该行无深夜数值」。 */
    val depthMissing: Boolean,
    val mutation: BossMutation?,
) {
    /** 承受削韧总倍率 = poiseTakenBase × 人数档承受削韧（有效韧性小字用）。 */
    val poiseTakenTotal: Double get() = poiseTakenBase * tier.poiseTaken
}

class BossFight(
    val npcId: Int,
    val npcIds: List<Int>,
    val paramdexName: String?,
    val labelZh: String,
    val labelEn: String,
    /** 代表行的 Paramdex 名带 "?"，阶段 / 用途属社区推测。 */
    val labelUncertain: Boolean,
    /** 夜王：普通远征 / 至暗战实际使用的行（不唯一）。 */
    val isMain: Boolean,
    /** 守夜 / 野外：该行的威胁档位（只是缩放档位名，不决定分组）。 */
    val threat: String?,
    /** 1 人时玩家真正要打掉的血量（已含常驻缩放）。 */
    val hp: Int,
    val hpBase: Int,
    val hpMultiplier: Double,
    /** superArmorDurability；-1 表示不吃削韧。 */
    val poise: Double,
    val poiseRecover: Double,
    val poiseTakenBase: Double,
    val poiseRecoverMultiplier: Double,
    val damageRates: BossDamageRates,
    val ailmentDamageRateBase: Double,
    val resist: BossResistances,
    val immune: List<String>,
    val permScalingIds: List<Int>,
    val deepOfNight: BossDeepOfNightStats?,
    val scalingId: Int?,
    val scaling: BossScalingPair?,
    val attackRateBase: Double,
    /** ChaosMatchingCorrectParam 行号，可能与 scalingId 不等（14 行如此）。 */
    val chaosCorrectId: Int?,
    /** 深度 1…5 的数值；为空表示这一行没有深夜数值。 */
    val depthStats: Map<Int, BossDepthStats>,
    val mutationPool: List<Int>,
    /** 该行不掉任何奖励。 */
    val noReward: Boolean,
    /** 出场场合（规范顺序、无重复）；合并行是各原始行场合的并集。 */
    val roles: List<String>,
    /** 每个场合的出处（逐表逐行）。 */
    val roleEvidence: Map<String, List<BossRoleEvidence>>,
    /** 合并进本行的各原始 NpcParam 行各自的场合，键是 npcId。 */
    val rowRoles: Map<Int, List<String>>,
) {
    val id: Int get() = npcId

    // MARK: 出场场合

    val hasRoles: Boolean get() = roles.isNotEmpty()

    /** 只出现在默认隐藏的场合（「未放置」「随从/召唤物」）；没有场合数据的行不算。 */
    val isHiddenByDefault: Boolean
        get() = hasRoles && roles.all { it in BossRoleCatalog.hiddenRoles }

    fun belongs(group: BossGroup): Boolean = roles.any { group.contains(it) }

    fun evidence(role: String): List<BossRoleEvidence> = roleEvidence[role].orEmpty()

    /** 有没有哪个场合不止一条出处（此时给「展开全部出处」按钮）。 */
    val hasMoreEvidence: Boolean get() = roles.any { evidence(it).size > 1 }

    /**
     * 合并进本行的原始行按场合归拢：同一组场合的 npcId 放在一起，顺序按 npcIds 里第一次
     * 出现的顺序，rowRoles 里多出来的键按数值升序接在后面。
     */
    val rowRoleGroups: List<Pair<List<String>, List<Int>>> by lazy {
        val order = mutableListOf<List<String>>()
        val members = LinkedHashMap<List<String>, MutableList<Int>>()
        val ids = npcIds.filter { rowRoles.containsKey(it) } +
            rowRoles.keys.sorted().filter { it !in npcIds }
        for (id in ids) {
            val roles = rowRoles[id] ?: continue
            if (!members.containsKey(roles)) order += roles
            members.getOrPut(roles) { mutableListOf() } += id
        }
        order.map { it to members[it].orEmpty().toList() }
    }

    /** 合并行的各原始行场合不同（此时展开区要逐行写出来）。 */
    val hasMixedRowRoles: Boolean get() = rowRoleGroups.size > 1

    /** 显示用标签：labelZh 为空时依次回退 labelEn / paramdexName / 「行 npcId」。 */
    val displayLabel: String
        get() = when {
            labelZh.isNotEmpty() -> labelZh
            labelEn.isNotEmpty() -> labelEn
            !paramdexName.isNullOrEmpty() -> paramdexName
            else -> "行 $npcId"
        }

    val hasDeepOfNight: Boolean get() = deepOfNight != null
    val hasDepthStats: Boolean get() = depthStats.isNotEmpty()
    val canMutate: Boolean get() = mutationPool.isNotEmpty()

    /** 登场演出 / 血条实体 / 教程这类玩家打不到、或只是挂血条的行（只用于代表行评选）。 */
    val isStagingRow: Boolean
        get() {
            val label = displayLabel
            return STAGING_LABEL_KEYWORDS.any { label.contains(it) }
        }

    /** 深度 1…5 里实际有数值的那些（升序）。 */
    val availableDepths: List<Int> get() = depthStats.keys.sorted()

    /** 该行威胁档位的短标签（守夜 / 野外）。 */
    val threatTitle: String?
        get() {
            val value = threat
            if (value.isNullOrEmpty()) return null
            return when (value) {
                "night" -> "守夜"
                "field" -> "野外"
                else -> threat
            }
        }

    /** 展开区「威胁档位」小字；夜王的 fight 没有 threat，返回 null。 */
    val threatTierCaption: String?
        get() = threat?.takeIf { it.isNotEmpty() }?.let { BossRoleText.threatTierCaption(listOf(it)) }

    /** 免疫的异常：immune 列表优先，缺了按 resist 里的 999 回推。 */
    fun immuneKinds(): List<BossAilmentKind> {
        val declared = immune.toSet()
        val byFlag = BossAilmentKind.entries.filter { it.key in declared }
        return byFlag.ifEmpty { resist.immuneKinds }
    }

    // MARK: 换算

    /** 一次换算的基准数值（人数缩放与变异倍率都还没乘上去）。 */
    data class Baseline(
        val hp: Int,
        val hpMultiplier: Double,
        val poiseTakenBase: Double,
        val poiseRecoverMultiplier: Double,
        val ailmentDamageRateBase: Double,
        val attackRateBase: Double,
        val permScalingIds: List<Int>,
        /** 请求了某个深度，但这一行没有 depthStats —— 已退回常规数值。 */
        val depthMissing: Boolean,
    )

    fun baseline(mode: BossNightMode): Baseline {
        val depth = mode.depth
        if (depth != null) {
            val stats = depthStats[depth] ?: return baseline(BossNightMode.NORMAL).copy(depthMissing = true)
            return Baseline(
                hp = stats.hp,
                hpMultiplier = stats.hpMultiplier,
                poiseTakenBase = stats.poiseTakenBase,
                poiseRecoverMultiplier = deepOfNight?.poiseRecoverMultiplier ?: poiseRecoverMultiplier,
                ailmentDamageRateBase = deepOfNight?.ailmentDamageRateBase ?: ailmentDamageRateBase,
                attackRateBase = stats.attackRateBase,
                permScalingIds = deepOfNight?.permScalingIds ?: permScalingIds,
                depthMissing = false,
            )
        }
        return Baseline(
            hp = hp,
            hpMultiplier = hpMultiplier,
            poiseTakenBase = poiseTakenBase,
            poiseRecoverMultiplier = poiseRecoverMultiplier,
            ailmentDamageRateBase = ailmentDamageRateBase,
            attackRateBase = attackRateBase,
            permScalingIds = permScalingIds,
            depthMissing = false,
        )
    }

    fun tier(players: BossPartySize): BossScalingTier = scaling?.tier(players) ?: BossScalingTier.IDENTITY

    /** 血量 = depthStats[N].hp（或常规 hp）× 人数档血量倍率 × 变异血量倍率，最后一次取整。 */
    fun hp(
        players: BossPartySize,
        mode: BossNightMode = BossNightMode.NORMAL,
        mutation: BossMutation? = null,
    ): Int {
        val base = baseline(mode)
        val scaled = base.hp.toDouble() * tier(players).hp * (mutation?.hp ?: 1.0)
        if (!scaled.isFinite()) return base.hp
        return scaled.roundHalfAway()
    }

    /** 削韧槽语义：> 0 能算有效韧性，= 0 是「没有削韧槽」，< 0 是「不吃削韧」。 */
    val poiseKind: BossPoiseKind
        get() = when {
            poise < 0 || !poise.isFinite() -> BossPoiseKind.NONE
            poise == 0.0 -> BossPoiseKind.ZERO
            else -> BossPoiseKind.VALUE
        }

    /** 有效韧性 = poise /（poiseTakenBase × 人数档承受削韧）；变异不碰削韧，所以没有 mutation 参数。 */
    fun effectivePoise(players: BossPartySize, mode: BossNightMode = BossNightMode.NORMAL): Double? {
        if (poiseKind != BossPoiseKind.VALUE) return null
        val factor = baseline(mode).poiseTakenBase * tier(players).poiseTaken
        if (!(factor > 0) || !factor.isFinite()) return null
        return poise / factor
    }

    fun poiseRecoverSpeed(players: BossPartySize, mode: BossNightMode = BossNightMode.NORMAL): Double =
        poiseRecover * baseline(mode).poiseRecoverMultiplier * tier(players).poiseRecover

    fun ailmentDamageRate(players: BossPartySize, mode: BossNightMode = BossNightMode.NORMAL): Double =
        baseline(mode).ailmentDamageRateBase * tier(players).ailmentDamageRate

    fun ailmentBuildupRate(players: BossPartySize): Double = tier(players).buildupRate

    fun attackRate(
        players: BossPartySize,
        mode: BossNightMode = BossNightMode.NORMAL,
        mutation: BossMutation? = null,
    ): Double = baseline(mode).attackRateBase * tier(players).attackRate * (mutation?.attackRate ?: 1.0)

    /** 一次算齐所有换算结果。 */
    fun stats(
        players: BossPartySize,
        mode: BossNightMode = BossNightMode.NORMAL,
        mutation: BossMutation? = null,
    ): BossComputedStats {
        val base = baseline(mode)
        val tier = tier(players)
        val mutationAttack = mutation?.attackRate ?: 1.0
        return BossComputedStats(
            hp = hp(players, mode, mutation),
            effectivePoise = effectivePoise(players, mode),
            poiseKind = poiseKind,
            poiseRecover = poiseRecoverSpeed(players, mode),
            ailmentDamageRate = ailmentDamageRate(players, mode),
            ailmentBuildupRate = tier.buildupRate,
            poisonDamageRate = tier.poisonRate,
            tier = tier,
            permScalingIds = base.permScalingIds,
            hpMultiplier = base.hpMultiplier,
            poiseTakenBase = base.poiseTakenBase,
            attackRate = base.attackRateBase * tier.attackRate * mutationAttack,
            runeRate = mutation?.runeRate ?: 1.0,
            mode = mode,
            depthMissing = base.depthMissing,
            mutation = mutation,
        )
    }

    /** 展开区「深夜各深度」小表的一行。 */
    data class DepthRow(
        val depth: Int,
        val hp: Int,
        val attackRate: Double,
        /** 承受削韧倍率 = depthStats[N].poiseTakenBase × 人数档承受削韧。 */
        val poiseTaken: Double,
        val effectivePoise: Double?,
    )

    /** 深度 1…5 的小表，按当前人数（与已选变异档位）换算。没有 depthStats 时返回空列表。 */
    fun depthRows(players: BossPartySize, mutation: BossMutation? = null): List<DepthRow> =
        availableDepths.map { depth ->
            val mode = BossNightMode.depth(depth)
            val base = baseline(mode)
            DepthRow(
                depth = depth,
                hp = hp(players, mode, mutation),
                attackRate = attackRate(players, mode, mutation),
                poiseTaken = base.poiseTakenBase * tier(players).poiseTaken,
                effectivePoise = effectivePoise(players, mode),
            )
        }

    override fun toString(): String = "BossFight($npcId $displayLabel)"

    companion object {
        /** 「演出行」关键词：扫的是 displayLabel（页面上写着什么就按什么判）。 */
        val STAGING_LABEL_KEYWORDS: List<String> = listOf("登场演出", "血条实体", "教程")
    }
}
