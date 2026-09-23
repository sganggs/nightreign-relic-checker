import SwiftUI
import RelicCore

// 「首领数据」页里深夜 · 深度与变异个体相关的小组件。
// 与 BossDataComponents.swift 拆开只是为了别让单个文件太长，样式口径完全一致。

// MARK: - 深夜 · 深度

/// 展开区的「深夜各深度」小表：深度 1–5 的血量 / 攻击倍率 / 承受削韧 / 有效韧性。
///
/// 这是 v2 最大的缺口：v2 的 `deepOfNight` 只算到「深夜修正」，没乘深度倍率，
/// 于是页面上「深夜」看起来只是换了个数，深度 1 和深度 5 毫无区别。
struct BossDepthTable: View {
    let rows: [BossFight.DepthRow]
    /// 当前选中的深度（常规模式为 nil），用来高亮。
    let currentDepth: Int?
    /// 说明这张小表是按什么条件换算出来的（人数、变异档位）。
    let caption: String
    /// 「深度」的游戏内文本词。
    let depthWord: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            BossSubHeading(title: "深夜各深度", detail: caption)
            if rows.isEmpty {
                Text(BossRowText.noDepthStatsText)
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.tertiaryText)
            } else {
                VStack(spacing: 0) {
                    headerRow
                    ForEach(rows) { row in
                        valueRow(row)
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.white.opacity(0.03))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(AppTheme.border, lineWidth: 1)
                        )
                )
            }
        }
    }

    private var headerRow: some View {
        HStack(spacing: 8) {
            cell(depthWord, width: 66, weight: .semibold, tint: AppTheme.tertiaryText)
            cell("血量", width: 92, weight: .semibold, tint: AppTheme.tertiaryText, alignment: .trailing)
            cell("攻击倍率", width: 86, weight: .semibold, tint: AppTheme.tertiaryText, alignment: .trailing)
            cell("承受削韧", width: 86, weight: .semibold, tint: AppTheme.tertiaryText, alignment: .trailing)
            cell("有效韧性", width: 86, weight: .semibold, tint: AppTheme.tertiaryText, alignment: .trailing)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    private func valueRow(_ row: BossFight.DepthRow) -> some View {
        let isCurrent = currentDepth == row.depth
        return HStack(spacing: 8) {
            cell("\(depthWord) \(row.depth)", width: 66,
                 weight: isCurrent ? .bold : .regular,
                 tint: isCurrent ? AppTheme.purpleSoft : AppTheme.secondaryText)
            cell(BossFormat.integer(row.hp), width: 92, weight: .semibold,
                 tint: isCurrent ? AppTheme.purpleSoft : .white, alignment: .trailing)
            // 攻击力涨得比血量快得多（最终 Boss 档深度 5 的伤害是深度 1 的 2.27 倍），
            // 只列血量会严重低估深夜难度，所以这一列必须在。
            cell(BossFormat.multiplier(row.attackRate, digits: 3), width: 86,
                 tint: AppTheme.red, alignment: .trailing)
            cell(BossFormat.multiplier(row.poiseTaken, digits: 3), width: 86,
                 tint: AppTheme.secondaryText, alignment: .trailing)
            cell(row.effectivePoise.map { BossFormat.decimal($0, digits: 1) } ?? "—", width: 86,
                 tint: AppTheme.secondaryText, alignment: .trailing)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(isCurrent ? AppTheme.purple.opacity(0.10) : Color.clear)
    }

    private func cell(
        _ text: String, width: CGFloat, weight: Font.Weight = .regular,
        tint: Color = .white, alignment: Alignment = .leading
    ) -> some View {
        Text(text)
            .font(.system(size: 11, weight: weight, design: .rounded))
            .foregroundStyle(tint)
            .frame(width: width, alignment: alignment)
    }
}

/// 夜王展开区的「各深度出现权重」。权重 0 = 该深度打不到这个形态
/// （永夜之王与救世旗手在深度 1 全是 0）。
struct BossDepthChanceRow: View {
    let weights: [(depth: Int, weight: Int)]
    let depthWord: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            BossSubHeading(
                title: "各深度出现权重",
                detail: "NightBossMenuParam.depth1..5ChanceWeight；权重是相对值，不是百分比"
            )
            HStack(alignment: .top, spacing: 8) {
                ForEach(weights, id: \.depth) { item in
                    VStack(spacing: 3) {
                        Text("\(depthWord) \(item.depth)")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(AppTheme.secondaryText)
                        Text(item.weight <= 0 ? "—" : "\(item.weight)")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(item.weight <= 0 ? AppTheme.tertiaryText : .white)
                        Text(item.weight <= 0 ? BossRowText.depthWeightZero : "权重")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(item.weight <= 0 ? AppTheme.amber : AppTheme.tertiaryText)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(item.weight <= 0 ? AppTheme.amber.opacity(0.07) : Color.white.opacity(0.03))
                    )
                }
            }
        }
    }
}

/// 底部折叠区的深度概览：诅咒遗物率、地图挑战权重、天变数量权重。
struct BossDepthOverview: View {
    let infos: [BossDepthInfo]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // ChaosMatchingRankControlParam 只管全局控制，一个血量 / 攻击倍率都没有——
            // 想看深度对数值的影响得看每一行的「深夜各深度」小表。
            Text("下面这张表来自 ChaosMatchingRankControlParam，只有全局控制项，"
                 + "不含任何血量 / 攻击力倍率；深度对数值的影响请看每条数值行展开后的「深夜各深度」。")
                .font(.system(size: 11))
                .foregroundStyle(AppTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            ForEach(infos) { info in
                VStack(alignment: .leading, spacing: 3) {
                    Text(info.title)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                    BossDetailRow(
                        label: "诅咒遗物率（罕见 / 稀有）",
                        value: BossFormat.decimal(info.cursedUncommonRate, digits: 2)
                            + " / " + BossFormat.decimal(info.cursedRareRate, digits: 2),
                        tint: AppTheme.secondaryText
                    )
                    BossDetailRow(
                        label: "地图挑战权重（地图 / 夜王 / 无）",
                        value: BossFormat.decimal(info.mapChallengeWeight.map, digits: 2)
                            + " / " + BossFormat.decimal(info.mapChallengeWeight.nightlord, digits: 2)
                            + " / " + BossFormat.decimal(info.mapChallengeWeight.none, digits: 2),
                        tint: AppTheme.secondaryText
                    )
                    BossDetailRow(
                        label: "天变数量权重（0 / 1 / 2）",
                        value: (0...2).map { String(info.cataclysmWeight[$0] ?? 0) }.joined(separator: " / "),
                        tint: AppTheme.secondaryText
                    )
                }
                .padding(.vertical, 2)
            }
        }
    }
}

// MARK: - 变异个体

/// 展开区的「变异个体」块：可能的档位清单 + 「按变异个体计算」下拉。
struct BossMutationSection: View {
    /// 标题用 deepOfNightText 的游戏文本（「变异个体」），不要写社区叫法「红化」。
    let title: String
    let pool: [BossMutation]
    @Binding var selectedId: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            BossSubHeading(title: title, detail: BossRowText.mutationStackNote)

            HStack(spacing: 8) {
                Text(BossRowText.mutationPickerTitle)
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.secondaryText)
                Picker(BossRowText.mutationPickerTitle, selection: $selectedId) {
                    Text(BossRowText.mutationPickerNone).tag(Int?.none)
                    ForEach(pool) { mutation in
                        Text(mutation.pickerTitle).tag(Int?.some(mutation.id))
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(maxWidth: 340)
                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: 4) {
                ForEach(pool) { mutation in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(verbatim: "#\(mutation.id)")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(selectedId == mutation.id ? AppTheme.red : AppTheme.tertiaryText)
                            .frame(width: 58, alignment: .leading)
                        Text(mutation.summary)
                            .font(.system(size: 11))
                            .foregroundStyle(selectedId == mutation.id ? .white : AppTheme.secondaryText)
                        if let statName = mutation.statNameEn {
                            Text(statName)
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(AppTheme.tertiaryText)
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
            .padding(9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(AppTheme.red.opacity(selectedId == nil ? 0.04 : 0.09))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(AppTheme.red.opacity(selectedId == nil ? 0.12 : 0.26), lineWidth: 1)
                    )
            )
        }
    }
}

/// 底部折叠区的「变异个体出现只数」表：地图 × 深度 → 只数。
struct BossMutationCountTable: View {
    let categories: [BossMutationCategory]
    let depthWord: String

    private var grouped: [(category: String, rows: [BossMutationCategory])] {
        var order: [Int] = []
        var buckets: [Int: [BossMutationCategory]] = [:]
        for item in categories {
            if buckets[item.categoryId] == nil { order.append(item.categoryId) }
            buckets[item.categoryId, default: []].append(item)
        }
        return order.map { (buckets[$0]?.first?.categoryTitle ?? "#\($0)", buckets[$0] ?? []) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // 这是「有几只被变异」的个数，不是百分比概率——最容易被误读的一项。
            Text(BossRowText.mutationCountNote)
                .font(.system(size: 11))
                .foregroundStyle(AppTheme.amber)
                .fixedSize(horizontal: false, vertical: true)

            ForEach(Array(grouped.enumerated()), id: \.offset) { item in
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.element.category)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                    HStack(spacing: 8) {
                        Text("地图")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(AppTheme.tertiaryText)
                            .frame(width: 104, alignment: .leading)
                        ForEach(1...5, id: \.self) { depth in
                            Text("\(depthWord) \(depth)")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(AppTheme.tertiaryText)
                                .frame(width: 54, alignment: .trailing)
                        }
                        Spacer(minLength: 0)
                    }
                    ForEach(item.element.rows) { row in
                        HStack(spacing: 8) {
                            Text(row.mapTitle)
                                .font(.system(size: 11))
                                .foregroundStyle(AppTheme.secondaryText)
                                .frame(width: 104, alignment: .leading)
                            ForEach(1...5, id: \.self) { depth in
                                let count = row.count(atDepth: depth)
                                Text("\(count)")
                                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                                    .foregroundStyle(count == 0 ? AppTheme.tertiaryText : .white)
                                    .frame(width: 54, alignment: .trailing)
                            }
                            Spacer(minLength: 0)
                        }
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }
}
