#!/usr/bin/env python3
# /// script
# requires-python = ">=3.11"
# dependencies = ["pycryptodome>=3.20", "zstandard>=0.22"]
# ///
"""从《黑夜君临》的 data*.bhd/bdt 归档里取出全部地图 MSB（/map/mapstudio/*.msb.dcx），
把「敌人放置」导出成 CSV，供 generate_bosses.py 判定每一行 NpcParam 在哪种场合出现。

为什么需要它：NpcParam 自己没有「出现在哪」的字段。决定一只敌人在哪登场的是地图文件
MSB 里的 Enemy part（每个 part 带 npcParamId），再由参数表决定这张地图块什么时候被放进
远征：LotResultPlayAreaParam.bossId1/2（夜晚首领地图块）、LotResultSmallBaseAndSpot
（据点/野外首领/封印监牢等地图块挂到哪个挂点）、SmallBaseAndSpotAttachPoint.defaultSmallBase
（大据点挂点的默认地块）。本脚本只负责前半段：地图 → npcParamId。

流程：复用 extract_msg.py 的 BHD5 解密 / 路径哈希 / DCX 解压；归档只存 64 位路径哈希，
所以先对 /map/mapstudio/mAA_BB_CC_DD.msb.dcx（AA..DD 各 00–99）逐一算哈希找出实际存在的
文件（约 1 分半）；KRAK 压缩可以用 --krak-batch-cmd 一次解完（oodledec.exe --batch），
也可以沿用 extract_msg.py 的逐个 --krak-cmd。MSB 布局对照 Smithbox 仓库
Documentation/Binary Templates/MSB/MSB_NR（TKGP 的 010 Editor 模板，Paramdex 同一修订）：
  * 文件头 16 字节，之后依次是 MODEL/EVENT/POINT/ROUTE/LAYER/PARTS 六个 param，
    每个 param = version(i32) count(i32) nameOffset(i64) offsets[count-1](i64) next(i64)；
  * Part：type 在 +0x0C（2 = Enemy，10 = DummyEnemy），modelIndex +0x14，
    commonOffset +0x60，typeOffset +0x68（均相对 part 起点）；
  * PartCommon：entityId +0x00，entityGroupIds[8] +0x1C；
  * PartEnemy：npcThinkParamId +0x08，npcParamId +0x0C，talkId +0x10，charaInitParamId +0x18。

输出（均在 --out 下，默认 raw/msb/，与 raw/params 一样不入 git）：
  MsbEnemyParts.csv  每个 Enemy / DummyEnemy part 一行：
      map, partName, partType(enemy|dummy), model, entityId, entityGroupIds(空格分隔),
      npcParamId, npcThinkParamId, talkId, charaInitParamId
  manifest.json      地图清单、各地图 part 数、生成参数

用法：
    uv run extract_msb.py --game "<...>/ELDEN RING NIGHTREIGN/Game" \\
        --krak-batch-cmd "'<wine>' --bottle Steam --no-gui 'Z:\\...\\oodledec.exe' \\
                          'Z:\\...\\oo2core_9_win64.dll' --batch {win_manifest}" \\
        [--out raw/msb] [--maps m46_56_00_00,m49_24_00_00]
"""
from __future__ import annotations

import argparse
import csv
import json
import os
import shlex
import struct
import subprocess
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from extract_msg import ER_HASH_PRIME, Archives, _to_win_path, dcx_decompress  # noqa: E402

MSB_DIR = "/map/mapstudio/"
PART_ENEMY, PART_DUMMY_ENEMY = 2, 10
MASK64 = 0xFFFFFFFFFFFFFFFF
CSV_COLUMNS = ["map", "partName", "partType", "model", "entityId", "entityGroupIds",
               "npcParamId", "npcThinkParamId", "talkId", "charaInitParamId"]


# ---------- 找出归档里实际存在的 MSB ----------

def _extend(h: int, text: str) -> int:
    for ch in text:
        h = (h * ER_HASH_PRIME + ord(ch)) & MASK64
    return h


def enumerate_msbs(arc: Archives) -> list[str]:
    """归档只存路径哈希：对 mAA_BB_CC_DD（各 00–99）逐一增量算哈希，返回命中的地图名。"""
    keys = arc.index
    base = _extend(0, MSB_DIR + "m")
    found = []
    for a in range(100):
        ha = _extend(base, f"{a:02d}_")
        for b in range(100):
            hb = _extend(ha, f"{b:02d}_")
            for c in range(100):
                hc = _extend(hb, f"{c:02d}_")
                for d in range(100):
                    if _extend(hc, f"{d:02d}.msb.dcx") in keys:
                        found.append(f"m{a:02d}_{b:02d}_{c:02d}_{d:02d}")
    return found


# ---------- DCX（KRAK 批量） ----------

def _dcx_payload(d: bytes) -> tuple[bytes, bytes, int]:
    fmt = d[0x28:0x2C]
    unc = struct.unpack(">I", d[0x1C:0x20])[0]
    comp = struct.unpack(">I", d[0x20:0x24])[0]
    dca = d.find(b"DCA\0", 0x40, 0x80)
    off = dca + struct.unpack(">I", d[dca + 4:dca + 8])[0]
    return fmt, d[off:off + comp], unc


def krak_batch(items: dict[str, tuple[bytes, int]], cmd: str) -> dict[str, bytes]:
    """一次调用外部命令解完整批 KRAK。items: 名字 → (压缩数据, 解压后长度)。"""
    out: dict[str, bytes] = {}
    with tempfile.TemporaryDirectory() as td:
        lines = []
        for name, (payload, unc) in items.items():
            src, dst = os.path.join(td, name + ".krak"), os.path.join(td, name + ".bin")
            with open(src, "wb") as fp:
                fp.write(payload)
            lines.append(f"{_to_win_path(src)}\t{_to_win_path(dst)}\t{unc}")
        manifest = os.path.join(td, "manifest.txt")
        with open(manifest, "w", encoding="utf-8") as fp:
            fp.write("\n".join(lines) + "\n")
        sub = {"{manifest}": manifest, "{win_manifest}": _to_win_path(manifest)}
        argv = []
        for tok in shlex.split(cmd):
            for k, v in sub.items():
                tok = tok.replace(k, v)
            argv.append(tok)
        r = subprocess.run(argv, capture_output=True, text=True)
        for name, (_, unc) in items.items():
            path = os.path.join(td, name + ".bin")
            if not os.path.exists(path):
                raise RuntimeError("Kraken 批量解压失败（%s）：%s" % (name, (r.stderr or r.stdout).strip()[-400:]))
            with open(path, "rb") as fp:
                data = fp.read()
            if len(data) != unc:
                raise ValueError("%s：解压长度不符 %d != %d" % (name, len(data), unc))
            out[name] = data
    return out


# ---------- MSB ----------

def _wstr(b: bytes, off: int) -> str:
    end = off
    while b[end:end + 2] != b"\0\0":
        end += 2
    return b[off:end].decode("utf-16-le")


def _params(b: bytes) -> dict[str, tuple[int, ...]]:
    if b[:4] != b"MSB ":
        raise ValueError("不是 MSB 文件")
    pos, out = 0x10, {}
    while True:
        _ver, cnt, name_off = struct.unpack_from("<iiq", b, pos)
        offs = struct.unpack_from("<%dq" % (cnt - 1), b, pos + 16)
        nxt = struct.unpack_from("<q", b, pos + 16 + 8 * (cnt - 1))[0]
        out[_wstr(b, name_off)] = offs
        if nxt == 0:
            return out
        pos = nxt


def parse_enemies(map_name: str, b: bytes) -> list[dict]:
    ps = _params(b)
    models = [_wstr(b, o + struct.unpack_from("<q", b, o)[0]) for o in ps["MODEL_PARAM_ST"]]
    rows = []
    for o in ps["PARTS_PARAM_ST"]:
        name_off, _part_no, ptype, _tidx, midx = struct.unpack_from("<qiiii", b, o)
        if ptype not in (PART_ENEMY, PART_DUMMY_ENEMY):
            continue
        common_off, type_off = struct.unpack_from("<qq", b, o + 0x60)
        c, t = o + common_off, o + type_off
        entity = struct.unpack_from("<I", b, c)[0]
        groups = [g for g in struct.unpack_from("<8I", b, c + 0x1C) if g]
        _u0, _u4, think, npc, talk = struct.unpack_from("<iiiii", b, t)
        chara_init = struct.unpack_from("<i", b, t + 0x18)[0]
        rows.append({
            "map": map_name,
            "partName": _wstr(b, o + name_off),
            "partType": "enemy" if ptype == PART_ENEMY else "dummy",
            "model": models[midx] if 0 <= midx < len(models) else "",
            "entityId": entity,
            "entityGroupIds": " ".join(str(g) for g in groups),
            "npcParamId": npc,
            "npcThinkParamId": think,
            "talkId": talk,
            "charaInitParamId": chara_init,
        })
    return rows


# ---------- 主流程 ----------

def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--game", required=True)
    ap.add_argument("--krak-batch-cmd", help="批量 Kraken 解压命令模板，占位符 {manifest} / {win_manifest}")
    ap.add_argument("--krak-cmd", help="逐个解压的命令模板（与 extract_msg.py 相同），没有批量命令时使用")
    ap.add_argument("--out", default=os.path.join(os.path.dirname(os.path.abspath(__file__)), "raw", "msb"))
    ap.add_argument("--maps", help="逗号分隔的地图名（如 m46_56_00_00），省略则枚举全部")
    args = ap.parse_args()

    arc = Archives(args.game)
    if args.maps:
        maps = [m.strip() for m in args.maps.split(",") if m.strip()]
    else:
        maps = enumerate_msbs(arc)
    print("找到 %d 张地图 MSB" % len(maps), file=sys.stderr)

    raw: dict[str, bytes] = {}
    krak: dict[str, tuple[bytes, int]] = {}
    for m in maps:
        d = arc.read(MSB_DIR + m + ".msb.dcx")
        if d[:4] == b"DCX\0":
            fmt, payload, unc = _dcx_payload(d)
            if fmt == b"KRAK" and args.krak_batch_cmd:
                krak[m] = (payload, unc)
                continue
            d = dcx_decompress(d, args.krak_cmd)
        raw[m] = d
    if krak:
        raw.update(krak_batch(krak, args.krak_batch_cmd))

    rows: list[dict] = []
    per_map: dict[str, dict[str, int]] = {}
    for m in sorted(raw):
        got = parse_enemies(m, raw[m])
        rows.extend(got)
        per_map[m] = {"enemy": sum(1 for r in got if r["partType"] == "enemy"),
                      "dummy": sum(1 for r in got if r["partType"] == "dummy")}

    os.makedirs(args.out, exist_ok=True)
    with open(os.path.join(args.out, "MsbEnemyParts.csv"), "w", newline="", encoding="utf-8") as fp:
        w = csv.DictWriter(fp, fieldnames=CSV_COLUMNS)
        w.writeheader()
        w.writerows(rows)
    with open(os.path.join(args.out, "manifest.json"), "w", encoding="utf-8") as fp:
        json.dump({
            "source": "/map/mapstudio/*.msb.dcx（data0–3 / dlc01 归档）",
            "layout": "Smithbox Documentation/Binary Templates/MSB/MSB_NR（Paramdex 同一修订）",
            "maps": len(per_map),
            "enemyParts": sum(v["enemy"] for v in per_map.values()),
            "dummyEnemyParts": sum(v["dummy"] for v in per_map.values()),
            "perMap": per_map,
        }, fp, ensure_ascii=False, indent=1)
    print("%d 张地图，Enemy %d 个、DummyEnemy %d 个 → %s" % (
        len(per_map), sum(v["enemy"] for v in per_map.values()),
        sum(v["dummy"] for v in per_map.values()), args.out))
    return 0


if __name__ == "__main__":
    sys.exit(main())
