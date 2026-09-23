# Android 数据页移植约定

本文件写给移植桌面端 v0.3.0 新功能的各条车道：**词条反查、首领数据、角色属性、增伤排名、存档检查**。
导航、数据加载与页面外壳已经由骨架提供，各车道只需要**整文件替换自己的占位页**，再在 `:gamedata`
里写自己的解析与测试。骨架文件一律不改，这样五条车道可以并行开发、合并时互不冲突。

## 1. 导航结构（已完成，勿改）

底栏 5 项（`AppDestination`，顺序即显示顺序）：

| 底栏 | 目的地 | 内容 |
| --- | --- | --- |
| 检查 | `CHECKER` | 三词条手动检查（原有） |
| 反查 | `LOOKUP` | **词条反查**（一级页，紧跟「检查」） |
| 词条库 | `CATALOG` | 词条库浏览（原有） |
| 数据 | `DATA` | 数据枢纽页 → 首领数据 / 角色属性 / 增伤排名 / 存档检查 |
| 设置 | `SETTINGS` | 设置与关于（原有） |

- 「数据」是枢纽页 `DataHubScreen`，四张入口卡片点进全屏子页；子页顶栏左侧是返回按钮，系统返回键也回到枢纽页（`DataDestination` 里的 `BackHandler`）。
- 在子页里再点一次底栏「数据」，同样回到枢纽页。
- 状态保持：每个一级页、枢纽页和每个子页各有一个 `SaveableStateProvider`。**页内用 `rememberSaveable` 保存的状态**在切换底栏、返回枢纽后再进入时都会保留；用普通 `remember` 保存的状态会丢。
- 子页标题与英文小标题统一从 `DataPage` 取（`DataPage.BOSSES.title` / `.eyebrow` 等），保证与枢纽卡片一致；词条反查的标题是「词条反查」/「AFFIX LOOKUP」。

## 2. 文件归属

| 车道 | 占位文件（整文件替换） | 入口 | 可能用到的数据 | `:gamedata` 包 |
| --- | --- | --- | --- | --- |
| 词条反查 | `app/.../ui/lookup/LookupScreen.kt` | 底栏「反查」，`onBack = null` | `RELICS` + 词条库 `catalog` | `gamedata/lookup/` |
| 首领数据 | `app/.../ui/bosses/BossesScreen.kt` | 数据 → 首领数据 | `BOSSES` | `gamedata/bosses/` |
| 角色属性 | `app/.../ui/heroes/HeroesScreen.kt` | 数据 → 角色属性 | `HEROES` | `gamedata/heroes/` |
| 增伤排名 | `app/.../ui/ranker/RankerScreen.kt` | 数据 → 增伤排名 | `SKILLS` + `BUFFS`（自组遗物校验另需 `catalog`，必要时 `RELICS`） | `gamedata/ranker/` |
| 存档检查 | `app/.../ui/save/SaveScreen.kt` | 数据 → 存档检查 | `RELICS` + `catalog`；存档文件经 SAF 选取 | `gamedata/save/` |

（`app/...` = `app/src/main/kotlin/com/nightreign/relicchecker`；`gamedata/<page>/` =
`gamedata/src/main/kotlin/com/nightreign/relicchecker/gamedata/<page>/`，测试放
`gamedata/src/test/kotlin/com/nightreign/relicchecker/gamedata/<page>/`。）

**各车道可以改动的范围：**

- 自己的 `app/.../ui/<page>/` 目录：替换占位文件，可在同目录新增任意文件（组件、状态、格式化工具）；
- 自己的 `gamedata/.../gamedata/<page>/` 包与对应测试目录；
- 如需 `:app` 的 JVM 单测，放 `app/src/test/kotlin/com/nightreign/relicchecker/ui/<page>/`。

**不要改的骨架文件**（需要改动时在最终报告里提出，由收尾车道统一处理）：

- `NightreignApp.kt`、`Components.kt`、`DataHubScreen.kt`、`theme/Theme.kt`、`ui/gamedata/*`；
- 原有页面 `CheckerScreen.kt`、`CatalogScreen.kt`、`SettingsScreen.kt`、`SettingsRepository.kt`（设置页的「关于」文案由收尾车道改）；
- `:rules`、`:catalog` 全部源码，`:gamedata` 根包下的 `GameDataFiles.kt` / `GameDataJson.kt` / `GameDataHeader.kt`；
- 所有 `build.gradle.kts`、`settings.gradle.kts`、Gradle Wrapper、AGP / Kotlin 版本；**不新增依赖**；
- `android/README.md`（收尾车道统一改）、根目录 `data/`（数据文件只读）。

需要一个骨架里没有的共用组件时，在自己的目录里写 `private` / `internal` 版本，不要去改 `Components.kt`。
多个车道需要的同一段逻辑（例如深夜遗物的诅咒逐行配对，增伤排名的自组遗物与存档检查都要用）各自在自己的包里实现，
并在报告里注明，收尾时再合并——并行车道之间不能互相依赖尚未合并的代码。

## 3. 占位页签名（固定）

```kotlin
@Composable
internal fun XxxScreen(
    catalog: AffixCatalog,       // 已加载的词条库（527 条），直接用，不要再读一次 JSON
    settings: UserSettings,      // 用户设置（只读）：defaultMode / autoInspect / selectorShowUnavailable / libraryCompact
    onBack: (() -> Unit)?,       // 词条反查为 null；四个子页非空，传给 GameDataScreenScaffold 即可
    modifier: Modifier = Modifier, // 已含状态栏与底栏的 Scaffold 内边距，必须加在页面根节点上
)
```

包名分别是 `com.nightreign.relicchecker.ui.lookup` / `.bosses` / `.heroes` / `.ranker` / `.save`，
函数名 `LookupScreen` / `BossesScreen` / `HeroesScreen` / `RankerScreen` / `SaveScreen`。签名、包名、
函数名都不能变，导航代码按它们调用。不需要设置的页面加 `@Suppress("UNUSED_PARAMETER")` 即可。

子页不需要自己处理「返回枢纽」：顶栏返回按钮与系统返回键都已接好。页内若有非抽屉式的下一级视图
（例如全屏详情），自己再注册 `BackHandler(enabled = detailOpen) { ... }`，它比枢纽的返回优先。

## 4. 数据加载

### 4.1 `:gamedata` 提供的东西

```kotlin
object GameDataFiles { BOSSES, SKILLS, BUFFS, HEROES, RELICS, all }   // 与 data/ 下文件名逐字一致

enum class GameDataKey(val fileName: String, val versionField: String, val expectedVersion: Int) {
    BOSSES("nightreign-bosses-v1.03.5.json", "bossesSchemaVersion", 4),
    SKILLS("nightreign-skills-v1.03.5.json", "schemaVersion", 2),
    BUFFS("nightreign-buffs-v1.03.5.json", "schemaVersion", 6),
    HEROES("nightreign-heroes-v1.03.5.json", "schemaVersion", 1),
    RELICS("nightreign-relics-v1.03.4.json", "relicsSchemaVersion", 1),
}

object GameDataJson {
    val lenient: Json      // ignoreUnknownKeys = true, isLenient = false, coerceInputValues = true
    inline fun <reified T> decode(key: GameDataKey, text: String): T   // 序列化错误包成带文件名的 GameDataFormatException
    fun requireVersion(key: GameDataKey, actual: Int?)                 // 版本不符即抛 GameDataFormatException
}

data class GameDataHeader(...)   // 顶层元数据：版本键、gameVersion、dataVersion、generatedAt
```

词条库仍由 `:catalog` 的 `CatalogLoader` 负责，已在应用启动时加载，通过参数 `catalog` 传入。

### 4.2 `:app` 提供的东西（`ui/gamedata/`）

```kotlin
sealed interface GameDataState<out T> { Loading; Ready(value: T); Failed(error: Throwable) }
fun <T, R> GameDataState<T>.map(transform: (T) -> R): GameDataState<R>
fun <A, B> GameDataState<A>.zip(other: GameDataState<B>): GameDataState<Pair<A, B>>

@Composable fun <T : Any> rememberGameData(key: GameDataKey, parserId: String, parse: (String) -> T): GameDataState<T>
@Composable fun rememberGameDataHeader(key: GameDataKey): GameDataState<GameDataHeader>
suspend fun <T : Any> GameDataRepository.get(assets, key, parserId, parse): Result<T>   // 非 Composable 场景

@Composable fun GameDataScreenScaffold(title, subtitle, onBack, modifier, statusPills, content: ColumnScope.() -> Unit)
@Composable fun <T> GameDataScreenScaffold(title, subtitle, onBack, state: GameDataState<T>, modifier, statusPills,
                                           loadingLabel = "载入游戏数据", content: ColumnScope.(T) -> Unit)
object GameDataLayout { Gutter = 16.dp; MaxContentWidth = 720.dp; SectionSpacing = 12.dp; fun listPadding(top, bottom) }
```

- `rememberGameData` 按 `GameDataKey + parserId` 做**进程级缓存**：同一数据被解析一次，旋转屏幕、切底栏、离开再进入页面都不重读；
  已解析过的数据同步返回 `Ready`，不会闪加载态。页面在解析途中离开，结果照样进缓存。
- `parse` 在 `Dispatchers.IO` 上执行，拿到的是整份 JSON 文本；解析失败（含版本不符）会显示在外壳的失败面板里，
  并提示「请确认 APK 由完整仓库构建」。失败结果同样缓存（asset 缺失或格式错误是确定性的）。
- **`parserId` 全应用唯一，且与 `parse` 的返回类型一一对应**（缓存按它取回后直接转型）。约定写成
  `"<页面>.<用途>.v<版本>"`，例如 `"bosses.page.v1"`、`"ranker.buffs.v1"`；DTO 结构变了就把版本号加一。
  同一个文件可以被不同页面用不同 `parserId` 各解析一份（例如词条反查与存档检查都读 `RELICS`）。
- 每次解析会打一行日志，`adb logcat -s GameData` 可以看到 `BOSSES#bosses.page.v1 ok in 1134 ms` 这样的耗时。

### 4.3 典型写法

`:gamedata` 里（纯 Kotlin，可单测）：

```kotlin
package com.nightreign.relicchecker.gamedata.bosses

@Serializable
internal data class BossesFileDto(
    val bossesSchemaVersion: Int? = null,
    val gameVersion: String = "",
    val dataVersion: String = "",
    val nightlords: List<NightlordDto> = emptyList(),
    val nightBosses: List<NightBossDto> = emptyList(),
    // 只声明页面要用的字段；diagnostics / notes / caveats 之类不声明，解码时自动跳过
)

data class BossesData(val bosses: List<BossEntry>, val byId: Map<Int, BossEntry>, /* 预先建好的索引 */)

object BossesParser {
    const val PARSER_ID = "bosses.page.v1"

    fun parse(text: String): BossesData {
        val dto = GameDataJson.decode<BossesFileDto>(GameDataKey.BOSSES, text)
        GameDataJson.requireVersion(GameDataKey.BOSSES, dto.bossesSchemaVersion)
        return BossesData(/* 把 DTO 转成页面直接可用的不可变模型，排序、分组、搜索键都在这里算好 */)
    }
}
```

`:app` 里（替换占位页）：

```kotlin
@Composable
internal fun BossesScreen(catalog: AffixCatalog, settings: UserSettings, onBack: (() -> Unit)?, modifier: Modifier = Modifier) {
    val state = rememberGameData(GameDataKey.BOSSES, BossesParser.PARSER_ID, BossesParser::parse)
    GameDataScreenScaffold(
        title = DataPage.BOSSES.title,
        subtitle = DataPage.BOSSES.eyebrow,
        onBack = onBack,
        state = state,
        modifier = modifier,
        statusPills = {
            NightPill("参数表 1.03.5", NightColors.TextMuted)
            (state as? GameDataState.Ready)?.let { NightPill("${it.value.bosses.size} 组", NightColors.PurpleSoft) }
        },
    ) { data ->
        var query by rememberSaveable { mutableStateOf("") }
        // 粘性工具条：放在 LazyColumn 外面
        NightSearchField(query, { query = it }, Modifier.padding(horizontal = GameDataLayout.Gutter), placeholder = "首领名称")
        val rows = remember(data, query) { data.bosses.filter { it.matches(query) } }
        LazyColumn(Modifier.fillMaxSize(), contentPadding = GameDataLayout.listPadding()) {
            items(rows, key = { it.id }, contentType = { "boss" }) { boss -> BossCard(boss) }
        }
    }
}
```

同时需要两个数据集时用 `zip`：

```kotlin
val skills = rememberGameData(GameDataKey.SKILLS, RankerParsers.SKILLS_ID, RankerParsers::skills)
val buffs = rememberGameData(GameDataKey.BUFFS, RankerParsers.BUFFS_ID, RankerParsers::buffs)
GameDataScreenScaffold(..., state = skills.zip(buffs)) { (skillData, buffData) -> ... }
```

外壳的 `content` **不带左右留白**，占满顶栏以下的全部高度；自己加留白用 `GameDataLayout.Gutter`，
列表用 `contentPadding = GameDataLayout.listPadding()`。宽屏时外壳已经限宽 720dp 并居中，页面不要再自己撑满超宽屏。

## 5. 共用组件（`ui/Components.kt`，包 `com.nightreign.relicchecker.ui`，均为 `internal`）

```kotlin
NightTopBar(title: String, eyebrow: String? = null, trailing: String? = null, modifier: Modifier = Modifier,
            onBack: (() -> Unit)? = null)               // trailing 显示为绿色带点小标签；onBack 非空时左侧为返回按钮
NightBackButton(onClick: () -> Unit, modifier: Modifier = Modifier, label: String = "返回")
SectionLabel(text: String, trailing: String? = null, modifier: Modifier = Modifier)   // 分区小标题 + 右侧灰色小字
NightPanel(modifier: Modifier = Modifier, borderColor: Color = NightColors.Border,
           shape: RoundedCornerShape = RoundedCornerShape(16.dp), content: @Composable BoxScope.() -> Unit)
           // 卡片；可点击时在 modifier 里写 .clip(shape).clickable { }，让水波纹不出圆角
NightPill(text: String, color: Color = NightColors.PurpleSoft, modifier: Modifier = Modifier, dot: Boolean = false)
NightSegmentedControl(items: List<String>, selectedIndex: Int, onSelect: (Int) -> Unit,
                      modifier: Modifier = Modifier, height: Dp = 40.dp)   // 等宽分段；手机上不超过 4 段短标签
NightSearchField(value: String, onValueChange: (String) -> Unit, modifier: Modifier = Modifier,
                 placeholder: String = "搜索词条")
AffixSummary(affix: Affix, modifier: Modifier = Modifier, compact: Boolean = false, showDescription: Boolean = true)
NightBottomSheet(onDismissRequest: () -> Unit, content: @Composable ColumnScope.() -> Unit)
           // 与词条库详情 / 检查页选择器同款的全展开底部抽屉
```

`ui/gamedata/` 另有 `GameDataLoadingView(label)`、`GameDataErrorView(error)`，页面内部需要局部加载态时可复用。

搜索：`:rules` 的 `Affix.matchesSearch(query)`（名称 / 别名 / 分类 / effectId，已处理大小写、全半角、重音、标点）
与 `String.foldedForSearch()`（给任意文本做同样的归一化，建议在解析阶段预先算好搜索键）。
合法性：`LegalityChecker().check(affixes, mode)`、`CheckMode`（四种口径，`eligiblePoolIds` / `slotPoolSequences`）。

### 色板 `NightColors`（`ui/theme/Theme.kt`）

| 名称 | 色值 | 用途 |
| --- | --- | --- |
| `BackgroundDeep` | `#07060C` | 最底层背景、抽屉遮罩 |
| `Background` | `#09080F` | 页面背景、粘性表头底色 |
| `Elevated` | `#12101B` | 底栏、底部抽屉 |
| `Card` / `CardHover` | `#15121F` / `#1A1627` | 卡片渐变起点 / 按下态 |
| `Field` / `FieldSoft` | `#0F0D17` / `#191522` | 输入框、分段控件底 / 次级按钮与筛选药丸 |
| `Border` / `BorderStrong` | `#2B2639` / `#3A3450` | 常规描边与分隔线 / 强调描边 |
| `TextPrimary` | `#F4F1FB` | 正文、标题 |
| `TextSecondary` | `#AAA3B8` | 说明文字 |
| `TextMuted` | `#736D80` | 注脚、出处、未选中 |
| `PurpleDeep` / `Purple` / `PurpleSoft` | `#7145D8` / `#8459E8` / `#B79AFF` | 主色：选中底 / 选中态与强调 / 数字、ID、链接 |
| `Green` | `#55D6A5` | 合法、离线、增益 |
| `Amber` | `#EEC16D` | 警告、需诅咒、推算值、未实测 |
| `Red` | `#ED6C7D` | 非法、负面词条、失败 |

字号（`MaterialTheme.typography`）：`headlineSmall` 20 / `titleLarge` 18 / `titleMedium` 16 / `bodyLarge` 14 /
`bodyMedium` 13 / `bodySmall` 12 / `labelLarge` 13 / `labelMedium` 12 / `labelSmall` 11（sp）。只用这套，不自定义字号。

## 6. 手机优先的布局约定

- **单列**：内容区一个 `LazyColumn`（`Modifier.fillMaxSize()` + `GameDataLayout.listPadding()`），不要在
  `verticalScroll` 里嵌 `LazyColumn`，也不要用 `verticalScroll` 渲染上百行。条目给稳定的 `key` 与 `contentType`。
- **选择器用底部抽屉**：选角色、选战技 / 武器、选遗物词条、选护符、筛选项多的面板一律用 `NightBottomSheet`；
  抽屉里的列表用 `LazyColumn(Modifier.heightIn(min = 300.dp, max = 590.dp))`，参考 `CheckerScreen.kt` 的 `AffixPicker`。
  抽屉开关状态用 `rememberSaveable` 存 id / 枚举名，不存对象。
- **粘性工具条**：搜索框、模式切换（常规 / 深夜、深度 1–5、人数）放在 `LazyColumn` 外面、内容区顶部；
  或用 `LazyColumn` 的 `stickyHeader`（背景填 `NightColors.Background`，避免透出下层文字）。
- **长表横向滚动**：角色属性 15 级 × 12 列、首领八系承伤倍率、深度 1–5 这类宽表，首列（名称 / 等级）固定，
  其余列放进 `Row(Modifier.horizontalScroll(scrollState))`，表头与各行**共用同一个 `ScrollState`** 同步横滚；
  数字右对齐、等宽数字（`fontFeatureSettings = "tnum"`）。
- **桌面端的双栏 / 侧栏**在手机上改为「列表 → 底部抽屉详情」或「列表 → 页内展开卡片」，不要做左右分栏。
- 触控目标不小于 48dp，整行可点优先；没有 hover，主要功能不依赖长按。
- 左右留白一律 16dp（`GameDataLayout.Gutter`），与检查 / 词条库页对齐；不要让内容贴屏幕边缘。
- 文案用简体中文与全角标点；倍率写 `×1.25`；大数加千分位；数值口径、「未实测 / 推算 / 参数推断」之类的标注与
  桌面端逐字一致，参考根 `README.md` 与 `macos/DataSources/PROVENANCE.md`，不要另起一套说法。
- 页内状态用 `rememberSaveable`（基本类型、String、枚举名、`ArrayList<Int>`；复杂状态写 `listSaver` / `mapSaver`），
  列表位置用 `rememberLazyListState()`，这样切底栏回来仍停在原处。

## 7. 性能约定

- 数据集体积：buffs 2.96 MB、bosses 1.59 MB、skills 1.56 MB、relics 0.41 MB、heroes 0.17 MB（全部随 APK 打包，
  debug APK 约 13 MB）。不要再往 APK 里加资源。
- **直接解码到 DTO**（`GameDataJson.decode<T>`），**不要**对整份文件 `parseToJsonElement`——那会建出整棵 JSON 树，
  内存是 DTO 的数倍。
- DTO 只声明页面用到的字段，所有字段给默认值（配合 `coerceInputValues`，个别行缺字段不会整份失败）；
  **不要声明** `diagnostics`、`schemaChangelog`、`notes`、`crossChecks`、`fieldNotes`、`sources`（除非页面要展示）等大块说明字段。
- 排序、分组、索引（`Map` by id）、搜索键、派生数值等**在 `parse` 里算好**（后台线程），Composable 里只做与交互相关的
  过滤：`remember(data, query, filter) { ... }`；上千行的重计算用 `produceState` 切到 `Dispatchers.Default`。
- 解析后的模型保持不可变（`val` + `List` / `Map`），在组合中按引用传递；Compose 编译器已开启 strong skipping，
  同一实例不会触发重组。
- 参考耗时（模拟器、debug 包，只解码顶层元数据）：relics 约 0.6 s、bosses 约 1.1 s、skills 约 0.5 s、buffs 约 0.6 s；
  首次安装后的第一次运行还会更慢。完整 DTO 会更久，用 `adb logcat -s GameData` 观察，超过 2 s 就要精简字段。

## 8. 测试与构建

```bash
cd android
export ANDROID_HOME=$HOME/Library/Android/sdk
export ANDROID_SDK_ROOT=$HOME/Library/Android/sdk
./gradlew testDebugUnitTest assembleDebug
```

- 根任务 `testDebugUnitTest` 会跑 `:rules:test`、`:catalog:test`、`:gamedata:test`、`:app:testDebugUnitTest`，必须全绿。
- `:gamedata` 的测试直接读仓库根 `data/`：`javaClass.classLoader.getResourceAsStream(GameDataKey.X.fileName)`。
  每个车道至少为自己的解析器写：版本校验、条目数等稳定事实（与根 README 的收录统计一致）、几条关键数值的抽样
  （与桌面端测试用例同值）。
- 口径以桌面端为准，移植前先读对应实现与测试：
  - 词条反查：`macos/Sources/RelicCore/AffixLookup.swift`、`RelicData.swift`，`windows/renderer/pages/lookup.js`，
    测试 `macos/Sources/RelicCoreChecks/AffixLookupChecks.swift`、`windows/tests/lookup_index.test.mjs`；
  - 首领数据：`RelicCore/BossData.swift`、`NightreignRelicChecker/BossData*.swift`，`pages/bosses.js`，
    测试 `BossDataChecks.swift`、`windows/tests/bosses*.test.mjs`；
  - 角色属性：`RelicCore/HeroData.swift`、`HeroStats*.swift`，`pages/heroes.js`，测试 `HeroStatsChecks.swift`、`heroes.test.mjs`；
  - 增伤排名：`RelicCore/BuffRanker.swift`、`BuffLoadout.swift`、`SkillData.swift`、`BuffRanker*.swift`，`pages/ranker.js`，
    测试 `BuffRankerChecks.swift`、`windows/tests/ranker*.test.mjs`；
  - 存档检查：`RelicCore/SaveFile.swift`、`SaveAudit.swift`、`RelicAudit.swift`、`SaveCompare.swift`、`SaveReport.swift`，
    Windows `savefile.go`、`renderer/savediff.js`、`renderer/savereport.js`，测试 `SaveCompareChecks.swift`、
    `windows/tests/core_audit.test.mjs`、`save_*.test.mjs`，对拍用例 `testdata/audit_cases.json`。
    Android 上用 Storage Access Framework（`rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument())`）只读打开，
    不申请存储权限、不声明 `INTERNET`；桌面端的「自动查找存档」「拖拽打开」在手机上不适用。
- UI 没有仪器测试；需要目测时可用本机模拟器：
  `$ANDROID_HOME/emulator/emulator -avd Medium_Phone_API_36.1 -no-window`，然后
  `adb install -r app/build/outputs/apk/debug/app-debug.apk`，`adb exec-out screencap -p > shot.png`。

## 9. 提交规则

- 提交信息用中文，说明改了什么、为什么；**不加 `Co-Authored-By` 或任何署名 / 生成工具行**。
- 只提交自己车道的文件；不要 push；不要改 `data/`。
