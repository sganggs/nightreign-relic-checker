@file:OptIn(ExperimentalLayoutApi::class)

package com.nightreign.relicchecker.ui.ranker

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.nightreign.relicchecker.gamedata.ranker.BuffFormat
import com.nightreign.relicchecker.gamedata.ranker.DamageType
import com.nightreign.relicchecker.gamedata.ranker.EntryState
import com.nightreign.relicchecker.gamedata.ranker.RankerText
import com.nightreign.relicchecker.gamedata.ranker.SummaryColumn
import com.nightreign.relicchecker.ui.NightPanel
import com.nightreign.relicchecker.ui.NightPill
import com.nightreign.relicchecker.ui.theme.NightColors

// 「增伤排名」页的私有组件与配色（骨架的 Components.kt 不改，页面要用的共用小件都在这里）。
// 配色取自 macOS 端 BuffRankerComponents.swift 的 RankerPalette 与 BuffRankerLoadoutSection.swift 的 LoadoutPalette。

internal object RankerPalette {
    val Blue = Color(0xFF8CC7FC)
    val DeepBlue = Color(0xFF8C99FC)

    /** 伤害类型：物理五类用不同深浅的灰白，属性用各自的颜色。 */
    fun type(type: DamageType): Color = when (type) {
        DamageType.SLASH -> Color(0xFFE0E0E0)
        DamageType.BLOW -> Color(0xFFB8B8B8)
        DamageType.THRUST -> Color(0xFF8F8F8F)
        DamageType.NEUTRAL -> Color(0xFF6B6B6B)
        DamageType.PHYS_NONE -> Color(0xFF4D4D4D)
        DamageType.MAGIC -> Color(0xFF7099FC)
        DamageType.FIRE -> Color(0xFFF57338)
        DamageType.LIGHTNING -> Color(0xFFF2CC40)
        DamageType.HOLY -> Color(0xFFFCEDC7)
    }

    fun column(column: SummaryColumn): Color = when (column) {
        SummaryColumn.WEAPON_AFFIX -> Color(0xFF6BB8F2)
        SummaryColumn.RELIC -> NightColors.PurpleSoft
        SummaryColumn.ACCESSORY -> Color(0xFFF29ED9)
        SummaryColumn.OTHER -> NightColors.Green
    }

    /** 其它增益各分栏。 */
    fun slot(slot: String): Color = when (slot) {
        "consumable" -> NightColors.Green
        "spellBuff" -> Blue
        "weaponSkill" -> Color(0xFFFCC773)
        "weaponInnate" -> Color(0xFF9EDBCC)
        "character" -> NightColors.Amber
        "permanent" -> Color(0xFFBFD98C)
        "runStack" -> Color(0xFFE68C66)
        else -> NightColors.TextSecondary
    }

    fun state(state: EntryState): Color = when (state) {
        EntryState.COUNTED -> NightColors.Green
        EntryState.PENDING, EntryState.CONTEXT, EntryState.ZERO_STACKS, EntryState.TIER_OFF -> NightColors.Amber
        EntryState.RELIC_INVALID -> NightColors.Red
        else -> NightColors.TextMuted
    }

    fun badge(text: String): Color = when (text) {
        RankerText.t("badges.deepOnly"), RankerText.t("runMode.deep") -> DeepBlue
        RankerText.t("badges.curse"), RankerText.t("badges.requiresCurse") -> NightColors.Red
        RankerText.t("badges.blessing") -> Color(0xFFFCD973)
        RankerText.t("badges.autoInnate"), RankerText.t("badges.currentSkill") -> NightColors.Green
        RankerText.t("badges.conditional"), RankerText.t("badges.activated"), RankerText.t("badges.ladder"),
        RankerText.t("badges.copies"), RankerText.t("badges.accLadder"), RankerText.t("badges.variant"),
        RankerText.t("badges.outsideWeaponType"), RankerText.t("badges.inferredTiers"),
        -> NightColors.Amber
        RankerText.t("badges.ally") -> Blue
        else -> NightColors.TextSecondary
    }
}

/** 数值写法：倍率「×1.25」，没有构成时「—」。 */
internal fun mul(value: Double?): String = BuffFormat.multiplier(value)

/**
 * 可折叠的分区卡片：标题行整行可点（折叠 / 展开），折叠时在标题下写一句摘要，展开后显示 [content]。
 */
@Composable
internal fun RankerSectionCard(
    title: String,
    expanded: Boolean,
    onToggle: () -> Unit,
    modifier: Modifier = Modifier,
    subtitle: String? = null,
    summary: String? = null,
    accent: Color = NightColors.PurpleSoft,
    trailing: (@Composable RowScope.() -> Unit)? = null,
    content: @Composable ColumnScope.() -> Unit = {},
) {
    NightPanel(modifier = modifier.fillMaxWidth()) {
        Column(Modifier.fillMaxWidth()) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .heightIn(min = 52.dp)
                    .clickable(role = Role.Button, onClickLabel = if (expanded) "折叠" else "展开", onClick = onToggle)
                    .padding(start = 14.dp, end = 8.dp, top = 10.dp, bottom = 10.dp)
                    .semantics { stateDescription = if (expanded) "已展开" else "已折叠" },
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Box(Modifier.size(width = 4.dp, height = 20.dp).background(accent, RoundedCornerShape(2.dp)))
                Spacer(Modifier.width(10.dp))
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    Text(title, style = MaterialTheme.typography.titleMedium, color = NightColors.TextPrimary)
                    val line = if (expanded) subtitle else summary ?: subtitle
                    if (!line.isNullOrEmpty()) {
                        Text(
                            line,
                            style = MaterialTheme.typography.bodySmall,
                            color = NightColors.TextMuted,
                            maxLines = if (expanded) 4 else 2,
                            overflow = TextOverflow.Ellipsis,
                        )
                    }
                }
                trailing?.let {
                    Spacer(Modifier.width(6.dp))
                    it()
                }
                Chevron(expanded, Modifier.padding(start = 4.dp))
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

/** 折叠箭头（向右＝折叠，向下＝展开）。 */
@Composable
internal fun Chevron(expanded: Boolean, modifier: Modifier = Modifier, color: Color = NightColors.TextMuted) {
    val angle by animateFloatAsState(if (expanded) 90f else 0f, label = "chevron")
    Canvas(modifier.size(14.dp).rotate(angle)) {
        val width = 1.8.dp.toPx()
        val tip = Offset(size.width * .72f, size.height * .5f)
        drawLine(color, Offset(size.width * .34f, size.height * .14f), tip, width, StrokeCap.Round)
        drawLine(color, tip, Offset(size.width * .34f, size.height * .86f), width, StrokeCap.Round)
    }
}

/** 列表里的一行卡片（选中时紫色描边、不生效时整行虚化）。 */
@Composable
internal fun RankerRowPanel(
    modifier: Modifier = Modifier,
    selected: Boolean = false,
    dimmed: Boolean = false,
    borderColor: Color? = null,
    content: @Composable ColumnScope.() -> Unit,
) {
    val shape = RoundedCornerShape(12.dp)
    Column(
        modifier = modifier
            .fillMaxWidth()
            .clip(shape)
            .background(if (selected) NightColors.Purple.copy(alpha = .10f) else NightColors.Card)
            .border(1.dp, borderColor ?: if (selected) NightColors.Purple.copy(alpha = .38f) else NightColors.Border, shape)
            .alpha(if (dimmed) .6f else 1f)
            .padding(horizontal = 12.dp, vertical = 10.dp),
        verticalArrangement = Arrangement.spacedBy(6.dp),
        content = content,
    )
}

/** 可点的小标签（筛选、攻击情境、分段勾选）。 */
@Composable
internal fun RankerChip(
    text: String,
    selected: Boolean,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    color: Color = NightColors.PurpleSoft,
    enabled: Boolean = true,
    trailing: String? = null,
) {
    val shape = RoundedCornerShape(999.dp)
    Row(
        modifier = modifier
            .heightIn(min = 36.dp)
            .clip(shape)
            .background(if (selected) color.copy(alpha = .16f) else NightColors.FieldSoft)
            .border(1.dp, if (selected) color.copy(alpha = .5f) else NightColors.Border, shape)
            .clickable(enabled = enabled, role = Role.Checkbox, onClick = onClick)
            .alpha(if (enabled) 1f else .45f)
            .padding(horizontal = 12.dp, vertical = 6.dp)
            .semantics { stateDescription = if (selected) "已选" else "未选" },
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(5.dp),
    ) {
        Text(
            text,
            style = MaterialTheme.typography.labelMedium,
            color = if (selected) color else NightColors.TextSecondary,
            maxLines = 2,
            overflow = TextOverflow.Ellipsis,
        )
        trailing?.let { Text(it, style = MaterialTheme.typography.labelSmall, color = NightColors.TextMuted) }
    }
}

/** 次级 / 主按钮（高 44dp）。 */
@Composable
internal fun RankerButton(
    text: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    primary: Boolean = false,
    enabled: Boolean = true,
    height: Dp = 44.dp,
) {
    val shape = RoundedCornerShape(11.dp)
    Box(
        modifier = modifier
            .heightIn(min = height)
            .clip(shape)
            .background(
                when {
                    !enabled -> NightColors.Field
                    primary -> NightColors.Purple
                    else -> NightColors.FieldSoft
                },
            )
            .border(1.dp, if (primary && enabled) NightColors.Purple else NightColors.Border, shape)
            .clickable(enabled = enabled, role = Role.Button, onClick = onClick)
            .padding(horizontal = 14.dp, vertical = 8.dp),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            text,
            style = MaterialTheme.typography.labelLarge,
            fontWeight = if (primary) FontWeight.SemiBold else FontWeight.Medium,
            color = when {
                !enabled -> NightColors.TextMuted
                primary -> NightColors.TextPrimary
                else -> NightColors.TextSecondary
            },
            textAlign = TextAlign.Center,
            maxLines = 2,
        )
    }
}

/** 复选框（22dp 的圆角方块），整行可点时只做展示。 */
@Composable
internal fun RankerCheckMark(checked: Boolean, modifier: Modifier = Modifier, color: Color = NightColors.PurpleSoft) {
    val shape = RoundedCornerShape(6.dp)
    Box(
        modifier = modifier
            .size(22.dp)
            .clip(shape)
            .background(if (checked) color.copy(alpha = .22f) else NightColors.Field)
            .border(1.5.dp, if (checked) color else NightColors.BorderStrong, shape),
        contentAlignment = Alignment.Center,
    ) {
        if (checked) {
            Canvas(Modifier.size(12.dp)) {
                val width = 2.dp.toPx()
                drawLine(color, Offset(size.width * .08f, size.height * .55f), Offset(size.width * .4f, size.height * .86f), width, StrokeCap.Round)
                drawLine(color, Offset(size.width * .4f, size.height * .86f), Offset(size.width * .94f, size.height * .14f), width, StrokeCap.Round)
            }
        }
    }
}

/** 整行可点的勾选项：复选框 + 文字（+ 下方的小字说明）。 */
@Composable
internal fun RankerCheckRow(
    text: String,
    checked: Boolean,
    onCheckedChange: (Boolean) -> Unit,
    modifier: Modifier = Modifier,
    detail: String? = null,
    color: Color = NightColors.PurpleSoft,
) {
    Row(
        modifier = modifier
            .fillMaxWidth()
            .heightIn(min = 44.dp)
            .clip(RoundedCornerShape(10.dp))
            .clickable(role = Role.Checkbox) { onCheckedChange(!checked) }
            .padding(vertical = 4.dp)
            .semantics { stateDescription = if (checked) "已勾选" else "未勾选" },
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        RankerCheckMark(checked, color = color)
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(1.dp)) {
            Text(text, style = MaterialTheme.typography.bodyMedium, color = NightColors.TextPrimary)
            detail?.takeIf { it.isNotEmpty() }?.let {
                Text(it, style = MaterialTheme.typography.bodySmall, color = NightColors.TextMuted, maxLines = 3, overflow = TextOverflow.Ellipsis)
            }
        }
    }
}

/** 开关行（显示不生效项、专注值不足版本）。 */
@Composable
internal fun RankerSwitchRow(
    text: String,
    checked: Boolean,
    onCheckedChange: (Boolean) -> Unit,
    modifier: Modifier = Modifier,
    detail: String? = null,
) {
    Row(
        modifier = modifier
            .fillMaxWidth()
            .heightIn(min = 48.dp)
            .clip(RoundedCornerShape(10.dp))
            .clickable(role = Role.Switch) { onCheckedChange(!checked) },
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(text, style = MaterialTheme.typography.bodyMedium, color = NightColors.TextPrimary)
            detail?.let { Text(it, style = MaterialTheme.typography.bodySmall, color = NightColors.TextMuted) }
        }
        Switch(
            checked = checked,
            onCheckedChange = onCheckedChange,
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

/** 数量步进：− 数字 ＋（48dp 触控区）。 */
@Composable
internal fun RankerStepper(
    value: Int,
    canDown: Boolean,
    canUp: Boolean,
    onDown: () -> Unit,
    onUp: () -> Unit,
    modifier: Modifier = Modifier,
    upLabel: String = RankerText.t("stepUp"),
    valueColor: Color = NightColors.TextPrimary,
) {
    Row(
        modifier = modifier.semantics { contentDescription = RankerText.t("stepperAria") + " " + value },
        verticalAlignment = Alignment.CenterVertically,
    ) {
        StepButton("−", canDown, RankerText.t("stepDown"), onDown)
        Text(
            value.toString(),
            modifier = Modifier.widthIn(min = 26.dp),
            style = MaterialTheme.typography.titleMedium,
            color = if (value > 0) valueColor else NightColors.TextMuted,
            textAlign = TextAlign.Center,
        )
        StepButton("＋", canUp, upLabel, onUp)
    }
}

@Composable
private fun StepButton(symbol: String, enabled: Boolean, label: String, onClick: () -> Unit) {
    Box(
        modifier = Modifier
            .size(44.dp)
            .clip(CircleShape)
            .clickable(enabled = enabled, role = Role.Button, onClickLabel = label, onClick = onClick)
            .semantics { contentDescription = label },
        contentAlignment = Alignment.Center,
    ) {
        Box(
            modifier = Modifier
                .size(32.dp)
                .clip(CircleShape)
                .background(if (enabled) NightColors.Purple.copy(alpha = .18f) else NightColors.Field)
                .border(1.dp, if (enabled) NightColors.PurpleSoft.copy(alpha = .45f) else NightColors.Border, CircleShape),
            contentAlignment = Alignment.Center,
        ) {
            Text(symbol, style = MaterialTheme.typography.titleMedium, color = if (enabled) NightColors.PurpleSoft else NightColors.TextMuted)
        }
    }
}

/**
 * 层数 / 份数：− [输入框] ＋。输入框可手填（赐福王的余威按本局新发现的赐福数填），每次改动立即提交（按 0…[max] 截断）。
 */
@Composable
internal fun RankerNumberStepper(
    value: Int,
    max: Int,
    onValueChange: (Int) -> Unit,
    modifier: Modifier = Modifier,
    warn: Boolean = false,
) {
    var text by remember(value) { mutableStateOf(value.toString()) }
    Row(modifier = modifier, verticalAlignment = Alignment.CenterVertically) {
        StepButton("−", value > 0, RankerText.t("stepDown")) { onValueChange(value - 1) }
        val shape = RoundedCornerShape(9.dp)
        BasicTextField(
            value = text,
            onValueChange = { raw ->
                val digits = raw.filter { it in '0'..'9' }.take(3)
                text = digits
                if (digits.isNotEmpty()) {
                    val parsed = digits.toInt()
                    val clamped = parsed.coerceIn(0, max)
                    // 超过上限按上限计（与 setStacks 同一截断），输入框同步写回截断后的值
                    if (clamped != parsed) text = clamped.toString()
                    onValueChange(clamped)
                }
            },
            modifier = Modifier
                .width(52.dp)
                .heightIn(min = 36.dp)
                .clip(shape)
                .background(NightColors.Field)
                .border(1.dp, if (warn) NightColors.Amber.copy(alpha = .7f) else NightColors.Border, shape)
                .padding(horizontal = 6.dp, vertical = 8.dp),
            textStyle = MaterialTheme.typography.bodyLarge.copy(
                color = if (warn) NightColors.Amber else NightColors.TextPrimary,
                textAlign = TextAlign.Center,
            ),
            singleLine = true,
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
        )
        StepButton("＋", value < max, RankerText.t("stepUp")) { onValueChange(value + 1) }
    }
}

/** 下拉选择（选层、选档）：按钮显示当前项，点开是菜单。 */
@Composable
internal fun <K> RankerDropdown(
    label: String,
    options: List<Pair<K, String>>,
    selected: K,
    onSelect: (K) -> Unit,
    modifier: Modifier = Modifier,
) {
    var open by remember { mutableStateOf(false) }
    val current = options.firstOrNull { it.first == selected }?.second ?: options.firstOrNull()?.second.orEmpty()
    Row(modifier = modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        Text(label, style = MaterialTheme.typography.labelMedium, color = NightColors.TextSecondary, modifier = Modifier.padding(end = 8.dp))
        Box(Modifier.weight(1f)) {
            val shape = RoundedCornerShape(10.dp)
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .heightIn(min = 44.dp)
                    .clip(shape)
                    .background(NightColors.Field)
                    .border(1.dp, NightColors.Border, shape)
                    .clickable(role = Role.DropdownList, onClickLabel = label) { open = true }
                    .padding(horizontal = 12.dp, vertical = 8.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(current, style = MaterialTheme.typography.bodyMedium, color = NightColors.TextPrimary, modifier = Modifier.weight(1f))
                Text("▾", style = MaterialTheme.typography.bodyMedium, color = NightColors.TextMuted)
            }
            DropdownMenu(
                expanded = open,
                onDismissRequest = { open = false },
                modifier = Modifier.background(NightColors.Elevated),
            ) {
                options.forEach { (key, text) ->
                    DropdownMenuItem(
                        text = {
                            Text(
                                text,
                                style = MaterialTheme.typography.bodyMedium,
                                color = if (key == selected) NightColors.PurpleSoft else NightColors.TextPrimary,
                            )
                        },
                        onClick = {
                            open = false
                            onSelect(key)
                        },
                    )
                }
            }
        }
    }
}

/** 候选行右侧的倍率：当前倍率 + 「条件成立时 …」+ 攻击力加算（Windows scoreHtml 同一口径）。 */
@Composable
internal fun RankerScore(
    score: Double?,
    counted: Boolean,
    hasComposition: Boolean,
    modifier: Modifier = Modifier,
    potential: Double? = null,
    oneStack: Boolean = false,
    flat: Double = 0.0,
) {
    Column(modifier = modifier, horizontalAlignment = Alignment.End, verticalArrangement = Arrangement.spacedBy(1.dp)) {
        if (!hasComposition) {
            Text("—", style = MaterialTheme.typography.titleMedium, color = NightColors.TextMuted)
            return@Column
        }
        val value = score ?: 1.0
        Text(
            mul(score),
            style = MaterialTheme.typography.titleMedium,
            color = if (counted && value > 1.0000001) NightColors.Green else NightColors.TextSecondary,
            maxLines = 1,
        )
        if (potential != null && Math.abs(potential - value) > 1e-7) {
            Text(
                RankerText.f(if (oneStack) "potentialOneStack" else "potentialText", mul(potential)),
                style = MaterialTheme.typography.labelSmall,
                color = NightColors.Amber,
                textAlign = TextAlign.End,
            )
        }
        if (BuffFormat.hasFlat(flat)) {
            Text(RankerText.f("flatInline", BuffFormat.flat(flat)), style = MaterialTheme.typography.labelSmall, color = NightColors.Amber)
        }
    }
}

@Composable
internal fun RankerStatePill(state: EntryState) {
    NightPill(state.label, RankerPalette.state(state))
}

/** 一排徽标（自动换行）。 */
@Composable
internal fun RankerBadges(badges: List<String>, modifier: Modifier = Modifier) {
    if (badges.isEmpty()) return
    FlowRow(modifier = modifier, horizontalArrangement = Arrangement.spacedBy(5.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
        badges.forEach { NightPill(it, RankerPalette.badge(it)) }
    }
}

/** 一排药丸（自动换行）。 */
@Composable
internal fun RankerPills(pills: List<Pair<String, Color>>, modifier: Modifier = Modifier) {
    if (pills.isEmpty()) return
    FlowRow(modifier = modifier, horizontalArrangement = Arrangement.spacedBy(6.dp), verticalArrangement = Arrangement.spacedBy(5.dp)) {
        pills.forEach { (text, color) -> NightPill(text, color) }
    }
}

/** 一行提示（左侧小圆点）：通知绿色、警告琥珀色、超限红色。 */
@Composable
internal fun RankerMessage(text: String, color: Color, modifier: Modifier = Modifier) {
    Row(modifier = modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        Box(Modifier.padding(top = 6.dp).size(6.dp).background(color, CircleShape))
        Text(text, style = MaterialTheme.typography.bodySmall, color = color, modifier = Modifier.weight(1f))
    }
}

/** 说明小字。 */
@Composable
internal fun RankerNote(text: String, modifier: Modifier = Modifier, color: Color = NightColors.TextMuted) {
    Text(text, style = MaterialTheme.typography.bodySmall, color = color, modifier = modifier)
}

/** 小标题（字段名）。 */
@Composable
internal fun RankerFieldLabel(text: String, modifier: Modifier = Modifier, trailing: String? = null) {
    Row(modifier = modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        Text(text, style = MaterialTheme.typography.labelMedium, color = NightColors.TextSecondary, modifier = Modifier.weight(1f))
        trailing?.let { Text(it, style = MaterialTheme.typography.labelSmall, color = NightColors.TextMuted) }
    }
}

/** 可点的「选择…」字段：左边当前值，右边 ▾（打开底部抽屉）。 */
@Composable
internal fun RankerPickerField(
    text: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    placeholder: Boolean = false,
    subtitle: String? = null,
    enabled: Boolean = true,
    color: Color = NightColors.TextPrimary,
) {
    val shape = RoundedCornerShape(11.dp)
    Row(
        modifier = modifier
            .fillMaxWidth()
            .heightIn(min = 48.dp)
            .clip(shape)
            .background(NightColors.Field)
            .border(1.dp, NightColors.Border, shape)
            .clickable(enabled = enabled, role = Role.Button, onClick = onClick)
            .alpha(if (enabled) 1f else .5f)
            .padding(horizontal = 12.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(1.dp)) {
            Text(
                text,
                style = MaterialTheme.typography.bodyMedium,
                fontWeight = if (placeholder) FontWeight.Normal else FontWeight.SemiBold,
                color = if (placeholder) NightColors.PurpleSoft else color,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
            )
            subtitle?.takeIf { it.isNotEmpty() }?.let {
                Text(it, style = MaterialTheme.typography.labelSmall, color = NightColors.TextMuted, maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
        }
        Text("▾", style = MaterialTheme.typography.bodyMedium, color = NightColors.TextMuted, modifier = Modifier.padding(start = 8.dp))
    }
}

/** 小「×」清除按钮（44dp 触控区）。 */
@Composable
internal fun RankerClearButton(label: String, onClick: () -> Unit, modifier: Modifier = Modifier) {
    Box(
        modifier = modifier
            .size(44.dp)
            .clip(CircleShape)
            .clickable(role = Role.Button, onClickLabel = label, onClick = onClick)
            .semantics { contentDescription = label },
        contentAlignment = Alignment.Center,
    ) {
        Text("×", style = MaterialTheme.typography.titleLarge, color = NightColors.TextMuted)
    }
}

/** 数据集原文的粗体标记：成对的 ** 换成粗体，其余原样（macOS strongText、Windows strongHtml 同一口径）。 */
internal fun strongText(text: String): AnnotatedString {
    val parts = text.split("**")
    if (parts.size < 3) return AnnotatedString(text)
    return buildAnnotatedString {
        parts.forEachIndexed { index, part ->
            when {
                index == parts.size - 1 && index % 2 == 1 -> append("**$part")
                index % 2 == 1 -> withStyle(SpanStyle(fontWeight = FontWeight.SemiBold, color = NightColors.TextPrimary)) { append(part) }
                else -> append(part)
            }
        }
    }
}

/** 底部抽屉的标题行。 */
@Composable
internal fun RankerSheetHeader(title: String, subtitle: String? = null, count: String? = null) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(title, style = MaterialTheme.typography.titleLarge, maxLines = 2, overflow = TextOverflow.Ellipsis)
            subtitle?.takeIf { it.isNotEmpty() }?.let {
                Text(it, style = MaterialTheme.typography.bodySmall, color = NightColors.TextMuted, maxLines = 3, overflow = TextOverflow.Ellipsis)
            }
        }
        count?.let { NightPill(it, NightColors.PurpleSoft) }
    }
}

/** 抽屉列表里的一项：标题、副标题、红字原因、右侧倍率。 */
@Composable
internal fun RankerPickRow(
    title: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    subtitle: String? = null,
    warning: String? = null,
    selected: Boolean = false,
    enabled: Boolean = true,
    dimmed: Boolean = false,
    trailing: (@Composable () -> Unit)? = null,
) {
    Row(
        modifier = modifier
            .fillMaxWidth()
            .heightIn(min = 52.dp)
            .clip(RoundedCornerShape(10.dp))
            .background(if (selected) NightColors.Purple.copy(alpha = .14f) else Color.Transparent)
            .clickable(enabled = enabled, onClick = onClick)
            .alpha(if (dimmed || !enabled) .55f else 1f)
            .padding(horizontal = 8.dp, vertical = 9.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(
                title,
                style = MaterialTheme.typography.bodyMedium,
                fontWeight = FontWeight.SemiBold,
                color = if (selected) NightColors.PurpleSoft else NightColors.TextPrimary,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
            )
            subtitle?.takeIf { it.isNotEmpty() }?.let {
                Text(it, style = MaterialTheme.typography.labelSmall, color = NightColors.TextMuted, maxLines = 2, overflow = TextOverflow.Ellipsis)
            }
            warning?.let { Text(it, style = MaterialTheme.typography.labelSmall, color = NightColors.Red, maxLines = 3, overflow = TextOverflow.Ellipsis) }
        }
        trailing?.let {
            Spacer(Modifier.width(8.dp))
            it()
        }
    }
}
