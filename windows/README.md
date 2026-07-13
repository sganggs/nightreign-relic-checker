# 夜幕验物（Windows 版 · WebView2）

《艾尔登法环 黑夜君临》三词条遗物的完全离线合法性检查器 —— Windows 版。

应用最初以 Electron 原型开发（该原型未随本仓库分发），本版**沿用了其全部界面与规则代码**：
`renderer/` 目录（index.html / app.js / core.js / styles.css）与内置词条库
`resources/affixes.json`。不同之处仅在容器：

- Electron 原型把整个 Chromium 打包进 EXE（约 89 MB）；
- 本版改用 Windows 10/11 系统自带的 **Microsoft Edge WebView2 运行时**
  渲染同一套页面（同为 Chromium 内核），EXE 只包含一个几 MB 的 Go 壳。

## 运行要求

- Windows 10/11 x64；
- Microsoft Edge WebView2 Runtime（Windows 11 与新版 Windows 10 已内置；
  如缺失可从 https://developer.microsoft.com/microsoft-edge/webview2/ 安装）。

自定义词条库保存在 `%LOCALAPPDATA%\NightreignRelicChecker\affixes.json`；
另外壳程序会在
`%LOCALAPPDATA%\NightreignRelicChecker\ui\` 与 `...\WebView2\` 下存放
界面文件副本与 WebView2 浏览器数据。

## 构建

需要 Go 1.25+（纯 Go 构建，无需 C 编译器）。资源文件（图标、版本信息、DPI
清单）已随源码提供为 `rsrc_windows_386.syso` / `rsrc_windows_amd64.syso`，
可离线直接构建：

```
go build -trimpath -ldflags "-s -w -H windowsgui" -o 夜幕验物.exe
```

仅当修改图标或版本信息时，才需用 go-winres 重新生成上述 syso：

```
go install github.com/tc-hib/go-winres@latest
go generate ./...
```

运行测试（依赖 `golang.org/x/sys/windows`，需在 Windows 环境运行）：

```
go test ./...
```

## 结构

- `main.go` — 入口：展开内嵌 renderer、创建窗口、注册桥接、进入消息循环。
- `window.go` — WebView2 壳窗口（基于 jchv/go-webview2 的 MIT 代码定制：
  加载完成前隐藏窗口、深色背景、绑定函数在后台 goroutine 运行、
  禁用右键菜单 / DevTools / 浏览器快捷键 / 缩放 / 自动填充、拒绝权限请求）。
- `bindings.go` — `window.nightreign` 桥：loadCatalog / importCatalog /
  saveCustomCatalog / resetCatalog / exportCatalog（含取消返回值与统一的
  错误文案）。
- `catalog.go` — 词条库读写：原子写入（临时文件 + 重命名）与统一的校验、
  错误消息。
- `internal/w32` — 所需的少量 Win32 绑定（自 jchv/go-webview2 内部包 fork）。
- `renderer/`、`resources/affixes.json`、`build/icon.ico` — 界面、内置词条库与图标。
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
