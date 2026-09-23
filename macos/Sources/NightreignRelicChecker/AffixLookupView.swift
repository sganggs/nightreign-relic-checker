import SwiftUI
import RelicCore

/// 词条反查页。
///
/// 由「词条反查」功能开发者独占：只改本文件（以及 AffixLookupDetail.swift、
/// RelicCore/AffixLookup.swift、RelicCoreChecks/AffixLookupChecks.swift）；
/// **不需要改 AppModel / RootView**，页面状态全部放在本视图内。
///
/// 数据：只读 `model.catalog`（词条库）与 `model.relicData`（遗物物品表，可能为
/// nil）。反向索引由 `RelicCore` 的纯函数一次性构建，缓存在 `@State` 里。
struct AffixLookupView: View {
    /// 只读地访问已载入的词条库 / 遗物物品表；请不要往 AppModel 上加本页状态。
    @EnvironmentObject private var model: AppModel

    enum Tab: String, CaseIterable, Identifiable {
        case byAffix
        case byRelic

        var id: String { rawValue }

        var title: String {
            switch self {
            case .byAffix: return "按词条查"
            case .byRelic: return "按遗物查"
            }
        }
    }

    enum AffixScope: String, CaseIterable, Identifiable {
        case all
        case catalog
        case extras

        var id: String { rawValue }

        var title: String {
            switch self {
            case .all: return "全部"
            case .catalog: return "词条库"
            case .extras: return "物品表补充"
            }
        }
    }

    /// 结果列表一次最多渲染多少行，超出由详情面板的「展开全部」就地展开。
    static let rowLimit = affixLookupRowLimit
    /// 互斥组最多展示多少条（最大的互斥组有 102 条，全铺会把页面挤没）。
    static let conflictLimit = affixLookupConflictLimit

    // 页面外壳与「首领数据」「角色属性」「增伤排名」等页同一套尺寸：
    // 横向留 26pt，内容最宽 1180pt，窗口更宽时整体居中。
    static let shellMaxWidth: CGFloat = 1180
    static let shellPadding: CGFloat = 26
    /// 左侧列表栏的宽度；右侧详情栏占满剩下的宽度。
    static let listWidth: CGFloat = 330

    @State private var index: AffixLookupIndex?
    @State private var tab: Tab = .byAffix
    @State private var affixQuery = ""
    @State private var relicQuery = ""
    @State private var affixScope: AffixScope = .catalog
    @State private var includeCurses = true
    @State private var onlyDeepRelics = false
    @State private var selectedAffixID: Int?
    @State private var selectedRelicID: Int?
    /// 只有「从详情页跨方向跳过来」时才自动滚动；用户自己点侧栏的行不滚，
    /// 否则鼠标下的内容会整片位移。
    @State private var pendingScrollAffixID: Int?
    @State private var pendingScrollRelicID: Int?

    /// 词条库 / 物品表换了就重建索引（用户可以在「数据设置」里导入自定义词条库）。
    private var signature: String {
        let relicPart = model.relicData.map { "\($0.dataVersion)#\($0.relics.count)" } ?? "none"
        return "\(model.catalog.dataVersion)#\(model.catalog.affixes.count)#\(relicPart)"
    }

    /// 整页不滚动：页头固定，下面的「列表 / 详情」双栏面板占满剩余高度，两栏各自滚动，
    /// 不会出现页面滚动条和栏内滚动条叠在一起的情况。
    var body: some View {
        VStack(spacing: 0) {
            headerBar
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .lookupPanel()
                .padding(.horizontal, Self.shellPadding)
                .padding(.top, 18)
                .padding(.bottom, 22)
                .frame(maxWidth: Self.shellMaxWidth, maxHeight: .infinity)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .task(id: signature) { await rebuildIndex() }
    }

    // MARK: - 顶部

    /// 页头的底色条与其它工具页一样横贯窗口，里面的内容与下方面板同宽、同一条左右边线。
    private var headerBar: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 14) {
                LogoMark(size: 40)
                VStack(alignment: .leading, spacing: 4) {
                    Text("词条反查")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                    Text("由词条反查可能出现它的遗物与出货池，也可以反过来按遗物看槽位池")
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                statusPills
            }

            Picker("查询方向", selection: $tab) {
                ForEach(Tab.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 280, alignment: .leading)
        }
        .padding(.horizontal, Self.shellPadding)
        .padding(.vertical, 20)
        .frame(maxWidth: Self.shellMaxWidth, alignment: .leading)
        .frame(maxWidth: .infinity)
        .background(AppTheme.elevated.opacity(0.55))
        .overlay(alignment: .bottom) { Rectangle().fill(AppTheme.border).frame(height: 1) }
    }

    private var statusPills: some View {
        HStack(spacing: 8) {
            Pill(
                text: "词条库 \(model.catalog.affixes.count) 条",
                color: model.catalog.affixes.isEmpty ? AppTheme.amber : AppTheme.green,
                symbol: "checkmark.circle"
            )
            if let index, index.hasRelicData {
                Pill(
                    text: "可查遗物 \(index.searchRelics("").count) 件",
                    color: AppTheme.green,
                    symbol: "shippingbox"
                )
            } else {
                Pill(text: "遗物物品表未内置", color: AppTheme.amber, symbol: "exclamationmark.triangle")
            }
        }
    }

    // MARK: - 主体

    @ViewBuilder
    private var content: some View {
        if let index {
            if index.affixes.isEmpty {
                // 词条库本身没载进来：把真实原因说出来，别让用户以为是搜索没命中
                EmptyStateView(
                    title: "词条库不可用",
                    symbol: "exclamationmark.triangle",
                    detail: model.loadError.map { "词条库载入失败：\($0)\n请到「数据设置」恢复内置词条库。" }
                        ?? "当前词条库里没有任何词条，请到「数据设置」恢复内置词条库。"
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack(spacing: 0) {
                    listPane(index)
                        .frame(width: Self.listWidth)
                        .frame(maxHeight: .infinity)
                    Rectangle()
                        .fill(AppTheme.border)
                        .frame(width: 1)
                    detailPane(index)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        } else {
            EmptyStateView(
                title: "正在建立反查索引…",
                symbol: "hourglass",
                detail: "首次进入本页时会把词条库与遗物物品表翻转成反向索引，只需一次。"
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// 遗物物品表缺失 / 解析失败时的原因说明（解析失败时只说「没有 relics.json」会误导）。
    /// 末尾带句号，方便与各处的后半句直接拼接。
    private var relicDataDetail: String {
        guard let error = model.relicDataError else { return "没有内置 relics.json。" }
        let trimmed = error.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = trimmed.hasSuffix("。") || trimmed.hasSuffix(".") ? String(trimmed.dropLast()) : trimmed
        return "遗物物品表载入失败：" + body + "。"
    }

    @ViewBuilder
    private func listPane(_ index: AffixLookupIndex) -> some View {
        switch tab {
        case .byAffix: affixListPane(index)
        case .byRelic: relicListPane(index)
        }
    }

    @ViewBuilder
    private func detailPane(_ index: AffixLookupIndex) -> some View {
        switch tab {
        case .byAffix:
            AffixLookupDetailPane(
                index: index,
                effectID: selectedAffixID,
                rowLimit: Self.rowLimit,
                conflictLimit: Self.conflictLimit,
                catalogSources: model.catalog.sources,
                relicSources: model.relicData?.sources ?? [],
                relicDataDetail: relicDataDetail,
                onPickAffix: { effectID in
                    reveal(effectID: effectID, in: index)
                },
                onPickRelic: { relicID in
                    reveal(relicID: relicID, in: index)
                }
            )
        case .byRelic:
            RelicLookupDetailPane(
                index: index,
                relicID: selectedRelicID,
                catalogSources: model.catalog.sources,
                relicSources: model.relicData?.sources ?? [],
                relicDataDetail: relicDataDetail,
                onPickAffix: { effectID in
                    reveal(effectID: effectID, in: index)
                    tab = .byAffix
                }
            )
        }
    }

    // MARK: - 词条列表

    private func filteredAffixes(_ index: AffixLookupIndex) -> [LookupAffix] {
        index.searchAffixes(
            affixQuery,
            includeCurses: includeCurses,
            catalogOnly: affixScope == .catalog
        )
        .filter { affixScope != .extras || !$0.inCatalog }
    }

    private func affixListPane(_ index: AffixLookupIndex) -> some View {
        let rows = filteredAffixes(index)
        return VStack(spacing: 0) {
            VStack(spacing: 10) {
                LookupSearchField(text: $affixQuery, placeholder: "搜索词条名、别名、分类或 effectId")
                Picker("范围", selection: $affixScope) {
                    ForEach(AffixScope.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                Toggle("含负面词条", isOn: $includeCurses)
                    .toggleStyle(.switch)
                    .font(.caption)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)

            Divider().overlay(AppTheme.border)

            if rows.isEmpty {
                EmptyStateView(title: "没有匹配词条", symbol: "magnifyingglass", detail: "换个关键词或放宽范围试试")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(rows) { affix in
                                LookupSelectableRow(isSelected: selectedAffixID == affix.effectID) {
                                    selectedAffixID = affix.effectID
                                } content: {
                                    AffixLookupListRow(affix: affix)
                                }
                                .id(affix.effectID)
                                Divider().overlay(AppTheme.border).padding(.leading, 14)
                            }
                        }
                    }
                    .task(id: pendingScrollAffixID) {
                        guard let target = pendingScrollAffixID else { return }
                        proxy.scrollTo(target, anchor: .center)
                        pendingScrollAffixID = nil
                    }
                }
            }

            listFooter(text: "\(rows.count) 条词条")
        }
        .background(AppTheme.elevated)
    }

    // MARK: - 遗物列表

    private func filteredRelics(_ index: AffixLookupIndex) -> [RelicLookupEntry] {
        index.searchRelics(relicQuery, onlyDeep: onlyDeepRelics)
    }

    @ViewBuilder
    private func relicListPane(_ index: AffixLookupIndex) -> some View {
        if !index.hasRelicData {
            VStack(spacing: 0) {
                EmptyStateView(
                    title: "遗物物品表未内置",
                    symbol: "shippingbox",
                    detail: relicDataDetail + "无法按遗物反查；「按词条查」仍可看词条说明与互斥组。"
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(AppTheme.elevated)
        } else {
            let rows = filteredRelics(index)
            VStack(spacing: 0) {
                VStack(spacing: 10) {
                    LookupSearchField(text: $relicQuery, placeholder: "搜索遗物名、种类或 ID")
                    Toggle("只看深夜遗物", isOn: $onlyDeepRelics)
                        .toggleStyle(.switch)
                        .font(.caption)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 13)

                Divider().overlay(AppTheme.border)

                if rows.isEmpty {
                    EmptyStateView(title: "没有匹配遗物", symbol: "magnifyingglass", detail: "换个关键词试试")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 0) {
                                ForEach(rows) { entry in
                                    LookupSelectableRow(isSelected: selectedRelicID == entry.id) {
                                        selectedRelicID = entry.id
                                    } content: {
                                        RelicLookupListRow(entry: entry)
                                    }
                                    .id(entry.id)
                                    Divider().overlay(AppTheme.border).padding(.leading, 14)
                                }
                            }
                        }
                        .task(id: pendingScrollRelicID) {
                            guard let target = pendingScrollRelicID else { return }
                            proxy.scrollTo(target, anchor: .center)
                            pendingScrollRelicID = nil
                        }
                    }
                }

                listFooter(text: "\(rows.count) 件遗物")
            }
            .background(AppTheme.elevated)
        }
    }

    private func listFooter(text: String) -> some View {
        HStack {
            Text(text)
            Spacer(minLength: 0)
        }
        .font(.caption)
        .foregroundStyle(AppTheme.secondaryText)
        .padding(.horizontal, 14)
        .frame(height: 32)
        .background(AppTheme.card)
        .overlay(alignment: .top) { Rectangle().fill(AppTheme.border).frame(height: 1) }
    }

    // MARK: - 选中与索引

    /// 跳到某条词条：先放开筛选保证它在列表里，再选中它。
    ///
    /// 搜索词只在「目标本来就搜不出来」时才清空 —— 用户从互斥组 / 诅咒池 / 槽位池
    /// 标签点过来时，多半还想留着原来的搜索词继续看，不该被无条件冲掉。
    private func reveal(effectID: Int, in index: AffixLookupIndex) {
        if let affix = index.affix(effectID) {
            if affix.isCurse { includeCurses = true }
            if affixScope == .catalog && !affix.inCatalog { affixScope = .all }
            if affixScope == .extras && affix.inCatalog { affixScope = .all }
            let needle = affixQuery.foldedForSearch
            if !needle.isEmpty && !affix.searchText.contains(needle) { affixQuery = "" }
        } else {
            affixQuery = ""
        }
        selectedAffixID = effectID
        pendingScrollAffixID = effectID
    }

    /// 跳到某件遗物；与 `reveal(effectID:in:)` 同样只在必要时才动搜索词与筛选。
    private func reveal(relicID: Int, in index: AffixLookupIndex) {
        if let entry = index.relic(relicID) {
            if onlyDeepRelics && !entry.deep { onlyDeepRelics = false }
            let needle = relicQuery.foldedForSearch
            if !needle.isEmpty && !entry.searchText.contains(needle) { relicQuery = "" }
        } else {
            relicQuery = ""
            onlyDeepRelics = false
        }
        selectedRelicID = relicID
        pendingScrollRelicID = relicID
        tab = .byRelic
    }

    private func rebuildIndex() async {
        let catalog = model.catalog
        let relicData = model.relicData
        let built = await Task.detached(priority: .userInitiated) {
            AffixLookupIndex(catalog: catalog, relicData: relicData)
        }.value

        // 先定好选中项再挂上索引：侧栏列表是在 index 非空之后才建出来的，
        // 这样不会在列表正在布局时改动选中项。
        if selectedAffixID == nil || built.affix(selectedAffixID ?? -1) == nil {
            selectedAffixID = built.affixes.first(where: { $0.inCatalog })?.effectID
                ?? built.affixes.first?.effectID
        }
        if selectedRelicID == nil || built.relic(selectedRelicID ?? -1) == nil {
            selectedRelicID = built.relics.first(where: { $0.isObtainable && $0.isUnique })?.id
                ?? built.relics.first(where: \.isObtainable)?.id
        }
        index = built
    }
}

// MARK: - 列表行与小组件

/// 双栏面板的外框：与 `.appCard()` 同一套圆角、描边，但不加内边距——两栏的底色与
/// 分隔线要贴到边框，所以先按圆角裁切再描边（描边画在内容之上，不会被栏底色盖住）。
private struct LookupPanelModifier: ViewModifier {
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        content
            // 详情栏的底色：比卡片暗一档，详情里的各张 `.appCard()` 能浮出来
            .background(AppTheme.elevated.opacity(0.5))
            .clipShape(shape)
            .overlay(shape.stroke(AppTheme.border, lineWidth: 1))
    }
}

private extension View {
    func lookupPanel() -> some View { modifier(LookupPanelModifier()) }
}

struct LookupSearchField: View {
    @Binding var text: String
    let placeholder: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(AppTheme.secondaryText)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(AppTheme.tertiaryText)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 32)
        .background(AppTheme.field, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppTheme.border, lineWidth: 1))
    }
}

/// 侧栏里的一行：整行可点，选中态用紫色底。
struct LookupSelectableRow<Content: View>: View {
    let isSelected: Bool
    let action: () -> Void
    @ViewBuilder let content: Content

    var body: some View {
        Button(action: action) {
            HStack(spacing: 0) {
                content
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(isSelected ? AppTheme.purple.opacity(0.28) : Color.clear)
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(isSelected ? AppTheme.purpleSoft : Color.clear)
                    .frame(width: 3)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct AffixLookupListRow: View {
    let affix: LookupAffix

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(affix.displayName)
                .font(.system(size: 12.5, weight: .semibold))
                .lineLimit(2)
            HStack(spacing: 5) {
                Text(String(affix.effectID))
                    .font(.caption2.monospaced())
                    .foregroundStyle(AppTheme.tertiaryText)
                if affix.isCurse {
                    Text("负面").font(.caption2).foregroundStyle(AppTheme.red)
                } else if affix.requiresCurse {
                    Text("需诅咒").font(.caption2).foregroundStyle(AppTheme.amber)
                }
                if !affix.inCatalog {
                    Text("物品表").font(.caption2).foregroundStyle(AppTheme.tertiaryText)
                }
            }
        }
    }
}

struct RelicLookupListRow: View {
    let entry: RelicLookupEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(entry.displayName)
                .font(.system(size: 12.5, weight: .semibold))
                .lineLimit(2)
            HStack(spacing: 5) {
                Text(String(entry.id))
                    .font(.caption2.monospaced())
                    .foregroundStyle(AppTheme.tertiaryText)
                Text(entry.kindLabel)
                    .font(.caption2)
                    .foregroundStyle(entry.deep ? AppTheme.purpleSoft : AppTheme.secondaryText)
                Text(verbatim: "\(entry.slotCount) 孔")
                    .font(.caption2)
                    .foregroundStyle(AppTheme.tertiaryText)
            }
        }
    }
}
