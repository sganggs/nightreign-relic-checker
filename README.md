# 夜幕验物（Nightreign Relic Checker）

《艾尔登法环 黑夜君临》三词条遗物的**完全离线**合法性检查器，界面参考原检查网站的深色三卡片布局。软件不会修改游戏存档，也不会连接游戏服务器。

> 本工具为非官方社区工具，与 FromSoftware、Bandai Namco Entertainment 及原参考网站无关；游戏名称与游戏内文本的权利归其各自权利方所有。

当前版本：**v0.1.2**。

## 下载

编译好的安装包在 [Releases](../../releases) 页面下载：

| 文件 | 说明 |
| --- | --- |
| `NightreignRelicChecker-Windows-x64-v0.1.2.exe` | **Windows 版**。约 3.8 MB，免安装，使用系统自带 Microsoft Edge WebView2 运行时。Windows 11 与新版 Windows 10 已内置该运行时；若缺失可[免费安装](https://developer.microsoft.com/microsoft-edge/webview2/)。 |
| `NightreignRelicChecker-macOS-Universal-v0.1.2.zip` | macOS 13+，Universal 2（Apple Silicon 与 Intel 均可运行）。 |

（GitHub Release 附件名不支持中文，故采用英文文件名。）

自定义词条库保存位置：Windows 为 `%LOCALAPPDATA%\NightreignRelicChecker\affixes.json`，macOS 为 `~/Library/Application Support/NightreignRelicChecker/affixes.json`。

> **Windows SmartScreen**：当前测试版未购买代码签名证书，SmartScreen 可能显示“未知发布者”。请先核对 Release 附带的 `SHA256SUMS.txt`；确认校验一致后，可选择“更多信息”→“仍要运行”。
>
> **macOS Gatekeeper**：当前版本采用本地临时签名，未做 Apple 公证。若首次打开被阻止，请在 Finder 中右键应用，选择“打开”。

## 仓库结构

| 目录 | 说明 |
| --- | --- |
| [`windows/`](windows/) | Windows 版：Go + WebView2 壳，对应 Windows EXE |
| [`macos/`](macos/) | macOS 版：Swift / SwiftUI |
| [`data/`](data/) | 各端共用的内置词条库 `nightreign-affixes-v1.03.4.json`，可从应用内“数据设置”重新导入 |

两个客户端共享同一套判定规则与内置词条库，仅界面容器不同。各目录内有独立的 README 与构建说明：

- **Windows 版**（Go 1.25+，纯 Go 构建）：`go build -trimpath -ldflags "-s -w -H windowsgui" -o 夜幕验物.exe`
- **macOS 版**（macOS 13+，Swift）：`swift run RelicCoreChecks && zsh Scripts/build_app.sh`

## 判定规则

默认“普通 1.03”模式严格检查当前 v1.03.4 + DLC 的 340 条可抽词条：

- 三条词条均须处于对应版本的非零权重池；
- `effectId` 不能重复；
- 非 `-1` 的 `compatibilityId` 不能重复；
- 最终顺序按 `(overrideEffectId, effectId)` 升序。

“普通旧池”对应 1.02 及更早 / 无 DLC 的 290 条可抽词条。随机普通遗物的红、蓝、黄、绿颜色不改变候选集合，因此无需选择颜色。

“深夜正面”会按游戏参数中的七种真实满三槽模板（AAA、AAB、ABB、BBB、AAC、ACC、CCC）预检；完整深夜遗物仍需结合具体遗物 ID、实际槽池模板与全部负面词条验证，软件会明确提示这一限制。

## 数据来源

- 游戏参数与简体中文 FMG：Elden Ring Nightreign Save Editor，修订 `0d2ad1494c372098e689c23159656df70ff2d76d`。
- 分类、说明与叠加性：NightreignQuickRef，修订 `3e23450094c18125ae5665927ed240b18189a040`。
- 参数语义交叉验证：Smithbox。
- 热门度：原检查站公开 API 的 2026-03-12 Wayback 快照，共恢复 19 条。

## 许可

整体以 [GNU GPL v3.0](LICENSE) 发布；具体第三方来源与许可见各目录内的 `THIRD_PARTY_NOTICES.md` 及词条库内的来源元数据。
