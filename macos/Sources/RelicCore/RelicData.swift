import Foundation

public struct RelicInfo: Codable, Hashable, Sendable, Identifiable {
    public let id: Int
    public let name: String
    public let color: Int
    public let deep: Bool
    public let slots: [Int]
    public let curseSlots: [Int]

    public init(id: Int, name: String, color: Int, deep: Bool, slots: [Int], curseSlots: [Int]) {
        self.id = id
        self.name = name
        self.color = color
        self.deep = deep
        self.slots = slots
        self.curseSlots = curseSlots
    }
}

public struct ExtraAffix: Codable, Hashable, Sendable {
    public let effectID: Int
    public let name: String
    public let sortID: Int
    public let compatibilityID: Int

    private enum CodingKeys: String, CodingKey {
        case effectID = "effectId"
        case name
        case sortID = "sortId"
        case compatibilityID = "compatibilityId"
    }

    public init(effectID: Int, name: String, sortID: Int, compatibilityID: Int) {
        self.effectID = effectID
        self.name = name
        self.sortID = sortID
        self.compatibilityID = compatibilityID
    }
}

public struct RelicCatalog: Codable, Sendable {
    public let relicsSchemaVersion: Int
    public let gameVersion: String
    public let dataVersion: String
    public let generatedAt: String
    public let sources: [CatalogSource]
    public let relics: [RelicInfo]
    public let pools: [String: [Int]]
    public let extraAffixes: [ExtraAffix]

    public init(
        relicsSchemaVersion: Int = 1,
        gameVersion: String,
        dataVersion: String,
        generatedAt: String,
        sources: [CatalogSource],
        relics: [RelicInfo],
        pools: [String: [Int]],
        extraAffixes: [ExtraAffix]
    ) {
        self.relicsSchemaVersion = relicsSchemaVersion
        self.gameVersion = gameVersion
        self.dataVersion = dataVersion
        self.generatedAt = generatedAt
        self.sources = sources
        self.relics = relics
        self.pools = pools
        self.extraAffixes = extraAffixes
    }
}

public enum RelicDataError: LocalizedError {
    case unreadable
    case unsupportedSchema(Int)

    public var errorDescription: String? {
        switch self {
        case .unreadable: return "无法读取遗物数据文件"
        case .unsupportedSchema(let version): return "不支持的遗物数据版本：\(version)"
        }
    }
}

public enum RelicDataLoader {
    public static func load(from url: URL) throws -> RelicCatalog {
        guard let data = try? Data(contentsOf: url) else {
            throw RelicDataError.unreadable
        }
        return try load(from: data)
    }

    public static func load(from data: Data) throws -> RelicCatalog {
        guard let catalog = try? JSONDecoder().decode(RelicCatalog.self, from: data) else {
            throw RelicDataError.unreadable
        }
        try validate(catalog)
        return catalog
    }

    public static func validate(_ catalog: RelicCatalog) throws {
        guard catalog.relicsSchemaVersion == 1 else {
            throw RelicDataError.unsupportedSchema(catalog.relicsSchemaVersion)
        }
    }
}
