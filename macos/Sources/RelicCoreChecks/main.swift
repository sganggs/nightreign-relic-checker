import CommonCrypto
import CryptoKit
import Foundation
import RelicCore

struct CheckFailure: Error, CustomStringConvertible {
    let description: String
}

var passed = 0

func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    guard condition() else { throw CheckFailure(description: message) }
    passed += 1
}

func makeAffix(
    id: Int,
    compatibility: Int,
    sort: Int,
    pools: [Int] = [110, 210, 310],
    requiresCurse: Bool = false
) -> Affix {
    Affix(
        effectID: id,
        name: "词条 \(id)",
        compatibilityID: compatibility,
        sortID: sort,
        poolIDs: pools,
        requiresCurse: requiresCurse
    )
}

let checker = LegalityChecker()

let valid = checker.check([
    makeAffix(id: 10, compatibility: 1, sort: 100),
    makeAffix(id: 20, compatibility: 2, sort: 200),
    makeAffix(id: 30, compatibility: -1, sort: 300)
], mode: .currentNormal)
try expect(valid.status == .valid, "合法且有序的组合应通过")

let wrongOrder = checker.check([
    makeAffix(id: 30, compatibility: 3, sort: 300),
    makeAffix(id: 10, compatibility: 1, sort: 100),
    makeAffix(id: 20, compatibility: 2, sort: 200)
], mode: .currentNormal)
try expect(wrongOrder.status == .wrongOrder, "乱序组合应报告顺序错误")
try expect(wrongOrder.orderedAffixes.map(\.effectID) == [10, 20, 30], "应返回规范顺序")

let tieBreak = checker.canonicalOrder([
    makeAffix(id: 12, compatibility: 1, sort: 100),
    makeAffix(id: 10, compatibility: 2, sort: 100),
    makeAffix(id: 11, compatibility: 3, sort: 100)
])
try expect(tieBreak.map(\.effectID) == [10, 11, 12], "sortId 相同时应按 effectId 排序")

let duplicate = makeAffix(id: 10, compatibility: -1, sort: 100)
let duplicateResult = checker.check([
    duplicate,
    duplicate,
    makeAffix(id: 30, compatibility: -1, sort: 300)
], mode: .currentNormal)
try expect(duplicateResult.status == .invalid, "重复 effectId 应非法")
try expect(duplicateResult.issues.contains { $0.kind == .duplicate }, "应给出重复原因")

let conflict = checker.check([
    makeAffix(id: 10, compatibility: 100, sort: 100),
    makeAffix(id: 20, compatibility: 100, sort: 200),
    makeAffix(id: 30, compatibility: -1, sort: 300)
], mode: .currentNormal)
try expect(conflict.status == .invalid, "compatibilityId 冲突应非法")
try expect(conflict.issues.contains { $0.kind == .conflict }, "应给出互斥池原因")

let minusOne = checker.check([
    makeAffix(id: 10, compatibility: -1, sort: 100),
    makeAffix(id: 20, compatibility: -1, sort: 200),
    makeAffix(id: 30, compatibility: -1, sort: 300)
], mode: .currentNormal)
try expect(minusOne.status == .valid, "compatibilityId -1 允许重复")

let unavailable = checker.check([
    makeAffix(id: 10, compatibility: 1, sort: 100),
    makeAffix(id: 20, compatibility: 2, sort: 200),
    makeAffix(id: 30, compatibility: 3, sort: 300, pools: [2_000_000])
], mode: .currentNormal)
try expect(unavailable.status == .invalid, "不在当前非零权重池应非法")
try expect(unavailable.issues.contains { $0.kind == .unavailable }, "应给出出货池原因")

let deepPoolTemplates = [
    [2_000_000, 2_000_000, 2_000_000],
    [2_000_000, 2_000_000, 2_100_000],
    [2_000_000, 2_100_000, 2_100_000],
    [2_100_000, 2_100_000, 2_100_000],
    [2_000_000, 2_000_000, 2_200_000],
    [2_000_000, 2_200_000, 2_200_000],
    [2_200_000, 2_200_000, 2_200_000]
]
try expect(CheckMode.deepPositive.slotPoolSequences == deepPoolTemplates, "深夜模式应使用七种真实三词条槽池模板")
try expect(CheckMode.deepPositive.eligiblePoolIDs == [2_000_000, 2_100_000, 2_200_000], "深夜候选筛选应保留 A/B/C 池并集")

for (templateIndex, template) in deepPoolTemplates.enumerated() {
    let affixes = template.enumerated().map { affixIndex, poolID in
        makeAffix(
            id: 10_000 + templateIndex * 10 + affixIndex,
            compatibility: 100 + affixIndex,
            sort: 100 + affixIndex,
            pools: [poolID],
            requiresCurse: poolID == 2_000_000
        )
    }
    let result = checker.check(affixes, mode: .deepPositive)
    try expect(result.status == .valid, "深夜真实模板 \(template) 应通过正面预检")
    try expect(result.warnings.contains { $0.kind == .cursePairing }, "深夜真实模板必须提示完整诅咒验证范围")
}

let impossibleDeepABC = checker.check([
    makeAffix(id: 20_010, compatibility: 1, sort: 100, pools: [2_000_000], requiresCurse: true),
    makeAffix(id: 20_020, compatibility: 2, sort: 200, pools: [2_100_000]),
    makeAffix(id: 20_030, compatibility: 3, sort: 300, pools: [2_200_000])
], mode: .deepPositive)
try expect(impossibleDeepABC.status == .invalid, "原始参数中不存在的深夜 A/B/C 三槽模板应判非法")
try expect(
    impossibleDeepABC.issues.contains { $0.kind == .unavailable && $0.title == "不符合当前槽池模板" },
    "A/B/C 组合应明确报告槽池模板不匹配"
)

let sourceFile = URL(fileURLWithPath: #filePath)
let projectRoot = sourceFile.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
let catalogURL = projectRoot.appendingPathComponent("Sources/NightreignRelicChecker/Resources/affixes.json")
let catalog = try CatalogLoader.load(from: catalogURL)

try expect(catalog.affixes.count == 527, "总记录数应为 527")
try expect(catalog.affixes.filter { !$0.isCurse }.count == 503, "正面词条应为 503")
try expect(catalog.affixes.filter { $0.poolIDs.contains(110) }.count == 340, "当前普通池应为 340")
try expect(catalog.affixes.filter { $0.poolIDs.contains(100) }.count == 290, "旧普通池应为 290")
try expect(Set(catalog.affixes.map(\.effectID)).count == catalog.affixes.count, "effectId 必须唯一")
try expect(catalog.affixes.filter { $0.popularity != nil }.count == 19, "应恢复 19 条热门度")

let reportedDeepIDs = [6_005_601, 6_610_400, 6_611_002]
let reportedDeepAffixes = reportedDeepIDs.compactMap { effectID in
    catalog.affixes.first { $0.effectID == effectID }
}
try expect(reportedDeepAffixes.count == 3, "截图中的三个真实深夜词条必须存在于词条库")
try expect(reportedDeepAffixes.allSatisfy { $0.poolIDs == [2_000_000] && $0.requiresCurse }, "截图词条应全部为需要诅咒的 A-only 词条")

let reportedDeepResult = checker.check(reportedDeepAffixes, mode: .deepPositive)
try expect(reportedDeepResult.status == .valid, "截图中的 A/A/A 深夜正面组合应通过")
try expect(reportedDeepResult.orderedAffixes.map(\.effectID) == reportedDeepIDs, "截图中的深夜词条顺序应正确")
try expect(reportedDeepResult.issues.isEmpty, "截图中的深夜正面组合不应报告非法原因")
guard let reportedWarning = reportedDeepResult.warnings.first(where: { $0.kind == .cursePairing }) else {
    throw CheckFailure(description: "截图中的深夜组合缺少诅咒验证警告")
}
try expect(reportedWarning.effectIDs == reportedDeepIDs, "诅咒警告应标记全部三个 A-only 词条")
try expect(reportedWarning.detail.contains("3 条为仅 A 池词条"), "诅咒警告应明确 A-only 词条数量")
try expect(reportedWarning.detail.contains("至少需要 3 个对应诅咒槽"), "诅咒警告应明确完整遗物所需最低诅咒槽数量")
try expect(reportedDeepResult.message.contains("不等同"), "深夜正面通过不得冒充完整遗物合法")

let current = catalog.affixes.filter { $0.poolIDs.contains(110) }
try expect(current.allSatisfy { $0.poolIDs.contains(210) && $0.poolIDs.contains(310) }, "当前普通三槽候选集合应相等")

let legacy = catalog.affixes.filter { $0.poolIDs.contains(100) }
try expect(legacy.allSatisfy { $0.poolIDs.contains(200) && $0.poolIDs.contains(300) }, "旧普通三槽候选集合应相等")

let attackGroup = current.filter { $0.compatibilityID == 100 }
try expect(attackGroup.count > 2, "攻击力互斥池应含多条词条")
guard let unrestricted = current.first(where: { $0.compatibilityID != 100 }) else {
    throw CheckFailure(description: "当前池缺少攻击池以外的测试词条")
}
let realConflictSample = checker.canonicalOrder(Array(attackGroup.prefix(2)) + [unrestricted])
try expect(checker.check(realConflictSample, mode: .currentNormal).status == .invalid, "真实数据中的同池组合应非法")

if let random = checker.randomCombination(from: catalog.affixes, mode: .currentNormal) {
    try expect(checker.check(random, mode: .currentNormal).status == .valid, "随机生成结果必须合法")
} else {
    throw CheckFailure(description: "无法从真实词条库生成合法组合")
}

// ===== 合成存档解析回归 =====

func u32le(_ value: UInt32) -> [UInt8] {
    [UInt8(value & 0xFF), UInt8((value >> 8) & 0xFF), UInt8((value >> 16) & 0xFF), UInt8((value >> 24) & 0xFF)]
}

func aesEncrypt(plain: [UInt8], iv: [UInt8], key: [UInt8]) -> [UInt8] {
    var cipher = [UInt8](repeating: 0, count: plain.count)
    var moved = 0
    let status = CCCrypt(
        CCOperation(kCCEncrypt), CCAlgorithm(kCCAlgorithmAES128), CCOptions(0),
        key, key.count, iv,
        plain, plain.count, &cipher, cipher.count, &moved
    )
    precondition(status == kCCSuccess && moved == plain.count, "夹具加密失败")
    return cipher
}

let fixtureKey: [UInt8] = [
    0x18, 0xF6, 0x32, 0x66, 0x05, 0xBD, 0x17, 0x8A,
    0x55, 0x24, 0x52, 0x3A, 0xC0, 0xA0, 0xC6, 0x09
]

/// 在明文尾部补齐对齐填充，并写入 MD5(明文[4 ..< L-28]) + 12 字节 padding。
func sealPlaintext(_ body: [UInt8]) -> [UInt8] {
    var plain = body
    let pad = (16 - ((plain.count + 28) % 16)) % 16
    plain += [UInt8](repeating: 0, count: pad)
    plain += Array(Insecure.MD5.hash(data: Data(plain[4...])))
    plain += [UInt8](repeating: 0, count: 12)
    precondition(plain.count % 16 == 0)
    return plain
}

func relicRecord(instance: UInt32, itemID: UInt32, effects: [UInt32], curses: [UInt32]) -> [UInt8] {
    var record = u32le(0xC000_0000 | instance)
    record += u32le(0x8000_0000 | itemID)
    record += u32le(0x8000_0000 | itemID)
    record += u32le(0xFFFF_FFFF)
    effects.forEach { record += u32le($0) }
    record += [UInt8](repeating: 0xFF, count: 8) + [0x00, 0x00, 0x00, 0xFF]
    record += [UInt8](repeating: 0x00, count: 8) + [UInt8](repeating: 0xFF, count: 8)
    curses.forEach { record += u32le($0) }
    record += u32le(0xFFFF_FFFF)
    record += [UInt8](repeating: 0, count: 8)
    precondition(record.count == 80)
    return record
}

func characterPlaintext(records: [[UInt8]], name: String) -> [UInt8] {
    var body = [UInt8](repeating: 0, count: 0x14)
    records.forEach { body += $0 }
    for _ in records.count..<5120 {
        body += u32le(0) + u32le(0xFFFF_FFFF)
    }
    body += [UInt8](repeating: 0, count: 0x94)
    var units = Array(name.utf16.prefix(15))
    units += [UInt16](repeating: 0, count: 16 - units.count)
    for unit in units {
        body += [UInt8(unit & 0xFF), UInt8(unit >> 8)]
    }
    return sealPlaintext(body)
}

func publicSlotPlaintext(flags: [UInt8]?, includeMagic: Bool) -> [UInt8] {
    var body = [UInt8](repeating: 0, count: 200)
    if includeMagic {
        if let flags {
            for (index, flag) in flags.enumerated() { body[100 + index] = flag }
        }
        let faceMagic: [UInt8] = [0x27, 0x00, 0x00, 0x46, 0x41, 0x43, 0x45]
        for (index, byte) in faceMagic.enumerated() { body[161 + index] = byte }
    }
    return sealPlaintext(body)
}

func buildSave(entries: [[UInt8]], corruptChecksumOfEntry: Int? = nil) -> Data {
    var header = Array("BND4".utf8)
    header += [UInt8](repeating: 0, count: 8)
    header += u32le(UInt32(entries.count))
    header += [UInt8](repeating: 0, count: 64 - header.count)

    var blobs: [[UInt8]] = []
    for (index, plaintext) in entries.enumerated() {
        var plain = plaintext
        if index == corruptChecksumOfEntry {
            plain[plain.count - 20] ^= 0xFF
        }
        let iv = (0..<16).map { UInt8(($0 * 7 + index + 3) & 0xFF) }
        blobs.append(iv + aesEncrypt(plain: plain, iv: iv, key: fixtureKey))
    }

    var offset = 64 + 32 * entries.count
    var table = [UInt8]()
    for blob in blobs {
        table += [0x40, 0x00, 0x00, 0x00, 0xFF, 0xFF, 0xFF, 0xFF]
        table += u32le(UInt32(blob.count))
        table += u32le(0)
        table += u32le(UInt32(offset))
        table += u32le(0)
        table += u32le(0)
        table += u32le(0)
        offset += blob.count
    }
    return Data(header + table + blobs.flatMap { $0 })
}

let weaponRecord = u32le(0x8000_0123) + u32le(0x0011_2233) + [UInt8](repeating: 0, count: 80)
let armorRecord = u32le(0x9000_0001) + u32le(0x0000_0456) + [UInt8](repeating: 0, count: 8)
let emptyRecord = u32le(0) + u32le(0xFFFF_FFFF)

let slot0Plain = characterPlaintext(
    records: [
        weaponRecord,
        armorRecord,
        relicRecord(
            instance: 1,
            itemID: 2_000_002,
            effects: [6_005_601, 6_610_400, 0xFFFF_FFFF],
            curses: [6_820_000, 0x0000_0000, 0xFFFF_FFFF]
        ),
        emptyRecord,
        relicRecord(
            instance: 2,
            itemID: 202,
            effects: [6_630_000, 7_000_000, 7_000_100],
            curses: [0xFFFF_FFFF, 0xFFFF_FFFF, 0xFFFF_FFFF]
        )
    ],
    name: "夜行者甲"
)
let slot1Plain = characterPlaintext(
    records: [
        relicRecord(
            instance: 3,
            itemID: 1040,
            effects: [7_040_300, 7_040_400, 0xFFFF_FFFF],
            curses: [0xFFFF_FFFF, 0xFFFF_FFFF, 0xFFFF_FFFF]
        )
    ],
    name: "夜行者乙"
)
let stubPlain = sealPlaintext([UInt8](repeating: 0, count: 4))
var fixtureEntries: [[UInt8]] = [slot0Plain, slot1Plain]
fixtureEntries += Array(repeating: stubPlain, count: 8)
fixtureEntries.append(publicSlotPlaintext(flags: [1, 1, 0, 0, 0, 0, 0, 0, 0, 0], includeMagic: true))

let fixtureSave = buildSave(entries: fixtureEntries)
let parsed = try SaveFileParser.parse(data: fixtureSave, fileName: "NR0000.sl2")
try expect(parsed.fileName == "NR0000.sl2", "解析结果应保留文件名")
try expect(parsed.checksumOk, "合成存档全部条目校验和应通过")
try expect(parsed.characters.count == 2, "占用标志应筛出两个角色")
try expect(parsed.characters.map(\.slot) == [0, 1], "角色槽位应为 0 与 1")
try expect(parsed.characters[0].name == "夜行者甲", "角色 0 名字应按 UTF-16LE 读取")
try expect(parsed.characters[1].name == "夜行者乙", "角色 1 名字应按 UTF-16LE 读取")
try expect(parsed.characters.allSatisfy { $0.parseError == nil }, "合成存档不应产生槽位解析错误")
try expect(parsed.characters[0].relics.count == 2, "角色 0 应解析出两件遗物（穿插武器/防具/空槽）")
let fixtureRelic0 = parsed.characters[0].relics[0]
try expect(fixtureRelic0.index == 0 && fixtureRelic0.itemID == 2_000_002, "遗物 0 应还原 realItemId")
try expect(fixtureRelic0.effects == [6_005_601, 6_610_400, -1], "遗物 0 词条应把 0xFFFFFFFF 归一化为 -1")
try expect(fixtureRelic0.curses == [6_820_000, -1, -1], "遗物 0 诅咒应把 0 与 0xFFFFFFFF 都归一化为 -1")
let fixtureRelic1 = parsed.characters[0].relics[1]
try expect(fixtureRelic1.index == 1 && fixtureRelic1.itemID == 202, "遗物 1 应保持遗物序号连续")
try expect(parsed.characters[1].relics.map(\.itemID) == [1040], "角色 1 应解析出唯一遗物 1040")

let corruptSave = buildSave(entries: fixtureEntries, corruptChecksumOfEntry: 0)
let corruptParsed = try SaveFileParser.parse(data: corruptSave, fileName: "NR0000.sl2")
try expect(!corruptParsed.checksumOk, "MD5 被篡改时 checksumOk 应为 false")
try expect(corruptParsed.characters.count == 2, "校验和异常不应阻断解析")

var noMagicEntries = fixtureEntries
noMagicEntries[10] = publicSlotPlaintext(flags: nil, includeMagic: false)
let noMagicParsed = try SaveFileParser.parse(data: buildSave(entries: noMagicEntries), fileName: "NR0000.co2")
try expect(noMagicParsed.characters.count == 10, "找不到占用标志时应视为全部占用")
try expect(noMagicParsed.characters[5].parseError != nil, "空白槽位应记录 parseError 而不中断整体解析")
try expect(noMagicParsed.characters[0].relics.count == 2, "全部占用回退下角色 0 仍应正常解析")

do {
    _ = try SaveFileParser.parse(data: Data("XXXX0000".utf8), fileName: "bad.sl2")
    throw CheckFailure(description: "非 BND4 输入应报错")
} catch let error as SaveFileError {
    try expect(error == .notASaveFile, "非 BND4 输入应报「不是有效的存档文件」")
}
do {
    _ = try SaveFileParser.parse(data: fixtureSave.prefix(80), fileName: "truncated.sl2")
    throw CheckFailure(description: "截断的条目头表应报错")
} catch let error as SaveFileError {
    // 与 Windows 端口径一致：头表按条目逐行校验，越界报「条目损坏」
    if case .corruptEntry = error {
        passed += 1
    } else {
        throw CheckFailure(description: "条目头表越界应报条目损坏，实际 \(error)")
    }
}
do {
    _ = try SaveFileParser.parse(data: fixtureSave.prefix(500), fileName: "truncated.sl2")
    throw CheckFailure(description: "条目数据越界应报错")
} catch let error as SaveFileError {
    if case .corruptEntry = error {
        passed += 1
    } else {
        throw CheckFailure(description: "条目数据越界应报条目损坏，实际 \(error)")
    }
}

// ===== 审计规则合成用例（真实 relics.json + affixes.json） =====

let relicDataURL = projectRoot.appendingPathComponent("Sources/NightreignRelicChecker/Resources/relics.json")
let relicData = try RelicDataLoader.load(from: relicDataURL)
try expect(relicData.relicsSchemaVersion == 1, "relics.json schema 应为 1")
try expect(relicData.relics.count == 1397, "遗物表应为 1397 件")
try expect(relicData.pools.count == 598, "槽池应为 598 个")
try expect(relicData.extraAffixes.count == 1552, "extraAffixes 应为 1552 条（全量 AttachEffectParam 补充）")

let auditContext = RelicAuditContext(catalog: catalog, relicData: relicData)
let auditor = RelicAuditor()

func saveRelic(index: Int = 0, id: Int, effects: [Int], curses: [Int] = [-1, -1, -1]) -> SaveRelic {
    SaveRelic(index: index, itemID: id, effects: effects, curses: curses)
}

func auditKinds(_ result: RelicAuditResult) -> [String] {
    result.issues.map(\.kind.rawValue)
}

func expectAudit(
    _ relic: SaveRelic,
    status: RelicAuditStatus,
    kinds: [String],
    warningKinds: [String] = [],
    _ label: String
) throws {
    let result = auditor.audit(relic, context: auditContext)
    try expect(result.status == status, "\(label)：status 应为 \(status.rawValue)，实际 \(result.status.rawValue)")
    try expect(auditKinds(result) == kinds, "\(label)：issue kinds 应为 \(kinds)，实际 \(auditKinds(result))")
    let actualWarnings = result.warnings.map(\.kind.rawValue)
    try expect(actualWarnings == warningKinds, "\(label)：warning kinds 应为 \(warningKinds)，实际 \(actualWarnings)")
}

// 合法：普通商店遗物（slots [310,210,110]）与深夜遗物（slots [A,B,B] + 诅咒槽）
try expectAudit(
    saveRelic(id: 202, effects: [6_630_000, 7_000_000, 7_000_100]),
    status: .valid, kinds: [], "普通商店遗物合法组合"
)
try expectAudit(
    saveRelic(id: 2_000_002, effects: [6_005_601, 6_003_000, 6_003_100], curses: [6_820_000, -1, -1]),
    status: .valid, kinds: [], "深夜遗物严格口径合法组合"
)

// §4.1-4.4
try expectAudit(saveRelic(id: 424_242, effects: [-1, -1, -1]), status: .invalid, kinds: ["unknownItem"], "未知遗物 ID")
try expectAudit(saveRelic(id: 20_000, effects: [-1, -1, -1]), status: .invalid, kinds: ["illegalRange", "effectMissing"], "作弊器 ID 区段")
try expectAudit(saveRelic(id: 1, effects: [8_100_100, -1, -1]), status: .invalid, kinds: ["outOfRange"], "超出合法 ID 范围")
try expectAudit(
    saveRelic(id: 202, effects: [7_000_000, 999_999, 7_000_100]),
    status: .invalid, kinds: ["unknownEffect"], "未知词条 ID"
)

// §4.5-4.6
try expectAudit(
    saveRelic(id: 202, effects: [7_001_400, 7_001_400, 7_000_000]),
    status: .invalid, kinds: ["duplicate", "conflict"], "词条重复（同词条必然同互斥组）"
)
try expectAudit(
    saveRelic(id: 202, effects: [7_001_400, 7_001_401, 7_000_000]),
    status: .invalid, kinds: ["conflict"], "互斥词条同时出现"
)

// §4.7 槽池与诅咒配对
try expectAudit(
    saveRelic(id: 2_000_000, effects: [6_005_601, 6_003_000, -1], curses: [6_820_000, -1, -1]),
    status: .invalid, kinds: ["effectUnexpected"], "多余的正面词条"
)
try expectAudit(
    saveRelic(id: 2_000_002, effects: [6_005_601, -1, -1], curses: [6_820_000, -1, -1]),
    status: .invalid, kinds: ["effectMissing"], "正面词条数量不足（按行配对模型合并为一条）"
)
try expectAudit(
    saveRelic(id: 2_000_002, effects: [6_005_601, 7_000_000, 6_003_000], curses: [6_820_000, -1, -1]),
    status: .invalid, kinds: ["slotMismatch"], "正面词条不在对应槽池"
)
try expectAudit(
    saveRelic(id: 2_000_002, effects: [6_005_601, 6_003_000, 6_003_100], curses: [6_820_000, 6_820_100, -1]),
    status: .invalid, kinds: ["curseUnexpected"], "多余的负面词条"
)
try expectAudit(
    saveRelic(id: 2_000_002, effects: [6_005_601, 6_003_000, 6_003_100]),
    status: .invalid, kinds: ["curseMissing"], "需诅咒词条缺少负面词条（按行配对）"
)
try expectAudit(
    saveRelic(id: 2_000_002, effects: [6_003_000, 6_003_100, 6_003_200]),
    status: .valid, kinds: [], "全部正面词条不需诅咒且无负面词条即合法"
)
try expectAudit(
    saveRelic(id: 2_000_002, effects: [6_005_601, 6_003_000, 6_003_100], curses: [7_000_000, -1, -1]),
    status: .invalid, kinds: ["curseMismatch"], "负面词条不在诅咒池"
)

// 按行配对：第 3 行需诅咒词条缺少负面词条（参数行槽池排列不再作为依据）
try expectAudit(
    saveRelic(id: 2_000_002, effects: [6_005_601, 6_003_000, 6_610_400], curses: [6_820_000, -1, -1]),
    status: .invalid, kinds: ["curseMissing"], "第 3 行需诅咒词条缺少负面词条"
)
// 深夜词条数量与槽数不符
try expectAudit(
    saveRelic(id: 2_000_002, effects: [6_003_000, -1, -1]),
    status: .invalid, kinds: ["effectMissing"], "深夜正面词条数量不足"
)
// 唯一遗物的固定词条被修改 → 非法（参数表的单词条固定池经真实存档交叉验证准确）
try expectAudit(
    saveRelic(id: 1_660, effects: [7_031_300, 7_060_200, 7_000_802]),
    status: .invalid, kinds: ["slotMismatch", "slotMismatch", "slotMismatch"], "唯一遗物固定词条被修改判非法"
)
// 官方原始词条则核验通过
try expectAudit(
    saveRelic(id: 1_660, effects: [6_641_000, 7_000_302, 7_000_402]),
    status: .valid, kinds: [], "唯一遗物官方固定词条核验通过"
)
// 被改动的唯一遗物应给出官方固定词条（便于改回）；合法时不给出
let modified1660 = auditor.audit(
    saveRelic(id: 1_660, effects: [7_031_300, 7_060_200, 7_000_802]),
    context: auditContext
)
try expect(
    modified1660.officialEffects == [6_641_000, 7_000_302, 7_000_402],
    "被改动的 1660 应给出官方固定词条，实际 \(String(describing: modified1660.officialEffects))"
)
let intact1660 = auditor.audit(
    saveRelic(id: 1_660, effects: [6_641_000, 7_000_302, 7_000_402]),
    context: auditContext
)
try expect(intact1660.officialEffects == nil, "未被改动的唯一遗物不应给出官方词条块")

// §4.10 保存顺序
let wrongOrderResult = auditor.audit(
    saveRelic(id: 202, effects: [7_000_000, 6_630_000, 7_000_100]),
    context: auditContext
)
try expect(wrongOrderResult.status == .invalid, "保存顺序错误应判非法")
try expect(auditKinds(wrongOrderResult) == ["wrongOrder"], "保存顺序错误应只报 wrongOrder")
try expect(wrongOrderResult.orderedEffects == [6_630_000, 7_000_000, 7_000_100], "应给出正确的保存顺序")

// 唯一遗物重复持有（含首件非法时的豁免转移）
var uniqueRelics = [
    saveRelic(index: 0, id: 1040, effects: [7_040_300, 7_040_400, -1]),
    saveRelic(index: 1, id: 1040, effects: [7_040_300, 7_040_400, -1])
]
var uniqueResults = uniqueRelics.map { auditor.audit($0, context: auditContext) }
auditor.applyUniqueDuplicates(&uniqueResults, relics: uniqueRelics)
try expect(auditKinds(uniqueResults[0]) == [], "唯一遗物首件合法者应豁免")
try expect(auditKinds(uniqueResults[1]) == ["uniqueDuplicate"], "唯一遗物第二件应追加 uniqueDuplicate")
try expect(uniqueResults[1].status == .invalid, "追加 uniqueDuplicate 后 status 应转为 invalid")

uniqueRelics = [
    saveRelic(index: 0, id: 1040, effects: [7_040_400, 7_040_300, -1]),
    saveRelic(index: 1, id: 1040, effects: [7_040_300, 7_040_400, -1])
]
uniqueResults = uniqueRelics.map { auditor.audit($0, context: auditContext) }
auditor.applyUniqueDuplicates(&uniqueResults, relics: uniqueRelics)
try expect(auditKinds(uniqueResults[0]) == ["wrongOrder", "uniqueDuplicate"], "首件非法时豁免应转移给首个合法者")
try expect(auditKinds(uniqueResults[1]) == [], "首个合法者应保持合法")

// §3 种类/颜色/名称标签
try expect(relicKindLabel(id: 2_000_002, info: auditContext.relicsByID[2_000_002]) == "深夜遗物", "深夜遗物标签")
try expect(relicKindLabel(id: 1040, info: auditContext.relicsByID[1040]) == "唯一遗物", "唯一遗物标签")
try expect(relicKindLabel(id: 150, info: nil) == "商店遗物（旧版）", "旧版商店遗物标签")
try expect(relicKindLabel(id: 250, info: nil) == "商店遗物", "商店遗物标签")
try expect(relicKindLabel(id: 1_000_005, info: nil) == "对局奖励", "对局奖励标签")
try expect(relicKindLabel(id: 424_242, info: nil) == "遗物", "默认遗物标签")
try expect([0, 1, 2, 3, 4].map(relicColorLabel) == ["红", "蓝", "黄", "绿", "白"], "颜色标签映射")
try expect(relicDisplayName(id: 2_000_002, info: auditContext.relicsByID[2_000_002]) == "辽阔的火燃暗淡情景", "已知遗物名称")
try expect(relicDisplayName(id: 1, info: auditContext.relicsByID[1]) == "未命名遗物 #1", "空名称遗物回退")
try expect(relicDisplayName(id: 424_242, info: nil) == "未知遗物 #424242", "未知遗物名称回退")

// ===== 与 JS 端对拍（testdata/audit_cases.json） =====

struct AuditCaseRelic: Decodable {
    let itemId: Int
    let effects: [Int]
    let curses: [Int]
}

struct AuditCase: Decodable {
    let name: String
    let relic: AuditCaseRelic
    let expectStatus: String
    let expectIssueKinds: [String]
    let expectWarningKinds: [String]?
}

struct AuditUniqueCase: Decodable {
    let name: String?
    let relics: [AuditCaseRelic]
    let expectKindsPerRelic: [[String]]
}

struct AuditCaseFile: Decodable {
    let cases: [AuditCase]
    let uniqueCases: [AuditUniqueCase]?
}

let auditCasesURL = projectRoot
    .deletingLastPathComponent()
    .appendingPathComponent("testdata/audit_cases.json")
if FileManager.default.fileExists(atPath: auditCasesURL.path) {
    let caseFile = try JSONDecoder().decode(AuditCaseFile.self, from: Data(contentsOf: auditCasesURL))
    for auditCase in caseFile.cases {
        let relic = SaveRelic(
            index: 0,
            itemID: auditCase.relic.itemId,
            effects: auditCase.relic.effects,
            curses: auditCase.relic.curses
        )
        let result = auditor.audit(relic, context: auditContext)
        try expect(
            result.status.rawValue == auditCase.expectStatus,
            "对拍 \(auditCase.name)：status 应为 \(auditCase.expectStatus)，实际 \(result.status.rawValue)"
        )
        try expect(
            auditKinds(result) == auditCase.expectIssueKinds,
            "对拍 \(auditCase.name)：issue kinds 应为 \(auditCase.expectIssueKinds)，实际 \(auditKinds(result))"
        )
        let expectedWarnings = auditCase.expectWarningKinds ?? []
        try expect(
            result.warnings.map(\.kind.rawValue) == expectedWarnings,
            "对拍 \(auditCase.name)：warning kinds 应为 \(expectedWarnings)，实际 \(result.warnings.map(\.kind.rawValue))"
        )
    }
    for (caseIndex, uniqueCase) in (caseFile.uniqueCases ?? []).enumerated() {
        let relics = uniqueCase.relics.enumerated().map { index, relic in
            SaveRelic(index: index, itemID: relic.itemId, effects: relic.effects, curses: relic.curses)
        }
        var results = relics.map { auditor.audit($0, context: auditContext) }
        auditor.applyUniqueDuplicates(&results, relics: relics)
        let actual = results.map(auditKinds)
        try expect(
            actual == uniqueCase.expectKindsPerRelic,
            "对拍 unique #\(caseIndex)（\(uniqueCase.name ?? "未命名")）：kinds 应为 \(uniqueCase.expectKindsPerRelic)，实际 \(actual)"
        )
    }
    print("对拍通过：\(caseFile.cases.count) 个单件用例，\(caseFile.uniqueCases?.count ?? 0) 个唯一遗物用例")
} else {
    print("对拍文件不存在，跳过：\(auditCasesURL.path)")
}

// ===== 跨端 payload 一致性（与 windows/renderer/core.js 探针输出逐字对拍） =====

// conflict 按出现顺序去重；深夜按行配对下 P2 的 kind 序列与 JS 端逐字一致
let p2 = auditor.audit(
    SaveRelic(index: 0, itemID: 2000002, effects: [6001400, 7120000, 6001401], curses: [7120100, -1, -1]),
    context: auditContext
)
try expect(
    p2.issues.map(\.kind.rawValue) == ["conflict", "slotMismatch", "curseMissing", "curseMismatch"],
    "P2 kinds 应与 JS 端一致，实际 \(p2.issues.map(\.kind.rawValue))"
)
try expect(
    p2.issues.first(where: { $0.kind == .conflict })?.effectIDs == [6001400, 7120000, 6001401, 7120100],
    "P2 conflict effectIds 应按出现顺序去重"
)
try expect(p2.orderedEffects == nil, "P2 orderedEffects 应为 nil（未评估 §4.10）")

// 合法遗物 orderedEffects 应为 nil（仅 wrongOrder 时给出）
let p3 = auditor.audit(
    SaveRelic(index: 0, itemID: 202, effects: [6630000, 7000000, 7000100], curses: [-1, -1, -1]),
    context: auditContext
)
try expect(p3.status == .valid && p3.orderedEffects == nil, "合法遗物 orderedEffects 应为 nil")

// 审计入口哨兵归一化（0 / 0xFFFFFFFF → -1）
let p4 = auditor.audit(
    SaveRelic(index: 0, itemID: 2000002, effects: [6630000, 0, 4294967295], curses: [0, -1, -1]),
    context: auditContext
)
try expect(
    p4.issues.map(\.kind.rawValue) == ["effectMissing"],
    "P4 未归一化输入 kinds 应与 JS 端一致，实际 \(p4.issues.map(\.kind.rawValue))"
)

print("RelicCoreChecks: \(passed) checks passed")

// ===== 可选：传入存档路径做真实存档端到端验证（swift run RelicCoreChecks <path.sl2>） =====
if CommandLine.arguments.count > 1 {
    let path = CommandLine.arguments[1]
    let data = try Data(contentsOf: URL(fileURLWithPath: path))
    let parsed = try SaveFileParser.parse(data: data, fileName: (path as NSString).lastPathComponent)
    print("存档: checksumOk=\(parsed.checksumOk) 角色=\(parsed.characters.count)")
    for character in parsed.characters {
        var results = character.relics.map { auditor.audit($0, context: auditContext) }
        auditor.applyUniqueDuplicates(&results, relics: character.relics)
        let invalid = zip(character.relics, results).filter { $0.1.status == .invalid }
        let warned = zip(character.relics, results).filter { $0.1.status == .valid && !$0.1.warnings.isEmpty }
        print("槽 \(character.slot) \(character.name)：遗物 \(character.relics.count) 件，非法 \(invalid.count)，警告 \(warned.count)")
        for (relic, result) in invalid {
            print("  非法 #\(relic.itemID) kinds=\(result.issues.map(\.kind.rawValue)) effects=\(relic.effects) curses=\(relic.curses)")
        }
        for (relic, result) in warned {
            print("  警告 #\(relic.itemID) kinds=\(result.warnings.map(\.kind.rawValue))")
        }
    }
}
