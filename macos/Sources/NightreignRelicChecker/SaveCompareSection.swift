import SwiftUI
import RelicCore

/// 存档对比结果面板（对比逻辑在 RelicCore/SaveCompare.swift，这里只负责展示）。
///
/// 口径：以当前载入的存档为准，另一份存档多出的遗物记为「新增」，
/// 少掉的记为「减少」；身份 = 遗物 ID + 三条正面词条 + 三条诅咒（都按存档顺序）。
/// 文案与 Windows 端 app.js 的对比卡一致。
struct SaveCompareSection: View {
    let result: SaveCompareResult
    let report: SaveScanReport
    let onClose: () -> Void

    @State private var query = ""
    /// 差异方向筛选（与 Windows 端的「全部 / 只看新增 / 只看减少」同一组控件）。
    @State private var direction: Direction = .all

    /// 差异方向。没有差异的槽位两端都不展示，所以不再单独给「只看有差异」开关。
    enum Direction: String, CaseIterable, Identifiable {
        case all
        case added
        case removed

        var id: String { rawValue }

        var title: String {
            switch self {
            case .all: return "全部"
            case .added: return "只看新增"
            case .removed: return "只看减少"
            }
        }
    }

    /// 一个槽位 + 它在当前搜索条件下的增减条目。
    ///
    /// 过滤结果随块一起带下去，`body` 里只算一次：`visibleCharacters` 曾是
    /// computed property，每次 body 求值都要把全部条目折叠比对好几遍。
    private struct CharacterBlock: Identifiable {
        let character: SaveCompareCharacter
        let added: [SaveCompareEntry]
        let removed: [SaveCompareEntry]

        var id: Int { character.slot }
    }

    var body: some View {
        let blocks = visibleBlocks()
        return VStack(alignment: .leading, spacing: 15) {
            HStack(alignment: .top, spacing: 12) {
                SectionHeading(
                    title: "存档对比",
                    subtitle: "当前：\(result.baseFileName)　对比：\(result.otherFileName)",
                    symbol: "arrow.left.arrow.right"
                )
                Button("关闭对比", action: onClose)
                    .buttonStyle(SecondaryButtonStyle())
            }

            HStack(spacing: 8) {
                Pill(text: "当前共 \(result.totalBase) 件", color: AppTheme.purpleSoft, symbol: "shippingbox")
                Pill(text: "对比共 \(result.totalOther) 件", color: AppTheme.purpleSoft, symbol: "shippingbox")
                Pill(text: "新增 \(result.totalAdded) 件", color: AppTheme.green, symbol: "plus.circle")
                Pill(text: "减少 \(result.totalRemoved) 件", color: AppTheme.red, symbol: "minus.circle")
                Pill(text: "有差异角色 \(result.changedCharacters)", color: AppTheme.purpleSoft, symbol: "person.2")
                if result.hasUnreliableSlots {
                    Pill(
                        text: "无法对比槽位 \(result.unreliableCharacters.count)",
                        color: AppTheme.amber,
                        symbol: "exclamationmark.triangle"
                    )
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 10) {
                Picker("差异方向", selection: $direction) {
                    ForEach(Direction.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 260)
                Spacer(minLength: 0)
            }

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(AppTheme.secondaryText)
                TextField("在对比结果中搜索遗物名、词条名或 ID", text: $query)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(AppTheme.field, in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(AppTheme.border, lineWidth: 1))

            if !result.hasDifferences {
                Text("两份存档的遗物完全一致。")
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
            }

            if result.hasUnreliableSlots {
                Text("有槽位在某一侧解析失败，该槽位读不出遗物；只作提示，不计入上面的增减。")
                    .font(.caption)
                    .foregroundStyle(AppTheme.amber)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ForEach(blocks) { block in
                characterBlock(block)
            }

            if blocks.isEmpty {
                Text(result.hasDifferences ? "没有符合筛选条件的差异" : "两份存档的遗物完全一致")
                    .font(.caption)
                    .foregroundStyle(AppTheme.tertiaryText)
            }

            Text("对比以「遗物 ID + 三条正面词条 + 三条诅咒」为一件遗物的身份（都按存档里的顺序，"
                + "顺序本身会影响合法性判定），按角色槽位分别统计；任一边解析失败的槽位只提示、不计入增减。"
                + "新增/减少遗物的合法性状态由当前词条库判定，取自该遗物所在存档的整体检查结果。")
                .font(.caption2)
                .foregroundStyle(AppTheme.tertiaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .appCard()
    }

    /// 过滤一次算完：折叠后的搜索串只算一遍，不再让 body 反复求值。
    private func visibleBlocks() -> [CharacterBlock] {
        let needle = query.foldedForSearch
        var blocks: [CharacterBlock] = []
        for character in result.characters {
            // 没有任何差异的槽位不展示；改名与解析失败这两类提示要放行。
            guard character.hasAnyDifference else { continue }
            let added = direction == .removed ? [] : filtered(character.added, needle: needle)
            let removed = direction == .added ? [] : filtered(character.removed, needle: needle)
            // 搜索/方向把这个槽位的条目滤空了就不再展示；改名（isIdentical）与
            // 解析失败这两类只有提示、本来就没有条目的槽位要留下。
            if !character.hasParseError && !character.isIdentical && added.isEmpty && removed.isEmpty {
                continue
            }
            blocks.append(CharacterBlock(character: character, added: added, removed: removed))
        }
        return blocks
    }

    @ViewBuilder
    private func characterBlock(_ block: CharacterBlock) -> some View {
        let character = block.character
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 8) {
                Text(character.displayName)
                    .font(.subheadline.weight(.semibold))
                Pill(text: "当前 \(character.baseTotal)", color: AppTheme.purpleSoft, symbol: "shippingbox")
                Pill(text: "对比 \(character.otherTotal)", color: AppTheme.purpleSoft, symbol: "shippingbox")
                if character.hasParseError {
                    Pill(text: "无法对比", color: AppTheme.amber, symbol: "exclamationmark.triangle")
                } else {
                    Pill(
                        text: "新增 \(character.addedCount)",
                        color: character.addedCount > 0 ? AppTheme.green : AppTheme.secondaryText,
                        symbol: "plus"
                    )
                    Pill(
                        text: "减少 \(character.removedCount)",
                        color: character.removedCount > 0 ? AppTheme.red : AppTheme.secondaryText,
                        symbol: "minus"
                    )
                }
                Spacer(minLength: 0)
            }

            // 解析失败的槽位只提示：它的遗物读不出来，不是真实差异。
            if let note = character.parseNote {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(AppTheme.amber)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let note = character.presenceNote {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(AppTheme.amber)
            }

            if character.isIdentical {
                if !character.hasParseError && character.presenceNote == nil {
                    Text("该角色的遗物与当前存档一致。")
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                }
            } else {
                entryGroup(
                    title: "对比存档中新增",
                    color: AppTheme.green,
                    symbol: "plus.circle",
                    entries: block.added
                )
                entryGroup(
                    title: "对比存档中减少",
                    color: AppTheme.red,
                    symbol: "minus.circle",
                    entries: block.removed
                )
            }
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.field.opacity(0.55), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppTheme.border, lineWidth: 1))
    }

    @ViewBuilder
    private func entryGroup(title: String, color: Color, symbol: String, entries: [SaveCompareEntry]) -> some View {
        if !entries.isEmpty {
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 6) {
                    Image(systemName: symbol)
                        .font(.caption2)
                        .foregroundStyle(color)
                    Text("\(title)（\(entries.reduce(0) { $0 + $1.count })）")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(color)
                    Spacer(minLength: 0)
                }
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 320), spacing: 14, alignment: .top)],
                    alignment: .leading,
                    spacing: 14
                ) {
                    ForEach(entries) { entry in
                        SaveRelicCard(relic: entry.relic, report: report, quantity: entry.count)
                    }
                }
            }
        }
    }

    private func filtered(_ entries: [SaveCompareEntry], needle: String) -> [SaveCompareEntry] {
        guard !needle.isEmpty else { return entries }
        return entries.filter { searchText(for: $0).contains(needle) }
    }

    /// 与存档列表一致的搜索口径：遗物名、ID、种类、全部正负词条名与 ID。
    private func searchText(for entry: SaveCompareEntry) -> String {
        let relic = entry.relic
        var parts = [relic.displayName, String(relic.relic.itemID), relic.kindLabel]
        for effectID in relic.relic.effects + relic.relic.curses where effectID != -1 {
            parts.append(report.affixName(effectID))
            parts.append(String(effectID))
        }
        return parts.joined(separator: " ").foldedForSearch
    }
}
