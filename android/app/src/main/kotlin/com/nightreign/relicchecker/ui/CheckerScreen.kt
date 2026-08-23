package com.nightreign.relicchecker.ui

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
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
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.nightreign.relicchecker.catalog.AffixCatalog
import com.nightreign.relicchecker.rules.Affix
import com.nightreign.relicchecker.rules.CheckIssue
import com.nightreign.relicchecker.rules.CheckMode
import com.nightreign.relicchecker.rules.CheckResult
import com.nightreign.relicchecker.rules.CheckStatus
import com.nightreign.relicchecker.rules.LegalityChecker
import com.nightreign.relicchecker.rules.matchesSearch
import com.nightreign.relicchecker.ui.theme.NightColors

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun CheckerScreen(
    catalog: AffixCatalog,
    settings: UserSettings,
    modifier: Modifier = Modifier,
) {
    val checker = remember { LegalityChecker() }
    var modeName by rememberSaveable { mutableStateOf(settings.defaultMode.name) }
    val mode = CheckMode.valueOf(modeName)
    var selectedIds by rememberSaveable { mutableStateOf(List(3) { -1 }) }
    val selected = selectedIds.map { id -> catalog.affixes.firstOrNull { it.effectId == id } }
    var manualRequested by rememberSaveable { mutableStateOf(false) }
    var transientResult by remember { mutableStateOf<CheckResult?>(null) }
    var pickerSlot by rememberSaveable { mutableStateOf<Int?>(null) }
    val complete = selected.all { it != null }
    val currentResult = when {
        transientResult != null -> transientResult
        complete && (settings.autoInspect || manualRequested) -> checker.check(selected.filterNotNull(), mode)
        else -> null
    }

    Column(
        modifier = modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 16.dp, vertical = 14.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        NightTopBar(
            title = "夜幕验物",
            eyebrow = "NIGHTREIGN RELIC CHECKER",
            trailing = "完全离线",
        )

        SectionLabel("校验口径", "当前 ${mode.shortTitle}")
        NightSegmentedControl(
            items = CheckMode.entries.map(CheckMode::shortTitle),
            selectedIndex = CheckMode.entries.indexOf(mode),
            onSelect = { index ->
                modeName = CheckMode.entries[index].name
                manualRequested = false
                transientResult = null
            },
        )
        Text(mode.detail, style = MaterialTheme.typography.bodySmall, color = NightColors.TextMuted)

        if (mode == CheckMode.DEEP_POSITIVE) {
            DeepModeNotice()
        }

        SectionLabel("从上到下选择三条效果", "顺序会参与判断")
        selected.forEachIndexed { index, affix ->
            AffixSlot(
                index = index,
                affix = affix,
                onChoose = { pickerSlot = index },
                onClear = {
                    selectedIds = selectedIds.toMutableList().also { it[index] = -1 }
                    manualRequested = false
                    transientResult = null
                },
            )
        }

        if (!settings.autoInspect) {
            Button(
                onClick = {
                    manualRequested = true
                    transientResult = null
                },
                enabled = complete,
                modifier = Modifier.fillMaxWidth().height(50.dp),
                shape = RoundedCornerShape(13.dp),
                colors = ButtonDefaults.buttonColors(
                    containerColor = NightColors.Purple,
                    contentColor = NightColors.TextPrimary,
                    disabledContainerColor = NightColors.FieldSoft,
                    disabledContentColor = NightColors.TextMuted,
                ),
            ) { Text("检查这件遗物", fontWeight = FontWeight.SemiBold) }
        }

        Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            UtilityAction("随机合法组合", Modifier.weight(1f)) {
                val combination = checker.randomCombination(catalog.affixes, mode)
                if (combination == null) {
                    transientResult = CheckResult(CheckStatus.INVALID, "当前词条库无法生成合法组合")
                } else {
                    selectedIds = combination.map(Affix::effectId)
                    manualRequested = !settings.autoInspect
                    transientResult = null
                }
            }
            UtilityAction("规范排序", Modifier.weight(1f), enabled = complete) {
                selectedIds = checker.canonicalOrder(selected.filterNotNull()).map(Affix::effectId)
                manualRequested = !settings.autoInspect
                transientResult = null
            }
            UtilityAction("清空", Modifier.weight(.72f)) {
                selectedIds = List(3) { -1 }
                manualRequested = false
                transientResult = null
            }
        }

        SectionLabel("检查结果", if (settings.autoInspect) "自动检查已开启" else "手动检查")
        ResultPanel(result = currentResult, selectedCount = selected.count { it != null })
        Spacer(Modifier.height(3.dp))
    }

    pickerSlot?.let { slot ->
        val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
        ModalBottomSheet(
            onDismissRequest = { pickerSlot = null },
            sheetState = sheetState,
            containerColor = NightColors.Elevated,
            contentColor = NightColors.TextPrimary,
            scrimColor = NightColors.BackgroundDeep.copy(alpha = .82f),
            dragHandle = {
                Box(
                    Modifier.padding(vertical = 10.dp).size(36.dp, 4.dp)
                        .background(NightColors.BorderStrong, RoundedCornerShape(99.dp)),
                )
            },
        ) {
            AffixPicker(
                slot = slot,
                catalog = catalog,
                mode = mode,
                defaultShowUnavailable = settings.selectorShowUnavailable,
                onSelect = { affix ->
                    selectedIds = selectedIds.toMutableList().also { it[slot] = affix.effectId }
                    manualRequested = false
                    transientResult = null
                    pickerSlot = null
                },
            )
        }
    }
}

@Composable
private fun DeepModeNotice() {
    NightPanel(borderColor = NightColors.Amber.copy(alpha = .38f), modifier = Modifier.fillMaxWidth()) {
        Row(
            modifier = Modifier.padding(horizontal = 14.dp, vertical = 12.dp),
            horizontalArrangement = Arrangement.spacedBy(10.dp),
            verticalAlignment = Alignment.Top,
        ) {
            NightPill("预检", NightColors.Amber)
            Text(
                "只验证三条正面效果。完整深夜遗物仍需结合具体遗物 ID、真实槽池模板与负面词条逐行配对。",
                style = MaterialTheme.typography.bodySmall,
                color = NightColors.TextSecondary,
                modifier = Modifier.weight(1f),
            )
        }
    }
}

@Composable
private fun AffixSlot(index: Int, affix: Affix?, onChoose: () -> Unit, onClear: () -> Unit) {
    val shape = RoundedCornerShape(15.dp)
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .heightIn(min = 70.dp)
            .clip(shape)
            .background(NightColors.Card)
            .border(1.dp, if (affix == null) NightColors.Border else NightColors.BorderStrong, shape)
            .clickable(onClick = onChoose)
            .padding(start = 12.dp, end = 7.dp, top = 10.dp, bottom = 10.dp)
            .semantics { contentDescription = "第 ${index + 1} 条词条，${affix?.name ?: "未选择"}" },
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(
            modifier = Modifier
                .size(34.dp)
                .background(NightColors.Purple.copy(alpha = .13f), CircleShape)
                .border(1.dp, NightColors.PurpleSoft.copy(alpha = .25f), CircleShape),
            contentAlignment = Alignment.Center,
        ) {
            Text("${index + 1}", color = NightColors.PurpleSoft, fontWeight = FontWeight.Bold)
        }
        Spacer(Modifier.width(11.dp))
        if (affix == null) {
            Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                Text("选择词条", color = NightColors.TextPrimary, fontWeight = FontWeight.SemiBold)
                Text("点按搜索内置词条库", style = MaterialTheme.typography.bodySmall, color = NightColors.TextMuted)
            }
            Text("＋", style = MaterialTheme.typography.titleLarge, color = NightColors.PurpleSoft, modifier = Modifier.padding(12.dp))
        } else {
            AffixSummary(affix, Modifier.weight(1f), showDescription = false)
            Box(
                modifier = Modifier.size(44.dp).clickable(
                    interactionSource = remember { MutableInteractionSource() },
                    indication = null,
                    onClick = onClear,
                ),
                contentAlignment = Alignment.Center,
            ) { Text("×", style = MaterialTheme.typography.titleLarge, color = NightColors.TextMuted) }
        }
    }
}

@Composable
private fun UtilityAction(
    label: String,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    onClick: () -> Unit,
) {
    val shape = RoundedCornerShape(11.dp)
    Box(
        modifier = modifier
            .height(44.dp)
            .clip(shape)
            .background(if (enabled) NightColors.FieldSoft else NightColors.Field)
            .border(1.dp, NightColors.Border, shape)
            .clickable(enabled = enabled, onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        Text(label, style = MaterialTheme.typography.labelMedium, color = if (enabled) NightColors.TextSecondary else NightColors.TextMuted)
    }
}

@Composable
private fun AffixPicker(
    slot: Int,
    catalog: AffixCatalog,
    mode: CheckMode,
    defaultShowUnavailable: Boolean,
    onSelect: (Affix) -> Unit,
) {
    var query by rememberSaveable(slot, mode.name) { mutableStateOf("") }
    var showUnavailable by rememberSaveable(slot, mode.name) { mutableStateOf(defaultShowUnavailable) }
    val filtered = remember(query, showUnavailable, mode, catalog) {
        catalog.affixes.asSequence()
            .filter { !it.isCurse }
            .filter { showUnavailable || it.isEligible(mode) }
            .filter { it.matchesSearch(query) }
            .sortedWith(compareByDescending<Affix> { it.isEligible(mode) }.thenBy(Affix::sortId).thenBy(Affix::effectId))
            .toList()
    }

    Column(
        modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Column(modifier = Modifier.weight(1f)) {
                Text("选择第 ${slot + 1} 条词条", style = MaterialTheme.typography.titleLarge)
                Text(mode.title, style = MaterialTheme.typography.bodySmall, color = NightColors.TextMuted)
            }
            NightPill("${filtered.size} 条", NightColors.PurpleSoft)
        }
        NightSearchField(query, { query = it }, placeholder = "名称、别名、分类或 effectId")
        NightSegmentedControl(
            items = listOf("当前可用", "显示全部"),
            selectedIndex = if (showUnavailable) 1 else 0,
            onSelect = { showUnavailable = it == 1 },
            height = 38.dp,
        )
        LazyColumn(modifier = Modifier.heightIn(min = 300.dp, max = 590.dp)) {
            items(filtered, key = Affix::effectId) { affix ->
                Row(
                    modifier = Modifier.fillMaxWidth().clickable { onSelect(affix) }.padding(vertical = 11.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    AffixSummary(affix, Modifier.weight(1f), compact = true)
                    if (!affix.isEligible(mode)) NightPill("当前不可用", NightColors.Red)
                }
                HorizontalDivider(color = NightColors.Border.copy(alpha = .7f))
            }
        }
        Spacer(Modifier.height(14.dp))
    }
}

@Composable
private fun ResultPanel(result: CheckResult?, selectedCount: Int) {
    val borderColor = when (result?.status) {
        CheckStatus.VALID -> NightColors.Green
        CheckStatus.WRONG_ORDER -> NightColors.Amber
        CheckStatus.INVALID -> NightColors.Red
        else -> NightColors.Border
    }
    NightPanel(
        modifier = Modifier.fillMaxWidth().heightIn(min = 142.dp).semantics { liveRegion = LiveRegionMode.Polite },
        borderColor = borderColor.copy(alpha = if (result == null) .8f else .5f),
    ) {
        AnimatedContent(
            targetState = result,
            transitionSpec = { fadeIn(tween(180)) togetherWith fadeOut(tween(140)) },
            label = "check-result",
        ) { value ->
            if (value == null) {
                Column(
                    modifier = Modifier.fillMaxWidth().padding(18.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    NightPill(if (selectedCount == 3) "等待检查" else "$selectedCount / 3", NightColors.PurpleSoft)
                    Text(
                        if (selectedCount == 3) "三个词条已就绪" else "还需要选择 ${3 - selectedCount} 条效果",
                        style = MaterialTheme.typography.titleMedium,
                    )
                    Text("检查结果、错误原因与规范顺序会显示在这里。", color = NightColors.TextMuted, style = MaterialTheme.typography.bodySmall)
                }
            } else {
                ResultContent(value)
            }
        }
    }
}

@Composable
private fun ResultContent(result: CheckResult) {
    val accent = when (result.status) {
        CheckStatus.VALID -> NightColors.Green
        CheckStatus.WRONG_ORDER -> NightColors.Amber
        CheckStatus.INVALID -> NightColors.Red
        CheckStatus.INCOMPLETE -> NightColors.TextMuted
    }
    Column(modifier = Modifier.padding(17.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        NightPill(
            when (result.status) {
                CheckStatus.VALID -> "合法"
                CheckStatus.WRONG_ORDER -> "顺序错误"
                CheckStatus.INVALID -> "不合法"
                CheckStatus.INCOMPLETE -> "未完成"
            },
            accent,
        )
        Text(result.message, style = MaterialTheme.typography.titleMedium, color = NightColors.TextPrimary)
        result.issues.forEach { IssueRow(it, warning = false) }
        result.warnings.forEach { IssueRow(it, warning = true) }
        if (result.orderedAffixes.isNotEmpty()) {
            Text("规范顺序", style = MaterialTheme.typography.labelLarge, color = NightColors.TextSecondary)
            result.orderedAffixes.forEachIndexed { index, affix ->
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text("${index + 1}", color = accent, fontWeight = FontWeight.Bold)
                    Text(affix.name, modifier = Modifier.weight(1f), maxLines = 2, overflow = TextOverflow.Ellipsis)
                    Text("${affix.sortId} / ${affix.effectId}", style = MaterialTheme.typography.labelSmall, color = NightColors.TextMuted)
                }
            }
        }
    }
}

@Composable
private fun IssueRow(issue: CheckIssue, warning: Boolean) {
    Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
        Text(
            (if (warning) "提示 · " else "问题 · ") + issue.title,
            color = if (warning) NightColors.Amber else NightColors.Red,
            fontWeight = FontWeight.SemiBold,
            style = MaterialTheme.typography.bodyMedium,
        )
        Text(issue.detail, style = MaterialTheme.typography.bodySmall, color = NightColors.TextSecondary)
    }
}
