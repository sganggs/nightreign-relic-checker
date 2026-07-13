import Foundation

public enum CheckMode: String, CaseIterable, Codable, Identifiable, Sendable {
    case currentNormal
    case legacyNormal
    case deepPositive
    case compatibilityOnly

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .currentNormal: return "普通 1.03"
        case .legacyNormal: return "普通旧池"
        case .deepPositive: return "深夜正面"
        case .compatibilityOnly: return "顺序/互斥"
        }
    }

    public var shortTitle: String {
        switch self {
        case .currentNormal: return "1.03"
        case .legacyNormal: return "旧池"
        case .deepPositive: return "深夜"
        case .compatibilityOnly: return "通用"
        }
    }

    public var detail: String {
        switch self {
        case .currentNormal:
            return "严格检查 1.03 / DLC 后普通大遗物的非零权重词条池。"
        case .legacyNormal:
            return "严格检查 1.02 及更早的普通大遗物词条池。"
        case .deepPositive:
            return "按真实七种三槽模板预检深夜正面词条、互斥与顺序；不替代具体遗物 ID 与负面词条配对校验。"
        case .compatibilityOnly:
            return "只检查词条是否重复、互斥，以及保存顺序；适合固定遗物或来源不明的组合。"
        }
    }

    public var slotPoolSequences: [[Int]] {
        switch self {
        case .currentNormal:
            return [[110, 210, 310]]
        case .legacyNormal:
            return [[100, 200, 300]]
        case .deepPositive:
            return [
                [2_000_000, 2_000_000, 2_000_000],
                [2_000_000, 2_000_000, 2_100_000],
                [2_000_000, 2_100_000, 2_100_000],
                [2_100_000, 2_100_000, 2_100_000],
                [2_000_000, 2_000_000, 2_200_000],
                [2_000_000, 2_200_000, 2_200_000],
                [2_200_000, 2_200_000, 2_200_000]
            ]
        case .compatibilityOnly: return []
        }
    }

    public var eligiblePoolIDs: [Int] {
        Array(Set(slotPoolSequences.flatMap { $0 })).sorted()
    }
}
