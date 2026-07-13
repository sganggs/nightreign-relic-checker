import SwiftUI
import RelicCore

struct CheckerView: View {
    @EnvironmentObject private var model: AppModel
    @State private var pickingSlot: SlotTarget?

    private struct SlotTarget: Identifiable {
        let id: Int
    }

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 22) {
                    checkerHeader

                    LazyVGrid(columns: columns(for: proxy.size.width), alignment: .leading, spacing: 18) {
                        selectionCard
                        resultCard
                        popularCard
                    }

                    rulesCard
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 26)
                .frame(maxWidth: 1440)
                .frame(maxWidth: .infinity)
            }
        }
        .sheet(item: $pickingSlot) { target in
            AffixPickerSheet(slot: target.id)
                .environmentObject(model)
        }
    }

    private var checkerHeader: some View {
        VStack(spacing: 10) {
            HStack(spacing: 13) {
                LogoMark(size: 42)
                Text("黑夜君临遗物词条合法性检查")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
            }
            Text("基于游戏参数的非零出货权重、互斥池与保存顺序，所有判断均在本机完成")
                .font(.system(size: 14))
                .foregroundStyle(AppTheme.secondaryText)
            HStack(spacing: 8) {
                Pill(text: model.catalogSummary, color: AppTheme.purpleSoft, symbol: "books.vertical")
                Pill(text: "颜色不影响随机词条池", color: AppTheme.green, symbol: "paintpalette")
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 3)
    }

    private var selectionCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            SectionHeading(
                title: "词条选择",
                subtitle: "按遗物画面从上到下依次填入三条效果",
                symbol: "magnifyingglass"
            )

            VStack(alignment: .leading, spacing: 8) {
                Text("校验口径")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.secondaryText)
                Picker("校验口径", selection: $model.mode) {
                    ForEach(CheckMode.allCases) { mode in
                        Text(mode.shortTitle).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                Text(model.mode.detail)
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 12) {
                ForEach(0..<3, id: \.self) { slot in
                    AffixSlotRow(
                        slot: slot,
                        affix: model.affix(at: slot),
                        choose: { pickingSlot = SlotTarget(id: slot) },
                        clear: { model.remove(slot: slot) }
                    )
                }
            }

            HStack(spacing: 10) {
                Button(action: model.checkSelection) {
                    Label("检查合法性", systemImage: "checkmark.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle())

                Button(action: model.randomize) {
                    Label("随机获取", systemImage: "shuffle")
                }
                .buttonStyle(SecondaryButtonStyle())
            }

            Button("清空三个词条", role: .destructive, action: model.clearSelection)
                .font(.caption)
                .buttonStyle(.plain)
                .foregroundStyle(AppTheme.secondaryText)
                .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, minHeight: 510, maxHeight: 510, alignment: .top)
        .appCard()
    }

    private var resultCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            SectionHeading(
                title: "检查结果",
                subtitle: "错误组合会标明原因；顺序错误可一键纠正",
                symbol: resultSymbol,
                tint: resultTint
            )

            if let result = model.result {
                ResultBanner(result: result)

                if !result.issues.isEmpty {
                    VStack(spacing: 9) {
                        ForEach(result.issues) { issue in
                            IssueRow(issue: issue, warning: false)
                        }
                    }
                }

                if !result.warnings.isEmpty {
                    VStack(spacing: 9) {
                        ForEach(result.warnings) { issue in
                            IssueRow(issue: issue, warning: true)
                        }
                    }
                }

                if !result.orderedAffixes.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text(result.status == .wrongOrder ? "正确的词条顺序" : "规范顺序")
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            Text("sortId → effectId")
                                .font(.caption2.monospaced())
                                .foregroundStyle(AppTheme.tertiaryText)
                        }
                        ForEach(Array(result.orderedAffixes.enumerated()), id: \.element.effectID) { index, affix in
                            OrderedAffixRow(index: index, affix: affix)
                        }
                    }
                }

                if result.status == .wrongOrder {
                    Button(action: model.applyCanonicalOrder) {
                        Label("按正确顺序重新排列", systemImage: "arrow.up.arrow.down")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PrimaryButtonStyle())
                }
            } else {
                VStack(spacing: 15) {
                    Image(systemName: "checkmark.seal")
                        .font(.system(size: 44, weight: .light))
                        .foregroundStyle(AppTheme.purpleSoft.opacity(0.75))
                    Text("等待检查")
                        .font(.title3.weight(.semibold))
                    Text("选择三个词条后，应用会依次核对出货池、重复效果、compatibilityId 互斥池，以及最终保存顺序。")
                        .font(.callout)
                        .foregroundStyle(AppTheme.secondaryText)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.vertical, 42)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 510, maxHeight: 510, alignment: .top)
        .appCard()
    }

    private var popularCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeading(
                title: "热门词条",
                subtitle: "点击即可填入第一个空卡槽",
                symbol: "chart.line.uptrend.xyaxis",
                tint: AppTheme.red
            )

            ScrollView {
                LazyVStack(spacing: 9) {
                    ForEach(model.popularAffixes) { affix in
                        Button { model.fillNext(with: affix) } label: {
                            HStack(alignment: .top, spacing: 9) {
                                Image(systemName: "sparkles")
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.purpleSoft)
                                    .padding(.top, 2)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(affix.name)
                                        .font(.system(size: 12, weight: .medium))
                                        .multilineTextAlignment(.leading)
                                    HStack(spacing: 7) {
                                        Text(affix.category)
                                        if let popularity = affix.popularity {
                                            Text("查询 \(popularity.formatted())")
                                        }
                                    }
                                    .font(.caption2)
                                    .foregroundStyle(AppTheme.secondaryText)
                                }
                                Spacer(minLength: 4)
                                Image(systemName: "plus.circle.fill")
                                    .foregroundStyle(AppTheme.purpleSoft)
                            }
                            .padding(10)
                            .background(AppTheme.field, in: RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(AppTheme.border, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 510, maxHeight: 510, alignment: .top)
        .appCard()
    }

    private var rulesCard: some View {
        HStack(alignment: .top, spacing: 30) {
            SectionHeading(
                title: "判定口径",
                subtitle: "当前版本按游戏真实参数重建，不依赖已失效的在线 API。",
                symbol: "info.circle"
            )
            Spacer(minLength: 10)
            VStack(alignment: .leading, spacing: 7) {
                Label("三条效果必须来自所选版本的非零权重池", systemImage: "checkmark")
                Label("effectId 不能重复，compatibilityId（-1 除外）不能重复", systemImage: "checkmark")
                Label("最终顺序按 (overrideEffectId, effectId) 升序", systemImage: "checkmark")
            }
            .font(.caption)
            .foregroundStyle(AppTheme.secondaryText)
        }
        .appCard(padding: 18)
    }

    private var resultSymbol: String {
        guard let status = model.result?.status else { return "checkmark.seal" }
        switch status {
        case .incomplete: return "ellipsis.circle"
        case .valid: return "checkmark.circle.fill"
        case .wrongOrder: return "arrow.up.arrow.down.circle.fill"
        case .invalid: return "xmark.octagon.fill"
        }
    }

    private var resultTint: Color {
        guard let status = model.result?.status else { return AppTheme.purpleSoft }
        switch status {
        case .incomplete: return AppTheme.secondaryText
        case .valid: return AppTheme.green
        case .wrongOrder: return AppTheme.amber
        case .invalid: return AppTheme.red
        }
    }

    private func columns(for width: CGFloat) -> [GridItem] {
        if width >= 1180 {
            return [
                GridItem(.flexible(minimum: 340), spacing: 18),
                GridItem(.flexible(minimum: 340), spacing: 18),
                GridItem(.flexible(minimum: 270, maximum: 320), spacing: 18)
            ]
        }
        if width >= 780 {
            return [
                GridItem(.flexible(minimum: 340), spacing: 18),
                GridItem(.flexible(minimum: 340), spacing: 18)
            ]
        }
        return [GridItem(.flexible())]
    }
}

private struct AffixSlotRow: View {
    let slot: Int
    let affix: Affix?
    let choose: () -> Void
    let clear: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("词条 \(slot + 1)")
                    .font(.caption.weight(.semibold))
                if let affix {
                    Text("ID " + String(affix.effectID))
                        .font(.caption2.monospaced())
                        .foregroundStyle(AppTheme.tertiaryText)
                }
                Spacer()
                if affix != nil {
                    Button(action: clear) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(AppTheme.secondaryText)
                    }
                    .buttonStyle(.plain)
                }
            }

            Button(action: choose) {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 7) {
                            Text(affix?.name ?? "选择词条 \(slot + 1)")
                                .foregroundStyle(affix == nil ? AppTheme.secondaryText : Color.white)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                            if let affix, affix.requiresCurse {
                                Pill(text: "需诅咒", color: AppTheme.amber)
                            }
                        }
                        if let affix {
                            Text(affix.category + " · 互斥池 " + String(affix.compatibilityID) + " · 排序 " + String(affix.sortID))
                                .font(.caption2)
                                .foregroundStyle(AppTheme.secondaryText)
                        }
                    }
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                }
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(AppTheme.field, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(AppTheme.borderStrong, lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
    }
}

private struct ResultBanner: View {
    let result: CheckResult

    private var tint: Color {
        switch result.status {
        case .incomplete: return AppTheme.secondaryText
        case .valid: return AppTheme.green
        case .wrongOrder: return AppTheme.amber
        case .invalid: return AppTheme.red
        }
    }

    private var symbol: String {
        switch result.status {
        case .incomplete: return "ellipsis"
        case .valid: return "checkmark"
        case .wrongOrder: return "arrow.up.arrow.down"
        case .invalid: return "xmark"
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .black))
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)
                .background(tint.opacity(0.13), in: Circle())
            Text(result.message)
                .font(.subheadline.weight(.semibold))
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 11))
        .overlay(RoundedRectangle(cornerRadius: 11).stroke(tint.opacity(0.32), lineWidth: 1))
    }
}

private struct IssueRow: View {
    let issue: CheckIssue
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
        .background(AppTheme.field.opacity(0.75), in: RoundedRectangle(cornerRadius: 9))
    }
}

private struct OrderedAffixRow: View {
    let index: Int
    let affix: Affix

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(index + 1)")
                .font(.caption.monospacedDigit().weight(.bold))
                .foregroundStyle(AppTheme.purpleSoft)
                .frame(width: 24, height: 24)
                .background(AppTheme.purple.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 3) {
                Text(affix.name)
                    .font(.caption.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Text(String(affix.sortID) + " → " + String(affix.effectID))
                    .font(.caption2.monospaced())
                    .foregroundStyle(AppTheme.tertiaryText)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(AppTheme.purple.opacity(0.06), in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(AppTheme.purple.opacity(0.18), lineWidth: 1))
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .padding(.horizontal, 14)
            .frame(minHeight: 38)
            .foregroundStyle(.white)
            .background(
                LinearGradient(
                    colors: [AppTheme.purpleSoft, AppTheme.purple],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 9)
            )
            .opacity(configuration.isPressed ? 0.76 : 1)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .padding(.horizontal, 13)
            .frame(minHeight: 38)
            .foregroundStyle(.white)
            .background(AppTheme.field, in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(AppTheme.borderStrong, lineWidth: 1))
            .opacity(configuration.isPressed ? 0.72 : 1)
    }
}
