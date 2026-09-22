import SwiftUI
import RelicCore

// 「首领数据」页的小组件与数值格式化。样式沿用 Theme.swift 的 AppTheme。

enum BossFormat {
    /// 整数带千位分隔：11328 → 11,328。
    static func integer(_ value: Int) -> String {
        value.formatted(.number.grouping(.automatic))
    }

    /// 去掉多余 0 的小数：1.350 → 1.35，2.0 → 2。
    static func decimal(_ value: Double, digits: Int = 2) -> String {
        guard value.isFinite else { return "—" }
        var text = String(format: "%.\(digits)f", value)
        if text.contains(".") {
            while text.hasSuffix("0") { text.removeLast() }
            if text.hasSuffix(".") { text.removeLast() }
        }
        return text.isEmpty ? "0" : text
    }

    /// 倍率：×1.35。
    static func multiplier(_ value: Double, digits: Int = 3) -> String {
        "×" + decimal(value, digits: digits)
    }

    /// 承伤 / 异常倍率的配色：> 1 绿（弱点）、< 1 红（抗性）、= 1 中性。
    static func rateColor(_ value: Double) -> Color {
        if value > 1.0001 { return AppTheme.green }
        if value < 0.9999 { return AppTheme.red }
        return AppTheme.secondaryText
    }

    static func rateTag(_ value: Double) -> String? {
        if value > 1.0001 { return "弱点" }
        if value < 0.9999 { return "抗性" }
        return nil
    }
}

/// 卡片头部 / 行内的一个数值块。
struct BossMetric: View {
    let title: String
    let value: String
    var caption: String? = nil
    var tint: Color = .white
    var width: CGFloat? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(AppTheme.tertiaryText)
            Text(value)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(tint)
            if let caption {
                Text(caption)
                    .font(.system(size: 10))
                    .foregroundStyle(AppTheme.tertiaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(width: width, alignment: .leading)
    }
}

/// 八种承伤倍率里的一格。`title` 由调用方从数据集的 affinityNames 取，避免硬编码漂移。
struct BossRateCell: View {
    let title: String
    let value: Double

    var body: some View {
        VStack(spacing: 3) {
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(AppTheme.secondaryText)
            Text(BossFormat.decimal(value))
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(BossFormat.rateColor(value))
            Text(BossFormat.rateTag(value) ?? "—")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(BossFormat.rateTag(value) == nil ? AppTheme.tertiaryText : BossFormat.rateColor(value))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(BossFormat.rateColor(value).opacity(value == 1 ? 0.04 : 0.10))
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title)承伤倍率 \(BossFormat.decimal(value))")
    }
}

/// 一种异常抗性（999 = 免疫）。
struct BossResistCell: View {
    let title: String
    let value: Int
    let immune: Bool

    var body: some View {
        VStack(spacing: 3) {
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(AppTheme.secondaryText)
            Text(immune ? "免疫" : BossFormat.integer(value))
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(immune ? AppTheme.red : .white)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(immune ? AppTheme.red.opacity(0.10) : Color.white.opacity(0.03))
        )
    }
}

/// 折叠区里的小标题。
struct BossSubHeading: View {
    let title: String
    var detail: String? = nil

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
            if let detail {
                Text(detail)
                    .font(.system(size: 10))
                    .foregroundStyle(AppTheme.tertiaryText)
            }
            Spacer(minLength: 0)
        }
    }
}

/// 「标签 / 值」一行，用于缩放明细。
struct BossDetailRow: View {
    let label: String
    let value: String
    var tint: Color = .white

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(AppTheme.secondaryText)
            Spacer(minLength: 6)
            Text(value)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(tint)
        }
    }
}

/// 人数档位的倍率明细（血量 / 削韧 / 异常）。
struct BossTierDetail: View {
    let title: String
    let tier: BossScalingTier
    var highlighted: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(highlighted ? AppTheme.purpleSoft : AppTheme.secondaryText)
                if highlighted {
                    Text("当前")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(AppTheme.purpleSoft)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(AppTheme.purple.opacity(0.16), in: Capsule())
                }
                Spacer(minLength: 0)
            }
            BossDetailRow(label: "血量", value: BossFormat.multiplier(tier.hp))
            BossDetailRow(label: "承受削韧", value: BossFormat.multiplier(tier.poiseTaken))
            BossDetailRow(label: "削韧恢复速度", value: BossFormat.multiplier(tier.poiseRecover))
            BossDetailRow(label: "异常发动伤害", value: BossFormat.multiplier(tier.ailmentDamageRate))
            BossDetailRow(label: "异常累积量", value: BossFormat.multiplier(tier.buildupRate))
            BossDetailRow(label: "中毒 / 腐败发动伤害", value: BossFormat.multiplier(tier.poisonRate))
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(highlighted ? AppTheme.purple.opacity(0.10) : Color.white.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(highlighted ? AppTheme.purple.opacity(0.28) : AppTheme.border, lineWidth: 1)
                )
        )
    }
}

/// 常驻缩放 SpEffect 的一条明细。
struct BossPermanentEffectRow: View {
    let effect: BossPermanentEffect

    private var parts: [String] {
        var items: [String] = []
        if effect.hp != 1 { items.append("血量 " + BossFormat.multiplier(effect.hp, digits: 4)) }
        if effect.poiseTaken != 1 { items.append("承受削韧 " + BossFormat.multiplier(effect.poiseTaken, digits: 4)) }
        if effect.poiseRecover != 1 { items.append("削韧恢复 " + BossFormat.multiplier(effect.poiseRecover, digits: 4)) }
        if effect.ailmentDamageRate != 1 { items.append("异常发动伤害 " + BossFormat.multiplier(effect.ailmentDamageRate, digits: 4)) }
        return items
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("#\(effect.id)")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(AppTheme.tertiaryText)
                .frame(width: 52, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(effect.displayName)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                    if effect.deepOfNight {
                        Text("仅深夜")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(AppTheme.amber)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(AppTheme.amber.opacity(0.14), in: Capsule())
                    }
                }
                Text(parts.isEmpty ? "无数值改动" : parts.joined(separator: " · "))
                    .font(.system(size: 10))
                    .foregroundStyle(AppTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }
}
