#!/usr/bin/env python3
# /// script
# requires-python = ">=3.11"
# dependencies = ["pycryptodome>=3.20", "zstandard>=0.22"]
# ///
"""从《黑夜君临》归档里取出玩家（c0000）的动画事件表 TAE，解出每个动画里
「攻击 / 子弹 / 通用 / 投技 / PC 行为」事件所带的 behaviorJudgeId。

为什么需要它：战技数据集（generate_skills.py）里的 hits 是沿参数链
（SwordArtsParam → BehaviorParam_PC → AtkParam_Pc / Bullet）和 Paramdex 行名找出来的，
但 BehaviorParam_PC 里存着的行不一定被本作动画真的调用——例如「狩猎大蛇」
（武器 17030000，behaviorVariationId 1703）的 judge 900/901/905 三段在参数里叫
"L2 #1/#2 Beam of Light"，而本作里这把武器的战技并不是远程。哪些 judge 真的会打出，
只能读动画事件表：InvokeAttackBehavior（事件 1）/ InvokeBulletBehavior（事件 2）等
事件的 Behavior Judge ID 字段就是 BehaviorParam_PC.behaviorJudgeId；
行 ID = base + behaviorVariationId*1000 + judge（见 generate_skills.py）。

流程：复用 extract_msg.py 的 BHD5 解密 / 路径哈希 / DCX（KRAK 走 oodledec 批量模式，
与 extract_msb.py 相同）→ BND4 拆包（dump_regulation.read_bnd4）→ 只取 *.tae →
写到 raw/tae/<包名>/<文件名>.tae → 解析 TAE → raw/tae/invoked.json。

TAE 布局对照 SoulsFormatsNEXT（SoulsFormats/Formats/TAE/TAE.cs、Animation.cs、Event.cs，
本作与艾尔登法环同为 64 位、版本 0x1000D 的「SDT/ER」格式）：
  * 文件头：0x00 "TAE "，0x07 = 0xFF（64 位），0x08 版本 0x1000D，0x30 eventBank，
    0x50 TAE ID，0x54 动画数，0x58 动画表偏移；
  * 动画表每项 16 字节：ID(i64) + 动画体偏移(i64)；
  * 动画体：事件表偏移 / 事件组偏移 / 时间表偏移 / 动画文件头偏移（各 i64），
    事件数 / 事件组数 / 时间数（各 i32），0；
  * 事件头每项 24 字节：起始时间偏移 / 结束时间偏移 / 事件数据偏移（各 i64），
    时间本身是 f32；事件数据：type(i32) + unk04(i32) + 参数偏移(i64) + 参数；
  * 动画文件头：miniHeaderType(i32)，0，指向「文件名偏移」的偏移；Standard 型带
    isLoop / importsHKX / allowDelayLoad / importHKXSourceAnimID，ImportOtherAnim 型
    带 importFromAnimID——后者表示整段动画（含事件）从另一个动画导入，本脚本会跟随。
事件参数字段依据 Smithbox 的 TAE.Template.NR.xml（src/Smithbox.Data/Assets/TAE/，
与 DSAnimStudio 的 TAE.Template.ERNR.xml 一致）：
  事件 1  Attack Behavior：attackType(s32) attackIndex(s32) judgeId(s32) dirType(u8) source(u8) stateInfo(s16)
  事件 2  Bullet Behavior：dummyPolyId(s32) attackIndex(s32) judgeId(s32) attachType(u8) enable(b) stateInfo(s16) offset(s16) u8 source(u8) 0(s32)
  事件 5  Common Behavior：attackIndex(s32) judgeId(s32) 0 0
  事件 304 Throw Attack Behavior：u16 source(s16) judgeId(s32) 0 0
  事件 307 Invoke PC Behavior：condition(u16) offset(u16) pcBehaviorType(s32) judgeId(s32) 0
      （pcBehaviorType=8 时 judgeId 与事件 1 同义，踢击 / 无 FP 版踏地就是这样触发的；
        type 4 的 judge 500–561 是翻滚 / 跳跃类，不查 BehaviorParam_PC）
  事件 64  Cast Selected Magic：dummyPolyId(s32) b u8 sharedHitSlot(s16) refSlot(u8) …，
      refSlot 0–9 对应 Magic.refId1–10；施法动画在 a(400 + Magic.refType) 里
  事件 66 / 67 / 401  Add SpEffect (- Multiplayer / - Multiplayer [401])：spEffectId(s32) 0
  事件 302 Add SpEffect - Dragon Form：spEffectId(s32) 0 0 0
  事件 331 Add SpEffect - Weapon Skill：spEffectIdFp(s32) spEffectIdNoFp(s32) 0 0
      （战技动画给自己上的 buff：野蛮咆哮 a740 上 1680/1682（无 FP 1685/1687）、战吼 a741 上
        1810/1812、灭洛斯的狂嚎 a815 上 840/842；verify_skill_hits.py 用它们做「吼叫类 R2」与
        「SpEffect 派生命中」的证据。302 在这些 TAE 里有 29 个（a774 死亡闪光 1790/1792、
        a786 雷暴 1510/1512、a834 血祭仪式 1626/1628…），401 有 286 个，都一并收进 invoked.json）
  （source 枚举：0 默认 / 1 右手 / 2 左手 / 3 技能武器 / 4 绝招武器 / 5 额外武器 / 6 灵鹰）
  事件里的 stateInfo 是前置条件：不为 0 时，只有角色带着对应 SP_EFFECT_TYPE 的 SpEffect 才触发。
给 --template 传模板 XML 时，其它事件也按模板解字段（写到 --full 指定的按包分文件的
完整转储里）；不传模板时只解上面 11 种事件，其它事件只记录类型号。

judgeId 与 BehaviorParam_PC 的对应（实测）：
  行 ID = base + behaviorVariationId*1000 + judge；TAE 的 judgeId = judge（base 100000000 的普通攻击）
  或 base/100000000*1000 + judge（其它组：3xxx 战技、4xxx 战技通用 / 角色变体、5xxx 另一组
  （大枪 / 大蛇狩猎矛普通攻击上带 stateInfo 187 门控的延长命中行等）、8xxx/9xxx 词条子弹…）。
  武器有专属行时取专属行，否则落到 variationId=0 的通用行；base 400000000 的行（风暴管束者
  4001xxxxx…）按行自己的 variationId 解——这些 var 与武器类别的 var 重合，「按渡夜者选行」是从
  Paramdex 的 AtkParam 行名（"[AoW - Duchess] Storm Ruler"）推断的，两种读法下 80 段都被 a860 调用。
  base 不是 1 亿整数倍的行（ID 10/11/100/400…、2120/2140 等 242 行）不走 TAE judgeId：
  其中 162 行被 SpEffectParam.behaviorId 引用（由 SpEffect 触发），其余 80 行（10/11/100/400–513…）
  没有任何 SpEffect 引用，也没有数据集的段落在它们上。
  战技动画在 a(600 + SwordArtsParam.swordArtsType) 里（动画号 4xxxx）；战吼 / 野蛮咆哮 /
  灭洛斯的狂嚎的 R2 段在武器 a(wepmotionCategory) 的 30600–30635 / 32600–32635 里
  （judgeId 3950–3969 野蛮咆哮 / 灭洛斯，3980–3997 战吼）。逐段核实见 verify_skill_hits.py。

输出（均在 --out 下，默认 raw/tae/，与 raw/params 一样不入 git）：
  <包名>/<文件名>.tae   原始 TAE 文件（例：c0000/a37.tae——本作的 TAE 文件名不补零，a37 即 TAE 37）
  invoked.json         {
     "meta": {...来源、包清单、统计...},
     "events": {"<包名>/<TAE名>": {"<动画ID>": [ {type, name, judgeId, start, end, ...} ]}},
     "imports": {"<包名>/<TAE名>": {"<动画ID>": <importFromAnimID>}},   # ImportOtherAnim
     "animMeta": {"<包名>/<TAE名>": {"<动画ID>": {"types": [...], "file": "...", "hkxFrom": N}}}
  }
  events 只收带 judgeId 的事件（类型 1/2/5/304/307）、施法事件 64（refSlot）与
  上 SpEffect 的事件 66/67/302/331/401（spEffectId / spEffectIdFp / spEffectIdNoFp）；
  animMeta.types 是该动画出现过的全部事件类型。
  --full <目录> 时另外把每个 TAE 的全部事件（按模板解字段）写到 <目录>/<包名>/<TAE名>.json。

用法：
    uv run extract_tae.py --game "<...>/ELDEN RING NIGHTREIGN/Game" \\
        --krak-batch-cmd "'<wine>' --bottle Steam --no-gui 'Z:\\...\\oodledec.exe' \\
                          'Z:\\...\\oo2core_9_win64.dll' --batch {win_manifest}" \\
        [--out raw/tae] [--bnds c0000,c0000_a0x,...] [--template raw/TAE.Template.NR.xml] [--full raw/tae/full]
    uv run extract_tae.py --parse-only [--out raw/tae] ...   # 只重新解析已取出的 .tae
"""
from __future__ import annotations

import argparse
import json
import os
import struct
import sys
import xml.etree.ElementTree as ET
from collections import Counter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
# 归档 / DCX / BND4 的依赖（pycryptodome、zstandard）只在真正读归档时才导入，
# 这样 --help 与 --parse-only 用系统 python3 就能跑；读归档请用 uv run。

# 实测（1.03.5）：玩家的 523 个 TAE 全部在 c0000.anibnd.dcx 里；
# c0000_a0x…a6x / a9x.anibnd.dcx 只有 HKX 动作数据、没有 TAE，所以默认只取 c0000。
DEFAULT_BNDS = ["c0000"]

# 带 behaviorJudgeId 的事件：类型 → (名字, [(字段名, struct 码)])
# 字段顺序与 Smithbox TAE.Template.NR.xml 一致；"_" 开头的字段只占位不输出。
JUDGE_EVENTS: dict[int, tuple[str, list[tuple[str, str]]]] = {
    1: ("AttackBehavior", [("attackType", "i"), ("attackIndex", "i"), ("judgeId", "i"),
                           ("dirType", "B"), ("source", "B"), ("stateInfo", "h")]),
    2: ("BulletBehavior", [("dummyPolyId", "i"), ("attackIndex", "i"), ("judgeId", "i"),
                           ("attachType", "B"), ("enable", "B"), ("stateInfo", "h"),
                           ("offset", "h"), ("_u8", "B"), ("source", "B"), ("_z", "i")]),
    5: ("CommonBehavior", [("attackIndex", "i"), ("judgeId", "i"), ("_z1", "i"), ("_z2", "i")]),
    304: ("ThrowAttackBehavior", [("_u16", "H"), ("source", "h"), ("judgeId", "i"),
                                  ("_z1", "i"), ("_z2", "i")]),
    307: ("InvokePCBehavior", [("condition", "H"), ("offset", "H"), ("pcBehaviorType", "i"),
                               ("judgeId", "i"), ("_z", "i")]),
}
SOURCE_NAMES = {0: "default", 1: "right", 2: "left", 3: "skillWeapon", 4: "ultWeapon",
                5: "extraWeapon", 6: "spectralHawk"}
# 施法事件（法术用）：Cast Selected Magic 只带「用 Magic.refId 第几槽」，子弹本身由 Magic 决定。
# 字段依据同一模板：dummyPolyId(s32) b u8 sharedHitSlot(s16) refSlot(u8, 0 → refId1 … 9 → refId10) u8 s16 s8 s8 u16(0)
CAST_EVENTS: dict[int, tuple[str, list[tuple[str, str]]]] = {
    64: ("CastSelectedMagic", [("dummyPolyId", "i"), ("_b", "B"), ("_u8", "B"), ("sharedHitSlot", "h"),
                               ("refSlot", "B"), ("_u8b", "B"), ("_s16", "h"), ("_s8a", "b"), ("_s8b", "b"),
                               ("_z", "H")]),
}
# 给自己上 SpEffect 的事件（模板：66 / 67 Add SpEffect (- Multiplayer)、302 Add SpEffect - Dragon Form、
# 331 Add SpEffect - Weapon Skill、401 Add SpEffect - Multiplayer [401]）。
# verify_skill_hits.py 用它们判断战技动画上了哪些 buff（吼叫类 R2 的证据）以及
# SpEffectParam.behaviorId 派生的命中是否由本战技的动画触发。模板里带 SpEffect ID 字段的事件只有这 5 种。
SPEFFECT_EVENTS: dict[int, tuple[str, list[tuple[str, str]]]] = {
    66: ("AddSpEffectMultiplayer", [("spEffectId", "i"), ("_z", "i")]),
    67: ("AddSpEffect", [("spEffectId", "i"), ("_z", "i")]),
    302: ("AddSpEffectDragonForm", [("spEffectId", "i"), ("_z1", "i"), ("_z2", "i"), ("_z3", "i")]),
    331: ("AddSpEffectWeaponSkill", [("spEffectIdFp", "i"), ("spEffectIdNoFp", "i"), ("_z1", "i"), ("_z2", "i")]),
    401: ("AddSpEffectMultiplayer401", [("spEffectId", "i"), ("_z", "i")]),
}

TEMPLATE_TYPES = {"s8": "b", "u8": "B", "x8": "B", "b": "?", "s16": "h", "u16": "H", "x16": "H",
                  "s32": "i", "u32": "I", "x32": "I", "f32": "f", "s64": "q", "u64": "Q",
                  "x64": "Q", "f64": "d"}


# ---------- 模板 ----------

def load_template(path: str) -> dict[int, tuple[str, list[tuple[str, str]]]]:
    """读 Smithbox / DSAnimStudio 的 TAE 模板 XML：{事件类型: (名字, [(字段名, struct 码)])}。
    只用到字段的类型与顺序；assert / entry / ref 等属性忽略。"""
    root = ET.parse(path).getroot()
    out: dict[int, tuple[str, list[tuple[str, str]]]] = {}
    for ev in root:
        if ev.tag not in ("event", "action"):
            continue
        ev_id = int(ev.attrib["id"])
        name = ev.attrib.get("name") or ev.attrib.get("Name") or f"Event{ev_id}"
        fields: list[tuple[str, str]] = []
        for i, p in enumerate(ev):
            code = TEMPLATE_TYPES.get(p.tag)
            if p.tag == "aob":
                code = "%ds" % int(p.attrib.get("length", "0"))
            elif p.tag == "f32grad":
                code = "ff"
            if code is None:
                continue
            fname = p.attrib.get("name") or p.attrib.get("Name") or f"unk{i}"
            if "assert" in p.attrib:
                fname = "_" + fname
            fields.append((fname.replace(" ", "_"), code))
        out[ev_id] = (name, fields)
    return out


def decode_params(fields: list[tuple[str, str]], buf: bytes) -> dict:
    out: dict = {}
    pos = 0
    for fname, code in fields:
        size = struct.calcsize("<" + code)
        if pos + size > len(buf):
            break
        vals = struct.unpack_from("<" + code, buf, pos)
        pos += size
        if fname.startswith("_"):
            continue
        val = vals[0] if len(vals) == 1 else list(vals)
        if isinstance(val, bytes):
            val = val.hex()
        elif isinstance(val, float):
            val = round(val, 6)
        out[fname] = val
    return out


# ---------- TAE ----------

def _wstr(b: bytes, off: int) -> str:
    end = off
    while b[end:end + 2] != b"\0\0":
        end += 2
    return b[off:end].decode("utf-16-le")


def parse_tae(b: bytes) -> dict:
    """返回 {"id", "eventBank", "anims": {animId: {"events": [(type, start, end, params_bytes)],
    "importFrom", "file", "hkxFrom", "loop"}}}。只支持本作的 64 位 0x1000D 格式。"""
    if b[:4] != b"TAE ":
        raise ValueError("不是 TAE 文件")
    if b[4] != 0 or b[7] != 0xFF:
        raise ValueError("只支持小端 64 位 TAE")
    version = struct.unpack_from("<i", b, 8)[0]
    if version != 0x1000D:
        raise ValueError("不支持的 TAE 版本 0x%X" % version)
    event_bank = struct.unpack_from("<q", b, 0x30)[0]
    tae_id, anim_count = struct.unpack_from("<ii", b, 0x50)
    anims_off = struct.unpack_from("<q", b, 0x58)[0]
    anims: dict[int, dict] = {}
    for i in range(anim_count):
        aid, aoff = struct.unpack_from("<qq", b, anims_off + i * 16)
        ev_off, grp_off, _times_off, file_off, ev_cnt, _grp_cnt, _t_cnt, _z = struct.unpack_from(
            "<qqqqiiii", b, aoff)
        # 事件：先收齐 (type, start, end, 参数起点)，参数长度 = 下一个事件的数据偏移 − 本参数起点
        raw: list[tuple[int, float, float, int]] = []
        data_offs: list[int] = []
        for j in range(ev_cnt):
            s_off, e_off, d_off = struct.unpack_from("<qqq", b, ev_off + j * 24)
            start = struct.unpack_from("<f", b, s_off)[0]
            end = struct.unpack_from("<f", b, e_off)[0]
            etype, _unk04, p_off = struct.unpack_from("<iiq", b, d_off)
            raw.append((etype, start, end, p_off if p_off else d_off + 16))
            data_offs.append(d_off)
        events = []
        for j, (etype, start, end, p_off) in enumerate(raw):
            if j + 1 < len(raw):
                p_end = data_offs[j + 1]
            elif grp_off:
                p_end = grp_off
            else:
                p_end = file_off if file_off > p_off else len(b)
            events.append((etype, start, end, b[p_off:max(p_off, p_end)]))
        info: dict = {"events": events}
        # 动画文件头（mini header）
        mh_type, _z0, name_off_off = struct.unpack_from("<iiq", b, file_off)
        if name_off_off:
            name_off = struct.unpack_from("<q", b, name_off_off)[0]
            pos = name_off_off + 8
            if mh_type == 0:
                loop, imports_hkx, _delay, _z, hkx_src = struct.unpack_from("<BBBBi", b, pos)
                if loop:
                    info["loop"] = True
                if imports_hkx:
                    info["hkxFrom"] = hkx_src
            elif mh_type == 1:
                import_from, _unk = struct.unpack_from("<ii", b, pos)
                info["importFrom"] = import_from
            if 0 < name_off < len(b):
                q = struct.unpack_from("<q", b, name_off)[0] if name_off + 8 <= len(b) else 1
                f = struct.unpack_from("<f", b, name_off)[0] if name_off + 4 <= len(b) else 0.0
                if q != 1 and not (0.016667 <= f <= 100):
                    try:
                        info["file"] = _wstr(b, name_off)
                    except (UnicodeDecodeError, IndexError):
                        pass
        anims[aid] = info
    return {"id": tae_id, "eventBank": event_bank, "anims": anims}


# ---------- 归档 ----------

def fetch_anibnds(arc, names: list[str], krak_batch_cmd: str | None,
                  krak_cmd: str | None) -> dict[str, bytes]:
    from extract_msb import _dcx_payload, krak_batch
    from extract_msg import dcx_decompress
    out: dict[str, bytes] = {}
    krak: dict[str, tuple[bytes, int]] = {}
    for name in names:
        path = "/chr/%s.anibnd.dcx" % name
        if not arc.has(path):
            print("跳过（归档里不存在）：%s" % path, file=sys.stderr)
            continue
        d = arc.read(path)
        if d[:4] == b"DCX\0":
            fmt, payload, unc = _dcx_payload(d)
            if fmt == b"KRAK" and krak_batch_cmd:
                krak[name] = (payload, unc)
                continue
            d = dcx_decompress(d, krak_cmd)
        out[name] = d
    if krak:
        print("Kraken 批量解压 %d 个包…" % len(krak), file=sys.stderr)
        out.update(krak_batch(krak, krak_batch_cmd))
    return out


def unpack_taes(bnd: bytes) -> list[tuple[str, bytes]]:
    from dump_regulation import read_bnd4
    _, entries = read_bnd4(bnd)
    out = []
    for e in entries:
        name = e.name.replace("\\", "/").rsplit("/", 1)[-1]
        if name.lower().endswith(".tae"):
            out.append((name, e.data))
    return out


# ---------- 主流程 ----------

def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--game", help="游戏目录（含 data0.bhd/bdt…）；--parse-only 时可省略")
    ap.add_argument("--krak-batch-cmd", help="批量 Kraken 解压命令模板，占位符 {manifest} / {win_manifest}（同 extract_msb.py）")
    ap.add_argument("--krak-cmd", help="逐个解压的命令模板（同 extract_msg.py），没有批量命令时使用")
    ap.add_argument("--out", default=os.path.join(os.path.dirname(os.path.abspath(__file__)), "raw", "tae"))
    ap.add_argument("--bnds", default=",".join(DEFAULT_BNDS),
                    help="逗号分隔的 anibnd 名（不含 .anibnd.dcx），默认 " + ",".join(DEFAULT_BNDS))
    ap.add_argument("--template", help="Smithbox / DSAnimStudio 的 TAE 模板 XML（可选，用于 --full 解全部事件字段）")
    ap.add_argument("--full", help="把每个 TAE 的全部事件写到该目录（按包分子目录），体积较大")
    ap.add_argument("--parse-only", action="store_true", help="不读归档，只解析 --out 下已有的 .tae")
    args = ap.parse_args()

    names = [n.strip() for n in args.bnds.split(",") if n.strip()]
    os.makedirs(args.out, exist_ok=True)

    if not args.parse_only:
        if not args.game:
            ap.error("--game 必填（除非 --parse-only）")
        from extract_msg import Archives
        arc = Archives(args.game)
        bnds = fetch_anibnds(arc, names, args.krak_batch_cmd, args.krak_cmd)
        for name, data in bnds.items():
            taes = unpack_taes(data)
            d = os.path.join(args.out, name)
            if taes:
                os.makedirs(d, exist_ok=True)
            for fname, tdata in taes:
                with open(os.path.join(d, fname), "wb") as fp:
                    fp.write(tdata)
            print("%s.anibnd.dcx：BND4 %d 字节，%d 个 TAE" % (name, len(data), len(taes)), file=sys.stderr)

    template = load_template(args.template) if args.template else {}
    layouts = dict(template)
    layouts.update(JUDGE_EVENTS)  # judge / 施法 / 上 SpEffect 事件用本脚本的字段名
    layouts.update(CAST_EVENTS)
    layouts.update(SPEFFECT_EVENTS)

    events_out: dict[str, dict[str, list[dict]]] = {}
    imports_out: dict[str, dict[str, int]] = {}
    meta_out: dict[str, dict[str, dict]] = {}
    stats = Counter()
    type_counter: Counter = Counter()
    packs: dict[str, list[str]] = {}
    for name in names:
        d = os.path.join(args.out, name)
        if not os.path.isdir(d):
            continue
        files = sorted(f for f in os.listdir(d) if f.lower().endswith(".tae"))
        packs[name] = files
        for fname in files:
            with open(os.path.join(d, fname), "rb") as fp:
                tae = parse_tae(fp.read())
            key = "%s/%s" % (name, fname[:-4])
            ev_map: dict[str, list[dict]] = {}
            imp_map: dict[str, int] = {}
            am_map: dict[str, dict] = {}
            full_map: dict[str, list[dict]] = {}
            for aid, info in sorted(tae["anims"].items()):
                stats["anims"] += 1
                types = sorted({e[0] for e in info["events"]})
                am: dict = {"types": types}
                for k in ("file", "hkxFrom", "loop"):
                    if k in info:
                        am[k] = info[k]
                am_map[str(aid)] = am
                if "importFrom" in info:
                    imp_map[str(aid)] = info["importFrom"]
                    stats["importOtherAnim"] += 1
                judged: list[dict] = []
                full: list[dict] = []
                for etype, start, end, pbytes in info["events"]:
                    stats["events"] += 1
                    type_counter[etype] += 1
                    lay = layouts.get(etype)
                    rec = {"type": etype, "start": round(start, 4), "end": round(end, 4)}
                    if lay:
                        rec["name"] = lay[0]
                        rec.update(decode_params(lay[1], pbytes))
                    elif args.full:
                        rec["raw"] = pbytes.hex()
                    if etype in JUDGE_EVENTS or etype in CAST_EVENTS or etype in SPEFFECT_EVENTS:
                        if "source" in rec:
                            rec["sourceName"] = SOURCE_NAMES.get(rec["source"], str(rec["source"]))
                        judged.append(rec)
                        stats["judgeEvents" if etype in JUDGE_EVENTS else
                              ("castEvents" if etype in CAST_EVENTS else "spEffectEvents")] += 1
                    if args.full:
                        full.append(rec)
                if judged:
                    ev_map[str(aid)] = judged
                if args.full:
                    full_map[str(aid)] = full
            events_out[key] = ev_map
            imports_out[key] = imp_map
            meta_out[key] = am_map
            if args.full:
                fd = os.path.join(args.full, name)
                os.makedirs(fd, exist_ok=True)
                with open(os.path.join(fd, fname[:-4] + ".json"), "w", encoding="utf-8") as fp:
                    json.dump({"id": tae["id"], "eventBank": tae["eventBank"], "anims": full_map,
                               "imports": imp_map, "animMeta": am_map}, fp, ensure_ascii=False, indent=0)
            stats["taes"] += 1

    meta = {
        "source": "/chr/<包名>.anibnd.dcx（data0–3 / dlc01 归档）→ BND4 → *.tae",
        "format": "TAE 64 位 0x1000D（SoulsFormatsNEXT TAE.cs / Animation.cs / Event.cs）",
        "eventFields": "Smithbox TAE.Template.NR.xml：事件 1/2/5/304/307 的 Behavior Judge ID 字段；64 的 refSlot；66/67/302/331/401 的 SpEffect ID",
        "template": os.path.basename(args.template) if args.template else None,
        "packs": packs,
        "stats": dict(stats),
        "eventTypeCounts": {str(k): v for k, v in sorted(type_counter.items())},
        "judgeIdRule": "BehaviorParam_PC.ID = base + behaviorVariationId*1000 + judge；TAE judgeId = judge（base 100000000）"
                       "或 base/100000000*1000 + judge（其它 base，如 3xxx 战技、4xxx 战技通用 / 角色变体）；"
                       "variationId 取武器 EquipParamWeapon.behaviorVariationId（base 400000000 的行按行自己的 variationId，"
                       "「按渡夜者选行」只是 AtkParam 行名的读法），缺则 0；"
                       "base 不是 1 亿整数倍的行（242 行）不走 TAE：162 行由 SpEffectParam.behaviorId 触发，其余 80 行没有任何引用",
    }
    with open(os.path.join(args.out, "invoked.json"), "w", encoding="utf-8") as fp:
        json.dump({"meta": meta, "events": events_out, "imports": imports_out, "animMeta": meta_out},
                  fp, ensure_ascii=False, indent=0)
    print("%d 个 TAE，%d 个动画，%d 个事件，其中带 judgeId 的 %d 个 → %s" % (
        stats["taes"], stats["anims"], stats["events"], stats["judgeEvents"],
        os.path.join(args.out, "invoked.json")))
    return 0


if __name__ == "__main__":
    sys.exit(main())
