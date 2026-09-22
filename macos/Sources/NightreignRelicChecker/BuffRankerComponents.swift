import RelicCore
import SwiftUI

// 「增伤排名」页的小组件与配色。样式沿用 Theme.swift 的 AppTheme。

enum RankerPalette {
    /// 伤害通道配色：物理四类用不同深浅的灰白，属性用各自的颜色。
    static func color(_ channel: SkillDamageChannel) -> Color {
        switch channel {
        case .slash: return Color(white: 0.88)
        case .strike: return Color(white: 0.72)
        case .pierce: return Color(white: 0.56)
        case .standard: return Color(white: 0.42)
        case .physicalOther: return Color(white: 0.30)
        case .magic: return Color(red: 0.44, green: 0.60, blue: 0.99)
        case .fire: return Color(red: 0.96, green: 0.45, blue: 0.22)
        case .lightning: return Color(red: 0.95, green: 0.80, blue: 0.25)
        case .holy: return Color(red: 0.99, green: 0.93, blue: 0.78)
        }
    }

    /// 来源类型徽标配色。
    static func sourceColor(_ kind: String) -> Color {
        switch kind {
        case "relicAffix": return AppTheme.purpleSoft
        case "weaponPassive": return Color(red: 0.42, green: 0.72, blue: 0.95)
        case "accessory": return Color(red: 0.95, green: 0.62, blue: 0.85)
        case "goods": return AppTheme.green
        case "spell": return Color(red: 0.55, green: 0.78, blue: 0.99)
        case "heroSkill": return AppTheme.amber
        case "permanent": return Color(red: 0.75, green: 0.85, blue: 0.55)
        default: return AppTheme.secondaryText
        }
    }
}

/// 复选框（段勾选、组合勾选都用它）。
struct RankerCheckbox: View {
    let isOn: Bool
    var tint: Color = AppTheme.purpleSoft

    var body: some View {
        Image(systemName: isOn ? "checkmark.square.fill" : "square")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(isOn ? tint : AppTheme.tertiaryText)
    }
}

/// 会自动换行的横向排布（情境多选的小标签有十几个，一行放不下）。
struct RankerWrap: Layout {
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
                current = Row()
                current.indices = [index]
                current.width = size.width
                current.height = size.height
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

/// 可点的筛选小标签。
struct RankerFilterChip: View {
    let text: String
    let isOn: Bool
    var color: Color = AppTheme.purpleSoft
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(text)
                .font(.caption.weight(.semibold))
                .foregroundStyle(isOn ? color : AppTheme.secondaryText)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(
                    Capsule().fill(isOn ? color.opacity(0.16) : Color.white.opacity(0.04))
                )
                .overlay(
                    Capsule().stroke(isOn ? color.opacity(0.42) : AppTheme.border, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

/// 搜索输入框。
struct RankerSearchField: View {
    let placeholder: String
    @Binding var text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(AppTheme.secondaryText)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(AppTheme.tertiaryText)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 34)
        .background(AppTheme.field, in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(AppTheme.border, lineWidth: 1))
    }
}

/// 标签 + 数值的一行。
struct RankerDetailRow: View {
    let label: String
    let value: String
    var tint: Color = .white

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(AppTheme.tertiaryText)
                .frame(width: 96, alignment: .leading)
            Text(value)
                .font(.system(size: 11))
                .foregroundStyle(tint)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}

/// 伤害构成的堆叠条。
struct RankerCompositionBar: View {
    let composition: SkillDamageComposition

    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 1) {
                ForEach(composition.breakdown) { item in
                    RankerPalette.color(item.channel)
                        .frame(width: max(1, proxy.size.width * item.share))
                }
            }
        }
        .frame(height: 14)
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .stroke(AppTheme.border, lineWidth: 1)
        )
    }
}

/// 构成明细里的一行（通道 + 百分比 + 细条）。
struct RankerCompositionLegendRow: View {
    let channel: SkillDamageChannel
    let share: Double
    let amount: Double

    var body: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(RankerPalette.color(channel))
                .frame(width: 10, height: 10)
            Text(channel.titleZh)
                .font(.system(size: 12))
                .frame(width: 80, alignment: .leading)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(Color.white.opacity(0.05))
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(RankerPalette.color(channel).opacity(0.78))
                        .frame(width: max(2, proxy.size.width * share))
                }
            }
            .frame(height: 8)
            Text(BuffFormat.percent(share))
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .frame(width: 56, alignment: .trailing)
            Text(BuffFormat.trim(amount, digits: 1))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(AppTheme.tertiaryText)
                .frame(width: 64, alignment: .trailing)
        }
    }
}

/// 一段命中的行。
struct RankerSegmentRow: View {
    let segment: SkillSegment
    let isSelected: Bool
    let onToggle: () -> Void

    /// noDamage 段构成恒为 0，勾不勾都一样——与 Windows 端 `disabled` 的 checkbox 对齐，
    /// 这里直接禁掉整行的点击。
    private var isDisabled: Bool { segment.noDamage }

    var body: some View {
        Button(action: onToggle) {
            HStack(alignment: .top, spacing: 10) {
                RankerCheckbox(isOn: isSelected)
                    .padding(.top, 1)

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        Text(segment.labelZh)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(segment.noDamage ? AppTheme.tertiaryText : .white)
                        if segment.isBullet {
                            Pill(text: "子弹", color: Color(red: 0.55, green: 0.78, blue: 0.99))
                        }
                        if segment.noFp {
                            Pill(text: "无 FP 版", color: AppTheme.amber)
                        }
                        if segment.noDamage {
                            Pill(text: "只挂状态", color: AppTheme.tertiaryText)
                        }
                        Spacer(minLength: 0)
                        Text("#\(segment.atkId)")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(AppTheme.tertiaryText)
                    }

                    HStack(spacing: 6) {
                        ForEach(segment.components) { component in
                            componentChip(component)
                        }
                        if segment.components.isEmpty {
                            Text("无伤害数值")
                                .font(.system(size: 11))
                                .foregroundStyle(AppTheme.tertiaryText)
                        }
                    }

                    HStack(spacing: 12) {
                        metric("削韧", BuffFormat.trim(segment.poise, digits: 1))
                        metric("耐力", BuffFormat.trim(segment.stamina, digits: 1))
                        if let channel = segment.physicalChannel {
                            metric("物理类型", channel.titleZh)
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(isSelected ? AppTheme.purple.opacity(0.10) : Color.white.opacity(0.02))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(isSelected ? AppTheme.purple.opacity(0.32) : AppTheme.border, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.55 : 1)
        .help(isDisabled ? "这一段只挂状态、不产生伤害，不能计入构成" : "")
    }

    private func componentChip(_ component: SkillSegmentComponent) -> some View {
        var parts: [String] = []
        if let motion = component.motionPercent {
            parts.append(BuffFormat.trim(motion, digits: 1) + "%")
        }
        if let flat = component.flat {
            parts.append("固定 " + BuffFormat.trim(flat, digits: 1))
        }
        if component.baseAttack != nil {
            parts.append("+基础攻击力")
        }
        let color = RankerPalette.color(component.channel)
        return HStack(spacing: 4) {
            Text(component.channel.titleZh)
                .font(.system(size: 10, weight: .semibold))
            Text(parts.joined(separator: " · "))
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(AppTheme.secondaryText)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private func metric(_ title: String, _ value: String) -> some View {
        HStack(spacing: 4) {
            Text(title)
                .font(.system(size: 10))
                .foregroundStyle(AppTheme.tertiaryText)
            Text(value)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(AppTheme.secondaryText)
        }
    }
}

/// 排名列表里的一行。
struct RankerBuffRow: View {
    let rank: Int
    let row: BuffRankingRow
    let dataset: BuffDataset
    let isExpanded: Bool
    /// 这一条当前是否计入推荐组合（passive 默认计入，条件型默认不计入）。
    let isInPlan: Bool
    let onToggleExpand: () -> Void
    let onTogglePlan: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            if isExpanded { details }
        }
        .padding(.vertical, 9)
        .padding(.horizontal, 11)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isInPlan ? Color.white.opacity(0.03) : Color.white.opacity(0.01))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(AppTheme.border, lineWidth: 1)
        )
        .opacity(row.isPassive && !isInPlan ? 0.5 : 1)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            Button(action: onTogglePlan) {
                RankerCheckbox(isOn: isInPlan, tint: row.isPassive ? AppTheme.purpleSoft : AppTheme.amber)
            }
            .buttonStyle(.plain)
            .help(planHelp)

            Text("\(rank)")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(AppTheme.tertiaryText)
                .frame(width: 26, alignment: .trailing)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(row.displayName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(row.isPassive ? .white : AppTheme.secondaryText)
                        .italic(!row.isPassive)
                    if !row.isPassive {
                        Pill(text: activationTitle, color: AppTheme.amber)
                    }
                    if row.target == "ally" {
                        Pill(text: "队友增益", color: Color(red: 0.55, green: 0.78, blue: 0.99))
                    }
                    if row.isInferredSource {
                        Pill(text: "来源为推断", color: AppTheme.tertiaryText)
                    }
                    // 只在某种攻击情境下才吃得到：不标出来的话，用户会当成常驻增伤。
                    ForEach(row.attackContextLabels, id: \.self) { label in
                        Pill(text: "限" + label, color: AppTheme.amber)
                    }
                    if let ladder = row.ladder {
                        Pill(
                            text: "叠层 1/\(ladder.tiers)" + (ladder.saved ? " · 存档保留" : ""),
                            color: AppTheme.amber
                        )
                    }
                    // v5：status 组的加算是玩家自伤，不是「攻击附带累积」；不打标会被当成增益。
                    if row.selfInflictedStatus {
                        Pill(text: "自伤型异常累积", color: AppTheme.tertiaryText)
                    }
                }
                HStack(spacing: 6) {
                    ForEach(row.sourceKinds, id: \.self) { kind in
                        Pill(text: dataset.sourceKindLabel(kind), color: RankerPalette.sourceColor(kind))
                    }
                    Text(row.durationText)
                        .font(.system(size: 10))
                        .foregroundStyle(AppTheme.tertiaryText)
                    Text("叠加组 " + row.stackGroup)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(AppTheme.tertiaryText)
                }
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 2) {
                Text(BuffFormat.multiplier(row.effectiveMultiplier))
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(row.effectiveMultiplier > 1 ? AppTheme.green : AppTheme.secondaryText)
                if let ladder = row.ladder {
                    Text("满 \(ladder.tiers) 层 " + BuffFormat.multiplier(ladder.topMultiplier))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(AppTheme.amber)
                } else if row.weightedFlat != 0 {
                    Text("加算 " + BuffFormat.trim(row.weightedFlat, digits: 1))
                        .font(.system(size: 10))
                        .foregroundStyle(AppTheme.amber)
                } else {
                    Text(BuffFormat.gain(row.effectiveMultiplier))
                        .font(.system(size: 10))
                        .foregroundStyle(AppTheme.tertiaryText)
                }
            }

            Button(action: onToggleExpand) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(AppTheme.tertiaryText)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private var planHelp: String {
        if !row.isPassive {
            return isInPlan ? "不再计入推荐组合" : "这条需要触发 / 发动才成立，勾选后单独纳入推荐组合"
        }
        return isInPlan ? "从推荐组合里去掉" : "重新计入推荐组合"
    }

    private var activationTitle: String {
        row.activation == "activated" ? "发动期间" : "需满足条件"
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 7) {
            if !row.rateValues.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    Text("倍率字段")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(AppTheme.tertiaryText)
                    ForEach(row.rateValues) { rate in
                        HStack(spacing: 6) {
                            Text(rate.zh)
                                .font(.system(size: 11))
                                .foregroundStyle(rate.countsAsDamage ? .white : AppTheme.tertiaryText)
                            Text(rate.displayValue)
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundStyle(rate.countsAsDamage ? AppTheme.green : AppTheme.tertiaryText)
                            if !rate.countsAsDamage {
                                Text(rate.conditionalDamage ? "（需满足条件，不计入）" : "（不计入伤害乘积）")
                                    .font(.system(size: 10))
                                    .foregroundStyle(AppTheme.tertiaryText)
                            }
                            Spacer(minLength: 0)
                        }
                    }
                }
            }

            if !row.channelFactors.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    Text("各伤害类型倍率 × 当前占比")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(AppTheme.tertiaryText)
                    ForEach(row.channelFactors) { factor in
                        HStack(spacing: 6) {
                            RoundedRectangle(cornerRadius: 2, style: .continuous)
                                .fill(RankerPalette.color(factor.channel))
                                .frame(width: 8, height: 8)
                            Text(factor.channel.titleZh)
                                .font(.system(size: 11))
                                .frame(width: 76, alignment: .leading)
                            Text(BuffFormat.multiplier(factor.factor))
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(factor.factor > 1 ? AppTheme.green : AppTheme.secondaryText)
                            Text("× 占比 " + BuffFormat.percent(factor.share))
                                .font(.system(size: 10))
                                .foregroundStyle(AppTheme.tertiaryText)
                            Spacer(minLength: 0)
                        }
                    }
                }
            }

            ForEach(row.scopeNotes, id: \.self) { note in
                RankerDetailRow(label: "生效范围", value: note, tint: AppTheme.secondaryText)
            }
            ForEach(row.conditionNotes, id: \.self) { note in
                RankerDetailRow(label: "发动条件", value: note, tint: AppTheme.amber)
            }
            if !row.sourceNames.isEmpty {
                RankerDetailRow(label: "来源", value: row.sourceNames.joined(separator: "、"), tint: AppTheme.secondaryText)
            }
            if let desc = row.descZh {
                RankerDetailRow(label: "说明", value: desc, tint: AppTheme.secondaryText)
            }
            if let ladder = row.ladder {
                RankerDetailRow(
                    label: "叠层",
                    value: "\(ladder.tierText)，数据集只收录第 1 层；满层 "
                        + BuffFormat.multiplier(ladder.topMultiplier)
                        + (ladder.saved ? "（层数跨局保留）" : "（层数本局有效）"),
                    tint: AppTheme.amber
                )
            }
            RankerDetailRow(
                label: "叠加",
                value: "\(row.stackGroup) · \(dataset.stackBehaviorLabel(row.stackBehavior))"
                    + " · spCategory \(row.spCategory) · stateInfo \(row.stateInfoLabel)",
                tint: AppTheme.secondaryText
            )
            RankerDetailRow(
                label: "参数行",
                value: (row.paramName ?? "—") + " · SpEffect #\(row.spEffectId)",
                tint: AppTheme.tertiaryText
            )
        }
        .padding(.leading, 38)
        .padding(.top, 2)
    }
}

/// 折叠区。
struct RankerDisclosure<Content: View>: View {
    let title: String
    @Binding var isOn: Bool
    let content: () -> Content

    init(title: String, isOn: Binding<Bool>, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self._isOn = isOn
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                isOn.toggle()
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(AppTheme.tertiaryText)
                        .rotationEffect(.degrees(isOn ? 90 : 0))
                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isOn {
                content()
                    .padding(.leading, 17)
            }
        }
    }
}
