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

Loadout slots and per-output applicability (schema v6)
------------------------------------------------------
The ranking page assembles a run loadout slot by slot, so every buff also says

  sourceSlot / sourceSlots   which column it belongs to: weaponAffix (in-run
                             armament passives, AttachEffectParam rows pooled
                             through EquipParamCustomWeapon.attachEffectTableId_1..6),
                             relicAffix (EquipParamAntique pools), accessory,
                             consumable, spellBuff, weaponSkill, weaponInnate,
                             character, permanent, runStack, other
  appliesTo / appliesToDetail  yes / no / conditional for skill, sorcery,
                             incantation, melee, ranged, throw -- derived from
                             wepParamChange / magParamChange / miracleParamChange
                             / throwAttackParamChange, triggerOnWepType,
                             stateInfo and magicSubCategoryChange1..3 checked
                             against the *measured* sub-categories of every
                             skill / spell hit (data/nightreign-skills-v1.03.5.json
                             + AtkParam_Pc + Magic.subCategory1..2)
  relicAffixes[]             catalog alignment with
                             data/nightreign-affixes-v1.03.4.json
  weaponAffixIds, stackInput, suggestedNameZh, scope.weaponTypes ...

plus the top-level slotRules (every number measured from params and asserted
in self_check), weaponAffixes, weaponAffixPools, fixedRelics and attackIndex.
v6 also fixes scope.attackContexts: magicSubCategoryChange1..3 is an OR list,
so [112 Skill Attack, 111 Charged Skill Attack] is *not* a charged-only gate.

A verification round on v6 added: the deep-only cap (each Deep-of-Night
weapon holds at most one affix that no slot-1..3 pool offers, so 6 across
six weapons, measured per EquipParamCustomWeapon row); the blessing role by
pool family (81x + the 603000x00 pools of the [Unique] X+2 hero weapons);
weaponInnate on every innate buff (weapon ids from EquipParamWeapon, the
[Weapon Power] rows matched to their legendary AE); PermanentBuffInfo as the
descZh of permanent / run-stack buffs (8970000 counts *newly found Sites of
Grace*, not bosses); and a Chinese-only displayNameZh -- the disambiguation
detail is the row name rendered from game text, never the English row name,
asserted in self_check.  BehaviorParam_PC is read for a melee-population
cross-check only (diagnostics.meleePopulationCheck).

A second verification round added stacking.exclusiveKey / exclusiveScope,
the key a page de-duplicates on: spCategory 20 ("Reset on Apply") is a
same-id rule, so it is per SpEffect like none / stackSelf (stacking.group
had merged all 77 of them); 200..299 is scoped by categoryPriority (every
saved ladder in 204, every cracked tear in 201 owns a priority); accumulator
ladders (accumuOverFireId tiers of the successive-attack talismans) share one
key and carry buffs[].accumulatorLadder.  Also: weaponAffixDeepOnlyPositive
(the deep-only cap does not count curses), 7020002 / 7020004 filed under
relic affix 7020000, stateInfo 197 (thrusting counter) is no for spells and
bows, and displayNameZh uses 「第N层」 / 「永久强化」 / the owning affix's
potency before falling back to #spEffectId.

A third round: the four potency rows of each 『出击时的武器，附加…』 relic
affix (7120001..7120004 ...), which the affix's own dispatcher row
(stateInfo 2101) picks from by starting-weapon type, share one key
"affix#<attachEffectId>" (exclusiveScope affixVariant, buffs[].affixVariant,
diagnostics.affixVariantScan); relicAffixes[].exclusivityId; the three
coexisting guard stages of weapon affix 8885200 (accumulator -> behavior ->
bullet -> buff, buffs[].accumulatorStages); accumulatorLadder
.shippedTierSpEffectIds and notes.accumulatorLadder (tierSpEffectIds
includes tier 1, the opposite of stackLadder; "sp120" makes the
successive-attack items exclusive of each other); the Self / Allies rows of
one cast (buffs[].selfAllyPair); "Stack N" rows read 「第N层」.

Sources (all local, exported beforehand; nothing is fetched at run time)
-----------------------------------------------------------------------
  raw/params/*.csv        regulation 1.03.5 (container 10350000), first column
                          ID, second column Name = community Paramdex row name
  raw/msg/<lang>/<bnd>_dlc01/<Fmg>.json   zhocn + engus, base + _dlc01 merged
  Paramdex field defaults / enums  vawser/Smithbox @ f5969c06 (NR ParamMeta,
                          Param Enums) and the Elden Ring paramdef for the
                          Japanese field descriptions -- both transcribed into
                          the tables below so this script stays offline.
  ../../data/nightreign-affixes-v1.03.4.json, nightreign-relics-v1.03.4.json,
  nightreign-skills-v1.03.5.json   read-only (v6): relic catalog alignment and
                          the skill / spell hit lists behind appliesTo.  Run
                          generate_skills.py first when the skills change.

Run:  cd macos/DataSources && python3 generate_buffs.py
"""

from __future__ import annotations

import argparse
import csv
import json
import re
from collections import Counter, OrderedDict, defaultdict
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
PARAM_DIR = HERE / "raw" / "params"
MSG_DIR = HERE / "raw" / "msg"
DEFAULT_OUT = ROOT / "data" / "nightreign-buffs-v1.03.5.json"

SCHEMA_VERSION = 6
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
        "version": 6,
        "zh": "为『增伤排名』改成按槽位组装（局内武器词条／遗物／护符／道具／法术／局内叠层…）而加的字段；"
              "只增字段、只增取值，没有改名或删字段。"
              "① **新增 buffs[].sourceSlot／sourceSlots／sourceSlotReason** 与 enums.sourceSlot（11 种）："
              "v5 的 sources[].kind 把所有进了 AttachEffectTableParam 池的 AttachEffectParam 行都叫 relicAffix，"
              "局内武器词条（8100000–8889999，经 EquipParamCustomWeapon 挂到武器上）与遗物词条分不开。"
              "sourceSlot 按词条真正所在的池判：EquipParamAntique 的池＝relicAffix、可掉落的 EquipParamCustomWeapon 行"
              "引用的池＝weaponAffix、EquipParamWeapon.attachEffectId＝weaponInnate。任务清单外新增 weaponSkill"
              "（战技发动后的自身增益）与 weaponInnate（武器固有效果）。sources[].kind 口径不变。"
              "② **新增 buffs[].appliesTo（skill／sorcery／incantation／melee／ranged／throw → yes／no／conditional）"
              "与 appliesToDetail（reason／requires／matchShare）**，配套 enums.outputClass／appliesToValue、"
              "顶层 attackIndex（各类输出的实测子类别人口）、counts.appliesToByOutput。页面不再需要按 scope 猜。"
              "③ **修正 scope.attackContexts 的推导（值变化，5 条）**：magicSubCategoryChange1..3 是『命中任一即生效』，"
              "只有全部子类别都是情境类才构成限制。312300／7006700／8350000／8350001／8350002『提升战技攻击力』"
              "的 [112, 111] 在 v4/v5 被标成 attackContexts=[\"chargedSkill\"]，页面因此把它们藏到『蓄力战技』后面；"
              "v6 删除这 5 条的 attackContexts（diagnostics.droppedAttackContexts），counts.buffsWithAttackContext 60→55、"
              "buffsByAttackContext.chargedSkill 6→1；diagnostics.contextGatedMultipliers 里抄录的这 5 条同样没有了 attackContexts 键。"
              "④ **局内武器词条**：buffs[].weaponAffixIds／weaponAffixRoles／weaponAffixDeepOnly、scope.rollableWeaponTypes，"
              "顶层 weaponAffixes（按词条列出常规／深夜可出现的 wepType）与 weaponAffixPools；"
              "**遗物**：buffs[].relicAffixes[]（catalogEffectId 对齐词条库、isDeepRelicAffix／requiresCurse／isCurse／"
              "compatibilityId／inNormalRelicPools／fixedRelicOnly）与顶层 fixedRelics（官方固定词条遗物 120 种）；"
              "顶层 slotRules（武器 6 把、常规每把 1 条、深夜诅咒武器每把 2 条＋1 条诅咒；遗物 3＋3、每件 3 条；护符 2 个），"
              "数字附实测依据。"
              "⑤ **新增 scope.weaponTypes**（{mode: attackWith|equippedCount, wepTypes, namesZh, count?}）与 "
              "scope.attachedWeaponOnly（本版本 0 条），enums.wepType（中文取自 CL_MenuText）。"
              "⑥ **新增 buffs[].stackInput**（5 条：封印监牢、黑夜入侵者、玛雷家的庇佑、复仇的庇佑、赐福王的余威）"
              "与 enums.stackInputMode；activationSource 新增取值 stackInputRequired。"
              "**值变化（1 条）**：8970000『赐福王的余威』activation passive→conditional、activationSource noEvidence→"
              "stackInputRequired（一局开始是 0 层，不得默认乘进排名）；counts.buffsByActivation passive 354→353、"
              "conditional 363→364。"
              "⑦ **名字**：nameSource 新增取值 permanentBuffNameById（本版本 2 条：8161600『提升长矛攻击力』、"
              "8390000『强化投掷壶』在 PermanentBuffName 里有同 ID 的游戏文本；8390000 在 AttachEffectName 里也有同一文本，"
              "按 PermanentBuffName 优先记）与 attachEffectNameById（备用：PermanentBuffName 没有同 ID 文本时才取 AttachEffectName，"
              "本版本 0 条）；这 2 条 nameZh／nameEn 由 null／英文行名改为游戏文本（counts.buffsWithoutChineseName 82→80）。"
              "其余 80 条无任何自身文本的新增 suggestedNameZh（＋suggestedNameZhSource／suggestedNameZhInferred），displayNameZh 改用它；"
              "脚本挂载的战技来源新增 sources[].artsNameZh／artsId（90 条 buff；『Barbaric/Milos Roar』这类『A/B C』行名拆开查 ArtsName）。"
              "displayNameZh 的消歧限定词不再用英文 Paramdex 行名，改用行名的中文拼写（所属词条名／战技名／角色技艺・绝招・能力名／"
              "道具与 SpEffect 名＋TAIL_PHRASES_ZH），拼不全就落到『#spEffectId』。"
              "**displayNameZh 变 180 条**：v5 有 150 条 displayNameZh 带英文，现在 0 条（80 条改用建议名、2 条用同 ID 文本、"
              "68 条的英文限定词换成中文）；另有 26 条补写了战技名，1940 不再显示武器名『短弓』而是『短弓等13把武器的固有效果：黄金箭』，"
              "3 条因消歧重排而变化（322100 多了来源限定词、1660000 少了倍率限定词、1722000 多了类别限定词）。"
              "displayNameEn 变 4 条（8161600、8390000 换成游戏英文名，322100 因与 8390000 同名补了来源，1940 同上改写）；"
              "唯一性保证不变，新增 self_check：displayNameZh 除 NPC／HP／FP 外不得有拉丁字母。"
              "diagnostics.selfInflictedStatus／topUnconditionalMultipliers／contextGatedMultipliers 里抄录的 displayNameZh 随之变化。"
              "⑧ notes 新增 userQuestions（Q1–Q5 的参数依据）、sourceSlot、appliesTo、weaponAffix、relicAffix、stackInput、"
              "suggestedName。"
              "⑨ **核验补充**（仍是 v6，只增字段）："
              "slotRules.weaponAffix 新增 deepOnlyPerWeaponMax=1／maxDeepOnlyAffixes=6（每把深夜诅咒武器的 2 条正面词条里最多 1 条"
              "是深夜专属词条，2950 行实测）、slotRules.modes.*.deepOnlyAffixesPerWeapon，evidence 新增 deepOnlyPositiveSlotsPerRow／"
              "deepOnlyAttachEffectIds／distinctAttachEffectIdsInReachablePools／slotLayouts／blessingPools／blessingPoolsBySubsetOf81x；"
              "weaponAffixRoles 的 blessing 改按池族判（81x＋成员是其子集的 603000x00），"
              "『[Unique] X+2』角色武器的 603 池由 affix 改为 blessing（weaponAffixPools 3 个、weaponAffixes 16 个、buffs 24 条的 roles 变化）；"
              "buffs[].weaponInnate 扩到全部 42 条 sourceSlots 含 weaponInnate 的条目，新增 wepTypes／inferredFromRowName／rowCategory，"
              "[Weapon Power] 行按同百位 SpEffect＋同名前缀归到庇佑 AE（8980002 等 → 9021400『夜与火的庇佑』）；"
              "7050301『道具效用能扩及我方人物（勇者肉块）』归到遗物词条 AE 7050100（relicAffixes），sourceSlots 加 consumable，"
              "新增 buffs[].requiresGoodsIds；permanent／runStack 条目新增 descZh（取 PermanentBuffInfo，9 条）与 descZhSource；"
              "8970000『赐福王的余威』的层数单位改为『本局新发现的赐福数』（PermanentBuffInfo#8970000），不是打倒的首领数；"
              "顶层 sources[] 的新条目移到末尾（v5 的 4 条位置不变）；"
              "新增 diagnostics.displayNameZhLatinResidue／displayNameZhDetailUntranslated／displayNameZhDetailNote／"
              "displayNameZhWeaponNamed／weaponInnateWithoutWeaponIds(+Note)／meleePopulationCheck(+Note)，"
              "counts.buffsWithWeaponInnate／buffsWithRequiresGoodsIds／buffsWithDescZhSource。"
              "⑩ **复核二轮**（仍是 v6，只增字段；取值变化逐条如下）："
              "(a) **新增 buffs[].stacking.exclusiveKey／exclusiveScope 与 enums.exclusiveScope**——页面去重应改用它："
              "perSpEffect（none／stackSelf／resetOnApply…按 ID）、category（removePrevious 100–199、applyHighest、applyFirst 按类别）、"
              "categoryPriority（200–299 按类别＋categoryPriority）、accumulatorLadder（连续攻击类累积阶梯各档共用一键）；"
              "新增 buffs[].accumulatorLadder（15 条：连刺破露滴 3558–3561、米莉森的义手 312505–312508、带翼剑徽章 320804–320807、"
              "遗物『连续攻击时，提升攻击力』7037604–7037606）与 diagnostics.exclusiveKeyEvidence(+Note)／accumulatorLadderConflicts、"
              "counts.buffsByExclusiveScope／exclusiveKeys／exclusiveKeysShared／buffsWithAccumulatorLadder。"
              "**值变化**：stacking.group 对 spCategoryBehavior=resetOnApply 的 77 条由 \"sp20\" 改为 \"sp20#<spEffectId>\""
              "（spCategory 20＝Paramdex『Reset on Apply』，是同一效果重复获得的规则，不是跨 ID 互斥；v6 之前 77 条互不相干的遗物／护符／"
              "战技增益被并成一组、只剩一条）；enums.spCategoryBehavior 的 resetOnApply 与 removePrevious 说明文字；stackingRules 第 1、2 条。"
              "(b) **7020002／7020004**（追踪者遗物『发动技艺时，轻攻击能使出缠绕火焰的追加攻击』的火属性 +20 右／左手，descZh『遗物带来的效果』）"
              "归到遗物词条 AE 7020000：sourceSlot／sourceSlots character→relicAffix，新增 relicAffixes；fixedRelics『深灰色砥石』的 spEffectIds "
              "加上这 2 条；counts.buffsBySourceSlot character −2／relicAffix +2、buffsWithRelicAffixes 256→258。"
              "(c) **深夜专属上限只数正面词条**：新增 buffs[].weaponAffixDeepOnlyPositive（152 条有值、30 条 true）、weaponAffixes[].deepOnlyPositive、"
              "slotRules.weaponAffix.deepOnlyCapField／deepOnlyCapCountsCurses／duplicateWithinWeapon（同一把武器两条正面词条能否相同：未知），"
              "evidence 新增 deepOnlyPositiveAttachEffectIds（52）／deepOnlyCurseAttachEffectIds（44）／deepOnlyPositivePotencyByPoolFamily／"
              "potencyCountsByPoolTier／deepPositivePairRows／deepPositivePairRowsWithSharedAffix；weaponAffixDeepOnly／deepOnly 的取值不变"
              "（诅咒仍为 true），上限的说明文字改为只数正面词条。"
              "(d) **stateInfo=197（强化突刺反击）**：320600、7034702、8430000、8851800、8851850 的 appliesTo.sorcery／incantation／ranged "
              "conditional→no（矛护符 AccessoryInfo#2060『能强化突刺攻击特有的反击攻击』），这 15 处的 appliesToDetail.reason 改写、requires 随之消失；"
              "counts.appliesToByOutput 三类各 conditional −5／no +5。"
              "(e) **displayNameZh 变 55 条、displayNameEn 变 45 条**：累积阶梯 15 条各档写『第N层』（其中 11 条原来落到『#spEffectId』）；"
              "只由 PermanentBuffParam 授予的 [Weapon] 行 17 条写『永久强化』而不是『武器』；行名没有档位时取所属词条的档位 6 条"
              "（8810301／8810351／8810401／8810451／8821000／8821050）；1731002／1731003 补上『自身累积』『蓄力・自身累积』；"
              "另 15 条只因消歧重排少了倍率限定词（其中 7610800–7610802、8850600／8850650 同时去掉了『#spEffectId』）。"
              "counts.displayNameZhFallingBackToSpEffectId 58→32（剩下的见 diagnostics.displayNameZhIdFallback／Note）；"
              "suggestedNameZh 变 2 条（3560／3561『第3层加成』→『第3层』）。"
              "(f) 7069001『封印监牢』的 stackInput.practicalMaxSource 注明只覆盖有行名的 320 个 patternId（另 200 个无行名的未核）；"
              "notes.stackInput／Q5 写明四条 204 阶梯（封印监牢、黑夜入侵者、玛雷家的庇佑、复仇的庇佑）categoryPriority 各不相同，"
              "按 exclusiveKey 彼此独立；notes.appliesTo 写明 throw=0 的读法与 Paramdex 字面相反及其依据；"
              "slotRules.weaponAffix.zh 改正『按稀有度的档位』的说法并写明深夜专属词条在 505 池只有档位1；"
              "slotRules.consumable／spellBuff 的 zh 改为『同 stacking.exclusiveKey 的只取一份』。"
              "⑪ **复核三轮**（仍是 v6，只增字段、只增取值；取值变化逐条如下）："
              "(a) **exclusiveScope 新增取值 affixVariant，exclusiveKey 新增取值 \"affix#<attachEffectId>\"**，新增 buffs[].affixVariant"
              "（key／attachEffectId／variant／variants／variantSpEffectIds／dispatcherSpEffectIds／dispatcherStateInfo／differingRateKeys／"
              "differingChainFields）：『出击时的武器，附加魔力／火／雷／圣属性攻击力』『…附加异常状态冻伤／中毒／出血』7 条遗物词条各 4 档"
              "（7120001–7120004、7120101–7120104、7120201–7120204、7120301–7120304、7120401–7120404、7120501–7120504、7120601–7120604）"
              "由词条的派发行（stateInfo=2101）按出击武器选一档，同一时刻只生效一档。"
              "**值变化 28 条**：stacking.exclusiveKey \"sp10#<id>\"→\"affix#<attachEffectId>\"、exclusiveScope perSpEffect→affixVariant"
              "（stacking.group 不变）；counts.buffsByExclusiveScope perSpEffect 428→400（新增 affixVariant 28）、exclusiveKeys 463→442、"
              "exclusiveKeysShared 27→34。新增 diagnostics.affixVariantScan(+Note)（合并的 7 组与没合并的近似组及原因）。"
              "(b) **relicAffixes[] 新增 exclusivityId**（AttachEffectParam 原值；262 处）与 diagnostics.relicAffixExclusivityGroups(+Note)："
              "上面 7 条词条共用 exclusivityId=100（同时装备时游戏亮红色感叹号），只作提示，没有并键。"
              "(c) **新增 buffs[].accumulatorStages**（3 条：8885220–8885222，武器词条 8885200『维持防御时，强化魔法、祷告与缩短咏唱时间』"
              "经累积器→行为→子弹依次达到的三个阶段，各 ×1.1，同时存在、逐段相乘，键仍各自一个）。"
              "(d) **accumulatorLadder 新增 shippedTierSpEffectIds**（15 条；7037604–7037606 的 tiers=4 但第 4 档 7037607 没有倍率、不在 buffs 里），"
              "新增 notes.accumulatorLadder 写明各键口径（tierSpEffectIds 含第 1 档，与 stackLadder 相反）与 \"sp120\" 让不同物品互斥的结论；"
              "enums.exclusiveScope.accumulatorLadder、notes.stackLadder 的说明文字随之补充。"
              "(e) **新增 buffs[].selfAllyPair**（6 条＝3 对：1835／1836、1870／1871、1876／1877）与 diagnostics.selfAllyPairs(+Note)："
              "算施放者自己的伤害时不计同一战技的 Allies 行（共享圣律 1877 只由 AtkParam_Pc 300000820 交给队友）；两行的键不变。"
              "(f) **displayNameZh／displayNameEn 各变 16 条**：7039900–7039909『提升攻击力（档位N）』→『出现异常状态量表时，能缓慢提升攻击力（第N层）』"
              "（行名 Stack N 的叠层行写『第N层』并带上所属词条名；英文去掉行名里重复的 Stack N）；7500801–7500803 的『档位N』→『第N层』"
              "（英文 LvN→Stack N）；8885220–8885222『强化魔法、祷告（武器・×1.1・…・命中时武器效果N）』→"
              "『维持防御时，强化魔法、祷告与缩短咏唱时间（第N阶段）』（英文改用词条名＋Stage N）。"
              "(g) 新增 notes.affixVariant／accumulatorLadder／accumulatorStages／selfAllyPair，enums.exclusiveScope.affixVariant，"
              "counts.buffsWithAffixVariant／affixVariantGroups／buffsWithAccumulatorStages／buffsWithSelfAllyPair；"
              "notes.ranking／relicAffix／stackLadder／suggestedName、stackingRules.zh 第 2 条的文字有补充。",
    },
    {
        "version": 5,
        "zh": "① **buffs[].target 再修正 43 条 self→enemy：命中投递槽补全第三条路径。** "
              "v4 把『命中槽』从 Bullet.spEffectId0..4 扩到 atkOccurrenceSpEffectId，改判了 33 条油脂／"
              "附加属性武器的异常累积行，但同一机制还有一条投递路径没纳入："
              "EquipParamWeapon.spEffectBehaviorId0..2（武器打中目标时交给目标的负载）与 "
              "AttachEffectParam.onHitSpEffect（『攻击附带异常状态』遗物词条的命中槽）。"
              "结果 3176『[Item] Poison Grease (Right) - Poison』已判 enemy，"
              "而与它**逐列同构**的 106010『Lvl 1-2 Poison +45』（毒匕首，"
              "poizonAttackPower／poisonInflictRate=1／isUseStatusAilmentAtkPowerCorrect=1／"
              "cycleOccurrenceSpEffectId=505／stateInfo=2／spCategory=10004／effectEndurance=40／"
              "changeHpPoint=10 的中毒 DoT 全部相同，只差阵营位与投递槽）仍是 self。"
              "v5 把这两个槽纳入同一套判定（阵营位优先、两侧都开时看负载类型），"
              "28 条武器自带异常属性累积行 ＋ 15 条 8110000-8110502『[Weapon] Attacks Inflict X』"
              "共 43 条改判 enemy，全部是 status／flag 负载、countsAsDamage=false，不影响伤害乘积；"
              "新增 targetSource weaponHitOpposeOnly／weaponHitSelfOnly／weaponHitStatusPayload。"
              "counts.buffsByTarget：self 759→716、enemy 65→108。"
              "**做『异常状态累积』榜的页面必须重取**：武器／词条带来的累积现在全在 target=enemy 侧。"
              "② **新增 buffs[].selfInflictedStatus（bool，仅 true 时出现，20 条）。** "
              "反方向的坑：target=self、阵营位 effectTargetSelfTarget=1／effectTargetOpposeTarget=0、"
              "且带 status 组**加算点数**（valueKind=flat 的 xxxAttackPower）的行，累的是**玩家自己**"
              "——1753『Seppuku - Self Blood Loss』+9999、"
              "1732002『Frenzied Burst (Self Madness +20)』、6851301／8810301『血量没有全满时，累积中毒量表』"
              "（简中 descZh 直接写『会持续受到损伤』）。v4 把其中 5 条由 conditional 改判成 passive，"
              "按『target=self ＋ activation=passive』默认计入的异常累积榜会把自伤列成玩家增益。"
              "xxxInflictRate（multiplier，含义是『自身造成的累积倍率』）刻意不算在内，"
              "99620『艾奥尼亚蝶』的状态标签「强化异常状态腥红腐败」证明那是真实增益、方向相反。"
              "配套 counts.buffsWithSelfInflictedStatus、diagnostics.selfInflictedStatus + Note，"
              "notes.target／notes.ranking 第⑤步已写明 status 轴的过滤口径。"
              "③ **enums.stateInfo 的条数以实测为准并纳入自检。** 实际 37 项，v4 的修复报告与说明写成 36 项。"
              "新增 counts.stateInfoLabels，self_check 改为断言 enums.stateInfo 的键集合与"
              "全表非 0 stacking.stateInfo 的取值集合**完全相等**（既不许缺标签，也不许有死标签），"
              "口径不会再只靠散文维护。"
              "④ **stackLadder 的字段口径写进说明，并更正排除举例。** 新增 notes.stackLadder："
              "tiers 含第 1 层、tierSpEffectIds 是第 2 层起且长度恒为 tiers-1、"
              "topRates 是最后一层、saved 表示 saveCategory≠-1。"
              "diagnostics.stackLaddersNote 里『[Relic] Improved Throwing Pot Damage +1/+2』"
              "引用了不存在的行名（参数表只有 7040300 ×1.15 与 7040301『…… +1』×1.30 两条有名字的档位，"
              "空行名的 7040302 才是 ×1.35），已改写成真实结构；"
              "self_check 增加 tierSpEffectIds 升序、不含自身、不与已收录 buff 相交、saved 必为 true 四条断言。"
              "⑤ diagnostics.opposeBitsWithoutHitSlot 由 42 条降为 37 条（1939、105510、8110200-202 已改判），"
              "其 Note 里把『武器行为槽』列为『无法确认投递路径』的说法是错的，已更正。",
    },
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
              "（**v5 补充**：这一轮只补了一半——同一机制还有 EquipParamWeapon.spEffectBehaviorId0..2 与 "
              "AttachEffectParam.onHitSpEffect 两个命中槽没纳入，43 条武器自带异常属性／"
              "『攻击附带异常状态』词条的累积行仍留在 self，其中 106010『Lvl 1-2 Poison +45』"
              "与本条已改判的 3176 逐列同构。v5 已按同一规则改判，见 v5 条目①。）"
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
    (20, 20, "resetOnApply",
     "重复取得**同一个** SpEffect 时刷新计时（不叠第二份）；不同 ID 之间不互斥"
     "（遗物词条、护符的被动大多是这一类，按 ID 各自独立，见 stacking.exclusiveKey）"),
    (100, 299, "removePrevious",
     "同类互斥，新的覆盖旧的。100–199 整个 spCategory 互斥；200–299 只有 categoryPriority 也相同才覆盖"
     "（Paramdex 只把 200 标成 w/ Matching Priority，但 201／204 的数据显示整个 200 系列都按优先度分组："
     "同一阶梯／同一道具的各档共用一个优先度，不同效果各有自己的优先度，见 stacking.exclusiveKey）。"
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
# v6 (re-verify): which *different* SpEffects exclude each other
# --------------------------------------------------------------------------
# stacking.group used "sp<spCategory>" for every behaviour other than
# none / stackSelf, so all 77 spCategory=20 buffs (1310 SpEffectParam rows,
# 1202 of the AttachEffectParam passives -- i.e. most relic affixes and
# talismans) collapsed into one de-dup bucket and a page kept only one of
# 红羽七刃剑 ×1.2 + 『装备三把以上短剑』 ×1.2 + 无赖被动 ×1.5.
#
# What the params actually say:
#   * 20 is "Reset on Apply" (Paramdex NR SP_EFFECT_SPCATEGORY); it is about
#     the *same* SpEffect being applied again (the timer restarts), not about
#     other ids.  The affix catalog agrees: superposability 『不可叠加』 (the
#     same affix twice does not stack) is sp20 on 126 affixes, while
#     『不同级别可叠加』 (+1 and +2 do stack) is also sp20 on 7 affixes
#     (6005600 / 6005601 ...), and one fixed relic carries two sp20 buffs.
#     -> per SpEffect id, like none / stackSelf.
#   * 200..299: Paramdex labels 200 "Remove Previous w/ Matching Priority";
#     the data shows the whole block is priority-scoped.  201 has 292 rows
#     over 90 priorities that come in tier pairs (带火破露滴 511028 and its
#     tier 2 708940 share 226, 带魔力破露滴 511029 / 708950 share 227, ...),
#     204 has 350 rows in 12 saved ladders and every ladder owns its own
#     priority (封印监牢 7069001-010 = 11, 黑夜入侵者 7069201-210 = 13,
#     玛雷家的庇佑 8988200-299 = 5, 复仇的庇佑 8998000-099 = 4, the relic
#     『每次打倒…强敌』 ladders 8/9/10 ...).  A category-wide "remove previous"
#     would make two relic affixes of that kind knock each other out, which
#     is why the priorities are there.  -> "sp<cat>@p<priority>".
#   * 100..199 (removePrevious), 1000.. (applyHighest), 10000.. (applyFirst):
#     category-wide, as before (right-hand weapon enchant 162, body buffs 151,
#     auras 160 ... -- the Elden Ring engine groups the same way).
#   * accumulator ladders (successive-attack talismans etc.): the tiers are
#     fired one by one through accumuOverFireId; tiers 1-3 are sp120 but the
#     top tier is sp20 with effectEndurance=0 and the same value as tier 3
#     (312508 ×1.11 = 312507 ×1.11).  Taken per id the page could multiply
#     tier 3 and tier 4 of one talisman; the whole ladder takes the key of its
#     category tiers.
EXCLUSIVE_SCOPE_LABELS: "OrderedDict[str, str]" = OrderedDict([
    ("perSpEffect", "只与自己（同一 spEffectId）互斥：spCategoryBehavior 为 none／persistThroughDeath／stackSelf／"
                    "resetOnApply／unknown。不同 ID 永不互相顶替；同一 ID 从多个来源各拿一份时，stackSelf 各份相乘，"
                    "其余只算一份。键＝\"sp<spCategory>#<spEffectId>\"（与 group 相同）"),
    ("category", "同 spCategory 互斥（removePrevious 100–199、applyHighest 1000–1999、applyFirst 10000 以上）："
                 "键＝\"sp<spCategory>\"。例：162＝右手武器附魔（油脂、武器附魔战技、附魔祷告只能留一个），"
                 "151＝『火焰啊，赐予我力量！』与狂热香药、勇者肉块，160＝黄金树立誓与振奋香、归于麾下"),
    ("categoryPriority", "同 spCategory 且同 categoryPriority 才互斥（200–299 系列）：键＝\"sp<spCategory>@p<categoryPriority>\"。"
                         "同一阶梯／同一道具的各档共用一个优先度（封印监牢 7069001–7069010 都是 11），"
                         "不同效果各有自己的优先度（黑夜入侵者 13、玛雷家的庇佑 5、复仇的庇佑 4），因此彼此独立"),
    ("accumulatorLadder", "累积阶梯（accumuOverFireId 逐档触发的连续攻击类）：各档共用一个键——有档位落在互斥类别里时取该类别的键"
                          "（连续攻击类都是 sp120），否则取 \"ladder#<第 1 档 spEffectId>\"。最高档常是 spCategory=20、"
                          "effectEndurance=0、数值与前一档相同的『保持』行（312508 ×1.11＝312507 ×1.11），按 ID 算会把两档相乘。"
                          "**键 \"sp120\" 同时意味着不同物品之间互斥**：连刺破露滴 3558–3561、米莉森的义手 312505–312508、"
                          "带翼剑徽章 320804–320807、遗物『连续攻击时，提升攻击力』7037604–7037606 都落在 spCategory 120"
                          "（Paramdex：Remove Previous，新的顶替旧的），任取两件同时装备也只有一份生效，排名只算一份（默认取倍率最高的一档），"
                          "页面同时选中时应提示。这是按参数推断的，未实测；v6 之前的说明曾把『米莉森的义手＋带翼剑徽章』当作相乘的例子，以本条为准。"
                          "字段口径见 notes.accumulatorLadder"),
    # v6 (re-verify, round 3): the 4 potency rows of one relic affix that the
    # affix's own dispatcher row picks from (stateInfo 2101, only 7 rows in the
    # table) -- per id they read as four stackSelf buffs and multiplied.
    ("affixVariant", "同一条词条（AttachEffectParam）下互为替代的档位：键＝\"affix#<attachEffectId>\"，同键只取一档。"
                     "识别条件（全部满足，见 buffs[].affixVariant 与 diagnostics.affixVariantScan）：只归属这一条词条；"
                     "词条自己的 passiveSpEffectId_1..3 都不是 buff（只是派发行，如 stateInfo=2101『Apply State Info』）；"
                     "整张 SpEffectParam 表没有任何指向列（replace／cycle／atkOccurrence／accumuOverFire…）指向这些行，"
                     "只能由派发行按条件选一档；行名去掉『Potency N』后同干、倍率键相同，除行名、倍率数值与指向列外逐列相同；"
                     "原来都是按 ID 的键（perSpEffect）。本版本 7 条『出击时的武器，附加…』词条 × 4 档＝28 条"),
])


def exclusive_category_key(sp_category: int, priority: int) -> tuple[str | None, str]:
    """(key, scope) from spCategory / categoryPriority alone; key None = per SpEffect."""
    behaviour, _zh = spcategory_behaviour(sp_category)
    if behaviour == "removePrevious":
        if 200 <= sp_category <= 299:
            return f"sp{sp_category}@p{priority}", "categoryPriority"
        return f"sp{sp_category}", "category"
    if behaviour in ("applyHighest", "applyFirst"):
        return f"sp{sp_category}", "category"
    return None, "perSpEffect"


def exclusive_key_evidence(sp: dict[str, dict[str, str]], attach: dict[str, dict[str, str]],
                           catalog_affixes: list[dict[str, Any]]) -> dict[str, Any]:
    """The numbers stackingRules 1-2 quote, measured (and asserted against the text)."""
    rows_by_cat: dict[int, list[dict[str, str]]] = defaultdict(list)
    for row in sp.values():
        rows_by_cat[int(row["spCategory"])].append(row)
    passive_fields = ("passiveSpEffectId_1", "passiveSpEffectId_2", "passiveSpEffectId_3")
    attach_passives = Counter(int(sp[t]["spCategory"]) for row in attach.values()
                              for t in (ref(row.get(f)) for f in passive_fields) if t in sp)
    superpos: Counter = Counter()
    for affix in catalog_affixes:
        row = attach.get(str(affix["effectId"]))
        if row is None:
            continue
        cats = sorted({int(sp[t]["spCategory"]) for t in (ref(row.get(f)) for f in passive_fields) if t in sp})
        if cats == [20]:
            superpos[affix.get("superposability") or "?"] += 1
    per_200 = []
    for cat in sorted(c for c in rows_by_cat if 200 <= c <= 299):
        rows = rows_by_cat[cat]
        per_200.append({"spCategory": cat, "rows": len(rows),
                        "distinctCategoryPriority": len({r["categoryPriority"] for r in rows})})
    # 204: one categoryPriority = one saved ladder (its rows sit in one id block)
    by_priority: dict[int, list[dict[str, str]]] = defaultdict(list)
    for row in rows_by_cat.get(204, []):
        by_priority[int(row["categoryPriority"])].append(row)
    ladders_204: list[dict[str, Any]] = []
    for priority, rows in sorted(by_priority.items(), key=lambda kv: min(int(r["ID"]) for r in kv[1])):
        ids = sorted(int(r["ID"]) for r in rows)
        ladders_204.append({"categoryPriority": priority, "rows": len(rows),
                            "firstSpEffectId": ids[0], "lastSpEffectId": ids[-1],
                            "saveCategory": sorted({int(r["saveCategory"]) for r in rows}),
                            "paramName": next((r.get("Name") for r in sorted(rows, key=lambda r: int(r["ID"]))
                                               if r.get("Name")), None)})
    return {
        "spCategory20Rows": len(rows_by_cat.get(20, [])),
        "attachEffectPassivesBySpCategory": {str(k): v for k, v in sorted(attach_passives.items())},
        "affixCatalogSuperposabilityOfSp20": dict(sorted(superpos.items())),
        "category200sPriorities": per_200,
        "sp204Ladders": ladders_204,
        # every priority group is one id block (a ladder), not ids scattered over the table
        "sp204LaddersAreIdBlocks": all(l["lastSpEffectId"] - l["firstSpEffectId"] + 1 <= l["rows"] + 10
                                       for l in ladders_204),
    }


def accumulator_families(sp: dict[str, dict[str, str]]) -> list[list[int]]:
    """Runs of consecutive accumulator ids (accumuOverFireId set) with one stateInfo."""
    ids = sorted(int(k) for k, row in sp.items() if ref(row.get("accumuOverFireId")))
    families: list[list[int]] = []
    for value in ids:
        if (families and value == families[-1][-1] + 1
                and sp[str(value)]["stateInfo"] == sp[str(families[-1][-1])]["stateInfo"]):
            families[-1].append(value)
        else:
            families.append([value])
    return families


def accumulator_ladders(sp: dict[str, dict[str, str]]) -> tuple[dict[str, dict[str, Any]], list[dict[str, Any]]]:
    """Tier SpEffects of every multi-step accumulator ladder, and any unmergeable ladder.

    An accumulator row carries accumuOverFireId (the SpEffect fired once the
    counter passes accumuOverVal).  One ladder = a run of consecutive
    accumulator ids with the same stateInfo (312501..312504 -> 312505..312508,
    thresholds 17/30/45/60).  Single accumulators are not ladders.
    """
    tiers_of: dict[str, dict[str, Any]] = {}
    conflicts: list[dict[str, Any]] = []
    for family in accumulator_families(sp):
        if len(family) < 2:
            continue
        pairs = sorted(((float(sp[str(a)]["accumuOverVal"]), a, ref(sp[str(a)]["accumuOverFireId"]))
                        for a in family), key=lambda p: (p[0], p[1]))
        targets = [t for _thr, _a, t in pairs if t in sp]
        if len(targets) < 2:
            continue
        keys = sorted({k for k in (exclusive_category_key(int(sp[t]["spCategory"]),
                                                          int(sp[t]["categoryPriority"]))[0]
                                   for t in targets) if k})
        if len(keys) > 1:
            conflicts.append({"accumulatorSpEffectIds": family, "tierSpEffectIds": [int(t) for t in targets],
                              "keys": keys})
            continue
        key = keys[0] if keys else f"ladder#{targets[0]}"
        for index, target in enumerate(targets, 1):
            tiers_of[target] = {
                "key": key,
                "tier": index,
                "tiers": len(targets),
                "tierSpEffectIds": [int(t) for t in targets],
                "accumulatorSpEffectIds": [a for _thr, a, _t in pairs if _t in sp],
                "thresholds": [as_number(str(thr)) for thr, _a, t in pairs if t in sp],
            }
    return tiers_of, conflicts


def accumulator_stage_chains(sp: dict[str, dict[str, str]], behaviors: dict[str, dict[str, str]],
                             bullets: dict[str, dict[str, str]], shipped_ids: set[str]) -> dict[str, dict[str, Any]]:
    """Accumulator ladders whose tiers reach their buff through a behavior bullet.

    v6 (re-verify, round 3).  The guarding weapon affix 8885200 has three
    accumulators 8885201..8885203 (stateInfo 307, thresholds 4M / 9M / 15M)
    that fire 8885210..8885212 -- rows without a rate of their own but with a
    behaviorId (900010020..22; BehaviorParam_PC refType 1 = bullet) whose
    bullet 98885200..02 hands spEffectId0 = 8885220..8885222 to the player.
    accumulator_ladders() never sees those three buffs (its tiers are the
    fired rows themselves).  Unlike the successive-attack ladders they are
    not alternatives: all three are ×1.1 resetOnApply rows of their own id and
    differ only in effectEndurance (28 / 25.5 / 22.5 s), and the threshold
    gaps (5M, 6M) and the duration gaps (2.5 s, 3 s) are in one ratio -- the
    three stages run out at the same moment, i.e. they are built to coexist
    (the affix text says 『阶段性提升』).  Each stage keeps its own key.
    """
    out: dict[str, dict[str, Any]] = {}
    for family in accumulator_families(sp):
        if len(family) < 2:
            continue
        pairs = sorted(((float(sp[str(a)]["accumuOverVal"]), a, ref(sp[str(a)]["accumuOverFireId"]))
                        for a in family), key=lambda p: (p[0], p[1]))
        stages: list[tuple[float, int, str, str, str, str]] = []
        for thr, acc, target in pairs:
            row = sp.get(target or "")
            if row is None or target in shipped_ids:
                break
            behavior = behaviors.get(ref(row.get("behaviorId")) or "")
            if behavior is None or behavior.get("refType") != "1":
                break
            bullet = bullets.get(ref(behavior.get("refId")) or "")
            if bullet is None:
                break
            hits = [s for s in (ref(bullet.get(f"spEffectId{i}")) for i in range(5)) if s and s in shipped_ids]
            if len(hits) != 1:
                break
            stages.append((thr, acc, target, behavior["ID"], bullet["ID"], hits[0]))
        if len(stages) != len(pairs) or len(stages) < 2 or len({s[5] for s in stages}) != len(stages):
            continue
        thresholds = [s[0] for s in stages]
        durations = [float(sp[s[5]]["effectEndurance"]) for s in stages]
        # do the stages run out together?  (threshold gap / duration gap constant)
        aligned: dict[str, Any] | None = None
        gaps = [(thresholds[i + 1] - thresholds[i], durations[i] - durations[i + 1]) for i in range(len(stages) - 1)]
        if all(g > 0 and d > 0 for g, d in gaps):
            rates = [g / d for g, d in gaps]
            if max(rates) - min(rates) <= 1e-9 * max(rates):
                ends = [thresholds[i] / rates[0] + durations[i] for i in range(len(stages))]
                if max(ends) - min(ends) <= 1e-6:
                    aligned = {"unitsPerSecond": as_number(str(rates[0])), "commonEndSeconds": as_number(str(round(ends[0], 6)))}
        for index, stage in enumerate(stages, 1):
            out[stage[5]] = {
                "stage": index,
                "stages": len(stages),
                "stageSpEffectIds": [int(s[5]) for s in stages],
                "accumulatorSpEffectIds": [s[1] for s in stages],
                "thresholds": [as_number(str(t)) for t in thresholds],
                "behaviorSpEffectIds": [int(s[2]) for s in stages],
                "behaviorParamIds": [int(s[3]) for s in stages],
                "bulletIds": [int(s[4]) for s in stages],
                "durations": [as_number(str(d)) for d in durations],
                "expiryAligned": aligned,
                "coexist": True,
            }
    return out


# v6 (re-verify, round 3): the row-name family of an affix variant -- the
# Paramdex name without its "- Potency N" / "- Stack N" / trailing number.
VARIANT_SUFFIX_RE = re.compile(r"\s*-?\s*\b(?:Potency|Level|Lv|Stack|Step|Tier|Phase)\s*\d+\b|\s+\d+$", re.IGNORECASE)


def variant_family(name: str | None) -> str:
    return VARIANT_SUFFIX_RE.sub("", clean_param_name(name or "")).strip().casefold()


def affix_variant_scan(buffs: list[dict[str, Any]], sp: dict[str, dict[str, str]],
                       attach: dict[str, dict[str, str]]) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    """Groups of buffs that are alternative potencies of one affix, and the near misses.

    v6 (re-verify, round 3).  AttachEffectParam 7120000 『出击时的武器，附加魔力属性
    攻击力』 has one passive, 7120000 "Apply State Info" (stateInfo 2101 -- only
    the seven 『出击时的武器，附加…』 affixes use it), and four sibling rows
    7120001..7120004 "Damage Adjustment - Potency 1..4" (physical -30/-40/-50/
    -60, magic +33/+44/+55/+66; the affix catalog: 『根据武器类型…』) that no
    param column points at: the dispatcher picks one of them.  Per id they
    were four stackSelf buffs with four keys and a relic carrying the affix
    summed to -180 / +198 (the ×0.85 status rows to ×0.85^4).

    A group needs, for one owning affix (relicAffixes / weaponAffixIds, the
    buff owned by that affix only): no passive of the affix is itself a buff
    (the affix only dispatches); no chain column anywhere in SpEffectParam
    points at a member; the same row-name family (variant_family) and the same
    rate keys; every other column equal except Name and the chain columns;
    per-id keys today.  Anything that fails is listed with the reason.
    """
    referenced: set[str] = set()
    for row in sp.values():
        for field, _label in CHAIN_FIELDS:
            target = ref(row.get(field))
            if target:
                referenced.add(target)
    shipped = {str(b["spEffectId"]) for b in buffs}
    chain_fields = [field for field, _label in CHAIN_FIELDS]
    by_owner: dict[tuple[str, int], list[dict[str, Any]]] = defaultdict(list)
    for buff in buffs:
        owners = ([("relicAffix", e["attachEffectId"]) for e in buff.get("relicAffixes", [])]
                  + [("weaponAffix", a) for a in buff.get("weaponAffixIds", [])])
        if len(owners) == 1:
            by_owner[owners[0]].append(buff)
    groups: list[dict[str, Any]] = []
    rejected: list[dict[str, Any]] = []
    for (slot, attach_id), members in sorted(by_owner.items(), key=lambda kv: (kv[0][1], kv[0][0])):
        if len(members) < 2:
            continue
        attach_row = attach.get(str(attach_id), {})
        passives = [p for p in (ref(attach_row.get(f"passiveSpEffectId_{i}")) for i in (1, 2, 3)) if p]
        families: dict[tuple[str, tuple[str, ...]], list[dict[str, Any]]] = defaultdict(list)
        for buff in members:
            families[(variant_family(buff["paramName"]), tuple(sorted(buff["rates"])))].append(buff)
        for (_family, rate_keys), family in sorted(families.items(),
                                                   key=lambda kv: min(b["spEffectId"] for b in kv[1])):
            if len(family) < 2:
                continue
            ids = sorted(b["spEffectId"] for b in family)
            rows = [sp[str(i)] for i in ids]
            base: dict[str, Any] = {"attachEffectId": attach_id, "slot": slot, "spEffectIds": ids}
            reason = None
            if any(p in shipped for p in passives):
                reason = "ownerPassiveIsBuff"
            elif any(str(i) in referenced for i in ids):
                reason = "referencedByChain"
            elif any(b["stacking"]["exclusiveScope"] != "perSpEffect" for b in family):
                reason = "alreadySharedKey"
            else:
                skip = {"ID", "Name", *rate_keys, *chain_fields}
                differing = sorted(c for c in rows[0] if c not in skip and len({r.get(c) for r in rows}) > 1)
                if differing:
                    reason = "columnsDiffer"
                    base["differingColumns"] = differing
            if reason:
                rejected.append({**base, "reason": reason})
                continue
            groups.append({
                **base,
                "key": f"affix#{attach_id}",
                "dispatcherSpEffectIds": [int(p) for p in passives],
                "dispatcherStateInfo": sorted({int(sp[p]["stateInfo"]) for p in passives if p in sp}),
                "differingRateKeys": [k for k in rate_keys if len({b["rates"][k] for b in family}) > 1],
                "differingChainFields": [f for f in chain_fields if len({r.get(f) for r in rows}) > 1],
            })
    return groups, rejected


AFFIX_VARIANT_REJECT_REASONS = OrderedDict([
    ("ownerPassiveIsBuff", "词条自己的 passiveSpEffectId 就是 buff（词条直接给这一档，其余同干行不是它派发的，"
                           "如 6610700『减少专注值消耗』只引用档位1 7610700，7610701／7610702 在参数里没有任何引用）"),
    ("referencedByChain", "有指向列指向这些行（替换、周期、命中、击杀、累积、解析等级…），各行由不同事件分别触发，不是同一派发行的替代档"),
    ("alreadySharedKey", "原来就共用类别键（removePrevious／applyFirst…），已经互斥，不需要再合并"),
    ("columnsDiffer", "除行名、倍率与指向列外还有列不同（持续时间、特效、阵营位…），不是单纯的数值档位"),
])


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

# The *third* hit slot, and the one v4 still missed.  EquipParamWeapon's
# spEffectBehaviorId0..2 ("特殊効果行動ID") and AttachEffectParam.onHitSpEffect
# are not resident buffs on the wielder -- they are the payload the weapon /
# relic affix hands to whatever the attack connects with.  Two independent
# reads of the raw CSV say so:
#   * 106010 "Lvl 1-2 Poison +45" (the Poison Dagger's buildup, reached through
#     EquipParamWeapon.spEffectBehaviorId0) is column-for-column identical to
#     3176 "[Item] Poison Grease (Right) - Poison" -- poizonAttackPower,
#     poisonInflictRate=1, isUseStatusAilmentAtkPowerCorrect=1,
#     cycleOccurrenceSpEffectId=505, stateInfo=2, spCategory=10004,
#     effectEndurance=40, changeHpPoint=10 / changeHpRate=0.1 (the poison DoT
#     tick) -- and v4 already reclassified 3176 as target="enemy".  The only
#     differences are the faction bits and the buildup value.
#   * the delivery chain itself: EquipParamGoods 1460 "[Common] Poison Grease"
#     -> SpEffect 3175 "[Item] Poison Grease (Right)" (the 30 s buff that really
#     does sit on the player: wepParamChange=1, poizonAttackPower=0)
#     -> atkOccurrenceSpEffectId 3176.  The buildup lives one hop further out,
#     on the thing that was hit; reading it as a player-side buff would mean the
#     grease buff re-buffs the player on every swing.
#   * 105000 "Lvl 1-1 Blood Loss +30" carries changeHpPoint=100 /
#     changeHpRate=12.5 -- the blood-loss burst.  That damage is dealt to the
#     victim, not to the wielder holding the dagger.
# v4 left 43 such rows (28 weapon-buildup rows + 15 "[Weapon] Attacks Inflict X"
# relic affixes) on target="self", structurally identical to the grease rows it
# had just moved to "enemy".  The faction bits are still asked first, so the two
# genuinely self-directed rows that use this slot (704030 "[Skill - Raider]
# Retaliate (Fully Restore Stamina)", 5121800 "[Ultimate - Recluse] Soulblood
# Song", both effectTargetSelfTarget=1 / effectTargetOpposeTarget=0) stay self.
WEAPON_HIT_VIA_RE = re.compile(r"(?:spEffectBehaviorId[0-2]|onHitSpEffect)(?:->|$)")

# Any of the three "handed to what the attack hit" slots (the Bullet slots have
# their own branch because the bullet's AtkParam gives them one extra question).
HIT_SLOT_VIA_RE = re.compile(
    r"(?:atkOccurrenceSpEffectId|spEffectBehaviorId[0-2]|onHitSpEffect)(?:->|$)")

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
        "（Bullet.spEffectId0..4、SpEffectParam.atkOccurrenceSpEffectId、"
        "EquipParamWeapon.spEffectBehaviorId0..2 或 AttachEffectParam.onHitSpEffect）。"
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
    "weaponHitOpposeOnly":
        "全部来源都经由**武器／词条的命中槽**投递——EquipParamWeapon.spEffectBehaviorId0..2"
        "（『特殊効果行動ID』，武器打中目标时交给目标的负载）或 AttachEffectParam.onHitSpEffect"
        "（遗物词条『攻击附带异常状态』的命中槽）——且阵营过滤位 effectTargetSelfTarget=0／"
        "effectTargetOpposeTarget=1，只能打给敌方。"
        "例：1939『[Serpent Bow] Arrow Poison』、105510『Lvl 1-2 Sleep +45』（托莉娜剑）、"
        "8110200-202『[Weapon] Attacks Inflict Sleep - Potency 1-3』。",
    "weaponHitSelfOnly":
        "全部来源都经由 EquipParamWeapon.spEffectBehaviorId0..2 或 AttachEffectParam.onHitSpEffect 投递，"
        "但阵营位只允许打给自己（effectTargetSelfTarget=1 且 effectTargetOpposeTarget=0，"
        "或两侧都开而负载不只是异常累积）——这是『命中瞬间给自己上 buff』的形态，效果挂在玩家身上。"
        "本版本没有实例进入数据集（704030『[Skill - Raider] Retaliate (Fully Restore Stamina)』与 "
        "5121800『[Ultimate - Recluse] Soulblood Song』走的就是这条路，但它们没有合格的倍率字段，未入选）。",
    "weaponHitStatusPayload":
        "全部来源都经由 EquipParamWeapon.spEffectBehaviorId0..2 或 AttachEffectParam.onHitSpEffect 投递，"
        "阵营过滤两侧都开，而负载只有异常累积／开关（没有任何倍率或攻击力加算）——"
        "『打中谁就给谁累积』，挂在被命中的敌人身上。"
        "这是各类武器自带的出血／中毒／冻伤／腐败／发狂累积行（105000『Lvl 1-1 Blood Loss +30』、"
        "106010『Lvl 1-2 Poison +45』…）以及『攻击附带异常状态』遗物词条（8110000-8110502）。"
        "判定依据：106010 与已判 enemy 的 3176『[Item] Poison Grease (Right) - Poison』逐列同构"
        "（stateInfo=2、spCategory=10004、cycleOccurrenceSpEffectId=505、effectEndurance=40、"
        "changeHpPoint=10／changeHpRate=0.1 的中毒持续伤害），只差阵营位与投递槽。",
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
    "stackInputRequired": "**v6 新增**：局内叠层增益（sourceSlot=runStack），一局开始时是 0 层，"
                          "层数要由用户按实际打倒的首领数填写（见 buffs[].stackInput），"
                          "因此不得作为『装上就有』的 passive 默认乘进排名"
                          "（例：8970000『赐福王的余威』每层 ×1.02，v5 标成 passive／noEvidence）。",
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
   - 20（resetOnApply）：**同一个 SpEffect** 重复取得时只刷新持续时间、不叠第二份；不同 ID 之间不互斥。
     Paramdex NR 的枚举就叫 Reset on Apply，说的是同一效果重复获得；遗物词条、护符的被动绝大多数是这一类
     （SpEffectParam 里 1310 行；AttachEffectParam passiveSpEffectId_1..3 的引用里有 1202 处指向 20 类），若跨 ID 互斥，装两条遗物词条就会互相顶掉。
     词条库的实测叠加性与此一致：『不可叠加』（同一词条装两次不叠）有 126 条是 20，
     『不同级别可叠加』（＋1 与＋2 可以同时生效）也有 7 条是 20（词条 6005600／6005601…，对应 buff 7005601／7005602）；
     固定遗物『辽阔的光耀情景』一件就带 7030602、7034402 两条 20 类增益。
     v6 之前 stacking.group 把 20 按类别整组合并，77 条互不相干的增益只剩一条，已改为按 ID；
   - 100～299（removePrevious）：同类互斥，新的把旧的顶掉。100～199 整个 spCategory 互斥；
     200～299 要求 categoryPriority 也相同才顶替。Paramdex 只把 200 标成 w/ Matching Priority，但数据显示
     整个 200 系列都按优先度分组：201 的 292 行分成 90 个优先度，同一破露滴的两档共用一个
     （带火破露滴 511028 与档位2 708940 都是 226，带魔力破露滴 511029／708950 都是 227）；
     204 的 350 行按优先度分成 12 组，每组正好是一条存档阶梯（一段连续 ID），即每条阶梯自己一个优先度（封印监牢 7069001–7069010＝11、
     黑夜入侵者 7069201–7069210＝13、玛雷家的庇佑 8988200–8988299＝5、复仇的庇佑 8998000–8998099＝4、
     遗物『每次打倒…强敌』的几条＝8／9／10…）。所以同一阶梯的各层互斥，不同阶梯互不影响。
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

2. 排名时的建议做法：**按 stacking.exclusiveKey 分组**（v6 新增，取值规则见 enums.exclusiveScope）：
   - exclusiveScope=perSpEffect：spCategoryBehavior 为 none／persistThroughDeath／stackSelf／resetOnApply／unknown，
     键＝"sp<spCategory>#<spEffectId>"，只和自己同键；
   - exclusiveScope=category：removePrevious 100～199、applyHighest、applyFirst，键＝"sp<spCategory>"；
   - exclusiveScope=categoryPriority：removePrevious 200～299，键＝"sp<spCategory>@p<categoryPriority>"；
   - exclusiveScope=accumulatorLadder：连续攻击类累积阶梯（accumuOverFireId 逐档触发，buffs[].accumulatorLadder），
     各档共用一个键——有档位落在互斥类别里时取该类别的键（连续攻击类都是 "sp120"），否则 "ladder#<第 1 档 id>"。
     最高档常是 spCategory=20、effectEndurance=0、数值与前一档相同的『保持』行（312508 ×1.11＝312507 ×1.11），
     按 ID 算会把同一护符的两档相乘。键 "sp120" 同时让连刺破露滴、米莉森的义手、带翼剑徽章、遗物『连续攻击时，提升攻击力』
     这几件彼此互斥（同时装备只有一份生效，参数推断、未实测，见 notes.accumulatorLadder）；
   - exclusiveScope=affixVariant（v6 复核三轮）：同一条词条下互为替代的档位（buffs[].affixVariant），键＝"affix#<attachEffectId>"。
     『出击时的武器，附加…』7 条遗物词条各有 4 档（7120001–7120004 等），由词条自己的派发行（stateInfo=2101）按出击武器选一档，
     按 ID 算会把物理 −30／−40／−50／−60 与属性 +33／+44／+55／+66 全加起来、把 ×0.85 乘成 ×0.52；
   - 反过来，accumulatorStages（8885220–8885222，武器词条『维持防御时…』的三个阶段）各自一键，逐段相乘（notes.accumulatorStages）；
     selfAllyPair 的 Self／Allies 两行各自一键，但算施放者自己时只计 Self 行（notes.selfAllyPair）。
   同键的只保留一份（applyHighest 取 categoryPriority 最优，其余取玩家实际选择的那一份，默认取倍率最高者）；
   不同键之间视为相互独立，各自的倍率相乘。同一个 spEffectId 从多个来源各拿一份时，stackSelf 各份相乘，其余只算一份。
   stacking.group 保留旧口径（"sp<spCategory>#<spEffectId>" 或 "sp<spCategory>"，只按类别、不看优先度与阶梯），
   v6 起 resetOnApply 也按 ID；页面应改用 exclusiveKey。
   正例（同键互斥）：右手附魔 162 的火油脂 3160 与雷油脂 3165；151 的『火焰啊，赐予我力量！』1605000 与狂热香药 503550；
   同一破露滴两档 511028／708940；米莉森的义手四档 312505–312508；封印监牢十层 7069001–7069010；
   『出击时的武器，附加魔力属性攻击力』四档 7120001–7120004、『…附加异常状态冻伤』四档 7120401–7120404。
   反例（不同键，相乘）：红羽七刃剑 320400、遗物『装备三把以上短剑』7080000、无赖被动 704301；
   『三把以上短剑』7080000 与『三把以上刀』7080600；7034402 与 7036801；7005601／7005602（＋1／＋2）；
   封印监牢 7069001、黑夜入侵者 7069201、玛雷家的庇佑 8988200、复仇的庇佑 8998000 四条阶梯彼此之间；
   『出击时的武器，附加…』7 条词条彼此之间（各自一键，同 exclusivityId=100 只作提示）；8885220／8885221／8885222 三个阶段；共享圣律 1876／1877。
   这些都写进了 self_check。

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
# v6 (re-verify, round 3): the Self / Allies rows of one cast
# ("[AoW] Shared Order - Damage Buff - Self" / "... - Allies")
SELF_ALLY_ROW_RE = re.compile(r"^(.*) - (Self|Allies)$")
# v6 (re-verify, round 3): a ladder layer row ("... - Stack 3"); shown as 「第N层」
STACK_ROW_RE = re.compile(r"\bStack\s*(\d+)\b", re.IGNORECASE)
SIDE_RE = re.compile(r"\b(Right|Left)\b")


# ==========================================================================
# v6 -- loadout slots (武器词条／遗物／护符／道具…) and per-output appliesTo
# ==========================================================================
# The 增伤排名 page is being rebuilt as a *loadout builder*: the user fills
# the slots a run really has (6 weapons x 1-2 affixes, 3+3 relics, 2
# talismans, consumables / spell buffs / run stacks) and the page multiplies
# only what applies to the chosen skill or spell.  v5 could not support that:
#
#   * every AttachEffectParam row that sat in *any* AttachEffectTableParam
#     pool was exported as kind="relicAffix", so the in-run weapon affixes
#     (8100000-8889999, pooled through EquipParamCustomWeapon) were
#     indistinguishable from relic affixes;
#   * nothing said which output a buff touches, so the page guessed from
#     scope and got it wrong three ways (see notes.userQuestions Q1/Q2).
#
# Everything below is derived from the params at run time; the few numbers
# that the params cannot give (talisman slots, the Night Invader cap) are
# labelled with their source instead of being passed off as measured.

AFFIX_CATALOG_PATH = ROOT / "data" / "nightreign-affixes-v1.03.4.json"
RELIC_CATALOG_PATH = ROOT / "data" / "nightreign-relics-v1.03.4.json"
SKILLS_DATASET_PATH = ROOT / "data" / "nightreign-skills-v1.03.5.json"

SOURCE_SLOTS: "OrderedDict[str, dict[str, str]]" = OrderedDict([
    ("weaponAffix", {
        "zh": "局内武器词条", "en": "In-run armament passive",
        "note": "局内捡到的武器随机带的附加效果（游戏里显示为「提升战技攻击力」「提升火属性攻击力」等）。"
                "实现上是 AttachEffectParam 行，经 EquipParamCustomWeapon.attachEffectTableId_1..6 → "
                "AttachEffectTableParam 池挂到武器上（与遗物词条同一张 AttachEffectParam 表、但不同的池）。"
                "按 slotRules.weaponAffix 组装：常规每把 1 条、深夜诅咒武器每把 2 条（另带 1 条负面诅咒），最多 6 把；"
                "深夜的 2 条正面词条里最多 1 条是深夜专属词条（weaponAffixDeepOnlyPositive=true；"
                "weaponAffixDeepOnly=true 也包括诅咒，诅咒另算每把 1 条，不占这个名额）。"}),
    ("relicAffix", {
        "zh": "遗物词条", "en": "Relic affix",
        "note": "EquipParamAntique 的词条池（attachEffectTableId_1..3／_curse1..3）里的 AttachEffectParam 行。"
                "每条带 relicAffixes[]：catalogEffectId 对齐词条库 data/nightreign-affixes-v1.03.4.json，"
                "页面按现有遗物合法性规则（windows/renderer/core.js）组遗物；官方固定词条遗物见 fixedRelics。"}),
    ("accessory", {
        "zh": "护符", "en": "Talisman",
        "note": "EquipParamAccessory.spEffectId_1..3 → AttachEffectParam → SpEffectParam，名字取 AccessoryName。"
                "按 slotRules.accessory 最多 2 个，同一护符（accessoryGroup 相同）不能重复。"}),
    ("consumable", {
        "zh": "道具（消耗品）", "en": "Consumable",
        "note": "EquipParamGoods：香、油脂、露滴、投掷物等，使用后获得的增益。"}),
    ("spellBuff", {
        "zh": "增益法术", "en": "Buff spell",
        "note": "Magic 表（魔法／祷告）施放后挂在身上或队友身上的增益，例如黄金树立誓、火焰啊赐予我力量。"}),
    ("weaponSkill", {
        "zh": "战技发动后的增益", "en": "Ash of War self-buff",
        "note": "**v6 新增取值（任务清单外）**：战技（AoW）发动后给自己的增益，例如战技『黄金树立誓』『归于麾下』『神圣刀刃』。"
                "它们由游戏脚本挂载（参数表无引用，sources[].inferred=true），数量多（v5 里 95 条），"
                "既不是武器词条也不是法术，归进 other 会让页面把它们与场景增益混在一起。"
                "注意：显示名里的『战技』是**来源**，不是『提升战技攻击力』——它们能否作用于法术看 appliesTo。"}),
    ("weaponInnate", {
        "zh": "武器固有效果", "en": "Armament innate effect",
        "note": "**v6 新增取值（任务清单外）**：武器本身自带、不随机的效果——"
                "EquipParamWeapon.residentSpEffectId*/spEffectBehaviorId*（武器自带的出血／中毒等）、"
                "EquipParamWeapon.attachEffectId（传说武器的『XX的庇佑』，如玛雷家行刑剑『玛雷家的庇佑』），"
                "以及 Paramdex 行名为 [Weapon Power]／[Bow]／[Arrow]／[Flail] 的脚本挂载行。选了那把武器才有。"}),
    ("character", {
        "zh": "角色技艺／绝招／被动", "en": "Nightfarer skill / ultimate / passive",
        "note": "Paramdex 行名 [Skill - X]／[Ultimate - X]／[Passive - X]（脚本挂载），以及隐士的『混合魔法』[Magic Cocktail]。"}),
    ("permanent", {
        "zh": "永久强化／潜在能力", "en": "Permanent buff / Dormant Power",
        "note": "PermanentBuffParam：局内打倒特定首领后获得、持续整局的效果（潜在能力、地图恩惠等）。"}),
    ("runStack", {
        "zh": "局内叠层增益", "en": "In-run stacking buff",
        "note": "不依附任何装备、随一局进程反复叠加的增益（本版本是 PermanentBuffParam.graceSpEffectId 投递的『赐福王的余威』）。"
                "叠层上限与每层倍率见 buffs[].stackInput。依附遗物词条／武器的叠层效果（封印监牢、黑夜入侵者、"
                "玛雷家的庇佑、复仇的庇佑）仍归各自的装备槽位，同样带 stackInput。"}),
    ("other", {
        "zh": "其他", "en": "Other",
        "note": "不属于上面任何可组装槽位的来源，每条都写了 sourceSlotReason："
                "天秤契约（黑夜王交易）、场景互动（蝴蝶、陨石）、没有任何池／物品引用的 AttachEffectParam 行、"
                "只能从其它 SpEffect 链式到达的行等。"}),
])
SOURCE_SLOT_ORDER = {key: index for index, key in enumerate(SOURCE_SLOTS)}

OUTPUT_CLASSES: "OrderedDict[str, dict[str, str]]" = OrderedDict([
    ("skill", {"zh": "战技", "en": "Skill (Ash of War)", "delivery": "weapon",
               "population": "skills 数据集里每个有伤害段的战技（skills[].hits 去掉 noDamage／noVariant 段）"
                             "——子类别取 AtkParam_Pc.subCategory1..5；战技射出的子弹段同样算"}),
    ("sorcery", {"zh": "魔法", "en": "Sorcery", "delivery": "sorcery",
                 "population": "skills 数据集 spells[] 里 kind=sorcery 且有伤害段的法术——子类别取 "
                               "Magic.subCategory1..2（流派）∪ 命中段 AtkParam_Pc.subCategory1..5（蓄力 110 等）"}),
    ("incantation", {"zh": "祷告", "en": "Incantation", "delivery": "incantation",
                     "population": "spells[] 里 kind=incantation 且有伤害段的祷告，子类别口径同上"}),
    ("melee", {"zh": "近战普通攻击", "en": "Melee armament attack", "delivery": "weapon",
               "population": "AtkParam_Pc 中行名为空（武器动作行）、带 130 近战武器攻击、throwFlag=0、"
                             "且不带战技／技艺／绝招／远程／道具类子类别的行。"
                             "注意这个口径是**用 130 本身定义的**，所以『提升近战攻击力』[130] 对 melee 判 yes 是定义使然；"
                             "独立旁证见 diagnostics.meleePopulationCheck：按各武器 behaviorVariationId 在 BehaviorParam_PC"
                             "（refType 0）实际引用的有伤害的无名行里，不带 130 的只有骑马攻击（101）等少数行"
                             "（本作没有骑乘，推断是沿用行，未实测）；"
                             "没有任何子类别的无名行不计入，其中有伤害且被武器引用的逐条列在 "
                             "meleePopulationCheck.unnamedNoSubcategoryDamagingReferencedByWeapons"}),
    ("ranged", {"zh": "弓弩普通射击", "en": "Ranged armament attack", "delivery": "weapon",
                "population": "AtkParam_Pc 中 isArrowAtk=1、不带 112 战技攻击的行（普通射击；战技箭算 skill）"}),
    ("throw", {"zh": "致命一击（背刺／破防处决）", "en": "Critical hit (throw attack)", "delivery": "throw",
               "population": "AtkParam_Pc 中 throwFlag=2（ATK_PATAM_THROWFLAG_TYPE：Throw）的行"}),
])

APPLIES_TO_VALUES = OrderedDict([
    ("yes", "对这类输出生效（仍要按 rates 的属性与伤害构成加权）"),
    ("no", "对这类输出不生效——页面应虚化并显示 reason"),
    ("conditional", "要看具体的战技／法术／持武器的手／攻击情境：requires 给出机读条件，"
                    "matchShare 是按人口实测的命中比例（战技、法术按条目，近战／射击／致命一击按 AtkParam 行）"),
])
APPLIES_RANK = {"no": 0, "conditional": 1, "yes": 2}

# economy fields that are meaningful for one of the six outputs; every other
# economy field (ultimate gauge, character-skill cooldown, goods, regain,
# spell-buff duration) never changes the damage of these six outputs.
ECONOMY_OUTPUTS: dict[str, dict[str, str]] = {
    "artsConsumptionRate": {"skill": "yes"},
    "magicConsumptionRate": {"sorcery": "yes"},
    "miracleConsumptionRate": {"incantation": "yes"},
    "bowDistRate": {"ranged": "yes", "skill": "conditional"},
}

# Paramdex WEP_TYPE (NR/Param Enums/WEP_TYPE.json @ SMITHBOX_COMMIT), English
# labels only; the Chinese label is resolved from CL_MenuText 60000-60200 by
# matching the English text, so no Chinese is hand-typed here.
WEP_TYPE_EN: dict[int, str] = {
    1: "Dagger", 3: "Straight Sword", 5: "Greatsword", 7: "Colossal Sword",
    9: "Curved Sword", 11: "Curved Greatsword", 13: "Katana", 14: "Twinblade",
    15: "Thrusting Sword", 16: "Heavy Thrusting Sword", 17: "Axe", 19: "Greataxe",
    21: "Hammer", 23: "Great Hammer", 24: "Flail", 25: "Spear", 28: "Great Spear",
    29: "Halberd", 31: "Reaper", 33: "Fist (Unarmed)", 35: "Fist", 37: "Claw",
    39: "Whip", 41: "Colossal Weapon", 50: "Light Bow", 51: "Bow", 53: "Greatbow",
    55: "Crossbow", 56: "Ballista", 57: "Glintstone Staff", 61: "Sacred Seal",
    65: "Small Shield", 67: "Medium Shield", 69: "Greatshield", 81: "Arrow",
    83: "Greatarrow", 85: "Bolt", 86: "Greatbolt", 87: "Torch",
}
RANGED_WEP_TYPES = {50, 51, 53, 55, 56}
SORCERY_CATALYST_WEP_TYPES = {57}
INCANTATION_CATALYST_WEP_TYPES = {61}

# Hero order used by CL_MenuText 288050+i (name), 411010+i (skill), 413010+i
# (ultimate) -- the same order AttachEffectFilterSubCategoryParam uses.
HERO_TEXT_BASE = {"name": 288050, "skill": 411010, "ultimate": 413010, "passive": 415010}
HERO_ORDER = ["Wylder", "Guardian", "Ironeye", "Duchess", "Raider", "Revenant",
              "Recluse", "Executor", "Scholar", "Undertaker"]

# AtkParam subcategories that make a row something other than a plain melee
# armament attack (used to carve the melee population out of AtkParam_Pc).
NON_MELEE_SUBCATEGORIES = {105, 106, 107, 108, 109, 110, 111, 112, 113, 114, 116, 117,
                           118, 120, 121, 122, 123, 126}
HERO_ONLY_SUBCATEGORIES = {122, 123}
ITEM_SUBCATEGORIES = {108, 109, 114, 120, 121}

# English tail phrases of script-applied rows -> Chinese, for suggestedNameZh
# only.  Longest first; applied as whole-token replacements.  Anything these
# cannot translate stays visible in suggestedNameZhUntranslated so the gap is
# measurable instead of silently English.
TAIL_PHRASES_ZH: list[tuple[str, str]] = [
    (r"Attack and Poise Buff \+ Fire Weapon VFX", "攻击力与削韧增益"),
    # v6 (display-name detail): 死诞者 is the game's own word for "Those Who
    # Live in Death" (ArtsCaption 604/605/1053, 『对死诞者的伤害尤为巨大』)
    (r"Damage/Defen[cs]e/Stamina Buff", "伤害／防御／精力增益"),
    (r"Anti-Undead/Damage Buff", "对死诞者特效／伤害增益"),
    (r"Boost Physical and Fire Damage", "提升物理与火属性伤害"),
    (r"Throw Damage Adjust", "致命一击伤害修正"),
    (r"Successive Attack Boost", "连续攻击加成"),
    (r"On-Hit Weapon Effect (\d+)", r"命中时武器效果\1"),
    (r"Attack/Defen[cs]e/Poise", "攻击力／防御力／强韧度"),
    (r"Damage/Stagger Buff", "伤害／削韧增益"),
    (r"Damage/Defen[cs]e Buff", "伤害／防御增益"),
    (r"Damage/Defen[cs]e Change", "伤害／防御调整"),
    (r"Anti-Undead Buff", "对死诞者特效增益"),
    (r"Ultimate Power Adjust", "绝招威力调整"),
    (r"Enemy Attack Debuff", "降低敌人攻击力"),
    (r"Spirit Stat Change", "灵魂数值调整"),
    (r"Beast Attack Boost", "兽化攻击力提升"),
    (r"Beast Depth (\d+)", r"兽化・深度\1"),
    (r"Apply State Info", "状态标记"),
    (r"Attack Boost", "攻击力提升"),
    (r"Damage Reduction", "伤害降低"),
    (r"Damage Buff", "伤害增益"),
    (r"Weapon Buff", "武器增益"),
    (r"Aura Buff", "光环增益"),
    (r"No FP", "无专注值版"),
    (r"\[NPC\]", "NPC专用版"),
    # v6 (re-verify): 「第N层」 like the accumulator tiers (accumulatorLadder),
    # so 3558..3561 read 连刺破露滴（第1层）..（第4层） in one style
    (r"\(Tier (\d+) Boost\)", r"第\1层"),
    # v6 (re-verify): 1731002 / 1731003 (The Flame of Frenzy, Self vs Charged
    # Self Madness +4) had no Chinese detail and fell back to #spEffectId
    (r"\bSelf Madness \+\d+", "自身累积"),
    (r"\bCharged\b", "蓄力"),
    (r"\(Add (\d+) damage\)", r"伤害+\1"),
    (r"Level (\d+)", r"等级\1"),
    (r"Depth (\d+)", r"深度\1"),
    (r"\bRight-Hand\b", "右手"),
    (r"\bLeft-Hand\b", "左手"),
    (r"\bRight\b", "右手"),
    (r"\bLeft\b", "左手"),
    (r"\bSelf\b", "自身"),
    (r"\bAllies\b", "队友"),
    (r"\bStart\b", "起始"),
    (r"\bBuff\b", "增益"),
    (r"\b(\d+)$", r"\1"),
]
# Latin letters allowed inside a Chinese display name (self_check): the NPC
# marker of TAIL_PHRASES_ZH and the game's own HP / FP abbreviations.
ZH_LATIN_ALLOWED = {"NPC", "HP", "FP"}
ZH_LATIN_RE = re.compile(r"[A-Za-z]+")


def zh_latin_residue(text: str | None) -> list[str]:
    """Latin words left in a Chinese display string (empty = fully Chinese)."""
    return [w for w in ZH_LATIN_RE.findall(text or "") if w not in ZH_LATIN_ALLOWED]
# Stems that no FMG names.  Each entry says where the Chinese comes from.
MANUAL_STEMS_ZH: dict[str, tuple[str, str]] = {
    "Attack Stance": ("攻击架式", "手工翻译：Paramdex 行名 [AoW] Attack Stance，ArtsName 无此战技（本作未实装的战技行）"),
    "Golden Great Arrow": ("黄金大箭", "WeaponCaption 42030000（黄金树大弓说明文）原文用词「黄金大箭」"),
    "Fallen Meteroite": ("坠落陨石", "手工翻译：Paramdex 行名 [Interactable Effect] Fallen Meteroite（场景互动）"),
    "Charge": ("蓄力", "手工翻译：Paramdex 行名 [Flail] Charge"),
}


def load_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def has_weight(row: dict[str, str]) -> bool:
    """Effective pool membership: base weight or DLC weight above zero.

    AttachEffectTableParam carries two weights; chanceWeight_dlc (!= -1)
    overrides for owners of the DLC.  Six Scholar / Undertaker affixes sit in
    pool 2200000 with chanceWeight=0 but chanceWeight_dlc=40/160, which is
    why the affix catalog lists 283 members where the base weight shows 277.
    """
    for key in ("chanceWeight", "chanceWeight_dlc"):
        try:
            if float(row.get(key) or "-1") > 0:
                return True
        except ValueError:
            continue
    return False


def pool_members(table_rows: list[dict[str, str]]) -> dict[str, list[str]]:
    members: dict[str, list[str]] = defaultdict(list)
    for row in table_rows:
        attach_id = ref(row.get("attachEffectId"))
        if attach_id and has_weight(row) and attach_id not in members[row["ID"]]:
            members[row["ID"]].append(attach_id)
    return members


def potency_of(name: str | None) -> int | None:
    match = re.search(r"\bPotency (\d+)\b", name or "")
    return int(match.group(1)) if match else None


def subcategory_set(row: dict[str, str], fields: tuple[str, ...]) -> frozenset[int]:
    out = set()
    for field in fields:
        try:
            value = int(row.get(field) or "0")
        except ValueError:
            continue
        if value:
            out.add(value)
    return frozenset(out)


ATK_SUB_FIELDS = tuple(f"subCategory{i}" for i in range(1, 6))
MAGIC_SUB_FIELDS = ("subCategory1", "subCategory2")


class AttackPopulations:
    """Measured attack signatures per output class (see OUTPUT_CLASSES)."""

    def __init__(self, atk_pc: dict[str, dict[str, str]], magic_rows: dict[str, dict[str, str]],
                 skills_data: dict[str, Any], bullet_atk_ids: set[str]) -> None:
        self.items: dict[str, list[dict[str, Any]]] = {"skill": [], "sorcery": [], "incantation": []}
        self.rows: dict[str, Counter] = {"melee": Counter(), "ranged": Counter(), "throw": Counter()}
        self.skill_index: dict[str, Any] = {}
        self.spell_index: dict[str, Any] = {}
        missing_atk: set[int] = set()

        def hit_sets(hits: list[dict[str, Any]], extra: frozenset[int]) -> Counter:
            sets: Counter = Counter()
            for hit in hits:
                # v3：TAE 判定永远打不出的段（notInvoked）不进实测人口，与三端页面的取段口径一致
                if hit.get("noDamage") or hit.get("noVariant") or hit.get("notInvoked"):
                    continue
                atk = atk_pc.get(str(hit.get("atkId")))
                if atk is None:
                    missing_atk.add(int(hit.get("atkId") or 0))
                    continue
                sets[subcategory_set(atk, ATK_SUB_FIELDS) | extra] += 1
            return sets

        for skill in skills_data.get("skills", []):
            sets = hit_sets(skill.get("hits") or [], frozenset())
            if not sets:
                continue
            item = {"id": int(skill["id"]), "nameZh": skill.get("nameZh") or skill.get("nameEn"),
                    "sets": sets}
            self.items["skill"].append(item)
            self.skill_index[str(skill["id"])] = {
                "nameZh": item["nameZh"],
                "subCategorySets": [{"subs": sorted(s), "hits": n}
                                    for s, n in sorted(sets.items(), key=lambda kv: (sorted(kv[0]), kv[1]))],
            }
        for spell in skills_data.get("spells", []):
            kind = spell.get("kind")
            if kind not in ("sorcery", "incantation"):
                continue
            magic_row = magic_rows.get(str(spell["id"])) or {}
            magic_subs = subcategory_set(magic_row, MAGIC_SUB_FIELDS)
            sets = hit_sets(spell.get("hits") or [], magic_subs)
            if not sets:
                continue
            item = {"id": int(spell["id"]), "nameZh": spell.get("nameZh") or spell.get("nameEn"),
                    "sets": sets}
            self.items[kind].append(item)
            self.spell_index[str(spell["id"])] = {
                "nameZh": item["nameZh"],
                "kind": kind,
                "magicSubCategories": sorted(magic_subs),
                "subCategorySets": [{"subs": sorted(s), "hits": n}
                                    for s, n in sorted(sets.items(), key=lambda kv: (sorted(kv[0]), kv[1]))],
            }
        for atk in atk_pc.values():
            subs = subcategory_set(atk, ATK_SUB_FIELDS)
            name = (atk.get("Name") or "").strip()
            if atk.get("throwFlag") == "2":
                self.rows["throw"][subs] += 1
                continue
            if atk.get("throwFlag") != "0":
                continue
            if atk.get("isArrowAtk") == "1":
                # only rows a Bullet actually fires (1200-3xxx are unreferenced
                # leftovers), and not the throwing-knife / stone item rows
                if (atk["ID"] in bullet_atk_ids and 112 not in subs
                        and not subs & (HERO_ONLY_SUBCATEGORIES | ITEM_SUBCATEGORIES)):
                    self.rows["ranged"][subs] += 1
                continue
            if not name and 130 in subs and not subs & NON_MELEE_SUBCATEGORIES:
                self.rows["melee"][subs] += 1
        self.missing_atk_ids = sorted(missing_atk)

    def match(self, cls: str, wanted: frozenset[int]) -> tuple[str, float, list[str]]:
        """(value, share, notes) for a magicSubCategoryChange set on one class."""
        if cls in self.items:
            items = self.items[cls]
            if not items:
                return "no", 0.0, []
            any_hits = [item for item in items if any(s & wanted for s in item["sets"])]
            all_hits = [item for item in items if all(s & wanted for s in item["sets"])]
            share = round(len(any_hits) / len(items), 4)
            if not any_hits:
                return "no", 0.0, []
            if len(all_hits) == len(items):
                return "yes", 1.0, []
            if len(any_hits) == len(items):
                partial = [i["nameZh"] for i in items if i not in all_hits]
                return "conditional", share, [f"全部 {len(items)} 个都有这类段，但 {len(partial)} 个只有部分段带"
                                              f"（例：{'、'.join(partial[:5])}）"]
            if share >= 0.5:
                without = [i["nameZh"] for i in items if i not in any_hits]
                return "conditional", share, [f"{len(items)} 个里 {len(any_hits)} 个有这类段"
                                              f"（没有的：{'、'.join(without[:6])}{'…' if len(without) > 6 else ''}）"]
            with_ = [i["nameZh"] for i in any_hits]
            return "conditional", share, [f"{len(items)} 个里只有 {len(any_hits)} 个有这类段"
                                          f"（{'、'.join(with_[:6])}{'…' if len(with_) > 6 else ''}）"]
        rows = self.rows[cls]
        total = sum(rows.values())
        if not total:
            return "no", 0.0, []
        hit = sum(n for subs, n in rows.items() if subs & wanted)
        share = round(hit / total, 4)
        if hit == 0:
            return "no", 0.0, []
        if hit == total:
            return "yes", 1.0, []
        return "conditional", share, [f"AtkParam_Pc 里 {total} 行中 {hit} 行带这类子类别"]

    def counts(self) -> dict[str, int]:
        out = {cls: len(items) for cls, items in self.items.items()}
        out.update({cls: sum(rows.values()) for cls, rows in self.rows.items()})
        return out


def atk_row_deals_damage(atk: dict[str, str]) -> bool:
    fields = ATK_CORRECTION_FIELDS + ["atkPhys", "atkMag", "atkFire", "atkThun", "atkDark"]
    for field in fields:
        try:
            if float(atk.get(field) or "0") != 0:
                return True
        except ValueError:
            continue
    return False


def melee_population_check(atk_pc: dict[str, dict[str, str]], weapons_by_id: dict[str, dict[str, str]],
                           weapon_names_zh: dict[str, str]) -> dict[str, Any]:
    """Cross-check of the melee population (outputClass.melee) against the rows
    the armaments actually use.

    The melee population is *defined* as unnamed AtkParam_Pc rows carrying 130
    (近战武器攻击), so 『提升近战攻击力』 [130] is melee=yes by construction.  This
    measures what that definition leaves out: (a) unnamed non-throw non-arrow
    rows with no subcategory at all, split into zero-damage and damaging rows;
    (b) the independent route -- AtkParam_Pc rows referenced by
    BehaviorParam_PC (refType 0 = attack) of every named weapon's
    behaviorVariationId -- and how many of those lack 130.
    """
    no_sub = [a for a in atk_pc.values()
              if a.get("throwFlag") == "0" and a.get("isArrowAtk") != "1"
              and not (a.get("Name") or "").strip() and not subcategory_set(a, ATK_SUB_FIELDS)]
    no_sub_damaging = sorted(int(a["ID"]) for a in no_sub if atk_row_deals_damage(a))
    variations = {w.get("behaviorVariationId") for wid, w in weapons_by_id.items()
                  if weapon_names_zh.get(wid) and ref(w.get("behaviorVariationId"))}
    referenced = {row["refId"] for row in read_param("BehaviorParam_PC")
                  if row.get("refType") == "0" and row.get("variationId") in variations}
    with_130 = 0
    without: Counter = Counter()
    without_ids: list[int] = []
    for atk_id in referenced:
        atk = atk_pc.get(atk_id)
        if (atk is None or (atk.get("Name") or "").strip() or atk.get("throwFlag") != "0"
                or atk.get("isArrowAtk") == "1" or not atk_row_deals_damage(atk)):
            continue
        subs = subcategory_set(atk, ATK_SUB_FIELDS)
        if 130 in subs:
            with_130 += 1
        else:
            without[",".join(str(v) for v in sorted(subs)) or "-"] += 1
            without_ids.append(int(atk_id))
    no_sub_referenced = sorted(int(a["ID"]) for a in no_sub if a["ID"] in referenced and atk_row_deals_damage(a))
    blocks: Counter = Counter("<1000000" if v < 1_000_000 else str(v // 1000 * 1000) for v in no_sub_damaging)
    return {
        "unnamedNoSubcategoryRows": len(no_sub),
        "unnamedNoSubcategoryZeroDamage": len(no_sub) - len(no_sub_damaging),
        "unnamedNoSubcategoryDamaging": len(no_sub_damaging),
        "unnamedNoSubcategoryDamagingByIdBlock": dict(sorted(blocks.items(), key=lambda kv: (-kv[1], kv[0]))),
        "unnamedNoSubcategoryDamagingReferencedByWeapons": no_sub_referenced,
        "weaponBehaviorVariations": len(variations),
        "weaponBehaviorDamagingRows": with_130 + sum(without.values()),
        "weaponBehaviorRowsWith130": with_130,
        "weaponBehaviorRowsWithout130BySubCategories": dict(sorted(without.items(), key=lambda kv: (-kv[1], kv[0]))),
        "weaponBehaviorRowsWithout130": sorted(without_ids),
    }


def sub_label(value: int) -> str:
    zh, _en = ATK_SUB_CATEGORY.get(value, (str(value), str(value)))
    return f"{value} {zh}"


def evaluate_applies_to(row: dict[str, str], target: str, rates: dict[str, Any],
                        pops: AttackPopulations, wep_type_zh: dict[int, str],
                        named_wep_types: set[int], skill_wep_types: set[int]) -> "OrderedDict[str, dict]":
    """Per-output verdict for one SpEffect row.  Pure function of the row."""
    out: "OrderedDict[str, dict]" = OrderedDict()
    groups = {RATE_FIELD_BY_KEY[key]["group"] for key in rates}
    live_groups = groups - {"flag"}
    economy_only = live_groups == {"economy"}
    wep = int(row.get("wepParamChange") or "0")
    mag = row.get("magParamChange") == "1"
    mir = row.get("miracleParamChange") == "1"
    thr = row.get("throwAttackParamChange") == "1"
    state = int(row.get("stateInfo") or "0")
    on_type = int(row.get("triggerOnWepType") or "0")
    attached = row.get("triggerAttachedWeapon") == "1"
    sp_attr = int(row.get("spAttribute") or "254")
    atk_attr = int(row.get("atkAttribute") or "254")
    subs = frozenset(int(row[f"magicSubCategoryChange{i}"]) for i in (1, 2, 3)
                     if int(row[f"magicSubCategoryChange{i}"]))

    def type_name(value: int) -> str:
        return wep_type_zh.get(value) or f"武器类别 {value}"

    for cls, spec in OUTPUT_CLASSES.items():
        gates: list[tuple[str, str, dict[str, Any]]] = []
        share: float | None = None
        if target in ("enemy", "summon"):
            gates.append(("no", f"target={target}（挂在{'被命中的敌人' if target == 'enemy' else '召唤物'}身上）", {}))
        elif economy_only:
            hits = [(key, ECONOMY_OUTPUTS[key][cls]) for key in rates
                    if key in ECONOMY_OUTPUTS and cls in ECONOMY_OUTPUTS[key]]
            if hits:
                value = max((v for _k, v in hits), key=lambda v: APPLIES_RANK[v])
                req = {"subCategoriesAny": [105]} if value == "conditional" else {}
                gates.append((value, "只含消耗／射程类字段：" + "、".join(
                    f"{RATE_FIELD_BY_KEY[k]['zh']}" for k, _v in hits)
                    + ("（弓系战技才有射程衰减）" if value == "conditional" else ""), req))
            else:
                labels = "、".join(RATE_FIELD_BY_KEY[k]["zh"] for k in rates
                                  if RATE_FIELD_BY_KEY[k]["group"] == "economy")
                gates.append(("no", f"只含 {labels}，不改变{spec['zh']}的伤害", {}))
        else:
            # --- hard state gates -------------------------------------------
            if state == 367:
                gates.append(("yes" if cls == "throw" else "no",
                              "stateInfo=367（强化致命一击）：只作用于致命一击", {}))
            # --- delivery ----------------------------------------------------
            delivery = spec["delivery"]
            if delivery == "weapon":
                if thr:
                    gates.append(("no", "throwAttackParamChange=1：这一行只作用于致命一击（投げ攻撃）", {}))
                elif wep == 3:
                    gates.append(("no", "wepParamChange=3（自身）：不作用于武器攻击", {}))
                elif wep == 4:
                    gates.append(("no", "wepParamChange=4：只作用于踢击", {}))
                elif wep in (1, 2):
                    gates.append(("conditional", f"wepParamChange={wep}：只作用于{WEP_CHANGE_PARAM[wep][0]}的攻击",
                                  {"hand": wep}))
            elif delivery == "throw":
                if not thr:
                    if wep in (3, 4):
                        gates.append(("no", f"wepParamChange={wep}：不作用于武器攻击", {}))
                    elif wep in (1, 2):
                        gates.append(("conditional", f"wepParamChange={wep}：只作用于{WEP_CHANGE_PARAM[wep][0]}的攻击",
                                      {"hand": wep}))
                    else:
                        gates.append(("yes", "throwAttackParamChange=0：按推断同样作用于致命一击（见 notes.appliesTo）", {}))
            elif delivery == "sorcery":
                if not mag:
                    gates.append(("no", "magParamChange=0：参数声明不作用于魔法", {}))
                elif wep in (1, 2):
                    gates.append(("conditional", f"wepParamChange={wep}（{WEP_CHANGE_PARAM[wep][0]}）＋magParamChange=1："
                                                 "法术是否按施法器所在的手判定未实测", {"hand": wep}))
            elif delivery == "incantation":
                if not mir:
                    gates.append(("no", "miracleParamChange=0：参数声明不作用于祷告", {}))
                elif wep in (1, 2):
                    gates.append(("conditional", f"wepParamChange={wep}（{WEP_CHANGE_PARAM[wep][0]}）＋miracleParamChange=1："
                                                 "法术是否按施法器所在的手判定未实测", {"hand": wep}))
            # --- armament type the attack is made with ---------------------------
            if on_type:
                name = type_name(on_type)
                if on_type not in named_wep_types:
                    gates.append(("no", f"triggerOnWepType={on_type}（{name}）：本作没有任何这一类别的武器，实际不会生效", {}))
                elif cls == "sorcery":
                    gates.append(("yes", f"triggerOnWepType={on_type}（{name}）：魔法由手杖施放", {})
                                 if on_type in SORCERY_CATALYST_WEP_TYPES else
                                 ("no", f"triggerOnWepType={on_type}：只作用于用{name}发动的攻击，魔法由手杖施放", {}))
                elif cls == "incantation":
                    gates.append(("yes", f"triggerOnWepType={on_type}（{name}）：祷告由圣印记施放", {})
                                 if on_type in INCANTATION_CATALYST_WEP_TYPES else
                                 ("no", f"triggerOnWepType={on_type}：只作用于用{name}发动的攻击，祷告由圣印记施放", {}))
                elif cls == "ranged":
                    gates.append(("conditional", f"triggerOnWepType={on_type}：只作用于用{name}射出的攻击",
                                  {"attackWeaponTypes": [on_type]})
                                 if on_type in RANGED_WEP_TYPES else
                                 ("no", f"triggerOnWepType={on_type}（{name}）不是弓弩类", {}))
                elif cls == "skill" and on_type not in skill_wep_types:
                    gates.append(("no", f"triggerOnWepType={on_type}（{name}）：没有这一类武器带有伤害战技", {}))
                elif cls in ("melee", "throw") and on_type in RANGED_WEP_TYPES:
                    gates.append(("no", f"triggerOnWepType={on_type}（{name}）是弓弩类", {}))
                else:
                    gates.append(("conditional", f"triggerOnWepType={on_type}：只作用于用{name}发动的攻击"
                                                 f"（{'所选战技所在的武器' if cls == 'skill' else '当前出手的武器'}须为{name}）",
                                  {"attackWeaponTypes": [on_type]}))
            if attached:
                gates.append(("conditional", "triggerAttachedWeapon=1：只作用于带这条效果的那把武器发动的攻击",
                              {"attachedWeaponOnly": True}))
            if sp_attr != 254 and wep == 0 and delivery in ("weapon", "throw"):
                zh_attr = SP_ATTR_TYPE.get(sp_attr, (str(sp_attr), ""))[0]
                gates.append(("conditional", f"spAttribute={sp_attr}（{zh_attr}）：附加属性负载，只对被附加的那把武器生效",
                                      {"imbuedWeaponOnly": True}))
            if atk_attr != 254:
                zh_attr = ATK_ATTR_TYPE.get(atk_attr, (str(atk_attr), ""))[0]
                gates.append(("conditional", f"atkAttribute={atk_attr}：只作用于物理攻击类型为{zh_attr}的段",
                              {"physicalType": atk_attr}))
            if state == 197:
                # v6 (re-verify): the counter is "unique to thrusting weapons"
                # (矛护符 AccessoryInfo#2060 『能强化突刺攻击特有的反击攻击』／
                # "Enhances counterattacks unique to thrusting weapons"), so a
                # spell or a bow shot never enters it; only weapon swings and
                # Ashes of War do.
                if cls == "throw":
                    gates.append(("no", "stateInfo=197（强化突刺反击）：致命一击不是反击", {}))
                elif cls in ("sorcery", "incantation", "ranged"):
                    gates.append(("no", "stateInfo=197（强化突刺反击）：突刺反击只由突刺类武器的近战攻击／战技触发"
                                        "（矛护符 AccessoryInfo#2060『能强化突刺攻击特有的反击攻击』），"
                                        f"{spec['zh']}不会进入这种情境", {}))
                else:
                    gates.append(("conditional", "stateInfo=197（强化突刺反击）：只在突刺反击时生效",
                                  {"attackContexts": ["thrustingCounter"]}))
            # --- attack sub-categories ------------------------------------------
            if subs:
                labels = "、".join(sub_label(v) for v in sorted(subs))
                if subs <= HERO_ONLY_SUBCATEGORIES:
                    gates.append(("no", f"子类别限定 [{labels}]：只作用于角色技艺／绝招，不在这六类输出内", {}))
                else:
                    value, share_here, notes = pops.match(cls, subs)
                    if value == "no":
                        gates.append(("no", f"子类别限定 [{labels}]：{spec['zh']}的命中段都不带这类子类别", {}))
                    elif value == "conditional":
                        share = share_here
                        gates.append(("conditional", f"子类别限定 [{labels}]：" + "；".join(notes),
                                      {"subCategoriesAny": sorted(subs)}))
                    else:
                        gates.append(("yes", f"子类别限定 [{labels}]：{spec['zh']}的命中段全部带这类子类别", {}))
        verdict = min((g[0] for g in gates), key=lambda v: APPLIES_RANK[v]) if gates else "yes"
        if verdict == "yes":
            reasons = [g[1] for g in gates] or [_default_yes_reason(cls, wep, mag, mir)]
        else:
            reasons = [g[1] for g in gates if g[0] != "yes"]
        entry: dict[str, Any] = {"value": verdict, "reason": "；".join(dict.fromkeys(reasons))}
        if verdict == "conditional":
            requires: dict[str, Any] = {}
            for value, _reason, req in gates:
                if value == "conditional":
                    requires.update(req)
            entry["requires"] = requires
            if share is not None:
                entry["matchShare"] = share
        out[cls] = entry
    return out


def _default_yes_reason(cls: str, wep: int, mag: bool, mir: bool) -> str:
    if cls == "sorcery":
        return "magParamChange=1，且没有子类别／武器类别限制"
    if cls == "incantation":
        return "miracleParamChange=1，且没有子类别／武器类别限制"
    return f"wepParamChange={wep}（{WEP_CHANGE_PARAM.get(wep, ('?', '?'))[0]}），且没有子类别／武器类别限制"


# --- names for script-applied rows (Q4) ---------------------------------------
TAG_RE = re.compile(r"<\?[^?]*\?>")


def plain_text(text: str | None) -> str:
    return flatten_text(TAG_RE.sub("", text or "")).strip()


def build_text_index(sources: list[tuple[str, dict[str, str], dict[str, str]]]) -> dict[str, tuple[str, str]]:
    """English FMG text (casefolded, with a leading "[X] " also indexed) -> (zh, "Fmg#id")."""
    index: dict[str, tuple[str, str]] = {}
    for fmg_name, en_map, zh_map in sources:
        for text_id in sorted(en_map, key=lambda k: int(k) if k.lstrip("-").isdigit() else 0):
            en_text = plain_text(en_map.get(text_id))
            zh_text = plain_text(zh_map.get(text_id))
            if not en_text or not zh_text:
                continue
            keys = {en_text.casefold()}
            stripped = re.sub(r"^\[[^\]]+\]\s*", "", en_text)
            keys.add(stripped.casefold())
            for key in keys:
                index.setdefault(key, (zh_text, f"{fmg_name}#{text_id}"))
    return index


def translate_phrases(text: str) -> str:
    out = text
    for pattern, replacement in TAIL_PHRASES_ZH:
        out = re.sub(pattern, replacement, out)
    return re.sub(r"\s+", "・", out.strip()).strip("・")


def suggest_name_zh(param_name: str | None, text_index: dict[str, tuple[str, str]],
                    hero_texts: dict[tuple[str, str], tuple[str, str]],
                    word_texts: dict[str, tuple[str, str]],
                    type_texts: dict[str, tuple[str, str]]) -> tuple[str | None, list[str], str | None]:
    """(suggested zh name, provenance list, untranslated residue) for a row with no own text."""
    if not param_name:
        return None, [], None
    category = row_category(param_name)
    body = clean_param_name(param_name)
    parts = [part.strip() for part in body.split(" - ") if part.strip()]
    if not parts:
        return None, [], None
    stem, tails = parts[0], parts[1:]
    provenance: list[str] = []

    def resolve(text: str) -> str | None:
        hit = text_index.get(text.casefold())
        if hit:
            provenance.append(hit[1])
            return hit[0]
        manual = MANUAL_STEMS_ZH.get(text)
        if manual:
            provenance.append("manual:" + manual[1])
            return manual[0]
        return None

    head = resolve(stem)
    if head is None:
        # longest resolvable leading run of words, the rest goes to the tail
        words = stem.split(" ")
        for cut in range(len(words) - 1, 0, -1):
            lead = resolve(" ".join(words[:cut]))
            if lead:
                head = lead
                tails = [" ".join(words[cut:])] + tails
                break
    translated_head = head is None
    if head is None:
        translated = translate_phrases(stem)
        for word, (zh_word, origin) in word_texts.items():
            if re.search(rf"\b{re.escape(word)}\b", translated):
                translated = re.sub(rf"\b{re.escape(word)}\b", zh_word, translated)
                provenance.append(origin)
        head = translated
    prefix = None
    match = re.match(r"^(Skill|Ultimate) - (\w+)$", category)
    if match and (match.group(1).lower(), match.group(2)) in hero_texts:
        prefix, origin = hero_texts[(match.group(1).lower(), match.group(2))]
        provenance.append(origin)
    elif category in type_texts and type_texts[category][0] not in head:
        prefix, origin = type_texts[category]
        provenance.append(origin)
    tail_zh = "・".join(filter(None, (translate_phrases(t) for t in tails)))
    name = head
    if prefix:
        name = f"{prefix}：{name}" if match else f"{prefix}・{name}"
    if tail_zh:
        name = f"{name}（{tail_zh}）"
    residue = " ".join(w for w in re.findall(r"[A-Za-z][A-Za-z'?]*", name) if w != "NPC") or None
    if tail_zh or translated_head:
        provenance.append("TAIL_PHRASES_ZH")
    return name, [p for p in dict.fromkeys(provenance) if p], residue


# --- pools: which AttachEffectParam rows a weapon / relic can carry ------------
def build_loadout_context(attach: dict[str, dict[str, str]],
                          attach_table: list[dict[str, str]],
                          weapons_by_id: dict[str, dict[str, str]],
                          weapon_names_zh: dict[str, str],
                          menu_zh: dict[str, str], menu_en: dict[str, str],
                          antique_names_zh: dict[str, str], antique_names_en: dict[str, str],
                          attach_names: Any) -> dict[str, Any]:
    """Everything the slot / relic / weapon-affix fields need, measured from params."""
    members = pool_members(attach_table)
    custom_rows = read_param("EquipParamCustomWeapon")
    item_table = read_param("ItemTableParam")
    lot_rows = read_param("ItemLotParam_map") + read_param("ItemLotParam_enemy")
    antiques = read_param("EquipParamAntique")
    stands = read_param("AntiqueStandParam")
    chara_init_header = list(read_param("CharaInitParam")[0].keys())
    chaos_rank = read_param("ChaosMatchingRankControlParam")
    spots = read_param("LotResultSmallBaseAndSpot")

    # ---- weapon types: zh label from CL_MenuText by English text ---------------
    menu_by_en: dict[str, tuple[str, str]] = {}
    for text_id in sorted((k for k in menu_en if k.isdigit() and 60000 <= int(k) <= 60200), key=int):
        en_text = plain_text(menu_en.get(text_id))
        zh_text = plain_text(menu_zh.get(text_id))
        if en_text and zh_text:
            menu_by_en.setdefault(en_text, (zh_text, text_id))
    wep_type_zh: dict[int, str] = {}
    wep_type_text_id: dict[int, str] = {}
    for value, en_label in WEP_TYPE_EN.items():
        hit = menu_by_en.get(en_label)
        if hit:
            wep_type_zh[value], wep_type_text_id[value] = hit
    named_wep_types = {int(row["wepType"]) for wid, row in weapons_by_id.items()
                       if weapon_names_zh.get(wid) and ref(row.get("wepType"))}

    # ---- weapon affixes -----------------------------------------------------------
    reachable = {row["itemId"] for row in item_table if row.get("itemCategory") == "6"}
    for row in lot_rows:
        for index in range(1, 9):
            if row.get(f"lotItemCategory0{index}") == "6" and ref(row.get(f"lotItemId0{index}")):
                reachable.add(row[f"lotItemId0{index}"])
    custom_by_id = {row["ID"]: row for row in custom_rows}
    weapon_affix: dict[str, dict[str, Any]] = {}
    table_info: dict[str, dict[str, Any]] = {}
    per_rarity: dict[tuple[str, str], Counter] = defaultdict(Counter)
    normal_positive_max = deep_positive_max = deep_curse_max = normal_curse_max = 0
    cursed_rows_mirror = True
    reachable_rows = 0
    # v6 (verify): the weapon blessing is a *pool family*, not a slot index.
    # isCursed 『Unique』 rows carry it in slot 3/6 (810-814 pools), but the 20
    # [Hero] / [Unique] X+2 rows (101750002-141755002) use another layout --
    # slot 1/4 = the character's fixed 601000x00 pool, slot 5 = 602000000
    # (the 17 deep-only affixes, potency 1) or 603000x00, slot 6 = the curse
    # (620/630).  603000x00 is a blessing pool: its members are a subset of an
    # 81x blessing pool (asserted in self_check via weaponAffixPools).
    # Only pools of reachable rows count, and only multi-member pools can be
    # a blessing by subset (the 808xxxxxx single-member pools of slot 1/5 are
    # a weapon's fixed affix, even when that affix also sits in an 81x pool).
    reachable_rows_list = [custom_by_id[c] for c in sorted(reachable, key=int)
                           if c in custom_by_id and custom_by_id[c]["targetWeaponId"] in weapons_by_id]
    all_tables = {t for row in reachable_rows_list
                  for t in (ref(row.get(f"attachEffectTableId_{k}")) for k in range(1, 7)) if t}
    family_blessing = {t for t in all_tables if 810 <= int(t) // 1_000_000 <= 814}
    blessing_members = [set(members.get(t, [])) for t in sorted(family_blessing, key=int)]
    blessing_tables = set(family_blessing)
    for table in all_tables:
        ids = set(members.get(table, []))
        if (table not in blessing_tables and len(ids) > 1
                and not all(attach.get(i, {}).get("isDebuff") == "1" for i in ids)
                and any(ids <= bm for bm in blessing_members)):
            blessing_tables.add(table)
    # the documented statement: the only subset-blessing pools are the 603 family
    assert {int(t) // 1_000_000 for t in blessing_tables - family_blessing} <= {603}, \
        sorted(blessing_tables - family_blessing)
    row_tables: list[tuple[bool, dict[int, str | None]]] = []
    layouts: Counter = Counter()
    for custom_id in sorted(reachable, key=int):
        row = custom_by_id.get(custom_id)
        if row is None:
            continue
        weapon = weapons_by_id.get(row["targetWeaponId"])
        if weapon is None:
            continue
        reachable_rows += 1
        wep_type = int(weapon["wepType"])
        rarity = weapon.get("rarity", "?")
        cursed = row.get("isCursed") == "1"
        tables = {k: ref(row.get(f"attachEffectTableId_{k}")) for k in range(1, 7)}
        if cursed and any(tables[k] != tables[k + 3] for k in (1, 2, 3)):
            cursed_rows_mirror = False
        row_tables.append((cursed, tables))
        layouts[("isCursed" if cursed else "regular",
                 "/".join(str(int(tables[k]) // 1_000_000) if tables[k] else "-" for k in range(1, 7)))] += 1
        counts = {"normal": [0, 0], "deep": [0, 0]}  # [positive, curse]
        for k in range(1, 7):
            table = tables[k]
            if not table:
                continue
            # slots 1-3: what the weapon carries in a normal expedition; slots
            # 4-6: its Deep of Night cursed variant.  isCursed rows mirror 1-3
            # into 4-6 and only drop in the Deep of Night (see slotRules).
            mode = "deep" if (k >= 4 or cursed) else "normal"
            if cursed and k <= 3:
                continue  # counted once through the mirrored 4-6
            ids = members.get(table, [])
            if not ids:
                continue
            is_curse = all(attach.get(i, {}).get("isDebuff") == "1" for i in ids)
            role = ("curse" if is_curse
                    else "blessing" if table in blessing_tables
                    else "fixed" if len(ids) == 1
                    else "affix")
            counts[mode][1 if is_curse else 0] += 1
            tinfo = table_info.setdefault(table, {"roles": set(), "modes": set(), "wepTypes": set(),
                                                  "slotIndexes": set(), "members": len(ids),
                                                  "potencies": set()})
            tinfo["roles"].add(role)
            tinfo["modes"].add(mode)
            tinfo["wepTypes"].add(wep_type)
            tinfo["slotIndexes"].add(k)
            tinfo["potencies"].update(p for p in (potency_of(attach.get(i, {}).get("Name")) for i in ids) if p)
            for attach_id in ids:
                info = weapon_affix.setdefault(attach_id, {
                    "normal": set(), "deep": set(), "roles": set(), "tables": set(), "rarities": set()})
                info[mode].add(wep_type)
                info["roles"].add(role)
                info["tables"].add(int(table))
                info["rarities"].add(int(rarity) if str(rarity).lstrip("-").isdigit() else rarity)
        if not cursed:
            normal_positive_max = max(normal_positive_max, counts["normal"][0])
            normal_curse_max = max(normal_curse_max, counts["normal"][1])
        if counts["deep"][0] or counts["deep"][1]:
            deep_positive_max = max(deep_positive_max, counts["deep"][0])
            deep_curse_max = max(deep_curse_max, counts["deep"][1])
        pattern = (f"normal+{counts['normal'][0]}/-{counts['normal'][1]}",
                   f"deep+{counts['deep'][0]}/-{counts['deep'][1]}")
        per_rarity[(str(rarity), "isCursed" if cursed else "regular")][" ".join(pattern)] += 1
    # a Deep of Night weapon that did *not* roll its cursed variant keeps its
    # slot-1..3 affix, so everything rollable normally is rollable deep too
    for info in weapon_affix.values():
        info["deep"] |= info["normal"]
    # v6 (verify): how many of a weapon's positive deep slots can hold a
    # deep-only affix (an AttachEffect id no slot-1..3 pool of any reachable
    # row contains).  slotRules said 2 per weapon / 12 in total, which lets a
    # page stack 12 deep-only affixes (提升物理攻击力 ×1.08 ...); every row has
    # at most one such slot (regular cursed: slot 6 = 505 pool; isCursed: the
    # 81x blessing; [Hero]/[Unique] +2: 602/603), so the cap is 6.
    deep_only_ids = {a for a, info in weapon_affix.items() if not info["normal"]}
    deep_only_slots: Counter = Counter()
    for cursed, tables in row_tables:
        count = 0
        for k in range(1, 7):
            table = tables[k]
            if not table or k <= 3:   # 1-3 = normal expedition (isCursed rows mirror them into 4-6)
                continue
            ids = members.get(table, [])
            if not ids or all(attach.get(i, {}).get("isDebuff") == "1" for i in ids):
                continue
            if set(ids) & deep_only_ids:
                count += 1
        deep_only_slots[count] += 1
    distinct_weighted_ids = set(weapon_affix)
    # v6 (re-verify): deep_only_ids also holds the curses (they only ever sit
    # in slots 4-6), and weaponAffixes[].deepOnly / buffs[].weaponAffixDeepOnly
    # follow it.  The 1-per-weapon cap measured above counts *positive* slots
    # only; a page that capped every deepOnly=true row would refuse the legal
    # 6 curses + 6 deep-only affixes.  Split the ids for the evidence and the
    # deepOnlyPositive flags.
    deep_only_curse_ids = {a for a in deep_only_ids if attach.get(a, {}).get("isDebuff") == "1"}
    deep_only_positive_ids = deep_only_ids - deep_only_curse_ids
    # v6 (re-verify): can one weapon roll the same affix twice?  On regular
    # rows the slot-6 pool (505) contains every member of the slot-5 pool
    # (501 / 808), so nothing in the pools prevents it; whether the lottery
    # de-duplicates (as relics do by compatibilityId) is not in the params.
    overlap_rows = 0
    positive_pair_rows = 0
    for cursed, tables in row_tables:
        positive = [set(members.get(tables[k], [])) for k in (4, 5, 6)
                    if tables[k] and members.get(tables[k])
                    and not all(attach.get(i, {}).get("isDebuff") == "1" for i in members.get(tables[k], []))]
        if len(positive) == 2:
            positive_pair_rows += 1
            if positive[0] & positive[1]:
                overlap_rows += 1
    # v6 (re-verify): "rarity -> potency" is the main potency of the pool, not
    # its only one -- the uncommon 501x00100 pools also hold 3 potency-1
    # members, the rare 501x00200 pools 2 potency-1 and 1 potency-2.  Counts
    # per potency, as [min, max] over the 501X / 505X weapon-type groups.
    potency_by_tier: dict[str, dict[int, list[int]]] = {}
    for table in table_info:
        family = int(table) // 1_000_000
        if family not in (501, 505):
            continue
        tier_key = f"{family}x00{(int(table) % 1000) // 100}00"
        counts = Counter(potency_of(attach.get(a, {}).get("Name")) for a in members.get(table, []))
        counts.pop(None, None)
        slot = potency_by_tier.setdefault(tier_key, {})
        for potency in set(slot) | set(counts):
            got = counts.get(potency, 0)
            low, high = slot.get(potency, [got, got])
            slot[potency] = [min(low, got), max(high, got)]
    # potency of the deep-only positive affixes by pool family (505 = regular
    # cursed weapons' slot 6, 602 = [Hero] +2 slot 5, 81x / 603 = blessing)
    deep_only_potency_by_family: dict[str, set[int]] = defaultdict(set)
    for table, info in table_info.items():
        for attach_id in set(members.get(table, [])) & deep_only_positive_ids:
            potency = potency_of(attach.get(attach_id, {}).get("Name"))
            if potency:
                deep_only_potency_by_family[str(int(table) // 1_000_000)].add(potency)

    innate: dict[str, list[str]] = defaultdict(list)
    for wid in sorted(weapons_by_id, key=int):
        attach_id = ref(weapons_by_id[wid].get("attachEffectId"))
        if attach_id and weapon_names_zh.get(wid):
            innate[attach_id].append(wid)

    # ---- relic pools (named, enabled relics only) --------------------------------
    relic_tables: dict[str, dict[str, Any]] = {}
    named_relics = []
    for row in antiques:
        if row.get("disableParam_NT") != "0" or not antique_names_zh.get(row["ID"]):
            continue
        named_relics.append(row)
        deep = row.get("isDeepRelic") == "1"
        for k in (1, 2, 3):
            table = ref(row.get(f"attachEffectTableId_{k}"))
            curse_table = ref(row.get(f"attachEffectTableId_curse{k}"))
            if table:
                spec = relic_tables.setdefault(table, {"deep": set(), "paired": set(), "curse": False, "rows": 0})
                spec["deep"].add(deep)
                spec["paired"].add(bool(curse_table))
                spec["rows"] += 1
            if curse_table:
                spec = relic_tables.setdefault(curse_table, {"deep": set(), "paired": set(), "curse": True, "rows": 0})
                spec["curse"] = True
                spec["deep"].add(deep)
                spec["rows"] += 1
    relic_affix: dict[str, dict[str, Any]] = {}
    for table, spec in relic_tables.items():
        ids = members.get(table, [])
        for attach_id in ids:
            info = relic_affix.setdefault(attach_id, {
                "pools": set(), "deepTables": set(), "normalTables": set(), "curse": False,
                "pairedDeep": False, "unpairedDeep": False, "random": False})
            info["pools"].add(int(table))
            if len(ids) > 1:
                info["random"] = True
            if spec["curse"]:
                info["curse"] = True
                continue
            if True in spec["deep"]:
                info["deepTables"].add(int(table))
                if True in spec["paired"]:
                    info["pairedDeep"] = True
                if False in spec["paired"]:
                    info["unpairedDeep"] = True
            if False in spec["deep"]:
                info["normalTables"].add(int(table))

    catalog = load_json(AFFIX_CATALOG_PATH)
    catalog_by_id = {int(a["effectId"]): a for a in catalog["affixes"]}
    relic_catalog = load_json(RELIC_CATALOG_PATH)
    extra_ids = {int(a["effectId"]) for a in relic_catalog.get("extraAffixes", [])}

    # ---- fixed relics ------------------------------------------------------------
    fixed: "OrderedDict[tuple, dict[str, Any]]" = OrderedDict()
    for row in named_relics:
        slots = [ref(row.get(f"attachEffectTableId_{k}")) for k in (1, 2, 3)]
        curse_slots = [ref(row.get(f"attachEffectTableId_curse{k}")) for k in (1, 2, 3)]
        used = [t for t in slots if t]
        if not used or any(len(members.get(t, [])) != 1 for t in used):
            continue
        if any(t and len(members.get(t, [])) != 1 for t in curse_slots):
            continue
        effect_ids = [int(members[t][0]) for t in used]
        curse_ids = [int(members[t][0]) for t in curse_slots if t]
        key = (antique_names_zh[row["ID"]], row.get("relicColor"), row.get("isDeepRelic"),
               tuple(effect_ids), tuple(curse_ids))
        entry = fixed.setdefault(key, {
            "relicIds": [],
            "nameZh": antique_names_zh[row["ID"]],
            "nameEn": antique_names_en.get(row["ID"]) or None,
            "color": int(row.get("relicColor") or 0),
            "isDeepRelic": row.get("isDeepRelic") == "1",
            "attachEffectIds": effect_ids,
            "curseAttachEffectIds": curse_ids,
        })
        entry["relicIds"].append(int(row["ID"]))

    # ---- slot-count evidence -------------------------------------------------------
    weapon_columns = [c for c in chara_init_header if re.match(r"^equip_Wep_(Right|Left)_\d+$", c)]
    enabled_stands = [s for s in stands if s.get("disableParam_NT") == "0"]
    stand_normal = Counter(sum(1 for k in (1, 2, 3) if ref(s.get(f"relicSlot{k}")) is not None
                               or s.get(f"relicSlot{k}") == "0") for s in enabled_stands)
    stand_deep = Counter(sum(1 for k in (1, 2, 3) if ref(s.get(f"deepRelicSlot{k}")) is not None
                             or s.get(f"deepRelicSlot{k}") == "0") for s in enabled_stands)
    relic_affix_slots = max(sum(1 for k in (1, 2, 3) if ref(r.get(f"attachEffectTableId_{k}")))
                            for r in named_relics)
    relic_curse_slots = max(sum(1 for k in (1, 2, 3) if ref(r.get(f"attachEffectTableId_curse{k}")))
                            for r in named_relics)
    evergaol_spots: dict[str, set[str]] = defaultdict(set)
    for row in spots:
        if "Evergaol" in (row.get("Name") or ""):
            evergaol_spots[row.get("patternId", "?")].add(row.get("attachId", "?"))
    evergaol_max = max((len(v) for v in evergaol_spots.values()), default=0)
    evergaol_dist = Counter(len(v) for v in evergaol_spots.values())
    evergaol_attach = sorted({int(a) for v in evergaol_spots.values() for a in v if a.lstrip("-").isdigit()})
    # v6 (re-verify): the count above only sees patterns whose rows carry a
    # Paramdex name.  The rest (patternId 1000-1199) are unnamed rows; they do
    # not reuse any of the evergaol attachIds, but whether they hold an
    # evergaol under other attach points is not decidable from the params.
    spot_patterns: dict[str, bool] = {}
    for row in spots:
        pattern = row.get("patternId", "?")
        spot_patterns[pattern] = spot_patterns.get(pattern, False) or bool((row.get("Name") or "").strip())
    unnamed_patterns = sorted((p for p, named in spot_patterns.items() if not named),
                              key=lambda p: int(p) if p.lstrip("-").isdigit() else 0)
    evergaol_attach_set = {str(a) for a in evergaol_attach}
    unnamed_on_evergaol_attach = {row.get("patternId") for row in spots
                                  if row.get("patternId") in set(unnamed_patterns)
                                  and row.get("attachId") in evergaol_attach_set}

    return {
        "members": members,
        "weaponAffix": weapon_affix,
        "weaponTables": table_info,
        "weaponRarityPatterns": {f"{r}/{c}": dict(sorted(v.items())) for (r, c), v in sorted(per_rarity.items())},
        "weaponReachableRows": reachable_rows,
        "cursedRowsMirror": cursed_rows_mirror,
        "deepOnlySlotsPerRow": {str(k): v for k, v in sorted(deep_only_slots.items())},
        "deepOnlyPerWeaponMax": max(deep_only_slots) if deep_only_slots else 0,
        "deepOnlyAttachIds": deep_only_ids,
        "deepOnlyPositiveAttachIds": deep_only_positive_ids,
        "deepOnlyCurseAttachIds": deep_only_curse_ids,
        "deepOnlyPositivePotencyByPoolFamily": {k: sorted(v) for k, v in sorted(deep_only_potency_by_family.items())},
        "deepPositivePairRows": positive_pair_rows,
        "potencyCountsByPoolTier": {k: {str(p): v for p, v in sorted(d.items())} for k, d in sorted(potency_by_tier.items())},
        "deepPositivePairRowsWithSharedAffix": overlap_rows,
        "distinctAffixIds": len(distinct_weighted_ids),
        "slotLayouts": [{"row": kind, "slots": layout, "rows": n}
                        for (kind, layout), n in sorted(layouts.items(), key=lambda kv: (-kv[1], kv[0]))],
        "blessingTables": sorted(int(t) for t in blessing_tables),
        "blessingTablesBySubset": sorted(int(t) for t in blessing_tables - family_blessing),
        "normalPositiveMax": normal_positive_max,
        "normalCurseMax": normal_curse_max,
        "deepPositiveMax": deep_positive_max,
        "deepCurseMax": deep_curse_max,
        "chaosCursedRates": [
            {"depth": row["Name"] or row["ID"], "cursedUncommonRate": as_number(row["cursedUncommonRate"]),
             "cursedRareRate": as_number(row["cursedRareRate"])} for row in chaos_rank],
        "weaponColumns": weapon_columns,
        "innate": innate,
        "relicTables": relic_tables,
        "relicAffix": relic_affix,
        "catalogById": catalog_by_id,
        "extraIds": extra_ids,
        "fixedRelics": list(fixed.values()),
        "standCount": len(enabled_stands),
        "standNormal": {str(k): v for k, v in sorted(stand_normal.items())},
        "standDeep": {str(k): v for k, v in sorted(stand_deep.items())},
        "relicAffixSlots": relic_affix_slots,
        "relicCurseSlots": relic_curse_slots,
        "namedRelicRows": len(named_relics),
        "evergaolMax": evergaol_max,
        "evergaolPatterns": len(evergaol_spots),
        "evergaolSpotsPerPattern": {str(k): v for k, v in sorted(evergaol_dist.items(), reverse=True)},
        "evergaolAttachIdRange": [evergaol_attach[0], evergaol_attach[-1]] if evergaol_attach else None,
        "evergaolAttachIds": len(evergaol_attach),
        "spotPatterns": len(spot_patterns),
        "unnamedSpotPatterns": len(unnamed_patterns),
        "unnamedSpotPatternRange": [unnamed_patterns[0], unnamed_patterns[-1]] if unnamed_patterns else None,
        "unnamedPatternsOnEvergaolAttachIds": len(unnamed_on_evergaol_attach),
        "wepTypeZh": wep_type_zh,
        "wepTypeTextId": wep_type_text_id,
        "namedWepTypes": named_wep_types,
    }


def attach_stem_index(attach: dict[str, dict[str, str]]) -> dict[tuple[str, str], list[str]]:
    """(row-category head, param stem) -> AttachEffectParam ids, for script-applied rows."""
    index: dict[tuple[str, str], list[str]] = defaultdict(list)
    for attach_id in sorted(attach, key=int):
        name = attach[attach_id].get("Name") or ""
        stem = param_stem(name)
        if stem:
            index[(row_category(name).split(" - ")[0], stem)].append(attach_id)
    return index


def owning_attach_ids(sp_id: str, param_name: str | None, attach: dict[str, dict[str, str]],
                      stems: dict[tuple[str, str], list[str]]) -> list[str]:
    """AttachEffectParam rows a script-applied SpEffect belongs to.

    Stem match first (same rule the name borrowing uses).  For *slot*
    purposes a decade / century neighbour with the same "[...]" head is also
    accepted even when the stems differ ("Magma upon Charge Attack - Flame
    Buff" belongs to AE 8881500 "Magma upon Charge Attacks"): which slot a row
    comes from does not depend on the exact wording, only on the family.
    """
    value = int(sp_id)
    stem = re.sub(r"\s*\+\d+$", "", param_stem(param_name or ""))
    head = row_category(param_name).split(" - ")[0]
    bases = (value, value - value % 10, value - value % 100)
    for base in bases:
        row = attach.get(str(base))
        if row is not None and (not stem or re.sub(r"\s*\+\d+$", "", param_stem(row.get("Name", ""))) == stem):
            return [str(base)]
    if stem and stems.get((head, stem)):
        return list(stems[(head, stem)])
    for base in bases[1:]:
        row = attach.get(str(base))
        if row is not None and row_category(row.get("Name")).split(" - ")[0] == head:
            return [str(base)]
    # v6 (verify): a per-item variant names the item in a trailing
    # parenthetical -- 7050301 "[Relic] Items confer effect to all nearby
    # allies (Exalted Flesh)" is a row of AE 7050100 "Items confer effect to
    # all nearby allies" (whose passiveSpEffectId_1..3 are 7050100/200/300).
    # Only tried when nothing above matched, so no earlier owner changes.
    bare = re.sub(r"\s*\([^()]*\)$", "", stem)
    if bare and bare != stem and stems.get((head, bare)):
        return list(stems[(head, bare)])
    # v6 (re-verify): a relic affix whose buff rows were filed under the
    # hero's skill.  7020002 / 7020004 "[Skill - Wylder] Relic Followup Buff
    # (Right/Left Active)" (fire +20, descZh 『遗物带来的效果』) are fired by
    # 7020001 / 7020003 and belong to AE 7020000 "[Relic - Wylder] Standard
    # attacks enhanced with fiery follow-ups ..." in the same decade; the "[...]"
    # heads differ (Skill vs Relic), so none of the rules above matched and the
    # buff landed in the character column.  Accepted only when the row name
    # itself says "Relic" and the neighbour is "[Relic - <same subject>]".
    category = row_category(param_name)
    subject = category.split(" - ", 1)[1] if " - " in category else ""
    if subject and re.search(r"\bRelic\b", clean_param_name(param_name or "")):
        for base in bases[1:]:
            row = attach.get(str(base))
            if row is not None and row_category(row.get("Name")) == f"Relic - {subject}":
                return [str(base)]
    return []


def innate_owner(sp_id: str, param_name: str | None, attach: dict[str, dict[str, str]],
                 innate: dict[str, list[str]]) -> list[str]:
    """Legendary-weapon AE for a script-applied [Weapon Power] row.

    "[Weapon Power] Power of Night and Flame: Magic Damage Buff (Right)"
    (SpEffect 8980002) has no " - " so its stem never equals the AE's; it
    belongs to AE 9021400 "[Weapon Power] Power of Night and Flame" (weapon
    2140000) whose passiveSpEffectId_1 = 8980000 sits in the same century.
    Both the century and the name prefix must agree.
    """
    value = int(sp_id)
    body = clean_param_name(param_name or "").casefold()
    hits = []
    for attach_id in innate:
        row = attach.get(attach_id) or {}
        stem = param_stem(row.get("Name", ""))
        if not stem or not body.startswith(stem):
            continue
        for field in ("passiveSpEffectId_1", "passiveSpEffectId_2", "passiveSpEffectId_3", "permanentSpEffectId"):
            target = ref(row.get(field))
            if target and int(target) // 100 == value // 100:
                hits.append(attach_id)
                break
    return sorted(hits, key=int)


def slot_of_attach(attach_id: str, ctx: dict[str, Any], accessory_attach: set[str]) -> str | None:
    if attach_id in ctx["relicAffix"]:
        return "relicAffix"
    if attach_id in ctx["weaponAffix"]:
        return "weaponAffix"
    if attach_id in ctx["innate"]:
        return "weaponInnate"
    if attach_id in accessory_attach:
        return "accessory"
    return None


OTHER_CATEGORY_REASONS = {
    "Libra Deal": "天秤契约：黑夜王『天秤』交易给出的局内临时效果，不属于任何可装备槽位",
    "Interactable Effect": "场景互动：地图上的蝴蝶、陨石等交互物给的临时效果，不属于任何可装备槽位",
    "EFfect": "Paramdex 行名 [EFfect]，没有任何参数列指向它（脚本挂载），无法确认来自哪个槽位",
}


def classify_source_slots(sp_id: str, param_name: str | None, all_sources: list[dict[str, Any]],
                          ctx: dict[str, Any], attach: dict[str, dict[str, str]],
                          stems: dict[tuple[str, str], list[str]], accessory_attach: set[str],
                          grace_ids: set[str], permanent_ids: set[str]) -> dict[str, Any]:
    """Slots for one buff, from *every* source (not only the 40 exported)."""
    slots: dict[str, set[str]] = defaultdict(set)   # slot -> attach ids that put it there
    reasons: list[str] = []
    for entry in all_sources:
        kind = entry["kind"]
        via = entry.get("via") or ""
        category = entry.get("paramRowCategory") or ""
        if entry.get("inferred"):
            head = category.split(" - ")[0]
            owners = owning_attach_ids(sp_id, param_name, attach, stems)
            if not owners and head == "Weapon Power":
                owners = innate_owner(sp_id, param_name, attach, ctx["innate"])
            placed = False
            for attach_id in owners:
                slot = slot_of_attach(attach_id, ctx, accessory_attach)
                if slot is None and attach_id in permanent_ids:
                    # DLC Dormant Power: PermanentBuffParam rows share the id
                    # of the weapon effect they grant (8330700, 8450100, ...)
                    slot = "permanent"
                if slot:
                    slots[slot].add(attach_id)
                    placed = True
            if placed:
                continue
            if head == "AoW":
                slots["weaponSkill"].add("")
            elif head in ("Skill", "Ultimate", "Passive", "Magic Cocktail"):
                slots["character"].add("")
            elif head in ("Weapon Power", "Bow", "Arrow", "Serpent Bow", "Flail"):
                slots["weaponInnate"].add("")
            elif head == "Relic":
                slots["relicAffix"].add("")
            elif head in ("Item", "Hub"):
                slots["consumable"].add("")
            elif head in ("Incantation", "Sorcery"):
                slots["spellBuff"].add("")
            elif head == "Talisman":
                slots["accessory"].add("")
            else:
                slots["other"].add("")
                reasons.append(OTHER_CATEGORY_REASONS.get(
                    head, f"Paramdex 行名 [{category}]：没有任何词条池／物品引用它，只能靠行名推断"))
            continue
        if kind in ("relicAffix", "other") and (entry.get("attachEffectId") or kind == "relicAffix"):
            attach_id = str(entry.get("attachEffectId") or entry.get("id") or "")
            slot = slot_of_attach(attach_id, ctx, accessory_attach) if attach_id else None
            if slot is None and attach_id in permanent_ids:
                slot = "permanent"
            if slot:
                slots[slot].add(attach_id)
            else:
                slots["other"].add(attach_id)
                reasons.append(f"AttachEffectParam {attach_id}：不在任何遗物／武器词条池里，"
                               "也不是护符或武器固有效果（未启用或仅供脚本使用的词条行）")
            continue
        if kind == "accessory":
            slots["accessory"].add(str(entry.get("attachEffectId") or ""))
        elif kind == "goods":
            slots["consumable"].add("")
        elif kind == "spell":
            slots["spellBuff"].add("")
        elif kind == "permanent":
            if via.startswith("graceSpEffectId") and sp_id in grace_ids:
                slots["runStack"].add("")
            else:
                slots["permanent"].add("")
        elif kind == "weaponPassive":
            slots["weaponInnate"].add("")
        elif kind == "heroSkill":
            slots["character"].add("")
        else:
            slots["other"].add("")
            reasons.append("只能从另一条没有物品来源的 SpEffect 链式到达（chainFields），无法归到可装备槽位")
    ordered = sorted(slots, key=lambda s: SOURCE_SLOT_ORDER[s])
    # a buff that also has a real slot does not need to show up under "other"
    if len(ordered) > 1 and "other" in ordered:
        ordered.remove("other")
        reasons = []
    return {
        "slots": ordered,
        "primary": ordered[0] if ordered else "other",
        "reason": "；".join(dict.fromkeys(reasons)) or None,
        "attach": {slot: sorted((a for a in ids if a), key=int) for slot, ids in slots.items()},
    }


# --------------------------------------------------------------------------
# main build
# --------------------------------------------------------------------------
def build() -> dict[str, Any]:
    sp_rows = read_param("SpEffectParam")
    sp = index_param(sp_rows)
    accum_ladders, accum_conflicts = accumulator_ladders(sp)

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
        "permanentInfo": read_fmg("item", "PermanentBuffInfo", "zhocn"),
        # v6: relic names, Ash of War names, menu words (weapon types, hero
        # skill / ultimate names) and the id-keyed name fallbacks for Q4
        "antique": read_fmg("item", "AntiqueName", "zhocn"),
        "arts": read_fmg("item", "ArtsName", "zhocn"),
        "menu": read_fmg("menu", "CL_MenuText", "zhocn"),
    }
    en = {
        "attach": read_fmg("item", "AttachEffectName", "engus"),
        "accessory": read_fmg("item", "AccessoryName", "engus"),
        "goods": read_fmg("item", "GoodsName", "engus"),
        "weapon": read_fmg("item", "WeaponName", "engus"),
        "magic": read_fmg("item", "MagicName", "engus"),
        "permanent": read_fmg("item", "PermanentBuffName", "engus"),
        "permanentInfo": read_fmg("item", "PermanentBuffInfo", "engus"),
        "speffect": read_fmg("menu", "SpEffectName", "engus"),
        "antique": read_fmg("item", "AntiqueName", "engus"),
        "arts": read_fmg("item", "ArtsName", "engus"),
        "menu": read_fmg("menu", "CL_MenuText", "engus"),
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
            return pick(("nameZh", "effectNameZh", "artsNameZh")), (pick(("nameEn", "effectNameEn"))
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
            # v6 (re-verify, round 3): a "Stack N" row is layer N of a ladder
            # (7039900..7039909, spCategory 206), not a potency -- 「档位」 is
            # the weapon-affix word and confused the two
            if match.group(0).casefold().startswith("stack"):
                return f"第{match.group(1)}层" if is_zh else f"Stack {match.group(1)}"
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
        if vias and all(HIT_SLOT_VIA_RE.search(via) for via in vias):
            # every route is "applied when the attack connects".  Same three
            # questions as the bullet branch, minus the bullet: the faction
            # bits first, and when both are open, what the payload is.
            #
            # The prefix only records *which* hit slot delivered it, so the
            # verdict can be traced back to a column; the three questions are
            # identical for all of them.  A row reachable through more than one
            # family of hit slot (none in this regulation) is filed under
            # attackHit*.
            prefix = ("attackHit"
                      if any(ATTACK_HIT_VIA_RE.search(via) for via in vias)
                      else "weaponHit")
            self_side = row.get("effectTargetSelfTarget") == "1"
            oppose_side = row.get("effectTargetOpposeTarget") == "1"
            if oppose_side and not self_side:
                return "enemy", prefix + "OpposeOnly"
            if self_side and not oppose_side:
                return "self", prefix + "SelfOnly"
            if not rate_groups - {"status", "flag"}:
                # nothing but ailment buildup -- it is what the weapon puts on
                # the thing it hit (greases, Frozen Armament, Bloodflame Blade,
                # and every weapon's own bleed / poison / frost buildup row)
                return "enemy", prefix + "StatusPayload"
            return "self", prefix + "SelfOnly"
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
    dropped_attack_contexts: list[dict[str, Any]] = []
    display_inputs: dict[int, tuple[list[dict[str, Any]], str | None]] = {}
    # ids the dataset will ship, needed before the loop so the stack-ladder scan
    # can stop at the next *reachable* tier instead of swallowing it
    shipped_ids = {sid for sid in sources if sp.get(sid) is not None and classify(sid)[0]}
    # v6 (re-verify, round 3): accumulator -> behavior bullet -> buff stages
    accum_stages = accumulator_stage_chains(sp, index_param(read_param("BehaviorParam_PC")), bullets, shipped_ids)
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

        # --- ailment buildup that lands on the player ---------------------
        # v5.  A status-group value on a row that sits on the player normally
        # means "your attacks inflict +X buildup".  It means the opposite when
        # the faction filter only allows the row to be applied to *yourself*
        # (effectTargetSelfTarget=1 / effectTargetOpposeTarget=0): then the
        # buildup accumulates on the player.  That is Seppuku's blood loss
        # (1753, +9999), the Frenzied Flame incantations' self madness
        # (1731002/1732002/... , whose 简中 descZh literally reads
        # 「血量、专注值会受到大损伤」) and the "poison builds up while below max
        # HP" relic affixes (6851301/8810301, descZh 「会持续受到损伤」).
        # v4 moved five of them from conditional to passive, so an "ailment
        # buildup" ranking that filters on target=self + activation=passive
        # lists self-harm as if it were a player buff.  The flag is structural
        # (faction bits + payload kind), not an id list.
        #
        # Only the *flat* buildup columns qualify.  The xxxInflictRate
        # multipliers are documented (and used) the other way round -- 「自身造成
        # 的累积倍率」, the rate the bearer inflicts on others -- and the game's
        # own text confirms it: 99620 「艾奥尼亚蝶」 diseaseInflictRate=1.3 carries
        # the label 「强化异常状态腥红腐败」 / "Strengthen Scarlet Rot Effect",
        # while every flat row here carries a *suffering* label instead
        # (「异常状态：中毒」+「会持续受到损伤」).  Mixing the two would flag the
        # butterfly's real rot bonus as self-harm.
        self_inflicted_status = (
            buff_target == "self"
            and any(RATE_FIELD_BY_KEY[key]["group"] == "status"
                    and RATE_FIELD_BY_KEY[key]["valueKind"] == "flat"
                    for key in rates)
            and row.get("effectTargetSelfTarget") == "1"
            and row.get("effectTargetOpposeTarget") == "0")

        sp_category = int(row["spCategory"])
        behaviour, _behaviour_zh = spcategory_behaviour(sp_category)
        # v6 (re-verify): resetOnApply (20) was grouped per *category*, which
        # put 77 unrelated relic / talisman / skill buffs into one de-dup
        # bucket.  It is a same-id rule, like none / stackSelf; the two
        # behaviours that no buff uses today (persistThroughDeath, unknown)
        # are per id as well.  The finer key is stacking.exclusiveKey.
        if behaviour in ("none", "stackSelf", "resetOnApply", "persistThroughDeath", SPCATEGORY_UNKNOWN[0]):
            group = f"sp{sp_category}#{sp_id}"
        else:
            group = f"sp{sp_category}"
        exclusive_key, exclusive_scope = exclusive_category_key(sp_category, int(row["categoryPriority"]))
        accum_tier = accum_ladders.get(sp_id)
        if accum_tier:
            exclusive_key, exclusive_scope = accum_tier["key"], "accumulatorLadder"
        elif exclusive_key is None:
            exclusive_key = f"sp{sp_category}#{sp_id}"

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
        # v6: magicSubCategoryChange1..3 is an OR list -- the rate applies to
        # an attack carrying *any* of them.  A situational subcategory is only
        # a restriction when every listed subcategory is situational: the
        # 『提升战技攻击力』 rows list [112 战技攻击, 111 蓄力战技攻击], so every
        # skill hit (which carries 112) qualifies, yet v4/v5 exported
        # attackContexts=["chargedSkill"] and the page hid them behind the
        # 「蓄力战技」 tick box.  [110, 111] (both situational) still gates.
        situational = [value for value in sub_categories if value in ATTACK_CONTEXT_BY_SUBCATEGORY]
        if situational and len(situational) != len(sub_categories):
            dropped_attack_contexts.append({
                "spEffectId": int(sp_id),
                "subCategories": sub_categories,
                "droppedAttackContexts": sorted({ATTACK_CONTEXT_BY_SUBCATEGORY[v] for v in situational}),
            })
            situational = []
        attack_contexts = sorted(
            {ATTACK_CONTEXT_BY_SUBCATEGORY[value] for value in situational}
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
                # v6 (re-verify): the key a page de-duplicates on -- equal
                # keys exclude each other, different keys multiply
                # (enums.exclusiveScope, stackingRules 2).
                "exclusiveKey": exclusive_key,
                "exclusiveScope": exclusive_scope,
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
        if self_inflicted_status:
            # v5, optional, only ever true.  See notes.target / enums.target
            # and diagnostics.selfInflictedStatus.
            entry["selfInflictedStatus"] = True
        if stack_ladder:
            entry["stackLadder"] = stack_ladder
        if accum_tier:
            # v6 (re-verify): this row is tier N of an accumulator ladder
            # (successive-attack talismans ...); every tier is its own buff.
            entry["accumulatorLadder"] = {
                "key": accum_tier["key"],
                "tier": accum_tier["tier"],
                "tiers": accum_tier["tiers"],
                "tierSpEffectIds": accum_tier["tierSpEffectIds"],
                "accumulatorSpEffectIds": accum_tier["accumulatorSpEffectIds"],
                "thresholds": accum_tier["thresholds"],
            }
        if sp_id in accum_stages:
            # v6 (re-verify, round 3): stage N of an accumulator whose tiers
            # hand their buff over through a behavior bullet (8885220..22);
            # the stages coexist, so the key stays per id.
            entry["accumulatorStages"] = accum_stages[sp_id]
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

    # --- v6: game text keyed by the SpEffect's own id (Q4) -----------------
    # Two of the v5 English-only rows do have game text, just not in
    # SpEffectName: PermanentBuffName 8161600 「提升长矛攻击力」 and
    # AttachEffectName 8390000 「强化投掷壶」 are keyed by the very same id.
    for buff in buffs:
        if buff["nameZh"]:
            continue
        key = str(buff["spEffectId"])
        for fmg_key, origin in (("permanent", "permanentBuffNameById"),
                                ("attach", "attachEffectNameById")):
            text = zh[fmg_key].get(key)
            if text:
                buff["nameZh"] = text
                buff["nameSource"] = origin
                buff["displayNameZh"] = text
                if en[fmg_key].get(key):
                    buff["nameEn"] = en[fmg_key][key]
                    buff["displayNameEn"] = en[fmg_key][key]
                break

    # --- v6: Ash of War names on the script-applied AoW sources -------------
    # "[AoW] Golden Vow - Damage/Defence Buff" had no localized origin, so the
    # display name read 「提升攻击力（战技・×1.115）」 and the user took the
    # 「战技」 token for 『提升战技攻击力』.  The ArtsName FMG names the skill.
    arts_by_en: dict[str, tuple[str, str]] = {}
    for text_id in sorted(en["arts"], key=lambda k: int(k) if k.isdigit() else 0):
        en_text = plain_text(en["arts"].get(text_id))
        zh_text = plain_text(zh["arts"].get(text_id))
        if en_text and zh_text:
            arts_by_en.setdefault(en_text.casefold(), (zh_text, text_id))
    def arts_lookup(stem: str) -> tuple[str, str] | None:
        """ArtsName hit for an Ash-of-War stem, "A/B C" stems included.

        Paramdex writes one row shared by two skills as "Barbaric/Milos Roar";
        each alternative ("Barbaric Roar", "Milos Roar") is looked up on its
        own and the ones the FMG knows are joined with 「／」 (the first one's
        id is kept as artsId).
        """
        hit = arts_by_en.get(stem.casefold())
        if hit or "/" not in stem or " " not in stem:
            return hit
        words = stem.split(" ")
        slashed = [i for i, w in enumerate(words) if "/" in w]
        if len(slashed) != 1:
            return None
        index = slashed[0]
        found: list[tuple[str, str]] = []
        for alt in words[index].split("/"):
            candidate = " ".join(words[:index] + [alt] + words[index + 1:])
            alt_hit = arts_by_en.get(candidate.casefold())
            if alt_hit and alt_hit not in found:
                found.append(alt_hit)
        if not found:
            return None
        return "／".join(h[0] for h in found), found[0][1]

    arts_named_sources = 0
    for buff in buffs:
        for entry in buff["sources"]:
            if not (entry.get("inferred") and entry.get("paramRowCategory", "").startswith("AoW")):
                continue
            stem = (entry.get("nameEn") or "").split(" - ")[0].strip()
            # "Rallying Standard (Buff)" -> "Rallying Standard"
            stem = re.sub(r"\s*\([^)]*\)$", "", stem)
            hit = arts_lookup(stem)
            if hit:
                entry["artsNameZh"] = hit[0]
                entry["artsId"] = int(hit[1])
                arts_named_sources += 1

    # --- v6: suggested Chinese names for rows with no game text at all -----
    suggest_index = build_text_index([
        ("ArtsName", en["arts"], zh["arts"]),
        ("MagicName", en["magic"], zh["magic"]),
        ("GoodsName", en["goods"], zh["goods"]),
        ("WeaponName", en["weapon"], zh["weapon"]),
        ("AccessoryName", en["accessory"], zh["accessory"]),
        ("AttachEffectName", en["attach"], zh["attach"]),
        ("PermanentBuffName", en["permanent"], zh["permanent"]),
    ])
    hero_texts: dict[tuple[str, str], tuple[str, str]] = {}
    for index, hero in enumerate(HERO_ORDER):
        for kind in ("skill", "ultimate", "passive"):
            text_id = str(HERO_TEXT_BASE[kind] + index)
            if plain_text(zh["menu"].get(text_id)):
                hero_texts[(kind, hero)] = (plain_text(zh["menu"][text_id]), f"CL_MenuText#{text_id}")
    word_texts: dict[str, tuple[str, str]] = {}
    for text_id in sorted((k for k in en["menu"] if k.isdigit()), key=int):
        en_text = plain_text(en["menu"].get(text_id))
        zh_text = plain_text(zh["menu"].get(text_id))
        # single capitalised words only (family names such as Helen / Frederick
        # / Sebastian); longer menu strings would match too loosely
        if en_text and zh_text and re.fullmatch(r"[A-Z][a-z]+", en_text):
            word_texts.setdefault(en_text, (zh_text, f"CL_MenuText#{text_id}"))
    type_texts: dict[str, tuple[str, str]] = {}
    for text_id in sorted((k for k in en["menu"] if k.isdigit() and 60000 <= int(k) <= 60200), key=int):
        en_text = plain_text(en["menu"].get(text_id))
        if en_text and plain_text(zh["menu"].get(text_id)):
            type_texts.setdefault(en_text, (plain_text(zh["menu"][text_id]), f"CL_MenuText#{text_id}"))
    suggested_untranslated: list[dict[str, Any]] = []
    for buff in buffs:
        if buff["nameZh"]:
            continue
        name, provenance, residue = suggest_name_zh(
            buff["paramName"], suggest_index, hero_texts,
            {w: t for w, t in word_texts.items() if w in ("Helen", "Frederick", "Sebastian")},
            type_texts)
        if not name:
            continue
        buff["suggestedNameZh"] = name
        buff["suggestedNameZhSource"] = provenance
        buff["suggestedNameZhInferred"] = True
        buff["displayNameZh"] = name
        if residue:
            buff["suggestedNameZhUntranslated"] = residue
            suggested_untranslated.append({"spEffectId": buff["spEffectId"], "suggestedNameZh": name,
                                           "untranslated": residue})

    # --- v6: Chinese rendering of the Paramdex row name (display detail) ------
    # The second-to-last disambiguation level of displayNameZh used to be the
    # raw English row name, so 42 Chinese display names still read
    # 「提升物理攻击力（遗物・×1.1・Switching Weapons Boosts Attack Power）」 after the
    # Q4 pass (which only covered rows with *no* Chinese name at all).  The
    # zh list now gets a Chinese rendering of that row name instead, built
    # only from game text and TAIL_PHRASES_ZH:
    #   stem   the owning AttachEffectParam row's own name (relic / weapon
    #          affixes: 7035902 -> AE 7035900 「切换武器时，能提升物理攻击力」),
    #          else ArtsName ("Barbaric/Milos Roar" -> 「野蛮咆哮」), the hero
    #          skill / ultimate / passive words of CL_MenuText 411010+ /
    #          413010+ / 415010+ ("Tenacity" -> 「不屈」), any item / spell /
    #          affix / SpEffect name, MANUAL_STEMS_ZH, then TAIL_PHRASES_ZH;
    #   tails  TAIL_PHRASES_ZH (Right / Left are dropped when the side token
    #          already says 右手武器 / 左手武器).
    # A rendering that still contains Latin words is not used at all -- the
    # name then falls through to 「#spEffectId」, which is always unique -- and
    # the row is listed in diagnostics.displayNameZhDetailUntranslated.
    stems = attach_stem_index(attach)
    detail_index = build_text_index([
        ("ArtsName", en["arts"], zh["arts"]),
        ("MagicName", en["magic"], zh["magic"]),
        ("GoodsName", en["goods"], zh["goods"]),
        ("WeaponName", en["weapon"], zh["weapon"]),
        ("AccessoryName", en["accessory"], zh["accessory"]),
        ("AttachEffectName", en["attach"], zh["attach"]),
        ("PermanentBuffName", en["permanent"], zh["permanent"]),
        ("SpEffectName", en["speffect"], zh["speffect"]),
    ])
    hero_words: dict[str, tuple[str, str]] = {}
    for kind in ("skill", "ultimate", "passive"):
        for index in range(len(HERO_ORDER)):
            text_id = str(HERO_TEXT_BASE[kind] + index)
            en_text = plain_text(en["menu"].get(text_id))
            zh_text = plain_text(zh["menu"].get(text_id))
            if en_text and zh_text:
                hero_words.setdefault(en_text.casefold(), (zh_text, f"CL_MenuText#{text_id}"))
    detail_untranslated: list[dict[str, Any]] = []
    DETAIL_OWNER_HEADS = ("Relic", "Weapon", "Weapon Power", "Talisman")

    def detail_whole(text: str) -> str | None:
        key = text.strip().casefold()
        if not key:
            return None
        for table in (detail_index, hero_words):
            if key in table:
                return table[key][0]
        arts = arts_lookup(text.strip())
        if arts:
            return arts[0]
        manual = MANUAL_STEMS_ZH.get(text.strip())
        return manual[0] if manual else None

    def detail_piece(text: str) -> str | None:
        """Chinese for one " - " segment of a row name, or None if any Latin is left."""
        text = text.strip()
        if not text:
            return ""
        hit = detail_whole(text)
        if hit:
            return hit
        paren = re.match(r"^(.*?)\s*\(([^()]*)\)$", text)
        if paren and paren.group(1):
            base = detail_piece(paren.group(1))
            inner = detail_whole(paren.group(2)) or detail_piece(f"({paren.group(2)})")
            if base is not None and inner is not None:
                return "・".join(filter(None, (base, inner)))
        if " & " in text:
            parts = [detail_piece(part) for part in text.split(" & ")]
            if all(part for part in parts):
                return "、".join(parts)
        words = text.split(" ")
        for cut in range(len(words) - 1, 0, -1):
            lead = detail_whole(" ".join(words[:cut]))
            if lead:
                rest = detail_piece(" ".join(words[cut:]))
                if rest is not None:
                    return "・".join(filter(None, (lead, rest)))
                break
        out = translate_phrases(text).replace("(", "").replace(")", "").strip("・")
        return None if zh_latin_residue(out) else out

    def zh_row_detail(sp_key: int, param_name: str | None, head: str, localized: str | None,
                      has_side: bool) -> str | None:
        if not param_name:
            return None
        category = row_category(param_name)
        body = clean_param_name(param_name)
        segments = [seg.strip() for seg in body.split(" - ") if seg.strip()]
        if not segments:
            return None
        stem, tails = segments[0], segments[1:]
        if ": " in stem:
            stem, extra = stem.split(": ", 1)
            tails = [extra] + tails
        stem_zh = None
        if category.split(" - ")[0] in DETAIL_OWNER_HEADS:
            for owner in owning_attach_ids(str(sp_key), param_name, attach, stems):
                owner_zh = attach_names(attach[owner])[0] if owner in attach else None
                if owner_zh:
                    stem_zh = owner_zh
                    break
        if stem_zh is None:
            stem_zh = detail_piece(stem)
        pieces: list[str | None] = []
        if stem_zh and not (stem_zh == localized or stem_zh in head
                            or (localized and stem_zh in localized)):
            pieces.append(stem_zh)
        elif stem_zh is None:
            pieces.append(None)
        for tail in tails:
            if has_side:
                tail = re.sub(r"\b(?:Right|Left)(?:-Hand)?\b", "", tail)
                tail = re.sub(r"\(\s*\)", "", re.sub(r"\s+", " ", tail)).strip()
            pieces.append(detail_piece(tail) if tail else "")
        if any(piece is None for piece in pieces):
            detail_untranslated.append({"spEffectId": sp_key, "paramName": param_name})
            return None
        text = "・".join(piece for piece in pieces if piece)
        return text or None

    # --- v6: a weapon's own name is not a buff name -------------------------
    # 1940 "[Bow] Golden Arrows Gain 1.5x TypeB" has no text of its own and
    # took the name of the first of the 13 bows that carry it (「短弓」).  Say
    # what it is instead; nameZh keeps the v5 value.
    weapon_named: list[int] = []
    for buff in buffs:
        if buff["nameSource"] != "itemName":
            continue
        all_src = sources[str(buff["spEffectId"])]
        weapon_ids = [e["id"] for e in all_src if e["kind"] == "weaponPassive" and e.get("id")]
        if len(all_src) != len(weapon_ids) or len(set(weapon_ids)) < 2:
            continue
        subs = buff["scope"].get("subCategories") or []
        subject_zh = "、".join(ATK_SUB_CATEGORY.get(v, (str(v), str(v)))[0] for v in subs)
        subject_en = ", ".join(ATK_SUB_CATEGORY.get(v, (str(v), str(v)))[1] for v in subs)
        buff["displayNameZh"] = (f"{buff['nameZh']}等{len(set(weapon_ids))}把武器的固有效果"
                                 + (f"：{subject_zh}" if subject_zh else ""))
        buff["displayNameEn"] = (f"Innate effect of {buff['nameEn']} and {len(set(weapon_ids)) - 1} other armaments"
                                 + (f": {subject_en}" if subject_en else ""))
        weapon_named.append(buff["spEffectId"])

    missing_zh = [
        f"{buff['spEffectId']} {sp[str(buff['spEffectId'])].get('Name') or ''} "
        f"-> {buff['nameEn']}".strip()
        for buff in buffs if not buff["nameZh"]
    ]

    # --- v6 (re-verify): slots before display names ------------------------
    # The display-name category word used to come from the Paramdex "[...]"
    # prefix only, so the permanent upgrade 8100500 (PermanentBuffParam, not
    # in any affix pool) read 「提升属性攻击力（档位1・武器・×1.05）」 like the
    # in-run weapon affix 8850600 and both needed 「#spEffectId」 to be told
    # apart.  The primary sourceSlot is known from the params alone, so it is
    # computed here once and used by the category level (slot_category_label).
    weapons_by_id = {row["ID"]: row for row in weapons}
    loadout = build_loadout_context(
        attach, attach_table, weapons_by_id, zh["weapon"], zh["menu"], en["menu"],
        zh["antique"], en["antique"], attach_names)
    grace_ids = {row["graceSpEffectId"] for row in permanents if ref(row.get("graceSpEffectId"))}
    permanent_ids = {row["ID"] for row in permanents}
    early_slot: dict[int, str] = {}
    # the potency of the affix a buff belongs to, when its own row name has
    # none: 8810301 / 8810351 are identical rows of AE 8810300 (Potency 1) and
    # 8810350 (Potency 2) and needed #spEffectId to be told apart
    early_owner_potency: dict[int, int] = {}
    # v6 (re-verify, round 3): the one affix a buff belongs to, for the layer /
    # stage rows whose own sources carry no localized name (7039900..09 read
    # 「提升攻击力（档位N）」 with no hint of the relic they come from)
    early_owner_name: dict[int, tuple[str | None, str | None]] = {}
    for buff in buffs:
        placed_early = classify_source_slots(
            str(buff["spEffectId"]), buff["paramName"], sources[str(buff["spEffectId"])], loadout, attach,
            stems, accessory_attach_ids, grace_ids, permanent_ids)
        early_slot[buff["spEffectId"]] = placed_early["primary"]
        owner_potencies = {potency_of(attach[a].get("Name")) for ids in placed_early["attach"].values()
                           for a in ids if a in attach}
        if len(owner_potencies) == 1 and None not in owner_potencies:
            early_owner_potency[buff["spEffectId"]] = owner_potencies.pop()
        owner_ids = sorted({a for ids in placed_early["attach"].values() for a in ids if a in attach}, key=int)
        if len(owner_ids) == 1:
            early_owner_name[buff["spEffectId"]] = attach_names(attach[owner_ids[0]])
    # layer / stage rows always show the owning affix and the layer / stage
    forced_step_origin = {b["spEffectId"] for b in buffs
                          if b.get("accumulatorStages") or STACK_ROW_RE.search(b["paramName"] or "")}

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

    # v6 (re-verify): an accumulator tier reads 「第N层」 (the successive-attack
    # talismans were 「米莉森的义手（护符・×1.04・#312505）」), and a [Weapon]
    # row that only PermanentBuffParam grants reads 「永久强化」 instead of
    # 「武器」 so it cannot be mistaken for the in-run weapon affix.
    def ladder_step_token(buff: dict[str, Any], is_zh: bool, with_stages: bool = True) -> str | None:
        stages = buff.get("accumulatorStages") if with_stages else None
        if stages:
            # v6 (re-verify, round 3): 8885220..22 were 「命中时武器效果1..3」
            return f"第{stages['stage']}阶段" if is_zh else f"Stage {stages['stage']}"
        ladder = buff.get("accumulatorLadder")
        if not ladder:
            return None
        return f"第{ladder['tier']}层" if is_zh else f"Stack {ladder['tier']}"

    def owner_potency_token(buff: dict[str, Any], is_zh: bool) -> str | None:
        potency = early_owner_potency.get(buff["spEffectId"])
        if not potency:
            return None
        return f"档位{potency}" if is_zh else f"Lv{potency}"

    def slot_category_label(buff: dict[str, Any], param_name: str | None, is_zh: bool) -> str | None:
        head = row_category(param_name).split(" - ")[0]
        slot = early_slot.get(buff["spEffectId"])
        if head == "Weapon" and slot == "permanent":
            return "永久强化" if is_zh else "Permanent"
        return row_category_label(param_name, is_zh)

    def disambiguate(field: str, is_zh: bool, zh_detail: bool) -> dict[int, str]:
        """Rendered, unique display names for one list (nothing is written)."""
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
            # (not in the v6-draft shadow run, whose count Q4 quotes)
            forced = sp_key in forced_step_origin and not (is_zh and not zh_detail)
            if forced and (not localized or all(e.get("inferred") for e in src_list)):
                # the row was found through its Paramdex name only, so its
                # "origin" is that English row name again -- use the affix
                owner_names = early_owner_name.get(sp_key)
                owner = (owner_names[0] if is_zh else owner_names[1]) if owner_names else None
                if owner and owner != head and owner not in head:
                    if head in owner:
                        head, localized = owner, None   # 「提升攻击力」 -> the affix that says so
                    else:
                        localized = owner
            if is_zh and zh_detail:
                # never the English row name in a Chinese list (see above)
                raw = zh_row_detail(sp_key, param_name, head, localized,
                                    side_token(buff["scope"], param_name, True) is not None)
                if raw and (raw == head or raw in head or raw == localized):
                    raw = None
                # v6 (re-verify): do not repeat the localized origin inside the
                # detail (「癫火・…・癫火・自身累积」)
                if raw and localized and raw.startswith(localized + "・"):
                    raw = raw[len(localized) + 1:] or None
            heads[sp_key] = head
            used[sp_key] = set()
            levels[sp_key] = [
                localized,
                (ladder_step_token(buff, is_zh, not (is_zh and not zh_detail)) or step_token(param_name, is_zh)
                 or owner_potency_token(buff, is_zh)),
                side_token(buff["scope"], param_name, is_zh),
                slot_category_label(buff, param_name, is_zh),
                rate_token(buff["rates"], is_zh),
                raw,
                f"#{sp_key}",
            ]
            if forced:
                used[sp_key] |= {level for level in (0, 1) if levels[sp_key][level]}

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

        return {buff["spEffectId"]: render(buff["spEffectId"]) for buff in named}

    # Shadow run with the v6-draft rule (English Paramdex row name as the zh
    # detail level): only to measure, in notes.userQuestions.Q4, how many
    # Chinese display names the Chinese detail level cleans up.
    draft_zh = disambiguate("displayNameZh", True, False)
    detail_fixed = [b for b in buffs if zh_latin_residue(draft_zh.get(b["spEffectId"]))]
    for field, is_zh in (("displayNameZh", True), ("displayNameEn", False)):
        rendered = disambiguate(field, is_zh, True)
        named = [b for b in buffs if b["spEffectId"] in rendered]
        for buff in named:
            buff[field] = rendered[buff["spEffectId"]]

        seen_display: dict[str, int] = {}
        for buff in named:
            value = buff[field]
            if value in seen_display:
                raise AssertionError(
                    f"{field} is not unique: {value!r} used by "
                    f"{seen_display[value]} and {buff['spEffectId']}")
            seen_display[value] = buff["spEffectId"]
    display_by_id = {b["spEffectId"]: b["displayNameZh"] for b in buffs}
    # rows the English detail used to separate but the Chinese one cannot:
    # they now end in 「#spEffectId」 instead
    detail_untranslated_needed = [
        {"spEffectId": b["spEffectId"], "paramName": b["paramName"], "displayNameZh": b["displayNameZh"],
         "withEnglishDetail": draft_zh.get(b["spEffectId"])}
        for b in buffs
        if zh_latin_residue(draft_zh.get(b["spEffectId"])) and DISPLAY_ID_TAIL_RE.search(b["displayNameZh"] or "")]
    latin_left = [{"spEffectId": b["spEffectId"], "displayNameZh": b["displayNameZh"],
                   "latin": zh_latin_residue(b["displayNameZh"])}
                  for b in buffs if zh_latin_residue(b["displayNameZh"])]

    # --- v6: loadout slots, weapon / relic affix pools, appliesTo ----------
    # (weapons_by_id / loadout / grace_ids / permanent_ids are built before the
    # display names, which need the primary slot -- see early_slot)
    skills_data = load_json(SKILLS_DATASET_PATH)
    bullet_atk_ids = {row.get("atkId_Bullet") for row in bullets.values() if ref(row.get("atkId_Bullet"))}
    populations = AttackPopulations(atk_pc, index_param(magics), skills_data, bullet_atk_ids)
    melee_check = melee_population_check(atk_pc, weapons_by_id, zh["weapon"])
    skill_wep_types = {int(w["wepType"]) for w in skills_data.get("weapons", [])
                       if "skillVariant" in w}
    wep_type_zh = loadout["wepTypeZh"]

    def wep_type_label(value: int) -> str:
        return wep_type_zh.get(value) or WEP_TYPE_EN.get(value) or f"武器类别 {value}"

    def relic_entry(attach_id: str) -> dict[str, Any]:
        info = loadout["relicAffix"][attach_id]
        row = attach[attach_id]
        effect_id = int(attach_id)
        in_catalog = effect_id in loadout["catalogById"]
        return {
            "attachEffectId": effect_id,
            "catalogEffectId": effect_id if in_catalog else None,
            "catalog": ("affixes" if in_catalog
                        else "extraAffixes" if effect_id in loadout["extraIds"] else None),
            "isDeepRelicAffix": bool(info["deepTables"]) or info["curse"],
            "requiresCurse": info["pairedDeep"] and not info["unpairedDeep"],
            "isCurse": info["curse"],
            "compatibilityId": int(row.get("compatibilityId") or "-1"),
            "inNormalRelicPools": bool(info["normalTables"]),
            "fixedRelicOnly": not info["random"],
            # v6 (re-verify, round 3): AttachEffectParam.exclusivityId as is
            # (-1 = none); same value on two equipped relics = the game's red
            # 「!」 conflict mark, see notes.relicAffix
            "exclusivityId": int(row.get("exclusivityId") or "-1"),
        }

    # stack caps the params cannot state on the SpEffect row itself
    def practical_stack_cap(owner_names: list[str]) -> tuple[int | None, str | None]:
        text = " ".join(owner_names).casefold()
        if "evergaol" in text:
            dist = "、".join(f"{k} 个点位 {v} 个" for k, v in loadout["evergaolSpotsPerPattern"].items())
            span = loadout["evergaolAttachIdRange"] or ["?", "?"]
            return loadout["evergaolMax"], (
                f"实测：LotResultSmallBaseAndSpot 里行名含 Evergaol 的地块，每个 patternId 最多落在 "
                f"{loadout['evergaolMax']} 个不同的 attachId 点位（{loadout['evergaolPatterns']} 个 patternId："
                f"{dist}；attachId 共 {loadout['evergaolAttachIds']} 个、取值 {span[0]}–{span[1]}），"
                f"即一张地图最多 {loadout['evergaolMax']} 座封印监牢；与用户反馈『最多 7 层』一致。"
                f"范围：只覆盖 Paramdex 有行名的这 {loadout['evergaolPatterns']} 个 patternId；"
                f"表里共 {loadout['spotPatterns']} 个 patternId，另 {loadout['unnamedSpotPatterns']} 个"
                f"（{'–'.join(loadout['unnamedSpotPatternRange'] or ['?', '?'])}）的行全部没有行名，"
                f"其中用到上述监牢 attachId 的有 {loadout['unnamedPatternsOnEvergaolAttachIds']} 个，"
                "但它们是否在别的点位放监牢，参数表看不出来，未核")
        if "night invader" in text:
            return 4, ("用户反馈：一局最多打倒 4 名黑夜入侵者（参数表里找不到每局入侵次数上限，"
                       "ChaosMatchingCorrectParam 7780 只给了深夜各深度的入侵者强度，未实测）")
        return None, None

    innate_without_weapon: list[dict[str, Any]] = []
    desc_en_by_id: dict[int, str] = {}
    goods_by_en: dict[str, list[int]] = defaultdict(list)
    for text_id in sorted((k for k in en["goods"] if k.isdigit()), key=int):
        if plain_text(en["goods"].get(text_id)) and plain_text(zh["goods"].get(text_id)):
            goods_by_en[plain_text(en["goods"][text_id])].append(int(text_id))
    slot_counts: dict[str, int] = defaultdict(int)
    applies_counts: dict[str, dict[str, int]] = {cls: defaultdict(int) for cls in OUTPUT_CLASSES}
    affix_to_buffs: dict[str, list[int]] = defaultdict(list)
    relic_to_buffs: dict[str, list[int]] = defaultdict(list)
    stack_inputs: list[dict[str, Any]] = []
    for buff in buffs:
        sp_key = str(buff["spEffectId"])
        row = sp[sp_key]
        placed = classify_source_slots(sp_key, buff["paramName"], sources[sp_key], loadout, attach,
                                       stems, accessory_attach_ids, grace_ids, permanent_ids)
        buff["sourceSlot"] = placed["primary"]
        buff["sourceSlots"] = placed["slots"]
        if placed["primary"] == "other" and placed["reason"]:
            buff["sourceSlotReason"] = placed["reason"]
        slot_counts[placed["primary"]] += 1
        # v6 (verify): the in-game description of a permanent / run-stack buff
        # lives in PermanentBuffInfo keyed by the PermanentBuffParam row, not in
        # SpEffectInfo -- 8970000 『赐福王的余威』 had descZh=null although the
        # game says 『根据新发现的赐福数量，提升攻击力』 (PermanentBuffInfo#8970000).
        if placed["primary"] in ("permanent", "runStack") and not buff.get("descZh"):
            for entry in sources[sp_key]:
                if entry["kind"] == "permanent" and entry.get("id") is not None \
                        and entry["via"] in ("spEffectId", "graceSpEffectId"):
                    info_zh = plain_text(zh["permanentInfo"].get(str(entry["id"])))
                    if info_zh:
                        buff["descZh"] = info_zh
                        buff["descZhSource"] = f"PermanentBuffInfo#{entry['id']}"
                        info_en = plain_text(en["permanentInfo"].get(str(entry["id"])))
                        if info_en:
                            desc_en_by_id[buff["spEffectId"]] = info_en
                        break

        weapon_ids = placed["attach"].get("weaponAffix") or []
        if weapon_ids:
            normal = set().union(*(loadout["weaponAffix"][a]["normal"] for a in weapon_ids))
            deep = set().union(*(loadout["weaponAffix"][a]["deep"] for a in weapon_ids))
            roles = set().union(*(loadout["weaponAffix"][a]["roles"] for a in weapon_ids))
            buff["weaponAffixIds"] = [int(a) for a in weapon_ids]
            buff["weaponAffixRoles"] = sorted(roles)
            buff["weaponAffixDeepOnly"] = not normal
            # v6 (re-verify): the per-weapon deep-only cap counts this flag,
            # not weaponAffixDeepOnly (which is also true on the curses)
            buff["weaponAffixDeepOnlyPositive"] = not normal and "curse" not in roles
            buff["scope"]["rollableWeaponTypes"] = sorted(normal | deep)
            for attach_id in weapon_ids:
                affix_to_buffs[attach_id].append(buff["spEffectId"])
        relic_ids = placed["attach"].get("relicAffix") or []
        if relic_ids:
            buff["relicAffixes"] = [relic_entry(a) for a in relic_ids]
            for attach_id in relic_ids:
                relic_to_buffs[attach_id].append(buff["spEffectId"])
        innate_ids = placed["attach"].get("weaponInnate") or []
        if "weaponInnate" in placed["slots"]:
            # v6 (verify): every weaponInnate buff says which weapons carry it --
            # from the legendary-weapon AE (EquipParamWeapon.attachEffectId) and
            # from the direct EquipParamWeapon sources (residentSpEffectId* /
            # spEffectBehaviorId*), all of them, not only the 40 exported.
            weapon_ids = {int(w) for a in innate_ids for w in loadout["innate"].get(a, [])}
            weapon_ids |= {int(e["id"]) for e in sources[sp_key]
                           if e["kind"] == "weaponPassive" and e.get("id") and not e.get("inferred")}
            innate = {"attachEffectIds": [int(a) for a in innate_ids], "weaponIds": sorted(weapon_ids)}
            if weapon_ids:
                innate["wepTypes"] = sorted({int(weapons_by_id[str(w)]["wepType"]) for w in weapon_ids
                                             if str(w) in weapons_by_id})
            else:
                # script-applied, found only through its Paramdex row name
                innate["inferredFromRowName"] = True
                innate["rowCategory"] = row_category(buff["paramName"]) or None
                innate_without_weapon.append({"spEffectId": buff["spEffectId"], "paramName": buff["paramName"],
                                              "displayNameZh": buff["displayNameZh"]})
            buff["weaponInnate"] = innate
        # v6 (verify): a relic affix that only extends a consumable to allies
        # (7050301 "Items confer effect to all nearby allies (Exalted Flesh)")
        # needs both the relic affix and that consumable.
        paren = re.search(r"\(([^()]*)\)$", buff["paramName"] or "")
        if paren and "relicAffix" in placed["slots"] and paren.group(1) in goods_by_en:
            buff["requiresGoodsIds"] = goods_by_en[paren.group(1)]
            if "consumable" not in buff["sourceSlots"]:
                buff["sourceSlots"] = sorted(buff["sourceSlots"] + ["consumable"], key=lambda s: SOURCE_SLOT_ORDER[s])

        # machine-readable armament-type conditions (Q3)
        on_type = int(row.get("triggerOnWepType") or "0")
        count_type = int(row.get("wepTypeTrigger") or "1")
        count = int(row.get("wepTypeTriggerCount") or "0")
        if on_type:
            buff["scope"]["weaponTypes"] = {"mode": "attackWith", "wepTypes": [on_type],
                                            "namesZh": [wep_type_label(on_type)],
                                            "field": "triggerOnWepType"}
        elif count:
            buff["scope"]["weaponTypes"] = {"mode": "equippedCount", "wepTypes": [count_type],
                                            "namesZh": [wep_type_label(count_type)], "count": count,
                                            "field": "wepTypeTrigger+wepTypeTriggerCount"}
        if row.get("triggerAttachedWeapon") == "1":
            buff["scope"]["attachedWeaponOnly"] = True

        verdicts = evaluate_applies_to(
            row, buff["target"], buff["rates"], populations, wep_type_zh,
            loadout["namedWepTypes"], skill_wep_types)
        buff["appliesTo"] = OrderedDict((cls, v["value"]) for cls, v in verdicts.items())
        detail = OrderedDict()
        for cls, verdict in verdicts.items():
            applies_counts[cls][verdict["value"]] += 1
            if verdict["value"] != "yes":
                detail[cls] = {k: verdict[k] for k in ("reason", "requires", "matchShare") if k in verdict}
        if detail:
            buff["appliesToDetail"] = detail

        # stack input (Q5)
        ladder = buff.get("stackLadder")
        owner_names = [attach.get(str(e.get("attachEffectId") or e.get("id") or ""), {}).get("Name", "")
                       for e in sources[sp_key]] + [buff.get("paramName") or ""]
        if ladder:
            multiplier_key = next(k for k in sorted(buff["rates"])
                                  if RATE_FIELD_BY_KEY[k]["valueKind"] == "multiplier")
            tier_values = [buff["rates"][multiplier_key]] + [
                as_number(sp[str(t)][multiplier_key]) for t in ladder["tierSpEffectIds"]]
            cap, cap_source = practical_stack_cap(owner_names)
            stack = {
                "mode": "ladder",
                "paramMaxStacks": ladder["tiers"],
                "practicalMaxStacks": cap,
                "practicalMaxSource": cap_source,
                "userInput": True,
                "multiplierKey": multiplier_key,
                "tierMultipliers": tier_values,
                "appliesToRateKeys": sorted(buff["rates"]),
                "perStackRatio": round(tier_values[1] / tier_values[0], 4) if len(tier_values) > 1 else None,
            }
            buff["stackInput"] = stack
        elif placed["primary"] == "runStack":
            multiplier_key = next((k for k in sorted(buff["rates"])
                                   if RATE_FIELD_BY_KEY[k]["valueKind"] == "multiplier"), None)
            text_hits = sorted(k for k, v in zh["speffect"].items()
                               if buff["nameZh"] and v.startswith(buff["nameZh"] + "＋"))
            unit = (f"层数按游戏文本计：{buff['descZhSource']}『{buff['descZh']}』"
                    + (f"／『{desc_en_by_id[buff['spEffectId']]}』" if buff["spEffectId"] in desc_en_by_id else "")
                    + ("——即本局新发现的赐福数，不是打倒的首领数" if "赐福" in buff["descZh"] else "")
                    if buff.get("descZhSource") else "层数的计数单位在参数与文本里都找不到")
            stack = {
                "mode": "copies",
                "paramMaxStacks": None,
                "practicalMaxStacks": None,
                "practicalMaxSource": "参数表没有上限：spCategory=10（stackSelf）允许同一效果多份共存；"
                                      f"{unit}，由用户手填；每份按 perStackMultiplier 相乘是按 spCategory 推断，未实测",
                "userInput": True,
                "multiplierKey": multiplier_key,
                "perStackMultiplier": buff["rates"].get(multiplier_key) if multiplier_key else None,
                "appliesToRateKeys": sorted(buff["rates"]),
                "uiLabelMax": len(text_hits) or None,
                "uiLabelTextIds": [int(k) for k in text_hits][:20],
            }
            buff["stackInput"] = stack
            if buff["activation"] == "passive":
                # zero stacks at the start of a run -- never multiply by default
                buff["activation"] = "conditional"
                buff["activationSource"] = "stackInputRequired"
        if buff.get("stackInput"):
            stack_inputs.append({"spEffectId": buff["spEffectId"], "displayNameZh": buff["displayNameZh"],
                                 "sourceSlot": buff["sourceSlot"], **{k: buff["stackInput"][k] for k in (
                                     "mode", "paramMaxStacks", "practicalMaxStacks")}})

    # --- v6 (re-verify, round 3) --------------------------------------------
    by_sp_id = {b["spEffectId"]: b for b in buffs}
    # (a) alternative potencies of one affix: one key per affix
    variant_groups, variant_rejected = affix_variant_scan(buffs, sp, attach)
    for group in variant_groups:
        ids = group["spEffectIds"]
        for index, member in enumerate(ids, 1):
            buff = by_sp_id[member]
            buff["stacking"]["exclusiveKey"] = group["key"]
            buff["stacking"]["exclusiveScope"] = "affixVariant"
            buff["affixVariant"] = {
                "key": group["key"],
                "attachEffectId": group["attachEffectId"],
                "variant": index,
                "variants": len(ids),
                "variantSpEffectIds": ids,
                "dispatcherSpEffectIds": group["dispatcherSpEffectIds"],
                "dispatcherStateInfo": group["dispatcherStateInfo"],
                "differingRateKeys": group["differingRateKeys"],
                "differingChainFields": group["differingChainFields"],
            }
    # (b) accumulator ladders: which tiers are buffs at all (7037607, the
    # relic ladder's tier 4, is sp120 / effectEndurance 0 / no rate)
    for buff in buffs:
        ladder = buff.get("accumulatorLadder")
        if ladder:
            ladder["shippedTierSpEffectIds"] = [t for t in ladder["tierSpEffectIds"] if t in by_sp_id]
    # (c) the Self / Allies rows of one cast (Shared Order 1876 / 1877 ...)
    pair_rows: dict[str, dict[str, dict[str, Any]]] = defaultdict(dict)
    for buff in buffs:
        match = SELF_ALLY_ROW_RE.match((buff["paramName"] or "").strip())
        if match:
            pair_rows[match.group(1)][match.group(2)] = buff
    friendly_hits: dict[str, list[int]] = defaultdict(list)
    for atk_id, atk_row in sorted(atk_pc.items(), key=lambda kv: int(kv[0])):
        if atk_row.get("friendlyTarget") == "1" and atk_row.get("selfTarget") == "0":
            for i in range(5):
                target = ref(atk_row.get(f"spEffectId{i}"))
                if target:
                    friendly_hits[target].append(int(atk_id))
    cycle_carriers: dict[str, list[int]] = defaultdict(list)
    for carrier_id, carrier in sp.items():
        target = ref(carrier.get("cycleOccurrenceSpEffectId"))
        if target:
            cycle_carriers[target].append(int(carrier_id))
    self_ally_pairs: list[dict[str, Any]] = []
    for stem, rows in sorted(pair_rows.items(), key=lambda kv: min(b["spEffectId"] for b in kv[1].values())):
        if set(rows) != {"Self", "Allies"}:
            continue
        own, allies = rows["Self"], rows["Allies"]
        own["selfAllyPair"] = {"role": "self", "counterpartSpEffectId": allies["spEffectId"]}
        allies["selfAllyPair"] = {"role": "ally", "counterpartSpEffectId": own["spEffectId"]}

        def delivery(buff: dict[str, Any]) -> dict[str, Any]:
            key = str(buff["spEffectId"])
            carriers = sorted(cycle_carriers.get(key, []))
            hits = sorted(set(friendly_hits.get(key, []))
                          | {a for c in carriers for a in friendly_hits.get(str(c), [])})
            return {"spEffectId": buff["spEffectId"], "target": buff["target"],
                    "exclusiveKey": buff["stacking"]["exclusiveKey"],
                    "cycleCarrierSpEffectIds": carriers, "friendlyHitAtkIds": hits}
        own_d, ally_d = delivery(own), delivery(allies)
        self_ally_pairs.append({
            "paramStem": clean_param_name(stem),
            "self": own_d,
            "ally": ally_d,
            # the rows a friendly hit (AtkParam_Pc friendlyTarget=1, selfTarget=0,
            # i.e. never the attacker) hands out should be the Allies row
            "deliveryMatchesRowName": bool(ally_d["friendlyHitAtkIds"]) and not own_d["friendlyHitAtkIds"],
        })
    # (d) relic affixes that share an exclusivityId (the in-game 「!」 group)
    exclusivity_members: dict[int, list[int]] = defaultdict(list)
    for attach_id, attach_row in attach.items():
        value = int(attach_row.get("exclusivityId") or "-1")
        if value != -1:
            exclusivity_members[value].append(int(attach_id))
    relic_ids_with_buffs = {e["attachEffectId"] for b in buffs for e in b.get("relicAffixes", [])}
    exclusivity_groups = []
    for value in sorted({e["exclusivityId"] for b in buffs for e in b.get("relicAffixes", [])} - {-1}):
        members = sorted(exclusivity_members[value])
        exclusivity_groups.append({
            "exclusivityId": value,
            "attachEffectIds": members,
            "attachEffectIdsWithBuffs": [a for a in members if a in relic_ids_with_buffs],
            "compatibilityIds": sorted({int(attach[str(a)].get("compatibilityId") or "-1") for a in members}),
            "namesZh": [attach_names(attach[str(a)])[0] for a in members],
        })

    weapon_affix_list = []
    for attach_id in sorted(loadout["weaponAffix"], key=int):
        info = loadout["weaponAffix"][attach_id]
        if attach_id not in affix_to_buffs:
            continue
        row = attach.get(attach_id, {})
        name_zh, name_en = attach_names(row) if row else (None, None)
        weapon_affix_list.append({
            "attachEffectId": int(attach_id),
            "nameZh": name_zh,
            "nameEn": name_en,
            "paramName": row.get("Name") or None,
            "potency": potency_of(row.get("Name")),
            "roles": sorted(info["roles"]),
            "isDebuff": row.get("isDebuff") == "1",
            "compatibilityId": int(row.get("compatibilityId") or "-1"),
            "normalWepTypes": sorted(info["normal"]),
            "deepWepTypes": sorted(info["deep"]),
            "deepOnly": not info["normal"],
            "deepOnlyPositive": not info["normal"] and row.get("isDebuff") != "1",
            "tableIds": sorted(info["tables"]),
            "spEffectIds": sorted(set(affix_to_buffs[attach_id])),
        })
    fixed_relics = []
    for entry in loadout["fixedRelics"]:
        spids = sorted({spid for a in entry["attachEffectIds"] + entry["curseAttachEffectIds"]
                        for spid in relic_to_buffs.get(str(a), [])})
        fixed_relics.append({
            **entry,
            "attachEffectNamesZh": [attach_names(attach[str(a)])[0] if str(a) in attach else None
                                    for a in entry["attachEffectIds"]],
            "spEffectIds": spids,
        })

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
            "usage": "SpEffectParam / AttachEffectParam / AttachEffectTableParam / EquipParamAccessory / EquipParamGoods / EquipParamWeapon / Magic / Bullet / PermanentBuffParam；"
                     "v6 起另读 EquipParamCustomWeapon / ItemTableParam / ItemLotParam_map / ItemLotParam_enemy（局内武器词条池）、"
                     "EquipParamAntique / AntiqueStandParam（遗物池与容器格数）、CharaInitParam（武器格数）、"
                     "ChaosMatchingRankControlParam（深夜诅咒武器概率）、LotResultSmallBaseAndSpot（封印监牢点位）、"
                     "AtkParam_Pc（攻击子类别）、BehaviorParam_PC（近战人口旁证 diagnostics.meleePopulationCheck）",
        },
        {
            "name": "ELDEN RING NIGHTREIGN message FMG",
            "detail": "本地导出的简中(zhocn)与英文(engus)文本 raw/msg/<lang>/<bnd>_dlc01/*.json（基础档与 _dlc01 增量合并）",
            "license": "游戏内资料，仅用于同人工具的数值展示",
            "usage": "AttachEffectName / AccessoryName / GoodsName / WeaponName / MagicName / PermanentBuffName / SpEffectName / SpEffectInfo；"
                     "v6 起另读 AntiqueName（固定词条遗物名）、ArtsName（战技名）、CL_MenuText（武器类别、角色技艺／绝招／能力、复仇者家人名）、"
                     "PermanentBuffInfo（永久强化／局内叠层的 descZh）",
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
        # v6: appended last so the positions of the v5 entries do not move
        {
            "name": "本仓库的其它数据集（v6 起）",
            "detail": "data/nightreign-affixes-v1.03.4.json（词条库，relicAffixes[].catalogEffectId 对齐与 self_check）、"
                      "data/nightreign-relics-v1.03.4.json（extraAffixes：固定词条遗物的特殊词条）、"
                      "data/nightreign-skills-v1.03.5.json（战技／法术的命中段 atkId，attackIndex 与 appliesTo 的人口）",
            "license": "本仓库生成物",
            "usage": "只读；generate_skills.py 须先于本脚本运行",
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
                  "target 在那条轴上表示的是『累积加在谁身上』，本来就该是 enemy。"
                  "**v5 修正（命中槽补全）**：v4 只把 Bullet.spEffectId0..4 与 atkOccurrenceSpEffectId "
                  "当成命中槽，漏了同一机制的另外两条投递路径——EquipParamWeapon.spEffectBehaviorId0..2"
                  "（武器自带的出血／中毒／冻伤／腐败／发狂累积）与 AttachEffectParam.onHitSpEffect"
                  "（『攻击附带异常状态』遗物词条）。结果 43 条与油脂行逐列同构的累积行仍是 self："
                  "106010『Lvl 1-2 Poison +45』（毒匕首）与已判 enemy 的 3176『[Item] Poison Grease (Right) "
                  "- Poison』除阵营位与投递槽外完全相同。v5 已按同一套规则改判这 43 条为 enemy，"
                  "新增 targetSource weaponHitOpposeOnly／weaponHitSelfOnly／weaponHitStatusPayload。"
                  "**做『异常状态累积』榜的页面请重取**：现在武器／词条带来的累积全部在 target=enemy 侧。"
                  "**v5 新增 selfInflictedStatus**：反过来，有 20 条 target=self 的行，其 status 加算点数是"
                  "累在玩家自己身上的自伤（切腹、癫火自伤、『血量没有全满时累积中毒量表』），"
                  "带 `selfInflictedStatus: true`，异常累积榜必须排除，详见 "
                  "diagnostics.selfInflictedStatus。",
        "stackLadder": "`stackLadder`（可缺，只出现在叠层阶梯的第 1 层上）各键的口径："
                       "`tiers`＝**阶梯总层数，含第 1 层**（本条自己）；"
                       "`tierSpEffectIds`＝**第 2 层起、不含第 1 层**的 spEffectId 列表，"
                       "长度恒等于 tiers-1，按层数升序，这些 id 不会作为独立 buff 出现在 buffs[] 里；"
                       "`topRates`＝最后一层（tierSpEffectIds 的最后一个）的数值，键集合与本条 rates 完全相同，"
                       "本条自身的 rates 就是第 1 层数值；"
                       "`saved`＝true 表示该行 saveCategory≠-1，层数会存进存档槽（这也是把它和"
                       "『可分别装备的词条档位』区分开的依据，见 diagnostics.stackLaddersNote）。"
                       "同层互斥：任何时刻只有一层生效，**各层数值绝不能相乘**，"
                       "页面要么显示第 1 层并注明满层值，要么让用户选层数。"
                       "（v6 复核三轮：注意 accumulatorLadder 的同名字段 tierSpEffectIds **含第 1 档**、各档本身就是 buff，"
                       "口径与这里相反，见 notes.accumulatorLadder。）",
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
                   "stance／status 另开一条轴——**status（异常累积）那条轴的过滤口径与伤害轴不同**："
                   "武器／油脂／附加属性带来的累积 target 是 enemy（累积加在被命中者身上，要按 "
                   "sources[].kind 取玩家可获得的来源而不是按 target=self 取），"
                   "而 target=self 且带 `selfInflictedStatus: true` 的是自伤（切腹、癫火自伤），必须排除；"
                   "special／flag／economy 只展示不乘；"
                   "⑥ 用 `stacking.exclusiveKey` 分组去重（同键只留一份，按 `spCategoryBehavior` 选哪份）后跨组相乘"
                   "（v6 起：stacking.group 是只按类别的旧口径，200 系列不看优先度、累积阶梯不合并，留作兼容；"
                   "resetOnApply 的 group 也已改为按 ID，见 stackingRules 第 2 条）；"
                   "⑦ 列表一律显示 `displayNameZh`（已保证唯一）。"
                   "**v6**：第④步里『其余 scope 字段按伤害构成加权』之前，先用 buffs[].appliesTo 判断这条 buff 对所选输出"
                   "（战技／魔法／祷告…）是否生效——no 直接虚化并显示 appliesToDetail.reason，conditional 按 requires 与 "
                   "attackIndex 对所选条目判定；页面分栏改用 sourceSlot（见 notes.appliesTo／notes.sourceSlot）。"
                   "武器词条栏按 slotRules 组装：常规 6 条、深夜 12 条正面词条（另有每把 1 条诅咒，最多 6 条），"
                   "**其中 weaponAffixDeepOnlyPositive=true 的最多 6 条**（slotRules.weaponAffix.maxDeepOnlyAffixes，每把 1 条；"
                   "诅咒也是 weaponAffixDeepOnly=true，但不计入这个上限，见 slotRules.weaponAffix.deepOnlyCapField）；"
                   "叠层类按 stackInput 让用户填层数。"
                   "**v6 复核三轮**：第①步保留 self 与 ally 时，带 `selfAllyPair` 的成对行（同一战技的 Self／Allies 两行）"
                   "算施放者自己只计 role=self 那一行，role=ally 那一行只在队友施放时计入（notes.selfAllyPair）；"
                   "第⑥步的 exclusiveKey 新增取值 \"affix#<attachEffectId>\"（exclusiveScope=affixVariant）：同一词条互为替代的 4 档共用一键、"
                   "只取一档（notes.affixVariant）；relicAffixes[].exclusivityId 相同的不同词条（出击武器附加类 7 条）同时选中时给出提示；"
                   "accumulatorStages 的各阶段各自一键、逐段相乘（notes.accumulatorStages）；"
                   "累积阶梯的 \"sp120\" 同时让不同物品互斥（notes.accumulatorLadder）。",
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
        # v5.  Machine-readable counterparts of two claims that used to live
        # only in prose (and drifted): how many rows carry self-inflicted
        # ailment buildup, and how many stateInfo labels enums.stateInfo ships.
        "buffsWithSelfInflictedStatus": sum(1 for b in buffs if b.get("selfInflictedStatus")),
        "stateInfoLabels": len(STATE_INFO_TYPE),
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
                                        "（阵营过滤位说『只允许打给敌方』），但它们的来源全部是 Paramdex 行名推断"
                                        "或其它无法确认投递路径的通道——四个已知命中槽"
                                        "（Bullet.spEffectId0..4、atkOccurrenceSpEffectId、"
                                        "EquipParamWeapon.spEffectBehaviorId0..2、AttachEffectParam.onHitSpEffect）"
                                        "一个都对不上，因此仍按保守缺省判成 target=\"self\"。"
                                        "**这是缺省而不是已证实的结论**：阵营位本身只说明『这份效果允许打给谁』，"
                                        "不说明『这条 SpEffect 挂在谁身上』。"
                                        "剩下的基本都是 [AoW] 战技行（脚本挂载、参数表无引用），"
                                        "若下一轮能把它们的投递路径还原出来，这批条目多半要改判 enemy。"
                                        "**v5 修正**：v4 这条把『武器行为槽』也写成『无法确认投递路径』，"
                                        "那是错的——EquipParamWeapon.spEffectBehaviorId0..2 与 "
                                        "AttachEffectParam.onHitSpEffect 正是命中槽，v5 已把它们纳入判定，"
                                        "本清单因此由 42 条降到 37 条（1939、105510、8110200-202 已改判 enemy）。",
        "selfInflictedStatus": [
            {
                "spEffectId": buff["spEffectId"],
                "displayNameZh": buff["displayNameZh"],
                "paramName": buff["paramName"],
                "statusRates": {key: value for key, value in buff["rates"].items()
                                if RATE_FIELD_BY_KEY[key]["group"] == "status"},
                "otherRateGroups": [g for g in buff["rateGroups"] if g != "status"],
                "activation": buff["activation"],
                "statusLabelsZh": buff.get("statusLabelsZh"),
                "descZh": buff.get("descZh"),
            }
            for buff in buffs if buff.get("selfInflictedStatus")
        ],
        "selfInflictedStatusNote": "buffs[].selfInflictedStatus=true 表示**这一行 rates 里 group=\"status\" 的"
                                   "加算点数（valueKind=\"flat\" 的 xxxAttackPower）是累在玩家自己身上的**（自伤），"
                                   "不是『让玩家的攻击多附带累积』。"
                                   "判定是结构性的：target=\"self\" ＋ 带 status 组的 flat 数值 ＋ 阵营过滤位 "
                                   "effectTargetSelfTarget=1 且 effectTargetOpposeTarget=0"
                                   "（参数层面只允许施加给自己，异常累积就只能累在自己身上）。"
                                   "**xxxInflictRate 这类 multiplier 刻意不算在内**：它们的含义是"
                                   "『自身造成的累积倍率』，方向相反。游戏文本可以佐证这条分界——"
                                   "99620『艾奥尼亚蝶』diseaseInflictRate=1.3 的状态标签是"
                                   "「强化异常状态腥红腐败」（Strengthen Scarlet Rot Effect），是真实增益；"
                                   "而下面这 20 条 flat 行的标签一律是「异常状态：中毒／出血／发狂」"
                                   "配上「会持续受到损伤」「血量、专注值会受到大损伤」这类**受害**描述。"
                                   "典型例：1753『[AoW] Seppuku - Self Blood Loss』出血 +9999、"
                                   "1732002『[Incantation] Frenzied Burst (Self Madness +20)』、"
                                   "6851301／8810301『血量没有全满时，累积中毒量表』"
                                   "（这三条的简中 descZh 直接写着『会持续受到损伤』『血量、专注值会受到大损伤』）。"
                                   "**做『异常状态累积』榜时必须先排除 selfInflictedStatus=true 的条目**："
                                   "v4 把其中 5 条（1731002／1731003／1731101／1732002／1732003）由 conditional "
                                   "改判成 passive，按『target=self ＋ activation=passive』默认计入的页面"
                                   "会把自伤当成玩家增益列出来。"
                                   "注意这是**按 status 轴**的标记：若某条同时带非 status 的倍率"
                                   "（见 otherRateGroups），那部分仍然是玩家自己的增益，不受此标记影响。",
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
                            "字段口径见 notes.stackLadder（tiers 含第 1 层，tierSpEffectIds 不含）。"
                            "检测是结构性的：ID 连续、后续各层行名为空且自身不是已收录的 buff、"
                            "除倍率外所有列相同、非默认倍率的键集合相同、倍率逐层严格递增、且 saveCategory≠-1。"
                            "**v5 更正排除举例**：最后一条排除的是『可分别装备的词条档位』，"
                            "v4 把它写成『[Relic] Improved Throwing Pot Damage +1/+2』，"
                            "但参数表里根本没有叫 +2 的行——真实结构是 7040300"
                            "『[Relic] Improved Throwing Pot Damage』×1.15、7040301『…… +1』×1.30"
                            "（两条都是有名字、各自独立收录的词条档位），紧跟着的 7040302 才是空行名的 ×1.35。"
                            "7040301 除了 saveCategory=-1 之外满足全部叠层特征，正是靠 saveCategory 这一条"
                            "才没有被误判成『第 1 层 ×1.30、满 2 层 ×1.35』的阶梯；"
                            "反过来真正的阶梯（7069001 等）saveCategory≠-1，层数会存进存档槽。",
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
                             "（四个命中槽：Bullet.spEffectId0..4、atkOccurrenceSpEffectId、"
                             "EquipParamWeapon.spEffectBehaviorId0..2、AttachEffectParam.onHitSpEffect；"
                             "减益、魅惑后的敌人增伤，以及油脂／附加属性武器／武器自带异常属性"
                             "打上去的异常累积）；"
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
    # ======================================================================
    # v6 payload: slot rules, weapon-affix pools, fixed relics, attack index
    # ======================================================================
    buff_by_id = {b["spEffectId"]: b for b in buffs}
    stand_normal = sorted(int(k) for k in loadout["standNormal"])
    stand_deep = sorted(int(k) for k in loadout["standDeep"])
    payload["slotRules"] = OrderedDict([
        ("modes", {
            "normal": {"zh": "常规（一般出击）", "weaponAffixesPerWeapon": loadout["normalPositiveMax"],
                       "relicSlots": stand_normal[-1], "weaponCursesPerWeapon": loadout["normalCurseMax"],
                       "deepOnlyAffixesPerWeapon": 0},
            "deep": {"zh": "深夜（The Deep of Night）", "weaponAffixesPerWeapon": loadout["deepPositiveMax"],
                     "relicSlots": stand_normal[-1] + stand_deep[-1],
                     "weaponCursesPerWeapon": loadout["deepCurseMax"],
                     "deepOnlyAffixesPerWeapon": loadout["deepOnlyPerWeaponMax"]},
            "zh": "页面的『常规／深夜』开关：常规＝每把武器 1 条局内词条、3 个遗物（普通池）；"
                  "深夜＝每把**诅咒武器** 2 条正面词条（另附 1 条负面诅咒）、3 个普通遗物＋3 个深夜遗物。"
                  f"深夜诅咒武器的 2 条正面词条里**最多 {loadout['deepOnlyPerWeaponMax']} 条**可以是深夜专属词条"
                  "（weaponAffixes[].deepOnlyPositive=true／buffs[].weaponAffixDeepOnlyPositive=true，"
                  "如『提升物理攻击力』×1.08、『提升属性攻击力』、『强化魔法、祷告』）："
                  "另一条来自常规池。6 把武器最多 "
                  f"{len(loadout['weaponColumns']) * loadout['deepOnlyPerWeaponMax']} 条深夜专属正面词条，不是 12 条"
                  "（见 slotRules.weaponAffix.deepOnlyPerWeaponMax／maxDeepOnlyAffixes）。"
                  "诅咒的 deepOnly 也是 true（诅咒只出现在深夜），但**不计入**这个上限，另按每把 1 条算。",
        }),
        ("weaponAffix", {
            "maxWeapons": len(loadout["weaponColumns"]),
            "normalPerWeapon": loadout["normalPositiveMax"],
            "deepPerWeapon": loadout["deepPositiveMax"],
            "deepCursePerWeapon": loadout["deepCurseMax"],
            "maxAffixesNormal": len(loadout["weaponColumns"]) * loadout["normalPositiveMax"],
            "maxAffixesDeep": len(loadout["weaponColumns"]) * loadout["deepPositiveMax"],
            "deepOnlyPerWeaponMax": loadout["deepOnlyPerWeaponMax"],
            "maxDeepOnlyAffixes": len(loadout["weaponColumns"]) * loadout["deepOnlyPerWeaponMax"],
            # v6 (re-verify): which flag the two caps above count.  The
            # curses are deepOnly=true as well but have their own 1-per-weapon
            # slot (deepCursePerWeapon).
            "deepOnlyCapField": "weaponAffixDeepOnlyPositive",
            "deepOnlyCapCountsCurses": False,
            "duplicateWithinWeapon": {
                "status": "unknown",
                "likelyKey": "compatibilityId",
                "zh": "同一把深夜诅咒武器的两条正面词条能否是同一条（或同一词条的不同档位）：参数表没有答案。"
                      f"池的结构允许——一般武器的槽6 池（505）包含槽5 池（501）的全部成员，"
                      f"实测 {loadout['deepPositivePairRows']} 行有两个正面槽的武器里 "
                      f"{loadout['deepPositivePairRowsWithSharedAffix']} 行的两个池有共同成员；"
                      "游戏是否像遗物那样按 compatibilityId 去重（遗物同一件上 compatibilityId 相同的词条不会同时出现，"
                      "武器词条的 compatibilityId 也把同一词条的各档归成一组，如强化祷告档位1–3 都是 401020），"
                      "EquipParamCustomWeapon／AttachEffectTableParam 里没有对应字段，未实测。"
                      "页面按用户选择放行；建议在同一把武器选了 compatibilityId 相同的两条时给出提示，而不是直接拒绝。",
            },
            "evidence": {
                "weaponColumns": loadout["weaponColumns"],
                "reachableCustomWeaponRows": loadout["weaponReachableRows"],
                "measuredNormalPositiveMax": loadout["normalPositiveMax"],
                "measuredDeepPositiveMax": loadout["deepPositiveMax"],
                "measuredDeepCurseMax": loadout["deepCurseMax"],
                "isCursedRowsMirrorSlots1to3Into4to6": loadout["cursedRowsMirror"],
                "slotPatternsByRarity": loadout["weaponRarityPatterns"],
                "deepCursedWeaponRates": loadout["chaosCursedRates"],
                "deepOnlyPositiveSlotsPerRow": loadout["deepOnlySlotsPerRow"],
                "deepOnlyAttachEffectIds": len(loadout["deepOnlyAttachIds"]),
                "deepOnlyPositiveAttachEffectIds": len(loadout["deepOnlyPositiveAttachIds"]),
                "deepOnlyCurseAttachEffectIds": len(loadout["deepOnlyCurseAttachIds"]),
                "deepOnlyPositivePotencyByPoolFamily": loadout["deepOnlyPositivePotencyByPoolFamily"],
                "potencyCountsByPoolTier": loadout["potencyCountsByPoolTier"],
                "deepPositivePairRows": loadout["deepPositivePairRows"],
                "deepPositivePairRowsWithSharedAffix": loadout["deepPositivePairRowsWithSharedAffix"],
                "distinctAttachEffectIdsInReachablePools": loadout["distinctAffixIds"],
                "slotLayouts": loadout["slotLayouts"],
                "blessingPools": loadout["blessingTables"],
                "blessingPoolsBySubsetOf81x": loadout["blessingTablesBySubset"],
            },
            "zh": "局内武器最多 6 把（CharaInitParam 的 equip_Wep_Right_1..3／Left_1..3），"
                  "所有已装备武器的词条都生效（词条 SpEffect 的 triggerAttachedWeapon=0，除非 scope.attachedWeaponOnly）。"
                  "EquipParamCustomWeapon 每行 6 个词条槽：attachEffectTableId_1..3 是常规出击时的词条，"
                  "_4..6 是同一把武器在深夜被『诅咒』后的版本。按稀有度实测（evidence.slotPatternsByRarity）："
                  "普通（rarity 0）、优良（1）、稀有（2）／传说（3）常规都是 1 条词条；池按稀有度分档"
                  "（501x00000／501x00100／501x00200），各池的**主档位**依次是档位1／2／3，但不是唯一档位："
                  "优良池另含档位1 成员、稀有池另含档位1 与档位2 成员（evidence.potencyCountsByPoolTier，"
                  "按 501X／505X 各武器组给出每个档位的成员数 [最少, 最多]）。"
                  "深夜版的槽位布局按池族实测（evidence.slotLayouts，池 ID 的百万位，如 501＝501000000 系）有三种："
                  "① 一般武器：槽4 一条负面诅咒（610／620 池）＋槽5 与常规相同的词条池（501／808）＋槽6 深夜池"
                  "（505xxx00y00，比常规池多 17 种深夜专属词条，如『提升物理攻击力』『提升属性攻击力』）；"
                  "② isCursed=1 的『Unique』武器：槽1..3 与 4..6 完全相同＝诅咒（630）＋常规池词条（501／808）＋"
                  "『武器赐福』（810..814 池），推断只在深夜掉落；"
                  "③ 20 行『[Hero] X+2』／『[Unique] X+2』角色武器（101750002–141755002，"
                  "由 ItemLotParam_enemy 13000000 起行名为 [Night Assassin]／[Night Thief]／[Night Hunter]…的掉落表给出）："
                  "槽1 与槽4＝该角色固定的 601000x00 池，[Hero] 槽5＝602000000（17 种深夜专属词条・档位1）＋槽6＝诅咒 620；"
                  "[Unique] 槽2/5＝603000x00（成员是 81x 赐福池的子集，按赐福计，evidence.blessingPoolsBySubsetOf81x）＋槽3/6＝诅咒 630。"
                  "weaponAffixRoles 的 blessing 按池族判（evidence.blessingPools），不按槽号。"
                  "深夜里优良／稀有武器变成诅咒版的概率见 evidence.deepCursedWeaponRates"
                  "（ChaosMatchingRankControlParam：各深度 25%／40%）。"
                  "因此常规每把 1 条（最多 6 条）、深夜诅咒武器每把 2 条正面词条（最多 12 条），"
                  f"**其中深夜专属词条每把最多 {loadout['deepOnlyPerWeaponMax']} 条、6 把最多 "
                  f"{len(loadout['weaponColumns']) * loadout['deepOnlyPerWeaponMax']} 条**"
                  "（evidence.deepOnlyPositiveSlotsPerRow：每行里池中含深夜专属词条的正面槽数的分布，"
                  "深夜专属＝没有任何可掉落行的槽1..3 池含有该词条，与 weaponAffixes[].deepOnly 同一口径）。"
                  "上限只数正面的深夜专属词条（deepOnlyCapField＝weaponAffixDeepOnlyPositive）；诅咒虽然也只出现在深夜"
                  "（deepOnly=true），但占的是每把 1 条的诅咒槽（deepCursePerWeapon），不计入 6 条上限"
                  f"（evidence：深夜专属 id {len(loadout['deepOnlyAttachIds'])} 个＝正面 "
                  f"{len(loadout['deepOnlyPositiveAttachIds'])}＋诅咒 {len(loadout['deepOnlyCurseAttachIds'])}）。"
                  "深夜专属词条的档位：一般诅咒武器的槽6（505 池）与『[Hero] X+2』的槽5（602 池）上只有档位1，"
                  "档位2 只来自赐福池（81x／603），见 evidence.deepOnlyPositivePotencyByPoolFamily。"
                  "同一把武器的两条正面词条能否重复见 duplicateWithinWeapon（未知）。"
                  "每条词条能出现在哪些武器类别上见 weaponAffixes[].normalWepTypes／deepWepTypes 与 buffs[].scope.rollableWeaponTypes。",
        }),
        ("relic", {
            "normal": stand_normal[-1],
            "deepExtra": stand_deep[-1],
            "affixesPerRelic": loadout["relicAffixSlots"],
            "curseAffixesPerDeepRelic": loadout["relicCurseSlots"],
            "evidence": {
                "enabledVessels": loadout["standCount"],
                "vesselNormalSlotCounts": loadout["standNormal"],
                "vesselDeepSlotCounts": loadout["standDeep"],
                "namedRelicRows": loadout["namedRelicRows"],
                "maxAffixSlotsPerRelic": loadout["relicAffixSlots"],
                "maxCurseSlotsPerRelic": loadout["relicCurseSlots"],
            },
            "zh": "每个容器（AntiqueStandParam，启用的全部是 3＋3）有 3 个普通遗物格和 3 个深夜遗物格"
                  "（深夜格只在『深夜』生效，TutorialBody 301950）；每件遗物最多 3 条词条，深夜遗物另有最多 3 条负面词条。"
                  "随机遗物的词条合法性沿用 core.js（普通池 100/110/200/210/300/310，深夜池 2000000/2100000/2200000，"
                  "负面 3000000）；官方固定词条遗物整件选入，见 fixedRelics。",
        }),
        ("accessory", {
            "slots": 2,
            "measured": False,
            "evidence": {
                "source": "用户说明（局内两个护符格）＋游戏文本：CL_MenuText 338380「已增加护符的空格数」表明局内会开护符格。"
                          "参数表没有护符格数字段（CharaInitParam.equip_Accessory01..04 是《艾尔登法环》沿用的 4 列，"
                          "本作只有第 1 列有值）。",
                "accessoryGroupUnique": all(
                    row.get("accessoryGroup") == row["ID"] for row in accessories
                    if zh["accessory"].get(row["ID"])),
            },
            "zh": "局内最多 2 个护符；EquipParamAccessory.accessoryGroup 相同的不能同时装备（本作每个护符的 group 都是自己的 ID，"
                  "即同一护符不能装两个）。",
        }),
        ("consumable", {"slots": None, "zh": "不限数量，按用户勾选；同 stacking.exclusiveKey 的只取一份"}),
        ("spellBuff", {"slots": None, "zh": "不限数量，按用户勾选；同 stacking.exclusiveKey 的只取一份"}),
        ("weaponSkill", {"slots": None, "zh": "随所选武器的战技而定，按用户勾选"}),
        ("weaponInnate", {"slots": None, "zh": "选了对应武器（buffs[].weaponInnate.weaponIds，wepTypes 是这些武器的类别）才有；"
                                            "weaponIds 为空、带 inferredFromRowName=true 的只能靠行名前缀归类"
                                            "（diagnostics.weaponInnateWithoutWeaponIds），页面只能让用户手动勾选"}),
        ("character", {"slots": None, "zh": "随所选角色而定，按用户勾选"}),
        ("permanent", {"slots": None, "zh": "局内获得，按用户勾选"}),
        ("runStack", {"slots": None, "zh": "按 stackInput 让用户填层数"}),
    ])
    payload["weaponAffixes"] = weapon_affix_list
    payload["weaponAffixPools"] = [
        {
            "tableId": int(table),
            "roles": sorted(info["roles"]),
            "modes": sorted(info["modes"]),
            "slotIndexes": sorted(info["slotIndexes"]),
            "potencies": sorted(info["potencies"]),
            "members": info["members"],
            "wepTypes": sorted(info["wepTypes"]),
        }
        for table, info in sorted(loadout["weaponTables"].items(), key=lambda kv: int(kv[0]))
    ]
    payload["fixedRelics"] = fixed_relics
    payload["attackIndex"] = {
        "zh": "appliesTo 的『人口』：每个战技／法术实际命中段的 AtkParam 子类别集合（法术再并上 Magic.subCategory1..2 流派），"
              "以及近战／射击／致命一击的 AtkParam_Pc 行分布。appliesTo=conditional 且 requires.subCategoriesAny 存在时，"
              "页面用所选战技／法术在这里的 subCategorySets 判定：某一段的 subs 与 requires.subCategoriesAny 有交集，"
              "这一段才吃这条 buff（hits 是段数，可按段加权）。",
        "populationCounts": populations.counts(),
        "skills": populations.skill_index,
        "spells": populations.spell_index,
        "melee": [{"subs": sorted(k), "rows": v}
                  for k, v in sorted(populations.rows["melee"].items(), key=lambda kv: (-kv[1], sorted(kv[0])))],
        "ranged": [{"subs": sorted(k), "rows": v}
                   for k, v in sorted(populations.rows["ranged"].items(), key=lambda kv: (-kv[1], sorted(kv[0])))],
        "throw": [{"subs": sorted(k), "rows": v}
                  for k, v in sorted(populations.rows["throw"].items(), key=lambda kv: (-kv[1], sorted(kv[0])))],
    }

    # ---- notes.userQuestions: answers built from the numbers above ----------
    skill_items = populations.items["skill"]
    skills_with_112 = [i for i in skill_items if any(112 in s for s in i["sets"])]
    skills_without_112 = [i["nameZh"] for i in skill_items if i not in skills_with_112]
    skills_with_130 = [i for i in skill_items if any(130 in s for s in i["sets"])]
    spell_items = populations.items["sorcery"] + populations.items["incantation"]
    spells_with_112 = [i for i in spell_items if any(112 in s for s in i["sets"])]
    skill_attack_affixes = [b for b in buffs if b["sourceSlot"] == "weaponAffix"
                            and 112 in b["scope"].get("subCategories", [])]
    skill_attack_all = [b for b in buffs if 112 in b["scope"].get("subCategories", [])
                        and b["target"] in ("self", "ally") and "damage" in b["rateGroups"]]
    sorcery_no = Counter()
    for b in buffs:
        if b["target"] not in ("self", "ally") or not (set(b["rateGroups"]) & DAMAGE_GROUPS):
            continue
        if b["appliesTo"]["sorcery"] == "no":
            first = b["appliesToDetail"]["sorcery"]["reason"].split("；")[0].split("：")[0].split("（")[0]
            if first.startswith("triggerOnWepType"):
                first = "triggerOnWepType（只对用该类武器发动的攻击）"
            elif first.startswith("子类别限定"):
                first = "子类别不匹配"
            sorcery_no[first] += 1
    equipped_count = [b for b in buffs if b["scope"].get("weaponTypes", {}).get("mode") == "equippedCount"]
    attack_with = [b for b in buffs if b["scope"].get("weaponTypes", {}).get("mode") == "attackWith"]
    stack_by_id = {s["spEffectId"]: buff_by_id[s["spEffectId"]] for s in stack_inputs}

    def rate_of(buff: dict[str, Any]) -> str:
        values = sorted({v for k, v in buff["rates"].items()
                         if RATE_FIELD_BY_KEY[k]["valueKind"] == "multiplier" and RATE_FIELD_BY_KEY[k]["countsAsDamage"]})
        return "/".join(f"×{v}" for v in values)

    def ladder_text(buff: dict[str, Any]) -> str:
        stack = buff["stackInput"]
        tiers = stack.get("tierMultipliers") or []
        cap = stack.get("practicalMaxStacks")
        at_cap = f"，{cap} 层 ×{tiers[cap - 1]}" if cap and len(tiers) >= cap else ""
        return (f"{buff['spEffectId']}『{buff['displayNameZh']}』第 1 层 ×{tiers[0]}、每层约 ×{stack['perStackRatio']}"
                f"（第 n 层＝×{stack['perStackRatio']}^n）{at_cap}，参数表共 {stack['paramMaxStacks']} 层（满层 ×{tiers[-1]}）"
                f"；practicalMaxStacks={cap}（{stack['practicalMaxSource'] or '参数表以外无上限依据，由用户填'}）")

    q1 = (
        "**数据是收录了的，是页面口径错了两处，另有一处数据集自身的推导错误（v6 已修）。**"
        f"局内武器词条『提升战技攻击力』＝ AttachEffectParam／SpEffectParam "
        + "、".join(f"{b['spEffectId']}（{rate_of(b)}）" for b in skill_attack_affixes)
        + "，全部五种伤害倍率、magicSubCategoryChange＝[112 战技攻击, 111 蓄力战技攻击]；"
        f"同样带 112 的还有 " + "、".join(f"{b['spEffectId']}『{b['displayNameZh']}』（{b['sourceSlot']}）"
                                        for b in skill_attack_all if b not in skill_attack_affixes) + "。"
        "① 数据集错误：v4 起 scope.attackContexts 把 111（蓄力战技）单独当成情境限制，给这 5 条标了 [\"chargedSkill\"]，"
        "页面据此把它们藏到『蓄力战技』勾选项后面。magicSubCategoryChange1..3 是『命中任一即生效』："
        f"实测 skills 数据集 {len(skill_items)} 个有伤害段的战技里 {len(skills_with_112)} 个的命中段带 112"
        f"（没有的是 {'、'.join(skills_without_112)}——咆哮类的伤害段是咆哮后强化的普通攻击，子类别 106+130）。"
        "v6 规定只有**全部**子类别都是情境类时才输出 attackContexts，这 5 条的 attackContexts 已删除（diagnostics.droppedAttackContexts）。"
        "② 页面错误：v5 把所有进了 AttachEffectTableParam 池的 AttachEffectParam 行都标成 sources[].kind=\"relicAffix\"，"
        "局内武器词条与遗物词条混在一起，页面无法单列『局内武器词条』；v6 新增 buffs[].sourceSlot=\"weaponAffix\"。"
        "③ 页面错误：ranker.js 的 meleeOnly 规则把只标 [130 近战武器攻击] 的条目（『提升近战攻击力』）判为不作用于战技，"
        f"但实测 {len(skills_with_130)}/{len(skill_items)} 个战技的命中段带 130（只有弓系战技没有），"
        "v6 的 appliesTo.skill 已给出 conditional＋requires.subCategoriesAny=[130]。"
        f"**法术不会吃『提升战技攻击力』**：{len(spell_items)} 个有伤害段的法术里带 112 的有 {len(spells_with_112)} 个，"
        "且这些词条 magParamChange＝miracleParamChange＝0，appliesTo.sorcery／incantation＝\"no\"。"
        "页面上法术吃到的『提升攻击力（战技・×1.115）』之类，是战技**发动后给自己的全伤害增益**——"
        "1730『[AoW] Golden Vow』×1.115（战技『黄金树立誓』）、1768『[AoW] Rallying Standard』×1.2（战技『归于麾下』）等，"
        "magParamChange＝miracleParamChange＝1，确实作用于法术；显示名里的『战技』是**来源类别**不是生效范围。"
        "v6 把它们归到 sourceSlot=\"weaponSkill\"，并在 sources[].artsNameZh／displayNameZh 写出战技名"
        + (f"（例：1730 现在显示为『{buff_by_id[1730]['displayNameZh']}』，"
           f"1768 为『{buff_by_id[1768]['displayNameZh']}』）。" if 1730 in buff_by_id and 1768 in buff_by_id else "。")
    )
    q2 = (
        "v6 为每条 buff 预计算 appliesTo（skill／sorcery／incantation／melee／ranged／throw → yes／no／conditional），"
        "no 与 conditional 的理由与机读条件在 appliesToDetail。页面对 value=\"no\" 的条目应虚化并显示 reason。"
        "对魔法判 no 的依据（target∈self/ally 且带伤害倍率的条目，按第一条理由计）："
        + "；".join(f"{k} {v} 条" for k, v in sorcery_no.most_common())
        + "。『提升 X 的攻击力』类（8160000–8162400，遗物词条 7330000 起）magParamChange=1，但 triggerOnWepType=X，"
        "只对用 X 发动的攻击生效，魔法由手杖（wepType 57）、祷告由圣印记（61）施放，因此判 no。"
        "wepParamChange=3（自身）的『强化魔法／祷告』对战技与普攻判 no；stateInfo=367 的『强化致命一击』只对 throw 判 yes。"
        "注意 yes 只表示『这类输出吃得到』，数值还要按 rates 的属性与所选战技／法术的伤害构成加权"
        "（纯物理倍率对纯魔力法术等于 ×1）。"
    )
    q3_rows = "、".join(f"{b['spEffectId']}（{b['scope']['weaponTypes']['namesZh'][0]}，{rate_of(b)}）"
                        for b in equipped_count[:4])
    q3 = (
        f"遗物词条『装备三把以上类别为 X 的武器，能提升攻击力』共 {len(equipped_count)} 条（{q3_rows}…）。"
        "条件字段是 SpEffectParam.wepTypeTrigger＝X（WEP_TYPE）＋wepTypeTriggerCount＝3，stateInfo＝2100（Use Weapon Type Trigger）："
        "判的是**装备中**有没有 3 把该类别武器，与当前出手的武器无关；生效范围 wepParamChange＝0（不限武器）、"
        "magParamChange＝miracleParamChange＝1、没有子类别与 triggerOnWepType 限制。"
        "倍率是 physics／magic／fire／thunder／dark AttackRate（最终伤害倍率，减防后乘）。"
        "**所以带三把短剑、手上用刀：刀的攻击吃得到；放魔法／祷告也吃得到**（appliesTo 六类全 yes，activation＝conditional，"
        "scope.weaponTypes={mode:\"equippedCount\", wepTypes:[X], count:3}）。"
        "注意 wepTypeTrigger 的默认值就是 1（短剑），短剑版的 conditions 里只看得到 wepTypeTriggerCount=3，"
        "v6 用 scope.weaponTypes 把类别写明。"
        f"与之相对，『提升 X 的攻击力』（{len(attack_with)} 条，triggerOnWepType＝X）只作用于**用 X 发动**的攻击："
        "刀、法术都吃不到（scope.weaponTypes.mode=\"attackWith\"）。"
        "『装备』是否把 6 个武器槽都算进去，参数表没有写明，按词条文本『装备三把以上』理解为 6 个武器槽都计入，未实测。"
    )
    fixed_by_id = [b for b in buffs if b.get("nameSource") in ("permanentBuffNameById", "attachEffectNameById")]
    suggested = [b for b in buffs if b.get("suggestedNameZh")]
    suggested_by_cat = Counter(row_category(b["paramName"]) for b in suggested)
    attach_row_hits = sum(1 for b in fixed_by_id + suggested if str(b["spEffectId"]) in attach)
    q4 = (
        f"v5 的 {len(fixed_by_id) + len(suggested)} 条无中文名 buff "
        + ("**没有一条是 AttachEffectParam 行**" if attach_row_hits == 0 else f"有 {attach_row_hits} 条是 AttachEffectParam 行")
        + f"（按 spEffectId 与 AttachEffectParam 逐一比对，命中 {attach_row_hits} 条）："
        "它们都是游戏脚本挂载、只能靠 Paramdex 行名找到的 SpEffect。"
        f"其中 {len(fixed_by_id)} 条在别的 FMG 里有**以同一 ID 为键**的游戏文本，已补进 nameZh："
        + "、".join(f"{b['spEffectId']}『{b['nameZh']}』（{b['nameSource']}）" for b in fixed_by_id)
        + f"。其余 {len(suggested)} 条在任何 FMG 里都没有自己的文本，新增 suggestedNameZh（suggestedNameZhInferred=true，"
        "suggestedNameZhSource 列出用到的游戏文本 ID），由游戏文本拼出：战技名取 ArtsName、法术名 MagicName、道具名 GoodsName、"
        "复仇者家人名与角色技艺／绝招名取 CL_MenuText，英文尾巴按 TAIL_PHRASES_ZH 词表翻译；displayNameZh 改用它。"
        "按类别：" + "、".join(f"[{k}] {v}" for k, v in suggested_by_cat.most_common())
        + f"。suggestedNameZh 仍有英文残留的条数见 diagnostics.suggestedNameZhUntranslated（本版本 {len(suggested_untranslated)} 条）。"
        "**但页面显示的是 displayNameZh，不只是名字本身**：v6 初稿在消歧限定词里还用着英文 Paramdex 行名，"
        f"有 {len(detail_fixed)} 条 displayNameZh 仍带英文（如 7035902『提升物理攻击力（遗物・×1.1・Switching Weapons Boosts Attack Power）』、"
        "1681『…Barbaric/Milos Roar - Right Damage Buff』），其中 "
        f"{sum(1 for b in detail_fixed if set(b['rateGroups']) & COUNTS_AS_DAMAGE_GROUPS)} 条带 countsAsDamage 的伤害倍率、"
        "会出现在通用排名里，另有 "
        f"{sum(1 for b in detail_fixed if not set(b['rateGroups']) & COUNTS_AS_DAMAGE_GROUPS and set(b['rateGroups']) & CONDITIONAL_DAMAGE_GROUPS)}"
        " 条只带特攻／致命一击这类条件伤害倍率。"
        "现在这一级限定词改用行名的中文拼写：词干优先取所属 AttachEffectParam 行自己的名字"
        "（7035902→AE 7035900『切换武器时，能提升物理攻击力』）、ArtsName（含『A/B C』拆开查，"
        "『Barbaric/Milos Roar』→『野蛮咆哮』，sources[].artsNameZh 同步补上）、CL_MenuText 的角色技艺／绝招／能力名"
        "（411010+／413010+／415010+，『Tenacity』→『不屈』）、道具／法术／SpEffect 名，尾巴按 TAIL_PHRASES_ZH；"
        "拼不全的行不用这一级，直接落到『#spEffectId』（diagnostics.displayNameZhDetailUntranslated：原本靠英文行名区分、"
        f"现在只能落到 #spEffectId 的条目，本版本 {len(detail_untranslated_needed)} 条）。"
        f"另外 {len(weapon_named)} 条的 nameZh 是携带它的第一把武器名，displayNameZh 改写为『X等N把武器的固有效果』："
        + "、".join(f"{i}『{buff_by_id[i]['nameZh']}』→『{buff_by_id[i]['displayNameZh']}』（{buff_by_id[i]['paramName']}）"
                   for i in weapon_named) + "。"
        f"**现在 displayNameZh 里除 NPC／HP／FP 外的拉丁字母残留：{len(latin_left)} 条**"
        "（diagnostics.displayNameZhLatinResidue，self_check 断言为空）。"
    )
    sp204_buffs = sorted((b for b in buffs if b["stacking"]["spCategory"] == 204), key=lambda b: b["spEffectId"])
    sp204_priorities = [(b["spEffectId"], b["stacking"]["categoryPriority"]) for b in sp204_buffs]
    sp204_keys = [(b["spEffectId"], b["stacking"]["exclusiveKey"]) for b in sp204_buffs]
    q5_items = [ladder_text(b) for b in stack_by_id.values()
                if b["stackInput"]["mode"] == "ladder" and b["sourceSlot"] == "relicAffix"]
    for b in stack_by_id.values():
        stack = b["stackInput"]
        if stack["mode"] != "copies":
            continue
        label_ids = stack.get("uiLabelTextIds") or []
        q5_items.append(
            f"{b['spEffectId']}『{b['displayNameZh']}』：PermanentBuffParam 8970000（Paramdex 行名前缀 [Boss Raid]）"
            f"的 graceSpEffectId→SpEffect {b['spEffectId']}，每份 ×{stack['perStackMultiplier']}"
            "（物理／魔力／火／雷／圣，含法术），spCategory=10（stackSelf，同一效果可多份共存）。"
            + (f"**层数的计数单位是本局新发现的赐福**（游戏文本 {b['descZhSource']}『{b['descZh']}』"
               + (f"／『{desc_en_by_id[b['spEffectId']]}』" if b["spEffectId"] in desc_en_by_id else "")
               + "；graceSpEffectId 这个列名也指向赐福），不是打倒的首领数——v6 初稿写成『每打倒一个给赐福的首领多一份』是错的"
               if b.get("descZhSource") else "层数的计数单位在参数与文本里都找不到")
            + f"。N 份按 ×{stack['perStackMultiplier']}^N 相乘（按 spCategory 推断，未实测）；"
            "参数表无上限，游戏文本备有『赐福王的余威＋1』到『＋"
            f"{stack.get('uiLabelMax')}』（SpEffectName {label_ids[0] if label_ids else '?'}–"
            f"{label_ids[-1] if label_ids else '?'}），页面让用户手填层数；"
            "v5 把它标成 passive 会被默认乘进排名，v6 改为 conditional／stackInputRequired")
    q5 = ("；".join(q5_items)
          + "。三者都是全伤害倍率，同时作用于战技与法术（appliesTo 全 yes）。"
          "阶梯类同一阶梯的各层互斥（spCategory 204 removePrevious，各层共用一个 categoryPriority），任何时刻只取当前层，"
          "绝不能把各层相乘，数值见 buffs[].stackInput.tierMultipliers。另外两条阶梯 8988200『玛雷家的庇佑』（玛雷家行刑剑）、"
          "8998000『复仇的庇佑』（剑骸大剑）各 100 层，归 sourceSlot=weaponInnate，同样带 stackInput。"
          "**不同阶梯之间不互斥**：这四条同为 spCategory 204，但 categoryPriority 各不相同"
          f"（{'／'.join(f'{b}={p}' for b, p in sp204_priorities)}），"
          "204 的 350 行按优先度分成 12 组、每组是一条连续 ID 的阶梯（diagnostics.exclusiveKeyEvidence.sp204Ladders），"
          "200 系列按『同优先度才顶替』处理（stackingRules 第 1 条），所以 stacking.exclusiveKey 各不相同，"
          "例如封印监牢 7 层与黑夜入侵者 4 层同时生效＝两条 tierMultipliers 相乘。"
          "旧的 stacking.group 只按类别给了同一个 \"sp204\"，按它去重会只剩一条——页面请改用 exclusiveKey。"
          "这是参数层面的推断（优先度结构＋遗物词条可以同时装），未实测。")
    payload["notes"]["userQuestions"] = OrderedDict([
        ("Q1", {"question": "战技排名为什么没有局内武器「提升战技攻击力」？法术为什么会吃到战技攻击力？", "answer": q1}),
        ("Q2", {"question": "法术不可能吃到的加成（各类武器攻击力等）应标不生效。", "answer": q2}),
        ("Q3", {"question": "带三把不相关的短剑、用刀或放法术时，「持有 N 把 X 类武器提升攻击力」能否吃到？",
                "answer": q3}),
        ("Q4", {"question": "仍是英文名的 buff 怎么处理？", "answer": q4}),
        ("Q5", {"question": "封印监牢、黑夜入侵者、赐福王的余威的层数上限与每层倍率？", "answer": q5}),
    ])
    payload["notes"]["sourceSlot"] = (
        "**v6 新增** `sourceSlot`（主槽位）／`sourceSlots`（全部槽位，按 enums.sourceSlot 顺序）：这条 buff 该放进页面的哪一栏。"
        "取值与中文说明见 enums.sourceSlot；除任务清单的九种外新增 weaponSkill（战技发动后的自身增益）与 "
        "weaponInnate（武器固有效果、传说武器的庇佑）。判定用的是**全部**来源（不止导出的 40 条）："
        "AttachEffectParam 行按它真正所在的池判——在 EquipParamAntique 的池里＝relicAffix，"
        "在可掉落的 EquipParamCustomWeapon 行引用的池里＝weaponAffix，被 EquipParamWeapon.attachEffectId 引用＝weaponInnate；"
        "只能靠 Paramdex 行名找到的脚本挂载行，先按『同族 AttachEffectParam』（同 ID 十位／百位、同词干）归，"
        "找不到再按 [...] 前缀归。sourceSlot=\"other\" 的条目一定带 sourceSlotReason。"
        "**sources[].kind 保持 v5 口径不变**（局内武器词条仍是 kind=\"relicAffix\"），页面分栏请改用 sourceSlot。"
    )
    by_id_all = {b["spEffectId"]: b for b in buffs}
    # v6 (re-verify): the rows notes.appliesTo quotes for reading throw=1 as
    # "critical hits only" (the opposite of the Paramdex wording)
    throw_one_damage = sorted(
        b["spEffectId"] for b in buffs
        if b["scope"].get("affectsThrow")
        and any(RATE_FIELD_BY_KEY[k]["countsAsDamage"] and RATE_FIELD_BY_KEY[k]["valueKind"] == "multiplier"
                for k in b["rates"]))
    # the note says every one of them is a critical-hit-only row
    assert throw_one_damage and all(
        by_id_all[i]["stacking"]["stateInfo"] == 367
        or re.search(r"Critical|Throw", by_id_all[i]["paramName"] or "") for i in throw_one_damage), throw_one_damage
    payload["notes"]["appliesTo"] = (
        "**v6 新增** `appliesTo`：{skill, sorcery, incantation, melee, ranged, throw} → \"yes\"／\"no\"／\"conditional\"，"
        "`appliesToDetail`：非 yes 的类别的 {reason, requires?, matchShare?}。判定只看 SpEffectParam 自己的列，按顺序叠加："
        "① target 为 enemy／summon → 全 no；② 只有消耗／射程类字段 → 按字段归属"
        "（战技消耗→skill、魔法消耗→sorcery、祷告消耗→incantation、射程衰减→ranged）；"
        "③ stateInfo=367（强化致命一击）只对 throw；④ 投递方式：武器类（skill／melee／ranged）看 wepParamChange"
        "（0 不限、1／2 限右／左手→conditional、3 自身→no、4 踢击→no）且 throwAttackParamChange=1 的行只作用于致命一击；"
        "sorcery 看 magParamChange、incantation 看 miracleParamChange；"
        "⑤ triggerOnWepType（出手武器类别）、triggerAttachedWeapon（只对带词条的那把武器）、"
        "spAttribute（附加属性负载，只对被附加的武器）、atkAttribute、stateInfo=197（突刺反击）；"
        "⑥ magicSubCategoryChange1..3（命中任一即可）对照 attackIndex 里各类输出的实测子类别："
        "全部命中→yes、全不命中→no、部分→conditional（matchShare＝战技／法术按条目、其余按 AtkParam 行的命中比例，"
        "requires.subCategoriesAny 给出需要的子类别，页面用 attackIndex.skills／spells 对所选条目逐段判定）。"
        "取最严的一关。**requires 的键**：hand（1 右手／2 左手）、attackWeaponTypes（出手武器 wepType）、"
        "attachedWeaponOnly、imbuedWeaponOnly、physicalType、attackContexts、subCategoriesAny。"
        "**推断与未实测**：throw（致命一击）对 throwAttackParamChange=0 的武器增益判 yes 是推断，"
        "**而且与 Paramdex 的字面说明相反**：Paramdex 对 throwAttackParamChange 的说明是"
        "『Set whether or not it is effective against throwing attacks』（与 magParamChange 同一写法），"
        "按字面 0＝不作用于致命一击；magParamChange=0 本数据集确实判 no，throw 却反着读成『1＝只作用于致命一击、0＝通用』。"
        f"依据：带无条件伤害倍率且 throw=1 的 buff 只有 {len(throw_one_damage)} 条"
        f"（{'、'.join(str(i) for i in throw_one_damage)}），全是『强化致命一击』类或专门修正致命一击的行"
        "（stateInfo=367 或行名 Critical／Throw），没有一条是通用增益——若 0 才是『不作用于致命一击』，"
        "所有通用增益都会漏掉致命一击、而只作用于致命一击的行反而写成 1，与这批行的用途对不上；"
        "反证是战技『决心』1691（右手 ×1.6，throw=0）另配 1694（throw=1，×0.75『Throw Damage Adjust』）专门压低致命一击，"
        "说明 throw=0 的增益本来就作用于致命一击、throw=1 的行只作用于致命一击；wepParamChange=3 判『不作用于武器攻击』"
        "的依据是它只出现在『强化魔法／祷告』类（magParamChange 或 miracleParamChange=1）与命中负载上。"
        "appliesTo 与 activation 正交：activation 回答『这份 buff 在不在身上』，appliesTo 回答『在身上时哪类输出吃得到』。"
    )
    payload["notes"]["weaponAffix"] = (
        "**v6 新增**：局内武器词条（sourceSlot=weaponAffix）带 `weaponAffixIds`（AttachEffectParam id）、"
        "`weaponAffixRoles`（affix 普通词条／curse 负面诅咒／blessing 武器赐福／fixed 某类武器固定带的词条）、"
        "`weaponAffixDeepOnly`（只在深夜池出现）与 `scope.rollableWeaponTypes`（能出现在哪些 wepType 上，常规∪深夜）。"
        "按词条（而不是按 SpEffect）列出的**有增伤 buff 的词条清单**在顶层 `weaponAffixes`（normalWepTypes／deepWepTypes 分开给）："
        f"只收能对应到 buffs[] 里某条 buff 的 AttachEffect id（本版本 {len(weapon_affix_list)} 个）；"
        f"可掉落武器的池里一共有 {loadout['distinctAffixIds']} 个带权重的 AttachEffect id"
        "（slotRules.weaponAffix.evidence.distinctAttachEffectIdsInReachablePools，含诅咒、恢复、减伤、攻击时释放X等不改输出的词条），"
        "不在本数据集范围内的请查词条库。"
        "池的概览在 `weaponAffixPools`。武器类别中文名见 enums.wepType（取自 CL_MenuText 60010–60175）。"
        "组装规则见 slotRules.weaponAffix／slotRules.modes；深夜诅咒武器每把最多 "
        f"{loadout['deepOnlyPerWeaponMax']} 条**正面的**深夜专属词条（`weaponAffixDeepOnlyPositive`=true，"
        "slotRules.weaponAffix.deepOnlyPerWeaponMax／deepOnlyCapField）。`weaponAffixDeepOnly` 的口径是『只在深夜池出现』，"
        "诅咒（weaponAffixRoles 含 curse）也只出现在深夜，所以同样为 true——**上限只数 weaponAffixDeepOnlyPositive**，"
        "诅咒另按每把 1 条（slotRules.weaponAffix.deepCursePerWeapon）算，6 条诅咒＋6 条深夜专属正面词条是合法组合。"
        f"evidence：深夜专属 AttachEffect id 共 {len(loadout['deepOnlyAttachIds'])} 个，"
        f"正面 {len(loadout['deepOnlyPositiveAttachIds'])} 个（deepOnlyPositiveAttachEffectIds）、"
        f"诅咒 {len(loadout['deepOnlyCurseAttachIds'])} 个（deepOnlyCurseAttachEffectIds）。"
        "同一把武器的两条正面词条能否相同：见 slotRules.weaponAffix.duplicateWithinWeapon（参数表里查不到，按未知处理）。"
    )
    payload["notes"]["relicAffix"] = (
        "**v6 新增**：遗物词条（sourceSlot=relicAffix）带 `relicAffixes[]`："
        "attachEffectId；catalogEffectId（=attachEffectId，且保证在 data/nightreign-affixes-v1.03.4.json 的 affixes 里，"
        "否则为 null）；catalog（\"affixes\"／\"extraAffixes\"——后者是只出现在固定词条遗物上的特殊词条，"
        "在 data/nightreign-relics-v1.03.4.json 的 extraAffixes 里）；isDeepRelicAffix、requiresCurse、isCurse"
        "（按 EquipParamAntique 的池实测：深夜池、与负面槽配对的深夜池、负面池 3000000）；"
        "compatibilityId（AttachEffectParam 原值，-1 不互斥）；inNormalRelicPools；fixedRelicOnly。"
        "self_check 保证与词条库的 requiresCurse／isCurse／compatibilityId 完全一致。"
        "官方固定词条遗物（名字相同、词条不同的算不同条目）在顶层 `fixedRelics`，页面可整件选入占一个遗物格。"
        "`requiresGoodsIds`（可缺）：这条遗物效果只在使用这些道具时才出现——7050301 是遗物词条 7050100"
        "『道具效用能扩及我方人物』把『勇者肉块』（GoodsName 1210）的效果分给队友的那一行，target=ally，"
        "sourceSlots=[relicAffix, consumable]，要同时选了遗物词条与道具才成立。"
        "**v6 复核三轮**：relicAffixes[] 新增 `exclusivityId`（AttachEffectParam 原值，-1＝无）。"
        "compatibilityId 管『同一件遗物上能否并存』，exclusivityId 管『已装备的几件遗物之间亮不亮红色感叹号』（Smithbox 注释）。"
        "本版本带 buff 的词条里只有 100 一组：『出击时的武器，附加…』7 条（魔力／火／雷／圣／冻伤／中毒／出血），"
        "compatibilityId 同为 200，同一件遗物上只能有一条；分装在两件遗物上会亮感叹号，按参数推断只有一条生效（未实测）。"
        "它们各自的 4 档由词条自己的派发行按出击武器选一档，4 档共用一个 exclusiveKey（\"affix#<attachEffectId>\"，见 notes.affixVariant）；"
        "不同词条之间没有并键，页面同时选中两条同 exclusivityId 的词条时应提示，分组见 diagnostics.relicAffixExclusivityGroups。"
    )
    payload["notes"]["stackInput"] = (
        "**v6 新增** `stackInput`（可缺）：需要用户填层数的叠层增益。"
        "mode=\"ladder\"＝叠层阶梯（与 stackLadder 同一批，第 n 层用 tierMultipliers[n-1]，各层互斥不可相乘）；"
        "mode=\"copies\"＝同一效果可多份共存（spCategory=10），N 层＝perStackMultiplier^N。"
        "paramMaxStacks＝参数表的层数上限（copies 为 null）；practicalMaxStacks＝一局实际能叠到的上限及其来源"
        "（practicalMaxSource 写明是实测还是用户反馈）；uiLabelMax＝游戏文本备好的『＋N』标签数。"
        "层数数的是什么，以游戏文本为准：8970000『赐福王的余威』的 descZh（descZhSource=PermanentBuffInfo#8970000）"
        "是『根据新发现的赐福数量，提升攻击力』——页面的输入框应提示『本局新发现的赐福数』，不是打倒的首领数。"
        "**阶梯之间**：7069001 封印监牢、7069201 黑夜入侵者、8988200 玛雷家的庇佑、8998000 复仇的庇佑同为 spCategory 204，"
        "但各自的 categoryPriority 不同（stacking.exclusiveKey 分别为 "
        + "、".join(f"\"{k}\"" for _b, k in sp204_keys) +
        "），按 200 系列『同优先度才顶替』的规则彼此独立，可以同时填层数、结果相乘；同一阶梯内各层才互斥。"
        "旧 stacking.group 把四条都给成 \"sp204\"，页面若仍按 group 去重，用户同时填监牢与入侵者时只会算其中一条。"
        "这是按参数结构推断（204 的 12 条阶梯各占一个优先度），未实测，页面可在这四条同时启用时给个提示。"
    )
    payload["notes"]["suggestedName"] = (
        "**v6 新增** `suggestedNameZh`（可缺，只在 nameZh 为 null 时出现）＋`suggestedNameZhSource`（用到的游戏文本 ID 列表）"
        "＋`suggestedNameZhInferred`=true：没有任何自身游戏文本的脚本挂载行，用游戏文本拼出的建议显示名；"
        "displayNameZh 已改用它。它**不是**该 SpEffect 自己的文本，nameZh 仍保持 null。"
        "displayNameZh 的消歧限定词（倒数第二级）同样只用中文：行名的中文拼写，拼不全就落到『#spEffectId』"
        "（v6 复核：之前还有两级——累积阶梯的各档写『第N层』，行名没有档位时取所属词条的档位，[Weapon] 行只由永久强化授予时写"
        "『永久强化』；落到 #spEffectId 的条目与原因见 diagnostics.displayNameZhIdFallback／Note），"
        "self_check 保证 displayNameZh 里除 NPC／HP／FP 外没有拉丁字母（diagnostics.displayNameZhLatinResidue）。"
        "`descZhSource`（可缺）：descZh 不是来自 SpEffectInfo 时写明出处，本版本只有 PermanentBuffInfo#<PermanentBuffParam 行>。"
        "（v6 复核三轮：行名是『Stack N』的叠层行写『第N层』而不是『档位N』，并带上所属词条名，"
        "如 7039900『出现异常状态量表时，能缓慢提升攻击力（第1层）』；accumulatorStages 的各阶段写『第N阶段』。）"
    )
    # v6 (re-verify, round 3)
    sp120_items = sorted({b["accumulatorLadder"]["tierSpEffectIds"][0] for b in buffs
                          if b.get("accumulatorLadder") and b["stacking"]["exclusiveKey"] == "sp120"})
    payload["notes"]["accumulatorLadder"] = (
        f"**v6 复核新增** `accumulatorLadder`（可缺，出现在累积阶梯的**每一档**上，本版本 {sum(1 for b in buffs if b.get('accumulatorLadder'))} 条）各键的口径："
        "`key`＝这条阶梯共用的 exclusiveKey（与 stacking.exclusiveKey 相同）；"
        "`tier`＝本条是第几档（从 1 起）；`tiers`＝阶梯总档数，**含第 1 档**；"
        "`tierSpEffectIds`＝**全部各档**的 spEffectId（含第 1 档、含本条自己），按阈值升序，长度恒等于 tiers；"
        "`accumulatorSpEffectIds`＝与各档一一对应的累积器行（带 accumuOverFireId 的那一行）；"
        "`thresholds`＝各档的触发阈值（累积器的 accumuOverVal，单位是累积器自己的计数，连续攻击类随命中累积），升序；"
        "`shippedTierSpEffectIds`（复核三轮新增）＝tierSpEffectIds 里真正作为 buff 出现在 buffs[] 里的那些档。"
        "**与 stackLadder 的同名字段含义相反**：stackLadder.tierSpEffectIds 是『第 2 层起、不含第 1 层』，而且那些 id 不会出现在 buffs[] 里；"
        "accumulatorLadder.tierSpEffectIds 含第 1 档，各档本身就是 buff。例外是没有任何倍率的档不会成为 buff："
        "遗物『连续攻击时，提升攻击力』7037604 的 tiers=4，但第 4 档 7037607 是 spCategory 120、持续 0 秒、没有倍率的行，"
        "不在 buffs[] 里，shippedTierSpEffectIds 只有 7037604–7037606 三档——页面显示层数时请用 shippedTierSpEffectIds，"
        "不要按 tiers 显示『共 4 层』。"
        "两者的区别：stackLadder 是存档叠层（saveCategory≠-1，打倒首领／监牢囚犯等一层层存起来，数据集只收第 1 层，页面让用户填层数）；"
        "accumulatorLadder 是局内累积（命中次数达到阈值依次触发下一档，各档都收录，页面让用户选能维持的档）。"
        "两者都是同一阶梯各档互斥，**各档绝不能相乘**。"
        "**互斥结论（参数推断，未实测）**：连续攻击类的各档落在 spCategory 120（Paramdex：Remove Previous），键都是 \"sp120\"，"
        "所以不止同一件物品的各档互斥，不同物品之间也互斥——"
        + "、".join(f"{SOURCE_SLOTS[by_sp_id[i]['sourceSlot']]['zh']}『{by_sp_id[i]['displayNameZh'].split('（')[0]}』"
                    f"{i}–{by_sp_id[i]['accumulatorLadder']['shippedTierSpEffectIds'][-1]}"
                    for i in sp120_items) +
        " 这几件任取两件同时装备也只有一份生效（新触发的顶替旧的；它们的阈值都是 17／30／45／60，几乎同时触发），"
        "排名只算一份、默认取倍率最高的一档，页面同时选中时应提示。v6 之前的说明曾把『米莉森的义手＋带翼剑徽章』当成相乘的例子，以本条为准。"
    )
    payload["notes"]["accumulatorStages"] = (
        "**v6 复核三轮新增** `accumulatorStages`（可缺，本版本 3 条：武器词条 8885200『维持防御时，强化魔法、祷告与缩短咏唱时间』"
        "的 8885220／8885221／8885222）：累积器依次触发、但每一阶段经『行为→子弹』才把 buff 交给玩家的阶段链。"
        "链路：累积器 8885201–8885203（stateInfo=307，阈值 4000000／9000000／15000000）→ 8885210–8885212（behaviorId "
        "900010020–900010022，BehaviorParam_PC refType=1＝子弹）→ Bullet 98885200–98885202 的 spEffectId0 → 8885220–8885222。"
        "各键：`stage`／`stages`（本条是第几阶段／共几阶段）、`stageSpEffectIds`（各阶段的 buff，按阈值升序，含本条）、"
        "`accumulatorSpEffectIds`、`thresholds`、`behaviorSpEffectIds`、`behaviorParamIds`、`bulletIds`、`durations`（各阶段 buff 的持续秒数）、"
        "`expiryAligned`（阈值差与持续时间差成同一比例时给出：unitsPerSecond＝推出的每秒累积量，commonEndSeconds＝各阶段一起结束的时刻；"
        "不成比例时为 null）、`coexist`=true。"
        "**与 accumulatorLadder 相反，这里的各阶段是同时存在、逐段相乘的**："
        "三条都是 ×1.1（另各带 dexterityCancelSystemOnlyAddDexterity=30 的咏唱加速），spCategory=20 各自一个 ID；"
        "持续时间 28／25.5／22.5 秒，阈值差 5M／6M 与持续时间差 2.5／3 秒同为每秒 2000000，"
        "即三段在开始防御后第 30 秒一起结束——这是『叠上去一起到期』的设计，游戏文本 AttachEffectInfo#8885200 也写『能阶段性提升』。"
        "所以三条保持各自的 exclusiveKey：维持到第 n 阶段时 ×1.1^n（第 3 阶段 ×1.331）。"
        "页面应按阶段勾选：勾第 n 阶段时第 1..n-1 阶段必然也在（依次达到）。累积量随防御时间线性增长是推断，阶段叠乘未实测。"
    )
    payload["notes"]["affixVariant"] = (
        "**v6 复核三轮新增** `affixVariant`（可缺，本版本 28 条）与 exclusiveScope=\"affixVariant\"：同一条词条下互为替代的档位，"
        "共用键 \"affix#<attachEffectId>\"，**同键只取一档，绝不能相乘**。"
        "本版本只有『出击时的武器，附加魔力／火／雷／圣属性攻击力』『…附加异常状态冻伤／中毒／出血』7 条遗物词条，每条 4 档："
        "词条（AttachEffectParam 7120000 等）只有一个被动 7120000『Apply State Info』（stateInfo=2101，全表只有这 7 行），"
        "4 档 7120001–7120004 等没有任何参数列指向，只能由这个派发行按条件选一档；"
        "词条库说明『根据武器类型降低物理攻击力30/40/50/60，并增加魔力属性攻击力33/44/55/66』——按出击武器的类别取一档。"
        "所以同一词条的 4 档不可能同时生效；它们不是可以分装在不同遗物上的独立词条（能装备的只有词条本身，档位由武器决定）；"
        "同一词条装在两件遗物上时，词条库叠加性是『不可叠加』，同键也只算一份。"
        "冻伤／中毒／出血的 4 档逐列相同（×0.85），只差指向的负载行。"
        "各键：`key`；`attachEffectId`；`variant`／`variants`（第几档／共几档，按 spEffectId 升序）；`variantSpEffectIds`；"
        "`dispatcherSpEffectIds`／`dispatcherStateInfo`（词条自己的被动行及其 stateInfo）；`differingRateKeys`（各档数值不同的倍率键，"
        "逐列相同的为空）；`differingChainFields`（各档不同的指向列）。"
        "页面：让用户按出击武器选一档（不知道时显示档位 1–4 的区间），不要把 4 档都乘进去；"
        "fixedRelics[].spEffectIds 仍列出全部 4 档（如『细腻的水滴情景』[7120001,7120002,7120003,7120004]），整件选入时同样按键去重。"
        "识别条件与没合并的近似组见 diagnostics.affixVariantScan(+Note)。"
    )
    payload["notes"]["selfAllyPair"] = (
        "**v6 复核三轮新增** `selfAllyPair`（可缺，本版本 6 条＝3 对）：Paramdex 行名以『- Self』／『- Allies』成对的战技增益，"
        "`role`（self／ally，与 target 一致）＋`counterpartSpEffectId`（另一行）。"
        "**算施放者自己的伤害时，不计入同一战技的 role=ally 那一行**——共享圣律 1876（自身 ×1.1）与 1877（队友 ×1.075）："
        "队友那一行由 AtkParam_Pc 300000820（friendlyTarget=1、selfTarget=0）交给命中的队友，施放者自己不会被命中；"
        "若只按 notes.ranking 第①步同时保留 self 与 ally 再相乘，施放者会被错算成 ×1.1825。"
        "role=ally 的行只在『队友施放、落到自己身上』时计入；两名队友都施放时，自己的 1876 与队友给的 1877 确实能同时存在"
        "（不同 ID、载体类别也不同），所以两行不共用 exclusiveKey。投递证据与哀悼墓碑 1835／1836 行名与投递对调的说明见 "
        "diagnostics.selfAllyPairs(+Note)。"
    )
    payload["enums"]["sourceSlot"] = {k: dict(v) for k, v in SOURCE_SLOTS.items()}
    payload["enums"]["outputClass"] = {k: dict(v) for k, v in OUTPUT_CLASSES.items()}
    payload["enums"]["appliesToValue"] = dict(APPLIES_TO_VALUES)
    payload["enums"]["wepType"] = {
        str(k): {"zh": wep_type_zh.get(k), "en": v, "textId": int(loadout["wepTypeTextId"][k])
                 if k in loadout["wepTypeTextId"] else None}
        for k, v in sorted(WEP_TYPE_EN.items())
    }
    payload["enums"]["weaponAffixRole"] = {
        "affix": "普通词条（常规／深夜的正面词条池）",
        "curse": "负面诅咒（Weapon Curse 1/2/3 池，AttachEffectParam.isDebuff=1），只出现在深夜诅咒武器上",
        "blessing": "武器赐福：按池族判——810000000–814000000 池（isCursed=1 武器的第 3/6 槽，按近战／弓／重型远程／法杖圣印／盾分池）"
                    "与成员是其子集的 603000x00 池（『[Unique] X+2』角色武器的第 2/5 槽），见 slotRules.weaponAffix.evidence.blessingPools",
        "fixed": "单成员池：某类武器固定带的词条（附加异常状态、附加属性等），不是随机抽的",
    }
    payload["enums"]["exclusiveScope"] = dict(EXCLUSIVE_SCOPE_LABELS)
    payload["enums"]["stackInputMode"] = {
        "ladder": "叠层阶梯：每层是一条独立的 SpEffect，同层互斥，取当前层",
        "copies": "同一效果多份共存（spCategory=10 stackSelf），层数＝份数，逐份相乘",
    }
    payload["counts"]["buffsBySourceSlot"] = {k: slot_counts[k] for k in SOURCE_SLOTS if slot_counts.get(k)}
    payload["counts"]["appliesToByOutput"] = {cls: {v: applies_counts[cls].get(v, 0) for v in APPLIES_TO_VALUES}
                                              for cls in OUTPUT_CLASSES}
    payload["counts"]["weaponAffixes"] = len(weapon_affix_list)
    payload["counts"]["weaponAffixPools"] = len(payload["weaponAffixPools"])
    payload["counts"]["fixedRelics"] = len(fixed_relics)
    payload["counts"]["buffsWithStackInput"] = sum(1 for b in buffs if b.get("stackInput"))
    payload["counts"]["buffsWithSuggestedNameZh"] = sum(1 for b in buffs if b.get("suggestedNameZh"))
    payload["counts"]["buffsWithRelicAffixes"] = sum(1 for b in buffs if b.get("relicAffixes"))
    payload["counts"]["buffsWithWeaponAffixIds"] = sum(1 for b in buffs if b.get("weaponAffixIds"))
    payload["counts"]["attackPopulation"] = populations.counts()
    payload["counts"]["buffsWithWeaponInnate"] = sum(1 for b in buffs if b.get("weaponInnate"))
    payload["counts"]["buffsWithRequiresGoodsIds"] = sum(1 for b in buffs if b.get("requiresGoodsIds"))
    payload["counts"]["buffsWithDescZhSource"] = sum(1 for b in buffs if b.get("descZhSource"))
    # v6 (re-verify)
    exclusive_members: dict[str, list[int]] = defaultdict(list)
    for b in buffs:
        exclusive_members[b["stacking"]["exclusiveKey"]].append(b["spEffectId"])
    payload["counts"]["buffsByExclusiveScope"] = {
        k: sum(1 for b in buffs if b["stacking"]["exclusiveScope"] == k)
        for k in EXCLUSIVE_SCOPE_LABELS if any(b["stacking"]["exclusiveScope"] == k for b in buffs)}
    payload["counts"]["exclusiveKeys"] = len(exclusive_members)
    payload["counts"]["exclusiveKeysShared"] = sum(1 for v in exclusive_members.values() if len(v) > 1)
    payload["counts"]["buffsWithAccumulatorLadder"] = sum(1 for b in buffs if b.get("accumulatorLadder"))
    payload["counts"]["buffsWithWeaponAffixDeepOnlyPositive"] = sum(
        1 for b in buffs if b.get("weaponAffixDeepOnlyPositive"))
    # v6 (re-verify, round 3)
    payload["counts"]["buffsWithAffixVariant"] = sum(1 for b in buffs if b.get("affixVariant"))
    payload["counts"]["affixVariantGroups"] = len(variant_groups)
    payload["counts"]["buffsWithAccumulatorStages"] = sum(1 for b in buffs if b.get("accumulatorStages"))
    payload["counts"]["buffsWithSelfAllyPair"] = sum(1 for b in buffs if b.get("selfAllyPair"))
    payload["diagnostics"]["droppedAttackContexts"] = dropped_attack_contexts
    # v6 (re-verify): the measurements behind stackingRules 1-2 / exclusiveKey
    key_evidence = exclusive_key_evidence(sp, attach, load_json(AFFIX_CATALOG_PATH)["affixes"])
    # the numbers quoted in STACKING_RULES_ZH must still hold
    assert key_evidence["spCategory20Rows"] == 1310, key_evidence["spCategory20Rows"]
    assert key_evidence["attachEffectPassivesBySpCategory"].get("20") == 1202, key_evidence
    assert key_evidence["affixCatalogSuperposabilityOfSp20"].get("不可叠加") == 126, key_evidence
    assert key_evidence["affixCatalogSuperposabilityOfSp20"].get("不同级别可叠加") == 7, key_evidence
    per_200 = {e["spCategory"]: e for e in key_evidence["category200sPriorities"]}
    assert (per_200[201]["rows"], per_200[201]["distinctCategoryPriority"]) == (292, 90), per_200[201]
    assert per_200[204]["rows"] == 350 and len(key_evidence["sp204Ladders"]) == 12, per_200[204]
    assert key_evidence["sp204LaddersAreIdBlocks"], key_evidence["sp204Ladders"]
    ladder_prio = {l["firstSpEffectId"]: (l["categoryPriority"], l["rows"]) for l in key_evidence["sp204Ladders"]}
    assert ladder_prio[7069001] == (11, 10) and ladder_prio[7069201] == (13, 10), ladder_prio
    assert ladder_prio[8988200] == (5, 100) and ladder_prio[8998000] == (4, 100), ladder_prio
    payload["diagnostics"]["exclusiveKeyEvidence"] = key_evidence
    payload["diagnostics"]["exclusiveKeyEvidenceNote"] = (
        "v6（复核）stacking.exclusiveKey 的依据，全部由生成器从参数表实测："
        "spCategory20Rows＝SpEffectParam 里 spCategory=20 的行数；attachEffectPassivesBySpCategory＝AttachEffectParam "
        "passiveSpEffectId_1..3 指向的 SpEffect 按 spCategory 计数（遗物词条与护符的被动绝大多数是 20，"
        "若 20 跨 ID 互斥，两条遗物词条就会互相顶掉）；affixCatalogSuperposabilityOfSp20＝被动全是 20 的词条在词条库里的叠加性"
        "（『不可叠加』＝同一词条装两次不叠，『不同级别可叠加』＝＋1 与＋2 这两个不同 ID 能同时生效）；"
        "category200sPriorities＝200 系列每个类别的行数与不同 categoryPriority 数；sp204Ladders＝204 按 categoryPriority 分组，"
        "每组正好是一段连续 ID 的存档阶梯（sp204LaddersAreIdBlocks=true；优先度 3 的一组中间隔了 5 个别类行），"
        "即一条阶梯一个优先度。"
        "self_check 另用已知互斥组（油脂与附魔 162、身体增益 151、同一破露滴两档、同一护符四档、封印监牢十层）做正例，"
        "用 77 条 spCategory=20 里明显应共存的组合（护符＋遗物＋角色被动、两条『装备三把以上X』、＋1／＋2）"
        "与四条 204 阶梯彼此之间做反例。"
    )
    payload["diagnostics"]["accumulatorLadderConflicts"] = accum_conflicts
    # v6 (re-verify, round 3)
    payload["diagnostics"]["affixVariantScan"] = {"groups": variant_groups, "rejected": variant_rejected}
    payload["diagnostics"]["affixVariantScanNote"] = (
        "v6（复核三轮）stacking.exclusiveScope=affixVariant 的识别过程：把只归属一条词条（relicAffixes／weaponAffixIds 恰好一个）"
        "的 buff 按『行名去掉 Potency／Stack／末尾编号后的词干＋倍率键集合』分组，两条以上的组逐条检查——"
        "groups 是全部满足条件、已合并成 \"affix#<attachEffectId>\" 的组（dispatcherSpEffectIds／dispatcherStateInfo 是词条自己的"
        "passiveSpEffectId 及其 stateInfo，differingRateKeys 是各档数值不同的倍率键，differingChainFields 是各档不同的指向列）；"
        "rejected 是没合并的组及原因：" + "；".join(f"{k}＝{v}" for k, v in AFFIX_VARIANT_REJECT_REASONS.items()) + "。"
        "本版本合并的全是『出击时的武器，附加…』7 条词条（派发行 stateInfo=2101，全表只有这 7 行用它）："
        "魔力／火／雷／圣 4 条的 4 档数值是物理 −30／−40／−50／−60、属性 +33／+44／+55／+66"
        "（词条库说明『根据武器类型降低物理攻击力30/40/50/60…』，即按出击武器的类别取一档），"
        "冻伤／中毒／出血 3 条的 4 档逐列相同（×0.85），只差 atkOccurrenceSpEffectId 指向的负载行，负载行本来就共用 applyFirst 类别键。"
        "rejected 里值得一看的：8885220–8885222（columnsDiffer：持续时间不同，是同时存在的三个阶段，见 buffs[].accumulatorStages）；"
        "7500801–7500803（referencedByChain：学者遗物由 analyzeSelfLevel1..3_effectId 分别指向，三档数值都是 ×0.85，"
        "是否能同时存在参数里看不出来，保持各自的键）；7610700–7610702（ownerPassiveIsBuff：词条 6610700 只引用档位1，"
        "7610701／7610702 在参数里没有任何引用，是按行名归到这条词条的）。"
    )
    payload["diagnostics"]["selfAllyPairs"] = self_ally_pairs
    payload["diagnostics"]["selfAllyPairsNote"] = (
        "v6（复核三轮）Paramdex 行名以『- Self』／『- Allies』成对的战技增益（buffs[].selfAllyPair）。"
        "friendlyHitAtkIds＝把这一行（或周期性施加它的载体行 cycleCarrierSpEffectIds）交给命中对象的 AtkParam_Pc"
        "（friendlyTarget=1、selfTarget=0，攻击判定不会命中施放者自己）。"
        "共享圣律 1876（×1.1，自身）／1877（×1.075，队友）：施放者经 1870（sp160）或 1875 周期性拿到 1876；"
        "AtkParam_Pc 300000820『[AoW] Shared Order』只把 1871（sp152）交给队友，1871 再周期性施加 1877——"
        "所以施放者自己的一次施放只拿到 1876，不会同时拿到 1877，算施放者自己的伤害时不能把两行相乘。"
        "两名队友都施放时，一个人可以同时挂着自己的 1876 和队友给的 1877（不同 ID、载体类别也不同），所以两行不共用 exclusiveKey。"
        "deliveryMatchesRowName=false 的是哀悼墓碑 1835／1836：AtkParam_Pc 303401800『[AoW Golden Epitaph] Last Rites』交给队友的是"
        "行名写 Self 的 1835，行名写 Allies 的 1836 没有任何参数投递（由战技动作脚本挂给施放者）。两行数值逐列相同、只差 spCategory"
        "（152／160），target 与 selfAllyPair.role 仍按行名给出，未改，页面计算伤害不受影响，只是与其它 152／160 增益的互斥对象会对调。"
    )
    payload["diagnostics"]["relicAffixExclusivityGroups"] = exclusivity_groups
    payload["diagnostics"]["relicAffixExclusivityGroupsNote"] = (
        "v6（复核三轮）relicAffixes[].exclusivityId≠-1 的词条按该值分组（attachEffectIds 取自整张 AttachEffectParam）。"
        "据 Smithbox 注释（见 macos/DataSources/PROVENANCE.md 第 47 行），exclusivityId 只控制『已装备遗物之间的红色感叹号提示』，"
        "compatibilityId 才决定同一件遗物上能否并存。100＝『出击时的武器，附加…』7 条（compatibilityId 同为 200，"
        "词条库叠加性都是『不可叠加』）：这 7 条同一件遗物上只能有一条；分装在两件遗物上时游戏会亮红色感叹号。"
        "它们都改写同一把出击武器的属性（spAttribute 负载），按参数推断两条同时装备时只有一条生效，但这是 UI 提示的含义推断，未实测，"
        "所以没有并进同一个 exclusiveKey（键仍是每条词条一个 \"affix#<attachEffectId>\"），页面同时选中两条时应给出提示。"
    )
    payload["diagnostics"]["displayNameZhIdFallback"] = [
        {"spEffectId": b["spEffectId"], "displayNameZh": b["displayNameZh"]}
        for b in buffs if DISPLAY_ID_TAIL_RE.search(b["displayNameZh"] or "")]
    payload["diagnostics"]["displayNameZhIdFallbackNote"] = (
        "v6（复核）displayNameZh 仍以『#spEffectId』收尾的条目。消歧顺序是：来源名→档位（行名的 Potency／Tier，"
        "累积阶梯用『第N层』，行名没有档位时取所属词条 AttachEffectParam 的档位）→左右手→类别（[Weapon] 行只由 "
        "PermanentBuffParam 授予时写『永久强化』而不是『武器』）→数值→行名的中文拼写→#spEffectId。"
        "剩下的这些在参数上逐列相同或只差指向／条件列，没有可读的区别："
        "7120401–7120408／7120501–7120508／7120601–7120608（同一遗物词条『出击时的武器，附加异常状态…』下 4 份逐列相同的行，"
        "只差 atkOccurrenceSpEffectId 指向的下一行）、8660203／8660206 与 8660204／8660207（同一效果的右手／左手两份，"
        "后两条逐列相同）、7035402／7035412（两个词条 7035400／7035410 同名，只差 invocationConditionsStateChange1）、"
        "8882514／8882515（只差 wepParamChange 3／0）。"
    )
    payload["diagnostics"]["droppedAttackContextsNote"] = (
        "v6 删除了这些条目 v5 里的 scope.attackContexts：它们的 magicSubCategoryChange 同时列了情境类子类别"
        "（111 蓄力战技）与非情境类子类别（112 战技攻击），而 magicSubCategoryChange1..3 是『命中任一即生效』，"
        "所有战技命中段都带 112，所以 111 不构成限制。v5 按 attackContexts 默认不计入，导致战技排名看不到『提升战技攻击力』。")
    payload["diagnostics"]["suggestedNameZhUntranslated"] = suggested_untranslated
    # v6 (verify): the list the page actually shows is displayNameZh
    payload["diagnostics"]["displayNameZhLatinResidue"] = latin_left
    payload["diagnostics"]["displayNameZhDetailUntranslated"] = detail_untranslated_needed
    payload["diagnostics"]["displayNameZhDetailNote"] = (
        "displayNameZh 的倒数第二级限定词（v5 起是英文 Paramdex 行名）在 v6 改为行名的中文拼写（见 notes.userQuestions.Q4）。"
        "displayNameZhLatinResidue 列出 displayNameZh 里仍有 NPC／HP／FP 以外拉丁字母的条目，self_check 断言为空；"
        "displayNameZhDetailUntranslated 列出原本靠英文行名区分、而行名拼不全中文的条目——它们的显示名改用『#spEffectId』结尾，"
        f"不会出现英文（本版本 {len(detail_untranslated_needed)} 条）。"
        f"行名拼不全中文的条目一共 {len(detail_untranslated)} 条，都不需要这一级：要么名字本来就唯一，"
        "要么与同行名的兄弟行本来就只能靠『#spEffectId』区分（如 7120401–7120404 四行行名完全相同）。"
        f"displayNameZhWeaponNamed：nameZh 取自携带它的第一把武器名的条目（{len(weapon_named)} 条），displayNameZh 已改写成『X等N把武器的固有效果』。")
    payload["diagnostics"]["displayNameZhWeaponNamed"] = weapon_named
    payload["diagnostics"]["weaponInnateWithoutWeaponIds"] = innate_without_weapon
    payload["diagnostics"]["weaponInnateWithoutWeaponIdsNote"] = (
        "sourceSlot 含 weaponInnate、但参数里找不到携带它的武器的条目：它们由游戏脚本挂载，只能靠 Paramdex 行名前缀"
        "（[Flail]／[Arrow]…）归到武器固有效果，weaponInnate.weaponIds 为空并带 inferredFromRowName=true，页面不能按所选武器自动启用，"
        "只能让用户手动勾选。其余 weaponInnate 条目的 weaponIds 来自传说武器的 EquipParamWeapon.attachEffectId"
        "（含 [Weapon Power] 行按同百位 SpEffect＋同名前缀归到庇佑，如 8980002→AE 9021400『夜与火的庇佑』→2140000）"
        "与直接引用它的 EquipParamWeapon.residentSpEffectId*／spEffectBehaviorId*（全部来源，不止导出的 40 条）。")
    payload["diagnostics"]["meleePopulationCheck"] = melee_check
    payload["diagnostics"]["meleePopulationCheckNote"] = (
        "outputClass.melee 的人口是『无名、throwFlag=0、非箭、带 130』的 AtkParam_Pc 行，130 本身就是定义口径。"
        f"它排除的无名、无任何子类别的行共 {melee_check['unnamedNoSubcategoryRows']} 行，其中 "
        f"{melee_check['unnamedNoSubcategoryZeroDamage']} 行没有任何伤害（如 1000460／1000470／1000480／1000591），"
        f"{melee_check['unnamedNoSubcategoryDamaging']} 行有伤害（按行号段分布见 unnamedNoSubcategoryDamagingByIdBlock，"
        f"{melee_check['unnamedNoSubcategoryDamagingByIdBlock'].get('<1000000', 0)} 行在 1000000 以下）；"
        "其中被武器的 BehaviorParam_PC 实际引用的只有 unnamedNoSubcategoryDamagingReferencedByWeapons 这几行。"
        "独立旁证：按全部有名武器的 behaviorVariationId 取 BehaviorParam_PC（refType 0＝攻击）实际引用的 AtkParam_Pc，"
        f"有伤害的无名近战行 {melee_check['weaponBehaviorDamagingRows']} 行里带 130 的 {melee_check['weaponBehaviorRowsWith130']} 行，"
        "不带 130 的按子类别见 weaponBehaviorRowsWithout130BySubCategories——几乎都是骑马攻击 101（本作没有骑乘，推断是沿用行），"
        "所以『提升近战攻击力』对 melee 判 yes 与武器实际用到的攻击行一致。")
    payload["diagnostics"]["artsNamedInferredSources"] = arts_named_sources
    payload["diagnostics"]["attackPopulationMissingAtkIds"] = populations.missing_atk_ids[:60]
    payload["diagnostics"]["relicAffixesOutsideCatalog"] = sorted({
        entry["attachEffectId"] for b in buffs for entry in b.get("relicAffixes", [])
        if entry["catalogEffectId"] is None})
    payload["diagnostics"]["relicAffixesOutsideCatalogNote"] = (
        "这些遗物词条只出现在官方固定词条遗物上（EquipParamAntique 单成员池），"
        "不在词条库 affixes 里，而在 data/nightreign-relics-v1.03.4.json 的 extraAffixes 里；relicAffixes[].catalog=\"extraAffixes\"。")
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
    # v5: all three non-bullet hit slots, not just atkOccurrenceSpEffectId
    attack_hit = re.compile(
        r"(?:atkOccurrenceSpEffectId|spEffectBehaviorId[0-2]|onHitSpEffect)(?:->|$)")
    # enums.stateInfo must be exactly the observed set -- no missing label (a
    # bare number the page cannot render) and no dead label (which is how the
    # "36 项" claim in the v4 write-up drifted away from the shipped 37)
    observed_state_info = {str(b["stacking"]["stateInfo"]) for b in buffs
                           if b["stacking"]["stateInfo"]}
    assert set(payload["enums"]["stateInfo"]) == observed_state_info, (
        "enums.stateInfo must match the observed non-zero values exactly",
        sorted(set(payload["enums"]["stateInfo"]) - observed_state_info),
        sorted(observed_state_info - set(payload["enums"]["stateInfo"])))
    assert payload["counts"]["stateInfoLabels"] == len(payload["enums"]["stateInfo"])
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
            # tier ids are the rungs *above* this one and never ship as buffs
            # of their own (notes.stackLadder states both to the consumer)
            assert ladder["tierSpEffectIds"] == sorted(ladder["tierSpEffectIds"]), sp_id
            assert sp_id not in ladder["tierSpEffectIds"], sp_id
            assert not set(ladder["tierSpEffectIds"]) & set(ids), sp_id
            assert ladder["saved"] is True, sp_id
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
        # v5: the self-harm flag may only sit on a player-side row that really
        # carries ailment buildup, and only when the faction filter says the
        # row can be applied to nobody but the player
        if buff.get("selfInflictedStatus"):
            assert buff["selfInflictedStatus"] is True, sp_id
            assert buff["target"] == "self", sp_id
            assert "status" in buff["rateGroups"], sp_id
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

    assert (payload["counts"]["buffsWithSelfInflictedStatus"]
            == len(payload["diagnostics"]["selfInflictedStatus"])
            == sum(1 for b in buffs if b.get("selfInflictedStatus"))), \
        "selfInflictedStatus count / diagnostics disagree"

    # every buff must keep at least one rate that justified its inclusion
    qualifying = {g["key"] for g in payload["rateFieldGroups"] if g["qualifies"]}
    for buff in buffs:
        assert any(group in qualifying for group in buff["rateGroups"]), buff["spEffectId"]

    self_check_v6(payload)


def self_check_v6(payload: dict[str, Any]) -> None:
    """v6 invariants: slots, relic catalog alignment, appliesTo vs scope, slot rules."""
    buffs = payload["buffs"]
    ids = {b["spEffectId"] for b in buffs}
    enums = payload["enums"]
    catalog = {int(a["effectId"]): a for a in load_json(AFFIX_CATALOG_PATH)["affixes"]}
    extra = {int(a["effectId"]) for a in load_json(RELIC_CATALOG_PATH).get("extraAffixes", [])}
    classes = list(enums["outputClass"])
    assert classes == list(OUTPUT_CLASSES), classes
    weapon_affix_ids = {w["attachEffectId"] for w in payload["weaponAffixes"]}
    field_group = {f["key"]: f["group"] for f in payload["rateFields"]}
    slot_total: dict[str, int] = defaultdict(int)
    for buff in buffs:
        sp_id = buff["spEffectId"]
        scope = buff["scope"]
        # --- slots -----------------------------------------------------------
        assert buff["sourceSlot"] in enums["sourceSlot"], (sp_id, buff["sourceSlot"])
        assert buff["sourceSlots"] and buff["sourceSlots"][0] == buff["sourceSlot"], sp_id
        assert all(s in enums["sourceSlot"] for s in buff["sourceSlots"]), sp_id
        assert buff["sourceSlots"] == sorted(buff["sourceSlots"], key=lambda s: SOURCE_SLOT_ORDER[s]), sp_id
        if buff["sourceSlot"] == "other":
            assert buff.get("sourceSlotReason"), (sp_id, "other without reason")
        else:
            assert "sourceSlotReason" not in buff, sp_id
        slot_total[buff["sourceSlot"]] += 1
        # --- relic affixes: aligned with the affix catalog --------------------
        for entry in buff.get("relicAffixes", []):
            assert "relicAffix" in buff["sourceSlots"], sp_id
            effect_id = entry["attachEffectId"]
            if entry["catalogEffectId"] is not None:
                assert entry["catalogEffectId"] == effect_id and effect_id in catalog, (sp_id, effect_id)
                assert entry["catalog"] == "affixes", (sp_id, effect_id)
                ref_affix = catalog[effect_id]
                assert entry["requiresCurse"] == bool(ref_affix["requiresCurse"]), (sp_id, effect_id, "requiresCurse")
                assert entry["isCurse"] == bool(ref_affix["isCurse"]), (sp_id, effect_id, "isCurse")
                assert entry["compatibilityId"] == int(ref_affix["compatibilityId"]), (sp_id, effect_id, "compat")
            else:
                # not a random-pool affix: must be one of the fixed-relic extras
                assert entry["catalog"] == "extraAffixes" and effect_id in extra, (sp_id, effect_id)
                assert entry["fixedRelicOnly"], (sp_id, effect_id)
        # --- weapon affixes --------------------------------------------------
        if buff.get("weaponAffixIds"):
            assert "weaponAffix" in buff["sourceSlots"], sp_id
            assert set(buff["weaponAffixIds"]) <= weapon_affix_ids, sp_id
            assert scope.get("rollableWeaponTypes"), sp_id
            assert all(str(t) in enums["wepType"] for t in scope["rollableWeaponTypes"]), sp_id
        else:
            assert "rollableWeaponTypes" not in scope and "weaponAffixRoles" not in buff, sp_id
        # --- appliesTo -------------------------------------------------------
        applies = buff["appliesTo"]
        assert list(applies) == classes, sp_id
        detail = buff.get("appliesToDetail", {})
        for cls, value in applies.items():
            assert value in enums["appliesToValue"], (sp_id, cls, value)
            if value == "yes":
                assert cls not in detail, (sp_id, cls)
            else:
                assert detail.get(cls, {}).get("reason"), (sp_id, cls, "no reason")
            if value == "conditional":
                assert detail[cls].get("requires"), (sp_id, cls, "conditional without requires")
        # appliesTo must not contradict scope
        groups = {field_group[k] for k in buff["rates"]} - {"flag"}
        economy_only = groups == {"economy"}
        if buff["target"] in ("enemy", "summon"):
            assert all(v == "no" for v in applies.values()), (sp_id, "enemy/summon row applies")
        elif not economy_only:
            if not scope["affectsSorcery"]:
                assert applies["sorcery"] == "no", (sp_id, "sorcery flag off but applies")
            if not scope["affectsIncantation"]:
                assert applies["incantation"] == "no", (sp_id, "incantation flag off but applies")
            if scope.get("weaponSlot") in (3, 4) or scope["affectsThrow"]:
                for cls in ("skill", "melee", "ranged"):
                    assert applies[cls] == "no", (sp_id, cls, "weaponSlot 3/4 or throw-only but applies")
            if scope.get("weaponSlot") in (1, 2):
                for cls in ("skill", "melee", "ranged"):
                    assert applies[cls] != "yes", (sp_id, cls, "hand-limited but unconditional")
            subs = set(scope.get("subCategories", []))
            if subs and subs <= HERO_ONLY_SUBCATEGORIES:
                assert all(v == "no" for v in applies.values()), (sp_id, "hero-only subcategory applies")
            for cls in ("skill", "sorcery", "incantation", "melee", "ranged"):
                if scope.get("attackContexts"):
                    assert applies[cls] != "yes", (sp_id, cls, "attackContexts but unconditional")
            kind = scope.get("weaponTypes", {})
            if kind.get("mode") == "attackWith":
                if not set(kind["wepTypes"]) & SORCERY_CATALYST_WEP_TYPES:
                    assert applies["sorcery"] == "no", (sp_id, "attackWith non-catalyst applies to sorcery")
                if not set(kind["wepTypes"]) & INCANTATION_CATALYST_WEP_TYPES:
                    assert applies["incantation"] == "no", (sp_id, "attackWith non-catalyst applies to incantation")
        # attackContexts only when every listed subcategory is situational
        contexts = set(scope.get("attackContexts", []))
        subs = scope.get("subCategories", [])
        if contexts and subs:
            situational = [v for v in subs if v in ATTACK_CONTEXT_BY_SUBCATEGORY]
            if situational:
                assert len(situational) == len(subs), (sp_id, "mixed subcategories produced attackContexts")
        # --- stack input -----------------------------------------------------
        stack = buff.get("stackInput")
        if stack:
            assert stack["mode"] in enums["stackInputMode"], sp_id
            assert buff["activation"] == "conditional", (sp_id, "stack input but not conditional")
            if stack["mode"] == "ladder":
                ladder = buff["stackLadder"]
                assert stack["paramMaxStacks"] == ladder["tiers"] == len(stack["tierMultipliers"]), sp_id
                assert all(b > a for a, b in zip(stack["tierMultipliers"], stack["tierMultipliers"][1:])), sp_id
            else:
                assert buff["sourceSlot"] == "runStack" and not buff.get("stackLadder"), sp_id
            if stack["practicalMaxStacks"] is not None:
                assert stack["practicalMaxSource"], sp_id
                if stack["paramMaxStacks"] is not None:
                    assert stack["practicalMaxStacks"] <= stack["paramMaxStacks"], sp_id
        elif buff.get("stackLadder") or buff["sourceSlot"] == "runStack":
            raise AssertionError((sp_id, "ladder / run stack without stackInput"))
        # --- names -----------------------------------------------------------
        if buff.get("suggestedNameZh"):
            assert not buff["nameZh"] and buff["suggestedNameZhInferred"] is True, sp_id
            assert buff["suggestedNameZhSource"], sp_id
            assert buff["displayNameZh"].startswith(buff["suggestedNameZh"].split("（")[0]), sp_id
        # what the page shows must be Chinese (NPC / HP / FP excepted)
        assert not zh_latin_residue(buff["displayNameZh"]), (sp_id, buff["displayNameZh"])
        # --- slot-specific fields (verify round) -------------------------------
        if "relicAffix" in buff["sourceSlots"]:
            assert buff.get("relicAffixes"), (sp_id, "relicAffix slot without relicAffixes")
        if "weaponAffix" in buff["sourceSlots"]:
            assert buff.get("weaponAffixIds"), (sp_id, "weaponAffix slot without weaponAffixIds")
        innate = buff.get("weaponInnate")
        if "weaponInnate" in buff["sourceSlots"]:
            assert innate is not None, (sp_id, "weaponInnate slot without weaponInnate")
            assert bool(innate["weaponIds"]) != bool(innate.get("inferredFromRowName")), (sp_id, innate)
            if innate["weaponIds"]:
                assert innate.get("wepTypes") and all(str(t) in enums["wepType"] for t in innate["wepTypes"]), sp_id
        else:
            assert innate is None, sp_id
        if buff.get("requiresGoodsIds"):
            assert {"relicAffix", "consumable"} <= set(buff["sourceSlots"]), sp_id
        if buff.get("descZhSource"):
            assert buff["sourceSlot"] in ("permanent", "runStack") and buff.get("descZh"), sp_id
            assert buff["descZhSource"].startswith("PermanentBuffInfo#"), sp_id
            if stack and stack["mode"] == "copies":
                assert buff["descZhSource"] in stack["practicalMaxSource"], (sp_id, "stack unit not from game text")
    assert payload["counts"]["buffsBySourceSlot"] == {k: v for k, v in
                                                     sorted(slot_total.items(), key=lambda kv: SOURCE_SLOT_ORDER[kv[0]])}
    for cls in classes:
        assert sum(payload["counts"]["appliesToByOutput"][cls].values()) == len(buffs), cls
    # --- weapon affix list / fixed relics -------------------------------------
    for affix in payload["weaponAffixes"]:
        assert set(affix["spEffectIds"]) <= ids, affix["attachEffectId"]
        assert set(affix["normalWepTypes"]) <= set(affix["deepWepTypes"]), affix["attachEffectId"]
        assert affix["deepOnly"] == (not affix["normalWepTypes"]), affix["attachEffectId"]
        assert set(affix["roles"]) <= set(enums["weaponAffixRole"]), affix["attachEffectId"]
    for relic in payload["fixedRelics"]:
        assert relic["relicIds"] and relic["attachEffectIds"], relic
        for effect_id in relic["attachEffectIds"] + relic["curseAttachEffectIds"]:
            assert effect_id in catalog or effect_id in extra, (relic["relicIds"], effect_id)
        assert set(relic["spEffectIds"]) <= ids, relic["relicIds"]
    # --- slot rules: every number must equal its measured evidence ----------------
    rules = payload["slotRules"]
    weapon = rules["weaponAffix"]
    ev = weapon["evidence"]
    assert weapon["maxWeapons"] == len(ev["weaponColumns"]) == 6, weapon["maxWeapons"]
    assert weapon["normalPerWeapon"] == ev["measuredNormalPositiveMax"], weapon
    assert weapon["deepPerWeapon"] == ev["measuredDeepPositiveMax"], weapon
    assert weapon["deepCursePerWeapon"] == ev["measuredDeepCurseMax"], weapon
    assert weapon["maxAffixesNormal"] == weapon["maxWeapons"] * weapon["normalPerWeapon"]
    assert weapon["maxAffixesDeep"] == weapon["maxWeapons"] * weapon["deepPerWeapon"]
    assert ev["isCursedRowsMirrorSlots1to3Into4to6"] is True
    relic = rules["relic"]
    assert [int(k) for k in relic["evidence"]["vesselNormalSlotCounts"]] == [relic["normal"]], relic
    assert [int(k) for k in relic["evidence"]["vesselDeepSlotCounts"]] == [relic["deepExtra"]], relic
    assert relic["affixesPerRelic"] == relic["evidence"]["maxAffixSlotsPerRelic"], relic
    assert rules["modes"]["normal"]["weaponAffixesPerWeapon"] == weapon["normalPerWeapon"]
    assert rules["modes"]["deep"]["weaponAffixesPerWeapon"] == weapon["deepPerWeapon"]
    assert rules["modes"]["deep"]["relicSlots"] == relic["normal"] + relic["deepExtra"]
    assert rules["accessory"]["measured"] is False and rules["accessory"]["evidence"]["source"]
    # deep-only affixes: at most deepOnlyPerWeaponMax per weapon (measured per row)
    per_row = {int(k): v for k, v in ev["deepOnlyPositiveSlotsPerRow"].items()}
    assert sum(per_row.values()) == ev["reachableCustomWeaponRows"], per_row
    assert weapon["deepOnlyPerWeaponMax"] == max(per_row) == 1, per_row
    assert weapon["deepOnlyPerWeaponMax"] <= weapon["deepPerWeapon"], weapon
    assert weapon["maxDeepOnlyAffixes"] == weapon["maxWeapons"] * weapon["deepOnlyPerWeaponMax"] == 6, weapon
    assert rules["modes"]["deep"]["deepOnlyAffixesPerWeapon"] == weapon["deepOnlyPerWeaponMax"]
    assert rules["modes"]["normal"]["deepOnlyAffixesPerWeapon"] == 0
    assert sum(layout["rows"] for layout in ev["slotLayouts"]) == ev["reachableCustomWeaponRows"]
    assert ev["distinctAttachEffectIdsInReachablePools"] >= len(payload["weaponAffixes"])
    # blessing role by pool family (81x + the 603 subset pools), not slot index
    blessing_pools = set(ev["blessingPools"])
    assert set(ev["blessingPoolsBySubsetOf81x"]) <= blessing_pools
    assert {t // 1_000_000 for t in blessing_pools} <= {603, 810, 811, 812, 813, 814}, blessing_pools
    for pool in payload["weaponAffixPools"]:
        assert ("blessing" in pool["roles"]) == (pool["tableId"] in blessing_pools), pool
    # diagnostics that must stay empty / consistent
    assert payload["diagnostics"]["displayNameZhLatinResidue"] == []
    assert sorted(r["spEffectId"] for r in payload["diagnostics"]["weaponInnateWithoutWeaponIds"]) == sorted(
        b["spEffectId"] for b in buffs if (b.get("weaponInnate") or {}).get("inferredFromRowName"))
    # sources[]: v5 entries keep their positions, the v6 entry is appended
    assert payload["sources"][-1]["name"].startswith("本仓库的其它数据集"), payload["sources"][-1]["name"]
    self_check_v6_reverify(payload)


PER_ID_BEHAVIOURS = ("none", "persistThroughDeath", "stackSelf", "resetOnApply", SPCATEGORY_UNKNOWN[0])


def self_check_v6_reverify(payload: dict[str, Any]) -> None:
    """Second verification round: exclusiveKey, relic-affix filing, deep-only cap, thrusting counter."""
    buffs = payload["buffs"]
    by_id = {b["spEffectId"]: b for b in buffs}
    enums = payload["enums"]
    assert list(enums["exclusiveScope"]) == list(EXCLUSIVE_SCOPE_LABELS), list(enums["exclusiveScope"])
    group_members: dict[str, set[int]] = defaultdict(set)
    for buff in buffs:
        group_members[buff["stacking"]["group"]].add(buff["spEffectId"])
    for buff in buffs:
        sp_id = buff["spEffectId"]
        st = buff["stacking"]
        cat, prio, behaviour = st["spCategory"], st["categoryPriority"], st["spCategoryBehavior"]
        key, scope = st["exclusiveKey"], st["exclusiveScope"]
        # group: per id for every same-id behaviour (resetOnApply included)
        if behaviour in PER_ID_BEHAVIOURS:
            assert st["group"] == f"sp{cat}#{sp_id}" and group_members[st["group"]] == {sp_id}, (sp_id, st)
        else:
            assert st["group"] == f"sp{cat}", (sp_id, st)
        # exclusiveKey follows exclusiveScope
        ladder = buff.get("accumulatorLadder")
        assert (scope == "accumulatorLadder") == bool(ladder), (sp_id, scope)
        if scope == "perSpEffect":
            assert behaviour in PER_ID_BEHAVIOURS and key == f"sp{cat}#{sp_id}", (sp_id, st)
        elif scope == "category":
            assert (behaviour in ("applyHighest", "applyFirst")
                    or (behaviour == "removePrevious" and cat < 200)) and key == f"sp{cat}", (sp_id, st)
        elif scope == "categoryPriority":
            assert behaviour == "removePrevious" and 200 <= cat <= 299 and key == f"sp{cat}@p{prio}", (sp_id, st)
        elif scope == "affixVariant":
            # v6 (re-verify, round 3): only per-id rows are merged, one key per affix
            variant = buff["affixVariant"]
            assert behaviour in PER_ID_BEHAVIOURS and key == variant["key"] == f"affix#{variant['attachEffectId']}", \
                (sp_id, st, variant)
        else:
            assert key == ladder["key"], (sp_id, st, ladder)
            assert ladder["tierSpEffectIds"][ladder["tier"] - 1] == sp_id, (sp_id, ladder)
            assert len(ladder["tierSpEffectIds"]) == ladder["tiers"] == len(ladder["thresholds"]), ladder
            assert ladder["thresholds"] == sorted(ladder["thresholds"]), ladder
            # a ladder key is the category key of its category tiers, or ladder#<tier 1>
            assert key.startswith("sp") or key == f"ladder#{ladder['tierSpEffectIds'][0]}", (sp_id, key)
            # the page reads 「第N层」 for every tier
            assert f"第{ladder['tier']}层" in (buff["displayNameZh"] or ""), (sp_id, buff["displayNameZh"])
        assert (scope == "affixVariant") == bool(buff.get("affixVariant")), (sp_id, scope)
        # tiers of one accumulator ladder that are shipped share the key
        if ladder:
            for other in ladder["tierSpEffectIds"]:
                if other in by_id:
                    assert by_id[other]["stacking"]["exclusiveKey"] == key, (sp_id, other)

    def same(*ids: int) -> None:
        keys = {by_id[i]["stacking"]["exclusiveKey"] for i in ids}
        assert len(keys) == 1, ("must exclude each other", ids, keys)

    def apart(*ids: int) -> None:
        keys = [by_id[i]["stacking"]["exclusiveKey"] for i in ids]
        assert len(set(keys)) == len(keys), ("must stack", ids, keys)

    # positives: groups the game really keeps to one at a time
    same(3160, 3165)                          # fire / lightning grease, right hand (162)
    same(1605000, 503550)                     # Flame, Grant Me Strength / Bloodboil Aromatic (151)
    same(1660000, 503501)                     # Golden Vow / Uplifting Aromatic (160)
    same(511028, 708940)                      # one cracked tear, two potencies (201 @ 226)
    same(707201, 707215)                      # beast form levels (201 @ 70)
    same(312505, 312506, 312507, 312508)      # Millicent's Prosthesis tiers 1..4 (tier 4 is sp20)
    same(320804, 320805, 320806, 320807)      # Winged Sword Insignia tiers 1..4
    same(3558, 3559, 3560, 3561)              # Thorny Cracked Tear tiers 1..4
    same(7039900, 7039909)                    # 206 ladder, stack 1 / stack 10
    # negatives: spCategory 20 buffs that have nothing to do with each other
    apart(320400, 7080000, 704301)            # Red-Feathered Branchsword + 3+ daggers relic + Raider passive
    apart(7080000, 7080600)                   # 3+ daggers + 3+ katana (6 weapons)
    apart(7034402, 7036801)
    apart(7005601, 7005602)                   # affix +1 / +2 (catalog: 不同级别可叠加)
    apart(7030602, 7034402)                   # both on the fixed relic 辽阔的光耀情景
    # ... and the four saved 204 ladders among themselves; different cracked tears
    apart(7069001, 7069201, 8988200, 8998000)
    apart(511028, 511029, 511030, 511031)
    for sp_id in (7069001, 7069201, 8988200, 8998000):
        ladder = by_id[sp_id].get("stackLadder")
        assert ladder and by_id[sp_id]["stacking"]["exclusiveScope"] == "categoryPriority", sp_id
    # every resetOnApply buff outside an accumulator ladder has a key of its own
    reset_keys = [b["stacking"]["exclusiveKey"] for b in buffs
                  if b["stacking"]["spCategoryBehavior"] == "resetOnApply" and not b.get("accumulatorLadder")]
    assert len(reset_keys) == len(set(reset_keys)) >= 70, len(reset_keys)
    ev = payload["diagnostics"]["exclusiveKeyEvidence"]
    assert ev["sp204LaddersAreIdBlocks"] and payload["diagnostics"]["accumulatorLadderConflicts"] == []
    counts = payload["counts"]
    assert sum(counts["buffsByExclusiveScope"].values()) == len(buffs), counts["buffsByExclusiveScope"]
    assert counts["exclusiveKeys"] == len({b["stacking"]["exclusiveKey"] for b in buffs})
    assert counts["buffsWithAccumulatorLadder"] == sum(1 for b in buffs if b.get("accumulatorLadder"))

    # relic-affix buffs the game itself labels 『遗物带来的效果』 sit in the relic column
    for buff in buffs:
        if buff.get("descZh") == "遗物带来的效果":
            assert "relicAffix" in buff["sourceSlots"] and buff.get("relicAffixes"), buff["spEffectId"]
    for sp_id in (7020002, 7020004):
        assert [r["attachEffectId"] for r in by_id[sp_id]["relicAffixes"]] == [7020000], sp_id

    # deep-only cap counts positive affixes only
    weapon = payload["slotRules"]["weaponAffix"]
    wev = weapon["evidence"]
    assert weapon["deepOnlyCapField"] == "weaponAffixDeepOnlyPositive" and weapon["deepOnlyCapCountsCurses"] is False
    assert (wev["deepOnlyPositiveAttachEffectIds"] + wev["deepOnlyCurseAttachEffectIds"]
            == wev["deepOnlyAttachEffectIds"]), wev
    assert wev["deepOnlyPositiveAttachEffectIds"] > 0 and wev["deepOnlyCurseAttachEffectIds"] > 0, wev
    assert weapon["duplicateWithinWeapon"]["status"] == "unknown"
    for buff in buffs:
        if "weaponAffixDeepOnly" in buff:
            assert buff["weaponAffixDeepOnlyPositive"] == (
                buff["weaponAffixDeepOnly"] and "curse" not in buff["weaponAffixRoles"]), buff["spEffectId"]
        else:
            assert "weaponAffixDeepOnlyPositive" not in buff, buff["spEffectId"]
    for affix in payload["weaponAffixes"]:
        assert affix["deepOnlyPositive"] == (affix["deepOnly"] and not affix["isDebuff"]), affix["attachEffectId"]
    assert any(b.get("weaponAffixDeepOnly") and not b.get("weaponAffixDeepOnlyPositive") for b in buffs)
    # the deep-only positive affixes of the regular 505 pools are potency 1 only
    assert wev["deepOnlyPositivePotencyByPoolFamily"].get("505") == [1], wev["deepOnlyPositivePotencyByPoolFamily"]

    # thrusting counter (stateInfo 197): weapon swings / skills only
    for buff in buffs:
        if buff["stacking"]["stateInfo"] == 197 and buff["target"] == "self":
            for cls in ("sorcery", "incantation", "ranged", "throw"):
                assert buff["appliesTo"][cls] == "no", (buff["spEffectId"], cls)
    self_check_v6_round3(payload)


def self_check_v6_round3(payload: dict[str, Any]) -> None:
    """Third verification round: affix variants, accumulator stages / ladder fields, Self/Allies pairs."""
    buffs = payload["buffs"]
    by_id = {b["spEffectId"]: b for b in buffs}
    diagnostics = payload["diagnostics"]
    counts = payload["counts"]

    def key_of(sp_id: int) -> str:
        return by_id[sp_id]["stacking"]["exclusiveKey"]

    # --- affix variants ------------------------------------------------------
    # the 7 『出击时的武器，附加…』 affixes: 4 potencies each, one key per affix
    affix_keys = []
    for base in (7120000, 7120100, 7120200, 7120300, 7120400, 7120500, 7120600):
        tiers = [base + i for i in (1, 2, 3, 4)]
        keys = {key_of(t) for t in tiers}
        assert keys == {f"affix#{base}"}, (base, keys)
        for index, sp_id in enumerate(tiers, 1):
            variant = by_id[sp_id]["affixVariant"]
            assert variant["attachEffectId"] == base and variant["variant"] == index, (sp_id, variant)
            assert variant["variantSpEffectIds"] == tiers and variant["variants"] == 4, (sp_id, variant)
            assert variant["dispatcherSpEffectIds"] == [base] and variant["dispatcherStateInfo"] == [2101], variant
            assert [r["attachEffectId"] for r in by_id[sp_id]["relicAffixes"]] == [base], sp_id
            assert by_id[sp_id]["relicAffixes"][0]["exclusivityId"] == 100, sp_id
        affix_keys.append(key_of(tiers[0]))
    # different affixes keep different keys (the cross-affix 「!」 group is a hint only)
    assert len(set(affix_keys)) == 7, affix_keys
    # the payload rows those tiers point at keep their applyFirst category key
    for payload_id, cat in ((7120405, 10007), (7120505, 10004), (7120605, 10003)):
        assert key_of(payload_id) == f"sp{cat}" and not by_id[payload_id].get("affixVariant"), payload_id
    scan = diagnostics["affixVariantScan"]
    grouped = sorted(i for g in scan["groups"] for i in g["spEffectIds"])
    assert grouped == sorted(b["spEffectId"] for b in buffs if b.get("affixVariant")), grouped
    assert counts["buffsWithAffixVariant"] == len(grouped) == 28 and counts["affixVariantGroups"] == 7, counts
    for group in scan["groups"]:
        members = [by_id[i] for i in group["spEffectIds"]]
        # one key, all passive, same rates keys, owned by the one affix only
        assert {key_of(i) for i in group["spEffectIds"]} == {group["key"]}, group
        assert len({tuple(sorted(b["rates"])) for b in members}) == 1, group
        for b in members:
            owners = ([e["attachEffectId"] for e in b.get("relicAffixes", [])] + list(b.get("weaponAffixIds", [])))
            assert owners == [group["attachEffectId"]], (b["spEffectId"], owners)
    assert all(r["reason"] in AFFIX_VARIANT_REJECT_REASONS for r in scan["rejected"]), scan["rejected"]
    rejected = {tuple(r["spEffectIds"]): r["reason"] for r in scan["rejected"]}
    assert rejected.get((8885220, 8885221, 8885222)) == "columnsDiffer", rejected
    assert rejected.get((7500801, 7500802, 7500803)) == "referencedByChain", rejected
    assert rejected.get((7610700, 7610701, 7610702)) == "ownerPassiveIsBuff", rejected
    # no per-id passive family of one dispatching affix is left with a key per row
    for r in scan["rejected"]:
        if r["reason"] == "alreadySharedKey":
            assert len({key_of(i) for i in r["spEffectIds"]}) == 1, r
    for group in diagnostics["relicAffixExclusivityGroups"]:
        assert group["exclusivityId"] != -1 and group["attachEffectIdsWithBuffs"], group
    excl_100 = next(g for g in diagnostics["relicAffixExclusivityGroups"] if g["exclusivityId"] == 100)
    assert excl_100["attachEffectIds"] == [7120000, 7120100, 7120200, 7120300, 7120400, 7120500, 7120600], excl_100
    assert excl_100["compatibilityIds"] == [200], excl_100
    for buff in buffs:
        for entry in buff.get("relicAffixes", []):
            assert isinstance(entry["exclusivityId"], int), buff["spEffectId"]

    # --- accumulator stages (8885200) --------------------------------------------
    staged = [b for b in buffs if b.get("accumulatorStages")]
    assert [b["spEffectId"] for b in staged] == [8885220, 8885221, 8885222], [b["spEffectId"] for b in staged]
    assert counts["buffsWithAccumulatorStages"] == len(staged)
    for buff in staged:
        stages = buff["accumulatorStages"]
        assert stages["stageSpEffectIds"][stages["stage"] - 1] == buff["spEffectId"], stages
        n = stages["stages"]
        for field in ("stageSpEffectIds", "accumulatorSpEffectIds", "thresholds", "behaviorSpEffectIds",
                      "behaviorParamIds", "bulletIds", "durations"):
            assert len(stages[field]) == n, (field, stages)
        assert stages["thresholds"] == sorted(stages["thresholds"]) and stages["coexist"] is True, stages
        assert f"第{stages['stage']}阶段" in buff["displayNameZh"], buff["displayNameZh"]
        assert f"Stage {stages['stage']}" in buff["displayNameEn"], buff["displayNameEn"]
        # coexisting stages keep a key each (never the per-id key of another stage)
        assert buff["stacking"]["exclusiveScope"] == "perSpEffect", buff["spEffectId"]
    stages = staged[0]["accumulatorStages"]
    assert stages["thresholds"] == [4000000, 9000000, 15000000] and stages["durations"] == [28, 25.5, 22.5], stages
    assert stages["expiryAligned"] == {"unitsPerSecond": 2000000, "commonEndSeconds": 30}, stages["expiryAligned"]
    keys = [key_of(i) for i in (8885220, 8885221, 8885222)]
    assert len(set(keys)) == 3, keys

    # --- accumulator ladder fields ------------------------------------------------
    for buff in buffs:
        ladder = buff.get("accumulatorLadder")
        if not ladder:
            continue
        assert ladder["shippedTierSpEffectIds"] == [t for t in ladder["tierSpEffectIds"] if t in by_id], ladder
        assert buff["spEffectId"] in ladder["shippedTierSpEffectIds"], buff["spEffectId"]
    relic_ladder = by_id[7037604]["accumulatorLadder"]
    assert relic_ladder["tiers"] == 4 and relic_ladder["shippedTierSpEffectIds"] == [7037604, 7037605, 7037606], relic_ladder
    assert 7037607 not in by_id
    # the successive-attack items all share "sp120": two of them never multiply
    assert {key_of(i) for i in (3558, 312505, 320804, 7037604)} == {"sp120"}
    assert "sp120" in payload["enums"]["exclusiveScope"]["accumulatorLadder"]
    assert "accumulatorLadder" in payload["notes"] and "stackLadder" in payload["notes"]

    # --- layer rows named "Stack N" read 「第N层」 ------------------------------------
    stack_rows = 0
    for buff in buffs:
        match = STACK_ROW_RE.search(buff["paramName"] or "")
        if match:
            stack_rows += 1
            assert f"第{match.group(1)}层" in buff["displayNameZh"], buff["displayNameZh"]
            assert "档位" not in buff["displayNameZh"], buff["displayNameZh"]
    assert stack_rows == 13, stack_rows
    assert by_id[7039900]["displayNameZh"].startswith("出现异常状态量表时，能缓慢提升攻击力"), by_id[7039900]["displayNameZh"]

    # --- Self / Allies pairs -------------------------------------------------------
    paired = [b for b in buffs if b.get("selfAllyPair")]
    assert counts["buffsWithSelfAllyPair"] == len(paired) == 6, len(paired)
    for buff in paired:
        pair = buff["selfAllyPair"]
        other = by_id[pair["counterpartSpEffectId"]]["selfAllyPair"]
        assert other["counterpartSpEffectId"] == buff["spEffectId"] and {pair["role"], other["role"]} == {"self", "ally"}
        assert buff["target"] == pair["role"], (buff["spEffectId"], buff["target"], pair)
    assert by_id[1876]["selfAllyPair"] == {"role": "self", "counterpartSpEffectId": 1877}
    assert key_of(1876) != key_of(1877)
    pairs = {p["self"]["spEffectId"]: p for p in diagnostics["selfAllyPairs"]}
    assert pairs[1870]["ally"]["friendlyHitAtkIds"] == [300000820] and pairs[1876]["ally"]["friendlyHitAtkIds"] == [300000820]
    assert pairs[1876]["deliveryMatchesRowName"] and not pairs[1835]["deliveryMatchesRowName"], pairs


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
