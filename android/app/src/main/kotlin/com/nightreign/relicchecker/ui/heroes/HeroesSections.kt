package com.nightreign.relicchecker.ui.heroes

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Slider
import androidx.compose.material3.SliderDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import com.nightreign.relicchecker.gamedata.heroes.HeroCrossCheck
import com.nightreign.relicchecker.gamedata.heroes.HeroDeltaTone
import com.nightreign.relicchecker.gamedata.heroes.HeroEntry
import com.nightreign.relicchecker.gamedata.heroes.HeroLibraRespec
import com.nightreign.relicchecker.gamedata.heroes.HeroModifierSource
import com.nightreign.relicchecker.gamedata.heroes.HeroModifierSourceTag
import com.nightreign.relicchecker.gamedata.heroes.HeroNote
import com.nightreign.relicchecker.gamedata.heroes.HeroRelicItem
import com.nightreign.relicchecker.gamedata.heroes.HeroSource
import com.nightreign.relicchecker.gamedata.heroes.HeroStatModifier
import com.nightreign.relicchecker.gamedata.heroes.HeroStatNames
import com.nightreign.relicchecker.gamedata.heroes.HeroStatsCopy
import com.nightreign.relicchecker.gamedata.heroes.HeroStatsSnapshot
import com.nightreign.relicchecker.gamedata.heroes.HeroStatsText
import com.nightreign.relicchecker.ui.NightBottomSheet
import com.nightreign.relicchecker.ui.NightPanel
import com.nightreign.relicchecker.ui.NightPill
import com.nightreign.relicchecker.ui.NightSegmentedControl
import com.nightreign.relicchecker.ui.SectionLabel
import com.nightreign.relicchecker.ui.gamedata.GameDataLayout
import com.nightreign.relicchecker.ui.theme.NightColors
import kotlin.math.roundToInt

// 「角色属性」页的分区组件。配色只用 NightColors；本页额外需要的两种蓝（词条「沿用锚点」
// 与遗物蓝色）是桌面端同一色值的私有版本，不改共用 Theme。

/** 本页私有配色表。 */
internal object HeroPalette {
    /** 「词条沿用 N 级锚点」的蓝：取 Windows `.pill--blue` / macOS HeroFormat.sourceBlue 的 #7AB8F5。 */
    val SourceBlue = Color(0xFF7AB8F5)

    /** 遗物蓝（macOS SaveRelicCard.colorPill 的 0.38 / 0.60 / 0.98）。 */
    private val RelicBlue = Color(0xFF619AFA)

    /** 三档三色：锚点绿 / 推算琥珀 / 沿用蓝（颜色名由 :gamedata 的 colorToken 给出，三端同一张表）。 */
    fun source(source: HeroModifierSource): Color = when (source.colorToken) {
        "green" -> NightColors.Green
        "amber" -> NightColors.Amber
        "blue" -> SourceBlue
        else -> NightColors.TextSecondary
    }

    /** 增减量配色：涨绿、跌红、不变中性。 */
    fun tone(tone: HeroDeltaTone): Color = when (tone) {
        HeroDeltaTone.UP -> NightColors.Green
        HeroDeltaTone.DOWN -> NightColors.Red
        HeroDeltaTone.FLAT -> NightColors.TextSecondary
    }

    /** 遗物颜色码（0 红 / 1 蓝 / 2 黄 / 3 绿 / 4 白）→ 展示色。 */
    fun relic(code: Int): Color = when (code) {
        0 -> NightColors.Red
        1 -> RelicBlue
        2 -> NightColors.Amber
        3 -> NightColors.Green
        4 -> NightColors.TextPrimary.copy(alpha = .72f)
        else -> NightColors.TextSecondary
    }
}

/** 等宽数字：数值列 / 卡片大数字对齐用。 */
internal fun TextStyle.tabular(): TextStyle = copy(fontFeatureSettings = "tnum")

/** 数据集原文的 `**粗体**` 标记渲染成粗体，而不是把星号原样显示出来。 */
@Composable
internal fun rememberBoldText(text: String): AnnotatedString = remember(text) {
    buildAnnotatedString {
        HeroStatsText.boldSegments(text).forEach { (part, bold) ->
            if (bold) {
                withStyle(SpanStyle(fontWeight = FontWeight.SemiBold, color = NightColors.TextPrimary)) { append(part) }
            } else {
                append(part)
            }
        }
    }
}

private val SectionPadding = Modifier.padding(vertical = 6.dp)

// ---------------------------------------------------------------- 工具条

/**
 * 粘性工具条（LazyColumn 外）：视图切换 + 等级滑块。
 *
 * [compact]（横屏等矮窗口）时两者并成一行：外壳顶栏、状态药丸和底栏已占去大半高度，
 * 分两行会把列表挤到只剩一两行可见。
 */
@Composable
internal fun HeroToolbar(
    views: List<String>,
    viewIndex: Int,
    onView: (Int) -> Unit,
    level: Int,
    maxLevel: Int,
    isAnchorLevel: Boolean,
    onLevel: (Int) -> Unit,
    compact: Boolean = false,
) {
    if (compact) {
        Row(
            modifier = Modifier.fillMaxWidth().padding(horizontal = GameDataLayout.Gutter),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            NightSegmentedControl(
                items = views,
                selectedIndex = viewIndex,
                onSelect = onView,
                modifier = Modifier.weight(.38f),
            )
            LevelControls(level, maxLevel, isAnchorLevel, onLevel, Modifier.weight(.62f))
        }
    } else {
        Column(
            modifier = Modifier.padding(horizontal = GameDataLayout.Gutter),
            verticalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            NightSegmentedControl(items = views, selectedIndex = viewIndex, onSelect = onView)
            LevelControls(level, maxLevel, isAnchorLevel, onLevel, Modifier.fillMaxWidth())
        }
    }
}

/** 等级行：− / 滑块 / + / 「N 级 · 锚点或插值」。 */
@Composable
private fun LevelControls(
    level: Int,
    maxLevel: Int,
    isAnchorLevel: Boolean,
    onLevel: (Int) -> Unit,
    modifier: Modifier = Modifier,
) {
    Row(modifier = modifier, verticalAlignment = Alignment.CenterVertically) {
        StepButton("−", "降低等级", enabled = level > 1) { onLevel(level - 1) }
        if (maxLevel > 1) {
            Slider(
                value = level.toFloat(),
                onValueChange = { onLevel(it.roundToInt()) },
                valueRange = 1f..maxLevel.toFloat(),
                steps = (maxLevel - 2).coerceAtLeast(0),
                modifier = Modifier.weight(1f).semantics { contentDescription = "等级" },
                colors = SliderDefaults.colors(
                    thumbColor = NightColors.PurpleSoft,
                    activeTrackColor = NightColors.Purple,
                    inactiveTrackColor = NightColors.FieldSoft,
                    activeTickColor = NightColors.PurpleSoft.copy(alpha = .55f),
                    inactiveTickColor = NightColors.BorderStrong,
                ),
            )
        } else {
            Spacer(Modifier.weight(1f))
        }
        StepButton("+", "提高等级", enabled = level < maxLevel) { onLevel(level + 1) }
        Column(modifier = Modifier.widthIn(min = 60.dp), horizontalAlignment = Alignment.End) {
            Text(
                "$level 级",
                style = MaterialTheme.typography.titleMedium.tabular(),
                color = NightColors.TextPrimary,
            )
            Text(
                if (isAnchorLevel) HeroStatsCopy.BASE_ANCHOR_TAG else HeroStatsCopy.BASE_INTERPOLATED_TAG,
                style = MaterialTheme.typography.labelSmall,
                color = if (isAnchorLevel) NightColors.Green else NightColors.TextMuted,
            )
        }
    }
}

@Composable
private fun StepButton(glyph: String, label: String, enabled: Boolean, onClick: () -> Unit) {
    Box(
        modifier = Modifier
            .size(48.dp) // 触控目标 48dp，视觉圆 32dp
            .clip(CircleShape)
            .clickable(enabled = enabled, role = Role.Button, onClickLabel = label, onClick = onClick)
            .semantics { contentDescription = label },
        contentAlignment = Alignment.Center,
    ) {
        Box(
            modifier = Modifier
                .size(32.dp)
                .clip(CircleShape)
                .background(if (enabled) NightColors.FieldSoft else NightColors.Field)
                .border(1.dp, NightColors.Border, CircleShape),
            contentAlignment = Alignment.Center,
        ) {
            Text(
                glyph,
                style = MaterialTheme.typography.titleMedium,
                color = if (enabled) NightColors.TextPrimary else NightColors.TextMuted,
            )
        }
    }
}

// ---------------------------------------------------------------- 角色选择

@Composable
internal fun HeroPickerSection(heroes: List<HeroEntry>, selectedKey: String, onSelect: (String) -> Unit) {
    val selectedIndex = heroes.indexOfFirst { it.key == selectedKey }.coerceAtLeast(0)
    val rowState = rememberLazyListState(initialFirstVisibleItemIndex = (selectedIndex - 1).coerceAtLeast(0))
    Column(modifier = SectionPadding, verticalArrangement = Arrangement.spacedBy(8.dp)) {
        SectionLabel("选择夜行者", "共 ${heroes.size} 位")
        LazyRow(state = rowState, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            itemsIndexed(heroes, key = { _, hero -> hero.key }) { _, hero ->
                HeroChip(hero, hero.key == selectedKey) { onSelect(hero.key) }
            }
        }
    }
}

@Composable
private fun HeroChip(hero: HeroEntry, selected: Boolean, onClick: () -> Unit) {
    val shape = RoundedCornerShape(12.dp)
    Column(
        modifier = Modifier
            .heightIn(min = 48.dp)
            .clip(shape)
            .background(if (selected) NightColors.PurpleDeep.copy(alpha = .85f) else NightColors.Field)
            .border(1.dp, if (selected) NightColors.PurpleSoft else NightColors.Border, shape)
            .clickable(role = Role.Tab, onClick = onClick)
            .semantics { this.selected = selected }
            .padding(horizontal = 14.dp, vertical = 7.dp),
        verticalArrangement = Arrangement.Center,
    ) {
        Text(
            hero.display,
            style = MaterialTheme.typography.bodyMedium,
            fontWeight = FontWeight.SemiBold,
            color = if (selected) NightColors.TextPrimary else NightColors.TextSecondary,
        )
        Text(
            hero.nameEn,
            style = MaterialTheme.typography.labelSmall,
            color = if (selected) NightColors.TextPrimary.copy(alpha = .75f) else NightColors.TextMuted,
        )
    }
}

// ---------------------------------------------------------------- 转职遗物

@Composable
internal fun ModifierSection(
    modifiers: List<HeroStatModifier>,
    selectedIds: Set<Int>,
    level: Int,
    sourceTag: HeroModifierSourceTag?,
    names: HeroStatNames,
    ruleHint: String,
    onToggle: (Int) -> Unit,
) {
    Column(modifier = SectionPadding, verticalArrangement = Arrangement.spacedBy(8.dp)) {
        SectionLabel(
            "转职遗物",
            if (selectedIds.isEmpty()) HeroStatsCopy.modifierCountBadge(modifiers.size) else "已勾选 ${selectedIds.size} 条",
        )
        Text(HeroStatsCopy.MODIFIER_SUBTITLE, style = MaterialTheme.typography.bodySmall, color = NightColors.TextMuted)
        if (modifiers.isEmpty()) {
            Text(HeroStatsCopy.NO_MODIFIER_DATA, style = MaterialTheme.typography.bodySmall, color = NightColors.TextMuted)
        }
        modifiers.forEach { statModifier ->
            ModifierToggleCard(
                statModifier = statModifier,
                checked = statModifier.affixId in selectedIds,
                level = level,
                sourceTag = sourceTag,
                names = names,
                onToggle = { onToggle(statModifier.affixId) },
            )
        }
        if (modifiers.isNotEmpty()) {
            Text(ruleHint, style = MaterialTheme.typography.labelSmall, color = NightColors.TextMuted)
        }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun ModifierToggleCard(
    statModifier: HeroStatModifier,
    checked: Boolean,
    level: Int,
    sourceTag: HeroModifierSourceTag?,
    names: HeroStatNames,
    onToggle: () -> Unit,
) {
    val shape = RoundedCornerShape(13.dp)
    val row = statModifier.level(level)
    val delta = row?.delta.orEmpty()
    val floorAlt = row?.deltaFloorAlt.orEmpty()
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(shape)
            .background(if (checked) NightColors.Purple.copy(alpha = .11f) else NightColors.Field)
            .border(1.dp, if (checked) NightColors.PurpleSoft.copy(alpha = .45f) else NightColors.Border, shape)
            .toggleable(value = checked, role = Role.Checkbox, onValueChange = { onToggle() })
            .padding(horizontal = 12.dp, vertical = 11.dp),
        horizontalArrangement = Arrangement.spacedBy(11.dp),
    ) {
        CheckGlyph(checked, Modifier.padding(top = 1.dp))
        Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(5.dp)) {
            Text(
                statModifier.display,
                style = MaterialTheme.typography.bodyMedium,
                fontWeight = FontWeight.SemiBold,
                color = if (checked) NightColors.TextPrimary else NightColors.TextSecondary,
            )
            if (sourceTag != null || statModifier.dlcOnly) {
                FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    // 标的是「本级增减量的来历」，与勾没勾无关（三档三色，与桌面端同一张表）
                    sourceTag?.let { SourcePill(it) }
                    if (statModifier.dlcOnly) NightPill(HeroStatsCopy.DLC_ONLY_TAG, HeroPalette.SourceBlue)
                }
            }
            Text(deltaLine(level, delta, names), style = MaterialTheme.typography.bodySmall.tabular())
            if (floorAlt.isNotEmpty()) {
                Text(
                    HeroStatsCopy.floorAlt(HeroStatsCopy.deltaSummary(floorAlt, names)),
                    style = MaterialTheme.typography.labelSmall,
                    color = NightColors.TextMuted,
                )
            }
            RelicItemsLine(statModifier.relicItems)
        }
    }
}

/** 「15 级增减：生命力 -5、集中力 +10」：文字与 Windows 逐字一致，数字按涨跌上色。 */
private fun deltaLine(level: Int, delta: Map<String, Int>, names: HeroStatNames): AnnotatedString = buildAnnotatedString {
    withStyle(SpanStyle(color = NightColors.TextMuted)) { append("$level 级增减：") }
    val keys = names.attributeKeys.filter { (delta[it] ?: 0) != 0 }
    if (keys.isEmpty()) {
        withStyle(SpanStyle(color = NightColors.TextMuted)) { append(HeroStatsCopy.NO_DELTA_AT_LEVEL) }
        return@buildAnnotatedString
    }
    keys.forEachIndexed { position, key ->
        val value = delta.getValue(key)
        if (position > 0) withStyle(SpanStyle(color = NightColors.TextMuted)) { append("、") }
        withStyle(SpanStyle(color = NightColors.TextSecondary)) { append(names.attributeTitle(key) + " ") }
        withStyle(SpanStyle(color = HeroPalette.tone(HeroDeltaTone.of(value)), fontWeight = FontWeight.Bold)) {
            append(HeroStatsText.signed(value))
        }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun RelicItemsLine(items: List<HeroRelicItem>) {
    FlowRow(
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalArrangement = Arrangement.spacedBy(3.dp),
        itemVerticalAlignment = Alignment.CenterVertically,
    ) {
        Text("遗物：", style = MaterialTheme.typography.labelSmall, color = NightColors.TextMuted)
        if (items.isEmpty()) {
            Text(HeroStatsCopy.EMPTY_DATA, style = MaterialTheme.typography.labelSmall, color = NightColors.TextMuted)
        }
        items.forEach { item ->
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                Box(Modifier.size(7.dp).background(HeroPalette.relic(item.color), CircleShape))
                Text(item.display, style = MaterialTheme.typography.labelSmall, color = NightColors.TextSecondary)
                Text(item.colorText, style = MaterialTheme.typography.labelSmall, color = HeroPalette.relic(item.color))
            }
        }
    }
}

@Composable
private fun CheckGlyph(checked: Boolean, modifier: Modifier = Modifier) {
    val shape = RoundedCornerShape(6.dp)
    Box(
        modifier = modifier
            .size(20.dp)
            .clip(shape)
            .background(if (checked) NightColors.Purple else NightColors.FieldSoft)
            .border(1.dp, if (checked) NightColors.PurpleSoft else NightColors.BorderStrong, shape),
        contentAlignment = Alignment.Center,
    ) {
        if (checked) Text("✓", style = MaterialTheme.typography.labelMedium, color = NightColors.TextPrimary)
    }
}

@Composable
internal fun SourcePill(tag: HeroModifierSourceTag) {
    NightPill(tag.source.glyph + " " + tag.label, HeroPalette.source(tag.source))
}

// ---------------------------------------------------------------- 利普拉的交易

@Composable
internal fun LibraSection(
    libra: HeroLibraRespec?,
    libraRule: String,
    canClear: Boolean,
    onOpen: () -> Unit,
    onClear: () -> Unit,
) {
    Column(modifier = SectionPadding, verticalArrangement = Arrangement.spacedBy(8.dp)) {
        SectionLabel("利普拉的交易", if (libra == null) "未选" else HeroStatsCopy.LIBRA_SWAP_TAG)
        val shape = RoundedCornerShape(13.dp)
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .heightIn(min = 56.dp)
                .clip(shape)
                .background(NightColors.Card)
                .border(1.dp, if (libra == null) NightColors.Border else NightColors.Amber.copy(alpha = .45f), shape)
                .clickable(role = Role.Button, onClickLabel = "选择利普拉的交易", onClick = onOpen)
                .padding(horizontal = 14.dp, vertical = 10.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(
                    libra?.display ?: "无（角色原表）",
                    style = MaterialTheme.typography.bodyMedium,
                    fontWeight = FontWeight.SemiBold,
                    color = NightColors.TextPrimary,
                )
                Text(
                    libra?.nameZh ?: HeroStatsCopy.LIBRA_EMPTY_HINT,
                    style = MaterialTheme.typography.bodySmall,
                    color = NightColors.TextMuted,
                )
            }
            if (libra != null) NightPill(HeroStatsCopy.libraBadge(libra.shortTitle), NightColors.Amber)
            Text("›", style = MaterialTheme.typography.titleLarge, color = NightColors.TextMuted, modifier = Modifier.padding(start = 8.dp))
        }
        if (libra != null) {
            NightPanel(modifier = Modifier.fillMaxWidth(), borderColor = NightColors.Amber.copy(alpha = .3f)) {
                Column(modifier = Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        NightPill(HeroStatsCopy.LIBRA_SWAP_TAG, NightColors.PurpleSoft)
                        NightPill("参数结构推断、未实测", NightColors.Amber)
                    }
                    Text(
                        "已把基础属性表整套换成「${libra.nameZh}」（${libra.effectNameZh}：${libra.effectInfoZh}）。" +
                            HeroStatsCopy.LIBRA_HINT + "。" + libraRule,
                        style = MaterialTheme.typography.bodySmall,
                        color = NightColors.TextSecondary,
                    )
                }
            }
        }
        if (canClear) {
            Box(
                modifier = Modifier
                    .heightIn(min = 48.dp)
                    .clip(RoundedCornerShape(11.dp))
                    .clickable(role = Role.Button, onClick = onClear)
                    .padding(horizontal = 4.dp),
                contentAlignment = Alignment.CenterStart,
            ) {
                Text("清空选择", style = MaterialTheme.typography.labelLarge, color = NightColors.PurpleSoft)
            }
        }
    }
}

@Composable
internal fun LibraPickerSheet(
    respecs: List<HeroLibraRespec>,
    selectedKey: String?,
    onSelect: (String?) -> Unit,
    onDismiss: () -> Unit,
) {
    // 「无」占第 0 行，交易从第 1 行起；打开时让已选那一行露在视口里（横屏只放得下两三行）
    val selectedRow = if (selectedKey == null) 0 else respecs.indexOfFirst { it.key == selectedKey } + 1
    val listState = rememberLazyListState(initialFirstVisibleItemIndex = (selectedRow - 1).coerceAtLeast(0))
    NightBottomSheet(onDismissRequest = onDismiss) {
        Column(
            modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Text("利普拉的交易", style = MaterialTheme.typography.titleLarge)
            Text("扭曲的重生：整套属性表替换为对应的交易版本", style = MaterialTheme.typography.bodySmall, color = NightColors.TextMuted)
            Spacer(Modifier.height(4.dp))
            // 抽屉高度以窗口为上限且自身不滚动：选项放进 LazyColumn，weight(fill = false) 让它只占标题与脚注之外
            // 剩下的高度（再以 590dp 封顶）。横屏 / 大字号下选项在列表里滚动，脚注仍然可见。
            LazyColumn(
                state = listState,
                modifier = Modifier.weight(1f, fill = false).heightIn(max = 590.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                item(key = "libra-none", contentType = "libra-option") {
                    LibraOption(
                        title = "无（角色原表）",
                        subtitle = HeroStatsCopy.LIBRA_EMPTY_HINT,
                        badge = null,
                        selected = selectedKey == null,
                    ) { onSelect(null) }
                }
                items(respecs, key = { "libra-${it.key}" }, contentType = { "libra-option" }) { respec ->
                    LibraOption(
                        title = respec.display,
                        subtitle = respec.nameZh,
                        badge = respec.shortTitle,
                        selected = respec.key == selectedKey,
                    ) { onSelect(respec.key) }
                }
            }
            Text(HeroStatsCopy.LIBRA_HINT + "。", style = MaterialTheme.typography.labelSmall, color = NightColors.TextMuted)
            Spacer(Modifier.height(18.dp))
        }
    }
}

@Composable
private fun LibraOption(title: String, subtitle: String, badge: String?, selected: Boolean, onClick: () -> Unit) {
    val shape = RoundedCornerShape(12.dp)
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .heightIn(min = 56.dp)
            .clip(shape)
            .background(if (selected) NightColors.Purple.copy(alpha = .14f) else NightColors.Field)
            .border(1.dp, if (selected) NightColors.PurpleSoft.copy(alpha = .5f) else NightColors.Border, shape)
            .clickable(role = Role.RadioButton, onClick = onClick)
            .semantics { this.selected = selected }
            .padding(horizontal = 14.dp, vertical = 9.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(title, style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.SemiBold, color = NightColors.TextPrimary)
            Text(subtitle, style = MaterialTheme.typography.labelSmall, color = NightColors.TextMuted)
        }
        badge?.let { NightPill(it, NightColors.Amber) }
        if (selected) Text("✓", style = MaterialTheme.typography.titleMedium, color = NightColors.PurpleSoft)
    }
}

// ---------------------------------------------------------------- 属性区

@OptIn(ExperimentalLayoutApi::class)
@Composable
internal fun StatsHeader(
    snapshot: HeroStatsSnapshot,
    level: Int,
    maxLevel: Int,
    allLevels: Boolean,
    onAllLevels: (Boolean) -> Unit,
    libra: HeroLibraRespec?,
    crossCheckNote: String?,
) {
    Column(modifier = Modifier.padding(top = 6.dp, bottom = 8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(
            "${snapshot.heroNameZh}　" + if (allLevels) "全部等级（1–$maxLevel 级）" else "$level 级属性",
            style = MaterialTheme.typography.titleMedium,
            color = NightColors.TextPrimary,
        )
        Text(
            if (allLevels) {
                "锚点行高亮；勾选转职遗物后，变动的格子按增减标绿 / 标红；点一行切到该等级"
            } else {
                "8 项属性 + 血量 / 专注值 / 精力 / 负重上限；勾选转职遗物后显示「基础 → 修改后」"
            },
            style = MaterialTheme.typography.bodySmall,
            color = NightColors.TextMuted,
        )
        NightSegmentedControl(
            items = listOf("本级卡片", "全部等级"),
            selectedIndex = if (allLevels) 1 else 0,
            onSelect = { onAllLevels(it == 1) },
            height = 36.dp,
        )
        FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            NightPill(
                HeroStatsCopy.baseLevelBadge(level, snapshot.isAnchorLevel),
                if (snapshot.isAnchorLevel) NightColors.Green else NightColors.PurpleSoft,
            )
            if (snapshot.hasModifier) {
                NightPill(HeroStatsCopy.modifierCountBadge(snapshot.activeModifiers.size), NightColors.PurpleSoft)
            }
            snapshot.modifierSource?.let { SourcePill(it) }
            libra?.let { NightPill(HeroStatsCopy.libraBadge(it.shortTitle), NightColors.Amber) }
        }
        crossCheckNote?.let {
            Text(it, style = MaterialTheme.typography.labelSmall, color = NightColors.TextMuted)
        }
    }
}

/** 单等级视图：8 项属性 + 4 项派生值的两列卡片，钳位汇总与遗留列脚注。 */
@Composable
internal fun StatTiles(snapshot: HeroStatsSnapshot, names: HeroStatNames) {
    Column(modifier = Modifier.padding(bottom = 6.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        val attributeTiles = names.orderedAttributes.map { attribute ->
            val key = attribute.key
            val delta = snapshot.effectiveDelta(key)
            val clampedFrom = snapshot.clampedFrom[key]
            TileModel(
                title = attribute.display,
                base = HeroStatsText.statText(snapshot.baseStats[key]),
                final = HeroStatsText.statText(snapshot.finalStats[key]),
                changed = delta != null && delta != 0,
                deltaText = delta?.let { HeroStatsText.signed(it) },
                tone = HeroDeltaTone.of(delta ?: 0),
                // 被钳位的那一项：大数字旁写生效值（-8），小字写词条请求的 -9
                note = if (clampedFrom != null) HeroStatsCopy.clampRequestedNote(snapshot.requestedDelta[key] ?: 0) else null,
                noteColor = NightColors.Amber,
            )
        }
        TileGrid(attributeTiles)
        Text("派生值（按 CalcCorrectGraph 重算）", style = MaterialTheme.typography.labelLarge, color = NightColors.TextSecondary)
        val derivedTiles = names.orderedDerived.map { entry ->
            val delta = snapshot.derivedDelta(entry.key)
            val tone = HeroDeltaTone.of(delta ?: 0.0)
            TileModel(
                title = names.derivedHeader(entry.key),
                base = HeroStatsText.derivedText(snapshot.baseDerived[entry.key], entry.integer),
                final = HeroStatsText.derivedText(snapshot.finalDerived[entry.key], entry.integer),
                changed = tone != HeroDeltaTone.FLAT,
                deltaText = delta?.let { HeroStatsText.signed(it, if (entry.integer) 0 else 1) },
                tone = tone,
                note = if (entry.inGameLabel) "来自" + names.attributeTitle(entry.fromStat) else HeroStatsCopy.EQUIP_LOAD_HINT,
                noteColor = NightColors.TextMuted,
            )
        }
        TileGrid(derivedTiles)
        if (snapshot.clampedStats.isNotEmpty()) {
            ClampNote(HeroStatsCopy.clampSummary(snapshot.clampedStats.map(names::attributeTitle)))
        }
        if (names.hasLegacyDerived) {
            Text(HeroStatsCopy.EQUIP_LOAD_FOOTNOTE, style = MaterialTheme.typography.labelSmall, color = NightColors.TextMuted)
        }
    }
}

private data class TileModel(
    val title: String,
    val base: String,
    val final: String,
    val changed: Boolean,
    val deltaText: String?,
    val tone: HeroDeltaTone,
    val note: String?,
    val noteColor: Color,
)

@Composable
private fun TileGrid(tiles: List<TileModel>) {
    tiles.chunked(2).forEach { pair ->
        Row(
            modifier = Modifier.fillMaxWidth().height(IntrinsicSize.Min),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            pair.forEach { StatTile(it, Modifier.weight(1f).fillMaxHeight()) }
            if (pair.size == 1) Spacer(Modifier.weight(1f))
        }
    }
}

/** 一项属性 / 派生值卡片：未修改时只显示一个数字，修改后显示「基础 → 修改后」并标出生效增减量。 */
@Composable
private fun StatTile(tile: TileModel, modifier: Modifier = Modifier) {
    val shape = RoundedCornerShape(12.dp)
    val accent = HeroPalette.tone(tile.tone)
    Column(
        modifier = modifier
            .clip(shape)
            .background(NightColors.Field)
            .border(1.dp, if (tile.changed) accent.copy(alpha = .35f) else NightColors.Border, shape)
            .padding(horizontal = 11.dp, vertical = 9.dp),
        verticalArrangement = Arrangement.spacedBy(3.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(
                tile.title,
                style = MaterialTheme.typography.labelMedium,
                color = NightColors.TextMuted,
                modifier = Modifier.weight(1f),
            )
            if (tile.changed && tile.deltaText != null) {
                Text(tile.deltaText, style = MaterialTheme.typography.labelMedium.tabular(), fontWeight = FontWeight.Bold, color = accent)
            }
        }
        Row(verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            if (tile.changed) {
                Text(
                    tile.base,
                    style = MaterialTheme.typography.bodyMedium.tabular(),
                    color = NightColors.TextMuted,
                    textDecoration = TextDecoration.LineThrough,
                    modifier = Modifier.padding(bottom = 2.dp),
                )
                Text("→", style = MaterialTheme.typography.labelSmall, color = NightColors.TextMuted, modifier = Modifier.padding(bottom = 3.dp))
            }
            Text(
                tile.final,
                style = MaterialTheme.typography.headlineSmall.tabular(),
                fontWeight = FontWeight.Bold,
                color = if (tile.changed) accent else NightColors.TextPrimary,
            )
        }
        tile.note?.let {
            Text(it, style = MaterialTheme.typography.labelSmall, color = tile.noteColor)
        }
    }
}

@Composable
internal fun ClampNote(text: String) {
    Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.Top) {
        NightPill(HeroStatsCopy.CLAMP_ROW_TAG, NightColors.Red)
        Text(text, style = MaterialTheme.typography.bodySmall, color = NightColors.Amber, modifier = Modifier.weight(1f))
    }
}

@Composable
internal fun LevelTableNotes(clampSummary: String, baseAnchorLevels: List<Int>, hasLegacy: Boolean) {
    Column(modifier = Modifier.padding(top = 10.dp, bottom = 6.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        if (clampSummary.isNotEmpty()) ClampNote(clampSummary)
        Text(HeroStatsCopy.allLevelsCaption(baseAnchorLevels), style = MaterialTheme.typography.labelSmall, color = NightColors.TextMuted)
        Text("表格可左右滑动；「${HeroStatsCopy.CLAMP_CELL_TAG}」标出被钳到最低 1 的格子。", style = MaterialTheme.typography.labelSmall, color = NightColors.TextMuted)
        if (hasLegacy) {
            Text(HeroStatsCopy.EQUIP_LOAD_FOOTNOTE, style = MaterialTheme.typography.labelSmall, color = NightColors.TextMuted)
        }
    }
}

// ---------------------------------------------------------------- 同级对比

@Composable
internal fun CompareHeader(level: Int, count: Int) {
    Column(modifier = Modifier.padding(top = 4.dp, bottom = 8.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Text("同级对比（$level 级）", style = MaterialTheme.typography.titleMedium, color = NightColors.TextPrimary)
        Text(
            "$count 位夜行者的 8 项属性与派生值；点列头排序，每列最高值标绿；点一行查看该角色",
            style = MaterialTheme.typography.bodySmall,
            color = NightColors.TextMuted,
        )
    }
}

@Composable
internal fun CompareNotes(hasLegacy: Boolean) {
    Column(modifier = Modifier.padding(top = 10.dp, bottom = 6.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(HeroStatsCopy.COMPARE_CAPTION, style = MaterialTheme.typography.labelSmall, color = NightColors.TextMuted)
        if (hasLegacy) {
            Text(HeroStatsCopy.EQUIP_LOAD_FOOTNOTE, style = MaterialTheme.typography.labelSmall, color = NightColors.TextMuted)
        }
    }
}

// ---------------------------------------------------------------- 底部说明

@Composable
internal fun NotesHeader() {
    Column(modifier = Modifier.padding(top = 18.dp, bottom = 8.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
        SectionLabel("数据说明", "取自游戏参数表")
        Text(
            "数值直接取自游戏参数表，不是官方公布，也不是实测结论",
            style = MaterialTheme.typography.bodySmall,
            color = NightColors.TextMuted,
        )
    }
}

@Composable
internal fun HeroDisclosure(
    title: String,
    count: Int,
    color: Color,
    expanded: Boolean,
    onToggle: () -> Unit,
    content: @Composable ColumnScope.() -> Unit,
) {
    NightPanel(modifier = Modifier.fillMaxWidth().padding(bottom = 8.dp)) {
        Column {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .heightIn(min = 52.dp)
                    .clickable(role = Role.Button, onClickLabel = if (expanded) "收起" else "展开", onClick = onToggle)
                    .padding(horizontal = 14.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                Text(if (expanded) "▾" else "▸", style = MaterialTheme.typography.bodyMedium, color = NightColors.TextMuted)
                Text(
                    title,
                    style = MaterialTheme.typography.bodyMedium,
                    fontWeight = FontWeight.SemiBold,
                    color = NightColors.TextPrimary,
                    modifier = Modifier.weight(1f),
                )
                NightPill("$count 条", color)
            }
            if (expanded) {
                Column(
                    modifier = Modifier.fillMaxWidth().padding(start = 14.dp, end = 14.dp, bottom = 14.dp),
                    verticalArrangement = Arrangement.spacedBy(10.dp),
                    content = content,
                )
            }
        }
    }
}

@Composable
internal fun InterpolationNotes(notes: List<HeroNote>) {
    notes.forEach { note ->
        Column(verticalArrangement = Arrangement.spacedBy(3.dp)) {
            Text(note.title, style = MaterialTheme.typography.labelMedium, fontWeight = FontWeight.SemiBold, color = NightColors.PurpleSoft)
            Text(rememberBoldText(note.text), style = MaterialTheme.typography.bodySmall, color = NightColors.TextSecondary)
        }
    }
}

@Composable
internal fun CaveatList(caveats: List<String>) {
    caveats.forEach { caveat ->
        Row(horizontalArrangement = Arrangement.spacedBy(7.dp)) {
            Text("·", style = MaterialTheme.typography.bodySmall, color = NightColors.TextMuted)
            Text(
                rememberBoldText(caveat),
                style = MaterialTheme.typography.bodySmall,
                color = NightColors.TextSecondary,
                modifier = Modifier.weight(1f),
            )
        }
    }
}

@Composable
internal fun SourceList(sources: List<HeroSource>, crossChecks: List<HeroCrossCheck>) {
    sources.forEach { source ->
        DetailRow(source.name, source.revision.ifEmpty { source.license })
    }
    if (crossChecks.isNotEmpty()) {
        Spacer(Modifier.height(2.dp))
        crossChecks.forEach { check ->
            DetailRow(
                label = check.heroNameZh.ifEmpty { check.heroKey } + " 逐格对照",
                value = "${check.cellsCompared} 格，差异 ${check.mismatchCount} 处" + (if (check.note.isEmpty()) "" else "；" + check.note),
                tint = if (check.mismatchCount == 0) NightColors.TextSecondary else NightColors.Amber,
            )
        }
    }
}

@Composable
private fun DetailRow(label: String, value: String, tint: Color = NightColors.TextSecondary) {
    Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
        Text(label, style = MaterialTheme.typography.labelMedium, fontWeight = FontWeight.SemiBold, color = NightColors.TextPrimary)
        Text(value, style = MaterialTheme.typography.bodySmall, color = tint)
    }
}

/** 数据版本块：5 行标签与取值口径三端逐字一致。 */
@Composable
internal fun VersionBlock(rows: List<Pair<String, String>>) {
    NightPanel(modifier = Modifier.fillMaxWidth().padding(top = 2.dp)) {
        Column(modifier = Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(7.dp)) {
            rows.forEach { (label, value) ->
                Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    Text(label, style = MaterialTheme.typography.labelMedium, color = NightColors.TextMuted, modifier = Modifier.width(92.dp))
                    Text(value, style = MaterialTheme.typography.bodySmall, color = NightColors.TextPrimary, modifier = Modifier.weight(1f))
                }
            }
        }
    }
}

// ---------------------------------------------------------------- 空态

@Composable
internal fun HeroEmptyNotice(detail: String) {
    NightPanel(modifier = Modifier.fillMaxWidth().padding(vertical = 6.dp)) {
        Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            NightPill(HeroStatsCopy.EMPTY_DATA, NightColors.Amber)
            Text(detail, style = MaterialTheme.typography.bodySmall, color = NightColors.TextSecondary)
        }
    }
}

/** 数据集缺 growthGraphs 等关键块时的降级页（Windows unavailableShell 同一句话）。 */
@Composable
internal fun HeroesUnavailable() {
    Box(
        modifier = Modifier.fillMaxSize().padding(horizontal = GameDataLayout.Gutter, vertical = 24.dp),
        contentAlignment = Alignment.TopCenter,
    ) {
        NightPanel(modifier = Modifier.fillMaxWidth(), borderColor = NightColors.Amber.copy(alpha = .35f)) {
            Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                NightPill(HeroStatsCopy.EMPTY_DATA, NightColors.Amber, dot = true)
                Text(HeroStatsCopy.EMPTY_DATA, style = MaterialTheme.typography.titleMedium)
                Text(
                    "尚未提供角色属性数据文件，页面无法显示数值。",
                    style = MaterialTheme.typography.bodySmall,
                    color = NightColors.TextSecondary,
                )
            }
        }
    }
}
