package com.nightreign.relicchecker.ui.bosses

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.nightreign.relicchecker.gamedata.bosses.BossDataIndex
import com.nightreign.relicchecker.gamedata.bosses.BossMutationChoice
import com.nightreign.relicchecker.gamedata.bosses.BossNightMode
import com.nightreign.relicchecker.gamedata.bosses.BossRowText
import com.nightreign.relicchecker.gamedata.bosses.mutationRowCounts
import com.nightreign.relicchecker.ui.NightBottomSheet
import com.nightreign.relicchecker.ui.NightPill
import com.nightreign.relicchecker.ui.theme.NightColors

/**
 * 「常规 / 深夜 · 深度 1…5」六选一（深度差别大，一个开关表达不了，所以做成抽屉里的单选）。
 * 整块内容约 470dp，横屏时抽屉只有约 380dp 高：内容整体可竖向滚动，深度 4 / 5 也选得到。
 */
@Composable
internal fun BossModeSheet(
    index: BossDataIndex,
    current: BossNightMode,
    onSelect: (BossNightMode) -> Unit,
    onDismiss: () -> Unit,
) {
    val dataset = index.dataset
    val text = dataset.deepOfNightText
    NightBottomSheet(onDismissRequest = onDismiss) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 16.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            Text("模式", style = MaterialTheme.typography.titleLarge)
            Text(
                "深夜按${text.depthTitle} 1–5 分档：血量与敌人攻击力逐级上涨，攻击力涨得比血量快得多；" +
                    "部分敌人还会以「${dataset.mutationTitle}」出现，倍率再乘一层。",
                style = MaterialTheme.typography.bodySmall,
                color = NightColors.TextSecondary,
            )
            if (text.description.zh.isNotEmpty()) {
                Text(text.description.zh.replace("\n", " "), style = MaterialTheme.typography.labelSmall, color = NightColors.TextMuted)
            }
            Column {
                BossNightMode.entries.forEach { mode ->
                    SheetOption(
                        title = dataset.title(mode),
                        detail = if (mode.isDeepOfNight) "血量 / 攻击力 / 承受削韧取该深度的 depthStats" else "常驻缩放后的常规数值",
                        selected = mode == current,
                        onClick = { onSelect(mode) },
                    )
                    HorizontalDivider(color = NightColors.Border.copy(alpha = .7f))
                }
            }
            Spacer(Modifier.height(18.dp))
        }
    }
}

/**
 * 「变异个体」选择：不计 / 各行自带档位 / 指定某一档（只作用于池里有它的行）。
 * 每行的 mutationPool 至多一个档位，所以「各行自带档位」就是桌面端逐行下拉的全选版本。
 * 选项列表带 weight(fill = false)：抽屉矮（横屏）时列表让出高度，标题与底部说明照常露出，列表自己滚。
 */
@Composable
internal fun BossMutationSheet(
    index: BossDataIndex,
    current: BossMutationChoice,
    onSelect: (BossMutationChoice) -> Unit,
    onDismiss: () -> Unit,
) {
    val dataset = index.dataset
    val counts = remember(index) { index.mutationRowCounts() }
    val mutable = remember(index) { dataset.allRows.count { it.canMutate } }
    NightBottomSheet(onDismissRequest = onDismiss) {
        Column(
            modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Column(modifier = Modifier.weight(1f)) {
                    Text(BossRowText.mutationPickerTitle, style = MaterialTheme.typography.titleLarge)
                    Text(BossRowText.mutationStackNote, style = MaterialTheme.typography.bodySmall, color = NightColors.TextMuted)
                }
                NightPill("${dataset.mutations.size} 档", NightColors.Red)
            }
            LazyColumn(modifier = Modifier.weight(1f, fill = false).heightIn(min = 300.dp, max = 590.dp)) {
                item(key = "none") {
                    SheetOption(
                        title = BossRowText.mutationPickerNone,
                        detail = "按普通个体计算",
                        selected = current == BossMutationChoice.None,
                        onClick = { onSelect(BossMutationChoice.None) },
                    )
                    HorizontalDivider(color = NightColors.Border.copy(alpha = .7f))
                }
                item(key = "own") {
                    SheetOption(
                        title = "各行自带档位",
                        detail = "$mutable 条数值行能变异，各按自己的 mutationPool 计算",
                        selected = current == BossMutationChoice.Own,
                        onClick = { onSelect(BossMutationChoice.Own) },
                    )
                    HorizontalDivider(color = NightColors.Border.copy(alpha = .7f))
                }
                items(dataset.orderedMutations, key = { it.id }) { mutation ->
                    SheetOption(
                        title = mutation.pickerTitle,
                        detail = listOfNotNull(mutation.statNameEn, "只作用于池里有它的 ${counts[mutation.id] ?: 0} 行").joinToString(" · "),
                        selected = current == BossMutationChoice.Tier(mutation.id),
                        onClick = { onSelect(BossMutationChoice.Tier(mutation.id)) },
                    )
                    HorizontalDivider(color = NightColors.Border.copy(alpha = .7f))
                }
            }
            Text(BossRowText.mutationCountNote, style = MaterialTheme.typography.labelSmall, color = NightColors.TextMuted)
            Spacer(Modifier.height(14.dp))
        }
    }
}

@Composable
private fun SheetOption(title: String, detail: String?, selected: Boolean, onClick: () -> Unit) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .heightIn(min = 52.dp)
            .clickable(role = Role.RadioButton, onClick = onClick)
            .semantics { this.selected = selected }
            .padding(vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Box(
            modifier = Modifier
                .size(18.dp)
                .border(1.5.dp, if (selected) NightColors.PurpleSoft else NightColors.BorderStrong, CircleShape),
            contentAlignment = Alignment.Center,
        ) {
            if (selected) Box(Modifier.size(9.dp).background(NightColors.PurpleSoft, CircleShape))
        }
        Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(
                title,
                style = MaterialTheme.typography.bodyMedium,
                color = NightColors.TextPrimary,
                fontWeight = if (selected) FontWeight.SemiBold else FontWeight.Normal,
            )
            if (!detail.isNullOrEmpty()) {
                Text(detail, style = MaterialTheme.typography.labelSmall, color = NightColors.TextMuted)
            }
        }
    }
}
