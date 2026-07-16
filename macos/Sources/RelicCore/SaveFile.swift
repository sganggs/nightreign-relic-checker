import CommonCrypto
import CryptoKit
import Foundation

public enum SaveFileError: LocalizedError, Equatable, Sendable {
    case notASaveFile
    case corruptEntry(Int)

    public var errorDescription: String? {
        switch self {
        case .notASaveFile: return "不是有效的存档文件"
        case .corruptEntry(let index): return "存档条目 \(index) 越界或魔数不符"
        }
    }
}

public struct SaveRelic: Codable, Hashable, Sendable, Identifiable {
    public let index: Int
    public let itemID: Int
    public let effects: [Int]
    public let curses: [Int]

    public var id: Int { index }

    private enum CodingKeys: String, CodingKey {
        case index
        case itemID = "itemId"
        case effects
        case curses
    }

    public init(index: Int, itemID: Int, effects: [Int], curses: [Int]) {
        self.index = index
        self.itemID = itemID
        self.effects = effects
        self.curses = curses
    }
}

public struct SaveCharacter: Codable, Sendable, Identifiable {
    public let slot: Int
    public let name: String
    public let parseError: String?
    public let relics: [SaveRelic]

    public var id: Int { slot }

    public init(slot: Int, name: String, parseError: String?, relics: [SaveRelic]) {
        self.slot = slot
        self.name = name
        self.parseError = parseError
        self.relics = relics
    }
}

public struct SaveParseResult: Codable, Sendable {
    public let fileName: String
    public let checksumOk: Bool
    public let characters: [SaveCharacter]

    public init(fileName: String, checksumOk: Bool, characters: [SaveCharacter]) {
        self.fileName = fileName
        self.checksumOk = checksumOk
        self.characters = characters
    }
}

public enum SaveFileParser {
    static let aesKey: [UInt8] = [
        0x18, 0xF6, 0x32, 0x66, 0x05, 0xBD, 0x17, 0x8A,
        0x55, 0x24, 0x52, 0x3A, 0xC0, 0xA0, 0xC6, 0x09
    ]
    private static let entryMagic: [UInt8] = [0x40, 0x00, 0x00, 0x00, 0xFF, 0xFF, 0xFF, 0xFF]
    private static let faceMagic: [UInt8] = [0x27, 0x00, 0x00, 0x46, 0x41, 0x43, 0x45]
    private static let stateSlotCount = 5120
    private static let characterSlotCount = 10

    private struct SlotError: Error {
        let message: String
    }

    public static func parse(data: Data, fileName: String) throws -> SaveParseResult {
        let bytes = [UInt8](data)
        guard bytes.count >= 64, Array(bytes[0..<4]) == Array("BND4".utf8) else {
            throw SaveFileError.notASaveFile
        }
        let entryCount = Int(readInt32(bytes, 12))
        guard entryCount > 0 else {
            throw SaveFileError.notASaveFile
        }

        // 结构校验只覆盖本功能读取的前 11 个条目头（USERDATA_0..10），
        // 与 Windows 端口径一致；条目数据层面的问题在解密阶段按槽位隔离。
        let parsed = min(entryCount, characterSlotCount + 1)
        var headers: [(size: Int, offset: Int)] = []
        for i in 0..<parsed {
            let base = 64 + 32 * i
            guard base + 32 <= bytes.count else {
                throw SaveFileError.corruptEntry(i)
            }
            let size = Int(readInt32(bytes, base + 8))
            let offset = Int(readInt32(bytes, base + 16))
            guard Array(bytes[base..<base + 8]) == entryMagic,
                  size >= 0, offset > 0, offset + size <= bytes.count else {
                throw SaveFileError.corruptEntry(i)
            }
            headers.append((size, offset))
        }

        var checksumOk = true

        func decryptEntry(_ index: Int) throws -> [UInt8] {
            let header = headers[index]
            guard header.size > 16, (header.size - 16) % 16 == 0 else {
                throw SlotError(message: "条目密文长度不是 16 的倍数")
            }
            let iv = Array(bytes[header.offset..<header.offset + 16])
            let cipher = Array(bytes[header.offset + 16..<header.offset + header.size])
            let plain = try aesDecrypt(cipher: cipher, iv: iv)
            if !verifyChecksum(plain) { checksumOk = false }
            return plain
        }

        var occupied = [Bool](repeating: true, count: characterSlotCount)
        if parsed > characterSlotCount, let publicPlain = try? decryptEntry(characterSlotCount),
           let flags = slotFlags(in: publicPlain) {
            occupied = flags
        }

        var characters: [SaveCharacter] = []
        for slot in 0..<min(characterSlotCount, parsed) where occupied[slot] {
            do {
                let plain = try decryptEntry(slot)
                characters.append(parseCharacter(slot: slot, plain: plain))
            } catch {
                let message = (error as? SlotError)?.message ?? error.localizedDescription
                characters.append(SaveCharacter(
                    slot: slot,
                    name: "槽位 \(slot + 1)",
                    parseError: "该槽位解密失败：\(message)",
                    relics: []
                ))
            }
        }

        return SaveParseResult(fileName: fileName, checksumOk: checksumOk, characters: characters)
    }

    // 单槽扫描失败时保留已解析出的遗物并记入 parseError（与 Windows 端一致），
    // 不再整槽丢弃。
    private static func parseCharacter(slot: Int, plain: [UInt8]) -> SaveCharacter {
        var offset = 0x14
        var relics: [SaveRelic] = []

        for record in 0..<stateSlotCount {
            guard offset + 8 <= plain.count else {
                return SaveCharacter(
                    slot: slot,
                    name: "槽位 \(slot + 1)",
                    parseError: "存档数据截断：第 \(record) 条物品记录越界",
                    relics: relics
                )
            }
            let gaHandle = readUInt32(plain, offset)
            let length: Int
            switch gaHandle & 0xF000_0000 {
            case 0x0000_0000: length = 8
            case 0x8000_0000: length = 88
            case 0x9000_0000: length = 16
            case 0xC000_0000: length = 80
            default: length = 8
            }
            guard offset + length <= plain.count else {
                return SaveCharacter(
                    slot: slot,
                    name: "槽位 \(slot + 1)",
                    parseError: "存档数据截断：第 \(record) 条物品记录不完整",
                    relics: relics
                )
            }
            if gaHandle & 0xF000_0000 == 0xC000_0000 {
                let itemID = Int(readUInt32(plain, offset + 4) & 0x00FF_FFFF)
                let effects = [16, 20, 24].map { normalizeEffect(readUInt32(plain, offset + $0)) }
                let curses = [56, 60, 64].map { normalizeEffect(readUInt32(plain, offset + $0)) }
                relics.append(SaveRelic(index: relics.count, itemID: itemID, effects: effects, curses: curses))
            }
            offset += length
        }

        let name = characterName(plain, at: offset + 0x94) ?? "槽位 \(slot + 1)"
        return SaveCharacter(slot: slot, name: name, parseError: nil, relics: relics)
    }

    // 名字区允许截断：只读到边界内完整的 UTF-16 单元（与 Windows 端一致）。
    private static func characterName(_ plain: [UInt8], at offset: Int) -> String? {
        guard offset >= 0, offset + 2 <= plain.count else { return nil }
        var units: [UInt16] = []
        for i in 0..<16 {
            let p = offset + i * 2
            guard p + 2 <= plain.count else { break }
            let unit = UInt16(plain[p]) | (UInt16(plain[p + 1]) << 8)
            if unit == 0 { break }
            units.append(unit)
        }
        guard !units.isEmpty else { return nil }
        let name = String(decoding: units, as: UTF16.self)
        return name.isEmpty ? nil : name
    }

    // 与参考实现一致：遍历全部 FACE 魔数命中，跳过含非 0/1 字节的假阳性，
    // 用 == 1 判定占用（与 Windows 端 slotFlags 等价）。
    private static func slotFlags(in plain: [UInt8]) -> [Bool]? {
        guard plain.count >= faceMagic.count else { return nil }
        var start = 0
        while start + faceMagic.count <= plain.count {
            guard Array(plain[start..<start + faceMagic.count]) == faceMagic else {
                start += 1
                continue
            }
            let flagsStart = start - 61
            if flagsStart >= 0, flagsStart + characterSlotCount <= plain.count {
                let candidate = Array(plain[flagsStart..<flagsStart + characterSlotCount])
                if candidate.allSatisfy({ $0 <= 1 }) {
                    return candidate.map { $0 == 1 }
                }
            }
            start += 1
        }
        return nil
    }

    private static func aesDecrypt(cipher: [UInt8], iv: [UInt8]) throws -> [UInt8] {
        var plain = [UInt8](repeating: 0, count: cipher.count)
        var moved = 0
        let status = CCCrypt(
            CCOperation(kCCDecrypt),
            CCAlgorithm(kCCAlgorithmAES128),
            CCOptions(0),
            aesKey, aesKey.count,
            iv,
            cipher, cipher.count,
            &plain, plain.count,
            &moved
        )
        guard status == kCCSuccess, moved == cipher.count else {
            throw SlotError(message: "条目解密失败")
        }
        return plain
    }

    private static func verifyChecksum(_ plain: [UInt8]) -> Bool {
        guard plain.count >= 32 else { return false }
        let digest = Insecure.MD5.hash(data: Data(plain[4..<plain.count - 28]))
        return Array(digest) == Array(plain[plain.count - 28..<plain.count - 12])
    }

    private static func normalizeEffect(_ raw: UInt32) -> Int {
        (raw == 0xFFFF_FFFF || raw == 0) ? -1 : Int(raw)
    }

    private static func readUInt32(_ bytes: [UInt8], _ offset: Int) -> UInt32 {
        UInt32(bytes[offset])
            | (UInt32(bytes[offset + 1]) << 8)
            | (UInt32(bytes[offset + 2]) << 16)
            | (UInt32(bytes[offset + 3]) << 24)
    }

    private static func readInt32(_ bytes: [UInt8], _ offset: Int) -> Int32 {
        Int32(bitPattern: readUInt32(bytes, offset))
    }
}
