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
                         同一个 (base, judge) 上，variationId = 武器 behaviorVariationId 的行
                         优先，没有才落到 variationId = 0 的通用行——游戏就是这样挑动作的。
                         据此可以把「这把武器的这个战技实际会打出哪些 AtkParam 行」解出来，
                         写进 skills[].variants，武器侧再给一个 skillVariant 下标。

动作套（variants）为什么必须存在
------------------------------
  通用战技（战吼 / 野蛮咆哮 / 回旋斩 / 盲击…）在参数里同时存在「不分武器的默认套」
  （行名 "[AoW] War Cry"）和「每个动作组各一套」（"[AoW Axe] War Cry"），
  两者是同一招的互斥变体，不是可叠加的分段。而行名方括号里的动作组名
  （Small Weapon / Large Weapon / Polearm / Scythe）既不在 WEP_TYPE 枚举里，
  也**不能**映射成 wepType——实测 110 盲击里 behaviorVariationId=1400 的斧走
  "Small Weapon"、1406/1407 的斧走 "Large Weapon"，同一个 wepType=17 被拆进了两组。
  所以按 ctx 字符串过滤既会漏（斧 / 镰类取不到段）又会重（默认套与类别套一起算）。
  唯一正确的做法是 BehaviorParam_PC 实解，见 variants / skillVariant。

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
"""

import argparse
import csv
import json
import re
import sys
from collections import Counter, defaultdict
from datetime import datetime, timezone
from pathlib import Path

SCHEMA_VERSION = 2   # v2：新增 skills[].variants + weapons[].skillVariant（取代按 ctx 字符串过滤）
GAME_VERSION = "v1.03.5 + DLC1"
DATA_VERSION = "regulation 10350000"

HERE = Path(__file__).resolve().parent
DEFAULT_PARAMS = HERE / "raw" / "params"
DEFAULT_MSG = HERE / "raw" / "msg"
DEFAULT_OUT = HERE.parents[1] / "data" / "nightreign-skills-v1.03.5.json"

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
# 动作组名里有 4 个不是 WEP_TYPE 枚举名的别名。**它们不能映射成 wepType**：
# 实测 Wild Strikes（盲击）里，behaviorVariationId=1400 的斧走 "Small Weapon"，
# 而 1406/1407 的斧走 "Large Weapon"——同一个 wepType=17 被拆到了两组，
# 分组依据是单把武器的动作变体而不是武器类别。所以本脚本不输出「别名→wepType」映射，
# 每把武器到底用哪一套由 skills[].variants（BehaviorParam_PC 实解）给出。
CTX_ALIAS_ZH = {
    "small weapon": ("Small Weapon", "小型武器动作组"),
    "large weapon": ("Large Weapon", "大型武器动作组"),
    "polearm": ("Polearm", "长柄武器动作组"),
    # Paramdex 的 "Scythe" 指 WEP_TYPE 31 Reaper（镰）这个类别，
    # 不是武器 19000000「大镰刀 / Scythe」——必须先判类别再判武器名，否则会译错。
    "scythe": ("Scythe", "镰"),
}

# "[AoW - X]" 带连字符的形式全部是夜行者（角色）名，共 10 个，只用在 1200 风暴管束者上。
CHR_CTX_ZH = {"default": "默认角色"}

# BehaviorParam_PC 唯一无法区分的战技：103 回旋斩的 4 套动作（无 ctx / Large Weapon /
# Polearm / Twinblade）全部挂在 variationId=0 的 behaviorJudgeId 220-257 上，
# 任何武器解出来都是 4 套全中。这里按武器类别手工归组：
# 直剑 / 曲剑走无 ctx 的默认套，大曲剑走 Large Weapon，双头剑走 Twinblade，戟 / 镰走 Polearm。
# （依据：这 4 套正好对应引用该战技的 6 个类别所共用的 4 组动作。）
CTX_MANUAL_BY_SKILL: dict[int, dict[int, str]] = {
    103: {3: "", 9: "", 11: "Large Weapon", 14: "Twinblade", 29: "Polearm", 31: "Polearm"},
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
    if empty:
        hit["noDamage"] = True
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
    args = ap.parse_args()

    weapons_raw = read_param(args.params, "EquipParamWeapon")
    arts_raw = read_param(args.params, "SwordArtsParam")
    magic_raw = read_param(args.params, "Magic")
    atk_raw = read_param(args.params, "AtkParam_Pc")
    bullet_raw = read_param(args.params, "Bullet")
    behavior_raw = read_param(args.params, "BehaviorParam_PC")
    # 只用来校验 hits[].overrideAecId 是否真的存在（本表本身不收录，见 usage.本数据集的边界）
    aec_ids = frozenset(row["ID"] for row in read_param(args.params, "AttackElementCorrectParam"))

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
    for row in weapons_raw:
        wid = to_int(row["ID"])
        name_zh = wep_zh.get(wid)
        name_en = wep_en.get(wid)
        if not name_zh and not name_en:
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
            "weaponIds": sorted(skill_to_weapons.get(sid, [])),
            "_rowId": sid,
        })

    # ---------------------------------------------------------------- spells
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
    spells_with_hits, spells_missing = finalize(spells, spell_hits, spell_index)

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

    def resolve_by_behavior(var: int, judges: set[tuple[int, int]],
                            pool: set[str]) -> set[str]:
        out: set[str] = set()
        for base, judge in judges:
            row = (behavior_by_key.get((base, var, judge))
                   or behavior_by_key.get((base, 0, judge)))
            if not row:
                continue
            ref_type = to_int(row.get("refType", "0"))
            ref = row.get("refId", "-1")
            if ref_type == 0:
                if ref in pool:
                    out.add(ref)
            elif ref_type == 1 and ref in bullets_by_id:
                out |= bullet_atks(ref) & pool
        return out

    def choose_ctx(wep: dict, skill_id: int, pool_ctx: set[str]) -> str | None:
        """BehaviorParam_PC 分不出来时，按「武器名 → 同名基础武器 → 手工表 → 武器类别
        → 唯一的具名套 → 默认套」的顺序单选一套（**不取并集**）。"""
        for cand in (norm_key(wep["nameEn"]),):
            for ctx in pool_ctx:
                if ctx and norm_key(ctx) == cand:
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
    for skill in skills:
        if not skill["hits"] or not skill["weaponIds"]:
            continue
        pool = {str(h["atkId"]) for h in skill["hits"]}
        ctx_of = {str(h["atkId"]): h.get("ctx", "") for h in skill["hits"]}
        judges: set[tuple[int, int]] = set()
        for aid in pool:
            judges |= judges_by_atk.get(aid, set())
        groups: dict[frozenset[str], dict] = {}
        for wid in skill["weaponIds"]:
            wep = weapon_by_id.get(str(wid))
            if not wep:
                continue
            var = to_int(wep.get("_behaviorVariationId", "0"))
            atks = resolve_by_behavior(var, judges, pool) if judges else set()
            via = "behavior"
            named = {ctx_of[a] for a in atks if ctx_of[a]}
            if not atks or len(named) > 1:
                # 行为表分不出来（103 回旋斩的 4 套动作全挂在 variationId=0 上），
                # 或者这把武器压根没接上行为表：退回按 ctx 单选一套。
                candidates = atks or pool
                chosen = choose_ctx(wep, skill["id"], {ctx_of[a] for a in candidates})
                if chosen is None:
                    variant_gaps.append(
                        f'{wid} {wep["nameZh"]} ← {skill["id"]} {skill["nameZh"]}')
                    continue
                atks = {a for a in candidates if ctx_of[a] == chosen}
                via = "ctx"
            if not atks:
                variant_gaps.append(f'{wid} {wep["nameZh"]} ← {skill["id"]} {skill["nameZh"]}')
                continue
            key = frozenset(atks)
            group = groups.setdefault(key, {"weaponIds": [], "via": via})
            group["weaponIds"].append(wid)
            if via == "ctx":
                group["via"] = "ctx"
            variant_stats[via] += 1
        if not groups:
            continue
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
                weapon_by_id[str(wid)]["skillVariant"] = index
            variants.append(entry)
        skill["variants"] = variants

    for wep in weapons:
        wep.pop("_behaviorVariationId", None)

    # ---- 标记「本作没有任何武器会打出」的动作套 ------------------------------
    # 参数表里一个通用战技往往存着比本作实际用得到的更多的动作套
    # （例如 650 野蛮咆哮存了 '[AoW Straight Sword] Barbaric Roar' 一整套，
    # 但本作没有任何直剑把 650 配为战技）。这些段行名确实点名了本战技，数据没错，
    # 但按 usage 的选段算法（variants → atkIds）永远取不到。
    # 给它们打上 noVariant=true，方便页面/体积裁剪时区分，不改变既有字段语义。
    no_variant_hits = 0
    no_variant_damaging = 0
    for skill in skills:
        if not skill.get("variants"):
            continue
        covered: set[int] = set()
        for v in skill["variants"]:
            covered |= set(v["atkIds"])
        for hit in skill["hits"]:
            if hit["atkId"] not in covered:
                hit["noVariant"] = True
                no_variant_hits += 1
                if hit.get("motion") or hit.get("flat"):
                    no_variant_damaging += 1

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

    payload = {
        "schemaVersion": SCHEMA_VERSION,
        "gameVersion": GAME_VERSION,
        "dataVersion": DATA_VERSION,
        "generatedAt": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "sources": [
            {
                "name": "Elden Ring Nightreign regulation.bin",
                "detail": "本机 CrossOver Steam 安装，exe 1.3.3.0，容器版本号 10350000（1.03.5）；"
                          "由 dump_regulation.py 解出 raw/params/*.csv",
                "license": "游戏数据，版权归 FromSoftware / Bandai Namco",
                "use": "EquipParamWeapon / SwordArtsParam / Magic / AtkParam_Pc / Bullet / BehaviorParam_PC",
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
        },
        "coverage": {
            "note": "下面这些战技 / 法术在参数里找不到任何带数值的攻击行，"
                    "基本都是纯增益、闪避、格挡或只改弓箭的技能。",
            "skillsWithoutHits": skills_missing,
            "spellsWithoutHits": spells_missing,
            "hitsWithoutVariantNote":
                f"skills[].hits 是该战技在参数表里的**全部**动作套，"
                f"其中只有 variants 覆盖到的那些才会被本作的武器真正打出。"
                f"本版本有 {no_variant_hits} 段（其中 {no_variant_damaging} 段带 motion / flat）"
                f"不属于该战技的任何一个 variant，已逐段标 noVariant=true——"
                f"多为「参数表里存着某个武器类别的动作套，但本作没有任何该类别的武器配了这个战技」"
                f"（例 650 野蛮咆哮的 '[AoW Straight Sword] Barbaric Roar'、"
                f"108 鲜血征收的 '[AoW Dagger] Blood Tax'）。"
                f"这些段数据本身没错，但按 usage 的选段算法取不到；"
                f"想裁体积或只看「本作打得出的段」时按 noVariant 过滤即可。"
                f"注意：没有 variants 的战技（没有武器引用它）其 hits 不会被标记。",
        },
        "fieldNotes": {
            "省略即默认值": "为控制体积，所有等于默认值的字段都被省略。"
                        "motion / flat 里只保留非 0 的属性键，整体为空则该键不存在；"
                        "poise / poiseMv / stamina / staminaMv / isBullet / bulletIds / noFp / "
                        "noDamage / noVariant / addBaseAtk / overrideAecId 缺失即表示 0 / false / -1；"
                        "weapons.atkAttribute / atkAttribute2（及其 ...Zh）是例外，四项恒存在；"
                        "weapons.attackBase / weapons.correct 同理（缺失的键 = 0）；"
                        "weapons.skillVariant 缺失表示这把武器的战技没有命中段；"
                        "skills.variants 缺失表示没有武器引用这个战技（或它没有命中段）。",
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
                   "（如 \"Axe\"、\"Large Weapon\"）、chr=夜行者角色名（行名写作 \"[AoW - Duchess]\"）。"
                   "ctxZh 是中文，与 ctx 相同时省略。"
                   "**ctx 只用来显示，不要拿它做过滤**：同一招的默认套与各动作组套是互斥变体，"
                   "按「ctx == 武器名 or ctx == 类别名 or ctx 缺失」取并集会把两套一起算进去；"
                   "而且 Small Weapon / Large Weapon / Polearm 这些动作组名并不对应 wepType"
                   "（同为 Axe 的武器会按 behaviorVariationId 被拆进不同组）。"
                   "请改用 skills[].variants + weapons[].skillVariant。",
            "variants": "skills[].variants 给出「每把武器实际会打出哪些段」，由 BehaviorParam_PC "
                        "实解得到（ID = base + behaviorVariationId*1000 + behaviorJudgeId，"
                        "武器自己的 variationId 优先、缺则落到 variationId=0 的通用行）。"
                        "每个元素：atkIds=这一套包含的段（对应 hits[].atkId）、weaponIds=用这一套的武器、"
                        "ctx/ctxZh/ctxKind=这一套的动作归属（整套 ctx 不一致时省略）、"
                        "via=\"behavior\"（行为表实解）或 \"ctx\"（行为表分不出来，按 ctx 单选，"
                        "目前只有 103 回旋斩走这条）。一套里可能混入少量 ctx 缺失的共用段"
                        "（例如战吼在 Axe 上是 14 段 ctx=\"Axe\" + 2 段共用的 ctx 缺失段），这是正确的。",
            "skillVariant": "weapons[].skillVariant 是该武器在「它的 swordArtsParamId 指向的战技」的 "
                            "variants 数组里的下标。缺失表示这把武器的战技没有任何命中段。"
                            "取段就是 skills[i].variants[skillVariant].atkIds。",
            "noDamage": "该 AtkParam 行确实属于这个战技 / 法术（行名点名），但 motion / flat / poise / "
                        "poiseMv / stamina / staminaMv 六项全为 0，只用来挂异常状态或减益"
                        "（例如百智的世界、催眠火焰）。这类行**保留**并标 noDamage=true；"
                        "只有「行名没点名、纯靠子弹链或锚点顺带捞到的全零辅助行」"
                        "（Blank / No Target / Spell Helper 之类）才被剔除。"
                        "想只看有伤害的段时按 noDamage 过滤。",
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
                         "详见 coverage.hitsWithoutVariantNote。",
        },
        "usage": {
            "选段（必读）": "先确定这把武器用哪一套：v = skills[i].variants[weapon.skillVariant]，"
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
            "Small Weapon / Large Weapon / Polearm 这些动作组名不能映射成 wepType："
            "实测 110 盲击里 behaviorVariationId=1400 的斧走 Small Weapon、"
            "1406/1407 的斧走 Large Weapon，同一个 wepType=17 被拆进了两组。"
            "所以本数据集不提供「别名 → wepType」映射表，归属一律以 variants 为准。",
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
        ],
        "enums": {
            "wepType": {str(k): {"en": v[0], "zh": v[1]} for k, v in sorted(WEP_TYPE_ZH.items())},
            "rarity": {str(k): {"en": v[0], "zh": v[1]} for k, v in sorted(RARITY_ZH.items())},
            "atkAttribute": {str(k): {"en": v[0], "zh": v[1]} for k, v in sorted(ATK_ATTR_ZH.items())},
            "magicKind": {k: MAGIC_KIND_ZH[k] for k in ("sorcery", "incantation", "pyromancy")},
            "ctxKind": {
                "weapon": "具体武器名（ctx 与某把武器的 nameEn 相同）",
                "category": "武器类别名（WEP_TYPE 枚举名）或 Paramdex 的动作组别名",
                "chr": "夜行者角色名，行名写作 \"[AoW - Duchess]\" 这种带连字符的形式",
            },
            "ctxAlias": {
                en: {"zh": zh,
                     "note": "Paramdex 动作组别名，不在 WEP_TYPE 枚举里；"
                             "**没有对应的 wepType**，归属见 skills[].variants"}
                for en, zh in sorted(CTX_ALIAS_ZH.values())
                if norm_key(en) not in {norm_key(v[0]) for v in WEP_TYPE_ZH.values()}
            },
        },
        "weapons": weapons,
        "skills": skills,
        "spells": spells,
    }

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
    print(f"ctx 并集会翻倍的武器 {ctx_union_dup} 把；ctx 单选取不到段的武器 {ctx_pick_miss} 把"
          f"（两数已写进 usage.选段）")
    print(f"伤害类型需回武器上取（attribute=253/252）的段 {wep_attr_hits}")
    if aec_dangling:
        print(f"⚠ overrideAecId 悬空（已不写出）：{dict(aec_dangling)}")
    if foreign_drops:
        print(f"丢弃跨条目误配段 {len(foreign_drops)}：")
        for line in foreign_drops:
            print(f"  - {line}")
    if variant_gaps:
        print(f"⚠ 有战技命中但选不出动作套的武器 {len(variant_gaps)}：{variant_gaps[:10]}")
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


if __name__ == "__main__":
    main()
