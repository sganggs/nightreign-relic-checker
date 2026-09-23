package com.nightreign.relicchecker.ui.gamedata

import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.nightreign.relicchecker.gamedata.GameDataHeader
import com.nightreign.relicchecker.gamedata.GameDataKey
import com.nightreign.relicchecker.ui.NightPanel
import com.nightreign.relicchecker.ui.NightPill
import com.nightreign.relicchecker.ui.NightTopBar
import com.nightreign.relicchecker.ui.SectionLabel
import com.nightreign.relicchecker.ui.theme.NightColors

/** 数据页共用的版式尺寸：左右留白与检查 / 词条库页一致，宽屏时内容居中限宽。 */
internal object GameDataLayout {
    /** 左右留白，与其它一级页相同。 */
    val Gutter: Dp = 16.dp

    /** 平板 / 横屏时内容列的最大宽度，超出部分两侧留空、内容居中。 */
    val MaxContentWidth: Dp = 720.dp

    /** 分区之间的竖向间距。 */
    val SectionSpacing: Dp = 12.dp

    /** 内容区 LazyColumn 的 contentPadding：左右留白 + 底部余量（避免最后一行贴着底栏）。 */
    fun listPadding(top: Dp = 4.dp, bottom: Dp = 28.dp): PaddingValues =
        PaddingValues(start = Gutter, end = Gutter, top = top, bottom = bottom)
}

/**
 * 数据页统一外壳（与数据加载无关的版本）：顶栏 + 可选状态小标签行 + 内容区。
 *
 * - [onBack] 非空时顶栏左侧显示返回按钮（数据枢纽进入的子页）；一级页（词条反查）传 null；
 * - [statusPills] 是顶栏下方一行可横向滚动的 [NightPill]，放数据版本、条目数之类的小字；
 * - [content] 占满剩余高度且**不带左右留白**，便于放整宽的 LazyColumn / 分隔线；
 *   自己加留白时用 [GameDataLayout.Gutter] 或 [GameDataLayout.listPadding]；
 * - 宽屏时整页居中、最大宽度 [GameDataLayout.MaxContentWidth]。
 */
@Composable
internal fun GameDataScreenScaffold(
    title: String,
    subtitle: String?,
    onBack: (() -> Unit)?,
    modifier: Modifier = Modifier,
    statusPills: (@Composable RowScope.() -> Unit)? = null,
    content: @Composable ColumnScope.() -> Unit,
) {
    Box(modifier = modifier.fillMaxSize(), contentAlignment = Alignment.TopCenter) {
        Column(
            modifier = Modifier
                .widthIn(max = GameDataLayout.MaxContentWidth)
                .fillMaxSize()
                .padding(top = 14.dp),
        ) {
            Column(
                modifier = Modifier.padding(horizontal = GameDataLayout.Gutter),
                verticalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                NightTopBar(title = title, eyebrow = subtitle, onBack = onBack)
                if (statusPills != null) {
                    Row(
                        modifier = Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()),
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        content = statusPills,
                    )
                }
            }
            Spacer(Modifier.height(GameDataLayout.SectionSpacing))
            Column(modifier = Modifier.fillMaxWidth().weight(1f), content = content)
        }
    }
}

/**
 * 数据页统一外壳（带加载状态的版本）：[state] 为加载中时显示进度，失败时显示原因与
 * 「请确认 APK 由完整仓库构建」，就绪后把解析结果交给 [content]。
 * 典型用法见 android/PAGES.md。
 */
@Composable
internal fun <T> GameDataScreenScaffold(
    title: String,
    subtitle: String?,
    onBack: (() -> Unit)?,
    state: GameDataState<T>,
    modifier: Modifier = Modifier,
    statusPills: (@Composable RowScope.() -> Unit)? = null,
    loadingLabel: String = "载入游戏数据",
    content: @Composable ColumnScope.(T) -> Unit,
) {
    GameDataScreenScaffold(
        title = title,
        subtitle = subtitle,
        onBack = onBack,
        modifier = modifier,
        statusPills = statusPills,
    ) {
        when (state) {
            GameDataState.Loading -> GameDataLoadingView(loadingLabel)
            is GameDataState.Failed -> GameDataErrorView(state.error)
            is GameDataState.Ready -> content(state.value)
        }
    }
}

@Composable
internal fun GameDataLoadingView(label: String = "载入游戏数据", modifier: Modifier = Modifier) {
    Box(modifier = modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            CircularProgressIndicator(color = NightColors.PurpleSoft, strokeWidth = 2.dp)
            Text(label, color = NightColors.TextSecondary, style = MaterialTheme.typography.bodyMedium)
        }
    }
}

@Composable
internal fun GameDataErrorView(error: Throwable, modifier: Modifier = Modifier) {
    Box(
        modifier = modifier
            .fillMaxSize()
            .padding(horizontal = GameDataLayout.Gutter, vertical = 24.dp),
        contentAlignment = Alignment.Center,
    ) {
        NightPanel(modifier = Modifier.fillMaxWidth(), borderColor = NightColors.Red.copy(alpha = .5f)) {
            Column(
                modifier = Modifier.fillMaxWidth().padding(20.dp),
                verticalArrangement = Arrangement.spacedBy(10.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                Text("无法载入游戏数据", style = MaterialTheme.typography.titleLarge)
                Text(
                    error.message ?: error::class.java.simpleName,
                    color = NightColors.Red,
                    style = MaterialTheme.typography.bodySmall,
                    textAlign = TextAlign.Center,
                    maxLines = 12,
                    overflow = TextOverflow.Ellipsis,
                )
                Text(
                    "请确认 APK 由完整仓库构建（data/ 下的数据集需随安装包一起打包）。",
                    color = NightColors.TextSecondary,
                    style = MaterialTheme.typography.bodySmall,
                    textAlign = TextAlign.Center,
                )
            }
        }
    }
}

/**
 * 占位页的正文：说明本页尚未移植，并列出已从 APK 读到的数据集（验证加载骨架可用）。
 * 页面车道替换占位文件后不再使用。
 */
@Composable
internal fun GameDataPendingNotice(
    detail: String,
    modifier: Modifier = Modifier,
    datasets: List<Pair<GameDataKey, GameDataHeader>> = emptyList(),
) {
    Column(
        modifier = modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = GameDataLayout.Gutter),
        verticalArrangement = Arrangement.spacedBy(GameDataLayout.SectionSpacing),
    ) {
        NightPanel(modifier = Modifier.fillMaxWidth(), borderColor = NightColors.Amber.copy(alpha = .35f)) {
            Column(
                modifier = Modifier.fillMaxWidth().padding(16.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                NightPill("待移植", NightColors.Amber, dot = true)
                Text("本页尚未移植", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
                Text(detail, style = MaterialTheme.typography.bodySmall, color = NightColors.TextSecondary)
            }
        }
        if (datasets.isNotEmpty()) {
            SectionLabel("已内置的数据集", "${datasets.size} 份")
            NightPanel(modifier = Modifier.fillMaxWidth()) {
                Column(
                    modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 12.dp),
                    verticalArrangement = Arrangement.spacedBy(10.dp),
                ) {
                    datasets.forEach { (key, header) ->
                        Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                            Text(key.fileName, style = MaterialTheme.typography.bodyMedium, color = NightColors.TextPrimary)
                            Text(
                                listOf(
                                    "${key.versionField} ${header.versionOf(key)}",
                                    header.gameVersion,
                                    header.dataVersion,
                                ).filter(String::isNotBlank).joinToString(" · "),
                                style = MaterialTheme.typography.labelSmall,
                                color = NightColors.TextMuted,
                            )
                        }
                    }
                }
            }
        }
    }
}
