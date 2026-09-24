@file:OptIn(ExperimentalLayoutApi::class, ExperimentalFoundationApi::class)

package com.nightreign.relicchecker.ui.ranker

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.HorizontalDivider
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
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import com.nightreign.relicchecker.gamedata.ranker.BuffFormat
import com.nightreign.relicchecker.gamedata.ranker.DamageComposition
import com.nightreign.relicchecker.gamedata.ranker.HitAction
import com.nightreign.relicchecker.gamedata.ranker.RankerText
import com.nightreign.relicchecker.gamedata.ranker.ResolvedMeans
import com.nightreign.relicchecker.gamedata.ranker.SkillElement
import com.nightreign.relicchecker.gamedata.ranker.SkillHit
import com.nightreign.relicchecker.gamedata.ranker.SkillSegment
import com.nightreign.relicchecker.gamedata.ranker.SkillWeapon
import com.nightreign.relicchecker.gamedata.ranker.SkillWeaponGroup
import com.nightreign.relicchecker.gamedata.ranker.WeaponSourceKind
import com.nightreign.relicchecker.rules.foldedForSearch
import com.nightreign.relicchecker.ui.NightPanel
import com.nightreign.relicchecker.ui.NightPill
import com.nightreign.relicchecker.ui.NightSearchField
import com.nightreign.relicchecker.ui.NightSegmentedControl
import com.nightreign.relicchecker.ui.theme.NightColors

// ① 输出手段：战技／法术（底部抽屉搜索）、战技的武器（底部抽屉，按类别分组）、武器槽、武器基础攻击力；
// 分段命中（小标签勾选 + 明细）；伤害构成（条形图 + 占比）。

@Composable
internal fun OutputCard(
    state: RankerPageState,
    expanded: Boolean,
    onToggle: () -> Unit,
    onPickOutput: () -> Unit,
    onPickWeapon: () -> Unit,
) {
    val resolved = state.resolved
    val output = resolved.output
    val summary = output?.let {
        listOfNotNull(
            it.displayName,
            resolved.weapon?.displayName,
            RankerStrings.hitsCount(resolved.selectedHits.size, resolved.hits.size),
        ).joinToString(" · ")
    }
    RankerSectionCard(
        title = RankerStrings.OUTPUT_TITLE,
        subtitle = RankerStrings.OUTPUT_SUBTITLE,
        summary = summary,
        expanded = expanded,
        onToggle = onToggle,
    ) {
        RankerPickerField(
            text = output?.displayName ?: RankerStrings.OUTPUT_SEARCH,
            subtitle = output?.nameEn,
            placeholder = output == null,
            onClick = onPickOutput,
        )
        if (output == null) {
            RankerNote(RankerStrings.NO_SELECTION)
            return@RankerSectionCard
        }
        val skill = resolved.skill
        val spell = resolved.spell
        if (skill != null) {
            RankerPills(
                buildList {
                    add(RankerText.t("outputClass.skill") to NightColors.PurpleSoft)
                    add(RankerStrings.weaponsAvailable(resolved.weaponGroups.sumOf { it.weapons.size }) to NightColors.TextSecondary)
                    if (skill.sparring) add(RankerStrings.SPARRING to NightColors.Green)
                },
            )
            RankerFieldLabel(RankerStrings.WEAPON_LABEL, trailing = resolved.weapon?.typeLabel)
            val weapon = resolved.weapon
            if (resolved.weaponGroups.isEmpty()) {
                RankerNote(RankerStrings.NO_WEAPON)
            } else {
                RankerPickerField(
                    text = weapon?.let { weaponTitle(it) } ?: RankerStrings.WEAPON_LABEL,
                    subtitle = weapon?.let { attackSummary(it) },
                    placeholder = weapon == null,
                    onClick = onPickWeapon,
                )
            }
        } else if (spell != null) {
            RankerPills(
                listOf(
                    spell.kindLabelZh to (if (spell.isIncantation) NightColors.Amber else RankerPalette.Blue),
                    RankerStrings.mpCost(spell.mp) to NightColors.TextSecondary,
                    RankerStrings.SPELL_FLAT_ONLY to NightColors.TextSecondary,
                ),
            )
        }
        RankerFieldLabel(RankerText.t("handLabel"))
        NightSegmentedControl(
            items = listOf(RankerText.t("hand.1"), RankerText.t("hand.2")),
            selectedIndex = if (state.means.hand == 2) 1 else 0,
            onSelect = { state.setHand(it + 1) },
        )
        RankerNote(RankerText.t("handHelp"))
        resolved.weapon?.let { weapon ->
            WeaponStats(weapon)
            RankerNote(RankerStrings.WEAPON_NOTE)
        }
        if (spell != null) RankerNote(RankerStrings.spellNote(spell.isIncantation))
    }
}

private fun weaponTitle(weapon: SkillWeapon): String =
    weapon.displayName + if (weapon.rarityZh.isNotEmpty()) "（${weapon.rarityZh}）" else ""

/** 「物理 120 · 火 80」（macOS weaponSummary）。 */
private fun attackSummary(weapon: SkillWeapon): String {
    val parts = SkillElement.entries.filter { weapon.attack(it) > 0 }
        .map { it.titleZh + " " + BuffFormat.trim(weapon.attack(it), 0) }
    return parts.ifEmpty { listOf(RankerStrings.NO_BASE_ATTACK) }.joinToString(" · ")
}

@Composable
private fun WeaponStats(weapon: SkillWeapon) {
    FlowRow(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(14.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        SkillElement.entries.forEach { element ->
            val value = weapon.attack(element)
            StatCell(element.titleZh, BuffFormat.trim(value, 0), muted = value <= 0.0)
        }
        StatCell(
            RankerStrings.PHYS_ATTACK_TYPE,
            weapon.atkAttributeZh.ifEmpty { "—" } + " / " + weapon.atkAttribute2Zh.ifEmpty { "—" },
        )
        StatCell(RankerStrings.POISE_BASE, BuffFormat.trim(weapon.poiseDamageBase, 1))
    }
}

@Composable
private fun StatCell(label: String, value: String, muted: Boolean = false) {
    Column(verticalArrangement = Arrangement.spacedBy(1.dp)) {
        Text(label, style = MaterialTheme.typography.labelSmall, color = NightColors.TextMuted)
        Text(
            value,
            style = MaterialTheme.typography.bodyMedium,
            fontWeight = FontWeight.SemiBold,
            color = if (muted) NightColors.TextMuted else NightColors.TextPrimary,
        )
    }
}

// ============================================================ 分段命中

@Composable
internal fun HitsCard(state: RankerPageState, detailOpen: Boolean, onToggleDetail: () -> Unit) {
    val resolved = state.resolved
    val hits = resolved.hits
    NightPanel(modifier = Modifier.fillMaxWidth()) {
        Column(Modifier.fillMaxWidth().padding(14.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(RankerStrings.HITS_TITLE, style = MaterialTheme.typography.titleMedium, modifier = Modifier.weight(1f))
                if (hits.isNotEmpty()) {
                    NightPill(RankerStrings.hitsCount(resolved.selectedHits.size, hits.size), NightColors.PurpleSoft)
                }
            }
            RankerNote(RankerStrings.HITS_SUBTITLE)
            if (hits.isEmpty()) {
                RankerMessage(if (resolved.skill != null) RankerStrings.HITS_EMPTY_SKILL else RankerStrings.HITS_EMPTY_SPELL, NightColors.Amber)
                return@Column
            }
            FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                RankerButton(RankerStrings.HITS_ALL, onClick = { state.hitAction(HitAction.ALL) }, height = 40.dp)
                RankerButton(RankerStrings.HITS_NONE, onClick = { state.hitAction(HitAction.NONE) }, height = 40.dp)
                RankerButton(RankerStrings.HITS_RESET, onClick = { state.hitAction(HitAction.RESET) }, height = 40.dp)
            }
            RankerNote(RankerStrings.HITS_ALL_HELP)
            if (resolved.hasNoFpVariant) {
                RankerSwitchRow(
                    text = RankerStrings.NO_FP_SWITCH,
                    checked = state.means.useNoFp,
                    onCheckedChange = state::setNoFp,
                    detail = RankerStrings.NO_FP_HELP,
                )
            }
            resolved.variant?.let { variant ->
                RankerNote(RankerStrings.variantNote(variant.displayContext ?: "默认", variant.via, variant.atkIds.size))
            }
            FlowRow(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(6.dp),
                verticalArrangement = Arrangement.spacedBy(6.dp),
            ) {
                resolved.segments.forEachIndexed { position, segment ->
                    val hit = hits[position]
                    val on = resolved.isEnabled(hit)
                    RankerChip(
                        text = "${position + 1} · ${segment.displayLabelZh}",
                        selected = on,
                        enabled = !hit.noDamage,
                        color = if (hit.noFp) NightColors.Amber else NightColors.PurpleSoft,
                        onClick = { state.setHit(hit, !on) },
                    )
                }
            }
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .heightIn(min = 44.dp)
                    .clip(RoundedCornerShape(10.dp))
                    .clickable(role = Role.Button, onClick = onToggleDetail),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Chevron(detailOpen)
                Spacer(Modifier.width(8.dp))
                Text(RankerStrings.SEGMENT_DETAIL, style = MaterialTheme.typography.labelLarge, color = NightColors.TextSecondary)
            }
            if (detailOpen) {
                resolved.segments.forEachIndexed { position, segment ->
                    SegmentDetail(position, segment, hits[position], resolved.isEnabled(hits[position]))
                }
            }
            RankerNote(RankerStrings.POISE_HELP)
        }
    }
}

@Composable
private fun SegmentDetail(position: Int, segment: SkillSegment, hit: SkillHit, on: Boolean) {
    RankerRowPanel(selected = on, dimmed = hit.noDamage) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(
                "${position + 1} · ${segment.displayLabelZh}",
                style = MaterialTheme.typography.bodyMedium,
                fontWeight = FontWeight.SemiBold,
                color = if (hit.noDamage) NightColors.TextMuted else NightColors.TextPrimary,
                modifier = Modifier.weight(1f),
            )
            Text("#${segment.atkId}", style = MaterialTheme.typography.labelSmall, color = NightColors.TextMuted)
        }
        val marks = buildList {
            if (hit.noFp) add(RankerStrings.MARK_NO_FP to NightColors.Amber)
            if (hit.isBullet) add(RankerStrings.MARK_BULLET to RankerPalette.Blue)
            if (hit.noDamage) add(RankerStrings.MARK_NO_DAMAGE to NightColors.TextMuted)
            if (hit.addBaseAtk) add(RankerStrings.MARK_ADD_BASE to NightColors.PurpleSoft)
        }
        RankerPills(marks)
        FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalArrangement = Arrangement.spacedBy(5.dp)) {
            val shown = segment.visibleComponents
            shown.forEach { component ->
                val parts = buildList {
                    component.motionPercent?.let { add(BuffFormat.trim(it, 1) + "%") }
                    component.flat?.let { add(RankerStrings.CHIP_FLAT + BuffFormat.trim(it, 1)) }
                    if (component.baseAttack != null) add(RankerStrings.CHIP_BASE_ATTACK)
                }
                val color = RankerPalette.type(component.type)
                Text(
                    component.type.titleZh + " " + parts.joinToString(" · "),
                    style = MaterialTheme.typography.labelSmall,
                    color = color,
                    modifier = Modifier
                        .clip(RoundedCornerShape(6.dp))
                        .background(color.copy(alpha = .12f))
                        .padding(horizontal = 7.dp, vertical = 3.dp),
                )
            }
            if (shown.isEmpty()) {
                Text(RankerStrings.NO_DAMAGE_VALUE, style = MaterialTheme.typography.labelSmall, color = NightColors.TextMuted)
            } else if (segment.hiddenZeroComponentCount > 0) {
                Text(
                    RankerStrings.OTHER_ZERO,
                    style = MaterialTheme.typography.labelSmall,
                    color = NightColors.TextMuted,
                    modifier = Modifier.alpha(.62f).padding(vertical = 3.dp),
                )
            }
        }
        val physical = segment.physicalType?.takeIf { type -> segment.visibleComponents.any { it.type == type } }
        Text(
            listOfNotNull(
                RankerStrings.POISE + " " + BuffFormat.trim(segment.poise, 1),
                RankerStrings.STAMINA + " " + BuffFormat.trim(segment.stamina, 1),
                physical?.let { RankerStrings.PHYS_TYPE + " " + it.titleZh },
            ).joinToString(" · "),
            style = MaterialTheme.typography.labelSmall,
            color = NightColors.TextSecondary,
        )
        if (hit.noDamage) RankerNote(RankerStrings.NO_DAMAGE_HELP)
    }
}

// ============================================================ 伤害构成

@Composable
internal fun CompositionCard(state: RankerPageState) {
    val composition = state.resolved.composition
    NightPanel(modifier = Modifier.fillMaxWidth()) {
        Column(Modifier.fillMaxWidth().padding(14.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Text(RankerStrings.COMP_TITLE, style = MaterialTheme.typography.titleMedium)
            RankerNote(RankerStrings.COMP_SUBTITLE)
            if (!composition.hasDamage) {
                RankerMessage(RankerStrings.COMP_EMPTY, NightColors.Amber)
            } else {
                CompositionBar(composition)
                Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    composition.breakdown.forEach { share ->
                        LegendRow(share.type.titleZh, RankerPalette.type(share.type), share.share, share.amount)
                    }
                }
                val physical = composition.physicalShare
                RankerPills(
                    listOf(
                        RankerStrings.physicalTotal(BuffFormat.percent(physical)) to NightColors.TextSecondary,
                        RankerStrings.elementTotal(BuffFormat.percent(1.0 - physical)) to NightColors.TextSecondary,
                        RankerStrings.relativeTotal(BuffFormat.trim(composition.total, 1)) to NightColors.TextSecondary,
                    ),
                )
            }
            Text(
                buildAnnotatedString {
                    append(RankerStrings.COMP_NOTE_PREFIX)
                    withStyle(SpanStyle(fontWeight = FontWeight.SemiBold)) { append(RankerStrings.COMP_NOTE_STRONG) }
                    append(RankerStrings.COMP_NOTE_SUFFIX)
                },
                style = MaterialTheme.typography.bodySmall,
                color = NightColors.Amber,
            )
            // 攻击情境：当前输出类别下数据里实际要求过的（勾选后，只在该情境成立的倍率才计入）
            val contexts = state.contextOptions
            if (contexts.isNotEmpty()) {
                RankerFieldLabel(RankerText.t("contextsLabel"))
                FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    contexts.forEach { option ->
                        RankerChip(
                            text = option.zh,
                            trailing = option.count.toString(),
                            selected = option.key in state.means.attackContexts,
                            color = NightColors.Amber,
                            onClick = { state.toggleContext(option.key) },
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun CompositionBar(composition: DamageComposition) {
    val parts = composition.breakdown
    Canvas(
        Modifier
            .fillMaxWidth()
            .height(14.dp)
            .clip(RoundedCornerShape(4.dp))
            .background(NightColors.Field),
    ) {
        var x = 0f
        val gap = 1.dp.toPx()
        parts.forEachIndexed { index, part ->
            val width = (size.width * part.share.toFloat()).coerceAtLeast(1f)
            val drawn = if (index < parts.size - 1) (width - gap).coerceAtLeast(1f) else width
            drawRect(RankerPalette.type(part.type), topLeft = Offset(x, 0f), size = Size(drawn, size.height))
            x += width
        }
    }
}

@Composable
private fun LegendRow(name: String, color: androidx.compose.ui.graphics.Color, share: Double, amount: Double) {
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        Box(Modifier.size(10.dp).background(color, RoundedCornerShape(2.dp)))
        Text(name, style = MaterialTheme.typography.bodySmall, color = NightColors.TextPrimary, modifier = Modifier.width(88.dp), maxLines = 1)
        Canvas(Modifier.weight(1f).height(8.dp)) {
            val radius = CornerRadius(3.dp.toPx())
            drawRoundRect(NightColors.FieldSoft, cornerRadius = radius)
            drawRoundRect(
                color.copy(alpha = .78f),
                size = Size((size.width * share.toFloat()).coerceAtLeast(2.dp.toPx()), size.height),
                cornerRadius = radius,
            )
        }
        Text(
            BuffFormat.percent(share),
            style = MaterialTheme.typography.bodySmall,
            fontWeight = FontWeight.SemiBold,
            color = NightColors.TextPrimary,
            modifier = Modifier.width(52.dp),
            textAlign = TextAlign.End,
        )
        Text(
            BuffFormat.trim(amount, 1),
            style = MaterialTheme.typography.labelSmall,
            color = NightColors.TextMuted,
            modifier = Modifier.width(48.dp),
            textAlign = TextAlign.End,
            maxLines = 1,
        )
    }
}

// ============================================================ 抽屉：输出手段 / 武器

@Composable
internal fun OutputPickerSheet(state: RankerPageState, onDone: () -> Unit) {
    val current = state.resolved.output
    var spellKind by rememberSaveable { mutableStateOf(current?.isSkill == false) }
    var query by rememberSaveable { mutableStateOf("") }
    val list = remember(spellKind, query) {
        val needle = query.foldedForSearch()
        state.skills.outputs.filter { it.isSkill != spellKind && it.matches(needle) }
    }
    Column(Modifier.fillMaxWidth().padding(horizontal = 16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        RankerSheetHeader(RankerStrings.OUTPUT_TITLE, RankerStrings.OUTPUT_SUBTITLE, RankerStrings.countPill(list.size))
        NightSegmentedControl(
            items = listOf(RankerStrings.KIND_SKILL, RankerStrings.KIND_SPELL),
            selectedIndex = if (spellKind) 1 else 0,
            onSelect = { spellKind = it == 1 },
            height = 38.dp,
        )
        NightSearchField(query, { query = it }, placeholder = RankerStrings.OUTPUT_SEARCH)
        LazyColumn(Modifier.heightIn(min = 300.dp, max = 590.dp)) {
            if (list.isEmpty()) item(key = "empty") { RankerNote(RankerStrings.OUTPUT_EMPTY, Modifier.padding(vertical = 12.dp)) }
            items(list, key = { it.id }) { output ->
                RankerPickRow(
                    title = output.displayName,
                    subtitle = listOf(
                        output.nameEn,
                        if (output.isSkill) RankerStrings.weaponCount(output.weaponCount) else RankerStrings.mpCost(output.mp ?: 0),
                    ).filter { it.isNotEmpty() }.joinToString(" · "),
                    selected = output.id == current?.id,
                    onClick = {
                        state.selectOutput(output)
                        onDone()
                    },
                    trailing = {
                        NightPill(
                            output.badgeZh,
                            when {
                                output.isSkill -> NightColors.PurpleSoft
                                output.outputClass.key == "incantation" -> NightColors.Amber
                                else -> RankerPalette.Blue
                            },
                        )
                    },
                )
                HorizontalDivider(color = NightColors.Border.copy(alpha = .6f))
            }
        }
        Spacer(Modifier.height(14.dp))
    }
}

/**
 * 武器抽屉里的一行（纯数据，页面测试直接校对）：名称（稀有度）、基础攻击力摘要、来源标记（固定战技 / 局内可抽到，
 * 两者都成立只标固定）与局内可抽到的说明（weaponSource.poolHint；固定武器没有）。
 */
internal data class WeaponPickRowModel(
    val weapon: SkillWeapon,
    val title: String,
    val subtitle: String,
    val source: WeaponSourceKind?,
    val mark: String?,
    val hint: String?,
)

/** 抽屉的分组与每一行（组与组内的顺序沿用 ResolvedMeans.weaponGroups：固定武器排前、其余按 id）。 */
internal fun weaponPickGroups(resolved: ResolvedMeans): List<Pair<SkillWeaponGroup, List<WeaponPickRowModel>>> =
    resolved.weaponGroups.map { group ->
        group to group.weapons.map { weapon ->
            val source = resolved.weaponSource(weapon)
            WeaponPickRowModel(
                weapon = weapon,
                title = weaponTitle(weapon),
                subtitle = attackSummary(weapon),
                source = source,
                mark = source?.title,
                hint = if (source == WeaponSourceKind.POOL) RankerText.t("weaponSource.poolHint") else null,
            )
        }
    }

/** 来源标记的颜色：固定＝绿，局内可抽到＝蓝（Windows weaponSourceBadgeHtml 同色）。 */
private fun sourceColor(source: WeaponSourceKind): androidx.compose.ui.graphics.Color = when (source) {
    WeaponSourceKind.FIXED -> NightColors.Green
    WeaponSourceKind.POOL -> RankerPalette.Blue
}

@Composable
internal fun WeaponPickerSheet(state: RankerPageState, onDone: () -> Unit) {
    val resolved = state.resolved
    val groups = remember(resolved) { weaponPickGroups(resolved) }
    Column(Modifier.fillMaxWidth().padding(horizontal = 16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        RankerSheetHeader(
            title = (resolved.output?.displayName ?: "") + " · " + RankerStrings.WEAPON_LABEL,
            subtitle = RankerStrings.WEAPON_NOTE,
            count = RankerStrings.weaponCount(groups.sumOf { it.second.size }),
        )
        // 来源小计（固定战技 N · 局内可抽到 N）与说明：武器列表含局内战技池能抽到这个战技的武器。
        val counts = resolved.weaponSourceCounts
        if (counts.isNotEmpty()) {
            RankerPills(
                WeaponSourceKind.entries.mapNotNull { kind ->
                    counts[kind]?.let { RankerStrings.sourceCount(kind.title, it) to sourceColor(kind) }
                },
            )
            RankerNote(RankerText.t("weaponSource.note"))
        }
        LazyColumn(Modifier.heightIn(min = 300.dp, max = 590.dp)) {
            groups.forEach { (group, rows) ->
                stickyHeader(key = "type-${group.wepTypeZh}") {
                    Text(
                        "${group.wepTypeZh}（${group.weapons.size}）",
                        style = MaterialTheme.typography.labelLarge,
                        color = NightColors.PurpleSoft,
                        modifier = Modifier
                            .fillMaxWidth()
                            .background(NightColors.Elevated)
                            .padding(vertical = 8.dp),
                    )
                }
                items(rows, key = { "weapon-${it.weapon.id}" }) { row ->
                    RankerPickRow(
                        title = row.title,
                        subtitle = row.subtitle,
                        note = row.hint,
                        selected = row.weapon.id == resolved.weapon?.id,
                        onClick = {
                            state.selectWeapon(row.weapon.id)
                            onDone()
                        },
                        trailing = { row.source?.let { source -> NightPill(source.title, sourceColor(source)) } },
                    )
                }
            }
        }
        Spacer(Modifier.height(14.dp))
    }
}

// ============================================================ 小件

@Composable
internal fun MissingCard() {
    NightPanel(modifier = Modifier.fillMaxWidth(), borderColor = NightColors.Amber.copy(alpha = .4f)) {
        Column(Modifier.fillMaxWidth().padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            NightPill(RankerText.t("noData"), NightColors.Amber, dot = true)
            Text(RankerText.t("loadoutMissing"), style = MaterialTheme.typography.bodyMedium, color = NightColors.TextSecondary)
        }
    }
}

@Composable
internal fun PlainNote(text: String) {
    Text(
        text,
        style = MaterialTheme.typography.bodySmall,
        color = NightColors.TextMuted,
        modifier = Modifier.fillMaxWidth().padding(horizontal = 6.dp, vertical = 4.dp),
    )
}

@Composable
internal fun GroupLabel(title: String, color: androidx.compose.ui.graphics.Color = NightColors.TextSecondary) {
    Text(
        title,
        style = MaterialTheme.typography.labelLarge,
        fontWeight = FontWeight.SemiBold,
        color = color,
        maxLines = 2,
        overflow = TextOverflow.Ellipsis,
        modifier = Modifier.fillMaxWidth().padding(start = 4.dp, top = 6.dp),
    )
}
