import SwiftUI
import RelicCore

// 「角色属性」页的小组件与数值格式化。样式沿用 Theme.swift 的 AppTheme，
// 本文件只补一个「颜色码 → 展示色」的表（数据集给的是 0–4），取值与
// SaveRelicCard.colorPill 保持一致；颜色**文案**不在这里造，走 RelicCore 的
// relicColorLabel（HeroRelicItem.colorText），与遗物卡 / 报告 / CSV 同一份口径。

enum HeroFormat {
    /// 属性值：整数直接显示；派生值里的负重上限保留 1 位小数。
    static func value(_ value: Double, integer: Bool) -> String {
        integer ? String(Int(value.rounded())) : HeroStatsText.decimal(value)
    }

    /// 增减量配色：涨绿、跌红、不变中性。
    static func deltaColor(_ delta: Double) -> Color {
        if delta > 0.0001 { return AppTheme.green }
        if delta < -0.0001 { return AppTheme.red }
        return AppTheme.secondaryText
    }

    /// 遗物颜色码（0 红 / 1 蓝 / 2 黄 / 3 绿 / 4 白）→ 展示色。
    /// 取值与 SaveRelicCard.colorPill 逐项一致（蓝色同为 0.38/0.60/0.98），
    /// 颜色文案则统一走 RelicCore 的 relicColorLabel（见 HeroRelicItem.colorText），
    /// 别在这里另写一份，否则同一个颜色在两个页面上会漂移。
    static func relicColor(_ code: Int) -> Color {
        switch code {
        case 0: return AppTheme.red
        case 1: return Color(red: 0.38, green: 0.60, blue: 0.98)
        case 2: return AppTheme.amber
        case 3: return AppTheme.green
        case 4: return Color.white.opacity(0.72)
        default: return AppTheme.secondaryText
        }
    }
}

// MARK: - 角色选择

/// 角色卡片：中文名 + 英文副标题。
struct HeroPickerChip: View {
    let hero: HeroEntry
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 2) {
                Text(hero.nameZh.isEmpty ? hero.nameEn : hero.nameZh)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.white : AppTheme.secondaryText)
                Text(hero.nameEn)
                    .font(.system(size: 10))
                    .foregroundStyle(isSelected ? Color.white.opacity(0.75) : AppTheme.tertiaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? AppTheme.purple.opacity(0.85) : AppTheme.field)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isSelected ? AppTheme.purpleSoft : AppTheme.border, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 单等级属性卡片

/// 一项属性 / 派生值的大数字卡片：未修改时只显示一个数字，
/// 修改后显示「基础 → 修改后」并用绿 / 红标出增减量。
struct HeroStatTile: View {
    let title: String
    let base: Double
    let final: Double
    let integer: Bool
    /// 属性被钳到下限时标出来。
    var clamped: Bool = false
    var caption: String? = nil

    private var delta: Double { final - base }
    private var changed: Bool { abs(delta) > 0.0001 }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppTheme.tertiaryText)
                Spacer(minLength: 0)
                if changed {
                    Text(HeroStatsText.signed(delta, digits: integer ? 0 : 1))
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(HeroFormat.deltaColor(delta))
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if changed {
                    Text(HeroFormat.value(base, integer: integer))
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(AppTheme.tertiaryText)
                        .strikethrough(color: AppTheme.tertiaryText)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(AppTheme.tertiaryText)
                }
                Text(HeroFormat.value(final, integer: integer))
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(changed ? HeroFormat.deltaColor(delta) : .white)
            }
            if clamped {
                Text("已钳到下限 1")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(AppTheme.amber)
            } else if let caption {
                Text(caption)
                    .font(.system(size: 9))
                    .foregroundStyle(AppTheme.tertiaryText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(AppTheme.field)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(changed ? HeroFormat.deltaColor(delta).opacity(0.35) : AppTheme.border, lineWidth: 1)
        )
    }
}

// MARK: - 转职遗物

/// 一条转职遗物词条：可勾选，右侧小字是携带它的遗物名与颜色。
struct HeroModifierToggleRow: View {
    let modifier: HeroStatModifier
    let isOn: Bool
    let statNames: HeroStatNames
    let level: Int
    let anchorLevels: [Int]
    let delta: [String: Int]
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: isOn ? "checkmark.square.fill" : "square")
                    .font(.system(size: 15))
                    .foregroundStyle(isOn ? AppTheme.purpleSoft : AppTheme.tertiaryText)
                    .padding(.top, 1)

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 7) {
                        Text(modifier.shortName)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(isOn ? .white : AppTheme.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                            .multilineTextAlignment(.leading)
                        if let tag = HeroStatsText.inferenceTag(level: level, anchorLevels: anchorLevels) {
                            // 标的是「本级增减量的来历」，与勾没勾无关
                            Pill(text: "本级" + tag, color: tag == "推算" ? AppTheme.amber : AppTheme.green)
                        }
                        if modifier.dlcOnly {
                            Pill(text: "仅 DLC 权重", color: AppTheme.purpleSoft)
                        }
                    }

                    // 当前等级的增减量
                    if delta.isEmpty {
                        Text("本级无增减量数据")
                            .font(.system(size: 10))
                            .foregroundStyle(AppTheme.tertiaryText)
                    } else {
                        HStack(spacing: 8) {
                            ForEach(statNames.attributeKeys.filter { delta[$0] != nil }, id: \.self) { key in
                                let value = delta[key] ?? 0
                                HStack(spacing: 3) {
                                    Text(statNames.attributeTitle(key))
                                        .font(.system(size: 10))
                                        .foregroundStyle(AppTheme.tertiaryText)
                                    Text(HeroStatsText.signed(value))
                                        .font(.system(size: 11, weight: .bold, design: .rounded))
                                        .foregroundStyle(HeroFormat.deltaColor(Double(value)))
                                }
                            }
                        }
                    }

                    // 携带该词条的遗物
                    HStack(spacing: 8) {
                        ForEach(modifier.relicItems) { item in
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(HeroFormat.relicColor(item.color))
                                    .frame(width: 7, height: 7)
                                Text(item.display)
                                    .font(.system(size: 10))
                                    .foregroundStyle(AppTheme.secondaryText)
                                Text(item.colorText)
                                    .font(.system(size: 9))
                                    .foregroundStyle(HeroFormat.relicColor(item.color))
                            }
                        }
                        if modifier.relicItems.isEmpty {
                            Text("数据未内置携带它的遗物")
                                .font(.system(size: 10))
                                .foregroundStyle(AppTheme.tertiaryText)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(isOn ? AppTheme.purple.opacity(0.11) : AppTheme.field)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(isOn ? AppTheme.purpleSoft.opacity(0.45) : AppTheme.border, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 表格

/// 表头单元格；`onTap` 不为空时可点击排序。
struct HeroHeaderCell: View {
    let title: String
    var width: CGFloat
    var alignment: Alignment = .trailing
    var sortState: HeroSortState = .none
    var onTap: (() -> Void)? = nil

    enum HeroSortState {
        case none, ascending, descending

        var symbol: String? {
            switch self {
            case .none: return nil
            case .ascending: return "chevron.up"
            case .descending: return "chevron.down"
            }
        }
    }

    var body: some View {
        let content = HStack(spacing: 3) {
            if alignment == .trailing { Spacer(minLength: 0) }
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(sortState == .none ? AppTheme.tertiaryText : AppTheme.purpleSoft)
                .lineLimit(1)
            if let symbol = sortState.symbol {
                Image(systemName: symbol)
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(AppTheme.purpleSoft)
            }
            if alignment == .leading { Spacer(minLength: 0) }
        }
        .frame(width: width, alignment: alignment)

        if let onTap {
            Button(action: onTap) { content.contentShape(Rectangle()) }
                .buttonStyle(.plain)
                .help("点击按该列排序")
        } else {
            content
        }
    }
}

/// 表格里的一格数值。
struct HeroValueCell: View {
    let text: String
    var width: CGFloat
    var tint: Color = .white
    var weight: Font.Weight = .medium
    var alignment: Alignment = .trailing

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: weight, design: .rounded))
            .foregroundStyle(tint)
            .lineLimit(1)
            .frame(width: width, alignment: alignment)
    }
}

/// 折叠区（与首领数据页同一种写法）。
struct HeroDisclosure<Content: View>: View {
    let title: String
    @Binding var isOn: Bool
    @ViewBuilder var content: () -> Content

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

/// 底部说明里的一行「标签：值」。
struct HeroDetailRow: View {
    let label: String
    let value: String
    var tint: Color = .white

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(AppTheme.tertiaryText)
                .frame(width: 120, alignment: .leading)
            Text(value)
                .font(.system(size: 11))
                .foregroundStyle(tint)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// 一条带项目符号的说明文字。
struct HeroBulletText: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 7) {
            Text("·")
                .foregroundStyle(AppTheme.tertiaryText)
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(AppTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}
