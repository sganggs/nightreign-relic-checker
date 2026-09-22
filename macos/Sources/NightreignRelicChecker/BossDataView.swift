import SwiftUI
import RelicCore

/// 首领数据页：夜王 / 守夜 / 野外首领的血量、韧性、承伤倍率与人数缩放。
///
/// 由「首领数据」功能开发者独占：只改本文件与 BossData*.swift、RelicCore 的
/// BossData.swift、RelicCoreChecks 的 BossDataChecks.swift；**不改 AppModel /
/// RootView**，页面状态全部放在本视图内。
///
/// 数据：`GameDataLoader.dataIfAvailable(for: .bosses)` → `Resources/bosses.json`
/// 的原始 JSON；未内置（文件缺失或仍是占位内容）时降级显示「数据未内置」。
/// 页面载入状态；解码放在后台任务里，因此需要 Sendable。
enum BossLoadState: Sendable {
    case loading
    case missing
    case failed(String)
    case ready(BossDataIndex)
}

struct BossDataView: View {
    private enum GroupFilter: String, CaseIterable, Identifiable {
        case all
        case nightlord
        case night
        case field

        var id: String { rawValue }

        var title: String {
            switch self {
            case .all: return "全部"
            case .nightlord: return BossCard.Group.nightlord.title
            case .night: return BossCard.Group.night.title
            case .field: return BossCard.Group.field.title
            }
        }

        var group: BossCard.Group? {
            switch self {
            case .all: return nil
            case .nightlord: return .nightlord
            case .night: return .night
            case .field: return .field
            }
        }
    }

    @State private var state: BossLoadState = .loading
    @State private var query = ""
    @State private var players: BossPartySize = .solo
    @State private var groupFilter: GroupFilter = .all
    @State private var deepOfNight = false
    @State private var expandedIDs: Set<String> = []
    @State private var showCaveats = false
    @State private var showScalingTiers = false

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider().overlay(AppTheme.border)
            content
            footer
        }
        .task { await load() }
    }

    // MARK: - 顶部

    private var toolbar: some View {
        VStack(spacing: 14) {
            HStack(alignment: .center, spacing: 14) {
                LogoMark(size: 40)
                VStack(alignment: .leading, spacing: 4) {
                    Text("首领数据")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                    Text("《黑夜君临》首领的血量、韧性、承伤倍率与多人缩放")
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                }
                Spacer()
                if case .ready(let index) = state {
                    Pill(text: index.summary, color: AppTheme.green, symbol: "checkmark.circle")
                }
            }

            HStack(spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(AppTheme.secondaryText)
                    TextField("搜索首领名、远征名、变体标签，或输入 npcId / chrId 前缀", text: $query)
                        .textFieldStyle(.plain)
                    if !query.isEmpty {
                        Button {
                            query = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(AppTheme.tertiaryText)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .frame(height: 38)
                .background(AppTheme.field, in: RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(AppTheme.border, lineWidth: 1))

                Picker("人数", selection: $players) {
                    ForEach(BossPartySize.allCases) { size in
                        Text(size.title).tag(size)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 168)

                Picker("分组", selection: $groupFilter) {
                    ForEach(GroupFilter.allCases) { filter in
                        Text(filter.title).tag(filter)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 124)

                Toggle("深夜", isOn: $deepOfNight)
                    .toggleStyle(.switch)
                    .font(.caption)
                    .help("按「深夜」模式显示：有深夜专属缩放的战斗行改用深夜数值")

                if !expandedIDs.isEmpty {
                    Button("收起全部") {
                        expandedIDs.removeAll()
                    }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(AppTheme.purpleSoft)
                }
            }
        }
        .padding(.horizontal, 26)
        .padding(.vertical, 22)
        .background(AppTheme.elevated.opacity(0.55))
    }

    // MARK: - 主体

    @ViewBuilder
    private var content: some View {
        switch state {
        case .loading:
            VStack(spacing: 12) {
                ProgressView()
                Text("正在载入首领数据…")
                    .font(.callout)
                    .foregroundStyle(AppTheme.secondaryText)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .missing:
            EmptyStateView(
                title: "数据未内置",
                symbol: "shield.lefthalf.filled",
                detail: "尚未提供 Resources/bosses.json，运行 scripts/sync-data.sh 同步后重新构建。"
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .failed(let message):
            EmptyStateView(
                title: "首领数据无法解析",
                symbol: "exclamationmark.triangle",
                detail: message
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .ready(let index):
            readyContent(index)
        }
    }

    @ViewBuilder
    private func readyContent(_ index: BossDataIndex) -> some View {
        let groups = visibleGroups(index)
        // 底部的 caveats / 缩放档位说明 / 数据版本与列表结果无关：
        // 搜索没命中时也必须留在页面上，不能让免责说明跟着结果一起消失。
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                if groups.allSatisfy({ $0.cards.isEmpty }) {
                    EmptyStateView(
                        title: "没有匹配的首领",
                        symbol: "magnifyingglass",
                        detail: "请调整搜索关键词或分组筛选。"
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 36)
                } else {
                    ForEach(groups, id: \.group) { section in
                        if !section.cards.isEmpty {
                            sectionHeader(section.group, count: section.cards.count)
                            ForEach(section.cards) { card in
                                BossCardView(
                                    card: card,
                                    group: section.group,
                                    index: index,
                                    players: players,
                                    deepOfNight: deepOfNight,
                                    isExpanded: expandedIDs.contains(card.id),
                                    onToggle: { toggle(card.id) }
                                )
                            }
                        }
                    }
                }
                bottomNotes(index)
                    .padding(.top, 8)
            }
            .padding(.horizontal, 26)
            .padding(.vertical, 18)
            .frame(maxWidth: 1180)
            .frame(maxWidth: .infinity)
        }
    }

    private func sectionHeader(_ group: BossCard.Group, count: Int) -> some View {
        HStack(spacing: 8) {
            Image(systemName: group.symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppTheme.purpleSoft)
            Text(group.title)
                .font(.system(size: 15, weight: .bold))
            Text("\(count)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.tertiaryText)
            Spacer(minLength: 0)
        }
        .padding(.top, 10)
        .padding(.bottom, 2)
    }

    // MARK: - 底部说明

    private func bottomNotes(_ index: BossDataIndex) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeading(
                title: "数据说明",
                subtitle: "数值直接取自游戏参数表，不是官方公布，也不是实测手感",
                symbol: "info.circle"
            )

            disclosure(
                title: "数据说明与已知取舍（\(index.dataset.caveats.count) 条）",
                isOn: $showCaveats
            ) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("本页数值直接读取游戏参数表，不是官方公布数据，也不是实测结论；标注与实际手感可能有出入。")
                        .font(.system(size: 11))
                        .foregroundStyle(AppTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    ForEach(Array(index.dataset.caveats.enumerated()), id: \.offset) { item in
                        HStack(alignment: .top, spacing: 7) {
                            Text("·")
                                .foregroundStyle(AppTheme.tertiaryText)
                            Text(item.element)
                                .font(.system(size: 11))
                                .foregroundStyle(AppTheme.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }

            disclosure(
                title: "人数缩放档位说明（\(index.scalingGroups.count) 档）",
                isOn: $showScalingTiers
            ) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("人数缩放来自 MultiPlayCorrectionParam：血量按档位倍率上浮，"
                         + "承受削韧与削韧恢复下调（更难打断），异常发动伤害与累积量下调（更难触发）。"
                         + "异常累积量倍率越小越难打出异常，不是阈值下调——触发阈值本身不随人数变化。")
                        .font(.system(size: 11))
                        .foregroundStyle(AppTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)

                    ForEach(index.scalingGroups) { tier in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Text("#\(tier.id)")
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    .foregroundStyle(AppTheme.purpleSoft)
                                Text(tier.title)
                                    .font(.system(size: 11))
                                    .foregroundStyle(AppTheme.secondaryText)
                                Spacer(minLength: 0)
                            }
                            HStack(alignment: .top, spacing: 8) {
                                if let duo = tier.duo {
                                    BossTierDetail(title: "双人", tier: duo)
                                }
                                if let trio = tier.trio {
                                    BossTierDetail(title: "三人", tier: trio)
                                }
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }

            let unmatched = index.dataset.notes?.unmatchedNames ?? []
            if !unmatched.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    Text("以下 \(unmatched.count) 组首领在游戏文本里没有对应词条，只保留英文名（对应上面的取舍说明）：")
                        .font(.system(size: 11))
                        .foregroundStyle(AppTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    ForEach(unmatched, id: \.self) { item in
                        BossDetailRow(
                            label: item.nameEn,
                            value: "chrId \(item.chrId)",
                            tint: AppTheme.secondaryText
                        )
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(AppTheme.amber.opacity(0.06))
                )
            }

            let dual = index.dualTierCards
            if !dual.isEmpty {
                Text("有 \(dual.count) 组首领同时有守夜与野外变体（\(dual.map(\.displayName).joined(separator: "、"))），"
                     + "它们在「守夜首领」与「野外首领」两个筛选下都会出现，展开后每行都标了所属档位。")
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 5) {
                BossDetailRow(label: "游戏版本", value: index.dataset.gameVersion)
                BossDetailRow(label: "数据版本", value: index.dataset.dataVersion)
                if !index.dataset.generatedAt.isEmpty {
                    BossDetailRow(label: "生成时间", value: index.dataset.generatedAt)
                }
                BossDetailRow(label: "数据集结构版本", value: "bossesSchemaVersion \(index.dataset.schemaVersion)")
                BossDetailRow(label: "收录", value: index.inventorySummary)
                ForEach(Array(index.dataset.sources.enumerated()), id: \.offset) { item in
                    BossDetailRow(
                        label: item.element.name,
                        value: item.element.revision.isEmpty ? item.element.license : item.element.revision,
                        tint: AppTheme.secondaryText
                    )
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.03))
            )
        }
        .appCard()
    }

    @ViewBuilder
    private func disclosure<Content: View>(
        title: String,
        isOn: Binding<Bool>,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                isOn.wrappedValue.toggle()
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(AppTheme.tertiaryText)
                        .rotationEffect(.degrees(isOn.wrappedValue ? 90 : 0))
                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isOn.wrappedValue {
                content()
                    .padding(.leading, 17)
            }
        }
    }

    // MARK: - 底栏

    private var footer: some View {
        HStack {
            Text(footerLeading)
            Spacer()
            Text(footerTrailing)
        }
        .font(.caption)
        .foregroundStyle(AppTheme.secondaryText)
        .padding(.horizontal, 28)
        .frame(height: 38)
        .background(AppTheme.elevated)
        .overlay(alignment: .top) { Rectangle().fill(AppTheme.border).frame(height: 1) }
    }

    private var footerLeading: String {
        guard case .ready(let index) = state else { return "完全离线，数值取自游戏参数表" }
        // 守夜 + 野外两种档位都有的组会在两个分组里各出现一次，这里按 id 去重再计数。
        var seen: Set<String> = []
        var rows = 0
        for section in visibleGroups(index) {
            for card in section.cards where seen.insert(card.id).inserted {
                rows += card.rows.count
            }
        }
        return "当前显示 \(seen.count) 个首领 · \(rows) 条战斗记录"
    }

    private var footerTrailing: String {
        guard case .ready(let index) = state else { return "" }
        let mode = deepOfNight ? "深夜" : "常规"
        return "\(players.title) · \(mode) · 数据版本 \(index.dataset.dataVersion)"
    }

    // MARK: - 逻辑

    private struct GroupSection: Identifiable {
        let group: BossCard.Group
        let cards: [BossCard]
        var id: String { group.rawValue }
    }

    private func visibleGroups(_ index: BossDataIndex) -> [GroupSection] {
        let groups: [BossCard.Group] = groupFilter.group.map { [$0] } ?? BossCard.Group.allCases
        return groups.map { GroupSection(group: $0, cards: index.cards(in: $0, query: query)) }
    }

    private func toggle(_ id: String) {
        withAnimation(.easeInOut(duration: 0.14)) {
            if expandedIDs.contains(id) {
                expandedIDs.remove(id)
            } else {
                expandedIDs.insert(id)
            }
        }
    }

    /// 只在首次进入时解码一次（400 KB JSON 放到后台线程），结果缓存在 @State 里。
    private func load() async {
        guard case .loading = state else { return }
        state = await Task.detached(priority: .userInitiated) { () -> BossLoadState in
            guard let data = GameDataLoader.dataIfAvailable(for: .bosses) else { return .missing }
            do {
                return .ready(try BossDataIndex(data: data))
            } catch {
                return .failed(error.localizedDescription)
            }
        }.value
    }
}
