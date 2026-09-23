package com.nightreign.relicchecker.gamedata.bosses

// 解码后的整份数据集（macOS 端 BossDataset / BossNightlord / BossNightBoss）。

class BossNightlord(
    val menuId: Int,
    val paramdexName: String,
    val nameZh: String,
    val nameEn: String,
    val expeditionZh: String,
    val expeditionEn: String,
    /** 只有 Paramdex 行名以 "[Everdark Sovereign]" 开头才是 true。 */
    val everdark: Boolean,
    /** "normal" | "everdark" | "standardBearers" | "unknown"。 */
    val variantKey: String,
    val variantNameZh: String,
    val variantNameEn: String,
    val sortId: Int,
    val weakness: List<BossWeakness>,
    val descriptionZh: String,
    val fights: List<BossFight>,
    /** 各深度的出现权重；权重 0 = 该深度不会出现。 */
    val depthChanceWeights: Map<Int, Int>,
    /** 出场场合（fights 的 roles 并集）。 */
    val roles: List<String>,
) {
    /** 深度 1…5 的权重（升序，缺的补 0）。 */
    val orderedDepthChanceWeights: List<Pair<Int, Int>>
        get() = (1..5).map { it to (depthChanceWeights[it] ?: 0) }

    val hasDepthChanceWeights: Boolean get() = depthChanceWeights.isNotEmpty()

    /** 永夜之王形态。 */
    val isEverdark: Boolean get() = variantKey == "everdark" || everdark
}

class BossNightBoss(
    /** "nameEn@chrIds[0]"，守夜 / 野外首领的主键（nameEn 不唯一）。 */
    val id: String,
    val nameEn: String,
    val nameZh: String,
    val nameSource: String,
    val nameInferred: Boolean,
    val npcNameId: Int?,
    val chrIds: List<Int>,
    /** "night" | "field"：只是「威胁档位」，不决定分组。 */
    val tier: String,
    val tiers: List<String>,
    val variants: List<BossFight>,
    val roles: List<String>,
    val nameApprox: Boolean,
    val nameEvidence: BossNameEvidence?,
    val nameNote: String,
    val nameSourceUrl: String,
    val nameZhFallback: String,
    val nameZhFallbackNote: String,
    val displayFallbackZh: String,
    val nameZhRejected: BossNameEvidence?,
    val hidden: Boolean,
    val noReward: Boolean,
)

class BossDataset(
    val schemaVersion: Int,
    val gameVersion: String,
    val dataVersion: String,
    val generatedAt: String,
    val sources: List<BossSource>,
    /** EFFECTIVE_AFFINITY 码 → (简中, 英文)。 */
    val affinityNames: Map<Int, Pair<String, String>>,
    val scalingTiers: Map<Int, BossScalingGroup>,
    val permanentScaling: Map<Int, BossPermanentEffect>,
    /** 数据集自带的取舍说明，页面底部原样展示。 */
    val caveats: List<String>,
    val nightlords: List<BossNightlord>,
    val nightBosses: List<BossNightBoss>,
    val notes: BossNotes?,
    val deepOfNightText: BossDeepOfNightText,
    val deepOfNightDepths: Map<Int, BossDepthInfo>,
    val deepOfNightTiers: Map<Int, BossDepthTier>,
    val mutations: Map<Int, BossMutation>,
    val mutationCategories: List<BossMutationCategory>,
    val roleNames: Map<String, BossRoleName>,
    val roleSummary: Map<String, Int>,
    val roleSummaryDetail: Map<String, BossRoleSummaryDetail>,
    val placementMaps: Map<String, BossPlacementMap>,
) {
    /** 全部数值行（夜王 fight + 守夜 / 野外 variant）。 */
    val allRows: List<BossFight> by lazy { nightlords.flatMap { it.fights } + nightBosses.flatMap { it.variants } }

    /** 场合的中文名：数据集 roleNames 的中文名 → 内置表 → roleNames 的英文名 → 键名原样。 */
    fun roleTitle(role: String): String {
        val name = roleNames[role]
        if (name != null && name.zh.isNotEmpty()) return name.zh
        BossRoleText.builtinRoleNames[role]?.let { return it }
        if (name != null && name.en.isNotEmpty()) return name.en
        return role
    }

    /** 场合的判定说明（roleNames.*.description）；缺失时为空串。 */
    fun roleDescription(role: String): String = roleNames[role]?.description.orEmpty()

    /**
     * 合并行的「逐行场合」：「逐行场合：夜王战 75000020 / 75002020；未放置 75001020」。
     * 各原始行场合都一样（或没有 rowRoles）时返回 null。
     */
    fun rowRolesSummary(row: BossFight): String? {
        if (!row.hasMixedRowRoles) return null
        val text = row.rowRoleGroups.joinToString("；") { (roles, ids) ->
            roles.joinToString(" + ") { roleTitle(it) } + " " + ids.joinToString(" / ")
        }
        return BossRoleText.rowRolesTitle + "：" + text
    }

    /** 页面要列出的全部场合：内置顺序在前，数据集里多出来的未知场合按键名排在后面。 */
    val orderedRoles: List<String>
        get() {
            val extra = (roleNames.keys + roleSummary.keys) - BossRoleCatalog.order.toSet()
            return BossRoleCatalog.order + extra.sorted()
        }

    fun permanentEffect(id: Int): BossPermanentEffect? = permanentScaling[id]

    /** 属性中文名：优先用数据集的 affinityNames，缺失时退回内置文案；物理四种恒用内置文案。 */
    fun title(kind: BossDamageKind): String {
        val code = kind.affinityCode ?: return kind.titleZh
        val name = affinityNames[code] ?: return kind.titleZh
        return name.first.ifEmpty { name.second }.ifEmpty { kind.titleZh }
    }

    fun title(kind: BossAilmentKind): String {
        val name = affinityNames[kind.affinityCode] ?: return kind.titleZh
        return name.first.ifEmpty { name.second }.ifEmpty { kind.titleZh }
    }

    fun scalingGroup(id: Int): BossScalingGroup? = scalingTiers[id]

    fun mutation(id: Int): BossMutation? = mutations[id]

    /** 某一行能选的变异档位（按 ID 升序），查不到明细的档位直接略过。 */
    fun mutations(row: BossFight): List<BossMutation> = row.mutationPool.sorted().mapNotNull { mutations[it] }

    /** 工具条选择的变异个体档位落到某一行上：「各行自带档位」取该行的第一档；指定档位只作用于池里有它的行。 */
    fun mutationFor(row: BossFight, choice: BossMutationChoice): BossMutation? = when (choice) {
        BossMutationChoice.None -> null
        BossMutationChoice.Own -> mutations(row).firstOrNull()
        is BossMutationChoice.Tier -> if (choice.id in row.mutationPool) mutations[choice.id] else null
    }

    fun depthTier(id: Int): BossDepthTier? = deepOfNightTiers[id]

    fun depthInfo(depth: Int): BossDepthInfo? = deepOfNightDepths[depth]

    val orderedDepthInfos: List<BossDepthInfo>
        get() = deepOfNightDepths.keys.sorted().mapNotNull { deepOfNightDepths[it] }

    /** 变异只数表：按 (categoryId, mapId) 稳定排序。 */
    val orderedMutationCategories: List<BossMutationCategory>
        get() = mutationCategories.sortedWith(compareBy<BossMutationCategory> { it.categoryId }.thenBy { it.mapId })

    /** 变异档位按 ID 升序（底部倍率表、工具条选择器用）。 */
    val orderedMutations: List<BossMutation> get() = mutations.keys.sorted().mapNotNull { mutations[it] }

    /** 模式选择器的标题：用 deepOfNightText 的游戏文本拼「深夜 · 深度 N」。 */
    fun title(mode: BossNightMode): String =
        BossNightMode.title(mode.depth, deepOfNightText.deepOfNightTitle, deepOfNightText.depthTitle)

    /** 「变异个体」的游戏文本词。 */
    val mutationTitle: String get() = deepOfNightText.mutationTitle

    /** 展开态「多人缩放明细」的档位说明。 */
    fun scalingCaption(row: BossFight): String =
        BossRowText.scalingCaption(row.scalingId, row.scalingId?.let { scalingGroup(it)?.title })

    /**
     * 这一行的多人缩放档位名与它是不是守夜首领对不上（Windows 端 threatRoleMismatch，45 行）：
     * 不当守夜首领的行挂着「守夜首领威胁档」，或守夜首领行挂着「野外首领威胁档」。
     * 默认收起的未放置 / 随从行不算。
     */
    fun threatRoleMismatch(row: BossFight): Boolean {
        if (!row.hasRoles || row.isHiddenByDefault) return false
        val id = row.scalingId ?: return false
        val group = scalingTiers[id]?.group
        val isNightRow = "night" in row.roles
        return when (group) {
            "Night Boss Threat" -> !isNightRow
            "Field Boss Threat" -> isNightRow
            else -> false
        }
    }

    /**
     * 出处的地图名（placementMaps 的 Paramdex 名或开放地块的地形名）与 MSB part：
     * 「m49_24_00_00：Night Boss - …… · c3100_9000（entityId 49240800）」（Windows 端 evidenceHint）。
     */
    fun evidenceHint(evidence: BossRoleEvidence): String {
        val msb = evidence.msb.orEmpty()
        val name = if (msb.isNotEmpty()) placementMaps[msb]?.name.orEmpty() else ""
        return listOf(if (name.isNotEmpty()) "$msb：$name" else "", evidence.part)
            .filter { it.isNotEmpty() }
            .joinToString(" · ")
    }
}

/** 工具条的「变异个体」选择：不计 / 按各行自带档位 / 指定某一档（只作用于池里有它的行）。 */
sealed interface BossMutationChoice {
    data object None : BossMutationChoice
    data object Own : BossMutationChoice
    data class Tier(val id: Int) : BossMutationChoice

    /** rememberSaveable 用的编码：none / own / 档位 ID。 */
    fun encode(): String = when (this) {
        None -> "none"
        Own -> "own"
        is Tier -> id.toString()
    }

    companion object {
        fun decode(text: String?): BossMutationChoice = when (text) {
            null, "", "none" -> None
            "own" -> Own
            else -> text.toIntOrNull()?.let(::Tier) ?: None
        }
    }
}
