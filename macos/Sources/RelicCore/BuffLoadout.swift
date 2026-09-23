import Foundation

// 「增伤排名」页（配置版）：自己组一套配置，汇总成一个总倍率。
//
// 页面结构：输出手段（战技／法术 + 武器 + 分段 + 伤害构成，沿用 SkillData.swift）
//   → 常规／深夜开关（slotRules.modes）
//   → 局内武器词条栏（weaponAffixes，数量步进，常规 6 条／深夜 12 条，深夜专属正面词条 ≤ 6）
//   → 遗物栏（3 或 6 张卡：官方固定词条遗物整件选入，或按词条检查页口径自组 ≤ 3 条）
//   → 护符栏（2 个槽位）
//   → 其它增益栏（道具／增益法术／战技自增益／武器固有／角色／永久强化／局内叠层／其它）
//   → 汇总面板（总倍率、各栏小计、槽位、生效条目、「按推荐填满」）。
//
// **两端同一口径**（Windows：windows/renderer/pages/ranker.js；数据以 stackingRules / notes.ranking 为准）：
//   ① 生效判定一律取 buffs[].appliesTo[输出类别]：战技（含战技子弹段）→ skill，魔法 → sorcery，祷告 → incantation。
//      conditional 按 requires 逐项判：hand / attackWeaponTypes（法术按施法器：魔法＝手杖 57、祷告＝圣印记 61）/
//      physicalType 自动判定；subCategoriesAny 用 attackIndex（部分段命中按 1＋(倍率−1)×命中段占比近似）；
//      attackContexts 用「攻击情境」勾选；imbuedWeaponOnly / attachedWeaponOnly / requiresGoodsIds / 认不出的键要确认。
//   ② 作用对象只留 self / ally（selfAllyPair 的 Allies 那一行不算施放者自己）；direction=decrease 一律不计入。
//   ③ activation ≠ passive 与要确认的条件默认不计入：占槽位的栏（武器词条、遗物、护符、当前武器固有）选中
//      ≠ 条件成立，要勾「条件成立」；不占槽位的栏里勾选即确认；叠层填层数、累积阶梯选层同样算确认。
//   ④ 多档词条（数据 affixVariant）同一组只算选中的一档（默认第 1 档；参数里查不到武器类别 → 档位的映射）。
//   ⑤ 去重按 stacking.exclusiveKey：同键只留一份（applyHighest 按 categoryPriority 取数值小的，其余取有效倍率
//      高的，再比加算、再取 spEffectId 小的）；同一 spEffectId 多份：stackSelf 且按 ID 互斥的各份相乘，其余只算一份。
//   ⑥ 总倍率＝去重后逐伤害类型连乘，再按伤害构成占比加权；各栏小计（武器词条／遗物／护符／其它增益）同法。
//   ⑦ 按推荐填满：武器词条 → 遗物逐格（固定 vs 自组，同分取固定）→ 护符；每一步取推荐口径的总倍率增幅最大的
//      候选（同增幅取 ID 小的），不选条件型、叠层与累积阶梯。
// 文案全部取自 `LoadoutText.table`，与 Windows 端 TEXT 常量表按点号路径逐键同文（两端自检校验同一个摘要）。

// MARK: - 基础枚举

public enum LoadoutMode: String, CaseIterable, Sendable, Hashable, Identifiable {
    case normal
    case deep

    public var id: String { rawValue }
    public var title: String { LoadoutText.t("runMode." + rawValue) }
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

    /// 汇总时归到哪一栏：「其它增益」含不占槽位的各分栏与武器固有。
    public var summaryColumn: LoadoutSummaryColumn {
        switch self {
        case .weaponAffix: return .weaponAffix
        case .relic: return .relic
        case .accessory: return .accessory
        default: return .other
        }
    }

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

/// 汇总的四栏（小计按这四栏算，与 Windows 端 COLUMN_ORDER 同序）。
public enum LoadoutSummaryColumn: String, CaseIterable, Sendable, Hashable, Identifiable {
    case weaponAffix
    case relic
    case accessory
    case other

    public var id: String { rawValue }
    public var title: String { LoadoutText.t("columns." + rawValue) }
}

/// appliesTo 的输出类别（本页只有这三类输出手段）。
public enum LoadoutOutputClass: String, Sendable, Hashable {
    case skill
    case sorcery
    case incantation

    public var title: String { LoadoutText.t("outputClass." + rawValue) }

    /// 法术的「出手武器」：魔法由手杖（57）施放，祷告由圣印记（61）施放（notes.userQuestions.Q2）。
    public var casterWepType: Int? {
        switch self {
        case .skill: return nil
        case .sorcery: return 57
        case .incantation: return 61
        }
    }
}

/// 当前的输出手段（决定 appliesTo 走哪一类、conditional 怎么判）。
public struct LoadoutOutput: Sendable, Hashable {
    public var outputClass: LoadoutOutputClass
    public var skillID: Int?
    public var spellID: Int?
    public var weaponID: Int?
    /// 战技所用武器的 wepType（法术为 nil，出手武器类别按施法器取，见 `attackWepType`）。
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

    /// 出手武器类别：战技＝所选武器的 wepType；魔法＝手杖；祷告＝圣印记。
    public var attackWepType: Int? {
        outputClass == .skill ? weaponWepType : outputClass.casterWepType
    }
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

    /// yes（生效）/ no（不生效）/ context（要勾选攻击情境）/ pending（要用户确认）。
    public enum State: String, Sendable, Hashable {
        case yes, no, context, pending
    }

    /// 数据里的 appliesTo 取值（缺失时为 missing）。
    public let value: Value
    public let state: State
    /// 不生效（no / context）的原因；pending 时是 appliesToDetail.reason。
    public let reasons: [String]
    /// 要用户确认的条件（imbuedWeaponOnly、需同时使用道具、认不出的键…）。
    public let needs: [String]
    /// 部分段命中的近似说明。
    public let notes: [String]
    /// 1 = 全部生效；(0, 1) = 子类别只有部分段命中、按段数近似折算。
    public let fraction: Double
    /// requires.physicalType：倍率只落在这一个物理通道。
    public let restrictedChannel: SkillDamageChannel?
    public let requirements: [LoadoutRequirement]
    public let activation: String
    /// activation ≠ passive 时的说明（条件型 / 发动型 / 装备中有 N 把以上 X）。
    public let activationNote: String?

    public var isApplicable: Bool { state == .yes || state == .pending }
    public var isPartial: Bool { isApplicable && fraction < 1 }
    public var needsConfirmation: Bool { !needs.isEmpty || activationNote != nil }

    /// 不生效时给用户看的原因。
    public var blockedReason: String? {
        guard !isApplicable else { return nil }
        return reasons.first ?? LoadoutText.t("verdictNoFallback")
    }

    /// 生效判定的短标签（两端同一口径）：不生效 → 部分段生效 → 要确认 → 条件已满足 → 生效。
    public var label: String {
        if !isApplicable { return LoadoutText.t("verdict.no") }
        if fraction < 1 { return LoadoutText.t("verdict.partial") }
        if !needs.isEmpty || activation != "passive" { return LoadoutText.t("verdict.needsUser") }
        if value == .conditional { return LoadoutText.t("verdict.conditionalMet") }
        return LoadoutText.t("verdict.yes")
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
    /// 分组标题（角色栏按角色、战技自增益按战技名、武器固有按「当前武器自带／其它武器」）。
    public let groupTitle: String?
    public let badges: [String]
    /// 能进计算的 buff 下标（进入计算的只有这些）。
    public let buffIndices: [Int]
    /// 固定遗物的逐条词条（非增伤词条只显示）。
    public let infoLines: [LoadoutItemInfoLine]
    public let searchKey: String
    public let weaponAffix: BuffWeaponAffixInfo?
    public let relicAffix: Affix?
    public let fixedRelic: BuffFixedRelic?
    /// 当前武器自带的固有效果（自动列入，但不算用户确认）。
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

    /// 这张卡是否还空着（「按推荐填满」只填空卡）：固定遗物要选中一件，自组要至少有一条词条或诅咒。
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
    /// 护符（EquipParamAccessory id），按格位顺序，最多 slotRules.accessory.slots 个。
    public var accessories: [Int]
    /// 不占槽位的栏里勾选的 spEffectId（勾选即确认条件）。
    public var selectedBuffs: Set<Int>
    /// 用户勾了「条件成立」的 spEffectId。
    public var confirmed: Set<Int>
    /// stackInput 的层数（spEffectId → 层数；缺省 0＝不计入）。
    public var stackCounts: [Int: Int]
    /// accumulatorLadder 选的层（阶梯第 1 层 spEffectId → 第几层；缺省＝不计入）。
    public var ladderTiers: [Int: Int]
    /// 多档词条选的档（affixVariant 组键 → 选中那一档的 spEffectId；缺省＝第 1 档）。
    public var variantChoices: [String: Int]
    /// 用户手动去掉的「当前武器自带」固有效果。
    public var excludedInnate: Set<Int>

    public init(mode: LoadoutMode = .normal, rules: BuffSlotRules = .fallback) {
        self.mode = mode
        weaponAffixCounts = [:]
        relicCards = Self.cards(for: mode, rules: rules)
        accessories = []
        selectedBuffs = []
        confirmed = []
        stackCounts = [:]
        ladderTiers = [:]
        variantChoices = [:]
        excludedInnate = []
    }

    static func cards(for mode: LoadoutMode, rules: BuffSlotRules) -> [LoadoutRelicCard] {
        let normal = max(0, rules.relicNormal)
        let total = max(normal, rules.relicSlots(mode))
        return (0..<total).map { LoadoutRelicCard(isDeepSlot: $0 >= normal) }
    }

    /// 切换常规／深夜（两端同一口径）：去掉新模式下不存在的词条，深夜专属超限的按 AttachEffect id 从大到小削，
    /// 总数超限的再按 id 从大到小削；切回常规时深夜遗物格清空。返回被去掉的武器词条条数。
    @discardableResult
    public mutating func setMode(
        _ newMode: LoadoutMode, rules: BuffSlotRules, weaponAffixes: [Int: BuffWeaponAffixInfo]
    ) -> Int {
        guard newMode != mode else { return 0 }
        let before = positiveWeaponAffixTotal(weaponAffixes)
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
        for (id, count) in weaponAffixCounts {
            guard let info = weaponAffixes[id], info.isAvailable(in: newMode), count > 0 else {
                weaponAffixCounts[id] = nil
                continue
            }
        }
        func trim(onlyDeep: Bool, capacity: Int) {
            let used = weaponAffixCounts.reduce(0) { partial, entry in
                guard let info = weaponAffixes[entry.key], !info.isCurse else { return partial }
                return onlyDeep && !info.deepOnlyPositive ? partial : partial + entry.value
            }
            var excess = used - capacity
            for id in weaponAffixCounts.keys.sorted(by: >) where excess > 0 {
                guard let info = weaponAffixes[id], !info.isCurse, !onlyDeep || info.deepOnlyPositive else { continue }
                let count = weaponAffixCounts[id] ?? 0
                let cut = min(count, excess)
                weaponAffixCounts[id] = count - cut == 0 ? nil : count - cut
                excess -= cut
            }
        }
        trim(onlyDeep: true, capacity: rules.deepOnlyCap(newMode))
        trim(onlyDeep: false, capacity: rules.weaponAffixCap(newMode))
        return max(0, before - positiveWeaponAffixTotal(weaponAffixes))
    }

    /// 占正面词条槽的数量（诅咒另算）。
    public func positiveWeaponAffixTotal(_ weaponAffixes: [Int: BuffWeaponAffixInfo]) -> Int {
        weaponAffixCounts.reduce(0) { partial, entry in
            (weaponAffixes[entry.key]?.isCurse ?? false) ? partial : partial + max(0, entry.value)
        }
    }
}

// MARK: - 计算结果

/// 一条的状态（与 Windows 端 item.state 同名同义）。
public enum LoadoutLineStatus: Sendable, Hashable {
    case counted
    /// 同一互斥键里留下了另一份（关联值是留下的那一份的 spEffectId）。
    case duplicate(by: Int)
    case pending
    case context
    case no
    case zeroStacks
    case tierOff
    case variantOff
    case relicInvalid
    /// 对当前构成没有增益（×1、没有正的攻击力加算）。
    case neutral

    public var isCounted: Bool { self == .counted }

    /// Windows 端的状态键（states.<key> 的文案）。
    public var key: String {
        switch self {
        case .counted: return "counted"
        case .duplicate: return "duplicate"
        case .pending: return "pending"
        case .context: return "context"
        case .no: return "no"
        case .zeroStacks: return "zeroStacks"
        case .tierOff: return "tierOff"
        case .variantOff: return "variantOff"
        case .relicInvalid: return "relicInvalid"
        case .neutral: return "neutral"
        }
    }

    public var title: String { LoadoutText.t("states." + key) }
}

/// 计算后的一条 buff（同一 spEffectId 从多处获得时合并成一行，copies 记份数）。
public struct LoadoutLine: Sendable, Hashable, Identifiable {
    public let id: String
    public let buffIndex: Int
    public let spEffectId: Int
    public let displayName: String
    public let column: LoadoutColumn
    /// 这条 buff 来自哪些条目（「提升战技攻击力（档位3） ×2」「普通遗物 1：…」）。
    public let sources: [String]
    /// 来源键（wa:<词条> / relic:<格>[:<行>] / acc:<格> / innate:<id> / other:<行键>），移除按钮用。
    public let sourceKeys: [String]
    public let copies: Int
    /// 实际计入的份数（1，或 stackSelf 多份相乘时的份数）。
    public let countedCopies: Int
    public let exclusiveKey: String
    public let verdict: LoadoutVerdict
    /// 要用户确认的条件（发动条件在前）。
    public let needs: [String]
    /// 用户勾过「条件成立」，或不占槽位的栏里勾选本身就是确认。
    public let isConfirmed: Bool
    /// 不占槽位的栏里用户亲手勾选（勾选即确认，不再给「条件成立」勾选框）。
    public let autoConfirm: Bool
    /// 当前武器自带（自动列入）。
    public let isAuto: Bool
    public let stacks: Int?
    /// 各通道乘数（已含层数、段数折算、份数）。
    public let channelMultiplier: [Double]
    /// 单独看这一条的有效倍率（按占比加权；没有构成时为 1）。
    public let multiplier: Double
    /// 按占比加权的攻击力加算点数（只展示）。
    public let weightedFlat: Double
    public let status: LoadoutLineStatus
    /// 不计入的原因。
    public let reasons: [String]
    /// 近似与提示（部分段命中、份数、层数超限）。
    public let notes: [String]
    public let activation: String
    /// 「条件全部成立」口径下叠层没有实际上限、只按 1 层算。
    public let assumedOneStack: Bool

    /// 状态标签 + 原因（汇总行的一句话）。
    public var statusText: String {
        ([status.title] + reasons).joined(separator: "：")
    }

    public var summaryColumn: LoadoutSummaryColumn { column.summaryColumn }
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

/// 自组遗物的一条问题（文案与 Windows 端逐字相同）。
public struct LoadoutIssue: Sendable, Hashable, Identifiable {
    public let kind: String
    public let title: String
    public let detail: String
    public let effectIDs: [Int]

    public var id: String { kind + "-" + effectIDs.map(String.init).joined(separator: "-") }
}

public struct LoadoutRelicCheck: Sendable, Hashable {
    public enum Status: String, Sendable, Hashable {
        case empty, fixed, partial, valid, invalid

        public var title: String { LoadoutText.t("relicStatus." + rawValue) }
    }

    public let status: Status
    public let message: String
    public let issues: [LoadoutIssue]
    public let warnings: [LoadoutIssue]
    public let affixCount: Int

    public static let empty = LoadoutRelicCheck(
        status: .empty, message: LoadoutText.t("relicEmpty"), issues: [], warnings: [], affixCount: 0
    )
}

/// 汇总里的一条提示（kind 与 Windows 端 warning.kind 同名）。
public struct LoadoutWarning: Sendable, Hashable, Identifiable {
    public let kind: String
    public let text: String

    public var id: String { kind + "|" + text }
}

public struct LoadoutEvaluation: Sendable {
    public let total: Double
    public let lines: [LoadoutLine]
    /// 四栏小计（本栏单独连乘加权；没有条目的栏为 ×1）。
    public let columnSubtotals: [LoadoutSummaryColumn: Double]
    public let weaponAffixUsage: LoadoutSlotUsage
    public let deepOnlyUsage: LoadoutSlotUsage
    public let curseUsage: LoadoutSlotUsage
    public let relicUsage: LoadoutSlotUsage
    public let accessoryUsage: LoadoutSlotUsage
    public let relicChecks: [LoadoutRelicCheck]
    public let warnings: [LoadoutWarning]
    public let violations: [String]
    public let weightedFlat: Double
    public let hasComposition: Bool

    /// 计入的条目（去重后留下的），按第一次出现的顺序。
    public var countedLines: [LoadoutLine] { lines.filter { $0.status.isCounted } }

    public static let empty = LoadoutEvaluation(
        total: 1, lines: [], columnSubtotals: [:],
        weaponAffixUsage: LoadoutSlotUsage(used: 0, cap: 0), deepOnlyUsage: LoadoutSlotUsage(used: 0, cap: 0),
        curseUsage: LoadoutSlotUsage(used: 0, cap: 0), relicUsage: LoadoutSlotUsage(used: 0, cap: 0),
        accessoryUsage: LoadoutSlotUsage(used: 0, cap: 0), relicChecks: [], warnings: [], violations: [],
        weightedFlat: 0, hasComposition: false
    )
}

/// 某一栏里一项候选的评估（单独选它时的倍率）。
public struct LoadoutCandidate: Sendable, Hashable, Identifiable {
    public let item: LoadoutItem
    public let lines: [LoadoutLine]
    /// 按当前的确认／层数／选层／选档，单独选它时的有效倍率。
    public let multiplier: Double
    /// 条件全部成立（层数取实际上限、阶梯取最高层）时的有效倍率。
    public let potential: Double
    public let isApplicable: Bool
    public let blockedReason: String?
    /// 还有条件没确认（或层数为 0、未选层）。
    public let needsConfirmation: Bool
    /// 条件全部成立时按占比加权的攻击力加算点数（只展示，不进倍率）。
    public let weightedFlat: Double
    /// 潜在倍率里有叠层条目没有「实际上限」、也还没填层数，只按 1 层算（页面要写明）。
    public let potentialAssumesOneStack: Bool
    /// 最接近生效的那一条的状态与原因（与 Windows 端 row.state / row.reasons 同一口径）。
    public let status: LoadoutLineStatus
    public let reasons: [String]

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
    public let status: LoadoutLineStatus
    public let reasons: [String]
    public let notes: [String]
    /// 条件全部成立时单独这一条的有效倍率（累积阶梯与多档词条按这一行自己的层／档，叠层取实际上限、没有上限的按 1 层）。
    public let multiplier: Double
    /// 叠层条目没有实际上限，倍率只按 1 层算。
    public let assumesOneStack: Bool
    public let activation: String
    public let exclusiveKey: String
    public let searchKey: String
    /// 这一条对当前输出生效（不是「不生效」也不是「需勾选攻击情境」）。
    public let isApplicable: Bool

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

    public let indexByID: [Int: Int]
    /// 带 countsAsDamage 的倍率／加算字段（与 Windows 端 entry.countsAsDamage 同一口径）。
    public let countsAsDamage: [Bool]
    /// 能进配置页的条目：带伤害字段、target ∈ {self, ally}、direction ≠ decrease。
    public let listable: [Bool]

    public let weaponAffixItems: [LoadoutItem]
    public let weaponAffixByID: [Int: BuffWeaponAffixInfo]
    /// 全部带增伤 buff 的遗物词条（effectId 升序；常规／深夜的可用性在查询时按 CheckMode 过滤）。
    public let relicAffixItems: [LoadoutItem]
    /// 官方固定词条遗物（按 relicIds[0] 升序）。
    public let fixedRelicItems: [LoadoutItem]
    public let accessoryItems: [LoadoutItem]
    /// 不占槽位的各分栏（武器固有另走 `innateItems(forWeapon:)`）。
    public let slotlessItems: [LoadoutColumn: [LoadoutItem]]
    /// 深夜遗物可配的负面词条（词条库 isCurse 且在诅咒池，按 effectId 升序）。
    public let curseAffixes: [Affix]
    /// 深夜遗物的负面词条池：词条库里只装诅咒词条的池（有多个时取成员最多、再取 ID 小的），
    /// 算不出来退回与 core.js 同值的兜底常量（与 Windows 端 cursePoolOf 同一口径）。
    public let cursePoolID: Int

    let itemsByID: [String: LoadoutItem]
    /// weaponId → 该武器自带的固有效果（buff 下标，数据顺序）。
    let innateByWeapon: [Int: [Int]]
    /// 全部固有效果（buff 下标，数据顺序）。
    let innateAll: [Int]
    /// 累积阶梯（ladderID）→ 能进计算的各层（buff 下标，按层升序）。
    let ladderMembers: [Int: [Int]]
    /// 多档词条组键 → 各档（buff 下标，按档位升序）。
    public let variantMembers: [String: [Int]]
    /// requiresGoodsIds 的道具名。
    let goodsNames: [Int: String]
    /// 每条 buff 的原始通道乘数（按 rateFields 顺序相乘，与 Windows 端 multiplierMap 同序）与逐通道加算。
    let baseChannels: [[Double]]
    let baseFlat: [[Double]]
    /// 能进伤害计算的倍率字段（rateFields 顺序）→ 通道。
    let multiplierFields: [(key: String, fallback: Double, channels: [SkillDamageChannel])]
    let flatFields: [(key: String, fallback: Double, channels: [SkillDamageChannel])]

    public init(ranker: BuffRankerIndex, catalog: [Affix] = []) {
        self.ranker = ranker
        let dataset = ranker.dataset
        slotRules = dataset.slotRules ?? .fallback
        supportsLoadout = dataset.slotRules != nil && dataset.buffs.contains { !$0.appliesTo.isEmpty }
        catalogAffixes = Dictionary(catalog.map { ($0.effectID, $0) }, uniquingKeysWith: { first, _ in first })
        indexByID = Dictionary(
            dataset.buffs.enumerated().map { ($0.element.spEffectId, $0.offset) }, uniquingKeysWith: { first, _ in first }
        )

        // 字段表：只收 countsAsDamage 的字段，multiplier 进乘积、flat 进加算（与 Windows rateFieldPlan 同一口径）。
        var multiplierFields: [(key: String, fallback: Double, channels: [SkillDamageChannel])] = []
        var flatFields: [(key: String, fallback: Double, channels: [SkillDamageChannel])] = []
        for field in dataset.rateFields where field.countsAsDamage {
            if field.valueKind == .multiplier, !field.key.hasSuffix("AttackPower") {
                let channels = BuffRankerIndex.channels(for: field.key)
                if !channels.isEmpty { multiplierFields.append((field.key, field.defaultValue, channels)) }
            } else if field.valueKind == .flat, let element = BuffRankerIndex.element(forFlat: field.key) {
                let channels = SkillDamageChannel.allCases.filter { $0.element == element }
                flatFields.append((field.key, field.defaultValue, channels))
            }
        }
        self.multiplierFields = multiplierFields
        self.flatFields = flatFields

        var baseChannels: [[Double]] = []
        var baseFlat: [[Double]] = []
        var counts: [Bool] = []
        for buff in dataset.buffs {
            let restricted = Self.scopeRestricted(buff)
            let channels = Self.channelTable(rates: buff.rates, fields: multiplierFields, restricted: restricted)
            let flat = Self.flatTable(rates: buff.rates, fields: flatFields)
            baseChannels.append(channels)
            baseFlat.append(flat)
            counts.append(channels.contains { $0 != 1 } || flat.contains { $0 != 0 })
        }
        self.baseChannels = baseChannels
        self.baseFlat = baseFlat
        countsAsDamage = counts
        listable = dataset.buffs.enumerated().map { offset, buff in
            counts[offset] && (buff.target == "self" || buff.target == "ally") && buff.direction != "decrease"
        }

        let indexByID = self.indexByID
        let listable = self.listable
        func listableIndices(_ ids: [Int]) -> [Int] {
            var seen: Set<Int> = []
            return ids.compactMap { indexByID[$0] }.filter { listable[$0] && seen.insert($0).inserted }
        }

        // 累积阶梯与多档词条的成员。
        var ladders: [Int: [Int]] = [:]
        var variants: [String: [Int]] = [:]
        for (offset, buff) in dataset.buffs.enumerated() {
            if listable[offset], let ladder = buff.accumulatorLadder { ladders[ladder.ladderID, default: []].append(offset) }
            if let variant = buff.affixVariant { variants[variant.groupKey, default: []].append(offset) }
        }
        ladderMembers = ladders.mapValues { members in
            members.sorted { lhs, rhs in
                let left = dataset.buffs[lhs].accumulatorLadder?.tier ?? 0
                let right = dataset.buffs[rhs].accumulatorLadder?.tier ?? 0
                return left == right ? dataset.buffs[lhs].spEffectId < dataset.buffs[rhs].spEffectId : left < right
            }
        }
        variantMembers = variants.mapValues { members in
            members.sorted { lhs, rhs in
                let left = dataset.buffs[lhs].affixVariant?.variant ?? 0
                let right = dataset.buffs[rhs].affixVariant?.variant ?? 0
                return left == right ? dataset.buffs[lhs].spEffectId < dataset.buffs[rhs].spEffectId : left < right
            }
        }

        var goods: [Int: String] = [:]
        for buff in dataset.buffs {
            for source in buff.sources where source.kind == "goods" {
                guard let id = source.sourceID, let name = source.nameZh, goods[id] == nil else { continue }
                goods[id] = name
            }
        }
        goodsNames = goods

        // 局内武器词条（按 AttachEffect id 升序；诅咒不进正面词条栏）。
        let weaponInfos = dataset.weaponAffixes
        weaponAffixByID = Dictionary(weaponInfos.map { ($0.attachEffectId, $0) }, uniquingKeysWith: { first, _ in first })
        weaponAffixItems = weaponInfos.sorted { $0.attachEffectId < $1.attachEffectId }.compactMap { info in
            guard !info.isCurse, !info.isDebuff else { return nil }
            let buffIndices = listableIndices(info.spEffectIds)
            guard !buffIndices.isEmpty else { return nil }
            var badges: [String] = []
            if let potency = info.potency { badges.append(LoadoutText.f("badges.potency", potency)) }
            if info.deepOnlyPositive || buffIndices.contains(where: { dataset.buffs[$0].weaponAffixDeepOnlyPositive }) {
                badges.append(LoadoutText.t("badges.deepOnly"))
            }
            if info.isBlessing { badges.append(LoadoutText.t("badges.blessing")) }
            if info.roles.contains("fixed") { badges.append(LoadoutText.t("badges.fixed")) }
            let name = info.nameZh.isEmpty ? (info.nameEn.isEmpty ? "#\(info.attachEffectId)" : info.nameEn) : info.nameZh
            return LoadoutItem(
                kind: .weaponAffix(info.attachEffectId), column: .weaponAffix, title: name,
                subtitle: "",
                groupTitle: nil, badges: badges, buffIndices: buffIndices, infoLines: [],
                searchKey: "\(name) \(info.nameEn) \(info.paramName ?? "") \(info.attachEffectId)".foldedForSearch,
                weaponAffix: info, relicAffix: nil, fixedRelic: nil, isAutoInnate: false
            )
        }

        // 遗物词条：relicAffixes[].catalogEffectId → 词条库（只收能进计算的条目，effectId 升序）。
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
            if affix.requiresCurse { badges.append(LoadoutText.t("badges.requiresCurse")) }
            return LoadoutItem(
                kind: .relicAffix(effectID), column: .relic, title: affix.name,
                subtitle: affix.category, groupTitle: nil, badges: badges,
                buffIndices: relicMap[effectID] ?? [], infoLines: [],
                searchKey: affix.searchableText,
                weaponAffix: nil, relicAffix: affix, fixedRelic: nil, isAutoInnate: false
            )
        }

        // 固定遗物：整件，spEffectIds 里能进计算的计入，其余词条只显示（按 relicIds[0] 升序）。
        fixedRelicItems = dataset.fixedRelics.enumerated()
            .sorted { $0.element.relicID == $1.element.relicID ? $0.offset < $1.offset : $0.element.relicID < $1.element.relicID }
            .map { offset, relic in
                let buffIndices = listableIndices(relic.spEffectIds)
                let counted = Set(buffIndices.flatMap { dataset.buffs[$0].relicAffixes.map(\.attachEffectId) })
                var lines: [LoadoutItemInfoLine] = []
                for (position, attachID) in relic.attachEffectIds.enumerated() {
                    let name = relic.attachEffectNamesZh.indices.contains(position)
                        ? (relic.attachEffectNamesZh[position] ?? LoadoutText.f("relicUnnamedEffect", attachID))
                        : LoadoutText.f("relicUnnamedEffect", attachID)
                    lines.append(LoadoutItemInfoLine(text: name, counted: counted.contains(attachID)))
                }
                let name = relic.nameZh.isEmpty ? relic.nameEn : relic.nameZh
                return LoadoutItem(
                    kind: .fixedRelic(offset), column: .relic, title: name,
                    subtitle: LoadoutText.fixedRelicSubtitle(relicID: relic.relicID, color: relic.color),
                    groupTitle: nil, badges: relic.isDeepRelic ? [LoadoutText.t("runMode.deep")] : [],
                    buffIndices: buffIndices, infoLines: lines,
                    searchKey: ([name, relic.nameEn, String(relic.relicID)] + lines.map(\.text))
                        .joined(separator: " ").foldedForSearch,
                    weaponAffix: nil, relicAffix: nil, fixedRelic: relic, isAutoInnate: false
                )
            }

        // 护符：主槽位是 accessory 的条目按护符 id 归组（同一护符的几档 / 几条效果合成一项），id 升序。
        var accessoryGroups: [Int: (name: String, indices: [Int])] = [:]
        for (offset, buff) in dataset.buffs.enumerated() where listable[offset] && buff.sourceSlot == "accessory" {
            for source in buff.sources where source.kind == "accessory" {
                guard let id = source.sourceID else { continue }
                let name = source.nameZh ?? source.nameEn ?? "#\(id)"
                if accessoryGroups[id] == nil { accessoryGroups[id] = (name, []) }
                if !(accessoryGroups[id]?.indices.contains(offset) ?? false) { accessoryGroups[id]?.indices.append(offset) }
            }
        }
        accessoryItems = accessoryGroups.keys.sorted().map { id in
            let group = accessoryGroups[id]!
            return LoadoutItem(
                kind: .accessory(id), column: .accessory, title: group.name,
                subtitle: group.indices.count > 1 ? LoadoutText.f("accEffectCount", group.indices.count) : "",
                groupTitle: nil, badges: [], buffIndices: group.indices, infoLines: [],
                searchKey: ([group.name, String(id)] + group.indices.map { dataset.buffs[$0].displayName })
                    .joined(separator: " ").foldedForSearch,
                weaponAffix: nil, relicAffix: nil, fixedRelic: nil, isAutoInnate: false
            )
        }

        // 不占槽位的各分栏 + 武器固有。
        var slotless: [LoadoutColumn: [LoadoutItem]] = [:]
        var innate: [Int: [Int]] = [:]
        var innateAll: [Int] = []
        var seenLadders: Set<Int> = []
        for (offset, buff) in dataset.buffs.enumerated() where listable[offset] {
            let column = LoadoutColumn(sourceSlot: buff.sourceSlot)
            if column == .weaponInnate {
                innateAll.append(offset)
                for weaponID in buff.weaponInnate?.weaponIds ?? [] { innate[weaponID, default: []].append(offset) }
                continue
            }
            guard !column.isSlotted else { continue }
            if let ladder = buff.accumulatorLadder {
                // 累积阶梯的各层合成一项（选中后在行里选层），不逐层各占一行。
                guard seenLadders.insert(ladder.ladderID).inserted else { continue }
                let members = ladders[ladder.ladderID] ?? [offset]
                let sorted = members.sorted {
                    (dataset.buffs[$0].accumulatorLadder?.tier ?? 0) < (dataset.buffs[$1].accumulatorLadder?.tier ?? 0)
                }
                guard let first = sorted.first else { continue }
                let base = Self.buffItem(first, buff: dataset.buffs[first], column: column, dataset: dataset)
                slotless[column, default: []].append(LoadoutItem(
                    kind: .buff(dataset.buffs[first].spEffectId), column: column, title: LoadoutText.stripTierSuffix(base.title),
                    subtitle: LoadoutText.f("ladderTierCount", sorted.count), groupTitle: base.groupTitle,
                    badges: base.badges, buffIndices: sorted, infoLines: [],
                    searchKey: ([base.searchKey] + sorted.map { dataset.buffs[$0].displayName.foldedForSearch })
                        .joined(separator: " "),
                    weaponAffix: nil, relicAffix: nil, fixedRelic: nil, isAutoInnate: false
                ))
                continue
            }
            slotless[column, default: []].append(Self.buffItem(offset, buff: buff, column: column, dataset: dataset))
        }
        slotlessItems = slotless
        innateByWeapon = innate
        self.innateAll = innateAll

        let cursePool = Self.cursePool(of: catalog)
        cursePoolID = cursePool
        curseAffixes = catalog.filter { $0.isCurse && $0.poolIDs.contains(cursePool) }
            .sorted { $0.effectID < $1.effectID }

        var byID: [String: LoadoutItem] = [:]
        for item in weaponAffixItems + relicAffixItems + fixedRelicItems + accessoryItems { byID[item.id] = item }
        for items in slotless.values { for item in items { byID[item.id] = item } }
        itemsByID = byID
    }

    public init(data: Data, catalog: [Affix] = []) throws {
        try self.init(ranker: BuffRankerIndex(data: data), catalog: catalog)
    }

    static func cursePool(of affixes: [Affix]) -> Int {
        var curseCount: [Int: Int] = [:]
        var mixed: Set<Int> = []
        for affix in affixes {
            for pool in affix.poolIDs {
                if affix.isCurse { curseCount[pool, default: 0] += 1 } else { mixed.insert(pool) }
            }
        }
        var best: Int?
        for (pool, count) in curseCount where !mixed.contains(pool) {
            guard let current = best else { best = pool; continue }
            let currentCount = curseCount[current] ?? 0
            if count > currentCount || (count == currentCount && pool < current) { best = pool }
        }
        return best ?? deepCursePoolID
    }

    /// scope.atkAttribute（0–3）：倍率只落在那一个物理通道。
    static func scopeRestricted(_ buff: BuffEntry) -> SkillDamageChannel? {
        guard let code = buff.scope.atkAttribute, (0...3).contains(code) else { return nil }
        return SkillDamageChannel.physical(code: code)
    }

    static func channelTable(
        rates: [String: Double], fields: [(key: String, fallback: Double, channels: [SkillDamageChannel])],
        restricted: SkillDamageChannel?
    ) -> [Double] {
        var table = Array(repeating: 1.0, count: SkillDamageChannel.allCases.count)
        for field in fields {
            guard let value = rates[field.key], value.isFinite, value > 0, value != field.fallback else { continue }
            let channels = restricted.map { only in field.channels.filter { $0 == only } } ?? field.channels
            for channel in channels { table[channel.rawValue] *= value }
        }
        return table
    }

    static func flatTable(
        rates: [String: Double], fields: [(key: String, fallback: Double, channels: [SkillDamageChannel])]
    ) -> [Double] {
        var table = Array(repeating: 0.0, count: SkillDamageChannel.allCases.count)
        for field in fields {
            guard let value = rates[field.key], value.isFinite, value != field.fallback else { continue }
            for channel in field.channels { table[channel.rawValue] += value }
        }
        return table
    }

    static func buffItem(_ offset: Int, buff: BuffEntry, column: LoadoutColumn, dataset: BuffDataset) -> LoadoutItem {
        var group: String?
        var subtitle = ""
        switch column {
        case .character:
            let hero = LoadoutText.heroGroup(paramName: buff.paramName)
            group = hero.hero
            subtitle = hero.kind
        case .weaponSkill:
            group = buff.sources.compactMap(\.artsNameZh).first ?? LoadoutText.t("groupUnknownSkill")
        case .consumable:
            group = buff.sources.first { $0.kind == "goods" }?.nameZh
        case .spellBuff:
            group = buff.sources.first { $0.kind == "spell" }?.nameZh
        default:
            break
        }
        let sourceNames = buff.sources.compactMap { $0.nameZh ?? $0.artsNameZh }
        return LoadoutItem(
            kind: .buff(buff.spEffectId), column: column, title: buff.displayName,
            subtitle: subtitle, groupTitle: group, badges: LoadoutText.entryBadges(buff), buffIndices: [offset], infoLines: [],
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

    /// 武器固有栏：当前武器自带的（自动列入）在前，其它武器的固有效果（手动勾选）在后。
    public func innateItems(forWeapon weaponID: Int?) -> [LoadoutItem] {
        let auto = Set(autoInnateIndices(forWeapon: weaponID))
        var result: [LoadoutItem] = []
        for offset in innateAll where auto.contains(offset) { result.append(innateItem(offset, auto: true)) }
        var seenLadders: Set<Int> = []
        for offset in innateAll where !auto.contains(offset) {
            if let ladder = dataset.buffs[offset].accumulatorLadder, !seenLadders.insert(ladder.ladderID).inserted { continue }
            result.append(innateItem(offset, auto: false))
        }
        return result
    }

    /// 当前武器自带、自动列入的固有效果（buff 下标）。
    public func autoInnateIndices(forWeapon weaponID: Int?) -> [Int] {
        guard let weaponID else { return [] }
        return innateByWeapon[weaponID] ?? []
    }

    /// 这条累积阶梯能进计算的各层（第几层，升序）；选层控件只列这些。
    public func ladderTierOptions(_ ladderID: Int) -> [Int] {
        (ladderMembers[ladderID] ?? []).compactMap { dataset.buffs[$0].accumulatorLadder?.tier }
    }

    /// 这条累积阶梯实际收录的最高层（「条件成立时」与勾选预填都取它，不取 accumulatorLadder.tiers）。
    public func ladderTopTier(_ ladderID: Int) -> Int? {
        ladderTierOptions(ladderID).last
    }

    /// 多档词条这一组的各档（buff 下标，按档位升序）。
    public func variantOptions(_ groupKey: String) -> [Int] { variantMembers[groupKey] ?? [] }

    /// 多档词条这一组选中的那一档（buff 下标）：用户选过的，否则第 1 档。
    public func selectedVariant(_ groupKey: String, loadout: BuffLoadout) -> Int? {
        let members = variantOptions(groupKey)
        if let chosen = loadout.variantChoices[groupKey], let offset = members.first(where: { dataset.buffs[$0].spEffectId == chosen }) {
            return offset
        }
        return members.first
    }

    /// 局内武器词条的「词条本身」：paramName 去掉末尾的「 - Potency N」；没有 paramName 时退中文名。
    /// 同一个键下的不同 AttachEffect＝同一词条的不同档位（只做提示，不参与计算；不用 compatibilityId 猜）。
    public static func weaponAffixFamilyKey(_ info: BuffWeaponAffixInfo) -> String {
        if let param = info.paramName?.trimmingCharacters(in: .whitespaces), !param.isEmpty {
            return "param:" + param.replacingOccurrences(
                of: #"\s*-\s*Potency\s*\d+\s*$"#, with: "", options: [.regularExpression, .caseInsensitive]
            )
        }
        return "zh:" + info.nameZh
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

    func innateItem(_ offset: Int, auto: Bool) -> LoadoutItem {
        let buff = dataset.buffs[offset]
        var indices = [offset]
        var title = buff.displayName
        if let ladder = buff.accumulatorLadder, let members = ladderMembers[ladder.ladderID] {
            indices = members
            title = LoadoutText.stripTierSuffix(title)
        }
        let base = Self.buffItem(offset, buff: buff, column: .weaponInnate, dataset: dataset)
        var badges = base.badges
        if auto { badges.insert(LoadoutText.t("badges.autoInnate"), at: 0) }
        if buff.weaponInnate?.inferredFromRowName == true { badges.append(LoadoutText.t("badges.inferredInnate")) }
        return LoadoutItem(
            kind: base.kind, column: .weaponInnate, title: title,
            subtitle: base.subtitle, groupTitle: auto ? LoadoutText.t("groupAutoInnate") : LoadoutText.t("groupOtherInnate"),
            badges: badges, buffIndices: indices, infoLines: [], searchKey: base.searchKey,
            weaponAffix: nil, relicAffix: nil, fixedRelic: nil, isAutoInnate: auto
        )
    }

    /// 遗物词条在这张卡（普通／深夜）上能不能选：沿用词条检查页的 CheckMode 口径。
    public func isRelicAffixEligible(_ affix: Affix, deepSlot: Bool) -> Bool {
        affix.isEligible(for: deepSlot ? .deepPositive : .currentNormal)
    }

    // MARK: 生效判定

    /// 按 appliesTo / appliesToDetail 判定一条 buff 对当前输出手段是否生效（与 Windows appliesVerdict 同一口径）。
    public func verdict(forBuffAt offset: Int, output: LoadoutOutput) -> LoadoutVerdict {
        let buff = dataset.buffs[offset]
        let activationNote = activationNote(buff)
        let cls = output.outputClass
        let raw = buff.appliesTo[cls.rawValue]
        let detail = buff.appliesToDetail[cls.rawValue]
        let value: LoadoutVerdict.Value = raw == "yes" ? .yes : (raw == "conditional" ? .conditional : (raw == nil ? .missing : .no))
        var needs: [String] = []
        var requirements: [LoadoutRequirement] = []
        func need(_ key: String, _ text: String) {
            needs.append(text)
            requirements.append(LoadoutRequirement(key: key, text: text, state: .needsUser))
        }
        func make(
            _ state: LoadoutVerdict.State, reasons: [String] = [], notes: [String] = [], fraction: Double = 1,
            restricted: SkillDamageChannel? = nil
        ) -> LoadoutVerdict {
            LoadoutVerdict(
                value: value, state: state, reasons: reasons, needs: state == .no ? [] : needs, notes: notes,
                fraction: fraction, restrictedChannel: restricted, requirements: requirements,
                activation: buff.activation, activationNote: activationNote
            )
        }
        guard raw == "yes" || raw == "conditional" else {
            let fallback = raw == nil ? LoadoutText.t("verdictMissing") : LoadoutText.t("verdictNoFallback")
            let reason = detail?.reason ?? ""
            return make(.no, reasons: [reason.isEmpty ? fallback : reason])
        }
        if !buff.requiresGoodsIds.isEmpty {
            let names = buff.requiresGoodsIds.map { goodsNames[$0] ?? LoadoutText.f("goodsFallback", $0) }
            need("goods", LoadoutText.f("requireGoods", names.joined(separator: "／")))
        }
        if raw == "yes" {
            return make(needs.isEmpty ? .yes : .pending)
        }
        let reason = detail?.reason ?? ""
        guard let requires = detail?.requires, requires.hasAnyKey else {
            need("detail", LoadoutText.f("requireManual", reason))
            return make(.pending, reasons: reason.isEmpty ? [] : [reason])
        }
        var fails: [String] = []
        var contexts: [String] = []
        var fraction = 1.0
        var notes: [String] = []
        var restricted: SkillDamageChannel?
        let clsTitle = cls.title
        if let hand = requires.hand {
            let text = LoadoutText.f("requireHand", LoadoutText.handName(hand), LoadoutText.handName(output.hand))
            let ok = hand == output.hand
            requirements.append(LoadoutRequirement(key: "hand", text: text, state: ok ? .met : .unmet))
            if !ok { fails.append(text) }
        }
        if requires.hasAttackWeaponTypes {
            let names = requires.attackWeaponTypes.map { wepTypeLabel($0) }.joined(separator: "／")
            let own = output.attackWepType
            let text = own.map { LoadoutText.f("requireWepType", names, wepTypeLabel($0)) }
                ?? LoadoutText.f("requireWepTypeNoWeapon", names)
            let ok = own.map { requires.attackWeaponTypes.contains($0) } ?? false
            requirements.append(LoadoutRequirement(key: "attackWeaponTypes", text: text, state: ok ? .met : .unmet))
            if !ok { fails.append(text) }
        }
        if let physical = requires.physicalType {
            if (0...3).contains(physical) {
                let channel = SkillDamageChannel.physical(code: physical)
                restricted = channel
                let present = !output.hasComposition
                    || (output.shares.indices.contains(channel.rawValue) && output.shares[channel.rawValue] > 0)
                let text = LoadoutText.f(present ? "requirePhysical" : "requirePhysicalFail", channel.titleZh)
                requirements.append(LoadoutRequirement(key: "physicalType", text: text, state: present ? .met : .unmet))
                if !present { fails.append(text) }
            } else {
                need("physicalType", LoadoutText.f("requireUnknown", "physicalType=\(physical)"))
            }
        }
        if requires.hasSubCategoriesAny {
            let label = subCategoryLabel(requires.subCategoriesAny)
            let sets: [BuffSubCategorySet]?
            switch cls {
            case .skill: sets = output.skillID.flatMap { dataset.attackIndex.skills[$0] }
            case .sorcery, .incantation: sets = output.spellID.flatMap { dataset.attackIndex.spells[$0] }
            }
            let wanted = Set(requires.subCategoriesAny)
            let total = sets?.reduce(0) { $0 + $1.hits } ?? 0
            if let sets, total > 0 {
                let matched = sets.filter { !wanted.isDisjoint(with: $0.subs) }.reduce(0) { $0 + $1.hits }
                if matched == 0 {
                    let text = LoadoutText.f("requireSubsFail", clsTitle, label)
                    requirements.append(LoadoutRequirement(key: "subCategoriesAny", text: text, state: .unmet))
                    fails.append(text)
                } else if matched < total {
                    fraction = Double(matched) / Double(total)
                    let text = LoadoutText.f("requireSubsPartial", clsTitle, matched, total, label)
                    requirements.append(LoadoutRequirement(key: "subCategoriesAny", text: text, state: .partial(fraction)))
                    notes.append(text)
                } else {
                    let text = LoadoutText.f("requireSubsAll", clsTitle, total, label)
                    requirements.append(LoadoutRequirement(key: "subCategoriesAny", text: text, state: .met))
                }
            } else {
                need("subCategoriesAny", LoadoutText.f("requireSubsUnknown", clsTitle, label))
            }
        }
        if requires.hasAttackContexts {
            let names = requires.attackContexts.map { dataset.attackContextLabel($0) }.joined(separator: "／")
            let picked = requires.attackContexts.contains { output.attackContexts.contains($0) }
            let text = LoadoutText.f("requireContext", names)
            requirements.append(LoadoutRequirement(key: "attackContexts", text: text, state: picked ? .met : .unmet))
            if !picked { contexts = requires.attackContexts }
        }
        if requires.imbuedWeaponOnly { need("imbuedWeaponOnly", LoadoutText.t("requireImbued")) }
        if requires.attachedWeaponOnly { need("attachedWeaponOnly", LoadoutText.t("requireAttached")) }
        for key in requires.unknownKeys { need("unknown-\(key)", LoadoutText.f("requireUnknown", key)) }
        if !fails.isEmpty {
            return make(.no, reasons: fails + (reason.isEmpty ? [] : [reason]), restricted: restricted)
        }
        if !contexts.isEmpty {
            let names = contexts.map { dataset.attackContextLabel($0) }.joined(separator: "／")
            return make(.context, reasons: [LoadoutText.f("requireContext", names)], restricted: restricted)
        }
        if !needs.isEmpty {
            return make(.pending, reasons: reason.isEmpty ? [] : [reason], notes: notes, fraction: fraction, restricted: restricted)
        }
        return make(.yes, notes: notes, fraction: fraction, restricted: restricted)
    }

    /// 发动条件的说明：发动型 / 条件型；「装备三把以上 X」写出数量与类别。
    func activationNote(_ buff: BuffEntry) -> String? {
        switch buff.activation {
        case "passive": return nil
        case "activated": return LoadoutText.t("activationNeed.activated")
        default:
            if let types = buff.scope.weaponTypes, types.mode == "equippedCount" {
                let names = types.namesZh.isEmpty ? types.wepTypes.map { wepTypeLabel($0) } : types.namesZh
                return LoadoutText.f("activationNeed.equipped", types.count ?? 3, names.joined(separator: "／"))
            }
            return LoadoutText.t("activationNeed.conditional")
        }
    }

    func wepTypeLabel(_ wepType: Int) -> String {
        dataset.wepTypeLabels[wepType] ?? LoadoutText.f("wepTypeFallback", wepType)
    }

    func subCategoryLabel(_ subs: [Int]) -> String {
        "[" + subs.map { sub in dataset.subCategoryLabels[sub].map { "\(sub) \($0)" } ?? String(sub) }
            .joined(separator: "、") + "]"
    }

    // MARK: 叠层

    /// 用户填的层数（缺省 0）。
    public func stacks(for buff: BuffEntry, loadout: BuffLoadout) -> Int {
        max(0, loadout.stackCounts[buff.spEffectId] ?? 0)
    }

    /// 勾选不占槽位的叠层条目时预填的层数：一局实际上限（没有实测上限的填 1），不超过参数表上限。
    public static func defaultStacks(_ input: BuffStackInput) -> Int {
        min(input.practicalMaxStacks.map { $0 > 0 ? $0 : 1 } ?? 1, input.maxAllowedStacks)
    }

    /// 叠层条目的提示：超过一局实际上限、超过参数表／页面上限、超过游戏文本备好的『＋N』。
    static func stackWarnings(_ input: BuffStackInput, raw: Int, stacks: Int) -> [String] {
        guard stacks > 0 else { return [] }
        var warnings: [String] = []
        if let practical = input.practicalMaxStacks, practical > 0, stacks > practical {
            // practicalMaxSource 的短来源（「实测」「用户反馈」…）：取第一个冒号／括号之前的部分。
            let label = (input.practicalMaxSource ?? "")
                .components(separatedBy: CharacterSet(charactersIn: "：:（(")).first ?? ""
            warnings.append(LoadoutText.f("stackOverPractical", stacks, practical, label.isEmpty ? "practicalMaxStacks" : label))
        }
        let max = input.maxAllowedStacks
        if raw > max { warnings.append(LoadoutText.f(input.isLadder ? "stackOverParam" : "stackOverCeiling", max)) }
        if !input.isLadder, let label = input.uiLabelMax, stacks > label {
            warnings.append(LoadoutText.f("stackOverLabel", label))
        }
        return warnings
    }

    // MARK: 倍率

    /// 这一条的逐通道倍率与加算：叠层替换 appliesToRateKeys、物理类型限定、部分段近似（1＋(m−1)×占比）、
    /// stackSelf 多份乘方（加算×份数）。与 Windows 端 entryTables 同一口径。
    func tables(
        forBuffAt offset: Int, stacks: Int?, restricted: SkillDamageChannel?, fraction: Double, copies: Int
    ) -> (channels: [Double], flat: [Double]) {
        let buff = dataset.buffs[offset]
        var channels: [Double]
        if let input = buff.stackInput, let stacks {
            guard stacks > 0 else {
                return (Array(repeating: 1, count: SkillDamageChannel.allCases.count),
                        Array(repeating: 0, count: SkillDamageChannel.allCases.count))
            }
            var rates = buff.rates
            if let value = input.multiplier(forStacks: stacks) {
                let keys = input.appliesToRateKeys.isEmpty ? [input.multiplierKey] : input.appliesToRateKeys
                for key in keys where !key.isEmpty { rates[key] = value }
            }
            channels = Self.channelTable(rates: rates, fields: multiplierFields, restricted: restricted ?? Self.scopeRestricted(buff))
        } else if restricted != nil {
            channels = Self.channelTable(rates: buff.rates, fields: multiplierFields, restricted: restricted)
        } else {
            channels = baseChannels[offset]
        }
        var flat = baseFlat[offset]
        let weight = fraction >= 0 && fraction < 1 ? fraction : 1
        for index in channels.indices {
            if weight < 1 {
                channels[index] = 1 + (channels[index] - 1) * weight
                flat[index] *= weight
            }
            if copies > 1 {
                channels[index] = pow(channels[index], Double(copies))
                flat[index] *= Double(copies)
            }
        }
        return (channels, flat)
    }

    // MARK: 自组遗物合法性

    /// 自组遗物的合法性（与 Windows 端 checkCustomRelic 同一口径、同一文案）：
    /// 正面词条不足三条时用可落任一槽池、不参与互斥的占位词条补足，再调 LegalityChecker（普通遗物 1.03 普通口径，
    /// 深夜遗物深夜正面口径）；问题按类型改用本页文案。深夜遗物另按存档检查的深夜遗物审计查诅咒配对。
    public func relicCheck(_ card: LoadoutRelicCard) -> LoadoutRelicCheck {
        switch card.choice {
        case .empty:
            return .empty
        case .fixed:
            return LoadoutRelicCheck(
                status: .fixed, message: LoadoutText.t("relicFixedValid"), issues: [], warnings: [], affixCount: 0
            )
        case .custom:
            break
        }
        guard hasCatalog else {
            return LoadoutRelicCheck(
                status: .invalid, message: LoadoutText.t("relicNoCatalog"),
                issues: [LoadoutIssue(kind: "noCatalog", title: LoadoutText.t("relicNoCatalog"), detail: "", effectIDs: [])],
                warnings: [], affixCount: 0
            )
        }
        var rows: [(row: Int, affix: Affix?, curse: Affix?)] = []
        var unknown: [Int] = []
        for (row, entry) in card.rows.enumerated() {
            var affix: Affix?
            var curse: Affix?
            if let id = entry.affixID {
                affix = catalogAffixes[id]
                if affix == nil, !unknown.contains(id) { unknown.append(id) }
            }
            if let id = entry.curseID {
                curse = catalogAffixes[id]
                if curse == nil, !unknown.contains(id) { unknown.append(id) }
            }
            if affix != nil || curse != nil { rows.append((row, affix, curse)) }
        }
        if !unknown.isEmpty {
            return LoadoutRelicCheck(
                status: .invalid, message: LoadoutText.t("relicInvalid"),
                issues: [LoadoutIssue(
                    kind: "unknownEffect", title: LoadoutText.t("relicUnknownEffectTitle"),
                    detail: LoadoutText.f("relicUnknownEffectDetail", unknown.map(String.init).joined(separator: "、")),
                    effectIDs: unknown
                )],
                warnings: [], affixCount: 0
            )
        }
        if rows.isEmpty { return .empty }
        let mode: CheckMode = card.isDeepSlot ? .deepPositive : .currentNormal
        let affixes = rows.compactMap(\.affix)
        var issues: [LoadoutIssue] = []
        if !affixes.isEmpty {
            var padded = affixes
            while padded.count < 3 { padded.append(Self.placeholderAffix(padded.count, mode: mode)) }
            let checker = LegalityChecker()
            let ordered = checker.canonicalOrder(padded)
            let result = checker.check(ordered, mode: mode)
            if result.status == .invalid {
                issues = Self.checkerIssues(result.issues, ordered: ordered, mode: mode)
            }
        }
        var warnings: [LoadoutIssue] = []
        let before = issues.count
        if card.isDeepSlot {
            issues += Self.curseIssues(rows, poolID: cursePoolID)
            if issues.count == before {
                warnings.append(LoadoutIssue(
                    kind: "cursePairing", title: LoadoutText.t("cursePairingTitle"),
                    detail: LoadoutText.f("cursePairingDetail", cursePoolID), effectIDs: []
                ))
            }
        } else {
            // 普通遗物没有诅咒槽：带了诅咒一律是多余的。
            for row in rows {
                guard let curse = row.curse else { continue }
                issues.append(LoadoutIssue(
                    kind: "curseUnexpected", title: LoadoutText.t("curseUnexpectedTitle"),
                    detail: LoadoutText.f("curseUnexpectedDetail", row.row + 1, curse.name), effectIDs: [curse.effectID]
                ))
            }
        }
        if !issues.isEmpty {
            return LoadoutRelicCheck(
                status: .invalid, message: LoadoutText.t("relicInvalid"), issues: issues, warnings: warnings,
                affixCount: affixes.count
            )
        }
        if affixes.count < 3 {
            return LoadoutRelicCheck(
                status: .partial, message: LoadoutText.f("relicPartial", affixes.count, 3 - affixes.count),
                issues: [], warnings: warnings, affixCount: affixes.count
            )
        }
        return LoadoutRelicCheck(
            status: .valid, message: LoadoutText.t(card.isDeepSlot ? "relicValidDeep" : "relicValidNormal"),
            issues: [], warnings: warnings, affixCount: affixes.count
        )
    }

    /// 不足三条时补的占位词条：能落进该模式的任一槽池、不参与互斥、排在最后。
    static func placeholderAffix(_ position: Int, mode: CheckMode) -> Affix {
        Affix(
            effectID: -(position + 1), name: LoadoutText.t("relicPlaceholderAffix"), compatibilityID: -1,
            sortID: Int.max, poolIDs: mode.eligiblePoolIDs, requiresCurse: false
        )
    }

    /// LegalityChecker 判出的问题按类型改用本页文案（两端逐字一致），只列真实词条；
    /// 排序：重复 → 互斥 → 出货池／槽池模板，同类按涉及词条的规范顺序。
    static func checkerIssues(_ raw: [CheckIssue], ordered: [Affix], mode: CheckMode) -> [LoadoutIssue] {
        let kindOrder = ["duplicate", "conflict", "unavailable"]
        var position: [Int: Int] = [:]
        for (index, affix) in ordered.enumerated() where position[affix.effectID] == nil { position[affix.effectID] = index }
        let byID = Dictionary(ordered.map { ($0.effectID, $0) }, uniquingKeysWith: { first, _ in first })
        let real = ordered.filter { $0.effectID > 0 }
        let pools = Set(mode.eligiblePoolIDs)
        var result: [(order: Int, issue: LoadoutIssue)] = []
        for issue in raw {
            let kind: String
            switch issue.kind {
            case .duplicate: kind = "duplicate"
            case .conflict: kind = "conflict"
            default: kind = "unavailable"
            }
            var affected: [Affix] = []
            for id in issue.effectIDs {
                guard let affix = byID[id], affix.effectID > 0, !affected.contains(where: { $0.effectID == id }) else { continue }
                affected.append(affix)
            }
            affected.sort { (position[$0.effectID] ?? 0) < (position[$1.effectID] ?? 0) }
            let title: String
            let detail: String
            switch kind {
            case "duplicate":
                title = LoadoutText.t("checkDuplicateTitle")
                detail = LoadoutText.f("checkDuplicateDetail", (affected.first ?? real.first)?.name ?? "")
            case "conflict":
                title = LoadoutText.t("checkConflictTitle")
                detail = LoadoutText.f("checkConflictDetail", affected.map(\.name).joined(separator: "、"))
            default:
                let outside = real.filter { Set($0.poolIDs).isDisjoint(with: pools) }
                if !outside.isEmpty {
                    affected = outside
                    title = LoadoutText.t("checkPoolTitle")
                    detail = LoadoutText.f("checkPoolDetail", outside.map(\.name).joined(separator: "、"))
                } else {
                    affected = real
                    title = LoadoutText.t("checkTemplateTitle")
                    detail = LoadoutText.f("checkTemplateDetail", real.map(\.name).joined(separator: "、"))
                }
            }
            let order = (kindOrder.firstIndex(of: kind) ?? 2) * 10 + (affected.first.flatMap { position[$0.effectID] } ?? 9)
            result.append((order, LoadoutIssue(kind: kind, title: title, detail: detail, effectIDs: affected.map(\.effectID))))
        }
        return result.enumerated().sorted { lhs, rhs in
            lhs.element.order == rhs.element.order ? lhs.offset < rhs.offset : lhs.element.order < rhs.element.order
        }.map(\.element.issue)
    }

    /// 深夜诅咒配对：与存档检查的深夜遗物审计（core.js auditRelic → auditDeepRelic、RelicAudit）同一口径、同一文案：
    /// 逐行「需诅咒 ⇔ 带诅咒」、诅咒须在诅咒池；另查涉及诅咒的重复与互斥（正面词条之间的已由 LegalityChecker 查过），
    /// 词条按出现顺序（先三行正面、再三行诅咒）列出。
    static func curseIssues(_ rows: [(row: Int, affix: Affix?, curse: Affix?)], poolID: Int) -> [LoadoutIssue] {
        var issues: [LoadoutIssue] = []
        for row in rows {
            let needsCurse = row.affix?.requiresCurse ?? false
            if needsCurse, row.curse == nil, let affix = row.affix {
                issues.append(LoadoutIssue(
                    kind: "curseMissing", title: LoadoutText.t("curseMissingTitle"),
                    detail: LoadoutText.f("curseMissingDetail", row.row + 1, affix.name), effectIDs: [affix.effectID]
                ))
            } else if !needsCurse, let curse = row.curse {
                issues.append(LoadoutIssue(
                    kind: "curseUnexpected", title: LoadoutText.t("curseUnexpectedTitle"),
                    detail: LoadoutText.f("curseUnexpectedDetail", row.row + 1, curse.name), effectIDs: [curse.effectID]
                ))
            }
        }
        for row in rows {
            guard let curse = row.curse, !(curse.isCurse && curse.poolIDs.contains(poolID)) else { continue }
            issues.append(LoadoutIssue(
                kind: "curseMismatch", title: LoadoutText.t("curseMismatchTitle"),
                detail: LoadoutText.f("curseMismatchDetail", row.row + 1, curse.name), effectIDs: [curse.effectID]
            ))
        }
        var all: [(affix: Affix, curse: Bool)] = []
        for row in rows { if let affix = row.affix { all.append((affix, false)) } }
        for row in rows { if let curse = row.curse { all.append((curse, true)) } }
        var dupIDs: [Int] = []
        for one in all where !dupIDs.contains(one.affix.effectID) {
            let same = all.filter { $0.affix.effectID == one.affix.effectID }
            if same.count > 1 && same.contains(where: \.curse) { dupIDs.append(one.affix.effectID) }
        }
        if !dupIDs.isEmpty {
            let names = dupIDs.compactMap { id in all.first { $0.affix.effectID == id }?.affix.name }
            issues.append(LoadoutIssue(
                kind: "duplicate", title: LoadoutText.t("curseDuplicateTitle"),
                detail: LoadoutText.f("curseDuplicateDetail", names.joined(separator: "、")), effectIDs: dupIDs
            ))
        }
        var conflicting: [Affix] = []
        for one in all where one.affix.compatibilityID != -1 {
            let group = all.filter { $0.affix.compatibilityID == one.affix.compatibilityID }
            guard group.count > 1, group.contains(where: \.curse) else { continue }
            if !conflicting.contains(where: { $0.effectID == one.affix.effectID }) { conflicting.append(one.affix) }
        }
        if !conflicting.isEmpty {
            issues.append(LoadoutIssue(
                kind: "conflict", title: LoadoutText.t("curseConflictTitle"),
                detail: LoadoutText.f("curseConflictDetail", conflicting.map(\.name).joined(separator: "、")),
                effectIDs: conflicting.map(\.effectID)
            ))
        }
        return issues
    }

    /// 深夜遗物负面词条池（与 core.js DEEP_CURSE_POOL_ID 相同）。
    public static let deepCursePoolID = 3_000_000
}

extension BuffAppliesRequirement {
    var hasAttackWeaponTypes: Bool { !attackWeaponTypes.isEmpty }
    var hasSubCategoriesAny: Bool { !subCategoriesAny.isEmpty }
    var hasAttackContexts: Bool { !attackContexts.isEmpty }
    /// requires 里至少有一个键（没有机读条件的 conditional 要用户确认）。
    var hasAnyKey: Bool {
        hand != nil || !attackWeaponTypes.isEmpty || attachedWeaponOnly || imbuedWeaponOnly || physicalType != nil
            || !attackContexts.isEmpty || !subCategoriesAny.isEmpty || !unknownKeys.isEmpty
    }
}

// MARK: - 计算器（绑定一个输出手段）

public struct LoadoutEvaluator: Sendable {
    public let index: BuffLoadoutIndex
    public let output: LoadoutOutput
    /// 按 buff 下标缓存的判定（不能进计算的条目为 nil）。
    let verdicts: [LoadoutVerdict?]
    let checkCache = RelicCheckCache()

    static let epsilon = 1e-9

    public init(index: BuffLoadoutIndex, output: LoadoutOutput) {
        self.index = index
        self.output = output
        verdicts = index.dataset.buffs.indices.map { offset in
            index.countsAsDamage[offset] ? index.verdict(forBuffAt: offset, output: output) : nil
        }
    }

    public func verdict(forBuffAt offset: Int) -> LoadoutVerdict? {
        verdicts.indices.contains(offset) ? verdicts[offset] : nil
    }

    var ranker: BuffRankerIndex { index.ranker }

    // MARK: 来源

    struct Source {
        let buffIndex: Int
        let column: LoadoutColumn
        let copies: Int
        let label: String
        let key: String
        var autoConfirm = false
        var isAuto = false
        var invalid = false
    }

    struct Merged {
        let buffIndex: Int
        let column: LoadoutColumn
        var copies: Int
        var labels: [String]
        var keys: [String]
        var autoConfirm: Bool
        var isAuto: Bool
        let invalid: Bool
    }

    struct Options {
        var strict = false
        var assumeAll = false
        var ownTier = false
        var ownVariant = false
    }

    func relicCheck(_ card: LoadoutRelicCard) -> LoadoutRelicCheck {
        checkCache.check(card) { index.relicCheck(card) }
    }

    /// 把配置展开成「来源 → 条目」（两端同一顺序）：武器词条（AttachEffect id 升序）→ 遗物格 → 护符格
    /// → 当前武器固有 → 不占槽位的栏里勾选的（spEffectId 升序）。
    func sources(_ loadout: BuffLoadout) -> (sources: [Source], checks: [LoadoutRelicCheck]) {
        var list: [Source] = []
        for id in loadout.weaponAffixCounts.keys.sorted() {
            let count = loadout.weaponAffixCounts[id] ?? 0
            guard count > 0, let item = index.weaponAffixItem(id), let info = item.weaponAffix,
                  info.isAvailable(in: loadout.mode) else { continue }
            let label = LoadoutText.weaponAffixLabel(info) + (count > 1 ? " ×\(count)" : "")
            for offset in item.buffIndices {
                list.append(Source(buffIndex: offset, column: .weaponAffix, copies: count, label: label, key: "wa:\(id)"))
            }
        }
        var checks: [LoadoutRelicCheck] = []
        let normalCount = index.slotRules.relicNormal
        for (cardIndex, card) in loadout.relicCards.enumerated() {
            let cardLabel = LoadoutText.relicCardTitle(cardIndex, normalCount: normalCount, deep: card.isDeepSlot)
            let check = relicCheck(card)
            checks.append(check)
            switch card.choice {
            case .empty:
                continue
            case .fixed(let fixedIndex):
                guard let item = index.fixedRelicItem(fixedIndex) else { continue }
                for offset in item.buffIndices {
                    list.append(Source(
                        buffIndex: offset, column: .relic, copies: 1, label: cardLabel + "：" + item.title, key: "relic:\(cardIndex)"
                    ))
                }
            case .custom:
                for (row, entry) in card.rows.enumerated() {
                    guard let id = entry.affixID, index.catalogAffixes[id] != nil else { continue }
                    let name = index.catalogAffixes[id]?.name ?? "#\(id)"
                    for offset in index.relicAffixItem(id)?.buffIndices ?? [] {
                        list.append(Source(
                            buffIndex: offset, column: .relic, copies: 1, label: cardLabel + "：" + name,
                            key: "relic:\(cardIndex):\(row)", invalid: check.status == .invalid
                        ))
                    }
                }
            }
        }
        for (slot, id) in loadout.accessories.enumerated() {
            guard let item = index.accessoryItem(id) else { continue }
            for offset in item.buffIndices {
                list.append(Source(buffIndex: offset, column: .accessory, copies: 1, label: item.title, key: "acc:\(slot)"))
            }
        }
        // 当前武器固有：自动列入，但不算用户确认——条件型默认未确认、叠层默认 0 层（notes.ranking ③）。
        let autoInnate = index.autoInnateIndices(forWeapon: output.outputClass == .skill ? output.weaponID : nil)
        let autoIDs = Set(autoInnate.map { index.dataset.buffs[$0].spEffectId })
        for offset in autoInnate where !loadout.excludedInnate.contains(index.dataset.buffs[offset].spEffectId) {
            list.append(Source(
                buffIndex: offset, column: .weaponInnate, copies: 1, label: LoadoutText.t("otherAutoInnate"),
                key: "innate:\(index.dataset.buffs[offset].spEffectId)", isAuto: true
            ))
        }
        for id in loadout.selectedBuffs.sorted() where !autoIDs.contains(id) {
            guard let offset = index.indexByID[id], index.listable[offset] else { continue }
            let buff = index.dataset.buffs[offset]
            let column = LoadoutColumn(sourceSlot: buff.sourceSlot)
            guard !column.isSlotted else { continue }
            let rowKey = buff.accumulatorLadder?.ladderID ?? id
            list.append(Source(
                buffIndex: offset, column: column, copies: 1, label: column.title, key: "other:\(rowKey)", autoConfirm: true
            ))
        }
        return (list, checks)
    }

    /// 同一个 spEffectId 从多处来的合并成一条（份数相加、来源并列）；不合法自组遗物里的单独成条（放在最后）。
    static func merge(_ sources: [Source]) -> [Merged] {
        var merged: [Merged] = []
        var position: [Int: Int] = [:]
        var invalid: [Merged] = []
        for source in sources {
            if source.invalid {
                invalid.append(Merged(
                    buffIndex: source.buffIndex, column: source.column, copies: source.copies, labels: [source.label],
                    keys: [source.key], autoConfirm: false, isAuto: false, invalid: true
                ))
                continue
            }
            if let at = position[source.buffIndex] {
                merged[at].copies += source.copies
                if !merged[at].labels.contains(source.label) { merged[at].labels.append(source.label) }
                if !merged[at].keys.contains(source.key) { merged[at].keys.append(source.key) }
                if source.autoConfirm { merged[at].autoConfirm = true }
                if !source.isAuto { merged[at].isAuto = false }
            } else {
                position[source.buffIndex] = merged.count
                merged.append(Merged(
                    buffIndex: source.buffIndex, column: source.column, copies: source.copies, labels: [source.label],
                    keys: [source.key], autoConfirm: source.autoConfirm, isAuto: source.isAuto, invalid: false
                ))
            }
        }
        return merged + invalid
    }

    // MARK: 单条评估

    struct Work {
        let merged: Merged
        let verdict: LoadoutVerdict
        var status: LoadoutLineStatus
        var reasons: [String]
        var notes: [String]
        var needs: [String]
        var confirmed: Bool
        var stacks: Int?
        var countedCopies: Int
        var channels: [Double]
        var flatChannels: [Double]
        var multiplier: Double
        var flat: Double
        var assumedOneStack: Bool
    }

    func weighted(_ table: [Double]) -> Double {
        BuffRankerIndex.effectiveMultiplier(channelMultiplier: table, shares: output.shares, fallback: 1)
    }

    func weightedFlat(_ table: [Double]) -> Double {
        var sum = 0.0
        var weight = 0.0
        for channel in SkillDamageChannel.allCases {
            let index = channel.rawValue
            guard output.shares.indices.contains(index), table.indices.contains(index) else { continue }
            let share = output.shares[index]
            guard share > 0 else { continue }
            sum += share * table[index]
            weight += share
        }
        return weight > 0 ? sum / weight : 0
    }

    /// 与 Windows 端 evaluateEntry 同一顺序：多档只留选中的一档 → 作用对象（含 selfAllyPair）→ 减益 → appliesTo
    /// → 累积阶梯选层 → 叠层层数 → 发动条件与手动确认 → 份数 → 对当前构成有没有增益。
    func evaluate(_ merged: Merged, loadout: BuffLoadout, options: Options) -> Work? {
        let offset = merged.buffIndex
        guard let verdict = verdicts[offset] else { return nil }
        let buff = index.dataset.buffs[offset]
        let copies = max(1, merged.copies)
        var raw: Int?
        var assumedOneStack = false
        if let input = buff.stackInput {
            var value = index.stacks(for: buff, loadout: loadout)
            if options.assumeAll {
                let soft = input.practicalMaxStacks.flatMap { $0 > 0 ? $0 : nil } ?? input.uiLabelMax.flatMap { $0 > 0 ? $0 : nil }
                if soft == nil && value <= 0 { assumedOneStack = true }
                value = max(value, min(soft ?? 1, input.maxAllowedStacks))
            }
            raw = value
        }
        let stacks = raw.map { value in buff.stackInput.map { min(value, $0.maxAllowedStacks) } ?? value }
        var work = Work(
            merged: merged, verdict: verdict, status: .counted, reasons: [], notes: verdict.notes, needs: [],
            confirmed: false, stacks: stacks, countedCopies: 1,
            channels: Array(repeating: 1, count: SkillDamageChannel.allCases.count),
            flatChannels: Array(repeating: 0, count: SkillDamageChannel.allCases.count),
            multiplier: 1, flat: 0, assumedOneStack: assumedOneStack
        )
        func finish(_ status: LoadoutLineStatus, _ reasons: [String]) -> Work {
            work.status = status
            work.reasons = reasons
            // 不计入的也给出「单独看这一条」的倍率，列表展示用（不进汇总）。
            let probe = index.tables(
                forBuffAt: offset, stacks: stacks, restricted: verdict.restrictedChannel, fraction: verdict.fraction, copies: 1
            )
            work.channels = probe.channels
            work.flatChannels = probe.flat
            work.multiplier = weighted(probe.channels)
            work.flat = output.hasComposition ? weightedFlat(probe.flat) : 0
            return work
        }
        if let variant = buff.affixVariant, !options.ownVariant {
            let members = index.variantOptions(variant.groupKey)
            let chosen = index.selectedVariant(variant.groupKey, loadout: loadout) ?? offset
            if chosen != offset {
                let tier = index.dataset.buffs[chosen].affixVariant?.variant ?? ((members.firstIndex(of: chosen) ?? 0) + 1)
                return finish(.variantOff, [LoadoutText.f("reasonVariantOff", max(members.count, 1), tier)])
            }
        }
        if buff.selfAllyPair?.role == "ally" { return finish(.no, [LoadoutText.t("reasonAllyPair")]) }
        if buff.target != "self" && buff.target != "ally" {
            return finish(.no, [LoadoutText.f("reasonTarget", buff.target)])
        }
        if buff.direction == "decrease" { return finish(.no, [LoadoutText.t("reasonDecrease")]) }
        switch verdict.state {
        case .no: return finish(.no, verdict.reasons)
        case .context: return finish(.context, verdict.reasons)
        default: break
        }
        var selectionConfirms = false
        if let ladder = buff.accumulatorLadder, !options.ownTier {
            let selected: Int?
            if options.assumeAll {
                selected = index.ladderTopTier(ladder.ladderID) ?? ladder.tier
            } else {
                let picked = loadout.ladderTiers[ladder.ladderID] ?? 0
                selected = index.ladderTierOptions(ladder.ladderID).contains(picked) ? picked : nil
            }
            guard let selected else { return finish(.tierOff, [LoadoutText.t("reasonTierNone")]) }
            if selected != ladder.tier { return finish(.tierOff, [LoadoutText.f("reasonTierOff", selected)]) }
            selectionConfirms = true
        } else if buff.accumulatorLadder != nil {
            selectionConfirms = true
        }
        if buff.stackInput != nil {
            guard let stacks, stacks > 0 else { return finish(.zeroStacks, [LoadoutText.t("reasonZeroStacks")]) }
            selectionConfirms = true
        }
        var needs = selectionConfirms ? [] : verdict.needs
        if !selectionConfirms, let note = verdict.activationNote { needs.insert(note, at: 0) }
        work.needs = needs
        if options.strict && (!needs.isEmpty || selectionConfirms) {
            return finish(.pending, needs.isEmpty ? [LoadoutText.t("fillNote")] : needs)
        }
        if !needs.isEmpty && !options.assumeAll {
            work.confirmed = loadout.confirmed.contains(buff.spEffectId) || merged.autoConfirm
            if !work.confirmed { return finish(.pending, needs) }
        }
        var countedCopies = 1
        if copies > 1 {
            if Self.copiesMultiply(buff) {
                countedCopies = copies
                work.notes.append(LoadoutText.f("noteCopiesStackSelf", copies))
            } else {
                work.notes.append(LoadoutText.f("noteCopiesSingle", copies))
            }
        }
        if let input = buff.stackInput, let stacks {
            work.notes += BuffLoadoutIndex.stackWarnings(input, raw: raw ?? stacks, stacks: stacks)
        }
        work.countedCopies = countedCopies
        let tables = index.tables(
            forBuffAt: offset, stacks: stacks, restricted: verdict.restrictedChannel, fraction: verdict.fraction,
            copies: countedCopies
        )
        work.channels = tables.channels
        work.flatChannels = tables.flat
        work.multiplier = weighted(tables.channels)
        work.flat = output.hasComposition ? weightedFlat(tables.flat) : 0
        if output.hasComposition && abs(work.multiplier - 1) <= Self.epsilon && work.flat <= Self.epsilon {
            work.status = .neutral
            work.reasons = [LoadoutText.t("reasonNeutral")]
            return work
        }
        work.status = .counted
        return work
    }

    /// 同一 spEffectId 多份：stackSelf 且按 ID 互斥（exclusiveScope=perSpEffect）的各份相乘；多档词条
    /// （exclusiveScope=affixVariant）同一词条装两件也只算一份（notes.affixVariant）。
    static func copiesMultiply(_ buff: BuffEntry) -> Bool {
        buff.stacking.spCategoryBehavior == "stackSelf"
            && (buff.stacking.exclusiveScope.isEmpty || buff.stacking.exclusiveScope == "perSpEffect")
    }

    // MARK: 去重与连乘

    /// 同键谁留下：两边都是 applyHighest 且 categoryPriority 不同 → 数值小的；否则有效倍率高的；
    /// 再比加算；再比 spEffectId 小的；完全并列时先出现的留下。
    static func prefers(_ candidate: Work, over current: Work, dataset: BuffDataset) -> Bool {
        let lhs = dataset.buffs[candidate.merged.buffIndex]
        let rhs = dataset.buffs[current.merged.buffIndex]
        if lhs.stacking.spCategoryBehavior == "applyHighest", rhs.stacking.spCategoryBehavior == "applyHighest",
           lhs.stacking.categoryPriority != rhs.stacking.categoryPriority {
            return lhs.stacking.categoryPriority < rhs.stacking.categoryPriority
        }
        if abs(candidate.multiplier - current.multiplier) > epsilon { return candidate.multiplier > current.multiplier }
        if abs(candidate.flat - current.flat) > epsilon { return candidate.flat > current.flat }
        return lhs.spEffectId < rhs.spEffectId
    }

    static func isPriorityWin(_ winner: Work, _ loser: Work, dataset: BuffDataset) -> Bool {
        let lhs = dataset.buffs[winner.merged.buffIndex].stacking
        let rhs = dataset.buffs[loser.merged.buffIndex].stacking
        return lhs.spCategoryBehavior == "applyHighest" && rhs.spCategoryBehavior == "applyHighest"
            && lhs.categoryPriority != rhs.categoryPriority
    }

    struct Resolved {
        var works: [Work]
        /// 去重后留下的（按第一次出现的顺序）。
        var winners: [Int]
        var total: Double
        var flat: Double
    }

    func resolve(_ merged: [Merged], loadout: BuffLoadout, options: Options) -> Resolved {
        var works: [Work] = []
        works.reserveCapacity(merged.count)
        for one in merged {
            guard var work = evaluate(one, loadout: loadout, options: options) else { continue }
            if one.invalid {
                work.status = .relicInvalid
                work.reasons = [LoadoutText.t("reasonRelicInvalid")]
            }
            works.append(work)
        }
        var winnerByKey: [String: Int] = [:]
        var order: [String] = []
        for (position, work) in works.enumerated() where work.status == .counted {
            let key = index.dataset.buffs[work.merged.buffIndex].stacking.exclusiveKey
            if let current = winnerByKey[key] {
                if Self.prefers(work, over: works[current], dataset: index.dataset) { winnerByKey[key] = position }
            } else {
                winnerByKey[key] = position
                order.append(key)
            }
        }
        for (position, work) in works.enumerated() where work.status == .counted {
            let key = index.dataset.buffs[work.merged.buffIndex].stacking.exclusiveKey
            guard let winner = winnerByKey[key], winner != position else { continue }
            let winnerBuff = index.dataset.buffs[works[winner].merged.buffIndex]
            let loserBuff = index.dataset.buffs[work.merged.buffIndex]
            works[position].status = .duplicate(by: winnerBuff.spEffectId)
            works[position].reasons = [Self.isPriorityWin(works[winner], work, dataset: index.dataset)
                ? LoadoutText.f(
                    "reasonDupPriority", winnerBuff.displayName, key,
                    winnerBuff.stacking.categoryPriority, loserBuff.stacking.categoryPriority
                )
                : LoadoutText.f("reasonDupKey", winnerBuff.displayName, key)]
        }
        let winners = order.compactMap { winnerByKey[$0] }
        var product = Array(repeating: 1.0, count: SkillDamageChannel.allCases.count)
        var flat = 0.0
        for position in winners {
            for channel in product.indices { product[channel] *= works[position].channels[channel] }
            flat += works[position].flat
        }
        return Resolved(works: works, winners: winners, total: weighted(product), flat: flat)
    }

    func line(_ work: Work, occurrence: Int) -> LoadoutLine {
        let buff = index.dataset.buffs[work.merged.buffIndex]
        var id = "\(buff.spEffectId)"
        if work.merged.invalid { id += "-invalid" }
        if occurrence > 0 { id += "-\(occurrence)" }
        return LoadoutLine(
            id: id, buffIndex: work.merged.buffIndex, spEffectId: buff.spEffectId, displayName: buff.displayName,
            column: work.merged.column, sources: work.merged.labels, sourceKeys: work.merged.keys,
            copies: work.merged.copies, countedCopies: work.countedCopies, exclusiveKey: buff.stacking.exclusiveKey,
            verdict: work.verdict, needs: work.needs, isConfirmed: work.confirmed, autoConfirm: work.merged.autoConfirm,
            isAuto: work.merged.isAuto, stacks: work.stacks, channelMultiplier: work.channels,
            multiplier: work.multiplier, weightedFlat: work.flat, status: work.status, reasons: work.reasons,
            notes: work.notes, activation: buff.activation, assumedOneStack: work.assumedOneStack
        )
    }

    func lines(_ resolved: Resolved) -> [LoadoutLine] {
        var seen: [String: Int] = [:]
        return resolved.works.map { work in
            let key = "\(work.merged.buffIndex)-\(work.merged.invalid)"
            let occurrence = seen[key, default: 0]
            seen[key] = occurrence + 1
            return line(work, occurrence: occurrence)
        }
    }

    // MARK: 整套配置

    public func evaluate(_ loadout: BuffLoadout) -> LoadoutEvaluation {
        let expanded = sources(loadout)
        let resolved = resolve(Self.merge(expanded.sources), loadout: loadout, options: Options())
        let allLines = lines(resolved)
        let rules = index.slotRules
        let mode = loadout.mode

        var subtotals: [LoadoutSummaryColumn: Double] = [:]
        for column in LoadoutSummaryColumn.allCases {
            var product = Array(repeating: 1.0, count: SkillDamageChannel.allCases.count)
            for position in resolved.winners where resolved.works[position].merged.column.summaryColumn == column {
                for channel in product.indices { product[channel] *= resolved.works[position].channels[channel] }
            }
            subtotals[column] = weighted(product)
        }

        var positive = 0
        var deepOnly = 0
        var curses = 0
        for (id, count) in loadout.weaponAffixCounts where count > 0 {
            guard let info = index.weaponAffixByID[id] else { continue }
            if info.isCurse {
                curses += count
            } else {
                positive += count
                if index.weaponAffixItem(id)?.badges.contains(LoadoutText.t("badges.deepOnly")) == true || info.deepOnlyPositive {
                    deepOnly += count
                }
            }
        }
        let weaponUsage = LoadoutSlotUsage(used: positive, cap: rules.weaponAffixCap(mode))
        let deepOnlyUsage = LoadoutSlotUsage(used: deepOnly, cap: rules.deepOnlyCap(mode))
        let curseUsage = LoadoutSlotUsage(used: curses, cap: rules.curseCap(mode))
        let relicUsage = LoadoutSlotUsage(used: loadout.relicCards.filter { !$0.isEmpty }.count, cap: rules.relicSlots(mode))
        let accessoryUsage = LoadoutSlotUsage(used: loadout.accessories.count, cap: rules.accessorySlots)

        var violations: [String] = []
        if weaponUsage.isOver {
            violations.append(LoadoutText.f("violationWeaponAffix", positive, mode.title, weaponUsage.cap))
        }
        if deepOnlyUsage.isOver {
            violations.append(mode == .normal
                ? LoadoutText.f("violationDeepOnlyInNormal", deepOnly)
                : LoadoutText.f("violationDeepOnly", deepOnly, deepOnlyUsage.cap))
        }
        if accessoryUsage.isOver {
            violations.append(LoadoutText.f("violationAccessory", accessoryUsage.used, accessoryUsage.cap))
        }
        if Set(loadout.accessories).count != loadout.accessories.count {
            violations.append(LoadoutText.t("violationAccessoryDuplicate"))
        }
        for (cardIndex, check) in expanded.checks.enumerated() where check.status == .invalid {
            let label = LoadoutText.relicCardTitle(cardIndex, normalCount: rules.relicNormal,
                                                   deep: loadout.relicCards[cardIndex].isDeepSlot)
            violations.append(LoadoutText.f("violationRelic", label, check.message))
        }

        return LoadoutEvaluation(
            total: resolved.total, lines: allLines, columnSubtotals: subtotals,
            weaponAffixUsage: weaponUsage, deepOnlyUsage: deepOnlyUsage, curseUsage: curseUsage,
            relicUsage: relicUsage, accessoryUsage: accessoryUsage, relicChecks: expanded.checks,
            warnings: warnings(resolved, allLines: allLines, loadout: loadout), violations: violations,
            weightedFlat: resolved.flat, hasComposition: output.hasComposition
        )
    }

    /// 提示（两端同一顺序）：互斥键压掉 → 同一效果多份只算一份 → stackSelf 多份相乘 → 同族不同档位相乘
    /// → 不同叠层阶梯相乘 → 遗物 exclusivityId → 同一件固定遗物装了两件。
    func warnings(_ resolved: Resolved, allLines: [LoadoutLine], loadout: BuffLoadout) -> [LoadoutWarning] {
        let dataset = index.dataset
        var warnings: [LoadoutWarning] = []
        var losersByKey: [String: [Int]] = [:]
        var keyOrder: [String] = []
        for (position, work) in resolved.works.enumerated() {
            guard case .duplicate = work.status else { continue }
            let key = dataset.buffs[work.merged.buffIndex].stacking.exclusiveKey
            if losersByKey[key] == nil { keyOrder.append(key) }
            losersByKey[key, default: []].append(position)
        }
        for key in keyOrder {
            let losers = losersByKey[key] ?? []
            guard let winner = resolved.winners.first(where: {
                dataset.buffs[resolved.works[$0].merged.buffIndex].stacking.exclusiveKey == key
            }) else { continue }
            let winnerName = dataset.buffs[resolved.works[winner].merged.buffIndex].displayName
            var names: [String] = []
            for position in losers {
                let name = dataset.buffs[resolved.works[position].merged.buffIndex].displayName
                if !names.contains(name) { names.append(name) }
            }
            if losers.allSatisfy({ Self.isPriorityWin(resolved.works[winner], resolved.works[$0], dataset: dataset) }) {
                warnings.append(LoadoutWarning(
                    kind: "priority", text: LoadoutText.f("warnPriority", key, winnerName, names.joined(separator: "、"))
                ))
            } else {
                var all = [winnerName]
                for name in names where !all.contains(name) { all.append(name) }
                warnings.append(LoadoutWarning(
                    kind: "duplicate",
                    text: LoadoutText.f("warnDuplicateKey", key, losers.count + 1, all.joined(separator: "、"))
                ))
            }
        }
        let winnerWorks = resolved.winners.map { resolved.works[$0] }
        let single = winnerWorks.filter { $0.merged.copies > 1 && $0.countedCopies == 1 }
        if !single.isEmpty {
            warnings.append(LoadoutWarning(kind: "copiesSingle", text: LoadoutText.f(
                "warnCopiesSingle", single.map { dataset.buffs[$0.merged.buffIndex].displayName }.joined(separator: "、")
            )))
        }
        let multiplied = winnerWorks.filter { $0.countedCopies > 1 }
        if !multiplied.isEmpty {
            warnings.append(LoadoutWarning(kind: "copiesStackSelf", text: LoadoutText.f(
                "warnCopiesStackSelf",
                multiplied.map { dataset.buffs[$0.merged.buffIndex].displayName + " ×\($0.countedCopies)" }.joined(separator: "、")
            )))
        }
        var familyOrder: [String] = []
        var byFamily: [String: [Work]] = [:]
        for work in winnerWorks {
            let family = dataset.buffs[work.merged.buffIndex].familyKey
            if byFamily[family] == nil { familyOrder.append(family) }
            byFamily[family, default: []].append(work)
        }
        for family in familyOrder {
            let group = byFamily[family] ?? []
            let keys = Set(group.map { dataset.buffs[$0.merged.buffIndex].stacking.exclusiveKey })
            guard keys.count >= 2, let first = group.first else { continue }
            warnings.append(LoadoutWarning(kind: "tiers", text: LoadoutText.f(
                "warnTiers", LoadoutText.familyName(dataset.buffs[first.merged.buffIndex].displayName),
                group.map { dataset.buffs[$0.merged.buffIndex].displayName }.joined(separator: "、")
            )))
        }
        let ladders = winnerWorks.filter { dataset.buffs[$0.merged.buffIndex].stackInput?.isLadder == true }
        if Set(ladders.map { dataset.buffs[$0.merged.buffIndex].stacking.exclusiveKey }).count >= 2 {
            warnings.append(LoadoutWarning(kind: "ladders", text: LoadoutText.f(
                "warnLadders", ladders.map { dataset.buffs[$0.merged.buffIndex].displayName }.joined(separator: "、")
            )))
        }
        var exclusivityOrder: [Int] = []
        var exclusivity: [Int: (attach: Set<Int>, names: [String])] = [:]
        for work in winnerWorks where work.merged.column == .relic {
            let buff = dataset.buffs[work.merged.buffIndex]
            for link in buff.relicAffixes where link.exclusivityId >= 0 {
                if exclusivity[link.exclusivityId] == nil {
                    exclusivityOrder.append(link.exclusivityId)
                    exclusivity[link.exclusivityId] = ([], [])
                }
                for attach in buff.relicAffixes.map(\.attachEffectId) { exclusivity[link.exclusivityId]?.attach.insert(attach) }
                if !(exclusivity[link.exclusivityId]?.names.contains(buff.displayName) ?? true) {
                    exclusivity[link.exclusivityId]?.names.append(buff.displayName)
                }
            }
        }
        for id in exclusivityOrder {
            guard let group = exclusivity[id], group.attach.count >= 2 else { continue }
            warnings.append(LoadoutWarning(
                kind: "exclusivity", text: LoadoutText.f("warnExclusivity", group.names.joined(separator: "、"), id)
            ))
        }
        var seenFixed: Set<Int> = []
        var reported: Set<Int> = []
        for card in loadout.relicCards {
            guard let fixedIndex = card.fixedIndex else { continue }
            if seenFixed.contains(fixedIndex), !reported.contains(fixedIndex) {
                reported.insert(fixedIndex)
                let name = index.fixedRelicItem(fixedIndex)?.title ?? "#\(fixedIndex)"
                warnings.append(LoadoutWarning(kind: "fixedDuplicate", text: LoadoutText.f("warnFixedDuplicate", name)))
            }
            seenFixed.insert(fixedIndex)
        }
        return warnings
    }

    /// 只算总倍率（「按推荐填满」的内层循环用；strict＝推荐口径）。
    public func total(of loadout: BuffLoadout, strict: Bool = false) -> Double {
        var options = Options()
        options.strict = strict
        return resolve(Self.merge(sources(loadout).sources), loadout: loadout, options: options).total
    }

    // MARK: 候选

    /// 某一栏的候选（单独选它时的倍率），按「生效的在前 → 当前倍率 → 条件成立时倍率 → ID」排序。
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
            items = index.innateItems(forWeapon: output.outputClass == .skill ? output.weaponID : nil)
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

    static func sortID(_ item: LoadoutItem) -> Int {
        switch item.kind {
        case .weaponAffix(let id), .relicAffix(let id), .accessory(let id), .buff(let id): return id
        case .fixedRelic: return item.fixedRelic?.relicID ?? 0
        }
    }

    func rank(_ candidates: [LoadoutCandidate]) -> [LoadoutCandidate] {
        candidates.sorted { lhs, rhs in
            if lhs.isApplicable != rhs.isApplicable { return lhs.isApplicable }
            if abs(lhs.multiplier - rhs.multiplier) > Self.epsilon { return lhs.multiplier > rhs.multiplier }
            if abs(lhs.potential - rhs.potential) > Self.epsilon { return lhs.potential > rhs.potential }
            return Self.sortID(lhs.item) < Self.sortID(rhs.item)
        }
    }

    static let stateRank: [String: Int] = [
        "counted": 0, "pending": 1, "zeroStacks": 2, "tierOff": 3, "context": 4, "neutral": 5, "duplicate": 6,
        "no": 7, "variantOff": 8, "relicInvalid": 9
    ]

    /// 一项候选单独放进来的评估（与 Windows 端 candidateScore 同一口径）。
    public func candidate(for item: LoadoutItem, loadout: BuffLoadout) -> LoadoutCandidate {
        let autoConfirm = !item.column.isSlotted && !item.isAutoInnate
        let merged = item.buffIndices.map { offset in
            Merged(buffIndex: offset, column: item.column, copies: 1, labels: [item.title], keys: [],
                   autoConfirm: autoConfirm, isAuto: item.isAutoInnate, invalid: false)
        }
        let current = resolve(merged, loadout: loadout, options: Options())
        var assume = Options()
        assume.assumeAll = true
        let potential = resolve(merged, loadout: loadout, options: assume)
        let currentLines = lines(current)
        var best: LoadoutLine?
        for line in currentLines {
            guard let known = best else { best = line; continue }
            if (Self.stateRank[line.status.key] ?? 99) < (Self.stateRank[known.status.key] ?? 99) { best = line }
        }
        let applicable = currentLines.contains { line in
            switch line.status {
            case .no, .context, .variantOff: return false
            default: return true
            }
        }
        let needs = currentLines.contains { line in
            switch line.status {
            case .pending, .zeroStacks, .tierOff: return true
            default: return false
            }
        }
        let oneStack = potential.works.contains { $0.assumedOneStack && $0.status == .counted }
        return LoadoutCandidate(
            item: item, lines: currentLines, multiplier: current.total, potential: potential.total,
            isApplicable: applicable,
            blockedReason: applicable ? nil : (best?.reasons.first ?? LoadoutText.t("verdictNoFallback")),
            needsConfirmation: needs, weightedFlat: potential.flat,
            potentialAssumesOneStack: oneStack && abs(potential.total - current.total) > Self.epsilon,
            status: best?.status ?? .no, reasons: best?.reasons ?? []
        )
    }

    // MARK: 全部增益一览

    /// 能进计算的条目逐条单独评估（两端同一口径）：「条件全部成立」——要确认的当成立，叠层取一局实际上限
    /// （没有就退『＋N』标签数，再没有 1 层），累积阶梯与多档词条按这一条自己的层／档；与当前配置无关。
    /// 生效的在前，按有效倍率降序，再按 spEffectId。
    public func overview() -> [LoadoutOverviewRow] {
        let empty = BuffLoadout(mode: .normal, rules: index.slotRules)
        var options = Options()
        options.assumeAll = true
        options.ownTier = true
        options.ownVariant = true
        var rows: [LoadoutOverviewRow] = []
        for offset in index.dataset.buffs.indices where index.listable[offset] {
            let buff = index.dataset.buffs[offset]
            let merged = Merged(buffIndex: offset, column: .other, copies: 1, labels: [], keys: [],
                                autoConfirm: false, isAuto: false, invalid: false)
            guard let work = evaluate(merged, loadout: empty, options: options) else { continue }
            let applicable: Bool
            switch work.status {
            case .no, .context: applicable = false
            default: applicable = true
            }
            let column: LoadoutColumn = LoadoutColumn(sourceSlot: buff.sourceSlot)
            rows.append(LoadoutOverviewRow(
                buffIndex: offset, spEffectId: buff.spEffectId, displayName: buff.displayName, column: column,
                verdict: work.verdict, status: work.status, reasons: work.reasons, notes: work.notes,
                multiplier: applicable ? work.multiplier : 1,
                assumesOneStack: applicable && work.assumedOneStack,
                activation: buff.activation, exclusiveKey: buff.stacking.exclusiveKey,
                searchKey: ranker.searchKey(at: offset), isApplicable: applicable
            ))
        }
        return rows.sorted { lhs, rhs in
            if lhs.isApplicable != rhs.isApplicable { return lhs.isApplicable }
            if abs(lhs.multiplier - rhs.multiplier) > Self.epsilon { return lhs.multiplier > rhs.multiplier }
            return lhs.spEffectId < rhs.spEffectId
        }
    }

    // MARK: 按推荐填满

    /// 这项候选在推荐口径下能不能贡献（有没有一条会计入）：没有的不必试（结果不变，只为快）。
    func strictCounts(_ item: LoadoutItem, loadout: BuffLoadout) -> Bool {
        var options = Options()
        options.strict = true
        return item.buffIndices.contains { offset in
            let merged = Merged(buffIndex: offset, column: item.column, copies: 1, labels: [], keys: [],
                                autoConfirm: false, isAuto: false, invalid: false)
            return evaluate(merged, loadout: loadout, options: options)?.status == .counted
        }
    }

    /// 两端同一口径：只填空槽、不改已选；顺序 武器词条 → 遗物逐格 → 护符；每一步取让（推荐口径的）总倍率
    /// 增幅最大的候选，增幅相同取 ID 小的，增幅 ≤ 1e-9 就停。推荐口径不计条件型、要确认的、叠层与累积阶梯。
    public func recommendedFill(_ loadout: BuffLoadout, weaponTypeFilter: Int?) -> BuffLoadout {
        var current = loadout
        guard output.hasComposition else { return current }
        var best = total(of: current, strict: true)
        let rules = index.slotRules
        let mode = current.mode

        // ① 武器词条：可以同一条多份（stackSelf 的各份相乘），受总上限与深夜专属上限约束。
        let weaponPool = index.weaponAffixItems.filter { item in
            guard let info = item.weaponAffix, info.isAvailable(in: mode), !info.isCurse else { return false }
            if let filter = weaponTypeFilter, !info.weaponTypes(in: mode).contains(filter) { return false }
            return strictCounts(item, loadout: current)
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
                let value = total(of: trial, strict: true)
                if value > (choice?.total ?? best) + Self.epsilon { choice = (info.attachEffectId, value) }
            }
            guard let choice else { break }
            current.weaponAffixCounts[choice.id, default: 0] += 1
            best = choice.total
        }

        // ② 遗物：逐个空格比较「最好的固定遗物」与「贪心自组」，分数相同取固定遗物。
        for cardIndex in current.relicCards.indices where current.relicCards[cardIndex].isEmpty {
            let deepSlot = current.relicCards[cardIndex].isDeepSlot
            var cardBest: (card: LoadoutRelicCard, total: Double)?
            let usedFixed = Set(current.relicCards.compactMap(\.fixedIndex))
            for item in index.fixedRelicItems {
                guard case .fixedRelic(let fixedIndex) = item.kind, !usedFixed.contains(fixedIndex),
                      (item.fixedRelic?.isDeepRelic ?? false) == deepSlot,
                      strictCounts(item, loadout: current) else { continue }
                var trial = current
                trial.relicCards[cardIndex] = LoadoutRelicCard(isDeepSlot: deepSlot, choice: .fixed(fixedIndex))
                let value = total(of: trial, strict: true)
                if value > (cardBest?.total ?? best) + Self.epsilon { cardBest = (trial.relicCards[cardIndex], value) }
            }
            if index.hasCatalog {
                let pool = index.relicAffixItems.filter { item in
                    guard let affix = item.relicAffix, index.isRelicAffixEligible(affix, deepSlot: deepSlot) else { return false }
                    return strictCounts(item, loadout: current)
                }
                var custom = LoadoutRelicCard(isDeepSlot: deepSlot, choice: .custom)
                var customTotal = best
                var rowsFilled = 0
                for row in 0..<3 where !pool.isEmpty {
                    var step: (card: LoadoutRelicCard, total: Double)?
                    for item in pool {
                        guard let affix = item.relicAffix, !custom.customAffixIDs.contains(affix.effectID) else { continue }
                        var trialCard = custom
                        trialCard.rows[row].affixID = affix.effectID
                        if deepSlot && affix.requiresCurse {
                            guard let curse = pickCurse(for: trialCard, row: row) else { continue }
                            trialCard.rows[row].curseID = curse
                        }
                        guard relicCheck(trialCard).status != .invalid else { continue }
                        var trial = current
                        trial.relicCards[cardIndex] = trialCard
                        let value = total(of: trial, strict: true)
                        if value > (step?.total ?? customTotal) + Self.epsilon { step = (trialCard, value) }
                    }
                    guard let step else { break }
                    custom = step.card
                    customTotal = step.total
                    rowsFilled += 1
                }
                if rowsFilled > 0, customTotal > (cardBest?.total ?? best) + Self.epsilon {
                    cardBest = (custom, customTotal)
                }
            }
            if let cardBest {
                current.relicCards[cardIndex] = cardBest.card
                best = cardBest.total
            }
        }

        // ③ 护符：不重复，取增幅最大的，按格位顺序补上。
        while current.accessories.count < rules.accessorySlots {
            var choice: (id: Int, total: Double)?
            for item in index.accessoryItems {
                guard case .accessory(let id) = item.kind, !current.accessories.contains(id),
                      strictCounts(item, loadout: current) else { continue }
                var trial = current
                trial.accessories.append(id)
                let value = total(of: trial, strict: true)
                if value > (choice?.total ?? best) + Self.epsilon { choice = (id, value) }
            }
            guard let choice else { break }
            current.accessories.append(choice.id)
            best = choice.total
        }
        return current
    }

    /// 给深夜遗物的这一行挑一条诅咒：诅咒池里按 effectId 升序，取第一条不会让这件遗物因它出问题的；配不上返回 nil。
    public func pickCurse(for card: LoadoutRelicCard, row: Int) -> Int? {
        for curse in index.curseAffixes {
            var trial = card
            trial.rows[row].curseID = curse.effectID
            let clash = relicCheck(trial).issues.contains { $0.effectIDs.contains(curse.effectID) }
            if !clash { return curse.effectID }
        }
        return nil
    }

    /// 给需诅咒的词条自动配诅咒（pickCurse），不需要诅咒的行清掉诅咒；普通遗物不带诅咒（与 Windows 端 autoAssignCurses 同法）。
    /// 逐行处理，已配了诅咒的行保留；后面的行挑诅咒时看得到前面刚配上的。
    public func autoAssignCurses(_ card: LoadoutRelicCard) -> LoadoutRelicCard {
        var next = card
        guard card.isDeepSlot else {
            for row in next.rows.indices { next.rows[row].curseID = nil }
            return next
        }
        for row in next.rows.indices {
            guard let id = next.rows[row].affixID, let affix = index.catalogAffixes[id], affix.requiresCurse else {
                next.rows[row].curseID = nil
                continue
            }
            if next.rows[row].curseID != nil { continue }
            next.rows[row].curseID = pickCurse(for: next, row: row)
        }
        return next
    }

    /// 自组遗物某一行换词条（与 Windows 端 withRelicAffix 同法）：这一行的旧诅咒先清掉，再 autoAssignCurses ——
    /// 深夜遗物选了需诅咒的词条就自动配一条（换成另一条需诅咒的词条时按新词条重配），不需要诅咒的行清掉诅咒；普通遗物不带诅咒。
    public func withRelicAffix(_ card: LoadoutRelicCard, row: Int, affixID: Int?) -> LoadoutRelicCard {
        guard card.rows.indices.contains(row) else { return card }
        var next = card
        next.choice = .custom
        next.rows[row].affixID = affixID
        next.rows[row].curseID = nil
        return autoAssignCurses(next)
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

/// 自组遗物检查的缓存（「按推荐填满」会对同一张卡反复检查）。
final class RelicCheckCache: @unchecked Sendable {
    private var storage: [LoadoutRelicCard: LoadoutRelicCheck] = [:]
    private let lock = NSLock()

    func check(_ card: LoadoutRelicCard, compute: () -> LoadoutRelicCheck) -> LoadoutRelicCheck {
        lock.lock()
        if let hit = storage[card] {
            lock.unlock()
            return hit
        }
        lock.unlock()
        let value = compute()
        lock.lock()
        if storage.count > 5000 { storage.removeAll() }
        storage[card] = value
        lock.unlock()
        return value
    }
}

// MARK: - 文案常量表（两端对照：与 Windows 端 ranker.js 的 TEXT 按点号路径逐键同文）

public enum LoadoutText {
    /// 配置部分的全部文案。带 {0} {1} 的是格式串，由 `f` / `fmt` 按位置替换（缺的参数替换成空串）。
    /// 与 windows/renderer/pages/ranker.js 的 TEXT（按点号路径展开）逐键逐字相同，两端自检校验同一个摘要。
    public static let table: [String: String] = [
        "accEffectCount": "{0} 条效果",
        "accFull": "护符已满",
        "accIntro": "最多 {0} 个，同一护符不能装两个（护符格数来自游戏文本与用户说明，参数表没有字段）",
        "accPlaceholder": "选择护符…",
        "accRemove": "移除",
        "accSlotLabel": "护符 {0}",
        "accUsedElsewhere": "（已装备）",
        "activationNeed.activated": "发动型：只在技艺／绝招／战技发动期间存在",
        "activationNeed.conditional": "条件型：需满足发动条件（残血、双手持、命中触发…）",
        "activationNeed.equipped": "条件型：装备中有 {0} 把以上{1}（与出手的武器无关）",
        "badges.accLadder": "累积阶梯",
        "badges.activated": "发动型",
        "badges.ally": "队友增益",
        "badges.allyPair": "队友那一行",
        "badges.autoInnate": "当前武器固有，自动列入",
        "badges.blessing": "武器赐福",
        "badges.conditional": "条件型",
        "badges.copies": "按份数叠加",
        "badges.currentSkill": "当前战技",
        "badges.curse": "诅咒",
        "badges.deepOnly": "深夜专属",
        "badges.fixed": "固定词条",
        "badges.inferredInnate": "行名推断",
        "badges.inferredSource": "来源为推断",
        "badges.inferredTiers": "参数推断，未实测",
        "badges.ladder": "叠层",
        "badges.outsideWeaponType": "不在当前武器类别",
        "badges.potency": "档位{0}",
        "badges.requiresCurse": "需诅咒",
        "badges.variant": "按武器类别取一档",
        "brief.activation": "activation 不是 passive 的条目（条件型／发动型）与需要手动确认的条件，默认不计入：占槽位的栏（武器词条、遗物、护符、当前武器固有）放进来≠条件成立，要单独勾选「条件成立」；不占槽位的「其它增益」栏里勾选本身就是确认；叠层填层数、累积阶梯选层同样算确认。",
        "brief.affixVariant": "同一遗物词条下挂多档的（数据 affixVariant，{0} 组 {1} 条，例如「出击时的武器，附加…」的 4 档）：游戏按出击武器的类别只生效一档、不能相乘；参数里查不到武器类别到档位的映射，本页默认按第 1 档计算，让你按出击武器选档。",
        "brief.appliesTo": "生效判定一律按数据的 appliesTo：战技（含战技射出的子弹段）看 skill、魔法看 sorcery、祷告看 incantation。conditional 的机读条件里，持武器的手、出手武器类别（法术按施法器：魔法＝手杖、祷告＝圣印记）、物理攻击类型按当前输出自动判定；子类别按 attackIndex 对所选战技／法术判定；攻击情境用上方的情境勾选；附魔武器限定、需同时使用道具等无法自动判定的要手动确认。",
        "brief.deepWeapon": "深夜诅咒武器每把 2 条正面词条，其中深夜专属正面词条最多 1 条（6 把最多 {0} 条，按 weaponAffixDeepOnlyPositive 计数）；负面诅咒另按每把 1 条算，不占这个名额，也不计增伤。同一把武器的两条正面词条能否相同（或同一词条的不同档位），参数表里查不到（duplicateWithinWeapon.status={1}），本页只校验总数与深夜专属上限，不按把分配。",
        "brief.direction": "减益不计入：direction=decrease 的 {0} 条（附加异常时的武器伤害惩罚、降低敌人攻击力等）按 notes.ranking 第②步一律不进乘积；mixed（有增有减，例如附加属性时物理减、属性加）照常计入。",
        "brief.equipped": "「装备三把以上类别为 X 的武器」判的是装备中的数量，与出手的武器无关，对战技与法术都生效；「提升 X 的攻击力」只对用 X 发动的攻击生效（notes.userQuestions.Q3）。",
        "brief.fill": "「按推荐填满」只填空着的槽位，顺序是武器词条 → 遗物逐格（最好的固定遗物与贪心自组的合法遗物比较，分数相同取固定遗物）→ 护符；每一步都按「加进去之后的总倍率」取增幅最大的候选，增幅相同取 ID 小的；只算不用确认、不用填层数或选层就会计入的条目，不选条件型。",
        "brief.formula": "总倍率＝按互斥键去重后，全部计入条目在每个伤害类型上的倍率连乘，再按伤害构成占比加权；攻击力倍率层与最终伤害倍率层相乘，物理子类型倍率只乘对应那一部分；各栏小计同法只算本栏；攻击力加算（点数）只展示、不进连乘。",
        "brief.innate": "当前武器的固有效果自动列入「其它增益 · 武器固有」：被动的直接计入；条件型默认不计入，要勾选「条件成立」；叠层类默认 0 层，要填层数（notes.ranking 第③步：自动带入不算用户确认）。其它武器的固有效果可以手动勾选。",
        "brief.partial": "子类别只有部分段命中（requires.subCategoriesAny）时按近似加权：每个伤害类型取 1＋(倍率−1)×命中段占比，占比＝attackIndex 里所选战技／法术带该子类别的段数÷总段数；attackIndex 只给整招各子类别组合的段数、没有逐段对应，所以占比不随上方的分段勾选变化。",
        "brief.relic": "遗物：普通遗物按「普通 1.03」口径（三条不重复、compatibilityId 两两不同、能分配到槽池模板）；深夜遗物按「深夜正面」口径，并要求 requiresCurse 的词条各配一条负面诅咒池（{0}）里的诅咒（与存档检查的深夜遗物审计同一规则、同一文案）。不足三条时用可落任一槽池、不参与互斥的占位词条补足后再检查。官方固定遗物整件计入；随整件带进来的条件型效果要手动确认。",
        "brief.runStack": "叠层：{0}。同一阶梯各层互斥、只取当前层；不同阶梯（封印监牢、黑夜入侵者等）按 categoryPriority 判为互不顶替、可以同时生效——参数推断，未实测。",
        "brief.skillAttack": "「提升战技攻击力」类（子类别 {0}）只作用于战技（含战技的子弹段），不作用于法术与普通攻击；法术吃到的「提升攻击力（XX・战技）」是战技发动后给自己的全伤害增益（sourceSlot=weaponSkill），名字里的「战技」是来源（notes.userQuestions.Q1）。",
        "brief.stacking": "叠加按 stacking.exclusiveKey：同键只计一份（applyHighest 按 categoryPriority 取数值小的，其余取有效倍率高的，再相同取 spEffectId 小的），不同键相乘。同一个 spEffectId 从多处各拿一份时，spCategory=10（stackSelf）且按 ID 互斥的各份相乘，其余只算一份（多档词条同一词条装两件也只算一份）——都是按 SpEffectParam 参数结构推断，未经木桩实测（stackingRules）。",
        "brief.target": "作用对象按 notes.ranking 第①步只保留 self 与 ally（ally＝自己与／或附近队友）；同一战技成对的 Self／Allies 两行（selfAllyPair）算施放者自己时只计 Self 那一行，Allies 那一行只在队友施放时计入。",
        "brief.throwInferred": "appliesTo 对致命一击（throw）的判定是推断，而且与 Paramdex 对 throwAttackParamChange 的字面说明相反（notes.appliesTo）；本页的输出只有战技与法术，不涉及致命一击。",
        "brief.tiers": "同一词条的不同档位（＋1／＋2、档位1／2／3）是不同的 SpEffect、各有自己的互斥键，本页按相乘计算——参数推断，未实测。",
        "briefHeading": "口径说明",
        "briefIntro": "数据集 notes.ranking / stackingRules / notes.userQuestions 的结论简述",
        "briefStack.copies": "每份 ×{0}、N 份按 N 次方相乘，参数表无上限",
        "briefStack.item": "{0}：{1}",
        "briefStack.ladder": "第 n 层取第 n 档（每层约 ×{0}），参数表 {1} 层",
        "briefStack.practical": "，一局实际上限 {0} 层（×{1}）",
        "briefStack.separator": "；",
        "briefStack.unit": "（层数＝{0}）",
        "cardControlsHint": "条件型效果请在下方勾选「条件成立」；叠层效果在这里填层数、累积阶梯在这里选层、按武器类别取一档的词条在这里选档",
        "characterKinds.Passive": "被动",
        "characterKinds.Skill": "技艺",
        "characterKinds.Ultimate": "绝招",
        "characterNames.Duchess": "女爵",
        "characterNames.Executor": "执行者",
        "characterNames.Guardian": "守护者",
        "characterNames.Ironeye": "铁之眼",
        "characterNames.Raider": "无赖",
        "characterNames.Recluse": "隐士",
        "characterNames.Revenant": "复仇者",
        "characterNames.Scholar": "学者",
        "characterNames.Undertaker": "送葬者",
        "characterNames.Wylder": "追踪者",
        "characterOther": "其他角色",
        "checkConflictDetail": "{0} 不能同时出现",
        "checkConflictTitle": "同一互斥池",
        "checkDuplicateDetail": "同一个效果不能在一件遗物上出现两次：{0}",
        "checkDuplicateTitle": "词条重复",
        "checkPoolDetail": "{0} 不在当前校验模式的候选词条池",
        "checkPoolTitle": "不在当前出货池",
        "checkTemplateDetail": "{0} 无法分配到任一合法三词条槽模板",
        "checkTemplateTitle": "不符合当前槽池模板",
        "clearButton": "清空配置",
        "columns.accessory": "护符",
        "columns.other": "其它增益",
        "columns.relic": "遗物",
        "columns.weaponAffix": "局内武器词条",
        "contextsLabel": "攻击情境（勾选后，只在该情境成立的倍率才计入）",
        "curseConflictDetail": "同一互斥池的词条不能同时出现：{0}",
        "curseConflictTitle": "互斥词条同时出现",
        "curseDuplicateDetail": "同一词条在一件遗物上重复出现：{0}",
        "curseDuplicateTitle": "词条重复",
        "curseMismatchDetail": "第 {0} 行的负面词条不在诅咒池：{1}",
        "curseMismatchTitle": "负面词条不在诅咒池",
        "curseMissingDetail": "第 {0} 行的正面词条需要配对负面词条：{1}",
        "curseMissingTitle": "需诅咒的词条缺少负面词条",
        "cursePairingDetail": "已按存档检查的深夜遗物审计规则逐行核对：需要诅咒的词条各配一条诅咒池（{0}）里的诅咒，不需要的不带；自组遗物按 3 格计，不涉及具体遗物 ID",
        "cursePairingTitle": "诅咒配对已校验",
        "curseUnexpectedDetail": "第 {0} 行的正面词条不需要负面词条，却携带负面词条：{1}",
        "curseUnexpectedTitle": "多余的负面词条",
        "detailActivation": "发动条件",
        "detailDesc": "说明",
        "detailKey": "互斥键",
        "detailStatus": "状态",
        "fillButton": "按推荐填满",
        "fillDone": "已按推荐填入 {0} 项",
        "fillNote": "只填空着的槽位：先局内武器词条，再逐格遗物（最好的固定遗物与贪心自组的合法遗物比较，同分取固定遗物），最后护符；每一步取让总倍率增幅最大的候选（同增幅取 ID 小的），不选条件型、叠层与累积阶梯，已选的一律保留",
        "fillNothing": "没有可填的空槽或可用条目",
        "flatInline": "攻击力 {0}",
        "goodsFallback": "道具 #{0}",
        "groupAutoInnate": "当前武器自带（自动列入）",
        "groupOtherInnate": "其它武器的固有效果（手动勾选）",
        "groupUnknownSkill": "未标明战技",
        "hand.1": "右手",
        "hand.2": "左手",
        "handHelp": "按增益的 appliesToDetail.requires.hand 判定当前手（只作用于另一只手的增益不计入），默认按右手计算",
        "handLabel": "武器槽",
        "innateRemove": "不计入",
        "innateRestore": "计入",
        "ladderTierCount": "共 {0} 层，选中后选层",
        "loadoutMissing": "增益数据缺少配置页需要的字段（slotRules／appliesTo，需 schemaVersion 6）",
        "modeTrimmed": "切到常规：已去掉 {0} 条深夜专属／超出常规上限的武器词条，深夜遗物格已清空",
        "noData": "数据未内置",
        "noteCopiesSingle": "装了 {0} 份：同一 spEffectId 多份只算一份（stackingRules：只有按 ID 互斥的 stackSelf 才各份相乘）",
        "noteCopiesStackSelf": "stackSelf：{0} 份各自相乘（stackingRules 第 2 条，参数推断，未实测）",
        "optionInactive": "（不生效）",
        "optionPotential": "（{0}，条件成立时 {1}）",
        "optionScore": "（{0}）",
        "otherAutoInnate": "当前武器固有，自动列入",
        "otherEmpty": "这一组里没有能增伤的条目",
        "otherGroups.character": "角色",
        "otherGroups.consumable": "道具",
        "otherGroups.other": "其它",
        "otherGroups.permanent": "永久强化",
        "otherGroups.runStack": "局内叠层",
        "otherGroups.spellBuff": "增益法术",
        "otherGroups.weaponInnate": "武器固有",
        "otherGroups.weaponSkill": "战技自增益",
        "otherInnateHint": "当前武器的固有效果自动列入（取消勾选可排除）：被动的直接计入；条件型默认不计入，要勾选「条件成立」；叠层类默认 0 层，要填层数",
        "otherInnateNoWeapon": "法术没有出手武器，这里只有需手动勾选的固有效果",
        "otherIntro": "不占槽位，按需勾选；勾选即视为条件成立，叠层类勾选后先填一局实际上限、累积阶梯先选最高层（都可以改）",
        "otherSearch": "搜索增益名称、来源或 SpEffect 行号",
        "outputClass.incantation": "祷告",
        "outputClass.skill": "战技",
        "outputClass.sorcery": "魔法",
        "overviewCount": "共 {0} 条（每条单独按「条件全部成立」算：叠层取一局实际上限、没有上限的按 1 层，累积阶梯与多档词条按每一层／每一档自己算；未去重、未连乘，只供查阅）。",
        "overviewMore": "再显示 {0} 条（剩余 {1} 条）",
        "overviewNext": "下一页",
        "overviewNoMatch": "没有匹配的条目",
        "overviewOneStack": "按 1 层",
        "overviewOneStackHelp": "叠层条目没有实际上限（practicalMaxStacks／uiLabelMax 都没有），一览只按 1 层算；在栏里填层数后按实际层数",
        "overviewPage": "第 {0} / {1} 页 · 每页 {2} 条",
        "overviewPill": "查阅用",
        "overviewPrev": "上一页",
        "overviewSearch": "搜索增益名称、来源或 Paramdex 行名",
        "overviewTitle": "全部增益一览",
        "pageSubtitle": "选一个战技／法术，再自己组一套局内配置：武器词条、遗物、护符与其它增益，看总增伤",
        "pageTitle": "增伤排名",
        "pickerDone": "完成",
        "potentialOneStack": "条件成立时（未设上限，按 1 层）{0}",
        "potentialText": "条件成立时 {0}",
        "questionsTitle": "数据集的问答（notes.userQuestions，{0} 条）",
        "reasonAllyPair": "同一战技的队友那一行（selfAllyPair.role=ally）：施放者自己吃不到，只在队友施放、落到自己身上时计入",
        "reasonDecrease": "direction=decrease：这是减益（降低自己的伤害、降低敌人攻击力等），按 notes.ranking 第②步只保留 increase／mixed，不计入增伤",
        "reasonDupKey": "与「{0}」同属互斥键 {1}，同键只取一份（取有效倍率高的）",
        "reasonDupPriority": "与「{0}」同属互斥键 {1}（applyHighest）：按 categoryPriority 取数值小的那份（{2} 优先于 {3}），本条被压掉",
        "reasonNeutral": "对当前伤害构成没有增益（倍率 ×1、没有正的攻击力加算）",
        "reasonNoDamage": "不含计入伤害的倍率字段",
        "reasonRelicInvalid": "所在的自组遗物不合法，整件不计入",
        "reasonTarget": "作用对象不是自己（target={0}）",
        "reasonTierNone": "累积阶梯还没选层（选层即视为条件成立）",
        "reasonTierOff": "累积阶梯只算选中的那一层（当前选第 {0} 层）",
        "reasonVariantOff": "同一遗物词条的 {0} 档按出击武器类别只生效一档（数据 affixVariant），当前按第 {1} 档计算",
        "reasonZeroStacks": "层数为 0，不计入（填层数即视为条件成立）",
        "relicAffixEmpty": "（空）",
        "relicAffixPickerHint": "按对当前输出的有效倍率排序；红字＝选上后这件遗物不合法的原因",
        "relicCardDeep": "深夜遗物 {0}",
        "relicCardNormal": "普通遗物 {0}",
        "relicColors.0": "红",
        "relicColors.1": "蓝",
        "relicColors.2": "黄",
        "relicColors.3": "绿",
        "relicColors.4": "白",
        "relicCountedLabel": "计入情况（非增伤词条只显示不计入）",
        "relicCurseLabel": "诅咒（不计增伤，但要占位）",
        "relicCurseNote": "诅咒只占位，不计增伤",
        "relicCursePlaceholder": "（未选诅咒）",
        "relicCurseSearch": "搜索诅咒",
        "relicEffectsLabel": "词条",
        "relicEmpty": "未选择词条",
        "relicFixedNone": "数据未内置深夜固定遗物，深夜遗物格只能自组",
        "relicFixedPlaceholder": "选择官方固定词条遗物…",
        "relicFixedSearch": "搜索固定遗物名称或词条",
        "relicFixedSubtitle": "{0}色 · 遗物 #{1}",
        "relicFixedUsedElsewhere": "（已在别的遗物格）",
        "relicFixedValid": "官方固定词条遗物：整件按数据的 spEffectIds 计入，非增伤词条只显示",
        "relicIntro": "常规 {0} 个普通遗物格；深夜另加 {1} 个深夜遗物格。每格二选一：官方固定词条遗物整件选入，或按词条检查页的规则自组不超过 3 条（普通遗物用「普通 1.03」口径，深夜遗物用「深夜正面」口径＋诅咒配对，实时检查合法性）",
        "relicInvalid": "该遗物组合不合法",
        "relicNoCatalog": "词条库未载入，无法自组遗物",
        "relicNonDamage": "不计增伤",
        "relicPartial": "预检通过：已选 {0} 条，其余 {1} 条可填任意不增伤、不冲突的合法词条",
        "relicPickAffix": "选择词条…",
        "relicPlaceholderAffix": "其余不增伤词条",
        "relicRemove": "移除",
        "relicRowLabel": "词条 {0}",
        "relicSearch": "搜索词条名称、分类或 ID",
        "relicStatus.empty": "空",
        "relicStatus.fixed": "固定遗物",
        "relicStatus.invalid": "不合法",
        "relicStatus.partial": "预检通过",
        "relicStatus.valid": "合法",
        "relicType.custom": "自组",
        "relicType.empty": "空",
        "relicType.fixed": "固定遗物",
        "relicTypeAria": "遗物来源",
        "relicUnknownEffectDetail": "以下词条 ID 不在词条索引中：{0}",
        "relicUnknownEffectTitle": "存在未知词条 ID",
        "relicUnnamedEffect": "词条 #{0}",
        "relicValidDeep": "合法：正面词条按「深夜正面」口径通过，诅咒配对已逐行校验",
        "relicValidNormal": "合法：三条词条按「普通 1.03」口径通过",
        "requireAttached": "只对带这条词条的那把武器生效，需确认",
        "requireContext": "只在「{0}」时成立（在「攻击情境」里勾选）",
        "requireGoods": "需同时使用道具：{0}，需确认",
        "requireHand": "只作用于{0}武器（当前为{1}）",
        "requireImbued": "只对附加了属性的那把武器生效（附魔／油脂／出击时附加），需确认",
        "requireManual": "数据判定为有条件生效：{0}，需确认",
        "requirePhysical": "只作用于{0}攻击",
        "requirePhysicalFail": "只作用于{0}攻击（当前构成里没有这一类）",
        "requireSubsAll": "所选{0}的 {1} 段都带子类别 {2}",
        "requireSubsFail": "所选{0}的命中段都不带子类别 {1}",
        "requireSubsPartial": "所选{0}只有 {1}/{2} 段带子类别 {3}：按 1＋(倍率−1)×{1}/{2} 近似加权（段数取 attackIndex 对整招的统计，与上方分段勾选无关）",
        "requireSubsUnknown": "attackIndex 里没有所选{0}，子类别 {1} 无法自动判定，需确认",
        "requireUnknown": "数据要求 {0}，本页无法自动判定，需确认",
        "requireWepType": "只对用{0}发动的攻击生效（当前为{1}）",
        "requireWepTypeNoWeapon": "只对用{0}发动的攻击生效（当前没有选武器）",
        "runMode.deep": "深夜",
        "runMode.normal": "常规",
        "runModeAria": "常规或深夜",
        "runModeHint": "常规：武器词条最多 {0} 条、遗物 {1} 件；深夜：武器词条最多 {2} 条（其中深夜专属最多 {3} 条）、遗物 {4} 件（普通 {5} ＋ 深夜 {6}）",
        "runModeLabel": "出击模式",
        "schemaTooOld": "增益数据是 schemaVersion {0}：本页按 v6 的 appliesTo / slotRules / exclusiveKey 组配置，旧数据缺这些字段，结果不可信",
        "searchPlaceholder": "搜索名称",
        "selectUse": "选用",
        "showInactive": "显示不生效项",
        "showInactiveHelp": "appliesTo 判为不生效（或条件不满足）的条目默认隐藏；打开后虚化显示并写明原因",
        "spellHandNote": "施法器同样握在左右手之一：按 appliesToDetail.requires.hand 判定，只作用于另一只手的增益不计入；武器词条栏按施法器（魔法＝手杖、祷告＝圣印记）的类别过滤。",
        "stackHintCopies": "每份 ×{0}，N 份按 ×{0}^N 相乘（参数表无上限）",
        "stackHintGrace": "本局新发现的赐福数",
        "stackHintLabel": "游戏文本备有『＋1』到『＋{0}』的标签",
        "stackHintLadder": "阶梯：第 n 层取 tierMultipliers[n-1]，参数表共 {0} 层，各层互斥只取当前层",
        "stackHintPractical": "一局实际最多 {0} 层，可以填更多但会提示",
        "stackLabel": "层数",
        "stackLabelCopies": "份数",
        "stackOverCeiling": "份数按上限 {0} 计算",
        "stackOverLabel": "游戏文本只备到＋{0}，更多层数按同一倍率外推（未实测）",
        "stackOverParam": "参数表只有 {0} 层，按第 {0} 层计算",
        "stackOverPractical": "填了 {0} 层，超过一局实际能叠到的 {1} 层（{2}）",
        "states.context": "需勾选攻击情境",
        "states.counted": "计入",
        "states.duplicate": "同键不叠加",
        "states.neutral": "对当前构成无增益",
        "states.no": "不生效",
        "states.noDamage": "不含伤害倍率",
        "states.pending": "条件未确认",
        "states.relicInvalid": "遗物不合法",
        "states.tierOff": "未选的层",
        "states.variantOff": "未选的档",
        "states.zeroStacks": "层数为 0",
        "stepDown": "减少",
        "stepUp": "增加",
        "stepperAria": "数量",
        "summaryColumnNote": "总倍率＝按互斥键去重后逐伤害类型连乘，再按伤害构成占比加权；各栏小计只算本栏（同法），不一定相乘等于总倍率",
        "summaryContribution": "贡献",
        "summaryCount": "{0} 条",
        "summaryCounted": "当前生效条目（{0}）",
        "summaryEmpty": "还没有放入任何增益。可以在下面各栏里挑选，或点「按推荐填满」。",
        "summaryFlat": "另有攻击力加算",
        "summaryFlatNote": "攻击力加算（点数）没有绝对攻击力就折不成倍率，只按占比加权展示，不进连乘",
        "summaryGain": "相对提升",
        "summaryHeading": "汇总",
        "summaryHiddenNo": "另有 {0} 条对当前输出不生效（打开「{1}」查看原因）。",
        "summaryNoComposition": "先勾选至少一段带伤害的命中，才能计算倍率",
        "summaryRemove": "移除",
        "summarySubtotals": "各栏小计（本栏单独计算）",
        "summaryTick": "条件成立",
        "summaryTickHelp": "条件型：勾上表示你确认这个条件在出手时成立，才计入总倍率",
        "summaryTotal": "总倍率",
        "summaryUncounted": "选了但未计入（{0} 条）",
        "tierLabel": "第 {0} 层",
        "tierLabelThreshold": "第 {0} 层（累积 {1}）",
        "tierNone": "不计",
        "tierSelectLabel": "层",
        "usageAccessory": "护符",
        "usageDeepOnly": "深夜专属",
        "usageRelic": "遗物",
        "usageWeaponAffix": "武器词条",
        "variantLabel": "档",
        "variantNoMapping": "参数里查不到「出击武器类别 → 档位」的映射（词条只有一个按武器派发的行，没有任何列指向这几档），默认按第 1 档计算，请按出击武器自行选档",
        "variantOption": "第 {0} 档{1}",
        "variantRates": "（{0}）",
        "verdict.conditionalMet": "生效（条件已满足）",
        "verdict.needsUser": "条件生效",
        "verdict.no": "不生效",
        "verdict.partial": "部分段生效",
        "verdict.yes": "生效",
        "verdictMissing": "数据未给出这类输出的 appliesTo，按不生效处理",
        "verdictNoFallback": "数据判定对这类输出不生效",
        "violationAccessory": "护符 {0} 个，超过上限 {1} 个",
        "violationAccessoryDuplicate": "同一护符不能装两个",
        "violationDeepOnly": "深夜专属正面词条 {0} 条，超过上限 {1} 条（每把武器最多 1 条）",
        "violationDeepOnlyInNormal": "常规模式没有深夜专属词条（当前选了 {0} 条）",
        "violationRelic": "{0}：{1}",
        "violationWeaponAffix": "局内武器词条 {0} 条，超过{1}上限 {2} 条",
        "waCapReached": "已达上限",
        "waCopiesHint": "同一条词条装多份：按 ID 互斥的 stackSelf 各份相乘，其余只算一份（stackingRules 第 2 条，参数推断，未实测）",
        "waDeepOnlyCapReached": "深夜专属已达上限",
        "waDeepOnlyUsage": "深夜专属 {0} / {1}",
        "waEmpty": "当前筛选下没有能增伤的武器词条",
        "waFilterAll": "全部类别",
        "waFilterAria": "武器类别过滤",
        "waFilterNone": "当前输出没有武器类别，显示全部",
        "waFilterWeapon": "当前武器类别（{0}）",
        "waIntro": "局内捡到的武器随机带的词条；{0} 把武器的词条全局生效。按对当前输出的有效倍率排序",
        "waNotInMode": "常规模式没有这条（只出现在深夜诅咒武器上）",
        "waSearch": "搜索武器词条",
        "waTierHint": "同一词条的不同档位各自一个互斥键，按相乘计算（参数推断，未实测）",
        "waUsage": "已用 {0} / {1}",
        "warnCopiesSingle": "同一效果装了多份，按数据 stackingRules 只算一份（只有按 ID 互斥的 stackSelf 才各份相乘）：{0}",
        "warnCopiesStackSelf": "同一效果装了多份，按 stackSelf 各份相乘（stackingRules 第 2 条，参数推断，未实测）：{0}",
        "warnDuplicateKey": "互斥键 {0}：{1} 份只计 1 份（{2}）",
        "warnExclusivity": "「{0}」同属遗物互斥组 exclusivityId={1}：按参数推断分装在不同遗物上时只有一条生效，本页仍分别计入（未实测）",
        "warnFixedDuplicate": "同一件固定遗物只能装备一件：{0}",
        "warnLadders": "不同叠层阶梯同时生效（{0}）：各阶梯 categoryPriority 不同、按参数结构判为互不顶替、结果相乘，未实测",
        "warnPriority": "互斥键 {0}（applyHighest）：按 categoryPriority 取数值小的「{1}」，压掉 {2}",
        "warnTiers": "「{0}」的不同档位同时计入（{1}），各自独立相乘：参数推断，未实测",
        "wepTypeFallback": "类别 {0}",
    ]

    /// 取一条文案（缺键时退回键名，自检会拦下）。
    public static func t(_ key: String) -> String { table[key] ?? key }

    /// 按位置替换 {n}。
    public static func fmt(_ template: String, _ args: [String]) -> String {
        var result = ""
        var index = template.startIndex
        while index < template.endIndex {
            let character = template[index]
            if character == "{", let close = template[index...].firstIndex(of: "}"),
               let number = Int(template[template.index(after: index)..<close]) {
                result += number < args.count ? args[number] : ""
                index = template.index(after: close)
                continue
            }
            result.append(character)
            index = template.index(after: index)
        }
        return result
    }

    public static func f(_ key: String, _ args: CustomStringConvertible...) -> String {
        fmt(t(key), args.map { $0.description })
    }

    // MARK: 常用组合

    public static func columnTitle(_ column: LoadoutColumn) -> String {
        switch column {
        case .weaponAffix, .relic, .accessory: return t("columns." + column.rawValue)
        default: return t("otherGroups." + column.rawValue)
        }
    }

    public static func handName(_ hand: Int) -> String { t(hand == 2 ? "hand.2" : "hand.1") }

    /// 遗物格标题：「普通遗物 N」「深夜遗物 N」（深夜格从 1 数起，与 Windows relicCardLabel 同一口径）。
    public static func relicCardTitle(_ cardIndex: Int, normalCount: Int, deep: Bool) -> String {
        deep ? f("relicCardDeep", cardIndex - normalCount + 1) : f("relicCardNormal", cardIndex + 1)
    }

    /// 武器词条的标签：「提升战技攻击力（档位3）」。
    public static func weaponAffixLabel(_ info: BuffWeaponAffixInfo) -> String {
        let name = info.nameZh.isEmpty ? (info.nameEn.isEmpty ? "#\(info.attachEffectId)" : info.nameEn) : info.nameZh
        return name + (info.potency.map { "（" + f("badges.potency", $0) + "）" } ?? "")
    }

    public static func fixedRelicSubtitle(relicID: Int, color: Int) -> String {
        let colorName = table["relicColors.\(color)"]
        return colorName.map { f("relicFixedSubtitle", $0, relicID) } ?? "#\(relicID)"
    }

    /// 同族提示里的名字：显示名去掉末尾的全角括注与「＋N」（与 Windows familyName 同一正则）。
    public static func familyName(_ name: String) -> String {
        name.replacingOccurrences(of: #"（[^（）]*）$"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s*[＋+]\s*[0-9０-９]+$"#, with: "", options: .regularExpression)
    }

    /// 「连刺破露滴（第1层）」→「连刺破露滴」。
    public static func stripTierSuffix(_ name: String) -> String {
        name.replacingOccurrences(of: #"（第\d+[层档]）$"#, with: "", options: .regularExpression)
    }

    /// 一条增益的徽标（条件型 / 发动型 / 叠层 / 累积阶梯 / 多档 / 来源为推断 / 队友）。
    public static func entryBadges(_ buff: BuffEntry) -> [String] {
        var badges: [String] = []
        if buff.activation == "conditional" { badges.append(t("badges.conditional")) }
        if buff.activation == "activated" { badges.append(t("badges.activated")) }
        if let input = buff.stackInput { badges.append(t(input.isLadder ? "badges.ladder" : "badges.copies")) }
        if buff.accumulatorLadder != nil { badges.append(t("badges.accLadder")) }
        if buff.affixVariant != nil { badges.append(t("badges.variant")) }
        if buff.isInferredSource { badges.append(t("badges.inferredSource")) }
        if buff.selfAllyPair?.role == "ally" {
            badges.append(t("badges.allyPair"))
        } else if buff.target == "ally" {
            badges.append(t("badges.ally"))
        }
        return badges
    }

    /// 角色栏分组：Paramdex 行名 `[Skill - Revenant] …` → （复仇者, 技艺）。
    public static func heroGroup(paramName: String?) -> (hero: String, kind: String) {
        guard let paramName, paramName.hasPrefix("["), let close = paramName.firstIndex(of: "]") else {
            return (t("characterOther"), "")
        }
        let inside = String(paramName[paramName.index(after: paramName.startIndex)..<close])
        let parts = inside.components(separatedBy: " - ")
        let rawKind = parts.first?.trimmingCharacters(in: .whitespaces) ?? ""
        let kind = table["characterKinds." + rawKind] ?? rawKind
        guard parts.count > 1 else { return (t("characterOther"), kind) }
        let english = parts[1].trimmingCharacters(in: .whitespaces)
        return (table["characterNames." + english] ?? english, kind)
    }

    /// 叠层输入的提示（阶梯／份数 + 一局实际上限或『＋N』标签 + 赐福数）。
    public static func stackHints(_ input: BuffStackInput, grace: Bool) -> [String] {
        var hints: [String] = []
        if input.isLadder {
            hints.append(f("stackHintLadder", input.maxAllowedStacks))
        } else {
            hints.append(f("stackHintCopies", BuffFormat.trim(input.perStackMultiplier ?? 1, digits: 4)))
        }
        if let practical = input.practicalMaxStacks {
            hints.append(f("stackHintPractical", practical))
        } else if let label = input.uiLabelMax {
            hints.append(f("stackHintLabel", label))
        }
        if grace { hints.append(t("stackHintGrace")) }
        return hints
    }

    /// 层数的计数单位以游戏文本为准（notes.stackInput）：descZh 写着「新发现的赐福」的按赐福数提示。
    public static func isGraceStack(_ buff: BuffEntry) -> Bool {
        buff.stackInput != nil && (buff.descZh ?? "").contains("赐福")
    }

    // MARK: 说明区（两端同一顺序、同一文案，数字照数据现算）

    /// 「提升战技攻击力」类的子类别：appliesTo 为 skill=conditional、sorcery=no、incantation=no 的
    /// requires.subCategoriesAny 里，没有在任何法术、近战普通攻击、弓弩射击命中段出现过的那些（attackIndex 人口统计）。
    public static func skillOnlySubCategories(_ dataset: BuffDataset) -> [String] {
        var seen: Set<Int> = []
        for sets in dataset.attackIndex.spells.values { for set in sets { seen.formUnion(set.subs) } }
        for set in dataset.attackIndex.melee + dataset.attackIndex.ranged { seen.formUnion(set.subs) }
        var found: Set<Int> = []
        for buff in dataset.buffs {
            guard buff.appliesTo["skill"] == "conditional", buff.appliesTo["sorcery"] == "no",
                  buff.appliesTo["incantation"] == "no" else { continue }
            let subs = buff.appliesToDetail["skill"]?.requires?.subCategoriesAny ?? []
            guard !subs.isEmpty, !subs.contains(where: { seen.contains($0) }) else { continue }
            found.formUnion(subs)
        }
        return found.sorted(by: >).map { sub in dataset.subCategoryLabels[sub].map { "\(sub) \($0)" } ?? String(sub) }
    }

    public static func briefNotes(index: BuffLoadoutIndex) -> [String] {
        let dataset = index.dataset
        let rules = index.slotRules
        var stackTexts: [String] = []
        for buff in dataset.buffs {
            guard let input = buff.stackInput else { continue }
            var text: String
            if input.isLadder {
                text = f("briefStack.ladder", BuffFormat.trim(input.perStackRatio ?? 0, digits: 4), input.maxAllowedStacks)
                if let practical = input.practicalMaxStacks, practical > 0, !input.tierMultipliers.isEmpty {
                    text += f("briefStack.practical", practical,
                              BuffFormat.trim(input.tierMultipliers[min(practical, input.tierMultipliers.count) - 1], digits: 4))
                }
            } else {
                text = f("briefStack.copies", BuffFormat.trim(input.perStackMultiplier ?? 0, digits: 4))
                if isGraceStack(buff) { text += f("briefStack.unit", t("stackHintGrace")) }
            }
            stackTexts.append(f("briefStack.item", buff.displayName, text))
        }
        let decreaseCount = dataset.buffs.indices.filter {
            index.countsAsDamage[$0] && dataset.buffs[$0].direction == "decrease"
        }.count
        let variantGroups = index.variantMembers
        let variantCount = variantGroups.values.reduce(0) { $0 + $1.count }
        let skillSubs = skillOnlySubCategories(dataset)
        var notes = [
            t("brief.appliesTo"),
            t("brief.formula"),
            t("brief.partial"),
            f("brief.direction", decreaseCount),
            t("brief.target"),
            t("brief.activation"),
            t("brief.stacking")
        ]
        if !variantGroups.isEmpty { notes.append(f("brief.affixVariant", variantGroups.count, variantCount)) }
        notes += [
            t("brief.tiers"),
            f("brief.deepWeapon", rules.deepOnlyCap(.deep), rules.duplicateWithinWeaponStatus.isEmpty ? "unknown" : rules.duplicateWithinWeaponStatus),
            f("brief.relic", index.hasCatalog ? String(index.cursePoolID) : t("noData")),
            f("brief.skillAttack", skillSubs.isEmpty ? t("noData") : skillSubs.joined(separator: "／")),
            t("brief.equipped"),
            t("brief.innate"),
            f("brief.runStack", stackTexts.isEmpty ? t("noData") : stackTexts.joined(separator: t("briefStack.separator"))),
            t("brief.fill"),
            t("brief.throwInferred")
        ]
        return notes
    }
}
