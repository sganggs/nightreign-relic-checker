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
| `data/nightreign-bosses-v1.03.5.json` | `generate_bosses.py` | `bossesSchemaVersion` 2 | 首领数据 |
| `data/nightreign-skills-v1.03.5.json` | `generate_skills.py` | 2 | 增伤排名（选段与伤害构成） |
| `data/nightreign-buffs-v1.03.5.json` | `generate_buffs.py` | 5 | 增伤排名（倍率与叠加） |

> 表里的 schemaVersion 是写死的：重新生成任何一套数据集时，请同步更新本表与
> [`windows/renderer/pages/README.md`](../../windows/renderer/pages/README.md) 的
> 「3. `ctx.getGameData(name)`」一节（那里也写了 `bossesSchemaVersion` 2 / skills 2 / buffs 5）。

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
「游戏数据集」总览表。原文保留不删。）

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
  weaponIds 由 `EquipParamWeapon.swordArtsParamId` 反查。
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
- `raw/params/HeroParam.csv` —— 10 个夜行者，`characterNameId` → CL_MenuText 288050+
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
