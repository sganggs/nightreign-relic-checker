# 夜幕验物（Nightreign Relic Checker）

《艾尔登法环 黑夜君临》三词条遗物的**完全离线**合法性检查器，界面参考原检查网站的深色三卡片布局。软件不会修改游戏存档，也不会连接游戏服务器。

> 本工具为非官方社区工具，与 FromSoftware、Bandai Namco Entertainment 及原参考网站无关；游戏名称与游戏内文本的权利归其各自权利方所有。

当前版本：**v0.3.0**（桌面双端新增「首领数据」「角色属性」「词条反查」「增伤排名」四页，存档检查新增自动查找、拖拽打开、导出报告与存档对比；首领数据换成了重新核验过的第二版数据集）。Android 手机版本轮**没有新功能**，仍是 v0.2.1。

## 下载

编译好的安装包在 [Releases](../../releases) 页面下载：

| 文件 | 说明 |
| --- | --- |
| `NightreignRelicChecker-Windows-x64-v0.3.0.exe` | **Windows 版**。约 8 MB，免安装，使用系统自带 Microsoft Edge WebView2 运行时。Windows 11 与新版 Windows 10 已内置该运行时；若缺失可[免费安装](https://developer.microsoft.com/microsoft-edge/webview2/)。 |
| `NightreignRelicChecker-macOS-Universal-v0.3.0.zip` | macOS 13+，Universal 2（Apple Silicon 与 Intel 均可运行），约 5 MB。 |
| `NightreignRelicChecker-Android-v0.2.1.apk` | Android 8.0+ 手机版：三词条手动检查与词条库（暂无存档检查），自签名安装包。**v0.3.0 未更新手机版**，此附件仍是 v0.2.1，桌面端本轮新增的四页与存档检查增强都不在其中。 |

（GitHub Release 附件名不支持中文，故采用英文文件名。）

体积变大的主因是内置了四套新的游戏数据集（约 4.5 MB 未压缩 JSON），不是代码膨胀。

自定义词条库保存位置：Windows 为 `%LOCALAPPDATA%\NightreignRelicChecker\affixes.json`，macOS 为 `~/Library/Application Support/NightreignRelicChecker/affixes.json`。

> **Windows SmartScreen**：当前测试版未购买代码签名证书，SmartScreen 可能显示“未知发布者”。请先核对 Release 附带的 `SHA256SUMS.txt`；确认校验一致后，可选择“更多信息”→“仍要运行”。
>
> **macOS Gatekeeper**：当前版本采用本地临时签名，未做 Apple 公证。若首次打开被阻止，请在 Finder 中右键应用，选择“打开”。

## 功能

桌面双端共八页，行为与数据完全一致；所有计算都在本机完成，不联网、不写入游戏存档。

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

18 个夜王条目与 116 个守夜 / 野外 Boss 的战斗数值：血量、削韧槽与恢复、八种伤害的承伤倍率、七项异常抗性与免疫、官方弱点标注，以及双人 / 三人的人数缩放（收录统计：夜王 18 · 守夜 50 · 野外 72，含 6 组两种档位都出现 · 数值行 394）。血量已经含常驻威胁档位缩放：绝大多数行只看参数里的 `NpcParam.hp` 会低估（夜王主战行约 3.5～5.5 倍，个别行可达 13 倍），少数常驻缩放 < 1 的行则相反，是高估。**普通 / 永夜之王 / 救世旗手** 三种形态分别列出（`variantKey`）；「深夜」不是第四种形态，而是同一条目的另一组数值，用页面顶部的模式选择在常规与「深夜·深度 1–5」之间切换（深度数值取自 `fights[].depthStats`，并可再叠加变异个体档位；少数带永夜/DLC 深夜专属修正的行会标出「深夜专属修正」）。

**名字口径（第二版起）**：简中名**只**按本作的游戏文本对照（`item/NpcName`、`menu/CL_MenuText`，每条都带 `nameEvidence` 记录 FMG 文件与文本 ID），游戏文本里没有的一律显示英文名。上一版按《艾尔登法环》官方简中手工补的 14 条译名已全部移出 `nameZh`，改挂 `nameZhFallback` 并声明**「参考译名·非本作游戏文本」**；显示名的回退顺序是 `nameZh` → `nameZhFallback`（标注非本作文本）→ `displayFallbackZh`（只有两条实在认不出的「未知敌人 cXXXX」）→ `nameEn`。借社区敌人名录，原本只能显示「未知敌人」的 5 个 chrId 已认出 4 组：古龙桂奥尔（c4504）、挖石山妖（c4603）、百足恶魔幼虫（c7711 / c7712）、无名王者的坐骑（c7910）——其中只有挖石山妖在游戏文本里有对应的简中词条，其余按上面的口径显示英文名。另有 4 组明显不是「首领」的实体（整组不掉任何奖励，且是不吃削韧的投射物 / 召唤实体，或连社区都认不出）在数据集里带 `hidden` 标记，供页面过滤。

**深夜的深度与变异个体（第二版新增）**：深夜数值按**深度 1–5** 分档（每条数值行的 `depthStats`），逐档给出血量倍率、五系攻击力倍率、承受削韧倍率与对玩家耐力的削减——实战夜王走的是 Tier 4a 档，深度 1→5 血量 ×1.25 / 1.4 / 1.57 / 1.95 / 2.16，攻击力 ×1.25 / 1.55 / 1.92 / 2.83 / 3.31。**变异个体（玩家口中的「红化」）**是另一层独立倍率（`mutations` 10 组，共 4 种数值档：血量 ×1.15～1.8、攻击力 ×1.15～1.75、卢恩 ×1.35～2）。常驻威胁档位、深度、变异、人数四层的 `spCategory` 互不相同，因此互不覆盖、**倍率连乘**。每个深度在哪张地图、哪类敌人身上变异**几只**记在 `mutationCategories`；夜王在各深度的出现权重逐条收录在 `nightlords[].depthChanceWeights`，唯一普适的结论是永夜之王 / 救世旗手形态在深度 1 的权重恒为 0。

**多人缩放（第二版核实结论）**：**不是简单地「血量乘人数」**。血量倍率按敌人档位从 ×1 到 ×3 不等——最终 Boss 与部分守夜档确实是 ×2 / ×3，常见的野外档只有 ×1.1 / ×1.2，联机突袭的两档甚至完全不加血；部分档位（一个野外档与三个守夜档）多人时敌人**攻击力还会 ×1.1（双人）/ ×1.2（三人）**。防御侧（五系防御倍率与 `damageRates`）、卢恩与掉落、异常抗性阈值**都不受人数影响**；随人数变的是异常累积量与异常发动伤害两组倍率，且都往下走（人越多越难让 Boss 中异常、中了也更弱）。结论与 Fextralife 各 Boss 页的实测血量逐位一致（格拉狄乌斯 11,328 / 22,656 / 33,984 等），个别条目的 1 点差异来自取整口径而非算法分歧。

**口径与局限**：`damageRates` 是承伤倍率不是减伤率（1.35 = 多受 35%）；有效韧性要按 `poise / (poiseTakenBase × 人数档位 poiseTaken)` 算；菜单上的官方弱点与实际承伤倍率**不总是一致**（史柴格斯标注「无弱点」但圣属性倍率 1.25），页面两者并列展示；人数缩放、深度与变异倍率都来自参数表的 SpEffect 链路（`MultiPlayCorrectionParam` / `ChaosMatchingCorrectParam` / `SpEffectSetParam`），不是实测；数据集只描述数值，不含招式、行为与掉落。

### 角色属性（v0.3.0 新增）

10 个夜行者 1–15 级的八项属性（生命力 / 集中力 / 耐力 / 力气 / 灵巧 / 智力 / 信仰 / 感应）与四项派生值（血量 / 专注值 / 精力 / 负重上限），逐级成表。可以叠加**转职遗物**——就是那 20 条「【角色】提升 X，但降低 Y」词条，逐级给出增减量、可多选、效果相加；也可以切换**利普拉的交易**（「扭曲的重生」的力气 / 灵巧 / 智力 / 信仰 / 感应 五套整表替换）；另有「同级对比」视图横向比十个角色的同一级。

**口径与局限**：参数表里每个角色只有 **1 / 2 / 12 / 15 级四行锚点**，其余 11 级是相邻锚点线性插值后向下取整（floor）算出来的。该规则已与 Fextralife / eldenring.wiki.gg 的逐级表交叉核对：追踪者、执行者各 165 格**全中**；女爵 165 格里有 14 格不同，全部集中在「灵巧 1–14 级」，原因是补丁 1.02.2 提高了女爵升级时的灵巧成长、而两个 wiki 的表停在补丁之前，本页一律以参数表为准。**转职遗物在参数表里只有 1 / 12 级两个锚点**：13–15 级沿用 12 级（已由多组 15 级玩家实测确认），而 **2–11 级的逐级数值是推算的**，页面对每一级都标出「词条锚点 / 词条推算 / 词条沿用」三种来源。派生值各吃一项属性（血量←生命力、专注值←集中力、精力←耐力、负重上限←耐力，对应 `CalcCorrectGraph` 100 / 101 / 104 / 220）；**负重上限是从《艾尔登法环》继承下来的遗留列**——本作装备没有重量、界面也没有负重条，未经实测，页面用 `*` 注记与脚注标出。转职遗物（`heroStatusModifier`，在当前表上加减）与利普拉的交易（`heroStatusId`，整套替换）是两个不同字段，机制上可同时生效，这一条按参数结构推断，未在游戏内实测。

### 词条反查（v0.3.0 新增）

从词条出发反查出处：某条词条能出现在哪些遗物、哪些槽位层、哪种颜色上，深夜遗物的 A/B/C 池与诅咒池归属，以及与它互斥（同 `compatibilityId`）的词条有哪些。只用已有的词条库与遗物物品表，不引入新数据。

**口径与局限**：出处按参数表里的槽池模板推出，槽位层标的是「N 孔层」而不是「第 N 槽」（3 孔遗物的第 1 个槽用的是 3 孔层池）；能不能真的抽到还取决于权重，本页只回答「在不在候选集合里」。

### 增伤排名（v0.3.0 新增）

选一把武器 + 一个战技 / 法术，页面按参数表解出这一招的实际命中分段与伤害构成（斩 / 打 / 突 / 标准 / 魔力 / 火 / 雷 / 圣的占比），再把全部增伤手段按对这一招的**有效倍率**排名，并给出理论上可以叠加的组合。

**口径与局限**：这是**相对构成**，不是绝对伤害——不含强化等级、能力值补正与 `AttackElementCorrectParam`，跨武器的数值不可直接比大小。增伤倍率的取舍（哪些默认计入、哪些要勾选情境）照数据集自带的排名说明实现：只有 `activation="passive"` 且没有作用情境限制的条目才默认相乘，残血 / 双手持 / 叠层 / 致命一击 / 突刺反击之类要用户自己勾。**叠加关系是按参数结构（`spCategory` / `categoryPriority` / `saveCategory` / `stateInfo`）推断的，没有经过木桩实测**，请当作参数层面的默认规则而不是实战结论。

### 数据设置

查看内置数据的版本、来源与记录数，导入 / 导出离线 JSON 词条库，或恢复内置词条库。

> **四页共同的数值口径**：所有数值取自本机导出的游戏参数表（regulation 1.03.5），**不是游戏内实测**；参数表与实际表现不一致的已知点都写在各数据集的 `caveats` 字段与 [`macos/DataSources/PROVENANCE.md`](macos/DataSources/PROVENANCE.md) 里，页面也会就地提示。

## 仓库结构

| 目录 | 说明 |
| --- | --- |
| [`windows/`](windows/) | Windows 版：Go + WebView2 壳，对应 Windows EXE；四个新页面在 [`windows/renderer/pages/`](windows/renderer/pages/README.md) |
| [`macos/`](macos/) | macOS 版：Swift / SwiftUI（`RelicCore` 纯逻辑 + `NightreignRelicChecker` 界面 + `RelicCoreChecks` 自检） |
| [`macos/DataSources/`](macos/DataSources/PROVENANCE.md) | 数据导出与生成管线：`dump_regulation.py`（regulation.bin → 每表一个 CSV）、`extract_msg.py`（游戏归档 → 每个 FMG 一个 JSON）、`tools/oodledec`（借游戏自带 Oodle DLL 解 KRAK 压缩）、六个 `generate_*.py`（含角色属性的 `generate_heroes.py`）；**需要本机已安装的游戏本体与 CrossOver / Wine**，产物 `raw/` 不入库。来源、字段映射与已知局限见 `PROVENANCE.md` |
| [`android/`](android/) | Android 手机版：Kotlin / Jetpack Compose / Material 3；手动验物、词条库与离线说明。**v0.3.0 未更新**，仍是 v0.2.1 |
| [`data/`](data/) | 各端共用的权威数据集：词条库 `nightreign-affixes-v1.03.4.json`、遗物物品表 `nightreign-relics-v1.03.4.json`（存档检查用）、首领数据 `nightreign-bosses-v1.03.5.json`、战技/法术/武器 `nightreign-skills-v1.03.5.json`、增伤手段 `nightreign-buffs-v1.03.5.json`、角色属性 `nightreign-heroes-v1.03.5.json` |
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
复制前会用 python3 校验源文件是合法 JSON，坏文件不会污染两端资源目录。六个源文件现已全部就位，
两端 `resources/heroes.json` 与 `data/nightreign-heroes-v1.03.5.json` 的 sha256 一致。

三个客户端共享同一套判定规则与内置词条库，仅界面容器不同。各目录内有独立的 README 与构建说明：

- **Windows 版**（Go 1.25+，纯 Go 构建）：`go build -trimpath -ldflags "-s -w -H windowsgui" -o 夜幕验物.exe`
- **macOS 版**（macOS 13+，Swift）：`swift build && swift run RelicCoreChecks && zsh Scripts/build_app.sh`（`swift build` 不能省——应用资源包没构建过时，`GameDataLoader 能定位已构建的资源包` 那一组会跳过，自检总数少 4 项；顺序见 [`macos/README.md`](macos/README.md)）
- **Android 版**（JDK 17 + Android SDK 36）：在 `android/` 运行 `./gradlew testDebugUnitTest assembleDebug`

Android 版专注手机化的三词条检查与词条库，尚未移植桌面端 `.sl2/.co2` 存档解析，也没有本轮新增的四页；详细边界见 [`android/README.md`](android/README.md)。

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

- **游戏参数表与简体中文文本（v0.3.0 新增的四套数据集）**：本机已安装游戏的 `regulation.bin` 与 msg 归档，容器版本号 `10350000`（即 **regulation 1.03.5**，exe 1.3.3.0），由 `macos/DataSources/` 下的 `dump_regulation.py` / `extract_msg.py` 在本机导出；原始产物受游戏权利方权利约束，不入库。
- **Smithbox Paramdex（NR）**：`vawser/Smithbox@f5969c060cea240476e9dd4d6a64eafa9dbafaab`，MIT。提供 paramdef（字段布局与版本感知过滤）、英文参数行名与若干枚举（`WEP_TYPE`、`RARITY`、`ATK_SUB_CATEGORY`、`SP_EFFECT_TYPE`、`EFFECTIVE_AFFINITY` 等）。早期还用其 Nightreign 注释确认 `compatibilityId` 的参数语义（修订 `b1b644a770f8cc4c8cab452da3a72ff7b91e105a`）。
- **归档解包所用的公开密钥**：`.bhd` 的 RSA 公钥与 regulation 的 AES 密钥取自 UXM / BinderTool / Smithbox 等公开工具长期公布的常量（`Keys.NightreignKeys`、`Keys.NR_REGULATION_KEY`）；本仓库不分发游戏文件，也不包含任何绕过反作弊的代码。
- **Elden Ring Nightreign Save Editor**：修订 `0d2ad1494c372098e689c23159656df70ff2d76d`，MIT。词条库与遗物物品表的参数来源、官方简中 FMG，以及存档格式（BND4 / AES-CBC / 遗物记录布局）的解析依据。
- **NightreignQuickRef**：修订 `3e23450094c18125ae5665927ed240b18189a040`，GPL-3.0。词条的中文分类、效果说明、叠加性与别名。
- **热门度**：原检查站公开 API 的 2026-03-12 Wayback 快照，共恢复 19 条。
- **社区敌人名录 `4laric/nightreign-enemy-rando`**（HEAD，2026-09 访问）：**只用于辨认** Paramdex 与游戏文本都没有名字的 chrId（古龙桂奥尔、挖石山妖、百足恶魔幼虫、无名王者的坐骑）。中文名仍然只从本作游戏文本取，社区来源在数据集的 `nameSourceUrl` 里标出。
- **外部 wiki / 社区实测（只用于交叉核对，数值一律以参数表为准）**：Elden Ring Nightreign Wiki (Fextralife) 与 eldenring.wiki.gg（均 2026-09 访问）——前者的各 Boss 页用于核对人数缩放后的血量、削韧与八系承伤倍率，两者的角色页用于逐级核对角色属性表；另有 Steam 社区讨论里的 15 级玩家实测，用于确认转职遗物 13–15 级沿用 12 级锚点。核对结果与差异逐条记在数据集的 `crossChecks` 与 `caveats` 里。

每套数据集的完整来源表、字段映射、推断部分与已知局限见 [`macos/DataSources/PROVENANCE.md`](macos/DataSources/PROVENANCE.md)；各端的第三方许可见 `windows/THIRD_PARTY_NOTICES.md`、`macos/THIRD_PARTY_NOTICES.md` 与 `android/THIRD_PARTY_NOTICES.md`。

## 许可

整体以 [GNU GPL v3.0](LICENSE) 发布；具体第三方来源与许可见各目录内的 `THIRD_PARTY_NOTICES.md` 及词条库内的来源元数据。
