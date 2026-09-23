package com.nightreign.relicchecker.gamedata.bosses

// 页面展示用的纯逻辑：场合徽标、出处小节、行内状态徽标、底部场合说明与各处数值小字。
// 放在 :gamedata 里是为了能用 JVM 测试逐字断言；文案与 macOS 端 BossData*View.swift /
// Windows 端 pages/bosses.js 同源。

/** 一枚场合徽标：颜色跟所属分组走，默认隐藏的两种画灰；current = 场合是否落在当前分组。 */
data class BossRoleBadge(
    val role: String,
    val title: String,
    val group: BossGroup,
    val hidden: Boolean,
    val current: Boolean,
)

/**
 * 一组场合徽标（卡头 / 行内共用）。[current] 为 null 时全部着色；否则只有落在当前分组的场合着色，
 * 其余中性——一眼看出这张卡为什么出现在这个分组里。
 */
fun BossDataset.roleBadges(roles: List<String>, current: BossGroup? = null): List<BossRoleBadge> =
    roles.map { role ->
        BossRoleBadge(
            role = role,
            title = roleTitle(role),
            group = BossGroup.forRole(role),
            hidden = role in BossRoleCatalog.hiddenRoles,
            current = current?.contains(role) ?: true,
        )
    }

/** 出处小节里的一条出处。[npcId] 只在出处来自被合并掉的原始行时给出（页面写「行 N」）。 */
data class BossEvidenceItem(val npcId: Int?, val summary: String, val note: String, val hint: String)

/** 出处小节里的一个场合：第一条出处（或全部），另有几条。 */
data class BossEvidenceLine(
    val role: String,
    val title: String,
    val group: BossGroup,
    val hidden: Boolean,
    val total: Int,
    val items: List<BossEvidenceItem>,
) {
    /** 这个场合没有出处明细（页面写「出处：数据未内置」）。 */
    val missing: Boolean get() = total == 0

    /** 「另有 N 条出处」里的 N。 */
    val more: Int get() = total - items.size
}

/** 展开区每行「出场场合」小节：每个场合给第一条出处（showAll 时给全部）。没有 roles 的行返回空列表。 */
fun BossDataset.evidenceLines(row: BossFight, showAll: Boolean): List<BossEvidenceLine> =
    row.roles.map { role ->
        val list = row.evidence(role)
        val shown = if (showAll) list else list.take(1)
        BossEvidenceLine(
            role = role,
            title = roleTitle(role),
            group = BossGroup.forRole(role),
            hidden = role in BossRoleCatalog.hiddenRoles,
            total = list.size,
            items = shown.map { evidence ->
                BossEvidenceItem(
                    npcId = evidence.npcId?.takeIf { it != row.npcId },
                    summary = evidence.summary,
                    note = evidence.note,
                    hint = evidenceHint(evidence),
                )
            },
        )
    }

/** 行内状态徽标（顺序即渲染顺序，排在场合徽标之后）：主战 → 标签为社区推测 → 深夜数值 → 深夜专属修正 → 变异个体。 */
enum class BossRowBadge(val text: String) {
    MAIN("主战"),
    UNCERTAIN(BossRowText.labelUncertainBadge),
    DEPTH(BossRowText.deepRowBadge),
    EXCLUSIVE(BossRowText.deepExclusiveBadge),
    MUTATION("变异个体"),
}

/** 一条数值行在当前模式下的状态徽标；常规模式不挂深夜徽标，徽标里不写深度数字。 */
fun BossFight.statusBadges(mode: BossNightMode, mutationApplied: Boolean): List<BossRowBadge> = buildList {
    if (isMain) add(BossRowBadge.MAIN)
    if (labelUncertain) add(BossRowBadge.UNCERTAIN)
    if (mode.isDeepOfNight && hasDepthStats) add(BossRowBadge.DEPTH)
    if (mode.isDeepOfNight && hasDeepOfNight) add(BossRowBadge.EXCLUSIVE)
    if (mutationApplied) add(BossRowBadge.MUTATION)
}

/** 底部「出场场合说明」表的一行：场合 → 分组（默认隐藏的分组标注），卡片计数与判定口径。 */
data class BossRoleOverviewRow(
    val role: String,
    val title: String,
    val en: String,
    val group: BossGroup,
    val groupText: String,
    val countText: String,
    val description: String,
)

fun BossDataIndex.roleOverviewRows(): List<BossRoleOverviewRow> = dataset.orderedRoles.map { role ->
    val group = BossGroup.forRole(role)
    BossRoleOverviewRow(
        role = role,
        title = dataset.roleTitle(role),
        en = dataset.roleNames[role]?.en.orEmpty(),
        group = group,
        groupText = group.title + if (group.isHiddenByDefault) BossRoleText.hiddenGroupMark else "",
        countText = BossRoleText.roleCountText(bossCardCount(role), nightlordCardCount(role)),
        description = dataset.roleDescription(role),
    )
}

/** 各变异档位在多少条数值行的 mutationPool 里（工具条的「变异个体」选择器用）。 */
fun BossDataIndex.mutationRowCounts(): Map<Int, Int> {
    val counts = LinkedHashMap<Int, Int>()
    dataset.orderedMutations.forEach { counts[it.id] = 0 }
    dataset.allRows.forEach { row -> row.mutationPool.toSet().forEach { counts[it] = (counts[it] ?: 0) + 1 } }
    return counts
}

/** 页面上各处数值下面的小字（macOS 端 BossCardView / BossFightRowView 同文案）。 */
object BossCaptions {
    /** 卡片折叠态血量的标题：夜王写「主战血量」，主战行不止一条时补「· 最高」。 */
    fun hpMetricTitle(card: BossCard): String = when {
        !card.isNightlord -> "血量"
        card.hasMultipleMainRows -> "主战血量 · 最高"
        else -> "主战血量"
    }

    /** 卡片折叠态血量下的小字。变异个体另起一段（「变异 ×1.15」），1 人对照值不含变异。 */
    fun summaryHp(
        row: BossFight,
        players: BossPartySize,
        mode: BossNightMode,
        depthWord: String,
        mutation: BossMutation?,
    ): String {
        val depth = mode.depth
        val base = if (depth != null) {
            if (!row.hasDepthStats) return BossRowText.noDepthStatsText
            if (players == BossPartySize.SOLO) {
                "$depthWord $depth 数值"
            } else {
                "$depthWord $depth · 1 人 ${BossFormat.integer(row.hp(BossPartySize.SOLO, mode))}"
            }
        } else if (players == BossPartySize.SOLO) {
            "含常驻缩放"
        } else {
            "1 人 ${BossFormat.integer(row.hp)}"
        }
        return if (mutation == null) base else base + " · 变异 " + BossFormat.multiplier(mutation.hp, 3)
    }

    /** 卡片折叠态攻击力倍率下的小字。 */
    fun summaryAttack(mode: BossNightMode): String = if (mode.isDeepOfNight) "含深度倍率" else "常驻基准"

    /** 展开区逐行血量的小字：参数原值、总倍率，以及深度 / 变异这两层。 */
    fun rowHp(row: BossFight, stats: BossComputedStats, depthWord: String): String {
        if (stats.depthMissing) return BossRowText.noDepthStatsText
        var text = "参数原值 ${BossFormat.integer(row.hpBase)} · 总倍率 " + BossFormat.multiplier(stats.hpMultiplier, 4)
        stats.mode.depth?.let { text += " · $depthWord $it" }
        stats.mutation?.let { text += " · 变异 " + BossFormat.multiplier(it.hp, 3) }
        return text
    }

    /** 展开区逐行攻击力倍率的小字：基准 · 多人 · 变异。 */
    fun rowAttack(row: BossFight, stats: BossComputedStats): String {
        val parts = mutableListOf("基准 " + BossFormat.multiplier(row.baseline(stats.mode).attackRateBase, 3))
        if (stats.tier.raisesAttack) parts += "多人 " + BossFormat.multiplier(stats.tier.attackRate, 3)
        stats.mutation?.let { parts += "变异 " + BossFormat.multiplier(it.attackRate, 3) }
        return parts.joinToString(" · ")
    }

    /** 展开区逐行有效韧性的小字（四支，见 BossRowText.poiseCaption）。 */
    fun rowPoise(row: BossFight, stats: BossComputedStats): String = BossRowText.poiseCaption(
        poise = row.poise,
        poiseTakenTotal = stats.poiseTakenTotal,
        kind = stats.poiseKind,
        hasEffectivePoise = stats.effectivePoise != null,
    )

    /** 「深夜各深度」小表的说明：按什么条件换算出来的。 */
    fun depthTable(players: BossPartySize, mutation: BossMutation?): String {
        val parts = mutableListOf("按 ${players.title}换算")
        mutation?.let { parts += "含变异 #${it.id}" }
        parts += "已含常驻缩放、深夜修正与深度倍率"
        return parts.joinToString(" · ")
    }

    /** 深夜提示随模式反向：常规模式告诉用户「可以切」，深度模式给出常规值作对照。 */
    fun deepNote(row: BossFight, mode: BossNightMode, depthWord: String): String {
        if (!row.hasDepthStats) return BossRowText.noDepthStatsText
        if (!mode.isDeepOfNight) {
            val deepest = row.depthRows(BossPartySize.SOLO).last()
            return "该行有深夜数值：$depthWord ${deepest.depth} 血量 ${BossFormat.integer(deepest.hp)}（1 人）、" +
                "攻击 ${BossFormat.multiplier(deepest.attackRate, 3)}，可用顶部的模式选择切换。"
        }
        return "当前为深夜数值；常规数值：血量 ${BossFormat.integer(row.hp)}（1 人）、" +
            "攻击 ${BossFormat.multiplier(row.attackRateBase, 3)}。"
    }

    /** chaosCorrectId 与 scalingId 不等（14 行）时的说明；相等或没有时为 null。 */
    fun chaosMismatch(row: BossFight): String? {
        val chaosId = row.chaosCorrectId ?: return null
        if (chaosId == row.scalingId) return null
        return "深度档位取 ChaosMatchingCorrectParam #$chaosId，与人数档位 " +
            (row.scalingId?.let { "#$it" } ?: "（无）") + " 不是同一行。"
    }

    /**
     * 折叠态「头条数值取自哪一行」：夜王有多条主战行、或同时属于多个分组的组，把候选行逐条列出；
     * 其余卡片展开区不止一行时写「代表行：…（共 N 组，展开看全部）」；都不需要时为 null。
     */
    fun primaryRowNote(
        card: BossCard,
        group: BossGroup,
        players: BossPartySize,
        mode: BossNightMode,
        shownRows: Int,
    ): Pair<String, Boolean>? {
        val primary = card.representativeRow(group) ?: return null
        val pool = card.rows(group)
        val ambiguous = if (card.isNightlord) card.hasMultipleMainRows else card.hasMultipleGroups
        if (ambiguous && pool.size > 1) {
            val list = pool.joinToString(" · ") { "${it.displayLabel} ${BossFormat.integer(it.hp(players, mode))}" }
            val lead = if (card.isNightlord) {
                "${pool.size} 条主战行，上方取血量最高的一条："
            } else {
                "该分组 ${pool.size} 条数值行，上方取血量最高的一条："
            }
            return (lead + list) to true
        }
        if (shownRows > 1) return "代表行：${primary.displayLabel}（共 $shownRows 组，展开看全部）" to false
        return null
    }
}
