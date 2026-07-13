import SwiftUI
import RelicCore

struct AffixLibraryView: View {
    @EnvironmentObject private var model: AppModel
    @State private var query = ""
    @State private var category = "全部"
    @State private var onlyEligible = true

    private var filtered: [Affix] {
        let needle = query.foldedForSearch
        return model.positiveAffixes
            .filter { !onlyEligible || $0.isEligible(for: model.mode) }
            .filter { category == "全部" || $0.category == category }
            .filter { needle.isEmpty || $0.searchableText.contains(needle) }
            .sorted {
                if $0.sortID != $1.sortID { return $0.sortID < $1.sortID }
                return $0.effectID < $1.effectID
            }
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 14) {
                HStack(alignment: .center, spacing: 14) {
                    LogoMark(size: 40)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("词条库")
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                        Text("查看官方简中名称、说明、互斥池与真实保存排序键")
                            .font(.caption)
                            .foregroundStyle(AppTheme.secondaryText)
                    }
                    Spacer()
                    Pill(text: model.catalogSummary, color: AppTheme.green, symbol: "checkmark.circle")
                }

                HStack(spacing: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(AppTheme.secondaryText)
                        TextField("搜索名称、别名、分类或 effectId", text: $query)
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
                    .frame(width: 180)

                    Picker("口径", selection: $model.mode) {
                        ForEach(CheckMode.allCases) { Text($0.title).tag($0) }
                    }
                    .frame(width: 150)

                    Toggle("仅当前口径", isOn: $onlyEligible)
                        .toggleStyle(.switch)
                        .font(.caption)
                }
            }
            .padding(.horizontal, 26)
            .padding(.vertical, 22)
            .background(AppTheme.elevated.opacity(0.55))

            Divider().overlay(AppTheme.border)

            HStack(spacing: 0) {
                Text("排序 / ID").frame(width: 150, alignment: .leading)
                Text("词条").frame(maxWidth: .infinity, alignment: .leading)
                Text("分类").frame(width: 145, alignment: .leading)
                Text("互斥池").frame(width: 90, alignment: .trailing)
                Text("可用模式").frame(width: 210, alignment: .trailing)
            }
            .font(.caption.weight(.bold))
            .foregroundStyle(AppTheme.secondaryText)
            .padding(.horizontal, 30)
            .padding(.vertical, 11)
            .background(AppTheme.elevated)

            if filtered.isEmpty {
                EmptyStateView(title: "没有匹配词条", symbol: "books.vertical", detail: "请调整搜索或筛选条件")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filtered) { affix in
                            LibraryRow(affix: affix)
                            Divider().overlay(AppTheme.border).padding(.horizontal, 26)
                        }
                    }
                }
            }

            HStack {
                Text("当前显示 \(filtered.count) 条")
                Spacer()
                Text("顺序键：overrideEffectId → effectId（升序）")
            }
            .font(.caption)
            .foregroundStyle(AppTheme.secondaryText)
            .padding(.horizontal, 28)
            .frame(height: 38)
            .background(AppTheme.elevated)
            .overlay(alignment: .top) { Rectangle().fill(AppTheme.border).frame(height: 1) }
        }
    }
}

private struct LibraryRow: View {
    let affix: Affix

    private var modes: [String] {
        CheckMode.allCases.filter { $0 != .compatibilityOnly && affix.isEligible(for: $0) }.map(\.shortTitle)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text(String(affix.sortID))
                    .font(.caption.monospaced().weight(.semibold))
                    .foregroundStyle(AppTheme.purpleSoft)
                Text(String(affix.effectID))
                    .font(.caption2.monospaced())
                    .foregroundStyle(AppTheme.tertiaryText)
            }
            .frame(width: 150, alignment: .leading)

            VStack(alignment: .leading, spacing: 5) {
                Text(affix.name)
                    .font(.system(size: 13, weight: .semibold))
                if !affix.explanation.isEmpty {
                    Text(affix.explanation)
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(affix.category)
                .font(.caption)
                .foregroundStyle(AppTheme.secondaryText)
                .frame(width: 145, alignment: .leading)

            Text(String(affix.compatibilityID))
                .font(.caption.monospaced())
                .frame(width: 90, alignment: .trailing)

            HStack(spacing: 5) {
                ForEach(modes, id: \.self) { Pill(text: $0, color: AppTheme.green) }
                if affix.requiresCurse { Pill(text: "需诅咒", color: AppTheme.amber) }
            }
            .frame(width: 210, alignment: .trailing)
        }
        .padding(.horizontal, 30)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}
