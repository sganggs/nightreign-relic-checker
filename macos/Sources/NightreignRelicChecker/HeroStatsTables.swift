import SwiftUI
import RelicCore

// 「角色属性」页的两张表：全部等级表（1–15 级）与同级对比表（10 个角色）。
// 纯展示，所有数值都由 RelicCore 的 HeroStatsIndex 算好后传进来。

enum HeroTableMetrics {
    static let levelColumn: CGFloat = 54
    static let statColumn: CGFloat = 56
    static let derivedColumn: CGFloat = 68
    /// 「说明」列最长的一条是「参数锚点 · 词条沿用 12 级锚点 · 已钳位」
    /// （10pt 系统字实测 173.8pt，出现在「利普拉 + 转职遗物」把属性减到下限的 15 级行），
    /// 留到 186 才不会把结尾的「已钳位」吃掉。
    static let noteColumn: CGFloat = 186
    static let heroColumn: CGFloat = 118
    static let rowSpacing: CGFloat = 3
}

// MARK: - 全部等级表

/// 1–15 级完整表；锚点行（1 / 2 / 12 / 15）高亮。
struct HeroAllLevelsTable: View {
    let snapshots: [HeroStatsSnapshot]
    let statNames: HeroStatNames
    let modifierAnchorLevels: [Int]
    let hasModifier: Bool
    let currentLevel: Int

    var body: some View {
        VStack(alignment: .leading, spacing: HeroTableMetrics.rowSpacing) {
            header
            Rectangle().fill(AppTheme.border).frame(height: 1)
            ForEach(snapshots, id: \.level) { snapshot in
                row(snapshot)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            HeroHeaderCell(title: "等级", width: HeroTableMetrics.levelColumn, alignment: .leading)
            ForEach(statNames.attributeKeys, id: \.self) { key in
                HeroHeaderCell(title: statNames.attributeTitle(key), width: HeroTableMetrics.statColumn)
            }
            ForEach(statNames.derivedKeys, id: \.self) { key in
                HeroHeaderCell(title: statNames.derivedTitle(key), width: HeroTableMetrics.derivedColumn)
            }
            HeroHeaderCell(title: "说明", width: HeroTableMetrics.noteColumn, alignment: .leading)
        }
    }

    private func row(_ snapshot: HeroStatsSnapshot) -> some View {
        HStack(spacing: 6) {
            HStack(spacing: 4) {
                Text("\(snapshot.level)")
                    .font(.system(size: 12, weight: snapshot.isAnchorLevel ? .bold : .medium, design: .rounded))
                    .foregroundStyle(snapshot.isAnchorLevel ? AppTheme.purpleSoft : .white)
                if snapshot.level == currentLevel {
                    Circle().fill(AppTheme.purpleSoft).frame(width: 5, height: 5)
                }
                Spacer(minLength: 0)
            }
            .frame(width: HeroTableMetrics.levelColumn, alignment: .leading)

            ForEach(statNames.attributeKeys, id: \.self) { key in
                let base = Double(snapshot.baseStats[key] ?? 0)
                let final = Double(snapshot.finalStats[key] ?? 0)
                HeroValueCell(
                    text: HeroFormat.value(final, integer: true),
                    width: HeroTableMetrics.statColumn,
                    tint: final == base ? .white : HeroFormat.deltaColor(final - base),
                    weight: final == base ? .medium : .bold
                )
                .help(final == base ? "" : "基础 \(Int(base)) → \(Int(final))")
            }

            ForEach(statNames.derivedKeys, id: \.self) { key in
                let entry = statNames.derivedEntry(key)
                let base = snapshot.baseDerived[key] ?? 0
                let final = snapshot.finalDerived[key] ?? 0
                HeroValueCell(
                    text: HeroFormat.value(final, integer: entry?.integer ?? true),
                    width: HeroTableMetrics.derivedColumn,
                    tint: final == base ? AppTheme.secondaryText : HeroFormat.deltaColor(final - base),
                    weight: final == base ? .medium : .bold
                )
                .help(final == base ? "" : "基础 \(HeroFormat.value(base, integer: entry?.integer ?? true)) → \(HeroFormat.value(final, integer: entry?.integer ?? true))")
            }

            Text(note(for: snapshot))
                .font(.system(size: 10))
                .foregroundStyle(snapshot.isAnchorLevel ? AppTheme.purpleSoft : AppTheme.tertiaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.85)      // 文案再长一点也先缩字号，别把「已钳位」截掉
                .help(note(for: snapshot))
                .frame(width: HeroTableMetrics.noteColumn, alignment: .leading)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(snapshot.isAnchorLevel ? AppTheme.purple.opacity(0.10) : Color.clear)
        )
    }

    /// 备注列：基础表是否锚点 + 勾了词条时的推算标记。
    private func note(for snapshot: HeroStatsSnapshot) -> String {
        var parts: [String] = []
        if snapshot.isAnchorLevel {
            parts.append("参数锚点")
        } else {
            parts.append("插值")
        }
        if hasModifier, let tag = HeroStatsText.inferenceTag(level: snapshot.level, anchorLevels: modifierAnchorLevels) {
            parts.append("词条" + tag)
        }
        if !snapshot.clampedStats.isEmpty {
            parts.append("已钳位")
        }
        return parts.joined(separator: " · ")
    }
}

// MARK: - 同级对比表

/// 当前等级下 10 个角色的横向对比；点列头排序。
struct HeroCompareTable: View {
    let rows: [HeroComparisonRow]
    let statNames: HeroStatNames
    let column: HeroComparisonColumn
    let ascending: Bool
    let onSort: (HeroComparisonColumn) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: HeroTableMetrics.rowSpacing) {
            header
            Rectangle().fill(AppTheme.border).frame(height: 1)
            ForEach(rows) { row in
                self.row(row)
            }
        }
    }

    private func sortState(for target: HeroComparisonColumn) -> HeroHeaderCell.HeroSortState {
        guard target == column else { return .none }
        return ascending ? .ascending : .descending
    }

    private var header: some View {
        HStack(spacing: 6) {
            HeroHeaderCell(
                title: "角色",
                width: HeroTableMetrics.heroColumn,
                alignment: .leading,
                sortState: sortState(for: .hero),
                onTap: { onSort(.hero) }
            )
            ForEach(statNames.attributeKeys, id: \.self) { key in
                HeroHeaderCell(
                    title: statNames.attributeTitle(key),
                    width: HeroTableMetrics.statColumn,
                    sortState: sortState(for: .stat(key)),
                    onTap: { onSort(.stat(key)) }
                )
            }
            ForEach(statNames.derivedKeys, id: \.self) { key in
                HeroHeaderCell(
                    title: statNames.derivedTitle(key),
                    width: HeroTableMetrics.derivedColumn,
                    sortState: sortState(for: .derived(key)),
                    onTap: { onSort(.derived(key)) }
                )
            }
        }
    }

    private func row(_ row: HeroComparisonRow) -> some View {
        let best = extremes()
        return HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 1) {
                Text(row.nameZh.isEmpty ? row.nameEn : row.nameZh)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                Text(row.nameEn)
                    .font(.system(size: 9))
                    .foregroundStyle(AppTheme.tertiaryText)
            }
            .frame(width: HeroTableMetrics.heroColumn, alignment: .leading)

            ForEach(statNames.attributeKeys, id: \.self) { key in
                let value = Double(row.stats[key] ?? 0)
                HeroValueCell(
                    text: HeroFormat.value(value, integer: true),
                    width: HeroTableMetrics.statColumn,
                    tint: best[.stat(key)] == value ? AppTheme.green : .white,
                    weight: best[.stat(key)] == value ? .bold : .medium
                )
            }
            ForEach(statNames.derivedKeys, id: \.self) { key in
                let entry = statNames.derivedEntry(key)
                let value = row.derived[key] ?? 0
                HeroValueCell(
                    text: HeroFormat.value(value, integer: entry?.integer ?? true),
                    width: HeroTableMetrics.derivedColumn,
                    tint: best[.derived(key)] == value ? AppTheme.green : AppTheme.secondaryText,
                    weight: best[.derived(key)] == value ? .bold : .medium
                )
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
    }

    /// 每列的最大值，用来把该列的最高者标绿。
    private func extremes() -> [HeroComparisonColumn: Double] {
        var result: [HeroComparisonColumn: Double] = [:]
        for key in statNames.attributeKeys {
            let column = HeroComparisonColumn.stat(key)
            result[column] = rows.compactMap { $0.value(for: column) }.max()
        }
        for key in statNames.derivedKeys {
            let column = HeroComparisonColumn.derived(key)
            result[column] = rows.compactMap { $0.value(for: column) }.max()
        }
        return result
    }
}
