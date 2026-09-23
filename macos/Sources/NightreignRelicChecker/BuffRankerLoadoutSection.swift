import RelicCore
import SwiftUI

// 「增伤排名」配置页：汇总面板、局内武器词条栏、护符栏、其它增益栏，以及共用的候选行与条件控件。
// 文案全部取自 RelicCore 的 `LoadoutText`（两端对照用的常量表）。

// MARK: - 配色

enum LoadoutPalette {
    static func column(_ column: LoadoutColumn) -> Color {
        switch column {
        case .weaponAffix: return Color(red: 0.42, green: 0.72, blue: 0.95)
        case .relic: return AppTheme.purpleSoft
        case .accessory: return Color(red: 0.95, green: 0.62, blue: 0.85)
        case .consumable: return AppTheme.green
        case .spellBuff: return Color(red: 0.55, green: 0.78, blue: 0.99)
        case .weaponSkill: return Color(red: 0.99, green: 0.78, blue: 0.45)
        case .weaponInnate: return Color(red: 0.62, green: 0.86, blue: 0.80)
        case .character: return AppTheme.amber
        case .permanent: return Color(red: 0.75, green: 0.85, blue: 0.55)
        case .runStack: return Color(red: 0.90, green: 0.55, blue: 0.40)
        case .other: return AppTheme.secondaryText
        }
    }

    static func verdict(_ verdict: LoadoutVerdict) -> Color {
        if !verdict.isApplicable { return AppTheme.red.opacity(0.85) }
        if verdict.isPartial || verdict.value == .conditional || verdict.needsConfirmation { return AppTheme.amber }
        return AppTheme.green
    }

    static func badge(_ text: String) -> Color {
        switch text {
        case LoadoutText.badgeDeepOnly, LoadoutText.modeDeep: return Color(red: 0.55, green: 0.60, blue: 0.99)
        case LoadoutText.badgeCurse, LoadoutText.badgeRequiresCurse: return AppTheme.red.opacity(0.85)
        case LoadoutText.badgeBlessing: return Color(red: 0.99, green: 0.85, blue: 0.45)
        case LoadoutText.badgeAutoInnate, LoadoutText.badgeCurrentSkill: return AppTheme.green
        case LoadoutText.badgeConditional, LoadoutText.badgeActivated, LoadoutText.badgeStack, LoadoutText.badgeLadder,
             LoadoutText.badgeOutsideWeaponType, LoadoutText.badgeInferredTiers:
            return AppTheme.amber
        default: return AppTheme.secondaryText
        }
    }
}

// MARK: - 汇总面板

struct BuffRankerSummarySection: View {
    @ObservedObject var model: BuffRankerModel
    @State private var showUncounted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeading(title: LoadoutText.summaryTitle, subtitle: LoadoutText.summarySubtitle, symbol: "sum")

            controls
            totalRow
            toggles
            if !model.contextOptions.isEmpty { contexts }
            subtotals
            messages
            countedList
            uncountedList
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .appCard()
    }

    private var controls: some View {
        HStack(spacing: 12) {
            Text(LoadoutText.modeLabel)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppTheme.secondaryText)
            Picker(LoadoutText.modeLabel, selection: Binding(
                get: { model.loadout.mode },
                set: { model.setMode($0) }
            )) {
                ForEach(LoadoutMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 150)
            .help(model.slotRules.modesZh.isEmpty ? LoadoutText.modeHelp : model.slotRules.modesZh)

            Spacer(minLength: 0)

            Button {
                model.fillRecommended()
            } label: {
                Label(LoadoutText.fillButton, systemImage: "wand.and.stars")
                    .font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(.borderedProminent)
            .tint(AppTheme.purple)
            .help(LoadoutText.fillHelp)

            Button(LoadoutText.clearButton) { model.clearLoadout() }
                .buttonStyle(.bordered)
                .font(.system(size: 12))
        }
    }

    private var totalRow: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(LoadoutText.totalLabel)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppTheme.tertiaryText)
                Text(BuffFormat.multiplier(model.evaluation.total, digits: 3))
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(model.evaluation.total > 1.0000001 ? AppTheme.green : AppTheme.secondaryText)
                Text(LoadoutText.totalGain(model.evaluation.total))
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.tertiaryText)
            }
            Divider().frame(height: 48).overlay(AppTheme.border)
            RankerWrap(spacing: 6, lineSpacing: 6) {
                usagePill(LoadoutText.usageWeaponAffix, model.evaluation.weaponAffixUsage)
                if model.loadout.mode == .deep {
                    usagePill(LoadoutText.usageDeepOnly, model.evaluation.deepOnlyUsage)
                    if model.evaluation.curseUsage.used > 0 {
                        usagePill(LoadoutText.usageCurse, model.evaluation.curseUsage)
                    }
                }
                usagePill(LoadoutText.usageRelic, model.evaluation.relicUsage)
                usagePill(LoadoutText.usageAccessory, model.evaluation.accessoryUsage)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func usagePill(_ title: String, _ usage: LoadoutSlotUsage) -> some View {
        Pill(
            text: "\(title) \(usage.text)",
            color: usage.isOver ? AppTheme.red : (usage.used >= usage.cap && usage.cap > 0 ? AppTheme.green : AppTheme.secondaryText)
        )
    }

    private var toggles: some View {
        HStack(spacing: 16) {
            Toggle(LoadoutText.showInapplicable, isOn: $model.showInapplicable)
                .toggleStyle(.switch)
                .font(.caption)
                .help(LoadoutText.showInapplicableHelp)
            Toggle(LoadoutText.stackSelfToggle, isOn: Binding(
                get: { model.loadout.stackSelfCopiesMultiply },
                set: { model.setStackSelfMultiply($0) }
            ))
            .toggleStyle(.switch)
            .font(.caption)
            .help(LoadoutText.stackSelfHelp)
            Spacer(minLength: 0)
            Text(model.deliveryLabel)
                .font(.system(size: 11))
                .foregroundStyle(AppTheme.secondaryText)
        }
    }

    private var contexts: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(LoadoutText.attackContextsLabel)
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.tertiaryText)
                RankerWrap(spacing: 6, lineSpacing: 5) {
                    ForEach(model.contextOptions) { option in
                        RankerFilterChip(
                            text: "\(option.zh) \(option.count)",
                            isOn: model.includedAttackContexts.contains(option.key),
                            color: AppTheme.amber
                        ) {
                            model.toggleAttackContext(option.key)
                        }
                    }
                }
            }
            Text(LoadoutText.attackContextsNote)
                .font(.system(size: 10))
                .foregroundStyle(AppTheme.tertiaryText)
        }
    }

    @ViewBuilder
    private var subtotals: some View {
        let columns = LoadoutColumn.allCases.filter { model.evaluation.columnSubtotals[$0] != nil }
        if !columns.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text(LoadoutText.subtotalsLabel)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(AppTheme.tertiaryText)
                RankerWrap(spacing: 6, lineSpacing: 5) {
                    ForEach(columns) { column in
                        Pill(
                            text: column.title + " " + BuffFormat.multiplier(model.evaluation.columnSubtotals[column] ?? 1),
                            color: LoadoutPalette.column(column)
                        )
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var messages: some View {
        let evaluation = model.evaluation
        if model.modeNotice != nil || !evaluation.violations.isEmpty || !evaluation.warnings.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                if let notice = model.modeNotice {
                    messageLine(notice, color: AppTheme.amber, symbol: "arrow.uturn.backward.circle")
                }
                ForEach(evaluation.violations, id: \.self) { text in
                    messageLine(text, color: AppTheme.red, symbol: "xmark.octagon")
                }
                ForEach(evaluation.warnings, id: \.self) { text in
                    messageLine(text, color: AppTheme.amber, symbol: "exclamationmark.triangle")
                }
            }
        }
    }

    private func messageLine(_ text: String, color: Color, symbol: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 11))
                .foregroundStyle(color)
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(color)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var countedList: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(LoadoutText.countedTitle + "（\(model.evaluation.countedLines.count)）")
                .font(.system(size: 12, weight: .semibold))
            if model.evaluation.countedLines.isEmpty {
                Text(LoadoutText.countedEmpty)
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.tertiaryText)
            } else {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(model.evaluation.countedLines) { line in
                        LoadoutSummaryLineRow(model: model, line: line)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var uncountedList: some View {
        // 累积阶梯没选中的各档只留一行（放选档控件），其余档不重复列出。
        let lines = model.evaluation.lines
        let uncounted = lines.filter { line in
            guard !line.status.isCounted else { return false }
            guard line.status == .tierNotSelected, let ladder = model.buff(line)?.accumulatorLadder else { return true }
            return LoadoutLineControls.ownsLadderPicker(line, ladder: ladder, siblings: lines, model: model)
        }
        if !uncounted.isEmpty {
            RankerDisclosure(title: LoadoutText.uncountedTitle(uncounted.count), isOn: $showUncounted) {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(uncounted) { line in
                        LoadoutSummaryLineRow(model: model, line: line)
                    }
                }
            }
        }
    }
}

/// 汇总面板里的一条：名称、来源、状态、贡献倍率与条件控件。
struct LoadoutSummaryLineRow: View {
    @ObservedObject var model: BuffRankerModel
    let line: LoadoutLine

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center, spacing: 8) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(LoadoutPalette.column(line.column))
                    .frame(width: 4, height: 26)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(line.displayName)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(line.status.isCounted ? .white : AppTheme.secondaryText)
                        Pill(text: line.column.title, color: LoadoutPalette.column(line.column))
                    }
                    Text(line.sources.joined(separator: "、") + " · " + line.statusText)
                        .font(.system(size: 10))
                        .foregroundStyle(line.status.isCounted ? AppTheme.tertiaryText : AppTheme.amber)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 6)
                VStack(alignment: .trailing, spacing: 1) {
                    Text(BuffFormat.multiplier(line.multiplier))
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(line.status.isCounted && line.multiplier > 1 ? AppTheme.green : AppTheme.tertiaryText)
                    Text(LoadoutText.contributionLabel)
                        .font(.system(size: 9))
                        .foregroundStyle(AppTheme.tertiaryText)
                }
            }
            LoadoutLineControls(model: model, line: line, allowConfirm: showsConfirm, siblings: model.evaluation.lines)
                .padding(.leading, 12)
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 8)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.white.opacity(0.025)))
    }

    /// 只有占槽位的栏（和当前武器自带）需要单独勾「条件成立」；不占槽位的栏勾选即确认。
    private var showsConfirm: Bool {
        line.column.isSlotted || line.sources.contains(LoadoutText.sourceAutoInnate)
    }
}

// MARK: - 条件 / 层数 / 选档控件

struct LoadoutLineControls: View {
    @ObservedObject var model: BuffRankerModel
    let line: LoadoutLine
    let allowConfirm: Bool
    /// 同一处列出的其它行（累积阶梯的各档只在一行上给选档控件）。
    let siblings: [LoadoutLine]

    var body: some View {
        if let buff = model.buff(line), line.verdict.isApplicable,
           line.status != .curse, line.status != .invalidRelic {
            if let input = buff.stackInput {
                stackControl(input)
            } else if let ladder = buff.accumulatorLadder {
                if Self.ownsLadderPicker(line, ladder: ladder, siblings: siblings, model: model) {
                    ladderControl(ladder)
                }
            } else if allowConfirm && line.verdict.needsConfirmation {
                confirmControl
            }
        }
    }

    /// 累积阶梯的选档控件放在哪一行：有计入的档就放在那一档，否则放在第 1 档。
    static func ownsLadderPicker(
        _ line: LoadoutLine, ladder: BuffAccumulatorLadder, siblings: [LoadoutLine], model: BuffRankerModel
    ) -> Bool {
        let counted = siblings.first { other in
            other.status.isCounted && model.buff(other)?.accumulatorLadder?.ladderID == ladder.ladderID
        }
        if let counted { return counted.id == line.id }
        return ladder.tier == 1
    }

    private var confirmControl: some View {
        HStack(spacing: 8) {
            Toggle(LoadoutText.confirmLabel, isOn: Binding(
                get: { model.isConfirmed(line.spEffectId) },
                set: { _ in model.toggleConfirmed(line.spEffectId) }
            ))
            .toggleStyle(.checkbox)
            .font(.system(size: 11))
            .help(LoadoutText.confirmHelp)
            if let note = line.verdict.activationNote ?? userRequirement {
                Text(note)
                    .font(.system(size: 10))
                    .foregroundStyle(AppTheme.tertiaryText)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
    }

    private var userRequirement: String? {
        line.verdict.requirements.first { $0.state == .needsUser }?.text
    }

    private func stackControl(_ input: BuffStackInput) -> some View {
        let current = model.stacks(line.spEffectId)
        return HStack(spacing: 8) {
            Text(LoadoutText.stacksLabel)
                .font(.system(size: 11))
                .foregroundStyle(AppTheme.secondaryText)
            Stepper(
                value: Binding(
                    get: { current },
                    set: { model.setStacks(line.spEffectId, $0, max: input.maxAllowedStacks) }
                ),
                in: 0...input.maxAllowedStacks
            ) {
                Text("\(current)")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(
                        (input.practicalMaxStacks.map { current > $0 } ?? false) ? AppTheme.amber : .white
                    )
                    .frame(minWidth: 24, alignment: .trailing)
            }
            .fixedSize()
            Text(LoadoutText.stacksHint(input))
                .font(.system(size: 10))
                .foregroundStyle(AppTheme.tertiaryText)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
    }

    private func ladderControl(_ ladder: BuffAccumulatorLadder) -> some View {
        HStack(spacing: 8) {
            Text(LoadoutText.ladderLabel)
                .font(.system(size: 11))
                .foregroundStyle(AppTheme.secondaryText)
            Picker(LoadoutText.ladderLabel, selection: Binding(
                get: { model.ladderTier(ladder.ladderID) },
                set: { model.setLadderTier(ladder.ladderID, $0) }
            )) {
                Text(LoadoutText.ladderNone).tag(0)
                ForEach(model.ladderTierOptions(ladder), id: \.self) { tier in
                    Text(LoadoutText.ladderTier(
                        tier, threshold: ladder.thresholds.indices.contains(tier - 1) ? ladder.thresholds[tier - 1] : nil
                    )).tag(tier)
                }
            }
            .labelsHidden()
            .frame(width: 150)
            Spacer(minLength: 0)
        }
    }
}

// MARK: - 候选行

/// 各栏共用的候选行：左边是选择控件（数量步进 / 勾选），右边是有效倍率，展开后逐条列 buff 的判定。
struct LoadoutCandidateRow<Leading: View>: View {
    @ObservedObject var model: BuffRankerModel
    let candidate: LoadoutCandidate
    let isSelected: Bool
    /// 占槽位的栏：选中≠条件成立，展开后给「条件成立」勾选。
    let allowConfirm: Bool
    /// 视图额外加的徽标（例如同一词条的不同档位同时选中时的「参数推断，未实测」）。
    var extraBadges: [String] = []
    @ViewBuilder let leading: () -> Leading
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 10) {
                leading()
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(candidate.item.title)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(candidate.isApplicable ? .white : AppTheme.tertiaryText)
                        ForEach(badges, id: \.self) { badge in
                            Pill(text: badge, color: LoadoutPalette.badge(badge))
                        }
                    }
                    Text(summary)
                        .font(.system(size: 10))
                        .foregroundStyle(summaryColor)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(BuffFormat.multiplier(candidate.multiplier))
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(candidate.multiplier > 1.0000001 ? AppTheme.green : AppTheme.secondaryText)
                    if abs(candidate.potential - candidate.multiplier) > 0.0000001 {
                        Text(candidate.potentialAssumesOneStack
                             ? LoadoutText.potentialTextOneStack(candidate.potential)
                             : LoadoutText.potentialText(candidate.potential))
                            .font(.system(size: 10))
                            .foregroundStyle(AppTheme.amber)
                    }
                    if candidate.weightedFlat > 0 {
                        Text(LoadoutText.flatText(candidate.weightedFlat))
                            .font(.system(size: 10))
                            .foregroundStyle(AppTheme.amber)
                    }
                }
                Button {
                    expanded.toggle()
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(AppTheme.tertiaryText)
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            if isSelected && !expanded {
                ForEach(inlineLines) { line in
                    LoadoutLineControls(model: model, line: line, allowConfirm: allowConfirm, siblings: candidate.lines)
                        .padding(.leading, 30)
                }
            }
            if expanded { details }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isSelected ? AppTheme.purple.opacity(0.10) : Color.white.opacity(0.02))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(isSelected ? AppTheme.purple.opacity(0.32) : AppTheme.border, lineWidth: 1)
        )
        .opacity(candidate.isApplicable ? 1 : 0.5)
    }

    /// 选中后直接在行内给出的控件：层数、选档、（占槽位的栏）条件成立。
    private var inlineLines: [LoadoutLine] {
        candidate.lines.filter { line in
            guard line.verdict.isApplicable, let buff = model.buff(line) else { return false }
            if buff.stackInput != nil { return true }
            if let ladder = buff.accumulatorLadder {
                return LoadoutLineControls.ownsLadderPicker(line, ladder: ladder, siblings: candidate.lines, model: model)
            }
            return allowConfirm && line.verdict.needsConfirmation
        }
    }

    private var badges: [String] {
        var result = candidate.item.badges + extraBadges
        if candidate.item.column == .weaponSkill, let skillID = model.skill?.id,
           candidate.item.buffIndices.contains(where: { offset in
               model.loadoutIndex?.dataset.buffs[offset].sources.contains { $0.artsId == skillID } ?? false
           }) {
            result.insert(LoadoutText.badgeCurrentSkill, at: 0)
        }
        return result
    }

    private var summary: String {
        if !candidate.isApplicable {
            return LoadoutText.appliesNo + "：" + (candidate.blockedReason ?? LoadoutText.appliesNoFallback)
        }
        var parts: [String] = []
        if let group = candidate.item.groupTitle, !group.isEmpty { parts.append(group) }
        if !candidate.item.subtitle.isEmpty { parts.append(candidate.item.subtitle) }
        let ladderCounted = candidate.lines.contains { $0.status.isCounted && model.buff($0)?.accumulatorLadder != nil }
        if let line = candidate.lines.first(where: { line in
            !line.status.isCounted && line.verdict.isApplicable && !(ladderCounted && line.status == .tierNotSelected)
        }) {
            parts.append(line.statusText)
        } else if let partial = candidate.lines.first(where: { $0.verdict.isPartial }) {
            parts.append(partial.statusText)
        } else if let first = candidate.lines.first {
            parts.append(first.verdict.label)
        }
        return parts.joined(separator: " · ")
    }

    private var summaryColor: Color {
        if !candidate.isApplicable { return AppTheme.red.opacity(0.8) }
        return candidate.needsConfirmation ? AppTheme.amber : AppTheme.tertiaryText
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 固定遗物里有同名词条（#1520 三条『出击时，会持有“星光碎片”』），按位置做 id。
            ForEach(Array(candidate.item.infoLines.enumerated()), id: \.offset) { _, info in
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
            ForEach(candidate.lines) { line in
                LoadoutLineDetail(model: model, line: line, allowConfirm: allowConfirm, siblings: candidate.lines)
            }
        }
        .padding(.leading, 30)
    }
}

/// 展开后的一条 buff：生效判定、条件逐项、倍率、互斥键。
struct LoadoutLineDetail: View {
    @ObservedObject var model: BuffRankerModel
    let line: LoadoutLine
    let allowConfirm: Bool
    let siblings: [LoadoutLine]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(line.displayName)
                    .font(.system(size: 11, weight: .semibold))
                Pill(text: line.verdict.label, color: LoadoutPalette.verdict(line.verdict))
                Spacer(minLength: 0)
                Text(BuffFormat.multiplier(line.multiplier))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(line.multiplier > 1 ? AppTheme.green : AppTheme.tertiaryText)
            }
            if let reason = line.verdict.blockedReason {
                RankerDetailRow(label: LoadoutText.appliesNo, value: reason, tint: AppTheme.red.opacity(0.85))
            }
            ForEach(line.verdict.requirements) { requirement in
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: symbol(requirement.state))
                        .font(.system(size: 10))
                        .foregroundStyle(color(requirement.state))
                    Text(requirement.text)
                        .font(.system(size: 10))
                        .foregroundStyle(AppTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if let note = line.verdict.activationNote {
                RankerDetailRow(label: LoadoutText.detailActivation, value: note, tint: AppTheme.amber)
            }
            if !line.status.isCounted || line.copies > 1 {
                RankerDetailRow(label: LoadoutText.detailStatus, value: line.statusText, tint: AppTheme.secondaryText)
            }
            LoadoutLineControls(model: model, line: line, allowConfirm: allowConfirm, siblings: siblings)
            if let buff = model.buff(line) {
                RankerDetailRow(
                    label: LoadoutText.detailKey,
                    value: line.exclusiveKey + " · " + (buff.paramName ?? "—") + " · SpEffect #\(line.spEffectId)",
                    tint: AppTheme.tertiaryText
                )
                if let desc = buff.descZh {
                    RankerDetailRow(label: LoadoutText.detailDesc, value: desc, tint: AppTheme.secondaryText)
                }
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.white.opacity(0.03)))
    }

    private func symbol(_ state: LoadoutRequirementState) -> String {
        switch state {
        case .met: return "checkmark.circle.fill"
        case .unmet: return "xmark.circle.fill"
        case .partial: return "circle.lefthalf.filled"
        case .needsUser: return "questionmark.circle"
        }
    }

    private func color(_ state: LoadoutRequirementState) -> Color {
        switch state {
        case .met: return AppTheme.green
        case .unmet: return AppTheme.red.opacity(0.85)
        case .partial, .needsUser: return AppTheme.amber
        }
    }
}

// MARK: - 局内武器词条栏

struct BuffRankerWeaponAffixSection: View {
    @ObservedObject var model: BuffRankerModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeading(
                title: LoadoutColumn.weaponAffix.title,
                subtitle: LoadoutText.weaponAffixSubtitle,
                symbol: "hammer",
                tint: LoadoutPalette.column(.weaponAffix)
            )
            HStack(spacing: 10) {
                if model.skill != nil, let name = model.weaponTypeName {
                    Picker("", selection: $model.weaponFilterAll) {
                        Text(LoadoutText.weaponFilterCurrent(name)).tag(false)
                        Text(LoadoutText.weaponFilterAll).tag(true)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 300)
                } else {
                    Text(LoadoutText.weaponFilterNoWeapon)
                        .font(.system(size: 11))
                        .foregroundStyle(AppTheme.tertiaryText)
                }
                RankerSearchField(placeholder: LoadoutText.weaponAffixSearch, text: $model.weaponAffixQuery)
                    .frame(maxWidth: 260)
                Spacer(minLength: 0)
                Text(usageText)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppTheme.secondaryText)
            }
            let rows = model.visibleWeaponAffixCandidates
            if rows.isEmpty {
                Text(LoadoutText.weaponAffixEmpty)
                    .font(.caption)
                    .foregroundStyle(AppTheme.tertiaryText)
            } else {
                LazyVStack(alignment: .leading, spacing: 5) {
                    ForEach(rows) { candidate in
                        row(candidate)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .appCard()
    }

    private var usageText: String {
        var text = LoadoutText.usageWeaponAffix + " " + model.evaluation.weaponAffixUsage.text
        if model.loadout.mode == .deep {
            text += " · " + LoadoutText.usageDeepOnly + " " + model.evaluation.deepOnlyUsage.text
        }
        return text
    }

    @ViewBuilder
    private func row(_ candidate: LoadoutCandidate) -> some View {
        if let info = candidate.item.weaponAffix {
            let count = model.weaponAffixCount(info.attachEffectId)
            LoadoutCandidateRow(
                model: model, candidate: candidate, isSelected: count > 0, allowConfirm: true,
                extraBadges: (model.isOutsideWeaponFilter(info) ? [LoadoutText.badgeOutsideWeaponType] : [])
                    + (model.hasSelectedTierSibling(info) ? [LoadoutText.badgeInferredTiers] : [])
            ) {
                HStack(spacing: 4) {
                    stepButton("minus", enabled: count > 0) { model.changeWeaponAffix(info, by: -1) }
                    Text("\(count)")
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundStyle(count > 0 ? .white : AppTheme.tertiaryText)
                        .frame(width: 20)
                    stepButton("plus", enabled: model.canIncrementWeaponAffix(info)) { model.changeWeaponAffix(info, by: 1) }
                }
            }
        }
    }

    private func stepButton(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol + ".circle.fill")
                .font(.system(size: 16))
                .foregroundStyle(enabled ? AppTheme.purpleSoft : AppTheme.tertiaryText.opacity(0.5))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

// MARK: - 护符栏

struct BuffRankerAccessorySection: View {
    @ObservedObject var model: BuffRankerModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeading(
                title: LoadoutColumn.accessory.title,
                subtitle: LoadoutText.accessorySubtitle,
                symbol: "seal",
                tint: LoadoutPalette.column(.accessory)
            )
            HStack {
                Text(LoadoutText.usageAccessory + " " + model.evaluation.accessoryUsage.text)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppTheme.secondaryText)
                if model.accessoryFull {
                    Pill(text: LoadoutText.accessoryFull, color: AppTheme.green)
                }
                Spacer(minLength: 0)
            }
            LazyVStack(alignment: .leading, spacing: 5) {
                ForEach(model.visibleAccessoryCandidates) { candidate in
                    if case .accessory(let id) = candidate.item.kind {
                        let selected = model.isAccessorySelected(id)
                        LoadoutCandidateRow(model: model, candidate: candidate, isSelected: selected, allowConfirm: true) {
                            Button {
                                model.toggleAccessory(id)
                            } label: {
                                RankerCheckbox(isOn: selected)
                            }
                            .buttonStyle(.plain)
                            .disabled(!selected && model.accessoryFull)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .appCard()
    }
}

// MARK: - 其它增益栏

struct BuffRankerOtherSection: View {
    @ObservedObject var model: BuffRankerModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeading(title: LoadoutText.otherTitle, subtitle: LoadoutText.otherSubtitle, symbol: "square.grid.2x2")
            RankerWrap(spacing: 6, lineSpacing: 6) {
                ForEach(LoadoutColumn.otherColumns) { column in
                    RankerFilterChip(
                        text: "\(column.title) \(model.otherCount(column))",
                        isOn: model.otherColumn == column,
                        color: LoadoutPalette.column(column)
                    ) {
                        model.otherColumn = column
                    }
                }
            }
            HStack(spacing: 10) {
                RankerSearchField(placeholder: LoadoutText.otherSearch, text: $model.otherQuery)
                    .frame(maxWidth: 360)
                Spacer(minLength: 0)
            }
            if let note = columnNote {
                Text(note)
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.tertiaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            let rows = model.visibleOtherCandidates
            if rows.isEmpty {
                Text(LoadoutText.otherEmpty)
                    .font(.caption)
                    .foregroundStyle(AppTheme.tertiaryText)
            } else if model.otherColumn == .character || model.otherColumn == .weaponInnate {
                groupedList(rows)
            } else {
                LazyVStack(alignment: .leading, spacing: 5) {
                    ForEach(rows) { candidate in row(candidate) }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .appCard()
    }

    private var columnNote: String? {
        if model.otherColumn == .weaponInnate && model.skill == nil { return LoadoutText.innateNoWeapon }
        return model.slotRules.slotlessZh[model.otherColumn.sourceSlotKey]
    }

    private func groupedList(_ rows: [LoadoutCandidate]) -> some View {
        var order: [String] = []
        var groups: [String: [LoadoutCandidate]] = [:]
        for candidate in rows {
            let key = candidate.item.groupTitle ?? LoadoutText.heroUnknown
            if groups[key] == nil { order.append(key) }
            groups[key, default: []].append(candidate)
        }
        return LazyVStack(alignment: .leading, spacing: 5) {
            ForEach(order, id: \.self) { key in
                Text(key)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(LoadoutPalette.column(model.otherColumn))
                    .padding(.top, 4)
                ForEach(groups[key] ?? []) { candidate in row(candidate) }
            }
        }
    }

    private func row(_ candidate: LoadoutCandidate) -> some View {
        let selected = model.isSelected(candidate.item)
        return LoadoutCandidateRow(
            model: model, candidate: candidate, isSelected: selected, allowConfirm: candidate.item.isAutoInnate
        ) {
            Button {
                model.toggleSlotless(candidate.item)
            } label: {
                RankerCheckbox(isOn: selected, tint: LoadoutPalette.column(candidate.item.column))
            }
            .buttonStyle(.plain)
            .help(candidate.item.isAutoInnate
                  ? (selected ? LoadoutText.innateRemove : LoadoutText.innateRestore)
                  : LoadoutText.confirmHelp)
        }
    }
}
