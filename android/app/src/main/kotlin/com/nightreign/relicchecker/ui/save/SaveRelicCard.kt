package com.nightreign.relicchecker.ui.save

import androidx.compose.animation.animateContentSize
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.nightreign.relicchecker.gamedata.save.AuditedRelic
import com.nightreign.relicchecker.gamedata.save.AuditedSave
import com.nightreign.relicchecker.gamedata.save.RelicAuditIssue
import com.nightreign.relicchecker.ui.NightPanel
import com.nightreign.relicchecker.ui.NightPill
import com.nightreign.relicchecker.ui.theme.NightColors

// 单件遗物卡（存档检查列表与存档对比共用），移植 macOS 端 SaveRelicCard.swift：
// 名称 + 状态、种类 / 颜色 / 深夜 / ID、三行正负词条（有说明的可展开 ⓘ）、问题列表、
// 官方固定词条与正确的词条顺序（两块的先后与导出报告一致）。

/** 负面词条的文字色（与桌面端同一色值）。 */
internal val SaveCurseText = Color(0xFF8CA3D1)
private val RelicBlue = Color(0xFF6199FA)
private val RelicWhite = Color.White.copy(alpha = .72f)

internal fun statusColor(relic: AuditedRelic): Color = when {
    relic.isInvalid -> NightColors.Red
    relic.result.warnings.isEmpty() -> NightColors.Green
    else -> NightColors.Amber
}

private fun relicColor(color: Int): Color = when (color) {
    0 -> NightColors.Red
    1 -> RelicBlue
    2 -> NightColors.Amber
    3 -> NightColors.Green
    4 -> RelicWhite
    else -> NightColors.TextSecondary
}

@Composable
internal fun SaveRelicCard(
    relic: AuditedRelic,
    save: AuditedSave,
    modifier: Modifier = Modifier,
    quantity: Int = 1,
) {
    val accent = statusColor(relic)
    NightPanel(
        modifier = modifier.fillMaxWidth(),
        borderColor = if (relic.isInvalid) NightColors.Red.copy(alpha = .38f) else NightColors.Border,
    ) {
        Column(
            modifier = Modifier.fillMaxWidth().padding(14.dp).animateContentSize(),
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            Row(verticalAlignment = Alignment.Top, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(
                    relic.displayName,
                    modifier = Modifier.weight(1f),
                    style = MaterialTheme.typography.titleMedium,
                    color = NightColors.TextPrimary,
                )
                if (quantity > 1) NightPill("×$quantity", NightColors.PurpleSoft)
                NightPill(relic.statusLabel, accent, dot = true)
            }

            Row(
                modifier = Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()),
                horizontalArrangement = Arrangement.spacedBy(6.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                NightPill(relic.kindLabel, NightColors.PurpleSoft)
                // 「红色」而不是「红」：与报告 / CSV 同一份颜色文案；遗物表里查不到时不显示
                relic.info?.let { NightPill(relic.colorText, relicColor(it.color)) }
                if (relic.isDeep) NightPill("深夜", NightColors.Purple)
                Text(
                    "ID ${relic.relic.itemId}",
                    style = MaterialTheme.typography.labelSmall,
                    color = NightColors.TextMuted,
                )
            }

            val rows = (0 until 3).mapNotNull { row ->
                val effect = relic.relic.effects.getOrElse(row) { -1L }
                val curse = relic.relic.curses.getOrElse(row) { -1L }
                if (effect == -1L && curse == -1L) null else Triple(row, effect, curse)
            }
            if (rows.isNotEmpty()) {
                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .clip(RoundedCornerShape(10.dp))
                        .background(NightColors.Field.copy(alpha = .75f))
                        .padding(horizontal = 4.dp, vertical = 4.dp),
                ) {
                    rows.forEach { (row, effect, curse) ->
                        SaveAffixLine(save = save, id = effect, isCurse = false, stateKey = "${relic.relic.index}-$row-e")
                        if (curse != -1L) {
                            SaveAffixLine(save = save, id = curse, isCurse = true, stateKey = "${relic.relic.index}-$row-c")
                        }
                    }
                }
            }

            relic.result.issues.forEach { SaveIssueRow(it, warning = false) }
            relic.result.warnings.forEach { SaveIssueRow(it, warning = true) }

            // 先「官方固定词条」、后「正确的词条顺序」：与导出报告和桌面端遗物卡同一顺序
            relic.result.officialEffects?.let { official ->
                val ids = official.filter { it != -1L }
                if (ids.isNotEmpty()) {
                    SaveHintBlock(
                        title = "该遗物的官方固定词条（可据此改回）",
                        lines = ids.mapIndexed { index, id -> "${index + 1}. ${save.affixName(id)} ($id)" },
                    )
                }
            }
            relic.result.orderedEffects?.let { ordered ->
                SaveHintBlock(
                    title = "正确的词条顺序",
                    lines = ordered.mapIndexed { index, id -> "${index + 1}. " + if (id == -1L) "（空）" else save.affixName(id) },
                )
            }
        }
    }
}

/**
 * 一条词条：有说明的整行可点，展开这一条的全文（正面 / 诅咒各自独立展开）；没有说明的不显示入口。
 * 负面词条前加「｜」并用诅咒色。
 */
@Composable
private fun SaveAffixLine(save: AuditedSave, id: Long, isCurse: Boolean, stateKey: String) {
    val name = if (id == -1L) "（空）" else save.affixName(id)
    val explanation = if (id == -1L) null else save.affixExplanation(id)
    var expanded by rememberSaveable(stateKey, id) { mutableStateOf(false) }
    val textColor = when {
        isCurse -> SaveCurseText
        id == -1L -> NightColors.TextMuted
        else -> NightColors.TextPrimary
    }
    Column(modifier = Modifier.fillMaxWidth()) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .heightIn(min = 40.dp)
                .clip(RoundedCornerShape(8.dp))
                .then(
                    if (explanation != null) {
                        Modifier
                            .clickable(role = Role.Button, onClickLabel = if (expanded) "收起词条说明" else "展开词条说明") {
                                expanded = !expanded
                            }
                            .semantics { contentDescription = "$name 的词条说明" }
                    } else {
                        Modifier
                    },
                )
                .padding(horizontal = 8.dp, vertical = 6.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            if (isCurse) {
                Text("｜", style = MaterialTheme.typography.bodyMedium, color = SaveCurseText)
            }
            Text(
                name,
                modifier = Modifier.weight(1f),
                style = MaterialTheme.typography.bodyMedium,
                color = textColor,
            )
            if (explanation != null) {
                Box(Modifier.width(8.dp))
                Box(
                    modifier = Modifier
                        .size(20.dp)
                        .clip(RoundedCornerShape(99.dp))
                        .background(if (expanded) NightColors.Purple.copy(alpha = .35f) else Color.Transparent)
                        .border(1.dp, NightColors.PurpleSoft.copy(alpha = if (expanded) 1f else .55f), RoundedCornerShape(99.dp)),
                    contentAlignment = Alignment.Center,
                ) {
                    Text("i", style = MaterialTheme.typography.labelSmall, color = NightColors.PurpleSoft, fontWeight = FontWeight.Bold)
                }
            }
        }
        if (expanded && explanation != null) {
            Text(
                explanation,
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(start = 8.dp, end = 8.dp, bottom = 6.dp)
                    .clip(RoundedCornerShape(8.dp))
                    .background(NightColors.Purple.copy(alpha = .08f))
                    .padding(10.dp),
                style = MaterialTheme.typography.bodySmall,
                color = NightColors.TextSecondary,
            )
        }
    }
}

@Composable
internal fun SaveIssueRow(issue: RelicAuditIssue, warning: Boolean) {
    val color = if (warning) NightColors.Amber else NightColors.Red
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(10.dp))
            .background(NightColors.Field.copy(alpha = .75f))
            .padding(10.dp),
        horizontalArrangement = Arrangement.spacedBy(9.dp),
        verticalAlignment = Alignment.Top,
    ) {
        Text(if (warning) "!" else "✗", style = MaterialTheme.typography.bodyMedium, color = color, fontWeight = FontWeight.Bold)
        Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
            Text(issue.title, style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.SemiBold, color = NightColors.TextPrimary)
            Text(issue.detail, style = MaterialTheme.typography.bodySmall, color = NightColors.TextSecondary)
        }
    }
}

@Composable
private fun SaveHintBlock(title: String, lines: List<String>) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(10.dp))
            .background(NightColors.Purple.copy(alpha = .06f))
            .border(1.dp, NightColors.Purple.copy(alpha = .18f), RoundedCornerShape(10.dp))
            .padding(10.dp),
        verticalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        Text(title, style = MaterialTheme.typography.labelLarge, fontWeight = FontWeight.Bold, color = NightColors.PurpleSoft)
        lines.forEach { Text(it, style = MaterialTheme.typography.bodySmall, color = NightColors.TextSecondary) }
    }
}
