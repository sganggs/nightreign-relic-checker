#!/usr/bin/env python3
"""生成「首领数据」数据集（nightreign-bosses-v1.03.5.json）。

覆盖：8 个本体夜王 + DLC 的哈尔莫妮亚/史柴格斯 + 永夜之王（Everdark Sovereign）与
救世旗手（Salvation's Standard-Bearers）变体，
以及守夜 Boss（Night Boss Threat）与野外 Boss（Field Boss Threat）。
每条记录给出单人基准血量/韧性、八系承伤倍率、七种异常抗性阈值，
以及 2 人 / 3 人的血量与削韧、异常累积缩放。

上游数据（均已导出在 raw/ 下，不入 git）：
  raw/params/NightBossMenuParam.csv      夜王菜单（名称/远征/官方弱点标注）
  raw/params/NpcParam.csv                敌人实体数值（hp、削韧、承伤倍率、异常抗性）
  raw/params/MultiPlayCorrectionParam.csv 人数缩放：client1=双人 / client2=三人
  raw/params/SpEffectParam.csv           缩放倍率本体（maxHpRate / saReceiveDamageRate / *DamageRate）
  raw/msg/<lang>/menu_dlc01/CL_MenuText(.._dlc01).json  夜王名、远征名、夜王说明
  raw/msg/<lang>/item_dlc01/NpcName(.._dlc01).json      Boss 简中/英文名
  NpcParam/NightBossMenuParam 的 Name 列 = 社区 Paramdex 行名（vawser/Smithbox@f5969c0）

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

用法：
  cd macos/DataSources && python3 generate_bosses.py [--raw raw] [--out ../../data/nightreign-bosses-v1.03.5.json]
"""

from __future__ import annotations

import argparse
import csv
import json
import re
from collections import defaultdict
from datetime import datetime, timezone
from pathlib import Path

SCHEMA_VERSION = 2
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
    "Field Boss": "野外首领",
    "Night Boss": "守夜首领",
    "Night Group Boss": "守夜群体首领",
    "Duo Night Boss": "守夜双人组",
    "Night Boss Add": "守夜首领 · 召唤物",
    "Tutorial": "教程",
    "Crater": "陨石坑",
    "Noklateo": "诺克拉提欧",
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
    "Marsh Group Boss": "沼泽群体首领", "Crater by fog gate": "陨石坑（雾门旁）",
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

# 游戏文本里没有对应条目、按 Elden Ring 官方简中补的名字
ALIAS_MANUAL_ZH = {
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

FIELD_THREAT = range(7740, 7750)
NIGHT_THREAT = range(7750, 7760)

CAVEATS = [
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
    "个别条目游戏文本里没有对应词条，nameSource 会标成 manual（按 Elden Ring 官方简中补）、"
    "chrid-fallback（连英文名都没有，用 chrId 兜底）或 english-only（只有英文）；"
    "nameInferred = true 表示名字是按 ID 结构推断的。",
    "nightBosses 的主键是 id（形如 \"Flying Dragon@4500\"），nameEn 会重复"
    "（chr 4500「丘陵飞龙」与 chr 4505「飞龙」的 Paramdex 基础名都是 Flying Dragon），不要拿它当 key。",
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


class Scaling:
    """multiPlayCorrectionParamId → 双人/三人倍率。"""

    def __init__(self, raw: Path, sp: dict[str, dict]):
        self.mpc = {r["ID"]: r for r in read_param(raw, "MultiPlayCorrectionParam")}
        self.sp = sp
        self.used: dict[int, dict] = {}

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
        }

    def get(self, mpc_id: str) -> tuple[int | None, dict | None]:
        mid = int(mpc_id)
        if mid == 0 or mpc_id not in self.mpc:
            return None, None
        row = self.mpc[mpc_id]
        entry = {
            "group": row["Name"] or None,
            "duo": self._tier(self.sp.get(row["client1SpEffectId"])),
            "trio": self._tier(self.sp.get(row["client2SpEffectId"])),
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

    def _factors(self, e: dict) -> tuple[float, float, float, float]:
        return (
            float(e["maxHpRate"]),
            float(e["saReceiveDamageRate"]),
            float(e["changeSaRecoveryVelocity"]),
            float(e["bloodDamageRate"] or 100) / 100,
        )

    def _register(self, eid: int, e: dict, deep: bool) -> None:
        if eid in self.used:
            return
        hp, poise, recover, ail = self._factors(e)
        self.used[eid] = {
            "nameEn": e["Name"] or None,
            "nameZh": perm_label_zh(e["Name"], deep),
            "hp": num(str(hp)),
            "poiseTaken": num(str(poise)),
            "poiseRecover": num(str(recover)),
            "ailmentDamageRate": num(str(ail)),
            "deepOfNight": deep,
        }

    def of(self, row: dict) -> dict:
        """→ 常驻缩放汇总（含深夜档）。"""
        ids: list[int] = []
        deep_ids: list[int] = []
        hp = poise = recover = ail = 1.0
        d_hp = d_poise = d_recover = d_ail = 1.0
        for slot in self.SLOTS:
            v = row.get(slot)
            if v in (None, "", "0", "-1"):
                continue
            e = self.sp.get(v)
            if e is None:
                continue
            f = self._factors(e)
            if f == (1.0, 1.0, 1.0, 1.0):
                continue
            conds = [int(e[f"invocationConditionsStateChange{i}"]) for i in (1, 2, 3)]
            deep = DEEP_OF_NIGHT_STATE in conds
            if any(conds) and not deep:
                continue                      # 其它条件触发的效果不算常驻
            eid = int(v)
            self._register(eid, e, deep)
            if deep:
                deep_ids.append(eid)
                d_hp *= f[0]; d_poise *= f[1]; d_recover *= f[2]; d_ail *= f[3]
            else:
                ids.append(eid)
                hp *= f[0]; poise *= f[1]; recover *= f[2]; ail *= f[3]
        return {
            "ids": sorted(ids),
            "deepIds": sorted(deep_ids),
            # 有没有挂「[Everdark Sovereign Scaling] …」：部分永夜之王行的 Paramdex
            # 行名与本体一模一样（75000200 / 76001000），只能靠这个认出来
            "everdarkScaled": any(
                (self.used[i]["nameEn"] or "").startswith("[Everdark Sovereign Scaling]")
                for i in ids),
            "hpMultiplier": round(hp, 6),
            "poiseTakenBase": round(poise, 6),
            "poiseRecoverMultiplier": round(recover, 6),
            "ailmentDamageRateBase": round(ail, 6),
            "deep": None if not deep_ids else {
                "hpMultiplier": round(hp * d_hp, 6),
                "poiseTakenBase": round(poise * d_poise, 6),
                "poiseRecoverMultiplier": round(recover * d_recover, 6),
                "ailmentDamageRateBase": round(ail * d_ail, 6),
            },
        }


# ---------------------------------------------------------------- 战斗行构建


def fight_stats(row: dict, scaling: Scaling, perm: PermScaling) -> dict:
    rates = {out: num(row[f"{src}DamageCutRate"]) for out, src in DAMAGE_RATES}
    resist = {out: num(row[src]) for out, src in RESISTS}
    scaling_id, tiers = scaling.get(row["multiPlayCorrectionParamId"])
    p = perm.of(row)
    hp_base = num(row["hp"])
    deep = None
    if p["deep"]:
        deep = {
            "hp": round(hp_base * p["deep"]["hpMultiplier"]),
            "hpMultiplier": p["deep"]["hpMultiplier"],
            "poiseTakenBase": p["deep"]["poiseTakenBase"],
            "poiseRecoverMultiplier": p["deep"]["poiseRecoverMultiplier"],
            "ailmentDamageRateBase": p["deep"]["ailmentDamageRateBase"],
            "permScalingIds": p["ids"] + p["deepIds"],
        }
    return {
        # hp 是玩家真正要打掉的 1 人血量；hpBase 才是 NpcParam.hp 原始字段
        "hp": round(hp_base * p["hpMultiplier"]),
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
    )


# ---------------------------------------------------------------- 夜王


def build_nightlords(raw: Path, npc_rows: list[dict], scaling: Scaling, perm: PermScaling,
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
                stats = fight_stats(r, scaling, perm)
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
            }
            fight.update(fight_stats(rep, scaling, perm))
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
                "hp": round(num(r["hp"]) * p["hpMultiplier"]),
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
    """NpcName 文本 ID 形如 9 + chrId(5 位) + 3 位序号，用它把 Paramdex 名对上简中名。"""

    def __init__(self, raw: Path):
        self.en = load_fmg(raw, "engus", "item_dlc01", "NpcName")
        self.zh = load_fmg(raw, "zhocn", "item_dlc01", "NpcName")
        self.by_chr: dict[int, list[str]] = defaultdict(list)
        self.by_norm: dict[str, str] = {}
        for k, v in self.en.items():
            if len(k) == 9 and k[0] == "9":
                self.by_chr[int(k[1:6])].append(k)
            self.by_norm.setdefault(norm(v), k)
        for ids in self.by_chr.values():
            ids.sort(key=int)

    def _pick(self, base: str, chr_id: int) -> str | None:
        nb = norm(base)
        cands = self.by_chr.get(chr_id, [])
        for k in cands:                                   # 1) 精确
            if norm(self.en[k]) == nb:
                return k
        for k in cands:                                   # 2) 单复数
            nk = norm(self.en[k])
            if (nk.startswith(nb) or nb.startswith(nk)) and abs(len(nk) - len(nb)) <= 2:
                return k
        for k in cands:                                   # 3) 「XXX of the YYY」这类扩写
            nk = norm(self.en[k])
            if nk.startswith(nb + " ") or nb.endswith(" " + nk):
                return k
        return None

    def resolve(self, base: str, chr_id: int, name_ids: set[str]) -> tuple[str, str, str, str, bool]:
        """→ (nameZh, nameEn, nameSource, npcNameId, inferred)

        解析顺序：NpcParam.nameId（该组唯一且 >0 时）→ (chrId, 基础名) 别名表 →
        基础名别名表 → 同 chrId 精确/近似匹配 → 全局同名 → 手工表 → chrId 独苗。
        NpcParam.nameId 是游戏自己填的「这一行叫什么」，优先级最高：
        610030300「Duchess (Undertaker Remembrance)」的 nameId = 140030「黑夜盗贼」，
        而不是 Paramdex 行名暗示的职业名「女爵」。
        """
        if len(name_ids) == 1:
            k = next(iter(name_ids))
            if self.zh.get(k) or self.en.get(k):
                return self.zh.get(k, ""), self.en.get(k, base), "npcparam-nameid", k, False
        ck = (chr_id, base)
        if ck in ALIAS_NPCNAME_ID_BY_CHR:
            k = ALIAS_NPCNAME_ID_BY_CHR[ck]
            if self.zh.get(k) or self.en.get(k):
                return (self.zh.get(k, ""), self.en.get(k, base),
                        "npcname-alias-chr", k, ck in ALIAS_INFERRED)
        if base in ALIAS_NPCNAME_ID:
            k = ALIAS_NPCNAME_ID[base]
            return self.zh.get(k, ""), base, "npcname-alias", k, False
        k = self._pick(base, chr_id)
        if k is not None and self.zh.get(k):
            return self.zh[k], base, "npcname", k, False
        g = self.by_norm.get(norm(base))
        if g is not None and self.zh.get(g):
            return self.zh[g], base, "npcname-global", g, False
        if base in ALIAS_MANUAL_ZH:
            return ALIAS_MANUAL_ZH[base], base, "manual", "", False
        only = self.by_chr.get(chr_id, [])
        if len(only) == 1 and self.zh.get(only[0]):
            return self.zh[only[0]], base, "npcname-chr-only", only[0], False
        return "", base, "english-only", "", False


def build_night_bosses(raw: Path, npc_rows: list[dict], scaling: Scaling, perm: PermScaling,
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
        if npc_id < 100000 or npc_id % 10000 == 9999 or num(r["hp"]) <= 0:
            # 辅助 NPC（[Caligo Raid] Helper）、调试行（…9999）、无血量的场景实体
            reason = ("辅助/召唤实体（ID < 100000）" if npc_id < 100000 else
                      "调试/模板行（ID 以 9999 结尾）" if npc_id % 10000 == 9999 else
                      "hp 为 0 的场景实体")
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
                    # Paramdex 与 NpcName 都没有名字：用 chrId 兜底保留，别静默丢掉
                    # （例如 c4504 的 45040000，有效血量 12440，是守夜档位里最高的几行之一）
                    base, base_source = f"Unknown Enemy (c{chr_id})", "placeholder"
        base_sources[(base, chr_id)].add(base_source)
        groups[(base, chr_id)].append((r, base, variant))

    out: list[dict] = []
    for (base, chr_id), items in groups.items():
        name_ids = {r["nameId"] for r, _, _ in items if r["nameId"] not in ("0", "-1", "")}
        name_zh, name_en, source, name_id, alias_inferred = book.resolve(base, chr_id, name_ids)
        if base.startswith("Unknown Enemy (c") and source == "english-only":
            name_zh, source = f"未知敌人 c{chr_id}", "chrid-fallback"
        if source == "english-only":
            report["unmatchedNames"].append({"nameEn": name_en, "chrId": chr_id})
        srcs = base_sources[(base, chr_id)]
        inferred = alias_inferred or ("paramdex" not in srcs and "sibling" in srcs)

        buckets: dict[tuple, list[tuple[dict, str]]] = defaultdict(list)
        tiers: set[str] = set()
        for r, _, variant in items:
            mpc = int(r["multiPlayCorrectionParamId"])
            tier = "night" if mpc in NIGHT_THREAT else "field"
            tiers.add(tier)
            stats = fight_stats(r, scaling, perm)
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
            }
            v.update(fight_stats(rep, scaling, perm))
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
        cur["variants"].extend(e["variants"])
    out = list(merged.values())
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


# ---------------------------------------------------------------- 主流程


def main() -> None:
    ap = argparse.ArgumentParser(description="生成 NIGHTREIGN 首领数据集")
    ap.add_argument("--raw", type=Path, default=DEFAULT_RAW, help="raw/ 目录（含 params 与 msg）")
    ap.add_argument("--out", type=Path, default=DEFAULT_OUT, help="输出 JSON 路径")
    args = ap.parse_args()

    raw: Path = args.raw
    npc_rows = read_param(raw, "NpcParam")
    speffects = load_speffects(raw)
    scaling = Scaling(raw, speffects)
    perm = PermScaling(speffects)
    report = {"skippedMenuRows": [], "skippedRows": [], "unmatchedNames": [],
              "missingZhNightlord": [], "unmappedNightlords": [],
              "unknownMenuVariants": [], "unassignedFinalBossRows": []}

    nightlords, claimed = build_nightlords(raw, npc_rows, scaling, perm, report)
    night_bosses = build_night_bosses(raw, npc_rows, scaling, perm, claimed, report)
    report["skippedRows"].sort(key=lambda s: s["npcId"])
    report["unassignedFinalBossRows"].sort(key=lambda s: s["npcId"])

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
                "usage": "NightBossMenuParam / NpcParam / MultiPlayCorrectionParam / SpEffectParam",
            },
            {
                "name": "ELDEN RING NIGHTREIGN 游戏内文本 FMG（简体中文 / 英文）",
                "url": "",
                "revision": "regulation 10350000 + DLC1",
                "license": "游戏本体数据，仅用于展示名称",
                "usage": "menu/CL_MenuText（夜王名、远征名、说明）、item/NpcName（Boss 名）",
            },
            {
                "name": "Smithbox Paramdex (NR)",
                "url": f"https://github.com/vawser/Smithbox/tree/{PARAMDEX_REV}/src/Smithbox.Data/Assets/PARAM/NR",
                "revision": PARAMDEX_REV,
                "license": "MIT",
                "usage": "paramdef 字段名、行名（Name 列）、EFFECTIVE_AFFINITY 枚举",
            },
        ],
        "affinityNames": {str(k): {"zh": v[0], "en": v[1]} for k, v in sorted(AFFINITY_NAMES.items())},
        "scalingTiers": {str(k): v for k, v in sorted(scaling.used.items())},
        "permanentScaling": {str(k): v for k, v in sorted(perm.used.items())},
        "caveats": CAVEATS,
        "nightlords": nightlords,
        "nightBosses": night_bosses,
        "notes": {
            "unmatchedNames": report["unmatchedNames"],
            "skippedMenuRows": report["skippedMenuRows"],
            "skippedRows": report["skippedRows"],
            "unassignedFinalBossRows": report["unassignedFinalBossRows"],
        },
    }

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
    inferred = [e for e in night_bosses if e["nameInferred"]]
    if inferred:
        print(f"  名字按 ID 结构推断：{len(inferred)} 组（" +
              "、".join(e["nameZh"] or e["nameEn"] for e in inferred[:10]) + " …）")


if __name__ == "__main__":
    main()
