import Foundation

/// 遗物身份：`itemId` + 三条正面词条 + 三条诅咒，都按存档里的顺序。
///
/// 存档里同一件遗物在不同存档中可能落在不同的物品序号上，所以身份只由内容
/// 决定，不含 `index`。三条正面与三条诅咒各自保持存档顺序参与比较：
/// 词条顺序本身会影响合法性判定（`RelicAuditor` 会报「词条顺序错误」），
/// 换序后的遗物可能一件合法一件非法，把它们当成同一件会让对比显示「没有差异」
/// 而状态其实变了。行内的正负配对关系同样保留（换了诅咒就是另一件）。
///
/// 与 Windows 端 `renderer/savediff.js` 的 `relicIdentity` 同一口径。
public struct SaveRelicIdentity: Hashable, Sendable, Comparable {
    /// 一行：正面词条与同一行的负面词条（空为 -1）。
    public struct Row: Hashable, Comparable, Sendable {
        public let effect: Int
        public let curse: Int

        public init(effect: Int, curse: Int) {
            self.effect = effect
            self.curse = curse
        }

        public static func < (lhs: Row, rhs: Row) -> Bool {
            lhs.effect == rhs.effect ? lhs.curse < rhs.curse : lhs.effect < rhs.effect
        }
    }

    public let itemID: Int
    /// 固定 3 行，按存档里的顺序（不排序）。
    public let rows: [Row]

    public init(_ relic: SaveRelic) {
        let effects = Self.normalized(relic.effects)
        let curses = Self.normalized(relic.curses)
        itemID = relic.itemID
        rows = (0..<3).map { Row(effect: effects[$0], curse: curses[$0]) }
    }

    /// 稳定的字符串键（`Identifiable` 与报告里用）。
    public var key: String {
        ([String(itemID)] + rows.map { "\($0.effect):\($0.curse)" }).joined(separator: "|")
    }

    public static func < (lhs: SaveRelicIdentity, rhs: SaveRelicIdentity) -> Bool {
        if lhs.itemID != rhs.itemID { return lhs.itemID < rhs.itemID }
        for (left, right) in zip(lhs.rows, rhs.rows) where left != right {
            return left < right
        }
        return false
    }

    /// 与 `RelicAuditor` 一致的空哨兵归一化（0 / 0xFFFFFFFF / 负值 → -1），并补齐到 3 位。
    private static func normalized(_ values: [Int]) -> [Int] {
        let filled = Array((values + Array(repeating: -1, count: 3)).prefix(3))
        return filled.map { ($0 <= 0 || $0 == 0xFFFF_FFFF) ? -1 : $0 }
    }
}

/// 对比结果里的一项：某个身份的遗物多出/少掉了几件。
public struct SaveCompareEntry: Identifiable, Sendable {
    public let identity: SaveRelicIdentity
    /// 代表件（带审计结论，用于展示合法性状态）。
    public let relic: AuditedSave.AuditedRelic
    /// 数量差（恒 ≥ 1）。
    public let count: Int

    public var id: String { identity.key }

    public init(identity: SaveRelicIdentity, relic: AuditedSave.AuditedRelic, count: Int) {
        self.identity = identity
        self.relic = relic
        self.count = count
    }
}

/// 一个角色槽位的对比结果。
public struct SaveCompareCharacter: Identifiable, Sendable {
    public let slot: Int
    /// 当前存档里的角色名；该槽位在当前存档中不存在时为 nil。
    public let baseName: String?
    /// 对比存档里的角色名；该槽位在对比存档中不存在时为 nil。
    public let otherName: String?
    /// 当前存档里该槽位的解析错误（解密失败时遗物列表为空但槽位并非真的空）。
    public let baseParseError: String?
    /// 对比存档里该槽位的解析错误。
    public let otherParseError: String?
    public let baseTotal: Int
    public let otherTotal: Int
    /// 对比存档多出的遗物。任一侧解析失败时恒为空：那个槽位读不出遗物，
    /// 拿空列表去比会把「读不出来」报成「一件不剩」。
    public let added: [SaveCompareEntry]
    /// 对比存档少掉的遗物。任一侧解析失败时恒为空，理由同 `added`。
    public let removed: [SaveCompareEntry]

    public var id: Int { slot }

    public var addedCount: Int { added.reduce(0) { $0 + $1.count } }

    public var removedCount: Int { removed.reduce(0) { $0 + $1.count } }

    /// 只看遗物多重集：两侧完全相同（解析失败的槽位不产出增减，也算「相同」，
    /// 展示层用 `hasParseError` 区分）。
    public var isIdentical: Bool { added.isEmpty && removed.isEmpty }

    /// 这个槽位是否算「有差异的角色」（解析失败不算，它只是读不出来）。
    public var isChanged: Bool { !hasParseError && !isIdentical }

    /// 至少有一侧解析失败：该槽位读不出遗物，只提示、不产出增减。
    public var hasParseError: Bool { baseParseError != nil || otherParseError != nil }

    /// 这个槽位是否有任何值得展示的差异（遗物增减 / 角色名变化 / 解析失败）。
    ///
    /// 视图的「只看有差异的角色」开关用这一项过滤：只看 `isIdentical`
    /// 会把「改名」与「解析失败」这两类提示一起吞掉。
    public var hasAnyDifference: Bool { !isIdentical || presenceNote != nil || hasParseError }

    public var displayName: String {
        let name = baseName ?? otherName ?? ""
        return name.isEmpty ? "槽位 \(slot + 1)" : "槽位 \(slot + 1) · \(name)"
    }

    /// 只在一侧存在，或两侧角色名不同时的提示；无异常时为 nil。
    public var presenceNote: String? {
        if baseName == nil { return "该槽位只在对比存档中存在" }
        if otherName == nil { return "该槽位只在当前存档中存在" }
        if let base = baseName, let other = otherName, base != other {
            return "两份存档的同一槽位角色名不同：\(base) → \(other)"
        }
        return nil
    }

    /// 解析失败提示；该槽位读不出遗物，只提示、不产出增减。
    public var parseNote: String? {
        var sides: [String] = []
        if let baseParseError { sides.append("当前存档：\(baseParseError)") }
        if let otherParseError { sides.append("对比存档：\(otherParseError)") }
        guard !sides.isEmpty else { return nil }
        return "该槽位解析失败，无法对比（" + sides.joined(separator: "；") + "）"
    }

    public init(
        slot: Int,
        baseName: String?,
        otherName: String?,
        baseParseError: String? = nil,
        otherParseError: String? = nil,
        baseTotal: Int,
        otherTotal: Int,
        added: [SaveCompareEntry],
        removed: [SaveCompareEntry]
    ) {
        self.slot = slot
        self.baseName = baseName
        self.otherName = otherName
        self.baseParseError = baseParseError
        self.otherParseError = otherParseError
        self.baseTotal = baseTotal
        self.otherTotal = otherTotal
        self.added = added
        self.removed = removed
    }
}

/// 两份存档的对比结果。
public struct SaveCompareResult: Sendable {
    public let baseFileName: String
    public let otherFileName: String
    /// 两份存档槽位的并集，按槽位升序。
    public let characters: [SaveCompareCharacter]

    public init(baseFileName: String, otherFileName: String, characters: [SaveCompareCharacter]) {
        self.baseFileName = baseFileName
        self.otherFileName = otherFileName
        self.characters = characters
    }

    /// 新增总数；解析失败的槽位不产出增减，自然也不计入。
    public var totalAdded: Int { characters.reduce(0) { $0 + $1.addedCount } }

    /// 减少总数；解析失败的槽位不产出增减，自然也不计入。
    public var totalRemoved: Int { characters.reduce(0) { $0 + $1.removedCount } }

    /// 当前存档的遗物总件数（解析失败的槽位读出来就是 0 件）。
    public var totalBase: Int { characters.reduce(0) { $0 + $1.baseTotal } }

    /// 对比存档的遗物总件数。
    public var totalOther: Int { characters.reduce(0) { $0 + $1.otherTotal } }

    /// 有遗物增减的角色数（解析失败的槽位不算）。
    public var changedCharacters: Int { characters.filter(\.isChanged).count }

    /// 有槽位在某一侧解析失败：这些槽位的遗物读不出来，不能当成真实差异。
    public var unreliableCharacters: [SaveCompareCharacter] { characters.filter(\.hasParseError) }

    public var hasUnreliableSlots: Bool { !unreliableCharacters.isEmpty }

    /// 有「只在一侧存在 / 角色名不同」这类槽位层面的提示。
    public var hasPresenceNotes: Bool { characters.contains { $0.presenceNote != nil } }

    /// 是否存在任何差异；除遗物增减外，改名与解析失败也算（否则面板会误称「完全一致」）。
    public var hasDifferences: Bool {
        totalAdded > 0 || totalRemoved > 0 || hasPresenceNotes || hasUnreliableSlots
    }

    /// 汇总文案：「新增 N 件 · 减少 M 件」。
    public var summaryText: String { "新增 \(totalAdded) 件 · 减少 \(totalRemoved) 件" }
}

/// 按角色槽位对比两份已审计存档的遗物多重集。
public enum SaveComparator {
    /// `base` 是当前载入的存档，`other` 是选来对比的另一份：
    /// `other` 相对 `base` 多出的记为「新增」，少掉的记为「减少」。
    ///
    /// 任一侧槽位解析失败（`parseError != nil`）时不产出增减：解析失败的槽位在
    /// `SaveFileParser` 里 relics 就是空数组，拿它去比会把「读不出来」报成
    /// 「遗物被删光」。与 Windows 端 `savediff.js` 的 `unreadable` 处理一致。
    public static func compare(base: AuditedSave, other: AuditedSave) -> SaveCompareResult {
        let baseBySlot = Dictionary(base.characters.map { ($0.slot, $0) }, uniquingKeysWith: { first, _ in first })
        let otherBySlot = Dictionary(other.characters.map { ($0.slot, $0) }, uniquingKeysWith: { first, _ in first })
        let slots = Set(baseBySlot.keys).union(otherBySlot.keys).sorted()

        let characters = slots.map { slot -> SaveCompareCharacter in
            let baseCharacter = baseBySlot[slot]
            let otherCharacter = otherBySlot[slot]
            let baseRelics = baseCharacter?.relics ?? []
            let otherRelics = otherCharacter?.relics ?? []
            let baseGroups = grouped(baseRelics)
            let otherGroups = grouped(otherRelics)

            var added: [SaveCompareEntry] = []
            var removed: [SaveCompareEntry] = []
            let unreadable = baseCharacter?.parseError != nil || otherCharacter?.parseError != nil
            for identity in Set(baseGroups.keys).union(otherGroups.keys).sorted() where !unreadable {
                let baseItems = baseGroups[identity] ?? []
                let otherItems = otherGroups[identity] ?? []
                if otherItems.count > baseItems.count, let sample = otherItems.first {
                    added.append(SaveCompareEntry(
                        identity: identity,
                        relic: sample,
                        count: otherItems.count - baseItems.count
                    ))
                } else if baseItems.count > otherItems.count, let sample = baseItems.first {
                    removed.append(SaveCompareEntry(
                        identity: identity,
                        relic: sample,
                        count: baseItems.count - otherItems.count
                    ))
                }
            }

            return SaveCompareCharacter(
                slot: slot,
                baseName: baseCharacter?.name,
                otherName: otherCharacter?.name,
                baseParseError: baseCharacter?.parseError,
                otherParseError: otherCharacter?.parseError,
                baseTotal: baseRelics.count,
                otherTotal: otherRelics.count,
                added: added,
                removed: removed
            )
        }

        return SaveCompareResult(
            baseFileName: base.fileName,
            otherFileName: other.fileName,
            characters: characters
        )
    }

    private static func grouped(_ relics: [AuditedSave.AuditedRelic]) -> [SaveRelicIdentity: [AuditedSave.AuditedRelic]] {
        Dictionary(grouping: relics) { SaveRelicIdentity($0.relic) }
    }
}
