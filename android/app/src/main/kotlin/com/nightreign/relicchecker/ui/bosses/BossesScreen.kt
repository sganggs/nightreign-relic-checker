package com.nightreign.relicchecker.ui.bosses

import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import com.nightreign.relicchecker.catalog.AffixCatalog
import com.nightreign.relicchecker.gamedata.GameDataKey
import com.nightreign.relicchecker.ui.DataPage
import com.nightreign.relicchecker.ui.NightPill
import com.nightreign.relicchecker.ui.UserSettings
import com.nightreign.relicchecker.ui.gamedata.GameDataPendingNotice
import com.nightreign.relicchecker.ui.gamedata.GameDataScreenScaffold
import com.nightreign.relicchecker.ui.gamedata.rememberGameDataHeader
import com.nightreign.relicchecker.ui.theme.NightColors

// 占位页：由「首领数据」车道整文件替换，签名保持不变（见 android/PAGES.md）。
// 由「数据」枢纽页进入，onBack 非空。
@Suppress("UNUSED_PARAMETER")
@Composable
internal fun BossesScreen(
    catalog: AffixCatalog,
    settings: UserSettings,
    onBack: (() -> Unit)?,
    modifier: Modifier = Modifier,
) {
    val bosses = rememberGameDataHeader(GameDataKey.BOSSES)
    GameDataScreenScaffold(
        title = DataPage.BOSSES.title,
        subtitle = DataPage.BOSSES.eyebrow,
        onBack = onBack,
        state = bosses,
        modifier = modifier,
        statusPills = { NightPill("参数表 1.03.5", NightColors.TextMuted) },
    ) { header ->
        GameDataPendingNotice(
            detail = DataPage.BOSSES.summary + "桌面端 v0.3.0 已提供，手机版正在移植。",
            datasets = listOf(GameDataKey.BOSSES to header),
        )
    }
}
