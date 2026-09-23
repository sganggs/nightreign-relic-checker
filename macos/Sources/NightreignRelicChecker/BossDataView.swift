import SwiftUI
import RelicCore

/// 首领数据页：夜王 / 守夜 / 野外首领的血量、韧性、承伤倍率与人数缩放。
///
/// 分组（schemaVersion 4）按出场场合 roles：夜王 / 守夜首领 / 据点首领 / 场景头目 /
/// 封印监牢 / 其它场合，打开「显示隐藏实体」后再多「随从/召唤物」「未放置」两项。
/// 一组首领可以同时出现在多个分组里；规则见 RelicCore 的 `BossCard.Group`。
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
    /// 分组筛选：「全部」或某一个分组。可选项随「显示隐藏实体」变化
    /// （`BossCard.Group.visibleCases(includeHidden:)`）。
    private enum GroupFilter: Hashable, Identifiable {
        case all
        case group(BossCard.Group)

        var id: String {
            switch self {
            case .all: return "all"
            case .group(let group): return group.rawValue
            }
        }

        var title: String {
            switch self {
            case .all: return "全部"
            case .group(let group): return group.title
            }
        }

        var group: BossCard.Group? {
            switch self {
            case .all: return nil
            case .group(let group): return group
            }
        }

        static func options(includeHidden: Bool) -> [GroupFilter] {
            [.all] + BossCard.Group.visibleCases(includeHidden: includeHidden).map { .group($0) }
        }
    }

    @State private var state: BossLoadState = .loading
    @State private var query = ""
    @State private var players: BossPartySize = .solo
    @State private var groupFilter: GroupFilter = .all
    /// 常规 / 深夜 · 深度 1…5。v2 的布尔「深夜」开关在这里被换掉：
    /// 深夜有 5 个深度，血量与攻击力倍率逐级不同，一个开关表达不了。
    @State private var mode: BossNightMode = .normal
    /// hidden = true 的组（召唤物 / 投射物等非首领实体）默认不显示；
    /// schemaVersion 4 起同一个开关也管「未放置」「随从/召唤物」两个场合（分组与展开区的行）。
    @State private var showHidden = false
    @State private var expandedIDs: Set<String> = []
    @State private var showCaveats = false
    @State private var showRoleOverview = false
    @State private var showScalingTiers = false
    @State private var showMutationCounts = false
    @State private var showDepthOverview = false

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

    /// 模式选择器的标题优先用数据集的游戏内文本（「深夜」「深度」），
    /// 数据缺失时退回内置文案。
    private func modeTitle(_ mode: BossNightMode) -> String {
        guard case .ready(let index) = state else { return mode.builtinTitle }
        return index.dataset.title(for: mode)
    }

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
                    TextField("搜索首领名、参考译名、远征名、变体标签、出场场合，或输入 npcId / chrId 前缀", text: $query)
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
                    ForEach(GroupFilter.options(includeHidden: showHidden)) { filter in
                        Text(filter.title).tag(filter)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 136)
                .help(BossRoleText.groupPickerHelp)

                Picker("模式", selection: $mode) {
                    ForEach(BossNightMode.allCases) { item in
                        Text(modeTitle(item)).tag(item)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 150)
                .help("深夜按深度 1–5 分档：血量与敌人攻击力逐级上涨，攻击力涨得比血量快得多")

                Toggle(BossRowText.hiddenToggleTitle, isOn: $showHidden)
                    .toggleStyle(.switch)
                    .font(.caption)
                    .help(BossRowText.hiddenToggleHelp + "；" + BossRoleText.hiddenToggleRoleHelp)
                    .onChange(of: showHidden) { isOn in
                        // 关掉开关时，正停在「随从/召唤物」「未放置」分组上就退回「全部」，
                        // 否则筛选器里选中的是一个已经不存在的选项。
                        if !isOn, let group = groupFilter.group, group.isHiddenByDefault {
                            groupFilter = .all
                        }
                    }

                if !expandedIDs.isEmpty {
                    Button("收起全部") {
                        expandedIDs.removeAll()
                    }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(AppTheme.purpleSoft)
                }
            }

            deepOfNightNote
        }
        .padding(.horizontal, 26)
        .padding(.vertical, 22)
        .background(AppTheme.elevated.opacity(0.55))
    }

    /// 顶部说明用 deepOfNightText 的游戏文本（深夜 / 深度 / 变异个体），
    /// 不要自己造词——社区叫「红化」，游戏里的正式叫法是「变异个体」。
    @ViewBuilder
    private var deepOfNightNote: some View {
        if case .ready(let index) = state, mode.isDeepOfNight {
            let text = index.dataset.deepOfNightText
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Pill(text: text.deepOfNightTitle, color: AppTheme.amber, symbol: "moon.fill")
                    Text("\(text.depthTitle) \(mode.depth ?? 0)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.amber)
                    Text("血量与敌人攻击力都按深度上浮，攻击力涨得更快；"
                         + "部分敌人还会以「\(text.mutationTitle)」出现，倍率再乘一层。")
                        .font(.system(size: 11))
                        .foregroundStyle(AppTheme.secondaryText)
                    Spacer(minLength: 0)
                }
                if !text.description.zh.isEmpty {
                    Text(text.description.zh.replacingOccurrences(of: "\n", with: " "))
                        .font(.system(size: 10))
                        .foregroundStyle(AppTheme.tertiaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(AppTheme.amber.opacity(0.06))
            )
        }
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
                                // 同一张卡可能出现在好几个分组里：展开状态按「分组 + 卡片」记，
                                // 在「守夜首领」里展开不会顺带把「场景头目」里的同一张也撑开。
                                let key = section.group.rawValue + "|" + card.id
                                BossCardView(
                                    card: card,
                                    group: section.group,
                                    index: index,
                                    players: players,
                                    mode: mode,
                                    showHidden: showHidden,
                                    isExpanded: expandedIDs.contains(key),
                                    onToggle: { toggle(key) }
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

            // 分组依据：14 种出场场合各归哪个分组、多少组、怎么判定的，以及它和威胁档位
            // （tier）对不上的原因——用户反馈「野外首领被归到守夜首领」的答案写在这里。
            disclosure(
                title: BossRoleText.overviewTitle(index.dataset.orderedRoles.count),
                isOn: $showRoleOverview
            ) {
                BossRoleOverview(index: index)
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

                    // 「多人是不是简单乘倍」是用户直接问的第三个问题，结论必须写在这里，
                    // 而不是埋在 37 条 caveats 里。摘要 + 数据集自带的逐项核实结论。
                    Text(BossRowText.multiplayerAuditSummary)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(AppTheme.amber)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(AppTheme.amber.opacity(0.06))
                        )

                    let audit = index.dataset.notes?.multiplayerScalingAudit ?? []
                    if !audit.isEmpty {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("逐项核实（数据集 notes.multiplayerScalingAudit，\(audit.count) 条）")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.white)
                            ForEach(Array(audit.enumerated()), id: \.offset) { item in
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

                    ForEach(index.scalingGroups) { tier in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Text(verbatim: "#\(tier.id)")
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

            if !index.dataset.mutationCategories.isEmpty {
                disclosure(
                    title: "\(index.dataset.mutationTitle)出现只数（\(index.dataset.mutationCategories.count) 行）",
                    isOn: $showMutationCounts
                ) {
                    BossMutationCountTable(
                        categories: index.dataset.orderedMutationCategories,
                        depthWord: index.dataset.deepOfNightText.depthTitle
                    )
                }
            }

            if !index.dataset.deepOfNightDepths.isEmpty {
                disclosure(
                    title: "\(index.dataset.deepOfNightText.depthTitle)概览（\(index.dataset.deepOfNightDepths.count) 档）",
                    isOn: $showDepthOverview
                ) {
                    VStack(alignment: .leading, spacing: 10) {
                        BossDepthOverview(infos: index.dataset.orderedDepthInfos)
                        let audit = index.dataset.notes?.deepOfNightAudit ?? []
                        if !audit.isEmpty {
                            VStack(alignment: .leading, spacing: 5) {
                                Text("逐项核实（数据集 notes.deepOfNightAudit，\(audit.count) 条）")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(.white)
                                ForEach(Array(audit.enumerated()), id: \.offset) { item in
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
                    }
                }
            }

            if let hiddenSummary = index.hiddenSummary {
                Text(hiddenSummary)
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.white.opacity(0.03))
                    )
            }

            let unmatched = index.dataset.notes?.unmatchedNames ?? []
            if !unmatched.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    Text("以下 \(unmatched.count) 组首领在本作游戏文本里查不到简中词条"
                         + "（其中一部分另有《艾尔登法环》的参考译名，主标题用它并已标注「"
                         + BossRowText.nameFallbackBadge + "」，搜索也认这些旧译名；"
                         + "其余只能显示英文名）：")
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

            let multi = index.multiGroupCards
            if !multi.isEmpty {
                Text(BossRoleText.multiGroupNote(count: multi.count, names: multi.map(\.displayName)))
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
        // 一组首领按出场场合可能出现在好几个分组里，这里按 id 去重再计数；
        // 行数只数展开区真正列出来的行（默认不含「未放置」「随从/召唤物」行）。
        var seen: Set<String> = []
        var rows = 0
        for section in visibleGroups(index) {
            for card in section.cards where seen.insert(card.id).inserted {
                rows += card.displayRows(includeHidden: showHidden).count
            }
        }
        return "当前显示 \(seen.count) 个首领 · \(rows) 条数值行"
    }

    private var footerTrailing: String {
        guard case .ready(let index) = state else { return "" }
        return "\(players.title) · \(index.dataset.title(for: mode)) · 数据版本 \(index.dataset.dataVersion)"
    }

    // MARK: - 逻辑

    private struct GroupSection: Identifiable {
        let group: BossCard.Group
        let cards: [BossCard]
        var id: String { group.rawValue }
    }

    private func visibleGroups(_ index: BossDataIndex) -> [GroupSection] {
        let groups: [BossCard.Group] = groupFilter.group.map { [$0] }
            ?? BossCard.Group.visibleCases(includeHidden: showHidden)
        return groups.map {
            GroupSection(
                group: $0,
                cards: index.cards(in: $0, query: query, includeHidden: showHidden)
            )
        }
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
