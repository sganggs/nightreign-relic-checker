import SwiftUI
import RelicCore

// 词条反查页的两个详情面板（「按词条查」/「按遗物查」）与共用小组件。
// 全部是无状态的展示组件，数据由 AffixLookupView 传进来。

// MARK: - 按词条查

struct AffixLookupDetailPane: View {
    let index: AffixLookupIndex
    let effectID: Int?
    let rowLimit: Int
    let conflictLimit: Int
    let catalogSources: [CatalogSource]
    let relicSources: [CatalogSource]
    /// 遗物物品表缺失 / 解析失败的原因，由外层从 AppModel 取。
    let relicDataDetail: String
    let onPickAffix: (Int) -> Void
    let onPickRelic: (Int) -> Void

    /// 互斥组默认只列前 `conflictLimit` 条，超出部分由「展开全部」就地展开。
    /// 「词条库」页没有按 compatibilityId 过滤的能力（searchableText 里不含它），
    /// 不能把用户指过去，所以必须在本页看全。
    @State private var conflictsExpanded = false

    var body: some View {
        ScrollView {
            if let effectID, let report = index.report(for: effectID) {
                VStack(alignment: .leading, spacing: 16) {
                    summaryCard(report)
                    // 四支与 Windows 端 pages/lookup.js 的 conflictBranch() 同一条链，
                    // 顺序也相同：不可达优先于 compatibilityID == -1（真实数据里有 148 条
                    // 两个条件同时成立的效果，顺序一反两端就给出相反的口径）。
                    switch AffixConflictBranch.of(
                        reachable: report.affix.appearsOnRelic,
                        compatibilityID: report.affix.compatibilityID,
                        peerCount: report.conflicts.count
                    ) {
                    case .unreachable:
                        // 互斥组是对称的：这条词条进不了任何槽位池，也就不进任何互斥组。
                        // 与其让「互斥组」整块消失，不如把原因写出来（两端同一句话）。
                        LookupNoticeCard(title: "不参与互斥判定", detail: affixLookupUnreachableConflictNote)
                    case .noGroup:
                        LookupNoticeCard(title: "互斥组", detail: affixLookupNoConflictGroupNote)
                    case .peers:
                        conflictCard(report)
                    case .lone:
                        LookupNoticeCard(
                            title: "互斥组",
                            detail: affixLookupLoneConflictNote(report.affix.compatibilityID)
                        )
                    }
                    deepCard(report)
                    if report.hasRelicData {
                        whereCard(report)
                    } else {
                        LookupNoticeCard(
                            title: "遗物物品表不可用",
                            detail: relicDataDetail
                                + "本页只能给出词条说明与互斥组；「能在哪出」「按遗物查」需要遗物物品表。"
                        )
                    }
                    LookupSourcesCard(catalogSources: catalogSources, relicSources: relicSources)
                }
                .padding(24)
                .frame(maxWidth: 900, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            } else {
                EmptyStateView(
                    title: "选择一条词条",
                    symbol: "magnifyingglass.circle",
                    detail: "在左侧搜索并选中词条，这里会列出它的说明、互斥组，以及能在哪些遗物、哪些池里出。"
                )
                .frame(maxWidth: .infinity)
                .padding(.top, 60)
            }
        }
        // 换一条词条就收起互斥组，不然新词条会一上来就铺开上百个标签
        .task(id: effectID) { conflictsExpanded = false }
    }

    // MARK: 词条说明

    /// 真正有正常遗物在用的槽位池数量（物品表里有些池只被超范围参数行引用）。
    /// 没有遗物物品表时退回词条库自带的 poolIds 条数。
    private func livePoolCount(_ report: AffixLookupReport) -> Int {
        guard report.hasRelicData else { return report.poolIDs.count }
        return report.poolIDs.filter { (index.relicCountByPool[$0] ?? 0) > 0 }.count
    }

    private func summaryCard(_ report: AffixLookupReport) -> some View {
        let affix = report.affix
        return VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(affix.displayName)
                    .font(.system(size: 19, weight: .bold))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Text(String(affix.effectID))
                    .font(.callout.monospaced())
                    .foregroundStyle(AppTheme.tertiaryText)
            }

            HStack(spacing: 7) {
                Pill(text: affix.category, color: AppTheme.purpleSoft, symbol: "tag")
                if affix.inCatalog {
                    Pill(text: "叠加性：\(affix.superposability)", color: AppTheme.secondaryTextPill)
                } else {
                    Pill(text: "仅物品表收录", color: AppTheme.amber, symbol: "exclamationmark.triangle")
                }
                if affix.isCurse { Pill(text: "负面词条", color: AppTheme.red, symbol: "minus.circle") }
                if affix.requiresCurse { Pill(text: "需配诅咒", color: AppTheme.amber, symbol: "link") }
                Spacer(minLength: 0)
            }

            if !affix.explanation.isEmpty {
                Text(affix.explanation)
                    .font(.callout)
                    .foregroundStyle(AppTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            } else if !affix.inCatalog {
                Text("这条词条只出现在遗物物品表里，词条库没有收录说明与叠加性。")
                    .font(.caption)
                    .foregroundStyle(AppTheme.tertiaryText)
            }

            Divider().overlay(AppTheme.border)

            HStack(alignment: .top, spacing: 26) {
                LookupKeyValue(key: "保存排序键 sortId", value: String(affix.sortID))
                LookupKeyValue(
                    key: "互斥组 compatibilityId",
                    value: affix.compatibilityID == -1 ? "-1（不互斥）" : String(affix.compatibilityID)
                )
                LookupKeyValue(key: "所在槽位池", value: livePoolCount(report) == 0 ? "无" : "\(livePoolCount(report)) 个")
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .appCard()
    }

    // MARK: 互斥组

    private func conflictCard(_ report: AffixLookupReport) -> some View {
        // 物品表补充条目没有说明，且大多不会出现在遗物槽池里，排在词条库条目之后
        let catalogOnes = report.conflicts.filter(\.inCatalog)
        let extraOnes = report.conflicts.filter { !$0.inCatalog }
        let preferred = catalogOnes + extraOnes
        let extras = extraOnes.count
        let shown = conflictsExpanded ? preferred : Array(preferred.prefix(conflictLimit))
        return VStack(alignment: .leading, spacing: 12) {
            SectionHeading(
                title: "互斥组（compatibilityId \(report.affix.compatibilityID)）",
                subtitle: "同组词条不能出现在同一件遗物上，共 \(report.conflicts.count + 1) 条"
                    + (extras > 0 ? "（其中 \(extras) 条只见于遗物物品表）" : ""),
                symbol: "arrow.triangle.branch"
            )
            LookupFlow(items: shown.map(\.id)) { id in
                if let affix = index.affix(id) {
                    Button { onPickAffix(id) } label: {
                        Text(affix.displayName)
                            .font(.caption)
                            .lineLimit(1)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(AppTheme.field, in: RoundedRectangle(cornerRadius: 7))
                            .overlay(RoundedRectangle(cornerRadius: 7).stroke(AppTheme.border, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .help(Text(verbatim: index.affixName(id) + "（" + String(id) + "）"))
                }
            }
            // 最大的互斥组有 102 条，必须能在本页看全
            if report.conflicts.count > conflictLimit {
                HStack(spacing: 10) {
                    Button {
                        conflictsExpanded.toggle()
                    } label: {
                        Text(verbatim: conflictsExpanded
                             ? "收起（只看前 \(conflictLimit) 条）"
                             : "展开全部 \(report.conflicts.count) 条")
                            .font(.caption)
                    }
                    Text(verbatim: conflictsExpanded
                         ? "已列出全部 \(report.conflicts.count) 条互斥词条"
                         : "还有 \(report.conflicts.count - conflictLimit) 条未列出")
                        .font(.caption2)
                        .foregroundStyle(AppTheme.tertiaryText)
                    Spacer(minLength: 0)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .appCard()
    }

    // MARK: 深夜信息

    private func deepCard(_ report: AffixLookupReport) -> some View {
        let hits = report.deepHits
        let inAny = hits.contains(where: \.contains) || report.cursePoolHit.contains
        // 结论文案由 RelicCore 统一给，Windows 端读同一个函数的同一支（两端逐字一致）。
        let note = affixLookupDeepNote(
            isCurse: report.affix.isCurse,
            requiresCurse: report.affix.requiresCurse,
            inAnyPool: inAny,
            cursePoolID: deepCurseLookupPool,
            curseCount: report.cursePoolHit.memberCount
        )
        return VStack(alignment: .leading, spacing: 12) {
            SectionHeading(
                title: "深夜遗物",
                subtitle: "A / B / C 三池的归属，以及这一行要不要配诅咒",
                symbol: "moon.stars"
            )

            VStack(spacing: 8) {
                ForEach(hits) { LookupPoolRow(hit: $0) }
                LookupPoolRow(hit: report.cursePoolHit)
            }

            LookupInlineNote(
                symbol: report.affix.isCurse
                    ? "minus.circle"
                    : (report.affix.requiresCurse ? "link" : (inAny ? "checkmark.circle" : "info.circle")),
                tint: report.affix.isCurse
                    ? AppTheme.red
                    : (report.affix.requiresCurse ? AppTheme.amber : (inAny ? AppTheme.green : AppTheme.tertiaryText)),
                text: note
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .appCard()
    }

    // MARK: 能在哪出

    private func whereCard(_ report: AffixLookupReport) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeading(
                title: "能在哪出",
                subtitle: report.totalRelicCount == 0
                    ? "按当前数据，没有正常可获得的遗物能出这条词条"
                    : "共 \(report.totalRelicCount) 件遗物：固定 \(report.fixedRelics.count) 件 · 随机池 \(report.randomRelics.count) 件",
                symbol: "shippingbox"
            )

            Text("普通随机遗物的出货口径")
                .font(.caption.weight(.bold))
                .foregroundStyle(AppTheme.secondaryText)

            VStack(spacing: 8) {
                ForEach(report.modeHits) { LookupModeRow(hit: $0) }
            }

            Text("普通大遗物按孔数分层取池：1 孔取 1 孔层池，2 孔取 2 孔层 + 1 孔层，3 孔取 3 / 2 / 1 孔层。"
                 + "三层是嵌套关系（大池包含小池），层号指的是孔数，不是槽位的先后顺序。")
                .font(.caption2)
                .foregroundStyle(AppTheme.tertiaryText)
                .fixedSize(horizontal: false, vertical: true)

            if report.modeHits.allSatisfy({ !$0.isAvailable }) && report.totalRelicCount > 0 {
                LookupInlineNote(
                    symbol: "info.circle",
                    tint: AppTheme.purpleSoft,
                    text: "上面三行只讲普通随机遗物的槽位池。本条不在这些池里，"
                        + "但下面列出的遗物仍能带上它（固定词条池，或深夜遗物的诅咒池）。"
                )
            }

            if !report.kindCounts.isEmpty {
                Divider().overlay(AppTheme.border)
                LookupFlow(items: report.kindCounts.map(\.id)) { kind in
                    if let item = report.kindCounts.first(where: { $0.kind == kind }) {
                        Pill(text: "\(item.kind) \(item.count)", color: AppTheme.purpleSoft)
                    }
                }
            }

            if !report.fixedRelics.isEmpty {
                LookupHitList(
                    title: "固定带这条词条（槽位池只有这一条）",
                    hits: report.fixedRelics,
                    limit: rowLimit,
                    tint: AppTheme.green,
                    onPick: onPickRelic
                )
            }
            if !report.randomRelics.isEmpty {
                LookupHitList(
                    title: "随机池里可能出（同池还有别的词条）",
                    hits: report.randomRelics,
                    limit: rowLimit,
                    tint: AppTheme.purpleSoft,
                    onPick: onPickRelic
                )
            }
            if report.hiddenRelicCount > 0 {
                Text(verbatim: "另有 \(report.hiddenRelicCount) 条不会正常获得的物品表条目未列出："
                     + "超出合法 ID 区间 / 没有名称的参数行（调试、未启用条目），"
                     + "以及 20000–30035 作弊器区段的遗物。")
                    .font(.caption2)
                    .foregroundStyle(AppTheme.tertiaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .appCard()
    }
}

// MARK: - 按遗物查

struct RelicLookupDetailPane: View {
    /// 每个槽位最多展示多少条池成员预览（两端同值，见 RelicCore 的同名常量）。
    private static let slotPreviewLimit = affixLookupSlotPreviewLimit

    let index: AffixLookupIndex
    let relicID: Int?
    let catalogSources: [CatalogSource]
    let relicSources: [CatalogSource]
    /// 遗物物品表缺失 / 解析失败的原因，由外层从 AppModel 取。
    let relicDataDetail: String
    let onPickAffix: (Int) -> Void

    var body: some View {
        ScrollView {
            if !index.hasRelicData {
                EmptyStateView(
                    title: "遗物物品表不可用",
                    symbol: "shippingbox",
                    detail: relicDataDetail + "无法按遗物反查槽位池。"
                )
                .frame(maxWidth: .infinity)
                .padding(.top, 60)
            } else if let relicID, let entry = index.relic(relicID) {
                VStack(alignment: .leading, spacing: 16) {
                    summaryCard(entry)
                    slotsCard(entry)
                    if let fixed = entry.fixedEffectIDs { fixedCard(entry, fixed: fixed) }
                    LookupSourcesCard(catalogSources: catalogSources, relicSources: relicSources)
                }
                .padding(24)
                .frame(maxWidth: 900, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            } else {
                EmptyStateView(
                    title: "选择一件遗物",
                    symbol: "shippingbox",
                    detail: "在左侧搜索并选中遗物，这里会列出它每个槽位的词条池成员；唯一遗物还会给出官方固定词条。"
                )
                .frame(maxWidth: .infinity)
                .padding(.top, 60)
            }
        }
    }

    private func summaryCard(_ entry: RelicLookupEntry) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(entry.displayName)
                    .font(.system(size: 19, weight: .bold))
                Spacer(minLength: 0)
                Text(String(entry.id))
                    .font(.callout.monospaced())
                    .foregroundStyle(AppTheme.tertiaryText)
            }
            HStack(spacing: 7) {
                Pill(text: entry.kindLabel, color: entry.deep ? AppTheme.purpleSoft : AppTheme.secondaryTextPill)
                Pill(text: "\(entry.colorLabel)色", color: AppTheme.purpleSoft, symbol: "circle.fill")
                Pill(text: "\(entry.slotCount) 孔", color: AppTheme.purpleSoft, symbol: "square.grid.3x1.below.line.grid.1x2")
                if entry.fixedEffectIDs != nil {
                    Pill(text: "词条固定", color: AppTheme.green, symbol: "lock")
                }
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .appCard()
    }

    private struct DeepPoolGroup: Identifiable {
        let slot: RelicSlotSummary
        let count: Int
        var id: Int { slot.poolID }
    }

    /// 深夜遗物的池构成：按池 id 归并，不按参数表的行序展示。
    ///
    /// 参数表里深夜遗物的行排列与游戏实际生成不符（见 RelicAudit 第 7 条注释），
    /// 存档里的正面词条又是按 (sortId, effectId) 升序保存的，两者没有对应关系；
    /// 一旦打出「第 N 槽」，用户就会拿存档第 N 行去对，结论必然是错的。
    private func deepPoolGroups(_ entry: RelicLookupEntry) -> [DeepPoolGroup] {
        var counts: [Int: Int] = [:]
        var firstSlot: [Int: RelicSlotSummary] = [:]
        for slot in entry.slots where !slot.isEmpty {
            counts[slot.poolID, default: 0] += 1
            if firstSlot[slot.poolID] == nil { firstSlot[slot.poolID] = slot }
        }
        return counts.keys.sorted().compactMap { poolID in
            guard let slot = firstSlot[poolID] else { return nil }
            return DeepPoolGroup(slot: slot, count: counts[poolID] ?? 0)
        }
    }

    private func slotsCard(_ entry: RelicLookupEntry) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            SectionHeading(
                title: "槽位池",
                subtitle: entry.deep
                    ? "深夜遗物的正面词条按池配对：A 池词条必定同时带一条深夜诅咒"
                    : "每个槽位从自己的池里抽一条正面词条",
                symbol: "square.grid.3x1.below.line.grid.1x2"
            )
            if entry.deep {
                ForEach(deepPoolGroups(entry)) { group in
                    RelicSlotRow(
                        index: index,
                        slot: group.slot,
                        title: "本件 \(group.count) 条",
                        limit: Self.slotPreviewLimit,
                        onPickAffix: onPickAffix
                    )
                }
                LookupInlineNote(
                    symbol: "exclamationmark.triangle",
                    tint: AppTheme.amber,
                    text: "深夜遗物只给池构成、不给槽位顺序：参数表里深夜遗物的行排列与游戏实际生成不符，"
                        + "存档里的正面词条又是按保存顺序（sortId 升序）排的，两者没有对应关系。"
                        + "某件深夜遗物是否合法，请以「存档检查」页的按行配对判定为准。"
                )
            } else {
                ForEach(entry.slots) { slot in
                    RelicSlotRow(
                        index: index,
                        slot: slot,
                        title: "第 \(slot.slotIndex + 1) 槽",
                        limit: Self.slotPreviewLimit,
                        onPickAffix: onPickAffix
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .appCard()
    }

    private func fixedCard(_ entry: RelicLookupEntry, fixed: [Int]) -> some View {
        let ids = fixed.filter { $0 != -1 }
        return VStack(alignment: .leading, spacing: 12) {
            SectionHeading(
                title: "官方固定词条",
                subtitle: "每个槽位池都只有一条词条，因此这件遗物的词条完全确定（已按保存顺序排列）",
                symbol: "lock"
            )
            VStack(spacing: 7) {
                ForEach(Array(ids.enumerated()), id: \.offset) { position, id in
                    Button { onPickAffix(id) } label: {
                        HStack(spacing: 9) {
                            Text(verbatim: String(position + 1))
                                .font(.caption.monospaced().weight(.bold))
                                .foregroundStyle(AppTheme.purpleSoft)
                                .frame(width: 18)
                            Text(index.affixName(id))
                                .font(.callout)
                                .foregroundStyle(.white)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                            Spacer(minLength: 8)
                            Text(String(id))
                                .font(.caption2.monospaced())
                                .foregroundStyle(AppTheme.tertiaryText)
                        }
                        .padding(.horizontal, 11)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(AppTheme.field, in: RoundedRectangle(cornerRadius: 9))
                        .overlay(RoundedRectangle(cornerRadius: 9).stroke(AppTheme.border, lineWidth: 1))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            LookupInlineNote(
                symbol: "info.circle",
                tint: AppTheme.purpleSoft,
                text: "存档里这件遗物出现别的词条，就是被改动过；「存档检查」页会直接给出这份官方词条。"
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .appCard()
    }
}

// MARK: - 共用组件

struct LookupKeyValue: View {
    let key: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(key)
                .font(.caption2)
                .foregroundStyle(AppTheme.tertiaryText)
            Text(value)
                .font(.callout.monospaced())
        }
    }
}

struct LookupInlineNote: View {
    let symbol: String
    let tint: Color
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: symbol)
                .font(.caption)
                .foregroundStyle(tint)
                .padding(.top, 1)
            Text(text)
                .font(.caption)
                .foregroundStyle(AppTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(tint.opacity(0.07), in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(tint.opacity(0.24), lineWidth: 1))
    }
}

struct LookupNoticeCard: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeading(title: title, subtitle: detail, symbol: "exclamationmark.triangle", tint: AppTheme.amber)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .appCard()
    }
}

struct LookupPoolRow: View {
    let hit: LookupPoolHit

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: hit.contains ? "checkmark.circle.fill" : "circle")
                .font(.caption)
                .foregroundStyle(hit.contains ? AppTheme.green : AppTheme.tertiaryText)
            VStack(alignment: .leading, spacing: 2) {
                Text(hit.label)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(hit.contains ? Color.white : AppTheme.secondaryText)
                if !hit.detail.isEmpty {
                    Text(hit.detail)
                        .font(.caption2)
                        .foregroundStyle(AppTheme.tertiaryText)
                }
            }
            Spacer(minLength: 8)
            // 没有遗物物品表时只知道「在不在这个池里」，不知道池有多大
            Text(verbatim: hit.memberCount == 0
                 ? "池 \(hit.poolID)"
                 : "池 \(hit.poolID) · \(hit.memberCount) 条 · \(hit.relicCount) 件遗物")
                .font(.caption2.monospaced())
                .foregroundStyle(AppTheme.tertiaryText)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .background(
            (hit.contains ? AppTheme.green.opacity(0.07) : AppTheme.field),
            in: RoundedRectangle(cornerRadius: 9)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9)
                .stroke(hit.contains ? AppTheme.green.opacity(0.28) : AppTheme.border, lineWidth: 1)
        )
    }
}

struct LookupModeRow: View {
    let hit: LookupModeHit

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: hit.isAvailable ? "checkmark.circle.fill" : "xmark.circle")
                .font(.caption)
                .foregroundStyle(hit.isAvailable ? AppTheme.green : AppTheme.tertiaryText)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 5) {
                Text(hit.mode.title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(hit.isAvailable ? Color.white : AppTheme.secondaryText)
                Text(hit.mode.detail)
                    .font(.caption2)
                    .foregroundStyle(AppTheme.tertiaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if hit.isAvailable {
                HStack(spacing: 5) {
                    ForEach(hit.hitPools) { pool in
                        Pill(text: pool.label, color: AppTheme.green)
                    }
                }
            } else {
                Text("不可出")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.tertiaryText)
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .background(AppTheme.field, in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(AppTheme.border, lineWidth: 1))
    }
}

struct LookupHitList: View {
    let title: String
    let hits: [RelicLookupHit]
    let limit: Int
    let tint: Color
    let onPick: (Int) -> Void

    /// 超过 `limit` 件时默认折叠；截断提示必须配一个能执行的展开动作，
    /// 不然用户拿不到剩下那些遗物。
    @State private var expanded = false

    var body: some View {
        let shown = expanded ? hits : Array(hits.prefix(limit))
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(AppTheme.secondaryText)
                Pill(text: "\(hits.count) 件", color: tint)
                Spacer(minLength: 0)
            }
            LazyVStack(spacing: 6) {
                ForEach(shown) { hit in
                    Button { onPick(hit.relicID) } label: {
                        HStack(spacing: 9) {
                            Text(hit.relicName)
                                .font(.system(size: 12.5, weight: .semibold))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                            Text(hit.kindLabel)
                                .font(.caption2)
                                .foregroundStyle(AppTheme.secondaryText)
                            if hit.role == .curse {
                                Text("诅咒槽")
                                    .font(.caption2)
                                    .foregroundStyle(AppTheme.red)
                            }
                            Spacer(minLength: 8)
                            Text(hit.poolIDs.map { affixPoolLabel($0) }.joined(separator: " / "))
                                .font(.caption2)
                                .foregroundStyle(AppTheme.tertiaryText)
                                .lineLimit(1)
                            Text(String(hit.relicID))
                                .font(.caption2.monospaced())
                                .foregroundStyle(AppTheme.tertiaryText)
                                .frame(width: 62, alignment: .trailing)
                        }
                        .padding(.horizontal, 11)
                        .padding(.vertical, 7)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(AppTheme.field, in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppTheme.border, lineWidth: 1))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            if hits.count > limit {
                HStack(spacing: 10) {
                    Button {
                        expanded.toggle()
                    } label: {
                        Text(verbatim: expanded
                             ? "收起（只看前 \(limit) 件）"
                             : "展开全部 \(hits.count) 件")
                            .font(.caption)
                    }
                    // 「共 N 件 · 已显示 M 件」这句与 Windows 端逐字相同；
                    // 控件不同（那边是翻页）没关系，计数口径必须一样。
                    Text(verbatim: affixLookupHitCountText(total: hits.count, shown: shown.count)
                         + "；上面的种类统计是全部命中的分布")
                        .font(.caption2)
                        .foregroundStyle(AppTheme.tertiaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
            }
        }
        // 换一条词条（命中集合变了）就收回折叠状态
        .task(id: hits.map(\.relicID)) { expanded = false }
    }
}

struct RelicSlotRow: View {
    let index: AffixLookupIndex
    let slot: RelicSlotSummary
    /// 行首标签。普通遗物给「第 N 槽」；深夜遗物给「本件 N 条」——
    /// 参数表的行序对深夜遗物不成立，不能打出槽序号。
    let title: String
    let limit: Int
    let onPickAffix: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(verbatim: title)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(slot.isEmpty ? AppTheme.tertiaryText : AppTheme.purpleSoft)
                if slot.isEmpty {
                    Text("无槽位")
                        .font(.caption)
                        .foregroundStyle(AppTheme.tertiaryText)
                } else {
                    Pill(text: affixPoolLabel(slot.poolID), color: AppTheme.purpleSoft)
                    Pill(
                        text: slot.isFixed ? "固定 1 条" : "随机 \(slot.poolSize) 条",
                        color: slot.isFixed ? AppTheme.green : AppTheme.secondaryTextPill
                    )
                    if slot.hasCurse {
                        Pill(text: "配诅咒 · \(slot.cursePoolSize) 条", color: AppTheme.amber, symbol: "link")
                    }
                }
                Spacer(minLength: 0)
                // 具名池（深夜 A/B/C 等）的标签里没有 id，这里补上；普通池的标签本身就是「池 xxx」
                if !slot.isEmpty, affixPoolLabel(slot.poolID) != "池 \(slot.poolID)" {
                    Text(verbatim: "池 \(slot.poolID)")
                        .font(.caption2.monospaced())
                        .foregroundStyle(AppTheme.tertiaryText)
                }
            }

            if !slot.isEmpty {
                let shown = Array(slot.previewEffectIDs.prefix(limit))
                LookupFlow(items: shown) { id in
                    Button { onPickAffix(id) } label: {
                        Text(index.affixName(id))
                            .font(.caption)
                            .lineLimit(1)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 7))
                            .overlay(RoundedRectangle(cornerRadius: 7).stroke(AppTheme.border, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .help(Text(verbatim: index.affixName(id) + "（" + String(id) + "）"))
                }
                if slot.poolSize > shown.count {
                    Text(verbatim: "池内另有 \(slot.poolSize - shown.count) 条词条，可在「按词条查」里逐条反查。")
                        .font(.caption2)
                        .foregroundStyle(AppTheme.tertiaryText)
                }
            }
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.field.opacity(0.7), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(AppTheme.border, lineWidth: 1))
    }
}

/// 数据来源与口径说明，默认折叠。
struct LookupSourcesCard: View {
    let catalogSources: [CatalogSource]
    let relicSources: [CatalogSource]

    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            DisclosureGroup(isExpanded: $expanded) {
                VStack(alignment: .leading, spacing: 12) {
                    LookupInlineNote(
                        symbol: "exclamationmark.triangle",
                        tint: AppTheme.amber,
                        text: "本页只回答「能不能出」，不回答「多大概率出」：槽位池的抽取权重不在数据集里。"
                            + "词条名与池的归属来自游戏参数表与社区整理，不是官方公布的掉落表，也不是实测统计。"
                    )
                    if !catalogSources.isEmpty {
                        sourceList(title: "词条库来源", sources: catalogSources)
                    }
                    if !relicSources.isEmpty {
                        sourceList(title: "遗物物品表来源", sources: relicSources)
                    }
                }
                .padding(.top, 10)
            } label: {
                Text("数据来源与口径说明")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(AppTheme.secondaryText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .appCard(padding: 16)
    }

    private func sourceList(title: String, sources: [CatalogSource]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(AppTheme.secondaryText)
            ForEach(Array(sources.enumerated()), id: \.offset) { _, source in
                VStack(alignment: .leading, spacing: 2) {
                    Text(source.name)
                        .font(.caption)
                    Text(source.url + (source.license.isEmpty ? "" : " · \(source.license)"))
                        .font(.caption2.monospaced())
                        .foregroundStyle(AppTheme.tertiaryText)
                        .textSelection(.enabled)
                }
            }
        }
    }
}

/// 简单的自动换行流式布局（用于词条标签堆）。
struct LookupFlow<Item: Hashable, Content: View>: View {
    let items: [Item]
    let spacing: CGFloat
    @ViewBuilder let content: (Item) -> Content

    init(items: [Item], spacing: CGFloat = 6, @ViewBuilder content: @escaping (Item) -> Content) {
        self.items = items
        self.spacing = spacing
        self.content = content
    }

    var body: some View {
        // 每行最多 3 列，足够容纳中文词条名，也避免 macOS 13 上缺少 Layout API 的问题
        let columns = [GridItem](
            repeating: GridItem(.flexible(), spacing: spacing, alignment: .leading),
            count: 3
        )
        LazyVGrid(columns: columns, alignment: .leading, spacing: spacing) {
            ForEach(items, id: \.self) { content($0) }
        }
    }
}

extension AppTheme {
    /// 中性灰的 Pill 配色。
    static let secondaryTextPill = Color.white.opacity(0.55)
}
