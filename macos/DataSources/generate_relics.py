#!/usr/bin/env python3
"""生成遗物物品表数据（relics.json），供「存档检查」功能使用。

上游数据（与 generate_affixes.py 相同的固定修订）：
  Elden Ring Nightreign Save Editor，修订 0d2ad1494c372098e689c23159656df70ff2d76d
  - src/Resources/Param/EquipParamAntique.csv        遗物物品表（槽池模板、颜色、深夜标记）
  - src/Resources/Param/AttachEffectTableParam.csv   池成员与权重
  - src/Resources/Param/AttachEffectParam.csv        词条元数据（排序键、互斥组）
  - src/Resources/Text/zh_CN/AntiqueName(.dlc01).fmg.xml       遗物简中名
  - src/Resources/Text/zh_CN/AttachEffectName(.dlc01).fmg.xml  词条简中名

用法：
  python3 generate_relics.py <save-editor 检出目录> <输出 relics.json>

输出 schema（relicsSchemaVersion 1）：
  relics[]      每件遗物：id、name、color(0红/1蓝/2黄/3绿/4白)、deep、
                slots[3]（正面槽池 ID，-1 为无槽）、curseSlots[3]（诅咒槽池 ID）
  pools{}       每个被引用池的「可掉落词条 ID」集合（权重过滤规则与
                generate_affixes.py 一致：chanceWeight_dlc>0，或
                chanceWeight!=0 且 chanceWeight_dlc==-1）
  extraAffixes[] 被池引用但不在词条库（affixes.json）中的词条的最小元数据，
                用于固定词条遗物的名称显示与顺序/互斥校验
"""

import csv
import json
import sys
import xml.etree.ElementTree as ET
from datetime import datetime, timezone
from pathlib import Path

CATALOG = Path(__file__).resolve().parents[2] / "data" / "nightreign-affixes-v1.03.4.json"


def load_fmg(path: Path) -> dict[int, str]:
    if not path.exists():
        return {}
    out = {}
    for node in ET.parse(path).getroot().iter("text"):
        text = (node.text or "").strip()
        if text and text != "%null%":
            out[int(node.attrib["id"])] = text
    return out


def rollable(weight: int, weight_dlc: int) -> bool:
    # 与 Save Editor df_filter_zero_chanceWeight / generate_affixes.py 相同：
    # dlc 权重 >0 即可掉落；dlc 为 -1（无覆盖）时看本体权重是否非零。
    if weight_dlc > 0:
        return True
    return weight != 0 and weight_dlc == -1


def main() -> None:
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    sed = Path(sys.argv[1])
    out_path = Path(sys.argv[2])
    param = sed / "src" / "Resources" / "Param"
    text = sed / "src" / "Resources" / "Text" / "zh_CN"

    antique_names = load_fmg(text / "AntiqueName.fmg.xml")
    antique_names_dlc = load_fmg(text / "AntiqueName_dlc01.fmg.xml")
    effect_names = load_fmg(text / "AttachEffectName.fmg.xml")
    effect_names.update(load_fmg(text / "AttachEffectName_dlc01.fmg.xml"))

    relics = []
    pools_used: set[int] = set()
    with open(param / "EquipParamAntique.csv", newline="") as f:
        for row in csv.DictReader(f):
            rid = int(row["ID"])
            slots = [int(row[f"attachEffectTableId_{i}"]) for i in (1, 2, 3)]
            curse_slots = [int(row[f"attachEffectTableId_curse{i}"]) for i in (1, 2, 3)]
            pools_used.update(p for p in slots + curse_slots if p != -1)
            name = antique_names_dlc.get(rid) or antique_names.get(rid) or ""
            relics.append(
                {
                    "id": rid,
                    "name": name,
                    "color": int(row["relicColor"]),
                    "deep": row["isDeepRelic"] == "1",
                    "slots": slots,
                    "curseSlots": curse_slots,
                }
            )

    pools: dict[int, list[int]] = {p: [] for p in pools_used}
    referenced_effects: set[int] = set()
    with open(param / "AttachEffectTableParam.csv", newline="") as f:
        for row in csv.DictReader(f):
            pool = int(row["ID"])
            if pool not in pools:
                continue
            if rollable(int(row["chanceWeight"]), int(row["chanceWeight_dlc"])):
                eid = int(row["attachEffectId"])
                pools[pool].append(eid)
                referenced_effects.add(eid)
    for pool in pools.values():
        pool.sort()
    empty = [p for p, members in pools.items() if not members]
    if empty:
        print(f"警告：{len(empty)} 个被引用池无可掉落词条（样例 {sorted(empty)[:5]}）", file=sys.stderr)

    catalog = json.loads(CATALOG.read_text())
    known = {a["effectId"] for a in catalog["affixes"]}
    extra = []
    with open(param / "AttachEffectParam.csv", newline="") as f:
        for row in csv.DictReader(f):
            eid = int(row["ID"])
            if eid in known or eid not in referenced_effects:
                continue
            extra.append(
                {
                    "effectId": eid,
                    "name": effect_names.get(int(row["attachTextId"]), f"词条 {eid}"),
                    "sortId": int(row["overrideEffectId"]),
                    "compatibilityId": int(row["compatibilityId"]),
                }
            )
    extra.sort(key=lambda a: a["effectId"])

    out = {
        "relicsSchemaVersion": 1,
        "gameVersion": catalog["gameVersion"],
        "dataVersion": catalog["dataVersion"],
        "generatedAt": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "sources": [
            {
                "name": "Elden Ring Nightreign Save Editor",
                "url": "https://github.com/alfizari/Elden-Ring-Nightreign-Save-Editor",
                "revision": "0d2ad1494c372098e689c23159656df70ff2d76d",
                "license": "MIT",
                "usage": "EquipParamAntique / AttachEffectTableParam / AttachEffectParam / AntiqueName FMG / AttachEffectName FMG",
            }
        ],
        "relics": relics,
        "pools": {str(k): v for k, v in sorted(pools.items())},
        "extraAffixes": extra,
    }
    out_path.write_text(json.dumps(out, ensure_ascii=False, separators=(",", ":")) + "\n")
    named = sum(1 for r in relics if r["name"])
    print(
        f"relics.json：{len(relics)} 件遗物（{named} 件有名称，深夜 {sum(1 for r in relics if r['deep'])} 件）、"
        f"{len(pools)} 个池、{len(extra)} 条补充词条 → {out_path}（{out_path.stat().st_size // 1024} KB）"
    )


if __name__ == "__main__":
    main()
