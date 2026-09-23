package com.nightreign.relicchecker.ui.save

import android.content.ActivityNotFoundException
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.rememberScrollState
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
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.nightreign.relicchecker.catalog.AffixCatalog
import com.nightreign.relicchecker.gamedata.GameDataKey
import com.nightreign.relicchecker.gamedata.save.AuditedCharacter
import com.nightreign.relicchecker.gamedata.save.AuditedRelic
import com.nightreign.relicchecker.gamedata.save.AuditedSave
import com.nightreign.relicchecker.gamedata.save.SaveAuditData
import com.nightreign.relicchecker.gamedata.save.SaveFilter
import com.nightreign.relicchecker.gamedata.save.SaveReportBuilder
import com.nightreign.relicchecker.gamedata.save.SaveReportCatalogInfo
import com.nightreign.relicchecker.gamedata.save.SaveReportFormat
import com.nightreign.relicchecker.ui.DataPage
import com.nightreign.relicchecker.ui.NightBottomSheet
import com.nightreign.relicchecker.ui.NightPanel
import com.nightreign.relicchecker.ui.NightPill
import com.nightreign.relicchecker.ui.NightSearchField
import com.nightreign.relicchecker.ui.NightSegmentedControl
import com.nightreign.relicchecker.ui.UserSettings
import com.nightreign.relicchecker.ui.gamedata.GameDataLayout
import com.nightreign.relicchecker.ui.gamedata.GameDataScreenScaffold
import com.nightreign.relicchecker.ui.gamedata.GameDataState
import com.nightreign.relicchecker.ui.gamedata.rememberGameData
import com.nightreign.relicchecker.ui.theme.NightColors
import java.time.LocalDateTime

/**
 * 存档检查（数据 → 存档检查）。
 *
 * 手机上没有游戏：用户把 .sl2 / .co2 拷到手机后，用 Storage Access Framework 只读选取
 * （ACTION_OPEN_DOCUMENT，不申请存储权限），在本机解密并逐件审计全部角色的遗物。
 * 解析、审计、对比都在 [SaveSession] 的 IO 线程上跑；遗物表与审计索引经 rememberGameData 在后台建好。
 * 桌面端的「自动查找存档」「拖拽打开」在手机上不适用，不提供。
 */
@Suppress("UNUSED_PARAMETER")
@Composable
internal fun SaveScreen(
    catalog: AffixCatalog,
    settings: UserSettings,
    onBack: (() -> Unit)?,
    modifier: Modifier = Modifier,
) {
    // parserId 与返回类型 SaveAuditData 一一对应；审计索引要合并词条库，catalog 在进程内只有一份
    val state = rememberGameData(GameDataKey.RELICS, SaveAuditData.PARSER_ID) { text -> SaveAuditData.build(text, catalog) }
    GameDataScreenScaffold(
        title = DataPage.SAVE.title,
        subtitle = DataPage.SAVE.eyebrow,
        onBack = onBack,
        state = state,
        modifier = modifier,
        loadingLabel = "载入遗物表",
        statusPills = {
            NightPill("存档只读", NightColors.Green, dot = true)
            NightPill("离线解析", NightColors.PurpleSoft)
            (state as? GameDataState.Ready)?.let { ready ->
                NightPill("遗物表 ${ready.value.relicData.gameVersion}", NightColors.TextMuted)
            }
        },
    ) { data -> SaveContent(data = data, catalog = catalog) }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun SaveContent(data: SaveAuditData, catalog: AffixCatalog) {
    val context = LocalContext.current
    val session = SaveSession
    val catalogInfo = remember(catalog) { SaveReportCatalogInfo("内置数据", catalog.gameVersion, catalog.dataVersion) }

    // SAF：只读打开（mime */*：.sl2 / .co2 没有登记的类型）与新建文档（导出报告）
    val openSave = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        if (uri != null) session.open(context.contentResolver, uri, data)
    }
    val openCompare = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        if (uri != null) session.openCompare(context.contentResolver, uri, data)
    }
    val exportText = rememberLauncherForActivityResult(ActivityResultContracts.CreateDocument(SaveReportFormat.TEXT.mimeType)) { uri ->
        if (uri != null) session.writeExport(context, uri, catalogInfo) else session.pendingExport = null
    }
    val exportCsv = rememberLauncherForActivityResult(ActivityResultContracts.CreateDocument(SaveReportFormat.CSV.mimeType)) { uri ->
        if (uri != null) session.writeExport(context, uri, catalogInfo) else session.pendingExport = null
    }

    var characterSheet by rememberSaveable { mutableStateOf(false) }
    var exportSheet by rememberSaveable { mutableStateOf(false) }

    val save = session.save
    val character = save?.characters?.let { characters ->
        characters.firstOrNull { it.slot == session.selectedSlot } ?: characters.firstOrNull()
    }
    val filter = session.filter
    val query = session.query
    val filtered = remember(character, filter, query) { character?.let { filter.apply(it.relics, query) }.orEmpty() }
    val compare = session.compare
    val direction = session.compareDirection
    val compareQuery = session.compareQuery
    val blocks = remember(compare, direction, compareQuery) { compare?.visibleBlocks(direction, compareQuery).orEmpty() }

    fun launchOpen(compareMode: Boolean) {
        try {
            (if (compareMode) openCompare else openSave).launch(arrayOf("*/*"))
        } catch (error: ActivityNotFoundException) {
            session.reportLaunchFailure("没有可用的文件选择器，无法选取存档")
        }
    }

    LazyColumn(
        modifier = Modifier.fillMaxSize(),
        state = rememberLazyListState(),
        contentPadding = GameDataLayout.listPadding(),
        verticalArrangement = Arrangement.spacedBy(GameDataLayout.SectionSpacing),
    ) {
        item(key = "pick", contentType = "pick") {
            PickCard(
                hasSave = save != null && !session.loading,
                loading = session.loading,
                comparing = session.comparing,
                exporting = session.exporting,
                messages = listOfNotNull(
                    session.saveMessage.takeIf { it.isNotEmpty() }?.let { it to true },
                    session.compareMessage.takeIf { it.isNotEmpty() }?.let { it to true },
                    session.exportMessage,
                ),
                onPick = { launchOpen(compareMode = false) },
                onExport = { exportSheet = true },
                onCompare = { launchOpen(compareMode = true) },
            )
        }
        if (session.loading) {
            item(key = "loading", contentType = "progress") { SaveProgressRow("正在读取并检查存档…") }
        } else if (save != null) {
            item(key = "summary", contentType = "summary") { SummaryCard(save) }
            if (compare != null) {
                item(key = "views", contentType = "views") {
                    NightSegmentedControl(
                        items = SaveView.entries.map { it.title },
                        selectedIndex = session.view.ordinal,
                        onSelect = { session.view = SaveView.entries[it] },
                    )
                }
            }
            if (session.view == SaveView.COMPARE && compare != null) {
                saveCompareItems(
                    result = compare,
                    blocks = blocks,
                    base = save,
                    direction = direction,
                    query = compareQuery,
                    onDirection = { session.compareDirection = it },
                    onQuery = { session.compareQuery = it },
                    onClose = { session.closeCompare() },
                )
            } else {
                checkItems(
                    save = save,
                    character = character,
                    filtered = filtered,
                    filter = filter,
                    query = query,
                    onOpenCharacters = { characterSheet = true },
                )
            }
        }
    }

    if (characterSheet && save != null) {
        NightBottomSheet(onDismissRequest = { characterSheet = false }) {
            CharacterPicker(save, character?.slot) { slot ->
                session.selectedSlot = slot
                characterSheet = false
            }
        }
    }

    if (exportSheet && save != null) {
        NightBottomSheet(onDismissRequest = { exportSheet = false }) {
            ExportSheet(
                onSave = { format ->
                    exportSheet = false
                    val now = LocalDateTime.now()
                    session.pendingExport = PendingExport(format, now)
                    try {
                        val launcher = if (format == SaveReportFormat.CSV) exportCsv else exportText
                        launcher.launch(SaveReportBuilder.suggestedFileName(save, format, now))
                    } catch (error: ActivityNotFoundException) {
                        session.pendingExport = null
                        session.reportExportFailure("导出失败：没有可用的文件管理器")
                    }
                },
                onShare = { format ->
                    exportSheet = false
                    session.share(context, format, catalogInfo)
                },
            )
        }
    }
}

@OptIn(ExperimentalFoundationApi::class)
private fun LazyListScope.checkItems(
    save: AuditedSave,
    character: AuditedCharacter?,
    filtered: List<AuditedRelic>,
    filter: SaveFilter,
    query: String,
    onOpenCharacters: () -> Unit,
) {
    if (character == null) {
        item(key = "no-characters", contentType = "empty") {
            SaveEmptyState("存档中没有角色", "未在该存档中找到已占用的角色槽位。")
        }
        return
    }
    // 粘性工具条：角色选择 + 过滤，滚动遗物列表时保持在顶部
    stickyHeader(key = "controls", contentType = "controls") {
        Column(
            modifier = Modifier.fillMaxWidth().background(NightColors.Background).padding(vertical = 6.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            CharacterSelector(character, save.characters.size, onOpenCharacters)
            NightSegmentedControl(
                items = SaveFilter.entries.map { it.title },
                selectedIndex = filter.ordinal,
                onSelect = { SaveSession.filter = SaveFilter.entries[it] },
            )
        }
    }
    item(key = "search", contentType = "search") {
        NightSearchField(query, { SaveSession.query = it }, placeholder = "搜索遗物名、词条名或 ID")
    }
    item(key = "stats", contentType = "stats") {
        val total = character.relics.size
        Row(
            modifier = Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()),
            horizontalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            NightPill("遗物总数 $total", NightColors.PurpleSoft)
            NightPill("合法 ${total - character.invalidCount}", NightColors.Green)
            NightPill("非法 ${character.invalidCount}", NightColors.Red)
            if (character.deepCount > 0) NightPill("深夜遗物 ${character.deepCount}", NightColors.Purple)
        }
    }
    if (character.hasParseError) {
        item(key = "parse-error-${character.slot}", contentType = "empty") {
            SaveEmptyState("该槽位解析失败", character.parseError.orEmpty(), accent = NightColors.Amber.copy(alpha = .4f))
        }
        return
    }
    if (character.invalidCount == 0 && character.relics.isNotEmpty()) {
        item(key = "all-valid-${character.slot}", contentType = "banner") {
            SaveBanner("未发现不合法遗物", NightColors.Green, leading = "🎉")
        }
    }
    if (filtered.isEmpty()) {
        item(key = "empty-${character.slot}", contentType = "empty") {
            SaveEmptyState(filter.emptyTitle(), filter.emptyDetail(character))
        }
    } else {
        items(filtered, key = { "relic-${character.slot}-${it.relic.index}" }, contentType = { "relic" }) { relic ->
            SaveRelicCard(relic = relic, save = save)
        }
    }
}

@Composable
private fun PickCard(
    hasSave: Boolean,
    loading: Boolean,
    comparing: Boolean,
    exporting: Boolean,
    messages: List<Pair<String, Boolean>>,
    onPick: () -> Unit,
    onExport: () -> Unit,
    onCompare: () -> Unit,
) {
    NightPanel(modifier = Modifier.fillMaxWidth()) {
        Column(modifier = Modifier.fillMaxWidth().padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Text("选择存档文件", style = MaterialTheme.typography.titleMedium, color = NightColors.TextPrimary)
            Text(
                "读取《黑夜君临》存档（.sl2 / .co2），逐件校验全部角色的遗物合法性",
                style = MaterialTheme.typography.bodySmall,
                color = NightColors.TextSecondary,
            )
            Text(
                "手机上没有游戏：请先把电脑上的存档文件拷到手机（Windows 默认位于 " +
                    "%APPDATA%\\Nightreign\\<SteamID>\\NR0000.sl2），再点下方按钮在系统文件选择器里选取。" +
                    "支持 .sl2 与 .co2（无缝联机）存档；只读取你选中的这一个文件，不申请存储权限。",
                style = MaterialTheme.typography.bodySmall,
                color = NightColors.TextMuted,
            )
            SavePrimaryButton(label = if (loading) "读取中…" else "选择存档文件", enabled = !loading, onClick = onPick)
            if (hasSave) {
                Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    SaveSecondaryButton("导出报告", Modifier.weight(1f), enabled = !exporting, onClick = onExport)
                    SaveSecondaryButton(
                        if (comparing) "读取中…" else "对比另一份存档",
                        Modifier.weight(1f),
                        enabled = !comparing,
                        onClick = onCompare,
                    )
                }
            }
            if (comparing) SaveProgressRow("正在读取要对比的存档…")
            if (exporting) SaveProgressRow("正在生成报告…")
            messages.forEach { (text, isError) ->
                Text(text, style = MaterialTheme.typography.bodySmall, color = if (isError) NightColors.Red else NightColors.Green)
            }
            Row(
                modifier = Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()),
                horizontalArrangement = Arrangement.spacedBy(6.dp),
            ) {
                NightPill("只读解析，不修改存档", NightColors.Green)
                NightPill("完全离线本地解析，不上传任何数据", NightColors.PurpleSoft)
            }
        }
    }
}

@Composable
private fun SummaryCard(save: AuditedSave) {
    NightPanel(modifier = Modifier.fillMaxWidth()) {
        Column(modifier = Modifier.fillMaxWidth().padding(14.dp), verticalArrangement = Arrangement.spacedBy(9.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(
                    save.fileName,
                    modifier = Modifier.weight(1f),
                    style = MaterialTheme.typography.titleMedium,
                    color = NightColors.TextPrimary,
                )
                NightPill(
                    if (save.checksumOk) "校验和通过" else "校验和异常",
                    if (save.checksumOk) NightColors.Green else NightColors.Amber,
                    dot = true,
                )
            }
            Row(
                modifier = Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()),
                horizontalArrangement = Arrangement.spacedBy(6.dp),
            ) {
                NightPill("角色 ${save.characters.size} · 遗物 ${save.relicCount}", NightColors.PurpleSoft)
                NightPill("非法 ${save.invalidCount}", if (save.invalidCount > 0) NightColors.Red else NightColors.Green)
            }
            if (!save.checksumOk) SaveBanner("存档校验和异常，结果仅供参考", NightColors.Amber, leading = "!")
        }
    }
}

/** 当前角色（点开底部抽屉换角色）。 */
@Composable
private fun CharacterSelector(character: AuditedCharacter, count: Int, onClick: () -> Unit) {
    val shape = RoundedCornerShape(12.dp)
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .heightIn(min = 48.dp)
            .clip(shape)
            .background(NightColors.Field)
            .clickable(role = Role.Button, onClickLabel = "选择角色", onClick = onClick)
            .padding(horizontal = 13.dp, vertical = 8.dp)
            .semantics { contentDescription = "当前角色：${character.displayName}，共 $count 个角色" },
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(1.dp)) {
            Text(character.displayName, style = MaterialTheme.typography.bodyLarge, fontWeight = FontWeight.SemiBold, color = NightColors.TextPrimary, maxLines = 1)
            Text(characterSubtitle(character), style = MaterialTheme.typography.labelSmall, color = NightColors.TextMuted, maxLines = 1)
        }
        Text("切换角色 ▾", style = MaterialTheme.typography.labelMedium, color = NightColors.PurpleSoft)
    }
}

private fun characterSubtitle(character: AuditedCharacter): String =
    if (character.hasParseError) "该槽位解析失败" else "遗物 ${character.relics.size} 件 · 非法 ${character.invalidCount} 件"

@Composable
private fun CharacterPicker(save: AuditedSave, selectedSlot: Int?, onSelect: (Int) -> Unit) {
    Column(modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Text("选择角色", style = MaterialTheme.typography.titleLarge)
        Text("${save.characters.size} 个已占用的角色槽位", style = MaterialTheme.typography.bodySmall, color = NightColors.TextMuted)
        LazyColumn(modifier = Modifier.heightIn(max = 590.dp)) {
            items(save.characters, key = { it.slot }) { character ->
                val selected = character.slot == selectedSlot
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .heightIn(min = 56.dp)
                        .clickable(role = Role.Button) { onSelect(character.slot) }
                        .padding(vertical = 8.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(10.dp),
                ) {
                    Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                        Text(
                            character.displayName,
                            style = MaterialTheme.typography.bodyLarge,
                            fontWeight = if (selected) FontWeight.SemiBold else FontWeight.Normal,
                            color = if (selected) NightColors.PurpleSoft else NightColors.TextPrimary,
                        )
                        Text(
                            characterSubtitle(character),
                            style = MaterialTheme.typography.labelSmall,
                            color = if (character.hasParseError) NightColors.Amber else NightColors.TextMuted,
                        )
                    }
                    if (character.invalidCount > 0) NightPill("非法 ${character.invalidCount}", NightColors.Red)
                    if (selected) Text("✓", style = MaterialTheme.typography.titleMedium, color = NightColors.PurpleSoft)
                }
                HorizontalDivider(color = NightColors.Border.copy(alpha = .7f))
            }
        }
        Spacer(Modifier.height(14.dp))
    }
}

@Composable
private fun ExportSheet(onSave: (SaveReportFormat) -> Unit, onShare: (SaveReportFormat) -> Unit) {
    Column(modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Text("导出存档检查报告", style = MaterialTheme.typography.titleLarge)
        Text(
            "文本报告按角色列出每件非法遗物的种类、词条与问题；表格每行一件遗物，便于在表格软件里排序筛选。" +
                "「保存到文件」由系统文件管理器选择位置，「分享」交给其它应用。",
            style = MaterialTheme.typography.bodySmall,
            color = NightColors.TextMuted,
        )
        SaveReportFormat.entries.forEach { format ->
            NightPanel(modifier = Modifier.fillMaxWidth()) {
                Column(modifier = Modifier.fillMaxWidth().padding(14.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    Text(format.title, style = MaterialTheme.typography.titleMedium, color = NightColors.TextPrimary)
                    Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        SaveSecondaryButton("保存到文件", Modifier.weight(1f), accent = NightColors.PurpleSoft) { onSave(format) }
                        SaveSecondaryButton("分享", Modifier.weight(1f), accent = NightColors.PurpleSoft) { onShare(format) }
                    }
                }
            }
        }
        Spacer(Modifier.height(14.dp))
    }
}
