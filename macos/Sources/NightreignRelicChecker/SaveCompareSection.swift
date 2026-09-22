import SwiftUI
import RelicCore

/// 存档对比结果面板（对比逻辑在 RelicCore/SaveCompare.swift，这里只负责展示）。
///
/// 口径：以当前载入的存档为基准，另一份存档多出的遗物记为「新增」，
/// 少掉的记为「减少」；身份 = 遗物 ID + 三行「正面词条 / 负面词条」配对。
struct SaveCompareSection: View {
    let result: SaveCompareResult
    let report: SaveScanReport
    let onClose: () -> Void

    @State private var query = ""
    /// 只看有差异的槽位（默认开，避免一次铺开十个槽位）。
    @State private var differencesOnly = true

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
                    subtitle: "基准：\(result.baseFileName)（当前载入）　对比：\(result.otherFileName)",
                    symbol: "arrow.left.arrow.right"
                )
                Button("关闭对比", action: onClose)
                    .buttonStyle(SecondaryButtonStyle())
            }

            HStack(spacing: 8) {
                Pill(text: "新增 \(result.totalAdded) 件", color: AppTheme.green, symbol: "plus.circle")
                Pill(text: "减少 \(result.totalRemoved) 件", color: AppTheme.red, symbol: "minus.circle")
                Pill(text: "角色槽位 \(result.characters.count)", color: AppTheme.purpleSoft, symbol: "person.2")
                if result.hasUnreliableSlots {
                    Pill(
                        text: "\(result.unreliableCharacters.count) 个槽位解析失败",
                        color: AppTheme.amber,
                        symbol: "exclamationmark.triangle"
                    )
                }
                Spacer(minLength: 0)
                Toggle("只看有差异的角色", isOn: $differencesOnly)
                    .toggleStyle(.checkbox)
                    .font(.caption)
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
                Text("两份存档的遗物完全一致（按遗物 ID 与三条正面 / 三条负面词条比较）。")
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
            }

            if result.hasUnreliableSlots {
                Text("有槽位在某一侧解析失败，该槽位读不出遗物；它的增减数字不可信，也没有计入上面的总数。")
                    .font(.caption)
                    .foregroundStyle(AppTheme.amber)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ForEach(blocks) { block in
                characterBlock(block)
            }

            if blocks.isEmpty {
                Text(query.isEmpty ? "没有需要显示的角色槽位。" : "没有匹配搜索条件的遗物。")
                    .font(.caption)
                    .foregroundStyle(AppTheme.tertiaryText)
            }

            Text("身份口径：遗物 ID 相同，且三行「正面词条 / 同行负面词条」完全相同即视为同一件；"
                + "行与行的先后顺序不计入差异。词条被改动过的遗物会同时出现在「减少」与「新增」里。")
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
            // 「只看有差异」也要放行改名与解析失败这两类提示。
            if differencesOnly && !character.hasAnyDifference { continue }
            let added = filtered(character.added, needle: needle)
            let removed = filtered(character.removed, needle: needle)
            if !needle.isEmpty && added.isEmpty && removed.isEmpty { continue }
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
                Pill(
                    text: "遗物 \(character.baseTotal) → \(character.otherTotal)",
                    color: AppTheme.purpleSoft,
                    symbol: "shippingbox"
                )
                if character.addedCount > 0 {
                    Pill(text: "新增 \(character.addedCount)", color: AppTheme.green, symbol: "plus")
                }
                if character.removedCount > 0 {
                    Pill(text: "减少 \(character.removedCount)", color: AppTheme.red, symbol: "minus")
                }
                if character.hasParseError {
                    Pill(text: "数字不可信", color: AppTheme.amber, symbol: "exclamationmark.triangle")
                }
                Spacer(minLength: 0)
            }

            // 解析失败优先于任何增减数字展示：那不是真实差异。
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
                if !character.hasParseError {
                    Text("该角色的遗物与基准存档一致。")
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                }
            } else {
                entryGroup(
                    title: "新增（对比存档多出）",
                    color: AppTheme.green,
                    symbol: "plus.circle",
                    entries: block.added
                )
                entryGroup(
                    title: "减少（对比存档中已不存在）",
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
                    Text("\(title) · \(entries.reduce(0) { $0 + $1.count }) 件")
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
