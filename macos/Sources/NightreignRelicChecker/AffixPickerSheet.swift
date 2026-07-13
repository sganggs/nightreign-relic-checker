import SwiftUI
import RelicCore

struct AffixPickerSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    let slot: Int

    @State private var query = ""
    @State private var category = "全部"
    @State private var showUnavailable = false

    private var filtered: [Affix] {
        let needle = query.foldedForSearch
        return model.positiveAffixes
            .filter { showUnavailable || $0.isEligible(for: model.mode) }
            .filter { category == "全部" || $0.category == category }
            .filter { needle.isEmpty || $0.searchableText.contains(needle) }
            .sorted { lhs, rhs in
                let lhsEligible = lhs.isEligible(for: model.mode)
                let rhsEligible = rhs.isEligible(for: model.mode)
                if lhsEligible != rhsEligible { return lhsEligible }
                if lhs.sortID != rhs.sortID { return lhs.sortID < rhs.sortID }
                return lhs.effectID < rhs.effectID
            }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                LogoMark(size: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text("选择词条 \(slot + 1)")
                        .font(.title3.weight(.bold))
                    Text("当前口径：\(model.mode.title)")
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                }
                Spacer()
                Button("完成") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(18)
            .background(AppTheme.elevated)

            VStack(spacing: 12) {
                HStack(spacing: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(AppTheme.secondaryText)
                        TextField("搜索词条名称、分类或 ID", text: $query)
                            .textFieldStyle(.plain)
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 38)
                    .background(AppTheme.field, in: RoundedRectangle(cornerRadius: 9))
                    .overlay(RoundedRectangle(cornerRadius: 9).stroke(AppTheme.border, lineWidth: 1))

                    Picker("分类", selection: $category) {
                        Text("全部分类").tag("全部")
                        ForEach(model.categories, id: \.self) { Text($0).tag($0) }
                    }
                    .frame(width: 170)
                }

                HStack {
                    Toggle("显示当前口径不可用的词条", isOn: $showUnavailable)
                        .toggleStyle(.switch)
                        .font(.caption)
                    Spacer()
                    Text("\(filtered.count) 条")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(AppTheme.secondaryText)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)

            Divider().overlay(AppTheme.border)

            if filtered.isEmpty {
                EmptyStateView(title: "没有匹配词条", symbol: "magnifyingglass", detail: "请更换关键词或分类")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(filtered) { affix in
                    AffixPickerRow(affix: affix, eligible: affix.isEligible(for: model.mode))
                        .contentShape(Rectangle())
                        .onTapGesture {
                            model.select(affix, for: slot)
                            dismiss()
                        }
                        .listRowBackground(AppTheme.background)
                        .listRowSeparatorTint(AppTheme.border)
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
            }
        }
        .frame(minWidth: 720, idealWidth: 820, minHeight: 610, idealHeight: 720)
        .background(AppTheme.background)
    }
}

private struct AffixPickerRow: View {
    let affix: Affix
    let eligible: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 4) {
                Text(String(affix.effectID))
                    .font(.caption2.monospaced())
                    .foregroundStyle(AppTheme.purpleSoft)
                Text(String(affix.sortID))
                    .font(.caption2.monospaced())
                    .foregroundStyle(AppTheme.tertiaryText)
            }
            .frame(width: 70)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 7) {
                    Text(affix.name)
                        .font(.system(size: 13, weight: .semibold))
                    Pill(text: affix.category, color: AppTheme.purpleSoft)
                    if affix.requiresCurse {
                        Pill(text: "需诅咒", color: AppTheme.amber)
                    }
                }
                if !affix.explanation.isEmpty {
                    Text(affix.explanation)
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                        .lineLimit(2)
                }
                Text("互斥池 " + String(affix.compatibilityID) + " · " + affix.superposability)
                    .font(.caption2)
                    .foregroundStyle(AppTheme.tertiaryText)
            }

            Spacer(minLength: 12)

            Image(systemName: eligible ? "plus.circle.fill" : "nosign")
                .font(.title3)
                .foregroundStyle(eligible ? AppTheme.purpleSoft : AppTheme.red.opacity(0.8))
                .padding(.top, 4)
        }
        .padding(.vertical, 6)
        .opacity(eligible ? 1 : 0.58)
    }
}
