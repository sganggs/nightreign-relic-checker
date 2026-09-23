package com.nightreign.relicchecker.ui.ranker

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.nightreign.relicchecker.gamedata.ranker.EntryState
import com.nightreign.relicchecker.gamedata.ranker.FixedRelicRow
import com.nightreign.relicchecker.gamedata.ranker.RankerText
import com.nightreign.relicchecker.gamedata.ranker.RelicAffixRow
import com.nightreign.relicchecker.gamedata.ranker.RelicCard
import com.nightreign.relicchecker.gamedata.ranker.RelicCardType
import com.nightreign.relicchecker.gamedata.ranker.RelicCheck
import com.nightreign.relicchecker.gamedata.ranker.RelicCheckStatus
import com.nightreign.relicchecker.gamedata.ranker.RelicIssue
import com.nightreign.relicchecker.gamedata.ranker.RelicKind
import com.nightreign.relicchecker.gamedata.ranker.RunMode
import com.nightreign.relicchecker.gamedata.ranker.SummaryColumn
import com.nightreign.relicchecker.rules.Affix
import com.nightreign.relicchecker.rules.foldedForSearch
import com.nightreign.relicchecker.rules.matchesSearch
import com.nightreign.relicchecker.ui.NightPill
import com.nightreign.relicchecker.ui.NightSearchField
import com.nightreign.relicchecker.ui.NightSegmentedControl
import com.nightreign.relicchecker.ui.theme.NightColors
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

// ④ 遗物：常规 3 张、深夜 6 张遗物卡。每张「空 / 固定遗物 / 自组」三选一：固定遗物整件从底部抽屉选入；
// 自组三行词条各从底部抽屉选（普通遗物格按「普通 1.03」、深夜遗物格按「深夜正面」口径），实时检查合法性，
// 需诅咒的词条自动配诅咒（可改）；卡片下列出逐条计入情况，叠层（封印监牢、黑夜入侵者）就地填层数、超限就地提示。

@Composable
internal fun RelicHeader(state: RankerPageState, expanded: Boolean, onToggle: () -> Unit) {
    val used = state.evaluation.slots.relic
    RankerSectionCard(
        title = SummaryColumn.RELIC.titleZh,
        subtitle = RankerText.f("relicIntro", state.caps.relicNormal, state.index.caps(RunMode.DEEP).relicDeep),
        summary = "${used.used} / ${used.cap}",
        expanded = expanded,
        onToggle = onToggle,
        accent = RankerPalette.column(SummaryColumn.RELIC),
    ) {
        RankerPills(listOf("${used.used} / ${used.cap}" to RankerPalette.Blue))
        if (!state.index.catalog.available) RankerMessage(RankerText.t("relicNoCatalog"), NightColors.Amber)
    }
}

private fun statusColor(status: RelicCheckStatus) = when (status) {
    RelicCheckStatus.VALID, RelicCheckStatus.FIXED -> NightColors.Green
    RelicCheckStatus.PARTIAL -> RankerPalette.Blue
    RelicCheckStatus.INVALID -> NightColors.Red
    RelicCheckStatus.EMPTY -> NightColors.TextMuted
}

@Composable
internal fun RelicCardItem(state: RankerPageState, cardIndex: Int, openSheet: (RankerSheet) -> Unit) {
    val caps = state.caps
    val kind = caps.relicKind(cardIndex)
    val deep = kind == RelicKind.DEEP
    val card = state.config.relic(cardIndex)
    val check = state.evaluation.relicChecks.getOrNull(cardIndex) ?: RelicCheck.EMPTY
    val border = when {
        check.isInvalid -> NightColors.Red.copy(alpha = .6f)
        card.isFilled -> NightColors.Purple.copy(alpha = .38f)
        else -> null
    }
    RankerRowPanel(selected = card.isFilled, borderColor = border) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(
                caps.relicCardLabel(cardIndex),
                style = MaterialTheme.typography.titleMedium,
                color = if (deep) RankerPalette.DeepBlue else NightColors.TextPrimary,
                modifier = Modifier.weight(1f),
            )
            if (card.type != RelicCardType.EMPTY && check.status != RelicCheckStatus.EMPTY) {
                NightPill(check.status.titleZh, statusColor(check.status))
            }
        }
        NightSegmentedControl(
            items = RelicCardType.entries.map { it.titleZh },
            selectedIndex = RelicCardType.entries.indexOf(card.type),
            onSelect = { position ->
                val type = RelicCardType.entries[position]
                val changed = type != card.type
                state.setRelicType(cardIndex, type)
                if (changed && type == RelicCardType.FIXED) openSheet(RankerSheet.Fixed(cardIndex))
            },
            height = 40.dp,
        )
        when (card.type) {
            RelicCardType.FIXED -> FixedRelicBody(state, cardIndex, card, deep, openSheet)
            RelicCardType.CUSTOM -> CustomRelicBody(state, cardIndex, card, deep, check, openSheet)
            RelicCardType.EMPTY -> Unit
        }
    }
}

@Composable
private fun FixedRelicBody(state: RankerPageState, cardIndex: Int, card: RelicCard, deep: Boolean, openSheet: (RankerSheet) -> Unit) {
    val index = state.index
    val fixed = card.fixedKey?.let { index.fixedRelicByKey[it] }
    if (index.fixedRelics.none { it.isDeepRelic == deep }) {
        RankerNote(RankerText.t("relicFixedNone"))
        return
    }
    RankerPickerField(
        text = fixed?.nameZh ?: RankerText.t("relicFixedPlaceholder"),
        subtitle = fixed?.subtitle,
        placeholder = fixed == null,
        onClick = { openSheet(RankerSheet.Fixed(cardIndex)) },
    )
    if (fixed == null) return
    RankerFieldLabel(RankerText.t("relicEffectsLabel"))
    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
        fixed.effectLines.forEach { line ->
            Row(verticalAlignment = Alignment.Top) {
                Text(
                    if (line.counted) "✓" else "－",
                    style = MaterialTheme.typography.bodySmall,
                    color = if (line.counted) NightColors.Green else NightColors.TextMuted,
                    modifier = Modifier.width(18.dp),
                )
                Text(
                    line.text + if (line.counted) "" else "　" + RankerText.t("relicNonDamage"),
                    style = MaterialTheme.typography.bodySmall,
                    color = if (line.counted) NightColors.TextPrimary else NightColors.TextMuted,
                    modifier = Modifier.weight(1f),
                )
            }
        }
    }
    ItemLines(state, state.itemsFrom("relic:$cardIndex"), label = RankerText.t("relicCountedLabel"))
}

@Composable
private fun CustomRelicBody(
    state: RankerPageState,
    cardIndex: Int,
    card: RelicCard,
    deep: Boolean,
    check: RelicCheck,
    openSheet: (RankerSheet) -> Unit,
) {
    val catalog = state.index.catalog
    if (!catalog.available) {
        RankerMessage(RankerText.t("relicNoCatalog"), NightColors.Amber)
        return
    }
    for (row in 0 until RelicCard.ROWS) {
        val affixId = card.affixAt(row)
        val affix = affixId?.let { catalog.byId[it] }
        val curseId = card.curseAt(row)
        val curse = curseId?.let { catalog.byId[it] }
        Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(RankerText.f("relicRowLabel", row + 1), style = MaterialTheme.typography.labelMedium, color = NightColors.TextSecondary, modifier = Modifier.weight(1f))
                if (affix?.requiresCurse == true) NightPill(RankerText.t("badges.requiresCurse"), RankerPalette.badge(RankerText.t("badges.requiresCurse")))
            }
            Row(verticalAlignment = Alignment.CenterVertically) {
                RankerPickerField(
                    text = affix?.name ?: affixId?.let { "#$it" } ?: RankerText.t("relicPickAffix"),
                    subtitle = affix?.let { it.category + " · " + it.effectId },
                    placeholder = affixId == null,
                    onClick = { openSheet(RankerSheet.Affix(cardIndex, row)) },
                    modifier = Modifier.weight(1f),
                )
                if (affixId != null || curseId != null) {
                    RankerClearButton(RankerText.t("relicRemove"), onClick = { state.removeSource("relic:$cardIndex:$row") })
                }
            }
            if (deep && (affix?.requiresCurse == true || curseId != null)) {
                Column(
                    modifier = Modifier
                        .padding(start = 12.dp)
                        .drawBehind {
                            drawLine(
                                NightColors.Red.copy(alpha = .55f),
                                Offset(0f, 0f),
                                Offset(0f, size.height),
                                strokeWidth = 2.dp.toPx(),
                            )
                        }
                        .padding(start = 10.dp),
                    verticalArrangement = Arrangement.spacedBy(3.dp),
                ) {
                    Text(RankerText.t("relicCurseLabel"), style = MaterialTheme.typography.labelSmall, color = NightColors.Red.copy(alpha = .8f))
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        RankerPickerField(
                            text = curse?.name ?: curseId?.let { "#$it" } ?: RankerText.t("relicCursePlaceholder"),
                            color = NightColors.TextSecondary,
                            onClick = { openSheet(RankerSheet.Curse(cardIndex, row)) },
                            modifier = Modifier.weight(1f),
                            subtitle = if (curseId == null) null else RankerText.t("relicCurseNote"),
                        )
                        if (curseId != null) RankerClearButton(RankerText.t("relicRemove"), onClick = { state.setRelicCurse(cardIndex, row, null) })
                    }
                    if (curseId == null) RankerNote(RankerText.t("relicCurseNote"), color = NightColors.Amber)
                }
            }
        }
    }
    if (check.status != RelicCheckStatus.EMPTY) {
        Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
            // 状态药丸已在卡片标题行，这里只写说明
            Text(check.message, style = MaterialTheme.typography.bodySmall, color = statusColor(check.status))
            check.issues.forEach { issue ->
                Text(issueText(issue), style = MaterialTheme.typography.bodySmall, color = NightColors.Red.copy(alpha = .9f))
            }
            check.warnings.forEach { warning ->
                Text(issueText(warning), style = MaterialTheme.typography.bodySmall, color = NightColors.TextMuted)
            }
        }
    }
    if (check.isInvalid) {
        // 整件不计入：这件遗物带进来的条目全部标「遗物不合法」。
        Row(verticalAlignment = Alignment.Top) {
            NightPill(EntryState.RELIC_INVALID.label, NightColors.Red)
            Spacer(Modifier.width(8.dp))
            Text(RankerText.t("reasonRelicInvalid"), style = MaterialTheme.typography.bodySmall, fontWeight = FontWeight.SemiBold, color = NightColors.Red, modifier = Modifier.weight(1f))
        }
    }
    ItemLines(state, state.itemsFrom("relic:$cardIndex"))
}

private fun issueText(issue: RelicIssue): String = "· " + issue.title + if (issue.detail.isNotEmpty()) "：" + issue.detail else ""

// ============================================================ 抽屉：固定遗物 / 自组词条 / 诅咒

@Composable
internal fun FixedRelicSheet(state: RankerPageState, cardIndex: Int, onDone: () -> Unit) {
    val evaluator = state.evaluator
    val config = state.config
    val caps = state.caps
    val kind = caps.relicKind(cardIndex)
    val rows by produceState<List<FixedRelicRow>?>(null, evaluator, config, kind) {
        value = withContext(Dispatchers.Default) { evaluator.fixedRelicRows(config, kind) }
    }
    var query by rememberSaveable(cardIndex) { mutableStateOf("") }
    val card = config.relic(cardIndex)
    val usedElsewhere = (0 until caps.relics).filter { it != cardIndex }
        .mapNotNull { other -> config.relic(other).takeIf { it.type == RelicCardType.FIXED }?.fixedKey }.toSet()
    val needle = query.foldedForSearch()
    val hasComposition = state.hasComposition
    val list = rows?.filter { row ->
        (state.showInactive || row.relic.hasDamage || row.relic.key == card.fixedKey) && row.relic.matches(needle)
    }
    Column(Modifier.fillMaxWidth().padding(horizontal = 16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        RankerSheetHeader(
            title = caps.relicCardLabel(cardIndex) + " · " + RelicCardType.FIXED.titleZh,
            subtitle = RankerText.t("relicFixedPlaceholder"),
            count = list?.let { RankerStrings.countPill(it.size) },
        )
        NightSearchField(query, { query = it }, placeholder = RankerText.t("relicFixedSearch"))
        LazyColumn(Modifier.heightIn(min = 300.dp, max = 590.dp)) {
            when {
                list == null -> item(key = "loading") { RankerNote("…", Modifier.padding(12.dp)) }
                list.isEmpty() -> item(key = "empty") {
                    RankerNote(
                        if (rows.isNullOrEmpty()) RankerText.t("relicFixedNone") else RankerText.t("overviewNoMatch"),
                        Modifier.padding(12.dp),
                    )
                }
            }
            items(list.orEmpty(), key = { it.relic.key }) { row ->
                val relic = row.relic
                val used = relic.key in usedElsewhere
                val score = row.score
                RankerPickRow(
                    title = relic.nameZh + (if (used) RankerText.t("relicFixedUsedElsewhere") else ""),
                    subtitle = relic.subtitle + " · " + relic.effectNames.joinToString("／"),
                    selected = relic.key == card.fixedKey,
                    enabled = !used,
                    dimmed = !score.applicable,
                    onClick = {
                        state.setFixedRelic(cardIndex, relic.key)
                        onDone()
                    },
                    trailing = {
                        RankerScore(score.score, score.state == EntryState.COUNTED, hasComposition, potential = score.potential, oneStack = score.assumesOneStack, flat = score.flat)
                    },
                )
                HorizontalDivider(color = NightColors.Border.copy(alpha = .6f))
            }
        }
        Spacer(Modifier.height(14.dp))
    }
}

/** 自组某一行的一个候选：选上以后这件遗物不合法的第一条原因（含配不上诅咒的「缺少负面词条」）。 */
private class AffixChoice(val row: RelicAffixRow, val blocking: RelicIssue?)

@Composable
internal fun RelicAffixSheet(state: RankerPageState, cardIndex: Int, row: Int, onDone: () -> Unit) {
    val evaluator = state.evaluator
    val config = state.config
    val index = state.index
    val caps = state.caps
    val kind = caps.relicKind(cardIndex)
    val card = config.relic(cardIndex)
    val choices by produceState<List<AffixChoice>?>(null, evaluator, config, cardIndex, row, kind) {
        value = withContext(Dispatchers.Default) {
            evaluator.relicAffixRows(config, kind).map { candidate ->
                // 与点选后的结果同一口径：这一行的旧诅咒清掉、需诅咒的词条自动配诅咒（withRelicAffix）。
                val trial = index.withRelicAffix(card, kind, row, candidate.option.id)
                AffixChoice(candidate, index.checkCustomRelic(trial, kind).issues.firstOrNull())
            }
        }
    }
    var query by rememberSaveable(cardIndex, row) { mutableStateOf("") }
    val chosen = card.affixAt(row)
    val hasComposition = state.hasComposition
    val list = choices?.filter { choice ->
        (state.showInactive || choice.row.score.isUseful(hasComposition) || choice.row.option.id == chosen) &&
            choice.row.option.affix.matchesSearch(query)
    }
    Column(Modifier.fillMaxWidth().padding(horizontal = 16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        RankerSheetHeader(
            title = caps.relicCardLabel(cardIndex) + " · " + RankerText.f("relicRowLabel", row + 1),
            subtitle = RankerText.t("relicAffixPickerHint"),
            count = list?.let { RankerStrings.countPill(it.size) },
        )
        NightSearchField(query, { query = it }, placeholder = RankerText.t("relicSearch"))
        LazyColumn(Modifier.heightIn(min = 300.dp, max = 590.dp)) {
            item(key = "none") {
                RankerPickRow(
                    title = RankerText.t("relicAffixEmpty"),
                    selected = chosen == null,
                    onClick = {
                        state.setRelicAffix(cardIndex, row, null)
                        onDone()
                    },
                )
                HorizontalDivider(color = NightColors.Border.copy(alpha = .6f))
            }
            when {
                list == null -> item(key = "loading") { RankerNote("…", Modifier.padding(12.dp)) }
                list.isEmpty() -> item(key = "empty") { RankerNote(RankerText.t("overviewNoMatch"), Modifier.padding(12.dp)) }
            }
            items(list.orEmpty(), key = { it.row.option.id }) { choice ->
                val option = choice.row.option
                val score = choice.row.score
                RankerPickRow(
                    title = option.name + if (score.applicable) "" else RankerText.t("optionInactive"),
                    subtitle = listOfNotNull(
                        option.affix.category + " · " + option.id,
                        if (option.requiresCurse) RankerText.t("badges.requiresCurse") else null,
                        if (score.applicable) null else score.blockedReason,
                    ).joinToString(" · "),
                    warning = choice.blocking?.let { it.title + "：" + it.detail },
                    selected = option.id == chosen,
                    dimmed = !score.applicable || choice.blocking != null,
                    onClick = {
                        state.setRelicAffix(cardIndex, row, option.id)
                        onDone()
                    },
                    trailing = {
                        RankerScore(score.score, score.state == EntryState.COUNTED, hasComposition, potential = score.potential, oneStack = score.assumesOneStack, flat = score.flat)
                    },
                )
                HorizontalDivider(color = NightColors.Border.copy(alpha = .6f))
            }
        }
        Spacer(Modifier.height(14.dp))
    }
}

@Composable
internal fun CurseSheet(state: RankerPageState, cardIndex: Int, row: Int, onDone: () -> Unit) {
    val index = state.index
    val config = state.config
    val card = config.relic(cardIndex)
    val choices by produceState<List<Pair<Affix, RelicIssue?>>?>(null, config, cardIndex, row) {
        value = withContext(Dispatchers.Default) {
            index.catalog.curses.map { curse ->
                val trial = card.withCurse(row, curse.effectId)
                curse to index.checkCustomRelic(trial, RelicKind.DEEP).issues.firstOrNull { curse.effectId in it.effectIds }
            }
        }
    }
    var query by rememberSaveable(cardIndex, row) { mutableStateOf("") }
    val current = card.curseAt(row)
    val list = choices?.filter { it.first.matchesSearch(query) }
    Column(Modifier.fillMaxWidth().padding(horizontal = 16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        RankerSheetHeader(
            title = state.caps.relicCardLabel(cardIndex) + " · " + RankerText.f("relicRowLabel", row + 1) + " · " + RankerText.t("relicCurseLabel"),
            subtitle = RankerText.t("relicCurseNote"),
            count = list?.let { RankerStrings.countPill(it.size) },
        )
        NightSearchField(query, { query = it }, placeholder = RankerText.t("relicCurseSearch"))
        LazyColumn(Modifier.heightIn(min = 300.dp, max = 590.dp)) {
            item(key = "none") {
                RankerPickRow(
                    title = RankerText.t("relicCursePlaceholder"),
                    selected = current == null,
                    onClick = {
                        state.setRelicCurse(cardIndex, row, null)
                        onDone()
                    },
                )
                HorizontalDivider(color = NightColors.Border.copy(alpha = .6f))
            }
            when {
                list == null -> item(key = "loading") { RankerNote("…", Modifier.padding(12.dp)) }
                list.isEmpty() -> item(key = "empty") { RankerNote(RankerText.t("overviewNoMatch"), Modifier.padding(12.dp)) }
            }
            items(list.orEmpty(), key = { it.first.effectId }) { (curse, issue) ->
                RankerPickRow(
                    title = curse.name,
                    subtitle = RankerText.t("relicCurseNote") + " · #" + curse.effectId,
                    warning = issue?.let { it.title + "：" + it.detail },
                    selected = curse.effectId == current,
                    dimmed = issue != null,
                    onClick = {
                        state.setRelicCurse(cardIndex, row, curse.effectId)
                        onDone()
                    },
                )
                HorizontalDivider(color = NightColors.Border.copy(alpha = .6f))
            }
        }
        Spacer(Modifier.height(14.dp))
    }
}
