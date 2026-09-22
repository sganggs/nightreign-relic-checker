# 夜幕验物（Nightreign Relic Checker）

《艾尔登法环 黑夜君临》三词条遗物的**完全离线**合法性检查器，界面参考原检查网站的深色三卡片布局。软件不会修改游戏存档，也不会连接游戏服务器。

> 本工具为非官方社区工具，与 FromSoftware、Bandai Namco Entertainment 及原参考网站无关；游戏名称与游戏内文本的权利归其各自权利方所有。

当前版本：**v0.3.0**（桌面双端新增「首领数据」「词条反查」「增伤排名」三页，存档检查新增自动查找、拖拽打开、导出报告与存档对比）。Android 手机版本轮**没有新功能**，仍是 v0.2.1。

## 下载

编译好的安装包在 [Releases](../../releases) 页面下载：

| 文件 | 说明 |
| --- | --- |
| `NightreignRelicChecker-Windows-x64-v0.3.0.exe` | **Windows 版**。约 8 MB，免安装，使用系统自带 Microsoft Edge WebView2 运行时。Windows 11 与新版 Windows 10 已内置该运行时；若缺失可[免费安装](https://developer.microsoft.com/microsoft-edge/webview2/)。 |
| `NightreignRelicChecker-macOS-Universal-v0.3.0.zip` | macOS 13+，Universal 2（Apple Silicon 与 Intel 均可运行），约 5 MB。 |
| `NightreignRelicChecker-Android-v0.2.1.apk` | Android 8.0+ 手机版：三词条手动检查与词条库（暂无存档检查），自签名安装包。**v0.3.0 未更新手机版**，此附件仍是 v0.2.1，桌面端本轮新增的三页与存档检查增强都不在其中。 |

（GitHub Release 附件名不支持中文，故采用英文文件名。）

体积变大的主因是内置了三套新的游戏数据集（约 3.5 MB 未压缩 JSON），不是代码膨胀。

自定义词条库保存位置：Windows 为 `%LOCALAPPDATA%\NightreignRelicChecker\affixes.json`，macOS 为 `~/Library/Application Support/NightreignRelicChecker/affixes.json`。

> **Windows SmartScreen**：当前测试版未购买代码签名证书，SmartScreen 可能显示“未知发布者”。请先核对 Release 附带的 `SHA256SUMS.txt`；确认校验一致后，可选择“更多信息”→“仍要运行”。
>
> **macOS Gatekeeper**：当前版本采用本地临时签名，未做 Apple 公证。若首次打开被阻止，请在 Finder 中右键应用，选择“打开”。

## 功能

桌面双端共七页，行为与数据完全一致；所有计算都在本机完成，不联网、不写入游戏存档。

### 词条检查

手动填入三条词条，按所选口径判定这件遗物能不能由游戏正常生成，并给出正确的保存顺序。四种口径：普通 1.03（当前池）、普通旧池（1.02 及更早 / 无 DLC）、深夜正面、顺序/互斥。可搜索全库、一键填入热门词条或生成一组合法随机组合。判定规则见下面的[判定规则](#判定规则)一节。

### 词条库

离线浏览全部 527 条词条：按名称、别名、分类、`effectId` 搜索，按口径过滤，查看分类、效果说明与叠加性。说明与分类来自 NightreignQuickRef，不覆盖游戏参数字段。

### 存档检查

选择或拖入 `.sl2` / `.co2` 存档，在本地解密并解析全部角色槽的全部遗物，逐件给出合法性报告——**只读、离线**，不上传、不修改存档。v0.3.0 新增四项：

- **自动查找存档**：直接扫描系统默认存档目录，列出找到的存档供选择，不必手动翻目录。Windows 扫 `%APPDATA%\Nightreign\<SteamID>\`；macOS 上游戏跑在 CrossOver / Wine 里，扫的是 `~/Library/Application Support/CrossOver/Bottles/<bottle>/drive_c/users/<用户名>/AppData/Roaming/Nightreign/<SteamID>/`（结果按 bottle 名与账户名标注），不在 CrossOver bottle 里的存档仍需手动选择或拖入。
- **拖拽打开**：把 `.sl2` / `.co2` 拖到本页任意位置即可解析。
- **导出报告**：把当前检查结果导出为可留档的文本报告或 CSV（文件名形如 `夜幕验物-存档报告-<存档名>-<时间戳>`）。
- **存档对比**：与另一份存档逐件对比，列出新增、消失与被改动的遗物，便于确认某次改动到底动了什么。
- 另外，遗物卡片上带说明的词条名后面会出现 ⓘ，可展开该条词条的完整说明（与词条库页同一份文案）。

逐件校验的具体项目见下面的[存档检查的校验项](#存档检查的校验项)。

### 首领数据（v0.3.0 新增）

18 个夜王条目与 117 个守夜 / 野外 Boss 的战斗数值：血量、削韧槽与恢复、八种伤害的承伤倍率、七项异常抗性与免疫、官方弱点标注，以及双人 / 三人的人数缩放。血量已经含常驻威胁档位缩放：绝大多数行只看参数里的 `NpcParam.hp` 会低估（夜王主战行约 3.5～5.5 倍，个别行可达 13 倍），少数常驻缩放 < 1 的行则相反，是高估。**普通 / 永夜之王 / 救世旗手** 三种形态分别列出（`variantKey`）；「深夜」不是第四种形态，而是同一条目的另一组数值，用页面顶部的「深夜数值」开关切换（`fights[].deepOfNight`，没有深夜专属缩放的行回落到常规值）。

**口径与局限**：`damageRates` 是承伤倍率不是减伤率（1.35 = 多受 35%）；有效韧性要按 `poise / (poiseTakenBase × 人数档位 poiseTaken)` 算；菜单上的官方弱点与实际承伤倍率**不总是一致**（史柴格斯标注「无弱点」但圣属性倍率 1.25），页面两者并列展示；人数缩放来自参数表的 `MultiPlayCorrectionParam` → `SpEffectParam` 链路，不是实测；数据集只描述数值，不含招式、行为与掉落。

### 词条反查（v0.3.0 新增）

从词条出发反查出处：某条词条能出现在哪些遗物、哪些槽位层、哪种颜色上，深夜遗物的 A/B/C 池与诅咒池归属，以及与它互斥（同 `compatibilityId`）的词条有哪些。只用已有的词条库与遗物物品表，不引入新数据。

**口径与局限**：出处按参数表里的槽池模板推出，槽位层标的是「N 孔层」而不是「第 N 槽」（3 孔遗物的第 1 个槽用的是 3 孔层池）；能不能真的抽到还取决于权重，本页只回答「在不在候选集合里」。

### 增伤排名（v0.3.0 新增）

选一把武器 + 一个战技 / 法术，页面按参数表解出这一招的实际命中分段与伤害构成（斩 / 打 / 突 / 标准 / 魔力 / 火 / 雷 / 圣的占比），再把全部增伤手段按对这一招的**有效倍率**排名，并给出理论上可以叠加的组合。

**口径与局限**：这是**相对构成**，不是绝对伤害——不含强化等级、能力值补正与 `AttackElementCorrectParam`，跨武器的数值不可直接比大小。增伤倍率的取舍（哪些默认计入、哪些要勾选情境）照数据集自带的排名说明实现：只有 `activation="passive"` 且没有作用情境限制的条目才默认相乘，残血 / 双手持 / 叠层 / 致命一击 / 突刺反击之类要用户自己勾。**叠加关系是按参数结构（`spCategory` / `categoryPriority` / `saveCategory` / `stateInfo`）推断的，没有经过木桩实测**，请当作参数层面的默认规则而不是实战结论。

### 数据设置

查看内置数据的版本、来源与记录数，导入 / 导出离线 JSON 词条库，或恢复内置词条库。

> **三页共同的数值口径**：所有数值取自本机导出的游戏参数表（regulation 1.03.5），**不是游戏内实测**；参数表与实际表现不一致的已知点都写在各数据集的 `caveats` 字段与 [`macos/DataSources/PROVENANCE.md`](macos/DataSources/PROVENANCE.md) 里，页面也会就地提示。

## 仓库结构

| 目录 | 说明 |
| --- | --- |
| [`windows/`](windows/) | Windows 版：Go + WebView2 壳，对应 Windows EXE；三个新页面在 [`windows/renderer/pages/`](windows/renderer/pages/README.md) |
| [`macos/`](macos/) | macOS 版：Swift / SwiftUI（`RelicCore` 纯逻辑 + `NightreignRelicChecker` 界面 + `RelicCoreChecks` 自检） |
| [`macos/DataSources/`](macos/DataSources/PROVENANCE.md) | 数据导出与生成管线：`dump_regulation.py`（regulation.bin → 每表一个 CSV）、`extract_msg.py`（游戏归档 → 每个 FMG 一个 JSON）、`tools/oodledec`（借游戏自带 Oodle DLL 解 KRAK 压缩）、五个 `generate_*.py`；**需要本机已安装的游戏本体与 CrossOver / Wine**，产物 `raw/` 不入库。来源、字段映射与已知局限见 `PROVENANCE.md` |
| [`android/`](android/) | Android 手机版：Kotlin / Jetpack Compose / Material 3；手动验物、词条库与离线说明。**v0.3.0 未更新**，仍是 v0.2.1 |
| [`data/`](data/) | 各端共用的权威数据集：词条库 `nightreign-affixes-v1.03.4.json`、遗物物品表 `nightreign-relics-v1.03.4.json`（存档检查用）、首领数据 `nightreign-bosses-v1.03.5.json`、战技/法术/武器 `nightreign-skills-v1.03.5.json`、增伤手段 `nightreign-buffs-v1.03.5.json` |
| [`scripts/`](scripts/) | 跨端脚本；[`sync-data.sh`](scripts/sync-data.sh) 把 `data/` 下的权威 JSON 同步到两端的内置资源目录 |
| [`testdata/`](testdata/) | 两端校验器共用的对拍用例 |

### 同步内置数据

`data/` 下的文件名带版本号，两端内置资源的文件名不带版本号。换数据时不要手动复制，运行：

```sh
zsh scripts/sync-data.sh
```

脚本把 `data/nightreign-<名字>-v<版本>.json` 复制成 `windows/resources/<名字>.json` 与
`macos/Sources/NightreignRelicChecker/Resources/<名字>.json`（当前映射：affixes、relics、
bosses、skills、buffs、heroes 六项）。源文件不存在时跳过并提示；换版本号只需改脚本里的映射表。
复制前会用 python3 校验源文件是合法 JSON，坏文件不会污染两端资源目录。

其中 `heroes`（角色属性，建设中）的源文件 `data/nightreign-heroes-v1.03.5.json` 还没生成，
脚本会跳过它，两端 `heroes.json` 暂时是占位 JSON（`{"placeholder": true}`），桌面双端的
「角色属性」页显示“数据未内置”，不影响现有功能与构建。

三个客户端共享同一套判定规则与内置词条库，仅界面容器不同。各目录内有独立的 README 与构建说明：

- **Windows 版**（Go 1.25+，纯 Go 构建）：`go build -trimpath -ldflags "-s -w -H windowsgui" -o 夜幕验物.exe`
- **macOS 版**（macOS 13+，Swift）：`swift build && swift run RelicCoreChecks && zsh Scripts/build_app.sh`（`swift build` 不能省——应用资源包没构建过时，`GameDataLoader 能定位已构建的资源包` 那一组会跳过，自检总数少 4 项；顺序见 [`macos/README.md`](macos/README.md)）
- **Android 版**（JDK 17 + Android SDK 36）：在 `android/` 运行 `./gradlew testDebugUnitTest assembleDebug`

Android 版专注手机化的三词条检查与词条库，尚未移植桌面端 `.sl2/.co2` 存档解析，也没有本轮新增的三页；详细边界见 [`android/README.md`](android/README.md)。

## 判定规则

默认“普通 1.03”模式严格检查当前 v1.03.4 + DLC 的 340 条可抽词条：

- 三条词条均须处于对应版本的非零权重池；
- `effectId` 不能重复；
- 非 `-1` 的 `compatibilityId` 不能重复；
- 最终顺序按 `(overrideEffectId, effectId)` 升序。

“普通旧池”对应 1.02 及更早 / 无 DLC 的 290 条可抽词条。随机普通遗物的红、蓝、黄、绿颜色不改变候选集合，因此无需选择颜色。

“深夜正面”会按游戏参数中的七种真实满三槽模板（AAA、AAB、ABB、BBB、AAC、ACC、CCC）预检；完整深夜遗物的逐件校验请使用「存档检查」。

## 存档检查的校验项

在「存档检查」页选择或拖入游戏存档（`NR0000.sl2` / 无缝联机 `.co2`，PC 默认位于 `C:\Users\<用户名>\AppData\Roaming\Nightreign\<SteamID>\`），软件在本地解密并解析全部角色槽的全部遗物，逐件给出合法性报告——**完全离线、只读**，不上传任何数据，也不会修改存档。

对每件遗物逐项校验：

- 遗物 ID 合法范围与作弊器常用 ID 区段；
- `effectId` 查重、互斥词条（`compatibilityId`）查重、正面词条保存顺序（按 `(overrideEffectId, effectId)` 升序）；
- **深夜遗物正负词条按行配对**：第 i 条正面词条为「需诅咒」词条（A 池）⇔ 第 i 条负面词条存在；不需诅咒的正面词条不得带负面词条；负面词条须在诅咒池内；词条数须等于该遗物的槽数（该模型经真实存档 759 件深夜遗物零违反实证；参数表中深夜遗物行的槽池排列与游戏实际生成不符，不作为校验依据）；
- 普通遗物按参数行槽池模板校验词条归属；唯一遗物（BOSS/事件遗物）按其单词条固定池核验固定词条（经真实存档交叉验证，参数表对唯一遗物的记录是准确的），词条被修改即判非法；
- 唯一遗物重复持有检查（只统计物品条目区实际引用的遗物；已删除遗物在存档中的残留记录会被过滤，不会造成误报）。

非法遗物会标出名称、种类（深夜/唯一/商店/对局奖励）、颜色与全部正负词条，并说明具体原因。Windows 与 macOS 两端校验器由同一份用例对拍，行为一致。

## 数据来源

- **游戏参数表与简体中文文本（v0.3.0 新增的三套数据集）**：本机已安装游戏的 `regulation.bin` 与 msg 归档，容器版本号 `10350000`（即 **regulation 1.03.5**，exe 1.3.3.0），由 `macos/DataSources/` 下的 `dump_regulation.py` / `extract_msg.py` 在本机导出；原始产物受游戏权利方权利约束，不入库。
- **Smithbox Paramdex（NR）**：`vawser/Smithbox@f5969c060cea240476e9dd4d6a64eafa9dbafaab`，MIT。提供 paramdef（字段布局与版本感知过滤）、英文参数行名与若干枚举（`WEP_TYPE`、`RARITY`、`ATK_SUB_CATEGORY`、`SP_EFFECT_TYPE`、`EFFECTIVE_AFFINITY` 等）。早期还用其 Nightreign 注释确认 `compatibilityId` 的参数语义（修订 `b1b644a770f8cc4c8cab452da3a72ff7b91e105a`）。
- **归档解包所用的公开密钥**：`.bhd` 的 RSA 公钥与 regulation 的 AES 密钥取自 UXM / BinderTool / Smithbox 等公开工具长期公布的常量（`Keys.NightreignKeys`、`Keys.NR_REGULATION_KEY`）；本仓库不分发游戏文件，也不包含任何绕过反作弊的代码。
- **Elden Ring Nightreign Save Editor**：修订 `0d2ad1494c372098e689c23159656df70ff2d76d`，MIT。词条库与遗物物品表的参数来源、官方简中 FMG，以及存档格式（BND4 / AES-CBC / 遗物记录布局）的解析依据。
- **NightreignQuickRef**：修订 `3e23450094c18125ae5665927ed240b18189a040`，GPL-3.0。词条的中文分类、效果说明、叠加性与别名。
- **热门度**：原检查站公开 API 的 2026-03-12 Wayback 快照，共恢复 19 条。

每套数据集的完整来源表、字段映射、推断部分与已知局限见 [`macos/DataSources/PROVENANCE.md`](macos/DataSources/PROVENANCE.md)；各端的第三方许可见 `windows/THIRD_PARTY_NOTICES.md`、`macos/THIRD_PARTY_NOTICES.md` 与 `android/THIRD_PARTY_NOTICES.md`。

## 许可

整体以 [GNU GPL v3.0](LICENSE) 发布；具体第三方来源与许可见各目录内的 `THIRD_PARTY_NOTICES.md` 及词条库内的来源元数据。
