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
                        Text(segment.displayLabelZh)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(segment.noDamage ? AppTheme.tertiaryText : .white)
                        if segment.isBullet {
                            Pill(text: "子弹", color: Color(red: 0.55, green: 0.78, blue: 0.99))
                        }
                        if segment.noFp {
                            Pill(text: "专注值不足版", color: AppTheme.amber)
                        }
                        if segment.noDamage {
                            Pill(text: "只挂状态", color: AppTheme.tertiaryText)
                        }
                        Spacer(minLength: 0)
                        Text("#\(segment.atkId)")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(AppTheme.tertiaryText)
                    }

                    // 只列对当前武器真正有贡献的通道（见 SkillSegment.visibleComponents）；
                    // 确有被隐藏项时在行末补一句很淡的小字，与 Windows 端同文。
                    HStack(spacing: 6) {
                        let shown = segment.visibleComponents
                        ForEach(shown) { component in
                            componentChip(component)
                        }
                        if shown.isEmpty {
                            Text("无伤害数值")
                                .font(.system(size: 11))
                                .foregroundStyle(AppTheme.tertiaryText)
                        } else if segment.hiddenZeroComponentCount > 0 {
                            Text("其余属性该武器为 0")
                                .font(.system(size: 10))
                                .foregroundStyle(AppTheme.tertiaryText)
                                .opacity(0.62)
                        }
                    }

                    HStack(spacing: 12) {
                        metric("削韧", BuffFormat.trim(segment.poise, digits: 1))
                            .help("对敌人韧性（削韧槽）的削减量")
                        metric("削精力", BuffFormat.trim(segment.stamina, digits: 1))
                            .help("对格挡中敌人精力条的削减量（武器基础精力伤害 × 动作值），与角色自己的精力无关")
                        // 物理这一项也按「真正有贡献」显示：法术段的 physicalChannel 来自
                        // 占位写法的 motion，不该在没有物理芯片时还挂一个物理类型。
                        if let channel = segment.physicalChannel,
                           segment.visibleComponents.contains(where: { $0.channel == channel }) {
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
