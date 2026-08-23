package com.nightreign.relicchecker.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
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
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.nightreign.relicchecker.catalog.AffixCatalog
import com.nightreign.relicchecker.rules.Affix
import com.nightreign.relicchecker.rules.CheckMode
import com.nightreign.relicchecker.rules.matchesSearch
import com.nightreign.relicchecker.ui.theme.NightColors

private const val ALL_MODES = "ALL"

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun CatalogScreen(
    catalog: AffixCatalog,
    compact: Boolean,
    modifier: Modifier = Modifier,
) {
    var query by rememberSaveable { mutableStateOf("") }
    var filterName by rememberSaveable { mutableStateOf(ALL_MODES) }
    var detail by remember { mutableStateOf<Affix?>(null) }
    val filterMode = filterName.takeUnless { it == ALL_MODES }?.let(CheckMode::valueOf)
    val filtered = remember(query, filterMode, catalog) {
        catalog.affixes.asSequence()
            .filter { filterMode == null || it.isEligible(filterMode) }
            .filter { it.matchesSearch(query) }
            .sortedWith(compareBy(Affix::sortId, Affix::effectId))
            .toList()
    }

    Column(
        modifier = modifier.fillMaxSize().padding(top = 14.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Column(
            modifier = Modifier.padding(horizontal = 16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            NightTopBar(
                title = "词条库",
                eyebrow = "AFFIX CATALOG",
                trailing = "${catalog.affixes.size} 条",
            )
            NightSearchField(query, { query = it }, placeholder = "名称、别名、分类或 effectId")
            Row(
                modifier = Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                ModePill("全部", filterMode == null) { filterName = ALL_MODES }
                CheckMode.entries.forEach { mode ->
                    ModePill(mode.shortTitle, filterMode == mode) { filterName = mode.name }
                }
            }
            SectionLabel(
                text = "${filtered.size} 条结果",
                trailing = if (compact) "紧凑显示 · sortId / effectId" else "sortId / effectId 排序",
            )
        }

        HorizontalDivider(color = NightColors.Border)
        if (filtered.isEmpty()) {
            Column(
                modifier = Modifier.fillMaxSize().padding(32.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.Center,
            ) {
                NightPill("0 条", NightColors.TextMuted)
                Spacer(Modifier.size(12.dp))
                Text("没有匹配词条", style = MaterialTheme.typography.titleMedium)
                Text("调整搜索关键词或模式筛选", color = NightColors.TextMuted)
            }
        } else {
            LazyColumn(modifier = Modifier.weight(1f)) {
                items(filtered, key = Affix::effectId) { affix ->
                    CatalogRow(affix = affix, compact = compact) { detail = affix }
                    HorizontalDivider(
                        modifier = Modifier.padding(horizontal = 16.dp),
                        color = NightColors.Border.copy(alpha = .68f),
                    )
                }
            }
        }
    }

    detail?.let { affix ->
        ModalBottomSheet(
            onDismissRequest = { detail = null },
            sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
            containerColor = NightColors.Elevated,
            contentColor = NightColors.TextPrimary,
            scrimColor = NightColors.BackgroundDeep.copy(alpha = .82f),
            dragHandle = {
                Box(
                    Modifier.padding(vertical = 10.dp).size(36.dp, 4.dp)
                        .background(NightColors.BorderStrong, RoundedCornerShape(99.dp)),
                )
            },
        ) { AffixDetailSheet(affix) }
    }
}

@Composable
private fun ModePill(label: String, selected: Boolean, onClick: () -> Unit) {
    val shape = RoundedCornerShape(999.dp)
    Box(
        modifier = Modifier
            .clip(shape)
            .background(if (selected) NightColors.Purple else NightColors.FieldSoft)
            .border(1.dp, if (selected) NightColors.PurpleSoft.copy(alpha = .35f) else NightColors.Border, shape)
            .clickable(onClick = onClick)
            .padding(horizontal = 14.dp, vertical = 9.dp),
    ) {
        Text(label, style = MaterialTheme.typography.labelMedium, color = if (selected) NightColors.TextPrimary else NightColors.TextSecondary)
    }
}

@Composable
private fun CatalogRow(affix: Affix, compact: Boolean, onClick: () -> Unit) {
    Row(
        modifier = Modifier.fillMaxWidth().clickable(onClick = onClick)
            .padding(horizontal = 16.dp, vertical = if (compact) 9.dp else 13.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(
            modifier = Modifier.size(if (compact) 5.dp else 7.dp)
                .background(if (affix.isCurse) NightColors.Red else NightColors.Purple, RoundedCornerShape(99.dp)),
        )
        Spacer(Modifier.size(11.dp))
        AffixSummary(affix, Modifier.weight(1f), compact = compact, showDescription = !compact)
        if (affix.isCurse) NightPill("负面", NightColors.Red)
        else Text("›", style = MaterialTheme.typography.titleLarge, color = NightColors.TextMuted)
    }
}

@Composable
private fun AffixDetailSheet(affix: Affix) {
    Column(
        modifier = Modifier.fillMaxWidth().heightIn(max = 670.dp)
            .verticalScroll(rememberScrollState()).padding(horizontal = 18.dp, vertical = 4.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        Row(verticalAlignment = Alignment.Top) {
            Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(5.dp)) {
                Text(affix.name, style = MaterialTheme.typography.titleLarge)
                Text("effectId ${affix.effectId}", color = NightColors.PurpleSoft, style = MaterialTheme.typography.labelMedium)
            }
            if (affix.isCurse) NightPill("负面词条", NightColors.Red)
            else if (affix.requiresCurse) NightPill("需诅咒", NightColors.Amber)
        }
        if (affix.explanation.isNotBlank()) {
            NightPanel(modifier = Modifier.fillMaxWidth()) {
                Text(
                    affix.explanation,
                    modifier = Modifier.padding(14.dp),
                    color = NightColors.TextSecondary,
                    style = MaterialTheme.typography.bodyMedium,
                )
            }
        }
        SectionLabel("结构参数")
        NightPanel(modifier = Modifier.fillMaxWidth()) {
            Column(modifier = Modifier.padding(horizontal = 14.dp, vertical = 6.dp)) {
                DetailLine("sortId", affix.sortId.toString())
                DetailLine("分类", affix.category)
                DetailLine("互斥池", affix.compatibilityId.toString())
                DetailLine("槽池", affix.poolIds.ifEmpty { listOf(-1) }.joinToString())
                DetailLine("叠加性", affix.superposability)
                DetailLine("类型", if (affix.isCurse) "负面词条" else "正面词条")
                DetailLine("需诅咒", if (affix.requiresCurse) "是" else "否")
                if (affix.popularity != null) DetailLine("历史热度", affix.popularity.toString())
            }
        }
        if (affix.aliases.isNotEmpty()) {
            SectionLabel("别名")
            Text(affix.aliases.joinToString("；"), color = NightColors.TextSecondary)
        }
        if (affix.source.isNotBlank()) {
            SectionLabel("来源")
            Text(affix.source, color = NightColors.TextSecondary, style = MaterialTheme.typography.bodySmall)
        }
        Spacer(Modifier.size(22.dp))
    }
}

@Composable
private fun DetailLine(label: String, value: String) {
    Row(modifier = Modifier.fillMaxWidth().padding(vertical = 9.dp), horizontalArrangement = Arrangement.spacedBy(16.dp)) {
        Text(label, style = MaterialTheme.typography.bodySmall, color = NightColors.TextMuted)
        Text(value, modifier = Modifier.weight(1f), style = MaterialTheme.typography.bodyMedium, color = NightColors.TextPrimary, fontWeight = FontWeight.Medium)
    }
}
