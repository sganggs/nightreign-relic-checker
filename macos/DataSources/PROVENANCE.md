# 遗物词条数据集：来源与计数

生成文件：`affixes.json`  
目标数据版本：v1.03.4 + DLC1  
生成时间：2026-07-10T01:36:40+00:00

## 可直接用于第一版普通遗物检查器的规则

- 下拉列表过滤：`eligibleForNormalChecker == true`（共 340 条）。
- 三条词条必须是三个不同 `effectId`，且非 `-1` 的 `compatibilityId` 两两不同。
- 正确显示／存档顺序：按 `(sortId, effectId)` 升序；`sortId` 就是游戏参数的 `overrideEffectId`。
- 普通随机遗物的红、蓝、黄、绿四种颜色使用相同词条池，颜色不改变组合合法性。
- 旧池为 100/200/300，共 290 条；当前池为 110/210/310，共 340 条。三个槽的候选集合相同，仅权重不同。
- 30 个远征奖励池的当前可抽候选集合也都与上述 340 条完全相同；商店 72 行、远征奖励 360 行中，每一种池序列都覆盖红蓝黄绿四色。

## 计数

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

## 来源

1. 游戏参数、简中 FMG：[0d2ad1494c37](https://github.com/alfizari/Elden-Ring-Nightreign-Save-Editor/tree/0d2ad1494c372098e689c23159656df70ff2d76d)。参数文件最后更新于 2026-01，QuickRef 同期提交明确标注为 v1.03.4 数据。
2. 说明与分类：[3e23450094c1](https://github.com/xxiixi/NightreignQuickRef/tree/3e23450094c18125ae5665927ed240b18189a040)。
3. 参数字段语义：[Smithbox Nightreign annotations](https://github.com/vawser/Smithbox/blob/b1b644a770f8cc4c8cab452da3a72ff7b91e105a/src/Smithbox.Data/Assets/PARAM/NR/Param%20Annotations/English/ATTACHEFFECT_PARAM_ST.json)。其中明确说明相同 `compatibilityId` 不能同时出现在同一遗物／武器；`exclusivityId` 只控制已装备遗物间的红色感叹号提示，不能拿来判定单件遗物组合。
4. 热度与旧称：Wayback 保存的 [`relics-with-ID`](https://web.archive.org/web/20260312030547id_/https://elden-api-v2.dingdangmarket.com/relics-with-ID) 与 [`hot-relics`](https://web.archive.org/web/20260312030548id_/https://elden-api-v2.dingdangmarket.com/hot-relics)，快照日期 2026-03-12。

游戏参数决定合法性；QuickRef 与旧站数据只用于展示、别名、说明和热度，不覆盖参数字段。

许可提示：Save Editor 与 Smithbox 为 MIT；NightreignQuickRef 为 GPL-3.0。公开分发内嵌 QuickRef 说明的版本时，应保留来源、许可证并履行 GPL 要求；游戏 FMG 文本仍受游戏权利方权利约束。此处仅记录来源，不构成法律意见。

## 合并异常／保守处理

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

## 游戏数据集（v0.3.0 规划：首领数据 / 增伤排名 / 削韧）

## nightreign-bosses-v1.03.5.json（首领数据）

生成器：`macos/DataSources/generate_bosses.py`
运行：`cd macos/DataSources && python3 generate_bosses.py`（默认读 `raw/`，写 `data/nightreign-bosses-v1.03.5.json`）

### 来源表

| 来源 | 修订 / 版本 | 许可 | 用途 |
| --- | --- | --- | --- |
| ELDEN RING NIGHTREIGN `regulation.bin` 导出的参数 CSV（`raw/params/`） | regulation 10350000 / exe 1.3.3.0 / steam build 22818764，sha256 `876a3ca2…e0268` | 游戏本体数据，仅用于展示数值 | `NightBossMenuParam`、`NpcParam`、`MultiPlayCorrectionParam`、`SpEffectParam` |
| 游戏内文本 FMG（`raw/msg/{zhocn,engus}/`） | regulation 10350000 + DLC1（基础 `X.json` 与 `X_dlc01.json` 合并，后者覆盖） | 游戏本体数据，仅用于展示名称 | `menu_dlc01/CL_MenuText`（夜王名 / 远征名 / 夜王说明）、`item_dlc01/NpcName`（Boss 名，中英） |
| Smithbox Paramdex (NR) | `vawser/Smithbox@f5969c060cea240476e9dd4d6a64eafa9dbafaab` | MIT | paramdef 字段名、参数行名（CSV 的 `Name` 列）、`EFFECTIVE_AFFINITY` 枚举 |

### 字段映射

- **夜王条目** ← `NightBossMenuParam` 每一行。`bossNameId`/`expeditionNameId`/`descriptionId` → `CL_MenuText`（zhocn + engus）；`effectiveAffinity1/2` → `EFFECTIVE_AFFINITY` 枚举（0 = None 已剔除），枚举中文译名为本项目补充。`everdark` 由行名是否以 `[` 开头判定（`[Everdark Sovereign] …` 与 `[Salvation's Standard-Bearers] Balancers / Harmonia`）。
- **战斗行** ← `NpcParam`。`hp`、`superArmorDurability` → poise、`saRecoveryRate` → poiseRecover。
- **承伤倍率** ← `neutral/slash/blow/thrust/magic/fire/thunder/darkDamageCutRate` → `standard/slash/strike/pierce/magic/fire/lightning/holy`。本作把**圣属性放在 dark 槽**；`def_*` 字段全为 100，不参与计算，未收录。
- **异常抗性** ← `resist_poison/desease/blood/freeze/sleep/madness/curse` → `poison/rot/bleed/frost/sleep/madness/death`，999 视为免疫（另出 `immune` 数组）。
- **人数缩放** ← `NpcParam.multiPlayCorrectionParamId` → `MultiPlayCorrectionParam`（`client1SpEffectId` = 双人、`client2SpEffectId` = 三人）→ `SpEffectParam`：`maxHpRate` → hp、`saReceiveDamageRate` → poiseTaken、`changeSaRecoveryVelocity` → poiseRecover、`bloodDamageRate`/100 → statusRate（与 freeze/sleep/madness 同值）、`poisonDamageRate`/100 → poisonRate、`poisonDefDamageRate` → resistRate（与其余 `*DefDamageRate` 同值）。同一档位名下不同尾号的缩放并不一致（例如 7762 是 ×1.3/×1.6，7767 是 ×2/×3），因此 `scalingTiers` 按具体 ID 收录。
- **守夜/野外 Boss 中文名**：`NpcName` 的文本 ID 形如 `9 + chrId(5 位) + 3 位序号`（如 `903100600` = c3100 铃珠猎人）。按 chrId 取候选后用「精确 → 单复数 → 扩写（`XXX of the YYY`）」匹配 Paramdex 基础名；失败再做全局精确匹配，再落到手工别名表，最后才保留英文。每条记录用 `nameSource` 标明来源。

### 推断与判断

- **夜王 ↔ NpcParam 的归属**是手工映射（`NIGHTLORD_CHRS`）：格拉狄乌斯 c7500、艾德雷 c7510/7511、格诺斯塔 c7520+c7521+c7530、玛利斯 c7540/7541、利普拉 c7560/7561/7570、弗格尔 c7600、卡莉果 c4900/4901、布德奇冥 c7580、哈尔莫妮亚 c7620+c4641、史柴格斯 c7610。依据是 Paramdex 行名、`WwiseValueToStrParam_BgmBossChrIdConv` 的 BGM 触发行、以及 `NpcName` 的分组（`9075200xx` 下同时有「慧心虫 / 格诺斯塔 / 亚尼姆斯」）。
- **弗堤士（Faurtis Stoneshield，“坚盾”弗堤士）与亚尼姆斯（Animus, Ascendant Light，“超越之光”亚尼姆斯）归入「慧心虫」远征**：两者都属「Final Boss Threat」且有至暗变体，却没有独立的 `NightBossMenuParam` 行，也没有独立 BGM 行；慧心虫说明文本写的是「飞翔空中的双翅、徘徊地面的螯剪」（两只虫）。亚尼姆斯只有至暗行（普通远征无对应 `(Boss)` 行），故只挂在至暗条目下。这是推断，非参数直接给出。
- **「至暗」判定**：行名含 `Everdark` / `Enhanced Boss`，或 chrId 属于只在至暗战登场的 `{7511, 7561, 4901, 4641, 7521, 7541}`。
- **`isMain`** 是手工列出的 npcId 集合（普通远征最终战用行 + 至暗战用行），不是参数字段。
- **合并规则**：同一条目下 hp / poise / poiseRecover / 八系倍率 / 七项抗性 / 解析后的缩放值完全一致的行合并为一条，`npcIds` 保留全部原始行号，`npcId` 是代表行（优先取 `isMain` 行 → 有手工标签的行 → 变体描述最长且非 Template 的行）。
- **手工补的中文名**（`nameSource: "manual"`，按 Elden Ring 官方简中或组合游戏文本）：山妖、雪花石之王、缟玛瑙之王、手指爬行者、行走灵庙、火焰骑士（含队长/长老/贤者）、大型黄金河马、废弃物蚯蚓脸、葬送战马、发狂米兰达之花、鲜血君王的长枪、墓地幽魂。
- **变体标签中文**（如「封印监牢」「地下堡垒精英」「登场演出」）是本项目对 Paramdex 括号注释的翻译，不是游戏文本。

### 已知局限

- 跳过 `NightBossMenuParam` ID 100「深夜 / The Deep of Night」（`bossNameId = -1`，是深度模式入口而非夜王），记录在 `notes.skippedMenuRows`。
- 跳过 15 行既无 Paramdex 行名又无 `NpcName` 的实体（c4504、c4603、c7711、c7712、c7910、c7931、c7932），以及 hp ≤ 0 的场景物件（Walking Mausoleum）和调试行（ID 末四位 9999，如 hp 63936 的 Crucible Knight）。
- `Putrid Flesh`(c4171)、`Giant Skeleton Torso`(c4960) 在游戏文本里找不到对应条目，只保留英文名，列在 `notes.unmatchedNames`。
- 官方弱点标注（`weakness`）与实际承伤倍率不总是一致（例如史柴格斯标注为「无弱点」，但圣属性实测倍率 1.25），页面应两者并列展示。
- Paramdex 行名是社区标注，个别带问号（`Everdark Phase 1?`）或笔误（`Giant Crowd`），本数据集已做归一但仍可能有残留误差。
- 本数据集只描述数值，不含行为/招式/掉落。

## 战技／法术／武器数据集（nightreign-skills-v1.03.5.json，2026-09-22）

生成器：`macos/DataSources/generate_skills.py`（python3 标准库；默认路径可直接
`cd macos/DataSources && python3 generate_skills.py`，可选 `--params/--msg/--out/--pretty`）。
产物：`data/nightreign-skills-v1.03.5.json`，1.13 MB 紧凑 JSON，
`schemaVersion 1` / `gameVersion "v1.03.5 + DLC1"` / `dataVersion "regulation 10350000"`。

### 来源表

| 来源 | 内容 | 许可 | 用途 |
| --- | --- | --- | --- |
| 本机 regulation.bin（exe 1.3.3.0，容器版本号 10350000）经 `dump_regulation.py` 导出的 `raw/params/*.csv` | EquipParamWeapon、SwordArtsParam、Magic、AtkParam_Pc、Bullet、BehaviorParam_PC | 游戏数据，版权归 FromSoftware / Bandai Namco | 全部数值字段 |
| 本机归档 msg 经 `extract_msg.py` 导出的 `raw/msg/{zhocn,engus}/item_dlc01/*.json`（X.json + X_dlc01.json 合并，后者覆盖） | WeaponName、ArtsName、MagicName、NpcName | 同上 | 简中与英文名、ctxZh 的角色名 |
| [vawser/Smithbox@f5969c060cea240476e9dd4d6a64eafa9dbafaab](https://github.com/vawser/Smithbox/tree/f5969c060cea240476e9dd4d6a64eafa9dbafaab/src/Smithbox.Data/Assets/PARAM/NR) | Param Row Names（英文行名）、Param Meta（字段 Enum/Refs 标注）、Param Enums | MIT | 行名解析依据；枚举 WEP_TYPE、RARITY、ATKPARAM_ATKATTR_TYPE、MAGIC_CATEGORY、BEHAVIOR_REF_TYPE |

Paramdex 文件为本次临时 `curl` 到 `/private/tmp` 查阅，未写入仓库；生成器里只保留了从中
抄录的枚举映射表（WEP_TYPE / RARITY / ATKPARAM_ATKATTR_TYPE / MAGIC_CATEGORY）。

### 字段映射

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

### 命中归属的五条路线（并集，逐段用 `source` 标注）

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

### 推断与判断

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

### 已知局限（caveats）

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

## 增伤手段数据集 `data/nightreign-buffs-v1.03.5.json`

生成器：`macos/DataSources/generate_buffs.py`（Python 3 标准库，运行 `cd macos/DataSources && python3 generate_buffs.py`，不联网、结果确定可复现）。

### 来源表

| 来源 | 内容 | 许可 / 用途 |
| --- | --- | --- |
| 本地导出参数表 `macos/DataSources/raw/params/*.csv` | regulation 1.03.5（容器 10350000）、exe 1.3.3.0。使用 SpEffectParam、AttachEffectParam、AttachEffectTableParam、EquipParamAccessory、EquipParamGoods、EquipParamWeapon、Magic、Bullet、PermanentBuffParam | 游戏内资料，仅用于同人工具数值展示 |
| 本地导出文本 `macos/DataSources/raw/msg/{zhocn,engus}/{item,menu}_dlc01/*.json` | AttachEffectName、AccessoryName、GoodsName、WeaponName、MagicName、PermanentBuffName、SpEffectName、SpEffectInfo（基础档与 `_dlc01` 增量合并，后者覆盖前者；所有文本已 strip 去除尾随换行） | 同上 |
| Smithbox Paramdex (NR) `vawser/Smithbox@f5969c060cea240476e9dd4d6a64eafa9dbafaab` | `PARAM/NR/Param Meta/SpEffectParam.xml` 的字段默认值；`PARAM/NR/Param Enums/` 的 ATK_SUB_CATEGORY、SP_EFE_WEP_CHANGE_PARAM、ATKPARAM_ATKATTR_TYPE、ATKPARAM_SPATTR_TYPE、SP_EFFECT_SPCATEGORY。均已转写为脚本内常量表，运行时不联网 | MIT |
| Smithbox Paramdex (ER) 同 commit `PARAM/ER/Defs/SpEffect.xml` | 字段日文说明（`攻撃側：物理ダメージ倍率`＝对已算出的伤害乘算；`物理攻撃力倍率`＝对攻击力数值乘算；`同一カテゴリ内での優先度（低い方が優先）`）。NR 的 paramdef 是精简版、不含日文说明，故用 ER 的同结构 paramdef 作字段语义参考 | MIT |

### 字段映射

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

### 推断部分（非参数直连）

- **叠加规则**：`stackingRules.zh` 全文是依据 SpEffectParam 的 `spCategory` / `categoryPriority` / `saveCategory` / `stateInfo` 四个字段的参数结构推断，并结合 Paramdex 的 SP_EFFECT_SPCATEGORY 枚举语义（10 = Stack Self 可自叠、20 = Reset on Apply、100–204 = Remove Previous、1000–1006 = Apply Highest by Category Priority、10000+ = Apply First）。**未经木桩全面实测**，请当作参数层面的默认规则。
- **推断来源条目**：战技（Ash of War）、角色技艺／绝招／被动、以及少数角色专属遗物效果（如公爵 7290001、7010701）由游戏事件脚本（ESD/EMEVD）挂载，参数表里没有任何列指向它们。这部分用 Paramdex 社区行名的前缀白名单（`[Relic*]`、`[Talisman]`、`[Item*]`、`[Incantation]`、`[Sorcery]`、`[Weapon*]`、`[AoW]`、`[Skill - *]`、`[Ultimate - *]`、`[Passive - *]`、`[Magic Cocktail]`、`[Interactable Effect]`、`[Libra Deal]` 等）反推来源类型，每条都带 `sources[].inferred: true` 与 `paramRowCategory`。共 344 条 buff 只有推断来源。
- **HeroParam**：经 NR paramdef 核对，HeroParam **没有任何 SpEffect 列**；其 `heroStatusParamId` 只通向 HeroStatusParam，后者的 `attackRate` / `abilityReinforce` 是随等级变化的属性成长，不是 buff，故未纳入。角色技艺／绝招的增伤改由上面的推断来源覆盖。
- **dark = 圣**：沿用本项目既有结论，参数里的 `dark*` 槽位在本作对应「圣」属性。

### 已知局限

1. 344 条 buff（41%）只有推断来源，其物品归属未经参数验证；113 条 buff 没有简体中文名（游戏内无对应 FMG 文本），保留英文名与 `paramName`。
2. `affectsAllies`（= effectTargetFriend 原始值）在绝大多数玩家侧 buff 上都是 1（目标掩码全开），**不能**据此判断队友是否共享。
3. 少数 `direction: "decrease"` 的条目其实是挂给敌人的 debuff（如「酸蚀喷雾」physicsAttackRate 0.85），本数据集不区分施加对象，页面应按 `direction` 过滤。
4. 8 条 buff 的来源超过 40 个（匕首／曲剑等大批武器共享同一出血被动），已截断并用 `sourcesTruncated` 标出真实条数。
5. 未覆盖：AtkParam_Pc 层面的攻击力倍率修正（`spEffectAtkPowerCorrectRate_*`）、多人缩放、敌人属性弱点；这些属于其他数据集的范围。

### 第二轮核验修复补充（skills）

（补进 nightreign-skills 一节）

第二轮核验修复（regulation 10350000，schemaVersion 仍为 2，纯增字段、无破坏性改动）：

1. **武器物理伤害类型落地**。weapons[] 新增 `atkAttribute` / `atkAttributeZh` / `atkAttribute2` / `atkAttribute2Zh`（取自 EquipParamWeapon 同名列，枚举复用 enums.atkAttribute）。此前 2205 段命中里有 1065 段（48%）的 AtkParam_Pc.atkAttribute 是 253 / 252 的间接引用（「沿用武器的 atkAttribute / atkAttribute2」），数据集内无处可查，「按伤害类型加权做增伤排名」这一核心用途对这些段走不通。新增 usage["伤害类型（斩 / 打 / 突）"] 与 fieldNotes.weaponAtkAttribute 说明解析步骤，并指明与 bosses 数据集 fights[].damageRates（standard / slash / strike / pierce）的对接方式。为省 96 KB 体积未重复写英文名，英文名查 enums.atkAttribute[str(值)].en。

2. **overrideAecId 悬空引用不再写出**。生成时以 AttackElementCorrectParam 的 ID 列校验 AtkParam_Pc.overwriteAttackElementCorrectId；本版本 1001 火焰唾球的两段（303215900 / 303215901）指向不存在的 AEC 行 1005，已不写出该字段（记入 caveats）。写出的 overrideAecId 保证在表中存在。AttackElementCorrectParam 本身仍不收录，只读其 ID 列作校验。

3. **跨条目误配段统一丢弃**。SwordArtsParam / Magic 的 atkParamId 锚点与子弹链存在指向别的战技 / 法术的残留引用。判据为「该 AtkParam 行的 Paramdex 行名点名的技能与本条目的名字键完全不相交」，行名匹配路线（source 含 n）与 "A/B/C - Slash" 式真共用行不受影响。本版本丢弃 4 段：308 突进冲击←300000870 '[AoW] Spectral Lance'、1051 米凯拉的光环←301604902 '[AoW Cleanrot Spear] Sacred Phalanx'、1200 风暴管束者←300000700 '[AoW] Square Off - R1'、4381 罗蕾塔的绝招←43810 "[Sorcery] Loretta's Greatbow"。这 4 段原本就不在任何 variant 内，影响的只是 weaponIds 为空的条目所走的「显示全部 hits」回退路径。counts.hits 2205→2201、sharedAtkRows 13→9（uniqueAtkIds 仍 2191）。

4. **不可达动作套显式标记**。hits[] 新增 `noVariant: true`：该战技有 variants、但这个 atkId 不在任何 variant 内，即参数表里存着、本作却没有任何武器会打出的动作套（本版本 550 段，其中 441 段带 motion / flat；大头是 650 野蛮咆哮 268 段、651 战吼 246 段）。新增 counts.hitsWithoutVariant / hitsWithoutVariantDamaging 与 coverage.hitsWithoutVariantNote。没有 variants 的战技其 hits 不做标记。

5. **usage 里的统计数字改为生成时实测**，不再写死：按 ctx 取并集会翻倍的武器 173 把（原文案写 175）、旧 ctx 单选口径取不到段的武器 52 把（原文案写 51，漏算 1166 那把）。

本轮产物实测：紧凑 1,559,196 字节（1.49 MiB），--pretty 2,146,116 字节（2.05 MiB，仅人读、不入包）。counts：weapons 1793、skills 187（有命中 166）、spells 160（有命中 139）、hits 2201、uniqueAtkIds 2191、sharedAtkRows 9、variants 130、weaponsWithVariant 1150。（上一版自述中的 1,180,059 字节 / 2200 段为笔误；另回归说明里把 14010000 称作「高地斧」有误，该 ID 是分岔手斧 / Forked Hatchet，14080000 才是冻壳斧 / Icerind Hatchet。）

### 第二轮核验修复补充（buffs）

（以下为建议补进 PROVENANCE.md 的说明，本轮未改该文件）

## nightreign-buffs-v1.03.5.json — schema v3（增伤手段数据集）

生成器：macos/DataSources/generate_buffs.py（离线运行，不联网）。数据来源与 v1/v2 相同：本地导出的 regulation 1.03.5（container 10350000）参数表 raw/params/*.csv、简中(zhocn)＋英文(engus) FMG 文本（基础档与 _dlc01 增量合并），以及转写进脚本常量表的 Smithbox Paramdex（NR，commit f5969c060cea240476e9dd4d6a64eafa9dbafaab）字段默认值与枚举。本轮未引入任何新数据源，未新增网络依赖。

v3 相对 v2 的变化（完整机读版见产物内的 payload.schemaChangelog）：

1. 新增 `buffs[].activation`（passive / conditional / activated）与 `buffs[].activationSource`。v2 的 notes.ranking 要求页面用 `conditions` / `triggered` 过滤掉有发动条件的 buff，但表中最大的几个倍率由 ESD/EMEVD 脚本开关、参数列里查不到条件，导致那一步在最需要它的条目上是空转的（704301「残血 25% 以下 ×1.5」、8300000-2「双手共持 +12/15/18%」、8310000-2「双手各持 +12/15/18%」、707201-215「处刑人绝招兽化 ×1.62–3.55」的 conditions 与 triggered 全为 null）。判定完全由数据推出、无写死 ID 名单：行名 `[...]` 前缀为 Ultimate/Skill/AoW → activated；行名含 while/whenever/when/upon/during/below/above/alongside/two-hand/wielding/stack → conditional（刻意不含 counter/critical/charged/chain——那是作用范围而非发动条件）；conditions 非空 / triggered / 「全部来源 inferred 且持续时间有限」→ conditional；其余 passive。**增伤排名默认只能乘 activation="passive" 的条目。**

2. 修正 `target` 判定对链式投递的漏判。Bullet 命中槽的识别正则原本带 `$` 锚，形如 `refId1->Bullet10631000.spEffectId0->cycleOccurrenceSpEffectId` 的链式 via 匹配不到，使 1631001『授血（血炎出血）』这条挂在被命中敌人身上的出血累积被标成 target="self"。证据：弹道 10631000/10631005 的 atkId_Bullet 均为 63100，AtkParam_Pc.63100 五个 atk*Correction 全为 100（攻击弹道），SpEffect 1631001 selfTarget=1/opposeTarget=1，按既有规则应判 enemy。现已改判为 target="enemy" / targetSource="bulletHitOffensiveBullet"，与同类的『冰雾』『毒雾』一致。全表仅此 1 条受影响。

3. 排除一条哨兵值行。704000『[Skill - Raider] Retaliate (Defense and Immortality)』的 characterSkillCooldownReduction=0 且 effectEndurance=0，真正负载是本数据集不读的 DamageCutRate=0.25 一组（无赖反击那一瞬的免伤窗口），按字面展示会变成「技艺冷却 -100%」并与真正的遗物档位 0.95/0.925/0.9 混列。排除规则刻意收窄为「全部合格数值都是 valueKind=multiplier 的 economy 字段且为 0，同时 effectEndurance=0」，因此 511060/708920『青露的秘密滴泪』与 1801400『魔法帷幕』（同样带 ×0 消耗倍率但有 15/20/8 秒持续时间、确实让施法免费）不受影响。被排除的行记入 diagnostics.sentinelOnlyRows，不再静默丢弃。

4. `enums.targetSource.bulletHitOpposeOnly` / `bulletHitFriendlyOnly` 的说明改写。effectTargetSelfTarget / effectTargetOpposeTarget 是「异常累积允许打给哪个阵营」的过滤位，不是「SpEffect 挂在谁身上」的证据：SpEffectParam 3176『[Item] Poison Grease (Right) - Poison』同样是 selfTarget=0/opposeTarget=1，却是玩家抹在自己武器上的油脂。这两个位只有在「该 SpEffect 的全部来源都只能由 Bullet 命中槽投递」的前提下才有判定力。判定代码本身一直是对的（本版本 13 条 bulletHitOpposeOnly 结论全部正确），改的是说明文字，以免后续维护者把规则推广到非弹道来源。

5. `displayNameZh` / `displayNameEn` 的消歧顺序调整（全表唯一性保证不变，生成时仍有断言）。新顺序：本地化来源名 → 强度档位 → 武器槽 → 来源类别（武器/遗物/护符/道具/战技/祷告/魔法/技艺/绝招/被动，取自行名 `[...]` 前缀，v3 新增的一级）→ 首个 rates 数值 → 原始英文 Paramdex 行名 → `#spEffectId`。同族（Paramdex 行名词干相同）的条目强制取相同的限定词组合。v2 里有 261 条中文名挂着英文行名做限定词（v3 降至 68 条），且同一档位序列会出现两种风格；v3 修掉了这两点，代价是 `#spEffectId` 兜底由 52 条升到 58 条（同族只要有一个成员需要 ID，全组都带）。实测数量见 counts.displayNameZhFallingBackToSpEffectId，完整 ID 清单见 diagnostics.displayNameZhFallingBackToSpEffectId。

生成时自检（self_check，每次生成自动运行，违反即抛错）在 v2 各项之外新增：activation / activationSource 必须落在 enums 内；有 conditions 或 triggered 的 buff 其 activation 不得为 passive；全部 via 都是 Bullet 命中槽的 buff 其 targetSource 不得为 "default"；不得输出「只靠 ×0 且无持续时间的 economy 哨兵值」入选的行。连续两次生成除 generatedAt 外输出完全一致。

### 第三轮核验修复补充（buffs，schemaVersion 4）

（以下为建议补进 PROVENANCE.md 的说明，本轮未改该文件）

## nightreign-buffs-v1.03.5.json — schema v4（增伤手段数据集）

生成器：macos/DataSources/generate_buffs.py（离线运行，不联网）。数据来源与 v1–v3 相同：本地导出的 regulation 1.03.5（container 10350000）参数表 raw/params/*.csv、简中(zhocn)＋英文(engus) FMG 文本（基础档与 _dlc01 增量合并），以及转写进脚本常量表的 Smithbox Paramdex（commit f5969c060cea240476e9dd4d6a64eafa9dbafaab）。本轮新引用了该 commit 下两份此前未用到的 Paramdex 资料，同样已转写进脚本常量表、运行时不联网：
- ER/Defs/SpEffect.xml 中 motionInterval 的日文字段说明（DisplayName「発動間隔[s]」、Description「何秒間隔で発生するのかを設定」），用于确定该字段是计时机制而非发动条件；
- NR/Param Enums/SP_EFFECT_TYPE.json（SpEffectParam.stateInfo 的枚举，NR ParamMeta 中 stateInfo 声明 Enum="SP_EFFECT_TYPE"），用于给 stateInfo 落中文标签并识别其中的攻击情境门（367 Enhance Critical Attacks、197 Enhance Thrusting Counter Attacks）。

v4 相对 v3 的变化（完整机读版见产物内的 payload.schemaChangelog）：

1. **activation 判定不再把计时列当成发动条件。** v3 的规则③是「conditions 非空 → conditional」，而 conditionFields 里混着两个纯机制字段：motionInterval（效果每几秒重新施加一次）与 isPeriodicEffect（是否按该间隔周期性重新施加）。全表 13472 行中 isPeriodicEffect 置 1 的 33 行逐行核对，全部是 tick／光环行（「[Weapon] Poison Buildup When Below Max HP - Apply Poison」等），两者都不是玩家需要满足的游戏状态。v3 有 210 条 buff 仅凭这两个字段被判成 conditional，其中 8 条是 target∈{self,ally} 的真实无条件增伤——708720 狂热香药·档位2 ×1.45、503550 狂热香药 ×1.35、1733000 夏玻利利的嘶吼 ×1.25、1605000 火焰啊赐予我力量 ×1.20、1660000 黄金树立誓 ×1.15 等，也就是整张表里最常用的几条消耗品与团队增益，按 v3 文档实现的页面会把它们全部排除在默认排名之外。现在只看 conditionFields[].isActivationCondition=true 的列；处刑人 Tenacity（707070/707071）改由新规则 paramRowPassiveTimed 判出（Paramdex 行名前缀为 Passive 且 effectEndurance≠-1——真正常驻的被动是 -1，带 18.5 秒时限说明有人把它打开过），1732『Golden Great Arrow』改由既有的 eventScriptTimedBuff 判出，都不再依赖那个 0.06 秒的 tick。共 73 条由 conditional 改为 passive，4 条由 passive 改为 conditional（见第 4 条）。

2. **新增 scope.attackContexts：作用情境的机读标记。** 游戏在两个互不相干的地方表达「这条倍率只对某种攻击生效」：magicSubCategoryChange1..3（ATK_SUB_CATEGORY，v1 起已导出为 scope.subCategories）与 stateInfo（SP_EFFECT_TYPE，v3 只是一个裸数字）。后者没有机读标记的直接后果是：6 条「强化致命一击」（stateInfo=367，×1.12–1.24）与 4 条「强化突刺反击」（stateInfo=197，×1.10–1.20）在页面看来是对所有攻击生效的常驻增伤——突刺反击那几条的 scope 甚至是 affectsSorcery／affectsIncantation／affectsShaman 全 true，比不标还更误导。v4 把两条来路归一化成 15 个情境键（致命一击、突刺反击、防御反击、连段最后一击、跳跃／冲刺／翻滚／后跳攻击、起手攻击、骑马攻击、蓄力强攻击／蓄力法术／蓄力战技、双手持、双持），配套 enums.attackContext（写明每个键的原始来源）与 enums.stateInfo（36 个观测值的中英文标签）。**attackContexts 非空的条目不得原封不动乘进通用排名，只在用户勾选对应情境时参与乘算**，notes.ranking 第④步已据此改写。注意 attackContexts 与 activation 是正交的两条轴：这类条目装上就一直生效（activation=passive），受限的是作用范围而不是发动时机，所以第③步拦不住它们。武器／法术门类过滤（近战／远程武器攻击、战技攻击、各流派魔法祷告等）刻意不收进 attackContexts，它们属于伤害构成加权，仍只出现在 scope.subCategories 里。

3. **target 判定补上第二个命中槽，修正 33 条。** 命中投递槽的识别此前只认 Bullet.spEffectId0..4，漏了 SpEffectParam.atkOccurrenceSpEffectId（攻击命中时发动）。结果是：各种油脂与「附加属性武器」的异常累积行（3176 毒油脂、3151 催眠油脂、3191 出血油脂、1449001 冰霜武器、1632002 血炎武器、1723001 附毒祷告等）标成 target="self"，而结构完全相同、只是改由弹道投递的同类（1722000 毒雾、1631001 授血）标成 target="enemy"。以 3176 为例：effectTargetSelfTarget=0／effectTargetOpposeTarget=1，参数层面根本不允许挂在玩家身上，via 正是 refId_default->atkOccurrenceSpEffectId。现已按与弹道分支同构的规则处理，新增 targetSource 取值 attackHitOpposeOnly／attackHitSelfOnly／attackHitStatusPayload；33 条改判 enemy（全部落在 status／flag 轴，countsAsDamage=false，不影响任何伤害乘积），3 条正确留在 self（7036901「连段最后一击后提升攻击力」、8660203/8660206「致命一击附带出血」的攻击力加算）。**这些 target=enemy 的条目仍然是玩家的异常累积手段**，只是效果挂在被命中的对象身上；做「异常状态累积」榜时应按 sources[].kind 取玩家可获得的来源，不要沿用「只留 self／ally」的过滤。

4. **新增 stackLadder，并修正 4 条叠层词条的 activation。** 7069001「每次打倒封印监牢里的囚犯，能提升攻击力」在数据集里是 ×1.05 且 v3 判为 passive，会被无条件乘进排名；但参数表里 7069002–7069010 一路涨到 ×1.6289，7069201–7069210 涨到 ×1.9672，8988200「玛雷家的庇佑」与 8998000「复仇的庇佑」更是各有 100 层（×1.011→×1.70、×1.007→×1.40）。它们都要先反复达成条件才涨层，第 1 层的数值既不是无条件的、也不是该词条的上限。检测是结构性的、无写死 ID：ID 连续、Paramdex 行名为空、不是已收录的 buff、除倍率外 15 个列完全相同、非默认倍率键集合相同、至少一个 multiplier 且逐层严格递增，且 saveCategory≠-1——最后一条把「[Relic] Improved Throwing Pot Damage +1/+2」这类可分别装备的词条档位（saveCategory 全为 -1）排除在外。命中 4 条，全部改判 conditional（7069001/7069201 由 localizedNameCondition 判出，另两条由 stackLadderTier1 判出）。数据集仍只收录每条阶梯的第 1 层，满层数值见 buffs[].stackLadder.topRates 与 diagnostics.stackLadders；同层互斥（spCategory 落在 removePrevious 区间），任何时刻只有一层生效，绝不能把各层相乘。

5. **更正 v3 文档里一句与参数相反的结论。** v3 的 enums.targetSource.bulletHitOpposeOnly 与 schemaChangelog[0] 第⑤条都写「SpEffectParam 3176 毒油脂……来源是 EquipParamGoods，根本没走 Bullet 命中槽……本数据集正确地把它标成 target="self"」。该举例是错的：3176 走的正是 atkOccurrenceSpEffectId 命中槽，且 effectTargetSelfTarget=0。相关措辞已改写为「阵营过滤位必须在**已确认投递路径是命中槽**的前提下才有判定力」，并换上真实的保留反例——本版本仍有 42 条带 oppose-only 阵营位、却只能靠 Paramdex 行名或武器行为槽追溯来源、投递路径无法确认因而保守判成 self 的条目，完整清单导出为 diagnostics.opposeBitsWithoutHitSlot，并注明「这是缺省而不是已证实的结论」。v3 的 changelog 条目保留原文并追加「v4 更正」段落，不做静默覆盖。

6. 抽查清单口径调整：diagnostics.topUnconditionalMultipliers 由 15 条扩到 40 条，筛选条件加上「scope 里既没有 attackContexts 也没有 subCategories」，即真正会被原封不动乘进通用排名的那一批；受作用范围限制的 86 条改列在新的 diagnostics.contextGatedMultipliers（带 attackContexts／subCategories／gateFrom）。v3 的清单只取前 15 条、阈值卡在 ×1.28 且不区分作用范围，致命一击族与突刺反击族正好排在第 16 名开外，躲过了上一轮的人工抽查。

生成时自检（self_check，每次生成自动运行，违反即抛错）在 v3 各项之外新增 6 条：conditionFields 里 isActivationCondition=false 的键集合必须恰好等于 TIMING_CONDITION_FIELDS；带**非计时类** conditions 或 triggered 的 buff 其 activation 不得为 passive；每个 scope.attackContexts 取值必须落在 enums.attackContext 内，且必须能从该行实际携带的 subCategories 或 stateInfo 推出来；非 0 的 stacking.stateInfo 必须能在 enums.stateInfo 里查到；带 stackLadder 的条目 activation 必须是 conditional，且 tiers 与 tierSpEffectIds、topRates 与 rates 的键集合自洽；「全部 via 都是命中槽」的判定扩到 atkOccurrenceSpEffectId。连续两次生成除 generatedAt 外输出完全一致。本轮未 commit／push，未改 PROVENANCE.md，未触碰其它数据集。

### 第四轮核验修复补充（buffs，schemaVersion 5）

第三轮独立复核报出 1 条 medium ＋ 3 条 low，全部核实成立并修复；schemaVersion 4 → 5，仍只增字段／只增取值。

1. **命中投递槽补全第三条路径，target 再修正 43 条 self→enemy。** v4 只把 `Bullet.spEffectId0..4` 与 `atkOccurrenceSpEffectId` 当作命中槽，`EquipParamWeapon.spEffectBehaviorId0..2`（武器命中时交给被命中者的负载）与 `AttachEffectParam.onHitSpEffect`（「攻击附带异常状态」词条的命中槽）没纳入，43 条与油脂行逐列同构的异常累积行仍是 self。依据：106010『Lvl 1-2 Poison +45』（毒匕首）与已判 enemy 的 3176『Poison Grease (Right) - Poison』除阵营位与投递槽外逐列相同；油脂真实链路是 `EquipParamGoods 1460 → SpEffect 3175（挂在玩家身上的 30 秒 buff）→ atkOccurrenceSpEffectId 3176`，累积值在链的外一跳；105000『Blood Loss +30』自带出血爆发伤害，不可能发给握刀者。判定按投递槽 → 阵营位 → 负载类型三问，结构性、无 ID 名单；新增 targetSource `weaponHitOpposeOnly`(5)／`weaponHitSelfOnly`(0)／`weaponHitStatusPayload`(38)。buffsByTarget：self 759→716、enemy 65→108。这 43 条全是 `rateGroups=["flag","status"]`，**伤害排名的乘积一个数都没动**；「异常状态累积」榜必须按 `sources[].kind` 取玩家可得来源，不能只留 target=self。
2. **新增 `buffs[].selfInflictedStatus`（20 条）标出自伤型异常累积**：target=self、阵营位 `S=1/O=0`、且带 status 组加算点数（`valueKind="flat"` 的 `xxxAttackPower`）的行（切腹自身出血 +9999、癫火系自身发狂 +30、血量未满时累积中毒等），累的是玩家自己；`xxxInflictRate`（「自身造成的累积倍率」，如艾奥尼亚蝶 diseaseInflictRate=1.3）方向相反，刻意不计入。异常累积榜需排除这 20 条。
3. **enums.stateInfo 以实测为准是 37 项**（上文写 36 项的是散文错误，JSON 一直是 37 且与全表非 0 取值双向相等）；新增 `counts.stateInfoLabels`，self_check 改为双向相等断言。
4. **stackLadder 口径写进 `notes.stackLadder`**：`tiers` 含第 1 层；`tierSpEffectIds` 从第 2 层起（长度 tiers-1，升序，不会作为独立 buff 出现）；`topRates` 为最后一层数值；`saved` = saveCategory≠-1。排除举例更正为参数表里真实存在的 7040300／7040301／7040302（后者是空行名 ×1.35，7040301 靠 saveCategory=-1 才没被误判成阶梯）。

self_check 新增：stateInfo 枚举与观测值双向相等；selfInflictedStatus 只出现在 target=self 且含 status 组的条目并三方计数一致；stackLadder 的 tierSpEffectIds 升序、不含自身、与已收录 ID 无交集；命中槽正则扩到 spEffectBehaviorId0..2 与 onHitSpEffect。
