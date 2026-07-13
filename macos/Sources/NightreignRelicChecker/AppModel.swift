import AppKit
import Foundation
import SwiftUI
import RelicCore

@MainActor
final class AppModel: ObservableObject {
    enum Page: String, CaseIterable, Identifiable {
        case checker
        case library
        case data

        var id: String { rawValue }

        var title: String {
            switch self {
            case .checker: return "词条检查"
            case .library: return "词条库"
            case .data: return "数据设置"
            }
        }

        var symbol: String {
            switch self {
            case .checker: return "checkmark.seal"
            case .library: return "list.bullet.rectangle"
            case .data: return "externaldrive"
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

    let checker = LegalityChecker()

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

    static func bundledCatalogURL() throws -> URL {
        if let url = Bundle.main.url(forResource: "affixes", withExtension: "json") { return url }
        if let url = Bundle.module.url(forResource: "affixes", withExtension: "json") { return url }
        throw CatalogError.unreadable
    }

    private static var customCatalogURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("NightreignRelicChecker", isDirectory: true)
            .appendingPathComponent("affixes.json")
    }
}
