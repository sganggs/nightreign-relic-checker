import RelicCore
import SwiftUI

// 「增伤排名」配置页的遗物栏：3 或 6 张遗物卡。每张卡二选一——官方固定词条遗物整件选入，
// 或按词条检查页的规则自组 ≤ 3 条词条（深夜遗物需诅咒的词条要配一条诅咒）。

/// 遗物栏的选择弹窗要选什么。
enum RelicPickerTarget: Identifiable {
    case fixed(card: Int)
    case affix(card: Int, row: Int)
    case curse(card: Int, row: Int)

    var id: String {
        switch self {
        case .fixed(let card): return "fixed-\(card)"
        case .affix(let card, let row): return "affix-\(card)-\(row)"
        case .curse(let card, let row): return "curse-\(card)-\(row)"
        }
    }
}

struct BuffRankerRelicSection: View {
    @ObservedObject var model: BuffRankerModel
    @State private var picker: RelicPickerTarget?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeading(
                title: LoadoutColumn.relic.title,
                subtitle: LoadoutText.relicSubtitle,
                symbol: "diamond",
                tint: LoadoutPalette.column(.relic)
            )
            if let error = model.catalogError {
                Text(LoadoutText.relicCatalogMissing + "（\(error)）")
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.amber)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 340), spacing: 10, alignment: .top)], spacing: 10) {
                ForEach(Array(model.loadout.relicCards.enumerated()), id: \.offset) { item in
                    RelicCardView(model: model, cardIndex: item.offset, card: item.element, picker: $picker)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .appCard()
        .sheet(item: $picker) { target in
            RelicPickerSheet(model: model, target: target)
        }
    }
}

struct RelicCardView: View {
    @ObservedObject var model: BuffRankerModel
    let cardIndex: Int
    let card: LoadoutRelicCard
    @Binding var picker: RelicPickerTarget?

    private var check: LoadoutRelicCheck {
        model.evaluation.relicChecks.indices.contains(cardIndex) ? model.evaluation.relicChecks[cardIndex] : .empty
    }

    private var hasFixedOption: Bool {
        !card.isDeepSlot || (model.loadoutIndex?.fixedRelicItems.contains { $0.fixedRelic?.isDeepRelic == true } ?? false)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(LoadoutText.relicCardTitle(cardIndex + 1, deep: card.isDeepSlot))
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(card.isDeepSlot ? LoadoutPalette.badge(LoadoutText.badgeDeepOnly) : .white)
                Spacer(minLength: 0)
                Picker("", selection: choiceBinding) {
                    Text(LoadoutText.relicChoiceEmpty).tag(ChoiceKind.empty)
                    if hasFixedOption {
                        Text(LoadoutText.relicChoiceFixed).tag(ChoiceKind.fixed)
                    }
                    Text(LoadoutText.relicChoiceCustom).tag(ChoiceKind.custom)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: hasFixedOption ? 190 : 130)
            }
            if card.isDeepSlot && !hasFixedOption {
                Text(LoadoutText.relicNoDeepFixed)
                    .font(.system(size: 10))
                    .foregroundStyle(AppTheme.tertiaryText)
            }
            switch card.choice {
            case .empty:
                EmptyView()
            case .fixed(let fixedIndex):
                fixedBody(fixedIndex)
            case .custom:
                customBody
            }
            linesBody
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(card.isEmpty ? Color.white.opacity(0.02) : AppTheme.purple.opacity(0.07))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(borderColor, lineWidth: 1)
        )
    }

    private var borderColor: Color {
        switch check.status {
        case .invalid: return AppTheme.red.opacity(0.6)
        case .valid: return card.isEmpty ? AppTheme.border : AppTheme.purple.opacity(0.35)
        case .empty: return AppTheme.border
        }
    }

    private enum ChoiceKind: Hashable { case empty, fixed, custom }

    private var choiceBinding: Binding<ChoiceKind> {
        Binding(
            get: {
                switch card.choice {
                case .empty: return .empty
                case .fixed: return .fixed
                case .custom: return .custom
                }
            },
            set: { kind in
                switch kind {
                case .empty: model.setRelicChoice(cardIndex, .empty)
                case .custom: model.setRelicChoice(cardIndex, .custom)
                case .fixed:
                    if case .fixed = card.choice { return }
                    picker = .fixed(card: cardIndex)
                }
            }
        )
    }

    @ViewBuilder
    private func fixedBody(_ fixedIndex: Int) -> some View {
        if let item = model.loadoutIndex?.fixedRelicItem(fixedIndex) {
            VStack(alignment: .leading, spacing: 6) {
                Button {
                    picker = .fixed(card: cardIndex)
                } label: {
                    HStack(spacing: 6) {
                        Text(item.title)
                            .font(.system(size: 13, weight: .semibold))
                        Text(item.subtitle)
                            .font(.system(size: 10))
                            .foregroundStyle(AppTheme.tertiaryText)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 9))
                            .foregroundStyle(AppTheme.tertiaryText)
                    }
                }
                .buttonStyle(.plain)
                // 固定遗物里有同名词条（#1520 三条『出击时，会持有“星光碎片”』），按位置做 id。
                ForEach(Array(item.infoLines.enumerated()), id: \.offset) { _, info in
                    HStack(spacing: 6) {
                        Image(systemName: info.counted ? "checkmark.circle" : "minus.circle")
                            .font(.system(size: 10))
                            .foregroundStyle(info.counted ? AppTheme.green : AppTheme.tertiaryText)
                        Text(info.text)
                            .font(.system(size: 11))
                            .foregroundStyle(info.counted ? .white : AppTheme.tertiaryText)
                        if !info.counted {
                            Text(LoadoutText.relicNonDamage)
                                .font(.system(size: 10))
                                .foregroundStyle(AppTheme.tertiaryText)
                        }
                    }
                }
            }
        }
    }

    private var customBody: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(0..<3, id: \.self) { row in
                rowView(row)
            }
            statusView
        }
    }

    private func rowView(_ row: Int) -> some View {
        let affixID = card.rows[row].affixID
        let affix = affixID.flatMap { model.loadoutIndex?.catalogAffixes[$0] }
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(LoadoutText.relicRowLabel(row + 1))
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.tertiaryText)
                    .frame(width: 44, alignment: .leading)
                Button {
                    picker = .affix(card: cardIndex, row: row)
                } label: {
                    Text(affix?.name ?? (affixID.map { "#\($0)" } ?? LoadoutText.relicPickAffix))
                        .font(.system(size: 12, weight: affix == nil ? .regular : .semibold))
                        .foregroundStyle(affix == nil ? AppTheme.purpleSoft : .white)
                        .lineLimit(1)
                }
                .buttonStyle(.plain)
                .disabled(!(model.loadoutIndex?.hasCatalog ?? false))
                if affix?.requiresCurse == true {
                    Pill(text: LoadoutText.badgeRequiresCurse, color: LoadoutPalette.badge(LoadoutText.badgeRequiresCurse))
                }
                Spacer(minLength: 0)
                if affixID != nil {
                    Button {
                        model.setRelicAffix(cardIndex, row: row, affixID: nil)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(AppTheme.tertiaryText)
                    }
                    .buttonStyle(.plain)
                }
            }
            if card.isDeepSlot && (affix?.requiresCurse == true || card.rows[row].curseID != nil) {
                curseRow(row)
            }
        }
    }

    private func curseRow(_ row: Int) -> some View {
        let curseID = card.rows[row].curseID
        let curse = curseID.flatMap { model.loadoutIndex?.catalogAffixes[$0] }
        return HStack(spacing: 6) {
            Text(LoadoutText.relicCurseLabel)
                .font(.system(size: 11))
                .foregroundStyle(AppTheme.red.opacity(0.8))
                .frame(width: 44, alignment: .leading)
                .padding(.leading, 12)
            Button {
                picker = .curse(card: cardIndex, row: row)
            } label: {
                Text(curse?.name ?? LoadoutText.relicPickCurse)
                    .font(.system(size: 11))
                    .foregroundStyle(curse == nil ? AppTheme.amber : AppTheme.secondaryText)
                    .lineLimit(1)
            }
            .buttonStyle(.plain)
            Text(LoadoutText.relicCurseNote)
                .font(.system(size: 10))
                .foregroundStyle(AppTheme.tertiaryText)
            Spacer(minLength: 0)
            if curseID != nil {
                Button {
                    model.setRelicCurse(cardIndex, row: row, curseID: nil)
                } label: {
                    Image(systemName: "xmark.circle")
                        .foregroundStyle(AppTheme.tertiaryText)
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var statusView: some View {
        if check.status != .empty {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Image(systemName: check.status == .valid ? "checkmark.seal.fill" : "xmark.octagon.fill")
                        .foregroundStyle(check.status == .valid ? AppTheme.green : AppTheme.red)
                    Text(check.status == .valid ? LoadoutText.relicValidLabel : LoadoutText.relicInvalidLabel)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(check.status == .valid ? AppTheme.green : AppTheme.red)
                    Text(check.message)
                        .font(.system(size: 11))
                        .foregroundStyle(AppTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ForEach(check.issues) { issue in
                    Text("· \(issue.title)：\(issue.detail)")
                        .font(.system(size: 10))
                        .foregroundStyle(AppTheme.red.opacity(0.9))
                        .fixedSize(horizontal: false, vertical: true)
                }
                ForEach(check.warnings) { warning in
                    Text("· \(warning.title)：\(warning.detail)")
                        .font(.system(size: 10))
                        .foregroundStyle(AppTheme.tertiaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    @ViewBuilder
    private var linesBody: some View {
        let lines = model.lines(forRelicCard: cardIndex)
        if !lines.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(lines) { line in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(line.displayName)
                                .font(.system(size: 11))
                                .foregroundStyle(line.status.isCounted ? .white : AppTheme.tertiaryText)
                                .lineLimit(1)
                            Spacer(minLength: 4)
                            Text(line.status.isCounted ? BuffFormat.multiplier(line.multiplier) : line.statusText)
                                .font(.system(size: 10, design: line.status.isCounted ? .monospaced : .default))
                                .foregroundStyle(line.status.isCounted ? AppTheme.green : AppTheme.amber)
                                .lineLimit(1)
                        }
                        LoadoutLineControls(model: model, line: line, allowConfirm: true, siblings: lines)
                    }
                }
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.white.opacity(0.03)))
        }
    }
}

// MARK: - 选择弹窗

struct RelicPickerSheet: View {
    @ObservedObject var model: BuffRankerModel
    let target: RelicPickerTarget
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                LogoMark(size: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.title3.weight(.bold))
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                }
                Spacer()
                Button(LoadoutText.pickerDone) { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(18)
            .background(AppTheme.elevated)

            RankerSearchField(placeholder: placeholder, text: $query)
                .padding(.horizontal, 18)
                .padding(.vertical, 12)

            Divider().overlay(AppTheme.border)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 5) {
                    content
                }
                .padding(14)
            }
        }
        .frame(minWidth: 680, idealWidth: 780, minHeight: 560, idealHeight: 680)
        .background(AppTheme.background)
    }

    private var title: String {
        switch target {
        case .fixed(let card): return LoadoutText.relicCardTitle(card + 1, deep: isDeep(card)) + " · " + LoadoutText.relicChoiceFixed
        case .affix(let card, let row):
            return LoadoutText.relicCardTitle(card + 1, deep: isDeep(card)) + " · " + LoadoutText.relicRowLabel(row + 1)
        case .curse(let card, let row):
            return LoadoutText.relicCardTitle(card + 1, deep: isDeep(card)) + " · " + LoadoutText.relicRowLabel(row + 1)
                + " · " + LoadoutText.relicCurseLabel
        }
    }

    private var subtitle: String {
        switch target {
        case .fixed: return LoadoutText.relicSubtitle
        case .affix: return LoadoutText.relicAffixPickerSubtitle
        case .curse: return LoadoutText.relicCurseNote
        }
    }

    private var placeholder: String {
        switch target {
        case .fixed: return LoadoutText.relicFixedSearch
        case .affix: return LoadoutText.relicSearch
        case .curse: return LoadoutText.relicCurseSearch
        }
    }

    private func isDeep(_ card: Int) -> Bool {
        model.loadout.relicCards.indices.contains(card) && model.loadout.relicCards[card].isDeepSlot
    }

    @ViewBuilder
    private var content: some View {
        let needle = query.foldedForSearch
        switch target {
        case .fixed(let card):
            ForEach(model.fixedRelicChoices(cardIndex: card).filter { $0.item.matches(foldedQuery: needle) }) { candidate in
                fixedRow(candidate, card: card)
            }
        case .affix(let card, let row):
            ForEach(model.relicAffixChoices(cardIndex: card, row: row).filter { choice in
                choice.candidate.item.matches(foldedQuery: needle)
                    && (model.showInapplicable || choice.candidate.isUseful)
            }) { choice in
                affixRow(choice, card: card, row: row)
            }
        case .curse(let card, let row):
            ForEach(model.curseChoices(cardIndex: card, row: row).filter { needle.isEmpty || $0.affix.searchableText.contains(needle) }) { choice in
                curseRow(choice, card: card, row: row)
            }
        }
    }

    private func fixedRow(_ candidate: LoadoutCandidate, card: Int) -> some View {
        let fixedIndex: Int? = {
            if case .fixedRelic(let index) = candidate.item.kind { return index }
            return nil
        }()
        let used = fixedIndex.map { model.fixedRelicUsedElsewhere($0, cardIndex: card) } ?? false
        return Button {
            if let fixedIndex {
                model.setRelicChoice(card, .fixed(fixedIndex))
                dismiss()
            }
        } label: {
            pickRow(
                title: candidate.item.title,
                subtitle: candidate.item.subtitle + " · " + candidate.item.infoLines.map(\.text).joined(separator: "／"),
                multiplier: candidate.multiplier,
                potential: candidate.potential,
                potentialOneStack: candidate.potentialAssumesOneStack,
                warning: used ? LoadoutText.relicFixedUsedElsewhere : nil,
                dimmed: used
            )
        }
        .buttonStyle(.plain)
        .disabled(used)
    }

    private func affixRow(_ choice: RelicAffixChoice, card: Int, row: Int) -> some View {
        let affix = choice.candidate.item.relicAffix
        return Button {
            if let affix {
                model.setRelicAffix(card, row: row, affixID: affix.effectID)
                dismiss()
            }
        } label: {
            pickRow(
                title: choice.candidate.item.title,
                subtitle: [choice.candidate.item.subtitle, affix?.requiresCurse == true ? LoadoutText.badgeRequiresCurse : nil,
                           choice.candidate.isApplicable ? nil : (choice.candidate.blockedReason ?? LoadoutText.appliesNo)]
                    .compactMap { $0 }.joined(separator: " · "),
                multiplier: choice.candidate.multiplier,
                potential: choice.candidate.potential,
                potentialOneStack: choice.candidate.potentialAssumesOneStack,
                warning: choice.blockingIssue.map { "\($0.title)：\($0.detail)" },
                dimmed: !choice.candidate.isApplicable || choice.blockingIssue != nil
            )
        }
        .buttonStyle(.plain)
    }

    private func curseRow(_ choice: CurseChoice, card: Int, row: Int) -> some View {
        Button {
            model.setRelicCurse(card, row: row, curseID: choice.affix.effectID)
            dismiss()
        } label: {
            pickRow(
                title: choice.affix.name,
                subtitle: LoadoutText.relicCurseNote + " · #\(choice.affix.effectID)",
                multiplier: nil,
                potential: nil,
                warning: choice.blockingIssue.map { "\($0.title)：\($0.detail)" },
                dimmed: choice.blockingIssue != nil
            )
        }
        .buttonStyle(.plain)
    }

    private func pickRow(
        title: String, subtitle: String, multiplier: Double?, potential: Double?, potentialOneStack: Bool = false,
        warning: String?, dimmed: Bool
    ) -> some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(AppTheme.tertiaryText)
                        .lineLimit(2)
                }
                if let warning {
                    Text(warning)
                        .font(.system(size: 10))
                        .foregroundStyle(AppTheme.red.opacity(0.9))
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 8)
            if let multiplier {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(BuffFormat.multiplier(multiplier))
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(multiplier > 1.0000001 ? AppTheme.green : AppTheme.secondaryText)
                    if let potential, abs(potential - multiplier) > 0.0000001 {
                        Text(potentialOneStack ? LoadoutText.potentialTextOneStack(potential) : LoadoutText.potentialText(potential))
                            .font(.system(size: 10))
                            .foregroundStyle(AppTheme.amber)
                    }
                }
            }
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.white.opacity(0.03)))
        .contentShape(Rectangle())
        .opacity(dimmed ? 0.55 : 1)
    }
}
