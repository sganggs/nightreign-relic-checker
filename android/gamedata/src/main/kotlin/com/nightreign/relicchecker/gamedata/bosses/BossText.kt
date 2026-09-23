package com.nightreign.relicchecker.gamedata.bosses

import java.math.BigDecimal
import java.math.RoundingMode

// 「首领数据」页的文案表与数字格式。
//
// BossRowText / BossRoleText 与 macOS 端 RelicCore/BossData.swift 的同名 enum 逐字一致，
// 也与 Windows 端 renderer/pages/bosses.js 的 TEXT / ROLE_TEXT 是同一张表（两端已互相对拍）。
// 改文案必须三端一起改；BossTextTest 逐条钉住字面量。

/** 数字格式：与 macOS 的 BossFormat / BossRowText.decimal 同口径。 */
object BossFormat {
    /**
     * 去掉多余 0 的小数：1.350 → 1.35，2.0 → 2；非有限数给「—」。
     *
     * macOS 用 `String(format: "%.Nf")`（C printf：按二进制精确值四舍六入五成双），
     * 这里用 `BigDecimal(value)`（同样是二进制精确值）+ HALF_EVEN 复刻同一结果，
     * 不用 `String.format`（Java 按最短十进制表示 HALF_UP，1.005 这类边界会差一位）。
     */
    fun decimal(value: Double, digits: Int = 2): String {
        if (!value.isFinite()) return "—"
        var text = BigDecimal(value).setScale(digits, RoundingMode.HALF_EVEN).toPlainString()
        if (text.contains('.')) {
            text = text.trimEnd('0').trimEnd('.')
        }
        if (text == "-0") text = "0"
        return text.ifEmpty { "0" }
    }

    /** 倍率：×1.35（默认三位小数）。 */
    fun multiplier(value: Double, digits: Int = 3): String = "×" + decimal(value, digits)

    /** 整数带千位分隔：11328 → 11,328。 */
    fun integer(value: Int): String {
        val negative = value < 0
        val digits = kotlin.math.abs(value.toLong()).toString()
        val builder = StringBuilder()
        digits.forEachIndexed { index, char ->
            if (index > 0 && (digits.length - index) % 3 == 0) builder.append(',')
            builder.append(char)
        }
        return (if (negative) "-" else "") + builder.toString()
    }

    /** 承伤倍率分类（macOS 的 BossFormat.rateColor / rateTag，Windows 的 rateClass / rateNote）。 */
    fun rateClass(value: Double): BossRateClass = when {
        !value.isFinite() -> BossRateClass.FLAT
        value > 1.0001 -> BossRateClass.WEAK
        value < 0.9999 -> BossRateClass.RESIST
        else -> BossRateClass.FLAT
    }
}

/** 承伤倍率 > 1 为弱点（多吃伤害），< 1 为抗性。 */
enum class BossRateClass(val tag: String?) {
    WEAK("弱点"),
    RESIST("抗性"),
    FLAT(null),
}

/** 「首领数据」页里两端必须逐字相同的几串文案与数字格式（macOS 的 BossRowText）。 */
object BossRowText {
    const val labelUncertainBadge = "标签为社区推测"
    const val deepRowBadge = "深夜数值"
    const val deepExclusiveBadge = "深夜专属修正"
    const val nameFallbackBadge = "参考译名 · 非本作游戏文本"
    const val nameApproxBadge = "近似匹配"
    const val hiddenToggleTitle = "显示隐藏实体"
    const val hiddenToggleHelp = "召唤物 / 投射物等非首领实体"
    const val noRewardGroupNote = "该组不掉任何奖励（getSoul / 掉落表全为 0 或 -1）"
    const val noRewardRowNote = "该行不掉任何奖励"
    const val noDepthStatsText = "该行无深夜数值"
    const val mutationPickerTitle = "按变异个体计算"
    const val mutationPickerNone = "无"
    const val mutationStackNote = "变异倍率在其它缩放之上再乘一层，按参数结构推断"
    const val mutationCountNote = "表里是「有几只被变异」的只数，不是百分比概率"
    const val attackRateUnchanged = "不变"
    const val depthWeightZero = "该深度不会出现"
    const val multiplayerAuditSummary =
        "多人不是简单乘倍：血量按档位从 ×1 到 ×3 不等（最终 Boss 档才是 ×2 / ×3，" +
            "野外常见档 7740 只有 ×1.1 / ×1.2，突袭档 98810 / 98815 完全不加血）；" +
            "7744 / 7753 / 7754 / 7758 四档的敌人攻击力还会上浮 10% / 20%；" +
            "防御、卢恩与掉落、异常触发阈值三项人数缩放一概不碰，" +
            "变的只是异常累积量与发动伤害倍率（都往下走，人越多越难上异常）。"

    /** 卡头右侧的数值行计数：「N 条数值行」。 */
    fun rowCount(count: Int): String = "$count 条数值行"

    /** 血量旁的多人攻击徽标：「多人攻击 ×1.1」。 */
    fun multiplayerAttackBadge(attackRate: Double): String =
        "多人攻击 ×" + BossFormat.decimal(attackRate, 3)

    /** 人数缩放明细里的攻击力值：1 倍时写「不变」。 */
    fun attackRateText(value: Double): String {
        if (!value.isFinite()) return "—"
        if (kotlin.math.abs(value - 1) < 0.0001) return attackRateUnchanged
        return "×" + BossFormat.decimal(value, 3)
    }

    /** 夜王某深度的出现权重文案（不加千位分隔符）。 */
    fun depthWeightText(weight: Int): String = if (weight <= 0) depthWeightZero else "权重 $weight"

    /** poise > 0 却算不出有效韧性时的小字（承受削韧倍率为 0 / 非有限）。 */
    fun abnormalPoiseTakenCaption(factor: Double): String =
        "承受削韧倍率异常（${BossFormat.decimal(factor, 3)}）"

    /** 展开态「有效韧性」下面的小字，四支两端逐字一致。 */
    fun poiseCaption(
        poise: Double,
        poiseTakenTotal: Double,
        kind: BossPoiseKind,
        hasEffectivePoise: Boolean,
    ): String {
        if (hasEffectivePoise) {
            return "韧性 ${BossFormat.decimal(poise, 0)} ÷ 承受削韧 ${BossFormat.decimal(poiseTakenTotal, 3)}"
        }
        return when (kind) {
            BossPoiseKind.ZERO -> "superArmorDurability = 0，该实体没有削韧槽"
            BossPoiseKind.NONE -> "superArmorDurability = ${BossFormat.decimal(poise, 0)}"
            BossPoiseKind.VALUE -> abnormalPoiseTakenCaption(poiseTakenTotal)
        }
    }

    /** 展开态「多人缩放明细」标题右边的档位说明。 */
    fun scalingCaption(scalingId: Int?, groupTitle: String?): String {
        if (scalingId == null) return "无缩放档位"
        if (groupTitle.isNullOrEmpty()) return "档位 #$scalingId"
        return "档位 #$scalingId · $groupTitle"
    }
}

/** 按出场场合分组的文案（macOS 的 BossRoleText，Windows 的 ROLE_TEXT）。 */
object BossRoleText {
    const val groupNightlord = "夜王"
    const val groupNight = "守夜首领"
    const val groupStronghold = "据点首领"
    const val groupField = "场景头目"
    const val groupEvergaol = "封印监牢"
    const val groupOther = "其它场合"
    const val groupSummon = "随从/召唤物"
    const val groupUnplaced = "未放置"

    /** roleNames 缺失时的内置中文名（与 v4 数据集 roleNames.*.zh 逐字相同）。 */
    val builtinRoleNames: Map<String, String> = linkedMapOf(
        "night" to "守夜首领",
        "prelude" to "守夜前哨",
        "field" to "场景头目",
        "stronghold" to "据点首领",
        "mine" to "坑道精英",
        "evergaol" to "封印监牢",
        "tower" to "大空洞高塔首领",
        "raid" to "突袭事件",
        "invader" to "黑夜入侵者",
        "event" to "地图事件",
        "nightlord" to "夜王战",
        "summon" to "随从/召唤物",
        "other" to "其他地图",
        "unplaced" to "未放置",
    )

    const val threatTierLabel = "威胁档位"
    const val threatTierNote =
        "威胁档位只是多人缩放档位（Field / Night Boss Threat），不代表出场场合；分组按地图放置判定的出场场合"
    const val rolesMissing = "出场场合：数据未内置"
    const val evidenceMissing = "出处：数据未内置"
    const val roleSectionTitle = "出场场合"
    const val roleSectionDetail = "按地图放置与抽选参数判定；分组看这里，不看威胁档位"
    const val evidenceExpand = "展开全部出处"
    const val evidenceCollapse = "只看每个场合的第一条出处"
    const val hiddenGroupMark = "（默认隐藏）"
    const val rowRolesTitle = "逐行场合"
    const val groupPickerHelp = "按出场场合分组；一组首领可以同时出现在多个分组里"
    const val hiddenToggleRoleHelp = "也控制「未放置」「随从/召唤物」两个场合（分组与展开区的行）"
    const val multiGroupNameLimit = 12

    fun overviewTitle(count: Int): String = "出场场合说明（$count 种）"

    fun auditTitle(count: Int): String = "与威胁档位的对照（数据集 notes.roleAudit，$count 条）"

    /** 底部场合说明表里的计数：「40 组」「1 组 · 夜王 6」「夜王 18」。 */
    fun roleCountText(groups: Int, nightlords: Int): String {
        val parts = mutableListOf<String>()
        if (groups > 0 || nightlords == 0) parts += "$groups 组"
        if (nightlords > 0) parts += "夜王 $nightlords"
        return parts.joinToString(" · ")
    }

    /** 卡头计数：显示的行数，另有默认隐藏的行时补一句。 */
    fun rowCount(visible: Int, hidden: Int): String {
        val base = BossRowText.rowCount(visible)
        return if (hidden > 0) "$base（另 $hidden 条已隐藏）" else base
    }

    fun evidenceMore(count: Int): String = "另有 $count 条出处"

    fun hiddenRows(count: Int): String =
        "另有 $count 条「$groupUnplaced」/「$groupSummon」行已隐藏，打开「${BossRowText.hiddenToggleTitle}」查看"

    /** 「威胁档位 · 守夜首领威胁档 / 野外首领威胁档」：去重保序，空时写「无」，未知取值原样写。 */
    fun threatTierCaption(threats: List<String>): String {
        val seen = LinkedHashSet<String>()
        threats.filter { it.isNotEmpty() }.forEach { seen += it }
        val titles = seen.map { threat ->
            when (threat) {
                "night" -> BossScalingGroup.title("Night Boss Threat")
                "field" -> BossScalingGroup.title("Field Boss Threat")
                else -> threat
            }
        }
        return threatTierLabel + " · " + (if (titles.isEmpty()) "无" else titles.joinToString(" / "))
    }

    /** 底部说明：同时出现在多个分组的组数（名字最多列 12 个，其余写「等」）。 */
    fun multiGroupNote(count: Int, names: List<String>): String {
        var list = names.take(multiGroupNameLimit).joinToString("、")
        if (names.size > multiGroupNameLimit) list += " 等"
        return "有 $count 组首领按出场场合同时属于多个分组（$list），" +
            "它们在各个分组下都会出现：卡头列出全部场合，折叠态代表行跟着当前分组走，" +
            "展开后每行标了自己的场合与出处。"
    }

    /** 底部说明：默认不显示的组（「显示隐藏实体」开关管的两类）；两类都没有时返回空串。 */
    fun hiddenSummary(flagged: List<String>, roleOnly: List<String>): String {
        val parts = mutableListOf<String>()
        if (flagged.isNotEmpty()) {
            parts += "${flagged.size} 组被判定为非首领实体（${flagged.joinToString("、")}），" +
                "判据是整组不掉任何奖励，且不吃削韧 / 连社区资料都认不出 / 社区标为杂兵"
        }
        if (roleOnly.isNotEmpty()) {
            parts += "${roleOnly.size} 组只出现在「$groupUnplaced」「$groupSummon」" +
                "两个场合（${roleOnly.joinToString("、")}）"
        }
        if (parts.isEmpty()) return ""
        return "另有 " + parts.joinToString("；另有 ") + "。它们默认不在列表里，" +
            "展开区里只出现在这两个场合的数值行也默认隐藏；" +
            "需要时打开工具条的「${BossRowText.hiddenToggleTitle}」，" +
            "分组筛选里会多出「$groupSummon」「$groupUnplaced」两项。"
    }
}

/**
 * 只有页面（Windows / 手机）才有、macOS 没有对应常量的几串文案。
 * 与 Windows 端 bosses.js 的 ROLE_PAGE_TEXT / hiddenCountText 同文案。
 */
object BossPageText {
    /** 卡片级「出场场合」一览的小药丸：「场景头目 · 2 行」。 */
    fun roleRowsChip(title: String, rows: Int): String = "$title · $rows 行"

    fun currentGroupNote(groupTitle: String, rows: Int): String =
        "当前分组「$groupTitle」对应其中 $rows 条数值行（下方描边高亮），" +
            "折叠态的代表行只从这几行里选。"

    /** 列表计数里的「已隐藏 / 含隐藏」一段。 */
    fun hiddenCountText(count: Int, shown: Boolean): String {
        if (count == 0) return ""
        return if (shown) "含隐藏 $count 组" else "已隐藏 $count 组（未放置 / 随从 / 非首领实体）"
    }

    const val unofficialNote = "本页数值直接读取游戏参数表，不是官方公布数据，也不是实测结论；标注与实际手感可能有出入。"
    const val nightlordOnlyWeakness = "本作只给夜王官方弱点标注；展开看承伤倍率"
    const val hotRatesLabel = "代表行承伤偏高"
    const val noOfficialWeakness = "官方标注：无弱点"
    const val emptyTitle = "没有匹配的首领"
    const val emptyDetail = "请调整搜索关键词或分组筛选。"
}
