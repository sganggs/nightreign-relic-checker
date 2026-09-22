import RelicCore
import SwiftUI

// 「增伤排名」页的下半部分：排名列表、推荐组合、底部数据说明。

// MARK: - 排名列表

struct BuffRankerRankingSection: View {
    @ObservedObject var model: BuffRankerModel
    /// 由页面在 `model.buffs` 已就绪时传入，避免在视图里强解包。
    let dataset: BuffDataset
    let sourceKinds: [String]
    @State private var expandedIDs: Set<Int> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeading(
                title: "增伤排名",
                subtitle: "有效倍率 = Σ(该伤害类型占比 × 作用于它的倍率连乘)；"
                    + "攻击力倍率与最终伤害倍率两层都乘，物理子类型倍率只乘对应部分",
                symbol: "list.number"
            )

            filters
            summaryLine

            if model.pageRows.isEmpty {
                Text("当前条件下没有可用的增伤手段。可以放宽筛选：打开「包含条件型」「包含队友增益」"
                     + "「包含属性／异常限定」，或清空来源类型与搜索词。")
                    .font(.caption)
                    .foregroundStyle(AppTheme.tertiaryText)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(model.pageRows.enumerated()), id: \.element.id) { item in
                        RankerBuffRow(
                            rank: model.page * model.pageSize + item.offset + 1,
                            row: item.element,
                            dataset: dataset,
                            isExpanded: expandedIDs.contains(item.element.spEffectId),
                            isInPlan: model.isInPlan(item.element),
                            onToggleExpand: { toggleExpand(item.element.spEffectId) },
                            onTogglePlan: { model.togglePlanMembership(item.element) }
                        )
                    }
                }
                pager
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .appCard()
    }

    private var filters: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 10) {
                RankerSearchField(placeholder: "搜索增伤手段（名称 / 来源 / SpEffect 行号）", text: $model.buffQuery)
                    .frame(maxWidth: 380)

                Toggle("包含条件型（需触发）", isOn: $model.includeConditional)
                    .toggleStyle(.switch)
                    .font(.caption)
                    .help("activation = conditional / activated：残血、双手持、叠层、命中触发、技艺发动期间等，"
                          + "默认不计入；打开后以灰色斜体列出，仍不进推荐组合")

                Toggle("包含队友给的增益", isOn: $model.includeAllies)
                    .toggleStyle(.switch)
                    .font(.caption)
                    .help("target = ally：自己与／或附近队友都能吃到的增益")

                Toggle("包含属性 / 异常限定", isOn: $model.includeAttributeScoped)
                    .toggleStyle(.switch)
                    .font(.caption)
                    .help("scope.spAttribute 限定（只对带某种属性或异常的攻击生效）；"
                          + "本页无法判定当前段是否带该属性，默认不计入")

                Toggle("叠层类按满层计算", isOn: $model.useLadderTopRates)
                    .toggleStyle(.switch)
                    .font(.caption)
                    .help("stackLadder：数据集只收第 1 层，topRates 才是满层数值。"
                          + "同一阶梯各层互斥，无论开关怎么拨都只按一层计算")

                Spacer(minLength: 0)
            }

            HStack(spacing: 6) {
                Text("来源")
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.tertiaryText)
                ForEach(sourceKinds, id: \.self) { kind in
                    RankerFilterChip(
                        text: dataset.sourceKindLabel(kind),
                        isOn: model.sourceKinds.contains(kind),
                        color: RankerPalette.sourceColor(kind)
                    ) {
                        model.toggleSourceKind(kind)
                    }
                }
                if !model.sourceKinds.isEmpty {
                    Button("清除") { model.clearSourceKinds() }
                        .buttonStyle(.plain)
                        .font(.caption)
                        .foregroundStyle(AppTheme.purpleSoft)
                }
                Spacer(minLength: 0)
            }

            attackContextFilter
        }
    }

    /// 攻击情境多选（notes.ranking ④）：默认全不选 = 通用排名。
    ///
    /// `scope.attackContexts` 非空的条目只在特定攻击情境下才吃得到（致命一击、突刺反击、
    /// 蓄力战技…），它们本身是 passive（装上就一直在），所以「包含条件型」那个开关拦不住，
    /// 必须单独在这里勾选才会进榜。
    @ViewBuilder
    private var attackContextFilter: some View {
        if !model.attackContextOptions.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text("攻击情境")
                        .font(.system(size: 11))
                        .foregroundStyle(AppTheme.tertiaryText)
                    if !model.includedAttackContexts.isEmpty {
                        Button("清除") { model.clearAttackContexts() }
                            .buttonStyle(.plain)
                            .font(.caption)
                            .foregroundStyle(AppTheme.purpleSoft)
                    }
                    Spacer(minLength: 0)
                }
                RankerWrap(spacing: 6, lineSpacing: 5) {
                    ForEach(model.attackContextOptions) { option in
                        RankerFilterChip(
                            text: "\(option.zh) \(option.count)",
                            isOn: model.includedAttackContexts.contains(option.key),
                            color: AppTheme.amber
                        ) {
                            model.toggleAttackContext(option.key)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Text("默认全不选 = 通用排名：只在某种攻击情境下才生效的倍率（强化致命一击、强化突刺反击、"
                     + "蓄力战技…）默认不计入，勾选情境后才参与乘算。这类条目本身是常驻（passive），"
                     + "「包含条件型」开关拦不住它们，只能在这里勾。勾多个情境时，命中其中任一情境的条目都会列出。")
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.tertiaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var summaryLine: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Text(model.hiddenFromDisplayCount > 0
                     ? "命中 \(model.ranking.rows.count) 条 · 当前筛选显示 \(model.displayRows.count) 条"
                     : "共 \(model.ranking.rows.count) 条")
                    .font(.system(size: 12, weight: .semibold))
                if model.ranking.neutralCount > 0 {
                    Text("另有 \(model.ranking.neutralCount) 条虽然作用于这次攻击，但对当前伤害构成没有增益（例如纯物理构成里的火属性倍率），未列出")
                        .font(.system(size: 11))
                        .foregroundStyle(AppTheme.tertiaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Text(model.deliveryLabel)
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.secondaryText)
            }
            Text(model.scopeNote)
                .font(.system(size: 11))
                .foregroundStyle(AppTheme.tertiaryText)
                .fixedSize(horizontal: false, vertical: true)
            if model.ranking.contextScopedCount > 0 {
                Text("另有 \(model.ranking.contextScopedCount) 条只在特定攻击情境下才生效"
                     + "（scope.attackContexts：致命一击 / 突刺反击 / 蓄力…）而未计入，"
                     + "勾选上方对应的「攻击情境」后才会列出并参与乘算")
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.tertiaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if model.ranking.attributeScopedCount > 0 {
                Text("另有 \(model.ranking.attributeScopedCount) 条被 scope.spAttribute 限定"
                     + "（只对带某种属性／异常的攻击生效）而未计入，打开「包含属性／异常限定」后才会列出")
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.tertiaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // 作用域不符的总数与分项：与 Windows 端 rankBodyHtml 的
            //「作用域不符 N 条」+ scopeBreakdownHtml 一一对应。
            //「为什么这些条目没出现」不该藏在一个总数里——数据集没给判据、由本页承担的判定
            //（只标 130 近战、只作用于法术…）更要逐条列出来。
            if model.ranking.scopeRejectedCount > 0 {
                Text("另有 \(model.ranking.scopeRejectedCount) 条作用域不符（武器槽／投掷／法术／攻击子类别）而未计入")
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.tertiaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !model.scopeReasonText.isEmpty {
                Text("排除原因分项：" + model.scopeReasonText)
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.tertiaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if model.composition.isEmpty {
                Text("当前没有勾选任何带伤害的段：没有构成就算不出有效倍率，列表为空。先在上面勾一段。")
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.amber)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if model.hiddenFromDisplayCount > 0 {
                Text("搜索词与来源类型只筛列表：被筛掉的 \(model.hiddenFromDisplayCount) 条仍然计入下面的推荐组合。"
                     + "要排除某一条，请在列表里勾掉它。")
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.tertiaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var pager: some View {
        if model.pageCount > 1 {
            HStack(spacing: 10) {
                Button {
                    model.goToPage(model.page - 1)
                } label: {
                    Label("上一页", systemImage: "chevron.left")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .disabled(model.page == 0)
                .foregroundStyle(model.page == 0 ? AppTheme.tertiaryText : AppTheme.purpleSoft)

                Text("第 \(model.page + 1) / \(model.pageCount) 页 · 每页 \(model.pageSize) 条")
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText)

                Button {
                    model.goToPage(model.page + 1)
                } label: {
                    Label("下一页", systemImage: "chevron.right")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .disabled(model.page + 1 >= model.pageCount)
                .foregroundStyle(model.page + 1 >= model.pageCount ? AppTheme.tertiaryText : AppTheme.purpleSoft)

                Spacer(minLength: 0)
            }
            .padding(.top, 2)
        }
    }

    private func toggleExpand(_ id: Int) {
        if expandedIDs.contains(id) {
            expandedIDs.remove(id)
        } else {
            expandedIDs.insert(id)
        }
    }
}

// MARK: - 推荐组合

struct BuffRankerStackSection: View {
    @ObservedObject var model: BuffRankerModel
    let dataset: BuffDataset

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeading(
                title: "推荐组合（理论叠加上限）",
                subtitle: "按 stackingRules：同一 stacking.group 只取一条（applyHighest 组取 categoryPriority 更优的一份），"
                    + "不同组相互独立、各自倍率相乘",
                symbol: "square.stack.3d.up"
            )

            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(BuffFormat.multiplier(model.plan.total, digits: 2))
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.green)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(model.plan.groupCount) 个叠加组连乘 · 相对当前构成 \(BuffFormat.gain(model.plan.total))")
                        .font(.system(size: 12, weight: .semibold))
                    Text("同组被顶掉 \(model.plan.droppedByStacking) 条"
                         + (model.plan.excludedCount > 0 ? " · 已勾掉 \(model.plan.excludedCount) 条" : "")
                         + (model.includedConditional.isEmpty ? "" : " · 已纳入 \(model.includedConditional.count) 条条件型"))
                        .font(.system(size: 11))
                        .foregroundStyle(AppTheme.tertiaryText)
                }
                Spacer(minLength: 0)
                if model.hasPlanOverrides {
                    Button("恢复默认") { model.resetPlanOverrides() }
                        .buttonStyle(.plain)
                        .font(.caption)
                        .foregroundStyle(AppTheme.purpleSoft)
                }
            }

            HStack(spacing: 14) {
                Toggle("同族效果只取最高档", isOn: $model.mergeFamilies)
                    .toggleStyle(.switch)
                    .font(.caption)
                    .help("按 Paramdex 行名词干合并叠加组：[Relic] X / X +1 / X +2 是同一条词条的不同档位，"
                          + "一枚遗物上只会有一档")

                Toggle("同 stateInfo 视为同一状态", isOn: $model.mergeStates)
                    .toggleStyle(.switch)
                    .font(.caption)
                    .help("stackingRules 第 3 条只说同一 stateInfo「值得怀疑」是同一状态的不同档位，"
                          + "并不是互斥分组；打开＝按这条交叉参考保守合并，可能把本可共存的效果并成一组")

                Spacer(minLength: 0)
            }

            if model.plan.picks.isEmpty {
                Text("当前条件下没有可叠加的无条件增伤手段。")
                    .font(.caption)
                    .foregroundStyle(AppTheme.tertiaryText)
            } else {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(model.plan.picks.prefix(40))) { pick in
                        pickRow(pick)
                    }
                }
                if model.plan.picks.count > 40 {
                    Text("仅显示前 40 条，其余 \(model.plan.picks.count - 40) 条已计入总倍率。")
                        .font(.system(size: 11))
                        .foregroundStyle(AppTheme.tertiaryText)
                }
            }

            Text("条件型（残血、双手持、叠层、命中触发、技艺发动期间…）默认不计入，"
                 + "在上面的列表里单独勾选才会纳入这里的连乘。"
                 + "组合按「全部命中条目」计算，不受上面的搜索框与来源类型筛选影响。"
                 + "攻击力加算（点数）没有绝对攻击力就折不成倍率，只在列表里单独展示，不进连乘。"
                 + "叠层阶梯的各层共用一个叠加组，绝不会有两层同时相乘。")
                .font(.system(size: 11))
                .foregroundStyle(AppTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            Text("注意：这是按参数结构推断出来的叠加上限，未经木桩实测；也没有考虑遗物孔位 / 护符槽位数量、"
                 + "道具持续时间与实际可获得性 —— 真实一局里不可能同时挂满。请把它当成「参数层面的天花板」，"
                 + "在上面的列表里按自己的配装勾掉用不到的条目再看总倍率。")
                .font(.system(size: 11))
                .foregroundStyle(AppTheme.amber)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .appCard()
    }

    private func pickRow(_ pick: BuffRankingRow) -> some View {
        Button {
            model.togglePlanMembership(pick)
        } label: {
            HStack(spacing: 9) {
                RankerCheckbox(isOn: true, tint: AppTheme.green)
                Text(pick.displayName)
                    .font(.system(size: 12))
                    .italic(!pick.isPassive)
                if !pick.isPassive {
                    Pill(text: pick.activation == "activated" ? "发动期间" : "需满足条件", color: AppTheme.amber)
                }
                Spacer(minLength: 8)
                ForEach(pick.sourceKinds.prefix(2), id: \.self) { kind in
                    Text(dataset.sourceKindLabel(kind))
                        .font(.system(size: 10))
                        .foregroundStyle(RankerPalette.sourceColor(kind))
                }
                Text(pick.durationText)
                    .font(.system(size: 10))
                    .foregroundStyle(AppTheme.tertiaryText)
                    .frame(width: 60, alignment: .trailing)
                Text(BuffFormat.multiplier(pick.effectiveMultiplier))
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(AppTheme.green)
                    .frame(width: 72, alignment: .trailing)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(0.02))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 底部数据说明

struct BuffRankerNotesSection: View {
    @ObservedObject var model: BuffRankerModel
    @State private var showPageRules = false
    @State private var showCaveats = false
    @State private var showUsage = false
    @State private var showRanking = false
    @State private var showStacking = false
    @State private var showCoverage = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeading(
                title: "数据说明",
                subtitle: "数值直接取自游戏参数表，既不是官方公布，也不是木桩实测",
                symbol: "info.circle"
            )

            // 本页自己承担的判定：与 Windows 端「数据说明与本页口径」同文，两端一起改。
            RankerDisclosure(
                title: "本页口径与自己承担的判定（\(model.pageRuleNotes.count) 条）",
                isOn: $showPageRules
            ) {
                bulletList(model.pageRuleNotes)
            }

            if let skills = model.skills {
                RankerDisclosure(
                    title: "战技数据的取舍与已知问题（\(skills.dataset.caveats.count) 条）",
                    isOn: $showCaveats
                ) {
                    // 数据集原文里还写着「6 段带 FP + 6 段 No FP」，这里与段名走同一套展示层
                    // 替换（Windows 端 caveatsHtml 同理），免得同一页上段名说「专注值不足版」、
                    // 底部说「No FP」。数据集本身不动。
                    bulletList(skills.dataset.caveats.map(SkillTextZh.fpText))
                }

                RankerDisclosure(title: "选段与边界（战技数据集 usage 原文）", isOn: $showUsage) {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(usageKeys(skills), id: \.self) { key in
                            if let text = skills.dataset.usage[key] {
                                noteBlock(title: key, text: text)
                            }
                        }
                    }
                }

                RankerDisclosure(title: "覆盖范围", isOn: $showCoverage) {
                    VStack(alignment: .leading, spacing: 5) {
                        RankerDetailRow(
                            label: "可选战技",
                            value: "\(skills.outputs.filter { $0.kind == .skill }.count) 个"
                                + "（另有 \(skills.skillsWithoutWeapons) 个战技本作没有任何武器引用、"
                                + "\(skills.skillsWithoutHits) 个战技没有命中段、"
                                + "\(skills.skillsWithoutDamage) 个战技每一段都算不出伤害，未列入）",
                            tint: AppTheme.secondaryText
                        )
                        RankerDetailRow(
                            label: "可选法术",
                            value: "\(skills.outputs.filter { $0.kind == .spell }.count) 个"
                                + "（另有 \(skills.spellsWithoutHits) 个法术是附魔 / 防护 / 回复类没有命中段、"
                                + "\(skills.spellsWithoutDamage) 个法术有命中段但一个固定值都没有，未列入）",
                            tint: AppTheme.secondaryText
                        )
                        if let buffs = model.buffs {
                            RankerDetailRow(
                                label: "增伤手段",
                                value: "\(buffs.dataset.buffs.count) 条，其中 \(buffs.attributeScopedCount) 条被"
                                    + "scope.spAttribute 限定（只对带某种属性 / 异常的攻击生效，默认不计入）、"
                                    + "\(buffs.contextScopedTotal) 条被 scope.attackContexts 限定"
                                    + "（只在某种攻击情境下才生效，默认不计入，需勾选情境）",
                                tint: AppTheme.secondaryText
                            )
                            RankerDetailRow(
                                label: "v4 / v5 字段",
                                value: "叠层阶梯 \(buffs.ladderCount) 条（只收第 1 层，topRates 才是满层数值，各层互斥）、"
                                    + "自伤型异常累积 \(buffs.selfInflictedStatusCount) 条"
                                    + "（status 组的加算累在玩家自己身上，countsAsDamage 全为 false，"
                                    + "伤害排名的乘积不受影响；将来做异常累积榜必须整条排除）、"
                                    + "stateInfo 中文标签 \(buffs.dataset.stateInfoLabelCount) 项",
                                tint: AppTheme.secondaryText
                            )
                        }
                    }
                }
            }

            if let buffs = model.buffs {
                RankerDisclosure(
                    title: "排名算法与数据取舍（增益数据集 notes 原文，\(buffs.dataset.notes.count) 段）",
                    isOn: $showRanking
                ) {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(noteKeys(buffs), id: \.self) { key in
                            if let text = buffs.dataset.notes[key] {
                                noteBlock(title: "notes." + key, text: text)
                            }
                        }
                    }
                }

                if !buffs.dataset.stackingRulesZh.isEmpty {
                    RankerDisclosure(title: "叠加规则（增益数据集 stackingRules 原文）", isOn: $showStacking) {
                        noteBlock(title: "stackingRules.zh", text: buffs.dataset.stackingRulesZh)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 5) {
                ForEach(model.datasetVersions, id: \.0) { row in
                    RankerDetailRow(label: row.0, value: row.1, tint: AppTheme.secondaryText)
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.03))
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .appCard()
    }

    /// notes 的展示顺序：先排名算法，再情境 / 叠层 / 倍率用法，最后目标 / 条件 / 命名这些取舍说明。
    /// 与 Windows 端 NOTE_ORDER 一致。
    private func noteKeys(_ buffs: BuffRankerIndex) -> [String] {
        let preferred = [
            "ranking", "attackContext", "stackLadder", "howToUseRates", "activation",
            "target", "conditions", "displayName", "damageTypeNaming", "zh"
        ]
        let existing = preferred.filter { buffs.dataset.notes[$0] != nil }
        let rest = buffs.dataset.notes.keys.filter { !preferred.contains($0) }.sorted()
        return existing + rest
    }

    private func usageKeys(_ skills: SkillDataIndex) -> [String] {
        let preferred = ["选段（必读）", "近战武器段", "法术 / 子弹段", "伤害类型（斩 / 打 / 突）", "削韧", "本数据集的边界"]
        let existing = preferred.filter { skills.dataset.usage[$0] != nil }
        let rest = skills.dataset.usage.keys.filter { !preferred.contains($0) }.sorted()
        return existing + rest
    }

    private func bulletList(_ items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(items.enumerated()), id: \.offset) { item in
                HStack(alignment: .top, spacing: 7) {
                    Text("·").foregroundStyle(AppTheme.tertiaryText)
                    Text(item.element)
                        .font(.system(size: 11))
                        .foregroundStyle(AppTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func noteBlock(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(AppTheme.purpleSoft)
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(AppTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.white.opacity(0.03))
        )
    }
}
