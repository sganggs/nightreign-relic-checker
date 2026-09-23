package com.nightreign.relicchecker.ui.bosses

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.ScrollState
import androidx.compose.foundation.background
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.nightreign.relicchecker.catalog.AffixCatalog
import com.nightreign.relicchecker.gamedata.GameDataKey
import com.nightreign.relicchecker.gamedata.bosses.BossCard
import com.nightreign.relicchecker.gamedata.bosses.BossDataIndex
import com.nightreign.relicchecker.gamedata.bosses.BossGroup
import com.nightreign.relicchecker.gamedata.bosses.BossMutationChoice
import com.nightreign.relicchecker.gamedata.bosses.BossNightMode
import com.nightreign.relicchecker.gamedata.bosses.BossPageText
import com.nightreign.relicchecker.gamedata.bosses.BossPartySize
import com.nightreign.relicchecker.gamedata.bosses.BossRoleText
import com.nightreign.relicchecker.gamedata.bosses.BossRowText
import com.nightreign.relicchecker.gamedata.bosses.BossesParser
import com.nightreign.relicchecker.ui.DataPage
import com.nightreign.relicchecker.ui.NightPill
import com.nightreign.relicchecker.ui.NightSearchField
import com.nightreign.relicchecker.ui.NightSegmentedControl
import com.nightreign.relicchecker.ui.UserSettings
import com.nightreign.relicchecker.ui.gamedata.GameDataLayout
import com.nightreign.relicchecker.ui.gamedata.GameDataScreenScaffold
import com.nightreign.relicchecker.ui.gamedata.GameDataState
import com.nightreign.relicchecker.ui.gamedata.rememberGameData
import com.nightreign.relicchecker.ui.theme.NightColors
import kotlinx.coroutines.launch

// 首领数据页（数据 → 首领数据）。
//
// 数据：nightreign-bosses-v1.03.5.json 经 :gamedata 的 BossesParser 解码成 BossDataIndex
// （后台线程，进程级缓存）；换算、分组、代表行、文案全部在 :gamedata 里，与 macOS RelicCore 同口径。
//
// 手机布局：顶部粘性工具条（搜索 / 人数 / 模式 / 变异个体 / 显示隐藏实体 / 分组 + 各分组计数），
// 下面一个 LazyColumn：分组小标题吸顶，组内卡片折叠态看代表行概览、点开看逐行数值；
// 末尾是数据说明（caveats、场合说明、缩放档位、变异只数、深度概览、数据版本），搜索没命中也留着。
// 分组计数与列表同源：搜索时各分组计数同步更新（桌面端的分组计数不随搜索变，是已知缺陷）。
//
// 横屏 / 分屏 / 矮屏手机（页面高 < 600dp，见 BossToolbarLayout）：只把搜索框与设置行吸顶（横屏并成一行），
// 外壳的状态小标签、分组药丸、状态行与说明挪进列表第 0 项随列表滚走，保证列表至少有一屏卡片的高度。

private const val ALL_GROUPS = "ALL"
private const val SHEET_MODE = "mode"
private const val SHEET_MUTATION = "mutation"

/** 搜索框占位提示（桌面端那句太长，手机上压成一行；横屏并排时再短一点）。 */
private const val SEARCH_HINT = "首领名、译名、远征名、场合，或 npcId / chrId"
private const val SEARCH_HINT_SHORT = "首领名、场合，或 npcId / chrId"

@Suppress("UNUSED_PARAMETER")
@Composable
internal fun BossesScreen(
    catalog: AffixCatalog,
    settings: UserSettings,
    onBack: (() -> Unit)?,
    modifier: Modifier = Modifier,
) {
    val state = rememberGameData(GameDataKey.BOSSES, BossesParser.PARSER_ID, BossesParser::parse)
    BoxWithConstraints(modifier = modifier.fillMaxSize()) {
        val layout = BossToolbarLayout.of(pageHeight = maxHeight, pageWidth = maxWidth)
        val pills: @Composable RowScope.() -> Unit = { BossStatusPills((state as? GameDataState.Ready)?.value) }
        GameDataScreenScaffold(
            title = DataPage.BOSSES.title,
            subtitle = DataPage.BOSSES.eyebrow,
            onBack = onBack,
            state = state,
            loadingLabel = "正在载入首领数据",
            // 紧凑排法下状态小标签挪进列表第 0 项（省下顶栏下面的一行）
            statusPills = pills.takeUnless { layout.compact },
        ) { index ->
            BossesContent(index, layout)
        }
    }
}

/** 数据版本与收录数的小标签（外壳顶栏下的一行，紧凑排法下在列表第 0 项里）。 */
@Composable
private fun BossStatusPills(index: BossDataIndex?) {
    NightPill("参数表 1.03.5", NightColors.TextMuted)
    if (index != null) {
        val lords = index.cards.count { it.isNightlord }
        NightPill("$lords 位夜王 · ${index.cards.size - lords} 组首领", NightColors.Green, dot = true)
        NightPill("${index.multiGroupCards.size} 组属于多个场合", NightColors.TextMuted)
    }
}

private fun Set<String>.toggled(key: String): Set<String> = if (key in this) this - key else this + key

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun BossesContent(index: BossDataIndex, layout: BossToolbarLayout) {
    val dataset = index.dataset
    var query by rememberSaveable { mutableStateOf("") }
    var groupKey by rememberSaveable { mutableStateOf(ALL_GROUPS) }
    var players by rememberSaveable { mutableStateOf(1) }
    var depth by rememberSaveable { mutableStateOf(0) }
    var mutationCode by rememberSaveable { mutableStateOf(BossMutationChoice.None.encode()) }
    var showHidden by rememberSaveable { mutableStateOf(false) }
    var expanded by rememberSaveable(stateSaver = StringSetSaver) { mutableStateOf(emptySet<String>()) }
    var evidenceOpen by rememberSaveable(stateSaver = StringSetSaver) { mutableStateOf(emptySet<String>()) }
    var footerOpen by rememberSaveable(stateSaver = StringSetSaver) { mutableStateOf(emptySet<String>()) }
    var sheet by rememberSaveable { mutableStateOf<String?>(null) }
    val listState = rememberLazyListState()
    val groupScroll = rememberScrollState()
    val scope = rememberCoroutineScope()

    val view = remember(players, depth, mutationCode, showHidden, index) {
        BossViewSettings(
            party = BossPartySize.of(players),
            mode = BossNightMode.depth(depth),
            mutation = BossMutationChoice.decode(mutationCode),
            showHidden = showHidden,
            depthWord = dataset.deepOfNightText.depthTitle,
        )
    }
    val selectedGroup = BossGroup.entries.firstOrNull { it.name == groupKey }?.takeIf { showHidden || !it.isHiddenByDefault }
    // 全部分组一次筛完：各分组计数（分组药丸上的数字）与列表同源，搜索时一起更新
    val full = remember(index, query, showHidden) { index.filter(query, showHidden) }
    val sections = remember(full, selectedGroup) {
        if (selectedGroup == null) full.sections else full.sections.filter { it.first == selectedGroup }
    }
    val shownCards = remember(sections) {
        val seen = LinkedHashMap<String, BossCard>()
        sections.forEach { (_, cards) -> cards.forEach { seen.putIfAbsent(it.id, it) } }
        seen.values.toList()
    }
    val shownRows = remember(shownCards, showHidden) { shownCards.sumOf { it.displayRows(showHidden).size } }

    fun scrollTo(item: Int) {
        scope.launch { listState.scrollToItem(item) }
    }

    // 紧凑排法下列表第 0 项是控件区：搜索时跳到它下面的第一项，结果不被控件区挤出这一屏；
    // 点分组药丸 / 开关隐藏实体时回到第 0 项（控件区本身跟着变）。
    val firstResultItem = if (layout.compact) 1 else 0
    val status = buildString {
        append("显示 ${shownCards.size} 个首领 · $shownRows 条数值行 · ${view.party.title} · ${dataset.title(view.mode)}")
        when (val choice = view.mutation) {
            BossMutationChoice.None -> Unit
            BossMutationChoice.Own -> append(" · ${dataset.mutationTitle}（各行档位）")
            is BossMutationChoice.Tier -> append(" · ${dataset.mutationTitle} #${choice.id}")
        }
        val hiddenText = BossPageText.hiddenCountText(shownCards.count { it.isHiddenByDefault }, showHidden)
        if (hiddenText.isNotEmpty()) append(" · $hiddenText")
    }
    val groupControls: @Composable () -> Unit = {
        BossGroupChips(
            groupKey = if (selectedGroup == null) ALL_GROUPS else groupKey,
            counts = full.counts,
            allCount = full.uniqueCards.size,
            showHidden = showHidden,
            scroll = groupScroll,
            onGroup = {
                groupKey = it
                scrollTo(0)
            },
        )
        BossStatusLines(status = status, showHidden = showHidden)
    }

    Column(modifier = Modifier.fillMaxSize()) {
        BossToolbar(
            layout = layout,
            query = query,
            onQuery = {
                query = it
                scrollTo(firstResultItem)
            },
            settings = { rowModifier, rowPadding ->
                BossSettingsRow(
                    index = index,
                    view = view,
                    onPlayers = { players = it },
                    onOpenMode = { sheet = SHEET_MODE },
                    onOpenMutation = { sheet = SHEET_MUTATION },
                    onToggleHidden = {
                        showHidden = !showHidden
                        // 关掉开关时正停在「随从/召唤物」「未放置」上就退回「全部」
                        if (!showHidden && BossGroup.entries.any { it.name == groupKey && it.isHiddenByDefault }) groupKey = ALL_GROUPS
                        scrollTo(0)
                    },
                    modifier = rowModifier,
                    contentPadding = rowPadding,
                )
            },
            below = groupControls.takeUnless { layout.compact },
        )
        LazyColumn(
            state = listState,
            modifier = Modifier.weight(1f).fillMaxWidth(),
            contentPadding = GameDataLayout.listPadding(top = 8.dp),
        ) {
            if (layout.compact) {
                // 紧凑排法：状态小标签、分组药丸、状态行与说明作为第 0 项，随列表滚走
                item(key = "controls", contentType = "controls") {
                    Column(
                        modifier = Modifier.bleedHorizontally(GameDataLayout.Gutter).padding(bottom = 8.dp),
                        verticalArrangement = Arrangement.spacedBy(2.dp),
                    ) {
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .horizontalScroll(rememberScrollState())
                                .padding(horizontal = GameDataLayout.Gutter, vertical = 4.dp),
                            horizontalArrangement = Arrangement.spacedBy(8.dp),
                            verticalAlignment = Alignment.CenterVertically,
                        ) { BossStatusPills(index) }
                        groupControls()
                        Spacer(Modifier.size(4.dp))
                        HorizontalDivider(color = NightColors.Border)
                    }
                }
            }
            if (view.mode.isDeepOfNight) {
                item(key = "deep-intro", contentType = "intro") { DeepIntro(index, view.mode) }
            }
            if (sections.all { it.second.isEmpty() }) {
                item(key = "empty", contentType = "empty") { EmptyResult() }
            }
            sections.forEach { (group, cards) ->
                if (cards.isEmpty()) return@forEach
                stickyHeader(key = "header-${group.key}", contentType = "header") {
                    SectionHeader(group, cards.size)
                }
                items(cards, key = { "${group.key}|${it.id}" }, contentType = { "boss" }) { card ->
                    val key = "${group.key}|${card.id}"
                    BossCardView(
                        card = card,
                        group = group,
                        index = index,
                        view = view,
                        expanded = key in expanded,
                        onToggle = { expanded = expanded.toggled(key) },
                        evidenceOpen = evidenceOpen,
                        onToggleEvidence = { evidenceOpen = evidenceOpen.toggled(it) },
                        modifier = Modifier.padding(bottom = 10.dp),
                    )
                }
            }
            bossFooterItems(index, footerOpen) { footerOpen = footerOpen.toggled(it) }
        }
    }

    when (sheet) {
        SHEET_MODE -> BossModeSheet(
            index = index,
            current = view.mode,
            onSelect = {
                depth = it.depth ?: 0
                sheet = null
            },
            onDismiss = { sheet = null },
        )
        SHEET_MUTATION -> BossMutationSheet(
            index = index,
            current = view.mutation,
            onSelect = {
                mutationCode = it.encode()
                sheet = null
            },
            onDismiss = { sheet = null },
        )
    }
}

/**
 * 顶部粘性工具条：搜索框 + 设置行（人数、模式、变异个体、显示隐藏实体）；[below] 非空时（完整排法）
 * 下面再接分组药丸（带当前搜索下的计数）与状态行。横屏时搜索框与设置行并成一行。
 */
@Composable
private fun BossToolbar(
    layout: BossToolbarLayout,
    query: String,
    onQuery: (String) -> Unit,
    settings: @Composable (modifier: Modifier, contentPadding: PaddingValues) -> Unit,
    below: (@Composable () -> Unit)?,
) {
    Column(
        modifier = Modifier.fillMaxWidth().background(NightColors.Background),
        verticalArrangement = Arrangement.spacedBy(2.dp),
    ) {
        if (layout == BossToolbarLayout.COMPACT_ONE_ROW) {
            Row(modifier = Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                // 并成一行时搜索框只有约 250dp：占位提示用短句，免得折成两行挤在框里
                BossSearchField(query, onQuery, Modifier.weight(1f).padding(start = GameDataLayout.Gutter), SEARCH_HINT_SHORT)
                settings(Modifier.weight(1.5f), PaddingValues(start = 8.dp, end = GameDataLayout.Gutter))
            }
        } else {
            BossSearchField(query, onQuery, Modifier.padding(horizontal = GameDataLayout.Gutter), SEARCH_HINT)
            settings(Modifier.fillMaxWidth(), PaddingValues(horizontal = GameDataLayout.Gutter))
        }
        below?.invoke()
        Spacer(Modifier.size(4.dp))
        HorizontalDivider(color = NightColors.Border)
    }
}

@Composable
private fun BossSearchField(query: String, onQuery: (String) -> Unit, modifier: Modifier, placeholder: String) {
    NightSearchField(value = query, onValueChange = onQuery, modifier = modifier, placeholder = placeholder)
}

/** 设置行：人数分段、模式、变异个体、显示隐藏实体；放不下时横向滑动。 */
@Composable
private fun BossSettingsRow(
    index: BossDataIndex,
    view: BossViewSettings,
    onPlayers: (Int) -> Unit,
    onOpenMode: () -> Unit,
    onOpenMutation: () -> Unit,
    onToggleHidden: () -> Unit,
    modifier: Modifier,
    contentPadding: PaddingValues,
) {
    val dataset = index.dataset
    Row(
        modifier = modifier
            .horizontalScroll(rememberScrollState())
            .padding(contentPadding),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        NightSegmentedControl(
            items = BossPartySize.entries.map { it.title },
            selectedIndex = view.party.ordinal,
            onSelect = { onPlayers(BossPartySize.entries[it].players) },
            modifier = Modifier.width(156.dp),
            height = 38.dp,
        )
        BossToolbarChip(
            text = dataset.title(view.mode) + " ▾",
            selected = view.mode.isDeepOfNight,
            onClick = onOpenMode,
            color = NightColors.Amber,
        )
        if (dataset.mutations.isNotEmpty()) {
            BossToolbarChip(
                text = dataset.mutationTitle + "：" + when (val choice = view.mutation) {
                    BossMutationChoice.None -> BossRowText.mutationPickerNone
                    BossMutationChoice.Own -> "各行档位"
                    is BossMutationChoice.Tier -> "#${choice.id}"
                } + " ▾",
                selected = view.mutation != BossMutationChoice.None,
                onClick = onOpenMutation,
                color = NightColors.Red,
            )
        }
        BossToolbarChip(
            text = BossRowText.hiddenToggleTitle,
            selected = view.showHidden,
            onClick = onToggleHidden,
            leading = { SwitchDot(view.showHidden) },
        )
    }
}

/** 分组药丸：全部 + 各分组（数字是当前搜索下的卡片数）。 */
@Composable
private fun BossGroupChips(
    groupKey: String,
    counts: Map<BossGroup, Int>,
    allCount: Int,
    showHidden: Boolean,
    scroll: ScrollState,
    onGroup: (String) -> Unit,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .horizontalScroll(scroll)
            .padding(horizontal = GameDataLayout.Gutter),
        horizontalArrangement = Arrangement.spacedBy(6.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        BossToolbarChip(text = "全部", selected = groupKey == ALL_GROUPS, onClick = { onGroup(ALL_GROUPS) }, count = allCount)
        BossGroup.visibleCases(showHidden).forEach { group ->
            BossToolbarChip(
                text = group.title,
                selected = groupKey == group.name,
                onClick = { onGroup(group.name) },
                color = if (group.isHiddenByDefault) NightColors.TextSecondary else BossPalette.group(group),
                count = counts[group] ?: 0,
            )
        }
    }
}

/** 状态行 + 一行说明。 */
@Composable
private fun BossStatusLines(status: String, showHidden: Boolean) {
    Text(
        status,
        modifier = Modifier.padding(horizontal = GameDataLayout.Gutter),
        style = MaterialTheme.typography.labelSmall,
        color = NightColors.TextMuted,
    )
    // 一行说明：平时讲分组口径；打开「显示隐藏实体」时讲这个开关管什么（桌面端是悬停提示）
    Text(
        if (showHidden) {
            BossRowText.hiddenToggleTitle + "：" + BossRowText.hiddenToggleHelp + "；" + BossRoleText.hiddenToggleRoleHelp
        } else {
            BossRoleText.groupPickerHelp
        },
        modifier = Modifier.padding(horizontal = GameDataLayout.Gutter),
        style = MaterialTheme.typography.labelSmall,
        color = NightColors.TextMuted.copy(alpha = 0.8f),
    )
}

/** 吸顶的分组小标题：分组名 + 当前搜索下的卡片数。背景填满，避免透出下层文字。 */
@Composable
private fun SectionHeader(group: BossGroup, count: Int) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .background(NightColors.Background)
            .padding(top = 8.dp, bottom = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Box(Modifier.size(8.dp).background(BossPalette.group(group), CircleShape))
        Text(group.title, style = MaterialTheme.typography.titleMedium, color = NightColors.TextPrimary, fontWeight = FontWeight.Bold)
        Text("$count", style = MaterialTheme.typography.labelLarge.tabular(), color = NightColors.TextMuted)
        if (group.isHiddenByDefault) {
            Text(BossRoleText.hiddenGroupMark, style = MaterialTheme.typography.labelSmall, color = NightColors.TextMuted)
        }
    }
}

/** 深度模式下列表顶部的说明：深夜 / 深度 / 变异个体一律用游戏内文本。 */
@Composable
private fun DeepIntro(index: BossDataIndex, mode: BossNightMode) {
    val text = index.dataset.deepOfNightText
    BossNoteBox(modifier = Modifier.padding(bottom = 10.dp), tint = NightColors.Amber, alpha = 0.06f) {
        BossFlow {
            NightPill(text.deepOfNightTitle, NightColors.Amber)
            Text(
                "${text.depthTitle} ${mode.depth ?: 0}",
                modifier = Modifier.align(Alignment.CenterVertically),
                style = MaterialTheme.typography.labelLarge,
                color = NightColors.Amber,
                fontWeight = FontWeight.SemiBold,
            )
        }
        Text(
            "血量与敌人攻击力都按深度上浮，攻击力涨得更快；部分敌人还会以「${index.dataset.mutationTitle}」出现，倍率再乘一层。",
            style = MaterialTheme.typography.bodySmall,
            color = NightColors.TextSecondary,
        )
        if (text.description.zh.isNotEmpty()) {
            Text(text.description.zh.replace("\n", " "), style = MaterialTheme.typography.labelSmall, color = NightColors.TextMuted)
        }
    }
}

@Composable
private fun EmptyResult() {
    Column(
        modifier = Modifier.fillMaxWidth().padding(vertical = 36.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        NightPill("0 组", NightColors.TextMuted)
        Text(BossPageText.emptyTitle, style = MaterialTheme.typography.titleMedium, color = NightColors.TextPrimary)
        Text(BossPageText.emptyDetail, style = MaterialTheme.typography.bodySmall, color = NightColors.TextMuted)
    }
}
