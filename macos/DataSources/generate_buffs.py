#!/usr/bin/env python3
"""Build the Nightreign "damage buff" dataset used by the 增伤排名 page.

What this produces
------------------
A catalogue of every SpEffect that can raise *the player's own output* and that
is reachable from something a player can actually equip, drink, cast or unlock:

  * relic affixes      AttachEffectParam.passiveSpEffectId_1..3 / onHitSpEffect
                       / permanentSpEffectId  (pool membership from
                       AttachEffectTableParam)
  * talismans          EquipParamAccessory.spEffectId_1..3 -> AttachEffectParam
                       -> SpEffectParam   (the accessory columns point at
                       AttachEffectParam, *not* at SpEffectParam directly)
  * consumables        EquipParamGoods.refId_default / refId_1 / level2RefId /
                       level3RefId (+ _1) with refCategory 1=Bullet 2=SpEffect,
                       plus carrySpEffectId / emptySpEffectId
  * weapon passives    EquipParamWeapon.spEffectBehaviorId0..2 /
                       residentSpEffectId(1,2)
  * spells             Magic.refId1..10 with refCategory1..10
                       (0=AtkParam_Pc, 1=Bullet, 2=SpEffect); bullets are
                       followed through spEffectIDForShooter / spEffectId0..4
  * permanent buffs    PermanentBuffParam.spEffectId / graceSpEffectId
  * chained effects    replaceSpEffectId / cycleOccurrenceSpEffectId /
                       atkOccurrenceSpEffectId / applyIdOnKillSp /
                       accumu*FireId / necromancy / revenantFamily / analyze*
                       followed up to CHAIN_DEPTH levels from any of the above
  * inferred entries   Ashes of War, hero skill/ultimate/passive buffs and a few
                       character-specific relic effects are hooked up by event
                       scripts (ESD/EMEVD), so no param column points at them.
                       They are picked up from the community Paramdex row name
                       with a conservative prefix allowlist and every such
                       source is flagged `inferred: true`.

HeroParam has no SpEffect column at all (checked against the NR paramdef); its
heroStatusParamId only reaches HeroStatusParam, whose attackRate/abilityReinforce
are per-level stat scaling rather than a buff, so nothing is pulled from there.
Hero skill / ultimate buffs are instead covered by the inferred pass above.

How "output boosting" is decided
--------------------------------
Nightreign has **no** dedicated "skill damage +x%" / "jump attack +x%" fields.
The multipliers are always the ordinary attack-rate fields; what makes them
apply to skills, charged attacks, guard counters, spells, ultimate arts, ...
is the *scope* triple

  magicSubCategoryChange1..3  (ATK_SUB_CATEGORY: 112 Skill Attack,
                               102 Jump Attack, 103 Guard Counter, 110 Charged
                               Spell, 111 Charged Skill, 122 Character Skill,
                               123 Ultimate Art, 105 Ranged Weapon, ...)
  wepParamChange / magParamChange / miracleParamChange / shamanParamChange /
  throwAttackParamChange       (which delivery the rates are allowed to touch)
  atkAttribute / spAttribute   (physical / special attribute filter)

so every buff carries both its `rates` and the `scope` those rates are gated by.
Each field in the output `rateFields` list was verified against the CSV header
of raw/params/SpEffectParam.csv and against the Paramdex field metadata; nothing
here is invented.

Sources (all local, exported beforehand; nothing is fetched at run time)
-----------------------------------------------------------------------
  raw/params/*.csv        regulation 1.03.5 (container 10350000), first column
                          ID, second column Name = community Paramdex row name
  raw/msg/<lang>/<bnd>_dlc01/<Fmg>.json   zhocn + engus, base + _dlc01 merged
  Paramdex field defaults / enums  vawser/Smithbox @ f5969c06 (NR ParamMeta,
                          Param Enums) and the Elden Ring paramdef for the
                          Japanese field descriptions -- both transcribed into
                          the tables below so this script stays offline.

Run:  cd macos/DataSources && python3 generate_buffs.py
"""

from __future__ import annotations

import argparse
import csv
import json
from collections import OrderedDict, defaultdict
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
PARAM_DIR = HERE / "raw" / "params"
MSG_DIR = HERE / "raw" / "msg"
DEFAULT_OUT = ROOT / "data" / "nightreign-buffs-v1.03.5.json"

SCHEMA_VERSION = 1
GAME_VERSION = "v1.03.5 + DLC1"
DATA_VERSION = "regulation 10350000"
SMITHBOX_COMMIT = "f5969c060cea240476e9dd4d6a64eafa9dbafaab"

CHAIN_DEPTH = 3
MAX_SOURCES_PER_BUFF = 40
CHAIN_INHERIT_LIMIT = 4

SOURCE_KIND_ORDER = {
    "relicAffix": 0, "accessory": 1, "goods": 2, "spell": 3,
    "permanent": 4, "weaponPassive": 5, "heroSkill": 6, "other": 7,
}


# --------------------------------------------------------------------------
# rate fields
# --------------------------------------------------------------------------
# key, zh, en, default, group, appliesTo  (+ optional lowerIsBetter)
# `group` in QUALIFY_GROUPS => a non-default value alone is enough to keep the
# SpEffect in the dataset.  "economy" fields never qualify on their own; they
# are only reported when the buff already qualified.
# `group` in COUNTS_AS_DAMAGE_GROUPS => the value may be folded into the damage
# product / summed as an output gain.  NOTE these two sets are *not* the same:
# the "special" group qualifies (those relics really are damage relics) but its
# values are per-field quantities (a restage copy ratio, an HP-scaled bonus),
# never plain multipliers, so it must never be multiplied into a damage total.
# Each field also carries `valueKind` (multiplier / flat / flag / special),
# derived below, which is the field-level version of the same warning.
RATE_FIELDS: list[dict[str, Any]] = [
    # --- 最终伤害倍率：作用在「已算出的伤害」上 -----------------------------
    dict(key="physicsAttackRate", zh="物理伤害倍率", en="Physical damage rate", default=1.0,
         group="damage",
         appliesTo="乘在已算出的物理伤害上（斩/打/突/标准四种物理攻击类型合计）。武器普攻、战技、法术里的物理部分都吃。"),
    dict(key="magicAttackRate", zh="魔力伤害倍率", en="Magic damage rate", default=1.0,
         group="damage", appliesTo="乘在已算出的魔力属性伤害上。"),
    dict(key="fireAttackRate", zh="火伤害倍率", en="Fire damage rate", default=1.0,
         group="damage", appliesTo="乘在已算出的火属性伤害上。"),
    dict(key="thunderAttackRate", zh="雷伤害倍率", en="Lightning damage rate", default=1.0,
         group="damage", appliesTo="乘在已算出的雷属性伤害上。"),
    dict(key="darkAttackRate", zh="圣伤害倍率", en="Holy damage rate", default=1.0,
         group="damage", appliesTo="乘在已算出的圣属性伤害上（参数里的 dark 槽位在本作＝圣）。"),
    dict(key="slashAttackRate", zh="斩击伤害倍率", en="Slash damage rate", default=1.0,
         group="damage", appliesTo="按攻击的物理攻击类型（AtkParam.atkAttribute＝斩击）额外乘算，与 physicsAttackRate 同时生效。"),
    dict(key="blowAttackRate", zh="打击伤害倍率", en="Strike damage rate", default=1.0,
         group="damage", appliesTo="按物理攻击类型＝打击额外乘算。"),
    dict(key="thrustAttackRate", zh="突刺伤害倍率", en="Pierce damage rate", default=1.0,
         group="damage", appliesTo="按物理攻击类型＝突刺额外乘算。"),
    dict(key="neutralAttackRate", zh="标准伤害倍率", en="Standard damage rate", default=1.0,
         group="damage", appliesTo="按物理攻击类型＝标准额外乘算。"),
    # --- 攻击力倍率：作用在「攻击力」数值上，在减算防御之前 -----------------
    dict(key="physicsAttackPowerRate", zh="物理攻击力倍率", en="Physical attack power rate", default=1.0,
         group="attackPower", appliesTo="乘在物理攻击力数值上（防御减算之前），与最终伤害倍率不同层，两者会相乘。"),
    dict(key="magicAttackPowerRate", zh="魔力攻击力倍率", en="Magic attack power rate", default=1.0,
         group="attackPower", appliesTo="乘在魔力攻击力数值上。"),
    dict(key="fireAttackPowerRate", zh="火攻击力倍率", en="Fire attack power rate", default=1.0,
         group="attackPower", appliesTo="乘在火攻击力数值上。"),
    dict(key="thunderAttackPowerRate", zh="雷攻击力倍率", en="Lightning attack power rate", default=1.0,
         group="attackPower", appliesTo="乘在雷攻击力数值上。"),
    dict(key="darkAttackPowerRate", zh="圣攻击力倍率", en="Holy attack power rate", default=1.0,
         group="attackPower", appliesTo="乘在圣（dark）攻击力数值上。"),
    dict(key="slashAttackPowerRate", zh="斩击攻击力倍率", en="Slash attack power rate", default=1.0,
         group="attackPower", appliesTo="按物理攻击类型＝斩击乘在攻击力上。"),
    dict(key="blowAttackPowerRate", zh="打击攻击力倍率", en="Strike attack power rate", default=1.0,
         group="attackPower", appliesTo="按物理攻击类型＝打击乘在攻击力上。"),
    dict(key="thrustAttackPowerRate", zh="突刺攻击力倍率", en="Pierce attack power rate", default=1.0,
         group="attackPower", appliesTo="按物理攻击类型＝突刺乘在攻击力上。"),
    dict(key="neutralAttackPowerRate", zh="标准攻击力倍率", en="Standard attack power rate", default=1.0,
         group="attackPower", appliesTo="按物理攻击类型＝标准乘在攻击力上。"),
    # --- 攻击力加算（点数） --------------------------------------------------
    dict(key="physicsAttackPower", zh="物理攻击力加算", en="Physical attack power", default=0,
         group="attackPowerFlat", appliesTo="物理攻击力的固定加减（点数，不是百分比）。"),
    dict(key="magicAttackPower", zh="魔力攻击力加算", en="Magic attack power", default=0,
         group="attackPowerFlat", appliesTo="魔力攻击力的固定加减。"),
    dict(key="fireAttackPower", zh="火攻击力加算", en="Fire attack power", default=0,
         group="attackPowerFlat", appliesTo="火攻击力的固定加减。"),
    dict(key="thunderAttackPower", zh="雷攻击力加算", en="Lightning attack power", default=0,
         group="attackPowerFlat", appliesTo="雷攻击力的固定加减。"),
    dict(key="darkAttackPower", zh="圣攻击力加算", en="Holy attack power", default=0,
         group="attackPowerFlat", appliesTo="圣（dark）攻击力的固定加减。"),
    # --- 特攻 ----------------------------------------------------------------
    dict(key="weakDmgRateA", zh="特攻Ａ倍率", en="Weakness A damage rate", default=1.0,
         group="weakness", appliesTo="对「特攻Ａ」类敌人的额外倍率（敌人侧由 EquipParamWeapon/NpcParam 的 weakA 判定）。"),
    dict(key="weakDmgRateB", zh="特攻Ｂ倍率", en="Weakness B damage rate", default=1.0,
         group="weakness", appliesTo="对「特攻Ｂ」类敌人的额外倍率。"),
    dict(key="weakDmgRateC", zh="特攻Ｃ倍率", en="Weakness C damage rate", default=1.0,
         group="weakness", appliesTo="对「特攻Ｃ」类敌人的额外倍率。"),
    dict(key="weakDmgRateD", zh="特攻Ｄ倍率", en="Weakness D damage rate", default=1.0,
         group="weakness", appliesTo="对「特攻Ｄ」类敌人的额外倍率。"),
    dict(key="weakDmgRateE", zh="特攻Ｅ倍率", en="Weakness E damage rate", default=1.0,
         group="weakness", appliesTo="对「特攻Ｅ」类敌人的额外倍率。"),
    dict(key="weakDmgRateF", zh="特攻Ｆ倍率", en="Weakness F damage rate", default=1.0,
         group="weakness", appliesTo="对「特攻Ｆ」类敌人的额外倍率。"),
    # --- 致命一击 ------------------------------------------------------------
    dict(key="vitalSpotChangeRate", zh="致命一击伤害倍率", en="Critical (sweet spot) rate", default=1.0,
         group="critical",
         appliesTo="要害／致命一击（背刺、破防处决）的伤害倍率，默认 1＝不改写。"
                   "本版本 SpEffectParam 全表 13472 行该字段恒为 1，没有任何非默认值，"
                   "因此本数据集不会出现该字段（rateFields 里的 observedCount 为 0），页面无需为它写逻辑。"),
    # --- 削韧 / 精力 ---------------------------------------------------------
    dict(key="saAttackPowerRate", zh="削韧攻击力倍率", en="Stance (SA) attack power rate", default=1.0,
         group="stance", appliesTo="削韧（SA）攻击力倍率，影响打出失衡的速度，不影响血量伤害。"),
    dict(key="staminaAttackRate", zh="精力削减倍率", en="Stamina attack rate", default=1.0,
         group="stance", appliesTo="对格挡中敌人削精力的倍率。"),
    dict(key="subSaBonusRate_Magic", zh="魔力追加削韧倍率", en="Sub-SA bonus (Magic)", default=1.0,
         group="stance", appliesTo="魔力属性命中时的追加削韧倍率。"),
    dict(key="subSaBonusRate_Fire", zh="火追加削韧倍率", en="Sub-SA bonus (Fire)", default=1.0,
         group="stance", appliesTo="火属性命中时的追加削韧倍率。"),
    dict(key="subSaBonusRate_Lightning", zh="雷追加削韧倍率", en="Sub-SA bonus (Lightning)", default=1.0,
         group="stance", appliesTo="雷属性命中时的追加削韧倍率。"),
    dict(key="subSaBonusRate_Holy", zh="圣追加削韧倍率", en="Sub-SA bonus (Holy)", default=1.0,
         group="stance", appliesTo="圣属性命中时的追加削韧倍率。"),
    dict(key="subSaBonusRate_Poison", zh="毒追加削韧倍率", en="Sub-SA bonus (Poison)", default=1.0,
         group="stance", appliesTo="中毒累积带来的追加削韧倍率。"),
    dict(key="subSaBonusRate_ScarletRot", zh="腐败追加削韧倍率", en="Sub-SA bonus (Scarlet Rot)", default=1.0,
         group="stance", appliesTo="猩红腐败累积带来的追加削韧倍率。"),
    dict(key="subSaBonusRate_Bleed", zh="出血追加削韧倍率", en="Sub-SA bonus (Bleed)", default=1.0,
         group="stance", appliesTo="出血累积带来的追加削韧倍率。"),
    dict(key="subSaBonusRate_Blight", zh="死之诅咒追加削韧倍率", en="Sub-SA bonus (Death Blight)", default=1.0,
         group="stance", appliesTo="死之诅咒累积带来的追加削韧倍率。"),
    dict(key="subSaBonusRate_Frostbite", zh="冻伤追加削韧倍率", en="Sub-SA bonus (Frostbite)", default=1.0,
         group="stance", appliesTo="冻伤累积带来的追加削韧倍率。"),
    dict(key="subSaBonusRate_Sleep", zh="睡眠追加削韧倍率", en="Sub-SA bonus (Sleep)", default=1.0,
         group="stance", appliesTo="睡眠累积带来的追加削韧倍率。"),
    dict(key="subSaBonusRate_Madness", zh="发狂追加削韧倍率", en="Sub-SA bonus (Madness)", default=1.0,
         group="stance", appliesTo="发狂累积带来的追加削韧倍率。"),
    # --- 异常状态累积 --------------------------------------------------------
    dict(key="poizonAttackPower", zh="中毒累积加算", en="Poison buildup", default=0,
         group="status", appliesTo="命中时对目标中毒累积值的加算点数。"),
    dict(key="diseaseAttackPower", zh="猩红腐败累积加算", en="Scarlet Rot buildup", default=0,
         group="status", appliesTo="命中时对目标猩红腐败累积值的加算点数。"),
    dict(key="bloodAttackPower", zh="出血累积加算", en="Blood loss buildup", default=0,
         group="status", appliesTo="命中时对目标出血累积值的加算点数。"),
    dict(key="curseAttackPower", zh="死之诅咒累积加算", en="Death blight buildup", default=0,
         group="status", appliesTo="命中时对目标死之诅咒累积值的加算点数。"),
    dict(key="freezeAttackPower", zh="冻伤累积加算", en="Frostbite buildup", default=0,
         group="status", appliesTo="命中时对目标冻伤累积值的加算点数。"),
    dict(key="sleepAttackPower", zh="睡眠累积加算", en="Sleep buildup", default=0,
         group="status", appliesTo="命中时对目标睡眠累积值的加算点数。"),
    dict(key="madnessAttackPower", zh="发狂累积加算", en="Madness buildup", default=0,
         group="status", appliesTo="命中时对目标发狂累积值的加算点数。"),
    dict(key="poisonInflictRate", zh="中毒累积倍率", en="Poison inflict rate", default=1.0,
         group="status", appliesTo="自身造成的中毒累积倍率。"),
    dict(key="diseaseInflictRate", zh="猩红腐败累积倍率", en="Scarlet Rot inflict rate", default=1.0,
         group="status", appliesTo="自身造成的猩红腐败累积倍率。"),
    dict(key="bloodInflictRate", zh="出血累积倍率", en="Blood loss inflict rate", default=1.0,
         group="status", appliesTo="自身造成的出血累积倍率。"),
    dict(key="curseInflictRate", zh="死之诅咒累积倍率", en="Death blight inflict rate", default=1.0,
         group="status", appliesTo="自身造成的死之诅咒累积倍率。"),
    dict(key="frostInflictRate", zh="冻伤累积倍率", en="Frostbite inflict rate", default=1.0,
         group="status", appliesTo="自身造成的冻伤累积倍率。"),
    dict(key="sleepInflictRate", zh="睡眠累积倍率", en="Sleep inflict rate", default=1.0,
         group="status", appliesTo="自身造成的睡眠累积倍率。"),
    dict(key="madnessInflictRate", zh="发狂累积倍率", en="Madness inflict rate", default=1.0,
         group="status", appliesTo="自身造成的发狂累积倍率。"),
    # --- 本作特有 ------------------------------------------------------------
    dict(key="currentHealthAttackRate", zh="随当前血量的攻击加成系数", en="Current-HP attack bonus factor", default=0,
         group="special",
         appliesTo="NIGHTREIGN 新增字段，默认 0＝不启用。按当前血量比例换算出的攻击加成系数（游戏内部再与血量比例相乘），"
                   "本版本唯一实例是遗物词条「防御反击成功时，能依照自己目前的血量提升伤害」（SpEffect 7150000，值 5）。"
                   "**这是系数不是倍率，数值本身不能当乘数直接乘进伤害**，页面应单独展示或自行建模。"),
    dict(key="restageAttackRate", zh="再演（Restage）伤害倍率", en="Restage (Duchess) damage rate", default=-1.0,
         group="special",
         appliesTo="NIGHTREIGN 新增字段，默认 -1＝不启用。指女爵（Duchess）的技艺／词条「再演（Restage）」"
                   "复制最近伤害时，复制出来的那一份所使用的伤害倍率。"
                   "本版本仅两行非默认：SpEffect 7010701＝0.4（词条『【女爵】短剑连击的最后攻击命中时，能对着周围的敌人，再次上演最近做过的行动』）、"
                   "SpEffect 7290001＝0.6（词条『【女爵】提升技艺造成的伤害』）。"
                   "**它是再演那一份的占比，不是对玩家整体伤害的乘算增益**，0.6 绝不等于 -40% 伤害，页面不得把它乘进伤害乘积。"),
    dict(key="isUseAtkParamAtkPowerCorrect", zh="套用攻击参数的攻击力倍率修正", en="Use AtkParam attack-power correction", default=0,
         group="flag", appliesTo="开关（非倍率）：是否套用 AtkParam 侧的攻击力倍率修正。单独出现不算增伤。"),
    dict(key="isUseStatusAilmentAtkPowerCorrect", zh="套用攻击参数的异常状态倍率修正", en="Use AtkParam status correction", default=0,
         group="flag", appliesTo="开关（非倍率）：是否套用 AtkParam 侧的异常状态攻击力倍率修正。单独出现不算增伤。"),
    # --- 间接（不直接增伤，页面可自行赋权为 0） -----------------------------
    dict(key="artsConsumptionRate", zh="战技消耗倍率", en="Skill FP cost rate", default=1.0,
         group="economy", lowerIsBetter=True, appliesTo="战技专注值消耗倍率，<1 为减少消耗（对玩家更有利）。不直接提升单次伤害。"),
    dict(key="magicConsumptionRate", zh="魔法消耗倍率", en="Sorcery FP cost rate", default=1.0,
         group="economy", lowerIsBetter=True, appliesTo="魔法专注值消耗倍率，<1 为减少消耗（对玩家更有利）。"),
    dict(key="miracleConsumptionRate", zh="祷告消耗倍率", en="Incantation FP cost rate", default=1.0,
         group="economy", lowerIsBetter=True, appliesTo="祷告专注值消耗倍率，<1 为减少消耗（对玩家更有利）。"),
    dict(key="shamanConsumptionRate", zh="秘术消耗倍率", en="Shaman FP cost rate", default=1.0,
         group="economy", lowerIsBetter=True, appliesTo="秘术（shaman 槽）专注值消耗倍率，<1 为减少消耗（对玩家更有利）。"),
    dict(key="goodsConsumptionRate", zh="道具消耗倍率", en="Item consumption rate", default=1.0,
         group="economy", lowerIsBetter=True, appliesTo="消耗品消耗倍率，<1 为减少消耗（对玩家更有利）。"),
    dict(key="ultimateArtGaugeRate", zh="绝招量表倍率", en="Ultimate art gauge rate", default=1.0,
         group="economy", appliesTo="绝招量表累积倍率。"),
    dict(key="ultimateArtGaugeChargeRate", zh="绝招量表自然累积倍率", en="Ultimate art gauge charge rate", default=1.0,
         group="economy", appliesTo="绝招量表自然回复倍率。"),
    dict(key="ultimateArtGauge", zh="绝招量表加算", en="Ultimate art gauge add", default=0,
         group="economy", appliesTo="绝招量表的一次性加算。"),
    dict(key="ultimateArtGaugeRecovery", zh="绝招量表恢复", en="Ultimate art gauge recovery", default=0,
         group="economy", appliesTo="绝招量表的持续恢复量。"),
    dict(key="ultimateArtDuration", zh="绝招持续时间", en="Ultimate art duration", default=0,
         group="economy", appliesTo="绝招持续时间的加成。"),
    dict(key="characterSkillCooldownReduction", zh="技艺冷却倍率", en="Character skill cooldown rate", default=1.0,
         group="economy", lowerIsBetter=True, appliesTo="角色技艺冷却时间倍率，<1 为缩短（对玩家更有利）。"),
    dict(key="additionalCharacterSkillUse", zh="技艺追加次数", en="Additional character skill uses", default=0,
         group="economy", appliesTo="角色技艺可用次数的追加。"),
    dict(key="magicEffectTimeChange", zh="法术效果时间增减", en="Magic effect time change", default=0,
         group="economy", appliesTo="魔法／祷告增益效果持续时间的加减（秒）。"),
    dict(key="bowDistRate", zh="弓射程修正", en="Bow distance rate", default=0,
         group="economy", appliesTo="弓类武器射程修正值（加算百分比）。"),
    dict(key="regainRate", zh="回复量表倍率", en="Regain rate", default=1.0,
         group="economy", appliesTo="Regain（受伤后可回收血量）倍率。"),
]

# key, zh, qualifies (a non-default value alone keeps the SpEffect),
# countsAsDamage (the value may be folded into a damage total), note
RATE_FIELD_GROUPS: list[dict[str, Any]] = [
    dict(key="damage", zh="最终伤害倍率", qualifies=True, countsAsDamage=True,
         note="减算防御之后的伤害乘数，可直接相乘。"),
    dict(key="attackPower", zh="攻击力倍率", qualifies=True, countsAsDamage=True,
         note="减算防御之前的攻击力乘数，与 damage 组分属两层，两层各自相乘后再相乘。"),
    dict(key="attackPowerFlat", zh="攻击力加算", qualifies=True, countsAsDamage=True,
         note="攻击力点数加算（默认 0），必须先加进攻击力再乘倍率，不能当乘数用。"),
    dict(key="weakness", zh="特攻倍率", qualifies=True, countsAsDamage=True,
         note="只对被标记为对应特攻类型的敌人生效，默认不计入通用排名。"),
    dict(key="critical", zh="致命一击", qualifies=True, countsAsDamage=True,
         note="致命一击／要害倍率。本版本参数表无任何非默认值（observedCount=0）。"),
    dict(key="stance", zh="削韧／精力", qualifies=True, countsAsDamage=False,
         note="削韧（SA）与削精力倍率，影响打出失衡的速度，不改变血量伤害，另算一条轴。"),
    dict(key="status", zh="异常状态累积", qualifies=True, countsAsDamage=False,
         note="异常状态累积的加算点数与倍率，不改变直接伤害，另算一条轴。"),
    dict(key="special", zh="本作特有（各自独立语义，禁止相乘）", qualifies=True, countsAsDamage=False,
         note="currentHealthAttackRate 是随血量换算的加成系数、restageAttackRate 是女爵『再演』复制那一份的伤害占比。"
              "两者都不是对玩家整体伤害的乘数：把 0.4／0.6 乘进伤害乘积会得出 -60%／-40% 的反向结论。"
              "页面只能单独展示（或按各自机制单独建模），绝不可参与乘算或加权汇总。"),
    dict(key="flag", zh="开关（非倍率）", qualifies=False, countsAsDamage=False,
         note="0/1 开关，标记该 SpEffect 是否套用 AtkParam 侧的修正，单独出现不算增伤。"),
    dict(key="economy", zh="消耗与量表（不直接增伤）", qualifies=False, countsAsDamage=False,
         note="专注值消耗、绝招量表、技艺冷却等；只在该 buff 已因其他字段入选时顺带输出。"
              "带 lowerIsBetter=true 的字段是数值越低越好。"),
]
RATE_FIELD_GROUP_BY_KEY = {group["key"]: group for group in RATE_FIELD_GROUPS}

QUALIFY_GROUPS = {g["key"] for g in RATE_FIELD_GROUPS if g["qualifies"]}
COUNTS_AS_DAMAGE_GROUPS = {g["key"] for g in RATE_FIELD_GROUPS if g["countsAsDamage"]}
GROUP_LABELS = {g["key"]: g["zh"] for g in RATE_FIELD_GROUPS}

# groups whose non-default value is an actual change to HP damage (as opposed
# to poise damage / status buildup / a mechanic of its own) -- the same set the
# `countsAsDamage` flag exports, kept under the old name for readability.
DAMAGE_GROUPS = COUNTS_AS_DAMAGE_GROUPS


def value_kind(field: dict[str, Any]) -> str:
    """How a consumer is allowed to use the number.

    multiplier  乘数（默认 1）           -> 可相乘
    flat        加算点数（默认 0）        -> 先加后乘
    flag        0/1 开关                 -> 只作标记
    special     语义独立，禁止直接相乘    -> 只能单独展示
    """
    if field["group"] == "flag":
        return "flag"
    if field["group"] == "special":
        return "special"
    return "flat" if float(field["default"]) == 0.0 else "multiplier"


for _field in RATE_FIELDS:
    _field["valueKind"] = value_kind(_field)

RATE_FIELD_BY_KEY = {field["key"]: field for field in RATE_FIELDS}


# --------------------------------------------------------------------------
# enums (transcribed from Smithbox NR "Param Enums", commit above)
# --------------------------------------------------------------------------
ATK_SUB_CATEGORY = {
    0: ("无", "None"),
    1: ("满月魔法", "Full Moon Sorcery"),
    2: ("卡利亚剑魔法", "Carian Sword Sorcery"),
    3: ("辉剑魔法", "Glintblade Sorcery"),
    4: ("掘石魔法", "Stonedigger Sorcery"),
    5: ("结晶人魔法", "Crystalian Sorcery"),
    6: ("彗星魔法", "Comet Sorcery"),
    7: ("星星魔法", "Star Sorcery"),
    8: ("熔岩魔法", "Magma Sorcery"),
    9: ("荆棘魔法", "Thorn Sorcery"),
    10: ("死之魔法", "Death Sorcery"),
    11: ("重力魔法", "Gravity Sorcery"),
    12: ("夜之魔法", "Night Sorcery"),
    13: ("冷气魔法", "Cold Sorcery"),
    14: ("亚兹勒彗星", "Comet Azur"),
    15: ("破灭之星", "Stars of Ruin"),
    20: ("弑神祷告", "Godslayer Incantation"),
    21: ("巨人火焰祷告", "Giantsflame Incantation"),
    22: ("古龙信仰祷告", "Dragon Cult Incantation"),
    23: ("兽祷告", "Bestial Incantation"),
    24: ("黄金律法祷告", "Golden Order Incantation"),
    25: ("龙餐祷告", "Dragon Communion Incantation"),
    26: ("癫火祷告", "Frenzied Flame Incantation"),
    27: ("贵人威势", "Noble Presence"),
    28: ("坩埚相关祷告", "Aspect of the Crucible Incantation"),
    100: ("蓄力强攻击", "Charged Heavy Attack"),
    101: ("骑马攻击", "Horseback Attack"),
    102: ("跳跃攻击", "Jump Attack"),
    103: ("防御反击", "Guard Counter Attack"),
    104: ("连段最后一击", "Final Chain Attack"),
    105: ("远程武器攻击", "Ranged Weapon Attack"),
    106: ("咆哮攻击", "Roar Attack"),
    107: ("吐息攻击", "Breath Attack"),
    108: ("投掷壶道具攻击", "Thrown Pot Item Attack"),
    109: ("香水道具攻击", "Perfume Item Attack"),
    110: ("蓄力法术攻击", "Charged Spell Attack"),
    111: ("蓄力战技攻击", "Charged Skill Attack"),
    112: ("战技攻击", "Skill Attack"),
    113: ("拉塔恩之枪", "Radahn's Spear"),
    114: ("祖灵婴儿头", "Ancestral Infant's Head"),
    116: ("亡灵咆哮", "Wraith Roar"),
    117: ("亡灵攻击", "Wraith Attack"),
    118: ("黄金箭", "Golden Arrow"),
    119: ("起手普通攻击", "Initial Standard Attack"),
    120: ("投掷小刀道具攻击", "Throwing Knife Item Attack"),
    121: ("投石道具攻击", "Throwing Stone Item Attack"),
    122: ("角色技艺", "Character Skill"),
    123: ("绝招", "Ultimate Art"),
    124: ("双手持攻击", "Two-handed Attack"),
    125: ("双持攻击", "Dual Wield Attack"),
    126: ("无伤骤死", "No-Damage Sudden Death"),
    127: ("冲刺攻击", "Dash Attack"),
    128: ("翻滚攻击", "Rolling Attack"),
    129: ("后跳攻击", "Backstep Attack"),
    130: ("近战武器攻击", "Melee Weapon Attack"),
}

WEP_CHANGE_PARAM = {
    0: ("不限", "None"),
    1: ("右手武器", "Right-hand"),
    2: ("左手武器", "Left-hand"),
    3: ("自身", "Self"),
    4: ("踢击", "Kick"),
}

ATK_ATTR_TYPE = {
    0: ("斩击", "Slash"),
    1: ("打击", "Strike"),
    2: ("突刺", "Pierce"),
    3: ("标准", "Standard"),
    252: ("引用武器 atkAttribute2", "EquipParamWeapon atkAttribute2 reference"),
    253: ("引用武器 atkAttribute", "EquipParamWeapon atkAttribute reference"),
    254: ("不限", "None"),
}

SP_ATTR_TYPE = {
    0: ("无属性", "None"),
    10: ("魔力", "Magic"),
    11: ("火", "Fire"),
    12: ("雷", "Lightning"),
    13: ("圣", "Holy"),
    20: ("毒", "Poison"),
    21: ("猩红腐败", "Scarlet Rot"),
    22: ("出血", "Blood Loss"),
    23: ("冻伤", "Frostbite"),
    24: ("睡眠", "Sleep"),
    25: ("发狂", "Madness"),
    26: ("死之诅咒", "Death Blight"),
    27: ("屠龙（箭）", "Dragonwound (Arrow)"),
    28: ("黑炎（箭）", "Blackflame (Arrow)"),
    29: ("血炎（箭）", "Bloodflame (Arrow)"),
    30: ("圣（大箭）", "Holy (Greatarrow)"),
    31: ("魔力（弩矢）", "Magic (Bolt)"),
    254: ("不限", "None"),
}

# SP_EFFECT_SPCATEGORY buckets, derived from the enum's own labels.
#
# The Paramdex enum only *names* the values it has seen (100..204, 1000..1006,
# 10000..10010), but the regulation uses a few more inside the same decades:
# 205 ([Ultimate - Scholar] Communion) and 206 ([Relic] Status Ailment Gauges
# Slowly Increase Attack Power - Stack 1..10, [Item - Level 3] Dart Defense
# Debuff - Stack 1..N) in the 200 block, 1007 ([Skill - Executor] Cursed Sword)
# and 1008 ([Near Death]) in the 1000 block.  The whole 100..299 block is
# "Remove Previous" and the whole 1000..1999 block is "Apply Highest", so the
# ranges are widened to the decade rather than to the values Paramdex happens to
# label -- otherwise those rows fall through to "unknown", which has no stacking
# rule a page could use.  A catch-all bucket is still emitted (and exported in
# enums.spCategoryBehavior) so that *every* value this script can print has a
# Chinese label.
SPCATEGORY_BEHAVIOUR = [
    (0, 0, "none", "不参与互斥；同类可以无限量共存"),
    (1, 1, "persistThroughDeath", "死亡后仍保留"),
    (10, 10, "stackSelf", "可与自己叠加（同一效果多份同时生效）"),
    (20, 20, "resetOnApply", "重复取得时刷新计时"),
    (100, 299, "removePrevious",
     "同类互斥，新的覆盖旧的（200 需 categoryPriority 相同才覆盖）。"
     "注意 205／206 未出现在 Paramdex 枚举里，但同属 200 系列＝Remove Previous 语义；"
     "206 的『异常状态量表逐层提升攻击力』1..10 层是同一条词条的十个档位，彼此互斥，只会生效当前层。"),
    (1000, 1999, "applyHighest", "同类互斥，按 categoryPriority 取最强的一份（数值小者优先）"),
    (10000, 19999, "applyFirst", "同类互斥，先生效的那份保留，后来的被忽略"),
]

SPCATEGORY_UNKNOWN = (
    "unknown",
    "未在已知区间内的 spCategory：Paramdex 枚举与本表都没有覆盖，叠加行为未知；"
    "页面应按『各自独立』保守处理并标注存疑（本版本数据中不会出现，见 diagnostics）。",
)


def spcategory_behaviour(value: int) -> tuple[str, str]:
    for lo, hi, code, zh in SPCATEGORY_BEHAVIOUR:
        if lo <= value <= hi:
            return code, zh
    return SPCATEGORY_UNKNOWN


# --------------------------------------------------------------------------
# non-rate SpEffectParam fields we read, with their Paramdex default
# --------------------------------------------------------------------------
FIELD_DEFAULTS: dict[str, str] = {
    "effectEndurance": "-1",
    "motionInterval": "0",
    "isPeriodicEffect": "0",
    "conditionHp": "-1",
    "conditionHpRate": "-1",
    "conditionStamina": "-1",
    "wepTypeTrigger": "1",
    "wepTypeTriggerCount": "0",
    "triggerOnWepType": "0",
    "triggerAttachedWeapon": "0",
    "enemyStateInfoTrigger": "0",
    "invocationConditionsStateChange1": "0",
    "invocationConditionsStateChange2": "0",
    "invocationConditionsStateChange3": "0",
    "randomChanceValue": "0",
    "accumuOverFireId": "-1",
    "accumuOverVal": "-1",
    "accumuUnderFireId": "-1",
    "accumuUnderVal": "-1",
    "accumuVal": "0",
    "effectTargetSelf": "0",
    "effectTargetFriend": "0",
    "effectTargetEnemy": "0",
    "effectTargetPlayer": "0",
    "stateInfo": "0",
    "spCategory": "0",
    "categoryPriority": "0",
    "saveCategory": "-1",
    "wepParamChange": "0",
    "magParamChange": "0",
    "miracleParamChange": "0",
    "shamanParamChange": "0",
    "throwAttackParamChange": "0",
    "atkAttribute": "254",
    "spAttribute": "254",
    "magicSubCategoryChange1": "0",
    "magicSubCategoryChange2": "0",
    "magicSubCategoryChange3": "0",
    "vowType0": "1",
}
for _f in RATE_FIELDS:
    FIELD_DEFAULTS[_f["key"]] = str(_f["default"])

CONDITION_FIELDS = [
    ("conditionHp", "残余血量低于此比例(%)才发动"),
    ("conditionHpRate", "残余血量高于此比例(%)才发动"),
    ("conditionStamina", "精力条件"),
    ("motionInterval", "发动间隔（秒）"),
    ("isPeriodicEffect", "周期性发动"),
    ("wepTypeTrigger", "触发所需武器种类"),
    ("wepTypeTriggerCount", "触发所需武器数量"),
    ("triggerOnWepType", "指定武器种类时触发"),
    ("triggerAttachedWeapon", "需要附加属性的武器"),
    ("enemyStateInfoTrigger", "敌人处于指定状态时触发"),
    ("invocationConditionsStateChange1", "发动条件：自身状态1"),
    ("invocationConditionsStateChange2", "发动条件：自身状态2"),
    ("invocationConditionsStateChange3", "发动条件：自身状态3"),
    ("randomChanceValue", "发动概率值"),
    # accumuOverFireId / accumuUnderFireId are *chain* references, not
    # conditions; they live in CHAIN_FIELDS only, so the same value is never
    # rendered twice (once under conditions and once under chainSpEffectId).
    # Only the thresholds stay here.
    ("accumuOverVal", "累积阈值（上）"),
    ("accumuUnderVal", "累积阈值（下）"),
    ("accumuVal", "每次累积量"),
    ("vowType0", "誓约0（阵营／模式限制）"),
]

CHAIN_FIELDS = [
    ("replaceSpEffectId", "替换为"),
    ("cycleOccurrenceSpEffectId", "周期性发动"),
    ("atkOccurrenceSpEffectId", "攻击命中时发动"),
    ("applyIdOnKillSp", "击杀时发动"),
    ("accumuOverFireId", "累积超过阈值时发动"),
    ("accumuUnderFireId", "累积低于阈值时发动"),
    ("applyIdOnGetSoul", "获得卢恩时发动"),
    ("necromancyActivationSpEffectId", "死灵术发动"),
    ("revenantFamily_spEffectId_1", "复仇者眷属1"),
    ("revenantFamily_spEffectId_2", "复仇者眷属2"),
    ("revenantFamily_spEffectId_3", "复仇者眷属3"),
    ("analyzeAcquire_effectId", "解析取得"),
    ("analyzeSelfLevel1_effectId", "解析等级1"),
    ("analyzeSelfLevel2_effectId", "解析等级2"),
    ("analyzeSelfLevel3_effectId", "解析等级3"),
]

# SpEffects that no param field points at (they are applied by event scripts /
# ESD, e.g. Ashes of War buffs, hero skill buffs, some character-specific relic
# effects).  The community Paramdex row name is the only handle we have, so a
# conservative allowlist of player-facing prefixes is used, and every entry made
# this way is flagged with `inferred: true`.
ORPHAN_PREFIX_KINDS: list[tuple[str, str]] = [
    ("Relic", "relicAffix"),
    ("Talisman", "accessory"),
    ("Item", "goods"),
    ("Magic Cocktail", "goods"),
    ("Hub", "goods"),
    ("Incantation", "spell"),
    ("Sorcery", "spell"),
    ("Weapon Power", "weaponPassive"),
    ("Weapon", "weaponPassive"),
    ("AoW", "weaponPassive"),
    ("Arrow", "weaponPassive"),
    ("Bow", "weaponPassive"),
    ("Serpent Bow", "weaponPassive"),
    ("Flail", "weaponPassive"),
    ("Skill -", "heroSkill"),
    ("Ultimate -", "heroSkill"),
    ("Passive -", "heroSkill"),
    ("Interactable Effect", "other"),
    ("Libra Deal", "other"),
    ("EFfect", "other"),
]

ATTACH_SPEFFECT_FIELDS = [
    ("passiveSpEffectId_1", "passive", False),
    ("passiveSpEffectId_2", "passive", False),
    ("passiveSpEffectId_3", "passive", False),
    ("onHitSpEffect", "onHit", True),
    ("permanentSpEffectId", "permanent", False),
]

BULLET_SPEFFECT_FIELDS = [
    "spEffectIDForShooter", "spEffectId0", "spEffectId1",
    "spEffectId2", "spEffectId3", "spEffectId4",
]

STACKING_RULES_ZH = """本数据集给出的叠加判定，是依据参数结构（SpEffectParam 的 spCategory / categoryPriority / saveCategory / stateInfo 四个字段）推断出来的，未经木桩全面实测，请当作「参数层面的默认规则」而不是最终结论。

1. spCategory 是主判定字段，决定同类效果之间怎么处理：
   - 0（none）：不参与互斥，想挂多少份就挂多少份；
   - 10（stackSelf）：同一个效果可以与自己叠加（遗物词条里的「提升物理攻击力」等就属于这一类，因此带同名词条的多枚遗物是各自结算再相乘的）；
   - 20（resetOnApply）：重复取得时只刷新持续时间；
   - 100～299（removePrevious）：同类互斥，新的把旧的顶掉；其中 200 要求 categoryPriority 相同才顶替。
     Paramdex 的 SP_EFFECT_SPCATEGORY 枚举只标注到 204，但本作实际还用了 205（学者绝招「共鸣」）与 206
     （遗物词条「异常状态量表逐层提升攻击力」1～10 层、三级投掷道具的减防叠层），整个 200 系列都是
     Remove Previous 语义，所以本表按区间归类：那十层「逐层提升攻击力」彼此互斥，同一时刻只生效当前层，
     排名时应按玩家能稳定维持的层数取一条，不能把 10 层相乘；
   - 1000～1999（applyHighest）：同类互斥，取 categoryPriority 更优（数值小）的那一份；枚举只标到 1006，
     本作还用了 1007（处刑人「诅咒之剑」）与 1008（濒死），同属该区间；
   - 10000 以上（applyFirst）：同类互斥，先生效的保留，后来的被忽略。
   本数据集把每个 buff 的 spCategory 数值、以及它落在哪一档（stacking.spCategoryBehavior）都一并输出；
   enums.spCategoryBehavior 末尾还有一条 min/max 为 null 的 "unknown" 兜底项，用于万一出现区间外的新值
   （本版本数据中不会出现，见 diagnostics.observedSpCategoryBehaviors）。

2. 排名时的建议做法：先按 stacking.group（= spCategoryBehavior 为 stackSelf/none 时用 "sp<spCategory>#<spEffectId>"，其余情况用 "sp<spCategory>"）分组；同组内按上面的规则只保留一份（applyHighest 取 categoryPriority 最优，removePrevious/applyFirst 取玩家实际选择的那一份，默认取倍率最高者）；不同组之间视为相互独立，各自的倍率相乘。

3. stateInfo 是「状态变化类型」标记，主要给游戏内的状态判定（例如 invocationConditionsStateChange、enemyStateInfoTrigger）用，并不是互斥分组；大量增伤 buff 的 stateInfo 都是 0。只有当两个 buff 的 stateInfo 相同且非 0 时，才值得怀疑它们是同一状态的不同档位（例如同一祷告的不同强度）。本数据集仍输出该值供交叉验证。

4. categoryPriority 是同一 spCategory 内的优先度（Paramdex 字段说明为「同一カテゴリ内での優先度（低い方が優先）」，即数值小的优先）；saveCategory 是存档槽位，-1 表示不写入存档，正值表示该 buff 占用某个可保存的槽（多用于永久强化）。

4b. rates 不能一律相乘：先看 rateFields[key].valueKind。multiplier 才是乘数；flat 是点数加算（先加进攻击力再乘倍率）；
   flag 只是开关；special 组（currentHealthAttackRate 随血量的加成系数、restageAttackRate 女爵「再演」复制那一份的伤害占比）
   语义各自独立，**一律不得参与乘算或加权汇总**——把 restageAttackRate=0.6 当乘数会把「提升技艺伤害」算成 -40%，排名完全反向。
   rateFieldGroups[].countsAsDamage=false 的组（stance 削韧、status 异常累积、special、flag、economy）都不进伤害乘积，只能单独展示。

5. 不同层之间的关系：xxxAttackPowerRate（攻击力倍率，减算防御前）与 xxxAttackRate（最终伤害倍率，减算防御后）属于两个不同的计算层，两者相乘；同一层内不同属性（物理／魔力／火／雷／圣）各自只作用于对应属性的伤害分量；物理攻击类型倍率（slash/blow/thrust/neutral）与 physics 倍率同时生效、相乘。

6. scope 字段（magicSubCategoryChange1..3、magParamChange、miracleParamChange、shamanParamChange、throwAttackParamChange、wepParamChange、atkAttribute、spAttribute）是这些倍率的生效范围。本作没有独立的「战技伤害 +x%」字段——所谓「强化战技／跳跃攻击／防御反击／绝招」都是普通的 AttackRate 字段加上 magicSubCategoryChange 的子类过滤（112 战技攻击、102 跳跃攻击、103 防御反击、110 蓄力法术、111 蓄力战技、122 角色技艺、123 绝招、105 远程武器攻击等）。页面按战技伤害构成加权时，必须先用 scope 判断这条 buff 是否作用于该攻击。"""


# --------------------------------------------------------------------------
# helpers
# --------------------------------------------------------------------------
def read_param(name: str) -> list[dict[str, str]]:
    path = PARAM_DIR / f"{name}.csv"
    with path.open(encoding="utf-8", newline="") as handle:
        return list(csv.DictReader(handle))


def index_param(rows: list[dict[str, str]]) -> dict[str, dict[str, str]]:
    """First occurrence wins (matches the in-game param row order)."""
    out: dict[str, dict[str, str]] = {}
    for row in rows:
        out.setdefault(row["ID"], row)
    return out


def _is_cjk(char: str) -> bool:
    code = ord(char)
    return (0x3000 <= code <= 0x303F        # CJK punctuation
            or 0x4E00 <= code <= 0x9FFF     # CJK ideographs
            or 0xFF00 <= code <= 0xFFEF)    # fullwidth forms


def flatten_text(text: str) -> str:
    """Join an FMG string's hard line breaks into one display line.

    FMG names wrap by hand ("...scarlet rot-afflicted\\nenemy", "...命中时，\\n　能对着..."),
    which looks broken in a table cell.  CJK lines are joined without a space,
    latin ones with one.
    """
    parts = [part.strip().strip("　").strip()
             for part in (text or "").replace("\r\n", "\n").split("\n")]
    parts = [part for part in parts if part]
    out = ""
    for part in parts:
        if out:
            out += "" if (_is_cjk(out[-1]) and _is_cjk(part[0])) else " "
        out += part
    return out


def read_fmg(bnd: str, name: str, lang: str) -> dict[str, str]:
    merged: dict[str, str] = {}
    for suffix in ("", "_dlc01"):
        path = MSG_DIR / lang / f"{bnd}_dlc01" / f"{name}{suffix}.json"
        if path.exists():
            for key, value in json.loads(path.read_text(encoding="utf-8")).items():
                merged[key] = flatten_text(value or "")
    return merged


def as_number(text: str) -> float | int:
    value = float(text)
    return int(value) if value.is_integer() else round(value, 6)


def is_default(row: dict[str, str], field: str) -> bool:
    default = FIELD_DEFAULTS.get(field)
    if default is None or field not in row:
        return True
    raw = row[field]
    try:
        return float(raw) == float(default)
    except ValueError:
        return raw == default


def ref(value: str | None) -> str | None:
    """Normalise a param reference: '' / '0' / '-1' mean 'not set'."""
    if value is None:
        return None
    value = value.strip()
    if value in ("", "0", "-1"):
        return None
    return value


def rate_direction(key: str, value: float) -> int:
    """+1 = the player hits harder, -1 = weaker, 0 = default."""
    group = RATE_FIELD_BY_KEY[key]["group"]
    default = float(FIELD_DEFAULTS[key])
    if value == default:
        return 0
    if group == "special":
        # currentHealthAttackRate / restageAttackRate: any override enables
        # an extra damage source, the neutral value is "off".  (The value
        # itself is NOT a multiplier -- see the group note.)
        return 1
    sign = 1 if value > default else -1
    if RATE_FIELD_BY_KEY[key].get("lowerIsBetter"):
        # consumption / cooldown style fields: the *lower* the better, so a
        # value below the default is a gain for the player.  Judging by the
        # field name alone (as this used to) called artsConsumptionRate=0.8
        # a downgrade and artsConsumptionRate=1.2 a downgrade as well.
        return -sign
    return sign


def clean_param_name(name: str) -> str:
    name = (name or "").strip()
    while name.startswith("["):
        end = name.find("]")
        if end < 0:
            break
        name = name[end + 1:].strip()
    return name


# --------------------------------------------------------------------------
# main build
# --------------------------------------------------------------------------
def build() -> dict[str, Any]:
    sp_rows = read_param("SpEffectParam")
    sp = index_param(sp_rows)

    attach_rows = read_param("AttachEffectParam")
    attach = index_param(attach_rows)
    attach_table = read_param("AttachEffectTableParam")
    pooled_affixes = {r["attachEffectId"] for r in attach_table if ref(r["attachEffectId"])}

    accessories = read_param("EquipParamAccessory")
    accessory_attach_ids = {
        value
        for row in accessories
        for value in (ref(row.get(f)) for f in ("spEffectId_1", "spEffectId_2", "spEffectId_3"))
        if value
    }
    goods = read_param("EquipParamGoods")
    weapons = read_param("EquipParamWeapon")
    magics = read_param("Magic")
    bullets = index_param(read_param("Bullet"))
    permanents = read_param("PermanentBuffParam")

    zh = {
        "attach": read_fmg("item", "AttachEffectName", "zhocn"),
        "accessory": read_fmg("item", "AccessoryName", "zhocn"),
        "goods": read_fmg("item", "GoodsName", "zhocn"),
        "weapon": read_fmg("item", "WeaponName", "zhocn"),
        "magic": read_fmg("item", "MagicName", "zhocn"),
        "permanent": read_fmg("item", "PermanentBuffName", "zhocn"),
        "speffect": read_fmg("menu", "SpEffectName", "zhocn"),
        "speffectInfo": read_fmg("menu", "SpEffectInfo", "zhocn"),
    }
    en = {
        "attach": read_fmg("item", "AttachEffectName", "engus"),
        "accessory": read_fmg("item", "AccessoryName", "engus"),
        "goods": read_fmg("item", "GoodsName", "engus"),
        "weapon": read_fmg("item", "WeaponName", "engus"),
        "magic": read_fmg("item", "MagicName", "engus"),
        "permanent": read_fmg("item", "PermanentBuffName", "engus"),
        "speffect": read_fmg("menu", "SpEffectName", "engus"),
    }

    missing_zh: list[str] = []
    missing_item_zh: list[str] = []

    def classify(sp_id: str) -> tuple[bool, str] | tuple[bool, None]:
        """(qualifies, direction) for an SpEffect row."""
        row = sp.get(sp_id)
        if row is None:
            return False, None
        ups = downs = 0
        damage_change = False
        for field in RATE_FIELDS:
            key = field["key"]
            if field["group"] not in QUALIFY_GROUPS or key not in row or is_default(row, key):
                continue
            direction = rate_direction(key, float(row[key]))
            if direction > 0:
                ups += 1
            elif direction < 0:
                downs += 1
            if field["group"] in DAMAGE_GROUPS:
                damage_change = True
        if not ups and not downs:
            return False, None
        direction = "increase" if ups and not downs else "decrease" if downs and not ups else "mixed"
        # a pure downgrade only stays in when it really lowers damage output
        # (this drops e.g. the anti-buildup boluses, which "reduce" a status
        # buildup value on the user themselves)
        if direction == "decrease" and not damage_change:
            return False, None
        return True, direction

    def qualifies(sp_id: str) -> bool:
        return classify(sp_id)[0]

    # --- collect sources -------------------------------------------------
    # sources[spEffectId] -> list of source dicts (dedup-ed by (kind, id, via))
    sources: dict[str, list[dict[str, Any]]] = defaultdict(list)
    seen_source: set[tuple[str, str, str, str]] = set()
    # every spEffect we can reach from a player-facing item (buff or not),
    # used as the seed set for chain expansion
    seeds: set[str] = set()

    def add_source(sp_id: str, kind: str, item_id: str | None, name_zh: str | None,
                   name_en: str | None, via: str, trigger: bool = False,
                   extra: dict[str, Any] | None = None) -> None:
        # item_id is None for entries that have no row in the source table at
        # all (the inferred pass below).  Those must NOT borrow the spEffectId
        # as an id: EquipParamWeapon really does have a row 1800 while
        # SpEffect 1800 is "[AoW] Hoarfrost Stomp - Frost", so a consumer
        # joining on (kind, id) would silently show the wrong item.
        key = (sp_id, kind, item_id or "", via)
        if key in seen_source:
            return
        seen_source.add(key)
        entry: dict[str, Any] = {
            "kind": kind,
            "id": int(item_id) if item_id is not None else None,
            "via": via,
        }
        if name_zh:
            entry["nameZh"] = name_zh
        if name_en:
            entry["nameEn"] = name_en
        if trigger:
            entry["trigger"] = True
        if extra:
            entry.update(extra)
        sources[sp_id].append(entry)

    def attach_names(attach_row: dict[str, str]) -> tuple[str | None, str | None]:
        text_id = attach_row.get("attachTextId") or attach_row["ID"]
        name_zh = zh["attach"].get(text_id) or zh["attach"].get(attach_row["ID"])
        name_en = en["attach"].get(text_id) or en["attach"].get(attach_row["ID"])
        if not name_en:
            name_en = clean_param_name(attach_row.get("Name", "")) or None
        return (name_zh or None), name_en

    def attach_sibling_names(sp_id: str) -> tuple[str | None, str | None]:
        """Chinese name of the AttachEffectParam row this SpEffect belongs to.

        Relic affix effects are numbered <affix base>+step: AttachEffectParam
        7120000 "出击时的武器，附加魔力属性攻击力" owns SpEffects 7120001..7120004,
        AE 7290000 "【女爵】提升技艺造成的伤害" owns SpEffect 7290001.  Those step
        rows are applied by event scripts, so no param column points at them and
        they end up with an English paramName only.  Round the id down to the
        decade (then the century) and reuse the affix's own name.
        """
        value = int(sp_id)
        for base in (value - value % 10, value - value % 100):
            if base == value:
                continue
            attach_row = attach.get(str(base))
            if attach_row is None:
                continue
            sibling_zh, sibling_en = attach_names(attach_row)
            if sibling_zh:
                return sibling_zh, sibling_en
        return None, None

    def display_name(base: str | None, src_list: list[dict[str, Any]],
                     zh: bool, param_name: str | None) -> str | None:
        """"状态名（来源物品名）" -- what a ranking row should actually print.

        nameZh is the status-bar text, which repeats a lot (92 buffs are called
        "提升攻击力"), so it is useless on its own in a list.  When no source has
        a Chinese name (event-script weapon/AoW buffs) the English source name,
        then the Paramdex row name, is used instead -- an ugly disambiguator
        beats 85 identical rows.
        """
        if not base:
            return None
        key_sets = [("nameZh", "effectNameZh"), ("nameEn", "effectNameEn")]
        if not zh:
            key_sets = key_sets[1:]
        origin = None
        for keys in key_sets:
            for entry in src_list:
                origin = next((entry[key] for key in keys if entry.get(key)), None)
                if origin:
                    break
            if origin:
                break
        if not origin:
            origin = clean_param_name(param_name or "") or None
        if not origin or origin == base or origin in base:
            return base
        if base in origin:
            # the source name is the same statement, spelled out
            # ("提升攻击力" vs "装备三把以上类别为短剑的武器，能提升攻击力")
            return origin
        return f"{base}（{origin}）" if zh else f"{base} ({origin})"

    # (a) relic affixes -- AttachEffectParam rows that appear in a relic pool
    for row in attach_rows:
        attach_id = row["ID"]
        is_pooled = attach_id in pooled_affixes
        if "Debug" in (row.get("Name") or ""):
            continue
        if not is_pooled and attach_id in accessory_attach_ids:
            continue  # covered by the accessory pass below, with the item name
        name_zh, name_en = attach_names(row)
        for field, via, trigger in ATTACH_SPEFFECT_FIELDS:
            target = ref(row.get(field))
            if not target:
                continue
            seeds.add(target)
            kind = "relicAffix" if is_pooled else "other"
            add_source(target, kind, attach_id, name_zh, name_en, field,
                       trigger=trigger,
                       extra={"attachEffectId": int(attach_id)} if kind == "other" else None)

    # (b) talismans / accessories -- EquipParamAccessory -> AttachEffectParam
    for row in accessories:
        acc_id = row["ID"]
        name_zh = zh["accessory"].get(acc_id)
        name_en = en["accessory"].get(acc_id) or clean_param_name(row.get("Name", "")) or None
        if not (name_zh or name_en):
            continue
        for field in ("spEffectId_1", "spEffectId_2", "spEffectId_3"):
            attach_id = ref(row.get(field))
            if not attach_id:
                continue
            attach_row = attach.get(attach_id)
            if attach_row is None:
                continue
            effect_zh, effect_en = attach_names(attach_row)
            for sub_field, via, trigger in ATTACH_SPEFFECT_FIELDS:
                target = ref(attach_row.get(sub_field))
                if not target:
                    continue
                seeds.add(target)
                extra: dict[str, Any] = {"attachEffectId": int(attach_id)}
                if effect_zh:
                    extra["effectNameZh"] = effect_zh
                if effect_en:
                    extra["effectNameEn"] = effect_en
                add_source(target, "accessory", acc_id, name_zh, name_en,
                           f"{field}->{sub_field}", trigger=trigger, extra=extra)

    # (c) consumables -- EquipParamGoods
    goods_fields = ["refId_default", "refId_1", "level2RefId", "level2RefId_1",
                    "level3RefId", "level3RefId_1"]
    for row in goods:
        goods_id = row["ID"]
        name_zh = zh["goods"].get(goods_id)
        name_en = en["goods"].get(goods_id) or clean_param_name(row.get("Name", "")) or None
        if not (name_zh or name_en):
            continue
        category = row.get("refCategory", "0")
        targets: list[tuple[str, str]] = []
        for field in goods_fields:
            value = ref(row.get(field))
            if not value:
                continue
            if category == "2":
                targets.append((value, field))
            elif category == "1":
                bullet = bullets.get(value)
                if bullet is None:
                    continue
                for bullet_field in BULLET_SPEFFECT_FIELDS:
                    inner = ref(bullet.get(bullet_field))
                    if inner:
                        targets.append((inner, f"{field}->Bullet{value}.{bullet_field}"))
        for field in ("carrySpEffectId", "emptySpEffectId"):
            value = ref(row.get(field))
            if value:
                targets.append((value, field))
        for target, via in targets:
            seeds.add(target)
            add_source(target, "goods", goods_id, name_zh, name_en, via)

    # (d) weapon passives -- EquipParamWeapon
    weapon_fields = ["spEffectBehaviorId0", "spEffectBehaviorId1", "spEffectBehaviorId2",
                     "residentSpEffectId", "residentSpEffectId1", "residentSpEffectId2"]
    for row in weapons:
        weapon_id = int(row["ID"])
        base_id = weapon_id - (weapon_id % 100)
        name_zh = zh["weapon"].get(str(weapon_id)) or zh["weapon"].get(str(base_id))
        name_en = en["weapon"].get(str(weapon_id)) or en["weapon"].get(str(base_id))
        if not (name_zh or name_en):
            continue
        for field in weapon_fields:
            target = ref(row.get(field))
            if not target:
                continue
            seeds.add(target)
            add_source(target, "weaponPassive", str(base_id), name_zh, name_en, field)

    # (e) spells -- Magic (direct SpEffect, or through a Bullet)
    for row in magics:
        magic_id = row["ID"]
        name_zh = zh["magic"].get(magic_id)
        name_en = en["magic"].get(magic_id) or clean_param_name(row.get("Name", "")) or None
        if not (name_zh or name_en):
            continue
        for index in range(1, 11):
            category = row.get(f"refCategory{index}", "-1")
            value = ref(row.get(f"refId{index}"))
            if not value:
                continue
            targets: list[tuple[str, str]] = []
            if category == "2":
                targets.append((value, f"refId{index}"))
            elif category == "1":
                bullet = bullets.get(value)
                if bullet is None:
                    continue
                for bullet_field in BULLET_SPEFFECT_FIELDS:
                    inner = ref(bullet.get(bullet_field))
                    if inner:
                        targets.append((inner, f"refId{index}->Bullet{value}.{bullet_field}"))
            for target, via in targets:
                seeds.add(target)
                add_source(target, "spell", magic_id, name_zh, name_en, via)

    # (f) permanent buffs -- PermanentBuffParam
    permanent_en_index: dict[str, str] = {}
    for text_id, text in en["permanent"].items():
        permanent_en_index.setdefault(text.strip().lower(), text_id)
    for row in permanents:
        buff_id = row["ID"]
        param_name = clean_param_name(row.get("Name", ""))
        stripped = param_name.split(" (")[0].strip()
        text_id = None
        if buff_id in zh["permanent"] or buff_id in en["permanent"]:
            text_id = buff_id
        if text_id is None:
            text_id = permanent_en_index.get(stripped.lower())
        if text_id is None:
            trimmed = str(int(buff_id) - int(buff_id) % 10)
            if en["permanent"].get(trimmed, "").strip().lower() == stripped.lower():
                text_id = trimmed
        name_zh = zh["permanent"].get(text_id or "", None)
        name_en = en["permanent"].get(text_id or "", None) or param_name or None
        for field in ("spEffectId", "graceSpEffectId"):
            target = ref(row.get(field))
            if not target:
                continue
            seeds.add(target)
            add_source(target, "permanent", buff_id, name_zh, name_en, field)

    # --- chain expansion --------------------------------------------------
    # a relic/talisman/grease often points at a "carrier" SpEffect with no rates
    # whose cycle/atkOccurrence/replace child holds the actual buff, so the item
    # provenance is inherited one link at a time.
    frontier = set(seeds)
    visited = set(seeds)
    for _ in range(CHAIN_DEPTH):
        next_frontier: set[str] = set()
        for parent_id in sorted(frontier, key=int):
            parent_row = sp.get(parent_id)
            if parent_row is None:
                continue
            inherited = sources.get(parent_id) or []
            for field, label in CHAIN_FIELDS:
                child = ref(parent_row.get(field))
                if not child or child == parent_id or child in seeds:
                    continue
                if inherited:
                    for entry in inherited[:CHAIN_INHERIT_LIMIT]:
                        via = f"{entry['via']}->{field}"
                        if len(via) > 120:
                            via = f"...->{field}"
                        extra = ({"attachEffectId": entry["attachEffectId"]}
                                 if "attachEffectId" in entry else None)
                        add_source(child, entry["kind"], str(entry["id"]),
                                   entry.get("nameZh"), entry.get("nameEn"),
                                   via, trigger=True, extra=extra)
                else:
                    add_source(child, "other", parent_id, None,
                               clean_param_name(parent_row.get("Name", "")) or None,
                               field, trigger=True)
                if child not in visited:
                    visited.add(child)
                    next_frontier.add(child)
        frontier = next_frontier
        if not frontier:
            break

    # --- orphan pass ------------------------------------------------------
    # Ashes of War, hero skill/ultimate buffs and a handful of character relic
    # effects are applied by event scripts, so no param column points at them.
    # Fall back to the Paramdex row name for those, restricted to player-facing
    # prefixes, and mark them as inferred.
    for sp_id, row in sp.items():
        if sp_id in sources:
            continue
        param_name = (row.get("Name") or "").strip()
        if not param_name.startswith("["):
            continue
        end = param_name.find("]")
        if end < 0:
            continue
        prefix = param_name[1:end].strip()
        kind = None
        for candidate, mapped in ORPHAN_PREFIX_KINDS:
            if prefix == candidate or prefix.startswith(candidate + " ") or prefix.startswith(candidate):
                if prefix == candidate or prefix[len(candidate):len(candidate) + 1] in (" ", "-", ""):
                    kind = mapped
                    break
        if kind is None:
            continue
        if not qualifies(sp_id):
            continue
        add_source(sp_id, kind, None, None, clean_param_name(param_name) or None,
                   "paramRowName", extra={"inferred": True, "paramRowCategory": prefix})

    # --- emit buffs -------------------------------------------------------
    buffs: list[dict[str, Any]] = []
    display_inputs: dict[int, tuple[list[dict[str, Any]], str | None]] = {}
    for sp_id in sorted(sources, key=int):
        row = sp.get(sp_id)
        if row is None:
            continue
        keep, direction = classify(sp_id)
        if not keep:
            continue
        rates: dict[str, Any] = {}
        for field in RATE_FIELDS:
            key = field["key"]
            if key in row and not is_default(row, key):
                rates[key] = as_number(row[key])

        text_ids = [ref(row.get(f"spEffectTextId_{i}")) for i in range(1, 5)]
        text_ids = [t for t in text_ids if t]

        def unique(values: list[str]) -> list[str]:
            """Keep first occurrence only -- spEffectTextId_1..4 often repeat
            the same text id (e.g. 46296 「炼金碎片」 three times)."""
            seen: set[str] = set()
            out: list[str] = []
            for value in values:
                if value not in seen:
                    seen.add(value)
                    out.append(value)
            return out

        labels_zh = unique([zh["speffect"][t] for t in text_ids if t in zh["speffect"]])
        labels_en = unique([en["speffect"][t] for t in text_ids if t in en["speffect"]])

        ordered = sorted(sources[sp_id],
                         key=lambda item: (SOURCE_KIND_ORDER.get(item["kind"], 99),
                                           0 if item.get("nameZh") else 1,
                                           item["id"] is None,
                                           item["id"] or 0))
        src_list = ordered[:MAX_SOURCES_PER_BUFF]
        name_zh = (labels_zh[0] if labels_zh else None)
        name_source = "spEffectName" if name_zh else None
        for key, origin in (("effectNameZh", "attachEffectName"), ("nameZh", "itemName")):
            if name_zh:
                break
            for entry in src_list:
                if entry.get(key):
                    name_zh = entry[key]
                    if origin == "itemName" and entry["kind"] in ("relicAffix", "other"):
                        # for relic affixes the item *is* the effect
                        name_source = "attachEffectName"
                    else:
                        name_source = origin
                    break
        name_en = (labels_en[0] if labels_en else None)
        for key in ("effectNameEn", "nameEn"):
            if name_en:
                break
            for entry in src_list:
                if entry.get(key):
                    name_en = entry[key]
                    break
        inferred_name = False
        if not name_zh:
            # Last resort for the event-script / "potency step" SpEffects: the
            # relic affix they belong to is the AttachEffectParam row at the
            # start of their own decade / century (7120001..7120004 all belong
            # to AE 7120000 "出击时的武器，附加魔力属性攻击力").  Only used when
            # nothing else produced a name, and flagged with inferredName.
            sibling_zh, sibling_en = attach_sibling_names(sp_id)
            if sibling_zh:
                name_zh = sibling_zh
                name_source = "attachEffectName"
                inferred_name = True
                # nameEn keeps whatever it already had (usually the Paramdex row
                # name, which spells out the potency step and so is strictly
                # more informative than the affix name).
                if not name_en:
                    name_en = sibling_en
        if not name_en:
            name_en = clean_param_name(row.get("Name", "")) or None
        if not name_zh:
            missing_zh.append(f"{sp_id} {row.get('Name') or ''} -> {name_en}".strip())
            name_source = None

        sp_category = int(row["spCategory"])
        behaviour, _behaviour_zh = spcategory_behaviour(sp_category)
        if behaviour in ("none", "stackSelf"):
            group = f"sp{sp_category}#{sp_id}"
        else:
            group = f"sp{sp_category}"

        scope: dict[str, Any] = {
            "affectsSorcery": row["magParamChange"] == "1",
            "affectsIncantation": row["miracleParamChange"] == "1",
            "affectsShaman": row["shamanParamChange"] == "1",
            "affectsThrow": row["throwAttackParamChange"] == "1",
        }
        wep_change = int(row["wepParamChange"])
        if wep_change:
            scope["weaponSlot"] = wep_change          # -> enums.wepParamChange
        atk_attr = int(row["atkAttribute"])
        if atk_attr != 254:
            scope["atkAttribute"] = atk_attr          # -> enums.atkAttribute
        sp_attr = int(row["spAttribute"])
        if sp_attr != 254:
            scope["spAttribute"] = sp_attr            # -> enums.spAttribute
        sub_categories = [
            int(row[f"magicSubCategoryChange{index}"])
            for index in (1, 2, 3)
            if int(row[f"magicSubCategoryChange{index}"])
        ]
        if sub_categories:
            scope["subCategories"] = sub_categories   # -> enums.atkSubCategory

        conditions: dict[str, Any] = {}
        for key, _label in CONDITION_FIELDS:
            if key in row and not is_default(row, key):
                conditions[key] = as_number(row[key])

        chain: list[dict[str, Any]] = []
        for key, _label in CHAIN_FIELDS:
            target = ref(row.get(key))
            if target:
                chain.append({"field": key, "spEffectId": int(target)})

        fallback_name = name_en or clean_param_name(row.get("Name", "")) or None
        entry: dict[str, Any] = {
            "spEffectId": int(sp_id),
            "nameZh": name_zh,
            "nameEn": name_en,
            "nameSource": name_source,
            # provisional; disambiguated against the whole list further down
            "displayNameZh": name_zh or fallback_name,
            "displayNameEn": name_en,
            "paramName": row.get("Name") or None,
            "sources": src_list,
            "rates": rates,
            "rateGroups": sorted({
                RATE_FIELD_BY_KEY[key]["group"] for key in rates
            }),
            "direction": direction,
            "scope": scope,
            "stacking": {
                "stateInfo": int(row["stateInfo"]),
                "spCategory": sp_category,
                "spCategoryBehavior": behaviour,
                "categoryPriority": int(row["categoryPriority"]),
                "saveCategory": int(row["saveCategory"]),
                "group": group,
            },
            "duration": as_number(row["effectEndurance"]),
            "permanent": float(row["effectEndurance"]) == -1.0,
            "affectsAllies": row["effectTargetFriend"] == "1",
        }
        if inferred_name:
            entry["inferredName"] = True
        if labels_zh:
            entry["statusLabelsZh"] = labels_zh
        if labels_en:
            entry["statusLabelsEn"] = labels_en
        info = zh["speffectInfo"].get(text_ids[0]) if text_ids else None
        if info:
            entry["descZh"] = info
        if conditions:
            entry["conditions"] = conditions
        if chain:
            entry["chainSpEffectId"] = chain
        if len(sources[sp_id]) > MAX_SOURCES_PER_BUFF:
            entry["sourcesTruncated"] = len(sources[sp_id])
        if any(item.get("trigger") for item in src_list):
            entry["triggered"] = True
        for item in src_list:
            if not item.get("nameZh") and not item.get("inferred"):
                missing_item_zh.append(
                    f"{item['kind']} {item['id']} ({item.get('nameEn') or '?'})")
        buffs.append(entry)
        display_inputs[int(sp_id)] = (src_list, row.get("Name"))

    # --- display names ----------------------------------------------------
    # Only names that actually collide get the "（来源）" suffix: a unique name
    # such as 「【女爵】提升技艺造成的伤害」 stays clean, while the 92 buffs called
    # 「提升攻击力」 all get told apart.
    for field, is_zh in (("displayNameZh", True), ("displayNameEn", False)):
        counts = defaultdict(int)
        for buff in buffs:
            if buff[field]:
                counts[buff[field]] += 1
        for buff in buffs:
            base = buff[field]
            if not base or counts[base] < 2:
                continue
            src_list, param_name = display_inputs[buff["spEffectId"]]
            buff[field] = display_name(base, src_list, zh=is_zh, param_name=param_name)

    # --- counts -----------------------------------------------------------
    kind_counts: dict[str, int] = defaultdict(int)
    kind_buffs: dict[str, set[int]] = defaultdict(set)
    for buff in buffs:
        for entry in buff["sources"]:
            kind_counts[entry["kind"]] += 1
            kind_buffs[entry["kind"]].add(buff["spEffectId"])
    group_counts: dict[str, int] = defaultdict(int)
    for buff in buffs:
        for group in buff["rateGroups"]:
            group_counts[group] += 1

    payload = OrderedDict()
    payload["schemaVersion"] = SCHEMA_VERSION
    payload["datasetId"] = "nightreign-buffs"
    payload["gameVersion"] = GAME_VERSION
    payload["dataVersion"] = DATA_VERSION
    payload["generatedAt"] = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    payload["sources"] = [
        {
            "name": "ELDEN RING NIGHTREIGN regulation params",
            "detail": "本地导出的 252 张参数表 raw/params/*.csv（regulation 10350000 / exe 1.3.3.0）",
            "license": "游戏内资料，仅用于同人工具的数值展示",
            "usage": "SpEffectParam / AttachEffectParam / AttachEffectTableParam / EquipParamAccessory / EquipParamGoods / EquipParamWeapon / Magic / Bullet / PermanentBuffParam",
        },
        {
            "name": "ELDEN RING NIGHTREIGN message FMG",
            "detail": "本地导出的简中(zhocn)与英文(engus)文本 raw/msg/<lang>/<bnd>_dlc01/*.json（基础档与 _dlc01 增量合并）",
            "license": "游戏内资料，仅用于同人工具的数值展示",
            "usage": "AttachEffectName / AccessoryName / GoodsName / WeaponName / MagicName / PermanentBuffName / SpEffectName / SpEffectInfo",
        },
        {
            "name": "Smithbox Paramdex (NR)",
            "url": f"https://github.com/vawser/Smithbox/tree/{SMITHBOX_COMMIT}/src/Smithbox.Data/Assets/PARAM/NR",
            "license": "MIT",
            "usage": "字段默认值（Param Meta）与枚举 ATK_SUB_CATEGORY / SP_EFE_WEP_CHANGE_PARAM / ATKPARAM_ATKATTR_TYPE / ATKPARAM_SPATTR_TYPE / SP_EFFECT_SPCATEGORY，已转写进本脚本常量表，运行时不联网",
        },
        {
            "name": "Smithbox Paramdex (ER) SpEffect paramdef",
            "url": f"https://github.com/vawser/Smithbox/blob/{SMITHBOX_COMMIT}/src/Smithbox.Data/Assets/PARAM/ER/Defs/SpEffect.xml",
            "license": "MIT",
            "usage": "字段日文说明（攻撃側ダメージ倍率 / 攻撃力倍率 等），用于确定各倍率字段的作用层",
        },
    ]
    payload["notes"] = {
        "zh": "只收录「能提升玩家自身输出」且能从玩家可获得的物品／法术／永久强化追溯到的 SpEffect。"
              "本作没有独立的『战技伤害 +x%』类字段，针对战技／跳跃攻击／防御反击／绝招等的强化"
              "都是普通的 AttackRate 字段 + magicSubCategoryChange 子类过滤，见每条 buff 的 scope。",
        "damageTypeNaming": "参数里的 dark 槽位在本作即『圣』属性；physics 为物理总量，slash/blow/thrust/neutral 是物理攻击类型细分。",
        "howToUseRates": "把 rates 折算成伤害之前，必须先看 rateFields[key].valueKind："
                         "multiplier 可直接相乘；flat 是点数，要先加进攻击力再乘倍率；"
                         "flag 只是开关，不参与计算；special 的每个字段语义各不相同、"
                         "**一律不得相乘**（restageAttackRate=0.6 指女爵『再演』复制那一份占 60%，"
                         "不是 -40% 伤害）。另可用 rateFieldGroups[].countsAsDamage 做粗筛："
                         "false 的组（stance 削韧、status 异常累积、special、flag、economy）不进伤害乘积，只单独展示。",
        "displayName": "nameZh 取自状态栏文本，重名极多（『提升攻击力』92 条、『异常状态：冻伤』53 条），"
                       "**任何列表都不要只显示 nameZh**。请直接用 displayNameZh／displayNameEn："
                       "名字本身唯一时它就等于 nameZh，出现重名时会自动补上来源（『提升攻击力（黄金树立誓）』），"
                       "来源没有中文名时退化为英文名或 Paramdex 行名。仍有极少数同名条目是同一道具的不同强度档位"
                       "（如六级『结冰油脂』），用 rates 的数值区分即可。",
    }
    rate_field_usage: dict[str, int] = defaultdict(int)
    for buff in buffs:
        for key in buff["rates"]:
            rate_field_usage[key] += 1

    payload["rateFieldGroups"] = [
        {
            "key": group["key"],
            "zh": group["zh"],
            "countsAsDamage": group["countsAsDamage"],
            "qualifies": group["qualifies"],
            "note": group["note"],
        }
        for group in RATE_FIELD_GROUPS
    ]
    payload["rateFields"] = [
        {
            "key": field["key"],
            "zh": field["zh"],
            "en": field["en"],
            "default": field["default"],
            "group": field["group"],
            "valueKind": field["valueKind"],
            "countsAsDamage": field["group"] in COUNTS_AS_DAMAGE_GROUPS,
            "observedCount": rate_field_usage.get(field["key"], 0),
            **({"lowerIsBetter": True} if field.get("lowerIsBetter") else {}),
            "appliesTo": field["appliesTo"],
        }
        for field in RATE_FIELDS
    ]
    payload["enums"] = {
        "atkSubCategory": {str(k): {"zh": v[0], "en": v[1]} for k, v in ATK_SUB_CATEGORY.items()},
        "wepParamChange": {str(k): {"zh": v[0], "en": v[1]} for k, v in WEP_CHANGE_PARAM.items()},
        "atkAttribute": {str(k): {"zh": v[0], "en": v[1]} for k, v in ATK_ATTR_TYPE.items()},
        "spAttribute": {str(k): {"zh": v[0], "en": v[1]} for k, v in SP_ATTR_TYPE.items()},
        "spCategoryBehavior": [
            {"min": lo, "max": hi, "code": code, "zh": text}
            for lo, hi, code, text in SPCATEGORY_BEHAVIOUR
        ] + [
            # catch-all so that every value stacking.spCategoryBehavior can
            # print is resolvable to a label
            {"min": None, "max": None, "code": SPCATEGORY_UNKNOWN[0],
             "zh": SPCATEGORY_UNKNOWN[1]},
        ],
        "sourceKind": {
            "relicAffix": "遗物词条",
            "accessory": "护符／饰品",
            "goods": "消耗品／道具",
            "weaponPassive": "武器被动",
            "spell": "魔法／祷告",
            "permanent": "永久强化",
            "heroSkill": "角色技艺／绝招／被动",
            "other": "其他（未归入遗物词条池的 AttachEffect、链式来源或仅凭 Paramdex 行名推断的条目）",
        },
        "sourceIdContract": "sources[].id 是来源表的行 ID，可以按 (kind, id) 联表；"
                            "但 inferred=true 的条目在参数表里根本没有对应行（由游戏脚本挂载），"
                            "其 id 恒为 null，消费方看到 inferred:true 必须只用 nameEn / paramRowCategory 展示，不得联表。",
    }
    payload["conditionFields"] = [{"key": key, "zh": label} for key, label in CONDITION_FIELDS]
    payload["chainFields"] = [{"key": key, "zh": label} for key, label in CHAIN_FIELDS]
    payload["stackingRules"] = {"zh": STACKING_RULES_ZH}
    payload["counts"] = {
        "buffs": len(buffs),
        "sourceLinksByKind": dict(sorted(kind_counts.items())),
        "buffsByKind": {k: len(v) for k, v in sorted(kind_buffs.items())},
        "buffsByRateGroup": dict(sorted(group_counts.items())),
        "buffsWithoutChineseName": sum(1 for b in buffs if not b["nameZh"]),
        "buffsOnlyInferredFromParamRowName": sum(
            1 for b in buffs if b["sources"] and all(s.get("inferred") for s in b["sources"])
        ),
    }
    unique_missing = sorted(set(missing_zh))
    unique_missing_items = sorted(set(missing_item_zh))
    unused_rate_fields = [f["key"] for f in RATE_FIELDS if not rate_field_usage.get(f["key"])]
    unused_scope_keys = [
        key for key in ("weaponSlot", "atkAttribute", "spAttribute", "subCategories")
        if not any(key in b["scope"] for b in buffs)
    ]
    observed_behaviours = sorted({b["stacking"]["spCategoryBehavior"] for b in buffs})
    payload["diagnostics"] = {
        "buffsWithoutChineseName": len(unique_missing),
        "buffsWithoutChineseNameSample": unique_missing[:60],
        "sourceItemsWithoutChineseName": unique_missing_items[:40],
        "note": "没有简体中文名的 buff：绝大多数是只能靠 Paramdex 行名推断出来的战技／技艺／武器 buff（游戏内没有对应的 FMG 文本），已保留英文名与 paramName。",
        "buffsWithInferredName": sum(1 for b in buffs if b.get("inferredName")),
        "inferredNameNote": "inferredName=true 的 buff，其 nameZh 借用的是同族遗物词条（AttachEffectParam id-id%10 / id-id%100）的名字，"
                            "是同一条词条的不同档位，名字正确但不是该 SpEffect 自己的文本。",
        "unusedRateFields": unused_rate_fields,
        "unusedRateFieldsNote": "这些 rateFields 在本版本 827 条 buff 里 observedCount=0，页面无需为它们写分支；"
                                "保留是因为它们在 SpEffectParam 里确实存在（economy 组的字段在护符／道具上有非默认值，"
                                "只是那些 SpEffect 本身没有增伤字段、不在本数据集内），便于下个版本命中时自动出现。",
        "unusedScopeKeys": unused_scope_keys,
        "unusedScopeKeysNote": "本版本所有 buff 的 atkAttribute 都是 254（不限），因此 scope.atkAttribute 不会出现；"
                               "enums.atkAttribute 仍保留以备后续版本。",
        "observedSpCategoryBehaviors": observed_behaviours,
        "spCategoryNote": "全部 buff 的 stacking.spCategoryBehavior 都落在 enums.spCategoryBehavior 的已知区间内"
                          f"（本次实测取值：{'、'.join(observed_behaviours)}）；"
                          "spCategory 205/206/1007/1008 虽未出现在 Paramdex 枚举里，但已按所在区间（200 系＝removePrevious、1000 系＝applyHighest）归类。",
    }
    payload["buffs"] = buffs
    return payload


def main() -> None:
    parser = argparse.ArgumentParser(description="Generate the Nightreign damage-buff dataset.")
    parser.add_argument("--out", type=Path, default=DEFAULT_OUT,
                        help=f"output JSON path (default: {DEFAULT_OUT})")
    parser.add_argument("--indent", type=int, default=1,
                        help="json indent, 0 for compact (default: 1)")
    args = parser.parse_args()

    payload = build()
    args.out.parent.mkdir(parents=True, exist_ok=True)
    if args.indent:
        text = json.dumps(payload, ensure_ascii=False, indent=args.indent)
    else:
        text = json.dumps(payload, ensure_ascii=False, separators=(",", ":"))
    args.out.write_text(text + "\n", encoding="utf-8")

    size = args.out.stat().st_size
    print(f"wrote {args.out} ({size/1024:.1f} KiB)")
    print(json.dumps(payload["counts"], ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
