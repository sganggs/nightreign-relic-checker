package com.nightreign.relicchecker.ui.bosses

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.rememberScrollState
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.nightreign.relicchecker.gamedata.bosses.BossDataIndex
import com.nightreign.relicchecker.gamedata.bosses.BossFormat
import com.nightreign.relicchecker.gamedata.bosses.BossPageText
import com.nightreign.relicchecker.gamedata.bosses.BossRoleBadge
import com.nightreign.relicchecker.gamedata.bosses.BossRoleCatalog
import com.nightreign.relicchecker.gamedata.bosses.BossRoleText
import com.nightreign.relicchecker.gamedata.bosses.BossRowText
import com.nightreign.relicchecker.gamedata.bosses.BossScalingTier
import com.nightreign.relicchecker.gamedata.bosses.roleOverviewRows
import com.nightreign.relicchecker.ui.theme.NightColors

// 页面底部的数据说明：与列表结果无关，搜索没命中时也必须留在页面上（免责说明不能跟着结果一起消失）。

internal object BossFooterSection {
    const val CAVEATS = "caveats"
    const val ROLES = "roles"
    const val TIERS = "tiers"
    const val MUTATIONS = "mutations"
    const val DEPTHS = "depths"
}

/**
 * 往列表末尾追加底部说明的各个条目（每个折叠块一个 item，展开状态由 [open] 控制）。
 * 「数据说明」标题吸顶：读到底部说明时它顶替上面最后一个分组小标题，
 * 不然「夜王 2」之类会一直钉在说明上面（横屏时还白占一行高度）。
 */
@OptIn(ExperimentalFoundationApi::class)
internal fun LazyListScope.bossFooterItems(
    index: BossDataIndex,
    open: Set<String>,
    onToggle: (String) -> Unit,
) {
    val dataset = index.dataset
    item(key = "footer-divider", contentType = "footer-divider") {
        HorizontalDivider(color = NightColors.Border, modifier = Modifier.padding(top = 18.dp, bottom = 4.dp))
    }
    stickyHeader(key = "footer-heading", contentType = "footer-heading") {
        Text(
            "数据说明",
            modifier = Modifier
                .fillMaxWidth()
                .background(NightColors.Background)
                .padding(top = 8.dp, bottom = 2.dp),
            style = MaterialTheme.typography.titleMedium,
            color = NightColors.TextPrimary,
        )
    }
    item(key = "footer-subtitle", contentType = "footer-subtitle") {
        Text(
            "数值直接取自游戏参数表，不是官方公布，也不是实测手感",
            modifier = Modifier.padding(bottom = 4.dp),
            style = MaterialTheme.typography.bodySmall,
            color = NightColors.TextMuted,
        )
    }
    item(key = "footer-caveats", contentType = "footer-disclosure") {
        BossDisclosure(
            title = "数据说明与已知取舍（${dataset.caveats.size} 条）",
            open = BossFooterSection.CAVEATS in open,
            onToggle = { onToggle(BossFooterSection.CAVEATS) },
        ) {
            Text(BossPageText.unofficialNote, style = MaterialTheme.typography.bodySmall, color = NightColors.TextSecondary)
            dataset.caveats.forEach { BossBullet(it) }
        }
    }
    item(key = "footer-roles", contentType = "footer-disclosure") {
        BossDisclosure(
            title = BossRoleText.overviewTitle(dataset.orderedRoles.size),
            open = BossFooterSection.ROLES in open,
            onToggle = { onToggle(BossFooterSection.ROLES) },
        ) { RoleOverview(index) }
    }
    item(key = "footer-tiers", contentType = "footer-disclosure") {
        BossDisclosure(
            title = "人数缩放档位说明（${index.scalingGroups.size} 档）",
            open = BossFooterSection.TIERS in open,
            onToggle = { onToggle(BossFooterSection.TIERS) },
        ) { ScalingTiers(index) }
    }
    if (dataset.mutationCategories.isNotEmpty()) {
        item(key = "footer-mutations", contentType = "footer-disclosure") {
            BossDisclosure(
                title = "${dataset.mutationTitle}出现只数（${dataset.mutationCategories.size} 行）",
                open = BossFooterSection.MUTATIONS in open,
                onToggle = { onToggle(BossFooterSection.MUTATIONS) },
            ) { MutationCounts(index) }
        }
    }
    if (dataset.deepOfNightDepths.isNotEmpty()) {
        item(key = "footer-depths", contentType = "footer-disclosure") {
            BossDisclosure(
                title = "${dataset.deepOfNightText.depthTitle}概览（${dataset.deepOfNightDepths.size} 档）",
                open = BossFooterSection.DEPTHS in open,
                onToggle = { onToggle(BossFooterSection.DEPTHS) },
            ) { DepthOverview(index) }
        }
    }
    index.hiddenSummary?.let { summary ->
        item(key = "footer-hidden", contentType = "footer-note") {
            BossNoteBox(modifier = Modifier.padding(top = 8.dp)) {
                Text(summary, style = MaterialTheme.typography.bodySmall, color = NightColors.TextSecondary)
            }
        }
    }
    val unmatched = dataset.notes?.unmatchedNames.orEmpty()
    if (unmatched.isNotEmpty()) {
        item(key = "footer-unmatched", contentType = "footer-note") {
            BossNoteBox(modifier = Modifier.padding(top = 8.dp), tint = NightColors.Amber, alpha = 0.06f) {
                Text(
                    "以下 ${unmatched.size} 组首领在本作游戏文本里查不到简中词条" +
                        "（其中一部分另有《艾尔登法环》的参考译名，主标题用它并已标注「" +
                        BossRowText.nameFallbackBadge + "」，搜索也认这些旧译名；其余只能显示英文名）：",
                    style = MaterialTheme.typography.bodySmall,
                    color = NightColors.TextSecondary,
                )
                unmatched.forEach { BossDetailLine(it.nameEn, "chrId ${it.chrId}", NightColors.TextSecondary) }
            }
        }
    }
    val multi = index.multiGroupCards
    if (multi.isNotEmpty()) {
        item(key = "footer-multi", contentType = "footer-note") {
            Text(
                BossRoleText.multiGroupNote(multi.size, multi.map { it.displayName }),
                modifier = Modifier.padding(top = 8.dp),
                style = MaterialTheme.typography.bodySmall,
                color = NightColors.TextSecondary,
            )
        }
    }
    item(key = "footer-version", contentType = "footer-note") {
        BossNoteBox(modifier = Modifier.padding(top = 8.dp)) {
            BossDetailLine("游戏版本", dataset.gameVersion)
            BossDetailLine("数据版本", dataset.dataVersion)
            if (dataset.generatedAt.isNotEmpty()) BossDetailLine("生成时间", dataset.generatedAt)
            BossDetailLine("数据集结构版本", "bossesSchemaVersion ${dataset.schemaVersion}")
            BossDetailLine("收录", index.inventorySummary)
            dataset.sources.forEach { source ->
                BossDetailLine(source.name, source.revision.ifEmpty { source.license }, NightColors.TextSecondary)
            }
        }
    }
}

/** 「出场场合说明」：为什么「威胁档位」和分组对不上，每个场合归哪个分组、多少组、怎么判定。 */
@Composable
private fun RoleOverview(index: BossDataIndex) {
    val dataset = index.dataset
    BossNoteBox(tint = NightColors.Amber, alpha = 0.06f) {
        Text(BossRoleText.threatTierNote + "。", style = MaterialTheme.typography.bodySmall, color = NightColors.Amber, fontWeight = FontWeight.SemiBold)
    }
    index.roleOverviewRows().forEach { row ->
        Column(verticalArrangement = Arrangement.spacedBy(3.dp), modifier = Modifier.padding(vertical = 2.dp)) {
            BossFlow {
                RolePill(
                    BossRoleBadge(
                        role = row.role,
                        title = row.title,
                        group = row.group,
                        hidden = row.role in BossRoleCatalog.hiddenRoles,
                        current = true,
                    ),
                )
                Text("→ " + row.groupText, style = MaterialTheme.typography.labelLarge, color = NightColors.TextSecondary)
                Text(row.countText, style = MaterialTheme.typography.labelSmall, color = NightColors.TextMuted)
            }
            if (row.en.isNotEmpty()) {
                Text(row.en, style = MaterialTheme.typography.labelSmall, color = NightColors.TextMuted)
            }
            if (row.description.isNotEmpty()) {
                Text(row.description, style = MaterialTheme.typography.labelSmall, color = NightColors.TextMuted)
            }
        }
    }
    val audit = dataset.notes?.roleAuditSummary.orEmpty()
    if (audit.isNotEmpty()) {
        Text(BossRoleText.auditTitle(audit.size), style = MaterialTheme.typography.labelLarge, color = NightColors.TextPrimary)
        audit.forEach { BossBullet(it) }
    }
}

/** 「人数缩放档位说明」：结论 + 逐项核实 + 全部档位的倍率表（首列固定，其余横滚，所有档位同步）。 */
@Composable
private fun ScalingTiers(index: BossDataIndex) {
    Text(
        "人数缩放来自 MultiPlayCorrectionParam：血量按档位倍率上浮，" +
            "承受削韧与削韧恢复下调（更难打断），异常发动伤害与累积量下调（更难触发）。" +
            "异常累积量倍率越小越难打出异常，不是阈值下调——触发阈值本身不随人数变化。",
        style = MaterialTheme.typography.bodySmall,
        color = NightColors.TextSecondary,
    )
    BossNoteBox(tint = NightColors.Amber, alpha = 0.06f) {
        Text(BossRowText.multiplayerAuditSummary, style = MaterialTheme.typography.bodySmall, color = NightColors.Amber, fontWeight = FontWeight.SemiBold)
    }
    val audit = index.dataset.notes?.multiplayerScalingAudit.orEmpty()
    if (audit.isNotEmpty()) {
        Text("逐项核实（数据集 notes.multiplayerScalingAudit，${audit.size} 条）", style = MaterialTheme.typography.labelLarge, color = NightColors.TextPrimary)
        audit.forEach { BossBullet(it) }
    }
    val scroll = rememberScrollState()
    val header = listOf("档位 · 人数", "血量", "攻击力", "承受削韧", "削韧恢复", "异常累积", "异常发动伤害")
    // 表头只画一次；各档位的小表共用同一个 ScrollState，横滚时整张表同步
    BossScrollTable(header = header, rows = emptyList(), scroll = scroll, firstColumnWidth = 104.dp, columnWidth = 80.dp)
    index.scalingGroups.forEach { tier ->
        Column(verticalArrangement = Arrangement.spacedBy(3.dp)) {
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                Text("#${tier.id}", style = MaterialTheme.typography.labelLarge.tabular(), color = NightColors.PurpleSoft, fontWeight = FontWeight.Bold)
                Text(tier.title, style = MaterialTheme.typography.labelSmall, color = NightColors.TextSecondary, modifier = Modifier.padding(top = 1.dp))
            }
            val rows = listOf("2 人" to tier.duo, "3 人" to tier.trio).map { (label, value) ->
                if (value == null) listOf(label, "无数据") else listOf(label) + tierValues(value)
            }
            BossScrollTable(
                header = header,
                rows = rows,
                scroll = scroll,
                firstColumnWidth = 104.dp,
                columnWidth = 80.dp,
                showHeader = false,
                cellColor = { r, column ->
                    val value = if (r == 0) tier.duo else tier.trio
                    if (column == 2 && value?.raisesAttack == true) NightColors.Red else NightColors.TextPrimary
                },
            )
        }
    }
}

private fun tierValues(tier: BossScalingTier): List<String> = listOf(
    BossFormat.multiplier(tier.hp),
    BossRowText.attackRateText(tier.attackRate),
    BossFormat.multiplier(tier.poiseTaken),
    BossFormat.multiplier(tier.poiseRecover),
    BossFormat.multiplier(tier.buildupRate),
    BossFormat.multiplier(tier.ailmentDamageRate),
)

/** 「变异个体出现只数」：地图 × 深度 → 只数（不是概率），按敌人类别分块；再列变异档位倍率。 */
@Composable
private fun MutationCounts(index: BossDataIndex) {
    val dataset = index.dataset
    val depthWord = dataset.deepOfNightText.depthTitle
    Text(BossRowText.mutationCountNote, style = MaterialTheme.typography.bodySmall, color = NightColors.Amber)
    val scroll = rememberScrollState()
    val header = listOf("地图") + (1..5).map { "$depthWord $it" }
    dataset.orderedMutationCategories.groupBy { it.categoryId }.values.forEach { rows ->
        Column(verticalArrangement = Arrangement.spacedBy(3.dp)) {
            Text(rows.first().categoryTitle, style = MaterialTheme.typography.labelLarge, color = NightColors.TextPrimary, fontWeight = FontWeight.SemiBold)
            BossScrollTable(
                header = header,
                rows = rows.map { row -> listOf(row.mapTitle) + (1..5).map { row.count(it).toString() } },
                scroll = scroll,
                firstColumnWidth = 112.dp,
                columnWidth = 58.dp,
                cellColor = { r, column ->
                    if (column > 0 && rows[r].count(column) == 0) NightColors.TextMuted else NightColors.TextPrimary
                },
            )
        }
    }
    val mutations = dataset.orderedMutations
    if (mutations.isNotEmpty()) {
        Text("变异档位倍率（SpEffectSetParam → 数值档位）", style = MaterialTheme.typography.labelLarge, color = NightColors.TextPrimary)
        BossScrollTable(
            header = listOf("档位", "血量", "攻击", "卢恩", "数值档位"),
            rows = mutations.map { m ->
                listOf(
                    "#${m.id}",
                    BossFormat.multiplier(m.hp, 3),
                    BossFormat.multiplier(m.attackRate, 3),
                    BossFormat.multiplier(m.runeRate, 3),
                    m.statSpEffectId?.let { "#$it" } ?: "—",
                )
            },
            scroll = rememberScrollState(),
            firstColumnWidth = 84.dp,
            columnWidth = 72.dp,
        )
        Text(
            "哪些敌人能变异 = NpcParam.chaosMatchingSpEffectSetParamId != -1 的行（数据集里 mutationPool 非空的即是）。",
            style = MaterialTheme.typography.labelSmall,
            color = NightColors.TextMuted,
        )
    }
}

/** 「深度概览」：ChaosMatchingRankControlParam 只有全局控制项，不含任何血量 / 攻击力倍率。 */
@Composable
private fun DepthOverview(index: BossDataIndex) {
    val dataset = index.dataset
    Text(
        "下面这张表来自 ChaosMatchingRankControlParam，只有全局控制项，" +
            "不含任何血量 / 攻击力倍率；深度对数值的影响请看每条数值行展开后的「深夜各深度」。",
        style = MaterialTheme.typography.bodySmall,
        color = NightColors.TextSecondary,
    )
    val description = dataset.deepOfNightText.description.zh
    if (description.isNotEmpty()) {
        Text(description.replace("\n", " "), style = MaterialTheme.typography.labelSmall, color = NightColors.TextMuted)
    }
    dataset.orderedDepthInfos.forEach { info ->
        Column(verticalArrangement = Arrangement.spacedBy(3.dp), modifier = Modifier.padding(vertical = 2.dp)) {
            Text(info.title, style = MaterialTheme.typography.labelLarge, color = NightColors.TextPrimary, fontWeight = FontWeight.Bold)
            BossDetailLine(
                "诅咒遗物率（罕见 / 稀有）",
                BossFormat.decimal(info.cursedUncommonRate) + " / " + BossFormat.decimal(info.cursedRareRate),
                NightColors.TextSecondary,
            )
            BossDetailLine(
                "地图挑战权重（地图 / 夜王 / 无）",
                listOf(info.mapChallengeWeight.map, info.mapChallengeWeight.nightlord, info.mapChallengeWeight.none)
                    .joinToString(" / ") { BossFormat.decimal(it) },
                NightColors.TextSecondary,
            )
            BossDetailLine(
                "天变数量权重（0 / 1 / 2）",
                (0..2).joinToString(" / ") { (info.cataclysmWeight[it] ?: 0).toString() },
                NightColors.TextSecondary,
            )
        }
    }
    val audit = dataset.notes?.deepOfNightAudit.orEmpty()
    if (audit.isNotEmpty()) {
        Text("逐项核实（数据集 notes.deepOfNightAudit，${audit.size} 条）", style = MaterialTheme.typography.labelLarge, color = NightColors.TextPrimary)
        audit.forEach { BossBullet(it) }
    }
}
