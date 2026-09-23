package com.nightreign.relicchecker.ui

import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.saveable.rememberSaveableStateHolder
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.unit.dp
import com.nightreign.relicchecker.catalog.AffixCatalog
import com.nightreign.relicchecker.ui.bosses.BossesScreen
import com.nightreign.relicchecker.ui.gamedata.GameDataLayout
import com.nightreign.relicchecker.ui.heroes.HeroesScreen
import com.nightreign.relicchecker.ui.ranker.RankerScreen
import com.nightreign.relicchecker.ui.save.SaveScreen
import com.nightreign.relicchecker.ui.theme.NightColors

/**
 * 「数据」枢纽页可进入的子页。标题与 eyebrow 同时用于枢纽卡片和子页顶栏，
 * 页面车道应直接引用 `DataPage.X.title` / `DataPage.X.eyebrow`，保证两处一致。
 */
internal enum class DataPage(
    val title: String,
    val eyebrow: String,
    val summary: String,
    val provenance: String,
    val section: DataSection,
) {
    BOSSES(
        title = "首领数据",
        eyebrow = "BOSS DATA",
        summary = "18 个夜王条目与 116 组首领的血量、削韧、承伤倍率与异常抗性；深夜按深度 1–5 分档，可叠加变异个体与多人缩放。",
        provenance = "来自游戏参数表 1.03.5 · 数值不含招式与掉落",
        section = DataSection.PARAMS,
    ),
    HEROES(
        title = "角色属性",
        eyebrow = "HERO STATS",
        summary = "10 个渡夜者 1–15 级的八项属性与血量、专注值、精力等派生值；可叠加转职遗物与利普拉的交易。",
        provenance = "来自游戏参数表 1.03.5 · 锚点等级间逐级插值",
        section = DataSection.PARAMS,
    ),
    RANKER(
        title = "增伤排名",
        eyebrow = "DAMAGE RANKER",
        summary = "自己组一套局内配置——武器词条、遗物、护符与其它增益——看这一招的总增伤。",
        provenance = "来自游戏参数表 1.03.5 · 叠加关系未经实测",
        section = DataSection.PARAMS,
    ),
    SAVE(
        title = "存档检查",
        eyebrow = "SAVE AUDIT",
        summary = "选择 .sl2 / .co2 存档，在本机解密并逐件校验全部角色的遗物。",
        provenance = "存档只读 · 本地解析，不上传、不修改",
        section = DataSection.SAVE,
    ),
}

internal enum class DataSection(val label: String, val trailing: String) {
    PARAMS("参数表数据", "游戏参数表 1.03.5"),
    SAVE("存档", "只读 · 离线"),
}

private const val HUB_STATE_KEY = "DATA_HUB"

/**
 * 「数据」底栏目的地：枢纽页与四个全屏子页之间的切换。
 *
 * [page] 为 null 时显示枢纽页；子页打开时系统返回键回到枢纽页。每个子页与枢纽页各占一个
 * SaveableStateProvider，切底栏、返回枢纽再进入都不丢页内 rememberSaveable 状态。
 */
@Composable
internal fun DataDestination(
    catalog: AffixCatalog,
    settings: UserSettings,
    page: DataPage?,
    onPageChange: (DataPage?) -> Unit,
    modifier: Modifier = Modifier,
) {
    val pageStates = rememberSaveableStateHolder()
    BackHandler(enabled = page != null) { onPageChange(null) }

    AnimatedContent(
        targetState = page,
        modifier = modifier,
        transitionSpec = {
            if (targetState != null) {
                (slideInHorizontally(tween(220)) { it / 8 } + fadeIn(tween(220))) togetherWith
                    fadeOut(tween(120))
            } else {
                fadeIn(tween(180)) togetherWith
                    (slideOutHorizontally(tween(200)) { it / 8 } + fadeOut(tween(160)))
            }
        },
        label = "data-page",
    ) { current ->
        pageStates.SaveableStateProvider(current?.name ?: HUB_STATE_KEY) {
            val back = { onPageChange(null) }
            when (current) {
                null -> DataHubScreen(onOpen = onPageChange)
                DataPage.BOSSES -> BossesScreen(catalog = catalog, settings = settings, onBack = back)
                DataPage.HEROES -> HeroesScreen(catalog = catalog, settings = settings, onBack = back)
                DataPage.RANKER -> RankerScreen(catalog = catalog, settings = settings, onBack = back)
                DataPage.SAVE -> SaveScreen(catalog = catalog, settings = settings, onBack = back)
            }
        }
    }
}

@Composable
internal fun DataHubScreen(
    onOpen: (DataPage) -> Unit,
    modifier: Modifier = Modifier,
) {
    Box(modifier = modifier.fillMaxSize(), contentAlignment = Alignment.TopCenter) {
        Column(
            modifier = Modifier
                .widthIn(max = GameDataLayout.MaxContentWidth)
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = GameDataLayout.Gutter, vertical = 14.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            NightTopBar(title = "游戏数据", eyebrow = "GAME DATA", trailing = "完全离线")
            Text(
                "首领、角色与增伤数据取自游戏参数表导出的数据集，随安装包内置；存档检查只在本机读取你选择的文件。",
                style = MaterialTheme.typography.bodySmall,
                color = NightColors.TextMuted,
            )
            DataSection.entries.forEach { section ->
                SectionLabel(section.label, section.trailing)
                DataPage.entries.filter { it.section == section }.forEach { page ->
                    DataPageCard(page = page, onClick = { onOpen(page) })
                }
            }
            Spacer(Modifier.height(4.dp))
        }
    }
}

@Composable
private fun DataPageCard(page: DataPage, onClick: () -> Unit) {
    val shape = RoundedCornerShape(16.dp)
    val accent = page.accent
    NightPanel(
        modifier = Modifier
            .fillMaxWidth()
            .clip(shape)
            .clickable(role = Role.Button, onClickLabel = "打开${page.title}", onClick = onClick),
        shape = shape,
    ) {
        Row(
            modifier = Modifier.fillMaxWidth().padding(14.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(13.dp),
        ) {
            Box(
                modifier = Modifier
                    .size(44.dp)
                    .clip(RoundedCornerShape(13.dp))
                    .background(accent.copy(alpha = .1f))
                    .border(1.dp, accent.copy(alpha = .26f), RoundedCornerShape(13.dp)),
                contentAlignment = Alignment.Center,
            ) {
                DataPageGlyph(page, accent, Modifier.size(24.dp))
            }
            Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(page.title, style = MaterialTheme.typography.titleMedium, color = NightColors.TextPrimary)
                Text(page.summary, style = MaterialTheme.typography.bodySmall, color = NightColors.TextSecondary)
                Text(page.provenance, style = MaterialTheme.typography.labelSmall, color = NightColors.TextMuted)
            }
            Text("›", style = MaterialTheme.typography.titleLarge, color = NightColors.TextMuted)
        }
    }
}

private val DataPage.accent: Color
    get() = when (this) {
        DataPage.BOSSES -> NightColors.Red
        DataPage.HEROES -> NightColors.Green
        DataPage.RANKER -> NightColors.Amber
        DataPage.SAVE -> NightColors.PurpleSoft
    }

@Composable
private fun DataPageGlyph(page: DataPage, color: Color, modifier: Modifier = Modifier) {
    Canvas(modifier = modifier) {
        val stroke = Stroke(width = 1.8.dp.toPx(), cap = StrokeCap.Round, join = StrokeJoin.Round)
        val w = size.width
        val h = size.height
        when (page) {
            DataPage.BOSSES -> {
                // 王冠
                val crown = Path().apply {
                    moveTo(w * .14f, h * .74f)
                    lineTo(w * .14f, h * .3f)
                    lineTo(w * .34f, h * .5f)
                    lineTo(w * .5f, h * .2f)
                    lineTo(w * .66f, h * .5f)
                    lineTo(w * .86f, h * .3f)
                    lineTo(w * .86f, h * .74f)
                    close()
                }
                drawPath(crown, color, style = stroke)
                drawLine(color, Offset(w * .14f, h * .88f), Offset(w * .86f, h * .88f), stroke.width, StrokeCap.Round)
            }
            DataPage.HEROES -> {
                // 人像：头 + 肩
                drawCircle(color, w * .17f, Offset(w * .5f, h * .3f), style = stroke)
                drawArc(
                    color = color,
                    startAngle = 180f,
                    sweepAngle = 180f,
                    useCenter = false,
                    topLeft = Offset(w * .16f, h * .58f),
                    size = Size(w * .68f, h * .6f),
                    style = stroke,
                )
            }
            DataPage.RANKER -> {
                // 上扬折线 + 箭头
                val trend = Path().apply {
                    moveTo(w * .12f, h * .8f)
                    lineTo(w * .4f, h * .5f)
                    lineTo(w * .58f, h * .64f)
                    lineTo(w * .86f, h * .26f)
                }
                drawPath(trend, color, style = stroke)
                drawLine(color, Offset(w * .86f, h * .26f), Offset(w * .64f, h * .24f), stroke.width, StrokeCap.Round)
                drawLine(color, Offset(w * .86f, h * .26f), Offset(w * .87f, h * .48f), stroke.width, StrokeCap.Round)
            }
            DataPage.SAVE -> {
                // 折角文档 + 两行字
                val doc = Path().apply {
                    moveTo(w * .22f, h * .1f)
                    lineTo(w * .6f, h * .1f)
                    lineTo(w * .78f, h * .28f)
                    lineTo(w * .78f, h * .9f)
                    lineTo(w * .22f, h * .9f)
                    close()
                }
                drawPath(doc, color, style = stroke)
                drawLine(color, Offset(w * .6f, h * .1f), Offset(w * .6f, h * .28f), stroke.width, StrokeCap.Round)
                drawLine(color, Offset(w * .6f, h * .28f), Offset(w * .78f, h * .28f), stroke.width, StrokeCap.Round)
                drawLine(color, Offset(w * .34f, h * .52f), Offset(w * .66f, h * .52f), stroke.width, StrokeCap.Round)
                drawLine(color, Offset(w * .34f, h * .7f), Offset(w * .58f, h * .7f), stroke.width, StrokeCap.Round)
            }
        }
    }
}
