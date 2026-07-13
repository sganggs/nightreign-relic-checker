#!/usr/bin/env python3
"""Build the Nightreign relic-affix dataset used by the desktop checker.

The authoritative mechanics fields come from unpacked game params/text in the
Nightreign Save Editor repository. NightreignQuickRef is enrichment only: it
adds user-facing categories, explanations, and stackability notes. An archived
copy of the retired dingdangmarket API contributes aliases and popularity.
"""

from __future__ import annotations

import csv
import hashlib
import json
import re
import unicodedata
import xml.etree.ElementTree as ET
from collections import defaultdict
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[2]
OUT_DIR = Path(__file__).resolve().parent

SAVE_RESOURCES = ROOT / "work/editor/src/Resources"
QUICKREF_DIR = ROOT / "work/quickref/src/data/zh-CN"
ARCHIVED_EFFECTS = ROOT / "work/relics_id_decoded.json"
ARCHIVED_HOT = ROOT / "work/archive_hot-relics.json"
ARCHIVED_COMPOUNDS = ROOT / "work/archive_hot-compounds.json"

PARAM_EFFECTS = SAVE_RESOURCES / "Param/AttachEffectParam.csv"
PARAM_POOLS = SAVE_RESOURCES / "Param/AttachEffectTableParam.csv"
PARAM_RELICS = SAVE_RESOURCES / "Param/EquipParamAntique.csv"
FMG_FILES = [
    SAVE_RESOURCES / "Text/zh_CN/AttachEffectName.fmg.xml",
    SAVE_RESOURCES / "Text/zh_CN/AttachEffectName_dlc01.fmg.xml",
]
QUICKREF_OUTSIDE = QUICKREF_DIR / "outsider_entries_zh-CN.json"
QUICKREF_DEEP = QUICKREF_DIR / "deep_night_entries.json"

LEGACY_NORMAL_POOLS = (100, 200, 300)
CURRENT_NORMAL_POOLS = (110, 210, 310)
DEEP_POSITIVE_POOLS = (2_000_000, 2_100_000, 2_200_000)
DEEP_CURSE_POOL = 3_000_000

SAVE_EDITOR_COMMIT = "0d2ad1494c372098e689c23159656df70ff2d76d"
QUICKREF_COMMIT = "3e23450094c18125ae5665927ed240b18189a040"
SMITHBOX_COMMIT = "b1b644a770f8cc4c8cab452da3a72ff7b91e105a"

CHARACTER_FIELDS = (
    ("allowWylder", "Wylder"),
    ("allowGuardian", "Guardian"),
    ("allowIroneye", "Ironeye"),
    ("allowDuchess", "Duchess"),
    ("allowRaider", "Raider"),
    ("allowRevenant", "Revenant"),
    ("allowRecluse", "Recluse"),
    ("allowExecutor", "Executor"),
    ("allowScholar", "Scholar"),
    ("allowUndertaker", "Undertaker"),
)

KNOWN_COMPATIBILITY_LABELS = {
    100: "攻击力类",
    200: "出击武器附加属性／异常状态",
    300: "出击武器战技／法术",
    800: "特定魔法／祷告流派强化",
    900: "角色专属",
    6_630_000: "潜在能力武器发现",
    7_082_500: "装备三把以上法术触媒",
    7_082_700: "装备三把以上盾牌",
    7_260_300: "对异常状态敌人强化攻击",
    7_340_000: "特定武器攻击恢复血量",
    7_350_000: "特定武器攻击恢复专注值",
}


def read_csv(path: Path) -> list[dict[str, str]]:
    with path.open("r", encoding="utf-8-sig", newline="") as handle:
        return list(csv.DictReader(handle))


def read_json(path: Path) -> Any:
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def clean_text(value: Any) -> str | None:
    if value is None:
        return None
    text = re.sub(r"\s+", " ", str(value)).strip()
    if not text or text == "%null%":
        return None
    return text


def normalize_name(value: str) -> str:
    text = unicodedata.normalize("NFKC", value).lower()
    return re.sub(r"[\s，,。；;：:、‘’“”'\"「」『』（）()※·・\-—_]+", "", text)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def effective_weight(base_weight: int, dlc_weight: int) -> int:
    """Match the save editor's final-weight rule.

    A positive DLC weight overrides the base weight. DLC weight -1 means use
    the base weight. Zero in either final position means the effect cannot roll.
    """

    if dlc_weight > 0:
        return dlc_weight
    if dlc_weight == -1 and base_weight != 0:
        return base_weight
    return 0


def load_fmg_names() -> dict[int, str]:
    names: dict[int, str] = {}
    for path in FMG_FILES:
        for node in ET.parse(path).getroot().iter("text"):
            text = clean_text(node.text)
            if text:
                names[int(node.attrib["id"])] = text
    return names


def quickref_subset(entry: dict[str, Any], *, deep: bool) -> dict[str, Any]:
    result: dict[str, Any] = {}
    field_map = {
        "entry_name": "nameZh",
        "entry_type": "category",
        "explanation": "explanation",
        "superposability": "stackability",
        "buff_type": "buffType",
    }
    for source_key, target_key in field_map.items():
        value = clean_text(entry.get(source_key))
        if value:
            result[target_key] = value
    result["source"] = "NightreignQuickRef/deep" if deep else "NightreignQuickRef/outside"
    return result


def pool_membership(
    effect_id: int,
    pool_rows: dict[int, dict[int, dict[str, int]]],
    pool_ids: tuple[int, ...],
) -> tuple[bool, dict[str, dict[str, int]]]:
    weights: dict[str, dict[str, int]] = {}
    eligible = False
    for pool_id in pool_ids:
        row = pool_rows.get(pool_id, {}).get(effect_id)
        if not row:
            continue
        weights[str(pool_id)] = row
        eligible = eligible or row["effective"] != 0
    return eligible, weights


def availability_type(
    *, legacy: bool, current: bool, deep: bool, curse: bool
) -> str:
    if curse:
        return "deep-curse"
    if current and deep:
        return "normal-and-deep-positive"
    if current or legacy:
        return "normal-positive"
    if deep:
        return "deep-positive"
    return "fixed-or-reference-only"


def rollable_effects(
    pool_rows: dict[int, dict[int, dict[str, int]]], pool_id: int
) -> set[int]:
    return {
        effect_id
        for effect_id, weights in pool_rows.get(pool_id, {}).items()
        if weights["effective"] != 0
    }


def main() -> None:
    required = [
        PARAM_EFFECTS,
        PARAM_POOLS,
        PARAM_RELICS,
        *FMG_FILES,
        QUICKREF_OUTSIDE,
        QUICKREF_DEEP,
        ARCHIVED_EFFECTS,
        ARCHIVED_HOT,
        ARCHIVED_COMPOUNDS,
    ]
    missing = [str(path) for path in required if not path.exists()]
    if missing:
        raise FileNotFoundError("Missing input files:\n" + "\n".join(missing))

    effect_rows = read_csv(PARAM_EFFECTS)
    effect_params = {int(row["ID"]): row for row in effect_rows}
    fmg_names = load_fmg_names()

    pool_rows: dict[int, dict[int, dict[str, int]]] = defaultdict(dict)
    for row in read_csv(PARAM_POOLS):
        pool_id = int(row["ID"])
        effect_id = int(row["attachEffectId"])
        base_weight = int(row["chanceWeight"])
        dlc_weight = int(row["chanceWeight_dlc"])
        pool_rows[pool_id][effect_id] = {
            "base": base_weight,
            "dlc": dlc_weight,
            "effective": effective_weight(base_weight, dlc_weight),
        }

    legacy_slot_sets = [rollable_effects(pool_rows, pool_id) for pool_id in LEGACY_NORMAL_POOLS]
    current_slot_sets = [rollable_effects(pool_rows, pool_id) for pool_id in CURRENT_NORMAL_POOLS]
    if not all(slot_set == legacy_slot_sets[0] for slot_set in legacy_slot_sets[1:]):
        raise ValueError("Legacy normal slot pools no longer have identical candidate sets")
    if not all(slot_set == current_slot_sets[0] for slot_set in current_slot_sets[1:]):
        raise ValueError("Current normal slot pools no longer have identical candidate sets")
    if not legacy_slot_sets[0].issubset(current_slot_sets[0]):
        raise ValueError("Current normal pool is unexpectedly missing legacy effects")

    relic_params = {int(row["ID"]): row for row in read_csv(PARAM_RELICS)}
    reward_pool_ids = tuple(
        sorted(pool_id for pool_id in pool_rows if 1_000_000 <= pool_id <= 1_009_999)
    )
    if len(reward_pool_ids) != 30:
        raise ValueError(f"Expected 30 normal reward pools, found {len(reward_pool_ids)}")
    if any(
        rollable_effects(pool_rows, pool_id) != current_slot_sets[0]
        for pool_id in reward_pool_ids
    ):
        raise ValueError("A normal expedition-reward pool differs from the current candidate set")

    def audit_normal_colors(min_id: int, max_id: int) -> dict[str, Any]:
        sequences: dict[tuple[int, int, int], set[int]] = defaultdict(set)
        row_count = 0
        for relic_id, row in relic_params.items():
            if not min_id <= relic_id <= max_id:
                continue
            sequence = tuple(
                int(row[f"attachEffectTableId_{index}"]) for index in (1, 2, 3)
            )
            sequences[sequence].add(int(row["relicColor"]))
            row_count += 1
        all_four = all(colors == {0, 1, 2, 3} for colors in sequences.values())
        if not all_four:
            raise ValueError(f"Not every random pool sequence in {min_id}-{max_id} covers four colors")
        return {
            "relicRowCount": row_count,
            "distinctPoolSequences": len(sequences),
            "everyPoolSequenceHasColors": [0, 1, 2, 3],
        }

    normal_color_audit = {
        "storeRelics": audit_normal_colors(100, 235),
        "expeditionRewardRelics": audit_normal_colors(1_000_000, 1_009_999),
    }
    color_evidence_groups = {
        "normalLegacyGrand": (102, 111, 120, 129),
        "normalCurrentGrand": (202, 211, 220, 229),
    }
    color_pool_evidence: dict[str, list[dict[str, Any]]] = {}
    for label, relic_ids in color_evidence_groups.items():
        evidence: list[dict[str, Any]] = []
        for relic_id in relic_ids:
            row = relic_params[relic_id]
            evidence.append(
                {
                    "relicId": relic_id,
                    "colorId": int(row["relicColor"]),
                    "positivePools": [
                        int(row["attachEffectTableId_1"]),
                        int(row["attachEffectTableId_2"]),
                        int(row["attachEffectTableId_3"]),
                    ],
                }
            )
        if {item["colorId"] for item in evidence} != {0, 1, 2, 3}:
            raise ValueError(f"{label} does not cover all four normal relic colors")
        if len({tuple(item["positivePools"]) for item in evidence}) != 1:
            raise ValueError(f"{label} colors no longer share one effect-pool sequence")
        color_pool_evidence[label] = evidence

    outside_entries = {
        int(entry["entry_id"]): quickref_subset(entry, deep=False)
        for entry in read_json(QUICKREF_OUTSIDE)
    }
    deep_raw = read_json(QUICKREF_DEEP)
    deep_map = deep_raw[0] if isinstance(deep_raw, list) and deep_raw else {}
    deep_entries = {
        int(effect_id): quickref_subset(entry, deep=True)
        for effect_id, entry in deep_map.items()
    }

    archived_entries = read_json(ARCHIVED_EFFECTS)
    archived_names_by_id: dict[int, list[str]] = defaultdict(list)
    archived_ids_by_exact_name: dict[str, set[int]] = defaultdict(set)
    archived_ids_by_normalized_name: dict[str, set[int]] = defaultdict(set)
    for entry in archived_entries:
        effect_id = int(entry["ID"])
        name = clean_text(entry.get("name"))
        if not name:
            continue
        archived_names_by_id[effect_id].append(name)
        archived_ids_by_exact_name[name].add(effect_id)
        archived_ids_by_normalized_name[normalize_name(name)].add(effect_id)

    rollable_pool_ids = (
        *LEGACY_NORMAL_POOLS,
        *CURRENT_NORMAL_POOLS,
        *DEEP_POSITIVE_POOLS,
        DEEP_CURSE_POOL,
    )
    rollable_ids: set[int] = set()
    for pool_id in rollable_pool_ids:
        rollable_ids.update(
            effect_id
            for effect_id, weights in pool_rows.get(pool_id, {}).items()
            if weights["effective"] != 0
        )

    reference_ids = set(outside_entries) | set(deep_entries)
    excluded_reference_ids = sorted(reference_ids - set(effect_params))
    candidate_ids = sorted(rollable_ids | (reference_ids & set(effect_params)))

    current_ids = set().union(*current_slot_sets)
    current_group_sizes: dict[int, int] = defaultdict(int)
    for effect_id in current_ids:
        current_group_sizes[int(effect_params[effect_id]["compatibilityId"])] += 1

    records: list[dict[str, Any]] = []
    records_by_id: dict[int, dict[str, Any]] = {}
    for effect_id in candidate_ids:
        param = effect_params[effect_id]
        compatibility_id = int(param["compatibilityId"])
        exclusivity_id = int(param["exclusivityId"])
        sort_id = int(param["overrideEffectId"])
        text_id = int(param["attachTextId"])

        eligible_legacy, legacy_weights = pool_membership(
            effect_id, pool_rows, LEGACY_NORMAL_POOLS
        )
        eligible_current, current_weights = pool_membership(
            effect_id, pool_rows, CURRENT_NORMAL_POOLS
        )
        eligible_deep, deep_weights = pool_membership(
            effect_id, pool_rows, DEEP_POSITIVE_POOLS
        )
        eligible_curse, curse_weights = pool_membership(
            effect_id, pool_rows, (DEEP_CURSE_POOL,)
        )

        outside = outside_entries.get(effect_id)
        deep_ref = deep_entries.get(effect_id)
        archived_names = archived_names_by_id.get(effect_id, [])
        official_name = fmg_names.get(text_id)

        if official_name:
            name_zh = official_name
            name_source = "game-fmg-zh_CN"
        elif outside and outside.get("nameZh"):
            name_zh = outside["nameZh"]
            name_source = "NightreignQuickRef/outside"
        elif deep_ref and deep_ref.get("nameZh"):
            name_zh = deep_ref["nameZh"]
            name_source = "NightreignQuickRef/deep"
        elif archived_names:
            name_zh = archived_names[0]
            name_source = "dingdangmarket-archive"
        else:
            name_zh = f"未命名词条 #{effect_id}"
            name_source = "generated-placeholder"

        aliases: list[str] = []
        alias_candidates = [
            official_name,
            outside.get("nameZh") if outside else None,
            deep_ref.get("nameZh") if deep_ref else None,
            *archived_names,
        ]
        seen_aliases = {name_zh}
        for alias in alias_candidates:
            alias = clean_text(alias)
            if alias and alias not in seen_aliases:
                aliases.append(alias)
                seen_aliases.add(alias)

        selected_ref: dict[str, Any] | None = None
        if eligible_current and outside:
            selected_ref = outside
        elif eligible_deep and deep_ref:
            selected_ref = deep_ref
        elif outside:
            selected_ref = outside
        elif deep_ref:
            selected_ref = deep_ref

        pool_a = deep_weights.get("2000000", {}).get("effective", 0) != 0
        pool_b = deep_weights.get("2100000", {}).get("effective", 0) != 0
        pool_c = deep_weights.get("2200000", {}).get("effective", 0) != 0
        requires_curse = pool_a and not (pool_b or pool_c)

        group_size = current_group_sizes.get(compatibility_id, 0)
        group_label = KNOWN_COMPATIBILITY_LABELS.get(compatibility_id)
        if not group_label and group_size > 1:
            group_label = "同系词条"

        sources = ["game-param/AttachEffectParam"]
        if official_name:
            sources.append("game-text/zh_CN-FMG")
        if outside:
            sources.append("NightreignQuickRef/outside")
        if deep_ref:
            sources.append("NightreignQuickRef/deep")
        if archived_names:
            sources.append("dingdangmarket-archive/relics-with-ID")

        record: dict[str, Any] = {
            "effectId": effect_id,
            "textId": text_id,
            "nameZh": name_zh,
            "nameSource": name_source,
            "aliases": aliases,
            "compatibilityId": compatibility_id,
            "compatibilityGroupLabel": group_label,
            "compatibilityGroupSizeNormalCurrent": group_size,
            "exclusivityId": exclusivity_id,
            "isDebuff": int(param["isDebuff"]) == 1,
            "allowedCharacters": [
                character
                for field, character in CHARACTER_FIELDS
                if int(param[field]) == 1
            ],
            "sortId": sort_id,
            "sortKey": [sort_id, effect_id],
            "type": availability_type(
                legacy=eligible_legacy,
                current=eligible_current,
                deep=eligible_deep,
                curse=eligible_curse,
            ),
            "category": selected_ref.get("category") if selected_ref else None,
            "categorySource": selected_ref.get("source") if selected_ref else None,
            "explanation": selected_ref.get("explanation") if selected_ref else None,
            "stackability": selected_ref.get("stackability") if selected_ref else None,
            "eligibleNormalLegacy": eligible_legacy,
            "eligibleNormalCurrent": eligible_current,
            "eligibleForNormalChecker": eligible_current and not eligible_curse,
            "eligibleDeep": eligible_deep,
            "eligibleDeepPoolA": pool_a,
            "eligibleDeepPoolB": pool_b,
            "eligibleDeepPoolC": pool_c,
            "requiresCurse": requires_curse,
            "isCurse": eligible_curse,
            "isRandomRollable": (
                eligible_legacy or eligible_current or eligible_deep or eligible_curse
            ),
            "isFixedOrReferenceOnly": not (
                eligible_legacy or eligible_current or eligible_deep or eligible_curse
            ),
            "poolWeights": {
                "normalLegacy": legacy_weights,
                "normalCurrent": current_weights,
                "deepPositive": deep_weights,
                "deepCurse": curse_weights,
            },
            "sources": sources,
        }
        quickref: dict[str, Any] = {}
        if outside:
            quickref["outside"] = outside
        if deep_ref:
            quickref["deep"] = deep_ref
        if quickref:
            record["quickRef"] = quickref
        records.append(record)
        records_by_id[effect_id] = record

    legacy_order = sorted(
        (record for record in records if record["eligibleNormalLegacy"]),
        key=lambda record: tuple(record["sortKey"]),
    )
    current_order = sorted(
        (record for record in records if record["eligibleNormalCurrent"]),
        key=lambda record: tuple(record["sortKey"]),
    )
    deep_order = sorted(
        (record for record in records if record["eligibleDeep"]),
        key=lambda record: tuple(record["sortKey"]),
    )
    for index, record in enumerate(legacy_order, start=1):
        record["normalLegacyOrderIndex"] = index
    for index, record in enumerate(current_order, start=1):
        record["normalCurrentOrderIndex"] = index
    for index, record in enumerate(deep_order, start=1):
        record["deepOrderIndex"] = index

    popularity_matches: list[dict[str, Any]] = []
    popularity_unmatched: list[dict[str, Any]] = []
    popularity_ambiguous: list[dict[str, Any]] = []
    hot_payload = read_json(ARCHIVED_HOT).get("data", {}).get("relics", [])
    for rank, item in enumerate(hot_payload, start=1):
        hot_name = clean_text(item.get("relic"))
        query_count = int(item["query_count"])
        if not hot_name:
            continue
        exact_ids = archived_ids_by_exact_name.get(hot_name, set())
        normalized_ids = archived_ids_by_normalized_name.get(normalize_name(hot_name), set())
        matched_via = "archived-exact-name"
        ids = exact_ids
        if not ids:
            ids = normalized_ids
            matched_via = "archived-normalized-name"
        ids = {effect_id for effect_id in ids if effect_id in records_by_id}
        if len(ids) == 1:
            effect_id = next(iter(ids))
            popularity = {
                "queryCount": query_count,
                "rank": rank,
                "sourceSnapshot": "2026-03-12",
                "matchedVia": matched_via,
                "archivedName": hot_name,
            }
            records_by_id[effect_id]["popularity"] = popularity
            popularity_matches.append({"effectId": effect_id, **popularity})
        elif len(ids) > 1:
            popularity_ambiguous.append(
                {"name": hot_name, "queryCount": query_count, "effectIds": sorted(ids)}
            )
        else:
            popularity_unmatched.append(
                {"name": hot_name, "queryCount": query_count}
            )

    compound_checks: list[dict[str, Any]] = []
    compound_unresolved: list[dict[str, Any]] = []
    compound_payload = read_json(ARCHIVED_COMPOUNDS).get("data", {}).get("compounds", [])
    for item in compound_payload:
        names = [clean_text(name) for name in item.get("relics", [])]
        effect_ids: list[int] = []
        ambiguous = False
        for name in names:
            ids = {
                effect_id
                for effect_id in archived_ids_by_exact_name.get(name or "", set())
                if effect_id in effect_params
            }
            if len(ids) != 1:
                ambiguous = True
                break
            effect_ids.append(next(iter(ids)))
        if ambiguous or len(effect_ids) != 3:
            compound_unresolved.append(
                {"names": names, "frequency": int(item.get("frequency", 0))}
            )
            continue
        sort_keys = [
            [int(effect_params[effect_id]["overrideEffectId"]), effect_id]
            for effect_id in effect_ids
        ]
        compatibility_ids = [
            int(effect_params[effect_id]["compatibilityId"])
            for effect_id in effect_ids
        ]
        compound_checks.append(
            {
                "effectIds": effect_ids,
                "sortKeys": sort_keys,
                "orderMatches": sort_keys == sorted(sort_keys),
                "compatibilityIds": compatibility_ids,
                "compatibilityDistinct": len(set(compatibility_ids)) == 3,
                "frequency": int(item.get("frequency", 0)),
            }
        )

    records.sort(key=lambda record: record["effectId"])
    unnamed = [record["effectId"] for record in records if record["nameSource"] == "generated-placeholder"]
    fallback_named = [
        record["effectId"]
        for record in records
        if record["nameSource"] not in {"game-fmg-zh_CN", "generated-placeholder"}
    ]

    counts = {
        "records": len(records),
        "eligibleNormalLegacy": sum(record["eligibleNormalLegacy"] for record in records),
        "eligibleNormalCurrent": sum(record["eligibleNormalCurrent"] for record in records),
        "eligibleDeepPositive": sum(record["eligibleDeep"] for record in records),
        "eligibleDeepPoolARequiresCurse": sum(record["requiresCurse"] for record in records),
        "deepCurses": sum(record["isCurse"] for record in records),
        "fixedOrReferenceOnly": sum(record["isFixedOrReferenceOnly"] for record in records),
        "officialFmgNames": sum(record["nameSource"] == "game-fmg-zh_CN" for record in records),
        "fallbackNames": len(fallback_named),
        "unnamedPlaceholders": len(unnamed),
        "withQuickRefCategory": sum(record["category"] is not None for record in records),
        "withPopularity": sum("popularity" in record for record in records),
    }

    source_files = [
        PARAM_EFFECTS,
        PARAM_POOLS,
        PARAM_RELICS,
        *FMG_FILES,
        QUICKREF_OUTSIDE,
        QUICKREF_DEEP,
        ARCHIVED_EFFECTS,
        ARCHIVED_HOT,
        ARCHIVED_COMPOUNDS,
    ]
    payload = {
        "schemaVersion": 1,
        "generatedAt": datetime.now(timezone.utc).replace(microsecond=0).isoformat(),
        "targetGameData": "v1.03.4 + DLC1",
        "sortRule": {
            "direction": "ascending",
            "keys": ["sortId (AttachEffectParam.overrideEffectId)", "effectId"],
        },
        "normalChecker": {
            "filter": "eligibleForNormalChecker == true",
            "requiredEffectCount": 3,
            "conflictRule": "effectId values and non--1 compatibilityId values must be pairwise distinct",
            "orderRule": "sort ascending by (sortId, effectId)",
            "colorRule": "random normal-affix pools are identical across red/blue/yellow/green; color does not change combination legality",
        },
        "poolDefinitions": {
            "normalLegacy": list(LEGACY_NORMAL_POOLS),
            "normalCurrent": list(CURRENT_NORMAL_POOLS),
            "deepPositive": list(DEEP_POSITIVE_POOLS),
            "deepCurse": [DEEP_CURSE_POOL],
        },
        "colorPoolEvidence": color_pool_evidence,
        "normalColorAudit": normal_color_audit,
        "counts": counts,
        "provenance": {
            "gameParamsAndZhText": {
                "repository": "https://github.com/alfizari/Elden-Ring-Nightreign-Save-Editor",
                "commit": SAVE_EDITOR_COMMIT,
                "repositoryLicense": "MIT",
                "note": "Extracted game parameter/text content remains subject to the game rightsholders' rights.",
            },
            "quickRefEnrichment": {
                "repository": "https://github.com/xxiixi/NightreignQuickRef",
                "commit": QUICKREF_COMMIT,
                "repositoryLicense": "GPL-3.0",
            },
            "paramFieldSemantics": {
                "repository": "https://github.com/vawser/Smithbox",
                "commit": SMITHBOX_COMMIT,
                "repositoryLicense": "MIT",
                "attachEffectAnnotations": "https://github.com/vawser/Smithbox/blob/b1b644a770f8cc4c8cab452da3a72ff7b91e105a/src/Smithbox.Data/Assets/PARAM/NR/Param%20Annotations/English/ATTACHEFFECT_PARAM_ST.json",
                "effectTableAnnotations": "https://github.com/vawser/Smithbox/blob/b1b644a770f8cc4c8cab452da3a72ff7b91e105a/src/Smithbox.Data/Assets/PARAM/NR/Param%20Annotations/English/ATTACHEFFECT_TABLE_PARAM_ST.json",
            },
            "dingdangmarketArchive": {
                "originalApi": "https://elden-api-v2.dingdangmarket.com",
                "waybackSnapshot": "2026-03-12",
                "effectListUrl": "https://web.archive.org/web/20260312030547id_/https://elden-api-v2.dingdangmarket.com/relics-with-ID",
                "hotRelicsUrl": "https://web.archive.org/web/20260312030548id_/https://elden-api-v2.dingdangmarket.com/hot-relics",
                "hotCompoundsUrl": "https://web.archive.org/web/20260312030549id_/https://elden-api-v2.dingdangmarket.com/hot-compounds",
            },
            "inputSha256": {
                str(path.relative_to(ROOT)): sha256(path) for path in source_files
            },
        },
        "affixes": records,
    }

    output_path = OUT_DIR / "affixes.json"
    with output_path.open("w", encoding="utf-8") as handle:
        json.dump(payload, handle, ensure_ascii=False, indent=2)
        handle.write("\n")

    report = f"""# 遗物词条数据集：来源与计数

生成文件：`affixes.json`  
目标数据版本：v1.03.4 + DLC1  
生成时间：{payload['generatedAt']}

## 可直接用于第一版普通遗物检查器的规则

- 下拉列表过滤：`eligibleForNormalChecker == true`（共 {counts['eligibleNormalCurrent']} 条）。
- 三条词条必须是三个不同 `effectId`，且非 `-1` 的 `compatibilityId` 两两不同。
- 正确显示／存档顺序：按 `(sortId, effectId)` 升序；`sortId` 就是游戏参数的 `overrideEffectId`。
- 普通随机遗物的红、蓝、黄、绿四种颜色使用相同词条池，颜色不改变组合合法性。
- 旧池为 100/200/300，共 {counts['eligibleNormalLegacy']} 条；当前池为 110/210/310，共 {counts['eligibleNormalCurrent']} 条。三个槽的候选集合相同，仅权重不同。
- 30 个远征奖励池的当前可抽候选集合也都与上述 {counts['eligibleNormalCurrent']} 条完全相同；商店 72 行、远征奖励 360 行中，每一种池序列都覆盖红蓝黄绿四色。

## 计数

- 数据记录：{counts['records']}
- 普通旧池可抽：{counts['eligibleNormalLegacy']}
- 普通当前池可抽：{counts['eligibleNormalCurrent']}
- 深夜正面可抽：{counts['eligibleDeepPositive']}
- 深夜 A 池且需要负面词条：{counts['eligibleDeepPoolARequiresCurse']}
- 深夜负面词条：{counts['deepCurses']}
- 固定／参考词条（不能进入随机普通检查器）：{counts['fixedOrReferenceOnly']}
- 官方简中 FMG 直接命名：{counts['officialFmgNames']}
- QuickRef／旧 API 补名：{counts['fallbackNames']}
- 仍无名称：{counts['unnamedPlaceholders']}
- 带 QuickRef 分类／说明：{counts['withQuickRefCategory']}
- 带旧站热门查询量：{counts['withPopularity']}

## 来源

1. 游戏参数、简中 FMG：[{SAVE_EDITOR_COMMIT[:12]}](https://github.com/alfizari/Elden-Ring-Nightreign-Save-Editor/tree/{SAVE_EDITOR_COMMIT})。参数文件最后更新于 2026-01，QuickRef 同期提交明确标注为 v1.03.4 数据。
2. 说明与分类：[{QUICKREF_COMMIT[:12]}](https://github.com/xxiixi/NightreignQuickRef/tree/{QUICKREF_COMMIT})。
3. 参数字段语义：[Smithbox Nightreign annotations](https://github.com/vawser/Smithbox/blob/{SMITHBOX_COMMIT}/src/Smithbox.Data/Assets/PARAM/NR/Param%20Annotations/English/ATTACHEFFECT_PARAM_ST.json)。其中明确说明相同 `compatibilityId` 不能同时出现在同一遗物／武器；`exclusivityId` 只控制已装备遗物间的红色感叹号提示，不能拿来判定单件遗物组合。
4. 热度与旧称：Wayback 保存的 [`relics-with-ID`](https://web.archive.org/web/20260312030547id_/https://elden-api-v2.dingdangmarket.com/relics-with-ID) 与 [`hot-relics`](https://web.archive.org/web/20260312030548id_/https://elden-api-v2.dingdangmarket.com/hot-relics)，快照日期 2026-03-12。

游戏参数决定合法性；QuickRef 与旧站数据只用于展示、别名、说明和热度，不覆盖参数字段。

许可提示：Save Editor 与 Smithbox 为 MIT；NightreignQuickRef 为 GPL-3.0。公开分发内嵌 QuickRef 说明的版本时，应保留来源、许可证并履行 GPL 要求；游戏 FMG 文本仍受游戏权利方权利约束。此处仅记录来源，不构成法律意见。

## 合并异常／保守处理

- QuickRef 中有 {len(excluded_reference_ids)} 个 ID 已不在当前 `AttachEffectParam`，已排除：{', '.join(map(str, excluded_reference_ids)) or '无'}。
- 热门词条成功按旧 API 的 effect ID 唯一匹配 {len(popularity_matches)} 条；歧义 {len(popularity_ambiguous)} 条；未匹配 {len(popularity_unmatched)} 条。
- 未匹配热门项：{', '.join(item['name'] for item in popularity_unmatched) or '无'}。
- 旧站 20 个热门组合中，{len(compound_checks)} 个能唯一还原为 effect ID；其中按 `(sortId, effectId)` 排序正确 {sum(item['orderMatches'] for item in compound_checks)} 个，`compatibilityId` 两两不同 {sum(item['compatibilityDistinct'] for item in compound_checks)} 个。其余 {len(compound_unresolved)} 个因旧站名称无法唯一映射而未用于结论。
- 对深夜遗物，本数据保留 A/B/C 池和诅咒标记，但第一版普通检查器不应显示 `isCurse == true` 或 `eligibleNormalCurrent == false` 的记录。
"""
    (OUT_DIR / "PROVENANCE.md").write_text(report, encoding="utf-8")

    diagnostics = {
        "excludedQuickRefIdsNotInCurrentParam": excluded_reference_ids,
        "unnamedEffectIds": unnamed,
        "fallbackNamedEffectIds": fallback_named,
        "popularityMatches": popularity_matches,
        "popularityAmbiguous": popularity_ambiguous,
        "popularityUnmatched": popularity_unmatched,
        "archivedHotCompoundChecks": compound_checks,
        "archivedHotCompoundUnresolved": compound_unresolved,
    }
    with (OUT_DIR / "diagnostics.json").open("w", encoding="utf-8") as handle:
        json.dump(diagnostics, handle, ensure_ascii=False, indent=2)
        handle.write("\n")

    print(json.dumps(counts, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
