package com.nightreign.relicchecker.ui.bosses

import androidx.compose.foundation.ScrollState
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.FlowRowScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.saveable.Saver
import androidx.compose.runtime.saveable.listSaver
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.layout
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.nightreign.relicchecker.gamedata.bosses.BossGroup
import com.nightreign.relicchecker.gamedata.bosses.BossRoleBadge
import com.nightreign.relicchecker.ui.NightPill
import com.nightreign.relicchecker.ui.theme.NightColors

// 首领数据页内部共用的小组件与配色。骨架的 Components.kt 不改，页面需要的变体都写在这里（internal / private）。

/**
 * 场合 → 颜色：跟着场合所在的分组走（「其它场合」里的几种共用一色），默认隐藏的两种压暗。
 * 与 macOS 端 BossRoleStyle 同一套；主题色板只有紫 / 绿 / 琥珀 / 红，下面三种只在本页用。
 */
internal object BossPalette {
    /** 据点首领：铜色（与夜王的琥珀色区分开）。 */
    val Stronghold = Color(0xFFEB8A57)

    /** 封印监牢：青蓝色。 */
    val Evergaol = Color(0xFF5CB3ED)

    /** 其它场合（高塔 / 突袭 / 入侵 / 事件等）：兰紫色。 */
    val Other = Color(0xFFD68CED)

    fun group(group: BossGroup): Color = when (group) {
        BossGroup.NIGHTLORD -> NightColors.Amber
        BossGroup.NIGHT -> NightColors.PurpleSoft
        BossGroup.STRONGHOLD -> Stronghold
        BossGroup.FIELD -> NightColors.Green
        BossGroup.EVERGAOL -> Evergaol
        BossGroup.OTHER -> Other
        BossGroup.SUMMON, BossGroup.UNPLACED -> NightColors.TextMuted
    }

    fun badge(badge: BossRoleBadge): Color = when {
        badge.hidden -> NightColors.TextMuted
        badge.current -> group(badge.group)
        else -> NightColors.TextSecondary
    }
}

/** 等宽数字（表格、数值格用）。 */
internal fun TextStyle.tabular(): TextStyle = copy(fontFeatureSettings = "tnum")

/** 展开状态等字符串集合的 rememberSaveable 存法。 */
internal val StringSetSaver: Saver<Set<String>, Any> = listSaver(
    save = { it.toList() },
    restore = { it.toSet() },
)

/** 会自动换行的徽标排布（一组首领最多 7 个出场场合，一行放不下）。 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
internal fun BossFlow(
    modifier: Modifier = Modifier,
    content: @Composable FlowRowScope.() -> Unit,
) {
    FlowRow(
        modifier = modifier,
        horizontalArrangement = Arrangement.spacedBy(6.dp),
        verticalArrangement = Arrangement.spacedBy(5.dp),
        content = content,
    )
}

@Composable
internal fun RolePill(badge: BossRoleBadge, text: String = badge.title) {
    NightPill(text, BossPalette.badge(badge))
}

/** 展开区的小标题：标题 + 右侧灰色说明（说明可换行）。 */
@Composable
internal fun BossSubHeading(title: String, detail: String? = null, modifier: Modifier = Modifier) {
    Column(modifier = modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(2.dp)) {
        Text(title, style = MaterialTheme.typography.labelLarge, fontWeight = FontWeight.SemiBold, color = NightColors.TextPrimary)
        if (!detail.isNullOrEmpty()) {
            Text(detail, style = MaterialTheme.typography.labelSmall, color = NightColors.TextMuted)
        }
    }
}

/** 一个数值块：小标题 / 数值 / 说明小字。放在两列网格里，宽度由父级决定。 */
@Composable
internal fun BossMetric(
    title: String,
    value: String,
    modifier: Modifier = Modifier,
    caption: String? = null,
    tint: Color = NightColors.TextPrimary,
) {
    Column(modifier = modifier, verticalArrangement = Arrangement.spacedBy(1.dp)) {
        Text(title, style = MaterialTheme.typography.labelSmall, color = NightColors.TextMuted)
        Text(
            value,
            style = MaterialTheme.typography.titleMedium.tabular(),
            color = tint,
            fontWeight = FontWeight.SemiBold,
        )
        if (!caption.isNullOrEmpty()) {
            Text(caption, style = MaterialTheme.typography.labelSmall, color = NightColors.TextMuted)
        }
    }
}

/** 两列网格（数值块用）：按顺序两两一行。 */
@Composable
internal fun <T> BossTwoColumns(
    items: List<T>,
    modifier: Modifier = Modifier,
    spacing: Dp = 12.dp,
    cell: @Composable (T, Modifier) -> Unit,
) {
    Column(modifier = modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        items.chunked(2).forEach { pair ->
            Row(horizontalArrangement = Arrangement.spacedBy(spacing), modifier = Modifier.fillMaxWidth()) {
                pair.forEach { cell(it, Modifier.weight(1f)) }
                if (pair.size == 1) Box(Modifier.weight(1f))
            }
        }
    }
}

/** 等分小格网格（承伤倍率 8 格、异常抗性 7 格，每行 4 格）。 */
@Composable
internal fun <T> BossCellGrid(
    items: List<T>,
    columns: Int = 4,
    cell: @Composable (T, Modifier) -> Unit,
) {
    Column(verticalArrangement = Arrangement.spacedBy(6.dp), modifier = Modifier.fillMaxWidth()) {
        items.chunked(columns).forEach { chunk ->
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp), modifier = Modifier.fillMaxWidth()) {
                chunk.forEach { cell(it, Modifier.weight(1f)) }
                repeat(columns - chunk.size) { Box(Modifier.weight(1f)) }
            }
        }
    }
}

/** 一个带底色的小格：标题 / 数值 / 标注。 */
@Composable
internal fun BossValueCell(
    title: String,
    value: String,
    tint: Color,
    modifier: Modifier = Modifier,
    tag: String? = null,
    tagColor: Color = tint,
    fill: Color = Color.White.copy(alpha = 0.03f),
) {
    Column(
        modifier = modifier
            .clip(RoundedCornerShape(8.dp))
            .background(fill)
            .padding(vertical = 6.dp, horizontal = 2.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(1.dp),
    ) {
        Text(title, style = MaterialTheme.typography.labelSmall, color = NightColors.TextSecondary, maxLines = 1)
        Text(value, style = MaterialTheme.typography.bodyLarge.tabular(), color = tint, fontWeight = FontWeight.Bold, maxLines = 1)
        if (tag != null) {
            Text(tag, style = MaterialTheme.typography.labelSmall, color = tagColor, maxLines = 1)
        }
    }
}

/**
 * 首列固定、其余列横向滚动的小表：表头与各行共用同一个 [scroll]，同步横滚。
 * [highlight] 为 true 的行加紫色底（当前深度 / 当前人数）。
 */
@Composable
internal fun BossScrollTable(
    header: List<String>,
    rows: List<List<String>>,
    scroll: ScrollState,
    firstColumnWidth: Dp,
    columnWidth: Dp,
    modifier: Modifier = Modifier,
    showHeader: Boolean = true,
    highlight: (Int) -> Boolean = { false },
    headerColor: (column: Int) -> Color = { NightColors.TextMuted },
    cellColor: (row: Int, column: Int) -> Color = { _, _ -> NightColors.TextPrimary },
) {
    val shape = RoundedCornerShape(10.dp)
    Column(
        modifier = modifier
            .fillMaxWidth()
            .clip(shape)
            .background(Color.White.copy(alpha = 0.03f))
            .border(1.dp, NightColors.Border, shape),
    ) {
        if (showHeader) {
            TableLine(header, scroll, firstColumnWidth, columnWidth, isHeader = true, highlighted = false, color = headerColor)
        }
        rows.forEachIndexed { index, cells ->
            TableLine(cells, scroll, firstColumnWidth, columnWidth, isHeader = false, highlighted = highlight(index)) { column ->
                cellColor(index, column)
            }
        }
    }
}

@Composable
private fun TableLine(
    cells: List<String>,
    scroll: ScrollState,
    firstColumnWidth: Dp,
    columnWidth: Dp,
    isHeader: Boolean,
    highlighted: Boolean,
    color: (Int) -> Color,
) {
    val style = (if (isHeader) MaterialTheme.typography.labelSmall else MaterialTheme.typography.bodySmall).tabular()
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .background(if (highlighted) NightColors.Purple.copy(alpha = 0.14f) else Color.Transparent)
            .padding(vertical = if (isHeader) 6.dp else 5.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            cells.firstOrNull().orEmpty(),
            modifier = Modifier.width(firstColumnWidth).padding(start = 10.dp, end = 4.dp),
            style = style,
            color = if (highlighted) NightColors.PurpleSoft else color(0),
            fontWeight = if (highlighted || isHeader) FontWeight.SemiBold else FontWeight.Normal,
        )
        Row(modifier = Modifier.weight(1f).horizontalScroll(scroll)) {
            cells.drop(1).forEachIndexed { index, text ->
                Text(
                    text,
                    modifier = Modifier.width(columnWidth).padding(end = 10.dp),
                    style = style,
                    textAlign = TextAlign.End,
                    maxLines = 1,
                    color = color(index + 1),
                    fontWeight = if (isHeader) FontWeight.SemiBold else FontWeight.Normal,
                )
            }
        }
    }
}

/** 底部说明的折叠块：整行可点（48dp），展开后显示 [content]。 */
@Composable
internal fun BossDisclosure(
    title: String,
    open: Boolean,
    onToggle: () -> Unit,
    modifier: Modifier = Modifier,
    trailing: String? = null,
    content: @Composable ColumnScope.() -> Unit,
) {
    Column(modifier = modifier.fillMaxWidth()) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .heightIn(min = 48.dp)
                .clip(RoundedCornerShape(10.dp))
                .clickable(role = Role.Button, onClickLabel = if (open) "收起" else "展开", onClick = onToggle)
                .padding(horizontal = 4.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Chevron(open)
            Text(
                title,
                modifier = Modifier.weight(1f),
                style = MaterialTheme.typography.bodyMedium,
                fontWeight = FontWeight.SemiBold,
                color = NightColors.TextPrimary,
            )
            trailing?.let { NightPill(it, NightColors.TextMuted) }
        }
        if (open) {
            Column(
                modifier = Modifier.fillMaxWidth().padding(start = 8.dp, end = 4.dp, bottom = 10.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp),
                content = content,
            )
        }
    }
}

/**
 * 数据集原文用 Markdown 的 **粗体** 标记重点：只把成对的 ** 换成粗体，其余字符原样保留
 * （不走完整 Markdown 解析，免得原文里的 / [ ] * 被误当成语法）。与 macOS 增伤排名页的
 * strongText、Windows ranker.js 的 strongHtml 同口径；落单的末尾 ** 原样显示。
 */
internal fun strongText(text: String): AnnotatedString {
    val parts = text.split("**")
    if (parts.size < 3) return AnnotatedString(text)
    return buildAnnotatedString {
        parts.forEachIndexed { index, part ->
            when {
                index == parts.lastIndex && index % 2 == 1 -> append("**$part")
                index % 2 == 1 -> withStyle(SpanStyle(fontWeight = FontWeight.SemiBold, color = NightColors.TextPrimary)) { append(part) }
                else -> append(part)
            }
        }
    }
}

/** 列表里的一条圆点文字（caveats、核实结论；数据集原文，** 粗体标记会被渲染）。 */
@Composable
internal fun BossBullet(text: String, color: Color = NightColors.TextSecondary) {
    Row(horizontalArrangement = Arrangement.spacedBy(7.dp)) {
        Text("·", style = MaterialTheme.typography.bodySmall, color = NightColors.TextMuted)
        Text(strongText(text), style = MaterialTheme.typography.bodySmall, color = color, modifier = Modifier.weight(1f))
    }
}

/**
 * 「标签 / 值」一行。标签最多占整行的 3/5、超出就在自己那一栏里换行：数据来源这类长标签
 * （「ELDEN RING NIGHTREIGN 游戏内文本 FMG（简体中文 / 英文）」）不设上限时会把值挤成一字一行。
 */
@Composable
internal fun BossDetailLine(label: String, value: String, valueColor: Color = NightColors.TextPrimary) {
    Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        Text(
            label,
            modifier = Modifier.maxWidthFraction(0.6f),
            style = MaterialTheme.typography.bodySmall,
            color = NightColors.TextSecondary,
        )
        Text(
            value,
            modifier = Modifier.weight(1f),
            style = MaterialTheme.typography.bodySmall,
            color = valueColor,
            textAlign = TextAlign.End,
            fontWeight = FontWeight.Medium,
        )
    }
}

/** 宽度不超过父级给的最大宽度的 [fraction]（Row 里不带 weight 的子项拿到的最大宽度就是整行剩余宽度）。 */
private fun Modifier.maxWidthFraction(fraction: Float): Modifier = layout { measurable, constraints ->
    val cap = if (constraints.hasBoundedWidth) (constraints.maxWidth * fraction).toInt() else constraints.maxWidth
    val placeable = measurable.measure(constraints.copy(minWidth = 0, maxWidth = cap))
    layout(placeable.width, placeable.height) { placeable.place(0, 0) }
}

/** 带浅色底的说明块。 */
@Composable
internal fun BossNoteBox(
    modifier: Modifier = Modifier,
    tint: Color = Color.White,
    alpha: Float = 0.03f,
    content: @Composable ColumnScope.() -> Unit,
) {
    Column(
        modifier = modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(10.dp))
            .background(tint.copy(alpha = alpha))
            .padding(10.dp),
        verticalArrangement = Arrangement.spacedBy(5.dp),
        content = content,
    )
}

/** 展开 / 折叠的小箭头。 */
@Composable
internal fun Chevron(open: Boolean, modifier: Modifier = Modifier) {
    Text(
        "›",
        modifier = modifier.rotate(if (open) 90f else 0f),
        style = MaterialTheme.typography.titleMedium,
        color = NightColors.TextMuted,
    )
}

/** 工具条上的一枚可点的筛选药丸：视觉高 34dp，触控区 48dp。 */
@Composable
internal fun BossToolbarChip(
    text: String,
    selected: Boolean,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    color: Color = NightColors.PurpleSoft,
    count: Int? = null,
    leading: (@Composable RowScope.() -> Unit)? = null,
) {
    val shape = RoundedCornerShape(999.dp)
    Box(
        modifier = modifier
            .heightIn(min = 48.dp)
            .clip(shape)
            .clickable(role = Role.Button, onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        Row(
            modifier = Modifier
                .heightIn(min = 34.dp)
                .clip(shape)
                .background(if (selected) color.copy(alpha = 0.18f) else NightColors.FieldSoft)
                .border(1.dp, if (selected) color.copy(alpha = 0.55f) else NightColors.Border, shape)
                .padding(horizontal = 12.dp, vertical = 6.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            leading?.invoke(this)
            Text(
                text,
                style = MaterialTheme.typography.labelLarge,
                color = if (selected) NightColors.TextPrimary else NightColors.TextSecondary,
                fontWeight = if (selected) FontWeight.SemiBold else FontWeight.Medium,
                maxLines = 1,
            )
            if (count != null) {
                Text(
                    count.toString(),
                    style = MaterialTheme.typography.labelSmall.tabular(),
                    color = when {
                        count == 0 -> NightColors.TextMuted
                        selected -> color
                        else -> NightColors.TextSecondary
                    },
                    maxLines = 1,
                )
            }
        }
    }
}

/** 开关小圆点（「显示隐藏实体」药丸前面）。 */
@Composable
internal fun SwitchDot(on: Boolean) {
    Box(
        modifier = Modifier
            .size(width = 22.dp, height = 13.dp)
            .clip(RoundedCornerShape(99.dp))
            .background(if (on) NightColors.Purple else NightColors.Border),
        contentAlignment = if (on) Alignment.CenterEnd else Alignment.CenterStart,
    ) {
        Box(Modifier.padding(horizontal = 2.dp).size(9.dp).background(NightColors.TextPrimary, CircleShape))
    }
}
