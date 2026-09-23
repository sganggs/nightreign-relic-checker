#!/usr/bin/env python3
"""生成「角色属性」数据集（nightreign-heroes-v1.03.5.json）。

覆盖：
  * 10 个渡夜者 1–15 级的 8 项属性（生命力/集中力/耐力/力气/灵巧/智力/信仰/感应）、
    由属性算出的血量 / 专注值 / 精力 / 负重上限，以及 abilityReinforce 等辅助列；
  * 20 条「转职遗物」词条（AttachEffectParam 6640000–6647500）在每一级上的属性增减量，
    以及哪件遗物物品带着这条词条；
  * 利普拉（Libra）的 5 笔「扭曲的重生」交易——整套替换掉的属性表。

上游数据（均已导出在 raw/ 下，不入 git）
--------------------------------------
  raw/params/HeroParam.csv          10 个角色：characterNameId（→ 菜单文本）、heroStatusParamId
  raw/params/HeroStatusParam.csv    属性锚点表：
                                      10000+          角色基础表，每人 4 行（Level 1/2/12/15）
                                      210000–250003   利普拉交易后的整套替换表（5 套 × 4 行）
                                      300000–309101   转职遗物的增减量，每条只有 Level 1 / Level 12
  raw/params/AttachEffectParam.csv  6640000–6647500 = 20 条转职遗物词条（attachTextId、allow* 角色位）
  raw/params/AttachEffectTableParam.csv
                                    随机池 → 词条的权重表：chanceWeight（基础）/ chanceWeight_dlc
                                    （开 DLC 后的权重，-1 = 不覆盖）。学者/送葬者的 4 条在池 2200000
                                    里基础权重是 0、只有 DLC 权重 40 → statModifiers[].poolWeights
  raw/params/SpEffectParam.csv      7640000–7647500 → heroStatusModifier（增减量行）
                                    46260–46264 [Libra Deal] → heroStatusId（整套替换行）
  raw/params/CalcCorrectGraph.csv   100 HP-Vigor / 101 FP-Mind / 104 Stamina-Endurance /
                                    220 Equip Load-Endurance
  raw/msg/<lang>/menu_dlc01/CL_MenuText(.._dlc01).json        角色名（288050+）
  raw/msg/<lang>/item_dlc01/AttachEffectName(.._dlc01).json   词条名、8 项属性名（19700000+）
  raw/msg/<lang>/item_dlc01/AntiqueName(.._dlc01).json        遗物物品名
  raw/msg/<lang>/menu_dlc01/SpEffectName/SpEffectInfo         120700「扭曲的重生」
  raw/msg/<lang>/menu_dlc01/EventTextForTalk(.._dlc01).json   27570060–27570100 五个交易选项
  ../../data/nightreign-relics-v1.03.4.json                   遗物物品 ↔ 词条（可选，缺了就空 relicItems）
  HeroStatusParam / SpEffectParam / AttachEffectParam 的 Name 列 = 社区 Paramdex 行名

关键约定
--------
  * **中间等级 = 相邻锚点之间线性插值后向下取整。** 锚点只有 1 / 2 / 12 / 15 四级，
    中间 11 级全靠插值。已用追踪者 1–15 级全表（8 项属性 + 血量/专注值/精力）逐格验证，
    120 + 45 格全中（见 WYLDER_BASELINE 与 self_check）。
  * 派生值走 CalcCorrectGraph 分段线性插值，且**只吃一项属性**：
      血量 ← 生命力（graph 100）、专注值 ← 集中力（101）、精力 ← 耐力（104）、
      负重上限 ← 耐力（220）。100/101/104 的 adjPt 全为 1（纯直线），
      在本作用到的每一段里斜率都是整数（血量 20/点、专注值 5/点、精力 2/点），
      所以这三项在任何整数属性上都是整数；self_check 会枚举真正用到的段并断言这一点
      （守护者 12–15 级生命力 54–60 用到了 100 的 [50,75] 段，不止 [1,25]/[25,50] 两段）。
      220 的 adjPt_maxGrowVal2 = 1.1（[25,60] 段带指数），而且本作根本没有装备重量，
      这一列只是参数表遗留，见 caveats。
  * 转职遗物是 heroStatusModifier（在基础表上**加减**），利普拉是 heroStatusId（**整套替换**），
    两者是不同字段，机制上可以同时生效。
  * 转职遗物只有 L1 / L12 两个锚点：本脚本按「1–12 线性插值、向零取整；13–15 沿用 L12 值」
    实现，levels[].inferred 标出哪些级是推断的；两种取整会差 1 的等级另给 deltaFloorAlt。
    「13–15 沿用 L12」已由多组 15 级玩家实测确认（见 sources 里的 Fextralife 词条页与两个
    Steam 讨论帖）→ interpolation.modifierAnchorVerified = True；没实测的只剩 2–11 级
    → interpolation.modifierMidLevelsVerified = False。
  * 随机池的名字必须**按遗物 ID 配对**再排序：72 件遗物只有 12 个名字，中英文各自 sorted()
    会让 relicNamesZh[i] 与 relicNamesEn[i] 指向不同遗物（端正=Polished 却排在 Delicate 前）。

用法：
  cd macos/DataSources && python3 generate_heroes.py [--raw raw] [--out ../../data/nightreign-heroes-v1.03.5.json] [--pretty]
"""

from __future__ import annotations

import argparse
import csv
import json
import math
from datetime import datetime, timezone
from fractions import Fraction
from pathlib import Path
from typing import Any

SCHEMA_VERSION = 1
DATASET_ID = "heroes"
GAME_VERSION = "v1.03.5 + DLC1"
DATA_VERSION = "regulation 10350000"
PARAMDEX_REV = "f5969c060cea240476e9dd4d6a64eafa9dbafaab"

HERE = Path(__file__).resolve().parent
DEFAULT_RAW = HERE / "raw"
DEFAULT_OUT = HERE.parents[1] / "data" / "nightreign-heroes-v1.03.5.json"
RELICS_JSON = HERE.parents[1] / "data" / "nightreign-relics-v1.03.4.json"

LEVELS = list(range(1, 16))

# ---------------------------------------------------------------- 字段 / 文本表

# 输出键 → (HeroStatusParam 列名, AttachEffectName 里的属性名文本 ID)
ATTRIBUTES: list[tuple[str, str, int]] = [
    ("vigor", "statVigor", 19700000),
    ("mind", "statMind", 19700010),
    ("endurance", "statEndurance", 19700020),
    ("strength", "statStrength", 19700030),
    ("dexterity", "statDexterity", 19700040),
    ("intelligence", "statIntelligence", 19700050),
    ("faith", "statFaith", 19700060),
    ("arcane", "statArcane", 19700070),
]
ATTR_KEYS = [a[0] for a in ATTRIBUTES]

# 输出键 → (来源属性, CalcCorrectGraph 行, CL_MenuText 文本 ID 或 None, 中/英兜底名, 是否整数)
# integral=True 的三项在本作用到的区间里斜率是整数，结果必为整数（脚本会断言）；
# equipLoad 走带指数的 220，只能给浮点，保留 1 位小数。
DERIVED: list[tuple[str, str, int, int | None, str, str, bool]] = [
    ("hp", "vigor", 100, 10500, "血量", "HP", True),
    ("fp", "mind", 101, 10501, "专注值", "FP", True),
    ("stamina", "endurance", 104, 10502, "精力", "Stamina", True),
    ("equipLoad", "endurance", 220, None, "负重上限", "Equip Load", False),
]
DERIVED_KEYS = [d[0] for d in DERIVED]
INTEGRAL_DERIVED = [d[0] for d in DERIVED if d[6]]

# HeroStatusParam 里跟着等级走的辅助列（不是 8 项属性，也不是派生值）
EXTRA_COLUMNS: list[tuple[str, str, str, str, str]] = [
    ("abilityReinforce", "abilityReinforce", "int",
     "角色技能强化等级", "Ability Reinforcement"),
    ("revenantSpiritReinforce", "revenantSpiritReinforce", "int",
     "复仇者灵魂强化等级", "Revenant Spirit Reinforcement"),
    ("executorBeastReinforce", "executorBeastReinforce", "int",
     "执行者妖刀强化等级", "Executor Beast Reinforcement"),
    ("attackRate", "attackRate", "float",
     "攻击力倍率", "Attack Rate"),
]

HERO_KEYS = {
    1: "wylder", 2: "guardian", 3: "ironeye", 4: "duchess", 5: "raider",
    6: "revenant", 7: "recluse", 8: "executor", 9: "scholar", 10: "undertaker",
}
# AttachEffectParam 里的 allow<角色> 列 → heroId
ALLOW_COLUMNS = {
    "allowWylder": 1, "allowGuardian": 2, "allowIroneye": 3, "allowDuchess": 4,
    "allowRaider": 5, "allowRevenant": 6, "allowRecluse": 7, "allowExecutor": 8,
    "allowScholar": 9, "allowUndertaker": 10,
}

HERO_NAME_TEXT_BASE = 288050          # CL_MenuText，+0..+9 对应 HeroParam.ID 1..10
ATTACH_EFFECT_RANGE = (6640000, 6647500)
MODIFIER_ROW_RANGE = (300000, 309101)
LIBRA_SPEFFECTS = [46260, 46261, 46262, 46263, 46264]
LIBRA_EFFECT_TEXT_ID = 120700          # menu/SpEffectName + SpEffectInfo，5 笔交易共用
# SpEffectParam 行名尾段 → (输出 key, 对话选项 EventTextForTalk 文本 ID)
LIBRA_DEALS = {
    "Strength": ("strength", 27570060),
    "Dexterity": ("dexterity", 27570080),
    "Intelligence": ("intelligence", 27570070),
    "Faith": ("faith", 27570090),
    "Arcane": ("arcane", 27570100),
}
RELIC_COLORS = {0: ("红", "Red"), 1: ("蓝", "Blue"), 2: ("黄", "Yellow"),
                3: ("绿", "Green"), 4: ("白", "White")}

# ---------------------------------------------------------------- 回归基线

# 追踪者 1–15 级全表。8 项属性取自 Fextralife 的 Wylder 页，血量/专注值/精力取自
# eldenring.wiki.gg 的 Nightreign:Wylder 页。**唯一一处改动**：wiki.gg 把 12 级精力
# 写成 92（跟 11 级重复），按 CalcCorrectGraph 104（耐力 24 → 50 + 48×23/24）应为 96，
# 基线里用 96；其余 8×15 + 血量/专注值 15×2 格全部原样照抄。
# 列序：vigor, mind, endurance, strength, dexterity, intelligence, faith, arcane, hp, fp, stamina
WYLDER_BASELINE: dict[int, tuple[int, ...]] = {
    1:  (8,  4,  3,  5,  4,  2,  2,  10, 240,  65,  54),
    2:  (16, 6,  6,  18, 15, 4,  4,  10, 400,  75,  60),
    3:  (19, 7,  7,  20, 17, 4,  4,  10, 460,  80,  62),
    4:  (22, 8,  9,  23, 19, 5,  5,  10, 520,  85,  66),
    5:  (25, 9,  11, 25, 21, 6,  6,  10, 580,  90,  70),
    6:  (28, 10, 13, 28, 23, 7,  7,  10, 640,  95,  74),
    7:  (31, 11, 15, 31, 25, 8,  8,  10, 700,  100, 78),
    8:  (34, 12, 16, 33, 27, 8,  8,  10, 760,  105, 80),
    9:  (37, 13, 18, 36, 29, 9,  9,  10, 820,  110, 84),
    10: (40, 14, 20, 38, 31, 10, 10, 10, 880,  115, 88),
    11: (43, 15, 22, 41, 33, 11, 11, 10, 940,  120, 92),
    12: (46, 16, 24, 44, 35, 12, 12, 10, 1000, 125, 96),
    13: (48, 17, 25, 46, 36, 13, 13, 10, 1040, 130, 98),
    14: (50, 18, 26, 48, 38, 14, 14, 10, 1080, 135, 100),
    15: (52, 19, 27, 50, 40, 15, 15, 10, 1120, 140, 102),
}
# 第二条基线：执行者，8 项属性 + 血量/专注值/精力全部取自 eldenring.wiki.gg 的
# Nightreign:Executor 页，原样照抄，165 格与本脚本算出来的结果全中（含 12 级精力 96，
# 反过来佐证追踪者那一格的 92 是 wiki 笔误）。
EXECUTOR_BASELINE: dict[int, tuple[int, ...]] = {
    1:  (7,  2,  3,  5,  8,  2, 2, 28, 220,  55,  54),
    2:  (14, 3,  5,  9,  20, 3, 3, 28, 360,  60,  58),
    3:  (16, 3,  6,  10, 24, 3, 3, 28, 400,  60,  60),
    4:  (19, 4,  8,  11, 28, 3, 3, 28, 460,  65,  64),
    5:  (21, 4,  10, 12, 32, 4, 3, 28, 500,  65,  68),
    6:  (24, 5,  12, 14, 36, 4, 3, 28, 560,  70,  72),
    7:  (27, 6,  14, 15, 40, 5, 4, 28, 620,  75,  76),
    8:  (29, 6,  16, 16, 44, 5, 4, 28, 660,  75,  80),
    9:  (32, 7,  18, 18, 48, 5, 4, 28, 720,  80,  84),
    10: (34, 7,  20, 19, 52, 6, 4, 28, 760,  80,  88),
    11: (37, 8,  22, 20, 56, 6, 4, 28, 820,  85,  92),
    12: (40, 9,  24, 22, 60, 7, 5, 28, 880,  90,  96),
    13: (42, 9,  25, 23, 61, 7, 5, 28, 920,  90,  98),
    14: (44, 10, 26, 24, 62, 7, 5, 28, 960,  95,  100),
    15: (46, 11, 27, 25, 63, 8, 6, 28, 1000, 100, 102),
}

# 第三条基线：女爵，两个 wiki（Fextralife / eldenring.wiki.gg）给的表完全一致，
# 但**灵巧那一列整列比 1.03.5 参数低**（1–14 级差 1～3，15 级相同）。
# 原因是补丁 1.02.2「提高了女爵升级时的灵巧成长」，两个 wiki 的表还停在补丁之前。
# 这里把外部表原样留下并把已知差异写死，self_check 断言「差异恰好只有灵巧的 1–14 级」——
# 以后任何一格意外变动都会立刻报出来。
DUCHESS_EXTERNAL: dict[int, tuple[int, ...]] = {
    1:  (7,  6,  3,  2,  4,  4,  3,  11, 220, 75,  54),
    2:  (13, 9,  4,  4,  12, 8,  6,  11, 340, 90,  56),
    3:  (15, 10, 5,  4,  14, 10, 7,  11, 380, 95,  58),
    4:  (17, 12, 6,  5,  16, 13, 9,  11, 420, 105, 60),
    5:  (19, 13, 7,  5,  18, 16, 11, 11, 460, 110, 62),
    6:  (21, 15, 8,  6,  21, 19, 13, 11, 500, 120, 64),
    7:  (24, 16, 9,  6,  23, 22, 15, 11, 560, 125, 66),
    8:  (26, 18, 10, 7,  25, 24, 16, 11, 600, 135, 68),
    9:  (28, 19, 11, 7,  28, 27, 18, 11, 640, 140, 70),
    10: (30, 21, 12, 8,  30, 30, 20, 11, 680, 150, 72),
    11: (32, 22, 13, 8,  32, 33, 22, 11, 720, 155, 74),
    12: (35, 24, 14, 9,  35, 36, 24, 11, 780, 165, 76),
    13: (36, 25, 15, 9,  37, 38, 25, 11, 800, 170, 78),
    14: (37, 26, 16, 10, 39, 40, 26, 11, 820, 175, 80),
    15: (39, 27, 18, 11, 45, 42, 27, 11, 860, 180, 84),
}
DUCHESS_KNOWN_DIFFS = {("dexterity", level) for level in range(1, 15)}

# hero key → (基线表, 必须全中?, 说明)
EXTERNAL_BASELINES: dict[str, tuple[dict[int, tuple[int, ...]], bool, str, list[str]]] = {
    "wylder": (WYLDER_BASELINE, True,
               "8 项属性取自 Fextralife，血量/专注值/精力取自 eldenring.wiki.gg；"
               "唯一一处不一致是 12 级精力（该页写 92，与 11 级重复，按 CalcCorrectGraph 104 应为 96），"
               "基线里已按参数修正，其余 164 格全中。",
               ["https://eldenringnightreign.wiki.fextralife.com/Wylder",
                "https://eldenring.wiki.gg/wiki/Nightreign:Wylder"]),
    "executor": (EXECUTOR_BASELINE, True,
                 "全表取自 eldenring.wiki.gg，165 格全中（含 12 级精力 96）。",
                 ["https://eldenring.wiki.gg/wiki/Nightreign:Executor"]),
    "duchess": (DUCHESS_EXTERNAL, False,
                "两个 wiki 的表一致，但灵巧列 1–14 级整列偏低（差 1～3，15 级相同）——"
                "补丁 1.02.2「提高了女爵升级时的灵巧成长」，wiki 的表停在补丁之前。"
                "本数据集以 regulation 10350000 为准；其余 151 格全中。",
                ["https://eldenringnightreign.wiki.fextralife.com/Duchess",
                 "https://eldenring.wiki.gg/wiki/Nightreign:Duchess",
                 "https://www.bandainamcoent.com/news/elden-ring-nightreign-patch-notes-version-1-02-2"]),
}

BASELINE_COLUMNS = ATTR_KEYS + ["hp", "fp", "stamina"]

CAVEATS = [
    "中间等级不是参数表里的数字。HeroStatusParam 每个角色只有 4 行锚点（Level 1 / 2 / 12 / 15），"
    "2–11、13–14 这 11 级是**相邻锚点之间线性插值后向下取整（floor）**算出来的。"
    "该规则已用追踪者 1–15 级全表（8 项属性 120 格 + 血量/专注值/精力 45 格）逐格验证，"
    "见 sources 里的两个 wiki 与脚本内的 WYLDER_BASELINE 回归基线。levels[].isAnchor 标出哪几级是原始行。",
    "派生值各自只吃一项属性，不吃等级也不吃别的属性：血量 ← 生命力（CalcCorrectGraph 100）、"
    "专注值 ← 集中力（101）、精力 ← 耐力（104）、负重上限 ← 耐力（220）。"
    "100/101/104 的 adjPt_maxGrowVal 全是 1，也就是纯分段线性、没有指数。"
    "100（血量）与 101（专注值）四段斜率相同，整条曲线其实是一条直线："
    "血量 = 20 × 生命力 + 80、专注值 = 5 × 集中力 + 45，在 1–99 任何整数属性上都是整数。"
    "104（精力）前三段 [1,25] / [25,50] / [50,75] 斜率都是 2（精力 = 2 × 耐力 + 48），"
    "只有最后一段 [75,99] 是 25/12 ≈ 2.0833 不是整数——本作耐力最高 38"
    "（守护者 15 级；叠加转职遗物或利普拉交易之后也没有更高的），够不到那一段。"
    "所以血量/专注值/精力这三项必为整数，不存在取整争议。"
    "（补充：本数据集里用到了三段而不是两段——守护者 12–15 级生命力 54/56/58/60 落在 100 的 "
    "[50,75] 段，对应血量 1160/1200/1240/1280；该段斜率同样是 20，结论不受影响。"
    "self_check 会枚举数据集真正用到的每一段并断言斜率是整数。）",
    "equipLoad（负重上限）是**未经实测的遗留值**，页面建议默认不展示。两个原因："
    "①《黑夜君临》里装备没有重量、界面也没有负重条，社区资料明确说本作没有装备重量限制，"
    "CalcCorrectGraph 220 很可能只是从《艾尔登法环》继承下来没删的行；"
    "② 220 的 adjPt_maxGrowVal2 = 1.1，[25,60] 这一段不是直线，本脚本按 Elden Ring 通用的 "
    "CalcCorrectGraph 公式（ratio ** adjPt[下段下标]）实现，指数挂在哪一段没有第二处数据可交叉验证。",
    "转职遗物（statModifiers）在参数表里**只有 Level 1 与 Level 12 两个锚点**，13–15 级没有行。"
    "本数据集按「1–12 线性插值、13–15 沿用 L12 值」处理。**13–15 级沿用 L12 这一条已由玩家 15 级实测确认**："
    "① Fextralife 的词条页把 L12 行的数字直接当成词条效果写（[Revenant] 提升生命力、耐力，降低集中力 = "
    "「集中力 −11、生命力 +5、耐力 +5」，正是 305001 那一行）；"
    "② Steam 讨论区的 15 级实测逐条对上 L12 锚点——守护者 灵巧 31→50 / 力气 41→50 / 生命力 60→52（301001 的 "
    "+19/+9/−8）、无赖 感应 10→27 / 生命力 56→52（304101 的 +17/−4）、"
    "隐士 智力 51→41 与 灵巧 +20（306000）、隐士 集中力 30→17（306101 的 −13）；"
    "③ 另一帖的 15 级复仇者实测 血量 880 / 专注值 145 / 精力 100，与本数据集 L15 基础（生命力 35 / 集中力 31 / 耐力 21）"
    "叠加 305001 后（40 / 20 / 26）算出来的派生值完全一致。"
    "所以 interpolation.modifierAnchorVerified = true。"
    "**还没实测的只剩 2–11 级**的逐级数值与取整方向（见下一条），"
    "interpolation.modifierMidLevelsVerified = false，levels[].inferred = true 标出所有推断出来的等级"
    "（锚点级为 false）。顶层的 modifierVerified 是这两个细分字段的保守合取（恒等于 modifierMidLevelsVerified），"
    "页面请优先读细分字段，别拿它把整张遗物表标成「未验证」。",
    "转职遗物 delta 的取整方向存在一处无法区分的歧义：基础属性表全是非负数，"
    "floor 与「向零取整（trunc）」结果完全相同，验证不出游戏用的是哪一种；"
    "而转职遗物有负的增减量，两者会差 1。本数据集的 delta 按**向零取整**给出，"
    "在两种取整结果不同的等级额外给一个 deltaFloorAlt（只含结果不同的属性）供页面对照。",
    "利普拉的交易与转职遗物走的是 SpEffectParam 的两个不同字段：交易是 heroStatusId"
    "（把整套 HeroStatusParam 换成 210000/220000/230000/240000/250000 那 5 套），"
    "转职遗物是 heroStatusModifier（在当前基础表上加减）。字段不同意味着二者不互斥，"
    "机制上应该是「先用交易的表替换基础属性，再叠加遗物的增减量」。这是按参数结构推断的，未在游戏里实测。",
    "利普拉的 5 套替换表**不分角色**：210000–250003 是全局的 20 行，任何角色接受同一笔交易之后，"
    "属性表完全一样（连原角色的感应固定值也会被换掉）。所以 libraRespecs 里没有 heroId 字段。",
    "5 笔交易在 SpEffectParam 里共用同一个文本 ID（120700「扭曲的重生」/ Twisted Reincarnation），"
    "参数里没有逐笔的名字。libraRespecs[].nameZh/nameEn 是脚本按「效果名（属性名）」拼出来的，"
    "真正能在游戏里看到的逐笔文案是 dealLineZh/dealLineEn（EventTextForTalk 27570060–27570100 的对话选项）。",
    "abilityReinforce / revenantSpiritReinforce / executorBeastReinforce 三列在所有角色、所有锚点上"
    "都恰好等于「等级 − 1」（0 / 1 / 11 / 14），插值后每一级也正好是等级 − 1；attackRate 恒为 1。"
    "三列在本数据集里原样写出，页面一般不需要展示。",
    "外部 wiki 的表不一定跟得上补丁。逐格比对过三张表："
    "追踪者（Fextralife + eldenring.wiki.gg）与执行者（eldenring.wiki.gg）165 格全中；"
    "女爵的**灵巧那一列 1–14 级整列比本数据集低 1～3**，因为补丁 1.02.2「提高了女爵升级时的灵巧成长」，"
    "而两个 wiki 的女爵表还停在补丁之前（15 级两边都是 45，所以只看首尾看不出来）。"
    "本数据集一律以 regulation 10350000 的参数为准，比对结果原样写在 crossChecks 里。",
    "statModifiers[].relicItems 只收「词条写死在槽位上」的遗物物品（每条词条各对应一件"
    "「辽阔的◯◯情景 / Grand ◯◯ Scene」）。这些词条同时出现在随机池 2100000 / 2200000 里，"
    "理论上也能从吃这两个池的遗物上掉出来，池号记在 rollablePoolIds，不逐件展开。"
    "遗物名来自 v1.03.4 的遗物数据集（data/nightreign-relics-v1.03.4.json），"
    "与本数据集的 1.03.5 参数存在一个小版本差；若该文件不存在，relicItems 为空数组。",
    "relicPools[].relicCount 与 relicNames* 的长度**不是一回事**，不要假设两者相等："
    "relicCount = 72 是真正吃这个池的遗物**件数**（EquipParamAntique 的 6 个 attachEffectTableId 列，"
    "isDeepRelic 全为 1）；relicNames / relicNamesZh / relicNamesEn 是这 72 件**去重后的名字**，"
    "只有 distinctNameCount = 12 个（端正/细腻/辽阔 × 光耀/幽静/水滴/火燃），"
    "差别在颜色（relicColor）与槽位，名字本身重复。要逐件展开请看 relicNames[].relicIds。"
    "另：relicNamesZh[i] 与 relicNamesEn[i] 现在保证指向同一件遗物（按遗物 ID 配对后整体排序），"
    "早期版本是中英文各自排序，下标配对会错译。",
    "两个随机池并不对等，学者/送葬者的 4 条词条**只有开 DLC 才掉得出来**："
    "AttachEffectTableParam 里，8 个基础角色的 16 条词条在池 2100000 是 (chanceWeight=50, chanceWeight_dlc=−1)、"
    "在 2200000 是 (50, 40)；而 6647200/6647300/6647400/6647500 这 4 条在 2100000 是 (0, −1)（根本不在池里）、"
    "在 2200000 是 (0, 40)——基础权重为 0，只有 DLC 权重 40 才让它们能掉。"
    "statModifiers[].poolWeights 逐池写出这两列（chanceWeight_dlc = −1 表示不覆盖、沿用基础权重，"
    "effectiveWeightDlc 给出折算后的值），dlcOnly / dlcOnlyPoolIds 直接标出这 4 条。",
]

# ---------------------------------------------------------------- 读表 / 读文本


def read_param(raw: Path, name: str) -> list[dict[str, str]]:
    with (raw / "params" / f"{name}.csv").open(newline="", encoding="utf-8") as fh:
        return list(csv.DictReader(fh))


def read_fmg(raw: Path, lang: str, bnd: str, fmg: str) -> dict[int, str]:
    """X.json 与 X_dlc01.json 合并（DLC 覆盖本体）。"""
    out: dict[int, str] = {}
    for suffix in ("", "_dlc01"):
        path = raw / "msg" / lang / f"{bnd}_dlc01" / f"{fmg}{suffix}.json"
        if not path.exists():
            continue
        for key, value in json.loads(path.read_text(encoding="utf-8")).items():
            text = (value or "").strip()
            if text and text != "%null%":
                out[int(key)] = text
    return out


class Text:
    """两种语言的文本表，取名统一走 .get(fmg, id)。"""

    FMGS = [
        ("menuText", "menu", "CL_MenuText"),
        ("attachName", "item", "AttachEffectName"),
        ("antiqueName", "item", "AntiqueName"),
        ("spEffectName", "menu", "SpEffectName"),
        ("spEffectInfo", "menu", "SpEffectInfo"),
        ("talk", "menu", "EventTextForTalk"),
    ]

    def __init__(self, raw: Path) -> None:
        self.tables: dict[str, dict[str, dict[int, str]]] = {}
        for key, bnd, fmg in self.FMGS:
            self.tables[key] = {
                "zh": read_fmg(raw, "zhocn", bnd, fmg),
                "en": read_fmg(raw, "engus", bnd, fmg),
            }

    def get(self, fmg: str, text_id: int) -> tuple[str, str]:
        table = self.tables[fmg]
        return table["zh"].get(text_id, ""), table["en"].get(text_id, "")


# ---------------------------------------------------------------- 插值 / 曲线


def interpolate(anchors: list[tuple[int, int]], level: int, *, toward_zero: bool) -> int:
    """在锚点之间线性插值，取整。用 Fraction 算，锚点级必定原样返回。

    anchors 按等级升序；小于第一个锚点或大于最后一个锚点时钳到端点值。
    toward_zero=False → floor（基础属性表，已验证）；True → 向零取整（转职遗物 delta）。
    """
    if level <= anchors[0][0]:
        return anchors[0][1]
    if level >= anchors[-1][0]:
        return anchors[-1][1]
    for (lo_lv, lo_val), (hi_lv, hi_val) in zip(anchors, anchors[1:]):
        if lo_lv <= level <= hi_lv:
            if level == lo_lv:
                return lo_val
            if level == hi_lv:
                return hi_val
            exact = Fraction(lo_val) + Fraction(hi_val - lo_val) * Fraction(level - lo_lv, hi_lv - lo_lv)
            return int(exact) if toward_zero else math.floor(exact)
    raise AssertionError(f"等级 {level} 落在锚点之外：{anchors}")


class Graph:
    """CalcCorrectGraph 的一行。"""

    def __init__(self, row: dict[str, str]) -> None:
        self.id = int(row["ID"])
        self.name = row["Name"]
        self.x = [float(row[f"stageMaxVal{i}"]) for i in range(5)]
        self.y = [float(row[f"stageMaxGrowVal{i}"]) for i in range(5)]
        self.adj = [float(row[f"adjPt_maxGrowVal{i}"]) for i in range(5)]

    @property
    def linear(self) -> bool:
        return all(a == 1.0 for a in self.adj)

    def segment(self, value: float) -> int:
        """返回 value 所在段的下标 i（区间 [x[i], x[i+1]]）。"""
        for i in range(4):
            if value <= self.x[i + 1]:
                return i
        return 3

    def calc(self, value: int) -> Fraction | float:
        """Elden Ring 通用 CalcCorrectGraph 求值。adjPt 取下段下标。

        整段都是直线（adjPt == 1）时用 Fraction 精确算，避免浮点误差影响取整。
        """
        if value <= self.x[0]:
            return Fraction(int(self.y[0])) if self.linear else self.y[0]
        if value >= self.x[4]:
            return Fraction(int(self.y[4])) if self.linear else self.y[4]
        i = self.segment(value)
        x0, x1, y0, y1, adj = self.x[i], self.x[i + 1], self.y[i], self.y[i + 1], self.adj[i]
        if adj == 1.0:
            return (Fraction(int(y0))
                    + Fraction(int(y1) - int(y0)) * Fraction(value - int(x0), int(x1) - int(x0)))
        ratio = (value - x0) / (x1 - x0)
        growth = ratio ** adj if adj > 0 else 1.0 - (1.0 - ratio) ** abs(adj)
        return y0 + (y1 - y0) * growth

    def as_json(self, used_for: list[str]) -> dict[str, Any]:
        def num(v: float) -> Any:
            return int(v) if float(v).is_integer() else v
        return {
            "id": self.id,
            "name": self.name,
            "stageMaxVal": [num(v) for v in self.x],
            "stageMaxGrowVal": [num(v) for v in self.y],
            "adjPt": [num(v) for v in self.adj],
            "linear": self.linear,
            "usedFor": used_for,
        }


# ---------------------------------------------------------------- 构建


def row_stats(row: dict[str, str]) -> dict[str, int]:
    return {key: int(row[column]) for key, column, _ in ATTRIBUTES}


def row_extras(row: dict[str, str]) -> dict[str, Any]:
    out: dict[str, Any] = {}
    for key, column, kind, _, _ in EXTRA_COLUMNS:
        raw = row[column]
        out[key] = int(raw) if kind == "int" else float(raw)
    return out


def anchor_entry(row: dict[str, str]) -> dict[str, Any]:
    entry: dict[str, Any] = {
        "level": int(row["totalLevel"]),
        "rowId": int(row["ID"]),
        "rowName": row["Name"],
        "stats": row_stats(row),
    }
    entry.update(row_extras(row))
    return entry


def build_levels(anchors: list[dict[str, Any]], graphs: dict[int, Graph]) -> list[dict[str, Any]]:
    """把 4 个锚点铺成 1–15 级的完整表（含派生值）。"""
    anchor_levels = {a["level"] for a in anchors}
    stat_anchors = {
        key: [(a["level"], a["stats"][key]) for a in anchors] for key in ATTR_KEYS
    }
    extra_anchors = {
        key: [(a["level"], a[key]) for a in anchors]
        for key, _, kind, _, _ in EXTRA_COLUMNS if kind == "int"
    }
    attack_rates = {a["attackRate"] for a in anchors}
    assert len(attack_rates) == 1, f"attackRate 在锚点之间不一致：{attack_rates}"
    attack_rate = attack_rates.pop()

    levels: list[dict[str, Any]] = []
    for level in LEVELS:
        stats = {
            key: interpolate(stat_anchors[key], level, toward_zero=False) for key in ATTR_KEYS
        }
        derived: dict[str, Any] = {}
        for key, source, graph_id, _, _, _, integral in DERIVED:
            value = graphs[graph_id].calc(stats[source])
            if integral:
                assert isinstance(value, Fraction) and value.denominator == 1, \
                    f"{key} 在 {source}={stats[source]} 上不是整数：{value}"
                derived[key] = int(value)
            else:
                derived[key] = round(float(value), 1)
        entry: dict[str, Any] = {
            "level": level,
            "isAnchor": level in anchor_levels,
            "stats": stats,
            "derived": derived,
            "attackRate": attack_rate,
        }
        for key in extra_anchors:
            entry[key] = interpolate(extra_anchors[key], level, toward_zero=False)
        levels.append(entry)
    return levels


def build_heroes(raw: Path, text: Text, status_by_id: dict[int, dict[str, str]],
                 graphs: dict[int, Graph]) -> list[dict[str, Any]]:
    heroes: list[dict[str, Any]] = []
    for row in read_param(raw, "HeroParam"):
        hero_id = int(row["ID"])
        base = int(row["heroStatusParamId"])
        name_id = int(row["characterNameId"])
        assert name_id == HERO_NAME_TEXT_BASE + hero_id - 1, (hero_id, name_id)
        name_zh, name_en = text.get("menuText", name_id)
        assert name_en.lower() == HERO_KEYS[hero_id], (hero_id, name_en)

        anchors = []
        for offset in range(4):
            status = status_by_id.get(base + offset)
            assert status is not None, f"缺少 HeroStatusParam 行 {base + offset}"
            assert status["Name"].startswith(f"[{name_en}] Level "), status["Name"]
            anchors.append(anchor_entry(status))
        anchors.sort(key=lambda a: a["level"])
        assert [a["level"] for a in anchors] == [1, 2, 12, 15], anchors

        heroes.append({
            "id": hero_id,
            "key": HERO_KEYS[hero_id],
            "nameZh": name_zh,
            "nameEn": name_en,
            "characterNameId": name_id,
            "heroStatusParamId": base,
            "anchors": anchors,
            "levels": build_levels(anchors, graphs),
        })
    heroes.sort(key=lambda h: h["id"])
    return heroes


class RelicIndex:
    """遗物数据集（v1.03.4）里「哪件遗物带哪条词条」的反查表。

    relics[].slots / curseSlots 里放的**都是池 ID**（实测 598 个槽位值全部命中 pools）。
    单成员池 = 这个槽位写死了那一条词条；多成员池 = 这个槽位会随机掉池里的任意一条。
    所以 fixed 只收单成员池那一路，随机池只记池号与命中的遗物件数。
    """

    def __init__(self) -> None:
        self.available = RELICS_JSON.exists()
        self.version = ""
        self.fixed: dict[int, list[dict[str, Any]]] = {}
        self.rollable_pools: dict[int, list[int]] = {}
        self.pool_summary: dict[int, dict[str, Any]] = {}
        if not self.available:
            return
        data = json.loads(RELICS_JSON.read_text(encoding="utf-8"))
        self.version = data.get("gameVersion", "")
        pools = {int(pid): members for pid, members in data.get("pools", {}).items()}
        for pool_id, members in pools.items():
            if len(members) > 1:
                for affix in members:
                    self.rollable_pools.setdefault(affix, []).append(pool_id)
        self.pool_relic_ids: dict[int, set[int]] = {}
        pool_relics = self.pool_relic_ids
        # 池 → {遗物 ID: 中文名}。**按 ID 存**，不存名字集合：中英文名各自排序会让同一
        # 下标指向不同遗物（端正/细腻/辽阔 与 Polished/Delicate/Grand 的字典序不一致）。
        self.pool_names_by_id: dict[int, dict[int, str]] = {}
        pool_names = self.pool_names_by_id
        for relic in data.get("relics", []):
            if not relic.get("name"):
                continue                 # 无名行是参数表里的占位/内部行
            for slot_kind, key in (("normal", "slots"), ("curse", "curseSlots")):
                for index, slot in enumerate(relic.get(key, [])):
                    if slot is None or slot < 0:
                        continue
                    members = pools.get(slot, [slot])
                    if len(members) == 1:
                        self.fixed.setdefault(members[0], []).append({
                            "id": relic["id"],
                            "nameZh": relic["name"],
                            "color": relic.get("color"),
                            "deep": bool(relic.get("deep")),
                            "slot": slot_kind,
                            "slotIndex": index,
                        })
                    else:
                        pool_relics.setdefault(slot, set()).add(relic["id"])
                        pool_names.setdefault(slot, {})[relic["id"]] = relic["name"]
        for pool_id, ids in pool_relics.items():
            self.pool_summary[pool_id] = {"relicCount": len(ids)}

    def add_pool_names(self, antique_zh: dict[int, str], antique_en: dict[int, str]) -> None:
        """给随机池摘要补上**成对**的中英文遗物名。

        中英文各自 sorted() 再按下标配对是错的：72 件遗物只有 12 个名字
        （端正/细腻/辽阔 × 光耀/幽静/水滴/火燃 = Polished/Delicate/Grand ×
        Luminous/Tranquil/Drizzly/Burning），两种语言的字典序不一致，
        relicNamesZh[0] 与 relicNamesEn[0] 会指向不同遗物。
        这里先按遗物 ID 取出 (zh, en) 二元组、**整体**去重再排序，
        保证同一下标的中英文说的是同一件遗物。
        """
        for pool_id, summary in self.pool_summary.items():
            by_pair: dict[tuple[str, str], list[int]] = {}
            for relic_id in sorted(self.pool_relic_ids[pool_id]):
                zh = antique_zh.get(relic_id) or self.pool_names_by_id[pool_id].get(relic_id, "")
                en = antique_en.get(relic_id, "")
                if not zh:
                    continue
                dataset_zh = self.pool_names_by_id[pool_id].get(relic_id)
                assert dataset_zh in (None, zh), (pool_id, relic_id, dataset_zh, zh)
                by_pair.setdefault((zh, en), []).append(relic_id)
            pairs = sorted(by_pair.items())
            summary["distinctNameCount"] = len(pairs)
            summary["relicNames"] = [
                {"zh": zh, "en": en, "relicIds": ids} for (zh, en), ids in pairs
            ]
            # 与 relicNames 同序：下标配对现在是对的，老字段继续可用。
            summary["relicNamesZh"] = [zh for (zh, _), _ in pairs]
            summary["relicNamesEn"] = [en for (_, en), _ in pairs]


def read_pool_weights(raw: Path) -> dict[int, dict[int, dict[str, int]]]:
    """AttachEffectTableParam → {池 ID: {词条 ID: {chanceWeight, chanceWeight_dlc}}}。

    只收 20 条转职遗物词条那一段。chanceWeight 是基础权重、chanceWeight_dlc 是开 DLC
    之后用的权重（-1 = 不覆盖、沿用基础权重）。学者/送葬者的 4 条在池 2200000 里
    基础权重是 0、只有 chanceWeight_dlc = 40，也就是**只有开 DLC 才掉得出来**。

    两类行被排除：
      * ID == attachEffectId 的单行「伪池」（EquipParamAntique 把词条写死在槽位上时指向它，
        权重恒为 100），那一路走 statModifiers[].relicItems；
      * 把这 20 条列成权重 0 的其他池（110/210/310/1000000–1009002/2000000）——
        列了但掉不出来，留着只会让 poolWeights 变成 36 个全零条目。
    只保留至少对一条词条给了非零权重的池，实测就是 2100000 与 2200000 两个。
    """
    collected: dict[int, dict[int, dict[str, int]]] = {}
    for row in read_param(raw, "AttachEffectTableParam"):
        affix_id = int(row["attachEffectId"])
        if not ATTACH_EFFECT_RANGE[0] <= affix_id <= ATTACH_EFFECT_RANGE[1]:
            continue
        pool_id = int(row["ID"])
        if pool_id == affix_id:            # 单行伪池，不是随机池
            continue
        base = int(row["chanceWeight"])
        dlc = int(row["chanceWeight_dlc"])
        per_pool = collected.setdefault(pool_id, {})
        assert affix_id not in per_pool, f"池 {pool_id} 里词条 {affix_id} 出现了多行"
        per_pool[affix_id] = {
            "chanceWeight": base,
            "chanceWeightDlc": dlc,
            # dlc 列为 -1 表示不覆盖，此时仍用基础权重
            "effectiveWeightDlc": base if dlc < 0 else dlc,
        }
    return {
        pool_id: per_pool
        for pool_id, per_pool in collected.items()
        if any(w["chanceWeight"] > 0 or w["effectiveWeightDlc"] > 0 for w in per_pool.values())
    }


def build_stat_modifiers(raw: Path, text: Text, status_by_id: dict[int, dict[str, str]],
                         speffect_by_id: dict[int, dict[str, str]],
                         heroes: list[dict[str, Any]],
                         relics: RelicIndex,
                         pool_weights: dict[int, dict[int, dict[str, int]]]) -> list[dict[str, Any]]:
    hero_by_id = {h["id"]: h for h in heroes}
    fixed_relics, pool_index = relics.fixed, relics.rollable_pools
    antique_zh, antique_en = text.tables["antiqueName"]["zh"], text.tables["antiqueName"]["en"]

    modifiers: list[dict[str, Any]] = []
    for row in read_param(raw, "AttachEffectParam"):
        affix_id = int(row["ID"])
        if not ATTACH_EFFECT_RANGE[0] <= affix_id <= ATTACH_EFFECT_RANGE[1]:
            continue
        sp_id = int(row["passiveSpEffectId_1"])
        sp = speffect_by_id.get(sp_id)
        assert sp is not None, f"AttachEffect {affix_id} 的 passiveSpEffectId_1 {sp_id} 不存在"
        modifier_base = int(sp["heroStatusModifier"])
        assert MODIFIER_ROW_RANGE[0] <= modifier_base <= MODIFIER_ROW_RANGE[1], (affix_id, modifier_base)

        # 角色归属三路交叉验证：allow* 位 / 修饰行 ID 结构 / 行名前缀
        allowed = [hid for col, hid in ALLOW_COLUMNS.items() if int(row[col]) != 0]
        assert len(allowed) == 1, f"AttachEffect {affix_id} 的 allow* 位不是恰好一个：{allowed}"
        hero_id = allowed[0]
        assert (modifier_base - MODIFIER_ROW_RANGE[0]) // 1000 == hero_id - 1, (affix_id, modifier_base)
        hero = hero_by_id[hero_id]
        assert row["Name"].startswith(f"[Relic - {hero['nameEn']}]"), row["Name"]

        anchors = []
        for offset, level in ((0, 1), (1, 12)):
            status = status_by_id.get(modifier_base + offset)
            assert status is not None, f"缺少增减量行 {modifier_base + offset}"
            assert int(status["totalLevel"]) == level, status["Name"]
            anchors.append({
                "level": level,
                "rowId": int(status["ID"]),
                "rowName": status["Name"],
                "delta": row_stats(status),
            })

        affected = sorted(
            (key for key in ATTR_KEYS if any(a["delta"][key] != 0 for a in anchors)),
            key=ATTR_KEYS.index,
        )
        assert affected, f"AttachEffect {affix_id} 的增减量全为 0"
        for anchor in anchors:                      # 只留真正动了的属性，两级键集一致
            anchor["delta"] = {key: anchor["delta"][key] for key in affected}

        per_stat = {key: [(a["level"], a["delta"][key]) for a in anchors] for key in affected}
        levels = []
        for level in LEVELS:
            delta = {key: interpolate(per_stat[key], level, toward_zero=True) for key in affected}
            floor_alt = {
                key: interpolate(per_stat[key], level, toward_zero=False) for key in affected
            }
            entry: dict[str, Any] = {
                "level": level,
                "isAnchor": level in (1, 12),
                "inferred": level not in (1, 12),
                "delta": delta,
            }
            diff = {k: v for k, v in floor_alt.items() if v != delta[k]}
            if diff:
                entry["deltaFloorAlt"] = diff
            levels.append(entry)

        relic_items = []
        for item in fixed_relics.get(affix_id, []):
            color = item["color"]
            relic_items.append({
                **item,
                "nameEn": antique_en.get(item["id"], ""),
                "colorZh": RELIC_COLORS.get(color, ("", ""))[0],
                "colorEn": RELIC_COLORS.get(color, ("", ""))[1],
            })
            if antique_zh.get(item["id"]):
                assert antique_zh[item["id"]] == item["nameZh"], item

        # 这条词条在哪些随机池里、各自的权重是多少（含「基础权重 0、只有 DLC 权重」的情形）
        rollable_ids = sorted(pool_index.get(affix_id, []))
        pool_weight_out: dict[str, Any] = {}
        weighted_pools: list[int] = []
        dlc_only_pools: list[int] = []
        for pool_id in sorted(pool_weights):
            entry_w = pool_weights[pool_id].get(affix_id)
            if entry_w is None:
                continue
            base_w, dlc_w = entry_w["chanceWeight"], entry_w["effectiveWeightDlc"]
            rollable = base_w > 0 or dlc_w > 0
            dlc_only = base_w <= 0 < dlc_w
            pool_weight_out[str(pool_id)] = {
                "chanceWeight": entry_w["chanceWeight"],
                "chanceWeightDlc": entry_w["chanceWeightDlc"],
                "effectiveWeightDlc": dlc_w,
                "rollable": rollable,
                "dlcOnly": dlc_only,
            }
            if rollable:
                weighted_pools.append(pool_id)
            if dlc_only:
                dlc_only_pools.append(pool_id)
        if pool_weight_out:      # 参数表里的「掉不掉得出来」必须与遗物数据集的池成员一致
            assert weighted_pools == rollable_ids, (affix_id, weighted_pools, rollable_ids)

        name_zh, name_en = text.get("attachName", int(row["attachTextId"]))
        modifiers.append({
            "affixId": affix_id,
            "nameZh": name_zh,
            "nameEn": name_en,
            "paramRowName": row["Name"],
            "attachTextId": int(row["attachTextId"]),
            "heroId": hero_id,
            "heroKey": hero["key"],
            "heroNameZh": hero["nameZh"],
            "heroNameEn": hero["nameEn"],
            "spEffectId": sp_id,
            "modifierRowIds": [modifier_base, modifier_base + 1],
            "affectedStats": affected,
            "anchors": anchors,
            "levels": levels,
            "relicItems": relic_items,
            "rollablePoolIds": rollable_ids,
            "poolWeights": pool_weight_out,
            "dlcOnlyPoolIds": dlc_only_pools,
            "dlcOnly": bool(dlc_only_pools) and dlc_only_pools == rollable_ids,
        })
    modifiers.sort(key=lambda m: m["affixId"])
    return modifiers


def build_libra_respecs(text: Text, status_by_id: dict[int, dict[str, str]],
                        speffect_by_id: dict[int, dict[str, str]],
                        graphs: dict[int, Graph]) -> list[dict[str, Any]]:
    effect_zh, effect_en = text.get("spEffectName", LIBRA_EFFECT_TEXT_ID)
    info_zh, info_en = text.get("spEffectInfo", LIBRA_EFFECT_TEXT_ID)
    stat_zh = {key: text.get("attachName", tid)[0] for key, _, tid in ATTRIBUTES}
    stat_en = {key: text.get("attachName", tid)[1] for key, _, tid in ATTRIBUTES}

    out: list[dict[str, Any]] = []
    for sp_id in LIBRA_SPEFFECTS:
        sp = speffect_by_id[sp_id]
        assert sp["Name"].startswith("[Libra Deal] Respec to "), sp["Name"]
        suffix = sp["Name"].rsplit(" ", 1)[-1]
        key, talk_id = LIBRA_DEALS[suffix]
        assert int(sp["spEffectTextId_1"]) == LIBRA_EFFECT_TEXT_ID, sp["Name"]
        base = int(sp["heroStatusId"])
        assert base > 0, sp["Name"]

        anchors = []
        for offset in range(4):
            status = status_by_id.get(base + offset)
            assert status is not None, f"缺少利普拉锚点行 {base + offset}"
            assert status["Name"].startswith(f"[Libra - {suffix}] Level "), status["Name"]
            anchors.append(anchor_entry(status))
        anchors.sort(key=lambda a: a["level"])
        assert [a["level"] for a in anchors] == [1, 2, 12, 15], anchors

        deal_zh, deal_en = text.get("talk", talk_id)
        out.append({
            "key": key,
            "nameZh": f"{effect_zh}（{stat_zh[key]}）",
            "nameEn": f"{effect_en} ({stat_en[key]})",
            "effectNameZh": effect_zh,
            "effectNameEn": effect_en,
            "effectInfoZh": info_zh,
            "effectInfoEn": info_en,
            "dealLineZh": deal_zh,
            "dealLineEn": deal_en,
            "dealTextId": talk_id,
            "statKey": key,
            "statNameZh": stat_zh[key],
            "statNameEn": stat_en[key],
            "spEffectId": sp_id,
            "spEffectTextId": LIBRA_EFFECT_TEXT_ID,
            "heroStatusId": base,
            "paramRowName": sp["Name"],
            "anchors": anchors,
            "levels": build_levels(anchors, graphs),
        })
    return out


def build_cross_checks(heroes: list[dict[str, Any]]) -> list[dict[str, Any]]:
    """把「跟哪几张外部表逐格比过、哪几格对不上」写进数据集本身。"""
    out: list[dict[str, Any]] = []
    for hero_key, (baseline, exact, note, urls) in EXTERNAL_BASELINES.items():
        hero = next(h for h in heroes if h["key"] == hero_key)
        mismatches = []
        for entry in hero["levels"]:
            expected = dict(zip(BASELINE_COLUMNS, baseline[entry["level"]]))
            actual = {**entry["stats"],
                      **{k: entry["derived"][k] for k in ("hp", "fp", "stamina")}}
            for column, want in expected.items():
                if actual[column] != want:
                    mismatches.append({"level": entry["level"], "field": column,
                                       "external": want, "ours": actual[column]})
        out.append({
            "heroKey": hero_key,
            "heroNameZh": hero["nameZh"],
            "urls": urls,
            "levelsCompared": len(baseline),
            "cellsCompared": len(baseline) * len(BASELINE_COLUMNS),
            "mismatchCount": len(mismatches),
            "mismatches": mismatches,
            "authoritative": "params",
            "note": note,
        })
    return out


def build_stat_names(text: Text) -> dict[str, Any]:
    attributes = []
    for key, column, text_id in ATTRIBUTES:
        zh, en = text.get("attachName", text_id)
        attributes.append({"key": key, "zh": zh, "en": en,
                           "paramColumn": column, "textId": text_id})
    derived = []
    for key, source, graph_id, text_id, zh_fallback, en_fallback, integral in DERIVED:
        zh, en = text.get("menuText", text_id) if text_id else ("", "")
        derived.append({
            "key": key,
            "zh": zh or zh_fallback,
            "en": en or en_fallback,
            "fromStat": source,
            "graphId": graph_id,
            "textId": text_id,
            "inGameLabel": bool(text_id),
            "integer": integral,
        })
    extras = [{"key": key, "zh": zh, "en": en, "paramColumn": column, "type": kind}
              for key, column, kind, zh, en in EXTRA_COLUMNS]
    return {
        "attributeOrder": ATTR_KEYS,
        "derivedOrder": DERIVED_KEYS,
        "attributes": attributes,
        "derived": derived,
        "extras": extras,
    }


# ---------------------------------------------------------------- 自检


def self_check(payload: dict[str, Any]) -> None:
    heroes = payload["heroes"]
    modifiers = payload["statModifiers"]
    respecs = payload["libraRespecs"]

    # ① 硬编码的 wiki 回归基线：追踪者与执行者必须逐格全中，
    #    女爵必须恰好只在「灵巧 1–14 级」这一处与外部表不同（补丁 1.02.2 之前的旧数据）
    for hero_key, (baseline, exact, _, _) in EXTERNAL_BASELINES.items():
        hero = next(h for h in heroes if h["key"] == hero_key)
        assert len(hero["levels"]) == 15, hero_key
        diffs = set()
        for entry in hero["levels"]:
            expected = dict(zip(BASELINE_COLUMNS, baseline[entry["level"]]))
            actual = {**entry["stats"],
                      **{k: entry["derived"][k] for k in ("hp", "fp", "stamina")}}
            for column, want in expected.items():
                if actual[column] != want:
                    diffs.add((column, entry["level"]))
        if exact:
            assert not diffs, f"{hero_key} 与 wiki 基线不符的格子：{sorted(diffs)}"
        elif hero_key == "duchess":
            assert diffs == DUCHESS_KNOWN_DIFFS, \
                f"女爵与外部表的差异不再是「只有灵巧 1–14 级」：{sorted(diffs)}"
        else:
            raise AssertionError(f"{hero_key} 没有声明允许的差异集合")

    # ② 每个角色：15 级齐全、锚点级等于原始行、属性与派生值单调不减
    for hero in heroes:
        assert [lv["level"] for lv in hero["levels"]] == LEVELS, hero["key"]
        by_level = {lv["level"]: lv for lv in hero["levels"]}
        assert [a["level"] for a in hero["anchors"]] == [1, 2, 12, 15], hero["key"]
        for anchor in hero["anchors"]:
            entry = by_level[anchor["level"]]
            assert entry["isAnchor"], (hero["key"], anchor["level"])
            assert entry["stats"] == anchor["stats"], (hero["key"], anchor["level"])
            for extra, _, kind, _, _ in EXTRA_COLUMNS:
                assert entry[extra] == anchor[extra], (hero["key"], anchor["level"], extra)
        assert sum(1 for lv in hero["levels"] if lv["isAnchor"]) == 4, hero["key"]
        for prev, cur in zip(hero["levels"], hero["levels"][1:]):
            for key in ATTR_KEYS:
                assert cur["stats"][key] >= prev["stats"][key], (hero["key"], key, cur["level"])
            for key in DERIVED_KEYS:
                assert cur["derived"][key] >= prev["derived"][key], (hero["key"], key, cur["level"])
        for entry in hero["levels"]:
            assert entry["abilityReinforce"] == entry["level"] - 1, (hero["key"], entry["level"])
            assert entry["revenantSpiritReinforce"] == entry["level"] - 1
            assert entry["executorBeastReinforce"] == entry["level"] - 1

    # ③ 20 条转职遗物：每条恰好挂一个角色，每级 delta 落在两个锚点之间
    assert len(modifiers) == 20, len(modifiers)
    hero_ids = [h["id"] for h in heroes]
    per_hero: dict[int, int] = {hid: 0 for hid in hero_ids}
    for mod in modifiers:
        assert mod["heroId"] in per_hero, mod["affixId"]
        per_hero[mod["heroId"]] += 1
        assert [lv["level"] for lv in mod["levels"]] == LEVELS, mod["affixId"]
        low = {a["level"]: a["delta"] for a in mod["anchors"]}
        assert set(low) == {1, 12}, mod["affixId"]
        for key in mod["affectedStats"]:
            lo, hi = sorted((low[1][key], low[12][key]))
            previous = None
            for entry in mod["levels"]:
                value = entry["delta"][key]
                assert lo <= value <= hi, (mod["affixId"], key, entry["level"], value, lo, hi)
                if previous is not None:      # 单调（跟两个锚点的方向一致）
                    assert (value - previous) * (low[12][key] - low[1][key]) >= 0, \
                        (mod["affixId"], key, entry["level"])
                previous = value
            assert mod["levels"][0]["delta"][key] == low[1][key], (mod["affixId"], key)
            for entry in mod["levels"][11:]:  # 12–15 级都等于 L12 锚点
                assert entry["delta"][key] == low[12][key], (mod["affixId"], key, entry["level"])
        assert [e["inferred"] for e in mod["levels"]] == [lv not in (1, 12) for lv in LEVELS]
    assert all(count == 2 for count in per_hero.values()), per_hero

    # ④ 5 套利普拉交易表齐全
    assert len(respecs) == 5, len(respecs)
    assert {r["key"] for r in respecs} == {"strength", "dexterity", "intelligence", "faith", "arcane"}
    for respec in respecs:
        assert [lv["level"] for lv in respec["levels"]] == LEVELS, respec["key"]
        by_level = {lv["level"]: lv for lv in respec["levels"]}
        for anchor in respec["anchors"]:
            assert by_level[anchor["level"]]["stats"] == anchor["stats"], respec["key"]
        assert [a["level"] for a in respec["anchors"]] == [1, 2, 12, 15], respec["key"]
        assert sum(1 for lv in respec["levels"] if lv["isAnchor"]) == 4, respec["key"]
        for prev, cur in zip(respec["levels"], respec["levels"][1:]):
            for key in ATTR_KEYS:
                assert cur["stats"][key] >= prev["stats"][key], (respec["key"], key, cur["level"])
            for key in DERIVED_KEYS:
                assert cur["derived"][key] >= prev["derived"][key], (respec["key"], key)
    # 每笔交易换来的那项属性，在 5 套表里必须是同项属性的最高值（15 级时）
    for respec in respecs:
        mine = respec["levels"][-1]["stats"][respec["statKey"]]
        others = [r["levels"][-1]["stats"][respec["statKey"]] for r in respecs if r is not respec]
        assert mine > max(others), (respec["key"], mine, others)

    # ⑤ 结构完整性与取值类型
    assert {h["key"] for h in heroes} == set(HERO_KEYS.values())
    assert len({m["affixId"] for m in modifiers}) == 20
    assert payload["statNames"]["attributeOrder"] == ATTR_KEYS
    assert payload["statNames"]["derivedOrder"] == DERIVED_KEYS
    for table in heroes + respecs:
        for entry in table["levels"]:
            assert set(entry["stats"]) == set(ATTR_KEYS), table.get("key")
            assert set(entry["derived"]) == set(DERIVED_KEYS), table.get("key")
            for key in INTEGRAL_DERIVED:
                assert isinstance(entry["derived"][key], int), (table.get("key"), key)
    for pool_ids in (m["rollablePoolIds"] for m in modifiers):
        for pool_id in pool_ids:
            assert str(pool_id) in payload["relicPools"] or not payload["relicPools"], pool_id

    # ⑥ 随机池：中英文名按下标严格配对、件数与名字数是两个不同量纲
    for pool_id, summary in payload["relicPools"].items():
        names = summary["relicNames"]
        assert summary["distinctNameCount"] == len(names) == len(summary["relicNamesZh"]) \
            == len(summary["relicNamesEn"]), pool_id
        assert [n["zh"] for n in names] == summary["relicNamesZh"], pool_id
        assert [n["en"] for n in names] == summary["relicNamesEn"], pool_id
        assert len({n["zh"] for n in names}) == len(names), f"池 {pool_id} 的中文名有重复"
        assert len({n["en"] for n in names}) == len(names), f"池 {pool_id} 的英文名有重复"
        assert all(n["zh"] and n["en"] for n in names), pool_id
        assert sum(len(n["relicIds"]) for n in names) == summary["relicCount"], pool_id
        assert len({i for n in names for i in n["relicIds"]}) == summary["relicCount"], pool_id
        # 中英文各自排序是个经典错误：这里断言两种排序**不一致**，保证配对不是巧合对上的
        assert summary["relicNamesEn"] != sorted(summary["relicNamesEn"]), \
            f"池 {pool_id} 的英文名恰好是自身的字典序——配对可能又退回了各排各的"

    # ⑦ 随机池权重：参数表的「掉不掉得出来」与 rollablePoolIds 一致，
    #    且「基础权重 0、只靠 DLC 权重」的恰好是学者/送葬者那 4 条
    dlc_only = sorted(m["affixId"] for m in modifiers if m["dlcOnly"])
    assert dlc_only == [6647200, 6647300, 6647400, 6647500], dlc_only
    for mod in modifiers:
        rollable = sorted(int(pid) for pid, w in mod["poolWeights"].items() if w["rollable"])
        assert rollable == mod["rollablePoolIds"], (mod["affixId"], rollable)
        for pid, weight in mod["poolWeights"].items():
            expect = weight["chanceWeight"] if weight["chanceWeightDlc"] < 0 else weight["chanceWeightDlc"]
            assert weight["effectiveWeightDlc"] == expect, (mod["affixId"], pid)
            assert weight["dlcOnly"] == (weight["chanceWeight"] <= 0 < weight["effectiveWeightDlc"])
        if mod["dlcOnly"]:
            assert mod["heroKey"] in ("scholar", "undertaker"), mod["affixId"]
            assert mod["rollablePoolIds"] == [2200000], mod["affixId"]

    # ⑧ 派生值：数据集真正用到的每一段 CalcCorrectGraph 斜率都必须是整数
    #    （caveats 里「只用到两段」的说法曾经漏掉守护者 12–15 级用到的 [50,75]）
    derived_from = {d["key"]: (str(d["graphId"]), d["fromStat"])
                    for d in payload["statNames"]["derived"]}
    used_segments: dict[str, set[int]] = {}
    for table in heroes + respecs:
        for entry in table["levels"]:
            for key in INTEGRAL_DERIVED:
                graph_id, stat = derived_from[key]
                stages = payload["growthGraphs"][graph_id]["stageMaxVal"]
                value = entry["stats"][stat]
                index = next((i for i in range(4) if value <= stages[i + 1]), 3)
                used_segments.setdefault(graph_id, set()).add(index)
    for graph_id, indices in sorted(used_segments.items()):
        graph = payload["growthGraphs"][graph_id]
        for index in sorted(indices):
            span = graph["stageMaxVal"][index + 1] - graph["stageMaxVal"][index]
            rise = graph["stageMaxGrowVal"][index + 1] - graph["stageMaxGrowVal"][index]
            slope = Fraction(rise, span)
            assert slope.denominator == 1, (graph_id, index, slope)
    assert used_segments == {"100": {0, 1, 2}, "101": {0, 1}, "104": {0, 1}}, used_segments


# ---------------------------------------------------------------- main


def main() -> None:
    ap = argparse.ArgumentParser(description="生成 NIGHTREIGN 角色属性数据集")
    ap.add_argument("--raw", type=Path, default=DEFAULT_RAW, help="raw/ 目录（含 params 与 msg）")
    ap.add_argument("--out", type=Path, default=DEFAULT_OUT, help="输出 JSON 路径")
    ap.add_argument("--pretty", action="store_true", help="带缩进输出（调试用，体积翻倍）")
    args = ap.parse_args()

    raw: Path = args.raw
    text = Text(raw)
    status_by_id = {int(r["ID"]): r for r in read_param(raw, "HeroStatusParam")}
    speffect_by_id = {int(r["ID"]): r for r in read_param(raw, "SpEffectParam")}
    graphs = {int(r["ID"]): Graph(r) for r in read_param(raw, "CalcCorrectGraph")}

    used_graphs: dict[int, list[str]] = {}
    for key, _, graph_id, _, _, _, _ in DERIVED:
        used_graphs.setdefault(graph_id, []).append(key)
    for graph_id, keys in used_graphs.items():
        graph = graphs[graph_id]
        if graph_id != 220:
            assert graph.linear, f"CalcCorrectGraph {graph_id} 不是纯线性：{graph.adj}"

    relics = RelicIndex()
    relics.add_pool_names(text.tables["antiqueName"]["zh"], text.tables["antiqueName"]["en"])
    pool_weights = read_pool_weights(raw)
    heroes = build_heroes(raw, text, status_by_id, graphs)
    modifiers = build_stat_modifiers(raw, text, status_by_id, speffect_by_id, heroes,
                                     relics, pool_weights)
    respecs = build_libra_respecs(text, status_by_id, speffect_by_id, graphs)
    relics_version = relics.version
    payload: dict[str, Any] = {
        "schemaVersion": SCHEMA_VERSION,
        "datasetId": DATASET_ID,
        "gameVersion": GAME_VERSION,
        "dataVersion": DATA_VERSION,
        "generatedAt": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "sources": [
            {
                "name": "ELDEN RING NIGHTREIGN regulation.bin",
                "url": "",
                "revision": "regulation 10350000 / exe 1.3.3.0",
                "license": "游戏本体数据，仅用于展示数值",
                "usage": "HeroParam / HeroStatusParam / AttachEffectParam / AttachEffectTableParam"
                         "（随机池权重）/ SpEffectParam / CalcCorrectGraph",
            },
            {
                "name": "ELDEN RING NIGHTREIGN 游戏内文本 FMG（简体中文 / 英文）",
                "url": "",
                "revision": "regulation 10350000 + DLC1",
                "license": "游戏本体数据，仅用于展示名称",
                "usage": "menu/CL_MenuText（角色名、血量/专注值/精力标签）、"
                         "item/AttachEffectName（词条名、8 项属性名）、item/AntiqueName（遗物名）、"
                         "menu/SpEffectName + SpEffectInfo（扭曲的重生）、"
                         "menu/EventTextForTalk（利普拉的 5 个交易选项）",
            },
            {
                "name": "Smithbox Paramdex (NR)",
                "url": f"https://github.com/vawser/Smithbox/tree/{PARAMDEX_REV}/src/Smithbox.Data/Assets/PARAM/NR",
                "revision": PARAMDEX_REV,
                "license": "MIT",
                "usage": "paramdef 字段名、行名（Name 列，如「[Wylder] Level 12」「[Libra Deal] Respec to Strength」）",
            },
            {
                "name": "Elden Ring Nightreign Wiki (Fextralife) — Wylder",
                "url": "https://eldenringnightreign.wiki.fextralife.com/Wylder",
                "revision": "2026-09 访问",
                "license": "第三方 wiki，仅作交叉验证",
                "usage": "追踪者 1–15 级 8 项属性全表 —— 与本脚本的线性插值 + 向下取整结果 120 格全中",
            },
            {
                "name": "Eldenpedia (eldenring.wiki.gg) — Nightreign:Wylder",
                "url": "https://eldenring.wiki.gg/wiki/Nightreign:Wylder",
                "revision": "2026-09 访问",
                "license": "第三方 wiki，仅作交叉验证",
                "usage": "追踪者 1–15 级血量/专注值/精力 —— 44/45 格一致，"
                         "12 级精力该页写 92（与 11 级重复）疑为笔误，按 CalcCorrectGraph 104 应为 96",
            },
            {
                "name": "Elden Ring Nightreign Wiki (Fextralife) — 转职遗物词条页 / Relic Effects",
                "url": "https://eldenringnightreign.wiki.fextralife.com/Relic_Effects",
                "revision": "2026-09 访问",
                "license": "第三方 wiki，仅作交叉验证",
                "usage": "词条页写出的数值全部等于 Level 12 那一行（例：Revenant 提升生命力、耐力，降低集中力 = "
                         "集中力 −11 / 生命力 +5 / 耐力 +5），佐证「13–15 级沿用 L12 值」",
            },
            {
                "name": "Elden Ring Nightreign Wiki (Fextralife) — "
                        "Revenant Improved Vigor and Endurance, Reduced Mind",
                "url": "https://eldenringnightreign.wiki.fextralife.com/"
                       "Revenant_Improved_Vigor_and_Endurance,_Reduced_Mind",
                "revision": "2026-09 访问",
                "license": "第三方 wiki，仅作交叉验证",
                "usage": "该页原文「Decreases mind by 11, increases vigor by 5 and endurance by 5」"
                         "＝ HeroStatusParam 305001（L12 锚点）逐格一致，"
                         "支撑 interpolation.modifierAnchorVerified",
            },
            {
                "name": "Steam 社区讨论「New stat shifts are a mega trap.」（玩家 15 级实测）",
                "url": "https://steamcommunity.com/app/2622380/discussions/0/572641938359169696/",
                "revision": "2026-09 访问",
                "license": "第三方玩家实测，仅作交叉验证",
                "usage": "15 级实测逐条对上 L12 锚点：守护者 灵巧 31→50 / 力气 41→50 / 生命力 60→52（301001）、"
                         "无赖 感应 10→27 / 生命力 56→52（304101）、隐士 智力 51→41 与 灵巧 +20（306000）、"
                         "隐士 集中力 30→17（306101）；贴中作参照的裸属性（追踪者 力气 50 / 生命力 52、"
                         "女爵 智力 42、执行者 感应 28）也与本数据集 L15 一致 —— 佐证「13–15 级沿用 L12 值」",
            },
            {
                "name": "Steam 社区讨论「Revenant Needs a Real Identity」（15 级复仇者派生值实测）",
                "url": "https://steamcommunity.com/app/2622380/discussions/0/603041689184442287/",
                "revision": "2026-09 访问",
                "license": "第三方玩家实测，仅作交叉验证",
                "usage": "15 级复仇者裸装 血量 780 / 专注值 200 / 精力 90、带该词条后 880 / 145 / 100，"
                         "与本数据集 L15 基础（生命力 35 / 集中力 31 / 耐力 21）叠加 305001 后"
                         "（40 / 20 / 26）经 CalcCorrectGraph 100/101/104 算出的值完全一致 —— "
                         "同时佐证「13–15 级沿用 L12 值」与派生值公式",
            },
        ] + ([{
            "name": "本仓库遗物数据集 nightreign-relics-v1.03.4.json",
            "url": "",
            "revision": relics_version,
            "license": "本仓库产物",
            "usage": "statModifiers[].relicItems：哪件遗物物品把转职词条写死在槽位上",
        }] if relics_version else []),
        "statNames": build_stat_names(text),
        "crossChecks": build_cross_checks(heroes),
        "growthGraphs": {str(gid): graphs[gid].as_json(keys) for gid, keys in sorted(used_graphs.items())},
        "interpolation": {
            "baseAnchorLevels": [1, 2, 12, 15],
            "modifierAnchorLevels": [1, 12],
            "maxLevel": 15,
            "baseRule": "相邻锚点之间线性插值，结果向下取整（floor）。小于最低锚点或大于最高锚点时钳到端点。",
            "baseRounding": "floor",
            "baseVerified": True,
            "baseVerification": "追踪者 1–15 级 8 项属性 120 格（Fextralife）+ 血量/专注值/精力 45 格"
                                "（eldenring.wiki.gg，12 级精力那一格按 CalcCorrectGraph 修正）逐格一致；"
                                "脚本把这 15 行硬编码成回归基线，self_check 每次生成都会重跑。",
            "derivedRule": "派生值 = CalcCorrectGraph 分段线性插值（growthGraphs 给出原始行）。"
                           "血量/专注值/精力所在的 100/101/104 三行 adjPt 全为 1；"
                           "100 与 101 四段斜率相同（整条是直线：血量 = 20×生命力 + 80、专注值 = 5×集中力 + 45），"
                           "104 的 [1,75] 斜率恒为 2（精力 = 2×耐力 + 48），只有够不到的 [75,99] 段是 25/12。"
                           "本数据集实际用到 100 的 [1,25]/[25,50]/[50,75] 三段（守护者 12–15 级生命力 54–60）"
                           "与 101/104 的 [1,25]/[25,50] 两段，每一段斜率都是整数，所以这三项必为整数；"
                           "负重上限（220）带指数、且本作没有装备重量。",
            "modifierRule": "转职遗物只有 L1 / L12 两个锚点：1–12 级线性插值后向零取整（trunc），"
                            "13–15 级沿用 L12 的值。",
            "modifierRounding": "trunc",
            "modifierVerified": False,
            "modifierVerifiedNote": "modifierVerified 是下面两个细分字段的保守合取"
                                    "（恒等于 modifierMidLevelsVerified），只为兼容早期读法保留；"
                                    "页面请读 modifierAnchorVerified / modifierMidLevelsVerified，"
                                    "别据此把整张遗物表标成「未验证」。",
            "modifierAnchorVerified": True,
            "modifierAnchorVerification": "L1/L12 锚点直接来自 HeroStatusParam；"
                                          "「13–15 级沿用 L12」已由多组 15 级实测独立确认："
                                          "守护者 灵巧 31→50 / 力气 41→50 / 生命力 60→52（301001）、"
                                          "无赖 感应 10→27 / 生命力 56→52（304101）、"
                                          "隐士 智力 51→41 与 灵巧 +20（306000）、隐士 集中力 30→17（306101）、"
                                          "复仇者 血量 880 / 专注值 145 / 精力 100"
                                          "（L15 基础 生命力 35 / 集中力 31 / 耐力 21 叠加 305001 → 40 / 20 / 26）；"
                                          "Fextralife 的词条页写出的数字也正是 L12 行。见 sources 里的三条外部证据。",
            "modifierMidLevelsVerified": False,
            "modifierInference": "L12 = 满级效果、13–15 沿用 L12 这一段已实测确认（见 modifierAnchorVerification）；"
                                 "真正还没实测的只剩 **2–11 级**的逐级数值与取整方向（floor vs trunc），"
                                 "statModifiers[].levels[].inferred = true 标出。"
                                 "floor 与 trunc 结果不同的等级另给 deltaFloorAlt。",
            "libraRule": "利普拉的交易是整套替换（heroStatusId），替换后的表与角色基础表用同一套插值规则；"
                         "转职遗物是在当前基础表上加减（heroStatusModifier），两者字段不同、可同时生效（推断）。",
        },
        "relicPools": {
            str(pool_id): summary
            for pool_id, summary in sorted(relics.pool_summary.items())
            if any(pool_id in m["rollablePoolIds"] for m in modifiers)
        },
        "counts": {
            "heroes": len(heroes),
            "levelsPerHero": len(LEVELS),
            "statModifiers": len(modifiers),
            "libraRespecs": len(respecs),
            "modifiersWithRelicItem": sum(1 for m in modifiers if m["relicItems"]),
            "dlcOnlyStatModifiers": sum(1 for m in modifiers if m["dlcOnly"]),
        },
        "caveats": CAVEATS,
        "heroes": heroes,
        "statModifiers": modifiers,
        "libraRespecs": respecs,
    }

    self_check(payload)

    args.out.parent.mkdir(parents=True, exist_ok=True)
    if args.pretty:
        body = json.dumps(payload, ensure_ascii=False, indent=1)
    else:
        body = json.dumps(payload, ensure_ascii=False, separators=(",", ":"))
    args.out.write_text(body + "\n", encoding="utf-8")

    size = args.out.stat().st_size
    no_relic = [m["affixId"] for m in modifiers if not m["relicItems"]]
    print(f"heroes.json：角色 {len(heroes)} 个 × {len(LEVELS)} 级、"
          f"转职遗物 {len(modifiers)} 条、利普拉交易 {len(respecs)} 套 → {args.out}"
          f"（{size} 字节 = {size / 1024:.1f} KB）")
    print(f"  自检通过：所有角色锚点级 = 原始行；属性与派生值单调；"
          f"{len(modifiers)} 条修饰各归一个角色、每级 delta 落在两锚点之间；5 套利普拉表齐全。")
    for pool_id, summary in payload["relicPools"].items():
        print(f"  随机池 {pool_id}：遗物 {summary['relicCount']} 件 / "
              f"去重后 {summary['distinctNameCount']} 个名字（中英文按遗物 ID 配对）")
    dlc_only = [m["affixId"] for m in modifiers if m["dlcOnly"]]
    if dlc_only:
        print(f"  仅 DLC 权重才掉得出来的词条（基础权重 0）：{dlc_only}")
    for check in payload["crossChecks"]:
        state = "全中" if check["mismatchCount"] == 0 else f"{check['mismatchCount']} 格不同（已知差异）"
        print(f"  外部表比对 {check['heroNameZh']}：{check['cellsCompared']} 格 → {state}")
    if no_relic:
        print(f"  ⚠ 没找到固定槽遗物的词条：{no_relic}")


if __name__ == "__main__":
    main()
