package com.nightreign.relicchecker.ui

import android.annotation.SuppressLint

import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.selectableGroup
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import com.nightreign.relicchecker.R
import com.nightreign.relicchecker.rules.Affix
import com.nightreign.relicchecker.ui.theme.NightColors

// 底栏顺序即枚举顺序；「反查」紧跟「检查」（两者都是从词条出发的功能）
internal enum class AppDestination(val label: String) {
    CHECKER("检查"),
    LOOKUP("反查"),
    CATALOG("词条库"),
    DATA("数据"),
    SETTINGS("设置"),
}

@Composable
internal fun NightBackground(content: @Composable BoxScope.() -> Unit) {
    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(NightColors.BackgroundDeep)
            .background(
                Brush.radialGradient(
                    colors = listOf(
                        NightColors.Purple.copy(alpha = 0.13f),
                        NightColors.Background.copy(alpha = 0.96f),
                        NightColors.Background,
                    ),
                    center = Offset(420f, -80f),
                    radius = 840f,
                ),
            ),
        content = content,
    )
}

/**
 * 页面顶栏。[onBack] 非空时左侧的应用图标换成返回按钮（数据枢纽进入的子页用），
 * 系统返回键由外层导航的 BackHandler 处理，这里只负责可点的按钮。
 */
@Composable
@SuppressLint("ModifierParameter")
internal fun NightTopBar(
    title: String,
    eyebrow: String? = null,
    trailing: String? = null,
    modifier: Modifier = Modifier,
    onBack: (() -> Unit)? = null,
) {
    Row(
        modifier = modifier
            .fillMaxWidth()
            .height(52.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        if (onBack != null) {
            NightBackButton(onClick = onBack)
        } else {
            Box(
                modifier = Modifier
                    .size(38.dp)
                    .clip(CircleShape)
                    .background(NightColors.Purple.copy(alpha = 0.13f))
                    .border(1.dp, NightColors.PurpleSoft.copy(alpha = 0.22f), CircleShape),
                contentAlignment = Alignment.Center,
            ) {
                androidx.compose.foundation.Image(
                    painter = painterResource(R.drawable.nightreign_icon),
                    contentDescription = null,
                    modifier = Modifier.size(34.dp),
                )
            }
        }
        Spacer(Modifier.width(11.dp))
        Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(1.dp)) {
            Text(
                text = title,
                style = MaterialTheme.typography.headlineSmall,
                color = NightColors.TextPrimary,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            eyebrow?.let {
                Text(
                    text = it,
                    style = MaterialTheme.typography.labelSmall,
                    color = NightColors.TextMuted,
                    maxLines = 1,
                )
            }
        }
        trailing?.let {
            NightPill(text = it, color = NightColors.Green, dot = true)
        }
    }
}

@Composable
internal fun NightBackButton(
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    label: String = "返回",
) {
    // 点击区 48dp（触控最小尺寸），圆形底只画 38dp，顶栏高度不变
    Box(
        modifier = modifier
            .size(48.dp)
            .clip(CircleShape)
            .clickable(role = Role.Button, onClickLabel = label, onClick = onClick)
            .semantics { contentDescription = label },
        contentAlignment = Alignment.Center,
    ) {
        Box(
            modifier = Modifier
                .size(38.dp)
                .clip(CircleShape)
                .background(NightColors.FieldSoft)
                .border(1.dp, NightColors.BorderStrong, CircleShape),
            contentAlignment = Alignment.Center,
        ) {
        Canvas(modifier = Modifier.size(15.dp)) {
            val width = 2.dp.toPx()
            val tip = Offset(size.width * .3f, size.height * .5f)
            drawLine(NightColors.TextPrimary, Offset(size.width * .68f, size.height * .1f), tip, width, StrokeCap.Round)
            drawLine(NightColors.TextPrimary, tip, Offset(size.width * .68f, size.height * .9f), width, StrokeCap.Round)
        }
        }
    }
}

/**
 * 与词条库详情、检查页选择器同款的底部抽屉：深色底、粗拖拽条、全展开。
 * 选择器与详情都用它，保持手机上的交互一致。
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun NightBottomSheet(
    onDismissRequest: () -> Unit,
    content: @Composable ColumnScope.() -> Unit,
) {
    ModalBottomSheet(
        onDismissRequest = onDismissRequest,
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
        content = content,
    )
}

@Composable
@SuppressLint("ModifierParameter")
internal fun SectionLabel(
    text: String,
    trailing: String? = null,
    modifier: Modifier = Modifier,
) {
    Row(
        modifier = modifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            text = text,
            style = MaterialTheme.typography.labelLarge,
            color = NightColors.TextSecondary,
        )
        Spacer(Modifier.weight(1f))
        trailing?.let {
            Text(
                text = it,
                style = MaterialTheme.typography.labelSmall,
                color = NightColors.TextMuted,
            )
        }
    }
}

@Composable
internal fun NightPanel(
    modifier: Modifier = Modifier,
    borderColor: Color = NightColors.Border,
    shape: RoundedCornerShape = RoundedCornerShape(16.dp),
    content: @Composable BoxScope.() -> Unit,
) {
    Box(
        modifier = modifier
            .clip(shape)
            .background(
                Brush.linearGradient(
                    listOf(NightColors.Card, Color(0xFF120F1B)),
                ),
            )
            .border(1.dp, borderColor, shape),
        content = content,
    )
}

@Composable
internal fun NightSegmentedControl(
    items: List<String>,
    selectedIndex: Int,
    onSelect: (Int) -> Unit,
    modifier: Modifier = Modifier,
    height: Dp = 40.dp,
) {
    val shape = RoundedCornerShape(14.dp)
    BoxWithConstraints(
        modifier = modifier
            .fillMaxWidth()
            .height(height)
            .clip(shape)
            .background(NightColors.Field)
            .border(1.dp, NightColors.Border, shape)
            .padding(3.dp)
            .semantics { selectableGroup() },
    ) {
        val segmentWidth = maxWidth / items.size
        val position by animateDpAsState(
            targetValue = segmentWidth * selectedIndex,
            animationSpec = tween(220, easing = FastOutSlowInEasing),
            label = "segment-position",
        )
        Box(
            modifier = Modifier
                .offset { IntOffset(position.roundToPx(), 0) }
                .width(segmentWidth)
                .fillMaxHeight()
                .clip(RoundedCornerShape(11.dp))
                .background(NightColors.Purple),
        )
        Row(modifier = Modifier.fillMaxSize()) {
            items.forEachIndexed { index, label ->
                val selected = index == selectedIndex
                val color by animateColorAsState(
                    if (selected) NightColors.TextPrimary else NightColors.TextSecondary,
                    tween(160),
                    label = "segment-color",
                )
                Box(
                    modifier = Modifier
                        .weight(1f)
                        .fillMaxHeight()
                        .clickable(
                            interactionSource = remember { MutableInteractionSource() },
                            indication = null,
                            role = Role.Tab,
                        ) { onSelect(index) }
                        .semantics { this.selected = selected },
                    contentAlignment = Alignment.Center,
                ) {
                    Text(
                        text = label,
                        style = MaterialTheme.typography.labelLarge,
                        fontWeight = if (selected) FontWeight.SemiBold else FontWeight.Medium,
                        color = color,
                        maxLines = 1,
                    )
                }
            }
        }
    }
}

@Composable
@SuppressLint("ModifierParameter")
internal fun NightPill(
    text: String,
    color: Color = NightColors.PurpleSoft,
    modifier: Modifier = Modifier,
    dot: Boolean = false,
) {
    Row(
        modifier = modifier
            .clip(RoundedCornerShape(999.dp))
            .background(color.copy(alpha = 0.09f))
            .border(1.dp, color.copy(alpha = 0.24f), RoundedCornerShape(999.dp))
            .padding(horizontal = 8.dp, vertical = 4.dp),
        horizontalArrangement = Arrangement.spacedBy(5.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        if (dot) Box(Modifier.size(5.dp).background(color, CircleShape))
        Text(text, style = MaterialTheme.typography.labelSmall, color = color, maxLines = 1)
    }
}

@Composable
internal fun NightSearchField(
    value: String,
    onValueChange: (String) -> Unit,
    modifier: Modifier = Modifier,
    placeholder: String = "搜索词条",
) {
    var focused by remember { mutableStateOf(false) }
    val border by animateColorAsState(
        if (focused) NightColors.Purple.copy(alpha = 0.85f) else NightColors.Border,
        tween(160),
        label = "search-border",
    )
    BasicTextField(
        value = value,
        onValueChange = onValueChange,
        modifier = modifier
            .fillMaxWidth()
            .height(46.dp)
            .onFocusChanged { focused = it.isFocused },
        textStyle = MaterialTheme.typography.bodyLarge.copy(color = NightColors.TextPrimary),
        singleLine = true,
        decorationBox = { inner ->
            Row(
                modifier = Modifier
                    .fillMaxSize()
                    .clip(RoundedCornerShape(12.dp))
                    .background(NightColors.Field)
                    .border(1.dp, border, RoundedCornerShape(12.dp))
                    .padding(horizontal = 13.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text("⌕", style = MaterialTheme.typography.titleMedium, color = NightColors.PurpleSoft)
                Spacer(Modifier.width(9.dp))
                Box(modifier = Modifier.weight(1f)) {
                    if (value.isEmpty()) {
                        Text(
                            placeholder,
                            style = MaterialTheme.typography.bodyLarge,
                            color = NightColors.TextMuted,
                        )
                    }
                    inner()
                }
                if (value.isNotEmpty()) {
                    Box(
                        modifier = Modifier
                            .size(40.dp)
                            .clickable(
                                interactionSource = remember { MutableInteractionSource() },
                                indication = null,
                            ) { onValueChange("") },
                        contentAlignment = Alignment.Center,
                    ) {
                        Text("×", style = MaterialTheme.typography.titleMedium, color = NightColors.TextMuted)
                    }
                }
            }
        },
    )
}

@Composable
internal fun AffixSummary(
    affix: Affix,
    modifier: Modifier = Modifier,
    compact: Boolean = false,
    showDescription: Boolean = true,
) {
    Column(modifier = modifier, verticalArrangement = Arrangement.spacedBy(if (compact) 2.dp else 4.dp)) {
        Text(
            text = affix.name,
            style = if (compact) MaterialTheme.typography.bodyMedium else MaterialTheme.typography.bodyLarge,
            fontWeight = FontWeight.SemiBold,
            color = NightColors.TextPrimary,
            maxLines = if (compact) 1 else 2,
            overflow = TextOverflow.Ellipsis,
        )
        if (showDescription && affix.explanation.isNotBlank() && !compact) {
            Text(
                text = affix.explanation,
                style = MaterialTheme.typography.bodySmall,
                color = NightColors.TextSecondary,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
            )
        }
        Row(
            horizontalArrangement = Arrangement.spacedBy(7.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(affix.effectId.toString(), style = MaterialTheme.typography.labelSmall, color = NightColors.PurpleSoft)
            Text("·", color = NightColors.TextMuted)
            Text(affix.category, style = MaterialTheme.typography.labelSmall, color = NightColors.TextMuted, maxLines = 1)
            if (affix.requiresCurse) NightPill("需诅咒", NightColors.Amber)
        }
    }
}

@Composable
internal fun NightNavBar(
    current: AppDestination,
    onSelect: (AppDestination) -> Unit,
) {
    Surface(color = NightColors.Elevated, tonalElevation = 0.dp, shadowElevation = 0.dp) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .border(1.dp, NightColors.Border)
                .navigationBarsPadding()
                .height(64.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            AppDestination.entries.forEach { destination ->
                val active = destination == current
                val color by animateColorAsState(
                    if (active) NightColors.PurpleSoft else NightColors.TextMuted,
                    tween(160),
                    label = "nav-color",
                )
                Column(
                    modifier = Modifier
                        .weight(1f)
                        .fillMaxHeight()
                        .clickable(
                            interactionSource = remember { MutableInteractionSource() },
                            indication = null,
                            role = Role.Tab,
                        ) { onSelect(destination) }
                        .semantics {
                            this.selected = active
                            role = Role.Tab
                            contentDescription = destination.label
                        },
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.Center,
                ) {
                    NightNavGlyph(destination, color, Modifier.size(23.dp))
                    Spacer(Modifier.height(3.dp))
                    Text(destination.label, style = MaterialTheme.typography.labelSmall, color = color)
                }
            }
        }
    }
}

@Composable
private fun NightNavGlyph(destination: AppDestination, color: Color, modifier: Modifier = Modifier) {
    Canvas(modifier = modifier) {
        val stroke = Stroke(width = 1.8.dp.toPx(), cap = StrokeCap.Round)
        when (destination) {
            AppDestination.CHECKER -> {
                val path = Path().apply {
                    moveTo(size.width * .5f, size.height * .08f)
                    lineTo(size.width * .9f, size.height * .5f)
                    lineTo(size.width * .5f, size.height * .92f)
                    lineTo(size.width * .1f, size.height * .5f)
                    close()
                }
                drawPath(path, color, style = stroke)
                drawLine(color, Offset(size.width * .32f, size.height * .52f), Offset(size.width * .46f, size.height * .66f), stroke.width, StrokeCap.Round)
                drawLine(color, Offset(size.width * .46f, size.height * .66f), Offset(size.width * .7f, size.height * .35f), stroke.width, StrokeCap.Round)
            }
            AppDestination.LOOKUP -> {
                // 放大镜里嵌一枚检查页同款的菱形：从词条反查遗物
                val lens = Offset(size.width * .42f, size.height * .42f)
                val radius = size.minDimension * .3f
                drawCircle(color, radius, lens, style = stroke)
                drawLine(color, Offset(size.width * .64f, size.height * .64f), Offset(size.width * .9f, size.height * .9f), stroke.width, StrokeCap.Round)
                val gem = Path().apply {
                    moveTo(lens.x, lens.y - radius * .5f)
                    lineTo(lens.x + radius * .42f, lens.y)
                    lineTo(lens.x, lens.y + radius * .5f)
                    lineTo(lens.x - radius * .42f, lens.y)
                    close()
                }
                drawPath(gem, color, style = Stroke(width = 1.4.dp.toPx(), cap = StrokeCap.Round))
            }
            AppDestination.DATA -> {
                // 三根高低不一的柱子 + 基线：参数表数据
                val base = size.height * .86f
                drawLine(color, Offset(size.width * .1f, base), Offset(size.width * .9f, base), stroke.width, StrokeCap.Round)
                listOf(.27f to .52f, .5f to .18f, .73f to .38f).forEach { (x, top) ->
                    drawLine(color, Offset(size.width * x, base - 3.dp.toPx()), Offset(size.width * x, size.height * top), 3.2.dp.toPx(), StrokeCap.Round)
                }
            }
            AppDestination.CATALOG -> {
                drawRoundRect(color, Offset(size.width * .14f, size.height * .12f), Size(size.width * .72f, size.height * .76f), cornerRadius = androidx.compose.ui.geometry.CornerRadius(3.dp.toPx()), style = stroke)
                listOf(.34f, .5f, .66f).forEach { y ->
                    drawCircle(color, 1.2.dp.toPx(), Offset(size.width * .3f, size.height * y))
                    drawLine(color, Offset(size.width * .42f, size.height * y), Offset(size.width * .72f, size.height * y), stroke.width, StrokeCap.Round)
                }
            }
            AppDestination.SETTINGS -> {
                drawCircle(color, size.minDimension * .31f, center, style = stroke)
                drawCircle(color, size.minDimension * .11f, center, style = stroke)
                repeat(8) { index ->
                    val angle = Math.toRadians((index * 45).toDouble())
                    val inner = size.minDimension * .35f
                    val outer = size.minDimension * .45f
                    drawLine(
                        color,
                        Offset(center.x + kotlin.math.cos(angle).toFloat() * inner, center.y + kotlin.math.sin(angle).toFloat() * inner),
                        Offset(center.x + kotlin.math.cos(angle).toFloat() * outer, center.y + kotlin.math.sin(angle).toFloat() * outer),
                        stroke.width,
                        StrokeCap.Round,
                    )
                }
            }
        }
    }
}
