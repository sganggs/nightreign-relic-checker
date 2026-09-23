package com.nightreign.relicchecker.ui.bosses

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.Immutable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.nightreign.relicchecker.gamedata.bosses.BossAilmentKind
import com.nightreign.relicchecker.gamedata.bosses.BossCaptions
import com.nightreign.relicchecker.gamedata.bosses.BossCard
import com.nightreign.relicchecker.gamedata.bosses.BossComputedStats
import com.nightreign.relicchecker.gamedata.bosses.BossDamageKind
import com.nightreign.relicchecker.gamedata.bosses.BossDataIndex
import com.nightreign.relicchecker.gamedata.bosses.BossFight
import com.nightreign.relicchecker.gamedata.bosses.BossFormat
import com.nightreign.relicchecker.gamedata.bosses.BossGroup
import com.nightreign.relicchecker.gamedata.bosses.BossMutation
import com.nightreign.relicchecker.gamedata.bosses.BossMutationChoice
import com.nightreign.relicchecker.gamedata.bosses.BossNameBadge
import com.nightreign.relicchecker.gamedata.bosses.BossNightMode
import com.nightreign.relicchecker.gamedata.bosses.BossPageText
import com.nightreign.relicchecker.gamedata.bosses.BossPartySize
import com.nightreign.relicchecker.gamedata.bosses.BossRateClass
import com.nightreign.relicchecker.gamedata.bosses.BossRoleText
import com.nightreign.relicchecker.gamedata.bosses.BossRowBadge
import com.nightreign.relicchecker.gamedata.bosses.BossRowText
import com.nightreign.relicchecker.gamedata.bosses.BossScalingTier
import com.nightreign.relicchecker.gamedata.bosses.evidenceLines
import com.nightreign.relicchecker.gamedata.bosses.roleBadges
import com.nightreign.relicchecker.gamedata.bosses.statusBadges
import com.nightreign.relicchecker.ui.NightPanel
import com.nightreign.relicchecker.ui.NightPill
import com.nightreign.relicchecker.ui.theme.NightColors

/** 工具条上的全局设置（人数 / 模式 / 变异个体 / 隐藏开关），整组往下传。 */
@Immutable
internal data class BossViewSettings(
    val party: BossPartySize,
    val mode: BossNightMode,
    val mutation: BossMutationChoice,
    val showHidden: Boolean,
    /** 「深度」的游戏文本词。 */
    val depthWord: String,
)

/**
 * 一张首领卡片：折叠态显示当前分组下代表行的概览（血量 / 有效韧性 / 攻击力 / 削韧恢复），
 * 展开后逐行列出数值行。同一张卡可能出现在好几个分组里，代表行跟着 [group] 走。
 */
@Composable
internal fun BossCardView(
    card: BossCard,
    group: BossGroup,
    index: BossDataIndex,
    view: BossViewSettings,
    expanded: Boolean,
    onToggle: () -> Unit,
    evidenceOpen: Set<String>,
    onToggleEvidence: (String) -> Unit,
    modifier: Modifier = Modifier,
) {
    val primary = card.representativeRow(group)
    val shownRows = card.displayRows(view.showHidden)
    val shape = RoundedCornerShape(14.dp)
    NightPanel(
        modifier = modifier.fillMaxWidth(),
        borderColor = if (expanded) NightColors.BorderStrong else NightColors.Border,
        shape = shape,
    ) {
        Column(modifier = Modifier.fillMaxWidth()) {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(shape)
                    .clickable(role = Role.Button, onClickLabel = if (expanded) "收起" else "展开", onClick = onToggle)
                    .padding(14.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                CardTitle(card, expanded)
                CardBadges(card, group, index, view, shownRows.size)
                if (!card.isNightlord) WeaknessNote(card, primary, index)
                BossCaptions.primaryRowNote(card, group, view.party, view.mode, shownRows.size)?.let { (text, warn) ->
                    Text(
                        text,
                        style = MaterialTheme.typography.labelSmall,
                        color = if (warn) NightColors.Amber else NightColors.TextMuted,
                    )
                }
                if (primary == null) {
                    Text("该首领没有可用的数值行。", style = MaterialTheme.typography.bodySmall, color = NightColors.TextMuted)
                } else {
                    SummaryMetrics(card, primary, index, view)
                }
            }
            if (expanded) {
                HorizontalDivider(color = NightColors.Border)
                ExpandedBody(card, group, index, view, shownRows, evidenceOpen, onToggleEvidence)
            }
        }
    }
}

@Composable
private fun CardTitle(card: BossCard, expanded: Boolean) {
    Row(verticalAlignment = Alignment.Top, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(1.dp)) {
            Text(
                card.displayName,
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.Bold,
                color = NightColors.TextPrimary,
            )
            card.subtitleName?.let {
                Text(it, style = MaterialTheme.typography.labelSmall, color = NightColors.TextMuted)
            }
        }
        Chevron(expanded)
    }
}

@Composable
private fun CardBadges(card: BossCard, group: BossGroup, index: BossDataIndex, view: BossViewSettings, shownRows: Int) {
    val dataset = index.dataset
    BossFlow {
        if (card.isNightlord) {
            if (card.expeditionZh.isNotEmpty()) NightPill("远征 · " + card.expeditionZh, NightColors.PurpleSoft)
            if (card.variantNameZh.isNotEmpty()) {
                NightPill(card.variantNameZh, if (card.isEverdark) NightColors.Amber else NightColors.PurpleSoft)
            }
            if (card.weakness.isEmpty()) {
                NightPill(BossPageText.noOfficialWeakness, NightColors.TextMuted)
            } else {
                card.weakness.forEach { NightPill("官方弱点 · " + it.display, NightColors.Green) }
            }
        }
        if (card.hasRoles) {
            dataset.roleBadges(card.roles, group).forEach { RolePill(it) }
        } else {
            NightPill(BossRoleText.rolesMissing, NightColors.TextMuted)
        }
        card.nameBadges.forEach { badge ->
            NightPill(badge.text, if (badge == BossNameBadge.COMMUNITY) NightColors.PurpleSoft else NightColors.Amber)
        }
        if (card.hidden) NightPill(BossRowText.hiddenToggleHelp, NightColors.TextMuted)
        if (view.mode.isDeepOfNight) {
            card.deepCoverage.badgeText?.let { NightPill(it, NightColors.Amber) }
            card.deepOfNightCoverage.exclusiveBadgeText?.let { NightPill(it, NightColors.Amber) }
        }
        Text(
            BossRoleText.rowCount(shownRows, card.hiddenRowCount(view.showHidden)),
            modifier = Modifier.align(Alignment.CenterVertically),
            style = MaterialTheme.typography.labelSmall,
            color = NightColors.TextMuted,
        )
    }
}

/** 守夜 / 野外首领没有官方弱点字段：改给代表行里承伤偏高的属性（绝不写「官方标注：无弱点」）。 */
@Composable
private fun WeaknessNote(card: BossCard, primary: BossFight?, index: BossDataIndex) {
    val hot = card.hotRates(primary)
    if (hot.isEmpty()) {
        Text(BossPageText.nightlordOnlyWeakness, style = MaterialTheme.typography.labelSmall, color = NightColors.TextMuted)
    } else {
        BossFlow {
            Text(
                BossPageText.hotRatesLabel,
                modifier = Modifier.align(Alignment.CenterVertically),
                style = MaterialTheme.typography.labelSmall,
                color = NightColors.TextMuted,
            )
            hot.forEach { (kind, rate) ->
                NightPill(index.dataset.title(kind) + " " + BossFormat.multiplier(rate, 2), NightColors.Amber)
            }
        }
    }
}

private data class MetricSpec(val title: String, val value: String, val caption: String?, val tint: Color)

@Composable
private fun SummaryMetrics(card: BossCard, row: BossFight, index: BossDataIndex, view: BossViewSettings) {
    val mutation = index.dataset.mutationFor(row, view.mutation)
    val stats = row.stats(view.party, view.mode, mutation)
    val metrics = listOf(
        MetricSpec(
            "${BossCaptions.hpMetricTitle(card)}（${view.party.title}）",
            BossFormat.integer(stats.hp),
            BossCaptions.summaryHp(row, view.party, view.mode, view.depthWord, mutation),
            NightColors.PurpleSoft,
        ),
        MetricSpec(
            "有效韧性",
            stats.effectivePoise?.let { BossFormat.decimal(it, 1) } ?: stats.poiseKind.placeholder,
            stats.effectivePoise?.let { "韧性槽 ${BossFormat.decimal(row.poise, 0)}" },
            NightColors.TextPrimary,
        ),
        MetricSpec(
            "攻击力倍率",
            BossFormat.multiplier(stats.attackRate, 3),
            BossCaptions.summaryAttack(view.mode),
            NightColors.Red,
        ),
        MetricSpec("削韧恢复", BossFormat.decimal(stats.poiseRecover, 3), "每秒", NightColors.TextPrimary),
    )
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        BossTwoColumns(metrics) { spec, modifier ->
            BossMetric(spec.title, spec.value, modifier, spec.caption, spec.tint)
        }
        // 多人不只是血条变长：7744 / 7753 / 7754 / 7758 四档敌人攻击力也上浮
        if (stats.tier.raisesAttack) {
            NightPill(BossRowText.multiplayerAttackBadge(stats.tier.attackRate), NightColors.Red)
        }
    }
}

// MARK: - 展开区

@Composable
private fun ExpandedBody(
    card: BossCard,
    group: BossGroup,
    index: BossDataIndex,
    view: BossViewSettings,
    shownRows: List<BossFight>,
    evidenceOpen: Set<String>,
    onToggleEvidence: (String) -> Unit,
) {
    Column(
        modifier = Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 12.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        IdentifierNote(card)
        CardRoleSection(card, group, index)
        NameNotes(card)
        if (card.descriptionZh.isNotEmpty()) {
            BossNoteBox {
                Text(card.descriptionZh, style = MaterialTheme.typography.bodySmall, color = NightColors.TextSecondary)
            }
        }
        card.depthChanceWeights?.let { DepthChance(it, view.depthWord) }
        shownRows.forEach { row ->
            val key = "${group.key}|${card.id}|${row.npcId}"
            FightRowView(
                row = row,
                index = index,
                view = view,
                inGroup = card.rows.size > 1 && row.belongs(group),
                showAllEvidence = key in evidenceOpen,
                onToggleEvidence = { onToggleEvidence(key) },
            )
        }
        val hidden = card.hiddenRowCount(view.showHidden)
        if (hidden > 0) {
            Text(BossRoleText.hiddenRows(hidden), style = MaterialTheme.typography.labelSmall, color = NightColors.TextMuted)
        }
    }
}

/** 守夜 / 野外首领的 chrId 与 NpcName ID，以及「威胁档位」小字（它不决定分组）。 */
@Composable
private fun IdentifierNote(card: BossCard) {
    if (card.isNightlord) return
    Column(verticalArrangement = Arrangement.spacedBy(3.dp)) {
        val ids = buildList {
            if (card.chrIds.isNotEmpty()) add("chrId " + card.chrIds.joinToString(" / "))
            card.npcNameId?.let { add("NpcName #$it") }
            if (card.nameSource.isNotEmpty()) add("名称来源 " + card.nameSource)
        }
        if (ids.isNotEmpty()) {
            Text(ids.joinToString("  ·  "), style = MaterialTheme.typography.labelSmall.tabular(), color = NightColors.TextMuted)
        }
        if (card.tiers.isNotEmpty()) {
            Text(
                BossRoleText.threatTierCaption(card.tiers) + "：" + BossRoleText.threatTierNote,
                style = MaterialTheme.typography.labelSmall,
                color = NightColors.TextMuted,
            )
        }
    }
}

/** 卡片级「出场场合」一览：每个场合涉及几条数值行，当前分组对应哪几行（下方描边高亮）。 */
@Composable
private fun CardRoleSection(card: BossCard, group: BossGroup, index: BossDataIndex) {
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        BossSubHeading(BossRoleText.roleSectionTitle)
        if (!card.hasRoles) {
            Text(BossRoleText.rolesMissing, style = MaterialTheme.typography.bodySmall, color = NightColors.TextMuted)
            return@Column
        }
        val badges = index.dataset.roleBadges(card.roles, group).associateBy { it.role }
        BossFlow {
            card.roleRowCounts().forEach { (role, rows) ->
                badges[role]?.let { RolePill(it, BossPageText.roleRowsChip(it.title, rows)) }
            }
        }
        val here = card.rowsInGroup(group)
        if (card.rows.size > 1 && here > 0) {
            Text(
                BossPageText.currentGroupNote(group.title, here),
                style = MaterialTheme.typography.labelSmall,
                color = NightColors.TextMuted,
            )
        }
    }
}

/** 名字来历：近似匹配的依据、社区认身份、让出同名词条的裁决、参考译名来源，以及组级「不掉奖励」。 */
@Composable
private fun NameNotes(card: BossCard) {
    if (!card.showsNameNotes) return
    BossNoteBox(tint = NightColors.Amber, alpha = 0.05f) {
        if (card.nameNote.isNotEmpty()) {
            Text(card.nameNote, style = MaterialTheme.typography.bodySmall, color = NightColors.TextSecondary)
        }
        card.nameEvidence?.let { BossDetailLine("游戏文本依据", it.summary, NightColors.TextSecondary) }
        card.nameZhRejected?.let { rejected ->
            BossDetailLine("被挡下的候选词条", rejected.summary, NightColors.Amber)
            if (rejected.reason.isNotEmpty()) {
                Text(rejected.reason, style = MaterialTheme.typography.labelSmall, color = NightColors.TextMuted)
            }
        }
        if (card.nameZhFallbackNote.isNotEmpty()) {
            Text(card.nameZhFallbackNote, style = MaterialTheme.typography.labelSmall, color = NightColors.TextMuted)
        }
        if (card.nameSourceUrl.isNotEmpty()) {
            Text(card.nameSourceUrl, style = MaterialTheme.typography.labelSmall, color = NightColors.TextMuted)
        }
        if (card.noReward) {
            Text(BossRowText.noRewardGroupNote, style = MaterialTheme.typography.labelSmall, color = NightColors.TextMuted)
        }
    }
}

/** 夜王各深度出现权重（NightBossMenuParam.depth1..5ChanceWeight）；权重 0 = 该深度不会出现。 */
@Composable
private fun DepthChance(weights: List<Pair<Int, Int>>, depthWord: String) {
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        BossSubHeading("各深度出现权重", "NightBossMenuParam.depth1..5ChanceWeight；权重是相对值，不是百分比")
        BossCellGrid(weights, columns = 5) { (depth, weight), modifier ->
            BossValueCell(
                title = "$depthWord $depth",
                value = if (weight <= 0) "—" else weight.toString(),
                tint = if (weight <= 0) NightColors.TextMuted else NightColors.TextPrimary,
                modifier = modifier,
                fill = if (weight <= 0) NightColors.Amber.copy(alpha = 0.07f) else Color.White.copy(alpha = 0.03f),
            )
        }
        val zero = weights.filter { it.second <= 0 }.map { it.first }
        if (zero.isNotEmpty()) {
            Text(
                zero.joinToString("、") { "$depthWord $it" } + "：" + BossRowText.depthWeightText(0),
                style = MaterialTheme.typography.labelSmall,
                color = NightColors.Amber,
            )
        }
    }
}

/** 单条数值行：数值概览 + 出场场合 + 八种承伤倍率 + 异常抗性 + 深夜各深度 + 变异个体 + 缩放明细。 */
@Composable
private fun FightRowView(
    row: BossFight,
    index: BossDataIndex,
    view: BossViewSettings,
    inGroup: Boolean,
    showAllEvidence: Boolean,
    onToggleEvidence: () -> Unit,
) {
    val dataset = index.dataset
    val mutation = dataset.mutationFor(row, view.mutation)
    val stats = row.stats(view.party, view.mode, mutation)
    val shape = RoundedCornerShape(12.dp)
    NightPanel(
        modifier = Modifier.fillMaxWidth(),
        borderColor = if (inGroup) NightColors.PurpleSoft.copy(alpha = 0.45f) else NightColors.Border,
        shape = shape,
    ) {
        Column(
            modifier = Modifier.fillMaxWidth().padding(10.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            RowTitle(row, index, view, mutation != null)
            val metrics = buildList {
                add(MetricSpec("${view.party.shortTitle}血量", BossFormat.integer(stats.hp), BossCaptions.rowHp(row, stats, view.depthWord), NightColors.PurpleSoft))
                add(
                    MetricSpec(
                        "有效韧性",
                        stats.effectivePoise?.let { BossFormat.decimal(it, 1) } ?: stats.poiseKind.placeholder,
                        BossCaptions.rowPoise(row, stats),
                        NightColors.TextPrimary,
                    ),
                )
                add(MetricSpec("攻击力倍率", BossFormat.multiplier(stats.attackRate, 3), BossCaptions.rowAttack(row, stats), NightColors.Red))
                add(MetricSpec("削韧恢复", BossFormat.decimal(stats.poiseRecover, 3), "基准 ${BossFormat.decimal(row.poiseRecover, 3)}", NightColors.TextPrimary))
                add(
                    MetricSpec(
                        "异常发动伤害",
                        BossFormat.multiplier(stats.ailmentDamageRate),
                        "累积量 " + BossFormat.multiplier(stats.ailmentBuildupRate),
                        NightColors.TextPrimary,
                    ),
                )
                if (mutation != null) {
                    add(MetricSpec("卢恩倍率", BossFormat.multiplier(stats.runeRate, 3), dataset.mutationTitle, NightColors.Red))
                }
            }
            BossTwoColumns(metrics) { spec, modifier -> BossMetric(spec.title, spec.value, modifier, spec.caption, spec.tint) }
            EvidenceSection(row, index, showAllEvidence, onToggleEvidence)
            DamageSection(row, index)
            ResistSection(row, index)
            DepthSection(row, view, mutation)
            if (row.canMutate) MutationSection(row, index, mutation?.id)
            ScalingSection(row, index, view, stats)
        }
    }
}

@Composable
private fun RowTitle(row: BossFight, index: BossDataIndex, view: BossViewSettings, mutationApplied: Boolean) {
    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Row(verticalAlignment = Alignment.Top, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(
                row.displayLabel,
                modifier = Modifier.weight(1f),
                style = MaterialTheme.typography.bodyLarge,
                fontWeight = FontWeight.SemiBold,
                color = NightColors.TextPrimary,
            )
            Text(
                if (row.npcIds.size > 1) "npcId ${row.npcId} 等 ${row.npcIds.size} 行" else "npcId ${row.npcId}",
                style = MaterialTheme.typography.labelSmall.tabular(),
                color = NightColors.TextMuted,
                textAlign = TextAlign.End,
            )
        }
        BossFlow {
            if (row.hasRoles) {
                index.dataset.roleBadges(row.roles).forEach { RolePill(it) }
            } else {
                NightPill(BossRoleText.rolesMissing, NightColors.TextMuted)
            }
            row.statusBadges(view.mode, mutationApplied).forEach { badge ->
                val color = when (badge) {
                    BossRowBadge.MAIN -> NightColors.Green
                    BossRowBadge.MUTATION -> NightColors.Red
                    else -> NightColors.Amber
                }
                NightPill(if (badge == BossRowBadge.MUTATION) index.dataset.mutationTitle else badge.text, color)
            }
        }
        if (row.labelEn.isNotEmpty() && row.labelEn != row.displayLabel) {
            Text(row.labelEn, style = MaterialTheme.typography.labelSmall, color = NightColors.TextMuted)
        }
        row.threatTierCaption?.let {
            Text(it, style = MaterialTheme.typography.labelSmall, color = NightColors.TextMuted)
        }
        if (row.noReward) {
            Text(BossRowText.noRewardRowNote, style = MaterialTheme.typography.labelSmall, color = NightColors.TextMuted)
        }
    }
}

/** 每行「出场场合」小节：逐个场合给出处摘要（第一条 + 另有 N 条），合并行另列「逐行场合」。 */
@Composable
private fun EvidenceSection(row: BossFight, index: BossDataIndex, showAll: Boolean, onToggle: () -> Unit) {
    val dataset = index.dataset
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        BossSubHeading(BossRoleText.roleSectionTitle, BossRoleText.roleSectionDetail)
        if (!row.hasRoles) {
            Text(BossRoleText.rolesMissing, style = MaterialTheme.typography.bodySmall, color = NightColors.TextMuted)
            return@Column
        }
        dataset.evidenceLines(row, showAll).forEach { line ->
            Column(verticalArrangement = Arrangement.spacedBy(3.dp)) {
                RolePill(dataset.roleBadges(listOf(line.role)).single())
                if (line.missing) {
                    Text(BossRoleText.evidenceMissing, style = MaterialTheme.typography.labelSmall, color = NightColors.TextMuted)
                }
                line.items.forEach { item ->
                    Column(modifier = Modifier.padding(start = 4.dp), verticalArrangement = Arrangement.spacedBy(1.dp)) {
                        Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                            item.npcId?.let {
                                Text("行 $it", style = MaterialTheme.typography.labelSmall.tabular(), color = NightColors.Amber, fontWeight = FontWeight.SemiBold)
                            }
                            Text(item.summary, style = MaterialTheme.typography.labelSmall, color = NightColors.TextSecondary, fontWeight = FontWeight.SemiBold)
                        }
                        if (item.note.isNotEmpty()) {
                            Text(
                                item.note,
                                style = MaterialTheme.typography.labelSmall,
                                color = NightColors.TextMuted,
                                maxLines = if (showAll) Int.MAX_VALUE else 2,
                                overflow = TextOverflow.Ellipsis,
                            )
                        }
                        // 手机上没有悬停：地图名与 MSB part 在「展开全部出处」时写出来
                        if (showAll && item.hint.isNotEmpty()) {
                            Text(item.hint, style = MaterialTheme.typography.labelSmall, color = NightColors.TextMuted)
                        }
                    }
                }
                if (line.more > 0) {
                    Text(BossRoleText.evidenceMore(line.more), style = MaterialTheme.typography.labelSmall, color = NightColors.TextMuted)
                }
            }
        }
        if (row.hasMoreEvidence || row.roles.any { role -> row.evidence(role).any { it.note.isNotEmpty() || it.part.isNotEmpty() } }) {
            // 触控区 48dp（PAGES.md §6），文字在其中竖向居中
            Box(
                modifier = Modifier
                    .heightIn(min = 48.dp)
                    .clip(RoundedCornerShape(8.dp))
                    .clickable(role = Role.Button, onClick = onToggle)
                    .padding(horizontal = 4.dp),
                contentAlignment = Alignment.CenterStart,
            ) {
                Text(
                    if (showAll) BossRoleText.evidenceCollapse else BossRoleText.evidenceExpand,
                    style = MaterialTheme.typography.labelLarge,
                    color = NightColors.PurpleSoft,
                )
            }
        }
        dataset.rowRolesSummary(row)?.let {
            Text(it, style = MaterialTheme.typography.labelSmall, color = NightColors.Amber)
        }
    }
}

@Composable
private fun DamageSection(row: BossFight, index: BossDataIndex) {
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        BossSubHeading("承伤倍率", "> 1 为弱点，< 1 为抗性；不随人数变化")
        BossCellGrid(BossDamageKind.entries) { kind, modifier ->
            val value = row.damageRates.value(kind)
            val rate = BossFormat.rateClass(value)
            val tint = when (rate) {
                BossRateClass.WEAK -> NightColors.Green
                BossRateClass.RESIST -> NightColors.Red
                BossRateClass.FLAT -> NightColors.TextSecondary
            }
            BossValueCell(
                title = index.dataset.title(kind),
                value = BossFormat.decimal(value),
                tint = tint,
                modifier = modifier,
                tag = rate.tag ?: "—",
                tagColor = if (rate.tag == null) NightColors.TextMuted else tint,
                fill = tint.copy(alpha = if (rate == BossRateClass.FLAT) 0.04f else 0.10f),
            )
        }
    }
}

@Composable
private fun ResistSection(row: BossFight, index: BossDataIndex) {
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        BossSubHeading("异常抗性", "数值为触发阈值，999 = 免疫；多人只改累积量，不改阈值")
        BossCellGrid(BossAilmentKind.entries) { kind, modifier ->
            val immune = row.resist.isImmune(kind)
            BossValueCell(
                title = index.dataset.title(kind),
                value = if (immune) "免疫" else BossFormat.integer(row.resist.value(kind)),
                tint = if (immune) NightColors.Red else NightColors.TextPrimary,
                modifier = modifier,
                fill = if (immune) NightColors.Red.copy(alpha = 0.10f) else Color.White.copy(alpha = 0.03f),
            )
        }
        val immune = row.immuneKinds()
        if (immune.isNotEmpty()) {
            Text(
                "免疫：" + immune.joinToString(" · ") { index.dataset.title(it) },
                style = MaterialTheme.typography.labelSmall,
                color = NightColors.Red,
            )
        }
    }
}

/** 「深夜各深度」小表：五行按当前人数（与已选变异档位）换算，当前深度高亮；首列固定，其余横滚。 */
@Composable
private fun DepthSection(row: BossFight, view: BossViewSettings, mutation: BossMutation?) {
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        BossSubHeading("深夜各深度", BossCaptions.depthTable(view.party, mutation))
        val rows = row.depthRows(view.party, mutation)
        if (rows.isEmpty()) {
            Text(BossRowText.noDepthStatsText, style = MaterialTheme.typography.bodySmall, color = NightColors.TextMuted)
        } else {
            BossScrollTable(
                header = listOf(view.depthWord, "血量", "攻击倍率", "承受削韧", "有效韧性"),
                rows = rows.map { item ->
                    listOf(
                        "${view.depthWord} ${item.depth}",
                        BossFormat.integer(item.hp),
                        BossFormat.multiplier(item.attackRate, 3),
                        BossFormat.multiplier(item.poiseTaken, 3),
                        item.effectivePoise?.let { BossFormat.decimal(it, 1) } ?: "—",
                    )
                },
                scroll = rememberScrollState(),
                firstColumnWidth = 68.dp,
                columnWidth = 84.dp,
                highlight = { rows[it].depth == view.mode.depth },
                cellColor = { r, column ->
                    when {
                        column == 2 -> NightColors.Red
                        column == 1 && rows[r].depth == view.mode.depth -> NightColors.PurpleSoft
                        column == 1 -> NightColors.TextPrimary
                        else -> NightColors.TextSecondary
                    }
                },
            )
        }
    }
}

/** 「变异个体」块：这一行可能变异成的档位（倍率在其它缩放之上再乘一层）；在工具条里选择后按它计算。 */
@Composable
private fun MutationSection(row: BossFight, index: BossDataIndex, appliedId: Int?) {
    val dataset = index.dataset
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        BossSubHeading(dataset.mutationTitle, BossRowText.mutationStackNote)
        BossNoteBox(tint = NightColors.Red, alpha = if (appliedId == null) 0.04f else 0.09f) {
            dataset.mutations(row).forEach { mutation ->
                val applied = mutation.id == appliedId
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text(
                        "#${mutation.id}",
                        style = MaterialTheme.typography.labelSmall.tabular(),
                        color = if (applied) NightColors.Red else NightColors.TextMuted,
                        fontWeight = FontWeight.SemiBold,
                    )
                    Column(modifier = Modifier.weight(1f)) {
                        Text(mutation.summary, style = MaterialTheme.typography.bodySmall, color = if (applied) NightColors.TextPrimary else NightColors.TextSecondary)
                        mutation.statNameEn?.let {
                            Text(it, style = MaterialTheme.typography.labelSmall, color = NightColors.TextMuted)
                        }
                    }
                }
            }
            Text(
                if (appliedId == null) {
                    "在工具条「${dataset.mutationTitle}」里选择「各行自带档位」或对应档位后，本行数值会按它再乘一层。"
                } else {
                    "已按 #$appliedId 计算：上面的血量 / 攻击力 / 卢恩在当前基础上再乘一层。"
                },
                style = MaterialTheme.typography.labelSmall,
                color = NightColors.TextMuted,
            )
        }
    }
}

@Composable
private fun ScalingSection(
    row: BossFight,
    index: BossDataIndex,
    view: BossViewSettings,
    stats: BossComputedStats,
) {
    val dataset = index.dataset
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        BossSubHeading("多人缩放明细", dataset.scalingCaption(row))
        // 档位名「守夜首领威胁档」挂在场景头目 / 据点首领行上最容易被读成出场位置：只在这种行上补一句
        if (dataset.threatRoleMismatch(row)) {
            Text(BossRoleText.threatTierNote + "。", style = MaterialTheme.typography.labelSmall, color = NightColors.TextMuted)
        }
        val scaling = row.scaling
        if (scaling == null || (scaling.duo == null && scaling.trio == null)) {
            Text("该行没有人数缩放数据，按单人数值处理", style = MaterialTheme.typography.bodySmall, color = NightColors.TextMuted)
        } else {
            val columns = buildList {
                add(BossPartySize.SOLO to BossScalingTier.IDENTITY)
                scaling.duo?.let { add(BossPartySize.DUO to it) }
                scaling.trio?.let { add(BossPartySize.TRIO to it) }
            }
            val labels = listOf("血量", "攻击力", "承受削韧", "削韧恢复速度", "异常发动伤害", "异常累积量", "中毒 / 腐败发动伤害")
            fun values(tier: BossScalingTier) = listOf(
                BossFormat.multiplier(tier.hp),
                BossRowText.attackRateText(tier.attackRate),
                BossFormat.multiplier(tier.poiseTaken),
                BossFormat.multiplier(tier.poiseRecover),
                BossFormat.multiplier(tier.ailmentDamageRate),
                BossFormat.multiplier(tier.buildupRate),
                BossFormat.multiplier(tier.poisonRate),
            )
            val perColumn = columns.map { values(it.second) }
            BossScrollTable(
                // 当前人数那一列表头与数值都着紫色（macOS 的「当前」小标签）
                header = listOf("人数") + columns.map { (party, _) ->
                    if (party == BossPartySize.SOLO) "单人（基准）" else party.shortTitle
                },
                rows = labels.mapIndexed { i, label -> listOf(label) + perColumn.map { it[i] } },
                scroll = rememberScrollState(),
                firstColumnWidth = 118.dp,
                columnWidth = 96.dp,
                headerColor = { column ->
                    if (columns.getOrNull(column - 1)?.first == view.party) NightColors.PurpleSoft else NightColors.TextMuted
                },
                cellColor = { r, column ->
                    val tier = columns.getOrNull(column - 1)
                    when {
                        tier == null -> NightColors.TextSecondary
                        r == 1 && tier.second.raisesAttack -> NightColors.Red
                        tier.first == view.party -> NightColors.PurpleSoft
                        else -> NightColors.TextPrimary
                    }
                },
            )
        }
        if (stats.permScalingIds.isNotEmpty()) {
            BossSubHeading(
                "常驻缩放",
                if (view.mode.isDeepOfNight && row.hasDeepOfNight) "深夜模式下生效的一组" else "已计入上面的血量与韧性",
            )
            Column(verticalArrangement = Arrangement.spacedBy(5.dp)) {
                index.permanentEffects(stats.permScalingIds).forEach { effect ->
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        Text("#${effect.id}", style = MaterialTheme.typography.labelSmall.tabular(), color = NightColors.TextMuted)
                        Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                            BossFlow {
                                Text(effect.displayName, style = MaterialTheme.typography.bodySmall, color = NightColors.TextPrimary, fontWeight = FontWeight.SemiBold)
                                if (effect.deepOfNight) NightPill("仅深夜", NightColors.Amber)
                            }
                            Text(
                                effect.factorParts.ifEmpty { listOf("无数值改动") }.joinToString(" · "),
                                style = MaterialTheme.typography.labelSmall,
                                color = NightColors.TextSecondary,
                            )
                        }
                    }
                }
                index.missingPermanentEffectIds(stats.permScalingIds).forEach { id ->
                    Text("#$id（缺少明细）", style = MaterialTheme.typography.labelSmall.tabular(), color = NightColors.TextMuted)
                }
            }
        }
        BossCaptions.chaosMismatch(row)?.let {
            Text(it, style = MaterialTheme.typography.labelSmall, color = NightColors.TextMuted)
        }
        Text(
            BossCaptions.deepNote(row, view.mode, view.depthWord),
            style = MaterialTheme.typography.labelSmall,
            color = if (row.hasDepthStats) NightColors.Amber else NightColors.TextMuted,
        )
    }
}
