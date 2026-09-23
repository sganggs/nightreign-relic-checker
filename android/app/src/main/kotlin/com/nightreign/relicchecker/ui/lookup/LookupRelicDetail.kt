package com.nightreign.relicchecker.ui.lookup

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.nightreign.relicchecker.gamedata.lookup.AffixLookupIndex
import com.nightreign.relicchecker.gamedata.lookup.LookupCopy
import com.nightreign.relicchecker.gamedata.lookup.RelicLookupEntry
import com.nightreign.relicchecker.gamedata.lookup.RelicSlotSummary
import com.nightreign.relicchecker.gamedata.lookup.affixPoolLabel
import com.nightreign.relicchecker.gamedata.lookup.affixPoolLabelIsFallback
import com.nightreign.relicchecker.ui.NightPill
import com.nightreign.relicchecker.ui.gamedata.GameDataLayout
import com.nightreign.relicchecker.ui.theme.NightColors

/**
 * 「按遗物查」的详情页（macOS RelicLookupDetailPane 的手机版）：概要 → 槽位池（普通遗物逐槽、
 * 深夜遗物按池归并不打槽序号）→ 官方固定词条 → 数据来源。池成员标签点了跳到该词条的详情。
 */
@Composable
internal fun LookupRelicDetail(
    index: AffixLookupIndex,
    relicId: Int,
    onPickAffix: (Int) -> Unit,
    modifier: Modifier = Modifier,
) {
    val listState = rememberLazyListState()
    val entry = index.relic(relicId)
    if (entry == null) {
        LookupEmptyState(title = LookupCopy.NO_RELIC_MATCH, detail = relicId.toString(), modifier = modifier)
        return
    }
    LazyColumn(
        modifier = modifier.fillMaxSize(),
        state = listState,
        contentPadding = GameDataLayout.listPadding(top = 4.dp),
    ) {
        item(key = "summary", contentType = "card") {
            RelicSummaryCard(entry, Modifier.padding(bottom = GameDataLayout.SectionSpacing))
        }
        item(key = "slots", contentType = "card") {
            SlotsCard(index, entry, onPickAffix, Modifier.padding(bottom = GameDataLayout.SectionSpacing))
        }
        entry.fixedEffectIds?.let { fixed ->
            item(key = "fixed", contentType = "card") {
                FixedCard(index, fixed.filter { it != -1 }, onPickAffix, Modifier.padding(bottom = GameDataLayout.SectionSpacing))
            }
        }
        item(key = "sources", contentType = "card") {
            LookupSourcesCard(index.catalogSources, index.relicSources)
        }
    }
}

@Composable
private fun RelicSummaryCard(entry: RelicLookupEntry, modifier: Modifier = Modifier) {
    LookupCard(modifier = modifier) {
        Row(verticalAlignment = Alignment.Top, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            Text(
                entry.displayName,
                style = MaterialTheme.typography.titleLarge,
                color = NightColors.TextPrimary,
                modifier = Modifier.weight(1f),
            )
            Text(
                entry.id.toString(),
                style = MaterialTheme.typography.labelMedium.lookupTabular(),
                color = NightColors.TextMuted,
                modifier = Modifier.padding(top = 4.dp),
            )
        }
        LookupFlow {
            NightPill(entry.kindLabel, if (entry.deep) NightColors.PurpleSoft else NightColors.TextSecondary)
            NightPill(LookupCopy.colorPill(entry.colorLabel), lookupRelicHue(entry.info.color), dot = true)
            NightPill(LookupCopy.slotCountLabel(entry.slotCount), NightColors.PurpleSoft)
            if (entry.fixedEffectIds != null) NightPill(LookupCopy.FIXED_PILL, NightColors.Green)
        }
    }
}

@Composable
private fun SlotsCard(
    index: AffixLookupIndex,
    entry: RelicLookupEntry,
    onPickAffix: (Int) -> Unit,
    modifier: Modifier = Modifier,
) {
    LookupCard(modifier = modifier) {
        LookupHeading(
            LookupCopy.SLOTS_TITLE,
            if (entry.deep) LookupCopy.SLOTS_SUBTITLE_DEEP else LookupCopy.SLOTS_SUBTITLE_NORMAL,
        )
        val groups = entry.deepPoolGroups
        if (groups != null) {
            // 深夜遗物：按池归并，写「本件 N 条」，不打槽序号
            groups.forEach { group ->
                SlotRow(index, group.slot, LookupCopy.deepGroupTitle(group.count), onPickAffix)
            }
            LookupInlineNote(LookupCopy.DEEP_SLOTS_NOTE, NightColors.Amber)
        } else {
            entry.slots.forEach { slot ->
                SlotRow(index, slot, LookupCopy.normalSlotTitle(slot.slotIndex), onPickAffix)
            }
        }
    }
}

@Composable
private fun SlotRow(
    index: AffixLookupIndex,
    slot: RelicSlotSummary,
    title: String,
    onPickAffix: (Int) -> Unit,
) {
    val shape = RoundedCornerShape(11.dp)
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(shape)
            .background(NightColors.Field.copy(alpha = .7f))
            .border(1.dp, NightColors.Border, shape)
            .padding(11.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        LookupFlow {
            Text(
                title,
                style = MaterialTheme.typography.labelLarge,
                fontWeight = FontWeight.Bold,
                color = if (slot.isEmpty) NightColors.TextMuted else NightColors.PurpleSoft,
                modifier = Modifier.align(Alignment.CenterVertically),
            )
            if (slot.isEmpty) {
                Text(
                    LookupCopy.NO_SLOT,
                    style = MaterialTheme.typography.bodySmall,
                    color = NightColors.TextMuted,
                    modifier = Modifier.align(Alignment.CenterVertically),
                )
            } else {
                NightPill(affixPoolLabel(slot.poolId), NightColors.PurpleSoft)
                NightPill(
                    LookupCopy.slotSizePill(slot.isFixed, slot.poolSize),
                    if (slot.isFixed) NightColors.Green else NightColors.TextSecondary,
                )
                if (slot.hasCurse) NightPill(LookupCopy.curseSlotPill(slot.cursePoolSize), NightColors.Amber)
                // 具名池（深夜 A/B/C 等）的标签里没有 id，这里补上；兜底标签本身就是「池 xxx」
                if (!affixPoolLabelIsFallback(slot.poolId)) {
                    Text(
                        LookupCopy.poolIdLabel(slot.poolId),
                        style = MaterialTheme.typography.labelSmall.lookupTabular(),
                        color = NightColors.TextMuted,
                        modifier = Modifier.align(Alignment.CenterVertically),
                    )
                }
            }
        }
        if (slot.isEmptyPool) {
            LookupFootnote(LookupCopy.EMPTY_POOL_NOTE)
        } else if (!slot.isEmpty) {
            LookupFlow(spacing = 2.dp) {
                slot.previewEffectIds.forEach { id ->
                    LookupAffixChip(
                        label = index.affixName(id),
                        effectId = id,
                        onClick = { onPickAffix(id) },
                        background = NightColors.Card,
                    )
                }
            }
            val more = slot.poolSize - slot.previewEffectIds.size
            if (more > 0) LookupFootnote(LookupCopy.previewMore(more))
        }
    }
}

@Composable
private fun FixedCard(
    index: AffixLookupIndex,
    ids: List<Int>,
    onPickAffix: (Int) -> Unit,
    modifier: Modifier = Modifier,
) {
    LookupCard(modifier = modifier) {
        LookupHeading(LookupCopy.FIXED_CARD_TITLE, LookupCopy.FIXED_CARD_SUBTITLE)
        Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
            ids.forEachIndexed { position, id ->
                val shape = RoundedCornerShape(10.dp)
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .heightIn(min = 48.dp)
                        .clip(shape)
                        .background(NightColors.Field)
                        .border(1.dp, NightColors.Border, shape)
                        .clickable(role = Role.Button) { onPickAffix(id) }
                        .padding(horizontal = 11.dp, vertical = 8.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(9.dp),
                ) {
                    Text(
                        (position + 1).toString(),
                        style = MaterialTheme.typography.labelLarge.lookupTabular(),
                        fontWeight = FontWeight.Bold,
                        color = NightColors.PurpleSoft,
                        modifier = Modifier.width(16.dp),
                    )
                    Text(
                        index.affixName(id),
                        style = MaterialTheme.typography.bodyMedium,
                        color = NightColors.TextPrimary,
                        maxLines = 2,
                        modifier = Modifier.weight(1f),
                    )
                    Text(id.toString(), style = MaterialTheme.typography.labelSmall.lookupTabular(), color = NightColors.TextMuted)
                }
            }
        }
        LookupInlineNote(LookupCopy.FIXED_CARD_NOTE, NightColors.PurpleSoft)
    }
}
