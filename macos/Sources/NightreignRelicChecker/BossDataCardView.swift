import SwiftUI
import RelicCore

// 「首领数据」页的首领卡片：折叠时显示主战行概览，展开后逐行列出全部战斗记录。

struct BossCardView: View {
    let card: BossCard
    /// 当前所在的分组区块。同一张卡片可能同时出现在「守夜」与「野外」两个区块里，
    /// 折叠态的代表行必须跟着分组走（野外区块就看野外那几行），不能恒取 rows[0]。
    let group: BossCard.Group
    let index: BossDataIndex
    let players: BossPartySize
    let deepOfNight: Bool
    let isExpanded: Bool
    let onToggle: () -> Void

    private var primary: BossFight? { card.representativeRow(in: group) }

    /// 该分组下参与评选的候选行（守夜 / 野外先按 threat 过滤，夜王收敛到 isMain）。
    private var candidates: [BossFight] { card.rows(in: group) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: onToggle) {
                header
            }
            .buttonStyle(.plain)

            if isExpanded {
                Divider().overlay(AppTheme.border)
                expandedBody
                    .padding(.top, 12)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(AppTheme.card)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(isExpanded ? AppTheme.borderStrong : AppTheme.border, lineWidth: 1)
                )
        )
    }

    // MARK: 折叠态

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(card.displayName)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                    if !card.nameEn.isEmpty, card.nameEn != card.displayName {
                        Text(card.nameEn)
                            .font(.system(size: 11))
                            .foregroundStyle(AppTheme.tertiaryText)
                    }
                }
                badges
                weaknessNote
                primaryRowNote
            }
            Spacer(minLength: 8)
            if let primary {
                summaryMetrics(for: primary)
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(AppTheme.tertiaryText)
                .rotationEffect(.degrees(isExpanded ? 90 : 0))
                .padding(.top, 4)
        }
        .contentShape(Rectangle())
    }

    private var badges: some View {
        HStack(spacing: 6) {
            switch card.group {
            case .nightlord:
                if !card.expeditionZh.isEmpty {
                    Pill(text: "远征 · " + card.expeditionZh, color: AppTheme.purpleSoft)
                }
                if !card.variantNameZh.isEmpty {
                    Pill(text: card.variantNameZh, color: card.isEverdark ? AppTheme.amber : AppTheme.purpleSoft)
                }
                weaknessBadge
            case .night, .field:
                // tiers 可能同时含守夜与野外：两个徽标都挂上，别让用户以为只有一种档位。
                ForEach(card.groups) { group in
                    Pill(
                        text: group.title,
                        color: group == .night ? AppTheme.purpleSoft : AppTheme.secondaryText,
                        symbol: group.symbol
                    )
                }
                nameSourceBadge
            }
            // 深夜徽标扫描整卡：首条代表行没有深夜值，不代表整张卡都没有。
            if deepOfNight, let text = card.deepCoverage.badgeText {
                Pill(text: text, color: AppTheme.amber, symbol: "moon.fill")
            }
            Text("\(card.rows.count) 条战斗记录")
                .font(.system(size: 10))
                .foregroundStyle(AppTheme.tertiaryText)
        }
    }

    /// 折叠态头条数值取自哪一行。两种情况都必须写清楚，否则同一张卡里差几倍的数值
    /// 会被当成算错：夜王的 `isMain` 不唯一（多阶段 / 多体有 2～5 条），
    /// 守夜 / 野外的候选行则随分组切换（同一组首领可能两种档位都有）。
    @ViewBuilder
    private var primaryRowNote: some View {
        if let primary {
            let pool = candidates
            // 只有「代表行本身有歧义」的卡片才铺开列全部候选行：夜王有多条 isMain，
            // 或同时属于守夜与野外的组（同一张卡在两个分组下给的是不同的行）。
            let ambiguous = card.group == .nightlord ? card.hasMultipleMainRows : card.groups.count > 1
            if ambiguous, pool.count > 1 {
                let list = pool
                    .map { "\($0.displayLabel) \(BossFormat.integer($0.hp(for: players, deepOfNight: deepOfNight)))" }
                    .joined(separator: " · ")
                let lead = card.group == .nightlord
                    ? "\(pool.count) 条主战行，上方取血量最高的一条："
                    : "该分组 \(pool.count) 条数值行，上方取血量最高的一条："
                Text(lead + list)
                    .font(.system(size: 10))
                    .foregroundStyle(AppTheme.amber)
                    .fixedSize(horizontal: false, vertical: true)
            } else if card.rows.count > 1 {
                Text("代表行：\(primary.displayLabel)（共 \(card.rows.count) 组，展开看全部）")
                    .font(.system(size: 10))
                    .foregroundStyle(AppTheme.tertiaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// weakness（NightBossMenuParam 的菜单弱点标注）只有夜王有：守夜 / 野外首领的数据里
    /// 根本没有这个字段，所以绝不能显示「官方标注：无弱点」——那是把「数据里没有」
    /// 说成「官方说没有」。它们改为给出代表行里承伤偏高的属性（页面自己按 damageRates 算的）。
    @ViewBuilder
    private var weaknessNote: some View {
        if card.group != .nightlord {
            let hot = primary.map { BossCardView.topDamageKinds($0) } ?? []
            if hot.isEmpty {
                Text("本作只给夜王官方弱点标注；展开看承伤倍率")
                    .font(.system(size: 10))
                    .foregroundStyle(AppTheme.tertiaryText)
            } else {
                HStack(spacing: 6) {
                    Text("代表行承伤偏高")
                        .font(.system(size: 10))
                        .foregroundStyle(AppTheme.tertiaryText)
                    ForEach(hot) { item in
                        Pill(
                            text: index.dataset.title(for: item.kind) + " "
                                + BossFormat.multiplier(item.rate, digits: 2),
                            color: AppTheme.amber
                        )
                    }
                }
            }
        }
    }

    /// 代表行里某个属性的承伤倍率。
    struct HotRate: Identifiable {
        let kind: BossDamageKind
        let rate: Double
        var id: String { kind.rawValue }
    }

    /// 代表行里承伤倍率 > 1 的属性，按倍率降序取前三个（与 Windows 端 topDamageTypes 同口径）。
    static func topDamageKinds(_ row: BossFight, limit: Int = 3) -> [HotRate] {
        row.damageRates.weakKinds.prefix(limit).map {
            HotRate(kind: $0, rate: row.damageRates.value(for: $0))
        }
    }

    @ViewBuilder
    private var weaknessBadge: some View {
        if card.weakness.isEmpty {
            Pill(text: "官方标注：无弱点", color: AppTheme.tertiaryText, symbol: "minus.circle")
        } else {
            ForEach(card.weakness) { weakness in
                Pill(text: "官方弱点 · " + weakness.display, color: AppTheme.green, symbol: "target")
            }
        }
    }

    @ViewBuilder
    private var nameSourceBadge: some View {
        if let badge = card.nameBadge {
            Pill(text: badge.text, color: AppTheme.amber)
        }
    }

    /// 主战行不止一条时标明头条取的是最高那条，别让用户以为「这只 Boss 就这点血」。
    private var hpMetricTitle: String {
        guard card.group == .nightlord else { return "血量" }
        return card.hasMultipleMainRows ? "主战血量 · 最高" : "主战血量"
    }

    /// 深夜开着但代表行没有深夜专属缩放时，要直说这一行回落到了常规值，
    /// 否则摘要与卡头的「部分行有深夜数值」徽标看着像在互相打架。
    private func hpCaption(_ stats: BossComputedStats, row: BossFight) -> String {
        if deepOfNight {
            guard row.hasDeepOfNight else { return "该行深夜同常规" }
            return players == .solo ? "深夜数值" : "深夜 1 人 \(BossFormat.integer(row.deepOfNight?.hp ?? row.hp))"
        }
        return players == .solo ? "含常驻缩放" : "1 人 \(BossFormat.integer(row.hp))"
    }

    private func summaryMetrics(for row: BossFight) -> some View {
        let stats = row.stats(for: players, deepOfNight: deepOfNight)
        return HStack(alignment: .top, spacing: 18) {
            BossMetric(
                title: "\(hpMetricTitle)（\(players.title)）",
                value: BossFormat.integer(stats.hp),
                caption: hpCaption(stats, row: row),
                tint: AppTheme.purpleSoft,
                width: 128
            )
            BossMetric(
                title: "有效韧性",
                value: stats.effectivePoise.map { BossFormat.decimal($0, digits: 1) } ?? stats.poiseKind.placeholder,
                caption: stats.effectivePoise == nil ? nil : "韧性槽 \(BossFormat.decimal(row.poise, digits: 0))",
                width: 84
            )
            BossMetric(
                title: "削韧恢复",
                value: BossFormat.decimal(stats.poiseRecover, digits: 3),
                caption: "每秒",
                width: 68
            )
        }
    }

    // MARK: 展开态

    /// 守夜 / 野外首领的 chrId 与 NpcName ID：对着 Paramdex / 存档工具查行时要用。
    @ViewBuilder
    private var identifierNote: some View {
        if card.group != .nightlord, !card.chrIds.isEmpty || card.npcNameId != nil {
            HStack(spacing: 12) {
                if !card.chrIds.isEmpty {
                    Text("chrId " + card.chrIds.map(String.init).joined(separator: " / "))
                }
                if let npcNameId = card.npcNameId {
                    Text("NpcName #\(npcNameId)")
                }
                if !card.nameSource.isEmpty {
                    Text("名称来源 " + card.nameSource)
                }
                Spacer(minLength: 0)
            }
            .font(.system(size: 10, design: .monospaced))
            .foregroundStyle(AppTheme.tertiaryText)
        }
    }

    private var expandedBody: some View {
        VStack(alignment: .leading, spacing: 14) {
            identifierNote
            if !card.descriptionZh.isEmpty {
                Text(card.descriptionZh)
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.white.opacity(0.03))
                    )
            }

            ForEach(card.rows) { row in
                BossFightRowView(
                    row: row,
                    index: index,
                    players: players,
                    deepOfNight: deepOfNight,
                    isNightlord: card.group == .nightlord
                )
            }
        }
    }
}

/// 单条战斗记录：数值概览 + 八种承伤倍率 + 异常抗性 + 缩放明细。
struct BossFightRowView: View {
    let row: BossFight
    let index: BossDataIndex
    let players: BossPartySize
    let deepOfNight: Bool
    let isNightlord: Bool

    private let rateColumns = [GridItem(.adaptive(minimum: 62, maximum: 120), spacing: 6)]

    private var stats: BossComputedStats { row.stats(for: players, deepOfNight: deepOfNight) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            titleLine
            metrics
            damageSection
            resistSection
            scalingSection
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(AppTheme.field.opacity(0.55))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(AppTheme.border, lineWidth: 1)
                )
        )
    }

    private var titleLine: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text(row.displayLabel)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                // 同一组首领可能同时有守夜与野外变体，两者威胁档位与血量差别很大。
                if let threat = row.threatTitle {
                    Pill(
                        text: threat,
                        color: row.threat == "night" ? AppTheme.purpleSoft : AppTheme.secondaryText,
                        symbol: row.threat == "night" ? "moon.stars" : "map"
                    )
                }
                if row.isMain {
                    Pill(text: "主战", color: AppTheme.green, symbol: "flag")
                }
                if row.labelUncertain {
                    Pill(text: "标签为社区推测", color: AppTheme.amber, symbol: "questionmark.circle")
                }
                if deepOfNight, row.hasDeepOfNight {
                    Pill(text: "深夜数值", color: AppTheme.amber, symbol: "moon.fill")
                }
                Spacer(minLength: 6)
                Text(row.npcIds.count > 1 ? "npcId \(row.npcId) 等 \(row.npcIds.count) 行" : "npcId \(row.npcId)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(AppTheme.tertiaryText)
            }
            if !row.labelEn.isEmpty, row.labelEn != row.displayLabel {
                Text(row.labelEn)
                    .font(.system(size: 10))
                    .foregroundStyle(AppTheme.tertiaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var metrics: some View {
        HStack(alignment: .top, spacing: 16) {
            BossMetric(
                title: "\(players.shortTitle)血量",
                value: BossFormat.integer(stats.hp),
                caption: "参数原值 \(BossFormat.integer(row.hpBase)) · 常驻 \(BossFormat.multiplier(stats.hpMultiplier, digits: 4))",
                tint: AppTheme.purpleSoft,
                width: 168
            )
            BossMetric(
                title: "有效韧性",
                value: stats.effectivePoise.map { BossFormat.decimal($0, digits: 1) } ?? stats.poiseKind.placeholder,
                caption: poiseCaption,
                width: 178
            )
            BossMetric(
                title: "削韧恢复",
                value: BossFormat.decimal(stats.poiseRecover, digits: 3),
                caption: "基准 \(BossFormat.decimal(row.poiseRecover, digits: 3))",
                width: 104
            )
            BossMetric(
                title: "异常发动伤害",
                value: BossFormat.multiplier(stats.ailmentDamageRate),
                caption: "累积量 " + BossFormat.multiplier(stats.ailmentBuildupRate),
                width: 118
            )
            Spacer(minLength: 0)
        }
    }

    /// 有效韧性为 nil 有三条来源：poise < 0（真的不吃削韧）、poise = 0（没有削韧槽），
    /// 以及承受削韧倍率为 0 / 非有限（数据异常）。三者文案必须分开。
    private var poiseCaption: String {
        guard stats.effectivePoise == nil else {
            let factor = stats.poiseTakenBase * stats.tier.poiseTaken
            return "韧性 \(BossFormat.decimal(row.poise, digits: 0)) ÷ 承受削韧 \(BossFormat.decimal(factor, digits: 3))"
        }
        switch stats.poiseKind {
        case .none: return "superArmorDurability = \(BossFormat.decimal(row.poise, digits: 0))"
        case .zero: return "superArmorDurability = 0，该实体没有削韧槽"
        case .value:
            return "承受削韧倍率异常（\(BossFormat.decimal(stats.poiseTakenBase * stats.tier.poiseTaken, digits: 3))）"
        }
    }

    private var damageSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            BossSubHeading(title: "承伤倍率", detail: "> 1 为弱点，< 1 为抗性；不随人数变化")
            LazyVGrid(columns: rateColumns, spacing: 6) {
                ForEach(BossDamageKind.allCases) { kind in
                    BossRateCell(
                        title: index.dataset.title(for: kind),
                        value: row.damageRates.value(for: kind)
                    )
                }
            }
        }
    }

    private var resistSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            BossSubHeading(title: "异常抗性", detail: "数值为触发阈值，999 = 免疫；多人只改累积量，不改阈值")
            LazyVGrid(columns: rateColumns, spacing: 6) {
                ForEach(BossAilmentKind.allCases) { kind in
                    BossResistCell(
                        title: index.dataset.title(for: kind),
                        value: row.resist.value(for: kind),
                        immune: row.resist.isImmune(to: kind)
                    )
                }
            }
            let immune = row.immuneKinds()
            if !immune.isEmpty {
                Text("免疫：" + immune.map { index.dataset.title(for: $0) }.joined(separator: " · "))
                    .font(.system(size: 10))
                    .foregroundStyle(AppTheme.red)
            }
        }
    }

    @ViewBuilder
    private var scalingSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            BossSubHeading(title: "多人缩放明细", detail: scalingCaption)
            if let scaling = row.scaling, scaling.duo != nil || scaling.trio != nil {
                HStack(alignment: .top, spacing: 8) {
                    BossTierDetail(title: "单人（基准）", tier: .identity, highlighted: players == .solo)
                    if let duo = scaling.duo {
                        BossTierDetail(title: "双人", tier: duo, highlighted: players == .duo)
                    }
                    if let trio = scaling.trio {
                        BossTierDetail(title: "三人", tier: trio, highlighted: players == .trio)
                    }
                }
            } else {
                Text("该行没有人数缩放数据，按单人数值处理")
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.tertiaryText)
            }

            if !stats.permScalingIds.isEmpty {
                BossSubHeading(
                    title: "常驻缩放",
                    detail: deepOfNight && row.hasDeepOfNight ? "深夜模式下生效的一组" : "已计入上面的血量与韧性"
                )
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(index.permanentEffects(stats.permScalingIds)) { effect in
                        BossPermanentEffectRow(effect: effect)
                    }
                    ForEach(index.missingPermanentEffectIDs(stats.permScalingIds), id: \.self) { id in
                        Text("#\(id)（缺少明细）")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(AppTheme.tertiaryText)
                    }
                }
            }

            // 深夜提示随开关反向：关着时告诉用户「可以切」，开着时给出常规值作对照。
            // 三条文案与 Windows 端 deepNote() 完全一致。
            if let deep = row.deepOfNight, !deepOfNight {
                Text("该行有深夜专属缩放：血量 \(BossFormat.integer(deep.hp))（1 人），可用顶部「深夜」开关切换。")
                    .font(.system(size: 10))
                    .foregroundStyle(AppTheme.amber)
                    .fixedSize(horizontal: false, vertical: true)
            } else if deepOfNight, row.hasDeepOfNight {
                Text("当前为深夜数值；常规数值：血量 \(BossFormat.integer(row.hp))（1 人）。")
                    .font(.system(size: 10))
                    .foregroundStyle(AppTheme.amber)
                    .fixedSize(horizontal: false, vertical: true)
            } else if deepOfNight {
                Text("该行没有深夜专属缩放，深夜数值与常规相同。")
                    .font(.system(size: 10))
                    .foregroundStyle(AppTheme.tertiaryText)
            }
        }
    }

    private var scalingCaption: String {
        guard let scalingId = row.scalingId else { return "无缩放档位" }
        guard let group = index.dataset.scalingGroup(scalingId) else { return "档位 #\(scalingId)" }
        return "档位 #\(scalingId) · \(group.title)"
    }
}
