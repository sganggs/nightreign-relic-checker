import Foundation

// 「增伤排名」页上半部分的数据模型：武器 / 战技 / 法术与它们的分段命中。
//
// 数据来源：Resources/skills.json（schemaVersion 3，更早的版本拒绝解码），经
// `GameDataLoader.dataIfAvailable(for: .skills)` 读出原始 Data 后在这里解码。
//
// 解码原则（数据集由另一条流水线维护，字段随时可能增删）：
//   * 未知字段一律忽略；
//   * 已知字段缺失 / 类型不符时退回默认值，**不抛错**；
//   * 数组逐元素解码，坏元素跳过而不是整份失败。
// 只有「顶层不是 JSON 对象」「schemaVersion < 3」「武器与战技全空」这种读不懂的情况才抛 `SkillDataError`。
//
// 关键算法（严格按数据集 usage 块，见页面底部的「原文」折叠区）：
//   * 选段：weapons[].skillVariants[战技 ID] → skills[].variants[i].atkIds，**不要**按 ctx 取并集；
//     skillVariants 缺这个战技时，只有「它就是武器的 swordArtsParamId」才回退 weapons[].skillVariant
//     （v3 起 skillVariant 只对固定战技有效，池里抽到的战技一律看 skillVariants）；
//   * 武器来源（v3）：skills[].weaponIds = 固定引用 ∪ 局内战技池；逐把来源看 skills[].weaponSources；
//   * 法术来源（v3 修订）：spells[] 只收施法器能带的法术（风暴管束者 8100 / 8101 这类 Magic 残留行不在里面，
//     见 coverage.spellsNotCastable）；能带它的施法器看 spells[].casterWeaponIds / casterSources，池看顶层 magicPools；
//   * 正常版 / 专注值不足版：取段规则是 `hit.fpBoth || hit.noFp == 开关`（fpBoth 段两侧都计）；
//   * 页面只从 variants 取段；任何直接回到 hits[] 的路径都过滤 notInvoked 与 noDamage；
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
    case unsupportedSchema(Int)
    case empty

    public var errorDescription: String? {
        switch self {
        case .notAnObject: return "战技数据不是合法的 JSON 对象"
        case .undecodable(let detail): return "战技数据无法解码：" + detail
        case .unsupportedSchema(let version):
            return "战技数据是 schemaVersion \(version)：本页按 v3 的 skillVariants / weaponSources 选段，"
                + "需要 schemaVersion \(SkillDataset.minimumSchemaVersion) 或更新的数据"
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

    /// `{"123": 0, ...}` 这种「字符串形式的整数键 → 整数」字典（weapons[].skillVariants）。
    /// 键不是整数、值不是有限数的项跳过。
    func skillIntKeyedIntDictionary(_ key: Key) -> [Int: Int] {
        guard let wrapped = try? decodeIfPresent([String: SkillFailable<Double>].self, forKey: key) else { return [:] }
        var result: [Int: Int] = [:]
        for (rawKey, value) in wrapped {
            guard let id = Int(rawKey.trimmingCharacters(in: .whitespaces)),
                  let number = value.value, number.isFinite else { continue }
            result[id] = Int(number.rounded())
        }
        return result
    }

    /// `[[1, 2, 3], ...]` 这种整数元组数组（weaponSources[].pool、weapons[].customWeapons）。
    /// 坏元素（不是数组、元素不是数）跳过，不让整份失败。
    func skillIntTuples(_ key: Key) -> [[Int]] {
        guard let wrapped = try? decodeIfPresent([SkillFailable<[SkillFailable<Double>]>].self, forKey: key) else { return [] }
        return wrapped.compactMap { row -> [Int]? in
            guard let items = row.value else { return nil }
            let numbers = items.compactMap(\.value)
            guard numbers.count == items.count, numbers.allSatisfy(\.isFinite) else { return nil }
            return numbers.map { Int($0.rounded()) }
        }
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
    /// 该武器在「它的**固定**战技（swordArtsParamId）」variants 数组里的下标；缺失表示这把武器的
    /// 固定战技没有命中段。v3 起只对固定战技有效——选段一律先看 `skillVariants`（见 `variantIndex(forSkill:)`）。
    public let skillVariant: Int?
    /// v3：这把武器局内可能出现的全部战技 ID（固定 + 可达 custom 行的池成员），升序。
    public let skillIds: [Int]
    /// v3：{战技 ID: 该战技 variants 的下标}，对每个 (战技, 武器) 对按 BehaviorParam_PC 实解。
    public let skillVariants: [Int: Int]
    /// v3：以这把武器为 targetWeaponId 的可达 EquipParamCustomWeapon 行。
    public let customWeapons: [SkillCustomWeapon]
    /// v3 修订（施法器）：可达 custom 行里至少一个法术槽不是 -1 的那些行，两个槽各从自己的池里抽一个法术。
    public let customMagicTables: [SkillCustomMagicTable]

    public var displayName: String { nameZh.isEmpty ? nameEn : nameZh }

    /// 这把武器用某个战技时的 variants 下标（usage.选段（必读））：
    /// 先看 `skillVariants[战技 ID]`；缺失时**只有**这个战技就是武器的 swordArtsParamId，才回退 `skillVariant`
    /// ——skillVariant 是固定战技的下标，拿去套池里抽到的别的战技会选错动作套。
    public func variantIndex(forSkill skillID: Int) -> Int? {
        if let index = skillVariants[skillID] { return index }
        return skillID == swordArtsParamId ? skillVariant : nil
    }

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
        skillIds = container.skillIntArray(.skillIds)
        skillVariants = container.skillIntKeyedIntDictionary(.skillVariants)
        customWeapons = container.skillIntTuples(.customWeapons).compactMap { row in
            row.count >= 2 ? SkillCustomWeapon(customId: row[0], swordArtsTableId: row[1]) : nil
        }
        customMagicTables = container.skillIntTuples(.customMagicTables).compactMap { row in
            row.count >= 3 ? SkillCustomMagicTable(customId: row[0], magicTableIds: [row[1], row[2]]) : nil
        }
    }

    private enum CodingKeys: String, CodingKey {
        case id, nameZh, nameEn, wepType, wepTypeZh, wepTypeEn, rarityZh
        case attackBase, staminaBase, poiseDamageBase, swordArtsParamId
        case atkAttribute, atkAttributeZh, atkAttribute2, atkAttribute2Zh, skillVariant
        case skillIds, skillVariants, customWeapons, customMagicTables
    }

    /// 自检 / 预览用的直接构造。
    public init(
        id: Int, nameZh: String, nameEn: String = "", wepType: Int = 0,
        wepTypeZh: String = "", wepTypeEn: String = "", rarityZh: String = "",
        attackBase: [SkillElement: Double] = [:], staminaBase: Double = 0,
        poiseDamageBase: Double = 0, swordArtsParamId: Int = -1,
        atkAttribute: Int = 3, atkAttributeZh: String = "标准",
        atkAttribute2: Int = 3, atkAttribute2Zh: String = "标准",
        skillVariant: Int? = nil, skillIds: [Int] = [], skillVariants: [Int: Int] = [:],
        customWeapons: [SkillCustomWeapon] = [], customMagicTables: [SkillCustomMagicTable] = []
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
        self.skillIds = skillIds
        self.skillVariants = skillVariants
        self.customWeapons = customWeapons
        self.customMagicTables = customMagicTables
    }
}

/// weapons[].customMagicTables 的一项：[customId, magicTableId_1, magicTableId_2]（-1 = 这个槽不抽法术）。
public struct SkillCustomMagicTable: Sendable, Hashable {
    public let customId: Int
    /// 两个法术槽各自的 MagicTableParam 池 ID（同一行两个槽要分开算）。
    public let magicTableIds: [Int]

    public init(customId: Int, magicTableIds: [Int]) {
        self.customId = customId
        self.magicTableIds = magicTableIds
    }
}

/// weapons[].customWeapons 的一项：[customId, swordArtsTableId]（-1 = 该行不抽池，沿用武器自带的战技）。
public struct SkillCustomWeapon: Sendable, Hashable {
    public let customId: Int
    public let swordArtsTableId: Int

    public init(customId: Int, swordArtsTableId: Int) {
        self.customId = customId
        self.swordArtsTableId = swordArtsTableId
    }
}

/// 这把武器带某个战技的来源（v3 skills[].weaponSources）。同一把武器两者都成立时只算「固定」。
public enum SkillWeaponSourceKind: String, Sendable, Hashable, CaseIterable {
    /// EquipParamWeapon.swordArtsParamId 就是这个战技。
    case fixed
    /// 只在局内战技池（EquipParamCustomWeapon → SwordArtsTableParam）里抽得到。
    case pool

    /// 文案键（LoadoutText.table：weaponSource.fixed / weaponSource.pool）。
    public var textKey: String { "weaponSource." + rawValue }

    /// 页面上的标记：「固定战技」「局内可抽到」（与 Windows 端 TEXT.weaponSource 同文）。
    public var title: String { LoadoutText.t(textKey) }
}

/// skills[].weaponSources[].pool 的一项：[swordArtsTableId, chanceWeight, customRows]。
public struct SkillPoolDraw: Sendable, Hashable {
    public let poolId: Int
    public let weight: Int
    public let customRows: Int

    public init(poolId: Int, weight: Int, customRows: Int) {
        self.poolId = poolId
        self.weight = weight
        self.customRows = customRows
    }
}

/// skills[].weaponSources 的一项（与 weaponIds 同序）：{id, fixed?, pool?}。
public struct SkillWeaponSource: Sendable, Hashable, Decodable {
    public let weaponId: Int
    public let fixed: Bool
    public let pool: [SkillPoolDraw]

    /// 页面标记：两者都成立时只标固定。
    public var kind: SkillWeaponSourceKind { fixed ? .fixed : .pool }

    public init(weaponId: Int, fixed: Bool, pool: [SkillPoolDraw] = []) {
        self.weaponId = weaponId
        self.fixed = fixed
        self.pool = pool
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        weaponId = container.skillInt(.id, default: -1)
        fixed = container.skillBool(.fixed)
        pool = container.skillIntTuples(.pool).compactMap { row in
            row.count >= 2 ? SkillPoolDraw(poolId: row[0], weight: row[1], customRows: row.count >= 3 ? row[2] : 0) : nil
        }
    }

    private enum CodingKeys: String, CodingKey {
        case id, fixed, pool
    }
}

/// counts 里的布尔项（其余计数是数字，走 `SkillDataset.counts`）。
struct SkillCountFlags: Decodable {
    let taeVerified: Bool

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        taeVerified = container.skillBool(.taeVerified)
    }

    private enum CodingKeys: String, CodingKey {
        case taeVerified
    }
}

/// spells[].casterSources 的一项（与 casterWeaponIds 同序）：{id, pool}。法术没有「固定」来源，全部来自施法器
/// custom 行的法术槽；pool 的每项是 [magicTableId, chanceWeight, customRows]，结构同 weaponSources[].pool。
public struct SpellCasterSource: Sendable, Hashable, Decodable {
    public let weaponId: Int
    public let pool: [SkillPoolDraw]

    public init(weaponId: Int, pool: [SkillPoolDraw] = []) {
        self.weaponId = weaponId
        self.pool = pool
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        weaponId = container.skillInt(.id, default: -1)
        pool = container.skillIntTuples(.pool).compactMap { row in
            row.count >= 2 ? SkillPoolDraw(poolId: row[0], weight: row[1], customRows: row.count >= 3 ? row[2] : 0) : nil
        }
    }

    private enum CodingKeys: String, CodingKey {
        case id, pool
    }
}

/// 顶层 swordArtsPools 的一项：[战技 ID, chanceWeight]。
public struct SkillPoolEntry: Sendable, Hashable {
    public let skillId: Int
    public let weight: Int

    public init(skillId: Int, weight: Int) {
        self.skillId = skillId
        self.weight = weight
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
    /// 专注值不足时打出的弱化版分支（与正常版互为替代，不相加）。
    public let noFp: Bool
    /// v3：noFp 由 TAE 判出时为 "tae"；nil = 来自行名里的 "No FP"。
    public let noFpSource: String?
    /// v3：带 FP / 无 FP 两侧动画共用的段——无论开关在哪一侧都计入（noFp 一定是 false）。
    public let fpBoth: Bool
    public let noDamage: Bool
    /// v3：只打自己 / 队友（自疗子弹等），数据集同时标了 noDamage。
    public let selfOrAllyOnly: Bool
    /// 该段所属动作套在本作没有任何武器会用到，按选段算法永远取不到。
    public let noVariant: Bool
    /// v3（TAE 核实）：所有解到它的武器的动画都不调用它，已从 variants 移除；只在 hits[] 里保留。
    public let notInvoked: Bool
    /// notInvoked 的原因（enums.notInvokedReason 的键）。
    public let notInvokedReason: String?
    public let addBaseAtk: Bool

    public var id: Int { atkId }

    /// 按「专注值不足版」开关取段：fpBoth 段两侧都计，其余段只取与开关同侧的。
    public func isOnSide(useNoFp: Bool) -> Bool {
        fpBoth || noFp == useNoFp
    }

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
        noFpSource = container.skillOptionalString(.noFpSource)
        fpBoth = container.skillBool(.fpBoth)
        noDamage = container.skillBool(.noDamage)
        selfOrAllyOnly = container.skillBool(.selfOrAllyOnly)
        noVariant = container.skillBool(.noVariant)
        notInvoked = container.skillBool(.notInvoked)
        notInvokedReason = container.skillOptionalString(.notInvokedReason)
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
        case isBullet, noFp, noFpSource, fpBoth, noDamage, selfOrAllyOnly, noVariant
        case notInvoked, notInvokedReason, addBaseAtk
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
    /// v3：能带这个战技的全部武器 = 固定引用（swordArtsParamId）∪ 局内战技池能抽到它的基础武器。
    public let weaponIds: [Int]
    /// v3：与 weaponIds 同序的来源（fixed / pool）。
    public let weaponSources: [SkillWeaponSource]
    public let hits: [SkillHit]
    public let variants: [SkillVariant]
    /// v3（TAE 核实）：战技动画匹配不到（本版本是弓系战技），hits / variants 没做 TAE 过滤。
    public let taeUnmatched: Bool

    public var displayName: String { nameZh.isEmpty ? nameEn : nameZh }

    /// 这把武器的来源记录（weaponSources 里 id 相同的那一项）。
    public func weaponSource(for weaponID: Int) -> SkillWeaponSource? {
        weaponSources.first { $0.weaponId == weaponID }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = container.skillInt(.id, default: -1)
        nameZh = container.skillString(.nameZh)
        nameEn = container.skillString(.nameEn)
        weaponIds = container.skillIntArray(.weaponIds)
        weaponSources = container.skillArray(.weaponSources)
        hits = container.skillArray(.hits)
        variants = container.skillArray(.variants)
        taeUnmatched = container.skillBool(.taeUnmatched)
    }

    private enum CodingKeys: String, CodingKey {
        case id, nameZh, nameEn, weaponIds, weaponSources, hits, variants, taeUnmatched
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
    /// v3 修订：能带这个法术的施法器（基础武器 ID，升序）；来源逐把见 `casterSources`。
    public let casterWeaponIds: [Int]
    /// v3 修订：与 casterWeaponIds 同序的来源（哪些池、池内权重、几行 custom 行）。
    public let casterSources: [SpellCasterSource]

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
        casterWeaponIds = container.skillIntArray(.casterWeaponIds)
        casterSources = container.skillArray(.casterSources)
    }

    private enum CodingKeys: String, CodingKey {
        case id, nameZh, nameEn, kind, kindZh, mp, hits, casterWeaponIds, casterSources
    }
}

public struct SkillDataset: Sendable {
    /// 本页按 v3 的 skillVariants / weaponSources / fpBoth / notInvoked 选段，更早的数据拒绝解码。
    public static let minimumSchemaVersion = 3

    public let schemaVersion: Int
    public let gameVersion: String
    public let dataVersion: String
    public let generatedAt: String
    public let sources: [SkillSource]
    public let counts: [String: Double]
    /// counts.taeVerified（v3）：命中段是否按 TAE 动画事件核实过。它是布尔值，不在 `counts` 里。
    public let taeVerified: Bool
    /// 数据集自带的算法说明（页面底部原样展示）。
    public let usage: [String: String]
    public let caveats: [String]
    public let weapons: [SkillWeapon]
    public let skills: [SkillEntry]
    public let spells: [SpellEntry]
    /// v3 顶层 swordArtsPools：{池 ID: [[战技 ID, chanceWeight], ...]}（只收被可达 custom 行引用的池）。
    public let swordArtsPools: [Int: [SkillPoolEntry]]
    /// v3 修订顶层 magicPools：{MagicTableParam 池 ID: [[法术 ID, chanceWeight], ...]}（只收被可达施法器 custom 行
    /// 引用的池、chanceWeight>0 的条目）。`SkillPoolEntry.skillId` 在这里是法术（Magic）ID。
    public let magicPools: [Int: [SkillPoolEntry]]

    public static func decode(from data: Data) throws -> SkillDataset {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              object is [String: Any] else {
            throw SkillDataError.notAnObject
        }
        let dataset: SkillDataset
        do {
            dataset = try JSONDecoder().decode(SkillDataset.self, from: data)
        } catch {
            throw SkillDataError.undecodable(String(describing: error))
        }
        // v2 没有 skillVariants：池里抽到的战技会拿固定战技的下标选段（选错动作套），宁可不认。
        guard dataset.schemaVersion >= minimumSchemaVersion else {
            throw SkillDataError.unsupportedSchema(dataset.schemaVersion)
        }
        return dataset
    }

    /// 某个池里某个战技的抽取概率（chanceWeight / 池内权重之和）；池或战技不在表里时为 nil。
    public func poolChance(poolId: Int, skillId: Int) -> Double? {
        Self.chance(in: swordArtsPools[poolId], id: skillId)
    }

    /// 某个法术池（magicPools）的一个槽抽到这个法术的概率；池或法术不在表里时为 nil。
    public func magicPoolChance(poolId: Int, spellId: Int) -> Double? {
        Self.chance(in: magicPools[poolId], id: spellId)
    }

    private static func chance(in entries: [SkillPoolEntry]?, id: Int) -> Double? {
        guard let entries, let entry = entries.first(where: { $0.skillId == id }) else { return nil }
        let total = entries.reduce(0) { $0 + max(0, $1.weight) }
        return total > 0 ? Double(entry.weight) / Double(total) : nil
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
        let flags = try? container.decodeIfPresent(SkillCountFlags.self, forKey: .counts)
        taeVerified = flags?.taeVerified ?? false
        usage = container.skillStringDictionary(.usage)
        caveats = container.skillArray(.caveats)
        weapons = container.skillArray(.weapons)
        skills = container.skillArray(.skills)
        spells = container.skillArray(.spells)
        swordArtsPools = SkillDataset.decodePools(container, forKey: .swordArtsPools)
        magicPools = SkillDataset.decodePools(container, forKey: .magicPools)
    }

    /// swordArtsPools / magicPools：键不是整数的池、坏条目一律跳过（宽容解码）。
    private static func decodePools(
        _ container: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys
    ) -> [Int: [SkillPoolEntry]] {
        guard let raw = try? container.decodeIfPresent(
            [String: SkillFailable<[SkillFailable<[SkillFailable<Double>]>]>].self, forKey: key
        ) else { return [:] }
        var pools: [Int: [SkillPoolEntry]] = [:]
        for (key, value) in raw {
            guard let poolId = Int(key), let rows = value.value else { continue }
            pools[poolId] = rows.compactMap { row -> SkillPoolEntry? in
                guard let items = row.value?.compactMap(\.value), items.count >= 2,
                      items[0].isFinite, items[1].isFinite else { return nil }
                return SkillPoolEntry(skillId: Int(items[0].rounded()), weight: Int(items[1].rounded()))
            }
        }
        return pools
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, gameVersion, dataVersion, generatedAt, sources
        case counts, usage, caveats, weapons, skills, spells, swordArtsPools, magicPools
    }
}

// MARK: - 展示层文案

/// 展示层的中文口径工具。**只换展示，不动数据集、不动字段名。**
public enum SkillTextZh {
    /// 与 Windows 端 renderer/pages/ranker.js 的 FP_TEXT_RULES 逐条相同。
    /// 顺序有意义：先认长的写法，最后才把剩下的孤零零 FP 换成「专注值」。
    private static let fpRules: [(pattern: String, replacement: String)] = [
        (#"无\s*FP\s*版"#, "专注值不足版"),
        (#"\s*[Nn]o\s*FP(?:\s*版)?"#, "专注值不足版"),
        (#"带\s*FP(?:\s*版)?"#, "正常版"),
        ("FP", "专注值")
    ]

    /// 数据集原文里还留着英文的 FP——hits[].labelZh 的「无FP版」（v3 本版本 375 段，含 TAE 补标的 213 段）、
    /// caveats 里的「12 段（6 段带 FP + 6 段 No FP）」「No FP 四段」——页面一律说中文的「专注值」。
    ///
    /// 两端都走正则，`\s` 把全角空格一起吃下（ICU 与 JS 的 `\s` 都含 U+3000），
    /// 数据集以后写成「无　FP版」也不会只有一端替换掉。
    ///
    /// 只对这两处**说明文字**用。buffs 数据集里「Determination - Right No FP Damage Buff」
    /// 这类是游戏参数表的英文原名（本版本上百条），套上去只会变成中英夹杂的乱码。
    public static func fpText(_ text: String) -> String {
        guard text.contains("FP") else { return text }
        var out = text
        for rule in fpRules {
            out = out.replacingOccurrences(
                of: rule.pattern, with: rule.replacement, options: [.regularExpression]
            )
        }
        return out
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
    /// 单段削精力（对格挡敌人精力条的削减）= stamina + 武器 staminaBase × staminaMv / 100。
    public let stamina: Double
    public let isBullet: Bool
    public let noFp: Bool
    /// 两侧共用的段（v3 fpBoth）：正常版与专注值不足版都计入。
    public let fpBoth: Bool
    public let noDamage: Bool
    public let attributeZh: String
    /// 这一段的物理伤害类型（attribute 已解析到武器的 atkAttribute / atkAttribute2）。
    public let physicalChannel: SkillDamageChannel?
    public let total: Double

    public var id: Int { atkId }
    public var hasDamage: Bool { total > 0 }

    /// 展示层的段名：把数据集里的「无FP版」换成中文的「专注值不足版」（见 SkillTextZh.fpText）。
    public var displayLabelZh: String { SkillTextZh.fpText(labelZh) }

    /// 芯片行要显示的通道：**只留对当前武器真正有贡献的那些**。
    ///
    /// 动作值（motion）是「武器该属性基础攻击力的百分比」，参数表里每段常常五个属性同值
    /// （尸横遍野每段都是 99%），但武器这一属性 attackBase 为 0 时乘出来恒为 0——
    /// 尸山血海只有物理 46 与火 46，魔力／雷／圣三项对构成与排名毫无影响，
    /// 并排列出来只会让人以为是 bug。判定即「amount > 0」，等价于：
    ///   · 近战段／战技子弹段：attackBase > 0 且（motion > 0 或 flat > 0）；
    ///   · addBaseAtk（额外加一份武器该属性攻击力）**单独也算一条通道**：这一档没有 motion
    ///     也没有 flat 照样出芯片（写成「+基础攻击力」），否则「可见芯片之和 == total」
    ///     这条不变量就不成立——113 主教冲锋 + 23000600 雷电主教大火槌的 #30000831
    ///     数据里只有 flat.fire = 55，真正打出来的 219 里有 164 来自 addBaseAtk；
    ///   · 法术段：weapon 为 nil、motion 不参与，等价于「flat > 0 的属性」。
    /// Windows 端 ranker.js 的 hitChipPlan 是同一口径（两端各有一条全量对照的自检）。
    public var visibleComponents: [SkillSegmentComponent] {
        components.filter { $0.amount > 0 }
    }

    /// 被隐藏的「动作值声明了、但武器该属性攻击力为 0」的通道数。
    /// 只数这一种，用来在芯片行末尾补一句「其余属性该武器为 0」；法术段的 motionPercent
    /// 本来就是 nil（不参与计算），缺席的原因不是武器为 0，所以不会计进来。
    public var hiddenZeroComponentCount: Int {
        components.filter { $0.amount <= 0 && ($0.motionPercent ?? 0) > 0 }.count
    }

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
            fpBoth: hit.fpBoth,
            noDamage: hit.noDamage,
            attributeZh: hit.attributeZh,
            physicalChannel: hasPhysical ? physicalChannel : nil,
            total: total
        )
    }

    /// 默认勾选：正常版这一侧、非 noDamage 的段（默认在正常版侧）。
    public static func defaultSelection(_ segments: [SkillSegment]) -> Set<Int> {
        selection(segments, useNoFp: false)
    }

    /// 「专注值不足版」与「正常版」互斥切换：只勾这一侧的段。
    ///
    /// 两侧互为替代，一起勾会把同一击算两遍，相对值合计直接翻倍、构成与排名权重跟着失真，
    /// 所以这里不做「这一侧为空就退回另一侧」的兜底（本版本数据里也不存在整套只有专注值不足版的动作套）。
    /// 与 Windows 端 hitEnabled / hitOverridesFor 同一口径：数值为 0 但没标 noDamage 的段照样勾上，
    /// 它对构成的贡献本来就是 0。
    ///
    /// v3：取段规则是 `fpBoth || noFp == 开关`——fpBoth 段（带 FP / 无 FP 两侧动画共用，本版本 19 段）
    /// 两侧都计。旧写法 `noFp == 开关` 会在专注值不足版这一侧丢掉它们：1024 唤矛仪式、1021 毁灭灵火
    /// 切过去一段都不剩，218 伟哉卡利亚少了最后一发。
    public static func selection(_ segments: [SkillSegment], useNoFp: Bool) -> Set<Int> {
        Set(segments.filter { ($0.fpBoth || $0.noFp == useNoFp) && !$0.noDamage }.map(\.atkId))
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

/// 输出手段选择器的三档：战技 / 魔法 / 祷告（与 Windows 端 state.meansKind、安卓端的三档开关同一口径）。
/// 只是界面层的过滤：`SkillOutput.kind` 仍只分战技与法术，生效判定另按 `LoadoutOutputClass` 走。
public enum OutputMeansKind: String, Sendable, Hashable, CaseIterable, Identifiable {
    case skill
    case sorcery
    case incantation

    public var id: String { rawValue }
}

/// 战技的武器选择：按武器类别分组。组内固定带这个战技的武器排前、其余按 id。
public struct SkillWeaponGroup: Sendable, Hashable, Identifiable {
    public let wepTypeZh: String
    public let weapons: [SkillWeapon]
    /// 组内固定带这个战技的武器数（它们排在 `weapons` 最前面）。
    public let fixedCount: Int

    public var id: String { wepTypeZh }

    public init(wepTypeZh: String, weapons: [SkillWeapon], fixedCount: Int = 0) {
        self.wepTypeZh = wepTypeZh
        self.weapons = weapons
        self.fixedCount = fixedCount
    }
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
    /// 列表里只在局内战技池里抽得到、没有任何武器固定带的战技数（v3 战技来源，页面底部说明用）。
    public let poolOnlyOutputs: Int
    /// hits[] 里标了 notInvoked 的段数（v3 TAE 核实：在所有武器上都打不出，本页不取）。
    public var notInvokedHits: Int {
        dataset.skills.reduce(0) { $0 + $1.hits.filter(\.notInvoked).count }
    }
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
        var poolOnly = 0
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
            let byID = weaponsByID
            if !skill.weaponIds.contains(where: { id in
                byID[id].map { Self.sourceKind(skill: skill, weapon: $0) == .fixed } ?? false
            }) {
                poolOnly += 1
            }
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
                    subtitleZh: "\(kindZh) · 专注值 \(spell.mp)",
                    weaponCount: 0,
                    segmentCount: spell.hits.count,
                    searchKey: "\(spell.nameZh) \(spell.nameEn) \(kindZh)".foldedForSearch
                )
            )
        }

        guard !outputs.isEmpty else { throw SkillDataError.empty }
        self.outputs = outputs
        skillsWithoutWeapons = withoutWeapons
        poolOnlyOutputs = poolOnly
        skillsWithoutHits = skillsNoHits
        spellsWithoutHits = spellsNoHits
        skillsWithoutDamage = skillsNoDamage
        spellsWithoutDamage = spellsNoDamage
    }

    /// 至少有一把能带它的武器（固定或局内战技池）能打出非 0 相对值（与 Windows 端 skillHasDamage 同一口径）。
    static func skillHasDamage(_ skill: SkillEntry, weaponsByID: [Int: SkillWeapon]) -> Bool {
        for id in skill.weaponIds {
            guard let weapon = weaponsByID[id] else { continue }
            if selectHits(skill, weapon: weapon).contains(where: { SkillDamageMath.segment(for: $0, weapon: weapon).hasDamage }) {
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

    /// 选择器当前档的搜索结果：只列这一档（战技 / 魔法 / 祷告），档内再按关键字过滤。
    public func outputs(matching query: String, kind: OutputMeansKind) -> [SkillOutput] {
        outputs(matching: query).filter { meansKind(of: $0) == kind }
    }

    /// 这条输出手段落在选择器的哪一档：战技；法术按 spells[].kind 分——sorcery＝魔法，
    /// 其余（incantation／pyromancy）＝祷告，与生效判定的 outputClass（isSorcery ? 魔法 : 祷告）同一口径。
    public func meansKind(of output: SkillOutput) -> OutputMeansKind {
        switch output.kind {
        case .skill:
            return .skill
        case .spell:
            return spellsByID[output.entryID]?.isSorcery == true ? .sorcery : .incantation
        }
    }

    // MARK: 武器

    /// 这把武器带这个战技的来源（v3 weaponSources）：固定 / 局内可抽到；两者都成立时只算固定。
    /// 武器不在这个战技的 weaponIds 里时为 nil。
    public func weaponSourceKind(skill: SkillEntry, weapon: SkillWeapon) -> SkillWeaponSourceKind? {
        guard skill.weaponIds.contains(weapon.id) else { return nil }
        return Self.sourceKind(skill: skill, weapon: weapon)
    }

    /// weaponSources 有这把武器就按它的 fixed；没有（数据缺这一项）时退回 swordArtsParamId 判定。
    static func sourceKind(skill: SkillEntry, weapon: SkillWeapon) -> SkillWeaponSourceKind {
        if let source = skill.weaponSource(for: weapon.id) { return source.kind }
        return weapon.swordArtsParamId == skill.id ? .fixed : .pool
    }

    /// 某个战技可用的武器（固定引用 ∪ 局内战技池），按武器类别分组：
    /// 类别内固定带这个战技的武器排前、其余按武器 id 升序；
    /// 类别之间先排含固定武器的，再按武器数量降序、类别名升序。默认武器因此总是固定武器（有的话）。
    public func weaponGroups(for skill: SkillEntry) -> [SkillWeaponGroup] {
        var grouped: [String: [SkillWeapon]] = [:]
        var fixed: Set<Int> = []
        for id in skill.weaponIds {
            guard let weapon = weaponsByID[id] else { continue }
            let key = weapon.wepTypeZh.isEmpty ? weapon.wepTypeEn : weapon.wepTypeZh
            grouped[key, default: []].append(weapon)
            if Self.sourceKind(skill: skill, weapon: weapon) == .fixed { fixed.insert(weapon.id) }
        }
        return grouped
            .map { key, weapons in
                let sorted = weapons.sorted { lhs, rhs in
                    let lhsFixed = fixed.contains(lhs.id)
                    let rhsFixed = fixed.contains(rhs.id)
                    return lhsFixed == rhsFixed ? lhs.id < rhs.id : lhsFixed
                }
                return SkillWeaponGroup(
                    wepTypeZh: key, weapons: sorted, fixedCount: sorted.filter { fixed.contains($0.id) }.count
                )
            }
            .sorted { lhs, rhs in
                if (lhs.fixedCount > 0) != (rhs.fixedCount > 0) { return lhs.fixedCount > 0 }
                return lhs.weapons.count == rhs.weapons.count
                    ? lhs.wepTypeZh < rhs.wepTypeZh
                    : lhs.weapons.count > rhs.weapons.count
            }
    }

    public func defaultWeapon(for skill: SkillEntry) -> SkillWeapon? {
        weaponGroups(for: skill).first?.weapons.first
    }

    // MARK: 选段

    /// 这把武器打出的段（usage.选段（必读））：
    /// `variants[weapon.skillVariants[战技 ID]].atkIds`（缺失时只有固定战技才回退 skillVariant，
    /// 见 `SkillWeapon.variantIndex(forSkill:)`）；variants 缺失时才退回 ctx 单选逻辑。
    ///
    /// **variants 存在时一律以下标为准**：数据集写明「skillVariants 覆盖 skillIds 里每个有命中段的战技」，
    /// 所以缺失 / 越界就是「打不出段」，不按 weaponIds 回查、也不退回 ctx 逻辑——那样会把数据问题盖掉。
    /// variants[].atkIds 已剔除 TAE 判定打不出的段（hits[] 里标 notInvoked），这条路径天然取不到它们。
    /// 与 Windows 端 selectHits 同一口径。
    public func hits(for skill: SkillEntry, weapon: SkillWeapon?) -> [SkillHit] {
        Self.selectHits(skill, weapon: weapon)
    }

    static func selectHits(_ skill: SkillEntry, weapon: SkillWeapon?) -> [SkillHit] {
        if !skill.variants.isEmpty {
            guard let weapon, let index = weapon.variantIndex(forSkill: skill.id),
                  skill.variants.indices.contains(index) else { return [] }
            let ids = Set(skill.variants[index].atkIds)
            return skill.hits.filter { ids.contains($0.atkId) }
        }
        return fallbackHits(for: skill, weapon: weapon)
    }

    /// variants 缺失时的退回逻辑：先 ctx == 武器 nameEn，再 ctx == wepTypeEn，
    /// 最后 ctx 缺失的那组 —— **单选，不取并集**；一个都对不上就是打不出段。
    /// 按 ctx 取并集会把通用战技（战吼 290 段、野蛮咆哮 358 段）重复统计几十遍。
    ///
    /// 这是唯一一条直接从 hits[] 取段的路径，所以先剔掉 notInvoked（TAE 判定永远打不出，
    /// 如狩猎大蛇的两段光之束）与 noDamage（只挂状态 / 只打自己队友的自疗子弹）——
    /// variants 那条路径由数据集保证不含 notInvoked，这里要自己把关。
    static func fallbackHits(for skill: SkillEntry, weapon: SkillWeapon?) -> [SkillHit] {
        let playable = skill.hits.filter { !$0.notInvoked && !$0.noDamage }
        if let weapon, !weapon.nameEn.isEmpty {
            let byName = playable.filter { $0.ctx == weapon.nameEn }
            if !byName.isEmpty { return byName }
        }
        if let weapon, !weapon.wepTypeEn.isEmpty {
            let byType = playable.filter { $0.ctx == weapon.wepTypeEn }
            if !byType.isEmpty { return byType }
        }
        return playable.filter { $0.ctx == nil }
    }

    public func segments(for skill: SkillEntry, weapon: SkillWeapon?) -> [SkillSegment] {
        hits(for: skill, weapon: weapon).map { SkillDamageMath.segment(for: $0, weapon: weapon) }
    }

    /// 法术：没有 variants，全部段都会打出；只用 flat 做配比（见 usage.法术 / 子弹段）。
    public func segments(for spell: SpellEntry) -> [SkillSegment] {
        // 法术目前没有 TAE 核实（fieldNotes 说明），但与 Windows / Android 同口径：notInvoked 段不进计算。
        spell.hits.filter { !$0.notInvoked }.map { SkillDamageMath.segment(for: $0, weapon: nil) }
    }

    /// 能带这个法术的施法器（spells[].casterWeaponIds 按 weapons[] 取到的那些，同序）。
    /// 伤害构成不用它们——法术段只用 flat（usage.法术 / 子弹段）；这里只供展示与自检。
    public func casters(for spell: SpellEntry) -> [SkillWeapon] {
        spell.casterWeaponIds.compactMap { weaponsByID[$0] }
    }

    public var summary: String {
        let weapons = dataset.weapons.count
        let skills = dataset.skills.count
        let spells = dataset.spells.count
        return "\(weapons) 把武器 · \(skills) 个战技 · \(spells) 个法术"
    }
}
