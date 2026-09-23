package com.nightreign.relicchecker.ui.heroes

import androidx.compose.foundation.ScrollState
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.nightreign.relicchecker.gamedata.heroes.HeroComparisonColumn
import com.nightreign.relicchecker.gamedata.heroes.HeroComparisonRow
import com.nightreign.relicchecker.gamedata.heroes.HeroDeltaTone
import com.nightreign.relicchecker.gamedata.heroes.HeroStatNames
import com.nightreign.relicchecker.gamedata.heroes.HeroStatsCopy
import com.nightreign.relicchecker.gamedata.heroes.HeroStatsSnapshot
import com.nightreign.relicchecker.gamedata.heroes.HeroStatsText
import com.nightreign.relicchecker.ui.theme.NightColors

// 「角色属性」页的两张横向可滚表：全部等级表（1 … 数据集声明的最大等级）与同级对比表。
// 首列（等级 / 角色）固定，其余列放进 Row(horizontalScroll)；表头与各行共用同一个 ScrollState，
// 横向同步滚动。缺数据一律破折号，数字等宽右对齐；「负重上限」列头带 * 注记（遗留列）。

private object HeroTableMetrics {
    val LevelColumn: Dp = 50.dp
    val StatColumn: Dp = 62.dp
    val DerivedColumn: Dp = 80.dp
    val NoteColumn: Dp = 220.dp
    val HeroColumn: Dp = 92.dp
    val CompareStatColumn: Dp = 56.dp
    val CompareDerivedColumn: Dp = 76.dp
    val ColumnGap: Dp = 12.dp
}

@Composable
private fun HeaderCell(title: String, width: Dp, alignEnd: Boolean = true, color: Color = NightColors.TextMuted) {
    Box(
        modifier = Modifier.width(width).heightIn(min = 36.dp),
        contentAlignment = if (alignEnd) Alignment.CenterEnd else Alignment.CenterStart,
    ) {
        Text(title, style = MaterialTheme.typography.labelMedium, color = color, maxLines = 1)
    }
}

// ---------------------------------------------------------------- 全部等级表

@Composable
internal fun LevelTableHeader(names: HeroStatNames, scroll: ScrollState) {
    Column(modifier = Modifier.fillMaxWidth().background(NightColors.Background)) {
        Row(modifier = Modifier.fillMaxWidth().padding(vertical = 2.dp), verticalAlignment = Alignment.CenterVertically) {
            Box(
                modifier = Modifier.width(HeroTableMetrics.LevelColumn).heightIn(min = 36.dp).padding(start = 8.dp),
                contentAlignment = Alignment.CenterStart,
            ) {
                Text("等级", style = MaterialTheme.typography.labelMedium, color = NightColors.TextMuted, maxLines = 1)
            }
            Row(modifier = Modifier.weight(1f).horizontalScroll(scroll), verticalAlignment = Alignment.CenterVertically) {
                names.attributeKeys.forEach { HeaderCell(names.attributeTitle(it), HeroTableMetrics.StatColumn) }
                names.derivedKeys.forEach { HeaderCell(names.derivedHeader(it), HeroTableMetrics.DerivedColumn) }
                Spacer(Modifier.width(HeroTableMetrics.ColumnGap))
                HeaderCell("说明", HeroTableMetrics.NoteColumn, alignEnd = false)
            }
        }
        HorizontalDivider(color = NightColors.Border)
    }
}

@Composable
internal fun LevelTableRow(
    snapshot: HeroStatsSnapshot,
    names: HeroStatNames,
    showSource: Boolean,
    isCurrent: Boolean,
    scroll: ScrollState,
    onClick: () -> Unit,
) {
    val shape = RoundedCornerShape(8.dp)
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 1.dp)
            .heightIn(min = 48.dp) // 整行可点：触控目标不小于 48dp
            .clip(shape)
            .background(if (snapshot.isAnchorLevel) NightColors.Purple.copy(alpha = .10f) else Color.Transparent)
            .then(if (isCurrent) Modifier.border(1.dp, NightColors.PurpleSoft.copy(alpha = .45f), shape) else Modifier)
            .clickable(onClickLabel = "切到 ${snapshot.level} 级", onClick = onClick),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Row(
            modifier = Modifier.width(HeroTableMetrics.LevelColumn).padding(start = 8.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(4.dp),
        ) {
            Text(
                snapshot.level.toString(),
                style = MaterialTheme.typography.bodyMedium.tabular(),
                fontWeight = if (snapshot.isAnchorLevel) FontWeight.Bold else FontWeight.Medium,
                color = if (snapshot.isAnchorLevel) NightColors.PurpleSoft else NightColors.TextPrimary,
            )
            if (isCurrent) Box(Modifier.size(5.dp).background(NightColors.PurpleSoft, CircleShape))
        }
        Row(modifier = Modifier.weight(1f).horizontalScroll(scroll), verticalAlignment = Alignment.CenterVertically) {
            names.attributeKeys.forEach { AttributeCell(snapshot, it) }
            names.orderedDerived.forEach { DerivedCell(snapshot, it.key, it.integer) }
            Spacer(Modifier.width(HeroTableMetrics.ColumnGap))
            NoteCell(snapshot, showSource)
        }
    }
}

/** 属性格：最终值 + 生效增减量；被钳的格子带「钳」角标（读屏写「原为 N，已钳到最低 1」）。 */
@Composable
private fun AttributeCell(snapshot: HeroStatsSnapshot, key: String) {
    val delta = snapshot.effectiveDelta(key)?.takeIf { it != 0 }
    val changed = delta != null
    val tone = HeroPalette.tone(HeroDeltaTone.of(delta ?: 0))
    val clampedFrom = snapshot.clampedFrom[key]
    Row(
        modifier = Modifier.width(HeroTableMetrics.StatColumn),
        horizontalArrangement = Arrangement.End,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            HeroStatsText.statText(snapshot.finalStats[key]),
            style = MaterialTheme.typography.bodyMedium.tabular(),
            fontWeight = if (changed) FontWeight.Bold else FontWeight.Medium,
            color = if (changed) tone else NightColors.TextPrimary,
            maxLines = 1,
        )
        if (delta != null) {
            Text(
                HeroStatsText.signed(delta),
                style = MaterialTheme.typography.labelSmall.tabular(),
                color = tone,
                maxLines = 1,
                modifier = Modifier.padding(start = 2.dp),
            )
        }
        if (clampedFrom != null) {
            Text(
                HeroStatsCopy.CLAMP_CELL_TAG,
                style = MaterialTheme.typography.labelSmall,
                fontWeight = FontWeight.Bold,
                color = NightColors.Red,
                modifier = Modifier
                    .padding(start = 2.dp)
                    .semantics { contentDescription = HeroStatsCopy.clampedFromNote(clampedFrom) },
            )
        }
    }
}

@Composable
private fun DerivedCell(snapshot: HeroStatsSnapshot, key: String, integer: Boolean) {
    val delta = snapshot.derivedDelta(key)
    val toneKind = HeroDeltaTone.of(delta ?: 0.0)
    val changed = toneKind != HeroDeltaTone.FLAT
    val tone = HeroPalette.tone(toneKind)
    Row(
        modifier = Modifier.width(HeroTableMetrics.DerivedColumn),
        horizontalArrangement = Arrangement.End,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            HeroStatsText.derivedText(snapshot.finalDerived[key], integer),
            style = MaterialTheme.typography.bodyMedium.tabular(),
            fontWeight = if (changed) FontWeight.Bold else FontWeight.Medium,
            color = if (changed) tone else NightColors.TextSecondary,
            maxLines = 1,
        )
        if (changed) {
            Text(
                HeroStatsText.signed(delta ?: 0.0, if (integer) 0 else 1),
                style = MaterialTheme.typography.labelSmall.tabular(),
                color = tone,
                maxLines = 1,
                modifier = Modifier.padding(start = 2.dp),
            )
        }
    }
}

/** 说明列：基础表是否锚点 · 勾了词条时的增减量来源 · 是否有属性被钳（三端同一串文案）。 */
@Composable
private fun NoteCell(snapshot: HeroStatsSnapshot, showSource: Boolean) {
    val text = buildAnnotatedString {
        withStyle(SpanStyle(color = if (snapshot.isAnchorLevel) NightColors.PurpleSoft else NightColors.TextMuted)) {
            append(if (snapshot.isAnchorLevel) HeroStatsCopy.BASE_ANCHOR_TAG else HeroStatsCopy.BASE_INTERPOLATED_TAG)
        }
        val source = snapshot.modifierSource
        if (showSource && source != null) {
            withStyle(SpanStyle(color = NightColors.TextMuted)) { append(" · ") }
            withStyle(SpanStyle(color = HeroPalette.source(source.source))) { append(source.label) }
        }
        if (snapshot.clampedStats.isNotEmpty()) {
            withStyle(SpanStyle(color = NightColors.TextMuted)) { append(" · ") }
            withStyle(SpanStyle(color = NightColors.Red, fontWeight = FontWeight.SemiBold)) { append(HeroStatsCopy.CLAMP_ROW_TAG) }
        }
    }
    Text(
        text,
        style = MaterialTheme.typography.labelSmall,
        maxLines = 2,
        overflow = TextOverflow.Ellipsis,
        modifier = Modifier.width(HeroTableMetrics.NoteColumn).padding(end = 8.dp),
    )
}

// ---------------------------------------------------------------- 同级对比表

@Composable
internal fun CompareTableHeader(
    names: HeroStatNames,
    column: HeroComparisonColumn,
    ascending: Boolean,
    scroll: ScrollState,
    onSort: (HeroComparisonColumn) -> Unit,
) {
    Column(modifier = Modifier.fillMaxWidth().background(NightColors.Background)) {
        Row(modifier = Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            SortHeaderCell(
                title = "角色",
                width = HeroTableMetrics.HeroColumn,
                alignEnd = false,
                active = column == HeroComparisonColumn.Hero,
                ascending = ascending,
                startPadding = 8.dp,
            ) { onSort(HeroComparisonColumn.Hero) }
            Row(modifier = Modifier.weight(1f).horizontalScroll(scroll), verticalAlignment = Alignment.CenterVertically) {
                names.attributeKeys.forEach { key ->
                    val target = HeroComparisonColumn.Stat(key)
                    SortHeaderCell(names.attributeTitle(key), HeroTableMetrics.CompareStatColumn, true, column == target, ascending) { onSort(target) }
                }
                names.derivedKeys.forEach { key ->
                    val target = HeroComparisonColumn.Derived(key)
                    SortHeaderCell(names.derivedHeader(key), HeroTableMetrics.CompareDerivedColumn, true, column == target, ascending) { onSort(target) }
                }
                Spacer(Modifier.width(8.dp))
            }
        }
        HorizontalDivider(color = NightColors.Border)
    }
}

@Composable
private fun SortHeaderCell(
    title: String,
    width: Dp,
    alignEnd: Boolean,
    active: Boolean,
    ascending: Boolean,
    startPadding: Dp = 0.dp,
    onClick: () -> Unit,
) {
    val arrow = if (!active) "" else if (ascending) "↑" else "↓"
    Box(
        modifier = Modifier
            .width(width)
            .heightIn(min = 48.dp) // 列宽 ≥ 56dp、行高 48dp：排序表头的触控目标不小于 48dp
            .clickable(role = Role.Button, onClickLabel = "按「$title」排序", onClick = onClick)
            .padding(start = startPadding),
        contentAlignment = if (alignEnd) Alignment.CenterEnd else Alignment.CenterStart,
    ) {
        Text(
            title + arrow,
            style = MaterialTheme.typography.labelMedium,
            fontWeight = if (active) FontWeight.SemiBold else FontWeight.Medium,
            color = if (active) NightColors.PurpleSoft else NightColors.TextMuted,
            maxLines = 1,
        )
    }
}

@Composable
internal fun CompareTableRow(
    row: HeroComparisonRow,
    names: HeroStatNames,
    maxima: Map<HeroComparisonColumn, Double>,
    isCurrent: Boolean,
    scroll: ScrollState,
    onClick: () -> Unit,
) {
    val shape = RoundedCornerShape(8.dp)
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 1.dp)
            .heightIn(min = 48.dp)
            .clip(shape)
            .background(if (isCurrent) NightColors.Purple.copy(alpha = .10f) else Color.Transparent)
            .clickable(onClickLabel = "查看${row.nameZh.ifEmpty { row.nameEn }}", onClick = onClick),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(modifier = Modifier.width(HeroTableMetrics.HeroColumn).padding(start = 8.dp)) {
            Text(
                row.nameZh.ifEmpty { row.nameEn },
                style = MaterialTheme.typography.bodyMedium,
                fontWeight = FontWeight.SemiBold,
                color = NightColors.TextPrimary,
                maxLines = 1,
            )
            Text(row.nameEn, style = MaterialTheme.typography.labelSmall, color = NightColors.TextMuted, maxLines = 1)
        }
        Row(modifier = Modifier.weight(1f).horizontalScroll(scroll), verticalAlignment = Alignment.CenterVertically) {
            names.attributeKeys.forEach { key ->
                val value = row.stats[key]
                val best = value != null && maxima[HeroComparisonColumn.Stat(key)] == value.toDouble()
                ValueCell(HeroStatsText.statText(value), HeroTableMetrics.CompareStatColumn, best, NightColors.TextPrimary)
            }
            names.orderedDerived.forEach { entry ->
                val value = row.derived[entry.key]
                val best = value != null && maxima[HeroComparisonColumn.Derived(entry.key)] == value
                ValueCell(HeroStatsText.derivedText(value, entry.integer), HeroTableMetrics.CompareDerivedColumn, best, NightColors.TextSecondary)
            }
            Spacer(Modifier.width(8.dp))
        }
    }
}

@Composable
private fun ValueCell(text: String, width: Dp, best: Boolean, color: Color) {
    Box(modifier = Modifier.width(width), contentAlignment = Alignment.CenterEnd) {
        Text(
            text,
            style = MaterialTheme.typography.bodyMedium.tabular(),
            fontWeight = if (best) FontWeight.Bold else FontWeight.Medium,
            color = if (best) NightColors.Green else color,
            maxLines = 1,
        )
    }
}
