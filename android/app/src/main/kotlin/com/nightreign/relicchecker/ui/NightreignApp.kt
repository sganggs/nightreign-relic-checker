package com.nightreign.relicchecker.ui

import androidx.compose.animation.Crossfade
import androidx.compose.animation.core.tween
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.saveable.rememberSaveableStateHolder
import androidx.compose.runtime.setValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import com.nightreign.relicchecker.catalog.AffixCatalog
import com.nightreign.relicchecker.catalog.CatalogLoader
import com.nightreign.relicchecker.rules.CheckMode
import com.nightreign.relicchecker.ui.theme.NightColors
import androidx.compose.runtime.LaunchedEffect
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

// 进程级缓存：词条库只解析一次，旋转等配置变更不重读
private object CatalogCache {
    @Volatile
    var result: Result<AffixCatalog>? = null
}

@Composable
fun NightreignApp() {
    val context = LocalContext.current
    val settingsRepository = remember { SettingsRepository(context.applicationContext) }
    val settings by settingsRepository.settings.collectAsState(initial = null)
    var catalogResult by remember { mutableStateOf(CatalogCache.result) }
    LaunchedEffect(Unit) {
        if (catalogResult == null) {
            val appContext = context.applicationContext
            val loaded = withContext(Dispatchers.IO) {
                runCatching {
                    appContext.assets.open(CatalogLoader.ASSET_FILE_NAME).bufferedReader().use { reader ->
                        CatalogLoader.parse(reader.readText())
                    }
                }
            }
            CatalogCache.result = loaded
            catalogResult = loaded
        }
    }

    NightBackground {
        val resolvedCatalog = catalogResult
        if (resolvedCatalog == null) {
            LoadingScreen()
        } else {
            resolvedCatalog.fold(
                onSuccess = { catalog ->
                    val resolvedSettings = settings
                    if (resolvedSettings == null) LoadingScreen() else AppScaffold(
                        catalog = catalog,
                        settings = resolvedSettings,
                        settingsRepository = settingsRepository,
                    )
                },
                onFailure = { error -> CatalogErrorScreen(error) },
            )
        }
    }
}

@Composable
private fun AppScaffold(
    catalog: AffixCatalog,
    settings: UserSettings,
    settingsRepository: SettingsRepository,
) {
    var destinationName by rememberSaveable { mutableStateOf(AppDestination.CHECKER.name) }
    val destination = AppDestination.valueOf(destinationName)
    val stateHolder = rememberSaveableStateHolder()
    val scope = rememberCoroutineScope()

    Scaffold(
        containerColor = Color.Transparent,
        contentColor = NightColors.TextPrimary,
        bottomBar = {
            NightNavBar(current = destination) { destinationName = it.name }
        },
    ) { padding ->
        Crossfade(
            targetState = destination,
            animationSpec = tween(180),
            label = "root-destination",
        ) { current ->
            stateHolder.SaveableStateProvider(current.name) {
                when (current) {
                    AppDestination.CHECKER -> CheckerScreen(
                        catalog = catalog,
                        settings = settings,
                        modifier = Modifier.padding(padding),
                    )
                    AppDestination.CATALOG -> CatalogScreen(
                        catalog = catalog,
                        compact = settings.libraryCompact,
                        modifier = Modifier.padding(padding),
                    )
                    AppDestination.SETTINGS -> SettingsScreen(
                        catalog = catalog,
                        settings = settings,
                        onDefaultModeChange = { mode: CheckMode ->
                            scope.launch { settingsRepository.setDefaultMode(mode) }
                        },
                        onAutoInspectChange = { enabled ->
                            scope.launch { settingsRepository.setAutoInspect(enabled) }
                        },
                        onSelectorShowUnavailableChange = { enabled ->
                            scope.launch { settingsRepository.setSelectorShowUnavailable(enabled) }
                        },
                        onLibraryCompactChange = { enabled ->
                            scope.launch { settingsRepository.setLibraryCompact(enabled) }
                        },
                        modifier = Modifier.padding(padding),
                    )
                }
            }
        }
    }
}

@Composable
private fun LoadingScreen() {
    Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            CircularProgressIndicator(color = NightColors.PurpleSoft, strokeWidth = 2.dp)
            Text("载入本地词条库", color = NightColors.TextSecondary)
        }
    }
}

@Composable
private fun CatalogErrorScreen(error: Throwable) {
    Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        NightPanel(modifier = Modifier.padding(28.dp), borderColor = NightColors.Red.copy(alpha = .5f)) {
            Column(
                modifier = Modifier.padding(20.dp),
                verticalArrangement = Arrangement.spacedBy(10.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                Text("无法载入内置词条库", style = MaterialTheme.typography.titleLarge)
                Text(
                    error.message ?: error::class.java.simpleName,
                    color = NightColors.Red,
                    style = MaterialTheme.typography.bodySmall,
                )
                Text("请确认 APK 由完整仓库的 Android 工程构建。", color = NightColors.TextSecondary)
            }
        }
    }
}
