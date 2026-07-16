import Foundation

public enum RelicAuditStatus: String, Codable, Sendable {
    case valid
    case invalid
}

public enum RelicIssueKind: String, Codable, Sendable {
    case unknownItem
    case illegalRange
    case outOfRange
    case unknownEffect
    case duplicate
    case conflict
    case effectUnexpected
    case effectMissing
    case slotMismatch
    case curseUnexpected
    case curseMissing
    case curseMismatch
    case wrongOrder
    case uniqueDuplicate
    case fixedPool
}

public struct RelicAuditIssue: Codable, Hashable, Sendable, Identifiable {
    public let kind: RelicIssueKind
    public let title: String
    public let detail: String
    public let effectIDs: [Int]

    public var id: String { "\(kind.rawValue)-\(effectIDs.map(String.init).joined(separator: "-"))-\(detail.hashValue)" }

    private enum CodingKeys: String, CodingKey {
        case kind
        case title
        case detail
        case effectIDs = "effectIds"
    }

    public init(kind: RelicIssueKind, title: String, detail: String, effectIDs: [Int]) {
        self.kind = kind
        self.title = title
        self.detail = detail
        self.effectIDs = effectIDs
    }
}

public struct RelicAuditResult: Codable, Sendable {
    public var status: RelicAuditStatus
    public var issues: [RelicAuditIssue]
    public var warnings: [RelicAuditIssue]
    public var orderedEffects: [Int]?

    public init(
        status: RelicAuditStatus,
        issues: [RelicAuditIssue] = [],
        warnings: [RelicAuditIssue] = [],
        orderedEffects: [Int]? = nil
    ) {
        self.status = status
        self.issues = issues
        self.warnings = warnings
        self.orderedEffects = orderedEffects
    }
}

/// 审计所需的词条索引条目（affixes.json ∪ extraAffixes）。
public struct AuditAffix: Hashable, Sendable {
    public let effectID: Int
    public let name: String
    public let sortID: Int
    public let compatibilityID: Int
    public let isCurse: Bool
    public let requiresCurse: Bool

    public init(effectID: Int, name: String, sortID: Int, compatibilityID: Int, isCurse: Bool, requiresCurse: Bool) {
        self.effectID = effectID
        self.name = name
        self.sortID = sortID
        self.compatibilityID = compatibilityID
        self.isCurse = isCurse
        self.requiresCurse = requiresCurse
    }
}

public struct RelicAuditContext: Sendable {
    public let relicsByID: [Int: RelicInfo]
    public let pools: [Int: Set<Int>]
    public let deepUnionPool: Set<Int>
    public let affixIndex: [Int: AuditAffix]

    static let deepPositivePoolIDs: Set<Int> = [2_000_000, 2_100_000, 2_200_000]
    static let deepCursePoolID = 3_000_000

    public init(catalog: AffixCatalog, relicData: RelicCatalog) {
        var index: [Int: AuditAffix] = [:]
        for affix in catalog.affixes {
            index[affix.effectID] = AuditAffix(
                effectID: affix.effectID,
                name: affix.name,
                sortID: affix.sortID,
                compatibilityID: affix.compatibilityID,
                isCurse: affix.isCurse,
                requiresCurse: affix.requiresCurse
            )
        }
        for extra in relicData.extraAffixes where index[extra.effectID] == nil {
            index[extra.effectID] = AuditAffix(
                effectID: extra.effectID,
                name: extra.name,
                sortID: extra.sortID,
                compatibilityID: extra.compatibilityID,
                isCurse: false,
                requiresCurse: false
            )
        }
        affixIndex = index

        relicsByID = Dictionary(relicData.relics.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        var poolSets: [Int: Set<Int>] = [:]
        for (key, effectIDs) in relicData.pools {
            guard let poolID = Int(key) else { continue }
            poolSets[poolID] = Set(effectIDs)
        }
        pools = poolSets
        deepUnionPool = Self.deepPositivePoolIDs.reduce(into: Set<Int>()) { union, poolID in
            union.formUnion(poolSets[poolID] ?? [])
        }
    }
}

/// 遗物种类判定用的唯一遗物 ID 区段。
public func isUniqueRelicID(_ id: Int) -> Bool {
    (1000...2100).contains(id) || (10000...19999).contains(id)
}

public func relicKindLabel(id: Int, info: RelicInfo?) -> String {
    if info?.deep == true { return "深夜遗物" }
    if isUniqueRelicID(id) { return "唯一遗物" }
    if (100...199).contains(id) { return "商店遗物（旧版）" }
    if (200...299).contains(id) { return "商店遗物" }
    if (1_000_000...1_009_999).contains(id) { return "对局奖励" }
    return "遗物"
}

public func relicColorLabel(_ color: Int) -> String {
    switch color {
    case 0: return "红"
    case 1: return "蓝"
    case 2: return "黄"
    case 3: return "绿"
    case 4: return "白"
    default: return "未知"
    }
}

public func relicDisplayName(id: Int, info: RelicInfo?) -> String {
    guard let info else { return "未知遗物 #\(id)" }
    return info.name.isEmpty ? "未命名遗物 #\(id)" : info.name
}

public struct RelicAuditor: Sendable {
    /// 排列 p 表示存档对 j 放入模板槽位 p[j]。顺序与契约一致。
    static let pairPermutations: [[Int]] = [
        [0, 1, 2], [0, 2, 1], [1, 0, 2], [1, 2, 0], [2, 0, 1], [2, 1, 0]
    ]

    private struct SlotProblem {
        let kind: RelicIssueKind
        let rank: Int
        let pairIndex: Int
        let effectID: Int?
    }

    public init() {}

    public func audit(_ relic: SaveRelic, context: RelicAuditContext) -> RelicAuditResult {
        var issues: [RelicAuditIssue] = []
        var warnings: [RelicAuditIssue] = []
        var orderedEffects: [Int]? = nil

        let effects = padded(relic.effects)
        let curses = padded(relic.curses)
        let itemID = relic.itemID

        // 1. 未知遗物 ID：无法继续，跳过其余检查
        guard let info = context.relicsByID[itemID] else {
            issues.append(RelicAuditIssue(
                kind: .unknownItem,
                title: "未知遗物 ID",
                detail: "遗物 ID \(itemID) 不在遗物数据表中，无法继续校验词条。",
                effectIDs: []
            ))
            return RelicAuditResult(status: .invalid, issues: issues, warnings: warnings)
        }

        // 2. 作弊器常用区段
        if (20000...30035).contains(itemID) {
            issues.append(RelicAuditIssue(
                kind: .illegalRange,
                title: "处于作弊器常用 ID 区段",
                detail: "遗物 ID \(itemID) 落在 20000-30035 区段，正常游玩不会获得。",
                effectIDs: []
            ))
        }

        // 3. 合法 ID 范围
        if itemID < 100 || itemID > 2_013_322 {
            issues.append(RelicAuditIssue(
                kind: .outOfRange,
                title: "超出合法遗物 ID 范围",
                detail: "遗物 ID \(itemID) 不在 100-2013322 的合法范围内。",
                effectIDs: []
            ))
        }

        // 4. 未知词条：无法继续词条级检查
        let unknownIDs = orderedUnique((effects + curses).filter { $0 != -1 && context.affixIndex[$0] == nil })
        if !unknownIDs.isEmpty {
            issues.append(RelicAuditIssue(
                kind: .unknownEffect,
                title: "存在未知词条 ID",
                detail: "以下词条 ID 不在词条索引中：" + unknownIDs.map(String.init).joined(separator: "、"),
                effectIDs: unknownIDs
            ))
            return RelicAuditResult(status: .invalid, issues: issues, warnings: warnings)
        }

        let nonEmptyAll = (effects + curses).filter { $0 != -1 }

        // 5. 词条重复
        let duplicated = orderedUnique(nonEmptyAll.filter { id in nonEmptyAll.filter { $0 == id }.count > 1 })
        if !duplicated.isEmpty {
            issues.append(RelicAuditIssue(
                kind: .duplicate,
                title: "词条重复",
                detail: "同一词条在这件遗物上出现多次：" + duplicated.map { affixLabel($0, context) }.joined(separator: "、"),
                effectIDs: duplicated
            ))
        }

        // 6. 互斥词条
        let conflictGroups = Dictionary(
            grouping: nonEmptyAll.filter { context.affixIndex[$0]?.compatibilityID != -1 },
            by: { context.affixIndex[$0]?.compatibilityID ?? -1 }
        ).values.filter { $0.count > 1 }
        if !conflictGroups.isEmpty {
            let conflicting = orderedUnique(nonEmptyAll.filter { id in
                conflictGroups.contains { $0.contains(id) }
            })
            issues.append(RelicAuditIssue(
                kind: .conflict,
                title: "互斥词条同时出现",
                detail: conflicting.map { affixLabel($0, context) }.joined(separator: "、") + " 属于同一互斥组，不能同时出现。",
                effectIDs: conflicting
            ))
        }

        // 7. 槽池与诅咒配对：深夜遗物按行配对（真实存档实证，参数表中深夜
        // 遗物行的槽池排列与游戏实际生成不符）；非深夜遗物按参数行模板做
        // 6 种排列匹配，唯一遗物模板不符时降级为警告放行（本版参数表对
        // 部分唯一遗物记录不准确）。
        if info.deep {
            auditDeepRelic(effects: effects, curses: curses, info: info, context: context, issues: &issues)
        } else {
            var bestProblems: [SlotProblem]? = nil
            for permutation in Self.pairPermutations {
                let problems = slotProblems(effects: effects, curses: curses, info: info, permutation: permutation, context: context)
                if problems.isEmpty {
                    bestProblems = nil
                    break
                }
                if bestProblems == nil || problems.count < bestProblems!.count {
                    bestProblems = problems
                }
            }
            if let bestProblems {
                let sorted = bestProblems.sorted {
                    $0.rank == $1.rank ? $0.pairIndex < $1.pairIndex : $0.rank < $1.rank
                }
                let pairIssues = sorted.map { issue(for: $0, context: context) }
                if isUniqueRelicID(itemID) {
                    warnings.append(RelicAuditIssue(
                        kind: .fixedPool,
                        title: "固定词条与参数表不符（不视为非法）",
                        detail: "唯一遗物的词条由游戏固定发放；本版参数表对部分唯一遗物（如场景遗物）的记录不准确，已放行。不符项：" +
                            pairIssues.map(\.detail).joined(separator: "；"),
                        effectIDs: effects.filter { $0 != -1 }
                    ))
                } else {
                    issues.append(contentsOf: pairIssues)
                }
            }
        }

        // 10. 保存顺序
        if issues.isEmpty {
            let canonical = canonicalEffectOrder(effects, context: context)
            if canonical != effects {
                orderedEffects = canonical
                issues.append(RelicAuditIssue(
                    kind: .wrongOrder,
                    title: "保存顺序错误",
                    detail: "正面词条未按 (sortId, effectId) 升序保存，空槽应排在最后。",
                    effectIDs: effects.filter { $0 != -1 }
                ))
            }
        }

        return RelicAuditResult(
            status: issues.isEmpty ? .valid : .invalid,
            issues: issues,
            warnings: warnings,
            orderedEffects: orderedEffects
        )
    }

    /// 按角色的整体检查：唯一遗物重复持有。对该角色全部遗物的审计结果原地追加。
    public func applyUniqueDuplicates(_ results: inout [RelicAuditResult], relics: [SaveRelic]) {
        guard results.count == relics.count else { return }
        var groups: [Int: [Int]] = [:]
        for (index, relic) in relics.enumerated() where isUniqueRelicID(relic.itemID) {
            groups[relic.itemID, default: []].append(index)
        }
        for itemID in groups.keys.sorted() {
            let indices = groups[itemID]!
            guard indices.count > 1 else { continue }
            let exempt = indices.first { results[$0].status == .valid }
            for index in indices where index != exempt {
                results[index].issues.append(RelicAuditIssue(
                    kind: .uniqueDuplicate,
                    title: "唯一遗物重复持有",
                    detail: "同一角色持有多件唯一遗物（ID \(itemID)），仅首件合法者视为正常。",
                    effectIDs: []
                ))
                results[index].status = .invalid
            }
        }
    }

    public func canonicalEffectOrder(_ effects: [Int], context: RelicAuditContext) -> [Int] {
        let nonEmpty = effects.filter { $0 != -1 }
        let sorted = nonEmpty.sorted { lhs, rhs in
            let sortL = context.affixIndex[lhs]?.sortID ?? Int.max
            let sortR = context.affixIndex[rhs]?.sortID ?? Int.max
            if sortL == sortR { return lhs < rhs }
            return sortL < sortR
        }
        return sorted + Array(repeating: -1, count: effects.count - sorted.count)
    }

    private func slotProblems(
        effects: [Int],
        curses: [Int],
        info: RelicInfo,
        permutation: [Int],
        context: RelicAuditContext
    ) -> [SlotProblem] {
        var problems: [SlotProblem] = []
        for pairIndex in 0..<3 {
            let slotIndex = permutation[pairIndex]
            let slotPool = slotValue(info.slots, slotIndex)
            let cursePool = slotValue(info.curseSlots, slotIndex)
            let effect = effects[pairIndex]
            let curse = curses[pairIndex]

            if slotPool == -1 {
                if effect != -1 {
                    problems.append(SlotProblem(kind: .effectUnexpected, rank: 0, pairIndex: pairIndex, effectID: effect))
                }
            } else if effect == -1 {
                problems.append(SlotProblem(kind: .effectMissing, rank: 1, pairIndex: pairIndex, effectID: nil))
            } else if !rollable(slotPool, context: context).contains(effect) {
                problems.append(SlotProblem(kind: .slotMismatch, rank: 2, pairIndex: pairIndex, effectID: effect))
            }

            if cursePool == -1 {
                if curse != -1 {
                    problems.append(SlotProblem(kind: .curseUnexpected, rank: 3, pairIndex: pairIndex, effectID: curse))
                }
            } else if curse == -1 {
                problems.append(SlotProblem(kind: .curseMissing, rank: 4, pairIndex: pairIndex, effectID: effect == -1 ? nil : effect))
            } else if !rollable(cursePool, context: context).contains(curse) {
                problems.append(SlotProblem(kind: .curseMismatch, rank: 5, pairIndex: pairIndex, effectID: curse))
            }
        }
        return problems
    }

    private func rollable(_ poolID: Int, context: RelicAuditContext) -> Set<Int> {
        context.pools[poolID] ?? []
    }

    /// 深夜遗物按行配对模型（与 windows/renderer/core.js 的 auditDeepRelic 一致）：
    /// 词条数 = 槽数；正面词条 ∈ A/B/C 池并集；第 i 行「需诅咒」⇔ 第 i 行有
    /// 负面词条；负面词条 ∈ 诅咒池。
    private func auditDeepRelic(
        effects: [Int],
        curses: [Int],
        info: RelicInfo,
        context: RelicAuditContext,
        issues: inout [RelicAuditIssue]
    ) {
        let slotCount = info.slots.filter { $0 != -1 }.count
        let effectCount = effects.filter { $0 != -1 }.count
        if effectCount < slotCount {
            issues.append(RelicAuditIssue(
                kind: .effectMissing,
                title: "正面词条数量不足",
                detail: "该遗物应有 \(slotCount) 条正面词条，实有 \(effectCount) 条",
                effectIDs: []
            ))
        } else if effectCount > slotCount {
            issues.append(RelicAuditIssue(
                kind: .effectUnexpected,
                title: "正面词条数量超出",
                detail: "该遗物应有 \(slotCount) 条正面词条，实有 \(effectCount) 条",
                effectIDs: []
            ))
        }
        for row in 0..<3 {
            let effect = effects[row]
            if effect != -1, !context.deepUnionPool.contains(effect) {
                issues.append(RelicAuditIssue(
                    kind: .slotMismatch,
                    title: "正面词条不在深夜词条池",
                    detail: "第 \(row + 1) 行的正面词条不在深夜词条池中：\(affixLabel(effect, context))",
                    effectIDs: [effect]
                ))
            }
        }
        for row in 0..<3 {
            let effect = effects[row]
            let curse = curses[row]
            let needsCurse = effect != -1 && context.affixIndex[effect]?.requiresCurse == true
            if needsCurse, curse == -1 {
                issues.append(RelicAuditIssue(
                    kind: .curseMissing,
                    title: "需诅咒的词条缺少负面词条",
                    detail: "第 \(row + 1) 行的正面词条需要配对负面词条：\(affixLabel(effect, context))",
                    effectIDs: [effect]
                ))
            } else if !needsCurse, curse != -1 {
                issues.append(RelicAuditIssue(
                    kind: .curseUnexpected,
                    title: "多余的负面词条",
                    detail: "第 \(row + 1) 行的正面词条不需要负面词条，却携带负面词条：\(affixLabel(curse, context))",
                    effectIDs: [curse]
                ))
            }
        }
        for row in 0..<3 {
            let curse = curses[row]
            if curse != -1, !rollable(RelicAuditContext.deepCursePoolID, context: context).contains(curse) {
                issues.append(RelicAuditIssue(
                    kind: .curseMismatch,
                    title: "负面词条不在诅咒池",
                    detail: "第 \(row + 1) 行的负面词条不在诅咒池：\(affixLabel(curse, context))",
                    effectIDs: [curse]
                ))
            }
        }
    }

    private func issue(for problem: SlotProblem, context: RelicAuditContext) -> RelicAuditIssue {
        let row = problem.pairIndex + 1
        let label = problem.effectID.map { affixLabel($0, context) } ?? ""
        let effectIDs = problem.effectID.map { [$0] } ?? []
        switch problem.kind {
        case .effectUnexpected:
            return RelicAuditIssue(
                kind: .effectUnexpected,
                title: "多余的正面词条",
                detail: "第 \(row) 行对应的模板槽位不存在，却出现正面词条 \(label)。",
                effectIDs: effectIDs
            )
        case .effectMissing:
            return RelicAuditIssue(
                kind: .effectMissing,
                title: "正面词条缺失",
                detail: "第 \(row) 行对应的模板槽位需要正面词条，但该行为空。",
                effectIDs: effectIDs
            )
        case .slotMismatch:
            return RelicAuditIssue(
                kind: .slotMismatch,
                title: "正面词条不在对应槽池",
                detail: "第 \(row) 行的正面词条 \(label) 不在对应槽位的可掉落池中。",
                effectIDs: effectIDs
            )
        case .curseUnexpected:
            return RelicAuditIssue(
                kind: .curseUnexpected,
                title: "多余的负面词条",
                detail: "第 \(row) 行对应的诅咒槽不存在，却出现负面词条 \(label)。",
                effectIDs: effectIDs
            )
        case .curseMissing:
            return RelicAuditIssue(
                kind: .curseMissing,
                title: "需诅咒的词条缺少负面词条",
                detail: "第 \(row) 行的诅咒槽不允许为空" + (label.isEmpty ? "。" : "：\(label)。"),
                effectIDs: effectIDs
            )
        case .curseMismatch:
            return RelicAuditIssue(
                kind: .curseMismatch,
                title: "负面词条不在诅咒池",
                detail: "第 \(row) 行的负面词条 \(label) 不在诅咒池的可掉落集合中。",
                effectIDs: effectIDs
            )
        default:
            return RelicAuditIssue(kind: problem.kind, title: "", detail: "", effectIDs: effectIDs)
        }
    }

    private func affixLabel(_ effectID: Int, _ context: RelicAuditContext) -> String {
        if let name = context.affixIndex[effectID]?.name, !name.isEmpty {
            return "\(name)（\(effectID)）"
        }
        return String(effectID)
    }

    private func slotValue(_ slots: [Int], _ index: Int) -> Int {
        slots.indices.contains(index) ? slots[index] : -1
    }

    // 补长并归一化空哨兵（0 / 0xFFFFFFFF / 负值 → -1），与 JS 端 normalizeTriple 一致；
    // 解析器已归一化，这里是直接调用审计 API 时的防御。
    private func padded(_ values: [Int]) -> [Int] {
        let filled = Array((values + Array(repeating: -1, count: 3)).prefix(3))
        return filled.map { ($0 <= 0 || $0 == 0xFFFF_FFFF) ? -1 : $0 }
    }

    private func orderedUnique(_ values: [Int]) -> [Int] {
        var seen: Set<Int> = []
        return values.filter { seen.insert($0).inserted }
    }
}
