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
A second, unrelated place states the same kind of restriction: SpEffectParam's
`stateInfo` (SP_EFFECT_TYPE), where 367 = Enhance Critical Attacks and 197 =
Enhance Thrusting Counter Attacks.  `scope.attackContexts` folds both routes
into one vocabulary a ranking page can branch on -- without it the ten
critical-hit / thrusting-counter affixes (x1.10 .. x1.24) look like ordinary
always-on damage and get multiplied into the general DPS ranking.
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
import re
from collections import OrderedDict, defaultdict
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
PARAM_DIR = HERE / "raw" / "params"
MSG_DIR = HERE / "raw" / "msg"
DEFAULT_OUT = ROOT / "data" / "nightreign-buffs-v1.03.5.json"

SCHEMA_VERSION = 4
GAME_VERSION = "v1.03.5 + DLC1"
DATA_VERSION = "regulation 10350000"
SMITHBOX_COMMIT = "f5969c060cea240476e9dd4d6a64eafa9dbafaab"

CHAIN_DEPTH = 3
MAX_SOURCES_PER_BUFF = 40
CHAIN_INHERIT_LIMIT = 4

# What changed between published schema versions.  Exported as
# payload["schemaChangelog"] so a consumer can tell *programmatically* that the
# meaning of a field it already reads has been tightened (a pure "add a field"
# bump would not need this, but v1 -> v2 also narrowed countsAsDamage and
# affectsAllies, which silently changes any ranking built on v1).
SCHEMA_CHANGELOG: list[dict[str, Any]] = [
    {
        "version": 4,
        "zh": "① **activation 判定不再把计时列当成发动条件。** v3 的第③条规则是『conditions 非空 → conditional』，"
              "而 conditionFields 里混着两个纯机制字段：motionInterval"
              "（ER paramdef：発動間隔[s]／『何秒間隔で発生するのかを設定』，即效果每几秒重新 tick 一次）"
              "与 isPeriodicEffect（周期性 tick 开关）。它们不是玩家需要满足的游戏状态。"
              "v3 里 210 条 buff 仅凭这两个字段被判成 conditional，其中 8 条是全表最强的真实无条件增伤"
              "（708720 狂热香药·档位2 ×1.45、503550 狂热香药 ×1.35、1733000 夏玻利利的嘶吼 ×1.25、"
              "1605000 火焰啊赐予我力量 ×1.20、1660000 黄金树立誓 ×1.15 等），按 v3 文档实现的页面会把它们"
              "全部排除在默认排名之外。现在 has_conditions 只看非计时类条件列；"
              "conditionFields[] 每项新增 `isActivationCondition` 布尔，明确标出哪两个不是发动条件。"
              "② **新增 buffs[].scope.attackContexts（string[]）与 enums.attackContext。** "
              "『致命一击』『突刺反击』这类只在特定攻击情境生效的倍率，其限制写在 SpEffectParam.stateInfo 里"
              "（367 Enhance Critical Attacks、197 Enhance Thrusting Counter Attacks），"
              "v3 只把 stateInfo 当作裸数字放在 stacking.stateInfo，scope 里没有 subCategories，"
              "所以 10 条 ×1.1–1.24 的倍率在页面看来是『对所有攻击生效的常驻增伤』。"
              "attackContexts 把 magicSubCategoryChange 与 stateInfo 两条来路统一成一组机读键"
              "（criticalHit／thrustingCounter／guardCounter／chainFinisher／jumpAttack／chargedHeavyAttack…）；"
              "**attackContexts 非空的条目不得计入通用排名，只在用户勾选对应情境时参与乘算。**"
              "同时新增 enums.stateInfo（Paramdex SP_EFFECT_TYPE 的中英文标签）。"
              "③ **buffs[].target 修正 33 条。** 命中投递槽的识别过去只认 Bullet.spEffectId0..4，"
              "漏了 atkOccurrenceSpEffectId（攻击命中时投递）。油脂／附加属性武器的异常累积行"
              "（3176 毒油脂、3151 催眠油脂、1449001 冰霜武器、1632002 血炎武器等）与结构完全相同的"
              "弹道投递版（1722000 毒雾、1631001 授血）自相矛盾地一个标 self 一个标 enemy。"
              "现已把 atkOccurrenceSpEffectId 纳入命中槽，新增 targetSource "
              "attackHitOpposeOnly／attackHitSelfOnly／attackHitStatusPayload。"
              "④ **修正 v3 changelog ⑤ 与 enums.targetSource 里一句与参数相反的说明**："
              "v3 写『3176 毒油脂……根本没走命中槽……本数据集正确地把它标成 target=\"self\"』，"
              "但 3176 的投递路径正是 refId_default->atkOccurrenceSpEffectId，"
              "且 effectTargetSelfTarget=0，参数层面根本不允许挂在玩家身上。该举例已删除并改写。"
              "⑤ **新增 buffs[].stackLadder 与 activationSource stackLadderTier1／localizedNameCondition／"
              "paramRowPassiveTimed。** 7069001『每次打倒封印监牢里的囚犯，能提升攻击力』×1.05、"
              "7069201『每次打倒黑夜入侵者』×1.07、8988200『玛雷家的庇佑』、8998000『复仇的庇佑』"
              "在 v3 里是 passive／noEvidence，会被无条件乘进排名；它们其实都是叠层阶梯的第 1 层"
              "（参数表里 7069002-010 一路涨到 ×1.6289、7069202-210 到 ×1.9672），必须先反复达成条件。"
              "⑥ diagnostics.topUnconditionalMultipliers 由 15 条扩到 40 条并排除 attackContexts 非空的条目；"
              "被排除的那一批改列在新的 diagnostics.contextGatedMultipliers。",
    },
    {
        "version": 3,
        "zh": "① **新增 buffs[].activation（passive／conditional／activated）与 activationSource**，"
              "配套 enums.activation／enums.activationSource、counts.buffsByActivation、notes.activation。"
              "v2 的 notes.ranking 第 ③ 步要求页面用 conditions／triggered 过滤发动条件型 buff，"
              "但榜首的 704301（残血 ×1.5）、8300000-2（双手持 +18%）、8310000-2（双持 +18%）、"
              "707201-215（绝招兽化 ×1.62–3.55）的 conditions 与 triggered 全是 null，那一步是空转的。"
              "**排名默认只能乘 activation=\"passive\" 的条目。**"
              "② **buffs[].target 修正一条**：1631001『授血（血炎出血）』的 via 形如 "
              "`refId1->Bullet10631000.spEffectId0->cycleOccurrenceSpEffectId`，"
              "旧正则带 `$` 锚匹配不到链式后缀，导致这条挂在敌人身上的出血累积被标成 self；"
              "现已按规则重算为 target=\"enemy\"／targetSource=\"bulletHitOffensiveBullet\"，"
              "与同类的『冰雾』『毒雾』一致（status 组 countsAsDamage=false，不影响伤害乘积）。"
              "③ **buffs 少一条（704000）**：它唯一的合格数值是 characterSkillCooldownReduction=0 "
              "且 effectEndurance=0，是无赖反击免伤窗口里的哨兵值而非『冷却 -100%』；"
              "改为记进 diagnostics.sentinelOnlyRows 而不是当成 buff 输出。"
              "④ **displayNameZh／En 的消歧顺序变了**（唯一性保证不变）：原始英文 Paramdex 行名由第一级"
              "降到倒数第二级，中间新增『来源类别』一级，并强制同族条目取相同的限定词组合；"
              "依赖 displayName 字符串做键的消费方需要重取。"
              "⑤ enums.targetSource 里 bulletHitOpposeOnly／bulletHitFriendlyOnly 的说明改写："
              "阵营过滤位必须在『已确认投递路径是命中槽』的前提下才有判定力。"
              "（**v4 更正**：v3 这一条原本举 3176 毒油脂为『阵营位是 oppose-only 却挂在玩家身上』的反例，"
              "该举例是错的——3176 走的正是 refId_default->atkOccurrenceSpEffectId 这个命中槽，"
              "且 effectTargetSelfTarget=0，v4 已把它改判为 target=\"enemy\"。"
              "当前的正确表述与真实反例见 v4 条目④与 diagnostics.opposeBitsWithoutHitSlot。）",
    },
    {
        "version": 2,
        "zh": "① countsAsDamage 收紧为『通用血量伤害』：stance／status／special／flag／economy 之外，"
              "weakness（特攻）与 critical（致命一击）也改为 false，改由新增的 conditionalDamage=true 标记"
              "——它们确实改血量伤害，但只在选定敌人类型／打出致命一击后才成立，不能无条件乘进通用排名。"
              "② 新增 buffs[].target（self／ally／summon／enemy）与 targetSource：数据集里存在挂在敌人身上的减益、"
              "魅惑敌人的增伤、复仇者家人（召唤物）自身的数值缩放，排名必须先按 target 过滤。"
              "③ affectsAllies 由 effectTargetFriend 原始位（827 条里 817 条为 true，等于无信息）改为按"
              "『友方 AoE 弹道投递』或『行名明示 Allies』判定；原始位保留在新字段 effectTargetFriendRaw。"
              "④ displayNameZh／displayNameEn 现在保证全表唯一（生成时断言）。"
              "⑤ economy 组（消耗／冷却／绝招量表／弓射程）改为 qualifies=true，这些真实的输出效率手段不再被整条丢弃。",
    },
    {
        "version": 1,
        "zh": "初版：rateFields / rateFieldGroups / valueKind / observedCount / displayName / sourceIdContract。",
    },
]

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
         group="weakness",
         appliesTo="对「特攻Ａ」类敌人的额外倍率（敌人侧由 EquipParamWeapon/NpcParam 的 weakA 判定），"
                   "对其它敌人恒为 1；conditionalDamage=true，必须先选定目标敌人类型才能计入伤害乘积。"),
    dict(key="weakDmgRateB", zh="特攻Ｂ倍率", en="Weakness B damage rate", default=1.0,
         group="weakness",
         appliesTo="对「特攻Ｂ」类敌人的额外倍率，对其它敌人恒为 1；"
                   "conditionalDamage=true，必须先选定目标敌人类型才能计入伤害乘积。"),
    dict(key="weakDmgRateC", zh="特攻Ｃ倍率", en="Weakness C damage rate", default=1.0,
         group="weakness",
         appliesTo="对「特攻Ｃ」类敌人的额外倍率，对其它敌人恒为 1；"
                   "conditionalDamage=true，必须先选定目标敌人类型才能计入伤害乘积。"),
    dict(key="weakDmgRateD", zh="特攻Ｄ倍率", en="Weakness D damage rate", default=1.0,
         group="weakness",
         appliesTo="对「特攻Ｄ」类敌人的额外倍率，对其它敌人恒为 1；"
                   "conditionalDamage=true，必须先选定目标敌人类型才能计入伤害乘积。"),
    dict(key="weakDmgRateE", zh="特攻Ｅ倍率", en="Weakness E damage rate", default=1.0,
         group="weakness",
         appliesTo="对「特攻Ｅ」类敌人的额外倍率，对其它敌人恒为 1；"
                   "conditionalDamage=true，必须先选定目标敌人类型才能计入伤害乘积。"),
    dict(key="weakDmgRateF", zh="特攻Ｆ倍率", en="Weakness F damage rate", default=1.0,
         group="weakness",
         appliesTo="对「特攻Ｆ」类敌人的额外倍率，对其它敌人恒为 1；"
                   "conditionalDamage=true，必须先选定目标敌人类型才能计入伤害乘积。"),
    # --- 致命一击 ------------------------------------------------------------
    dict(key="vitalSpotChangeRate", zh="致命一击伤害倍率", en="Critical (sweet spot) rate", default=1.0,
         group="critical",
         appliesTo="要害／致命一击（背刺、破防处决）的伤害倍率，默认 1＝不改写；只在那一击上成立，"
                   "不能乘进通用伤害排名（conditionalDamage=true）。"
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
    dict(key="bowDistRate", zh="远程伤害衰减减少", en="Bow distance rate", default=0,
         group="economy",
         appliesTo="远程武器（弓／弩）的伤害距离衰减减少量（加算百分比，+50＝衰减起点／幅度大幅放宽）。"
                   "这是字面意义上的增伤——同一发箭在远距离能打出更高伤害——但只在超过衰减距离时兑现，"
                   "因此标了 conditionalDamage=true 而不是 countsAsDamage=true，近战与贴脸射击完全用不到。"),
    dict(key="regainRate", zh="回复量表倍率", en="Regain rate", default=1.0,
         group="economy",
         appliesTo="Regain（受伤后可通过攻击回收血量）倍率。这是生存／续航向的字段，不改变输出，"
                   "只是与其它 economy 字段同属『不直接增伤』一类才放在这一组。"),
]

# key, zh, qualifies (a non-default value alone keeps the SpEffect),
# countsAsDamage (the value may be folded into the *unconditional* damage
# product), conditionalDamage (it really is HP damage, but only after the user
# pins down a condition the data cannot know: the target's weakness type, or
# landing a critical), note
#
# countsAsDamage and conditionalDamage are mutually exclusive by construction:
# a group is either always-on damage, conditionally-on damage, or not damage.
RATE_FIELD_GROUPS: list[dict[str, Any]] = [
    dict(key="damage", zh="最终伤害倍率", qualifies=True, countsAsDamage=True, conditionalDamage=False,
         note="减算防御之后的伤害乘数，可直接相乘。"),
    dict(key="attackPower", zh="攻击力倍率", qualifies=True, countsAsDamage=True, conditionalDamage=False,
         note="减算防御之前的攻击力乘数，与 damage 组分属两层，两层各自相乘后再相乘。"),
    dict(key="attackPowerFlat", zh="攻击力加算", qualifies=True, countsAsDamage=True, conditionalDamage=False,
         note="攻击力点数加算（默认 0），必须先加进攻击力再乘倍率，不能当乘数用。"),
    dict(key="weakness", zh="特攻倍率（需先选定敌人类型）", qualifies=True,
         countsAsDamage=False, conditionalDamage=True,
         note="只对被标记为对应特攻类型（weakA..weakF，例如不死类）的敌人生效，对其它敌人恒为 1。"
              "**countsAsDamage=false**：本版本最大值是『纠死圣律』weakDmgRateB=10（仅对不死类敌人），"
              "无条件乘进通用排名会让它以 ×10 压在榜首，远超真正的通用 buff（最高约 ×1.2）。"
              "页面必须先让用户选定目标敌人（或在『对某类敌人』分区里单独排名）才能把它乘进去。"),
    dict(key="critical", zh="致命一击（需打出致命一击）", qualifies=True,
         countsAsDamage=False, conditionalDamage=True,
         note="致命一击／要害倍率，只在背刺、破防处决那一击上成立，不改变普通命中的伤害，"
              "因此同样不计入通用乘积。本版本参数表无任何非默认值（observedCount=0）。"),
    dict(key="stance", zh="削韧／精力", qualifies=True, countsAsDamage=False, conditionalDamage=False,
         note="削韧（SA）与削精力倍率，影响打出失衡的速度，不改变血量伤害，另算一条轴。"),
    dict(key="status", zh="异常状态累积", qualifies=True, countsAsDamage=False, conditionalDamage=False,
         note="异常状态累积的加算点数与倍率，不改变直接伤害，另算一条轴。"
              "注意 target=\"enemy\" 的条目（例如毒雾、发狂祷告）是直接把累积值加在被命中的敌人身上，"
              "而不是『让玩家的攻击多附带累积』，两者不可混在同一条轴上排名。"),
    dict(key="special", zh="本作特有（各自独立语义，禁止相乘）", qualifies=True,
         countsAsDamage=False, conditionalDamage=False,
         note="currentHealthAttackRate 是随血量换算的加成系数、restageAttackRate 是女爵『再演』复制那一份的伤害占比。"
              "两者都不是对玩家整体伤害的乘数：把 0.4／0.6 乘进伤害乘积会得出 -60%／-40% 的反向结论。"
              "页面只能单独展示（或按各自机制单独建模），绝不可参与乘算或加权汇总。"),
    dict(key="flag", zh="开关（非倍率）", qualifies=False, countsAsDamage=False, conditionalDamage=False,
         note="0/1 开关，标记该 SpEffect 是否套用 AtkParam 侧的修正，单独出现不算增伤。"),
    dict(key="economy", zh="消耗／冷却／量表／射程／Regain（不直接改单次伤害）",
         qualifies=True, countsAsDamage=False, conditionalDamage=False,
         note="专注值消耗、技艺冷却、追加次数、绝招量表、弓射程衰减等。"
              "**qualifies=true**：这些是真实的 DPS 手段（『技艺冷却 -7.5%』『技艺追加 1 次』"
              "『远程伤害衰减减少』），v1 里因为 qualifies=false 而被整条丢弃，页面拿不到任何条目；"
              "现在它们会作为独立条目进入数据集，请单开一个『输出效率』分区，不要并进伤害乘积。"
              "带 lowerIsBetter=true 的字段是数值越低越好；bowDistRate 另带 conditionalDamage=true"
              "（远距离才兑现为伤害）。"),
]
RATE_FIELD_GROUP_BY_KEY = {group["key"]: group for group in RATE_FIELD_GROUPS}

QUALIFY_GROUPS = {g["key"] for g in RATE_FIELD_GROUPS if g["qualifies"]}
COUNTS_AS_DAMAGE_GROUPS = {g["key"] for g in RATE_FIELD_GROUPS if g["countsAsDamage"]}
CONDITIONAL_DAMAGE_GROUPS = {g["key"] for g in RATE_FIELD_GROUPS if g["conditionalDamage"]}
GROUP_LABELS = {g["key"]: g["zh"] for g in RATE_FIELD_GROUPS}

# Groups whose non-default value is a change to HP damage *at all* -- always-on
# plus conditional.  This is only used to decide whether a pure downgrade is
# worth keeping in the dataset; it is deliberately wider than
# COUNTS_AS_DAMAGE_GROUPS so that narrowing countsAsDamage (v1 -> v2) does not
# silently drop rows that used to qualify.
DAMAGE_GROUPS = COUNTS_AS_DAMAGE_GROUPS | CONDITIONAL_DAMAGE_GROUPS

# field-level overrides for conditionalDamage (the group default is used
# otherwise).  bowDistRate literally raises the damage a ranged attack lands
# for, but only past the falloff distance.
CONDITIONAL_DAMAGE_FIELDS = {"bowDistRate"}


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
    _field["countsAsDamage"] = _field["group"] in COUNTS_AS_DAMAGE_GROUPS
    _field["conditionalDamage"] = (_field["key"] in CONDITIONAL_DAMAGE_FIELDS
                                   or _field["group"] in CONDITIONAL_DAMAGE_GROUPS)

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

# SP_EFFECT_TYPE ("状態変化タイプ" -- SpEffectParam.stateInfo), transcribed from
# Smithbox NR/Param Enums/SP_EFFECT_TYPE.json (723 entries; only the values the
# regulation actually uses on a buff in this dataset are kept, the rest would be
# dead weight).  v3 exported stateInfo as a bare number with no labels at all,
# which is how "Enhance Critical Attacks" (367) and "Enhance Thrusting Counter
# Attacks" (197) ended up looking like unconditional x1.24 / x1.20 affixes.
STATE_INFO_TYPE = {
    2: ("中毒", "Poison"),
    5: ("猩红腐败", "Scarlet Rot"),
    6: ("出血", "Blood Loss"),
    28: ("右手武器附加特效", "Right-hand Buff VFX"),
    48: ("提升伤害", "Increase Damage"),
    50: ("HP／FP／精力回复", "HP/FP/Stamina Recovery"),
    60: ("魔力武器附加特效", "Magic Buff VFX"),
    62: ("火焰武器附加特效", "Fire Weapon Buff VFX"),
    64: ("附魔武器特效", "Enchanted Weapon Buff VFX"),
    71: ("法术威力提升", "Spell Power Boost"),
    116: ("死之诅咒", "Death Blight"),
    151: ("雷电武器附加特效", "Lightning Weapon Buff VFX"),
    152: ("允许对敌人施加攻击特效", "Enable Attack Effect against Enemy"),
    158: ("左手武器附加特效", "Left-hand Buff VFX"),
    168: ("弓射程变化", "Bow Distance Change"),
    197: ("强化突刺反击", "Enhance Thrusting Counter Attacks"),
    200: ("内在之力特效", "Power Within VFX"),
    205: ("圣属性武器附加特效", "Holy Weapon Buff VFX"),
    260: ("冻伤", "Frostbite"),
    303: ("累积器 1", "Accumulator 1"),
    305: ("累积器 3", "Accumulator 3"),
    308: ("累积器 6", "Accumulator 6"),
    367: ("强化致命一击", "Enhance Critical Attacks"),
    384: ("斗志加成", "Determination Buff"),
    385: ("斗志加成", "Determination Buff"),
    436: ("睡眠", "Sleep"),
    437: ("发狂", "Madness"),
    443: ("触发冲击波", "Triggers Shockwave"),
    449: ("受伤后攻击回复（反击回血）", "Rally/Post-Damage Attacks Heal"),
    601: ("再演", "Restage"),
    2100: ("使用武器种类触发", "Use Weapon Type Trigger"),
    2103: ("施加攻击时效果", "Apply On-Attack Effect"),
    2108: ("复仇者召唤物 2 生效中", "Revenant Summon 2 Active"),
    2110: ("使用敌人状态触发", "Use Enemy State Info Trigger"),
    2111: ("依当前血量缩放攻击", "Scale attack based on Current HP"),
    2113: ("无赖：延长绝招持续时间", "Raider: Extend Ultimate Art Duration"),
    2121: ("随机施加效果", "Apply Effect Randomly"),
}

# --------------------------------------------------------------------------
# attack contexts -- "this multiplier only applies to attacks made *like this*"
# --------------------------------------------------------------------------
# The game states an attack-situation restriction in two unrelated places:
#
#   magicSubCategoryChange1..3  ATK_SUB_CATEGORY, e.g. 103 Guard Counter Attack
#                               -- exported as scope.subCategories since v1
#   stateInfo                   SP_EFFECT_TYPE, e.g. 367 Enhance Critical
#                               Attacks -- a bare number in stacking.stateInfo
#
# A page cannot be expected to know the second one exists, which is how the six
# "Improved Critical Hits" rows (x1.12..x1.24) and the four "Improved Thrusting
# Counterattack" rows (x1.10..x1.20) came through v3 as passive, unscoped, and
# therefore multiplied into the general DPS ranking.  Note the thrusting-counter
# rows do not even look restricted: their scope is
# {affectsSorcery, affectsIncantation, affectsShaman} = true, which reads as
# "applies to everything including spells".
#
# `scope.attackContexts` folds both routes into one list of stable keys.  Only
# situations the *player* gets into are listed -- a weapon/spell class filter
# ("Melee Weapon Attack", "Ranged Weapon Attack", "Skill Attack", the sorcery
# and incantation schools) is damage composition, not a situation, and stays in
# scope.subCategories where the page already weights it.
#
# key -> (zh, en, from subCategories, from stateInfo)
ATTACK_CONTEXTS: dict[str, tuple[str, str, tuple[int, ...], tuple[int, ...]]] = {
    "criticalHit": ("致命一击／处决", "Critical hit / riposte / backstab", (), (367,)),
    "thrustingCounter": ("突刺反击（被打断攻击后的突刺）", "Thrusting counterattack", (), (197,)),
    "guardCounter": ("防御反击", "Guard counter", (103,), ()),
    "chainFinisher": ("连段最后一击", "Final hit of a chain attack", (104,), ()),
    "jumpAttack": ("跳跃攻击", "Jump attack", (102,), ()),
    "dashAttack": ("冲刺攻击", "Dash attack", (127,), ()),
    "rollingAttack": ("翻滚攻击", "Rolling attack", (128,), ()),
    "backstepAttack": ("后跳攻击", "Backstep attack", (129,), ()),
    "initialAttack": ("起手普通攻击", "Initial standard attack", (119,), ()),
    "horsebackAttack": ("骑马攻击", "Horseback attack", (101,), ()),
    "chargedHeavyAttack": ("蓄力强攻击", "Charged heavy attack", (100,), ()),
    "chargedSpell": ("蓄力法术", "Charged spell", (110,), ()),
    "chargedSkill": ("蓄力战技", "Charged skill", (111,), ()),
    "twoHanded": ("双手持武器时", "While two-handing one armament", (124,), ()),
    "dualWield": ("双持（左右手各一把）时", "While wielding two armaments", (125,), ()),
}
ATTACK_CONTEXT_BY_SUBCATEGORY = {
    value: key for key, (_zh, _en, subs, _st) in ATTACK_CONTEXTS.items() for value in subs
}
ATTACK_CONTEXT_BY_STATE_INFO = {
    value: key for key, (_zh, _en, _subs, states) in ATTACK_CONTEXTS.items() for value in states
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

# Two of the columns below are *timing* columns, not player-facing conditions.
# The ER paramdef (Smithbox ER/Defs/SpEffect.xml) spells motionInterval out as
#   DisplayName 発動間隔[s]   Description 何秒間隔で発生するのかを設定
# i.e. "how many seconds between ticks", the sibling of cycleOccurrenceSpEffectId
# (周期発生特殊効果 / 発動周期毎に発生する特殊効果ID).  isPeriodicEffect is the NR
# bit that says the effect re-applies on that cycle at all (13472 rows, 33 set,
# every one of them a tick/aura row such as "[Weapon] Poison Buildup When Below
# Max HP - Apply Poison").  Neither is a game state the player has to reach.
#
# v3 fed the whole `conditions` dict into the activation classifier, so 210
# buffs were labelled conditional on the strength of a tick interval alone --
# including Bloodboil Aromatic x1.45, Golden Vow x1.15 and Flame Grant Me
# Strength x1.20, i.e. the most ordinary "drink it / cast it and it is on"
# buffs in the game.  They stay in `conditions` (a consumer may well want to
# show the tick rate) but they may not decide `activation`.
TIMING_CONDITION_FIELDS = {"motionInterval", "isPeriodicEffect"}

CONDITION_FIELDS = [
    ("conditionHp", "残余血量低于此比例(%)才发动"),
    ("conditionHpRate", "残余血量高于此比例(%)才发动"),
    ("conditionStamina", "精力条件"),
    ("motionInterval", "效果重新施加的间隔（秒）——ER paramdef『発動間隔[s]／何秒間隔で発生するのかを設定』，"
                       "是计时机制不是发动条件，**不参与 activation 判定**"),
    ("isPeriodicEffect", "该效果按上面的间隔周期性重新施加——同样是计时机制不是发动条件，"
                         "**不参与 activation 判定**"),
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

# --------------------------------------------------------------------------
# who the SpEffect actually lands on
# --------------------------------------------------------------------------
# Being reachable from a player item does NOT mean the effect sits on the
# player.  Bullet.spEffectId0..4 are the *hit target* slots, so a thrown pot's
# poison and a debuff aura land on whoever the bullet hits; the Revenant's
# family are separate characters with their own stat-scaling rows.  v1 treated
# all of those as player buffs, which put "[Item - Level 3] Bewitching Branch
# (Attack Boost on Charmed)" (x2.0 on a charmed *enemy*) at the top of the
# damage ranking and read "[Skill - Revenant] Sebastian - Damage/Defense
# Change" (x0.15 on the summon) as "the player deals 15% damage".
# NOTE the `(?:->|$)` tail instead of a bare `$` anchor.  A via string does not
# always *end* at the hit slot: when the payload is reached through one more
# chain field the route reads
#   "refId1->Bullet10631000.spEffectId0->cycleOccurrenceSpEffectId"
# (『授血』 1631001 = Bloodboon's bloodflame tick).  Anchored at `$` that route
# did not match, so a blood-loss buildup that is stacked on the *enemy* standing
# in the flame fell through to target="self" -- i.e. onto the exact axis whose
# group note forbids mixing the two.  Matching the slot wherever it appears in
# the chain fixes it; the capture group carries the Bullet id.
BULLET_HIT_VIA_RE = re.compile(r"Bullet(\d+)\.spEffectId[0-4](?:->|$)")
BULLET_SHOOTER_VIA_RE = re.compile(r"Bullet\d+\.spEffectIDForShooter(?:->|$)")

# The *other* hit slot.  SpEffectParam.atkOccurrenceSpEffectId is "攻撃命中時に
# 発生する特殊効果" -- the payload handed to whatever the attack connected with.
# v3 only recognised the Bullet hit slots, so the 25 grease / armament rows that
# reach their payload through refId_default->atkOccurrenceSpEffectId
# (3176 Poison Grease, 3151 Soporific Grease, 1723001 Poison Armament, ...) fell
# through to target="self" while the structurally identical bullet-delivered
# versions (1722000 Poison Mist, 1631001 Bloodboon) were target="enemy".  Same
# faction bits, same spCategory, same cycleOccurrenceSpEffectId, opposite label.
ATTACK_HIT_VIA_RE = re.compile(r"atkOccurrenceSpEffectId(?:->|$)")

# Revenant family (Helen / Frederick / Sebastian) stat scaling: these rows are
# applied to the summons, not to the player.
SUMMON_ROW_RE = re.compile(
    r"^\[Skill - Revenant\].*(Spirit Stat Change|Helen|Frederick|Sebastian)")

# Paramdex row names that state outright that the effect is handed to teammates.
# "family" alone is deliberately excluded: "[Relic - Revenant] Power up while
# fighting alongside family" buffs the *player* while the family is out.
ALLIES_ROW_RE = re.compile(r"\ballies\b|\ballied\b", re.IGNORECASE)

# AtkParam correction columns.  A bullet whose AtkParam zeroes every damage
# correction cannot hurt anything -- it is a support/aura bullet (Golden Vow,
# the aromatics), so its spEffectId0..4 payload goes to the caster's own side.
# An offensive projectile (Kukri, Glintstone Icecrag, Bewitching Branch) keeps
# them at 100 and its payload goes to the enemy it hits.
ATK_CORRECTION_FIELDS = [
    "atkPhysCorrection", "atkMagCorrection", "atkFireCorrection",
    "atkThunCorrection", "atkDarkCorrection",
]

TARGET_LABELS = {
    "self": ("只作用于玩家自己", "Player only"),
    "ally": ("作用于自己与／或附近队友（友方 AoE、团队增益）", "Player and/or nearby allies"),
    "summon": ("作用在召唤物／复仇者家人自己身上，不是玩家的倍率", "The summon's own stats, not the player's"),
    "enemy": ("挂在被命中的敌人身上（减益，或魅惑后敌人自己的增伤）", "Applied to the enemy that was hit"),
}
TARGET_SOURCE_LABELS = {
    "default": "没有命中目标槽位的证据，按『挂在玩家自己身上』处理（遗物词条／护符／武器被动／永久强化等）",
    "revenantFamilyRow": "Paramdex 行名表明这是复仇者家人（召唤物）自身的数值缩放行",
    "alliesRow": "Paramdex 行名明示效果发给 allies（队友）",
    "bulletHitOpposeOnly":
        "**前提是**这条 SpEffect 的全部来源都只能由 Bullet 的命中槽（spEffectId0..4）投递；"
        "在这个前提下，再用阵营过滤位 effectTargetSelfTarget=0／effectTargetOpposeTarget=1 "
        "区分它投给敌方还是己方，判定为敌方。"
        "⚠️ 这两个位**单独出现不足以判定 target**：它们的语义是『这份异常累积／效果允许打给哪个阵营』，"
        "不是『这条 SpEffect 挂在谁身上』，必须先确认投递路径确实是命中槽"
        "（Bullet.spEffectId0..4 或 atkOccurrenceSpEffectId）。"
        "本版本仍有一批条目带着 oppose-only 的阵营位、却只能靠 Paramdex 行名或武器行为槽追溯来源，"
        "投递路径无法确认，一律保守地按 self 处理——清单见 diagnostics.opposeBitsWithoutHitSlot，"
        "那是缺省而不是已证实的结论。"
        "（v3 这里原本举 3176『[Item] Poison Grease (Right) - Poison』为『阵营位 oppose-only 却挂在玩家身上』"
        "的反例，说它『来源是 EquipParamGoods，根本没走命中槽』。那句是错的："
        "3176 的 via 正是 refId_default->atkOccurrenceSpEffectId，走的就是命中槽，"
        "v4 已按同一规则把它改判为 target=\"enemy\"。）",
    "bulletHitFriendlyOnly":
        "**前提同上**（全部来源都只能由 Bullet 的命中槽投递）；在这个前提下 effectTargetOpposeTarget=0 "
        "说明这份效果只允许打给己方阵营，判定为 ally。"
        "同样地，effectTargetOpposeTarget=0 单独出现不足以判定 target，必须先满足『只由命中槽投递』的前提。",
    "attackHitOpposeOnly":
        "全部来源都经由 atkOccurrenceSpEffectId（『攻击命中时发动』）投递——"
        "也就是说这份效果是在玩家打中目标的那一刻挂到**被打中的对象**身上的，不是挂在玩家身上；"
        "阵营过滤位 effectTargetSelfTarget=0／effectTargetOpposeTarget=1 进一步确认只能打给敌方。"
        "各种油脂（毒／催眠／出血／腐败）与『附加毒属性』祷告的累积行都属于这一类，"
        "与弹道投递的同类（1722000『毒雾』、1631001『授血』）判定一致。"
        "⚠️ 这些条目虽然 target=enemy，但**确实是玩家的异常累积手段**：要做『异常累积』榜时不能只留 self，"
        "应当按 sources[].kind 取玩家可获得的来源，见 notes.target。",
    "attackHitSelfOnly":
        "全部来源都经由 atkOccurrenceSpEffectId 投递，但阵营位允许打给自己"
        "（effectTargetSelfTarget=1 且 effectTargetOpposeTarget=0，或两侧都开而负载不只是异常累积）——"
        "这是『命中后给自己上 buff』的形态，效果挂在玩家身上"
        "（例：7036901『打出连段最后一击后提升攻击力』×1.16、"
        "8660203『致命一击附带出血』的攻击力加算）。发动条件由 activation 另行标记。",
    "attackHitStatusPayload":
        "全部来源都经由 atkOccurrenceSpEffectId 投递，阵营过滤两侧都开，而负载只有异常累积／开关"
        "（没有任何倍率或攻击力加算）——这种行是『打中谁就给谁累积』，视为挂在被命中的敌人身上"
        "（例：3141『[Item] Freezing Grease (Right) - Frostbite』、"
        "1449001『[Sorcery] Frozen Armament - Frost』、1632002『血炎武器 - 出血』）。",
    "bulletHitSupportBullet": "只能由 Bullet 的命中槽投递，阵营过滤两侧都开，但该 Bullet 的 AtkParam 伤害修正全为 0（纯辅助弹道，只会罩到己方）",
    "bulletHitStatusMist": "只能由 Bullet 的命中槽投递，阵营过滤两侧都开，弹道本身不造成伤害，且效果只有异常状态累积（站在雾里的人吃累积，视为敌人侧）",
    "bulletHitOffensiveBullet": "只能由 Bullet 的命中槽投递，阵营过滤两侧都开，但该 Bullet 的 AtkParam 是会造成伤害的攻击弹道（命中的是敌人）",
}

# --------------------------------------------------------------------------
# does the buff need something to happen before it applies?
# --------------------------------------------------------------------------
# `conditions` / `triggered` only cover the conditions that are *spelled out in
# SpEffectParam columns* (conditionHp, wepTypeTrigger, invocationConditions...).
# The biggest multipliers in the table are gated by things the param row cannot
# express, because an event script switches them on:
#   704301  "[Passive - Raider] Attack Boost when below 25% Health"  x1.50
#   8300000 "[Weapon] Improved Attack Power when Two-Handing"        x1.12..1.18
#   8310000 "[Weapon] Attack Up when Wielding Two Armaments"         x1.12..1.18
#   707215  "[Ultimate - Executor] Beast Attack Boost - Level 15"    x3.55
# all had conditions=null AND triggered=null, so "filter by conditions" -- the
# step notes.ranking asked the page to perform -- was a no-op on exactly the
# rows that need it most.  `activation` is the machine-readable answer.
#
#   passive      no activation condition: equip the relic / drink the item and
#                the multiplier is on.  Only these may be multiplied by default.
#   conditional  the multiplier exists but a game state must hold (low HP,
#                two-handing, a stack count, an on-hit trigger).  The user has
#                to tick it.
#   activated    the multiplier only exists while a skill / ultimate art / ash
#                of war is running.  The user has to tick it, and it is usually
#                a burst window rather than a sustained rate.
ACTIVATION_ORDER = {"passive": 0, "conditional": 1, "activated": 2}

# Paramdex "[...]" categories that are an art the player has to fire off.
# "Passive - X" is deliberately NOT here: a hero passive can be genuinely
# always-on, and the Raider's is gated on HP (caught by the row-name rule
# below), so lumping it in with the Ultimate Arts would be wrong in both
# directions.
ACTIVATED_ROW_CATEGORY_RE = re.compile(r"^(Ultimate|Skill|AoW)\b")

# Row-name words that state an activation condition.  Deliberately excludes the
# words that describe *scope* rather than a condition -- "Improved Guard
# Counters", "Improved Critical Hits", "Improved Charged Sorceries", "Improved
# Chain Attack Finishers" are ordinary always-on affixes whose rates are gated
# by scope.subCategories (ranking step ④), not by a state the user must reach.
CONDITION_ROW_NAME_RE = re.compile(
    r"\b(while|whenever|when|upon|during|below|above|alongside|two-hand|wielding|stack)",
    re.IGNORECASE)

# "[Passive - X]" rows that carry a *finite* duration.  A hero passive that is
# genuinely always on has effectEndurance = -1; one that lasts 18.5 s must have
# been switched on by something (the Executor's Tenacity fires on a successful
# deflect).  v3 caught 707070/707071 only through motionInterval=0.06, i.e. by
# accident, and lost them the moment the timing columns stopped counting.
PASSIVE_ROW_CATEGORY_RE = re.compile(r"^Passive\b")

# Localisation fallback.  Rules ① and ② read the English Paramdex row name, so
# they are blind on the rows that have none -- and two of those spell their
# condition out in the Chinese state-bar text instead:
#   7069001 "每次打倒封印监牢里的囚犯，能提升攻击力"  x1.05
#   7069201 "每次打倒黑夜入侵者，能提升攻击力"        x1.07
# The vocabulary is deliberately tiny (repeat-an-event wording only) and the
# rule is deliberately restricted to paramName-less rows: the v3 decision to
# keep counter / critical / charged / chain *out* of the condition vocabulary
# must not be undone through the Chinese side, where 『强化连续攻击的最后攻击』
# and 『降低射击时，伤害随距离递减的影响』 would otherwise match.
LOCALIZED_CONDITION_RE = re.compile(r"每次|每当|打倒|击倒|成功时|命中时")

ACTIVATION_LABELS = {
    "passive": ("装备／饮用后即生效，没有额外的发动条件，可默认计入乘积",
                "Always on once the source is equipped or used"),
    "conditional": ("需要满足某个游戏状态才成立（残血、双手持、叠层、命中触发等），"
                    "必须由用户勾选，默认不计入乘积",
                    "Requires a game state; must be opted in"),
    "activated": ("只在技艺／绝招／战技发动期间存在，必须由用户勾选，默认不计入乘积",
                  "Only while a skill / ultimate art / ash of war is running"),
}
ACTIVATION_SOURCE_LABELS = {
    "noEvidence": "没有任何发动条件的证据：来源行名不含条件词、非计时类 conditions 为空、triggered 为假，"
                  "且不是技艺／绝招／战技行、不是带时限的角色被动、不是叠层阶梯第 1 层。"
                  "注意 passive 的含义是『没有额外的发动条件』，"
                  "不等于『不用付出代价』——消耗品仍要先喝、遗物词条仍要先装备，那是 sources 的事；"
                  "也**不等于『对所有攻击都生效』**——作用范围是另一条轴，"
                  "先看 scope.attackContexts（致命一击、防御反击、蓄力…）再决定能不能计入通用排名。",
    "paramRowCategoryArt": "Paramdex 行名的 [...] 前缀是 Ultimate／Skill／AoW，"
                           "即这条 SpEffect 只在绝招／角色技艺／战技发动期间挂在身上"
                           "（例：707215『[Ultimate - Executor] Beast Attack Boost - Level 15』×3.55 "
                           "只存在于处刑人绝招兽化期间）。",
    "paramRowNameCondition": "Paramdex 行名里写明了发动条件（while／when／upon／during／below／above／"
                             "alongside／two-handing／wielding／stack）"
                             "（例：704301『Attack Boost when below 25% Health』×1.5、"
                             "8300000『Improved Attack Power when Two-Handing』、"
                             "8310000『Attack Up when Wielding Two Armaments』——"
                             "后两者还彼此互斥，不能同时计入）。"
                             "刻意不含 counter／critical／charged／chain 这类词：那是作用范围（scope.subCategories）"
                             "而不是发动条件，「强化防御反击」是常驻词条。",
    "paramRowPassiveTimed": "Paramdex 行名的 [...] 前缀是 Passive（角色被动），但 effectEndurance 是有限值——"
                            "真正常驻的被动是 -1，带时限就说明它是被某个时机打开的"
                            "（例：707071『[Passive - Executor] Tenacity』×1.2 持续 18.5 秒，"
                            "是处刑人挡拆成功后的窗口；707070 是它的 1.5 秒起手段）。",
    "localizedNameCondition": "该行没有 Paramdex 英文行名（规则①②天然失效），但简中／英文状态栏文本里写明了"
                              "需要反复达成的条件（每次／每当／打倒／击倒／成功时／命中时）"
                              "（例：7069001『每次打倒封印监牢里的囚犯，能提升攻击力』、"
                              "7069201『每次打倒黑夜入侵者，能提升攻击力』）。"
                              "刻意只在 paramName 为空时启用、且词表只收『重复达成某事』这一类措辞——"
                              "否则『强化连续攻击的最后攻击』『降低射击时，伤害随距离递减的影响』"
                              "这类**作用范围**描述会被误判成发动条件。",
    "stackLadderTier1": "这条 buff 是一段叠层阶梯的第 1 层（见 buffs[].stackLadder）："
                        "参数表里紧随其后是一串行名为空、除倍率外所有列完全相同、倍率逐层严格递增、"
                        "且 saveCategory≠-1（占用存档槽＝随游戏进程累积）的行。"
                        "层数要靠反复达成某个条件才涨，所以第 1 层的数值既不是无条件的、也不是该词条的上限"
                        "（例：8988200『玛雷家的庇佑』第 1 层 ×1.011，满 100 层 ×1.70）。",
    "conditionFields": "SpEffectParam 自带的条件列非默认（见 buffs[].conditions 与 conditionFields）。"
                       "**只算 conditionFields[].isActivationCondition=true 的那些列**——"
                       "motionInterval（发动间隔［秒］）与 isPeriodicEffect（周期性重新施加）是计时机制，"
                       "不是玩家要满足的状态；v3 把它们算进来，导致 210 条无条件 buff"
                       "（狂热香药 ×1.45、黄金树立誓 ×1.15…）被误判成 conditional。",
    "onHitTrigger": "来源是 AttachEffectParam.onHitSpEffect（命中时才挂上），同 buffs[].triggered。",
    "eventScriptTimedBuff": "这条 SpEffect 没有任何参数列指向它（全部来源都是 inferred=true，由游戏脚本挂载），"
                            "且持续时间有限（effectEndurance ≠ -1）——脚本必然是在某个时刻才把它打开的，"
                            "只是那个时刻写在 ESD／EMEVD 里、参数表看不到"
                            "（例：8980002『Power of Night and Flame: Magic Damage Buff』30 秒、"
                            "7035703『Switching Weapons Adds an Affinity Attack』10 秒）。",
}

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
   countsAsDamage=true 的组（damage／attackPower／attackPowerFlat）才是无条件的血量伤害；
   conditionalDamage=true 的（weakness 特攻、critical 致命一击、economy 里的 bowDistRate）要先满足条件才成立，
   不得无条件乘进通用排名（『纠死圣律』weakDmgRateB=10 只对不死类敌人生效）；
   两者都为 false 的组（stance 削韧、status 异常累积、special、flag、其余 economy）都不进伤害乘积，只能单独展示。

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


def param_stem(name: str) -> str:
    """The Paramdex row name without its per-step suffix.

    "[Relic] Starting armament deals magic damage - Damage Adjustment - Potency 1"
    and "[Relic] Starting armament deals magic damage - Apply State Info" share
    the stem "Starting armament deals magic damage", so they really are two
    rows of one affix.  "[Weapon] Improved Sorceries and Incantations - Potency 2"
    and "[Weapon] Improved Incantations - Potency 1" do NOT (their stems differ),
    which is exactly the pair v1 confused.  The "[...]" prefix is stripped first
    so that "[Relic - Duchess] ..." is not split on its own dash.
    """
    return clean_param_name(name).split(" - ")[0].strip().casefold()


ROW_CATEGORY_RE = re.compile(r"^\[([^\]]+)\]")


def row_category(name: str | None) -> str:
    """The "[...]" prefix of a Paramdex row name ("Relic - Duchess", "AoW")."""
    match = ROW_CATEGORY_RE.match((name or "").strip())
    return match.group(1).strip() if match else ""


# "[...]" prefix -> a short zh/en word usable as a display-name qualifier.
# Longest prefix wins, so "Weapon Power" beats "Weapon" and "Relic - Duchess"
# is matched by "Relic".
ROW_CATEGORY_LABELS: list[tuple[str, tuple[str, str]]] = [
    ("Weapon Power", ("武器固有", "Weapon Power")),
    ("Weapon", ("武器", "Weapon")),
    ("Relic", ("遗物", "Relic")),
    ("Talisman", ("护符", "Talisman")),
    ("Magic Cocktail", ("调合", "Cocktail")),
    ("Item", ("道具", "Item")),
    ("AoW", ("战技", "AoW")),
    ("Incantation", ("祷告", "Incantation")),
    ("Sorcery", ("魔法", "Sorcery")),
    ("Ultimate", ("绝招", "Ultimate")),
    ("Skill", ("技艺", "Skill")),
    ("Passive", ("被动", "Passive")),
    ("Arrow", ("箭矢", "Arrow")),
    ("Bow", ("弓", "Bow")),
    ("Serpent Bow", ("弓", "Bow")),
    ("Flail", ("连枷", "Flail")),
    ("Interactable Effect", ("场景互动", "Interactable")),
    ("Libra Deal", ("天秤契约", "Libra Deal")),
]


def row_category_label(name: str | None, is_zh: bool) -> str | None:
    category = row_category(name)
    if not category:
        return None
    best: tuple[str, str] | None = None
    best_len = 0
    for prefix, labels in ROW_CATEGORY_LABELS:
        if (category == prefix or category.startswith(prefix + " ")) and len(prefix) > best_len:
            best, best_len = labels, len(prefix)
    if best is None:
        return None
    return best[0] if is_zh else best[1]


# Scope columns that must agree before one SpEffect may borrow another's name.
NAME_BORROW_SCOPE_FIELDS = (
    "wepParamChange", "magParamChange", "miracleParamChange",
    "shamanParamChange", "throwAttackParamChange",
    "atkAttribute", "spAttribute",
    "magicSubCategoryChange1", "magicSubCategoryChange2", "magicSubCategoryChange3",
)


def same_scope(a: dict[str, str], b: dict[str, str]) -> bool:
    return all(a.get(f) == b.get(f) for f in NAME_BORROW_SCOPE_FIELDS)


# Per-step markers used to tell otherwise identically named buffs apart.
POTENCY_RE = re.compile(r"\b(?:Potency|Level|Lv|Stack|Step|Tier|Phase)\s*(\d+)", re.IGNORECASE)
# a display name that had to fall back to "#<spEffectId>" as its last qualifier
DISPLAY_ID_TAIL_RE = re.compile(r"#\d+[）)]$")
PERCENT_RE = re.compile(r"\(([+-]?\d+(?:\.\d+)?)\s*%\)")
SIDE_RE = re.compile(r"\b(Right|Left)\b")


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
    atk_pc = index_param(read_param("AtkParam_Pc"))
    permanents = read_param("PermanentBuffParam")

    def bullet_is_support(bullet_id: str) -> bool | None:
        """True when the bullet cannot damage anything (a buff/aura bullet).

        Unknown (None) when the Bullet or its AtkParam row is missing.
        """
        bullet = bullets.get(bullet_id)
        if bullet is None:
            return None
        atk = atk_pc.get((bullet.get("atkId_Bullet") or "").strip())
        if atk is None:
            return None
        try:
            return all(float(atk[f]) == 0.0 for f in ATK_CORRECTION_FIELDS)
        except (KeyError, ValueError):
            return None

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
    # rows in a source table that were skipped because the FMG has no name for
    # them at all (unused/placeholder rows).  Recorded so that a future
    # regulation adding those names shows up as a diff instead of silently
    # changing the buff count.
    skipped_unnamed: dict[str, list[str]] = defaultdict(list)
    skipped_unnamed_targets: dict[str, set[str]] = defaultdict(set)

    def note_skipped(table: str, row_id: str, targets: list[str]) -> None:
        skipped_unnamed[table].append(row_id)
        for target in targets:
            skipped_unnamed_targets[table].add(target)

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
        own_row = sp.get(sp_id) or {}
        own_stem = param_stem(own_row.get("Name", ""))
        for base in (value - value % 10, value - value % 100):
            if base == value:
                continue
            attach_row = attach.get(str(base))
            if attach_row is None:
                continue
            # Guard: the decade/century neighbour must be the SAME affix, not
            # merely a numeric neighbour.  8330104 "[Weapon] Improved Sorceries
            # and Incantations - Potency 2" used to borrow the name of
            # 8330100 "[Weapon] Improved Incantations - Potency 1", which turned
            # a sorcery+incantation buff into 「强化祷告」 and produced two
            # different 1.11 entries both called 「强化祷告」.
            sibling_sp = sp.get(str(base))
            if own_stem:
                sibling_stem = param_stem(
                    (sibling_sp or {}).get("Name") or attach_row.get("Name", ""))
                if sibling_stem and sibling_stem != own_stem:
                    continue
            sibling_zh, sibling_en = attach_names(attach_row)
            if sibling_zh:
                return sibling_zh, sibling_en
        return None, None

    def origin_labels(src_list: list[dict[str, Any]], is_zh: bool,
                      param_name: str | None) -> tuple[str | None, str | None]:
        """(localized origin, raw origin).

        The *localized* origin is a real FMG item / affix name in the language
        being built.  The *raw* origin is the community Paramdex row name (or an
        English source name while building the Chinese list) -- always English,
        often a mouthful, and it is what produced
        「强化魔法、祷告（Improved Sorceries and Incantations (+11%)）」 next to its
        own sibling 「强化魔法、祷告（档位1・×1.07）」.  Splitting them lets the
        localized one stay first (it is the most informative qualifier there is)
        while the raw one drops behind the potency / side / category / rate
        tokens, so a family is only spelled out in English when nothing else can
        tell its members apart.
        """
        def pick(keys: tuple[str, ...]) -> str | None:
            for entry in src_list:
                value = next((entry[key] for key in keys if entry.get(key)), None)
                if value:
                    return value
            return None

        raw_name = clean_param_name(param_name or "") or None
        if is_zh:
            return pick(("nameZh", "effectNameZh")), (pick(("nameEn", "effectNameEn"))
                                                      or raw_name)
        return pick(("nameEn", "effectNameEn")), raw_name

    def display_head(base: str, src_list: list[dict[str, Any]], is_zh: bool,
                     param_name: str | None) -> tuple[str, str | None, str | None]:
        """(head, localized origin qualifier, raw origin qualifier).

        nameZh is the status-bar text, which repeats a lot (92 buffs are called
        "提升攻击力"), so it is useless on its own in a list.
        """
        localized, raw = origin_labels(src_list, is_zh, param_name)
        head = base

        def usable(origin: str | None) -> str | None:
            if not origin or origin == head or origin in head:
                return None
            return origin

        localized = usable(localized)
        if localized and head in localized:
            # the source name is the same statement, spelled out
            # ("提升攻击力" vs "装备三把以上类别为短剑的武器，能提升攻击力")
            head, localized = localized, None
        return head, localized, usable(raw)

    def step_token(param_name: str | None, is_zh: bool) -> str | None:
        match = PERCENT_RE.search(param_name or "")
        if match:
            return f"{match.group(1)}%"
        match = POTENCY_RE.search(param_name or "")
        if match:
            return f"档位{match.group(1)}" if is_zh else f"Lv{match.group(1)}"
        return None

    def side_token(scope: dict[str, Any], param_name: str | None,
                   is_zh: bool) -> str | None:
        slot = scope.get("weaponSlot")
        if slot in (1, 2):
            labels = WEP_CHANGE_PARAM[slot]
            return labels[0] if is_zh else labels[1]
        match = SIDE_RE.search(param_name or "")
        if match:
            side = match.group(1)
            return ("右手" if side == "Right" else "左手") if is_zh else side
        return None

    def rate_token(rates: dict[str, Any], is_zh: bool) -> str | None:
        if not rates:
            return None
        key = next(iter(rates))
        field = RATE_FIELD_BY_KEY[key]
        value = rates[key]
        if field["valueKind"] == "multiplier":
            return f"×{value}"
        label = field["zh"] if is_zh else field["en"]
        return f"{label}{value:+g}" if isinstance(value, (int, float)) else f"{label}{value}"

    def assemble(head: str, quals: list[str], is_zh: bool) -> str:
        if not quals:
            return head
        inner = "・".join(quals) if is_zh else ", ".join(quals)
        return f"{head}（{inner}）" if is_zh else f"{head} ({inner})"

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
            note_skipped("EquipParamAccessory", acc_id,
                         [t for t in (ref(row.get(f)) for f in
                                      ("spEffectId_1", "spEffectId_2", "spEffectId_3")) if t])
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
            note_skipped("EquipParamGoods", goods_id,
                         [t for t in (ref(row.get(f)) for f in
                                      goods_fields + ["carrySpEffectId", "emptySpEffectId"]) if t])
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
            note_skipped("EquipParamWeapon", str(weapon_id),
                         [t for t in (ref(row.get(f)) for f in weapon_fields) if t])
            continue
        for field in weapon_fields:
            target = ref(row.get(field))
            if not target:
                continue
            seeds.add(target)
            add_source(target, "weaponPassive", str(base_id), name_zh, name_en, field)

    # (e) spells -- Magic (direct SpEffect, or through a Bullet)
    #
    # A handful of Magic rows carry a *relic* effect in one of their refId
    # slots: Magic.refId10 = 7037001 on all 30 assist incantations is the hook
    # for the Undertaker relic "[Relic - Undertaker] Physical attacks boosted
    # while assist effect from incantation is active for self", and the SpEffect
    # only fires when the player actually has that affix equipped
    # (invocationConditionsStateChange1 = 2065).  Writing 30 kind="spell"
    # sources for it made the page claim every assist incantation grants +19%,
    # and made its displayNameZh 「提升物理攻击力（火焰啊，赐予我力量！）」 -- the
    # same label as the real 1605000『火焰啊，赐予我力量！』.  Those mounts are
    # collected here and emitted as ONE relicAffix source instead.
    relic_mounts: dict[str, list[tuple[str, str]]] = defaultdict(list)

    for row in magics:
        magic_id = row["ID"]
        name_zh = zh["magic"].get(magic_id)
        name_en = en["magic"].get(magic_id) or clean_param_name(row.get("Name", "")) or None
        if not (name_zh or name_en):
            note_skipped("Magic", magic_id,
                         [t for t in (ref(row.get(f"refId{i}")) for i in range(1, 11)) if t])
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
                target_row = sp.get(target)
                if (target_row or {}).get("Name", "").startswith("[Relic"):
                    relic_mounts[target].append((magic_id, via))
                    continue
                add_source(target, "spell", magic_id, name_zh, name_en, via)

    for target, mounts in relic_mounts.items():
        target_row = sp.get(target) or {}
        value = int(target)
        affix_id: str | None = None
        affix_zh = affix_en = None
        for base in (value - value % 10, value - value % 100):
            attach_row = attach.get(str(base))
            if attach_row is None:
                continue
            affix_id = str(base)
            affix_zh, affix_en = attach_names(attach_row)
            break
        slots = sorted({via for _magic_id, via in mounts})
        add_source(
            target, "relicAffix", affix_id, affix_zh,
            affix_en or clean_param_name(target_row.get("Name", "")) or None,
            f"Magic.{'/'.join(slots)}",
            extra={
                "relicMount": True,
                "mountedOnSpellCount": len({magic_id for magic_id, _via in mounts}),
                "mountedOnSpellIds": sorted({int(magic_id) for magic_id, _via in mounts})[:40],
            },
        )

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

    # --- who does the effect land on? -------------------------------------
    def classify_target(sp_id: str, row: dict[str, str],
                        all_sources: list[dict[str, Any]],
                        rate_groups: set[str]) -> tuple[str, str]:
        name = row.get("Name") or ""
        if SUMMON_ROW_RE.match(name):
            return "summon", "revenantFamilyRow"
        vias = [entry["via"] for entry in all_sources]
        if vias and all(BULLET_HIT_VIA_RE.search(via) for via in vias):
            # every route to this SpEffect is a bullet's *hit target* slot, so
            # it lands on whoever the bullet hit, never on the caster.
            self_side = row.get("effectTargetSelfTarget") == "1"
            oppose_side = row.get("effectTargetOpposeTarget") == "1"
            if oppose_side and not self_side:
                return "enemy", "bulletHitOpposeOnly"
            if self_side and not oppose_side:
                return "ally", "bulletHitFriendlyOnly"
            # both faction filters open -- fall back to what the bullet is:
            # a damaging projectile hits enemies, a zero-damage aura bullet
            # (Golden Vow, the aromatics) only ever covers your own side.
            bullet_ids = {BULLET_HIT_VIA_RE.search(via).group(1) for via in vias}
            support = {bullet_is_support(bullet_id) for bullet_id in bullet_ids}
            if support == {True} and rate_groups - {"status", "flag"}:
                return "ally", "bulletHitSupportBullet"
            if support == {True}:
                # a zero-damage bullet whose whole payload is ailment buildup is
                # a mist/cloud that stacks the ailment on whoever stands in it
                # (Freezing Mist), not a party buff.
                return "enemy", "bulletHitStatusMist"
            return "enemy", "bulletHitOffensiveBullet"
        if vias and all(ATTACK_HIT_VIA_RE.search(via) for via in vias):
            # every route is "applied when the attack connects".  Same three
            # questions as the bullet branch, minus the bullet: the faction
            # bits first, and when both are open, what the payload is.
            self_side = row.get("effectTargetSelfTarget") == "1"
            oppose_side = row.get("effectTargetOpposeTarget") == "1"
            if oppose_side and not self_side:
                return "enemy", "attackHitOpposeOnly"
            if self_side and not oppose_side:
                return "self", "attackHitSelfOnly"
            if not rate_groups - {"status", "flag"}:
                # nothing but ailment buildup -- it is what the weapon puts on
                # the thing it hit (greases, Frozen Armament, Bloodflame Blade)
                return "enemy", "attackHitStatusPayload"
            return "self", "attackHitSelfOnly"
        if ALLIES_ROW_RE.search(name):
            return "ally", "alliesRow"
        return "self", "default"

    # --- does something have to happen first? -----------------------------
    def classify_activation(row: dict[str, str], all_sources: list[dict[str, Any]],
                            conditions: dict[str, Any], has_trigger: bool,
                            duration: float, localized: str,
                            stack_ladder: dict[str, Any] | None) -> tuple[str, str]:
        """(activation, activationSource) -- entirely data driven, no id lists.

        Checked strongest-first so the label is never weaker than the evidence:
        an art window beats a state condition beats "no evidence".
        """
        name = row.get("Name") or ""
        if ACTIVATED_ROW_CATEGORY_RE.match(row_category(name)):
            return "activated", "paramRowCategoryArt"
        if CONDITION_ROW_NAME_RE.search(clean_param_name(name)):
            return "conditional", "paramRowNameCondition"
        if PASSIVE_ROW_CATEGORY_RE.match(row_category(name)) and duration != -1.0:
            return "conditional", "paramRowPassiveTimed"
        if not name.strip() and LOCALIZED_CONDITION_RE.search(localized):
            # only where rules (1) and (2) have nothing to read
            return "conditional", "localizedNameCondition"
        # `conditions` carries two timing columns that are not player-facing
        # states; see TIMING_CONDITION_FIELDS.
        if any(key not in TIMING_CONDITION_FIELDS for key in conditions):
            return "conditional", "conditionFields"
        if has_trigger:
            return "conditional", "onHitTrigger"
        if stack_ladder:
            return "conditional", "stackLadderTier1"
        if all_sources and all(s.get("inferred") for s in all_sources) and duration != -1.0:
            return "conditional", "eventScriptTimedBuff"
        return "passive", "noEvidence"

    # --- is this row tier 1 of an accumulating stack? ---------------------
    # 7069001 "每次打倒封印监牢里的囚犯，能提升攻击力" ships as x1.05, but the CSV
    # continues 7069002..7069010 up to x1.6289 with empty row names: the affix
    # is a ladder the player climbs, and only the first rung is reachable from a
    # param column.  Detection is structural, no id list:
    #   * consecutive ids, row name empty, not themselves a shipped buff
    #   * every non-rate column identical to tier 1 (stacking, scope, duration)
    #   * exactly the same set of non-default rate keys
    #   * at least one multiplier, and every multiplier strictly increasing
    #   * saveCategory != -1  -- the buff occupies a save slot, i.e. the tier is
    #     remembered across the run.  This is what separates a real ladder from
    #     "[Relic] Improved Throwing Pot Damage +1/+2", three separately
    #     equippable affix grades that all sit at saveCategory = -1.
    LADDER_SAME_COLUMNS = (
        "spCategory", "categoryPriority", "saveCategory", "stateInfo",
        "effectEndurance", "wepParamChange", "magParamChange", "miracleParamChange",
        "shamanParamChange", "throwAttackParamChange", "atkAttribute", "spAttribute",
        "magicSubCategoryChange1", "magicSubCategoryChange2", "magicSubCategoryChange3",
    )
    LADDER_MAX_TIERS = 256

    def detect_stack_ladder(sp_id: str, row: dict[str, str],
                            rates: dict[str, Any],
                            shipped: set[str]) -> dict[str, Any] | None:
        if row.get("saveCategory", "-1") == "-1":
            return None
        multipliers = [key for key in rates
                       if RATE_FIELD_BY_KEY[key]["valueKind"] == "multiplier"]
        if not multipliers:
            return None
        base_keys = set(rates)
        tiers: list[str] = []
        previous = row
        step = 1
        while step <= LADDER_MAX_TIERS:
            nxt_id = str(int(sp_id) + step)
            nxt = sp.get(nxt_id)
            if nxt is None or nxt.get("Name", "").strip() or nxt_id in shipped:
                break
            if any(nxt[column] != row[column] for column in LADDER_SAME_COLUMNS):
                break
            nxt_rates = {key: as_number(nxt[key]) for key in RATE_FIELD_BY_KEY
                         if key in nxt and not is_default(nxt, key)}
            if set(nxt_rates) != base_keys:
                break
            if not all(float(nxt[key]) > float(previous[key]) for key in multipliers):
                break
            tiers.append(nxt_id)
            previous = nxt
            step += 1
        if not tiers:
            return None
        top = sp[tiers[-1]]
        return {
            "tiers": len(tiers) + 1,
            "tierSpEffectIds": [int(t) for t in tiers],
            "topRates": {key: as_number(top[key]) for key in sorted(base_keys)},
            "saved": True,
        }

    # --- emit buffs -------------------------------------------------------
    buffs: list[dict[str, Any]] = []
    sentinel_rows: list[dict[str, Any]] = []
    display_inputs: dict[int, tuple[list[dict[str, Any]], str | None]] = {}
    # ids the dataset will ship, needed before the loop so the stack-ladder scan
    # can stop at the next *reachable* tier instead of swallowing it
    shipped_ids = {sid for sid in sources if sp.get(sid) is not None and classify(sid)[0]}
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

        # --- drop "×0" economy sentinels --------------------------------
        # 704000 "[Skill - Raider] Retaliate (Defense and Immortality)" is the
        # Raider's counter i-frame window: effectEndurance=0 and its real
        # payload is the slash/blow/.../DamageCutRate=0.25 columns this dataset
        # does not read.  Its one readable value is
        # characterSkillCooldownReduction=0, which -- the field being a
        # multiplier with lowerIsBetter -- renders as 「技艺冷却 ×0（-100%）」,
        # a fake infinite cooldown reduction sitting next to the real relic
        # steps 0.95 / 0.925 / 0.9.  The 0 is a sentinel for "no cooldown
        # bookkeeping inside this window", not a displayable rate.
        #
        # The rule is kept deliberately narrow so it cannot eat real data:
        # 青露的秘密滴泪 (511060 / 708920) and 魔法帷幕 (1801400) also carry ×0
        # consumption rates, but they run for 15 / 20 / 8 seconds and really do
        # make casting free, so effectEndurance != 0 keeps them in.
        qualifying_keys = {k for k in rates
                           if RATE_FIELD_BY_KEY[k]["group"] in QUALIFY_GROUPS}
        sentinel_keys = {k for k in qualifying_keys
                         if RATE_FIELD_BY_KEY[k]["group"] == "economy"
                         and RATE_FIELD_BY_KEY[k]["valueKind"] == "multiplier"
                         and float(rates[k]) == 0.0}
        if (qualifying_keys and qualifying_keys == sentinel_keys
                and float(row["effectEndurance"]) == 0.0):
            sentinel_rows.append({
                "spEffectId": int(sp_id),
                "paramName": row.get("Name") or None,
                "rates": dict(rates),
                "duration": as_number(row["effectEndurance"]),
                "why": "唯一的合格数值是 valueKind=multiplier 的 economy 字段且取值为 0，"
                       "同时 effectEndurance=0（没有持续时间）——这是哨兵值而不是可展示的倍率，"
                       "按 -100% 展示会得出错误结论，故不作为 buff 输出。",
            })
            continue

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
        inferred_name_from: str | None = None
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
                inferred_name_from = "attachEffectSibling"
                # nameEn keeps whatever it already had (usually the Paramdex row
                # name, which spells out the potency step and so is strictly
                # more informative than the affix name).
                if not name_en:
                    name_en = sibling_en
        if not name_en:
            name_en = clean_param_name(row.get("Name", "")) or None
        if not name_zh:
            name_source = None

        buff_target, buff_target_source = classify_target(
            sp_id, row, sources[sp_id],
            {RATE_FIELD_BY_KEY[key]["group"] for key in rates})

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
        # v4: the one key a ranking page can branch on for "does this multiplier
        # only apply to a particular kind of attack".  Folds the two places the
        # game states such a restriction (magicSubCategoryChange + stateInfo)
        # into one vocabulary; see ATTACK_CONTEXTS and enums.attackContext.
        state_info = int(row["stateInfo"])
        attack_contexts = sorted(
            {ATTACK_CONTEXT_BY_SUBCATEGORY[value] for value in sub_categories
             if value in ATTACK_CONTEXT_BY_SUBCATEGORY}
            | ({ATTACK_CONTEXT_BY_STATE_INFO[state_info]}
               if state_info in ATTACK_CONTEXT_BY_STATE_INFO else set())
        )
        if attack_contexts:
            scope["attackContexts"] = attack_contexts  # -> enums.attackContext

        conditions: dict[str, Any] = {}
        for key, _label in CONDITION_FIELDS:
            if key in row and not is_default(row, key):
                conditions[key] = as_number(row[key])

        chain: list[dict[str, Any]] = []
        for key, _label in CHAIN_FIELDS:
            target = ref(row.get(key))
            if target:
                chain.append({"field": key, "spEffectId": int(target)})

        has_trigger = any(item.get("trigger") for item in src_list)
        desc_zh = zh["speffectInfo"].get(text_ids[0]) if text_ids else None
        stack_ladder = detect_stack_ladder(sp_id, row, rates, shipped_ids)
        buff_activation, buff_activation_source = classify_activation(
            row, sources[sp_id], conditions, has_trigger,
            float(row["effectEndurance"]),
            " || ".join(filter(None, (name_zh, name_en, desc_zh))),
            stack_ladder)

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
            # v1 exported the raw effectTargetFriend bit here.  That column is
            # a template default (9360 of 13472 SpEffectParam rows have it set)
            # and produced affectsAllies=true on 817 of 827 buffs, including
            # every pure self relic affix -- a badge that lights up on almost
            # every row carries no information.  The raw bit is kept under
            # effectTargetFriendRaw; affectsAllies now means "this really is
            # handed to teammates", i.e. the effect is delivered by a friendly
            # AoE bullet or the Paramdex row name says "Allies".
            "affectsAllies": buff_target == "ally",
            "effectTargetFriendRaw": row["effectTargetFriend"] == "1",
            "target": buff_target,
            "targetSource": buff_target_source,
            # v3.  `conditions` / `triggered` only see the SpEffectParam
            # condition columns, and the four biggest multipliers in the table
            # (Beast form x3.55, "below 25% Health" x1.5, two-handing +18%,
            # dual-wielding +18%) have neither, so the "filter by conditions"
            # ranking step was a no-op on exactly the rows it existed for.
            # `activation` is the field the page must branch on first; see
            # enums.activation / enums.activationSource and notes.activation.
            "activation": buff_activation,
            "activationSource": buff_activation_source,
        }
        if stack_ladder:
            entry["stackLadder"] = stack_ladder
        if inferred_name:
            entry["inferredName"] = True
            entry["inferredNameFrom"] = inferred_name_from
        if labels_zh:
            entry["statusLabelsZh"] = labels_zh
        if labels_en:
            entry["statusLabelsEn"] = labels_en
        if desc_zh:
            entry["descZh"] = desc_zh
        if conditions:
            entry["conditions"] = conditions
        if chain:
            entry["chainSpEffectId"] = chain
        if len(sources[sp_id]) > MAX_SOURCES_PER_BUFF:
            entry["sourcesTruncated"] = len(sources[sp_id])
        if has_trigger:
            entry["triggered"] = True
        for item in src_list:
            if not item.get("nameZh") and not item.get("inferred"):
                missing_item_zh.append(
                    f"{item['kind']} {item['id']} ({item.get('nameEn') or '?'})")
        buffs.append(entry)
        display_inputs[int(sp_id)] = (src_list, row.get("Name"))

    # --- borrow a name from an identical sibling step ---------------------
    # Some potency steps have no text of their own: SpEffect 8330104
    # "[Weapon] Improved Sorceries and Incantations - Potency 2" only has an
    # English PermanentBuffParam name, while 8330103 (Potency 1 of the very
    # same affix, identical scope columns) does have 「强化魔法、祷告」.  Borrow
    # across steps only when the Paramdex stem AND every scope column match,
    # and flag it so a consumer knows the text is not this row's own.
    stem_names: dict[tuple[Any, ...], tuple[str, str | None]] = {}
    for buff in buffs:
        if not buff["nameZh"] or buff.get("inferredName"):
            continue
        row = sp[str(buff["spEffectId"])]
        stem = param_stem(row.get("Name", ""))
        if not stem:
            continue
        key = (stem,) + tuple(row.get(f) for f in NAME_BORROW_SCOPE_FIELDS)
        stem_names.setdefault(key, (buff["nameZh"], buff["nameSource"]))
    for buff in buffs:
        if buff["nameZh"]:
            continue
        row = sp[str(buff["spEffectId"])]
        stem = param_stem(row.get("Name", ""))
        if not stem:
            continue
        key = (stem,) + tuple(row.get(f) for f in NAME_BORROW_SCOPE_FIELDS)
        borrowed = stem_names.get(key)
        if not borrowed:
            continue
        buff["nameZh"] = borrowed[0]
        buff["nameSource"] = borrowed[1]
        buff["inferredName"] = True
        buff["inferredNameFrom"] = "siblingSpEffect"
        buff["displayNameZh"] = borrowed[0]

    missing_zh = [
        f"{buff['spEffectId']} {sp[str(buff['spEffectId'])].get('Name') or ''} "
        f"-> {buff['nameEn']}".strip()
        for buff in buffs if not buff["nameZh"]
    ]

    # --- display names ----------------------------------------------------
    # Only names that actually collide get a qualifier: a unique name such as
    # 「【女爵】提升技艺造成的伤害」 stays clean, while the 92 buffs called
    # 「提升攻击力」 all get told apart.  v1 stopped after one qualifier (the
    # source name) and still left 323 of 827 buffs sharing a display name --
    # 「提升火属性攻击力（火油脂）」 covered six rows whose only difference was the
    # grease level and the weapon slot.  The qualifiers are therefore applied
    # in escalating order until every name in the whole list is unique, and
    # that uniqueness is asserted below.
    # Level order.  The raw English Paramdex row name used to sit at level 0,
    # which is why 261 Chinese names carried an English qualifier and why one
    # member of a potency family could be spelled out in English while its
    # siblings got a tidy 「档位N」.  It now sits second to last, after the
    # tokens that read well in either language.
    LEVEL_KEYS = ("localizedOrigin", "potency", "weaponSide",
                  "rowCategory", "rate", "rawOrigin", "spEffectId")
    LEVEL_COUNT = len(LEVEL_KEYS)

    for field, is_zh in (("displayNameZh", True), ("displayNameEn", False)):
        heads: dict[int, str] = {}
        levels: dict[int, list[str | None]] = {}
        used: dict[int, set[int]] = {}
        for buff in buffs:
            base = buff[field]
            sp_key = buff["spEffectId"]
            if not base:
                heads[sp_key] = ""
                levels[sp_key] = [None] * LEVEL_COUNT
                used[sp_key] = set()
                continue
            src_list, param_name = display_inputs[sp_key]
            head, localized, raw = display_head(base, src_list, is_zh, param_name)
            heads[sp_key] = head
            used[sp_key] = set()
            levels[sp_key] = [
                localized,
                step_token(param_name, is_zh),
                side_token(buff["scope"], param_name, is_zh),
                row_category_label(param_name, is_zh),
                rate_token(buff["rates"], is_zh),
                raw,
                f"#{sp_key}",
            ]

        named = [b for b in buffs if b[field]]

        def render(sp_key: int) -> str:
            tokens = []
            for index in sorted(used[sp_key]):
                token = levels[sp_key][index]
                if token and token not in tokens:
                    tokens.append(token)
            return assemble(heads[sp_key], tokens, is_zh)

        def collisions() -> dict[str, int]:
            counts: dict[str, int] = defaultdict(int)
            for buff in named:
                counts[render(buff["spEffectId"])] += 1
            return counts

        def escalate() -> None:
            for level in range(LEVEL_COUNT):
                counts = collisions()
                if all(count == 1 for count in counts.values()):
                    return
                for buff in named:
                    sp_key = buff["spEffectId"]
                    if counts[render(sp_key)] < 2:
                        continue
                    if levels[sp_key][level]:
                        used[sp_key].add(level)

        escalate()

        # --- keep a family spelled the same way ---------------------------
        # Members of one affix family (same Paramdex stem) used to end up in
        # different styles: 8330101 got 「强化祷告（档位2）」 while its own
        # 8330100 needed 「（档位1・×1.05・#8330100）」 because it collided with
        # the [Relic] copy of the same affix.  Give every member of a family the
        # union of the levels any member needed, so one relic set reads as one
        # block in the list.
        families: dict[str, list[int]] = defaultdict(list)
        for buff in named:
            _src, param_name = display_inputs[buff["spEffectId"]]
            stem = param_stem(param_name or "")
            if stem:
                families[stem].append(buff["spEffectId"])
        for members in families.values():
            if len(members) < 2:
                continue
            union = set().union(*(used[sp_key] for sp_key in members))
            for sp_key in members:
                used[sp_key] |= union
        # the union only ever adds tokens, so it cannot break a family apart,
        # but it can collide a family member with an unrelated buff -- escalate
        # once more (the last level is #spEffectId, which always separates).
        escalate()

        # Once a name carries #spEffectId it is unique on that alone, so the raw
        # English row name is pure noise at that point -- and it is the longest,
        # ugliest token of the lot.  Dropping it keeps
        # 「米莉森的义手（护符・×1.11・#312507）」 readable instead of
        # 「米莉森的义手（护符・×1.11・Millicent's Prosthesis・#312507）」.
        raw_level = LEVEL_KEYS.index("rawOrigin")
        id_level = LEVEL_KEYS.index("spEffectId")
        for buff in named:
            sp_key = buff["spEffectId"]
            if id_level in used[sp_key]:
                used[sp_key].discard(raw_level)

        for buff in named:
            buff[field] = render(buff["spEffectId"])

        seen_display: dict[str, int] = {}
        for buff in named:
            value = buff[field]
            if value in seen_display:
                raise AssertionError(
                    f"{field} is not unique: {value!r} used by "
                    f"{seen_display[value]} and {buff['spEffectId']}")
            seen_display[value] = buff["spEffectId"]

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
    payload["schemaChangelog"] = SCHEMA_CHANGELOG
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
        "zh": "收录「能改变输出数值」且能从玩家可获得的物品／法术／永久强化／遗物词条追溯到的 SpEffect。"
              "**注意：能追溯到玩家物品 ≠ 挂在玩家身上**——投掷道具与法术的 Bullet 命中槽（spEffectId0..4）"
              "把效果挂在被命中的对象上，复仇者的家人（海伦／弗雷德里克／塞巴斯蒂安）另有自己的数值缩放行。"
              "因此每条 buff 都带 `target`（self／ally／summon／enemy），排名前必须先按它过滤。"
              "本作没有独立的『战技伤害 +x%』类字段，针对战技／跳跃攻击／防御反击／绝招等的强化"
              "都是普通的 AttackRate 字段 + magicSubCategoryChange 子类过滤，见每条 buff 的 scope。",
        "target": "`target` 说明这条 SpEffect 实际挂在谁身上：self＝只作用于玩家自己；ally＝自己与／或附近队友"
                  "（友方 AoE 弹道，如黄金树立誓、振奋香，或行名明示 Allies 的团队增益）；"
                  "summon＝复仇者家人等召唤物**自己**的数值缩放（296220『塞巴斯蒂安』的 0.15 是召唤物的伤害系数，"
                  "不是让玩家伤害变成 15%）；enemy＝挂在被命中的敌人身上（酸蚀喷雾、桂奥尔的咆哮这类减益，"
                  "或『魅惑树枝』让被魅惑的敌人攻击力 ×2）。"
                  "**增伤排名只能对 target 为 self／ally 的条目做乘算**；enemy 条目的 `direction` 描述的是"
                  "敌人数值的增减（decrease＝把敌人削弱，对玩家有利），语义与 self 条目相反，"
                  "summon 条目请单独成表。判定依据见每条的 `targetSource`，中文解释在 enums.targetSource。"
                  "**v4 注意**：油脂、附加属性武器、毒雾这类『打中谁就给谁上异常累积』的行，"
                  "target 一律是 enemy（v3 里由 atkOccurrenceSpEffectId 投递的 33 条被错标成 self，"
                  "与结构完全相同、由弹道投递的同类自相矛盾）。"
                  "但它们**确实是玩家的异常累积手段**——要做『异常状态累积』榜时不要只留 target=self，"
                  "应按 sources[].kind 取玩家可获得的来源（goods／spell／weaponPassive…），"
                  "target 在那条轴上表示的是『累积加在谁身上』，本来就该是 enemy。",
        "activation": "`activation` 是**发动条件的机读标记**，三态：passive／conditional／activated。"
                      "`conditions` 与 `triggered` 只能看到 SpEffectParam 自带的条件列，"
                      "而表里最大的那几个倍率恰恰不写在参数列里——它们由 ESD／EMEVD 脚本开关，"
                      "所以 v2 里 704301『残血 25% 以下 ×1.5』、8300000-2『双手持 +12/15/18%』、"
                      "8310000-2『双持 +12/15/18%』、707201-215『处刑人绝招兽化 ×1.62–3.55』"
                      "的 conditions 与 triggered 全是 null。"
                      "**只有 activation=\"passive\" 的条目才允许默认乘进通用排名**；"
                      "conditional 与 activated 必须由用户显式勾选（默认不计入）。"
                      "另外请注意互斥：8300000-2（双手共持）与 8310000-2（双手各持）不可能同时成立，"
                      "同理 707201-215 是绝招兽化的 15 个等级，同一时刻只有一层。"
                      "判定依据逐条写在 `activationSource`，中文解释见 enums.activationSource；"
                      "passive 的含义是『没有额外的发动条件』，不等于『不用付出代价』——"
                      "消耗品仍要先喝、遗物词条仍要先装备，那是 sources 的事；"
                      "也**不等于『对所有攻击都生效』**——那是 scope.attackContexts 管的，见 notes.attackContext。"
                      "**v4 修正**：v3 把 conditions 整个拿来判定，而 conditions 里混着 motionInterval"
                      "（效果重新 tick 的间隔［秒］）与 isPeriodicEffect（周期性重新施加）两个计时字段，"
                      "结果 210 条无条件 buff 被误判成 conditional——其中就有狂热香药 ×1.45／×1.35、"
                      "夏玻利利的嘶吼 ×1.25、火焰啊赐予我力量 ×1.20、黄金树立誓 ×1.15，"
                      "也就是整张表里最常用的几条消耗品与团队增益。"
                      "现在只有 conditionFields[].isActivationCondition=true 的列才参与判定。",
        "attackContext": "`scope.attackContexts` 是**作用情境的机读标记**：非空表示这条倍率只在列出的攻击情境下"
                         "才吃得到，**默认不得乘进通用排名**，只有用户勾选了该情境才参与乘算。"
                         "它和 activation 是正交的两条轴——activation 回答『这份 buff 现在挂在身上吗』，"
                         "attackContexts 回答『挂着的时候哪些攻击吃得到』。"
                         "『强化致命一击 ×1.24』『强化突刺反击 ×1.20』装上就一直在（activation=passive），"
                         "但只有打出致命一击／突刺反击时才生效，所以必须靠这一条拦住。"
                         "取值与中文说明见 enums.attackContext，其中还写明每个键是从哪个原始值推出来的："
                         "fromSubCategories 对应 magicSubCategoryChange1..3（ATK_SUB_CATEGORY），"
                         "fromStateInfo 对应 SpEffectParam.stateInfo（SP_EFFECT_TYPE，中文标签见 enums.stateInfo）。"
                         "**v3 只有前一条来路是机读的**，所以 stateInfo=367（强化致命一击，6 条 ×1.12–1.24）"
                         "与 stateInfo=197（强化突刺反击，4 条 ×1.10–1.20）在页面看来是『对所有攻击生效的常驻增伤』；"
                         "突刺反击那 4 条的 scope 甚至是 affectsSorcery／affectsIncantation／affectsShaman 全 true。"
                         "注意 attackContexts 只收『玩家进入的攻击情境』，"
                         "武器／法术门类过滤（近战武器攻击、远程武器攻击、战技攻击、各流派魔法祷告）"
                         "仍然只出现在 scope.subCategories 里，按伤害构成加权即可，不属于情境勾选。",
        "conditions": "带 `conditions` / `triggered` 的 buff 有发动条件（武器种类、血量、自身状态、概率、命中触发等），"
                      "例如 7037001 是送葬者遗物词条，只有装备该词条并且身上有祷告辅助效果时才给 +19%——"
                      "它挂在 30 个辅助祷告的 Magic.refId10 上，并不代表任何人施放这些祷告都能拿到。"
                      "排名时必须让用户勾选是否满足条件，**默认不计入乘积**。"
                      "本版本 conditions 字段的中文含义见 conditionFields。"
                      "⚠️ conditions 里有两个字段**不是发动条件**："
                      "motionInterval（效果每几秒重新施加一次，ER paramdef『発動間隔[s]』）与 "
                      "isPeriodicEffect（是否按该间隔周期性重新施加）。"
                      "它们是光环／持续类效果的计时机制，几乎每条有持续时间的 buff 都带，"
                      "**判断一条 buff 是否有发动条件时必须跳过它们**——"
                      "conditionFields[].isActivationCondition 就是为此而设。",
        "damageTypeNaming": "参数里的 dark 槽位在本作即『圣』属性；physics 为物理总量，slash/blow/thrust/neutral 是物理攻击类型细分。",
        "ranking": "增伤排名的推荐步骤（顺序不能省）："
                   "① 先按 `target` 过滤，只保留 self 与 ally——summon 是召唤物自己的系数、"
                   "enemy 是挂在敌人身上的效果，混进来会直接占据榜首／榜尾；"
                   "② 按 `direction` 过滤（只要 increase／mixed）；"
                   "③ **先看 `activation`，再看 `conditions`／`triggered`**："
                   "只有 activation=\"passive\" 才允许默认计入乘积；"
                   "conditional（残血、双手持、叠层、命中触发…）与 activated（技艺／绝招／战技发动期间）"
                   "一律由用户勾选，默认不计入。"
                   "顺序不能反过来——v2 只写了『看 conditions／triggered』，而 704301（×1.5）、"
                   "8300000-2、8310000-2、707201-215（×3.55）这些榜首条目的 conditions／triggered 全是 null，"
                   "那一步在最需要它的条目上是空转的。"
                   "拿到具体条件字段仍然看 `conditions`（含义见 conditionFields，"
                   "**只有 isActivationCondition=true 的列才是发动条件**，"
                   "motionInterval／isPeriodicEffect 是计时机制）与 `triggered`；"
                   "④ **再看 `scope.attackContexts`**：非空表示这条倍率只在某种攻击情境下生效"
                   "（致命一击、突刺反击、防御反击、连段最后一击、蓄力、跳跃／冲刺／翻滚攻击、双手持…），"
                   "**默认不得计入通用排名**，只有当用户勾选了对应情境时才参与乘算——"
                   "这类条目本身是 passive（装上就一直在），限制的是作用范围而不是发动时机，"
                   "所以第③步拦不住它们，必须单独走这一步。"
                   "其余 scope 字段（affectsSorcery／affectsIncantation／affectsShaman／affectsThrow／"
                   "weaponSlot／spAttribute／subCategories）仍按伤害构成加权；"
                   "attackContexts 是 subCategories 与 stateInfo 两条来路的归一化视图，"
                   "原始值都还在原处，中文解释见 enums.attackContext；"
                   "⑤ 对每个 rates 字段查 `rateFields[key].valueKind` 与 `countsAsDamage`／`conditionalDamage` "
                   "决定怎么用——damage 组（减防后）与 attackPower 组（减防前）分别按伤害构成加权后两层相乘，"
                   "attackPowerFlat 先加后乘，conditionalDamage 只在对应分区里算，"
                   "stance／status 另开一条轴，special／flag／economy 只展示不乘；"
                   "⑥ 用 `stacking.group` 分组去重（同组按 `spCategoryBehavior` 处理）后跨组相乘；"
                   "⑦ 列表一律显示 `displayNameZh`（已保证唯一）。",
        "howToUseRates": "把 rates 折算成伤害之前，必须先看 rateFields[key].valueKind："
                         "multiplier 可直接相乘；flat 是点数，要先加进攻击力再乘倍率；"
                         "flag 只是开关，不参与计算；special 的每个字段语义各不相同、"
                         "**一律不得相乘**（restageAttackRate=0.6 指女爵『再演』复制那一份占 60%，"
                         "不是 -40% 伤害）。再用两个布尔做粗筛："
                         "`countsAsDamage=true` 的组（damage／attackPower／attackPowerFlat）是**无条件**的血量伤害，"
                         "可以进通用乘积；`conditionalDamage=true` 的组与字段（weakness 特攻、critical 致命一击、"
                         "以及 economy 里的 bowDistRate 远程衰减）确实改血量伤害，但要先满足条件才成立，"
                         "**不得无条件乘进通用排名**——『纠死圣律』weakDmgRateB=10 只对不死类敌人生效，"
                         "无条件相乘会让它以 ×10 稳居榜首；页面应在『指定敌人类型』或『远程／致命一击』分区里另算。"
                         "两者都为 false 的组（stance 削韧、status 异常累积、special、flag、其余 economy）"
                         "不进伤害乘积，只单独展示或另开轴。",
        "displayName": "nameZh 取自状态栏文本，重名极多（『提升攻击力』92 条、『异常状态：冻伤』53 条），"
                       "**任何列表都不要只显示 nameZh**。请直接用 displayNameZh／displayNameEn，"
                       "**生成时已断言它们在全表唯一**（v1 还有 323/827 条重名，现在为 0）。"
                       "消歧是逐级追加的：名字本身唯一时等于 nameZh；否则依次补"
                       "① 本地化来源名（『提升攻击力（黄金树立誓）』）、② 强度档位（Potency／Level／+N%）、"
                       "③ 武器槽（右手／左手）、④ 来源类别（武器／遗物／护符／道具／战技／祷告／魔法／技艺／绝招／被动，"
                       "取自 Paramdex 行名的 [...] 前缀）、⑤ 首个 rates 数值（×1.11 / 火攻击力加算+35）、"
                       "⑥ 原始英文行名，全部用完仍重名才退到 `#spEffectId`。"
                       "因此『提升火属性攻击力（火油脂・档位2・右手）』这种长名字是刻意的："
                       "六个油脂档位×左右手原本完全同名。"
                       "v3 相对 v2 改了两处：原始英文行名从第一级降到倒数第二级（v2 有 261 条中文名挂着英文行名做限定词，"
                       "还会出现括号套括号的『强化魔法、祷告（Improved Sorceries and Incantations (+11%)）』）；"
                       "同族（Paramdex 行名词干相同）的条目现在强制取相同的限定词组合，"
                       "避免同一组遗物一条带 #id、一条不带。"
                       "实际退到 `#spEffectId` 的条数见 counts.displayNameZhFallingBackToSpEffectId，"
                       "完整 ID 清单见 diagnostics.displayNameZhFallingBackToSpEffectId（v2 为 52 条）。",
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
            "conditionalDamage": group["conditionalDamage"],
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
            "countsAsDamage": field["countsAsDamage"],
            "conditionalDamage": field["conditionalDamage"],
            "observedCount": rate_field_usage.get(field["key"], 0),
            **({"lowerIsBetter": True} if field.get("lowerIsBetter") else {}),
            "appliesTo": field["appliesTo"],
        }
        for field in RATE_FIELDS
    ]
    payload["enums"] = {
        "atkSubCategory": {str(k): {"zh": v[0], "en": v[1]} for k, v in ATK_SUB_CATEGORY.items()},
        "attackContext": {
            key: {
                "zh": zh_label,
                "en": en_label,
                "fromSubCategories": list(subs),
                "fromStateInfo": list(states),
            }
            for key, (zh_label, en_label, subs, states) in ATTACK_CONTEXTS.items()
        },
        "stateInfo": {str(k): {"zh": v[0], "en": v[1]} for k, v in STATE_INFO_TYPE.items()},
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
        "sourceRelicMount": "sources[] 里带 relicMount=true 的条目表示：这条 SpEffect 是挂在一批法术的 "
                            "Magic.refIdN 槽位上的**遗物词条**效果（所有辅助祷告共用同一个挂载槽），"
                            "mountedOnSpellCount / mountedOnSpellIds 记录了共用它的法术数量与 ID。"
                            "它不是这些法术本身的增益，必须同时满足该词条已装备与 conditions 里的发动条件。",
        "target": {key: {"zh": labels[0], "en": labels[1]}
                   for key, labels in TARGET_LABELS.items()},
        "targetSource": dict(TARGET_SOURCE_LABELS),
        "activation": {key: {"zh": labels[0], "en": labels[1]}
                       for key, labels in ACTIVATION_LABELS.items()},
        "activationSource": dict(ACTIVATION_SOURCE_LABELS),
        "sourceIdContract": "sources[].id 是来源表的行 ID，可以按 (kind, id) 联表；"
                            "但 inferred=true 的条目在参数表里根本没有对应行（由游戏脚本挂载），"
                            "其 id 恒为 null，消费方看到 inferred:true 必须只用 nameEn / paramRowCategory 展示，不得联表。",
    }
    payload["conditionFields"] = [
        {
            "key": key,
            "zh": label,
            # v4: two of these columns are timing, not conditions.  A consumer
            # deciding "is this buff gated" must skip the false ones -- and so
            # must classify_activation, which v3 did not.
            "isActivationCondition": key not in TIMING_CONDITION_FIELDS,
        }
        for key, label in CONDITION_FIELDS
    ]
    payload["chainFields"] = [{"key": key, "zh": label} for key, label in CHAIN_FIELDS]
    payload["stackingRules"] = {"zh": STACKING_RULES_ZH}
    target_counts: dict[str, int] = defaultdict(int)
    for buff in buffs:
        target_counts[buff["target"]] += 1
    activation_counts: dict[str, int] = defaultdict(int)
    activation_source_counts: dict[str, int] = defaultdict(int)
    attack_context_counts: dict[str, int] = defaultdict(int)
    for buff in buffs:
        activation_counts[buff["activation"]] += 1
        activation_source_counts[buff["activationSource"]] += 1
        for context in buff["scope"].get("attackContexts", ()):
            attack_context_counts[context] += 1
    display_id_fallback = [
        buff["spEffectId"] for buff in buffs
        if buff["displayNameZh"] and DISPLAY_ID_TAIL_RE.search(buff["displayNameZh"])
    ]
    payload["counts"] = {
        "buffs": len(buffs),
        "sourceLinksByKind": dict(sorted(kind_counts.items())),
        "buffsByKind": {k: len(v) for k, v in sorted(kind_buffs.items())},
        "buffsByRateGroup": dict(sorted(group_counts.items())),
        "buffsByTarget": dict(sorted(target_counts.items())),
        "buffsByActivation": dict(sorted(activation_counts.items())),
        "buffsByActivationSource": dict(sorted(activation_source_counts.items())),
        "buffsByAttackContext": dict(sorted(attack_context_counts.items())),
        "buffsWithAttackContext": sum(1 for b in buffs if b["scope"].get("attackContexts")),
        "buffsWithStackLadder": sum(1 for b in buffs if b.get("stackLadder")),
        "displayNameZhFallingBackToSpEffectId": len(display_id_fallback),
        "buffsAffectingAllies": sum(1 for b in buffs if b["affectsAllies"]),
        "buffsWithoutChineseName": sum(1 for b in buffs if not b["nameZh"]),
        "buffsOnlyInferredFromParamRowName": sum(
            1 for b in buffs if b["sources"] and all(s.get("inferred") for s in b["sources"])
        ),
    }
    inferred_name_origins: dict[str, int] = defaultdict(int)
    for buff in buffs:
        if buff.get("inferredName"):
            inferred_name_origins[buff.get("inferredNameFrom") or "unknown"] += 1
    non_self_targets: dict[str, list[int]] = defaultdict(list)
    for buff in buffs:
        if buff["target"] != "self":
            non_self_targets[buff["target"]].append(buff["spEffectId"])
    unique_missing = sorted(set(missing_zh))
    unique_missing_items = sorted(set(missing_item_zh))
    unused_rate_fields = [f["key"] for f in RATE_FIELDS if not rate_field_usage.get(f["key"])]
    unused_scope_keys = [
        key for key in ("weaponSlot", "atkAttribute", "spAttribute", "subCategories",
                        "attackContexts")
        if not any(key in b["scope"] for b in buffs)
    ]
    observed_behaviours = sorted({b["stacking"]["spCategoryBehavior"] for b in buffs})

    def damage_multipliers(buff: dict[str, Any]) -> list[float]:
        return [value for key, value in buff["rates"].items()
                if RATE_FIELD_BY_KEY[key]["countsAsDamage"]
                and RATE_FIELD_BY_KEY[key]["valueKind"] == "multiplier"
                and value > 1]

    def multiplier_digest(buff: dict[str, Any]) -> dict[str, Any]:
        contexts = buff["scope"].get("attackContexts", [])
        sub_categories = buff["scope"].get("subCategories", [])
        gate_from = sorted(
            ({"subCategories"} if sub_categories else set())
            | ({"stateInfo"} if buff["stacking"]["stateInfo"]
               in ATTACK_CONTEXT_BY_STATE_INFO else set()))
        digest = {
            "spEffectId": buff["spEffectId"],
            "displayNameZh": buff["displayNameZh"],
            "paramName": buff["paramName"],
            "maxMultiplier": max(damage_multipliers(buff)),
            "duration": buff["duration"],
            "activation": buff["activation"],
        }
        if contexts:
            digest["attackContexts"] = contexts
        if sub_categories:
            digest["subCategories"] = sub_categories
        if gate_from:
            digest["gateFrom"] = gate_from
        return digest

    def is_scope_gated(buff: dict[str, Any]) -> bool:
        return bool(buff["scope"].get("attackContexts")
                    or buff["scope"].get("subCategories"))

    passive_damage = sorted(
        (b for b in buffs
         if b["target"] in ("self", "ally") and b["activation"] == "passive"
         and damage_multipliers(b)),
        key=lambda b: (-max(damage_multipliers(b)), b["spEffectId"]))
    general_multipliers = [b for b in passive_damage if not is_scope_gated(b)]
    context_gated_multipliers = [b for b in passive_damage if is_scope_gated(b)]
    oppose_without_hit_slot = [
        b["spEffectId"] for b in buffs
        if sp[str(b["spEffectId"])].get("effectTargetSelfTarget") == "0"
        and sp[str(b["spEffectId"])].get("effectTargetOpposeTarget") == "1"
        and b["targetSource"] == "default"
    ]
    payload["diagnostics"] = {
        "buffsWithoutChineseName": len(unique_missing),
        "buffsWithoutChineseNameSample": unique_missing[:60],
        "sourceItemsWithoutChineseName": unique_missing_items[:40],
        "note": "没有简体中文名的 buff：绝大多数是只能靠 Paramdex 行名推断出来的战技／技艺／武器 buff（游戏内没有对应的 FMG 文本），已保留英文名与 paramName。",
        "buffsWithInferredName": sum(1 for b in buffs if b.get("inferredName")),
        "buffsWithInferredNameByOrigin": dict(sorted(inferred_name_origins.items())),
        "inferredNameNote": "inferredName=true 的 buff，其 nameZh 不是该 SpEffect 自己的文本，而是借来的，"
                            "来源写在 inferredNameFrom："
                            "attachEffectSibling＝同族遗物词条（AttachEffectParam id-id%10 / id-id%100）的名字；"
                            "siblingSpEffect＝同一条目的另一个强度档位（Paramdex 行名去掉『- Potency N』后的词干相同，"
                            "且 wepParamChange/magParamChange/miracleParamChange/shamanParamChange/throwAttackParamChange/"
                            "atkAttribute/spAttribute/magicSubCategoryChange1-3 全部一致）。"
                            "两种借用都做了词干＋作用范围校验：v1 把 8330104"
                            "『Improved Sorceries and Incantations - Potency 2』误标成 8330100 的「强化祷告」，"
                            "现在它会正确借到 8330103 的「强化魔法、祷告」。",
        "nonSelfTargetBuffs": {
            key: sorted(value)[:60]
            for key, value in sorted(non_self_targets.items())
        },
        "activationNote": "activation 的三态判定完全由数据推出，没有写死的 ID 名单，判定依据逐条写在 "
                          "buffs[].activationSource（中文解释见 enums.activationSource）。"
                          "本版本取值分布见 counts.buffsByActivation／buffsByActivationSource。"
                          "**页面必须先按 activation 过滤再按 conditions／triggered 取具体条件**："
                          "v2 里 704301（残血 ×1.5）、8300000-2（双手持 +12/15/18%）、"
                          "8310000-2（双持 +12/15/18%）、707201-215（绝招兽化 ×1.62–3.55）"
                          "的 conditions 与 triggered 全是空的，按 v2 文档实现的排名会把它们当无条件增伤压在榜首。"
                          "**v4 两处修正**："
                          "① v3 的『conditions 非空 → conditional』把 motionInterval（重新施加间隔［秒］）"
                          "与 isPeriodicEffect（周期性重新施加）这两个计时列也算了进去，"
                          "结果 210 条 buff 仅凭一个 tick 间隔被判成 conditional——"
                          "其中 8 条是 target∈{self,ally} 的真实无条件增伤"
                          "（708720 狂热香药·档位2 ×1.45、503550 狂热香药 ×1.35、1733000 夏玻利利的嘶吼 ×1.25、"
                          "707070／707071 处刑人 Tenacity ×1.2、1605000 火焰啊赐予我力量 ×1.20、"
                          "1660000 黄金树立誓 ×1.15、1732 Golden Great Arrow ×1.075）。"
                          "现在只看 conditionFields[].isActivationCondition=true 的列，"
                          "处刑人 Tenacity 改由 paramRowPassiveTimed（[Passive - X] 行且时长有限）判出，"
                          "1732 改由 eventScriptTimedBuff 判出，都不再依赖那个 0.06 秒的 tick。"
                          "② activation 只回答『这份 buff 现在在不在身上』，不回答『哪些攻击吃得到』——"
                          "后者是 scope.attackContexts（v4 新增），"
                          "致命一击族与突刺反击族在 v3 里是 passive 且毫无作用范围标记，"
                          "会被无条件乘进排名，见 diagnostics.contextGatedMultipliers。",
        "topUnconditionalMultipliers": [
            multiplier_digest(buff) for buff in general_multipliers[:40]
        ],
        "topUnconditionalMultipliersNote": "按 target∈{self,ally} ＋ activation=passive ＋ countsAsDamage 倍率，"
                                           "**且 scope 里既没有 attackContexts 也没有 subCategories** 筛出的前 40 条，"
                                           "也就是页面默认会原封不动乘进通用排名的那一批。"
                                           "这份清单是给维护者做人工抽查用的：如果哪天有明显需要发动条件的"
                                           "条目出现在这里，说明 activation 判定漏了一条规则。"
                                           f"本版本符合条件的共 {len(general_multipliers)} 条"
                                           f"（另有 {len(context_gated_multipliers)} 条受作用范围限制，"
                                           "见 contextGatedMultipliers）。"
                                           "v3 只导出前 15 条、阈值卡在 ×1.28，也不区分作用范围，"
                                           "结果排在第 16–20 名开外的致命一击族／突刺反击族整个漏出了抽查范围。",
        "contextGatedMultipliers": [
            multiplier_digest(buff) for buff in context_gated_multipliers
        ],
        "contextGatedMultipliersNote": "target∈{self,ally} ＋ activation=passive ＋ countsAsDamage 倍率，"
                                       "但作用范围受限——装上就一直生效（所以是 passive），"
                                       "可是只有一部分攻击吃得到，**不得原封不动乘进通用排名**。"
                                       "两种受限方式要分开处理："
                                       "① `attackContexts` 非空＝只在某种攻击情境下生效"
                                       "（致命一击、突刺反击、防御反击、蓄力、跳跃／冲刺／翻滚…），"
                                       "**默认不计入，用户勾选该情境后才乘**；"
                                       "② 只有 `subCategories`＝限定攻击／法术门类"
                                       "（投掷壶道具攻击、香水道具攻击、远程武器攻击、各流派魔法祷告…），"
                                       "按伤害构成加权即可，不必做成勾选项。"
                                       "gateFrom 写明限制写在哪一列：subCategories＝magicSubCategoryChange1..3"
                                       "（v1 起就机读）；stateInfo＝SpEffectParam.stateInfo"
                                       "（v3 之前只有裸数字，致命一击族 6 条 ×1.12–1.24 与突刺反击族 4 条 ×1.10–1.20 "
                                       "因此在页面看来是对所有攻击生效的常驻增伤——"
                                       "突刺反击族的 scope 甚至是 affectsSorcery/Incantation/Shaman 全 true）。",
        "opposeBitsWithoutHitSlot": sorted(oppose_without_hit_slot),
        "opposeBitsWithoutHitSlotNote": "这些条目的 effectTargetSelfTarget=0／effectTargetOpposeTarget=1"
                                        "（阵营过滤位说『只允许打给敌方』），但它们的来源全部是 Paramdex 行名推断、"
                                        "武器行为槽或其它无法确认投递路径的通道，"
                                        "既没有 Bullet 命中槽也没有 atkOccurrenceSpEffectId，"
                                        "因此仍按保守缺省判成 target=\"self\"。"
                                        "**这是缺省而不是已证实的结论**：阵营位本身只说明『这份效果允许打给谁』，"
                                        "不说明『这条 SpEffect 挂在谁身上』。"
                                        "若下一轮能把 [AoW] 行的投递路径还原出来，这批条目多半要改判 enemy。",
        "stackLadders": [
            {
                "spEffectId": buff["spEffectId"],
                "displayNameZh": buff["displayNameZh"],
                "paramName": buff["paramName"],
                "tiers": buff["stackLadder"]["tiers"],
                "tier1Rates": dict(buff["rates"]),
                "topRates": buff["stackLadder"]["topRates"],
                "activation": buff["activation"],
                "activationSource": buff["activationSource"],
            }
            for buff in buffs if buff.get("stackLadder")
        ],
        "stackLaddersNote": "数据集只收录了这些叠层效果的**第 1 层**（参数表里只有第 1 层被某个参数列指向，"
                            "更高层由游戏脚本按层数替换）。buffs[].stackLadder 给出总层数、后续各层的 spEffectId "
                            "与满层数值，页面展示时不要把 rates 当成该词条的上限："
                            "7069001『每次打倒封印监牢里的囚犯』第 1 层 ×1.05、满 10 层 ×1.6289；"
                            "7069201『每次打倒黑夜入侵者』×1.07 → ×1.9672；"
                            "8988200『玛雷家的庇佑』×1.011 → ×1.70（100 层）；"
                            "8998000『复仇的庇佑』×1.007 → ×1.40（100 层）。"
                            "同层互斥（spCategory 落在 removePrevious 区间），所以任何时刻只有一层生效，"
                            "绝不能把各层相乘。"
                            "检测是结构性的：ID 连续、行名为空、除倍率外所有列相同、倍率逐层严格递增、"
                            "且 saveCategory≠-1——最后一条把『[Relic] Improved Throwing Pot Damage +1/+2』"
                            "这种可分别装备的词条档位排除在外（它们的 saveCategory 都是 -1）。",
        "passiveWithoutParamName": sorted(
            buff["spEffectId"] for buff in buffs
            if buff["activation"] == "passive" and not buff["paramName"]
        ),
        "passiveWithoutParamNameNote": "activation 判定链的前两条规则读的是 Paramdex 英文行名，"
                                       "对没有行名的条目天然失效。这里列出最终仍判成 passive、"
                                       "却连行名都没有的条目，供维护者人工复核——"
                                       "它们的发动条件（如果有）只可能写在本地化文本或游戏脚本里。"
                                       "v3 这份清单有 4 条（7069001／7069201／8988200／8998000），"
                                       "全部是叠层阶梯的第 1 层，v4 已分别由 localizedNameCondition 与 "
                                       "stackLadderTier1 判成 conditional。",
        "sentinelOnlyRows": sentinel_rows,
        "sentinelOnlyRowsNote": "这些 SpEffect 满足入选条件，但它们唯一的合格数值是一个『×0』的 economy 倍率"
                                "并且没有持续时间（effectEndurance=0），属于哨兵值而不是可展示的倍率，"
                                "因此**不作为 buff 输出**，只记在这里。"
                                "本版本唯一实例 704000『[Skill - Raider] Retaliate (Defense and Immortality)』"
                                "是无赖反击那一瞬的免伤／无敌窗口（真正的负载是本数据集不读的 "
                                "slash/blow/thrust/neutral/magic/fire/thunder/dark DamageCutRate=0.25），"
                                "它的 characterSkillCooldownReduction=0 若按字面展示就是『技艺冷却 -100%』，"
                                "会与真正的遗物档位 0.95／0.925／0.9 混在同一个『输出效率』列表里。"
                                "注意排除规则刻意收得很窄：青露的秘密滴泪（511060／708920）与魔法帷幕（1801400）"
                                "同样带 ×0 的消耗倍率，但它们有 15／20／8 秒的持续时间、确实让施法免费，仍然保留。",
        "nonSelfTargetNote": "target 不是 self 的 buff：summon＝复仇者家人自身的数值缩放行（不是玩家倍率）；"
                             "enemy＝通过命中槽挂到被命中对象身上的效果"
                             "（Bullet.spEffectId0..4 或 atkOccurrenceSpEffectId；"
                             "减益、魅惑后的敌人增伤，以及油脂／附加属性武器打上去的异常累积）；"
                             "ally＝友方 AoE／团队增益。它们仍然保留在数据集里（有各自的展示价值），"
                             "但**增伤排名必须先按 target 过滤**。",
        "skippedUnnamedSourceRows": {
            table: {
                "rows": len(row_ids),
                "rowIdsSample": sorted(row_ids, key=int)[:40],
                "spEffectIdsQualifying": sorted(
                    (int(t) for t in skipped_unnamed_targets[table] if qualifies(t)))[:60],
            }
            for table, row_ids in sorted(skipped_unnamed.items())
        },
        "skippedUnnamedSourceRowsNote": "这些来源表行在简中与英文 FMG 里都查不到名字（多为未启用的箭矢／弩矢等占位行），"
                                        "整行跳过、不作为 buff 来源。跳过本身大概率是对的，但记录下来是为了让下个版本"
                                        "FromSoft 补上名字时，数量变化能被 diff 出来，而不是无声发生。"
                                        "spEffectIdsQualifying 是这些被跳过的行指向、且本身满足入选条件的 SpEffect。",
        "displayNameZhFallingBackToSpEffectId": sorted(display_id_fallback),
        "displayNameNote": "这些条目的 displayNameZh 以『#spEffectId』结尾——来源名、强度档位、武器槽、"
                           "来源类别（武器／遗物／护符…）、首个 rates 数值、原始英文行名全部用完仍然重名，"
                           "只能退到 ID。v2 是 52 条且同族内风格分裂（8330100 带 #id、8330101 不带）；"
                           "v3 新增了『来源类别』一级并强制同族（param_stem 相同）取相同的限定词组合，"
                           "所以同一组遗物在列表里要么都带 #id、要么都不带。",
        "unusedRateFields": unused_rate_fields,
        "unusedRateFieldsNote": "这些 rateFields 在本版本的 buff 里 observedCount=0，页面无需为它们写分支；"
                                "保留是因为它们在 SpEffectParam 里确实存在，便于下个版本命中时自动出现。"
                                "v2 起 economy 组已改为 qualifies=true，因此技艺冷却／追加次数／绝招量表／"
                                "弓射程衰减这类条目会真正进入数据集，不再整条缺席。",
        "unusedScopeKeys": unused_scope_keys,
        "unusedScopeKeysNote": "本版本所有 buff 的 atkAttribute 都是 254（不限），因此 scope.atkAttribute 不会出现；"
                               "enums.atkAttribute 仍保留以备后续版本。",
        "observedSpCategoryBehaviors": observed_behaviours,
        "spCategoryNote": "全部 buff 的 stacking.spCategoryBehavior 都落在 enums.spCategoryBehavior 的已知区间内"
                          f"（本次实测取值：{'、'.join(observed_behaviours)}）；"
                          "spCategory 205/206/1007/1008 虽未出现在 Paramdex 枚举里，但已按所在区间（200 系＝removePrevious、1000 系＝applyHighest）归类。",
    }
    payload["buffs"] = buffs
    self_check(payload)
    return payload


def self_check(payload: dict[str, Any]) -> None:
    """Invariants the page is allowed to rely on.  Raises on violation."""
    buffs = payload["buffs"]
    field_by_key = {f["key"]: f for f in payload["rateFields"]}
    group_by_key = {g["key"]: g for g in payload["rateFieldGroups"]}

    for group in payload["rateFieldGroups"]:
        assert not (group["countsAsDamage"] and group["conditionalDamage"]), \
            f"group {group['key']} is both unconditional and conditional damage"
    for field in payload["rateFields"]:
        assert not (field["countsAsDamage"] and field["conditionalDamage"]), \
            f"field {field['key']} is both unconditional and conditional damage"
        assert field["group"] in group_by_key, field["key"]

    ids = [b["spEffectId"] for b in buffs]
    assert ids == sorted(ids), "buffs must stay sorted by spEffectId"
    assert len(set(ids)) == len(ids), "duplicate spEffectId"

    behaviours = {entry["code"] for entry in payload["enums"]["spCategoryBehavior"]}
    for name in ("displayNameZh", "displayNameEn"):
        values = [b[name] for b in buffs if b[name]]
        assert len(set(values)) == len(values), f"{name} is not unique"

    bullet_hit = re.compile(r"Bullet\d+\.spEffectId[0-4](?:->|$)")
    attack_hit = re.compile(r"atkOccurrenceSpEffectId(?:->|$)")
    timing_condition_keys = {
        field["key"] for field in payload["conditionFields"]
        if not field["isActivationCondition"]
    }
    assert timing_condition_keys == TIMING_CONDITION_FIELDS, timing_condition_keys
    for buff in buffs:
        sp_id = buff["spEffectId"]
        assert buff["target"] in payload["enums"]["target"], (sp_id, buff["target"])
        assert buff["targetSource"] in payload["enums"]["targetSource"], (sp_id, buff["targetSource"])
        assert buff["activation"] in payload["enums"]["activation"], (sp_id, buff["activation"])
        assert buff["activationSource"] in payload["enums"]["activationSource"], \
            (sp_id, buff["activationSource"])
        # an activated / conditional label must never be *weaker* than the
        # explicit condition columns the row already carries -- but the two
        # timing columns are not conditions, so they may not force the label
        real_conditions = set(buff.get("conditions") or {}) - timing_condition_keys
        if real_conditions or buff.get("triggered"):
            assert buff["activation"] != "passive", (sp_id, "condition columns but passive")
        # every attack context must be resolvable, and must really come from a
        # raw value the row carries (no context invented out of nothing)
        for context in buff["scope"].get("attackContexts", ()):
            assert context in payload["enums"]["attackContext"], (sp_id, context)
            spec = payload["enums"]["attackContext"][context]
            assert (set(spec["fromSubCategories"]) & set(buff["scope"].get("subCategories", ()))
                    or buff["stacking"]["stateInfo"] in spec["fromStateInfo"]), (sp_id, context)
        if buff["stacking"]["stateInfo"]:
            assert str(buff["stacking"]["stateInfo"]) in payload["enums"]["stateInfo"], sp_id
        ladder = buff.get("stackLadder")
        if ladder:
            assert ladder["tiers"] == len(ladder["tierSpEffectIds"]) + 1, sp_id
            assert set(ladder["topRates"]) == set(buff["rates"]), sp_id
            # tier 1 of a saved ladder is never an unconditional multiplier
            assert buff["activation"] == "conditional", (sp_id, "stack ladder but not conditional")
        # a buff every one of whose routes is a bullet *hit* slot lands on the
        # thing that was hit, so it can never be the "no evidence" default --
        # this is the invariant the `$`-anchored via regex used to violate
        # (1631001 『授血』 reached through ...spEffectId0->cycleOccurrenceSpEffectId)
        vias = [entry["via"] for entry in buff["sources"]]
        if vias and (all(bullet_hit.search(via) for via in vias)
                     or all(attack_hit.search(via) for via in vias)):
            assert buff["targetSource"] != "default", (sp_id, vias)
        # no shipped buff may rest solely on a "×0 with no duration" sentinel
        sentinel = [key for key, value in buff["rates"].items()
                    if field_by_key[key]["group"] == "economy"
                    and field_by_key[key]["valueKind"] == "multiplier"
                    and float(value) == 0.0]
        if sentinel and buff["duration"] == 0:
            qualifying_here = [key for key in buff["rates"]
                               if group_by_key[field_by_key[key]["group"]]["qualifies"]]
            assert set(qualifying_here) - set(sentinel), (sp_id, "sentinel-only row shipped")
        assert buff["affectsAllies"] == (buff["target"] == "ally"), sp_id
        assert isinstance(buff["effectTargetFriendRaw"], bool), sp_id
        assert buff["stacking"]["spCategoryBehavior"] in behaviours, sp_id
        for key in buff["rates"]:
            assert key in field_by_key, (sp_id, key)
        assert buff["rateGroups"] == sorted({field_by_key[k]["group"] for k in buff["rates"]}), sp_id
        for entry in buff["sources"]:
            if entry.get("inferred"):
                assert entry["id"] is None, (sp_id, entry)
        if buff.get("inferredName"):
            assert buff.get("inferredNameFrom") in ("attachEffectSibling", "siblingSpEffect"), sp_id

    # every buff must keep at least one rate that justified its inclusion
    qualifying = {g["key"] for g in payload["rateFieldGroups"] if g["qualifies"]}
    for buff in buffs:
        assert any(group in qualifying for group in buff["rateGroups"]), buff["spEffectId"]


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
