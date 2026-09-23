package com.nightreign.relicchecker.ui.heroes

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalWindowInfo
import androidx.compose.ui.unit.dp
import com.nightreign.relicchecker.catalog.AffixCatalog
import com.nightreign.relicchecker.gamedata.GameDataKey
import com.nightreign.relicchecker.gamedata.heroes.HeroComparison
import com.nightreign.relicchecker.gamedata.heroes.HeroComparisonColumn
import com.nightreign.relicchecker.gamedata.heroes.HeroStatsCopy
import com.nightreign.relicchecker.gamedata.heroes.HeroStatsIndex
import com.nightreign.relicchecker.gamedata.heroes.HeroesParser
import com.nightreign.relicchecker.ui.DataPage
import com.nightreign.relicchecker.ui.NightPill
import com.nightreign.relicchecker.ui.UserSettings
import com.nightreign.relicchecker.ui.gamedata.GameDataLayout
import com.nightreign.relicchecker.ui.gamedata.GameDataScreenScaffold
import com.nightreign.relicchecker.ui.gamedata.GameDataState
import com.nightreign.relicchecker.ui.gamedata.rememberGameData
import com.nightreign.relicchecker.ui.theme.NightColors

/**
 * 角色属性（数据 → 角色属性）：10 位夜行者 1–15 级的八项属性与派生值，可叠加转职遗物与利普拉的交易，
 * 另有「同级对比」横向表。所有换算都在 :gamedata 的 heroes 包（与 macOS RelicCore/HeroData.swift
 * 逐条对应、JVM 测试钉死），本文件只负责页面状态与布局。
 *
 * 页内状态一律 rememberSaveable（角色 key、等级、勾选的词条 id、利普拉 key、排序列 token、折叠区开关），
 * 切底栏或返回枢纽再进入都保留；每次交互只在 remember 里重算一次快照，不逐帧重算。
 */
@Suppress("UNUSED_PARAMETER")
@Composable
internal fun HeroesScreen(
    catalog: AffixCatalog,
    settings: UserSettings,
    onBack: (() -> Unit)?,
    modifier: Modifier = Modifier,
) {
    val state = rememberGameData(GameDataKey.HEROES, HeroesParser.PARSER_ID, HeroesParser::parse)
    GameDataScreenScaffold(
        title = DataPage.HEROES.title,
        subtitle = DataPage.HEROES.eyebrow,
        onBack = onBack,
        state = state,
        modifier = modifier,
        statusPills = {
            NightPill("参数表 1.03.5", NightColors.TextMuted)
            (state as? GameDataState.Ready)?.let { NightPill(it.value.summary, NightColors.Green, dot = true) }
        },
        loadingLabel = "载入角色属性",
    ) { index ->
        if (index.hasHeroData) {
            HeroesContent(index, Modifier.fillMaxWidth().weight(1f))
        } else {
            HeroesUnavailable()
        }
    }
}

/** 窗口高度（含系统栏）低于它（横屏手机、上下分屏）时工具条改为单行；竖屏手机窗口都在 600dp 以上。 */
private val CompactHeight = 480.dp

/** 页内视图：单角色 / 同级对比（与桌面端同一对文案）。 */
private enum class HeroView(val title: String) {
    SINGLE(HeroStatsCopy.VIEW_SINGLE),
    COMPARE(HeroStatsCopy.VIEW_COMPARE),
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun HeroesContent(index: HeroStatsIndex, modifier: Modifier = Modifier) {
    var viewName by rememberSaveable { mutableStateOf(HeroView.SINGLE.name) }
    var heroKeyState by rememberSaveable { mutableStateOf(index.heroes.first().key) }
    var levelState by rememberSaveable { mutableIntStateOf(index.maxLevel) }
    var allLevels by rememberSaveable { mutableStateOf(false) }
    var modifierIds by rememberSaveable { mutableStateOf(ArrayList<Int>()) }
    var libraKey by rememberSaveable { mutableStateOf("") }
    var sortToken by rememberSaveable { mutableStateOf(HeroComparisonColumn.Hero.token) }
    var sortAscending by rememberSaveable { mutableStateOf(true) }
    var libraSheetOpen by rememberSaveable { mutableStateOf(false) }
    var showNotes by rememberSaveable { mutableStateOf(false) }
    var showCaveats by rememberSaveable { mutableStateOf(false) }
    var showSources by rememberSaveable { mutableStateOf(false) }

    val view = HeroView.valueOf(viewName)
    val hero = index.hero(heroKeyState) ?: index.heroes.first()
    val level = index.clampLevel(levelState)
    val libra = index.libra(libraKey.ifEmpty { null })
    val selectedIds = remember(modifierIds) { modifierIds.toSet() }
    val names = index.statNames

    // 交互驱动的重算：只在输入变化时算一次（remember 键即全部输入）
    val snapshot = remember(index, hero.key, level, selectedIds, libra?.key) {
        index.snapshot(hero.key, level, selectedIds, libra?.key)
    }
    val allSnapshots = remember(index, hero.key, selectedIds, libra?.key, allLevels) {
        if (allLevels) index.snapshots(hero.key, selectedIds, libra?.key) else emptyList()
    }
    val sortColumn = HeroComparisonColumn.fromToken(sortToken)
    val compareRows = remember(index, level, sortColumn, sortAscending, view) {
        if (view == HeroView.COMPARE) HeroComparison.sorted(index.comparisonRows(level), sortColumn, sortAscending) else emptyList()
    }
    val compareMaxima = remember(compareRows) { HeroComparison.columnMaxima(compareRows, names) }
    val levelTableScroll = rememberScrollState()
    val compareTableScroll = rememberScrollState()
    val listState = rememberLazyListState()
    // 横屏手机（窗口高度 < 480dp）：视图切换与等级滑块并成一行，给列表多留约 50dp
    val windowHeight = with(LocalDensity.current) { LocalWindowInfo.current.containerSize.height.toDp() }
    val compactHeight = windowHeight < CompactHeight

    fun selectHero(key: String) {
        if (key == hero.key) return
        heroKeyState = key
        modifierIds = ArrayList() // 转职遗物是逐角色的两条，换角色必须清空勾选
    }

    fun toggleModifier(id: Int) {
        modifierIds = ArrayList(if (id in modifierIds) modifierIds.filter { it != id } else modifierIds + id)
    }

    Column(modifier = modifier) {
        HeroToolbar(
            views = HeroView.entries.map { it.title },
            viewIndex = view.ordinal,
            onView = { viewName = HeroView.entries[it].name },
            level = level,
            maxLevel = index.maxLevel,
            isAnchorLevel = snapshot?.isAnchorLevel ?: (level in index.baseAnchorLevels),
            onLevel = { levelState = index.clampLevel(it) },
            compact = compactHeight,
        )
        LazyColumn(
            state = listState,
            modifier = Modifier.fillMaxSize(),
            contentPadding = GameDataLayout.listPadding(top = 10.dp),
        ) {
            when (view) {
                HeroView.SINGLE -> {
                    item(key = "hero-picker", contentType = "section") {
                        HeroPickerSection(index.heroes, hero.key, onSelect = ::selectHero)
                    }
                    item(key = "modifiers", contentType = "section") {
                        ModifierSection(
                            modifiers = index.modifiers(hero.key),
                            selectedIds = selectedIds,
                            level = level,
                            sourceTag = index.modifierLevelNote(level),
                            names = names,
                            ruleHint = index.modifierRuleHint,
                            onToggle = ::toggleModifier,
                        )
                    }
                    item(key = "libra", contentType = "section") {
                        LibraSection(
                            libra = libra,
                            libraRule = index.dataset.interpolation.libraRule,
                            canClear = selectedIds.isNotEmpty() || libra != null,
                            onOpen = { libraSheetOpen = true },
                            onClear = {
                                modifierIds = ArrayList()
                                libraKey = ""
                            },
                        )
                    }
                    if (snapshot == null) {
                        item(key = "stats-empty", contentType = "section") { HeroEmptyNotice("这个角色没有可用的等级数据") }
                    } else {
                        item(key = "stats-head", contentType = "section") {
                            StatsHeader(
                                snapshot = snapshot,
                                level = level,
                                maxLevel = index.maxLevel,
                                allLevels = allLevels,
                                onAllLevels = { allLevels = it },
                                libra = libra,
                                crossCheckNote = index.crossCheckNote(hero.key, libra?.key),
                            )
                        }
                        if (allLevels) {
                            stickyHeader(key = "level-table-head", contentType = "table-head") {
                                LevelTableHeader(names, levelTableScroll)
                            }
                            items(allSnapshots, key = { "lv-${it.level}" }, contentType = { "level-row" }) { row ->
                                LevelTableRow(
                                    snapshot = row,
                                    names = names,
                                    showSource = snapshot.hasModifier,
                                    isCurrent = row.level == level,
                                    scroll = levelTableScroll,
                                    onClick = { levelState = row.level },
                                )
                            }
                            item(key = "level-table-notes", contentType = "section") {
                                LevelTableNotes(
                                    clampSummary = HeroStatsCopy.clampSummaryByLevel(index.clampedByLevel(allSnapshots), index.maxLevel),
                                    baseAnchorLevels = index.baseAnchorLevels,
                                    hasLegacy = names.hasLegacyDerived,
                                )
                            }
                        } else {
                            item(key = "stat-tiles", contentType = "section") {
                                StatTiles(snapshot, names)
                            }
                        }
                    }
                }

                HeroView.COMPARE -> {
                    item(key = "compare-head", contentType = "section") {
                        CompareHeader(level = level, count = compareRows.size)
                    }
                    if (compareRows.isEmpty()) {
                        item(key = "compare-empty", contentType = "section") { HeroEmptyNotice("没有可对比的角色") }
                    } else {
                        stickyHeader(key = "compare-table-head", contentType = "table-head") {
                            CompareTableHeader(
                                names = names,
                                column = sortColumn,
                                ascending = sortAscending,
                                scroll = compareTableScroll,
                                onSort = { column ->
                                    if (column == sortColumn) {
                                        sortAscending = !sortAscending
                                    } else {
                                        sortToken = column.token
                                        // 数值列默认从高到低，角色列默认按数据集顺序
                                        sortAscending = column == HeroComparisonColumn.Hero
                                    }
                                },
                            )
                        }
                        items(compareRows, key = { "cmp-${it.heroKey}" }, contentType = { "compare-row" }) { row ->
                            CompareTableRow(
                                row = row,
                                names = names,
                                maxima = compareMaxima,
                                isCurrent = row.heroKey == hero.key,
                                scroll = compareTableScroll,
                                onClick = {
                                    selectHero(row.heroKey)
                                    viewName = HeroView.SINGLE.name
                                },
                            )
                        }
                        item(key = "compare-notes", contentType = "section") {
                            CompareNotes(hasLegacy = names.hasLegacyDerived)
                        }
                    }
                }
            }

            item(key = "notes-head", contentType = "section") { NotesHeader() }
            item(key = "notes-interpolation", contentType = "disclosure") {
                val notes = index.dataset.interpolation.notes
                HeroDisclosure(
                    title = HeroStatsCopy.interpolationTitle(notes.size),
                    count = notes.size,
                    color = NightColors.PurpleSoft,
                    expanded = showNotes,
                    onToggle = { showNotes = !showNotes },
                ) { InterpolationNotes(notes) }
            }
            item(key = "notes-caveats", contentType = "disclosure") {
                val caveats = index.dataset.caveats
                HeroDisclosure(
                    title = HeroStatsCopy.caveatsTitle(caveats.size),
                    count = caveats.size,
                    color = NightColors.Amber,
                    expanded = showCaveats,
                    onToggle = { showCaveats = !showCaveats },
                ) { CaveatList(caveats) }
            }
            item(key = "notes-sources", contentType = "disclosure") {
                val sources = index.dataset.sources
                HeroDisclosure(
                    title = HeroStatsCopy.sourcesTitle(sources.size),
                    count = sources.size,
                    color = NightColors.Green,
                    expanded = showSources,
                    onToggle = { showSources = !showSources },
                ) { SourceList(sources, index.dataset.crossChecks) }
            }
            item(key = "notes-version", contentType = "section") {
                VersionBlock(index.versionRows())
            }
        }
    }

    if (libraSheetOpen) {
        LibraPickerSheet(
            respecs = index.libraRespecs,
            selectedKey = libra?.key,
            onSelect = { key ->
                libraKey = key.orEmpty()
                libraSheetOpen = false
            },
            onDismiss = { libraSheetOpen = false },
        )
    }
}
