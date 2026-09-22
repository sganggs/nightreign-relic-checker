import RelicCore
import SwiftUI

/// 增伤排名页：选一个输出手段（战技 / 法术）→ 勾选它实际打出的段 →
/// 看这套段的伤害构成 → 按构成加权给「增伤手段」排名 → 给出理论叠加组合。
///
/// 由「增伤排名」功能开发者独占：只改本文件与 BuffRanker*.swift、RelicCore 的
/// SkillData.swift / BuffRanker.swift、RelicCoreChecks 的 BuffRankerChecks.swift；
/// **不改 AppModel / RootView**，页面状态全部放在 `BuffRankerModel` 里。
///
/// 数据：`GameDataLoader.dataIfAvailable(for: .skills)` 与 `… (for: .buffs)`；
/// 未内置（文件缺失或仍是占位内容）时降级显示「数据未内置」。
struct BuffRankerView: View {
    @StateObject private var model = BuffRankerModel()

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider().overlay(AppTheme.border)
            content
            footer
        }
        .task { await model.load() }
    }

    // MARK: - 顶部

    private var toolbar: some View {
        VStack(spacing: 12) {
            HStack(alignment: .center, spacing: 14) {
                LogoMark(size: 40)
                VStack(alignment: .leading, spacing: 4) {
                    Text("增伤排名")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                    Text("按战技 / 法术的实际分段算出伤害构成，再给增伤手段排名")
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                }
                Spacer()
                if case .ready = model.phase, let skills = model.skills, let buffs = model.buffs {
                    Pill(text: skills.summary, color: AppTheme.green, symbol: "checkmark.circle")
                    Pill(text: buffs.summary, color: AppTheme.purpleSoft, symbol: "bolt.circle")
                }
            }
        }
        .padding(.horizontal, 26)
        .padding(.vertical, 20)
        .background(AppTheme.elevated.opacity(0.55))
    }

    // MARK: - 主体

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .loading:
            VStack(spacing: 12) {
                ProgressView()
                Text("正在载入战技与增益数据…")
                    .font(.callout)
                    .foregroundStyle(AppTheme.secondaryText)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .missing:
            EmptyStateView(
                title: "数据未内置",
                symbol: "chart.bar.xaxis",
                detail: "尚未提供 Resources/skills.json 与 Resources/buffs.json，"
                    + "运行 scripts/sync-data.sh 同步后重新构建。"
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .failed(let message):
            EmptyStateView(
                title: "战技 / 增益数据无法解析",
                symbol: "exclamationmark.triangle",
                detail: message
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .ready:
            readyContent
        }
    }

    private var readyContent: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                BuffRankerOutputSection(model: model)
                if model.selectedOutput != nil, let buffs = model.buffs {
                    BuffRankerSegmentSection(model: model)
                    BuffRankerCompositionSection(model: model)
                    BuffRankerRankingSection(
                        model: model,
                        dataset: buffs.dataset,
                        sourceKinds: buffs.availableSourceKinds
                    )
                    BuffRankerStackSection(model: model, dataset: buffs.dataset)
                }
                BuffRankerNotesSection(model: model)
            }
            .padding(.horizontal, 26)
            .padding(.vertical, 18)
            .frame(maxWidth: 1180)
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - 底栏

    private var footer: some View {
        HStack {
            Text(footerLeading)
            Spacer()
            Text(footerTrailing)
        }
        .font(.caption)
        .foregroundStyle(AppTheme.secondaryText)
        .padding(.horizontal, 28)
        .frame(height: 38)
        .background(AppTheme.elevated)
        .overlay(alignment: .top) { Rectangle().fill(AppTheme.border).frame(height: 1) }
    }

    private var footerLeading: String {
        guard case .ready = model.phase else { return "完全离线，数值取自游戏参数表" }
        guard model.selectedOutput != nil else { return "请选择一个战技或法术" }
        return "\(model.outputTitle) · 勾选 \(model.selectedSegmentIDs.count)/\(model.segments.count) 段 · "
            + "增伤条目 \(model.ranking.rows.count)"
    }

    private var footerTrailing: String {
        guard case .ready = model.phase, let buffs = model.buffs else { return "" }
        return "\(model.deliveryLabel) · 数据版本 \(buffs.dataset.dataVersion)"
    }
}

// MARK: - 输出手段

struct BuffRankerOutputSection: View {
    @ObservedObject var model: BuffRankerModel

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            SectionHeading(
                title: "输出手段",
                subtitle: "搜索战技（中文 / 英文名）或法术（魔法 · 祷告）；战技可选具体武器",
                symbol: "scope"
            )

            RankerSearchField(placeholder: "搜索战技或法术，例如「尸横遍野」「Corpse Piler」「帚星」", text: $model.outputQuery)

            if !model.outputQuery.isEmpty || model.selectedOutput == nil {
                resultList
            }

            if let output = model.selectedOutput {
                selection(output)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .appCard()
    }

    private var resultList: some View {
        VStack(alignment: .leading, spacing: 6) {
            if model.outputResults.isEmpty {
                Text("没有匹配的战技或法术")
                    .font(.caption)
                    .foregroundStyle(AppTheme.tertiaryText)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(model.outputResults) { output in
                            Button {
                                model.select(output: output)
                                model.outputQuery = ""
                            } label: {
                                HStack(spacing: 8) {
                                    Pill(
                                        text: output.kind == .skill ? "战技" : "法术",
                                        color: output.kind == .skill ? AppTheme.purpleSoft : Color(red: 0.55, green: 0.78, blue: 0.99)
                                    )
                                    Text(output.displayName)
                                        .font(.system(size: 12, weight: .semibold))
                                    Text(output.nameEn)
                                        .font(.system(size: 11))
                                        .foregroundStyle(AppTheme.tertiaryText)
                                    Spacer(minLength: 0)
                                    Text(output.subtitleZh)
                                        .font(.system(size: 11))
                                        .foregroundStyle(AppTheme.secondaryText)
                                }
                                .padding(.horizontal, 9)
                                .padding(.vertical, 6)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(model.selectedOutput?.id == output.id ? AppTheme.purple.opacity(0.14) : Color.white.opacity(0.02))
                                )
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxHeight: 230)

                if model.outputMatchCount > model.outputResults.count {
                    Text("共 \(model.outputMatchCount) 条匹配，仅显示前 \(model.outputResults.count) 条，请继续输入缩小范围。")
                        .font(.system(size: 11))
                        .foregroundStyle(AppTheme.tertiaryText)
                }
            }
        }
    }

    @ViewBuilder
    private func selection(_ output: SkillOutput) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(output.displayName)
                    .font(.system(size: 17, weight: .bold))
                Text(output.nameEn)
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.tertiaryText)
                Pill(text: output.subtitleZh, color: AppTheme.purpleSoft)
                Spacer(minLength: 0)
            }

            if model.skill != nil {
                weaponPicker
            } else if let spell = model.spell {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        Pill(
                            text: spell.kindZh.isEmpty ? (spell.isSorcery ? "魔法" : "祷告") : spell.kindZh,
                            color: AppTheme.green
                        )
                        Spacer(minLength: 0)
                        // 施法器同样占左右手之一，scope.weaponSlot 要对上（与 Windows 端一致）。
                        handPicker
                    }
                    Text("法术段只用固定伤害（flat）做配比：参数表里的 motion 是「照抄武器攻击力 100%」的占位写法，"
                         + "乘到辉石魔杖 / 圣印记的物理攻击力上会凭空造出物理伤害。"
                         + "武器槽用于匹配 scope.weaponSlot —— 只作用于另一只手的增益不计入。")
                        .font(.system(size: 11))
                        .foregroundStyle(AppTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.03))
        )
    }

    /// 武器槽（左右手）：战技与法术都要，scope.weaponSlot 按它匹配。
    private var handPicker: some View {
        Picker("武器槽", selection: $model.weaponSlot) {
            Text("右手").tag(1)
            Text("左手").tag(2)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(width: 124)
        .help("增伤 buff 的 scope.weaponSlot 会区分左右手（缺失与「自身」视为不限），默认按右手计算")
    }

    private var weaponPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Menu {
                    ForEach(model.weaponGroups) { group in
                        Menu("\(group.wepTypeZh)（\(group.weapons.count)）") {
                            ForEach(group.weapons) { weapon in
                                Button(weapon.displayName) { model.select(weapon: weapon) }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "wrench.and.screwdriver")
                            .font(.caption)
                        Text(model.weapon?.displayName ?? "选择武器")
                            .font(.system(size: 12, weight: .semibold))
                    }
                }
                .menuStyle(.borderlessButton)
                .frame(maxWidth: 260)

                if let weapon = model.weapon {
                    Pill(text: weapon.wepTypeZh, color: AppTheme.secondaryText)
                    if !weapon.rarityZh.isEmpty {
                        Pill(text: weapon.rarityZh, color: AppTheme.tertiaryText)
                    }
                }

                Spacer(minLength: 0)

                handPicker
            }

            if let weapon = model.weapon {
                HStack(spacing: 14) {
                    ForEach(SkillElement.allCases, id: \.self) { element in
                        attackCell(element.titleZh, weapon.attack(element))
                    }
                    Divider().frame(height: 26).overlay(AppTheme.border)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("物理攻击类型")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(AppTheme.tertiaryText)
                        Text("\(weapon.atkAttributeZh) / \(weapon.atkAttribute2Zh)")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                    }
                    Spacer(minLength: 0)
                }
                Text("基础攻击力取自 EquipParamWeapon，不含强化等级、亲和与词条加成；"
                     + "本页只做相对构成，绝对伤害不在范围内。")
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.tertiaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func attackCell(_ title: String, _ value: Double) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(AppTheme.tertiaryText)
            Text(BuffFormat.trim(value, digits: 0))
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(value > 0 ? .white : AppTheme.tertiaryText)
        }
        .frame(width: 44, alignment: .leading)
    }
}

// MARK: - 分段命中

struct BuffRankerSegmentSection: View {
    @ObservedObject var model: BuffRankerModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeading(
                title: "分段命中",
                subtitle: model.skill == nil
                    ? "法术的全部命中段；勾掉不想统计的段（例如只算爆发段）"
                    : "按 weapons[].skillVariant → skills[].variants[].atkIds 选出「这把武器会打出的段」",
                symbol: "list.bullet.rectangle"
            )

            HStack(spacing: 10) {
                Button("全选") { model.selectAllSegments() }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(AppTheme.purpleSoft)
                    .help("只勾当前这一侧的段：正常版与专注值不足版互为替代，两边一起勾会把同一击算两遍")
                Button("全不选") { model.clearSegments() }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(AppTheme.purpleSoft)

                if model.hasNoFpVariant {
                    Toggle("使用专注值不足版本", isOn: Binding(
                        get: { model.useNoFp },
                        set: { model.setUseNoFp($0) }
                    ))
                    .toggleStyle(.switch)
                    .font(.caption)
                    .help("没蓝时打出的弱化版战技：正常版与专注值不足版互斥，这里整体切换")

                    Text("没蓝时打出的弱化版战技")
                        .font(.system(size: 10))
                        .foregroundStyle(AppTheme.tertiaryText)
                }

                Spacer(minLength: 0)

                Text("已勾选 \(model.selectedSegmentIDs.count) / \(model.segments.count) 段")
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
            }

            if model.segments.isEmpty {
                Text("这套动作没有任何命中段（多为纯增益 / 格挡 / 附魔类技能）。")
                    .font(.caption)
                    .foregroundStyle(AppTheme.tertiaryText)
            } else {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(model.segments) { segment in
                        RankerSegmentRow(
                            segment: segment,
                            isSelected: model.selectedSegmentIDs.contains(segment.atkId),
                            onToggle: { model.toggleSegment(segment.atkId) }
                        )
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .appCard()
    }
}

// MARK: - 伤害构成

struct BuffRankerCompositionSection: View {
    @ObservedObject var model: BuffRankerModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeading(
                title: "伤害构成",
                subtitle: "占比 = Σ(武器该属性基础攻击力 × motion/100 + flat) / 总和；物理再按斩 / 打 / 突 / 标准细分",
                symbol: "chart.pie"
            )

            if model.composition.isEmpty {
                Text("当前没有勾选任何带伤害的段，无法计算构成——排名与推荐组合都要先有一个真实的伤害构成。")
                    .font(.caption)
                    .foregroundStyle(AppTheme.amber)
            } else {
                RankerCompositionBar(composition: model.composition)
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(model.composition.breakdown) { item in
                        RankerCompositionLegendRow(
                            channel: item.channel,
                            share: item.share,
                            amount: item.amount
                        )
                    }
                }
                HStack(spacing: 14) {
                    Text("物理合计 " + BuffFormat.percent(model.composition.physicalShare))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(AppTheme.secondaryText)
                    Text("相对伤害总量 " + BuffFormat.trim(model.composition.total, digits: 1))
                        .font(.system(size: 11))
                        .foregroundStyle(AppTheme.tertiaryText)
                    Spacer(minLength: 0)
                }
            }

            Text("这是「相对构成」，不含强化等级与能力值补正，绝对伤害不在本页范围 —— "
                 + "战技数据集没有收录 ReinforceParamWeapon 与 AttackElementCorrectParam，"
                 + "它支持的是同一把武器上不同段的相对比较与按伤害类型加权的排名（usage.本数据集的边界）。")
                .font(.system(size: 11))
                .foregroundStyle(AppTheme.tertiaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .appCard()
    }
}
