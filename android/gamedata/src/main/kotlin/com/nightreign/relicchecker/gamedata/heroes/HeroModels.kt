package com.nightreign.relicchecker.gamedata.heroes

// 「角色属性」页的不可变模型，逐项对应 macOS RelicCore/HeroData.swift 的同名类型。
// 由 HeroesParser 在后台线程从 DTO 转换而来；页面只读、按引用传递。

/** 数据集 `statNames.attributes[]` 的一项。中文名一律以数据集为准，不在代码里硬编码。 */
data class HeroStatName(val key: String, val zh: String, val en: String) {
    val display: String get() = zh.ifEmpty { en }
}

/** 数据集 `statNames.derived[]` 的一项：派生值 + 它依赖的属性与 CalcCorrectGraph 行号。 */
data class HeroDerivedName(
    val key: String,
    val zh: String,
    val en: String,
    val fromStat: String,
    val graphId: Int,
    /** 游戏内有对应 UI 标签（血量 / 专注值 / 精力有，负重上限没有 → 遗留列，列头带 *）。 */
    val inGameLabel: Boolean = true,
    /** 结果必为整数（血量 / 专注值 / 精力）；负重上限带指数，保留 1 位小数。 */
    val integer: Boolean = true,
) {
    val display: String get() = zh.ifEmpty { en }
}

/** 属性 / 派生值的中文名与展示顺序。 */
class HeroStatNames(
    val attributeOrder: List<String> = emptyList(),
    val derivedOrder: List<String> = emptyList(),
    val attributes: List<HeroStatName> = emptyList(),
    val derived: List<HeroDerivedName> = emptyList(),
) {
    /** 按 `attributeOrder` 排好的属性；顺序表缺失时退回数组自身顺序。 */
    val orderedAttributes: List<HeroStatName> = ordered(attributes, attributeOrder) { it.key }

    /** 按 `derivedOrder` 排好的派生值。 */
    val orderedDerived: List<HeroDerivedName> = ordered(derived, derivedOrder) { it.key }

    val attributeKeys: List<String> = orderedAttributes.map { it.key }
    val derivedKeys: List<String> = orderedDerived.map { it.key }

    private val attributeTitles: Map<String, String> =
        LinkedHashMap<String, String>().also { map -> orderedAttributes.forEach { map.putIfAbsent(it.key, it.display) } }
    private val derivedTitles: Map<String, String> =
        LinkedHashMap<String, String>().also { map -> orderedDerived.forEach { map.putIfAbsent(it.key, it.display) } }

    /** 属性中文名；数据集没有这一项时原样回显 key（页面不硬编码中文名）。 */
    fun attributeTitle(key: String): String = attributeTitles[key] ?: key

    fun derivedTitle(key: String): String = derivedTitles[key] ?: key

    fun derivedEntry(key: String): HeroDerivedName? = derived.firstOrNull { it.key == key }

    /** 派生值列头：遗留列（没有游戏内 UI 标签的那一项）带 * 注记（Windows derivedHeader 同口径）。 */
    fun derivedHeader(key: String): String {
        val entry = derivedEntry(key)
        val title = derivedTitle(key)
        return if (entry != null && !entry.inGameLabel) HeroStatsCopy.legacyHeader(title) else title
    }

    /** 表里有没有遗留列（有才写脚注）。 */
    val hasLegacyDerived: Boolean get() = derived.any { !it.inGameLabel }

    /** 遗留列的 key（当前只有负重上限；靠 inGameLabel 判定，不写死 key）。 */
    val legacyDerivedKeys: List<String> get() = derivedKeys.filter { derivedEntry(it)?.inGameLabel == false }

    val isEmpty: Boolean get() = attributes.isEmpty() && derived.isEmpty()

    private companion object {
        fun <T> ordered(items: List<T>, order: List<String>, key: (T) -> String): List<T> {
            if (order.isEmpty()) return items
            val byKey = LinkedHashMap<String, T>()
            items.forEach { byKey.putIfAbsent(key(it), it) }
            val result = ArrayList<T>()
            order.forEach { name -> byKey[name]?.let(result::add) }
            items.filterTo(result) { key(it) !in order }
            return result
        }
    }
}

/** 参数表里真实存在的一行（Level 1 / 2 / 12 / 15）。 */
data class HeroAnchorRow(
    val level: Int,
    val rowId: Int = 0,
    val rowName: String = "",
    val stats: Map<String, Int> = emptyMap(),
)

/** 一个等级的完整属性行。 */
data class HeroLevelRow(
    val level: Int,
    /** 参数表锚点（1 / 2 / 12 / 15），其余等级是插值推算。 */
    val isAnchor: Boolean,
    val stats: Map<String, Int>,
    val derived: Map<String, Double> = emptyMap(),
)

/** 一位渡夜者。 */
data class HeroEntry(
    val id: Int,
    val key: String,
    val nameZh: String,
    val nameEn: String,
    val heroStatusParamId: Int = 0,
    val anchors: List<HeroAnchorRow> = emptyList(),
    /** 已按 level 升序排好。 */
    val levels: List<HeroLevelRow> = emptyList(),
) {
    val display: String get() = nameZh.ifEmpty { nameEn }

    fun level(level: Int): HeroLevelRow? = levels.firstOrNull { it.level == level }

    val maxLevel: Int get() = levels.maxOfOrNull { it.level } ?: 0
    val anchorLevels: List<Int> get() = levels.filter { it.isAnchor }.map { it.level }
}

/** 携带某条转职词条的遗物。 */
data class HeroRelicItem(
    val id: Int,
    val nameZh: String,
    val nameEn: String = "",
    val color: Int = -1,
    val colorZh: String = "",
    val colorEn: String = "",
    val deep: Boolean = false,
) {
    val display: String get() = nameZh.ifEmpty { nameEn }

    /**
     * 颜色文案。数据集给的 `colorZh` 是「红 / 蓝 / 黄 / 绿」，而遗物卡 / 报告 / CSV 统一用
     * 「红色 / 蓝色 / …」，这里跟着走同一份口径（macOS HeroRelicItem.colorText）。
     */
    val colorText: String
        get() = when (color) {
            in 0..4 -> relicColorLabel(color) + "色"
            else -> colorZh.ifEmpty { colorEn.ifEmpty { "颜色未知" } }
        }

    companion object {
        /** 遗物颜色码 → 单字文案（macOS RelicAudit.relicColorLabel 同一张表）。 */
        fun relicColorLabel(color: Int): String = when (color) {
            0 -> "红"
            1 -> "蓝"
            2 -> "黄"
            3 -> "绿"
            4 -> "白"
            else -> "未知"
        }
    }
}

/** 转职词条某一级的增减量。 */
data class HeroModifierLevel(
    val level: Int,
    /** 参数表锚点（1 / 12）。 */
    val isAnchor: Boolean,
    /** 非锚点等级（2–11 插值、13–15 沿用 12 级）都是推算值。 */
    val inferred: Boolean,
    val delta: Map<String, Int>,
    /** 取整方向换成 floor 时结果不同的属性（只含不同的项）。 */
    val deltaFloorAlt: Map<String, Int> = emptyMap(),
)

/** 转职词条的参数锚点行（Level 1 / 12）。 */
data class HeroModifierAnchor(
    val level: Int,
    val rowId: Int = 0,
    val rowName: String = "",
    val delta: Map<String, Int> = emptyMap(),
)

/** 一条转职遗物词条（每个角色 2 条）。 */
data class HeroStatModifier(
    val affixId: Int,
    val nameZh: String,
    val nameEn: String = "",
    val heroId: Int = 0,
    val heroKey: String,
    val heroNameZh: String = "",
    val affectedStats: List<String> = emptyList(),
    val anchors: List<HeroModifierAnchor> = emptyList(),
    /** 已按 level 升序排好。 */
    val levels: List<HeroModifierLevel> = emptyList(),
    val relicItems: List<HeroRelicItem> = emptyList(),
    val rollablePoolIds: List<Int> = emptyList(),
    /** 只靠 DLC 权重才掉得出来的词条（全库 4 条）。 */
    val dlcOnly: Boolean = false,
) {
    val display: String get() = nameZh.ifEmpty { nameEn }

    fun level(level: Int): HeroModifierLevel? = levels.firstOrNull { it.level == level }

    /** 词条名去掉开头的「【角色】」，在角色卡片下展示时不必重复角色名。 */
    val shortName: String
        get() {
            if (!nameZh.startsWith("【")) return display
            val end = nameZh.indexOf('】')
            return if (end < 0) display else nameZh.substring(end + 1)
        }
}

/** 利普拉的交易（5 套整表替换，不分角色）。 */
data class HeroLibraRespec(
    val key: String,
    val nameZh: String = "",
    val nameEn: String = "",
    val effectNameZh: String = "",
    val effectInfoZh: String = "",
    /** 游戏里真正能看到的逐笔文案（对话选项），页面优先展示这一条。 */
    val dealLineZh: String = "",
    val statKey: String = "",
    val statNameZh: String = "",
    val heroStatusId: Int = 0,
    val anchors: List<HeroAnchorRow> = emptyList(),
    /** 已按 level 升序排好。 */
    val levels: List<HeroLevelRow> = emptyList(),
) {
    val display: String get() = dealLineZh.ifEmpty { nameZh.ifEmpty { nameEn } }

    /** 选择器里的短标签：用属性名（力气 / 灵巧 / 智力 / 信仰 / 感应）。 */
    val shortTitle: String get() = statNameZh.ifEmpty { nameZh.ifEmpty { key } }

    fun level(level: Int): HeroLevelRow? = levels.firstOrNull { it.level == level }
}

data class HeroSource(
    val name: String,
    val url: String = "",
    val revision: String = "",
    val license: String = "",
    val usage: String = "",
)

data class HeroCrossCheckMismatch(val level: Int, val field: String, val external: Int, val ours: Int)

/** 与外部 wiki 的逐格对照结果。 */
data class HeroCrossCheck(
    val heroKey: String,
    val heroNameZh: String = "",
    val cellsCompared: Int = 0,
    val mismatchCount: Int = 0,
    val mismatches: List<HeroCrossCheckMismatch> = emptyList(),
    /** 差异以哪一边为准（当前数据集一律是 "params"）。 */
    val authoritative: String = "",
    val note: String = "",
)

/** 底部折叠区要逐条展示的一段说明。 */
data class HeroNote(val title: String, val text: String)

/** 插值 / 验证口径。 */
data class HeroInterpolation(
    val baseAnchorLevels: List<Int> = emptyList(),
    val modifierAnchorLevels: List<Int> = emptyList(),
    /** 缺这一项时留 0，由 HeroStatsIndex.maxLevel 退回「各角色 levels 里的最大等级」。 */
    val maxLevel: Int = 0,
    val baseRule: String = "",
    val baseRounding: String = "",
    val baseVerified: Boolean = false,
    val baseVerification: String = "",
    val derivedRule: String = "",
    val modifierRule: String = "",
    val modifierRounding: String = "",
    /** 兼容字段：等于 modifierMidLevelsVerified 的保守合取，页面读下面两个细分字段。 */
    val modifierVerified: Boolean = false,
    val modifierVerifiedNote: String = "",
    /** L1 / L12 锚点 + 「13–15 沿用 L12」已由实测确认。 */
    val modifierAnchorVerified: Boolean = false,
    val modifierAnchorVerification: String = "",
    /** 2–11 级的逐级数值与取整方向仍未实测。 */
    val modifierMidLevelsVerified: Boolean = false,
    val modifierInference: String = "",
    val libraRule: String = "",
) {
    /**
     * 底部「插值与验证口径」折叠区逐条展示（正文为空的条目跳过）。
     * 与 macOS HeroInterpolation.notes、Windows interpolationNotes(data) 同序同文，
     * 标题里的「N 条」因此三端相同。
     */
    val notes: List<HeroNote> by lazy {
        val titles = HeroStatsCopy.interpolationNoteTitles
        listOf(
            titles[0] to if (baseAnchorLevels.isEmpty()) "" else
                HeroStatsCopy.interpolationAnchorNote(baseAnchorLevels, modifierAnchorLevels),
            titles[1] to baseRule,
            titles[2] to baseVerification,
            titles[3] to derivedRule,
            titles[4] to modifierRule,
            titles[5] to modifierAnchorVerification,
            titles[6] to modifierInference,
            titles[7] to HeroStatsCopy.interpolationRoundingNote(baseRounding, modifierRounding),
            titles[8] to modifierVerifiedNote,
            titles[9] to libraRule,
        ).filter { it.second.isNotEmpty() }.map { HeroNote(it.first, it.second) }
    }

    companion object {
        /** 整段 interpolation 缺失时的兜底（全部字段留空，页面据此不显示任何说明）。 */
        val EMPTY = HeroInterpolation()
    }
}

/** 整份角色属性数据集（解析后的不可变模型）。 */
data class HeroDataset(
    val schemaVersion: Int = 0,
    val datasetId: String = "",
    val gameVersion: String = "",
    val dataVersion: String = "",
    val generatedAt: String = "",
    val statNames: HeroStatNames = HeroStatNames(),
    /** CalcCorrectGraph 行号 → 行。 */
    val growthGraphs: Map<Int, HeroGrowthGraph> = emptyMap(),
    /** 数据集是否声明了 growthGraphs（缺整块时 Windows 判「数据未内置」，页面同样降级）。 */
    val growthGraphsDeclared: Boolean = growthGraphs.isNotEmpty(),
    val interpolation: HeroInterpolation = HeroInterpolation.EMPTY,
    val caveats: List<String> = emptyList(),
    val counts: Map<String, Int> = emptyMap(),
    val heroes: List<HeroEntry> = emptyList(),
    val statModifiers: List<HeroStatModifier> = emptyList(),
    val libraRespecs: List<HeroLibraRespec> = emptyList(),
    val crossChecks: List<HeroCrossCheck> = emptyList(),
    val sources: List<HeroSource> = emptyList(),
) {
    /**
     * 数据版本块的 5 行「标签 → 值」：标签与取值口径与 macOS / Windows 逐字一致
     * （HeroStatsCopy.versionLabels / contentSummary）。缺字段给破折号，不写「未知」/ 0。
     */
    fun versionRows(maxLevel: Int): List<Pair<String, String>> {
        val labels = HeroStatsCopy.versionLabels
        return listOf(
            labels[0] to gameVersion.ifEmpty { HeroStatsCopy.MISSING },
            labels[1] to dataVersion.ifEmpty { HeroStatsCopy.MISSING },
            labels[2] to generatedAt.ifEmpty { HeroStatsCopy.MISSING },
            labels[3] to "schemaVersion $schemaVersion",
            labels[4] to HeroStatsCopy.contentSummary(heroes.size, maxLevel, statModifiers.size, libraRespecs.size),
        )
    }
}
