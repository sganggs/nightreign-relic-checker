# 夜幕验物（Windows 版 · WebView2）

《艾尔登法环 黑夜君临》三词条遗物的完全离线合法性检查器 —— Windows 版。

应用最初以 Electron 原型开发（该原型未随本仓库分发），本版**沿用了其全部界面与规则代码**：
`renderer/` 目录（index.html / app.js / core.js / styles.css）与内置词条库
`resources/affixes.json`。不同之处仅在容器：

- Electron 原型把整个 Chromium 打包进 EXE（约 89 MB）；
- 本版改用 Windows 10/11 系统自带的 **Microsoft Edge WebView2 运行时**
  渲染同一套页面（同为 Chromium 内核），EXE 只包含一个几 MB 的 Go 壳。

当前版本 **v0.3.0**（`main.go` 的 `appVersion` 与 `winres/winres.json` 为准）。

## 运行要求

- Windows 10/11 x64；
- Microsoft Edge WebView2 Runtime（Windows 11 与新版 Windows 10 已内置；
  如缺失可从 https://developer.microsoft.com/microsoft-edge/webview2/ 安装）。

自定义词条库保存在 `%LOCALAPPDATA%\NightreignRelicChecker\affixes.json`；
另外壳程序会在
`%LOCALAPPDATA%\NightreignRelicChecker\ui\` 与 `...\WebView2\` 下存放
界面文件副本与 WebView2 浏览器数据。界面副本按版本分目录（`ui\v0.3.0\`），
升级时旧版本目录会被自动清理，与版本无关的 `ui\resources\`（新页面数据）保留。

## 构建

需要 Go 1.25+（纯 Go 构建，无需 C 编译器）。资源文件（图标、版本信息、DPI
清单）已随源码提供为 `rsrc_windows_386.syso` / `rsrc_windows_amd64.syso`，
可离线直接构建：

```
go build -trimpath -ldflags "-s -w -H windowsgui" -o 夜幕验物.exe
```

交叉构建（在 macOS / Linux 上产出同一个 EXE）：

```
GOOS=windows GOARCH=amd64 go build -trimpath -ldflags "-s -w -H windowsgui" -o 夜幕验物.exe .
```

仅当修改图标或版本信息时，才需用 go-winres 重新生成上述 syso（改完
`winres/winres.json` 的版本号务必跑一次，否则 EXE 属性里还是旧版本号）：

```
go install github.com/tc-hib/go-winres@latest
go-winres make --arch 386,amd64
```

> `--arch` 不可省：它的默认值是 `amd64,386`，但会被环境变量 `$GOARCH` 覆盖
> （见 `go-winres make --help`）。在上面交叉编译那一节导出过 `GOARCH` 的 shell 里
> 直接跑 `go-winres make`，只会重写该架构的 syso，另一个架构仍留着旧版本号；
> 在 Apple Silicon 上跑 `go generate ./...`（`main.go` 里的 `//go:generate go-winres make`
> 走的正是这条命令）同样会被注入 `GOARCH=arm64`，只产出 `rsrc_windows_arm64.syso`。
> 显式写 `--arch 386,amd64`（或先 `unset GOARCH`）可避免这个坑；本仓库不分发
> Windows on ARM 构建，误生成的 `rsrc_windows_arm64.syso` 不入库，删掉即可。

## 测试

审计核心（JS）与四个新页面的纯计算层测试，任意平台可跑（无依赖，用 node 自带的
测试运行器）：

```
node --test tests/*.test.mjs
```

当前覆盖 `tests/` 下十一个文件：

- 存档页：`core_audit`（存档审计规则，用例取自仓库根 `testdata/`，与 macOS 端对拍）、
  `save_report` / `save_diff`（报告导出与存档对比，口径与 macOS 端 `SaveReport.swift` /
  `SaveCompare.swift` 逐行一致）；
- 首领数据：`bosses`（数值口径、代表行与收录统计）、`bosses_roles`（按出场场合分组的专项：
  默认六组与两个默认隐藏的分组、多重归属、代表行按分组过滤、逐行场合与出处）、
  `bosses_parity`（直接读仓库内 macOS 的 `BossData.swift` 与 `BossDataChecks.swift`，
  文案表逐项比对、macOS 自检钉住的对照表逐条拿来跑本端实现）；
- 角色属性：`heroes`（逐级插值、转职遗物叠加与钳位、利普拉的交易与同级对比，与 macOS 端
  `HeroStatsChecks.swift` 共用一组对照用例）；
- 词条反查：`lookup_index`；
- 增伤排名：`ranker`（纯计算层单元测试）、`ranker_config`（「自己组一套配置」的整套口径：
  槽位与深夜专属上限、互斥键去重、遗物合法性与深夜诅咒配对、appliesTo 分流、叠层换算、
  汇总连乘、按推荐填满不越界）、`ranker_crosscheck`（与 macOS 端
  `BuffRankerChecks.swift` 的 `checkLoadoutParity` 同一组输入、同一套断言口径，含三组固定
  配置对照与文案表摘要）。

两端的数据契约断言要一起改：`bosses.test.mjs` / `bosses_roles.test.mjs` 钉着
`bossesSchemaVersion` 4 与收录统计（夜王 18 · 守夜首领 40 · 据点首领 51 · 场景头目 35 ·
封印监牢 10 · 其它场合 45 · 随从/召唤物 11 · 未放置 93，含 49 组同时属于多个分组 ·
数值行 394），`ranker.test.mjs` 要求 buffs `schemaVersion` ≥ 6、skills `schemaVersion` 2，
重新生成数据集时必须同步。

存档解析器（Go 子包，无平台约束）：

```
go test ./internal/savefile/
```

静态检查（交叉平台）与主包全部测试（后者依赖 `golang.org/x/sys/windows`，
需在 Windows 环境运行）：

```
GOOS=windows go vet ./...
go test ./...
```

页面改动建议在浏览器里实际点验：`renderer/` 是纯静态目录，用任意静态 HTTP
服务打开 `index.html` 即可（`file://` 下 `fetch` 被 Chromium 拦截，必须走
HTTP；预览模式会从 `../resources/<name>.json` 回退读取数据）。

## 数据

内置数据在 `resources/`，由 `go:embed` 打进 EXE，**不要手工复制**：仓库根的
`data/` 是唯一权威来源，换数据时在仓库根运行

```
zsh scripts/sync-data.sh
```

把 `data/nightreign-<名字>-v<版本>.json` 同步成 `windows/resources/<名字>.json`
（affixes、relics、bosses、skills、buffs、heroes 六项），两端同时覆盖，代码无需改动。
六个源文件现已全部就位，`resources/heroes.json` 与 `data/nightreign-heroes-v1.03.5.json`
的 sha256 一致。

`resources/bosses.json`、`skills.json`、`buffs.json`、`heroes.json` 的生成管线在
[`../macos/DataSources/`](../macos/DataSources/PROVENANCE.md)（`dump_regulation.py` /
`extract_msg.py` / `extract_msb.py`（首领出场场合用的地图敌人放置）/ `generate_*.py`，需要本机游戏本体；Oodle 解压器的构建与调用
见 [`../macos/DataSources/tools/oodledec/README.md`](../macos/DataSources/tools/oodledec/README.md)）。
数据集的来源、字段映射与已知局限见同目录的 `PROVENANCE.md`。

## 结构

- `main.go` — 入口：展开内嵌 renderer 与数据、创建窗口、注册桥接、进入消息循环；
  `appVersion` 决定 `ui\v<版本>\` 目录名与旧版本清理（`pruneOldUIVersions` 保留
  `ui\resources\`）。
- `window.go` — WebView2 壳窗口（基于 jchv/go-webview2 的 MIT 代码定制：
  加载完成前隐藏窗口、深色背景、绑定函数在后台 goroutine 运行、
  禁用右键菜单 / DevTools / 浏览器快捷键 / 缩放 / 自动填充、拒绝权限请求）。
- `bindings.go` — `window.nightreign` 桥：loadCatalog / importCatalog /
  saveCustomCatalog / resetCatalog / exportCatalog / openSaveFile /
  locateSaveFiles / openLocatedSave / parseSaveData / exportText /
  loadRelicData / loadGameData（含取消返回值与统一的错误文案）。
- `internal/savefile` — 存档只读解析器（BND4 容器、AES-128-CBC 解密、
  遗物记录提取；无平台约束，任意平台可测）；`savefile.go` 为主包薄封装。
- `catalog.go` — 词条库读写：原子写入（临时文件 + 重命名）与统一的校验、
  错误消息。
- `internal/w32` — 所需的少量 Win32 绑定（自 jchv/go-webview2 内部包 fork）。
- `renderer/` — 界面：`index.html` / `app.js` / `core.js`（规则与审计）/
  `styles.css`，以及存档页的 `savereport.js`（报告与 CSV 导出）与
  `savediff.js`（存档对比）。
- `renderer/pages/` — 四个新页面（导航位置：词条反查紧跟「词条检查」；首领数据 → 角色属性 → 增伤排名
  排在「存档检查」之后、「数据设置」之前；主导航顺序以 `index.html` 的 `.main-nav` 为准）各自的
  `<key>.js` 与 `<key>.css`。**页面模块契约见 [`renderer/pages/README.md`](renderer/pages/README.md)**：
  注册方式、`ctx` 的内容、`ctx.getGameData` 的语义、样式与 CSP 约束都在那里，
  功能开发只改这两个文件，不必动 `index.html` / `app.js` / `main.go`。其中「首领数据」按出场场合分组
  （`bossesSchemaVersion` 4 的 `roles`），规则与文案表照抄 macOS 端 `RelicCore/BossData.swift`；
  「增伤排名」是「自己组一套局内配置」（常规 / 深夜、局内武器词条、遗物、护符、其它增益、汇总），
  口径与 macOS 端 `RelicCore/BuffLoadout.swift` 相同，配置部分的文案集中在 `ranker.js` 的 `TEXT`
  常量表，与 macOS 端 `LoadoutText.table` 按点号路径逐键同文。
- `resources/affixes.json`、`relics.json`、`bosses.json`、`skills.json`、
  `buffs.json`、`heroes.json`、`build/icon.ico` — 内置词条库、遗物物品表与四套游戏数据集
  （全部由 `go:embed` 内嵌，经 `window.nightreign.loadGameData(name)` 桥交给渲染层）
  与图标。**这些文件不能删**（`go:embed` 要求文件存在）；内容统一由
  `scripts/sync-data.sh` 覆盖。
- `cmd/dumpsave` — 排障用的存档转储小工具。
- `winres/winres.json` — 图标、版本信息与 per-monitor v2 DPI 清单。

## 调试

设置环境变量 `NIGHTREIGN_DEBUG=1` 后启动，可启用右键菜单与 DevTools。

## 与 Electron 原型的行为一致性（历史设计说明）

本版开发时曾与 Electron 原型逐项对照评审（该原型未随本仓库分发，以下内容作为设计备忘保留）。经评审确认、判定为可接受的**已知细微差异**：

- **容器层导航硬化**：Electron 用 `will-navigate` / `setWindowOpenHandler` 阻断顶层导航与新窗口。本版通过三重措施达到等效防护：注入脚本仅在文档为本应用 `index.html` 时才暴露 `window.nightreign`（等价 Electron 的 `assertTrustedIpcSender`），`index.html` 的严格 CSP（`script-src 'self'`，无 `unsafe-inline`/`eval`），以及冻结、无任何外链/导航入口的 renderer。未在容器层注册 `NavigationStarting` / `NewWindowRequested`（需 fork 上游 WebView2 绑定），因当前 renderer 下不可达，故未实现。
- **appDataDir 回退分支**：`%LOCALAPPDATA%` 未设置时的回退路径与 Electron 的 `userData` 布局略有不同。Windows 上 `%LOCALAPPDATA%` 恒有值，此分支为实际死代码，主路径与 Electron 逐字节一致。

导入/导出/校验的词条库文件、错误提示文案、五个 IPC 方法的返回值形状在开发期间均与 Electron 原型逐项核验一致（含导出文件与源库的 SHA-256 对照）。

## 许可

整体以 GNU GPL v3.0 发布（见 `LICENSE`）；第三方组件见
`THIRD_PARTY_NOTICES.md`。
