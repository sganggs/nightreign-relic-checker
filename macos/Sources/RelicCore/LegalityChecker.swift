import Foundation

public enum CheckStatus: String, Codable, Sendable {
    case incomplete
    case valid
    case wrongOrder
    case invalid
}

public enum IssueKind: String, Codable, Sendable {
    case duplicate
    case conflict
    case unavailable
    case cursePairing
}

public struct CheckIssue: Codable, Hashable, Sendable, Identifiable {
    public let kind: IssueKind
    public let title: String
    public let detail: String
    public let effectIDs: [Int]

    public var id: String { "\(kind.rawValue)-\(effectIDs.map(String.init).joined(separator: "-"))" }
}

public struct CheckResult: Codable, Sendable {
    public let status: CheckStatus
    public let message: String
    public let orderedAffixes: [Affix]
    public let issues: [CheckIssue]
    public let warnings: [CheckIssue]

    public init(
        status: CheckStatus,
        message: String,
        orderedAffixes: [Affix] = [],
        issues: [CheckIssue] = [],
        warnings: [CheckIssue] = []
    ) {
        self.status = status
        self.message = message
        self.orderedAffixes = orderedAffixes
        self.issues = issues
        self.warnings = warnings
    }
}

public struct LegalityChecker: Sendable {
    public init() {}

    public func check(_ affixes: [Affix], mode: CheckMode) -> CheckResult {
        guard affixes.count == 3 else {
            return CheckResult(status: .incomplete, message: "请选择三个词条")
        }

        var issues: [CheckIssue] = []
        var warnings: [CheckIssue] = []

        let duplicates = Dictionary(grouping: affixes, by: \.effectID).values.filter { $0.count > 1 }
        for group in duplicates {
            issues.append(CheckIssue(
                kind: .duplicate,
                title: "词条重复",
                detail: "同一个效果不能在一件遗物上出现两次：\(group[0].name)",
                effectIDs: group.map(\.effectID)
            ))
        }

        let conflictGroups = Dictionary(
            grouping: affixes.filter { $0.compatibilityID != -1 },
            by: \.compatibilityID
        ).values.filter { $0.count > 1 }

        for group in conflictGroups {
            issues.append(CheckIssue(
                kind: .conflict,
                title: "同一互斥池",
                detail: group.map(\.name).joined(separator: "、") + " 不能同时出现",
                effectIDs: group.map(\.effectID)
            ))
        }

        if mode != .compatibilityOnly && !hasPoolAssignment(
            affixes,
            slotPoolSequences: mode.slotPoolSequences
        ) {
            let eligiblePoolIDs = Set(mode.eligiblePoolIDs)
            let unavailable = affixes.filter { affix in
                Set(affix.poolIDs).isDisjoint(with: eligiblePoolIDs)
            }
            let names = unavailable.isEmpty ? affixes.map(\.name) : unavailable.map(\.name)
            issues.append(CheckIssue(
                kind: .unavailable,
                title: unavailable.isEmpty ? "不符合当前槽池模板" : "不在当前出货池",
                detail: names.joined(separator: "、") + (unavailable.isEmpty
                    ? " 无法分配到任一真实的三词条槽池模板"
                    : " 不属于当前校验口径的非零权重出货池"),
                effectIDs: (unavailable.isEmpty ? affixes : unavailable).map(\.effectID)
            ))
        }

        if mode == .deepPositive {
            let curseBound = affixes.filter(\.requiresCurse)
            let curseNames = curseBound.map(\.name).joined(separator: "、")
            let curseRequirement = curseBound.isEmpty
                ? "其中没有仅 A 池词条；"
                : "其中 \(curseBound.count) 条为仅 A 池词条，至少需要 \(curseBound.count) 个对应诅咒槽；"
            let detail = curseRequirement +
                "当前仅预检三条正面效果，完整深夜遗物仍需结合具体遗物 ID、实际槽池模板与负面词条验证。" +
                (curseNames.isEmpty ? "" : "仅 A 池词条：\(curseNames)")
            warnings.append(CheckIssue(
                kind: .cursePairing,
                title: "深夜模式仅作预检",
                detail: detail,
                effectIDs: curseBound.map(\.effectID)
            ))
        }

        let ordered = canonicalOrder(affixes)
        if !issues.isEmpty {
            return CheckResult(
                status: .invalid,
                message: "该三词条组合不合法",
                orderedAffixes: ordered,
                issues: issues,
                warnings: warnings
            )
        }

        if ordered.map(\.effectID) != affixes.map(\.effectID) {
            return CheckResult(
                status: .wrongOrder,
                message: "组合本身可成立，但词条顺序错误",
                orderedAffixes: ordered,
                warnings: warnings
            )
        }

        return CheckResult(
            status: .valid,
            message: mode == .deepPositive
                ? "正面词条预检通过；不等同于完整深夜遗物合法"
                : "该三词条组合合法，顺序正确",
            orderedAffixes: ordered,
            warnings: warnings
        )
    }

    public func canonicalOrder(_ affixes: [Affix]) -> [Affix] {
        affixes.sorted {
            if $0.sortID == $1.sortID { return $0.effectID < $1.effectID }
            return $0.sortID < $1.sortID
        }
    }

    public func hasPoolAssignment(_ affixes: [Affix], slotPools: [Int]) -> Bool {
        guard affixes.count == slotPools.count else { return false }
        if slotPools.isEmpty { return true }

        return permutations(of: Array(affixes.indices)).contains { permutation in
            zip(permutation, slotPools).allSatisfy { index, poolID in
                affixes[index].poolIDs.contains(poolID)
            }
        }
    }

    public func hasPoolAssignment(_ affixes: [Affix], slotPoolSequences: [[Int]]) -> Bool {
        slotPoolSequences.contains { slotPools in
            hasPoolAssignment(affixes, slotPools: slotPools)
        }
    }

    public func randomCombination(from catalog: [Affix], mode: CheckMode) -> [Affix]? {
        let candidates = catalog.filter { $0.isEligible(for: mode) }
        guard candidates.count >= 3 else { return nil }

        for _ in 0..<6_000 {
            let sample = Array(candidates.shuffled().prefix(3))
            let ordered = canonicalOrder(sample)
            let result = check(ordered, mode: mode)
            if result.status == .valid { return ordered }
        }
        return nil
    }

    private func permutations<T>(of values: [T]) -> [[T]] {
        guard let first = values.first else { return [[]] }
        let tail = Array(values.dropFirst())
        return permutations(of: tail).flatMap { permutation in
            (0...permutation.count).map { index in
                var copy = permutation
                copy.insert(first, at: index)
                return copy
            }
        }
    }
}
