package com.nightreign.relicchecker.gamedata.heroes

import kotlin.math.abs

/** 转职遗物增减量在某一级的来历。 */
enum class HeroModifierSource(
    /** 三档三色，与 macOS HeroModifierSource.colorToken / Windows SOURCE_PILL 同一张表。 */
    val colorToken: String,
    /** 手机端徽标前的小符号；三档各不相同（「沿用锚点」与「锚点」不能只靠文字区分）。 */
    val glyph: String,
) {
    /** 参数表原值（1 / 12 级）。 */
    ANCHOR("green", "✓"),

    /** 锚点之间的线性插值推算（2–11 级）。 */
    INFERRED("amber", "≈"),

    /** 沿用最后一个锚点（13–15 级）。 */
    CARRIED("blue", "→"),
}

data class HeroModifierSourceTag(val source: HeroModifierSource, val label: String)

/** 增减量的涨跌（页面配色：涨绿、跌红、不变中性；Windows deltaClass 同一条）。 */
enum class HeroDeltaTone {
    UP, DOWN, FLAT;

    companion object {
        fun of(value: Int): HeroDeltaTone = when {
            value > 0 -> UP
            value < 0 -> DOWN
            else -> FLAT
        }

        fun of(value: Double): HeroDeltaTone = when {
            value > 0.0001 -> UP
            value < -0.0001 -> DOWN
            else -> FLAT
        }
    }
}

/** 数值格式化（逐条移植 macOS HeroStatsText）。 */
object HeroStatsText {
    /** 去掉多余 0 的小数：74.10 → 74.1，45.0 → 45。 */
    fun decimal(value: Double, digits: Int = 1): String {
        if (!value.isFinite()) return HeroStatsCopy.MISSING
        var text = HeroStatsMath.fixed(value, digits)
        if (text.contains('.')) {
            text = text.trimEnd('0').trimEnd('.')
        }
        return if (text == "-0") "0" else text
    }

    /** 带符号的增减量：+5 / -3 / 0。 */
    fun signed(value: Int): String = if (value > 0) "+$value" else value.toString()

    fun signed(value: Double, digits: Int = 1): String {
        val text = decimal(abs(value), digits)
        return when {
            value > 0 -> "+$text"
            value < 0 -> "-$text"
            else -> "0"
        }
    }

    /** 属性值：没有数值时给破折号，不要退回 0（0 是真实数值，破折号才是「没有」）。 */
    fun statText(value: Int?): String = value?.toString() ?: HeroStatsCopy.MISSING

    /**
     * 派生值：整数项直接显示，负重上限**固定**保留 1 位小数（45.0 不写成 45，整列小数点才对得齐）；
     * 缺 growthGraph 或缺来源属性时给破折号。
     */
    fun derivedText(value: Double?, integer: Boolean): String {
        if (value == null || !value.isFinite()) return HeroStatsCopy.MISSING
        return if (integer) {
            HeroStatsMath.roundHalfAwayFromZero(value).toLong().toString()
        } else {
            HeroStatsMath.fixed(value, 1)
        }
    }

    /**
     * 某一级的转职遗物增减量来源：锚点 / 推算 / 沿用最后一个锚点。锚点等级一律读数据集的
     * `interpolation.modifierAnchorLevels`，不写死 1 / 12；没有锚点信息时返回 null（什么都不标）。
     */
    fun modifierSource(level: Int, anchorLevels: List<Int>): HeroModifierSourceTag? {
        val last = anchorLevels.maxOrNull() ?: return null
        if (level in anchorLevels) return HeroModifierSourceTag(HeroModifierSource.ANCHOR, "词条锚点")
        if (level > last) return HeroModifierSourceTag(HeroModifierSource.CARRIED, "词条沿用 $last 级锚点")
        return HeroModifierSourceTag(HeroModifierSource.INFERRED, "词条推算")
    }

    /**
     * 数据集原文用 Markdown 的 `**粗体**` 标记重点：拆成「文字 + 是否加粗」的片段，页面据此
     * 渲染粗体而不是把星号原样显示出来（Windows strongHtml 同一套配对规则：成对的 ** 才算，
     * 落单的 ** 原样保留）。
     */
    fun boldSegments(text: String): List<Pair<String, Boolean>> {
        val parts = text.split("**")
        if (parts.size < 3) return listOf(text to false)
        return parts.mapIndexed { index, part ->
            when {
                index == parts.lastIndex && index % 2 == 1 -> "**$part" to false
                index % 2 == 1 -> part to true
                else -> part to false
            }
        }.filter { it.first.isNotEmpty() }
    }
}

/**
 * 「角色属性」页三端必须逐字相同的文案：macOS RelicCore/HeroData.swift 的 HeroStatsCopy 与
 * Windows renderer/pages/heroes.js 的 COPY 是同一份，这里照抄，JVM 测试把同一批字面量钉死。
 * 改文案时三端 + 三份用例一起改。
 */
object HeroStatsCopy {
    /** 没有数值时统一显示破折号，**不要**退回 0。 */
    const val MISSING = "—"
    const val EMPTY_DATA = "数据未内置"

    // 视图
    const val VIEW_SINGLE = "单角色"
    const val VIEW_COMPARE = "同级对比"

    // 基础表的等级来源
    fun baseLevelBadge(level: Int, isAnchor: Boolean): String =
        if (isAnchor) "$level 级是参数锚点" else "$level 级为插值推算"

    const val BASE_ANCHOR_TAG = "参数锚点"
    const val BASE_INTERPOLATED_TAG = "插值推算"

    fun allLevelsCaption(anchorLevels: List<Int>): String =
        "加粗行是参数表里的锚点（" + anchorLevels.joinToString(" / ") + " 级），其余等级按相邻锚点线性插值后向下取整。"

    // 转职遗物
    fun modifierCountBadge(count: Int): String = "转职遗物 $count 条"
    const val MODIFIER_SUBTITLE = "勾选后在基础属性上加减（可同时勾选，效果相加）；派生值按 CalcCorrectGraph 重算"
    const val DLC_ONLY_TAG = "仅 DLC 池可掉"
    const val NO_DELTA_AT_LEVEL = "本级无增减"
    const val NO_MODIFIER_DATA = "数据未内置该角色的转职遗物词条"

    /** 「生命力 -5、集中力 +10」：增减量摘要，按属性展示顺序排、跳过 0。 */
    fun deltaSummary(delta: Map<String, Int>, names: HeroStatNames): String =
        names.attributeKeys
            .filter { (delta[it] ?: 0) != 0 }
            .joinToString("、") { names.attributeTitle(it) + " " + HeroStatsText.signed(delta[it] ?: 0) }

    /** deltaFloorAlt 只含负向项的替换，文案写清楚「其余项不变」。 */
    fun floorAlt(summary: String): String = "若按 floor 取整，负向项改为：" + summary + "（其余项不变）"

    /**
     * 「锚点只有 1 / 12 级：…」这句里的等级一律取自数据集锚点表（Windows modifierRuleHint 原文）。
     */
    fun modifierRuleHint(anchorLevels: List<Int>, maxLevel: Int): String {
        if (anchorLevels.isEmpty()) return "数据集没有给出转职遗物的参数锚点等级，本页不另立说法。"
        val last = anchorLevels.max()
        return "锚点只有 " + anchorLevels.joinToString(" / ") + " 级：中间等级是线性插值后向零取整的推算值，" +
            last + " 级之后沿用 " + last + " 级锚点（沿用这一条已由多组 " + maxLevel + " 级实测确认）。"
    }

    // 钳位
    const val CLAMP_CELL_TAG = "钳"
    const val CLAMP_ROW_TAG = "已钳位"
    val clampTail: String get() = "已钳到最低 ${HeroStatsMath.MINIMUM_STAT}"
    private val clampFloor: String get() = "（游戏里属性不会低于 ${HeroStatsMath.MINIMUM_STAT}）"

    fun clampedFromNote(raw: Int): String = "原为 $raw，" + clampTail

    /** 卡片上的大数字是**生效**增减量；请求值只在这句小字里出现（「词条请求 -9，已钳到最低 1」）。 */
    fun clampRequestedNote(requested: Int): String = "词条请求 " + HeroStatsText.signed(requested) + "，" + clampTail

    fun clampSummary(names: List<String>): String =
        names.joinToString("、") + " 叠加后不足 ${HeroStatsMath.MINIMUM_STAT}，" + clampTail + clampFloor

    /** 全部等级视图的钳位汇总：**按行聚合**（每一级各列哪些属性被钳）。 */
    fun clampSummaryByLevel(rows: List<HeroClampedLevel>, maxLevel: Int): String {
        if (rows.isEmpty()) return ""
        val body = rows.joinToString("；") { "${it.level} 级 " + it.names.joinToString("、") }
        return "1–$maxLevel 级里有 ${rows.size} 级叠加后不足 ${HeroStatsMath.MINIMUM_STAT}：" +
            body + "；" + clampTail + clampFloor
    }

    // 利普拉的交易
    const val LIBRA_SWAP_TAG = "整套替换"
    const val LIBRA_HINT = "利普拉的交易把整套基础属性表替换掉；能否与转职遗物叠加是按参数字段结构推断的，未实测"
    const val LIBRA_EMPTY_HINT = "选中后基础表整套换成对应的替换表，转职遗物仍可叠加。"
    fun libraBadge(statName: String): String = "利普拉：$statName"

    // 与外部 wiki 的逐格对照
    fun crossCheckNote(count: Int, note: String): String =
        "与外部 wiki 有 $count 格差异，本页以参数为准" + (if (note.isEmpty()) "" else "：$note")

    /** 做了利普拉的交易之后，基础表已经不是该角色的原表，wiki 差异提示无从谈起。 */
    const val LIBRA_CROSS_CHECK_NOTE = "已做利普拉的交易，基础表整套替换，与外部 wiki 的角色原表差异不再适用"

    // 负重上限：遗留列
    const val LEGACY_MARK = "*"
    fun legacyHeader(title: String): String = "$title $LEGACY_MARK"
    const val EQUIP_LOAD_HINT = "本作装备没有重量，负重上限是《艾尔登法环》继承下来的遗留列，未经实测"
    const val EQUIP_LOAD_FOOTNOTE = LEGACY_MARK +
        " 负重上限是《艾尔登法环》继承下来的遗留列：本作装备没有重量、界面也没有负重条，未经实测，仅供参考。"

    // 同级对比
    const val COMPARE_CAPTION = "对比表只用各角色的基础表：利普拉的交易不分角色（叠上去每行都一样），" +
        "转职遗物是逐角色的词条，都不进对比。"

    // 底部折叠区
    val interpolationNoteTitles: List<String> = listOf(
        "参数锚点", "基础属性插值", "基础表验证", "派生值换算", "转职遗物插值",
        "转职遗物锚点验证", "转职遗物中间等级", "取整方向", "兼容字段说明", "利普拉的交易",
    )

    fun interpolationAnchorNote(baseAnchorLevels: List<Int>, modifierAnchorLevels: List<Int>): String =
        "基础属性表只有 " + baseAnchorLevels.joinToString(" / ") + " 级是参数原值，" +
            "转职遗物只有 " + modifierAnchorLevels.joinToString(" / ") + " 级是参数原值。"

    fun roundingTerm(raw: String): String = when (raw) {
        "floor" -> "向下取整（floor）"
        "trunc" -> "向零取整（trunc）"
        "round" -> "四舍五入（round）"
        else -> raw
    }

    /** baseRounding / modifierRounding 两条口径；两个字段都缺时返回空串（整条说明不出现）。 */
    fun interpolationRoundingNote(base: String, modifier: String): String {
        val parts = mutableListOf<String>()
        if (base.isNotEmpty()) parts.add("基础属性表按" + roundingTerm(base))
        if (modifier.isNotEmpty()) parts.add("转职遗物增减量按" + roundingTerm(modifier))
        if (parts.isEmpty()) return ""
        var note = parts.joinToString("，") + "。"
        if (base != modifier && base.isNotEmpty() && modifier.isNotEmpty()) {
            note += "两种取整只在负的增减量上差 1；"
        }
        note += "换成另一种取整后结果不同的等级，数据集在 statModifiers[].levels[].deltaFloorAlt 里另给了一份备用值，" +
            "本页展示的一律是上面这一种。"
        return note
    }

    fun interpolationTitle(count: Int): String = "插值与验证口径（$count 条）"
    fun caveatsTitle(count: Int): String = "已知取舍（$count 条）"
    fun sourcesTitle(count: Int): String = "数据出处（$count 条）与外部对照"
    val versionLabels: List<String> = listOf("游戏版本", "数据版本", "生成时间", "数据集结构版本", "收录")

    fun contentSummary(heroes: Int, maxLevel: Int, modifiers: Int, libra: Int): String =
        "$heroes 位夜行者 × $maxLevel 级 · $modifiers 条转职遗物词条 · $libra 笔利普拉交易"
}
