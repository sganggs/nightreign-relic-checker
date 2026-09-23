package com.nightreign.relicchecker.ui.lookup

import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.Stable
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.listSaver
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.saveable.rememberSaveableStateHolder
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.nestedscroll.NestedScrollConnection
import androidx.compose.ui.input.nestedscroll.NestedScrollSource
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import com.nightreign.relicchecker.catalog.AffixCatalog
import com.nightreign.relicchecker.gamedata.GameDataKey
import com.nightreign.relicchecker.gamedata.lookup.AffixLookupIndex
import com.nightreign.relicchecker.gamedata.lookup.AffixLookupScope
import com.nightreign.relicchecker.gamedata.lookup.LookupAffix
import com.nightreign.relicchecker.gamedata.lookup.LookupCopy
import com.nightreign.relicchecker.gamedata.lookup.RelicLookupEntry
import com.nightreign.relicchecker.ui.NightBackButton
import com.nightreign.relicchecker.ui.NightPill
import com.nightreign.relicchecker.ui.NightSearchField
import com.nightreign.relicchecker.ui.NightSegmentedControl
import com.nightreign.relicchecker.ui.UserSettings
import com.nightreign.relicchecker.ui.gamedata.GameDataLayout
import com.nightreign.relicchecker.ui.gamedata.GameDataLoadingView
import com.nightreign.relicchecker.ui.gamedata.GameDataScreenScaffold
import com.nightreign.relicchecker.ui.gamedata.GameDataState
import com.nightreign.relicchecker.ui.gamedata.rememberGameData
import com.nightreign.relicchecker.ui.theme.NightColors
import kotlinx.coroutines.launch
import kotlin.math.roundToInt

/**
 * 词条反查（底栏「反查」，一级页，onBack 恒为 null）。
 *
 * 桌面端是「左列表 / 右详情」；手机改成：顶部「按词条查 / 按遗物查」分段 + 搜索（常驻），
 * 下面单列列表，范围 / 条数 / 开关是列表第一项、随列表滚走；横屏等矮屏时分段与搜索并成一行，
 * 并随列表下滑收起、上滑即回。点行进全屏详情（带返回，系统返回键同样生效）。详情里点互斥词条、池成员、
 * 出处遗物会在同一个详情栈里跨方向继续往下跳，返回时逐层退回、每一层的滚动位置与展开状态都保留。
 *
 * 数据：遗物物品表（RELICS）在 IO 线程解析并与词条库一起建好反向索引（进程级缓存，
 * parserId = [AffixLookupIndex.PARSER_ID]）。物品表载入失败时退化为只有词条库的索引，
 * 仍可看词条说明与互斥组（macOS 的降级口径）。
 */
@Suppress("UNUSED_PARAMETER")
@Composable
internal fun LookupScreen(
    catalog: AffixCatalog,
    settings: UserSettings,
    onBack: (() -> Unit)?,
    modifier: Modifier = Modifier,
) {
    // 模拟器 debug 包冷启动实测：解码约 160 ms + 建索引约 250 ms（adb logcat -s GameData 看总耗时）
    val state = rememberGameData(GameDataKey.RELICS, AffixLookupIndex.PARSER_ID) { text ->
        AffixLookupIndex.parse(catalog, text)
    }
    GameDataScreenScaffold(
        title = LookupCopy.TITLE,
        subtitle = LookupCopy.EYEBROW,
        onBack = onBack,
        modifier = modifier,
        statusPills = {
            NightPill(
                LookupCopy.catalogPill(catalog.affixes.size),
                if (catalog.affixes.isEmpty()) NightColors.Amber else NightColors.Green,
                dot = true,
            )
            when (state) {
                is GameDataState.Ready -> NightPill(LookupCopy.obtainablePill(state.value.obtainableRelicCount), NightColors.PurpleSoft)
                is GameDataState.Failed -> NightPill(LookupCopy.RELIC_DATA_NOT_BUNDLED, NightColors.Amber)
                GameDataState.Loading -> Unit
            }
        },
    ) {
        when (state) {
            GameDataState.Loading -> GameDataLoadingView(LookupCopy.INDEX_LOADING)
            is GameDataState.Ready -> LookupContent(index = state.value, relicDataDetail = LookupCopy.relicDataDetail(null))
            is GameDataState.Failed -> {
                val bare = remember(catalog) { AffixLookupIndex(catalog, null) }
                LookupContent(index = bare, relicDataDetail = LookupCopy.relicDataDetail(state.error.message ?: state.error.toString()))
            }
        }
    }
}

// MARK: - 详情栈

/**
 * 详情栈里的一层：某条词条或某件遗物。[serial] 是压栈时分配的序号，
 * 用作这一层保存状态（滚动位置、展开状态）的键：同一条词条在栈里出现两次也互不干扰。
 */
@Immutable
private data class LookupFrame(val kind: Kind, val id: Int, val serial: Int) {
    enum class Kind { AFFIX, RELIC }

    val stateKey: String get() = "lookup-frame-$serial"

    fun sameTarget(other: LookupFrame?): Boolean = other != null && other.kind == kind && other.id == id
}

private val FrameStackSaver = listSaver<List<LookupFrame>, Int>(
    save = { stack -> stack.flatMap { listOf(it.kind.ordinal, it.id, it.serial) } },
    restore = { flat ->
        flat.chunked(3).map { (kind, id, serial) -> LookupFrame(LookupFrame.Kind.entries[kind], id, serial) }
    },
)

/** 详情栈最多保留多少层；更早的层被丢弃（连同它保存的滚动位置）。 */
private const val MAX_STACK_DEPTH = 32

private enum class LookupTab { AFFIX, RELIC }

@Composable
private fun LookupContent(index: AffixLookupIndex, relicDataDetail: String) {
    var tabName by rememberSaveable { mutableStateOf(LookupTab.AFFIX.name) }
    val tab = LookupTab.entries.firstOrNull { it.name == tabName } ?: LookupTab.AFFIX
    var affixQuery by rememberSaveable { mutableStateOf("") }
    var relicQuery by rememberSaveable { mutableStateOf("") }
    // 与 macOS 默认一致：范围「词条库」、含负面词条、不限深夜
    var scopeName by rememberSaveable { mutableStateOf(AffixLookupScope.CATALOG.name) }
    val scope = AffixLookupScope.entries.firstOrNull { it.name == scopeName } ?: AffixLookupScope.CATALOG
    var includeCurses by rememberSaveable { mutableStateOf(true) }
    var onlyDeep by rememberSaveable { mutableStateOf(false) }
    var stack by rememberSaveable(stateSaver = FrameStackSaver) { mutableStateOf(emptyList<LookupFrame>()) }
    var nextSerial by rememberSaveable { mutableIntStateOf(1) }

    // 列表滚动位置提到这里：进详情时列表离开组合，回来仍停在原处
    val affixListState = rememberLazyListState()
    val relicListState = rememberLazyListState()
    val frameStates = rememberSaveableStateHolder()
    val coroutines = rememberCoroutineScope()
    val focusManager = LocalFocusManager.current

    val affixRows = remember(index, affixQuery, scope, includeCurses) {
        index.searchAffixes(affixQuery, includeCurses = includeCurses, scope = scope)
    }
    val relicRows = remember(index, relicQuery, onlyDeep) {
        index.searchRelics(relicQuery, onlyDeep = onlyDeep)
    }

    fun open(kind: LookupFrame.Kind, id: Int, fromList: Boolean) {
        focusManager.clearFocus()
        val base = if (fromList) {
            stack.forEach { frameStates.removeState(it.stateKey) }
            emptyList()
        } else {
            stack
        }
        // 序号只增不减：刚弹出的那一层可能还在退场动画里，复用它的键会让两份内容撞键
        val frame = LookupFrame(kind, id, serial = nextSerial)
        if (frame.sameTarget(base.lastOrNull())) return
        nextSerial += 1
        var next = base + frame
        while (next.size > MAX_STACK_DEPTH) {
            frameStates.removeState(next.first().stateKey)
            next = next.drop(1)
        }
        stack = next
    }

    fun pop() {
        val top = stack.lastOrNull() ?: return
        frameStates.removeState(top.stateKey)
        stack = stack.dropLast(1)
    }

    BackHandler(enabled = stack.isNotEmpty()) { pop() }

    val openAffix = { effectId: Int -> open(LookupFrame.Kind.AFFIX, effectId, fromList = false) }
    val openRelic = { relicId: Int -> open(LookupFrame.Kind.RELIC, relicId, fromList = false) }

    AnimatedContent(
        targetState = stack.size to stack.lastOrNull(),
        modifier = Modifier.fillMaxSize(),
        transitionSpec = {
            if (targetState.first > initialState.first) {
                (slideInHorizontally(tween(220)) { it / 8 } + fadeIn(tween(220))) togetherWith fadeOut(tween(120))
            } else {
                fadeIn(tween(180)) togetherWith (slideOutHorizontally(tween(200)) { it / 8 } + fadeOut(tween(160)))
            }
        },
        label = "lookup-frame",
    ) { (_, frame) ->
        if (frame == null) {
            LookupListPane(
                index = index,
                relicDataDetail = relicDataDetail,
                tab = tab,
                onTab = { tabName = it.name },
                affixQuery = affixQuery,
                onAffixQuery = {
                    affixQuery = it
                    coroutines.launch { affixListState.scrollToItem(0) }
                },
                scope = scope,
                onScope = {
                    scopeName = it.name
                    coroutines.launch { affixListState.scrollToItem(0) }
                },
                includeCurses = includeCurses,
                onIncludeCurses = {
                    includeCurses = it
                    coroutines.launch { affixListState.scrollToItem(0) }
                },
                affixRows = affixRows,
                relicQuery = relicQuery,
                onRelicQuery = {
                    relicQuery = it
                    coroutines.launch { relicListState.scrollToItem(0) }
                },
                onlyDeep = onlyDeep,
                onOnlyDeep = {
                    onlyDeep = it
                    coroutines.launch { relicListState.scrollToItem(0) }
                },
                relicRows = relicRows,
                affixListState = affixListState,
                relicListState = relicListState,
                onOpenAffix = { open(LookupFrame.Kind.AFFIX, it, fromList = true) },
                onOpenRelic = { open(LookupFrame.Kind.RELIC, it, fromList = true) },
            )
        } else {
            frameStates.SaveableStateProvider(frame.stateKey) {
                LookupDetailFrame(
                    index = index,
                    frame = frame,
                    relicDataDetail = relicDataDetail,
                    onBack = ::pop,
                    onPickAffix = openAffix,
                    onPickRelic = openRelic,
                )
            }
        }
    }
}

// MARK: - 列表

/**
 * 屏幕高度低于这个值（dp）就用紧凑布局：横屏手机 360–412dp（去掉页头、底栏后列表区只剩约 140–215dp），
 * 上下分屏也常落在这里；竖屏手机至少 640dp，走常规布局。
 *
 * 按 Configuration.screenHeightDp 判断而不是列表区实测高度：软键盘弹出不改变它，
 * 不会在输入途中来回切换布局、让搜索框丢焦点。
 */
private const val COMPACT_SCREEN_HEIGHT_DP = 480

/** 搜索框高度（NightSearchField 固定 46dp）；紧凑工具条的页签分段与它等高。 */
private val SearchFieldHeight = 46.dp

/** 紧凑工具条总高：一行 46 + 下方留白 8 + 分隔线 1。固定值，列表顶部留白与收起距离都按它算。 */
private val CompactToolbarHeight = SearchFieldHeight + 8.dp + 1.dp

/**
 * 紧凑布局的「下滑收起、上滑即回」工具条（enterAlways）。
 *
 * 只跟随列表**实际滚动**的距离（[onPostScroll] 的 consumed）：列表滚不动时工具条不动，不会空出一条。
 * 始终满足 offset ≥ −已滚动距离，所以列表回到最顶时工具条一定完整露出；
 * 程序滚动（改搜索后回到顶部、结果变少）不经过嵌套滚动，由 [limitToScrolled] 兜底。
 */
@Stable
private class QuickReturnToolbar(private val hidePx: Float) : NestedScrollConnection {
    var offsetPx by mutableFloatStateOf(0f)
        private set

    override fun onPostScroll(consumed: Offset, available: Offset, source: NestedScrollSource): Offset {
        if (consumed.y != 0f) offsetPx = (offsetPx + consumed.y).coerceIn(-hidePx, 0f)
        return Offset.Zero
    }

    /** 列表停在第一项、只滚了 [scrolledPx] 时，工具条最多收起这么多。 */
    fun limitToScrolled(scrolledPx: Int) {
        val floor = -scrolledPx.toFloat()
        if (offsetPx < floor) offsetPx = floor
    }
}

@Composable
private fun LookupListPane(
    index: AffixLookupIndex,
    relicDataDetail: String,
    tab: LookupTab,
    onTab: (LookupTab) -> Unit,
    affixQuery: String,
    onAffixQuery: (String) -> Unit,
    scope: AffixLookupScope,
    onScope: (AffixLookupScope) -> Unit,
    includeCurses: Boolean,
    onIncludeCurses: (Boolean) -> Unit,
    affixRows: List<LookupAffix>,
    relicQuery: String,
    onRelicQuery: (String) -> Unit,
    onlyDeep: Boolean,
    onOnlyDeep: (Boolean) -> Unit,
    relicRows: List<RelicLookupEntry>,
    affixListState: LazyListState,
    relicListState: LazyListState,
    onOpenAffix: (Int) -> Unit,
    onOpenRelic: (Int) -> Unit,
) {
    val listState = when (tab) {
        LookupTab.AFFIX -> affixListState
        LookupTab.RELIC -> relicListState
    }
    // 常驻的只有页签与搜索框；范围分段、条数与开关是列表的第一项，随列表滚走（横屏也能看到列表行）
    val tabs: @Composable (Modifier, Dp) -> Unit = { modifier, height ->
        NightSegmentedControl(
            items = listOf(LookupCopy.TAB_AFFIX, LookupCopy.TAB_RELIC),
            selectedIndex = tab.ordinal,
            onSelect = { onTab(LookupTab.entries[it]) },
            modifier = modifier,
            height = height,
        )
    }
    val search: (@Composable (Modifier) -> Unit)? = when {
        tab == LookupTab.AFFIX -> { modifier ->
            NightSearchField(affixQuery, onAffixQuery, modifier, placeholder = LookupCopy.AFFIX_SEARCH_PLACEHOLDER)
        }
        index.hasRelicData -> { modifier ->
            NightSearchField(relicQuery, onRelicQuery, modifier, placeholder = LookupCopy.RELIC_SEARCH_PLACEHOLDER)
        }
        else -> null
    }
    val list: @Composable (Dp) -> Unit = { topPadding ->
        // 两个页签各一份列表组合：互不复用条目，各自保留滚动位置
        key(tab) {
            LookupResultList(
                index = index,
                relicDataDetail = relicDataDetail,
                tab = tab,
                scope = scope,
                onScope = onScope,
                includeCurses = includeCurses,
                onIncludeCurses = onIncludeCurses,
                affixRows = affixRows,
                onlyDeep = onlyDeep,
                onOnlyDeep = onOnlyDeep,
                relicRows = relicRows,
                listState = listState,
                topPadding = topPadding,
                onOpenAffix = onOpenAffix,
                onOpenRelic = onOpenRelic,
            )
        }
    }

    if (LocalConfiguration.current.screenHeightDp >= COMPACT_SCREEN_HEIGHT_DP) {
        // 常规（竖屏）：页签、搜索各占一行，固定在列表上方
        Column(modifier = Modifier.fillMaxSize()) {
            Column(
                modifier = Modifier.padding(horizontal = GameDataLayout.Gutter),
                verticalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                tabs(Modifier, 40.dp)
                search?.invoke(Modifier)
            }
            Spacer(Modifier.height(8.dp))
            LookupDivider()
            Box(modifier = Modifier.fillMaxWidth().weight(1f)) { list(4.dp) }
        }
    } else {
        CompactListPane(listState = listState, tabs = tabs, search = search, list = list)
    }
}

/** 紧凑布局（横屏 / 分屏）：页签与搜索并成一行，列表下滑时整行收起、上滑即回。 */
@Composable
private fun CompactListPane(
    listState: LazyListState,
    tabs: @Composable (Modifier, Dp) -> Unit,
    search: (@Composable (Modifier) -> Unit)?,
    list: @Composable (Dp) -> Unit,
) {
    // 多收 2dp：各段高度分别取整到像素后，分隔线可能比 55dp 多出一像素，收起时不留残线
    val hidePx = with(LocalDensity.current) { (CompactToolbarHeight + 2.dp).toPx() }
    val quickReturn = remember(hidePx) { QuickReturnToolbar(hidePx) }
    LaunchedEffect(listState, quickReturn) {
        snapshotFlow {
            if (listState.firstVisibleItemIndex == 0) listState.firstVisibleItemScrollOffset else Int.MAX_VALUE
        }.collect { quickReturn.limitToScrolled(it) }
    }
    val scrolled by remember(listState) {
        derivedStateOf { listState.firstVisibleItemIndex > 0 || listState.firstVisibleItemScrollOffset > 0 }
    }
    Box(
        modifier = Modifier
            .fillMaxSize()
            .clipToBounds()
            .nestedScroll(quickReturn),
    ) {
        list(CompactToolbarHeight + 4.dp)
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .height(CompactToolbarHeight)
                .offset { IntOffset(0, quickReturn.offsetPx.roundToInt()) }
                // 列表在顶部时透出页面底色；滚动后列表行从工具条下面经过，需要不透明底
                .background(if (scrolled) NightColors.Background else Color.Transparent),
        ) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .height(SearchFieldHeight)
                    .padding(horizontal = GameDataLayout.Gutter),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                tabs(Modifier.fillMaxWidth(.42f).widthIn(max = 240.dp), SearchFieldHeight)
                search?.invoke(Modifier.weight(1f))
            }
            Spacer(Modifier.height(8.dp))
            LookupDivider()
        }
    }
}

/** 结果列表：第一项是筛选（范围 / 条数 / 开关），不固定，随列表滚走；没有结果时筛选仍在，便于放宽条件。 */
@Composable
private fun LookupResultList(
    index: AffixLookupIndex,
    relicDataDetail: String,
    tab: LookupTab,
    scope: AffixLookupScope,
    onScope: (AffixLookupScope) -> Unit,
    includeCurses: Boolean,
    onIncludeCurses: (Boolean) -> Unit,
    affixRows: List<LookupAffix>,
    onlyDeep: Boolean,
    onOnlyDeep: (Boolean) -> Unit,
    relicRows: List<RelicLookupEntry>,
    listState: LazyListState,
    topPadding: Dp,
    onOpenAffix: (Int) -> Unit,
    onOpenRelic: (Int) -> Unit,
) {
    LazyColumn(
        modifier = Modifier.fillMaxSize(),
        state = listState,
        contentPadding = GameDataLayout.listPadding(top = topPadding),
    ) {
        when (tab) {
            LookupTab.AFFIX -> {
                item(key = "affix-filters", contentType = "filters") {
                    Column(
                        modifier = Modifier.fillMaxWidth().padding(top = 6.dp),
                        verticalArrangement = Arrangement.spacedBy(6.dp),
                    ) {
                        NightSegmentedControl(
                            items = AffixLookupScope.entries.map { it.title },
                            selectedIndex = scope.ordinal,
                            onSelect = { onScope(AffixLookupScope.entries[it]) },
                            height = 38.dp,
                        )
                        FilterBar(LookupCopy.affixCount(affixRows.size)) {
                            LookupSwitch(LookupCopy.INCLUDE_CURSES, includeCurses, onIncludeCurses)
                        }
                    }
                }
                if (affixRows.isEmpty()) {
                    item(key = "affix-empty", contentType = "empty") {
                        LookupEmptyState(LookupCopy.NO_AFFIX_MATCH, LookupCopy.NO_AFFIX_MATCH_DETAIL)
                    }
                } else {
                    items(affixRows, key = { it.effectId }, contentType = { "affix" }) { affix ->
                        LookupDivider(Modifier.padding(horizontal = 6.dp))
                        AffixRow(affix) { onOpenAffix(affix.effectId) }
                    }
                }
            }
            LookupTab.RELIC -> if (!index.hasRelicData) {
                item(key = "relic-unavailable", contentType = "notice") {
                    LookupNoticeCard(
                        LookupCopy.RELIC_DATA_NOT_BUNDLED,
                        relicDataDetail + LookupCopy.RELIC_TAB_UNAVAILABLE_SUFFIX,
                        Modifier.padding(top = 8.dp),
                    )
                }
            } else {
                item(key = "relic-filters", contentType = "filters") {
                    FilterBar(LookupCopy.relicCount(relicRows.size), Modifier.padding(top = 2.dp)) {
                        LookupSwitch(LookupCopy.ONLY_DEEP, onlyDeep, onOnlyDeep)
                    }
                }
                if (relicRows.isEmpty()) {
                    item(key = "relic-empty", contentType = "empty") {
                        LookupEmptyState(LookupCopy.NO_RELIC_MATCH, LookupCopy.NO_RELIC_MATCH_DETAIL)
                    }
                } else {
                    items(relicRows, key = { it.id }, contentType = { "relic" }) { entry ->
                        LookupDivider(Modifier.padding(horizontal = 6.dp))
                        RelicRow(entry) { onOpenRelic(entry.id) }
                    }
                }
            }
        }
    }
}

/** 结果条数 + 右侧开关。 */
@Composable
private fun FilterBar(countText: String, modifier: Modifier = Modifier, toggle: @Composable () -> Unit) {
    Row(modifier = modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        Text(
            countText,
            style = MaterialTheme.typography.labelLarge.lookupTabular(),
            color = NightColors.TextSecondary,
            modifier = Modifier.weight(1f),
        )
        toggle()
    }
}

@Composable
private fun AffixRow(affix: LookupAffix, onClick: () -> Unit) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .heightIn(min = 56.dp)
            .clip(RoundedCornerShape(12.dp))
            .clickable(role = Role.Button, onClick = onClick)
            .padding(horizontal = 6.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        LookupRowDot(
            when {
                affix.isCurse -> NightColors.Red
                affix.requiresCurse -> NightColors.Amber
                affix.inCatalog -> NightColors.Purple
                else -> NightColors.TextMuted
            },
        )
        Spacer(Modifier.width(11.dp))
        Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
            Text(
                affix.displayName,
                style = MaterialTheme.typography.bodyLarge,
                fontWeight = FontWeight.SemiBold,
                color = NightColors.TextPrimary,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
            )
            Row(horizontalArrangement = Arrangement.spacedBy(7.dp), verticalAlignment = Alignment.CenterVertically) {
                Text(affix.effectId.toString(), style = MaterialTheme.typography.labelSmall.lookupTabular(), color = NightColors.PurpleSoft)
                Text(
                    affix.category,
                    style = MaterialTheme.typography.labelSmall,
                    color = NightColors.TextMuted,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.weight(1f, fill = false),
                )
                when {
                    affix.isCurse -> Text(LookupCopy.ROW_CURSE, style = MaterialTheme.typography.labelSmall, color = NightColors.Red)
                    affix.requiresCurse -> Text(LookupCopy.ROW_REQUIRES_CURSE, style = MaterialTheme.typography.labelSmall, color = NightColors.Amber)
                }
                if (!affix.inCatalog) {
                    Text(LookupCopy.ROW_EXTRA, style = MaterialTheme.typography.labelSmall, color = NightColors.TextMuted)
                }
            }
        }
        Text("›", style = MaterialTheme.typography.titleLarge, color = NightColors.TextMuted, modifier = Modifier.padding(start = 8.dp))
    }
}

@Composable
private fun RelicRow(entry: RelicLookupEntry, onClick: () -> Unit) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .heightIn(min = 56.dp)
            .clip(RoundedCornerShape(12.dp))
            .clickable(role = Role.Button, onClick = onClick)
            .padding(horizontal = 6.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        LookupRelicDot(entry.info.color)
        Spacer(Modifier.width(12.dp))
        Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
            Text(
                entry.displayName,
                style = MaterialTheme.typography.bodyLarge,
                fontWeight = FontWeight.SemiBold,
                color = NightColors.TextPrimary,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
            )
            Row(horizontalArrangement = Arrangement.spacedBy(7.dp), verticalAlignment = Alignment.CenterVertically) {
                Text(entry.id.toString(), style = MaterialTheme.typography.labelSmall.lookupTabular(), color = NightColors.PurpleSoft)
                Text(
                    entry.kindLabel,
                    style = MaterialTheme.typography.labelSmall,
                    color = if (entry.deep) NightColors.PurpleSoft else NightColors.TextSecondary,
                )
                Text(LookupCopy.slotCountLabel(entry.slotCount), style = MaterialTheme.typography.labelSmall, color = NightColors.TextMuted)
                if (entry.fixedEffectIds != null) {
                    Text(LookupCopy.FIXED_PILL, style = MaterialTheme.typography.labelSmall, color = NightColors.Green)
                }
            }
        }
        Text("›", style = MaterialTheme.typography.titleLarge, color = NightColors.TextMuted, modifier = Modifier.padding(start = 8.dp))
    }
}

@Composable
private fun LookupRowDot(color: Color) {
    Box(Modifier.size(7.dp).background(color, CircleShape))
}

// MARK: - 详情

@Composable
private fun LookupDetailFrame(
    index: AffixLookupIndex,
    frame: LookupFrame,
    relicDataDetail: String,
    onBack: () -> Unit,
    onPickAffix: (Int) -> Unit,
    onPickRelic: (Int) -> Unit,
) {
    val (eyebrow, title) = when (frame.kind) {
        LookupFrame.Kind.AFFIX -> LookupCopy.TAB_AFFIX to index.affixName(frame.id)
        LookupFrame.Kind.RELIC -> LookupCopy.TAB_RELIC to (index.relic(frame.id)?.displayName ?: frame.id.toString())
    }
    Column(modifier = Modifier.fillMaxSize()) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(start = GameDataLayout.Gutter - 6.dp, end = GameDataLayout.Gutter)
                .height(52.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            NightBackButton(onClick = onBack)
            Spacer(Modifier.width(6.dp))
            Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(1.dp)) {
                Text(eyebrow, style = MaterialTheme.typography.labelSmall, color = NightColors.TextMuted, maxLines = 1)
                Text(
                    title,
                    style = MaterialTheme.typography.titleMedium,
                    color = NightColors.TextPrimary,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }
        }
        Spacer(Modifier.height(6.dp))
        when (frame.kind) {
            LookupFrame.Kind.AFFIX -> LookupAffixDetail(
                index = index,
                effectId = frame.id,
                relicDataDetail = relicDataDetail,
                onPickAffix = onPickAffix,
                onPickRelic = onPickRelic,
            )
            LookupFrame.Kind.RELIC -> LookupRelicDetail(
                index = index,
                relicId = frame.id,
                onPickAffix = onPickAffix,
            )
        }
    }
}
