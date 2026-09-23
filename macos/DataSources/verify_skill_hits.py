#!/usr/bin/env python3
"""核实战技 / 法术数据集里的每段命中是否真的会被本作动画打出（读 TAE 事件）。

背景
----
generate_skills.py 的 hits 是沿参数链找出来的：SwordArtsParam → BehaviorParam_PC → AtkParam_Pc /
Bullet，再加 Paramdex 行名匹配。但参数表里存着的行不一定被本作的动画调用——「狩猎大蛇」
（武器 17030000，behaviorVariationId 1703）在参数里有三段 "Beam of Light"，本作里却不是远程。
唯一能回答「这段到底会不会打出」的是动画事件表 TAE（extract_tae.py 解出的 raw/tae/invoked.json）。

规律（1.03.5 实测，见 PROVENANCE.md「TAE 动画事件与命中核实」）
----------------------------------------------------------------
1. 战技动画在 TAE a(600 + SwordArtsParam.swordArtsType) 里，动画号 4xxxx
   （40000 = L2 第一段，40005 = 同段的无 FP 版，40010/40020 = 后续段，40200/40300/42400… =
   其它动作组的变体）。例：狩猎大蛇 swordArtsType 188 → a788；狮子斩 0 → a600；
   风暴刃 59 → a659；狩猎巨人 16 → a616；回旋斩 3 → a603；野蛮咆哮 140 → a740；战吼 141 → a741。
2. 事件里的 Behavior Judge ID 是「行为组前缀 + judge」的压缩写法：
   BehaviorParam_PC.ID = base + behaviorVariationId*1000 + behaviorJudgeId，
   TAE 的 judgeId = judge（base 为 1 亿的普通攻击）或 (base / 1 亿)*1000 + judge（其它组）。
   例：a788 动画 40000 的 judgeId 3950 → base 300000000、judge 950 → 武器 1703 取 301703950。
   解行按三级回退（Params.resolve_row，与 generate_skills.py 同一口径）：武器自己的 variationId（1703 →
   301703950）→ 没有时取整到百位的「族」variationId（例 1101 / 1107 的锤 → 1100 → 301100957）→ 再没有才落到
   variationId=0 的通用行（300000950）。（第一版只有「自己 → 0」两级，曾把锤误判成打 300000957，见 PROVENANCE。）
   两个例外：
   * base 400000000 的行（风暴管束者 4001xxxxx…）按行自己的 variationId 解、不按武器：这些
     variationId（100/500/900/1100/1102/1800/2100/2300/4100/5000）与武器类别的 var 重合，
     「按渡夜者选行」是从 Paramdex 的 AtkParam 行名（"[AoW - Duchess] Storm Ruler"）推断的；
     两种读法下结论相同（code 相同、a860 全部调用），匹配记录带 characterVariationId；
   * base 不是 1 亿整数倍的行（ID 10/11/100/400…、2120/2121/2140/2141 等 242 行）不走 TAE judgeId：
     其中 162 行被 SpEffectParam.behaviorId 引用、由 SpEffect 触发（祈祷一击的回血子弹 SpEffect 1630 → 2120、
     卡利亚式奉还的反击 1515 → 2140），本脚本记为 spEffect 并附来源；其余 80 行（10/11/100/400–513…）
     没有任何 SpEffect 引用，数据集也没有段落在它们上。
3. 事件的 stateInfo 是**前置条件**：不为 0 时，只有角色身上有对应 SP_EFFECT_TYPE 的
   SpEffect 才会触发（例：2211 "Ice Storm upon Charged Attacks" 门控着蓄力攻击上的冰暴子弹；
   609 "Cursed Sword Active" 门控执行者的诅咒剑攻击）。stateInfo 187 是本体打拉卡德时
   大蛇狩猎矛「光波延长命中」的门控：本作全部参数里只有 SpEffect 1908 带它，1908 只被
   BuddyStoneParam 16000114（m16 的 NPC 召唤石 doping）引用，玩家拿不到。
4. 战吼 / 野蛮咆哮 / 灭洛斯的狂嚎这三个「改写 R2」的战技（ROAR_R2_SKILLS），其 R2 攻击段在
   **武器动作组** TAE a(EquipParamWeapon.wepmotionCategory) 的 30600–30635 / 32600–32635 动画里
   （judgeId 3950–3969 野蛮咆哮 / 灭洛斯，3980–3997 战吼），不在 a740 / a741 / a815 里；
   这三个 TAE 的事件 331（Add SpEffect - Weapon Skill）上的 buff（1680/1682、1810/1812、840/842）
   就是 HKS 选 30600 系动画的开关。所以只有这三个战技的段允许 weaponTae；别的战技的段若只出现在
   这些动画里（例：狩猎大蛇 301703955 只在 a37_030605），记为 roarR2Only——不属于该战技。
5. 法术：施法动画在 TAE a(400 + Magic.refType) 里，事件 64「Cast Selected Magic」只带
   refSlot（0 → Magic.refId1 … 9 → refId10），子弹 / 攻击行由 Magic.refIdN 决定。
   所以法术段的「是否打出」= 它所在的 refId 槽是否被施法动画的事件 64 用到；
   refCategory 2 槽里带 stateInfo 的 SpEffect（因果性原理 1676000，stateInfo 170）是触发型，
   它触发时发射同一 Magic 里施法动画不用的子弹槽（spEffectDerived）。
6. 动画头为 ImportOtherAnim 的动画（598 个）整段从另一个动画导入事件，本脚本跟随
   （导入号 = TAE 号 * 1000000 + 动画号）。
7. 战技 TAE 的 4xxxx 动画按百位分「套」：400xx 默认套、402xx 大型武器套、403xx 长柄套、
   4XXxx（XX ≥ 20）= wepmotionCategory XX 的武器专属套（424 双头剑、442 拳、445 大弓、447/448 盾）。
   同一把武器只播其中一套（HKS 的 GetSwordArtsDiffCategory 选，字节码读不出）。多数战技各套的
   judge 相同，但回旋斩 a603（四套）、二连斩 a612、剑舞 a624、鲜血斩击 a654 各套 judge 不同——
   把几套一起算会让伤害翻 2–4 倍。本脚本按 variant × var 检查各段所在的套有没有交集，没有交集时
   按 choose_block() 的规则选一套（motion 专属套 → 专属行 → 类别归组（有证据）→ 行名点名类别 →
   类别归组（推断）→ 默认套），其余套的段记 exclusiveBlock，另列一桶（不与 invoked 相加）。
   「行名点名类别」：某套的 AtkParam 行名写着 "(Greatsword)" 这类 WEP_TYPE 名时，是「该类别播这一套」的直接
   证据（204 鲜血斩击 402 套的 300000055/056 行名是 "Slash (Greatsword)"），比体型类比强，记 classGroupNamed。
8. 战技 TAE 的 4xxxx 动画按十位成对：个位 0–4 = 带 FP 版，个位 5–9 = 同一动作的无 FP 版（= 带 FP 版动画号 + 5；
   40005 ↔ 40000、40116 ↔ 40111、40068 ↔ 40063）。本机 1.03.5 全部战技 TAE 里个位 ≥ 5 的 4xxxx 动画 436 个，
   每一个都有 −5 的带 FP 版；数据集里行名带 "No FP" 且有 TAE 证据的段全部只被个位 ≥ 5 的动画调用，没有一段
   落在个位 0–4 上。所以一段若只被无 FP 版动画调用，它就是无 FP 分支，即使行名没写 "No FP"（风暴刃
   300000411–413 只在 a659 的 40005/40015/40025，狩猎巨人 301700915 只在 a616 的 40005）；两边动画都调用的
   段是共用段。fp_evidence() 给出一段的依据分支，generate_skills.py 据此补标 hits[].noFp / fpBoth。

判定
----
对数据集每个战技的每个 variant（每把武器）、按 behaviorVariationId 分组逐段：
  * 先按该武器的 behaviorVariationId 解出「哪些 (base, judge) 会打出这段」（三级回退：专属行 → 取整到百位的
    族 var → var 0，与 generate_skills.py 同一口径）；
  * 再把每个 (base, judge) 换成 TAE judgeId，在战技 TAE → 武器 TAE → 全局 里找事件；
  * status：invoked（战技 TAE 里有无门控事件）/ weaponTae（吼叫类战技的 R2，在武器动作组 TAE 的
    30600 系动画里）/ spEffect（由 SpEffectParam.behaviorId 触发，附来源）/ conditional（只有带
    stateInfo 门控的事件且该状态可达）/ exclusiveBlock（只在这把武器不播的另一套 4xxxx 动画里）/
    gated（只有 187 门控）/ roarR2Only（非吼叫战技却只在吼叫 R2 动画里）/ elsewhere（只在别的 TAE
    里出现，列出位置）/ notInvoked（有行、任何 TAE 都没有事件）/ spEffectNoSource（由 SpEffect 触发，
    但该 SpEffect 在全部参数表与 TAE 事件里都没有来源）/ rowForOtherWeapon（BehaviorParam_PC 里产出
    这段的行只属于别的 behaviorVariationId，这把武器解不到）/ unreferenced（没有任何参数行、子弹、
    Magic 或其它参数列引用这段）/ noJudge（走箭矢 / 子弹或只是 SwordArtsParam.atkParamId 锚点，
    不经 BehaviorParam_PC，无法用本方法判定）。
  * 「从未打出」的清单按 variant × behaviorVariationId 列（同一段在大锤上打不出、在锤上打得出
    的情况不会被战技层的「最好状态」盖掉），数据集 variant（via=behavior）与抽取表补的
    variant（via=table）分开计数。
  * 数据集里没挂武器的战技（如风暴刃、狩猎巨人：本作武器的战技是从 SwordArtsTableParam 抽的，
    v2 的 generate_skills.py 只看了 EquipParamWeapon.swordArtsParamId），用抽取表里会抽到它的武器补上
    （via="table"）。v3 数据集（schemaVersion ≥ 3）的 weaponIds 已含局内战技池，不再补。

被 generate_skills.py 调用
------------------------
  TaeVerifier（本文件）把上面的判定打包：generate_skills.py 生成数据集时逐 (战技, 武器) 调用 check()，
  variants[].atkIds 只留 KEEP_STATUSES（invoked / weaponTae / spEffect / conditional / noJudge），
  并按规律 8 用 fp_evidence() 补标 hits[].noFp（noFpSource="tae"）/ fpBoth。
  所以对 TAE 核实后的数据集再跑本脚本，数据集 variant 里应当只剩这几种状态（自洽检查）；
  核实前的对照报告可用 --skills 指向 A 阶段的数据集另跑一份。
  「打得出」不等于「打敌人」：AtkParam 的 opposeTarget=0 且 selfTarget / friendlyTarget=1 的行只打自己 / 队友
  （祈祷一击的回血子弹 1202100 Heal Self、1202110 Heal Others，各带圣 motion 100）。它们照样按 spEffect 留在
  atkIds 里（动画确实会触发），但数据集在 hits 上标 noDamage + selfOrAllyOnly，本脚本的「带伤害」计数
  （hit_damaging）也不算它们。

用法
----
  cd "<repo>/macos/DataSources" && python3 verify_skill_hits.py
  可选：--invoked raw/tae/invoked.json --params raw/params --skills ../../data/nightreign-skills-v1.03.5.json
        --enum raw/paramdex/SP_EFFECT_TYPE.json --out raw/tae
输出：raw/tae/hit-invocation-report.json 与 hit-invocation-report.md
"""
from __future__ import annotations

import argparse
import csv
import json
import re
import sys
from collections import Counter, defaultdict
from datetime import datetime, timezone
from pathlib import Path

HERE = Path(__file__).resolve().parent
DEFAULT_PARAMS = HERE / "raw" / "params"
DEFAULT_INVOKED = HERE / "raw" / "tae" / "invoked.json"
DEFAULT_SKILLS = HERE.parents[1] / "data" / "nightreign-skills-v1.03.5.json"
DEFAULT_ENUM = HERE / "raw" / "paramdex" / "SP_EFFECT_TYPE.json"
DEFAULT_OUT = HERE / "raw" / "tae"

SKILL_TAE_BASE = 600      # 战技 TAE = a(600 + swordArtsType)
MAGIC_TAE_BASE = 400      # 施法 TAE = a(400 + Magic.refType)
NORMAL_BASE = 100000000   # 普通攻击行的 base；其它 base 都是它的整数倍
HIT_EVENT_TYPES = {1: "attack", 2: "bullet", 5: "common", 304: "throw", 307: "pcBehavior"}
# 事件 307 Invoke PC Behavior 只有 pcBehaviorType=8 时 judgeId 走 BehaviorParam_PC（踢击 3085/3086、
# 无 FP 版踏地 3051/3056 都是这样触发的）；type 4（judge 500–561，翻滚 / 跳跃类）与 2 / 16 不是攻击行。
PC_BEHAVIOR_ATTACK_TYPE = 8
CAST_EVENT = 64
SPEFFECT_EVENT_TYPES = {66, 67, 302, 331, 401}   # extract_tae.py 记录的「给自己上 SpEffect」事件
STATUS_ORDER = ["invoked", "weaponTae", "spEffect", "conditional", "exclusiveBlock", "roarR2Only", "gated", "elsewhere",
                "notInvoked", "spEffectNoSource", "rowForOtherWeapon", "unreferenced", "noJudge"]
# 该战技在该武器上永远打不出（exclusiveBlock 不在内：它在别的动作套里打得出，另列一桶）
NEVER_STATUSES = ("roarR2Only", "gated", "elsewhere", "notInvoked", "spEffectNoSource", "rowForOtherWeapon", "unreferenced")
# 只有 SpEffect 1908 带 stateInfo 187，而 1908 只被 BuddyStoneParam 16000114 的 dopingSpEffectId 引用
UNREACHABLE_GATES = {187}
# 改写 R2 的吼叫类战技：它们的 TAE（a740 / a741 / a815）用事件 331 给自己上 1680/1682、1810/1812、840/842，
# HKS 据此把 R2 换成武器动作组 TAE 的 30600 系动画。HKS 是字节码读不出来，这里显式列出；
# 报告的 roarSkills 会把每个战技 TAE 上的 331 SpEffect 列出来作证据（夸耀咆哮 654 / 王者嘶吼 1031 也有
# 同结构的 331 buff，但数据集没有把 R2 行挂给它们——见 PROVENANCE）。
ROAR_R2_SKILLS = {650: "野蛮咆哮", 651: "战吼", 1015: "灭洛斯的狂嚎"}
ROAR_R2_ANIM_RANGES = ((30600, 30635), (32600, 32635))
# variationId 表示渡夜者而不是武器的 base（风暴管束者 4001xxxxx = 女爵、4005xxxxx …）
CHARACTER_VARIATION_BASES = {400000000}
# 战技 TAE 的 4xxxx 动画按百位分套（规律 7）：400 默认、402 大型武器、403 长柄、4XX（XX ≥ 20）= wepmotionCategory XX 专属。
SKILL_ANIM_RANGE = (40000, 49999)
DEFAULT_BLOCK, LARGE_BLOCK, POLEARM_BLOCK = 400, 402, 403
# wepType → 套。有证据的一组来自数据集 103 回旋斩的手工归组（generate_skills.py CTX_MANUAL_BY_SKILL：直剑 3 / 曲剑 9 默认套，
# 大曲剑 11 Large Weapon，戟 29 / 镰 31 Polearm；双头剑 14 走 424 由 motion 规则覆盖）。其余按体型类比推断（报告标 inferred，未证实）。
CLASS_BLOCK_EVIDENCED = {3: DEFAULT_BLOCK, 9: DEFAULT_BLOCK, 11: LARGE_BLOCK, 29: POLEARM_BLOCK, 31: POLEARM_BLOCK}
CLASS_BLOCK_INFERRED = {5: LARGE_BLOCK, 7: LARGE_BLOCK, 19: LARGE_BLOCK, 23: LARGE_BLOCK, 41: LARGE_BLOCK,
                        25: POLEARM_BLOCK, 28: POLEARM_BLOCK}
# 「行名点名类别」（规律 7）：AtkParam 行名里的类别写法（Paramdex WEP_TYPE 英文名），只列推断组里的类别——
# 有证据的类别不需要它，别的类别在本作的互斥套战技里没有被行名点名。匹配带括号的整词 "(Greatsword)"，
# 所以 "(Curved Greatsword)" 不会误中大剑。
WEP_TYPE_NAME_EN = {5: "Greatsword", 7: "Colossal Sword", 19: "Greataxe", 23: "Great Hammer", 41: "Colossal Weapon",
                    25: "Spear", 28: "Great Spear"}
# 规律 8：战技 TAE 的 4xxxx 动画个位 0–4 = 带 FP 版、5–9 = 无 FP 版（带 FP 版动画号 + 5）
NO_FP_UNIT_MIN = 5
# 箭矢 / 大箭 / 弩箭 / 弩炮弹的 behaviorVariationId 都在 5000–5399（wepType 81/83/85/86）：弓系战技的段由弹药的行打出，
# 数据集按弓的 var 挂武器，这里不按弹药 var 解，只记 noJudge 并说明
AMMO_VARIATION_RANGE = (5000, 5399)
# 全表扫描时，列名含 spEffect / doping 但其实不是 SpEffect ID 的列（消息 / 文本 / 开关 / 倍率 / 子弹号…）
SPEFFECT_COLUMN_EXCLUDE = ("msg", "text", "enable", "type", "category", "rate", "life", "override", "dummypoly",
                           "bulletid", "fadeout", "maxlength", "disablehit", "setparam")


def is_hit_event(ev: dict) -> bool:
    t = ev["type"]
    if t == 307:
        return ev.get("pcBehaviorType") == PC_BEHAVIOR_ATTACK_TYPE
    return t in HIT_EVENT_TYPES


def is_roar_anim(aid: int) -> bool:
    return any(lo <= aid <= hi for lo, hi in ROAR_R2_ANIM_RANGES)


def is_speffect_column(name: str) -> bool:
    n = name.lower()
    return ("speffect" in n or "doping" in n) and not any(x in n for x in SPEFFECT_COLUMN_EXCLUDE)


def is_ammo_var(var: int) -> bool:
    return AMMO_VARIATION_RANGE[0] <= var <= AMMO_VARIATION_RANGE[1]


def is_atk_column(name: str) -> bool:
    """引用 AtkParam 的列：atkId_Bullet / atkParamId / markingAtkParamId…（atkBehaviorId、atkAttribute 不算）。"""
    return re.search(r"atk(param)?id", name, re.I) is not None


def read_param(params: Path, name: str) -> list[dict]:
    with open(params / f"{name}.csv", newline="", encoding="utf-8") as fp:
        return list(csv.DictReader(fp))


def to_int(v, default=0) -> int:
    try:
        return int(v)
    except (TypeError, ValueError):
        return default


def judge_code(base: int, judge: int) -> int | None:
    """BehaviorParam_PC 的 (base, judge) → TAE 事件里的 judgeId；base 不是 1 亿整数倍的行不走 TAE。"""
    if base < NORMAL_BASE or base % NORMAL_BASE != 0:
        return None
    if base == NORMAL_BASE:
        return judge
    return (base // NORMAL_BASE) * 1000 + judge


# ------------------------------------------------------------------ TAE 索引

class TaeIndex:
    def __init__(self, invoked: dict):
        self.events: dict[tuple[int, int], list[dict]] = {}
        self.imports: dict[tuple[int, int], int] = {}
        self.files: dict[tuple[int, int], str] = {}
        self.anims: dict[int, set[int]] = defaultdict(set)
        for key, anims in invoked["animMeta"].items():
            tae = int(key.split("/a")[1])
            for aid, meta in anims.items():
                self.anims[tae].add(int(aid))
                if meta.get("file"):
                    self.files[(tae, int(aid))] = meta["file"]
        for key, anims in invoked["events"].items():
            tae = int(key.split("/a")[1])
            for aid, evs in anims.items():
                self.events[(tae, int(aid))] = evs
        for key, anims in invoked["imports"].items():
            tae = int(key.split("/a")[1])
            for aid, src in anims.items():
                self.imports[(tae, int(aid))] = int(src)
        self._resolved: dict[tuple[int, int], list[dict]] = {}
        # code → [(tae, anim, event)]，只收命中类事件
        self.by_code: dict[int, list[tuple[int, int, dict]]] = defaultdict(list)
        self.by_tae_code: dict[int, dict[int, list[tuple[int, dict]]]] = defaultdict(lambda: defaultdict(list))
        self.cast_slots: dict[int, dict[int, set[int]]] = defaultdict(lambda: defaultdict(set))  # tae → anim → slots
        self.speffects: dict[tuple[int, int], set[int]] = defaultdict(set)   # (tae, anim) → 事件 66/67/331 上的 SpEffect
        self.by_tae_speffects: dict[int, set[int]] = defaultdict(set)
        self.by_tae_weapon_skill_speffects: dict[int, set[int]] = defaultdict(set)   # 只算事件 331（战技 buff）
        self.speffect_taes: dict[int, set[int]] = defaultdict(set)   # SpEffect → 哪些 TAE 的事件会上它（全局）
        self.has_speffect_events = False
        for tae, aids in self.anims.items():
            for aid in aids:
                for ev in self.resolve(tae, aid):
                    if is_hit_event(ev):
                        code = ev["judgeId"]
                        self.by_code[code].append((tae, aid, ev))
                        self.by_tae_code[tae][code].append((aid, ev))
                    elif ev["type"] == CAST_EVENT:
                        self.cast_slots[tae][aid].add(ev.get("refSlot", 0))
                    elif ev["type"] in SPEFFECT_EVENT_TYPES:
                        self.has_speffect_events = True
                        for k in ("spEffectId", "spEffectIdFp", "spEffectIdNoFp"):
                            sid = ev.get(k)
                            if sid and sid > 0:
                                self.speffects[(tae, aid)].add(sid)
                                self.by_tae_speffects[tae].add(sid)
                                self.speffect_taes[sid].add(tae)
                                if ev["type"] == 331:
                                    self.by_tae_weapon_skill_speffects[tae].add(sid)

    def resolve(self, tae: int, aid: int, depth: int = 0) -> list[dict]:
        key = (tae, aid)
        if key in self._resolved:
            return self._resolved[key]
        out = list(self.events.get(key, []))
        src = self.imports.get(key)
        if src is not None and depth < 4:
            s_tae, s_aid = src // 1000000, src % 1000000
            if (s_tae, s_aid) != key:
                out = out + self.resolve(s_tae, s_aid, depth + 1)
        self._resolved[key] = out
        return out


# ------------------------------------------------------------------ 参数

class Params:
    def __init__(self, params: Path):
        self.atk = {r["ID"]: r for r in read_param(params, "AtkParam_Pc")}
        self.bullets = {r["ID"]: r for r in read_param(params, "Bullet")}
        self.magic = {r["ID"]: r for r in read_param(params, "Magic")}
        self.sword_arts = {r["ID"]: r for r in read_param(params, "SwordArtsParam")}
        self.weapons = {r["ID"]: r for r in read_param(params, "EquipParamWeapon")}
        self.rows: dict[tuple[int, int, int], dict] = {}
        self.row_by_id: dict[str, dict] = {}
        self.producers: dict[str, set[tuple[int, int, int]]] = defaultdict(set)   # atkId → {(base, var, judge)}
        self._row_atks: dict[str, frozenset[str]] = {}
        for r in read_param(params, "BehaviorParam_PC"):
            bid, var, judge = to_int(r["ID"]), to_int(r["variationId"]), to_int(r["behaviorJudgeId"])
            base = bid - var * 1000 - judge
            self.rows[(base, var, judge)] = r
            self.row_by_id[r["ID"]] = r
            for a in self.row_atks(r):
                self.producers[a].add((base, var, judge))
        # 抽取表：tableId → {swordArtsId}
        self.tables: dict[str, set[str]] = defaultdict(set)
        for r in read_param(params, "SwordArtsTableParam"):
            if to_int(r["chanceWeight"]) > 0 and r["swordArtsId"] not in ("-1", "0"):
                self.tables[r["ID"]].add(r["swordArtsId"])
        # SpEffect：门控名、behaviorId 引用
        self.sp_rows: dict[str, dict] = {}
        self.state_names: dict[int, str] = {}
        self.sp_by_behavior: dict[str, list[str]] = defaultdict(list)   # BehaviorParam_PC.ID → [SpEffect ID]
        for r in read_param(params, "SpEffectParam"):
            self.sp_rows[r["ID"]] = r
            si = to_int(r.get("stateInfo"))
            if si and r.get("Name") and si not in self.state_names:
                self.state_names[si] = r["Name"]
            if r.get("behaviorId") not in ("-1", "0", "", None):
                self.sp_by_behavior[r["behaviorId"]].append(r["ID"])
        # 全表扫描（全部 *.csv）：
        #   sp_sources：任何表里名字含 spEffect / doping 的列 → 「谁会上这个 SpEffect」（AtkParam_Pc.spEffectId0–4、
        #     Bullet.spEffectId0–4 / spEffectIDForShooter、SpEffectParam 的 cycle / atk / replace 链、EquipParamWeapon、
        #     BuddyStoneParam.dopingSpEffectId…），用来判断 SpEffect 触发的段有没有来源（spEffectNoSource）；
        #   atk_refs：名字是 atkId / atkParamId 的列（Bullet.atkId_Bullet、Magic.atkParamId、SwordArtsParam.atkParamId、
        #     PlayerCommonParam.markingAtkParamId）以及 BehaviorParam_PC.refId（refType 0）、Magic.refIdN（refCategory 0）
        #     → 「谁引用了这段 AtkParam」，用来判断段是否完全无引用（unreferenced）。
        self.sp_sources: dict[str, list[str]] = defaultdict(list)       # SpEffect ID → "表 行ID.列"
        self.atk_refs: dict[str, list[str]] = defaultdict(list)         # AtkParam_Pc ID → "表 行ID.列"
        self.scanned_tables: list[str] = []
        for path in sorted(params.glob("*.csv")):
            table = path.stem
            with open(path, newline="", encoding="utf-8") as fp:
                reader = csv.reader(fp)
                header = next(reader, None)
                if not header:
                    continue
                sp_cols = [i for i, h in enumerate(header) if i and is_speffect_column(h)]
                atk_cols = [i for i, h in enumerate(header) if i and is_atk_column(h)]
                if not sp_cols and not atk_cols:
                    continue
                self.scanned_tables.append(table)
                for row in reader:
                    for i in sp_cols:
                        v = row[i] if i < len(row) else ""
                        if v not in ("-1", "0", ""):
                            self.sp_sources[v].append(f"{table} {row[0]}.{header[i]}")
                    for i in atk_cols:
                        v = row[i] if i < len(row) else ""
                        if v not in ("-1", "0", "") and v in self.atk:
                            self.atk_refs[v].append(f"{table} {row[0]}.{header[i]}")
        for r in self.row_by_id.values():
            if to_int(r.get("refType")) == 0 and r.get("refId") in self.atk:
                self.atk_refs[r["refId"]].append(f"BehaviorParam_PC {r['ID']}.refId")
        for r in self.magic.values():
            for n in range(1, 11):
                if to_int(r.get(f"refCategory{n}")) == 0 and r.get(f"refId{n}") in self.atk:
                    self.atk_refs[r[f"refId{n}"]].append(f"Magic {r['ID']}.refId{n}")
        # behaviorVariationId → 武器行（rowForOtherWeapon 时说明那些行属于谁）
        self.weapons_by_var: dict[int, list[dict]] = defaultdict(list)
        for r in self.weapons.values():
            self.weapons_by_var[to_int(r.get("behaviorVariationId"))].append(r)

    def bullet_chain(self, root: str, limit: int = 64) -> list[str]:
        seen, order, stack = set(), [], [root]
        while stack and len(order) < limit:
            bid = stack.pop()
            if bid in seen or bid not in self.bullets:
                continue
            seen.add(bid)
            order.append(bid)
            row = self.bullets[bid]
            for f in ("HitBulletID", "intervalCreateBulletId"):
                child = row.get(f, "-1")
                if child not in ("-1", "0", "") and child in self.bullets:
                    stack.append(child)
        return order

    def bullet_atks(self, bullet_id: str) -> frozenset[str]:
        key = "b" + bullet_id
        if key not in self._row_atks:
            out = set()
            for bid in self.bullet_chain(bullet_id):
                a = self.bullets[bid].get("atkId_Bullet", "-1")
                if a in self.atk:
                    out.add(a)
            self._row_atks[key] = frozenset(out)
        return self._row_atks[key]

    def row_atks(self, row: dict) -> frozenset[str]:
        ref_type, ref = to_int(row.get("refType")), row.get("refId", "-1")
        if ref_type == 0:
            return frozenset([ref]) if ref in self.atk else frozenset()
        if ref_type == 1 and ref in self.bullets:
            return self.bullet_atks(ref)
        return frozenset()

    def row_bullets(self, row: dict) -> list[str]:
        if to_int(row.get("refType")) == 1 and row.get("refId") in self.bullets:
            return self.bullet_chain(row["refId"])
        return []

    def resolve_row(self, base: int, var: int, judge: int) -> dict | None:
        """与 generate_skills.py 的 behavior_row 同一口径的三级回退：武器自己的 variationId →
        向下取整到百位的「族」variationId（例 1406 → 1400、117 → 100）→ variationId = 0 的通用行。
        （第一版只有「自己 → 0」，v3 数据集的战技池武器里 1500 多个 (段, 武器) 因此被误判成 rowForOtherWeapon。）"""
        return (self.rows.get((base, var, judge))
                or (self.rows.get((base, var // 100 * 100, judge)) if var % 100 else None)
                or self.rows.get((base, 0, judge)))

    def codes_for_atk(self, atk: str, var: int) -> dict[int, dict]:
        """这段命中在该武器（behaviorVariationId=var）上会由哪些 TAE judgeId 打出：code → 行。
        base 400000000 的行按渡夜者取 variationId，与武器无关，按行自己的 variationId 解（附 _charVars）。"""
        out: dict[int, dict] = {}
        for base, v, judge in self.producers.get(atk, ()):
            code = judge_code(base, judge)
            if code is None:          # SpEffectParam.behaviorId 触发的行，不走 TAE
                continue
            if base in CHARACTER_VARIATION_BASES and v != 0:
                row = self.rows[(base, v, judge)]
                if code in out and "_charVars" in out[code]:
                    out[code]["_charVars"].append(v)
                else:
                    out[code] = dict(row, _charVars=[v])
                continue
            row = self.resolve_row(base, var, judge)
            if row and atk in self.row_atks(row):
                out[code] = row
        return out

    def speffect_rows_for_atk(self, atk: str) -> list[tuple[dict, list[str]]]:
        """会产出这段、且被 SpEffectParam.behaviorId 引用的 BehaviorParam_PC 行（任何 base）。"""
        out = []
        for base, v, judge in sorted(self.producers.get(atk, ())):
            row = self.rows[(base, v, judge)]
            sps = self.sp_by_behavior.get(row["ID"])
            if sps:
                out.append((row, sps))
        return out

    def producer_rows(self, atk: str) -> list[dict]:
        """产出这段的全部 BehaviorParam_PC 行，附各行 variationId 对应的武器（rowForOtherWeapon 的说明）。"""
        out = []
        for base, v, judge in sorted(self.producers.get(atk, ())):
            row = self.rows[(base, v, judge)]
            ws = self.weapons_by_var.get(v, [])
            out.append({"behaviorId": to_int(row["ID"]), "variationId": v,
                        "weapons": [f"{w['ID']} {w.get('Name', '')}".strip() for w in ws[:4]],
                        "weaponSwordArtsParamIds": sorted({to_int(w.get("swordArtsParamId")) for w in ws})[:8]})
        return out


# ------------------------------------------------------------------ 判定

def state_name(si: int, params: Params, enum: dict[int, str]) -> str:
    if si == 187:
        return "187（本体打拉卡德的光波延长命中门控；本作只有 SpEffect 1908 带它，1908 只被 BuddyStoneParam 16000114 的 doping 引用，玩家拿不到）"
    name = enum.get(si) or params.state_names.get(si) or ""
    return f"{si}（{name}）" if name else str(si)


class SkillCtx:
    """判断 spEffect 来源是否出自本战技：本战技的段、这些段的子弹链、战技 TAE 上的 SpEffect。"""

    def __init__(self, atks: set[str], bullets: set[str], tae_speffects: set[int]):
        self.atks, self.bullets, self.tae_speffects = atks, bullets, tae_speffects

    def owns(self, source: str, sp_id: str) -> bool:
        if to_int(sp_id) in self.tae_speffects:
            return True
        table, rest = source.split(" ", 1)
        ident = rest.split(".", 1)[0]
        if table == "AtkParam_Pc":
            return ident in self.atks
        if table == "Bullet":
            return ident in self.bullets
        return False


def match_events(atk: str, codes: dict[int, dict], skill_tae: int | None, weapon_taes: set[int], idx: TaeIndex,
                 params: Params, enum: dict[int, str], roar_skill: bool,
                 sp_rows: list[tuple[dict, list[str]]] = (), ctx: SkillCtx | None = None,
                 anchor: str | None = None) -> dict:
    """在战技 TAE → 武器 TAE → 全局 找这些 code 的事件，返回 status 与证据。
    codes 为空时再分：有行但不属于这把武器的 var（rowForOtherWeapon）/ 锚点或走子弹（noJudge）/ 完全无引用（unreferenced）。"""
    matches: list[dict] = []
    for code, row in sorted(codes.items()):
        # 武器专属行（variationId≠0）只会被「这把武器」的动画解到：别的 TAE 里同样的 code
        # 会解成别的武器 / var 0 的行，所以对专属行不看「其它位置」。角色变体行（_charVars）不算专属。
        specific = to_int(row.get("variationId")) != 0 and "_charVars" not in row
        for tae, aid, ev in idx.by_code.get(code, []):
            if tae == skill_tae:
                loc = "skill"
            elif tae in weapon_taes:
                loc = "weaponRoar" if is_roar_anim(aid) else "weapon"
            else:
                loc = "otherWeapon" if specific else "other"
            m = {
                "code": code, "behaviorId": to_int(row["ID"]), "loc": loc, "tae": f"a{tae}", "anim": aid,
                "file": idx.files.get((tae, aid)), "eventType": HIT_EVENT_TYPES[ev["type"]],
                "start": ev["start"], "end": ev["end"], "stateInfo": ev.get("stateInfo", 0),
                "attackIndex": ev.get("attackIndex"),
            }
            if "_charVars" in row:
                m["characterVariationId"] = sorted(set(row["_charVars"]))
            matches.append(m)
    relevant = [m for m in matches if m["loc"] != "otherWeapon"]
    ungated = [m for m in relevant if not m["stateInfo"]]
    gated_here = [m for m in relevant if m["stateInfo"] and
                  (m["loc"] == "skill" or (m["loc"] == "weaponRoar" and roar_skill))]
    if any(m["loc"] == "skill" for m in ungated):
        status = "invoked"
    elif roar_skill and any(m["loc"] == "weaponRoar" for m in ungated):
        status = "weaponTae"
    elif sp_rows:
        status = "spEffect"
    elif gated_here:
        # 门控：条件玩家拿得到 → conditional；只有 187 这种拿不到的状态 → gated（等于永远打不出）
        reachable = any(m["stateInfo"] not in UNREACHABLE_GATES for m in gated_here)
        status = "conditional" if reachable else "gated"
    elif any(m["loc"] == "weaponRoar" for m in ungated):
        status = "roarR2Only"
    elif ungated:
        status = "elsewhere"
    elif codes:
        status = "notInvoked"
    elif any(not is_ammo_var(v) for _b, v, _j in params.producers.get(atk, ())):
        status = "rowForOtherWeapon"      # 有行产出它，但都属于别的武器的 var
    elif atk == anchor or params.producers.get(atk) or params.atk_refs.get(atk):
        status = "noJudge"                # 锚点 / 只有弹药 var 的行 / 只被子弹等列引用：不经这把武器的 BehaviorParam_PC
    else:
        status = "unreferenced"
    gates = sorted({m["stateInfo"] for m in gated_here})
    # 「其它位置」只保留摘要，避免同一个 code 在几十个动作组 TAE 里刷屏
    kept = [m for m in matches if m["loc"] in ("skill", "weaponRoar")]
    other = sorted({(m["tae"], m["anim"]) for m in matches if m["loc"] in ("other", "weapon")})
    out = {"status": status, "codes": sorted(codes), "matches": kept}
    if other:
        out["elsewhere"] = [f"{t}_{a}" for t, a in other[:12]] + (["…"] if len(other) > 12 else [])
    seen_other_weapon = sorted({m["tae"] for m in matches if m["loc"] == "otherWeapon"})
    if seen_other_weapon:
        out["codeSeenInOtherWeaponTaes"] = seen_other_weapon[:12]
    if gates:
        out["gates"] = [state_name(g, params, enum) for g in gates]
    char_vars = sorted({v for m in matches for v in m.get("characterVariationId", [])})
    if char_vars:
        out["characterVariationIds"] = char_vars
    if sp_rows:
        out["spEffects"] = []
        for row, sps in sp_rows:
            for sid in sps:
                sp = params.sp_rows.get(sid, {})
                si = to_int(sp.get("stateInfo"))
                sources = params.sp_sources.get(sid, [])
                taes = sorted(idx.speffect_taes.get(to_int(sid), ()))
                rec = {"behaviorId": to_int(row["ID"]), "spEffectId": to_int(sid), "name": sp.get("Name", ""),
                       "stateInfo": state_name(si, params, enum) if si else 0,
                       "sources": sources[:8], "sourceCount": len(sources),
                       "taeEvents": [f"a{t}" for t in taes[:8]],
                       "hasSource": bool(sources or taes),
                       "viaThisSkill": bool(ctx) and (any(ctx.owns(s, sid) for s in sources) or to_int(sid) in ctx.tae_speffects)}
                out["spEffects"].append(rec)
        out["spEffectViaThisSkill"] = any(r["viaThisSkill"] for r in out["spEffects"])
        if status == "spEffect" and not any(r["hasSource"] for r in out["spEffects"]):
            # 触发它的 SpEffect 在全部参数表的 SpEffect 列与全部 TAE 的事件 66/67/302/331/401 里都没有来源：等于永远不会触发
            status = out["status"] = "spEffectNoSource"
    if status == "rowForOtherWeapon":
        out["producerRows"] = params.producer_rows(atk)
    elif status == "noJudge":
        ammo = sorted({v for _b, v, _j in params.producers.get(atk, ())})
        out["noJudgeReason"] = ((["SwordArtsParam.atkParamId 锚点"] if atk == anchor else [])
                                + ([f"只有弹药 var 的行（behaviorVariationId {ammo[:6]}）"] if ammo else [])
                                + params.atk_refs.get(atk, [])[:6])
    elif status == "unreferenced":
        out["unreferenced"] = "没有任何 BehaviorParam_PC 行、子弹、Magic 或其它参数列引用这段（全部参数表已扫）"
    return out


def skill_blocks(r: dict) -> set[int]:
    """这段在战技 TAE 的哪些 4xxxx 动画套（百位）里被无门控事件调用。3xxxx（改写普攻的战技的 R1/R2）不算套。"""
    lo, hi = SKILL_ANIM_RANGE
    return {m["anim"] // 100 for m in r.get("matches", [])
            if m["loc"] == "skill" and not m["stateInfo"] and lo <= m["anim"] <= hi}


def choose_block(alternatives: set[int], var: int, motions: set[int], wep_types: set[int],
                 var_specific_blocks: set[int], named_blocks: dict[int, set[int]] | None = None) -> tuple[int, str]:
    """互斥的几套里这把武器播哪一套：motion 专属套 → 只有一套配了本 var 的专属行 → 类别归组（有证据）→
    行名点名类别（named_blocks：wepType → 行名写着该类别名的套）→ 类别归组（推断）→ 默认套。"""
    for mc in sorted(motions):
        if DEFAULT_BLOCK + mc in alternatives:
            return DEFAULT_BLOCK + mc, f"motion（wepmotionCategory {mc} 的专属套 {DEFAULT_BLOCK + mc}）"
    if len(var_specific_blocks) == 1:
        b = next(iter(var_specific_blocks))
        return b, f"varRows（behaviorVariationId {var} 只为套 {b} 配了专属行）"
    for t in sorted(wep_types):
        b = CLASS_BLOCK_EVIDENCED.get(t)
        if b in alternatives:
            return b, f"classGroup（wepType {t} 按 103 回旋斩的手工归组走套 {b}）"
    for t in sorted(wep_types):
        named = (named_blocks or {}).get(t, set()) & alternatives
        if len(named) == 1:
            b = next(iter(named))
            return b, f'classGroupNamed（wepType {t}：套 {b} 的 AtkParam 行名点名 "({WEP_TYPE_NAME_EN[t]})"）'
    for t in sorted(wep_types):
        b = CLASS_BLOCK_INFERRED.get(t)
        if b in alternatives:
            return b, f"classGroupInferred（wepType {t} 按体型类比推断走套 {b}，未证实）"
    if DEFAULT_BLOCK in alternatives:
        return DEFAULT_BLOCK, "default（未能判定，取默认套 400）"
    return min(alternatives), "lowest（未能判定，取号最小的套）"


def resolve_exclusive_blocks(res: dict[str, dict], var: int, motions: set[int], wep_types: set[int],
                             row_var: dict[int, int], atk_rows: dict[str, dict] | None = None) -> dict | None:
    """同一 variant × var 里 invoked 的段若分散在没有交集的几套 4xxxx 动画里，选一套，其余记 exclusiveBlock。
    row_var：behaviorId → 行的 variationId（判断哪套配了本 var 的专属行）；atk_rows：AtkParam_Pc 行（看行名是否
    点名武器类别，可省略）。返回说明（没有互斥时返回 None）。"""
    blocks_of = {a: skill_blocks(r) for a, r in res.items() if r["status"] == "invoked"}
    blocks_of = {a: b for a, b in blocks_of.items() if b}
    if len(blocks_of) < 2 or set.intersection(*blocks_of.values()):
        return None
    all_blocks = sorted(set().union(*blocks_of.values()))
    alternatives = {b: sorted((a for a, bs in blocks_of.items() if b in bs), key=int) for b in all_blocks}
    var_specific = set()
    family = {var, var // 100 * 100} - {0}     # 专属行 = 本 var 或它取整到百位的族 var 上的行（三级回退）
    if family:
        for b, atks in alternatives.items():
            for a in atks:
                if any(m["anim"] // 100 == b and row_var.get(m["behaviorId"]) in family for m in res[a]["matches"]
                       if m["loc"] == "skill"):
                    var_specific.add(b)
    named: dict[int, set[int]] = defaultdict(set)   # wepType → 行名写着 "(该类别)" 的套
    for t in wep_types:
        en = WEP_TYPE_NAME_EN.get(t)
        if not en or not atk_rows:
            continue
        for b, atks in alternatives.items():
            if any(f"({en})" in (atk_rows.get(a) or {}).get("Name", "") for a in atks):
                named[t].add(b)
    chosen, reason = choose_block(set(all_blocks), var, motions, wep_types, var_specific, named)
    excluded = []
    for a, bs in blocks_of.items():
        if chosen not in bs:
            r = res[a]
            r["status"] = "exclusiveBlock"
            r["blocks"] = sorted(bs)
            r["chosenBlock"] = chosen
            r["blockChoice"] = reason
            excluded.append(a)
    codes_by_block = {b: sorted({m["code"] for a in atks for m in res[a]["matches"]
                                 if m["loc"] == "skill" and m["anim"] // 100 == b}) for b, atks in alternatives.items()}
    return {"chosenBlock": chosen, "blockChoice": reason,
            "alternatives": {str(b): {"atkIds": [int(a) for a in atks], "codes": codes_by_block[b]} for b, atks in alternatives.items()},
            "excludedAtkIds": sorted(int(a) for a in excluded)}


def best_status(statuses: list[str]) -> str:
    return min(statuses, key=STATUS_ORDER.index) if statuses else "noJudge"


def hit_damaging(hit: dict) -> bool:
    """数据集的一段算不算「对敌伤害」：noDamage（六项全 0，或只打自己 / 队友的 selfOrAllyOnly 行）不算。"""
    if hit.get("noDamage") or hit.get("selfOrAllyOnly"):
        return False
    return any(v for v in (hit.get("motion") or {}).values()) or any(v for v in (hit.get("flat") or {}).values())


def fp_branch(anim: int) -> str:
    """规律 8：战技 TAE 动画属于哪一侧——4xxxx 个位 0–4 = "fp"（带 FP 版），5–9 = "noFp"（无 FP 版，
    = 带 FP 版动画号 + 5）；3xxxx 等不分 FP 的动画 = "neutral"。"""
    lo, hi = SKILL_ANIM_RANGE
    if lo <= anim <= hi:
        return "noFp" if anim % 10 >= NO_FP_UNIT_MIN else "fp"
    return "neutral"


def fp_evidence(r: dict, roar_skill: bool, chosen_block: int | None = None) -> dict[str, set[int]]:
    """一段（match_events / check 的结果）被哪些分支的动画调用：{"fp" / "noFp" / "neutral": {动画号}}。
    只看让它留下的依据：战技 TAE 里的事件（187 这种玩家拿不到的门控不算）与吼叫类战技的 R2 动画（不分 FP，记
    neutral）；有互斥动画套时只看这把武器播的那一套（chosen_block）。没有动画依据（spEffect / noJudge）时返回空。"""
    out: dict[str, set[int]] = defaultdict(set)
    lo, hi = SKILL_ANIM_RANGE
    for m in r.get("matches", []):
        if m["stateInfo"] in UNREACHABLE_GATES:
            continue
        if m["loc"] == "skill":
            if chosen_block is not None and lo <= m["anim"] <= hi and m["anim"] // 100 != chosen_block:
                continue
            out[fp_branch(m["anim"])].add(m["anim"])
        elif m["loc"] == "weaponRoar" and roar_skill:
            out["neutral"].add(m["anim"])
    return dict(out)


# ------------------------------------------------------------------ 供 generate_skills.py 调用

# 逐武器核实后「留在 variants[].atkIds 里」的状态：动画确实会打出（invoked / weaponTae），由本战技的 SpEffect
# 触发（spEffect），带玩家拿得到的 stateInfo 门控（conditional），或无法经 TAE 判定、不敢删（noJudge：弓系锚点 / 弹药行）。
# 其余状态（exclusiveBlock 与 NEVER_STATUSES）都表示这把武器用这个战技时打不出这段。
# 「打得出」≠「打敌人」：spEffect 里祈祷一击的回血子弹 1202100（Heal Self，selfTarget=1）/ 1202110（Heal Others，
# friendlyTarget=1）opposeTarget=0，只打自己 / 队友。它们留在 atkIds（动画确实会触发），由 generate_skills.py 在
# hits 上标 noDamage + selfOrAllyOnly（按 AtkParam 的 opposeTarget / selfTarget / friendlyTarget 判），三端都不把
# noDamage 段计入构成，本脚本的 hit_damaging() 也不算。
KEEP_STATUSES = ("invoked", "weaponTae", "spEffect", "conditional", "noJudge")
# 判断「战技动画匹配得上」：至少一段在某把武器上有事件调用（B 报告 skills[].matched 的同一口径）
MATCHED_STATUSES = ("invoked", "weaponTae")


def load_enum(path: Path | None) -> dict[int, str]:
    enum: dict[int, str] = {}
    if path and path.exists():
        with open(path, encoding="utf-8") as fp:
            for o in json.load(fp).get("Options", []):
                enum[to_int(o["Key"])] = o["Names"][0]["Text"]
    return enum


class TaeVerifier:
    """把本脚本的判定打包成可复用的对象：generate_skills.py 生成数据集时逐 (战技, 武器) 调用 check()，
    本脚本的 main() 也用它（两边同一套 TAE 索引、参数、三级回退与互斥动画套规则）。"""

    def __init__(self, invoked_path: Path, params_dir: Path, enum_path: Path | None = DEFAULT_ENUM):
        with open(invoked_path, encoding="utf-8") as fp:
            invoked = json.load(fp)
        self.invoked_meta = invoked.get("meta", {})
        self.idx = TaeIndex(invoked)
        self.params = Params(params_dir)
        self.enum = load_enum(enum_path)
        self.row_var = {to_int(r["ID"]): to_int(r.get("variationId")) for r in self.params.row_by_id.values()}

    def wep(self, wid) -> dict | None:
        return self.params.weapons.get(str(wid))

    def weapon_taes(self, wids) -> set[int]:
        """武器动作组 TAE：a(wepmotionCategory)，另加 spAtkcategory>0 时的专属组。"""
        out = set()
        for wid in wids:
            w = self.wep(wid)
            if w:
                out.add(to_int(w["wepmotionCategory"]))
                if to_int(w["spAtkcategory"]) > 0:
                    out.add(to_int(w["spAtkcategory"]))
        return out

    def skill_context(self, skill_id: int, hit_atks) -> dict:
        """战技层的上下文：战技 TAE、是否吼叫类、锚点、spEffect 来源归属（SkillCtx）。"""
        params, idx = self.params, self.idx
        sa = params.sword_arts.get(str(skill_id))
        s_type = to_int(sa["swordArtsType"]) if sa else -1
        skill_tae = SKILL_TAE_BASE + s_type if sa and s_type != 255 else None
        tae_ok = skill_tae is not None and skill_tae in idx.anims
        hits = {str(a) for a in hit_atks}
        bullets: set[str] = set()
        for a in hits:
            for base, v_, judge in params.producers.get(a, ()):
                bullets.update(params.row_bullets(params.rows[(base, v_, judge)]))
        tae_id = skill_tae if tae_ok else None
        return {"skillId": skill_id, "swordArtsType": s_type, "skillTae": skill_tae, "taeFound": tae_ok,
                "taeId": tae_id, "roar": skill_id in ROAR_R2_SKILLS,
                "anchor": sa.get("atkParamId") if sa else None,
                "ctx": SkillCtx(hits, bullets, set(self.idx.by_tae_speffects.get(tae_id, ())) if tae_id else set())}

    def check(self, sctx: dict, atks, var: int, weapon_ids, wep_types: set[int]) -> tuple[dict[str, dict], dict | None]:
        """这组武器（同一 behaviorVariationId）用这个战技时，atks 里每段的判定（含互斥动画套的选套）。
        返回 ({atkId: match_events 结果（status 已按互斥套改写）}, 互斥套说明或 None)。"""
        taes = self.weapon_taes(weapon_ids)
        results = {a: match_events(a, self.params.codes_for_atk(a, var), sctx["taeId"], taes, self.idx, self.params,
                                   self.enum, sctx["roar"], self.params.speffect_rows_for_atk(a), sctx["ctx"],
                                   sctx["anchor"])
                   for a in (str(x) for x in atks)}
        motions = {to_int(self.wep(w)["wepmotionCategory"]) for w in weapon_ids if self.wep(w)}
        info = resolve_exclusive_blocks(results, var, motions, wep_types, self.row_var, self.params.atk)
        return results, info


def reason_text(r: dict) -> str:
    """一段判定的中文说明（generate_skills.py 的 diagnostics 用）。"""
    st = r["status"]
    if st == "exclusiveBlock":
        return f"只在另一套动画 {r.get('blocks')} 里（这把武器播 {r.get('chosenBlock')}：{r.get('blockChoice')}）"
    if st == "gated":
        return "只有 stateInfo 门控的事件调用它：" + "；".join(r.get("gates") or [])
    if st == "roarR2Only":
        anims = sorted({f'{m["tae"]}_{m["anim"]}' for m in r.get("matches", [])})
        return "只在武器动作组的吼叫 R2 动画里（" + ", ".join(anims[:4]) + "），本战技不是吼叫类"
    if st == "elsewhere":
        return "通用行只在别的动画里被调用（" + ", ".join((r.get("elsewhere") or [])[:4]) + "）"
    if st == "notInvoked":
        return f"judgeId {r.get('codes')} 在战技 / 武器 TAE 里都没有事件"
    if st == "spEffectNoSource":
        sps = r.get("spEffects") or []
        return "由 SpEffect " + "、".join(str(x["spEffectId"]) for x in sps) + " 触发，但它在全部参数表与 TAE 里都没有来源"
    if st == "rowForOtherWeapon":
        rows = r.get("producerRows") or []
        return "产出它的 BehaviorParam_PC 行只属于别的 behaviorVariationId（" + ", ".join(
            f"{x['behaviorId']} var {x['variationId']}" for x in rows[:3]) + "）"
    if st == "unreferenced":
        return "没有任何参数行引用它"
    return st


# ------------------------------------------------------------------ 主流程

def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--invoked", type=Path, default=DEFAULT_INVOKED)
    ap.add_argument("--params", type=Path, default=DEFAULT_PARAMS)
    ap.add_argument("--skills", type=Path, default=DEFAULT_SKILLS)
    ap.add_argument("--enum", type=Path, default=DEFAULT_ENUM, help="Smithbox Paramdex NR 的 SP_EFFECT_TYPE.json（可选）")
    ap.add_argument("--out", type=Path, default=DEFAULT_OUT)
    args = ap.parse_args()

    with open(args.skills, encoding="utf-8") as fp:
        ds = json.load(fp)
    verifier = TaeVerifier(args.invoked, args.params, args.enum)
    invoked = {"meta": verifier.invoked_meta}
    idx, params, enum = verifier.idx, verifier.params, verifier.enum
    weapon_ids = {str(w["id"]) for w in ds["weapons"]}
    weapon_name = {str(w["id"]): w["nameZh"] for w in ds["weapons"]}
    # v3 起数据集的 weaponIds 已含局内战技池（可达 EquipParamCustomWeapon 行的 SwordArtsTableParam 池），
    # 不再用 EquipParamWeapon.swordArtsTableId 的抽取表补武器（那一列指向不被 custom 行引用的 xx10 池，
    # generate_skills.py v3 已论证它不是来源）；只对 v2 及以前的数据集补。
    use_table = to_int(ds.get("schemaVersion")) < 3
    wep = verifier.wep
    weapon_taes = verifier.weapon_taes

    def group_by_var(wids: list[int]) -> dict[int, list[int]]:
        out: dict[int, list[int]] = defaultdict(list)
        for w in wids:
            r = wep(w)
            out[to_int(r["behaviorVariationId"]) if r else 0].append(w)
        return dict(sorted(out.items())) or {0: []}

    # 抽取表：skill → 会抽到它的武器
    table_weapons: dict[str, set[str]] = defaultdict(set)
    for wid in weapon_ids if use_table else ():
        w = wep(wid)
        if not w:
            continue
        for sid in params.tables.get(w["swordArtsTableId"], ()):
            table_weapons[sid].add(wid)

    # 规律自检：战技 TAE 里的 code 能否都在 BehaviorParam_PC 找到行
    rule_check = Counter()
    for tae in idx.by_tae_code:
        if SKILL_TAE_BASE <= tae < 900:
            for code in idx.by_tae_code[tae]:
                base = NORMAL_BASE if code < 1000 else (code // 1000) * NORMAL_BASE
                judge = code if code < 1000 else code % 1000
                found = any(k[0] == base and k[2] == judge for k in params.rows)
                rule_check["resolved" if found else "unresolved"] += 1

    # 吼叫类战技的证据：战技 TAE 事件 331 上的 buff
    roar_evidence: dict[str, dict] = {}
    for sid, zh in ROAR_R2_SKILLS.items():
        sa = params.sword_arts.get(str(sid))
        tae = SKILL_TAE_BASE + to_int(sa["swordArtsType"]) if sa else None
        sps = sorted(idx.by_tae_weapon_skill_speffects.get(tae, ())) if tae else []
        roar_evidence[str(sid)] = {
            "nameZh": zh, "tae": f"a{tae}" if tae else None,
            "taeSpEffects": [{"id": s, "name": params.sp_rows.get(str(s), {}).get("Name", "")} for s in sps],
            "evidenceAvailable": idx.has_speffect_events,
        }

    report_skills = []
    stats = Counter()
    never: list[dict] = []
    conditional: list[dict] = []
    speffect_hits: list[dict] = []
    exclusive: list[dict] = []
    ds_wep_type = {str(w["id"]): to_int(w.get("wepType")) for w in ds["weapons"]}
    row_var = verifier.row_var

    def hit_record(skill: dict, v: dict | None, var: int, ws: list[int], a: str, h: dict, r: dict) -> dict:
        rec = {"skillId": skill["id"], "skillZh": skill["nameZh"], "skillEn": skill["nameEn"],
               "variant": v["index"] if v else None, "via": v["via"] if v else "noVariant",
               "ctx": v.get("ctx") if v else None, "behaviorVariationId": var,
               "weaponCount": len(ws), "weaponIds": ws,
               "weaponSample": [f'{w} {weapon_name.get(str(w), "")}' for w in ws[:3]],
               "atkId": int(a), "label": h.get("label"), "hitCtx": h.get("ctx"),
               "noVariant": bool(h.get("noVariant")), "status": r["status"], "codes": r.get("codes")}
        if h.get("notInvoked"):
            # v3 数据集已按 TAE 核实把它移出 variants（hits[].notInvoked），所以这里落在「不属于任何 variant」
            rec["notInvokedInDataset"] = h.get("notInvokedReason") or True
        for k in ("gates", "elsewhere", "codeSeenInOtherWeaponTaes", "spEffects", "spEffectViaThisSkill",
                  "blocks", "chosenBlock", "blockChoice", "producerRows", "noJudgeReason", "unreferenced"):
            if r.get(k) is not None:
                rec[k] = r[k]
        if r["status"] == "roarR2Only":
            rec["roarAnims"] = sorted({f'{m["tae"]}_{m["anim"]}' for m in r["matches"]})
        return rec

    def collect(skill: dict, v: dict | None, var: int, ws: list[int], a: str, h: dict, r: dict) -> None:
        """带伤害且打不出 / 有条件 / SpEffect 触发的段进对应清单（按 variant × behaviorVariationId）。"""
        if not hit_damaging(h):
            return
        st = r["status"]
        if st in NEVER_STATUSES:
            never.append(hit_record(skill, v, var, ws, a, h, r))
        elif st == "conditional":
            conditional.append(hit_record(skill, v, var, ws, a, h, r))
        elif st == "spEffect":
            speffect_hits.append(hit_record(skill, v, var, ws, a, h, r))
        elif st == "exclusiveBlock":
            exclusive.append(hit_record(skill, v, var, ws, a, h, r))

    def account(v: dict, h: dict, st: str) -> None:
        """variant × behaviorVariationId × 段 的计数：dataset（数据集 variant，via=behavior 或 ctx）/ table（抽取表补）/
        none（没挂武器）。"""
        via = {"table": "table", "none": "none"}.get(v["via"], "dataset")
        stats[f"variantHits.{st}"] += 1
        stats[f"{via}VariantHits.{st}"] += 1
        if hit_damaging(h):
            stats[f"variantHitsDamaging.{st}"] += 1
            stats[f"{via}VariantHitsDamaging.{st}"] += 1

    for skill in ds["skills"]:
        sid = str(skill["id"])
        sa = params.sword_arts.get(sid)
        s_type = to_int(sa["swordArtsType"]) if sa else -1
        skill_tae = SKILL_TAE_BASE + s_type if sa and s_type != 255 else None
        tae_ok = skill_tae is not None and skill_tae in idx.anims
        roar_skill = skill["id"] in ROAR_R2_SKILLS
        entry: dict = {
            "id": skill["id"], "nameZh": skill["nameZh"], "nameEn": skill["nameEn"],
            "swordArtsType": s_type, "tae": f"a{skill_tae}" if skill_tae else None,
            "taeFound": tae_ok, "roarR2Skill": roar_skill,
            "taeAnims": sorted(idx.anims.get(skill_tae, ())) if tae_ok else [],
            "weaponsInDataset": len(skill["weaponIds"]),
            "weaponsFromTable": sorted(int(w) for w in table_weapons.get(sid, ()) if int(w) not in skill["weaponIds"]),
        }
        stats["skills"] += 1
        if tae_ok:
            stats["skillsWithTae"] += 1
        hits = {str(h["atkId"]): h for h in skill["hits"]}
        if not hits:
            entry["variants"] = []
            report_skills.append(entry)
            continue
        stats["skillsWithHits"] += 1
        skill_tae_id = skill_tae if tae_ok else None
        anchor = sa.get("atkParamId") if sa else None
        # spEffect 来源归属：本战技的段、产出这些段的行的子弹链、战技 TAE 上的 SpEffect
        skill_bullets: set[str] = set()
        for a in hits:
            for base, v_, judge in params.producers.get(a, ()):
                skill_bullets.update(params.row_bullets(params.rows[(base, v_, judge)]))
        ctx = SkillCtx(set(hits), skill_bullets, set(idx.by_tae_speffects.get(skill_tae_id, ())) if skill_tae_id else set())

        # 变体：数据集的 variants + 抽取表补上的武器（按 behaviorVariationId 分组）
        variants: list[dict] = []
        for i, v in enumerate(skill.get("variants", [])):
            variants.append({"index": i, "via": v.get("via"), "ctx": v.get("ctx"), "weaponIds": v["weaponIds"],
                             "atkIds": [str(a) for a in v["atkIds"]]})
        covered = {w for v in variants for w in v["weaponIds"]}
        extra = [w for w in entry["weaponsFromTable"] if w not in covered]
        by_var: dict[int, list[int]] = defaultdict(list)
        for w in extra:
            r = wep(w)
            if r:
                by_var[to_int(r["behaviorVariationId"])].append(w)
        for var, ws in sorted(by_var.items()):
            # 与 generate_skills.py 的 resolve_by_behavior 同法：这把武器在该战技上实际会解到哪些段。
            # 几套互斥的 4xxxx 动画（回旋斩等）在这里仍是并集，靠下面的 resolve_exclusive_blocks 按套拆开。
            atks = set()
            for a in hits:
                if params.codes_for_atk(a, var) or params.speffect_rows_for_atk(a):
                    atks.add(a)
            variants.append({"index": len(variants), "via": "table", "ctx": None, "weaponIds": sorted(ws),
                             "atkIds": sorted(atks, key=int), "behaviorVariationId": var})
        if not variants:
            variants.append({"index": 0, "via": "none", "ctx": None, "weaponIds": [], "atkIds": sorted(hits, key=int)})

        atk_status: dict[str, list[str]] = defaultdict(list)
        variant_summary: Counter = Counter()
        out_variants = []
        for v in variants:
            vars_ = group_by_var(v["weaponIds"])
            # 武器动作组 TAE 按 behaviorVariationId 分别取（同一 variant 里大锤 a35 与肢解菜刀 a32 不能互相借证据）
            taes_by_var = {var: weapon_taes(ws) for var, ws in vars_.items()}
            results: dict[str, dict[int, dict]] = {}
            for a in v["atkIds"]:
                sp_rows = params.speffect_rows_for_atk(a)
                results[a] = {var: match_events(a, params.codes_for_atk(a, var), skill_tae_id, taes_by_var[var], idx,
                                                params, enum, roar_skill, sp_rows, ctx, anchor) for var in vars_}
            # 互斥动画套：同一 var 里 invoked 的段若分散在没有交集的几套 4xxxx 动画里，只保留这把武器播的那套
            block_info: dict[int, dict] = {}
            for var, ws in vars_.items():
                motions = {to_int(wep(w)["wepmotionCategory"]) for w in ws if wep(w)}
                wtypes = {ds_wep_type.get(str(w), 0) for w in ws}
                info = resolve_exclusive_blocks({a: results[a][var] for a in results}, var, motions, wtypes, row_var,
                                                params.atk)
                if info:
                    block_info[var] = info
            atks_out = []
            for a in v["atkIds"]:
                h = hits.get(a, {})
                per_var = results[a]
                statuses = [r["status"] for r in per_var.values()]
                best = best_status(statuses)
                best_var = next(var for var, r in per_var.items() if r["status"] == best)
                rec = {"atkId": int(a), "label": h.get("label"), "ctx": h.get("ctx"),
                       "damaging": hit_damaging(h), "status": best, "behaviorVariationId": best_var}
                rec.update({k: v_ for k, v_ in per_var[best_var].items() if k != "status"})
                if len(set(statuses)) > 1:
                    rec["statusByVariation"] = {str(var): r["status"] for var, r in per_var.items()}
                atks_out.append(rec)
                atk_status[a].append(best)
                for var, r in per_var.items():
                    variant_summary[r["status"]] += 1
                    account(v, h, r["status"])
                    collect(skill, v, var, vars_[var], a, h, r)
            out_variants.append({**{k: v_ for k, v_ in v.items() if k != "atkIds"},
                                 "weaponCount": len(v["weaponIds"]),
                                 "weaponSample": [f'{w} {weapon_name.get(str(w), "")}' for w in v["weaponIds"][:3]],
                                 "behaviorVariationIds": list(vars_),
                                 "weaponTaes": {str(var): sorted(f"a{t}" for t in taes) for var, taes in taes_by_var.items()},
                                 "exclusiveBlocks": {str(var): info for var, info in block_info.items()},
                                 "hits": atks_out})
        entry["variants"] = out_variants

        # 不属于任何 variant 的段（noVariant）：按 var 0 与所有武器的 var 试一遍（武器 TAE 同样按 var 取）
        var_weapons: dict[int, list[int]] = defaultdict(list)
        for v in variants:
            for w in v["weaponIds"]:
                if wep(w):
                    var_weapons[to_int(wep(w)["behaviorVariationId"])].append(w)
        all_vars = sorted(set(var_weapons) | {0})
        taes_all = {var: weapon_taes(ws) for var, ws in var_weapons.items()}
        unused = []
        for a, h in hits.items():
            if a in atk_status:
                continue
            sp_rows = params.speffect_rows_for_atk(a)
            per_var = {var: match_events(a, params.codes_for_atk(a, var), skill_tae_id, taes_all.get(var, set()), idx,
                                         params, enum, roar_skill, sp_rows, ctx, anchor) for var in all_vars}
            best = best_status([r["status"] for r in per_var.values()])
            best_var = next(var for var, r in per_var.items() if r["status"] == best)
            rec = {"atkId": int(a), "label": h.get("label"), "ctx": h.get("ctx"), "damaging": hit_damaging(h),
                   "status": best, "behaviorVariationId": best_var}
            rec.update({k: v_ for k, v_ in per_var[best_var].items() if k != "status"})
            if len({r["status"] for r in per_var.values()}) > 1:
                rec["statusByVariation"] = {str(var): r["status"] for var, r in per_var.items()}
            unused.append(rec)
            atk_status[a].append(best)
            stats[f"noVariantHits.{best}"] += 1
            # 这些段没有武器归属，只按最好的 var 记一条（via=noVariant）
            collect(skill, None, best_var, [], a, h, per_var[best_var])
        entry["hitsOutsideVariants"] = unused

        # 战技层汇总（每段取所有 variant 里最好的状态，只用于概览；逐武器的结论看 variants / neverInvokedDamaging）
        skill_level = {a: best_status(s) for a, s in atk_status.items()}
        entry["hitSummary"] = dict(Counter(skill_level.values()))
        entry["variantHitSummary"] = dict(variant_summary)
        entry["matched"] = any(s in ("invoked", "weaponTae") for s in skill_level.values())
        if entry["matched"]:
            stats["skillsMatched"] += 1
        for a, s in skill_level.items():
            stats["hits"] += 1
            stats[f"hits.{s}"] += 1
            if hit_damaging(hits[a]):
                stats["hitsDamaging"] += 1
                stats[f"hitsDamaging.{s}"] += 1
        report_skills.append(entry)

    # ------------------------------------------------------------ 法术
    spell_stats = Counter()
    spells_out = []
    for spell in ds["spells"]:
        m = params.magic.get(str(spell["id"]))
        if not m:
            continue
        tae = MAGIC_TAE_BASE + to_int(m["refType"])
        slots_used: set[int] = set()
        for aid, slots in idx.cast_slots.get(tae, {}).items():
            slots_used |= slots
        slot_atks: dict[int, set[str]] = {}
        bullet_slots: set[int] = set()
        trigger_sps: list[dict] = []   # 施法动画用到的 SpEffect 槽里带 stateInfo 的（触发型：反击 / 吸收成功…）
        for n in range(1, 11):
            ref, cat = m.get(f"refId{n}", "-1"), to_int(m.get(f"refCategory{n}"))
            if ref in ("-1", "0", ""):
                continue
            if cat == 0 and ref in params.atk:
                slot_atks[n - 1] = {ref}
            elif cat == 1 and ref in params.bullets:
                slot_atks[n - 1] = set(params.bullet_atks(ref))
                bullet_slots.add(n - 1)
            elif cat == 2 and ref in params.sp_rows and (n - 1) in slots_used:
                si = to_int(params.sp_rows[ref].get("stateInfo"))
                if si:
                    trigger_sps.append({"slot": n - 1, "spEffectId": to_int(ref), "name": params.sp_rows[ref].get("Name", ""),
                                        "stateInfo": state_name(si, params, enum)})
        rec = {"id": spell["id"], "nameZh": spell["nameZh"], "tae": f"a{tae}", "taeFound": tae in idx.anims,
               "castSlotsUsed": sorted(slots_used), "slotsPopulated": sorted(slot_atks), "hits": []}
        if trigger_sps:
            rec["triggerSpEffects"] = trigger_sps
        spell_stats["spells"] += 1
        if tae in idx.anims:
            spell_stats["spellsWithTae"] += 1
        anchor = m.get("atkParamId", "-1")
        for h in spell["hits"]:
            a = str(h["atkId"])
            slots = sorted(n for n, atks in slot_atks.items() if a in atks)
            hrec: dict = {"atkId": h["atkId"], "slots": slots, "damaging": hit_damaging(h)}
            if slots:
                if any(n in slots_used for n in slots):
                    st = "invoked"
                elif trigger_sps and any(n in bullet_slots for n in slots):
                    st = "spEffectDerived"
                    hrec["derivedFrom"] = trigger_sps
                else:
                    st = "slotUnused"
            elif a == anchor:
                st = "anchorOnly"
            else:
                sp_rows = params.speffect_rows_for_atk(a)
                if sp_rows:
                    hrec["spEffects"] = [{"behaviorId": to_int(row["ID"]), "spEffectId": to_int(s),
                                          "name": params.sp_rows.get(s, {}).get("Name", ""),
                                          "sources": params.sp_sources.get(s, [])[:6],
                                          "taeEvents": [f"a{t}" for t in sorted(idx.speffect_taes.get(to_int(s), ()))[:6]]}
                                         for row, sps in sp_rows for s in sps]
                    st = "spEffect" if any(r["sources"] or r["taeEvents"] for r in hrec["spEffects"]) else "spEffectNoSource"
                else:
                    st = "noSlot"
            hrec["status"] = st
            rec["hits"].append(hrec)
            spell_stats["hits"] += 1
            spell_stats[f"hits.{st}"] += 1
            if hit_damaging(h):
                spell_stats[f"hitsDamaging.{st}"] += 1
        spells_out.append(rec)

    # ------------------------------------------------------------ 狩猎大蛇专项
    serpent = next((s for s in report_skills if s["id"] == 1188), None)
    serpent_answer = None
    if serpent and serpent["taeFound"]:
        tae = int(serpent["tae"][1:])
        anims = {}
        for aid in serpent["taeAnims"]:
            evs = [e for e in idx.resolve(tae, aid) if is_hit_event(e)]
            anims[str(aid)] = {"file": idx.files.get((tae, aid)), "events": [
                {"type": HIT_EVENT_TYPES[e["type"]], "judgeId": e["judgeId"], "behaviorId": 300000000 + 1703 * 1000 + e["judgeId"] % 1000
                 if e["judgeId"] >= 3000 else None, "start": e["start"], "end": e["end"], "attackIndex": e.get("attackIndex"),
                 "stateInfo": e.get("stateInfo", 0), "dirType": e.get("dirType")} for e in evs]}
        gate187 = Counter()
        for (t, aid), evs in idx.events.items():
            for e in evs:
                if e.get("stateInfo") == 187:
                    gate187[f"a{t}"] += 1
        serpent_answer = {"tae": serpent["tae"], "anims": anims,
                          "byHit": {str(r["atkId"]): {"status": r["status"], "gates": r.get("gates"),
                                                       "matches": [(m["tae"], m["anim"], m["start"], m["end"], m["stateInfo"]) for m in r["matches"]]}
                                    for v in serpent["variants"] for r in v["hits"]},
                          "stateInfo187EventsByTae": dict(sorted(gate187.items())),
                          "stateInfo187Explanation": (
                              "stateInfo 187 是本体《艾尔登法环》打拉卡德（神皮吞食者大蛇）时大蛇狩猎矛「光波延长命中」的门控："
                              "L2 的 3900/3901 与大枪动作组 a37 / 大蛇狩猎矛专属组 a207 普通攻击上的 5000 系 judge 都挂着它。"
                              "本作全部参数里只有 SpEffect 1908 带 stateInfo 187，而 1908 只被 BuddyStoneParam 16000114"
                              "（m16 的 NPC 召唤石，eliminateTargetEntityId 16005800）的 dopingSpEffectId 引用，玩家拿不到，"
                              "所以本作玩家永远打不出光波（EMEVD 未查）。")}

    meta = {
        "generatedAt": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "dataset": args.skills.name, "invoked": str(args.invoked.name),
        "invokedStats": invoked["meta"].get("stats"),
        "rules": {
            "skillTae": "a(600 + SwordArtsParam.swordArtsType)，动画号 4xxxx；swordArtsType 255（无战技）没有 TAE",
            "judgeCode": "TAE judgeId = judge（base 1 亿）或 base/1 亿*1000 + judge；BehaviorParam_PC.ID = base + behaviorVariationId*1000 + judge，"
                         "专属行优先、缺则 variationId=0；base 不是 1 亿整数倍的行（242 行）不走 TAE：其中 162 行被 SpEffectParam.behaviorId 引用、"
                         "由 SpEffect 触发，其余 80 行没有任何引用、数据集也没有段落在它们上",
            "characterVariation": "base 400000000 的行（风暴管束者 4001xxxxx…）按行自己的 variationId 解、不按武器：这些 variationId 与武器类别的 var 重合，"
                                  "「按渡夜者选行」是从 Paramdex 的 AtkParam 行名（[AoW - Duchess] Storm Ruler）推断的，两种读法下 80 段都被 a860 调用；"
                                  "匹配记录带 characterVariationId",
            "stateInfoGate": "事件 stateInfo≠0 时需要角色带对应 SP_EFFECT_TYPE 的 SpEffect 才触发",
            "gate187": "stateInfo 187：本体打拉卡德的光波延长命中门控。本作只有 SpEffect 1908 带它，1908 只被 BuddyStoneParam 16000114"
                       "（m16 NPC 召唤石 doping）引用，玩家拿不到；它只残留在 a37（大枪动作组）/ a207（大蛇狩猎矛专属组）/ a788（狩猎大蛇）"
                       "与 a26 / a31 / a271 的少数事件上。EMEVD 未查",
            "roarR2": "野蛮咆哮 / 战吼 / 灭洛斯的狂嚎（ROAR_R2_SKILLS）改写 R2：段在武器 a(wepmotionCategory) 的 30600–30635 / 32600–32635 动画里"
                      "（judgeId 3950–3969 野蛮咆哮 / 灭洛斯，3980–3997 战吼）；只有这三个战技的段允许 weaponTae，别的战技落在这些动画上算 roarR2Only",
            "spEffect": "被 SpEffectParam.behaviorId 引用的 BehaviorParam_PC 行由 SpEffect 触发而非动画事件：状态 spEffect，附 SpEffect 名、"
                        "stateInfo 与来源（全部参数表里名字含 spEffect / doping 的列，以及哪个 TAE 的事件 66/67/302/331/401 上的它），"
                        "viaThisSkill = 来源出自本战技的段 / 子弹链 / 战技 TAE；一个来源都没有时记 spEffectNoSource（永远不会触发）",
            "exclusiveBlock": "战技 TAE 的 4xxxx 动画按百位分套：400 默认、402 大型武器、403 长柄、4XX（XX ≥ 20）= wepmotionCategory XX 专属（424 双头剑、"
                              "442 拳、445 大弓、447/448 盾）；一把武器只播一套（HKS GetSwordArtsDiffCategory 选，字节码读不出）。同一 variant × var 里"
                              "invoked 的段若分散在没有交集的几套里，按 motion 专属套 → 只有一套配了本 var 专属行 → 类别归组（103 手工归组有证据；"
                              "某套的 AtkParam 行名点名类别如 \"(Greatsword)\" 也算证据，记 classGroupNamed；其余"
                              "大剑 / 特大剑 / 大斧 / 大锤 / 特大武器 → 402、矛 / 大矛 → 403 是体型类比推断）→ 默认套 400 选一套，其余记 exclusiveBlock",
            "unreferenced": "codes 为空时再分三种：产出这段的 BehaviorParam_PC 行存在但都属于别的 behaviorVariationId（rowForOtherWeapon）；"
                            "是 SwordArtsParam.atkParamId 锚点或被 Bullet.atkId_Bullet 等列引用、走箭矢 / 子弹（noJudge）；"
                            "全部参数表里没有任何列引用（unreferenced）。前两种记入永远打不出",
            "magicTae": "a(400 + Magic.refType)，事件 64 的 refSlot 选 Magic.refId(1..10)",
            "magicSpEffect": "refCategory 2 槽里带 stateInfo 的 SpEffect 是触发型（因果性原理 1676000，stateInfo 170），它触发时发射的是同一 Magic 里"
                             "施法动画不用的子弹槽（spEffectDerived）；行名点名但不在任何槽里、且由 SpEffect.behaviorId 触发的段记 spEffect",
            "imports": "ImportOtherAnim 动画跟随导入源（TAE*1000000+动画号）",
        },
        "roarSkills": roar_evidence,
        "ruleSelfCheck": {"skillTaeCodesResolvedToBehaviorRows": dict(rule_check)},
        "statusMeaning": {
            "invoked": "战技 TAE 里有不带门控的事件调用它",
            "weaponTae": "吼叫类战技（野蛮咆哮 / 战吼 / 灭洛斯的狂嚎）的 R2 段：在该武器动作组 TAE 的 30600–30635 / 32600–32635 动画里被调用",
            "spEffect": "不由动画事件调用，而由 SpEffectParam.behaviorId 触发（spEffects 列出 SpEffect 与来源，viaThisSkill 表示来源出自本战技）",
            "conditional": "只有带 stateInfo 门控的事件调用它，且该状态玩家拿得到（gates 列出条件）",
            "exclusiveBlock": "在战技 TAE 里被调用，但只在这把武器不播的另一套 4xxxx 动画里（blocks / chosenBlock / blockChoice）——不与 invoked 相加",
            "roarR2Only": "本战技不是吼叫类，但这段只出现在武器动作组的吼叫 R2 动画里——不属于本战技，本战技永远打不出",
            "gated": "只有带 stateInfo 187 门控的事件调用它，而 187 玩家拿不到——永远打不出",
            "elsewhere": "通用行（variationId=0）只在别的战技 / 动画里被用到，本战技在这把武器上的动画不调用它（elsewhere 列出位置）",
            "notInvoked": "任何相关 TAE 都没有事件调用它（专属行若在别的武器 TAE 出现同号 code，列在 codeSeenInOtherWeaponTaes，但那会解到别的行）",
            "spEffectNoSource": "由 SpEffectParam.behaviorId 触发，但该 SpEffect 在全部参数表的 SpEffect 列与全部 TAE 的 SpEffect 事件里都没有来源——永远不会触发",
            "rowForOtherWeapon": "产出这段的 BehaviorParam_PC 行只属于别的 behaviorVariationId（producerRows 列出那些行与武器），这把武器解不到——永远打不出",
            "unreferenced": "没有任何 BehaviorParam_PC 行、子弹、Magic 或其它参数列引用这段（全部参数表已扫）——永远打不出",
            "noJudge": "不经 BehaviorParam_PC：是 SwordArtsParam.atkParamId 锚点，或只被箭矢 / 子弹的 atkId_Bullet 等列引用（noJudgeReason），无法经 TAE 判定",
        },
        "scannedTables": params.scanned_tables,
    }
    by_status = lambda prefix: {s: stats[f"{prefix}.{s}"] for s in STATUS_ORDER if stats[f"{prefix}.{s}"]}  # noqa: E731

    def bucket(items: list[dict]) -> dict:
        return {"variantHits": len(items),
                "byVia": dict(Counter(i["via"] for i in items)),
                "byStatus": dict(Counter(i["status"] for i in items)),
                "uniqueSkillHits": len({(i["skillId"], i["atkId"]) for i in items}),
                "skills": len({i["skillId"] for i in items}),
                "weaponHits": sum(i["weaponCount"] for i in items)}

    summary = {
        "skills": stats["skills"], "skillsWithTae": stats["skillsWithTae"], "skillsWithHits": stats["skillsWithHits"],
        "skillsMatched": stats["skillsMatched"],
        "hits": stats["hits"], "hitsByStatus": by_status("hits"),
        "hitsDamaging": stats["hitsDamaging"], "hitsDamagingByStatus": by_status("hitsDamaging"),
        "variantHitsByStatus": by_status("variantHits"),
        "variantHitsDamagingByStatus": by_status("variantHitsDamaging"),
        "datasetVariantHitsDamagingByStatus": by_status("datasetVariantHitsDamaging"),
        "tableVariantHitsDamagingByStatus": by_status("tableVariantHitsDamaging"),
        "noWeaponVariantHitsDamagingByStatus": by_status("noneVariantHitsDamaging"),
        "noVariantHitsByStatus": by_status("noVariantHits"),
        "neverInvokedDamaging": bucket(never),
        "conditionalDamaging": bucket(conditional),
        "spEffectDamaging": {**bucket(speffect_hits),
                             "viaThisSkill": sum(1 for i in speffect_hits if i.get("spEffectViaThisSkill"))},
        "exclusiveBlockDamaging": {**bucket(exclusive),
                                   "byBlockChoice": dict(Counter(i["blockChoice"].split("（")[0] for i in exclusive))},
        "spells": dict(spell_stats),
    }
    report = {"meta": meta, "summary": summary, "neverInvokedDamaging": never, "conditionalDamaging": conditional,
              "spEffectDamaging": speffect_hits, "exclusiveBlockDamaging": exclusive,
              "serpentHunter": serpent_answer, "skills": report_skills, "spells": spells_out}
    args.out.mkdir(parents=True, exist_ok=True)
    with open(args.out / "hit-invocation-report.json", "w", encoding="utf-8") as fp:
        json.dump(report, fp, ensure_ascii=False, indent=1)
    with open(args.out / "hit-invocation-report.md", "w", encoding="utf-8") as fp:
        fp.write(render_md(report))
    print(json.dumps(summary, ensure_ascii=False, indent=1))
    return 0


# ------------------------------------------------------------------ Markdown

def _variant_label(n: dict) -> str:
    via = n["via"]
    if via == "noVariant":
        if n.get("notInvokedInDataset"):
            return f"已被数据集 TAE 核实移出 variants（notInvoked={n['notInvokedInDataset']}）"
        return "不属于任何 variant"
    parts = [via]
    if n.get("ctx"):
        parts.append(n["ctx"])
    parts.append(f"var {n['behaviorVariationId']}")
    return " / ".join(parts)


def _hit_cell(n: dict) -> str:
    extra = ""
    if n.get("gates"):
        extra = " gate=" + "; ".join(n["gates"])
    elif n.get("roarAnims"):
        extra = " roarAnims=" + ",".join(n["roarAnims"][:4])
    elif n.get("elsewhere"):
        extra = " at=" + ",".join(n["elsewhere"][:4])
    elif n.get("producerRows"):
        extra = " rows=" + "; ".join(f"{r['behaviorId']}(var {r['variationId']}: {', '.join(r['weapons'][:2]) or '无武器'}"
                                     f"{', 战技 ' + str(r['weaponSwordArtsParamIds']) if r['weaponSwordArtsParamIds'] else ''})"
                                     for r in n["producerRows"][:3])
    elif n.get("spEffects"):
        extra = " spEffect=" + "; ".join(f"{r['spEffectId']} {r['name']}（来源 {r.get('sourceCount', 0)} 个，TAE {r.get('taeEvents') or '无'}）"
                                         for r in n["spEffects"][:2])
    return (f"{n['atkId']} {n['status']}{' [' + n['hitCtx'] + ']' if n.get('hitCtx') else ''}"
            f"{' ' + n['label'] if n.get('label') else ''}{' (noVariant)' if n.get('noVariant') else ''}{extra}")


def render_md(rep: dict) -> str:
    s, m = rep["summary"], rep["meta"]
    L: list[str] = []
    L.append("# 战技命中段 × TAE 动画事件 核实报告\n")
    L.append(f"生成时间 {m['generatedAt']}；数据集 {m['dataset']}；TAE 事件 {m['invoked']}（{m['invokedStats']}）。\n")
    L.append("## 规律\n")
    for k, v in m["rules"].items():
        L.append(f"- **{k}**：{v}")
    L.append(f"- 规律自检：战技 TAE（a600–a899）里的 judgeId 能在 BehaviorParam_PC 找到行的比例 {m['ruleSelfCheck']}\n")
    L.append("## 统计\n")
    L.append(f"- 战技 {s['skills']} 个，其中有 TAE 的 {s['skillsWithTae']} 个、有命中段的 {s['skillsWithHits']} 个、至少一段被动画调用的 {s['skillsMatched']} 个。")
    L.append(f"- 命中段按战技取「所有武器里最好的状态」（只用于概览）{s['hits']} 段：{s['hitsByStatus']}；其中带伤害的 {s['hitsDamaging']} 段：{s['hitsDamagingByStatus']}")
    L.append(f"- 按 variant × behaviorVariationId 展开（每把武器实际解到的行，逐武器结论以此为准）：{s['variantHitsByStatus']}；带伤害 {s['variantHitsDamagingByStatus']}")
    L.append(f"  - 数据集 variant（via=behavior）带伤害：{s['datasetVariantHitsDamagingByStatus']}")
    L.append(f"  - 抽取表补的 variant（via=table）带伤害：{s['tableVariantHitsDamagingByStatus']}")
    L.append(f"  - 没挂武器、也没有抽取表武器的战技（via=none，按 var 0）带伤害：{s['noWeaponVariantHitsDamagingByStatus']}")
    L.append(f"- 不属于任何 variant 的段（每段取所有 var 里最好的）：{s['noVariantHitsByStatus']}")
    n = s["neverInvokedDamaging"]
    L.append(f"- **从未被玩家动画调用的带伤害段：{n['variantHits']} 个 variant 段**（去重后 {n['uniqueSkillHits']} 个战技段，涉及 {n['skills']} 个战技、{n['weaponHits']} 个武器×段）；"
             f"按状态 {n['byStatus']}；按来源 {n['byVia']}（见下表；roarR2Only=非吼叫战技却只在吼叫 R2 动画里、gated=只有 187 门控、elsewhere=通用行只被别的战技 / 武器用、notInvoked=有行但没有任何事件、"
             f"spEffectNoSource=触发它的 SpEffect 没有来源、rowForOtherWeapon=行只属于别的武器、unreferenced=没有任何引用）")
    x = s["exclusiveBlockDamaging"]
    L.append(f"- **互斥动画套里的带伤害段：{x['variantHits']} 个 variant 段**（去重 {x['uniqueSkillHits']}，涉及 {x['skills']} 个战技、{x['weaponHits']} 个武器×段；"
             f"选套依据 {x['byBlockChoice']}）——这些段在战技 TAE 里被调用，但只在这把武器不播的另一套 4xxxx 动画里，**不能与同一武器的 invoked 段相加**（见「互斥动画套」表）")
    c = s["conditionalDamaging"]
    L.append(f"- 有条件才打出的带伤害段：{c['variantHits']} 个 variant 段（去重 {c['uniqueSkillHits']}，见「有条件触发」表）")
    e = s["spEffectDamaging"]
    L.append(f"- 由 SpEffect 触发（不经动画事件）的带伤害段：{e['variantHits']} 个 variant 段（去重 {e['uniqueSkillHits']}，其中来源出自本战技的 {e['viaThisSkill']}，见「SpEffect 触发」表）")
    L.append(f"- 法术：{s['spells']}\n")
    L.append("status 含义：" + "；".join(f"{k}={v}" for k, v in m["statusMeaning"].items()) + "\n")

    L.append("## 吼叫类 R2 战技（允许 weaponTae 的战技）\n")
    L.append("| 战技 | TAE | 事件 331 上的 buff（证据） |")
    L.append("|---|---|---|")
    for sid, r in m["roarSkills"].items():
        sps = ", ".join(f"{x['id']} {x['name']}".strip() for x in r["taeSpEffects"]) or ("（invoked.json 没有 SpEffect 事件，请重跑 extract_tae.py --parse-only）" if not r["evidenceAvailable"] else "—")
        L.append(f"| {sid} {r['nameZh']} | {r['tae']} | {sps} |")
    L.append("")

    sh = rep.get("serpentHunter")
    if sh:
        L.append("## 狩猎大蛇（1188，Serpent-Hunter 17030000，behaviorVariationId 1703）\n")
        L.append(f"战技 TAE {sh['tae']}，动画与命中事件：\n")
        L.append("| 动画 | 动作文件 | 事件 | judgeId → BehaviorParam_PC | 时间 | attackIndex | stateInfo |")
        L.append("|---|---|---|---|---|---|---|")
        for aid, a in sh["anims"].items():
            for e in a["events"]:
                L.append(f"| {aid} | {a['file']} | {e['type']} | {e['judgeId']} → {e['behaviorId']} | {e['start']}–{e['end']} | {e['attackIndex']} | {e['stateInfo']} |")
        L.append("\n各段判定：\n")
        L.append("| atkId | status | 门控 | 事件（TAE, 动画, 起, 止, stateInfo） |")
        L.append("|---|---|---|---|")
        for a, r in sh["byHit"].items():
            L.append(f"| {a} | {r['status']} | {r.get('gates') or ''} | {r['matches']} |")
        L.append(f"\n{sh['stateInfo187Explanation']}\n")
        L.append(f"stateInfo 187 事件按 TAE 计数（原始事件，不含 ImportOtherAnim 展开）：{sh['stateInfo187EventsByTae']}\n")

    L.append("## 从未被调用的带伤害段（按战技 × variant × behaviorVariationId）\n")
    L.append("同一段在不同武器上状态可能不同（例：野蛮咆哮 300000957「1H R2 #2-2 Charged」在锤 / var 0 武器上由 a33_30610 打出，"
             "在大锤 / 大斧 / 矛上却没有任何动画调用），所以按 variant 列，不按战技取最好状态。\n")
    L.append("| 战技 | variant（via / ctx / var） | 武器数（示例） | 段（atkId status [ctx] label{gate/roarAnims/at}） |")
    L.append("|---|---|---|---|")
    grouped: dict[tuple, list[dict]] = defaultdict(list)
    for x in rep["neverInvokedDamaging"]:
        grouped[(x["skillId"], x["skillZh"], x["skillEn"], x["variant"], x["via"], x.get("ctx"), x["behaviorVariationId"])].append(x)
    for key, items in grouped.items():
        sid, zh, en = key[:3]
        first = items[0]
        L.append(f"| {sid} {zh}／{en} | {_variant_label(first)} | {first['weaponCount']}（{'; '.join(first['weaponSample'])}） | {'<br>'.join(_hit_cell(x) for x in items)} |")
    L.append("")

    L.append("### 按战技段去重\n")
    L.append("| 战技 | atkId | label | 状态（按 variant） | 受影响 variant 数 / 武器数 |")
    L.append("|---|---|---|---|---|")
    per_hit: dict[tuple, list[dict]] = defaultdict(list)
    for x in rep["neverInvokedDamaging"]:
        per_hit[(x["skillId"], x["skillZh"], x["skillEn"], x["atkId"])].append(x)
    for (sid, zh, en, atk), items in per_hit.items():
        st = Counter(x["status"] for x in items)
        L.append(f"| {sid} {zh}／{en} | {atk} | {items[0].get('label') or ''} | {dict(st)} | {len(items)} / {sum(x['weaponCount'] for x in items)} |")
    L.append("")

    L.append("## 互斥动画套（同一 variant × var 里 invoked 的段分散在没有交集的几套 4xxxx 动画里）\n")
    L.append("战技 TAE 的 4xxxx 动画按百位分套（400 默认 / 402 大型武器 / 403 长柄 / 4XX = wepmotionCategory XX 专属），一把武器只播一套。"
             "选套规则：motion（TAE 里有这把武器 wepmotionCategory 的专属套）→ varRows（只有一套配了本 var 的专属行）→ classGroup（103 回旋斩手工归组：直剑 / 曲剑默认、"
             "大曲剑 402、戟 / 镰 403）→ classGroupNamed（某套的 AtkParam 行名点名这把武器的类别，如 204 鲜血斩击 402 套的 \"Slash (Greatsword)\"）"
             "→ classGroupInferred（大剑 / 特大剑 / 大斧 / 大锤 / 特大武器 402、矛 / 大矛 403，体型类比，未证实）→ default（400）。"
             "HKS 的 GetSwordArtsDiffCategory 才是真正的选套者，字节码读不出。\n")
    L.append("| 战技 | variant（via / ctx / var） | 武器数（示例） | 选中的套（依据） | 各套的段 | 记 exclusiveBlock 的段 |")
    L.append("|---|---|---|---|---|---|")
    for sk in rep["skills"]:
        for v in sk.get("variants", []):
            for var, info in (v.get("exclusiveBlocks") or {}).items():
                alts = "<br>".join(f"{b}: {a['atkIds']}" for b, a in info["alternatives"].items())
                label = " / ".join([v["via"]] + ([v["ctx"]] if v.get("ctx") else []) + [f"var {var}"])
                L.append(f"| {sk['id']} {sk['nameZh']}／{sk['nameEn']} | {label} | {v['weaponCount']}（{'; '.join(v['weaponSample'])}） | "
                         f"{info['chosenBlock']}（{info['blockChoice']}） | {alts} | {info['excludedAtkIds']} |")
    L.append("")

    L.append("## 有条件触发的带伤害段（stateInfo 门控，玩家可达）\n")
    L.append("| 战技 | variant | atkId | label | 条件 |")
    L.append("|---|---|---|---|---|")
    for x in rep["conditionalDamaging"]:
        L.append(f"| {x['skillId']} {x['skillZh']}／{x['skillEn']} | {_variant_label(x)} | {x['atkId']} | {x.get('label') or ''} | {'; '.join(x.get('gates') or [])} |")
    L.append("")

    L.append("## SpEffect 触发的带伤害段（不经动画事件）\n")
    L.append("| 战技 | variant | atkId | label | SpEffect（behaviorId ← SpEffect 名 [stateInfo]） | 来源 | 出自本战技 |")
    L.append("|---|---|---|---|---|---|---|")
    L.append("（触发它的 SpEffect 一个来源都没有的段记 spEffectNoSource，列在「从未被调用」表里，不在这里。）")
    seen_sp: set[tuple] = set()
    for x in rep["spEffectDamaging"]:
        key = (x["skillId"], x["atkId"], x["via"])
        if key in seen_sp:
            continue
        seen_sp.add(key)
        sps = "<br>".join(f"{r['behaviorId']} ← {r['spEffectId']} {r['name']}{' [' + str(r['stateInfo']) + ']' if r['stateInfo'] else ''}" for r in x.get("spEffects", []))
        srcs = "<br>".join(", ".join(r["sources"][:3] + [f"TAE {t}" for t in r.get("taeEvents", [])[:3]]) or "（没找到）" for r in x.get("spEffects", []))
        L.append(f"| {x['skillId']} {x['skillZh']}／{x['skillEn']} | {x['via']}{' / ' + x['ctx'] if x.get('ctx') else ''} | {x['atkId']} | {x.get('label') or ''} | {sps} | {srcs} | {'是' if x.get('spEffectViaThisSkill') else '否'} |")
    L.append("")

    L.append("## 各战技概览\n")
    L.append("| 战技 | swordArtsType | TAE | 动画数 | 武器（数据集/抽取表补） | 段判定（战技层最好状态） | 段判定（variant × var） |")
    L.append("|---|---|---|---|---|---|---|")
    for sk in rep["skills"]:
        L.append(f"| {sk['id']} {sk['nameZh']}／{sk['nameEn']}{'（吼叫类）' if sk.get('roarR2Skill') else ''} | {sk['swordArtsType']} | {sk['tae'] or '—'}{'' if sk['taeFound'] else '（缺）'} | {len(sk['taeAnims'])} | {sk['weaponsInDataset']}/{len(sk['weaponsFromTable'])} | {sk.get('hitSummary', {})} | {sk.get('variantHitSummary', {})} |")
    L.append("")

    L.append("## 法术\n")
    L.append("法术的子弹 / 攻击行由 Magic.refId1–10 决定，施法动画（TAE a(400+Magic.refType)）里的事件 64 只说「第几槽在什么时候发射」。"
             "所以法术段不需要像战技那样逐 judge 核实；只需确认段所在的 refId 槽被施法动画用到。"
             "refCategory 2 槽里带 stateInfo 的 SpEffect 是触发型（反击 / 吸收成功才发），它发射的子弹槽施法动画不用，记 spEffectDerived；"
             "行名点名但不在任何槽里、由 SpEffect.behaviorId 触发的段记 spEffect。")
    L.append("| 法术 | TAE | 动画用到的槽 | 有内容的槽 | 触发型 SpEffect | 段判定 |")
    L.append("|---|---|---|---|---|---|")
    for sp in rep["spells"]:
        c = Counter(h["status"] for h in sp["hits"])
        if not sp["taeFound"] or any(c.get(k) for k in ("slotUnused", "noSlot", "spEffect", "spEffectDerived")):
            trig = "; ".join(f"槽{t['slot']} {t['spEffectId']} {t['stateInfo']}" for t in sp.get("triggerSpEffects", []))
            L.append(f"| {sp['id']} {sp['nameZh']} | {sp['tae']}{'' if sp['taeFound'] else '（缺）'} | {sp['castSlotsUsed']} | {sp['slotsPopulated']} | {trig} | {dict(c)} |")
    L.append("\n（只列出 TAE 缺失或有段不是 invoked / anchorOnly 的法术；其余全部 invoked。）\n")
    return "\n".join(L)


if __name__ == "__main__":
    sys.exit(main())
