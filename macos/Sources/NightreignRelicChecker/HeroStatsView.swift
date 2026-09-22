import SwiftUI
import RelicCore

/// 角色属性页：10 位夜行者 1–15 级的属性、派生值，以及装备转职遗物 /
/// 做了利普拉的交易之后的属性。
///
/// 由「角色属性」功能开发者独占：只改本文件与 HeroStats*.swift、RelicCore 的
/// HeroData.swift、RelicCoreChecks 的 HeroStatsChecks.swift；**不改 AppModel /
/// RootView**，页面状态全部放在本视图内。
///
/// 数据：`GameDataLoader.dataIfAvailable(for: .heroes)` → `Resources/heroes.json`
/// 的原始 JSON；未内置（文件缺失或仍是占位内容）时降级显示「数据未内置」。
/// 所有换算（派生值插值、词条叠加、钳位、对比表排序）都在 RelicCore/HeroData.swift，
/// 本文件只做展示。
enum HeroLoadState: Sendable {
    case loading
    case missing
    case failed(String)
    case ready(HeroStatsIndex)
}

struct HeroStatsView: View {
    private enum Tab: String, CaseIterable, Identifiable {
        case single
        case compare

        var id: String { rawValue }

        var title: String {
            switch self {
            case .single: return HeroStatsCopy.viewSingle
            case .compare: return HeroStatsCopy.viewCompare
            }
        }
    }

    @State private var state: HeroLoadState = .loading
    @State private var tab: Tab = .single
    @State private var heroKey = ""
    @State private var level = 15
    @State private var showAllLevels = false
    @State private var selectedModifiers: Set<Int> = []
    /// 空串 = 没做利普拉的交易。
    @State private var libraKey = ""
    @State private var sortColumn: HeroComparisonColumn = .hero
    @State private var sortAscending = true
    @State private var showInterpolation = false
    @State private var showCaveats = false
    @State private var showSources = false

    private var activeLibraKey: String? { libraKey.isEmpty ? nil : libraKey }

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
                    Text("角色属性")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                    Text("《黑夜君临》各夜行者逐等级属性，以及装备转职遗物后的属性")
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                }
                Spacer()
                if case .ready(let index) = state {
                    Pill(text: index.summary, color: AppTheme.green, symbol: "checkmark.circle")
                }
            }

            if case .ready(let index) = state {
                controls(index)
            }
        }
        .padding(.horizontal, 26)
        .padding(.vertical, 22)
        .background(AppTheme.elevated.opacity(0.55))
    }

    private func controls(_ index: HeroStatsIndex) -> some View {
        HStack(spacing: 10) {
            Picker("视图", selection: $tab) {
                ForEach(Tab.allCases) { item in
                    Text(item.title).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 176)

            Picker("等级", selection: $level) {
                ForEach(index.levelRange, id: \.self) { value in
                    Text("\(value) 级").tag(value)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(width: 92)

            if tab == .single {
                Toggle("全部等级", isOn: $showAllLevels)
                    .toggleStyle(.switch)
                    .font(.caption)
                    // 等级范围与锚点一律读数据集，界面上不写死 15 与 1/2/12/15
                    .help(allLevelsHelp(index))

                Picker("利普拉的交易", selection: $libraKey) {
                    Text("利普拉：无").tag("")
                    ForEach(index.libraRespecs) { respec in
                        Text("利普拉：" + respec.shortTitle).tag(respec.key)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 150)
                .help("扭曲的重生：整套属性表替换为对应的交易版本")

                if !selectedModifiers.isEmpty || !libraKey.isEmpty {
                    Button("清空选择") {
                        selectedModifiers.removeAll()
                        libraKey = ""
                    }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(AppTheme.purpleSoft)
                }
            }

            Spacer(minLength: 0)
        }
    }

    /// 基础表的参数锚点等级（读数据集，不写死 1 / 2 / 12 / 15）。
    private func anchorText(_ index: HeroStatsIndex) -> String {
        index.dataset.interpolation.baseAnchorLevels.map(String.init).joined(separator: " / ")
    }

    private func allLevelsHelp(_ index: HeroStatsIndex) -> String {
        "切换成 1–\(index.maxLevel) 级的完整表，参数锚点行（\(anchorText(index))）高亮"
    }

    // MARK: - 主体

    @ViewBuilder
    private var content: some View {
        switch state {
        case .loading:
            VStack(spacing: 12) {
                ProgressView()
                Text("正在载入角色属性数据…")
                    .font(.callout)
                    .foregroundStyle(AppTheme.secondaryText)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .missing:
            EmptyStateView(
                title: HeroStatsCopy.emptyData,
                symbol: "person.text.rectangle",
                detail: "尚未提供 Resources/heroes.json，运行 scripts/sync-data.sh 同步后重新构建。"
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .failed(let message):
            EmptyStateView(
                title: "角色属性数据无法解析",
                symbol: "exclamationmark.triangle",
                detail: message
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .ready(let index):
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    switch tab {
                    case .single:
                        heroPickerCard(index)
                        modifierCard(index)
                        statsCard(index)
                    case .compare:
                        compareCard(index)
                    }
                    bottomNotes(index)
                }
                .padding(26)
                .frame(maxWidth: 1180)
                .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - 角色选择

    private func heroPickerCard(_ index: HeroStatsIndex) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            SectionHeading(
                title: "选择夜行者",
                subtitle: "共 \(index.heroes.count) 位，属性表取自 HeroStatusParam"
                    + "（\(anchorText(index)) 级为参数原值）",
                symbol: "person.2"
            )
            LazyVGrid(
                columns: [GridItem](repeating: GridItem(.flexible(), spacing: 9), count: 5),
                spacing: 9
            ) {
                ForEach(index.heroes) { hero in
                    HeroPickerChip(hero: hero, isSelected: hero.key == heroKey) {
                        guard hero.key != heroKey else { return }
                        heroKey = hero.key
                        selectedModifiers.removeAll()
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .appCard()
    }

    // MARK: - 转职遗物 / 利普拉

    private func modifierCard(_ index: HeroStatsIndex) -> some View {
        let modifiers = index.modifiers(for: heroKey)
        let anchors = index.dataset.interpolation.modifierAnchorLevels
        return VStack(alignment: .leading, spacing: 12) {
            SectionHeading(
                title: "转职遗物",
                subtitle: HeroStatsCopy.modifierSubtitle,
                symbol: "sparkles"
            )

            if modifiers.isEmpty {
                Text(HeroStatsCopy.noModifierData)
                    .font(.caption)
                    .foregroundStyle(AppTheme.tertiaryText)
            } else {
                ForEach(modifiers) { modifier in
                    HeroModifierToggleRow(
                        modifier: modifier,
                        isOn: selectedModifiers.contains(modifier.affixId),
                        statNames: index.statNames,
                        level: level,
                        anchorLevels: anchors,
                        delta: modifier.level(level)?.delta ?? [:],
                        deltaFloorAlt: modifier.level(level)?.deltaFloorAlt ?? [:]
                    ) {
                        if selectedModifiers.contains(modifier.affixId) {
                            selectedModifiers.remove(modifier.affixId)
                        } else {
                            selectedModifiers.insert(modifier.affixId)
                        }
                    }
                }
            }

            if let respec = index.libra(activeLibraKey) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 7) {
                        Text(respec.display)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white)
                        Pill(text: HeroStatsCopy.libraSwapTag, color: AppTheme.purpleSoft)
                        Pill(text: "参数结构推断、未实测", color: AppTheme.amber, symbol: "exclamationmark.triangle")
                    }
                    Text("已把基础属性表整套换成「\(respec.nameZh)」（\(respec.effectNameZh)：\(respec.effectInfoZh)）。"
                         + HeroStatsCopy.libraHint + "。"
                         + (index.dataset.interpolation.libraRule.isEmpty ? "" : index.dataset.interpolation.libraRule))
                        .font(.system(size: 11))
                        .foregroundStyle(AppTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(AppTheme.amber.opacity(0.06))
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .appCard()
    }

    // MARK: - 属性表

    @ViewBuilder
    private func statsCard(_ index: HeroStatsIndex) -> some View {
        if let snapshot = index.snapshot(
            heroKey: heroKey, level: level, modifierIDs: selectedModifiers, libraKey: activeLibraKey
        ) {
            VStack(alignment: .leading, spacing: 13) {
                SectionHeading(
                    title: showAllLevels ? "全部等级（1–\(index.maxLevel) 级）" : "\(level) 级属性",
                    subtitle: showAllLevels
                        ? "锚点行高亮；勾选转职遗物后，变动的格子按增减标绿 / 标红（悬停看基础值）"
                        : "8 项属性 + 血量 / 专注值 / 精力 / 负重上限；勾选转职遗物后显示「基础 → 修改后」",
                    symbol: "chart.bar.doc.horizontal"
                )

                badges(snapshot, index: index)

                let allSnapshots = showAllLevels
                    ? index.snapshots(heroKey: heroKey, modifierIDs: selectedModifiers, libraKey: activeLibraKey)
                    : []

                if showAllLevels {
                    ScrollView(.horizontal, showsIndicators: true) {
                        HeroAllLevelsTable(
                            snapshots: allSnapshots,
                            statNames: index.statNames,
                            modifierAnchorLevels: index.dataset.interpolation.modifierAnchorLevels,
                            hasModifier: snapshot.hasModifier,
                            currentLevel: level
                        )
                        .padding(.bottom, 4)
                    }
                    Text(HeroStatsCopy.allLevelsCaption(
                        anchorLevels: index.dataset.interpolation.baseAnchorLevels
                    ))
                    .font(.system(size: 10))
                    .foregroundStyle(AppTheme.tertiaryText)
                    .fixedSize(horizontal: false, vertical: true)
                } else {
                    statTiles(snapshot, index: index)
                }

                // 钳位汇总。全部等级视图下**按行聚合**：表里一次看得到 15 行，
                // 只报当前那一行会与表里的「已钳位」标记对不上。
                if showAllLevels {
                    let clampedRows = index.clampedByLevel(allSnapshots)
                    if !clampedRows.isEmpty {
                        Text(HeroStatsCopy.clampSummaryByLevel(clampedRows, maxLevel: index.maxLevel))
                            .font(.system(size: 11))
                            .foregroundStyle(AppTheme.amber)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else if !snapshot.clampedStats.isEmpty {
                    Text(HeroStatsCopy.clampSummary(
                        snapshot.clampedStats.map { index.statNames.attributeTitle($0) }
                    ))
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.amber)
                    .fixedSize(horizontal: false, vertical: true)
                }

                if let footnote = HeroTableMetrics.legacyFootnote(index.statNames) {
                    Text(footnote)
                        .font(.system(size: 10))
                        .foregroundStyle(AppTheme.tertiaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .appCard()
        } else {
            VStack(alignment: .leading, spacing: 8) {
                SectionHeading(title: "属性表", subtitle: "选中的角色或等级没有数据", symbol: "chart.bar.doc.horizontal")
                Text(HeroStatsCopy.emptyData)
                    .font(.caption)
                    .foregroundStyle(AppTheme.tertiaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .appCard()
        }
    }

    /// 当前状态的标签条：基础表等级来源 / 词条增减量来源 / 利普拉 / 与 wiki 的差异。
    /// 文案全部走 HeroStatsCopy，与 Windows 端 statusRow 逐字一致。
    private func badges(_ snapshot: HeroStatsSnapshot, index: HeroStatsIndex) -> some View {
        let source = snapshot.modifierSource
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 7) {
                Pill(
                    text: HeroStatsCopy.baseLevelBadge(level: level, isAnchor: snapshot.isAnchorLevel),
                    color: snapshot.isAnchorLevel ? AppTheme.green : AppTheme.purpleSoft,
                    symbol: snapshot.isAnchorLevel ? "checkmark.seal" : "function"
                )
                if snapshot.hasModifier {
                    Pill(
                        text: HeroStatsCopy.modifierCountBadge(snapshot.activeModifiers.count),
                        color: AppTheme.purpleSoft,
                        symbol: "sparkles"
                    )
                }
                if let source {
                    // 三档三色三图标：锚点绿 / 推算琥珀 / 沿用蓝，与 Windows 端 SOURCE_PILL
                    // 同一张表（配色名在 RelicCore 的 HeroModifierSource.colorToken 上）。
                    Pill(
                        text: source.label,
                        color: HeroFormat.sourceColor(source.source),
                        symbol: source.source.symbolName
                    )
                }
                if let respec = index.libra(activeLibraKey) {
                    Pill(
                        text: HeroStatsCopy.libraBadge(respec.shortTitle),
                        color: AppTheme.amber,
                        symbol: "arrow.triangle.2.circlepath"
                    )
                }
                Spacer(minLength: 0)
            }
            if let note = crossCheckNote(index) {
                Text(note)
                    .font(.system(size: 10))
                    .foregroundStyle(AppTheme.tertiaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// 与外部 wiki 的逐格差异提示。
    ///
    /// 做了利普拉的交易之后基础表已经**整套换掉**，展示的不再是该角色的原表，
    /// 再提「本角色与 wiki 差 N 格」会把人带偏 —— 这时改写成一句说明。
    private func crossCheckNote(_ index: HeroStatsIndex) -> String? {
        guard let check = index.crossCheck(for: heroKey) else { return nil }
        if activeLibraKey != nil { return HeroStatsCopy.libraCrossCheckNote }
        return HeroStatsCopy.crossCheckNote(count: check.mismatchCount, note: check.note)
    }

    private func statTiles(_ snapshot: HeroStatsSnapshot, index: HeroStatsIndex) -> some View {
        let names = index.statNames
        return VStack(alignment: .leading, spacing: 10) {
            LazyVGrid(
                columns: [GridItem](repeating: GridItem(.flexible(), spacing: 9), count: 4),
                spacing: 9
            ) {
                ForEach(names.orderedAttributes) { attribute in
                    HeroStatTile(
                        title: attribute.display,
                        base: snapshot.baseStats[attribute.key].map(Double.init),
                        final: snapshot.finalStats[attribute.key].map(Double.init),
                        integer: true,
                        // 被钳位的那一项：大数字旁写生效值，小字写词条请求的 -9
                        clampRequested: snapshot.clampedFrom[attribute.key] == nil
                            ? nil
                            : snapshot.requestedDelta[attribute.key]
                    )
                }
            }
            LazyVGrid(
                columns: [GridItem](repeating: GridItem(.flexible(), spacing: 9), count: 4),
                spacing: 9
            ) {
                ForEach(names.orderedDerived) { derived in
                    HeroStatTile(
                        title: derived.inGameLabel
                            ? derived.display
                            : HeroStatsCopy.legacyHeader(derived.display),
                        base: snapshot.baseDerived[derived.key],
                        final: snapshot.finalDerived[derived.key],
                        integer: derived.integer,
                        caption: derived.inGameLabel
                            ? "来自" + names.attributeTitle(derived.fromStat)
                            : HeroStatsCopy.equipLoadHint
                    )
                }
            }
        }
    }

    // MARK: - 同级对比

    private func compareCard(_ index: HeroStatsIndex) -> some View {
        let rows = HeroComparison.sorted(
            index.comparisonRows(level: level), by: sortColumn, ascending: sortAscending
        )
        return VStack(alignment: .leading, spacing: 13) {
            SectionHeading(
                title: "同级对比（\(level) 级）",
                subtitle: "\(rows.count) 位夜行者的 8 项属性与派生值；点列头排序，每列最高值标绿",
                symbol: "arrow.up.arrow.down.square"
            )
            if rows.isEmpty {
                Text(HeroStatsCopy.emptyData)
                    .font(.caption)
                    .foregroundStyle(AppTheme.tertiaryText)
            } else {
                ScrollView(.horizontal, showsIndicators: true) {
                    HeroCompareTable(
                        rows: rows,
                        statNames: index.statNames,
                        column: sortColumn,
                        ascending: sortAscending,
                        onSort: sort(by:)
                    )
                    .padding(.bottom, 4)
                }
            }
            Text(HeroStatsCopy.compareCaption)
                .font(.system(size: 11))
                .foregroundStyle(AppTheme.tertiaryText)
                .fixedSize(horizontal: false, vertical: true)
            if let footnote = HeroTableMetrics.legacyFootnote(index.statNames) {
                Text(footnote)
                    .font(.system(size: 10))
                    .foregroundStyle(AppTheme.tertiaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .appCard()
    }

    private func sort(by column: HeroComparisonColumn) {
        if sortColumn == column {
            sortAscending.toggle()
        } else {
            sortColumn = column
            // 数值列默认从高到低，角色列默认按数据集顺序。
            sortAscending = column == .hero
        }
    }

    // MARK: - 底部说明

    private func bottomNotes(_ index: HeroStatsIndex) -> some View {
        let dataset = index.dataset
        return VStack(alignment: .leading, spacing: 12) {
            SectionHeading(
                title: "数据说明",
                subtitle: "数值直接取自游戏参数表，不是官方公布，也不是实测结论",
                symbol: "info.circle"
            )

            HeroDisclosure(title: HeroStatsCopy.interpolationTitle(dataset.interpolation.notes.count), isOn: $showInterpolation) {
                VStack(alignment: .leading, spacing: 9) {
                    ForEach(dataset.interpolation.notes) { note in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(note.title)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(AppTheme.purpleSoft)
                            Text(note.text)
                                .font(.system(size: 11))
                                .foregroundStyle(AppTheme.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }

            HeroDisclosure(title: HeroStatsCopy.caveatsTitle(dataset.caveats.count), isOn: $showCaveats) {
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(Array(dataset.caveats.enumerated()), id: \.offset) { item in
                        HeroBulletText(text: item.element)
                    }
                }
            }

            HeroDisclosure(title: HeroStatsCopy.sourcesTitle(dataset.sources.count), isOn: $showSources) {
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(Array(dataset.sources.enumerated()), id: \.offset) { item in
                        HeroDetailRow(
                            label: item.element.name,
                            value: item.element.revision.isEmpty ? item.element.license : item.element.revision,
                            tint: AppTheme.secondaryText
                        )
                    }
                    ForEach(dataset.crossChecks) { check in
                        HeroDetailRow(
                            label: check.heroNameZh + " 逐格对照",
                            value: "\(check.cellsCompared) 格，差异 \(check.mismatchCount) 处"
                                + (check.note.isEmpty ? "" : "；" + check.note),
                            tint: check.mismatchCount == 0 ? AppTheme.secondaryText : AppTheme.amber
                        )
                    }
                }
            }

            // 数据版本块：5 行标签与取值口径两端逐字一致（HeroStatsCopy.versionLabels）
            VStack(alignment: .leading, spacing: 5) {
                HeroDetailRow(label: HeroStatsCopy.versionLabels[0], value: dataset.gameVersion)
                HeroDetailRow(label: HeroStatsCopy.versionLabels[1], value: dataset.dataVersion)
                HeroDetailRow(
                    label: HeroStatsCopy.versionLabels[2],
                    value: dataset.generatedAt.isEmpty ? HeroStatsCopy.missing : dataset.generatedAt
                )
                HeroDetailRow(label: HeroStatsCopy.versionLabels[3], value: "schemaVersion \(dataset.schemaVersion)")
                HeroDetailRow(
                    label: HeroStatsCopy.versionLabels[4],
                    value: HeroStatsCopy.contentSummary(
                        heroes: dataset.heroes.count,
                        maxLevel: index.maxLevel,
                        modifiers: dataset.statModifiers.count,
                        libra: dataset.libraRespecs.count
                    )
                )
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.03))
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .appCard()
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
        switch tab {
        case .compare:
            return "同级对比 · \(index.comparisonRows(level: level).count) 位夜行者 · \(level) 级"
        case .single:
            let hero = index.hero(heroKey)?.display ?? "—"
            let levelText = showAllLevels ? "1–\(index.maxLevel) 级" : "\(level) 级"
            var parts = ["\(hero) · \(levelText)"]
            if !selectedModifiers.isEmpty { parts.append("转职遗物 \(selectedModifiers.count) 条") }
            if let respec = index.libra(activeLibraKey) { parts.append("利普拉：" + respec.shortTitle) }
            return parts.joined(separator: " · ")
        }
    }

    private var footerTrailing: String {
        guard case .ready(let index) = state else { return "" }
        return "数据版本 \(index.dataset.dataVersion)"
    }

    // MARK: - 载入

    /// 只在首次进入时解码一次（150 KB JSON 放到后台线程），结果缓存在 @State 里。
    private func load() async {
        guard case .loading = state else { return }
        let loaded = await Task.detached(priority: .userInitiated) { () -> HeroLoadState in
            guard let data = GameDataLoader.dataIfAvailable(for: .heroes) else { return .missing }
            do {
                return .ready(try HeroStatsIndex(data: data))
            } catch {
                return .failed(error.localizedDescription)
            }
        }.value
        if case .ready(let index) = loaded {
            if heroKey.isEmpty { heroKey = index.heroes.first?.key ?? "" }
            level = min(max(1, level), index.maxLevel)
        }
        state = loaded
    }
}
