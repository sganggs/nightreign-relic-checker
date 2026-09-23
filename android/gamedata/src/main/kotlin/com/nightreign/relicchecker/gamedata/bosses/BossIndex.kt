package com.nightreign.relicchecker.gamedata.bosses

import com.nightreign.relicchecker.gamedata.GameDataFormatException
import com.nightreign.relicchecker.rules.foldedForSearch

// 页面用的统一卡片模型与索引（macOS 端 BossCard / BossDataIndex）。

/** 名字缺失 / 非游戏内文本时的灰色徽标（与 Windows 端 nameBadges 同序同文案）。 */
enum class BossNameBadge(val text: String) {
    /** nameSource = english-only：游戏文本里只有英文名。 */
    ENGLISH_ONLY("仅英文名"),
    /** nameSource = chrid-fallback，或 nameZh 为空的其余来源。 */
    NO_GAME_NAME("无游戏内名称"),
    /** nameSource = manual（schemaVersion 3 起不再产出，仍是合法取值）。 */
    MANUAL("名称手工补录"),
    /** nameInferred：名字是按 ID 结构推断的。 */
    INFERRED("名称按 ID 推断"),
    /** nameSource = community / community-npcname 且没有游戏文本依据。 */
    COMMUNITY("社区资料"),
    /** nameApprox：游戏文本不是逐字命中。 */
    APPROX(BossRowText.nameApproxBadge),
    /** 主标题取自 nameZhFallback（参考译名，不是本作文本）。 */
    FALLBACK(BossRowText.nameFallbackBadge),
}

/** 一张卡片里有多少行带某类深夜数值（扫描整卡，不只看代表行）。 */
enum class BossDeepCoverage {
    NONE,
    SOME,
    ALL,
    ;

    /** 深度模式下挂在卡头的「深夜数值」徽标（depthStats 口径）；none 不挂。 */
    val badgeText: String?
        get() = when (this) {
            NONE -> null
            SOME -> "部分行有深夜数值"
            ALL -> BossRowText.deepRowBadge
        }

    /** 深度模式下挂在卡头的「深夜专属修正」徽标（deepOfNight 口径）；none 不挂。 */
    val exclusiveBadgeText: String?
        get() = when (this) {
            NONE -> null
            SOME -> "部分行有" + BossRowText.deepExclusiveBadge
            ALL -> BossRowText.deepExclusiveBadge
        }
}

enum class BossCardKind { NIGHTLORD, BOSS }

class BossCard(
    val id: String,
    val kind: BossCardKind,
    /** 主分组：卡片所属分组里排在最前的那个。 */
    val group: BossGroup,
    /** 该卡片应出现在哪些分组里（按 BossGroup.entries 顺序）。 */
    val groups: List<BossGroup>,
    /** 出场场合（规范顺序），卡头逐个挂徽标。 */
    roles: List<String>,
    roleSearchTerms: List<String>,
    /** 威胁档位（守夜 / 野外首领的 tiers；缺失时退回 tier），只作展开区小字。 */
    val tiers: List<String>,
    val nameZh: String,
    val nameEn: String,
    val expeditionZh: String,
    val expeditionEn: String,
    val variantNameZh: String,
    val variantNameEn: String,
    val variantKey: String,
    val isEverdark: Boolean,
    val weakness: List<BossWeakness>,
    val descriptionZh: String,
    val nameSource: String,
    val nameInferred: Boolean,
    val nameApprox: Boolean,
    val nameNote: String,
    val nameSourceUrl: String,
    val nameZhFallback: String,
    val nameZhFallbackNote: String,
    val displayFallbackZh: String,
    val nameEvidence: BossNameEvidence?,
    val nameZhRejected: BossNameEvidence?,
    val hidden: Boolean,
    val noReward: Boolean,
    /** 夜王的 NightBossMenuParam 行号（守夜 / 野外为 null）。 */
    val menuId: Int?,
    val chrIds: List<Int>,
    val npcNameId: Int?,
    /** 夜王的 fights / 守夜 · 野外的 variants。 */
    val rows: List<BossFight>,
    /** 夜王各深度出现权重（守夜 / 野外为 null）。 */
    val depthChanceWeights: List<Pair<Int, Int>>?,
) {
    val roles: List<String> = BossRoleCatalog.normalized(roles)

    /**
     * 折叠后的搜索串：中英文名 + 参考译名 + 占位名 + 远征名 + 变体名 + 官方弱点 + 每行标签 +
     * 出场场合名（roleNames 的中英文）。nameSource / threat / variantKey 与场合取值 key 不进。
     *
     * 各段之间用换行隔开，避免跨段拼出不存在的词。**这里有意与 macOS 不同**：macOS
     * `BossCard.init` 用空格拼接，而 `foldedForSearch` 会删掉空格，结果各段首尾直接相连，
     * 「格拉狄乌斯」+「Gladius」能被「斯glad」这种跨两段的查询命中；换行不会被折叠掉，
     * 跨段查询在这里一律不命中。Windows `bosses.js` 的 `joinSearch` 用的也是换行，
     * 所以手机与 Windows 同口径、与 macOS 只差在跨段查询上（单段内的命中两端完全一致）。
     * 断言见 BossDatasetTest「搜索串分段用换行」；macOS 若要跟进，把 `joined(separator: " ")` 改成 "\n" 即可。
     */
    val searchKey: String = buildList {
        addAll(listOf(nameZh, nameEn, nameZhFallback, displayFallbackZh, expeditionZh, expeditionEn, variantNameZh, variantNameEn))
        addAll(weakness.map { it.display })
        addAll(rows.map { it.displayLabel })
        addAll(rows.map { it.labelEn })
        addAll(roleSearchTerms)
    }.filter { it.isNotEmpty() }.joinToString("\n").foldedForSearch() // 折叠不动换行，整串折一次即可

    /** 可按行号搜索的数字：全部 npcIds（含被合并掉的行）+ chrIds + npcNameId。 */
    val numberKeys: List<String> = LinkedHashSet<String>().apply {
        rows.flatMap { it.npcIds.ifEmpty { listOf(it.npcId) } }.forEach { add(it.toString()) }
        chrIds.forEach { add(it.toString()) }
        npcNameId?.let { add(it.toString()) }
    }.toList()

    val isNightlord: Boolean get() = kind == BossCardKind.NIGHTLORD

    /**
     * 主标题的四级回退：nameZh → nameZhFallback（参考译名）→ displayFallbackZh（占位名）→ nameEn；
     * 四项都空才自己拼「未知敌人 cXXXX」。
     */
    val displayName: String
        get() = when {
            nameZh.isNotEmpty() -> nameZh
            nameZhFallback.isNotEmpty() -> nameZhFallback
            displayFallbackZh.isNotEmpty() -> displayFallbackZh
            nameEn.isNotEmpty() -> nameEn
            chrIds.isNotEmpty() -> "未知敌人 c${chrIds.first()}"
            else -> "未知敌人"
        }

    /** 主标题用的是 nameZhFallback（第 2 级），徽标里必须有「参考译名 · 非本作游戏文本」。 */
    val usesNameFallback: Boolean get() = nameZh.isEmpty() && nameZhFallback.isNotEmpty()

    /** 主标题用的是 displayFallbackZh（第 3 级）。 */
    val usesDisplayFallback: Boolean
        get() = nameZh.isEmpty() && nameZhFallback.isEmpty() && displayFallbackZh.isNotEmpty()

    /** 副标题：主标题不是英文名时把英文名显示出来。 */
    val subtitleName: String? get() = nameEn.takeIf { it.isNotEmpty() && it != displayName }

    /**
     * 名字徽标（夜王不挂）。两层判定：① 名字本身缺不缺；② 身份是谁认出来的（community 且没有
     * 游戏文本依据时追加「社区资料」）；再追加「近似匹配」「参考译名」。
     */
    val nameBadges: List<BossNameBadge>
        get() {
            if (kind != BossCardKind.BOSS) return emptyList()
            val badges = mutableListOf<BossNameBadge>()
            when {
                nameSource == "chrid-fallback" -> badges += BossNameBadge.NO_GAME_NAME
                nameZh.isEmpty() ->
                    badges += if (nameSource == "english-only") BossNameBadge.ENGLISH_ONLY else BossNameBadge.NO_GAME_NAME
                nameSource == "manual" -> badges += BossNameBadge.MANUAL
                nameInferred -> badges += BossNameBadge.INFERRED
            }
            if (nameSource.startsWith("community") && nameEvidence == null) badges += BossNameBadge.COMMUNITY
            if (nameApprox) badges += BossNameBadge.APPROX
            if (usesNameFallback) badges += BossNameBadge.FALLBACK
            return badges
        }

    val nameBadge: BossNameBadge? get() = nameBadges.firstOrNull()

    val showsApproxBadge: Boolean get() = kind == BossCardKind.BOSS && nameApprox

    /** 展开区「名字来历 + 组级不掉奖励」小字块显不显示（noReward 也要进条件）。 */
    val showsNameNotes: Boolean
        get() = kind == BossCardKind.BOSS && (
            nameNote.isNotEmpty() || nameZhFallbackNote.isNotEmpty() || nameEvidence != null ||
                nameZhRejected != null || nameSourceUrl.isNotEmpty() || noReward
            )

    /** 整张卡片有没有「深夜数值」（hasDepthStats 口径，扫描全部行）。 */
    val deepCoverage: BossDeepCoverage get() = coverage { it.hasDepthStats }

    /** 整张卡片有没有「深夜专属常驻修正」（deepOfNight 口径）。 */
    val deepOfNightCoverage: BossDeepCoverage get() = coverage { it.hasDeepOfNight }

    private inline fun coverage(flag: (BossFight) -> Boolean): BossDeepCoverage {
        if (rows.isEmpty()) return BossDeepCoverage.NONE
        val hit = rows.count(flag)
        if (hit == 0) return BossDeepCoverage.NONE
        return if (hit == rows.size) BossDeepCoverage.ALL else BossDeepCoverage.SOME
    }

    /** 全部主战行（isMain 不唯一）。 */
    val mainRows: List<BossFight> get() = rows.filter { it.isMain }

    /**
     * 某个分组下参与「代表行」评选的候选行：分组场合 roles → isMain → 排掉演出行 → 排掉无奖励行，
     * 任何一步会把候选池清空就跳过那一步。
     */
    fun rows(group: BossGroup?): List<BossFight> = candidateRows(rows, group)

    /** 折叠态头条用的行：候选行里 1 人基准血量最高的一条（同血量取 npcId 较小者）。 */
    fun representativeRow(group: BossGroup?): BossFight? = representativeRow(rows, group)

    /** 卡片自身主分组下的代表行。 */
    val primaryRow: BossFight? get() = representativeRow(group)

    val hasMultipleMainRows: Boolean get() = mainRows.size > 1

    fun belongs(group: BossGroup): Boolean = group in groups

    val hasRoles: Boolean get() = roles.isNotEmpty()

    /** 默认不显示：hidden（非首领实体），或者全部场合都是「未放置」「随从/召唤物」。 */
    val isHiddenByDefault: Boolean
        get() = hidden || (hasRoles && roles.all { it in BossRoleCatalog.hiddenRoles })

    /** 同时属于多个默认可见分组。 */
    val hasMultipleGroups: Boolean get() = groups.count { !it.isHiddenByDefault } > 1

    /** 展开区要逐行列出的行：默认藏掉只出现在「未放置」「随从/召唤物」的行；整卡都是这种行时全部列出。 */
    fun displayRows(includeHidden: Boolean): List<BossFight> = displayRows(rows, includeHidden)

    fun hiddenRowCount(includeHidden: Boolean): Int = rows.size - displayRows(includeHidden).size

    /** 每个场合涉及这张卡的几条数值行（含默认收起的行；卡片级「出场场合」一览用）。 */
    fun roleRowCounts(): List<Pair<String, Int>> = roles.map { role -> role to rows.count { role in it.roles } }

    fun matches(foldedQuery: String): Boolean {
        if (foldedQuery.isEmpty()) return true
        // 纯数字按行号前缀匹配：npcId / chrId 是 4～9 位数，contains 会让「1」「50」命中全表。
        if (foldedQuery.all { it in '0'..'9' }) return numberKeys.any { it.startsWith(foldedQuery) }
        return searchKey.contains(foldedQuery)
    }

    /** 代表行里承伤倍率 > 1 的属性（降序，最多 limit 个）。 */
    fun hotRates(row: BossFight?, limit: Int = 3): List<Pair<BossDamageKind, Double>> =
        row?.damageRates?.weakKinds?.take(limit)?.map { it to row.damageRates.value(it) }.orEmpty()

    /** 当前分组对应这张卡的几条数值行（卡里不止一行时，展开区描边高亮这几行）。 */
    fun rowsInGroup(group: BossGroup?): Int = if (group == null) 0 else rows.count { it.belongs(group) }

    override fun toString(): String = "BossCard($id)"

    companion object {
        /**
         * 代表行候选（两端唯一正式规则，macOS 的 BossCard.rows(in:)）：
         * ① 按当前分组过滤 roles（group 为 null 时不过滤）→ ② isMain → ③ 排掉演出行 → ④ 排掉 noReward，
         * 任何一步会把候选池清空就跳过那一步。noReward 必须在 isMain 之后：夜王主战行几乎都是 noReward。
         */
        fun candidateRows(rows: List<BossFight>, group: BossGroup?): List<BossFight> {
            var pool = rows
            if (group != null) {
                val byRole = pool.filter { it.belongs(group) }
                if (byRole.isNotEmpty()) pool = byRole
            }
            val mains = pool.filter { it.isMain }
            if (mains.isNotEmpty()) pool = mains
            val playable = pool.filter { !it.isStagingRow }
            if (playable.isNotEmpty()) pool = playable
            val rewarding = pool.filter { !it.noReward }
            if (rewarding.isNotEmpty()) pool = rewarding
            return pool
        }

        /** 候选行里 1 人基准血量最高的一条（同血量取 npcId 较小者），与人数 / 模式无关。 */
        fun representativeRow(rows: List<BossFight>, group: BossGroup?): BossFight? =
            candidateRows(rows, group).sortedWith(compareByDescending<BossFight> { it.hp }.thenBy { it.npcId }).firstOrNull()

        /** 展开区列出的行：默认藏掉只出现在「未放置」「随从/召唤物」的行；全是这种行时全部列出。 */
        fun displayRows(rows: List<BossFight>, includeHidden: Boolean): List<BossFight> {
            if (includeHidden) return rows
            val shown = rows.filter { !it.isHiddenByDefault }
            return shown.ifEmpty { rows }
        }
    }
}

/** 一次筛选的结果：每个可见分组的卡片（已按搜索过滤）、计数与去重后的总数。 */
class BossFilterResult(
    val sections: List<Pair<BossGroup, List<BossCard>>>,
) {
    /** 各分组的卡片数（与 sections 的列表严格一致，搜索时同步更新）。 */
    val counts: Map<BossGroup, Int> = sections.associate { (group, cards) -> group to cards.size }

    /** 去重后的卡片（同一张卡可能出现在多个分组里）。 */
    val uniqueCards: List<BossCard> by lazy {
        val seen = LinkedHashMap<String, BossCard>()
        sections.forEach { (_, cards) -> cards.forEach { seen.putIfAbsent(it.id, it) } }
        seen.values.toList()
    }

    val isEmpty: Boolean get() = sections.all { it.second.isEmpty() }
}

/** 解码 + 分组 + 搜索索引，一次构建好交给页面。 */
class BossDataIndex(val dataset: BossDataset) {
    val cards: List<BossCard>

    init {
        val list = ArrayList<BossCard>(dataset.nightlords.size + dataset.nightBosses.size)
        dataset.nightlords.forEach { lord ->
            list += BossCard(
                id = "nightlord-${lord.menuId}",
                kind = BossCardKind.NIGHTLORD,
                group = BossGroup.NIGHTLORD,
                groups = listOf(BossGroup.NIGHTLORD),
                roles = lord.roles,
                roleSearchTerms = roleSearchTerms(lord.roles, dataset),
                tiers = emptyList(),
                nameZh = lord.nameZh,
                nameEn = lord.nameEn,
                expeditionZh = lord.expeditionZh,
                expeditionEn = lord.expeditionEn,
                variantNameZh = lord.variantNameZh,
                variantNameEn = lord.variantNameEn,
                variantKey = lord.variantKey,
                isEverdark = lord.isEverdark,
                weakness = lord.weakness,
                descriptionZh = lord.descriptionZh,
                nameSource = "",
                nameInferred = false,
                nameApprox = false,
                nameNote = "",
                nameSourceUrl = "",
                nameZhFallback = "",
                nameZhFallbackNote = "",
                displayFallbackZh = "",
                nameEvidence = null,
                nameZhRejected = null,
                hidden = false,
                noReward = false,
                menuId = lord.menuId,
                chrIds = emptyList(),
                npcNameId = null,
                rows = lord.fights,
                depthChanceWeights = if (lord.hasDepthChanceWeights) lord.orderedDepthChanceWeights else null,
            )
        }
        dataset.nightBosses.forEach { boss ->
            val groups = groups(boss.roles)
            list += BossCard(
                id = "boss-${boss.id}",
                kind = BossCardKind.BOSS,
                group = groups.firstOrNull() ?: BossGroup.OTHER,
                groups = groups,
                roles = boss.roles,
                roleSearchTerms = roleSearchTerms(boss.roles, dataset),
                tiers = boss.tiers.ifEmpty { if (boss.tier.isEmpty()) emptyList() else listOf(boss.tier) },
                nameZh = boss.nameZh,
                nameEn = boss.nameEn,
                expeditionZh = "",
                expeditionEn = "",
                variantNameZh = "",
                variantNameEn = "",
                variantKey = "",
                isEverdark = false,
                weakness = emptyList(),
                descriptionZh = "",
                nameSource = boss.nameSource,
                nameInferred = boss.nameInferred,
                nameApprox = boss.nameApprox,
                nameNote = boss.nameNote,
                nameSourceUrl = boss.nameSourceUrl,
                nameZhFallback = boss.nameZhFallback,
                nameZhFallbackNote = boss.nameZhFallbackNote,
                displayFallbackZh = boss.displayFallbackZh,
                nameEvidence = boss.nameEvidence,
                nameZhRejected = boss.nameZhRejected,
                hidden = boss.hidden,
                noReward = boss.noReward,
                menuId = null,
                chrIds = boss.chrIds,
                npcNameId = boss.npcNameId,
                rows = boss.variants,
                depthChanceWeights = null,
            )
        }
        // 一条首领记录都没有是读不懂的数据（确定性失败，外壳显示原因并缓存）
        if (list.isEmpty()) throw GameDataFormatException("首领数据里没有任何首领记录")
        cards = list
    }

    /** 按分组返回卡片；includeHidden = false 时两个默认隐藏的分组整组不显示，其余分组滤掉默认隐藏的卡。 */
    fun cards(group: BossGroup, includeHidden: Boolean = false): List<BossCard> {
        if (group.isHiddenByDefault && !includeHidden) return emptyList()
        return cards.filter { it.belongs(group) && (includeHidden || !it.isHiddenByDefault) }
    }

    /** 按分组返回过滤后的卡片；query 会自动折叠。 */
    fun cards(group: BossGroup, query: String, includeHidden: Boolean = false): List<BossCard> {
        val needle = query.foldedForSearch()
        return cards(group, includeHidden).filter { it.matches(needle) }
    }

    /**
     * 一次算齐页面要的筛选结果：[only] 为 null（「全部」）时是全部可见分组，否则只有那一个分组。
     * 计数与列表同源——搜索时各分组计数同步更新（桌面端的分组计数不随搜索更新，手机版在这里做对）。
     */
    fun filter(query: String, includeHidden: Boolean, only: BossGroup? = null): BossFilterResult {
        val needle = query.foldedForSearch()
        val groups = BossGroup.visibleCases(includeHidden).filter { only == null || it == only }
        return BossFilterResult(groups.map { group -> group to cards(group, includeHidden).filter { it.matches(needle) } })
    }

    /** 各分组（含未选中的）在当前搜索与开关下的卡片数：分组筛选器上的数字。 */
    fun groupCounts(query: String, includeHidden: Boolean): Map<BossGroup, Int> =
        filter(query, includeHidden).counts

    /** hidden = true 的组（召唤物 / 投射物等非首领实体）。 */
    val hiddenCards: List<BossCard> get() = cards.filter { it.hidden }

    /** 默认不显示的全部卡片。 */
    val hiddenByDefaultCards: List<BossCard> get() = cards.filter { it.isHiddenByDefault }

    /** 同时属于多个默认可见分组的组。 */
    val multiGroupCards: List<BossCard> get() = cards.filter { it.hasMultipleGroups }

    /** 某个场合在分组视图里的卡片数（含隐藏）：守夜 / 野外首领里 roles 含它的组。 */
    fun bossCardCount(role: String): Int = cards.count { !it.isNightlord && role in it.roles }

    /** 含某个场合的夜王卡片数。 */
    fun nightlordCardCount(role: String): Int = cards.count { it.isNightlord && role in it.roles }

    fun permanentEffects(ids: List<Int>): List<BossPermanentEffect> = ids.mapNotNull { dataset.permanentEffect(it) }

    /** 查不到明细的常驻缩放 SpEffect ID。 */
    fun missingPermanentEffectIds(ids: List<Int>): List<Int> = ids.filter { dataset.permanentEffect(it) == null }

    /** 底部「缩放档位说明」用：按档位 ID 升序。 */
    val scalingGroups: List<BossScalingGroup> get() = dataset.scalingTiers.values.sortedBy { it.id }

    val rowCount: Int get() = cards.sumOf { it.rows.size }

    /** 顶部胶囊：数据集收录了多少（含隐藏实体，不跟着开关变）。 */
    val summary: String
        get() {
            val lords = cards.count { it.isNightlord }
            val bosses = cards.size - lords
            val multi = multiGroupCards.size
            var text = "$lords 位夜王 · $bosses 组首领按出场场合分组"
            if (multi > 0) text += "（$multi 组属于多个场合）"
            return text
        }

    /** 「数据版本与来源」里的收录统计：每个分组（含默认隐藏的两个）的卡片数与数值行总数。 */
    val inventorySummary: String
        get() {
            val counts = BossGroup.entries.joinToString(" · ") { "${it.title} ${cards(it, includeHidden = true).size}" }
            val multi = multiGroupCards.size
            var text = counts
            if (multi > 0) text += "（含 $multi 组同时属于多个分组）"
            text += " · 数值行 $rowCount"
            return text
        }

    /** 隐藏实体的说明（底部「数据说明」用）。没有默认隐藏的组时为 null。 */
    val hiddenSummary: String?
        get() {
            val text = BossRoleText.hiddenSummary(
                flagged = hiddenCards.map { it.displayName },
                roleOnly = hiddenByDefaultCards.filter { !it.hidden }.map { it.displayName },
            )
            return text.ifEmpty { null }
        }

    companion object {
        /** 一组守夜 / 野外首领按 roles 归入哪些分组；nightlord 场合归「其它场合」；没有 roles 时归「其它场合」。 */
        fun groups(roles: List<String>): List<BossGroup> {
            if (roles.isEmpty()) return listOf(BossGroup.OTHER)
            val hit = roles.map { role ->
                val group = BossGroup.forRole(role)
                if (group == BossGroup.NIGHTLORD) BossGroup.OTHER else group
            }.toSet()
            return BossGroup.entries.filter { it in hit }
        }

        /** 搜索索引里的场合名：每个场合的中文名 + roleNames 的英文名。 */
        fun roleSearchTerms(roles: List<String>, dataset: BossDataset): List<String> =
            BossRoleCatalog.normalized(roles).flatMap { role ->
                val terms = mutableListOf(dataset.roleTitle(role))
                dataset.roleNames[role]?.en?.takeIf { it.isNotEmpty() }?.let { terms += it }
                terms
            }
    }
}
