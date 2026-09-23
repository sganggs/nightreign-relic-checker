import SwiftUI
import RelicCore

// 「首领数据」页的首领卡片：折叠时显示主战行概览，展开后逐行列出全部战斗记录。

struct BossCardView: View {
    let card: BossCard
    /// 当前所在的分组区块。同一组首领按出场场合可能同时出现在「守夜首领」「场景头目」
    /// 「据点首领」……好几个区块里，折叠态的代表行必须跟着分组走（场景头目区块就看
    /// 场景头目那几行），不能恒取 rows[0]。
    let group: BossCard.Group
    let index: BossDataIndex
    let players: BossPartySize
    /// 常规 / 深夜 · 深度 1…5。
    let mode: BossNightMode
    /// 「显示隐藏实体」：同时决定展开区列不列「未放置」「随从/召唤物」的行。
    let showHidden: Bool
    let isExpanded: Bool
    let onToggle: () -> Void

    private var primary: BossFight? { card.representativeRow(in: group) }

    /// 该分组下参与评选的候选行（先按当前分组过滤 roles，再收敛到 isMain，
    /// 排掉登场演出 / 血条实体这类演出行与无奖励行）。规则正文见 BossCard.rows(in:)。
    private var candidates: [BossFight] { card.rows(in: group) }

    /// 展开区列出的行（默认藏掉只出现在「未放置」「随从/召唤物」的行）。
    private var shownRows: [BossFight] { card.displayRows(includeHidden: showHidden) }

    private var depthWord: String { index.dataset.deepOfNightText.depthTitle }

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
                titleLine
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

    /// 主标题走 `BossCard.displayName` 的四级回退（nameZh → nameZhFallback →
    /// displayFallbackZh → nameEn）；副标题恒为英文名（主标题已经是英文名时不重复）。
    /// 「这个标题是不是游戏里的名字」由 `badges` 里的名字徽标负责说明。
    private var titleLine: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(card.displayName)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)
            if let subtitle = card.subtitleName {
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.tertiaryText)
            }
        }
    }

    /// 卡头徽标会自动换行：一组首领最多有 7 个出场场合，再加名字 / 深夜徽标，一行放不下。
    private var badges: some View {
        BossWrap(spacing: 6, lineSpacing: 5) {
            switch card.kind {
            case .nightlord:
                if !card.expeditionZh.isEmpty {
                    Pill(text: "远征 · " + card.expeditionZh, color: AppTheme.purpleSoft)
                }
                if !card.variantNameZh.isEmpty {
                    Pill(text: card.variantNameZh, color: card.isEverdark ? AppTheme.amber : AppTheme.purpleSoft)
                }
                weaknessBadge
                // 夜王卡片只进「夜王」分组，突袭 / 地图事件 / 未放置这些场合只挂徽标。
                BossRoleBadges(roles: card.roles, dataset: index.dataset, group: group)
            case .boss:
                // 卡头列出全部出场场合（可多重归属）；属于当前分组的场合着色，
                // 其余用中性色——一眼看出这张卡为什么出现在这个分组里。
                BossRoleBadges(roles: card.roles, dataset: index.dataset, group: group)
                // 近似匹配与「参考译名」已并进 card.nameBadges（与 Windows 端同序）。
                nameSourceBadge
                if card.hidden {
                    Pill(text: BossRowText.hiddenToggleHelp, color: AppTheme.tertiaryText, symbol: "eye.slash")
                }
            }
            // 深夜徽标扫描整卡：首条代表行没有深夜值，不代表整张卡都没有。
            // 两个徽标分工：前者说「深度模式下这张卡的数值变了」（depthStats 口径，
            // v3 全量覆盖），后者说「还额外吃一组深夜专属常驻修正」（deepOfNight，只有 31 行）。
            if mode.isDeepOfNight {
                if let text = card.deepCoverage.badgeText {
                    Pill(text: text, color: AppTheme.amber, symbol: "moon.fill")
                }
                if let text = card.deepOfNightCoverage.exclusiveBadgeText {
                    Pill(text: text, color: AppTheme.amber, symbol: "moon.stars.fill")
                }
            }
            // 「N 条数值行」：卡头计数与 Windows 端 rowCountText() 逐字一致；
            // 默认藏掉的「未放置」「随从/召唤物」行另补一句。
            Text(BossRoleText.rowCount(
                visible: shownRows.count,
                hidden: card.hiddenRowCount(includeHidden: showHidden)
            ))
                .font(.system(size: 10))
                .foregroundStyle(AppTheme.tertiaryText)
        }
    }

    /// 折叠态头条数值取自哪一行。两种情况都必须写清楚，否则同一张卡里差几倍的数值
    /// 会被当成算错：夜王的 `isMain` 不唯一（多阶段 / 多体有 2～5 条），
    /// 守夜 / 野外首领的候选行则随分组切换（同一组首领可能有好几个出场场合）。
    @ViewBuilder
    private var primaryRowNote: some View {
        if let primary {
            let pool = candidates
            // 只有「代表行本身有歧义」的卡片才铺开列全部候选行：夜王有多条 isMain，
            // 或同时属于多个分组的组（同一张卡在不同分组下给的是不同的行）。
            let ambiguous = card.isNightlord ? card.hasMultipleMainRows : card.hasMultipleGroups
            if ambiguous, pool.count > 1 {
                let list = pool
                    .map { "\($0.displayLabel) \(BossFormat.integer($0.hp(for: players, mode: mode)))" }
                    .joined(separator: " · ")
                let lead = card.isNightlord
                    ? "\(pool.count) 条主战行，上方取血量最高的一条："
                    : "该分组 \(pool.count) 条数值行，上方取血量最高的一条："
                Text(lead + list)
                    .font(.system(size: 10))
                    .foregroundStyle(AppTheme.amber)
                    .fixedSize(horizontal: false, vertical: true)
            } else if shownRows.count > 1 {
                Text("代表行：\(primary.displayLabel)（共 \(shownRows.count) 组，展开看全部）")
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
        if !card.isNightlord {
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

    /// 「名字缺不缺」与「身份谁认出来的」是两件事，可能同时成立（Elder Dragon Greyoll
    /// 之类既没有简中名、身份又只有社区资料），所以按 nameBadges 全挂上。
    @ViewBuilder
    private var nameSourceBadge: some View {
        ForEach(card.nameBadges, id: \.self) { badge in
            Pill(text: badge.text, color: badge == .community ? AppTheme.purpleSoft : AppTheme.amber)
        }
    }

    /// 主战行不止一条时标明头条取的是最高那条，别让用户以为「这只 Boss 就这点血」。
    private var hpMetricTitle: String {
        guard card.isNightlord else { return "血量" }
        return card.hasMultipleMainRows ? "主战血量 · 最高" : "主战血量"
    }

    /// 深度模式下代表行没有 depthStats 时要直说，否则摘要与卡头的深夜徽标看着像在互相打架。
    private func hpCaption(row: BossFight) -> String {
        if let depth = mode.depth {
            guard row.hasDepthStats else { return BossRowText.noDepthStatsText }
            let solo = row.hp(for: .solo, mode: mode)
            return players == .solo
                ? "\(depthWord) \(depth) 数值"
                : "\(depthWord) \(depth) · 1 人 \(BossFormat.integer(solo))"
        }
        return players == .solo ? "含常驻缩放" : "1 人 \(BossFormat.integer(row.hp))"
    }

    private func summaryMetrics(for row: BossFight) -> some View {
        let stats = row.stats(for: players, mode: mode)
        let tier = row.tier(for: players)
        return HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 3) {
                BossMetric(
                    title: "\(hpMetricTitle)（\(players.title)）",
                    value: BossFormat.integer(stats.hp),
                    caption: hpCaption(row: row),
                    tint: AppTheme.purpleSoft,
                    width: 136
                )
                // 多人不只是血条变长：7744 / 7753 / 7754 / 7758 四档敌人攻击力也上浮。
                if tier.raisesAttack {
                    Text(BossRowText.multiplayerAttackBadge(tier.attackRate))
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(AppTheme.red)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(AppTheme.red.opacity(0.14), in: Capsule())
                }
            }
            BossMetric(
                title: "有效韧性",
                value: stats.effectivePoise.map { BossFormat.decimal($0, digits: 1) } ?? stats.poiseKind.placeholder,
                caption: stats.effectivePoise == nil ? nil : "韧性槽 \(BossFormat.decimal(row.poise, digits: 0))",
                width: 84
            )
            BossMetric(
                title: "攻击力倍率",
                value: BossFormat.multiplier(stats.attackRate, digits: 3),
                caption: mode.isDeepOfNight ? "含深度倍率" : "常驻基准",
                tint: AppTheme.red,
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
    /// 下面再补一行「威胁档位」小字：tier / tiers 不再决定分组，但仍是参数里的事实。
    @ViewBuilder
    private var identifierNote: some View {
        if !card.isNightlord {
            VStack(alignment: .leading, spacing: 3) {
                if !card.chrIds.isEmpty || card.npcNameId != nil {
                    HStack(spacing: 12) {
                        if !card.chrIds.isEmpty {
                            Text("chrId " + card.chrIds.map(String.init).joined(separator: " / "))
                        }
                        if let npcNameId = card.npcNameId {
                            Text(verbatim: "NpcName #\(npcNameId)")
                        }
                        if !card.nameSource.isEmpty {
                            Text("名称来源 " + card.nameSource)
                        }
                        Spacer(minLength: 0)
                    }
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(AppTheme.tertiaryText)
                }
                if !card.tiers.isEmpty {
                    Text(BossRoleText.threatTierCaption(card.tiers) + "：" + BossRoleText.threatTierNote)
                        .font(.system(size: 10))
                        .foregroundStyle(AppTheme.tertiaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    /// 名字来历：近似匹配的依据、社区认身份的说明、让出同名词条的裁决，以及参考译名的来源。
    /// 组级「不掉奖励」小字也挂在这块里，所以 `noReward` 必须进外层条件——否则
    /// Giant Skeleton Torso（五个名字字段全空、noReward = true）这类组就永远看不到那行小字。
    @ViewBuilder
    private var nameNotes: some View {
        if card.showsNameNotes {
            VStack(alignment: .leading, spacing: 5) {
                if !card.nameNote.isEmpty {
                    Text(card.nameNote)
                        .font(.system(size: 11))
                        .foregroundStyle(AppTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let evidence = card.nameEvidence {
                    BossDetailRow(label: "游戏文本依据", value: evidence.summary, tint: AppTheme.secondaryText)
                }
                if let rejected = card.nameZhRejected {
                    BossDetailRow(label: "被挡下的候选词条", value: rejected.summary, tint: AppTheme.amber)
                    if !rejected.reason.isEmpty {
                        Text(rejected.reason)
                            .font(.system(size: 10))
                            .foregroundStyle(AppTheme.tertiaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if !card.nameZhFallbackNote.isEmpty {
                    Text(card.nameZhFallbackNote)
                        .font(.system(size: 10))
                        .foregroundStyle(AppTheme.tertiaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !card.nameSourceUrl.isEmpty {
                    Text(card.nameSourceUrl)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(AppTheme.tertiaryText)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                // noReward 只作小字，不影响是否显示：Storm King / 蚯蚓脸这些不掉奖励但仍是首领。
                if card.noReward {
                    Text(BossRowText.noRewardGroupNote)
                        .font(.system(size: 10))
                        .foregroundStyle(AppTheme.tertiaryText)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(AppTheme.amber.opacity(0.05))
            )
        }
    }

    private var expandedBody: some View {
        VStack(alignment: .leading, spacing: 14) {
            identifierNote
            nameNotes
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

            // 夜王才有按深度的出现权重（守夜 / 野外 Boss 参数里根本没有这张表）。
            if card.isNightlord, let weights = depthChanceWeights {
                BossDepthChanceRow(weights: weights, depthWord: depthWord)
            }

            ForEach(shownRows) { row in
                BossFightRowView(
                    row: row,
                    index: index,
                    players: players,
                    mode: mode,
                    isNightlord: card.isNightlord
                )
            }

            let hiddenRows = card.hiddenRowCount(includeHidden: showHidden)
            if hiddenRows > 0 {
                Text(BossRoleText.hiddenRows(hiddenRows))
                    .font(.system(size: 10))
                    .foregroundStyle(AppTheme.tertiaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// 该卡片对应夜王的各深度出现权重；不是夜王或数据缺失时为 nil。
    private var depthChanceWeights: [(depth: Int, weight: Int)]? {
        guard let menuId = card.menuId,
              let lord = index.dataset.nightlords.first(where: { $0.menuId == menuId }),
              lord.hasDepthChanceWeights
        else { return nil }
        return lord.orderedDepthChanceWeights
    }
}

/// 单条战斗记录：数值概览 + 八种承伤倍率 + 异常抗性 + 深夜各深度 + 变异个体 + 缩放明细。
struct BossFightRowView: View {
    let row: BossFight
    let index: BossDataIndex
    let players: BossPartySize
    let mode: BossNightMode
    let isNightlord: Bool

    /// 「按变异个体计算」的选择。变异档位是逐行的（mutationPool 每行不同），
    /// 所以状态也放在行里；收起卡片后归零，不会悄悄影响别处的数值。
    @State private var mutationId: Int? = nil

    private let rateColumns = [GridItem(.adaptive(minimum: 62, maximum: 120), spacing: 6)]

    private var mutationPool: [BossMutation] { index.dataset.mutations(for: row) }

    private var mutation: BossMutation? {
        guard let mutationId else { return nil }
        return index.dataset.mutation(mutationId)
    }

    private var stats: BossComputedStats {
        row.stats(for: players, mode: mode, mutation: mutation)
    }

    private var depthWord: String { index.dataset.deepOfNightText.depthTitle }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            titleLine
            metrics
            BossRoleEvidenceSection(row: row, dataset: index.dataset)
            damageSection
            resistSection
            depthSection
            mutationSection
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
                // 这一行自己的出场场合（合并行是各原始行的并集，逐行的写在「出场场合」小节里）。
                // schemaVersion 3 以前这里挂的是 threat「守夜 / 野外」——那只是缩放档位，
                // 铃珠猎人野外版照样是「守夜」，正是用户反馈的误导，已降为下面的小字。
                BossRoleBadges(roles: row.roles, dataset: index.dataset)
                if row.isMain {
                    Pill(text: "主战", color: AppTheme.green, symbol: "flag")
                }
                if row.labelUncertain {
                    Pill(text: BossRowText.labelUncertainBadge, color: AppTheme.amber, symbol: "questionmark.circle")
                }
                if mode.isDeepOfNight, row.hasDepthStats {
                    Pill(text: BossRowText.deepRowBadge, color: AppTheme.amber, symbol: "moon.fill")
                }
                if mode.isDeepOfNight, row.hasDeepOfNight {
                    Pill(text: BossRowText.deepExclusiveBadge, color: AppTheme.amber, symbol: "moon.stars.fill")
                }
                if mutation != nil {
                    Pill(text: index.dataset.mutationTitle, color: AppTheme.red, symbol: "flame")
                }
                Spacer(minLength: 6)
                Text(verbatim: row.npcIds.count > 1 ? "npcId \(row.npcId) 等 \(row.npcIds.count) 行" : "npcId \(row.npcId)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(AppTheme.tertiaryText)
            }
            if !row.labelEn.isEmpty, row.labelEn != row.displayLabel {
                Text(row.labelEn)
                    .font(.system(size: 10))
                    .foregroundStyle(AppTheme.tertiaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let caption = row.threatTierCaption {
                Text(caption)
                    .font(.system(size: 10))
                    .foregroundStyle(AppTheme.tertiaryText)
            }
            if row.noReward {
                Text(BossRowText.noRewardRowNote)
                    .font(.system(size: 10))
                    .foregroundStyle(AppTheme.tertiaryText)
            }
        }
    }

    private var metrics: some View {
        let current = stats
        return HStack(alignment: .top, spacing: 16) {
            BossMetric(
                title: "\(players.shortTitle)血量",
                value: BossFormat.integer(current.hp),
                caption: hpCaption(current),
                tint: AppTheme.purpleSoft,
                width: 190
            )
            BossMetric(
                title: "有效韧性",
                value: current.effectivePoise.map { BossFormat.decimal($0, digits: 1) } ?? current.poiseKind.placeholder,
                caption: poiseCaption,
                width: 178
            )
            BossMetric(
                title: "攻击力倍率",
                value: BossFormat.multiplier(current.attackRate, digits: 3),
                caption: attackCaption(current),
                tint: AppTheme.red,
                width: 150
            )
            BossMetric(
                title: "削韧恢复",
                value: BossFormat.decimal(current.poiseRecover, digits: 3),
                caption: "基准 \(BossFormat.decimal(row.poiseRecover, digits: 3))",
                width: 104
            )
            BossMetric(
                title: "异常发动伤害",
                value: BossFormat.multiplier(current.ailmentDamageRate),
                caption: "累积量 " + BossFormat.multiplier(current.ailmentBuildupRate),
                width: 118
            )
            Spacer(minLength: 0)
        }
    }

    /// 血量小字要把「这个数是怎么来的」说全：参数原值、常驻倍率，以及深度 / 变异这两层。
    private func hpCaption(_ current: BossComputedStats) -> String {
        if current.depthMissing { return BossRowText.noDepthStatsText }
        var text = "参数原值 \(BossFormat.integer(row.hpBase)) · 总倍率 "
            + BossFormat.multiplier(current.hpMultiplier, digits: 4)
        if let depth = current.mode.depth { text += " · \(depthWord) \(depth)" }
        if let mutation = current.mutation {
            text += " · 变异 " + BossFormat.multiplier(mutation.hp, digits: 3)
        }
        return text
    }

    private func attackCaption(_ current: BossComputedStats) -> String {
        var parts = ["基准 " + BossFormat.multiplier(row.baseline(mode: current.mode).attackRateBase, digits: 3)]
        if current.tier.raisesAttack {
            parts.append("多人 " + BossFormat.multiplier(current.tier.attackRate, digits: 3))
        }
        if let mutation = current.mutation {
            parts.append("变异 " + BossFormat.multiplier(mutation.attackRate, digits: 3))
        }
        return parts.joined(separator: " · ")
    }

    /// 有效韧性为 nil 有三条来源：poise < 0（真的不吃削韧）、poise = 0（没有削韧槽），
    /// 以及承受削韧倍率为 0 / 非有限（数据异常）。三者文案必须分开。
    /// 四支整体下沉到 RelicCore 的 BossRowText，与 Windows 端逐字一致。
    private var poiseCaption: String {
        let current = stats
        return BossRowText.poiseCaption(
            poise: row.poise,
            poiseTakenTotal: current.poiseTakenBase * current.tier.poiseTaken,
            kind: current.poiseKind,
            hasEffectivePoise: current.effectivePoise != nil
        )
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

    /// 「深夜各深度」小表。按当前人数（与已选变异档位）换算，口径与上面的主数值一致。
    private var depthSection: some View {
        BossDepthTable(
            rows: row.depthRows(for: players, mutation: mutation),
            currentDepth: mode.depth,
            caption: depthCaption,
            depthWord: depthWord
        )
    }

    private var depthCaption: String {
        var parts = ["按 \(players.title)换算"]
        if let mutation { parts.append("含变异 #\(mutation.id)") }
        parts.append("已含常驻缩放、深夜修正与深度倍率")
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private var mutationSection: some View {
        if !mutationPool.isEmpty {
            BossMutationSection(
                title: index.dataset.mutationTitle,
                pool: mutationPool,
                selectedId: $mutationId
            )
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

            let current = stats
            if !current.permScalingIds.isEmpty {
                BossSubHeading(
                    title: "常驻缩放",
                    detail: mode.isDeepOfNight && row.hasDeepOfNight ? "深夜模式下生效的一组" : "已计入上面的血量与韧性"
                )
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(index.permanentEffects(current.permScalingIds)) { effect in
                        BossPermanentEffectRow(effect: effect)
                    }
                    ForEach(index.missingPermanentEffectIDs(current.permScalingIds), id: \.self) { id in
                        Text(verbatim: "#\(id)（缺少明细）")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(AppTheme.tertiaryText)
                    }
                }
            }

            // chaosCorrectId 可能与 scalingId 不等（14 行如此），不标出来会让人对不上深度档位。
            if let chaosId = row.chaosCorrectId, chaosId != row.scalingId {
                Text("深度档位取 ChaosMatchingCorrectParam #\(chaosId)，与人数档位 "
                     + (row.scalingId.map { "#\($0)" } ?? "（无）") + " 不是同一行。")
                    .font(.system(size: 10))
                    .foregroundStyle(AppTheme.tertiaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            deepNote
        }
    }

    /// 深夜提示随模式反向：常规模式告诉用户「可以切」，深度模式给出常规值作对照。
    @ViewBuilder
    private var deepNote: some View {
        if !mode.isDeepOfNight {
            if row.hasDepthStats, let deepest = row.depthRows(for: .solo).last {
                Text("该行有深夜数值：\(depthWord) \(deepest.depth) 血量 \(BossFormat.integer(deepest.hp))（1 人）、"
                     + "攻击 \(BossFormat.multiplier(deepest.attackRate, digits: 3))，可用顶部的模式选择切换。")
                    .font(.system(size: 10))
                    .foregroundStyle(AppTheme.amber)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else if row.hasDepthStats {
            Text("当前为深夜数值；常规数值：血量 \(BossFormat.integer(row.hp))（1 人）、"
                 + "攻击 \(BossFormat.multiplier(row.attackRateBase, digits: 3))。")
                .font(.system(size: 10))
                .foregroundStyle(AppTheme.amber)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Text(BossRowText.noDepthStatsText)
                .font(.system(size: 10))
                .foregroundStyle(AppTheme.tertiaryText)
        }
    }

    /// 三支下沉到 RelicCore 的 BossRowText，与 Windows 端逐字一致。
    private var scalingCaption: String {
        BossRowText.scalingCaption(
            scalingID: row.scalingId,
            groupTitle: row.scalingId.flatMap { index.dataset.scalingGroup($0)?.title }
        )
    }
}
