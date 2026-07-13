import Foundation

public struct Affix: Codable, Identifiable, Hashable, Sendable {
    public let effectID: Int
    public let name: String
    public let aliases: [String]
    public let category: String
    public let explanation: String
    public let superposability: String
    public let compatibilityID: Int
    public let sortID: Int
    public let poolIDs: [Int]
    public let isCurse: Bool
    public let requiresCurse: Bool
    public let popularity: Int?
    public let source: String

    public var id: Int { effectID }

    private enum CodingKeys: String, CodingKey {
        case effectID = "effectId"
        case name
        case aliases
        case category
        case explanation
        case superposability
        case compatibilityID = "compatibilityId"
        case sortID = "sortId"
        case poolIDs = "poolIds"
        case isCurse
        case requiresCurse
        case popularity
        case source
    }

    public init(
        effectID: Int,
        name: String,
        aliases: [String] = [],
        category: String = "未分类",
        explanation: String = "",
        superposability: String = "未知",
        compatibilityID: Int = -1,
        sortID: Int,
        poolIDs: [Int] = [],
        isCurse: Bool = false,
        requiresCurse: Bool = false,
        popularity: Int? = nil,
        source: String = ""
    ) {
        self.effectID = effectID
        self.name = name
        self.aliases = aliases
        self.category = category
        self.explanation = explanation
        self.superposability = superposability
        self.compatibilityID = compatibilityID
        self.sortID = sortID
        self.poolIDs = poolIDs
        self.isCurse = isCurse
        self.requiresCurse = requiresCurse
        self.popularity = popularity
        self.source = source
    }

    public var searchableText: String {
        ([name, category, String(effectID)] + aliases).joined(separator: " ").foldedForSearch
    }

    public func isEligible(for mode: CheckMode) -> Bool {
        if mode == .compatibilityOnly { return !isCurse }
        return !isCurse && !Set(poolIDs).isDisjoint(with: Set(mode.eligiblePoolIDs))
    }
}

public struct CatalogSource: Codable, Hashable, Sendable {
    public let name: String
    public let url: String
    public let revision: String
    public let license: String

    public init(name: String, url: String, revision: String = "", license: String = "") {
        self.name = name
        self.url = url
        self.revision = revision
        self.license = license
    }
}

public struct AffixCatalog: Codable, Sendable {
    public let schemaVersion: Int
    public let gameVersion: String
    public let dataVersion: String
    public let generatedAt: String
    public let sources: [CatalogSource]
    public let affixes: [Affix]

    public init(
        schemaVersion: Int = 1,
        gameVersion: String,
        dataVersion: String,
        generatedAt: String,
        sources: [CatalogSource],
        affixes: [Affix]
    ) {
        self.schemaVersion = schemaVersion
        self.gameVersion = gameVersion
        self.dataVersion = dataVersion
        self.generatedAt = generatedAt
        self.sources = sources
        self.affixes = affixes
    }
}

public extension String {
    var foldedForSearch: String {
        folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "，", with: ",")
            .replacingOccurrences(of: "＋", with: "+")
            .lowercased()
    }
}
