# 夜幕验物（macOS）

《艾尔登法环 黑夜君临》三词条遗物离线合法性检查器。界面参考已失效的在线检查站，但数据和判定均在本机完成。

当前版本 **v0.3.0**（`Packaging/Info.plist` 的 `CFBundleShortVersionString` 为准）。

## 功能

八个页面，行为与 Windows 版一致：

- **词条检查** — 严格检查普通遗物当前 1.03.4 + DLC 词条池（340 条），可切换旧版 / 无 DLC 池（290 条）；检查重复 `effectId` 与 `compatibilityId` 互斥，按 `(overrideEffectId, effectId)` 给出正确保存顺序；热门词条快捷填入、合法随机组合；按游戏参数中的七种真实三正面槽位模板预检深夜词条。
- **词条反查**（v0.3.0 新增，导航里紧跟词条检查） — 从词条反查它能出现在哪些遗物、哪些槽位层与颜色上，以及互斥组。
- **词条库** — 搜索完整词条库，查看分类、说明与叠加性。
- **存档检查**（v0.2.0 起） — 只读解析 `.sl2` / `.co2` 存档，逐件校验全部角色的全部遗物（含深夜遗物正负词条配对、唯一遗物重复、保存顺序），指出非法遗物的种类与词条。v0.3.0 新增自动查找存档、拖拽打开、导出报告 / CSV、与另一份存档逐件对比，以及在遗物卡片上就地展开词条说明。自动查找只扫 CrossOver 的 bottle 目录 `~/Library/Application Support/CrossOver/Bottles/<bottle>/drive_c/users/<用户名>/AppData/Roaming/Nightreign/<SteamID>/`（macOS 上游戏跑在 CrossOver / Wine 里，存档落在 bottle 的模拟 Windows 盘上；候选项按 bottle 名与账户名标注）——存档不在 CrossOver bottle 下时这里找不到，仍可手动选择或拖入。
- **首领数据**（v0.3.0 新增） — 18 个夜王条目与 116 组首领的血量、削韧、八系承伤倍率、异常抗性与人数缩放。第三版数据集（`bossesSchemaVersion` 4）起按出场场合分组：夜王 / 守夜首领 / 据点首领 / 场景头目（游戏文本对白天野外强敌的叫法）/ 封印监牢 / 其它场合，一组首领可同时属于多个分组（如铃珠猎人的野外版与守夜版分属不同数值行），展开后逐行可见场合与出处；「随从/召唤物」「未放置」两个分组默认隐藏。第二版数据集（`bossesSchemaVersion` 3）起：简中名只按本作游戏文本对照、没有的显示英文名（旧《艾尔登法环》译名降级为「参考译名·非本作游戏文本」），深夜按深度 1–5 分档、另有可连乘的变异个体（红化）倍率，人数缩放核实为「按敌人档位 ×1～×3 不等、部分档位多人时敌人攻击力 ×1.1 / ×1.2，防御 / 卢恩 / 异常阈值不变」。
- **角色属性**（v0.3.0 新增，导航里紧跟首领数据） — 10 个渡夜者 1–15 级的八项属性与血量 / 专注值 / 精力 / 负重上限，可叠加 20 条转职遗物词条、切换利普拉的交易（五套整表替换），并按等级横向对比十个角色。
- **增伤排名**（v0.3.0 新增） — 选一个战技（+ 武器）或法术并勾选命中分段、解出伤害构成，再自己组一套局内配置：常规 / 深夜开关（武器词条 6 把 × 1 条 / 6 把 × 2 条正面，深夜专属正面每把最多 1 条；遗物 3 件 / 3 普通 + 3 深夜），局内武器词条、遗物（固定词条遗物整件，或自组三词条并按词条检查口径实时校验、深夜遗物自动配诅咒）、护符两槽、其它增益按来源分类，汇总按互斥键去重后连乘再按构成加权，给出总倍率、各栏小计与「按推荐填满」。生效判定用数据集预计算的 `appliesTo`，不生效项默认隐藏、可显示并标出原因。
- **数据设置** — 查看内置数据版本与来源，导入 / 导出离线 JSON 词条库。

四个新页面的数值口径与已知局限（数值取自参数表而非实测；增伤排名只给相对构成，叠加关系按参数结构推断，配置里同一效果多份时 stackSelf 按份数相乘、其余只算一份，同一遗物词条的 4 档互为替代只取一档，也都未实测；人数缩放与深夜深度 / 变异倍率来自参数；角色属性的中间等级为插值且转职遗物 2–11 级为推算）见仓库根 README 的「功能」一节与 [`DataSources/PROVENANCE.md`](DataSources/PROVENANCE.md)。

## 运行

双击 `夜幕验物.app`。这是本地临时签名版本；若 macOS 首次阻止打开，请在 Finder 中右键应用并选择“打开”。

最低系统版本：macOS 13。发行包为 Universal 2，同时支持 Apple Silicon 与 Intel Mac。

## 从源码构建

```sh
swift build                 # 先构建一次，应用目标的资源包才会存在
swift run RelicCoreChecks   # 自检，最后一行打印通过的检查条数
zsh Scripts/build_app.sh    # 产出 build/夜幕验物.app（Universal 2 + 临时签名）
```

`RelicCoreChecks` 把每组检查的条数逐行打印出来，末行是总数（目前两万余项，含首领数据、
角色属性、词条反查、增伤排名四页的数据自检）；**总数只增不减**，改动后的数字必须不低于
改动前。注意 `GameDataLoader 能定位已构建的资源包` 这一组依赖
`swift build` 产生的资源包：没先构建过应用目标时它会打印「应用资源包未构建，跳过」
并计 0 项，总数因此比正常少 4 项——所以请按上面的顺序先 `swift build`。

只要发行二进制的话：

```sh
swift build -c release --product NightreignRelicChecker
```

`Scripts/build_app.sh` 在此基础上再编一份 `x86_64-apple-macosx13.0`，用 `lipo` 合成
Universal 2 可执行文件，拷入 `Info.plist`、六个数据 JSON、`LICENSE` 与
`THIRD_PARTY_NOTICES.md`，生成图标并做本地临时签名。产物位于 `build/夜幕验物.app`。

## 数据更新

内置数据位于 `Sources/NightreignRelicChecker/Resources/`：词条库 `affixes.json`
（schema 版本 1，应用内“数据设置”可导入相同格式的 JSON）、遗物物品表 `relics.json`
（存档检查用），以及四个新页面的 `bosses.json` / `skills.json` / `buffs.json` / `heroes.json`。

**不要手动复制**。仓库根的 `data/` 是唯一权威来源，换数据时在仓库根运行：

```sh
zsh scripts/sync-data.sh
```

脚本把 `data/nightreign-<名字>-v<版本>.json` 同步成两端的 `<名字>.json`
（affixes、relics、bosses、skills、buffs、heroes 六项），Windows 与 macOS 一次覆盖，代码无需改动。
六个源文件现已全部就位，`Resources/heroes.json` 与 `data/nightreign-heroes-v1.03.5.json`
的 sha256 一致；数据缺位或退回占位 JSON 时页面仍会走「数据未内置」分支。

这些 JSON 的生成管线在 [`DataSources/`](DataSources/PROVENANCE.md)：
`dump_regulation.py`（regulation.bin → 每表一个 CSV）、`extract_msg.py`（游戏归档 →
每个 FMG 一个 JSON）、`extract_msb.py`（游戏归档 → 地图 MSB 的敌人放置，首领按出场场合分组的依据）、
`generate_affixes.py` / `generate_relics.py` / `generate_bosses.py` / `generate_skills.py` /
`generate_buffs.py` / `generate_heroes.py`。三个导出脚本需要本机已安装
的游戏本体（macOS 下通过 CrossOver / Wine 的 Steam bottle 访问），导出的 `raw/` 不入库；
解 KRAK（Oodle 2.9）压缩用的小工具与调用方式见
[`DataSources/tools/oodledec/README.md`](DataSources/tools/oodledec/README.md)。
各数据集的来源表、字段映射、推断部分与已知局限见 `DataSources/PROVENANCE.md`。

## 页面结构（首领数据 / 角色属性 / 词条反查 / 增伤排名）

四页各自一个视图文件（导航位置：词条反查紧跟「词条检查」；首领数据 → 角色属性 → 增伤排名排在「存档检查」之后、「数据设置」之前；
主导航顺序就是 `AppModel.Page` 的声明顺序），页面状态
全部自持，**功能开发不需要再改 `AppModel.swift` / `RootView.swift`**：

| 页面 | 视图文件 | 数据 |
| --- | --- | --- |
| 首领数据 | `Sources/NightreignRelicChecker/BossDataView.swift`（卡片与分组组件在 `BossData*.swift`） | `GameDataLoader.dataIfAvailable(for: .bosses)` |
| 词条反查 | `Sources/NightreignRelicChecker/AffixLookupView.swift` | `model.catalog` / `model.relicData`（无新数据文件） |
| 增伤排名 | `Sources/NightreignRelicChecker/BuffRankerView.swift`（状态在 `BuffRankerModel.swift`，配置 / 遗物 / 一览各分区在 `BuffRanker*Section.swift`） | `GameDataLoader.dataIfAvailable(for: .skills / .buffs)` |
| 角色属性 | `Sources/NightreignRelicChecker/HeroStatsView.swift` | `GameDataLoader.dataIfAvailable(for: .heroes)` |

- 纯逻辑放 `Sources/RelicCore/`（`BossData.swift` / `HeroData.swift` / `AffixLookup.swift` /
  `SkillData.swift` / `BuffRanker.swift` / `BuffLoadout.swift`），视图只做展示——两端的判定与算法口径靠这一层与
  Windows 端对齐；`HeroData.swift` 里的 `HeroStatsCopy` 与 Windows 端 `pages/heroes.js`
  的 `COPY` 是同一份文案，改字要两端加两份用例一起改。同理：首领分组规则的正文在 `BossData.swift`
  （`BossCard.Group` 的文档注释），文案表 `BossRowText` / `BossRoleText` 与 `pages/bosses.js` 的
  `TEXT` / `ROLE_TEXT` 逐字相同；增伤排名的配置口径在 `BuffLoadout.swift`，文案表 `LoadoutText.table`
  与 `pages/ranker.js` 的 `TEXT` 按点号路径逐键同文，两端自检校验同一个摘要。
- `RelicCore/GameDataLoader.swift` 提供 `GameDataResource`（bosses / skills / buffs / heroes）与
  `url(for:)`、`data(for:)`（未内置时抛出可读错误）、`isPlaceholder(_:)`、
  `dataIfAvailable(for:)`（未内置 / 占位 / 读取失败时返回 nil）。加载器**只返回原始
  `Data`**，业务模型各自在自己的文件里定义。
- 查找顺序是 `Bundle.main`（打包后的 .app）→ 应用目标的 SwiftPM 资源包（`swift run`）。
- 数据文件缺失或仍是占位 JSON（`{"placeholder": true}`）时页面显示“数据未内置”，
  不影响其它功能与构建；用 `scripts/sync-data.sh` 覆盖后重新构建即可。
- 自检：`Sources/RelicCoreChecks/GameDataChecks.swift` 里维护一个检查列表，
  功能开发者把自己的 `() throws -> Int` 检查函数写在新文件里，只往列表加一行；四页各有
  一个文件（`BossDataChecks` / `HeroStatsChecks` / `AffixLookupChecks` / `BuffRankerChecks`）。
  `BossDataChecks` 钉着首领数据的收录统计、分组对照表与名字回退口径（Windows 端
  `tests/bosses_parity.test.mjs` 直接读这个文件的对照表来跑），`BuffRankerChecks` 的
  `checkLoadoutParity` 与 Windows 端 `tests/ranker_crosscheck.test.mjs` 是同一组配置对照用例，
  换数据集或改口径时要一并更新。
- 两端共享的数据契约（`getGameData` / `dataIfAvailable` 的「永不失败、未内置返回空」
  语义，四个数据文件与 `data/` 源文件的对应关系）另有一份更详细的说明，见 Windows 端的
  页面模块契约 [`../windows/renderer/pages/README.md`](../windows/renderer/pages/README.md)。

## 许可

本项目以 GPL-3.0 发布。第三方数据、修订号及许可见 `THIRD_PARTY_NOTICES.md`。
