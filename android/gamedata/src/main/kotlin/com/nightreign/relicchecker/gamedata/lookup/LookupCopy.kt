package com.nightreign.relicchecker.gamedata.lookup

// 词条反查页的文案表。凡是桌面端也有的句子，一律与 macOS（RelicCore/AffixLookup.swift、
// NightreignRelicChecker/AffixLookupView.swift / AffixLookupDetail.swift）逐字一致；
// 带参数的句子写成函数，JVM 测试对照桌面端测试里的原文断言。
// 页面（:app 的 ui/lookup/）只从这里取文案，不在 Composable 里另写一套说法。

/** 槽位池的中文短名；未知池回退为「池 <id>」。层号是孔数，不是槽序号（与 macOS affixPoolLabel 同表）。 */
fun affixPoolLabel(poolId: Int): String = when (poolId) {
    100 -> "旧池 · 1 孔层"
    200 -> "旧池 · 2 孔层"
    300 -> "旧池 · 3 孔层"
    110 -> "1.03 · 1 孔层"
    210 -> "1.03 · 2 孔层"
    310 -> "1.03 · 3 孔层"
    2_000_000 -> "深夜 A 池"
    2_100_000 -> "深夜 B 池"
    2_200_000 -> "深夜 C 池"
    3_000_000 -> "深夜诅咒池"
    else -> "池 $poolId"
}

/** 标签是不是「池 <id>」这种兜底写法；是的话旁边不再重复打一遍 id（与 Windows poolLabelIsFallback 同判断）。 */
fun affixPoolLabelIsFallback(poolId: Int): Boolean = affixPoolLabel(poolId) == "池 $poolId"

/** 槽位池的补充说明；没有则为空串（与 macOS affixPoolDetail 同表）。 */
fun affixPoolDetail(poolId: Int): String = when (poolId) {
    2_000_000 -> "强力正面词条：同一行必定配一条深夜诅咒"
    2_100_000, 2_200_000 -> "普通正面词条：同一行不带诅咒"
    3_000_000 -> "深夜遗物负面词条的唯一来源"
    else -> ""
}

/** 「共 N 件 / 已显示 M 件」（macOS affixLookupHitCountText，Windows hitCountText）。 */
fun affixLookupHitCountText(total: Int, shown: Int): String {
    val visible = maxOf(0, minOf(shown, total))
    if (visible >= total) return "共 $total 件 · 已显示全部 $total 件"
    return "共 $total 件 · 已显示 $visible 件（另有 ${total - visible} 件未列出）"
}

/**
 * 深夜遗物一栏的结论文案（macOS affixLookupDeepNote，Windows deepNoteText）。
 * 分支顺序固定：负面词条 → A 池（需诅咒）→ B/C 池 → 不在任何深夜池。
 */
fun affixLookupDeepNote(
    isCurse: Boolean,
    requiresCurse: Boolean,
    inAnyPool: Boolean,
    cursePoolId: Int,
    curseCount: Int,
): String = when {
    isCurse -> "负面词条：只出现在深夜遗物带诅咒的那一行，与同一行的 A 池正面词条配对；" +
        "诅咒池（$cursePoolId）共 $curseCount 条。"
    requiresCurse -> "A 池词条：出货时这一行必定同时带一条深夜诅咒（诅咒池 $cursePoolId，" +
        "共 $curseCount 条）。存档里这条词条没配诅咒即为改动。"
    inAnyPool -> "B / C 池词条：深夜遗物可出，所在行不带诅咒。"
    else -> "这条词条不在任何深夜词条池里，深夜遗物不会出它。"
}

/** 互斥池里只有它自己时的说明（macOS affixLookupLoneConflictNote）。 */
fun affixLookupLoneConflictNote(compatibilityId: Int): String =
    "互斥池 $compatibilityId 内只有这一条词条，没有互斥对象。"

object LookupCopy {
    // ---- 页面与列表 ----
    const val TITLE = "词条反查"
    const val EYEBROW = "AFFIX LOOKUP"
    const val TAB_AFFIX = "按词条查"
    const val TAB_RELIC = "按遗物查"
    const val AFFIX_SEARCH_PLACEHOLDER = "搜索词条名、别名、分类或 effectId"
    const val RELIC_SEARCH_PLACEHOLDER = "搜索遗物名、种类或 ID"
    const val INCLUDE_CURSES = "含负面词条"
    const val ONLY_DEEP = "只看深夜遗物"
    const val NO_AFFIX_MATCH = "没有匹配词条"
    const val NO_AFFIX_MATCH_DETAIL = "换个关键词或放宽范围试试"
    const val NO_RELIC_MATCH = "没有匹配遗物"
    const val NO_RELIC_MATCH_DETAIL = "换个关键词试试"
    const val INDEX_LOADING = "正在建立反查索引…"
    const val INDEX_LOADING_DETAIL = "首次进入本页时会把词条库与遗物物品表翻转成反向索引，只需一次。"
    /** 顶部状态小标签与「按遗物查」的说明卡标题（macOS AffixLookupView 两处同文）。 */
    const val RELIC_DATA_NOT_BUNDLED = "遗物物品表未内置"
    /** 词条详情里「能在哪出」位置的说明卡标题（macOS AffixLookupDetail）。 */
    const val RELIC_DATA_UNAVAILABLE = "遗物物品表不可用"
    const val ROW_CURSE = "负面"
    const val ROW_REQUIRES_CURSE = "需诅咒"
    const val ROW_EXTRA = "物品表"

    fun affixCount(count: Int) = "$count 条词条"
    fun relicCount(count: Int) = "$count 件遗物"
    fun catalogPill(count: Int) = "词条库 $count 条"
    fun obtainablePill(count: Int) = "可查遗物 $count 件"
    fun slotCountLabel(count: Int) = "$count 孔"

    /** 遗物物品表缺失 / 解析失败的原因；末尾带句号，方便与后半句拼接（macOS relicDataDetail）。 */
    fun relicDataDetail(error: String?): String {
        if (error == null) return "没有内置 relics.json。"
        val trimmed = error.trim()
        val body = if (trimmed.endsWith("。") || trimmed.endsWith(".")) trimmed.dropLast(1) else trimmed
        return "遗物物品表载入失败：$body。"
    }

    const val RELIC_TAB_UNAVAILABLE_SUFFIX = "无法按遗物反查；「按词条查」仍可看词条说明与互斥组。"
    const val AFFIX_DETAIL_UNAVAILABLE_SUFFIX =
        "本页只能给出词条说明与互斥组；「能在哪出」「按遗物查」需要遗物物品表。"

    // ---- 词条详情：基本信息 ----
    const val EXTRA_ONLY_PILL = "仅物品表收录"
    const val CURSE_PILL = "负面词条"
    const val REQUIRES_CURSE_PILL = "需配诅咒"
    const val EXTRA_ONLY_NOTE = "这条词条只出现在遗物物品表里，词条库没有收录说明与叠加性。"
    const val KEY_SORT_ID = "保存排序键 sortId"
    const val KEY_COMPATIBILITY_ID = "互斥组 compatibilityId"
    const val KEY_LIVE_POOLS = "所在槽位池"

    fun superposabilityPill(value: String) = "叠加性：$value"
    fun compatibilityValue(compatibilityId: Int) =
        if (compatibilityId == -1) "-1（不互斥）" else compatibilityId.toString()
    fun livePoolValue(count: Int) = if (count == 0) "无" else "$count 个"

    // ---- 词条详情：互斥组 ----
    /** 不可达词条的说明（macOS affixLookupUnreachableConflictNote）。 */
    const val UNREACHABLE_CONFLICT_NOTE =
        "这条词条不会出现在任何遗物的槽位池里，不参与互斥判定：互斥只约束「能同时出现在一件遗物上」的词条。"

    /** compatibilityId == -1 的说明（macOS affixLookupNoConflictGroupNote）。 */
    const val NO_CONFLICT_GROUP_NOTE = "该词条没有互斥组，可与任意其他词条同时出现（仍不能与自身重复）。"
    const val UNREACHABLE_CONFLICT_TITLE = "不参与互斥判定"
    const val CONFLICT_TITLE = "互斥组"

    fun conflictCardTitle(compatibilityId: Int) = "互斥组（compatibilityId $compatibilityId）"
    fun conflictCardSubtitle(groupSize: Int, extras: Int) =
        "同组词条不能出现在同一件遗物上，共 $groupSize 条" +
            if (extras > 0) "（其中 $extras 条只见于遗物物品表）" else ""
    fun conflictExpandButton(expanded: Boolean, total: Int, limit: Int) =
        if (expanded) "收起（只看前 $limit 条）" else "展开全部 $total 条"
    fun conflictExpandHint(expanded: Boolean, total: Int, limit: Int) =
        if (expanded) "已列出全部 $total 条互斥词条" else "还有 ${total - limit} 条未列出"

    // ---- 词条详情：深夜遗物 ----
    const val DEEP_TITLE = "深夜遗物"
    const val DEEP_SUBTITLE = "A / B / C 三池的归属，以及这一行要不要配诅咒"

    /** 池一行右侧的规模说明；没有遗物物品表时只知道池 id（macOS LookupPoolRow）。 */
    fun poolRowMeta(poolId: Int, memberCount: Int, relicCount: Int) =
        if (memberCount == 0) "池 $poolId" else "池 $poolId · $memberCount 条 · $relicCount 件遗物"

    // ---- 词条详情：能在哪出 ----
    const val WHERE_TITLE = "能在哪出"
    const val WHERE_NONE = "按当前数据，没有正常可获得的遗物能出这条词条"
    fun whereSubtitle(total: Int, fixed: Int, random: Int) =
        if (total == 0) WHERE_NONE else "共 $total 件遗物：固定 $fixed 件 · 随机池 $random 件"

    const val MODES_HEADING = "普通随机遗物的出货口径"
    const val MODE_UNAVAILABLE = "不可出"
    const val TIER_NOTE = "普通大遗物按孔数分层取池：1 孔取 1 孔层池，2 孔取 2 孔层 + 1 孔层，3 孔取 3 / 2 / 1 孔层。" +
        "三层是嵌套关系（大池包含小池），层号指的是孔数，不是槽位的先后顺序。"
    const val NOT_IN_NORMAL_POOLS_NOTE = "上面三行只讲普通随机遗物的槽位池。本条不在这些池里，" +
        "但下面列出的遗物仍能带上它（固定词条池，或深夜遗物的诅咒池）。"
    const val FIXED_HITS_TITLE = "固定带这条词条（槽位池只有这一条）"
    const val RANDOM_HITS_TITLE = "随机池里可能出（同池还有别的词条）"
    const val HIT_CURSE_SLOT = "诅咒槽"

    fun kindCountPill(kind: String, count: Int) = "$kind $count"
    fun hitCountPill(count: Int) = "$count 件"
    fun hitExpandButton(expanded: Boolean, total: Int, limit: Int) =
        if (expanded) "收起（只看前 $limit 件）" else "展开全部 $total 件"
    fun hitExpandHint(total: Int, shown: Int) =
        affixLookupHitCountText(total, shown) + "；上面的种类统计是全部命中的分布"
    fun hiddenRelicsNote(count: Int) = "另有 $count 条不会正常获得的物品表条目未列出：" +
        "超出合法 ID 区间 / 没有名称的参数行（调试、未启用条目），" +
        "以及 20000–30035 作弊器区段的遗物。"

    // ---- 遗物详情 ----
    const val FIXED_PILL = "词条固定"
    const val SLOTS_TITLE = "槽位池"
    const val SLOTS_SUBTITLE_DEEP = "深夜遗物的正面词条按池配对：A 池词条必定同时带一条深夜诅咒"
    const val SLOTS_SUBTITLE_NORMAL = "每个槽位从自己的池里抽一条正面词条"
    const val NO_SLOT = "无槽位"
    const val DEEP_SLOTS_NOTE = "深夜遗物只给池构成、不给槽位顺序：参数表里深夜遗物的行排列与游戏实际生成不符，" +
        "存档里的正面词条又是按保存顺序（sortId 升序）排的，两者没有对应关系。" +
        "某件深夜遗物是否合法，请以「存档检查」页的按行配对判定为准。"
    const val EMPTY_POOL_NOTE = "该池在数据集中没有成员（空池），这个槽位不会出词条。"
    const val FIXED_CARD_TITLE = "官方固定词条"
    const val FIXED_CARD_SUBTITLE = "每个槽位池都只有一条词条，因此这件遗物的词条完全确定（已按保存顺序排列）"
    const val FIXED_CARD_NOTE = "存档里这件遗物出现别的词条，就是被改动过；「存档检查」页会直接给出这份官方词条。"

    fun colorPill(colorLabel: String) = "${colorLabel}色"
    fun normalSlotTitle(slotIndex: Int) = "第 ${slotIndex + 1} 槽"
    fun deepGroupTitle(count: Int) = "本件 $count 条"
    fun poolIdLabel(poolId: Int) = "池 $poolId"
    fun slotSizePill(isFixed: Boolean, size: Int) = if (isFixed) "固定 1 条" else "随机 $size 条"
    fun curseSlotPill(curseSize: Int) = "配诅咒 · $curseSize 条"
    fun previewMore(more: Int) = "池内另有 $more 条词条，可在「按词条查」里逐条反查。"

    // ---- 数据来源 ----
    const val SOURCES_TITLE = "数据来源与口径说明"
    const val SOURCES_CAVEAT = "本页只回答「能不能出」，不回答「多大概率出」：槽位池的抽取权重不在数据集里。" +
        "词条名与池的归属来自游戏参数表与社区整理，不是官方公布的掉落表，也不是实测统计。"
    const val CATALOG_SOURCES = "词条库来源"
    const val RELIC_SOURCES = "遗物物品表来源"
}
