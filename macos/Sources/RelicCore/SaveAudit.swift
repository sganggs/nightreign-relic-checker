import Foundation

/// 一份存档的完整审计结果：解析结果 + 逐件审计 + 展示所需的词条名与说明。
///
/// 这是「存档检查」页、报告导出与存档对比共用的数据结构；构造只走
/// `SaveAuditPipeline`，保证三处口径一致。
public struct AuditedSave: Sendable {
    /// 一件遗物 + 它的审计结论。
    public struct AuditedRelic: Identifiable, Sendable {
        public let relic: SaveRelic
        public let info: RelicInfo?
        public let result: RelicAuditResult

        public var id: Int { relic.index }
        public var isDeep: Bool { info?.deep == true }
        public var displayName: String { relicDisplayName(id: relic.itemID, info: info) }
        public var kindLabel: String { relicKindLabel(id: relic.itemID, info: info) }
        /// 颜色文案；遗物表里查不到这件遗物时为 nil。
        public var colorLabel: String? { info.map { relicColorLabel($0.color) } }

        /// 「非法 / 警告 / 合法」三态文案（页面与报告统一用这一份口径）。
        public var statusLabel: String {
            if result.status == .invalid { return "非法" }
            return result.warnings.isEmpty ? "合法" : "警告"
        }

        public init(relic: SaveRelic, info: RelicInfo?, result: RelicAuditResult) {
            self.relic = relic
            self.info = info
            self.result = result
        }
    }

    /// 一个角色槽位。
    public struct Character: Identifiable, Sendable {
        public let slot: Int
        public let name: String
        public let parseError: String?
        public let relics: [AuditedRelic]

        public var id: Int { slot }

        public var displayName: String { "槽位 \(slot + 1) · \(name)" }

        public var invalidCount: Int { relics.filter { $0.result.status == .invalid }.count }

        public var warningCount: Int {
            relics.filter { $0.result.status != .invalid && !$0.result.warnings.isEmpty }.count
        }

        public init(slot: Int, name: String, parseError: String?, relics: [AuditedRelic]) {
            self.slot = slot
            self.name = name
            self.parseError = parseError
            self.relics = relics
        }
    }

    public let fileName: String
    public let checksumOk: Bool
    /// effectId → 词条名（affixes.json ∪ extraAffixes）。
    public let affixNames: [Int: String]
    /// effectId → 词条说明（只收录 affixes.json 里非空的 explanation）。
    public let affixExplanations: [Int: String]
    public let characters: [Character]

    public init(
        fileName: String,
        checksumOk: Bool,
        affixNames: [Int: String],
        affixExplanations: [Int: String] = [:],
        characters: [Character]
    ) {
        self.fileName = fileName
        self.checksumOk = checksumOk
        self.affixNames = affixNames
        self.affixExplanations = affixExplanations
        self.characters = characters
    }

    public var relicCount: Int { characters.reduce(0) { $0 + $1.relics.count } }

    public var invalidCount: Int { characters.reduce(0) { $0 + $1.invalidCount } }

    public func affixName(_ id: Int) -> String {
        if let name = affixNames[id], !name.isEmpty { return name }
        return "未知词条 #\(id)"
    }

    /// 词条说明；没有收录说明时为 nil（页面据此不显示）。
    public func affixExplanation(_ id: Int) -> String? {
        guard let text = affixExplanations[id], !text.isEmpty else { return nil }
        return text
    }

    /// 「词条名（ID）」，报告与对比列表统一用这一份写法。
    public func affixLabel(_ id: Int) -> String {
        id == -1 ? "（空）" : "\(affixName(id))（\(id)）"
    }
}

/// 解析结果 → 审计结果的装配流程（纯逻辑，可在检查里直接调用）。
public enum SaveAuditPipeline {
    /// effectId → 词条说明（只收录非空的 explanation）。
    ///
    /// 复用 `context` 重载时由调用方建一次、传进去，避免每份存档重复遍历词条库。
    public static func explanations(from catalog: AffixCatalog) -> [Int: String] {
        var explanations: [Int: String] = [:]
        for affix in catalog.affixes where !affix.explanation.isEmpty {
            explanations[affix.effectID] = affix.explanation
        }
        return explanations
    }

    /// 用词条库与遗物表审计一份已解析的存档。
    public static func audit(
        _ parsed: SaveParseResult,
        catalog: AffixCatalog,
        relicData: RelicCatalog
    ) -> AuditedSave {
        let context = RelicAuditContext(catalog: catalog, relicData: relicData)
        return audit(parsed, context: context, affixExplanations: explanations(from: catalog))
    }

    /// 复用已经建好的审计上下文（对比两份存档时避免重复建索引）。
    ///
    /// `affixExplanations` 必填：漏传会让界面上的词条说明（ⓘ）静默消失，
    /// 没有说明可用时显式传 `[:]`，需要说明就用 `explanations(from:)` 建一份。
    public static func audit(
        _ parsed: SaveParseResult,
        context: RelicAuditContext,
        affixExplanations: [Int: String]
    ) -> AuditedSave {
        let auditor = RelicAuditor()
        let characters = parsed.characters.map { character -> AuditedSave.Character in
            var results = character.relics.map { auditor.audit($0, context: context) }
            auditor.applyUniqueDuplicates(&results, relics: character.relics)
            let relics = zip(character.relics, results).map { relic, result in
                AuditedSave.AuditedRelic(
                    relic: relic,
                    info: context.relicsByID[relic.itemID],
                    result: result
                )
            }
            return AuditedSave.Character(
                slot: character.slot,
                name: character.name,
                parseError: character.parseError,
                relics: relics
            )
        }
        return AuditedSave(
            fileName: parsed.fileName,
            checksumOk: parsed.checksumOk,
            affixNames: context.affixIndex.mapValues(\.name),
            affixExplanations: affixExplanations,
            characters: characters
        )
    }
}
