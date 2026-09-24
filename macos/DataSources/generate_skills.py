#!/usr/bin/env python3
"""生成「战技 / 法术 / 武器」数据集（nightreign-skills-v1.03.5.json）。

用途
----
给应用里的「增伤排名」与「削韧查询」页提供：
  * 每把武器的基础攻击力（分属性）、基础削韧、战技引用、攻击力补正表引用；
  * 每个战技 / 法术由哪些「分段命中」（AtkParam_Pc 行）组成；
  * 每段命中的动作值（atk*Correction，百分比，乘武器对应属性攻击力）、
    固定伤害（atkPhys/atkMag/... ，子弹与法术常用）、削韧、攻击属性（斩/打/突/标准）。

数据来源（均为本机导出，不入库）
------------------------------
  raw/params/<ParamName>.csv      regulation.bin 10350000 解出的参数表
                                  首列 ID、第二列 Name 为社区 Paramdex（Smithbox）英文行名
  raw/msg/<lang>/<bnd>_dlc01/*.json  游戏 FMG 文本，zhocn / engus，X.json + X_dlc01.json 合并

用到的表与字段
--------------
  EquipParamWeapon   武器：wepType / rarity / attackBase* / attackBaseStamina /
                     saWeaponDamage / correct* / atkAttribute / atkAttribute2 /
                     swordArtsParamId / attackElementCorrectId / reinforceTypeId /
                     behaviorVariationId
                     （atkAttribute / atkAttribute2 是 AtkParam.atkAttribute = 253 / 252
                       那 1064 段的实际物理伤害类型来源，见 usage.伤害类型）
  SwordArtsParam     战技：textId → ArtsName；atkParamId（代表攻击）；
                     enableSparringGrounds；sparringGroundsWeaponId
  Magic              法术：ID → MagicName；mp；atkParamId；
                     ezStateBehaviorType（Paramdex Param Meta 标注 Enum="MAGIC_CATEGORY"，
                       0=Sorcery 魔法 / 1=Incantation 祷告 / 2=Pyromancy，本作未见 2）；
                     refId1..10 + refCategory1..10（Paramdex Refs：
                       refCategory=0 → AtkParam_Pc，1 → Bullet，2 → SpEffectParam）
  AtkParam_Pc        分段命中：atk*Correction / atk* / atkSuperArmor(Correction) /
                     atkStam(Correction) / atkAttribute / isAddBaseAtk /
                     overwriteAttackElementCorrectId
  Bullet             子弹：atkId_Bullet → AtkParam_Pc；HitBulletID / intervalCreateBulletId 子链
  AttackElementCorrectParam  只读 ID 列，用来校验 overwriteAttackElementCorrectId
                     是不是悬空引用（本表内容不收录，见 usage.本数据集的边界）
  BehaviorParam_PC   两个用途：
                     (1) 兜底：variationId == 武器 behaviorVariationId 且
                         behaviorJudgeId ∈ [900,950) 的行是「该武器专属战技」的攻击槽
                         （refType 0=攻击 / 1=子弹）；
                     (2) **动作套归属**：行 ID = base + variationId*1000 + behaviorJudgeId。
                         同一个 (base, judge) 上按三级回退取行：武器 behaviorVariationId 本身 →
                         向下取整到百位的「族」variationId（v3 补上，例 1406 → 1400、117 → 100）→
                         variationId = 0 的通用行——游戏就是这样挑动作的。
                         据此可以把「这把武器的这个战技实际会打出哪些 AtkParam 行」解出来，
                         写进 skills[].variants，武器侧再给 skillVariant / skillVariants 下标。
  （v3）局内武器的战技池：
  EquipParamCustomWeapon   局内掉落 / 商店 / 宝箱给出的「成品武器」：targetWeaponId → EquipParamWeapon
                     基础武器，swordArtsTableId → SwordArtsTableParam 池（-1 = 不抽池）
  SwordArtsTableParam      战技池：**同一个 ID 的全部行 = 一个池**（与 AttachEffectTableParam
                     同一惯例），每行 swordArtsId + chanceWeight（权重，>0 才算池成员）
  ItemTableParam / ItemLotParam_map / ItemLotParam_enemy / ShopLineupParam
                     只用来判「哪些 custom 行真的会给到玩家」：itemCategory=6 /
                     lotItemCategory0N=6 / equipType=6 引用的 custom 行 ID（实测三者引用的 ID
                     全部落在 EquipParamCustomWeapon 里，见 PROVENANCE「战技池（v3）」）
  （v3 修订）法术的可施放口径：
  EquipParamCustomWeapon.magicTableId_1 / magicTableId_2   施法器（手杖 / 圣印记）custom 行的两个法术槽
  MagicTableParam          法术池：同一个 ID 的全部行 = 一个池（同 SwordArtsTableParam），每行 magicId + chanceWeight

法术来源（v3 修订）
-----------------
  spells[] 只收「本作玩家能施放」的法术：magicId 出现在可达施法器 custom 行（可达口径同下面的战技池）的
  magicTableId_1 / _2 指向的 MagicTableParam 池里、且 chanceWeight>0（本版本 122 个池、158 个 magicId）。
  Magic 表里有名字却不在任何这种池里的行不收（本版本只有 8100 / 8101「风暴管束者」：全部参数表都不引用这两行 Magic，
  是本体把风暴管束者做成 Magic 时的残留行；本作的风暴管束者是战技 SwordArtsParam 1200，武器是各渡夜者的角色武器），
  记进 coverage.spellsNotCastable。命中归属仍按全部有名 Magic 行做（名字索引不变，其它法术的 hits 与修订前逐段相同），
  落地后再过滤。每个法术新增 casterWeaponIds / casterSources，施法器侧新增 weapons[].customMagicTables，顶层 magicPools。

战技池（v3）
-----------
  本作局内拿到的武器几乎都是 EquipParamCustomWeapon 行，战技由 swordArtsTableId 指向的池随机决定；
  EquipParamWeapon.swordArtsParamId 只是「基础武器自带的那一个」。v2 只看后者，于是风暴刃（210）、
  狩猎巨人（116）等 52 个战技没有任何武器引用、在增伤排名里选不到。v3 起：
    skills[].weaponIds     = 固定引用 ∪ 可达 custom 行的池（chanceWeight>0）里出现该战技的 targetWeaponId；
    skills[].weaponSources = 每把武器的来源（fixed / pool，池条目权重与 custom 行数）；
    weapons[].skillIds / skillVariants / customWeapons 与顶层 swordArtsPools 给出反向与回溯信息。
  池的分组规则（同 ID = 一池）的证据与反证见 PROVENANCE「战技池（v3）」与 fieldNotes.swordArtsPools。

命中段 TAE 核实（v3 第二部分）
----------------------------
  行为表（BehaviorParam_PC）解出的段不一定被本作的动画调用：1188 狩猎大蛇的两段 "Beam of Light" 参数还在，
  但战技 TAE a788 调用它们的事件带 stateInfo 187 门控（本作玩家拿不到）；二连斩 / 剑舞 / 鲜血斩击的几套动作
  挂在同一个 variationId=0 上，行为表分不出来，TAE 里却是互斥的几套 4xxxx 动画。所以生成时读
  raw/tae/invoked.json（extract_tae.py 从本机 c0000 动画包解出），用同目录 verify_skill_hits.py 的 TaeVerifier
  逐 (战技, 武器) 判定每段的状态，variants[].atkIds 只留 invoked / weaponTae / spEffect / conditional / noJudge；
  在所有武器上都被移除的段在 hits[] 里标 notInvoked + notInvokedReason；动画完全匹配不到的战技（弓系）标
  taeUnmatched、不过滤。invoked.json 缺失或 --no-tae 时保持行为表口径（counts.taeVerified=false），
  weapons / skills / spells / swordArtsPools 与 TAE 核实前逐项相同（审查修正后只差 hits[].selfOrAllyOnly 标记，其中带数值的几段另加 noDamage）。
  法术不做 TAE 过滤。判定规律见 PROVENANCE「TAE 动画事件与命中核实」，
  本步骤的结果见 PROVENANCE「命中段 TAE 核实（v3）」与产物的 diagnostics.taeVerification。
  同一趟 TAE 还用来分带 FP / 无 FP：战技 TAE 的 4xxxx 动画个位 0–4 是带 FP 版、5–9 是无 FP 版，行名没写 "No FP"
  但只被无 FP 版动画调用的段补标 hits[].noFp（noFpSource="tae"），两侧共用的段标 fpBoth。
  AtkParam 只打自己 / 队友的行（opposeTarget=0 且 selfTarget / friendlyTarget=1，祈祷一击的回血子弹）标
  noDamage + selfOrAllyOnly，不算对敌伤害。

动作套（variants）为什么必须存在
------------------------------
  通用战技（战吼 / 野蛮咆哮 / 回旋斩 / 盲击…）在参数里同时存在「不分武器的默认套」
  （行名 "[AoW] War Cry"）和「每个动作组各一套」（"[AoW Axe] War Cry"），
  两者是同一招的互斥变体，不是可叠加的分段。而行名方括号里的动作组名
  （Small Weapon / Large Weapon / Polearm / Scythe）不在 WEP_TYPE 枚举里，
  也没有全局的「别名 → wepType」对应：它们是**逐个战技**的动作族（110 盲击里
  Small Weapon = 曲剑 / 锤 / 连枷 / 斧、Large Weapon = 大剑 / 大曲剑 / 大锤 / 大斧），
  而且哪一族挂在 variationId=0 上当默认套也因战技而异。
  所以按 ctx 字符串过滤既会漏（斧 / 镰类取不到段）又会重（默认套与类别套一起算）。
  唯一正确的做法是 BehaviorParam_PC 实解，见 variants / skillVariant / skillVariants。
  （v2 的实解少了「取整到百位」这一级回退，曾得出「1400 的斧走 Small Weapon、1406/1407 的斧走
  Large Weapon」的结论；v3 补上后同一战技里同一武器类别只落进一套动作，无一例外。）

命中归属（hits）的几条路线，取并集，每条 hit 用 source 标明
----------------------------------------------------------
  "n"  行名匹配：AtkParam_Pc 行名 "[AoW <武器或类别>] <战技名> - <段标签>"，
       "[Sorcery] <法术名> ..." / "[Incantation] <法术名> ..."
  "b"  子弹：Bullet 行名同样解析，或 Magic.refCategory=1 的 refId；
       再沿 HitBulletID / intervalCreateBulletId 展开子子弹，取 atkId_Bullet
  "r"  Magic.refCategory=0 的 refId（直接指向 AtkParam_Pc）
  "a"  SwordArtsParam.atkParamId / Magic.atkParamId 锚点（弓系战技行名为空，只能靠它）；
       锚点只指向连段的第 1 段，命中后会把「同一行名组（同 ctx、同技能名）的整组行」
       一并收进来——否则龙戟的 1166 回旋斩只剩 1 段（实际是 6 连段）
  "w"  BehaviorParam_PC 兜底（仅对前几路一无所获、且只有唯一武器引用的战技启用）

  每段的 ctx（属于哪一套动作）一律以它自己的 AtkParam_Pc 行名为准，
  行名没有方括号时才退回发现它的那条路线给的 ctx。

用法
----
  cd "<repo>/macos/DataSources" && python3 generate_skills.py
  可选： --params <dir> --msg <dir> --out <file> --pretty
        --invoked raw/tae/invoked.json --sp-enum raw/paramdex/SP_EFFECT_TYPE.json --no-tae
"""

import argparse
import csv
import json
import re
import sys
from collections import Counter, defaultdict
from datetime import datetime, timezone
from pathlib import Path

SCHEMA_VERSION = 3   # v3：局内战技池（SwordArtsTableParam）进 weaponIds，新增 weaponSources / skillIds / skillVariants

# 结构变更记录：消费方可以程序化地知道每一版加了 / 改了什么（同 generate_buffs.py 的 schemaChangelog 惯例）。
SCHEMA_CHANGELOG = [
    {"version": 1,
     "summary": "初版：weapons / skills / spells 三张表，skills[].hits 与 spells[].hits 是按五条路线"
                "（n / b / r / a / w）收集的分段命中。"},
    {"version": 2,
     "summary": "新增 skills[].variants + weapons[].skillVariant（BehaviorParam_PC 实解每把武器实际打出的动作套，"
                "取代按 ctx 字符串过滤）；第二轮核验补 weapons[].atkAttribute / atkAttribute2、"
                "hits[].noVariant，悬空 overrideAecId 不再写出，跨条目误配段丢弃。"},
    {"version": 3,
     "summary": "两部分：(1) 局内武器的战技池进数据集——只增字段、旧字段语义不变，但 weaponIds 等字段的**取值范围**扩大；"
                "(2) 命中段按 TAE 动画事件核实——variants[].atkIds 只保留该战技的动画真正会打出的段"
                "（逐武器核对，互斥动画套只留这把武器播的一套），被移除的段仍留在 hits[] 并标 notInvoked。"
                "（2）需要生成时有 raw/tae/invoked.json，counts.taeVerified 标明本文件是否做过。",
     "added": [
         "skills[].weaponSources（每把武器的来源：fixed / pool，pool 项 = [swordArtsTableId, chanceWeight, custom 行数]）",
         "weapons[].skillIds（该武器局内可能出现的全部战技，含固定）",
         "weapons[].skillVariants（{战技 ID 字符串: 该战技 variants 的下标}，覆盖 skillIds 里每个有命中段的战技）",
         "weapons[].customWeapons（可达的 EquipParamCustomWeapon 行：[customId, swordArtsTableId]）",
         "swordArtsPools（顶层：被可达 custom 行引用的 SwordArtsTableParam 池，{池 ID: [[战技 ID, 权重], ...]}）",
         "schemaChangelog、coverage.skillsWithoutWeapons / skillsWithoutFixedWeapons / skillsPoolOnly、"
         "counts 里的池相关计数",
         "（TAE 核实）skills[].hits[].notInvoked + notInvokedReason：行为表给至少一把武器解出了这段、但在所有这些武器上"
         "都不会被该战技的动画调用（从 variants 移除，hits 里保留）；取值见 enums.notInvokedReason",
         "（TAE 核实）skills[].taeUnmatched：战技动画匹配不到的战技（本版本是弓系战技），hits / variants 不做过滤",
         "（TAE 核实）counts.taeVerified 与 hitsNotInvoked / hitsNotInvokedDamaging / hitsPartiallyRemovedByTae / "
         "weaponHitsRemovedByTae / skillWeaponPairsChangedByTae / skillsChangedByTae / skillsTaeUnmatched；"
         "enums.notInvokedReason；顶层 diagnostics.taeVerification（移除清单、部分武器移除清单、互斥动画套的选套、"
         "保留的条件触发 / SpEffect 触发 / 无法判定段）",
         "（审查修正）skills[].hits[].noFpSource（\"tae\" = noFp 由 TAE 判出）与 fpBoth（带 FP / 无 FP 两侧动画共用的段）；"
         "counts.hitsNoFpByTae / hitsNoFpByTaeDamaging / hitsFpBoth；diagnostics.taeVerification.noFpRule / noFpFromTae / "
         "fpBoth / noFpConflicts",
         "（审查修正）hits[].selfOrAllyOnly（AtkParam opposeTarget=0 且 selfTarget / friendlyTarget=1：只打自己 / 队友）；"
         "counts.hitsSelfOrAllyOnly / hitsSelfOrAllyOnlyWithValues",
         "（法术可施放口径）spells[].casterWeaponIds（能携带该法术的施法器基础武器）与 spells[].casterSources"
         "（{id, pool: [[magicTableId, chanceWeight, customRows], ...]}，仿 weaponSources）；weapons[].customMagicTables"
         "（[[customId, magicTableId_1, magicTableId_2], ...]）；顶层 magicPools（{池 ID: [[magicId, chanceWeight], ...]}）；"
         "coverage.spellsNotCastable(+Note)；counts.spellsNamed / spellsCastable / spellsDropped / magicPools / magicPoolEntries / "
         "magicPoolZeroWeightRows / casterWeapons / casterCustomRows / casterCustomRowsUnreachable / spellWeaponPairs；"
         "diagnostics.spellCasting；fieldNotes.casterWeaponIds / casterSources / customMagicTables / magicPools / spellsNotCastable；"
         "usage.法术来源（v3）",
     ],
     "changed": [
         "skills[].weaponIds：v2 = 只有 EquipParamWeapon.swordArtsParamId 反查；v3 = 固定引用 ∪ 局内战技池"
         "（可达 custom 行的 targetWeaponId，池里含该战技且 chanceWeight>0）。「能带这个战技的武器」这个含义不变，"
         "只是补上了池来源。",
         "skills[].variants[].weaponIds 随之扩展（新增的 (战技, 武器) 对同样用 BehaviorParam_PC 实解）；"
         "variants 的顺序仍按最小 atkId 排，所以已有武器的 skillVariant 下标可能变化，但始终与本文件的 variants 对齐。",
         "hits[].noVariant 按新的 variants 重算：原来没有武器的战技现在也会标记，原来标了的段可能因为新武器而变为可达。",
         "weapons[].skillVariant 语义不变：仍只指「swordArtsParamId 指向的那个固定战技」的 variants 下标。",
         "选段实解补上 BehaviorParam_PC 的「variationId 取整到百位」一级回退，1200 风暴管束者按「武器有专属行的"
         "行为组」消歧，103 回旋斩的手工表补齐新类别：hits 不变，但 58 个固定武器 (战技, 武器) 对的选段随之改变"
         "（109 连击 1、110 盲击 17、650 野蛮咆哮 24、651 战吼 16；regulation 10350000 实测，见 caveats）。",
         "（TAE 核实）skills[].variants[].atkIds：在行为表选段之上再按 TAE 核实，只留这把武器用这个战技时动画真会打出的段"
         "（invoked / weaponTae / spEffect / conditional，以及无法经 TAE 判定、保守保留的 noJudge）。"
         "含义从「行为表解得到的段」收窄为「本作真正打得出的段」，页面的取段写法不变。"
         "同一行为表选段的武器可能因动作组 TAE 或互斥动画套不同而分到不同 variant，所以 variants 数量、顺序与"
         "weapons[].skillVariant / skillVariants 下标都会变，但始终与本文件的 variants 对齐。",
         "（TAE 核实）hits[].noVariant 改按 TAE 核实**之前**的行为表选段判定（含义同 A 阶段：行为表层就没有武器用到），"
         "与 notInvoked 互斥。",
         "（TAE 核实）spells[] 不做 TAE 过滤（施法动画只按 refId 槽发射，见 fieldNotes.法术与 TAE）。",
         "（审查修正）hits[].noFp：原先只看行名里的 \"No FP\"；TAE 核实时再按战技 TAE 动画号（4xxxx 个位 5–9 = 无 FP 版）"
         "补标行名没写的无 FP 段（noFpSource=\"tae\"，labelZh 前补「无FP版」），例：风暴刃 300000411–413、狩猎巨人 301700915。"
         "页面取段要改成「hit.fpBoth 或 noFp 与开关同侧」（fpBoth 段两侧都计），带 FP 版不再混进无 FP 段。",
         "（审查修正）hits[].noDamage：除了六项全 0 的挂状态行，只打自己 / 队友的行（selfOrAllyOnly，如祈祷一击的回血子弹 "
         "1202100 / 1202110）也标 noDamage，motion / flat 原值保留。这一条不依赖 TAE，--no-tae 时同样生效。",
         "（审查修正）counts 的 *Damaging 计数（hitsWithoutVariantDamaging / hitsNotInvokedDamaging）不再把 noDamage 段算作带伤害。",
         "（法术可施放口径）spells[] 从「Magic 表里有 MagicName 的全部行」收窄为「可施放的行」：magicId 在可达施法器 custom 行"
         "（可达口径同战技池）的 magicTableId_1 / _2 指向的 MagicTableParam 池里且 chanceWeight>0。"
         "本版本只删掉 2 条死行 8100 / 8101「风暴管束者」（全部参数表都不引用这两行 Magic，是本体遗留；本作的风暴管束者是战技 1200，"
         "仍在 skills[]），移到 coverage.spellsNotCastable；其余 158 个法术的全部旧字段与 hits 逐项不变，只多了 casterWeaponIds / "
         "casterSources。counts.spells 160→158、spellsWithHits 139→137，hits / uniqueAtkIds 等全局计数少了这两行的段。"
         "schemaVersion 仍为 3：没有改名或改语义的字段，只删了两条死行、其余只增字段。",
     ]},
]
GAME_VERSION = "v1.03.5 + DLC1"
DATA_VERSION = "regulation 10350000"

HERE = Path(__file__).resolve().parent
DEFAULT_PARAMS = HERE / "raw" / "params"
DEFAULT_MSG = HERE / "raw" / "msg"
DEFAULT_OUT = HERE.parents[1] / "data" / "nightreign-skills-v1.03.5.json"
# TAE 核实（v3 第二部分）：extract_tae.py 解出的动画事件 + Paramdex 的 SP_EFFECT_TYPE（可选，只影响门控名的显示）
DEFAULT_INVOKED = HERE / "raw" / "tae" / "invoked.json"
DEFAULT_SP_ENUM = HERE / "raw" / "paramdex" / "SP_EFFECT_TYPE.json"

ELEMENTS = ("physical", "magic", "fire", "lightning", "holy")
# AtkParam_Pc 动作值字段（百分比，作用于武器对应属性攻击力）
MV_FIELDS = {
    "physical": "atkPhysCorrection",
    "magic": "atkMagCorrection",
    "fire": "atkFireCorrection",
    "lightning": "atkThunCorrection",
    "holy": "atkDarkCorrection",
}
# AtkParam_Pc 固定伤害字段
FLAT_FIELDS = {
    "physical": "atkPhys",
    "magic": "atkMag",
    "fire": "atkFire",
    "lightning": "atkThun",
    "holy": "atkDark",
}
# EquipParamWeapon 基础攻击力字段
WEP_ATK_FIELDS = {
    "physical": "attackBasePhysics",
    "magic": "attackBaseMagic",
    "fire": "attackBaseFire",
    "lightning": "attackBaseThunder",
    "holy": "attackBaseDark",
}

# Paramdex 枚举 WEP_TYPE（vawser/Smithbox@f5969c0 NR/Param Enums/WEP_TYPE.json）英文名 → 中文类别
WEP_TYPE_ZH = {
    -1: ("Any", "任意"),
    0: ("None", "无"),
    1: ("Dagger", "短剑"),
    3: ("Straight Sword", "直剑"),
    5: ("Greatsword", "大剑"),
    7: ("Colossal Sword", "特大剑"),
    9: ("Curved Sword", "曲剑"),
    11: ("Curved Greatsword", "大曲剑"),
    13: ("Katana", "刀"),
    14: ("Twinblade", "双头剑"),
    15: ("Thrusting Sword", "刺剑"),
    16: ("Heavy Thrusting Sword", "重刺剑"),
    17: ("Axe", "斧"),
    19: ("Greataxe", "大斧"),
    21: ("Hammer", "锤"),
    23: ("Great Hammer", "大锤"),
    24: ("Flail", "连枷"),
    25: ("Spear", "矛"),
    28: ("Great Spear", "大矛"),
    29: ("Halberd", "戟"),
    31: ("Reaper", "镰"),
    33: ("Fist (Unarmed)", "拳（徒手）"),
    35: ("Fist", "拳"),
    37: ("Claw", "爪"),
    39: ("Whip", "鞭"),
    41: ("Colossal Weapon", "特大武器"),
    50: ("Light Bow", "轻弓"),
    51: ("Bow", "弓"),
    53: ("Greatbow", "大弓"),
    55: ("Crossbow", "弩"),
    56: ("Ballista", "弩炮"),
    57: ("Glintstone Staff", "辉石魔杖"),
    61: ("Sacred Seal", "圣印记"),
    65: ("Small Shield", "小盾"),
    67: ("Medium Shield", "中盾"),
    69: ("Greatshield", "大盾"),
    81: ("Arrow", "箭"),
    83: ("Greatarrow", "大箭"),
    85: ("Bolt", "弩矢"),
    86: ("Greatbolt", "大弩矢"),
    87: ("Torch", "火把"),
    1100: ("Wylder - Greatsword", "追踪者专属大剑"),
    1200: ("Guardian - Halberd", "守护者专属戟"),
    1300: ("Ironeye - Bow", "铁之眼专属弓"),
    1400: ("Duchess - Dagger", "女爵专属短剑"),
    1500: ("Raider - Greataxe / Great Hammer / Colossal Weapon", "无赖专属大斧／大锤／特大武器"),
    1600: ("Revenant - Sacred Seal", "复仇者专属圣印记"),
    1700: ("Recluse - Glintstone Staff", "隐士专属辉石魔杖"),
    1800: ("Executor - Katana", "执行者专属刀"),
    1900: ("Scholar - Thrusting Sword", "学者专属刺剑"),
    2000: ("Undertaker - Hammer", "送葬者专属锤"),
}

# Paramdex 枚举 RARITY
RARITY_ZH = {
    0: ("Common / White", "普通"),
    1: ("Uncommon / Blue", "优良"),
    2: ("Rare / Purple", "稀有"),
    3: ("Legendary / Gold", "传说"),
    9: ("Unique / Red", "独特"),
}

# Paramdex 枚举 ATKPARAM_ATKATTR_TYPE
ATK_ATTR_ZH = {
    0: ("Slash", "斩击"),
    1: ("Strike", "打击"),
    2: ("Pierce", "突刺"),
    3: ("Standard", "标准"),
    252: ("WeaponAtkAttribute2", "沿用武器 atkAttribute2"),
    253: ("WeaponAtkAttribute", "沿用武器 atkAttribute"),
    254: ("None", "无"),
}

# Paramdex 枚举 MAGIC_CATEGORY（Magic.ezStateBehaviorType）
MAGIC_KIND = {0: "sorcery", 1: "incantation", 2: "pyromancy"}
MAGIC_KIND_ZH = {"sorcery": "魔法", "incantation": "祷告", "pyromancy": "火焰术"}

# EquipParamWeapon 的物理伤害类型字段（枚举同 ATKPARAM_ATKATTR_TYPE 的 0-3）。
# AtkParam_Pc.atkAttribute = 253 / 252 的段（本作 1065 段，占全部命中的 48%）
# 不自带伤害类型，而是「沿用武器的 atkAttribute / atkAttribute2」，
# 必须回武器行上取，否则这些段落不到具体的斩 / 打 / 突 / 标准，
# 也就没法按 boss 的 slash/blow/thrustDamageCutRate 加权。
# 只写 int + 中文名：英文名用 enums.atkAttribute[str(int)].en 查即可，
# 1793 把武器 × 2 个英文名 ≈ 96 KB，不值得为一次查表付这个体积。
WEP_ATK_ATTR_FIELDS = (
    ("atkAttribute", "atkAttributeZh"),
    ("atkAttribute2", "atkAttribute2Zh"),
)

# EquipParamWeapon 属性补正字段（游戏内「能力值补正」）
WEP_CORRECT_FIELDS = {
    "strength": "correctStrength",
    "dexterity": "correctAgility",
    "intelligence": "correctMagic",
    "faith": "correctFaith",
    "arcane": "correctLuck",
}

# ---------------------------------------------------------------- ctx 分类表
# Paramdex 在 AtkParam_Pc / Bullet 行名方括号里用 "[AoW <X>]" 标出这一段属于哪一套动作。
# X 有三种：武器名、武器「动作组」名、角色名（"[AoW - Duchess]" 这种带连字符的形式）。
#
# 动作组名里有 4 个不是 WEP_TYPE 枚举名的别名。**它们没有全局的 wepType 对应**：
# 同一个别名在不同战技里覆盖的类别不同，哪一族挂在 variationId=0 上当默认套也因战技而异
# （110 盲击：Small Weapon = 曲剑 / 锤 / 连枷 / 斧，Large Weapon = 大剑 / 大曲剑 / 大锤 / 大斧）。
# 所以本脚本不输出「别名→wepType」映射，每把武器到底用哪一套由 skills[].variants
# （BehaviorParam_PC 实解）给出。v2 曾记「1400 的斧走 Small、1406/1407 的斧走 Large」，
# 那是解析时漏了「variationId 取整到百位」这一级回退造成的，v3 已更正。
CTX_ALIAS_ZH = {
    "small weapon": ("Small Weapon", "小型武器动作组"),
    "large weapon": ("Large Weapon", "大型武器动作组"),
    "polearm": ("Polearm", "长柄武器动作组"),
    # Paramdex 的 "Scythe" 指 WEP_TYPE 31 Reaper（镰）这个类别，
    # 不是武器 19000000「大镰刀 / Scythe」——必须先判类别再判武器名，否则会译错。
    "scythe": ("Scythe", "镰"),
}

# "[AoW - X]" 带连字符的形式全部是渡夜者（角色）名，共 10 个，只用在 1200 风暴管束者上。
CHR_CTX_ZH = {"default": "默认角色"}

# BehaviorParam_PC 唯一无法区分的战技：103 回旋斩的 4 套动作（无 ctx / Large Weapon /
# Polearm / Twinblade）全部挂在 variationId=0 的 behaviorJudgeId 220-257 上，
# 任何武器解出来都是 4 套全中。这里按武器类别手工归组：
# 直剑 / 曲剑走无 ctx 的默认套，大曲剑走 Large Weapon，双头剑走 Twinblade，戟 / 镰走 Polearm。
# （依据：这 4 套正好对应引用该战技的 6 个类别所共用的 4 组动作。）
# v3：局内战技池让 103 还能出现在短剑 / 大剑 / 刀 / 斧 / 大斧 / 矛上，按同一套「动作族」补齐：
#   大剑、大斧 → Large Weapon；矛 → Polearm；短剑、刀、斧 → 默认套。
#   依据是行为表能解出来的同类战技：110 盲击（v3 三级回退后）Large Weapon = 大剑 / 大曲剑 / 大锤 / 大斧，
#   Small Weapon = 曲剑 / 锤 / 连枷 / 斧；矛 / 大矛 / 戟 / 镰在 118 罗蕾塔的斩击里同属长柄一族。
#   这是推断（行为表本身分不出来）；Large Weapon 与 Polearm 两套数值完全相同，所以真正有影响的
#   只是「默认套 vs 大型 / 长柄套」这一刀（动作值差 5）。
# hits[].notInvokedReason 的取值（= verify_skill_hits.py 的 status 里表示「这把武器用这个战技时打不出」的那些），
# 顺序即「不同武器原因不同时取哪一个」的优先级（与 verify_skill_hits.STATUS_ORDER 一致）
NOT_INVOKED_REASON_ZH = {
    "exclusiveBlock": "在战技动画里被调用，但只在另一套互斥的 4xxxx 动画里（战技 TAE 按百位分套：400 默认 / 402 大型武器 / "
                      "403 长柄 / 4XX = 该动作组专属），用到它的武器都播别的那套",
    "roarR2Only": "只出现在武器动作组的吼叫 R2 动画（30600–30635 / 32600–32635）里，而本战技不是吼叫类"
                  "（例：狩猎大蛇 301703955 只在大枪动作组的 a37_030605）",
    "gated": "只有带 stateInfo 187 门控的事件调用它，187 玩家拿不到（本作只有 SpEffect 1908 带它，1908 只被 NPC 召唤石引用）"
             "——例：狩猎大蛇的两段 Beam of Light",
    "elsewhere": "通用行（variationId=0）只在别的战技 / 动画里被调用，本战技在这些武器上的动画不调用它",
    "notInvoked": "解出的 TAE judgeId 在战技 TAE 与武器动作组 TAE 里都没有事件",
    "spEffectNoSource": "由 SpEffectParam.behaviorId 触发，但该 SpEffect 在全部参数表与全部 TAE 事件里都没有来源",
    "rowForOtherWeapon": "产出它的 BehaviorParam_PC 行只属于别的 behaviorVariationId，这些武器解不到",
    "unreferenced": "没有任何 BehaviorParam_PC 行、子弹、Magic 或其它参数列引用它",
}

# v3 修订（法术可施放口径）：不可施放的 Magic 行里，逐个核过「全部参数表」的那几个补充证据
# （生成器只程序化检查 MagicTableParam 与 custom 行；全表引用扫描是一次性的人工核查，见 PROVENANCE「法术可施放口径」）。
_MAGIC_8100_SCAN = ("全部 252 张参数表里取值为 8100 / 8101 的非 ID 列只有 NpcParam.spEffectID16 / SoundBankId / SfxResBankId、"
                    "RideParam.defChrId、SpEffectParam.behaviorId、ActionButtonParam.textId、"
                    "PersonalScenarioParam.personalScenarioObjectiveId，分别是 SpEffect / 音效库 / 特效库 / 角色 / 行为 / 文本 / 剧情目标 ID，"
                    "没有一列指向 Magic")
MAGIC_NOT_CASTABLE_EVIDENCE = {
    magic_id: f"；{_MAGIC_8100_SCAN}——是本体把风暴管束者做成 Magic 时的残留行" for magic_id in (8100, 8101)
}

CTX_MANUAL_BY_SKILL: dict[int, dict[int, str]] = {
    103: {1: "", 3: "", 9: "", 13: "", 17: "",
          5: "Large Weapon", 11: "Large Weapon", 19: "Large Weapon",
          14: "Twinblade", 25: "Polearm", 29: "Polearm", 31: "Polearm"},
}

# ---------------------------------------------------------------- 段标签中文化
# 多词短语优先，其次单词；未收录的词原样保留。
LABEL_PHRASES = [
    ("Beam of Light", "光之束"),
    ("Pre-Final Hit", "倒数第二击"),
    ("Pre-Final", "倒数第二段"),
    ("Charged Burst", "蓄力爆发"),
    ("Charged Helper", "蓄力辅助"),
    ("Ground Fire", "地面火焰"),
    ("Flame Aura", "火焰光环"),
    ("Area Flame", "范围火焰"),
    ("Magma Ball", "熔岩球"),
    ("Magma Floor", "熔岩地面"),
    ("Lava Pool", "熔岩池"),
    ("Staff Plant", "手杖插地"),
    ("Drill Initial", "钻击起手"),
    ("Drill Release", "钻击释放"),
    ("Constant Close Attack", "持续近身攻击"),
    ("Infrequent Stagger", "偶发硬直"),
    ("Bullet Damage", "子弹伤害"),
    ("Mounted Slash", "骑乘斩击"),
    ("Hit Ground", "命中地面"),
    ("No Target", "无目标"),
    ("Self Target", "自身目标"),
    ("Weapon Trail", "武器轨迹"),
]
LABEL_WORDS = {
    "UNUSED": "未使用",
    "unused": "未使用",
    "Heal": "回复",
    "Emitter": "发生源",
    "Others": "他人",
    "Starter": "起手",
    "Pre": "前置",
    "Launching": "起跳",
    "Attempt": "尝试",
    "Hold": "保持",
    "Stamina": "精力",
    "Cost": "消耗",
    "Middle": "中段",
    "Midleft": "中左",
    "Direct": "直击",
    "Defence": "防御",
    "Defense": "防御",
    "Late": "后段",
    "Tackle": "撞击",
    "Spell": "法术",
    "Dispel": "驱散",
    "Success": "成功",
    "Standard": "标准",
    "Returning": "回收",
    "Dive": "俯冲",
    "Bloom": "绽放",
    "Final": "最终段",
    "1H": "单手",
    "2H": "双手",
    "Charged": "蓄力",
    "Uncharged": "未蓄力",
    "Bullet": "子弹",
    "Self": "自身",
    "Other": "他人",
    "Final": "最终段",
    "Initial": "初段",
    "Start": "起手",
    "End": "收招",
    "During": "持续中",
    "Slash": "斩击",
    "Thrust": "突刺",
    "Swing": "挥击",
    "Slam": "砸击",
    "Stamp": "踏击",
    "Plunge": "跳劈",
    "Light": "轻击",
    "Heavy": "重击",
    "Right": "右",
    "Left": "左",
    "Mounted": "骑乘",
    "Damage": "伤害",
    "Hit": "命中",
    "Flame": "火焰",
    "Fire": "火",
    "Magma": "熔岩",
    "Lava": "熔岩",
    "Ball": "球",
    "Floor": "地面",
    "Ground": "地面",
    "Pool": "池",
    "Area": "范围",
    "AoE": "范围",
    "Aura": "光环",
    "Beam": "光束",
    "Melee": "近战",
    "Ring": "环",
    "Landing": "落地",
    "Shockwave": "冲击波",
    "Blast": "爆风",
    "Burst": "爆发",
    "Explosion": "爆炸",
    "Impact": "撞击",
    "Wave": "波",
    "Gravity": "重力",
    "Grab": "抓取",
    "Spear": "枪",
    "Drill": "钻击",
    "Drilling": "钻击",
    "Release": "释放",
    "Whorl": "漩涡",
    "Twirl": "旋转",
    "Spinning": "旋转",
    "Looping": "循环",
    "Mist": "雾",
    "Quake": "震荡",
    "Roar": "咆哮",
    "Staff": "手杖",
    "Plant": "插地",
    "Constant": "持续",
    "Close": "近身",
    "Attack": "攻击",
    "Infrequent": "偶发",
    "Stagger": "硬直",
    "Residual": "残留",
    "Trail": "轨迹",
    "Greatsword": "大剑",
    "First": "第一",
    "Second": "第二",
    "Rising": "上挑",
    "Descending": "下劈",
    "Flurry": "连击",
    "Projectile": "飞射物",
    "Waiting": "待机",
    "Emitted": "发射",
    "Followup": "追击",
    "Dodge": "翻滚",
    "Weapon": "武器",
    "Target": "目标",
    "Helper": "辅助",
    "Cure": "治愈",
    "Frost": "霜",
    "Blank": "空",
}

# ------------------------------------------------------------------ 基础工具
def read_param(params_dir: Path, name: str) -> list[dict]:
    path = params_dir / f"{name}.csv"
    if not path.exists():
        sys.exit(f"缺少参数表：{path}")
    with path.open(newline="", encoding="utf-8") as fh:
        return list(csv.DictReader(fh))


def read_fmg(msg_dir: Path, lang: str, bnd: str, fmg: str) -> dict[int, str]:
    """基础 X.json 与增量 X_dlc01.json 合并（后者覆盖）。"""
    out: dict[int, str] = {}
    for suffix in ("", "_dlc01"):
        path = msg_dir / lang / f"{bnd}_dlc01" / f"{fmg}{suffix}.json"
        if not path.exists():
            continue
        for key, value in json.loads(path.read_text(encoding="utf-8")).items():
            text = (value or "").strip()
            if text and text != "%null%":
                out[int(key)] = text
            else:
                out.pop(int(key), None)
    return out


def to_int(value: str, default: int = 0) -> int:
    try:
        return int(float(value))
    except (TypeError, ValueError):
        return default


def to_num(value: str, default: float = 0):
    """保留小数：atkSuperArmor / atkSuperArmorCorrection / saWeaponDamage 在参数表里是浮点
    （例如 5.5、10.175、262.5），直接取整会把削韧算错。整数值仍以 int 输出。"""
    try:
        num = float(value)
    except (TypeError, ValueError):
        return default
    num = round(num, 4)
    return int(num) if num == int(num) else num


def norm_key(text: str) -> str:
    """把名字压成「只留字母数字与单空格」的匹配键，吸收 Paramdex 行名里的标点差异
    （例如 AtkParam 的 "I Command Thee- Kneel!" 对 FMG 的 "I Command Thee, Kneel!"）。"""
    return re.sub(r"[^a-z0-9]+", " ", text.lower().replace("’", "'")).strip()


def strip_bracket_prefix(text: str) -> str:
    return re.sub(r"^\[[^\]]*\]\s*", "", (text or "").strip())


def paren_hint(text: str) -> str:
    m = re.search(r"\(([^)]*)\)\s*$", (text or "").strip())
    return m.group(1).strip() if m else ""


def strip_paren_suffix(text: str) -> str:
    return re.sub(r"\s*\([^)]*\)\s*$", "", (text or "").strip())


# ------------------------------------------------------------- 段标签中文化
def label_to_zh(label: str) -> str:
    """把 AtkParam 行名尾部的英文段标签规则化成可读中文。
    例："L2 #1-1" → "L2 第1段-第1击"；"No FP L2 #3" → "无FP版 L2 第3段"。"""
    if not label:
        return ""
    text = label.strip()
    prefix = ""
    # "No FP" 可能在开头，也可能跟在 "[UNUSED]" 之类的前缀后面
    if re.search(r"\bNo\s*FP\b", text, flags=re.I):
        prefix = "无FP版"
        text = re.sub(r"\bNo\s*FP\b\s*", "", text, flags=re.I).strip()
    text = re.sub(r"\[\s*UNUSED\s*\]|<\s*unused\s*>|\[\s*unused\s*\]", "〔未使用〕", text, flags=re.I)
    # 方括号 / 圆括号里的内容（如 "[Charged]"、"(Hit)"）先递归翻译，再统一成中文括号
    text = re.sub(r"\[([^\]]*)\]", lambda m: "〔" + (label_to_zh(m.group(1)) or m.group(1)) + "〕", text)
    text = re.sub(r"\(([^)]*)\)", lambda m: "〔" + (label_to_zh(m.group(1)) or m.group(1)) + "〕", text)

    for src, dst in LABEL_PHRASES:
        text = re.sub(re.escape(src), dst, text, flags=re.I)

    out: list[str] = []
    for token in re.findall(r"〔[^〕]*〕|\S+", text):
        if token.startswith("〔"):
            out.append("（" + token[1:-1] + "）")
            continue
        m = re.fullmatch(r"#(\d+)-(\d+)", token)
        if m:
            out.append(f"第{m.group(1)}段-第{m.group(2)}击")
            continue
        m = re.fullmatch(r"#(\d+)", token)
        if m:
            out.append(f"第{m.group(1)}段")
            continue
        m = re.fullmatch(r"([RLrl][12])-(\d+)", token)
        if m:
            out.append(f"{m.group(1).upper()} 第{m.group(2)}击")
            continue
        if re.fullmatch(r"[RLrl][12]", token):
            out.append(token.upper())
            continue
        if re.fullmatch(r"\d+", token):
            out.append(token)  # "Bullet 1"→"子弹 1"，编号原样保留
            continue
        core = token.strip(".,")
        zh = LABEL_WORDS.get(core) or LABEL_WORDS.get(core.capitalize())
        out.append(zh if zh else token)

    # 先用空格连接，再把「中文 中文」之间的空格去掉，避免 "第1击 蓄力" 变成 "第1击蓄力"
    joined = " ".join(p for p in out if p)
    joined = re.sub(r"(?<=[一-鿿（）])\s+(?=[一-鿿（）])", "", joined).strip()
    if prefix:
        joined = f"{prefix} {joined}".strip() if joined else prefix
    return joined


# ------------------------------------------------------------ 行名解析 / 匹配
ROW_RE = re.compile(r"^\[(?P<tag>[^\]]+)\]\s*(?P<rest>.*)$")


def parse_row_name(name: str) -> tuple[str, str, str, bool] | None:
    """把 Paramdex 行名拆成 (kind, ctx, rest, is_chr)。
    kind:   "aow" / "sorcery" / "incantation"
    ctx:    AoW 后面的武器名 / 动作组名 / 角色名（可能为空）
    is_chr: 行名写成 "[AoW - X]"（带连字符）——这种形式全部是角色名，
            例如 "[AoW - Duchess] Storm Ruler"、"[AoW - Default] Storm Ruler"。"""
    name = (name or "").strip()
    m = ROW_RE.match(name)
    if not m:
        return None
    tag = m.group("tag").strip()
    rest = m.group("rest").strip()
    if tag == "Sorcery":
        return ("sorcery", "", rest, False)
    if tag == "Incantation":
        return ("incantation", "", rest, False)
    if tag == "AoW" or tag.startswith("AoW "):
        ctx = tag[3:].strip()
        is_chr = ctx.startswith("-")
        ctx = ctx.lstrip("-").strip()
        return ("aow", ctx, rest, is_chr and bool(ctx))
    return None


class NameIndex:
    """英文名 → 条目 ID 的最长前缀匹配索引（条目 = 战技或法术）。"""

    def __init__(self) -> None:
        self.by_key: dict[str, list[str]] = defaultdict(list)
        self.keys_of: dict[str, set[str]] = defaultdict(set)
        self.hints: dict[str, set[str]] = defaultdict(set)
        self.specific: set[str] = set()
        self._sorted: list[str] | None = None

    def add(self, entry_id: str, name: str) -> None:
        key = norm_key(name)
        if key and entry_id not in self.by_key[key]:
            self.by_key[key].append(entry_id)
            self.keys_of[entry_id].add(key)
            self._sorted = None

    def add_hint(self, entry_id: str, hint: str, specific: bool = False) -> None:
        key = norm_key(hint)
        if key:
            self.hints[entry_id].add(key)
            if specific:
                self.specific.add(entry_id)

    def keys_desc(self) -> list[str]:
        if self._sorted is None:
            self._sorted = sorted(self.by_key, key=len, reverse=True)
        return self._sorted

    def match(self, rest: str) -> tuple[str, str] | None:
        """返回 (匹配到的名字键, 剩余的段标签)。"""
        normed = norm_key(rest)
        for key in self.keys_desc():
            if normed == key or normed.startswith(key + " "):
                tokens = re.findall(r"\S+", rest)
                label = " ".join(tokens[len(key.split()):]).strip()
                label = re.sub(r"^[-–—]\s*", "", label).strip()
                return key, label
            # 行名把多个条目写在一起，例如 "Chilling Mist/Poisonous Mist - Slash"
        return None

    def match_shared(self, rest: str) -> list[tuple[str, str]]:
        """处理 "A/B/C - label" 这种被多个条目共用的行名。"""
        head, _, tail = rest.partition(" - ")
        if "/" not in head:
            return []
        out = []
        for piece in head.split("/"):
            key = norm_key(piece)
            if key in self.by_key:
                out.append((key, tail.strip()))
        return out

    def resolve(self, key: str, ctx: str) -> list[str]:
        """同名多条目时，用行名括号里的武器名 / 类别（ctx）消歧。"""
        candidates = self.by_key.get(key, [])
        if len(candidates) <= 1:
            return list(candidates)
        ctx_key = norm_key(ctx)
        if ctx_key:
            exact = [c for c in candidates if ctx_key in self.hints.get(c, ())]
            if len(exact) == 1:
                return exact
            if exact:
                return exact
        generic = [c for c in candidates if c not in self.specific]
        if len(generic) == 1:
            return generic
        return list(candidates)


# --------------------------------------------------------------------- 子弹链
def bullet_chain(bullets: dict[str, dict], root: str, limit: int = 64) -> list[str]:
    """从一个子弹出发，沿 HitBulletID / intervalCreateBulletId 展开出全部相关子弹。"""
    seen: set[str] = set()
    order: list[str] = []
    stack = [root]
    while stack and len(order) < limit:
        bid = stack.pop()
        if bid in seen or bid not in bullets:
            continue
        seen.add(bid)
        order.append(bid)
        row = bullets[bid]
        for field in ("HitBulletID", "intervalCreateBulletId"):
            child = row.get(field, "-1")
            if child and child not in ("-1", "0") and child in bullets:
                stack.append(child)
    return order


# ------------------------------------------------------------------- hit 构造
def build_hit(atk_row: dict, label: str, no_fp: bool, sources: set[str],
              bullet_ids: list[str], ctx: str = "", ctx_zh: str = "",
              ctx_kind: str = "", aec_ids: frozenset[str] = frozenset(),
              aec_dangling: Counter | None = None) -> dict | None:
    """把一行 AtkParam_Pc 变成一个 hit。
    全零（无伤害、无削韧、无精力削减）的行：若只是子弹链/锚点顺带捞到的辅助行（Blank、
    No Target、Spell Helper 之类）就丢弃；若是行名直接点名的攻击行（source 含 n），
    则保留——那是该战技确实存在但只挂异常状态 / 减益的一段。"""
    motion = {el: to_num(atk_row.get(MV_FIELDS[el], "0")) for el in ELEMENTS}
    flat = {el: to_num(atk_row.get(FLAT_FIELDS[el], "0")) for el in ELEMENTS}
    poise = to_num(atk_row.get("atkSuperArmor", "0"))
    poise_mv = to_num(atk_row.get("atkSuperArmorCorrection", "0"))
    stamina = to_num(atk_row.get("atkStam", "0"))
    stamina_mv = to_num(atk_row.get("atkStamCorrection", "0"))
    empty = (not any(motion.values()) and not any(flat.values()) and not poise
             and not poise_mv and not stamina and not stamina_mv)
    if empty and "n" not in sources:
        return None
    # 只打自己 / 队友的行：opposeTarget=0 且 selfTarget 或 friendlyTarget=1。祈祷一击的回血子弹
    # 1202100 "Heal Self"（selfTarget）/ 1202110 "Heal Others"（friendlyTarget）各带圣 motion 100——那是回血量的倍率，
    # 不是对敌伤害。标 noDamage（三端都不把 noDamage 段计入构成）并加 selfOrAllyOnly 说明原因。
    # opposeTarget=0 但三项全 0 的行（神圣光环的光环、各种子弹链上的行）不在此列：它们由子弹自己的判定命中敌人。
    self_ally = (to_int(atk_row.get("opposeTarget", "1"), 1) == 0
                 and (to_int(atk_row.get("selfTarget", "0")) == 1 or to_int(atk_row.get("friendlyTarget", "0")) == 1))

    attr = to_int(atk_row.get("atkAttribute", "254"), 254)
    attr_en, attr_zh = ATK_ATTR_ZH.get(attr, (f"unknown({attr})", "未知"))

    hit: dict = {"atkId": to_int(atk_row["ID"])}
    if ctx:
        hit["ctx"] = ctx
        if ctx_kind:
            hit["ctxKind"] = ctx_kind
        if ctx_zh and ctx_zh != ctx:
            hit["ctxZh"] = ctx_zh
    if label:
        hit["label"] = label
        zh = label_to_zh(label)
        if zh:
            hit["labelZh"] = zh
    elif no_fp:
        hit["labelZh"] = "无FP版"
    if any(motion.values()):
        hit["motion"] = {el: motion[el] for el in ELEMENTS if motion[el]}
    if any(flat.values()):
        hit["flat"] = {el: flat[el] for el in ELEMENTS if flat[el]}
    if poise:
        hit["poise"] = poise
    if poise_mv:
        hit["poiseMv"] = poise_mv
    if stamina:
        hit["stamina"] = stamina
    if stamina_mv:
        hit["staminaMv"] = stamina_mv
    hit["attribute"] = attr_en
    hit["attributeZh"] = attr_zh
    if bullet_ids:
        hit["isBullet"] = True
        hit["bulletIds"] = [to_int(b) for b in sorted(set(bullet_ids), key=int)][:8]
    if no_fp:
        hit["noFp"] = True
    if empty or self_ally:
        hit["noDamage"] = True
    if self_ally:
        hit["selfOrAllyOnly"] = True
    if to_int(atk_row.get("isAddBaseAtk", "0")):
        hit["addBaseAtk"] = True
    over = to_int(atk_row.get("overwriteAttackElementCorrectId", "-1"), -1)
    if over != -1:
        # 参数表里存在悬空引用（本作 1001 火焰唾球的两段指向不存在的 AEC 行 1005）。
        # 消费方会照着 usage 去查 AttackElementCorrectParam 然后拿到空值，
        # 所以查不到的一律不写出这个字段，只在 caveats 里记一笔。
        if str(over) in aec_ids:
            hit["overrideAecId"] = over
        elif aec_dangling is not None:
            aec_dangling[over] += 1
    hit["source"] = "".join(sorted(sources))
    return hit


def hit_has_damage(hit: dict) -> bool:
    """对敌伤害段：motion / flat 非空，且没标 noDamage（noDamage 含只打自己 / 队友的 selfOrAllyOnly 行）。
    counts 里所有 *Damaging 计数都按它算。"""
    return bool(hit.get("motion") or hit.get("flat")) and not hit.get("noDamage")


# hits[] 元素的键顺序（build_hit 的写出顺序，再接后面各步追加的标记）；后补字段时按它重排，保证输出稳定可读
HIT_KEY_ORDER = ("atkId", "ctx", "ctxKind", "ctxZh", "label", "labelZh", "motion", "flat", "poise", "poiseMv",
                 "stamina", "staminaMv", "attribute", "attributeZh", "isBullet", "bulletIds", "noFp", "noFpSource",
                 "fpBoth", "noDamage", "selfOrAllyOnly", "addBaseAtk", "overrideAecId", "source",
                 "noVariant", "notInvoked", "notInvokedReason")


def set_hit_fields(hit: dict, **fields) -> None:
    """原地给 hit 加字段并按 HIT_KEY_ORDER 重排（保持对象身份，别处持有的引用不失效）。"""
    merged = dict(hit, **fields)
    rank = {k: i for i, k in enumerate(HIT_KEY_ORDER)}
    ordered = sorted(merged.items(), key=lambda kv: rank.get(kv[0], len(rank)))
    hit.clear()
    hit.update(ordered)


NO_FP_LABEL_PREFIX = "无FP版"   # 与 label_to_zh() 给行名带 "No FP" 的段加的前缀一致


class HitCollector:
    """按 atkId 去重地累积某个战技 / 法术的分段命中。"""

    def __init__(self) -> None:
        self.by_atk: dict[str, dict] = {}

    def add(self, atk_id: str, label: str, source: str, bullet_id: str | None = None,
            ctx: str = "") -> None:
        entry = self.by_atk.setdefault(
            atk_id, {"label": "", "labelRank": 9, "ctx": "", "ctxRank": 9,
                     "sources": set(), "bullets": []})
        # 行名匹配（n）给出的段标签最可信，其次子弹行名（b），锚点/兜底不带标签。
        rank = {"n": 0, "b": 1}.get(source, 9)
        if label and rank < entry["labelRank"]:
            entry["label"] = label
            entry["labelRank"] = rank
        if ctx and rank < entry["ctxRank"]:
            entry["ctx"] = ctx
            entry["ctxRank"] = rank
        entry["sources"].add(source)
        if bullet_id:
            entry["bullets"].append(bullet_id)


# ------------------------------------------------------------------------ 主流程
def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--params", type=Path, default=DEFAULT_PARAMS)
    ap.add_argument("--msg", type=Path, default=DEFAULT_MSG)
    ap.add_argument("--out", type=Path, default=DEFAULT_OUT)
    ap.add_argument("--pretty", action="store_true", help="indent=1 输出（默认紧凑）")
    ap.add_argument("--invoked", type=Path, default=DEFAULT_INVOKED,
                    help="extract_tae.py 的 raw/tae/invoked.json；缺失时不做 TAE 核实（counts.taeVerified=false）")
    ap.add_argument("--sp-enum", type=Path, default=DEFAULT_SP_ENUM, help="Paramdex SP_EFFECT_TYPE.json（可选）")
    ap.add_argument("--no-tae", action="store_true", help="跳过 TAE 核实（等同 invoked.json 缺失，保持 A 阶段口径）")
    args = ap.parse_args()

    weapons_raw = read_param(args.params, "EquipParamWeapon")
    arts_raw = read_param(args.params, "SwordArtsParam")
    magic_raw = read_param(args.params, "Magic")
    atk_raw = read_param(args.params, "AtkParam_Pc")
    bullet_raw = read_param(args.params, "Bullet")
    behavior_raw = read_param(args.params, "BehaviorParam_PC")
    # 只用来校验 hits[].overrideAecId 是否真的存在（本表本身不收录，见 usage.本数据集的边界）
    aec_ids = frozenset(row["ID"] for row in read_param(args.params, "AttackElementCorrectParam"))
    # v3：局内武器的战技池
    arts_table_raw = read_param(args.params, "SwordArtsTableParam")
    custom_raw = read_param(args.params, "EquipParamCustomWeapon")
    item_table_raw = read_param(args.params, "ItemTableParam")
    lot_raw = (read_param(args.params, "ItemLotParam_map")
               + read_param(args.params, "ItemLotParam_enemy"))
    shop_raw = read_param(args.params, "ShopLineupParam")
    # v3 修订：法术的可施放口径（施法器 custom 行的 magicTableId_1 / _2 → MagicTableParam 池）
    magic_table_raw = read_param(args.params, "MagicTableParam")

    wep_zh = read_fmg(args.msg, "zhocn", "item", "WeaponName")
    wep_en = read_fmg(args.msg, "engus", "item", "WeaponName")
    arts_zh = read_fmg(args.msg, "zhocn", "item", "ArtsName")
    arts_en = read_fmg(args.msg, "engus", "item", "ArtsName")
    magic_zh = read_fmg(args.msg, "zhocn", "item", "MagicName")
    magic_en = read_fmg(args.msg, "engus", "item", "MagicName")
    npc_zh = read_fmg(args.msg, "zhocn", "item", "NpcName")
    npc_en = read_fmg(args.msg, "engus", "item", "NpcName")

    # -------- 行名方括号里的 ctx → (kind, 中文) ----------------------------------
    # 解析顺序必须是「先类别、再角色、最后武器名」：
    #   * Twinblade / Dagger / Spear / Halberd / Greatsword / Hammer / Flail / Greataxe
    #     这 8 个词既是 WEP_TYPE 枚举名又是某把武器的名字；
    #   * Scythe 只是武器 19000000「大镰刀」的名字，但 Paramdex 拿它指 Reaper（镰）类别。
    # 先查武器名会把类别译成具体武器名（旧版就把 Scythe 译成了「大镰刀」）。
    ctx_category: dict[str, tuple[str, str]] = {}
    for _en, _zh in WEP_TYPE_ZH.values():
        ctx_category.setdefault(norm_key(_en), (_en, _zh))
    ctx_category.update(CTX_ALIAS_ZH)          # 别名覆盖（含 Scythe → 镰）

    ctx_chr: dict[str, str] = dict(CHR_CTX_ZH)
    for _id, _en in npc_en.items():
        if npc_zh.get(_id):
            ctx_chr.setdefault(norm_key(_en), npc_zh[_id])

    ctx_weapon: dict[str, str] = {}
    for _id, _en in wep_en.items():
        if wep_zh.get(_id):
            ctx_weapon.setdefault(norm_key(_en), wep_zh[_id])

    def classify_ctx(ctx: str, is_chr: bool) -> tuple[str, str]:
        """ctx 原文 → (ctxKind, ctxZh)。ctxKind ∈ category / chr / weapon / ""（未知）。"""
        key = norm_key(ctx)
        if not key:
            return ("", "")
        if is_chr:
            return ("chr", ctx_chr.get(key, ctx))
        if key in ctx_category:
            return ("category", ctx_category[key][1])
        if key in ctx_chr:
            return ("chr", ctx_chr[key])
        if key in ctx_weapon:
            return ("weapon", ctx_weapon[key])
        return ("", "")

    atk_by_id = {row["ID"]: row for row in atk_raw}
    bullets_by_id = {row["ID"]: row for row in bullet_raw}
    behaviors_by_var: dict[str, list[dict]] = defaultdict(list)
    for row in behavior_raw:
        behaviors_by_var[row["variationId"]].append(row)

    # BehaviorParam_PC 的行 ID 规律：ID = base + variationId * 1000 + behaviorJudgeId，
    # base 是「行为组」前缀（100000000 普通攻击 / 300000000 战技 / 900000000 武器专属等）。
    # 同一个 (base, judgeId) 上，variationId = 武器 behaviorVariationId 的行优先，
    # 没有就落到 variationId = 0 的通用行——这正是游戏挑动作的方式，
    # 也是判断「这把武器的战技到底用哪一套 AtkParam」的唯一权威依据。
    behavior_by_key: dict[tuple[int, int, int], dict] = {}
    behavior_judges_by_ref: dict[str, set[tuple[int, int]]] = defaultdict(set)
    for row in behavior_raw:
        try:
            bid = int(row["ID"])
            var = int(row.get("variationId", "0"))
            judge = int(row.get("behaviorJudgeId", "0"))
        except (TypeError, ValueError):
            continue
        base = bid - var * 1000 - judge
        behavior_by_key[(base, var, judge)] = row
        behavior_judges_by_ref[row.get("refId", "-1")].add((base, judge))

    # ---------------------------------------------------------------- weapons
    weapons: list[dict] = []
    skill_to_weapons: dict[str, list[int]] = defaultdict(list)
    unnamed_weapon_type: Counter = Counter()
    # 没有 WeaponName 文本的 EquipParamWeapon 行（例如 100000–101000 这批 wepType 3、rarity 0、
    # Paramdex 行名为空的测试行，它们把 swordArtsParamId 指到 210 风暴刃）一律不收录：
    # 这里记下它们对战技的引用，只用于 fieldNotes 说明「为什么 v2 里 210 看着有引用却没有武器」。
    unnamed_skill_refs: Counter = Counter()
    unnamed_rows = 0
    for row in weapons_raw:
        wid = to_int(row["ID"])
        name_zh = wep_zh.get(wid)
        name_en = wep_en.get(wid)
        if not name_zh and not name_en:
            unnamed_rows += 1
            ref_arts = to_int(row.get("swordArtsParamId", "-1"), -1)
            if ref_arts > 0:
                unnamed_skill_refs[ref_arts] += 1
            continue
        wep_type = to_int(row.get("wepType", "0"))
        type_en, type_zh = WEP_TYPE_ZH.get(wep_type, ("unknown", "unknown"))
        if type_en == "unknown":
            unnamed_weapon_type[wep_type] += 1
        rarity = to_int(row.get("rarity", "0"))
        rarity_en, rarity_zh = RARITY_ZH.get(rarity, ("unknown", "unknown"))
        attack_base = {el: to_num(row.get(WEP_ATK_FIELDS[el], "0")) for el in ELEMENTS}
        arts_id = to_int(row.get("swordArtsParamId", "-1"), -1)
        entry = {
            "id": wid,
            "nameZh": name_zh or name_en,
            "nameEn": name_en or name_zh,
            "wepType": wep_type,
            "wepTypeEn": type_en,
            "wepTypeZh": type_zh,
            "rarity": rarity,
            "rarityEn": rarity_en,
            "rarityZh": rarity_zh,
            "attackBase": {el: attack_base[el] for el in ELEMENTS if attack_base[el]},
            "staminaBase": to_num(row.get("attackBaseStamina", "0")),
            "correct": {k: to_num(row.get(f, "0")) for k, f in WEP_CORRECT_FIELDS.items()
                        if to_num(row.get(f, "0"))},
            "poiseDamageBase": to_num(row.get("saWeaponDamage", "0")),
            "swordArtsParamId": arts_id,
        }
        for src, key_zh in WEP_ATK_ATTR_FIELDS:
            val = to_int(row.get(src, "3"), 3)
            entry[src] = val
            entry[key_zh] = ATK_ATTR_ZH.get(val, ("unknown", "未知"))[1]
        entry |= {
            "attackElementCorrectId": to_int(row.get("attackElementCorrectId", "-1"), -1),
            "reinforceTypeId": to_int(row.get("reinforceTypeId", "0")),
        }
        behavior_var = row.get("behaviorVariationId", "0")
        weapons.append(entry)
        if arts_id > 0:
            skill_to_weapons[str(arts_id)].append(wid)
        entry["_behaviorVariationId"] = behavior_var  # 内部用，输出前删掉

    weapons.sort(key=lambda e: e["id"])
    weapon_ids_named = {str(w["id"]) for w in weapons}

    # ---------------------------------------------------- 局内武器的战技池（v3）
    # SwordArtsTableParam 的分组规则：**同一个 ID 的全部行 = 一个池**。
    #   * 表里 11896 行只有 841 个不同 ID（例如 ID 10000000 有 44 行、每行一个不同的 swordArtsId），
    #     与 AttachEffectTableParam（generate_buffs.py 的 pool_members，已对词条库 283 个成员验证）同一惯例；
    #   * EquipParamCustomWeapon.swordArtsTableId 的 497 个不同取值（-1 除外）**全部**等于某个表行 ID；
    #   * 带 "<类别>" 前缀的池（"<Dagger>" / "<Untyped Straight Sword>" …）只被 targetWeaponId 属于
    #     该类别的 custom 行引用，按「同 ID」分组后类别前缀与武器类别零冲突（按「连续行到下一个起点」分组则会
    #     把未被 custom 引用的 xx10 池并进来——那些池被 EquipParamWeapon.swordArtsTableId 单独引用，是独立的池）。
    # 详细证据与反证写在 PROVENANCE「战技池（v3）」。
    # 同一个池里同一个战技偶尔出现两行（例 50000000 刺剑池把 850 白影诱惑写了两遍、120000110 整池重复
    # 20 个战技），抽取时等于权重相加，所以这里按池内首次出现的顺序把权重累加成一项。
    pool_weights: dict[str, dict[int, int]] = defaultdict(dict)
    pool_dup_rows = 0
    for row in arts_table_raw:
        arts = to_int(row.get("swordArtsId", "-1"), -1)
        weight = to_int(row.get("chanceWeight", "0"))
        if arts <= 0 or weight <= 0:
            continue
        bucket = pool_weights[row["ID"]]
        if arts in bucket:
            pool_dup_rows += 1
        bucket[arts] = bucket.get(arts, 0) + weight
    pool_entries: dict[str, list[tuple[int, int]]] = {
        pid: list(bucket.items()) for pid, bucket in pool_weights.items()}

    # 「可达」的 custom 行：被 ItemTableParam（itemCategory=6）、ItemLotParam_map/_enemy
    # （lotItemCategory0N=6）或 ShopLineupParam（equipType=6）引用。三处引用到的 ID 全部是
    # EquipParamCustomWeapon 的行（实测 4165 / 453 / 1554 条引用全中），所以 6 = custom weapon。
    # 没有被任何一处引用的 custom 行（1288 行，多为 [Common] Longsword 这类早期测试行，
    # 例如 custom 10 把长剑配成 100 狮子斩、50000001–50000008 把混种大剑配成各种单一战技）不算来源。
    reachable_custom: set[str] = set()
    for row in item_table_raw:
        if row.get("itemCategory") == "6":
            reachable_custom.add(row.get("itemId", ""))
    for row in lot_raw:
        for i in range(1, 9):
            if row.get(f"lotItemCategory0{i}") == "6":
                reachable_custom.add(row.get(f"lotItemId0{i}", ""))
    for row in shop_raw:
        if row.get("equipType") == "6":
            reachable_custom.add(row.get("equipId", ""))

    # (战技, 武器) → {池 ID: [权重, 引用该池的可达 custom 行数]}
    pool_pairs: dict[tuple[str, str], dict[str, list[int]]] = defaultdict(dict)
    custom_by_weapon: dict[str, list[tuple[int, int]]] = defaultdict(list)
    used_pools: set[str] = set()
    custom_stats: Counter = Counter()
    unreachable_pairs: set[tuple[str, str]] = set()
    for row in custom_raw:
        cid = row["ID"]
        target = row.get("targetWeaponId", "-1")
        table = row.get("swordArtsTableId", "-1")
        if cid not in reachable_custom:
            custom_stats["unreachable"] += 1
            if target in weapon_ids_named:
                for arts, _w in pool_entries.get(table, ()):
                    unreachable_pairs.add((str(arts), target))
            continue
        if target not in weapon_ids_named:
            custom_stats["reachableUnnamedTarget"] += 1
            continue
        custom_stats["reachable"] += 1
        custom_by_weapon[target].append((to_int(cid), to_int(table, -1)))
        if table == "-1":
            custom_stats["reachableFixedOnly"] += 1
            continue
        if table not in pool_entries:
            custom_stats["reachableEmptyPool"] += 1
            continue
        used_pools.add(table)
        for arts, weight in pool_entries[table]:
            slot = pool_pairs[(str(arts), target)].setdefault(table, [weight, 0])
            slot[1] += 1

    skill_to_pool_weapons: dict[str, set[int]] = defaultdict(set)
    weapon_pool_skills: dict[str, set[int]] = defaultdict(set)
    for (sid, wid), _tables in pool_pairs.items():
        skill_to_pool_weapons[sid].add(int(wid))
        weapon_pool_skills[wid].add(int(sid))
    # 只在未可达 custom 行里出现、可达行里没有的 (战技, 武器) 对（写进 coverage 说明）
    unreachable_only_pairs = sorted(
        (int(s), int(w)) for s, w in unreachable_pairs
        if (s, w) not in pool_pairs and int(w) not in skill_to_weapons.get(s, []))

    # EquipParamWeapon 自己也有一个 swordArtsTableId 列（指向不被任何 custom 行引用的 xx10 池，
    # 内容 = 同类别 xx00 全池，或「该属性池 ∪ Untyped 池」）。参数表里看不出它在本作何时生效
    # （局内掉落走 custom 行），所以不作为来源，只统计「若算上它会多出多少 (战技, 武器) 对 / 多少战技」。
    epw_table_pairs: set[tuple[int, int]] = set()
    for row in weapons_raw:
        if row["ID"] not in weapon_ids_named:
            continue
        for arts, _w in pool_entries.get(row.get("swordArtsTableId", "-1"), ()):
            epw_table_pairs.add((arts, int(row["ID"])))

    # ---------------------------------------------- 法术的施法器池（v3 修订：可施放口径）
    # 本作玩家能施放的法术 = 局内施法器（手杖 / 圣印记）custom 行的 magicTableId_1 / magicTableId_2
    # 指向的 MagicTableParam 池里的 magicId。MagicTableParam 与 SwordArtsTableParam 同一惯例：
    # **同一个 ID 的全部行 = 一个池**，每行 magicId + chanceWeight（>0 才算池成员）。可达性沿用上面
    # 战技池的 reachable_custom（ItemTableParam / ItemLotParam / ShopLineupParam 引用）。
    # Magic 表里有名字、却不在任何可达施法器池里的行不收进 spells（本版本只有 8100 / 8101「风暴管束者」：
    # 全部参数表都没有引用 Magic 8100 / 8101，是本体把风暴管束者做成 Magic 的残留行；本作的风暴管束者是
    # 战技 SwordArtsParam 1200），见 coverage.spellsNotCastable 与 PROVENANCE「法术可施放口径」。
    magic_pool_weights: dict[str, dict[int, int]] = defaultdict(dict)
    magic_zero_rows: list[tuple[str, int, str]] = []    # (池 ID, magicId, 行名)：chanceWeight=0 的行
    magic_pool_dup_rows = 0
    magic_refs_any: dict[int, set[str]] = defaultdict(set)   # magicId → 出现它的池（任意权重）
    for row in magic_table_raw:
        magic_id = to_int(row.get("magicId", "-1"), -1)
        weight = to_int(row.get("chanceWeight", "0"))
        if magic_id <= 0:
            continue
        magic_refs_any[magic_id].add(row["ID"])
        if weight <= 0:
            magic_zero_rows.append((row["ID"], magic_id, row.get("Name", "")))
            continue
        bucket = magic_pool_weights[row["ID"]]
        if magic_id in bucket:
            magic_pool_dup_rows += 1
        bucket[magic_id] = bucket.get(magic_id, 0) + weight
    magic_pool_entries: dict[str, list[tuple[int, int]]] = {
        pid: list(bucket.items()) for pid, bucket in magic_pool_weights.items()}

    # (magicId, 武器) → {池 ID: [权重, 引用该池的可达 custom 行数]}；一行的两个槽指向同一个池时只算一行
    spell_pool_pairs: dict[tuple[int, int], dict[str, list[int]]] = defaultdict(dict)
    custom_magic_by_weapon: dict[str, list[tuple[int, int, int]]] = defaultdict(list)
    used_magic_pools: set[str] = set()
    magic_custom_stats: Counter = Counter()
    magic_tables_any_custom: set[str] = set()     # 任意 custom 行（含不可达）引用到的池
    for row in custom_raw:
        tables = [row.get(f, "-1") or "-1" for f in ("magicTableId_1", "magicTableId_2")]
        if all(t == "-1" for t in tables):
            continue
        magic_tables_any_custom.update(t for t in tables if t != "-1")
        cid = row["ID"]
        target = row.get("targetWeaponId", "-1")
        if cid not in reachable_custom:
            magic_custom_stats["unreachable"] += 1
            continue
        if target not in weapon_ids_named:
            magic_custom_stats["reachableUnnamedTarget"] += 1
            continue
        magic_custom_stats["reachable"] += 1
        custom_magic_by_weapon[target].append((to_int(cid), to_int(tables[0], -1), to_int(tables[1], -1)))
        for table in dict.fromkeys(t for t in tables if t != "-1"):
            if table not in magic_pool_entries:
                magic_custom_stats["reachableEmptyPool"] += 1
                continue
            used_magic_pools.add(table)
            for magic_id, weight in magic_pool_entries[table]:
                slot = spell_pool_pairs[(magic_id, int(target))].setdefault(table, [weight, 0])
                slot[1] += 1
    castable_magic: set[int] = {m for m, _w in spell_pool_pairs}
    spell_caster_weapons: dict[int, set[int]] = defaultdict(set)
    for magic_id, wid in spell_pool_pairs:
        spell_caster_weapons[magic_id].add(wid)
    # 可达施法器池里 chanceWeight=0 的行：抽不到，不算池成员。逐行记下它所在的槽，以及引用该池的 custom 行
    # 另一个槽的池里有没有这个法术（实测多数是「第 2 槽池把第 1 槽的法术置 0」）。
    magic_zero_in_used: list[dict] = []
    for pid, magic_id, name in magic_zero_rows:
        if pid not in used_magic_pools:
            continue
        users = [row for row in custom_raw if row["ID"] in reachable_custom
                 and pid in (row.get("magicTableId_1"), row.get("magicTableId_2"))]
        slots = sorted({1 if row.get("magicTableId_1") == pid else 2 for row in users})
        other_pools = sorted({(row.get("magicTableId_2") if row.get("magicTableId_1") == pid else row.get("magicTableId_1"))
                              for row in users} - {"-1", ""}, key=int)
        magic_zero_in_used.append({
            "pool": int(pid), "magicId": magic_id, "rowName": name, "slots": slots,
            "otherSlotPools": [int(p) for p in other_pools],
            "inOtherSlotPool": bool(other_pools) and all(
                dict(magic_pool_entries.get(p, ())).get(magic_id, 0) > 0 for p in other_pools),
        })

    def caster_sources(magic_id: int) -> list[dict]:
        """spells[].casterSources：与 casterWeaponIds 同序，每把施法器一项（结构仿 skills[].weaponSources，
        法术没有「固定」来源，所以只有 pool）：pool = [[magicTableId, chanceWeight, customRows], ...]，按池 ID 升序；
        customRows = 这把武器的可达 custom 行里 magicTableId_1 或 _2 指向该池的行数，具体行见
        weapons[该武器].customMagicTables。"""
        out = []
        for wid in sorted(spell_caster_weapons.get(magic_id, ())):
            tables = spell_pool_pairs[(magic_id, wid)]
            out.append({"id": wid,
                        "pool": [[to_int(t), w, n] for t, (w, n) in sorted(tables.items(), key=lambda kv: int(kv[0]))]})
        return out

    def weapon_sources(sid: str) -> list[dict]:
        """skills[].weaponSources：与 weaponIds 同序，每把武器一项。
        fixed=true  → EquipParamWeapon.swordArtsParamId 就是这个战技（v2 的唯一来源）；
        pool        → [[swordArtsTableId, 该战技在池里的 chanceWeight, 引用该池的可达 custom 行数], ...]，
                      按池 ID 升序；具体是哪几行见 weapons[].customWeapons 里 table 相同的那些。"""
        fixed_ids = set(skill_to_weapons.get(sid, []))
        out = []
        for wid in sorted(fixed_ids | skill_to_pool_weapons.get(sid, set())):
            item: dict = {"id": wid}
            if wid in fixed_ids:
                item["fixed"] = True
            tables = pool_pairs.get((sid, str(wid)))
            if tables:
                item["pool"] = [[to_int(t), w, n] for t, (w, n) in sorted(tables.items(), key=lambda kv: int(kv[0]))]
            out.append(item)
        return out

    # ---------------------------------------------------------------- skills
    skills: list[dict] = []
    skill_index = NameIndex()
    skill_rows: dict[str, dict] = {}
    for row in arts_raw:
        text_id = to_int(row.get("textId", "-1"), -1)
        name_zh = arts_zh.get(text_id)
        name_en = arts_en.get(text_id)
        if not name_zh and not name_en:
            continue
        sid = row["ID"]
        skill_rows[sid] = row
        internal = strip_bracket_prefix(row.get("Name", ""))
        hint = paren_hint(internal)
        internal_core = strip_paren_suffix(internal)
        if name_en:
            skill_index.add(sid, name_en)
        if internal_core:
            skill_index.add(sid, internal_core)
        if hint:
            skill_index.add_hint(sid, hint, specific=True)
        for wid in skill_to_weapons.get(sid, []):
            skill_index.add_hint(sid, wep_en.get(wid, ""))
        skills.append({
            "id": to_int(sid),
            "nameZh": name_zh or name_en,
            "nameEn": name_en or name_zh,
            "sparring": bool(to_int(row.get("enableSparringGrounds", "0"))),
            # v3：固定引用 ∪ 局内战技池。命中归属（行名消歧的武器提示、路线 w 的「唯一武器」判定）
            # 仍只用固定引用 skill_to_weapons，保证 hits 与 v2 完全一致。
            "weaponIds": sorted(set(skill_to_weapons.get(sid, []))
                                | skill_to_pool_weapons.get(sid, set())),
            "weaponSources": weapon_sources(sid),
            "_rowId": sid,
        })

    # ---------------------------------------------------------------- spells
    # 先按「有 MagicName 的全部 Magic 行」建条目与名字索引、做命中归属（与 v3 之前完全相同，
    # 保证其它法术的 hits 不因少了两个名字键而变化），落地 hits 之后再按可施放口径过滤（见 finalize 之后）。
    spells: list[dict] = []
    spell_index = NameIndex()
    spell_rows: dict[str, dict] = {}
    for row in magic_raw:
        mid = to_int(row["ID"])
        name_zh = magic_zh.get(mid)
        name_en = magic_en.get(mid)
        if not name_zh and not name_en:
            continue
        rid = row["ID"]
        spell_rows[rid] = row
        internal = strip_bracket_prefix(row.get("Name", ""))
        if name_en:
            spell_index.add(rid, name_en)
        if internal:
            spell_index.add(rid, strip_paren_suffix(internal))
        kind_num = to_int(row.get("ezStateBehaviorType", "0"))
        kind = MAGIC_KIND.get(kind_num, f"unknown({kind_num})")
        spells.append({
            "id": mid,
            "nameZh": name_zh or name_en,
            "nameEn": name_en or name_zh,
            "kind": kind,
            "kindZh": MAGIC_KIND_ZH.get(kind, "未知"),
            "mp": to_int(row.get("mp", "0")),
            "sparring": bool(to_int(row.get("enableSparringGrounds", "0"))),
            # v3 修订：能携带它的施法器（基础武器，经 custom 行 targetWeaponId）与每把的池来源
            "casterWeaponIds": sorted(spell_caster_weapons.get(mid, ())),
            "casterSources": caster_sources(mid),
            "_rowId": rid,
        })

    skill_hits: dict[str, HitCollector] = defaultdict(HitCollector)
    spell_hits: dict[str, HitCollector] = defaultdict(HitCollector)
    stats = Counter()
    ambiguous: list[str] = []

    def assign(index: NameIndex, collector: dict[str, HitCollector], key: str, ctx: str,
               atk_id: str, label: str, source: str, bullet_id: str | None,
               row_name: str) -> None:
        targets = index.resolve(key, ctx)
        if len(targets) > 1:
            ambiguous.append(f"{row_name} → {targets}")
        for target in targets:
            collector[target].add(atk_id, label, source, bullet_id, ctx)

    # ---- 先把每行 AtkParam_Pc 自己的行名解析一遍 ------------------------------
    # atk_self[atkId]：这一行自己的 ctx / 段标签 / 匹配到的技能名键。
    #   ctx 一律以「这一行自己的行名」为准——旧版只有行名匹配（n）路线填 ctx，
    #   锚点（a）/ 兜底（w）/ 子弹（b）落下来的段 ctx 是空的，于是
    #   1166 回旋斩的 '[AoW Polearm] Spinning Slash' 被当成了不分武器的通用段。
    # row_groups[(kind, ctx, 名字键)]：同一套动作的整组行，锚点命中其中一行时整组一起收。
    atk_self: dict[str, dict] = {}
    row_groups: dict[tuple[str, str, str], list[str]] = defaultdict(list)
    for row in atk_raw:
        parsed = parse_row_name(row.get("Name", ""))
        if not parsed:
            continue
        kind, ctx, rest, is_chr = parsed
        index = skill_index if kind == "aow" else spell_index
        # 先看 "A/B/C - label" 这种被多个战技共用的行名，再退回单名最长前缀匹配
        matches = index.match_shared(rest)
        if not matches:
            one = index.match(rest)
            matches = [one] if one else []
        atk_self[row["ID"]] = {
            "kind": kind, "ctx": ctx, "chr": is_chr,
            "label": matches[0][1] if matches else "",
            "keys": {k for k, _ in matches},
        }
        for key, _label in matches:
            row_groups[(kind, ctx, key)].append(row["ID"])

    # 路线 n：AtkParam_Pc 行名
    for row in atk_raw:
        info = atk_self.get(row["ID"])
        if not info:
            continue
        if not info["keys"]:
            stats["atkRowsUnmatched"] += 1
            continue
        kind = info["kind"]
        index = skill_index if kind == "aow" else spell_index
        collector = skill_hits if kind == "aow" else spell_hits
        for key in sorted(info["keys"]):
            assign(index, collector, key, info["ctx"], row["ID"], info["label"],
                   "n", None, row["Name"])
        stats["atkRowsMatched"] += 1

    def anchor_add(collector: HitCollector, entry_keys: set[str], kind: str,
                   atk_id: str, source: str) -> None:
        """锚点 / 兜底路线落段：除了锚点那一行，把「同一套动作的整组行」一并收进来。
        SwordArtsParam.atkParamId 只指向连段的第 1 段（例如龙戟的 1166 回旋斩只指到
        300000240），整组 6 段里其余 5 段没有别的路线能找到。只有当锚点行的技能名
        正好就是本战技的名字时才展开，避免把别的战技的整组动作抓过来。"""
        collector.add(atk_id, "", source)
        info = atk_self.get(atk_id)
        if not info or info["kind"] != kind:
            return
        for key in info["keys"] & entry_keys:
            for sibling in row_groups.get((kind, info["ctx"], key), []):
                collector.add(sibling, atk_self[sibling]["label"], source)

    # 路线 b：Bullet 行名（AoW / Sorcery / Incantation），再展开子弹链
    for row in bullet_raw:
        parsed = parse_row_name(row.get("Name", ""))
        if not parsed:
            continue
        kind, ctx, rest, _is_chr = parsed
        index = skill_index if kind == "aow" else spell_index
        collector = skill_hits if kind == "aow" else spell_hits
        matches = index.match_shared(rest)
        if not matches:
            hit = index.match(rest)
            if not hit:
                continue
            matches = [hit]
        for bid in bullet_chain(bullets_by_id, row["ID"]):
            atk_id = bullets_by_id[bid].get("atkId_Bullet", "-1")
            if atk_id not in atk_by_id:
                continue
            for key, label in matches:
                assign(index, collector, key, ctx, atk_id,
                       label if bid == row["ID"] else "", "b", bid, row["Name"])
        stats["bulletRowsMatched"] += 1

    # 路线 a / r / b：SwordArtsParam.atkParamId、Magic.atkParamId 与 Magic.refId
    for sid, row in skill_rows.items():
        anchor = row.get("atkParamId", "-1")
        if anchor in atk_by_id:
            anchor_add(skill_hits[sid], skill_index.keys_of.get(sid, set()), "aow", anchor, "a")

    for rid, row in spell_rows.items():
        spell_keys = spell_index.keys_of.get(rid, set())
        anchor = row.get("atkParamId", "-1")
        if anchor in atk_by_id:
            kind = atk_self.get(anchor, {}).get("kind", "sorcery")
            anchor_add(spell_hits[rid], spell_keys, kind, anchor, "a")
        for i in range(1, 11):
            ref = row.get(f"refId{i}", "-1")
            cat = to_int(row.get(f"refCategory{i}", "0"))
            if not ref or ref in ("-1", ""):
                continue
            if cat == 0 and ref in atk_by_id:
                kind = atk_self.get(ref, {}).get("kind", "sorcery")
                anchor_add(spell_hits[rid], spell_keys, kind, ref, "r")
            elif cat == 1 and ref in bullets_by_id:
                for bid in bullet_chain(bullets_by_id, ref):
                    atk_id = bullets_by_id[bid].get("atkId_Bullet", "-1")
                    if atk_id in atk_by_id:
                        spell_hits[rid].add(atk_id, "", "b", bid)

    # 路线 w：行名/锚点都没给出命中的战技，若只有唯一武器引用它，
    # 用该武器 behaviorVariationId 的「专属战技槽」（behaviorJudgeId ∈ [900,950)）兜底。
    weapon_by_id = {str(w["id"]): w for w in weapons}
    for skill in skills:
        sid = skill["_rowId"]
        if skill_hits[sid].by_atk:
            continue
        wids = skill_to_weapons.get(sid, [])
        if len(wids) != 1:
            continue
        wep = weapon_by_id.get(str(wids[0]))
        if not wep:
            continue
        for brow in behaviors_by_var.get(wep["_behaviorVariationId"], []):
            judge = to_int(brow.get("behaviorJudgeId", "0"))
            if not (900 <= judge < 950):
                continue
            ref_type = to_int(brow.get("refType", "0"))
            ref_id = brow.get("refId", "-1")
            if ref_type == 0 and ref_id in atk_by_id:
                anchor_add(skill_hits[sid], skill_index.keys_of.get(sid, set()),
                           "aow", ref_id, "w")
            elif ref_type == 1 and ref_id in bullets_by_id:
                for bid in bullet_chain(bullets_by_id, ref_id):
                    atk_id = bullets_by_id[bid].get("atkId_Bullet", "-1")
                    if atk_id in atk_by_id:
                        skill_hits[sid].add(atk_id, "", "w", bid)

    # ---------------------------------------------------------------- 落地 hits
    aec_dangling: Counter = Counter()
    foreign_drops: list[str] = []

    def finalize(entries: list[dict], collectors: dict[str, HitCollector],
                 index: NameIndex) -> tuple[int, list[str]]:
        with_hits = 0
        missing: list[str] = []
        for entry in entries:
            rid = entry["_rowId"]
            raw = collectors.get(rid)
            entry_keys = index.keys_of.get(rid, set())
            hits: list[dict] = []
            if raw:
                for atk_id in sorted(raw.by_atk, key=int):
                    info = raw.by_atk[atk_id]
                    label = info["label"]
                    ctx, is_chr = info["ctx"], False
                    # 这一段属于哪套动作，以它自己的 AtkParam_Pc 行名为准；
                    # 行名没有方括号时才退回发现它的那条路线（子弹行名）给的 ctx。
                    self_info = atk_self.get(atk_id)
                    if self_info:
                        ctx, is_chr = self_info["ctx"], self_info["chr"]
                        if self_info["label"] and not label:
                            label = self_info["label"]
                        # 跨条目误配：这一行的行名点名的是**另一个**已知战技 / 法术
                        # （SwordArtsParam.atkParamId / Magic.atkParamId 里的残留锚点，
                        # 以及子弹链顺带捞到的别家的段）。行名匹配路线 n 永远不会把
                        # 这种行分给本条目——n 路线按行名匹配到的名字键去分发——
                        # 所以「行名匹配到了名字键、但与本条目的名字键完全不相交」
                        # 就是误配的充要判据，直接丢弃。
                        if self_info["keys"] and not (self_info["keys"] & entry_keys):
                            foreign_drops.append(
                                f'{entry["id"]} {entry["nameZh"]} ← {atk_id} '
                                f'{atk_by_id[atk_id].get("Name", "")}'
                                f'（source={"".join(sorted(info["sources"]))}）')
                            continue
                    no_fp = bool(re.search(r"\bNo\s*FP\b", label, flags=re.I))
                    ctx_kind, ctx_zh = classify_ctx(ctx, is_chr)
                    hit = build_hit(atk_by_id[atk_id], label, no_fp, info["sources"],
                                    info["bullets"], ctx, ctx_zh, ctx_kind,
                                    aec_ids, aec_dangling)
                    if hit:
                        hits.append(hit)
            entry["hits"] = hits
            del entry["_rowId"]
            if hits:
                with_hits += 1
            else:
                missing.append(f'{entry["id"]} {entry["nameZh"]}／{entry["nameEn"]}')
        return with_hits, missing

    skills_with_hits, skills_missing = finalize(skills, skill_hits, skill_index)
    finalize(spells, spell_hits, spell_index)

    # ---- 法术只收「可施放」的（v3 修订）------------------------------------------
    # 命中归属已经按全部有名 Magic 行做完（其它法术的 hits 与修订前逐段相同），这里再把不在任何
    # 可达施法器池里的行拿掉，记进 coverage.spellsNotCastable（附原因），不再出现在 spells[]。
    skill_by_name_zh: dict[str, list[dict]] = defaultdict(list)
    for sk in skills:
        skill_by_name_zh[sk["nameZh"]].append(sk)
    spells_not_castable: list[dict] = []
    for entry in spells:
        if entry["id"] in castable_magic:
            continue
        pools_any = sorted(magic_refs_any.get(entry["id"], ()), key=int)
        same_name_skills = [sk for sk in skill_by_name_zh.get(entry["nameZh"], []) if sk["weaponIds"]]
        if not pools_any:
            reason = "MagicTableParam 没有任何行（任何池、任何权重）引用这个 magicId，所以没有施法器能带它"
            reason += MAGIC_NOT_CASTABLE_EVIDENCE.get(entry["id"], "")
        elif not set(pools_any) & magic_tables_any_custom:
            reason = f"只出现在没有任何 custom 行引用的 MagicTableParam 池 {pools_any} 里"
        else:
            reason = f"只出现在不可达 custom 行引用的 MagicTableParam 池 {pools_any} 里"
        if same_name_skills:
            reason += "；本作同名的是战技 " + "、".join(
                f'SwordArtsParam {sk["id"]}「{sk["nameZh"]}」（{len(sk["weaponIds"])} 把武器）' for sk in same_name_skills)
        spells_not_castable.append({
            "id": entry["id"], "nameZh": entry["nameZh"], "nameEn": entry["nameEn"], "kind": entry["kind"],
            "hits": len(entry["hits"]), "atkIds": [h["atkId"] for h in entry["hits"]],
            "magicTablePools": [int(p) for p in pools_any],
            "sameNameSkillIds": [sk["id"] for sk in same_name_skills],
            "reason": reason,
        })
    spells_named_total = len(spells)
    spells = [entry for entry in spells if entry["id"] in castable_magic]
    for entry in spells:
        assert entry["casterWeaponIds"], entry["id"]
    spells_with_hits = sum(1 for entry in spells if entry["hits"])
    spells_missing = [f'{entry["id"]} {entry["nameZh"]}／{entry["nameEn"]}' for entry in spells if not entry["hits"]]
    # 可施放池里出现、但 Magic 表里没有名字（或根本没有这一行）、因而不在 spells 里的 magicId：本版本应为空
    castable_unnamed = sorted(castable_magic - {entry["id"] for entry in spells})
    # 没有 MagicName 文本、从来不收的 Magic 行（90、4641、4642、8000–8023、999999999 这类）
    unnamed_magic_ids = [to_int(r["ID"]) for r in magic_raw
                         if not magic_zh.get(to_int(r["ID"])) and not magic_en.get(to_int(r["ID"]))]

    # ---------------------------------------------------- 每把武器用哪一套动作
    # 通用战技（战吼 / 野蛮咆哮 / 回旋斩 / 盲击…）在参数里同时存在「不分武器的默认套」
    # 和「每个动作组各一套」，它们是同一招的互斥变体而不是可叠加的分段：
    # 按「ctx 等于武器名 或 等于类别名 或 ctx 缺失」取并集会把两套一起算进去，
    # 段数与总伤害直接翻倍。这里用 BehaviorParam_PC 把每把武器实际会用到的
    # AtkParam 行解出来，写成 skills[].variants，武器侧再给一个 skillVariant 下标。
    bullet_atk_cache: dict[str, frozenset[str]] = {}

    def bullet_atks(bullet_id: str) -> frozenset[str]:
        cached = bullet_atk_cache.get(bullet_id)
        if cached is None:
            out = set()
            for bid in bullet_chain(bullets_by_id, bullet_id):
                aid = bullets_by_id[bid].get("atkId_Bullet", "-1")
                if aid in atk_by_id:
                    out.add(aid)
            cached = frozenset(out)
            bullet_atk_cache[bullet_id] = cached
        return cached

    # atkId → 哪些 (base, behaviorJudgeId) 会打出它
    judges_by_atk: dict[str, set[tuple[int, int]]] = defaultdict(set)
    for row in behavior_raw:
        try:
            bid = int(row["ID"])
            var = int(row.get("variationId", "0"))
            judge = int(row.get("behaviorJudgeId", "0"))
        except (TypeError, ValueError):
            continue
        base = bid - var * 1000 - judge
        ref_type = to_int(row.get("refType", "0"))
        ref = row.get("refId", "-1")
        if ref_type == 0 and ref in atk_by_id:
            judges_by_atk[ref].add((base, judge))
        elif ref_type == 1 and ref in bullets_by_id:
            for aid in bullet_atks(ref):
                judges_by_atk[aid].add((base, judge))

    def behavior_row(base: int, var: int, judge: int, legacy: bool = False) -> dict | None:
        """按游戏的回退顺序取行为行：武器自己的 variationId → 向下取整到百位的「族」variationId
        → 0 号通用行。v3 起补上中间这一级（v2 只有「自己 → 0」）。证据（PROVENANCE「战技池（v3）」）：
          * 1200 风暴管束者的 10 套角色动作挂在 variationId 0/100/500/900/1100/1102/1800/2100/2300/4100 上，
            正好是各渡夜者专属武器 behaviorVariationId（117/503/900/1100/1102/1800/2151/2304/4100，
            追踪者 300 无专属行 → 0 = Default 套）取整到百位的值，与 Paramdex 行名的角色名逐一对上；
            没有这一级时女爵 / 学者 / 复仇者 / 无赖会被算成追踪者的 Default 套，执行者等 5 把一套都解不出。
          * 加上这一级后，每个战技里「同一武器类别只落进一套动作」无一例外（self_check 断言）；两级回退时
            650 野蛮咆哮、651 战吼、110 盲击等都有同类别武器被拆进默认套与类别套两边，例如 1400 的斧走
            Small Weapon、1406/1407 的斧却落到 0 号行的 Large Weapon（实测个数写进 caveats）。"""
        if legacy:  # v2 口径，只用来统计 v3 改了哪些 (战技, 武器) 对的选段
            return behavior_by_key.get((base, var, judge)) or behavior_by_key.get((base, 0, judge))
        return (behavior_by_key.get((base, var, judge))
                or (behavior_by_key.get((base, var // 100 * 100, judge)) if var % 100 else None)
                or behavior_by_key.get((base, 0, judge)))

    def resolve_by_behavior(var: int, judges: set[tuple[int, int]], pool: set[str],
                            legacy: bool = False) -> tuple[set[str], dict[str, set[tuple[int, bool]]]]:
        """返回 (解出的 atkId 集合, {atkId: {(解出它的行为组 base, 该行是否专属行 variationId≠0)}})。
        第二项只在消歧时用：见 variants 循环里的「只看有专属行的行为组」。"""
        out: set[str] = set()
        prov: dict[str, set[tuple[int, bool]]] = defaultdict(set)
        for base, judge in judges:
            row = behavior_row(base, var, judge, legacy)
            if not row:
                continue
            ref_type = to_int(row.get("refType", "0"))
            ref = row.get("refId", "-1")
            got: set[str] = set()
            if ref_type == 0:
                if ref in pool:
                    got = {ref}
            elif ref_type == 1 and ref in bullets_by_id:
                got = bullet_atks(ref) & pool
            out |= got
            own = to_int(row.get("variationId", "0")) != 0
            for aid in got:
                prov[aid].add((base, own))
        return out, prov

    def choose_ctx(wep: dict, skill_id: int, pool_ctx: set[str],
                   chr_ctx: frozenset[str] = frozenset()) -> str | None:
        """BehaviorParam_PC 分不出来时，按「武器名 → 武器名里的渡夜者名（v3）→ 同名基础武器 → 手工表
        → 武器类别 → 唯一的具名套 → 默认套」的顺序单选一套（**不取并集**）。"""
        for cand in (norm_key(wep["nameEn"]),):
            for ctx in pool_ctx:
                if ctx and norm_key(ctx) == cand:
                    return ctx
        # v3：角色套（"[AoW - Ironeye] Storm Ruler"）按专属武器英文名里的角色名选
        # （"Ironeye's Bow" → Ironeye）。只有 1200 风暴管束者有角色套。
        name_tokens = set(norm_key(wep["nameEn"]).split())
        for ctx in sorted(pool_ctx & chr_ctx):
            if norm_key(ctx) in name_tokens:
                return ctx
        # 亲和 / 强化变体：武器 ID 的百位是亲和偏移，行名里用的是基础 ID 那把的名字
        # （例：18100800 魔力罗蕾塔的战镰 → 18100000 罗蕾塔的战镰）
        base_id = wep["id"] - wep["id"] % 1000
        base_wep = weapon_by_id.get(str(base_id))
        if base_wep and base_id != wep["id"]:
            base_key = norm_key(base_wep["nameEn"])
            for ctx in pool_ctx:
                if ctx and norm_key(ctx) == base_key:
                    return ctx
        manual = CTX_MANUAL_BY_SKILL.get(skill_id, {}).get(wep["wepType"])
        if manual is not None and manual in pool_ctx:
            return manual
        type_key = norm_key(wep["wepTypeEn"])
        for ctx in pool_ctx:
            if ctx and norm_key(ctx) == type_key:
                return ctx
        named = sorted({c for c in pool_ctx if c})
        if len(named) == 1:
            return named[0]
        if "" in pool_ctx:
            return ""
        return None

    variant_stats: Counter = Counter()
    variant_gaps: list[str] = []
    # v2 口径（两级回退、无「只看有专属行的行为组」、无角色名选套）解出来的段，与 v3 不同的 (战技, 武器) 对
    legacy_changed: list[tuple[int, int, bool, str, str]] = []
    legacy_sel: dict[tuple[int, int], frozenset[str]] = {}

    def legacy_pick(wep: dict, skill_id: int, var: int, judges: set[tuple[int, int]],
                    pool: set[str], ctx_of: dict[str, str]) -> set[str]:
        atks, _prov = resolve_by_behavior(var, judges, pool, legacy=True) if judges else (set(), {})
        named = {ctx_of[a] for a in atks if ctx_of[a]}
        if not atks or len(named) > 1:
            candidates = atks or pool
            chosen = choose_ctx(wep, skill_id, {ctx_of[a] for a in candidates})
            if chosen is None:
                return set()
            atks = {a for a in candidates if ctx_of[a] == chosen}
        return atks

    # ---- TAE 核实（v3 第二部分）：行为表解出的段，还要被该战技的动画事件真正调用才留在 variants 里 ----
    # 判定逻辑在同目录的 verify_skill_hits.py（TaeVerifier，车道 B 的规律 1–10），这里逐 (战技, 武器) 调用，
    # 两边同一套 TAE 索引、三级回退与互斥动画套规则。invoked.json 缺失（或 --no-tae）时保持 A 阶段口径。
    tae = None
    vsh = None
    tae_skip_reason = ""
    if args.no_tae:
        tae_skip_reason = "--no-tae"
    elif not args.invoked.exists():
        tae_skip_reason = f"找不到 {args.invoked}（先跑 extract_tae.py）"
    else:
        sys.path.insert(0, str(HERE))
        import verify_skill_hits as vsh  # noqa: E402  同目录脚本，只用标准库
        tae = vsh.TaeVerifier(args.invoked, args.params, args.sp_enum)
    # 行为表层（TAE 核实前）每个 (战技, 武器) 解出的段；self_check 与「构成变化」统计都要用
    pre_sel: dict[tuple[int, int], frozenset[str]] = {}
    tae_removed: dict[int, dict[str, dict[str, list[int]]]] = defaultdict(lambda: defaultdict(lambda: defaultdict(list)))
    tae_kept_special: dict[int, dict[str, dict[str, list[int]]]] = defaultdict(lambda: defaultdict(lambda: defaultdict(list)))
    tae_detail: dict[tuple[int, str, str], str] = {}        # (战技, atkId, status) → 中文说明（取第一次遇到的）
    tae_blocks: dict[int, Counter] = defaultdict(Counter)   # 战技 → {"选中的套（依据）": 武器数}
    tae_unmatched: list[str] = []
    tae_empty: list[str] = []
    tae_checks = 0
    # (战技, atkId) → {"fp" / "noFp" / "neutral": {战技 TAE 动画号}}：这段在「留下它的武器」上由哪一侧的动画调用
    # （verify_skill_hits 规律 8：4xxxx 个位 0–4 带 FP、5–9 无 FP）。用来补标行名没写 "No FP" 的无 FP 段。
    tae_fp: dict[tuple[int, str], dict[str, set[int]]] = defaultdict(lambda: defaultdict(set))
    skill_tae_of: dict[int, str] = {}

    for skill in skills:
        if not skill["hits"] or not skill["weaponIds"]:
            continue
        pool = {str(h["atkId"]) for h in skill["hits"]}
        ctx_of = {str(h["atkId"]): h.get("ctx", "") for h in skill["hits"]}
        chr_ctx = frozenset(h["ctx"] for h in skill["hits"] if h.get("ctxKind") == "chr")
        judges: set[tuple[int, int]] = set()
        for aid in pool:
            judges |= judges_by_atk.get(aid, set())
        groups: dict[frozenset[str], dict] = {}
        selections: list[tuple[int, str, int, set[str]]] = []   # (武器, via, behaviorVariationId, 行为表解出的段)
        for wid in skill["weaponIds"]:
            wep = weapon_by_id.get(str(wid))
            if not wep:
                continue
            var = to_int(wep.get("_behaviorVariationId", "0"))
            atks, prov = resolve_by_behavior(var, judges, pool) if judges else (set(), {})
            via = "behavior"
            named = {ctx_of[a] for a in atks if ctx_of[a]}
            own_bases = {b for got in prov.values() for b, own in got if own}
            if len(named) > 1 and own_bases:
                # 同一批段被不止一个行为组（base）引用时，只看「这把武器在其中有专属行」的那些组：
                # 1200 风暴管束者的 Default 套除了 base 400000000，还在 500000000 挂了一份 0 号行
                # （judge 200/220/230/240），女爵的短剑（variationId 117 → 100）只在 400000000 有专属行，
                # 500000000 的 0 号行不该把追踪者的 Default 套也算进来。
                # 只在「具名套 > 1」时才介入，所以不歧义的 (战技, 武器) 对不受影响。
                narrowed = {a for a in atks if any(b in own_bases for b, _own in prov[a])}
                narrowed_named = {ctx_of[a] for a in narrowed if ctx_of[a]}
                if narrowed and len(narrowed_named) == 1:
                    atks, named = narrowed, narrowed_named
                    variant_stats["behavior:narrowedToOwnBase"] += 1
            if not atks or len(named) > 1:
                # 行为表分不出来（103 回旋斩的 4 套动作全挂在 variationId=0 上），
                # 或者这把武器压根没接上行为表：退回按 ctx 单选一套。
                candidates = atks or pool
                chosen = choose_ctx(wep, skill["id"], {ctx_of[a] for a in candidates}, chr_ctx)
                if chosen and chosen in chr_ctx:
                    # 角色套整套取：铁之眼的弓（variationId 4100）的 No FP 段挂在 4100 上，
                    # 带 FP 的四段却挂在 variationId 5000（= 铁之眼箭矢 50030000 的 5050 取整）上，
                    # 弓的子弹行为按箭矢的 variationId 解——所以按弓自己的 4100 解会落到 Default 套。
                    candidates = {a for a in pool if ctx_of[a] == chosen}
                if chosen is None:
                    variant_gaps.append(
                        f'{wid} {wep["nameZh"]} ← {skill["id"]} {skill["nameZh"]}')
                    continue
                atks = {a for a in candidates if ctx_of[a] == chosen}
                via = "ctx"
            if not atks:
                variant_gaps.append(f'{wid} {wep["nameZh"]} ← {skill["id"]} {skill["nameZh"]}')
                continue
            legacy_atks = legacy_pick(wep, skill["id"], var, judges, pool, ctx_of)
            legacy_sel[(skill["id"], wid)] = frozenset(legacy_atks)
            if legacy_atks != atks:
                def set_ctx(ids: set[str]) -> str:
                    names = sorted({ctx_of[a] for a in ids if ctx_of[a]})
                    return "/".join(names) if names else ("默认套" if ids else "解不出")
                legacy_changed.append((skill["id"], wid, wep["swordArtsParamId"] == skill["id"],
                                       set_ctx(legacy_atks), set_ctx(atks)))
            selections.append((wid, via, var, atks))
            pre_sel[(skill["id"], wid)] = frozenset(atks)
            variant_stats[via] += 1
            is_fixed = wep["swordArtsParamId"] == skill["id"]
            variant_stats[f'{via}:{"fixed" if is_fixed else "poolOnly"}'] += 1
        if not selections:
            continue
        skill["_preCovered"] = {int(a) for _w, _v, _var, atks in selections for a in atks}

        # TAE 核实：逐武器判定（同 var / 动作组 / 类别 / 段集合的武器共用一次结果）
        final: dict[int, set[str]] = {wid: atks for wid, _v, _var, atks in selections}
        if tae is not None:
            sctx = tae.skill_context(skill["id"], pool)
            skill_tae_of[skill["id"]] = f'a{sctx["skillTae"]}' if sctx["skillTae"] is not None else None
            checked: dict[int, tuple[dict, dict | None]] = {}
            cache: dict[tuple, tuple[dict, dict | None]] = {}
            for wid, _via, var, atks in selections:
                wrow = tae.wep(wid)
                wtype = weapon_by_id[str(wid)]["wepType"]
                key = (var, frozenset(tae.weapon_taes([wid])),
                       to_int(wrow["wepmotionCategory"]) if wrow else -1, wtype, frozenset(atks))
                if key not in cache:
                    cache[key] = tae.check(sctx, atks, var, [wid], {wtype})
                    tae_checks += 1
                checked[wid] = cache[key]
            matched = sctx["taeFound"] and any(
                r["status"] in vsh.MATCHED_STATUSES for res, _i in checked.values() for r in res.values())
            if not matched:
                # 战技动画匹配不到（弓系战技只有锚点段、或战技 TAE 缺失）：hits 与 variants 一律不动，只打标记
                skill["taeUnmatched"] = True
                statuses = Counter(r["status"] for res, _i in checked.values() for r in res.values())
                tae_unmatched.append(
                    f'{skill["id"]} {skill["nameZh"]}（战技 TAE a{sctx["skillTae"]}'
                    f'{"" if sctx["taeFound"] else " 缺失"}；各段判定 {dict(statuses)}）')
            else:
                for wid, _via, var, atks in selections:
                    res, info = checked[wid]
                    kept = {a for a in atks if res[a]["status"] in vsh.KEEP_STATUSES}
                    if not kept:
                        # 这把武器一段都留不下：不敢断定它打不出这个战技，保持行为表口径并记下来
                        tae_empty.append(f'{wid} {weapon_by_id[str(wid)]["nameZh"]} ← {skill["id"]} {skill["nameZh"]}'
                                         f'（{dict(Counter(r["status"] for r in res.values()))}）')
                        continue
                    final[wid] = kept
                    if info:
                        tae_blocks[skill["id"]][f'{info["chosenBlock"]}（{info["blockChoice"].split("（")[0]}）'] += 1
                    for a in kept:
                        for branch, anims in vsh.fp_evidence(res[a], sctx["roar"],
                                                             info["chosenBlock"] if info else None).items():
                            tae_fp[(skill["id"], a)][branch] |= anims
                    for a in atks:
                        st = res[a]["status"]
                        if a not in kept:
                            tae_removed[skill["id"]][a][st].append(wid)
                            tae_detail.setdefault((skill["id"], a, st), vsh.reason_text(res[a]))
                        elif st not in vsh.MATCHED_STATUSES:
                            tae_kept_special[skill["id"]][a][st].append(wid)
                            tae_detail.setdefault((skill["id"], a, st), (
                                "；".join(res[a].get("gates") or []) if st == "conditional"
                                else "SpEffect " + "、".join(f'{x["spEffectId"]} {x["name"]}' for x in res[a].get("spEffects", []))
                                if st == "spEffect" else "；".join(res[a].get("noJudgeReason") or []) or st))

        for wid, via, _var, _atks in selections:
            key = frozenset(final[wid])
            group = groups.setdefault(key, {"weaponIds": [], "via": via})
            group["weaponIds"].append(wid)
            if via == "ctx":
                group["via"] = "ctx"
        variants = []
        for key, group in sorted(groups.items(), key=lambda kv: min(int(a) for a in kv[0])):
            named = sorted({ctx_of[a] for a in key if ctx_of[a]})
            entry: dict = {"atkIds": sorted(to_int(a) for a in key)}
            if len(named) == 1:
                entry["ctx"] = named[0]
                sample = next(h for h in skill["hits"]
                              if h.get("ctx") == named[0] and str(h["atkId"]) in key)
                if "ctxKind" in sample:
                    entry["ctxKind"] = sample["ctxKind"]
                if "ctxZh" in sample:
                    entry["ctxZh"] = sample["ctxZh"]
            entry["via"] = group["via"]
            entry["weaponIds"] = sorted(group["weaponIds"])
            index = len(variants)
            for wid in group["weaponIds"]:
                wep = weapon_by_id[str(wid)]
                # skillVariants 覆盖该武器可能出现的每个战技；skillVariant 仍只给固定战技（v2 语义）
                wep.setdefault("skillVariants", {})[str(skill["id"])] = index
                if wep["swordArtsParamId"] == skill["id"]:
                    wep["skillVariant"] = index
            variants.append(entry)
        skill["variants"] = variants

    for wep in weapons:
        wep.pop("_behaviorVariationId", None)

    # ---- 武器侧：skillIds / skillVariants / customWeapons（v3） ---------------
    skill_ids_known = {s["id"] for s in skills}
    for i, wep in enumerate(weapons):
        wid = str(wep["id"])
        ids = set(weapon_pool_skills.get(wid, set()))
        if wep["swordArtsParamId"] in skill_ids_known:
            ids.add(wep["swordArtsParamId"])
        ordered: dict = {}
        for key, value in wep.items():
            if key in ("skillVariant", "skillVariants"):
                continue
            ordered[key] = value
            if key == "swordArtsParamId":
                ordered["skillIds"] = sorted(ids)
        if "skillVariant" in wep:
            ordered["skillVariant"] = wep["skillVariant"]
        if wep.get("skillVariants"):
            ordered["skillVariants"] = {k: wep["skillVariants"][k]
                                        for k in sorted(wep["skillVariants"], key=int)}
        if custom_by_weapon.get(wid):
            ordered["customWeapons"] = [[c, t] for c, t in sorted(custom_by_weapon[wid])]
        # v3 修订：施法器的可达 custom 行与两个法术池槽（spells[].casterSources 回溯用）
        if custom_magic_by_weapon.get(wid):
            ordered["customMagicTables"] = [[c, t1, t2] for c, t1, t2 in sorted(custom_magic_by_weapon[wid])]
        weapons[i] = ordered
    weapon_by_id = {str(w["id"]): w for w in weapons}

    # ---- 标记「本作没有任何武器会打出」的动作套 ------------------------------
    # 参数表里一个通用战技往往存着比本作实际用得到的更多的动作套
    # （例如 650 野蛮咆哮存了 '[AoW Straight Sword] Barbaric Roar' 一整套，
    # 但本作没有任何直剑把 650 配为战技）。这些段行名确实点名了本战技，数据没错，
    # 但按 usage 的选段算法（variants → atkIds）永远取不到。
    # 给它们打上 noVariant=true，方便页面/体积裁剪时区分，不改变既有字段语义。
    # noVariant 看的是「行为表层」的覆盖（TAE 核实之前）：TAE 核实移除的段另标 notInvoked，两者互斥。
    no_variant_hits = 0
    no_variant_damaging = 0
    for skill in skills:
        covered: set[int] = skill.pop("_preCovered", set())
        if not skill.get("variants"):
            continue
        for hit in skill["hits"]:
            if hit["atkId"] not in covered:
                hit["noVariant"] = True
                no_variant_hits += 1
                if hit_has_damage(hit):
                    no_variant_damaging += 1

    # ---- TAE 核实的标记与清单 -------------------------------------------------------
    # hits[].notInvoked：行为表给至少一把武器解出了这段，但 TAE 核实后在**所有**这些武器上都被移除；
    # 只在部分武器上被移除的段不标，逐武器结论看 variants，清单见 diagnostics.taeVerification.partiallyRemoved。
    # 本版本这类段全部来自互斥动画套，例：二连斩 Large Weapon 套 300000185–196 只留给大剑 / 大曲剑，
    # 在其余武器上记 exclusiveBlock 移除。（野蛮咆哮 300000957/959/967/969 不是这种：三级回退下锤族 var 1100
    # 解到自己的 301100957，没有任何武器会打 var 0 的这 4 行，所以它们在全部 141 把武器上都被移除、标 notInvoked。）
    reason_order = list(vsh.STATUS_ORDER) if vsh else []
    removed_list: list[dict] = []
    partial_list: list[dict] = []
    kept_special_list: list[dict] = []
    hits_not_invoked = 0
    hits_not_invoked_damaging = 0
    weapon_hits_removed = 0
    skills_by_id_tmp = {s["id"]: s for s in skills}
    for sid, per_atk in sorted(tae_removed.items()):
        skill = skills_by_id_tmp[sid]
        kept_any = {a for v in skill.get("variants", ()) for a in v["atkIds"]}
        by_atk = {h["atkId"]: h for h in skill["hits"]}
        for a, by_status in sorted(per_atk.items(), key=lambda kv: int(kv[0])):
            hit = by_atk[int(a)]
            reason = min(by_status, key=reason_order.index)
            wids = sorted({w for ws in by_status.values() for w in ws})
            weapon_hits_removed += len(wids)
            rec = {"skillId": sid, "nameZh": skill["nameZh"], "atkId": int(a)}
            if hit.get("label"):
                rec["label"] = hit["label"]
            if hit.get("ctx"):
                rec["ctx"] = hit["ctx"]
            rec["damaging"] = hit_has_damage(hit)
            rec["reasons"] = {st: len(ws) for st, ws in sorted(by_status.items(), key=lambda kv: reason_order.index(kv[0]))}
            rec["reasonZh"] = tae_detail[(sid, a, reason)]
            if int(a) in kept_any:
                rec["keptOnWeapons"] = sum(len(v["weaponIds"]) for v in skill["variants"] if int(a) in v["atkIds"])
                rec["removedOnWeapons"] = len(wids)
                rec["removedWeaponSample"] = wids[:5]
                partial_list.append(rec)
            else:
                hit["notInvoked"] = True
                hit["notInvokedReason"] = reason
                hits_not_invoked += 1
                if rec["damaging"]:
                    hits_not_invoked_damaging += 1
                rec["notInvokedReason"] = reason
                rec["weapons"] = len(wids)
                rec["weaponSample"] = wids[:5]
                removed_list.append(rec)
    for sid, per_atk in sorted(tae_kept_special.items()):
        skill = skills_by_id_tmp[sid]
        for a, by_status in sorted(per_atk.items(), key=lambda kv: int(kv[0])):
            for st, ws in by_status.items():
                kept_special_list.append({"skillId": sid, "nameZh": skill["nameZh"], "atkId": int(a), "status": st,
                                          "weapons": len(ws), "detail": tae_detail[(sid, a, st)]})

    # ---- TAE 核实：带 FP / 无 FP 分支（verify_skill_hits 规律 8） ---------------------------
    # hits[].noFp 原先只看行名里的 "No FP"。很多战技的无 FP 段行名没写（风暴刃 300000411–413 = a659 的
    # 40005/40015/40025，狩猎巨人 301700915 = a616 的 40005），于是和带 FP 段一起被默认勾选、相加。
    # 这里按「留下这段的武器上，调用它的战技 TAE 动画在哪一侧」补标：
    #   只被无 FP 版动画（4xxxx 个位 5–9）调用 → noFp=true + noFpSource="tae"，labelZh 前补「无FP版」；
    #   带 FP 版（或不分 FP 的 3xxxx / 吼叫 R2）动画与无 FP 版动画都调用 → fpBoth=true（两侧共用，无论开关在哪侧都该计入）；
    #   行名写了 "No FP" 却被带 FP 版动画调用 → 记进 noFpConflicts（规律 8 的反例；本版本为空，self_check 断言）。
    # 没有动画依据的段（spEffect / noJudge）与 taeUnmatched 的战技保持行名口径。
    no_fp_tae: list[dict] = []
    fp_both_list: list[dict] = []
    no_fp_conflicts: list[str] = []
    for skill in skills:
        if tae is None or skill.get("taeUnmatched"):
            continue
        for hit in skill["hits"]:
            ev = tae_fp.get((skill["id"], str(hit["atkId"])))
            if not ev:
                continue
            branches = set(ev)
            anims = {b: sorted(ev[b]) for b in ("fp", "noFp", "neutral") if ev.get(b)}
            rec = {"skillId": skill["id"], "nameZh": skill["nameZh"], "skillTae": skill_tae_of.get(skill["id"]),
                   "atkId": hit["atkId"], "damaging": hit_has_damage(hit), "anims": anims}
            if branches == {"noFp"}:
                if not hit.get("noFp"):
                    label_zh = hit.get("labelZh", "")
                    set_hit_fields(hit, noFp=True, noFpSource="tae",
                                   labelZh=f"{NO_FP_LABEL_PREFIX} {label_zh}" if label_zh else NO_FP_LABEL_PREFIX)
                    no_fp_tae.append(rec)
            elif "noFp" in branches:
                if hit.get("noFp"):
                    no_fp_conflicts.append(f'{skill["id"]} {skill["nameZh"]} {hit["atkId"]}（行名 No FP，动画 {anims}）')
                else:
                    set_hit_fields(hit, fpBoth=True)
                    fp_both_list.append(rec)
            elif hit.get("noFp") and "fp" in branches:
                no_fp_conflicts.append(f'{skill["id"]} {skill["nameZh"]} {hit["atkId"]}（行名 No FP，动画 {anims}）')
    no_fp_tae_damaging = sum(1 for r in no_fp_tae if r["damaging"])

    skills.sort(key=lambda e: e["id"])
    spells.sort(key=lambda e: e["id"])

    total_hits = sum(len(e["hits"]) for e in skills) + sum(len(e["hits"]) for e in spells)
    atk_id_uses: Counter = Counter()
    for entry in skills + spells:
        for hit in entry["hits"]:
            atk_id_uses[hit["atkId"]] += 1
    shared_atk_rows = sum(1 for v in atk_id_uses.values() if v > 1)
    total_variants = sum(len(e.get("variants", ())) for e in skills)
    weapons_with_variant = sum(1 for w in weapons if "skillVariant" in w)

    # usage.选段 里那两个数字一律实测，避免改了归组逻辑后文字漂移：
    #   ctx_union_dup —— 该武器的战技同时存在「ctx 缺失的默认套」与「ctx == 自己 wepTypeEn 的类别套」，
    #                    按 ctx 取并集会把两套一起算进去（段数与伤害翻倍）；
    #   ctx_pick_miss —— 旧的「ctx == 武器名 → ctx == wepTypeEn → ctx 缺失」单选口径一段都取不到
    #                    （动作组别名 Small Weapon / Large Weapon / Polearm 不在 WEP_TYPE 里）。
    skills_by_id = {s["id"]: s for s in skills}
    ctx_union_dup = 0
    ctx_pick_miss = 0
    for wep in weapons:
        skill = skills_by_id.get(wep["swordArtsParamId"])
        if not skill or not skill["hits"]:
            continue
        ctxs = {h.get("ctx", "") for h in skill["hits"]}
        if "" in ctxs and wep["wepTypeEn"] in ctxs:
            ctx_union_dup += 1
        if not ({"", wep["wepTypeEn"], wep["nameEn"]} & ctxs):
            ctx_pick_miss += 1

    # 有多少段的伤害类型要回武器上取（attribute = 253 / 252）
    wep_attr_hits = sum(1 for e in skills + spells for h in e["hits"]
                        if h["attribute"] in ("WeaponAtkAttribute", "WeaponAtkAttribute2"))

    # ---- 选段口径变化（v3 三级回退等）的实测 ----------------------------------------
    # 「同一战技里同一武器类别被拆进不同动作套」的战技：v3 口径应为 0（self_check 断言），
    # v2 口径（两级回退）分别按「只看固定武器」与「v3 的全部武器」统计。
    wep_type_of = {w["id"]: w["wepType"] for w in weapons}
    fixed_pair_set = {(sk["id"], src["id"]) for sk in skills for src in sk["weaponSources"] if src.get("fixed")}

    def split_skills(selection: dict[tuple[int, int], frozenset], only: set | None = None) -> list[int]:
        seen: dict[tuple[int, int], set[frozenset]] = defaultdict(set)
        for (sid, wid), atks in selection.items():
            if only is not None and (sid, wid) not in only:
                continue
            seen[(sid, wep_type_of[wid])].add(atks)
        return sorted({sid for (sid, _t), sets in seen.items() if len(sets) > 1})

    v3_sel: dict[tuple[int, int], frozenset] = {}
    for sk in skills:
        for v in sk.get("variants", ()):
            for wid in v["weaponIds"]:
                v3_sel[(sk["id"], wid)] = frozenset(str(a) for a in v["atkIds"])
    # 「同一武器类别只落进一套动作」是行为表层的规律，按 TAE 核实前的选段统计；
    # TAE 核实后同一类别可以因动作组 TAE / 互斥动画套不同而分到不同 variant（另计，写进 diagnostics）
    split_v3 = split_skills(pre_sel)
    split_after_tae = split_skills(v3_sel)
    split_legacy_fixed = split_skills(legacy_sel, fixed_pair_set)
    split_legacy_all = split_skills(legacy_sel)
    legacy_changed_fixed = [c for c in legacy_changed if c[2]]
    legacy_changed_fixed_by_skill = Counter(c[0] for c in legacy_changed_fixed)
    legacy_changed_fixed_text = "、".join(
        f'{sid} {skills_by_id[sid]["nameZh"]} {n} 把' for sid, n in sorted(legacy_changed_fixed_by_skill.items()))

    # ---- v3 战技池统计 ---------------------------------------------------------
    def skill_label(skill: dict) -> str:
        return f'{skill["id"]} {skill["nameZh"]}／{skill["nameEn"]}'

    pair_fixed = sum(1 for sk in skills for src in sk["weaponSources"] if src.get("fixed"))
    pair_pool = sum(1 for sk in skills for src in sk["weaponSources"] if src.get("pool"))
    pair_both = sum(1 for sk in skills for src in sk["weaponSources"]
                    if src.get("fixed") and src.get("pool"))
    skills_without_weapons = [skill_label(sk) for sk in skills if not sk["weaponIds"]]
    skills_without_fixed = [skill_label(sk) for sk in skills
                            if not any(src.get("fixed") for src in sk["weaponSources"])]
    skills_pool_only = [f'{skill_label(sk)}（{len(sk["weaponIds"])} 把）' for sk in skills
                        if sk["weaponIds"] and not any(src.get("fixed") for src in sk["weaponSources"])]
    skills_pool_only_with_hits = sum(1 for sk in skills if sk["hits"] and sk["weaponIds"]
                                     and not any(src.get("fixed") for src in sk["weaponSources"]))
    weapons_with_pool = sum(1 for w in weapons if str(w["id"]) in weapon_pool_skills)
    weapons_with_skill_variants = sum(1 for w in weapons if w.get("skillVariants"))
    pool_payload = {str(t): [[a, w] for a, w in pool_entries[t]] for t in sorted(used_pools, key=int)}
    pool_entry_count = sum(len(v) for v in pool_payload.values())
    # v3 修订：法术池
    magic_pool_payload = {str(t): [[m, w] for m, w in magic_pool_entries[t]] for t in sorted(used_magic_pools, key=int)}
    magic_pool_entry_count = sum(len(v) for v in magic_pool_payload.values())
    caster_type_counts = Counter(weapon_by_id[w]["wepTypeZh"] for w in custom_magic_by_weapon)
    all_pairs = {(sk["id"], wid) for sk in skills for wid in sk["weaponIds"]}
    epw_extra_pairs = {pr for pr in epw_table_pairs if pr not in all_pairs and pr[0] in skill_ids_known}
    epw_extra_skills = {a for a, _w in epw_extra_pairs} - {sk["id"] for sk in skills if sk["weaponIds"]}
    no_variant_by_skill: Counter = Counter()
    no_variant_example: dict[int, str] = {}
    for sk in skills:
        for hit in sk["hits"]:
            if hit.get("noVariant"):
                no_variant_by_skill[sk["id"]] += 1
                no_variant_example.setdefault(sk["id"], hit.get("ctx", ""))
    no_variant_top = "、".join(
        f'{sid} {skills_by_id[sid]["nameZh"]} {n} 段'
        + (f'（ctx "{no_variant_example[sid]}"）' if no_variant_example[sid] else "（默认套）")
        for sid, n in no_variant_by_skill.most_common(4))

    # ---- TAE 核实统计 ------------------------------------------------------------
    tae_verified = tae is not None
    # fieldNotes.notInvoked 里「只在部分武器上打不出」的例子按数据现算（self_check 另断言它成立）：
    # 二连斩的 Large Weapon 套只留给它自己那一套的武器，其余武器按互斥动画套移除。
    partial_example = ""
    ex_rows = [r for r in partial_list if r["skillId"] == 112 and r.get("ctx") == "Large Weapon"]
    if ex_rows:
        ex_first = ex_rows[0]
        ex_types = sorted({weapon_by_id[str(w)]["wepType"] for v in skills_by_id[112].get("variants", ())
                           if ex_first["atkId"] in v["atkIds"] for w in v["weaponIds"]})
        partial_example = (
            f'例：{skills_by_id[112]["nameZh"]} {ex_rows[0]["atkId"]}–{ex_rows[-1]["atkId"]}（Large Weapon 套 {len(ex_rows)} 段）'
            f'只留给 {" / ".join(WEP_TYPE_ZH[t][1] for t in ex_types)}（{ex_first["keptOnWeapons"]} 把），'
            f'在另 {ex_first["removedOnWeapons"]} 把武器上按互斥动画套（exclusiveBlock）移除；'
            "野蛮咆哮 300000957/959/967/969 不属于这种——三级回退下选到这 4 行 var 0 通用行的 141 把武器（大剑 / 特大剑 / 大斧 / 大锤 / 矛…）的 R2 动画只发 3956/3958/3966/3968，没有任何武器会打出它们，"
            "它们在全部选到它们的武器上都被移除、标了 notInvoked")
    hits_self_or_ally = sum(1 for e in skills + spells for h in e["hits"] if h.get("selfOrAllyOnly"))
    hits_self_or_ally_with_values = sum(1 for e in skills + spells for h in e["hits"]
                                        if h.get("selfOrAllyOnly") and (h.get("motion") or h.get("flat")))
    tae_skill_weapon_pairs = sum(1 for (sid, wid), atks in pre_sel.items()
                                 if not skills_by_id[sid].get("taeUnmatched")) if tae_verified else 0
    tae_pairs_changed = sum(1 for (sid, wid), atks in pre_sel.items()
                            if v3_sel.get((sid, wid)) is not None and v3_sel[(sid, wid)] != atks)
    tae_skills_changed = sorted({sid for (sid, wid), atks in pre_sel.items()
                                 if v3_sel.get((sid, wid)) is not None and v3_sel[(sid, wid)] != atks})
    tae_unmatched_ids = [sk["id"] for sk in skills if sk.get("taeUnmatched")]
    removed_reason_counts = Counter(r["notInvokedReason"] for r in removed_list)
    weapon_hits_removed_by_status: Counter = Counter()
    for per_atk in tae_removed.values():
        for by_status in per_atk.values():
            for st, ws in by_status.items():
                weapon_hits_removed_by_status[st] += len(ws)
    tae_meta = {}
    if tae_verified:
        im = tae.invoked_meta
        tae_meta = {"file": "raw/tae/invoked.json（extract_tae.py 生成，不入库）",
                    "source": im.get("source"), "packs": im.get("packs"), "stats": im.get("stats")}
    tae_diagnostics = {
        "verified": tae_verified,
        "skippedReason": tae_skip_reason or None,
        "invoked": tae_meta or None,
        "rules": ("战技 TAE = a(600 + SwordArtsParam.swordArtsType)；事件 judgeId = judge（base 1 亿）或 base/1 亿*1000 + judge；"
                  "BehaviorParam_PC 按三级回退（武器 var → 取整到百位 → 0）解行；吼叫类（650/651/1015）的 R2 段在武器动作组 "
                  "a(wepmotionCategory) 的 30600–30635 / 32600–32635 动画里；stateInfo≠0 是前置条件，187 玩家拿不到；"
                  "由 SpEffectParam.behaviorId 触发的行按 SpEffect 来源判；战技 TAE 的 4xxxx 动画按百位分套，一把武器只播一套。"
                  "详见 PROVENANCE「TAE 动画事件与命中核实」规律 1–10 与「命中段 TAE 核实（v3）」。"),
        "keepStatuses": list(vsh.KEEP_STATUSES) if vsh else [],
        "counts": {
            "skillWeaponPairsChecked": tae_skill_weapon_pairs,
            "distinctChecks": tae_checks,
            "skillWeaponPairsChanged": tae_pairs_changed,
            "skillsChanged": len(tae_skills_changed),
            "weaponHitsRemoved": weapon_hits_removed,
            "weaponHitsRemovedByStatus": dict(sorted(weapon_hits_removed_by_status.items(),
                                                     key=lambda kv: (vsh.STATUS_ORDER.index(kv[0]) if vsh else 0))),
            "hitsNotInvoked": hits_not_invoked,
            "hitsNotInvokedByReason": dict(removed_reason_counts),
            "hitsPartiallyRemoved": len(partial_list),
            "skillsTaeUnmatched": len(tae_unmatched_ids),
            "weaponsKeptUnfiltered": len(tae_empty),
            "hitsNoFpByTae": len(no_fp_tae),
            "hitsNoFpByTaeDamaging": no_fp_tae_damaging,
            "skillsNoFpByTae": len({r["skillId"] for r in no_fp_tae}),
            "hitsFpBoth": len(fp_both_list),
            "noFpConflicts": len(no_fp_conflicts),
        },
        "skillsChanged": [f'{sid} {skills_by_id[sid]["nameZh"]}' for sid in tae_skills_changed],
        "removedHits": removed_list,
        "partiallyRemoved": partial_list,
        "keptNonAnimation": kept_special_list,
        "exclusiveBlocks": [{"skillId": sid, "nameZh": skills_by_id[sid]["nameZh"],
                             "chosenBlockWeapons": dict(sorted(c.items()))}
                            for sid, c in sorted(tae_blocks.items())],
        "taeUnmatchedSkills": tae_unmatched,
        "weaponsKeptUnfiltered": tae_empty,
        "sameWeaponTypeSplitAfterTae": [f'{sid} {skills_by_id[sid]["nameZh"]}' for sid in split_after_tae],
        "noFpRule": ("战技 TAE 的 4xxxx 动画个位 0–4 = 带 FP 版、5–9 = 无 FP 版（带 FP 版动画号 + 5；本机全部战技 TAE 里个位 ≥ 5 的 "
                     "4xxxx 动画都有对应的带 FP 版）。一段在留下它的武器上只被无 FP 版动画调用 → hits[].noFp=true、"
                     "noFpSource=\"tae\"（下面 noFpFromTae，行名没写 No FP 的才列）；两侧（或不分 FP 的 3xxxx / 吼叫 R2 动画）"
                     "都调用 → fpBoth=true（fpBoth）。anims 按侧列出调用它的动画号：fp / noFp 在战技 TAE（skillTae）里，"
                     "neutral 是 3xxxx 或吼叫类战技在武器动作组 TAE 里的 R2 动画。行名写 No FP 却被带 FP 版动画调用的段列在 "
                     "noFpConflicts（本版本应为空）。"),
        "noFpFromTae": no_fp_tae,
        "fpBoth": fp_both_list,
        "noFpConflicts": no_fp_conflicts,
    }

    payload = {
        "schemaVersion": SCHEMA_VERSION,
        "gameVersion": GAME_VERSION,
        "dataVersion": DATA_VERSION,
        "generatedAt": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "schemaChangelog": SCHEMA_CHANGELOG,
        "sources": [
            {
                "name": "Elden Ring Nightreign regulation.bin",
                "detail": "本机 CrossOver Steam 安装，exe 1.3.3.0，容器版本号 10350000（1.03.5）；"
                          "由 dump_regulation.py 解出 raw/params/*.csv",
                "license": "游戏数据，版权归 FromSoftware / Bandai Namco",
                "use": "EquipParamWeapon / SwordArtsParam / Magic / AtkParam_Pc / Bullet / BehaviorParam_PC；"
                       "v3 起另读 EquipParamCustomWeapon / SwordArtsTableParam（局内战技池）与 "
                       "ItemTableParam / ItemLotParam_map / ItemLotParam_enemy / ShopLineupParam（只判 custom 行是否可达）；"
                       "v3 修订另读 MagicTableParam 与 custom 行的 magicTableId_1 / _2（法术的可施放口径）",
            },
            {
                "name": "Elden Ring Nightreign 游戏内文本（FMG）",
                "detail": "由 extract_msg.py 解出 raw/msg/{zhocn,engus}/item_dlc01/*.json，"
                          "基础 + _dlc01 合并",
                "license": "游戏数据，版权归 FromSoftware / Bandai Namco",
                "use": "WeaponName / ArtsName / MagicName 的简中与英文名",
            },
            {
                "name": "Smithbox Paramdex (NR)",
                "url": "https://github.com/vawser/Smithbox/tree/f5969c060cea240476e9dd4d6a64eafa9dbafaab/src/Smithbox.Data/Assets/PARAM/NR",
                "license": "MIT",
                "use": "字段定义、英文行名（Param Row Names）、枚举 WEP_TYPE / RARITY / "
                       "ATKPARAM_ATKATTR_TYPE / MAGIC_CATEGORY / BEHAVIOR_REF_TYPE",
            },
        ],
        "counts": {
            "weapons": len(weapons),
            "skills": len(skills),
            "skillsWithHits": skills_with_hits,
            "spells": len(spells),
            "spellsWithHits": spells_with_hits,
            "hits": total_hits,
            "uniqueAtkIds": len(atk_id_uses),
            "sharedAtkRows": shared_atk_rows,
            "variants": total_variants,
            "weaponsWithVariant": weapons_with_variant,
            "hitsWithoutVariant": no_variant_hits,
            "hitsWithoutVariantDamaging": no_variant_damaging,
            # v3：战技池
            "skillsWithWeapons": sum(1 for sk in skills if sk["weaponIds"]),
            "skillsWithFixedWeapons": len(skills) - len(skills_without_fixed),
            "skillsPoolOnly": len(skills_pool_only),
            "skillsPoolOnlyWithHits": skills_pool_only_with_hits,
            "weaponSkillPairs": len(all_pairs),
            "weaponSkillPairsFixed": pair_fixed,
            "weaponSkillPairsPool": pair_pool,
            "weaponSkillPairsBoth": pair_both,
            "weaponsWithPool": weapons_with_pool,
            "weaponsWithSkillVariants": weapons_with_skill_variants,
            "customWeaponRows": custom_stats["reachable"],
            "customWeaponRowsFixedOnly": custom_stats["reachableFixedOnly"],
            "customWeaponRowsUnreachable": custom_stats["unreachable"],
            "swordArtsPools": len(pool_payload),
            "swordArtsPoolEntries": pool_entry_count,
            # v3 修订：法术可施放口径
            "spellsNamed": spells_named_total,
            "spellsCastable": len(castable_magic),
            "spellsDropped": len(spells_not_castable),
            "magicPools": len(magic_pool_payload),
            "magicPoolEntries": magic_pool_entry_count,
            "magicPoolZeroWeightRows": len(magic_zero_in_used),
            "casterWeapons": len(custom_magic_by_weapon),
            "casterCustomRows": magic_custom_stats["reachable"],
            "casterCustomRowsUnreachable": magic_custom_stats["unreachable"],
            "spellWeaponPairs": len(spell_pool_pairs),
            # v3 第二部分：TAE 核实
            "taeVerified": tae_verified,
            "hitsNotInvoked": hits_not_invoked,
            "hitsNotInvokedDamaging": hits_not_invoked_damaging,
            "hitsPartiallyRemovedByTae": len(partial_list),
            "weaponHitsRemovedByTae": weapon_hits_removed,
            "skillWeaponPairsChangedByTae": tae_pairs_changed,
            "skillsChangedByTae": len(tae_skills_changed),
            "skillsTaeUnmatched": len(tae_unmatched_ids),
            # v3 审查修正：TAE 补标的无 FP 段、两侧共用段、只打自己 / 队友的段
            "hitsNoFpByTae": len(no_fp_tae),
            "hitsNoFpByTaeDamaging": no_fp_tae_damaging,
            "hitsFpBoth": len(fp_both_list),
            "hitsSelfOrAllyOnly": hits_self_or_ally,
            "hitsSelfOrAllyOnlyWithValues": hits_self_or_ally_with_values,
        },
        "coverage": {
            "note": "下面这些战技 / 法术在参数里找不到任何带数值的攻击行，"
                    "基本都是纯增益、闪避、格挡或只改弓箭的技能。",
            "skillsWithoutHits": skills_missing,
            "spellsWithoutHits": spells_missing,
            "spellsNotCastable": spells_not_castable,
            "spellsNotCastableNote":
                f"（v3 修订）spells[] 只收「可施放」的法术：magicId 出现在某个可达施法器 custom 行"
                f"（magicTableId_1 / magicTableId_2）指向的 MagicTableParam 池里、且 chanceWeight>0。"
                f"Magic 表里有 MagicName 的 {spells_named_total} 行中，{len(castable_magic)} 行可施放、收进 spells；"
                f"其余 {len(spells_not_castable)} 行（"
                + "、".join(f'{e["id"]} {e["nameZh"]}' for e in spells_not_castable)
                + "）列在 spellsNotCastable，附原因、原先归到它们的命中段（atkIds）与同名战技。"
                  "这些行修订前在 spells[] 里（带 hits），页面会把它们当成玩家法术参与排名；它们的 hits 不再输出。"
                  f"另有 {len(unnamed_magic_ids)} 行 Magic 没有 MagicName 文本（"
                + "、".join(str(i) for i in unnamed_magic_ids)
                + "），从来不收，也都不在任何可达施法器池里。",
            "hitsWithoutVariantNote":
                f"skills[].hits 是该战技在参数表里的**全部**动作套，"
                f"其中只有 variants 覆盖到的那些才会被本作的武器真正打出。"
                f"本版本有 {no_variant_hits} 段（其中 {no_variant_damaging} 段带 motion / flat）"
                f"不属于该战技的任何一个 variant，已逐段标 noVariant=true——"
                f"多为「参数表里存着某一套动作，但本作没有任何武器会用到它」"
                f"（通用战技的默认套在每个武器类别都有专属套时就用不到；"
                f"或者行名点名的武器在本作并不带这个战技，例如 120 转啊转的 'Carian Regal Scepter' 套——"
                f"33090000 卡利亚权杖在本作的战技是 10 无战技，也不在任何战技池里）。"
                f"（v2 只按固定引用算武器，曾把 650 野蛮咆哮的 '[AoW Straight Sword]' 套等也标成不可达，"
                f"v3 加上战技池与三级回退后它们都有武器打得出。）"
                f"这些段数据本身没错，但按 usage 的选段算法取不到；"
                f"想裁体积或只看「本作打得出的段」时按 noVariant 过滤即可。"
                f"注意：没有 variants 的战技（没有武器引用它）其 hits 不会被标记。"
                f"v3 按「固定 + 战技池」的武器重算后，剩下的大头是：{no_variant_top}。",
            "hitsNotInvokedNote": (
                f"（v3 TAE 核实）{hits_not_invoked} 段（其中带 motion / flat 的 {hits_not_invoked_damaging} 段）行为表给武器解得到、"
                f"但所有这些武器的动画都不调用，已从 variants 移除并标 notInvoked："
                + "；".join(f'{sid} {skills_by_id[sid]["nameZh"]} ' + "、".join(
                    f'{r["atkId"]}（{r["notInvokedReason"]}）' for r in removed_list if r["skillId"] == sid)
                    for sid in sorted({r["skillId"] for r in removed_list}))
                + f"。另有 {len(partial_list)} 段只在部分武器上打不出（"
                + "、".join(f'{sid} {skills_by_id[sid]["nameZh"]}' for sid in sorted({r["skillId"] for r in partial_list}))
                + "，都是互斥动画套），不标 notInvoked，逐武器以 variants 为准；"
                  f"战技动画匹配不到、未做过滤的 {len(tae_unmatched_ids)} 个战技标 taeUnmatched。"
                  "原因的中文说明与涉及武器见 diagnostics.taeVerification。"
                if tae_verified else "（v3 TAE 核实）本文件生成时没有做 TAE 核实（counts.taeVerified=false）。"),
            "skillsWithoutWeapons": skills_without_weapons,
            "skillsWithoutFixedWeapons": skills_without_fixed,
            "skillsPoolOnly": skills_pool_only,
            "weaponSourcesNote":
                f"skills[].weaponIds（v3）= EquipParamWeapon.swordArtsParamId 固定引用 ∪ 局内战技池。"
                f"skillsWithoutWeapons 是 v3 口径下仍然没有任何武器的战技（{len(skills_without_weapons)} 个，"
                f"都是占位条目）；skillsWithoutFixedWeapons 是 v2 口径（只看固定引用）下没有武器的战技"
                f"（{len(skills_without_fixed)} 个）；二者之差 skillsPoolOnly（{len(skills_pool_only)} 个，"
                f"其中 {skills_pool_only_with_hits} 个有命中段）就是 v2 里「选不到」、v3 起只经由局内战技池出现的战技，"
                f"括号里是能带它的基础武器数。"
                f"只算可达的 custom 行（被 ItemTableParam / ItemLotParam / ShopLineupParam 引用，"
                f"本版本 {custom_stats['reachable']} 行，另有 {custom_stats['unreachable']} 行无人引用不算来源）："
                + ("未可达行独有的 (战技, 武器) 对共 " + str(len(unreachable_only_pairs)) + " 个（"
                   + "、".join(f"{a}→{w}" for a, w in unreachable_only_pairs[:10]) + "），不计入。"
                   if unreachable_only_pairs else "未可达行没有带来任何额外的 (战技, 武器) 对。")
                + f"EquipParamWeapon 自己的 swordArtsTableId 列（指向未被任何 custom 行引用的 xx10 池）不作为来源："
                  f"算上它会多出 {len(epw_extra_pairs)} 个 (战技, 武器) 对（绝大多数落在属性变体武器行上），"
                  f"但新增战技 {len(epw_extra_skills)} 个——参数表里看不出它在本作何时生效，见 caveats。",
        },
        "fieldNotes": {
            "省略即默认值": "为控制体积，所有等于默认值的字段都被省略。"
                        "motion / flat 里只保留非 0 的属性键，整体为空则该键不存在；"
                        "poise / poiseMv / stamina / staminaMv / isBullet / bulletIds / noFp / "
                        "noDamage / noVariant / addBaseAtk / overrideAecId 缺失即表示 0 / false / -1；"
                        "weapons.atkAttribute / atkAttribute2（及其 ...Zh）是例外，四项恒存在；"
                        "weapons.attackBase / weapons.correct 同理（缺失的键 = 0）；"
                        "weapons.skillVariant 缺失表示这把武器的战技没有命中段；"
                        "skills.variants 缺失表示没有武器引用这个战技（或它没有命中段）；"
                        "（v3）weaponSources[].fixed 缺失 = false、pool 缺失 = 不经由战技池；"
                        "weapons.skillVariants 缺失 = 该武器的战技都没有命中段，"
                        "weapons.customWeapons 缺失 = 没有可达的 custom 行以它为基础武器；"
                        "（v3 TAE 核实）hits.notInvoked 缺失 = false（此时也没有 notInvokedReason），"
                        "skills.taeUnmatched 缺失 = false；"
                        "（v3 审查修正）hits.noFpSource 缺失 = noFp 来自行名（或 noFp=false），hits.fpBoth 缺失 = false，"
                        "hits.selfOrAllyOnly 缺失 = false；"
                        "（v3 修订）weapons.customMagicTables 缺失 = 没有可达的施法器 custom 行以它为基础武器；"
                        "spells.casterWeaponIds / casterSources 恒存在且非空（不可施放的 Magic 行不进 spells）。",
            "weaponIds": "（v3 取值扩大）skills[].weaponIds = 能带这个战技的全部武器 ="
                         "EquipParamWeapon.swordArtsParamId 固定引用 ∪ 局内战技池"
                         "（可达的 EquipParamCustomWeapon 行，其 swordArtsTableId 指向的池里含该战技且 chanceWeight>0，"
                         "取该行的 targetWeaponId）。v2 只有前一半，所以风暴刃（210）、狩猎巨人（116）等只在池里出现的战技"
                         "没有武器。每把武器的来源见 weaponSources；逐个战技的变化见 coverage.skillsPoolOnly。",
            "weaponSources": "skills[].weaponSources（v3）与 weaponIds 一一对应（同序），每项 {id, fixed?, pool?}："
                             "fixed=true 表示 EquipParamWeapon.swordArtsParamId 就是这个战技；"
                             "pool 是 [[swordArtsTableId, chanceWeight, customRows], ...]（按池 ID 升序）："
                             "该武器的可达 custom 行里，有 customRows 行指向池 swordArtsTableId，"
                             "池里这个战技的权重是 chanceWeight（同池其它条目见顶层 swordArtsPools[池 ID]，"
                             "该行抽到本战技的概率 = chanceWeight / 池内权重之和）。"
                             "要回溯到具体行：weapons[该武器].customWeapons 里 swordArtsTableId 相同的那些 customId。"
                             "两者可以同时存在（固定战技也在池里）。",
            "skillIds": "weapons[].skillIds（v3）= 该武器局内可能出现的全部战技 ID（固定的 swordArtsParamId + "
                        "它所有可达 custom 行的池成员），升序；与 skills[].weaponIds 互为反向索引。"
                        "swordArtsParamId 指向不收录的战技行（没有 ArtsName）时不计入。",
            "skillVariants": "weapons[].skillVariants（v3）= {战技 ID（字符串）: 该战技 variants 数组的下标}，"
                             "覆盖 skillIds 里每个有命中段、且能解出动作套的战技。"
                             "取段：skills[战技].variants[weapon.skillVariants[str(战技 ID)]].atkIds。"
                             "固定战技那一项与 skillVariant 相同。",
            "customWeapons": "weapons[].customWeapons（v3）= [[customId, swordArtsTableId], ...]：以这把武器为 "
                             "targetWeaponId 的**可达** EquipParamCustomWeapon 行（被 ItemTableParam itemCategory=6、"
                             "ItemLotParam lotItemCategory0N=6 或 ShopLineupParam equipType=6 引用）。"
                             "swordArtsTableId = -1 表示该行不抽池（推断：沿用武器自带的 swordArtsParamId）。"
                             "只收 targetWeaponId 是有名武器的行。",
            "swordArtsPools": "顶层 swordArtsPools（v3）= {SwordArtsTableParam 池 ID: [[战技 ID, chanceWeight], ...]}，"
                              "只收被可达 custom 行引用的池、且只收 chanceWeight>0 的条目；"
                              f"同一池里同一战技写了两行的（本版本 {pool_dup_rows} 行，例 50000000 刺剑池的 850 白影诱惑）"
                              "按抽取效果把权重相加合并成一项。"
                              "**分组规则：同一个 ID 的全部行 = 一个池**（SwordArtsTableParam 11896 行只有 841 个不同 ID，"
                              "与 AttachEffectTableParam 同一惯例）。Paramdex 行名前缀里的 \"<Dagger>\" / "
                              "\"<Untyped Straight Sword>\" 等与引用它的 custom 行的武器类别逐一吻合；"
                              "行名本身（包括 custom 行与商店行的名字）不可靠，归属一律以 targetWeaponId 为准。",
            "casterWeaponIds": "spells[].casterWeaponIds（v3 修订）= 能携带这个法术的施法器（基础武器 ID，升序）："
                               "可达的 EquipParamCustomWeapon 行里，magicTableId_1 或 magicTableId_2 指向的 MagicTableParam 池"
                               "含该 magicId 且 chanceWeight>0，取该行的 targetWeaponId。本版本施法器 "
                               f"{len(custom_magic_by_weapon)} 把（"
                               + "、".join(f"{t} {n} 把" for t, n in sorted(caster_type_counts.items()))
                               + "）。每把的来源见 casterSources。",
            "casterSources": "spells[].casterSources（v3 修订）与 casterWeaponIds 一一对应（同序），每项 {id, pool}，"
                             "结构仿 skills[].weaponSources（法术没有「固定」来源，所以没有 fixed）："
                             "pool = [[magicTableId, chanceWeight, customRows], ...]（按池 ID 升序）——"
                             "该武器的可达 custom 行里有 customRows 行的 magicTableId_1 或 _2 指向池 magicTableId"
                             "（同一行两个槽指向同一个池只算一行），池里这个法术的权重是 chanceWeight"
                             "（同池其它条目见顶层 magicPools[池 ID]，该槽抽到本法术的概率 = chanceWeight / 池内权重之和）。"
                             "要回溯到具体行：weapons[该武器].customMagicTables 里两个槽之一等于该池的那些 customId。",
            "customMagicTables": "weapons[].customMagicTables（v3 修订）= [[customId, magicTableId_1, magicTableId_2], ...]："
                                 "以这把武器为 targetWeaponId、且至少一个法术槽不是 -1 的**可达** EquipParamCustomWeapon 行"
                                 "（可达口径同 customWeapons）。一局里拿到的施法器每个槽从对应的池里各抽一个法术。",
            "magicPools": "顶层 magicPools（v3 修订）= {MagicTableParam 池 ID: [[magicId, chanceWeight], ...]}，只收被可达施法器 "
                          "custom 行引用的池、且只收 chanceWeight>0 的条目。分组规则同 swordArtsPools：**同一个 ID 的全部行 = 一个池**"
                          f"（MagicTableParam {len(magic_table_raw)} 行、{len({r['ID'] for r in magic_table_raw})} 个不同 ID；"
                          f"custom 行引用到的池 {len(magic_tables_any_custom)} 个，全部是表里的 ID）。"
                          f"可达池里 chanceWeight=0 的行 {len(magic_zero_in_used)} 行（抽不到；多数是第 2 槽池把第 1 槽的法术置 0），不收，"
                          "清单与说明见 diagnostics.spellCasting.zeroWeightRowsInUsedPools / zeroWeightNote；这些 magicId 也都在别的池里以正权重出现。"
                          + (f"同一池里同一法术写了两行的 {magic_pool_dup_rows} 行已按权重相加合并。" if magic_pool_dup_rows else ""),
            "spellsNotCastable": "coverage.spellsNotCastable（v3 修订）：Magic 表里有名字、但不在任何可达施法器池里的行，不收进 spells[]。"
                                 "每项 {id, nameZh, nameEn, kind, hits（修订前归到它的命中段数）, atkIds, magicTablePools"
                                 "（任何权重下引用它的池，空 = 没有）, sameNameSkillIds（本作同名、有武器的战技）, reason}。",
            "unnamedWeapons": "没有 WeaponName 文本的 EquipParamWeapon 行不收录（本版本 "
                              f"{unnamed_rows} 行）。其中 100000–101000 这批 wepType 3、rarity 0、Paramdex 行名为空的"
                              "测试行把 swordArtsParamId 指到 210 风暴刃（" + str(unnamed_skill_refs.get(210, 0)) + " 行）——"
                              "这就是 v2 里「210 看着有武器引用、weaponIds 却为空」的原因；v3 里 210 的武器全部来自战技池。"
                              "custom 行的 targetWeaponId 指向无名行的同样不收（可达行里本版本 "
                              f"{custom_stats['reachableUnnamedTarget']} 行）。",
            "motion": "AtkParam_Pc 的 atkPhysCorrection / atkMagCorrection / atkFireCorrection / "
                      "atkThunCorrection / atkDarkCorrection，单位是百分比，"
                      "乘以武器对应属性的攻击力（含强化与词条加成后的值）。",
            "flat": "AtkParam_Pc 的 atkPhys / atkMag / atkFire / atkThun / atkDark，固定伤害，"
                    "子弹与法术常用；与 motion 同时存在时两者相加。",
            "holy": "游戏内部字段名是 dark（atkDarkCorrection / attackBaseDark），本作即「圣」属性。",
            "poise": "poise = atkSuperArmor（固定削韧值）；poiseMv = atkSuperArmorCorrection"
                     "（百分比，乘武器 poiseDamageBase = saWeaponDamage）。"
                     "玩家武器攻击基本只用 poiseMv，子弹 / 法术多用 poise。",
            "stamina": "stamina = atkStam（固定精力削减，即对格挡中敌人精力条的伤害）；staminaMv = atkStamCorrection"
                       "（百分比，乘武器 attackBaseStamina）。",
            "小数": "poise / poiseMv / weapons.poiseDamageBase 在参数表里就是浮点"
                  "（如 5.5、10.175、262.5），这里原样保留；其余数值字段都是整数。",
            "attribute": "AtkParam_Pc.atkAttribute（枚举 ATKPARAM_ATKATTR_TYPE）："
                         "Slash 斩击 / Strike 打击 / Pierce 突刺 / Standard 标准 / None 无；"
                         "252、253 表示沿用武器的 atkAttribute2 / atkAttribute——"
                         "此时**必须**回到 weapons[] 上读 atkAttribute2 / atkAttribute"
                         "（见 fieldNotes.weaponAtkAttribute），本数据集 48% 的段是这种间接引用。",
            "weaponAtkAttribute": "weapons[].atkAttribute / atkAttribute2 = EquipParamWeapon 的同名字段，"
                                  "枚举与 hits[].attribute 共用 enums.atkAttribute（0 斩击 / 1 打击 / "
                                  "2 突刺 / 3 标准）；atkAttributeZh / atkAttribute2Zh 是对应中文名，"
                                  "四项恒存在；英文名请查 enums.atkAttribute[str(值)].en（省体积没重复写）。"
                                  "hits[].attribute == \"WeaponAtkAttribute\"（253）的段实际伤害类型 = "
                                  "该武器的 atkAttribute；== \"WeaponAtkAttribute2\"（252）的段 = "
                                  "该武器的 atkAttribute2。多数武器两者不同"
                                  "（例 9040000 尸山血海：atkAttribute=0 斩击、atkAttribute2=2 突刺），"
                                  "所以不能只看其中一个。",
            "source": "这段命中是怎么找到的，字母可叠加："
                      "n=AtkParam_Pc 行名匹配，b=经由 Bullet（含 Magic.refCategory=1 与子弹链），"
                      "r=Magic.refCategory=0 的 refId，a=SwordArtsParam/Magic 的 atkParamId 锚点，"
                      "w=BehaviorParam_PC 兜底。",
            "label": "Paramdex 行名里战技 / 法术名之后的原始英文段标签；labelZh 是规则化中文。"
                     "两者都缺失表示该行名只有技能名（多见于只有一段的战技）。",
            "ctx": "该段命中来自哪一套动作，取自 Paramdex 行名方括号里 \"AoW\" 之后的部分；"
                   "缺失表示方括号里只有 \"AoW\"（不分武器的默认套）。ctxKind 说明它是什么："
                   "weapon=具体武器名（如 \"Rivers of Blood\"）、category=武器类别或动作组名"
                   "（如 \"Axe\"、\"Large Weapon\"）、chr=渡夜者角色名（行名写作 \"[AoW - Duchess]\"）。"
                   "ctxZh 是中文，与 ctx 相同时省略。"
                   "**ctx 只用来显示，不要拿它做过滤**：同一招的默认套与各动作组套是互斥变体，"
                   "按「ctx == 武器名 or ctx == 类别名 or ctx 缺失」取并集会把两套一起算进去；"
                   "而且 Small Weapon / Large Weapon / Polearm 这些动作组名并不对应 wepType"
                   "（同为 Axe 的武器会按 behaviorVariationId 被拆进不同组）。"
                   "请改用 skills[].variants + weapons[].skillVariant。",
            "variants": "skills[].variants 给出「每把武器实际会打出哪些段」，由 BehaviorParam_PC "
                        "实解得到（ID = base + behaviorVariationId*1000 + behaviorJudgeId，"
                        "三级回退：武器自己的 variationId → 取整到百位的族 variationId（v3 补上）"
                        "→ variationId=0 的通用行）。v3 起 weaponIds 含战技池里的武器，"
                        "variants[].weaponIds 相应扩展。"
                        "每个元素：atkIds=这一套包含的段（对应 hits[].atkId）、weaponIds=用这一套的武器、"
                        "ctx/ctxZh/ctxKind=这一套的动作归属（整套 ctx 不一致时省略）、"
                        "via=\"behavior\"（行为表实解）或 \"ctx\"（行为表分不出来，按 ctx 单选：本版本是 "
                        + "、".join(f'{sk["id"]} {sk["nameZh"]}' for sk in skills
                                   if any(v["via"] == "ctx" for v in sk.get("variants", ())))
                        + "，原因见 caveats）。一套里可能混入少量 ctx 缺失的共用段"
                        "（例如战吼在 Axe 上是 14 段 ctx=\"Axe\" + 2 段共用的 ctx 缺失段），这是正确的。",
            "skillVariant": "weapons[].skillVariant 是该武器在「它的 swordArtsParamId 指向的战技」的 "
                            "variants 数组里的下标。缺失表示这把武器的战技没有任何命中段。"
                            "取段就是 skills[i].variants[skillVariant].atkIds。"
                            "（v3 语义不变，只指固定战技；池里其它战技的下标见 skillVariants。）",
            "noDamage": "noDamage=true = 这一段不产生对敌伤害，构成与排名都不算它。两种来源："
                        "(a) 该 AtkParam 行确实属于这个战技 / 法术（行名点名），但 motion / flat / poise / "
                        "poiseMv / stamina / staminaMv 六项全为 0，只用来挂异常状态或减益"
                        "（例如百智的世界、催眠火焰）；"
                        "(b)（v3 审查修正）行只打自己 / 队友（同时标 selfOrAllyOnly=true，见该条），"
                        "它的 motion / flat 是回血等效果的倍率，保留原值但不是伤害。"
                        "这类行**保留**并标 noDamage=true；"
                        "只有「行名没点名、纯靠子弹链或锚点顺带捞到的全零辅助行」"
                        "（Blank / No Target / Spell Helper 之类）才被剔除。"
                        "想只看有伤害的段时按 noDamage 过滤。",
            "selfOrAllyOnly": "hits[].selfOrAllyOnly=true（v3 审查修正）：AtkParam_Pc.opposeTarget=0 且 selfTarget=1 或 "
                              "friendlyTarget=1——这一段只打自己 / 队友，不打敌人（例：208 祈祷一击的回血子弹 1202100 "
                              "\"Heal Self\"、1202110 \"Heal Others\"，各带圣 motion 100，那是回血量的倍率）。"
                              "一律同时标 noDamage=true，所以三端不会把它算进伤害构成。它照样可以在 variants[].atkIds 里"
                              "（动画 / SpEffect 确实会触发它）。opposeTarget=0 但三项全 0 的行（如神圣光环的光环子弹）"
                              "靠子弹自己的判定命中敌人，不标。"
                              + f"本版本 {hits_self_or_ally} 段（其中 {hits_self_or_ally_with_values} 段带 motion / flat）。",
            "noFp": "hits[].noFp=true：专注值（FP）不足时打出的弱化版分支。同一次战技只打带 FP 版或无 FP 版其中一侧，"
                    "两侧互为替代，**不要相加**：按「noFp 与当前开关同侧」取段。"
                    "来源：行名带 \"No FP\"（noFpSource 缺失），或（v3 审查修正，需 counts.taeVerified=true）"
                    "noFpSource=\"tae\"——行名没写，但在留下它的武器上只被战技 TAE 里的无 FP 版动画调用"
                    "（4xxxx 个位 5–9，= 带 FP 版动画号 + 5；例：210 风暴刃 300000411–413 = a659 的 40005/40015/40025，"
                    "116 狩猎巨人 301700915 = a616 的 40005）。TAE 补标的段 labelZh 前加了「无FP版」，"
                    "与行名带 No FP 的段写法一致。"
                    + (f"本版本 TAE 补标 {len(no_fp_tae)} 段（{len({r['skillId'] for r in no_fp_tae})} 个战技，"
                       f"其中带伤害 {no_fp_tae_damaging} 段），清单见 diagnostics.taeVerification.noFpFromTae。"
                       if tae_verified else "本文件没有做 TAE 核实，noFp 只来自行名。"),
            "noFpSource": "只在 noFp=true 且由 TAE 判出时出现，取值 \"tae\"；缺失表示 noFp 来自行名里的 \"No FP\"。",
            "fpBoth": "hits[].fpBoth=true（v3 审查修正，需 counts.taeVerified=true）：带 FP 版与无 FP 版动画（或不分 FP 的 "
                      "3xxxx / 吼叫 R2 动画）都会调用这一段——两侧共用，无论「专注值不足」开关在哪一侧都应计入。"
                      "fpBoth 段的 noFp 一定是 false。"
                      + (f"本版本 {len(fp_both_list)} 段，清单见 diagnostics.taeVerification.fpBoth。" if tae_verified else ""),
            "correct": "weapons[].correct 是能力值补正（EquipParamWeapon 的 correctStrength / "
                       "correctAgility / correctMagic / correctFaith / correctLuck），键名依次为 "
                       "strength / dexterity / intelligence / faith / arcane，只保留非 0 项。"
                       "辉石魔杖与圣印记的法术强度就挂在这里（如辉石杖 intelligence=100）。",
            "staminaBase": "weapons[].staminaBase = EquipParamWeapon.attackBaseStamina，"
                           "hits[].staminaMv 乘的就是它。",
            "noVariant": "hits[].noVariant=true 表示：这一段确实属于该战技（行名点名），"
                         "但它所在的动作套在本作没有任何武器会用到——"
                         "该战技有 variants，而这个 atkId 不在其中任何一个的 atkIds 里。"
                         "按 usage 的选段算法它永远取不到，只在「显示该战技的全部段」时才会出现。"
                         "缺失表示可达，或该战技根本没有 variants（没有武器引用它，无从判断）。"
                         "v3 起「武器」含战技池来源，所以标记范围与 v2 不同。"
                         "（v3 TAE 核实后）判定基于 TAE 核实**之前**的行为表选段，与 notInvoked 互斥。"
                         "详见 coverage.hitsWithoutVariantNote。",
            "notInvoked": "hits[].notInvoked=true（v3 TAE 核实）：行为表（BehaviorParam_PC）给至少一把武器解出了这段，"
                          "但逐武器核对动画事件（TAE）后，它在所有这些武器上都不会被该战技的动画调用，"
                          "已从 variants[].atkIds 移除；hits[] 里保留，只在「显示该战技的全部段」时出现。"
                          "notInvokedReason 给原因，取值见 enums.notInvokedReason；不同武器原因不同时取 enums 里靠前的那个，"
                          "完整分布见 diagnostics.taeVerification.removedHits[].reasons。"
                          "只在**部分**武器上打不出的段不标（" + (partial_example or "本版本没有这种段")
                          + "），逐武器结论一律看 variants，清单见 diagnostics.taeVerification.partiallyRemoved。"
                          "与 noVariant 互斥（noVariant = 行为表层就没有武器用到）。",
            "notInvokedReason": "与 notInvoked 同时出现，取值是 enums.notInvokedReason 的键。",
            "taeUnmatched": "skills[].taeUnmatched=true（v3 TAE 核实）：该战技的动画匹配不到——战技 TAE a(600+swordArtsType) "
                            "缺失，或它的段在任何武器上都没有事件调用（本版本："
                            + ("、".join(f'{sid} {skills_by_id[sid]["nameZh"]}' for sid in tae_unmatched_ids) or "无")
                            + "；弓系战技的段只有 SwordArtsParam.atkParamId 锚点、伤害走箭矢，不经 BehaviorParam_PC）。"
                            "这类战技的 hits 与 variants 不做 TAE 过滤，与 TAE 核实前相同，页面照旧。缺失 = false。",
            "taeVerified": "counts.taeVerified=true 表示本文件的 variants[].atkIds 已按 TAE 核实"
                           "（生成时 raw/tae/invoked.json 存在，由 extract_tae.py 从本机 c0000 动画包解出）；"
                           "false 表示生成时没有 TAE 数据，variants 是行为表口径，notInvoked / taeUnmatched 一律不出现，"
                           "diagnostics.taeVerification.skippedReason 说明原因。",
            "法术与 TAE": "spells[] 不做 TAE 过滤：法术的子弹 / 攻击行由 Magic.refId1–10 决定，施法动画 a(400+Magic.refType) "
                         "的事件 64 只带 refSlot，没有逐段的 judgeId 可核；按「段所在的 refId 槽是否被施法动画用到」的核实结果"
                         "（raw/tae/hit-invocation-report.json 的 spells[]）绝大多数段都在被用到的槽里，其余是锚点、触发型 SpEffect "
                         "发射的子弹或未用槽，与本数据集对法术段的用法（只看 flat 做相对排名）不冲突，所以本版不改 spells。",
        },
        "usage": {
            "选段（必读）": "先确定这把武器用哪一套：v = skills[i].variants[weapon.skillVariants[str(skills[i].id)]]"
                       "（固定战技也可用 weapon.skillVariant），"
                       "段 = hits 中 atkId ∈ v.atkIds 的那些。**不要**按 ctx 字符串取并集——"
                       f"默认套与动作组套是互斥变体，取并集会让 {ctx_union_dup} 把武器的段数与伤害翻倍，"
                       f"而 {ctx_pick_miss} 把斧 / 镰 / 戟类武器因为动作组名"
                       "（Small Weapon / Large Weapon / Polearm）"
                       "不在 WEP_TYPE 枚举里而一段都取不到。"
                       "skills[].variants 缺失（多见于没有任何武器引用的战技）时，"
                       "退回「先 ctx == 武器 nameEn，没有再 ctx == wepTypeEn，再没有才用 ctx 缺失的那组」"
                       "的单选逻辑，仍然不要取并集。",
            "近战武器段": "适用于战技里 motion 非空的段。该属性伤害 ≈ "
                     "武器该属性攻击力（含强化、亲和与词条加成后的最终值）× motion[el] / 100 "
                     "+ flat[el]；addBaseAtk=true 的段额外再加一份武器该属性攻击力"
                     "（AtkParam.isAddBaseAtk=1）。"
                     "overrideAecId 存在时，这一段改用该 ID 指向的 AttackElementCorrectParam "
                     "计算能力值补正，而不是武器自己的 attackElementCorrectId"
                     "（写出前已校验该 ID 在 AttackElementCorrectParam 里真实存在，"
                     "参数表里的悬空引用不会写出这个字段，见 caveats）。",
            "伤害类型（斩 / 打 / 突）": "先看 hits[].attribute："
                            "Slash / Strike / Pierce / Standard 就是这一段自己的物理伤害类型；"
                            "若为 \"WeaponAtkAttribute\" 则改读 weapons[].atkAttribute，"
                            "若为 \"WeaponAtkAttribute2\" 则改读 weapons[].atkAttribute2"
                            "（各自带 ...Zh 中文名，英文名查 enums.atkAttribute）；"
                            "\"None\" 表示这一段不吃物理减伤类型（多为纯属性伤害或挂状态段）。"
                            f"本版本 {total_hits} 段里有 {wep_attr_hits} 段"
                            f"（{wep_attr_hits * 100 // max(total_hits, 1)}%）走 Weapon* 间接引用，"
                            "要按 boss 数据集的 fights[].damageRates"
                            "（standard / slash / strike / pierce，键名就是 enums.atkAttribute 的 en 小写）"
                            "加权就必须走这一步。",
            "法术 / 子弹段": "法术段的 motion 在参数表里几乎都是五属性同值 100（420 段里 327 段如此），"
                        "那是「照抄武器攻击力 100%」的占位写法，**不要**把它乘到施法器的 "
                        "attackBase 上——辉石魔杖 / 圣印记的 attackBase 只有 physical"
                        "（如 33000000 辉石杖 physical=25），乘出来会凭空多出一截物理伤害，"
                        "而法术本身不吃物理。法术段请只用 flat[el]（如 4021 帚星 flat.magic=285）"
                        "做属性配比与相对排名；motion 只在施法器该属性 attackBase 非 0 时才有意义。",
            "削韧": "单段削韧 = poise + 武器 poiseDamageBase × poiseMv / 100。"
                  "单段精力削减（对格挡中敌人的精力条，与玩家自身精力无关）= stamina + 武器 staminaBase × staminaMv / 100。",
            "本数据集的边界": "没有收录 ReinforceParamWeapon（强化倍率，武器 reinforceTypeId 指向）与 "
                        "AttackElementCorrectParam（能力值补正曲线，武器 attackElementCorrectId / "
                        "段 overrideAecId 指向），也没有 CalcCorrectGraph。"
                        "因此**绝对伤害数值无法由本数据集还原**；它支持的是："
                        "(a) 同一把武器上不同战技 / 不同段的相对比较，"
                        "(b) 按伤害类型加权的属性配比排名，"
                        "(c) 削韧 / 精力削减的绝对值（这两项不走上面那几张表）。"
                        "要算绝对值，请由调用方提供游戏内显示的最终分属性攻击力。",
            "战技来源（v3）": "「这把武器能带哪些战技」读 weapons[].skillIds，「这个战技能用哪些武器」读 "
                         "skills[].weaponIds；要区分固定 / 随机池、或给出池内概率，读 skills[].weaponSources"
                         "（pool 项的权重配合 swordArtsPools 求概率）。不要再用 swordArtsParamId 反查——"
                         f"那样会漏掉 {len(skills_pool_only)} 个只在局内战技池里出现的战技（coverage.skillsPoolOnly）。",
            "法术来源（v3）": "spells[] 就是本作玩家能施放的全部法术（v3 修订后只收可施放的，"
                          f"{len(spells_not_castable)} 行 Magic 残留行见 coverage.spellsNotCastable）："
                          "「这个法术能用哪些施法器」读 spells[].casterWeaponIds；「这把手杖 / 圣印记可能带哪些法术」反查 "
                          "casterWeaponIds 含它的 spells（或按 weapons[].customMagicTables 的两个槽查 magicPools）；"
                          "要给出概率，读 spells[].casterSources 的 pool 项并配合 magicPools 求池内占比。"
                          "施法器每个 custom 行有两个法术槽，各从自己的池里抽一个，所以同一行的两个槽要分开算。"
                          "不要再按「Magic 表里有名字」列法术——那样会把风暴管束者（8100 / 8101，本作是战技 1200）当成玩家法术。",
            "命中段已按 TAE 核实（v3）": (
                ("counts.taeVerified=true：skills[].variants[].atkIds 在行为表选段之上又逐武器核对了动画事件（TAE），"
                 "只留下这把武器用这个战技时动画真会打出的段，取段写法不变（仍是 variants[下标].atkIds）。留下的状态："
                 "invoked（战技 TAE a(600+swordArtsType) 里有无门控事件调用它）、weaponTae（野蛮咆哮 / 战吼 / 灭洛斯的狂嚎"
                 "改写 R2 后，段在武器动作组 TAE 的 30600 系动画里）、spEffect（由本战技的 SpEffect 触发，如祈祷一击的回血子弹、"
                 "卡利亚式奉还的反击；回血子弹只打自己 / 队友，标了 noDamage + selfOrAllyOnly，不算伤害）、"
                 "conditional（带玩家拿得到的 stateInfo 门控，本版本只有 1196 黄金式奉还格挡成功后的两段）、"
                 "noJudge（锚点 / 弹药行，无法经 TAE 判定，保守保留）。子弹链上的段按发射它的 BehaviorParam_PC 行被"
                 "InvokeBulletBehavior（事件 2）以对应 judgeId 调用与否判定；战技 TAE 的 4xxxx 动画按百位分套，一把武器只播一套，"
                 "几套 judge 不同的（二连斩 / 剑舞 / 鲜血斩击等）只留这把武器那一套，不再相加。"
                 f"本版本移除 {weapon_hits_removed} 个武器×段（{len(tae_skills_changed)} 个战技、"
                 f"{tae_pairs_changed} 个 (战技, 武器) 对的段有变化），其中 {hits_not_invoked} 段在所有武器上都打不出、"
                 f"已标 hits[].notInvoked，{len(partial_list)} 段只在部分武器上打不出；清单见 diagnostics.taeVerification。"
                 "局限：(1) TAE 只回答「动画会不会调用这段」，不回答一次战技里会命中几次（持续判定 / 多次 Hit 仍按一段算）；"
                 "(2) 互斥动画套由 HKS 的 GetSwordArtsDiffCategory 选，c0000.hks 是字节码读不出，本版按 wepmotionCategory "
                 "专属套 → 本 var 专属行 → 类别归组（103 回旋斩手工表有证据；某套的 AtkParam 行名点名类别时也算证据，"
                 "记 classGroupNamed，如 204 鲜血斩击 402 套的 \"Slash (Greatsword)\" → 大剑；其余大剑 / 特大剑 / 大斧 / 大锤 / "
                 "特大武器 → 402、矛 / 大矛 → 403 是体型类比推断）→ 默认套 400 选，选套依据见 diagnostics.taeVerification.exclusiveBlocks；"
                 "(3) stateInfo 187「玩家拿不到」只查了参数表（EMEVD 未查）；「成功格挡 / 弹反之后才打出」的段按可达保留、"
                 "默认计入排名：1196 黄金式奉还的两段是 conditional（stateInfo 469），305 卡利亚式奉还的 300000682/683"
                 "（魔力 flat 270）是弹反法术成功后由 SpEffect 1515 触发的 spEffect 段，性质相同；"
                 f"(4) 带 FP / 无 FP 两个分支都在 atkIds 里，靠 hits[].noFp 区分、按与开关同侧取段，不要相加。"
                 f"行名没写 \"No FP\" 的无 FP 段原先没有标记、会和带 FP 段一起被默认计入；核实后按战技 TAE 的动画号"
                 f"（4xxxx 个位 5–9 = 无 FP 版）补标了 {len(no_fp_tae)} 段（noFpSource=\"tae\"，{len({r['skillId'] for r in no_fp_tae})} 个战技，"
                 "例：风暴刃 300000411–413、狩猎巨人 301700915），"
                 f"两侧动画都调用的 {len(fp_both_list)} 段标 fpBoth（两侧都该计入），见 fieldNotes.noFp / fpBoth；"
                 "(5) skills[].taeUnmatched=true 的战技不过滤；(6) 法术不过滤（fieldNotes.法术与 TAE）；"
                 "(7) 结论以本机 1.03.5 的 c0000 动画包为准，游戏更新后要重跑 extract_tae.py 再重生成。")
                if tae_verified else
                ("counts.taeVerified=false：生成时没有 raw/tae/invoked.json（" + tae_skip_reason + "），"
                 "variants[].atkIds 是行为表口径，可能包含本作动画并不调用的段（例：狩猎大蛇的 Beam of Light），"
                 "也可能把几套互斥动画的段相加；hits[].noFp 只来自行名，行名没写 No FP 的无 FP 段（风暴刃 300000411–413 等）"
                 "没有标记。先跑 extract_tae.py 再重生成即可得到核实过的版本。")),
        },
        "caveats": [
            "103 回旋斩是唯一一个 BehaviorParam_PC 分不出来的战技：它的 4 套动作"
            "（默认 / Large Weapon / Polearm / Twinblade）全部挂在 variationId=0 的 "
            "behaviorJudgeId 220-257 上，任何武器解出来都是 4 套全中。"
            "这里按武器类别手工归组（直剑 / 曲剑→默认，大曲剑→Large Weapon，"
            "双头剑→Twinblade，戟 / 镰→Polearm），对应的 variants[].via = \"ctx\"。"
            "附带说明：Large Weapon 与 Polearm 这两套的 6 段数值完全相同"
            "（105/60/110/70/40/85，poiseMv 230/75/230/100/50/100），"
            "所以「大曲剑 vs 戟 / 镰」分到哪一套对数值没有任何影响；"
            "真正有区别的只有默认套（110/65/115/70/40/85）与 Twinblade 套（poiseMv 290/90…）。",
            "400 贯穿射击 / 401 连续射击 / 1169 拉塔恩的骤雨 这 3 个弓系战技的 AtkParam 行名"
            "没有方括号，BehaviorParam_PC 里也没有对应的战技槽（弓的伤害走箭矢），"
            "只能靠 atkParamId 锚点拿到 1 段，variants[].via = \"ctx\"。",
            "Small Weapon / Large Weapon / Polearm 这些动作组名没有全局的 wepType 对应："
            "它们是逐个战技的动作族（110 盲击：Small Weapon = 曲剑 / 锤 / 连枷 / 斧，"
            "Large Weapon = 大剑 / 大曲剑 / 大锤 / 大斧），哪一族挂在 variationId=0 上当默认套也因战技而异。"
            "所以本数据集不提供「别名 → wepType」映射表，归属一律以 variants 为准。"
            "（v2 曾写「1400 的斧走 Small Weapon、1406/1407 的斧走 Large Weapon」，那是解析时漏了"
            "「variationId 取整到百位」这一级回退；v3 补上后，同一战技里同一武器类别只落进一套动作。）",
            "（v3）BehaviorParam_PC 三级回退：武器 behaviorVariationId → 取整到百位 → 0。"
            "证据：1200 风暴管束者的 10 套角色动作挂在 variationId 0/100/500/900/1100/1102/1800/2100/2300/4100 上，"
            "正好是各渡夜者专属武器 behaviorVariationId（117/503/900/1100/1102/1800/2151/2304/4100；"
            "追踪者 300 无专属行 → 0 = Default 套）取整到百位的结果，与 Paramdex 行名的角色名逐一吻合；"
            f"且补上这一级后，每个战技里同一武器类别只落进一套动作（本版本 {len(split_v3)} 个例外；"
            f"两级回退口径下，只看固定武器有 {len(split_legacy_fixed)} 个战技"
            f"（{'、'.join(str(x) for x in split_legacy_fixed) or '无'}）、"
            f"按 v3 的全部武器有 {len(split_legacy_all)} 个战技"
            f"（{'、'.join(str(x) for x in split_legacy_all) or '无'}）出现同类别武器被拆到两套）。"
            f"这一变化也改了 {len(legacy_changed_fixed)} 个**固定**武器 (战技, 武器) 对的选段"
            f"（{legacy_changed_fixed_text or '无'}），hits 本身不变；"
            f"连同战技池新增的对，与两级回退口径不同的共 {len(legacy_changed)} 对。",
            "（v3）1200 风暴管束者：Default 套在行为组 base 400000000 与 500000000 各挂了一份 0 号行，"
            "只看「武器在其中有专属行」的行为组才能把女爵 / 学者 / 执行者 / 送葬者 / 隐士 / 守护者 / 复仇者 / 无赖"
            "各自的角色套单独解出来（只在具名套 > 1 时介入，其它战技不受影响）；铁之眼的弓（variationId 4100）"
            "只有 No FP 四段挂在 4100 上，带 FP 的四段挂在 variationId 5000（= 铁之眼箭矢 50030000 的 5050 取整，"
            "弓的子弹行为按箭矢解），所以按武器名里的角色名整套选 Ironeye，variants[].via = \"ctx\"。",
            "（v3）103 回旋斩经局内战技池还能出现在短剑 / 大剑 / 刀 / 斧 / 大斧 / 矛上，行为表同样分不出来，"
            "按动作族补齐手工表：大剑、大斧 → Large Weapon，矛 → Polearm，短剑、刀、斧 → 默认套"
            "（推断，依据是 110 盲击与 118 罗蕾塔的斩击能实解出来的动作族；Large Weapon 与 Polearm 数值完全相同）。",
            "（v3）EquipParamWeapon 也有一个 swordArtsTableId 列，指向不被任何 custom 行引用的 xx10 池"
            "（内容 = 同类别 xx00 全池，或「属性池 ∪ Untyped 池」，如 10000510 = 10000500 火焰短剑池 ∪ 10000050）。"
            "局内掉落走 EquipParamCustomWeapon，参数表里看不出这一列在本作何时生效，所以**不**作为 weaponIds 来源；"
            f"若算上它，会多出 {len(epw_extra_pairs)} 个 (战技, 武器) 对，但不会让任何战技从「无武器」变为「有武器」。",
            "9040000 尸山血海 / 1177 尸横遍野：血刀气没有独立的 Bullet 行。"
            "该武器 behaviorVariationId=906 在战技槽（base 300000000，judge 900-915）上"
            "全部是 refType=0 的直接 AtkParam 引用，12 段（6 段带 FP + 6 段 No FP）就是全部；"
            "血刀气的判定包含在这 12 段的 AtkParam 里，没有可标注的子弹 ID。",
            "跨条目误配段已统一丢弃：SwordArtsParam / Magic 的 atkParamId 锚点与子弹链里存在"
            "指向**别的**战技 / 法术的残留引用，本版本共 "
            f"{len(foreign_drops)} 段被丢弃——"
            + "；".join(foreign_drops) +
            "。判据是「该 AtkParam 行的 Paramdex 行名点名的技能与本条目的名字完全不相交」，"
            "行名匹配（source 含 n）路线得到的段不受影响。"
            "这几段原先都没有进入任何 variant，走 skillVariant 的页面本就取不到；"
            "丢弃是为了让「显示全部 hits」的回退路径（weaponIds 为空的条目只能走这条）也不再出现假段。",
            "AttackElementCorrectParam 悬空引用：AtkParam_Pc.overwriteAttackElementCorrectId "
            "在参数表里可能指向不存在的行"
            + ("（本版本：" + "、".join(f"AEC 行 {k} 被 {v} 段引用" for k, v in sorted(aec_dangling.items()))
               + "，来自 1001 火焰唾球）" if aec_dangling else "（本版本无）")
            + "。这类值不会写成 hits[].overrideAecId，以免消费方照 usage 去查表拿到空值；"
            "写出的 overrideAecId 保证在 AttackElementCorrectParam 里存在。",
            "（v3 TAE 核实）1188 狩猎大蛇在本体里是带光波的远程战技，本作不是：参数里 301703900 / 301703901 "
            "「L2 #1/#2 Beam of Light」（超长胶囊判定）仍在，但战技 TAE a788 的 L2 动画调用它们的事件都带 stateInfo 187 门控，"
            "187 在本作玩家拿不到；301703905 / 301703975 没有任何动画调用，301703955 只在大枪动作组的吼叫 R2 动画里。"
            + (f"本版本 variants 只剩 {'/'.join(str(a) for a in skills_by_id[1188]['variants'][0]['atkIds'])}"
               "（两段近战 L2 #1 / #2 与各自的无 FP 版）。"
               if tae_verified and skills_by_id.get(1188, {}).get("variants")
               else "本版本没有做 TAE 核实，这些段仍在 variants 里。"),
        ],
        "enums": {
            "wepType": {str(k): {"en": v[0], "zh": v[1]} for k, v in sorted(WEP_TYPE_ZH.items())},
            "rarity": {str(k): {"en": v[0], "zh": v[1]} for k, v in sorted(RARITY_ZH.items())},
            "atkAttribute": {str(k): {"en": v[0], "zh": v[1]} for k, v in sorted(ATK_ATTR_ZH.items())},
            "magicKind": {k: MAGIC_KIND_ZH[k] for k in ("sorcery", "incantation", "pyromancy")},
            "ctxKind": {
                "weapon": "具体武器名（ctx 与某把武器的 nameEn 相同）",
                "category": "武器类别名（WEP_TYPE 枚举名）或 Paramdex 的动作组别名",
                "chr": "渡夜者角色名，行名写作 \"[AoW - Duchess]\" 这种带连字符的形式",
            },
            "ctxAlias": {
                en: {"zh": zh,
                     "note": "Paramdex 动作组别名，不在 WEP_TYPE 枚举里；"
                             "**没有对应的 wepType**，归属见 skills[].variants"}
                for en, zh in sorted(CTX_ALIAS_ZH.values())
                if norm_key(en) not in {norm_key(v[0]) for v in WEP_TYPE_ZH.values()}
            },
            "notInvokedReason": NOT_INVOKED_REASON_ZH,
        },
        "diagnostics": {
            "taeVerification": tae_diagnostics,
            # v3 修订：法术可施放口径的中间量
            "spellCasting": {
                "rule": "spells[] = 可达施法器 custom 行（ItemTableParam itemCategory=6 / ItemLotParam lotItemCategory0N=6 / "
                        "ShopLineupParam equipType=6 引用）的 magicTableId_1 / magicTableId_2 → MagicTableParam 池"
                        "（同 ID = 一池）里 chanceWeight>0 的 magicId；同一行两个槽指向同一池只算一行。",
                "customRows": {"reachable": magic_custom_stats["reachable"],
                               "unreachable": magic_custom_stats["unreachable"],
                               "reachableUnnamedTarget": magic_custom_stats["reachableUnnamedTarget"],
                               "reachableEmptyPool": magic_custom_stats["reachableEmptyPool"]},
                "poolsReferencedByAnyCustomRow": len(magic_tables_any_custom),
                "poolsReferencedByReachableRows": len(used_magic_pools),
                "poolDuplicateRows": magic_pool_dup_rows,
                "zeroWeightRowsInUsedPools": magic_zero_in_used,
                "zeroWeightNote": (
                    f"可达施法器池里 chanceWeight=0 的行（{len(magic_zero_in_used)} 行）：抽取时抽不到，不计入 magicPools 与 casterSources。"
                    "每项 {pool, magicId, rowName, slots（该池在引用它的 custom 行里是第几槽）, otherSlotPools（这些行另一个槽的池）, "
                    "inOtherSlotPool（另一个槽的池里这个法术是否有正权重）}。"
                    f"全部在第 {'/'.join(str(s) for s in sorted({s for z in magic_zero_in_used for s in z['slots']}))} 槽；"
                    f"{sum(1 for z in magic_zero_in_used if z['inOtherSlotPool'])} 行的法术正是同一行另一个槽的池里的法术"
                    "（例 3300100 的 4000 = 33000000 辉石杖第 1 槽池 3300000 的唯一法术），推断是「第 2 槽不再抽第 1 槽已给的法术」；"
                    "其余："
                    + ("、".join(f'{z["pool"]} 的 {z["magicId"]}（另一槽池 {z["otherSlotPools"]} 里没有它）'
                                for z in magic_zero_in_used if not z["inOtherSlotPool"]) or "无")
                    + "。行名多是 \"<Table> (0% weight)\"，保留了法术名的有 "
                    + ("、".join(f'{z["pool"]} 的 {z["magicId"]}「{z["rowName"]}」' for z in magic_zero_in_used
                                if "(0% weight)" not in z["rowName"]) or "无") + "。"
                    "这些 magicId 都另有正权重的来源（self_check 断言），所以不影响哪些法术可施放。"),
                "unnamedMagicIds": unnamed_magic_ids,
                "castableButUnnamed": castable_unnamed,
            },
        },
        "swordArtsPools": pool_payload,
        "magicPools": magic_pool_payload,
        "weapons": weapons,
        "skills": skills,
        "spells": spells,
    }

    self_check(payload, {row["ID"]: row for row in custom_raw}, reachable_custom, pre_sel, magic_table_raw)
    print("self_check 通过")

    args.out.parent.mkdir(parents=True, exist_ok=True)
    if args.pretty:
        text = json.dumps(payload, ensure_ascii=False, indent=1)
    else:
        text = json.dumps(payload, ensure_ascii=False, separators=(",", ":"))
    args.out.write_text(text, encoding="utf-8")

    size = args.out.stat().st_size
    print(f"写入 {args.out}（{size} 字节 = {size / 1024:.1f} KiB = {size / 1024 / 1024:.2f} MiB"
          f"{'，--pretty' if args.pretty else '，紧凑'}）")
    print(f"武器 {len(weapons)}；战技 {len(skills)}（有命中 {skills_with_hits}）；"
          f"法术 {len(spells)}（有命中 {spells_with_hits}）；命中段共 {total_hits}")
    print(f"命中段去重后 {len(atk_id_uses)} 个 atkId，其中 {shared_atk_rows} 行被多个条目共用"
          f"（行名写作 'A/B/C - Slash' 的共用行），共多出 {total_hits - len(atk_id_uses)} 条目。")
    print(f"动作套 variants {total_variants} 组，覆盖武器 {weapons_with_variant} 把"
          f"（按 via：{dict(variant_stats)}）")
    print(f"不属于任何 variant 的段（已标 noVariant）{no_variant_hits}，"
          f"其中带 motion/flat 的 {no_variant_damaging}")
    print(f"战技池（v3）：可达 custom 行 {custom_stats['reachable']}（其中不抽池 {custom_stats['reachableFixedOnly']}），"
          f"不可达 {custom_stats['unreachable']}；用到的池 {len(pool_payload)} 个 / 条目 {pool_entry_count}；"
          f"(战技, 武器) 对 {len(all_pairs)}（固定 {pair_fixed}、池 {pair_pool}、两者皆是 {pair_both}）；"
          f"池内重复条目 {pool_dup_rows} 行（已按权重相加合并）")
    print(f"有武器的战技 {sum(1 for sk in skills if sk['weaponIds'])}（v2 口径 {len(skills) - len(skills_without_fixed)}），"
          f"只经由战技池出现的 {len(skills_pool_only)}：")
    for line in skills_pool_only:
        print(f"  + {line}")
    print(f"仍然没有武器的战技：{skills_without_weapons}")
    print(f"法术可施放口径（v3 修订）：有名 Magic 行 {spells_named_total}，可施放 {len(castable_magic)}（收进 spells），"
          f"不可施放 {len(spells_not_castable)}：" + "、".join(f'{e["id"]} {e["nameZh"]}' for e in spells_not_castable)
          + f"；施法器 {len(custom_magic_by_weapon)} 把 {dict(caster_type_counts)}、可达 custom 行 {magic_custom_stats['reachable']}"
          f"（不可达 {magic_custom_stats['unreachable']}）、池 {len(magic_pool_payload)} 个 / 条目 {magic_pool_entry_count}、"
          f"(法术, 施法器) 对 {len(spell_pool_pairs)}；0 权重行 {len(magic_zero_in_used)}")
    print(f"选段与两级回退口径不同的 (战技, 武器) 对 {len(legacy_changed)}（固定 {len(legacy_changed_fixed)}："
          f"{legacy_changed_fixed_text or '无'}）；同类别拆两套的战技：v3 {split_v3}，"
          f"两级回退只看固定 {split_legacy_fixed}、全部武器 {split_legacy_all}")
    if unreachable_only_pairs:
        print(f"只在不可达 custom 行里出现的 (战技, 武器) 对（不计入）：{unreachable_only_pairs}")
    print(f"EquipParamWeapon.swordArtsTableId（不作为来源）若计入会多 {len(epw_extra_pairs)} 对、"
          f"新增有武器的战技 {len(epw_extra_skills)} 个")
    print(f"ctx 并集会翻倍的武器 {ctx_union_dup} 把；ctx 单选取不到段的武器 {ctx_pick_miss} 把"
          f"（两数已写进 usage.选段）")
    print(f"伤害类型需回武器上取（attribute=253/252）的段 {wep_attr_hits}")
    print(f"只打自己 / 队友的段（selfOrAllyOnly，已标 noDamage）{hits_self_or_ally}，其中带 motion/flat 的 {hits_self_or_ally_with_values}："
          + "、".join(f'{e["id"]} {e["nameZh"]} {h["atkId"]}' for e in skills + spells for h in e["hits"]
                     if h.get("selfOrAllyOnly") and (h.get("motion") or h.get("flat"))))
    if aec_dangling:
        print(f"⚠ overrideAecId 悬空（已不写出）：{dict(aec_dangling)}")
    if foreign_drops:
        print(f"丢弃跨条目误配段 {len(foreign_drops)}：")
        for line in foreign_drops:
            print(f"  - {line}")
    if variant_gaps:
        print(f"⚠ 有战技命中但选不出动作套的武器 {len(variant_gaps)}：{variant_gaps[:10]}")
    if tae_verified:
        tc = tae_diagnostics["counts"]
        print(f"TAE 核实：检查 (战技, 武器) 对 {tc['skillWeaponPairsChecked']}（去重判定 {tc['distinctChecks']} 次），"
              f"段有变化的对 {tc['skillWeaponPairsChanged']}、战技 {tc['skillsChanged']}；"
              f"移除武器×段 {tc['weaponHitsRemoved']} {tc['weaponHitsRemovedByStatus']}")
        print(f"  所有武器上都打不出、已标 notInvoked 的段 {hits_not_invoked}（带伤害 {hits_not_invoked_damaging}）"
              f"{tc['hitsNotInvokedByReason']}；只在部分武器上打不出的段 {len(partial_list)}")
        for r in removed_list:
            print(f"  - {r['skillId']} {r['nameZh']} {r['atkId']} {r.get('label', '')} → {r['notInvokedReason']}"
                  f"（{r['weapons']} 把）{r['reasonZh']}")
        for r in partial_list:
            print(f"  ~ {r['skillId']} {r['nameZh']} {r['atkId']} {r.get('label', '')}：保留 {r['keptOnWeapons']} 把、"
                  f"移除 {r['removedOnWeapons']} 把 {r['reasons']}")
        for b in tae_diagnostics["exclusiveBlocks"]:
            print(f"  互斥动画套 {b['skillId']} {b['nameZh']}：{b['chosenBlockWeapons']}")
        print(f"  动画匹配不到、不过滤的战技 {len(tae_unmatched)}：{tae_unmatched}")
        if tae_empty:
            print(f"⚠ TAE 后一段都不剩、保持行为表口径的 (战技, 武器) {len(tae_empty)}：{tae_empty[:10]}")
        if split_after_tae:
            print(f"  TAE 核实后同类别武器分到不同 variant 的战技：{split_after_tae}")
        print(f"  带 FP / 无 FP 分支（4xxxx 个位 5–9 = 无 FP 版）：TAE 补标 noFp {len(no_fp_tae)} 段"
              f"（带伤害 {no_fp_tae_damaging}，{len({r['skillId'] for r in no_fp_tae})} 个战技），"
              f"两侧共用标 fpBoth {len(fp_both_list)} 段，行名 No FP 与 TAE 冲突 {len(no_fp_conflicts)} 段")
    else:
        print(f"⚠ 未做 TAE 核实：{tae_skip_reason}（counts.taeVerified=false）")
    print(f"AtkParam 行名匹配 {stats['atkRowsMatched']}，未匹配 {stats['atkRowsUnmatched']}；"
          f"Bullet 行名匹配 {stats['bulletRowsMatched']}")
    if unnamed_weapon_type:
        print(f"未知 wepType：{dict(unnamed_weapon_type)}")
    if ambiguous:
        print(f"同名歧义行 {len(ambiguous)} 条（已同时归给多个条目），例：{ambiguous[:3]}")
    if skills_missing:
        print(f"没有任何命中的战技 {len(skills_missing)}：")
        for name in skills_missing:
            print(f"  - {name}")
    if spells_missing:
        print(f"没有任何命中的法术 {len(spells_missing)}：")
        for name in spells_missing:
            print(f"  - {name}")


# ------------------------------------------------------------------ self_check
def self_check(payload: dict, custom_by_id: dict[str, dict], reachable: set[str],
               pre_sel: dict[tuple[int, int], frozenset[str]], magic_table_rows: list[dict]) -> None:
    """生成后立刻校验 v3 的战技池字段、法术可施放口径与 TAE 核实结果（任何一条不成立都直接中止，不写文件）。
    pre_sel：行为表层（TAE 核实前）每个 (战技, 武器) 解出的段；magic_table_rows：原始 MagicTableParam。"""
    assert payload["schemaVersion"] == SCHEMA_VERSION == 3, payload["schemaVersion"]
    assert [c["version"] for c in payload["schemaChangelog"]] == [1, 2, 3]
    weapons = {w["id"]: w for w in payload["weapons"]}
    skills = {s["id"]: s for s in payload["skills"]}
    pools = payload["swordArtsPools"]

    # 无名测试行（100000–101000，wepType 3、rarity 0、没有 WeaponName）不收录
    assert not any(100000 <= wid <= 101999 for wid in weapons), "无名测试武器行混进了 weapons[]"
    assert all(w["nameZh"] and w["nameEn"] for w in weapons.values())

    # 池：条目权重 > 0，每个池都被某把武器的 customWeapons 引用
    referenced_tables = {t for w in weapons.values() for _c, t in w.get("customWeapons", ())}
    for pid, entries in pools.items():
        assert entries and all(wt > 0 for _a, wt in entries), pid
        assert int(pid) in referenced_tables, f"池 {pid} 没有可达 custom 行引用"
        assert len({a for a, _w in entries}) == len(entries), f"池 {pid} 有重复战技"

    # customWeapons 能逐行回溯到原始参数表，且都可达
    for wid, w in weapons.items():
        rows = w.get("customWeapons", [])
        assert rows == sorted(rows), wid
        for cid, table in rows:
            raw = custom_by_id.get(str(cid))
            assert raw is not None, (wid, cid)
            assert str(cid) in reachable, (wid, cid)
            assert int(raw["targetWeaponId"]) == wid, (wid, cid)
            assert int(raw["swordArtsTableId"]) == table, (wid, cid)
            assert table == -1 or str(table) in pools, (wid, cid, table)

    pairs_from_skills: set[tuple[int, int]] = set()
    for sid, sk in skills.items():
        srcs = sk["weaponSources"]
        assert [src["id"] for src in srcs] == sk["weaponIds"] == sorted(set(sk["weaponIds"])), sid
        for src in srcs:
            wid = src["id"]
            w = weapons[wid]
            pairs_from_skills.add((sid, wid))
            assert src.get("fixed") or src.get("pool"), (sid, wid)
            assert bool(src.get("fixed")) == (w["swordArtsParamId"] == sid), (sid, wid)
            for table, weight, n_rows in src.get("pool", ()):
                assert [sid, weight] in pools[str(table)], (sid, wid, table, weight)
                backing = [cid for cid, t in w.get("customWeapons", ()) if t == table]
                # pool 项必须回溯到具体的可达 custom 行，行数一致
                assert n_rows >= 1 and n_rows == len(backing), (sid, wid, table, n_rows, backing)
        # variants：武器分组不重不漏（只含 weaponIds 里的武器），段都在 hits 里，下标与武器侧一致
        hit_ids = {h["atkId"] for h in sk["hits"]}
        seen: set[int] = set()
        for idx, v in enumerate(sk.get("variants", ())):
            assert set(v["atkIds"]) <= hit_ids, (sid, idx)
            for wid in v["weaponIds"]:
                assert wid in sk["weaponIds"] and wid not in seen, (sid, wid)
                seen.add(wid)
                assert weapons[wid]["skillVariants"][str(sid)] == idx, (sid, wid, idx)
        # 同一战技里同一武器类别只落进一套动作（三级回退后的实测规律，行为表层；TAE 核实后可因动作组 TAE 再细分）
        by_type: dict[int, set[frozenset]] = defaultdict(set)
        for idx, v in enumerate(sk.get("variants", ())):
            for wid in v["weaponIds"]:
                by_type[weapons[wid]["wepType"]].add(pre_sel[(sid, wid)])
        assert all(len(ix) == 1 for ix in by_type.values()), (sid, {t: len(x) for t, x in by_type.items()})

    pairs_from_weapons = {(sid, wid) for wid, w in weapons.items() for sid in w["skillIds"]}
    assert pairs_from_skills == pairs_from_weapons, (
        sorted(pairs_from_skills ^ pairs_from_weapons)[:10])
    for wid, w in weapons.items():
        assert w["skillIds"] == sorted(set(w["skillIds"])), wid
        for key, idx in w.get("skillVariants", {}).items():
            assert int(key) in w["skillIds"], (wid, key)
            assert wid in skills[int(key)]["variants"][idx]["weaponIds"], (wid, key)
        if "skillVariant" in w:
            assert w["skillVariants"][str(w["swordArtsParamId"])] == w["skillVariant"], wid

    # 这次修的两个热门战技：v2 没有任何武器，v3 全部来自战技池
    for sid in (210, 116):
        sk = skills[sid]
        assert sk["weaponIds"], f"{sid} 仍然没有武器"
        assert all(src.get("pool") and not src.get("fixed") for src in sk["weaponSources"]), sid
        assert sk.get("variants"), f"{sid} 没有解出动作套"
    assert skills[100]["weaponIds"]
    storm_ruler = skills[1200]
    assert len(storm_ruler.get("variants", ())) == len(storm_ruler["weaponIds"]) == 10, "风暴管束者应每个角色一套"

    # ---- v3 修订：法术只收可施放的 -------------------------------------------------
    spells = {sp["id"]: sp for sp in payload["spells"]}
    magic_pools = payload["magicPools"]
    counts_ = payload["counts"]
    not_castable = {e["id"]: e for e in payload["coverage"]["spellsNotCastable"]}
    # 用户点名的风暴管束者：Magic 8100 / 8101 是本体遗留的死行，不是玩家法术；本作的风暴管束者是战技 1200
    for magic_id in (8100, 8101):
        assert magic_id not in spells, f"{magic_id} 风暴管束者不应在 spells 里"
        e = not_castable[magic_id]
        assert e["magicTablePools"] == [] and e["sameNameSkillIds"] == [1200] and "残留" in e["reason"], e
    assert 1200 in skills and skills[1200]["nameZh"] == not_castable[8100]["nameZh"] and skills[1200]["weaponIds"]
    assert set(spells).isdisjoint(not_castable)
    assert counts_["spells"] == len(spells) == counts_["spellsCastable"], (counts_["spells"], counts_["spellsCastable"])
    assert counts_["spellsDropped"] == len(not_castable) and counts_["spellsNamed"] == len(spells) + len(not_castable)
    assert counts_["magicPools"] == len(magic_pools)
    assert counts_["magicPoolEntries"] == sum(len(v) for v in magic_pools.values())
    assert counts_["spellsWithHits"] == sum(1 for sp in spells.values() if sp["hits"])
    spell_info = payload["diagnostics"]["spellCasting"]
    assert not spell_info["castableButUnnamed"], spell_info["castableButUnnamed"]
    # 池内容与 MagicTableParam 原表一致（同 ID = 一池、只收正权重、重复行权重相加）
    raw_pools: dict[str, dict[int, int]] = defaultdict(dict)
    for row in magic_table_rows:
        m, wt = int(row["magicId"]), int(row["chanceWeight"])
        if m > 0 and wt > 0:
            raw_pools[row["ID"]][m] = raw_pools[row["ID"]].get(m, 0) + wt
    referenced_magic_tables = {t for w in weapons.values() for _c, t1, t2 in w.get("customMagicTables", ())
                               for t in (t1, t2) if t != -1}
    assert {int(p) for p in magic_pools} == referenced_magic_tables, sorted(referenced_magic_tables ^ {int(p) for p in magic_pools})
    for pid, entries in magic_pools.items():
        assert entries and all(wt > 0 for _m, wt in entries), pid
        assert len({m for m, _w in entries}) == len(entries), f"法术池 {pid} 有重复条目"
        assert dict((m, wt) for m, wt in entries) == raw_pools[pid], pid
    # 权重 0 的行抽不到：不进 magicPools，且它们的 magicId 都另有正权重来源（所以不影响可施放集合）
    assert payload["counts"]["magicPoolZeroWeightRows"] == len(spell_info["zeroWeightRowsInUsedPools"])
    for z in spell_info["zeroWeightRowsInUsedPools"]:
        pid, m = z["pool"], z["magicId"]
        assert str(pid) in magic_pools and m not in {mm for mm, _w in magic_pools[str(pid)]}, z
        assert m in spells, z
        if z["inOtherSlotPool"]:
            assert all(m in {mm for mm, _w in magic_pools[str(p)]} for p in z["otherSlotPools"]), z
    # zeroWeightNote 里举的例子
    assert magic_pools["3300000"] == [[4000, 100]] and [33000000, 3300000, 3300100] in weapons[33000000]["customMagicTables"]
    assert any(z["pool"] == 3300100 and z["magicId"] == 4000 and z["inOtherSlotPool"]
               for z in spell_info["zeroWeightRowsInUsedPools"])
    # customMagicTables 逐行回溯到原始 custom 行
    for wid, w in weapons.items():
        rows = w.get("customMagicTables", [])
        assert rows == sorted(rows), wid
        for cid, t1, t2 in rows:
            raw = custom_by_id.get(str(cid))
            assert raw is not None and str(cid) in reachable, (wid, cid)
            assert int(raw["targetWeaponId"]) == wid, (wid, cid)
            assert (int(raw["magicTableId_1"]), int(raw["magicTableId_2"])) == (t1, t2), (wid, cid)
            assert t1 != -1 or t2 != -1, (wid, cid)
    # 每个法术至少一把施法器；casterSources 可回溯到 custom 行，且反过来施法器池里的每个法术都列了这把武器
    spell_pairs: set[tuple[int, int]] = set()
    for sid, sp in spells.items():
        srcs = sp["casterSources"]
        assert sp["casterWeaponIds"], f"法术 {sid} 没有施法器"
        assert [s["id"] for s in srcs] == sp["casterWeaponIds"] == sorted(set(sp["casterWeaponIds"])), sid
        for src in srcs:
            wid = src["id"]
            assert set(src) == {"id", "pool"} and src["pool"], (sid, wid)
            spell_pairs.add((sid, wid))
            for table, weight, n_rows in src["pool"]:
                assert [sid, weight] in magic_pools[str(table)], (sid, wid, table, weight)
                backing = [cid for cid, t1, t2 in weapons[wid].get("customMagicTables", ()) if table in (t1, t2)]
                assert n_rows >= 1 and n_rows == len(backing), (sid, wid, table, n_rows, backing)
    pairs_from_pools = {(m, wid) for wid, w in weapons.items() for _c, t1, t2 in w.get("customMagicTables", ())
                        for t in (t1, t2) if t != -1 for m, _wt in magic_pools[str(t)]}
    assert spell_pairs == pairs_from_pools, sorted(spell_pairs ^ pairs_from_pools)[:10]
    assert counts_["spellWeaponPairs"] == len(spell_pairs)
    assert counts_["casterWeapons"] == sum(1 for w in weapons.values() if w.get("customMagicTables"))
    # 施法器都是手杖（57）或圣印记（61）
    assert {weapons[wid]["wepType"] for sp in spells.values() for wid in sp["casterWeaponIds"]} <= {57, 61}

    # ---- TAE 核实 ---------------------------------------------------------------
    counts = payload["counts"]
    verified = counts["taeVerified"]
    diag = payload["diagnostics"]["taeVerification"]
    assert diag["verified"] == verified
    reasons = payload["enums"]["notInvokedReason"]
    n_not_invoked = n_unmatched = 0
    for sid, sk in skills.items():
        variants = sk.get("variants", ())
        in_variants = {a for v in variants for a in v["atkIds"]}
        pre_cov = {int(a) for (s_, w), atks in pre_sel.items() if s_ == sid for a in atks}
        if sk.get("taeUnmatched"):
            assert verified and sk["taeUnmatched"] is True, sid
            n_unmatched += 1
        for idx, v in enumerate(variants):
            assert v["atkIds"], (sid, idx, "空 variant")
            for wid in v["weaponIds"]:
                pre = {int(a) for a in pre_sel[(sid, wid)]}
                post = set(v["atkIds"])
                assert post <= pre, (sid, wid, sorted(post - pre))   # TAE 只删不增
                if not verified or sk.get("taeUnmatched"):
                    assert post == pre, (sid, wid)                    # 没核实 / 匹配不到时不动
        for h in sk["hits"]:
            a = h["atkId"]
            if h.get("notInvoked"):
                n_not_invoked += 1
                assert verified and not sk.get("taeUnmatched"), (sid, a)
                assert h["notInvokedReason"] in reasons, (sid, a, h.get("notInvokedReason"))
                assert a not in in_variants and a in pre_cov, (sid, a)
                assert not h.get("noVariant"), (sid, a, "noVariant 与 notInvoked 互斥")
            else:
                assert "notInvokedReason" not in h, (sid, a)
                if variants:
                    # 行为表选到过、TAE 后哪都没留下的段必须标 notInvoked；行为表就没选到的必须标 noVariant
                    assert (a in in_variants) or (a not in pre_cov and h.get("noVariant")), (sid, a)
    assert n_not_invoked == counts["hitsNotInvoked"] == len(diag["removedHits"]), (n_not_invoked, counts["hitsNotInvoked"])
    assert n_unmatched == counts["skillsTaeUnmatched"]
    if verified:
        # 用户点名的狩猎大蛇：本作只打出两段近战与各自的无 FP 版，Beam of Light 两段是 187 门控
        serpent = skills[1188]
        assert [v["atkIds"] for v in serpent["variants"]] == [[301703950, 301703951, 301703970, 301703971]], serpent["variants"]
        by_atk = {h["atkId"]: h for h in serpent["hits"]}
        assert by_atk[301703900].get("notInvokedReason") == by_atk[301703901].get("notInvokedReason") == "gated"
        assert by_atk[301703955].get("notInvokedReason") == "roarR2Only"
        assert all(by_atk[a].get("notInvoked") for a in (301703905, 301703975))
        # 互斥动画套：二连斩的默认套（3170 系）与 Large Weapon 套（3185 系）不再出现在同一个 variant 里
        for v in skills[112].get("variants", ()):
            assert not ({300000170, 300000185} <= set(v["atkIds"])), v["atkIds"]
        assert not any(sk.get("taeUnmatched") for sk in skills.values() if sk["id"] in (210, 116, 1188))

        # ---- 审查修正：带 FP / 无 FP 分支按 TAE 补标 ----
        # 用户点名的风暴刃：a659 的 40000/40010/40020 打 407/408/409 + 飞刃 410，40005/40015/40025 打 411/412/413；
        # 狩猎巨人：a616 的 40000 打 301700910，40005 打 301700915。无 FP 段必须标 noFp，带 FP 段不能标。
        def hit_of(sid: int, atk: int) -> dict:
            return next(h for h in skills[sid]["hits"] if h["atkId"] == atk)
        for sid, no_fp_atks, fp_atks in ((210, (300000411, 300000412, 300000413), (300000407, 300000408, 300000409, 300000410)),
                                         (116, (301700915,), (301700910,))):
            for a in no_fp_atks:
                h = hit_of(sid, a)
                assert h.get("noFp") and h.get("noFpSource") == "tae", (sid, a, h)
                assert h["labelZh"].startswith("无FP版"), (sid, a, h.get("labelZh"))
            for a in fp_atks:
                h = hit_of(sid, a)
                assert not h.get("noFp") and not h.get("fpBoth"), (sid, a, h)
            # 默认（带 FP 侧）取段不再混进无 FP 段
            for v in skills[sid]["variants"]:
                fp_side = [a for a in v["atkIds"] if not hit_of(sid, a).get("noFp")]
                assert not set(fp_side) & set(no_fp_atks), (sid, v["atkIds"])
        assert not diag["noFpConflicts"], diag["noFpConflicts"]
        assert counts["hitsNoFpByTae"] == diag["counts"]["hitsNoFpByTae"] == len(diag["noFpFromTae"])
        assert counts["hitsFpBoth"] == diag["counts"]["hitsFpBoth"] == len(diag["fpBoth"])

        # fieldNotes.notInvoked 的「只在部分武器上打不出」例子必须与数据一致：二连斩 Large Weapon 套 300000185–196
        # 只留给大剑 / 大曲剑，其余武器按 exclusiveBlock 移除；野蛮咆哮的 4 段 var 0 行在全部武器上都被移除。
        partial = {(r["skillId"], r["atkId"]): r for r in diag["partiallyRemoved"]}
        for a in range(300000185, 300000197):
            r = partial[(112, a)]
            assert set(r["reasons"]) == {"exclusiveBlock"}, r
            kept_types = {weapons[w]["wepType"] for v in skills[112]["variants"] if a in v["atkIds"] for w in v["weaponIds"]}
            assert kept_types == {5, 11}, (a, kept_types)
        roar = {h["atkId"]: h for h in skills[650]["hits"]}
        for a in (300000957, 300000959, 300000967, 300000969):
            assert roar[a].get("notInvoked") and (650, a) not in partial, (a, roar[a])
        assert "300000185–300000196" in payload["fieldNotes"]["notInvoked"], payload["fieldNotes"]["notInvoked"]
    else:
        assert not diag["removedHits"] and not diag["partiallyRemoved"]

    # ---- 审查修正：带 FP / 无 FP 标记与只打自己 / 队友的行（与是否做 TAE 核实无关的不变式）----
    for entry in list(skills.values()) + payload["spells"]:
        for h in entry["hits"]:
            if h.get("noFp"):
                # 三端测试依赖：数据集原文里 noFp 段的 labelZh 一律以「无FP版」开头
                assert h.get("labelZh", "").startswith("无FP版"), (entry["id"], h["atkId"], h.get("labelZh"))
            if "noFpSource" in h:
                assert verified and h["noFp"] and h["noFpSource"] == "tae", (entry["id"], h["atkId"])
            if h.get("fpBoth"):
                assert verified and not h.get("noFp"), (entry["id"], h["atkId"])
            if h.get("selfOrAllyOnly"):
                assert h.get("noDamage"), (entry["id"], h["atkId"])
    # 祈祷一击：回血子弹 1202100（Heal Self）/ 1202110（Heal Others）只打自己 / 队友，不算伤害；主段照常算
    prayer = {h["atkId"]: h for h in skills[208]["hits"]}
    for a in (1202100, 1202110, 1202105):
        assert prayer[a].get("selfOrAllyOnly") and prayer[a].get("noDamage"), (a, prayer[a])
    assert any(not h.get("noDamage") and (h.get("motion") or h.get("flat")) for h in prayer.values()), prayer
    removed_damaging = sum(1 for r in diag["removedHits"] if r["damaging"])
    assert removed_damaging == counts["hitsNotInvokedDamaging"], (removed_damaging, counts["hitsNotInvokedDamaging"])
    assert not any(r["damaging"] for r in diag["removedHits"] if r["skillId"] == 208 and r["atkId"] == 1202105)

    assert counts["weaponSkillPairs"] == len(pairs_from_skills)
    assert counts["skillsWithWeapons"] == sum(1 for sk in skills.values() if sk["weaponIds"])
    assert counts["swordArtsPools"] == len(pools)
    cov = payload["coverage"]
    assert len(cov["skillsWithoutWeapons"]) == sum(1 for sk in skills.values() if not sk["weaponIds"])
    assert (len(cov["skillsWithoutFixedWeapons"]) - len(cov["skillsWithoutWeapons"])
            == len(cov["skillsPoolOnly"]) == counts["skillsPoolOnly"])


if __name__ == "__main__":
    main()
