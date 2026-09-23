package com.nightreign.relicchecker.ui.lookup

import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import com.nightreign.relicchecker.catalog.AffixCatalog
import com.nightreign.relicchecker.gamedata.GameDataKey
import com.nightreign.relicchecker.ui.NightPill
import com.nightreign.relicchecker.ui.UserSettings
import com.nightreign.relicchecker.ui.gamedata.GameDataPendingNotice
import com.nightreign.relicchecker.ui.gamedata.GameDataScreenScaffold
import com.nightreign.relicchecker.ui.gamedata.rememberGameDataHeader
import com.nightreign.relicchecker.ui.theme.NightColors

// 占位页：由「词条反查」车道整文件替换，签名保持不变（见 android/PAGES.md）。
// 底栏一级页，onBack 恒为 null。
@Suppress("UNUSED_PARAMETER")
@Composable
internal fun LookupScreen(
    catalog: AffixCatalog,
    settings: UserSettings,
    onBack: (() -> Unit)?,
    modifier: Modifier = Modifier,
) {
    val relics = rememberGameDataHeader(GameDataKey.RELICS)
    GameDataScreenScaffold(
        title = "词条反查",
        subtitle = "AFFIX LOOKUP",
        onBack = onBack,
        state = relics,
        modifier = modifier,
        statusPills = {
            NightPill("词条库 ${catalog.affixes.size} 条", NightColors.PurpleSoft)
            NightPill("遗物物品表 v1.03.4", NightColors.TextMuted)
        },
    ) { header ->
        GameDataPendingNotice(
            detail = "从词条出发反查出处：能出现在哪些遗物、哪个槽位层与颜色上，深夜遗物的 A / B / C 池与诅咒池归属，" +
                "以及与它互斥的词条。桌面端 v0.3.0 已提供，手机版正在移植。",
            datasets = listOf(GameDataKey.RELICS to header),
        )
    }
}
