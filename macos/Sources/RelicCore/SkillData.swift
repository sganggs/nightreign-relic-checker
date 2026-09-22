import Foundation

// 「增伤排名」页上半部分的数据模型：武器 / 战技 / 法术与它们的分段命中。
//
// 数据来源：Resources/skills.json（schemaVersion 2），经
// `GameDataLoader.dataIfAvailable(for: .skills)` 读出原始 Data 后在这里解码。
//
// 解码原则（数据集由另一条流水线维护，字段随时可能增删）：
//   * 未知字段一律忽略；
//   * 已知字段缺失 / 类型不符时退回默认值，**不抛错**；
//   * 数组逐元素解码，坏元素跳过而不是整份失败。
// 只有「顶层不是 JSON 对象」「武器与战技全空」这种读不懂的情况才抛 `SkillDataError`。
//
// 关键算法（严格按数据集 usage 块，见页面底部的「原文」折叠区）：
//   * 选段：weapons[].skillVariant → skills[].variants[i].atkIds，**不要**按 ctx 取并集；
//   * 近战武器段：该属性伤害 ≈ 武器该属性攻击力 × motion/100 + flat（addBaseAtk 再加一份基础攻击力）；
//   * 法术 / 子弹段：法术只用 flat（motion 的五属性同值 100 是占位写法）；
//   * 伤害类型：attribute 为 WeaponAtkAttribute / WeaponAtkAttribute2 时回 weapons[] 取 atkAttribute / atkAttribute2。
//
// 本数据集不含强化倍率与能力值补正曲线，因此这里算出来的一律是**相对构成**，
// 不是绝对伤害（见 dataset.usage["本数据集的边界"]）。

// MARK: - 错误

public enum SkillDataError: LocalizedError {
    case notAnObject
    case undecodable(String)
    case empty

    public var errorDescription: String? {
        switch self {
        case .notAnObject: return "战技数据不是合法的 JSON 对象"
        case .undecodable(let detail): return "战技数据无法解码：" + detail
        case .empty: return "战技数据里没有任何武器或战技记录"
        }
    }
}

// MARK: - 宽容解码辅助（与其它页面的同名辅助分开，避免互相牵连）

/// 逐元素解码用的包装：单个元素解不出来时置 nil，由调用方过滤掉。
struct SkillFailable<T: Decodable>: Decodable {
    let value: T?

    init(from decoder: Decoder) throws {
        value = try? T(from: decoder)
    }
}

extension KeyedDecodingContainer {
    func skillDouble(_ key: Key, default fallback: Double) -> Double {
        if let value = try? decodeIfPresent(Double.self, forKey: key) { return value }
        if let value = try? decodeIfPresent(Int.self, forKey: key) { return Double(value) }
        if let text = try? decodeIfPresent(String.self, forKey: key), let value = Double(text) { return value }
        return fallback
    }

    func skillInt(_ key: Key, default fallback: Int) -> Int {
        if let value = try? decodeIfPresent(Int.self, forKey: key) { return value }
        if let value = try? decodeIfPresent(Double.self, forKey: key), value.isFinite {
            return Int(value.rounded())
        }
        if let text = try? decodeIfPresent(String.self, forKey: key), let value = Int(text) { return value }
        return fallback
    }

    func skillOptionalInt(_ key: Key) -> Int? {
        if let value = try? decodeIfPresent(Int.self, forKey: key) { return value }
        if let value = try? decodeIfPresent(Double.self, forKey: key), value.isFinite {
            return Int(value.rounded())
        }
        return nil
    }

    func skillString(_ key: Key, default fallback: String = "") -> String {
        if let value = try? decodeIfPresent(String.self, forKey: key) { return value }
        if let value = try? decodeIfPresent(Int.self, forKey: key) { return String(value) }
        return fallback
    }

    func skillOptionalString(_ key: Key) -> String? {
        guard let value = try? decodeIfPresent(String.self, forKey: key), !value.isEmpty else { return nil }
        return value
    }

    func skillBool(_ key: Key, default fallback: Bool = false) -> Bool {
        if let value = try? decodeIfPresent(Bool.self, forKey: key) { return value }
        if let value = try? decodeIfPresent(Int.self, forKey: key) { return value != 0 }
        return fallback
    }

    func skillArray<T: Decodable>(_ key: Key) -> [T] {
        guard let wrapped = try? decodeIfPresent([SkillFailable<T>].self, forKey: key) else { return [] }
        return wrapped.compactMap(\.value)
    }

    func skillIntArray(_ key: Key) -> [Int] {
        let numbers: [Double] = skillArray(key)
        return numbers.map { Int($0.rounded()) }
    }

    func skillStringDictionary(_ key: Key) -> [String: String] {
        guard let wrapped = try? decodeIfPresent([String: SkillFailable<String>].self, forKey: key) else { return [:] }
        return wrapped.compactMapValues(\.value)
    }

    /// 只保留有限数值的字典（motion / flat / attackBase）。
    func skillNumberDictionary(_ key: Key) -> [String: Double] {
        guard let wrapped = try? decodeIfPresent([String: SkillFailable<Double>].self, forKey: key) else { return [:] }
        return wrapped.compactMapValues { $0.value.flatMap { $0.isFinite ? $0 : nil } }
    }
}

// MARK: - 属性与伤害类型

/// 五个攻击力属性槽（参数里的 dark 槽位在本作即「圣」，数据集已改名为 holy）。
public enum SkillElement: String, CaseIterable, Sendable, Hashable {
    case physical, magic, fire, lightning, holy

    public var titleZh: String {
        switch self {
        case .physical: return "物理"
        case .magic: return "魔力"
        case .fire: return "火"
        case .lightning: return "雷"
        case .holy: return "圣"
        }
    }
}

/// 伤害构成的细分通道：物理再按攻击类型分成斩 / 打 / 突 / 标准，
/// 另外留一个「物理（无类型）」给 attribute = None 的段。
public enum SkillDamageChannel: Int, CaseIterable, Sendable, Hashable, Identifiable {
    case slash = 0
    case strike
    case pierce
    case standard
    case physicalOther
    case magic
    case fire
    case lightning
    case holy

    public var id: Int { rawValue }

    public var titleZh: String {
        switch self {
        case .slash: return "斩击"
        case .strike: return "打击"
        case .pierce: return "突刺"
        case .standard: return "标准"
        case .physicalOther: return "物理（无类型）"
        case .magic: return "魔力"
        case .fire: return "火"
        case .lightning: return "雷"
        case .holy: return "圣"
        }
    }

    public var isPhysical: Bool {
        switch self {
        case .slash, .strike, .pierce, .standard, .physicalOther: return true
        case .magic, .fire, .lightning, .holy: return false
        }
    }

    public var element: SkillElement {
        switch self {
        case .slash, .strike, .pierce, .standard, .physicalOther: return .physical
        case .magic: return .magic
        case .fire: return .fire
        case .lightning: return .lightning
        case .holy: return .holy
        }
    }

    /// `enums.atkAttribute` 的 0…3（斩 / 打 / 突 / 标准）。
    public static func physical(code: Int) -> SkillDamageChannel {
        switch code {
        case 0: return .slash
        case 1: return .strike
        case 2: return .pierce
        case 3: return .standard
        default: return .physicalOther
        }
    }

    public static func channel(for element: SkillElement) -> SkillDamageChannel {
        switch element {
        case .physical: return .physicalOther
        case .magic: return .magic
        case .fire: return .fire
        case .lightning: return .lightning
        case .holy: return .holy
        }
    }
}

/// `hits[].attribute`：Slash / Strike / Pierce / Standard / None，
/// 以及必须回武器上取的 WeaponAtkAttribute（253）与 WeaponAtkAttribute2（252）。
public enum SkillAttackAttribute: Sendable, Hashable {
    case fixed(Int)          // 0…3
    case weaponPrimary       // 253
    case weaponSecondary     // 252
    case none                // 254

    public init(raw: String) {
        switch raw {
        case "Slash": self = .fixed(0)
        case "Strike": self = .fixed(1)
        case "Pierce": self = .fixed(2)
        case "Standard": self = .fixed(3)
        case "WeaponAtkAttribute": self = .weaponPrimary
        case "WeaponAtkAttribute2": self = .weaponSecondary
        default: self = .none
        }
    }

    /// 解析成具体通道；`weapon` 为空（法术）时 Weapon* 只能退成「物理（无类型）」。
    public func channel(weapon: SkillWeapon?) -> SkillDamageChannel {
        switch self {
        case .fixed(let code): return .physical(code: code)
        case .weaponPrimary:
            guard let weapon else { return .physicalOther }
            return .physical(code: weapon.atkAttribute)
        case .weaponSecondary:
            guard let weapon else { return .physicalOther }
            return .physical(code: weapon.atkAttribute2)
        case .none: return .physicalOther
        }
    }
}

// MARK: - 数据模型

public struct SkillSource: Sendable, Hashable, Decodable {
    public let name: String
    public let detail: String
    public let url: String
    public let license: String
    public let use: String

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = container.skillString(.name)
        detail = container.skillString(.detail)
        url = container.skillString(.url)
        license = container.skillString(.license)
        use = container.skillString(.use)
    }

    private enum CodingKeys: String, CodingKey {
        case name, detail, url, license, use
    }
}

public struct SkillWeapon: Sendable, Hashable, Identifiable, Decodable {
    public let id: Int
    public let nameZh: String
    public let nameEn: String
    public let wepType: Int
    public let wepTypeZh: String
    public let wepTypeEn: String
    public let rarityZh: String
    /// 五属性基础攻击力（缺失的键 = 0，**未含强化与词条加成**）。
    public let attackBase: [SkillElement: Double]
    public let staminaBase: Double
    public let poiseDamageBase: Double
    public let swordArtsParamId: Int
    /// EquipParamWeapon.atkAttribute / atkAttribute2（0 斩 / 1 打 / 2 突 / 3 标准）。
    public let atkAttribute: Int
    public let atkAttributeZh: String
    public let atkAttribute2: Int
    public let atkAttribute2Zh: String
    /// 该武器在「它的战技」variants 数组里的下标；缺失表示这把武器的战技没有命中段。
    public let skillVariant: Int?

    public var displayName: String { nameZh.isEmpty ? nameEn : nameZh }

    public func attack(_ element: SkillElement) -> Double { attackBase[element] ?? 0 }

    public var totalAttack: Double {
        SkillElement.allCases.reduce(0) { $0 + attack($1) }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = container.skillInt(.id, default: -1)
        nameZh = container.skillString(.nameZh)
        nameEn = container.skillString(.nameEn)
        wepType = container.skillInt(.wepType, default: -1)
        wepTypeZh = container.skillString(.wepTypeZh)
        wepTypeEn = container.skillString(.wepTypeEn)
        rarityZh = container.skillString(.rarityZh)
        var base: [SkillElement: Double] = [:]
        for (key, value) in container.skillNumberDictionary(.attackBase) {
            if let element = SkillElement(rawValue: key) { base[element] = value }
        }
        attackBase = base
        staminaBase = container.skillDouble(.staminaBase, default: 0)
        poiseDamageBase = container.skillDouble(.poiseDamageBase, default: 0)
        swordArtsParamId = container.skillInt(.swordArtsParamId, default: -1)
        atkAttribute = container.skillInt(.atkAttribute, default: 3)
        atkAttributeZh = container.skillString(.atkAttributeZh)
        atkAttribute2 = container.skillInt(.atkAttribute2, default: 3)
        atkAttribute2Zh = container.skillString(.atkAttribute2Zh)
        skillVariant = container.skillOptionalInt(.skillVariant)
    }

    private enum CodingKeys: String, CodingKey {
        case id, nameZh, nameEn, wepType, wepTypeZh, wepTypeEn, rarityZh
        case attackBase, staminaBase, poiseDamageBase, swordArtsParamId
        case atkAttribute, atkAttributeZh, atkAttribute2, atkAttribute2Zh, skillVariant
    }

    /// 自检 / 预览用的直接构造。
    public init(
        id: Int, nameZh: String, nameEn: String = "", wepType: Int = 0,
        wepTypeZh: String = "", wepTypeEn: String = "", rarityZh: String = "",
        attackBase: [SkillElement: Double] = [:], staminaBase: Double = 0,
        poiseDamageBase: Double = 0, swordArtsParamId: Int = -1,
        atkAttribute: Int = 3, atkAttributeZh: String = "标准",
        atkAttribute2: Int = 3, atkAttribute2Zh: String = "标准",
        skillVariant: Int? = nil
    ) {
        self.id = id
        self.nameZh = nameZh
        self.nameEn = nameEn
        self.wepType = wepType
        self.wepTypeZh = wepTypeZh
        self.wepTypeEn = wepTypeEn
        self.rarityZh = rarityZh
        self.attackBase = attackBase
        self.staminaBase = staminaBase
        self.poiseDamageBase = poiseDamageBase
        self.swordArtsParamId = swordArtsParamId
        self.atkAttribute = atkAttribute
        self.atkAttributeZh = atkAttributeZh
        self.atkAttribute2 = atkAttribute2
        self.atkAttribute2Zh = atkAttribute2Zh
        self.skillVariant = skillVariant
    }
}

public struct SkillHit: Sendable, Hashable, Identifiable, Decodable {
    public let atkId: Int
    public let ctx: String?
    public let ctxZh: String?
    public let ctxKind: String?
    public let label: String?
    public let labelZh: String?
    public let motion: [SkillElement: Double]
    public let flat: [SkillElement: Double]
    public let poise: Double
    public let poiseMv: Double
    public let stamina: Double
    public let staminaMv: Double
    public let attribute: SkillAttackAttribute
    public let attributeZh: String
    public let isBullet: Bool
    public let noFp: Bool
    public let noDamage: Bool
    /// 该段所属动作套在本作没有任何武器会用到，按选段算法永远取不到。
    public let noVariant: Bool
    public let addBaseAtk: Bool

    public var id: Int { atkId }

    public var displayLabel: String {
        if let labelZh, !labelZh.isEmpty { return labelZh }
        if let label, !label.isEmpty { return label }
        return "单段"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        atkId = container.skillInt(.atkId, default: -1)
        ctx = container.skillOptionalString(.ctx)
        ctxZh = container.skillOptionalString(.ctxZh)
        ctxKind = container.skillOptionalString(.ctxKind)
        label = container.skillOptionalString(.label)
        labelZh = container.skillOptionalString(.labelZh)
        motion = SkillHit.elementMap(container.skillNumberDictionary(.motion))
        flat = SkillHit.elementMap(container.skillNumberDictionary(.flat))
        poise = container.skillDouble(.poise, default: 0)
        poiseMv = container.skillDouble(.poiseMv, default: 0)
        stamina = container.skillDouble(.stamina, default: 0)
        staminaMv = container.skillDouble(.staminaMv, default: 0)
        attribute = SkillAttackAttribute(raw: container.skillString(.attribute, default: "None"))
        attributeZh = container.skillString(.attributeZh)
        isBullet = container.skillBool(.isBullet)
        noFp = container.skillBool(.noFp)
        noDamage = container.skillBool(.noDamage)
        noVariant = container.skillBool(.noVariant)
        addBaseAtk = container.skillBool(.addBaseAtk)
    }

    private static func elementMap(_ raw: [String: Double]) -> [SkillElement: Double] {
        var result: [SkillElement: Double] = [:]
        for (key, value) in raw where value != 0 {
            if let element = SkillElement(rawValue: key) { result[element] = value }
        }
        return result
    }

    private enum CodingKeys: String, CodingKey {
        case atkId, ctx, ctxZh, ctxKind, label, labelZh, motion, flat
        case poise, poiseMv, stamina, staminaMv, attribute, attributeZh
        case isBullet, noFp, noDamage, noVariant, addBaseAtk
    }
}

/// 一套实际会打出的段。`atkIds` 是本战技 hits 里的 atkId 子集。
public struct SkillVariant: Sendable, Hashable, Decodable {
    public let atkIds: [Int]
    public let ctx: String?
    public let ctxZh: String?
    public let ctxKind: String?
    public let via: String
    public let weaponIds: [Int]

    public var displayContext: String? {
        if let ctxZh, !ctxZh.isEmpty { return ctxZh }
        if let ctx, !ctx.isEmpty { return ctx }
        return nil
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        atkIds = container.skillIntArray(.atkIds)
        ctx = container.skillOptionalString(.ctx)
        ctxZh = container.skillOptionalString(.ctxZh)
        ctxKind = container.skillOptionalString(.ctxKind)
        via = container.skillString(.via)
        weaponIds = container.skillIntArray(.weaponIds)
    }

    private enum CodingKeys: String, CodingKey {
        case atkIds, ctx, ctxZh, ctxKind, via, weaponIds
    }
}

public struct SkillEntry: Sendable, Hashable, Identifiable, Decodable {
    public let id: Int
    public let nameZh: String
    public let nameEn: String
    public let weaponIds: [Int]
    public let hits: [SkillHit]
    public let variants: [SkillVariant]

    public var displayName: String { nameZh.isEmpty ? nameEn : nameZh }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = container.skillInt(.id, default: -1)
        nameZh = container.skillString(.nameZh)
        nameEn = container.skillString(.nameEn)
        weaponIds = container.skillIntArray(.weaponIds)
        hits = container.skillArray(.hits)
        variants = container.skillArray(.variants)
    }

    private enum CodingKeys: String, CodingKey {
        case id, nameZh, nameEn, weaponIds, hits, variants
    }
}

public struct SpellEntry: Sendable, Hashable, Identifiable, Decodable {
    public let id: Int
    public let nameZh: String
    public let nameEn: String
    /// sorcery / incantation / pyromancy。
    public let kind: String
    public let kindZh: String
    public let mp: Int
    public let hits: [SkillHit]

    public var displayName: String { nameZh.isEmpty ? nameEn : nameZh }
    public var isSorcery: Bool { kind == "sorcery" }
    public var isIncantation: Bool { kind == "incantation" || kind == "pyromancy" }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = container.skillInt(.id, default: -1)
        nameZh = container.skillString(.nameZh)
        nameEn = container.skillString(.nameEn)
        kind = container.skillString(.kind)
        kindZh = container.skillString(.kindZh)
        mp = container.skillInt(.mp, default: 0)
        hits = container.skillArray(.hits)
    }

    private enum CodingKeys: String, CodingKey {
        case id, nameZh, nameEn, kind, kindZh, mp, hits
    }
}

public struct SkillDataset: Sendable {
    public let schemaVersion: Int
    public let gameVersion: String
    public let dataVersion: String
    public let generatedAt: String
    public let sources: [SkillSource]
    public let counts: [String: Double]
    /// 数据集自带的算法说明（页面底部原样展示）。
    public let usage: [String: String]
    public let caveats: [String]
    public let weapons: [SkillWeapon]
    public let skills: [SkillEntry]
    public let spells: [SpellEntry]

    public static func decode(from data: Data) throws -> SkillDataset {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              object is [String: Any] else {
            throw SkillDataError.notAnObject
        }
        do {
            return try JSONDecoder().decode(SkillDataset.self, from: data)
        } catch {
            throw SkillDataError.undecodable(String(describing: error))
        }
    }
}

extension SkillDataset: Decodable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = container.skillInt(.schemaVersion, default: 0)
        gameVersion = container.skillString(.gameVersion)
        dataVersion = container.skillString(.dataVersion)
        generatedAt = container.skillString(.generatedAt)
        sources = container.skillArray(.sources)
        var numbers: [String: Double] = [:]
        for (key, value) in container.skillNumberDictionary(.counts) { numbers[key] = value }
        counts = numbers
        usage = container.skillStringDictionary(.usage)
        caveats = container.skillArray(.caveats)
        weapons = container.skillArray(.weapons)
        skills = container.skillArray(.skills)
        spells = container.skillArray(.spells)
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, gameVersion, dataVersion, generatedAt, sources
        case counts, usage, caveats, weapons, skills, spells
    }
}

// MARK: - 分段命中（已按所选武器算好相对伤害）

/// 一段命中在某个伤害通道上的贡献。`motionPercent` / `flat` 原样来自数据集，
/// `amount` 是按「武器基础攻击力 × motion/100 + flat（+ addBaseAtk 的一份基础攻击力）」算出的相对值。
public struct SkillSegmentComponent: Sendable, Hashable, Identifiable {
    public let channel: SkillDamageChannel
    public let motionPercent: Double?
    public let flat: Double?
    public let baseAttack: Double?
    public let amount: Double

    public var id: Int { channel.rawValue }
}

public struct SkillSegment: Sendable, Hashable, Identifiable {
    public let atkId: Int
    public let labelZh: String
    public let labelEn: String
    public let components: [SkillSegmentComponent]
    /// 单段削韧 = poise + 武器 poiseDamageBase × poiseMv / 100。
    public let poise: Double
    /// 单段耐力削减 = stamina + 武器 staminaBase × staminaMv / 100。
    public let stamina: Double
    public let isBullet: Bool
    public let noFp: Bool
    public let noDamage: Bool
    public let attributeZh: String
    /// 这一段的物理伤害类型（attribute 已解析到武器的 atkAttribute / atkAttribute2）。
    public let physicalChannel: SkillDamageChannel?
    public let total: Double

    public var id: Int { atkId }
    public var hasDamage: Bool { total > 0 }

    public func amount(_ channel: SkillDamageChannel) -> Double {
        components.first { $0.channel == channel }?.amount ?? 0
    }
}

/// 构成明细里的一格。
public struct SkillChannelShare: Sendable, Hashable, Identifiable {
    public let channel: SkillDamageChannel
    public let share: Double
    public let amount: Double

    public var id: Int { channel.rawValue }
}

/// 勾选的段汇总出的相对伤害构成。
public struct SkillDamageComposition: Sendable, Equatable {
    /// 按 `SkillDamageChannel.rawValue` 索引的相对伤害量。
    public let amounts: [Double]
    public let total: Double
    public let segmentCount: Int

    public static let empty = SkillDamageComposition(amounts: Array(repeating: 0, count: SkillDamageChannel.allCases.count), total: 0, segmentCount: 0)

    public init(amounts: [Double], total: Double, segmentCount: Int) {
        self.amounts = amounts
        self.total = total
        self.segmentCount = segmentCount
    }

    public func amount(_ channel: SkillDamageChannel) -> Double {
        amounts.indices.contains(channel.rawValue) ? amounts[channel.rawValue] : 0
    }

    /// 占比（0…1）；总量为 0 时一律 0。
    public func share(_ channel: SkillDamageChannel) -> Double {
        total > 0 ? amount(channel) / total : 0
    }

    /// 按 `SkillDamageChannel.rawValue` 索引的占比数组，供排名引擎直接加权。
    public var shares: [Double] {
        guard total > 0 else { return Array(repeating: 0, count: SkillDamageChannel.allCases.count) }
        return amounts.map { $0 / total }
    }

    /// 有占比的通道，按占比降序（相同占比按通道顺序）。
    public var breakdown: [SkillChannelShare] {
        SkillDamageChannel.allCases
            .map { SkillChannelShare(channel: $0, share: share($0), amount: amount($0)) }
            .filter { $0.share > 0.0000001 }
            .sorted { lhs, rhs in
                lhs.share == rhs.share ? lhs.channel.rawValue < rhs.channel.rawValue : lhs.share > rhs.share
            }
    }

    public var physicalShare: Double {
        SkillDamageChannel.allCases.filter(\.isPhysical).reduce(0) { $0 + share($1) }
    }

    public var isEmpty: Bool { total <= 0 }
}

// MARK: - 选段与构成

public enum SkillDamageMath {
    /// 把一段命中换算成相对伤害。`weapon` 为 nil（法术）时不使用 motion，只用 flat。
    ///
    /// - 近战武器段：amount[el] = 攻击力[el] × motion[el] / 100 + flat[el]（addBaseAtk 再加一份攻击力[el]）；
    /// - 法术 / 子弹段：法术的 motion 是「照抄武器攻击力 100%」的占位写法，只用 flat。
    ///
    /// `hit.noDamage`（数据集标出来的「只挂状态、不产生伤害」的段）一律**短路**：构成为空、
    /// total 为 0，motion / flat / addBaseAtk 一个都不累加。与 Windows 端 hitContribution
    /// 第一行的 `if (!hit || hit.noDamage) return out;` 同一口径——本作有 8 段是
    /// `noDamage + addBaseAtk`（癫火突击、灭洛斯的狂嚎…），照 addBaseAtk 累加会凭空造出
    /// 一整份武器攻击力，勾进构成后占比、排名与推荐组合全部偏掉。
    public static func segment(for hit: SkillHit, weapon: SkillWeapon?) -> SkillSegment {
        let physicalChannel = hit.attribute.channel(weapon: weapon)
        var byChannel: [SkillDamageChannel: SkillSegmentComponent] = [:]

        for element in SkillElement.allCases where !hit.noDamage {
            let motion = hit.motion[element]
            let flat = hit.flat[element]
            let base = weapon?.attack(element) ?? 0
            let useMotion = weapon != nil
            var amount = 0.0
            if useMotion, let motion { amount += base * motion / 100 }
            if let flat { amount += flat }
            var baseAttack: Double? = nil
            if hit.addBaseAtk, base > 0 {
                amount += base
                baseAttack = base
            }
            guard motion != nil || flat != nil || baseAttack != nil else { continue }
            let channel = element == .physical ? physicalChannel : SkillDamageChannel.channel(for: element)
            let component = SkillSegmentComponent(
                channel: channel,
                motionPercent: useMotion ? motion : nil,
                flat: flat,
                baseAttack: baseAttack,
                amount: max(0, amount)
            )
            // 同一通道只会来自一个属性槽，这里仍做一次合并以防数据出现重复键。
            if let existing = byChannel[channel] {
                byChannel[channel] = SkillSegmentComponent(
                    channel: channel,
                    motionPercent: existing.motionPercent ?? component.motionPercent,
                    flat: (existing.flat ?? 0) + (component.flat ?? 0),
                    baseAttack: (existing.baseAttack ?? 0) + (component.baseAttack ?? 0),
                    amount: existing.amount + component.amount
                )
            } else {
                byChannel[channel] = component
            }
        }

        let components = byChannel.values.sorted { $0.channel.rawValue < $1.channel.rawValue }
        let total = components.reduce(0) { $0 + $1.amount }
        let poise = hit.poise + (weapon?.poiseDamageBase ?? 0) * hit.poiseMv / 100
        let stamina = hit.stamina + (weapon?.staminaBase ?? 0) * hit.staminaMv / 100
        let hasPhysical = components.contains { $0.channel.isPhysical }

        return SkillSegment(
            atkId: hit.atkId,
            labelZh: hit.displayLabel,
            labelEn: hit.label ?? "",
            components: components,
            poise: poise,
            stamina: stamina,
            isBullet: hit.isBullet,
            noFp: hit.noFp,
            noDamage: hit.noDamage,
            attributeZh: hit.attributeZh,
            physicalChannel: hasPhysical ? physicalChannel : nil,
            total: total
        )
    }

    /// 默认勾选：当前 FP 侧、非 noDamage 的段（默认在 FP 侧）。
    public static func defaultSelection(_ segments: [SkillSegment]) -> Set<Int> {
        selection(segments, useNoFp: false)
    }

    /// 「无 FP 版」与「FP 版」互斥切换：只勾这一侧的段。
    ///
    /// 两侧互为替代，一起勾会把同一击算两遍，相对值合计直接翻倍、构成与排名权重跟着失真，
    /// 所以这里不做「这一侧为空就退回另一侧」的兜底（本版本数据里也不存在整套只有无 FP 版的动作套）。
    /// 与 Windows 端 hitEnabled / hitOverridesFor 同一口径：数值为 0 但没标 noDamage 的段照样勾上，
    /// 它对构成的贡献本来就是 0。
    public static func selection(_ segments: [SkillSegment], useNoFp: Bool) -> Set<Int> {
        Set(segments.filter { $0.noFp == useNoFp && !$0.noDamage }.map(\.atkId))
    }

    /// 汇总勾选的段：各通道相对伤害量 → 占比。
    public static func composition(of segments: [SkillSegment], selected: Set<Int>) -> SkillDamageComposition {
        var amounts = Array(repeating: 0.0, count: SkillDamageChannel.allCases.count)
        var total = 0.0
        var count = 0
        for segment in segments where selected.contains(segment.atkId) {
            count += 1
            for component in segment.components {
                amounts[component.channel.rawValue] += component.amount
                total += component.amount
            }
        }
        return SkillDamageComposition(amounts: amounts, total: total, segmentCount: count)
    }
}

// MARK: - 页面用的输出手段

/// 搜索框里的一条「输出手段」：战技或法术。
public struct SkillOutput: Sendable, Hashable, Identifiable {
    public enum Kind: String, Sendable, Hashable {
        case skill
        case spell
    }

    public let kind: Kind
    public let entryID: Int
    public let nameZh: String
    public let nameEn: String
    /// 法术为「魔法」/「祷告」，战技为武器数量说明。
    public let subtitleZh: String
    public let weaponCount: Int
    public let segmentCount: Int
    let searchKey: String

    public var id: String { "\(kind.rawValue)-\(entryID)" }
    public var displayName: String { nameZh.isEmpty ? nameEn : nameZh }

    public func matches(foldedQuery: String) -> Bool {
        guard !foldedQuery.isEmpty else { return true }
        if foldedQuery.allSatisfy(\.isNumber) { return String(entryID).hasPrefix(foldedQuery) }
        return searchKey.contains(foldedQuery)
    }
}

/// 战技的武器选择：按武器类别分组。
public struct SkillWeaponGroup: Sendable, Hashable, Identifiable {
    public let wepTypeZh: String
    public let weapons: [SkillWeapon]

    public var id: String { wepTypeZh }
}

public struct SkillDataIndex: Sendable {
    public let dataset: SkillDataset
    public let weaponsByID: [Int: SkillWeapon]
    public let skillsByID: [Int: SkillEntry]
    public let spellsByID: [Int: SpellEntry]
    /// 可选的输出手段。收录条件与 Windows 端 buildMeansItems 一致：
    /// 战技要有命中段 + 至少一把引用它的武器 + 至少一种选法算得出非 0 相对值；
    /// 法术要有命中段且至少一段带固定值。
    public let outputs: [SkillOutput]
    /// 有命中段但本作没有任何武器引用的战技数量（页面底部说明用）。
    public let skillsWithoutWeapons: Int
    /// 完全没有命中段的战技 / 法术数量（纯增益、格挡、附魔一类）。
    public let skillsWithoutHits: Int
    public let spellsWithoutHits: Int
    /// 有命中段、也有武器，但每一段都算不出伤害（全是 noDamage / 纯挂状态）的战技数。
    public let skillsWithoutDamage: Int
    /// 有命中段但一段固定值都没有的法术数（恢复／庇佑／附魔类）。
    public let spellsWithoutDamage: Int

    public init(dataset: SkillDataset) throws {
        self.dataset = dataset
        weaponsByID = Dictionary(dataset.weapons.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        skillsByID = Dictionary(dataset.skills.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        spellsByID = Dictionary(dataset.spells.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        var outputs: [SkillOutput] = []
        var withoutWeapons = 0
        var skillsNoHits = 0
        var skillsNoDamage = 0
        for skill in dataset.skills {
            if skill.hits.isEmpty {
                skillsNoHits += 1
                continue
            }
            if skill.weaponIds.isEmpty {
                withoutWeapons += 1
                continue
            }
            // 一段都算不出非 0 相对值的战技（纯增益 / 只挂异常状态）选中后构成恒为 0，是死路。
            guard Self.skillHasDamage(skill, weaponsByID: weaponsByID) else {
                skillsNoDamage += 1
                continue
            }
            let weapons = skill.weaponIds.count
            outputs.append(
                SkillOutput(
                    kind: .skill,
                    entryID: skill.id,
                    nameZh: skill.nameZh,
                    nameEn: skill.nameEn,
                    subtitleZh: "战技 · \(weapons) 把武器",
                    weaponCount: weapons,
                    segmentCount: skill.hits.count,
                    searchKey: "\(skill.nameZh) \(skill.nameEn) 战技".foldedForSearch
                )
            )
        }

        var spellsNoHits = 0
        var spellsNoDamage = 0
        for spell in dataset.spells {
            if spell.hits.isEmpty {
                spellsNoHits += 1
                continue
            }
            // 法术没有武器，构成只来自 flat；一个 flat 都没有的（冰雾、各种恢复／庇佑／防护）排除。
            guard spell.hits.contains(where: { SkillDamageMath.segment(for: $0, weapon: nil).hasDamage }) else {
                spellsNoDamage += 1
                continue
            }
            let kindZh = spell.kindZh.isEmpty ? (spell.isSorcery ? "魔法" : "祷告") : spell.kindZh
            outputs.append(
                SkillOutput(
                    kind: .spell,
                    entryID: spell.id,
                    nameZh: spell.nameZh,
                    nameEn: spell.nameEn,
                    subtitleZh: "\(kindZh) · FP \(spell.mp)",
                    weaponCount: 0,
                    segmentCount: spell.hits.count,
                    searchKey: "\(spell.nameZh) \(spell.nameEn) \(kindZh)".foldedForSearch
                )
            )
        }

        guard !outputs.isEmpty else { throw SkillDataError.empty }
        self.outputs = outputs
        skillsWithoutWeapons = withoutWeapons
        skillsWithoutHits = skillsNoHits
        spellsWithoutHits = spellsNoHits
        skillsWithoutDamage = skillsNoDamage
        spellsWithoutDamage = spellsNoDamage
    }

    /// 至少有一把引用它的武器能打出非 0 相对值（与 Windows 端 skillHasDamage 同一口径）。
    static func skillHasDamage(_ skill: SkillEntry, weaponsByID: [Int: SkillWeapon]) -> Bool {
        for id in skill.weaponIds {
            guard let weapon = weaponsByID[id] else { continue }
            let hits: [SkillHit]
            if skill.variants.isEmpty {
                hits = fallbackHits(for: skill, weapon: weapon)
            } else if let index = weapon.skillVariant, skill.variants.indices.contains(index) {
                let ids = Set(skill.variants[index].atkIds)
                hits = skill.hits.filter { ids.contains($0.atkId) }
            } else {
                continue
            }
            if hits.contains(where: { SkillDamageMath.segment(for: $0, weapon: weapon).hasDamage }) {
                return true
            }
        }
        return false
    }

    public init(data: Data) throws {
        try self.init(dataset: SkillDataset.decode(from: data))
    }

    public func outputs(matching query: String) -> [SkillOutput] {
        let needle = query.foldedForSearch
        guard !needle.isEmpty else { return outputs }
        return outputs.filter { $0.matches(foldedQuery: needle) }
    }

    // MARK: 武器

    /// 某个战技可用的武器，按武器类别分组（类别内按武器 id 升序，类别按武器数量降序）。
    public func weaponGroups(for skill: SkillEntry) -> [SkillWeaponGroup] {
        var grouped: [String: [SkillWeapon]] = [:]
        for id in skill.weaponIds {
            guard let weapon = weaponsByID[id] else { continue }
            let key = weapon.wepTypeZh.isEmpty ? weapon.wepTypeEn : weapon.wepTypeZh
            grouped[key, default: []].append(weapon)
        }
        return grouped
            .map { SkillWeaponGroup(wepTypeZh: $0.key, weapons: $0.value.sorted { $0.id < $1.id }) }
            .sorted { lhs, rhs in
                lhs.weapons.count == rhs.weapons.count
                    ? lhs.wepTypeZh < rhs.wepTypeZh
                    : lhs.weapons.count > rhs.weapons.count
            }
    }

    public func defaultWeapon(for skill: SkillEntry) -> SkillWeapon? {
        weaponGroups(for: skill).first?.weapons.first
    }

    // MARK: 选段

    /// 这把武器打出的段（usage.选段（必读））：
    /// `variants[weapon.skillVariant].atkIds`；variants 缺失时才退回 ctx 单选逻辑。
    ///
    /// **variants 存在时一律以 skillVariant 为准**：数据集写明「skillVariant 缺失表示该武器的
    /// 战技没有任何命中段」，所以缺失 / 越界就是「打不出段」，不按 weaponIds 回查、也不退回
    /// ctx 逻辑——那样会把数据问题盖掉。与 Windows 端 selectHits 同一口径。
    public func hits(for skill: SkillEntry, weapon: SkillWeapon?) -> [SkillHit] {
        if !skill.variants.isEmpty {
            guard let weapon, let index = weapon.skillVariant,
                  skill.variants.indices.contains(index) else { return [] }
            let ids = Set(skill.variants[index].atkIds)
            return skill.hits.filter { ids.contains($0.atkId) }
        }
        return Self.fallbackHits(for: skill, weapon: weapon)
    }

    /// variants 缺失时的退回逻辑：先 ctx == 武器 nameEn，再 ctx == wepTypeEn，
    /// 最后 ctx 缺失的那组 —— **单选，不取并集**；一个都对不上就是打不出段。
    /// 按 ctx 取并集会把通用战技（战吼 290 段、野蛮咆哮 358 段）重复统计几十遍。
    static func fallbackHits(for skill: SkillEntry, weapon: SkillWeapon?) -> [SkillHit] {
        if let weapon, !weapon.nameEn.isEmpty {
            let byName = skill.hits.filter { $0.ctx == weapon.nameEn }
            if !byName.isEmpty { return byName }
        }
        if let weapon, !weapon.wepTypeEn.isEmpty {
            let byType = skill.hits.filter { $0.ctx == weapon.wepTypeEn }
            if !byType.isEmpty { return byType }
        }
        return skill.hits.filter { $0.ctx == nil }
    }

    public func segments(for skill: SkillEntry, weapon: SkillWeapon?) -> [SkillSegment] {
        hits(for: skill, weapon: weapon).map { SkillDamageMath.segment(for: $0, weapon: weapon) }
    }

    /// 法术：没有 variants，全部段都会打出；只用 flat 做配比（见 usage.法术 / 子弹段）。
    public func segments(for spell: SpellEntry) -> [SkillSegment] {
        spell.hits.map { SkillDamageMath.segment(for: $0, weapon: nil) }
    }

    public var summary: String {
        let weapons = dataset.weapons.count
        let skills = dataset.skills.count
        let spells = dataset.spells.count
        return "\(weapons) 把武器 · \(skills) 个战技 · \(spells) 个法术"
    }
}
