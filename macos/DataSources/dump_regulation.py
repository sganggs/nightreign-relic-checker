#!/usr/bin/env python3
# /// script
# requires-python = ">=3.11"
# dependencies = ["pycryptodome>=3.20", "zstandard>=0.22"]
# ///
"""把《黑夜君临》的 regulation.bin 解成每张参数表一个 CSV。

流程：AES-256-CBC 解密 → DCX(ZSTD/DFLT) 解压 → BND4 容器 → 每个 .param 按
Smithbox Paramdex 的 paramdef XML 展开字段。二进制布局对照 SoulsFormats
（Smithbox 内嵌副本）的 BND4 / PARAM / PARAMDEF 实现。

用法：
    uv run dump_regulation.py --game "<...>/ELDEN RING NIGHTREIGN/Game" \
        --defs <paramdef 目录> --out raw/params [--rownames <Paramdex 行名目录>] \
        [--params NpcParam,SpEffectParam] [--list]
"""
from __future__ import annotations

import argparse
import csv
import hashlib
import json
import os
import re
import struct
import sys
import xml.etree.ElementTree as ET
import zlib
from dataclasses import dataclass

import zstandard
from Crypto.Cipher import AES

NR_REGULATION_KEY = bytes.fromhex(
    "9a8ee90c4c01a43168a17d9d75e4a7d02107ebcf43d5acb0554f941601b57918"
)
NR_STEAM_APPID = "2622380"


# ---------- 解密 / 解压 ----------

def decrypt_regulation(raw: bytes) -> bytes:
    iv, body = raw[:16], raw[16:]
    body += b"\0" * ((-len(body)) % 16)
    return AES.new(NR_REGULATION_KEY, AES.MODE_CBC, iv).decrypt(body)


def dcx_decompress(d: bytes) -> bytes:
    if d[:4] != b"DCX\0":
        raise ValueError("不是 DCX 数据：%r" % d[:8])
    fmt = d[0x28:0x2C]
    comp_size = struct.unpack(">I", d[0x20:0x24])[0]
    unc_size = struct.unpack(">I", d[0x1C:0x20])[0]
    if fmt == b"ZSTD":
        out = zstandard.ZstdDecompressor().decompressobj().decompress(d[0x4C:0x4C + comp_size])
    elif fmt == b"DFLT":
        out = zlib.decompress(d[0x4C:0x4C + comp_size])
    else:
        raise ValueError("暂不支持的 DCX 压缩格式：%r" % fmt)
    if len(out) != unc_size:
        raise ValueError("DCX 解压长度不符：%d != %d" % (len(out), unc_size))
    return out


# ---------- BND4 ----------

def _reverse_bits(b: int) -> int:
    return int("{:08b}".format(b)[::-1], 2)


def _cstr_utf16(buf: bytes, off: int) -> str:
    end = off
    while buf[end:end + 2] != b"\0\0":
        end += 2
    return buf[off:end].decode("utf-16-le")


@dataclass
class BndEntry:
    id: int
    name: str
    data: bytes


def read_bnd4(buf: bytes) -> tuple[str, list[BndEntry]]:
    if buf[:4] != b"BND4":
        raise ValueError("不是 BND4：%r" % buf[:4])
    big_endian = buf[9] != 0
    bit_big_endian = buf[10] == 0
    if big_endian:
        raise ValueError("不支持大端 BND4")
    file_count = struct.unpack_from("<i", buf, 0x0C)[0]
    version = buf[0x18:0x20].split(b"\0")[0].decode("ascii")
    file_header_size = struct.unpack_from("<q", buf, 0x20)[0]
    unicode = buf[0x30] != 0
    raw_format = buf[0x31]
    reverse = bit_big_endian or ((raw_format & 1) != 0 and (raw_format & 0x80) == 0)
    fmt = raw_format if reverse else _reverse_bits(raw_format)
    has_ids = bool(fmt & 0x02)
    has_names = bool(fmt & 0x0C)
    long_offsets = bool(fmt & 0x10)
    has_compression = bool(fmt & 0x20)

    entries = []
    pos = 0x40
    for _ in range(file_count):
        start = pos
        raw_flags = buf[pos]
        rev = bit_big_endian or ((raw_flags & 1) != 0 and (raw_flags & 0x80) == 0)
        flags = raw_flags if rev else _reverse_bits(raw_flags)
        pos += 4
        pos += 4  # -1
        comp_size = struct.unpack_from("<q", buf, pos)[0]
        pos += 8
        if has_compression:
            pos += 8  # uncompressed size
        if long_offsets:
            data_off = struct.unpack_from("<q", buf, pos)[0]
            pos += 8
        else:
            data_off = struct.unpack_from("<I", buf, pos)[0]
            pos += 4
        fid = -1
        if has_ids:
            fid = struct.unpack_from("<i", buf, pos)[0]
            pos += 4
        name = ""
        if has_names:
            name_off = struct.unpack_from("<I", buf, pos)[0]
            pos += 4
            name = _cstr_utf16(buf, name_off) if unicode else buf[name_off:buf.index(b"\0", name_off)].decode("shift_jis")
        if pos - start != file_header_size:
            raise ValueError("BND4 文件头长度不符：%d != %d" % (pos - start, file_header_size))
        data = buf[data_off:data_off + comp_size]
        if flags & 0x01:
            data = dcx_decompress(data)
        entries.append(BndEntry(fid, name, data))
    return version, entries


# ---------- PARAMDEF ----------

BIT_TYPES = {"s8": (8, True), "u8": (8, False), "s16": (16, True), "u16": (16, False),
             "s32": (32, True), "u32": (32, False), "dummy8": (8, False)}
FIXED_SIZE = {"b32": 4, "f32": 4, "angle32": 4, "f64": 8}
DEF_OUTER = re.compile(r"^(?P<type>\S+)\s+(?P<name>.+?)(?:\s*=\s*(?P<default>\S+))?$")
DEF_BIT = re.compile(r"^(?P<name>.+?)\s*:\s*(?P<size>\d+)$")
DEF_ARRAY = re.compile(r"^(?P<name>.+?)\s*\[\s*(?P<length>\d+)\]$")


@dataclass
class DefField:
    type: str
    name: str
    bit_size: int = -1
    array_len: int = 1
    display_name: str = ""
    first_version: int | None = None
    removed_version: int | None = None

    def valid_for(self, version: int) -> bool:
        return (self.first_version is None or version >= self.first_version) and (
            self.removed_version is None or version < self.removed_version)


@dataclass
class ParamDef:
    param_type: str
    data_version: int
    fields: list[DefField]
    source: str

    def row_size(self) -> int:
        size = 0
        bit_off, bit_limit = -1, -1
        for f in self.fields:
            if f.type in FIXED_SIZE:
                size += FIXED_SIZE[f.type]
                bit_off = -1
            elif f.type == "fixstr":
                size += f.array_len
                bit_off = -1
            elif f.type == "fixstrW":
                size += f.array_len * 2
                bit_off = -1
            elif f.type in BIT_TYPES:
                limit = BIT_TYPES[f.type][0]
                if f.bit_size == -1:
                    size += (limit // 8) * (f.array_len if f.type == "dummy8" else 1)
                    bit_off = -1
                else:
                    if bit_off == -1 or limit != bit_limit or bit_off + f.bit_size > bit_limit:
                        size += limit // 8
                        bit_off, bit_limit = 0, limit
                    bit_off += f.bit_size
            else:
                raise ValueError("未知字段类型 %s" % f.type)
        return size


def load_defs(def_dir: str, reg_version: int) -> dict[str, list[ParamDef]]:
    by_type: dict[str, list[ParamDef]] = {}
    for path in sorted(os.listdir(def_dir)):
        if not path.endswith(".xml"):
            continue
        root = ET.parse(os.path.join(def_dir, path)).getroot()
        ptype = root.findtext("ParamType")
        dv = root.findtext("DataVersion") or root.findtext("Unk06") or "0"
        fields = []
        for node in root.find("Fields"):
            m = DEF_OUTER.match(node.attrib["Def"])
            ftype, fname = m.group("type").strip(), m.group("name").strip()
            f = DefField(ftype, fname, display_name=node.findtext("DisplayName") or "")
            if node.get("FirstVersion"):
                f.first_version = int(node.get("FirstVersion"))
            if node.get("RemovedVersion"):
                f.removed_version = int(node.get("RemovedVersion"))
            if not f.valid_for(reg_version):
                continue
            mb = DEF_BIT.match(fname)
            ma = DEF_ARRAY.match(fname)
            if mb:
                f.name, f.bit_size = mb.group("name").strip(), int(mb.group("size"))
            elif ma:
                f.name, f.array_len = ma.group("name").strip(), int(ma.group("length"))
            fields.append(f)
        by_type.setdefault(ptype, []).append(ParamDef(ptype, int(dv), fields, path))
    return by_type


# ---------- PARAM ----------

@dataclass
class ParamRow:
    id: int
    name: str
    data_offset: int


@dataclass
class ParamFile:
    param_type: str
    data_version: int
    rows: list[ParamRow]
    detected_size: int
    buf: bytes


def read_param(buf: bytes) -> ParamFile:
    big_endian = buf[0x2C] == 0xFF
    if big_endian:
        raise ValueError("不支持大端 PARAM")
    f2d, f2e = buf[0x2D], buf[0x2E]
    flag01, int_off, long_off, off_ptype = f2d & 1, f2d & 2, f2d & 4, f2d & 0x80
    strings_off = struct.unpack_from("<I", buf, 0)[0]
    data_version = struct.unpack_from("<h", buf, 8)[0]
    row_count = struct.unpack_from("<H", buf, 0x0A)[0]
    if off_ptype:
        ptype_off = struct.unpack_from("<q", buf, 0x10)[0]
        param_type = buf[ptype_off:buf.index(b"\0", ptype_off)].decode("ascii")
        strings_off = min(strings_off, ptype_off) if strings_off else ptype_off
    else:
        param_type = buf[0x0C:0x2C].split(b"\0")[0].decode("ascii")
    pos = 0x30
    if (flag01 and int_off) or long_off:
        pos = 0x40
    unicode_names = bool(f2e & 1)
    rows = []
    for _ in range(row_count):
        if long_off:
            rid = struct.unpack_from("<i", buf, pos)[0]
            data_off = struct.unpack_from("<q", buf, pos + 8)[0]
            name_off = struct.unpack_from("<q", buf, pos + 16)[0]
            pos += 24
        else:
            rid, data_off, name_off = struct.unpack_from("<iII", buf, pos)
            pos += 12
        name = ""
        if name_off:
            strings_off = min(strings_off, name_off) if strings_off else name_off
            name = _cstr_utf16(buf, name_off) if unicode_names else buf[name_off:buf.index(b"\0", name_off)].decode("shift_jis", "replace")
        rows.append(ParamRow(rid, name, data_off))
    if len(rows) > 1:
        detected = rows[1].data_offset - rows[0].data_offset
    elif rows:
        detected = strings_off - rows[0].data_offset
    else:
        detected = -1
    return ParamFile(param_type, data_version, rows, detected, buf)


def _fmt_f32(v: float) -> str:
    """float32 的最短可回读十进制表示，优先不用科学计数法（120 而不是 1.2e+02）。"""
    if v != v:
        return "NaN"
    if v in (float("inf"), float("-inf")):
        return "inf" if v > 0 else "-inf"
    if v == int(v) and abs(v) < 1e15:
        return str(int(v))
    for p in range(1, 10):
        s = "%.*g" % (p, v)
        if struct.unpack("<f", struct.pack("<f", float(s)))[0] == v:
            if "e" in s and 1e-6 <= abs(v) < 1e15:
                fixed = ("%.20f" % float(s)).rstrip("0").rstrip(".")
                if struct.unpack("<f", struct.pack("<f", float(fixed)))[0] == v:
                    return fixed
            return s
    return repr(v)


def read_cells(buf: bytes, off: int, fields: list[DefField]) -> list:
    out = []
    bit_off, bit_limit, bit_val = -1, -1, 0
    for f in fields:
        t = f.type
        value = None
        if t == "b32":
            value = struct.unpack_from("<i", buf, off)[0]
            off += 4
        elif t in ("f32", "angle32"):
            value = _fmt_f32(struct.unpack_from("<f", buf, off)[0])
            off += 4
        elif t == "f64":
            value = repr(struct.unpack_from("<d", buf, off)[0])
            off += 8
        elif t == "fixstr":
            value = buf[off:off + f.array_len].split(b"\0")[0].decode("shift_jis", "replace")
            off += f.array_len
        elif t == "fixstrW":
            value = buf[off:off + f.array_len * 2].decode("utf-16-le", "replace").split("\0")[0]
            off += f.array_len * 2
        elif t in BIT_TYPES:
            limit, signed = BIT_TYPES[t]
            if f.bit_size == -1:
                if t == "dummy8":
                    value = buf[off:off + f.array_len].hex()
                    off += f.array_len
                else:
                    fmt = {8: "b", 16: "h", 32: "i"}[limit]
                    value = struct.unpack_from("<" + (fmt if signed else fmt.upper()), buf, off)[0]
                    off += limit // 8
            else:
                if bit_off == -1 or limit != bit_limit or bit_off + f.bit_size > bit_limit:
                    fmt = {8: "B", 16: "H", 32: "I"}[limit]
                    bit_val = struct.unpack_from("<" + fmt, buf, off)[0]
                    off += limit // 8
                    bit_off, bit_limit = 0, limit
                v = (bit_val >> bit_off) & ((1 << f.bit_size) - 1)
                if signed and v & (1 << (f.bit_size - 1)):
                    v -= 1 << f.bit_size
                bit_off += f.bit_size
                out.append(v)
                continue
        else:
            raise ValueError("未知字段类型 %s" % t)
        bit_off = -1
        out.append(value)
    return out


# ---------- 主流程 ----------

def sha256_file(path: str) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as fp:
        for chunk in iter(lambda: fp.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def exe_version(game_dir: str) -> str | None:
    exe = os.path.join(game_dir, "nightreign.exe")
    if not os.path.exists(exe):
        return None
    b = open(exe, "rb").read()
    key = "ProductVersion".encode("utf-16-le")
    i = b.find(key)
    if i < 0:
        return None
    seg = b[i + len(key):i + len(key) + 64].decode("utf-16-le", "ignore")
    m = re.search(r"\d+(?:\.\d+)+", seg)
    return m.group(0) if m else None


def steam_buildid(game_dir: str) -> str | None:
    manifest = os.path.join(game_dir, "..", "..", "..", "appmanifest_%s.acf" % NR_STEAM_APPID)
    if not os.path.exists(manifest):
        return None
    m = re.search(r'"buildid"\s+"(\d+)"', open(manifest, encoding="utf-8", errors="ignore").read())
    return m.group(1) if m else None


def load_rownames(path: str) -> dict[int, list[str]]:
    """Paramdex 行名：{"Entries": [{"ID": 110, "Entries": ["名1", "名2", ...]}]}。
    同一 ID 出现多行的表（如 AttachEffectTableParam）按出现次序依次取名。"""
    if not path or not os.path.exists(path):
        return {}
    data = json.load(open(path, encoding="utf-8"))
    return {int(item["ID"]): [str(v) for v in item.get("Entries", [])] for item in data.get("Entries", [])}


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--game", required=True, help="Game 目录（含 regulation.bin）或 regulation.bin 路径")
    ap.add_argument("--defs", required=True, help="Paramdex NR 的 Defs 目录")
    ap.add_argument("--out", required=True, help="CSV 输出目录")
    ap.add_argument("--rownames", help="Paramdex NR 的 Param Row Names/English 目录（可选，补英文行名）")
    ap.add_argument("--params", help="只导出这些表（逗号分隔，用 BND4 内的文件名，不含 .param）")
    ap.add_argument("--list", action="store_true", help="只列出表名和行数")
    ap.add_argument("--defs-rev", default="", help="记录到 manifest 的 paramdef 来源版本")
    args = ap.parse_args()

    reg_path = args.game if args.game.endswith(".bin") else os.path.join(args.game, "regulation.bin")
    game_dir = os.path.dirname(reg_path)
    raw = open(reg_path, "rb").read()
    bnd_version, entries = read_bnd4(dcx_decompress(decrypt_regulation(raw)))
    defs = load_defs(args.defs, int(bnd_version))
    wanted = set(args.params.split(",")) if args.params else None

    manifest = {
        "regulationVersion": bnd_version,
        "regulationSha256": sha256_file(reg_path),
        "regulationSize": len(raw),
        "exeVersion": exe_version(game_dir),
        "steamBuildId": steam_buildid(game_dir),
        "paramdefSource": args.defs_rev,
        "params": {},
    }
    os.makedirs(args.out, exist_ok=True)
    problems = 0
    for e in entries:
        stem = e.name.replace("\\", "/").rsplit("/", 1)[-1].removesuffix(".param")
        p = read_param(e.data)
        if args.list:
            print("%-52s %-40s rows=%-6d rowsize=%d" % (stem, p.param_type, len(p.rows), p.detected_size))
            continue
        if wanted and stem not in wanted:
            continue
        cands = defs.get(p.param_type, [])
        match = next((d for d in cands if d.data_version == p.data_version and (p.detected_size == -1 or d.row_size() == p.detected_size)), None)
        if match is None:
            match = next((d for d in cands if p.detected_size == -1 or d.row_size() == p.detected_size), None)
        info = {"paramType": p.param_type, "rows": len(p.rows), "detectedRowSize": p.detected_size,
                "dataVersion": p.data_version, "paramdef": match.source if match else None,
                "paramdefRowSize": match.row_size() if match else None, "paramdefDataVersion": match.data_version if match else None}
        manifest["params"][stem] = info
        if match is None:
            problems += 1
            print("!! %s：没有匹配的 paramdef（%s，行长 %d，候选 %s）" % (stem, p.param_type, p.detected_size, [(d.source, d.row_size(), d.data_version) for d in cands]), file=sys.stderr)
            continue
        rownames = load_rownames(os.path.join(args.rownames, stem + ".json")) if args.rownames else {}
        cols = [f for f in match.fields if f.type != "dummy8"]
        with open(os.path.join(args.out, stem + ".csv"), "w", newline="", encoding="utf-8") as fp:
            w = csv.writer(fp)
            w.writerow(["ID", "Name"] + [f.name for f in cols])
            seen: dict[int, int] = {}
            for row in p.rows:
                cells = read_cells(p.buf, row.data_offset, match.fields)
                vals = [c for f, c in zip(match.fields, cells) if f.type != "dummy8"]
                k = seen.get(row.id, 0)
                seen[row.id] = k + 1
                names = rownames.get(row.id, [])
                w.writerow([row.id, row.name or (names[k] if k < len(names) else "")] + vals)
        print("%-40s rows=%-6d fields=%-4d def=%s" % (stem, len(p.rows), len(cols), match.source))
    if not args.list:
        with open(os.path.join(args.out, "manifest.json"), "w", encoding="utf-8") as fp:
            json.dump(manifest, fp, ensure_ascii=False, indent=2)
        print("regulation %s, exe %s, buildid %s, %d 张表已导出，%d 张无 paramdef" % (
            bnd_version, manifest["exeVersion"], manifest["steamBuildId"], len(manifest["params"]) - problems, problems))
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
