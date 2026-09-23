package com.nightreign.relicchecker.ui.lookup

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.FlowRowScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.selection.toggleable
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.minimumInteractiveComponentSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.nightreign.relicchecker.catalog.CatalogSource
import com.nightreign.relicchecker.gamedata.lookup.LookupCopy
import com.nightreign.relicchecker.ui.NightPanel
import com.nightreign.relicchecker.ui.NightPill
import com.nightreign.relicchecker.ui.theme.NightColors

// 词条反查页私有的小组件。Components.kt 是骨架文件，不改；这里的版本只给本页用。

/** 等宽数字（计数、id 对齐用）。 */
internal fun TextStyle.lookupTabular(): TextStyle = copy(fontFeatureSettings = "tnum")

/** 卡片：NightPanel + 统一内边距与行距。 */
@Composable
internal fun LookupCard(
    modifier: Modifier = Modifier,
    borderColor: Color = NightColors.Border,
    content: @Composable ColumnScope.() -> Unit,
) {
    NightPanel(modifier = modifier.fillMaxWidth(), borderColor = borderColor) {
        Column(
            modifier = Modifier.fillMaxWidth().padding(14.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp),
            content = content,
        )
    }
}

/** 卡片标题 + 副标题（macOS SectionHeading）。 */
@Composable
internal fun LookupHeading(title: String, subtitle: String?, tint: Color = NightColors.TextPrimary) {
    Column(verticalArrangement = Arrangement.spacedBy(3.dp)) {
        Text(title, style = MaterialTheme.typography.titleMedium, color = tint)
        if (!subtitle.isNullOrEmpty()) {
            Text(subtitle, style = MaterialTheme.typography.bodySmall, color = NightColors.TextSecondary)
        }
    }
}

/** 只有一句说明的卡片（macOS LookupNoticeCard）：琥珀色描边。 */
@Composable
internal fun LookupNoticeCard(title: String, detail: String, modifier: Modifier = Modifier) {
    LookupCard(modifier = modifier, borderColor = NightColors.Amber.copy(alpha = .35f)) {
        LookupHeading(title = title, subtitle = detail, tint = NightColors.Amber)
    }
}

/** 带色条的说明块（macOS LookupInlineNote）。 */
@Composable
internal fun LookupInlineNote(text: String, tint: Color, modifier: Modifier = Modifier) {
    val shape = RoundedCornerShape(10.dp)
    Row(
        modifier = modifier
            .fillMaxWidth()
            .clip(shape)
            .background(tint.copy(alpha = .07f))
            .border(1.dp, tint.copy(alpha = .24f), shape)
            .padding(10.dp),
        horizontalArrangement = Arrangement.spacedBy(9.dp),
    ) {
        Box(Modifier.padding(top = 5.dp).size(6.dp).background(tint, CircleShape))
        Text(text, style = MaterialTheme.typography.bodySmall, color = NightColors.TextSecondary, modifier = Modifier.weight(1f))
    }
}

/** 小字说明（注脚）。 */
@Composable
internal fun LookupFootnote(text: String, modifier: Modifier = Modifier) {
    Text(text, modifier = modifier, style = MaterialTheme.typography.bodySmall, color = NightColors.TextMuted)
}

/** 状态圆点：命中为实心绿点，未命中为空心灰圈（代替 ✓ / ○ 字形，避免字体缺字）。 */
@Composable
internal fun LookupHitDot(on: Boolean, modifier: Modifier = Modifier) {
    val base = modifier.size(10.dp).clip(CircleShape)
    Box(
        if (on) base.background(NightColors.Green) else base.border(1.5.dp, NightColors.TextMuted, CircleShape),
    )
}

/**
 * 并排的几组键值（macOS LookupKeyValue × N）。
 *
 * 键一行、值一行，两行用相同的等分权重与间距，所以各列天然对齐：某个键在窄屏或大字号下折成三行，
 * 只是整行键变高，所有值仍从同一条线开始，键也不会被截断。读屏时按「键：值」逐组朗读。
 */
@Composable
internal fun LookupKeyValues(pairs: List<Pair<String, String>>, modifier: Modifier = Modifier, spacing: Dp = 12.dp) {
    Column(
        modifier = modifier
            .fillMaxWidth()
            .clearAndSetSemantics { contentDescription = pairs.joinToString("，") { (key, value) -> "$key：$value" } },
        verticalArrangement = Arrangement.spacedBy(2.dp),
    ) {
        Row(horizontalArrangement = Arrangement.spacedBy(spacing)) {
            pairs.forEach { (key, _) ->
                Text(
                    key,
                    style = MaterialTheme.typography.labelSmall,
                    color = NightColors.TextMuted,
                    modifier = Modifier.weight(1f).alignByBaseline(),
                )
            }
        }
        Row(horizontalArrangement = Arrangement.spacedBy(spacing)) {
            pairs.forEach { (_, value) ->
                Text(
                    value,
                    style = MaterialTheme.typography.bodyLarge.lookupTabular(),
                    color = NightColors.TextPrimary,
                    fontWeight = FontWeight.Medium,
                    // 按首行基线对齐：「2 个」这类含汉字的值行高更大，顶对齐时会比纯数字低半格
                    modifier = Modifier.weight(1f).alignByBaseline(),
                )
            }
        }
    }
}

/** 自动换行的标签堆。 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
internal fun LookupFlow(
    modifier: Modifier = Modifier,
    spacing: Dp = 6.dp,
    content: @Composable FlowRowScope.() -> Unit,
) {
    FlowRow(
        modifier = modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(spacing),
        verticalArrangement = Arrangement.spacedBy(spacing),
        content = content,
    )
}

/**
 * 可点的词条标签：视觉高度 34dp，触控区至少 48dp（minimumInteractiveComponentSize）。
 * 点了跳到该词条的详情。
 */
@Composable
internal fun LookupAffixChip(
    label: String,
    effectId: Int,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    background: Color = NightColors.Field,
    prefix: String? = null,
) {
    val shape = RoundedCornerShape(9.dp)
    Box(
        modifier = modifier
            .minimumInteractiveComponentSize()
            .clip(shape)
            .clickable(role = Role.Button, onClick = onClick)
            .semantics { contentDescription = "$label（$effectId）" },
        contentAlignment = Alignment.Center,
    ) {
        Row(
            modifier = Modifier
                .clip(shape)
                .background(background)
                .border(1.dp, NightColors.Border, shape)
                .heightIn(min = 34.dp)
                .padding(horizontal = 10.dp, vertical = 6.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            if (prefix != null) {
                Text(prefix, style = MaterialTheme.typography.labelMedium, color = NightColors.PurpleSoft, fontWeight = FontWeight.Bold)
            }
            Text(
                label,
                style = MaterialTheme.typography.bodySmall,
                color = NightColors.TextPrimary,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier.weight(1f, fill = false),
            )
        }
    }
}

/** 次级文字按钮（展开 / 收起）：高 40dp，外加 minimumInteractiveComponentSize 到 48dp。 */
@Composable
internal fun LookupTextButton(label: String, onClick: () -> Unit, modifier: Modifier = Modifier) {
    val shape = RoundedCornerShape(11.dp)
    Box(
        modifier = modifier
            .minimumInteractiveComponentSize()
            .clip(shape)
            .background(NightColors.FieldSoft)
            .border(1.dp, NightColors.Border, shape)
            .clickable(role = Role.Button, onClick = onClick)
            .heightIn(min = 40.dp)
            .padding(horizontal = 14.dp, vertical = 9.dp),
        contentAlignment = Alignment.Center,
    ) {
        Text(label, style = MaterialTheme.typography.labelLarge, color = NightColors.PurpleSoft, maxLines = 1)
    }
}

/** 整行可点的开关（「含负面词条」「只看深夜遗物」）。 */
@Composable
internal fun LookupSwitch(label: String, checked: Boolean, onCheckedChange: (Boolean) -> Unit, modifier: Modifier = Modifier) {
    Row(
        modifier = modifier
            .heightIn(min = 48.dp)
            .clip(RoundedCornerShape(12.dp))
            .toggleable(value = checked, role = Role.Switch, onValueChange = onCheckedChange)
            .padding(start = 8.dp, end = 2.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Text(label, style = MaterialTheme.typography.labelLarge, color = NightColors.TextSecondary, maxLines = 1)
        Switch(
            checked = checked,
            onCheckedChange = null,
            colors = SwitchDefaults.colors(
                checkedThumbColor = NightColors.TextPrimary,
                checkedTrackColor = NightColors.Purple,
                checkedBorderColor = NightColors.Purple,
                uncheckedThumbColor = NightColors.TextMuted,
                uncheckedTrackColor = NightColors.Field,
                uncheckedBorderColor = NightColors.BorderStrong,
            ),
        )
    }
}

/** 列表为空时的占位。 */
@Composable
internal fun LookupEmptyState(title: String, detail: String, modifier: Modifier = Modifier) {
    Column(
        modifier = modifier.fillMaxSize().padding(32.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        NightPill("0", NightColors.TextMuted)
        Spacer(Modifier.size(12.dp))
        Text(title, style = MaterialTheme.typography.titleMedium, color = NightColors.TextPrimary)
        Spacer(Modifier.size(4.dp))
        Text(detail, style = MaterialTheme.typography.bodySmall, color = NightColors.TextMuted, textAlign = TextAlign.Center)
    }
}

/** 遗物颜色的色点（游戏里的遗物颜色，是数据而非主题色）。 */
internal fun lookupRelicHue(color: Int): Color = when (color) {
    0 -> NightColors.Red
    1 -> Color(0xFF7FA7F2)
    2 -> NightColors.Amber
    3 -> NightColors.Green
    4 -> NightColors.TextSecondary
    else -> NightColors.TextMuted
}

@Composable
internal fun LookupRelicDot(color: Int, modifier: Modifier = Modifier) {
    Box(modifier.size(8.dp).background(lookupRelicHue(color), CircleShape))
}

/** 数据来源与口径说明，默认折叠（macOS LookupSourcesCard）。 */
@Composable
internal fun LookupSourcesCard(
    catalogSources: List<CatalogSource>,
    relicSources: List<CatalogSource>,
    modifier: Modifier = Modifier,
) {
    var expanded by rememberSaveable { mutableStateOf(false) }
    LookupCard(modifier = modifier) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .heightIn(min = 44.dp)
                .clip(RoundedCornerShape(10.dp))
                .clickable(role = Role.Button) { expanded = !expanded },
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(
                LookupCopy.SOURCES_TITLE,
                style = MaterialTheme.typography.labelLarge,
                color = NightColors.TextSecondary,
                modifier = Modifier.weight(1f),
            )
            Text(if (expanded) "▴" else "▾", style = MaterialTheme.typography.titleMedium, color = NightColors.TextMuted)
        }
        if (expanded) {
            LookupInlineNote(LookupCopy.SOURCES_CAVEAT, NightColors.Amber)
            if (catalogSources.isNotEmpty()) LookupSourceList(LookupCopy.CATALOG_SOURCES, catalogSources)
            if (relicSources.isNotEmpty()) LookupSourceList(LookupCopy.RELIC_SOURCES, relicSources)
        }
    }
}

@Composable
private fun LookupSourceList(title: String, sources: List<CatalogSource>) {
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Text(title, style = MaterialTheme.typography.labelMedium, color = NightColors.TextSecondary, fontWeight = FontWeight.SemiBold)
        sources.forEach { source ->
            Column(verticalArrangement = Arrangement.spacedBy(1.dp)) {
                Text(source.name, style = MaterialTheme.typography.bodySmall, color = NightColors.TextPrimary)
                Text(
                    source.url + if (source.license.isEmpty()) "" else " · ${source.license}",
                    style = MaterialTheme.typography.labelSmall,
                    color = NightColors.TextMuted,
                )
            }
        }
    }
}

@Composable
internal fun LookupDivider(modifier: Modifier = Modifier) {
    HorizontalDivider(modifier = modifier, color = NightColors.Border)
}
