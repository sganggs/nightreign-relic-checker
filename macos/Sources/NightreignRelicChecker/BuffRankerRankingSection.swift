import RelicCore
import SwiftUI

// 「增伤排名」页的下半部分：全部增益一览（折叠表，只供查阅）与底部数据说明。

// MARK: - 全部增益一览

struct BuffRankerOverviewSection: View {
    @ObservedObject var model: BuffRankerModel
    @State private var isOpen = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            RankerDisclosure(title: LoadoutText.t("overviewTitle") + " · " + LoadoutText.t("overviewPill"), isOn: $isOpen) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(LoadoutText.f("overviewCount", model.overviewVisibleRows.count))
                        .font(.system(size: 11))
                        .foregroundStyle(AppTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    RankerSearchField(placeholder: LoadoutText.t("overviewSearch"), text: $model.overviewQuery)
                        .frame(maxWidth: 380)
                    LazyVStack(alignment: .leading, spacing: 3) {
                        ForEach(Array(model.overviewPageRows.enumerated()), id: \.element.id) { item in
                            OverviewRow(rank: model.overviewPage * model.overviewPageSize + item.offset + 1, row: item.element)
                        }
                    }
                    pager
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .appCard()
    }

    @ViewBuilder
    private var pager: some View {
        if model.overviewPageCount > 1 {
            HStack(spacing: 10) {
                Button {
                    model.goToOverviewPage(model.overviewPage - 1)
                } label: {
                    Label(LoadoutText.t("overviewPrev"), systemImage: "chevron.left").font(.caption)
                }
                .buttonStyle(.plain)
                .disabled(model.overviewPage == 0)
                .foregroundStyle(model.overviewPage == 0 ? AppTheme.tertiaryText : AppTheme.purpleSoft)

                Text(LoadoutText.f("overviewPage", model.overviewPage + 1, model.overviewPageCount, model.overviewPageSize))
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText)

                Button {
                    model.goToOverviewPage(model.overviewPage + 1)
                } label: {
                    Label(LoadoutText.t("overviewNext"), systemImage: "chevron.right").font(.caption)
                }
                .buttonStyle(.plain)
                .disabled(model.overviewPage + 1 >= model.overviewPageCount)
                .foregroundStyle(model.overviewPage + 1 >= model.overviewPageCount ? AppTheme.tertiaryText : AppTheme.purpleSoft)
                Spacer(minLength: 0)
            }
        }
    }
}

private struct OverviewRow: View {
    let rank: Int
    let row: LoadoutOverviewRow

    var body: some View {
        HStack(spacing: 8) {
            Text("\(rank)")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(AppTheme.tertiaryText)
                .frame(width: 30, alignment: .trailing)
            Text(row.displayName)
                .font(.system(size: 12))
                .foregroundStyle(row.isApplicable ? .white : AppTheme.tertiaryText)
                .lineLimit(1)
            Pill(text: row.column.title, color: LoadoutPalette.column(row.column))
            Pill(text: row.verdict.label, color: LoadoutPalette.verdict(row.verdict))
            if row.activation != "passive" {
                Pill(
                    text: row.activation == "activated" ? LoadoutText.t("badges.activated") : LoadoutText.t("badges.conditional"),
                    color: AppTheme.amber
                )
            }
            Spacer(minLength: 6)
            if !row.isApplicable, let reason = row.reasons.first {
                Text(reason)
                    .font(.system(size: 10))
                    .foregroundStyle(AppTheme.tertiaryText)
                    .lineLimit(1)
                    .frame(maxWidth: 280, alignment: .trailing)
            } else if let note = row.notes.first {
                Text(note)
                    .font(.system(size: 10))
                    .foregroundStyle(AppTheme.tertiaryText)
                    .lineLimit(1)
                    .frame(maxWidth: 280, alignment: .trailing)
            }
            if row.assumesOneStack {
                Text(LoadoutText.t("overviewOneStack"))
                    .font(.system(size: 10))
                    .foregroundStyle(AppTheme.amber)
                    .help(LoadoutText.t("overviewOneStackHelp"))
            }
            Text(BuffFormat.multiplier(row.multiplier))
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(row.multiplier > 1.0000001 ? AppTheme.green : AppTheme.tertiaryText)
                .frame(width: 70, alignment: .trailing)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.white.opacity(0.02)))
        .opacity(row.isApplicable ? 1 : 0.55)
        .help("SpEffect #\(row.spEffectId) · 互斥键 \(row.exclusiveKey)")
    }
}

// MARK: - 底部数据说明

struct BuffRankerNotesSection: View {
    @ObservedObject var model: BuffRankerModel
    @State private var showPageRules = false
    @State private var showQuestions = false
    @State private var showCaveats = false
    @State private var showUsage = false
    @State private var showRanking = false
    @State private var showStacking = false
    @State private var showCoverage = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeading(title: LoadoutText.t("briefHeading"), subtitle: LoadoutText.t("briefIntro"), symbol: "info.circle")

            if let index = model.loadoutIndex {
                let notes = LoadoutText.briefNotes(index: index)
                RankerDisclosure(title: LoadoutText.t("briefHeading") + "（\(notes.count)）", isOn: $showPageRules) {
                    bulletList(notes)
                }
            }

            if let buffs = model.buffs {
                if !buffs.dataset.userQuestions.isEmpty {
                    RankerDisclosure(
                        title: LoadoutText.f("questionsTitle", buffs.dataset.userQuestions.count), isOn: $showQuestions
                    ) {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(buffs.dataset.userQuestions) { item in
                                noteBlock(title: item.key + " · " + item.question, text: item.answer)
                            }
                        }
                    }
                }
            }

            if let skills = model.skills {
                RankerDisclosure(
                    title: "战技数据的取舍与已知问题（\(skills.dataset.caveats.count) 条）",
                    isOn: $showCaveats
                ) {
                    // 数据集原文里还写着「6 段带 FP + 6 段 No FP」，这里与段名走同一套展示层替换。
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
                                + "（其中 \(skills.poolOnlyOutputs) 个只能从局内战技池抽到，见 usage.战技来源（v3）；"
                                + "另有 \(skills.skillsWithoutWeapons) 个战技本作没有任何武器能带、"
                                + "\(skills.skillsWithoutHits) 个战技没有命中段、"
                                + "\(skills.skillsWithoutDamage) 个战技每一段都算不出伤害，未列入）",
                            tint: AppTheme.secondaryText
                        )
                        RankerDetailRow(
                            label: "命中段核实",
                            value: skills.dataset.taeVerified
                                ? "已按 TAE 动画事件核实：\(skills.notInvokedHits) 段在所有武器上都打不出（hits[].notInvoked），"
                                    + "本页不取（usage.命中段已按 TAE 核实（v3））"
                                : "这份数据没做 TAE 核实（counts.taeVerified 不为 true），选段只按行为表",
                            tint: AppTheme.secondaryText
                        )
                        RankerDetailRow(
                            label: "可选法术",
                            value: "\(skills.outputs.filter { $0.kind == .spell }.count) 个"
                                + "（法术只收施法器能带的，见 usage.法术来源（v3）；另有 \(skills.spellsWithoutHits) 个法术是附魔 / 防护 / 回复类没有命中段、"
                                + "\(skills.spellsWithoutDamage) 个法术有命中段但一个固定值都没有，未列入）",
                            tint: AppTheme.secondaryText
                        )
                        if let index = model.loadoutIndex {
                            RankerDetailRow(
                                label: "配置页条目",
                                value: "局内武器词条 \(index.weaponAffixItems.count) 条、遗物词条 \(index.relicAffixItems.count) 条、"
                                    + "固定遗物 \(index.fixedRelicItems.count) 件、护符 \(index.accessoryItems.count) 个、"
                                    + "其它增益 \(index.slotlessItems.values.reduce(0) { $0 + $1.count }) 条"
                                    + "（只收 target 为自己／队友、带 countsAsDamage 字段的条目）",
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

    /// notes 的展示顺序：先排名算法与 v6 的生效范围／槽位说明，再其余取舍说明。
    private func noteKeys(_ buffs: BuffRankerIndex) -> [String] {
        let preferred = [
            "ranking", "appliesTo", "sourceSlot", "weaponAffix", "relicAffix", "stackInput",
            "attackContext", "stackLadder", "howToUseRates", "activation",
            "target", "conditions", "displayName", "suggestedName", "damageTypeNaming", "zh"
        ]
        let existing = preferred.filter { buffs.dataset.notes[$0] != nil }
        let rest = buffs.dataset.notes.keys.filter { !preferred.contains($0) }.sorted()
        return existing + rest
    }

    /// usage 的展示顺序：选段在前，紧跟 v3 的三条（战技来源、法术来源、命中段已按 TAE 核实），再是算法与边界，其余按键名。
    private func usageKeys(_ skills: SkillDataIndex) -> [String] {
        let preferred = [
            "选段（必读）", "战技来源（v3）", "法术来源（v3）", "命中段已按 TAE 核实（v3）",
            "近战武器段", "法术 / 子弹段", "伤害类型（斩 / 打 / 突）", "削韧", "本数据集的边界"
        ]
        let existing = preferred.filter { skills.dataset.usage[$0] != nil }
        let rest = skills.dataset.usage.keys.filter { !preferred.contains($0) }.sorted()
        return existing + rest
    }

    private func bulletList(_ items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(items.enumerated()), id: \.offset) { item in
                HStack(alignment: .top, spacing: 7) {
                    Text("·").foregroundStyle(AppTheme.tertiaryText)
                    Text(strongText(item.element))
                        .font(.system(size: 11))
                        .foregroundStyle(AppTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // 数据集原文用 Markdown 的 **粗体** 标记重点；`Text(String)` 不解析 Markdown，
    // 这里只把成对的 ** 换成粗体，其余字符原样保留（不走完整 Markdown 解析，避免
    // 原文里的 / [ ] * 之类被误当成语法）。Windows 端 ranker.js 的 strongHtml 同口径。
    private func strongText(_ text: String) -> AttributedString {
        let parts = text.components(separatedBy: "**")
        guard parts.count >= 3 else { return AttributedString(text) }
        var result = AttributedString()
        for (index, part) in parts.enumerated() {
            if index == parts.count - 1 && index % 2 == 1 {
                result.append(AttributedString("**" + part))
            } else if index % 2 == 1 {
                var strong = AttributedString(part)
                strong.inlinePresentationIntent = .stronglyEmphasized
                result.append(strong)
            } else {
                result.append(AttributedString(part))
            }
        }
        return result
    }

    private func noteBlock(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(AppTheme.purpleSoft)
            Text(strongText(text))
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
