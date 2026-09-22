import SwiftUI
import RelicCore

/// 单件遗物的详情卡（存档检查页 / 存档对比共用）。
struct SaveRelicCard: View {
    let relic: SaveScanReport.AuditedRelic
    let report: SaveScanReport
    /// 对比列表里用来显示「×2」这类数量。
    var quantity: Int = 1

    private var statusText: String { relic.statusLabel }

    private var statusColor: Color {
        if relic.result.status == .invalid { return AppTheme.red }
        return relic.result.warnings.isEmpty ? AppTheme.green : AppTheme.amber
    }

    private var statusSymbol: String {
        if relic.result.status == .invalid { return "xmark.octagon.fill" }
        return relic.result.warnings.isEmpty ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
    }

    private var colorPill: (text: String, color: Color)? {
        guard let info = relic.info else { return nil }
        // 「红色」而不是「红」：与遗物卡 / 报告 / CSV 同一份颜色文案。
        let label = relic.colorText
        switch info.color {
        case 0: return (label, AppTheme.red)
        case 1: return (label, Color(red: 0.38, green: 0.60, blue: 0.98))
        case 2: return (label, AppTheme.amber)
        case 3: return (label, AppTheme.green)
        case 4: return (label, Color.white.opacity(0.72))
        default: return (label, AppTheme.secondaryText)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .top, spacing: 8) {
                Text(relic.displayName)
                    .font(.subheadline.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                if quantity > 1 {
                    Pill(text: "×\(quantity)", color: AppTheme.purpleSoft)
                }
                Spacer(minLength: 4)
                Pill(text: statusText, color: statusColor, symbol: statusSymbol)
            }

            HStack(spacing: 6) {
                Pill(text: relic.kindLabel, color: AppTheme.purpleSoft)
                if let colorPill {
                    Pill(text: colorPill.text, color: colorPill.color)
                }
                if relic.isDeep {
                    Pill(text: "深夜", color: AppTheme.purple, symbol: "moon.stars")
                }
                Text("ID \(relic.relic.itemID)")
                    .font(.caption2.monospaced())
                    .foregroundStyle(AppTheme.tertiaryText)
                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: 6) {
                ForEach(0..<3, id: \.self) { row in
                    if effect(row) != -1 || curse(row) != -1 {
                        SaveAffixRow(report: report, effect: effect(row), curse: curse(row))
                    }
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppTheme.field.opacity(0.6), in: RoundedRectangle(cornerRadius: 9))

            ForEach(relic.result.issues) { issue in
                SaveIssueRow(issue: issue, warning: false)
            }
            ForEach(relic.result.warnings) { issue in
                SaveIssueRow(issue: issue, warning: true)
            }

            // 「官方固定词条」在前、「正确的词条顺序」在后：与导出报告
            // （SaveReportBuilder.relicLines）和 Windows 端的遗物卡同一顺序，
            // 三处都是先给「原样长什么样」，再给「顺序该怎么排」。
            if let official = relic.result.officialEffects {
                VStack(alignment: .leading, spacing: 4) {
                    Text("该遗物的官方固定词条（可据此改回）")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(AppTheme.purpleSoft)
                    ForEach(Array(official.filter { $0 != -1 }.enumerated()), id: \.offset) { index, effectID in
                        Text("\(index + 1). \(report.affixName(effectID)) (\(effectID))")
                            .font(.system(size: 12))
                            .foregroundStyle(AppTheme.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AppTheme.purple.opacity(0.06), in: RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(AppTheme.purple.opacity(0.18), lineWidth: 1))
            }

            if let ordered = relic.result.orderedEffects {
                VStack(alignment: .leading, spacing: 4) {
                    Text("正确的词条顺序")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(AppTheme.purpleSoft)
                    ForEach(Array(ordered.enumerated()), id: \.offset) { index, effectID in
                        Text("\(index + 1). " + (effectID == -1 ? "（空）" : report.affixName(effectID)))
                            .font(.caption)
                            .foregroundStyle(AppTheme.secondaryText)
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AppTheme.purple.opacity(0.06), in: RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(AppTheme.purple.opacity(0.18), lineWidth: 1))
            }
        }
        .appCard(padding: 14)
    }

    private func effect(_ row: Int) -> Int {
        relic.relic.effects.indices.contains(row) ? relic.relic.effects[row] : -1
    }

    private func curse(_ row: Int) -> Int {
        relic.relic.curses.indices.contains(row) ? relic.relic.curses[row] : -1
    }
}

/// 一行词条：正面词条 ｜ 同一行的负面词条。
///
/// 展示方式与 Windows 端一致：词条库里有说明（`explanation`）的词条，名字后面
/// 跟一个 ⓘ——悬停看浮层，点开在行下展开这一条的全文；没有说明的词条不显示
/// 入口，也不占位。展开状态按「哪一条词条」单独记，点开正面词条不会把同一行
/// 的诅咒一起撑开。
private struct SaveAffixRow: View {
    let report: SaveScanReport
    let effect: Int
    let curse: Int

    /// 本行展开了说明的词条 ID（正面 / 诅咒各自独立）。
    @State private var expanded: Set<Int> = []

    private static let curseText = Color(red: 0.55, green: 0.64, blue: 0.82)

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .top, spacing: 0) {
                affixText(effect, isCurse: false)
                if curse != -1 {
                    Text("｜")
                        .font(.system(size: 12))
                        .foregroundStyle(Self.curseText)
                    affixText(curse, isCurse: true)
                }
                Spacer(minLength: 6)
            }

            ForEach(expandedNotes, id: \.id) { note in
                Text(note.text)
                    .font(.caption2)
                    .foregroundStyle(AppTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AppTheme.purple.opacity(0.07), in: RoundedRectangle(cornerRadius: 7))
            }
        }
    }

    /// 已展开的说明，按「正面在前、诅咒在后」的行内顺序。
    private var expandedNotes: [(id: Int, text: String)] {
        [effect, curse]
            .filter { $0 != -1 && expanded.contains($0) }
            .compactMap { id in report.affixExplanation(id).map { (id: id, text: $0) } }
    }

    @ViewBuilder
    private func affixText(_ id: Int, isCurse: Bool) -> some View {
        let name = id == -1 ? "（空）" : report.affixName(id)
        HStack(alignment: .firstTextBaseline, spacing: 2) {
            Text(name)
                .font(.system(size: 12))
                .foregroundStyle(isCurse ? Self.curseText : Color.primary)
                .fixedSize(horizontal: false, vertical: true)
            if id != -1, let explanation = report.affixExplanation(id) {
                Button {
                    withAnimation(.easeOut(duration: 0.14)) {
                        if expanded.contains(id) { expanded.remove(id) } else { expanded.insert(id) }
                    }
                } label: {
                    Image(systemName: expanded.contains(id) ? "info.circle.fill" : "info.circle")
                        .font(.system(size: 11))
                        .foregroundStyle(AppTheme.purpleSoft.opacity(expanded.contains(id) ? 1 : 0.7))
                }
                .buttonStyle(.plain)
                .help(explanation)
                .accessibilityLabel("\(name) 的词条说明")
            }
        }
    }
}

struct SaveIssueRow: View {
    let issue: RelicAuditIssue
    let warning: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: warning ? "exclamationmark.triangle.fill" : "xmark.circle.fill")
                .foregroundStyle(warning ? AppTheme.amber : AppTheme.red)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 3) {
                Text(issue.title).font(.caption.weight(.bold))
                Text(issue.detail)
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.field.opacity(0.75), in: RoundedRectangle(cornerRadius: 9))
    }
}
