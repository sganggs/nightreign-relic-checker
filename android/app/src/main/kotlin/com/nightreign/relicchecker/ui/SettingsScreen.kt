package com.nightreign.relicchecker.ui

import android.os.Build
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.nightreign.relicchecker.catalog.AffixCatalog
import com.nightreign.relicchecker.rules.CheckMode
import com.nightreign.relicchecker.ui.theme.NightColors

@Composable
internal fun SettingsScreen(
    catalog: AffixCatalog,
    settings: UserSettings,
    onDefaultModeChange: (CheckMode) -> Unit,
    onAutoInspectChange: (Boolean) -> Unit,
    onSelectorShowUnavailableChange: (Boolean) -> Unit,
    onLibraryCompactChange: (Boolean) -> Unit,
    modifier: Modifier = Modifier,
) {
    val context = LocalContext.current
    val version = remember(context) {
        @Suppress("DEPRECATION")
        context.packageManager.getPackageInfo(context.packageName, 0).let { info ->
            val code = if (Build.VERSION.SDK_INT >= 28) info.longVersionCode else info.versionCode.toLong()
            "${info.versionName ?: "0.1.0"} ($code)"
        }
    }
    val counts = remember(catalog) {
        CatalogCounts(
            total = catalog.affixes.size,
            positive = catalog.affixes.count { !it.isCurse },
            curse = catalog.affixes.count { it.isCurse },
            current = catalog.affixes.count { affix ->
                affix.poolIds.any(CheckMode.CURRENT_NORMAL.eligiblePoolIds::contains)
            },
            legacy = catalog.affixes.count { affix ->
                affix.poolIds.any(CheckMode.LEGACY_NORMAL.eligiblePoolIds::contains)
            },
        )
    }

    Column(
        modifier = modifier.fillMaxSize().verticalScroll(rememberScrollState())
            .padding(horizontal = 16.dp, vertical = 14.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        NightTopBar(title = "设置", eyebrow = "PREFERENCES & ABOUT", trailing = "v${version.substringBefore(" ")}")

        SectionLabel("检查偏好", "更改后自动保存")
        NightPanel(modifier = Modifier.fillMaxWidth()) {
            Column(modifier = Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Text("默认校验口径", style = MaterialTheme.typography.labelLarge, color = NightColors.TextSecondary)
                NightSegmentedControl(
                    items = CheckMode.entries.map(CheckMode::shortTitle),
                    selectedIndex = CheckMode.entries.indexOf(settings.defaultMode),
                    onSelect = { onDefaultModeChange(CheckMode.entries[it]) },
                )
                Text(
                    settings.defaultMode.detail,
                    style = MaterialTheme.typography.bodySmall,
                    color = NightColors.TextMuted,
                )
                HorizontalDivider(color = NightColors.Border)
                SettingToggle(
                    title = "自动检查",
                    detail = "选满三条后立即给出结论；关闭后显示检查按钮。",
                    checked = settings.autoInspect,
                    onCheckedChange = onAutoInspectChange,
                )
            }
        }

        SectionLabel("浏览偏好")
        NightPanel(modifier = Modifier.fillMaxWidth()) {
            Column {
                SettingToggle(
                    title = "选择器默认显示不可用词条",
                    detail = "仍可点选，以便检查池外或来源不明的组合。",
                    checked = settings.selectorShowUnavailable,
                    onCheckedChange = onSelectorShowUnavailableChange,
                )
                HorizontalDivider(modifier = Modifier.padding(horizontal = 14.dp), color = NightColors.Border)
                SettingToggle(
                    title = "词条库紧凑显示",
                    detail = "减小行距和说明文字，一屏浏览更多记录。",
                    checked = settings.libraryCompact,
                    onCheckedChange = onLibraryCompactChange,
                )
            }
        }

        SectionLabel("数据与隐私")
        NightPanel(modifier = Modifier.fillMaxWidth()) {
            Column(modifier = Modifier.padding(horizontal = 14.dp, vertical = 6.dp)) {
                DataRow("应用版本", version)
                DataRow("游戏版本", catalog.gameVersion)
                DataRow("数据版本", catalog.dataVersion)
                DataRow("生成时间", catalog.generatedAt)
                DataRow("全部记录", counts.total.toString())
                DataRow("正面 / 负面", "${counts.positive} / ${counts.curse}")
                DataRow("普通 1.03 / 旧池", "${counts.current} / ${counts.legacy}")
            }
        }
        NightPanel(modifier = Modifier.fillMaxWidth(), borderColor = NightColors.Green.copy(alpha = .35f)) {
            Column(modifier = Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    NightPill("离线", NightColors.Green, dot = true)
                    Text("本地完成，不读取存档", fontWeight = FontWeight.SemiBold)
                }
                Text(
                    "应用未声明 INTERNET 权限，不收集或上传数据。内置词条库、搜索、随机和判定都只在设备上运行。",
                    style = MaterialTheme.typography.bodySmall,
                    color = NightColors.TextSecondary,
                )
            }
        }

        SectionLabel("来源与许可")
        catalog.sources.forEach { source ->
            NightPanel(modifier = Modifier.fillMaxWidth()) {
                Column(modifier = Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(5.dp)) {
                    Text(source.name, fontWeight = FontWeight.SemiBold, color = NightColors.TextPrimary)
                    Text(
                        listOf(source.license, source.revision).filter(String::isNotBlank).joinToString(" · "),
                        style = MaterialTheme.typography.labelSmall,
                        color = NightColors.PurpleSoft,
                    )
                    if (source.url.isNotBlank()) {
                        Text(source.url, style = MaterialTheme.typography.bodySmall, color = NightColors.TextMuted)
                    }
                }
            }
        }

        SectionLabel("关于")
        NightPanel(modifier = Modifier.fillMaxWidth()) {
            Column(modifier = Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text("夜幕验物 · Android", style = MaterialTheme.typography.titleMedium)
                Text(
                    "与 Windows、macOS 版共享同一份权威词条数据和核心判定口径。Android 版目前专注三词条手动验物，尚未移植 .sl2 / .co2 存档解析。",
                    style = MaterialTheme.typography.bodySmall,
                    color = NightColors.TextSecondary,
                )
                HorizontalDivider(color = NightColors.Border)
                Text("GNU General Public License v3.0", color = NightColors.PurpleSoft, style = MaterialTheme.typography.labelMedium)
            }
        }
        Spacer(Modifier.padding(4.dp))
    }
}

@Composable
private fun SettingToggle(
    title: String,
    detail: String,
    checked: Boolean,
    onCheckedChange: (Boolean) -> Unit,
) {
    Row(
        modifier = Modifier.fillMaxWidth().clickable { onCheckedChange(!checked) }.padding(14.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(title, style = MaterialTheme.typography.bodyLarge, fontWeight = FontWeight.SemiBold)
            Text(detail, style = MaterialTheme.typography.bodySmall, color = NightColors.TextMuted)
        }
        Switch(
            checked = checked,
            onCheckedChange = onCheckedChange,
            colors = SwitchDefaults.colors(
                checkedThumbColor = NightColors.TextPrimary,
                checkedTrackColor = NightColors.Purple,
                uncheckedThumbColor = NightColors.TextSecondary,
                uncheckedTrackColor = NightColors.Field,
                uncheckedBorderColor = NightColors.BorderStrong,
            ),
        )
    }
}

@Composable
private fun DataRow(label: String, value: String) {
    Row(modifier = Modifier.fillMaxWidth().padding(vertical = 9.dp), horizontalArrangement = Arrangement.spacedBy(16.dp)) {
        Text(label, color = NightColors.TextMuted, style = MaterialTheme.typography.bodySmall)
        Text(value, modifier = Modifier.weight(1f), color = NightColors.TextPrimary, style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.Medium)
    }
}

private data class CatalogCounts(
    val total: Int,
    val positive: Int,
    val curse: Int,
    val current: Int,
    val legacy: Int,
)
