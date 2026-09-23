import SwiftUI
import RelicCore

// 「首领数据」页按出场场合（roles，schemaVersion 4）分组后新增的小组件：
// 场合徽标、每行的出处摘要、底部的场合说明表。文案全部来自 RelicCore 的
// BossRoleText / 数据集 roleNames，这里只管样式。

/// 会自动换行的横向排布（卡头的场合徽标最多 7 个，一行放不下）。
/// 与增伤排名页的 RankerWrap 同一算法；各页组件互不引用，这里单独放一份。
struct BossWrap: Layout {
    var spacing: CGFloat = 6
    var lineSpacing: CGFloat = 5

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        let rows = layout(subviews: subviews, maxWidth: maxWidth)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.reduce(0) { $0 + $1.height } + lineSpacing * CGFloat(max(0, rows.count - 1))
        return CGSize(width: min(width, maxWidth == .infinity ? width : maxWidth), height: height)
    }

    func placeSubviews(
        in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
    ) {
        let rows = layout(subviews: subviews, maxWidth: bounds.width)
        var y = bounds.minY
        for row in rows {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(
                    at: CGPoint(x: x, y: y + (row.height - size.height) / 2),
                    proposal: ProposedViewSize(size)
                )
                x += size.width + spacing
            }
            y += row.height + lineSpacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func layout(subviews: Subviews, maxWidth: CGFloat) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            if !current.indices.isEmpty && needed > maxWidth {
                rows.append(current)
                current = Row(indices: [index], width: size.width, height: size.height)
            } else {
                current.indices.append(index)
                current.width = needed
                current.height = max(current.height, size.height)
            }
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}

/// 场合 → 颜色 / 图标。颜色跟着场合所在的分组走（「其它场合」里的几种共用一色），
/// 默认隐藏的「未放置」「随从/召唤物」一律压暗。
enum BossRoleStyle {
    /// AppTheme 只有紫 / 绿 / 琥珀 / 红四种强调色，六个可见分组不够分，下面三种只在本页用，
    /// 不往全局主题里加。
    /// 据点首领：铜色（与夜王的琥珀色区分开）。
    static let strongholdTint = Color(red: 0.92, green: 0.54, blue: 0.34)
    /// 封印监牢：青蓝色。
    static let evergaolTint = Color(red: 0.36, green: 0.70, blue: 0.93)
    /// 其它场合（高塔 / 突袭 / 入侵 / 事件等）：兰紫色。
    static let otherTint = Color(red: 0.84, green: 0.55, blue: 0.93)

    static func color(for group: BossCard.Group) -> Color {
        switch group {
        case .nightlord: return AppTheme.amber
        case .night: return AppTheme.purpleSoft
        case .stronghold: return strongholdTint
        case .field: return AppTheme.green
        case .evergaol: return evergaolTint
        case .other: return otherTint
        case .summon, .unplaced: return AppTheme.tertiaryText
        }
    }

    static func color(forRole role: String) -> Color {
        color(for: BossCard.Group.forRole(role))
    }

    static func symbol(forRole role: String) -> String {
        BossCard.Group.forRole(role).symbol
    }
}

/// 一个场合徽标。`emphasized = false` 时（场合不属于当前分组）用中性色，
/// 让用户一眼看出「这张卡为什么出现在这个分组里」。
struct BossRolePill: View {
    let title: String
    let role: String
    var emphasized: Bool = true

    var body: some View {
        let hidden = BossRoleCatalog.hiddenRoles.contains(role)
        let tint: Color = hidden
            ? AppTheme.tertiaryText
            : (emphasized ? BossRoleStyle.color(forRole: role) : AppTheme.secondaryText)
        Pill(text: title, color: tint, symbol: BossRoleStyle.symbol(forRole: role))
    }
}

/// 一组场合徽标（卡头 / 行内共用）。没有场合数据时挂「出场场合：数据未内置」。
struct BossRoleBadges: View {
    let roles: [String]
    let dataset: BossDataset
    /// 当前所在分组；nil 表示不区分（全部着色）。
    var group: BossCard.Group? = nil

    var body: some View {
        if roles.isEmpty {
            Pill(text: BossRoleText.rolesMissing, color: AppTheme.tertiaryText, symbol: "questionmark.circle")
        } else {
            ForEach(roles, id: \.self) { role in
                BossRolePill(
                    title: dataset.roleTitle(role),
                    role: role,
                    emphasized: group.map { $0.contains(role: role) } ?? true
                )
                .help(dataset.roleDescription(role))
            }
        }
    }
}

/// 展开区每行的「出场场合」小节：逐个场合给出处摘要（第一条 + 另有 N 条），
/// 合并行各原始行场合不同时再列「逐行场合」。
struct BossRoleEvidenceSection: View {
    let row: BossFight
    let dataset: BossDataset
    /// 展开全部出处（每行各自记，收起卡片后归零）。
    @State private var showAll = false

    private var hasMore: Bool {
        row.roles.contains { row.evidence(for: $0).count > 1 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            BossSubHeading(
                title: BossRoleText.roleSectionTitle,
                detail: BossRoleText.roleSectionDetail
            )
            if !row.hasRoles {
                Text(BossRoleText.rolesMissing)
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.tertiaryText)
            } else {
                ForEach(row.roles, id: \.self) { role in
                    roleLine(role)
                }
                if hasMore {
                    Button(showAll ? BossRoleText.evidenceCollapse : BossRoleText.evidenceExpand) {
                        showAll.toggle()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(AppTheme.purpleSoft)
                }
                if let summary = dataset.rowRolesSummary(row) {
                    Text(summary)
                        .font(.system(size: 10))
                        .foregroundStyle(AppTheme.amber)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
            }
        }
    }

    @ViewBuilder
    private func roleLine(_ role: String) -> some View {
        let evidence = row.evidence(for: role)
        HStack(alignment: .top, spacing: 8) {
            // 固定列宽：场合名长短不一（封印监牢 / 大空洞高塔首领），出处摘要要对齐成一列。
            BossRolePill(title: dataset.roleTitle(role), role: role)
                .frame(width: 164, alignment: .leading)
                .help(dataset.roleDescription(role))
            VStack(alignment: .leading, spacing: 4) {
                if evidence.isEmpty {
                    Text(BossRoleText.evidenceMissing)
                        .font(.system(size: 10))
                        .foregroundStyle(AppTheme.tertiaryText)
                } else {
                    ForEach(Array((showAll ? evidence : Array(evidence.prefix(1))).enumerated()), id: \.offset) { item in
                        evidenceLine(item.element)
                    }
                    if !showAll, evidence.count > 1 {
                        Text(BossRoleText.evidenceMore(evidence.count - 1))
                            .font(.system(size: 10))
                            .foregroundStyle(AppTheme.tertiaryText)
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func evidenceLine(_ item: BossRoleEvidence) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                // 合并行：出处可能来自被合并掉的原始行，标出来才对得上 npcId。
                if let npcId = item.npcId, npcId != row.npcId {
                    Text(verbatim: "行 \(npcId)")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(AppTheme.amber)
                }
                Text(item.summary)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(AppTheme.secondaryText)
                    .textSelection(.enabled)
            }
            if !item.note.isEmpty {
                Text(item.note)
                    .font(.system(size: 10))
                    .foregroundStyle(AppTheme.tertiaryText)
                    .lineLimit(showAll ? nil : 2)
                    .fixedSize(horizontal: false, vertical: true)
                    .help(item.note)
            }
        }
    }
}

/// 底部「出场场合说明」：每个场合归哪个分组、多少组、判定说明，以及 tier 对照结论。
struct BossRoleOverview: View {
    let index: BossDataIndex

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(BossRoleText.threatTierNote + "。")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(AppTheme.amber)
                .fixedSize(horizontal: false, vertical: true)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(AppTheme.amber.opacity(0.06))
                )

            ForEach(index.dataset.orderedRoles, id: \.self) { role in
                roleRow(role)
            }

            let audit = index.dataset.notes?.roleAuditSummary ?? []
            if !audit.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    Text(BossRoleText.auditTitle(audit.count))
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

    private func roleRow(_ role: String) -> some View {
        let group = BossCard.Group.forRole(role)
        let lords = index.cards.filter { $0.isNightlord && $0.roles.contains(role) }.count
        let bosses = index.bossCardCount(role: role)
        let counts = BossRoleText.roleCountText(groups: bosses, nightlords: lords)
        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                BossRolePill(title: index.dataset.roleTitle(role), role: role)
                Text("→ " + group.title + (group.isHiddenByDefault ? BossRoleText.hiddenGroupMark : ""))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppTheme.secondaryText)
                Text(counts)
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.tertiaryText)
                Spacer(minLength: 0)
            }
            let description = index.dataset.roleDescription(role)
            if !description.isEmpty {
                Text(description)
                    .font(.system(size: 10))
                    .foregroundStyle(AppTheme.tertiaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
        }
        .padding(.vertical, 2)
    }
}
