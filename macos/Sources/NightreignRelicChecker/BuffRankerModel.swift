import Foundation
import RelicCore
import SwiftUI

/// 「增伤排名」页（配置版）的状态与增量计算。
///
/// 页面状态全部收在这里（视图只读不算），纯计算在 RelicCore 的 `BuffLoadout.swift`：
///   * 换输出手段 / 换武器 → 重新选段 → 重算构成 → 重建计算器（appliesTo 判定跟着输出走）；
///   * 勾选段 / 换手 / 勾攻击情境 → 重建计算器；
///   * 改配置（武器词条、遗物、护符、其它增益、条件、层数…）→ 只重算汇总与各栏候选。
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
    private(set) var loadoutIndex: BuffLoadoutIndex?
    /// 词条库读不出来时的原因（自组遗物不可用，其余照常）。
    private(set) var catalogError: String?

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
    /// 当前勾的是专注值不足版（正常版与专注值不足版互斥切换）。
    @Published private(set) var useNoFp: Bool = false

    // MARK: 生效判定的输入

    /// 当前手（appliesToDetail.requires.hand 按它判）。
    @Published var weaponSlot: Int = 1 {
        didSet { if weaponSlot != oldValue { refreshEvaluator() } }
    }
    /// 用户勾选的攻击情境（requires.attackContexts）。
    @Published private(set) var includedAttackContexts: Set<String> = []
    @Published private(set) var contextOptions: [BuffAttackContextOption] = []

    // MARK: 配置

    @Published private(set) var loadout = BuffLoadout()
    /// 显示 appliesTo 判为不生效的条目（虚化 + 原因）。
    @Published var showInapplicable: Bool = false
    /// 武器词条栏：true = 全部武器类别，false = 当前武器类别。
    @Published var weaponFilterAll: Bool = false {
        didSet { if weaponFilterAll != oldValue { refreshCandidates() } }
    }
    @Published var weaponAffixQuery: String = ""
    @Published var otherQuery: String = ""
    @Published var otherColumn: LoadoutColumn = .consumable
    /// 切模式时去掉了几条武器词条（给用户看一句话）。
    @Published private(set) var modeNotice: String?

    // MARK: 结果

    @Published private(set) var evaluation: LoadoutEvaluation = .empty
    @Published private(set) var weaponAffixCandidates: [LoadoutCandidate] = []
    @Published private(set) var accessoryCandidates: [LoadoutCandidate] = []
    @Published private(set) var otherCandidates: [LoadoutColumn: [LoadoutCandidate]] = [:]
    @Published private(set) var overviewRows: [LoadoutOverviewRow] = []
    @Published var overviewQuery: String = "" {
        didSet { if overviewQuery != oldValue { overviewPage = 0 } }
    }
    @Published private(set) var overviewPage: Int = 0

    private(set) var evaluator: LoadoutEvaluator?
    let overviewPageSize = 50

    // MARK: 载入

    func load() async {
        guard case .loading = phase else { return }
        let catalogURL = try? AppModel.bundledCatalogURL()
        let loaded = await Task.detached(priority: .userInitiated) { () -> Result<Loaded, Error>? in
            guard let skillsData = GameDataLoader.dataIfAvailable(for: .skills),
                  let buffsData = GameDataLoader.dataIfAvailable(for: .buffs) else { return nil }
            do {
                let skills = try SkillDataIndex(data: skillsData)
                let buffs = try BuffRankerIndex(data: buffsData)
                var affixes: [Affix] = []
                var catalogError: String?
                if let catalogURL {
                    do {
                        affixes = try CatalogLoader.load(from: catalogURL).affixes
                    } catch {
                        catalogError = error.localizedDescription
                    }
                } else {
                    catalogError = LoadoutText.relicCatalogMissing
                }
                let index = BuffLoadoutIndex(ranker: buffs, catalog: affixes)
                return .success(Loaded(skills: skills, buffs: buffs, loadout: index, catalogError: catalogError))
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
        case .success(let result):
            skills = result.skills
            buffs = result.buffs
            loadoutIndex = result.loadout
            catalogError = result.catalogError
            loadout = BuffLoadout(mode: .normal, rules: result.loadout.slotRules)
            phase = .ready
            refreshOutputResults()
            // 默认选一个有代表性的输出：第一条有武器的战技。
            if let first = result.skills.outputs.first(where: { $0.kind == .skill }) ?? result.skills.outputs.first {
                select(output: first)
            }
        }
    }

    private struct Loaded: Sendable {
        let skills: SkillDataIndex
        let buffs: BuffRankerIndex
        let loadout: BuffLoadoutIndex
        let catalogError: String?
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

    /// 「全选」只勾**当前这一侧**的段：正常版与专注值不足版互为替代，两边一起勾会把同一击算两遍。
    func selectAllSegments() {
        selectedSegmentIDs = SkillDamageMath.selection(segments, useNoFp: useNoFp)
        refreshComposition()
    }

    func clearSegments() {
        selectedSegmentIDs = []
        refreshComposition()
    }

    /// 正常版与专注值不足版互斥切换。
    func setUseNoFp(_ value: Bool) {
        guard value != useNoFp else { return }
        useNoFp = value
        selectedSegmentIDs = SkillDamageMath.selection(segments, useNoFp: value)
        refreshComposition()
    }

    var hasNoFpVariant: Bool { segments.contains { $0.noFp } }

    private func refreshComposition() {
        composition = SkillDamageMath.composition(of: segments, selected: selectedSegmentIDs)
        refreshEvaluator()
    }

    // MARK: 生效判定

    var outputClass: LoadoutOutputClass {
        if let spell { return spell.isSorcery ? .sorcery : .incantation }
        return .skill
    }

    var loadoutOutput: LoadoutOutput {
        LoadoutOutput(
            outputClass: outputClass,
            skillID: skill?.id,
            spellID: spell?.id,
            weaponID: skill == nil ? nil : weapon?.id,
            weaponWepType: skill == nil ? nil : weapon?.wepType,
            hand: weaponSlot,
            shares: composition.shares,
            attackContexts: includedAttackContexts
        )
    }

    private func refreshEvaluator() {
        guard let loadoutIndex else { return }
        let evaluator = LoadoutEvaluator(index: loadoutIndex, output: loadoutOutput)
        self.evaluator = evaluator
        contextOptions = evaluator.attackContextOptions()
        let valid = Set(contextOptions.map(\.key))
        if !includedAttackContexts.isSubset(of: valid) {
            includedAttackContexts = includedAttackContexts.intersection(valid)
        }
        overviewRows = evaluator.overview()
        overviewPage = 0
        refreshLoadout()
    }

    func toggleAttackContext(_ key: String) {
        if includedAttackContexts.contains(key) {
            includedAttackContexts.remove(key)
        } else {
            includedAttackContexts.insert(key)
        }
        refreshEvaluator()
    }

    // MARK: 配置：计算

    /// 配置变了：重算汇总与各栏候选（候选的「当前倍率」取决于已勾的条件与层数）。
    private func refreshLoadout() {
        guard let evaluator else { return }
        evaluation = evaluator.evaluate(loadout)
        refreshCandidates()
    }

    private func refreshCandidates() {
        guard let evaluator else { return }
        weaponAffixCandidates = evaluator.candidates(
            for: .weaponAffix, loadout: loadout, weaponTypeFilter: weaponTypeFilter
        )
        accessoryCandidates = evaluator.candidates(for: .accessory, loadout: loadout)
        var others: [LoadoutColumn: [LoadoutCandidate]] = [:]
        for column in LoadoutColumn.otherColumns {
            others[column] = evaluator.candidates(for: column, loadout: loadout)
        }
        otherCandidates = others
    }

    private func mutate(_ change: (inout BuffLoadout) -> Void) {
        var copy = loadout
        change(&copy)
        guard copy != loadout else { return }
        loadout = copy
        modeNotice = nil
        refreshLoadout()
    }

    var supportsLoadout: Bool { loadoutIndex?.supportsLoadout ?? false }
    var slotRules: BuffSlotRules { loadoutIndex?.slotRules ?? .fallback }

    // MARK: 模式 / 全局开关

    func setMode(_ mode: LoadoutMode) {
        guard let loadoutIndex, mode != loadout.mode else { return }
        var copy = loadout
        let removed = copy.setMode(mode, rules: loadoutIndex.slotRules, weaponAffixes: loadoutIndex.weaponAffixByID)
        loadout = copy
        modeNotice = removed > 0 ? LoadoutText.modeTrimmed(removed) : nil
        refreshLoadout()
    }

    func setStackSelfMultiply(_ value: Bool) {
        mutate { $0.stackSelfCopiesMultiply = value }
    }

    func fillRecommended() {
        guard let evaluator else { return }
        let filled = evaluator.recommendedFill(loadout, weaponTypeFilter: weaponTypeFilter)
        mutate { $0 = filled }
    }

    func clearLoadout() {
        guard let loadoutIndex else { return }
        var fresh = BuffLoadout(mode: loadout.mode, rules: loadoutIndex.slotRules)
        fresh.stackSelfCopiesMultiply = loadout.stackSelfCopiesMultiply
        mutate { $0 = fresh }
    }

    // MARK: 武器词条

    /// 武器词条栏的武器类别过滤：当前武器的 wepType（法术 / 选了「全部」时为 nil）。
    var weaponTypeFilter: Int? {
        guard !weaponFilterAll, skill != nil else { return nil }
        return weapon?.wepType
    }

    var weaponTypeName: String? {
        guard let weapon else { return nil }
        if let label = loadoutIndex?.dataset.wepTypeLabels[weapon.wepType] { return label }
        return weapon.wepTypeZh.isEmpty ? nil : weapon.wepTypeZh
    }

    func weaponAffixCount(_ id: Int) -> Int { loadout.weaponAffixCounts[id] ?? 0 }

    /// 还能不能再加一条：正面词条总数、深夜专属数、诅咒数都受上限约束。
    func canIncrementWeaponAffix(_ info: BuffWeaponAffixInfo) -> Bool {
        guard info.isAvailable(in: loadout.mode) else { return false }
        let rules = slotRules
        if info.isCurse {
            return evaluation.curseUsage.used < rules.curseCap(loadout.mode)
        }
        if evaluation.weaponAffixUsage.used >= rules.weaponAffixCap(loadout.mode) { return false }
        if info.deepOnlyPositive && evaluation.deepOnlyUsage.used >= rules.deepOnlyCap(loadout.mode) { return false }
        return true
    }

    func changeWeaponAffix(_ info: BuffWeaponAffixInfo, by delta: Int) {
        if delta > 0 && !canIncrementWeaponAffix(info) { return }
        mutate { loadout in
            let next = max(0, (loadout.weaponAffixCounts[info.attachEffectId] ?? 0) + delta)
            loadout.weaponAffixCounts[info.attachEffectId] = next == 0 ? nil : next
        }
    }

    /// 同一词条（paramName 去掉「 - Potency N」后相同）的另一个档位也选了：按独立键相乘，属于参数推断。
    /// 分组口径与汇总面板的提示同一套（`BuffLoadoutIndex.selectedTierFamilies`），不用 compatibilityId。
    func hasSelectedTierSibling(_ info: BuffWeaponAffixInfo) -> Bool {
        guard weaponAffixCount(info.attachEffectId) > 0, let loadoutIndex else { return false }
        return loadoutIndex.selectedTierFamilies(loadout).contains { $0.contains(info.attachEffectId) }
    }

    /// 已选、但不在当前武器类别过滤里的词条（仍占槽、仍计入；列出来是为了能在这一栏里减掉）。
    func isOutsideWeaponFilter(_ info: BuffWeaponAffixInfo) -> Bool {
        guard let filter = weaponTypeFilter else { return false }
        return !info.weaponTypes(in: loadout.mode).contains(filter)
    }

    var visibleWeaponAffixCandidates: [LoadoutCandidate] {
        filtered(weaponAffixCandidates, query: weaponAffixQuery, keepSelected: { candidate in
            if case .weaponAffix(let id) = candidate.item.kind { return self.weaponAffixCount(id) > 0 }
            return false
        })
    }

    // MARK: 遗物

    func setRelicChoice(_ cardIndex: Int, _ choice: LoadoutRelicCard.Choice) {
        mutate { loadout in
            guard loadout.relicCards.indices.contains(cardIndex) else { return }
            let deep = loadout.relicCards[cardIndex].isDeepSlot
            switch choice {
            case .empty:
                loadout.relicCards[cardIndex] = LoadoutRelicCard(isDeepSlot: deep)
            case .custom:
                if loadout.relicCards[cardIndex].choice != .custom {
                    loadout.relicCards[cardIndex] = LoadoutRelicCard(isDeepSlot: deep, choice: .custom)
                }
            case .fixed(let index):
                loadout.relicCards[cardIndex] = LoadoutRelicCard(isDeepSlot: deep, choice: .fixed(index))
            }
        }
    }

    func setRelicAffix(_ cardIndex: Int, row: Int, affixID: Int?) {
        mutate { loadout in
            guard loadout.relicCards.indices.contains(cardIndex), (0..<3).contains(row) else { return }
            var card = loadout.relicCards[cardIndex]
            card.choice = .custom
            card.rows[row].affixID = affixID
            // 换了词条：不再需要诅咒的行把诅咒清掉（诅咒只配需诅咒的词条）。
            let needsCurse = affixID.flatMap { loadoutIndex?.catalogAffixes[$0]?.requiresCurse } ?? false
            if !needsCurse { card.rows[row].curseID = nil }
            loadout.relicCards[cardIndex] = card
        }
    }

    func setRelicCurse(_ cardIndex: Int, row: Int, curseID: Int?) {
        mutate { loadout in
            guard loadout.relicCards.indices.contains(cardIndex), (0..<3).contains(row) else { return }
            loadout.relicCards[cardIndex].rows[row].curseID = curseID
        }
    }

    /// 自组遗物某一行的候选（普通格／深夜格各自的口径），附带「选上以后这件遗物是否合法」。
    func relicAffixChoices(cardIndex: Int, row: Int) -> [RelicAffixChoice] {
        guard let evaluator, let loadoutIndex, loadout.relicCards.indices.contains(cardIndex) else { return [] }
        let card = loadout.relicCards[cardIndex]
        let candidates = evaluator.candidates(for: .relic, loadout: loadout, relicDeep: card.isDeepSlot)
        return candidates.map { candidate in
            var trial = card
            trial.choice = .custom
            if let affix = candidate.item.relicAffix {
                trial.rows[row].affixID = affix.effectID
                if !affix.requiresCurse { trial.rows[row].curseID = nil }
            }
            let check = loadoutIndex.relicCheck(trial)
            // 只看这条词条自己惹出的问题（没配诅咒是下一步的事，不算）。
            let blocking = check.issues.first { issue in
                issue.kind != .cursePairing || issue.title != LoadoutText.curseMissingTitle
            }
            return RelicAffixChoice(candidate: candidate, blockingIssue: blocking)
        }
    }

    func curseChoices(cardIndex: Int, row: Int) -> [CurseChoice] {
        guard let loadoutIndex, loadout.relicCards.indices.contains(cardIndex) else { return [] }
        let card = loadout.relicCards[cardIndex]
        return loadoutIndex.curseAffixes.map { curse in
            var trial = card
            trial.rows[row].curseID = curse.effectID
            let issue = loadoutIndex.relicCheck(trial).issues.first { $0.effectIDs.contains(curse.effectID) }
            return CurseChoice(affix: curse, blockingIssue: issue)
        }
    }

    func fixedRelicChoices(cardIndex: Int) -> [LoadoutCandidate] {
        guard let evaluator, loadout.relicCards.indices.contains(cardIndex) else { return [] }
        return evaluator.fixedRelicCandidates(loadout: loadout, deepSlot: loadout.relicCards[cardIndex].isDeepSlot)
    }

    /// 已装在别的遗物格的固定遗物（同一件只能装一件）。
    func fixedRelicUsedElsewhere(_ fixedIndex: Int, cardIndex: Int) -> Bool {
        loadout.relicCards.enumerated().contains { $0.offset != cardIndex && $0.element.fixedIndex == fixedIndex }
    }

    /// 这张卡里某条词条 / 某件固定遗物的逐条 buff（汇总里取，便于显示状态与条件控件）。
    func lines(forRelicCard cardIndex: Int) -> [LoadoutLine] {
        let prefix = "遗物 \(cardIndex + 1)"
        return evaluation.lines.filter { line in line.sources.contains { $0.hasPrefix(prefix) } }
    }

    // MARK: 护符 / 其它增益 / 武器固有

    func isAccessorySelected(_ id: Int) -> Bool { loadout.accessories.contains(id) }

    var accessoryFull: Bool { loadout.accessories.count >= slotRules.accessorySlots }

    func toggleAccessory(_ id: Int) {
        mutate { loadout in
            if let position = loadout.accessories.firstIndex(of: id) {
                loadout.accessories.remove(at: position)
            } else if loadout.accessories.count < slotRules.accessorySlots {
                loadout.accessories.append(id)
            }
        }
    }

    /// 不占槽位的条目是否在用（武器固有里当前武器自带的：没被去掉就算在用）。
    func isSelected(_ item: LoadoutItem) -> Bool {
        guard case .buff(let id) = item.kind else { return false }
        if item.isAutoInnate { return !loadout.excludedInnate.contains(id) }
        return !itemBuffIDs(item).isEmpty && itemBuffIDs(item).allSatisfy { loadout.selectedBuffs.contains($0) }
    }

    /// 条目里的全部 spEffectId（累积阶梯合成的一项含各档）。
    private func itemBuffIDs(_ item: LoadoutItem) -> [Int] {
        guard let loadoutIndex else { return [] }
        return item.buffIndices.map { loadoutIndex.dataset.buffs[$0].spEffectId }
    }

    func toggleSlotless(_ item: LoadoutItem) {
        guard case .buff(let id) = item.kind else { return }
        let ids = itemBuffIDs(item)
        let selected = isSelected(item)
        let ladder = item.buffIndices.first.flatMap { loadoutIndex?.dataset.buffs[$0].accumulatorLadder }
        let stackInputs: [(Int, BuffStackInput)] = item.buffIndices.compactMap { offset in
            guard let buff = loadoutIndex?.dataset.buffs[offset], let input = buff.stackInput else { return nil }
            return (buff.spEffectId, input)
        }
        mutate { loadout in
            if item.isAutoInnate {
                if loadout.excludedInnate.contains(id) {
                    loadout.excludedInnate.remove(id)
                } else {
                    loadout.excludedInnate.insert(id)
                }
            } else if selected {
                for buffID in ids { loadout.selectedBuffs.remove(buffID) }
            } else {
                for buffID in ids { loadout.selectedBuffs.insert(buffID) }
                // 不占槽位的累积阶梯：勾上即在用，没选过档就先取数据里实际收录的最高档（可在行内改）。
                if let ladder, (loadout.ladderTiers[ladder.ladderID] ?? 0) == 0 {
                    loadout.ladderTiers[ladder.ladderID] = loadoutIndex?.ladderTopTier(ladder.ladderID) ?? ladder.tier
                }
                // 叠层：没填过层数就先填「一局实际上限」，没有实测上限的填 1（可在行内改）。
                for (id, input) in stackInputs where (loadout.stackCounts[id] ?? 0) == 0 {
                    loadout.stackCounts[id] = min(input.practicalMaxStacks ?? 1, input.maxAllowedStacks)
                }
            }
        }
    }

    var visibleOtherCandidates: [LoadoutCandidate] {
        filtered(otherCandidates[otherColumn] ?? [], query: otherQuery, keepSelected: { self.isSelected($0.item) })
    }

    func otherCount(_ column: LoadoutColumn) -> Int {
        (otherCandidates[column] ?? []).filter { showInapplicable || $0.isUseful || isSelected($0.item) }.count
    }

    var visibleAccessoryCandidates: [LoadoutCandidate] {
        filtered(accessoryCandidates, query: "", keepSelected: { candidate in
            if case .accessory(let id) = candidate.item.kind { return self.isAccessorySelected(id) }
            return false
        })
    }

    /// 「显示不生效项」关闭时隐藏不生效（以及对当前构成没有任何增益）的条目，但已选的一律留着（否则取消不掉）。
    private func filtered(
        _ list: [LoadoutCandidate], query: String, keepSelected: (LoadoutCandidate) -> Bool
    ) -> [LoadoutCandidate] {
        let needle = query.foldedForSearch
        return list.filter { candidate in
            guard candidate.item.matches(foldedQuery: needle) else { return false }
            return showInapplicable || candidate.isUseful || keepSelected(candidate)
        }
    }

    // MARK: 条件 / 层数 / 选档

    func isConfirmed(_ spEffectId: Int) -> Bool { loadout.confirmed.contains(spEffectId) }

    func toggleConfirmed(_ spEffectId: Int) {
        mutate { loadout in
            if loadout.confirmed.contains(spEffectId) {
                loadout.confirmed.remove(spEffectId)
            } else {
                loadout.confirmed.insert(spEffectId)
            }
        }
    }

    func stacks(_ spEffectId: Int) -> Int { loadout.stackCounts[spEffectId] ?? 0 }

    func setStacks(_ spEffectId: Int, _ value: Int, max: Int) {
        let clamped = Swift.max(0, Swift.min(value, max))
        mutate { $0.stackCounts[spEffectId] = clamped == 0 ? nil : clamped }
    }

    func ladderTier(_ ladderID: Int) -> Int { loadout.ladderTiers[ladderID] ?? 0 }

    /// 选档控件列出的档位：只列数据里真实存在的档（accumulatorLadder.tiers 可能比实际收录的多）。
    func ladderTierOptions(_ ladder: BuffAccumulatorLadder) -> [Int] {
        let options = loadoutIndex?.ladderTierOptions(ladder.ladderID) ?? []
        return options.isEmpty ? [ladder.tier] : options
    }

    func setLadderTier(_ ladderID: Int, _ tier: Int) {
        mutate { $0.ladderTiers[ladderID] = tier <= 0 ? nil : tier }
    }

    func buff(_ line: LoadoutLine) -> BuffEntry? {
        guard let loadoutIndex, loadoutIndex.dataset.buffs.indices.contains(line.buffIndex) else { return nil }
        return loadoutIndex.dataset.buffs[line.buffIndex]
    }

    // MARK: 全部增益一览

    var overviewVisibleRows: [LoadoutOverviewRow] {
        let needle = overviewQuery.foldedForSearch
        return overviewRows.filter { row in
            (showInapplicable || row.verdict.isApplicable) && (needle.isEmpty || row.searchKey.contains(needle))
        }
    }

    var overviewPageCount: Int {
        max(1, Int(ceil(Double(overviewVisibleRows.count) / Double(overviewPageSize))))
    }

    var overviewPageRows: [LoadoutOverviewRow] {
        let rows = overviewVisibleRows
        let start = overviewPage * overviewPageSize
        guard start < rows.count else { return [] }
        return Array(rows[start..<min(start + overviewPageSize, rows.count)])
    }

    func goToOverviewPage(_ index: Int) {
        overviewPage = max(0, min(index, overviewPageCount - 1))
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

/// 自组遗物某一行的一个候选词条。
struct RelicAffixChoice: Identifiable {
    let candidate: LoadoutCandidate
    /// 选上以后这件遗物会不合法的原因（没配诅咒不算）。
    let blockingIssue: CheckIssue?

    var id: String { candidate.id }
}

struct CurseChoice: Identifiable {
    let affix: Affix
    let blockingIssue: CheckIssue?

    var id: Int { affix.effectID }
}
