import SwiftUI
import RelicCore

// 「角色属性」页的两张表：全部等级表（1 … 数据集声明的最大等级）与同级对比表。
// 纯展示，所有数值都由 RelicCore 的 HeroStatsIndex 算好后传进来。
//
// 两张表的缺数据一律是破折号（HeroStatsText.statText / derivedText），**不要**退回 0：
// 0 是真实数值，破折号才是「没有」—— 全部等级表之前是这三张表里唯一写 0 的。
//
// 「负重上限」是《艾尔登法环》继承下来的遗留列（本作装备没有重量），两张表的列头
// 都带 `*` 注记、表下都有同一条脚注 —— 单等级卡片上有小字提示，表格里没有地方写，
// 之前只有卡片提到这件事，表格里的数字看着就像实测值。

enum HeroTableMetrics {
    static let levelColumn: CGFloat = 54
    static let statColumn: CGFloat = 62         // 三位数 + 逐格的「钳」角标（8.5pt）也放得下
    static let derivedColumn: CGFloat = 74      // 「负重上限 *」比原来多一个注记符

    /// 列头文案：遗留列（没有游戏内 UI 标签的派生值，当前只有负重上限）带 `*`。
    static func derivedHeader(_ key: String, names: HeroStatNames) -> String {
        let title = names.derivedTitle(key)
        guard let entry = names.derivedEntry(key), !entry.inGameLabel else { return title }
        return HeroStatsCopy.legacyHeader(title)
    }

    /// 表下的脚注：只在表里真有遗留列时才写。
    static func legacyFootnote(_ names: HeroStatNames) -> String? {
        let hasLegacy = names.derivedKeys.contains { names.derivedEntry($0)?.inGameLabel == false }
        return hasLegacy ? HeroStatsCopy.equipLoadFootnote : nil
    }
    /// 「说明」列最长的一条是「参数锚点 · 词条沿用 12 级锚点 · 已钳位」
    /// （10pt 系统字实测 173.8pt，出现在「利普拉 + 转职遗物」把属性减到下限的 15 级行），
    /// 留到 186 才不会把结尾的「已钳位」吃掉。
    static let noteColumn: CGFloat = 186
    static let heroColumn: CGFloat = 118
    static let rowSpacing: CGFloat = 3
}

// MARK: - 全部等级表

/// 1 … 数据集声明的最大等级的完整表；锚点行（由数据集的 baseAnchorLevels 决定）高亮。
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
                HeroHeaderCell(
                    title: HeroTableMetrics.derivedHeader(key, names: statNames),
                    width: HeroTableMetrics.derivedColumn
                )
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
                // 缺这一项属性时给破折号，不要退回 0（与同级对比表、单等级卡片同一条）
                let base = snapshot.baseStats[key].map(Double.init)
                let final = snapshot.finalStats[key].map(Double.init)
                let changed = base != nil && final != nil && base != final
                let clampedFrom = snapshot.clampedFrom[key]
                HStack(spacing: 3) {
                    Spacer(minLength: 0)
                    Text(HeroStatsText.statText(snapshot.finalStats[key]))
                        .font(.system(size: 12, weight: changed ? .bold : .medium, design: .rounded))
                        .foregroundStyle(changed ? HeroFormat.deltaColor((final ?? 0) - (base ?? 0)) : .white)
                        .lineLimit(1)
                    // 逐格的「钳」角标：这一行哪一格被钳、钳位前是多少，鼠标停上去看得到
                    // （Windows 端表里是同一个角标 + 同一句 title）。
                    if clampedFrom != nil {
                        Text(HeroStatsCopy.clampCellTag)
                            .font(.system(size: 8.5, weight: .bold))
                            .foregroundStyle(AppTheme.red)
                    }
                }
                .frame(width: HeroTableMetrics.statColumn, alignment: .trailing)
                .help(cellHelp(base: base, final: final, changed: changed, clampedFrom: clampedFrom))
            }

            ForEach(statNames.derivedKeys, id: \.self) { key in
                let entry = statNames.derivedEntry(key)
                let integer = entry?.integer ?? true
                // 缺 growthGraph / 缺来源属性时是 nil，显示破折号而不是 0
                let base = snapshot.baseDerived[key]
                let final = snapshot.finalDerived[key]
                let changed = base != nil && final != nil && base != final
                HeroValueCell(
                    text: HeroFormat.value(final, integer: integer),
                    width: HeroTableMetrics.derivedColumn,
                    tint: changed ? HeroFormat.deltaColor((final ?? 0) - (base ?? 0)) : AppTheme.secondaryText,
                    weight: changed ? .bold : .medium
                )
                .help(changed
                      ? "基础 \(HeroFormat.value(base, integer: integer)) → \(HeroFormat.value(final, integer: integer))"
                      : "")
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

    /// 属性格子的 tooltip：被钳的格子写「原为 N，已钳到最低 1」（比「基础 9 → 1」多说了
    /// 一件事：这一格是被钳的，原值是多少），其余变动的格子写「基础 x → y」。
    /// 与 Windows 端表格里 `title=clampedFromNote(raw)` 逐字一致。
    private func cellHelp(base: Double?, final: Double?, changed: Bool, clampedFrom: Int?) -> String {
        if let clampedFrom { return HeroStatsCopy.clampedFromNote(clampedFrom) }
        guard changed, let base, let final else { return "" }
        return "基础 \(Int(base)) → \(Int(final))"
    }

    /// 备注列：基础表是否锚点 + 勾了词条时的增减量来源标记 + 是否钳位。
    /// 两端逐字一致（Windows 端同名的三个 pill 用同一串文案）。
    private func note(for snapshot: HeroStatsSnapshot) -> String {
        var parts: [String] = []
        parts.append(snapshot.isAnchorLevel ? HeroStatsCopy.baseAnchorTag : HeroStatsCopy.baseInterpolatedTag)
        if hasModifier,
           let tag = HeroStatsText.modifierSource(level: snapshot.level, anchorLevels: modifierAnchorLevels) {
            parts.append(tag.label)
        }
        if !snapshot.clampedStats.isEmpty {
            parts.append(HeroStatsCopy.clampRowTag)
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
                    title: HeroTableMetrics.derivedHeader(key, names: statNames),
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
                let value = row.stats[key].map(Double.init)
                HeroValueCell(
                    text: HeroStatsText.statText(row.stats[key]),
                    width: HeroTableMetrics.statColumn,
                    tint: value != nil && best[.stat(key)] == value ? AppTheme.green : .white,
                    weight: value != nil && best[.stat(key)] == value ? .bold : .medium
                )
            }
            ForEach(statNames.derivedKeys, id: \.self) { key in
                let entry = statNames.derivedEntry(key)
                let value = row.derived[key]
                HeroValueCell(
                    text: HeroFormat.value(value, integer: entry?.integer ?? true),
                    width: HeroTableMetrics.derivedColumn,
                    tint: value != nil && best[.derived(key)] == value ? AppTheme.green : AppTheme.secondaryText,
                    weight: value != nil && best[.derived(key)] == value ? .bold : .medium
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
