import Foundation

public enum CatalogError: LocalizedError {
    case unreadable
    case unsupportedSchema(Int)
    case duplicateEffectIDs([Int])
    case tooFewAffixes

    public var errorDescription: String? {
        switch self {
        case .unreadable: return "无法读取词条库文件"
        case .unsupportedSchema(let version): return "不支持的词条库版本：\(version)"
        case .duplicateEffectIDs(let ids): return "词条库包含重复 ID：\(ids.map(String.init).joined(separator: ", "))"
        case .tooFewAffixes: return "词条库中的有效正面词条不足三个"
        }
    }
}

public enum CatalogLoader {
    public static func load(from url: URL) throws -> AffixCatalog {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        guard let catalog = try? decoder.decode(AffixCatalog.self, from: data) else {
            throw CatalogError.unreadable
        }
        try validate(catalog)
        return catalog
    }

    public static func validate(_ catalog: AffixCatalog) throws {
        guard catalog.schemaVersion == 1 else {
            throw CatalogError.unsupportedSchema(catalog.schemaVersion)
        }
        let duplicates = Dictionary(grouping: catalog.affixes, by: \.effectID)
            .filter { $0.value.count > 1 }
            .map(\.key)
            .sorted()
        guard duplicates.isEmpty else { throw CatalogError.duplicateEffectIDs(duplicates) }
        guard catalog.affixes.filter({ !$0.isCurse }).count >= 3 else {
            throw CatalogError.tooFewAffixes
        }
    }

    public static func encode(_ catalog: AffixCatalog) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(catalog)
    }
}
