package com.nightreign.relicchecker.ui.lookup

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.nightreign.relicchecker.gamedata.lookup.AFFIX_LOOKUP_CONFLICT_LIMIT
import com.nightreign.relicchecker.gamedata.lookup.AFFIX_LOOKUP_ROW_LIMIT
import com.nightreign.relicchecker.gamedata.lookup.AffixConflictBranch
import com.nightreign.relicchecker.gamedata.lookup.AffixLookupIndex
import com.nightreign.relicchecker.gamedata.lookup.AffixLookupReport
import com.nightreign.relicchecker.gamedata.lookup.LookupCopy
import com.nightreign.relicchecker.gamedata.lookup.LookupModeHit
import com.nightreign.relicchecker.gamedata.lookup.LookupPoolHit
import com.nightreign.relicchecker.gamedata.lookup.RelicLookupHit
import com.nightreign.relicchecker.gamedata.lookup.RelicSlotRole
import com.nightreign.relicchecker.gamedata.lookup.affixLookupLoneConflictNote
import com.nightreign.relicchecker.gamedata.lookup.affixLookupShown
import com.nightreign.relicchecker.gamedata.lookup.affixPoolLabel
import com.nightreign.relicchecker.ui.NightPill
import com.nightreign.relicchecker.ui.gamedata.GameDataLayout
import com.nightreign.relicchecker.ui.theme.NightColors

/**
 * 「按词条查」的详情页（macOS AffixLookupDetailPane 的手机版）：基本信息 → 互斥组 →
 * 深夜遗物 → 能在哪出（口径 / 种类统计 / 固定与随机出处）→ 数据来源。
 * 出处可能上百行，所以整页是一个 LazyColumn，命中的遗物逐行作为独立 item。
 */
@Composable
internal fun LookupAffixDetail(
    index: AffixLookupIndex,
    effectId: Int,
    relicDataDetail: String,
    onPickAffix: (Int) -> Unit,
    onPickRelic: (Int) -> Unit,
    modifier: Modifier = Modifier,
) {
    val report = remember(index, effectId) { index.report(effectId) }
    // 以下状态在 SaveableStateProvider 里按「这一层详情」保存：返回上一层时还原
    var conflictsExpanded by rememberSaveable { mutableStateOf(false) }
    var fixedExpanded by rememberSaveable { mutableStateOf(false) }
    var randomExpanded by rememberSaveable { mutableStateOf(false) }
    val listState = rememberLazyListState()

    if (report == null) {
        LookupEmptyState(title = index.affixName(effectId), detail = LookupCopy.NO_AFFIX_MATCH, modifier = modifier)
        return
    }
    val curses = remember(index, report) {
        if (report.affix.requiresCurse && !report.affix.isCurse && report.hasRelicData) index.curseAffixes() else emptyList()
    }

    LazyColumn(
        modifier = modifier.fillMaxSize(),
        state = listState,
        contentPadding = GameDataLayout.listPadding(top = 4.dp),
    ) {
        item(key = "summary", contentType = "card") {
            AffixSummaryCard(report, Modifier.padding(bottom = GameDataLayout.SectionSpacing))
        }
        item(key = "conflicts", contentType = "card") {
            ConflictCard(
                report = report,
                expanded = conflictsExpanded,
                onToggle = { conflictsExpanded = !conflictsExpanded },
                onPickAffix = onPickAffix,
                modifier = Modifier.padding(bottom = GameDataLayout.SectionSpacing),
            )
        }
        item(key = "deep", contentType = "card") {
            DeepCard(
                report = report,
                curses = curses.map { it.effectId to it.displayName },
                onPickAffix = onPickAffix,
                modifier = Modifier.padding(bottom = GameDataLayout.SectionSpacing),
            )
        }
        if (report.hasRelicData) {
            item(key = "where", contentType = "card") {
                WhereCard(report, Modifier.padding(bottom = GameDataLayout.SectionSpacing))
            }
            hitSection(
                keyPrefix = "fixed",
                title = LookupCopy.FIXED_HITS_TITLE,
                tint = NightColors.Green,
                hits = report.fixedRelics,
                expanded = fixedExpanded,
                onToggle = { fixedExpanded = !fixedExpanded },
                onPickRelic = onPickRelic,
            )
            hitSection(
                keyPrefix = "random",
                title = LookupCopy.RANDOM_HITS_TITLE,
                tint = NightColors.PurpleSoft,
                hits = report.randomRelics,
                expanded = randomExpanded,
                onToggle = { randomExpanded = !randomExpanded },
                onPickRelic = onPickRelic,
            )
            if (report.hiddenRelicCount > 0) {
                item(key = "hidden", contentType = "note") {
                    LookupFootnote(
                        LookupCopy.hiddenRelicsNote(report.hiddenRelicCount),
                        Modifier.padding(start = 2.dp, end = 2.dp, bottom = GameDataLayout.SectionSpacing),
                    )
                }
            }
        } else {
            item(key = "no-relic-data", contentType = "card") {
                LookupNoticeCard(
                    title = LookupCopy.RELIC_DATA_UNAVAILABLE,
                    detail = relicDataDetail + LookupCopy.AFFIX_DETAIL_UNAVAILABLE_SUFFIX,
                    modifier = Modifier.padding(bottom = GameDataLayout.SectionSpacing),
                )
            }
        }
        item(key = "sources", contentType = "card") {
            LookupSourcesCard(index.catalogSources, index.relicSources)
        }
    }
}

// MARK: 基本信息

@Composable
private fun AffixSummaryCard(report: AffixLookupReport, modifier: Modifier = Modifier) {
    val affix = report.affix
    LookupCard(modifier = modifier) {
        Row(verticalAlignment = Alignment.Top, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            Text(
                affix.displayName,
                style = MaterialTheme.typography.titleLarge,
                color = NightColors.TextPrimary,
                modifier = Modifier.weight(1f),
            )
            Text(
                affix.effectId.toString(),
                style = MaterialTheme.typography.labelMedium.lookupTabular(),
                color = NightColors.TextMuted,
                modifier = Modifier.padding(top = 4.dp),
            )
        }
        LookupFlow {
            NightPill(affix.category, NightColors.PurpleSoft)
            if (affix.inCatalog) {
                NightPill(LookupCopy.superposabilityPill(affix.superposability), NightColors.TextSecondary)
            } else {
                NightPill(LookupCopy.EXTRA_ONLY_PILL, NightColors.Amber)
            }
            if (affix.isCurse) NightPill(LookupCopy.CURSE_PILL, NightColors.Red)
            if (affix.requiresCurse) NightPill(LookupCopy.REQUIRES_CURSE_PILL, NightColors.Amber)
        }
        if (affix.explanation.isNotEmpty()) {
            Text(affix.explanation, style = MaterialTheme.typography.bodyMedium, color = NightColors.TextSecondary)
        } else if (!affix.inCatalog) {
            LookupFootnote(LookupCopy.EXTRA_ONLY_NOTE)
        }
        LookupDivider()
        LookupKeyValues(
            listOf(
                LookupCopy.KEY_SORT_ID to affix.sortId.toString(),
                LookupCopy.KEY_COMPATIBILITY_ID to LookupCopy.compatibilityValue(affix.compatibilityId),
                LookupCopy.KEY_LIVE_POOLS to LookupCopy.livePoolValue(report.livePoolCount),
            ),
        )
    }
}

// MARK: 互斥组

@Composable
private fun ConflictCard(
    report: AffixLookupReport,
    expanded: Boolean,
    onToggle: () -> Unit,
    onPickAffix: (Int) -> Unit,
    modifier: Modifier = Modifier,
) {
    // 四支与 macOS / Windows 同一条链：不可达优先于 compatibilityId == -1
    when (report.conflictBranch) {
        AffixConflictBranch.UNREACHABLE ->
            LookupNoticeCard(LookupCopy.UNREACHABLE_CONFLICT_TITLE, LookupCopy.UNREACHABLE_CONFLICT_NOTE, modifier)
        AffixConflictBranch.NO_GROUP ->
            LookupNoticeCard(LookupCopy.CONFLICT_TITLE, LookupCopy.NO_CONFLICT_GROUP_NOTE, modifier)
        AffixConflictBranch.LONE ->
            LookupNoticeCard(LookupCopy.CONFLICT_TITLE, affixLookupLoneConflictNote(report.affix.compatibilityId), modifier)
        AffixConflictBranch.PEERS -> {
            // 物品表补充条目没有说明，排在词条库条目之后（macOS conflictCard）
            val preferred = remember(report) {
                report.conflicts.filter { it.inCatalog } + report.conflicts.filter { !it.inCatalog }
            }
            val extras = preferred.count { !it.inCatalog }
            val total = report.conflicts.size
            val shown = affixLookupShown(preferred, expanded, AFFIX_LOOKUP_CONFLICT_LIMIT)
            LookupCard(modifier = modifier) {
                LookupHeading(
                    title = LookupCopy.conflictCardTitle(report.affix.compatibilityId),
                    subtitle = LookupCopy.conflictCardSubtitle(total + 1, extras),
                )
                LookupFlow(spacing = 2.dp) {
                    shown.forEach { peer ->
                        LookupAffixChip(peer.displayName, peer.effectId, onClick = { onPickAffix(peer.effectId) })
                    }
                }
                // 最大的互斥组有 102 条，必须能在本页看全
                if (total > AFFIX_LOOKUP_CONFLICT_LIMIT) {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        LookupTextButton(LookupCopy.conflictExpandButton(expanded, total, AFFIX_LOOKUP_CONFLICT_LIMIT), onToggle)
                        LookupFootnote(
                            LookupCopy.conflictExpandHint(expanded, total, AFFIX_LOOKUP_CONFLICT_LIMIT),
                            Modifier.weight(1f),
                        )
                    }
                }
            }
        }
    }
}

// MARK: 深夜遗物

@Composable
private fun DeepCard(
    report: AffixLookupReport,
    curses: List<Pair<Int, String>>,
    onPickAffix: (Int) -> Unit,
    modifier: Modifier = Modifier,
) {
    val affix = report.affix
    val inAny = report.deepHits.any { it.contains } || report.cursePoolHit.contains
    val tint = when {
        affix.isCurse -> NightColors.Red
        affix.requiresCurse -> NightColors.Amber
        inAny -> NightColors.Green
        else -> NightColors.TextMuted
    }
    LookupCard(modifier = modifier) {
        LookupHeading(LookupCopy.DEEP_TITLE, LookupCopy.DEEP_SUBTITLE)
        Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
            (report.deepHits + report.cursePoolHit).forEach { PoolRow(it) }
        }
        LookupInlineNote(report.deepNote, tint)
        if (curses.isNotEmpty()) {
            LookupFlow(spacing = 2.dp) {
                curses.forEach { (id, name) ->
                    LookupAffixChip(name, id, onClick = { onPickAffix(id) })
                }
            }
        }
    }
}

@Composable
private fun PoolRow(hit: LookupPoolHit) {
    val shape = RoundedCornerShape(10.dp)
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(shape)
            .background(if (hit.contains) NightColors.Green.copy(alpha = .07f) else NightColors.Field)
            .border(1.dp, if (hit.contains) NightColors.Green.copy(alpha = .28f) else NightColors.Border, shape)
            .padding(horizontal = 11.dp, vertical = 9.dp),
        horizontalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        LookupHitDot(hit.contains, Modifier.padding(top = 5.dp))
        Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(
                hit.label,
                style = MaterialTheme.typography.bodyMedium,
                fontWeight = FontWeight.SemiBold,
                color = if (hit.contains) NightColors.TextPrimary else NightColors.TextSecondary,
            )
            if (hit.detail.isNotEmpty()) {
                Text(hit.detail, style = MaterialTheme.typography.labelSmall, color = NightColors.TextMuted)
            }
            // 没有遗物物品表时只知道「在不在这个池里」，不知道池有多大
            Text(
                LookupCopy.poolRowMeta(hit.poolId, hit.memberCount, hit.relicCount),
                style = MaterialTheme.typography.labelSmall.lookupTabular(),
                color = NightColors.TextMuted,
            )
        }
    }
}

// MARK: 能在哪出

@Composable
private fun WhereCard(report: AffixLookupReport, modifier: Modifier = Modifier) {
    LookupCard(modifier = modifier) {
        LookupHeading(
            LookupCopy.WHERE_TITLE,
            LookupCopy.whereSubtitle(report.totalRelicCount, report.fixedRelics.size, report.randomRelics.size),
        )
        Text(
            LookupCopy.MODES_HEADING,
            style = MaterialTheme.typography.labelMedium,
            fontWeight = FontWeight.Bold,
            color = NightColors.TextSecondary,
        )
        Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
            report.modeHits.forEach { ModeRow(it) }
        }
        LookupFootnote(LookupCopy.TIER_NOTE)
        if (report.modeHits.none { it.isAvailable } && report.totalRelicCount > 0) {
            LookupInlineNote(LookupCopy.NOT_IN_NORMAL_POOLS_NOTE, NightColors.PurpleSoft)
        }
        if (report.kindCounts.isNotEmpty()) {
            LookupDivider()
            LookupFlow {
                report.kindCounts.forEach { NightPill(LookupCopy.kindCountPill(it.kind, it.count), NightColors.PurpleSoft) }
            }
        }
    }
}

@Composable
private fun ModeRow(hit: LookupModeHit) {
    val shape = RoundedCornerShape(10.dp)
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(shape)
            .background(NightColors.Field)
            .border(1.dp, NightColors.Border, shape)
            .padding(horizontal = 11.dp, vertical = 10.dp),
        horizontalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        LookupHitDot(hit.isAvailable, Modifier.padding(top = 5.dp))
        Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(5.dp)) {
            Text(
                hit.mode.title,
                style = MaterialTheme.typography.bodyMedium,
                fontWeight = FontWeight.SemiBold,
                color = if (hit.isAvailable) NightColors.TextPrimary else NightColors.TextSecondary,
            )
            Text(hit.mode.detail, style = MaterialTheme.typography.labelSmall, color = NightColors.TextMuted)
            if (hit.isAvailable) {
                LookupFlow {
                    hit.hitPools.forEach { NightPill(it.label, NightColors.Green) }
                }
            } else {
                Text(
                    LookupCopy.MODE_UNAVAILABLE,
                    style = MaterialTheme.typography.labelMedium,
                    fontWeight = FontWeight.SemiBold,
                    color = NightColors.TextMuted,
                )
            }
        }
    }
}

/** 固定 / 随机出处：标题一行 + 每件遗物一行（独立 item）+ 展开 / 收起。 */
private fun LazyListScope.hitSection(
    keyPrefix: String,
    title: String,
    tint: Color,
    hits: List<RelicLookupHit>,
    expanded: Boolean,
    onToggle: () -> Unit,
    onPickRelic: (Int) -> Unit,
) {
    if (hits.isEmpty()) return
    val shown = affixLookupShown(hits, expanded, AFFIX_LOOKUP_ROW_LIMIT)
    item(key = "$keyPrefix-head", contentType = "hit-head") {
        Row(
            modifier = Modifier.fillMaxWidth().padding(start = 2.dp, end = 2.dp, bottom = 8.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Text(
                title,
                style = MaterialTheme.typography.labelLarge,
                fontWeight = FontWeight.Bold,
                color = NightColors.TextSecondary,
                modifier = Modifier.weight(1f, fill = false),
            )
            NightPill(LookupCopy.hitCountPill(hits.size), tint)
        }
    }
    items(shown, key = { "$keyPrefix-${it.key}" }, contentType = { "hit" }) { hit ->
        HitRow(hit, onClick = { onPickRelic(hit.relicId) }, modifier = Modifier.padding(bottom = 6.dp))
    }
    if (hits.size > AFFIX_LOOKUP_ROW_LIMIT) {
        item(key = "$keyPrefix-more", contentType = "hit-more") {
            Column(
                modifier = Modifier.fillMaxWidth().padding(top = 2.dp, bottom = GameDataLayout.SectionSpacing),
                verticalArrangement = Arrangement.spacedBy(4.dp),
            ) {
                LookupTextButton(LookupCopy.hitExpandButton(expanded, hits.size, AFFIX_LOOKUP_ROW_LIMIT), onToggle)
                // 「共 N 件 · 已显示 M 件」与桌面两端逐字相同
                LookupFootnote(LookupCopy.hitExpandHint(hits.size, shown.size))
            }
        }
    } else {
        item(key = "$keyPrefix-end", contentType = "spacer") {
            // 最后一行自带 6dp 下边距，这里补足到分区间距
            Spacer(Modifier.height(GameDataLayout.SectionSpacing - 6.dp))
        }
    }
}

@Composable
private fun HitRow(hit: RelicLookupHit, onClick: () -> Unit, modifier: Modifier = Modifier) {
    val shape = RoundedCornerShape(10.dp)
    Row(
        modifier = modifier
            .fillMaxWidth()
            .heightIn(min = 52.dp)
            .clip(shape)
            .background(NightColors.Field)
            .border(1.dp, NightColors.Border, shape)
            .clickable(role = Role.Button, onClick = onClick)
            .padding(horizontal = 12.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        LookupRelicDot(hit.color)
        Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                Text(
                    hit.relicName,
                    style = MaterialTheme.typography.bodyMedium,
                    fontWeight = FontWeight.SemiBold,
                    color = NightColors.TextPrimary,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.weight(1f, fill = false),
                )
                if (hit.role == RelicSlotRole.CURSE) {
                    Text(LookupCopy.HIT_CURSE_SLOT, style = MaterialTheme.typography.labelSmall, color = NightColors.Red)
                }
            }
            Text(
                hit.kindLabel + " · " + hit.poolIds.joinToString(" / ") { affixPoolLabel(it) },
                style = MaterialTheme.typography.labelSmall,
                color = NightColors.TextMuted,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
        }
        Text(
            hit.relicId.toString(),
            style = MaterialTheme.typography.labelSmall.lookupTabular(),
            color = NightColors.TextMuted,
        )
    }
}
