import Foundation

// 「增伤排名」页的增伤手段数据（buffs.json，schemaVersion ≥ 3（当前 6）；各版只增字段，
// 向前兼容）的解码，以及旧版「按倍率排全表 + 推荐组合」的排名引擎。
//
// **页面已改为「自己组一套配置」**（BuffLoadout.swift：常规／深夜、局内武器词条、遗物、护符、其它增益，
// 生效判定一律取 v6 的 appliesTo / appliesToDetail）。下面的 BuffRankerIndex.rankResult / stackPlan /
// BuffRankerPageNotes 不再直接出现在页面上，保留是因为：① 每条 buff 的通道乘数（profiles）、
// 有效倍率加权与攻击力加算的算法由配置页直接复用；② 自检与 Windows 端的旧口径对照仍然钉在它们上面。
// v6 新增字段（sourceSlot / appliesTo / weaponAffix* / relicAffixes / stackInput / accumulatorLadder /
// exclusiveKey / slotRules / weaponAffixes / fixedRelics / attackIndex / userQuestions）的模型在本文件末尾。
//
// 旧引擎的口径（与 Windows 端 renderer/pages/ranker.js 旧版同一套）：
//
// 算法严格按数据集自带的 notes.ranking / notes.attackContext / notes.howToUseRates / stackingRules：
//   ① 先按 target 过滤：只保留 self（「包含队友给的增益」打开时再加 ally），
//      summon 是召唤物自己的系数、enemy 是挂在敌人身上的效果，混进来会直接霸榜；
//   ② 按 direction 过滤（只要 increase / mixed）；
//   ③ **先看 activation**：只有 passive 允许默认计入，conditional / activated 由用户勾选；
//   ④ **先看 scope.attackContexts**（v4 新增）：非空表示这条倍率只在某种攻击情境
//      （致命一击 / 突刺反击 / 防御反击 / 蓄力 / 跳跃…）下才吃得到，默认不得计入通用排名，
//      只有用户勾选了对应情境才参与乘算。这类条目本身是 passive（装上就一直在），
//      限制的是作用范围而不是发动时机，所以第③步拦不住它们，必须单独走这一步；
//      再按其余 scope 判断是否作用于当前输出手段（武器槽 / 魔法 / 祷告 / 攻击子类别 / 属性限定）；
//   ⑤ 每个 rates 字段查 rateFields[key]：只有 countsAsDamage 且 valueKind = multiplier 的
//      才进乘积（damage 层与 attackPower 层都乘）；flat 是点数加算，需要绝对攻击力才能换算成
//      倍率，本页只展示不乘；weakness / critical（conditionalDamage）、stance / status /
//      special / flag / economy 一律不进乘积；
//   ⑥ 用 stacking.group 分组去重（同组按 spCategoryBehavior 处理）后跨组相乘；
//   ⑦ 列表一律显示 displayNameZh。
//
// v4 新增并已实现：scope.attackContexts（④）、stackLadder（同一阶梯共用一个叠加组键，
//   另给「按满层计算」开关）、enums.stateInfo（叠加组标签）。
// v5 新增并已实现：selfInflictedStatus（20 条自伤型异常累积，只打标 + 写进说明；那些字段
//   countsAsDamage 全为 false，伤害乘积一个数都不受影响）、43 条 target self→enemy
//   （被第①步的 target 白名单挡下）、notes.stackLadder（底部原文）。
//
// 有效倍率 = Σ_通道 占比_通道 × Π(作用于该通道的倍率字段)。
// 每条 buff 的「各通道乘数」只跟它自己的 rates + scope 有关，与勾选的段无关，
// 因此在建索引时一次算好（`BuffRankerIndex.profiles`）；选段变化时只做
// 「9 个通道的加权求和」，不重建索引。

// MARK: - 错误

public enum BuffDataError: LocalizedError {
    case notAnObject
    case undecodable(String)
    case empty

    public var errorDescription: String? {
        switch self {
        case .notAnObject: return "增益数据不是合法的 JSON 对象"
        case .undecodable(let detail): return "增益数据无法解码：" + detail
        case .empty: return "增益数据里没有任何 buff 记录"
        }
    }
}

// MARK: - 宽容解码辅助

struct BuffFailable<T: Decodable>: Decodable {
    let value: T?

    init(from decoder: Decoder) throws {
        value = try? T(from: decoder)
    }
}

/// JSON 里的数字 / 布尔 / 数字字符串都收成 Double（rates、conditions 混用这几种）。
struct BuffNumber: Decodable {
    let value: Double

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let number = try? container.decode(Double.self) {
            value = number
        } else if let flag = try? container.decode(Bool.self) {
            value = flag ? 1 : 0
        } else if let text = try? container.decode(String.self), let number = Double(text) {
            value = number
        } else {
            throw DecodingError.typeMismatch(
                Double.self,
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "不是数值")
            )
        }
    }
}

extension KeyedDecodingContainer {
    func buffDouble(_ key: Key, default fallback: Double) -> Double {
        if let wrapped = try? decodeIfPresent(BuffNumber.self, forKey: key) { return wrapped.value }
        return fallback
    }

    func buffInt(_ key: Key, default fallback: Int) -> Int {
        if let wrapped = try? decodeIfPresent(BuffNumber.self, forKey: key), wrapped.value.isFinite {
            return Int(wrapped.value.rounded())
        }
        return fallback
    }

    func buffOptionalInt(_ key: Key) -> Int? {
        if let wrapped = try? decodeIfPresent(BuffNumber.self, forKey: key), wrapped.value.isFinite {
            return Int(wrapped.value.rounded())
        }
        return nil
    }

    func buffString(_ key: Key, default fallback: String = "") -> String {
        if let value = try? decodeIfPresent(String.self, forKey: key), !value.isEmpty { return value }
        if let wrapped = try? decodeIfPresent(BuffNumber.self, forKey: key), wrapped.value.isFinite {
            return String(Int(wrapped.value.rounded()))
        }
        return fallback
    }

    func buffOptionalString(_ key: Key) -> String? {
        guard let value = try? decodeIfPresent(String.self, forKey: key), !value.isEmpty else { return nil }
        return value
    }

    func buffBool(_ key: Key, default fallback: Bool = false) -> Bool {
        if let value = try? decodeIfPresent(Bool.self, forKey: key) { return value }
        if let wrapped = try? decodeIfPresent(BuffNumber.self, forKey: key) { return wrapped.value != 0 }
        return fallback
    }

    func buffArray<T: Decodable>(_ key: Key) -> [T] {
        guard let wrapped = try? decodeIfPresent([BuffFailable<T>].self, forKey: key) else { return [] }
        return wrapped.compactMap(\.value)
    }

    func buffIntArray(_ key: Key) -> [Int] {
        guard let wrapped = try? decodeIfPresent([BuffFailable<BuffNumber>].self, forKey: key) else { return [] }
        return wrapped.compactMap { $0.value.flatMap { $0.value.isFinite ? Int($0.value.rounded()) : nil } }
    }

    func buffStringArray(_ key: Key) -> [String] {
        guard let wrapped = try? decodeIfPresent([BuffFailable<String>].self, forKey: key) else { return [] }
        return wrapped.compactMap(\.value)
    }

    func buffNumberDictionary(_ key: Key) -> [String: Double] {
        guard let wrapped = try? decodeIfPresent([String: BuffFailable<BuffNumber>].self, forKey: key) else { return [:] }
        return wrapped.compactMapValues { $0.value.flatMap { $0.value.isFinite ? $0.value : nil } }
    }

    func buffStringDictionary(_ key: Key) -> [String: String] {
        guard let wrapped = try? decodeIfPresent([String: BuffFailable<String>].self, forKey: key) else { return [:] }
        return wrapped.compactMapValues(\.value)
    }
}

// MARK: - 字段表

public enum BuffRateValueKind: String, Sendable, Hashable {
    case multiplier
    case flat
    case flag
    case special
    case unknown

    public init(raw: String) {
        self = BuffRateValueKind(rawValue: raw) ?? .unknown
    }
}

public struct BuffRateFieldGroup: Sendable, Hashable, Decodable, Identifiable {
    public let key: String
    public let zh: String
    public let countsAsDamage: Bool
    public let conditionalDamage: Bool
    public let qualifies: Bool
    public let note: String

    public var id: String { key }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        key = container.buffString(.key)
        zh = container.buffString(.zh)
        countsAsDamage = container.buffBool(.countsAsDamage)
        conditionalDamage = container.buffBool(.conditionalDamage)
        qualifies = container.buffBool(.qualifies)
        note = container.buffString(.note)
    }

    private enum CodingKeys: String, CodingKey {
        case key, zh, countsAsDamage, conditionalDamage, qualifies, note
    }
}

public struct BuffRateField: Sendable, Hashable, Decodable, Identifiable {
    public let key: String
    public let zh: String
    public let en: String
    public let defaultValue: Double
    public let group: String
    public let valueKind: BuffRateValueKind
    public let countsAsDamage: Bool
    public let conditionalDamage: Bool
    public let observedCount: Int
    public let lowerIsBetter: Bool
    public let appliesTo: String

    public var id: String { key }

    /// 进通用伤害乘积的字段：countsAsDamage 且是乘数。
    public var isRankingMultiplier: Bool { countsAsDamage && valueKind == .multiplier }
    /// 攻击力加算：countsAsDamage，但必须先加进攻击力再乘倍率，本页只展示。
    public var isRankingFlat: Bool { countsAsDamage && valueKind == .flat }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        key = container.buffString(.key)
        zh = container.buffString(.zh)
        en = container.buffString(.en)
        defaultValue = container.buffDouble(.default, default: 0)
        group = container.buffString(.group)
        valueKind = BuffRateValueKind(raw: container.buffString(.valueKind, default: "unknown"))
        countsAsDamage = container.buffBool(.countsAsDamage)
        conditionalDamage = container.buffBool(.conditionalDamage)
        observedCount = container.buffInt(.observedCount, default: 0)
        lowerIsBetter = container.buffBool(.lowerIsBetter)
        appliesTo = container.buffString(.appliesTo)
    }

    private enum CodingKeys: String, CodingKey {
        case key, zh, en, group, valueKind, countsAsDamage, conditionalDamage
        case observedCount, lowerIsBetter, appliesTo
        case `default`
    }
}

// MARK: - buff 条目

public struct BuffSourceRef: Sendable, Hashable, Decodable, Identifiable {
    public let kind: String
    /// inferred = true 的条目 id 恒为 null，不得联表（sourceIdContract）。
    public let sourceID: Int?
    public let nameZh: String?
    public let nameEn: String?
    public let effectNameZh: String?
    public let via: String
    public let trigger: String?
    public let inferred: Bool
    public let paramRowCategory: String?
    /// v6：AoW 推断来源上写出的战技名（ArtsName）与战技 id。
    public let artsNameZh: String?
    public let artsId: Int?

    public var id: String { "\(kind)-\(sourceID.map(String.init) ?? (nameEn ?? nameZh ?? "?"))" }

    public var displayName: String {
        if let nameZh, !nameZh.isEmpty { return nameZh }
        if let nameEn, !nameEn.isEmpty { return nameEn }
        if let paramRowCategory, !paramRowCategory.isEmpty { return paramRowCategory }
        return "未命名来源"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = container.buffString(.kind, default: "other")
        sourceID = container.buffOptionalInt(.id)
        nameZh = container.buffOptionalString(.nameZh)
        nameEn = container.buffOptionalString(.nameEn)
        effectNameZh = container.buffOptionalString(.effectNameZh)
        via = container.buffString(.via)
        trigger = container.buffOptionalString(.trigger)
        inferred = container.buffBool(.inferred)
        paramRowCategory = container.buffOptionalString(.paramRowCategory)
        artsNameZh = container.buffOptionalString(.artsNameZh)
        artsId = container.buffOptionalInt(.artsId)
    }

    private enum CodingKeys: String, CodingKey {
        case kind, id, nameZh, nameEn, effectNameZh, via, trigger, inferred, paramRowCategory
        case artsNameZh, artsId
    }
}

public struct BuffScope: Sendable, Hashable, Decodable {
    public let affectsSorcery: Bool
    public let affectsIncantation: Bool
    public let affectsShaman: Bool
    public let affectsThrow: Bool
    /// wepParamChange：1 右手 / 2 左手 / 3 自身 / 4 踢击；缺失（0）= 不限。
    public let weaponSlot: Int?
    /// 只作用于某个物理攻击类型（0 斩 / 1 打 / 2 突 / 3 标准）；本版本 0 实例。
    public let atkAttribute: Int?
    /// 只作用于带某个特殊属性（魔 / 火 / 雷 / 圣 / 各种异常）的攻击。
    public let spAttribute: Int?
    /// magicSubCategoryChange1..3：攻击子类别过滤（112 战技攻击、123 绝招…）。
    public let subCategories: [Int]
    /// v4 新增：这条倍率只在列出的攻击情境（致命一击 / 突刺反击 / 蓄力战技…）下才吃得到。
    ///
    /// 非空 = **默认不得计入通用排名**，只有用户勾选了其中任一情境才参与乘算
    /// （notes.attackContext：它和 activation 是正交的两条轴，第③步拦不住它们）。
    /// 取值见 `enums.attackContext`，是 subCategories 与 stacking.stateInfo 两条来路的归一化视图。
    public let attackContexts: [String]
    /// v6：局内武器词条能出现在哪些武器类别（wepType）上（常规∪深夜）。
    public let rollableWeaponTypes: [Int]
    /// v6：「装备 N 把 X 类武器」／「用 X 类武器发动」的武器类别条件。
    public let weaponTypes: BuffWeaponTypesScope?

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        affectsSorcery = container.buffBool(.affectsSorcery)
        affectsIncantation = container.buffBool(.affectsIncantation)
        affectsShaman = container.buffBool(.affectsShaman)
        affectsThrow = container.buffBool(.affectsThrow)
        weaponSlot = container.buffOptionalInt(.weaponSlot)
        atkAttribute = container.buffOptionalInt(.atkAttribute)
        spAttribute = container.buffOptionalInt(.spAttribute)
        subCategories = container.buffIntArray(.subCategories)
        attackContexts = container.buffStringArray(.attackContexts)
        rollableWeaponTypes = container.buffIntArray(.rollableWeaponTypes)
        weaponTypes = (try? container.decodeIfPresent(BuffWeaponTypesScope.self, forKey: .weaponTypes)).flatMap { $0 }
    }

    private enum CodingKeys: String, CodingKey {
        case affectsSorcery, affectsIncantation, affectsShaman, affectsThrow
        case weaponSlot, atkAttribute, spAttribute, subCategories, attackContexts
        case rollableWeaponTypes, weaponTypes
    }

    public init(
        affectsSorcery: Bool = false, affectsIncantation: Bool = false,
        affectsShaman: Bool = false, affectsThrow: Bool = false,
        weaponSlot: Int? = nil, atkAttribute: Int? = nil,
        spAttribute: Int? = nil, subCategories: [Int] = [],
        attackContexts: [String] = [],
        rollableWeaponTypes: [Int] = [],
        weaponTypes: BuffWeaponTypesScope? = nil
    ) {
        self.affectsSorcery = affectsSorcery
        self.affectsIncantation = affectsIncantation
        self.affectsShaman = affectsShaman
        self.affectsThrow = affectsThrow
        self.weaponSlot = weaponSlot
        self.atkAttribute = atkAttribute
        self.spAttribute = spAttribute
        self.subCategories = subCategories
        self.attackContexts = attackContexts
        self.rollableWeaponTypes = rollableWeaponTypes
        self.weaponTypes = weaponTypes
    }

    /// 只在某种攻击情境下才吃得到（默认不计入通用排名）。
    public var isContextGated: Bool { !attackContexts.isEmpty }

    /// scope.spAttribute 限定：只对带某种属性 / 异常的攻击生效，本页无从判定，默认不计入。
    public var isAttributeScoped: Bool { spAttribute != nil }

    // 下面三条是**页面自己承担的判定**（数据集没有直接字段），两端同一套：
    //
    //  · throwOnly：affectsThrow 单独为真＝只作用于「投げ」攻击，也就是致命一击 / 背刺 / 处决
    //    （『强化致命一击』全系都是这个签名）。无条件相乘会让它稳居榜首。
    //    **只在没有 attackContexts 时才用这条推断**：v4 起 attackContexts 给出了机读依据
    //    （criticalHit 等），有它就以它为准。
    //  · spellOnly：weaponSlot=3 且只点亮魔法／祷告、没点亮秘术＝『强化魔法』『强化祷告』
    //    那一类只作用于法术的条目，不能算进武器／战技命中。
    //  · meleeOnly：subCategories 只有 130（近战武器攻击）而没有 112（战技攻击）。战技的近战
    //    命中算不算 130，数据集没有给出判据，两端都保守地判为作用域不符并在说明里列出。
    public var isThrowOnly: Bool {
        attackContexts.isEmpty && affectsThrow && !affectsSorcery && !affectsIncantation && !affectsShaman
    }

    public var isSpellOnly: Bool {
        weaponSlot == 3 && (affectsSorcery || affectsIncantation) && !affectsShaman
    }

    public var isMeleeOnly: Bool {
        subCategories.contains(BuffRankingContext.meleeAttackSubCategory)
            && !subCategories.contains(BuffRankingContext.skillAttackSubCategory)
    }
}

/// v4 新增：这条 buff 是一段叠层阶梯的第 1 层，数据集只收录了第 1 层。
///
/// `topRates` 是满层数值——页面必须标出来，否则用户看到的是「×1.007」这种
/// 看起来像噪音、实际满 100 层是 ×1.40 的条目。同一阶梯的各层互斥，**绝不能相乘**。
public struct BuffStackLadder: Sendable, Hashable, Decodable {
    /// 总层数。
    public let tiers: Int
    /// 同一阶梯其余各层的 spEffectId（本版本只收录第 1 层，这里是「将来会收的那些」）。
    public let tierSpEffectIds: [Int]
    /// 满层时的 rates。
    public let topRates: [String: Double]
    /// 层数是否存档保留（跨局不清空）。
    public let saved: Bool

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        tiers = container.buffInt(.tiers, default: 0)
        tierSpEffectIds = container.buffIntArray(.tierSpEffectIds)
        topRates = container.buffNumberDictionary(.topRates)
        saved = container.buffBool(.saved)
    }

    private enum CodingKeys: String, CodingKey {
        case tiers, tierSpEffectIds, topRates, saved
    }

    public init(tiers: Int, tierSpEffectIds: [Int] = [], topRates: [String: Double] = [:], saved: Bool = false) {
        self.tiers = tiers
        self.tierSpEffectIds = tierSpEffectIds
        self.topRates = topRates
        self.saved = saved
    }
}

public struct BuffStacking: Sendable, Hashable, Decodable {
    public let stateInfo: Int
    public let spCategory: Int
    public let spCategoryBehavior: String
    public let categoryPriority: Int
    public let saveCategory: Int
    /// 分组键：stackSelf / none 时是 "sp<category>#<spEffectId>"，其余是 "sp<category>"。
    public let group: String
    /// v6：互斥键（同键只留一份，不同键相乘）。缺失时退回 `group`（旧口径）。
    public let exclusiveKey: String
    /// v6：perSpEffect / category / categoryPriority / accumulatorLadder。
    public let exclusiveScope: String

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        stateInfo = container.buffInt(.stateInfo, default: 0)
        spCategory = container.buffInt(.spCategory, default: 0)
        spCategoryBehavior = container.buffString(.spCategoryBehavior, default: "unknown")
        categoryPriority = container.buffInt(.categoryPriority, default: 0)
        saveCategory = container.buffInt(.saveCategory, default: -1)
        group = container.buffString(.group)
        exclusiveKey = container.buffString(.exclusiveKey, default: group)
        exclusiveScope = container.buffString(.exclusiveScope)
    }

    private enum CodingKeys: String, CodingKey {
        case stateInfo, spCategory, spCategoryBehavior, categoryPriority, saveCategory, group
        case exclusiveKey, exclusiveScope
    }

    public init(
        stateInfo: Int = 0, spCategory: Int = 0, spCategoryBehavior: String = "none",
        categoryPriority: Int = 0, saveCategory: Int = -1, group: String,
        exclusiveKey: String? = nil, exclusiveScope: String = ""
    ) {
        self.stateInfo = stateInfo
        self.spCategory = spCategory
        self.spCategoryBehavior = spCategoryBehavior
        self.categoryPriority = categoryPriority
        self.saveCategory = saveCategory
        self.group = group
        self.exclusiveKey = exclusiveKey ?? group
        self.exclusiveScope = exclusiveScope
    }
}

public struct BuffEntry: Sendable, Hashable, Decodable, Identifiable {
    public let spEffectId: Int
    public let nameZh: String?
    public let nameEn: String?
    /// 列表一律显示它（生成时已保证全表唯一）。
    public let displayNameZh: String?
    public let displayNameEn: String?
    public let paramName: String?
    public let sources: [BuffSourceRef]
    public let rates: [String: Double]
    public let rateGroups: [String]
    public let direction: String
    public let scope: BuffScope
    public let stacking: BuffStacking
    /// v4：非 nil 表示这条只是一段叠层阶梯的第 1 层，`topRates` 才是满层数值。
    public let stackLadder: BuffStackLadder?
    /// 秒；-1 表示永久。
    public let duration: Double
    public let permanent: Bool
    public let target: String
    public let targetSource: String
    /// passive / conditional / activated。
    public let activation: String
    public let activationSource: String
    public let descZh: String?
    public let conditions: [String: Double]
    public let triggered: [String: Double]
    /// nameZh 借用了同族词条的名字（同一条词条的不同档位）。
    public let inferredName: Bool
    /// v5：这一行 rates 里 group="status" 的加算点数是**累在玩家自己身上的自伤**，
    /// 不是「让玩家的攻击多附带累积」。那些字段 countsAsDamage 全为 false，伤害乘积不受影响；
    /// 做异常累积榜时必须整条排除（notes.target / diagnostics.selfInflictedStatus）。
    public let selfInflictedStatus: Bool
    public let statusLabelsZh: [String]
    public let sourcesTruncated: Int?

    // MARK: v6（配置页用；缺失一律退默认值，不抛错）

    /// 这条 buff 该放进配置页的哪一栏（enums.sourceSlot）。缺失时为 "other"。
    public let sourceSlot: String
    /// 全部槽位（按 enums.sourceSlot 顺序，[0] 就是 sourceSlot）。
    public let sourceSlots: [String]
    public let sourceSlotReason: String?
    /// skill / sorcery / incantation / melee / ranged / throw → yes / no / conditional。
    public let appliesTo: [String: String]
    /// 非 yes 的类别的 {reason, requires?, matchShare?}。
    public let appliesToDetail: [String: BuffAppliesDetail]
    /// 局内武器词条：AttachEffect id、角色（affix / curse / blessing / fixed）、是否只在深夜池出现。
    public let weaponAffixIds: [Int]
    public let weaponAffixRoles: [String]
    public let weaponAffixDeepOnly: Bool
    /// 正面的深夜专属词条（深夜每把武器最多 1 条、合计最多 6 条的计数口径）。
    public let weaponAffixDeepOnlyPositive: Bool
    public let relicAffixes: [BuffRelicAffixRef]
    public let weaponInnate: BuffWeaponInnate?
    public let stackInput: BuffStackInput?
    public let accumulatorLadder: BuffAccumulatorLadder?
    /// 只在使用这些道具（GoodsName id）时才成立。
    public let requiresGoodsIds: [Int]

    public var id: Int { spEffectId }

    public var displayName: String {
        if let displayNameZh, !displayNameZh.isEmpty { return displayNameZh }
        if let nameZh, !nameZh.isEmpty { return nameZh }
        if let displayNameEn, !displayNameEn.isEmpty { return displayNameEn }
        if let nameEn, !nameEn.isEmpty { return nameEn }
        if let paramName, !paramName.isEmpty { return paramName }
        return "#\(spEffectId)"
    }

    public var isPassive: Bool { activation == "passive" }
    /// 来源全靠 Paramdex 行名推断（物品归属未经验证，倍率数值本身仍是原始值）。
    public var isInferredSource: Bool { !sources.isEmpty && sources.allSatisfy(\.inferred) }

    /// 去重后的来源类型，按数据集里的出现顺序。
    public var sourceKinds: [String] {
        var seen: Set<String> = []
        return sources.map(\.kind).filter { seen.insert($0).inserted }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        spEffectId = container.buffInt(.spEffectId, default: -1)
        nameZh = container.buffOptionalString(.nameZh)
        nameEn = container.buffOptionalString(.nameEn)
        displayNameZh = container.buffOptionalString(.displayNameZh)
        displayNameEn = container.buffOptionalString(.displayNameEn)
        paramName = container.buffOptionalString(.paramName)
        sources = container.buffArray(.sources)
        rates = container.buffNumberDictionary(.rates)
        rateGroups = container.buffStringArray(.rateGroups)
        direction = container.buffString(.direction, default: "increase")
        scope = (try? container.decodeIfPresent(BuffScope.self, forKey: .scope)).flatMap { $0 } ?? BuffScope()
        stacking = (try? container.decodeIfPresent(BuffStacking.self, forKey: .stacking)).flatMap { $0 }
            ?? BuffStacking(group: "sp0#\(container.buffInt(.spEffectId, default: -1))")
        stackLadder = (try? container.decodeIfPresent(BuffStackLadder.self, forKey: .stackLadder)).flatMap { $0 }
        duration = container.buffDouble(.duration, default: -1)
        permanent = container.buffBool(.permanent)
        target = container.buffString(.target, default: "self")
        targetSource = container.buffString(.targetSource, default: "default")
        activation = container.buffString(.activation, default: "passive")
        activationSource = container.buffString(.activationSource, default: "noEvidence")
        descZh = container.buffOptionalString(.descZh)
        conditions = container.buffNumberDictionary(.conditions)
        triggered = container.buffNumberDictionary(.triggered)
        inferredName = container.buffBool(.inferredName)
        selfInflictedStatus = container.buffBool(.selfInflictedStatus)
        statusLabelsZh = container.buffStringArray(.statusLabelsZh)
        sourcesTruncated = container.buffOptionalInt(.sourcesTruncated)

        let slots = container.buffStringArray(.sourceSlots)
        sourceSlot = container.buffOptionalString(.sourceSlot) ?? slots.first ?? "other"
        sourceSlots = slots.isEmpty ? [sourceSlot] : slots
        sourceSlotReason = container.buffOptionalString(.sourceSlotReason)
        appliesTo = container.buffStringDictionary(.appliesTo)
        if let wrapped = try? container.decodeIfPresent(
            [String: BuffFailable<BuffAppliesDetail>].self, forKey: .appliesToDetail
        ) {
            appliesToDetail = wrapped.compactMapValues(\.value)
        } else {
            appliesToDetail = [:]
        }
        weaponAffixIds = container.buffIntArray(.weaponAffixIds)
        weaponAffixRoles = container.buffStringArray(.weaponAffixRoles)
        weaponAffixDeepOnly = container.buffBool(.weaponAffixDeepOnly)
        weaponAffixDeepOnlyPositive = container.buffBool(.weaponAffixDeepOnlyPositive)
        relicAffixes = container.buffArray(.relicAffixes)
        weaponInnate = (try? container.decodeIfPresent(BuffWeaponInnate.self, forKey: .weaponInnate)).flatMap { $0 }
        stackInput = (try? container.decodeIfPresent(BuffStackInput.self, forKey: .stackInput)).flatMap { $0 }
        accumulatorLadder = (try? container.decodeIfPresent(
            BuffAccumulatorLadder.self, forKey: .accumulatorLadder
        )).flatMap { $0 }
        requiresGoodsIds = container.buffIntArray(.requiresGoodsIds)
    }

    private enum CodingKeys: String, CodingKey {
        case spEffectId, nameZh, nameEn, displayNameZh, displayNameEn, paramName
        case sources, rates, rateGroups, direction, scope, stacking, stackLadder
        case duration, permanent, target, targetSource, activation, activationSource
        case descZh, conditions, triggered, inferredName, selfInflictedStatus
        case statusLabelsZh, sourcesTruncated
        case sourceSlot, sourceSlots, sourceSlotReason, appliesTo, appliesToDetail
        case weaponAffixIds, weaponAffixRoles, weaponAffixDeepOnly, weaponAffixDeepOnlyPositive
        case relicAffixes, weaponInnate, stackInput, accumulatorLadder, requiresGoodsIds
    }

    /// 同族＝Paramdex 行名去掉档位后缀后相同（`[Item - Level 3] X` → `[Item] X`、
    /// `[Weapon] X - Potency 2` → `[Weapon] X`、`[Relic] X +3` → `[Relic] X`）。
    /// 数据集自己就用「同族」概念统一 displayName 的限定词，这里复用同一口径；
    /// 与 Windows 端 familyKey 逐条对应。
    public var familyKey: String {
        guard let paramName, !paramName.isEmpty else { return "id#\(spEffectId)" }
        let stem = Self.familyStem(paramName)
        return stem.isEmpty ? "id#\(spEffectId)" : stem
    }

    /// `[Item - Level 3] X` → `[Item] X`、`[Weapon] X - Potency 2` → `[Weapon] X`、
    /// `[Relic] X +3` → `[Relic] X`。逐条对应 Windows 端 familyKey 里的三条正则
    /// （`^\[([^\]]*)\]\s*(.*)$`、`\s*-\s*(?:Potency|Level|Tier)\s*\d+\s*$`、`\s*\+\d+\s*$`）。
    static func familyStem(_ raw: String) -> String {
        var text = raw
        if text.hasPrefix("["), let close = text.firstIndex(of: "]") {
            let inside = String(text[text.index(after: text.startIndex)..<close])
            var rest = String(text[text.index(after: close)...])
            while let first = rest.first, first.isWhitespace { rest.removeFirst() }
            let head = (inside.components(separatedBy: " - ").first ?? inside)
                .trimmingCharacters(in: .whitespaces)
            text = "[" + head + "] " + rest
        }
        text = stripTierSuffix(text)
        text = stripPlusSuffix(text)
        return text.trimmingCharacters(in: .whitespaces)
    }

    private static func isAsciiDigit(_ character: Character) -> Bool {
        character.isASCII && character.isNumber
    }

    /// `\s*-\s*(?:Potency|Level|Tier)\s*\d+\s*$`
    private static func stripTierSuffix(_ text: String) -> String {
        let chars = Array(text)
        var index = chars.count
        while index > 0, chars[index - 1].isWhitespace { index -= 1 }
        var digits = 0
        while index > 0, isAsciiDigit(chars[index - 1]) {
            index -= 1
            digits += 1
        }
        guard digits > 0 else { return text }
        while index > 0, chars[index - 1].isWhitespace { index -= 1 }
        var matched = false
        for keyword in ["potency", "level", "tier"] where index >= keyword.count {
            if String(chars[(index - keyword.count)..<index]).lowercased() == keyword {
                index -= keyword.count
                matched = true
                break
            }
        }
        guard matched else { return text }
        while index > 0, chars[index - 1].isWhitespace { index -= 1 }
        guard index > 0, chars[index - 1] == "-" else { return text }
        index -= 1
        while index > 0, chars[index - 1].isWhitespace { index -= 1 }
        return String(chars[0..<index])
    }

    /// `\s*\+\d+\s*$`
    private static func stripPlusSuffix(_ text: String) -> String {
        let chars = Array(text)
        var index = chars.count
        while index > 0, chars[index - 1].isWhitespace { index -= 1 }
        var digits = 0
        while index > 0, isAsciiDigit(chars[index - 1]) {
            index -= 1
            digits += 1
        }
        guard digits > 0, index > 0, chars[index - 1] == "+" else { return text }
        index -= 1
        while index > 0, chars[index - 1].isWhitespace { index -= 1 }
        return String(chars[0..<index])
    }

    /// stackingRules 第 3 条的「交叉参考」键：behavior 本身就互斥的组不需要它，
    /// stateInfo 为 0 的（绝大多数）也没有判定力。默认关闭，由页面开关打开。
    public var stateCrossReferenceKey: String? {
        guard stacking.spCategoryBehavior == "none" || stacking.spCategoryBehavior == "stackSelf" else {
            return nil
        }
        guard stacking.stateInfo != 0 else { return nil }
        return "state#\(stacking.stateInfo)"
    }
}

// MARK: - 数据集

public struct BuffDataset: Sendable {
    public let schemaVersion: Int
    public let gameVersion: String
    public let dataVersion: String
    public let generatedAt: String
    /// notes.ranking / notes.howToUseRates / notes.activation… 页面底部原样展示。
    public let notes: [String: String]
    public let stackingRulesZh: String
    public let rateFields: [BuffRateField]
    public let rateFieldGroups: [BuffRateFieldGroup]
    public let conditionFieldLabels: [String: String]
    public let sourceKindLabels: [String: String]
    public let weaponSlotLabels: [Int: String]
    public let spAttributeLabels: [Int: String]
    public let subCategoryLabels: [Int: String]
    public let activationLabels: [String: String]
    public let stackBehaviorLabels: [String: String]
    /// v4 `enums.attackContext`：攻击情境键 → 中文名（criticalHit → 致命一击／处决）。
    public let attackContextLabels: [String: String]
    /// v4 `enums.stateInfo`：SP_EFFECT_TYPE → 中文名（367 → 强化致命一击）。
    public let stateInfoLabels: [Int: String]
    public let counts: [String: Double]
    public let buffs: [BuffEntry]

    // MARK: v6（配置页用）

    /// slotRules：常规／深夜的武器词条、遗物、护符槽位。缺失时为 nil（页面显示「数据未内置」）。
    public let slotRules: BuffSlotRules?
    /// 有增伤 buff 的局内武器词条清单（按 AttachEffect id）。
    public let weaponAffixes: [BuffWeaponAffixInfo]
    /// 官方固定词条遗物。
    public let fixedRelics: [BuffFixedRelic]
    /// 每个战技／法术实际命中段的子类别集合（appliesTo=conditional 且带 subCategoriesAny 时用）。
    public let attackIndex: BuffAttackIndex
    /// enums.sourceSlot：键 → 中文名 / 说明。
    public let sourceSlotLabels: [String: String]
    public let sourceSlotNotes: [String: String]
    /// enums.wepType：wepType → 中文名（短剑、刀…）。
    public let wepTypeLabels: [Int: String]
    /// enums.exclusiveScope：键 → 中文说明。
    public let exclusiveScopeLabels: [String: String]
    /// notes.userQuestions（Q1…Q5）。
    public let userQuestions: [BuffUserQuestion]

    public func rateField(_ key: String) -> BuffRateField? {
        rateFields.first { $0.key == key }
    }

    public func sourceKindLabel(_ kind: String) -> String {
        sourceKindLabels[kind] ?? kind
    }

    public func activationLabel(_ activation: String) -> String {
        activationLabels[activation] ?? activation
    }

    public func stackBehaviorLabel(_ code: String) -> String {
        stackBehaviorLabels[code] ?? code
    }

    /// 攻击情境的中文名；数据集没给标签时退回原始键。
    public func attackContextLabel(_ key: String) -> String {
        attackContextLabels[key] ?? key
    }

    /// `enums.stateInfo` 的标签条数（v5 起 counts.stateInfoLabels 也有同一个数）。
    public var stateInfoLabelCount: Int { stateInfoLabels.count }

    /// 叠加组 stateInfo 的中文名；缺标签时退回裸数字（「强化致命一击（367）」）。
    public func stateInfoLabel(_ value: Int) -> String {
        guard let label = stateInfoLabels[value], !label.isEmpty else { return String(value) }
        return "\(label)（\(value)）"
    }

    public static func decode(from data: Data) throws -> BuffDataset {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              object is [String: Any] else {
            throw BuffDataError.notAnObject
        }
        do {
            return try JSONDecoder().decode(BuffDataset.self, from: data)
        } catch {
            throw BuffDataError.undecodable(String(describing: error))
        }
    }
}

extension BuffDataset: Decodable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = container.buffInt(.schemaVersion, default: 0)
        gameVersion = container.buffString(.gameVersion)
        dataVersion = container.buffString(.dataVersion)
        generatedAt = container.buffString(.generatedAt)
        notes = container.buffStringDictionary(.notes)
        if let rules = try? container.decodeIfPresent([String: BuffFailable<String>].self, forKey: .stackingRules) {
            stackingRulesZh = rules["zh"]?.value ?? ""
        } else {
            stackingRulesZh = ""
        }
        rateFields = container.buffArray(.rateFields)
        rateFieldGroups = container.buffArray(.rateFieldGroups)

        var conditionLabels: [String: String] = [:]
        for field in container.buffArray(.conditionFields) as [BuffLabeledKey] {
            conditionLabels[field.key] = field.zh
        }
        conditionFieldLabels = conditionLabels

        let enums = (try? container.decodeIfPresent(BuffEnums.self, forKey: .enums)).flatMap { $0 } ?? BuffEnums()
        sourceKindLabels = enums.sourceKind
        weaponSlotLabels = enums.wepParamChange
        spAttributeLabels = enums.spAttribute
        subCategoryLabels = enums.atkSubCategory
        activationLabels = enums.activation
        stackBehaviorLabels = enums.spCategoryBehavior
        attackContextLabels = enums.attackContext
        stateInfoLabels = enums.stateInfo
        sourceSlotLabels = enums.sourceSlot
        sourceSlotNotes = enums.sourceSlotNote
        wepTypeLabels = enums.wepType
        exclusiveScopeLabels = enums.exclusiveScope

        counts = container.buffNumberDictionary(.counts)
        buffs = container.buffArray(.buffs)

        slotRules = (try? container.decodeIfPresent(BuffSlotRules.self, forKey: .slotRules)).flatMap { $0 }
        weaponAffixes = container.buffArray(.weaponAffixes)
        fixedRelics = container.buffArray(.fixedRelics)
        attackIndex = (try? container.decodeIfPresent(BuffAttackIndex.self, forKey: .attackIndex)).flatMap { $0 }
            ?? BuffAttackIndex()
        userQuestions = (try? container.decodeIfPresent(BuffNotesQuestions.self, forKey: .notes))
            .flatMap { $0?.questions } ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, gameVersion, dataVersion, generatedAt, notes
        case stackingRules, rateFields, rateFieldGroups, conditionFields, enums, counts, buffs
        case slotRules, weaponAffixes, fixedRelics, attackIndex
    }
}

/// conditionFields / chainFields 的 {key, zh}。
struct BuffLabeledKey: Decodable {
    let key: String
    let zh: String

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        key = container.buffString(.key)
        zh = container.buffString(.zh)
    }

    private enum CodingKeys: String, CodingKey {
        case key, zh
    }
}

/// enums 块：只取页面要用的几张表，其余忽略。
struct BuffEnums: Decodable {
    var sourceKind: [String: String] = [:]
    var wepParamChange: [Int: String] = [:]
    var spAttribute: [Int: String] = [:]
    var atkSubCategory: [Int: String] = [:]
    var activation: [String: String] = [:]
    var spCategoryBehavior: [String: String] = [:]
    /// v4：攻击情境键 → 中文名。
    var attackContext: [String: String] = [:]
    /// v4：SP_EFFECT_TYPE → 中文名。
    var stateInfo: [Int: String] = [:]
    /// v6：sourceSlot → 中文名 / 说明。
    var sourceSlot: [String: String] = [:]
    var sourceSlotNote: [String: String] = [:]
    /// v6：wepType → 中文名。
    var wepType: [Int: String] = [:]
    /// v6：exclusiveScope → 中文说明（值直接是字符串）。
    var exclusiveScope: [String: String] = [:]

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sourceKind = container.buffStringDictionary(.sourceKind)
        wepParamChange = Self.intLabels(container.localized(.wepParamChange))
        spAttribute = Self.intLabels(container.localized(.spAttribute))
        atkSubCategory = Self.intLabels(container.localized(.atkSubCategory))
        activation = container.localized(.activation)
        attackContext = container.localized(.attackContext)
        stateInfo = Self.intLabels(container.localized(.stateInfo))
        sourceSlot = container.localized(.sourceSlot)
        if let wrapped = try? container.decodeIfPresent(
            [String: BuffFailable<BuffSlotLabel>].self, forKey: .sourceSlot
        ) {
            sourceSlotNote = wrapped.compactMapValues { $0.value?.note }
        }
        wepType = Self.intLabels(container.localized(.wepType))
        exclusiveScope = container.buffStringDictionary(.exclusiveScope)
        var behaviors: [String: String] = [:]
        for item in container.buffArray(.spCategoryBehavior) as [BuffBehaviorRange] {
            behaviors[item.code] = item.zh
        }
        spCategoryBehavior = behaviors
    }

    private static func intLabels(_ raw: [String: String]) -> [Int: String] {
        var result: [Int: String] = [:]
        for (key, value) in raw {
            if let number = Int(key) { result[number] = value }
        }
        return result
    }

    private enum CodingKeys: String, CodingKey {
        case sourceKind, wepParamChange, spAttribute, atkSubCategory, activation, spCategoryBehavior
        case attackContext, stateInfo, sourceSlot, wepType, exclusiveScope
    }
}

struct BuffBehaviorRange: Decodable {
    let code: String
    let zh: String

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        code = container.buffString(.code, default: "unknown")
        zh = container.buffString(.zh)
    }

    private enum CodingKeys: String, CodingKey {
        case code, zh
    }
}

/// `{"<键>": {"zh": …, "en": …}}` 形状的枚举表，只取 zh。
struct BuffLocalizedLabel: Decodable {
    let zh: String

    init(from decoder: Decoder) throws {
        if let container = try? decoder.container(keyedBy: CodingKeys.self) {
            zh = container.buffString(.zh)
        } else {
            let single = try decoder.singleValueContainer()
            zh = (try? single.decode(String.self)) ?? ""
        }
    }

    private enum CodingKeys: String, CodingKey {
        case zh
    }
}

extension KeyedDecodingContainer {
    func localized(_ key: Key) -> [String: String] {
        guard let wrapped = try? decodeIfPresent([String: BuffFailable<BuffLocalizedLabel>].self, forKey: key) else { return [:] }
        return wrapped.compactMapValues { $0.value?.zh }
    }
}

// MARK: - 排名上下文

/// 当前的输出手段（决定 scope 过滤怎么走）。武器槽单独放在 `BuffRankingContext.weaponSlot`：
/// 法术也握在左右手之一，scope.weaponSlot 同样要对上（两端同一口径）。
public enum BuffDelivery: Sendable, Hashable {
    /// 武器战技命中。
    case weaponSkill
    case sorcery
    case incantation

    public var isSpell: Bool { self != .weaponSkill }
}

public struct BuffRankingContext: Sendable, Hashable {
    public var delivery: BuffDelivery
    /// 当前武器槽：1 右手 / 2 左手。scope.weaponSlot 为 0（缺失）或 3（自身）时不限。
    public var weaponSlot: Int
    /// 这次攻击属于哪些攻击子类别（战技命中 = 112 战技攻击；普通法术 = 空）。
    public var subCategories: Set<Int>
    /// 按 `SkillDamageChannel.rawValue` 索引的伤害占比（和为 1；全 0 表示没有勾选任何段）。
    public var shares: [Double]

    public init(delivery: BuffDelivery, weaponSlot: Int = 1, subCategories: Set<Int>, shares: [Double]) {
        self.delivery = delivery
        self.weaponSlot = weaponSlot == 2 ? 2 : 1
        self.subCategories = subCategories
        self.shares = shares
    }

    public init(
        delivery: BuffDelivery, weaponSlot: Int = 1,
        subCategories: Set<Int>, composition: SkillDamageComposition
    ) {
        self.init(
            delivery: delivery, weaponSlot: weaponSlot,
            subCategories: subCategories, shares: composition.shares
        )
    }

    /// 战技命中：子类别固定为 112（本作没有独立的「战技伤害 +x%」字段，
    /// 所谓强化战技都是普通 AttackRate + magicSubCategoryChange = 112）。
    public static let skillAttackSubCategory = 112
    /// 130 近战武器攻击：战技的近战命中算不算它，数据集没有给出判据，两端都保守排除。
    public static let meleeAttackSubCategory = 130

    public var hasComposition: Bool { shares.contains { $0 > 0 } }
}

public struct BuffRankingOptions: Sendable, Hashable {
    /// 打开后 activation = conditional / activated 的条目也会列出（默认不计入推荐组合）。
    public var includeConditional: Bool
    /// 打开后 target = ally（队友也能吃到的增益）一并列出。
    public var includeAllies: Bool
    /// 打开后 scope.spAttribute 限定（只对带某个属性 / 异常的攻击生效）的条目也列出。
    public var includeAttributeScoped: Bool
    /// 用户勾选的攻击情境（`enums.attackContext` 的键）。
    ///
    /// 默认空集合 = 通用排名，`scope.attackContexts` 非空的条目一律不计入
    /// （notes.ranking ④ / notes.attackContext）。勾选后的口径是「**只要命中任一已勾选的情境**
    /// 就参与乘算」——数据集里 attackContexts 是一组并列情境（例如「翻滚攻击／后跳攻击」
    /// 两种都吃得到），本来就是「或」的关系。
    public var includedAttackContexts: Set<String>
    /// 叠层阶梯（stackLadder）按满层数值计算：默认关，按数据集收录的第 1 层计。
    public var useLadderTopRates: Bool
    /// 同族效果只取最高档（按 Paramdex 行名词干合并叠加组）：默认开。
    public var mergeFamilies: Bool
    /// 同 stateInfo 视为同一状态（stackingRules 第 3 条的交叉参考，偏保守）：默认关。
    public var mergeStates: Bool
    /// 来源类型多选；空集合 = 不过滤。**只影响列表显示，不影响推荐组合**。
    public var sourceKinds: Set<String>
    /// 搜索词。**只影响列表显示，不影响推荐组合**（否则搜一个词总倍率就变了）。
    public var query: String

    public init(
        includeConditional: Bool = false,
        includeAllies: Bool = false,
        includeAttributeScoped: Bool = false,
        includedAttackContexts: Set<String> = [],
        useLadderTopRates: Bool = false,
        mergeFamilies: Bool = true,
        mergeStates: Bool = false,
        sourceKinds: Set<String> = [],
        query: String = ""
    ) {
        self.includeConditional = includeConditional
        self.includeAllies = includeAllies
        self.includeAttributeScoped = includeAttributeScoped
        self.includedAttackContexts = includedAttackContexts
        self.useLadderTopRates = useLadderTopRates
        self.mergeFamilies = mergeFamilies
        self.mergeStates = mergeStates
        self.sourceKinds = sourceKinds
        self.query = query
    }
}

// MARK: - 排名结果

public struct BuffChannelFactor: Sendable, Hashable, Identifiable {
    public let channel: SkillDamageChannel
    public let factor: Double
    public let share: Double

    public var id: Int { channel.rawValue }
}

public struct BuffRateValue: Sendable, Hashable, Identifiable {
    public let key: String
    public let zh: String
    public let value: Double
    public let valueKind: BuffRateValueKind
    public let group: String
    public let countsAsDamage: Bool
    public let conditionalDamage: Bool

    public var id: String { key }

    /// 页面里的数值文案：乘数写 ×1.11，加算写 +35，其余原样。
    public var displayValue: String {
        switch valueKind {
        case .multiplier: return "×" + BuffFormat.trim(value)
        case .flat: return (value >= 0 ? "+" : "") + BuffFormat.trim(value)
        case .flag: return value != 0 ? "开" : "关"
        case .special, .unknown: return BuffFormat.trim(value)
        }
    }
}

/// 排名卡片里的一个攻击情境选项。
public struct BuffAttackContextOption: Sendable, Hashable, Identifiable {
    public let key: String
    public let zh: String
    /// 被这个情境限定的条目数。
    public let count: Int

    public var id: String { key }

    public init(key: String, zh: String, count: Int) {
        self.key = key
        self.zh = zh
        self.count = count
    }
}

/// 叠层阶梯（v4）在页面上要展示的那几项：数据集只收第 1 层，满层数值在 `topRates` 里。
public struct BuffLadderInfo: Sendable, Hashable {
    /// 总层数。
    public let tiers: Int
    /// 满层时按当前伤害构成算出的有效倍率。
    public let topMultiplier: Double
    /// 层数是否跨局存档保留。
    public let saved: Bool
    /// 同一阶梯的所有 spEffectId（含第 1 层自己）——推荐组合里绝不能把同一阶梯的两层相乘。
    public let tierSpEffectIds: [Int]

    public init(tiers: Int, topMultiplier: Double, saved: Bool, tierSpEffectIds: [Int]) {
        self.tiers = tiers
        self.topMultiplier = topMultiplier
        self.saved = saved
        self.tierSpEffectIds = tierSpEffectIds
    }

    /// 「第 1 层 / 共 10 层」。
    public var tierText: String { "第 1 层 / 共 \(tiers) 层" }
}

public struct BuffRankingRow: Sendable, Hashable, Identifiable {
    public let spEffectId: Int
    public let displayName: String
    public let paramName: String?
    /// Σ 占比 × Π(适用倍率)；没有勾选任何段时退回「各通道乘数的最大值」。
    public let effectiveMultiplier: Double
    /// 按占比加权后的攻击力加算点数（需要绝对攻击力才能换算成倍率，只展示）。
    public let weightedFlat: Double
    public let activation: String
    public let isPassive: Bool
    public let target: String
    public let direction: String
    public let duration: Double
    public let permanent: Bool
    public let sourceKinds: [String]
    public let sourceNames: [String]
    public let isInferredSource: Bool
    public let stackGroup: String
    /// 同族键（Paramdex 行名词干）：打开「同族只取最高档」时用它把叠加组并起来。
    public let familyKey: String
    /// stateInfo 交叉参考键（stackingRules 第 3 条）；不适用时为 nil。
    public let stateCrossReferenceKey: String?
    public let stackBehavior: String
    public let stackPriority: Int
    public let stateInfo: Int
    /// stateInfo 的中文标签（enums.stateInfo），缺标签时是裸数字。
    public let stateInfoLabel: String
    public let spCategory: Int
    /// `scope.attackContexts` 原始键；非空 = 只在这些攻击情境下才吃得到。
    public let attackContexts: [String]
    /// 上面那些键的中文名（致命一击／处决…），页面直接显示。
    public let attackContextLabels: [String]
    /// 非 nil = 这条只是叠层阶梯的第 1 层，`ladder.topMultiplier` 才是满层有效倍率。
    public let ladder: BuffLadderInfo?
    public let channelFactors: [BuffChannelFactor]
    public let rateValues: [BuffRateValue]
    public let scopeNotes: [String]
    public let conditionNotes: [String]
    public let descZh: String?
    /// v5：status 组的加算是玩家自伤（不是「攻击附带累积」）。伤害乘积不受影响，只打标。
    public let selfInflictedStatus: Bool
    /// 列表搜索用的折叠串；搜索是**显示层**过滤，不参与排名与推荐组合。
    public let searchKey: String

    public var id: Int { spEffectId }

    /// 只在某种攻击情境下生效（默认不进通用排名，勾选情境后才出现）。
    public var isContextGated: Bool { !attackContexts.isEmpty }

    /// 对当前伤害构成真有增益：倍率大于 1，或有正的攻击力加算。
    /// 与 Windows 端 effectiveFor().useful 同一口径——「增伤排名」不列 ×0.9 这种反向条目。
    public var isUseful: Bool { effectiveMultiplier > 1.0000001 || weightedFlat > 0 }

    /// 有效倍率本身有意义（> 1）。
    public var hasMultiplier: Bool { effectiveMultiplier > 1.0000001 }

    public var durationText: String {
        if permanent || duration < 0 { return "永久" }
        if duration == 0 { return "瞬间" }
        return BuffFormat.trim(duration) + " 秒"
    }
}

/// 作用域判定不通过的原因。`isAttributeScoped` 表示「其余各关都过了、单单被
/// scope.spAttribute 拦下」——页面把这一类单独计数（打开开关后就会进榜）。
public struct BuffScopeRejection: Sendable, Hashable {
    public let reason: String
    public let isAttributeScoped: Bool

    public init(reason: String, isAttributeScoped: Bool = false) {
        self.reason = reason
        self.isAttributeScoped = isAttributeScoped
    }
}

public struct BuffRankingResult: Sendable, Hashable {
    /// 对当前伤害构成真正有增益（或有攻击力加算）的条目，按有效倍率降序。
    public let rows: [BuffRankingRow]
    /// 通过了 target / direction / activation / scope 四关的条目总数。
    public let candidateCount: Int
    /// 其中「对当前构成没有任何增益」（例如纯斩击构成里的火属性增伤）而未列出的条目数。
    public let neutralCount: Int
    /// 其它各关都过了、只因为 `scope.attackContexts` 限定（致命一击 / 突刺反击 / 蓄力…）
    /// 而被拦下的条目数——勾选对应情境后它们才会进榜，页面在汇总行说明。
    public let contextScopedCount: Int
    /// 其它各关都过了、只因为 `scope.spAttribute` 限定（只对带某种属性 / 异常的攻击生效）
    /// 而被拦下的条目数——打开「包含属性／异常限定」后才会进榜。
    public let attributeScopedCount: Int
    /// 作用域不符（武器槽 / 投掷 / 法术 / 攻击子类别 / 物理攻击类型）而未计入的条目数。
    /// 不含情境限定与属性限定那两类——它们是「开关打开后才计入」，另外计数。
    public let scopeRejectedCount: Int
    /// 排除原因的分项：原因串 → 条数。页面照它在汇总行下方展开，
    /// 与 Windows 端 excluded.scopeReasons 同一口径（含情境限定那一条）。
    public let scopeReasons: [String: Int]

    public init(
        rows: [BuffRankingRow],
        candidateCount: Int,
        neutralCount: Int,
        contextScopedCount: Int = 0,
        attributeScopedCount: Int = 0,
        scopeRejectedCount: Int = 0,
        scopeReasons: [String: Int] = [:]
    ) {
        self.rows = rows
        self.candidateCount = candidateCount
        self.neutralCount = neutralCount
        self.contextScopedCount = contextScopedCount
        self.attributeScopedCount = attributeScopedCount
        self.scopeRejectedCount = scopeRejectedCount
        self.scopeReasons = scopeReasons
    }

    /// 分项按条数降序（同数按原因串排），供页面直接展示。
    public var scopeReasonBreakdown: [(reason: String, count: Int)] {
        scopeReasons
            .map { (reason: $0.key, count: $0.value) }
            .sorted { $0.count == $1.count ? $0.reason < $1.reason : $0.count > $1.count }
    }

    public static let empty = BuffRankingResult(
        rows: [], candidateCount: 0, neutralCount: 0, contextScopedCount: 0, attributeScopedCount: 0
    )
}

public struct BuffStackPlan: Sendable, Hashable {
    public let picks: [BuffRankingRow]
    /// 各组选出的一条连乘后的总倍率。
    public let total: Double
    public let groupCount: Int
    /// 因为同组已有更强的一条而被略过的条目数。
    public let droppedByStacking: Int
    /// 被用户勾掉的条目数。
    public let excludedCount: Int

    public static let empty = BuffStackPlan(
        picks: [], total: 1, groupCount: 0, droppedByStacking: 0, excludedCount: 0
    )
}

public enum BuffFormat {
    /// 去掉多余 0：1.250 → 1.25、2.0 → 2。
    public static func trim(_ value: Double, digits: Int = 3) -> String {
        guard value.isFinite else { return "—" }
        var text = String(format: "%.\(digits)f", value)
        if text.contains(".") {
            while text.hasSuffix("0") { text.removeLast() }
            if text.hasSuffix(".") { text.removeLast() }
        }
        return text.isEmpty ? "0" : text
    }

    public static func multiplier(_ value: Double, digits: Int = 3) -> String {
        "×" + trim(value, digits: digits)
    }

    /// 相对增幅：1.153 → +15.3%。
    public static func gain(_ value: Double) -> String {
        let percent = (value - 1) * 100
        let sign = percent >= 0 ? "+" : ""
        return sign + String(format: "%.1f", percent) + "%"
    }

    public static func percent(_ share: Double) -> String {
        String(format: "%.1f", share * 100) + "%"
    }
}

// MARK: - 索引（预计算 + 排名）

public struct BuffRankerIndex: Sendable {
    /// 每条 buff 的「与选段无关」的预计算结果。
    struct Profile: Sendable {
        /// 按通道索引的乘数（damage 层 × attackPower 层已经乘在一起）。
        let channelMultiplier: [Double]
        /// 按 `SkillElement.allCases` 索引的攻击力加算点数。
        let elementFlat: [Double]
        let maxMultiplier: Double
        let hasRankingRate: Bool
        let hasMultiplier: Bool
        let searchKey: String
        let sourceKinds: [String]
        let sourceNames: [String]
        let rateValues: [BuffRateValue]
        let scopeNotes: [String]
        let conditionNotes: [String]
        /// `scope.attackContexts` 的中文名，建索引时查好。
        let attackContextLabels: [String]
        /// 叠层阶梯满层时的通道乘数（与选段无关，同样建索引时算好）。
        let ladderChannelMultiplier: [Double]?
        /// 同族键与 stateInfo 交叉参考键（推荐组合的可选合并用）。
        let familyKey: String
        let stateCrossReferenceKey: String?
    }

    public let dataset: BuffDataset
    let profiles: [Profile]
    /// 数据集里出现过的来源类型（按 enums.sourceKind 的顺序，供筛选器用）。
    public let availableSourceKinds: [String]
    /// 被 scope.spAttribute 限定、默认不计入的条目数（页面底部说明用）。
    public let attributeScopedCount: Int
    /// 数据集里出现过的攻击情境（供排名卡片的情境多选用），按固定顺序。
    public let availableAttackContexts: [BuffAttackContextOption]
    /// 被 scope.attackContexts 限定、默认不计入通用排名的条目总数（页面底部说明用）。
    public let contextScopedTotal: Int
    /// 带 stackLadder（叠层阶梯第 1 层）的条目数。
    public let ladderCount: Int
    /// v5 selfInflictedStatus（自伤型异常累积）的条目数。
    public let selfInflictedStatusCount: Int
    /// 只标 130（近战武器攻击）而没有 112（战技攻击）的条目数（页面底部说明用；
    /// 与 Windows 端照 scopeInfo(...).meleeOnly 现算的同一个数）。
    public let meleeOnlyCount: Int

    public init(dataset: BuffDataset) throws {
        guard !dataset.buffs.isEmpty else { throw BuffDataError.empty }
        self.dataset = dataset

        let fieldByKey = Dictionary(dataset.rateFields.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
        var profiles: [Profile] = []
        profiles.reserveCapacity(dataset.buffs.count)
        var kinds: [String] = []
        var seenKinds: Set<String> = []
        var attributeScoped = 0
        var contextCounts: [String: Int] = [:]
        var contextScoped = 0

        for buff in dataset.buffs {
            let profile = Self.makeProfile(for: buff, fields: fieldByKey, dataset: dataset)
            profiles.append(profile)
            for kind in buff.sourceKinds where seenKinds.insert(kind).inserted {
                kinds.append(kind)
            }
            if buff.scope.spAttribute != nil { attributeScoped += 1 }
            if buff.scope.isContextGated {
                contextScoped += 1
                // chip 上的数字只统计**带伤害倍率字段**的条目：这排 chip 是排名列表的筛选器，
                // 永远进不了榜的条目不该把数字撑大。与 Windows 端 availableContexts 同一口径。
                guard profile.hasRankingRate else { continue }
                for context in buff.scope.attackContexts { contextCounts[context, default: 0] += 1 }
            }
        }

        self.profiles = profiles
        availableSourceKinds = kinds.sorted { lhs, rhs in
            let left = Self.sourceKindOrder.firstIndex(of: lhs) ?? Self.sourceKindOrder.count
            let right = Self.sourceKindOrder.firstIndex(of: rhs) ?? Self.sourceKindOrder.count
            return left == right ? lhs < rhs : left < right
        }
        attributeScopedCount = attributeScoped
        contextScopedTotal = contextScoped
        ladderCount = dataset.buffs.reduce(0) { $0 + ($1.stackLadder == nil ? 0 : 1) }
        selfInflictedStatusCount = dataset.buffs.reduce(0) { $0 + ($1.selfInflictedStatus ? 1 : 0) }
        meleeOnlyCount = dataset.buffs.reduce(0) { $0 + ($1.scope.isMeleeOnly ? 1 : 0) }
        availableAttackContexts = contextCounts
            .map { key, count in
                BuffAttackContextOption(key: key, zh: dataset.attackContextLabel(key), count: count)
            }
            .sorted { lhs, rhs in
                let left = Self.attackContextOrder.firstIndex(of: lhs.key) ?? Self.attackContextOrder.count
                let right = Self.attackContextOrder.firstIndex(of: rhs.key) ?? Self.attackContextOrder.count
                return left == right ? lhs.key < rhs.key : left < right
            }
    }

    /// 情境多选的固定顺序（enums.attackContext 的 15 个键；数据集里没出现的不显示）。
    /// 与 Windows 端 ATTACK_CONTEXT_ORDER 逐项相同。
    public static let attackContextOrder = [
        "criticalHit", "thrustingCounter", "guardCounter", "chainFinisher",
        "chargedHeavyAttack", "chargedSkill", "chargedSpell",
        "jumpAttack", "dashAttack", "rollingAttack", "backstepAttack",
        "initialAttack", "horsebackAttack", "twoHanded", "dualWield"
    ]

    public init(data: Data) throws {
        try self.init(dataset: BuffDataset.decode(from: data))
    }

    /// 第 `index` 条 buff 有没有 countsAsDamage 的倍率／加算字段（自检用）。
    public func hasRankingRate(at index: Int) -> Bool {
        profiles.indices.contains(index) ? profiles[index].hasRankingRate : false
    }

    /// 第 `index` 条 buff 的可检索字符串（自检用；两端取同一个字段并集）。
    public func searchKey(at index: Int) -> String {
        profiles.indices.contains(index) ? profiles[index].searchKey : ""
    }

    /// 筛选器里来源类型的固定顺序（数据集里没出现的排在最后）。
    static let sourceKindOrder = [
        "relicAffix", "weaponPassive", "accessory", "goods", "spell", "heroSkill", "permanent", "other"
    ]

    // MARK: 预计算

    /// 哪些通道吃这个倍率字段。
    static func channels(for key: String) -> [SkillDamageChannel] {
        let stem = key
            .replacingOccurrences(of: "AttackPowerRate", with: "")
            .replacingOccurrences(of: "AttackRate", with: "")
        switch stem {
        case "physics": return SkillDamageChannel.allCases.filter(\.isPhysical)
        case "magic": return [.magic]
        case "fire": return [.fire]
        case "thunder": return [.lightning]
        case "dark": return [.holy]
        case "slash": return [.slash]
        case "blow": return [.strike]
        case "thrust": return [.pierce]
        case "neutral": return [.standard]
        default: return []
        }
    }

    /// 攻击力加算字段对应的属性槽。
    static func element(forFlat key: String) -> SkillElement? {
        switch key {
        case "physicsAttackPower": return .physical
        case "magicAttackPower": return .magic
        case "fireAttackPower": return .fire
        case "thunderAttackPower": return .lightning
        case "darkAttackPower": return .holy
        default: return nil
        }
    }

    static func makeProfile(
        for buff: BuffEntry,
        fields: [String: BuffRateField],
        dataset: BuffDataset
    ) -> Profile {
        var channelMultiplier = Array(repeating: 1.0, count: SkillDamageChannel.allCases.count)
        var elementFlat = Array(repeating: 0.0, count: SkillElement.allCases.count)
        var rateValues: [BuffRateValue] = []
        var hasMultiplier = false
        var hasFlat = false

        // scope.atkAttribute：只作用于某个物理攻击类型时，倍率只落在那个通道上。
        let restricted: Set<SkillDamageChannel>? = buff.scope.atkAttribute.flatMap { code in
            (0...3).contains(code) ? [SkillDamageChannel.physical(code: code)] : nil
        }

        for (key, value) in buff.rates.sorted(by: { $0.key < $1.key }) {
            let field = fields[key]
            rateValues.append(
                BuffRateValue(
                    key: key,
                    zh: field?.zh ?? key,
                    value: value,
                    valueKind: field?.valueKind ?? .unknown,
                    group: field?.group ?? "",
                    countsAsDamage: field?.countsAsDamage ?? false,
                    conditionalDamage: field?.conditionalDamage ?? false
                )
            )
            guard let field else { continue }
            if field.isRankingMultiplier, value.isFinite, value > 0 {
                var targets = Self.channels(for: key)
                if let restricted { targets = targets.filter { restricted.contains($0) } }
                guard !targets.isEmpty else { continue }
                for channel in targets { channelMultiplier[channel.rawValue] *= value }
                hasMultiplier = true
            } else if field.isRankingFlat, value.isFinite, value != 0 {
                if let element = Self.element(forFlat: key),
                   let position = SkillElement.allCases.firstIndex(of: element) {
                    elementFlat[position] += value
                    hasFlat = true
                }
            }
        }

        rateValues.sort { lhs, rhs in
            if lhs.countsAsDamage != rhs.countsAsDamage { return lhs.countsAsDamage }
            return lhs.key < rhs.key
        }

        // 叠层阶梯：满层数值同样在建索引时算好，选段变化时只做加权求和。
        let ladderChannelMultiplier = buff.stackLadder.map {
            Self.channelMultipliers(rates: $0.topRates, fields: fields, restricted: restricted)
        }

        let attackContextLabels = buff.scope.attackContexts.map { dataset.attackContextLabel($0) }

        var scopeNotes: [String] = []
        if !attackContextLabels.isEmpty {
            scopeNotes.append(
                "只在这些攻击情境下生效：" + attackContextLabels.joined(separator: "／")
                    + "（默认不计入通用排名，需在上方勾选对应情境）"
            )
        }
        if let slot = buff.scope.weaponSlot, let label = dataset.weaponSlotLabels[slot] {
            scopeNotes.append("武器槽：" + label)
        }
        if !buff.scope.subCategories.isEmpty {
            let labels = buff.scope.subCategories.map { dataset.subCategoryLabels[$0] ?? "子类别 \($0)" }
            scopeNotes.append("只作用于：" + labels.joined(separator: "／"))
        }
        if let attribute = buff.scope.spAttribute {
            scopeNotes.append("限定属性攻击：" + (dataset.spAttributeLabels[attribute] ?? "属性 \(attribute)"))
        }
        if let attribute = buff.scope.atkAttribute {
            scopeNotes.append("限定物理攻击类型：" + SkillDamageChannel.physical(code: attribute).titleZh)
        }
        var delivery: [String] = []
        if buff.scope.affectsSorcery { delivery.append("魔法") }
        if buff.scope.affectsIncantation { delivery.append("祷告") }
        if buff.scope.affectsShaman { delivery.append("秘术") }
        if buff.scope.affectsThrow { delivery.append("投掷") }
        if !delivery.isEmpty { scopeNotes.append("同时作用于：" + delivery.joined(separator: "／")) }

        var conditionNotes: [String] = []
        for (key, value) in buff.conditions.sorted(by: { $0.key < $1.key }) {
            let label = dataset.conditionFieldLabels[key] ?? key
            conditionNotes.append("\(label)：\(BuffFormat.trim(value))")
        }
        for (key, value) in buff.triggered.sorted(by: { $0.key < $1.key }) where value != 0 {
            conditionNotes.append("触发：\(key)")
        }

        let kinds = buff.sourceKinds
        // 展示用的来源名只取前 6 个（行上放不下更多）。
        var names: [String] = []
        var seenNames: Set<String> = []
        for source in buff.sources.prefix(6) where seenNames.insert(source.displayName).inserted {
            names.append(source.displayName)
        }
        // 可检索的来源名要**全部**收进来：搜索框按前 6 个截断会让第 7 个来源搜不到，
        // 与 Windows 端（收全部来源的 nameZh / nameEn / effectNameZh）对不上。
        var searchableNames: [String] = []
        var seenSearchable: Set<String> = []
        for source in buff.sources {
            for name in [source.nameZh, source.nameEn, source.effectNameZh] {
                guard let name, !name.isEmpty, seenSearchable.insert(name).inserted else { continue }
                searchableNames.append(name)
            }
        }

        // 可检索字段两端取并集：名称（中英 + displayName）+ paramName + descZh
        // + 全部来源名 + 来源类型中文标签 + spEffectId。
        // 与 Windows 端 indexBuff 的 searchText 逐项相同——同一个关键词必须在两端命中同一批行。
        let searchParts = [
            buff.displayName,
            buff.nameZh ?? "",
            buff.nameEn ?? "",
            buff.displayNameEn ?? "",
            buff.paramName ?? "",
            buff.descZh ?? "",
            searchableNames.joined(separator: " "),
            kinds.map { dataset.sourceKindLabel($0) }.joined(separator: " "),
            String(buff.spEffectId)
        ]

        return Profile(
            channelMultiplier: channelMultiplier,
            elementFlat: elementFlat,
            maxMultiplier: channelMultiplier.max() ?? 1,
            hasRankingRate: hasMultiplier || hasFlat,
            hasMultiplier: hasMultiplier,
            searchKey: searchParts.joined(separator: " ").foldedForSearch,
            sourceKinds: kinds,
            sourceNames: names,
            rateValues: rateValues,
            scopeNotes: scopeNotes,
            conditionNotes: conditionNotes,
            attackContextLabels: attackContextLabels,
            ladderChannelMultiplier: ladderChannelMultiplier,
            familyKey: buff.familyKey,
            stateCrossReferenceKey: buff.stateCrossReferenceKey
        )
    }

    /// 只算「各通道乘数」，不产生展示用的 rateValues（叠层阶梯的满层数值用）。
    static func channelMultipliers(
        rates: [String: Double],
        fields: [String: BuffRateField],
        restricted: Set<SkillDamageChannel>?
    ) -> [Double] {
        var result = Array(repeating: 1.0, count: SkillDamageChannel.allCases.count)
        for (key, value) in rates {
            guard let field = fields[key], field.isRankingMultiplier, value.isFinite, value > 0 else { continue }
            var targets = Self.channels(for: key)
            if let restricted { targets = targets.filter { restricted.contains($0) } }
            for channel in targets { result[channel.rawValue] *= value }
        }
        return result
    }

    // MARK: 过滤

    /// notes.ranking ①②③⑤：与当前选段无关的那几步。
    ///
    /// **不含搜索词与来源类型**：那两个是列表的显示筛选（`matchesDisplayFilters`），
    /// 放进这里会让「搜一个词」把推荐组合的总倍率也改掉。
    func passesEntryFilters(_ buff: BuffEntry, _ profile: Profile, _ options: BuffRankingOptions) -> Bool {
        // ① target：self 恒取；ally 由开关控制；summon / enemy 一律排除。
        switch buff.target {
        case "self": break
        case "ally": if !options.includeAllies { return false }
        default: return false
        }
        // ② direction：只要 increase / mixed。
        guard buff.direction == "increase" || buff.direction == "mixed" else { return false }
        // ③ activation：只有 passive 默认计入。
        if !buff.isPassive && !options.includeConditional { return false }
        // ⑤ 必须至少有一个 countsAsDamage 的倍率或加算字段。
        guard profile.hasRankingRate else { return false }
        return true
    }

    /// 列表的显示筛选：搜索词 + 来源类型。与排名、推荐组合无关。
    func matchesDisplayFilters(_ row: BuffRankingRow, _ options: BuffRankingOptions) -> Bool {
        if !options.sourceKinds.isEmpty && row.sourceKinds.allSatisfy({ !options.sourceKinds.contains($0) }) {
            return false
        }
        let needle = options.query.foldedForSearch
        if !needle.isEmpty && !row.searchKey.contains(needle) { return false }
        return true
    }

    /// 排名列表里当前可见的那些行（推荐组合仍然用全部行）。
    public func visibleRows(_ rows: [BuffRankingRow], options: BuffRankingOptions) -> [BuffRankingRow] {
        guard !options.sourceKinds.isEmpty || !options.query.isEmpty else { return rows }
        return rows.filter { matchesDisplayFilters($0, options) }
    }

    /// notes.ranking ④ 的第一小步：攻击情境闸门。
    ///
    /// `scope.attackContexts` 非空 = 这条倍率只在某种攻击情境下才吃得到，**默认不得计入
    /// 通用排名**；用户勾选了其中任一情境才放行。这类条目本身是 passive，
    /// 第③步（activation）拦不住它们，必须单独走这一步。
    func attackContextAllowed(_ buff: BuffEntry, options: BuffRankingOptions) -> Bool {
        let contexts = buff.scope.attackContexts
        guard !contexts.isEmpty else { return true }
        return contexts.contains { options.includedAttackContexts.contains($0) }
    }

    /// notes.ranking ④：scope 是否作用于当前输出手段（含攻击情境闸门）。
    func scopeMatches(_ buff: BuffEntry, context: BuffRankingContext, options: BuffRankingOptions) -> Bool {
        attackContextAllowed(buff, options: options)
            && scopeMatchesIgnoringAttackContexts(buff, context: context, options: options)
    }

    /// scope 的其余各项（投掷限定 / 武器槽 / 属性限定 / 魔法 / 祷告 / 攻击子类别 / 物理子类型）。
    /// 顺序与 Windows 端 scopeVerdict 一致，分项原因也一一对应。
    func scopeMatchesIgnoringAttackContexts(
        _ buff: BuffEntry, context: BuffRankingContext, options: BuffRankingOptions
    ) -> Bool {
        scopeVerdict(buff, context: context, options: options) == nil
    }

    /// 不适用的原因（nil = 作用域匹配）。页面把它按原因分项展示。
    ///
    /// **计数点**：`isAttributeScoped` 只在「其余各关都过、单单被 scope.spAttribute 拦下」时为真。
    /// 页面把这一类单独计数（打开「包含属性／异常限定」后它们就会进榜），其余一律算作用域不符。
    /// 与 Windows 端 candidateFilter 里 `verdict.attribute` / `"scope"` 的分支同一口径——
    /// 只要把计数挪到「返回非 nil 就算」的位置，被武器槽 / 投掷 / 子类别拦下的条目就会混进来，
    /// 两端的「属性／异常限定 N 条未计入」立刻对不上（右手 33 vs 45）。
    func scopeVerdict(
        _ buff: BuffEntry, context: BuffRankingContext, options: BuffRankingOptions
    ) -> BuffScopeRejection? {
        let scope = buff.scope
        // 页面自担判定①：只点亮 affectsThrow ＝ 只作用于致命一击 / 投掷（没有 attackContexts 时才用）。
        if scope.isThrowOnly { return BuffScopeRejection(reason: "只作用于致命一击／投掷攻击") }
        // wepParamChange：0（缺失）与 3（自身）不限，1 / 2 必须对上当前手，其余（4 踢击）不适用。
        if let weaponSlot = scope.weaponSlot, weaponSlot != 0, weaponSlot != 3,
           weaponSlot != context.weaponSlot {
            switch weaponSlot {
            case 1: return BuffScopeRejection(reason: "只作用于右手武器")
            case 2: return BuffScopeRejection(reason: "只作用于左手武器")
            default: return BuffScopeRejection(reason: "只作用于别的武器槽（踢击等）")
            }
        }
        // scope.spAttribute：只对带某种属性 / 异常的攻击生效，默认不计入。
        if scope.isAttributeScoped && !options.includeAttributeScoped {
            return BuffScopeRejection(reason: "限定属性／异常攻击", isAttributeScoped: true)
        }
        switch context.delivery {
        case .weaponSkill:
            // 页面自担判定②③：只作用于法术的条目、以及只标 130 没标 112 的近战条目。
            if scope.isSpellOnly { return BuffScopeRejection(reason: "只作用于魔法／祷告") }
            if scope.isMeleeOnly { return BuffScopeRejection(reason: "只作用于近战武器攻击子类别（130）") }
        case .sorcery:
            guard scope.affectsSorcery else { return BuffScopeRejection(reason: "不作用于魔法") }
        case .incantation:
            guard scope.affectsIncantation else { return BuffScopeRejection(reason: "不作用于祷告") }
        }
        if !scope.subCategories.isEmpty {
            guard !context.subCategories.isEmpty,
                  scope.subCategories.contains(where: { context.subCategories.contains($0) })
            else {
                return BuffScopeRejection(
                    reason: context.delivery == .weaponSkill
                        ? "限定别的攻击子类别"
                        : "限定法术流派／蓄力，数据集无流派字段"
                )
            }
        }
        if let attribute = scope.atkAttribute, (0...3).contains(attribute), context.hasComposition {
            let channel = SkillDamageChannel.physical(code: attribute)
            guard context.shares.indices.contains(channel.rawValue), context.shares[channel.rawValue] > 0 else {
                return BuffScopeRejection(reason: "限定物理攻击类型")
            }
        }
        return nil
    }

    // MARK: 计算

    /// 有效倍率 = Σ_通道 占比 × Π(作用于该通道的倍率)。
    ///
    /// 没有勾选任何段（占比全 0）时一律返回 1，也就是「算不出」——排名必须建立在一个真实的
    /// 伤害构成上，退回「各通道乘数的最大值」会让纯物理构成里的火属性增伤看起来也有收益。
    /// 与 Windows 端 effectiveFor 同一口径。
    /// `useLadderTop` = 叠层阶梯按满层数值计算。
    func effectiveMultiplier(_ profile: Profile, shares: [Double], useLadderTop: Bool = false) -> Double {
        let table = (useLadderTop ? profile.ladderChannelMultiplier : nil) ?? profile.channelMultiplier
        return Self.effectiveMultiplier(channelMultiplier: table, shares: shares, fallback: 1)
    }

    static func effectiveMultiplier(
        channelMultiplier: [Double], shares: [Double], fallback: Double = 1
    ) -> Double {
        var total = 0.0
        var weight = 0.0
        for channel in SkillDamageChannel.allCases {
            let index = channel.rawValue
            guard shares.indices.contains(index), channelMultiplier.indices.contains(index) else { continue }
            let share = shares[index]
            guard share > 0 else { continue }
            total += share * channelMultiplier[index]
            weight += share
        }
        guard weight > 0 else { return fallback }
        return total / weight
    }

    func weightedFlat(_ profile: Profile, shares: [Double]) -> Double {
        var total = 0.0
        var weight = 0.0
        for (position, element) in SkillElement.allCases.enumerated() {
            let elementShare = SkillDamageChannel.allCases
                .filter { $0.element == element }
                .reduce(0.0) { partial, channel in
                    shares.indices.contains(channel.rawValue) ? partial + shares[channel.rawValue] : partial
                }
            guard elementShare > 0 else { continue }
            total += elementShare * profile.elementFlat[position]
            weight += elementShare
        }
        // 没有构成就折不出加权点数（与 Windows 端一致，返回 0 而不是最大值）。
        guard weight > 0 else { return 0 }
        return total / weight
    }

    func makeRow(index: Int, context: BuffRankingContext, options: BuffRankingOptions) -> BuffRankingRow {
        let buff = dataset.buffs[index]
        let profile = profiles[index]
        let shares = context.shares
        let factors = SkillDamageChannel.allCases.compactMap { channel -> BuffChannelFactor? in
            let position = channel.rawValue
            let share = shares.indices.contains(position) ? shares[position] : 0
            let factor = profile.channelMultiplier[position]
            guard share > 0 || abs(factor - 1) > 0.0000001 else { return nil }
            return BuffChannelFactor(channel: channel, factor: factor, share: share)
        }
        // 叠层阶梯：数据集只收第 1 层，页面要同时给出满层数值，否则 ×1.007 看着像噪音。
        let ladder = buff.stackLadder.flatMap { info -> BuffLadderInfo? in
            guard let multipliers = profile.ladderChannelMultiplier else { return nil }
            return BuffLadderInfo(
                tiers: info.tiers,
                topMultiplier: Self.effectiveMultiplier(channelMultiplier: multipliers, shares: shares),
                saved: info.saved,
                tierSpEffectIds: ([buff.spEffectId] + info.tierSpEffectIds).sorted()
            )
        }
        return BuffRankingRow(
            spEffectId: buff.spEffectId,
            displayName: buff.displayName,
            paramName: buff.paramName,
            effectiveMultiplier: effectiveMultiplier(
                profile, shares: shares, useLadderTop: options.useLadderTopRates
            ),
            weightedFlat: weightedFlat(profile, shares: shares),
            activation: buff.activation,
            isPassive: buff.isPassive,
            target: buff.target,
            direction: buff.direction,
            duration: buff.duration,
            permanent: buff.permanent,
            sourceKinds: profile.sourceKinds,
            sourceNames: profile.sourceNames,
            isInferredSource: buff.isInferredSource,
            stackGroup: buff.stacking.group,
            familyKey: profile.familyKey,
            stateCrossReferenceKey: profile.stateCrossReferenceKey,
            stackBehavior: buff.stacking.spCategoryBehavior,
            stackPriority: buff.stacking.categoryPriority,
            stateInfo: buff.stacking.stateInfo,
            stateInfoLabel: dataset.stateInfoLabel(buff.stacking.stateInfo),
            spCategory: buff.stacking.spCategory,
            attackContexts: buff.scope.attackContexts,
            attackContextLabels: profile.attackContextLabels,
            ladder: ladder,
            channelFactors: factors,
            rateValues: profile.rateValues,
            scopeNotes: profile.scopeNotes,
            conditionNotes: profile.conditionNotes,
            descZh: buff.descZh,
            selfInflictedStatus: buff.selfInflictedStatus,
            searchKey: profile.searchKey
        )
    }

    /// 按当前输出手段与筛选条件排好序的条目（有效倍率降序）。
    ///
    /// 只做一次线性扫描 + 排序；每条的通道乘数在建索引时已经算好，
    /// 选段变化时这里只是「9 个通道的加权求和」，几百条不会卡。
    ///
    /// 「对当前伤害构成完全没有增益」的条目不列出（例如纯物理构成里的火属性增伤），
    /// 它们的条数记在 `neutralCount` 里，页面在底部说明。
    public func rankResult(
        context: BuffRankingContext,
        options: BuffRankingOptions = BuffRankingOptions()
    ) -> BuffRankingResult {
        var rows: [BuffRankingRow] = []
        rows.reserveCapacity(128)
        var candidates = 0
        var neutral = 0
        var contextScoped = 0
        var attributeScoped = 0
        var scopeRejected = 0
        var scopeReasons: [String: Int] = [:]
        for index in dataset.buffs.indices {
            let buff = dataset.buffs[index]
            let profile = profiles[index]
            guard passesEntryFilters(buff, profile, options) else { continue }
            // notes.ranking ④：情境限定的条目默认不进通用排名，单独计数供页面说明
            //（顺序与 Windows 端一致：情境闸门在其余 scope 判定之前）。
            guard attackContextAllowed(buff, options: options) else {
                contextScoped += 1
                scopeReasons[Self.contextGateReason, default: 0] += 1
                continue
            }
            if let rejection = scopeVerdict(buff, context: context, options: options) {
                // 属性／异常限定单独计数：它不是「不适用」，而是「打开开关后才计入」，
                // 所以**只有 scopeVerdict 明确判成这一类**才记在它头上（与 Windows 同一判定点）。
                if rejection.isAttributeScoped {
                    attributeScoped += 1
                } else {
                    scopeRejected += 1
                    scopeReasons[rejection.reason, default: 0] += 1
                }
                continue
            }
            candidates += 1
            let row = makeRow(index: index, context: context, options: options)
            guard row.isUseful else {
                neutral += 1
                continue
            }
            rows.append(row)
        }
        rows.sort { lhs, rhs in
            if lhs.effectiveMultiplier != rhs.effectiveMultiplier {
                return lhs.effectiveMultiplier > rhs.effectiveMultiplier
            }
            if lhs.weightedFlat != rhs.weightedFlat { return lhs.weightedFlat > rhs.weightedFlat }
            return lhs.spEffectId < rhs.spEffectId
        }
        return BuffRankingResult(
            rows: rows,
            candidateCount: candidates,
            neutralCount: neutral,
            contextScopedCount: contextScoped,
            attributeScopedCount: attributeScoped,
            scopeRejectedCount: scopeRejected,
            scopeReasons: scopeReasons
        )
    }

    /// 情境闸门在分项里的原因串，与 Windows 端 scopeVerdict 返回的同一个字符串。
    public static let contextGateReason = "只在特定攻击情境成立"

    public func rank(
        context: BuffRankingContext,
        options: BuffRankingOptions = BuffRankingOptions()
    ) -> [BuffRankingRow] {
        rankResult(context: context, options: options).rows
    }

    /// 推荐组合（stackingRules 第 2 条）：同一 `stacking.group` 只留一条，
    /// applyHighest 组按 categoryPriority 更优（数值小）的一份，其余组取倍率最高的一条；
    /// 不同组相互独立，各自倍率相乘。
    ///
    /// **这是参数结构推断出来的理论叠加上限**，既没有木桩实测，也没有考虑遗物 / 护符
    /// 的槽位数量与实际可获得性，页面必须原样标注。
    ///
    /// - Parameters:
    ///   - excluded: 用户勾掉的条目（不参与组合）。
    ///   - includedConditional: 用户明确勾选纳入的条件型条目（activation ≠ passive）；
    ///     其余条件型按 notes.ranking ③ 默认不计入。
    public func stackPlan(
        rows: [BuffRankingRow],
        excluded: Set<Int> = [],
        includedConditional: Set<Int> = [],
        options: BuffRankingOptions = BuffRankingOptions()
    ) -> BuffStackPlan {
        var pool: [BuffRankingRow] = []
        var excludedCount = 0
        for row in rows {
            if excluded.contains(row.spEffectId) {
                excludedCount += 1
                continue
            }
            // 只有 passive 才默认进组合；条件型必须由用户单独勾选纳入。
            guard row.isPassive || includedConditional.contains(row.spEffectId) else { continue }
            guard row.effectiveMultiplier > 1.0000001 else { continue }
            pool.append(row)
        }

        let buckets = Self.bucketRows(pool, mergeFamilies: options.mergeFamilies, mergeStates: options.mergeStates)
        var best: [String: BuffRankingRow] = [:]
        var dropped = 0
        for (key, members) in buckets {
            var champion: BuffRankingRow?
            for row in members {
                guard let current = champion else {
                    champion = row
                    continue
                }
                dropped += 1
                if Self.prefers(row, over: current) { champion = row }
            }
            best[key] = champion
        }

        let picks = best.values.sorted { lhs, rhs in
            lhs.effectiveMultiplier == rhs.effectiveMultiplier
                ? lhs.spEffectId < rhs.spEffectId
                : lhs.effectiveMultiplier > rhs.effectiveMultiplier
        }
        let total = picks.reduce(1.0) { $0 * $1.effectiveMultiplier }
        return BuffStackPlan(
            picks: picks,
            total: total,
            groupCount: picks.count,
            droppedByStacking: dropped,
            excludedCount: excludedCount
        )
    }

    /// 去重用的分组键：一般是 `stacking.group`；叠层阶梯的各层共用一个键，
    /// 保证同一条阶梯**绝不会有两层同时进组合相乘**（当前数据集每条阶梯只收第 1 层，
    /// 将来收全层时这一层保护才会真正派上用场）。与 Windows 端 stackKeyFor 同一口径。
    static func stackKey(for row: BuffRankingRow) -> String {
        guard let ladder = row.ladder, let first = ladder.tierSpEffectIds.first else { return row.stackGroup }
        return "ladder#\(first)"
    }

    /// 并查集分桶：先按 stackKey 分组，打开「同族只取最高档」时再把同族的组并起来，
    /// 打开「同 stateInfo 视为同一状态」时再按 stateInfo 并一次。
    /// 与 Windows 端 bucketRows 同一口径（同一套键名、同一个合并顺序）。
    static func bucketRows(
        _ rows: [BuffRankingRow], mergeFamilies: Bool, mergeStates: Bool
    ) -> [String: [BuffRankingRow]] {
        var parent: [String: String] = [:]

        func find(_ key: String) -> String {
            var root = key
            while let next = parent[root], next != root { root = next }
            var current = key
            while let next = parent[current], next != current {
                parent[current] = root
                current = next
            }
            parent[key] = root
            return root
        }

        func union(_ lhs: String, _ rhs: String) {
            if parent[lhs] == nil { parent[lhs] = lhs }
            if parent[rhs] == nil { parent[rhs] = rhs }
            let left = find(lhs)
            let right = find(rhs)
            if left != right { parent[right] = left }
        }

        for row in rows {
            let group = "grp:" + stackKey(for: row)
            union(group, "row#\(row.spEffectId)")
            if mergeFamilies { union(group, "fam:" + row.familyKey) }
            if mergeStates, let state = row.stateCrossReferenceKey { union(group, "st:" + state) }
        }

        var buckets: [String: [BuffRankingRow]] = [:]
        for row in rows {
            buckets[find("row#\(row.spEffectId)"), default: []].append(row)
        }
        return buckets
    }

    /// 同组内谁留下：applyHighest 取 categoryPriority 数值小的，其余取倍率高的。
    static func prefers(_ candidate: BuffRankingRow, over current: BuffRankingRow) -> Bool {
        if candidate.stackBehavior == "applyHighest" && current.stackBehavior == "applyHighest" {
            if candidate.stackPriority != current.stackPriority {
                return candidate.stackPriority < current.stackPriority
            }
        }
        if candidate.effectiveMultiplier != current.effectiveMultiplier {
            return candidate.effectiveMultiplier > current.effectiveMultiplier
        }
        return candidate.spEffectId < current.spEffectId
    }

    public var summary: String {
        let total = dataset.buffs.count
        let passive = dataset.buffs.filter(\.isPassive).count
        return "\(total) 条增伤手段 · 其中 \(passive) 条无条件生效"
    }
}

// MARK: - 页面底部「本页自己承担的判定」

/// 「增伤排名」页底部那 13 条口径说明。
///
/// 放在 RelicCore 而不是视图层，是为了让自检能直接拿到它，与 Windows 端
/// `ranker.js` 的 `pageRuleNotes` **逐字同文**——任何一句改动都要同时改两边，
/// 两端各有一份锚点断言把顺序与措辞钉住。**所有条数一律由调用方照数据现算**，
/// 这里不写死任何具体数值。
public enum BuffRankerPageNotes {
    public static func rules(
        attributeScoped: Int,
        ladders: Int,
        selfInflicted: Int,
        meleeOnly: Int,
        skillsWithoutDamage: Int,
        spellsWithoutDamage: Int,
        hasAttackContexts: Bool
    ) -> [String] {
        let hasContexts = hasAttackContexts
        return [
            "选段一律走 weapons[].skillVariant → skills[].variants[i].atkIds，不按 ctx 取并集"
                + "（usage.选段（必读））；一个都对不上就是这把武器打不出段。",
            "只有法术段忽略 motion：usage「法术 / 子弹段」的结论是「motion 只在施法器该属性 attackBase 非 0 时"
                + "才有意义」，而法术在本页走「没有武器」这一路（attackBase 全 0）。战技的子弹段挂的是真武器、"
                + "motion 是真实动作值，照常按 攻击力 × motion/100 + flat 计算，addBaseAtk 也照常加一份。",
            "只有 rateFields[].countsAsDamage 为 true 且 valueKind 为 multiplier 的字段进入连乘；"
                + "特攻（weakness）、致命一击（critical）是 conditionalDamage，削韧／异常／special／flag／economy 一律不乘。",
            "武器槽（scope.weaponSlot）：缺失与 3（自身）视为不限，1／2 必须对上当前选的手，其余取值"
                + "（4 踢击）判为作用域不符。法术同样按当前手判定——施法器也占左右手之一。",
            "scope.spAttribute（只对带某种属性／异常的攻击生效，本版本 \(attributeScoped) 条）默认不计入："
                + "本页拿不到「这一段带不带该属性」的判据，要看请打开「包含属性／异常限定」。",
            "叠层阶梯（stackLadder，本版本 \(ladders) 条）：数据集只收第 1 层，topRates 才是满层数值。"
                + "行上同时标出第 1 层与满层倍率；同一阶梯的各层互斥（notes.stackLadder），"
                + "推荐组合里共用一个叠加组，绝不相乘；想按满层看请打开「叠层类按满层计算」。",
            "selfInflictedStatus（v5，本版本 \(selfInflicted) 条）标的是「status 组的加算点数累在玩家自己身上」"
                + "的自伤行。这些字段 countsAsDamage 全为 false，伤害排名的乘积一个数都不受它们影响；"
                + "本页只在行上打「自伤型异常累积」标，将来若加异常累积轴必须整条排除。",
            "本页额外做了三条数据集没有直接字段的判定：① affectsThrow 单独为真＝只作用于致命一击／投掷攻击"
                + "（『强化致命一击』全系都是这个签名，无条件相乘会让它稳居榜首）——"
                + (hasContexts
                    ? "这条只在该条目没有 scope.attackContexts 时才用，有 attackContexts 就以它为准；"
                    : "数据集给出 scope.attackContexts 后，本页会改以该字段为准；")
                + "② weaponSlot=3 且只点亮魔法／祷告、没点亮秘术＝只作用于法术（『强化魔法』『强化祷告』）；"
                + "③ subCategories 只标 130（近战武器攻击）而没有 112（战技攻击）的条目"
                + "（『提升近战攻击力』等 \(meleeOnly) 条）在战技模式下判为作用域不符——"
                + "战技的近战命中算不算 130，数据集没有给出判据，本页取保守口径，"
                + "排除条数按原因分项列在「增伤排名」的汇总行下方。",
            "叠加分组只用数据集算好的 stacking.group（叠层阶梯的各层共用一个阶梯键）；stateInfo 默认不参与分组"
                + "（stackingRules 第 3 条：它「并不是互斥分组」，实测同一个 stateInfo 下挂着几十条互不相干的效果）。"
                + "需要保守口径时可在「推荐组合」里打开「同 stateInfo 视为同一状态」。"
                + "同组留哪一条：两边都是 applyHighest 时按 categoryPriority 取数值小的那一份"
                + "（stackingRules 第 4 条「低い方が優先」），否则取有效倍率高的。",
            "「推荐组合」用全部命中条目计算，不受排名列表的搜索框与来源类型筛选影响——那两个是视图筛选；"
                + "要排除某一条请在列表里勾掉它，会即时回退到同组次高的那一条。",
            "攻击力加算（attackPowerFlat）是点数，必须先加进攻击力再乘倍率；本页没有绝对攻击力，"
                + "所以只按占比加权展示，不折成倍率、不进连乘。",
            "输出手段列表只收「至少有一段能算出非 0 相对值」的战技与法术：战技还要求至少有一把武器引用它"
                + "（没有武器就没有 attackBase），法术要求至少有一段带固定值。纯增益的战技"
                + "（\(skillsWithoutDamage) 条）与恢复／庇佑类法术（\(spellsWithoutDamage) 条）"
                + "选中后构成恒为 0，是死路，所以不进列表。",
            hasContexts
                ? "只在特定攻击情境成立的倍率（scope.attackContexts：突刺反击／防御反击／跳跃攻击…）"
                    + "按 notes.ranking 第④步默认不计入，在「增伤排名」里勾选对应情境后才参与乘算。"
                : "有些增益的生效条件写在攻击本身而不是 SpEffect 的 scope 里（例如『强化突刺反击』这类反击时机）。"
                    + "当前数据版本还没有 scope.attackContexts，数据集把它们标成 activation=passive、"
                    + "activationSource=noEvidence，本页没有依据把它们排除，看到明显只在特定时机成立的条目请自行勾掉；"
                    + "数据集补上 attackContexts 后本页会自动按情境分区。"
        ]
    }
}

// MARK: - v6 数据结构（配置页用）
//
// 增伤数据集 schemaVersion 6 新增的结构（「增伤排名」配置页用）。
//
// 全部宽容解码：未知字段忽略、缺字段退默认值、坏元素跳过，**不抛错**。
// 字段含义见数据集 notes.sourceSlot / notes.appliesTo / notes.weaponAffix / notes.relicAffix /
// notes.stackInput 与 slotRules.*.zh；页面口径见 BuffLoadout.swift 顶部说明。

/// 动态键：用来找出 requires 里本页认不出的键。
struct BuffAnyKey: CodingKey {
    let stringValue: String
    let intValue: Int?

    init(_ string: String) {
        stringValue = string
        intValue = nil
    }

    init?(stringValue: String) {
        self.stringValue = stringValue
        intValue = nil
    }

    init?(intValue: Int) {
        stringValue = String(intValue)
        self.intValue = intValue
    }
}

// MARK: - appliesTo

/// appliesToDetail.<类别>.requires：conditional 的机读条件。
public struct BuffAppliesRequirement: Sendable, Hashable, Decodable {
    /// 1 右手 / 2 左手。
    public let hand: Int?
    /// 出手武器的 wepType。
    public let attackWeaponTypes: [Int]
    /// 只对带这条词条的那把武器生效。
    public let attachedWeaponOnly: Bool
    /// 只对被附加属性（附魔／油脂／属性变化）的那把武器生效。
    public let imbuedWeaponOnly: Bool
    /// 只作用于某个物理攻击类型（0 斩 / 1 打 / 2 突 / 3 标准）。
    public let physicalType: Int?
    /// 只在这些攻击情境下成立（enums.attackContext 的键）。
    public let attackContexts: [String]
    /// 命中段的子类别与它有交集才吃得到（attackIndex 判定）。
    public let subCategoriesAny: [Int]
    /// 本页认不出的键（数据集以后新增的条件）：一律交给用户确认。
    public let unknownKeys: [String]

    static let knownKeys: Set<String> = [
        "hand", "attackWeaponTypes", "attachedWeaponOnly", "imbuedWeaponOnly",
        "physicalType", "attackContexts", "subCategoriesAny"
    ]

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: BuffAnyKey.self)
        hand = container.buffOptionalInt(BuffAnyKey("hand"))
        attackWeaponTypes = container.buffIntArray(BuffAnyKey("attackWeaponTypes"))
        attachedWeaponOnly = container.buffBool(BuffAnyKey("attachedWeaponOnly"))
        imbuedWeaponOnly = container.buffBool(BuffAnyKey("imbuedWeaponOnly"))
        physicalType = container.buffOptionalInt(BuffAnyKey("physicalType"))
        attackContexts = container.buffStringArray(BuffAnyKey("attackContexts"))
        subCategoriesAny = container.buffIntArray(BuffAnyKey("subCategoriesAny"))
        unknownKeys = container.allKeys.map(\.stringValue).filter { !Self.knownKeys.contains($0) }.sorted()
    }

    public init(
        hand: Int? = nil, attackWeaponTypes: [Int] = [], attachedWeaponOnly: Bool = false,
        imbuedWeaponOnly: Bool = false, physicalType: Int? = nil, attackContexts: [String] = [],
        subCategoriesAny: [Int] = [], unknownKeys: [String] = []
    ) {
        self.hand = hand
        self.attackWeaponTypes = attackWeaponTypes
        self.attachedWeaponOnly = attachedWeaponOnly
        self.imbuedWeaponOnly = imbuedWeaponOnly
        self.physicalType = physicalType
        self.attackContexts = attackContexts
        self.subCategoriesAny = subCategoriesAny
        self.unknownKeys = unknownKeys
    }
}

/// appliesToDetail.<类别>：非 yes 的类别的理由与条件。
public struct BuffAppliesDetail: Sendable, Hashable, Decodable {
    public let reason: String
    public let requires: BuffAppliesRequirement?
    public let matchShare: Double?

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        reason = container.buffString(.reason)
        requires = (try? container.decodeIfPresent(BuffAppliesRequirement.self, forKey: .requires)).flatMap { $0 }
        if let wrapped = try? container.decodeIfPresent(BuffNumber.self, forKey: .matchShare), wrapped.value.isFinite {
            matchShare = wrapped.value
        } else {
            matchShare = nil
        }
    }

    private enum CodingKeys: String, CodingKey {
        case reason, requires, matchShare
    }
}

// MARK: - 词条 / 叠层 / 武器固有

/// buffs[].relicAffixes[]：这条 buff 来自哪条遗物词条（对齐词条库）。
public struct BuffRelicAffixRef: Sendable, Hashable, Decodable {
    public let attachEffectId: Int
    /// 词条库 effectId；只出现在固定遗物上的特殊词条为 nil（在 relics.json 的 extraAffixes 里）。
    public let catalogEffectId: Int?
    public let catalog: String
    public let isDeepRelicAffix: Bool
    public let requiresCurse: Bool
    public let isCurse: Bool
    public let compatibilityId: Int
    public let inNormalRelicPools: Bool
    public let fixedRelicOnly: Bool

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        attachEffectId = container.buffInt(.attachEffectId, default: -1)
        catalogEffectId = container.buffOptionalInt(.catalogEffectId)
        catalog = container.buffString(.catalog, default: "affixes")
        isDeepRelicAffix = container.buffBool(.isDeepRelicAffix)
        requiresCurse = container.buffBool(.requiresCurse)
        isCurse = container.buffBool(.isCurse)
        compatibilityId = container.buffInt(.compatibilityId, default: -1)
        inNormalRelicPools = container.buffBool(.inNormalRelicPools)
        fixedRelicOnly = container.buffBool(.fixedRelicOnly)
    }

    private enum CodingKeys: String, CodingKey {
        case attachEffectId, catalogEffectId, catalog, isDeepRelicAffix, requiresCurse, isCurse
        case compatibilityId, inNormalRelicPools, fixedRelicOnly
    }
}

/// buffs[].weaponInnate：武器自带、不随机的效果。
public struct BuffWeaponInnate: Sendable, Hashable, Decodable {
    public let attachEffectIds: [Int]
    public let weaponIds: [Int]
    public let wepTypes: [Int]
    /// weaponIds 为空、只能靠行名前缀归类（页面只能让用户手动勾选）。
    public let inferredFromRowName: Bool
    public let rowCategory: String?

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        attachEffectIds = container.buffIntArray(.attachEffectIds)
        weaponIds = container.buffIntArray(.weaponIds)
        wepTypes = container.buffIntArray(.wepTypes)
        inferredFromRowName = container.buffBool(.inferredFromRowName)
        rowCategory = container.buffOptionalString(.rowCategory)
    }

    private enum CodingKeys: String, CodingKey {
        case attachEffectIds, weaponIds, wepTypes, inferredFromRowName, rowCategory
    }
}

/// buffs[].stackInput：需要用户填层数的叠层增益。
public struct BuffStackInput: Sendable, Hashable, Decodable {
    /// ladder（叠层阶梯，第 n 层取 tierMultipliers[n-1]）/ copies（同一效果 N 份，perStackMultiplier^N）。
    public let mode: String
    public let paramMaxStacks: Int?
    public let practicalMaxStacks: Int?
    public let practicalMaxSource: String?
    public let multiplierKey: String
    /// 层数换算出来的倍率要替换进 rates 的哪些字段。
    public let appliesToRateKeys: [String]
    public let tierMultipliers: [Double]
    public let perStackRatio: Double?
    public let perStackMultiplier: Double?
    public let uiLabelMax: Int?

    public var isLadder: Bool { mode == "ladder" }

    /// 输入框允许的最大层数：阶梯＝参数表层数；份数型参数表无上限，给一个足够大的数。
    public var maxAllowedStacks: Int {
        if isLadder {
            let tiers = tierMultipliers.count
            if let paramMaxStacks, paramMaxStacks > 0 { return tiers > 0 ? min(paramMaxStacks, tiers) : paramMaxStacks }
            return max(tiers, 1)
        }
        return Self.copiesInputCeiling
    }

    /// 「实际能叠到」的上限：practicalMaxStacks，没有就退游戏文本备好的『＋N』标签数。
    public var softMaxStacks: Int? { practicalMaxStacks ?? uiLabelMax }

    /// 份数型输入框的硬上限（参数表无上限，页面只拦住明显的误输入）。
    public static let copiesInputCeiling = 99

    /// n 层对应的倍率；n ≤ 0 或越界时为 nil。
    public func multiplier(forStacks stacks: Int) -> Double? {
        guard stacks > 0 else { return nil }
        if isLadder {
            guard !tierMultipliers.isEmpty else {
                guard let perStackRatio, perStackRatio > 0 else { return nil }
                return pow(perStackRatio, Double(stacks))
            }
            let tier = min(stacks, tierMultipliers.count)
            return tierMultipliers[tier - 1]
        }
        guard let perStackMultiplier, perStackMultiplier > 0 else { return nil }
        return pow(perStackMultiplier, Double(stacks))
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        mode = container.buffString(.mode, default: "copies")
        paramMaxStacks = container.buffOptionalInt(.paramMaxStacks)
        practicalMaxStacks = container.buffOptionalInt(.practicalMaxStacks)
        practicalMaxSource = container.buffOptionalString(.practicalMaxSource)
        multiplierKey = container.buffString(.multiplierKey)
        appliesToRateKeys = container.buffStringArray(.appliesToRateKeys)
        tierMultipliers = (try? container.decodeIfPresent([BuffFailable<BuffNumber>].self, forKey: .tierMultipliers))
            .flatMap { $0 }?
            .compactMap { $0.value.flatMap { $0.value.isFinite ? $0.value : nil } } ?? []
        perStackRatio = Self.optionalDouble(container, .perStackRatio)
        perStackMultiplier = Self.optionalDouble(container, .perStackMultiplier)
        uiLabelMax = container.buffOptionalInt(.uiLabelMax)
    }

    private static func optionalDouble(_ container: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> Double? {
        guard let wrapped = try? container.decodeIfPresent(BuffNumber.self, forKey: key), wrapped.value.isFinite else {
            return nil
        }
        return wrapped.value
    }

    private enum CodingKeys: String, CodingKey {
        case mode, paramMaxStacks, practicalMaxStacks, practicalMaxSource, multiplierKey
        case appliesToRateKeys, tierMultipliers, perStackRatio, perStackMultiplier, uiLabelMax
    }
}

/// buffs[].accumulatorLadder：连续攻击类累积阶梯（各档共用一个互斥键，用户选一档）。
public struct BuffAccumulatorLadder: Sendable, Hashable, Decodable {
    public let key: String
    public let tier: Int
    public let tiers: Int
    public let tierSpEffectIds: [Int]
    public let accumulatorSpEffectIds: [Int]
    public let thresholds: [Double]

    /// 阶梯身份（第 1 档的 spEffectId）：同一阶梯的各档共用它，选档状态按它存。
    public var ladderID: Int { tierSpEffectIds.first ?? -1 }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        key = container.buffString(.key)
        tier = container.buffInt(.tier, default: 1)
        tiers = container.buffInt(.tiers, default: 1)
        tierSpEffectIds = container.buffIntArray(.tierSpEffectIds)
        accumulatorSpEffectIds = container.buffIntArray(.accumulatorSpEffectIds)
        thresholds = (try? container.decodeIfPresent([BuffFailable<BuffNumber>].self, forKey: .thresholds))
            .flatMap { $0 }?
            .compactMap { $0.value?.value } ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case key, tier, tiers, tierSpEffectIds, accumulatorSpEffectIds, thresholds
    }
}

/// scope.weaponTypes：「装备 N 把 X 类武器」（equippedCount）或「用 X 类武器发动」（attackWith）。
public struct BuffWeaponTypesScope: Sendable, Hashable, Decodable {
    public let mode: String
    public let wepTypes: [Int]
    public let namesZh: [String]
    public let field: String
    public let count: Int?

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        mode = container.buffString(.mode)
        wepTypes = container.buffIntArray(.wepTypes)
        namesZh = container.buffStringArray(.namesZh)
        field = container.buffString(.field)
        count = container.buffOptionalInt(.count)
    }

    private enum CodingKeys: String, CodingKey {
        case mode, wepTypes, namesZh, field, count
    }
}

// MARK: - slotRules

public struct BuffSlotRules: Sendable, Hashable, Decodable {
    public struct ModeRule: Sendable, Hashable, Decodable {
        public let zh: String
        public let weaponAffixesPerWeapon: Int
        public let relicSlots: Int
        public let weaponCursesPerWeapon: Int
        public let deepOnlyAffixesPerWeapon: Int

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            zh = container.buffString(.zh)
            weaponAffixesPerWeapon = container.buffInt(.weaponAffixesPerWeapon, default: 1)
            relicSlots = container.buffInt(.relicSlots, default: 3)
            weaponCursesPerWeapon = container.buffInt(.weaponCursesPerWeapon, default: 0)
            deepOnlyAffixesPerWeapon = container.buffInt(.deepOnlyAffixesPerWeapon, default: 0)
        }

        public init(zh: String, perWeapon: Int, relicSlots: Int, cursesPerWeapon: Int, deepOnlyPerWeapon: Int) {
            self.zh = zh
            weaponAffixesPerWeapon = perWeapon
            self.relicSlots = relicSlots
            weaponCursesPerWeapon = cursesPerWeapon
            deepOnlyAffixesPerWeapon = deepOnlyPerWeapon
        }

        private enum CodingKeys: String, CodingKey {
            case zh, weaponAffixesPerWeapon, relicSlots, weaponCursesPerWeapon, deepOnlyAffixesPerWeapon
        }
    }

    public let normal: ModeRule
    public let deep: ModeRule
    public let modesZh: String
    public let maxWeapons: Int
    public let maxAffixesNormal: Int
    public let maxAffixesDeep: Int
    public let maxDeepOnlyAffixes: Int
    public let deepOnlyPerWeaponMax: Int
    public let deepCursePerWeapon: Int
    public let deepOnlyCapField: String
    public let deepOnlyCapCountsCurses: Bool
    /// 同一把深夜诅咒武器的两条正面词条能否相同：数据集写 unknown。
    public let duplicateWithinWeaponStatus: String
    public let duplicateWithinWeaponZh: String
    public let weaponAffixZh: String
    public let relicNormal: Int
    public let relicDeepExtra: Int
    public let affixesPerRelic: Int
    public let relicZh: String
    public let accessorySlots: Int
    public let accessoryMeasured: Bool
    public let accessoryZh: String
    /// consumable / spellBuff / … 这些不限数量的栏目的说明。
    public let slotlessZh: [String: String]

    public func weaponAffixCap(_ mode: LoadoutMode) -> Int {
        mode == .deep ? maxAffixesDeep : maxAffixesNormal
    }

    /// 正面的深夜专属词条上限：常规 0（deepOnlyAffixesPerWeapon=0），深夜 maxDeepOnlyAffixes。
    public func deepOnlyCap(_ mode: LoadoutMode) -> Int {
        mode == .deep ? min(maxDeepOnlyAffixes, deep.deepOnlyAffixesPerWeapon * maxWeapons) : normal.deepOnlyAffixesPerWeapon * maxWeapons
    }

    /// 武器诅咒上限：常规 0，深夜每把 1 条。
    public func curseCap(_ mode: LoadoutMode) -> Int {
        (mode == .deep ? deep.weaponCursesPerWeapon : normal.weaponCursesPerWeapon) * maxWeapons
    }

    public func relicSlots(_ mode: LoadoutMode) -> Int {
        mode == .deep ? deep.relicSlots : normal.relicSlots
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = BuffSlotRules.fallback
        let modes = (try? container.decodeIfPresent(RawModes.self, forKey: .modes)).flatMap { $0 }
        normal = modes?.normal ?? fallback.normal
        deep = modes?.deep ?? fallback.deep
        modesZh = modes?.zh ?? ""
        let weapon = (try? container.decodeIfPresent(RawWeaponAffix.self, forKey: .weaponAffix)).flatMap { $0 }
        maxWeapons = weapon?.maxWeapons ?? fallback.maxWeapons
        maxAffixesNormal = weapon?.maxAffixesNormal ?? fallback.maxAffixesNormal
        maxAffixesDeep = weapon?.maxAffixesDeep ?? fallback.maxAffixesDeep
        maxDeepOnlyAffixes = weapon?.maxDeepOnlyAffixes ?? fallback.maxDeepOnlyAffixes
        deepOnlyPerWeaponMax = weapon?.deepOnlyPerWeaponMax ?? fallback.deepOnlyPerWeaponMax
        deepCursePerWeapon = weapon?.deepCursePerWeapon ?? fallback.deepCursePerWeapon
        deepOnlyCapField = weapon?.deepOnlyCapField ?? fallback.deepOnlyCapField
        deepOnlyCapCountsCurses = weapon?.deepOnlyCapCountsCurses ?? false
        duplicateWithinWeaponStatus = weapon?.duplicateStatus ?? "unknown"
        duplicateWithinWeaponZh = weapon?.duplicateZh ?? ""
        weaponAffixZh = weapon?.zh ?? ""
        let relic = (try? container.decodeIfPresent(RawRelic.self, forKey: .relic)).flatMap { $0 }
        relicNormal = relic?.normal ?? fallback.relicNormal
        relicDeepExtra = relic?.deepExtra ?? fallback.relicDeepExtra
        affixesPerRelic = relic?.affixesPerRelic ?? fallback.affixesPerRelic
        relicZh = relic?.zh ?? ""
        let accessory = (try? container.decodeIfPresent(RawAccessory.self, forKey: .accessory)).flatMap { $0 }
        accessorySlots = accessory?.slots ?? fallback.accessorySlots
        accessoryMeasured = accessory?.measured ?? false
        accessoryZh = accessory?.zh ?? ""
        var slotless: [String: String] = [:]
        let dynamic = try decoder.container(keyedBy: BuffAnyKey.self)
        for key in ["consumable", "spellBuff", "weaponSkill", "weaponInnate", "character", "permanent", "runStack"] {
            if let raw = (try? dynamic.decodeIfPresent(RawZh.self, forKey: BuffAnyKey(key))).flatMap({ $0 }),
               !raw.zh.isEmpty {
                slotless[key] = raw.zh
            }
        }
        slotlessZh = slotless
    }

    /// slotRules 缺失时的兜底（仅供计算不崩；页面在缺失时显示「数据未内置」）。
    public static let fallback = BuffSlotRules()

    private init() {
        normal = ModeRule(zh: "", perWeapon: 1, relicSlots: 3, cursesPerWeapon: 0, deepOnlyPerWeapon: 0)
        deep = ModeRule(zh: "", perWeapon: 2, relicSlots: 6, cursesPerWeapon: 1, deepOnlyPerWeapon: 1)
        modesZh = ""
        maxWeapons = 6
        maxAffixesNormal = 6
        maxAffixesDeep = 12
        maxDeepOnlyAffixes = 6
        deepOnlyPerWeaponMax = 1
        deepCursePerWeapon = 1
        deepOnlyCapField = "weaponAffixDeepOnlyPositive"
        deepOnlyCapCountsCurses = false
        duplicateWithinWeaponStatus = "unknown"
        duplicateWithinWeaponZh = ""
        weaponAffixZh = ""
        relicNormal = 3
        relicDeepExtra = 3
        affixesPerRelic = 3
        relicZh = ""
        accessorySlots = 2
        accessoryMeasured = false
        accessoryZh = ""
        slotlessZh = [:]
    }

    private enum CodingKeys: String, CodingKey {
        case modes, weaponAffix, relic, accessory
    }

    private struct RawModes: Decodable {
        let normal: ModeRule?
        let deep: ModeRule?
        let zh: String

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            normal = (try? container.decodeIfPresent(ModeRule.self, forKey: .normal)).flatMap { $0 }
            deep = (try? container.decodeIfPresent(ModeRule.self, forKey: .deep)).flatMap { $0 }
            zh = container.buffString(.zh)
        }

        private enum CodingKeys: String, CodingKey { case normal, deep, zh }
    }

    private struct RawWeaponAffix: Decodable {
        let maxWeapons: Int?
        let maxAffixesNormal: Int?
        let maxAffixesDeep: Int?
        let maxDeepOnlyAffixes: Int?
        let deepOnlyPerWeaponMax: Int?
        let deepCursePerWeapon: Int?
        let deepOnlyCapField: String?
        let deepOnlyCapCountsCurses: Bool?
        let duplicateStatus: String?
        let duplicateZh: String?
        let zh: String

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            maxWeapons = container.buffOptionalInt(.maxWeapons)
            maxAffixesNormal = container.buffOptionalInt(.maxAffixesNormal)
            maxAffixesDeep = container.buffOptionalInt(.maxAffixesDeep)
            maxDeepOnlyAffixes = container.buffOptionalInt(.maxDeepOnlyAffixes)
            deepOnlyPerWeaponMax = container.buffOptionalInt(.deepOnlyPerWeaponMax)
            deepCursePerWeapon = container.buffOptionalInt(.deepCursePerWeapon)
            deepOnlyCapField = container.buffOptionalString(.deepOnlyCapField)
            deepOnlyCapCountsCurses = (try? container.decodeIfPresent(Bool.self, forKey: .deepOnlyCapCountsCurses))
                .flatMap { $0 }
            let duplicate = (try? container.decodeIfPresent(RawDuplicate.self, forKey: .duplicateWithinWeapon))
                .flatMap { $0 }
            duplicateStatus = duplicate?.status
            duplicateZh = duplicate?.zh
            zh = container.buffString(.zh)
        }

        private enum CodingKeys: String, CodingKey {
            case maxWeapons, maxAffixesNormal, maxAffixesDeep, maxDeepOnlyAffixes, deepOnlyPerWeaponMax
            case deepCursePerWeapon, deepOnlyCapField, deepOnlyCapCountsCurses, duplicateWithinWeapon, zh
        }
    }

    private struct RawDuplicate: Decodable {
        let status: String
        let zh: String

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            status = container.buffString(.status, default: "unknown")
            zh = container.buffString(.zh)
        }

        private enum CodingKeys: String, CodingKey { case status, zh }
    }

    private struct RawRelic: Decodable {
        let normal: Int?
        let deepExtra: Int?
        let affixesPerRelic: Int?
        let zh: String

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            normal = container.buffOptionalInt(.normal)
            deepExtra = container.buffOptionalInt(.deepExtra)
            affixesPerRelic = container.buffOptionalInt(.affixesPerRelic)
            zh = container.buffString(.zh)
        }

        private enum CodingKeys: String, CodingKey { case normal, deepExtra, affixesPerRelic, zh }
    }

    private struct RawAccessory: Decodable {
        let slots: Int?
        let measured: Bool
        let zh: String

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            slots = container.buffOptionalInt(.slots)
            measured = container.buffBool(.measured)
            zh = container.buffString(.zh)
        }

        private enum CodingKeys: String, CodingKey { case slots, measured, zh }
    }

    private struct RawZh: Decodable {
        let zh: String

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            zh = container.buffString(.zh)
        }

        private enum CodingKeys: String, CodingKey { case zh }
    }
}

// MARK: - 顶层清单

/// weaponAffixes[]：有增伤 buff 的局内武器词条（按 AttachEffect id）。
public struct BuffWeaponAffixInfo: Sendable, Hashable, Decodable, Identifiable {
    public let attachEffectId: Int
    public let nameZh: String
    public let nameEn: String
    public let paramName: String?
    /// 档位 1 / 2 / 3（没有档位的为 nil）。
    public let potency: Int?
    public let roles: [String]
    public let isDebuff: Bool
    public let compatibilityId: Int
    public let normalWepTypes: [Int]
    public let deepWepTypes: [Int]
    public let deepOnly: Bool
    public let deepOnlyPositive: Bool
    public let tableIds: [Int]
    public let spEffectIds: [Int]

    public var id: Int { attachEffectId }
    public var isCurse: Bool { roles.contains("curse") }
    public var isBlessing: Bool { roles.contains("blessing") }
    public var isFixed: Bool { roles.contains("fixed") && !roles.contains("affix") }

    /// 这个模式下能不能出现：常规不出深夜专属（含诅咒），深夜全都能出。
    public func isAvailable(in mode: LoadoutMode) -> Bool {
        mode == .deep || (!deepOnly && !isCurse)
    }

    /// 这个模式下能出现在哪些武器类别上。
    public func weaponTypes(in mode: LoadoutMode) -> [Int] {
        mode == .deep ? (deepWepTypes.isEmpty ? normalWepTypes : deepWepTypes) : normalWepTypes
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        attachEffectId = container.buffInt(.attachEffectId, default: -1)
        nameZh = container.buffString(.nameZh)
        nameEn = container.buffString(.nameEn)
        paramName = container.buffOptionalString(.paramName)
        potency = container.buffOptionalInt(.potency)
        roles = container.buffStringArray(.roles)
        isDebuff = container.buffBool(.isDebuff)
        compatibilityId = container.buffInt(.compatibilityId, default: -1)
        normalWepTypes = container.buffIntArray(.normalWepTypes)
        deepWepTypes = container.buffIntArray(.deepWepTypes)
        deepOnly = container.buffBool(.deepOnly)
        deepOnlyPositive = container.buffBool(.deepOnlyPositive)
        tableIds = container.buffIntArray(.tableIds)
        spEffectIds = container.buffIntArray(.spEffectIds)
    }

    private enum CodingKeys: String, CodingKey {
        case attachEffectId, nameZh, nameEn, paramName, potency, roles, isDebuff, compatibilityId
        case normalWepTypes, deepWepTypes, deepOnly, deepOnlyPositive, tableIds, spEffectIds
    }
}

/// fixedRelics[]：官方固定词条遗物（整件占一个遗物格）。
public struct BuffFixedRelic: Sendable, Hashable, Decodable {
    public let relicIds: [Int]
    public let nameZh: String
    public let nameEn: String
    public let color: Int
    public let isDeepRelic: Bool
    public let attachEffectIds: [Int]
    public let curseAttachEffectIds: [Int]
    /// 与 attachEffectIds 一一对应；没有中文名的位置为 nil。
    public let attachEffectNamesZh: [String?]
    public let spEffectIds: [Int]

    public var relicID: Int { relicIds.first ?? -1 }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        relicIds = container.buffIntArray(.relicIds)
        nameZh = container.buffString(.nameZh)
        nameEn = container.buffString(.nameEn)
        color = container.buffInt(.color, default: -1)
        isDeepRelic = container.buffBool(.isDeepRelic)
        attachEffectIds = container.buffIntArray(.attachEffectIds)
        curseAttachEffectIds = container.buffIntArray(.curseAttachEffectIds)
        attachEffectNamesZh = ((try? container.decodeIfPresent([BuffFailable<String>].self, forKey: .attachEffectNamesZh))
            .flatMap { $0 } ?? []).map(\.value)
        spEffectIds = container.buffIntArray(.spEffectIds)
    }

    private enum CodingKeys: String, CodingKey {
        case relicIds, nameZh, nameEn, color, isDeepRelic, attachEffectIds, curseAttachEffectIds
        case attachEffectNamesZh, spEffectIds
    }
}

/// attackIndex 里一组命中段的子类别集合与段数。
public struct BuffSubCategorySet: Sendable, Hashable, Decodable {
    public let subs: [Int]
    public let hits: Int

    public init(subs: [Int], hits: Int) {
        self.subs = subs
        self.hits = hits
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        subs = container.buffIntArray(.subs)
        hits = max(0, container.buffInt(.hits, default: 0))
    }

    private enum CodingKeys: String, CodingKey { case subs, hits }
}

/// attackIndex：每个战技／法术实际命中段的子类别集合。
public struct BuffAttackIndex: Sendable, Hashable, Decodable {
    public let skills: [Int: [BuffSubCategorySet]]
    public let spells: [Int: [BuffSubCategorySet]]

    public init(skills: [Int: [BuffSubCategorySet]] = [:], spells: [Int: [BuffSubCategorySet]] = [:]) {
        self.skills = skills
        self.spells = spells
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        skills = Self.table(container, .skills)
        spells = Self.table(container, .spells)
    }

    private static func table(_ container: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> [Int: [BuffSubCategorySet]] {
        guard let raw = try? container.decodeIfPresent([String: BuffFailable<Entry>].self, forKey: key) else { return [:] }
        var result: [Int: [BuffSubCategorySet]] = [:]
        for (id, entry) in raw {
            guard let number = Int(id), let sets = entry.value?.sets else { continue }
            result[number] = sets
        }
        return result
    }

    private struct Entry: Decodable {
        let sets: [BuffSubCategorySet]

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            sets = container.buffArray(.subCategorySets)
        }

        private enum CodingKeys: String, CodingKey { case subCategorySets }
    }

    private enum CodingKeys: String, CodingKey { case skills, spells }
}

/// notes.userQuestions 的一问一答。
public struct BuffUserQuestion: Sendable, Hashable, Identifiable {
    public let key: String
    public let question: String
    public let answer: String

    public var id: String { key }
}

/// 只为取出 notes.userQuestions（notes 其余键都是字符串，由 buffStringDictionary 读）。
struct BuffNotesQuestions: Decodable {
    let questions: [BuffUserQuestion]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard let raw = try? container.decodeIfPresent([String: BuffFailable<RawQuestion>].self, forKey: .userQuestions) else {
            questions = []
            return
        }
        questions = raw
            .compactMap { key, value in
                value.value.map { BuffUserQuestion(key: key, question: $0.question, answer: $0.answer) }
            }
            .filter { !$0.question.isEmpty || !$0.answer.isEmpty }
            .sorted { lhs, rhs in
                lhs.key.count == rhs.key.count ? lhs.key < rhs.key : lhs.key.count < rhs.key.count
            }
    }

    private struct RawQuestion: Decodable {
        let question: String
        let answer: String

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            question = container.buffString(.question)
            answer = container.buffString(.answer)
        }

        private enum CodingKeys: String, CodingKey { case question, answer }
    }

    private enum CodingKeys: String, CodingKey { case userQuestions }
}

/// enums.sourceSlot 的一项：{zh, en, note}。
struct BuffSlotLabel: Decodable {
    let zh: String
    let note: String

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        zh = container.buffString(.zh)
        note = container.buffString(.note)
    }

    private enum CodingKeys: String, CodingKey { case zh, note }
}
