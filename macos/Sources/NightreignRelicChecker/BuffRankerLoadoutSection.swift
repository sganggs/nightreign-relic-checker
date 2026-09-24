import RelicCore
import SwiftUI

// 「增伤排名」配置页：汇总面板、局内武器词条栏、护符栏、其它增益栏，以及共用的候选行与条件控件。
// 文案全部取自 RelicCore 的 `LoadoutText.table`（与 Windows 端 ranker.js 的 TEXT 按点号路径逐键同文）。

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

    static func summary(_ column: LoadoutSummaryColumn) -> Color {
        switch column {
        case .weaponAffix: return Self.column(.weaponAffix)
        case .relic: return Self.column(.relic)
        case .accessory: return Self.column(.accessory)
        case .other: return AppTheme.green
        }
    }

    static func verdict(_ verdict: LoadoutVerdict) -> Color {
        if !verdict.isApplicable { return AppTheme.red.opacity(0.85) }
        if verdict.isPartial || verdict.value == .conditional || verdict.needsConfirmation { return AppTheme.amber }
        return AppTheme.green
    }

    static func status(_ status: LoadoutLineStatus) -> Color {
        switch status {
        case .counted: return AppTheme.green
        case .pending, .context, .zeroStacks, .tierOff: return AppTheme.amber
        case .relicInvalid: return AppTheme.red
        default: return AppTheme.tertiaryText
        }
    }

    static func badge(_ text: String) -> Color {
        switch text {
        case LoadoutText.t("badges.deepOnly"), LoadoutText.t("runMode.deep"): return Color(red: 0.55, green: 0.60, blue: 0.99)
        case LoadoutText.t("badges.curse"), LoadoutText.t("badges.requiresCurse"): return AppTheme.red.opacity(0.85)
        case LoadoutText.t("badges.blessing"): return Color(red: 0.99, green: 0.85, blue: 0.45)
        case LoadoutText.t("badges.autoInnate"), LoadoutText.t("badges.currentSkill"): return AppTheme.green
        case LoadoutText.t("badges.conditional"), LoadoutText.t("badges.activated"), LoadoutText.t("badges.ladder"),
             LoadoutText.t("badges.copies"), LoadoutText.t("badges.accLadder"), LoadoutText.t("badges.variant"),
             LoadoutText.t("badges.outsideWeaponType"), LoadoutText.t("badges.inferredTiers"):
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
            SectionHeading(title: LoadoutText.t("summaryHeading"), subtitle: LoadoutText.t("summaryColumnNote"), symbol: "sum")

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

    private var modeHint: String {
        let rules = model.slotRules
        return LoadoutText.f(
            "runModeHint", rules.weaponAffixCap(.normal), rules.relicSlots(.normal), rules.weaponAffixCap(.deep),
            rules.deepOnlyCap(.deep), rules.relicSlots(.deep), rules.relicNormal, rules.relicSlots(.deep) - rules.relicNormal
        )
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                Text(LoadoutText.t("runModeLabel"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppTheme.secondaryText)
                Picker(LoadoutText.t("runModeAria"), selection: Binding(
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
                .help(modeHint)

                Spacer(minLength: 0)

                Button {
                    model.fillRecommended()
                } label: {
                    Label(LoadoutText.t("fillButton"), systemImage: "wand.and.stars")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.purple)
                .disabled(!model.loadoutOutput.hasComposition)
                .help(LoadoutText.t("fillNote"))

                Button(LoadoutText.t("clearButton")) { model.clearLoadout() }
                    .buttonStyle(.bordered)
                    .font(.system(size: 12))
            }
            Text(modeHint)
                .font(.system(size: 10))
                .foregroundStyle(AppTheme.tertiaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var totalRow: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(LoadoutText.t("summaryTotal"))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppTheme.tertiaryText)
                Text(model.evaluation.hasComposition ? BuffFormat.multiplier(model.evaluation.total, digits: 3) : "—")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(model.evaluation.total > 1.0000001 ? AppTheme.green : AppTheme.secondaryText)
                Text(model.totalGainText)
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.tertiaryText)
                if model.evaluation.weightedFlat >= 0.05 || model.evaluation.weightedFlat <= -0.05 {
                    Text(LoadoutText.t("summaryFlat") + " " + LoadoutText.f("flatInline", BuffFormat.signedFlat(model.evaluation.weightedFlat)))
                        .font(.system(size: 10))
                        .foregroundStyle(AppTheme.amber)
                        .help(LoadoutText.t("summaryFlatNote"))
                }
            }
            Divider().frame(height: 48).overlay(AppTheme.border)
            RankerWrap(spacing: 6, lineSpacing: 6) {
                usagePill(LoadoutText.t("usageWeaponAffix"), model.evaluation.weaponAffixUsage)
                if model.loadout.mode == .deep {
                    usagePill(LoadoutText.t("usageDeepOnly"), model.evaluation.deepOnlyUsage)
                }
                usagePill(LoadoutText.t("usageRelic"), model.evaluation.relicUsage)
                usagePill(LoadoutText.t("usageAccessory"), model.evaluation.accessoryUsage)
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
            Toggle(LoadoutText.t("showInactive"), isOn: $model.showInapplicable)
                .toggleStyle(.switch)
                .font(.caption)
                .help(LoadoutText.t("showInactiveHelp"))
            Spacer(minLength: 0)
            Text(model.deliveryLabel)
                .font(.system(size: 11))
                .foregroundStyle(AppTheme.secondaryText)
        }
    }

    private var contexts: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(LoadoutText.t("contextsLabel"))
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
    }

    private var subtotals: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(LoadoutText.t("summarySubtotals"))
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(AppTheme.tertiaryText)
            RankerWrap(spacing: 6, lineSpacing: 5) {
                ForEach(LoadoutSummaryColumn.allCases) { column in
                    Pill(
                        text: column.title + " " + BuffFormat.multiplier(model.evaluation.columnSubtotals[column] ?? 1),
                        color: LoadoutPalette.summary(column)
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var messages: some View {
        let evaluation = model.evaluation
        let notices = [model.modeNotice, model.fillNotice].compactMap { $0 }
        if !notices.isEmpty || !evaluation.violations.isEmpty || !evaluation.warnings.isEmpty || !evaluation.hasComposition {
            VStack(alignment: .leading, spacing: 4) {
                if !evaluation.hasComposition {
                    messageLine(LoadoutText.t("summaryNoComposition"), color: AppTheme.amber, symbol: "exclamationmark.triangle")
                }
                ForEach(notices, id: \.self) { notice in
                    messageLine(notice, color: AppTheme.green, symbol: "checkmark.circle")
                }
                ForEach(evaluation.violations, id: \.self) { text in
                    messageLine(text, color: AppTheme.red, symbol: "xmark.octagon")
                }
                ForEach(evaluation.warnings) { warning in
                    messageLine(warning.text, color: AppTheme.amber, symbol: "exclamationmark.triangle")
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
            Text(LoadoutText.f("summaryCounted", model.evaluation.countedLines.count))
                .font(.system(size: 12, weight: .semibold))
            if model.evaluation.countedLines.isEmpty {
                Text(LoadoutText.t("summaryEmpty"))
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
        // 未选的档不列；累积阶梯没选中的各层只留一行（放选层控件）；不生效的默认隐藏。
        let lines = model.evaluation.lines
        let uncounted = lines.filter { line in
            guard !line.status.isCounted, line.status != .variantOff else { return false }
            if !model.showInapplicable && (line.status == .no || line.status == .context) { return false }
            guard line.status == .tierOff, let ladder = model.buff(line)?.accumulatorLadder else { return true }
            return LoadoutLineControls.ownsLadderPicker(line, ladder: ladder, siblings: lines, model: model)
        }
        let hidden = lines.filter { $0.status == .no || $0.status == .context }.count
        if !uncounted.isEmpty {
            RankerDisclosure(title: LoadoutText.f("summaryUncounted", uncounted.count), isOn: $showUncounted) {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(uncounted) { line in
                        LoadoutSummaryLineRow(model: model, line: line)
                    }
                }
            }
        }
        if !model.showInapplicable && hidden > 0 {
            Text(LoadoutText.f("summaryHiddenNo", hidden, LoadoutText.t("showInactive")))
                .font(.system(size: 10))
                .foregroundStyle(AppTheme.tertiaryText)
        }
    }
}

extension BuffFormat {
    /// 攻击力加算带符号：正数写「+」，四舍五入后为 0 写「0」（与 Windows fmtFlat 同一口径）。
    static func signedFlat(_ value: Double) -> String {
        var text = trim(value, digits: 1)
        if text == "-0" { text = "0" }
        return (value > 0 && text != "0" ? "+" : "") + text
    }
}

/// 汇总面板里的一条：名称、来源、状态、贡献倍率、条件控件与移除按钮。
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
                        Pill(text: line.status.title, color: LoadoutPalette.status(line.status))
                    }
                    Text(line.sources.joined(separator: "、") + " · " + line.exclusiveKey)
                        .font(.system(size: 10))
                        .foregroundStyle(AppTheme.tertiaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    if !line.status.isCounted, !line.reasons.isEmpty {
                        Text(line.reasons.joined(separator: "；"))
                            .font(.system(size: 10))
                            .foregroundStyle(AppTheme.amber)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if !line.notes.isEmpty {
                        Text(line.notes.joined(separator: "；"))
                            .font(.system(size: 10))
                            .foregroundStyle(AppTheme.tertiaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 6)
                VStack(alignment: .trailing, spacing: 1) {
                    Text(BuffFormat.multiplier(line.multiplier))
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(line.status.isCounted && line.multiplier > 1 ? AppTheme.green : AppTheme.tertiaryText)
                    Text(LoadoutText.t("summaryContribution"))
                        .font(.system(size: 9))
                        .foregroundStyle(AppTheme.tertiaryText)
                }
                removeButtons
            }
            LoadoutLineControls(model: model, line: line, siblings: model.evaluation.lines)
                .padding(.leading, 12)
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 8)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.white.opacity(0.025)))
    }

    /// 移除：按来源键（与 Windows 端汇总行的「移除」按钮同一口径）。
    private var removeButtons: some View {
        HStack(spacing: 4) {
            ForEach(Array(line.sourceKeys.enumerated()), id: \.offset) { position, key in
                Button {
                    model.removeSource(key)
                } label: {
                    Image(systemName: "minus.circle")
                        .foregroundStyle(AppTheme.tertiaryText)
                }
                .buttonStyle(.plain)
                .help((key.hasPrefix("innate:") ? LoadoutText.t("innateRemove") : LoadoutText.t("summaryRemove"))
                      + (line.sources.indices.contains(position) ? "：" + line.sources[position] : ""))
            }
        }
    }
}

// MARK: - 条件 / 层数 / 选层 / 选档控件

struct LoadoutLineControls: View {
    @ObservedObject var model: BuffRankerModel
    let line: LoadoutLine
    /// 同一处列出的其它行（累积阶梯的各层只在一行上给选层控件）。
    let siblings: [LoadoutLine]

    var body: some View {
        if let buff = model.buff(line), line.status != .no, line.status != .context, line.status != .relicInvalid {
            VStack(alignment: .leading, spacing: 4) {
                if let input = buff.stackInput {
                    stackControl(input, grace: LoadoutText.isGraceStack(buff))
                }
                if let ladder = buff.accumulatorLadder,
                   Self.ownsLadderPicker(line, ladder: ladder, siblings: siblings, model: model) {
                    ladderControl(ladder)
                }
                if let variant = buff.affixVariant, line.status != .variantOff {
                    variantControl(variant)
                }
                if !line.needs.isEmpty && !line.autoConfirm {
                    confirmControl
                }
            }
        }
    }

    /// 累积阶梯的选层控件放在哪一行：选中的那一层（没选就第 1 层）。
    static func ownsLadderPicker(
        _ line: LoadoutLine, ladder: BuffAccumulatorLadder, siblings: [LoadoutLine], model: BuffRankerModel
    ) -> Bool {
        let picked = model.ladderTier(ladder.ladderID)
        if model.ladderTierOptions(ladder).contains(picked) { return ladder.tier == picked }
        return ladder.tier == (model.ladderTierOptions(ladder).first ?? 1)
    }

    private var confirmControl: some View {
        HStack(spacing: 8) {
            Toggle(LoadoutText.t("summaryTick"), isOn: Binding(
                get: { model.isConfirmed(line.spEffectId) },
                set: { _ in model.toggleConfirmed(line.spEffectId) }
            ))
            .toggleStyle(.checkbox)
            .font(.system(size: 11))
            .help(LoadoutText.t("summaryTickHelp"))
            Text(line.needs.joined(separator: "；"))
                .font(.system(size: 10))
                .foregroundStyle(AppTheme.tertiaryText)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
    }

    private func stackControl(_ input: BuffStackInput, grace: Bool) -> some View {
        let current = model.stacks(line.spEffectId)
        return HStack(spacing: 8) {
            Text(LoadoutText.t(input.isLadder ? "stackLabel" : "stackLabelCopies"))
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
            Text(LoadoutText.stackHints(input, grace: grace).joined(separator: "；"))
                .font(.system(size: 10))
                .foregroundStyle(AppTheme.tertiaryText)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
    }

    private func ladderControl(_ ladder: BuffAccumulatorLadder) -> some View {
        HStack(spacing: 8) {
            Text(LoadoutText.t("tierSelectLabel"))
                .font(.system(size: 11))
                .foregroundStyle(AppTheme.secondaryText)
            Picker(LoadoutText.t("tierSelectLabel"), selection: Binding(
                get: { model.ladderTier(ladder.ladderID) },
                set: { model.setLadderTier(ladder.ladderID, $0) }
            )) {
                Text(LoadoutText.t("tierNone")).tag(0)
                ForEach(model.ladderTierOptions(ladder), id: \.self) { tier in
                    Text(ladder.thresholds.indices.contains(tier - 1)
                         ? LoadoutText.f("tierLabelThreshold", tier, BuffFormat.trim(ladder.thresholds[tier - 1], digits: 0))
                         : LoadoutText.f("tierLabel", tier)).tag(tier)
                }
            }
            .labelsHidden()
            .frame(minWidth: 90, maxWidth: 170)
            Spacer(minLength: 0)
        }
    }

    private func variantControl(_ variant: BuffAffixVariant) -> some View {
        HStack(spacing: 8) {
            Text(LoadoutText.t("variantLabel"))
                .font(.system(size: 11))
                .foregroundStyle(AppTheme.secondaryText)
            Picker(LoadoutText.t("variantLabel"), selection: Binding(
                get: { model.variantChoice(variant.groupKey) ?? line.spEffectId },
                set: { model.setVariant(variant.groupKey, $0) }
            )) {
                ForEach(model.variantOptions(variant.groupKey), id: \.id) { option in
                    Text(option.text).tag(option.id)
                }
            }
            .labelsHidden()
            .frame(maxWidth: 360)
            .help(LoadoutText.t("variantNoMapping"))
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
                        // 道具 2／3 级行（学者「携物知识」）：名字旁标等级，悬停说明只有学者能把道具升上去。
                        if let tag = goodsLevelTag {
                            Pill(text: tag, color: AppTheme.amber)
                                .help(LoadoutText.t("goodsLevel.hint"))
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
                             ? LoadoutText.f("potentialOneStack", BuffFormat.multiplier(candidate.potential))
                             : LoadoutText.f("potentialText", BuffFormat.multiplier(candidate.potential)))
                            .font(.system(size: 10))
                            .foregroundStyle(AppTheme.amber)
                    }
                    if candidate.weightedFlat >= 0.05 || candidate.weightedFlat <= -0.05 {
                        Text(LoadoutText.f("flatInline", BuffFormat.signedFlat(candidate.weightedFlat)))
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
                    LoadoutLineControls(model: model, line: line, siblings: selectedLines)
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

    /// 选中后，这一项在汇总里的逐条（控件以汇总为准：条件、层数、选层、选档都按整套配置算）。
    private var selectedLines: [LoadoutLine] {
        let ids = Set(candidate.item.buffIndices)
        return model.evaluation.lines.filter { ids.contains($0.buffIndex) }
    }

    /// 选中后直接在行内给出的控件：层数、选层、选档、（占槽位的栏）条件成立。
    private var inlineLines: [LoadoutLine] {
        selectedLines.filter { line in
            guard let buff = model.buff(line), line.status != .no, line.status != .context, line.status != .variantOff else {
                return false
            }
            if buff.stackInput != nil || buff.affixVariant != nil { return true }
            if let ladder = buff.accumulatorLadder {
                return LoadoutLineControls.ownsLadderPicker(line, ladder: ladder, siblings: selectedLines, model: model)
            }
            return !line.needs.isEmpty && !line.autoConfirm
        }
    }

    /// 「道具」栏 goodsLevel ≥ 2 的行：「携物知识 N 级」；其余为 nil。
    private var goodsLevelTag: String? {
        LoadoutText.goodsLevelTag(model.loadoutIndex?.goodsLevel(of: candidate.item))
    }

    private var badges: [String] {
        var result = candidate.item.badges + extraBadges
        if candidate.item.column == .weaponSkill, let skillID = model.skill?.id,
           candidate.item.buffIndices.contains(where: { offset in
               model.loadoutIndex?.dataset.buffs[offset].sources.contains { $0.artsId == skillID } ?? false
           }) {
            result.insert(LoadoutText.t("badges.currentSkill"), at: 0)
        }
        return result
    }

    private var summary: String {
        if !candidate.isApplicable {
            return LoadoutText.t("verdict.no") + "：" + (candidate.blockedReason ?? LoadoutText.t("verdictNoFallback"))
        }
        var parts: [String] = []
        if let group = candidate.item.groupTitle, !group.isEmpty { parts.append(group) }
        if !candidate.item.subtitle.isEmpty { parts.append(candidate.item.subtitle) }
        if candidate.status.isCounted {
            if let partial = candidate.lines.first(where: { $0.verdict.isPartial }) {
                parts.append(partial.verdict.label)
            } else if let first = candidate.lines.first {
                parts.append(first.verdict.label)
            }
        } else {
            parts.append(([candidate.status.title] + candidate.reasons).joined(separator: "："))
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
                        Text(LoadoutText.t("relicNonDamage"))
                            .font(.system(size: 10))
                            .foregroundStyle(AppTheme.tertiaryText)
                    }
                }
            }
            ForEach(candidate.lines) { line in
                LoadoutLineDetail(model: model, line: line)
            }
        }
        .padding(.leading, 30)
    }
}

/// 展开后的一条 buff：生效判定、条件逐项、倍率、互斥键。
struct LoadoutLineDetail: View {
    @ObservedObject var model: BuffRankerModel
    let line: LoadoutLine

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(line.displayName)
                    .font(.system(size: 11, weight: .semibold))
                Pill(text: line.verdict.label, color: LoadoutPalette.verdict(line.verdict))
                Pill(text: line.status.title, color: LoadoutPalette.status(line.status))
                Spacer(minLength: 0)
                Text(BuffFormat.multiplier(line.multiplier))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(line.multiplier > 1 ? AppTheme.green : AppTheme.tertiaryText)
            }
            if let reason = line.verdict.blockedReason {
                RankerDetailRow(label: LoadoutText.t("verdict.no"), value: reason, tint: AppTheme.red.opacity(0.85))
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
                RankerDetailRow(label: LoadoutText.t("detailActivation"), value: note, tint: AppTheme.amber)
            }
            if !line.status.isCounted || !line.notes.isEmpty {
                RankerDetailRow(
                    label: LoadoutText.t("detailStatus"),
                    value: (line.status.isCounted ? line.notes : line.reasons + line.notes).joined(separator: "；"),
                    tint: AppTheme.secondaryText
                )
            }
            if let buff = model.buff(line) {
                RankerDetailRow(
                    label: LoadoutText.t("detailKey"),
                    value: line.exclusiveKey + " · " + (buff.paramName ?? "—") + " · SpEffect #\(line.spEffectId)",
                    tint: AppTheme.tertiaryText
                )
                if let desc = buff.descZh {
                    RankerDetailRow(label: LoadoutText.t("detailDesc"), value: desc, tint: AppTheme.secondaryText)
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
                subtitle: LoadoutText.f("waIntro", model.slotRules.maxWeapons),
                symbol: "hammer",
                tint: LoadoutPalette.column(.weaponAffix)
            )
            HStack(spacing: 10) {
                if let name = model.weaponTypeName {
                    Picker(LoadoutText.t("waFilterAria"), selection: $model.weaponFilterAll) {
                        Text(LoadoutText.f("waFilterWeapon", name)).tag(false)
                        Text(LoadoutText.t("waFilterAll")).tag(true)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    // 按固有宽度排：两段等宽、按「当前武器类别（…）」撑开，类别名长时会超过原来的
                    // 300pt 固定框、在框里居中后左右伸出（同遗物卡的分段选择，见 RelicCardView.typePicker）
                    .fixedSize()
                } else {
                    Text(LoadoutText.t("waFilterNone"))
                        .font(.system(size: 11))
                        .foregroundStyle(AppTheme.tertiaryText)
                }
                RankerSearchField(placeholder: LoadoutText.t("waSearch"), text: $model.weaponAffixQuery)
                    .frame(maxWidth: 260)
                Spacer(minLength: 0)
                Text(usageText)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppTheme.secondaryText)
            }
            if model.evaluation.lines.contains(where: { $0.column == .weaponAffix && $0.copies > 1 }) {
                Text(LoadoutText.t("waCopiesHint"))
                    .font(.system(size: 10))
                    .foregroundStyle(AppTheme.amber)
            }
            if let loadoutIndex = model.loadoutIndex, !loadoutIndex.selectedTierFamilies(model.loadout).isEmpty {
                Text(LoadoutText.t("waTierHint"))
                    .font(.system(size: 10))
                    .foregroundStyle(AppTheme.tertiaryText)
            }
            let rows = model.visibleWeaponAffixCandidates
            if rows.isEmpty {
                Text(LoadoutText.t("waEmpty"))
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
        var text = LoadoutText.f("waUsage", model.evaluation.weaponAffixUsage.used, model.evaluation.weaponAffixUsage.cap)
        if model.loadout.mode == .deep {
            text += " · " + LoadoutText.f("waDeepOnlyUsage", model.evaluation.deepOnlyUsage.used, model.evaluation.deepOnlyUsage.cap)
        }
        return text
    }

    @ViewBuilder
    private func row(_ candidate: LoadoutCandidate) -> some View {
        if let info = candidate.item.weaponAffix {
            let count = model.weaponAffixCount(info.attachEffectId)
            LoadoutCandidateRow(
                model: model, candidate: candidate, isSelected: count > 0,
                extraBadges: (model.isOutsideWeaponFilter(info) ? [LoadoutText.t("badges.outsideWeaponType")] : [])
                    + (model.hasSelectedTierSibling(info) ? [LoadoutText.t("badges.inferredTiers")] : [])
            ) {
                HStack(spacing: 4) {
                    stepButton("minus", enabled: count > 0, help: LoadoutText.t("stepDown")) {
                        model.changeWeaponAffix(info, by: -1)
                    }
                    Text("\(count)")
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundStyle(count > 0 ? .white : AppTheme.tertiaryText)
                        .frame(width: 20)
                    stepButton("plus", enabled: model.canIncrementWeaponAffix(info), help: model.incrementBlockReason(info)) {
                        model.changeWeaponAffix(info, by: 1)
                    }
                }
            }
        }
    }

    private func stepButton(_ symbol: String, enabled: Bool, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol + ".circle.fill")
                .font(.system(size: 16))
                .foregroundStyle(enabled ? AppTheme.purpleSoft : AppTheme.tertiaryText.opacity(0.5))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .help(help)
    }
}

// MARK: - 护符栏

struct BuffRankerAccessorySection: View {
    @ObservedObject var model: BuffRankerModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeading(
                title: LoadoutColumn.accessory.title,
                subtitle: LoadoutText.f("accIntro", model.slotRules.accessorySlots),
                symbol: "seal",
                tint: LoadoutPalette.column(.accessory)
            )
            HStack {
                Text(LoadoutText.t("usageAccessory") + " " + model.evaluation.accessoryUsage.text)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppTheme.secondaryText)
                if model.accessoryFull {
                    Pill(text: LoadoutText.t("accFull"), color: AppTheme.green)
                }
                Spacer(minLength: 0)
            }
            LazyVStack(alignment: .leading, spacing: 5) {
                ForEach(model.visibleAccessoryCandidates) { candidate in
                    if case .accessory(let id) = candidate.item.kind {
                        let selected = model.isAccessorySelected(id)
                        LoadoutCandidateRow(model: model, candidate: candidate, isSelected: selected) {
                            Button {
                                model.toggleAccessory(id)
                            } label: {
                                RankerCheckbox(isOn: selected)
                            }
                            .buttonStyle(.plain)
                            .disabled(!selected && model.accessoryFull)
                            .help(selected ? LoadoutText.t("accRemove") : LoadoutText.t("accPlaceholder"))
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
            SectionHeading(title: LoadoutText.t("columns.other"), subtitle: LoadoutText.t("otherIntro"), symbol: "square.grid.2x2")
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
                RankerSearchField(placeholder: LoadoutText.t("otherSearch"), text: $model.otherQuery)
                    .frame(maxWidth: 360)
                Spacer(minLength: 0)
            }
            ForEach(columnNotes, id: \.self) { note in
                Text(note)
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.tertiaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            let rows = model.visibleOtherCandidates
            if rows.isEmpty {
                Text(LoadoutText.t("otherEmpty"))
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

    /// 分栏说明区：slotRules 的栏目说明；「道具」栏另加一句道具等级（学者「携物知识」）的说明。
    private var columnNotes: [String] {
        if model.otherColumn == .weaponInnate {
            if model.skill == nil { return [LoadoutText.t("otherInnateNoWeapon")] }
            if (model.otherCandidates[.weaponInnate] ?? []).contains(where: \.item.isAutoInnate) {
                return [LoadoutText.t("otherInnateHint")]
            }
        }
        var notes = model.slotRules.slotlessZh[model.otherColumn.sourceSlotKey].map { [$0] } ?? []
        if model.otherColumn == .consumable, model.loadoutIndex?.hasGoodsLevelItems == true {
            notes.append(LoadoutText.t("goodsLevel.note"))
        }
        return notes
    }

    private func groupedList(_ rows: [LoadoutCandidate]) -> some View {
        var order: [String] = []
        var groups: [String: [LoadoutCandidate]] = [:]
        for candidate in rows {
            let key = candidate.item.groupTitle ?? LoadoutText.t("characterOther")
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
        return LoadoutCandidateRow(model: model, candidate: candidate, isSelected: selected) {
            Button {
                model.toggleSlotless(candidate.item)
            } label: {
                RankerCheckbox(isOn: selected, tint: LoadoutPalette.column(candidate.item.column))
            }
            .buttonStyle(.plain)
            .help(candidate.item.isAutoInnate
                  ? (selected ? LoadoutText.t("innateRemove") : LoadoutText.t("innateRestore"))
                  : LoadoutText.t("selectUse"))
        }
    }
}
