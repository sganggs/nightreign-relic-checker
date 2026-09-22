import Foundation

// 「增伤排名」页下半部分：增伤手段（buffs.json，schemaVersion 4）的解码与排名引擎。
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
    }

    private enum CodingKeys: String, CodingKey {
        case kind, id, nameZh, nameEn, effectNameZh, via, trigger, inferred, paramRowCategory
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
    }

    private enum CodingKeys: String, CodingKey {
        case affectsSorcery, affectsIncantation, affectsShaman, affectsThrow
        case weaponSlot, atkAttribute, spAttribute, subCategories, attackContexts
    }

    public init(
        affectsSorcery: Bool = false, affectsIncantation: Bool = false,
        affectsShaman: Bool = false, affectsThrow: Bool = false,
        weaponSlot: Int? = nil, atkAttribute: Int? = nil,
        spAttribute: Int? = nil, subCategories: [Int] = [],
        attackContexts: [String] = []
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
    }

    /// 只在某种攻击情境下才吃得到（默认不计入通用排名）。
    public var isContextGated: Bool { !attackContexts.isEmpty }
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

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        stateInfo = container.buffInt(.stateInfo, default: 0)
        spCategory = container.buffInt(.spCategory, default: 0)
        spCategoryBehavior = container.buffString(.spCategoryBehavior, default: "unknown")
        categoryPriority = container.buffInt(.categoryPriority, default: 0)
        saveCategory = container.buffInt(.saveCategory, default: -1)
        group = container.buffString(.group)
    }

    private enum CodingKeys: String, CodingKey {
        case stateInfo, spCategory, spCategoryBehavior, categoryPriority, saveCategory, group
    }

    public init(
        stateInfo: Int = 0, spCategory: Int = 0, spCategoryBehavior: String = "none",
        categoryPriority: Int = 0, saveCategory: Int = -1, group: String
    ) {
        self.stateInfo = stateInfo
        self.spCategory = spCategory
        self.spCategoryBehavior = spCategoryBehavior
        self.categoryPriority = categoryPriority
        self.saveCategory = saveCategory
        self.group = group
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
    public let statusLabelsZh: [String]
    public let sourcesTruncated: Int?

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
        statusLabelsZh = container.buffStringArray(.statusLabelsZh)
        sourcesTruncated = container.buffOptionalInt(.sourcesTruncated)
    }

    private enum CodingKeys: String, CodingKey {
        case spEffectId, nameZh, nameEn, displayNameZh, displayNameEn, paramName
        case sources, rates, rateGroups, direction, scope, stacking, stackLadder
        case duration, permanent, target, targetSource, activation, activationSource
        case descZh, conditions, triggered, inferredName, statusLabelsZh, sourcesTruncated
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

        counts = container.buffNumberDictionary(.counts)
        buffs = container.buffArray(.buffs)
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, gameVersion, dataVersion, generatedAt, notes
        case stackingRules, rateFields, rateFieldGroups, conditionFields, enums, counts, buffs
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
        case attackContext, stateInfo
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

/// 当前的输出手段（决定 scope 过滤怎么走）。
public enum BuffDelivery: Sendable, Hashable {
    /// 武器战技命中：槽位 1 右手 / 2 左手。
    case weaponSkill(slot: Int)
    case sorcery
    case incantation

    public var slot: Int? {
        if case .weaponSkill(let slot) = self { return slot }
        return nil
    }
}

public struct BuffRankingContext: Sendable, Hashable {
    public var delivery: BuffDelivery
    /// 这次攻击属于哪些攻击子类别（战技命中 = 112 战技攻击；普通法术 = 空）。
    public var subCategories: Set<Int>
    /// 按 `SkillDamageChannel.rawValue` 索引的伤害占比（和为 1；全 0 表示没有勾选任何段）。
    public var shares: [Double]

    public init(delivery: BuffDelivery, subCategories: Set<Int>, shares: [Double]) {
        self.delivery = delivery
        self.subCategories = subCategories
        self.shares = shares
    }

    public init(delivery: BuffDelivery, subCategories: Set<Int>, composition: SkillDamageComposition) {
        self.init(delivery: delivery, subCategories: subCategories, shares: composition.shares)
    }

    /// 战技命中：子类别固定为 112（本作没有独立的「战技伤害 +x%」字段，
    /// 所谓强化战技都是普通 AttackRate + magicSubCategoryChange = 112）。
    public static let skillAttackSubCategory = 112

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
    /// 来源类型多选；空集合 = 不过滤。
    public var sourceKinds: Set<String>
    public var query: String

    public init(
        includeConditional: Bool = false,
        includeAllies: Bool = false,
        includeAttributeScoped: Bool = false,
        includedAttackContexts: Set<String> = [],
        sourceKinds: Set<String> = [],
        query: String = ""
    ) {
        self.includeConditional = includeConditional
        self.includeAllies = includeAllies
        self.includeAttributeScoped = includeAttributeScoped
        self.includedAttackContexts = includedAttackContexts
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

    public var id: Int { spEffectId }

    /// 只在某种攻击情境下生效（默认不进通用排名，勾选情境后才出现）。
    public var isContextGated: Bool { !attackContexts.isEmpty }

    /// 有效倍率没有意义（只有加算 / 只在别的轴上生效）时为 false。
    public var hasMultiplier: Bool { effectiveMultiplier > 1.0000001 || effectiveMultiplier < 0.9999999 }

    public var durationText: String {
        if permanent || duration < 0 { return "永久" }
        if duration == 0 { return "瞬间" }
        return BuffFormat.trim(duration) + " 秒"
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

    public init(
        rows: [BuffRankingRow],
        candidateCount: Int,
        neutralCount: Int,
        contextScopedCount: Int = 0
    ) {
        self.rows = rows
        self.candidateCount = candidateCount
        self.neutralCount = neutralCount
        self.contextScopedCount = contextScopedCount
    }

    public static let empty = BuffRankingResult(
        rows: [], candidateCount: 0, neutralCount: 0, contextScopedCount: 0
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
            profiles.append(Self.makeProfile(for: buff, fields: fieldByKey, dataset: dataset))
            for kind in buff.sourceKinds where seenKinds.insert(kind).inserted {
                kinds.append(kind)
            }
            if buff.scope.spAttribute != nil { attributeScoped += 1 }
            if buff.scope.isContextGated {
                contextScoped += 1
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
    static let attackContextOrder = [
        "criticalHit", "thrustingCounter", "guardCounter", "chainFinisher",
        "chargedHeavyAttack", "chargedSkill", "chargedSpell",
        "jumpAttack", "dashAttack", "rollingAttack", "backstepAttack",
        "initialAttack", "horsebackAttack", "twoHanded", "dualWield"
    ]

    public init(data: Data) throws {
        try self.init(dataset: BuffDataset.decode(from: data))
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
        var names: [String] = []
        var seenNames: Set<String> = []
        for source in buff.sources.prefix(6) where seenNames.insert(source.displayName).inserted {
            names.append(source.displayName)
        }

        let searchParts = [
            buff.displayName,
            buff.nameZh ?? "",
            buff.nameEn ?? "",
            buff.displayNameEn ?? "",
            buff.paramName ?? "",
            names.joined(separator: " "),
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
            ladderChannelMultiplier: ladderChannelMultiplier
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
        if !options.sourceKinds.isEmpty && profile.sourceKinds.allSatisfy({ !options.sourceKinds.contains($0) }) {
            return false
        }
        return true
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

    /// scope 的其余各项（武器槽 / 魔法 / 祷告 / 攻击子类别 / 属性限定 / 物理子类型）。
    func scopeMatchesIgnoringAttackContexts(
        _ buff: BuffEntry, context: BuffRankingContext, options: BuffRankingOptions
    ) -> Bool {
        let scope = buff.scope
        switch context.delivery {
        case .weaponSkill(let slot):
            // 缺失（0 不限）与 3（自身）视为作用于任何武器；1 / 2 必须对上当前槽位。
            if let weaponSlot = scope.weaponSlot, weaponSlot != slot, weaponSlot != 3 { return false }
        case .sorcery:
            guard scope.affectsSorcery else { return false }
        case .incantation:
            guard scope.affectsIncantation else { return false }
        }
        if !scope.subCategories.isEmpty {
            guard !context.subCategories.isEmpty,
                  scope.subCategories.contains(where: { context.subCategories.contains($0) }) else { return false }
        }
        if scope.spAttribute != nil && !options.includeAttributeScoped { return false }
        if let attribute = scope.atkAttribute, (0...3).contains(attribute), context.hasComposition {
            let channel = SkillDamageChannel.physical(code: attribute)
            guard context.shares.indices.contains(channel.rawValue), context.shares[channel.rawValue] > 0 else {
                return false
            }
        }
        return true
    }

    // MARK: 计算

    /// 有效倍率 = Σ_通道 占比 × Π(作用于该通道的倍率)。
    /// 没有勾选任何段时（占比全 0）退回「各通道乘数的最大值」，页面会提示这一点。
    func effectiveMultiplier(_ profile: Profile, shares: [Double]) -> Double {
        Self.effectiveMultiplier(
            channelMultiplier: profile.channelMultiplier,
            shares: shares,
            fallback: profile.maxMultiplier
        )
    }

    static func effectiveMultiplier(
        channelMultiplier: [Double], shares: [Double], fallback: Double
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
        guard weight > 0 else { return profile.elementFlat.max() ?? 0 }
        return total / weight
    }

    func makeRow(index: Int, context: BuffRankingContext) -> BuffRankingRow {
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
                topMultiplier: Self.effectiveMultiplier(
                    channelMultiplier: multipliers,
                    shares: shares,
                    fallback: multipliers.max() ?? 1
                ),
                saved: info.saved,
                tierSpEffectIds: ([buff.spEffectId] + info.tierSpEffectIds).sorted()
            )
        }
        return BuffRankingRow(
            spEffectId: buff.spEffectId,
            displayName: buff.displayName,
            paramName: buff.paramName,
            effectiveMultiplier: effectiveMultiplier(profile, shares: shares),
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
            descZh: buff.descZh
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
        let needle = options.query.foldedForSearch
        var rows: [BuffRankingRow] = []
        rows.reserveCapacity(128)
        var candidates = 0
        var neutral = 0
        var contextScoped = 0
        for index in dataset.buffs.indices {
            let buff = dataset.buffs[index]
            let profile = profiles[index]
            guard passesEntryFilters(buff, profile, options) else { continue }
            guard scopeMatchesIgnoringAttackContexts(buff, context: context, options: options) else { continue }
            if !needle.isEmpty && !profile.searchKey.contains(needle) { continue }
            // notes.ranking ④：情境限定的条目默认不进通用排名，单独计数供页面说明。
            guard attackContextAllowed(buff, options: options) else {
                contextScoped += 1
                continue
            }
            candidates += 1
            let row = makeRow(index: index, context: context)
            guard row.hasMultiplier || row.weightedFlat != 0 else {
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
            contextScopedCount: contextScoped
        )
    }

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
        includedConditional: Set<Int> = []
    ) -> BuffStackPlan {
        var best: [String: BuffRankingRow] = [:]
        var dropped = 0
        var excludedCount = 0

        for row in rows {
            if excluded.contains(row.spEffectId) {
                excludedCount += 1
                continue
            }
            // 只有 passive 才默认进组合；条件型必须由用户单独勾选纳入。
            guard row.isPassive || includedConditional.contains(row.spEffectId) else { continue }
            guard row.effectiveMultiplier > 1.0000001 else { continue }
            let key = Self.stackKey(for: row)
            guard let current = best[key] else {
                best[key] = row
                continue
            }
            dropped += 1
            if Self.prefers(row, over: current) { best[key] = row }
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
    /// 将来收全层时这一层保护才会真正派上用场）。
    static func stackKey(for row: BuffRankingRow) -> String {
        guard let ladder = row.ladder, let first = ladder.tierSpEffectIds.first else { return row.stackGroup }
        return "ladder#\(first)"
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
