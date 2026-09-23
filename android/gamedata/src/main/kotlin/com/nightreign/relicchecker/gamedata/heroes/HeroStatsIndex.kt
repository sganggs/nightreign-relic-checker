package com.nightreign.relicchecker.gamedata.heroes

/**
 * 某个角色在某一级、叠加若干条转职遗物（可选利普拉替换）后的完整属性（macOS HeroStatsSnapshot）。
 */
data class HeroStatsSnapshot(
    val heroKey: String,
    val heroNameZh: String,
    val heroNameEn: String,
    val level: Int,
    /** 基础表这一级是不是参数锚点。 */
    val isAnchorLevel: Boolean,
    /** 选中的利普拉交易（整表替换）；null 表示没选。 */
    val libraKey: String?,
    /** 基础属性（利普拉替换之后、转职遗物之前）。 */
    val baseStats: Map<String, Int>,
    /** 最终属性（叠加转职遗物并钳位之后）。 */
    val finalStats: Map<String, Int>,
    /** 转职遗物给出的原始增减量之和（未钳位）。 */
    val requestedDelta: Map<String, Int>,
    /** 被钳到 1 的属性，按页面上的属性展示顺序排。 */
    val clampedStats: List<String>,
    /** 被钳属性钳位前的原值（页面写「原为 0，已钳到最低 1」）。 */
    val clampedFrom: Map<String, Int>,
    val baseDerived: Map<String, Double>,
    val finalDerived: Map<String, Double>,
    /** 生效的词条（按数据集顺序）。 */
    val activeModifiers: List<HeroStatModifier>,
    /** 这一级增减量的来历（锚点 / 推算 / 沿用）；没勾词条时为 null。徽标、表里备注列都读它。 */
    val modifierSource: HeroModifierSourceTag?,
) {
    /** 生效词条的这一级是锚点之间的推算（2–11 级）。 */
    val hasInferredDelta: Boolean get() = modifierSource?.source == HeroModifierSource.INFERRED

    /** 当前等级在最后一个锚点之后，增减量沿用那个锚点。 */
    val carriesAnchorDelta: Boolean get() = modifierSource?.source == HeroModifierSource.CARRIED

    val hasModifier: Boolean get() = activeModifiers.isNotEmpty()
    val isModified: Boolean get() = hasModifier || libraKey != null

    /**
     * 卡片 / 表格里显示的增减量：一律是**生效值**（最终 − 基础）。被钳位时它与请求值不同
     * （请求 -9、生效 -8），请求值走 HeroStatsCopy.clampRequestedNote 的小字。
     * 没勾词条、或这一项缺基础值 / 最终值时返回 null（没有可显示的增减量；Windows effectiveDelta 同口径）。
     */
    fun effectiveDelta(key: String): Int? {
        if (!hasModifier) return null
        val base = baseStats[key] ?: return null
        val after = finalStats[key] ?: return null
        return after - base
    }

    /** 派生值的变化量；任一侧缺值时返回 null。 */
    fun derivedDelta(key: String): Double? {
        val base = baseDerived[key] ?: return null
        val after = finalDerived[key] ?: return null
        return after - base
    }
}

/** 全部等级表的钳位汇总里的一行：等级 → 被钳属性中文名（按属性展示顺序）。 */
data class HeroClampedLevel(val level: Int, val names: List<String>)

/** 「同级对比」表的可排序列。 */
sealed interface HeroComparisonColumn {
    /** 存进 rememberSaveable 的字符串形式。 */
    val token: String

    data object Hero : HeroComparisonColumn {
        override val token: String = "hero"
    }

    data class Stat(val key: String) : HeroComparisonColumn {
        override val token: String get() = "stat:$key"
    }

    data class Derived(val key: String) : HeroComparisonColumn {
        override val token: String get() = "derived:$key"
    }

    companion object {
        fun fromToken(token: String): HeroComparisonColumn = when {
            token.startsWith("stat:") -> Stat(token.removePrefix("stat:"))
            token.startsWith("derived:") -> Derived(token.removePrefix("derived:"))
            else -> Hero
        }
    }
}

/** 「同级对比」表的一行。 */
data class HeroComparisonRow(
    val heroKey: String,
    val heroId: Int,
    val nameZh: String,
    val nameEn: String,
    val level: Int,
    val stats: Map<String, Int>,
    val derived: Map<String, Double>,
) {
    /** 排序用的数值；角色列没有数值（按数据集顺序排），未知列返回 null。 */
    fun value(column: HeroComparisonColumn): Double? = when (column) {
        HeroComparisonColumn.Hero -> null
        is HeroComparisonColumn.Stat -> stats[column.key]?.toDouble()
        is HeroComparisonColumn.Derived -> derived[column.key]
    }
}

object HeroComparison {
    /**
     * 按列排序。数值相同（或该列缺数据）时一律退回数据集顺序（heroId），也就是**稳定排序**：
     * 平手的几行在升序和降序里保持同一个相对顺序，数值列上点两次列头得到的**不是**严格反序
     * （macOS HeroComparison.sorted / Windows sortCompareRows 同一条）。永远返回新列表。
     */
    fun sorted(rows: List<HeroComparisonRow>, column: HeroComparisonColumn, ascending: Boolean): List<HeroComparisonRow> =
        rows.sortedWith { lhs, rhs ->
            if (column == HeroComparisonColumn.Hero) {
                when {
                    lhs.heroId != rhs.heroId ->
                        if (ascending) lhs.heroId.compareTo(rhs.heroId) else rhs.heroId.compareTo(lhs.heroId)
                    else -> lhs.heroKey.compareTo(rhs.heroKey)
                }
            } else {
                val left = lhs.value(column)
                val right = rhs.value(column)
                when {
                    left != null && right != null && left != right ->
                        if (ascending) left.compareTo(right) else right.compareTo(left)
                    left != null && right == null -> -1 // 有数据的排在缺数据的前面
                    left == null && right != null -> 1
                    else -> lhs.heroId.compareTo(rhs.heroId)
                }
            }
        }

    /** 每列的最大值（对比表里把该列最高者标绿；macOS HeroCompareTable.extremes 同口径）。 */
    fun columnMaxima(rows: List<HeroComparisonRow>, names: HeroStatNames): Map<HeroComparisonColumn, Double> {
        val result = LinkedHashMap<HeroComparisonColumn, Double>()
        val columns = names.attributeKeys.map { HeroComparisonColumn.Stat(it) } +
            names.derivedKeys.map { HeroComparisonColumn.Derived(it) }
        for (column in columns) {
            rows.mapNotNull { it.value(column) }.maxOrNull()?.let { result[column] = it }
        }
        return result
    }
}

/**
 * 页面用的数据索引：解析一次（后台线程），之后所有换算都走这里的纯函数（macOS HeroStatsIndex）。
 */
class HeroStatsIndex(val dataset: HeroDataset) {
    private val heroesByKey: Map<String, HeroEntry> =
        LinkedHashMap<String, HeroEntry>().also { map -> dataset.heroes.forEach { map.putIfAbsent(it.key, it) } }
    private val modifiersByHero: Map<String, List<HeroStatModifier>> = dataset.statModifiers.groupBy { it.heroKey }
    private val libraByKey: Map<String, HeroLibraRespec> =
        LinkedHashMap<String, HeroLibraRespec>().also { map -> dataset.libraRespecs.forEach { map.putIfAbsent(it.key, it) } }

    val heroes: List<HeroEntry> get() = dataset.heroes
    val statNames: HeroStatNames get() = dataset.statNames
    val libraRespecs: List<HeroLibraRespec> get() = dataset.libraRespecs

    /**
     * 能不能正常展示：至少一个角色，且数据集给了 growthGraphs（缺了就没法重算派生值；
     * Windows hasHeroData 同一条，页面此时降级显示「数据未内置」）。
     */
    val hasHeroData: Boolean get() = dataset.heroes.isNotEmpty() && dataset.growthGraphsDeclared

    /**
     * 数据集声明的最大等级；没声明（或声明成 0）时退回各角色 levels 里的最大等级，
     * 再没有才退回 [FALLBACK_MAX_LEVEL]。等级选择器、表体行数、标题与汇总一起跟着数据集走。
     */
    val maxLevel: Int = run {
        val declared = dataset.interpolation.maxLevel
        if (declared > 0) declared else dataset.heroes.maxOfOrNull { it.maxLevel }?.takeIf { it > 0 } ?: FALLBACK_MAX_LEVEL
    }

    val levelRange: List<Int> get() = (1..maxOf(1, maxLevel)).toList()

    /** 把任意等级钳进 1 … maxLevel；null 时取最大等级（Windows clampLevel 同口径）。 */
    fun clampLevel(level: Int?): Int = (level ?: maxLevel).coerceIn(1, maxOf(1, maxLevel))

    val baseAnchorLevels: List<Int> get() = dataset.interpolation.baseAnchorLevels.filter { it > 0 }
    val modifierAnchorLevels: List<Int> get() = dataset.interpolation.modifierAnchorLevels.filter { it > 0 }

    fun hero(key: String): HeroEntry? = heroesByKey[key]

    fun modifiers(heroKey: String): List<HeroStatModifier> = modifiersByHero[heroKey].orEmpty()

    /** 只认本角色的词条，按传入的 id 过滤（Windows selectedModifiers）。 */
    fun selectedModifiers(heroKey: String, ids: Collection<Int>): List<HeroStatModifier> =
        modifiers(heroKey).filter { it.affixId in ids }

    fun libra(key: String?): HeroLibraRespec? = key?.let { libraByKey[it] }

    /** 某个角色与外部 wiki 的逐格对照；**只有真有差异时**才返回。 */
    fun crossCheck(heroKey: String): HeroCrossCheck? =
        dataset.crossChecks.firstOrNull { it.heroKey == heroKey && it.mismatchCount > 0 }

    /**
     * 状态栏下的 wiki 差异提示：做了利普拉的交易之后基础表已整套换掉，改写成一句说明；
     * 没有差异时返回 null。
     */
    fun crossCheckNote(heroKey: String, libraKey: String?): String? {
        val check = crossCheck(heroKey) ?: return null
        if (libra(libraKey) != null) return HeroStatsCopy.LIBRA_CROSS_CHECK_NOTE
        return HeroStatsCopy.crossCheckNote(check.mismatchCount, check.note)
    }

    val summary: String get() = "${dataset.heroes.size} 位夜行者 · 1–$maxLevel 级"

    /** 基础属性表：选了利普拉的交易就整套换成对应的表（heroStatusId 替换）。 */
    fun baseLevels(heroKey: String, libraKey: String?): List<HeroLevelRow> =
        libra(libraKey)?.levels ?: hero(heroKey)?.levels.orEmpty()

    fun baseLevel(heroKey: String, level: Int, libraKey: String?): HeroLevelRow? =
        baseLevels(heroKey, libraKey).firstOrNull { it.level == level }

    /** 派生值：一律按 growthGraphs 现算（与数据集自带的 derived 逐格一致，见 JVM 测试）。 */
    fun derivedValues(stats: Map<String, Int>): Map<String, Double> =
        HeroStatsMath.derivedValues(stats, dataset.statNames, dataset.growthGraphs)

    /** 某一级的转职遗物增减量来源（等级先钳进范围；没有锚点信息时为 null）。 */
    fun modifierLevelNote(level: Int): HeroModifierSourceTag? =
        HeroStatsText.modifierSource(clampLevel(level), modifierAnchorLevels)

    /** 转职遗物说明句（「锚点只有 1 / 12 级：…」）。 */
    val modifierRuleHint: String get() = HeroStatsCopy.modifierRuleHint(modifierAnchorLevels, maxLevel)

    /**
     * 某个角色在某一级、叠加若干条词条后的完整属性。等级不在表里（例如 99）或角色未知时返回 null；
     * 页面传入的等级先经 [clampLevel]。
     */
    fun snapshot(
        heroKey: String,
        level: Int,
        modifierIds: Set<Int> = emptySet(),
        libraKey: String? = null,
    ): HeroStatsSnapshot? {
        val hero = hero(heroKey) ?: return null
        val baseRow = baseLevel(heroKey, level, libraKey) ?: return null
        val active = modifiers(heroKey).filter { it.affixId in modifierIds }
        val rows = active.mapNotNull { it.level(level) }
        val applied = HeroStatsMath.apply(rows.map { it.delta }, baseRow.stats, dataset.statNames.attributeKeys)
        return HeroStatsSnapshot(
            heroKey = hero.key,
            heroNameZh = hero.nameZh,
            heroNameEn = hero.nameEn,
            level = level,
            isAnchorLevel = baseRow.isAnchor,
            libraKey = libra(libraKey)?.key,
            baseStats = baseRow.stats,
            finalStats = applied.stats,
            requestedDelta = applied.requested,
            clampedStats = applied.clamped,
            clampedFrom = applied.clampedFrom,
            baseDerived = derivedValues(baseRow.stats),
            finalDerived = derivedValues(applied.stats),
            activeModifiers = active,
            modifierSource = if (active.isEmpty()) null else HeroStatsText.modifierSource(level, modifierAnchorLevels),
        )
    }

    /** 「全部等级」表：1 … maxLevel 逐行（同样支持词条叠加与利普拉替换）。 */
    fun snapshots(
        heroKey: String,
        modifierIds: Set<Int> = emptySet(),
        libraKey: String? = null,
    ): List<HeroStatsSnapshot> = levelRange.mapNotNull { snapshot(heroKey, it, modifierIds, libraKey) }

    /** 全部等级表的钳位汇总：按**行**聚合成「等级 → 被钳属性中文名」。 */
    fun clampedByLevel(snapshots: List<HeroStatsSnapshot>): List<HeroClampedLevel> =
        snapshots
            .filter { it.clampedStats.isNotEmpty() }
            .sortedBy { it.level }
            .map { snapshot -> HeroClampedLevel(snapshot.level, snapshot.clampedStats.map { dataset.statNames.attributeTitle(it) }) }

    /**
     * 「同级对比」表：某一级下各角色的基础属性与派生值（不含转职遗物 / 利普拉）。
     * 这一级没有数据的角色整行丢掉，而不是摆一行 0。
     */
    fun comparisonRows(level: Int): List<HeroComparisonRow> = dataset.heroes.mapNotNull { hero ->
        val row = hero.level(level) ?: return@mapNotNull null
        HeroComparisonRow(
            heroKey = hero.key,
            heroId = hero.id,
            nameZh = hero.nameZh,
            nameEn = hero.nameEn,
            level = level,
            stats = row.stats,
            derived = derivedValues(row.stats),
        )
    }

    /** 数据版本块的 5 行。 */
    fun versionRows(): List<Pair<String, String>> = dataset.versionRows(maxLevel)

    companion object {
        /** 数据集既没声明最大等级、角色表里也一行都没有时才用这个常量。 */
        const val FALLBACK_MAX_LEVEL = 15
    }
}
