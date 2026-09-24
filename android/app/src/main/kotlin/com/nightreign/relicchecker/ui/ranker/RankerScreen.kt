package com.nightreign.relicchecker.ui.ranker

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.Stable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.listSaver
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.nightreign.relicchecker.catalog.AffixCatalog
import com.nightreign.relicchecker.gamedata.GameDataKey
import com.nightreign.relicchecker.gamedata.ranker.EntryState
import com.nightreign.relicchecker.gamedata.ranker.EvaluatedEntry
import com.nightreign.relicchecker.gamedata.ranker.LoadoutIndex
import com.nightreign.relicchecker.gamedata.ranker.OtherRowScore
import com.nightreign.relicchecker.gamedata.ranker.RankerParsers
import com.nightreign.relicchecker.gamedata.ranker.RankerText
import com.nightreign.relicchecker.gamedata.ranker.SkillDataIndex
import com.nightreign.relicchecker.gamedata.ranker.SkillDataset
import com.nightreign.relicchecker.gamedata.ranker.SkillTextZh
import com.nightreign.relicchecker.gamedata.ranker.SummaryColumn
import com.nightreign.relicchecker.gamedata.ranker.WeaponAffixRow
import com.nightreign.relicchecker.rules.foldedForSearch
import com.nightreign.relicchecker.ui.DataPage
import com.nightreign.relicchecker.ui.NightBottomSheet
import com.nightreign.relicchecker.ui.NightPill
import com.nightreign.relicchecker.ui.UserSettings
import com.nightreign.relicchecker.ui.gamedata.GameDataLayout
import com.nightreign.relicchecker.ui.gamedata.GameDataScreenScaffold
import com.nightreign.relicchecker.ui.gamedata.GameDataState
import com.nightreign.relicchecker.ui.gamedata.rememberGameData
import com.nightreign.relicchecker.ui.gamedata.zip
import com.nightreign.relicchecker.ui.theme.NightColors
import kotlinx.coroutines.launch

/**
 * 「增伤排名」页（数据 → 增伤排名）：选一个战技／法术，再自己组一套局内配置（常规／深夜、局内武器词条、遗物、
 * 护符、其它增益），看总增伤。手机版是一列可折叠的卡片，自上而下：
 * ① 输出手段（战技／法术、武器、武器槽、分段、伤害构成、攻击情境）→ ② 出击模式（各槽位上限与用量）→
 * ③ 局内武器词条 → ④ 遗物 → ⑤ 护符 → ⑥ 其它增益 → ⑦ 汇总（推荐填满、清空、显示不生效项；另有粘在底部的总倍率条）
 * → ⑧ 说明与已知局限。
 * 选择器一律用底部抽屉。数值与文案口径同桌面端（配置引擎在 :gamedata 的 ranker 包，文案走 RankerText / LoadoutText）。
 */
@Suppress("UNUSED_PARAMETER")
@Composable
internal fun RankerScreen(
    catalog: AffixCatalog,
    settings: UserSettings,
    onBack: (() -> Unit)?,
    modifier: Modifier = Modifier,
) {
    val skills = rememberGameData(GameDataKey.SKILLS, RankerParsers.SKILLS_ID, RankerParsers::skills)
    // buffs 解析 + 配置页索引（与词条库对照）一起在 IO 线程建好，进程级缓存。
    val loadout = rememberGameData(GameDataKey.BUFFS, RANKER_LOADOUT_PARSER_ID) { text ->
        LoadoutIndex(RankerParsers.buffs(text), catalog.affixes)
    }
    val state = skills.zip(loadout)
    GameDataScreenScaffold(
        title = DataPage.RANKER.title,
        subtitle = DataPage.RANKER.eyebrow,
        onBack = onBack,
        state = state,
        modifier = modifier,
        loadingLabel = RankerStrings.LOADING,
        statusPills = {
            NightPill("参数表 1.03.5", NightColors.TextMuted)
            (state as? GameDataState.Ready)?.value?.let { (skillIndex, index) ->
                NightPill(skillIndex.summary, NightColors.Green)
                NightPill(index.ranker.summary, NightColors.PurpleSoft)
            }
        },
    ) { (skillIndex, index) ->
        RankerContent(skillIndex, index)
    }
}

/** 分区与子块的开合状态（存成字符串集合，rememberSaveable 可存）。 */
@Stable
internal class RankerToggles(initial: Set<String>) {
    var keys: Set<String> by mutableStateOf(initial)
        private set

    operator fun contains(key: String): Boolean = key in keys

    fun toggle(key: String) {
        keys = if (key in keys) keys - key else keys + key
    }

    fun add(key: String) {
        if (key !in keys) keys = keys + key
    }

    companion object {
        val Saver = listSaver<RankerToggles, String>(save = { it.keys.toList() }, restore = { RankerToggles(it.toSet()) })
    }
}

/** 底部抽屉要选什么（存成字符串，rememberSaveable 可存）。 */
internal sealed interface RankerSheet {
    data object Output : RankerSheet
    data object Weapon : RankerSheet
    data class Fixed(val card: Int) : RankerSheet
    data class Affix(val card: Int, val row: Int) : RankerSheet
    data class Curse(val card: Int, val row: Int) : RankerSheet
    data class Talisman(val slot: Int) : RankerSheet

    fun encode(): String = when (this) {
        Output -> "output"
        Weapon -> "weapon"
        is Fixed -> "fixed:$card"
        is Affix -> "affix:$card:$row"
        is Curse -> "curse:$card:$row"
        is Talisman -> "acc:$slot"
    }

    companion object {
        fun decode(text: String?): RankerSheet? {
            val parts = text?.split(':') ?: return null
            val a = parts.getOrNull(1)?.toIntOrNull()
            val b = parts.getOrNull(2)?.toIntOrNull()
            return when (parts[0]) {
                "output" -> Output
                "weapon" -> Weapon
                "fixed" -> a?.let { Fixed(it) }
                "affix" -> if (a != null && b != null) Affix(a, b) else null
                "curse" -> if (a != null && b != null) Curse(a, b) else null
                "acc" -> a?.let { Talisman(it) }
                else -> null
            }
        }
    }
}

/** 页面列表里的一项（LazyColumn 的 key / contentType 都从这里取）。 */
internal sealed class RankerItem(val key: String, val type: String) {
    object Output : RankerItem("output", "output")
    object Hits : RankerItem("hits", "hits")
    object Composition : RankerItem("composition", "composition")
    object Missing : RankerItem("missing", "missing")
    object Mode : RankerItem("mode", "mode")
    object WeaponHeader : RankerItem("wa-header", "wa-header")
    class WeaponRow(val row: WeaponAffixRow) : RankerItem("wa-${row.affix.id}", "wa-row")
    class Plain(key: String, val text: String) : RankerItem(key, "plain")
    object RelicHeader : RankerItem("relic-header", "relic-header")
    class RelicCard(val index: Int) : RankerItem("relic-$index", "relic-card")
    object TalismanHeader : RankerItem("acc-header", "acc-header")
    class TalismanSlot(val slot: Int) : RankerItem("acc-$slot", "acc-slot")
    object OtherHeader : RankerItem("other-header", "other-header")
    class OtherSlot(val slot: String, val shown: Int, val searching: Boolean) : RankerItem("other-slot-$slot", "other-slot")
    class OtherGroup(slot: String, val title: String) : RankerItem("other-group-$slot-$title", "group")
    class OtherRow(val row: OtherRowScore) : RankerItem("other-row-${row.row.key}", "other-row")
    object SummaryHeader : RankerItem("summary", "summary")
    /** [defaultOpen]：默认展开的块记在「被折叠」集合里，默认折叠的记在「被展开」集合里。 */
    class SummaryLabel(key: String, val text: String, val open: Boolean, val toggleKey: String, val defaultOpen: Boolean) :
        RankerItem(key, "summary-label")
    class SummaryGroup(key: String, val column: SummaryColumn) : RankerItem(key, "group")
    class SummaryRow(key: String, val item: EvaluatedEntry) : RankerItem(key, "summary-row")
    object NotesHeader : RankerItem("notes", "notes")
    class NoteBlock(val id: String, val title: String, val pill: String?, val open: Boolean) : RankerItem("note-$id", "note-block")
    class NoteBody(key: String, val title: String?, val text: String, val bullet: Boolean) : RankerItem(key, "note-body")
}

internal object RankerKeys {
    const val OUTPUT = "s-output"
    const val MODE = "s-mode"
    const val WEAPON = "s-wa"
    const val RELIC = "s-relic"
    const val TALISMAN = "s-acc"
    const val OTHER = "s-other"
    const val SUMMARY = "s-summary"
    const val NOTES = "s-notes"
    const val SUM_COUNTED = "sum-counted"
    const val SUM_UNCOUNTED = "sum-uncounted"
    const val HITS_DETAIL = "hits-detail"

    fun otherSlot(slot: String) = "other:$slot"
    fun note(id: String) = "note:$id"
}

@Composable
private fun RankerContent(skills: SkillDataIndex, index: LoadoutIndex) {
    val state = rememberSaveable(skills, index, saver = RankerPageState.saver(skills, index)) {
        RankerPageState.create(skills, index)
    }
    val rows = rememberRankerRows(state)
    val listState = rememberLazyListState()
    val scope = rememberCoroutineScope()
    // 分区默认展开（记被折叠的），子块默认折叠（记被展开的）；汇总的「生效条目」默认展开。
    val closed = rememberSaveable(saver = RankerToggles.Saver) { RankerToggles(emptySet()) }
    val open = rememberSaveable(saver = RankerToggles.Saver) { RankerToggles(emptySet()) }
    var waQuery by rememberSaveable { mutableStateOf("") }
    var otherQuery by rememberSaveable { mutableStateOf("") }
    var sheetKey by rememberSaveable { mutableStateOf<String?>(null) }
    val sheet = RankerSheet.decode(sheetKey)
    val openSheet: (RankerSheet) -> Unit = { sheetKey = it.encode() }

    val items = buildItems(state, rows, closed, open, waQuery, otherQuery)
    val summaryIndex = items.indexOfFirst { it === RankerItem.SummaryHeader }

    Column(Modifier.fillMaxSize()) {
        LazyColumn(
            state = listState,
            modifier = Modifier.fillMaxWidth().weight(1f),
            contentPadding = GameDataLayout.listPadding(bottom = 20.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            items(items, key = { it.key }, contentType = { it.type }) { item ->
                when (item) {
                    RankerItem.Output -> OutputCard(
                        state = state,
                        expanded = RankerKeys.OUTPUT !in closed,
                        onToggle = { closed.toggle(RankerKeys.OUTPUT) },
                        onPickOutput = { openSheet(RankerSheet.Output) },
                        onPickWeapon = { openSheet(RankerSheet.Weapon) },
                    )
                    RankerItem.Hits -> HitsCard(state, detailOpen = RankerKeys.HITS_DETAIL in open, onToggleDetail = { open.toggle(RankerKeys.HITS_DETAIL) })
                    RankerItem.Composition -> CompositionCard(state)
                    RankerItem.Missing -> MissingCard()
                    RankerItem.Mode -> ModeCard(state, expanded = RankerKeys.MODE !in closed, onToggle = { closed.toggle(RankerKeys.MODE) })
                    RankerItem.WeaponHeader -> WeaponAffixHeader(
                        state = state,
                        expanded = RankerKeys.WEAPON !in closed,
                        onToggle = { closed.toggle(RankerKeys.WEAPON) },
                        query = waQuery,
                        onQueryChange = { waQuery = it },
                    )
                    is RankerItem.WeaponRow -> WeaponAffixRowItem(state, item.row)
                    is RankerItem.Plain -> PlainNote(item.text)
                    RankerItem.RelicHeader -> RelicHeader(state, expanded = RankerKeys.RELIC !in closed, onToggle = { closed.toggle(RankerKeys.RELIC) })
                    is RankerItem.RelicCard -> RelicCardItem(state, item.index, openSheet)
                    RankerItem.TalismanHeader -> TalismanHeader(state, expanded = RankerKeys.TALISMAN !in closed, onToggle = { closed.toggle(RankerKeys.TALISMAN) })
                    is RankerItem.TalismanSlot -> TalismanSlotItem(state, item.slot, openSheet)
                    RankerItem.OtherHeader -> OtherHeader(
                        state = state,
                        expanded = RankerKeys.OTHER !in closed,
                        onToggle = { closed.toggle(RankerKeys.OTHER) },
                        query = otherQuery,
                        onQueryChange = { otherQuery = it },
                    )
                    is RankerItem.OtherSlot -> OtherSlotHeader(
                        state = state,
                        slot = item.slot,
                        shown = item.shown,
                        expanded = item.searching || RankerKeys.otherSlot(item.slot) in open,
                        searching = item.searching,
                        onToggle = { open.toggle(RankerKeys.otherSlot(item.slot)) },
                    )
                    is RankerItem.OtherGroup -> GroupLabel(item.title)
                    is RankerItem.OtherRow -> OtherRowItem(state, item.row)
                    RankerItem.SummaryHeader -> SummaryCard(state, expanded = RankerKeys.SUMMARY !in closed, onToggle = { closed.toggle(RankerKeys.SUMMARY) }, scope = scope)
                    is RankerItem.SummaryLabel -> SummaryListLabel(item.text, item.open) {
                        if (item.defaultOpen) closed.toggle(item.toggleKey) else open.toggle(item.toggleKey)
                    }
                    is RankerItem.SummaryGroup -> GroupLabel(item.column.titleZh, RankerPalette.column(item.column))
                    is RankerItem.SummaryRow -> SummaryRowItem(state, item.item)
                    RankerItem.NotesHeader -> NotesHeader(state, expanded = RankerKeys.NOTES !in closed, onToggle = { closed.toggle(RankerKeys.NOTES) })
                    is RankerItem.NoteBlock -> NoteBlockHeader(item.title, item.pill, item.open) { open.toggle(RankerKeys.note(item.id)) }
                    is RankerItem.NoteBody -> NoteBody(item.title, item.text, item.bullet)
                }
            }
        }
        if (state.index.supportsLoadout) {
            RankerSummaryBar(
                state = state,
                onFill = { state.fill(scope) },
                onShowSummary = {
                    if (RankerKeys.SUMMARY in closed) closed.toggle(RankerKeys.SUMMARY)
                    if (summaryIndex >= 0) scope.launch { listState.animateScrollToItem(summaryIndex) }
                },
            )
        }
    }

    sheet?.let { target ->
        NightBottomSheet(onDismissRequest = { sheetKey = null }) {
            val dismiss = { sheetKey = null }
            when (target) {
                RankerSheet.Output -> OutputPickerSheet(state, onDone = dismiss)
                RankerSheet.Weapon -> WeaponPickerSheet(state, onDone = dismiss)
                is RankerSheet.Fixed -> FixedRelicSheet(state, target.card, onDone = dismiss)
                is RankerSheet.Affix -> RelicAffixSheet(state, target.card, target.row, onDone = dismiss)
                is RankerSheet.Curse -> CurseSheet(state, target.card, target.row, onDone = dismiss)
                is RankerSheet.Talisman -> TalismanSheet(state, target.slot, onDone = dismiss)
            }
        }
    }
}

/**
 * 按当前状态列出页面的全部项（只是轻量描述，真正的内容在 LazyColumn 里按需组合）。
 * 折叠的分区只留标题卡；搜索词在这里过滤（候选分数来自后台的 [RankerRows]）。
 */
internal fun buildItems(
    state: RankerPageState,
    rows: RankerRows?,
    closed: RankerToggles,
    open: RankerToggles,
    waQuery: String,
    otherQuery: String,
): List<RankerItem> = buildList {
    add(RankerItem.Output)
    if (RankerKeys.OUTPUT !in closed && state.resolved.output != null) {
        add(RankerItem.Hits)
        add(RankerItem.Composition)
    }
    val index = state.index
    if (!index.supportsLoadout) {
        add(RankerItem.Missing)
    } else {
        val config = state.config
        val caps = state.caps
        val hasComposition = state.hasComposition

        add(RankerItem.Mode)

        // ③ 局内武器词条
        add(RankerItem.WeaponHeader)
        if (RankerKeys.WEAPON !in closed) {
            if (rows == null) {
                add(RankerItem.Plain("wa-loading", "…"))
            } else {
                val needle = waQuery.foldedForSearch()
                val shown = rows.weaponRows.filter { row ->
                    when {
                        config.weaponAffixCount(row.affix.id) > 0 -> true
                        !state.showInactive && !row.score.isUseful(hasComposition) -> false
                        else -> row.affix.matches(needle)
                    }
                }
                if (shown.isEmpty()) add(RankerItem.Plain("wa-empty", RankerText.t("waEmpty")))
                shown.forEach { add(RankerItem.WeaponRow(it)) }
            }
        }

        // ④ 遗物
        add(RankerItem.RelicHeader)
        if (RankerKeys.RELIC !in closed) for (card in 0 until caps.relics) add(RankerItem.RelicCard(card))

        // ⑤ 护符
        add(RankerItem.TalismanHeader)
        if (RankerKeys.TALISMAN !in closed) for (slot in 0 until caps.accessory) add(RankerItem.TalismanSlot(slot))

        // ⑥ 其它增益：按分栏折叠；有搜索词时跨全部分栏列出匹配项
        add(RankerItem.OtherHeader)
        if (RankerKeys.OTHER !in closed) {
            val needle = otherQuery.foldedForSearch()
            val searching = needle.isNotEmpty()
            var matched = 0
            for (slot in LoadoutIndex.OTHER_SLOTS) {
                val slotRows = rows?.otherRows?.get(slot).orEmpty()
                val shown = if (searching) slotRows.filter { it.row.matches(needle) } else slotRows
                if (searching && shown.isEmpty()) continue
                matched += shown.size
                add(RankerItem.OtherSlot(slot, shown.size, searching))
                if (!searching && RankerKeys.otherSlot(slot) !in open) continue
                if (rows == null) {
                    add(RankerItem.Plain("other-loading-$slot", "…"))
                    continue
                }
                if (shown.isEmpty()) {
                    add(RankerItem.Plain("other-empty-$slot", RankerText.t("otherEmpty")))
                    continue
                }
                var lastGroup: String? = null
                for (row in shown) {
                    val group = state.evaluator.otherRowGroup(row, slot)
                    if (group != null && group != lastGroup) {
                        add(RankerItem.OtherGroup(slot, group))
                        lastGroup = group
                    }
                    add(RankerItem.OtherRow(row))
                }
            }
            if (searching && matched == 0) add(RankerItem.Plain("other-nomatch", RankerText.t("overviewNoMatch")))
        }

        // ⑦ 汇总
        add(RankerItem.SummaryHeader)
        if (RankerKeys.SUMMARY !in closed && hasComposition) {
            val result = state.evaluation
            val visible = state.evaluator.visibleItems(result.items, config).filter { item ->
                state.showInactive || (item.state != EntryState.NO && item.state != EntryState.CONTEXT)
            }
            val counted = visible.filter { it.isCounted }
            val uncounted = visible.filter { !it.isCounted }
            val countedOpen = RankerKeys.SUM_COUNTED !in closed
            add(RankerItem.SummaryLabel("sum-counted-label", RankerText.f("summaryCounted", result.counted.size), countedOpen, RankerKeys.SUM_COUNTED, defaultOpen = true))
            if (countedOpen) {
                if (counted.isEmpty()) add(RankerItem.Plain("sum-empty", RankerText.t("summaryEmpty")))
                addGrouped("c", counted)
            }
            if (uncounted.isNotEmpty()) {
                val uncountedOpen = RankerKeys.SUM_UNCOUNTED in open
                add(RankerItem.SummaryLabel("sum-uncounted-label", RankerText.f("summaryUncounted", uncounted.size), uncountedOpen, RankerKeys.SUM_UNCOUNTED, defaultOpen = false))
                if (uncountedOpen) addGrouped("u", uncounted)
            }
            val hidden = result.hiddenCount
            if (!state.showInactive && hidden > 0) {
                add(RankerItem.Plain("sum-hidden", RankerText.f("summaryHiddenNo", hidden, RankerText.t("showInactive"))))
            }
        }
    }

    // ⑧ 说明与已知局限
    add(RankerItem.NotesHeader)
    if (RankerKeys.NOTES !in closed) addNotes(state, open)
}

/** 汇总清单按四栏分组（Windows summaryHtml 的 grouped）。 */
private fun MutableList<RankerItem>.addGrouped(prefix: String, list: List<EvaluatedEntry>) {
    for (column in SummaryColumn.entries) {
        val own = list.filter { it.column == column }
        if (own.isEmpty()) continue
        add(RankerItem.SummaryGroup("sum-$prefix-group-${column.key}", column))
        own.forEachIndexed { position, item -> add(RankerItem.SummaryRow("sum-$prefix-${column.key}-$position-${item.id}", item)) }
    }
}

/**
 * 底部说明的各个折叠块（口径说明、问答、战技数据的已知取舍、战技来源与 TAE 核实（skills usage 原文）、notes 原文、
 * 叠加规则、数据版本）。
 */
private fun MutableList<RankerItem>.addNotes(state: RankerPageState, open: RankerToggles) {
    val dataset = state.index.dataset
    val skills = state.skills.dataset
    fun block(id: String, title: String, pill: String?, body: () -> List<RankerItem>) {
        val isOpen = RankerKeys.note(id) in open
        add(RankerItem.NoteBlock(id, title, pill, isOpen))
        if (isOpen) addAll(body())
    }

    val brief = state.briefNotes
    block("brief", RankerText.t("briefHeading") + "（${brief.size}）", null) {
        brief.mapIndexed { i, text -> RankerItem.NoteBody("note-brief-$i", null, text, bullet = true) }
    }
    if (dataset.userQuestions.isNotEmpty()) {
        block("questions", RankerText.f("questionsTitle", dataset.userQuestions.size), null) {
            dataset.userQuestions.map { q -> RankerItem.NoteBody("note-q-${q.key}", q.key + " · " + q.question, q.answer, bullet = false) }
        }
    }
    block("caveats", RankerStrings.CAVEATS_TITLE, RankerStrings.countPill(skills.caveats.size)) {
        skills.caveats.mapIndexed { i, text ->
            RankerItem.NoteBody("note-caveat-$i", null, SkillTextZh.fpText(text), bullet = true)
        }
    }
    // skills schemaVersion 3 的两节 usage 原文：武器来源（固定 / 局内战技池）与命中段的 TAE 核实。
    skills.usage[SkillDataset.USAGE_WEAPON_SOURCES]?.let { text ->
        block("weapon-sources", RankerStrings.SOURCES_TITLE, RankerStrings.RAW) {
            listOf(
                RankerItem.NoteBody("note-sources-intro", null, RankerStrings.SOURCES_NOTE, bullet = false),
                RankerItem.NoteBody("note-sources-usage", SkillDataset.USAGE_WEAPON_SOURCES, SkillTextZh.fpText(text), bullet = false),
            )
        }
    }
    skills.usage[SkillDataset.USAGE_TAE]?.let { text ->
        block("tae", RankerStrings.TAE_TITLE, if (skills.taeVerified) RankerStrings.TAE_VERIFIED else RankerStrings.TAE_UNVERIFIED) {
            listOf(
                RankerItem.NoteBody("note-tae-intro", null, RankerStrings.TAE_NOTE, bullet = false),
                RankerItem.NoteBody("note-tae-usage", SkillDataset.USAGE_TAE, SkillTextZh.fpText(text), bullet = false),
            )
        }
    }
    val keys = RankerStrings.NOTE_ORDER.map { it.first }.filter { it in dataset.notes } +
        dataset.notes.keys.filter { key -> RankerStrings.NOTE_ORDER.none { it.first == key } }.sorted()
    if (keys.isNotEmpty()) {
        block("buffs-notes", RankerStrings.notesTitle(keys.size), RankerStrings.RAW) {
            keys.mapNotNull { key ->
                dataset.notes[key]?.let { text -> RankerItem.NoteBody("note-buffs-$key", RankerStrings.noteTitle(key), text, bullet = false) }
            }
        }
    }
    if (dataset.stackingRulesZh.isNotEmpty()) {
        block("stacking", RankerStrings.STACKING_TITLE, RankerStrings.RAW) {
            listOf(RankerItem.NoteBody("note-stacking-body", null, dataset.stackingRulesZh, bullet = false))
        }
    }
    block("version", RankerStrings.VERSION_TITLE, skills.gameVersion.ifEmpty { null }) {
        versionLines(state).mapIndexed { i, (label, value) -> RankerItem.NoteBody("note-version-$i", label, value, bullet = false) }
    }
}

/** 「数据版本与来源」（Windows versionHtml 同一组字段）。 */
private fun versionLines(state: RankerPageState): List<Pair<String, String>> {
    val skills = state.skills.dataset
    val buffs = state.index.dataset
    val counts = buffs.counts
    return listOf(
        "游戏版本" to skills.gameVersion.ifEmpty { "—" },
        "数据版本" to skills.dataVersion.ifEmpty { "—" },
        "skills" to "schemaVersion ${skills.schemaVersion} · 武器 ${skills.count("weapons")} · 战技 ${skills.count("skills")}" +
            " · 法术 ${skills.count("spells")} · 分段 ${skills.count("hits")}" +
            (if (skills.taeVerified) RankerStrings.taeVersion(skills.count("hitsNotInvoked")) else ""),
        "buffs" to "schemaVersion ${buffs.schemaVersion} · 增益 ${counts.buffs} 条 · 倍率字段 ${buffs.rateFields.size} 个",
        "v6 字段" to "局内武器词条 ${counts.weaponAffixes} 条 · 固定遗物 ${counts.fixedRelics} 件 · 叠层输入 ${counts.buffsWithStackInput}" +
            " 条 · 互斥键 ${counts.exclusiveKeys} 个",
        "生成时间" to skills.generatedAt.ifEmpty { "—" } + " / " + buffs.generatedAt.ifEmpty { "—" },
    )
}
