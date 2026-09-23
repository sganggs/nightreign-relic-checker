@file:OptIn(ExperimentalLayoutApi::class)

package com.nightreign.relicchecker.ui.ranker

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
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.produceState
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.nightreign.relicchecker.gamedata.ranker.BuffFormat
import com.nightreign.relicchecker.gamedata.ranker.CandidateScore
import com.nightreign.relicchecker.gamedata.ranker.EntryState
import com.nightreign.relicchecker.gamedata.ranker.EvaluatedEntry
import com.nightreign.relicchecker.gamedata.ranker.LoadoutText
import com.nightreign.relicchecker.gamedata.ranker.OtherRowScore
import com.nightreign.relicchecker.gamedata.ranker.RankerText
import com.nightreign.relicchecker.gamedata.ranker.RunMode
import com.nightreign.relicchecker.gamedata.ranker.SummaryColumn
import com.nightreign.relicchecker.gamedata.ranker.TalismanRow
import com.nightreign.relicchecker.gamedata.ranker.WeaponAffixRow
import com.nightreign.relicchecker.ui.NightPill
import com.nightreign.relicchecker.ui.NightSearchField
import com.nightreign.relicchecker.ui.NightSegmentedControl
import com.nightreign.relicchecker.ui.theme.NightColors
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

// ② 出击模式 · ③ 局内武器词条 · ⑤ 护符 · ⑥ 其它增益，以及各处共用的「已放进配置的条目」逐条显示与控件
// （叠层填层数、累积阶梯选层、多档词条选档、占槽位的栏里勾「条件成立」）。

// ============================================================ ② 出击模式

private fun usageColor(used: Int, cap: Int): Color = when {
    used > cap -> NightColors.Red
    cap > 0 && used >= cap -> NightColors.Green
    else -> NightColors.TextSecondary
}

/** 槽位用量的几枚药丸（武器词条 / 深夜专属 / 遗物 / 护符）。 */
internal fun usagePills(state: RankerPageState): List<Pair<String, Color>> {
    val slots = state.evaluation.slots
    val weapon = slots.weaponAffix
    return buildList {
        add(RankerText.t("usageWeaponAffix") + " " + weapon.used + "/" + weapon.cap to usageColor(weapon.used, weapon.cap))
        if (weapon.deepOnlyCap > 0 || weapon.deepOnlyUsed > 0) {
            add(RankerText.t("usageDeepOnly") + " " + weapon.deepOnlyUsed + "/" + weapon.deepOnlyCap to usageColor(weapon.deepOnlyUsed, weapon.deepOnlyCap))
        }
        add(RankerText.t("usageRelic") + " " + slots.relic.text to usageColor(slots.relic.used, slots.relic.cap))
        add(RankerText.t("usageAccessory") + " " + slots.accessory.text to usageColor(slots.accessory.used, slots.accessory.cap))
    }
}

@Composable
internal fun ModeCard(state: RankerPageState, expanded: Boolean, onToggle: () -> Unit) {
    val config = state.config
    val pills = usagePills(state)
    val normal = state.index.caps(RunMode.NORMAL)
    val deep = state.index.caps(RunMode.DEEP)
    RankerSectionCard(
        title = RankerText.t("runModeLabel"),
        summary = config.runMode.titleZh + " · " + pills.joinToString(" · ") { it.first },
        expanded = expanded,
        onToggle = onToggle,
        accent = RankerPalette.DeepBlue,
    ) {
        NightSegmentedControl(
            items = RunMode.entries.map { it.titleZh },
            selectedIndex = RunMode.entries.indexOf(config.runMode),
            onSelect = { state.setRunMode(RunMode.entries[it]) },
        )
        RankerNote(
            RankerText.f(
                "runModeHint", normal.weaponAffix, normal.relics, deep.weaponAffix, deep.deepOnly, deep.relics, deep.relicNormal, deep.relicDeep,
            ),
        )
        RankerPills(pills)
        state.notice?.let { RankerMessage(it, NightColors.Green) }
        val schema = state.index.dataset.schemaVersion ?: 0
        if (schema < 6) RankerMessage(RankerText.f("schemaTooOld", schema), NightColors.Amber)
    }
}

// ============================================================ ③ 局内武器词条

@Composable
internal fun WeaponAffixHeader(
    state: RankerPageState,
    expanded: Boolean,
    onToggle: () -> Unit,
    query: String,
    onQueryChange: (String) -> Unit,
) {
    val usage = state.evaluation.slots.weaponAffix
    val usageText = RankerText.f("waUsage", usage.used, usage.cap)
    val deepText = if (usage.deepOnlyCap > 0) RankerText.f("waDeepOnlyUsage", usage.deepOnlyUsed, usage.deepOnlyCap) else null
    RankerSectionCard(
        title = SummaryColumn.WEAPON_AFFIX.titleZh,
        subtitle = RankerText.f("waIntro", state.caps.maxWeapons),
        summary = listOfNotNull(usageText, deepText).joinToString(" · "),
        expanded = expanded,
        onToggle = onToggle,
        accent = RankerPalette.column(SummaryColumn.WEAPON_AFFIX),
    ) {
        RankerPills(
            listOfNotNull(
                usageText to if (usage.used >= usage.cap) NightColors.Amber else NightColors.PurpleSoft,
                deepText?.let { it to if (usage.deepOnlyUsed >= usage.deepOnlyCap) NightColors.Amber else NightColors.PurpleSoft },
            ),
        )
        val wepType = state.output.attackWepType
        if (wepType == null) {
            RankerNote(RankerText.t("waFilterNone"))
        } else {
            FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                RankerChip(
                    text = RankerText.f("waFilterWeapon", state.index.ranker.wepTypeLabel(wepType)),
                    selected = !state.waFilterAll,
                    onClick = { state.updateWaFilterAll(false) },
                )
                RankerChip(
                    text = RankerText.t("waFilterAll"),
                    selected = state.waFilterAll,
                    onClick = { state.updateWaFilterAll(true) },
                )
            }
        }
        NightSearchField(query, onQueryChange, placeholder = RankerText.t("waSearch"))
        if (state.evaluation.items.any { it.column == SummaryColumn.WEAPON_AFFIX && it.copies > 1 }) {
            RankerNote(RankerText.t("waCopiesHint"), color = NightColors.Amber)
        }
        if (state.index.selectedTierFamilies(state.config).isNotEmpty()) RankerNote(RankerText.t("waTierHint"))
    }
}

/** 候选行的一句原因（不生效写「不生效：…」，其余写状态与原因）。 */
private fun scoreReason(score: CandidateScore): String? = when {
    !score.applicable -> RankerText.t("verdict.no") + "：" + (score.blockedReason ?: RankerText.t("verdictNoFallback"))
    score.state != EntryState.COUNTED && score.reasons.isNotEmpty() -> score.reasons.joinToString("；")
    else -> null
}

@Composable
private fun ScoreReason(score: CandidateScore) {
    val text = scoreReason(score) ?: return
    Text(
        text,
        style = MaterialTheme.typography.bodySmall,
        color = if (score.applicable) NightColors.Amber else NightColors.Red.copy(alpha = .85f),
        maxLines = 4,
        overflow = TextOverflow.Ellipsis,
    )
}

@Composable
internal fun WeaponAffixRowItem(state: RankerPageState, row: WeaponAffixRow) {
    val affix = row.affix
    val config = state.config
    val index = state.index
    val count = config.weaponAffixCount(affix.id)
    val can = index.canAddWeaponAffix(config, affix.id)
    val outside = count > 0 && !affix.matchesType(config.runMode, state.waFilterType)
    val tierSibling = count > 0 && index.selectedTierFamilies(config).any { affix.id in it }
    val badges = buildList {
        addAll(affix.badges)
        if (outside) add(RankerText.t("badges.outsideWeaponType"))
        if (tierSibling) add(RankerText.t("badges.inferredTiers"))
        affix.entries.firstOrNull()?.let { addAll(LoadoutText.entryBadges(it)) }
    }
    val score = row.score
    RankerRowPanel(selected = count > 0, dimmed = !score.applicable && count == 0) {
        // 手机上压成两列：左边「名字 · 徽标 · 原因 · 已用 n」，右边「倍率 · 步进」。
        Row(verticalAlignment = Alignment.Top) {
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(
                    affix.nameZh,
                    style = MaterialTheme.typography.bodyLarge,
                    fontWeight = FontWeight.SemiBold,
                    color = if (score.applicable) NightColors.TextPrimary else NightColors.TextMuted,
                    maxLines = 3,
                    overflow = TextOverflow.Ellipsis,
                )
                RankerBadges(badges)
                ScoreReason(score)
                Text(
                    RankerStrings.usedCount(count) + if (!can.ok && can.reason.isNotEmpty()) " · " + can.reason else "",
                    style = MaterialTheme.typography.labelMedium,
                    color = when {
                        !can.ok && can.reason.isNotEmpty() -> NightColors.Amber
                        count > 0 -> NightColors.PurpleSoft
                        else -> NightColors.TextMuted
                    },
                )
            }
            Spacer(Modifier.width(6.dp))
            Column(horizontalAlignment = Alignment.End, verticalArrangement = Arrangement.spacedBy(2.dp)) {
                RankerScore(
                    score = score.score,
                    counted = score.state == EntryState.COUNTED,
                    hasComposition = state.hasComposition,
                    potential = score.potential,
                    oneStack = score.assumesOneStack,
                    flat = score.flat,
                    modifier = Modifier.widthIn(max = 140.dp),
                )
                RankerStepper(
                    value = count,
                    canDown = count > 0,
                    canUp = can.ok,
                    onDown = { state.stepWeaponAffix(affix.id, -1) },
                    onUp = { state.stepWeaponAffix(affix.id, 1) },
                    upLabel = if (can.ok) RankerText.t("stepUp") else can.reason.ifEmpty { RankerText.t("stepUp") },
                )
            }
        }
        if (count > 0) ItemControlBlock(state, state.itemsFrom("wa:${affix.id}"))
    }
}

// ============================================================ ⑤ 护符

@Composable
internal fun TalismanHeader(state: RankerPageState, expanded: Boolean, onToggle: () -> Unit) {
    val used = state.evaluation.slots.accessory
    val names = state.config.accessories.take(state.caps.accessory).filterNotNull()
        .map { id -> state.index.talismanById[id]?.nameZh ?: "#$id" }
    RankerSectionCard(
        title = SummaryColumn.ACCESSORY.titleZh,
        subtitle = RankerText.f("accIntro", state.caps.accessory),
        summary = (listOf(used.used.toString() + " / " + used.cap) + names).joinToString(" · "),
        expanded = expanded,
        onToggle = onToggle,
        accent = RankerPalette.column(SummaryColumn.ACCESSORY),
    ) {
        RankerPills(
            listOfNotNull(
                "${used.used} / ${used.cap}" to RankerPalette.Blue,
                if (used.used >= used.cap) RankerText.t("accFull") to NightColors.Green else null,
            ),
        )
    }
}

@Composable
internal fun TalismanSlotItem(state: RankerPageState, slot: Int, openSheet: (RankerSheet) -> Unit) {
    val chosen = state.config.accessory(slot)
    val talisman = chosen?.let { state.index.talismanById[it] }
    RankerRowPanel(selected = chosen != null) {
        RankerFieldLabel(RankerText.f("accSlotLabel", slot + 1))
        Row(verticalAlignment = Alignment.CenterVertically) {
            RankerPickerField(
                text = talisman?.nameZh ?: chosen?.let { "#$it" } ?: RankerText.t("accPlaceholder"),
                subtitle = talisman?.subtitle,
                placeholder = chosen == null,
                onClick = { openSheet(RankerSheet.Talisman(slot)) },
                modifier = Modifier.weight(1f),
            )
            if (chosen != null) RankerClearButton(RankerText.t("accRemove"), onClick = { state.removeSource("acc:$slot") })
        }
        if (chosen != null) ItemLines(state, state.itemsFrom("acc:$slot"))
    }
}

@Composable
internal fun TalismanSheet(state: RankerPageState, slot: Int, onDone: () -> Unit) {
    val evaluator = state.evaluator
    val config = state.config
    val rows by produceState<List<TalismanRow>?>(null, evaluator, config) {
        value = withContext(Dispatchers.Default) { evaluator.talismanRows(config) }
    }
    val chosen = config.accessory(slot)
    val hasComposition = state.hasComposition
    val list = rows?.filter { state.showInactive || it.score.isUseful(hasComposition) || it.talisman.id == chosen }
    Column(Modifier.fillMaxWidth().padding(horizontal = 16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        RankerSheetHeader(
            title = RankerText.f("accSlotLabel", slot + 1),
            subtitle = RankerText.f("accIntro", state.caps.accessory),
            count = list?.let { RankerStrings.countPill(it.size) },
        )
        LazyColumn(Modifier.heightIn(min = 300.dp, max = 590.dp)) {
            if (chosen != null) {
                item(key = "remove") {
                    RankerPickRow(title = RankerText.t("accRemove"), onClick = {
                        state.setAccessory(slot, null)
                        onDone()
                    })
                    HorizontalDivider(color = NightColors.Border.copy(alpha = .6f))
                }
            }
            if (list == null) item(key = "loading") { RankerNote("…", Modifier.padding(12.dp)) }
            items(list.orEmpty(), key = { it.talisman.id }) { row ->
                val talisman = row.talisman
                val elsewhere = talisman.id in config.accessories && talisman.id != chosen
                val score = row.score
                RankerPickRow(
                    title = talisman.nameZh + (if (score.applicable) "" else RankerText.t("optionInactive")) +
                        (if (elsewhere) RankerText.t("accUsedElsewhere") else ""),
                    subtitle = listOfNotNull(talisman.subtitle.takeIf { it.isNotEmpty() }, scoreReason(score)).joinToString(" · "),
                    selected = talisman.id == chosen,
                    enabled = !elsewhere,
                    dimmed = !score.applicable,
                    onClick = {
                        state.setAccessory(slot, talisman.id)
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

// ============================================================ ⑥ 其它增益

@Composable
internal fun OtherHeader(
    state: RankerPageState,
    expanded: Boolean,
    onToggle: () -> Unit,
    query: String,
    onQueryChange: (String) -> Unit,
) {
    val picked = state.config.others.size
    RankerSectionCard(
        title = SummaryColumn.OTHER.titleZh,
        subtitle = RankerText.t("otherIntro"),
        summary = if (picked > 0) RankerText.f("summaryCount", picked) else RankerText.t("otherIntro"),
        expanded = expanded,
        onToggle = onToggle,
        accent = RankerPalette.column(SummaryColumn.OTHER),
    ) {
        NightSearchField(query, onQueryChange, placeholder = RankerText.t("otherSearch"))
    }
}

/** 分栏说明：enums.sourceSlot 的 note 去掉粗体标记、取第一句（Windows slotNoteFor）。 */
private fun slotNote(state: RankerPageState, slot: String): String? =
    state.index.dataset.enums.sourceSlotNote[slot]?.replace("**", "")?.split("。")?.firstOrNull()?.takeIf { it.isNotBlank() }

@Composable
internal fun OtherSlotHeader(
    state: RankerPageState,
    slot: String,
    shown: Int,
    expanded: Boolean,
    searching: Boolean,
    onToggle: () -> Unit,
) {
    val color = RankerPalette.slot(slot)
    val rows = state.index.otherRows[slot].orEmpty()
    val picked = rows.count { it.key in state.config.others }
    val count = if (searching) RankerText.f("summaryCount", shown) else (if (picked > 0) "$picked/" else "") + rows.size
    val shape = RoundedCornerShape(12.dp)
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(shape)
            .background(NightColors.FieldSoft)
            .clickable(enabled = !searching, role = Role.Button, onClick = onToggle)
            .padding(horizontal = 12.dp, vertical = 8.dp)
            .semantics { stateDescription = if (expanded) "已展开" else "已折叠" },
        verticalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        Row(Modifier.heightIn(min = 32.dp), verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.size(8.dp).background(color, CircleShape))
            Spacer(Modifier.width(8.dp))
            Text(LoadoutText.slotTitle(slot), style = MaterialTheme.typography.bodyLarge, fontWeight = FontWeight.SemiBold, color = color, modifier = Modifier.weight(1f))
            NightPill(count, if (picked > 0) color else NightColors.TextMuted)
            if (!searching) Chevron(expanded, Modifier.padding(start = 8.dp))
        }
        if (expanded) {
            val innateNote = when {
                slot != "weaponInnate" -> null
                state.evaluator.currentInnateEntries.isNotEmpty() -> RankerText.t("otherInnateHint")
                state.resolved.isSpell -> RankerText.t("otherInnateNoWeapon")
                else -> null
            }
            listOfNotNull(slotNote(state, slot), innateNote).forEach { RankerNote(it) }
        }
    }
}

@Composable
internal fun OtherRowItem(state: RankerPageState, row: OtherRowScore) {
    val selected = state.isOtherSelected(row)
    val score = row.score
    val color = RankerPalette.slot(row.row.slot)
    val skillId = state.resolved.skill?.id
    val badges = buildList {
        if (row.auto) add(RankerText.t("badges.autoInnate"))
        if (row.row.slot == "weaponSkill" && skillId != null &&
            row.row.entries.any { entry -> entry.buff.sources.any { it.artsId == skillId } }
        ) {
            add(RankerText.t("badges.currentSkill"))
        }
        addAll(row.row.badges)
    }
    val toggleLabel = if (row.auto) RankerText.t(if (selected) "innateRemove" else "innateRestore") else RankerText.t("selectUse")
    RankerRowPanel(selected = selected, dimmed = !score.applicable && !selected) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .clip(RoundedCornerShape(8.dp))
                .clickable(role = Role.Checkbox, onClickLabel = toggleLabel) { state.toggleOther(row.row.key, !selected) }
                .semantics { stateDescription = if (selected) "已勾选" else "未勾选" },
            verticalAlignment = Alignment.Top,
        ) {
            RankerCheckMark(selected, Modifier.padding(top = 2.dp), color = color)
            Spacer(Modifier.width(10.dp))
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                Text(
                    row.row.name,
                    style = MaterialTheme.typography.bodyLarge,
                    fontWeight = FontWeight.SemiBold,
                    color = if (score.applicable) NightColors.TextPrimary else NightColors.TextMuted,
                    maxLines = 3,
                    overflow = TextOverflow.Ellipsis,
                )
                if (row.row.subtitle.isNotEmpty()) RankerNote(row.row.subtitle)
                RankerBadges(badges)
            }
            Spacer(Modifier.width(8.dp))
            RankerScore(
                score = score.score,
                counted = score.state == EntryState.COUNTED,
                hasComposition = state.hasComposition,
                potential = score.potential,
                oneStack = score.assumesOneStack,
                flat = score.flat,
            )
        }
        ScoreReason(score)
        // 不占槽位的栏勾选即确认（autoConfirm），只有当前武器固有自动列入的条件型要单独勾「条件成立」。
        if (selected) ItemControlBlock(state, state.itemsForOtherRow(row))
    }
}

// ============================================================ 已放进配置的条目：逐条显示与控件

private val NO_CONTROLS = setOf(EntryState.NO, EntryState.CONTEXT, EntryState.RELIC_INVALID, EntryState.NO_DAMAGE)

/** 这一条要不要给控件（与 Windows itemControlsHtml 同一判定）。 */
internal fun hasControls(state: RankerPageState, item: EvaluatedEntry): Boolean {
    if (item.state in NO_CONTROLS) return false
    val entry = item.entry
    return entry.stackInput != null ||
        (entry.accLadder != null && state.evaluator.isLadderOwner(item, state.config)) ||
        (entry.variantGroup != null && item.state != EntryState.VARIANT_OFF) ||
        (item.needs.isNotEmpty() && !item.autoConfirm)
}

/**
 * 一条已放进配置的增益的控件：叠层填层数、累积阶梯选层、多档词条选档、占槽位的栏里的条件型勾「条件成立」
 * （不占槽位的「其它增益」栏勾选本身就是确认，不再给勾选框）。
 */
@Composable
internal fun ItemControls(state: RankerPageState, item: EvaluatedEntry) {
    if (!hasControls(state, item)) return
    val entry = item.entry
    val config = state.config
    val ranker = state.index.ranker
    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(6.dp)) {
        entry.stackInput?.let { input ->
            val value = config.stacks(entry.id)
            val practical = input.practicalMaxStacks
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(LoadoutText.stackLabel(entry), style = MaterialTheme.typography.labelMedium, color = NightColors.TextSecondary, modifier = Modifier.weight(1f))
                RankerNumberStepper(
                    value = value,
                    max = input.paramMax,
                    onValueChange = { state.setStacks(entry, it) },
                    warn = practical != null && practical > 0 && value > practical,
                )
            }
            RankerNote(LoadoutText.stackHints(entry).joinToString("；"))
        }
        val ladderId = entry.ladderGroup
        if (entry.accLadder != null && ladderId != null && state.evaluator.isLadderOwner(item, config)) {
            val members = ranker.ladderMembers(ladderId)
            val options: List<Pair<Int?, String>> =
                listOf<Pair<Int?, String>>(null to RankerText.t("tierNone")) + members.map { (it.id as Int?) to LoadoutText.tierLabel(it) }
            RankerDropdown(
                label = RankerText.t("tierSelectLabel"),
                options = options,
                selected = ranker.selectedLadderTier(entry, config).id,
                onSelect = { state.setTier(ladderId, it) },
            )
        }
        val group = entry.variantGroup
        if (group != null && item.state != EntryState.VARIANT_OFF) {
            val members = ranker.variantMembers(entry).ifEmpty { listOf(entry) }
            RankerDropdown(
                label = RankerText.t("variantLabel"),
                options = members.mapIndexed { position, member -> member.id to LoadoutText.variantOption(member, position) },
                selected = ranker.selectedVariant(entry, config).id ?: entry.id,
                onSelect = { state.setVariant(group, it) },
            )
            RankerNote(RankerText.t("variantNoMapping"))
        }
        if (item.needs.isNotEmpty() && !item.autoConfirm) {
            RankerCheckRow(
                text = RankerText.t("summaryTick"),
                checked = config.isConfirmed(entry.id),
                onCheckedChange = { state.setTick(entry.id, it) },
                detail = RankerText.t("summaryTickHelp") + "：" + item.needs.joinToString("；"),
                color = NightColors.Amber,
            )
        }
    }
}

/** 候选行选中后的控件（只列有控件的条目；多条时写出条目名）。 */
@Composable
internal fun ItemControlBlock(state: RankerPageState, items: List<EvaluatedEntry>) {
    val visible = state.evaluator.visibleItems(items, state.config).filter { hasControls(state, it) }
    if (visible.isEmpty()) return
    Column(
        Modifier.fillMaxWidth().clip(RoundedCornerShape(10.dp)).background(NightColors.Field).padding(10.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        visible.forEach { item ->
            if (visible.size > 1) Text(item.entry.name, style = MaterialTheme.typography.labelMedium, color = NightColors.TextSecondary)
            item.stackWarnings.forEach { RankerMessage(it, NightColors.Amber) }
            ItemControls(state, item)
        }
    }
}

/** 遗物卡、护符格下的逐条计入情况与控件（Windows relicEffectLinesHtml 同一口径：选层／选档／填层数／「条件成立」就地给出）。 */
@Composable
internal fun ItemLines(state: RankerPageState, items: List<EvaluatedEntry>, label: String? = null) {
    val visible = state.evaluator.visibleItems(items, state.config)
    if (visible.isEmpty()) return
    Column(
        Modifier.fillMaxWidth().clip(RoundedCornerShape(10.dp)).background(NightColors.Field).padding(10.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        label?.let { RankerFieldLabel(it) }
        visible.forEach { item -> ItemLine(state, item) }
    }
}

@Composable
private fun ItemLine(state: RankerPageState, item: EvaluatedEntry) {
    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Row(verticalAlignment = Alignment.Top) {
            Text(
                item.entry.name,
                style = MaterialTheme.typography.bodyMedium,
                color = if (item.isCounted) NightColors.TextPrimary else NightColors.TextSecondary,
                modifier = Modifier.weight(1f),
                maxLines = 3,
                overflow = TextOverflow.Ellipsis,
            )
            Spacer(Modifier.width(6.dp))
            RankerStatePill(item.state)
        }
        val multiplier = item.multiplier
        if (multiplier != null && item.state != EntryState.NO_DAMAGE) {
            Text(
                mul(multiplier) + if (BuffFormat.hasFlat(item.flat)) " · " + RankerText.f("flatInline", BuffFormat.flat(item.flat)) else "",
                style = MaterialTheme.typography.labelMedium,
                color = if (item.isCounted && multiplier > 1.0000001) NightColors.Green else NightColors.TextMuted,
            )
        }
        if (!item.isCounted && item.reasons.isNotEmpty()) {
            Text(item.reasons.joinToString("；"), style = MaterialTheme.typography.bodySmall, color = NightColors.Amber)
        }
        item.stackWarnings.forEach { RankerMessage(it, NightColors.Amber) }
        ItemControls(state, item)
    }
}

/** 汇总里一栏的小计（「局内武器词条 · 2/6」）。 */
internal fun columnSlotText(state: RankerPageState, column: SummaryColumn): String {
    val slots = state.evaluation.slots
    return when (column) {
        SummaryColumn.WEAPON_AFFIX -> slots.weaponAffix.used.toString() + "/" + slots.weaponAffix.cap
        SummaryColumn.RELIC -> slots.relic.text
        SummaryColumn.ACCESSORY -> slots.accessory.text
        SummaryColumn.OTHER -> RankerText.f("summaryCount", state.evaluation.column(column).count)
    }
}
