#!/usr/bin/env python3
"""生成「首领数据」数据集（nightreign-bosses-v1.03.5.json）。

覆盖：8 个本体夜王 + DLC 的哈尔莫妮亚/史柴格斯 + 永夜之王（Everdark Sovereign）与
救世旗手（Salvation's Standard-Bearers）变体，
以及守夜 Boss（Night Boss Threat）与野外 Boss（Field Boss Threat）。
每条记录给出单人基准血量/韧性、八系承伤倍率、七种异常抗性阈值，
以及 2 人 / 3 人的血量与削韧、异常累积缩放。

上游数据（均已导出在 raw/ 下，不入 git）：
  raw/params/NightBossMenuParam.csv      夜王菜单（名称/远征/官方弱点标注/各深度出现权重）
  raw/params/NpcParam.csv                敌人实体数值（hp、削韧、承伤倍率、异常抗性）
  raw/params/MultiPlayCorrectionParam.csv 人数缩放：client1=双人 / client2=三人
  raw/params/SpEffectParam.csv           缩放倍率本体（maxHpRate / saReceiveDamageRate / *DamageRate）
  raw/params/SpEffectSetParam.csv        深夜「变异个体」（红化）的 VFX + 数值组合
  raw/params/ChaosMatchingCorrectParam.csv        深夜深度 1–5 的数值缩放（spEffect00..04）
  raw/params/ChaosMatchingRankControlParam.csv    深度 1–5 的全局控制（诅咒率/挑战/天变权重）
  raw/params/ChaosMatchingMutationCategoryParam.csv 每个深度各类敌人被变异的「个数」
  raw/msg/<lang>/menu_dlc01/CL_MenuText(.._dlc01).json  夜王名、远征名、夜王说明、深夜/深度/变异个体
  raw/msg/<lang>/item_dlc01/NpcName(.._dlc01).json      Boss 简中/英文名
  raw/msg/<lang>/menu_dlc01/TutorialTitle(.._dlc01).json 特异地形名（开放地图地块的地形变体）
  raw/msg/<lang>/menu_dlc01/TutorialBody(.._dlc01).json  地图图标说明 403200（场景头目 / 坑道入口 / 封印监牢）
  raw/msb/MsbEnemyParts.csv + manifest.json  地图 MSB 的敌人放置（extract_msb.py 导出，schemaVersion 4）
  raw/params/LotResultPlayAreaParam / LotResultSmallBaseAndSpot / SmallBaseAndSpotAttachPoint /
             SmallBaseMapVariationParam / ChaosMatchingMutationEnemyTableParam / LotResultMapPatternFlag /
             SmallBaseEnemyLotMapCombinationParam / SmallbaseInvationNpcParam   地图块何时进入远征（出场场合）
  NpcParam/NightBossMenuParam 的 Name 列 = 社区 Paramdex 行名（vawser/Smithbox@f5969c0）

schemaVersion 3 新增（只增不删）：
  * 名字：nameEvidence / nameApprox / nameSourceUrl / nameNote / hidden；
    删掉了 v2 里按《艾尔登法环》官方简中手工补的 14 个 manual 译名
    （游戏文本里找不到完全一致的字符串，一律改成 nameZh 留空）。
  * 深夜：顶层 deepOfNightDepths / deepOfNightTiers / mutations / mutationCategories，
    每个 fight/variant 上的 chaosCorrectId / depthTierId / depthStats[1..5] /
    mutationSetId / mutationPool，夜王条目上的 depthChanceWeights。
  * 人数缩放：scalingTiers.*.fullEffects（client1/client2 SpEffect 的全部非默认字段）、
    duo/trio 的 attackRate（部分档位多人时敌人攻击力**会上升**）。

schemaVersion 4 新增（只增不删，tier / tiers / 名字 / hidden / 数值一律不动；旧字段只改了 mapZh 三个地图名，见下）：
  * 出场场合 roles：v3 的 tier 只看 multiPlayCorrectionParamId 的档位名（Field/Night Boss Threat），
    那是缩放档位不是「在哪出现」。现在按「地图 MSB 的 Enemy part（npcParamId）→ 地图块 →
    决定地图块何时进入远征的参数」重判：LotResultPlayAreaParam.bossId1/2/extraBossId1/2 = 夜晚首领；
    ChaosMatchingMutationEnemyTableParam.categoryId 120 = 场景头目、160 = 封印监牢；
    LotResultSmallBaseAndSpot 全部落在 Raid / Night Horde 修饰的地图模式 = 突袭 / 地图事件；
    挂到大空洞高塔挂点 = tower；其余据点/地点地图块 = 据点首领；m60_* 开放地块按该地块该地形变体的
    变异类别（ChaosMatchingMutationEnemyTableParam 里 smallBaseId = 0 的行，地块号由 mapUnk_1..3 解码）
    分：含 120 = 场景头目、没有 120 而有 150/151 = 坑道精英（mine）、只有 110 = 据点首领、都没有 = 场景头目；
    SmallbaseInvationNpcParam = 黑夜入侵者；夜晚首领地图块里 7741 档 = 守夜前哨；
    只在首领战地图里、零奖励、同图另有掉奖励首领 = 随从/召唤物。枚举与口径见 ROLE_DEFS。
  * 每个 fight / variant 追加 roles / roleEvidence / rowRoles，分组追加 roles / roleVariants；
    顶层追加 roleNames / roleSummary / roleSummaryDetail / placementMaps，notes 追加 roleAudit。
  * 复核修正：前哨（7741）所在地图块又挂到大空洞高塔时只标 prelude、不标 tower；
    坐骑/辅助实体（不带首领奖励表、卢恩 ≤ 同图首领 5%，如送葬马、贪食魔龙的 c2150 辅助实体）
    判 summon，野外首领地图块里的同类实体同样处理；地图号在地图块区段却没有任何表引用的地图
    （m46_90）按未启用地图块；「圣树骑士」例子改为罗蕾塔 = c3252 卡利亚禁卫骑士
    （WeaponCaption + 按 chrId 编号的掉落表 23252000 为证）；LotResult* 表的 modifier 套用
    PATTERN_MODIFIER 是推断（Meta 未标 Enum），旁证在生成时实测断言，写进 caveats。
  * 第二次复核修正：开放地块不再一律算 field——按地块变异类别，坑道里的精英（Troll (Mine) 46000110、
    大空洞坑道的挖石山妖 46030010）改判新增的场合 mine「坑道精英」；开放地块上换了模型、占位 AI、
    不掉奖励的辅助实体（“冻结冰雾”玻列琉斯 45030020，模型 c0100）判 summon；不掉奖励、与带对话脚本的
    实体同属一个 MSB 实体组的剧情敌人（神皮使徒 35600060）判 event；roleNames.field.zh 改用游戏文本
    「场景头目」（TutorialBody 403200）；突袭证据补 LotResultMapPatternFlag.targetBoss（Meta：Refs =
    NightBossMenuParam），大空洞 4 块没被 Raid 修饰抽到的据点改写成「推断」；roleAudit 例子加到 12 个。
  * 旧字段的值改动只有「标签改取游戏文本」一类（键与结构不变）：mutationCategories[].mapZh
    （林薇尔德 → 宁姆韦德、陨石坑 → 火山口、笼罩之城 → “隐城”诺克拉缇欧）、categoryZh 120
    （野外首领 → 场景头目）、变体 labelZh 里的同一批词（陨石坑 → 火山口、诺克拉提欧 → “隐城”诺克拉缇欧、
    野外首领 → 场景头目），以及 caveats / notes.deepOfNightAudit 里引用这些标签的句子。

关键约定（与 PROVENANCE 一致）：
  * NpcParam 的 def_* 字段全部是 100，真正的属性减伤走 *DamageCutRate：
    1.35 = 多受 35% 伤害，0.5 = 只受 50%；dark 槽在本作用于「圣」属性。
  * NpcParam.hp **不是**玩家面对的血量。每一行 Boss 的 spEffectID0..31 上都挂着常驻
    SpEffect（「Enemy Scaling: Field/Night/Final Boss Threat」「[Everdark Sovereign
    Scaling] …」「[DLC Scaling] …」等），它们带 maxHpRate。真实单人血量 =
    NpcParam.hp × 所有无条件常驻 SpEffect 的 maxHpRate 连乘。
    本数据集里 hpBase = 原始字段、hpMultiplier = 连乘倍率、hp = 二者乘积（玩家血量）。
    带 invocationConditionsStateChange1 = 2287 的行只在「深夜」模式生效，单列在 deepOfNight。
  * 多人缩放：NpcParam.multiPlayCorrectionParamId → MultiPlayCorrectionParam
    →（client1SpEffectId 双人 / client2SpEffectId 三人）→ SpEffectParam。
  * SpEffectParam 里两组容易混淆的异常字段（行名反查确认）：
      *DefDamageRate（f32）= 承受的异常「累积量」倍率
        708456 Neutralizing Boluses (Reduce Buildup) = 0.5、708302 Fetid Pot
        (Increase Status Buildup) = 1.25、19390 [NPC] Take 30% Death Blight Buildup
        只改 curseDefDamageRate = 0.3。→ 本数据集的 buildupRate。
      *DamageRate（u8 百分比）= 异常「发动时的伤害」倍率
        95000 Reduce Blood Damage by 30% = 70、8830000 Ailments Cause Increased
        Damage = 125。→ 本数据集的 ailmentDamageRate / poisonRate。
      真正增减阈值的是 change*ResistPoint（护符 +75 那种），人数缩放行全为 0，
      也就是多人**不**改阈值。
  * resist_* 是异常累积阈值（越大越难触发），999 视为免疫。
  * 深夜（The Deep of Night）三层缩放：
      1) NpcParam.chaosMatchingCorrectParamId → ChaosMatchingCorrectParam 的
         spEffect00..spEffect04 = 深度 1..5 的「[Deep Night Scaling] Tier X, Depth N」行，
         带 maxHpRate / *AttackPowerRate / staminaAttackRate / saReceiveDamageRate，
         并且自身 stateInfo = 2287；
      2) stateInfo 2287 会点亮该敌人 spEffectID0..31 上 invocationConditionsStateChange=2287
         的「[Deep of Night Everdark Scaling] / [DLC Deep of Night Scaling]」修正行
         （把永夜之王/DLC 的加成压回去）；
      3) 「变异个体」（玩家口中的红化）：NpcParam.chaosMatchingSpEffectSetParamId →
         SpEffectSetParam「Set: Deep Night Mutation - VFX + Scaling」→
         spEffectId1 = 红光 VFX 档位（4480..4483 / 4485），spEffectId2 = 数值档位
         （7200/7210/7215/7220/7230/7240/7241，最高 2 倍血 2 倍伤害 2 倍卢恩）。
      四类缩放的 spCategory：深度 0、常驻威胁档位 0、[Deep of Night Everdark Scaling] 20（个别
      100）、[DLC Deep of Night Scaling] 0、变异 203、人数 140。**0 不是一个分类**（Paramdex：
      spCategory 决定「互相覆盖」的行为，0 表示不参与覆盖），所以同为 0 的几类仍然各自生效、
      倍率连乘；真正需要担心覆盖的只有非 0 的分类，生成时逐行断言过没有冲突。
      详见 notes.deepOfNightAudit。

用法：
  cd macos/DataSources && python3 generate_bosses.py [--raw raw] [--out ../../data/nightreign-bosses-v1.03.5.json]
"""

from __future__ import annotations

import argparse
import csv
import json
import re
from collections import Counter, defaultdict
from datetime import datetime, timezone
from decimal import ROUND_HALF_UP, Decimal
from pathlib import Path

SCHEMA_VERSION = 4
GAME_VERSION = "v1.03.5 + DLC1"
DATA_VERSION = "regulation 10350000"
PARAMDEX_REV = "f5969c060cea240476e9dd4d6a64eafa9dbafaab"

HERE = Path(__file__).resolve().parent
DEFAULT_RAW = HERE / "raw"
DEFAULT_OUT = HERE.parents[1] / "data" / "nightreign-bosses-v1.03.5.json"

# ---------------------------------------------------------------- 字段映射表

# 输出字段 → NpcParam 的 *DamageCutRate 前缀。dark 在本作是「圣」。
DAMAGE_RATES = [
    ("standard", "neutral"),
    ("slash", "slash"),
    ("strike", "blow"),
    ("pierce", "thrust"),
    ("magic", "magic"),
    ("fire", "fire"),
    ("lightning", "thunder"),
    ("holy", "dark"),
]

# 输出字段 → NpcParam 的 resist_* 列
RESISTS = [
    ("poison", "resist_poison"),
    ("rot", "resist_desease"),
    ("bleed", "resist_blood"),
    ("frost", "resist_freeze"),
    ("sleep", "resist_sleep"),
    ("madness", "resist_madness"),
    ("death", "resist_curse"),
]

IMMUNE = 999  # resist_* 达到该值视为免疫

# EFFECTIVE_AFFINITY 枚举（Paramdex Param Enums/EFFECTIVE_AFFINITY.json）+ 简中译名
AFFINITY_NAMES = {
    0: ("无", "None"),
    1: ("魔力", "Magic"),
    2: ("火", "Fire"),
    3: ("雷", "Lightning"),
    4: ("圣", "Holy"),
    5: ("中毒", "Poison"),
    6: ("猩红腐败", "Scarlet Rot"),
    7: ("出血", "Blood Loss"),
    8: ("死亡", "Death Blight"),
    9: ("冻伤", "Frostbite"),
    10: ("睡眠", "Sleep"),
    11: ("发狂", "Madness"),
}

# 夜王菜单行名尾段（"Tricephalos / Gladius" → "Gladius"）→ 该夜王涉及的 chrId
NIGHTLORD_CHRS = {
    "Gladius": [7500],
    "Adel": [7510, 7511],
    "Gnoster": [7520, 7521, 7530],   # 格诺斯塔（蛾）+ 亚尼姆斯 + 弗堤士（螯剪）
    "Maris": [7540, 7541],
    "Libra": [7560, 7561, 7570],     # 利普拉 + 永夜 + 持秤商人（伪装）
    "Fulghor": [7600],
    "Caligo": [4900, 4901],
    "Heolstor": [7580],
    "Harmonia": [7620, 4641],        # 女武神本体 + 永夜蠕虫
    "Straghess": [7610],
}

# 只在永夜之王 / 救世旗手战里登场的 chrId
EVERDARK_CHRS = {7511, 7561, 4901, 4641, 7521, 7541}

# 普通远征最终战 / 永夜之王（含救世旗手）战实际使用的行。
# 一场战斗里同时出场或分阶段登场的行都算 main，因此慧心虫/弗堤士/玛利斯的
# 一、二阶段行都在内（修复前只列了其中一个阶段，导致另一阶段被并进来后取到偏低数值）。
MAIN_NPC_IDS = {
    # 普通远征
    75000020, 75100020, 75200020, 75200110, 75300010, 75300110,
    75400020, 75600020, 76000010, 49000010, 75800010, 75802010,
    76100010, 76200010,
    # 永夜之王 / 救世旗手
    75000210, 75110010, 75200120, 75200030, 75300120, 75300020,
    75210010, 75400100, 75410000, 75610010, 76001010, 49010010,
    76200310, 76200210, 46410000,
}

# 深夜模式（The Deep of Night）常驻 SpEffect 的触发状态号
DEEP_OF_NIGHT_STATE = 2287

# 夜王侧实体名（chrId → 简中），来自 NpcName 游戏文本
ENTITY_ZH = {
    7500: "格拉狄乌斯", 7510: "艾德雷", 7511: "艾德雷", 7520: "格诺斯塔", 7521: "亚尼姆斯",
    7530: "弗堤士", 7540: "玛利斯", 7541: "玛利斯", 7560: "利普拉",
    7561: "利普拉", 7570: "持秤商人（利普拉伪装）", 7580: "黑夜轮廓",
    7600: "弗格尔", 7610: "史柴格斯", 7620: "哈尔莫妮亚", 4900: "卡莉果",
    4901: "卡莉果", 4641: "哈尔莫妮亚",
}
# 按 ID//1000 的更细覆盖（布德奇冥二阶段换了模型）
ENTITY_ZH_SUB = {75802: "布德奇冥", 75809: "布德奇冥", 76109: "史柴格斯（冲动）"}

# Paramdex 括号/后缀 → 简中变体说明
VARIANT_ZH = {
    "Boss": "远征首领",
    "Boss Phase 1": "远征首领 · 一阶段",
    "Boss Phase 2": "远征首领 · 二阶段",
    # 游戏内简中把 Everdark Sovereign 译作「永夜之王」（CL_MenuText 131040），
    # 不是社区惯用的「至暗之王」。玩家在游戏里看到的是「永夜」，这里统一跟随官方文本。
    "Everdark Sovereign": "永夜之王",
    "Everdark Sovereign Phase 1": "永夜之王 · 一阶段",
    "Everdark Sovereign Phase 2": "永夜之王 · 二阶段",
    "Everdark Sovereign, Single Dog": "永夜之王 · 单体犬",
    "Everdark Phase 1?": "一阶段（Paramdex 标为推测）",
    "Everdark Phase 2": "二阶段",
    "Everdark Worm": "蠕虫",
    "Enhanced Boss": "永夜之王",
    "Single Dog": "单体犬",
    "Random Encounter": "随机遭遇",
    "Raid": "联机突袭",
    "Expedition": "远征首领",
    "Dreglord Intro": "开场演出",
    "Shrouded": "伪装形态",
    "Shrouded, Boss": "伪装形态 · 首领",
    "Shape of Night": "黑夜轮廓",
    # 「场景头目」= 游戏文本对 Field Boss 的叫法（TutorialBody 403200 地图图标说明，engus「Field Boss」；
    # 生成时用 map_icon_names 断言），v3 写的是说明性译名「野外首领」
    "Field Boss": "场景头目",
    "Night Boss": "守夜首领",
    "Night Group Boss": "守夜群体首领",
    "Duo Night Boss": "守夜双人组",
    "Night Boss Add": "守夜首领 · 召唤物",
    "Tutorial": "教程",
    # 地形名与 mutationCategories.mapZh 同一组游戏文本（terrain_names，生成时断言一致）；
    # v3 写的是「陨石坑」「诺克拉提欧」（后者还是错字，游戏文本一律写「诺克拉缇欧」）
    "Crater": "火山口",
    "Noklateo": "“隐城”诺克拉缇欧",
    "The Oldest Gaol": "最古老的牢狱",
    "Ruins Boss": "遗迹首领",
    "Underground Fort Boss": "地下堡垒首领",
    "Eastern Underground Fort Boss": "东部地下堡垒首领",
    "Eastern Underground Fort Variant": "东部地下堡垒变体",
    "Western Underground Fort Variant": "西部地下堡垒变体",
    "Castle Basement": "城堡地下",
    "Remembrance": "追忆",
    "Tibia Mariner Summon": "提比亚唤声船召唤",
    "Transforming?": "变身形态",
    "Template": "模板行",
    # " - xxx" 后缀
    "Halberd": "长戟", "Spear": "长枪", "Mace": "槌", "Sword": "剑",
    "Greatsword": "大剑", "Dagger": "匕首", "Twindaggers": "双匕首",
    "Twinaxes": "双斧", "Longhaft Axe": "长柄斧", "Hammers": "双锤",
    "Greataxe": "大斧", "Darkness": "黑暗", "Lightning": "雷",
    "Mimic Tear": "仿身泪滴", "Sword+Halberd": "剑 + 长戟",
    "Sundered": "分离体", "Sword Sundered": "断剑分离体", "Dual Swords": "双剑",
    "Demon from Below": "洞底恶魔", "Demon in Pain": "负伤恶魔",
    "Straghess": "史柴格斯阵营", "Glaive": "剑刃戟", "Flail": "连枷",
    # 黑夜入侵者对应的夜行者职业
    "Wylder": "追踪者", "Guardian": "守护者", "Ironeye": "铁之眼", "Duchess": "女爵",
    "Raider": "无赖", "Revenant": "复仇者", "Recluse": "隐士", "Executor": "执行者",
    "Scholar": "学者", "Undertaker": "送葬者", "Priestess": "女巫",
    # 地点 / 刷新位说明
    "Evergaol": "封印监牢", "Encampment": "营地", "Fort": "堡垒", "Ruins": "遗迹",
    "Castle": "城堡", "Mountaintop": "山顶", "Duo": "双人组", "Large": "大型", "Small": "小型",
    "Blacksmith Boss": "铁匠铺首领", "Blacksmith Group Boss": "铁匠铺群体首领",
    "Ruins Group Boss": "遗迹群体首领", "Great Church Boss": "大教堂首领",
    "Great Church Group Boss": "大教堂群体首领", "Marsh Boss": "沼泽首领",
    "Marsh Group Boss": "沼泽群体首领", "Crater by fog gate": "火山口（雾门旁）",
    "Frost Marsh Elite": "冰霜沼泽精英", "Eastern Underground Fort Elite": "东部地下堡垒精英",
    "Western Underground Fort Elite": "西部地下堡垒精英",
    "Western Underground Fort Group Boss": "西部地下堡垒群体首领",
    "Night Horde": "夜之群袭", "healthbar": "血条实体", "Treespear": "树枪",
    "Tibia Mariner Torso": "唤声船躯干", "Undertaker Remembrance": "送葬者追忆",
    "Undertaker Remembrance - Unused?": "送葬者追忆（未使用）", "Unused?": "未使用",
    # 「XXX Prelude」= 该 Boss 的登场演出
    "Fallingstar Beast Prelude": "坠星兽物 · 登场演出",
    "Great Red Bear Prelude": "大红熊 · 登场演出",
    "Lord of Blood Prelude": "鲜血君王 · 登场演出",
    "Nameless King Prelude": "无名王者 · 登场演出",
    "Smelter Demon Prelude": "镕铁恶魔 · 登场演出",
}

# 无 Paramdex 行名 / 需要人工说明的夜王行标签。labelEn 可能是合成文本，
# 原始 Paramdex 行名另存在 fight.paramdexName 里。
NIGHTLORD_LABEL_OVERRIDE = {
    75800010: ("黑夜轮廓 · 远征首领", "Heolstor (Shape of Night) (Boss)"),
    75801000: ("黑夜轮廓", "Heolstor (Shape of Night)"),
    75802000: ("布德奇冥 · 二阶段", "Heolstor the Nightlord (Phase 2)"),
    75802010: ("布德奇冥 · 二阶段（远征首领）", "Heolstor the Nightlord (Phase 2, Boss)"),
    76209000: ("哈尔莫妮亚 · 剧情/序章变体 A", "Weapon-Bequeathed Harmonia (scripted variant A)"),
    76209010: ("哈尔莫妮亚 · 剧情/序章变体 B", "Weapon-Bequeathed Harmonia (scripted variant B)"),
    76209050: ("哈尔莫妮亚 · 剧情/序章变体（强化）",
               "Weapon-Bequeathed Harmonia (scripted variant, buffed)"),
    46410010: ("哈尔莫妮亚 · 蠕虫（联机突袭）",
               "Weapon-Bequeathed Harmonia (Everdark Worm, Raid)"),
    # 七位女武神（长戟/长枪/槌）数值完全相同，已合并成一条
    76200010: ("哈尔莫妮亚 · 远征首领（七姐妹每人）", "Weapon-Bequeathed Harmonia (each of the seven)"),
    76200110: ("哈尔莫妮亚 · 联机突袭（每人）", "Weapon-Bequeathed Harmonia (Raid, each of the seven)"),
    # menuId 18 的官方名是「救世旗手」（CL_MenuText 131042），不是永夜之王
    76200310: ("救世旗手 · 一阶段（每人；Paramdex 标为推测）",
               "Weapon-Bequeathed Harmonia (Salvation's Standard-Bearers Phase 1?, each of the seven)"),
    76200210: ("救世旗手 · 二阶段（每人）",
               "Weapon-Bequeathed Harmonia (Salvation's Standard-Bearers Phase 2, each of the seven)"),
    # 慧心虫的两只虫：远征版一、二阶段数值相同，合并后不再标阶段；
    # 永夜之王版两阶段挂的常驻缩放不同（一阶段多 ×1.2），必须分开
    75200020: ("格诺斯塔 · 远征首领（一、二阶段同数值）", "Gnoster - Wisdom of Night (Boss, both phases)"),
    75300010: ("弗堤士 · 远征首领（一、二阶段同数值）", "Faurtis Stoneshield (Boss, both phases)"),
    75200120: ("格诺斯塔 · 永夜之王 · 一阶段", "Gnoster - Wisdom of Night (Everdark Sovereign Phase 1)"),
    75200030: ("格诺斯塔 · 永夜之王 · 二阶段", "Gnoster - Wisdom of Night (Everdark Sovereign Phase 2)"),
    75300120: ("弗堤士 · 永夜之王 · 一阶段", "Faurtis Stoneshield (Everdark Sovereign Phase 1)"),
    75300020: ("弗堤士 · 永夜之王 · 二阶段", "Faurtis Stoneshield (Everdark Sovereign Phase 2)"),
}

# NightBossMenuParam 行名前缀 → (variantKey, CL_MenuText 文本 ID)
# 131040 = Everdark Sovereign / 永夜之王，131042 = Salvation's Standard-Bearers / 救世旗手
MENU_VARIANTS = [
    ("[Everdark Sovereign]", "everdark", "131040"),
    ("[Salvation's Standard-Bearers]", "standardBearers", "131042"),
]

# Paramdex 基础名归一（笔误 / 同一 Boss 的两种写法）
BASE_ALIAS = {
    "Giant Crowd": "Giant Crow",
    "Astel, Naturalborn of the Void": "Naturalborn of the Void",
    "Godrick the Grafted": "Grafted Monarch",
}

# 守夜/野外 Boss：Paramdex 基础名 → NpcName 文本 ID（chr 对不上或叫法不同时）
ALIAS_NPCNAME_ID = {
    "Morgott": "902130000",                 # 恶兆妖鬼
    "Red Wolf of Radagon": "903181300",     # 王夫的红狼
    "Lord of Blood / Mohg": "904800600",    # 鲜血君王
    "Decaying Ekzykes": "904501600",        # 步入腐败仇恨龙
}

# (chrId, Paramdex 基础名) → NpcName 文本 ID。
# chr 61003「XXX (Undertaker Remembrance)」整段是黑夜入侵者的送葬者追忆版本：
# 其中 610030300 / 610030500 的 NpcParam.nameId 明确写着 140030「黑夜盗贼」/
# 140050「黑夜人偶」，其余 6 行 nameId 为 0，但 x00 序号与 chr 60003 的
# 「Night XXX (职业名)」一一对应，按同一体系补名并标 nameInferred。
ALIAS_NPCNAME_ID_BY_CHR = {
    (61003, "Wylder"): "140000",     # 黑夜刺客
    (61003, "Guardian"): "140010",   # 黑夜堕者
    (61003, "Ironeye"): "140020",    # 黑夜猎人
    (61003, "Duchess"): "140030",    # 黑夜盗贼（NpcParam.nameId 佐证）
    (61003, "Raider"): "140040",     # 黑夜掠夺者
    (61003, "Revenant"): "140050",   # 黑夜人偶（NpcParam.nameId 佐证）
    (61003, "Recluse"): "140060",    # 黑夜魔女
    (61003, "Executor"): "140070",   # 黑夜处刑人
}
# 上面靠结构推断、没有 nameId 直接佐证的组
ALIAS_INFERRED = {k for k in ALIAS_NPCNAME_ID_BY_CHR
                  if k not in {(61003, "Duchess"), (61003, "Revenant")}}

# v2 里按《艾尔登法环》官方简中手工补的译名已从 nameZh 里全部删除：逐条在全部 FMG
# （两种语言、55 个文件）里做过「完全一致字符串」检索，没有任何一条能对上，
# 属于翻译而不是游戏文本。现在 nameZh 的规则是「有游戏文本就用文本，没有就留空 + nameEn」。
# 为了页面不至于只剩英文，这些译名改挂在**另一个字段** nameZhFallback 上，
# 并由 nameZhFallbackNote 明确写清「不是游戏内文本」——页面可以拿它兜底显示，
# 但必须和 nameZh 区分开。变更明细在 notes.nameChanges。
# 唯一在 FMG 里查到的是 Stonedigger Troll（904600320「挖石山妖」），
# 它对应的是 c4603，走下面的 COMMUNITY_CHR。
REMOVED_MANUAL_ZH = {
    "Troll": "山妖",
    "Alabaster Lord": "雪花石之王",
    "Onyx Lord": "缟玛瑙之王",
    "Fingercreeper": "手指爬行者",
    "Walking Mausoleum": "行走灵庙",
    "Fire Knight": "火焰骑士",
    "Fire Knight Captain": "火焰骑士队长",
    "Fire Knight Elder": "火焰骑士长老",
    "Fire Knight Sage": "火焰骑士贤者",
    "Large Golden Hippopotamus": "大型黄金河马",
    "Dreg Wormface": "废弃物蚯蚓脸",
    "Funeral Steed": "葬送战马",
    "Frenzied Miranda": "发狂米兰达之花",
    "Cemetery Shade": "墓地幽魂",
    "Lord of Blood Spear": "鲜血君王的长枪",
}

# Paramdex 与游戏文本都没有名字的 chrId：社区资料给出的身份。
# 来源：4laric/nightreign-enemy-rando 的 data/nr_enemy_roster.json（all_variants[].variant_name）
# 与 data/nr_enemy_tags.json（name / tier / _confidence / _source）。
# 这里只用它「认身份」；中文名仍然必须从 NpcName 等 FMG 里取（见 NameBook.resolve）。
# role: "boss" = 正经首领/首领的一个阶段；"add" = 召唤物/杂兵；"unknown" = 社区也不知道。
COMMUNITY_SOURCE_URL = "https://github.com/4laric/nightreign-enemy-rando/blob/HEAD/data/nr_enemy_roster.json"
COMMUNITY_CHR = {
    4504: {
        "nameEn": "Elder Dragon Greyoll", "role": "boss", "confidence": "high",
        "note": "社区（nr_enemy_tags：_confidence=high，_source_override=er_npc_param_import）认定为"
                "《艾尔登法环》的古龙桂奥尔；参数侧佐证：hitRadius 17（全表最大之一）、"
                "superArmorDurability -1（不吃削韧，和不会被打断的巨龙一致）、behaviorVariationId 45000"
                "（与 c4500/c4505 飞龙同一套行为）。游戏文本里没有这只敌人的名字词条"
                "（只有 MagicName 7090「桂奥尔的咆哮」提到桂奥尔），所以 nameZh 留空。",
    },
    4603: {
        "nameEn": "Stonedigger Troll", "role": "boss", "confidence": "high",
        "note": "社区 roster 标为 Stonedigger Troll；参数侧佐证：behaviorVariationId 46000"
                "（与 c4600 山妖同一套行为）、hitHeight 7.2 / hitRadius 1.8 与山妖体型一致。"
                "游戏文本 NpcName 904600320「Stonedigger Troll / 挖石山妖」正好对上。",
    },
    7711: {
        "nameEn": "Centipede Grub", "role": "add", "confidence": "medium",
        "note": "紧邻 c7710「百足恶魔」，getSoul = 0、chaosMatchingRewardLotId = -1（不掉任何奖励），"
                "weight 30000（不可推动）；社区 roster 标为 Centipede Grub、tier=grunt。"
                "判断为百足恶魔战里的幼虫召唤物，不应作为首领展示（hidden=true）。",
    },
    7712: {
        "nameEn": "Centipede Grub", "role": "add", "confidence": "medium",
        "note": "与 c7711 同一套（体型略小）：不掉奖励、社区 tier=grunt，"
                "判断为百足恶魔的幼虫召唤物，不应作为首领展示（hidden=true）。",
    },
    7910: {
        "nameEn": "Storm King", "role": "boss", "confidence": "low",
        "note": "紧邻 c7900「无名王者」，社区 roster 标为 Storm King（《黑暗之魂3》无名王者的"
                "坐骑巨龙 King of the Storm）。参数侧：getSoul = 0、无独立掉落，符合「同一场战斗的"
                "第一阶段，奖励挂在无名王者身上」。游戏文本里没有对应名字词条，nameZh 留空。",
    },
    7931: {
        "nameEn": "", "role": "unknown", "confidence": "none",
        "note": "无法确认。紧邻 c7930「恶魔王子」且 hp 2880 与恶魔王子（守夜档）完全相同，"
                "但 superArmorDurability = 0、partsDamageType = 0、hitRadius 1.1、"
                "getSoul = 0 且没有任何掉落，behaviorVariationId 自成一套（79310）。"
                "疑似恶魔王子战里的火焰/投射物实体，不应作为首领展示（hidden=true）。"
                "社区 roster 对这两组也只写了 chrId，没有名字。",
    },
    7932: {
        "nameEn": "", "role": "unknown", "confidence": "none",
        "note": "无法确认。4 行完全相同（79320000–79320003），hitRadius 0.7、无削韧、无掉落，"
                "hp 沿用恶魔王子的 2880。疑似恶魔王子战里成组生成的火焰实体，"
                "不应作为首领展示（hidden=true）。",
    },
}

# 中文里的「群/们/队」后缀：同一条英文名有单数和群体两种中文词条时优先取非群体的那条
PLURAL_ZH_SUFFIX = ("群", "们", "队")

# 深夜深度（The Deep of Night）：ChaosMatchingCorrectParam.spEffect00..04 = 深度 1..5
DEPTHS = (1, 2, 3, 4, 5)

FIELD_THREAT = range(7740, 7750)
NIGHT_THREAT = range(7750, 7760)

def build_caveats(m: dict) -> list[str]:
    """页面底部原样展示的中文说明。

    带数字的几条**不写死**：m 里是生成时从产物本身实测出来的统计（各夜王的深度出现权重、
    deepOfNightTiers 的档位/数值表个数、nameZh 为空 / nameZhFallback 的条数等），
    caveats 用 f-string 把实测值拼进去，避免数据变了而文字没跟着变。
    """
    return [
    "hp 是 1 人时玩家真正要打掉的血量 = hpBase（NpcParam.hp 原始字段）× hpMultiplier。"
    "hpMultiplier 是该行 spEffectID0..31 上所有无条件常驻 SpEffect 的 maxHpRate 连乘，"
    "也就是「Enemy Scaling: Field/Night/Final Boss Threat」这类威胁档位缩放（如最终 Boss ×3.54），"
    "永夜之王专属加成（[Everdark Sovereign Scaling] ×1.2～1.55）与 DLC 加成（[DLC Scaling] ×1.25）。"
    "只看 NpcParam.hp 会把血量低估 1.58～5.5 倍（个别剧情/强化行更高）。",
    "damageRates 是「承伤倍率」而不是减伤率：1.35 = 多受 35% 伤害，0.5 = 只受一半，1 = 正常。"
    "holy 取自参数里的 darkDamageCutRate（本作把圣属性放在 dark 槽）；NpcParam 的 def_* 字段全为 100，不参与计算。",
    "poise 是削韧槽容量（superArmorDurability），poiseRecover 是每秒恢复系数（saRecoveryRate）；"
    "-1 表示该行不吃削韧（一般是子弹/投射物实体）。"
    "poiseTakenBase 是常驻 SpEffect 带来的「承受削韧倍率」（DLC 最终 Boss 为 0.88），"
    "poiseRecoverMultiplier 是常驻的削韧恢复速度倍率（最终 Boss 档位 0.2，恢复更慢）。",
    "人数缩放来自参数表：multiPlayCorrectionParamId → MultiPlayCorrectionParam →"
    "（client1SpEffectId = 双人 / client2SpEffectId = 三人）→ SpEffectParam。",
    "scaling.poiseTaken 是「承受削韧倍率」：双人 0.55 表示同样的削韧只吃到 55%，"
    "等价于有效韧性约为单人的 1/0.55 ≈ 1.8 倍；三人 0.3 约为 3.3 倍。"
    "页面展示「有效韧性」请用 poise / (poiseTakenBase × scaling.poiseTaken)。",
    "多人并不会让 Boss 更容易中异常。resist 是异常累积阈值（越大越难触发，999 = 免疫），"
    "人数缩放的 change*ResistPoint 全为 0，阈值不变；变化的是两个倍率："
    "scaling.buildupRate（Boss 承受的累积量，双人 0.85 / 三人 0.7）与 "
    "scaling.ailmentDamageRate（异常发动时的伤害，双人 0.75 / 三人 0.5）。两者都是往下走，"
    "也就是人越多，出血/冻伤/睡眠/发狂越难打出来、打出来也越弱。",
    "ailmentDamageRateBase 是常驻档位自带的异常伤害倍率（守夜/最终 Boss 为 0.5），"
    "poisonRate 对应中毒/腐败，当前各档位都是 1。",
    "weakness 是 NightBossMenuParam 里的官方弱点标注（菜单上那几个图标），"
    "不一定等于 damageRates 里实际最吃的属性，页面建议两者并列展示。",
    "同一夜王/同一 Boss 下，数值、常驻缩放与人数档位完全一致的多行才会合并成一条，"
    "npcIds 保留全部原始行号，npcId 是代表行，paramdexName 是代表行的原始 Paramdex 行名；"
    "labelEn 是变体说明，可能由多行合成、或在 Paramdex 原名之外加了阶段说明。"
    "labelUncertain = true 表示 Paramdex 原名带「?」，阶段/用途属于社区推测。",
    "夜王菜单有两种特殊变体：[Everdark Sovereign] = 永夜之王（游戏内简中，CL_MenuText 131040），"
    "[Salvation's Standard-Bearers] = 救世旗手（131042，只有哈尔莫妮亚有）。"
    "everdark 只对前者为 true，variantKey / variantNameZh 可区分三种形态。",
    "deepOfNight 是「深夜」模式下的数值：那些带 invocationConditionsStateChange1 = 2287 的常驻 "
    "SpEffect 只在深夜生效，会抵消掉永夜之王/DLC 的血量加成（乘完约为本体的 1.05 倍 / 1.0 倍）。"
    "为 null 表示该行没有深夜专属缩放，数值与 hp 相同。",
    "弗堤士（Faurtis Stoneshield）与亚尼姆斯（Animus）归入「慧心虫 / 格诺斯塔」远征："
    "它们没有独立的夜王菜单行、没有独立 BGM 行，chrId 也紧邻格诺斯塔；亚尼姆斯只在永夜之王版本登场。",
    "NightBossMenuParam 的 ID 100「深夜」没有 bossNameId（不是一个夜王，是深度模式入口），已跳过。",
    "守夜/野外 Boss 的中文名按 NpcParam.nameId → chrId 对照 NpcName 文本取得；"
    "个别条目游戏文本里没有对应词条，nameSource 会标成 chrid-fallback"
    "（连 Paramdex 英文名都没有，英文名是用 chrId 拼的「Unknown Enemy (cXXXX)」）"
    "或 english-only（只有英文名）；两种情况下 nameZh 都是空串。"
    "nameInferred = true 表示名字是按 ID 结构推断的。"
    "**schemaVersion 3 的产物里不存在 nameSource = manual 的条目**"
    "（v2 那种按《艾尔登法环》官方简中手工补的译名已全部移出 nameZh，"
    f"本次产物 manual 条数 = {m['manualCount']}）；"
    "两端只是为了读旧数据才保留这个取值的分支，写新代码不用考虑它。详见下面【名字】几条。",
    "nightBosses 的主键是 id（形如 \"Flying Dragon@4500\"），nameEn 会重复"
    "（chr 4500「丘陵飞龙」与 chr 4505「飞龙」的 Paramdex 基础名都是 Flying Dragon），不要拿它当 key。",

    # ---------------- schemaVersion 3 新增 ----------------
    "【名字】schemaVersion 3 起，简中名只来自游戏自带文本（item/NpcName、menu/CL_MenuText 等 FMG），"
    "不再有按《艾尔登法环》官方简中手工补的译名，也不再有生成器拼出来的占位名。"
    f"v2 里的 {m['manualPresent']} 条 manual 译名逐条在全部 FMG 里检索过「完全一致的字符串」，"
    "一条都没有，已全部移出 nameZh"
    f"（生成器的删除清单 REMOVED_MANUAL_ZH 共 {m['removedManualTotal']} 条，"
    f"多出的 {m['removedManualTotal'] - m['manualPresent']} 条在 v2 / v3 里都不单独成组，不产生条目）；"
    f"找不到文本的组 nameZh 留空、只给 nameEn —— 本产物共 {m['zhEmpty']} 组 nameZh 为空"
    f"（{m['englishOnly']} 组 english-only、{m['community']} 组 community/community-npcname、"
    f"{m['chridFallback']} 组 chrid-fallback）。"
    "变更明细在 notes.nameChanges。nameSource 合法取值：npcparam-nameid、npcname、"
    "npcname-global、npcname-relaxed、npcname-chr-only、npcname-alias、npcname-alias-chr、"
    "community-npcname、community、english-only、chrid-fallback"
    "（manual 已不再产出，保留取值只为兼容旧数据；npcname-relaxed / npcname-chr-only "
    "目前数据里也没有条目——解析出来的那 4 条都因为下面的「同名去重」退回了 english-only，"
    "页面对未知取值按 english-only 优雅降级即可）。",
    "【名字】nameZhFallback 收下被移出 nameZh 的手工译名（《艾尔登法环》官方简中），"
    "**不是本作的游戏内文本**，nameZhFallbackNote 里写清了这一点。"
    "只要这一组现在的 nameZh 不等于旧译名就会写。"
    f"本产物里 nameZhFallback 非空的共 {m['fallbackCount']} 组，全部落在 nameZh 为空的组上；"
    f"反过来 nameZh 为空的 {m['zhEmpty']} 组里只有 {m['fallbackCount']} 组拿得到旧译名，"
    f"剩下 {m['zhEmptyNoFallback']} 组（{m['zhEmptyNoFallbackNames']}）连旧译名都没有 —— "
    f"其中 {m['displayFallbackCount']} 组有下一条说的 displayFallbackZh 占位名，"
    f"另 {m['zhEmptyNoFallback'] - m['displayFallbackCount']} 组只能显示英文名。"
    "页面在 nameZh 为空时可以用它兜底显示，但要和游戏文本名区分开（例如加「非官方译名」标记）；"
    "判断「这个名字是不是游戏里的」请只看 nameZh 与 nameSource。",
    "【名字】displayFallbackZh 是**另一个**兜底字段，和 nameZhFallback 不是一回事："
    "nameZhFallback 是《艾尔登法环》的官方简中旧译名（至少是个真译名），"
    "displayFallbackZh 只是生成器用 chrId 拼出来的占位串「未知敌人 cXXXX」，"
    "既不是游戏文本也不是译名，纯粹为了页面不至于只能显示 \"Unknown Enemy (c7931)\"。"
    f"本产物里只有 {m['displayFallbackCount']} 组有它（{m['displayFallbackNames']}）——"
    "连游戏文本带社区资料都认不出是谁的那几组。"
    "v3 首版把这个串写在 nameZh 里，与「简中名只来自游戏文本」自相矛盾，现已挪出来。"
    "页面取显示名的推荐顺序：nameZh（游戏文本，可信）→ nameZhFallback（标「非官方译名」）"
    "→ displayFallbackZh（标「无游戏内名称」）→ nameEn。",
    "【名字】nameEvidence 给出这个简中名的出处（fmg 文件名 + 文本 ID + 该条的英文/简中原文），"
    "nameApprox = true 表示不是逐字命中：可能是借了中心词（Large Wormface → "
    "NpcName 904580600「Wormface / 蚯蚓脸」），或英文是单复数差异。"
    "页面展示 nameApprox 的条目时建议加个「近似」标记，并可用 nameNote 解释。",
    "【名字】同一个 nameZh 不会同时挂在两组首领上——nameZh 是两端卡片的主显示名，"
    "两张卡顶同一个中文名等于没有名字。放宽匹配（中心词 / chrId 独苗群体名）一度产生 3 对重名，"
    "现在按证据强度裁决：逐字命中 > 近似但词条属于本组自己的 chrId > 借别的 chrId 的词条；"
    "唯一的最强者留下 nameZh，其余退回 english-only（两端既有的「仅英文名」徽标会自动挂上），"
    "被挡下的候选词条完整记在 nameZhRejected（fmg / id / en / zh / reason）里，证据不丢。"
    "结果：黄金河马归 Golden Hippopotamus@5011（Large Golden Hippopotamus@5010 让出）、"
    "蚯蚓脸归 Large Wormface@4580（Dreg Wormface@7660 让出）；"
    "石肤众王（903600530「Stoneskin Lords」）对 Alabaster Lord 与 Onyx Lord 是同一个群体名、"
    "证据强度相同，两组都让出——它本来就盖不住这两个各自独立的首领。"
    "明细在 notes.nameCollisions。",
    "【名字】nameSource = community / community-npcname 的条目，身份判断来自社区资料"
    "（4laric/nightreign-enemy-rando 的 data/nr_enemy_roster.json 与 nr_enemy_tags.json，"
    "URL 在 nameSourceUrl），中文仍然只从游戏文本取；社区也认不出来的两组"
    "（c7931 / c7932）nameSource 仍是 chrid-fallback、nameZh 为空，"
    "占位显示名「未知敌人 cXXXX」在 displayFallbackZh 里，判断写在 nameNote 里。",
    "【名字】hidden = true 表示这一组明显不是「首领」，页面默认可以不展示。判据是结构性的："
    "整组不掉任何奖励（getSoul / chaosMatchingRewardLotId / itemLotId_enemy 全是 0 或 -1），"
    "并且要么不吃削韧（superArmorDurability ≤ 0，典型的投射物/部件实体），"
    "要么连游戏文本带社区资料都认不出是谁，要么社区把它标成杂兵。"
    "noReward 单独给出「不掉奖励」这一项，方便页面自己定策略。",

    "【深夜】深夜（The Deep of Night）的「深度」1–5 走 NpcParam.chaosMatchingCorrectParamId → "
    "ChaosMatchingCorrectParam.spEffect00..04，顶层 deepOfNightTiers 是按档位归并的完整倍率表，"
    "每个 fight/variant 的 depthStats[\"1\"..\"5\"] 是该行在各深度的实际数值"
    "（hp / hpMultiplier / attackRateBase / attackRatesBase / poiseTakenBase / staminaAttackRateBase）。"
    "depthStats 已经把常驻档位与深夜修正一起乘进去了，可以直接展示；"
    "原有的 deepOfNight 字段语义不变（= 深夜基准，相当于深度倍率取 1），只是新增了攻击力/耐力两项。",
    "【深夜】深度对攻击力的加成远大于对血量的加成。实战夜王：27 条 isMain 战斗行里有 26 条走 "
    "chaosCorrectId = 7767，深度档位是 **Tier 4a** —— 深度 1→5 血量 "
    "×1.25 / 1.4 / 1.57 / 1.95 / 2.16，攻击力 ×1.25 / 1.55 / 1.92 / 2.83 / 3.31"
    "（深度 5 的伤害是深度 1 的 2.65 倍），承受削韧 0.88 → 0.84，对玩家耐力削减 1.15 → 1.5。"
    "注意 ChaosMatchingCorrectParam 的 7760–7769 行名虽然都是「Final Boss Threat」，"
    "深度档位却不是同一个：7765 = Tier 2c、7766 = Tier 3e、7767 = Tier 4a，"
    "其余（7760–7764 / 7768 / 7769）才是 Tier 3f（×1.3 → ×1.718 血 / ×1.3 → ×2.947 攻击），"
    "本数据集里 Tier 3f 只出现在夜王的非主战行（召唤物/阶段实体）与救世旗手哈尔莫妮亚的永夜虫上。"
    "请一律按每行自己的 chaosCorrectId 去查 deepOfNightTiers，别按行名段猜。"
    "页面只展示血量会严重低估深夜的难度。",
    "【深夜】「红化」在游戏内简中的正式叫法是**变异个体**（CL_MenuText 138296 / 338806）。"
    "顶层 mutations 按 SpEffectSetParam 行号列出每一档变异会给敌人加什么"
    "（vfxTier = 红光档位，hp / attackRate / runeRate = 血量/伤害/卢恩倍率），"
    "每个 fight/variant 的 mutationSetId（与 mutationPool）指向它；mutationSetId 为 null "
    "表示这一行不会被变异。变异倍率与深度、常驻、人数三层都是相乘关系（spCategory 各不相同）。",
    "【深夜·不确定】变异档位的两行（VFX 4480–4483 与数值 7200–7241）spCategory 都是 203、"
    "categoryPriority 都是 10。同一分类通常意味着互相覆盖，但它们是通过同一个 SpEffectSetParam "
    "一起挂上去的、且改的字段完全不重叠（VFX 行只有 vfxId，数值行只有倍率），"
    "Paramdex 也没有对 203 的说明，所以这里按「两条都生效」处理。"
    "如果实际是只生效一条，受影响的只是 mutations 里 vfxTier 与倍率的搭配，倍率本身不变。",
    "【深夜·不确定】ChaosMatchingCorrectParam 与 MultiPlayCorrectionParam 用的是同一套行号"
    "（7700–7780、98810…），但 NpcParam 里有 18 组行的 chaosMatchingCorrectParamId 与 "
    "multiPlayCorrectionParamId 不同（例如 mpc 7730 / chaos 7753 共 60 行），"
    "所以两者必须分别查表，不能互相代用；本数据集的 scalingId 与 chaosCorrectId 因此可能不相等。",
    "【深夜】变异的**数量**由 ChaosMatchingMutationCategoryParam 决定（顶层 mutationCategories）："
    "它给的是「该深度这一类敌人会有几只被变异」的个数，不是每只敌人被变异的百分比概率。"
    "场景头目（类别 120）与封印监牢首领（类别 160）在深度 1 都是 0，"
    "也就是深度 1 不会遇到变异的场景头目；深度 4 起据点首领（类别 110）的变异数量再上一档。",
    "【深夜】夜王在各深度的出现权重在 nightlords[].depthChanceWeights（NightBossMenuParam "
    f"depth1..5ChanceWeight）。**权重不是每个夜王都一样的**，{m['weightRows']} 条里有 "
    f"{m['weightShapes']} 种不同的数列，请直接读每条自己的 depthChanceWeights，不要按下面的举例套用。"
    "实测（本次生成时从产物里逐条拼出）：\n" + m["weightLines"] +
    "\n规律：本体形态走「深度越深权重越低」的形状（相对值 1000/800/650/500/500），"
    "永夜之王与救世旗手走「深度 1 为 0、之后递增」的形状（0/200/350/500/500），"
    "但整条数列会按夜王各自的基数缩放——玛利斯是上述形状的一半，哈尔莫妮亚是 1.6 倍，"
    "DLC 的史柴格斯与布德奇冥则是**五个深度同一个值**（不随深度变化）。"
    "唯一对所有夜王都成立的结论是：**深度 1 打不到永夜之王/救世旗手**（depth1 权重恒为 0）。"
    "守夜/野外 Boss **没有**对应的按深度出现权重表，"
    "参数里只有上面那张变异数量表，所以本数据集不提供它们的深度出现概率。",
    "【深夜】ChaosMatchingMutationEnemyTableParam（3067 行）是按地图刷新点组织的"
    "（categoryId + smallBaseId → SmallBaseMapVariationParam），没法直接对到某一行 NpcParam，"
    "因此没有收录；ChaosMatchingReplaceTreasure* 两张表 Paramdex 的字段全是 unk_*，也没有收录。",

    "【多人】多人**不是**简单乘倍数。scalingTiers.*.fullEffects 里是 client1（双人）/ "
    "client2（三人）指向的 SpEffect 行的全部非默认字段，完整结论见 notes.multiplayerScalingAudit。"
    "要点：血量倍率按档位从 ×1（突袭档）到 ×2/×3（最终 Boss）不等；"
    "7744 / 7753 / 7754 / 7758 四个档位多人时敌人**攻击力**还会 ×1.1（双人）/ ×1.2（三人）"
    "（新增字段 scaling.duo.attackRate / scaling.trio.attackRate）；"
    "防御减伤、卢恩掉落、异常阈值完全不变。",
    "【多人】与社区实测核对（Fextralife，2026-09）：格拉狄乌斯 11,328 / 22,656 / 33,984、"
    "永夜之王格拉狄乌斯 17,558 / 35,116 / 52,674、艾德雷 13,140 / 26,280 / 39,420 完全一致；"
    "卡莉果 Fextralife 记 12,007 / 24,014 / 36,021 而本数据集是 12,008 / 24,016 / 36,024，"
    "差别只在 3392 × 3.54 = 12007.68 的取整（本数据集四舍五入，Fextralife 截断），不是算法分歧。"
    "个别条目与第三方 wiki 差 1–3 点血都属于这一类，不必当成错误。"
    "本数据集的取整规则见下面【取整】那条（ROUND_HALF_UP，且先把倍率量化到 6 位小数）。",
    "【多人】MultiPlayCorrectionParam 的 client3SpEffectId（4 人）整表都是 -1，"
    "对应游戏最多 3 人，fullEffects.quad 恒为 null。",
    "【常驻缩放】schemaVersion 3 起，常驻 SpEffect 的判定多看了攻击力（五种 *AttackPowerRate）"
    "与 staminaAttackRate 两项，因此 permScalingIds / deepOfNight.permScalingIds 会多出"
    "一些「只改攻击力、不改血量」的行（如 7799「Enemy Scaling: Noklateo Lesser Threat」×1.2 攻击、"
    "7783「Mountaintop Giant Crow」×2.45 攻击、62750 ×1.15 耐力削减），共影响 27 处。"
    "hp / hpMultiplier / poise / damageRates / resist / scaling 等所有原有数值**没有任何改动**，"
    "新增的合并倍率在 attackRateBase / attackRatesBase / staminaAttackRateBase 里。",
    "【合并】schemaVersion 3 起，merge_key 额外比较 chaosCorrectId（深度档位）与 "
    "mutationSetId（变异档位），所以 v2 里因为「玩家侧数值相同」而被合并、但深度/变异档位不同的行"
    "现在会拆开（例如黑刀刺客 2 → 3 个变体）。npcIds 仍然保留全部原始行号，hp 等数值没有任何改动。"
    "拆开后同一张卡里会出现血量相同、只差深度/变异档位的两行，"
    "个别组（血斑巨乌鸦 c4561、冰霜螯虾 c4420）里没有 Paramdex 行名的那一行 npcId 更小，"
    "按「血量最高、同血量取 npcId 较小」的代表行规则会顶上卡头、labelZh 显示成「基准」；"
    "两行的数值完全一致，差别只在「能不能被变异」（mutationSetId）。",
    "【合并】Paramdex 行名以「- Template」结尾的模板行不收录（与 …9999 调试行同一口径），"
    "明细在 notes.skippedRows。这 10 行是黑夜人偶十个角色的模板"
    "（600030000/600030100/…/600030900）：数值与同组真实行完全相同，但 getSoul = 0、"
    "rewardItemLot 全是 -1，chaosMatchingCorrectParamId 也不一样（模板 7740 / 真实 7780）。"
    "v3 的 merge_key 加入 chaosCorrectId 后它们会被拆成独立变体，而且 npcId 更小会抢走"
    "两端的代表行位置，让卡头显示「模板行」、深度 5 血量高 7.4% / 攻击力高 33%。"
    "另外每个 fight/variant 新增了 noReward 布尔（整行不掉卢恩/不掉任何奖励表），"
    "两端排代表行时可以让它排在同血量的实战行之后。",
    "【变异】mutationCategories 的 categoryZh，以及 mutations 里的「变异个体」，"
    "是按 Paramdex 的 MUTATION_CATEGORY 枚举与 CL_MenuText 的语义"
    "**译出来的标签**，游戏文本里大多没有这些词条单独存在"
    "（「变异个体」只作为 138296「打败敌人的次数（变异个体）」与 338806「已打倒变异个体」的子串出现，"
    "「据点首领」等类别名在 zhocn FMG 里检索不到）；例外是 120 Field Boss：TutorialBody 403200 的地图图标说明"
    "把 Field Boss 叫「场景头目」（engus 同一处写 Field Boss），schemaVersion 4 起 categoryZh 120 改用它"
    "（v3 是「野外首领」），150 / 151 的「坑道」也取自同一段的「坑道入口」。"
    "mapZh 自 schemaVersion 4 起改取游戏文本（地图修饰 10–15 = 地形变体 0–5：宁姆韦德取 "
    "PersonalScenarioObjective 1020 的子串，其余取 TutorialTitle 403400–403440「特异地形：…」去掉前缀）："
    f"{m['mapZhAll']}。schemaVersion 4 对旧字段的值改动只有这一类「标签改取游戏文本」：mapZh {m['mapZhChanges']}；"
    "categoryZh 120「野外首领」→「场景头目」；变体 labelZh 里 Paramdex 括注 (Crater) / (Noklateo) / (Field Boss) 的译法"
    f"{m['labelZhChanges']}；连同本条、【深夜】变异数量那条与 notes.deepOfNightAudit 里引用这些名字的句子。"
    "键与结构不变。"
    "上面【名字】那条「简中名只来自游戏文本」只约束 nightBosses.nameZh 与 nightlords 的名字，"
    "不包括 categoryZh / labelZh 这类分类标签；categoryEn / mapEn 与枚举逐字一致，数值与 CSV 逐字段一致。",
    "【体积】schemaVersion 3 的文件约 1.1 MB（v2 约 0.4 MB），涨的主要是 depthStats："
    "每个 fight/variant 都把 5 个深度的 hp / hpMultiplier / poiseTakenBase / "
    "attackRateBase / attackRatesBase / staminaAttackRateBase / depthSpEffectId 展开了一遍，"
    "与 scaling 在每条记录里重复展开是同类取舍（换页面零查表）。"
    "嫌大可以只用 depthStats[N].hp，其余倍率按 chaosCorrectId 去 deepOfNightTiers 查"
    f"（整表只有 {m['depthIds']} 个 chaosCorrectId），两者数值一致。",

    # ---------------- 第二版复核补充 ----------------
    f"【深夜】deepOfNightTiers 的键是 **chaosCorrectId**（ChaosMatchingCorrectParam 行号），"
    f"不是「档位」——本产物有 {m['depthIds']} 个键，但它们只对应 {m['depthLabels']} 种档位名"
    f"（tierLabel），再往下只对应 {m['depthTables']} 张互不相同的数值表。"
    f"tier 是 Paramdex 在 SpEffect 行名里写的正式 Tier 段（{m['depthNamedLabels']}），"
    f"有 {m['depthUnnamedCount']} 个键的行名里压根没有 Tier 段（{m['depthUnnamedLabels']}，"
    "联机突袭行），它们的 tier 是 **null**。"
    "为了页面不用处理 null，新增了 **tierLabel（恒非空）**：有 Tier 段就是 Tier 名，"
    "没有就退到 ChaosMatchingCorrectParam 的行名；tierSource 说明这个标题是哪来的"
    "（tierName / rowName / chaosCorrectId）。"
    "另外注意「档位名不同」不等于「数值不同」：Tier 3b / 3d / 3f 的五个深度倍率完全一致，"
    "Tier 5a / 5b / 5c 与 Night Invader 也完全一致（差别在别的、本数据集没有收录的字段上）。"
    "要判断两行深夜表现是否相同，请比 depths 里的数值，别比 tier 名。",

    "【取整】所有整数血量（hp、deepOfNight.hp、depthStats[N].hp）都是 "
    "**hpBase × 同一条记录里公布的那个 hpMultiplier，再四舍五入（ROUND_HALF_UP）**。"
    "两点约定请照抄，否则会差 1 点：①倍率先量化到 6 位小数再乘（JSON 里写的就是 6 位），"
    "不要拿「常驻倍率 × 深度倍率」的未量化乘积去算；②恰好落在 .5 时**进位**，"
    "不是 Python / IEEE 默认的「银行家舍入」（.5 进偶数）。"
    "v3 首版直接用浮点 round()，三条恰好落在 .5 的行取整方向不一致"
    "（Great Wyrm 49110010 深度 1 的 2950 × 3.51、Gaping Dragon 77000000 的 2950 × 1.83、"
    "Godskin Noble 35700000 的 2055 × 2.7），本版统一成 ROUND_HALF_UP，"
    "后两条各 +1（5398 → 5399、5548 → 5549），全表其余数值零变化。"
    "与第三方 wiki 差 1–3 点血仍然只是取整口径差异（对方截断），不是缩放逻辑分歧。",

    "【多人】" + SCALING_FIELD_UNIT_NOTE +
    " fieldUnits 只列出该档位真正出现过的列；生成时会断言 fields 里的每一列都在量纲表里，"
    "出现新列会直接报错而不是静默漏说明。"
    "顶层 scaling.duo / scaling.trio 里的字段则**已经全部折算成倍率**，可以直接连乘，"
    "不需要再查 fieldUnits。",

    # ---------------- schemaVersion 4：出场场合 ----------------
    "【场合】tier / tiers 是 v3 按 multiPlayCorrectionParamId 的档位名（Field Boss Threat 7740–7749 / "
    "Night Boss Threat 7750–7759）分出来的，**那是缩放档位，不是出场场合**："
    "铃珠猎人的野外版 31000010、大树守卫的野外版 32510020 挂的都是 7753「Night Boss Threat」，"
    "熔炉骑士的守夜版 25000020 挂的是 7746「Field Boss Threat」。"
    "schemaVersion 4 新增 roles：按地图 MSB 的敌人放置 + 决定地图块何时进入远征的参数表重新判定，"
    f"本产物 nightBosses 各场合的组数：{m['roleGroupLine']}（一组可以同时属于多个场合）。"
    f"tier=night 的 {m['roleTierNightGroups']} 组里有 {m['roleTierNightNoNight']} 组根本不会当守夜首领，"
    f"tier=field 却确实会当守夜首领的有 {m['roleTierFieldNight']} 组，明细在 notes.roleAudit。"
    "tier / tiers 按约定保留原值只为兼容旧页面，**按场合分组请改读 roles**。",

    "【场合】roles 的取值与判定口径见顶层 roleNames（数组按 roleNames 的键序排列）。"
    "每个 fight / variant 的 roleEvidence[场合] 是逐条证据：npcId（哪一行原始 NpcParam）、"
    "msb（放在哪张地图，入侵者/未放置为 null）、part（MSB 里的 part 名与 entityId）、"
    "table + row（决定这个场合的参数表与行，如 LotResultPlayAreaParam「bossId1 = 4924」）、note（说明）；"
    "同一张地图的全部出处在顶层 placementMaps[地图].evidence。"
    "变体是按数值合并的，合并进同一变体的原始行场合可能不同"
    f"（本产物有 {m['roleMixedVariants']} 个这样的变体），逐行场合看 rowRoles（键是 npcId 字符串）。"
    "分组（nightBosses[] / nightlords[]）的 roles 是其变体/战斗行的并集，"
    "roleVariants[场合] 列出带这个场合的变体代表行 npcId，证据去对应变体的 roleEvidence 里看。",

    f"【场合】数据来源：extract_msb.py 从归档解出的 {m['roleMsbMaps']} 张地图 MSB，"
    f"共 {m['roleMsbEnemy']} 个 Enemy part；另有 {m['roleMsbDummy']} 个 DummyEnemy part 不参与战斗"
    "（场景头目地图块里放着别的首领的 Dummy 之类），**不计入场合**。"
    f"没有任何 Enemy part、也不在 SmallbaseInvationNpcParam 里的行标为 unplaced"
    f"（本产物 {m['roleRowsUnplaced']} 个原始行 / {m['roleVariantsUnplaced']} 个整条变体），"
    f"其中 {m['roleUnplacedBaseTier']} 行挂的是 7740 / 7750 这两个基础档（labelEn 多为「Base」，即 Paramdex "
    f"行名不带括注），其余 {m['roleRowsUnplaced'] - m['roleUnplacedBaseTier']} 行是其它档位里没放进地图的行"
    "（含只有 DummyEnemy 的行与只在未启用地图块里的行），"
    "页面可以把 roles = [\"unplaced\"] 的变体淡化或折叠。"
    "地图块在 LotResultPlayAreaParam / LotResultSmallBaseAndSpot / defaultSmallBase / "
    "SmallBaseEnemyLotMapCombinationParam 里都没被引用的（如 m48_70「Night Boss - Godskin Apostle」），"
    "placementMaps 里 kind = inactivePiece、roles 为空，放在里面的行不因此获得场合。"
    "地图号落在地图块区段（与 SmallBaseMapVariationParam 的行同一个 AA 段）、却连该表的行都没有、"
    f"也没有任何抽选表引用的地图（{m['roleUnlistedPieces']}，放着首领档的行 {m['roleUnlistedPieceRows']}）"
    "同样按 inactivePiece 处理；不在地图块区段的无引用地图（圆桌厅堂 m10_00、追忆 m13_00、教程 m35_90 等）才标 other。",

    "【场合】标签出处：「封印监牢」「突袭事件」「黑夜入侵者」「场景头目」与夜晚槽位的「初始日：夜晚 / 中间日：夜晚」"
    "（CL_MenuText 338310 / 138275、AttachEffectName 7060200、TutorialBody 403200、CL_MenuText 146501 / 146503）"
    "以及开放地块的地形名（TutorialTitle 403400–403440「特异地形：…」，宁姆韦德取 "
    "PersonalScenarioObjective 1020 的子串）是游戏文本；「坑道精英」的「坑道」取自 TutorialBody 403200 的「坑道入口」"
    "（engus Tunnel Entrance），「精英」随 Paramdex 枚举名 Mine Elite；「守夜首领」「守夜前哨」「据点首领」"
    "「大空洞高塔首领」「地图事件」「夜王战」「随从/召唤物」「其他地图」「未放置」是说明性标签。"
    "field 在 schemaVersion 4 首版叫说明性的「野外首领」，现改用游戏文本「场景头目」：TutorialBody 403200"
    "「地图：可攻略地点（二）」逐个说明地图图标——坑道入口 / 要塞 / 场景头目（四处徘徊的强大敌人）/ 封印监牢，"
    "engus 同一处是 Tunnel Entrance / Castle / Field Boss / Evergaol（403140 的地图图标表里也有「场景头目」）；"
    "同一个词也用到了 categoryZh 120 与变体 labelZh 的 (Field Boss)（见【变异】）。"
    "其中 tower 只凭挂点的 Paramdex 行名（[Great Hollow] East/West Tower Boss - Floor 1–3）命名，"
    "游戏文本里没有「高塔」这个词条；地图块的 paramdexName 也是 Paramdex 社区行名，只作说明。"
    "（mutationCategories 的 mapZh 与变体 labelZh 里的地形名已改成同一组游戏文本名，见【变异】。）",

    f"【场合】几条特殊口径：① 夜王（nightlords[].fights）的场合只有 nightlord（夜王战场 {m['roleArenaMaps']}）、"
    "raid（突袭地图块，或带 Raid 修饰的据点地图块——本产物有 "
    f"{m['roleLordRaidStrongholdMaps']} 张据点地图块放着夜王突袭行 {m['roleLordRaidStrongholdRows']}，"
    f"其中 {m['roleLordRaidInferred']}自己的抽选结果里没有这个 Raid 修饰、同一建筑的另一元素变体才有，"
    "按同一突袭计是推断，要看 EMEVD 才能定）、"
    f"event（夜王本体行在夜王战场与突袭以外现身：{m['roleLordEventRows']}，所在地图 {m['roleLordEventMaps']}）"
    "与 unplaced；"
    "② summon 在首领战地图块（夜晚首领 / 高塔 / 夜王战场 / 场景头目地图块）里判定，"
    "条件二选一：自身零奖励且同图另有掉奖励首领（百足恶魔的幼虫、鲜血君王的长枪、无名王者的坐骑风暴之王等）；"
    f"或不带任何首领奖励表、卢恩不超过同图首领行的 {m['roleSummonRatio']}"
    f"（坐骑与辅助实体：{m['roleSummonRatioRows']}）。开放地图地块上一张图里首领太多、比卢恩没有意义，只认一种："
    "自身零奖励、全部 MSB part 都换成别的模型且 npcThinkParamId 是 0 / 1 通用占位 AI 的辅助实体"
    f"（{m['roleOpenMapHelperRows']}）。判为 summon 后不再同时标 night / field；"
    "同图的真双首领（夜骑兵连枷版 31501020 卢恩与骑手相同、黄金河马 50110020 是熔炉骑士的 2/3）不受影响；"
    "③ 同一张夜晚首领地图块可能又被挂到大空洞高塔，于是同一行同时是 night 与 tower（铃珠猎人 31000020 等）；"
    "④ 开放地图地块 m60_* 按该地块该地形变体的变异类别判定（场景头目 / 坑道精英 / 据点首领，见最后一条【场合】），"
    "地形变体写在 placementMaps[地图].tileVariant；开放地块上自身零奖励、MSB part 与带对话脚本（talkId）的实体"
    f"同属一个实体组的剧情敌人（{m['roleScriptedRows']}）标 event；"
    f"⑤ 夜晚首领地图块里挂 {PRELUDE_SCALING_ID} 档的行（{m['rolePreludeRows']}）是首领本体登场前的前哨，"
    "标 prelude 而不是 night；地图块同时挂到大空洞高塔时前哨也不标 tower"
    f"（{m['rolePreludeTowerRows']}，高塔挂法写在 prelude 证据的 note 里），"
    f"所以 tower 只统计真正的高塔首领（本产物 {m['roleTowerGroups']} 组）；"
    f"⑥ 黑夜入侵者行放在据点地图块里的位置（{m['roleInvaderSpawnMaps']} 张）是入侵者的出生点，"
    "证据并进 invader，不标 stronghold。",

    "【场合】raid / event 用到的「地图模式修饰」是**推断的枚举对应**：Paramdex Param Meta 只给 "
    "LotBaseMapPatternFlag.modifier、LotBaseSmallBaseAndSpot.modifier1/2、MapPatternSet.*Modifier* 等标了 "
    "Enum = PATTERN_MODIFIER，本数据集读的 LotResultMapPatternFlag.modifier 与 LotResultSmallBaseAndSpot.modifier "
    "在 Meta 里没有 Enum 标注（同名字段、同一族表），是按 PATTERN_MODIFIER 套用的。生成时实测、对不上就报错的旁证："
    f"① 突袭修饰各自只落在一个突袭地图块上，且与地图块 Paramdex 行名一一对应：{m['roleRaidModifierPairs']}；"
    f"② 地图修饰 10–15 与地图模式 Paramdex 行名的地形词一致：{m['roleMapModifierWords']}；"
    f"③ 抽选结果全部带修饰 {HORDE_MODIFIER[0]} 的 {m['roleHordePieces']} 张地图块行名都是「Night Horde - …」；"
    f"④ 自带 modifier {MERCHANT_MODIFIER[0]} 的地图块是 {m['roleMerchantPieces']}；"
    "⑤ LotResultMapPatternFlag.targetBoss（Paramdex Meta：Refs = NightBossMenuParam）是这个地图模式属于哪位夜王的远征"
    f"（{m['rolePatternTargetCheck']}）：各 Raid 修饰所在地图模式的 targetBoss——{m['roleRaidTargets']}；"
    "每种夜王 Raid 修饰都从不出现在该夜王自己的远征里，与「突袭 = 夜王闯进别的夜王的远征」一致"
    "（逐块分布写在突袭地图块 placementMaps 的 evidence.raid 与夜王突袭行的证据 note 里）。"
    "大据点默认地块（placementMaps kind = majorBaseDefault）标 event 的依据同样不是游戏文本而是参数间接证据："
    f"全表 {m['roleMeteorPatterns']} 个带修饰 {METEOR_MODIFIER[0]}（{METEOR_MODIFIER[1]}）的地图模式"
    "个个都把某个大据点默认地块挂出来；"
    f"默认地块里的首领行是 {m['roleDefaultBossRows']}；"
    f"但默认地块一共 {m['roleDefaultLots']} 行抽选结果里只有 {m['roleDefaultLotsMeteor']} 行在陨石模式里，"
    f"另外 {m['roleDefaultLots'] - m['roleDefaultLotsMeteor']} 行在别的模式里（Paramdex 行名多是「(Cataclysm)」天变地块），"
    "默认地块在没有被抽选覆盖时是否也会放出这只首领，参数表里看不出来（要看地图事件脚本 EMEVD，本数据集没有解析）。"
    "每张默认地块的这两类证据写在 placementMaps[地图].evidence.event 里。",

    f"【场合】开放地图地块 m60_*（本产物引用 {m['roleOverworldMaps']} 张）按该地块该地形变体的**首领类变异类别**判定："
    "ChaosMatchingMutationEnemyTableParam 里 smallBaseId = 0 的行是开放地块上的变异刷新点，Paramdex 把定位字段叫 "
    "mapUnk_1(u8) / mapUnk_2(u8) / mapUnk_3(u16)、没有说明，按小端拼成一个整数正好是 60XXYY（地块 m60_XX_YY）。"
    f"这是**推断的解码**，生成时逐行断言的旁证：smallBaseId = 0 的 {m['roleTileRows']} 行全部解码成 60XXYY"
    f"（{m['roleTileCodes']} 个地块），smallBaseId > 0 的行全部解码成 0；行号本身也编码了同一个地块与地形变体"
    "（modifierMapId1 = 0 的行号 = 60XXYY × 1000 + 序号；modifierMapId1 = 10+v 的行号在 10^6 / 10^5 / 10^4 位上 = "
    "XX−40 / YY−30 / v），两种编码逐行一致。适用规则：modifierMapId1 = 10+v 的行只在地形变体 v；modifierMapId1 = 0 的行"
    "对宁姆韦德及各特异地形通用，modifierMapId2/3 列出**不适用**的变体，大空洞（变体 4）有自己的一套行；"
    f"坑道精英三行实测对得上：{m['roleTileMineChecks']}。"
    "判定：该变体的首领类类别含 120（Field Boss）→ 场景头目；没有 120、有 150 / 151（Mine Elite）→ 坑道精英（mine）；"
    "没有 120 / 150 / 151、只有 110（Base Boss）→ 据点首领；都没有 → 场景头目（只表示放在开放地图上）；"
    "合并显示用的大地块（LOD，如 m60_10_09_12）没有自己的刷新点，按 part 名前缀里的原地块判定。"
    f"结果：坑道精英 {m['roleMineRows']}；开放地块上的场景头目原始行 {m['roleOverworldFieldRows']} 个，"
    f"其中 {m['roleFieldNoLotCount']} 行不带首领奖励表（{m['roleFieldNoLotRows']}），"
    "它们只说明和场景头目放在同一块开放地图上，未必就是地图上标图标的那只，证据 note 里逐行注明。"
    "v4 首版把开放地块上的行一律算 field，本版因此改判："
    f"坑道精英从 field 改成 mine；开放地块上的辅助实体（{m['roleOpenMapHelperRows']}）改成 summon；"
    f"零奖励的剧情敌人（{m['roleScriptedRows']}）改成 event。",
]

# ---------------------------------------------------------------- 工具函数


def read_param(raw: Path, name: str) -> list[dict]:
    with open(raw / "params" / f"{name}.csv", newline="", encoding="utf-8") as f:
        return list(csv.DictReader(f))


def load_fmg(raw: Path, lang: str, bnd: str, name: str) -> dict[str, str]:
    out: dict[str, str] = {}
    for fn in (f"{name}.json", f"{name}_dlc01.json"):
        p = raw / "msg" / lang / bnd / fn
        if p.exists():
            out.update({k: v for k, v in json.loads(p.read_text(encoding="utf-8")).items() if v})
    return out


def _pct(text: str):
    """SpEffectParam 里的百分数（100 = 原样）→ 倍率。"""
    v = round(float(text) / 100, 4)
    return int(v) if v == int(v) else v


def num(text: str):
    """CSV 文本 → int / float（尽量保持整数形态，便于 JSON 体积）。"""
    f = float(text)
    return int(f) if f == int(f) else round(f, 6)


# 血量倍率在 JSON 里一律保留 6 位小数（num / round(..., 6)），血量本身是整数。
MULT_PLACES = 6


def hp_from(hp_base, hp_mult) -> int:
    """整数血量 = hpBase × **公布出去的那个 hpMultiplier**，四舍五入（ROUND_HALF_UP）。

    这里刻意做两件事，保证「页面拿 hpBase × hpMultiplier 自己算」能逐位复现本数据集：

    1. **先把倍率量化到 6 位小数，再乘**。倍率是多层连乘出来的（常驻档位 × 深夜修正 ×
       深度倍率），JSON 里写的是 round(乘积, 6)；如果血量用未量化的乘积去算，两者会在
       恰好落在 .5 的行上差 1 点。
    2. **用 Decimal 而不是 float，取整规则是 ROUND_HALF_UP（四舍五入）**，不是 Python
       内建 round() 的「银行家舍入」（.5 进偶数）。v3 首版直接用 round(float × float)，
       结果同样落在 .5 的三行取整方向不一致：
         Great Wyrm 49110010  2950 × 3.51 = 10354.5 → 10355（float 噪声把它推到 .5 以上）
         Gaping Dragon 77000000 2950 × 1.83 = 5398.5 → 5398（银行家舍入进偶数）
         Godskin Noble 35700000 2055 × 2.70 = 5548.5 → 5548（同上）
       统一成 ROUND_HALF_UP 后，后两行各 +1（10355 / 5399 / 5549），其余全表零变化。
       与 Fextralife 的差异仍然只是「本数据集四舍五入、对方截断」，见 caveats 与
       notes.multiplayerScalingAudit。
    """
    return int((Decimal(str(hp_base)) * Decimal(str(hp_mult)))
               .quantize(Decimal("1"), rounding=ROUND_HALF_UP))


def is_template(row: dict) -> bool:
    """Paramdex 行名以「- Template」结尾的模板行。

    NpcParam 里 600030000/600030100/…/600030900 这 10 行是黑夜人偶（Night Invader）
    十个角色的模板：数值与同组真实行（…0010/…0110/…）完全相同，但
    getSoul = 0、rewardItemLot_1/2 = -1（真实行是 getSoul 1000 + rewardItemLot 13xxxxxx），
    chaosMatchingCorrectParamId 也不一样（模板 7740 / 真实 7780），
    显然不是实战行。schemaVersion 2 里它们因为「玩家侧数值相同」被并进真实行，
    schemaVersion 3 的 merge_key 加入 chaosCorrectId 后会被拆成独立变体、
    而且 npcId 更小会抢走两端的「代表行」位置（血条与深度倍率都会显示错的那一套），
    所以与 …9999 调试行同一口径直接跳过，明细在 notes.skippedRows。
    """
    return (row.get("Name") or "").rstrip().endswith("- Template")


def rows_no_reward(rows: list[dict]) -> bool:
    """整组行都不掉任何奖励（卢恩 / 深夜奖励表 / 敌人掉落表全是 0 或 -1）。"""
    return all(num(r["getSoul"]) <= 0 and int(r["chaosMatchingRewardLotId"]) <= 0
               and int(r["itemLotId_enemy"]) <= 0 for r in rows)


def base_and_variant(paramdex_name: str) -> tuple[str, str]:
    """Paramdex 行名 → (基础名, 变体说明)。

    "Ulcerated Tree Spirit (Field Boss)"    → ("Ulcerated Tree Spirit", "Field Boss")
    "Death Knight - Twinaxes"               → ("Death Knight", "Twinaxes")
    "Night Assassin (Wylder) - Template"    → ("Night Assassin", "Wylder, Template")
    "Gladius - Beast of Night (Boss)"       → ("Gladius - Beast of Night", "Boss")

    " - xxx" 只有在 xxx 是已知变体词（武器/阶段/模板…）时才当成变体切掉，
    否则保留在基础名里（夜王行名形如 "Adel - Baron of Night"）。
    """
    name = (paramdex_name or "").strip()
    parts = [p.strip() for p in re.findall(r"\(([^()]*)\)", name) if p.strip()]
    name = re.sub(r"\s*\([^()]*\)", "", name).strip()
    while " - " in name:
        head, tail = name.rsplit(" - ", 1)
        if not head.strip() or tail.strip() not in VARIANT_ZH:
            break
        name = head.strip()
        parts.append(tail.strip())
    return name, ", ".join(parts)


def variant_zh(variant: str) -> str:
    if not variant:
        return ""
    if variant in VARIANT_ZH:
        return VARIANT_ZH[variant]
    parts = [p.strip() for p in re.split(r"[,;]", variant) if p.strip()]
    if len(parts) > 1 and all(p in VARIANT_ZH for p in parts):
        return " · ".join(VARIANT_ZH[p] for p in parts)
    return variant


def norm(text: str) -> str:
    return re.sub(r"[^a-z0-9 ]+", "", text.lower()).strip()


def disambiguate(entries: list[dict]) -> None:
    """同一夜王/同一 Boss 下 labelZh 撞车时补一个区分后缀。

    很多 NpcParam 行的 Paramdex 名完全相同、括号里也没写变体（例如 Morgott 的
    21300000 与 21300030），拆开常驻缩放后它们数值不同却顶着同一个「基准」标签。
    优先用能说明问题的维度（血量倍率 → 人数缩放档位），都区分不开才退回行号。
    """
    by_label: dict[str, list[dict]] = defaultdict(list)
    for e in entries:
        by_label[e["labelZh"]].append(e)
    for label, group in by_label.items():
        if len(group) < 2:
            continue
        for pick, fmt_zh, fmt_en in (
            (lambda e: e["hpMultiplier"], "常驻缩放 ×{}", "perm x{}"),
            (lambda e: e["scalingId"], "缩放档位 {}", "scaling {}"),
        ):
            vals = [pick(e) for e in group]
            if len(set(vals)) == len(group):
                break
        else:
            vals = [e["npcId"] for e in group]
            fmt_zh, fmt_en = "行 {}", "row {}"
        for e, v in zip(group, vals):
            e["labelZh"] = f"{label}（{fmt_zh.format(v)}）"
            e["labelEn"] = f"{e['labelEn']} [{fmt_en.format(v)}]"


# ---------------------------------------------------------------- 缩放表


def load_speffects(raw: Path) -> dict[str, dict]:
    sp: dict[str, dict] = {}
    for r in read_param(raw, "SpEffectParam"):
        sp.setdefault(r["ID"], r)
    return sp


# SpEffectParam 每一列的「默认值」：取全表该列的众数。Paramdex 的 Param Meta 里写了
# DefaultValue，但 raw/ 下没有存 Meta，而 SpEffectParam 有上万行、绝大多数列压倒性地是
# 同一个值（maxHpRate=1、physicsAttackPowerRate=1、*DefDamageRate=1、*DamageRate=100…），
# 众数与 Meta 的 DefaultValue 在所有用到的列上一致，且只依赖 CSV 本身，结果可复现。
SPEFFECT_META_COLS = ("ID", "Name")


def speffect_defaults(sp: dict[str, dict]) -> dict[str, str]:
    cols = list(next(iter(sp.values())).keys())
    out: dict[str, str] = {}
    for col in cols:
        if col in SPEFFECT_META_COLS:
            continue
        counter: dict[str, int] = defaultdict(int)
        for row in sp.values():
            counter[row[col]] += 1
        out[col] = max(counter.items(), key=lambda kv: (kv[1], kv[0]))[0]
    return out


def speffect_diff(row: dict, defaults: dict[str, str]) -> dict:
    """SpEffect 行 → 所有与默认值不同的字段（原样保留 CSV 文本转成的数字）。"""
    out: dict = {}
    for col, default in defaults.items():
        v = row.get(col)
        if v is None or v == default:
            continue
        try:
            out[col] = num(v)
        except ValueError:
            out[col] = v
    return out


# SpEffect 里敌人自身攻击力的五项倍率（dark 槽在本作是「圣」，与 DAMAGE_RATES 一致）
ATTACK_RATE_FIELDS = [
    ("physical", "physicsAttackPowerRate"),
    ("magic", "magicAttackPowerRate"),
    ("fire", "fireAttackPowerRate"),
    ("lightning", "thunderAttackPowerRate"),
    ("holy", "darkAttackPowerRate"),
]


def attack_rates(e: dict) -> dict[str, float]:
    return {out: float(e[src]) for out, src in ATTACK_RATE_FIELDS}


def attack_rate(e: dict) -> float:
    """缩放行的攻击力倍率。人数/深度/变异三类缩放行的五项始终同值，取一个即可。"""
    rates = set(attack_rates(e).values())
    assert len(rates) == 1, f"SpEffect {e['ID']} 的五种攻击力倍率不一致：{rates}"
    return rates.pop()


# fullEffects.fields 里每个字段的**量纲**。这一列是原样搬的 SpEffectParam 列值，
# 同一个 fields 对象里混着三种完全不同的量纲，只看数字会读错一个数量级：
#   multiplier  倍率，默认 1（maxHpRate 1.1 = 血量 ×1.1）
#   percent     整数百分比，默认 100（bloodDamageRate 98 = ×0.98；顶层 scaling.*
#               里的 ailmentDamageRate / poisonRate 就是它 ÷ 100 之后的值）
#   flag        作用目标标记位，0/1，不是数值（全部 136 条人数缩放行上恒为 1）
#   enum        枚举/状态号，不是数值（spCategory 140 = 人数缩放分类；stateInfo 282）
# 生成时会断言 fields 里出现的每个列名都在这张表里，出现新列会直接失败而不是静默漏说明。
SCALING_FIELD_UNITS = {
    # 倍率（默认 1）
    "maxHpRate": "multiplier",
    "maxStaminaRate": "multiplier",
    "saReceiveDamageRate": "multiplier",
    "changeSaRecoveryVelocity": "multiplier",
    "staminaAttackRate": "multiplier",
    "haveSoulRate": "multiplier",
    "itemDropRate": "multiplier",
    "physicsAttackPowerRate": "multiplier",
    "magicAttackPowerRate": "multiplier",
    "fireAttackPowerRate": "multiplier",
    "thunderAttackPowerRate": "multiplier",
    "darkAttackPowerRate": "multiplier",
    "physicsDiffenceRate": "multiplier",
    "magicDiffenceRate": "multiplier",
    "fireDiffenceRate": "multiplier",
    "thunderDiffenceRate": "multiplier",
    "darkDiffenceRate": "multiplier",
    "poisonDefDamageRate": "multiplier",
    "diseaseDefDamageRate": "multiplier",
    "bloodDefDamageRate": "multiplier",
    "curseDefDamageRate": "multiplier",
    "freezeDefDamageRate": "multiplier",
    "sleepDefDamageRate": "multiplier",
    "madnessDefDamageRate": "multiplier",
    # 整数百分比（默认 100）
    "poisonDamageRate": "percent",
    "diseaseDamageRate": "percent",
    "bloodDamageRate": "percent",
    "curseDamageRate": "percent",
    "freezeDamageRate": "percent",
    "sleepDamageRate": "percent",
    "madnessDamageRate": "percent",
    # 标记位（0/1，不是倍率）
    "effectTargetSelfTarget": "flag",
    "effectTargetFriendlyTarget": "flag",
    "effectTargetOpposeTarget": "flag",
    "effectTargetFriend": "flag",
    "effectTargetEnemy": "flag",
    "magParamChange": "flag",
    "miracleParamChange": "flag",
    # 枚举 / 状态号（不是数值）
    "spCategory": "enum",
    "categoryPriority": "enum",
    "stateInfo": "enum",
    "invocationConditionsStateChange1": "enum",
    "invocationConditionsStateChange2": "enum",
    "invocationConditionsStateChange3": "enum",
}

SCALING_FIELD_UNIT_NOTE = (
    "fullEffects.*.fields 是 SpEffectParam 原样的列值，一个对象里混着四种量纲，"
    "fieldUnits 逐列给出：multiplier = 倍率（默认 1，如 maxHpRate 1.1 = 血量 ×1.1）；"
    "percent = 整数百分比（默认 100，如 bloodDamageRate 98 = ×0.98，"
    "顶层 scaling.*.ailmentDamageRate / poisonRate 就是它 ÷100 之后的值）；"
    "flag = 作用目标标记位（0/1，不是数值，人数缩放行上恒为 1）；"
    "enum = 枚举或状态号（spCategory 140 是「人数缩放」这个分类，stateInfo 282 是状态号，"
    "都不参与任何乘算）。**不要把 percent 和 multiplier 放进同一次连乘**。"
)


class Scaling:
    """multiPlayCorrectionParamId → 双人/三人倍率。"""

    def __init__(self, raw: Path, sp: dict[str, dict], defaults: dict[str, str]):
        self.mpc = {r["ID"]: r for r in read_param(raw, "MultiPlayCorrectionParam")}
        self.sp = sp
        self.defaults = defaults
        self.used: dict[int, dict] = {}

    def _full(self, eid: str) -> dict | None:
        """client1/client2 指向的 SpEffect 行的**全部**非默认字段。

        用来回答「多人是不是简单乘倍数」：把整行摊开看，改动的只有
        maxHpRate / saReceiveDamageRate / changeSaRecoveryVelocity /
        七种 *DefDamageRate（异常累积） / 四种 *DamageRate（异常发动伤害） /
        五种 *AttackPowerRate（少数档位），外加 spCategory=140、stateInfo=282 两个
        标记位。**没有**任何防御/减伤（*DiffenceRate、defEnemyDmgCorrectRate_*）、
        没有 haveSoulRate（卢恩）、没有 change*ResistPoint（异常阈值）、
        没有 maxStaminaRate / itemDropRate。
        """
        row = self.sp.get(eid)
        if row is None:
            return None
        return {
            "spEffectId": int(eid),
            "nameEn": row["Name"] or None,
            "fields": speffect_diff(row, self.defaults),
        }

    @staticmethod
    def _tier(sp: dict | None) -> dict | None:
        """SpEffectParam 行 → 一个人数档位。

        字段含义（由 Paramdex 行名反查确认，见模块 docstring）：
          maxHpRate               血量倍率
          saReceiveDamageRate     承受削韧倍率（0.55 = 同样的削韧只吃 55%）
          changeSaRecoveryVelocity 削韧恢复速度倍率
          bloodDamageRate(u8 %)   异常「发动时的伤害」倍率（出血/冻伤/睡眠/发狂同值）
          poisonDamageRate(u8 %)  中毒/腐败的发动伤害倍率
          poisonDefDamageRate     承受的异常「累积量」倍率（七种异常同值）
        阈值本身由 change*ResistPoint 控制，人数缩放行全为 0，因此多人不改阈值。
        """
        if sp is None:
            return None
        buildup = {sp[f"{k}DefDamageRate"]
                   for k in ("poison", "disease", "blood", "curse", "freeze", "sleep", "madness")}
        assert len(buildup) == 1, f"人数缩放行 {sp['ID']} 的七种 *DefDamageRate 不一致：{buildup}"
        return {
            "hp": num(sp["maxHpRate"]),
            "poiseTaken": num(sp["saReceiveDamageRate"]),
            "poiseRecover": num(sp["changeSaRecoveryVelocity"]),
            "ailmentDamageRate": _pct(sp["bloodDamageRate"]),
            "poisonRate": _pct(sp["poisonDamageRate"]),
            "buildupRate": num(sp["poisonDefDamageRate"]),
            # schemaVersion 3 新增：多人时敌人自身的攻击力倍率。多数档位是 1，
            # 但 7744 / 7753 / 7754 三档双人 ×1.1、三人 ×1.2 —— 人越多 Boss 打得越疼。
            "attackRate": num(str(attack_rate(sp))),
            "staminaAttackRate": num(sp["staminaAttackRate"]),
        }

    def get(self, mpc_id: str) -> tuple[int | None, dict | None]:
        mid = int(mpc_id)
        if mid == 0 or mpc_id not in self.mpc:
            return None, None
        row = self.mpc[mpc_id]
        full = {
            "duo": self._full(row["client1SpEffectId"]),
            "trio": self._full(row["client2SpEffectId"]),
            # 4 人档位在 NIGHTREIGN 里整表都是 -1（游戏最多 3 人）
            "quad": self._full(row.get("client3SpEffectId", "-1")),
            "overrideType": num(row["bOverrideSpEffect"]) if row.get("bOverrideSpEffect") else None,
        }
        # 本档位真正出现过的列 → 量纲。fields 里混着倍率/百分数/标记位/枚举，
        # 没有这张表没法安全地用（见 SCALING_FIELD_UNIT_NOTE）。
        seen: set[str] = set()
        for side in ("duo", "trio", "quad"):
            if full[side]:
                seen |= set(full[side]["fields"])
        missing = sorted(seen - set(SCALING_FIELD_UNITS))
        assert not missing, f"人数缩放行出现未登记量纲的列：{missing}（请补 SCALING_FIELD_UNITS）"
        full["fieldUnits"] = {k: SCALING_FIELD_UNITS[k] for k in sorted(seen)}
        entry = {
            "group": row["Name"] or None,
            "duo": self._tier(self.sp.get(row["client1SpEffectId"])),
            "trio": self._tier(self.sp.get(row["client2SpEffectId"])),
            # schemaVersion 3 新增：两档人数缩放 SpEffect 的全部非默认字段 + 行号
            "fullEffects": full,
        }
        self.used[mid] = entry
        return mid, {"duo": entry["duo"], "trio": entry["trio"]}


# ------------------------------------------------- 常驻 SpEffect（威胁档位/永夜/DLC）

PERM_LABEL_RULES = [
    (re.compile(r"^Enemy Scaling: Field Boss Threat"), "野外 Boss 威胁档位"),
    (re.compile(r"^Enemy Scaling: Night Boss Threat"), "守夜 Boss 威胁档位"),
    (re.compile(r"^Enemy Scaling: Final Boss Threat"), "最终 Boss 威胁档位"),
    (re.compile(r"^Enemy Scaling: (.+)$"), "敌人缩放（{0}）"),
    (re.compile(r"^\[Deep of Night Everdark Scaling\] (.+)$"), "深夜 · 永夜之王缩放（{0}）"),
    (re.compile(r"^\[DLC Deep of Night Scaling\] (.+)$"), "深夜 · DLC 缩放（{0}）"),
    (re.compile(r"^\[Everdark Sovereign Scaling\] (.+)$"), "永夜之王加成（{0}）"),
    (re.compile(r"^\[DLC Scaling\] (.+)$"), "DLC 加成（{0}）"),
    (re.compile(r"^\[NPC Quest Scaling\]"), "NPC 任务缩放"),
    (re.compile(r"^\[(.+?)\] Stat Change$"), "数值调整（{0}）"),
]


def perm_label_zh(name: str, deep: bool) -> str:
    for rx, tpl in PERM_LABEL_RULES:
        m = rx.match(name or "")
        if m:
            return tpl.format(*m.groups()) if m.groups() else tpl
    return "深夜专属常驻缩放" if deep else "未命名常驻缩放"


class PermScaling:
    """NpcParam.spEffectID0..31 上的常驻 SpEffect。

    这些 SpEffect 没有 invocationConditions，敌人一出生就挂着，
    maxHpRate / saReceiveDamageRate / changeSaRecoveryVelocity / bloodDamageRate
    全部作用在 NpcParam 的基准值上 —— 也就是说 NpcParam.hp 不是玩家看到的血量。
    只有 invocationConditionsStateChange1 = 2287（深夜模式）那一批是条件触发的，
    单独收集到 deepOfNight 里，不计入常驻。
    """

    SLOTS = [f"spEffectID{i}" for i in range(32)]

    def __init__(self, sp: dict[str, dict]):
        self.sp = sp
        self.used: dict[int, dict] = {}

    # (血量, 承受削韧, 削韧恢复, 异常发动伤害, 耐力削减, 物理/魔力/火/雷/圣 五项攻击力)
    FACTOR_KEYS = ("hp", "poiseTaken", "poiseRecover", "ailmentDamageRate",
                   "staminaAttackRate") + tuple(k for k, _ in ATTACK_RATE_FIELDS)

    def _factors(self, e: dict) -> tuple[float, ...]:
        atk = attack_rates(e)
        return (
            float(e["maxHpRate"]),
            float(e["saReceiveDamageRate"]),
            float(e["changeSaRecoveryVelocity"]),
            float(e["bloodDamageRate"] or 100) / 100,
            float(e["staminaAttackRate"]),
        ) + tuple(atk[k] for k, _ in ATTACK_RATE_FIELDS)

    def _register(self, eid: int, e: dict, deep: bool) -> None:
        if eid in self.used:
            return
        f = dict(zip(self.FACTOR_KEYS, self._factors(e)))
        self.used[eid] = {
            "nameEn": e["Name"] or None,
            "nameZh": perm_label_zh(e["Name"], deep),
            "hp": num(str(f["hp"])),
            "poiseTaken": num(str(f["poiseTaken"])),
            "poiseRecover": num(str(f["poiseRecover"])),
            "ailmentDamageRate": num(str(f["ailmentDamageRate"])),
            "deepOfNight": deep,
            # schemaVersion 3 新增：敌人自身的攻击力倍率（分属性）与对玩家耐力的削减倍率。
            # 常驻档位里确实有只加物理的行（16178「×2.42 血 ×1.1 物理」），所以必须分开记。
            "attackRates": {k: num(str(f[k])) for k, _ in ATTACK_RATE_FIELDS},
            "attackRate": num(str(f["physical"])),
            "staminaAttackRate": num(str(f["staminaAttackRate"])),
        }

    def of(self, row: dict) -> dict:
        """→ 常驻缩放汇总（含深夜档）。"""
        ids: list[int] = []
        deep_ids: list[int] = []
        n = len(self.FACTOR_KEYS)
        base = [1.0] * n
        deep_f = [1.0] * n
        neutral = tuple([1.0] * n)
        for slot in self.SLOTS:
            v = row.get(slot)
            if v in (None, "", "0", "-1"):
                continue
            e = self.sp.get(v)
            if e is None:
                continue
            f = self._factors(e)
            if f == neutral:
                continue
            conds = [int(e[f"invocationConditionsStateChange{i}"]) for i in (1, 2, 3)]
            deep = DEEP_OF_NIGHT_STATE in conds
            if any(conds) and not deep:
                continue                      # 其它条件触发的效果不算常驻
            eid = int(v)
            self._register(eid, e, deep)
            target, bucket = (deep_f, deep_ids) if deep else (base, ids)
            bucket.append(eid)
            for i in range(n):
                target[i] *= f[i]
        b = dict(zip(self.FACTOR_KEYS, base))
        d = dict(zip(self.FACTOR_KEYS, (x * y for x, y in zip(base, deep_f))))
        return {
            "ids": sorted(ids),
            "deepIds": sorted(deep_ids),
            # 有没有挂「[Everdark Sovereign Scaling] …」：部分永夜之王行的 Paramdex
            # 行名与本体一模一样（75000200 / 76001000），只能靠这个认出来
            "everdarkScaled": any(
                (self.used[i]["nameEn"] or "").startswith("[Everdark Sovereign Scaling]")
                for i in ids),
            "hpMultiplier": round(b["hp"], 6),
            "poiseTakenBase": round(b["poiseTaken"], 6),
            "poiseRecoverMultiplier": round(b["poiseRecover"], 6),
            "ailmentDamageRateBase": round(b["ailmentDamageRate"], 6),
            "attackRatesBase": {k: round(b[k], 6) for k, _ in ATTACK_RATE_FIELDS},
            "attackRateBase": round(b["physical"], 6),
            "staminaAttackRateBase": round(b["staminaAttackRate"], 6),
            "deep": None if not deep_ids else {
                "hpMultiplier": round(d["hp"], 6),
                "poiseTakenBase": round(d["poiseTaken"], 6),
                "poiseRecoverMultiplier": round(d["poiseRecover"], 6),
                "ailmentDamageRateBase": round(d["ailmentDamageRate"], 6),
                "attackRatesBase": {k: round(d[k], 6) for k, _ in ATTACK_RATE_FIELDS},
                "attackRateBase": round(d["physical"], 6),
                "staminaAttackRateBase": round(d["staminaAttackRate"], 6),
            },
        }


# ------------------------------------------------- 深夜深度 / 变异个体（红化）

# ChaosMatchingMutationCategoryParam.categoryId 的枚举（Paramdex Param Enums/
# MUTATION_CATEGORY.json）+ 简中说明。除 120 外游戏文本里没有这些类别的词条，zh 是说明不是官方译名；
# 120 Field Boss 取游戏文本「场景头目」（TutorialBody 403200 地图图标说明，engus 同一处写 Field Boss；
# v3 是「野外首领」），150/151 的「坑道」取自同一段的「坑道入口」（Tunnel Entrance），「精英」随枚举名。
MUTATION_CATEGORY_ZH = {
    100: ("普通敌人 A", "Standard Enemy A"),
    101: ("普通敌人 B", "Standard Enemy B"),
    103: ("普通敌人 C", "Standard Enemy C"),
    104: ("普通敌人 D", "Standard Enemy D"),
    105: ("普通敌人（大空洞）", "Standard Enemy (Great Hollow)"),
    110: ("据点首领", "Base Boss"),
    120: ("场景头目", "Field Boss"),
    130: ("城堡精英", "Castle Elite"),
    131: ("城堡敌人", "Castle Enemy"),
    135: ("东部堡垒首领/精英（大空洞）", "Eastern Fort Boss/Elite (Great Hollow)"),
    136: ("西部堡垒首领/精英（大空洞）", "Western Fort Boss/Elite (Great Hollow)"),
    137: ("东部堡垒敌人（大空洞）", "Eastern Fort Enemy (Great Hollow)"),
    138: ("西部堡垒敌人（大空洞）", "Western Fort Enemy (Great Hollow)"),
    140: ("圣甲虫", "Scarab"),
    141: ("圣甲虫（大空洞）", "Scarab (Great Hollow)"),
    150: ("坑道精英", "Mine Elite"),
    151: ("坑道精英（大空洞）", "Mine Elite (Great Hollow)"),
    160: ("封印监牢首领", "Evergaol Boss"),
}

# ChaosMatchingMutationCategoryParam.modifierMapId 里出现的「地图」枚举
# （Paramdex Param Enums/PATTERN_MODIFIER.json 的 10–15 段）。
# 简中名 schemaVersion 4 起改取游戏文本（terrain_names：修饰 10+v = 地形变体 v，
# 宁姆韦德 / 山顶 / 火山口 / 腐败森林 / 大空洞 / “隐城”诺克拉缇欧）；
# v3 写的是说明性译名「林薇尔德」「陨石坑」「笼罩之城」，不是游戏文本，见 caveats【变异】。
# 这里只留英文（= 枚举原文）和 0 的说明性标签。
MUTATION_MAP_ZH = {
    0: ("全部地图", "All maps"),
    10: ("", "Map - Limveld"),
    11: ("", "Map - Mountaintop"),
    12: ("", "Map - The Crater"),
    13: ("", "Map - Rotted Woods"),
    14: ("", "Map - Great Hollow"),
    15: ("", "Map - Shrouded City"),
}
# v3 的变体 labelZh 译法 → 现在的游戏文本（VARIANT_ZH 的键；只用于 caveats 说明改了哪几个值）
VARIANT_ZH_V3 = {"Crater": "陨石坑", "Noklateo": "诺克拉提欧", "Field Boss": "野外首领"}
# v3 的 mapZh → 游戏文本（只用于 caveats 说明改了哪几个值）
MUTATION_MAP_ZH_V3 = {10: "林薇尔德", 11: "山顶", 12: "陨石坑", 13: "腐败森林", 14: "大空洞", 15: "笼罩之城"}

# CL_MenuText 里和深夜/深度/变异个体有关的词条 ID（游戏文本，不是翻译）
DEEP_TEXT_IDS = {
    "deepOfNight": "131150",     # 深夜 / The Deep of Night
    "depth": "131011",           # 深度 / Depth
    "mutation": "338806",        # 已打倒变异个体 / Variant felled
    "mutationCount": "138296",   # 打败敌人的次数（变异个体） / Enemies felled (variants)
    "description": "131151",     # 深夜的说明
}


class DepthScaling:
    """深夜「深度 1–5」的数值缩放。

    NpcParam.chaosMatchingCorrectParamId → ChaosMatchingCorrectParam →
    spEffect00..spEffect04 = 深度 1..5 的 SpEffect 行
    （Paramdex 行名「[Deep Night Scaling] Tier X, Depth N」）。
    这些行自身 stateInfo = 2287，也就是「进入深夜」这个状态本身就是它们打上去的，
    因此它们和 NpcParam 上 invocationConditionsStateChange=2287 的修正行是叠加关系：
    深度行 spCategory = 0，[Deep of Night Everdark Scaling] 是 20（个别 100），
    [DLC Deep of Night Scaling] 是 0 —— 分类各不相同，不互相覆盖，倍率连乘。
    """

    def __init__(self, raw: Path, sp: dict[str, dict]):
        self.rows = {r["ID"]: r for r in read_param(raw, "ChaosMatchingCorrectParam")}
        self.sp = sp
        self.used: dict[int, dict] = {}

    def get(self, chaos_id: str) -> tuple[int | None, dict | None]:
        """→ (ChaosMatchingCorrectParam 行号, {"1".."5": 该深度的倍率})"""
        if chaos_id in (None, "", "0", "-1") or chaos_id not in self.rows:
            return None, None
        row = self.rows[chaos_id]
        depths: dict[str, dict] = {}
        for i, depth in enumerate(DEPTHS):
            eid = row[f"spEffect0{i}"]
            e = self.sp.get(eid)
            if e is None:
                continue
            depths[str(depth)] = {
                "spEffectId": int(eid),
                "nameEn": e["Name"] or None,
                "hp": num(e["maxHpRate"]),
                "attackRate": num(str(attack_rate(e))),
                "poiseTaken": num(e["saReceiveDamageRate"]),
                "staminaAttackRate": num(e["staminaAttackRate"]),
            }
        if not depths:
            return None, None
        cid = int(chaos_id)
        group = row["Name"] or None
        # 行名形如「[Deep Night Scaling] Tier 3b, Depth 1」，档位名取 Tier 那段
        tier = _depth_tier_name(depths["1"]["nameEn"])
        self.used[cid] = {
            "group": group,
            "tier": tier,
            # tier 为 null 的两条（98810 / 98815）是联机突袭行：它们的 SpEffect 行名
            # 就叫「[Gladius Raid] Depth 1」，Paramdex 根本没给它们 Tier 段。tierLabel
            # 保证**恒非空**，页面直接拿它当档位标题即可；想知道标题是不是 Paramdex
            # 的正式 Tier 名，看 tierSource。
            "tierLabel": tier or group or f"chaosCorrectId {cid}",
            "tierSource": "tierName" if tier else ("rowName" if group else "chaosCorrectId"),
            "depths": depths,
        }
        return cid, depths


def _depth_tier_name(name: str | None) -> str | None:
    m = re.match(r"^\[(?:Deep Night Scaling|.+?)\]\s*(.*?),?\s*Depth \d+$", name or "")
    return (m.group(1).strip() or None) if m else (name or None)


def depth_tier_stats(tiers: dict[int, dict]) -> dict:
    """deepOfNightTiers 的实测统计，供 caveats / notes 直接引用（不写死数字）。"""
    labels: dict[str, list[int]] = defaultdict(list)
    tables: dict[str, list[int]] = defaultdict(list)
    for cid, t in sorted(tiers.items()):
        labels[t["tierLabel"]].append(cid)
        sig = json.dumps({d: {k: v for k, v in dv.items() if k not in ("spEffectId", "nameEn")}
                          for d, dv in t["depths"].items()}, sort_keys=True, ensure_ascii=False)
        tables[sig].append(cid)
    named = sorted(l for l, _ in labels.items()
                   if any(tiers[c]["tierSource"] == "tierName" for c in labels[l]))
    unnamed = sorted(l for l in labels if l not in named)
    return {
        "ids": len(tiers),
        "labels": len(labels),
        "namedLabels": named,
        "unnamedLabels": unnamed,
        "tables": len(tables),
        # 每张数值表对应哪些 chaosCorrectId（同表的档位名可能不同，见下面的说明）
        "tableGroups": [sorted(v) for v in tables.values()],
    }


class Mutations:
    """深夜的「变异个体」（玩家口中的红化 / 红怪）。

    NpcParam.chaosMatchingSpEffectSetParamId → SpEffectSetParam
    「Set: Deep Night Mutation - VFX + Scaling」：
      spEffectId1 = 红光 VFX 档位（4480 / 4481 / 4482 / 4483，vfxId 150050–150053）
      spEffectId2 = 数值档位（[Deep Night Scaling] N x HP, M x damage）
      spEffectId3 = 附加档（4485，vfxId 150055，只挂在少数行上）
    数值档位的 spCategory 是 203，和深度（0）、常驻（0）、人数（140）都不同，
    所以变异倍率是在其它缩放之上再乘一层。haveSoulRate 说明变异个体掉的卢恩也翻倍。
    「变异个体」是游戏内简中原词（CL_MenuText 138296 / 338806），不是自造译名。
    """

    def __init__(self, raw: Path, sp: dict[str, dict]):
        self.sets = {r["ID"]: r for r in read_param(raw, "SpEffectSetParam")}
        self.sp = sp
        self.used: dict[int, dict] = {}

    def get(self, set_id: str) -> int | None:
        if set_id in (None, "", "0", "-1") or set_id not in self.sets:
            return None
        row = self.sets[set_id]
        sid = int(set_id)
        if sid not in self.used:
            slots = [row[f"spEffectId{i}"] for i in (1, 2, 3, 4)]
            vfx_ids, stat = [], None
            for v in slots:
                e = self.sp.get(v)
                if e is None:
                    continue
                if (e["Name"] or "").startswith("Deep Night Mutation VFX"):
                    vfx_ids.append(int(v))
                elif float(e["maxHpRate"]) != 1.0 or attack_rate(e) != 1.0:
                    stat = e
            self.used[sid] = {
                "nameZh": "变异个体",
                "nameEn": "Variant",
                "setNameEn": row["Name"] or None,
                "vfxSpEffectIds": sorted(vfx_ids),
                "vfxTier": (min(vfx_ids) - 4479) if vfx_ids else None,
                "statSpEffectId": int(stat["ID"]) if stat else None,
                "statNameEn": (stat["Name"] or None) if stat else None,
                "hp": num(stat["maxHpRate"]) if stat else 1,
                "attackRate": num(str(attack_rate(stat))) if stat else 1,
                "runeRate": num(stat["haveSoulRate"]) if stat else 1,
            }
        return sid


# ---------------------------------------------------------------- 出场场合（schemaVersion 4）
#
# v3 的 tier / tiers 只看 multiPlayCorrectionParamId 的档位名（Field Boss Threat 7740–7749 /
# Night Boss Threat 7750–7759），那是**缩放档位**，不是「在哪出现」：铃珠猎人的野外首领行
# 31000010 挂的就是 7753「Night Boss Threat」，熔炉骑士的守夜行 25000020 挂的是 7746
# 「Field Boss Threat」。游戏里决定一行 NpcParam 在哪登场的是两段：
#   1) 地图 MSB 的 Enemy part 带 npcParamId（extract_msb.py 导出到 raw/msb/MsbEnemyParts.csv）；
#   2) 参数表决定这张地图什么时候进入远征：
#        LotResultPlayAreaParam.bossId1/bossId2/extraBossId1/extraBossId2 → 夜晚首领地图块
#        （Paramdex Meta：Refs = SmallBaseMapVariationParam）；
#        LotResultSmallBaseAndSpot.smallBaseMapId → 地图块挂到哪个挂点（SmallBaseAndSpotAttachPoint）；
#        SmallBaseAndSpotAttachPoint.defaultSmallBase → 大据点挂点的默认地块；
#        ChaosMatchingMutationEnemyTableParam.categoryId + smallBaseId → 地图块的敌人类别
#        （MUTATION_CATEGORY：110 据点首领 / 120 场景头目 / 130–138 城寨与地下要塞 / 150–151 坑道精英 /
#        160 封印监牢，
#        **没有「守夜/夜晚首领」类别**——夜晚首领只走 LotResultPlayAreaParam）；
#        LotResultMapPatternFlag.modifier → 地图模式带的事件修饰（600–604 / 10000–10001 Raid、
#        180 Night Horde、200 Meteorite…，PATTERN_MODIFIER 枚举）；
#        SmallbaseInvationNpcParam.npcParamId → 黑夜入侵者（直接引用 NpcParam，不经过 MSB）。
# 地图 ID 与地图块 ID 的对应：mAA_BB_00_00 ↔ SmallBaseMapVariationParam 行 AA×100+BB
# （4656 ↔ m46_56_00_00「Field Boss - Bell Bearing Hunter」，MSB 里正好放着 31000010）。

# 场合枚举：键 → (简中标签, 英文标签, 判定口径)。字典顺序即 roles 数组的规范顺序。
# 简中标签里「封印监牢」「突袭事件」「黑夜入侵者」「场景头目」是游戏文本原词（CL_MenuText 338310 / 138275、
# AttachEffectName 7060200、TutorialBody 403200 地图图标说明），「坑道精英」的「坑道」取自同一段的
# 「坑道入口」，其余是说明性标签，不是官方译名（生成时 map_icon_names 断言这些原词确实在游戏文本里）。
ROLE_DEFS = {
    "night": ("守夜首领", "Night Boss",
              "第一天/第二天夜晚缩圈后出现的首领：所在地图块被 LotResultPlayAreaParam 抽为 "
              "bossId1（初始日：夜晚）/ bossId2（中间日：夜晚）/ extraBossId1/2（同一夜的额外首领）"),
    "prelude": ("守夜前哨", "Night Boss Prelude",
                "夜晚首领地图块里、首领本体登场前先出现的一波敌人：放在夜晚首领地图块里且 "
                "multiPlayCorrectionParamId = 7741（凡是放进地图的 7741 行都在夜晚首领地图块里，生成时断言；"
                "Paramdex 行名也都写着 Prelude）。所在地图块若也挂到大空洞高塔，前哨会随地图块一起出现在高塔里，"
                "但它不是高塔首领，所以不另标 tower（证据 note 里注明）"),
    "field": ("场景头目", "Field Boss",
              "白天在野外遇到的强敌。「场景头目」是游戏文本（TutorialBody 403200 的地图图标说明：场景头目——"
              "「四处徘徊的强大敌人。」，engus 同一处写 Field Boss）。判定：所在地图块在 ChaosMatchingMutationEnemyTableParam 里是 "
              "categoryId 120（Field Boss，含城寨屋顶/地下室与大空洞的野外挂点；大据点默认地块除外，见 event）；"
              "或者放在开放地图地块 m60_*（宁姆韦德与各特异地形）上，且该地块该地形变体的变异类别含 120"
              "（smallBaseId = 0 的行，地块号由 mapUnk_1..3 解码，见 caveats【场合】开放地图地块），"
              "或该地块该变体没有任何首领类变异类别（此时只表示「放在开放地图上」）。"
              "开放地块上不带首领奖励表（rewardItemLot_2 ≤ 0）的行（火焰战车等）只说明它和场景头目放在同一块开放地图上，"
              "未必就是地图上标图标的那只，证据 note 里逐行注明"),
    "stronghold": ("据点首领", "Stronghold Boss",
                   "放在其余据点/地点地图块里（要塞、营地、遗迹、教堂、沼泽、铁匠村、城寨、"
                   "大空洞的大教堂/遗迹/地下要塞等；变异类别 110 / 130–138 或无类别）；"
                   "开放地图地块上该地形变体只有 110（Base Boss）类别、没有 120 / 150 / 151 时也算这里"),
    "mine": ("坑道精英", "Mine Elite",
             "坑道里的精英敌人（「坑道」是游戏文本：TutorialBody 403200 地图图标「坑道入口」/ Tunnel Entrance；"
             "「精英」随 Paramdex 枚举名 Mine Elite，是说明性标签）：放在开放地图地块 m60_* 上，且该地块该地形变体"
             "的变异类别有 150 / 151（MUTATION_CATEGORY：Mine Elite / Mine Elite (Great Hollow)）、没有 120。"
             "宁姆韦德坑道精英的首领奖励表 Paramdex 行名写着 (Mine)（ItemLotParam_enemy 613xxxx，如 6130000「[Troll (Mine)]」）；"
             "大空洞的坑道精英（151）奖励表没有 Paramdex 行名，证据 note 里注明它是该地形变体上唯一带首领奖励表的首领档行"),
    "evergaol": ("封印监牢", "Evergaol",
                 "封印监牢地图块：变异类别 160（Evergaol Boss），"
                 "SmallBaseEnemyLotMapCombinationParam 的 Evergaol 行也引用它们"),
    "tower": ("大空洞高塔首领", "Great Hollow Tower Boss",
              "夜晚首领地图块又被 LotResultSmallBaseAndSpot 挂到大空洞的高塔挂点"
              "（挂点 Paramdex 行名 [Great Hollow] East/West Tower Boss - Floor 1–3），"
              "随特异地形「大空洞」的地图生成放置，不经过夜晚首领的抽选；只标首领本体，"
              "同一地图块里 7741 档的前哨行只标 prelude"),
    "raid": ("突袭事件", "Raid Event",
             "远征途中的突袭：地图块的全部抽选结果都落在带 Raid 修饰（PATTERN_MODIFIER 600–604 / "
             "10000–10001）的地图模式里；夜王本体行出现在带 Raid 修饰的据点里（哈尔莫妮亚突袭）也算"),
    "invader": ("黑夜入侵者", "Night Invader",
                "SmallbaseInvationNpcParam.npcParamId 直接引用的行（不经过地图 MSB）；"
                "这些行放在据点地图块里的出生位置也并进这里，不算据点首领"),
    "event": ("地图事件", "Map Event",
              "黑夜势力倾巢而出（地图块全部抽选结果带修饰 180 Night Horde）、"
              "大据点挂点的默认地块（SmallBaseAndSpotAttachPoint.defaultSmallBase；Paramdex 抽选行名显示是"
              "天变/陨石事件用的地块）里的首领、持秤商人地图块（抽选行 modifier 424），"
              "夜王本体行在夜王战场与突袭以外的现身，"
              "以及开放地图地块上自身不掉任何奖励、MSB part 与带对话脚本（talkId）的实体同属一个实体组的剧情敌人"
              "（推断为剧情遭遇，地图事件脚本 EMEVD 未解析）"),
    "nightlord": ("夜王战", "Nightlord Battle",
                  "夜王战场地图：放着夜王本体行（最终 Boss 档 7760–7769）、又不属于据点/地点地图块的 MSB"),
    "summon": ("随从/召唤物", "Add / Summon",
               "首领身边的附属实体（召唤物、坐骑、辅助实体等）。在首领战地图块（夜晚首领地图块 / 大空洞高塔 / "
               "夜王战场 / 场景头目地图块）里满足其一："
               "① 自身不掉任何奖励（getSoul / rewardItemLot_1/2 / chaosMatchingRewardLotId / itemLotId_enemy "
               "全为 0 或 -1）且同图另有掉奖励的首领行；"
               "② 不带任何首领奖励表（rewardItemLot_1/2 / chaosMatchingRewardLotId 全为 0 或 -1），"
               "且卢恩不超过同图首领行（带 rewardItemLot_2 首领奖励表）的 5%（坐骑、辅助实体只给零头卢恩）。"
               "开放地图地块上一张图里首领太多、①② 比不出主从，只认 ③：自身不掉任何奖励，且全部 MSB part 都换成"
               "别的模型（不是本行 chrId）、npcThinkParamId 是 0 / 1（NpcThinkParam 0 与 1 都是 logicId 11000、"
               "disableParam_NT = 1 的通用占位 AI）的辅助实体"),
    "other": ("其他地图", "Other Map",
              "放在不参与远征随机生成的地图里（圆桌厅堂/追忆/教程等，没有任何抽选表引用）"),
    "unplaced": ("未放置", "Not Placed",
                 "全部地图 MSB 的 Enemy part 与 SmallbaseInvationNpcParam 都没有引用这一行"
                 "（模板/未使用行，或只出现在未被任何抽选表引用的地图块、或只是 DummyEnemy）；"
                 "地图号落在地图块区段（与 SmallBaseMapVariationParam 的行同一个 AA 段）却没有任何表引用的地图"
                 "（如 m46_90），也按未启用地图块处理"),
}
ROLE_ORDER = tuple(ROLE_DEFS)

# 守夜前哨专用的人数缩放档位（MultiPlayCorrectionParam 行号；Paramdex 行名只写 Field Boss Threat）
PRELUDE_SCALING_ID = 7741

# LotResultPlayAreaParam 的首领槽 → CL_MenuText 里的时段词条（游戏文本）
NIGHT_SLOT_TEXT = {"bossId1": ("146501", ""), "bossId2": ("146503", ""),
                   "extraBossId1": ("146501", "（额外首领）"), "extraBossId2": ("146503", "（额外首领）")}
NIGHT_SLOTS = tuple(NIGHT_SLOT_TEXT)

# PATTERN_MODIFIER（Paramdex Param Enums）里与场合有关的几个事件修饰。
# 注意：这是**推断出来的对应**。Paramdex Param Meta 只给 LotBaseMapPatternFlag.modifier、
# LotBaseSmallBaseAndSpot.modifier1/2、MapPatternSet.*Modifier*、ChaosMatchingMutation*.modifierMapId
# 标了 Enum="PATTERN_MODIFIER"；本脚本读的 LotResultMapPatternFlag.modifier 与
# LotResultSmallBaseAndSpot.modifier 在 Meta 里**没有** Enum 标注（同名字段、同一族表）。
# 数值对得上的旁证在生成时实测并断言（measure_roles → caveats【场合】）：
#   * 600–604 / 10000 各自只落在一个突袭地图块上，且与 SmallBaseMapVariationParam 行名一一对应
#     （600 ↔ 5300「Boss Raid - Tricephalos (Gladius)」… 604 ↔ 4678「Boss Raid - Fell Omen (Morgott)」）；
#   * 10–15 与地图模式行名（Standard / Mountaintop / The Crater / Rotted Woods / Great Hollow /
#     Shrouded City）一致；180 的地图块全是「Night Horde - …」；424 落在「Scale-bearing Merchant (Libra)」。
RAID_MODIFIERS = {600: "Raid - Gladius", 601: "Raid - Gnoster", 602: "Raid - Libra",
                  603: "Raid - Maris", 604: "Raid - Morgott",
                  10000: "Raid - Caligo", 10001: "Raid - Harmonia"}
HORDE_MODIFIER = (180, "Event - Night Horde")
MERCHANT_MODIFIER = (424, "Event - Scale-bearing Merchant (Libra)")
METEOR_MODIFIER = (200, "Event - Meteorite")
# 地图模式修饰 10–15 ↔ 地图模式 Paramdex 行名里的地形关键词（用来旁证上面的推断）
MAP_MODIFIER_PATTERN_WORD = {10: "Standard", 11: "Mountaintop", 12: "The Crater", 13: "Rotted Woods",
                             14: "Great Hollow", 15: "Shrouded City"}

# 随从/召唤物的第二条判据：卢恩 ≤ 同图首领行卢恩 × 该比例（坐骑 50 / 1350、辅助实体 80 / 3200 这一类）
SUMMON_SOUL_RATIO = 0.05

# 开放地图地块 m60_XX_YY_DD：DD // 10 是地形变体（0–5 与 PATTERN_MODIFIER 10–15「Map - …」
# 一一对应，地块内容也对得上：_50 放着诺克拉缇欧的黑暗弃子、_20 放着火山口的熔岩土龙）。
# 名字取 TutorialTitle「特异地形：…」去掉前缀；宁姆韦德没有独立词条，取
# PersonalScenarioObjective 1020「在宁姆韦德，寻找砥石 / Find a whetstone in Limveld」的子串。
TILE_VARIANT_TEXT = {1: "403420", 2: "403430", 3: "403400", 4: "403440", 5: "403410"}
LIMVELD_NAME = ("宁姆韦德", "Limveld")
LIMVELD_TEXT_ID = "1020"     # PersonalScenarioObjective


def terrain_names(raw: Path) -> dict[int, tuple[str, str]]:
    """地形变体 0–5 → (简中, 英文)，全部取游戏文本（生成时断言宁姆韦德确实在 PersonalScenarioObjective 里）。

    同一组名字也用于 mutationCategories 的 mapZh（地图修饰 10–15 = 地形变体 0–5）。"""
    obj = (load_fmg(raw, "zhocn", "menu_dlc01", "PersonalScenarioObjective"),
           load_fmg(raw, "engus", "menu_dlc01", "PersonalScenarioObjective"))
    assert LIMVELD_NAME[0] in obj[0].get(LIMVELD_TEXT_ID, "") and \
        LIMVELD_NAME[1] in obj[1].get(LIMVELD_TEXT_ID, ""), \
        f"PersonalScenarioObjective {LIMVELD_TEXT_ID} 里找不到 {LIMVELD_NAME}"
    tut = (load_fmg(raw, "zhocn", "menu_dlc01", "TutorialTitle"),
           load_fmg(raw, "engus", "menu_dlc01", "TutorialTitle"))
    out = {0: LIMVELD_NAME}
    for v, tid in TILE_VARIANT_TEXT.items():
        zh, en = tut[0].get(tid, ""), tut[1].get(tid, "")
        assert "：" in zh and ": " in en, f"TutorialTitle {tid} 不是「特异地形：…」：{zh!r} / {en!r}"
        out[v] = (zh.split("：", 1)[-1], en.split(": ", 1)[-1])
    return out

# TutorialBody 403200「地图：可攻略地点（二）」逐个说明地图图标：<?image@4152##6?>：坑道入口 … ——
# 场合标签「场景头目」（field）与「坑道」（mine）的游戏文本出处。图标号 → 场合。
MAP_ICON_TEXT_ID = "403200"
MAP_ICONS = {"field": "4016", "mine": "4152", "evergaol": "4009"}


def map_icon_names(raw: Path) -> dict[str, tuple[str, str]]:
    """TutorialBody 403200 → {图标号: (简中名, 英文名)}（游戏文本；生成时断言场合标签确实取自这里）。"""
    pat = re.compile(r"<\?image@(\d+)##\d+\?>[：:]\s*([^\n]+)")
    zh, en = (dict(pat.findall(load_fmg(raw, lang, "menu_dlc01", "TutorialBody").get(MAP_ICON_TEXT_ID, "")))
              for lang in ("zhocn", "engus"))
    out = {k: (v.strip(), en.get(k, "").strip()) for k, v in zh.items()}
    assert out.get(MAP_ICONS["field"]) == ("场景头目", "Field Boss"), f"TutorialBody {MAP_ICON_TEXT_ID}：{out}"
    assert out.get(MAP_ICONS["mine"]) == ("坑道入口", "Tunnel Entrance"), f"TutorialBody {MAP_ICON_TEXT_ID}：{out}"
    assert out.get(MAP_ICONS["evergaol"], ("", ""))[0] == "封印监牢", f"TutorialBody {MAP_ICON_TEXT_ID}：{out}"
    return out


# 开放地图地块的变异刷新点 = ChaosMatchingMutationEnemyTableParam 里 smallBaseId = 0 的行。
# Paramdex 把定位字段叫 mapUnk_1(u8) / mapUnk_2(u8) / mapUnk_3(u16)，没有说明；按小端拼成一个整数
# 正好是 60XXYY（= 地块 m60_XX_YY）。这是**推断的解码**，旁证在生成时断言（Placement.__init__ / measure_roles）：
#   * smallBaseId = 0 的行全部解码成 60XXYY，smallBaseId > 0 的行全部解码成 0；
#   * 行号本身也编码了同一个地块：modifierMapId1 = 0 的行号 = 60XXYY × 1000 + 序号；
#     modifierMapId1 = 10+v 的行号在 10^6 / 10^5 / 10^4 位上 = XX−40 / YY−30 / v（v = 地形变体）；
#   * 适用规则：modifierMapId1 = 10+v 的行只在地形变体 v；modifierMapId1 = 0 的行对宁姆韦德及其特异地形
#     通用，modifierMapId2/3 列出**不适用**的变体（该地块在那几种特异地形里被整块替换）；大空洞（变体 4）
#     有自己的一套行（行号 16… 段，modifierMapId1 = 14），不吃通用行——坑道精英（150）三行实测：
#     (Mine) 首领行放在哪几个地形变体里，正好是「该地块现有 MSB 变体 − 大空洞 − modifierMapId2/3」。
TILE_BOSS_CATEGORIES = (110, 120, 150, 151, 160)   # 首领类变异类别（决定开放地块上的场合）
MINE_CATEGORIES = (150, 151)
GREAT_HOLLOW_VARIANT = 4


def tile_code(row: dict) -> int:
    """ChaosMatchingMutationEnemyTableParam 的 mapUnk_1 / mapUnk_2 / mapUnk_3 → 小端整数（60XXYY 或 0）。"""
    return int(row["mapUnk_1"]) | int(row["mapUnk_2"]) << 8 | int(row["mapUnk_3"]) << 16


def piece_family(name: str) -> tuple[str, str] | None:
    """「Great Church A - Holy (Great Hollow)」→ ("Great Church A", "(Great Hollow)")：同一建筑的不同元素变体。"""
    mm = re.match(r"^(.+?) - [^()]+?\s*(\([^()]*\))?$", name or "")
    return (mm.group(1), mm.group(2) or "") if mm else None


# 奖励字段：全部 <= 0 才算「不掉任何东西」（比 rows_no_reward 多看 rewardItemLot_1/2）
REWARD_FIELDS = ("getSoul", "rewardItemLot_1", "rewardItemLot_2",
                 "chaosMatchingRewardLotId", "itemLotId_enemy")
# 首领奖励表字段：随从/召唤物第二条判据只看这三项（卢恩与普通掉落 itemLotId_enemy 另算）
BOSS_LOT_FIELDS = ("rewardItemLot_1", "rewardItemLot_2", "chaosMatchingRewardLotId")
# 随从/召唤物只在这些场合 / 地图种类里判定（开放地图地块 m60_* 上同一张图里首领太多，比卢恩没有意义）
SUMMON_CONTEXT_ROLES = {"night", "tower", "nightlord", "field"}
SUMMON_CONTEXT_KINDS = {"nightBossPiece", "nightlordArena", "smallBasePiece"}

# notes.roleAudit 的核对样例（玩家熟知的几只；「龙」取古龙与两种飞龙）。
# 「圣树骑士」是游戏文本里罗蕾塔的称号：WeaponCaption 18100000 / 18100800 / 31060000
# 「“圣树骑士”罗蕾塔的武器」（engus「Loretta, Knight of the Haligtree」），同一段写着
# 「身为卡利亚的禁卫骑士时受赐的武器」；按 chrId 编号的掉落表 ItemLotParam_enemy 23252000（c3252）
# 放的正是罗蕾塔的战镰 18100000 与白银盾 31060000（同一编号规则：23251000 = c3251 大树守卫的
# 黄金戟 / 黄金树大盾，23250000 = c3250 龙装大树守卫的大龙爪 / 龙爪盾）。所以「圣树骑士」=
# c3252「卡利亚禁卫骑士」（NpcName 903253500）。按字面也可能被理解成大树守卫一类，作为另一种读法列在后面。
# ROLE_EXAMPLE_TEXT：上面的出处写进 notes.roleAudit.examples[].source（生成时逐条核对文本确实存在）。
ROLE_EXAMPLES = [
    ("铃珠猎人", ["Bell Bearing Hunter@3100"]),
    ("圣树骑士（“圣树骑士”罗蕾塔 = 卡利亚禁卫骑士 c3252）", ["Royal Carian Knight@3252"]),
    ("大树守卫 / 龙装大树守卫（「圣树骑士」的另一种读法）", ["Tree Sentinel@3251", "Draconic Tree Sentinel@3250"]),
    ("恶兆妖鬼", ["Morgott@2130"]),
    ("熔炉骑士", ["Crucible Knight@2500"]),
    ("龙（古龙 / 丘陵飞龙 / 飞龙）", ["Ancient Dragon@4510", "Flying Dragon@4500", "Flying Dragon@4505"]),
    ("死亡仪式鸟", ["Death Rite Bird@4980"]),
    ("黑夜骑兵", ["Night's Cavalry@3150"]),
    ("恶魔王子", ["Demon Prince@7930"]),
]


# 例子「圣树骑士」→ c3252 的出处（生成时逐条核对：文本/掉落表里确实有这些字串或物品）
#   (FMG 语言, 文本包, FMG 名, 词条 ID, 必须包含的子串) 或 ("ItemLotParam_enemy", 行号, 必须包含的物品 ID)
ROLE_EXAMPLE_SOURCES = {
    "Royal Carian Knight@3252": [
        ("zhocn", "item_dlc01", "WeaponCaption", "18100000", "“圣树骑士”罗蕾塔的武器"),
        ("engus", "item_dlc01", "WeaponCaption", "18100000", "Loretta, Knight of the Haligtree"),
        ("zhocn", "item_dlc01", "WeaponCaption", "18100000", "身为卡利亚的禁卫骑士时受赐的武器"),
        ("zhocn", "item_dlc01", "WeaponCaption", "31060000", "“圣树骑士”罗蕾塔的武器"),
        ("ItemLotParam_enemy", "23252000", ("18100000", "31060000")),
        ("ItemLotParam_enemy", "23251000", ("18080000",)),
        ("ItemLotParam_enemy", "23250000", ("23060000",)),
        ("zhocn", "item_dlc01", "NpcName", "903253500", "卡利亚禁卫骑士"),
    ],
}


def role_example_sources(raw: Path) -> dict[str, list[dict]]:
    """ROLE_EXAMPLE_SOURCES → [{table, row, note}]，逐条断言原文确实存在。"""
    wname = load_fmg(raw, "zhocn", "item_dlc01", "WeaponName")
    lots = {r["ID"]: r for r in read_param(raw, "ItemLotParam_enemy")}
    out: dict[str, list[dict]] = {}
    for gid, specs in ROLE_EXAMPLE_SOURCES.items():
        items = []
        for spec in specs:
            if spec[0] == "ItemLotParam_enemy":
                _, lot_id, want = spec
                row = lots.get(lot_id)
                got = {row[f"lotItemId0{i}"] for i in range(1, 9)} if row else set()
                assert row and set(want) <= got, f"例子出处：ItemLotParam_enemy {lot_id} 里没有 {want}"
                names = "、".join(f"{w} {wname.get(w, '')}" for w in want)
                chr_id = lot_id[1:5]
                items.append(_ev("ItemLotParam_enemy", lot_id,
                                 f"按 chrId 编号的掉落表（2 + chrId {chr_id} + 000）含 {names}"))
            else:
                lang, bnd, fmg, tid, needle = spec
                text = load_fmg(raw, lang, bnd, fmg).get(tid, "")
                assert needle in text, f"例子出处：{lang}/{fmg} {tid} 里找不到「{needle}」"
                items.append(_ev(f"{fmg}（{lang}）", tid, f"含「{needle}」"))
        out[gid] = items
    return out


def gives_nothing(row: dict) -> bool:
    return all(int(float(row[f] or 0)) <= 0 for f in REWARD_FIELDS)


def _ev(table: str, row: str, note: str) -> dict:
    return {"table": table, "row": row, "note": note}


class Placement:
    """地图放置（MSB）+ 抽选参数 → 每一行 NpcParam 的出场场合（roles）。"""

    def __init__(self, raw: Path, npc_rows: list[dict], claimed: set[int]):
        path = raw / "msb" / "MsbEnemyParts.csv"
        if not path.exists():
            raise SystemExit(f"缺少 {path}：请先运行 extract_msb.py 导出地图敌人放置"
                             "（用法见该脚本 docstring）")
        with open(path, newline="", encoding="utf-8") as f:
            parts = list(csv.DictReader(f))
        self.npc = {int(r["ID"]): r for r in npc_rows}
        self.claimed = claimed
        self.enemy_parts: dict[int, list[dict]] = defaultdict(list)
        self.dummy_parts: dict[int, list[dict]] = defaultdict(list)
        self.map_npcs: dict[str, set[int]] = defaultdict(set)
        self.parts_by_map: dict[str, list[dict]] = defaultdict(list)
        maps = set()
        for p in parts:
            maps.add(p["map"])
            self.parts_by_map[p["map"]].append(p)
            nid = int(p["npcParamId"])
            if p["partType"] == "enemy":
                self.enemy_parts[nid].append(p)
                self.map_npcs[p["map"]].add(nid)
            else:
                self.dummy_parts[nid].append(p)
        manifest = raw / "msb" / "manifest.json"
        mani = json.loads(manifest.read_text(encoding="utf-8")) if manifest.exists() else None
        self.msb_maps = mani["maps"] if mani else len(maps)
        self.msb_map_names = set(mani["perMap"]) if mani else maps
        self.msb_enemy = sum(1 for p in parts if p["partType"] == "enemy")
        self.msb_dummy = len(parts) - self.msb_enemy

        self.sbv = {int(r["ID"]): r["Name"] for r in read_param(raw, "SmallBaseMapVariationParam")}
        self.night_slots: dict[int, Counter] = defaultdict(Counter)
        for r in read_param(raw, "LotResultPlayAreaParam"):
            for f in NIGHT_SLOTS:
                v = int(r[f])
                if v > 0:
                    self.night_slots[v][f] += 1
        self.attach = {int(r["ID"]): r for r in read_param(raw, "SmallBaseAndSpotAttachPoint")}
        self.defaults: dict[int, list[int]] = defaultdict(list)
        for aid, r in sorted(self.attach.items()):
            v = int(r["defaultSmallBase"])
            if v > 0:
                self.defaults[v].append(aid)
        self.pmods: dict[int, set[int]] = defaultdict(set)
        self.pattern_rows = read_param(raw, "LotResultMapPatternFlag")
        # targetBoss（Paramdex Meta：Refs = NightBossMenuParam）= 这个地图模式属于哪位夜王的远征；每个模式唯一
        self.ptarget: dict[int, int] = {}
        self.pattern_names: dict[int, str] = {}
        for r in self.pattern_rows:
            pid, tgt = int(r["patternId"]), int(r["targetBoss"])
            self.pmods[pid].add(int(r["modifier"]))
            assert self.ptarget.setdefault(pid, tgt) == tgt, f"地图模式 {pid} 的 targetBoss 不唯一"
            self.pattern_names.setdefault(pid, r["Name"] or "")
        self.menu_names = {int(r["ID"]): r["Name"] or "" for r in read_param(raw, "NightBossMenuParam")}
        self.meteor_patterns = {pid for pid, mods in self.pmods.items() if METEOR_MODIFIER[0] in mods}
        self.lot_names = {int(r["ID"]): r["Name"] for r in read_param(raw, "ItemLotParam_enemy")}
        self.lots: dict[int, list[dict]] = defaultdict(list)
        for r in read_param(raw, "LotResultSmallBaseAndSpot"):
            self.lots[int(r["smallBaseMapId"])].append(r)
        self.mcat: dict[int, dict[int, list[int]]] = defaultdict(lambda: defaultdict(list))
        # 开放地图地块的变异刷新点：地块号 60XXYY → [{id, cat, m1, m2, m3}]（mapUnk 解码见 tile_code 的注释）
        self.tile_rows: dict[int, list[dict]] = defaultdict(list)
        for r in read_param(raw, "ChaosMatchingMutationEnemyTableParam"):
            s, rid, code = int(r["smallBaseId"]), int(r["ID"]), tile_code(r)
            if s > 0:
                assert code == 0, f"mapUnk 解码：smallBaseId {s} 的行 {rid} 应当解码成 0，实际 {code}"
                self.mcat[s][int(r["categoryId"])].append(rid)
                continue
            assert code // 10000 == 60, f"mapUnk 解码：smallBaseId = 0 的行 {rid} 解码成 {code}，不是 60XXYY"
            xx, yy = code // 100 % 100, code % 100
            m1, m2, m3 = (int(r[f"modifierMapId{i}"]) for i in (1, 2, 3))
            if m1:
                assert (rid // 10**6 % 10 + 40, rid // 10**5 % 10 + 30, rid // 10**4 % 10) == (xx, yy, m1 - 10), \
                    f"mapUnk 解码：行号 {rid} 与地块 {code} / modifierMapId1 {m1} 对不上"
            else:
                assert rid // 1000 == code, f"mapUnk 解码：行号 {rid} 与地块 {code} 对不上"
                assert 10 + GREAT_HOLLOW_VARIANT not in (m2, m3), f"通用行 {rid} 竟然单独排除了大空洞"
            self.tile_rows[code].append({"id": rid, "cat": int(r["categoryId"]), "m1": m1, "m2": m2, "m3": m3})
        self.tile_row_count = sum(len(v) for v in self.tile_rows.values())
        self._ow_cache: dict[str, tuple[str, list[dict], dict]] = {}
        self.combos: dict[int, list[int]] = defaultdict(list)
        for r in read_param(raw, "SmallBaseEnemyLotMapCombinationParam"):
            for k in ("mapId1", "mapId2", "mapId3", "mapId4"):
                v = int(r[k])
                if v > 0:
                    self.combos[v].append(int(r["ID"]))
        self.invaders = {int(r["npcParamId"]): r for r in read_param(raw, "SmallbaseInvationNpcParam")
                         if int(r["npcParamId"]) > 0}
        self.menu = (load_fmg(raw, "zhocn", "menu_dlc01", "CL_MenuText"),
                     load_fmg(raw, "engus", "menu_dlc01", "CL_MenuText"))
        self.terrain = terrain_names(raw)
        self.icons = map_icon_names(raw)
        # 标签必须真的取自游戏文本：场合 / 变异类别 / 变体说明里的「场景头目」「坑道」「封印监牢」与地形名
        field_zh = self.icons[MAP_ICONS["field"]][0]
        assert ROLE_DEFS["field"][0] == VARIANT_ZH["Field Boss"] == MUTATION_CATEGORY_ZH[120][0] == field_zh
        assert ROLE_DEFS["evergaol"][0] == self.icons[MAP_ICONS["evergaol"]][0]
        assert all(x.startswith("坑道") and "坑道" in self.icons[MAP_ICONS["mine"]][0]
                   for x in (ROLE_DEFS["mine"][0], MUTATION_CATEGORY_ZH[150][0], MUTATION_CATEGORY_ZH[151][0]))
        assert (VARIANT_ZH["Mountaintop"], VARIANT_ZH["Crater"], VARIANT_ZH["Noklateo"]) == \
            (self.terrain[1][0], self.terrain[2][0], self.terrain[5][0]), "VARIANT_ZH 的地形名与游戏文本不一致"
        assert VARIANT_ZH["Crater by fog gate"].startswith(self.terrain[2][0])
        # NpcThinkParam 0 / 1：通用占位 AI（logicId 11000、disableParam_NT = 1），开放地块辅助实体的判据之一
        think = {r["ID"]: r for r in read_param(raw, "NpcThinkParam") if r["ID"] in ("0", "1")}
        self.placeholder_think = {k for k, r in think.items() if r["logicId"] == "11000" and r["disableParam_NT"] == "1"}
        assert self.placeholder_think == {"0", "1"}, f"NpcThinkParam 0/1 不再是占位 AI：{think}"
        self.known_pieces = (set(self.sbv) | set(self.lots) | set(self.defaults)
                             | set(self.night_slots) | set(self.mcat) | set(self.combos))
        # 地图块区段：SmallBaseMapVariationParam 的行号 AA×100+BB 用到的 AA（30、32、34、37、38、40–53）
        self.piece_areas = {sid // 100 for sid in self.sbv if sid < 10000}

        # 夜王战场：放着夜王本体行（claimed chrId + 最终 Boss 档）的非地图块、非开放地块 MSB
        self.arenas: dict[str, list[int]] = {}
        for m, ids in self.map_npcs.items():
            if m.startswith("m60_") or self._piece_id(m) is not None or self._unlisted_piece(m) is not None:
                continue
            lords = sorted(i for i in ids if i // 10000 in claimed and i in self.npc
                           and 7760 <= int(self.npc[i]["multiPlayCorrectionParamId"]) < 7770)
            if lords:
                self.arenas[m] = lords
        self.maps: dict[str, dict] = {}
        self.used_maps: set[str] = set()

    # ---- 地图 → 场合

    def _piece_id(self, m: str) -> int | None:
        a, b, c, d = (int(x) for x in m[1:].split("_"))
        sid = a * 100 + b
        return sid if c == 0 and d == 0 and a != 60 and sid in self.known_pieces else None

    def _unlisted_piece(self, m: str) -> int | None:
        """地图号落在地图块区段（同 AA 段有 SmallBaseMapVariationParam 行）、却没有任何表引用的 mAA_BB_00_00。"""
        a, b, c, d = (int(x) for x in m[1:].split("_"))
        sid = a * 100 + b
        return (sid if c == 0 and d == 0 and a != 60 and a in self.piece_areas
                and sid not in self.known_pieces else None)

    def tile_variant(self, v: int) -> tuple[str, str]:
        return self.terrain.get(v, (f"变体 {v}", f"Variant {v}"))

    # ---- 开放地图地块：按该地块该地形变体的变异类别判场合

    def tile_categories(self, code: int, v: int) -> dict[int, list[int]]:
        """地块 60XXYY 在地形变体 v 下适用的变异类别 → 行号（适用规则见 tile_code 的注释）。"""
        out: dict[int, list[int]] = defaultdict(list)
        for t in self.tile_rows.get(code, ()):
            if t["m1"]:
                hit = t["m1"] == 10 + v
            else:
                hit = v != GREAT_HOLLOW_VARIANT and 10 + v not in (t["m2"], t["m3"])
            if hit:
                out[t["cat"]].append(t["id"])
        return dict(out)

    @staticmethod
    def lod_origin(parts: list[dict]) -> str | None:
        """合并显示用的大地块（m60_10_09_12 等）里 part 名带原地块前缀：「m60_43_39_10-c0100_9000」。"""
        origins = {mm.group(1) for p in parts if (mm := re.match(r"(m60_\d\d_\d\d_\d\d)-", p["partName"]))}
        return origins.pop() if len(origins) == 1 else None

    def overworld_role(self, m: str) -> tuple[str, list[dict], dict[int, list[int]]]:
        """开放地图地块 → (场合, 证据, 该变体适用的全部变异类别)。

        首领类类别含 120 → field（场景头目）；只有 150/151 → mine（坑道精英）；只有 110 → stronghold；
        都没有 → field（只表示放在开放地图上）。大地块（LOD）没有自己的刷新点，逐行按 part 名里的原地块判定。"""
        if m in self._ow_cache:
            return self._ow_cache[m]
        _, b, c, d = (int(x) for x in m[1:].split("_"))
        v = d // 10
        zh = self.tile_variant(v)[0]
        base = f"开放地图地块（地形变体 {v} = {zh}），不属于任何据点/地点地图块"
        if d % 10:
            res = ("field", [_ev("MSB", m, base + f"；这是合并显示用的大地块（LOD {d % 10}），part 名前缀标着原地块，"
                                           "逐行按原地块的变异类别判定")], {})
            self._ow_cache[m] = res
            return res
        code = 600000 + b * 100 + c
        all_cats = self.tile_categories(code, v)
        cats = {k: ids for k, ids in all_cats.items() if k in TILE_BOSS_CATEGORIES}
        rows_of = lambda ids: f"{ids[0]}" + (f" 等 {len(ids)} 行" if len(ids) > 1 else "")
        cat_line = "、".join(f"{k} {MUTATION_CATEGORY_ZH.get(k, (str(k),))[0]}（{rows_of(ids)}）"
                             for k, ids in sorted(cats.items()))
        if 120 in cats:
            role = "field"
        elif set(cats) & set(MINE_CATEGORIES):
            role = "mine"
        elif 110 in cats:
            role = "stronghold"
        else:
            role = "field"
        items: list[dict] = []
        if cats:
            tail = {"mine": "：有 Mine Elite、没有 Field Boss（120）→ 坑道精英",
                    "stronghold": "：只有 Base Boss（110）→ 据点首领"}.get(role, "：含 Field Boss（120）→ 场景头目")
            items.append(_ev("ChaosMatchingMutationEnemyTableParam", "、".join(rows_of(ids) for _, ids in sorted(cats.items())),
                             f"smallBaseId = 0 的行按 mapUnk_1..3 解码为地块 {code}（m60_{b:02d}_{c:02d}），"
                             f"适用于地形变体 {v}（{zh}）的首领类变异类别：{cat_line}{tail}"))
        msb = _ev("MSB", m, base + ("；该地块该变体的首领类变异类别：" + cat_line if cats else
                                    "；该地块该变体没有首领类变异类别（110 / 120 / 150 / 151 / 160），只表示放在开放地图上"))
        if role == "field":
            items.insert(0, msb)
        else:
            items.append(msb)
            if role == "mine":
                for nid in sorted(self.map_npcs.get(m, ())):
                    r = self.npc.get(nid)
                    lot = int(r["rewardItemLot_2"]) if r else -1
                    if lot > 0 and "(Mine" in (self.lot_names.get(lot) or ""):
                        items.append(_ev("ItemLotParam_enemy", str(lot),
                                         f"地图里的行 {nid}（Paramdex 行名 {r['Name'] or '无'}）的 rewardItemLot_2 → "
                                         f"Paramdex 行名「{self.lot_names[lot]}」"))
        res = (role, items, all_cats)
        self._ow_cache[m] = res
        return res

    def target_line(self, pattern_ids) -> str:
        """地图模式 → targetBoss（NightBossMenuParam 行号与 Paramdex 行名）分布。"""
        c = Counter(self.ptarget[int(p)] for p in pattern_ids)
        return "、".join(f"{t}「{self.menu_names.get(t, '?')}」×{n}" for t, n in sorted(c.items(), key=lambda kv: (-kv[1], kv[0])))

    def lord_menu_ids(self, mod: int) -> set[int]:
        """Raid 修饰 → 发动突袭的夜王在 NightBossMenuParam 里的行（行名「… / Gladius」；莫格（604）没有）。"""
        key = RAID_MODIFIERS[mod].split(" - ", 1)[1]
        return {i for i, n in self.menu_names.items() if n.endswith(f"/ {key}")}

    def _placeholder_uses(self, model: str, npc_id: int, limit: int = 4) -> str:
        c = Counter(self.npc[int(p["npcParamId"])]["Name"] for ps in self.parts_by_map.values() for p in ps
                    if p["partType"] == "enemy" and p["model"] == model and p["npcThinkParamId"] in self.placeholder_think
                    and int(p["npcParamId"]) != npc_id and int(p["npcParamId"]) in self.npc
                    and self.npc[int(p["npcParamId"])]["Name"])
        return "、".join(f"「{n}」" for n, _ in c.most_common(limit)) or "（无）"

    def open_map_helper(self, npc_id: int, placed: list[tuple[str, dict, str]]) -> list[dict] | None:
        """开放地块上的辅助实体：全部 part 都换了模型、npcThinkParamId 是占位 AI（0/1）。自身零奖励由调用方判定。"""
        chr_model = f"c{npc_id // 10000:04d}"
        out = []
        for m, _, part in placed:
            ps = [p for p in self.enemy_parts.get(npc_id, []) if p["map"] == m]
            if not ps or any(p["model"] == chr_model or p["npcThinkParamId"] not in self.placeholder_think for p in ps):
                return None
            models = "/".join(sorted({p["model"] for p in ps}))
            thinks = "/".join(sorted({p["npcThinkParamId"] for p in ps}))
            origin = self.lod_origin(ps)
            origin_note = ""
            if origin:
                peers = sorted((i for i in self.map_npcs.get(origin, ()) if i // 10000 == npc_id // 10000
                                and i in self.npc and int(self.npc[i]["rewardItemLot_2"]) > 0),
                               key=lambda i: (-num(self.npc[i]["getSoul"]), i))
                origin_note = f"；part 名前缀显示它原属 {origin}"
                if peers:
                    pr = self.npc[peers[0]]
                    origin_note += (f"，该地块上同 chrId 的首领行是 {peers[0]}（{pr['Name'] or '无 Paramdex 行名'}，"
                                    f"rewardItemLot_2 = {pr['rewardItemLot_2']}）")
            note = (f"{'/'.join(REWARD_FIELDS)} 全为 0 或 -1；MSB part 用的是模型 {models}（不是本行 chrId 的 {chr_model}），"
                    f"npcThinkParamId = {thinks}（NpcThinkParam 0 / 1 是 logicId 11000、disableParam_NT = 1 的通用占位 AI，"
                    f"不是首领 AI）{origin_note}；全部 MSB 里同样「{models} + 占位 AI」的 part 还用于 "
                    f"{self._placeholder_uses(models.split('/')[0], npc_id)} 等：开放地图上的辅助实体，不是可以打的首领")
            out.append({"npcId": npc_id, "msb": m, "part": part, **_ev("NpcParam", str(npc_id), note)})
        return out

    def scripted_encounter(self, npc_id: int, placed: list[tuple[str, dict, str]]) -> list[dict] | None:
        """开放地块上零奖励的敌人与带对话脚本（talkId）的实体同属一个 MSB 实体组 → 剧情遭遇（推断）。"""
        out = []
        groups_of = lambda p: {g for g in (p["entityGroupIds"] or "").split() if g not in ("0", "-1")}
        for m, info, part in placed:
            own = [p for p in self.enemy_parts.get(npc_id, []) if p["map"] == m]
            groups = set().union(*(groups_of(p) for p in own)) if own else set()
            talkers = [p for p in self.parts_by_map.get(m, []) if p["partType"] == "enemy"
                       and p["npcParamId"] != str(npc_id) and p["talkId"] not in ("", "0", "-1") and groups & groups_of(p)]
            if not talkers:
                return None
            shared = sorted(groups & set().union(*(groups_of(p) for p in talkers)))
            npcs = sorted({(p["npcParamId"], self.npc.get(int(p["npcParamId"]), {}).get("Name") or "")
                           for p in self.parts_by_map[m] if p["partType"] == "enemy"
                           and p["talkId"] not in ("", "0", "-1") and p["model"] == "c0000"})
            note = (f"{'/'.join(REWARD_FIELDS)} 全为 0 或 -1（不掉任何奖励），不是该地块变异类别里的首领"
                    f"（本图场合：{'/'.join(ROLE_DEFS[r][0] for r in info['roles'])}）；MSB part 与 {len(talkers)} 个带对话脚本"
                    f"（talkId）的实体（{talkers[0]['partName']} 等，npcParamId {talkers[0]['npcParamId']}，talkId "
                    f"{talkers[0]['talkId']}）同属实体组 {'、'.join(shared)}"
                    + (f"；同图还有 NPC {'、'.join(f'{i}（{n}）' for i, n in npcs[:2])}" if npcs else "")
                    + "：推断为剧情遭遇（地图事件脚本 EMEVD 未解析），不算场景头目")
            out.append({"npcId": npc_id, "msb": m, "part": part,
                        **_ev("MSB", f"{m} 实体组 {shared[0]}", note)})
        return out

    def _attach_summary(self, lots: list[dict], limit: int = 4) -> dict[str, int]:
        c = Counter((self.attach.get(int(l["attachId"]), {}).get("Name") or "（无行名）") for l in lots)
        return dict(sorted(c.items(), key=lambda kv: (-kv[1], kv[0]))[:limit])

    def classify(self, m: str) -> dict:
        if m in self.maps:
            return self.maps[m]
        a, b, c, d = (int(x) for x in m[1:].split("_"))
        info: dict = {"kind": "", "roles": [], "smallBaseId": None, "paramdexName": None}
        ev: dict[str, list[dict]] = {}
        sid = self._piece_id(m)
        if a == 60:
            v = d // 10
            zh, en = self.tile_variant(v)
            info["kind"] = "overworldTile"
            info["tileVariant"] = {"id": v, "zh": zh, "en": en}
            role, items, all_cats = self.overworld_role(m)
            if all_cats:
                info["mutationCategories"] = sorted(all_cats)
            if d % 10:
                info["note"] = (f"合并显示用的大地块（LOD {d % 10}）：part 名前缀标着原地块，"
                                "放在这里的行按原地块该地形变体的变异类别判定场合")
            info["roles"] = [role]
            ev[role] = items
        elif sid is not None:
            lots = self.lots.get(sid, [])
            cats = self.mcat.get(sid, {})
            info["smallBaseId"] = sid
            info["paramdexName"] = self.sbv.get(sid) or None
            info["lotRows"] = len(lots)
            if lots:
                info["attachPoints"] = self._attach_summary(lots)
            if cats:
                info["mutationCategories"] = sorted(cats)
            # 该地图块的抽选结果落在带各 Raid 修饰的地图模式里的行数（内部用：判定夜王突袭，不输出）
            info["raidPatternRows"] = {str(k): v for k, v in sorted(Counter(
                mod for l in lots for mod in self.pmods[int(l["patternId"])] if mod in RAID_MODIFIERS).items())}
            slots = self.night_slots.get(sid)
            cat_note = lambda k: (f"{cats[k][0]}" + (f" 等 {len(cats[k])} 行" if len(cats[k]) > 1 else ""))
            if slots:
                info["kind"] = "nightBossPiece"
                info["nightSlots"] = {f: slots[f] for f in NIGHT_SLOTS if slots.get(f)}
                info["roles"] = ["night"]
                ev["night"] = []
                for f in NIGHT_SLOTS:
                    if slots.get(f):
                        tid, suffix = NIGHT_SLOT_TEXT[f]
                        ev["night"].append(_ev("LotResultPlayAreaParam", f"{f} = {sid}",
                                               f"{slots[f]} 行 ·「{self.menu[0].get(tid, '')}」{suffix}"
                                               f"（CL_MenuText {tid}）"))
                tower = [l for l in lots
                         if "Tower Boss" in (self.attach.get(int(l["attachId"]), {}).get("Name") or "")]
                if tower:
                    info["roles"].append("tower")
                    floors = sorted({re.sub(r".*Tower Boss - ", "", self.attach[int(l["attachId"])]["Name"])
                                     for l in tower})
                    ev["tower"] = [_ev("LotResultSmallBaseAndSpot", f"smallBaseMapId = {sid}",
                                       f"{len(tower)} 行挂到挂点「[Great Hollow] East/West Tower Boss」"
                                       f"（{'/'.join(floors)}）")]
            elif sid not in self.sbv and sid not in self.defaults and not lots:
                info["kind"] = "inactivePiece"
            elif not lots and sid not in self.defaults and sid not in self.combos:
                info["kind"] = "inactivePiece"
            elif sid in self.defaults:
                info["kind"] = "majorBaseDefault"
                info["roles"] = ["event"]
                aids = self.defaults[sid]
                tile_names = sorted({l["Name"] for l in lots if l["Name"]})
                ev["event"] = [_ev("SmallBaseAndSpotAttachPoint", "、".join(str(x) for x in aids),
                                   f"defaultSmallBase = {sid}：大据点挂点（"
                                   f"{self.attach[aids[0]]['Name'] or '无行名'} 等）的默认地块"
                                   + (f"；另有 {len(lots)} 行抽选结果，Paramdex 行名如「{tile_names[0]}」"
                                      "（行名看是天变/陨石事件用的地块）" if tile_names else ""))]
                meteor = sum(1 for l in lots if int(l["patternId"]) in self.meteor_patterns)
                hit = sum(1 for pid in self.meteor_patterns
                          if any(int(l["patternId"]) == pid for d_sid in self.defaults
                                 for l in self.lots.get(d_sid, [])))
                ev["event"].append(_ev(
                    "LotResultMapPatternFlag", f"modifier = {METEOR_MODIFIER[0]}",
                    f"本地图块 {meteor}/{len(lots)} 行抽选结果落在带修饰 {METEOR_MODIFIER[0]}"
                    f"（{METEOR_MODIFIER[1]}，推断的 PATTERN_MODIFIER 对应）的地图模式里；"
                    f"全表 {len(self.meteor_patterns)} 个带该修饰的地图模式有 {hit} 个把大据点默认地块挂出来"))
                for nid in sorted(self.map_npcs.get(m, ())):
                    r = self.npc.get(nid)
                    lot = int(r["rewardItemLot_2"]) if r else -1
                    if r and lot > 0 and 7740 <= int(r["multiPlayCorrectionParamId"]) < 7770:
                        ev["event"].append(_ev(
                            "ItemLotParam_enemy", str(lot),
                            f"地图里的首领行 {nid}（Paramdex 行名 {r['Name'] or '无'}）的 rewardItemLot_2 → "
                            f"Paramdex 行名「{self.lot_names.get(lot) or '无'}」"))
                if cats.get(120):
                    ev["event"].append(_ev("ChaosMatchingMutationEnemyTableParam", cat_note(120),
                                           f"categoryId 120（Field Boss）、smallBaseId {sid}"))
            else:
                info["kind"] = "smallBasePiece"
                all_raid = lots and all(self.pmods[int(l["patternId"])] & set(RAID_MODIFIERS) for l in lots)
                all_horde = lots and all(HORDE_MODIFIER[0] in self.pmods[int(l["patternId"])] for l in lots)
                merchant = sum(1 for l in lots if int(l["modifier"]) == MERCHANT_MODIFIER[0])
                if cats.get(160) or sid in self.combos:
                    info["roles"] = ["evergaol"]
                    ev["evergaol"] = []
                    if cats.get(160):
                        ev["evergaol"].append(_ev("ChaosMatchingMutationEnemyTableParam", cat_note(160),
                                                  f"categoryId 160（Evergaol Boss）、smallBaseId {sid}"))
                    if sid in self.combos:
                        ev["evergaol"].append(_ev("SmallBaseEnemyLotMapCombinationParam",
                                                  "、".join(str(x) for x in self.combos[sid][:5]),
                                                  f"Evergaol 组合行的 mapId 引用 {sid}"))
                elif all_raid:
                    mods = "、".join(f"{k}（{RAID_MODIFIERS[int(k)]}）×{v}" for k, v in info["raidPatternRows"].items())
                    info["roles"] = ["raid"]
                    ev["raid"] = [_ev("LotResultSmallBaseAndSpot", f"smallBaseMapId = {sid}",
                                      f"{len(lots)} 行全部落在带 Raid 修饰的地图模式里"
                                      f"（LotResultMapPatternFlag.modifier {mods}）")]
                    lord_ids = set().union(*(self.lord_menu_ids(int(k)) for k in info["raidPatternRows"]))
                    targets = {self.ptarget[int(l["patternId"])] for l in lots}
                    assert not targets & lord_ids, f"突袭地图块 {sid} 的地图模式指向了发动突袭的夜王本人：{targets & lord_ids}"
                    own_note = (f"，从不指向发动突袭的夜王本人的远征（NightBossMenuParam {'/'.join(map(str, sorted(lord_ids)))}）"
                                if lord_ids else "（莫格不是夜王，NightBossMenuParam 里没有他的远征）")
                    ev["raid"].append(_ev("LotResultMapPatternFlag", "targetBoss",
                                          f"这 {len(lots)} 行所在地图模式的 targetBoss（Paramdex Meta：Refs = NightBossMenuParam，"
                                          f"即本局远征的夜王）：{self.target_line(l['patternId'] for l in lots)}"
                                          f"{own_note}——突袭是闯进别的夜王的远征"))
                elif all_horde:
                    info["roles"] = ["event"]
                    ev["event"] = [_ev("LotResultSmallBaseAndSpot", f"smallBaseMapId = {sid}",
                                       f"{len(lots)} 行全部落在带修饰 {HORDE_MODIFIER[0]}"
                                       f"（{HORDE_MODIFIER[1]}）的地图模式里：黑夜势力倾巢而出")]
                elif merchant * 2 > len(lots):
                    info["roles"] = ["event"]
                    ev["event"] = [_ev("LotResultSmallBaseAndSpot", f"smallBaseMapId = {sid}",
                                       f"{merchant}/{len(lots)} 行自带 modifier {MERCHANT_MODIFIER[0]}"
                                       f"（{MERCHANT_MODIFIER[1]}）")]
                elif cats.get(120):
                    info["roles"] = ["field"]
                    ev["field"] = [_ev("ChaosMatchingMutationEnemyTableParam", cat_note(120),
                                       f"categoryId 120（Field Boss）、smallBaseId {sid}"),
                                   _ev("LotResultSmallBaseAndSpot", f"smallBaseMapId = {sid}",
                                       f"{len(lots)} 行抽选结果（挂点分布见 attachPoints）")]
                else:
                    info["roles"] = ["stronghold"]
                    ev["stronghold"] = [_ev("SmallBaseMapVariationParam", str(sid),
                                            self.sbv.get(sid) or "（无 Paramdex 行名）")]
                    if cats:
                        cs = "、".join(f"{k} {MUTATION_CATEGORY_ZH.get(k, ('（Paramdex 枚举未收录）',))[0]}"
                                      for k in sorted(cats))
                        ev["stronghold"].append(_ev("ChaosMatchingMutationEnemyTableParam",
                                                    "、".join(cat_note(k) for k in sorted(cats)),
                                                    f"smallBaseId {sid} 的变异类别：{cs}（没有 120 / 160）"))
                    ev["stronghold"].append(_ev("LotResultSmallBaseAndSpot", f"smallBaseMapId = {sid}",
                                                f"{len(lots)} 行抽选结果（挂点分布见 attachPoints）"))
            if info["kind"] == "inactivePiece":
                info["note"] = ("该地图块没有被 LotResultPlayAreaParam / LotResultSmallBaseAndSpot / "
                                "SmallBaseAndSpotAttachPoint.defaultSmallBase / "
                                "SmallBaseEnemyLotMapCombinationParam 引用，本版本不会出现在远征里")
        elif self._unlisted_piece(m) is not None:
            usid = self._unlisted_piece(m)
            info["kind"] = "inactivePiece"
            info["smallBaseId"] = usid
            info["note"] = (f"地图号落在地图块区段（SmallBaseMapVariationParam 有 {a}xx 段的行），但该表没有 {usid} "
                            "这一行，LotResultPlayAreaParam / LotResultSmallBaseAndSpot.smallBaseMapId / "
                            "SmallBaseAndSpotAttachPoint.defaultSmallBase / ChaosMatchingMutationEnemyTableParam / "
                            "SmallBaseEnemyLotMapCombinationParam 也都没有引用：未启用的地图块，本版本不会出现在远征里")
        elif m in self.arenas:
            lords = self.arenas[m]
            info["kind"] = "nightlordArena"
            info["roles"] = ["nightlord"]
            info["nightlordRows"] = lords
            ev["nightlord"] = [_ev("MSB", m, f"放着夜王本体行 {'、'.join(str(x) for x in lords[:3])}"
                                             f"{' 等' if len(lords) > 3 else ''}（最终 Boss 档 7760–7769），"
                                             "且不是任何据点/地点地图块")]
        else:
            info["kind"] = "otherMap"
            info["roles"] = ["other"]
            ev["other"] = [_ev("MSB", m, "没有任何抽选表引用的地图（非远征地图块/开放地块），也不是夜王战场")]
        info["evidence"] = ev
        self.maps[m] = info
        return info

    # ---- 行 → 场合

    def lord_raid_modifier(self, npc_id: int) -> int | None:
        """夜王本体行 → 它自己的 Raid 修饰（NIGHTLORD_CHRS 的键与 PATTERN_MODIFIER「Raid - 键」对上）。"""
        chr_id = npc_id // 10000
        for key, chrs in NIGHTLORD_CHRS.items():
            if chr_id in chrs:
                return next((mod for mod, name in RAID_MODIFIERS.items() if name == f"Raid - {key}"), None)
        return None

    def _peer(self, m: str, npc_id: int) -> int | None:
        """同图里掉奖励的首领行（不同 chrId、威胁档 7740–7769）。"""
        cands = [i for i in self.map_npcs.get(m, ()) if i // 10000 != npc_id // 10000 and i in self.npc
                 and 7740 <= int(self.npc[i]["multiPlayCorrectionParamId"]) < 7770
                 and not gives_nothing(self.npc[i])]
        # 优先取带首领奖励表（rewardItemLot_2）的那行，其次卢恩最多的，避免挑到前哨小怪
        return max(cands, key=lambda i: (int(self.npc[i]["rewardItemLot_2"]) > 0,
                                         num(self.npc[i]["getSoul"]), -i)) if cands else None

    def _boss_peer(self, m: str, npc_id: int) -> int | None:
        """同图里带首领奖励表（rewardItemLot_2 > 0）、威胁档 7740–7769 的另一行（可以同 chrId），卢恩最多者。"""
        cands = [i for i in self.map_npcs.get(m, ()) if i != npc_id and i in self.npc
                 and 7740 <= int(self.npc[i]["multiPlayCorrectionParamId"]) < 7770
                 and int(self.npc[i]["rewardItemLot_2"]) > 0]
        return max(cands, key=lambda i: (num(self.npc[i]["getSoul"]), -i)) if cands else None

    def _helper_hints(self, m: str, npc_id: int, peer: int) -> list[str]:
        """MSB 里能看出「附属实体」的旁证：换了模型、没有 AI、与首领 part 同组。"""
        own = [p for p in self.enemy_parts.get(npc_id, []) if p["map"] == m]
        boss = [p for p in self.enemy_parts.get(peer, []) if p["map"] == m]
        hints = []
        chr_model = f"c{npc_id // 10000:04d}"
        other_models = sorted({p["model"] for p in own if p["model"] != chr_model})
        if other_models:
            hints.append(f"MSB part 用的是模型 {'/'.join(other_models)}（不是本行 chrId 的 {chr_model}）")
        if own and all(p["npcThinkParamId"] in ("0", "-1", "") for p in own):
            hints.append("MSB part 的 npcThinkParamId = 0（没有 AI）")
        groups = lambda ps: {g for p in ps for g in (p["entityGroupIds"] or "").split() if g not in ("0", "-1")}
        common = sorted(groups(own) & groups(boss))
        if common:
            hints.append(f"与首领行 {peer} 的 part 共用 entityGroupId {'、'.join(common)}（同组实体，如坐骑与骑手）")
        return hints

    def row_roles(self, npc_id: int, lord: bool) -> dict[str, list[dict]]:
        by_map: dict[str, list[dict]] = defaultdict(list)
        for p in self.enemy_parts.get(npc_id, []):
            by_map[p["map"]].append(p)
        ev: dict[str, list[dict]] = {}
        inactive: list[str] = []
        placed: list[tuple[str, dict, str]] = []
        lord_strongholds: list[tuple[str, dict, str, int]] = []   # 自己的抽选里没有本夜王 Raid 修饰的据点
        for m in sorted(by_map):
            ps = by_map[m]
            info = self.classify(m)
            self.used_maps.add(m)
            if not info["roles"]:
                inactive.append(m)
                continue
            ent = next((p["entityId"] for p in ps if p["entityId"] not in ("0", "")), "")
            part = ps[0]["partName"] + (f" 等 {len(ps)} 个" if len(ps) > 1 else "") + \
                (f"（entityId {ent}）" if ent else "")
            placed.append((m, info, part))
            roles = list(info["roles"])
            basis: dict[str, dict] = {r: info["evidence"][r][0] for r in roles}
            if info["kind"] == "overworldTile" and not lord:
                origin = self.lod_origin(ps) if int(m[-2:]) % 10 else None
                if origin:
                    # 大地块（LOD）里的 part：按 part 名前缀里的原地块判定
                    role, items, _ = self.overworld_role(origin)
                    roles = [role]
                    basis = {role: dict(items[0], note=f"大地块 {m} 里的 part，名字前缀显示它原属 {origin}："
                                                       + items[0]["note"])}
                row = self.npc[npc_id]
                lot = int(row["rewardItemLot_2"])
                if roles == ["field"] and lot <= 0:
                    basis = {"field": dict(basis["field"], note=basis["field"]["note"] +
                                           "；本行不带首领奖励表（rewardItemLot_2 ≤ 0），只说明它和场景头目放在同一块开放地图上，"
                                           "未必就是地图上标「场景头目」图标的那只")}
                elif roles == ["mine"]:
                    bosses = sorted(i for i in self.map_npcs.get(m, ()) if i in self.npc
                                    and 7740 <= int(self.npc[i]["multiPlayCorrectionParamId"]) < 7770
                                    and int(self.npc[i]["rewardItemLot_2"]) > 0)
                    only = ("；它是这块地形变体上唯一带首领奖励表的首领档（7740–7769）行" if bosses == [npc_id] else
                            f"；同图带首领奖励表的首领档行：{'、'.join(map(str, bosses))}")
                    basis = {"mine": dict(basis["mine"], note=basis["mine"]["note"] +
                                          f"；本行 rewardItemLot_2 = {lot}「{self.lot_names.get(lot) or '无 Paramdex 行名'}」"
                                          f"、chaosMatchingRewardLotId = {row['chaosMatchingRewardLotId']}{only}")}
            if lord and info["kind"] not in ("nightlordArena", "otherMap"):
                # 夜王本体行出现在夜王战场以外：突袭（突袭地图块 / 带「本夜王」Raid 修饰的据点）或其它事件
                own = self.lord_raid_modifier(npc_id)
                own_rows = (info.get("raidPatternRows") or {}).get(str(own), 0) if own else 0
                if "raid" in roles or "event" in roles:
                    roles = ["raid"] if "raid" in roles else ["event"]
                elif "stronghold" in roles and own_rows:
                    roles = ["raid"]
                    pids = [l["patternId"] for l in self.lots.get(info["smallBaseId"], [])
                            if own in self.pmods[int(l["patternId"])]]
                    lord_ids = self.lord_menu_ids(own)
                    assert not {self.ptarget[int(p)] for p in pids} & lord_ids, \
                        f"{npc_id}：带 {own} 的地图模式指向了发动突袭的夜王本人"
                    basis = {"raid": _ev("LotResultSmallBaseAndSpot", f"smallBaseMapId = {info['smallBaseId']}",
                                         f"夜王本体行放在据点地图块里；该地图块有 {own_rows} 行抽选结果落在带修饰 "
                                         f"{own}（{RAID_MODIFIERS[own]}）的地图模式里：夜王在据点突袭；这 {own_rows} 行所在地图模式的 "
                                         f"targetBoss（Refs = NightBossMenuParam，本局远征的夜王）：{self.target_line(pids)}，"
                                         f"从不是本夜王自己的远征（{'/'.join(map(str, sorted(lord_ids)))}）")}
                elif "stronghold" in roles and own:
                    lord_strongholds.append((m, info, part, own))
                    continue
                else:
                    roles = ["event"]
                    basis = {"event": _ev("MSB", m, "夜王本体行出现在夜王战场与突袭地图块以外"
                                                    f"（此图场合：{'/'.join(ROLE_DEFS[r][0] for r in info['roles'])}）："
                                                    "持秤商人等事件现身")}
            if "night" in roles and int(self.npc[npc_id]["multiPlayCorrectionParamId"]) == PRELUDE_SCALING_ID:
                # 夜晚首领登场前的前哨：同一张地图块，但不是首领本体。地图块也挂到大空洞高塔时，
                # 前哨会随地图块一起出现在高塔里，但它不是高塔首领 → 不标 tower，只在证据里注明
                tower_note = ""
                if "tower" in roles:
                    tower_note = (f"；该地图块也挂到大空洞高塔（{basis['tower']['note']}），"
                                  "前哨随地图块一起出现在高塔里，但不是高塔首领，不另标 tower")
                roles = ["prelude" if r == "night" else r for r in roles if r != "tower"]
                basis = dict(basis, prelude=_ev(
                    "NpcParam", str(npc_id),
                    f"multiPlayCorrectionParamId = {PRELUDE_SCALING_ID}（前哨档位）；所在夜晚首领地图块 "
                    f"{info['smallBaseId']}：{basis['night']['row']} {basis['night']['note']}{tower_note}"))
            if npc_id in self.invaders and "stronghold" in roles:
                # 黑夜入侵者在据点地图块里预先放好的出生位置：归到 invader，不当成据点首领
                roles = ["invader" if r == "stronghold" else r for r in roles]
                basis = dict(basis, invader=_ev("SmallBaseMapVariationParam", str(info["smallBaseId"]),
                                                f"{info['paramdexName'] or '据点地图块'}：入侵者在据点里的出生位置"
                                                "（该行同时被 SmallbaseInvationNpcParam 引用）"))
            for r in roles:
                ev.setdefault(r, []).append({"npcId": npc_id, "msb": m, "part": part, **basis[r]})
        raid_maps = len({e["msb"] for e in ev.get("raid", [])})
        raid_sids = {self.maps[e["msb"]]["smallBaseId"] for e in ev.get("raid", []) if e["msb"]} - {None}
        for m, info, part, own in lord_strongholds:
            # 同一行夜王突袭在别的据点地图块里由带本夜王 Raid 修饰的地图模式放出时，按同一突袭计——这是推断：
            # 本地图块自己的抽选结果里没有这个修饰，MSB 里预放的这行在这里会不会被启用要看 EMEVD
            if raid_maps:
                sid = info["smallBaseId"]
                fam = piece_family(self.sbv.get(sid, ""))
                sibs = sorted(s for s in raid_sids if fam and piece_family(self.sbv.get(s, "")) == fam)
                sib_note = ""
                if sibs:
                    pids = sorted({int(l["patternId"]) for s in sibs for l in self.lots.get(s, [])
                                   if own in self.pmods[int(l["patternId"])]})
                    sib_note = (f"；同一建筑的另一元素变体 {'、'.join(f'{s}「{self.sbv[s]}」' for s in sibs)}的 MSB 也放着这一行，"
                                f"而且有抽选结果落在带该修饰的地图模式 {'、'.join(f'{p}「{self.pattern_names[p]}」' for p in pids[:3])}"
                                f"（按模式计的 targetBoss：{self.target_line(pids)}）里")
                basis = _ev("SmallBaseMapVariationParam", str(sid),
                            f"{info['paramdexName'] or '据点地图块'}：夜王本体行预放在这里，但本地图块 "
                            f"{len(self.lots.get(sid, []))} 行抽选结果没有一行落在带修饰 {own}（{RAID_MODIFIERS[own]}）的"
                            f"地图模式里（参数表上看它不会在这次突袭里被抽到）{sib_note}；同一行在其它 {raid_maps} 张地图块里"
                            "由带该修饰的地图模式放出。这里按同一突袭计是**推断**：MSB 里预放的这一行在本地图块会不会被启用，"
                            "要看地图事件脚本 EMEVD（本数据集没有解析）")
                ev.setdefault("raid", []).append({"npcId": npc_id, "msb": m, "part": part, **basis})
            else:
                basis = _ev("MSB", m, "夜王本体行放在据点地图块里，但找不到带本夜王 Raid 修饰的抽选结果")
                ev.setdefault("event", []).append({"npcId": npc_id, "msb": m, "part": part, **basis})
        if npc_id in self.invaders:
            inv = self.invaders[npc_id]
            ev.setdefault("invader", []).insert(0, {
                "npcId": npc_id, "msb": None, "part": "",
                **_ev("SmallbaseInvationNpcParam", inv["ID"],
                      f"npcParamId = {npc_id}（Paramdex 行名 {inv['Name'] or '无'}）")})
        # 随从/召唤物：首领战地图块（夜晚首领 / 高塔 / 夜王战场 / 场景头目地图块，不含开放地块）里，
        # ① 自身零奖励、同图有掉奖励的首领；或 ② 不带首领奖励表、卢恩 ≤ 同图首领行的 SUMMON_SOUL_RATIO
        # （坐骑、辅助实体：送葬马 50 卢恩 / 骑手 1350，贪食魔龙的 c2150 辅助实体 80 / 3200）
        row = self.npc[npc_id]
        if (not lord and ev and set(ev) <= SUMMON_CONTEXT_ROLES
                and all(info["kind"] in SUMMON_CONTEXT_KINDS for _, info, _ in placed)):
            ctx = "/".join(ROLE_DEFS[r][0] for r in ROLE_ORDER if r in ev)
            notes = None
            if gives_nothing(row):
                notes = []
                for m, info, part in placed:
                    if info["kind"] == "nightlordArena":
                        notes.append((m, part, f"夜王战场，同图夜王本体行 {info['nightlordRows'][0]}"))
                        continue
                    peer = self._peer(m, npc_id)
                    if peer is None:
                        notes = None
                        break
                    notes.append((m, part, f"同图掉奖励的首领行 {peer}"))
                if notes:
                    notes = [(m, part, f"{'/'.join(REWARD_FIELDS)} 全为 0 或 -1；{peer_note}；登场场合：{ctx}")
                             for m, part, peer_note in notes]
            if not notes and all(int(float(row[f] or 0)) <= 0 for f in BOSS_LOT_FIELDS):
                notes = []
                soul = num(row["getSoul"])
                for m, info, part in placed:
                    peer = self._boss_peer(m, npc_id) if info["kind"] != "nightlordArena" else None
                    psoul = num(self.npc[peer]["getSoul"]) if peer is not None else 0
                    if peer is None or psoul <= 0 or soul > psoul * SUMMON_SOUL_RATIO:
                        notes = None
                        break
                    hints = self._helper_hints(m, npc_id, peer)
                    notes.append((m, part,
                                  f"{'/'.join(BOSS_LOT_FIELDS)} 全为 0 或 -1（不带首领奖励表）；"
                                  f"卢恩 {soul} 只有同图首领行 {peer}（卢恩 {psoul}，"
                                  f"rewardItemLot_2 = {self.npc[peer]['rewardItemLot_2']}）的 "
                                  f"{soul / psoul * 100:.1f}%（≤ {SUMMON_SOUL_RATIO * 100:g}%）"
                                  + "".join(f"；{h}" for h in hints) + f"；登场场合：{ctx}"))
            if notes:
                ev = {"summon": [{"npcId": npc_id, "msb": m, "part": part, **_ev("NpcParam", str(npc_id), note)}
                                 for m, part, note in notes]}
        ow = [(m, info, part) for m, info, part in placed if info["kind"] == "overworldTile"]
        if (not lord and ow and len(ow) == len(placed) and npc_id not in self.invaders
                and set(ev) <= {"field", "mine", "stronghold"} and gives_nothing(row)):
            helper = self.open_map_helper(npc_id, ow)
            scripted = None if helper else self.scripted_encounter(npc_id, ow)
            if helper:
                ev = {"summon": helper}
            elif scripted:
                ev = {"event": scripted}
        if not ev:
            note = "MSB Enemy part 与 SmallbaseInvationNpcParam 均未引用"
            if inactive:
                note += f"；只在未启用的地图块 {'、'.join(inactive)}"
            dummies = sorted({p["map"] for p in self.dummy_parts.get(npc_id, [])})
            if dummies:
                note += (f"；DummyEnemy {'、'.join(dummies[:3])}"
                         f"{' 等' if len(dummies) > 3 else ''}（不计）")
            ev["unplaced"] = [{"npcId": npc_id, "msb": None, "part": "", **_ev("MSB", "—", note)}]
        return ev

    # ---- 挂到产物上

    def annotate_rows(self, rows: list[dict], lord: bool) -> None:
        for v in rows:
            evid: dict[str, list[dict]] = {}
            row_roles: dict[str, list[str]] = {}
            for nid in v["npcIds"]:
                ev = self.row_roles(nid, lord)
                row_roles[str(nid)] = [r for r in ROLE_ORDER if r in ev]
                for r, items in ev.items():
                    evid.setdefault(r, []).extend(items)
            v["roles"] = [r for r in ROLE_ORDER if r in evid]
            v["roleEvidence"] = {r: evid[r] for r in v["roles"]}
            v["rowRoles"] = row_roles

    @staticmethod
    def annotate_group(group: dict, rows: list[dict]) -> None:
        group["roles"] = [r for r in ROLE_ORDER if any(r in v["roles"] for v in rows)]
        group["roleVariants"] = {r: [v["npcId"] for v in rows if r in v["roles"]] for r in group["roles"]}

    def annotate(self, nightlords: list[dict], night_bosses: list[dict]) -> None:
        for e in nightlords:
            self.annotate_rows(e["fights"], lord=True)
            self.annotate_group(e, e["fights"])
        for b in night_bosses:
            self.annotate_rows(b["variants"], lord=False)
            self.annotate_group(b, b["variants"])

    def placement_maps(self) -> dict[str, dict]:
        return {m: {k: v for k, v in self.maps[m].items() if k != "raidPatternRows"}
                for m in sorted(self.used_maps)}


def role_names() -> dict[str, dict]:
    return {k: {"zh": zh, "en": en, "description": desc} for k, (zh, en, desc) in ROLE_DEFS.items()}


def role_summary(nightlords: list[dict], night_bosses: list[dict]) -> tuple[dict, dict]:
    """roleSummary（nightBosses 各场合的组数）+ roleSummaryDetail（组/变体/原始行/夜王条目/战斗行）。"""
    summary = {r: sum(1 for b in night_bosses if r in b["roles"]) for r in ROLE_ORDER}
    detail = {}
    for r in ROLE_ORDER:
        detail[r] = {
            "groups": summary[r],
            "variants": sum(1 for b in night_bosses for v in b["variants"] if r in v["roles"]),
            "rows": sum(1 for b in night_bosses for v in b["variants"]
                        for rr in v["rowRoles"].values() if r in rr),
            "nightlords": sum(1 for e in nightlords if r in e["roles"]),
            "fights": sum(1 for e in nightlords for f in e["fights"] if r in f["roles"]),
            "fightRows": sum(1 for e in nightlords for f in e["fights"]
                             for rr in f["rowRoles"].values() if r in rr),
        }
    return summary, detail


def _roles_zh(roles: list[str]) -> str:
    return "/".join(ROLE_DEFS[r][0] for r in roles) or "（无）"


def build_role_audit(night_bosses: list[dict], placement: Placement,
                     sources: dict[str, list[dict]] | None = None) -> dict:
    """tier（缩放档位名）与 roles（实际出场场合）的对照，以及玩家熟知例子（ROLE_EXAMPLES）的核对。"""
    day_roles = ["field", "stronghold", "mine", "evergaol", "tower"]
    mismatches = []
    tier_night_no_night = tier_field_has_night = 0
    tier_night_only_day = 0
    breakdown: Counter = Counter()
    for b in night_bosses:
        kinds = []
        if b["tier"] == "night" and "night" not in b["roles"]:
            kinds.append("tierNightButNeverNightBoss")
            tier_night_no_night += 1
            if set(b["roles"]) & set(day_roles):
                tier_night_only_day += 1
            else:
                breakdown[_roles_zh([r for r in b["roles"] if r != "unplaced"]) if b["roles"] != ["unplaced"]
                          else "未放置"] += 1
        if b["tier"] == "field" and "night" in b["roles"]:
            kinds.append("tierFieldButNightBoss")
            tier_field_has_night += 1
        rows = []
        for v in b["variants"]:
            bad = (v["threat"] == "night") != ("night" in v["roles"])
            if bad and set(v["roles"]) != {"unplaced"}:
                rows.append({"npcId": v["npcId"], "npcIds": v["npcIds"], "threat": v["threat"],
                             "scalingId": v["scalingId"], "roles": v["roles"],
                             "msb": sorted({e["msb"] for es in v["roleEvidence"].values()
                                            for e in es if e["msb"]})})
        if kinds or rows:
            if not kinds:
                kinds.append("variantThreatMismatch")
            mismatches.append({"id": b["id"], "nameZh": b["nameZh"], "nameEn": b["nameEn"],
                               "tier": b["tier"], "tiers": b["tiers"], "roles": b["roles"],
                               "kinds": kinds, "variants": rows})

    v_all = [v for b in night_bosses for v in b["variants"]]
    v_night_threat_not_night = sum(1 for v in v_all if v["threat"] == "night" and "night" not in v["roles"]
                                   and set(v["roles"]) != {"unplaced"})
    v_field_threat_night = sum(1 for v in v_all if v["threat"] == "field" and "night" in v["roles"])
    v_unplaced = sum(1 for v in v_all if v["roles"] == ["unplaced"])
    mixed = sum(1 for v in v_all if len({tuple(x) for x in v["rowRoles"].values()}) > 1)
    night_groups = [b for b in night_bosses if b["tier"] == "night"]

    summary = [
        f"v3 的 tier 只看 multiPlayCorrectionParamId 的档位名：{len(night_groups)} 组 tier=night、"
        f"{len(night_bosses) - len(night_groups)} 组 tier=field。按地图 MSB + 抽选参数重算出场场合后："
        f"tier=night 的 {len(night_groups)} 组里有 {tier_night_no_night} 组根本不会作为守夜首领出场"
        f"（其中 {tier_night_only_day} 组在{_roles_zh(day_roles)}出现；其余 "
        + "、".join(f"{k} {v} 组" for k, v in sorted(breakdown.items(), key=lambda kv: (-kv[1], kv[0])))
        + "）；"
        f"反过来 tier=field 却确实会当守夜首领的有 {tier_field_has_night} 组。",
        f"变体粒度：threat=night 但实际不是守夜首领的变体 {v_night_threat_not_night} 个（不含整行未放置的），"
        f"threat=field 却是守夜首领的变体 {v_field_threat_night} 个；"
        f"整条变体都未放置（roles = [unplaced]）的 {v_unplaced} 个；"
        f"合并进同一变体、但各原始行场合不同的变体 {mixed} 个（看 rowRoles）。",
        "原因：Night Boss Threat（7750–7759）只是「缩放档位」的 Paramdex 行名，场景头目地图块里的行"
        "（如 31000010 铃珠猎人野外版、32510020 大树守卫野外版、45000010 丘陵飞龙野外版）同样挂 7753；"
        "而熔炉骑士/王室幽魂/亚人女王等的守夜行挂的是 Field Boss Threat（7745/7746）。"
        "tier / tiers 按约定保留原值不动，页面要按场合分组请改读 roles。",
        f"判定依据：{placement.msb_maps} 张地图 MSB 的 {placement.msb_enemy} 个 Enemy part"
        f"（另有 {placement.msb_dummy} 个 DummyEnemy 不计），地图块 ↔ 场合由 LotResultPlayAreaParam / "
        "LotResultSmallBaseAndSpot / SmallBaseAndSpotAttachPoint / ChaosMatchingMutationEnemyTableParam / "
        "LotResultMapPatternFlag 决定，每个变体的 roleEvidence 与顶层 placementMaps 给出逐表逐行出处。",
    ]

    by_id = {b["id"]: b for b in night_bosses}
    examples = []
    for title, ids in ROLE_EXAMPLES:
        for gid in ids:
            b = by_id.get(gid)
            if b is None:
                examples.append({"example": title, "id": gid, "missing": True})
                continue
            rows = []
            for v in b["variants"]:
                for nid in v["npcIds"]:
                    rr = v["rowRoles"][str(nid)]
                    maps = sorted({e["msb"] for es in v["roleEvidence"].values() for e in es
                                   if e["npcId"] == nid and e["msb"]})
                    rows.append({"npcId": nid, "variantNpcId": v["npcId"], "threat": v["threat"],
                                 "scalingId": v["scalingId"], "roles": rr, "msb": maps})
            line_parts = []
            for r in ROLE_ORDER:
                ids_r = [x["npcId"] for x in rows if r in x["roles"]]
                if ids_r and r != "unplaced":
                    line_parts.append(f"{ROLE_DEFS[r][0]} " + "、".join(str(i) for i in ids_r[:6])
                                      + (" 等" if len(ids_r) > 6 else ""))
            n_unplaced = sum(1 for x in rows if x["roles"] == ["unplaced"])
            tail = ""
            if b["tier"] == "night" and "night" not in b["roles"]:
                tail = "；**不会**作为守夜首领出场（tier=night 只是缩放档位名）"
            elif b["tier"] == "field" and "night" in b["roles"]:
                tail = "；tier=field，但确实会当守夜首领"
            verdict = (f"{title} · {b['nameZh'] or b['nameEn']}（{gid}，tier={b['tier']}）："
                       + "；".join(line_parts)
                       + (f"；另 {n_unplaced} 行未放置" if n_unplaced else "") + tail)
            ex = {"example": title, "id": gid, "nameZh": b["nameZh"], "tier": b["tier"],
                  "roles": b["roles"], "verdict": verdict, "rows": rows}
            if sources and gid in sources:
                ex["source"] = sources[gid]
            examples.append(ex)
    return {"summary": summary, "mismatches": mismatches, "examples": examples}


def measure_roles(placement: "Placement", role_counts: dict, role_detail: dict,
                  placement_maps: dict, night_bosses: list[dict], nightlords: list[dict]) -> dict:
    """caveats【场合】几条要引用的数字，全部从产物实测；文案点名的例子在这里断言成立。"""
    m: dict = {}
    m["roleMsbMaps"] = placement.msb_maps
    m["roleMsbEnemy"] = placement.msb_enemy
    m["roleMsbDummy"] = placement.msb_dummy
    m["rolePlacementMaps"] = len(placement_maps)
    m["roleGroupLine"] = "、".join(f"{ROLE_DEFS[r][0]} {n}" for r, n in role_counts.items() if n)
    tier_night = [b for b in night_bosses if b["tier"] == "night"]
    m["roleTierNightGroups"] = len(tier_night)
    m["roleTierNightNoNight"] = sum(1 for b in tier_night if "night" not in b["roles"])
    m["roleTierFieldNight"] = sum(1 for b in night_bosses if b["tier"] == "field" and "night" in b["roles"])
    v_all = [v for b in night_bosses for v in b["variants"]]
    m["roleMixedVariants"] = sum(1 for v in v_all if len({tuple(x) for x in v["rowRoles"].values()}) > 1)
    m["roleRowsUnplaced"] = role_detail["unplaced"]["rows"]
    m["roleVariantsUnplaced"] = sum(1 for v in v_all if v["roles"] == ["unplaced"])

    lord_raid_maps, lord_raid_rows, lord_event_rows, lord_event_maps = set(), set(), set(), set()
    for e in nightlords:
        for f in e["fights"]:
            for ev in f["roleEvidence"].get("raid", []):
                info = placement_maps.get(ev["msb"] or "", {})
                if info.get("kind") == "smallBasePiece" and "raid" not in info.get("roles", []):
                    lord_raid_maps.add(ev["msb"])
                    lord_raid_rows.add(ev["npcId"])
            for ev in f["roleEvidence"].get("event", []):
                lord_event_rows.add(ev["npcId"])
                lord_event_maps.add(ev["msb"])
    m["roleLordRaidStrongholdMaps"] = len(lord_raid_maps)
    m["roleLordRaidStrongholdRows"] = "、".join(str(x) for x in sorted(lord_raid_rows)) or "（无）"
    m["roleLordEventRows"] = "、".join(str(x) for x in sorted(lord_event_rows)) or "（无）"
    m["roleLordEventMaps"] = "、".join(
        f"{x}（{placement_maps[x]['paramdexName'] or placement_maps[x].get('tileVariant', {}).get('zh', '')}）"
        for x in sorted(lord_event_maps)) or "（无）"
    m["roleArenaMaps"] = "、".join(sorted(placement.arenas))
    unplaced_rows = [int(nid) for v in v_all for nid, rr in v["rowRoles"].items() if rr == ["unplaced"]]
    m["roleUnplacedBaseTier"] = sum(1 for nid in unplaced_rows
                                    if placement.npc[nid]["multiPlayCorrectionParamId"] in ("7740", "7750"))
    m["rolePreludeRows"] = "、".join(sorted({str(e["npcId"]) for v in v_all
                                              for e in v["roleEvidence"].get("prelude", [])})) or "（无）"
    m["roleInvaderSpawnMaps"] = len({e["msb"] for v in v_all for e in v["roleEvidence"].get("invader", [])
                                     if e["msb"]})
    # 前哨所在地图块也挂到大空洞高塔的行（这些行只标 prelude，不标 tower）
    m["rolePreludeTowerRows"] = "、".join(sorted({str(e["npcId"]) for v in v_all
                                                   for e in v["roleEvidence"].get("prelude", [])
                                                   if "tower" in placement_maps.get(e["msb"] or "", {}).get("roles", [])})) or "（无）"
    m["roleTowerGroups"] = role_counts["tower"]
    # 随从/召唤物按第二条判据（不带首领奖励表、卢恩 ≤ 5%）判出来的行
    ratio_rows = sorted({e["npcId"] for v in v_all for e in v["roleEvidence"].get("summon", [])
                         if "不带首领奖励表" in e["note"]})
    m["roleSummonRatioRows"] = "、".join(
        f"{nid}（{placement.npc[nid]['Name'] or '无 Paramdex 行名'}，卢恩 {num(placement.npc[nid]['getSoul'])}）"
        for nid in ratio_rows) or "（无）"
    m["roleSummonRatio"] = f"{SUMMON_SOUL_RATIO * 100:g}%"
    # 地图号在地图块区段、却没有任何表引用的地图（按未启用地图块处理）
    unlisted = sorted(mm for mm in placement_maps if placement._unlisted_piece(mm) is not None)
    m["roleUnlistedPieces"] = "、".join(unlisted) or "（无）"
    m["roleUnlistedPieceRows"] = "、".join(sorted({str(nid) for mm in unlisted for nid in placement.map_npcs[mm]
                                                   if nid in placement.npc and
                                                   7740 <= int(placement.npc[nid]["multiPlayCorrectionParamId"]) < 7770})) or "（无）"

    # 夜王突袭行放在自己的抽选里没有本夜王 Raid 修饰的据点（按同一突袭计，推断）
    inferred = sorted({e["msb"] for e2 in nightlords for f in e2["fights"] for e in f["roleEvidence"].get("raid", [])
                       if "**推断**" in e["note"]})
    m["roleLordRaidInferred"] = (f"{len(inferred)} 张（{'、'.join(inferred)}）" if inferred else "0 张")

    # ---- 开放地图地块（变异类别判定）
    ow_maps = sorted(mm for mm, info in placement_maps.items() if info["kind"] == "overworldTile")
    m["roleOverworldMaps"] = len(ow_maps)
    m["roleTileRows"] = placement.tile_row_count
    m["roleTileCodes"] = len(placement.tile_rows)
    ev_rows = lambda role, pred: sorted({e["npcId"] for v in v_all for e in v["roleEvidence"].get(role, []) if pred(e)})
    group_name = {nid: (b["nameZh"] or b["nameEn"]) for b in night_bosses for v in b["variants"] for nid in v["npcIds"]}
    name_of = lambda nid: (placement.npc[nid]["Name"]
                           or (f"无 Paramdex 行名，所在组 {group_name[nid]}" if nid in group_name else "无 Paramdex 行名"))
    fmt_rows = lambda ids: "、".join(f"{nid}（{name_of(nid)}）" for nid in ids) or "（无）"
    mine_rows = ev_rows("mine", lambda e: True)
    m["roleMineRows"] = fmt_rows(mine_rows)
    helper_rows = ev_rows("summon", lambda e: "通用占位 AI" in e["note"])
    m["roleOpenMapHelperRows"] = fmt_rows(helper_rows)
    scripted_rows = ev_rows("event", lambda e: "对话脚本" in e["note"])
    m["roleScriptedRows"] = fmt_rows(scripted_rows)
    ow_field = ev_rows("field", lambda e: e["msb"] in ow_maps)
    no_lot = ev_rows("field", lambda e: e["msb"] in ow_maps and "不带首领奖励表（rewardItemLot_2 ≤ 0）" in e["note"])
    m["roleOverworldFieldRows"] = len(ow_field)
    m["roleFieldNoLotCount"] = len(no_lot)
    m["roleFieldNoLotRows"] = fmt_rows(no_lot)
    # mapUnk 解码与适用规则的实测旁证：坑道精英（150，modifierMapId1 = 0）的 (Mine) 首领行放在哪几个地形变体里，
    # 必须正好是「该地块现有 MSB 变体 − 大空洞 − modifierMapId2/3」
    mine_checks = []
    for code, trs in sorted(placement.tile_rows.items()):
        for t in trs:
            if t["cat"] != 150 or t["m1"]:
                continue
            prefix = f"m60_{code // 100 % 100:02d}_{code % 100:02d}_"
            have = sorted({int(mm[-2:]) // 10 for mm in placement.msb_map_names
                           if mm.startswith(prefix) and int(mm[-2:]) % 10 == 0})
            excl = sorted(x - 10 for x in (t["m2"], t["m3"]) if x)
            want = [v for v in have if v != GREAT_HOLLOW_VARIANT and v not in excl]
            elite = sorted({nid for mm, ids in placement.map_npcs.items() if mm.startswith(prefix) for nid in ids
                            if nid in placement.npc and "(Mine" in (placement.lot_names.get(
                                int(placement.npc[nid]["rewardItemLot_2"])) or "")})
            assert len(elite) == 1, f"坑道精英行 {t['id']} 的地块上 (Mine) 首领行不是恰好一行：{elite}"
            got = sorted({int(p["map"][-2:]) // 10 for p in placement.enemy_parts[elite[0]] if p["map"].startswith(prefix)})
            assert got == want, f"坑道精英行 {t['id']}：(Mine) 行 {elite[0]} 放在变体 {got}，按适用规则应为 {want}"
            mine_checks.append(f"{t['id']}（排除变体 {'/'.join(map(str, excl)) or '无'}）的 {elite[0]}「{name_of(elite[0])}」"
                               f"放在变体 {'/'.join(map(str, got))}（该地块现有 {'/'.join(map(str, have))}）")
    assert len(mine_checks) == 3, mine_checks
    m["roleTileMineChecks"] = "；".join(mine_checks)

    # ---- PATTERN_MODIFIER 推断的旁证（全部实测；对不上就报错）
    raid_sbv = {sid: n for sid, n in placement.sbv.items() if n.startswith("Boss Raid - ")}
    raid_pairs = []
    for mod, name in RAID_MODIFIERS.items():
        pats = {pid for pid, mods in placement.pmods.items() if mod in mods}
        pieces = sorted({sid for sid in raid_sbv for l in placement.lots.get(sid, [])
                         if int(l["patternId"]) in pats})
        key = name.split(" - ", 1)[1]
        if not pieces:
            # 哈尔莫妮亚的突袭在据点里，不单独占一个突袭地图块
            raid_pairs.append(f"{mod}（{name}）↔ 无独立突袭地图块")
            continue
        assert len(pieces) == 1 and f"({key})" in raid_sbv[pieces[0]], \
            f"PATTERN_MODIFIER 推断：{mod} {name} 对应的突袭地图块不唯一或行名对不上：{pieces}"
        lots = placement.lots[pieces[0]]
        inside = sum(1 for l in lots if mod in placement.pmods[int(l["patternId"])])
        assert inside == len(lots), f"突袭地图块 {pieces[0]} 有抽选结果不在修饰 {mod} 的地图模式里"
        raid_pairs.append(f"{mod} ↔ {pieces[0]}「{raid_sbv[pieces[0]]}」（{inside}/{len(lots)} 行）")
    m["roleRaidModifierPairs"] = "；".join(raid_pairs)
    # targetBoss：地图模式行名的 [夜王] 前缀必须与 targetBoss 指向的 NightBossMenuParam 行名一致；
    # 每种夜王 Raid 修饰都不能出现在该夜王自己的远征里
    named = 0
    for pid, pname in placement.pattern_names.items():
        mm = re.match(r"\[([^\]]+)\]", pname)
        if mm:
            assert placement.menu_names.get(placement.ptarget[pid], "").endswith(f"/ {mm.group(1)}"), \
                f"地图模式 {pid}「{pname}」的 targetBoss {placement.ptarget[pid]} 对不上"
            named += 1
    assert named == len(placement.pattern_names), "有地图模式行名不带 [夜王] 前缀"
    m["rolePatternTargetCheck"] = (f"全表 {named} 个地图模式的行名前缀「[夜王]」与 targetBoss 指向的 "
                                   "NightBossMenuParam 行名逐个一致")
    tparts = []
    for mod, name in RAID_MODIFIERS.items():
        pats = sorted(pid for pid, mods in placement.pmods.items() if mod in mods)
        tgts = Counter(placement.ptarget[p] for p in pats)
        own_ids = placement.lord_menu_ids(mod)
        assert not set(tgts) & own_ids, f"Raid 修饰 {mod} 出现在夜王本人的远征里：{set(tgts) & own_ids}"
        tparts.append(f"{mod}（{name.split(' - ', 1)[1]}）{len(pats)} 个模式 → "
                      + "/".join(f"{t}×{n}" for t, n in sorted(tgts.items()))
                      + (f"（不含 {'/'.join(map(str, sorted(own_ids)))}）" if own_ids else "（莫格没有远征）"))
    m["roleRaidTargets"] = "；".join(tparts)
    word_ok = []
    for mod, word in MAP_MODIFIER_PATTERN_WORD.items():
        names = [r["Name"] for r in placement.pattern_rows if int(r["modifier"]) == mod and r["Name"]]
        good = sum(1 for n in names if word in n)
        assert names and good == len(names), f"PATTERN_MODIFIER 推断：修饰 {mod} 的地图模式行名不全含 {word}"
        word_ok.append(f"{mod}「{word}」{good}/{len(names)}")
    m["roleMapModifierWords"] = "、".join(word_ok)
    horde = sorted(sid for sid, ls in placement.lots.items()
                   if ls and all(HORDE_MODIFIER[0] in placement.pmods[int(l["patternId"])] for l in ls))
    assert horde and all(placement.sbv.get(sid, "").startswith("Night Horde - ") for sid in horde), \
        f"PATTERN_MODIFIER 推断：修饰 180 的地图块行名不全是 Night Horde：{horde}"
    m["roleHordePieces"] = len(horde)
    merch = sorted({int(l["smallBaseMapId"]) for ls in placement.lots.values() for l in ls
                    if int(l["modifier"]) == MERCHANT_MODIFIER[0]})
    assert all("(Libra)" in placement.sbv.get(sid, "") for sid in merch), \
        f"PATTERN_MODIFIER 推断：modifier 424 的地图块行名不全带 (Libra)：{merch}"
    m["roleMerchantPieces"] = "、".join(f"{sid}「{placement.sbv[sid]}」" for sid in merch)
    # 陨石（修饰 200）与大据点默认地块
    dlots = [l for sid in placement.defaults for l in placement.lots.get(sid, [])]
    meteor_hit = sum(1 for pid in placement.meteor_patterns if any(int(l["patternId"]) == pid for l in dlots))
    assert meteor_hit == len(placement.meteor_patterns), "陨石模式没有全部挂出大据点默认地块"
    m["roleMeteorPatterns"] = len(placement.meteor_patterns)
    m["roleDefaultLots"] = len(dlots)
    m["roleDefaultLotsMeteor"] = sum(1 for l in dlots if int(l["patternId"]) in placement.meteor_patterns)
    default_bosses = sorted({nid for sid in placement.defaults for mm in [f"m{sid // 100}_{sid % 100:02d}_00_00"]
                             for nid in placement.map_npcs.get(mm, ())
                             if nid in placement.npc and int(placement.npc[nid]["rewardItemLot_2"]) > 0})
    m["roleDefaultBossRows"] = "、".join(
        f"{nid}（{placement.npc[nid]['Name']}，rewardItemLot_2 {placement.npc[nid]['rewardItemLot_2']}"
        f"「{placement.lot_names.get(int(placement.npc[nid]['rewardItemLot_2']), '')}」）" for nid in default_bosses)

    # 文案（caveats / notes.roleAudit）里点名的例子必须真的成立：数据变了就报错，不让文字悄悄失真
    row_roles = {nid: rr for v in v_all for nid, rr in v["rowRoles"].items()}
    expect = {
        "31000010": ["field"],            # 铃珠猎人野外版（挂 7753 Night Boss Threat）
        "32510020": ["field"],            # 大树守卫野外版（7753）
        "31000020": ["night", "tower"],   # 铃珠猎人守夜版，同一地图块又挂到大空洞高塔
        "77110010": ["summon"], "48010010": ["summon"], "79100010": ["summon"],
        "45050020": ["prelude"],          # 无名王者战前的小飞龙
        # 夜晚首领地图块也挂到大空洞高塔时，前哨只标 prelude（白金之子 / 归树看门犬）
        "36000010": ["prelude"], "36001010": ["prelude"], "42600110": ["prelude"],
        # 坐骑与辅助实体（第二条判据）：送葬马（守夜 / 野外）、贪食魔龙的 c2150 辅助实体
        "31600020": ["summon"], "31600010": ["summon"], "77009010": ["summon"],
        # 零头卢恩判据不能误伤真正的双首领：夜骑兵（连枷）与熔炉骑士同图的黄金河马
        "31501020": ["night", "tower"], "50110020": ["night", "tower"],
        # 「圣树骑士」罗蕾塔 = 卡利亚禁卫骑士：只当野外首领（野外首领地图块 m46_54 与诺克拉缇欧地块）
        "32520010": ["field"],
        # m46_90 是没被任何表引用的地图块 → 先祖之灵这一行未放置
        "46700020": ["unplaced"],
        # 开放地块按变异类别：坑道里的精英（宁姆韦德的 Troll (Mine)、大空洞的挖石山妖）→ mine
        "46000110": ["mine"], "46030010": ["mine"],
        # 开放地块上的辅助实体（模型 c0100、占位 AI、零奖励）→ summon；零奖励的剧情敌人 → event
        "45030020": ["summon"], "35600060": ["event"],
        # 新增的三个核对样例（与 Fextralife 的 Night Bosses Day 1 / Day 2 名单一致）
        "49801010": ["night", "tower"], "49801020": ["field"], "49801110": ["summon"],
        "31500020": ["night", "tower"], "31500010": ["field"], "79301010": ["night"],
    }
    for nid, want in expect.items():
        assert row_roles.get(nid) == want, f"场合样例 {nid} 期望 {want}，实际 {row_roles.get(nid)}"
    # 文案里「真双首领不受零头卢恩判据影响」的两处数字
    soul = lambda i: num(placement.npc[i]["getSoul"])
    assert soul(31501020) == soul(31500020) and soul(50110020) * 3 == soul(25000020) * 2, \
        "caveats【场合】② 里夜骑兵连枷版 / 黄金河马的卢恩对比失真"
    for nid in ("25000020", "40210020", "41301010"):      # 挂 Field Boss Threat 的守夜行
        assert "night" in row_roles.get(nid, []), f"场合样例 {nid} 应当是守夜首领"
    assert "night" not in row_roles.get("45000010", []) and "field" in row_roles.get("45000010", [])
    assert placement.maps.get("m48_70_00_00", {}).get("kind") == "inactivePiece"
    assert placement.maps.get("m46_90_00_00", {}).get("kind") == "inactivePiece"
    assert placement.maps.get("m35_90_00_00", {}).get("kind") == "otherMap"      # 教程（Morgott (Tutorial)）
    groups = {b["id"]: b for b in night_bosses}
    assert groups["Borealis the Freezing Fog@4503"]["roles"] == ["summon", "unplaced"]
    assert "field" not in groups["Troll@4600"]["roles"] and "mine" in groups["Troll@4600"]["roles"]
    assert "field" not in groups["Godskin Apostle@3560"]["roles"]
    rck = next(b for b in night_bosses if b["id"] == "Royal Carian Knight@3252")
    assert "night" not in rck["roles"] and "field" in rck["roles"], rck["roles"]
    assert {e["msb"] for v in rck["variants"] for e in v["roleEvidence"].get("field", [])} >= {"m46_54_00_00"}
    # 前哨判定只靠 7741 档：凡是放进地图的 7741 行，所在地图必须全是夜晚首领地图块
    for nid, r in placement.npc.items():
        if int(r["multiPlayCorrectionParamId"]) == PRELUDE_SCALING_ID:
            kinds = {placement.classify(p["map"])["kind"] for p in placement.enemy_parts.get(nid, [])}
            assert kinds <= {"nightBossPiece"}, f"7741 行 {nid} 放在了夜晚首领地图块以外：{kinds}"
    return m


# ---------------------------------------------------------------- 战斗行构建


def fight_stats(row: dict, scaling: Scaling, perm: PermScaling,
                depth: "DepthScaling", mutations: "Mutations") -> dict:
    rates = {out: num(row[f"{src}DamageCutRate"]) for out, src in DAMAGE_RATES}
    resist = {out: num(row[src]) for out, src in RESISTS}
    scaling_id, tiers = scaling.get(row["multiPlayCorrectionParamId"])
    p = perm.of(row)
    hp_base = num(row["hp"])
    deep = None
    if p["deep"]:
        deep = {
            "hp": hp_from(hp_base, p["deep"]["hpMultiplier"]),
            "hpMultiplier": p["deep"]["hpMultiplier"],
            "poiseTakenBase": p["deep"]["poiseTakenBase"],
            "poiseRecoverMultiplier": p["deep"]["poiseRecoverMultiplier"],
            "ailmentDamageRateBase": p["deep"]["ailmentDamageRateBase"],
            "attackRateBase": p["deep"]["attackRateBase"],
            "attackRatesBase": p["deep"]["attackRatesBase"],
            "staminaAttackRateBase": p["deep"]["staminaAttackRateBase"],
            "permScalingIds": p["ids"] + p["deepIds"],
        }

    # ---- 深夜各深度（schemaVersion 3）
    # 深夜里「深度修正行（2287 条件触发）」和「深度 1–5 的缩放行」都会生效，所以
    # 深度 N 的基准 = deepOfNight 那一档（没有就是常驻档）再乘上深度行的倍率。
    chaos_id, depth_tiers = depth.get(row.get("chaosMatchingCorrectParamId", "0"))
    deep_hp_mult = p["deep"]["hpMultiplier"] if p["deep"] else p["hpMultiplier"]
    deep_poise = p["deep"]["poiseTakenBase"] if p["deep"] else p["poiseTakenBase"]
    deep_atk = p["deep"]["attackRatesBase"] if p["deep"] else p["attackRatesBase"]
    deep_stam = p["deep"]["staminaAttackRateBase"] if p["deep"] else p["staminaAttackRateBase"]
    depth_stats = None
    if depth_tiers:
        depth_stats = {}
        for k, d in depth_tiers.items():
            # hp 先量化倍率再乘（见 hp_from）：页面用 hpBase × hpMultiplier 能逐位复现
            hp_mult = round(deep_hp_mult * d["hp"], MULT_PLACES)
            depth_stats[k] = {
                "hp": hp_from(hp_base, hp_mult),
                "hpMultiplier": hp_mult,
                "poiseTakenBase": round(deep_poise * d["poiseTaken"], 6),
                "attackRatesBase": {k: round(v * d["attackRate"], 6)
                                    for k, v in deep_atk.items()},
                "attackRateBase": round(deep_atk["physical"] * d["attackRate"], 6),
                "staminaAttackRateBase": round(deep_stam * d["staminaAttackRate"], 6),
                "depthSpEffectId": d["spEffectId"],
            }

    mutation_id = mutations.get(row.get("chaosMatchingSpEffectSetParamId", "-1"))

    return {
        # hp 是玩家真正要打掉的 1 人血量；hpBase 才是 NpcParam.hp 原始字段
        "hp": hp_from(hp_base, p["hpMultiplier"]),
        "hpBase": hp_base,
        "hpMultiplier": p["hpMultiplier"],
        "poise": num(row["superArmorDurability"]),
        "poiseRecover": num(row["saRecoveryRate"]),
        "poiseTakenBase": p["poiseTakenBase"],
        "poiseRecoverMultiplier": p["poiseRecoverMultiplier"],
        "damageRates": rates,
        "ailmentDamageRateBase": p["ailmentDamageRateBase"],
        "resist": resist,
        "immune": [k for k, v in resist.items() if v >= IMMUNE],
        "permScalingIds": p["ids"],
        "deepOfNight": deep,
        "scalingId": scaling_id,
        "scaling": tiers,
        # ---- schemaVersion 3 新增
        "attackRateBase": p["attackRateBase"],
        "attackRatesBase": p["attackRatesBase"],
        "staminaAttackRateBase": p["staminaAttackRateBase"],
        "chaosCorrectId": chaos_id,
        "depthStats": depth_stats,
        "mutationSetId": mutation_id,
        "mutationPool": [mutation_id] if mutation_id is not None else [],
    }


def merge_key(stats: dict, extra: tuple) -> tuple:
    """只有「玩家侧完全一致」的行才允许合并。

    这里必须把常驻 SpEffect 的效果一起比，否则像 Morgott 的
    21300010（×1.83）和 21300520（×1.83×2.42）这种有效血量差 2.4 倍的行
    会因为 NpcParam.hp 相同而被当成同一条。
    """
    return (
        extra,
        stats["hp"],
        stats["hpBase"],
        stats["hpMultiplier"],
        stats["poise"],
        stats["poiseRecover"],
        stats["poiseTakenBase"],
        stats["poiseRecoverMultiplier"],
        stats["ailmentDamageRateBase"],
        tuple(stats["damageRates"].items()),
        tuple(stats["resist"].items()),
        json.dumps(stats["deepOfNight"], sort_keys=True),
        json.dumps(stats["scaling"], sort_keys=True),
        # schemaVersion 3：深度缩放与变异档位不同的行不能再合并
        stats["chaosCorrectId"],
        stats["mutationSetId"],
        stats["attackRateBase"],
        stats["staminaAttackRateBase"],
    )


# ---------------------------------------------------------------- 夜王


def build_nightlords(raw: Path, npc_rows: list[dict], scaling: Scaling, perm: PermScaling,
                     depth: DepthScaling, mutations: Mutations,
                     report: dict) -> tuple[list[dict], set[int]]:
    menu_zh = load_fmg(raw, "zhocn", "menu_dlc01", "CL_MenuText")
    menu_en = load_fmg(raw, "engus", "menu_dlc01", "CL_MenuText")
    used_npc_ids: set[int] = set()

    by_chr: dict[int, list[dict]] = defaultdict(list)
    claimed: set[int] = set()
    for chrs in NIGHTLORD_CHRS.values():
        claimed.update(chrs)
    for r in npc_rows:
        c = int(r["ID"]) // 10000
        if c in claimed and r["multiPlayCorrectionParamId"] != "0":
            by_chr[c].append(r)

    out: list[dict] = []
    for m in read_param(raw, "NightBossMenuParam"):
        menu_id = int(m["ID"])
        boss_name_id = m["bossNameId"]
        if boss_name_id in ("-1", ""):
            report["skippedMenuRows"].append({"menuId": menu_id, "name": m["Name"],
                                              "reason": "没有 bossNameId（深度模式入口，不是夜王）"})
            continue
        # 行名前缀区分三种形态：本体 / [Everdark Sovereign] 永夜之王 /
        # [Salvation's Standard-Bearers] 救世旗手（只有哈尔莫妮亚有，修复前被误判成永夜之王）
        variant_key, variant_text_id = "normal", None
        for prefix, vk, text_id in MENU_VARIANTS:
            if m["Name"].startswith(prefix):
                variant_key, variant_text_id = vk, text_id
                break
        else:
            if m["Name"].startswith("["):
                report["unknownMenuVariants"].append(m["Name"])
                variant_key = "unknown"
        is_variant = variant_key != "normal"
        everdark = variant_key == "everdark"
        key = m["Name"].split("/")[-1].strip()
        chrs = NIGHTLORD_CHRS.get(key)
        if chrs is None:
            report["unmappedNightlords"].append(m["Name"])
            chrs = []

        weakness = []
        for f in ("effectiveAffinity1", "effectiveAffinity2"):
            code = int(m[f])
            if code == 0:
                continue
            zh, en = AFFINITY_NAMES.get(code, (str(code), str(code)))
            weakness.append({"code": code, "zh": zh, "en": en})

        # 把该夜王名下的 NpcParam 行按 (变体?, 突袭?) 归属后合并
        buckets: dict[tuple, list[dict]] = defaultdict(list)
        for c in chrs:
            for r in by_chr.get(c, []):
                name = r["Name"]
                row_is_variant = (c in EVERDARK_CHRS or "Everdark" in name
                                  or "Enhanced Boss" in name or perm.of(r)["everdarkScaled"])
                if row_is_variant != is_variant:
                    continue
                stats = fight_stats(r, scaling, perm, depth, mutations)
                is_raid = "Raid" in name
                buckets[merge_key(stats, (is_raid,))].append(r)

        fights = []
        for rows in buckets.values():
            rows.sort(key=lambda r: int(r["ID"]))
            rep = next((r for r in rows if int(r["ID"]) in MAIN_NPC_IDS), None)
            if rep is None:
                rep = next((r for r in rows if int(r["ID"]) in NIGHTLORD_LABEL_OVERRIDE), None)
            if rep is None:                      # 优先取有 Paramdex 行名的那一行
                named = [r for r in rows if r["Name"]]
                rep = max(named or rows, key=lambda r: (len(r["Name"]), -int(r["ID"])))
            label_zh, label_en = nightlord_label(rep)
            fight = {
                "npcId": int(rep["ID"]),
                "npcIds": [int(r["ID"]) for r in rows],
                "paramdexName": rep["Name"] or None,
                "labelZh": label_zh,
                "labelEn": label_en,
                "labelUncertain": "?" in (rep["Name"] or ""),
                "isMain": any(int(r["ID"]) in MAIN_NPC_IDS for r in rows),
                # schemaVersion 3：行级「不掉任何奖励」，与 nightBosses 的变体同义
                "noReward": rows_no_reward(rows),
            }
            fight.update(fight_stats(rep, scaling, perm, depth, mutations))
            fight["mutationPool"] = sorted({m for r in rows
                                            for m in [mutations.get(r.get("chaosMatchingSpEffectSetParamId", "-1"))]
                                            if m is not None})
            fights.append(fight)
            used_npc_ids.update(int(r["ID"]) for r in rows)
        disambiguate(fights)
        fights.sort(key=lambda f: (not f["isMain"], f["npcId"]))

        entry = {
            "menuId": menu_id,
            "paramdexName": m["Name"],
            "nameZh": menu_zh.get(boss_name_id, ""),
            "nameEn": menu_en.get(boss_name_id, ""),
            "expeditionZh": menu_zh.get(m["expeditionNameId"], ""),
            "expeditionEn": menu_en.get(m["expeditionNameId"], ""),
            "everdark": everdark,
            "variantKey": variant_key,
            "variantNameZh": menu_zh.get(variant_text_id, "") if variant_text_id else "",
            "variantNameEn": menu_en.get(variant_text_id, "") if variant_text_id else "",
            "sortId": int(m["sortId"]),
            "weakness": weakness,
            "descriptionZh": menu_zh.get(m["descriptionId"], ""),
            "descriptionEn": menu_en.get(m["descriptionId"], ""),
            # schemaVersion 3：该夜王在深夜深度 1–5 的出现权重（同深度下各夜王的权重相除
            # 即为相对概率；永夜之王/救世旗手在深度 1 全是 0，也就是深度 1 不会出永夜形态）
            "depthChanceWeights": {str(d): num(m[f"depth{d}ChanceWeight"]) for d in DEPTHS},
            "fights": fights,
        }
        if not entry["nameZh"]:
            report["missingZhNightlord"].append(m["Name"])
        out.append(entry)

    out.sort(key=lambda e: (e["variantKey"] != "normal", e["sortId"]))

    # 落在「Final Boss Threat」(7760–7769) 却没有被任何夜王条目收走的行
    for r in npc_rows:
        npc_id = int(r["ID"])
        if 7760 <= int(r["multiPlayCorrectionParamId"]) < 7770 and npc_id not in used_npc_ids:
            p = perm.of(r)
            report["unassignedFinalBossRows"].append({
                "npcId": npc_id,
                "name": r["Name"] or None,
                "chrId": npc_id // 10000,
                "hp": hp_from(num(r["hp"]), p["hpMultiplier"]),
                "hpBase": num(r["hp"]),
                "scalingId": int(r["multiPlayCorrectionParamId"]),
                "reason": "multiPlayCorrectionParamId 属于最终 Boss 档位，但 chrId 不属于任何夜王",
            })
    return out, claimed


def nightlord_label(row: dict) -> tuple[str, str]:
    npc_id = int(row["ID"])
    if npc_id in NIGHTLORD_LABEL_OVERRIDE:
        return NIGHTLORD_LABEL_OVERRIDE[npc_id]
    chr_id = npc_id // 10000
    entity = ENTITY_ZH_SUB.get(npc_id // 1000) or ENTITY_ZH.get(chr_id) or ""
    _, variant = base_and_variant(row["Name"])
    vz = variant_zh(variant)
    label_zh = f"{entity} · {vz}" if entity and vz else (entity or vz or "本体")
    return label_zh, row["Name"] or f"NpcParam {npc_id}"


# ---------------------------------------------------------------- 守夜/野外


class NameBook:
    """NpcName 文本 ID 形如 9 + chrId(5 位) + 3 位序号，用它把 Paramdex 名对上简中名。

    规范化规则（schemaVersion 3 起写死成结构性的，不再有手工译名）：
      * NpcName 的文本 ID = 900000000 + chrId × 1000 + 变体号；
        chrId = NpcParam 行号 // 10000。
      * 对照用的键是 norm()：英文小写、只留 a-z0-9 和空格。
        「Paramdex 行名的基础名」与「engus NpcName」normalize 后相等即算同一敌人。
      * 同一条英文名有单数和群体两种简中词条时（例如 904480311「米兰达之花」与
        904480200「米兰达之花群」），优先取不带「群/们/队」后缀的那条。
      * 只有当 Paramdex 基础名比 NpcName 长、且 NpcName 是它的「中心词」时
        （norm(base) 以 " " + norm(fmg) 结尾，如 Large Golden Hippopotamus ⊃
        Golden Hippopotamus）才允许放宽匹配，并标 nameApprox = true。
        反方向（NpcName 比基础名长）一律不匹配，否则 Troll 会错配成 Troll Knight。
    """

    def __init__(self, raw: Path):
        self.en = load_fmg(raw, "engus", "item_dlc01", "NpcName")
        self.zh = load_fmg(raw, "zhocn", "item_dlc01", "NpcName")
        self.by_chr: dict[int, list[str]] = defaultdict(list)
        self.by_norm: dict[str, list[str]] = defaultdict(list)
        for k, v in self.en.items():
            if len(k) == 9 and k[0] == "9":
                self.by_chr[int(k[1:6])].append(k)
            self.by_norm[norm(v)].append(k)
        for ids in self.by_chr.values():
            ids.sort(key=int)
        for ids in self.by_norm.values():
            ids.sort(key=int)
        # chrId → 该 chrId 自己的 Paramdex 基础名（normalize 过）。用来判断一条全局
        # 精确命中的 NpcName 到底「属于谁」：904505000「Flying Dragon」所在的 chr 4505
        # 自己的 Paramdex 名就是 Flying Dragon，那它就是 c4505 的名字，c4500 不能拿；
        # 而 904601001「Snowfield Troll」所在的 chr 4601 自己叫 Troll Knight，
        # 这条只是挂在 4601 名字段里的邻居，c4602 可以拿。
        self.chr_bases: dict[int, set[str]] = {}

    # ---- 挑选

    def _prefer(self, ids: list[str]) -> str | None:
        """一组候选里挑最合适的：有简中的优先，非「群/们/队」结尾的优先，再按 ID。"""
        cands = [k for k in ids if self.zh.get(k)] or list(ids)
        if not cands:
            return None
        return min(cands, key=lambda k: ((self.zh.get(k, "") or "").endswith(PLURAL_ZH_SUFFIX),
                                         int(k)))

    def _exact_in_chr(self, base: str, chr_id: int) -> str | None:
        nb = norm(base)
        return self._prefer([k for k in self.by_chr.get(chr_id, []) if norm(self.en[k]) == nb])

    def _owned_by_other_chr(self, k: str, chr_id: int) -> bool:
        """这条 NpcName 是不是「别的 chrId 自己的名字」。

        只有当本 chrId **自己也有**游戏文本词条时才拦：
          * c4500 自己有 904500600「Flying Dragon of the Hills」，
            那 904505000「Flying Dragon」就是隔壁 c4505 的名字，不能抢（→ 丘陵飞龙）；
          * c4021 自己一条词条都没有，那它借用同一只敌人在 c4020 名下的
            904020540「Royal Revenant / 王室幽魂」是对的。
        """
        if not (len(k) == 9 and k[0] == "9"):
            return False
        owner = int(k[1:6])
        if owner == chr_id or not self.by_chr.get(chr_id):
            return False
        return norm(self.en.get(k, "")) in self.chr_bases.get(owner, set())

    def _exact_global(self, base: str, chr_id: int) -> str | None:
        cands = [k for k in self.by_norm.get(norm(base), [])
                 if not self._owned_by_other_chr(k, chr_id)]
        return self._prefer(cands)

    def _loose_in_chr(self, base: str, chr_id: int) -> str | None:
        """同 chrId 下的单复数 / 扩写匹配（Snowfield Troll ↔ Snowfield Trolls）。"""
        nb = norm(base)
        cands = self.by_chr.get(chr_id, [])
        hit = [k for k in cands
               if (lambda nk: (nk.startswith(nb) or nb.startswith(nk))
                   and abs(len(nk) - len(nb)) <= 2)(norm(self.en[k]))]
        if hit:
            return self._prefer(hit)
        hit = [k for k in cands
               if (lambda nk: nk.startswith(nb + " ") or nb.endswith(" " + nk))(norm(self.en[k]))]
        return self._prefer(hit)

    def _head_noun_global(self, base: str, chr_id: int) -> str | None:
        """全局「中心词」匹配：只允许 NpcName 是基础名的后缀（基础名更长）。"""
        nb = norm(base)
        best, best_len = None, -1
        for nk, ids in self.by_norm.items():
            if nk and nb.endswith(" " + nk) and len(nk) > best_len:
                k = self._prefer(ids)
                if k is not None and self.zh.get(k):
                    best, best_len = k, len(nk)
        return best

    def evidence(self, k: str) -> dict:
        return {"fmg": "item/NpcName", "id": k,
                "en": self.en.get(k, ""), "zh": self.zh.get(k, "")}

    # ---- 主流程

    def resolve(self, base: str, chr_id: int, name_ids: set[str],
                community: dict | None = None) -> dict:
        """→ {nameZh, nameEn, nameSource, npcNameId, inferred, approx, evidence, note, sourceUrl}

        顺序：NpcParam.nameId（该组唯一且 >0 时）→ (chrId, 基础名) 别名表 → 基础名别名表 →
        同 chrId 精确 → 全局精确 → 同 chrId 放宽 → 全局中心词 → chrId 独苗 →
        社区身份（只用来认「这是谁」，中文仍去 NpcName 里取）→ 只有英文 / 只有 chrId。
        NpcParam.nameId 是游戏自己填的「这一行叫什么」，优先级最高：
        610030300「Duchess (Undertaker Remembrance)」的 nameId = 140030「黑夜盗贼」，
        而不是 Paramdex 行名暗示的职业名「女爵」。
        """
        def done(k: str, source: str, *, name_en: str | None = None, approx: bool = False,
                 inferred: bool = False, note: str = "", url: str = "") -> dict:
            return {
                "nameZh": self.zh.get(k, ""),
                "nameEn": name_en if name_en is not None else base,
                "nameSource": source,
                "npcNameId": k,
                "inferred": inferred,
                "approx": approx,
                "evidence": self.evidence(k),
                "note": note,
                "sourceUrl": url,
            }

        if len(name_ids) == 1:
            k = next(iter(name_ids))
            if self.zh.get(k) or self.en.get(k):
                r = done(k, "npcparam-nameid")
                r["nameEn"] = self.en.get(k, base)
                return r
        ck = (chr_id, base)
        if ck in ALIAS_NPCNAME_ID_BY_CHR:
            k = ALIAS_NPCNAME_ID_BY_CHR[ck]
            if self.zh.get(k) or self.en.get(k):
                r = done(k, "npcname-alias-chr", inferred=ck in ALIAS_INFERRED)
                r["nameEn"] = self.en.get(k, base)
                return r
        if base in ALIAS_NPCNAME_ID:
            return done(ALIAS_NPCNAME_ID[base], "npcname-alias")
        k = self._exact_in_chr(base, chr_id)
        if k is not None and self.zh.get(k):
            return done(k, "npcname")
        k = self._exact_global(base, chr_id)
        if k is not None and self.zh.get(k):
            return done(k, "npcname-global")
        k = self._loose_in_chr(base, chr_id)
        if k is not None and self.zh.get(k):
            return done(k, "npcname", approx=norm(self.en[k]) != norm(base))
        k = self._head_noun_global(base, chr_id)
        if k is not None:
            return done(k, "npcname-relaxed", approx=True,
                        note=f"游戏文本里没有「{base}」这条词条，取了中心词「{self.en[k]}」"
                             f"（NpcName {k}）的简中名，仅供参考。")
        only = self.by_chr.get(chr_id, [])
        if len(only) == 1 and self.zh.get(only[0]):
            # 该 chrId 底下只有一条游戏文本词条，但英文对不上基础名（多半是把同一处
            # 遭遇里的一伙敌人合起来叫的群体名，例如 c3600 的 903600530
            # 「Stoneskin Lords / 石肤众王」同时盖住雪花石之王和缟玛瑙之王），标 nameApprox
            return done(only[0], "npcname-chr-only", approx=True,
                        note=f"游戏文本里 c{chr_id} 只有一条词条"
                             f"「{self.en.get(only[0], '')}」，英文与 Paramdex 行名"
                             f"「{base}」对不上，多半是这处遭遇的群体名，仅供参考。")
        if community:
            name_en = community.get("nameEn") or base
            ck2 = self._exact_global(name_en, chr_id) if name_en else None
            if ck2 is not None and self.zh.get(ck2):
                return done(ck2, "community-npcname", name_en=name_en,
                            note=community.get("note", ""), url=COMMUNITY_SOURCE_URL)
            return {
                "nameZh": "", "nameEn": name_en, "nameSource": "community",
                "npcNameId": "", "inferred": False, "approx": False, "evidence": None,
                "note": community.get("note", ""), "sourceUrl": COMMUNITY_SOURCE_URL,
            }
        return {"nameZh": "", "nameEn": base, "nameSource": "english-only", "npcNameId": "",
                "inferred": False, "approx": False, "evidence": None, "note": "", "sourceUrl": ""}


def fallback_zh(name_en: str, name_zh: str) -> tuple[str, str]:
    """→ (nameZhFallback, nameZhFallbackNote)。

    v2 里按《艾尔登法环》官方简中手工补的译名（nameSource=manual）在 v3 全部移出
    nameZh，但不丢：只要这一组现在的 nameZh 不等于旧译名，就把旧译名放进
    nameZhFallback，并在 note 里写清「不是本作的游戏内文本」。
    （v3 首版只在 nameZh 为空时才写 fallback，导致 4 条被游戏文本名替换掉的旧译名
    只剩在 notes.nameChanges 里，页面拿不到；这里改成「不相等就写」。）
    """
    old = REMOVED_MANUAL_ZH.get(name_en, "")
    if not old or old == name_zh:
        return "", ""
    note = (f"「{old}」**不是本作的游戏内文本**，"
            f"是按《艾尔登法环》官方简中补的译名（v2 的 nameSource=manual）。"
            f"全部 FMG 里检索不到完全一致的字符串，因此不进 nameZh；")
    note += ("页面要显示中文时可以拿它兜底，但请标明不是官方名。" if not name_zh else
             f"本条的 nameZh「{name_zh}」来自游戏文本，以 nameZh 为准，"
             f"这里只是保留旧译名备查。")
    return old, note


def name_evidence_rank(entry: dict) -> int:
    """nameZh 的证据强度，用来在「两张卡同名」时决定谁保留。

    3 = 逐字命中游戏文本（nameApprox = false）；
    2 = 近似命中，但词条属于本组自己的 chrId（NpcName ID 的 9xxxxx 段 = chrId）；
    1 = 近似命中，而且词条是从别的 chrId 借来的（中心词 / 群体名）；
    0 = 没有 nameZh。
    """
    if not entry["nameZh"]:
        return 0
    if not entry["nameApprox"]:
        return 3
    ev = entry["nameEvidence"]
    key = (ev or {}).get("id", "")
    if len(key) == 9 and key[0] == "9" and int(key[1:6]) in entry["chrIds"]:
        return 2
    return 1


def resolve_name_collisions(entries: list[dict], report: dict) -> None:
    """同一个 nameZh 不允许同时挂在两组首领上。

    v3 首版放宽了 NpcName 的匹配（中心词 / chrId 独苗群体名），结果产生 3 对重名：
    石肤众王（Alabaster Lord + Onyx Lord）、黄金河马（Large Golden Hippopotamus +
    Golden Hippopotamus）、蚯蚓脸（Dreg Wormface + Large Wormface）。
    两端页面都是「有 nameZh 就显示 nameZh」，于是用户会看到两张只有英文小字能区分的同名卡片，
    而且 Alabaster / Onyx 这一对是拿一个自认低置信的群体名盖掉了两个各自正确的名字。

    规则：按 name_evidence_rank 排序，只有**唯一的最强证据**那一条能留下 nameZh；
    并列最强（例如同为群体名）则全部让出。让出的一条退回 english-only
    （两端既有的「仅英文名」徽标会自动挂上），候选词条记进 nameZhRejected 不丢证据。
    """
    by_zh: dict[str, list[dict]] = defaultdict(list)
    for e in entries:
        if e["nameZh"]:
            by_zh[e["nameZh"]].append(e)
    for zh, group in sorted(by_zh.items()):
        if len(group) < 2:
            continue
        ranks = [name_evidence_rank(e) for e in group]
        top = max(ranks)
        keeper = group[ranks.index(top)] if ranks.count(top) == 1 else None
        for e in group:
            if e is keeper:
                continue
            ev = e["nameEvidence"]
            reason = (f"同一条游戏文本会同时落到 {len(group)} 组首领头上"
                      f"（{'、'.join(x['nameEn'] for x in group)}），"
                      + (f"其中「{keeper['nameEn']}」的证据更强（逐字命中或词条属于它自己的 chrId），"
                         f"本组让出 nameZh。" if keeper else
                         "几组的证据强度相同（都是近似匹配的群体名/中心词），全部让出 nameZh。"))
            if ev:
                e["nameZhRejected"] = {**ev, "reason": reason}
                note = (f"游戏文本里唯一的候选是 NpcName {ev['id']}"
                        f"「{ev['en']} / {ev['zh']}」，但{reason}"
                        f"本组保留英文名，旧译名（如有）在 nameZhFallback。")
                # 解析阶段那条 note 讲的就是这次被否掉的匹配，直接换掉；
                # 只有社区来源的说明（讲「这是谁」）才保留并接在后面。
                e["nameNote"] = (f"{note} {e['nameNote']}".strip()
                                 if e["nameSourceUrl"] else note)
            e["nameZh"] = ""
            e["nameSource"] = "english-only"
            e["npcNameId"] = None            # 这里的类型是 int|null，不能写成空串
            e["nameEvidence"] = None
            e["nameApprox"] = False
            # 这一条**不进 unmatchedNames**：它在游戏文本里是匹配上了的，只是因为
            # 同名去重让出了 nameZh。两类混在一起会让「查无此名」的条数虚高 4 条，
            # 页面也没法区分「没有文本」和「有文本但让给了别人」。明细只进 nameCollisions。
            report["nameCollisions"].append({
                "nameZh": zh,
                "keptBy": f"{keeper['nameEn']}@{keeper['chrIds'][0]}" if keeper else None,
                "releasedBy": f"{e['nameEn']}@{e['chrIds'][0]}",
                "chrIds": list(e["chrIds"]),
                "candidate": e["nameZhRejected"],
                "reason": reason,
            })


def build_night_bosses(raw: Path, npc_rows: list[dict], scaling: Scaling, perm: PermScaling,
                       depth: DepthScaling, mutations: Mutations,
                       claimed: set[int], report: dict) -> list[dict]:
    book = NameBook(raw)
    groups: dict[tuple[str, int], list[tuple[dict, str, str]]] = defaultdict(list)

    # 无名行的兜底基础名：先在更细的 ID 前缀（npcId // 1000）里找有名的兄弟行，
    # 再退回 chrId 级。同一 chrId 下可能住着好几个不同 Boss（5081-0-xx 是血怪之首、
    # 5081-1-xx 是紫怪之首；4420-3-xx 是冰霜螯虾而不是巨型螯虾），只按 chrId 兜底会错配。
    prefix_base: dict[int, str] = {}
    chr_base: dict[int, str] = {}
    for r in sorted(npc_rows, key=lambda r: int(r["ID"])):
        if r["Name"]:
            b = base_and_variant(r["Name"])[0]
            b = BASE_ALIAS.get(b, b)
            prefix_base.setdefault(int(r["ID"]) // 1000, b)
            chr_base.setdefault(int(r["ID"]) // 10000, b)

    # 每组名字的来源：paramdex（本组自带行名）/ npcname（该 chrId 的游戏文本）/
    # sibling（借了兄弟行的 Paramdex 名，有错配风险）/ placeholder（两边都没有）
    base_sources: dict[tuple[str, int], set[str]] = defaultdict(set)
    for r in npc_rows:
        npc_id = int(r["ID"])
        mpc = int(r["multiPlayCorrectionParamId"])
        if mpc not in FIELD_THREAT and mpc not in NIGHT_THREAT:
            continue
        chr_id = npc_id // 10000
        if npc_id < 100000 or npc_id % 10000 == 9999 or num(r["hp"]) <= 0 or is_template(r):
            # 辅助 NPC（[Caligo Raid] Helper）、调试行（…9999）、无血量的场景实体、
            # Paramdex 模板行（行名以「- Template」结尾）
            reason = ("辅助/召唤实体（ID < 100000）" if npc_id < 100000 else
                      "调试/模板行（ID 以 9999 结尾）" if npc_id % 10000 == 9999 else
                      "hp 为 0 的场景实体" if num(r["hp"]) <= 0 else
                      "Paramdex 模板行（行名以「- Template」结尾，getSoul=0、"
                      "rewardItemLot/chaosMatchingRewardLotId/itemLotId_enemy 全为 -1，"
                      "与同组真实行数值相同但 chaosMatchingCorrectParamId 不同，不是实战行）")
            report["skippedRows"].append({"npcId": npc_id, "name": r["Name"] or None,
                                          "chrId": chr_id, "hp": num(r["hp"]),
                                          "scalingId": mpc, "reason": reason})
            continue
        if chr_id in claimed:                     # 夜王阵营的行放在 nightlords 里
            continue
        base, variant = base_and_variant(r["Name"])
        base = BASE_ALIAS.get(base, base)
        base_source = "paramdex"
        if not base:
            base = prefix_base.get(npc_id // 1000) or chr_base.get(chr_id) or ""
            base_source = "sibling"
            if not base:
                fallback = book.by_chr.get(chr_id)
                if fallback:
                    base, base_source = book.en[fallback[0]], "npcname"
                else:
                    # Paramdex 与 NpcName 都没有名字：先看社区资料能不能认出这是谁
                    # （schemaVersion 3；只用来认身份，中文名仍然只从 FMG 取），
                    # 认不出来就用 chrId 兜底保留，别静默丢掉（例如 c4504 的 45040000，
                    # 有效血量 12440，是守夜档位里最高的几行之一）。
                    comm = COMMUNITY_CHR.get(chr_id)
                    if comm and comm.get("nameEn"):
                        base, base_source = comm["nameEn"], "community"
                    else:
                        base, base_source = f"Unknown Enemy (c{chr_id})", "placeholder"
        base_sources[(base, chr_id)].add(base_source)
        groups[(base, chr_id)].append((r, base, variant))

    # 每个 chrId 自己的 Paramdex 基础名（含没进 groups 的行），供 NameBook 判断归属
    chr_bases: dict[int, set[str]] = defaultdict(set)
    for r in npc_rows:
        if r["Name"]:
            b = base_and_variant(r["Name"])[0]
            chr_bases[int(r["ID"]) // 10000].add(norm(BASE_ALIAS.get(b, b)))
    book.chr_bases = dict(chr_bases)

    out: list[dict] = []
    for (base, chr_id), items in groups.items():
        name_ids = {r["nameId"] for r, _, _ in items if r["nameId"] not in ("0", "-1", "")}
        comm = COMMUNITY_CHR.get(chr_id)
        # 社区资料只有在真的给出名字时才参与解析；只有「判断」没有名字的
        # （c7931 / c7932）走原来的 chrid-fallback，保留「未知敌人 cXXXX」。
        res = book.resolve(base, chr_id, name_ids, comm if (comm or {}).get("nameEn") else None)
        name_zh, name_en = res["nameZh"], res["nameEn"]
        source, name_id = res["nameSource"], res["npcNameId"]
        note, source_url = res["note"], res["sourceUrl"]
        # 【名字】「未知敌人 cXXXX」是生成器拼出来的占位串，游戏文本里没有这个词条，
        # 所以它**不能进 nameZh**（nameZh 的契约是「只来自游戏自带文本」）。
        # 放进 displayFallbackZh：页面在 nameZh 为空时可以拿它当显示名，但要清楚
        # 这不是游戏里的名字（nameSource = chrid-fallback，两端的「无游戏内名称」徽标会挂上）。
        display_fallback_zh = ""
        if base.startswith("Unknown Enemy (c") and source == "english-only":
            name_zh, source = "", "chrid-fallback"
            display_fallback_zh = f"未知敌人 c{chr_id}"
            if comm:
                note = note or comm.get("note", "")
                source_url = source_url or COMMUNITY_SOURCE_URL
        if source == "english-only":
            report["unmatchedNames"].append({"nameEn": name_en, "chrId": chr_id})
        srcs = base_sources[(base, chr_id)]
        inferred = res["inferred"] or ("paramdex" not in srcs and "sibling" in srcs)
        # 基础名本身来自社区认定时，即使中文是从 FMG 取到的也要标出来源
        if "community" in srcs and source.startswith("npcname") and comm:
            source = "community-npcname"
            note = note or comm.get("note", "")
            source_url = source_url or COMMUNITY_SOURCE_URL

        # 「明显不是首领」的判据（结构性，不是手挑）：整组没有任何奖励
        # （getSoul / chaosMatchingRewardLotId / itemLotId_enemy 全是 0 或 -1），
        # 并且要么不吃削韧（superArmorDurability <= 0，典型的投射物/部件实体），
        # 要么连游戏文本带社区资料都认不出是谁，要么社区把它标成杂兵。
        rows_all = [r for r, _, _ in items]
        no_reward = rows_no_reward(rows_all)
        max_poise = max(num(r["superArmorDurability"]) for r in rows_all)
        comm_role = (comm or {}).get("role")
        hidden = bool(no_reward and (max_poise <= 0 or source == "chrid-fallback"
                                     or comm_role == "add"))

        buckets: dict[tuple, list[tuple[dict, str]]] = defaultdict(list)
        tiers: set[str] = set()
        for r, _, variant in items:
            mpc = int(r["multiPlayCorrectionParamId"])
            tier = "night" if mpc in NIGHT_THREAT else "field"
            tiers.add(tier)
            stats = fight_stats(r, scaling, perm, depth, mutations)
            buckets[merge_key(stats, (tier,))].append((r, variant))

        variants = []
        for rows in buckets.values():
            rows.sort(key=lambda rv: int(rv[0]["ID"]))
            # 代表行优先取有 Paramdex 行名、且不是模板行的那一条
            rep, variant = max(rows, key=lambda rv: (bool(rv[0]["Name"]),
                                                     "Template" not in rv[1],
                                                     len(rv[1]), -int(rv[0]["ID"])))
            mpc = int(rep["multiPlayCorrectionParamId"])
            v = {
                "npcId": int(rep["ID"]),
                "npcIds": [int(r["ID"]) for r, _ in rows],
                "paramdexName": rep["Name"] or None,
                "labelZh": variant_zh(variant) or "基准",
                "labelEn": variant or "Base",
                "labelUncertain": "?" in (rep["Name"] or ""),
                "threat": "night" if mpc in NIGHT_THREAT else "field",
                # schemaVersion 3：行级「不掉任何奖励」。两端选「代表行」时可以拿它
                # 把模板行/投射物行排在同血量的实战行之后，而不必去猜 Paramdex 行名。
                "noReward": rows_no_reward([r for r, _ in rows]),
            }
            v.update(fight_stats(rep, scaling, perm, depth, mutations))
            v["mutationPool"] = sorted({m for r, _ in rows
                                        for m in [mutations.get(r.get("chaosMatchingSpEffectSetParamId", "-1"))]
                                        if m is not None})
            variants.append(v)
        disambiguate(variants)
        variants.sort(key=lambda v: (v["threat"] != "night", -v["hp"], v["npcId"]))

        out.append({
            "nameEn": name_en,
            "nameZh": name_zh,
            "nameSource": source,
            "nameInferred": inferred,
            "npcNameId": int(name_id) if name_id else None,
            "chrIds": [chr_id],
            "tier": "night" if "night" in tiers else "field",
            "tiers": sorted(tiers),
            "variants": variants,
            # ---- schemaVersion 3 新增
            "nameApprox": res["approx"],
            "nameEvidence": res["evidence"],
            "nameNote": note,
            "nameSourceUrl": source_url,
            "nameZhFallback": "",
            "nameZhFallbackNote": "",
            # schemaVersion 3：nameZh 为空时的纯显示用占位名（生成器拼的「未知敌人 cXXXX」），
            # **不是游戏文本、也不是译名**，与 nameZhFallback（《艾尔登法环》旧译名）分开放。
            "displayFallbackZh": display_fallback_zh,
            # schemaVersion 3：被「同名去重」挡下来的候选词条（见 resolve_name_collisions）
            "nameZhRejected": None,
            "hidden": hidden,
            "noReward": no_reward,
        })

    # 同名同中文名的组（同一 Boss 分散在多个 chrId）合并成一条
    merged: dict[tuple[str, str], dict] = {}
    for e in out:
        key = (e["nameEn"], e["nameZh"])
        cur = merged.get(key)
        if cur is None:
            merged[key] = e
            continue
        cur["chrIds"] = sorted(set(cur["chrIds"]) | set(e["chrIds"]))
        cur["tiers"] = sorted(set(cur["tiers"]) | set(e["tiers"]))
        cur["tier"] = "night" if "night" in cur["tiers"] else "field"
        cur["nameInferred"] = cur["nameInferred"] or e["nameInferred"]
        cur["nameApprox"] = cur["nameApprox"] or e["nameApprox"]
        cur["hidden"] = cur["hidden"] and e["hidden"]
        cur["noReward"] = cur["noReward"] and e["noReward"]
        cur["nameNote"] = cur["nameNote"] or e["nameNote"]
        cur["nameSourceUrl"] = cur["nameSourceUrl"] or e["nameSourceUrl"]
        cur["nameEvidence"] = cur["nameEvidence"] or e["nameEvidence"]
        cur["nameZhFallback"] = cur["nameZhFallback"] or e["nameZhFallback"]
        cur["nameZhFallbackNote"] = cur["nameZhFallbackNote"] or e["nameZhFallbackNote"]
        cur["displayFallbackZh"] = cur["displayFallbackZh"] or e["displayFallbackZh"]
        cur["nameZhRejected"] = cur["nameZhRejected"] or e["nameZhRejected"]
        cur["variants"].extend(e["variants"])
    out = list(merged.values())

    # 【名字·同名去重】必须放在上面的 (nameEn, nameZh) 合并之后：同一只 Boss 分散在
    # 多个 chrId 时（王室幽魂 c4020+c4021、黑夜人偶十个角色各有 c60003/c61003 两组）
    # 合并前看起来就是「同名的两组」，在这之前去重会把它们全部误杀。
    # 合并之后还同名的，才是真正的两只不同 Boss 抢同一条游戏文本。
    resolve_name_collisions(out, report)
    for e in out:
        e["nameZhFallback"], e["nameZhFallbackNote"] = fallback_zh(e["nameEn"], e["nameZh"])

    for e in out:                        # 跨 chrId 合并后可能又撞车
        disambiguate(e["variants"])
        e["variants"].sort(key=lambda v: (v["threat"] != "night", -v["hp"], v["npcId"]))

    # nameEn 不唯一（chr 4500「丘陵飞龙」与 chr 4505「飞龙」的 Paramdex 基础名都是
    # Flying Dragon），给前端一个显式主键
    for e in out:
        e["id"] = f"{e['nameEn']}@{e['chrIds'][0]}"
    ids = [e["id"] for e in out]
    assert len(ids) == len(set(ids)), "nightBosses.id 不唯一"

    out.sort(key=lambda e: (e["tier"] != "night", e["nameEn"], e["chrIds"][0]))
    return out


# schemaVersion 2 里的简中名，只列出本次会变的那几条。写死在这里是为了让
# notes.nameChanges 可复现（不依赖上一版的 JSON 文件），同时在生成时做自检：
# 如果新的解析规则跑出来的名字和 "new" 对不上就直接报错，防止悄悄漂移。
V2_TO_V3_NAMES = [
    # (id, 旧简中名, 新简中名, 依据)
    ("Snowfield Troll@4602", "雪原山妖群", "雪原山妖",
     "旧规则在同 chrId 下只找到群体词条 NpcName 904602000「Snowfield Trolls / 雪原山妖群」；"
     "新规则先做全局精确匹配，命中 904601001「Snowfield Troll / 雪原山妖」（单数）。"),
    ("Miranda Blossom@4480", "米兰达之花群", "米兰达之花",
     "NpcName 904480200 与 904480311 的英文都是「Miranda Blossom」，但前者简中是"
     "「米兰达之花群」、后者是「米兰达之花」；新规则在同一英文名的候选里优先取"
     "不带「群/们/队」后缀的那条。"),
]


def name_changes(night_bosses: list[dict]) -> list[dict]:
    """本次（schemaVersion 2 → 3）的名字变更清单。"""
    by_id = {e["id"]: e for e in night_bosses}
    out: list[dict] = []

    # 1) 删掉的 14 条手工译名
    for e in night_bosses:
        old_zh = REMOVED_MANUAL_ZH.get(e["nameEn"])
        if old_zh is None or e["nameSource"] == "manual":
            continue
        if e["nameEvidence"]:
            replacement = (
                f"改用游戏文本 NpcName {e['nameEvidence']['id']}"
                f"「{e['nameEvidence']['en']} / {e['nameEvidence']['zh']}」"
                + ("（中心词近似匹配，已标 nameApprox）。" if e["nameApprox"] else "。"))
        elif e["nameZhRejected"]:
            rej = e["nameZhRejected"]
            replacement = (
                f"游戏文本里唯一的候选是 NpcName {rej['id']}「{rej['en']} / {rej['zh']}」，"
                f"但{rej['reason']}为避免两张卡顶同一个中文名，nameZh 留空、只保留 nameEn；"
                f"旧译名移到 nameZhFallback（已标明不是游戏内文本），候选词条记在 nameZhRejected。")
        else:
            replacement = (
                f"游戏文本里找不到对应词条，nameZh 留空、只保留 nameEn；"
                f"旧译名移到 nameZhFallback（已标明不是游戏内文本）。")
        out.append({
            "id": e["id"], "chrIds": e["chrIds"],
            "oldNameEn": e["nameEn"], "newNameEn": e["nameEn"],
            "oldNameZh": old_zh, "newNameZh": e["nameZh"],
            "oldNameSource": "manual", "newNameSource": e["nameSource"],
            "nameZhFallback": e["nameZhFallback"],
            "reason": (
                f"v2 的「{old_zh}」是按《艾尔登法环》官方简中手工补的译名。"
                f"在全部 FMG（engus/zhocn、55 个文件）里检索「{old_zh}」与「{e['nameEn']}」"
                f"都没有完全一致的字符串，按新规则删除。" + replacement
            ),
            "evidence": e["nameEvidence"] or e["nameZhRejected"],
        })

    # 2) 社区认出身份的 7 个 chrId
    for chr_id, comm in sorted(COMMUNITY_CHR.items()):
        hit = next((e for e in night_bosses if chr_id in e["chrIds"]), None)
        if hit is None:
            continue
        out.append({
            "id": hit["id"], "chrIds": hit["chrIds"],
            "oldNameEn": f"Unknown Enemy (c{chr_id})", "newNameEn": hit["nameEn"],
            "oldNameZh": f"未知敌人 c{chr_id}", "newNameZh": hit["nameZh"],
            "oldNameSource": "chrid-fallback", "newNameSource": hit["nameSource"],
            "displayFallbackZh": hit["displayFallbackZh"],
            "reason": (("社区资料也认不出这是谁，身份仍然未知；本次的变化是 nameZh 清空 —— "
                        f"「未知敌人 c{chr_id}」是生成器拼出来的占位串、不是游戏文本，"
                        "按「nameZh 只来自游戏自带文本」的规则移到 displayFallbackZh（纯显示兜底），"
                        "另外新增了 hidden 标记与判断说明："
                        if not comm.get("nameEn") else "") + comm["note"]),
            "confidence": comm["confidence"],
            "hidden": hit["hidden"],
            "sourceUrl": COMMUNITY_SOURCE_URL,
            "evidence": hit["nameEvidence"],
        })

    # 3) 匹配规则变严带来的修正（单复数 / 群体词条）
    for gid, old_zh, new_zh, reason in V2_TO_V3_NAMES:
        e = by_id.get(gid)
        if e is None:
            continue
        assert e["nameZh"] == new_zh, f"{gid} 期望简中名 {new_zh}，实际 {e['nameZh']}"
        out.append({
            "id": gid, "chrIds": e["chrIds"],
            "oldNameEn": e["nameEn"], "newNameEn": e["nameEn"],
            "oldNameZh": old_zh, "newNameZh": new_zh,
            "oldNameSource": "npcname", "newNameSource": e["nameSource"],
            "reason": reason, "evidence": e["nameEvidence"],
        })
    out.sort(key=lambda c: (c["chrIds"][0], c["id"]))
    return out


def build_multiplayer_audit(m: dict) -> list[str]:
    """notes.multiplayerScalingAudit。带条数的几句由 m 里的实测值拼出。"""
    return [
    "结论：多人**不是**简单地「血量乘人数」。把 MultiPlayCorrectionParam 每一行的 "
    "client1（双人）/ client2（三人）指向的 SpEffect 整行摊开（scalingTiers.*.fullEffects.fields "
    "里是全部非默认字段），一共只动这几类：maxHpRate（血量）、saReceiveDamageRate（承受削韧）、"
    "changeSaRecoveryVelocity（削韧恢复速度）、七种 *DefDamageRate（异常累积量）、"
    "四种 *DamageRate（异常发动伤害）、以及少数档位的五种 *AttackPowerRate（敌人攻击力）。"
    f"**另有 6 个非倍率的列在全部 {m['mpRows']} 条人数缩放 SpEffect 上都是非默认值**，"
    "fullEffects.fields 里原样带着，千万不要当成倍率乘进去："
    "作用目标标记位 effectTargetFriendlyTarget / effectTargetOpposeTarget / "
    "magParamChange / miracleParamChange **四项恒为 1**（0/1 的开关位，"
    "意思是「这条效果对友方/敌方生效、会被魔法与祷告的参数变化影响」，不是 ×1 的倍率）；"
    f"再加上 spCategory 恒为 {m['mpSpCategory']}（「人数缩放」这个互相覆盖分类的编号）"
    f"与 stateInfo 恒为 {m['mpStateInfo']}（状态号）两个枚举。"
    "每个 fullEffects 都带了 fieldUnits，逐列给出 multiplier / percent / flag / enum 四种量纲——"
    "同一个 fields 对象里 maxHpRate = 1.1 是倍率、bloodDamageRate = 98 是百分数，"
    "不查 fieldUnits 会直接读错一个数量级。"
    "全表另有 Spirit Creatures（7770–7779）用的 45696/45697 两行带 "
    "invocationConditionsStateChange1 = 413，这几个档位本数据集一行都没用到，不在 scalingTiers 里。",
    "血量倍率按档位差别很大，并不都是 ×2 / ×3：最终 Boss（7760–7769）与部分守夜档确实是 "
    "×2 / ×3；但野外 Boss 常见档 7740 只有 ×1.1 / ×1.2，7743/7749/7750 是 ×1.3 / ×1.6，"
    "7744/7753/7754/7758 是 ×1.74 / ×2.48，联机突袭档 98818 是 ×1.35 / ×1.7、98822 是 ×1.75 / ×2.5，"
    "98810/98815（格拉狄乌斯/哈尔莫妮亚突袭）甚至是 ×1 / ×1（完全不加血）。",
    "**多人会让敌人打得更疼**：7744（野外 Boss）与 7753 / 7754 / 7758（守夜 Boss）四档的缩放行 "
    "physicsAttackPowerRate = magic = fire = thunder = dark = 1.1（双人）/ 1.2（三人），"
    "也就是这些 Boss 在多人时攻击力上浮 10% / 20%。其余档位攻击力倍率都是 1。"
    "staminaAttackRate（对玩家耐力的削减）在所有人数缩放行里都是 1，没有变化。",
    "**防御侧完全没动**：physicsDiffenceRate / magicDiffenceRate / fireDiffenceRate / "
    "thunderDiffenceRate / darkDiffenceRate、defEnemyDmgCorrectRate_* 全部保持默认 1，"
    "也就是多人不会让 Boss 变得更耐打（每一刀的伤害不变，只是血条更长）。"
    "NpcParam 的 *DamageCutRate（damageRates）也不受人数影响。",
    "**掉落与卢恩没动**：haveSoulRate、itemDropRate 都是默认值，人数缩放行不碰它们；"
    "多人时的奖励差异来自别处（MultiSoulBonusRateParam 等），不在本数据集范围内。",
    "**异常阈值没动**：change*ResistPoint 七项全是 0，多人不改 resist 阈值；"
    "变的是「累积量倍率」*DefDamageRate（双人 0.85–0.985 / 三人 0.7–0.97，按档位）"
    "与「发动伤害倍率」*DamageRate（双人 75–98% / 三人 50–97%），两者都往下走，"
    "所以人越多越难让 Boss 中异常、中了也更弱。",
    "叠加方式是**相乘不是相加**：人数缩放行的 spCategory = 140，常驻威胁档位与深度缩放行的 "
    "spCategory = 0，变异个体是 203 —— Paramdex 的 paramdef 说明 spCategory 是"
    "「决定特殊效果互相覆盖行为的分类」、categoryPriority 是「同一分类内的优先级」，"
    "分类不同就不会互相覆盖，各自的 maxHpRate 等倍率连乘。同一分类里才会按优先级只留一个"
    "（双人/三人两行都是 140，正好保证同时只有一档生效）。"
    "注意 **0 不是一个分类**（表示不参与覆盖），所以同为 0 的常驻档位、深度行与 "
    "[DLC Deep of Night Scaling] 行仍然各自生效，见 notes.deepOfNightAudit。",
    "实测核对（Fextralife 各 Boss 页，2026-09）：格拉狄乌斯 11,328 / 22,656 / 33,984、"
    "永夜之王格拉狄乌斯 17,558 / 35,116 / 52,674、艾德雷 13,140 / 26,280 / 39,420 —— "
    "与本数据集逐位一致；卡莉果 Fextralife 记 12,007 / 24,014 / 36,021，本数据集 "
    "12,008 / 24,016 / 36,024，差异来自 hpBase × hpMultiplier = 3392 × 3.54 = 12007.68 "
    "的取整方式（本数据集四舍五入，Fextralife 截断），不是缩放逻辑的分歧。"
    "削韧（格拉狄乌斯 120 / 艾德雷 150 / 卡莉果 160）与八系承伤倍率也逐项对上。",
    "MultiPlayCorrectionParam 还有 client3SpEffectId（4 人档），NIGHTREIGN 整表都是 -1，"
    "对应游戏最多 3 人；fullEffects.quad 因此恒为 null。",
]

def build_deep_of_night_audit(m: dict) -> list[str]:
    """notes.deepOfNightAudit。带条数/权重的几句由 m 里的实测值拼出。"""
    return [
    "深夜（The Deep of Night，CL_MenuText 131150）的「深度」（Depth，131011）1–5 "
    "是通过 NpcParam.chaosMatchingCorrectParamId → ChaosMatchingCorrectParam 生效的："
    "该表的 spEffect00..spEffect04 就是深度 1..5 的 SpEffect 行，Paramdex 行名形如"
    f"「[Deep Night Scaling] Tier 3b, Depth 4」。整表 {m['chaosRows']} 行里 "
    f"{m['chaosEmptyRows']} 行（ID {m['chaosEmptyIds']}）的 spEffect00..04 全是 -1"
    f"（没有任何深度效果），其余 {m['chaosRows'] - m['chaosEmptyRows']} 行按 spEffect00 的 "
    f"Paramdex 行名归并成 **{m['chaosGroups']} 组**（以上都是生成时逐行数出来的）："
    + "、".join(m["chaosGroupNames"]) + "。"
    f"deepOfNightTiers 只收录数据集实际用到的 {m['depthIds']} 个 chaosCorrectId，没有悬空引用；"
    f"它们只对应 {m['depthLabels']} 种档位名（tierLabel）与 {m['depthTables']} 张互不相同的数值表，"
    "所以「22 档」这种说法是错的——键是 chaosCorrectId，不是档位。"
    f"其中 {m['depthUnnamedCount']} 个键（{m['depthUnnamedLabels']}）的 SpEffect 行名里没有 Tier 段，"
    "tier 为 null，请改用恒非空的 tierLabel（来源见 tierSource）。",
    "深度缩放行自身 stateInfo = 2287，也就是「进入深夜」这个状态是它们打上去的"
    "（敌人用的那 85 行全是 2287；只有玩家技能那 4 行 99000–99002 / 99010 是 0，"
    "本数据集一行都没用到）；"
    "NpcParam 上那些 invocationConditionsStateChange1 = 2287 的"
    "「[Deep of Night Everdark Scaling] / [DLC Deep of Night Scaling]」行随之点亮，"
    "作用是把永夜之王/DLC 的加成压回去（例如格拉狄乌斯 ×0.677）。"
    "**spCategory 并不是「三者各不相同」（v3 首版这句话是错的）**，实测逐行是："
    "深度缩放行 = 0；[Deep of Night Everdark Scaling]（7330–7348、7355/7356 共 19 行）= 20，"
    "其中 7342 / 7344 / 7355 / 7356 这 4 行 = 100；"
    "[DLC Deep of Night Scaling]（7395–7398 共 4 行）**也是 0**，与深度行同值。"
    "同为 0 并不构成冲突：Paramdex 的 paramdef 说 spCategory 是「决定特殊效果互相覆盖行为的分类」，"
    "**0 表示不参与覆盖**，所以它们与常驻威胁档位一起连乘是安全的。"
    "真正需要检查的是非 0 的分类——把数据集用到的全部 NpcParam 行逐行扫过，"
    "没有任何一行出现两条非中性效果共用同一个非 0 spCategory，hpMultiplier 这类连乘因此成立。",
    "所以 depthStats[N].hp = NpcParam.hp × 常驻档位倍率 × 深夜修正（有才乘）× 深度 N 的 maxHpRate。"
    "v2 的 deepOfNight 字段只算到「深夜修正」为止，没有乘深度倍率，"
    "现在 deepOfNight 保留原义（= 深夜基准，等价于深度倍率为 1 时的值），深度值在 depthStats 里。",
    "实战夜王走的是 **Tier 4a**（chaosCorrectId = 7767）：数据集里 27 条 isMain 夜王战斗行"
    "有 26 条是它（只有救世旗手哈尔莫妮亚的永夜虫 46410000 走 7760 = Tier 3f）。"
    "Tier 4a 深度 1→5 的血量倍率 1.25 / 1.4 / 1.57 / 1.95 / 2.16，"
    "攻击力倍率 1.25 / 1.55 / 1.92 / 2.83 / 3.31，"
    "承受削韧 0.88 / 0.87 / 0.86 / 0.85 / 0.84，对玩家耐力削减 1.15 / 1.2 / 1.3 / 1.45 / 1.5。"
    "注意攻击力涨得比血量快得多——深度 5 的伤害是深度 1 的 2.65 倍。",
    "**别按 ChaosMatchingCorrectParam 的行名段猜档位**：7760–7769 行名全是「Final Boss Threat」，"
    "但 7765 = Tier 2c、7766 = Tier 3e、7767 = Tier 4a，只有 7760–7764 / 7768 / 7769 是 Tier 3f"
    "（×1.3 / 1.378 / 1.461 / 1.636 / 1.718 血，×1.3 / 1.547 / 1.841 / 2.54 / 2.947 攻击）。"
    "本数据集里 Tier 3f 只挂在夜王的非主战行（召唤物 / 阶段实体）与上面那条永夜虫上。"
    "一律按每一行自己的 chaosCorrectId 查 deepOfNightTiers。",
    "档位之间差别不小：杂兵档 Tier 1（7700 段）深度 5 是 ×2.106 血 / ×3.6 伤害，"
    "守夜大型档 Tier 5a/5b/5c（7753/7754/7758）只有 ×1.6 血 / ×2.22 伤害，"
    "突袭档（[Gladius Raid] / [Harmonia Raid]）是 ×1.5 血 / ×1.85 伤害，"
    "[Caligo Raid] 各深度全是 ×1（完全不随深度变强）。"
    "夜王档 Tier 4a 是 ×2.16 血 / ×3.31 伤害，野外常见档 7740（Tier 3b）是 ×1.718 血 / ×2.947 伤害。",
    "「红化」在游戏内简中叫**变异个体**（CL_MenuText 138296「打败敌人的次数（变异个体）」、"
    "338806「已打倒变异个体」）。它走 NpcParam.chaosMatchingSpEffectSetParamId → "
    "SpEffectSetParam「Set: Deep Night Mutation - VFX + Scaling」："
    "spEffectId1 是红光 VFX 档位（4480–4483，vfxId 150050–150053），"
    "spEffectId2 是数值档位（7200/7210/7215/7220/7230/7240/7241），"
    "少数行还带 spEffectId3 = 4485（vfxId 150055）。",
    "变异的数值档位共 7 种：×2 血 ×2 伤害 ×2 卢恩（7200/7210）、×2 血 ×1.75 伤害（7215）、"
    "×1.8 血 ×1.75 伤害（7220）、×1.8 血 ×1.5 伤害（7241）、×1.65 血 ×1.5 伤害 ×1.6 卢恩（7230）、"
    "×1.15 血 ×1.15 伤害 ×1.35 卢恩（7240）。spCategory = 203，与深度（0）、常驻（0）、"
    "人数（140）都不同，所以变异倍率是在其它缩放之上**再乘一层**。",
    "哪些敌人能被变异：NpcParam 里 chaosMatchingSpEffectSetParamId != -1 的行都挂了变异档位"
    "（本数据集里每个 fight/variant 的 mutationSetId / mutationPool 就是它）。"
    "多少只会被变异由 ChaosMatchingMutationCategoryParam 决定：它按"
    "（敌人类别 × 地图）给出每个深度「被变异的个数」，不是百分比概率——"
    "例如宁姆韦德的场景头目（类别 120 / 地图 10）深度 1 是 0 只、深度 2–5 各 5 只，"
    "封印监牢首领（类别 160）同样深度 1 为 0、深度 2 起才有。"
    "也就是**深度 1 不会出现变异的场景头目/封印监牢首领**，深度 4 起据点首领的变异数量再上一档。",
    "ChaosMatchingMutationEnemyTableParam（3067 行）是「地图上哪些刷新点可以被变异」的表"
    "（categoryId + smallBaseId → SmallBaseMapVariationParam + modifierMapId），"
    "它按刷新点而不是按 NpcParam 行组织，没法直接对到某只 Boss，本数据集没有收录；"
    "能确定的只有类别层面的数量，见 mutationCategories。",
    "每个夜王在各深度的出现权重来自 NightBossMenuParam 的 depth1..5ChanceWeight，"
    "已写进每个 nightlords 条目的 depthChanceWeights。"
    "**v3 首版把它概括成「本体 1000/800/650/500/500、永夜 0/200/350/500/500」是错的**："
    f"{m['weightRows']} 条里只有 {m['weightRows'] - m['weightOffShape']} 条对得上，"
    f"另外 {m['weightOffShape']} 条（{m['weightOffShapeNames']}）完全不是这两串数。"
    "本次生成时逐条实测的结果：\n" + m["weightLines"] +
    "\n可以概括的只有「形状」而不是具体数字：本体形态是深度越深权重越低"
    "（相对 1000 : 800 : 650 : 500 : 500），永夜之王/救世旗手是深度 1 为 0、之后递增"
    "（相对 0 : 200 : 350 : 500 : 500），但每个夜王会按自己的基数整条缩放"
    "（玛利斯 ×0.5、哈尔莫妮亚 ×1.6），而 DLC 的史柴格斯（1120）与布德奇冥（700）"
    "**五个深度同一个值**，根本不走上面的形状。"
    "对全部 18 条都成立的只有一句：**深度 1 打不到永夜之王/救世旗手**（depth1 恒为 0）。"
    "页面要展示权重请直接读 depthChanceWeights，不要套用任何范例数列。"
    "守夜/野外 Boss 没有对应的按深度出现权重表（参数里只有变异数量），已写进 caveats。",
]


def build_depth_overview(raw: Path) -> tuple[dict, list[dict], dict]:
    """→ (deepOfNightDepths, mutationCategories, deepOfNightText)

    deepOfNightDepths：ChaosMatchingRankControlParam 的 5 行（Paramdex 行名就是
    「Depth 1」…「Depth 5」），给出每个深度的全局控制值。字段含义来自 Paramdex Defs：
      cursedUncommonRate / cursedRareRate  诅咒（罕见/稀有）遗物的出现率
      mapChallengeWeight_Map/_Nightlord/_None  地图挑战类型的权重
      cataclysmWeight_0/_1/_2              天变（地形变化）数量 0/1/2 的权重
    这张表里**没有**血量/攻击倍率——那些在 ChaosMatchingCorrectParam 里，按敌人档位分，
    见 deepOfNightTiers 与每个 fight/variant 的 depthStats。
    """
    menu_zh = load_fmg(raw, "zhocn", "menu_dlc01", "CL_MenuText")
    menu_en = load_fmg(raw, "engus", "menu_dlc01", "CL_MenuText")
    text = {k: {"zh": menu_zh.get(v, ""), "en": menu_en.get(v, ""), "textId": int(v)}
            for k, v in DEEP_TEXT_IDS.items()}
    terrain = terrain_names(raw)

    depths: dict[str, dict] = {}
    for r in read_param(raw, "ChaosMatchingRankControlParam"):
        d = int(r["ID"])
        if d not in DEPTHS:
            continue
        depths[str(d)] = {
            "rankId": d,
            "paramdexName": r["Name"] or None,
            "labelZh": f'{text["depth"]["zh"]} {d}' if text["depth"]["zh"] else f"深度 {d}",
            "labelEn": f'{text["depth"]["en"]} {d}' if text["depth"]["en"] else f"Depth {d}",
            "cursedUncommonRate": num(r["cursedUncommonRate"]),
            "cursedRareRate": num(r["cursedRareRate"]),
            "mapChallengeWeight": {"map": num(r["mapChallengeWeight_Map"]),
                                   "nightlord": num(r["mapChallengeWeight_Nightlord"]),
                                   "none": num(r["mapChallengeWeight_None"])},
            "cataclysmWeight": {"0": num(r["cataclysmWeight_0"]),
                                "1": num(r["cataclysmWeight_1"]),
                                "2": num(r["cataclysmWeight_2"])},
        }

    cats: list[dict] = []
    for r in read_param(raw, "ChaosMatchingMutationCategoryParam"):
        cid = int(r["categoryId"])
        mid = int(r["modifierMapId"])
        czh, cen = MUTATION_CATEGORY_ZH.get(cid, (str(cid), str(cid)))
        mzh, men = MUTATION_MAP_ZH.get(mid, (str(mid), str(mid)))
        if 10 <= mid <= 15:
            mzh = terrain[mid - 10][0]
        cats.append({
            "rowId": int(r["ID"]),
            "categoryId": cid, "categoryZh": czh, "categoryEn": cen,
            "mapId": mid, "mapZh": mzh, "mapEn": men,
            # 注意：这些是「该深度会有多少只这一类敌人被变异」的**个数**，不是百分比概率
            "mutatedCount": {str(d): num(r[f"depth{d}Count"]) for d in DEPTHS},
        })
    cats.sort(key=lambda c: (c["categoryId"], c["mapId"]))
    return depths, cats, text


# ---------------------------------------------------------------- 实测统计


# v3 首版写死在 caveats / notes 里的两串「范例」权重。留着只为算出「有几条对不上」。
CANONICAL_DEPTH_WEIGHTS = ((1000, 800, 650, 500, 500), (0, 200, 350, 500, 500))


def measure(nightlords: list[dict], night_bosses: list[dict], scaling: "Scaling",
            depth: "DepthScaling", speffects: dict[str, dict]) -> dict:
    """从**刚生成出来的产物本身**数出 caveats / notes 里要引用的每一个数字。

    第二版复核报出的问题里有一半是「文字里的统计数字和数据本身对不上」
    （夜王深度权重 18 条错 6 条、deepOfNightTiers 被说成 22 档、nameZhFallback 的条数……）。
    根治办法不是把数字改对一次，而是**不写死**：这里实测一遍，文案用 f-string 拼。
    """
    m: dict = {}

    # ---- 夜王各深度出现权重（caveats / deepOfNightAudit）
    lines, shapes, off = [], set(), []
    for e in nightlords:
        w = tuple(e["depthChanceWeights"][str(d)] for d in DEPTHS)
        shapes.add(w)
        title = f"{e['nameZh']}（{e['variantNameZh']}）" if e["variantNameZh"] else e["nameZh"]
        lines.append(f"  {title}：" + " / ".join(str(x) for x in w))
        if w not in CANONICAL_DEPTH_WEIGHTS:
            off.append(title)
    m["weightRows"] = len(nightlords)
    m["weightShapes"] = len(shapes)
    m["weightLines"] = "\n".join(lines)
    m["weightOffShape"] = len(off)
    m["weightOffShapeNames"] = "、".join(off)

    # ---- deepOfNightTiers（caveats / deepOfNightAudit）
    ds = depth_tier_stats(depth.used)
    m["depthIds"] = ds["ids"]
    m["depthLabels"] = ds["labels"]
    m["depthTables"] = ds["tables"]
    m["depthNamedLabels"] = " / ".join(ds["namedLabels"])
    m["depthUnnamedCount"] = len(ds["unnamedLabels"])
    m["depthUnnamedLabels"] = " / ".join(ds["unnamedLabels"])

    # ---- ChaosMatchingCorrectParam 整表（deepOfNightAudit 第 1 条）
    empty, groups = [], defaultdict(list)
    for rid, row in depth.rows.items():
        eids = [row[f"spEffect0{i}"] for i in range(5)]
        if all(e in ("-1", "") for e in eids):
            empty.append(rid)
            continue
        name = (speffects.get(eids[0]) or {}).get("Name") or ""
        groups[re.sub(r",?\s*Depth \d+$", "", name)].append(rid)
    m["chaosRows"] = len(depth.rows)
    m["chaosEmptyRows"] = len(empty)
    m["chaosEmptyIds"] = "、".join(sorted(empty, key=int))
    m["chaosGroups"] = len(groups)
    # 展示时去掉共同前缀，可读性和 v3 首版手写的那串一致
    m["chaosGroupNames"] = [g.replace("[Deep Night Scaling] ", "") or "（无行名）"
                            for g in sorted(groups)]

    # ---- 人数缩放 SpEffect 整表（multiplayerScalingAudit 第 1 条）
    mp_ids = {v for r in scaling.mpc.values()
              for k in ("client1SpEffectId", "client2SpEffectId", "client3SpEffectId")
              for v in [r.get(k, "-1")] if v not in ("-1", "", "0")}
    m["mpRows"] = len(mp_ids)
    for col, key in (("spCategory", "mpSpCategory"), ("stateInfo", "mpStateInfo")):
        vals = {speffects[i][col] for i in mp_ids}
        assert len(vals) == 1, f"人数缩放行的 {col} 不唯一：{sorted(vals)}"
        m[key] = num(vals.pop())
    for col in ("effectTargetFriendlyTarget", "effectTargetOpposeTarget",
                "magParamChange", "miracleParamChange"):
        vals = {speffects[i][col] for i in mp_ids}
        assert vals == {"1"}, f"标记位 {col} 不是全表恒为 1：{sorted(vals)}"

    # ---- 名字相关条数（caveats【名字】几条）
    zh_empty = [e for e in night_bosses if not e["nameZh"]]
    no_fb = [e for e in zh_empty if not e["nameZhFallback"]]
    disp_fb = [e for e in night_bosses if e["displayFallbackZh"]]
    present = {e["nameEn"] for e in night_bosses} & set(REMOVED_MANUAL_ZH)
    m["manualCount"] = sum(1 for e in night_bosses if e["nameSource"] == "manual")
    m["removedManualTotal"] = len(REMOVED_MANUAL_ZH)
    m["manualPresent"] = len(present)
    m["zhEmpty"] = len(zh_empty)
    m["englishOnly"] = sum(1 for e in zh_empty if e["nameSource"] == "english-only")
    m["community"] = sum(1 for e in zh_empty if e["nameSource"].startswith("community"))
    m["chridFallback"] = sum(1 for e in zh_empty if e["nameSource"] == "chrid-fallback")
    m["fallbackCount"] = sum(1 for e in night_bosses if e["nameZhFallback"])
    m["zhEmptyNoFallback"] = len(no_fb)
    m["zhEmptyNoFallbackNames"] = "、".join(sorted(e["nameEn"] for e in no_fb))
    m["displayFallbackCount"] = len(disp_fb)
    m["displayFallbackNames"] = "、".join(sorted(e["displayFallbackZh"] for e in disp_fb))
    assert m["manualCount"] == 0, "schemaVersion 3 不应再产出 nameSource = manual"
    assert all(e["nameZh"] == "" for e in disp_fb), "displayFallbackZh 只在 nameZh 为空时才给"
    return m


# ---------------------------------------------------------------- 生成时自检


def self_check(payload: dict) -> int:
    """写文件前跑一遍契约自检，违反即抛 AssertionError（与 buffs / heroes 同一约定）。

    只钉「两端页面会直接依赖、且出错时很难被肉眼发现」的不变量。
    """
    n = 0

    def ok(cond, msg):
        nonlocal n
        assert cond, f"self_check 失败：{msg}"
        n += 1

    rows = [(f"夜王 {e['nameZh']}", f) for e in payload["nightlords"] for f in e["fights"]]
    rows += [(b["id"], v) for b in payload["nightBosses"] for v in b["variants"]]
    ok(rows, "至少要有一条战斗行")

    # ① 整数血量必须能由「hpBase × 同一条记录里公布的 hpMultiplier」逐位复现（见 hp_from）
    for tag, v in rows:
        ok(v["hp"] == hp_from(v["hpBase"], v["hpMultiplier"]),
           f"{tag} npcId {v['npcId']} 的 hp 与公布的 hpMultiplier 对不上")
        if v.get("deepOfNight"):
            d = v["deepOfNight"]
            ok(d["hp"] == hp_from(v["hpBase"], d["hpMultiplier"]),
               f"{tag} npcId {v['npcId']} 的 deepOfNight.hp 与 hpMultiplier 对不上")
        for k, d in (v.get("depthStats") or {}).items():
            ok(d["hp"] == hp_from(v["hpBase"], d["hpMultiplier"]),
               f"{tag} npcId {v['npcId']} 深度 {k} 的 hp 与 hpMultiplier 对不上")

    # ② 名字契约：nameZh 只来自游戏文本；兜底串各归各位
    zh_seen: dict[str, str] = {}
    for e in payload["nightBosses"]:
        ok(e["nameSource"] != "manual", f"{e['id']} 不应再产出 nameSource = manual")
        if e["nameZh"]:
            ok(e["nameZh"] not in zh_seen,
               f"简中名「{e['nameZh']}」同时挂在 {zh_seen.get(e['nameZh'])} 与 {e['id']} 上")
            zh_seen[e["nameZh"]] = e["id"]
            ok(not e["displayFallbackZh"], f"{e['id']} 有 nameZh 就不该再给 displayFallbackZh")
        if e["displayFallbackZh"]:
            ok(e["nameSource"] == "chrid-fallback",
               f"{e['id']} 的 displayFallbackZh 只应出现在 chrid-fallback 上")
        ok(not (e["nameZh"] and e["nameZh"] == e["nameZhFallback"]),
           f"{e['id']} 的 nameZhFallback 与 nameZh 重复")

    # ③ notes.unmatchedNames（查无此名）与 notes.nameCollisions（有文本但让出）不许重叠
    unmatched = {(u["nameEn"], u["chrId"]) for u in payload["notes"]["unmatchedNames"]}
    for c in payload["notes"]["nameCollisions"]:
        key = (c["releasedBy"].rsplit("@", 1)[0], c["chrIds"][0])
        ok(key not in unmatched,
           f"{c['releasedBy']} 是「匹配到了但让出」，不该同时记进 unmatchedNames")

    # ④ deepOfNightTiers：tier 允许为 null，tierLabel 必须恒非空
    for cid, t in payload["deepOfNightTiers"].items():
        ok(bool(t["tierLabel"]), f"deepOfNightTiers {cid} 的 tierLabel 为空")
        ok(t["tierSource"] in ("tierName", "rowName", "chaosCorrectId"),
           f"deepOfNightTiers {cid} 的 tierSource 取值非法：{t['tierSource']}")
        ok(len(t["depths"]) == len(DEPTHS), f"deepOfNightTiers {cid} 的深度不全")

    # ⑤ scalingTiers：fullEffects 的每一列都要有量纲说明
    for sid, tier in payload["scalingTiers"].items():
        full = tier["fullEffects"]
        units = full["fieldUnits"]
        for side in ("duo", "trio", "quad"):
            if not full[side]:
                continue
            miss = sorted(set(full[side]["fields"]) - set(units))
            ok(not miss, f"scalingTiers {sid} 的 {side} 有未标量纲的列：{miss}")
        ok(set(units.values()) <= {"multiplier", "percent", "flag", "enum"},
           f"scalingTiers {sid} 的 fieldUnits 出现未知量纲")

    # ⑥ 每条 caveat 都是非空字符串（页面直接整条渲染）
    ok(all(isinstance(c, str) and c.strip() for c in payload["caveats"]), "caveats 有空条目")

    # ⑦ 出场场合（schemaVersion 4）：取值合法、顺序规范、证据非空且能对回行与地图、汇总与实际一致
    valid = set(ROLE_ORDER)
    ok(list(payload["roleNames"]) == list(ROLE_ORDER), "roleNames 的键与 ROLE_ORDER 不一致")
    for k, v in payload["roleNames"].items():
        ok(all(isinstance(v[f], str) and v[f] for f in ("zh", "en", "description")),
           f"roleNames.{k} 有空字段")
    maps = payload["placementMaps"]
    map_kinds = {"overworldTile", "nightBossPiece", "smallBasePiece", "majorBaseDefault",
                 "inactivePiece", "nightlordArena", "otherMap"}
    for mname, info in maps.items():
        ok(info["kind"] in map_kinds, f"placementMaps.{mname} 的 kind 非法：{info['kind']}")
        ok(set(info["roles"]) <= valid, f"placementMaps.{mname} 的 roles 有非法取值")
        ok(list(info["evidence"]) == info["roles"], f"placementMaps.{mname} 的 evidence 键与 roles 不一致")
        ok(all(info["evidence"][r] for r in info["roles"]), f"placementMaps.{mname} 有空证据")
        ok(bool(info["roles"]) == (info["kind"] != "inactivePiece"),
           f"placementMaps.{mname}：只有 inactivePiece 允许没有场合")
        ok(info["kind"] != "inactivePiece" or bool(info.get("note")),
           f"placementMaps.{mname}：inactivePiece 必须写明为什么未启用")
        ok(info["kind"] != "majorBaseDefault" or
           any(e["table"] == "LotResultMapPatternFlag" for e in info["evidence"].get("event", [])),
           f"placementMaps.{mname}：大据点默认地块缺少陨石修饰的证据")
        ok(info["kind"] != "overworldTile" or set(info["roles"]) <= {"field", "mine", "stronghold"},
           f"placementMaps.{mname}：开放地块只能是 场景头目 / 坑道精英 / 据点首领")
        ok("mine" not in info["roles"] or info["evidence"]["mine"][0]["table"] == "ChaosMatchingMutationEnemyTableParam",
           f"placementMaps.{mname}：坑道精英必须以变异类别（150/151）为首条证据")
        ok("raid" not in info["roles"] or info["kind"] != "smallBasePiece" or
           any(e["table"] == "LotResultMapPatternFlag" and e["row"] == "targetBoss" for e in info["evidence"]["raid"]),
           f"placementMaps.{mname}：突袭地图块缺少 targetBoss 证据")

    def check_rows(tag: str, rows: list[dict]) -> None:
        for v in rows:
            roles = v["roles"]
            ok(roles and set(roles) <= valid, f"{tag} npcId {v['npcId']} 的 roles 为空或有非法取值：{roles}")
            ok(roles == [r for r in ROLE_ORDER if r in roles], f"{tag} npcId {v['npcId']} 的 roles 不是规范顺序或有重复")
            ok(list(v["roleEvidence"]) == roles, f"{tag} npcId {v['npcId']} 的 roleEvidence 键与 roles 不一致")
            ok(set(v["rowRoles"]) == {str(i) for i in v["npcIds"]},
               f"{tag} npcId {v['npcId']} 的 rowRoles 键与 npcIds 不一致")
            union = [r for r in ROLE_ORDER if any(r in rr for rr in v["rowRoles"].values())]
            ok(union == roles, f"{tag} npcId {v['npcId']} 的 rowRoles 并集与 roles 不一致")
            for nid, rr in v["rowRoles"].items():
                ok(rr and set(rr) <= valid and rr == [r for r in ROLE_ORDER if r in rr],
                   f"{tag} 行 {nid} 的 rowRoles 为空/非法/非规范顺序")
                ok("unplaced" not in rr or rr == ["unplaced"], f"{tag} 行 {nid}：unplaced 不应与其它场合并存")
                ok(not ("summon" in rr and "night" in rr), f"{tag} 行 {nid}：summon 不与 night 并存")
                ok(not ("summon" in rr and "field" in rr), f"{tag} 行 {nid}：summon 不与 field 并存")
                ok(not ("mine" in rr and "field" in rr), f"{tag} 行 {nid}：mine 不与 field 并存")
                ok(not ("prelude" in rr and "tower" in rr), f"{tag} 行 {nid}：prelude 不与 tower 并存"
                   "（前哨随地图块进高塔也不算高塔首领）")
            for r, items in v["roleEvidence"].items():
                ok(items, f"{tag} npcId {v['npcId']} 的 roleEvidence.{r} 为空")
                covered = set()
                for e in items:
                    ok(e["npcId"] in v["npcIds"], f"{tag} npcId {v['npcId']} 的证据指向不属于本变体的行 {e['npcId']}")
                    ok(all(isinstance(e[f], str) and e[f] for f in ("table", "row", "note")),
                       f"{tag} npcId {v['npcId']} 的 {r} 证据有空的 table/row/note")
                    ok(e["msb"] is None or e["msb"] in maps,
                       f"{tag} npcId {v['npcId']} 的证据地图 {e['msb']} 不在 placementMaps 里")
                    ok(r in v["rowRoles"][str(e["npcId"])], f"{tag} 行 {e['npcId']} 有 {r} 证据却没有该场合")
                    covered.add(e["npcId"])
                want = {int(k) for k, rr in v["rowRoles"].items() if r in rr}
                ok(covered == want, f"{tag} npcId {v['npcId']} 的 {r}：有行缺证据 {sorted(want - covered)}")

    for e in payload["nightlords"]:
        check_rows(f"夜王 {e['nameZh']}", e["fights"])
    for b in payload["nightBosses"]:
        check_rows(b["id"], b["variants"])
    groups = [(f"夜王 {e['nameZh']}", e, e["fights"]) for e in payload["nightlords"]]
    groups += [(b["id"], b, b["variants"]) for b in payload["nightBosses"]]
    for tag, g, rows in groups:
        ok(g["roles"] == [r for r in ROLE_ORDER if any(r in v["roles"] for v in rows)],
           f"{tag} 的 roles 不是其变体 roles 的并集")
        ok(list(g["roleVariants"]) == g["roles"], f"{tag} 的 roleVariants 键与 roles 不一致")
        by_npc = {v["npcId"]: v for v in rows}
        for r, ids in g["roleVariants"].items():
            ok(ids and all(i in by_npc and r in by_npc[i]["roles"] for i in ids),
               f"{tag} 的 roleVariants.{r} 为空或指向没有该场合的变体")
            ok(len(ids) == sum(1 for v in rows if r in v["roles"]), f"{tag} 的 roleVariants.{r} 漏了变体")
    recount = {r: sum(1 for b in payload["nightBosses"] if r in b["roles"]) for r in ROLE_ORDER}
    ok(payload["roleSummary"] == recount, f"roleSummary 与实际组数不一致：{payload['roleSummary']} vs {recount}")
    ok(all(payload["roleSummaryDetail"][r]["groups"] == recount[r] for r in ROLE_ORDER),
       "roleSummaryDetail.groups 与 roleSummary 不一致")
    ok(all(b["roles"] for b in payload["nightBosses"]), "有 nightBosses 分组没有任何场合")
    ex = payload["notes"]["roleAudit"]["examples"]
    ok(len(ex) == sum(len(ids) for _, ids in ROLE_EXAMPLES) and not any(e.get("missing") for e in ex),
       f"notes.roleAudit.examples 的条数（{len(ex)}）与 ROLE_EXAMPLES 不一致或有缺失")
    return n


# ---------------------------------------------------------------- 主流程


def main() -> None:
    ap = argparse.ArgumentParser(description="生成 NIGHTREIGN 首领数据集")
    ap.add_argument("--raw", type=Path, default=DEFAULT_RAW, help="raw/ 目录（含 params 与 msg）")
    ap.add_argument("--out", type=Path, default=DEFAULT_OUT, help="输出 JSON 路径")
    args = ap.parse_args()

    raw: Path = args.raw
    npc_rows = read_param(raw, "NpcParam")
    speffects = load_speffects(raw)
    defaults = speffect_defaults(speffects)
    scaling = Scaling(raw, speffects, defaults)
    perm = PermScaling(speffects)
    depth = DepthScaling(raw, speffects)
    mutations = Mutations(raw, speffects)
    report = {"skippedMenuRows": [], "skippedRows": [], "unmatchedNames": [],
              "missingZhNightlord": [], "unmappedNightlords": [],
              "unknownMenuVariants": [], "unassignedFinalBossRows": [],
              "nameCollisions": []}

    nightlords, claimed = build_nightlords(raw, npc_rows, scaling, perm, depth, mutations, report)
    night_bosses = build_night_bosses(raw, npc_rows, scaling, perm, depth, mutations, claimed, report)
    depth_overview, mutation_categories, deep_text = build_depth_overview(raw)
    report["skippedRows"].sort(key=lambda s: s["npcId"])
    report["unmatchedNames"].sort(key=lambda u: (u["chrId"], u["nameEn"]))
    report["unassignedFinalBossRows"].sort(key=lambda s: s["npcId"])
    # schemaVersion 4：出场场合（roles）。只在已有的 fight / variant / 分组上**追加**字段，
    # tier / tiers / 名字 / hidden / 数值一律不碰（annotate 只写 roles / roleEvidence /
    # rowRoles / roleVariants 四个新键）。
    placement = Placement(raw, npc_rows, claimed)
    placement.annotate(nightlords, night_bosses)
    role_counts, role_detail = role_summary(nightlords, night_bosses)
    role_audit = build_role_audit(night_bosses, placement, role_example_sources(raw))
    placement_maps = placement.placement_maps()
    # caveats / notes 里所有带数字的句子都从产物实测拼出，不写死（见 measure 的 docstring）
    stats = measure(nightlords, night_bosses, scaling, depth, speffects)
    stats.update(measure_roles(placement, role_counts, role_detail, placement_maps,
                               night_bosses, nightlords))
    map_zh = {c["mapId"]: c["mapZh"] for c in mutation_categories if 10 <= c["mapId"] <= 15}
    assert map_zh and all(map_zh.values()), f"mutationCategories 的 mapZh 有空值：{map_zh}"
    stats["mapZhAll"] = "、".join(f"{k} {v}" for k, v in sorted(map_zh.items()))
    stats["mapZhChanges"] = "、".join(f"「{MUTATION_MAP_ZH_V3[k]}」→「{v}」" for k, v in sorted(map_zh.items())
                                      if MUTATION_MAP_ZH_V3[k] != v) or "（无）"
    labels = [v["labelZh"] for b in night_bosses for v in b["variants"]] + \
             [f["labelZh"] for e in nightlords for f in e["fights"]]
    stats["labelZhChanges"] = "（" + "、".join(
        f"「{old}」→「{VARIANT_ZH[key]}」{sum(1 for x in labels if VARIANT_ZH[key] in x)} 个"
        for key, old in VARIANT_ZH_V3.items()) + "，含「火山口（雾门旁）」）"
    assert all(old not in x for x in labels for old in VARIANT_ZH_V3.values()), "labelZh 里还有 v3 的旧词"

    out = {
        "bossesSchemaVersion": SCHEMA_VERSION,
        "gameVersion": GAME_VERSION,
        "dataVersion": DATA_VERSION,
        "generatedAt": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "sources": [
            {
                "name": "ELDEN RING NIGHTREIGN regulation.bin",
                "url": "",
                "revision": "regulation 10350000 / exe 1.3.3.0",
                "license": "游戏本体数据，仅用于展示数值",
                "usage": "NightBossMenuParam / NpcParam / MultiPlayCorrectionParam / SpEffectParam"
                         " / SpEffectSetParam / ChaosMatchingCorrectParam"
                         " / ChaosMatchingRankControlParam / ChaosMatchingMutationCategoryParam",
            },
            {
                "name": "ELDEN RING NIGHTREIGN 游戏内文本 FMG（简体中文 / 英文）",
                "url": "",
                "revision": "regulation 10350000 + DLC1",
                "license": "游戏本体数据，仅用于展示名称",
                "usage": "menu/CL_MenuText（夜王名、远征名、说明、深夜/深度/变异个体）、"
                         "item/NpcName（Boss 名；所有简中名的唯一来源）",
            },
            {
                "name": "Smithbox Paramdex (NR)",
                "url": f"https://github.com/vawser/Smithbox/tree/{PARAMDEX_REV}/src/Smithbox.Data/Assets/PARAM/NR",
                "revision": PARAMDEX_REV,
                "license": "MIT",
                "usage": "paramdef 字段名、行名（Name 列）、EFFECTIVE_AFFINITY / "
                         "MUTATION_CATEGORY / PATTERN_MODIFIER 枚举、"
                         "SpEffectParam 的 spCategory/categoryPriority 字段说明（叠加规则）",
            },
            {
                "name": "4laric/nightreign-enemy-rando",
                "url": COMMUNITY_SOURCE_URL,
                "revision": "HEAD（2026-09 访问）",
                "license": "第三方社区数据，仅用于辨认 Paramdex 与游戏文本都没有名字的 chrId",
                "usage": "data/nr_enemy_roster.json（all_variants[].variant_name）与 "
                         "data/nr_enemy_tags.json（name / tier / _confidence）—— "
                         "c4504 / c4603 / c7711 / c7712 / c7910 的身份判断；"
                         "简中名仍然只从游戏文本取，社区来源在 nameSourceUrl 里标出",
            },
            {
                "name": "Elden Ring Nightreign Wiki (Fextralife)",
                "url": "https://eldenringnightreign.wiki.fextralife.com/",
                "revision": "2026-09 访问",
                "license": "第三方 wiki，仅作交叉验证",
                "usage": "格拉狄乌斯 / 永夜之王格拉狄乌斯 / 艾德雷 / 卡莉果 的 1/2/3 人血量、"
                         "削韧与八系承伤倍率 —— 用来核对本数据集的人数缩放，"
                         "结果见 notes.multiplayerScalingAudit",
            },
            # ---- schemaVersion 4：出场场合（roles）的来源，追加在末尾、不改前面各条
            {
                "name": "ELDEN RING NIGHTREIGN 地图 MSB（/map/mapstudio/*.msb.dcx）+ 远征生成参数",
                "url": "",
                "revision": "exe 1.3.3.0 / regulation 10350000 + DLC1（与参数同一次导出）",
                "license": "游戏本体数据，仅用于判定出场场合",
                "usage": "extract_msb.py 从 data0–3 / dlc01 归档解出全部地图 MSB，导出每个 Enemy / "
                         "DummyEnemy part 的 npcParamId（raw/msb/MsbEnemyParts.csv；布局对照 Smithbox "
                         "Documentation/Binary Templates/MSB/MSB_NR，同一修订）；地图块何时进入远征取自 "
                         "LotResultPlayAreaParam / LotResultSmallBaseAndSpot / SmallBaseAndSpotAttachPoint / "
                         "SmallBaseMapVariationParam / ChaosMatchingMutationEnemyTableParam / "
                         "LotResultMapPatternFlag / SmallBaseEnemyLotMapCombinationParam，入侵者取自 "
                         "SmallbaseInvationNpcParam；引用关系按 Paramdex Param Meta 的 Refs"
                         "（bossId1/2 → SmallBaseMapVariationParam 等）与 MUTATION_CATEGORY / "
                         "PATTERN_MODIFIER 枚举。只回答「这一行 NpcParam 在哪种场合出现」，数值仍全部来自参数表。"
                         "开放地图地块的变异类别按 ChaosMatchingMutationEnemyTableParam.mapUnk_1..3 解码出的地块号判定"
                         "（推断的解码，见 caveats【场合】开放地图地块）；突袭证据另读 LotResultMapPatternFlag.targetBoss"
                         "（Refs = NightBossMenuParam）；场合标签「场景头目」「坑道」取 TutorialBody 403200 的地图图标说明",
            },
        ],
        "affinityNames": {str(k): {"zh": v[0], "en": v[1]} for k, v in sorted(AFFINITY_NAMES.items())},
        "scalingTiers": {str(k): v for k, v in sorted(scaling.used.items())},
        "permanentScaling": {str(k): v for k, v in sorted(perm.used.items())},
        # ---- schemaVersion 3 新增的顶层键
        "deepOfNightText": deep_text,
        "deepOfNightDepths": depth_overview,
        "deepOfNightTiers": {str(k): v for k, v in sorted(depth.used.items())},
        "mutations": {str(k): v for k, v in sorted(mutations.used.items())},
        "mutationCategories": mutation_categories,
        # ---- schemaVersion 4 新增的顶层键（出场场合）
        "roleNames": role_names(),
        "roleSummary": role_counts,
        "roleSummaryDetail": role_detail,
        "placementMaps": placement_maps,
        "caveats": build_caveats(stats),
        "nightlords": nightlords,
        "nightBosses": night_bosses,
        "notes": {
            "unmatchedNames": report["unmatchedNames"],
            "skippedMenuRows": report["skippedMenuRows"],
            "skippedRows": report["skippedRows"],
            "unassignedFinalBossRows": report["unassignedFinalBossRows"],
            "nameChanges": name_changes(night_bosses),
            "nameCollisions": report["nameCollisions"],
            "multiplayerScalingAudit": build_multiplayer_audit(stats),
            "deepOfNightAudit": build_deep_of_night_audit(stats),
            "roleAudit": role_audit,
        },
    }

    checks = self_check(out)

    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(out, ensure_ascii=False, separators=(",", ":")) + "\n",
                        encoding="utf-8")

    n_fights = sum(len(e["fights"]) for e in nightlords)
    n_vars = sum(len(e["variants"]) for e in night_bosses)
    zh_ok = sum(1 for e in night_bosses if e["nameZh"])
    print(
        f"bosses.json：夜王 {len(nightlords)} 条（{n_fights} 个战斗行）、"
        f"守夜/野外 Boss {len(night_bosses)} 组（{n_vars} 个变体，{zh_ok} 组有简中名）、"
        f"缩放档位 {len(scaling.used)} 个 → {args.out}"
        f"（{args.out.stat().st_size // 1024} KB）"
    )
    print(f"  self_check：{checks} 项断言全过")
    if report["unmatchedNames"]:
        print("  未匹配到中文名：" + "、".join(u["nameEn"] for u in report["unmatchedNames"]))
    for s in report["skippedMenuRows"]:
        print(f"  跳过菜单行 {s['menuId']}（{s['name']}）：{s['reason']}")
    for s in report["unknownMenuVariants"]:
        print(f"  未知的夜王菜单变体前缀：{s}")
    if report["skippedRows"]:
        print(f"  notes.skippedRows：{len(report['skippedRows'])} 行（" +
              "、".join(str(s["npcId"]) for s in report["skippedRows"]) + "）")
    if report["unassignedFinalBossRows"]:
        print(f"  notes.unassignedFinalBossRows：{len(report['unassignedFinalBossRows'])} 行（" +
              "、".join(str(s["npcId"]) for s in report["unassignedFinalBossRows"]) + "）")
    print("  出场场合（nightBosses 组数）：" +
          "、".join(f"{ROLE_DEFS[r][0]} {n}" for r, n in role_counts.items() if n) +
          f"；地图 {len(placement_maps)} 张（MSB {placement.msb_maps} 张 / Enemy part {placement.msb_enemy} 个）")
    inferred = [e for e in night_bosses if e["nameInferred"]]
    if inferred:
        print(f"  名字按 ID 结构推断：{len(inferred)} 组（" +
              "、".join(e["nameZh"] or e["nameEn"] for e in inferred[:10]) + " …）")


if __name__ == "__main__":
    main()
