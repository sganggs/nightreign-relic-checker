import Foundation

// 「增伤排名」页（配置版）：自己组一套配置，汇总成一个总倍率。
//
// 页面结构：输出手段（战技／法术 + 武器 + 分段 + 伤害构成，沿用 SkillData.swift）
//   → 常规／深夜开关（slotRules.modes）
//   → 局内武器词条栏（weaponAffixes，数量步进，常规 6 条／深夜 12 条，深夜专属正面词条 ≤ 6）
//   → 遗物栏（3 或 6 张卡：官方固定词条遗物整件选入，或按词条检查页口径自组 ≤ 3 条）
//   → 护符栏（2 个槽位）
//   → 其它增益栏（道具／增益法术／战技自增益／武器固有／角色／永久强化／局内叠层／其它）
//   → 汇总面板（总倍率、各栏小计、槽位、生效条目与贡献、「按推荐填满」）。
//
// 口径（两端一致，数值与判定全部取数据集，不在页面里猜）：
//   ① 生效判定一律取 buffs[].appliesTo[输出类别]：战技（含战技子弹段）→ skill，魔法 → sorcery，
//      祷告 → incantation。yes 计入；no 不计入（默认隐藏，打开「显示不生效项」后虚化并显示 reason）；
//      conditional 按 appliesToDetail.requires 逐项判定：hand 取当前手、attackWeaponTypes 取当前武器
//      wepType、physicalType 看构成里有没有这一物理类型、attackContexts 用「攻击情境」勾选、
//      subCategoriesAny 用 attackIndex 里所选战技／法术的命中段（全部满足 = 生效，部分满足 = 按段数折算，
//      一段都不满足 = 不生效）、imbuedWeaponOnly／attachedWeaponOnly／认不出的键交给用户确认。
//   ② activation ≠ passive 的条目要用户勾「条件成立」才计入；占槽位的栏（武器词条／遗物／护符／
//      当前武器自带）选中≠条件成立，不占槽位的栏里勾选本身就是确认。stackInput 的层数、
//      accumulatorLadder 的选档同时充当确认。
//   ③ 有效倍率沿用旧页算法：每条 buff 的各通道乘数（攻击力倍率 × 伤害倍率，物理子类型只乘对应通道，
//      attackPowerFlat 只展示不乘），按伤害构成占比加权。总倍率＝按 stacking.exclusiveKey 去重
//      （同键取有效倍率最高者；applyHighest 取 categoryPriority 数值小的）后，**逐通道连乘再按占比加权**。
//   ④ 同一 spEffectId 装了多份：默认只计一份（保守口径）；数据 stackingRules 认为 stackSelf 各份相乘、
//      其余只算一份，所以打开「stackSelf 多份相乘」后 spCategoryBehavior = stackSelf 的按份数相乘（参数推断，未实测）。
//      同一词条的不同档位（paramName 去掉「 - Potency N」后相同，见 `weaponAffixFamilyKey`）是不同 SpEffect，
//      各自独立的互斥键相乘并标「参数推断，未实测」——compatibilityId 是大组（一组里有十几种词条），不能用来分档位。
//   ⑤ 「按推荐填满」只填占槽位的三栏：先武器词条、再遗物（逐张卡：固定遗物与贪心自组取总倍率更高者，
//      自组每一步都必须通过合法性检查）、最后护符；每一步取让总倍率增幅最大的候选（同增幅取 ID 小的），
//      没有正增益就停。只看「不需要额外确认就会计入」的部分——条件型要先勾「条件成立」才会被推荐。

// MARK: - 基础枚举

public enum LoadoutMode: String, CaseIterable, Sendable, Hashable, Identifiable {
    case normal
    case deep

    public var id: String { rawValue }
    public var title: String { self == .deep ? LoadoutText.modeDeep : LoadoutText.modeNormal }
}

/// 配置页的栏目。
public enum LoadoutColumn: String, CaseIterable, Sendable, Hashable, Identifiable {
    case weaponAffix
    case relic
    case accessory
    case consumable
    case spellBuff
    case weaponSkill
    case weaponInnate
    case character
    case permanent
    case runStack
    case other

    public var id: String { rawValue }
    public var title: String { LoadoutText.columnTitle(self) }

    /// 占槽位的三栏（其余不限数量，勾选即确认）。
    public var isSlotted: Bool { self == .weaponAffix || self == .relic || self == .accessory }

    /// 「其它增益」栏里的分栏，按页面顺序。
    public static let otherColumns: [LoadoutColumn] = [
        .consumable, .spellBuff, .weaponSkill, .weaponInnate, .character, .permanent, .runStack, .other
    ]

    /// 数据集 sourceSlot → 栏目（relicAffix → 遗物栏）。
    public init(sourceSlot: String) {
        switch sourceSlot {
        case "weaponAffix": self = .weaponAffix
        case "relicAffix": self = .relic
        case "accessory": self = .accessory
        case "consumable": self = .consumable
        case "spellBuff": self = .spellBuff
        case "weaponSkill": self = .weaponSkill
        case "weaponInnate": self = .weaponInnate
        case "character": self = .character
        case "permanent": self = .permanent
        case "runStack": self = .runStack
        default: self = .other
        }
    }

    /// 反查数据集的 sourceSlot 键。
    public var sourceSlotKey: String { self == .relic ? "relicAffix" : rawValue }
}

/// appliesTo 的输出类别（本页只有这三类输出手段）。
public enum LoadoutOutputClass: String, Sendable, Hashable {
    case skill
    case sorcery
    case incantation

    public var title: String {
        switch self {
        case .skill: return "战技"
        case .sorcery: return "魔法"
        case .incantation: return "祷告"
        }
    }
}

/// 当前的输出手段（决定 appliesTo 走哪一类、conditional 怎么判）。
public struct LoadoutOutput: Sendable, Hashable {
    public var outputClass: LoadoutOutputClass
    public var skillID: Int?
    public var spellID: Int?
    public var weaponID: Int?
    /// 出手武器的 wepType（法术没有武器时为 nil）。
    public var weaponWepType: Int?
    /// 1 右手 / 2 左手。
    public var hand: Int
    /// 按 `SkillDamageChannel.rawValue` 索引的伤害占比。
    public var shares: [Double]
    /// 用户勾选的攻击情境（enums.attackContext 的键）。
    public var attackContexts: Set<String>

    public init(
        outputClass: LoadoutOutputClass, skillID: Int? = nil, spellID: Int? = nil,
        weaponID: Int? = nil, weaponWepType: Int? = nil, hand: Int = 1,
        shares: [Double], attackContexts: Set<String> = []
    ) {
        self.outputClass = outputClass
        self.skillID = skillID
        self.spellID = spellID
        self.weaponID = weaponID
        self.weaponWepType = weaponWepType
        self.hand = hand == 2 ? 2 : 1
        self.shares = shares
        self.attackContexts = attackContexts
    }

    public var hasComposition: Bool { shares.contains { $0 > 0 } }
}

// MARK: - 生效判定

public enum LoadoutRequirementState: Sendable, Hashable {
    case met
    case unmet
    /// 按段数折算（attackIndex：满足的段 / 全部段）。
    case partial(Double)
    /// 本页判不了，交给用户勾「条件成立」。
    case needsUser
}

public struct LoadoutRequirement: Sendable, Hashable, Identifiable {
    public let key: String
    public let text: String
    public let state: LoadoutRequirementState

    public var id: String { key }
}

public struct LoadoutVerdict: Sendable, Hashable {
    public enum Value: String, Sendable, Hashable {
        case yes, no, conditional, missing
    }

    /// 数据里的 appliesTo 取值（缺失时为 missing）。
    public let value: Value
    /// appliesToDetail.reason（no / conditional 时才有）。
    public let reason: String?
    public let requirements: [LoadoutRequirement]
    /// activation ≠ passive 时的说明（需满足条件 / 发动期间）。
    public let activationNote: String?
    /// 0 = 不生效；(0, 1) = 按段数折算；1 = 全部生效。
    public let fraction: Double
    /// activation ≠ passive，或有「需用户确认」的条件。
    public let needsConfirmation: Bool

    public var isApplicable: Bool { fraction > 0 }
    public var isPartial: Bool { fraction > 0 && fraction < 1 }

    /// 不生效时给用户看的原因：no 取 reason，conditional 取第一条没满足的条件。
    public var blockedReason: String? {
        guard !isApplicable else { return nil }
        if value == .missing { return LoadoutText.appliesMissing }
        if value == .no { return reason ?? LoadoutText.appliesNoFallback }
        if let unmet = requirements.first(where: { $0.state == .unmet }) { return unmet.text }
        return reason ?? LoadoutText.appliesNoFallback
    }

    /// 页面上的生效标签。
    public var label: String {
        if !isApplicable { return LoadoutText.appliesNo }
        if isPartial { return LoadoutText.appliesPartial }
        if needsConfirmation { return LoadoutText.appliesConditional }
        if value == .conditional { return LoadoutText.appliesConditionalMet }
        return LoadoutText.appliesYes
    }
}

// MARK: - 候选条目

public struct LoadoutItemInfoLine: Sendable, Hashable {
    public let text: String
    /// 这条词条有没有带增伤 buff（固定遗物里的非增伤词条只显示不计入）。
    public let counted: Bool
}

/// 某一栏里可选的一项：一条武器词条 / 一条遗物词条 / 一件固定遗物 / 一个护符 / 一条增益。
public struct LoadoutItem: Sendable, Hashable, Identifiable {
    public enum Kind: Sendable, Hashable {
        case weaponAffix(Int)   // AttachEffect id
        case relicAffix(Int)    // 词条库 effectId
        case fixedRelic(Int)    // fixedRelics 下标
        case accessory(Int)     // EquipParamAccessory id
        case buff(Int)          // spEffectId
    }

    public let kind: Kind
    public let column: LoadoutColumn
    public let title: String
    public let subtitle: String
    /// 分组标题（角色栏按角色、战技自增益按战技名）。
    public let groupTitle: String?
    public let badges: [String]
    /// 带增伤的 buff 下标（进入计算的只有这些）。
    public let buffIndices: [Int]
    /// 固定遗物的逐条词条（非增伤词条只显示）。
    public let infoLines: [LoadoutItemInfoLine]
    public let searchKey: String
    public let weaponAffix: BuffWeaponAffixInfo?
    public let relicAffix: Affix?
    public let fixedRelic: BuffFixedRelic?
    /// 当前武器自带的固有效果（自动计入）。
    public let isAutoInnate: Bool

    public var id: String {
        switch kind {
        case .weaponAffix(let value): return "wa-\(value)"
        case .relicAffix(let value): return "ra-\(value)"
        case .fixedRelic(let value): return "fr-\(value)"
        case .accessory(let value): return "ac-\(value)"
        case .buff(let value): return "bf-\(value)"
        }
    }

    public func matches(foldedQuery: String) -> Bool {
        foldedQuery.isEmpty || searchKey.contains(foldedQuery)
    }
}

// MARK: - 配置状态

public struct LoadoutRelicRow: Sendable, Hashable {
    public var affixID: Int?
    /// 深夜遗物里配给这一行的负面词条（只占位，不计增伤）。
    public var curseID: Int?

    public init(affixID: Int? = nil, curseID: Int? = nil) {
        self.affixID = affixID
        self.curseID = curseID
    }
}

public struct LoadoutRelicCard: Sendable, Hashable {
    public enum Choice: Sendable, Hashable {
        case empty
        /// fixedRelics 的下标。
        case fixed(Int)
        case custom
    }

    public var choice: Choice
    public var rows: [LoadoutRelicRow]
    /// 深夜遗物格（深夜模式的第 4–6 张卡）。
    public let isDeepSlot: Bool

    public init(isDeepSlot: Bool, choice: Choice = .empty, rows: [LoadoutRelicRow] = []) {
        self.isDeepSlot = isDeepSlot
        self.choice = choice
        var padded = Array(rows.prefix(3))
        while padded.count < 3 { padded.append(LoadoutRelicRow()) }
        self.rows = padded
    }

    public var customAffixIDs: [Int] { rows.compactMap(\.affixID) }

    /// 这张卡是否还空着（「按推荐填满」只填空卡）。
    public var isEmpty: Bool {
        switch choice {
        case .empty: return true
        case .fixed: return false
        case .custom: return rows.allSatisfy { $0.affixID == nil && $0.curseID == nil }
        }
    }

    public var fixedIndex: Int? {
        if case .fixed(let index) = choice { return index }
        return nil
    }
}

/// 用户组的一套配置（值类型，页面状态与自检共用）。
public struct BuffLoadout: Sendable, Hashable {
    public private(set) var mode: LoadoutMode
    /// AttachEffect id → 数量（占几个武器词条槽）。
    public var weaponAffixCounts: [Int: Int]
    public var relicCards: [LoadoutRelicCard]
    /// 护符（EquipParamAccessory id），最多 slotRules.accessory.slots 个。
    public var accessories: [Int]
    /// 不占槽位的栏里勾选的 spEffectId（勾选即确认条件）。
    public var selectedBuffs: Set<Int>
    /// 占槽位的栏里用户勾了「条件成立」的 spEffectId。
    public var confirmed: Set<Int>
    /// stackInput 的层数（spEffectId → 层数）。
    public var stackCounts: [Int: Int]
    /// accumulatorLadder 选的档（阶梯第 1 档 spEffectId → 档位，0 / 缺失 = 不计）。
    public var ladderTiers: [Int: Int]
    /// 用户手动去掉的「当前武器自带」固有效果。
    public var excludedInnate: Set<Int>
    /// stackSelf 的同一效果多份相乘（默认关：多份只计一份）。
    public var stackSelfCopiesMultiply: Bool

    public init(mode: LoadoutMode = .normal, rules: BuffSlotRules = .fallback) {
        self.mode = mode
        weaponAffixCounts = [:]
        relicCards = Self.cards(for: mode, rules: rules)
        accessories = []
        selectedBuffs = []
        confirmed = []
        stackCounts = [:]
        ladderTiers = [:]
        excludedInnate = []
        stackSelfCopiesMultiply = false
    }

    static func cards(for mode: LoadoutMode, rules: BuffSlotRules) -> [LoadoutRelicCard] {
        let normal = max(0, rules.relicNormal)
        let total = max(normal, rules.relicSlots(mode))
        return (0..<total).map { LoadoutRelicCard(isDeepSlot: $0 >= normal) }
    }

    /// 切换常规／深夜：遗物卡数随之增减（深夜格的内容切回常规时清掉）；
    /// 切回常规时去掉深夜专属词条与武器诅咒，并把武器词条总数裁到常规上限（按 AttachEffect id 从大到小裁）。
    /// 返回被去掉的武器词条条数。
    @discardableResult
    public mutating func setMode(
        _ newMode: LoadoutMode, rules: BuffSlotRules, weaponAffixes: [Int: BuffWeaponAffixInfo]
    ) -> Int {
        guard newMode != mode else { return 0 }
        mode = newMode
        let fresh = Self.cards(for: newMode, rules: rules)
        var cards: [LoadoutRelicCard] = []
        for (index, card) in fresh.enumerated() {
            if relicCards.indices.contains(index), relicCards[index].isDeepSlot == card.isDeepSlot {
                cards.append(relicCards[index])
            } else {
                cards.append(card)
            }
        }
        relicCards = cards
        guard newMode == .normal else { return 0 }
        var removed = 0
        for (id, count) in weaponAffixCounts {
            guard let info = weaponAffixes[id], !info.isAvailable(in: .normal) else { continue }
            removed += count
            weaponAffixCounts[id] = nil
        }
        var excess = positiveWeaponAffixTotal(weaponAffixes) - rules.weaponAffixCap(.normal)
        for id in weaponAffixCounts.keys.sorted(by: >) where excess > 0 {
            let count = weaponAffixCounts[id] ?? 0
            let cut = min(count, excess)
            weaponAffixCounts[id] = count - cut == 0 ? nil : count - cut
            excess -= cut
            removed += cut
        }
        return removed
    }

    /// 占正面词条槽的数量（诅咒另算）。
    public func positiveWeaponAffixTotal(_ weaponAffixes: [Int: BuffWeaponAffixInfo]) -> Int {
        weaponAffixCounts.reduce(0) { partial, entry in
            (weaponAffixes[entry.key]?.isCurse ?? false) ? partial : partial + max(0, entry.value)
        }
    }
}

// MARK: - 计算结果

public enum LoadoutLineStatus: Sendable, Hashable {
    case counted
    /// 同一互斥键里有更强的一份（关联值是胜出者的 spEffectId）。
    case replaced(by: Int)
    case notApplicable
    case needsConfirmation
    case noStacks
    case tierNotSelected
    /// 对当前伤害构成没有增益（×1、无加算）。
    case neutral
    /// 深夜遗物里配的诅咒：只占位，不计增伤。
    case curse
    /// 自组遗物不合法，整件不计入。
    case invalidRelic

    public var isCounted: Bool { self == .counted }
}

/// 计算后的一条 buff（同一 spEffectId 从多处获得时合并成一行，copies 记份数）。
public struct LoadoutLine: Sendable, Hashable, Identifiable {
    public let id: String
    public let buffIndex: Int
    public let spEffectId: Int
    public let displayName: String
    public let column: LoadoutColumn
    /// 这条 buff 来自哪些条目（「局内武器词条『…』×2」「遗物 1『…』」…）。
    public let sources: [String]
    public let copies: Int
    /// 实际计入的份数（1，或 stackSelf 多份相乘时的份数）。
    public let countedCopies: Int
    public let exclusiveKey: String
    public let verdict: LoadoutVerdict
    public let stacks: Int?
    /// 各通道乘数（已含层数、段数折算、份数）。
    public let channelMultiplier: [Double]
    /// 单独看这一条的有效倍率（按占比加权）。
    public let multiplier: Double
    /// 按占比加权的攻击力加算点数（只展示）。
    public let weightedFlat: Double
    public let status: LoadoutLineStatus
    public let statusText: String
    public let activation: String
}

public struct LoadoutSlotUsage: Sendable, Hashable {
    public let used: Int
    public let cap: Int

    public var isOver: Bool { used > cap }
    public var text: String { "\(used)/\(cap)" }

    public init(used: Int, cap: Int) {
        self.used = used
        self.cap = cap
    }
}

public struct LoadoutRelicCheck: Sendable, Hashable {
    public enum Status: String, Sendable, Hashable {
        case empty, valid, invalid
    }

    public let status: Status
    public let message: String
    public let issues: [CheckIssue]
    public let warnings: [CheckIssue]
    public let affixCount: Int

    public static let empty = LoadoutRelicCheck(
        status: .empty, message: LoadoutText.relicEmpty, issues: [], warnings: [], affixCount: 0
    )
}

public struct LoadoutEvaluation: Sendable {
    public let total: Double
    public let lines: [LoadoutLine]
    public let columnSubtotals: [LoadoutColumn: Double]
    public let weaponAffixUsage: LoadoutSlotUsage
    public let deepOnlyUsage: LoadoutSlotUsage
    public let curseUsage: LoadoutSlotUsage
    public let relicUsage: LoadoutSlotUsage
    public let accessoryUsage: LoadoutSlotUsage
    public let relicChecks: [LoadoutRelicCheck]
    public let warnings: [String]
    public let violations: [String]
    public let weightedFlat: Double

    public var countedLines: [LoadoutLine] {
        lines.filter { $0.status.isCounted }.sorted { lhs, rhs in
            lhs.multiplier == rhs.multiplier ? lhs.spEffectId < rhs.spEffectId : lhs.multiplier > rhs.multiplier
        }
    }

    public static let empty = LoadoutEvaluation(
        total: 1, lines: [], columnSubtotals: [:],
        weaponAffixUsage: LoadoutSlotUsage(used: 0, cap: 0), deepOnlyUsage: LoadoutSlotUsage(used: 0, cap: 0),
        curseUsage: LoadoutSlotUsage(used: 0, cap: 0), relicUsage: LoadoutSlotUsage(used: 0, cap: 0),
        accessoryUsage: LoadoutSlotUsage(used: 0, cap: 0), relicChecks: [], warnings: [], violations: [],
        weightedFlat: 0
    )
}

/// 某一栏里一项候选的评估（单独选它时的倍率）。
public struct LoadoutCandidate: Sendable, Hashable, Identifiable {
    public let item: LoadoutItem
    public let lines: [LoadoutLine]
    /// 按当前的确认／层数／选档，单独选它时的有效倍率。
    public let multiplier: Double
    /// 条件全部成立（层数取实际上限、阶梯取最高档）时的有效倍率。
    public let potential: Double
    public let isApplicable: Bool
    public let blockedReason: String?
    /// 还有条件没确认（或层数为 0、未选档）。
    public let needsConfirmation: Bool
    /// 条件全部成立时按占比加权的攻击力加算点数（只展示，不进倍率）。
    public let weightedFlat: Double
    /// 潜在倍率里有叠层条目没有「实际上限」、也还没填层数，只按 1 层算（页面要写明）。
    public let potentialAssumesOneStack: Bool

    public var id: String { item.id }

    /// 对当前构成真有增益：条件成立时倍率 > 1，或有正的攻击力加算。页面默认只列这些。
    public var isUseful: Bool { isApplicable && (potential > 1.0000001 || weightedFlat > 0) }
}

/// 「全部增益一览」的一行。
public struct LoadoutOverviewRow: Sendable, Hashable, Identifiable {
    public let buffIndex: Int
    public let spEffectId: Int
    public let displayName: String
    public let column: LoadoutColumn
    public let verdict: LoadoutVerdict
    /// 条件全部成立时单独这一条的有效倍率（累积阶梯按这一行自己的档位，叠层取实际上限、没有上限的按 1 层）。
    public let multiplier: Double
    /// 叠层条目没有实际上限，倍率只按 1 层算。
    public let assumesOneStack: Bool
    public let activation: String
    public let exclusiveKey: String
    public let searchKey: String

    public var id: Int { spEffectId }
}

// MARK: - 索引（一次建好，与输出手段无关）

public struct BuffLoadoutIndex: Sendable {
    public let ranker: BuffRankerIndex
    public var dataset: BuffDataset { ranker.dataset }
    public let slotRules: BuffSlotRules
    /// 数据集带 slotRules 且 buffs 带 appliesTo（schemaVersion ≥ 6）。否则配置页显示「数据未内置」。
    public let supportsLoadout: Bool
    /// 词条库（自组遗物用）；缺失时自组遗物不可用。
    public let catalogAffixes: [Int: Affix]
    public var hasCatalog: Bool { !catalogAffixes.isEmpty }

    let fieldByKey: [String: BuffRateField]
    public let indexByID: [Int: Int]
    /// 能进伤害计算的条目：target ∈ {self, ally}、direction ∈ {increase, mixed}、带 countsAsDamage 字段。
    public let listable: [Bool]

    public let weaponAffixItems: [LoadoutItem]
    public let weaponAffixByID: [Int: BuffWeaponAffixInfo]
    /// 全部带增伤 buff 的遗物词条（常规／深夜的可用性在查询时按 CheckMode 过滤）。
    public let relicAffixItems: [LoadoutItem]
    public let fixedRelicItems: [LoadoutItem]
    public let accessoryItems: [LoadoutItem]
    /// 不占槽位的各分栏（武器固有另走 `innateItems(forWeapon:)`）。
    public let slotlessItems: [LoadoutColumn: [LoadoutItem]]
    /// 深夜遗物可配的负面词条（词条库 isCurse，按 effectId 升序）。
    public let curseAffixes: [Affix]

    let itemsByID: [String: LoadoutItem]
    /// weaponId → 该武器自带的固有效果（buff 下标）。
    let innateByWeapon: [Int: [Int]]
    /// weaponIds 为空、只能靠行名归类的固有效果（只能手动勾选）。
    let inferredInnate: [Int]
    /// 累积阶梯（ladderID）→ 数据里真实存在、能进计算的档位（升序）。accumulatorLadder.tiers 可能比实际收录的多
    ///（例如 7037604–7037606 写着 tiers = 4，buffs[] 里却没有第 4 档 7037607），选档与「最高档」一律以这里为准。
    let ladderTierOptionsByID: [Int: [Int]]

    public init(ranker: BuffRankerIndex, catalog: [Affix] = []) {
        self.ranker = ranker
        let dataset = ranker.dataset
        slotRules = dataset.slotRules ?? .fallback
        supportsLoadout = dataset.slotRules != nil && dataset.buffs.contains { !$0.appliesTo.isEmpty }
        catalogAffixes = Dictionary(catalog.map { ($0.effectID, $0) }, uniquingKeysWith: { first, _ in first })
        fieldByKey = Dictionary(dataset.rateFields.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
        indexByID = Dictionary(
            dataset.buffs.enumerated().map { ($0.element.spEffectId, $0.offset) }, uniquingKeysWith: { first, _ in first }
        )
        listable = dataset.buffs.enumerated().map { offset, buff in
            (buff.target == "self" || buff.target == "ally")
                && (buff.direction == "increase" || buff.direction == "mixed")
                && ranker.profiles[offset].hasRankingRate
        }

        let indexByID = self.indexByID
        let listable = self.listable
        var ladderTiers: [Int: Set<Int>] = [:]
        for (offset, buff) in dataset.buffs.enumerated() where listable[offset] {
            guard let ladder = buff.accumulatorLadder else { continue }
            ladderTiers[ladder.ladderID, default: []].insert(ladder.tier)
        }
        ladderTierOptionsByID = ladderTiers.mapValues { $0.sorted() }
        func listableIndices(_ ids: [Int]) -> [Int] {
            var seen: Set<Int> = []
            return ids.compactMap { indexByID[$0] }.filter { listable[$0] && seen.insert($0).inserted }
        }

        // 局内武器词条：优先用顶层 weaponAffixes（按 AttachEffect id）。
        let weaponInfos = dataset.weaponAffixes
        weaponAffixByID = Dictionary(weaponInfos.map { ($0.attachEffectId, $0) }, uniquingKeysWith: { first, _ in first })
        weaponAffixItems = weaponInfos.sorted { $0.attachEffectId < $1.attachEffectId }.compactMap { info in
            let buffIndices = listableIndices(info.spEffectIds)
            guard !buffIndices.isEmpty else { return nil }
            var badges: [String] = []
            if let potency = info.potency { badges.append(LoadoutText.badgePotency(potency)) }
            if info.deepOnlyPositive { badges.append(LoadoutText.badgeDeepOnly) }
            if info.isBlessing { badges.append(LoadoutText.badgeBlessing) }
            if info.isFixed { badges.append(LoadoutText.badgeFixed) }
            if info.isCurse { badges.append(LoadoutText.badgeCurse) }
            let name = info.nameZh.isEmpty ? (info.nameEn.isEmpty ? "#\(info.attachEffectId)" : info.nameEn) : info.nameZh
            return LoadoutItem(
                kind: .weaponAffix(info.attachEffectId), column: .weaponAffix, title: name,
                subtitle: "",
                groupTitle: nil, badges: badges, buffIndices: buffIndices, infoLines: [],
                searchKey: "\(name) \(info.nameEn) \(info.attachEffectId)".foldedForSearch,
                weaponAffix: info, relicAffix: nil, fixedRelic: nil, isAutoInnate: false
            )
        }

        // 遗物词条：relicAffixes[].catalogEffectId → 词条库。
        var relicMap: [Int: [Int]] = [:]
        for (offset, buff) in dataset.buffs.enumerated() where listable[offset] {
            for ref in buff.relicAffixes {
                guard let effectID = ref.catalogEffectId else { continue }
                if !(relicMap[effectID]?.contains(offset) ?? false) { relicMap[effectID, default: []].append(offset) }
            }
        }
        let catalogAffixes = self.catalogAffixes
        relicAffixItems = relicMap.keys.sorted().compactMap { effectID in
            guard let affix = catalogAffixes[effectID], !affix.isCurse else { return nil }
            var badges: [String] = []
            if affix.requiresCurse { badges.append(LoadoutText.badgeRequiresCurse) }
            return LoadoutItem(
                kind: .relicAffix(effectID), column: .relic, title: affix.name,
                subtitle: affix.category, groupTitle: nil, badges: badges,
                buffIndices: relicMap[effectID] ?? [], infoLines: [],
                searchKey: affix.searchableText,
                weaponAffix: nil, relicAffix: affix, fixedRelic: nil, isAutoInnate: false
            )
        }

        // 固定遗物：整件，spEffectIds 里带增伤的计入，其余词条只显示。
        fixedRelicItems = dataset.fixedRelics.enumerated().map { offset, relic in
            let buffIndices = listableIndices(relic.spEffectIds)
            let counted = Set(buffIndices.flatMap { dataset.buffs[$0].relicAffixes.map(\.attachEffectId) })
            var lines: [LoadoutItemInfoLine] = []
            for (position, attachID) in relic.attachEffectIds.enumerated() {
                let name = relic.attachEffectNamesZh.indices.contains(position)
                    ? (relic.attachEffectNamesZh[position] ?? "词条 #\(attachID)") : "词条 #\(attachID)"
                lines.append(LoadoutItemInfoLine(text: name, counted: counted.contains(attachID)))
            }
            let name = relic.nameZh.isEmpty ? relic.nameEn : relic.nameZh
            return LoadoutItem(
                kind: .fixedRelic(offset), column: .relic, title: name,
                subtitle: LoadoutText.fixedRelicSubtitle(relicID: relic.relicID, color: relic.color),
                groupTitle: nil, badges: relic.isDeepRelic ? [LoadoutText.modeDeep] : [],
                buffIndices: buffIndices, infoLines: lines,
                searchKey: ([name, relic.nameEn, String(relic.relicID)] + lines.map(\.text))
                    .joined(separator: " ").foldedForSearch,
                weaponAffix: nil, relicAffix: nil, fixedRelic: relic, isAutoInnate: false
            )
        }

        // 护符：按护符 id 归组（同一护符的几档 / 几条效果合成一项）。
        var accessoryGroups: [Int: (name: String, indices: [Int])] = [:]
        for (offset, buff) in dataset.buffs.enumerated() where listable[offset] && buff.sourceSlot == "accessory" {
            let source = buff.sources.first { $0.kind == "accessory" && $0.sourceID != nil }
            let id = source?.sourceID ?? -buff.spEffectId
            let name = source?.nameZh ?? buff.displayName
            accessoryGroups[id, default: (name, [])].indices.append(offset)
        }
        accessoryItems = accessoryGroups.keys.sorted().map { id in
            let group = accessoryGroups[id]!
            return LoadoutItem(
                kind: .accessory(id), column: .accessory, title: group.name,
                subtitle: group.indices.count > 1 ? LoadoutText.accessoryEffectCount(group.indices.count) : "",
                groupTitle: nil, badges: [], buffIndices: group.indices, infoLines: [],
                searchKey: ([group.name, String(id)] + group.indices.map { dataset.buffs[$0].displayName })
                    .joined(separator: " ").foldedForSearch,
                weaponAffix: nil, relicAffix: nil, fixedRelic: nil, isAutoInnate: false
            )
        }

        // 不占槽位的各分栏 + 武器固有。
        var slotless: [LoadoutColumn: [LoadoutItem]] = [:]
        var innate: [Int: [Int]] = [:]
        var inferred: [Int] = []
        var ladderGroups: [Int: [Int]] = [:]
        var ladderOrder: [(Int, LoadoutColumn)] = []
        for (offset, buff) in dataset.buffs.enumerated() where listable[offset] {
            if let info = buff.weaponInnate,
               buff.sourceSlot == "weaponInnate" || buff.sourceSlots.contains("weaponInnate") {
                if info.weaponIds.isEmpty {
                    inferred.append(offset)
                } else {
                    for weaponID in info.weaponIds { innate[weaponID, default: []].append(offset) }
                }
                continue
            }
            let column = LoadoutColumn(sourceSlot: buff.sourceSlot)
            guard !column.isSlotted, column != .weaponInnate else { continue }
            if let ladder = buff.accumulatorLadder {
                // 累积阶梯的各档合成一项（选中后在行里选档），不逐档各占一行。
                if ladderGroups[ladder.ladderID] == nil { ladderOrder.append((ladder.ladderID, column)) }
                ladderGroups[ladder.ladderID, default: []].append(offset)
                continue
            }
            slotless[column, default: []].append(Self.buffItem(offset, buff: buff, column: column, dataset: dataset))
        }
        for (ladderID, column) in ladderOrder {
            let members = (ladderGroups[ladderID] ?? []).sorted {
                (dataset.buffs[$0].accumulatorLadder?.tier ?? 0) < (dataset.buffs[$1].accumulatorLadder?.tier ?? 0)
            }
            guard let first = members.first else { continue }
            let base = Self.buffItem(first, buff: dataset.buffs[first], column: column, dataset: dataset)
            let title = LoadoutText.stripTierSuffix(base.title)
            slotless[column, default: []].append(LoadoutItem(
                kind: .buff(dataset.buffs[first].spEffectId), column: column, title: title,
                subtitle: LoadoutText.ladderTierCount(members.count), groupTitle: base.groupTitle,
                badges: base.badges, buffIndices: members, infoLines: [],
                searchKey: ([base.searchKey] + members.map { dataset.buffs[$0].displayName.foldedForSearch })
                    .joined(separator: " "),
                weaponAffix: nil, relicAffix: nil, fixedRelic: nil, isAutoInnate: false
            ))
        }
        for key in slotless.keys {
            slotless[key]?.sort { lhs, rhs in
                (lhs.groupTitle ?? "", lhs.title) < (rhs.groupTitle ?? "", rhs.title)
            }
        }
        slotlessItems = slotless
        innateByWeapon = innate
        inferredInnate = inferred

        curseAffixes = catalog.filter { $0.isCurse }.sorted { $0.effectID < $1.effectID }

        var byID: [String: LoadoutItem] = [:]
        for item in weaponAffixItems + relicAffixItems + fixedRelicItems + accessoryItems { byID[item.id] = item }
        for items in slotless.values { for item in items { byID[item.id] = item } }
        itemsByID = byID
    }

    public init(data: Data, catalog: [Affix] = []) throws {
        try self.init(ranker: BuffRankerIndex(data: data), catalog: catalog)
    }

    static func buffItem(_ offset: Int, buff: BuffEntry, column: LoadoutColumn, dataset: BuffDataset) -> LoadoutItem {
        var group: String?
        var subtitle = ""
        var badges: [String] = []
        switch column {
        case .character:
            let hero = LoadoutText.heroGroup(paramName: buff.paramName)
            group = hero.hero
            subtitle = hero.kind
        case .weaponSkill:
            group = buff.sources.compactMap(\.artsNameZh).first ?? LoadoutText.groupUnknownSkill
        case .consumable:
            group = buff.sources.first { $0.kind == "goods" }?.nameZh
        case .spellBuff:
            group = buff.sources.first { $0.kind == "spell" }?.nameZh
        default:
            break
        }
        if buff.activation == "activated" { badges.append(LoadoutText.badgeActivated) }
        if buff.activation == "conditional" { badges.append(LoadoutText.badgeConditional) }
        if buff.target == "ally" { badges.append(LoadoutText.badgeAlly) }
        if buff.stackInput != nil { badges.append(LoadoutText.badgeStack) }
        if buff.accumulatorLadder != nil { badges.append(LoadoutText.badgeLadder) }
        if column == .weaponInnate, buff.weaponInnate?.inferredFromRowName == true {
            badges.append(LoadoutText.badgeInferredInnate)
        }
        let sourceNames = buff.sources.compactMap { $0.nameZh ?? $0.artsNameZh }
        return LoadoutItem(
            kind: .buff(buff.spEffectId), column: column, title: buff.displayName,
            subtitle: subtitle, groupTitle: group, badges: badges, buffIndices: [offset], infoLines: [],
            searchKey: ([buff.displayName, buff.nameZh ?? "", buff.paramName ?? "", String(buff.spEffectId), group ?? ""]
                + sourceNames).joined(separator: " ").foldedForSearch,
            weaponAffix: nil, relicAffix: nil, fixedRelic: nil, isAutoInnate: false
        )
    }

    public func item(id: String) -> LoadoutItem? { itemsByID[id] }

    public func weaponAffixItem(_ attachEffectId: Int) -> LoadoutItem? { itemsByID["wa-\(attachEffectId)"] }
    public func relicAffixItem(_ effectID: Int) -> LoadoutItem? { itemsByID["ra-\(effectID)"] }
    public func accessoryItem(_ id: Int) -> LoadoutItem? { itemsByID["ac-\(id)"] }
    public func fixedRelicItem(_ index: Int) -> LoadoutItem? { itemsByID["fr-\(index)"] }

    /// 这把武器的固有效果：自带的（自动计入）+ 只能靠行名归类的（手动勾选）。
    public func innateItems(forWeapon weaponID: Int?) -> [LoadoutItem] {
        var result: [LoadoutItem] = []
        if let weaponID {
            for offset in innateByWeapon[weaponID] ?? [] {
                result.append(innateItem(offset, auto: true))
            }
        }
        for offset in inferredInnate {
            result.append(innateItem(offset, auto: false))
        }
        return result
    }

    /// 当前武器自带、自动计入的固有效果（buff 下标）。
    public func autoInnateIndices(forWeapon weaponID: Int?) -> [Int] {
        guard let weaponID else { return [] }
        return innateByWeapon[weaponID] ?? []
    }

    /// 这条累积阶梯在数据里真实存在的档位（升序）；选档控件只列这些。
    public func ladderTierOptions(_ ladderID: Int) -> [Int] {
        ladderTierOptionsByID[ladderID] ?? []
    }

    /// 这条累积阶梯实际收录的最高档（「条件成立时」与勾选预填都取它，不取 accumulatorLadder.tiers）。
    public func ladderTopTier(_ ladderID: Int) -> Int? {
        ladderTierOptionsByID[ladderID]?.last
    }

    /// 局内武器词条的「词条本身」：paramName 去掉末尾的「 - Potency N」；没有 paramName 时退中文名。
    /// 同一个键下的不同 AttachEffect＝同一词条的不同档位。compatibilityId 是大组（401020 一组里就有
    /// 提升近战攻击力、提升战技攻击力、强化魔法……十几种词条，-1 也混着多种），不能用来分档位。
    public static func weaponAffixFamilyKey(_ info: BuffWeaponAffixInfo) -> String {
        if let param = info.paramName?.trimmingCharacters(in: .whitespaces), !param.isEmpty {
            return "param:" + param.replacingOccurrences(
                of: #"\s*-\s*Potency\s*\d+\s*$"#, with: "", options: [.regularExpression, .caseInsensitive]
            )
        }
        if !info.nameZh.isEmpty { return "zh:" + info.nameZh }
        return "id:\(info.attachEffectId)"
    }

    /// 已选的武器词条里，同一词条同时选了 ≥ 2 个档位的各组（组内按 AttachEffect id 升序，组按首个 id 升序）。
    public func selectedTierFamilies(_ loadout: BuffLoadout) -> [[Int]] {
        var families: [String: [Int]] = [:]
        for (id, count) in loadout.weaponAffixCounts where count > 0 {
            guard let info = weaponAffixByID[id] else { continue }
            families[Self.weaponAffixFamilyKey(info), default: []].append(id)
        }
        return families.values.filter { $0.count > 1 }.map { $0.sorted() }.sorted { $0[0] < $1[0] }
    }

    /// 页面上一条档位的名字：「提升近战攻击力（档位1）」；没有档位的退「#id」。
    public func weaponAffixTierLabel(_ attachEffectId: Int) -> String {
        let info = weaponAffixByID[attachEffectId]
        let title = weaponAffixItem(attachEffectId)?.title
            ?? info.map { $0.nameZh.isEmpty ? $0.nameEn : $0.nameZh } ?? "#\(attachEffectId)"
        return LoadoutText.weaponAffixTierName(title, potency: info?.potency, id: attachEffectId)
    }

    func innateItem(_ offset: Int, auto: Bool) -> LoadoutItem {
        let buff = dataset.buffs[offset]
        let base = Self.buffItem(offset, buff: buff, column: .weaponInnate, dataset: dataset)
        var badges = base.badges
        if auto { badges.insert(LoadoutText.badgeAutoInnate, at: 0) }
        return LoadoutItem(
            kind: base.kind, column: .weaponInnate, title: base.title,
            subtitle: base.subtitle, groupTitle: auto ? LoadoutText.groupAutoInnate : LoadoutText.groupInferredInnate,
            badges: badges, buffIndices: base.buffIndices, infoLines: [], searchKey: base.searchKey,
            weaponAffix: nil, relicAffix: nil, fixedRelic: nil, isAutoInnate: auto
        )
    }

    /// 遗物词条在这张卡（普通／深夜）上能不能选：沿用词条检查页的 CheckMode 口径。
    public func isRelicAffixEligible(_ affix: Affix, deepSlot: Bool) -> Bool {
        affix.isEligible(for: deepSlot ? .deepPositive : .currentNormal)
    }

    // MARK: 生效判定

    /// 按 appliesTo / appliesToDetail 判定一条 buff 对当前输出手段是否生效。
    public func verdict(forBuffAt offset: Int, output: LoadoutOutput) -> LoadoutVerdict {
        let buff = dataset.buffs[offset]
        let profile = ranker.profiles[offset]
        var activationNote: String?
        var confirmNeeded = false
        if buff.activation == "activated" {
            activationNote = LoadoutText.activationActivated
            confirmNeeded = true
        } else if buff.activation != "passive" {
            var detail = profile.conditionNotes.prefix(2).joined(separator: "；")
            if let weaponTypes = buff.scope.weaponTypes, weaponTypes.mode == "equippedCount" {
                let names = weaponTypes.namesZh.isEmpty
                    ? weaponTypes.wepTypes.map { dataset.wepTypeLabels[$0] ?? "类别 \($0)" }
                    : weaponTypes.namesZh
                detail = LoadoutText.reqEquipped(count: weaponTypes.count ?? 3, names: names.joined(separator: "／"))
            }
            activationNote = LoadoutText.activationConditional(detail)
            confirmNeeded = true
        }

        var requirements: [LoadoutRequirement] = []
        if !buff.requiresGoodsIds.isEmpty {
            requirements.append(LoadoutRequirement(
                key: "goods", text: LoadoutText.reqGoods(goodsNames(buff.requiresGoodsIds)), state: .needsUser
            ))
        }

        let cls = output.outputClass.rawValue
        guard let raw = buff.appliesTo[cls] else {
            return LoadoutVerdict(
                value: .missing, reason: nil, requirements: requirements, activationNote: activationNote,
                fraction: 0, needsConfirmation: confirmNeeded
            )
        }
        let detail = buff.appliesToDetail[cls]
        switch raw {
        case "yes":
            return LoadoutVerdict(
                value: .yes, reason: nil, requirements: requirements, activationNote: activationNote,
                fraction: 1, needsConfirmation: confirmNeeded || requirements.contains { $0.state == .needsUser }
            )
        case "no":
            return LoadoutVerdict(
                value: .no, reason: detail?.reason, requirements: requirements, activationNote: activationNote,
                fraction: 0, needsConfirmation: confirmNeeded
            )
        default:
            break
        }

        // conditional（或认不出的取值）：逐项判 requires。
        if let requires = detail?.requires {
            requirements += conditionalRequirements(requires, output: output)
        } else {
            requirements.append(LoadoutRequirement(
                key: "detail", text: LoadoutText.reqNoDetail(detail?.reason ?? ""), state: .needsUser
            ))
        }
        var fraction = 1.0
        for requirement in requirements {
            switch requirement.state {
            case .met, .needsUser: continue
            case .unmet: fraction = 0
            case .partial(let share): fraction *= share
            }
        }
        return LoadoutVerdict(
            value: .conditional,
            reason: detail?.reason, requirements: requirements, activationNote: activationNote,
            fraction: fraction,
            needsConfirmation: confirmNeeded || requirements.contains { $0.state == .needsUser }
        )
    }

    func conditionalRequirements(_ requires: BuffAppliesRequirement, output: LoadoutOutput) -> [LoadoutRequirement] {
        var result: [LoadoutRequirement] = []
        if let hand = requires.hand {
            result.append(LoadoutRequirement(
                key: "hand",
                text: LoadoutText.reqHand(hand: hand, current: output.hand),
                state: hand == output.hand ? .met : .unmet
            ))
        }
        if !requires.attackWeaponTypes.isEmpty {
            let names = requires.attackWeaponTypes.map { dataset.wepTypeLabels[$0] ?? "类别 \($0)" }
            let current = output.weaponWepType.map { dataset.wepTypeLabels[$0] ?? "类别 \($0)" }
            let met = output.weaponWepType.map { requires.attackWeaponTypes.contains($0) } ?? false
            result.append(LoadoutRequirement(
                key: "attackWeaponTypes",
                text: LoadoutText.reqWeaponTypes(names: names.joined(separator: "／"), current: current),
                state: met ? .met : .unmet
            ))
        }
        if let physical = requires.physicalType {
            let channel = SkillDamageChannel.physical(code: physical)
            let present = output.shares.indices.contains(channel.rawValue) && output.shares[channel.rawValue] > 0
            result.append(LoadoutRequirement(
                key: "physicalType",
                text: LoadoutText.reqPhysicalType(channel.titleZh, present: present),
                state: present ? .met : .unmet
            ))
        }
        if !requires.attackContexts.isEmpty {
            let labels = requires.attackContexts.map { dataset.attackContextLabel($0) }.joined(separator: "／")
            let met = requires.attackContexts.contains { output.attackContexts.contains($0) }
            result.append(LoadoutRequirement(
                key: "attackContexts", text: LoadoutText.reqContexts(labels), state: met ? .met : .unmet
            ))
        }
        if !requires.subCategoriesAny.isEmpty {
            let labels = requires.subCategoriesAny.map { code in
                dataset.subCategoryLabels[code].map { "\(code) \($0)" } ?? String(code)
            }.joined(separator: "、")
            let sets: [BuffSubCategorySet]?
            switch output.outputClass {
            case .skill: sets = output.skillID.flatMap { dataset.attackIndex.skills[$0] }
            case .sorcery, .incantation: sets = output.spellID.flatMap { dataset.attackIndex.spells[$0] }
            }
            if let sets, sets.contains(where: { $0.hits > 0 }) {
                let wanted = Set(requires.subCategoriesAny)
                let total = sets.reduce(0) { $0 + $1.hits }
                let matched = sets.filter { !wanted.isDisjoint(with: $0.subs) }.reduce(0) { $0 + $1.hits }
                let state: LoadoutRequirementState
                if matched == 0 {
                    state = .unmet
                } else if matched >= total {
                    state = .met
                } else {
                    state = .partial(Double(matched) / Double(total))
                }
                result.append(LoadoutRequirement(
                    key: "subCategoriesAny",
                    text: LoadoutText.reqSubCategories(
                        labels, matched: matched, total: total, outputTitle: output.outputClass.title
                    ),
                    state: state
                ))
            } else {
                result.append(LoadoutRequirement(
                    key: "subCategoriesAny", text: LoadoutText.reqSubCategoriesUnknown(labels), state: .needsUser
                ))
            }
        }
        if requires.imbuedWeaponOnly {
            result.append(LoadoutRequirement(key: "imbuedWeaponOnly", text: LoadoutText.reqImbued, state: .needsUser))
        }
        if requires.attachedWeaponOnly {
            result.append(LoadoutRequirement(key: "attachedWeaponOnly", text: LoadoutText.reqAttached, state: .needsUser))
        }
        for key in requires.unknownKeys {
            result.append(LoadoutRequirement(key: "unknown-\(key)", text: LoadoutText.reqUnknown(key), state: .needsUser))
        }
        return result
    }

    func goodsNames(_ ids: [Int]) -> String {
        ids.map { id in
            for buff in dataset.buffs {
                if let source = buff.sources.first(where: { $0.kind == "goods" && $0.sourceID == id }),
                   let name = source.nameZh {
                    return name
                }
            }
            return "道具 #\(id)"
        }.joined(separator: "／")
    }

    // MARK: 倍率

    /// 叠层后的各通道乘数（层数替换 appliesToRateKeys 的数值；无 stackInput 或层数无效时取原值）。
    func channelMultiplier(forBuffAt offset: Int, stacks: Int?) -> [Double] {
        let buff = dataset.buffs[offset]
        let profile = ranker.profiles[offset]
        guard let input = buff.stackInput, let stacks, let value = input.multiplier(forStacks: stacks) else {
            return profile.channelMultiplier
        }
        var rates = buff.rates
        let keys = input.appliesToRateKeys.isEmpty ? [input.multiplierKey] : input.appliesToRateKeys
        for key in keys where !key.isEmpty { rates[key] = value }
        let restricted: Set<SkillDamageChannel>? = buff.scope.atkAttribute.flatMap { code in
            (0...3).contains(code) ? [SkillDamageChannel.physical(code: code)] : nil
        }
        return BuffRankerIndex.channelMultipliers(rates: rates, fields: fieldByKey, restricted: restricted)
    }

    // MARK: 自组遗物合法性

    /// 自组遗物的合法性：普通遗物走 1.03 普通口径（CheckMode.currentNormal），深夜遗物走深夜正面口径
    /// （CheckMode.deepPositive）＋诅咒配对（需诅咒的词条必须配一条诅咒池 3000000 的负面词条）。
    /// 三条时直接调 `LegalityChecker.check`（先按规范顺序排好，因此只会是合法／不合法）；
    /// 少于三条时按同一套规则判「这几条能不能同时出现在一件遗物上」，文案与 check 逐字相同。
    public func relicCheck(_ card: LoadoutRelicCard) -> LoadoutRelicCheck {
        guard card.choice == .custom else {
            if case .fixed = card.choice {
                return LoadoutRelicCheck(
                    status: .valid, message: LoadoutText.relicFixedValid, issues: [], warnings: [], affixCount: 0
                )
            }
            return .empty
        }
        var issues: [CheckIssue] = []
        var positives: [(row: Int, affix: Affix)] = []
        var unknown: [Int] = []
        for (row, entry) in card.rows.enumerated() {
            guard let id = entry.affixID else { continue }
            if let affix = catalogAffixes[id] { positives.append((row, affix)) } else { unknown.append(id) }
        }
        var curses: [(row: Int, affix: Affix)] = []
        if card.isDeepSlot {
            for (row, entry) in card.rows.enumerated() {
                guard let id = entry.curseID else { continue }
                if let affix = catalogAffixes[id] { curses.append((row, affix)) } else { unknown.append(id) }
            }
        }
        if positives.isEmpty && curses.isEmpty && unknown.isEmpty { return .empty }
        if !unknown.isEmpty {
            issues.append(CheckIssue(
                kind: .unavailable, title: LoadoutText.relicUnknownTitle,
                detail: LoadoutText.relicUnknownDetail(unknown), effectIDs: unknown
            ))
        }

        let mode: CheckMode = card.isDeepSlot ? .deepPositive : .currentNormal
        let checker = LegalityChecker()
        let affixes = positives.map(\.affix)
        var warnings: [CheckIssue] = []
        var fullMessage: String?
        if affixes.count == 3 {
            let result = checker.check(checker.canonicalOrder(affixes), mode: mode)
            issues += result.issues
            warnings += result.warnings
            fullMessage = result.message
        } else if !affixes.isEmpty {
            issues += Self.partialIssues(affixes, mode: mode)
            if mode == .deepPositive { warnings.append(Self.deepPartialWarning(affixes)) }
        }

        if card.isDeepSlot {
            issues += curseIssues(positives: positives, curses: curses)
        }

        let count = affixes.count
        if issues.isEmpty {
            return LoadoutRelicCheck(
                status: .valid,
                message: count == 3 ? (fullMessage ?? LoadoutText.relicValid) : LoadoutText.relicPartialValid(count),
                issues: [], warnings: warnings, affixCount: count
            )
        }
        return LoadoutRelicCheck(
            status: .invalid,
            message: count == 3 ? LoadoutText.relicInvalidFull : LoadoutText.relicInvalidPartial,
            issues: issues, warnings: warnings, affixCount: count
        )
    }

    /// 少于三条时的判定：重复、互斥、能否分进当前口径的某个三槽模板（文案与 LegalityChecker 逐字相同）。
    public static func partialIssues(_ affixes: [Affix], mode: CheckMode) -> [CheckIssue] {
        var issues: [CheckIssue] = []
        for group in Dictionary(grouping: affixes, by: \.effectID).values.sorted(by: { $0[0].effectID < $1[0].effectID })
        where group.count > 1 {
            issues.append(CheckIssue(
                kind: .duplicate, title: LoadoutText.checkDuplicateTitle,
                detail: LoadoutText.checkDuplicateDetail(group[0].name), effectIDs: group.map(\.effectID)
            ))
        }
        let conflictGroups = Dictionary(grouping: affixes.filter { $0.compatibilityID != -1 }, by: \.compatibilityID)
            .values.filter { $0.count > 1 }.sorted { $0[0].compatibilityID < $1[0].compatibilityID }
        for group in conflictGroups {
            issues.append(CheckIssue(
                kind: .conflict, title: LoadoutText.checkConflictTitle,
                detail: LoadoutText.checkConflictDetail(group.map(\.name)), effectIDs: group.map(\.effectID)
            ))
        }
        if mode != .compatibilityOnly && !partialPoolAssignment(affixes, sequences: mode.slotPoolSequences) {
            let eligible = Set(mode.eligiblePoolIDs)
            let unavailable = affixes.filter { Set($0.poolIDs).isDisjoint(with: eligible) }
            let names = unavailable.isEmpty ? affixes.map(\.name) : unavailable.map(\.name)
            issues.append(CheckIssue(
                kind: .unavailable,
                title: unavailable.isEmpty ? LoadoutText.checkTemplateTitle : LoadoutText.checkPoolTitle,
                detail: names.joined(separator: "、")
                    + (unavailable.isEmpty ? LoadoutText.checkTemplateSuffix : LoadoutText.checkPoolSuffix),
                effectIDs: (unavailable.isEmpty ? affixes : unavailable).map(\.effectID)
            ))
        }
        return issues
    }

    /// k（≤ 3）条词条能否各占一个不同的槽，分进某个三槽模板。
    static func partialPoolAssignment(_ affixes: [Affix], sequences: [[Int]]) -> Bool {
        guard !affixes.isEmpty else { return true }
        return sequences.contains { pools in
            guard affixes.count <= pools.count else { return false }
            var used = Array(repeating: false, count: pools.count)
            func assign(_ index: Int) -> Bool {
                if index == affixes.count { return true }
                for slot in pools.indices where !used[slot] && affixes[index].poolIDs.contains(pools[slot]) {
                    used[slot] = true
                    if assign(index + 1) { return true }
                    used[slot] = false
                }
                return false
            }
            return assign(0)
        }
    }

    /// 深夜遗物不满三条时的预检提示（与 LegalityChecker 深夜模式的 cursePairing 提示同文）。
    static func deepPartialWarning(_ affixes: [Affix]) -> CheckIssue {
        let curseBound = affixes.filter(\.requiresCurse)
        let curseNames = curseBound.map(\.name).joined(separator: "、")
        let curseRequirement = curseBound.isEmpty
            ? "其中没有仅 A 池词条；"
            : "其中 \(curseBound.count) 条为仅 A 池词条，至少需要 \(curseBound.count) 个对应诅咒槽；"
        let detail = curseRequirement
            + "当前仅预检三条正面效果，完整深夜遗物仍需结合具体遗物 ID、实际槽池模板与负面词条验证。"
            + (curseNames.isEmpty ? "" : "仅 A 池词条：\(curseNames)")
        return CheckIssue(kind: .cursePairing, title: "深夜模式仅作预检", detail: detail, effectIDs: curseBound.map(\.effectID))
    }

    /// 深夜遗物的诅咒配对：需诅咒的行必须配一条、不需要的行不得携带、诅咒须在诅咒池，
    /// 诅咒之间不得重复、与同件词条不得同一互斥池（与存档审计 auditDeepRelic 同一口径）。
    func curseIssues(positives: [(row: Int, affix: Affix)], curses: [(row: Int, affix: Affix)]) -> [CheckIssue] {
        var issues: [CheckIssue] = []
        let curseByRow = Dictionary(curses.map { ($0.row, $0.affix) }, uniquingKeysWith: { first, _ in first })
        let positiveByRow = Dictionary(positives.map { ($0.row, $0.affix) }, uniquingKeysWith: { first, _ in first })
        for row in 0..<3 {
            let positive = positiveByRow[row]
            let curse = curseByRow[row]
            if let positive, positive.requiresCurse, curse == nil {
                issues.append(CheckIssue(
                    kind: .cursePairing, title: LoadoutText.curseMissingTitle,
                    detail: LoadoutText.curseMissingDetail(row: row + 1, name: positive.name),
                    effectIDs: [positive.effectID]
                ))
            } else if let curse, !(positive?.requiresCurse ?? false) {
                issues.append(CheckIssue(
                    kind: .cursePairing, title: LoadoutText.curseUnexpectedTitle,
                    detail: LoadoutText.curseUnexpectedDetail(row: row + 1, name: curse.name),
                    effectIDs: [curse.effectID]
                ))
            }
        }
        for (row, curse) in curses.sorted(by: { $0.row < $1.row })
        where !curse.isCurse || !curse.poolIDs.contains(Self.deepCursePoolID) {
            issues.append(CheckIssue(
                kind: .unavailable, title: LoadoutText.curseMismatchTitle,
                detail: LoadoutText.curseMismatchDetail(row: row + 1, name: curse.name), effectIDs: [curse.effectID]
            ))
        }
        for group in Dictionary(grouping: curses.map(\.affix), by: \.effectID).values
            .sorted(by: { $0[0].effectID < $1[0].effectID }) where group.count > 1 {
            issues.append(CheckIssue(
                kind: .duplicate, title: LoadoutText.checkDuplicateTitle,
                detail: LoadoutText.checkDuplicateDetail(group[0].name), effectIDs: group.map(\.effectID)
            ))
        }
        let curseIDs = Set(curses.map(\.affix.effectID))
        let combined = positives.map(\.affix) + curses.map(\.affix)
        let conflictGroups = Dictionary(grouping: combined.filter { $0.compatibilityID != -1 }, by: \.compatibilityID)
            .values
            .filter { group in group.count > 1 && group.contains { curseIDs.contains($0.effectID) } }
            .sorted { $0[0].compatibilityID < $1[0].compatibilityID }
        for group in conflictGroups {
            issues.append(CheckIssue(
                kind: .conflict, title: LoadoutText.checkConflictTitle,
                detail: LoadoutText.checkConflictDetail(group.map(\.name)), effectIDs: group.map(\.effectID)
            ))
        }
        return issues
    }

    /// 深夜遗物负面词条池（与 core.js DEEP_CURSE_POOL_ID 相同）。
    public static let deepCursePoolID = 3_000_000
}

// MARK: - 计算器（绑定一个输出手段）

public struct LoadoutEvaluator: Sendable {
    public let index: BuffLoadoutIndex
    public let output: LoadoutOutput
    /// 按 buff 下标缓存的判定（不能进计算的条目为 nil）。
    let verdicts: [LoadoutVerdict?]

    static let epsilon = 1e-9

    public init(index: BuffLoadoutIndex, output: LoadoutOutput) {
        self.index = index
        self.output = output
        verdicts = index.dataset.buffs.indices.map { offset in
            index.listable[offset] ? index.verdict(forBuffAt: offset, output: output) : nil
        }
    }

    public func verdict(forBuffAt offset: Int) -> LoadoutVerdict? {
        verdicts.indices.contains(offset) ? verdicts[offset] : nil
    }

    // MARK: 原始行

    enum RawKind {
        case normal
        case curse
        case invalidRelic
    }

    struct RawLine {
        let buffIndex: Int
        let copies: Int
        let source: String
        let column: LoadoutColumn
        let kind: RawKind
        /// 不占槽位的栏里勾选＝确认条件。
        let autoConfirmed: Bool
    }

    func rawLines(_ loadout: BuffLoadout, relicChecks: [LoadoutRelicCheck]) -> [RawLine] {
        var raws: [RawLine] = []
        for id in loadout.weaponAffixCounts.keys.sorted() {
            let count = loadout.weaponAffixCounts[id] ?? 0
            guard count > 0, let item = index.weaponAffixItem(id) else { continue }
            let source = LoadoutText.sourceWeaponAffix(item.title, count: count)
            for offset in item.buffIndices {
                raws.append(RawLine(
                    buffIndex: offset, copies: count, source: source, column: .weaponAffix, kind: .normal,
                    autoConfirmed: false
                ))
            }
        }
        for (cardIndex, card) in loadout.relicCards.enumerated() {
            switch card.choice {
            case .empty:
                continue
            case .fixed(let fixedIndex):
                guard let item = index.fixedRelicItem(fixedIndex) else { continue }
                let source = LoadoutText.sourceRelic(cardIndex + 1, item.title)
                for offset in item.buffIndices {
                    raws.append(RawLine(
                        buffIndex: offset, copies: 1, source: source, column: .relic, kind: .normal, autoConfirmed: false
                    ))
                }
            case .custom:
                let check = relicChecks.indices.contains(cardIndex) ? relicChecks[cardIndex] : index.relicCheck(card)
                let kind: RawKind = check.status == .invalid ? .invalidRelic : .normal
                for row in card.rows {
                    if let id = row.affixID, let item = index.relicAffixItem(id) {
                        let source = LoadoutText.sourceRelic(cardIndex + 1, item.title)
                        for offset in item.buffIndices {
                            raws.append(RawLine(
                                buffIndex: offset, copies: 1, source: source, column: .relic, kind: kind,
                                autoConfirmed: false
                            ))
                        }
                    }
                    if card.isDeepSlot, let curseID = row.curseID {
                        for offset in curseBuffIndices(curseID) {
                            raws.append(RawLine(
                                buffIndex: offset, copies: 1,
                                source: LoadoutText.sourceRelicCurse(cardIndex + 1),
                                column: .relic, kind: .curse, autoConfirmed: false
                            ))
                        }
                    }
                }
            }
        }
        for id in loadout.accessories {
            guard let item = index.accessoryItem(id) else { continue }
            let source = LoadoutText.sourceAccessory(item.title)
            for offset in item.buffIndices {
                raws.append(RawLine(
                    buffIndex: offset, copies: 1, source: source, column: .accessory, kind: .normal, autoConfirmed: false
                ))
            }
        }
        let autoInnate = index.autoInnateIndices(forWeapon: output.weaponID)
        let autoInnateIDs = Set(autoInnate.map { index.dataset.buffs[$0].spEffectId })
        for offset in autoInnate where !loadout.excludedInnate.contains(index.dataset.buffs[offset].spEffectId) {
            raws.append(RawLine(
                buffIndex: offset, copies: 1, source: LoadoutText.sourceAutoInnate, column: .weaponInnate,
                kind: .normal, autoConfirmed: false
            ))
        }
        for id in loadout.selectedBuffs.sorted() where !autoInnateIDs.contains(id) {
            guard let offset = index.indexByID[id], index.listable[offset] else { continue }
            let buff = index.dataset.buffs[offset]
            let column: LoadoutColumn = buff.weaponInnate != nil
                && (buff.sourceSlot == "weaponInnate" || buff.sourceSlots.contains("weaponInnate"))
                ? .weaponInnate : LoadoutColumn(sourceSlot: buff.sourceSlot)
            raws.append(RawLine(
                buffIndex: offset, copies: 1, source: column.title, column: column, kind: .normal, autoConfirmed: true
            ))
        }
        return raws
    }

    /// 诅咒词条对应的 buff（只用于显示「诅咒只占位」）。
    func curseBuffIndices(_ curseID: Int) -> [Int] {
        index.dataset.buffs.indices.filter { offset in
            index.listable[offset] && index.dataset.buffs[offset].relicAffixes.contains { $0.catalogEffectId == curseID }
        }
    }

    // MARK: 合并 → 判定 → 去重 → 连乘

    struct Draft {
        var buffIndex: Int
        var copies: Int
        var sources: [String]
        var column: LoadoutColumn
        var autoConfirmed: Bool
        var kind: RawKind
    }

    struct Work {
        var draft: Draft
        var verdict: LoadoutVerdict
        var status: LoadoutLineStatus
        var channels: [Double]
        var multiplier: Double
        var flat: Double
        var stacks: Int?
        var countedCopies: Int
    }

    struct Resolved {
        var lines: [LoadoutLine]
        var total: Double
        var subtotals: [LoadoutColumn: Double]
        var flat: Double
        /// assumeAll 时有计入的叠层条目没有实际上限、也没填层数，只按 1 层算。
        var assumedOneStack: Bool = false
    }

    /// - Parameters:
    ///   - assumeAll: true = 条件全部成立、层数取「已填层数与实际上限」较大者（都没有就按 1 层）、
    ///     阶梯取数据里实际收录的最高档（候选的「潜在倍率」）。
    ///   - ladderOverride: 累积阶梯（ladderID）强制取的档位（「全部增益一览」按每一行自己的档位算）。
    func resolve(
        _ raws: [RawLine], loadout: BuffLoadout, assumeAll: Bool, detailed: Bool, ladderOverride: [Int: Int] = [:]
    ) -> Resolved {
        var order: [Int] = []
        var drafts: [Int: Draft] = [:]
        var specials: [Draft] = []
        for raw in raws {
            switch raw.kind {
            case .curse, .invalidRelic:
                specials.append(Draft(
                    buffIndex: raw.buffIndex, copies: raw.copies, sources: [raw.source], column: raw.column,
                    autoConfirmed: false, kind: raw.kind
                ))
            case .normal:
                if var draft = drafts[raw.buffIndex] {
                    draft.copies += raw.copies
                    if !draft.sources.contains(raw.source) { draft.sources.append(raw.source) }
                    draft.autoConfirmed = draft.autoConfirmed || raw.autoConfirmed
                    drafts[raw.buffIndex] = draft
                } else {
                    order.append(raw.buffIndex)
                    drafts[raw.buffIndex] = Draft(
                        buffIndex: raw.buffIndex, copies: raw.copies, sources: [raw.source], column: raw.column,
                        autoConfirmed: raw.autoConfirmed, kind: .normal
                    )
                }
            }
        }

        let channelCount = SkillDamageChannel.allCases.count
        let shares = output.shares
        var works: [Work] = []
        works.reserveCapacity(order.count + specials.count)
        var assumedOneStack = false

        for offset in order {
            guard let draft = drafts[offset], let verdict = verdicts[offset] else { continue }
            let buff = index.dataset.buffs[offset]
            var status: LoadoutLineStatus = .counted
            var stacks: Int?
            var confirmedBySelection = false
            if !verdict.isApplicable {
                status = .notApplicable
            } else if let ladder = buff.accumulatorLadder {
                let selected: Int
                if let forced = ladderOverride[ladder.ladderID] {
                    selected = forced
                } else if assumeAll {
                    selected = index.ladderTopTier(ladder.ladderID) ?? ladder.tier
                } else {
                    selected = loadout.ladderTiers[ladder.ladderID] ?? 0
                }
                if selected != ladder.tier { status = .tierNotSelected } else { confirmedBySelection = true }
            }
            if status == .counted, let input = buff.stackInput {
                let entered = min(loadout.stackCounts[buff.spEffectId] ?? 0, input.maxAllowedStacks)
                var value = entered
                if assumeAll {
                    // 潜在倍率不低于当前：取已填层数与实际上限的较大者；两样都没有才按 1 层（并标出来）。
                    let soft = min(input.softMaxStacks ?? 1, input.maxAllowedStacks)
                    value = max(entered, soft)
                    if input.softMaxStacks == nil && entered <= 0 { assumedOneStack = true }
                }
                stacks = value
                if value <= 0 { status = .noStacks } else { confirmedBySelection = true }
            }
            if status == .counted, verdict.needsConfirmation, !confirmedBySelection,
               !(assumeAll || draft.autoConfirmed || loadout.confirmed.contains(buff.spEffectId)) {
                status = .needsConfirmation
            }
            var channels = index.channelMultiplier(forBuffAt: offset, stacks: stacks)
            if verdict.isPartial {
                channels = channels.map { 1 + verdict.fraction * ($0 - 1) }
            }
            var countedCopies = 1
            if draft.copies > 1, loadout.stackSelfCopiesMultiply, buff.stacking.spCategoryBehavior == "stackSelf" {
                countedCopies = draft.copies
                channels = channels.map { pow($0, Double(draft.copies)) }
            }
            let multiplier = BuffRankerIndex.effectiveMultiplier(channelMultiplier: channels, shares: shares, fallback: 1)
            var flat = index.ranker.weightedFlat(index.ranker.profiles[offset], shares: shares)
            if verdict.isPartial { flat *= verdict.fraction }
            if status == .counted, abs(multiplier - 1) < Self.epsilon, flat <= 0 {
                status = .neutral
            }
            works.append(Work(
                draft: draft, verdict: verdict, status: status, channels: channels,
                multiplier: multiplier, flat: flat, stacks: stacks, countedCopies: countedCopies
            ))
        }

        // 互斥键去重：同键只留一份。
        var winnerByKey: [String: Int] = [:]
        for (position, work) in works.enumerated() where work.status == .counted {
            let key = index.dataset.buffs[work.draft.buffIndex].stacking.exclusiveKey
            if let current = winnerByKey[key] {
                if Self.prefers(work, over: works[current], dataset: index.dataset) {
                    winnerByKey[key] = position
                }
            } else {
                winnerByKey[key] = position
            }
        }
        for (position, work) in works.enumerated() where work.status == .counted {
            let key = index.dataset.buffs[work.draft.buffIndex].stacking.exclusiveKey
            if let winner = winnerByKey[key], winner != position {
                works[position].status = .replaced(by: index.dataset.buffs[works[winner].draft.buffIndex].spEffectId)
            }
        }

        for special in specials {
            guard let verdict = verdicts[special.buffIndex] else { continue }
            let channels = index.ranker.profiles[special.buffIndex].channelMultiplier
            works.append(Work(
                draft: special, verdict: verdict,
                status: special.kind == .curse ? .curse : .invalidRelic,
                channels: channels,
                multiplier: BuffRankerIndex.effectiveMultiplier(channelMultiplier: channels, shares: shares, fallback: 1),
                flat: 0, stacks: nil, countedCopies: 1
            ))
        }

        var product = Array(repeating: 1.0, count: channelCount)
        var columnProducts: [LoadoutColumn: [Double]] = [:]
        var flat = 0.0
        for work in works where work.status == .counted {
            for channel in 0..<channelCount where work.channels.indices.contains(channel) {
                product[channel] *= work.channels[channel]
            }
            var column = columnProducts[work.draft.column] ?? Array(repeating: 1.0, count: channelCount)
            for channel in 0..<channelCount where work.channels.indices.contains(channel) {
                column[channel] *= work.channels[channel]
            }
            columnProducts[work.draft.column] = column
            flat += work.flat
        }
        let total = BuffRankerIndex.effectiveMultiplier(channelMultiplier: product, shares: shares, fallback: 1)
        var subtotals: [LoadoutColumn: Double] = [:]
        for (column, channels) in columnProducts {
            subtotals[column] = BuffRankerIndex.effectiveMultiplier(channelMultiplier: channels, shares: shares, fallback: 1)
        }

        var lines: [LoadoutLine] = []
        if detailed {
            let nameByID = Dictionary(
                works.map { (index.dataset.buffs[$0.draft.buffIndex].spEffectId, index.dataset.buffs[$0.draft.buffIndex].displayName) },
                uniquingKeysWith: { first, _ in first }
            )
            var seenIDs: [String: Int] = [:]
            for work in works {
                let buff = index.dataset.buffs[work.draft.buffIndex]
                var id = "\(buff.spEffectId)"
                if work.draft.kind != .normal { id += work.draft.kind == .curse ? "-curse" : "-invalid" }
                let dup = seenIDs[id, default: 0]
                seenIDs[id] = dup + 1
                if dup > 0 { id += "-\(dup)" }
                lines.append(LoadoutLine(
                    id: id, buffIndex: work.draft.buffIndex, spEffectId: buff.spEffectId,
                    displayName: buff.displayName, column: work.draft.column, sources: work.draft.sources,
                    copies: work.draft.copies, countedCopies: work.countedCopies,
                    exclusiveKey: buff.stacking.exclusiveKey, verdict: work.verdict, stacks: work.stacks,
                    channelMultiplier: work.channels, multiplier: work.multiplier, weightedFlat: work.flat,
                    status: work.status,
                    statusText: Self.statusText(work.status, verdict: work.verdict, copies: work.draft.copies,
                                                countedCopies: work.countedCopies, names: nameByID,
                                                behavior: buff.stacking.spCategoryBehavior),
                    activation: buff.activation
                ))
            }
        }
        return Resolved(lines: lines, total: total, subtotals: subtotals, flat: flat, assumedOneStack: assumedOneStack)
    }

    /// 同一互斥键里谁留下：两边都是 applyHighest 时取 categoryPriority 数值小的，其余取有效倍率高的
    ///（再比加算点数，最后取 spEffectId 小的）。
    static func prefers(_ candidate: Work, over current: Work, dataset: BuffDataset) -> Bool {
        let lhs = dataset.buffs[candidate.draft.buffIndex].stacking
        let rhs = dataset.buffs[current.draft.buffIndex].stacking
        if lhs.spCategoryBehavior == "applyHighest", rhs.spCategoryBehavior == "applyHighest",
           lhs.categoryPriority != rhs.categoryPriority {
            return lhs.categoryPriority < rhs.categoryPriority
        }
        if abs(candidate.multiplier - current.multiplier) > epsilon { return candidate.multiplier > current.multiplier }
        if abs(candidate.flat - current.flat) > epsilon { return candidate.flat > current.flat }
        return dataset.buffs[candidate.draft.buffIndex].spEffectId < dataset.buffs[current.draft.buffIndex].spEffectId
    }

    static func statusText(
        _ status: LoadoutLineStatus, verdict: LoadoutVerdict, copies: Int, countedCopies: Int, names: [Int: String],
        behavior: String
    ) -> String {
        switch status {
        case .counted:
            if copies > 1 {
                if countedCopies > 1 { return LoadoutText.statusCopiesMultiply(countedCopies) }
                return behavior == "stackSelf"
                    ? LoadoutText.statusDuplicateStackSelf(copies)
                    : LoadoutText.statusDuplicateSingle(copies)
            }
            return verdict.isPartial ? LoadoutText.statusCountedPartial(verdict.fraction) : LoadoutText.statusCounted
        case .replaced(let winner):
            return LoadoutText.statusReplaced(names[winner] ?? "#\(winner)")
        case .notApplicable:
            return verdict.blockedReason ?? LoadoutText.appliesNo
        case .needsConfirmation:
            return LoadoutText.statusNeedsConfirmation
        case .noStacks:
            return LoadoutText.statusNoStacks
        case .tierNotSelected:
            return LoadoutText.statusTierNotSelected
        case .neutral:
            return LoadoutText.statusNeutral
        case .curse:
            return LoadoutText.statusCurse
        case .invalidRelic:
            return LoadoutText.statusInvalidRelic
        }
    }

    // MARK: 整套配置

    public func evaluate(_ loadout: BuffLoadout) -> LoadoutEvaluation {
        let relicChecks = loadout.relicCards.map { index.relicCheck($0) }
        let raws = rawLines(loadout, relicChecks: relicChecks)
        let resolved = resolve(raws, loadout: loadout, assumeAll: false, detailed: true)
        let rules = index.slotRules
        let mode = loadout.mode

        var positive = 0
        var deepOnly = 0
        var curses = 0
        for (id, count) in loadout.weaponAffixCounts where count > 0 {
            guard let info = index.weaponAffixByID[id] else { continue }
            if info.isCurse {
                curses += count
            } else {
                positive += count
                if info.deepOnlyPositive { deepOnly += count }
            }
        }
        let weaponUsage = LoadoutSlotUsage(used: positive, cap: rules.weaponAffixCap(mode))
        let deepOnlyUsage = LoadoutSlotUsage(used: deepOnly, cap: rules.deepOnlyCap(mode))
        let curseUsage = LoadoutSlotUsage(used: curses, cap: rules.curseCap(mode))
        let relicUsage = LoadoutSlotUsage(
            used: loadout.relicCards.filter { !$0.isEmpty }.count, cap: rules.relicSlots(mode)
        )
        let accessoryUsage = LoadoutSlotUsage(used: loadout.accessories.count, cap: rules.accessorySlots)

        var violations: [String] = []
        if weaponUsage.isOver {
            violations.append(LoadoutText.violationWeaponAffix(used: positive, cap: weaponUsage.cap, mode: mode))
        }
        if deepOnlyUsage.isOver {
            violations.append(mode == .normal
                ? LoadoutText.violationDeepOnlyInNormal(deepOnly)
                : LoadoutText.violationDeepOnly(used: deepOnly, cap: deepOnlyUsage.cap))
        }
        if curseUsage.isOver {
            violations.append(LoadoutText.violationCurse(used: curses, cap: curseUsage.cap))
        }
        if accessoryUsage.isOver {
            violations.append(LoadoutText.violationAccessory(used: accessoryUsage.used, cap: accessoryUsage.cap))
        }
        if Set(loadout.accessories).count != loadout.accessories.count {
            violations.append(LoadoutText.violationAccessoryDuplicate)
        }
        for (cardIndex, check) in relicChecks.enumerated() where check.status == .invalid {
            violations.append(LoadoutText.violationRelic(cardIndex + 1, check.message))
        }

        var warnings: [String] = []
        if !output.hasComposition { warnings.append(LoadoutText.warnNoComposition) }
        let duplicates = resolved.lines.filter { $0.copies > 1 && $0.countedCopies == 1 && $0.status.isCounted }
        let stackSelfDuplicates = duplicates.filter {
            index.dataset.buffs[$0.buffIndex].stacking.spCategoryBehavior == "stackSelf"
        }
        let singleDuplicates = duplicates.filter {
            index.dataset.buffs[$0.buffIndex].stacking.spCategoryBehavior != "stackSelf"
        }
        if !stackSelfDuplicates.isEmpty {
            warnings.append(LoadoutText.warnDuplicateStackSelf(stackSelfDuplicates.map(\.displayName)))
        }
        if !singleDuplicates.isEmpty {
            warnings.append(LoadoutText.warnDuplicateSingle(singleDuplicates.map(\.displayName)))
        }
        let multiplied = resolved.lines.filter { $0.countedCopies > 1 && $0.status.isCounted }
        if !multiplied.isEmpty {
            warnings.append(LoadoutText.warnCopiesMultiplied(multiplied.map(\.displayName)))
        }
        // 同一词条的不同档位（paramName 去掉「 - Potency N」后相同、AttachEffect id 不同）：按各自独立键相乘。
        let tierNames = index.selectedTierFamilies(loadout).flatMap { ids in ids.map { index.weaponAffixTierLabel($0) } }
        if !tierNames.isEmpty { warnings.append(LoadoutText.warnTiersIndependent(tierNames)) }
        let ladders = resolved.lines.filter { line in
            line.status.isCounted && (index.dataset.buffs[line.buffIndex].stackInput?.isLadder ?? false)
        }
        if Set(ladders.map(\.exclusiveKey)).count > 1 {
            warnings.append(LoadoutText.warnLaddersIndependent(ladders.map(\.displayName)))
        }
        for line in resolved.lines where line.status.isCounted {
            guard let input = index.dataset.buffs[line.buffIndex].stackInput,
                  let stacks = line.stacks, let soft = input.practicalMaxStacks, stacks > soft else { continue }
            warnings.append(LoadoutText.warnStackOverPractical(line.displayName, stacks: stacks, max: soft))
        }
        let fixedUsed = loadout.relicCards.compactMap(\.fixedIndex)
        let fixedDup = Dictionary(grouping: fixedUsed, by: { $0 }).filter { $0.value.count > 1 }.keys.sorted()
        for fixedIndex in fixedDup {
            if let item = index.fixedRelicItem(fixedIndex) {
                warnings.append(LoadoutText.warnFixedRelicDuplicate(item.title))
            }
        }
        if resolved.flat > 0 { warnings.append(LoadoutText.warnFlat(resolved.flat)) }

        return LoadoutEvaluation(
            total: resolved.total, lines: resolved.lines, columnSubtotals: resolved.subtotals,
            weaponAffixUsage: weaponUsage, deepOnlyUsage: deepOnlyUsage, curseUsage: curseUsage,
            relicUsage: relicUsage, accessoryUsage: accessoryUsage, relicChecks: relicChecks,
            warnings: warnings, violations: violations, weightedFlat: resolved.flat
        )
    }

    /// 只算总倍率（「按推荐填满」的内层循环用，不拼文案）。
    public func total(of loadout: BuffLoadout) -> Double {
        let checks = loadout.relicCards.map { index.relicCheck($0) }
        return resolve(rawLines(loadout, relicChecks: checks), loadout: loadout, assumeAll: false, detailed: false).total
    }

    // MARK: 候选

    /// 某一栏的候选（单独选它时的倍率），按「当前倍率 → 潜在倍率 → 名称」降序；不生效的排在最后。
    ///
    /// - Parameters:
    ///   - weaponTypeFilter: 武器词条栏的武器类别过滤（nil = 全部）。
    ///   - relicDeep: 遗物栏：true = 深夜遗物格的候选（深夜正面口径），false = 普通遗物格。
    public func candidates(
        for column: LoadoutColumn, loadout: BuffLoadout, weaponTypeFilter: Int? = nil, relicDeep: Bool = false
    ) -> [LoadoutCandidate] {
        let items: [LoadoutItem]
        switch column {
        case .weaponAffix:
            items = index.weaponAffixItems.filter { item in
                guard let info = item.weaponAffix else { return false }
                // 已选的词条一律列出（在「全部」下选的别的类别、或换了武器之后），否则在这一栏里减不掉。
                if (loadout.weaponAffixCounts[info.attachEffectId] ?? 0) > 0 { return true }
                guard info.isAvailable(in: loadout.mode) else { return false }
                guard let filter = weaponTypeFilter else { return true }
                return info.weaponTypes(in: loadout.mode).contains(filter)
            }
        case .relic:
            items = index.relicAffixItems.filter { item in
                guard let affix = item.relicAffix else { return false }
                return index.isRelicAffixEligible(affix, deepSlot: relicDeep)
            }
        case .accessory:
            items = index.accessoryItems
        case .weaponInnate:
            items = index.innateItems(forWeapon: output.weaponID)
        default:
            items = index.slotlessItems[column] ?? []
        }
        return rank(items.map { candidate(for: $0, loadout: loadout) })
    }

    /// 固定遗物候选（普通遗物格只列普通固定遗物，深夜格只列深夜固定遗物）。
    public func fixedRelicCandidates(loadout: BuffLoadout, deepSlot: Bool) -> [LoadoutCandidate] {
        rank(index.fixedRelicItems
            .filter { ($0.fixedRelic?.isDeepRelic ?? false) == deepSlot }
            .map { candidate(for: $0, loadout: loadout) })
    }

    func rank(_ candidates: [LoadoutCandidate]) -> [LoadoutCandidate] {
        candidates.sorted { lhs, rhs in
            if lhs.isApplicable != rhs.isApplicable { return lhs.isApplicable }
            if abs(lhs.multiplier - rhs.multiplier) > Self.epsilon { return lhs.multiplier > rhs.multiplier }
            if abs(lhs.potential - rhs.potential) > Self.epsilon { return lhs.potential > rhs.potential }
            return lhs.item.id < rhs.item.id
        }
    }

    public func candidate(for item: LoadoutItem, loadout: BuffLoadout) -> LoadoutCandidate {
        let autoConfirmed = !item.column.isSlotted && !item.isAutoInnate
        let raws = item.buffIndices.map { offset in
            RawLine(
                buffIndex: offset, copies: 1, source: item.title, column: item.column, kind: .normal,
                autoConfirmed: autoConfirmed
            )
        }
        let current = resolve(raws, loadout: loadout, assumeAll: false, detailed: true)
        let potential = resolve(raws, loadout: loadout, assumeAll: true, detailed: false)
        let applicable = current.lines.contains { $0.verdict.isApplicable }
        let blocked = applicable ? nil : current.lines.first?.verdict.blockedReason
        let needs = current.lines.contains { line in
            switch line.status {
            case .needsConfirmation, .noStacks, .tierNotSelected: return true
            default: return false
            }
        }
        return LoadoutCandidate(
            item: item, lines: current.lines, multiplier: current.total, potential: potential.total,
            isApplicable: applicable, blockedReason: blocked, needsConfirmation: needs,
            weightedFlat: potential.flat,
            potentialAssumesOneStack: potential.assumedOneStack && abs(potential.total - current.total) > Self.epsilon
        )
    }

    // MARK: 全部增益一览

    public func overview() -> [LoadoutOverviewRow] {
        let empty = BuffLoadout(mode: .normal, rules: index.slotRules)
        var rows: [LoadoutOverviewRow] = []
        for offset in index.dataset.buffs.indices where index.listable[offset] {
            guard let verdict = verdicts[offset] else { continue }
            let buff = index.dataset.buffs[offset]
            let raw = RawLine(
                buffIndex: offset, copies: 1, source: "", column: .other, kind: .normal, autoConfirmed: true
            )
            // 累积阶梯：每一档按它自己的档位算（否则只有最高档有倍率，其余档全是 ×1）。
            let override = buff.accumulatorLadder.map { [$0.ladderID: $0.tier] } ?? [:]
            let resolved = resolve([raw], loadout: empty, assumeAll: true, detailed: false, ladderOverride: override)
            let column: LoadoutColumn = buff.weaponInnate != nil && buff.sourceSlots.contains("weaponInnate")
                ? .weaponInnate : LoadoutColumn(sourceSlot: buff.sourceSlot)
            rows.append(LoadoutOverviewRow(
                buffIndex: offset, spEffectId: buff.spEffectId, displayName: buff.displayName, column: column,
                verdict: verdict, multiplier: verdict.isApplicable ? resolved.total : 1,
                assumesOneStack: verdict.isApplicable && resolved.assumedOneStack,
                activation: buff.activation, exclusiveKey: buff.stacking.exclusiveKey,
                searchKey: ranker.searchKey(at: offset)
            ))
        }
        return rows.sorted { lhs, rhs in
            if lhs.verdict.isApplicable != rhs.verdict.isApplicable { return lhs.verdict.isApplicable }
            if abs(lhs.multiplier - rhs.multiplier) > Self.epsilon { return lhs.multiplier > rhs.multiplier }
            return lhs.spEffectId < rhs.spEffectId
        }
    }

    var ranker: BuffRankerIndex { index.ranker }

    // MARK: 按推荐填满

    /// 各栏按有效倍率贪心填满**未用**的槽位（已选的一律保留）：
    ///   ① 局内武器词条：每一步取让总倍率增幅最大的一条（受总数、深夜专属数上限约束，不推荐诅咒）；
    ///   ② 遗物：逐张空卡，比较「最好的一件固定遗物」与「贪心自组（每一步都必须通过合法性检查，
    ///      深夜需诅咒的词条自动配一条合法的诅咒）」，取总倍率更高者（相同取固定遗物）；
    ///   ③ 护符：不重复，取增幅最大的。
    /// 增幅 ≤ 1e-9 就停；同增幅取 ID 小的（遍历顺序即 ID 升序）。
    public func recommendedFill(_ loadout: BuffLoadout, weaponTypeFilter: Int?) -> BuffLoadout {
        var current = loadout
        var best = total(of: current)
        let rules = index.slotRules
        let mode = current.mode

        // ① 武器词条
        let weaponPool = index.weaponAffixItems.filter { item in
            guard let info = item.weaponAffix, info.isAvailable(in: mode), !info.isCurse else { return false }
            guard let filter = weaponTypeFilter else { return true }
            return info.weaponTypes(in: mode).contains(filter)
        }
        while true {
            let used = current.positiveWeaponAffixTotal(index.weaponAffixByID)
            guard used < rules.weaponAffixCap(mode) else { break }
            let deepOnlyUsed = current.weaponAffixCounts.reduce(0) { partial, entry in
                (index.weaponAffixByID[entry.key]?.deepOnlyPositive ?? false) ? partial + entry.value : partial
            }
            var choice: (id: Int, total: Double)?
            for item in weaponPool {
                guard let info = item.weaponAffix else { continue }
                if info.deepOnlyPositive && deepOnlyUsed >= rules.deepOnlyCap(mode) { continue }
                var trial = current
                trial.weaponAffixCounts[info.attachEffectId, default: 0] += 1
                let value = total(of: trial)
                if value > (choice?.total ?? best) + Self.epsilon { choice = (info.attachEffectId, value) }
            }
            guard let choice else { break }
            current.weaponAffixCounts[choice.id, default: 0] += 1
            best = choice.total
        }

        // ② 遗物
        for cardIndex in current.relicCards.indices where current.relicCards[cardIndex].isEmpty {
            let deepSlot = current.relicCards[cardIndex].isDeepSlot
            var cardBest: (card: LoadoutRelicCard, total: Double)?
            let usedFixed = Set(current.relicCards.compactMap(\.fixedIndex))
            for item in index.fixedRelicItems {
                guard case .fixedRelic(let fixedIndex) = item.kind, !usedFixed.contains(fixedIndex),
                      (item.fixedRelic?.isDeepRelic ?? false) == deepSlot else { continue }
                var trial = current
                trial.relicCards[cardIndex] = LoadoutRelicCard(isDeepSlot: deepSlot, choice: .fixed(fixedIndex))
                let value = total(of: trial)
                if value > (cardBest?.total ?? best) + Self.epsilon {
                    cardBest = (trial.relicCards[cardIndex], value)
                }
            }
            if index.hasCatalog {
                var custom = LoadoutRelicCard(isDeepSlot: deepSlot, choice: .custom)
                var customTotal = best
                let pool = index.relicAffixItems.filter { item in
                    guard let affix = item.relicAffix else { return false }
                    return index.isRelicAffixEligible(affix, deepSlot: deepSlot)
                }
                for row in 0..<3 {
                    var step: (card: LoadoutRelicCard, total: Double)?
                    for item in pool {
                        guard let affix = item.relicAffix, !custom.customAffixIDs.contains(affix.effectID) else { continue }
                        var trialCard = custom
                        trialCard.rows[row].affixID = affix.effectID
                        if deepSlot && affix.requiresCurse {
                            guard let curse = pickCurse(for: trialCard, row: row) else { continue }
                            trialCard.rows[row].curseID = curse
                        }
                        guard index.relicCheck(trialCard).status == .valid else { continue }
                        var trial = current
                        trial.relicCards[cardIndex] = trialCard
                        let value = total(of: trial)
                        if value > (step?.total ?? customTotal) + Self.epsilon { step = (trialCard, value) }
                    }
                    guard let step else { break }
                    custom = step.card
                    customTotal = step.total
                }
                if customTotal > (cardBest?.total ?? best) + Self.epsilon {
                    cardBest = (custom, customTotal)
                }
            }
            if let cardBest {
                current.relicCards[cardIndex] = cardBest.card
                best = cardBest.total
            }
        }

        // ③ 护符
        while current.accessories.count < rules.accessorySlots {
            var choice: (id: Int, total: Double)?
            for item in index.accessoryItems {
                guard case .accessory(let id) = item.kind, !current.accessories.contains(id) else { continue }
                var trial = current
                trial.accessories.append(id)
                let value = total(of: trial)
                if value > (choice?.total ?? best) + Self.epsilon { choice = (id, value) }
            }
            guard let choice else { break }
            current.accessories.append(choice.id)
            best = choice.total
        }
        return current
    }

    /// 给深夜遗物的这一行挑一条能让整件遗物合法的诅咒（按 effectId 升序取第一条）。
    public func pickCurse(for card: LoadoutRelicCard, row: Int) -> Int? {
        for curse in index.curseAffixes where curse.poolIDs.contains(BuffLoadoutIndex.deepCursePoolID) {
            var trial = card
            trial.rows[row].curseID = curse.effectID
            let issues = index.relicCheck(trial).issues
            let curseTroubles = issues.contains { issue in
                issue.effectIDs.contains(curse.effectID)
            }
            if !curseTroubles { return curse.effectID }
        }
        return nil
    }

    /// 当前输出手段下出现在 requires.attackContexts 里的情境（「攻击情境」勾选项），按固定顺序。
    public func attackContextOptions() -> [BuffAttackContextOption] {
        var counts: [String: Int] = [:]
        let cls = output.outputClass.rawValue
        for offset in index.dataset.buffs.indices where index.listable[offset] {
            let buff = index.dataset.buffs[offset]
            guard buff.appliesTo[cls] == "conditional",
                  let contexts = buff.appliesToDetail[cls]?.requires?.attackContexts else { continue }
            for context in contexts { counts[context, default: 0] += 1 }
        }
        return counts
            .map { BuffAttackContextOption(key: $0.key, zh: index.dataset.attackContextLabel($0.key), count: $0.value) }
            .sorted { lhs, rhs in
                let left = BuffRankerIndex.attackContextOrder.firstIndex(of: lhs.key) ?? BuffRankerIndex.attackContextOrder.count
                let right = BuffRankerIndex.attackContextOrder.firstIndex(of: rhs.key) ?? BuffRankerIndex.attackContextOrder.count
                return left == right ? lhs.key < rhs.key : left < right
            }
    }
}

// MARK: - 文案常量表（两端对照：Windows 端 ranker.js 的配置页文案应与这里逐条对应）

public enum LoadoutText {
    // MARK: 模式 / 栏目 / 生效标签

    public static let modeNormal = "常规"
    public static let modeDeep = "深夜"

    public static func columnTitle(_ column: LoadoutColumn) -> String {
        switch column {
        case .weaponAffix: return "局内武器词条"
        case .relic: return "遗物"
        case .accessory: return "护符"
        case .consumable: return "道具"
        case .spellBuff: return "增益法术"
        case .weaponSkill: return "战技自增益"
        case .weaponInnate: return "武器固有"
        case .character: return "角色"
        case .permanent: return "永久强化"
        case .runStack: return "局内叠层"
        case .other: return "其它"
        }
    }

    public static let appliesYes = "生效"
    public static let appliesPartial = "部分段生效"
    public static let appliesConditional = "条件生效"
    public static let appliesConditionalMet = "生效（条件已满足）"
    public static let appliesNo = "不生效"
    public static let appliesNoFallback = "数据判定对这类输出不生效"
    public static let appliesMissing = "数据未给出生效范围（appliesTo，需增益数据 schemaVersion 6）"

    public static func handName(_ hand: Int) -> String { hand == 2 ? "左手" : "右手" }
    public static let handPickerHelp = "按增益的 appliesToDetail.requires.hand 判定当前手（只作用于另一只手的增益不计入），默认按右手计算"
    public static let spellHandNote = "施法器同样握在左右手之一：按 appliesToDetail.requires.hand 判定，只作用于另一只手的增益不计入。"

    // MARK: 徽标 / 分组

    public static func badgePotency(_ potency: Int) -> String { "档位\(potency)" }
    /// 提示里的一条档位：「提升近战攻击力（档位1）」；没有档位的写 AttachEffect id。
    public static func weaponAffixTierName(_ name: String, potency: Int?, id: Int) -> String {
        name + "（" + (potency.map(badgePotency) ?? "#\(id)") + "）"
    }
    /// 已选的武器词条不在当前武器类别（仍占槽、仍计入，列出来是为了能减掉）。
    public static let badgeOutsideWeaponType = "不在当前武器类别"
    public static let badgeDeepOnly = "深夜专属"
    public static let badgeBlessing = "武器赐福"
    public static let badgeFixed = "固定词条"
    public static let badgeCurse = "诅咒"
    public static let badgeRequiresCurse = "需诅咒"
    public static let badgeActivated = "发动期间"
    public static let badgeConditional = "需满足条件"
    public static let badgeAlly = "队友也吃"
    public static let badgeStack = "填层数"
    public static let badgeLadder = "选档"
    public static let badgeAutoInnate = "当前武器自带"
    public static let badgeInferredInnate = "行名推断"
    public static let badgeCurrentSkill = "当前战技"
    public static let badgeInferredTiers = "参数推断，未实测"

    public static let groupUnknownSkill = "未标明战技"
    public static let groupAutoInnate = "当前武器自带（自动计入）"
    public static let groupInferredInnate = "只能靠行名归类（手动勾选）"

    /// 遗物颜色（与 core.js RELIC_COLOR_LABELS 同序）。
    public static let relicColors = ["红", "蓝", "黄", "绿", "白"]

    public static func fixedRelicSubtitle(relicID: Int, color: Int) -> String {
        let colorName = relicColors.indices.contains(color) ? relicColors[color] + "色 · " : ""
        return colorName + "遗物 #\(relicID)"
    }

    public static func accessoryEffectCount(_ count: Int) -> String { "\(count) 条效果" }

    /// 角色栏分组：Paramdex 行名 `[Skill - Revenant] …` → （复仇者, 技艺）。
    public static let heroNames: [String: String] = [
        "Wylder": "追踪者", "Guardian": "守护者", "Ironeye": "铁之眼", "Duchess": "女爵", "Raider": "无赖",
        "Revenant": "复仇者", "Recluse": "隐士", "Executor": "执行者", "Scholar": "学者", "Undertaker": "送葬者"
    ]
    public static let heroKinds: [String: String] = ["Skill": "技艺", "Ultimate": "绝招", "Passive": "被动"]
    public static let heroUnknown = "未标明角色"

    public static func heroGroup(paramName: String?) -> (hero: String, kind: String) {
        guard let paramName, paramName.hasPrefix("["), let close = paramName.firstIndex(of: "]") else {
            return (heroUnknown, "")
        }
        let inside = String(paramName[paramName.index(after: paramName.startIndex)..<close])
        let parts = inside.components(separatedBy: " - ")
        let kind = parts.first.map { heroKinds[$0.trimmingCharacters(in: .whitespaces)] ?? $0 } ?? ""
        guard parts.count > 1 else { return (heroUnknown, kind) }
        let english = parts[1].trimmingCharacters(in: .whitespaces)
        return (heroNames[english] ?? english, kind)
    }

    // MARK: 条件

    public static let activationActivated = "只在技艺／绝招／战技发动期间存在"
    public static func activationConditional(_ detail: String) -> String {
        detail.isEmpty ? "需满足条件" : "需满足条件：" + detail
    }

    public static func reqHand(hand: Int, current: Int) -> String {
        "只作用于\(handName(hand))武器（当前：\(handName(current))）"
    }

    public static func reqWeaponTypes(names: String, current: String?) -> String {
        "只对用\(names)发动的攻击生效（当前出手武器：\(current ?? "无")）"
    }

    public static func reqPhysicalType(_ name: String, present: Bool) -> String {
        "只作用于\(name)伤害（当前构成\(present ? "含" : "不含")\(name)）"
    }

    public static func reqContexts(_ labels: String) -> String {
        "只在「\(labels)」时成立（在「攻击情境」里勾选）"
    }

    public static func reqSubCategories(_ labels: String, matched: Int, total: Int, outputTitle: String) -> String {
        "要求命中段带子类别 \(labels)：当前\(outputTitle)的 \(matched)/\(total) 段满足（attackIndex）"
            + (matched > 0 && matched < total ? "，按段数折算" + subCategoriesAllHitsNote : "")
    }
    /// attackIndex 只给出每个战技／法术的子类别组合与段数，没有 atkId 对应，所以折算与「分段命中」的勾选无关。
    public static let subCategoriesAllHitsNote = "（按该战技／法术的全部命中段折算，与「分段命中」的勾选无关）"

    public static func reqSubCategoriesUnknown(_ labels: String) -> String {
        "要求命中段带子类别 \(labels)：attackIndex 里没有当前输出手段，需自行确认"
    }

    public static let reqImbued = "只对被附加属性的那把武器生效（需确认当前武器就是被附加的那把）"
    public static let reqAttached = "只对带这条词条的那把武器生效（需确认）"
    public static func reqUnknown(_ key: String) -> String { "本页认不出的条件 \(key)（需自行确认）" }
    public static func reqNoDetail(_ reason: String) -> String {
        reason.isEmpty ? "条件未写明（需自行确认）" : "条件：\(reason)（需自行确认）"
    }
    public static func reqGoods(_ names: String) -> String { "需同时使用道具：\(names)" }
    public static func reqEquipped(count: Int, names: String) -> String { "装备中有 \(count) 把以上\(names)" }

    // MARK: 自组遗物（重复 / 互斥 / 出货池的文案与 LegalityChecker 逐字相同）

    public static let relicEmpty = "未选词条"
    public static let relicFixedValid = "官方固定词条遗物"
    public static let relicValid = "该三词条组合合法"
    public static func relicPartialValid(_ count: Int) -> String {
        "已选 \(count) 条，这几条可以同时出现；其余词条位可填任意不冲突的词条（不计增伤）"
    }
    public static let relicInvalidFull = "该三词条组合不合法"
    public static let relicInvalidPartial = "当前词条组合不合法"
    public static let relicUnknownTitle = "词条库里没有这条词条"
    public static func relicUnknownDetail(_ ids: [Int]) -> String {
        "以下词条 ID 不在词条库中：" + ids.map(String.init).joined(separator: "、")
    }

    public static let checkDuplicateTitle = "词条重复"
    public static func checkDuplicateDetail(_ name: String) -> String { "同一个效果不能在一件遗物上出现两次：\(name)" }
    public static let checkConflictTitle = "同一互斥池"
    public static func checkConflictDetail(_ names: [String]) -> String { names.joined(separator: "、") + " 不能同时出现" }
    public static let checkTemplateTitle = "不符合当前槽池模板"
    public static let checkPoolTitle = "不在当前出货池"
    public static let checkTemplateSuffix = " 无法分配到任一真实的三词条槽池模板"
    public static let checkPoolSuffix = " 不属于当前校验口径的非零权重出货池"

    public static let curseMissingTitle = "需诅咒的词条缺少负面词条"
    public static func curseMissingDetail(row: Int, name: String) -> String {
        "第 \(row) 行的正面词条需要配对负面词条：\(name)"
    }
    public static let curseUnexpectedTitle = "多余的负面词条"
    public static func curseUnexpectedDetail(row: Int, name: String) -> String {
        "第 \(row) 行的正面词条不需要负面词条，却携带负面词条：\(name)"
    }
    public static let curseMismatchTitle = "负面词条不在诅咒池"
    public static func curseMismatchDetail(row: Int, name: String) -> String {
        "第 \(row) 行的负面词条不在诅咒池：\(name)"
    }

    // MARK: 来源 / 状态

    public static func sourceWeaponAffix(_ name: String, count: Int) -> String {
        "局内武器词条「\(name)」" + (count > 1 ? " ×\(count)" : "")
    }
    public static func sourceRelic(_ card: Int, _ name: String) -> String { "遗物 \(card)「\(name)」" }
    public static func sourceRelicCurse(_ card: Int) -> String { "遗物 \(card) 的诅咒" }
    public static func sourceAccessory(_ name: String) -> String { "护符「\(name)」" }
    public static let sourceAutoInnate = "当前武器自带"

    public static let statusCounted = "计入"
    public static func statusCountedPartial(_ fraction: Double) -> String {
        "计入（按段数折算 \(BuffFormat.percent(fraction))）"
    }
    /// stackSelf 的同一效果多份：默认按一份计（保守口径），数据 stackingRules 认为可以相乘。
    public static func statusDuplicateStackSelf(_ copies: Int) -> String {
        "装了 \(copies) 份：默认按一份计（保守口径）；数据 stackingRules 认为 stackSelf 可多份相乘，可打开「\(stackSelfToggle)」"
    }
    /// 其余类别的同一效果多份：数据 stackingRules 规定只算一份。
    public static func statusDuplicateSingle(_ copies: Int) -> String {
        "装了 \(copies) 份：同一 spEffectId 多份只算一份（数据 stackingRules：非 stackSelf 只算一份）"
    }
    public static func statusCopiesMultiply(_ copies: Int) -> String {
        "stackSelf：\(copies) 份相乘（参数推断，未实测）"
    }
    public static func statusReplaced(_ name: String) -> String { "与「\(name)」同一互斥键，只计更强的一份" }
    public static let statusNeedsConfirmation = "条件型：勾选「条件成立」后才计入"
    public static let statusNoStacks = "层数为 0，未计入"
    public static let statusTierNotSelected = "未选这一档"
    public static let statusNeutral = "对当前伤害构成没有增益"
    public static let statusCurse = "诅咒只占位，不计增伤"
    public static let statusInvalidRelic = "自组遗物不合法，未计入"

    // MARK: 超限 / 提示

    public static func violationWeaponAffix(used: Int, cap: Int, mode: LoadoutMode) -> String {
        "局内武器词条 \(used) 条，超过\(mode.title)上限 \(cap) 条"
    }
    public static func violationDeepOnlyInNormal(_ count: Int) -> String {
        "常规模式没有深夜专属词条（当前选了 \(count) 条）"
    }
    public static func violationDeepOnly(used: Int, cap: Int) -> String {
        "深夜专属正面词条 \(used) 条，超过上限 \(cap) 条（每把武器最多 1 条）"
    }
    public static func violationCurse(used: Int, cap: Int) -> String { "武器诅咒 \(used) 条，超过上限 \(cap) 条" }
    public static func violationAccessory(used: Int, cap: Int) -> String { "护符 \(used) 个，超过上限 \(cap) 个" }
    public static let violationAccessoryDuplicate = "同一护符不能装两个"
    public static func violationRelic(_ card: Int, _ message: String) -> String { "遗物 \(card)：\(message)" }

    public static let warnNoComposition = "当前没有勾选任何带伤害的段，算不出倍率——先在「分段命中」里勾一段"
    public static func warnDuplicateStackSelf(_ names: [String]) -> String {
        "同一效果装了多份，默认按一份计（保守口径）；数据 stackingRules 认为 stackSelf 可多份相乘，"
            + "可打开「\(stackSelfToggle)」：" + names.joined(separator: "、")
    }
    public static func warnDuplicateSingle(_ names: [String]) -> String {
        "同一效果装了多份，按数据 stackingRules 只算一份（非 stackSelf）：" + names.joined(separator: "、")
    }
    public static func warnCopiesMultiplied(_ names: [String]) -> String {
        "已按 stackSelf 多份相乘（stackingRules 第 2 条，参数推断，未实测）：" + names.joined(separator: "、")
    }
    public static func warnTiersIndependent(_ names: [String]) -> String {
        "同一词条的不同档位按各自独立的互斥键相乘：" + names.joined(separator: "、") + "（参数推断，未实测）"
    }
    public static func warnLaddersIndependent(_ names: [String]) -> String {
        "不同叠层阶梯互不顶替、结果相乘：" + names.joined(separator: "、")
            + "（按 categoryPriority 推断，未实测）"
    }
    public static func warnStackOverPractical(_ name: String, stacks: Int, max: Int) -> String {
        "「\(name)」填了 \(stacks) 层，超过一局实际能叠到的 \(max) 层"
    }
    public static func warnFixedRelicDuplicate(_ name: String) -> String { "同一件固定遗物只能装备一件：\(name)" }
    public static func warnFlat(_ value: Double) -> String {
        "攻击力加算按占比加权约 +" + BuffFormat.trim(value, digits: 1) + "（点数，没有绝对攻击力折不成倍率，只展示不乘）"
    }
    public static func modeTrimmed(_ count: Int) -> String {
        "切到常规：已去掉 \(count) 条深夜专属／超出常规上限的武器词条"
    }

    // MARK: 页面文案（视图直接取用）

    public static let pageSubtitle = "选输出手段，再自己组一套配置（局内武器词条／遗物／护符／其它增益），按伤害构成算总倍率"
    public static let summaryTitle = "配置汇总"
    public static let summarySubtitle = "总倍率＝按互斥键去重后逐伤害类型连乘，再按上面的伤害构成占比加权；"
        + "攻击力倍率与伤害倍率两层都乘，物理子类型只乘对应部分，攻击力加算只展示不乘"
    public static let modeLabel = "模式"
    public static let modeHelp = "常规＝每把武器 1 条局内词条、3 个普通遗物；深夜＝每把诅咒武器 2 条正面词条（深夜专属每把最多 1 条）、"
        + "3 个普通遗物＋3 个深夜遗物"
    public static let fillButton = "按推荐填满"
    public static let fillHelp = "各栏按有效倍率贪心填满未用的槽位：先局内武器词条、再遗物（固定遗物与合法的自组取高者）、最后护符；"
        + "只推荐不需要额外确认就会计入的部分，已选的一律保留"
    public static let clearButton = "清空配置"
    public static let showInapplicable = "显示不生效项"
    public static let showInapplicableHelp = "appliesTo 判为不生效（或条件不满足）的条目默认隐藏；打开后虚化显示并写明原因"
    public static let stackSelfToggle = "stackSelf 多份相乘"
    public static let stackSelfHelp = "默认同一效果装多份按一份计（保守口径）；数据 stackingRules 第 2 条认为 stackSelf（spCategory 10）"
        + "各份相乘、其余只算一份——打开后 spCategoryBehavior = stackSelf 的按份数相乘（参数推断，未实测）"
    public static let attackContextsLabel = "攻击情境"
    public static let attackContextsNote = "只在特定攻击情境成立的条目（appliesToDetail.requires.attackContexts）在这里勾选后才计入"
    public static let totalLabel = "总倍率"
    public static func totalGain(_ total: Double) -> String { "相对当前构成 " + BuffFormat.gain(total) }
    public static let usageWeaponAffix = "武器词条"
    public static let usageDeepOnly = "深夜专属"
    public static let usageCurse = "武器诅咒"
    public static let usageRelic = "遗物"
    public static let usageAccessory = "护符"
    public static let subtotalsLabel = "各栏小计（本栏单独计算）"
    public static let countedTitle = "当前生效条目"
    public static let countedEmpty = "还没有计入任何增益。可以在下面各栏里挑选，或点「按推荐填满」。"
    public static func uncountedTitle(_ count: Int) -> String { "选了但未计入（\(count) 条）" }
    public static let contributionLabel = "贡献"

    public static let weaponAffixSubtitle = "按对当前输出的有效倍率排序；每条可设数量（占武器词条槽，常规合计 ≤ 6、深夜 ≤ 12，"
        + "深夜专属正面词条 ≤ 6）。6 把武器的词条全局生效；同一词条多份默认按一份计（见「stackSelf 多份相乘」），"
        + "同一词条的不同档位按独立键相乘（参数推断，未实测）"
    public static func weaponFilterCurrent(_ name: String) -> String { "当前武器类别（\(name)）" }
    public static let weaponFilterAll = "全部武器类别"
    public static let weaponFilterNoWeapon = "法术没有出手武器，列出全部武器类别的词条"
    public static let weaponAffixSearch = "搜索武器词条"
    public static let weaponAffixDeepOnlyBlocked = "常规模式没有深夜专属词条"

    public static let relicSubtitle = "常规 3 个普通遗物格；深夜另加 3 个深夜遗物格。每格二选一：官方固定词条遗物整件选入，"
        + "或按词条检查页的规则自组 ≤ 3 条词条（普通遗物用 1.03 普通口径，深夜遗物用深夜正面口径＋诅咒配对）"
    public static func relicCardTitle(_ index: Int, deep: Bool) -> String {
        "遗物 \(index) · " + (deep ? "深夜遗物格" : "普通遗物格")
    }
    public static let relicChoiceEmpty = "空"
    public static let relicChoiceFixed = "固定遗物"
    public static let relicChoiceCustom = "自组"
    public static let relicPickFixed = "选择固定遗物…"
    public static let relicNoDeepFixed = "数据里没有深夜固定词条遗物，深夜遗物格只能自组"
    public static func relicRowLabel(_ row: Int) -> String { "词条 \(row)" }
    public static let relicPickAffix = "选择词条…"
    public static let relicCurseLabel = "诅咒"
    public static let relicPickCurse = "选择诅咒…"
    public static let relicCurseNote = "诅咒只占位，不计增伤"
    public static let relicNonDamage = "不计增伤"
    public static let relicCatalogMissing = "词条库未内置，无法自组遗物"
    public static let relicFixedUsedElsewhere = "已装在别的遗物格"
    public static let relicSearch = "搜索词条名称、分类或 ID"
    public static let relicFixedSearch = "搜索固定遗物名称或词条"
    public static let relicCurseSearch = "搜索诅咒"

    public static let accessorySubtitle = "最多 2 个，同一护符不能装两个（护符格数来自游戏文本与用户说明，参数表没有字段）"
    public static let accessoryFull = "护符已满"

    public static let otherSubtitle = "不占槽位；勾选即表示在用（条件型勾选即视为条件成立）。武器固有：当前武器自带的自动计入，可去掉"
    public static let otherSearch = "搜索增益名称、来源或 SpEffect 行号"
    public static let innateNoWeapon = "法术没有出手武器，这里只有靠行名归类、需手动勾选的固有效果"

    public static let confirmLabel = "条件成立"
    public static let confirmHelp = "条件型：勾上表示你确认这个条件在出手时成立，才计入总倍率"
    public static let stacksLabel = "层数"
    public static func stacksHint(_ input: BuffStackInput) -> String {
        var parts: [String] = []
        if input.isLadder {
            parts.append("阶梯：第 n 层取 tierMultipliers[n-1]，参数表共 \(input.maxAllowedStacks) 层，各层互斥只取当前层")
        } else if let per = input.perStackMultiplier {
            parts.append("每份 ×" + BuffFormat.trim(per, digits: 4) + "，N 份按 ×" + BuffFormat.trim(per, digits: 4)
                + "^N 相乘（参数表无上限）")
        }
        if let practical = input.practicalMaxStacks {
            parts.append("一局实际最多 \(practical) 层，可以填更多但会提示")
        } else if let label = input.uiLabelMax {
            parts.append("游戏文本备有『＋1』到『＋\(label)』的标签")
        }
        return parts.joined(separator: "；")
    }
    public static let ladderLabel = "选档"
    public static func ladderTierCount(_ count: Int) -> String { "共 \(count) 档，选中后在行内选档" }
    /// 「连刺破露滴（第1层）」→「连刺破露滴」。
    public static func stripTierSuffix(_ name: String) -> String {
        name.replacingOccurrences(of: #"（第\d+[层档]）$"#, with: "", options: .regularExpression)
    }
    public static let ladderNone = "不计"
    public static func ladderTier(_ tier: Int, threshold: Double?) -> String {
        "第 \(tier) 档" + (threshold.map { "（累积 " + BuffFormat.trim($0, digits: 0) + "）" } ?? "")
    }
    public static let innateRemove = "不计入"
    public static let weaponAffixEmpty = "没有可用的武器词条。"
    public static let otherTitle = "其它增益"
    public static let otherEmpty = "这一栏没有可用的增益。"
    public static func potentialText(_ value: Double) -> String { "条件成立时 " + BuffFormat.multiplier(value) }
    /// 叠层条目没有实际上限、也还没填层数：潜在倍率只按 1 层算。
    public static func potentialTextOneStack(_ value: Double) -> String {
        "条件成立时（未设上限，按 1 层）" + BuffFormat.multiplier(value)
    }
    public static let overviewOneStack = "按 1 层"
    public static let overviewOneStackHelp = "叠层条目没有实际上限（practicalMaxStacks／uiLabelMax 都没有），一览只按 1 层算；在栏里填层数后按实际层数"
    public static func flatText(_ value: Double) -> String { "攻击力加算 +" + BuffFormat.trim(value, digits: 1) }
    public static let detailActivation = "发动条件"
    public static let detailStatus = "状态"
    public static let detailKey = "互斥键"
    public static let detailDesc = "说明"
    public static let relicValidLabel = "合法"
    public static let relicInvalidLabel = "不合法"
    public static let relicAffixPickerSubtitle = "按对当前输出的有效倍率排序；红字＝选上后这件遗物不合法的原因"
    public static let pickerDone = "完成"
    public static let innateRestore = "计入"

    public static let overviewTitle = "全部增益一览"
    public static let overviewSubtitle = "按当前输出手段列出全部能进伤害计算的条目（条件全部成立时的单条倍率：叠层取实际上限、没有上限的按 1 层，"
        + "累积阶梯按每一档自己算），只供查阅"
    public static let overviewSearch = "搜索增益名称 / 来源 / SpEffect 行号"
    public static let noteTitle = "说明"
    public static let noteSubtitle = "数值直接取自游戏参数表；叠加规则与部分生效范围是参数推断，未经木桩实测"
    public static func pageRulesTitle(_ count: Int) -> String { "本页口径（\(count) 条）" }
    public static let conclusionsTitle = "数据集的研究结论（中文简述）"
    public static func questionsTitle(_ count: Int) -> String { "数据集的问答（notes.userQuestions，\(count) 条）" }
    public static let loadoutMissing = "增益数据缺少配置页需要的字段（slotRules／appliesTo，需 schemaVersion 6）"

    // MARK: 本页口径（说明区）

    public static let pageRules: [String] = [
        "生效判定一律取数据的 appliesTo：战技（含战技射出的子弹段）看 skill，魔法看 sorcery，祷告看 incantation。"
            + "yes 计入；no 默认隐藏（打开「显示不生效项」后虚化并显示 appliesToDetail.reason）；"
            + "conditional 按 requires 逐项判：hand 取当前手，attackWeaponTypes 取当前武器类别，physicalType 看构成里有没有该物理类型，"
            + "attackContexts 用「攻击情境」勾选，subCategoriesAny 用 attackIndex 里所选战技／法术的命中段"
            + "（全部满足＝生效，部分满足＝按段数折算，一段都不满足＝不生效；attackIndex 没有逐段对应，折算按该战技／法术的全部命中段，"
            + "与「分段命中」的勾选无关），imbuedWeaponOnly 等判不了的交给用户勾「条件成立」。",
        "activation 不是 passive 的条目（需满足条件／发动期间）要勾「条件成立」才计入；占槽位的栏（武器词条／遗物／护符／当前武器自带）"
            + "选中不等于条件成立，不占槽位的栏里勾选本身就是确认。叠层条目填层数、累积阶梯选档同样算确认。",
        "有效倍率沿用原排名页算法：攻击力倍率（减防前）与伤害倍率（减防后）两层相乘，物理倍率作用于斩／打／突／标准全部物理通道，"
            + "物理子类型倍率只乘对应通道，再按伤害构成占比加权；攻击力加算（点数）没有绝对攻击力就折不成倍率，只展示不乘。",
        "总倍率＝全部计入条目按 stacking.exclusiveKey 去重（同键只留有效倍率最高的一份；两边都是 applyHighest 时取 categoryPriority 数值小的），"
            + "再逐伤害类型连乘、按构成占比加权；各栏小计是本栏单独这样算出来的，不一定相乘等于总倍率。",
        "同一 spEffectId 装了多份（同一武器词条数量 >1、多件遗物带同一词条）：默认只计一份（保守口径）；"
            + "数据 stackingRules 第 2 条认为 stackSelf 各份相乘、其余只算一份，打开「stackSelf 多份相乘」后 stackSelf 的按份数相乘"
            + "（参数推断，未实测）。同一词条的不同档位（paramName 去掉「 - Potency N」后相同）是不同 SpEffect、按独立键相乘，"
            + "同样标「参数推断，未实测」；compatibilityId 是大组，不用来分档位。",
        "局内武器词条只按总数计槽位：常规合计 ≤ 6，深夜正面词条合计 ≤ 12、其中深夜专属（weaponAffixDeepOnlyPositive）≤ 6，诅咒另算每把 1 条。"
            + "武器类别过滤默认取当前武器的 wepType（常规看 normalWepTypes、深夜看 deepWepTypes），只影响列表与「按推荐填满」的候选。",
        "自组遗物严格沿用词条检查页的口径：三条时直接调 LegalityChecker（普通遗物 1.03 普通池、深夜遗物深夜正面七种三槽模板），"
            + "不满三条时按同一套规则判「这几条能否同时出现」；深夜遗物需诅咒的词条必须配一条诅咒池的负面词条（诅咒只占位不计增伤）。"
            + "不合法的自组遗物整件不计入总倍率。固定遗物按数据给的 spEffectIds 计入，非增伤词条只显示；同一件固定遗物只能装一件。",
        "「按推荐填满」只填占槽位的三栏：先局内武器词条，再逐张空遗物卡（最好的固定遗物与贪心自组取总倍率更高者，相同取固定遗物），"
            + "最后护符；每一步取让总倍率增幅最大的候选（同增幅取 ID 小的），没有正增益就停。条件型要先勾「条件成立」才会被推荐。",
        "武器固有效果：当前武器（weaponInnate.weaponIds）自带的自动列入并标注，被动的直接计入，条件型仍需勾选，可手动去掉；"
            + "weaponIds 为空、只能靠行名归类的只能手动勾选。其它不占槽位的栏按 sourceSlot 分栏，角色按角色分组。",
        "列表只收 target 为自己或队友、direction 为 increase／mixed、且带 countsAsDamage 字段的条目；"
            + "enemy（挂在敌人身上）与 summon（召唤物自己的系数）不进计算。"
    ]

    // MARK: 研究结论（说明区；数字取自数据）

    public static func dataConclusions(dataset: BuffDataset) -> [String] {
        var lines: [String] = [
            "叠加规则是按 SpEffectParam 的 spCategory／categoryPriority 参数结构推断的，未经木桩实测："
                + "同一 exclusiveKey 只留一份、不同键相乘；resetOnApply（20 类）重复获得只刷新，stackSelf（10 类）同一效果可与自己叠加。",
            "本作没有独立的「战技伤害 +x%」字段：『提升战技攻击力』是普通伤害倍率加子类别 112（战技攻击），"
                + "实测 155 个有伤害段的战技里 150 个带 112（含战技射出的子弹段），法术的命中段一个都不带，所以法术吃不到它。",
            "法术吃到的『提升攻击力（……・战技）』是战技发动后给自己的全伤害增益（例如黄金树立誓、归于麾下），"
                + "名字里的『战技』是来源，不是生效范围——本页把它们放在「战技自增益」栏。",
            "『装备三把以上 X 类武器』判的是装备中有没有三把该类武器，与出手武器无关，对法术也生效（需勾「条件成立」）；"
                + "『提升 X 的攻击力』只对用 X 发动的攻击生效。",
            "throw（致命一击）对 throwAttackParamChange=0 的增益判生效是数据集的推断，与 Paramdex 的字面说明相反（详见 notes.appliesTo）。"
        ]
        let rules = dataset.slotRules ?? .fallback
        lines.append(
            "局内武器词条：常规每把 1 条、最多 \(rules.maxWeapons) 把（\(rules.maxAffixesNormal) 条）；"
                + "深夜诅咒武器每把 2 条正面词条（\(rules.maxAffixesDeep) 条）另带 1 条负面诅咒，"
                + "其中深夜专属正面词条每把最多 \(rules.deepOnlyPerWeaponMax) 条、合计最多 \(rules.maxDeepOnlyAffixes) 条（诅咒不占这个名额）。"
        )
        lines.append(
            "同一把深夜诅咒武器的两条正面词条能否是同一条（或同一词条的不同档位）："
                + (rules.duplicateWithinWeaponStatus == "unknown" ? "参数表没有答案，按未知处理" : "见 slotRules")
                + "；本页只按总数计槽位，不逐把核对。同一词条的不同档位是不同的 SpEffect、各有独立的互斥键，本页按相乘计算（参数推断，未实测）。"
        )
        lines.append(
            "遗物：常规 \(rules.relicNormal) 个普通遗物格，深夜另加 \(rules.relicDeepExtra) 个深夜遗物格；"
                + "护符最多 \(rules.accessorySlots) 个"
                + (rules.accessoryMeasured ? "。" : "（来自游戏文本与用户说明，参数表没有护符格数字段）。")
        )
        for buff in dataset.buffs {
            guard let input = buff.stackInput else { continue }
            var text = "叠层「\(buff.displayName)」："
            if input.isLadder {
                let ratio = input.perStackRatio.map { "第 n 层约 ×" + BuffFormat.trim($0, digits: 3) + "^n" } ?? "逐层取 tierMultipliers"
                text += ratio + "，参数表共 \(input.maxAllowedStacks) 层"
            } else if let per = input.perStackMultiplier {
                text += "每份 ×" + BuffFormat.trim(per, digits: 4) + "，参数表无上限"
            }
            if let practical = input.practicalMaxStacks {
                text += "，一局实际最多 \(practical) 层"
            }
            lines.append(text + "。")
        }
        lines.append(
            "同一阶梯的各层互斥只取当前层；不同阶梯（封印监牢、黑夜入侵者、玛雷家的庇佑、复仇的庇佑）互斥键各不相同，"
                + "可以同时生效、结果相乘——同样是参数推断。"
        )
        return lines
    }
}
