# 数据集来源与计数（PROVENANCE）

本文件记录仓库 `data/` 下每一套权威数据集的来源、字段映射、推断部分与已知局限；消费方
（两端页面）的数值口径必须以本文件与各数据集自带的 `caveats` / `notes` 字段为准。文件按
数据集分节，每节内部固定是「来源表 → 字段映射 → 推断与判断 → 已知局限 → 逐轮核验修复
补充」的顺序。

- **遗物词条库** `affixes.json`（`generate_affixes.py`）—— 合法性判定的权威数据。
- **遗物物品表** `relics.json`（`generate_relics.py`）—— 存档检查用。
- **首领数据** `bosses.json`（`generate_bosses.py`）、**战技／法术／武器** `skills.json`
  （`generate_skills.py`）、**增伤手段** `buffs.json`（`generate_buffs.py`）—— v0.3.0 三个新页面用。

## 遗物词条数据集（affixes.json）

生成文件：`affixes.json`  
目标数据版本：v1.03.4 + DLC1  
生成时间：2026-07-10T01:36:40+00:00

### 可直接用于第一版普通遗物检查器的规则

- 下拉列表过滤：`eligibleForNormalChecker == true`（共 340 条）。
- 三条词条必须是三个不同 `effectId`，且非 `-1` 的 `compatibilityId` 两两不同。
- 正确显示／存档顺序：按 `(sortId, effectId)` 升序；`sortId` 就是游戏参数的 `overrideEffectId`。
- 普通随机遗物的红、蓝、黄、绿四种颜色使用相同词条池，颜色不改变组合合法性。
- 旧池为 100/200/300，共 290 条；当前池为 110/210/310，共 340 条。三个槽的候选集合相同，仅权重不同。
- 30 个远征奖励池的当前可抽候选集合也都与上述 340 条完全相同；商店 72 行、远征奖励 360 行中，每一种池序列都覆盖红蓝黄绿四色。

### 计数

- 数据记录：527
- 普通旧池可抽：290
- 普通当前池可抽：340
- 深夜正面可抽：332
- 深夜 A 池且需要负面词条：49
- 深夜负面词条：24
- 固定／参考词条（不能进入随机普通检查器）：30
- 官方简中 FMG 直接命名：527
- QuickRef／旧 API 补名：0
- 仍无名称：0
- 带 QuickRef 分类／说明：520
- 带旧站热门查询量：19

### 来源

1. 游戏参数、简中 FMG：[0d2ad1494c37](https://github.com/alfizari/Elden-Ring-Nightreign-Save-Editor/tree/0d2ad1494c372098e689c23159656df70ff2d76d)。参数文件最后更新于 2026-01，QuickRef 同期提交明确标注为 v1.03.4 数据。
2. 说明与分类：[3e23450094c1](https://github.com/xxiixi/NightreignQuickRef/tree/3e23450094c18125ae5665927ed240b18189a040)。
3. 参数字段语义：[Smithbox Nightreign annotations](https://github.com/vawser/Smithbox/blob/b1b644a770f8cc4c8cab452da3a72ff7b91e105a/src/Smithbox.Data/Assets/PARAM/NR/Param%20Annotations/English/ATTACHEFFECT_PARAM_ST.json)。其中明确说明相同 `compatibilityId` 不能同时出现在同一遗物／武器；`exclusivityId` 只控制已装备遗物间的红色感叹号提示，不能拿来判定单件遗物组合。
4. 热度与旧称：Wayback 保存的 [`relics-with-ID`](https://web.archive.org/web/20260312030547id_/https://elden-api-v2.dingdangmarket.com/relics-with-ID) 与 [`hot-relics`](https://web.archive.org/web/20260312030548id_/https://elden-api-v2.dingdangmarket.com/hot-relics)，快照日期 2026-03-12。

游戏参数决定合法性；QuickRef 与旧站数据只用于展示、别名、说明和热度，不覆盖参数字段。

许可提示：Save Editor 与 Smithbox 为 MIT；NightreignQuickRef 为 GPL-3.0。公开分发内嵌 QuickRef 说明的版本时，应保留来源、许可证并履行 GPL 要求；游戏 FMG 文本仍受游戏权利方权利约束。此处仅记录来源，不构成法律意见。

### 合并异常／保守处理

- QuickRef 中有 11 个 ID 已不在当前 `AttachEffectParam`，已排除：6800000, 6800200, 6810100, 6850000, 6850100, 7033300, 7043900, 7331600, 7341600, 7351600, 7370500。
- 热门词条成功按旧 API 的 effect ID 唯一匹配 19 条；歧义 0 条；未匹配 1 条。
- 未匹配热门项：加快累积绝招量表＋３。
- 旧站 20 个热门组合中，19 个能唯一还原为 effect ID；其中按 `(sortId, effectId)` 排序正确 19 个，`compatibilityId` 两两不同 19 个。其余 1 个因旧站名称无法唯一映射而未用于结论。
- 对深夜遗物，本数据保留 A/B/C 池和诅咒标记，但第一版普通检查器不应显示 `isCurse == true` 或 `eligibleNormalCurrent == false` 的记录。

## 遗物物品表（relics.json，v0.2.0 存档检查功能）

`generate_relics.py` 从 Save Editor 同一修订（0d2ad1494c372098e689c23159656df70ff2d76d）生成
`data/nightreign-relics-v1.03.4.json`（同步内嵌至 Windows / macOS 资源目录）：

- `EquipParamAntique.csv`：1397 件遗物的槽池模板（`attachEffectTableId_1..3` 与
  `attachEffectTableId_curse1..3`）、颜色（`relicColor`）、深夜标记（`isDeepRelic`）。
  当前数据共标记 222 件深夜遗物；真实存档验证支持「A 池（2000000）槽数 = 诅咒槽（3000000）数」，
  即「需诅咒」词条与负面词条按槽位一一配对。
- `AttachEffectTableParam.csv`：598 个被引用池的可掉落集合（权重过滤规则与
  `generate_affixes.py` 一致）；与 affixes.json 的 `poolIds` 交叉验证一致。
- `AntiqueName(.dlc01).fmg.xml`、`AttachEffectName(.dlc01).fmg.xml`：遗物与词条简中名；
  词条库未收录但被遗物池引用的 1552 条词条以 `extraAffixes` 形式补充最小元数据。
- 存档二进制格式（BND4 / AES-128-CBC / 80 字节遗物记录，正面词条偏移 16/20/24、
  负面词条偏移 56/60/64）依据同修订的 `src/packer/_pc.py` 与 `src/inventory_handler.py`。

## 本机游戏参数与文本导出（2026-09-22，为伤害/削韧/Boss 数据功能做准备）

工具：`dump_regulation.py`（regulation.bin → 每表一个 CSV）、`extract_msg.py`（归档里的
msg/<lang>/*.msgbnd.dcx → 每个 FMG 一个 JSON）、`tools/oodledec/`（Wine 下调用游戏自带
Oodle DLL 的 Kraken 解压器）。产物写到 `raw/`（已 .gitignore，不入库）。

- 游戏来源：本机 CrossOver 的 Steam bottle，`nightreign.exe` 1.3.3.0，Steam buildid 22818764，
  `regulation.bin` sha256 `876a3ca279a4561d0c69f81fe5e510c75c59ab9a8a201694f8cf4a42c91e0268`，
  容器版本号 `10350000`（即 1.03.5）。
- regulation.bin：AES-256-CBC（密钥取自 Smithbox 内嵌 SoulsFormats 的 `Keys.NR_REGULATION_KEY`，
  IV 为文件前 16 字节）→ DCX/ZSTD → BND4（252 个 .param）。字段布局用 Smithbox Paramdex
  `Assets/PARAM/NR/Defs`（vawser/Smithbox@f5969c060cea240476e9dd4d6a64eafa9dbafaab），
  版本感知字段按 10350000 过滤；英文行名取同仓库 `Param Row Names/English`，同 ID 多行的表
  按出现次序取名。252 张表全部匹配到 paramdef，行长逐表核对一致。
- 解析正确性核验：`EquipParamAntique` / `AttachEffectParam` / `AttachEffectTableParam` /
  `AntiqueStandParam` 与 Save Editor 0d2ad149 的 1.03.4 CSV 逐格比对（共 17+32+5+12 个
  共有字段，含位域）全部一致，同时说明 1.03.5 没有改动遗物相关表，现有词条库仍然有效。
- 归档：data0–3、dlc01 的 .bhd 用 UXM/Smithbox 公开的 RSA 公钥解密（`Keys.NightreignKeys`），
  条目按 64 位路径哈希（乘数 0x85）定位，用 Smithbox 的 `EldenRingNightreignDictionary.txt`
  做过命中率核验（data2/data3 全中）。当前版本已不存在 `item.msgbnd.dcx` / `menu.msgbnd.dcx`，
  完整文本在 `item_dlc01.msgbnd.dcx` / `menu_dlc01.msgbnd.dcx` 里（含无后缀的基础 FMG 与
  `_dlc01` 增量 FMG）。条目在 .bdt 里带 AES-128-ECB 区间加密，DCX 为 KRAK（Oodle 2.9）。
- 可用于新功能的关键表：`NpcParam`（血量、韧性 `superArmorDurability`、各属性
  `*DamageCutRate`、异常抗性、`multiPlayCorrectionParamId`）、`MultiPlayCorrectionParam` +
  `SpEffectParam`（双人/三人的血量倍率 `maxHpRate`、削韧承受倍率 `saReceiveDamageRate`、
  异常累积倍率）、`NightBossMenuParam`（夜王列表、`effectiveAffinity` 官方弱点、菜单文本 ID）、
  `AtkParam_Pc`（动作值 `atk*Correction`、削韧 `atkSuperArmor`，Paramdex 行名已标注大部分战技的
  分段）、`SpEffectParam`（增伤倍率 `*AttackRate` / `*AttackPowerRate`、叠加分类 `stateInfo`）、
  `SwordArtsParam` / `Magic` / `EquipParamWeapon` / `Bullet` / `ReinforceParamWeapon` /
  `AttackElementCorrectParam` / `CalcCorrectGraph`。

## 游戏数据集（v0.3.0：首领数据 / 词条反查 / 增伤排名）

以下三节是 v0.3.0 为三个新页面生成的数据集，全部来自上一节导出的本机游戏参数表与游戏内
文本，互相独立、可分别重新生成：

| 数据集 | 生成器 | 当前 schemaVersion | 供哪一页使用 |
| --- | --- | --- | --- |
| `data/nightreign-bosses-v1.03.5.json` | `generate_bosses.py` | `bossesSchemaVersion` 4 | 首领数据 |
| `data/nightreign-skills-v1.03.5.json` | `generate_skills.py` | 3（v3 起含局内战技池，命中段按 TAE 核实，无 FP 段与只打自己 / 队友的段按审查意见补标；三端界面仍按 2 读取，待界面车道跟进） | 增伤排名（选段与伤害构成） |
| `data/nightreign-buffs-v1.03.5.json` | `generate_buffs.py` | 6 | 增伤排名（倍率、叠加与配置槽位） |
| `data/nightreign-heroes-v1.03.5.json` | `generate_heroes.py` | 1 | 角色属性 |

> 表里的 schemaVersion 是写死的：重新生成任何一套数据集时，请同步更新本表与
> [`windows/renderer/pages/README.md`](../../windows/renderer/pages/README.md) 的
> 「3. `ctx.getGameData(name)`」一节（那里也写了 `bossesSchemaVersion` 4 / skills 2 / buffs 6 / heroes 1）。

「词条反查」页不使用新数据集，只用既有的 `affixes.json` 与 `relics.json`。原计划里的
「削韧」没有单独成集：削韧数值（`atkSuperArmor` / `atkSuperArmorCorrection` /
`saWeaponDamage` 与 Boss 侧的 `poise` / `poiseTaken`）已分别并入 skills 与 bosses 两套数据。

三套数据集都经过独立核验与修复（buffs 四轮、skills 两轮），每轮的修复内容附在对应数据集
一节的末尾，schemaVersion 的变化也记在那里；旧结论被推翻时保留原文并追加更正段落，不做
静默覆盖。

### 首领数据集 `nightreign-bosses-v1.03.5.json`

生成器：`macos/DataSources/generate_bosses.py`
运行：`cd macos/DataSources && python3 generate_bosses.py`（默认读 `raw/`，写 `data/nightreign-bosses-v1.03.5.json`）

#### 来源表

| 来源 | 修订 / 版本 | 许可 | 用途 |
| --- | --- | --- | --- |
| ELDEN RING NIGHTREIGN `regulation.bin` 导出的参数 CSV（`raw/params/`） | regulation 10350000 / exe 1.3.3.0 / steam build 22818764，sha256 `876a3ca2…e0268` | 游戏本体数据，仅用于展示数值 | `NightBossMenuParam`、`NpcParam`、`MultiPlayCorrectionParam`、`SpEffectParam` |
| 游戏内文本 FMG（`raw/msg/{zhocn,engus}/`） | regulation 10350000 + DLC1（基础 `X.json` 与 `X_dlc01.json` 合并，后者覆盖） | 游戏本体数据，仅用于展示名称 | `menu_dlc01/CL_MenuText`（夜王名 / 远征名 / 夜王说明）、`item_dlc01/NpcName`（Boss 名，中英） |
| Smithbox Paramdex (NR) | `vawser/Smithbox@f5969c060cea240476e9dd4d6a64eafa9dbafaab` | MIT | paramdef 字段名、参数行名（CSV 的 `Name` 列）、`EFFECTIVE_AFFINITY` 枚举 |

#### 字段映射

- **夜王条目** ← `NightBossMenuParam` 每一行。`bossNameId`/`expeditionNameId`/`descriptionId` → `CL_MenuText`（zhocn + engus）；`effectiveAffinity1/2` → `EFFECTIVE_AFFINITY` 枚举（0 = None 已剔除），枚举中文译名为本项目补充。`everdark` 由行名是否以 `[` 开头判定（`[Everdark Sovereign] …` 与 `[Salvation's Standard-Bearers] Balancers / Harmonia`）。
- **战斗行** ← `NpcParam`。`hp`、`superArmorDurability` → poise、`saRecoveryRate` → poiseRecover。
- **承伤倍率** ← `neutral/slash/blow/thrust/magic/fire/thunder/darkDamageCutRate` → `standard/slash/strike/pierce/magic/fire/lightning/holy`。本作把**圣属性放在 dark 槽**；`def_*` 字段全为 100，不参与计算，未收录。
- **异常抗性** ← `resist_poison/desease/blood/freeze/sleep/madness/curse` → `poison/rot/bleed/frost/sleep/madness/death`，999 视为免疫（另出 `immune` 数组）。
- **人数缩放** ← `NpcParam.multiPlayCorrectionParamId` → `MultiPlayCorrectionParam`（`client1SpEffectId` = 双人、`client2SpEffectId` = 三人）→ `SpEffectParam`：`maxHpRate` → hp、`saReceiveDamageRate` → poiseTaken、`changeSaRecoveryVelocity` → poiseRecover、`bloodDamageRate`/100 → statusRate（与 freeze/sleep/madness 同值）、`poisonDamageRate`/100 → poisonRate、`poisonDefDamageRate` → resistRate（与其余 `*DefDamageRate` 同值）。同一档位名下不同尾号的缩放并不一致（例如 7762 是 ×1.3/×1.6，7767 是 ×2/×3），因此 `scalingTiers` 按具体 ID 收录。
- **守夜/野外 Boss 中文名**：`NpcName` 的文本 ID 形如 `9 + chrId(5 位) + 3 位序号`（如 `903100600` = c3100 铃珠猎人）。按 chrId 取候选后用「精确 → 单复数 → 扩写（`XXX of the YYY`）」匹配 Paramdex 基础名；失败再做全局精确匹配，再落到手工别名表，最后才保留英文。每条记录用 `nameSource` 标明来源。

#### 推断与判断

- **夜王 ↔ NpcParam 的归属**是手工映射（`NIGHTLORD_CHRS`）：格拉狄乌斯 c7500、艾德雷 c7510/7511、格诺斯塔 c7520+c7521+c7530、玛利斯 c7540/7541、利普拉 c7560/7561/7570、弗格尔 c7600、卡莉果 c4900/4901、布德奇冥 c7580、哈尔莫妮亚 c7620+c4641、史柴格斯 c7610。依据是 Paramdex 行名、`WwiseValueToStrParam_BgmBossChrIdConv` 的 BGM 触发行、以及 `NpcName` 的分组（`9075200xx` 下同时有「慧心虫 / 格诺斯塔 / 亚尼姆斯」）。
- **弗堤士（Faurtis Stoneshield，“坚盾”弗堤士）与亚尼姆斯（Animus, Ascendant Light，“超越之光”亚尼姆斯）归入「慧心虫」远征**：两者都属「Final Boss Threat」且有至暗变体，却没有独立的 `NightBossMenuParam` 行，也没有独立 BGM 行；慧心虫说明文本写的是「飞翔空中的双翅、徘徊地面的螯剪」（两只虫）。亚尼姆斯只有至暗行（普通远征无对应 `(Boss)` 行），故只挂在至暗条目下。这是推断，非参数直接给出。
- **「至暗」判定**：行名含 `Everdark` / `Enhanced Boss`，或 chrId 属于只在至暗战登场的 `{7511, 7561, 4901, 4641, 7521, 7541}`。
- **`isMain`** 是手工列出的 npcId 集合（普通远征最终战用行 + 至暗战用行），不是参数字段。
- **合并规则**：同一条目下 hp / poise / poiseRecover / 八系倍率 / 七项抗性 / 解析后的缩放值完全一致的行合并为一条，`npcIds` 保留全部原始行号，`npcId` 是代表行（优先取 `isMain` 行 → 有手工标签的行 → 变体描述最长且非 Template 的行）。
- **手工补的中文名**（`nameSource: "manual"`，按 Elden Ring 官方简中或组合游戏文本）：山妖、雪花石之王、缟玛瑙之王、手指爬行者、行走灵庙、火焰骑士（含队长/长老/贤者）、大型黄金河马、废弃物蚯蚓脸、葬送战马、发狂米兰达之花、鲜血君王的长枪、墓地幽魂。
- **变体标签中文**（如「封印监牢」「地下堡垒精英」「登场演出」）是本项目对 Paramdex 括号注释的翻译，不是游戏文本。

#### 已知局限

- 跳过 `NightBossMenuParam` ID 100「深夜 / The Deep of Night」（`bossNameId = -1`，是深度模式入口而非夜王），记录在 `notes.skippedMenuRows`。
- 跳过 15 行既无 Paramdex 行名又无 `NpcName` 的实体（c4504、c4603、c7711、c7712、c7910、c7931、c7932），以及 hp ≤ 0 的场景物件（Walking Mausoleum）和调试行（ID 末四位 9999，如 hp 63936 的 Crucible Knight）。
- `Putrid Flesh`(c4171)、`Giant Skeleton Torso`(c4960) 在游戏文本里找不到对应条目，只保留英文名，列在 `notes.unmatchedNames`。
- 官方弱点标注（`weakness`）与实际承伤倍率不总是一致（例如史柴格斯标注为「无弱点」，但圣属性实测倍率 1.25），页面应两者并列展示。
- Paramdex 行名是社区标注，个别带问号（`Everdark Phase 1?`）或笔误（`Giant Crowd`），本数据集已做归一但仍可能有残留误差。
- 本数据集只描述数值，不含行为/招式/掉落。

### 战技／法术／武器数据集 `nightreign-skills-v1.03.5.json`（2026-09-22）

生成器：`macos/DataSources/generate_skills.py`（python3 标准库；默认路径可直接
`cd macos/DataSources && python3 generate_skills.py`，可选 `--params/--msg/--out/--pretty`）。
产物：`data/nightreign-skills-v1.03.5.json`，1.13 MB 紧凑 JSON，
`schemaVersion 1` / `gameVersion "v1.03.5 + DLC1"` / `dataVersion "regulation 10350000"`。
（**勘误**：上面的体积与 schemaVersion 是初版数据的口径；经后续两轮修复，当前文件为
`schemaVersion 2`、1,559,196 B ≈ 1.49 MiB，见本节末尾的第二轮补充与上方
「游戏数据集」总览表。原文保留不删。**再勘误**：2026-09-24 起为 `schemaVersion 3`、2,474,443 B ≈ 2.36 MiB，
见本节末尾「战技池（v3）」。）

#### 来源表

| 来源 | 内容 | 许可 | 用途 |
| --- | --- | --- | --- |
| 本机 regulation.bin（exe 1.3.3.0，容器版本号 10350000）经 `dump_regulation.py` 导出的 `raw/params/*.csv` | EquipParamWeapon、SwordArtsParam、Magic、AtkParam_Pc、Bullet、BehaviorParam_PC | 游戏数据，版权归 FromSoftware / Bandai Namco | 全部数值字段 |
| 本机归档 msg 经 `extract_msg.py` 导出的 `raw/msg/{zhocn,engus}/item_dlc01/*.json`（X.json + X_dlc01.json 合并，后者覆盖） | WeaponName、ArtsName、MagicName、NpcName | 同上 | 简中与英文名、ctxZh 的角色名 |
| [vawser/Smithbox@f5969c060cea240476e9dd4d6a64eafa9dbafaab](https://github.com/vawser/Smithbox/tree/f5969c060cea240476e9dd4d6a64eafa9dbafaab/src/Smithbox.Data/Assets/PARAM/NR) | Param Row Names（英文行名）、Param Meta（字段 Enum/Refs 标注）、Param Enums | MIT | 行名解析依据；枚举 WEP_TYPE、RARITY、ATKPARAM_ATKATTR_TYPE、MAGIC_CATEGORY、BEHAVIOR_REF_TYPE |

Paramdex 文件为本次临时 `curl` 到 `/private/tmp` 查阅，未写入仓库；生成器里只保留了从中
抄录的枚举映射表（WEP_TYPE / RARITY / ATKPARAM_ATKATTR_TYPE / MAGIC_CATEGORY）。

#### 字段映射

- 武器：`ID`→id，`WeaponName`→nameZh/nameEn，`wepType`（Enum=WEP_TYPE）→wepType/wepTypeEn/wepTypeZh，
  `rarity`（Enum=RARITY）→rarity/rarityEn/rarityZh，
  `attackBasePhysics/Magic/Fire/Thunder/Dark`→attackBase{physical,magic,fire,lightning,holy}，
  `saWeaponDamage`→poiseDamageBase，`swordArtsParamId` / `attackElementCorrectId` /
  `reinforceTypeId` 原样保留。
- 战技：`SwordArtsParam.textId`→`ArtsName`，`enableSparringGrounds`→sparring，
  weaponIds 由 `EquipParamWeapon.swordArtsParamId` 反查（v3 起再并上局内战技池，见「战技池（v3）」）。
- 法术：`Magic.ID`→`MagicName`，`mp`→mp，
  **kind 的依据是 `Magic.ezStateBehaviorType`**——Paramdex `Param Meta/Magic.xml` 对该字段标注
  `Enum="MAGIC_CATEGORY"`，枚举为 0=Sorcery / 1=Incantation / 2=Pyromancy；
  本作 160 条有名法术里 0 有 67 条、1 有 93 条、2 有 0 条，且与 `spEffectCategory`（3/4）完全同分布，
  互为交叉验证。（`refCategory1` 标注的是 BEHAVIOR_REF_TYPE，不是法术类别，已排除。）
- 分段命中：`AtkParam_Pc` 的 `atkPhysCorrection/atkMagCorrection/atkFireCorrection/
  atkThunCorrection/atkDarkCorrection`→motion，`atkPhys/atkMag/atkFire/atkThun/atkDark`→flat，
  `atkSuperArmor`→poise、`atkSuperArmorCorrection`→poiseMv，
  `atkStam`→stamina、`atkStamCorrection`→staminaMv，
  `atkAttribute`（Enum=ATKPARAM_ATKATTR_TYPE）→attribute/attributeZh，
  `isAddBaseAtk`→addBaseAtk，`overwriteAttackElementCorrectId`→overrideAecId。
  内部字段名 `dark` 即本作的「圣」属性，输出统一叫 holy。

#### 命中归属的五条路线（并集，逐段用 `source` 标注）

1. `n` — AtkParam_Pc 行名。解析 `[AoW <武器或类别>] <战技名> - <段标签>`、
   `[Sorcery]/[Incantation] <法术名> ...`。战技名用「已知名字的最长前缀匹配」提取，
   匹配键做过标点归一（吸收 Paramdex 的 `I Command Thee- Kneel!` 对 FMG 的
   `I Command Thee, Kneel!`），因此 `No FP`、`L2 #1-1`、`[Charged]`、`(Upward Cut)`
   一律落在段标签里。行名形如 `Chilling Mist/Poisonous Mist - Slash` 的共用行会拆开同时归给多个战技。
2. `b` — Bullet 行名同样解析；另外 `Magic.refCategory<i>=1` 的 `refId<i>` 也当子弹入口。
   拿到子弹后沿 `HitBulletID` 与 `intervalCreateBulletId` 展开子子弹（去重、上限 64），
   取每个子弹的 `atkId_Bullet` → AtkParam_Pc。这些段标 `isBullet` 与 `bulletIds`。
3. `r` — `Magic.refCategory<i>=0` 的 `refId<i>`，直接指向 AtkParam_Pc。
4. `a` — `SwordArtsParam.atkParamId` / `Magic.atkParamId` 锚点。弓系战技（贯穿箭、连射、
   拉满弓、魔法箭、天击、箭雨、拉塔恩之雨）的 AtkParam 行名是空的，只能靠这条捞到。
5. `w` — 兜底：前四路一无所获、且只有唯一武器引用该战技时，用该武器
   `behaviorVariationId` 在 BehaviorParam_PC 里 `behaviorJudgeId ∈ [900,950)` 的行
   （refType 0=攻击 / 1=子弹，依 BEHAVIOR_REF_TYPE）。
   **判定依据**：以尸山血海（behaviorVariationId 906）为例，该 variation 共 28 行，
   0/5/10/…/50 是普段，900–915 恰好是尸横遍野的 12 段；而通用武器（长剑 variation 200）的
   950–963 是野蛮咆哮、980–993 是战吼，与武器实际装的战技无关——所以 950 以上不能用，
   这条路线也只在「唯一武器专属」时启用。

同名战技（星云×2、流形×2、无法防御之刃×2、艾奥齐德的跳舞剑×2、萝蕾塔的剑技、回旋斩）
靠行名方括号里的武器名消歧：优先匹配 `SwordArtsParam.Name` 括号里的武器提示与引用武器的英文名，
都不匹配时归给没有专属武器提示的那个通用战技。

#### 推断与判断

- `atkSuperArmorCorrection`（削韧动作值，%）而不是 `atkSuperArmor`（固定削韧）才是近战武器攻击的
  主要削韧来源：尸横遍野 12 段的 `atkSuperArmor` 全为 0，`atkSuperArmorCorrection` 为
  75/100/75/75/100/200。两者都输出（poise / poiseMv），总削韧 = poise + 武器 poiseDamageBase × poiseMv/100。
- `atkSuperArmor`、`atkSuperArmorCorrection`、`saWeaponDamage` 在参数表里是**浮点**
  （186 / 34 / 557 行带小数，如 5.5、10.175、262.5、12.95）。生成器用 `to_num` 原样保留，
  不做取整——取整会把削韧算错。
- 全零行处理：`motion/flat/poise/poiseMv/stamina/staminaMv` 全为 0 时，
  若这段是「行名直接点名」的（source 含 n）就保留并打 `noDamage`（例如百智的世界、催眠火焰、
  哀悼墓碑、归于麾下这类只挂减益的战技），否则丢弃——后者都是子弹链顺带捞到的
  `Blank: Hit Enemy` / `No Target` / `[Spell Helper]` 之类辅助行。
- 武器类别中文名按 WEP_TYPE 枚举英文名逐项对应；Twinblade 译作「双头剑」（游戏简中用词），
  不是需求里写的「双刀」。稀有度中文（普通／优良／稀有／传说／独特）是对 Paramdex RARITY 枚举的
  译名，不是游戏内原文。

#### 已知局限（caveats）

- 尸山血海的「血刀气」在本作里不是子弹：Bullet 表中没有任何行的 `atkId_Bullet` 落在
  303400300–303400315；BehaviorParam_PC variation 906 的 900–915 全是 `refType=0`（直接攻击判定）。
  即血刀气就是这 12 个 AtkParam 行本身的判定框，`hits` 里因此没有 `isBullet` 段。
- `Magic` 里的 8000–8023「Magic Cocktail（魔法调合）」没有 MagicName 文本，按需求
  「MagicName 有名字的行」被排除在 spells 之外。另外 8100/8101「风暴管束者」的
  `refId1` 指向 10800000/10800100，也就是 8000/8001 调合法术的子弹（游戏内的数据复用），
  所以这两条的 hits 会带上调合系的 AtkParam 行——归属正确但名字看着奇怪。
- AtkParam_Pc 里 15 行 `[Sorcery]/[Incantation]` 前缀的行名匹配不到任何 Magic 行
  （Terra Magicus、Lucidity、Unseen Form、Fia's Mist、Cure Poison、Lord's Aid、
  Assassin's Approach、Order Healing、Bestial Constitution、Inescapable Frenzy），
  都是 Paramdex 沿用自《艾尔登法环》、本作未收录的法术，已确认不是漏匹配。
- 拉满弓（战技 402）的 `atkParamId=5000810` 在 AtkParam_Pc 里根本不存在；其余弓系战技的锚点行
  存在但数值全为 0——弓系战技的伤害走箭矢本身，本数据集不覆盖箭矢（EquipParamWeapon 里的
  箭／弩矢行已收进 weapons，但没有对应的 hits）。
- `label`→`labelZh` 是规则化词表翻译（约 100 个词条 + 20 个短语 + L2/R1/#N/1H/2H/No FP 模式），
  不是人工润色；已确认当前 315 个不同段标签全部无残留英文单词，但用词未必是玩家习惯叫法。
- 通用战技的 hits 很多（战吼 290 段、野蛮咆哮 358 段、盲击 22 段），是因为每个武器类别都有独立的
  一套动作值。排名页必须先按 `ctx` 过滤，否则同一招会被重复统计。

#### 第二轮核验修复补充（skills，schemaVersion 2）

（第二轮核验的交付说明原文，v0.3.0 文档收尾时按其要求并入本节。）

第二轮核验修复（regulation 10350000，schemaVersion 仍为 2，纯增字段、无破坏性改动）：

1. **武器物理伤害类型落地**。weapons[] 新增 `atkAttribute` / `atkAttributeZh` / `atkAttribute2` / `atkAttribute2Zh`（取自 EquipParamWeapon 同名列，枚举复用 enums.atkAttribute）。此前 2205 段命中里有 1065 段（48%）的 AtkParam_Pc.atkAttribute 是 253 / 252 的间接引用（「沿用武器的 atkAttribute / atkAttribute2」），数据集内无处可查，「按伤害类型加权做增伤排名」这一核心用途对这些段走不通。新增 usage["伤害类型（斩 / 打 / 突）"] 与 fieldNotes.weaponAtkAttribute 说明解析步骤，并指明与 bosses 数据集 fights[].damageRates（standard / slash / strike / pierce）的对接方式。为省 96 KB 体积未重复写英文名，英文名查 enums.atkAttribute[str(值)].en。

2. **overrideAecId 悬空引用不再写出**。生成时以 AttackElementCorrectParam 的 ID 列校验 AtkParam_Pc.overwriteAttackElementCorrectId；本版本 1001 火焰唾球的两段（303215900 / 303215901）指向不存在的 AEC 行 1005，已不写出该字段（记入 caveats）。写出的 overrideAecId 保证在表中存在。AttackElementCorrectParam 本身仍不收录，只读其 ID 列作校验。

3. **跨条目误配段统一丢弃**。SwordArtsParam / Magic 的 atkParamId 锚点与子弹链存在指向别的战技 / 法术的残留引用。判据为「该 AtkParam 行的 Paramdex 行名点名的技能与本条目的名字键完全不相交」，行名匹配路线（source 含 n）与 "A/B/C - Slash" 式真共用行不受影响。本版本丢弃 4 段：308 突进冲击←300000870 '[AoW] Spectral Lance'、1051 米凯拉的光环←301604902 '[AoW Cleanrot Spear] Sacred Phalanx'、1200 风暴管束者←300000700 '[AoW] Square Off - R1'、4381 罗蕾塔的绝招←43810 "[Sorcery] Loretta's Greatbow"。这 4 段原本就不在任何 variant 内，影响的只是 weaponIds 为空的条目所走的「显示全部 hits」回退路径。counts.hits 2205→2201、sharedAtkRows 13→9（uniqueAtkIds 仍 2191）。

4. **不可达动作套显式标记**。hits[] 新增 `noVariant: true`：该战技有 variants、但这个 atkId 不在任何 variant 内，即参数表里存着、本作却没有任何武器会打出的动作套（本版本 550 段，其中 441 段带 motion / flat；大头是 650 野蛮咆哮 268 段、651 战吼 246 段）。新增 counts.hitsWithoutVariant / hitsWithoutVariantDamaging 与 coverage.hitsWithoutVariantNote。没有 variants 的战技其 hits 不做标记。

5. **usage 里的统计数字改为生成时实测**，不再写死：按 ctx 取并集会翻倍的武器 173 把（原文案写 175）、旧 ctx 单选口径取不到段的武器 52 把（原文案写 51，漏算 1166 那把）。

本轮产物实测：紧凑 1,559,196 字节（1.49 MiB），--pretty 2,146,116 字节（2.05 MiB，仅人读、不入包）。counts：weapons 1793、skills 187（有命中 166）、spells 160（有命中 139）、hits 2201、uniqueAtkIds 2191、sharedAtkRows 9、variants 130、weaponsWithVariant 1150。（上一版自述中的 1,180,059 字节 / 2200 段为笔误；另回归说明里把 14010000 称作「高地斧」有误，该 ID 是分岔手斧 / Forked Hatchet，14080000 才是冻壳斧 / Icerind Hatchet。）

#### 战技池（v3，schemaVersion 3，2026-09-24）

**起因**：增伤排名页只列「有武器引用」的战技，v2 的武器引用只取 `EquipParamWeapon.swordArtsParamId`。
但本作局内拿到的武器几乎都是 `EquipParamCustomWeapon`（成品武器）行：`targetWeaponId` → 基础武器，
`swordArtsTableId` → `SwordArtsTableParam` 战技池，战技在池里按 `chanceWeight` 随机抽。
所以风暴刃（210）、狩猎巨人（116）这类只在池里出现的战技，v2 里一把武器都没有，页面上选不到。
`EquipParamWeapon` 里引用 210 的只有 9 行没有 WeaponName 的测试行（100000–101000，wepType 3、rarity 0），
引用 116 的一行都没有。

**新读入的表**：`EquipParamCustomWeapon`（5148 行）、`SwordArtsTableParam`（11896 行），
以及只用来判「custom 行会不会真的给到玩家」的 `ItemTableParam`、`ItemLotParam_map`、`ItemLotParam_enemy`、
`ShopLineupParam`。

**池的分组规则：同一个 ID 的全部行是一个池。** 证据：

1. `SwordArtsTableParam` 的 11896 行只有 841 个不同 ID（例：ID 10000000 有 44 行，每行一个不同的
   `swordArtsId`），ID 升序排列。`generate_buffs.py` 的 `pool_members` 对 `AttachEffectTableParam`
   用的是同一个惯例（22088 行、1081 个不同 ID），那边已经对上词条库 2200000 池的 283 个成员。
2. custom 行的 `swordArtsTableId` 去掉 -1 后有 497 个不同取值，**每一个**都正好是某个池 ID。
3. 带类别前缀的池（Paramdex 行名 `<Dagger>` / `<Untyped Straight Sword>` / `<Fire Katana>` …，
   池 ID = 类别序号 × 10⁷ + 变体 00 / 50 / 100 / 500–1200）只被「targetWeaponId 属于该类别」的 custom 行
   引用，按「同 ID」分组后类别和武器对不上的情况一例都没有。`<Table>` 前缀的是单把武器的专用池
   （例 11140000 只被 1140000 染血短刀引用）；ID < 1000 与 1000–1200 的都是单一战技池
   （116 = `[Standard] Giant Hunt` 权重 100，1200 = `[Legendary] Storm Ruler`）。
4. 行里的 `unknown_0` 全部是 1，不能用来分段。

**否决的候选规则**：

- 「从 tableId 那一行起，连续取到下一个被引用的起点」：这样 10000000 会把紧随其后的 10000010 也吞进来。
  10000010 这批 xx10 池没有行名，内容是同类别 xx00 池的全集，或「属性池 ∪ Untyped 池」
  （例 10000510 = 10000500 火焰短剑池 ∪ 10000050）。它们不被任何 custom 行引用，却被
  `EquipParamWeapon.swordArtsTableId` 引用（224 个不同值），说明它们本身就是独立的池。
  连续行分组会让同一战技的权重翻倍，和 xx10 被单独引用的事实矛盾。
- 「按 ID 区间分组」：单一战技池（100、116、503 …）夹在类别池之间，区间分组解释不了 custom 行直接引用
  单个小 ID 的写法。
- 任务说明里有一条线索：「长剑 custom 10 的 tableId=100 指向 10000000 起的 `<Dagger>` 池」。实测不是这样：
  custom 10 `[Common] Longsword` 的 tableId 是 100，而 100 号池只有一行 `[Standard] Lion's Claw`。
  另外这一行不可达，没有任何 ItemTable、ItemLot 或 Shop 引用它，所以不计入来源。

**行名不可靠**：custom 行和商店行的 Paramdex 行名常常和实际武器对不上。例如商店行
`[Rare Merchant - Set 0] Hand Ballista` 卖的是 custom 551004 `[Uncommon] Hand Ballista`，
但这一行的 targetWeaponId 是 3180000「大剑」，池 116 狩猎巨人。所以武器归属一律按 targetWeaponId 判。

**同池重复条目**：6 个池里有同一战技写了两遍，例如 50000000 刺剑池里 850 白影诱惑出现两次，
120000110 整池 20 个战技各重复一次。抽取时重复行等于权重相加，生成器按首次出现的顺序合并成一项。

**可达性**：只有被 `ItemTableParam`（itemCategory=6）、`ItemLotParam_map/_enemy`（lotItemCategory0N=6）
或 `ShopLineupParam`（equipType=6）引用的 custom 行才算来源。三处的引用分别是 4165、453、1554 条，
全部指向 `EquipParamCustomWeapon`，所以 6 就是 custom weapon。

- 可达的 custom 行 3860 行，其中 151 行的 tableId=-1，不抽池。按推断，这些行沿用基础武器自带的战技。
- 不可达的 1288 行里，1220 行本来就不抽池。
- 不可达行带来的唯一额外 (战技, 武器) 对是 300 盾牌冲击 → 32750000 守护者的大盾，来自 custom 320304。
  这一行只被 CharaInitParam 7509 引用，看起来是 NPC 的初始装备，不计入。
- 可达行的 targetWeaponId 全部是 10000 的整数倍（基础武器），而且都是有名武器。

**不作为来源的 `EquipParamWeapon.swordArtsTableId`**：这一列指向上面说的 xx10 池。局内掉落走的是
custom 行，参数表里看不出这一列在本作什么时候生效。如果把它也算进来，会多出 26419 个 (战技, 武器) 对，
绝大多数落在「毒长剑」这类属性变体武器行上，但不会让任何战技从「无武器」变成「有武器」。
所以没有收录，写在 caveats 里。

**字段**（详细定义见数据集 `fieldNotes` / `schemaChangelog`）：

- `skills[].weaponIds` 改为「固定引用 ∪ 战技池」，是取值范围扩大，字段含义不变。
- 新增 `skills[].weaponSources`：`{id, fixed?, pool?: [[池 ID, 权重, 可达 custom 行数], ...]}`。
- 新增 `weapons[].skillIds`、`weapons[].skillVariants`（`{战技 ID: variants 下标}`）和
  `weapons[].customWeapons`（`[[customId, 池 ID], ...]`）。
- 新增顶层 `swordArtsPools`（`{池 ID: [[战技, 权重], ...]}`）。
- 新增 `coverage.skillsWithoutWeapons`、`coverage.skillsWithoutFixedWeapons`、`coverage.skillsPoolOnly`，
  以及 counts 里 `skillsWithWeapons` 等 15 个计数。
- `weapons[].skillVariant` 语义不变，仍只指固定战技。
- `self_check` 新增断言：
  - 210 与 116 有武器，且全部来自战技池；
  - 每个 pool 项的行数都等于 `customWeapons` 里同池的行数，并能逐行回溯到原始 custom 行
    （target、tableId、可达性都要对上）；
  - skills 与 weapons 两侧的反向索引完全一致；
  - 同一战技里同一武器类别只落进一套动作；
  - 无名测试行不收录。

**选段（variants）口径的三处修正**。新增的 (战技, 武器) 对要逐一用 BehaviorParam_PC 实解。
这个过程中发现 v2 的实解缺了一级回退：

1. **三级回退**：先取武器自己的 behaviorVariationId，找不到时取整到百位（例 1406 → 1400、117 → 100），
   再找不到才用 0 号通用行。v2 只有「自己 → 0」两级。证据有两条：
   - 1200 风暴管束者的 10 套角色动作挂在 variationId 0/100/500/900/1100/1102/1800/2100/2300/4100 上。
     这些值正好是各渡夜者专属武器的 behaviorVariationId（117/503/900/1100/1102/1800/2151/2304/4100）
     取整到百位的结果；追踪者的 300 没有专属行，落到 0 = Default 套。取整结果与 Paramdex 行名里的
     角色名逐一对上。
   - 补上这一级后，每个战技里同一武器类别只落进一套动作，没有例外。只用两级回退时，只看固定武器
     就有 110、650、651 三个战技出现同类别拆成两套；按 v3 的全部武器看，108、109、110、118、120、124、
     650、651 共 8 个战技出现这种拆分。v2 caveats 里「1400 的斧走 Small Weapon、1406/1407 的斧走
     Large Weapon」就是这一级缺失造成的；补上后 110 盲击的 Small Weapon = 曲剑、锤、连枷、斧，
     Large Weapon = 大剑、大曲剑、大锤、大斧。
2. **只看有专属行的行为组**：1200 的 Default 套除了 base 400000000，在 base 500000000 还挂了一份 0 号行。
   解析时只看「这把武器在其中有专属行」的那个组，女爵、学者、执行者、送葬者、隐士、守护者、复仇者、无赖
   才能各自解出自己的角色套。这条规则只在解出的具名套多于一个时才介入。
   铁之眼的弓（variationId 4100）只有 No FP 四段挂在 4100 上，带 FP 的四段挂在 5000 上；5000 是
   铁之眼箭矢 50030000 的 5050 取整后的值，弓的子弹行为按箭矢的 variationId 解。所以这把弓按
   武器名里的角色名整套选 Ironeye，`via = "ctx"`。
3. **103 回旋斩的手工表补齐**：103 经战技池还能出现在短剑、大剑、刀、斧、大斧、矛上，行为表同样分不出来，
   按动作族补齐：大剑、大斧 → Large Weapon；矛 → Polearm；短剑、刀、斧 → 默认套。这是推断，
   依据是 110 盲击与 118 罗蕾塔的斩击实解出来的动作族。Large Weapon 与 Polearm 两套数值完全相同。

**变化统计（对比 v2，regulation 10350000 不变）**：

- **hits 不变**：2201 段逐段一致，唯一例外是派生标记 `noVariant`，从 550 段降到 59 段
  （其中带 motion / flat 的从 441 段降到 44 段）。
- spells 完全一致；weapons 的旧字段（skillVariant 除外）完全一致；带 skillVariant 的武器仍是 1150 把。
- variants 从 130 组增加到 223 组。
- 因为 variants 重新排序，164 把武器的 skillVariant 下标变了，但它们实际选出的段只有 58 把不同。
  这 58 把都来自三级回退：109 连击 1 把、110 盲击 17 把（Large Weapon → Small Weapon）、
  650 野蛮咆哮 24 把（默认套 → 锤 / 大斧类别套）、651 战吼 16 把（默认套 → 斧 / 大斧类别套）。
- 有武器的战技从 133 个增加到 185 个。仍然没有武器的只剩 1 无战技、9999 ？？？ 两个占位条目。
- (战技, 武器) 对共 8817 个：固定 1793、池 7376，两者都有 352。有池来源的武器 360 把。
  用到的池 496 个、3764 个条目。
- **由「无武器」变为「有武器」的 52 个战技**（箭头后是基础武器数）：
  102 突刺 0→63、107 箭步（回旋斩） 0→63、111 回旋击 0→29、116 狩猎巨人 0→50、118 罗蕾塔的斩击 0→29、
  119 双吻毒蛾 0→38、120 转啊转 0→91、122 风暴袭击 0→34、123 唤起风暴 0→88、124 剑舞 0→85、
  200 辉剑圆阵 0→72、202 冰枪 0→24、204 鲜血斩击 0→40、207 熔岩火浆 0→44、210 风暴刃 0→64、
  212 撼地 0→34、214 炎击 0→117、216 落雷 0→144、217 雷击斩 0→85、219 卡利亚大剑 0→50、
  222 神圣光环 0→24、224 血刃 0→25、225 幻影共击 0→32、226 幻影枪 0→20、227 寒气冻雾 0→130、
  228 毒雾 0→129、305 卡利亚式奉还 0→42、306 风暴障壁 0→43、307 黄金格挡 0→40、308 突进冲击 0→63、
  309 托普斯的力场 0→42、404 宿灵射击 0→13、405 对空射击 0→13、406 箭雨 0→16、502 风暴足 0→172、
  504 雷电羊球 0→143、505 红狮子火焰 0→145、506 坠落震击 0→172、507 黄金坠落震击 0→148、
  508 黑暗波动 0→29、509 荷莱·露的撼地 0→115、600 决心 0→172、601 侍王骑士的决心 0→172、
  602 暗杀办法 0→23、605 共享圣律 0→148、606 切腹 0→70、607 岩石剑 0→168、652 野兽咆哮 0→115、
  701 无敌 0→60、702 圣域 0→60、802 潜雾猛禽 0→172、1200 风暴管束者 0→10。
  其中 600、601、602、606、701、802 这 6 个没有命中段（纯增益或位移），另外 46 个能进增伤排名。
- **武器数变多的其余 40 个战技**：10 无战技 232→272、100 狮子斩 8→76、101 贯穿 116→184、
  103 回旋斩 233→309、105 突击 62→87、106 箭步（上砍） 75→127、108 鲜血征收 1→64、109 连击 13→92、
  110 盲击 49→112、112 二连斩 8→82、113 主教冲锋 8→31、114 居合 17→19、115 准备架式 48→54、
  201 神圣刀刃 3→136、203 辉石魔砾 2→85、205 夺命拳 1→11、208 祈祷一击 1→37、209 重力 3→131、
  213 黄金大地 1→31、218 伟哉卡利亚 2→52、220 真空斩 8→102、221 黑焰漩涡 8→35、300 盾牌冲击 76→127、
  301 铁壁盾防 8→70、302 格挡 184→244、303 小圆盾格挡 9→24、401 连续射击 5→13、402 拉满弓 8→13、
  501 冻霜踏地 2→145、503 踢击 99→260、603 黄金树立誓 1→148、604 圣律 8→155、650 野蛮咆哮 96→230、
  651 战吼 50→189、653 山妖咆哮 18→64、654 夸耀咆哮 16→113、700 忍耐 83→243、800 碎步 99→256、
  801 猎犬步法 8→179、850 白影诱惑 1→122。其余 93 个有武器的战技数量不变（多为传说武器的专属战技）。
- 体积：紧凑 JSON 从 1,559,309 字节（1.49 MiB）增加到 2,474,443 字节（2.36 MiB）。
  大头是 weaponSources，约 526 KB。连续生成两次，除 `generatedAt` 外逐字节一致。

**三端现状**：本车道不改界面代码。三端目前都按 schemaVersion 2 读数据，也都只认 `skillVariant`。
Android 的 `GameDataKey.SKILLS` 要求 schemaVersion 必须等于 2；Windows / macOS 的测试断言
「variants 里的每把武器都用 skillVariant 指向这一套」。这些都需要后续车道改用 `skillVariants`
并提升版本号，失败清单见本次提交说明。上表里的 skills schemaVersion 已改成 3；
`windows/renderer/pages/README.md` 描述的是页面代码现状，仍写 2，等界面车道一起改。

### 增伤手段数据集 `nightreign-buffs-v1.03.5.json`

生成器：`macos/DataSources/generate_buffs.py`（Python 3 标准库，运行 `cd macos/DataSources && python3 generate_buffs.py`，不联网、结果确定可复现）。

#### 来源表

| 来源 | 内容 | 许可 / 用途 |
| --- | --- | --- |
| 本地导出参数表 `macos/DataSources/raw/params/*.csv` | regulation 1.03.5（容器 10350000）、exe 1.3.3.0。使用 SpEffectParam、AttachEffectParam、AttachEffectTableParam、EquipParamAccessory、EquipParamGoods、EquipParamWeapon、Magic、Bullet、PermanentBuffParam | 游戏内资料，仅用于同人工具数值展示 |
| 本地导出文本 `macos/DataSources/raw/msg/{zhocn,engus}/{item,menu}_dlc01/*.json` | AttachEffectName、AccessoryName、GoodsName、WeaponName、MagicName、PermanentBuffName、SpEffectName、SpEffectInfo（基础档与 `_dlc01` 增量合并，后者覆盖前者；所有文本已 strip 去除尾随换行） | 同上 |
| Smithbox Paramdex (NR) `vawser/Smithbox@f5969c060cea240476e9dd4d6a64eafa9dbafaab` | `PARAM/NR/Param Meta/SpEffectParam.xml` 的字段默认值；`PARAM/NR/Param Enums/` 的 ATK_SUB_CATEGORY、SP_EFE_WEP_CHANGE_PARAM、ATKPARAM_ATKATTR_TYPE、ATKPARAM_SPATTR_TYPE、SP_EFFECT_SPCATEGORY。均已转写为脚本内常量表，运行时不联网 | MIT |
| Smithbox Paramdex (ER) 同 commit `PARAM/ER/Defs/SpEffect.xml` | 字段日文说明（`攻撃側：物理ダメージ倍率`＝对已算出的伤害乘算；`物理攻撃力倍率`＝对攻击力数值乘算；`同一カテゴリ内での優先度（低い方が優先）`）。NR 的 paramdef 是精简版、不含日文说明，故用 ER 的同结构 paramdef 作字段语义参考 | MIT |

#### 字段映射

**倍率字段（78 项，顶层 `rateFields`）** —— 全部在 `SpEffectParam.csv` 表头逐一核对过，分组如下：

- 最终伤害倍率（减防后乘算）：`physics/magic/fire/thunder/darkAttackRate`、`slash/blow/thrust/neutralAttackRate`
- 攻击力倍率（减防前乘算）：`physics/magic/fire/thunder/darkAttackPowerRate`、`slash/blow/thrust/neutralAttackPowerRate`
- 攻击力加算：`physics/magic/fire/thunder/darkAttackPower`
- 特攻：`weakDmgRateA..F`
- 致命一击：`vitalSpotChangeRate`（本版本玩家侧未见非默认值，仍列出）
- 削韧／精力：`saAttackPowerRate`、`staminaAttackRate`、`subSaBonusRate_{Magic,Fire,Lightning,Holy,Poison,ScarletRot,Bleed,Blight,Frostbite,Sleep,Madness}`
- 异常状态累积：`poizon/disease/blood/curse/freeze/sleep/madnessAttackPower`、`poison/disease/blood/curse/frost/sleep/madnessInflictRate`
- 本作特有：`currentHealthAttackRate`（随当前血量追加攻击倍率）、`restageAttackRate`（公爵「重演」伤害比例，0.4／0.6）
- 开关（不单独算增伤）：`isUseAtkParamAtkPowerCorrect`、`isUseStatusAilmentAtkPowerCorrect`
- 消耗与量表（不直接增伤）：`arts/magic/miracle/shaman/goodsConsumptionRate`、`ultimateArtGauge*`、`ultimateArtDuration`、`characterSkillCooldownReduction`、`additionalCharacterSkillUse`、`magicEffectTimeChange`、`bowDistRate`、`regainRate`

**「针对战技／法术／绝招／跳跃／蓄力／防反／投射物」的实现方式** —— SpEffectParam 里**没有**这类独立字段。真正的机制是 `magicSubCategoryChange1..3`（枚举 ATK_SUB_CATEGORY），与普通 `AttackRate` 字段配合：112 战技攻击、111 蓄力战技、110 蓄力法术、102 跳跃攻击、103 防御反击、100 蓄力强攻击、122 角色技艺、123 绝招、105 远程武器攻击、104 连段最后一击、124 双手持、125 双持、127 冲刺、128 翻滚、129 后跳、130 近战武器攻击，另有 1–28 的魔法／祷告流派子类。再叠加 `magParamChange` / `miracleParamChange` / `shamanParamChange` / `throwAttackParamChange`（布尔，是否作用于魔法／祷告／秘术／投掷）、`wepParamChange`（左右手／自身／踢击）、`atkAttribute`（斩打突标准）、`spAttribute`（属性／异常状态）共同构成生效范围，全部输出在每条 buff 的 `scope` 里。

**来源链路**

- 遗物词条：`AttachEffectParam.passiveSpEffectId_1..3` / `onHitSpEffect`（标 `trigger`）/ `permanentSpEffectId` → SpEffectParam；中文名走 `attachTextId` → AttachEffectName（**不是**直接用 AttachEffectParam.ID，两者在部分行上不一致）；是否属于遗物词条池由 `AttachEffectTableParam.attachEffectId` 判定（942 个 ID）。
- 护符／饰品：`EquipParamAccessory.spEffectId_1..3` 指向的是 **AttachEffectParam**（Paramdex 元数据 `Refs="AttachEffectParam"`），需再经 AttachEffectParam 才到 SpEffectParam；物品名用 AccessoryName，词条名另存为 `sources[].effectNameZh`。
- 道具：`EquipParamGoods.refId_default` / `refId_1` / `level2RefId(_1)` / `level3RefId(_1)`，按 `refCategory`（BEHAVIOR_REF_TYPE：0 攻击、1 Bullet、2 SpEffect）分流；Bullet 再取 `spEffectIDForShooter` / `spEffectId0..4`；另加 `carrySpEffectId` / `emptySpEffectId`。名字用 GoodsName。
- 武器被动：`EquipParamWeapon.spEffectBehaviorId0..2` / `residentSpEffectId(1,2)`；名字用 WeaponName（先按行 ID 直查，未命中再退回 `id - id%100` 的基础 ID），强化等级已按基础 ID 归并。
- 魔法／祷告：`Magic.refId1..10` 配合 `refCategory1..10`；类别 2 直连 SpEffect（如「火焰啊，赐予我力量！」6050 → 1605000），类别 1 经 Bullet 再取子弹的 spEffect 字段（如「黄金树立誓」6600 → Bullet 10660000 → spEffectId0 = 1660000）。名字用 MagicName，并与 SpEffectParam 的 Paramdex 行名（含 `[Incantation]` / `[Sorcery]` 前缀）交叉确认。
- 永久强化：`PermanentBuffParam.spEffectId` / `graceSpEffectId`；中文名先按行 ID 直查 PermanentBuffName，未命中再用英文名匹配（关键道具段 100–160 的 ID 与文本 ID 不是稳定偏移，必须靠英文名匹配），再退回末位归零。
- 链式：从上述任一 SpEffect 出发，沿 `replaceSpEffectId` / `cycleOccurrenceSpEffectId` / `atkOccurrenceSpEffectId` / `applyIdOnKillSp` / `accumuOver(Under)FireId` / `applyIdOnGetSoul` / `necromancyActivationSpEffectId` / `revenantFamily_spEffectId_1..3` / `analyze*_effectId` 最多展开 3 层，并把物品来源逐层继承下去（油脂、触发型词条等都靠这条路径才对得上物品）。
- buff 自身的中文名备选：`spEffectTextId_1..4` → menu FMG 的 SpEffectName；`spEffectTextId_1` → SpEffectInfo 作 `descZh`。

#### 推断部分（非参数直连）

- **叠加规则**：`stackingRules.zh` 全文是依据 SpEffectParam 的 `spCategory` / `categoryPriority` / `saveCategory` / `stateInfo` 四个字段的参数结构推断，并结合 Paramdex 的 SP_EFFECT_SPCATEGORY 枚举语义（10 = Stack Self 可自叠、20 = Reset on Apply、100–204 = Remove Previous、1000–1006 = Apply Highest by Category Priority、10000+ = Apply First）。**未经木桩全面实测**，请当作参数层面的默认规则。
- **推断来源条目**：战技（Ash of War）、角色技艺／绝招／被动、以及少数角色专属遗物效果（如公爵 7290001、7010701）由游戏事件脚本（ESD/EMEVD）挂载，参数表里没有任何列指向它们。这部分用 Paramdex 社区行名的前缀白名单（`[Relic*]`、`[Talisman]`、`[Item*]`、`[Incantation]`、`[Sorcery]`、`[Weapon*]`、`[AoW]`、`[Skill - *]`、`[Ultimate - *]`、`[Passive - *]`、`[Magic Cocktail]`、`[Interactable Effect]`、`[Libra Deal]` 等）反推来源类型，每条都带 `sources[].inferred: true` 与 `paramRowCategory`。共 344 条 buff 只有推断来源。
- **HeroParam**：经 NR paramdef 核对，HeroParam **没有任何 SpEffect 列**；其 `heroStatusParamId` 只通向 HeroStatusParam，后者的 `attackRate` / `abilityReinforce` 是随等级变化的属性成长，不是 buff，故未纳入。角色技艺／绝招的增伤改由上面的推断来源覆盖。
- **dark = 圣**：沿用本项目既有结论，参数里的 `dark*` 槽位在本作对应「圣」属性。

#### 已知局限

1. 344 条 buff（41%）只有推断来源，其物品归属未经参数验证；113 条 buff 没有简体中文名（游戏内无对应 FMG 文本），保留英文名与 `paramName`。
2. `affectsAllies`（= effectTargetFriend 原始值）在绝大多数玩家侧 buff 上都是 1（目标掩码全开），**不能**据此判断队友是否共享。
3. 少数 `direction: "decrease"` 的条目其实是挂给敌人的 debuff（如「酸蚀喷雾」physicsAttackRate 0.85），本数据集不区分施加对象，页面应按 `direction` 过滤。
4. 8 条 buff 的来源超过 40 个（匕首／曲剑等大批武器共享同一出血被动），已截断并用 `sourcesTruncated` 标出真实条数。
5. 未覆盖：AtkParam_Pc 层面的攻击力倍率修正（`spEffectAtkPowerCorrectRate_*`）、多人缩放、敌人属性弱点；这些属于其他数据集的范围。

#### 第二轮核验修复补充（buffs，schemaVersion 3）

（第二轮核验的交付说明原文，v0.3.0 文档收尾时并入本文件；原标题「nightreign-buffs-v1.03.5.json — schema v3」。）

生成器：macos/DataSources/generate_buffs.py（离线运行，不联网）。数据来源与 v1/v2 相同：本地导出的 regulation 1.03.5（container 10350000）参数表 raw/params/*.csv、简中(zhocn)＋英文(engus) FMG 文本（基础档与 _dlc01 增量合并），以及转写进脚本常量表的 Smithbox Paramdex（NR，commit f5969c060cea240476e9dd4d6a64eafa9dbafaab）字段默认值与枚举。本轮未引入任何新数据源，未新增网络依赖。

v3 相对 v2 的变化（完整机读版见产物内的 payload.schemaChangelog）：

1. 新增 `buffs[].activation`（passive / conditional / activated）与 `buffs[].activationSource`。v2 的 notes.ranking 要求页面用 `conditions` / `triggered` 过滤掉有发动条件的 buff，但表中最大的几个倍率由 ESD/EMEVD 脚本开关、参数列里查不到条件，导致那一步在最需要它的条目上是空转的（704301「残血 25% 以下 ×1.5」、8300000-2「双手共持 +12/15/18%」、8310000-2「双手各持 +12/15/18%」、707201-215「处刑人绝招兽化 ×1.62–3.55」的 conditions 与 triggered 全为 null）。判定完全由数据推出、无写死 ID 名单：行名 `[...]` 前缀为 Ultimate/Skill/AoW → activated；行名含 while/whenever/when/upon/during/below/above/alongside/two-hand/wielding/stack → conditional（刻意不含 counter/critical/charged/chain——那是作用范围而非发动条件）；conditions 非空 / triggered / 「全部来源 inferred 且持续时间有限」→ conditional；其余 passive。**增伤排名默认只能乘 activation="passive" 的条目。**

2. 修正 `target` 判定对链式投递的漏判。Bullet 命中槽的识别正则原本带 `$` 锚，形如 `refId1->Bullet10631000.spEffectId0->cycleOccurrenceSpEffectId` 的链式 via 匹配不到，使 1631001『授血（血炎出血）』这条挂在被命中敌人身上的出血累积被标成 target="self"。证据：弹道 10631000/10631005 的 atkId_Bullet 均为 63100，AtkParam_Pc.63100 五个 atk*Correction 全为 100（攻击弹道），SpEffect 1631001 selfTarget=1/opposeTarget=1，按既有规则应判 enemy。现已改判为 target="enemy" / targetSource="bulletHitOffensiveBullet"，与同类的『冰雾』『毒雾』一致。全表仅此 1 条受影响。

3. 排除一条哨兵值行。704000『[Skill - Raider] Retaliate (Defense and Immortality)』的 characterSkillCooldownReduction=0 且 effectEndurance=0，真正负载是本数据集不读的 DamageCutRate=0.25 一组（无赖反击那一瞬的免伤窗口），按字面展示会变成「技艺冷却 -100%」并与真正的遗物档位 0.95/0.925/0.9 混列。排除规则刻意收窄为「全部合格数值都是 valueKind=multiplier 的 economy 字段且为 0，同时 effectEndurance=0」，因此 511060/708920『青露的秘密滴泪』与 1801400『魔法帷幕』（同样带 ×0 消耗倍率但有 15/20/8 秒持续时间、确实让施法免费）不受影响。被排除的行记入 diagnostics.sentinelOnlyRows，不再静默丢弃。

4. `enums.targetSource.bulletHitOpposeOnly` / `bulletHitFriendlyOnly` 的说明改写。effectTargetSelfTarget / effectTargetOpposeTarget 是「异常累积允许打给哪个阵营」的过滤位，不是「SpEffect 挂在谁身上」的证据：SpEffectParam 3176『[Item] Poison Grease (Right) - Poison』同样是 selfTarget=0/opposeTarget=1，却是玩家抹在自己武器上的油脂。这两个位只有在「该 SpEffect 的全部来源都只能由 Bullet 命中槽投递」的前提下才有判定力。判定代码本身一直是对的（本版本 13 条 bulletHitOpposeOnly 结论全部正确），改的是说明文字，以免后续维护者把规则推广到非弹道来源。

5. `displayNameZh` / `displayNameEn` 的消歧顺序调整（全表唯一性保证不变，生成时仍有断言）。新顺序：本地化来源名 → 强度档位 → 武器槽 → 来源类别（武器/遗物/护符/道具/战技/祷告/魔法/技艺/绝招/被动，取自行名 `[...]` 前缀，v3 新增的一级）→ 首个 rates 数值 → 原始英文 Paramdex 行名 → `#spEffectId`。同族（Paramdex 行名词干相同）的条目强制取相同的限定词组合。v2 里有 261 条中文名挂着英文行名做限定词（v3 降至 68 条），且同一档位序列会出现两种风格；v3 修掉了这两点，代价是 `#spEffectId` 兜底由 52 条升到 58 条（同族只要有一个成员需要 ID，全组都带）。实测数量见 counts.displayNameZhFallingBackToSpEffectId，完整 ID 清单见 diagnostics.displayNameZhFallingBackToSpEffectId。

生成时自检（self_check，每次生成自动运行，违反即抛错）在 v2 各项之外新增：activation / activationSource 必须落在 enums 内；有 conditions 或 triggered 的 buff 其 activation 不得为 passive；全部 via 都是 Bullet 命中槽的 buff 其 targetSource 不得为 "default"；不得输出「只靠 ×0 且无持续时间的 economy 哨兵值」入选的行。连续两次生成除 generatedAt 外输出完全一致。

#### 第三轮核验修复补充（buffs，schemaVersion 4）

（第三轮核验的交付说明原文，v0.3.0 文档收尾时并入本文件；原标题「nightreign-buffs-v1.03.5.json — schema v4」。）

生成器：macos/DataSources/generate_buffs.py（离线运行，不联网）。数据来源与 v1–v3 相同：本地导出的 regulation 1.03.5（container 10350000）参数表 raw/params/*.csv、简中(zhocn)＋英文(engus) FMG 文本（基础档与 _dlc01 增量合并），以及转写进脚本常量表的 Smithbox Paramdex（commit f5969c060cea240476e9dd4d6a64eafa9dbafaab）。本轮新引用了该 commit 下两份此前未用到的 Paramdex 资料，同样已转写进脚本常量表、运行时不联网：
- ER/Defs/SpEffect.xml 中 motionInterval 的日文字段说明（DisplayName「発動間隔[s]」、Description「何秒間隔で発生するのかを設定」），用于确定该字段是计时机制而非发动条件；
- NR/Param Enums/SP_EFFECT_TYPE.json（SpEffectParam.stateInfo 的枚举，NR ParamMeta 中 stateInfo 声明 Enum="SP_EFFECT_TYPE"），用于给 stateInfo 落中文标签并识别其中的攻击情境门（367 Enhance Critical Attacks、197 Enhance Thrusting Counter Attacks）。

v4 相对 v3 的变化（完整机读版见产物内的 payload.schemaChangelog）：

1. **activation 判定不再把计时列当成发动条件。** v3 的规则③是「conditions 非空 → conditional」，而 conditionFields 里混着两个纯机制字段：motionInterval（效果每几秒重新施加一次）与 isPeriodicEffect（是否按该间隔周期性重新施加）。全表 13472 行中 isPeriodicEffect 置 1 的 33 行逐行核对，全部是 tick／光环行（「[Weapon] Poison Buildup When Below Max HP - Apply Poison」等），两者都不是玩家需要满足的游戏状态。v3 有 210 条 buff 仅凭这两个字段被判成 conditional，其中 8 条是 target∈{self,ally} 的真实无条件增伤——708720 狂热香药·档位2 ×1.45、503550 狂热香药 ×1.35、1733000 夏玻利利的嘶吼 ×1.25、1605000 火焰啊赐予我力量 ×1.20、1660000 黄金树立誓 ×1.15 等，也就是整张表里最常用的几条消耗品与团队增益，按 v3 文档实现的页面会把它们全部排除在默认排名之外。现在只看 conditionFields[].isActivationCondition=true 的列；处刑人 Tenacity（707070/707071）改由新规则 paramRowPassiveTimed 判出（Paramdex 行名前缀为 Passive 且 effectEndurance≠-1——真正常驻的被动是 -1，带 18.5 秒时限说明有人把它打开过），1732『Golden Great Arrow』改由既有的 eventScriptTimedBuff 判出，都不再依赖那个 0.06 秒的 tick。共 73 条由 conditional 改为 passive，4 条由 passive 改为 conditional（见第 4 条）。

2. **新增 scope.attackContexts：作用情境的机读标记。** 游戏在两个互不相干的地方表达「这条倍率只对某种攻击生效」：magicSubCategoryChange1..3（ATK_SUB_CATEGORY，v1 起已导出为 scope.subCategories）与 stateInfo（SP_EFFECT_TYPE，v3 只是一个裸数字）。后者没有机读标记的直接后果是：6 条「强化致命一击」（stateInfo=367，×1.12–1.24）与 4 条「强化突刺反击」（stateInfo=197，×1.10–1.20）在页面看来是对所有攻击生效的常驻增伤——突刺反击那几条的 scope 甚至是 affectsSorcery／affectsIncantation／affectsShaman 全 true，比不标还更误导。v4 把两条来路归一化成 15 个情境键（致命一击、突刺反击、防御反击、连段最后一击、跳跃／冲刺／翻滚／后跳攻击、起手攻击、骑马攻击、蓄力强攻击／蓄力法术／蓄力战技、双手持、双持），配套 enums.attackContext（写明每个键的原始来源）与 enums.stateInfo（37 个观测值的中英文标签；本条原文误写为 36，JSON 一直是 37，第四轮第 3 条已勘误，此处直接改正）。**attackContexts 非空的条目不得原封不动乘进通用排名，只在用户勾选对应情境时参与乘算**，notes.ranking 第④步已据此改写。注意 attackContexts 与 activation 是正交的两条轴：这类条目装上就一直生效（activation=passive），受限的是作用范围而不是发动时机，所以第③步拦不住它们。武器／法术门类过滤（近战／远程武器攻击、战技攻击、各流派魔法祷告等）刻意不收进 attackContexts，它们属于伤害构成加权，仍只出现在 scope.subCategories 里。

3. **target 判定补上第二个命中槽，修正 33 条。** 命中投递槽的识别此前只认 Bullet.spEffectId0..4，漏了 SpEffectParam.atkOccurrenceSpEffectId（攻击命中时发动）。结果是：各种油脂与「附加属性武器」的异常累积行（3176 毒油脂、3151 催眠油脂、3191 出血油脂、1449001 冰霜武器、1632002 血炎武器、1723001 附毒祷告等）标成 target="self"，而结构完全相同、只是改由弹道投递的同类（1722000 毒雾、1631001 授血）标成 target="enemy"。以 3176 为例：effectTargetSelfTarget=0／effectTargetOpposeTarget=1，参数层面根本不允许挂在玩家身上，via 正是 refId_default->atkOccurrenceSpEffectId。现已按与弹道分支同构的规则处理，新增 targetSource 取值 attackHitOpposeOnly／attackHitSelfOnly／attackHitStatusPayload；33 条改判 enemy（全部落在 status／flag 轴，countsAsDamage=false，不影响任何伤害乘积），3 条正确留在 self（7036901「连段最后一击后提升攻击力」、8660203/8660206「致命一击附带出血」的攻击力加算）。**这些 target=enemy 的条目仍然是玩家的异常累积手段**，只是效果挂在被命中的对象身上；做「异常状态累积」榜时应按 sources[].kind 取玩家可获得的来源，不要沿用「只留 self／ally」的过滤。

4. **新增 stackLadder，并修正 4 条叠层词条的 activation。** 7069001「每次打倒封印监牢里的囚犯，能提升攻击力」在数据集里是 ×1.05 且 v3 判为 passive，会被无条件乘进排名；但参数表里 7069002–7069010 一路涨到 ×1.6289，7069201–7069210 涨到 ×1.9672，8988200「玛雷家的庇佑」与 8998000「复仇的庇佑」更是各有 100 层（×1.011→×1.70、×1.007→×1.40）。它们都要先反复达成条件才涨层，第 1 层的数值既不是无条件的、也不是该词条的上限。检测是结构性的、无写死 ID：ID 连续、Paramdex 行名为空、不是已收录的 buff、除倍率外 15 个列完全相同、非默认倍率键集合相同、至少一个 multiplier 且逐层严格递增，且 saveCategory≠-1——最后一条把「[Relic] Improved Throwing Pot Damage +1/+2」这类可分别装备的词条档位（saveCategory 全为 -1）排除在外。命中 4 条，全部改判 conditional（7069001/7069201 由 localizedNameCondition 判出，另两条由 stackLadderTier1 判出）。数据集仍只收录每条阶梯的第 1 层，满层数值见 buffs[].stackLadder.topRates 与 diagnostics.stackLadders；同层互斥（spCategory 落在 removePrevious 区间），任何时刻只有一层生效，绝不能把各层相乘。

5. **更正 v3 文档里一句与参数相反的结论。** v3 的 enums.targetSource.bulletHitOpposeOnly 与 schemaChangelog[0] 第⑤条都写「SpEffectParam 3176 毒油脂……来源是 EquipParamGoods，根本没走 Bullet 命中槽……本数据集正确地把它标成 target="self"」。该举例是错的：3176 走的正是 atkOccurrenceSpEffectId 命中槽，且 effectTargetSelfTarget=0。相关措辞已改写为「阵营过滤位必须在**已确认投递路径是命中槽**的前提下才有判定力」，并换上真实的保留反例——本版本仍有 42 条带 oppose-only 阵营位、却只能靠 Paramdex 行名或武器行为槽追溯来源、投递路径无法确认因而保守判成 self 的条目，完整清单导出为 diagnostics.opposeBitsWithoutHitSlot，并注明「这是缺省而不是已证实的结论」。v3 的 changelog 条目保留原文并追加「v4 更正」段落，不做静默覆盖。

6. 抽查清单口径调整：diagnostics.topUnconditionalMultipliers 由 15 条扩到 40 条，筛选条件加上「scope 里既没有 attackContexts 也没有 subCategories」，即真正会被原封不动乘进通用排名的那一批；受作用范围限制的 86 条改列在新的 diagnostics.contextGatedMultipliers（带 attackContexts／subCategories／gateFrom）。v3 的清单只取前 15 条、阈值卡在 ×1.28 且不区分作用范围，致命一击族与突刺反击族正好排在第 16 名开外，躲过了上一轮的人工抽查。

生成时自检（self_check，每次生成自动运行，违反即抛错）在 v3 各项之外新增 6 条：conditionFields 里 isActivationCondition=false 的键集合必须恰好等于 TIMING_CONDITION_FIELDS；带**非计时类** conditions 或 triggered 的 buff 其 activation 不得为 passive；每个 scope.attackContexts 取值必须落在 enums.attackContext 内，且必须能从该行实际携带的 subCategories 或 stateInfo 推出来；非 0 的 stacking.stateInfo 必须能在 enums.stateInfo 里查到；带 stackLadder 的条目 activation 必须是 conditional，且 tiers 与 tierSpEffectIds、topRates 与 rates 的键集合自洽；「全部 via 都是命中槽」的判定扩到 atkOccurrenceSpEffectId。连续两次生成除 generatedAt 外输出完全一致。本轮未 commit／push，未改 PROVENANCE.md，未触碰其它数据集。

#### 第四轮核验修复补充（buffs，schemaVersion 5）

第三轮独立复核报出 1 条 medium ＋ 3 条 low，全部核实成立并修复；schemaVersion 4 → 5，仍只增字段／只增取值。

1. **命中投递槽补全第三条路径，target 再修正 43 条 self→enemy。** v4 只把 `Bullet.spEffectId0..4` 与 `atkOccurrenceSpEffectId` 当作命中槽，`EquipParamWeapon.spEffectBehaviorId0..2`（武器命中时交给被命中者的负载）与 `AttachEffectParam.onHitSpEffect`（「攻击附带异常状态」词条的命中槽）没纳入，43 条与油脂行逐列同构的异常累积行仍是 self。依据：106010『Lvl 1-2 Poison +45』（毒匕首）与已判 enemy 的 3176『Poison Grease (Right) - Poison』除阵营位与投递槽外逐列相同；油脂真实链路是 `EquipParamGoods 1460 → SpEffect 3175（挂在玩家身上的 30 秒 buff）→ atkOccurrenceSpEffectId 3176`，累积值在链的外一跳；105000『Blood Loss +30』自带出血爆发伤害，不可能发给握刀者。判定按投递槽 → 阵营位 → 负载类型三问，结构性、无 ID 名单；新增 targetSource `weaponHitOpposeOnly`(5)／`weaponHitSelfOnly`(0)／`weaponHitStatusPayload`(38)。buffsByTarget：self 759→716、enemy 65→108。这 43 条全是 `rateGroups=["flag","status"]`，**伤害排名的乘积一个数都没动**；「异常状态累积」榜必须按 `sources[].kind` 取玩家可得来源，不能只留 target=self。
2. **新增 `buffs[].selfInflictedStatus`（20 条）标出自伤型异常累积**：target=self、阵营位 `S=1/O=0`、且带 status 组加算点数（`valueKind="flat"` 的 `xxxAttackPower`）的行（切腹自身出血 +9999、癫火系自身发狂 +30、血量未满时累积中毒等），累的是玩家自己；`xxxInflictRate`（「自身造成的累积倍率」，如艾奥尼亚蝶 diseaseInflictRate=1.3）方向相反，刻意不计入。异常累积榜需排除这 20 条。
3. **enums.stateInfo 以实测为准是 37 项**（第三轮说明里写 36 项的是散文错误，JSON 一直是 37 且与全表非 0 取值双向相等；该处原文已就地改正并注明）；新增 `counts.stateInfoLabels`，self_check 改为双向相等断言。
4. **stackLadder 口径写进 `notes.stackLadder`**：`tiers` 含第 1 层；`tierSpEffectIds` 从第 2 层起（长度 tiers-1，升序，不会作为独立 buff 出现）；`topRates` 为最后一层数值；`saved` = saveCategory≠-1。排除举例更正为参数表里真实存在的 7040300／7040301／7040302（后者是空行名 ×1.35，7040301 靠 saveCategory=-1 才没被误判成阶梯）。

self_check 新增：stateInfo 枚举与观测值双向相等；selfInflictedStatus 只出现在 target=self 且含 status 组的条目并三方计数一致；stackLadder 的 tierSpEffectIds 升序、不含自身、与已收录 ID 无交集；命中槽正则扩到 spEffectBehaviorId0..2 与 onHitSpEffect。

## 角色属性数据集（v0.3.1 规划）

（这段是给 PROVENANCE.md 用的文本，我没有改那个文件。）

## 角色属性（nightreign-heroes-v1.03.5.json）

生成脚本：macos/DataSources/generate_heroes.py（python3 标准库，`--raw` / `--out` / `--pretty`，自带 self_check）

### 上游数据
- raw/params/HeroParam.csv —— 10 个角色，characterNameId（288050+，指向 menu/CL_MenuText）、heroStatusParamId
- raw/params/HeroStatusParam.csv —— 三段：
  - 10000/20000/…/100000 起每人 4 行「[X] Level 1/2/12/15」= 角色基础属性锚点
  - 210000/220000/230000/240000/250000 起各 4 行「[Libra - Strength/Dexterity/…] Level 1/2/12/15」= 利普拉交易后的整套替换表
  - 300000–309101 每条 2 行「[X - +A/-B] Level 1 / Level 12」= 转职遗物的属性增减量
- raw/params/AttachEffectParam.csv —— 6640000–6647500 共 20 条转职遗物词条；passiveSpEffectId_1 → SpEffect，attachTextId → item/AttachEffectName，allowWylder…allowUndertaker 给出角色归属
- raw/params/SpEffectParam.csv —— 7640000–7647500 的 heroStatusModifier 指向增减量行；46260–46264「[Libra Deal] Respec to …」的 heroStatusId 指向整套替换表，spEffectTextId_1 = 120700
- raw/params/CalcCorrectGraph.csv —— 100「HP Scaling - Vigor」、101「FP Scaling - Mind」、104「Stamina - Endurance」、220「Equip Load - Endurance」
- raw/msg/<zhocn|engus>/menu_dlc01/CL_MenuText —— 角色名（288050+）、血量/专注值/精力标签（10500–10502）
- raw/msg/<zhocn|engus>/item_dlc01/AttachEffectName —— 词条名（6640000+）、8 项属性名（19700000/19700010/…/19700070）
- raw/msg/<zhocn|engus>/item_dlc01/AntiqueName —— 遗物物品名
- raw/msg/<zhocn|engus>/menu_dlc01/SpEffectName + SpEffectInfo —— 120700「扭曲的重生」/「与恶魔谈判过后，能力值产生变化」
- raw/msg/<zhocn|engus>/menu_dlc01/EventTextForTalk —— 27570060–27570100 五个交易对话选项
- data/nightreign-relics-v1.03.4.json —— 遗物物品 ↔ 词条反查（可选依赖；缺失时 relicItems 为空数组）
- 行名（Name 列）来自社区 Paramdex，与 bosses/skills 用同一修订 f5969c060cea240476e9dd4d6a64eafa9dbafaab（MIT）

### 关键读法
1. **中间等级是算出来的，不是表里的。** 每个角色只有 4 行锚点（1/2/12/15），其余 11 级 = 相邻锚点线性插值后向下取整（floor）。该规则经三张外部表逐格验证，见「交叉验证」。
2. **派生值各吃一项属性**：血量←生命力(graph 100)、专注值←集中力(101)、精力←耐力(104)、负重上限←耐力(220)。100/101/104 的 adjPt 全为 1（纯分段线性），且本作用到的 [1,25]/[25,50] 两段斜率恰好是整数（血量 20/点、专注值 5/点、精力 2/点），所以这三项必为整数。
3. **转职遗物 vs 利普拉是两个不同字段**：AttachEffect → SpEffect.heroStatusModifier 是「在基础表上加减」；[Libra Deal] → SpEffect.heroStatusId 是「整套替换」。机制上不互斥，应为「先替换、再叠加」（按参数结构推断，未实测）。利普拉的 5 套表不分角色。
4. 5 笔交易共用一个 SpEffect 文本（120700），逐笔的可见文案只有 EventTextForTalk 的对话选项。

### 交叉验证（都写进了 JSON 的 crossChecks）
- 追踪者 1–15 级 165 格（8 属性取自 Fextralife /Wylder，血量/专注值/精力取自 eldenring.wiki.gg /Nightreign:Wylder）：**全中**。唯一例外是该 wiki 把 12 级精力写成 92（与 11 级重复），按 CalcCorrectGraph 104（耐力 24 → 50+48×23/24）应为 96，基线里按参数修正。
- 执行者 1–15 级 165 格（eldenring.wiki.gg /Nightreign:Executor）：**全中**，包括 12 级精力 96 —— 反过来佐证追踪者那一格是 wiki 笔误。
- 女爵 1–15 级 165 格（Fextralife + eldenring.wiki.gg，两边表一致）：**151 格中，灵巧列 1–14 级整列偏低 1～3**（15 级两边都是 45）。原因是官方补丁 1.02.2「提高了女爵升级时的灵巧成长」，两个 wiki 的表停在补丁之前。本数据集以 regulation 10350000 为准；差异逐格写在 crossChecks[].mismatches 里，self_check 断言「差异恰好只有灵巧 1–14 级」，以后任何一格意外变动都会立刻报出来。

### 推断（未实测，已在 caveats 与字段里标出）
- 转职遗物 13–15 级沿用 L12 值：社区资料把 L12 行的数字直接写成词条效果（如 Revenant「集中力 −11 / 生命力 +5 / 耐力 +5」= 305001 行；Raider「+17 感应 / −4 生命力」= 304101 行），并说明等级越低偏移越小。2–11 级的逐级数值没有公开实测 → levels[].inferred = true。
- 取整方向：基础表全非负，floor 与 trunc 无法区分；转职遗物有负数，两者差 1。本数据集 delta 用向零取整，差异等级另给 deltaFloorAlt。
- equipLoad：本作没有装备重量、界面也不显示负重，CalcCorrectGraph 220 很可能是从《艾尔登法环》继承下来的遗留行；且 220 的 adjPt_maxGrowVal2 = 1.1（[25,60] 段带指数），指数挂在哪一段没有第二处数据可交叉验证。页面建议默认隐藏这一列。

### 外部链接
- https://eldenringnightreign.wiki.fextralife.com/Wylder
- https://eldenring.wiki.gg/wiki/Nightreign:Wylder
- https://eldenring.wiki.gg/wiki/Nightreign:Executor
- https://eldenringnightreign.wiki.fextralife.com/Duchess
- https://eldenring.wiki.gg/wiki/Nightreign:Duchess
- https://www.bandainamcoent.com/news/elden-ring-nightreign-patch-notes-version-1-02-2
- https://eldenringnightreign.wiki.fextralife.com/Relic_Effects

### 核验修复补充

以下为 PROVENANCE.md 的来源说明文本（按要求未直接写入文件，请脚手架代理合并）：

### nightreign-heroes-v1.03.5.json（角色属性 / 转职遗物 / 利普拉的交易）

**生成脚本** `macos/DataSources/generate_heroes.py`（python3 标准库，自带 self_check）
**产物** `data/nightreign-heroes-v1.03.5.json` → `scripts/sync-data.sh` 同步到 `windows/resources/heroes.json` 与 `macos/Sources/NightreignRelicChecker/Resources/heroes.json`（三份字节一致，sha256 `1640d3cb6f2f0eb8844bd44697ac6c2a507bf9c99195cd17f1e1d1fb37d4b0d1`）

**一次来源（游戏本体，regulation 10350000 / exe 1.3.3.0，v1.03.5 + DLC1）**
- `raw/params/HeroParam.csv` —— 10 个渡夜者，`characterNameId` → CL_MenuText 288050+
- `raw/params/HeroStatusParam.csv` —— 基础锚点表（10000+，每人 Level 1/2/12/15）、利普拉整套替换表（210000–250003）、转职遗物增减量行（300000–309101，每条只有 L1/L12）
- `raw/params/AttachEffectParam.csv` —— 6640000–6647500 共 20 条转职遗物词条（`attachTextId`、`allow<角色>` 位、`passiveSpEffectId_1`）
- `raw/params/AttachEffectTableParam.csv` —— 随机池 → 词条的权重表（`chanceWeight` 基础权重 / `chanceWeight_dlc` DLC 权重，−1 = 不覆盖）
- `raw/params/SpEffectParam.csv` —— 7640000–7647500 的 `heroStatusModifier`（加减）、46260–46264 `[Libra Deal]` 的 `heroStatusId`（整套替换）
- `raw/params/CalcCorrectGraph.csv` —— 100 HP←生命力 / 101 FP←集中力 / 104 精力←耐力 / 220 负重上限←耐力
- `raw/msg/<zhocn|engus>/menu_dlc01/{CL_MenuText, SpEffectName, SpEffectInfo, EventTextForTalk}` 与 `item_dlc01/{AttachEffectName, AntiqueName}`（X.json + X_dlc01.json 合并，DLC 覆盖本体）—— 所有 zh/en 名称

**二次来源**
- Smithbox Paramdex (NR) `f5969c060cea240476e9dd4d6a64eafa9dbafaab`（MIT）—— paramdef 字段名与行名（`[Wylder] Level 12`、`[Libra Deal] Respec to Strength` 等）
- 本仓库 `data/nightreign-relics-v1.03.4.json` —— 遗物物品 ↔ 词条的反查（`relicItems`、随机池成员）。存在一个小版本差（1.03.4 vs 1.03.5），已写入 caveats。

**外部交叉验证（第三方，仅作核对，数值一律以参数表为准）**
- Fextralife《Wylder》+ eldenring.wiki.gg《Nightreign:Wylder》—— 追踪者 1–15 级 165 格全中（该 wiki 12 级精力写 92 与 11 级重复，按 CalcCorrectGraph 104 应为 96，基线里已按参数修正）
- eldenring.wiki.gg《Nightreign:Executor》—— 执行者 165 格全中
- Fextralife / eldenring.wiki.gg《Duchess》—— 165 格中 14 格不同，全部集中在「灵巧 1–14 级」，原因是补丁 1.02.2「提高了女爵升级时的灵巧成长」而两个 wiki 的表停在补丁之前；差异原样记录在 `crossChecks`，并被 self_check 钉死为已知差异集合
- Fextralife《Revenant Improved Vigor and Endurance, Reduced Mind》—— 页面原文「Decreases mind by 11, increases vigor by 5 and endurance by 5」＝ HeroStatusParam 305001（L12 锚点）
- Steam 社区讨论《New stat shifts are a mega trap.》—— 玩家 15 级实测：守护者 灵巧 31→50 / 力气 41→50 / 生命力 60→52（301001）、无赖 感应 10→27 / 生命力 56→52（304101）、隐士 智力 51→41 与 灵巧 +20（306000）、隐士 集中力 30→17（306101）；贴中作参照的裸属性（追踪者 力气 50 / 生命力 52、女爵 智力 42、执行者 感应 28）亦与本数据集 L15 一致
- Steam 社区讨论《Revenant Needs a Real Identity》—— 15 级复仇者裸装 血量 780 / 专注值 200 / 精力 90，带该词条后 880 / 145 / 100，与本数据集 L15 基础叠加 305001 后（生命力 40 / 集中力 20 / 耐力 26）经 CalcCorrectGraph 算出的值完全一致

**推断与未验证项（详见 JSON 的 `caveats` 13 条与 `interpolation`）**
- 中间等级 = 相邻锚点线性插值后 **floor**，已用追踪者全表逐格验证（`baseVerified: true`）
- 转职遗物只有 L1/L12 两个锚点：**13–15 级沿用 L12 已由上述 5 组 15 级实测确认**（`modifierAnchorVerified: true`）；**2–11 级的逐级数值与取整方向（floor vs trunc）仍未实测**（`modifierMidLevelsVerified: false`），delta 按「向零取整」给出，与 floor 结果不同的等级另给 `deltaFloorAlt`
- 利普拉的交易（`heroStatusId`，整套替换）与转职遗物（`heroStatusModifier`，加减）是 SpEffectParam 的两个不同字段，机制上可同时生效 —— 按参数结构推断，未在游戏内实测
- `equipLoad` 是未经实测的遗留值（本作没有装备重量，CalcCorrectGraph 220 带指数），页面建议默认不展示

**本次修订（2026-09）**
修了 5 处核验问题：① 随机池的中英文遗物名改为**按遗物 ID 配对**后整体排序（此前中英文各自排序，按下标配对会错译，例如 `端正的光耀暗淡情景` 被配成 `Deep Delicate Burning Scene`，正确是 `Deep Polished Luminous Scene`），并新增 `relicNames: [{zh, en, relicIds}]`；② 新增 `distinctNameCount` 与 caveat，说明 `relicCount`(72 件) 与名字数(12 个)不同量纲；③ 重跑 `sync-data.sh` 让三份副本字节一致；④ 修正 caveats/`derivedRule` 里「只用到 [1,25] 与 [25,50] 两段」的漏写（守护者 12–15 级生命力 54–60 用到 graph 100 的 [50,75] 段），并加 self_check 枚举真正用到的段；⑤ 把 `modifierVerified` 拆成 `modifierAnchorVerified`(true) / `modifierMidLevelsVerified`(false) 并补进外部证据；⑥ 新增 `statModifiers[].poolWeights` / `dlcOnly`，记录学者/送葬者 4 条词条在池 2200000 的基础权重为 0、仅 DLC 权重 40 生效。所有数值内容未变。

### 第二版（bossesSchemaVersion 3）：名字重对照、深夜深度与变异个体、多人缩放核实

（按要求没有改 PROVENANCE.md，以下为 bosses 一节的补充文本，可直接追加）

### bosses 数据集 schemaVersion 3（2026-09-23）

**新增上游参数表**
- `raw/params/ChaosMatchingCorrectParam.csv`（90 行）——深夜「深度」1–5 的数值缩放。`spEffect00..spEffect04` 依次对应深度 1..5，指向 `[Deep Night Scaling] Tier X, Depth N` 的 SpEffect 行。注意：本表与 `MultiPlayCorrectionParam` 共用同一套行号（7700–7780、98810…），但 `NpcParam.chaosMatchingCorrectParamId` 与 `multiPlayCorrectionParamId` 在 18 组行上**不相等**（如 mpc 7730 / chaos 7753 共 60 行），必须分别查表。
- `raw/params/ChaosMatchingRankControlParam.csv`（5 行，行名即 Depth 1–5）——每个深度的全局控制：诅咒遗物出现率、地图挑战权重、天变数量权重。**不含**任何血量/攻击倍率。
- `raw/params/ChaosMatchingMutationCategoryParam.csv`（46 行）——按（敌人类别 × 地图）给出每个深度**被变异的个数**（不是概率）。类别枚举 `MUTATION_CATEGORY`、地图枚举 `PATTERN_MODIFIER`（10–15 段）均来自 Paramdex Param Enums。
- `raw/params/SpEffectSetParam.csv`——变异个体（玩家口中的「红化」）的 VFX + 数值组合，行名 `Set: Deep Night Mutation - VFX + Scaling`。

**深夜三层链路（新解出）**
1. `NpcParam.chaosMatchingCorrectParamId` → `ChaosMatchingCorrectParam.spEffect0N` = 深度 N+1 的缩放行，带 `maxHpRate` / 五种 `*AttackPowerRate` / `staminaAttackRate` / `saReceiveDamageRate`，且**自身 `stateInfo = 2287`**。
2. 该 2287 状态点亮 `NpcParam.spEffectID0..31` 上 `invocationConditionsStateChange1 = 2287` 的 `[Deep of Night Everdark Scaling]` / `[DLC Deep of Night Scaling]` 修正行（把永夜之王/DLC 加成压回去）。
3. `NpcParam.chaosMatchingSpEffectSetParamId` → `SpEffectSetParam`：`spEffectId1` = 红光 VFX 档位（4480–4483，`SpEffectVfxParam` 150050–150053），`spEffectId2` = 数值档位（7200/7210/7215/7220/7230/7240/7241），少数行另有 `spEffectId3 = 4485`。

四层缩放的 `spCategory` 互不相同（常驻 0 / 深度 0 / 变异 203 / 人数 140）。依据 Paramdex paramdef：`spCategory` =「决定特殊效果互相覆盖行为的分类」，`categoryPriority` =「同一分类内的优先级（低的优先）」——分类不同即不互相覆盖，倍率**连乘**。

**名字来源口径变更（重要）**
简中名现在**只**来自游戏自带文本（`item/NpcName`、`menu/CL_MenuText`）。schemaVersion 2 里按《艾尔登法环》官方简中手工补的 14 条 `nameSource=manual` 译名，已逐条在 `raw/msg` 下 engus+zhocn 共 55 个 FMG 文件中检索「完全一致字符串」，命中数为 0，全部移出 `nameZh`，改挂在新字段 `nameZhFallback`（并由 `nameZhFallbackNote` 声明「不是本作游戏内文本」）。对照规则写死为结构性的：`NpcName` 文本 ID = 900000000 + chrId×1000 + 变体号（chrId = NpcParam 行号 // 10000），匹配键为 `norm()`（小写、只留 a-z0-9 和空格）；同英文名有单复数两种简中词条时优先取非「群/们/队」；全局命中的词条若是**别的 chrId 自己的 Paramdex 名**且本 chrId 另有词条则不许借用；放宽匹配只允许「游戏文本是 Paramdex 基础名的中心词」一个方向。每条名字都带 `nameEvidence`（fmg 文件 + 文本 ID + 原文）。

**新增第三方来源**
- `4laric/nightreign-enemy-rando`（`data/nr_enemy_roster.json` 的 `all_variants[].variant_name`、`data/nr_enemy_tags.json` 的 `name / tier / _confidence`，HEAD，2026-09 访问）——**只用于辨认** Paramdex 与游戏文本都没有名字的 chrId：c4504 = Elder Dragon Greyoll（confidence high）、c4603 = Stonedigger Troll、c7711/c7712 = Centipede Grub（tier grunt）、c7910 = Storm King（confidence auto/low）。c7931 / c7932 社区亦无名，保留「未知」。中文名仍只从游戏文本取，社区来源在 `nameSourceUrl` 标出。
- `Elden Ring Nightreign Wiki (Fextralife)`（2026-09 访问）——人数缩放交叉验证：格拉狄乌斯 11,328 / 22,656 / 33,984、永夜之王格拉狄乌斯 17,558 / 35,116 / 52,674、艾德雷 13,140 / 26,280 / 39,420 与本数据集逐位一致（削韧与八系承伤倍率同样逐项对上）；卡莉果 12,007 / 24,014 / 36,021 vs 本数据集 12,008 / 24,016 / 36,024，差异来自 `3392 × 3.54 = 12007.68` 的取整口径（本数据集四舍五入，Fextralife 截断），不是算法分歧。

**SpEffect 默认值口径**
`fullEffects.fields` 列出「与默认值不同」的字段。因为 `raw/` 下没有保存 Paramdex 的 Param Meta，默认值取 `SpEffectParam` 全表各列的**众数**——该表上万行、绝大多数列压倒性地是同一个值，在所有用到的列上与 Meta 的 `DefaultValue` 一致，且只依赖 CSV 本身，结果可复现（已验证连跑两次字节级一致）。

**常驻缩放判定修正**
常驻 SpEffect 的「是否中性」判定补上了五种 `*AttackPowerRate` 与 `staminaAttackRate`，因此 `permScalingIds` / `deepOfNight.permScalingIds` 在 27 处多出真实存在的「只改攻击力」的行（7799 Noklateo Lesser Threat ×1.2 攻击、7783 Mountaintop Giant Crow ×2.45 攻击、62750/62751 ×1.15 耐力削减等）。`hp` / `hpMultiplier` / `poise` / `damageRates` / `resist` / `scaling` 等既有数值零改动。常驻档位里存在只加物理的行（16178「×2.42 血 ×1.1 物理」），故攻击力按五属性分开记录。

#### 核验修复补充

（按要求没有改 PROVENANCE.md，以下是 bosses 一节可直接追加的文本。）

---

### bosses：schemaVersion 3 核验后的修订（1.03.5，本轮）

上一轮 schemaVersion 2 → 3 的产出经交叉核验发现 10 处问题，全部成立并已修复。生成器
`macos/DataSources/generate_bosses.py`，重新生成后跑 `zsh scripts/sync-data.sh`；
data/ 与 windows/resources/、macos/…/Resources/ 三份 sha256 一致，生成器两次运行除
`generatedAt` 外逐字节相同。结构相对 v2 仍为纯增量。

**1. Paramdex 模板行不再收录。** NpcParam 的 600030000 / 600030100 / … / 600030900 共 10 行
Paramdex 名以「- Template」结尾，是黑夜人偶十个角色的模板：数值与配对的真实行
（…0010 / …0110 / …）完全相同，但 getSoul = 0、rewardItemLot_1/2 = -1（真实行 getSoul 1000、
rewardItemLot 13xxxxxx），chaosMatchingCorrectParamId 也不同（模板 7740 / 真实 7780）。
schemaVersion 3 的 merge_key 加入 chaosCorrectId 后它们被拆成独立变体，且 npcId 更小，
会按「血量最高、同血量取 npcId 较小」的代表行规则抢走卡头并带错深度倍率
（复仇者深度 5 血量偏高 7.4%、攻击力偏高 33%）。现按与 …9999 调试行同一口径进
`notes.skippedRows`（4 → 14 行）。另给每个 fight/variant 新增 `noReward` 布尔，
供两端代表行排序使用。数值行合计 404 → 394。

**2. 深度档位结论修正：实战夜王是 Tier 4a，不是 Tier 3f。** ChaosMatchingCorrectParam
7760–7769 的 Paramdex 行名都是「Final Boss Threat」，但指向的深度档位不同：
7765 = Tier 2c、7766 = Tier 3e、7767 = Tier 4a，其余（7760–7764 / 7768 / 7769）才是 Tier 3f。
数据集 27 条 isMain 夜王战斗行里 26 条 chaosCorrectId = 7767（Tier 4a），仅救世旗手
哈尔莫妮亚的永夜虫 46410000 走 7760。Tier 4a 深度 1→5：血量 ×1.25 / 1.4 / 1.57 / 1.95 / 2.16，
攻击力 ×1.25 / 1.55 / 1.92 / 2.83 / 3.31，承受削韧 0.88 → 0.84，对玩家耐力削减 1.15 → 1.5。
caveats 与 notes.deepOfNightAudit 已按此改写，并新增一条提醒「不要按行名段推档位」。
depthStats 本身此前即正确（394 行逐行重算，0 处不符）。

**3. 简中名唯一性规则（新）。** nameZh 是两端卡片的主显示名，不允许同时挂在两组首领上。
放宽匹配（中心词 / chrId 独苗群体名）曾产生 3 对重名。现按证据强度裁决：
逐字命中 > 近似但 NpcName 词条属于本组自己的 chrId > 借别的 chrId 的词条；
唯一最强者保留 nameZh，其余退回 nameSource = english-only，被挡下的候选存入新字段
`nameZhRejected`，裁决记录见新键 `notes.nameCollisions`。结果：
黄金河马归 Golden Hippopotamus@5011（NpcName 905011000 逐字命中），
蚯蚓脸归 Large Wormface@4580（904580600 属于 c4580 自己），
石肤众王（903600530「Stoneskin Lords」）对 Alabaster Lord 与 Onyx Lord 强度相同、
本身就是群体名，两组都让出。重名 3 对 → 0 对；有简中名的组 101 → 97。
实现上这一步必须放在 (nameEn, nameZh) 合并之后，否则会把「同一只 Boss 分散在多个 chrId」
的正常组（王室幽魂 c4020+c4021、黑夜人偶 c60003+c61003）误判为重名。

**4. nameZhFallback 补全。** v2 那 14 条 manual 手工译名（《艾尔登法环》官方简中）此前只有
10 条进了 nameZhFallback，另外 4 条（雪花石之王 / 缟玛瑙之王 / 大型黄金河马 / 废弃物蚯蚓脸）
只留在 notes.nameChanges 里、页面拿不到。规则改为「现在的 nameZh 不等于旧译名就写」，
并在同名去重后重算，现 14 条齐全。nameZh + nameSource 仍是「这名字是不是游戏里的」唯一判据。

**5. 事实性更正（不影响数值）。**
- ChaosMatchingCorrectParam 90 行里 ID 0 那行 spEffect00..04 全为 -1；其余 89 行归并成
  **25** 组档位（原文写 26）。deepOfNightTiers 收录 22 档，与数据集实际用到的 22 个
  chaosCorrectId 一一对应，无悬空引用。
- 深夜修正行与深度行的 spCategory 并非「都是 0」：深度行 877xxx 是 0，
  [Deep of Night Everdark Scaling] 7330–7348/7355/7356 是 20（7342/7344/7355/7356 为 100），
  [DLC Deep of Night Scaling] 7395–7398 是 0。分类互不相同 → 互不覆盖 → 连乘，结论不变。
  另复核：数据集用到的全部 NpcParam 行里，没有任何一行出现两条非中性效果共用同一个
  非 0 spCategory，hpMultiplier 连乘安全。
- 人数缩放 SpEffect 的非默认字段集合补齐：除已列出的倍率类外，还有
  effectTargetFriendlyTarget / effectTargetOpposeTarget / magParamChange / miracleParamChange
  四个作用目标标记位（136/136 恒为 1）与 spCategory = 140 / stateInfo = 282；
  Spirit Creatures（7770–7779）的 45696/45697 两行带 invocationConditionsStateChange1 = 413，
  该档位本数据集未使用。均非数值，结论不变。
- mutationCategories 的 categoryZh / mapZh 与 mutations 的「变异个体」是按 Paramdex 的
  MUTATION_CATEGORY / PATTERN_MODIFIER 枚举与 CL_MenuText 语义译出的**标签**，
  游戏文本里没有这些独立词条（已检索全部 zhocn FMG）。caveats 里「简中名只来自游戏文本」
  只约束 nightBosses.nameZh 与 nightlords 的名字。categoryEn / mapEn 与枚举逐字一致。

**6. 两端数据自检同步。** 数据契约变更必须同步的断言已更新（未改页面逻辑）：
`windows/tests/bosses.test.mjs`（schema 2→3；manual 样本替换；counts.night 51→50、
counts.rows 384→394；「河马」搜索断言改按英文名并校验 nameZhFallback）与
`macos/Sources/RelicCoreChecks/BossDataChecks.swift`（unmatchedNames 2→16；
Cemetery Shade 徽标 manual→englishOnly；chrid-fallback 样本 c4504→c7931；
inventorySummary 守夜 51→50、数值行 384→394）。
现状：Windows 8 个测试文件全绿，macOS RelicCoreChecks 11718 项全过。

**7. 已知未尽项。** 血斑巨乌鸦 c4561 与冰霜螯虾 c4420 两组里，没有 Paramdex 行名的真实行
因 npcId 较小而顶上卡头、标签显示为「基准」（两行数值一致，只差能否变异）；
彻底解决需要两端代表行排序在同 hp 时优先取 paramdexName 非空或 noReward = false 的行，
本轮未动页面代码，已在 caveats 里点名。另外 4 组让出 nameZh 后不再能用中文搜到
（搜索串不索引 nameZhFallback），同属页面侧待办。

#### 第二版核验修订（bosses，schemaVersion 3 仍为纯增量）

第二轮交叉核验报出 8 处问题全部成立并修复；生成器新增 `measure()`（caveats / notes 引用的统计数字改为生成时从产物实测拼出）与 `self_check()`（2960 项，写文件前运行）。

1. **整数血量取整统一**（唯一数值变化）：原 `round(float × float)` 在恰好 .5 时方向不一致；现统一为「倍率量化到 6 位小数（即公布的 hpMultiplier）后 Decimal ROUND_HALF_UP」，保证页面用 `hpBase × hpMultiplier` 能逐位复现。影响 4 条记录各 +1（大口龙三个变体 5398→5399、神皮贵族 5548→5549），其余零变化。
2. `notes.unmatchedNames` 只留游戏文本里查无此名的 12 条；4 条「匹配到但因重名让出」的只记在 `nameCollisions`。
3. 占位串「未知敌人 cXXXX」移出 `nameZh`，新增 `displayFallbackZh`（仅 c7931/c7932）；显示名推荐顺序：`nameZh` → `nameZhFallback`（标非本作文本）→ `displayFallbackZh`（标无游戏内名称）→ `nameEn`。实测：`nameZh` 为空 21 组（16 english-only / 3 community / 2 chrid-fallback），`nameZhFallback` 14 组，`manual` 0 条。
4. `deepOfNightTiers` 新增恒非空的 `tierLabel` 与 `tierSource`：22 个 chaosCorrectId → 13 个档位名 → 只有 7 张互不相同的数值表；98810/98815 两条行名无 Tier 段，`tier` 保持 null。
5. `scalingTiers.*.fullEffects` 新增 `fieldUnits`（multiplier / percent / flag / enum），生成时断言每列都已登记。
6. 事实性更正：夜王各深度出现权重 18 条逐条实测（玛利斯 500/400/325/250/250、哈尔莫妮亚 1600/1280/1040/800/800、史柴格斯 1120×5、布德奇冥 700×5 等），唯一普适结论是永夜/救世旗手形态深度 1 权重恒为 0；深夜修正行 spCategory = 20（少数 100）、DLC 深夜修正与深度行 = 0（0 表示不参与覆盖，连乘成立）；ChaosMatchingCorrectParam 90 行 → 89 行归并 25 组；人数缩放 136 条上恒为 1 的 4 个字段是 0/1 开关位而非倍率。
7. 两端数据断言同步（只改断言）：Windows bosses.test.mjs 的名字回退口径、macOS BossDataChecks 的 unmatchedNames 12 与 chrid-fallback 显示名。

## 增伤数据集第六版（按来源槽位与生效范围重构）

## buffs v6（schemaVersion 6，2026-09-23）

- **生成器**：macos/DataSources/generate_buffs.py。纯标准库，不联网，输出确定（连续两次生成除 generatedAt 外完全一致）。输出到 data/nightreign-buffs-v1.03.5.json，并用 scripts/sync-data.sh 同步到两端的 resources。
- **v6 新读取的参数表**（regulation 1.03.5，raw/params）：
  - EquipParamCustomWeapon、ItemTableParam、ItemLotParam_map、ItemLotParam_enemy：局内武器词条池、可掉落武器行、isCursed
  - EquipParamAntique、AntiqueStandParam：遗物词条池、固定词条遗物、容器格数
  - CharaInitParam：武器格数（equip_Wep_Right/Left_1..3）
  - ChaosMatchingRankControlParam：深夜诅咒武器概率
  - LotResultSmallBaseAndSpot：封印监牢（Evergaol）点位数
  - AtkParam_Pc：subCategory1..5、throwFlag、isArrowAtk
  - Magic：subCategory1..2
- **v6 新读取的 FMG**（zhocn 与 engus）：AntiqueName、ArtsName、CL_MenuText（武器类别 60010–60175、角色名 288050+i、技艺 411010+i、绝招 413010+i、复仇者家人 332001–332003），以及按同一 ID 查 PermanentBuffName 和 AttachEffectName。
- **v6 新读取的本仓库数据**：
  - data/nightreign-affixes-v1.03.4.json：relicAffixes[].catalogEffectId 的对齐与 self_check
  - data/nightreign-relics-v1.03.4.json：extraAffixes，固定遗物专用的词条
  - data/nightreign-skills-v1.03.5.json：战技和法术的命中段 atkId，用于 attackIndex 和 appliesTo 的『人口』
  - **generate_skills.py 必须先于本脚本运行。**
- **Paramdex 依据**（vawser/Smithbox@f5969c0，只用来核对，已转写进脚本常量）：
  - NR Param Enums：WEP_TYPE、SP_EFE_WEP_CHANGE_PARAM、ATK_SUB_CATEGORY
  - ER Param Enums：ATK_PATAM_THROWFLAG_TYPE（2=Throw）
  - NR Param Meta：EquipParamCustomWeapon、AttachEffect(Table/Filter*)、EquipParamAntique、ItemTableParam
  - ER Defs：SpEffect.xml（wepParamChange『どの武器に対して効果を発揮するか』、magParamChange、throwAttackParamChange『投げ攻撃に対して効果を発揮するか』）、AtkParam.xml（subCategory、throwFlag）
- **推断而非实测的口径**（写进了 notes 和 slotRules）：
  - isCursed=1 的武器只在深夜掉落。
  - throwAttackParamChange=0 的增益也作用于致命一击（旁证：战技『决心』的 1691 与 1694 两行）。
  - wepParamChange=3 表示不作用于武器攻击。
  - spAttribute 是附加属性的负载，不是生效门槛。
  - 『赐福王的余威』每份相乘。
  - 护符 2 格：参数表没有这个字段，依据是用户说明和 CL_MenuText 338380。
  - 黑夜入侵者上限 4 层：按用户反馈。
- **验证**：
  - self_check 新增 self_check_v6：槽位、词条库对齐（requiresCurse/isCurse/compatibilityId 零差异）、appliesTo 与 scope 不矛盾、slotRules 数字等于实测、叠层字段、fixedRelics、attackContexts 推导规则。反例测试全部被拦下。
  - macOS RelicCoreChecks 12697 项全过。
  - Windows 的 ranker.test.mjs 与 ranker_crosscheck.test.mjs 共 107 项全过。

#### 核验修复补充

generate_buffs.py（schemaVersion 6，核验轮）补充：

1. 新读的数据：
   - 游戏文本 PermanentBuffInfo（zhocn＋engus，基础档与 _dlc01 合并），用作 permanent／runStack 条目的 descZh，出处记在 buffs[].descZhSource。PermanentBuffCaption 的 ID 与 PermanentBuffParam 对不上，没有使用。
   - 参数表 BehaviorParam_PC.csv（refType 0＝AtkParam），只用于近战人口旁证 diagnostics.meleePopulationCheck。
   - CL_MenuText 415010+i（角色能力名，与 411010+i 技艺、413010+i 绝招同一套角色顺序，例：415017 不屈＝执行者）。
   - ArtsCaption 604／605／1053 里的用词『死诞者』，作为 TAIL_PHRASES_ZH 中『Anti-Undead』的译法出处。

2. 封印监牢的实测依据（更正）：LotResultSmallBaseAndSpot 中行名含 Evergaol 的行共 320 个 patternId；每个 patternId 的点位数分布为 7 个点位 160 个、6 个点位 80 个、4 个点位 80 个；attachId 共 91 个，取值 520–763。此前变更摘要里写的『attachId 601–607』有误，不要写入。practicalMaxStacks=7 不变。

3. 赐福王的余威：PermanentBuffInfo#8970000 原文为『根据新发现的赐福数量，提升攻击力』／『Newly found Sites of Grace raise attack power』，层数单位是本局新发现的赐福数，不是打倒的首领数。每份 ×1.02、多份按 spCategory=10 相乘，仍是推断。

4. 深夜专属词条上限：在 2950 行可掉落的 EquipParamCustomWeapon 上逐行统计槽 4–6 中非诅咒、且池里含深夜专属 AttachEffect id（任何可掉落行的槽 1–3 池都不含的 id，共 96 个）的槽数，结果为 {1: 2007, 0: 943}。因此每把最多 1 条、6 把最多 6 条。可掉落池里带权重的 AttachEffect id 共 310 个，其中 146 个对应 buffs。

5. 武器槽位布局（池 ID 按百万位归族）：
   - 一般武器：501 或 808／-／-／610 或 620／501 或 808／505。
   - isCursed 武器：630／501 或 808／810–814，槽 4–6 与槽 1–3 镜像。
   - 20 行 [Hero]／[Unique] X+2 角色武器（101750002–141755002，由 ItemLotParam_enemy 13000000 起、行名为 [Night Assassin]／[Night Thief]／[Night Hunter]／[Night Witch] 等的掉落表给出）：[Hero] 为 601／-／-／601／602／620，[Unique] 为 601／603／630，槽 4–6 镜像。
   - 603000000、603000100、603000200 分别是 810000000、811000000、813000000 的成员子集，按赐福计。808xxxxxx 是单成员的固定词条池。

6. 近战人口旁证：179 个有名武器的 behaviorVariationId 在 BehaviorParam_PC 中引用、且有伤害的无名近战 AtkParam_Pc 共 3271 行，其中 3221 行带 130。不带 130 的 50 行里，47 行带 101（骑马攻击），2 行没有子类别（4600800、4600801），1 行只有 102。无名、无子类别的非投技非箭行共 470 行：213 行无伤害，257 行有伤害，其中 195 行 ID 在 1000000 以下。

7. 其他：
   - nameSource 取值 attachEffectNameById 本版本 0 条。8390000 在 PermanentBuffName 和 AttachEffectName 里都有同一段文本，按 PermanentBuffName 优先记，参数表里没有 ID 为 8390000 的行。
   - [Weapon Power] 脚本行按『同一百位的 SpEffect＋同名前缀』归到传说武器的 AE，例：8980002 → AE 9021400（passiveSpEffectId_1=8980000）→ 武器 2140000。
   - 7050301 归到 AE 7050100（passiveSpEffectId_1..3 分别为 7050100、7050200、7050300），括号里的『Exalted Flesh』对应 GoodsName 1210。


#### 复核修复补充

generate_buffs.py（schemaVersion 6，复核二轮）补充：

1. spCategory=20 的语义（Paramdex NR SP_EFFECT_SPCATEGORY：Reset on Apply）
- 按同一 SpEffect 重复获得处理，不是跨 ID 互斥。
- 实测依据：
  - SpEffectParam 里 20 类 1310 行。
  - AttachEffectParam passiveSpEffectId_1..3 的引用按 spCategory 计：20 类 1202、10 类 781、0 类 203、203 类 4。
  - 词条库 nightreign-affixes-v1.03.4.json 里被动全是 20 的词条，叠加性分布：不可叠加 126、不同级别可叠加 7、未知 7、可叠加 1。
  - 固定遗物『辽阔的光耀情景』同时带 7030602 和 7034402。

2. 200–299 系列按 categoryPriority 分组
- 这是推断，Paramdex 只把 200 标为 w/ Matching Priority。
- 各类别的行数与不同优先度数：

| spCategory | 行数 | 不同优先度 |
|---|---|---|
| 200 | 152 | 53 |
| 201 | 292 | 90 |
| 202 | 26 | 10 |
| 203 | 26 | 6 |
| 204 | 350 | 12 |
| 205 | 5 | 3 |
| 206 | 20 | 2 |

- 201：破露滴同一种的两档共用一个优先度（带火破露滴 511028／708940 都是 226；带魔力、带雷、带圣依次为 227–229）。
- 204：按优先度分成 12 组，每组是一段连续 ID 的存档阶梯。封印监牢 7069001–7069010＝11，黑夜入侵者 7069201–7069210＝13，玛雷家的庇佑 8988200–8988299＝5，复仇的庇佑 8998000–8998099＝4，遗物『每次打倒…强敌』各阶梯＝8／9／10…，24231–24245＝3（中间隔了 5 个其他类别的行）。

3. 累积阶梯
- 识别方法：SpEffectParam 中带 accumuOverFireId 的行，按『连续 ID＋同 stateInfo』归族，共 83 个累积行、62 族。
- 其中多档族：3554–3557 → 3558–3561、13865 → 13869–13872、49753、312501–312504 → 312505–312508、320800–320803 → 320804–320807、707050、7037600–7037603 → 7037604–7037607、8884201、8885201。阈值 17／30／45／60。
- 连续攻击类第 1–3 档是 spCategory 120（removePrevious），第 4 档是 20、effectEndurance=0、数值与第 3 档相同。

4. 游戏文本
- 矛护符 AccessoryInfo#2060（zhocn『能强化突刺攻击特有的反击攻击』／engus "Enhances counterattacks unique to thrusting weapons"），作为 stateInfo=197 对魔法、祷告、射击判 no 的依据。

5. 封印监牢的覆盖范围
- LotResultSmallBaseAndSpot 共 520 个 patternId，其中有行名的 320 个全部含 Evergaol 行。
- 另外 200 个（1000–1199）的行都没有行名：不使用 91 个监牢 attachId（520–763），但 smallBaseMapId 与监牢行有部分重合，是否含监牢未核。

6. 局内武器词条
- 深夜专属 AttachEffect id 共 96 个，其中正面 52 个、诅咒（isDebuff=1）44 个。
- 深夜专属正面词条的档位按池族：505／602 只有档位1；603、810–814 只有档位2。
- 常规池各档位的成员数（各武器组相同）：
  - 501x00000：档位1 54 个
  - 501x00100：档位2 51 个、档位1 3 个
  - 501x00200：档位3 48 个、档位2 1 个、档位1 2 个
  - 505x00100：档位2 51 个、档位1 20 个
  - 505x00200：档位3 48 个、档位2 1 个、档位1 19 个
- 有两个正面深夜槽的行共 2007 行，其中 1164 行的两个池有共同成员；同一把武器是否去重，参数表里没有字段。
- 武器 AE 的 compatibilityId 把同一词条的各档归为一组（例：8330100–8330102 都是 401020），exclusivityId 在 8xxxxxx 段全部为 -1。

7. throwAttackParamChange 的读法
- 与 Paramdex 字面相反，依据是带无条件伤害倍率且 throw=1 的 10 条：1694、1704、1711、1713（Throw Damage Adjust）；320900、7040200、7040201、8130000–8130002（stateInfo=367 强化致命一击）。

## 首领数据第三版（bossesSchemaVersion 4：按出场场合的多重归属 roles）

### 地图敌人放置（MSB）与出场场合（bosses schemaVersion 4，2026-09-23）
- 新增导出脚本 macos/DataSources/extract_msb.py（uv 脚本，依赖 pycryptodome 和 zstandard）。它复用 extract_msg.py 的 BHD5 解密、路径哈希和 DCX 解压。归档里只存路径哈希，所以脚本对 /map/mapstudio/mAA_BB_CC_DD.msb.dcx（每段 00–99）逐一计算增量哈希来找出实际存在的文件，共找到 402 张，全部是 KRAK 压缩。
- tools/oodledec 新增批量模式：`oodledec.exe <oo2core_9_win64.dll> --batch <manifest>`，manifest 每行格式为 `in<TAB>out<TAB>size`，这样一次 Wine 进程就能解完整批文件。原来的单文件调用方式不变。
- 本机实际执行的命令（exe 1.3.3.0 / regulation 1.03.5，CrossOver Steam bottle），整批约 100 秒：
  `uv run extract_msb.py --game "<Game>" --krak-batch-cmd "'<CrossOver wine>' --bottle Steam --no-gui 'Z:\…\tools\oodledec\oodledec.exe' 'Z:\…\Game\oo2core_9_win64.dll' --batch {win_manifest}"`
- 产物位于 raw/msb/，与 raw/params 一样不入 git：
  - MsbEnemyParts.csv：每个 Enemy / DummyEnemy part 一行，列为 map, partName, partType, model, entityId, entityGroupIds, npcParamId, npcThinkParamId, talkId, charaInitParamId。共 8701 行，其中 Enemy 7476、DummyEnemy 1225。
  - manifest.json：地图数 402，以及各地图的 part 数。
- MSB 布局对照 Smithbox 仓库 Documentation/Binary Templates/MSB/MSB_NR（TKGP 的 010 模板，与 Paramdex 同一修订 f5969c0）：
  - Part：type 在 +0x0C（2 = Enemy，10 = DummyEnemy），commonOffset 在 +0x60，typeOffset 在 +0x68；
  - PartCommon：entityId 在 +0x00，entityGroupIds[8] 在 +0x1C；
  - PartEnemy：npcThinkParamId 在 +0x08，npcParamId 在 +0x0C。
  - 抽查一致：m46_56（Field Boss - Bell Bearing Hunter）里放的是 31000010，m49_24（Night Boss - Bell-bearing Hunter）里放的是 31000020。
- generate_bosses.py（schemaVersion 4）新读取的输入：raw/msb/MsbEnemyParts.csv + manifest.json；参数表 LotResultPlayAreaParam、LotResultSmallBaseAndSpot、SmallBaseAndSpotAttachPoint、SmallBaseMapVariationParam、ChaosMatchingMutationEnemyTableParam、LotResultMapPatternFlag、SmallBaseEnemyLotMapCombinationParam、SmallbaseInvationNpcParam；文本 menu/TutorialTitle（特异地形名 403400–403440）和 CL_MenuText 146501/146503（初始日/中间日：夜晚）。缺少 raw/msb 时生成器会直接报错，并提示先运行 extract_msb.py。
- 场合判定口径（完整说明见生成器里的 ROLE_DEFS）：
  - 地图块被 LotResultPlayAreaParam.bossId1/2/extraBossId1/2 引用 → 守夜首领；其中挂 7741 档的行 → 守夜前哨；
  - 夜晚首领地图块又挂到大空洞 Tower Boss 挂点 → tower；
  - ChaosMatchingMutationEnemyTableParam 类别 160，或 SmallBaseEnemyLotMapCombinationParam 引用 → 封印监牢；
  - 抽选结果全部落在 Raid 修饰（600–604 / 10000 / 10001）→ 突袭事件；全部落在 180 修饰 → 黑夜势力事件；抽选行 modifier 424 → 持秤商人事件；defaultSmallBase 默认地块 → event；
  - 类别 120 → 野外首领；其余据点/地点地图块 → 据点首领；m60_* 开放地块 → 野外首领（地形变体 = 末段 ÷ 10）；
  - SmallbaseInvationNpcParam → 黑夜入侵者；
  - 夜王本体行：在夜王战场 m16/m18/m19 → 夜王战，否则 → 突袭或事件；
  - 只出现在首领战地图里、自身零奖励、同图另有掉奖励首领 → 随从/召唤物；
  - DummyEnemy 不计入；完全没有 Enemy part 的行 → 未放置。
- 验证：12735 项 self_check 全部通过；与 v3 产物逐键比对，原有字段 0 处变化；两次生成除 generatedAt 外逐字节相同；data/ 与两端 resources/ 的 sha256 一致。

#### 核验修复补充

bosses schemaVersion 4 review fixes (2026-09-23, generate_bosses.py):

(1) The 圣树骑士 example is c3252 卡利亚禁卫骑士 (Royal Carian Knight@3252). Evidence:
- WeaponCaption 18100000/18100800/31060000: 「“圣树骑士”罗蕾塔的武器」 (engus: 'Loretta, Knight of the Haligtree'); 18100000 also says 「身为卡利亚的禁卫骑士时受赐的武器」.
- ItemLotParam_enemy 23252000 (per-chrId numbering 2+3252+000) contains 18100000 罗蕾塔的战镰 and 31060000 白银盾. By the same numbering, 23251000 = c3251 (黄金戟 / 黄金树大盾) and 23250000 = c3250 (大龙爪 / 龙爪盾). NpcParam does not reference these lots.
- Conclusion: it is only a field boss (m46_54, m60_42_37_50), never a night boss.

(2) Rows at 7741 (prelude) in a night boss piece that also attaches to a Great Hollow tower get prelude only, not tower. The tower attachment is recorded in the prelude evidence note.

(3) A second summon criterion for mounts and helpers: rewardItemLot_1/2 and chaosMatchingRewardLotId are all ≤ 0, and getSoul ≤ 5% of a same-map row that has rewardItemLot_2 > 0. It applies in night boss pieces, towers and field boss pieces, but not on m60_* tiles.
- Hits: 31600010 and 31600020 (Funeral Steed; the night horse shares MSB entityGroupId 49285810 with its rider) and 77009010 (placed as model c2150 'Lightning Ball' with npcThinkParamId 0).
- Real co-bosses such as 31501020 and 50110020 are unaffected.

(4) A map mAA_BB_00_00 whose AA is one of the SmallBaseMapVariationParam piece areas, but with no SmallBaseMapVariationParam row and no references from any lot or attach table, is treated as inactivePiece. Today only m46_90 (Ancestor Spirit 46700020) qualifies.

(5) Using PATTERN_MODIFIER on LotResultMapPatternFlag.modifier and LotResultSmallBaseAndSpot.modifier is an inference. At Smithbox@f5969c0, Param Meta sets Enum on LotBaseMapPatternFlag.modifier, LotBaseSmallBaseAndSpot.modifier1/2 and MapPatternSet, but not on the LotResult* tables. Supporting evidence is measured and asserted at generation time:
- raid modifiers 600–604 and 10000 map one-to-one to the 'Boss Raid - … (X)' pieces;
- 10–15 match the pattern row names Standard / Mountaintop / The Crater / Rotted Woods / Great Hollow / Shrouded City;
- the all-180 pieces are 'Night Horde - …';
- 424 is on the Libra pieces.

Meteor evidence for the major-base default pieces: all 14 modifier-200 patterns attach a default piece, and 46801010 has rewardItemLot_2 6310000 '[Fallingstar Beast (Random Encounter)]'. However, 19 of the 33 default-piece lot rows are in non-meteor patterns. Confirming the role would need EMEVD.

(6) mutationCategories[].mapZh now comes from game text: 10 宁姆韦德 (PersonalScenarioObjective 1020), 11–15 from TutorialTitle 403420/403430/403400/403440/403410 「特异地形：…」. The v3 labels 林薇尔德, 陨石坑 and 笼罩之城 were not game text. This is a value-only change in schemaVersion 4.

Additional input files now read: ItemLotParam_enemy (row names and 23252000), and zhocn/engus PersonalScenarioObjective, WeaponCaption and WeaponName FMGs.


#### 复核修复补充

#### schemaVersion 4 第二轮复核修订（bosses，2026-09-23，generate_bosses.py）

1. **开放地图地块改按变异类别判定场合。**
   - v4 首版把 m60_* 地块上的行一律算 field，这是错的。
   - 解码：ChaosMatchingMutationEnemyTableParam 里 smallBaseId = 0 的行是开放地块的变异刷新点。Paramdex 给的字段名只有 mapUnk_1(u8) / mapUnk_2(u8) / mapUnk_3(u16)，按小端拼起来正好是 60XXYY，即地块 m60_XX_YY。这是**推断的解码**。
   - 生成时逐行断言：
     - smallBaseId = 0 的 667 行全部解码成 60XXYY（共 16 个地块），smallBaseId > 0 的行全部解码成 0；
     - 行号编码的是同一个地块与地形变体（60XXYY×1000+序号，或 10^6/10^5/10^4 位 = XX−40/YY−30/v）。
   - 适用规则：
     - modifierMapId1 = 10+v 的行只适用于地形变体 v；
     - modifierMapId1 = 0 的行通用，但 modifierMapId2/3 列出的变体除外；
     - 大空洞有自己的一套行。
   - 用坑道精英三行实测验证了这套规则：43511120 放在 0/5，46000110 放在 0/2/5，43401120 放在 0/3/5。
   - 判定规则：
     - 含 120 → 场景头目；
     - 没有 120 但有 150/151 → 新增场合 **mine「坑道精英」**；
     - 只有 110 → 据点首领；
     - 都没有 → 场景头目（只表示放在开放地图上）；
     - 大地块（LOD）按 part 名前缀里的原地块判定。
   - 本轮改判：
     - Troll (Mine) 46000110 → mine。证据：604436000 类别 150；奖励表 6130000「[Troll (Mine)]」。
     - 大空洞坑道的挖石山妖 46030010 → mine。证据：1602940006 类别 151；它是该地形变体上唯一带首领奖励表的首领档行。
   - 开放地块上仍标 field 但不带首领奖励表的 7 行，证据 note 里逐行注明「未必就是地图上标图标的那只」。

2. **开放地块上的零奖励行。**
   - 辅助实体判 summon：全部 part 换成别的模型、npcThinkParamId 为 0/1。NpcThinkParam 0/1 都是 logicId 11000、disableParam_NT = 1 的占位 AI。
     - 本轮命中：“冻结冰雾”玻列琉斯 45030020。模型 c0100；part 名显示原属 m60_43_39_10，同一 chrId 的首领行是 45030010。
   - 剧情敌人判 event（推断，EMEVD 未解析）：MSB part 与带 talkId 的实体同属一个实体组。
     - 本轮命中：神皮使徒 35600060。与 6 个带对话脚本的 c0100 实体同属实体组 1029405700，同图还有 Scholar NPC 521090000。

3. **标签改取游戏文本。**
   - 出处：TutorialBody 403200 地图图标说明「坑道入口 / 要塞 / 场景头目 / 封印监牢」（engus：Tunnel Entrance / Castle / Field Boss / Evergaol）。
   - roleNames.field.zh 改为「场景头目」。
   - 为保持一致，categoryZh 120（6 行）与变体 labelZh 的 (Field Boss)（21 个）也改成场景头目。
   - 变体 labelZh 的地形名与 mapZh 统一：陨石坑 → 火山口（3 个），诺克拉提欧 → “隐城”诺克拉缇欧（5 个）。
   - 以上都在生成时断言与游戏文本一致。

4. **突袭证据补 LotResultMapPatternFlag.targetBoss**（Paramdex Meta：Refs = NightBossMenuParam）。
   - 实测：520 个地图模式，每个 targetBoss 唯一，且与行名前缀「[夜王]」一致。
   - 每种夜王 Raid 修饰都从不出现在该夜王自己的远征里。例如 10001 Harmonia 出现在 20 个模式中，分布为 9×10，3/4/5/6 各 ×2，0/7 各 ×1，从不含 8/18。
   - 6 个突袭地图块的 placementMaps、以及哈尔莫妮亚突袭行的证据里，都写入了 targetBoss 分布。
   - 大空洞 5240/5245/5250/5255 四块改写为**推断**：
     - 它们自己的抽选结果没有一行落在 10001 模式里；
     - 同建筑的另一元素变体 5242/5246/5252/5257 各有 1 行落在模式 1177「[Straghess] Great Hollow (DLC)」里；
     - 是否启用要看 EMEVD。

5. **notes.roleAudit.examples 数量订正。**
   - 上轮修复说明写的是 10 条，但实际数据里是 9 条。
   - 本轮新增死亡仪式鸟、黑夜骑兵、恶魔王子三条，现为 12 条。self_check 断言条数与 ROLE_EXAMPLES 一致。

6. **统计变化。**
   - roleSummary：场景头目 39 → 35，随从/召唤物 10 → 11，地图事件 4 → 5，新增坑道精英 2。
   - caveats 47 → 48，末尾新增【场合】开放地图地块一条。
   - self_check 断言 15523 项全过。
   - 文件 1,594,753 字节。
   - 新读入：TutorialBody（zhocn/engus）、NpcThinkParam（0/1 行）、NightBossMenuParam（targetBoss 名称），以及 LotResultMapPatternFlag 的 targetBoss 列。

## 地图 MSB 提取（extract_msb.py）

为判断首领「放在哪张地图、何时进入远征」，新增 extract_msb.py（复用 extract_msg.py 的归档解密/哈希/解压，用 Smithbox 的 NR 文件字典枚举 /map/mapstudio/*.msb.dcx），oodledec 增加 --batch 模式一次进程解一整批 Kraken 数据；产物 raw/msb/ 不入库。

#### 增伤数据集第六版复核三轮补充

generate_buffs.py（schemaVersion 6，复核三轮）补充：

1. 『出击时的武器，附加…』的 4 档互为替代（exclusiveScope=affixVariant）
- 所属词条：AttachEffectParam 7120000、7120100、7120200、7120300、7120400、7120500、7120600。
  - passiveSpEffectId_1 都只指向同号的 SpEffect『[Relic] Starting armament … - Apply State Info』。
  - 这些行的 stateInfo=2101，全表只有这 7 行用它，本身没有倍率。
  - compatibilityId 同为 200，exclusivityId 同为 100。
- 档位行：7120x01–7120x04，SpEffectParam 里没有任何指向列指向它们，只能由上面的派发行选一档。
  - 魔力、火、雷、圣四条的 4 档：物理攻击力 −30／−40／−50／−60，属性攻击力 +33／+44／+55／+66。
  - 冻伤、中毒、出血三条的 4 档：都是 ×0.85，逐列相同，只差 atkOccurrenceSpEffectId（7120x05–7120x08）。
- 词条库说明原文是『根据武器类型降低物理攻击力30/40/50/60…』，叠加性为『不可叠加』。参数里没有武器类别与档位的对应表。
- 结论：同一词条的 4 档同一时刻只生效一档，改为共用键 "affix#<attachEffectId>"。
- 全表按『只归属一条词条、词条被动不是 buff、没有指向列、行名去掉 Potency N 后同干、除行名／倍率／指向列外逐列相同、原来按 ID 分键』扫描，只命中这 7 组。
- 没有合并的近似组：
  - 6500000：7500001/2，原来就共用类别键。
  - 6500800：7500801–03，由 analyzeSelfLevel1..3_effectId 分别指向。
  - 6610700：词条只引用 7610700，7610701/02 在参数里没有引用。
  - 7037700：7039900–09，原来就共用 sp206@p2。
  - 8690000／8690200／8690300：原来就共用类别键。
  - 8885200：持续时间与 vfxId 不同。
  - 7120x05–08：由 atkOccurrenceSpEffectId 指向。
- exclusivityId 的语义取自 Smithbox 注释（见本文件第 47 行）：只控制已装备遗物之间的红色感叹号。上述 7 条同为 100。『分装两件时只有一条生效』是推断，没有据此并键。

2. 武器词条 8885200『维持防御时，强化魔法、祷告与缩短咏唱时间』的三个阶段
- 链路：累积器 8885201–8885203（stateInfo=307，accumuOverVal 4000000／9000000／15000000，dedupeAccumuTrigger=1）
  → accumuOverFireId 8885210–8885212（behaviorId 900010020–900010022）
  → BehaviorParam_PC（refType=1，refId 98885200–98885202）
  → Bullet spEffectId0 8885220–8885222。
- 三条都是 ×1.1（另有 dexterityCancelSystemOnlyAddDexterity=30），spCategory=20，effectEndurance 28／25.5／22.5。
- 阈值差 5M／6M 与持续时间差 2.5／3 秒同为每秒 2,000,000，三段在第 30 秒一起结束。
- 游戏文本 AttachEffectInfo#8885200 原文为『维持防御时，能阶段性提升魔法、祷告的攻击力与缩短咏唱时间』（英文 "Continued guarding gradually enhances…"）。
- 结论：三段同时存在、逐段相乘，最多 ×1.331，各自保留原来的键。这是推断，未实测。
- 同一识别方式（累积器 → 行为 → 子弹 → buff）在全表只命中这一族；8884201（Shielding Creates Holy Ground）的子弹不带 SpEffect。

3. 自身行与队友行（buffs[].selfAllyPair）
- 共享圣律：
  - AtkParam_Pc 300000820『[AoW] Shared Order』的 friendlyTarget=1、selfTarget=0、spEffectId1=1871；1871 的 cycleOccurrenceSpEffectId=1877。
  - 自身侧是 1870（spCategory 160），1875（无行名，8 秒）的 cycleOccurrenceSpEffectId=1876。
  - 所以施放者自己施放时只拿到 1876（×1.1），队友拿到 1877（×1.075）。
- 哀悼墓碑：AtkParam_Pc 303401800『[AoW Golden Epitaph] Last Rites』交给队友的是行名写 Self 的 1835，行名写 Allies 的 1836 没有参数投递。两行只差 spCategory 152／160，target 仍按行名给出。

4. 累积阶梯
- 7037600–7037603 → 7037604–7037607，7037607 没有倍率，不在 buffs 里（shippedTierSpEffectIds）。
- 连续攻击类 3558–3561、312505–312508、320804–320807、7037604–7037606 都落在 spCategory 120（Paramdex SP_EFFECT_SPCATEGORY：Remove Previous），不同物品之间同样互斥。这是推断，未实测。

5. 验证
- self_check 新增 self_check_v6_round3，另做 10 种篡改的反例测试，全部被拦下。
- 连续生成两次，除 generatedAt 外完全一致。
- macOS RelicCoreChecks 12697 项全过；Windows ranker.test.mjs 与 ranker_crosscheck.test.mjs 共 107 项全过。

## TAE 动画事件与命中核实（extract_tae.py / verify_skill_hits.py，2026-09-24）

背景：战技数据集（generate_skills.py）的 hits 只沿参数链（SwordArtsParam → BehaviorParam_PC → AtkParam_Pc / Bullet）和 Paramdex 行名找，参数里存着的行不一定被本作动画调用——用户指出「狩猎大蛇」（17030000，behaviorVariationId 1703）在本作不是远程，而数据集里有 301703900/901/905 三段 "Beam of Light"。要判定哪些 judge 真的会打出，只能读玩家的动画事件表 TAE。

### 来源文件
- /chr/c0000.anibnd.dcx（data1 归档，KRAK 压缩，BND4 解出 57.6 MB）里的 523 个 *.tae（文件名 aN.tae，不补零，a37 即 TAE 37；共 11606 个动画、513165 个事件）。
- /chr/c0000_a0x…a6x、a9x.anibnd.dcx 只有 HKX 动作数据，没有 TAE（已实测，脚本默认只取 c0000）。
- /action/script/c0000.hks 是 HavokScript 字节码（\x1bLuaQ），只能看字符串（SwordArts_Activate、GetSwordArtsDiffCategory…），动画号规律用 TAE 数据反推。
- 本机命令（exe 1.3.3.0 / regulation 1.03.5）：`uv run extract_tae.py --game "<Game>" --krak-batch-cmd "'<CrossOver wine>' --bottle Steam --no-gui 'Z:\…\tools\oodledec\oodledec.exe' 'Z:\…\Game\oo2core_9_win64.dll' --batch {win_manifest}"`，约 40 秒；`--parse-only` 只重解已取出的 .tae（系统 python3 即可）；`--template raw/TAE.Template.NR.xml --full raw/tae/full` 另外按模板解全部事件（95 MB）。
- 产物（raw/tae/，不入 git）：c0000/aN.tae、invoked.json（只收带 judgeId 的事件 1/2/5/304/307、施法事件 64 与给自己上 SpEffect 的事件 66/67/302/331/401——模板里带 SpEffect ID 字段的全部 5 种；302「Dragon Form」29 个、401「Multiplayer [401]」286 个，a774 死亡闪光 1790/1792、a786 雷暴 1510/1512、a834 血祭仪式 1626/1628 走的是 302——外加每个动画的事件类型清单、ImportOtherAnim 导入关系、动作文件名）、hit-invocation-report.json / .md（verify_skill_hits.py 生成）。

### 格式依据
- TAE 二进制布局对照 SoulsFormatsNEXT（SoulsFormats/Formats/TAE/TAE.cs、Animation.cs、Event.cs）：本作与艾尔登法环同为 64 位、版本 0x1000D 的 SDT/ER 格式。文件头 0x50 TAE ID、0x54 动画数、0x58 动画表；动画表每项 ID(i64)+偏移(i64)；动画体 = 事件表 / 事件组 / 时间表 / 动画文件头四个偏移 + 事件数等；事件头每项三个 i64（起止时间偏移、事件数据偏移），事件数据 = type(i32)+unk(i32)+参数偏移(i64)+参数；动画文件头区分 Standard（importsHKX / importHKXSourceAnimID）与 ImportOtherAnim（整段动画含事件从别的动画导入，598 个，导入号 = TAE 号×1000000+动画号，脚本跟随）。
- 事件参数字段依据 Smithbox 的 src/Smithbox.Data/Assets/TAE/TAE.Template.NR.xml（与 DSAnimStudio 的 TAE.Template.ERNR.xml 一致，后者把 source 枚举补到了 3 技能武器 / 4 绝招武器 / 5 额外武器 / 6 灵鹰）：
  - 1 Attack Behavior：attackType(s32) attackIndex(s32) **judgeId(s32)** dirType(u8) source(u8) stateInfo(s16)
  - 2 Bullet Behavior：dummyPolyId(s32) attackIndex(s32) **judgeId(s32)** attachType(u8) enable(b) stateInfo(s16) offset(s16) u8 source(u8) 0
  - 5 Common Behavior：attackIndex judgeId；304 Throw Attack Behavior：u16 source judgeId；307 Invoke PC Behavior：condition(u16) offset(u16) pcBehaviorType(s32) judgeId(s32)
  - 64 Cast Selected Magic：… refSlot(u8)，0–9 对应 Magic.refId1–10
  - 66 / 67 / 401 Add SpEffect (- Multiplayer / - Multiplayer [401])：spEffectId(s32) 0；302 Add SpEffect - Dragon Form：spEffectId(s32) 0 0 0；331 Add SpEffect - Weapon Skill：spEffectIdFp(s32) spEffectIdNoFp(s32) 0 0（战技动画给自己上的 buff）
- SP_EFFECT_TYPE 名称取自 Smithbox src/Smithbox.Data/Assets/PARAM/NR/Param Enums/SP_EFFECT_TYPE.json（复制到 raw/paramdex/）。

### 实测出的规律
1. **judgeId ↔ BehaviorParam_PC**：行 ID = base + behaviorVariationId×1000 + judge（generate_skills.py 已用）；TAE 事件的 judgeId = judge（base 100000000 的普通攻击）或 base/100000000×1000 + judge（3xxx 战技、4xxx 战技通用行 / 角色变体行、5xxx 另一组（大枪 / 大蛇狩猎矛普通攻击上带 stateInfo 187 门控的延长命中行等）、8xxx/9xxx 词条子弹、6xxx/7xxx 渡夜者技能）。武器有专属行取专属行，否则落到 variationId=0。自检：战技 TAE（a600–a899）里 1115 个 judgeId 有 1114 个能找到行。两个例外：
   - **base 400000000 的行按行自己的 variationId 解，不按武器**：风暴管束者 1200 的 80 段 = var 0 的 8 行 + 8 组（var 100 / 500 / 900 / 1100 / 1102 / 1800 / 2100 / 2300）× 8 + var 4100 与 5000 各 4；武器 3980000 自己的 behaviorVariationId 是 300、不在其中。这些 var 值与武器类别的 var 完全重合（100 匕首、900 打刀、1800 戟、2300 特大武器…），而 Paramdex 的 AtkParam 行名按渡夜者标（"[AoW - Duchess] Storm Ruler"…）——**「按角色选行」是从行名推断的**，运行时的选行键没有实证；两种读法下结论相同：这些行 code 相同（4200–4250 共 11 个），a860（40100–40117）把 11 个 code 全部调用，80 段全 invoked。verify_skill_hits.py 对这种 base 按行自己的 variationId 解并附 characterVariationId（原先按武器 var 解，72 段被误记 noJudge）。
   - **base 不是 1 亿整数倍的行（242 行：ID 10/11/100/400…、2120/2121/2140/2141…）不走 TAE judgeId**：其中 162 行被 SpEffectParam.behaviorId 引用、由 SpEffect 触发（SpEffect 1630/1635 "[AoW] Prayerful Strike - Heal Bullet Spawn" → 2120/2121 → 子弹 2150/2155 → 祈祷一击的回血段 1202100/1202105；1515 "[AoW] Carian Retaliation" → 2140 → 2652 → 300000682/683），其余 80 行（10/11/100/400–513…）没有任何 SpEffect 引用，数据集也没有段落在它们上。原先 judge_code 把它们压成 code 0，与所有武器 R1 的 judge 0 撞号，祈祷一击 3 段与卡利亚式奉还 2 段因此被误记成 weaponTae（证据竟是 a33_30000 普通 R1）。现在这种行记 spEffect，并列出 SpEffect 名、stateInfo 与来源——来源扫全部 253 个参数表里名字含 spEffect / doping 的列（29 个表；消息 / 文本 / 开关 / 倍率 / 子弹号列除外）与全部 TAE 的事件 66/67/302/331/401：1630 由祈祷一击自己的落地段 AtkParam_Pc 301200820.spEffectId1 上；1515 由卡利亚式奉还的弹反子弹 Bullet 2651.spEffectId0 上；1635（无 FP 回血）在全部参数列与全部 TAE 事件里都没有来源（无 FP 落地段 301200821 只带 6906），记 spEffectNoSource、计入永远打不出。
2. **战技动画 = TAE a(600 + SwordArtsParam.swordArtsType)**，动画号 4xxxx：40000 = L2 第一段、40005 = 同段无 FP 版、40010/40020 = 后续段、40200/40300/42400… = 其它动作组变体（回旋斩 a603 正好 4 套×2 段）。狩猎大蛇 188 → a788；狮子斩 0 → a600；风暴刃 59 → a659；狩猎巨人 16 → a616；回旋斩 3 → a603；尸横遍野 177 → a777；野蛮咆哮 140 → a740；战吼 141 → a741。数据集 187 个战技里除两个「无战技」（swordArtsType 255）外 185 个都有对应 TAE。
3. **战吼 / 野蛮咆哮 / 灭洛斯的狂嚎的 R2 段**不在自己的 TAE 里，而在武器动作组 TAE a(EquipParamWeapon.wepmotionCategory) 的 30600–30635 / 32600–32635 动画（每组 8 个：30600/05/10/15/20/25/30/35 与 32600–32635；judgeId 3950–3969 野蛮咆哮 / 灭洛斯，3980–3997 战吼；这些 code 在别的动画里一次都没出现），所以核实时除战技 TAE 还查武器的 wepmotionCategory / spAtkcategory TAE。选 30600 系动画的开关是这三个战技 TAE 用事件 331 给自己上的 buff：a740 上 1680/1682（无 FP 1685/1687，"[AoW] Barbaric/Milos Roar"）、a741 上 1810/1812/1815/1817（"[AoW] War Cry"）、a815 上 840/842/845/847（无名，结构与前者相同）。HKS 是字节码读不出判断，verify_skill_hits.py 把这三个战技显式列为 ROAR_R2_SKILLS，**只有它们的段允许 weaponTae**；别的战技若只落在这些动画上记 roarR2Only（不属于该战技）——狩猎大蛇 301703955 就是这种：只在大枪动作组的吼叫 R2 a37_030605 里，大蛇狩猎矛的战技固定、拿不到吼叫 buff。夸耀咆哮 654（a744 上 1860/1862）与王者嘶吼 1031（a831 上 890/892）也有同结构的 331 buff，但数据集没有把 R2 行挂给它们，本次不动。
4. **stateInfo 是前置条件**：事件 stateInfo≠0 时只有角色带对应 SP_EFFECT_TYPE 的 SpEffect 才触发。证据：每个蓄力攻击动画都挂着一串 stateInfo=2211（Ice Storm upon Charged Attacks）/2213（Black Flames…）/2214/2216/2218/2221/2224/2228 的子弹事件，正是局内武器词条；609（Cursed Sword Active）门控执行者的诅咒剑段。**stateInfo 187 是本体《艾尔登法环》打拉卡德（神皮吞食者大蛇）时大蛇狩猎矛「光波延长命中」的门控**，不是通用的 NPC 同伴行：它只出现在 6 个 TAE 里——a37（大枪 wepmotionCategory 37，74 个事件）、a207（大蛇狩猎矛专属 spAtkcategory 207，99 个）、a788（狩猎大蛇战技，2 个：3900/3901）与 a26（大剑组，4 个 8000 系子弹）/ a31（决斗大斧组，12 个）/ a271（1 个）；带命中事件的 R1 动画（30000–30099）224 个里只有 a37 / a207 的 30000/30010/30020 这 6 个挂着它（5000 系 judge = base 500000000 的延长命中行）。本作全部参数表里只有 SpEffect 1908 带 stateInfo 187（NR 枚举里也没名字），而 1908 只被 BuddyStoneParam 16000114（m16 的 NPC 召唤石，eliminateTargetEntityId 16005800）的 dopingSpEffectId 引用——玩家拿不到，所以本作玩家永远打不出光波。EMEVD 事件脚本没有查。
5. **事件 307（Invoke PC Behavior）pcBehaviorType=8 时 judgeId 与事件 1 同义**：踢击（3085/3086）、无 FP 版冻霜踏地 / 风暴足（3056/3051）都是这样触发的；type 4 的 500–561 是翻滚 / 跳跃类，不查 BehaviorParam_PC。
6. **法术**：施法动画在 TAE a(400 + Magic.refType) 里（160 个法术全部命中），事件 64 只带 refSlot；子弹 / 攻击行由 Magic.refIdN 决定，所以法术段只需确认它所在的 refId 槽被施法动画用到。
7. 本作武器的战技是从 **SwordArtsTableParam** 抽的（EquipParamWeapon.swordArtsTableId → 同 ID 多行，每行 swordArtsId + chanceWeight），generate_skills.py 只看 swordArtsParamId，所以风暴刃 210、狩猎巨人 116 等只出现在抽取表里的战技 weaponIds 为空（下一阶段处理）；verify_skill_hits.py 用抽取表补上武器（via="table"）。
8. **法术里的触发型 SpEffect**：Magic 的 refCategory 2 槽若带 stateInfo（因果性原理 6760 的槽 1 = SpEffect 1676000，stateInfo 170 "Karmic Justice Counter"；贵族气场 6270 的槽 2 = 1624000，stateInfo 443），施法动画只上这个 SpEffect，它触发时发射的是同一 Magic 里施法动画不用的子弹槽（因果性原理槽 0 = 子弹 10676000 → 67601）。这种段记 spEffectDerived，不再和卡利亚大剑 / 亚杜拉的月光剑 / 卡利亚迅剑的槽 4–5（本体骑乘版残留，真的没用）混在 slotUnused 里。行名点名但不在任何槽里、由 SpEffect.behaviorId 触发的段（卡利亚式奉还 4640 的 6 段、因果性原理 67600、火焰重罪 79005）记 spEffect。
9. **战技 TAE 的 4xxxx 动画按百位分「套」，一把武器只播一套**：400xx 默认套、402xx 大型武器套、403xx 长柄套、4XXxx（XX ≥ 20）= wepmotionCategory XX 的专属套（424 双头剑、442 拳、445 大弓、447 / 448 大盾 / 小盾、420 匕首、428 曲剑；a691 大盾战技另有 404–409）。证据：103 回旋斩 Paramdex 标 Twinblade 的 250–257 只在 42400 系（双头剑 wepmotionCategory 24），Large Weapon 230s 在 40200 系、Polearm 240s 在 40300 系；124 剑舞 var 1000（双头剑）的专属行只配给 42400 / 40300 系的 490s；406 箭雨的 44560 系发的是大箭 var 5100 的行。选套的是 HKS 的 GetSwordArtsDiffCategory（c0000.hks 是字节码，映射读不出）。185 个战技 TAE 里各套 judge 不同的只有 a603 回旋斩（四套）、a612 二连斩（400/403 用 3170–3181，402 用 3185–3196）、a624 剑舞（400 用 3470s、402 用 3480s、403/424 用 3490s）、a654 鲜血斩击（400/424 用 3023/3024，402 用 3020/3022），其余多套 TAE 各套 judge 相同、不受影响。verify_skill_hits.py 对每个 variant × var 取各段所在的套，交集为空时按 motion 专属套 → 只有一套配了本 var 的专属行（varRows）→ 类别归组（classGroup：103 的手工归组，直剑 / 曲剑默认、大曲剑 402、戟 / 镰 403；classGroupInferred：大剑 / 特大剑 / 大斧 / 大锤 / 特大武器 402、矛 / 大矛 403，体型类比、未证实）→ 默认套 400 选一套，其余套的段记 exclusiveBlock，另列一桶、不与 invoked 相加。3xxxx（改写普攻的战技的 R1 / R2，a830–a852）是不同输入、不算套。
10. **codes 为空（BehaviorParam_PC 解不到行）的段再分三种**：产出它的行存在但都属于别的 behaviorVariationId → rowForOtherWeapon（转啊转 120 的 303309900/901/902/905/906/907：行只有 var 3309 = 卡利亚王笏 33090000 / 35090000，而那把武器的战技是 10，不是 120）；全部参数表里名字为 atkId / atkParamId 的列（Bullet.atkId_Bullet、Magic.atkParamId、SwordArtsParam.atkParamId、PlayerCommonParam.markingAtkParamId）与 BehaviorParam_PC.refId、Magic.refIdN 都不引用它 → unreferenced（12 段：突击 301600901/902、落雷 301600843、信仰喷发 301217914、掠夺火焰 300314903/904、毁灭灵火 303401401、催眠烟雾 300208911、萨米尔冰风暴 303401602/603、隙间月影 303400102/107）；只是 SwordArtsParam.atkParamId 锚点，或产出它的行都是弹药 var（5000–5399，箭 / 大箭 / 弩箭 / 弩炮弹）→ noJudge（弓系战技 400/401/404/405/406 的锚点由弹药的行打出，如 a705 箭雨 40060 的 judge 641 发的是箭 var 5000 的 105000641，本报告不按弹药 var 解）。前两种计入永远打不出。

### 核实结果（hit-invocation-report.md，重跑于修正 judge_code / 吼叫判定 / 角色变体行 / 按 var 取武器 TAE / 互斥动画套 / noJudge 细分之后）
- 战技 187 个：有 TAE 185、有命中段 166、至少一段被动画调用 160（未匹配的 6 个：5 个弓系射击战技与拉塔恩的骤雨——只有锚点段，伤害走箭矢 / 子弹，status=noJudge）。
- 报告分两层：**战技层**每段取所有武器里最好的状态（只用于概览），**variant × behaviorVariationId 层**才是每把武器实际解到的行（武器动作组 TAE 也按 var 分别取：同一 variant 里锤的 a33 不能给肢解菜刀 a32 作证据）——同一段在不同武器上状态可能不同，逐武器结论以后者为准。
- 战技层 1782 段（带伤害 1534）：invoked 1051 / weaponTae 660 / spEffect 4 / conditional 2 / roarR2Only 1 / gated 2 / elsewhere 1 / notInvoked 25 / spEffectNoSource 1 / rowForOtherWeapon 6 / unreferenced 19 / noJudge 10；带伤害段里 invoked 941、weaponTae 540、spEffect 4、conditional 2、roarR2Only 1、gated 2、elsewhere 1、notInvoked 16、spEffectNoSource 1、rowForOtherWeapon 6、unreferenced 12、noJudge 8（原先的 noJudge 26 拆成 unreferenced 12 + rowForOtherWeapon 6 + noJudge 8；spEffect 5 拆成 4 + spEffectNoSource 1）。
- variant × var 层带伤害：数据集 variant（via=behavior）invoked 781 / weaponTae 172 / spEffect 2 / conditional 2 / exclusiveBlock 12 / roarR2Only 1 / gated 2 / elsewhere 16 / notInvoked 15 / spEffectNoSource 1；抽取表补的 variant（via=table）invoked 8989 / weaponTae 1652 / spEffect 36 / exclusiveBlock 1540 / elsewhere 198 / notInvoked 28 / spEffectNoSource 16；没挂武器的（via=none）invoked 182 / noJudge 3；不属于任何 variant 的 32 段：rowForOtherWeapon 6 / unreferenced 19 / noJudge 7。
- **从未被玩家动画调用的带伤害段：295 个 variant 段（去重后 43 个战技段，涉及 21 个战技、2878 个武器×段）**，按状态 elsewhere 214 / notInvoked 43 / spEffectNoSource 17 / unreferenced 12 / rowForOtherWeapon 6 / gated 2 / roarR2Only 1，按来源 数据集 variant 35 / 抽取表 variant 242 / 不属于任何 variant 18：
  - **野蛮咆哮 300000957/959/967/969（1H R2 #2-2 及其蓄力版）在大锤 / 大斧 / 矛 / 肢解菜刀上打不出**：这些武器组没有专属行，数据集给它们落到了 var 0 的通用行，但它们的动作组 TAE a35 / a32 / a36 在 30610/30615/32610/32615 里只发 3956/3958/3966/3968，3957/3959/3967/3969 只在锤 / var 0 武器的 a33 等 TAE 里出现（大棍棒 12000000 逐行解过）。数据集 variant 里 4 组（var 1200 大锤 40 把、1500 大斧 16 把、1600 矛 8 把、1501 肢解菜刀 15120000–15121100 8 把——最后一组原先被同一 variant 里锤的 a33 盖成了 weaponTae，现在武器 TAE 按 var 取）× 4 段 = 16 个 variant 段、72 把武器；抽取表补的 variant 再加 31 组 124 个 variant 段、1780 个武器×段。
  - **狩猎大蛇 301703955**：只在大枪动作组的吼叫 R2 a37_030605 里出现，而 1188 不是吼叫战技，记 roarR2Only。
  - **祈祷一击 1202105（无 FP 回血）**：由 SpEffect 1635 触发，1635 在全部参数列与 TAE 事件里没有来源，记 spEffectNoSource（1 个数据集 variant 段 + 16 个抽取表 variant 段）。
  - **转啊转 6 段**（303309900/901/902/905/906/907）：行只属于卡利亚王笏 var 3309（那把武器的战技是 10），rowForOtherWeapon；**12 段完全无引用**（unreferenced，清单见规律 10）。
  - 其余与原先一致：狩猎大蛇 900/901（gated 187）、905/975（notInvoked）、撼地 300000327、黄金大地 300000557、黄金坠落震击 300000801（[UNUSED] 行只被黄金波动 a820 用，抽取表 74 个 variant 段）、信仰喷发 3 段、唤矛仪式 2 段、王者嘶吼 1 段、旋转刺轮 2 段、弹指 2 段、女王黑焰 1 段、风暴踢击 1 段（专属行在自己武器 / 战技的 TAE 里都没有对应 code）。
- **互斥动画套里的带伤害段：1552 个 variant 段（去重 70 个战技段，4 个战技、20320 个武器×段）**：回旋斩 103 35 组、二连斩 112 36 组、剑舞 124 37 组、鲜血斩击 204 23 组。数据集 variant 只有二连斩 蛇骨刀 9080000 ×8（var 901）的 12 段：generate_skills.py 把默认套 170–181 与 Large Weapon 套 185–196 一起给了它（ctx 缺失的默认套 + 唯一具名套没有触发它的 ctx 单选），本报告按默认套 400 保留 170–181；其余 1540 段都在抽取表补的 variant 里（原先的表 variant 合成把各套并集全部记成 invoked，回旋斩会多算 3 套）。选套依据 default 538 / classGroup 522 / classGroupInferred 446 / motion 46（variant 段数）。这些段在战技 TAE 里被调用，只是不在这把武器播的那套里，**下一阶段合并时不能与同一武器的 invoked 段相加**。
- 有条件触发 2 段：黄金式奉还 303208905/906（stateInfo 469，吸收法术成功后才有）。SpEffect 触发（不经动画事件）且有来源的带伤害段 4 个战技段 / 38 个 variant 段：祈祷一击 1202100/1202110（来源 AtkParam_Pc 301200820.spEffectId1）与卡利亚式奉还 300000682/683（来源弹反子弹 Bullet 2651.spEffectId0），全部出自本战技自己的段。
- 狩猎大蛇结论：a788 的 40000（L2 第 1 段）同时挂 3900（Beam of Light，stateInfo 187）与 3950（L2 #1，无门控），40010 同理挂 3901/3951，40005/40015 是无 FP 版 3970/3971；所以玩家每段只打出 950/951（无 FP 时 970/971）。光波 900/901 是本体打拉卡德的延长命中（规律 4），本作只有 m16 残留的 NPC 召唤石 doping 能给出 187 这个状态，玩家永远触发不了；905/975 没有任何动画调用，955 只在吼叫 R2 动画里（roarR2Only）。本作里这招就是 2 段近战，参数里的三段 Beam of Light 不是远程。
- 法术 419 段：invoked 377、spEffect 8（卡利亚式奉还 6、因果性原理 67600、火焰重罪 79005，由 SpEffect.behaviorId 触发，8 个 SpEffect 都有来源）、spEffectDerived 1（因果性原理 67601，槽 0 子弹由 stateInfo 170 触发发射）、noSlot 21（行名点名但不在任何 refId 槽里也找不到 SpEffect 来源）、anchorOnly 6（Magic.atkParamId 锚点）、slotUnused 6（卡利亚大剑 / 亚杜拉的月光剑 / 卡利亚迅剑各 2，槽 4–5 施法动画不用）。
### 局限
- 只读了玩家 c0000 的 TAE；HKS 是字节码：哪把武器播 4xxxx 的哪一套（GetSwordArtsDiffCategory）、哪些 buff 让 R2 切到 30600 系动画都由它决定。互斥套只能从 TAE 判「有几套、各套 judge 是否不同」，选哪一套是本报告的规则（motion / varRows 有数据证据，classGroup 来自 103 的手工归组，classGroupInferred 与 default 是推断），每个 exclusiveBlock 段都带 blockChoice 说明依据；吼叫战技用显式清单（ROAR_R2_SKILLS）并在报告里列出 331 buff 作证据。
- stateInfo 门控只判断「是否可达」两档（187 不可达，其余可达），没有追溯每个状态怎么获得；EMEVD 事件脚本本脚本没有查（187 的结论只基于参数表与 TAE）。
- spEffect 状态只说明「由哪个 SpEffect 触发、这个 SpEffect 在哪个参数列 / 哪个 TAE 事件上」，没有再往下追 SpEffect 的触发条件（stateInfo 275 等）；来源扫描按列名（含 spEffect / doping）取列，靠列名判断。
- noJudge 只剩两种：SwordArtsParam.atkParamId 锚点，以及只由弹药 var（5000–5399）的行打出的弓系段——后者其实能按弹药 var 解（a705 40060 的 judge 641 → 105000641），本报告没做。
- 报告基于 1.03.5 的 regulation 与本机归档；数据集尚未据此修改（下一阶段合并时按 variant × var 层的结论处理：野蛮咆哮的 4 段 var 0 通用行、狩猎大蛇的 5 段、祈祷一击 1202105、互斥套的 1552 段，以及 generate_skills.py 给二连斩 蛇骨刀 同时挂两套的问题）。

## 命中段 TAE 核实（v3，schemaVersion 3 第二部分，2026-09-24）

把上一节（车道 B）的 TAE 核实结论并进战技数据集。数据集仍是 schemaVersion 3（`schemaChangelog` 的 version 3 条目已补上这一部分），产物 `data/nightreign-skills-v1.03.5.json` 紧凑 2,522,743 字节，三份副本（data/、windows/resources/、macos/…/Resources/）sha256 一致。（审查修正后为 2,568,862 字节，见本节末「审查修正」。）

### 做法
- `generate_skills.py` 生成时读 `raw/tae/invoked.json`（extract_tae.py 的产物），调用同目录 `verify_skill_hits.py` 新增的 `TaeVerifier`：先照旧用 BehaviorParam_PC 三级回退解出每个 (战技, 武器) 的段（行为表层，记为 pre），再逐武器判定每段的状态。同 behaviorVariationId、同动作组 TAE、同 wepType、同段集合的武器共用一次判定（6508 个 (战技, 武器) 对，实际判定 2635 次）。两个脚本共用一套 TAE 索引、judgeId 换算、三级回退与互斥动画套规则。
- `variants[].atkIds` 只保留下面五种状态的段：invoked（战技 TAE 里有无门控事件）、weaponTae（吼叫类战技的 R2 段在武器动作组 TAE 的 30600 系动画里）、spEffect（由本战技的 SpEffect 触发，本版本是祈祷一击的回血子弹与卡利亚式奉还的反击）、conditional（带玩家拿得到的 stateInfo 门控，本版本只有 1196 黄金式奉还格挡成功后的两段）、noJudge（锚点或弹药行，TAE 判不了，不删）。子弹链上的段看发射它的 BehaviorParam_PC 行：InvokeBulletBehavior（事件 2）用对应的 judgeId 调了就算调用。
- 其余状态都从 atkIds 移除：exclusiveBlock（在另一套互斥的 4xxxx 动画里）、roarR2Only、gated、elsewhere、notInvoked、spEffectNoSource、rowForOtherWeapon、unreferenced。同一行为表选段的武器按核实结果重新分组，所以 variants 可能拆开：112 二连斩从 1 组变 2 组，124 剑舞从 2 组变 4 组，204 鲜血斩击从 1 组变 2 组，总数从 223 变成 227。固定战技的 `weapons[].skillVariant` 下标一个都没变；`skillVariants` 里有 98 项下标变了，都已和本文件的 variants 对齐。
- `hits[]` 一段都不删：
  - 行为表给至少一把武器选过、但在所有这些武器上都被移除的段，标 `notInvoked: true` 加 `notInvokedReason`（取值见 `enums.notInvokedReason`；不同武器原因不同时，取 enums 顺序里靠前的那个）。
  - 只在部分武器上被移除的段不标，逐武器结论看 variants。
  - `noVariant` 改为按 pre 判定，所以它和 notInvoked 互斥，59 段的数量不变。
- 动画完全匹配不到的战技标 `taeUnmatched: true`，hits 和 variants 都不过滤。这类战技要么战技 TAE 缺失，要么没有一段在任何武器上是 invoked 或 weaponTae。本版本是 400 贯穿射击、401 连续射击、404 宿灵射击、405 对空射击、406 箭雨、1169 拉塔恩的骤雨，共 6 个弓系战技，段全是 noJudge，涉及 59 个 (战技, 武器) 对。
- 法术不做 TAE 过滤，原因写在 `fieldNotes.法术与 TAE`：施法动画只按 refId 槽发射，没有逐段的 judgeId 可核。
- `invoked.json` 缺失或传 `--no-tae` 时保持行为表口径，`counts.taeVerified=false`。这时 weapons / skills / spells / swordArtsPools 与 A 阶段产物逐项相同（已实测），只多出新的计数、说明文字和 `diagnostics`。
- 新字段：`hits[].notInvoked` / `notInvokedReason`、`skills[].taeUnmatched`、`counts.taeVerified` 加 7 个计数（hitsNotInvoked 34、hitsNotInvokedDamaging 25、hitsPartiallyRemovedByTae 46、weaponHitsRemovedByTae 2924、skillWeaponPairsChangedByTae 611、skillsChangedByTae 21、skillsTaeUnmatched 6）、`enums.notInvokedReason`、`coverage.hitsNotInvokedNote`、`usage.命中段已按 TAE 核实（v3）`（含局限）、`fieldNotes` 的 notInvoked / notInvokedReason / taeUnmatched / taeVerified / 法术与 TAE，以及顶层 `diagnostics.taeVerification`。最后这个对象约 31 KB，包括移除清单、部分武器移除清单、互斥动画套的选套分布、保留的非动画段、未匹配战技和 TAE 来源摘要。

### 对车道 B 结论的更正
1. **B 的判定脚本原本只有两级回退**：`verify_skill_hits.py` 的 `resolve_row` 是「武器自己的 variationId → 0」，现在改成与 generate_skills.py 相同的三级回退「自己 → 取整到百位 → 0」，互斥动画套的 varRows 规则也按族 var 认专属行。
   - 两级回退用在 v3 数据集上，会把 1539 个带伤害的 variant 段误记成 rowForOtherWeapon（修正前的试跑）。
   - 用在 v2 数据集上，锤（var 1101/1107）会落到 var 0 的 300000957/959/967/969，所以 B 报告写了「在锤 / var 0 武器上由 a33 打出」。实际上锤族 var 1100 有自己的 301100957/959，a33 的 30610 系动画调用的是那两行。
   - 结论：300000957/959/967/969 这 4 段在本作**没有任何武器能打出**，在全部 141 把选到它们的武器上都被移除，记为 elsewhere。B 在「实测出的规律」第 1 条写的「否则落到 variationId=0」应读作三级回退。
2. **规律 7 的抽取表补武器不再用于 v3**：v3 数据集的 weaponIds 已含局内战技池（可达 custom 行）。`verify_skill_hits.py` 对 schemaVersion ≥ 3 的数据集不再用 `EquipParamWeapon.swordArtsTableId` 补武器，因为「战技池（v3）」一节论证了那一列不是来源。另外，variant × var 计数原先把 via=ctx 的 variant 记成 none，现在记成 dataset。
3. 报告文件的去向（都在 raw/tae/，不入库）：
   - `laneB-v2-dataset/`：B 的原报告（v2 数据集加抽取表）。
   - `stageA-baseline/`：A 阶段 v3 数据集（核实前）用修正后的脚本重跑的结果。
   - `hit-invocation-report.*`：核实后的数据集重跑一遍，作为自洽检查。其中数据集 variant × var 层带伤害的段只剩 invoked 9905 / weaponTae 1756 / spEffect 36 / conditional 2 / noJudge 7。核实前还有 exclusiveBlock 922、elsewhere 199、notInvoked 43、spEffectNoSource 16、gated 2、roarR2Only 1；exclusiveBlock 与各种「永远打不出」的段全部清零。

### 结果（regulation 10350000，本机 1.03.5 c0000 动画包）
- 21 个战技、611 个 (战技, 武器) 对的段有变化，一共移除 2924 个武器×段。按原因分：exclusiveBlock 2084、elsewhere 712、notInvoked 88、spEffectNoSource 37、gated 2、roarR2Only 1。只删不增。
- **所有武器上都打不出、标 notInvoked 的 34 段（带伤害 25 段）**：
  - 1188 狩猎大蛇：301703900 / 301703901「L2 #1/#2 Beam of Light」（gated，stateInfo 187）；301703905 与 301703975（notInvoked）；301703955（roarR2Only，只在大枪动作组的吼叫 R2 a37_030605 里）。
  - 650 野蛮咆哮：300000957 / 959 / 967 / 969，即 1H/2H R2 #2-2 及其蓄力版（elsewhere，141 把）。
  - 507 黄金坠落震击：300000801 [UNUSED]（elsewhere，只被黄金波动 a820 调用，148 把）。
  - 208 祈祷一击：1202105，无 FP 回血（spEffectNoSource，37 把）。
  - 212 撼地：300000327（notInvoked，34 把）。
  - 213 黄金大地：300000557（notInvoked，31 把）。
  - 单武器专属战技：
    - 1000 信仰喷发：301217901 / 902 / 925。
    - 1015 灭洛斯的狂嚎：303401102。
    - 1019 夜与火的架式：300214900。
    - 1020 黄金波动：300310900 [UNUSED] Swing。
    - 1024 唤矛仪式：301612900 Thrust、301612915 No FP Thrust。
    - 1031 王者嘶吼：302305900。
    - 1034 授血仪式：301711900 / 910 / 920 [UNUSED] Thrust。
    - 1039 旋转刺轮：302309905 / 908。
    - 1046 弹指：301113905 / 906。
    - 1170 女王黑焰：300800311。
    - 1190 风暴踢击：302112918。
    - 1194 重力雷电：302308900 / 906 / 920。
  - 以上除 1015、1019、1020、1034、1194 那 9 段（只有削韧 / 无伤害）外都带伤害。
- **只在部分武器上打不出的 46 段，全部来自互斥动画套**：112 二连斩 24 段、124 剑舞 18 段、204 鲜血斩击 4 段。每把武器只留它播的那一套。
  - 112 二连斩：默认套 170–181 给短剑、直剑、曲剑、刀、双头剑、戟、镰；Large Weapon 套 185–196 给大剑、大曲剑。
  - 124 剑舞：3470 系给短剑、直剑、刀；3480 系给大剑、大曲剑、大斧；3490 系给矛、戟、镰；双头剑用自己的 301000490 系。
  - 204 鲜血斩击：「Slash (Greatsword)」55/56 给大剑、大曲剑；「Slash」57/58 给短剑、直剑、重刺剑、刀、双头剑。
  - 选套依据（按武器计）：
    - 112：400 classGroup 23、400 default 28、402 classGroup 4、402 classGroupInferred 11、403 classGroup 16。
    - 124：400 classGroup 12、400 default 16、402 classGroup 4、402 classGroupInferred 20、403 classGroup 15、403 classGroupInferred 13、424 motion 5。
    - 204：400 classGroup 8、400 default 14、402 classGroup 4、402 classGroupInferred 10、424 motion 4。
  - 核实后同一战技里同一武器类别仍只落进一个 variant，没有因为 TAE 再拆开。
  - 103 回旋斩在行为表层已经按手工表单选一套，TAE 核实全部 invoked，不受影响。
- **按非动画路径保留的段**：
  - 祈祷一击 1202100 / 1202110：spEffect，SpEffect 1630，37 把。
  - 卡利亚式奉还 300000682 / 683：spEffect，SpEffect 1515，42 把。
  - 黄金式奉还 303208905 / 906：conditional，stateInfo 469，1 把。
- 用户点名的几个战技：
  - 210 风暴刃、116 狩猎巨人、100 狮子斩：全部 invoked，不受影响。
  - 1200 风暴管束者：10 套 80 段全部 invoked。
  - 1188 狩猎大蛇：variants 从 9 段变成 `[301703950, 301703951, 301703970, 301703971]`，也就是 L2 #1 / #2 两段近战加各自的无 FP 版。本作里这招没有光波，不是远程（依据见上一节规律 4）。

### 与 A 阶段产物的对比（raw/skills_v3/stageA_vs_tae.json，脚本 raw/skills_v3/compare_stageA_vs_tae.py）
6567 个带 variants 的 (战技, 武器) 对里 611 个的段有变化，一共移除 2924 个武器×段，新增 0 个。下表按「每把武器被移除段占 pre 伤害（motion 合计，无 motion 时用 flat）的比例」取该战技全部武器的平均值排序，列出构成变化最大的 10 个战技：

| 战技 | 武器数（受影响） | 每把武器的段数 | 平均移除的伤害占比 | 移除武器×段 |
| --- | --- | --- | --- | --- |
| 1024 唤矛仪式 | 1（1） | 9 → 7 | 78.8% | 2 |
| 124 剑舞 | 85（85） | 18 → 6 | 66.7% | 1020 |
| 1188 狩猎大蛇 | 1（1） | 9 → 4 | 54.4% | 5 |
| 204 鲜血斩击 | 40（40） | 4 → 2 | 50.2% | 80 |
| 112 二连斩 | 82（82） | 24 → 12 | 50.0% | 984 |
| 1046 弹指 | 1（1） | 4 → 2 | 41.9% | 2 |
| 1000 信仰喷发 | 1（1） | 13 → 10 | 20.8% | 3 |
| 507 黄金坠落震击 | 148（148） | 5 → 4 | 17.4% | 148 |
| 1039 旋转刺轮 | 1（1） | 8 → 6 | 13.9% | 2 |
| 650 野蛮咆哮 | 230（141） | 22 → 18（141 把） | 13.7% | 564 |

按移除的武器×段数排序，前 10 名是 124、112、650、507、204、208 祈祷一击（37）、212 撼地（34）、213 黄金大地（31）、1188、1000。

### 验证
- `self_check` 新增的断言：
  - TAE 只删不增：每个 (战技, 武器) 核实后的段 ⊆ pre。
  - 没核实，或战技是 taeUnmatched 时，段与 pre 相同。
  - 没有空 variant。
  - notInvoked 段不在任何 variant 里，但在 pre 里；它的 notInvokedReason 在枚举里，而且不和 noVariant 同时出现。
  - 反过来，pre 选过、核实后哪都没留下的段必须标 notInvoked；pre 就没选到的段必须标 noVariant。
  - `counts.hitsNotInvoked` 等于标记数，也等于 `diagnostics.removedHits` 的条数；`skillsTaeUnmatched` 等于标记数；`diagnostics.verified` 等于 `counts.taeVerified`。
  - 狩猎大蛇 variants 恰好是 950/951/970/971，900/901 的原因是 gated，955 是 roarR2Only，905/975 是 notInvoked。
  - 二连斩的默认套和 Large Weapon 套不在同一个 variant 里。
  - 210、116、1188 都不是 taeUnmatched。
  - 「同一战技里同一武器类别只落进一套动作」改为在 pre 上断言。
- 另做 10 种篡改，全部被拦下：光波段放回 variants、notInvoked 段加 noVariant、原因不在枚举、移除段丢标记、variant 多出 pre 没有的段、二连斩两套合并、计数不符、taeUnmatched 战技被过滤、空 variant、diagnostics 与 counts 不符。
- 连续生成两次，除 generatedAt 外完全一致。`--no-tae` 与 invoked.json 缺失两种情况下，weapons / skills / spells / swordArtsPools 与 A 阶段产物逐项相同。

### 局限
- TAE 只回答「动画会不会调用这段」，不回答一次战技里命中几次：持续判定和多次 Hit 仍按一段算。
- 互斥动画套由 HKS 的 GetSwordArtsDiffCategory 选，c0000.hks 是字节码，读不出映射。选套依据分三档：
  - motion 与 varRows 有数据证据。
  - classGroup 来自 103 回旋斩的手工归组。
  - classGroupInferred（大剑 / 特大剑 / 大斧 / 大锤 / 特大武器 → 402，矛 / 大矛 → 403）和 default（其余类别 → 400）是推断。
  - 这三个战技共有 2084 个武器×段按这套规则移除，每把武器的依据写在 `diagnostics.taeVerification.exclusiveBlocks`。
- 狩猎大蛇光波的「stateInfo 187 玩家拿不到」只查了参数表和 TAE，EMEVD 没查。conditional 段（黄金式奉还）按可达保留，排名会算上它们。
- 带 FP 和无 FP 两个分支都在 atkIds 里，靠 `hits[].noFp` 区分。原先这里写「TAE 核实不改变这一点」，但行名没写 "No FP" 的无 FP 段并没有 noFp，会和带 FP 段一起被默认计入——已在下文「审查修正」第 2 条按 TAE 补标。
- 弓系 6 个战技是 taeUnmatched，没有过滤；它们的段由弹药 var 的行打出，本版没有按弹药 var 解。法术不过滤。
- 三端界面代码未改，仍按 schemaVersion 2 读取，所以测试的失败与 A 阶段完全相同：
  - Windows：376 过 / 3 败（196 数据集版本、202 selectHits、223 buildMeansItems）。
  - macOS：RelicCoreChecks 在「多套动作的战技两边都应选出段」处中止。
  - Android：`:gamedata:test` 408 项里 84 项失败。
  - 把数据换回 A 阶段产物重跑，三端的失败清单逐项相同，本阶段没有新增失败。
- 游戏更新后，要先重跑 extract_tae.py，再重生成本数据集。

### 审查修正（2026-09-24，schemaVersion 仍为 3）

审查指出 5 条问题（2 条 medium 关于数据、1 条 medium 关于文档、2 条 low）。逐条处理如下，产物重新生成并同步三份副本：紧凑 2,568,862 字节，sha256 `1637e6adda0f6503ae2df4f74a639e695834c0bad2921d42ffdef0564db65b83`。

1. **fieldNotes.notInvoked 的例子写反了（medium）**。原文举「野蛮咆哮 300000957 在锤上由 a33 的 R2 动画打出、在大锤 / 大斧 / 矛上不打」作为「只在部分武器上打不出」的例子，与数据矛盾：三级回退下锤族（var 1101/1102/1107 → 1100）解到自己的 301100957，没有任何武器会打 var 0 的 300000957/959/967/969，这 4 段在全部 141 把武器上都被移除、标了 notInvoked（上文「对车道 B 结论的更正」第 1 条）。
   - 现在的例子按数据现算：二连斩 300000185–300000196（Large Weapon 套 12 段）只留给大剑 / 大曲剑（15 把），在另 67 把武器上按互斥动画套（exclusiveBlock）移除；并注明野蛮咆哮那 4 段不属于这种情况。`generate_skills.py` 里同一处注释一并改掉。
   - `self_check` 断言这个例子成立：112 的 185–196 都在 partiallyRemoved 里、原因只有 exclusiveBlock、保留它们的武器类别恰好是 {大剑, 大曲剑}；650 的 4 段标 notInvoked、不在 partiallyRemoved 里；fieldNotes 文本里含 "300000185–300000196"。
   - `verify_skill_hits.py` 文档字符串规律 2 原写「没有该武器专属行时落到 variationId=0」，改为三级回退的完整说明（自己的 var → 取整到百位的族 var → 0，并举锤 1101/1107 → 1100 → 301100957 为例）。

2. **带 FP 与无 FP 分支仍然相加（medium）**。`hits[].noFp` 原先只看 AtkParam 行名里的 "No FP"，很多战技的无 FP 段行名没写，于是和带 FP 段一起被默认勾选（Windows 默认 `Boolean(hit.noFp) === Boolean(state.noFp)`，三端同口径）。用户点名的两个都中招：风暴刃 210 的 300000411/412/413（a659 的 40005/40015/40025，motion 105–107）与带 FP 的 407–409 加飞刃 410 相加；狩猎巨人 116 的 301700915（a616 的 40005）与 301700910 相加。
   - **规则（`verify_skill_hits.py` 规律 8）**：战技 TAE 的 4xxxx 动画个位 0–4 是带 FP 版，5–9 是无 FP 版，无 FP 版动画号 = 带 FP 版 + 5。证据：本机全部战技 TAE 里个位 ≥ 5 的 4xxxx 动画 436 个，每一个都有 −5 的带 FP 版（0 个例外）；数据集里行名带 "No FP" 且有 TAE 依据的 158 段全部只被个位 ≥ 5 的动画调用，没有一段落在个位 0–4 上。
   - 审查意见给的是「个位 = 5」。个位 6–9 的无 FP 动画也存在，例如 113 主教冲锋 40000/40003/40004 ↔ 40005/40008/40009、1200 风暴管束者 40110–40112 ↔ 40115–40117、110 盲击 40060/40062/40063 ↔ 40065/40067/40068。若只认个位 5，会有 28 段行名写着 "No FP" 的段被判成带 FP 侧，所以按「个位 ≥ 5」。
   - **做法**：`generate_skills.py` 在逐武器核实时，对每把武器**留下**的段收集调用它的动画（`verify_skill_hits.fp_evidence`）：只看战技 TAE 的事件（stateInfo 187 这种玩家拿不到的门控不算），有互斥动画套时只看这把武器播的那一套；吼叫类战技在武器动作组 TAE 的 R2 动画、以及 3xxxx 动画不分 FP，记 neutral。汇总全部武器后：
     - 只被无 FP 版动画调用、行名没写 No FP 的段 → `noFp: true` + `noFpSource: "tae"`，`labelZh` 前补「无FP版」（与行名带 No FP 的段写法一致；Windows / Android 的测试要求数据集里 noFp 段的 labelZh 以它开头）。本版本 **213 段（带伤害 206 段），84 个战技**，清单在 `diagnostics.taeVerification.noFpFromTae`（附调用它的动画号）。除上面两个外还有：103 回旋斩 12 段、124 剑舞 475–477 / 485–487 / 495–497 与双头剑套 301000495–497、1045 火焰舞 302006910–914、208 祈祷一击 301200821（无 FP 落地段）、1190 风暴踢击 9 段、1179 血刃乱舞 7 段等。
     - 带 FP 版与无 FP 版（或 neutral）动画都调用的段 → `fpBoth: true`（两侧共用，开关在哪一侧都应计入）。本版本 19 段，例：221 黑焰漩涡 300000305（40000/40001 与 40005）、118 罗蕾塔的斩击 300000440、223 喷火 300000595。清单在 `diagnostics.taeVerification.fpBoth`。三端目前的默认勾选在无 FP 侧会漏掉它们（界面车道可改成 `hit.fpBoth || noFp 同侧`）。
     - 行名写 No FP 却被带 FP 版动画调用的段记进 `noFpConflicts`：本版本 0 段，`self_check` 断言为空。
     - 没有动画依据的段（spEffect / noJudge）和 taeUnmatched 的弓系战技保持行名口径；`--no-tae` 时 noFp 只来自行名，`noFpSource` / `fpBoth` 一律不出现。
   - 新增 `counts.hitsNoFpByTae`（213）/ `hitsNoFpByTaeDamaging`（206）/ `hitsFpBoth`（19），`diagnostics.taeVerification` 加 `noFpRule` / `noFpFromTae` / `fpBoth` / `noFpConflicts` 与对应计数；`fieldNotes` 新增 noFp / noFpSource / fpBoth，`usage` 的局限 (4) 改写为实际做法，`schemaChangelog` v3 条目补 added / changed。
   - `self_check`：210 的 411–413 与 116 的 301700915 必须 `noFp` 且 `noFpSource="tae"`、labelZh 以「无FP版」开头；210 的 407–410 与 116 的 301700910 不能标 noFp / fpBoth；这两个战技每个 variant 的带 FP 侧不含无 FP 段；任何 noFp 段的 labelZh 以「无FP版」开头；noFpSource / fpBoth 只在 TAE 核实时出现，fpBoth 与 noFp 互斥。
   - variants / weapons / swordArtsPools 不变（逐项比对），只改 hits 上的标记。

3. **祈祷一击的回血子弹被当成伤害（medium）**。208 的 1202100 "Heal Self"（AtkParam selfTarget=1）与 1202110 "Heal Others"（friendlyTarget=1）opposeTarget 都是 0，各带圣 motion 100（那是回血量的倍率），却按 spEffect 留在 37 把武器的 atkIds 里，让祈祷一击的构成凭空多出 2×圣 100。
   - **做法**：`build_hit` 对 opposeTarget=0 且 selfTarget 或 friendlyTarget=1 的 AtkParam 行标 `noDamage: true` + `selfOrAllyOnly: true`，motion / flat 原值保留。三端都已把 noDamage 段排除在构成之外（Windows `hitEnabled`、macOS `SkillData` 与 `BuffRankerModel`、Android 同口径），所以界面不用改。opposeTarget=0 但三项全 0 的行（如 222 神圣光环、1051 米凯拉的光环的光环子弹）靠子弹自己的判定命中敌人，不标。
   - 没有改成「从 atkIds 移除」：这两段确实由动画 → SpEffect 1630 触发（回血真的会发生），留在 atkIds 里、靠 noDamage 不计入，和其它挂状态段的处理一致；而且这条判据只看 AtkParam，与 TAE 无关，法术也适用（法术不走 variants）。
   - 本版本 36 段 selfOrAllyOnly（战技 13、法术 23），其中带 motion / flat 的 5 段：208 的 1202100 / 1202105 / 1202110、6760 因果性原理 67601（Law of Causality，selfTarget）、7900 火焰重罪 79009（Self Target）；其余 31 段本来就是六项全 0 的 noDamage 段。审查意见说「全表扫描没有别的」，指的是战技；法术里这 2 段是新发现，一并处理。
   - `*Damaging` 计数统一按「motion / flat 非空且不是 noDamage」：`counts.hitsNotInvokedDamaging` 25 → 24（1202105 无 FP 回血不再算带伤害），`hitsWithoutVariantDamaging` 44 不变。新增 `counts.hitsSelfOrAllyOnly`（36）/ `hitsSelfOrAllyOnlyWithValues`（5）、`fieldNotes.selfOrAllyOnly`，`fieldNotes.noDamage` 补上这种来源。`verify_skill_hits.hit_damaging()` 也不算 selfOrAllyOnly。
   - `self_check`：208 的三段都是 selfOrAllyOnly + noDamage，主段 301200820（motion 235）照常算伤害；任何 selfOrAllyOnly 段必有 noDamage；removedHits 里 damaging 的条数等于 `hitsNotInvokedDamaging`。
   - 这一条不依赖 TAE，所以 `--no-tae` 的产物与 A 阶段产物不再逐项相同：weapons / swordArtsPools 仍相同，skills / spells 只差这 36 段的 `selfOrAllyOnly`（其中 5 段另加 `noDamage`）。

4. **204 鲜血斩击的选套依据（low，可选）**：402 套两段的 AtkParam 行名是 "Slash (Greatsword)" / "No FP Slash (Greatsword)"，这是「大剑播 402」的直接证据。`choose_block` 在「类别归组（有证据）」之后、「类别归组（推断）」之前加一级 classGroupNamed：某套的行名里写着 "(该 wepType 的英文名)" 时选它（只匹配带括号的整词，"(Curved Greatsword)" 不会误中大剑）。选套结果不变，只是 204 的 10 把大剑从 classGroupInferred 改记 classGroupNamed；112 / 124 的行名没有点名类别（"[AoW Large Weapon]" 只说明是大型武器套，不说明哪些类别算大型），仍按推断。HKS 的真实映射仍待游戏内确认。

5. **卡利亚式奉还的弹反段没有说明（low）**：305 的 300000682/683（魔力 flat 270）只在弹反法术成功后由 SpEffect 1515 触发，与 1196 黄金式奉还的 conditional 段同属「成功格挡 / 弹反后才打出」，按 spEffect 保留、默认计入排名。`usage` 的局限 (3) 已把 305 与 1196 并列写明；没有新增字段。

**验证**
- `python3 generate_skills.py`：self_check 通过；连续两次生成除 generatedAt 外一致；`--no-tae` 也通过 self_check。新增断言另做 11 种篡改，全部被拦下：411 / 301700915 去掉 noFp、407 误标 noFp、labelZh 缺「无FP版」前缀、回血段去掉 noDamage 或 selfOrAllyOnly、fpBoth 段同时标 noFp、noFpConflicts 非空、fieldNotes 换回野蛮咆哮的旧例子、hitsNotInvokedDamaging 与清单不符、hitsNoFpByTae 与清单不符。与上一版产物比对：weapons、swordArtsPools、全部 variants 不变；hits 上的变化只有 noFp / noFpSource / labelZh（213 段）、fpBoth（19 段）、selfOrAllyOnly（36 段）与 noDamage（5 段）。
- `python3 verify_skill_hits.py --out raw/tae/v3-review-fix`（新报告，不入库；原 raw/tae/hit-invocation-report.* 保留作对照）：数据集 variant × var 层带伤害只剩 invoked 9905 / weaponTae 1756 / spEffect 4 / conditional 2 / noJudge 7，spEffect 从 36 降到 4（剩下的是卡利亚式奉还 682/683），其余不变。
- 三端测试与改动前逐项相同：Windows 376 过 / 3 败（196、202、223；361 是 TODO），失败输出逐字相同；macOS RelicCoreChecks 仍在「多套动作的战技两边都应选出段」处中止；Android `:gamedata:test` 408 项 84 项失败，失败清单与换回上一版数据时逐项相同。
- 未处理：`data/nightreign-buffs-v1.03.5.json` 的 attackIndex 是从 v2 的战技数据算的（A 阶段起就没有重生成），本次的 noDamage 变化只影响其中 208 / 6760 / 7900 三项的段数；buffs 由别的车道重生成。
