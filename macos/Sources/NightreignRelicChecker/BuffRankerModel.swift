import Foundation
import RelicCore
import SwiftUI

/// 「增伤排名」页的状态与增量计算。
///
/// 页面状态全部收在这里（视图只读不算），改一个开关就只重算受影响的那一段：
///   * 换输出手段 / 换武器 → 重新选段 → 重算构成 → 重排名；
///   * 勾选段 → 重算构成 → 重排名；
///   * 改筛选 / 搜索 → 只重排名（每条 buff 的通道乘数在建索引时就算好了，
///     这里只是 9 个通道的加权求和，几百条不会卡）。
@MainActor
final class BuffRankerModel: ObservableObject {
    enum Phase {
        case loading
        case missing
        case failed(String)
        case ready
    }

    @Published private(set) var phase: Phase = .loading

    private(set) var skills: SkillDataIndex?
    private(set) var buffs: BuffRankerIndex?

    // MARK: 输出手段

    @Published var outputQuery: String = "" {
        didSet { refreshOutputResults() }
    }
    @Published private(set) var outputResults: [SkillOutput] = []
    @Published private(set) var selectedOutput: SkillOutput?
    @Published private(set) var weaponGroups: [SkillWeaponGroup] = []
    @Published private(set) var weapon: SkillWeapon?
    /// 当前战技（法术时为 nil）。
    @Published private(set) var skill: SkillEntry?
    @Published private(set) var spell: SpellEntry?

    // MARK: 分段

    @Published private(set) var segments: [SkillSegment] = []
    @Published private(set) var selectedSegmentIDs: Set<Int> = []
    @Published private(set) var composition: SkillDamageComposition = .empty
    /// 当前勾的是无 FP 版（FP 段与无 FP 段互斥切换）。
    @Published private(set) var useNoFp: Bool = false

    // MARK: 排名筛选

    @Published var weaponSlot: Int = 1 {
        didSet { if weaponSlot != oldValue { refreshRanking() } }
    }
    @Published var includeConditional: Bool = false {
        didSet { if includeConditional != oldValue { refreshRanking() } }
    }
    @Published var includeAllies: Bool = false {
        didSet { if includeAllies != oldValue { refreshRanking() } }
    }
    @Published var includeAttributeScoped: Bool = false {
        didSet { if includeAttributeScoped != oldValue { refreshRanking() } }
    }
    /// 叠层阶梯按满层数值计算（stackLadder.topRates）；默认关。
    @Published var useLadderTopRates: Bool = false {
        didSet { if useLadderTopRates != oldValue { refreshRanking() } }
    }
    /// 同族效果只取最高档（按 Paramdex 行名词干合并叠加组）；默认开。
    @Published var mergeFamilies: Bool = true {
        didSet { if mergeFamilies != oldValue { refreshPlan() } }
    }
    /// 同 stateInfo 视为同一状态（stackingRules 第 3 条的交叉参考，偏保守）；默认关。
    @Published var mergeStates: Bool = false {
        didSet { if mergeStates != oldValue { refreshPlan() } }
    }
    /// 搜索框：**只影响列表显示**，推荐组合仍按全部命中条目算。
    @Published var buffQuery: String = "" {
        didSet { if buffQuery != oldValue { refreshDisplayRows() } }
    }
    @Published private(set) var sourceKinds: Set<String> = []
    /// 用户勾选的攻击情境（notes.ranking ④）。默认全不选 = 通用排名，
    /// scope.attackContexts 非空的条目（强化致命一击、强化突刺反击、蓄力战技…）一律不计入。
    @Published private(set) var includedAttackContexts: Set<String> = []

    // MARK: 结果

    @Published private(set) var ranking: BuffRankingResult = .empty
    /// 列表实际显示的那些行（= ranking.rows 再过一遍搜索词与来源类型）。
    @Published private(set) var displayRows: [BuffRankingRow] = []
    @Published private(set) var plan: BuffStackPlan = .empty
    /// 用户在推荐组合里勾掉的条目（默认计入的 passive 条目）。
    @Published private(set) var excludedFromPlan: Set<Int> = []
    /// 用户明确勾选纳入的条件型条目（activation ≠ passive，默认不计入）。
    @Published private(set) var includedConditional: Set<Int> = []
    /// 列表分页游标（从 0 开始）。
    @Published private(set) var page: Int = 0

    let pageSize = 50

    // MARK: 载入

    func load() async {
        guard case .loading = phase else { return }
        let loaded = await Task.detached(priority: .userInitiated) { () -> Result<(SkillDataIndex, BuffRankerIndex), Error>? in
            guard let skillsData = GameDataLoader.dataIfAvailable(for: .skills),
                  let buffsData = GameDataLoader.dataIfAvailable(for: .buffs) else { return nil }
            do {
                return .success((try SkillDataIndex(data: skillsData), try BuffRankerIndex(data: buffsData)))
            } catch {
                return .failure(error)
            }
        }.value

        guard let loaded else {
            phase = .missing
            return
        }
        switch loaded {
        case .failure(let error):
            phase = .failed(error.localizedDescription)
        case .success(let (skillsIndex, buffsIndex)):
            skills = skillsIndex
            buffs = buffsIndex
            phase = .ready
            refreshOutputResults()
            // 默认选一个有代表性的输出：第一条有武器的战技。
            if let first = skillsIndex.outputs.first(where: { $0.kind == .skill }) ?? skillsIndex.outputs.first {
                select(output: first)
            }
        }
    }

    // MARK: 输出手段

    private func refreshOutputResults() {
        guard let skills else {
            outputResults = []
            return
        }
        let matches = skills.outputs(matching: outputQuery)
        outputResults = Array(matches.prefix(Self.maxOutputResults))
        outputMatchCount = matches.count
    }

    private(set) var outputMatchCount: Int = 0
    static let maxOutputResults = 60

    func select(output: SkillOutput) {
        guard let skills else { return }
        selectedOutput = output
        excludedFromPlan = []
        includedConditional = []
        switch output.kind {
        case .skill:
            spell = nil
            let entry = skills.skillsByID[output.entryID]
            skill = entry
            weaponGroups = entry.map { skills.weaponGroups(for: $0) } ?? []
            weapon = entry.flatMap { skills.defaultWeapon(for: $0) }
        case .spell:
            skill = nil
            weaponGroups = []
            weapon = nil
            spell = skills.spellsByID[output.entryID]
        }
        refreshSegments(resetSelection: true)
    }

    func select(weapon newWeapon: SkillWeapon) {
        guard weapon?.id != newWeapon.id else { return }
        weapon = newWeapon
        refreshSegments(resetSelection: true)
    }

    // MARK: 分段

    private func refreshSegments(resetSelection: Bool) {
        guard let skills else { return }
        if let skill {
            segments = skills.segments(for: skill, weapon: weapon)
        } else if let spell {
            segments = skills.segments(for: spell)
        } else {
            segments = []
        }
        if resetSelection {
            useNoFp = false
            selectedSegmentIDs = SkillDamageMath.defaultSelection(segments)
        } else {
            selectedSegmentIDs = selectedSegmentIDs.filter { id in segments.contains { $0.atkId == id } }
        }
        refreshComposition()
    }

    /// noDamage 段（只挂状态、构成恒为 0）不可勾选：与 Windows 端把这类段的 checkbox
    /// 设成 disabled 同一口径，勾上只会让用户以为它进了构成。
    func canToggleSegment(_ atkId: Int) -> Bool {
        guard let segment = segments.first(where: { $0.atkId == atkId }) else { return false }
        return !segment.noDamage
    }

    func toggleSegment(_ atkId: Int) {
        guard canToggleSegment(atkId) else { return }
        if selectedSegmentIDs.contains(atkId) {
            selectedSegmentIDs.remove(atkId)
        } else {
            selectedSegmentIDs.insert(atkId)
        }
        refreshComposition()
    }

    /// 「全选」只勾**当前 FP 侧**的段：FP 版与无 FP 版互为替代，两边一起勾会把同一击算两遍。
    /// 口径与 Windows 端 hitOverridesFor(action="all") 一致。
    func selectAllSegments() {
        selectedSegmentIDs = SkillDamageMath.selection(segments, useNoFp: useNoFp)
        refreshComposition()
    }

    func clearSegments() {
        selectedSegmentIDs = []
        refreshComposition()
    }

    /// FP 段与无 FP 段互斥切换。
    func setUseNoFp(_ value: Bool) {
        guard value != useNoFp else { return }
        useNoFp = value
        selectedSegmentIDs = SkillDamageMath.selection(segments, useNoFp: value)
        refreshComposition()
    }

    var hasNoFpVariant: Bool { segments.contains { $0.noFp } }

    private func refreshComposition() {
        composition = SkillDamageMath.composition(of: segments, selected: selectedSegmentIDs)
        refreshRanking()
    }

    // MARK: 排名

    var delivery: BuffDelivery {
        if let spell {
            return spell.isSorcery ? .sorcery : .incantation
        }
        return .weaponSkill
    }

    var context: BuffRankingContext {
        BuffRankingContext(
            delivery: delivery,
            weaponSlot: weaponSlot,
            subCategories: skill == nil ? [] : [BuffRankingContext.skillAttackSubCategory],
            composition: composition
        )
    }

    var options: BuffRankingOptions {
        BuffRankingOptions(
            includeConditional: includeConditional,
            includeAllies: includeAllies,
            includeAttributeScoped: includeAttributeScoped,
            includedAttackContexts: includedAttackContexts,
            useLadderTopRates: useLadderTopRates,
            mergeFamilies: mergeFamilies,
            mergeStates: mergeStates,
            sourceKinds: sourceKinds,
            query: buffQuery
        )
    }

    /// 可勾选的攻击情境（数据集里真正出现过的那些）。
    var attackContextOptions: [BuffAttackContextOption] { buffs?.availableAttackContexts ?? [] }

    func toggleAttackContext(_ key: String) {
        if includedAttackContexts.contains(key) {
            includedAttackContexts.remove(key)
        } else {
            includedAttackContexts.insert(key)
        }
        // 情境变了，原来勾进组合的情境限定条目可能已经不在榜上，交给 refreshRanking 重算。
        refreshRanking()
    }

    func clearAttackContexts() {
        guard !includedAttackContexts.isEmpty else { return }
        includedAttackContexts = []
        refreshRanking()
    }

    /// 来源类型是**显示筛选**：只换列表，不动推荐组合（否则勾一个来源总倍率就变了）。
    func toggleSourceKind(_ kind: String) {
        if sourceKinds.contains(kind) {
            sourceKinds.remove(kind)
        } else {
            sourceKinds.insert(kind)
        }
        refreshDisplayRows()
    }

    func clearSourceKinds() {
        guard !sourceKinds.isEmpty else { return }
        sourceKinds = []
        refreshDisplayRows()
    }

    /// 被搜索词 / 来源类型筛掉、但仍计入推荐组合的条目数（页面要写明这一点）。
    var hiddenFromDisplayCount: Int { ranking.rows.count - displayRows.count }

    /// 这一条当前是否计入推荐组合：passive 默认计入（可勾掉），
    /// 条件型默认不计入（勾上才纳入，对应 notes.ranking ③）。
    func isInPlan(_ row: BuffRankingRow) -> Bool {
        row.isPassive
            ? !excludedFromPlan.contains(row.spEffectId)
            : includedConditional.contains(row.spEffectId)
    }

    func togglePlanMembership(_ row: BuffRankingRow) {
        if row.isPassive {
            if excludedFromPlan.contains(row.spEffectId) {
                excludedFromPlan.remove(row.spEffectId)
            } else {
                excludedFromPlan.insert(row.spEffectId)
            }
        } else {
            if includedConditional.contains(row.spEffectId) {
                includedConditional.remove(row.spEffectId)
            } else {
                includedConditional.insert(row.spEffectId)
            }
        }
        refreshPlan()
    }

    var hasPlanOverrides: Bool { !excludedFromPlan.isEmpty || !includedConditional.isEmpty }

    func resetPlanOverrides() {
        guard hasPlanOverrides else { return }
        excludedFromPlan = []
        includedConditional = []
        refreshPlan()
    }

    func goToPage(_ index: Int) {
        page = max(0, min(index, max(0, pageCount - 1)))
    }

    var pageCount: Int {
        max(1, Int(ceil(Double(displayRows.count) / Double(pageSize))))
    }

    var pageRows: [BuffRankingRow] {
        let start = page * pageSize
        guard start < displayRows.count else { return [] }
        let end = min(start + pageSize, displayRows.count)
        return Array(displayRows[start..<end])
    }

    private func refreshRanking() {
        guard let buffs else { return }
        ranking = buffs.rankResult(context: context, options: options)
        refreshDisplayRows()
        refreshPlan()
    }

    /// 只重算列表显示（搜索词 / 来源类型）——推荐组合不受影响。
    private func refreshDisplayRows() {
        guard let buffs else { return }
        displayRows = buffs.visibleRows(ranking.rows, options: options)
        page = 0
    }

    private func refreshPlan() {
        guard let buffs else { return }
        // 组合按**全部命中条目**算，不吃搜索框与来源类型筛选：那两个是看列表用的视图筛选，
        // 不是取舍。要排除某一条请在列表里勾掉它。
        plan = buffs.stackPlan(
            rows: ranking.rows,
            excluded: excludedFromPlan,
            includedConditional: includedConditional,
            options: options
        )
    }

    // MARK: 展示辅助

    var weaponSummary: String? {
        guard let weapon else { return nil }
        var parts: [String] = []
        for element in SkillElement.allCases where weapon.attack(element) > 0 {
            parts.append("\(element.titleZh) \(BuffFormat.trim(weapon.attack(element), digits: 0))")
        }
        if parts.isEmpty { parts.append("无基础攻击力") }
        return parts.joined(separator: " · ")
    }

    var outputTitle: String {
        selectedOutput?.displayName ?? "未选择"
    }

    var deliveryLabel: String {
        let slot = weaponSlot == 2 ? "左手" : "右手"
        if let spell {
            let kind = spell.kindZh.isEmpty ? (spell.isSorcery ? "魔法" : "祷告") : spell.kindZh
            return "\(kind) · \(slot)施法器"
        }
        return "战技攻击 · \(slot)武器"
    }

    /// 当前是按什么规则匹配 buff 的 scope —— 列表上方原样说明，避免「为什么这条没出现」。
    var scopeNote: String {
        let slot = weaponSlot == 2 ? "左手" : "右手"
        if spell != nil {
            return "法术按 scope.affectsSorcery / affectsIncantation + 武器槽（\(slot)，"
                + "scope.weaponSlot 为空或「自身」视为不限）匹配；普通施法不属于任何攻击子类别，"
                + "因此带子类别限定（蓄力法术、绝招…）的条目不计入。"
        }
        return "战技命中按攻击子类别 112（战技攻击）+ 武器槽（\(slot)，scope.weaponSlot 为空或「自身」视为不限）匹配；"
            + "带其它子类别限定（跳跃攻击 / 防御反击 / 蓄力 / 绝招 / 远程 / 只标 130 近战…）的条目不计入，"
            + "只作用于魔法／祷告（weaponSlot=自身 + 只点亮魔法／祷告）与只作用于致命一击／投掷"
            + "（只点亮 affectsThrow）的条目同样不计入。"
    }

    /// 排除原因的分项文案（按条数降序）：与 Windows 端 scopeBreakdownHtml 同一顺序、同一措辞。
    var scopeReasonText: String {
        ranking.scopeReasonBreakdown
            .map { "\($0.reason) \($0.count) 条" }
            .joined(separator: "；")
    }

    /// 「本页自己承担的判定」13 条。正文在 RelicCore 的 `BuffRankerPageNotes` 里，
    /// 与 Windows 端 ranker.js 的 pageRuleNotes **逐字同文**；这里只负责把数据现算的条数喂进去。
    var pageRuleNotes: [String] {
        BuffRankerPageNotes.rules(
            attributeScoped: buffs?.attributeScopedCount ?? 0,
            ladders: buffs?.ladderCount ?? 0,
            selfInflicted: buffs?.selfInflictedStatusCount ?? 0,
            meleeOnly: buffs?.meleeOnlyCount ?? 0,
            skillsWithoutDamage: skills?.skillsWithoutDamage ?? 0,
            spellsWithoutDamage: skills?.spellsWithoutDamage ?? 0,
            hasAttackContexts: !(buffs?.availableAttackContexts.isEmpty ?? true)
        )
    }

    var datasetVersions: [(String, String)] {
        var rows: [(String, String)] = []
        if let skills {
            rows.append(("战技数据版本", "\(skills.dataset.gameVersion) · \(skills.dataset.dataVersion)"))
            rows.append(("战技数据结构版本", "schemaVersion \(skills.dataset.schemaVersion)"))
            if !skills.dataset.generatedAt.isEmpty {
                rows.append(("战技数据生成时间", skills.dataset.generatedAt))
            }
        }
        if let buffs {
            rows.append(("增益数据版本", "\(buffs.dataset.gameVersion) · \(buffs.dataset.dataVersion)"))
            rows.append(("增益数据结构版本", "schemaVersion \(buffs.dataset.schemaVersion)"))
            if !buffs.dataset.generatedAt.isEmpty {
                rows.append(("增益数据生成时间", buffs.dataset.generatedAt))
            }
        }
        return rows
    }
}
