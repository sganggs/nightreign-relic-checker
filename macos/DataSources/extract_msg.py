#!/usr/bin/env python3
# /// script
# requires-python = ">=3.11"
# dependencies = ["pycryptodome>=3.20", "zstandard>=0.22"]
# ///
"""从《黑夜君临》的 data*.bhd/bdt 归档里取出文本包（msg/<lang>/*.msgbnd.dcx），
把每个 FMG 解成 {id: 文本} 的 JSON。

流程：RSA 公钥解密 .bhd 目录 → 按 64 位路径哈希定位条目 → 从 .bdt 读出（必要时
AES-128-ECB 解密指定区间）→ DCX 解压（KRAK 交给外部命令，ZSTD/DFLT 内建）→ BND4 →
FMG。二进制布局对照 SoulsFormats 的 BHD5 / DCX / FMG 实现；归档公钥是 UXM /
BinderTool 长期公开的常量。

用法：
    uv run extract_msg.py --game "<...>/ELDEN RING NIGHTREIGN/Game" --krak-cmd "<见 --help>" \
        --out raw/msg [--lang zhocn,engus] [--bnd item,menu]

KRAK 说明：本游戏的归档用 Oodle 2.9 的 Kraken 压缩，开源的 ooz 解不开（只能解到 2.7 的码流），
所以用 Go 交叉编译一个 oodledec.exe，在 CrossOver/Wine 里加载游戏目录自带的 oo2core_9_win64.dll。
"""
from __future__ import annotations

import argparse
import json
import os
import struct
import shlex
import subprocess
import sys
import tempfile
import zlib

import zstandard
from Crypto.Cipher import AES
from Crypto.PublicKey import RSA

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from dump_regulation import read_bnd4  # noqa: E402

ER_HASH_PRIME = 0x85

ARCHIVE_KEYS = {
    "data0": """-----BEGIN RSA PUBLIC KEY-----
MIIBDAKCAQEAz8F9U1V9hgKs40gdzl1ZOf3IBirf6xUEzXtDd6oSEBE6XiYocvAB
ykiK+WMdAaJL7HJ58Gt2xSRxA3t9toCGKMI/3gNAfcR0BV83gsQo0O0dVP0fqyxX
lA2pGN5B4IE8aLWPX2cNNFSFKAdjYnzsYSevzef/pgnpV1ZgPf2j2SQwNGSufYeN
3Owji8l0K2C0fKIx6gSO0cK9kvTIm8AdpvzZbBkTylT1jF3m8DsSA1OFzFJTdFyZ
bTRi85M6bmv6rHtvZc5OW21dye7Q6fmLlxOyMetLTu4dpOXjHAAf/LFTbfQpXFr9
aXO4O6I7nWDJn7FRzNlLkb8RwSyZ1/KWyQIFALEDsAc=
-----END RSA PUBLIC KEY-----
""",
    "data1": """-----BEGIN RSA PUBLIC KEY-----
MIIBDAKCAQEA0E6dtnDmT6d2+VaNkPzomUNv+T6896H//RAaTR2guPACMDNZpAsF
vV3MfNcR2BS6Cbxl55MmMWsmsZs1s293MuOdS+c99vmZbNYcXWjx0uJGO+VrRXe4
3TRzmQFh1uD+Xcq6+wYfTrGyLOdAtmwdDXNvW8jYoFDM7nsuoPKOXKtKd0uz7/MK
ZYLk1J7pAoBQqw9VD5qi2Ih86zn0VWm5lLMTI0qnutOzpZVDvZWBg/jr4Nbnr/Ox
PLeJO1tFuRuHUPuBAWtYM/J23MPqqKkQrG5z2r7PexUI744UPdmo3Sn+Mqynuxxv
V9SEhska6pStzn8R9i94wOKPTQ32HEFuUQIFAP////8=
-----END RSA PUBLIC KEY-----
""",
    "data2": """-----BEGIN RSA PUBLIC KEY-----
MIIBDAKCAQEAqpkf9yHnx8k84+WXITLFUW/STypXjZMPuw842pzNHa5L7v9gU4M5
hBHwTQs0YIcfnf+mbjqoJYnmYPBblxLjFXgwT4ICJdpnPMY75BwD0Nv28/CvvIsA
0QQWOhUeOXnm5BT26dGYi3CHHPvD14F76tJt3TO/CC3fyhdxne9Cra5G87aGTJGv
0ImsU0KPCizYX/RHQ2jdJdlB5BHzkMgLhIaEdhC3nhIqMJDNQNGKMo7rRV1tAEGf
0zIZ23PGEsPsbVg31nnnRoq338WfD9ArZZG6bM11vlfVcYmrJs7v4vBjKXnYVwVX
0rQGIfSNDnaZcEj4tsl04AqnupTdvSrHXwIFANOg6RU=
-----END RSA PUBLIC KEY-----
""",
    "data3": """-----BEGIN RSA PUBLIC KEY-----
MIIBCwKCAQEAwm2Rcw4eoP8FgWijxw1X8b9rEVFsVqy7rXWcH2yVm61yYBlzPlTq
Kqnc2VeqZSh/TLXeFY3+Om2X78RQxZNS3L3OokvD7l/0wqPIpXSSumeeL8UAZm5k
7nFA2m2HJfc+F07kNwwCEqhmFs5YQIMnWyIrqnEax/qSncFErLjIYMBMArVnVLE8
WqgsD7N8lW937dlUcT2TaPh1HfjavKOSUy/OHM9zaneyDL4NRmDdU8GmNXTSm5kP
YoSRCDIvFVj0g5iaXr60eRh0d+40TctoBUdtaoJCPOyRlmkE7qU6Q9FyyvMNbhtf
D95d+6IJejNd7kvyV/ISlB37kb2Uh9TavwIEOqKLtw==
-----END RSA PUBLIC KEY-----
""",
    "dlc01": """-----BEGIN RSA PUBLIC KEY-----
MIIBDAKCAQEA1q4MOehlD++h5Ietq9Jk97eGOJL2zDpDcu9Wk6RXK1+R3LycMBQl
L/hnPg/qqvcoViA7wLX5GOFr5lo6dtKaQqlBkBqgYHGIdBvioBPZ8BuXAjYr3sm8
N0SYC2TNHXmfw6yFC+ePsrl+gNldrO//XXY27hsGgcegfWr6JuQaJti/BOKlGb8A
RbKwyIqGc5WiWj/v0tGE1cdPi0fLQRbTrLFaQtx1roQVqsQuJ5zRGTpnj/mhaJtq
J7V0s5gLG5CCevx71lN8m7oyWk2JemzSLvllwv4tjtzrw3jNQtiYb8nzy2Spjibs
vX1iRCg5btMSiNPcSeIJ5jX+FUW9LSnrkwIFAKhopbM=
-----END RSA PUBLIC KEY-----
""",
}


# ---------- BHD5 ----------

def rsa_decrypt_bhd(enc: bytes, key: RSA.RsaKey) -> bytes:
    """FromSoft 用「公钥」做原始模幂运算解密 .bhd：每 256 字节一块，输出去掉首字节的 255 字节。"""
    block = key.size_in_bytes()
    out = bytearray()
    for i in range(0, len(enc), block):
        chunk = enc[i:i + block]
        m = pow(int.from_bytes(chunk, "big"), key.e, key.n)
        out += m.to_bytes(block, "big")[1:]
    return bytes(out)


def path_hash(path: str, prime: int = ER_HASH_PRIME) -> int:
    p = path.lower().replace("\\", "/")
    if not p.startswith("/"):
        p = "/" + p
    h = 0
    for ch in p:
        h = (h * prime + ord(ch)) & 0xFFFFFFFFFFFFFFFF
    return h


class Entry:
    __slots__ = ("padded", "size", "offset", "aes_key", "aes_ranges", "archive")

    def __init__(self, padded, size, offset, archive):
        self.padded, self.size, self.offset, self.archive = padded, size, offset, archive
        self.aes_key, self.aes_ranges = None, []


def read_bhd5(data: bytes, archive: str) -> dict[int, Entry]:
    if data[:4] != b"BHD5":
        raise ValueError("%s：解密后不是 BHD5（密钥或格式不对）" % archive)
    if data[4] != 0xFF:
        raise ValueError("%s：不支持大端 BHD5" % archive)
    bucket_count, buckets_off = struct.unpack_from("<ii", data, 16)
    entries: dict[int, Entry] = {}
    for b in range(bucket_count):
        count, off = struct.unpack_from("<ii", data, buckets_off + b * 8)
        for i in range(count):
            h, padded, size, foff, _sha, aes_off = struct.unpack_from("<QiiQqq", data, off + i * 40)
            e = Entry(padded, size, foff, archive)
            if aes_off:
                e.aes_key = data[aes_off:aes_off + 16]
                rc = struct.unpack_from("<i", data, aes_off + 16)[0]
                e.aes_ranges = [struct.unpack_from("<qq", data, aes_off + 20 + r * 16) for r in range(rc)]
            entries[h] = e
    return entries


class Archives:
    def __init__(self, game_dir: str):
        self.game_dir = game_dir
        self.index: dict[int, Entry] = {}
        for name, pem in ARCHIVE_KEYS.items():
            bhd = os.path.join(game_dir, name + ".bhd")
            if not os.path.exists(bhd):
                continue
            key = RSA.import_key(pem)
            entries = read_bhd5(rsa_decrypt_bhd(open(bhd, "rb").read(), key), name)
            for h, e in entries.items():
                self.index.setdefault(h, e)
            print("%s.bhd：%d 个条目" % (name, len(entries)), file=sys.stderr)

    def has(self, path: str) -> bool:
        return path_hash(path) in self.index

    def read(self, path: str) -> bytes:
        e = self.index.get(path_hash(path))
        if e is None:
            raise KeyError(path)
        with open(os.path.join(self.game_dir, e.archive + ".bdt"), "rb") as fp:
            fp.seek(e.offset)
            data = bytearray(fp.read(e.padded if e.size <= 0 else max(e.size, e.padded)))
        if e.aes_key:
            cipher = AES.new(e.aes_key, AES.MODE_ECB)
            for start, end in e.aes_ranges:
                if start == -1 or end == -1:
                    continue
                n = (end - start) - (end - start) % 16
                data[start:start + n] = cipher.decrypt(bytes(data[start:start + n]))
        return bytes(data[:e.size] if e.size > 0 else data)


# ---------- DCX ----------

def _to_win_path(path: str) -> str:
    """Wine 把根目录映射为 Z:，本机绝对路径可直接改写成 Windows 路径。"""
    return "Z:" + path.replace("/", "\\")


def krak_decompress(payload: bytes, unc: int, krak_cmd: str) -> bytes:
    """按命令模板调用外部 Kraken 解压器。占位符：{in} {out} {size}，以及 Wine 用的 {win_in} {win_out}。"""
    with tempfile.TemporaryDirectory() as td:
        src, dst = os.path.join(td, "in.krak"), os.path.join(td, "out.bin")
        open(src, "wb").write(payload)
        sub = {"{in}": src, "{out}": dst, "{size}": str(unc), "{win_in}": _to_win_path(src), "{win_out}": _to_win_path(dst)}
        argv = []
        for tok in shlex.split(krak_cmd):
            for k, v in sub.items():
                tok = tok.replace(k, v)
            argv.append(tok)
        r = subprocess.run(argv, capture_output=True, text=True)
        if r.returncode != 0 or not os.path.exists(dst):
            raise RuntimeError("Kraken 解压失败（%s）：%s" % (argv[0], (r.stderr or r.stdout).strip()[-400:]))
        return open(dst, "rb").read()


def dcx_decompress(d: bytes, krak_cmd: str | None) -> bytes:
    if d[:4] != b"DCX\0":
        return d
    fmt = d[0x28:0x2C]
    unc = struct.unpack(">I", d[0x1C:0x20])[0]
    comp = struct.unpack(">I", d[0x20:0x24])[0]
    dca = d.find(b"DCA\0", 0x40, 0x80)
    payload_off = dca + struct.unpack(">I", d[dca + 4:dca + 8])[0]
    payload = d[payload_off:payload_off + comp]
    if fmt == b"ZSTD":
        out = zstandard.ZstdDecompressor().decompressobj().decompress(payload)
    elif fmt == b"DFLT":
        out = zlib.decompress(payload)
    elif fmt == b"KRAK":
        if not krak_cmd:
            raise RuntimeError("KRAK 压缩需要 --krak-cmd（例如通过 Wine 调用游戏自带 oo2core DLL 的 oodledec）")
        out = krak_decompress(payload, unc, krak_cmd)
    else:
        raise ValueError("暂不支持的 DCX 压缩格式：%r" % fmt)
    if len(out) != unc:
        raise ValueError("DCX 解压长度不符：%d != %d" % (len(out), unc))
    return out


# ---------- FMG ----------

def read_fmg(buf: bytes) -> dict[int, str]:
    big_endian = buf[1] != 0
    version = buf[2]
    if big_endian:
        raise ValueError("不支持大端 FMG")
    wide = version == 2
    unicode = buf[8] != 0
    group_count = struct.unpack_from("<i", buf, 0x0C)[0]
    pos = 0x14
    if wide:
        pos += 4  # 0xFF
        offsets_off = struct.unpack_from("<q", buf, pos)[0]
        pos += 16
    else:
        offsets_off = struct.unpack_from("<i", buf, pos)[0]
        pos += 8
    out: dict[int, str] = {}
    for _ in range(group_count):
        offset_index, first_id, last_id = struct.unpack_from("<iii", buf, pos)
        pos += 16 if wide else 12
        for j in range(last_id - first_id + 1):
            if wide:
                so = struct.unpack_from("<q", buf, offsets_off + (offset_index + j) * 8)[0]
            else:
                so = struct.unpack_from("<i", buf, offsets_off + (offset_index + j) * 4)[0]
            if so <= 0:
                continue
            if unicode:
                end = so
                while buf[end:end + 2] != b"\0\0":
                    end += 2
                text = buf[so:end].decode("utf-16-le")
            else:
                text = buf[so:buf.index(b"\0", so)].decode("shift_jis", "replace")
            out[first_id + j] = text
    return out


# ---------- 主流程 ----------

def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--game", required=True)
    ap.add_argument("--krak-cmd", help="Kraken 解压命令模板，占位符 {in} {out} {size} {win_in} {win_out}；"
                    "例如 '<wine> --bottle Steam --no-gui Z:\\...\\oodledec.exe Z:\\...\\oo2core_9_win64.dll {win_in} {win_out} {size}'")
    ap.add_argument("--out", required=True)
    ap.add_argument("--lang", default="zhocn", help="逗号分隔，如 zhocn,engus,jpnjp")
    ap.add_argument("--bnd", default="item,menu", help="逗号分隔的 msgbnd 名（item、menu、ngword…）")
    ap.add_argument("--dlc", default=",_dlc01", help="逗号分隔的后缀（空串表示本体）")
    args = ap.parse_args()

    arc = Archives(args.game)
    summary = {}
    for lang in args.lang.split(","):
        for bnd in args.bnd.split(","):
            for suffix in args.dlc.split(","):
                path = "/msg/%s/%s%s.msgbnd.dcx" % (lang, bnd, suffix)
                if not arc.has(path):
                    print("跳过（不存在）：%s" % path, file=sys.stderr)
                    continue
                raw = arc.read(path)
                _, entries = read_bnd4(dcx_decompress(raw, args.krak_cmd))
                out_dir = os.path.join(args.out, lang, bnd + suffix)
                os.makedirs(out_dir, exist_ok=True)
                for e in entries:
                    name = e.name.replace("\\", "/").rsplit("/", 1)[-1]
                    if not name.lower().endswith(".fmg"):
                        continue
                    texts = read_fmg(e.data)
                    with open(os.path.join(out_dir, name[:-4] + ".json"), "w", encoding="utf-8") as fp:
                        json.dump({str(k): v for k, v in sorted(texts.items())}, fp, ensure_ascii=False, indent=0)
                    summary.setdefault(path, {})[name] = len(texts)
                print("%s：%d 个 FMG，%d 条文本" % (path, len(summary[path]), sum(summary[path].values())))
    with open(os.path.join(args.out, "manifest.json"), "w", encoding="utf-8") as fp:
        json.dump(summary, fp, ensure_ascii=False, indent=2)
    return 0


if __name__ == "__main__":
    sys.exit(main())
