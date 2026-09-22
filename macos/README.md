# 夜幕验物（macOS）

《艾尔登法环 黑夜君临》三词条遗物离线合法性检查器。界面参考已失效的在线检查站，但数据和判定均在本机完成。

当前版本 **v0.3.0**（`Packaging/Info.plist` 的 `CFBundleShortVersionString` 为准）。

## 功能

七个页面，行为与 Windows 版一致：

- **词条检查** — 严格检查普通遗物当前 1.03.4 + DLC 词条池（340 条），可切换旧版 / 无 DLC 池（290 条）；检查重复 `effectId` 与 `compatibilityId` 互斥，按 `(overrideEffectId, effectId)` 给出正确保存顺序；热门词条快捷填入、合法随机组合；按游戏参数中的七种真实三正面槽位模板预检深夜词条。
- **词条库** — 搜索完整词条库，查看分类、说明与叠加性。
- **存档检查**（v0.2.0 起） — 只读解析 `.sl2` / `.co2` 存档，逐件校验全部角色的全部遗物（含深夜遗物正负词条配对、唯一遗物重复、保存顺序），指出非法遗物的种类与词条。v0.3.0 新增自动查找存档、拖拽打开、导出报告 / CSV、与另一份存档逐件对比，以及在遗物卡片上就地展开词条说明。自动查找只扫 CrossOver 的 bottle 目录 `~/Library/Application Support/CrossOver/Bottles/<bottle>/drive_c/users/<用户名>/AppData/Roaming/Nightreign/<SteamID>/`（macOS 上游戏跑在 CrossOver / Wine 里，存档落在 bottle 的模拟 Windows 盘上；候选项按 bottle 名与账户名标注）——存档不在 CrossOver bottle 下时这里找不到，仍可手动选择或拖入。
- **首领数据**（v0.3.0 新增） — 夜王与守夜 / 野外 Boss 的血量、削韧、八系承伤倍率、异常抗性与人数缩放。
- **词条反查**（v0.3.0 新增） — 从词条反查它能出现在哪些遗物、哪些槽位层与颜色上，以及互斥组。
- **增伤排名**（v0.3.0 新增） — 按武器 + 战技 / 法术解出伤害构成，给出增伤手段的有效倍率排名与可叠加组合。
- **数据设置** — 查看内置数据版本与来源，导入 / 导出离线 JSON 词条库。

三个新页面的数值口径与已知局限（数值取自参数表而非实测、增伤排名只给相对构成且叠加关系为参数结构推断、人数缩放来自参数）见仓库根 README 的「功能」一节与 [`DataSources/PROVENANCE.md`](DataSources/PROVENANCE.md)。

## 运行

双击 `夜幕验物.app`。这是本地临时签名版本；若 macOS 首次阻止打开，请在 Finder 中右键应用并选择“打开”。

最低系统版本：macOS 13。发行包为 Universal 2，同时支持 Apple Silicon 与 Intel Mac。

## 从源码构建

```sh
swift build                 # 先构建一次，应用目标的资源包才会存在
swift run RelicCoreChecks   # 自检，最后一行打印通过的检查条数
zsh Scripts/build_app.sh    # 产出 build/夜幕验物.app（Universal 2 + 临时签名）
```

`RelicCoreChecks` 把每组检查的条数逐行打印出来，末行是总数；**总数只增不减**，改动后
的数字必须不低于改动前。注意 `GameDataLoader 能定位已构建的资源包` 这一组依赖
`swift build` 产生的资源包：没先构建过应用目标时它会打印「应用资源包未构建，跳过」
并计 0 项，总数因此比正常少 3 项——所以请按上面的顺序先 `swift build`。

只要发行二进制的话：

```sh
swift build -c release --product NightreignRelicChecker
```

`Scripts/build_app.sh` 在此基础上再编一份 `x86_64-apple-macosx13.0`，用 `lipo` 合成
Universal 2 可执行文件，拷入 `Info.plist`、五个数据 JSON、`LICENSE` 与
`THIRD_PARTY_NOTICES.md`，生成图标并做本地临时签名。产物位于 `build/夜幕验物.app`。

## 数据更新

内置数据位于 `Sources/NightreignRelicChecker/Resources/`：词条库 `affixes.json`
（schema 版本 1，应用内“数据设置”可导入相同格式的 JSON）、遗物物品表 `relics.json`
（存档检查用），以及三个新页面的 `bosses.json` / `skills.json` / `buffs.json`。

**不要手动复制**。仓库根的 `data/` 是唯一权威来源，换数据时在仓库根运行：

```sh
zsh scripts/sync-data.sh
```

脚本把 `data/nightreign-<名字>-v<版本>.json` 同步成两端的 `<名字>.json`
（affixes、relics、bosses、skills、buffs 五项），Windows 与 macOS 一次覆盖，代码无需改动。

这些 JSON 的生成管线在 [`DataSources/`](DataSources/PROVENANCE.md)：
`dump_regulation.py`（regulation.bin → 每表一个 CSV）、`extract_msg.py`（游戏归档 →
每个 FMG 一个 JSON）、`generate_affixes.py` / `generate_relics.py` /
`generate_bosses.py` / `generate_skills.py` / `generate_buffs.py`。前两步需要本机已安装
的游戏本体（macOS 下通过 CrossOver / Wine 的 Steam bottle 访问），导出的 `raw/` 不入库；
解 KRAK（Oodle 2.9）压缩用的小工具与调用方式见
[`DataSources/tools/oodledec/README.md`](DataSources/tools/oodledec/README.md)。
各数据集的来源表、字段映射、推断部分与已知局限见 `DataSources/PROVENANCE.md`。

## 页面结构（首领数据 / 词条反查 / 增伤排名）

三页各自一个视图文件，页面状态全部自持，**功能开发不需要再改 `AppModel.swift` / `RootView.swift`**：

| 页面 | 视图文件 | 数据 |
| --- | --- | --- |
| 首领数据 | `Sources/NightreignRelicChecker/BossDataView.swift` | `GameDataLoader.dataIfAvailable(for: .bosses)` |
| 词条反查 | `Sources/NightreignRelicChecker/AffixLookupView.swift` | `model.catalog` / `model.relicData`（无新数据文件） |
| 增伤排名 | `Sources/NightreignRelicChecker/BuffRankerView.swift` | `GameDataLoader.dataIfAvailable(for: .skills / .buffs)` |

- 纯逻辑放 `Sources/RelicCore/`（`BossData.swift` / `AffixLookup.swift` / `SkillData.swift` /
  `BuffRanker.swift`），视图只做展示——两端的判定与算法口径靠这一层与 Windows 端对齐。
- `RelicCore/GameDataLoader.swift` 提供 `GameDataResource`（bosses / skills / buffs）与
  `url(for:)`、`data(for:)`（未内置时抛出可读错误）、`isPlaceholder(_:)`、
  `dataIfAvailable(for:)`（未内置 / 占位 / 读取失败时返回 nil）。加载器**只返回原始
  `Data`**，业务模型各自在自己的文件里定义。
- 查找顺序是 `Bundle.main`（打包后的 .app）→ 应用目标的 SwiftPM 资源包（`swift run`）。
- 数据文件缺失或仍是占位 JSON（`{"placeholder": true}`）时页面显示“数据未内置”，
  不影响其它功能与构建；用 `scripts/sync-data.sh` 覆盖后重新构建即可。
- 自检：`Sources/RelicCoreChecks/GameDataChecks.swift` 里维护一个检查列表，
  功能开发者把自己的 `() throws -> Int` 检查函数写在新文件里，只往列表加一行。
- 两端共享的数据契约（`getGameData` / `dataIfAvailable` 的「永不失败、未内置返回空」
  语义，三个数据文件与 `data/` 源文件的对应关系）另有一份更详细的说明，见 Windows 端的
  页面模块契约 [`../windows/renderer/pages/README.md`](../windows/renderer/pages/README.md)。

## 许可

本项目以 GPL-3.0 发布。第三方数据、修订号及许可见 `THIRD_PARTY_NOTICES.md`。
