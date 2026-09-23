package com.nightreign.relicchecker.ui.save

import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.nightreign.relicchecker.gamedata.save.AuditedSave
import com.nightreign.relicchecker.gamedata.save.SaveCompareBlock
import com.nightreign.relicchecker.gamedata.save.SaveCompareCharacter
import com.nightreign.relicchecker.gamedata.save.SaveCompareDirection
import com.nightreign.relicchecker.gamedata.save.SaveCompareEntry
import com.nightreign.relicchecker.gamedata.save.SaveCompareResult
import com.nightreign.relicchecker.ui.NightPanel
import com.nightreign.relicchecker.ui.NightPill
import com.nightreign.relicchecker.ui.NightSearchField
import com.nightreign.relicchecker.ui.NightSegmentedControl
import com.nightreign.relicchecker.ui.theme.NightColors

// 存档对比结果（移植 macOS 端 SaveCompareSection.swift，文案一致）：
// 以当前存档为准，另一份多出的记为「新增」、少掉的记为「减少」；按角色槽位分块，
// 每块是一张头部卡片 + 新增 / 减少两组遗物卡（遗物卡逐件是 LazyColumn 的独立条目）。

internal fun LazyListScope.saveCompareItems(
    result: SaveCompareResult,
    blocks: List<SaveCompareBlock>,
    base: AuditedSave,
    direction: SaveCompareDirection,
    query: String,
    onDirection: (SaveCompareDirection) -> Unit,
    onQuery: (String) -> Unit,
    onClose: () -> Unit,
) {
    item(key = "cmp-header", contentType = "cmp-header") {
        CompareHeader(result, direction, query, onDirection, onQuery, onClose)
    }
    blocks.forEach { block ->
        val slot = block.character.slot
        item(key = "cmp-$slot", contentType = "cmp-character") { CompareCharacterHeader(block.character) }
        if (!block.character.isIdentical) {
            entryGroup(slot, "a", "对比存档中新增", NightColors.Green, block.added, base)
            entryGroup(slot, "r", "对比存档中减少", NightColors.Red, block.removed, base)
        }
    }
    if (blocks.isEmpty()) {
        // 「完全一致」只在这里说一次
        item(key = "cmp-empty", contentType = "cmp-note") {
            Text(
                result.emptyListNote,
                modifier = Modifier.fillMaxWidth().padding(vertical = 8.dp),
                style = MaterialTheme.typography.bodyMedium,
                color = NightColors.TextSecondary,
            )
        }
    }
    item(key = "cmp-foot", contentType = "cmp-note") {
        Text(SaveCompareResult.FOOTNOTE, style = MaterialTheme.typography.labelSmall, color = NightColors.TextMuted)
    }
}

private fun LazyListScope.entryGroup(
    slot: Int,
    tag: String,
    title: String,
    color: Color,
    entries: List<SaveCompareEntry>,
    base: AuditedSave,
) {
    if (entries.isEmpty()) return
    item(key = "cmp-$slot-$tag", contentType = "cmp-group") {
        Text(
            "$title（${entries.sumOf { it.count }}）",
            modifier = Modifier.padding(start = 4.dp, top = 2.dp),
            style = MaterialTheme.typography.labelLarge,
            fontWeight = FontWeight.Bold,
            color = color,
        )
    }
    items(entries, key = { "cmp-$slot-$tag-${it.id}" }, contentType = { "relic" }) { entry ->
        SaveRelicCard(relic = entry.relic, save = base, quantity = entry.count)
    }
}

@Composable
private fun CompareHeader(
    result: SaveCompareResult,
    direction: SaveCompareDirection,
    query: String,
    onDirection: (SaveCompareDirection) -> Unit,
    onQuery: (String) -> Unit,
    onClose: () -> Unit,
) {
    NightPanel(modifier = Modifier.fillMaxWidth()) {
        Column(modifier = Modifier.fillMaxWidth().padding(14.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    Text("存档对比", style = MaterialTheme.typography.titleMedium, color = NightColors.TextPrimary)
                    Text(
                        "当前：${result.baseFileName}　对比：${result.otherFileName}",
                        style = MaterialTheme.typography.bodySmall,
                        color = NightColors.TextMuted,
                    )
                }
                SaveSecondaryButton("关闭对比", onClick = onClose)
            }
            Row(
                modifier = Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()),
                horizontalArrangement = Arrangement.spacedBy(6.dp),
            ) {
                NightPill("当前共 ${result.totalBase} 件", NightColors.PurpleSoft)
                NightPill("对比共 ${result.totalOther} 件", NightColors.PurpleSoft)
                NightPill("新增 ${result.totalAdded} 件", NightColors.Green)
                NightPill("减少 ${result.totalRemoved} 件", NightColors.Red)
                NightPill("有差异角色 ${result.changedCharacters}", NightColors.PurpleSoft)
                if (result.hasUnreliableSlots) {
                    NightPill("无法对比槽位 ${result.unreliableCharacters.size}", NightColors.Amber)
                }
            }
            NightSegmentedControl(
                items = SaveCompareDirection.entries.map { it.title },
                selectedIndex = direction.ordinal,
                onSelect = { onDirection(SaveCompareDirection.entries[it]) },
            )
            NightSearchField(query, onQuery, placeholder = "在对比结果中搜索遗物名、词条名或 ID")
            if (result.hasUnreliableSlots) {
                Text(SaveCompareResult.UNRELIABLE_NOTE, style = MaterialTheme.typography.bodySmall, color = NightColors.Amber)
            }
        }
    }
}

@Composable
private fun CompareCharacterHeader(character: SaveCompareCharacter) {
    NightPanel(modifier = Modifier.fillMaxWidth()) {
        Column(modifier = Modifier.fillMaxWidth().padding(13.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(character.displayName, style = MaterialTheme.typography.titleMedium, color = NightColors.TextPrimary)
            Row(
                modifier = Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()),
                horizontalArrangement = Arrangement.spacedBy(6.dp),
            ) {
                NightPill("当前 ${character.baseTotal}", NightColors.PurpleSoft)
                NightPill("对比 ${character.otherTotal}", NightColors.PurpleSoft)
                if (character.hasParseError) {
                    NightPill("无法对比", NightColors.Amber)
                } else {
                    NightPill("新增 ${character.addedCount}", if (character.addedCount > 0) NightColors.Green else NightColors.TextSecondary)
                    NightPill("减少 ${character.removedCount}", if (character.removedCount > 0) NightColors.Red else NightColors.TextSecondary)
                }
            }
            // 解析失败的槽位只提示：它的遗物读不出来，不是真实差异
            character.parseNote?.let { Text(it, style = MaterialTheme.typography.bodySmall, color = NightColors.Amber) }
            character.presenceNote?.let { Text(it, style = MaterialTheme.typography.bodySmall, color = NightColors.Amber) }
            if (character.isIdentical) {
                character.identicalNote?.let { Text(it, style = MaterialTheme.typography.bodySmall, color = NightColors.TextSecondary) }
            }
        }
    }
}
