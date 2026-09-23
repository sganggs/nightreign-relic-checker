@file:OptIn(ExperimentalLayoutApi::class)

package com.nightreign.relicchecker.ui.ranker

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.nightreign.relicchecker.gamedata.ranker.BuffFormat
import com.nightreign.relicchecker.gamedata.ranker.EntryState
import com.nightreign.relicchecker.gamedata.ranker.EvaluatedEntry
import com.nightreign.relicchecker.gamedata.ranker.RankerText
import com.nightreign.relicchecker.gamedata.ranker.SkillDataset
import com.nightreign.relicchecker.gamedata.ranker.SummaryColumn
import com.nightreign.relicchecker.ui.NightPill
import com.nightreign.relicchecker.ui.theme.NightColors
import kotlinx.coroutines.CoroutineScope

// ⑦ 汇总（卡片 + 粘在底部的总倍率条）与 ⑧ 说明与已知局限。

@Composable
internal fun SummaryCard(state: RankerPageState, expanded: Boolean, onToggle: () -> Unit, scope: CoroutineScope) {
    val result = state.evaluation
    val total = result.totalMultiplier
    val hasComposition = state.hasComposition
    RankerSectionCard(
        title = RankerText.t("summaryHeading"),
        subtitle = RankerText.t("summaryColumnNote"),
        summary = RankerText.t("summaryTotal") + " " + mul(total) + " · " + RankerText.t("summaryGain") + " " + BuffFormat.gain(total),
        expanded = expanded,
        onToggle = onToggle,
        accent = NightColors.Green,
    ) {
        Row(
            modifier = Modifier.fillMaxWidth().semantics { liveRegion = LiveRegionMode.Polite },
            verticalAlignment = Alignment.Bottom,
            horizontalArrangement = Arrangement.spacedBy(18.dp),
        ) {
            Column {
                Text(RankerText.t("summaryTotal"), style = MaterialTheme.typography.labelSmall, color = NightColors.TextMuted)
                Text(
                    mul(total),
                    style = MaterialTheme.typography.headlineSmall,
                    color = if ((total ?: 1.0) > 1.0000001) NightColors.Green else NightColors.TextSecondary,
                )
            }
            Column {
                Text(RankerText.t("summaryGain"), style = MaterialTheme.typography.labelSmall, color = NightColors.TextMuted)
                Text(BuffFormat.gain(total), style = MaterialTheme.typography.titleMedium, color = NightColors.TextSecondary)
            }
        }
        Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
            SummaryColumn.entries.forEach { column ->
                val one = result.column(column)
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Box(Modifier.size(width = 4.dp, height = 16.dp).background(RankerPalette.column(column), RoundedCornerShape(2.dp)))
                    Spacer(Modifier.width(8.dp))
                    Text(
                        column.titleZh + " · " + columnSlotText(state, column),
                        style = MaterialTheme.typography.bodyMedium,
                        color = NightColors.TextSecondary,
                        modifier = Modifier.weight(1f),
                    )
                    Text(mul(one.multiplier), style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.SemiBold, color = NightColors.TextPrimary)
                }
            }
            if (BuffFormat.hasFlat(result.total.flat)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(RankerText.t("summaryFlat"), style = MaterialTheme.typography.bodyMedium, color = NightColors.Amber, modifier = Modifier.weight(1f))
                    Text(BuffFormat.flat(result.total.flat), style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.SemiBold, color = NightColors.Amber)
                }
            }
        }
        RankerNote(RankerText.t("summarySubtotals"))
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            RankerButton(
                RankerText.t("fillButton"),
                onClick = { state.fill(scope) },
                primary = true,
                enabled = hasComposition && !state.filling,
                modifier = Modifier.weight(1f),
            )
            RankerButton(RankerText.t("clearButton"), onClick = { state.clear() }, modifier = Modifier.weight(1f))
        }
        RankerNote(RankerText.t("fillNote"))
        RankerSwitchRow(
            text = RankerText.t("showInactive"),
            checked = state.showInactive,
            onCheckedChange = { state.updateShowInactive(it) },
            detail = RankerText.t("showInactiveHelp"),
        )
        state.notice?.let { RankerMessage(it, NightColors.Green) }
        if (!hasComposition) RankerMessage(RankerText.t("summaryNoComposition"), NightColors.Amber)
        result.violations.forEach { RankerMessage(it, NightColors.Red) }
        result.warnings.forEach { RankerMessage(it.text, NightColors.Amber) }
        if (BuffFormat.hasFlat(result.total.flat)) RankerNote(RankerText.t("summaryFlatNote"))
    }
}

/** 汇总清单的小标题（可点开合）。 */
@Composable
internal fun SummaryListLabel(text: String, open: Boolean, onToggle: () -> Unit) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .heightIn(min = 44.dp)
            .clip(RoundedCornerShape(10.dp))
            .clickable(role = Role.Button, onClick = onToggle)
            .padding(horizontal = 6.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Chevron(open)
        Spacer(Modifier.width(8.dp))
        Text(text, style = MaterialTheme.typography.labelLarge, fontWeight = FontWeight.SemiBold, color = NightColors.TextPrimary)
    }
}

/** 汇总里的一条：名称、来源与互斥键、状态、贡献倍率、原因与说明、条件控件与移除按钮。 */
@Composable
internal fun SummaryRowItem(state: RankerPageState, item: EvaluatedEntry) {
    val entry = item.entry
    val inactive = item.state == EntryState.NO || item.state == EntryState.CONTEXT
    RankerRowPanel(dimmed = inactive) {
        Row(verticalAlignment = Alignment.Top) {
            Box(
                Modifier
                    .padding(top = 3.dp)
                    .size(width = 4.dp, height = 28.dp)
                    .background(RankerPalette.column(item.column), RoundedCornerShape(2.dp)),
            )
            Spacer(Modifier.width(10.dp))
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(
                    entry.name,
                    style = MaterialTheme.typography.bodyMedium,
                    fontWeight = FontWeight.SemiBold,
                    color = if (item.isCounted) NightColors.TextPrimary else NightColors.TextSecondary,
                    maxLines = 3,
                    overflow = TextOverflow.Ellipsis,
                )
                Text(
                    item.labels.joinToString("、") + " · " + entry.key,
                    style = MaterialTheme.typography.labelSmall,
                    color = NightColors.TextMuted,
                )
            }
            Spacer(Modifier.width(8.dp))
            Column(horizontalAlignment = Alignment.End, verticalArrangement = Arrangement.spacedBy(4.dp)) {
                RankerStatePill(item.state)
                RankerScore(item.multiplier, item.isCounted, item.multiplier != null, flat = item.flat)
            }
        }
        if (!item.isCounted && item.reasons.isNotEmpty()) {
            Text(item.reasons.joinToString("；"), style = MaterialTheme.typography.bodySmall, color = NightColors.Amber)
        }
        if (item.notes.isNotEmpty()) RankerNote(item.notes.joinToString("；"))
        ItemControls(state, item)
        FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            item.keys.forEachIndexed { position, key ->
                val action = RankerText.t(if (key.startsWith("innate:")) "innateRemove" else "summaryRemove")
                val label = item.labels.getOrNull(position) ?: item.labels.firstOrNull()
                RankerButton(
                    text = if (label.isNullOrEmpty() || item.keys.size == 1) action else "$action · $label",
                    onClick = { state.removeSource(key) },
                    height = 36.dp,
                )
            }
        }
    }
}

/** 粘在底部的总倍率条：总倍率与相对提升、槽位用量、「按推荐填满」与「汇总」（滚到汇总卡片）。 */
@Composable
internal fun RankerSummaryBar(state: RankerPageState, onFill: () -> Unit, onShowSummary: () -> Unit) {
    val total = state.evaluation.totalMultiplier
    Surface(color = NightColors.Elevated, tonalElevation = 0.dp, shadowElevation = 0.dp) {
        Column(Modifier.fillMaxWidth()) {
            HorizontalDivider(color = NightColors.Border)
            Row(
                modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                Column(
                    modifier = Modifier
                        .weight(1f)
                        .clip(RoundedCornerShape(10.dp))
                        .clickable(role = Role.Button, onClickLabel = RankerText.t("summaryHeading"), onClick = onShowSummary)
                        .semantics { liveRegion = LiveRegionMode.Polite },
                ) {
                    Text(RankerText.t("summaryTotal"), style = MaterialTheme.typography.labelSmall, color = NightColors.TextMuted)
                    Row(verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        Text(
                            mul(total),
                            style = MaterialTheme.typography.titleLarge,
                            color = if ((total ?: 1.0) > 1.0000001) NightColors.Green else NightColors.TextSecondary,
                            maxLines = 1,
                        )
                        Text(BuffFormat.gain(total), style = MaterialTheme.typography.bodySmall, color = NightColors.TextMuted, maxLines = 1)
                    }
                    Text(
                        usagePills(state).joinToString(" · ") { it.first },
                        style = MaterialTheme.typography.labelSmall,
                        color = NightColors.TextMuted,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                }
                RankerButton(
                    RankerText.t("fillButton"),
                    onClick = onFill,
                    primary = true,
                    enabled = state.hasComposition && !state.filling,
                )
                RankerButton(RankerText.t("summaryHeading"), onClick = onShowSummary)
            }
        }
    }
}

// ============================================================ ⑧ 说明与已知局限

@Composable
internal fun NotesHeader(state: RankerPageState, expanded: Boolean, onToggle: () -> Unit) {
    RankerSectionCard(
        title = RankerText.t("briefHeading"),
        subtitle = RankerText.t("briefIntro"),
        expanded = expanded,
        onToggle = onToggle,
        accent = NightColors.TextSecondary,
    ) {
        // 「相对构成不是绝对伤害」：数据集没有强化倍率与能力值补正曲线（usage「本数据集的边界」）。
        Text(
            androidx.compose.ui.text.buildAnnotatedString {
                append(RankerStrings.COMP_NOTE_PREFIX)
                pushStyle(androidx.compose.ui.text.SpanStyle(fontWeight = FontWeight.SemiBold))
                append(RankerStrings.COMP_NOTE_STRONG)
                pop()
                append(RankerStrings.COMP_NOTE_SUFFIX)
            },
            style = MaterialTheme.typography.bodySmall,
            color = NightColors.Amber,
        )
        state.skills.dataset.usage[SkillDataset.USAGE_BOUNDARY]?.let { boundary ->
            Column(
                Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(10.dp))
                    .background(NightColors.Field)
                    .border(1.dp, NightColors.Border, RoundedCornerShape(10.dp))
                    .padding(10.dp),
                verticalArrangement = Arrangement.spacedBy(4.dp),
            ) {
                Text(RankerStrings.BOUNDARY_LABEL, style = MaterialTheme.typography.labelSmall, color = NightColors.PurpleSoft)
                Text(strongText(boundary), style = MaterialTheme.typography.bodySmall, color = NightColors.TextSecondary)
            }
        }
    }
}

/** 说明区的一个折叠块标题。 */
@Composable
internal fun NoteBlockHeader(title: String, pill: String?, open: Boolean, onToggle: () -> Unit) {
    val shape = RoundedCornerShape(12.dp)
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .heightIn(min = 48.dp)
            .clip(shape)
            .background(NightColors.Card)
            .border(1.dp, NightColors.Border, shape)
            .clickable(role = Role.Button, onClick = onToggle)
            .padding(horizontal = 12.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Chevron(open)
        Spacer(Modifier.width(8.dp))
        Text(title, style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.SemiBold, color = NightColors.TextPrimary, modifier = Modifier.weight(1f))
        pill?.let { NightPill(it, NightColors.TextMuted) }
    }
}

/** 说明区的一段正文（数据集原文的粗体标记照样加粗）。 */
@Composable
internal fun NoteBody(title: String?, text: String, bullet: Boolean) {
    Column(
        Modifier.fillMaxWidth().padding(start = 12.dp, end = 6.dp),
        verticalArrangement = Arrangement.spacedBy(2.dp),
    ) {
        title?.let { Text(it, style = MaterialTheme.typography.labelMedium, fontWeight = FontWeight.SemiBold, color = NightColors.PurpleSoft) }
        Row {
            if (bullet) Text("·", style = MaterialTheme.typography.bodySmall, color = NightColors.TextMuted, modifier = Modifier.width(12.dp))
            Text(strongText(text), style = MaterialTheme.typography.bodySmall, color = NightColors.TextSecondary, modifier = Modifier.weight(1f))
        }
    }
}
