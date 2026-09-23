import AppKit
import Foundation
import SwiftUI
import RelicCore

@MainActor
final class AppModel: ObservableObject {
    /// 声明顺序即主导航顺序（`allCases`）。「词条反查」紧跟「词条检查」：两页都是按词条查，放在一块。
    enum Page: String, CaseIterable, Identifiable {
        case checker
        case lookup
        case library
        case saveScan
        case bosses
        case heroes
        case ranker
        case data

        var id: String { rawValue }

        var title: String {
            switch self {
            case .checker: return "词条检查"
            case .library: return "词条库"
            case .data: return "数据设置"
            case .saveScan: return "存档检查"
            case .bosses: return "首领数据"
            case .heroes: return "角色属性"
            case .lookup: return "词条反查"
            case .ranker: return "增伤排名"
            }
        }

        var symbol: String {
            switch self {
            case .checker: return "checkmark.seal"
            case .library: return "list.bullet.rectangle"
            case .data: return "externaldrive"
            case .saveScan: return "externaldrive.badge.checkmark"
            case .bosses: return "shield.lefthalf.filled"
            case .heroes: return "person.text.rectangle"
            case .lookup: return "magnifyingglass.circle"
            case .ranker: return "chart.bar.xaxis"
            }
        }
    }

    enum SaveFilter: String, CaseIterable, Identifiable {
        case all
        case invalidOnly
        case deepOnly

        var id: String { rawValue }

        var title: String {
            switch self {
            case .all: return "全部"
            case .invalidOnly: return "仅非法"
            case .deepOnly: return "深夜遗物"
            }
        }
    }

    @Published var page: Page = .checker
    @Published var mode: CheckMode = .currentNormal {
        didSet {
            guard oldValue != mode else { return }
            result = nil
            selectedIDs = selectedIDs.map { id in
                guard let id, let affix = byID[id], affix.isEligible(for: mode) else { return nil }
                return id
            }
        }
    }
    @Published var selectedIDs: [Int?] = [nil, nil, nil]
    @Published var result: CheckResult?
    @Published var catalog: AffixCatalog
    @Published var catalogOrigin = "内置数据"
    @Published var dataMessage = ""
    @Published var loadError: String?
    @Published var saveReport: SaveScanReport?
    @Published var saveMessage = ""
    @Published var saveFilter: SaveFilter = .all
    @Published var saveQuery = ""
    @Published var saveSelectedSlot: Int?
    /// 存档文件被拖到存档页以外的地方时的提示（与 Windows 端的全局兜底同一句话）。
    ///
    /// macOS 上落点不对不会像 WebView2 那样导航到 .sl2，但会「什么都不发生」，
    /// 用户以为拖拽功能坏了；这里给一句和 Windows 一样的提示。
    @Published var strayDropHint = ""

    let checker = LegalityChecker()
    private(set) var relicData: RelicCatalog?
    private(set) var relicDataError: String?

    private var byID: [Int: Affix] {
        Dictionary(uniqueKeysWithValues: catalog.affixes.map { ($0.effectID, $0) })
    }

    init() {
        let empty = AffixCatalog(
            gameVersion: "未知",
            dataVersion: "不可用",
            generatedAt: "",
            sources: [],
            affixes: []
        )
        catalog = empty

        do {
            if let customURL = Self.customCatalogURL, FileManager.default.fileExists(atPath: customURL.path) {
                catalog = try CatalogLoader.load(from: customURL)
                catalogOrigin = "自定义数据"
            } else {
                catalog = try CatalogLoader.load(from: Self.bundledCatalogURL())
            }
        } catch {
            loadError = error.localizedDescription
        }

        do {
            relicData = try RelicDataLoader.load(from: Self.bundledRelicDataURL())
        } catch {
            relicDataError = error.localizedDescription
        }
    }

    var selectedAffixes: [Affix] {
        selectedIDs.compactMap { id in id.flatMap { byID[$0] } }
    }

    var positiveAffixes: [Affix] {
        catalog.affixes.filter { !$0.isCurse }
    }

    var eligibleAffixes: [Affix] {
        positiveAffixes.filter { $0.isEligible(for: mode) }
    }

    var popularAffixes: [Affix] {
        let eligible = eligibleAffixes
        let ranked = eligible.filter { $0.popularity != nil }.sorted {
            ($0.popularity ?? 0) > ($1.popularity ?? 0)
        }
        if !ranked.isEmpty { return Array(ranked.prefix(18)) }
        return Array(eligible.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }.prefix(18))
    }

    var categories: [String] {
        Array(Set(positiveAffixes.map(\.category))).sorted {
            $0.localizedStandardCompare($1) == .orderedAscending
        }
    }

    var catalogSummary: String {
        let positive = positiveAffixes.count
        let curses = catalog.affixes.count - positive
        return "\(positive) 条正面词条 · \(curses) 条负面词条"
    }

    func affix(at slot: Int) -> Affix? {
        guard selectedIDs.indices.contains(slot), let id = selectedIDs[slot] else { return nil }
        return byID[id]
    }

    func select(_ affix: Affix, for slot: Int) {
        guard selectedIDs.indices.contains(slot) else { return }
        selectedIDs[slot] = affix.effectID
        result = nil
    }

    func fillNext(with affix: Affix) {
        guard !selectedIDs.contains(affix.effectID) else { return }
        if let index = selectedIDs.firstIndex(where: { $0 == nil }) {
            select(affix, for: index)
        } else {
            select(affix, for: 2)
        }
    }

    func remove(slot: Int) {
        guard selectedIDs.indices.contains(slot) else { return }
        selectedIDs[slot] = nil
        result = nil
    }

    func clearSelection() {
        selectedIDs = [nil, nil, nil]
        result = nil
    }

    func checkSelection() {
        result = checker.check(selectedAffixes, mode: mode)
    }

    func applyCanonicalOrder() {
        let ordered = checker.canonicalOrder(selectedAffixes)
        guard ordered.count == 3 else { return }
        selectedIDs = ordered.map(\.effectID)
        result = checker.check(ordered, mode: mode)
    }

    func randomize() {
        guard let combination = checker.randomCombination(from: positiveAffixes, mode: mode) else {
            result = CheckResult(status: .invalid, message: "当前词条库无法生成合法组合")
            return
        }
        selectedIDs = combination.map(\.effectID)
        result = checker.check(combination, mode: mode)
    }

    func importCatalog(from url: URL) {
        do {
            let imported = try CatalogLoader.load(from: url)
            guard let destination = Self.customCatalogURL else { throw CatalogError.unreadable }
            try FileManager.default.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try CatalogLoader.encode(imported)
            try data.write(to: destination, options: .atomic)
            catalog = imported
            catalogOrigin = "自定义数据"
            dataMessage = "已载入 \(imported.affixes.count) 条词条"
            clearSelection()
        } catch {
            dataMessage = "导入失败：\(error.localizedDescription)"
        }
    }

    func resetCatalog() {
        do {
            if let customURL = Self.customCatalogURL,
               FileManager.default.fileExists(atPath: customURL.path) {
                try FileManager.default.removeItem(at: customURL)
            }
            catalog = try CatalogLoader.load(from: Self.bundledCatalogURL())
            catalogOrigin = "内置数据"
            dataMessage = "已恢复内置词条库"
            clearSelection()
        } catch {
            dataMessage = "恢复失败：\(error.localizedDescription)"
        }
    }

    func exportCatalog(to url: URL) {
        do {
            try CatalogLoader.encode(catalog).write(to: url, options: .atomic)
            dataMessage = "已导出：\(url.lastPathComponent)"
        } catch {
            dataMessage = "导出失败：\(error.localizedDescription)"
        }
    }

    func importSave(from url: URL) {
        do {
            let report = try auditedSave(from: url)
            saveReport = report
            saveSelectedSlot = report.characters.first?.slot
            saveFilter = .all
            saveQuery = ""
            saveMessage = ""
        } catch {
            saveReport = nil
            saveSelectedSlot = nil
            // 遗物数据缺失本身就是完整的说明，不再套「解析失败」的壳。
            saveMessage = error is SaveLoadError
                ? error.localizedDescription
                : "解析失败：\(error.localizedDescription)"
        }
    }

    /// 解析并审计一份存档（载入与「对比另一份存档」共用同一套口径）。
    func auditedSave(from url: URL) throws -> AuditedSave {
        guard let relicData else {
            throw SaveLoadError.relicDataUnavailable(relicDataError)
        }
        let data = try Data(contentsOf: url)
        let parsed = try SaveFileParser.parse(data: data, fileName: url.lastPathComponent)
        return SaveAuditPipeline.audit(parsed, catalog: catalog, relicData: relicData)
    }

    static func bundledCatalogURL() throws -> URL {
        if let url = Bundle.main.url(forResource: "affixes", withExtension: "json") { return url }
        if let url = Bundle.module.url(forResource: "affixes", withExtension: "json") { return url }
        throw CatalogError.unreadable
    }

    static func bundledRelicDataURL() throws -> URL {
        if let url = Bundle.main.url(forResource: "relics", withExtension: "json") { return url }
        if let url = Bundle.module.url(forResource: "relics", withExtension: "json") { return url }
        throw RelicDataError.unreadable
    }

    private static var customCatalogURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("NightreignRelicChecker", isDirectory: true)
            .appendingPathComponent("affixes.json")
    }
}

/// 存档页使用的报告类型；模型与装配流程都在 RelicCore（`SaveAudit.swift`），
/// 报告导出与存档对比共用同一份结构。
typealias SaveScanReport = AuditedSave

enum SaveLoadError: LocalizedError {
    case relicDataUnavailable(String?)

    var errorDescription: String? {
        switch self {
        case .relicDataUnavailable(let detail):
            return "遗物数据不可用：" + (detail ?? "未找到 relics.json")
        }
    }
}
