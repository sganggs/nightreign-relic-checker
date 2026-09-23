import Foundation

// 「首领数据」页的数据模型与换算函数。
//
// 数据来源：Resources/bosses.json（bossesSchemaVersion = 4），经
// `GameDataLoader.dataIfAvailable(for: .bosses)` 读取原始 Data 后在这里解码。
//
// v4 相对 v3 只增字段：每条数值行 / 每组首领多了 roles（出场场合，可多重归属）、
// roleEvidence（逐表逐行的出处）、rowRoles（合并行各自的场合），顶层多了
// roleNames / roleSummary / roleSummaryDetail。页面分组从此按 roles 走——
// v3 的 tier / tiers 只是多人缩放档位名（Field / Night Boss Threat），
// 不代表出场位置（铃珠猎人野外版挂的就是 Night Boss Threat），所以只留在
// 展开区当「威胁档位」小字。分组规则见 `BossCard.Group`。
//
// v3 相对 v2 是纯增量，这里跟进的四件事：
//   * 名字：nameZh / nameZhFallback / nameApprox / nameNote / hidden / noReward，
//     让「只有英文名」「翻译不对」「未知敌人」三类问题在页面上说得清；
//   * 深夜：depthStats[1…5] 才是「深夜 + 深度 N」的真数值，v2 的 deepOfNight
//     只算到「深夜修正」，缺了最后一层深度倍率；
//   * 变异个体（社区俗称「红化」）：mutations / mutationPool / mutationCategories，
//     倍率在其它缩放之上再乘一层；
//   * 多人：scaling.*.attackRate —— 多人不只是血条变长，部分档位敌人攻击力也上浮。
//
// 解码原则（数据集由另一条流水线维护，字段随时可能增删）：
//   * 未知字段一律忽略（Swift 合成解码的默认行为）；
//   * 已知字段缺失、类型不符时退回默认值，**不抛错**；
//   * 数组逐元素解码，坏元素跳过而不是整份失败。
// 只有「顶层不是 JSON 对象」「一条首领记录都没有」这种读不懂的情况才抛
// `BossDataError`。

// MARK: - 错误

public enum BossDataError: LocalizedError {
    case notAnObject
    /// 其他解码失败（JSON 截断 / 编码损坏 / 字段结构彻底对不上），带上原始错误说明。
    /// 数据文件由另一条流水线生成，这里必须把排障信息透出去。
    case undecodable(String)
    case empty

    public var errorDescription: String? {
        switch self {
        case .notAnObject: return "首领数据不是合法的 JSON 对象"
        case .undecodable(let detail): return "首领数据无法解码：" + detail
        case .empty: return "首领数据里没有任何首领记录"
        }
    }
}

// MARK: - 宽容解码辅助

/// 逐元素解码用的包装：单个元素解不出来时置 nil，由调用方过滤掉。
struct BossFailable<T: Decodable>: Decodable {
    let value: T?

    init(from decoder: Decoder) throws {
        value = try? T(from: decoder)
    }
}

extension KeyedDecodingContainer {
    /// 任意 `Decodable`：解不出来（缺键 / 类型不符）时用默认值。
    func bossValue<T: Decodable>(_ key: Key, default fallback: T) -> T {
        if let value = try? decodeIfPresent(T.self, forKey: key) { return value }
        return fallback
    }

    func bossDouble(_ key: Key, default fallback: Double) -> Double {
        if let value = try? decodeIfPresent(Double.self, forKey: key) { return value }
        if let value = try? decodeIfPresent(Int.self, forKey: key) { return Double(value) }
        if let text = try? decodeIfPresent(String.self, forKey: key), let value = Double(text) { return value }
        return fallback
    }

    func bossInt(_ key: Key, default fallback: Int) -> Int {
        if let value = try? decodeIfPresent(Int.self, forKey: key) { return value }
        if let value = try? decodeIfPresent(Double.self, forKey: key), value.isFinite {
            return Int(value.rounded())
        }
        if let text = try? decodeIfPresent(String.self, forKey: key), let value = Int(text) { return value }
        return fallback
    }

    func bossOptionalInt(_ key: Key) -> Int? {
        if let value = try? decodeIfPresent(Int.self, forKey: key) { return value }
        if let value = try? decodeIfPresent(Double.self, forKey: key), value.isFinite {
            return Int(value.rounded())
        }
        return nil
    }

    func bossString(_ key: Key, default fallback: String = "") -> String {
        if let value = try? decodeIfPresent(String.self, forKey: key) { return value }
        if let value = try? decodeIfPresent(Int.self, forKey: key) { return String(value) }
        return fallback
    }

    func bossOptionalString(_ key: Key) -> String? {
        guard let value = try? decodeIfPresent(String.self, forKey: key), !value.isEmpty else { return nil }
        return value
    }

    func bossBool(_ key: Key, default fallback: Bool = false) -> Bool {
        if let value = try? decodeIfPresent(Bool.self, forKey: key) { return value }
        if let value = try? decodeIfPresent(Int.self, forKey: key) { return value != 0 }
        return fallback
    }

    /// 逐元素宽容解码；键缺失或不是数组时返回空数组。
    func bossArray<T: Decodable>(_ key: Key) -> [T] {
        guard let wrapped = try? decodeIfPresent([BossFailable<T>].self, forKey: key) else { return [] }
        return wrapped.compactMap(\.value)
    }

    /// 逐值宽容解码的字典；键缺失或不是对象时返回空字典。
    func bossDictionary<T: Decodable>(_ key: Key) -> [String: T] {
        guard let wrapped = try? decodeIfPresent([String: BossFailable<T>].self, forKey: key) else { return [:] }
        return wrapped.compactMapValues(\.value)
    }

    func bossIntArray(_ key: Key) -> [Int] {
        let numbers: [Double] = bossArray(key)
        return numbers.map { Int($0.rounded()) }
    }

    /// 键是数字字符串（"1"…"5"、"0"…"2"）的字典，解码后把键转成 Int；转不了的键丢掉。
    func bossNumberKeyedDictionary<T: Decodable>(_ key: Key) -> [Int: T] {
        let raw: [String: T] = bossDictionary(key)
        return raw.reduce(into: [:]) { result, entry in
            guard let numeric = Int(entry.key) else { return }
            result[numeric] = entry.value
        }
    }

    /// 键是数字字符串、值是整数的字典（depthChanceWeights / mutatedCount / cataclysmWeight）。
    func bossNumberKeyedIntDictionary(_ key: Key) -> [Int: Int] {
        let raw: [Int: Double] = bossNumberKeyedDictionary(key)
        return raw.mapValues { Int($0.rounded()) }
    }
}

// MARK: - 基础结构

public struct BossLocalizedName: Codable, Sendable, Hashable {
    public let zh: String
    public let en: String

    public init(zh: String, en: String) {
        self.zh = zh
        self.en = en
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        zh = container.bossString(.zh)
        en = container.bossString(.en)
    }

    /// 简中优先，空则回退英文。
    public var display: String { zh.isEmpty ? en : zh }
}

public struct BossSource: Codable, Sendable, Hashable {
    public let name: String
    public let url: String
    public let revision: String
    public let license: String
    public let usage: String

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = container.bossString(.name)
        url = container.bossString(.url)
        revision = container.bossString(.revision)
        license = container.bossString(.license)
        usage = container.bossString(.usage)
    }
}

/// 菜单参数里标注的官方弱点（与 damageRates 的实测倍率并不总是一致）。
public struct BossWeakness: Codable, Sendable, Hashable, Identifiable {
    public let code: Int
    public let zh: String
    public let en: String

    public var id: Int { code }
    public var display: String { zh.isEmpty ? en : zh }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        code = container.bossInt(.code, default: -1)
        zh = container.bossString(.zh)
        en = container.bossString(.en)
    }
}

// MARK: - 属性 / 异常枚举

public enum BossDamageKind: String, CaseIterable, Identifiable, Sendable {
    case standard, slash, strike, pierce, magic, fire, lightning, holy

    public var id: String { rawValue }

    public var titleZh: String {
        switch self {
        case .standard: return "标准"
        case .slash: return "斩击"
        case .strike: return "打击"
        case .pierce: return "突刺"
        case .magic: return "魔力"
        case .fire: return "火"
        case .lightning: return "雷"
        case .holy: return "圣"
        }
    }

    public var isPhysical: Bool {
        switch self {
        case .standard, .slash, .strike, .pierce: return true
        default: return false
        }
    }

    /// 数据集 `affinityNames` 的 EFFECTIVE_AFFINITY 枚举码；物理四种没有对应码。
    public var affinityCode: Int? {
        switch self {
        case .magic: return 1
        case .fire: return 2
        case .lightning: return 3
        case .holy: return 4
        case .standard, .slash, .strike, .pierce: return nil
        }
    }
}

public enum BossAilmentKind: String, CaseIterable, Identifiable, Sendable {
    case poison, rot, bleed, frost, sleep, madness, death

    public var id: String { rawValue }

    public var titleZh: String {
        switch self {
        case .poison: return "中毒"
        case .rot: return "猩红腐败"
        case .bleed: return "出血"
        case .frost: return "冻伤"
        case .sleep: return "睡眠"
        case .madness: return "发狂"
        case .death: return "死亡"
        }
    }

    /// 数据集 `affinityNames` 的 EFFECTIVE_AFFINITY 枚举码。
    public var affinityCode: Int {
        switch self {
        case .poison: return 5
        case .rot: return 6
        case .bleed: return 7
        case .death: return 8
        case .frost: return 9
        case .sleep: return 10
        case .madness: return 11
        }
    }
}

public struct BossDamageRates: Codable, Sendable, Hashable {
    public let standard: Double
    public let slash: Double
    public let strike: Double
    public let pierce: Double
    public let magic: Double
    public let fire: Double
    public let lightning: Double
    public let holy: Double

    public static let neutral = BossDamageRates()

    public init(
        standard: Double = 1, slash: Double = 1, strike: Double = 1, pierce: Double = 1,
        magic: Double = 1, fire: Double = 1, lightning: Double = 1, holy: Double = 1
    ) {
        self.standard = standard
        self.slash = slash
        self.strike = strike
        self.pierce = pierce
        self.magic = magic
        self.fire = fire
        self.lightning = lightning
        self.holy = holy
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        standard = container.bossDouble(.standard, default: 1)
        slash = container.bossDouble(.slash, default: 1)
        strike = container.bossDouble(.strike, default: 1)
        pierce = container.bossDouble(.pierce, default: 1)
        magic = container.bossDouble(.magic, default: 1)
        fire = container.bossDouble(.fire, default: 1)
        lightning = container.bossDouble(.lightning, default: 1)
        holy = container.bossDouble(.holy, default: 1)
    }

    public func value(for kind: BossDamageKind) -> Double {
        switch kind {
        case .standard: return standard
        case .slash: return slash
        case .strike: return strike
        case .pierce: return pierce
        case .magic: return magic
        case .fire: return fire
        case .lightning: return lightning
        case .holy: return holy
        }
    }

    /// 倍率 > 1 的属性（按倍率降序），即数值意义上的「弱点」。
    /// 同倍率按 `allCases` 的声明顺序（= Windows 端 DAMAGE_TYPES 的顺序）兜底，
    /// 保证两端列出来的「承伤偏高」属性顺序完全一致（Swift 的 sort 不保证稳定）。
    public var weakKinds: [BossDamageKind] {
        orderedKinds { $0 > 1 } by: { $0 > $1 }
    }

    /// 倍率 < 1 的属性（按倍率升序），即抗性。
    public var resistantKinds: [BossDamageKind] {
        orderedKinds { $0 < 1 } by: { $0 < $1 }
    }

    private func orderedKinds(
        _ include: (Double) -> Bool,
        by isBefore: (Double, Double) -> Bool
    ) -> [BossDamageKind] {
        BossDamageKind.allCases.enumerated()
            .filter { include(value(for: $0.element)) }
            .sorted { lhs, rhs in
                let left = value(for: lhs.element)
                let right = value(for: rhs.element)
                return left == right ? lhs.offset < rhs.offset : isBefore(left, right)
            }
            .map(\.element)
    }
}

public struct BossResistances: Codable, Sendable, Hashable {
    /// 数据集里 999 表示免疫。
    public static let immuneThreshold = 999

    public let poison: Int
    public let rot: Int
    public let bleed: Int
    public let frost: Int
    public let sleep: Int
    public let madness: Int
    public let death: Int

    public init(
        poison: Int = 0, rot: Int = 0, bleed: Int = 0, frost: Int = 0,
        sleep: Int = 0, madness: Int = 0, death: Int = 0
    ) {
        self.poison = poison
        self.rot = rot
        self.bleed = bleed
        self.frost = frost
        self.sleep = sleep
        self.madness = madness
        self.death = death
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        poison = container.bossInt(.poison, default: 0)
        rot = container.bossInt(.rot, default: 0)
        bleed = container.bossInt(.bleed, default: 0)
        frost = container.bossInt(.frost, default: 0)
        sleep = container.bossInt(.sleep, default: 0)
        madness = container.bossInt(.madness, default: 0)
        death = container.bossInt(.death, default: 0)
    }

    public func value(for kind: BossAilmentKind) -> Int {
        switch kind {
        case .poison: return poison
        case .rot: return rot
        case .bleed: return bleed
        case .frost: return frost
        case .sleep: return sleep
        case .madness: return madness
        case .death: return death
        }
    }

    public func isImmune(to kind: BossAilmentKind) -> Bool {
        value(for: kind) >= Self.immuneThreshold
    }

    public var immuneKinds: [BossAilmentKind] {
        BossAilmentKind.allCases.filter(isImmune(to:))
    }
}

// MARK: - 人数缩放

public enum BossPartySize: Int, CaseIterable, Identifiable, Sendable {
    case solo = 1
    case duo = 2
    case trio = 3

    public var id: Int { rawValue }

    public var title: String { "\(rawValue) 人" }

    public var shortTitle: String {
        switch self {
        case .solo: return "单人"
        case .duo: return "双人"
        case .trio: return "三人"
        }
    }
}

/// 敌人攻击力倍率的五个属性分支（physicsAttackPowerRate 等）。
/// 常驻档位里确实存在「只加物理」的行（如 16178「×2.42 血 ×1.1 物理」），
/// 所以攻击力不能只留一个标量。
public struct BossAttackRates: Codable, Sendable, Hashable {
    public let physical: Double
    public let magic: Double
    public let fire: Double
    public let lightning: Double
    public let holy: Double

    public static let neutral = BossAttackRates()

    public init(
        physical: Double = 1, magic: Double = 1, fire: Double = 1,
        lightning: Double = 1, holy: Double = 1
    ) {
        self.physical = physical
        self.magic = magic
        self.fire = fire
        self.lightning = lightning
        self.holy = holy
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        physical = container.bossDouble(.physical, default: 1)
        magic = container.bossDouble(.magic, default: 1)
        fire = container.bossDouble(.fire, default: 1)
        lightning = container.bossDouble(.lightning, default: 1)
        holy = container.bossDouble(.holy, default: 1)
    }

    /// 五个分支是否同值（数据里绝大多数如此，页面就只显示一个数）。
    public var isUniform: Bool {
        physical == magic && magic == fire && fire == lightning && lightning == holy
    }

    public func scaled(by factor: Double) -> BossAttackRates {
        BossAttackRates(
            physical: physical * factor, magic: magic * factor, fire: fire * factor,
            lightning: lightning * factor, holy: holy * factor
        )
    }
}

/// MultiPlayCorrectionParam 的一档（双人或三人）。
public struct BossScalingTier: Codable, Sendable, Hashable {
    /// 血量倍率（maxHpRate）。
    public let hp: Double
    /// 承受削韧倍率（saReceiveDamageRate）；0.55 = 同样的削韧只吃 55%。
    public let poiseTaken: Double
    /// 削韧恢复速度倍率（changeSaRecoveryVelocity）。
    public let poiseRecover: Double
    /// 异常发动时的伤害倍率（bloodDamageRate/100）。
    public let ailmentDamageRate: Double
    /// 中毒 / 腐败的发动伤害倍率（poisonDamageRate/100），当前恒为 1。
    public let poisonRate: Double
    /// Boss 承受的异常累积量倍率（poisonDefDamageRate）；越小越难打出异常。
    public let buildupRate: Double
    /// **敌人攻击力**倍率（五种 *AttackPowerRate）。7744 / 7753 / 7754 / 7758 四档
    /// 双人 1.1、三人 1.2 —— 多人不是只有血条变长，这几档 Boss 打得也更疼。
    public let attackRate: Double
    /// 对玩家耐力的削减倍率（staminaAttackRate）；人数缩放行里恒为 1。
    public let staminaAttackRate: Double

    /// 单人（不做任何人数缩放）。
    public static let identity = BossScalingTier(
        hp: 1, poiseTaken: 1, poiseRecover: 1, ailmentDamageRate: 1, poisonRate: 1, buildupRate: 1
    )

    public init(
        hp: Double, poiseTaken: Double, poiseRecover: Double,
        ailmentDamageRate: Double, poisonRate: Double, buildupRate: Double,
        attackRate: Double = 1, staminaAttackRate: Double = 1
    ) {
        self.hp = hp
        self.poiseTaken = poiseTaken
        self.poiseRecover = poiseRecover
        self.ailmentDamageRate = ailmentDamageRate
        self.poisonRate = poisonRate
        self.buildupRate = buildupRate
        self.attackRate = attackRate
        self.staminaAttackRate = staminaAttackRate
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        hp = container.bossDouble(.hp, default: 1)
        poiseTaken = container.bossDouble(.poiseTaken, default: 1)
        poiseRecover = container.bossDouble(.poiseRecover, default: 1)
        ailmentDamageRate = container.bossDouble(.ailmentDamageRate, default: 1)
        poisonRate = container.bossDouble(.poisonRate, default: 1)
        buildupRate = container.bossDouble(.buildupRate, default: 1)
        attackRate = container.bossDouble(.attackRate, default: 1)
        staminaAttackRate = container.bossDouble(.staminaAttackRate, default: 1)
    }

    /// 该档位是否让敌人攻击力上浮（> 1）。页面据此在血量旁挂「多人攻击 ×1.1」。
    public var raisesAttack: Bool { attackRate > 1.0001 }
}

/// 单条记录里展开的 duo / trio 两档。
public struct BossScalingPair: Codable, Sendable, Hashable {
    public let duo: BossScalingTier?
    public let trio: BossScalingTier?

    public init(duo: BossScalingTier?, trio: BossScalingTier?) {
        self.duo = duo
        self.trio = trio
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        duo = try? container.decodeIfPresent(BossScalingTier.self, forKey: .duo)
        trio = try? container.decodeIfPresent(BossScalingTier.self, forKey: .trio)
    }

    /// 缺档时按单人（不缩放）处理。
    public func tier(for players: BossPartySize) -> BossScalingTier {
        switch players {
        case .solo: return .identity
        case .duo: return duo ?? .identity
        case .trio: return trio ?? .identity
        }
    }
}

/// 顶层 `scalingTiers` 的一项（带 Paramdex 分组名）。
public struct BossScalingGroup: Codable, Sendable, Hashable, Identifiable {
    /// 档位分组的中文标签。与 Windows 端 `pages/bosses.js` 的 GROUP_LABELS 一一对应，
    /// 两端必须给同一个 group 值同一个中文名（数据里还存在 group = null 的档位）。
    public static func title(for group: String?) -> String {
        switch group {
        case "Field Boss Threat": return "野外首领威胁档"
        case "Night Boss Threat": return "守夜首领威胁档"
        case "Final Boss Threat": return "最终首领威胁档"
        case .some(let name) where !name.isEmpty: return name
        default: return "其它档位"
        }
    }

    public let id: Int
    public let group: String?
    public let duo: BossScalingTier?
    public let trio: BossScalingTier?

    /// 分组中文名；group 缺失时是「其它档位」。
    public var title: String { Self.title(for: group) }

    private enum CodingKeys: String, CodingKey {
        case group, duo, trio
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = 0
        group = container.bossOptionalString(.group)
        duo = try? container.decodeIfPresent(BossScalingTier.self, forKey: .duo)
        trio = try? container.decodeIfPresent(BossScalingTier.self, forKey: .trio)
    }

    public init(id: Int, group: String?, duo: BossScalingTier?, trio: BossScalingTier?) {
        self.id = id
        self.group = group
        self.duo = duo
        self.trio = trio
    }

    /// `scalingTiers` 的 key 才是档位 ID，解码后补上。
    public func withID(_ id: Int) -> BossScalingGroup {
        BossScalingGroup(id: id, group: group, duo: duo, trio: trio)
    }

    public var pair: BossScalingPair { BossScalingPair(duo: duo, trio: trio) }
}

/// 顶层 `permanentScaling` 的一项：常驻挂在 NpcParam 上的缩放 SpEffect。
public struct BossPermanentEffect: Codable, Sendable, Hashable, Identifiable {
    public let id: Int
    public let nameEn: String?
    public let nameZh: String
    public let hp: Double
    public let poiseTaken: Double
    public let poiseRecover: Double
    public let ailmentDamageRate: Double
    /// 敌人攻击力倍率（五属性同值时的代表值）。
    public let attackRate: Double
    public let attackRates: BossAttackRates
    public let staminaAttackRate: Double
    /// true 表示只在「深夜」模式生效。
    public let deepOfNight: Bool

    private enum CodingKeys: String, CodingKey {
        case nameEn, nameZh, hp, poiseTaken, poiseRecover, ailmentDamageRate
        case attackRate, attackRates, staminaAttackRate, deepOfNight
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = 0
        nameEn = container.bossOptionalString(.nameEn)
        nameZh = container.bossString(.nameZh)
        hp = container.bossDouble(.hp, default: 1)
        poiseTaken = container.bossDouble(.poiseTaken, default: 1)
        poiseRecover = container.bossDouble(.poiseRecover, default: 1)
        ailmentDamageRate = container.bossDouble(.ailmentDamageRate, default: 1)
        attackRate = container.bossDouble(.attackRate, default: 1)
        attackRates = container.bossValue(.attackRates, default: BossAttackRates.neutral)
        staminaAttackRate = container.bossDouble(.staminaAttackRate, default: 1)
        deepOfNight = container.bossBool(.deepOfNight)
    }

    public init(
        id: Int, nameEn: String?, nameZh: String, hp: Double, poiseTaken: Double,
        poiseRecover: Double, ailmentDamageRate: Double, attackRate: Double = 1,
        attackRates: BossAttackRates = .neutral, staminaAttackRate: Double = 1,
        deepOfNight: Bool
    ) {
        self.id = id
        self.nameEn = nameEn
        self.nameZh = nameZh
        self.hp = hp
        self.poiseTaken = poiseTaken
        self.poiseRecover = poiseRecover
        self.ailmentDamageRate = ailmentDamageRate
        self.attackRate = attackRate
        self.attackRates = attackRates
        self.staminaAttackRate = staminaAttackRate
        self.deepOfNight = deepOfNight
    }

    /// `permanentScaling` 的 key 才是 SpEffect ID，解码后补上。
    public func withID(_ id: Int) -> BossPermanentEffect {
        BossPermanentEffect(
            id: id, nameEn: nameEn, nameZh: nameZh, hp: hp, poiseTaken: poiseTaken,
            poiseRecover: poiseRecover, ailmentDamageRate: ailmentDamageRate,
            attackRate: attackRate, attackRates: attackRates,
            staminaAttackRate: staminaAttackRate, deepOfNight: deepOfNight
        )
    }

    public var displayName: String {
        if !nameZh.isEmpty { return nameZh }
        if let nameEn, !nameEn.isEmpty { return nameEn }
        return "常驻缩放 #\(id)"
    }
}

// MARK: - 战斗行（夜王 fight / 守夜·野外 variant 共用同一套数值字段）

/// 「深夜」模式下的同一组基准数值（**不含**深度倍率，深度在 depthStats 里）。
public struct BossDeepOfNightStats: Codable, Sendable, Hashable {
    public let hp: Int
    public let hpMultiplier: Double
    public let poiseTakenBase: Double
    public let poiseRecoverMultiplier: Double
    public let ailmentDamageRateBase: Double
    public let attackRateBase: Double
    public let attackRatesBase: BossAttackRates
    public let staminaAttackRateBase: Double
    public let permScalingIds: [Int]

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        hp = container.bossInt(.hp, default: 0)
        hpMultiplier = container.bossDouble(.hpMultiplier, default: 1)
        poiseTakenBase = container.bossDouble(.poiseTakenBase, default: 1)
        poiseRecoverMultiplier = container.bossDouble(.poiseRecoverMultiplier, default: 1)
        ailmentDamageRateBase = container.bossDouble(.ailmentDamageRateBase, default: 1)
        attackRateBase = container.bossDouble(.attackRateBase, default: 1)
        attackRatesBase = container.bossValue(.attackRatesBase, default: BossAttackRates.neutral)
        staminaAttackRateBase = container.bossDouble(.staminaAttackRateBase, default: 1)
        permScalingIds = container.bossIntArray(.permScalingIds)
    }
}

/// 「深夜 · 深度 N」下的一组基准数值。
///
/// 这才是深夜的真数值：`hp` 已经把常驻威胁档位、深夜修正、深度 N 倍率三层都乘进去了
/// （v2 的 `deepOfNight` 只算到第二层，正是用户说的「不同深度的属性没展示」）。
/// 页面再乘人数缩放即可；`poiseTakenBase` 同理已含深夜修正 × 深度倍率。
public struct BossDepthStats: Codable, Sendable, Hashable {
    public let hp: Int
    public let hpMultiplier: Double
    public let poiseTakenBase: Double
    public let attackRateBase: Double
    public let attackRatesBase: BossAttackRates
    public let staminaAttackRateBase: Double
    /// 该深度用到的 ChaosMatchingCorrectParam SpEffect 行号。
    public let depthSpEffectId: Int?

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        hp = container.bossInt(.hp, default: 0)
        hpMultiplier = container.bossDouble(.hpMultiplier, default: 1)
        poiseTakenBase = container.bossDouble(.poiseTakenBase, default: 1)
        attackRateBase = container.bossDouble(.attackRateBase, default: 1)
        attackRatesBase = container.bossValue(.attackRatesBase, default: BossAttackRates.neutral)
        staminaAttackRateBase = container.bossDouble(.staminaAttackRateBase, default: 1)
        depthSpEffectId = container.bossOptionalInt(.depthSpEffectId)
    }
}

/// 变异个体（游戏内简中正式叫法；社区俗称「红化」）的一档倍率。
///
/// 链路：NpcParam.chaosMatchingSpEffectSetParamId → SpEffectSetParam
/// 「Set: Deep Night Mutation - VFX + Scaling」→ 红光 VFX 档位 + 数值档位。
/// 数值档位的 spCategory = 203，与深度（0）、常驻（0）、人数（140）都不同，
/// 因此**在其它缩放之上再乘一层**（按参数结构推断，不是实测）。
public struct BossMutation: Codable, Sendable, Hashable, Identifiable {
    /// SpEffectSetParam 行号（mutationPool 里存的就是它）。
    public let id: Int
    public let nameZh: String
    public let nameEn: String
    public let setNameEn: String?
    public let vfxSpEffectIds: [Int]
    /// 红光特效档位 1…4，越高越显眼。
    public let vfxTier: Int?
    /// 数值档位的 SpEffect 行号（7220 / 7230 / 7240 / 7241 …）。
    public let statSpEffectId: Int?
    public let statNameEn: String?
    public let hp: Double
    public let attackRate: Double
    public let runeRate: Double

    private enum CodingKeys: String, CodingKey {
        case nameZh, nameEn, setNameEn, vfxSpEffectIds, vfxTier, statSpEffectId, statNameEn
        case hp, attackRate, runeRate
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = 0
        nameZh = container.bossString(.nameZh, default: "变异个体")
        nameEn = container.bossString(.nameEn, default: "Variant")
        setNameEn = container.bossOptionalString(.setNameEn)
        vfxSpEffectIds = container.bossIntArray(.vfxSpEffectIds)
        vfxTier = container.bossOptionalInt(.vfxTier)
        statSpEffectId = container.bossOptionalInt(.statSpEffectId)
        statNameEn = container.bossOptionalString(.statNameEn)
        hp = container.bossDouble(.hp, default: 1)
        attackRate = container.bossDouble(.attackRate, default: 1)
        runeRate = container.bossDouble(.runeRate, default: 1)
    }

    public init(
        id: Int, nameZh: String, nameEn: String, setNameEn: String?, vfxSpEffectIds: [Int],
        vfxTier: Int?, statSpEffectId: Int?, statNameEn: String?,
        hp: Double, attackRate: Double, runeRate: Double
    ) {
        self.id = id
        self.nameZh = nameZh
        self.nameEn = nameEn
        self.setNameEn = setNameEn
        self.vfxSpEffectIds = vfxSpEffectIds
        self.vfxTier = vfxTier
        self.statSpEffectId = statSpEffectId
        self.statNameEn = statNameEn
        self.hp = hp
        self.attackRate = attackRate
        self.runeRate = runeRate
    }

    /// `mutations` 的 key 才是档位 ID，解码后补上。
    public func withID(_ id: Int) -> BossMutation {
        BossMutation(
            id: id, nameZh: nameZh, nameEn: nameEn, setNameEn: setNameEn,
            vfxSpEffectIds: vfxSpEffectIds, vfxTier: vfxTier, statSpEffectId: statSpEffectId,
            statNameEn: statNameEn, hp: hp, attackRate: attackRate, runeRate: runeRate
        )
    }

    /// 下拉框里的一行：「#113240 · 血量 ×1.8 · 攻击 ×1.5 · 卢恩 ×1.35」。
    public var summary: String {
        "血量 ×\(BossRowText.decimal(hp)) · 攻击 ×\(BossRowText.decimal(attackRate))"
            + " · 卢恩 ×\(BossRowText.decimal(runeRate))"
    }

    public var pickerTitle: String { "#\(id) · " + summary }
}

/// ChaosMatchingMutationCategoryParam 的一行：某地图某类敌人在各深度**有几只**被变异。
/// 这是只数，不是百分比概率——最容易被误读的一项。
public struct BossMutationCategory: Codable, Sendable, Hashable, Identifiable {
    public let rowId: Int
    public let categoryId: Int
    public let categoryZh: String
    public let categoryEn: String
    public let mapId: Int
    public let mapZh: String
    public let mapEn: String
    /// 深度 1…5 → 只数。
    public let mutatedCount: [Int: Int]

    public var id: Int { rowId }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        rowId = container.bossInt(.rowId, default: 0)
        categoryId = container.bossInt(.categoryId, default: 0)
        categoryZh = container.bossString(.categoryZh)
        categoryEn = container.bossString(.categoryEn)
        mapId = container.bossInt(.mapId, default: 0)
        mapZh = container.bossString(.mapZh)
        mapEn = container.bossString(.mapEn)
        mutatedCount = container.bossNumberKeyedIntDictionary(.mutatedCount)
    }

    public func count(atDepth depth: Int) -> Int { mutatedCount[depth] ?? 0 }

    public var categoryTitle: String { categoryZh.isEmpty ? categoryEn : categoryZh }
    public var mapTitle: String { mapZh.isEmpty ? mapEn : mapZh }
}

/// ChaosMatchingRankControlParam 的一行（深度 1…5 的全局控制，**不含**任何血量攻击倍率）。
public struct BossDepthInfo: Codable, Sendable, Hashable, Identifiable {
    public let rankId: Int
    public let paramdexName: String?
    public let labelZh: String
    public let labelEn: String
    /// 诅咒遗物（罕见 / 稀有）出现率，当前全深度不变。
    public let cursedUncommonRate: Double
    public let cursedRareRate: Double
    /// 地图挑战权重：地图 / 夜王 / 无。
    public let mapChallengeWeight: BossMapChallengeWeight
    /// 天变数量权重（"0" / "1" / "2"）。
    public let cataclysmWeight: [Int: Int]

    public var id: Int { rankId }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        rankId = container.bossInt(.rankId, default: 0)
        paramdexName = container.bossOptionalString(.paramdexName)
        labelZh = container.bossString(.labelZh)
        labelEn = container.bossString(.labelEn)
        cursedUncommonRate = container.bossDouble(.cursedUncommonRate, default: 0)
        cursedRareRate = container.bossDouble(.cursedRareRate, default: 0)
        mapChallengeWeight = container.bossValue(
            .mapChallengeWeight, default: BossMapChallengeWeight()
        )
        cataclysmWeight = container.bossNumberKeyedIntDictionary(.cataclysmWeight)
    }

    public var title: String { labelZh.isEmpty ? labelEn : labelZh }
}

public struct BossMapChallengeWeight: Codable, Sendable, Hashable {
    public let map: Double
    public let nightlord: Double
    public let none: Double

    public init(map: Double = 0, nightlord: Double = 0, none: Double = 0) {
        self.map = map
        self.nightlord = nightlord
        self.none = none
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        map = container.bossDouble(.map, default: 0)
        nightlord = container.bossDouble(.nightlord, default: 0)
        none = container.bossDouble(.none, default: 0)
    }
}

/// `deepOfNightTiers` 的一档：某个 ChaosMatchingCorrectParam 行号在 5 个深度上的倍率。
public struct BossDepthTier: Codable, Sendable, Hashable, Identifiable {
    public let id: Int
    public let group: String?
    /// Paramdex 的档位名，如 "Tier 3f"。
    public let tier: String?
    public let depths: [Int: BossDepthTierStats]

    private enum CodingKeys: String, CodingKey {
        case group, tier, depths
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = 0
        group = container.bossOptionalString(.group)
        tier = container.bossOptionalString(.tier)
        depths = container.bossNumberKeyedDictionary(.depths)
    }

    public init(id: Int, group: String?, tier: String?, depths: [Int: BossDepthTierStats]) {
        self.id = id
        self.group = group
        self.tier = tier
        self.depths = depths
    }

    public func withID(_ id: Int) -> BossDepthTier {
        BossDepthTier(id: id, group: group, tier: tier, depths: depths)
    }

    public var title: String { BossScalingGroup.title(for: group) }
}

public struct BossDepthTierStats: Codable, Sendable, Hashable {
    public let spEffectId: Int?
    public let nameEn: String?
    public let hp: Double
    public let attackRate: Double
    public let poiseTaken: Double
    public let staminaAttackRate: Double

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        spEffectId = container.bossOptionalInt(.spEffectId)
        nameEn = container.bossOptionalString(.nameEn)
        hp = container.bossDouble(.hp, default: 1)
        attackRate = container.bossDouble(.attackRate, default: 1)
        poiseTaken = container.bossDouble(.poiseTaken, default: 1)
        staminaAttackRate = container.bossDouble(.staminaAttackRate, default: 1)
    }
}

/// 一条游戏内文本（CL_MenuText）。
public struct BossGameText: Codable, Sendable, Hashable {
    public let zh: String
    public let en: String
    public let textId: Int?

    public static let empty = BossGameText(zh: "", en: "", textId: nil)

    public init(zh: String, en: String, textId: Int?) {
        self.zh = zh
        self.en = en
        self.textId = textId
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        zh = container.bossString(.zh)
        en = container.bossString(.en)
        textId = container.bossOptionalInt(.textId)
    }

    public var display: String { zh.isEmpty ? en : zh }
    public var isEmpty: Bool { zh.isEmpty && en.isEmpty }
}

/// 顶层 `deepOfNightText`：深夜 / 深度 / 变异个体的**游戏内简中原文**。
/// 页面上这几个词一律用它，不要自己造词（「红化」是社区叫法，游戏里叫「变异个体」）。
public struct BossDeepOfNightText: Codable, Sendable, Hashable {
    public let deepOfNight: BossGameText
    public let depth: BossGameText
    public let mutation: BossGameText
    public let mutationCount: BossGameText
    public let description: BossGameText

    public static let fallback = BossDeepOfNightText(
        deepOfNight: BossGameText(zh: "深夜", en: "The Deep of Night", textId: nil),
        depth: BossGameText(zh: "深度", en: "Depth", textId: nil),
        mutation: BossGameText(zh: "变异个体", en: "Variant", textId: nil),
        mutationCount: .empty,
        description: .empty
    )

    public init(
        deepOfNight: BossGameText, depth: BossGameText, mutation: BossGameText,
        mutationCount: BossGameText, description: BossGameText
    ) {
        self.deepOfNight = deepOfNight
        self.depth = depth
        self.mutation = mutation
        self.mutationCount = mutationCount
        self.description = description
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        deepOfNight = container.bossValue(.deepOfNight, default: Self.fallback.deepOfNight)
        depth = container.bossValue(.depth, default: Self.fallback.depth)
        mutation = container.bossValue(.mutation, default: Self.fallback.mutation)
        mutationCount = container.bossValue(.mutationCount, default: .empty)
        description = container.bossValue(.description, default: .empty)
    }

    /// 「深夜」的显示词；数据缺失时退回内置文案。
    public var deepOfNightTitle: String {
        deepOfNight.display.isEmpty ? Self.fallback.deepOfNight.zh : deepOfNight.display
    }

    public var depthTitle: String {
        depth.display.isEmpty ? Self.fallback.depth.zh : depth.display
    }

    /// 「变异个体」。游戏文本里 338806 是「已打倒变异个体」这种整句，
    /// 只有其中的名词能当标题用，所以这里做一次收敛。
    public var mutationTitle: String {
        let text = mutation.zh
        if text.contains("变异个体") { return "变异个体" }
        return text.isEmpty ? Self.fallback.mutation.zh : text
    }
}

/// 页面顶部的模式选择：常规，或「深夜 · 深度 1…5」。
///
/// v2 的布尔「深夜」开关在这里被替换掉：深夜一共有 5 个深度，每个深度的血量与
/// 攻击力倍率都不同（最终 Boss 档深度 5 的伤害是深度 1 的 2.27 倍），一个开关
/// 根本表达不了。
public enum BossNightMode: Int, CaseIterable, Identifiable, Sendable, Hashable {
    case normal = 0
    case depth1 = 1
    case depth2 = 2
    case depth3 = 3
    case depth4 = 4
    case depth5 = 5

    public var id: Int { rawValue }

    /// 深度 1…5；常规模式为 nil。
    public var depth: Int? { self == .normal ? nil : rawValue }

    public var isDeepOfNight: Bool { self != .normal }

    public static func depth(_ value: Int) -> BossNightMode {
        BossNightMode(rawValue: value) ?? .normal
    }

    /// 数据集缺 `deepOfNightText` 时的兜底标题。正常走 `BossDataset.title(for:)`。
    public var builtinTitle: String {
        Self.title(depth: depth, deepOfNight: "深夜", depthWord: "深度")
    }

    static func title(depth: Int?, deepOfNight: String, depthWord: String) -> String {
        guard let depth else { return "常规" }
        return "\(deepOfNight) · \(depthWord) \(depth)"
    }
}

/// 削韧槽的三种语义。`poise = -1`（子弹 / 投射物等实体）与 `poise = 0`（没有削韧槽）
/// 都算不出有效韧性，但**不是一回事**，文案必须分开；两端口径一致。
public enum BossPoiseKind: String, Sendable, Hashable {
    /// superArmorDurability > 0，能算出有效韧性。
    case value
    /// superArmorDurability = 0：没有削韧槽。
    case zero
    /// superArmorDurability < 0：不吃削韧。
    case none

    /// 算不出有效韧性时的显示文案（与 Windows 端 fmtPoise 一致）。
    ///
    /// `.value` 走到这里只有一种来源：poise > 0，但承受削韧倍率是 0 / 非有限
    /// （数据异常）。它既不是「不吃削韧」也不是「无削韧槽」，两端一律给
    /// 占位符「—」，原因写在数值下面的小字里（poiseCaption）；空串会让
    /// 数值格看起来像渲染坏了。
    public var placeholder: String {
        switch self {
        case .value: return "—"
        case .zero: return "无削韧槽"
        case .none: return "不吃削韧"
        }
    }
}

/// 「首领数据」页里两端必须逐字相同的几串文案与数字格式。
///
/// 对应 Windows 端 `renderer/pages/bosses.js` 的 `BADGE_LABEL_UNCERTAIN` /
/// `BADGE_DEEP_ROW` / `rowCountText()` / `poiseCaption()`。放在 RelicCore 里
/// 是为了让 RelicCoreChecks 能直接断言这些串——写在 SwiftUI 视图里就只能靠人眼比对。
public enum BossRowText {
    /// 行内徽标：Paramdex 名带 "?"，阶段 / 用途属社区推测。
    public static let labelUncertainBadge = "标签为社区推测"
    /// 行内徽标：这一行当前显示的是深夜数值（depthStats 口径）。
    ///
    /// schemaVersion 3 起判据是 `hasDepthStats` 而不是 `hasDeepOfNight`：394 条数值行
    /// **全部**带 depthStats，深度模式下每一行的血量 / 攻击倍率都变了；只有 31 行另外
    /// 带 deepOfNight（深夜专属的那组常驻修正）。按 deepOfNight 挂这个徽标会让用户
    /// 以为同卡其余行在深夜下数值不变——那是错的。
    public static let deepRowBadge = "深夜数值"
    /// 行内 / 卡头徽标：这一行除了深度倍率，还额外吃一组「深夜专属」的常驻修正
    /// （deepOfNight：削韧恢复倍率 / 异常发动基准 / 常驻 SpEffect 清单另算一套）。
    public static let deepExclusiveBadge = "深夜专属修正"

    /// 副标题徽标：nameZh 为空时用 nameZhFallback 当参考译名。
    /// 它来自《艾尔登法环》官方简中，**不是本作的游戏内文本**，必须写明白。
    public static let nameFallbackBadge = "参考译名 · 非本作游戏文本"
    /// 名字徽标：nameApprox —— 游戏文本不是逐字命中，靠中心词 / 唯一词条匹配上的。
    public static let nameApproxBadge = "近似匹配"
    /// 工具条开关：hidden = true 的组默认不显示。
    public static let hiddenToggleTitle = "显示隐藏实体"
    public static let hiddenToggleHelp = "召唤物 / 投射物等非首领实体"
    /// 展开区小字：整组 / 该行不掉任何奖励。
    public static let noRewardGroupNote = "该组不掉任何奖励（getSoul / 掉落表全为 0 或 -1）"
    public static let noRewardRowNote = "该行不掉任何奖励"
    /// 该行没有 depthStats 时的深夜小表占位文案。
    public static let noDepthStatsText = "该行无深夜数值"
    /// 变异个体块的标题与说明。
    public static let mutationPickerTitle = "按变异个体计算"
    public static let mutationPickerNone = "无"
    public static let mutationStackNote = "变异倍率在其它缩放之上再乘一层，按参数结构推断"
    public static let mutationCountNote = "表里是「有几只被变异」的只数，不是百分比概率"
    /// 人数缩放明细里攻击力列的「1 倍」写法。
    public static let attackRateUnchanged = "不变"
    /// 夜王各深度出现权重为 0 时的说明。
    public static let depthWeightZero = "该深度不会出现"
    /// 底部「人数缩放档位说明」的结论段（notes.multiplayerScalingAudit 的中文摘要）。
    public static let multiplayerAuditSummary =
        "多人不是简单乘倍：血量按档位从 ×1 到 ×3 不等（最终 Boss 档才是 ×2 / ×3，"
        + "野外常见档 7740 只有 ×1.1 / ×1.2，突袭档 98810 / 98815 完全不加血）；"
        + "7744 / 7753 / 7754 / 7758 四档的敌人攻击力还会上浮 10% / 20%；"
        + "防御、卢恩与掉落、异常触发阈值三项人数缩放一概不碰，"
        + "变的只是异常累积量与发动伤害倍率（都往下走，人越多越难上异常）。"

    /// 卡头右侧的数值行计数：「N 条数值行」。
    public static func rowCount(_ count: Int) -> String { "\(count) 条数值行" }

    /// 血量旁的多人攻击徽标：「多人攻击 ×1.1」。
    public static func multiplayerAttackBadge(_ attackRate: Double) -> String {
        "多人攻击 ×" + decimal(attackRate, digits: 3)
    }

    /// 人数缩放明细里的攻击力值：1 倍时写「不变」，避免「×1」被当成没读到数据。
    public static func attackRateText(_ value: Double) -> String {
        guard value.isFinite else { return "—" }
        if abs(value - 1) < 0.0001 { return attackRateUnchanged }
        return "×" + decimal(value, digits: 3)
    }

    /// 夜王某深度的出现权重文案。
    public static func depthWeightText(_ weight: Int) -> String {
        weight <= 0 ? depthWeightZero : "权重 \(weight)"
    }

    /// poise > 0 却算不出有效韧性时的小字（承受削韧倍率为 0 / 非有限）。
    /// 此时数值格给 `BossPoiseKind.value.placeholder`（「—」），原因写在这里。
    public static func abnormalPoiseTakenCaption(_ factor: Double) -> String {
        "承受削韧倍率异常（\(decimal(factor, digits: 3))）"
    }

    /// 展开态「有效韧性」下面的小字，四支两端逐字一致（Windows 端
    /// `pages/bosses.js` 的 `poiseCaption()`）。
    ///
    /// - `hasEffectivePoise`：算得出有效韧性（poise > 0 且承受削韧倍率是正的有限数）。
    /// - `poise`：原始 superArmorDurability；缺字段时两端都取 -1。
    /// - `poiseTakenTotal`：poiseTakenBase × tier.poiseTaken。
    public static func poiseCaption(
        poise: Double,
        poiseTakenTotal: Double,
        kind: BossPoiseKind,
        hasEffectivePoise: Bool
    ) -> String {
        if hasEffectivePoise {
            return "韧性 \(decimal(poise, digits: 0)) ÷ 承受削韧 \(decimal(poiseTakenTotal, digits: 3))"
        }
        switch kind {
        case .zero: return "superArmorDurability = 0，该实体没有削韧槽"
        case .none: return "superArmorDurability = \(decimal(poise, digits: 0))"
        case .value: return abnormalPoiseTakenCaption(poiseTakenTotal)
        }
    }

    /// 展开态「多人缩放明细」标题右边的档位说明，三支两端逐字一致（Windows 端
    /// `pages/bosses.js` 的 `scalingCaption()`）。
    ///
    /// id 前面的「#」两端都写：macOS 的底部档位表、Windows 的底部档位表都写 `#<id>`。
    public static func scalingCaption(scalingID: Int?, groupTitle: String?) -> String {
        guard let scalingID else { return "无缩放档位" }
        guard let groupTitle, !groupTitle.isEmpty else { return "档位 #\(scalingID)" }
        return "档位 #\(scalingID) · \(groupTitle)"
    }

    /// 去掉多余 0 的小数：1.350 → 1.35，2.0 → 2（与 Windows 端 fmtNumber 同口径）。
    public static func decimal(_ value: Double, digits: Int = 2) -> String {
        guard value.isFinite else { return "—" }
        var text = String(format: "%.\(digits)f", value)
        if text.contains(".") {
            while text.hasSuffix("0") { text.removeLast() }
            if text.hasSuffix(".") { text.removeLast() }
        }
        return text.isEmpty ? "0" : text
    }
}

/// 一条战斗记录换算到指定人数 / 模式后的结果。
public struct BossComputedStats: Sendable, Hashable {
    /// 玩家真正要打掉的血量。
    public let hp: Int
    /// 有效韧性 = poise / (poiseTakenBase × tier.poiseTaken)；nil 表示算不出（见 poiseKind）。
    public let effectivePoise: Double?
    /// 有效韧性为 nil 时用它区分「不吃削韧」与「无削韧槽」。
    public let poiseKind: BossPoiseKind
    /// 削韧恢复速度 = poiseRecover × poiseRecoverMultiplier × tier.poiseRecover。
    public let poiseRecover: Double
    /// 异常发动伤害倍率 = ailmentDamageRateBase × tier.ailmentDamageRate。
    public let ailmentDamageRate: Double
    /// Boss 承受的异常累积量倍率（只来自人数缩放）。
    public let ailmentBuildupRate: Double
    /// 中毒 / 腐败的发动伤害倍率。
    public let poisonDamageRate: Double
    /// 本次换算用到的人数档。
    public let tier: BossScalingTier
    /// 本次换算用到的常驻缩放 SpEffect ID。
    public let permScalingIds: [Int]
    public let hpMultiplier: Double
    public let poiseTakenBase: Double
    /// 敌人攻击力倍率 = 基准 × 人数档 × 变异档；页面直接展示这个数。
    public let attackRate: Double
    public let attackRates: BossAttackRates
    /// 对玩家耐力的削减倍率。
    public let staminaAttackRate: Double
    /// 卢恩倍率（只有变异个体会动它）。
    public let runeRate: Double
    /// 本次换算所处的模式。
    public let mode: BossNightMode
    /// 选深度但该行没有 depthStats 时为 true —— 页面要写「该行无深夜数值」。
    public let depthMissing: Bool
    /// 本次换算叠加的变异档位（未选时为 nil）。
    public let mutation: BossMutation?
}

public struct BossFight: Codable, Sendable, Hashable, Identifiable {
    public let npcId: Int
    public let npcIds: [Int]
    public let paramdexName: String?
    public let labelZh: String
    public let labelEn: String
    /// 代表行的 Paramdex 名带 "?"，阶段 / 用途属社区推测。
    public let labelUncertain: Bool
    /// 夜王：普通远征 / 至暗战实际使用的行。
    public let isMain: Bool
    /// 守夜 / 野外：该行的威胁档位。
    public let threat: String?

    /// 1 人时玩家真正要打掉的血量（已含常驻缩放）。
    public let hp: Int
    /// NpcParam.hp 原始字段。
    public let hpBase: Int
    public let hpMultiplier: Double
    /// superArmorDurability；-1 表示不吃削韧。
    public let poise: Double
    /// saRecoveryRate。
    public let poiseRecover: Double
    public let poiseTakenBase: Double
    public let poiseRecoverMultiplier: Double
    public let damageRates: BossDamageRates
    public let ailmentDamageRateBase: Double
    public let resist: BossResistances
    public let immune: [String]
    public let permScalingIds: [Int]
    public let deepOfNight: BossDeepOfNightStats?
    public let scalingId: Int?
    public let scaling: BossScalingPair?

    /// 常驻攻击力倍率（五属性同值时的代表值）。
    public let attackRateBase: Double
    public let attackRatesBase: BossAttackRates
    public let staminaAttackRateBase: Double
    /// ChaosMatchingCorrectParam 行号。**可能与 scalingId 不等**（14 行如此）。
    public let chaosCorrectId: Int?
    /// 深度 1…5 的数值；null 表示这一行没有深夜数值。
    public let depthStats: [Int: BossDepthStats]
    /// 代表行自己的变异档位（SpEffectSetParam 行号）。
    public let mutationSetId: Int?
    /// 合并进本行的所有原始行用到的变异档位。
    public let mutationPool: [Int]
    /// 该行不掉任何奖励（getSoul / chaosMatchingRewardLotId / itemLotId_enemy 全是 0 或 -1）。
    public let noReward: Bool

    /// 出场场合（schemaVersion 4），按 `BossRoleCatalog.order` 排好、无重复。
    /// 合并行时是各原始行场合的并集，逐行的场合看 `rowRoles`。
    /// 数据缺失（旧版数据集）时为空数组，页面写「数据未内置」。
    public let roles: [String]
    /// 每个场合的出处（逐表逐行），键集合与 `roles` 相同。
    public let roleEvidence: [String: [BossRoleEvidence]]
    /// 合并进本行的各原始 NpcParam 行各自的场合，键是 npcId。
    public let rowRoles: [Int: [String]]

    public var id: Int { npcId }

    private enum CodingKeys: String, CodingKey {
        case npcId, npcIds, paramdexName, labelZh, labelEn, labelUncertain, isMain, threat
        case hp, hpBase, hpMultiplier, poise, poiseRecover, poiseTakenBase, poiseRecoverMultiplier
        case damageRates, ailmentDamageRateBase, resist, immune, permScalingIds
        case deepOfNight, scalingId, scaling
        case attackRateBase, attackRatesBase, staminaAttackRateBase
        case chaosCorrectId, depthStats, mutationSetId, mutationPool, noReward
        case roles, roleEvidence, rowRoles
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        npcId = container.bossInt(.npcId, default: 0)
        let ids = container.bossIntArray(.npcIds)
        npcIds = ids.isEmpty ? [container.bossInt(.npcId, default: 0)] : ids
        paramdexName = container.bossOptionalString(.paramdexName)
        labelZh = container.bossString(.labelZh)
        labelEn = container.bossString(.labelEn)
        labelUncertain = container.bossBool(.labelUncertain)
        isMain = container.bossBool(.isMain)
        threat = container.bossOptionalString(.threat)
        hp = container.bossInt(.hp, default: 0)
        hpBase = container.bossInt(.hpBase, default: 0)
        hpMultiplier = container.bossDouble(.hpMultiplier, default: 1)
        poise = container.bossDouble(.poise, default: -1)
        poiseRecover = container.bossDouble(.poiseRecover, default: 0)
        poiseTakenBase = container.bossDouble(.poiseTakenBase, default: 1)
        poiseRecoverMultiplier = container.bossDouble(.poiseRecoverMultiplier, default: 1)
        damageRates = container.bossValue(.damageRates, default: BossDamageRates.neutral)
        ailmentDamageRateBase = container.bossDouble(.ailmentDamageRateBase, default: 1)
        resist = container.bossValue(.resist, default: BossResistances())
        immune = container.bossArray(.immune)
        permScalingIds = container.bossIntArray(.permScalingIds)
        deepOfNight = try? container.decodeIfPresent(BossDeepOfNightStats.self, forKey: .deepOfNight)
        scalingId = container.bossOptionalInt(.scalingId)
        scaling = try? container.decodeIfPresent(BossScalingPair.self, forKey: .scaling)
        attackRateBase = container.bossDouble(.attackRateBase, default: 1)
        attackRatesBase = container.bossValue(.attackRatesBase, default: BossAttackRates.neutral)
        staminaAttackRateBase = container.bossDouble(.staminaAttackRateBase, default: 1)
        chaosCorrectId = container.bossOptionalInt(.chaosCorrectId)
        depthStats = container.bossNumberKeyedDictionary(.depthStats)
        mutationSetId = container.bossOptionalInt(.mutationSetId)
        mutationPool = container.bossIntArray(.mutationPool)
        noReward = container.bossBool(.noReward)
        roles = BossRoleCatalog.normalized(container.bossArray(.roles))
        // 出处逐条宽容解码：一条坏证据只丢它自己，不连累同一场合的其它出处。
        let rawEvidence: [String: [BossFailable<BossRoleEvidence>]] = container.bossDictionary(.roleEvidence)
        roleEvidence = rawEvidence.mapValues { $0.compactMap(\.value) }
        let rawRowRoles: [String: [String]] = container.bossDictionary(.rowRoles)
        rowRoles = rawRowRoles.reduce(into: [:]) { result, entry in
            guard let id = Int(entry.key) else { return }
            result[id] = BossRoleCatalog.normalized(entry.value)
        }
    }

    // MARK: 出场场合

    /// 这一行有没有场合数据（旧版数据集没有）。
    public var hasRoles: Bool { !roles.isEmpty }

    /// 这一行是否只出现在默认隐藏的场合（「未放置」「随从/召唤物」）。
    /// 没有场合数据的行不算——缺数据不能被当成「未放置」藏起来。
    public var isHiddenByDefault: Bool {
        hasRoles && roles.allSatisfy { BossRoleCatalog.hiddenRoles.contains($0) }
    }

    /// 这一行属不属于某个分组（看 `roles` 与分组场合有无交集）。
    public func belongs(to group: BossCard.Group) -> Bool {
        roles.contains { group.contains(role: $0) }
    }

    /// 某个场合的出处；没有时为空数组（页面写「数据未内置」）。
    public func evidence(for role: String) -> [BossRoleEvidence] {
        roleEvidence[role] ?? []
    }

    /// 合并进本行的原始行按场合归拢：同一组场合的 npcId 放在一起，
    /// 顺序按场合组在本行里第一次出现的 npcId 顺序（npcIds 的顺序）。
    /// 只有一种场合组合时返回一个元素；没有 rowRoles 时返回空数组。
    public var rowRoleGroups: [(roles: [String], npcIds: [Int])] {
        var order: [[String]] = []
        var members: [[String]: [Int]] = [:]
        let ids = npcIds.filter { rowRoles[$0] != nil } + rowRoles.keys.sorted().filter { !npcIds.contains($0) }
        for id in ids {
            guard let roles = rowRoles[id] else { continue }
            if members[roles] == nil { order.append(roles) }
            members[roles, default: []].append(id)
        }
        return order.map { ($0, members[$0] ?? []) }
    }

    /// 合并行的各原始行场合不同（此时展开区要逐行写出来，否则并集会让人以为每行都这样）。
    public var hasMixedRowRoles: Bool { rowRoleGroups.count > 1 }

    /// 显示用标签：labelZh 为空时依次回退 labelEn / paramdexName / npcId。
    public var displayLabel: String {
        if !labelZh.isEmpty { return labelZh }
        if !labelEn.isEmpty { return labelEn }
        if let paramdexName, !paramdexName.isEmpty { return paramdexName }
        return "行 \(npcId)"
    }

    /// 该行是否有「深夜」专属缩放；没有时深夜数值与常规相同。
    public var hasDeepOfNight: Bool { deepOfNight != nil }

    /// 该行是否有逐深度的数值（depthStats）。没有的行在深度模式下要写「该行无深夜数值」。
    public var hasDepthStats: Bool { !depthStats.isEmpty }

    /// 该行能不能变异（chaosMatchingSpEffectSetParamId != -1）。
    public var canMutate: Bool { !mutationPool.isEmpty }

    /// 「演出行」：登场动画 / 血条实体 / 教程这类玩家打不到、或者只是挂血条的行。
    /// 它们不像模板行那样一定 noReward（`鲜血君王 · 登场演出` 35500020、`血条实体`
    /// 45601020 都掉奖励），所以 noReward 那一层拦不住，得单独认标签。
    /// 只用于代表行评选，不影响展开区里的逐行展示。
    public static let stagingLabelKeywords = ["登场演出", "血条实体", "教程"]

    /// 见 `stagingLabelKeywords`。扫的是 `displayLabel`——页面上写着什么就按什么判，
    /// 免得「卡头写着登场演出、代码里按另一个字段判」这种对不上的情况。
    public var isStagingRow: Bool {
        let label = displayLabel
        return BossFight.stagingLabelKeywords.contains { label.contains($0) }
    }

    /// 深度 1…5 里实际有数值的那些（升序）。
    public var availableDepths: [Int] { depthStats.keys.sorted() }

    /// 该行威胁档位的短标签（守夜 / 野外）；夜王的 fight 没有 threat，返回 nil。
    ///
    /// schemaVersion 4 起它**不再决定分组**：threat 只是 multiPlayCorrectionParamId
    /// 的档位名（Field / Night Boss Threat），铃珠猎人野外版 31000010 挂的就是
    /// Night Boss Threat。页面只在展开区用 `threatTierCaption` 写一行小字。
    public var threatTitle: String? {
        guard let threat, !threat.isEmpty else { return nil }
        switch threat {
        case "night": return "守夜"
        case "field": return "野外"
        default: return threat
        }
    }

    /// 展开区「威胁档位」小字；夜王的 fight 没有 threat，返回 nil。
    public var threatTierCaption: String? {
        guard let threat, !threat.isEmpty else { return nil }
        return BossRoleText.threatTierCaption([threat])
    }

    public func immuneKinds() -> [BossAilmentKind] {
        let declared = Set(immune)
        let byFlag = BossAilmentKind.allCases.filter { declared.contains($0.rawValue) }
        return byFlag.isEmpty ? resist.immuneKinds : byFlag
    }

    // MARK: 换算

    /// 一次换算的基准数值（人数缩放与变异倍率都还没乘上去）。
    public struct Baseline: Sendable, Hashable {
        public let hp: Int
        public let hpMultiplier: Double
        public let poiseTakenBase: Double
        public let poiseRecoverMultiplier: Double
        public let ailmentDamageRateBase: Double
        public let attackRateBase: Double
        public let attackRatesBase: BossAttackRates
        public let staminaAttackRateBase: Double
        public let permScalingIds: [Int]
        /// 请求了某个深度，但这一行没有 depthStats —— 已退回常规数值。
        public let depthMissing: Bool
    }

    /// 基准数值。
    ///
    /// 深度模式取 `depthStats[N]`：它的 hp / poiseTakenBase / attackRateBase 已经把
    /// 常驻威胁档位、深夜修正、深度 N 倍率三层乘齐了。depthStats 里没有的几项
    /// （削韧恢复倍率、异常发动伤害基准、常驻 SpEffect 清单）仍取深夜那一组，
    /// 深夜组缺失时退回常规值——深度模式本身就是「深夜」，不能退回常规的那一套。
    public func baseline(mode: BossNightMode) -> Baseline {
        if let depth = mode.depth {
            guard let stats = depthStats[depth] else {
                let regular = baseline(mode: .normal)
                return Baseline(
                    hp: regular.hp, hpMultiplier: regular.hpMultiplier,
                    poiseTakenBase: regular.poiseTakenBase,
                    poiseRecoverMultiplier: regular.poiseRecoverMultiplier,
                    ailmentDamageRateBase: regular.ailmentDamageRateBase,
                    attackRateBase: regular.attackRateBase,
                    attackRatesBase: regular.attackRatesBase,
                    staminaAttackRateBase: regular.staminaAttackRateBase,
                    permScalingIds: regular.permScalingIds,
                    depthMissing: true
                )
            }
            return Baseline(
                hp: stats.hp,
                hpMultiplier: stats.hpMultiplier,
                poiseTakenBase: stats.poiseTakenBase,
                poiseRecoverMultiplier: deepOfNight?.poiseRecoverMultiplier ?? poiseRecoverMultiplier,
                ailmentDamageRateBase: deepOfNight?.ailmentDamageRateBase ?? ailmentDamageRateBase,
                attackRateBase: stats.attackRateBase,
                attackRatesBase: stats.attackRatesBase,
                staminaAttackRateBase: stats.staminaAttackRateBase,
                permScalingIds: deepOfNight?.permScalingIds ?? permScalingIds,
                depthMissing: false
            )
        }
        return Baseline(
            hp: hp, hpMultiplier: hpMultiplier, poiseTakenBase: poiseTakenBase,
            poiseRecoverMultiplier: poiseRecoverMultiplier,
            ailmentDamageRateBase: ailmentDamageRateBase,
            attackRateBase: attackRateBase, attackRatesBase: attackRatesBase,
            staminaAttackRateBase: staminaAttackRateBase,
            permScalingIds: permScalingIds, depthMissing: false
        )
    }

    public func tier(for players: BossPartySize) -> BossScalingTier {
        scaling?.tier(for: players) ?? .identity
    }

    /// 指定人数 / 模式 / 变异档位下玩家要打掉的血量。
    /// = depthStats[N].hp（或常规 hp）× 人数档血量倍率 × 变异血量倍率，最后一次取整。
    public func hp(
        for players: BossPartySize,
        mode: BossNightMode = .normal,
        mutation: BossMutation? = nil
    ) -> Int {
        let base = baseline(mode: mode)
        let scaled = Double(base.hp) * tier(for: players).hp * (mutation?.hp ?? 1)
        guard scaled.isFinite else { return base.hp }
        return Int(scaled.rounded())
    }

    /// 削韧槽语义：> 0 能算有效韧性，= 0 是「没有削韧槽」，< 0 是「不吃削韧」。
    public var poiseKind: BossPoiseKind {
        if poise < 0 || !poise.isFinite { return .none }
        return poise == 0 ? .zero : .value
    }

    /// 有效韧性 = poise / (poiseTakenBase × 人数档承受削韧倍率)；
    /// poise ≤ 0（不吃削韧 / 无削韧槽）或分母为 0 时返回 nil。
    /// poise = 0 不能算成「有效韧性 0」——那是「没有削韧槽」，与 -1 的「不吃削韧」都不该显示数字。
    /// 变异档位只改血量 / 攻击 / 卢恩，不碰削韧，所以这里没有 mutation 参数。
    public func effectivePoise(for players: BossPartySize, mode: BossNightMode = .normal) -> Double? {
        guard poiseKind == .value else { return nil }
        let factor = baseline(mode: mode).poiseTakenBase * tier(for: players).poiseTaken
        guard factor > 0, factor.isFinite else { return nil }
        return poise / factor
    }

    /// 削韧恢复速度 = saRecoveryRate × 常驻恢复倍率 × 人数档恢复倍率。
    public func poiseRecoverSpeed(for players: BossPartySize, mode: BossNightMode = .normal) -> Double {
        poiseRecover * baseline(mode: mode).poiseRecoverMultiplier * tier(for: players).poiseRecover
    }

    /// 异常发动伤害倍率。
    public func ailmentDamageRate(for players: BossPartySize, mode: BossNightMode = .normal) -> Double {
        baseline(mode: mode).ailmentDamageRateBase * tier(for: players).ailmentDamageRate
    }

    /// Boss 承受的异常累积量倍率（越小越难打出异常）。
    public func ailmentBuildupRate(for players: BossPartySize) -> Double {
        tier(for: players).buildupRate
    }

    /// 敌人攻击力倍率 = 基准（含深度）× 人数档 × 变异档。
    public func attackRate(
        for players: BossPartySize,
        mode: BossNightMode = .normal,
        mutation: BossMutation? = nil
    ) -> Double {
        baseline(mode: mode).attackRateBase * tier(for: players).attackRate * (mutation?.attackRate ?? 1)
    }

    /// 一次算齐所有换算结果。
    public func stats(
        for players: BossPartySize,
        mode: BossNightMode = .normal,
        mutation: BossMutation? = nil
    ) -> BossComputedStats {
        let base = baseline(mode: mode)
        let tier = tier(for: players)
        let mutationAttack = mutation?.attackRate ?? 1
        return BossComputedStats(
            hp: hp(for: players, mode: mode, mutation: mutation),
            effectivePoise: effectivePoise(for: players, mode: mode),
            poiseKind: poiseKind,
            poiseRecover: poiseRecoverSpeed(for: players, mode: mode),
            ailmentDamageRate: ailmentDamageRate(for: players, mode: mode),
            ailmentBuildupRate: tier.buildupRate,
            poisonDamageRate: tier.poisonRate,
            tier: tier,
            permScalingIds: base.permScalingIds,
            hpMultiplier: base.hpMultiplier,
            poiseTakenBase: base.poiseTakenBase,
            attackRate: base.attackRateBase * tier.attackRate * mutationAttack,
            attackRates: base.attackRatesBase.scaled(by: tier.attackRate * mutationAttack),
            staminaAttackRate: base.staminaAttackRateBase * tier.staminaAttackRate,
            runeRate: mutation?.runeRate ?? 1,
            mode: mode,
            depthMissing: base.depthMissing,
            mutation: mutation
        )
    }

    /// 展开区「深夜各深度」小表的一行。
    public struct DepthRow: Sendable, Hashable, Identifiable {
        public let depth: Int
        public let hp: Int
        public let attackRate: Double
        /// 承受削韧倍率 = depthStats[N].poiseTakenBase × 人数档承受削韧。
        public let poiseTaken: Double
        /// 有效韧性；算不出时为 nil（与主数值口径一致）。
        public let effectivePoise: Double?

        public var id: Int { depth }
    }

    /// 深度 1…5 的小表，按当前人数（与已选变异档位）换算。没有 depthStats 时返回空数组。
    public func depthRows(
        for players: BossPartySize,
        mutation: BossMutation? = nil
    ) -> [DepthRow] {
        availableDepths.map { depth in
            let mode = BossNightMode.depth(depth)
            let base = baseline(mode: mode)
            return DepthRow(
                depth: depth,
                hp: hp(for: players, mode: mode, mutation: mutation),
                attackRate: attackRate(for: players, mode: mode, mutation: mutation),
                poiseTaken: base.poiseTakenBase * tier(for: players).poiseTaken,
                effectivePoise: effectivePoise(for: players, mode: mode)
            )
        }
    }
}

// MARK: - 夜王 / 守夜 · 野外首领

public struct BossNightlord: Codable, Sendable, Hashable, Identifiable {
    public let menuId: Int
    public let paramdexName: String
    public let nameZh: String
    public let nameEn: String
    public let expeditionZh: String
    public let expeditionEn: String
    /// 只有 Paramdex 行名以 "[Everdark Sovereign]" 开头才是 true。
    public let everdark: Bool
    /// "normal" | "everdark" | "standardBearers" | "unknown"。
    public let variantKey: String
    public let variantNameZh: String
    public let variantNameEn: String
    public let sortId: Int
    public let weakness: [BossWeakness]
    public let descriptionZh: String
    public let descriptionEn: String
    public let fights: [BossFight]
    /// 各深度的出现权重（NightBossMenuParam.depth1..5ChanceWeight）。
    /// 权重 0 = 该深度不会出现（永夜之王 / 救世旗手在深度 1 就是 0）。
    public let depthChanceWeights: [Int: Int]
    /// 出场场合（fights 的 roles 并集，schemaVersion 4）。夜王卡片只进「夜王」分组，
    /// 突袭 / 事件 / 未放置这些场合只作卡头徽标（见 `BossCard.Group`）。
    public let roles: [String]
    /// 场合 → 含该场合的战斗行代表 npcId。
    public let roleVariants: [String: [Int]]

    public var id: Int { menuId }

    /// 深度 1…5 的权重（升序，缺的补 0）。
    public var orderedDepthChanceWeights: [(depth: Int, weight: Int)] {
        (1...5).map { ($0, depthChanceWeights[$0] ?? 0) }
    }

    /// 有没有权重数据；整表缺失时页面不显示这一块。
    public var hasDepthChanceWeights: Bool { !depthChanceWeights.isEmpty }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        menuId = container.bossInt(.menuId, default: 0)
        paramdexName = container.bossString(.paramdexName)
        nameZh = container.bossString(.nameZh)
        nameEn = container.bossString(.nameEn)
        expeditionZh = container.bossString(.expeditionZh)
        expeditionEn = container.bossString(.expeditionEn)
        everdark = container.bossBool(.everdark)
        variantKey = container.bossString(.variantKey, default: "normal")
        variantNameZh = container.bossString(.variantNameZh)
        variantNameEn = container.bossString(.variantNameEn)
        sortId = container.bossInt(.sortId, default: 0)
        weakness = container.bossArray(.weakness)
        descriptionZh = container.bossString(.descriptionZh)
        descriptionEn = container.bossString(.descriptionEn)
        fights = container.bossArray(.fights)
        depthChanceWeights = container.bossNumberKeyedIntDictionary(.depthChanceWeights)
        roles = BossRoleCatalog.groupRoles(declared: container.bossArray(.roles), rows: fights)
        roleVariants = container.bossDictionary(.roleVariants)
    }

    /// 永夜之王形态。
    public var isEverdark: Bool { variantKey == "everdark" || everdark }
}

public struct BossNightBoss: Codable, Sendable, Hashable, Identifiable {
    /// "nameEn@chrIds[0]"，守夜 / 野外首领的主键（nameEn 不唯一）。
    public let id: String
    public let nameEn: String
    public let nameZh: String
    public let nameSource: String
    /// true 表示名字是按 ID 结构推断的，不是直接查到的。
    public let nameInferred: Bool
    public let npcNameId: Int?
    public let chrIds: [Int]
    /// "night" | "field"。schemaVersion 4 起只是「威胁档位」，不再决定分组。
    public let tier: String
    public let tiers: [String]
    public let variants: [BossFight]
    /// 出场场合（variants 的 roles 并集，schemaVersion 4），决定这组首领出现在哪些分组。
    public let roles: [String]
    /// 场合 → 含该场合的变体代表 npcId。
    public let roleVariants: [String: [Int]]

    /// 名字不是逐字命中游戏文本，而是靠中心词 / 唯一词条匹配上的。
    public let nameApprox: Bool
    /// 命中的游戏文本词条（fmg / id / en / zh）。
    public let nameEvidence: BossNameEvidence?
    /// 取名过程的说明（近似匹配、社区认身份、让出同名词条等）。
    public let nameNote: String
    public let nameSourceUrl: String
    /// 被移出 nameZh 的旧手工译名（《艾尔登法环》官方简中，不是本作游戏文本）。
    public let nameZhFallback: String
    public let nameZhFallbackNote: String
    /// 生成器用 chrId 拼出来的占位名「未知敌人 cXXXX」。它既不是游戏文本也不是译名，
    /// 所以第二版核验把它从 nameZh 挪到了这里（只有 c7931 / c7932 两组非空）。
    public let displayFallbackZh: String
    /// 因为「同一个 nameZh 不能挂两组首领」而被挡下的游戏文本候选。
    public let nameZhRejected: BossNameEvidence?
    /// 召唤物 / 投射物等非首领实体，默认不显示。
    public let hidden: Bool
    /// 整组不掉任何奖励。
    public let noReward: Bool

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let nameEn = container.bossString(.nameEn)
        let chrIds = container.bossIntArray(.chrIds)
        let rawId = container.bossString(.id)
        self.nameEn = nameEn
        self.chrIds = chrIds
        if !rawId.isEmpty {
            id = rawId
        } else if let first = chrIds.first {
            id = "\(nameEn)@\(first)"
        } else {
            id = nameEn
        }
        nameZh = container.bossString(.nameZh)
        nameSource = container.bossString(.nameSource)
        nameInferred = container.bossBool(.nameInferred)
        npcNameId = container.bossOptionalInt(.npcNameId)
        tier = container.bossString(.tier, default: "field")
        tiers = container.bossArray(.tiers)
        variants = container.bossArray(.variants)
        roles = BossRoleCatalog.groupRoles(declared: container.bossArray(.roles), rows: variants)
        roleVariants = container.bossDictionary(.roleVariants)
        nameApprox = container.bossBool(.nameApprox)
        nameEvidence = try? container.decodeIfPresent(BossNameEvidence.self, forKey: .nameEvidence)
        nameNote = container.bossString(.nameNote)
        nameSourceUrl = container.bossString(.nameSourceUrl)
        nameZhFallback = container.bossString(.nameZhFallback)
        nameZhFallbackNote = container.bossString(.nameZhFallbackNote)
        displayFallbackZh = container.bossString(.displayFallbackZh)
        nameZhRejected = try? container.decodeIfPresent(BossNameEvidence.self, forKey: .nameZhRejected)
        hidden = container.bossBool(.hidden)
        noReward = container.bossBool(.noReward)
    }
}

/// 名字对照的证据：命中（或被挡下）的那条游戏文本词条。
public struct BossNameEvidence: Codable, Sendable, Hashable {
    /// 词条所在的 FMG，如 "item/NpcName"。
    public let fmg: String
    public let id: String
    public let en: String
    public let zh: String
    /// 只有 nameZhRejected 才有：被挡下的原因。
    public let reason: String

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        fmg = container.bossString(.fmg)
        id = container.bossString(.id)
        en = container.bossString(.en)
        zh = container.bossString(.zh)
        reason = container.bossString(.reason)
    }

    /// 「item/NpcName #905011000 · Golden Hippopotamus / 黄金河马」。
    public var summary: String {
        var text = fmg.isEmpty ? "游戏文本" : fmg
        if !id.isEmpty { text += " #\(id)" }
        let names = [en, zh].filter { !$0.isEmpty }.joined(separator: " / ")
        if !names.isEmpty { text += " · " + names }
        return text
    }
}

public struct BossNotes: Codable, Sendable {
    public let unmatchedNames: [BossUnmatchedName]
    /// 多人缩放的逐项核实结论（9 条中文）。底部「人数缩放档位说明」原样展示。
    public let multiplayerScalingAudit: [String]
    /// 深夜 / 深度 / 变异个体的核实结论（11 条中文）。
    public let deepOfNightAudit: [String]
    /// tier 与实际出场场合的对照结论（schemaVersion 4，notes.roleAudit.summary，4 条中文）。
    public let roleAuditSummary: [String]

    private enum CodingKeys: String, CodingKey {
        case unmatchedNames, multiplayerScalingAudit, deepOfNightAudit, roleAudit
    }

    private enum RoleAuditKeys: String, CodingKey {
        case summary
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        unmatchedNames = container.bossArray(.unmatchedNames)
        multiplayerScalingAudit = container.bossArray(.multiplayerScalingAudit)
        deepOfNightAudit = container.bossArray(.deepOfNightAudit)
        if let audit = try? container.nestedContainer(keyedBy: RoleAuditKeys.self, forKey: .roleAudit) {
            roleAuditSummary = audit.bossArray(.summary)
        } else {
            roleAuditSummary = []
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(unmatchedNames, forKey: .unmatchedNames)
        try container.encode(multiplayerScalingAudit, forKey: .multiplayerScalingAudit)
        try container.encode(deepOfNightAudit, forKey: .deepOfNightAudit)
        var audit = container.nestedContainer(keyedBy: RoleAuditKeys.self, forKey: .roleAudit)
        try audit.encode(roleAuditSummary, forKey: .summary)
    }
}

public struct BossUnmatchedName: Codable, Sendable, Hashable {
    public let nameEn: String
    public let chrId: Int

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        nameEn = container.bossString(.nameEn)
        chrId = container.bossInt(.chrId, default: 0)
    }
}

// MARK: - 出场场合（schemaVersion 4）

/// roleNames 的一项：场合的中文名 / 英文名 / 判定说明。
public struct BossRoleName: Codable, Sendable, Hashable {
    public let zh: String
    public let en: String
    public let description: String

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        zh = container.bossString(.zh)
        en = container.bossString(.en)
        description = container.bossString(.description)
    }
}

/// roleSummaryDetail 的一项。
public struct BossRoleSummaryDetail: Codable, Sendable, Hashable {
    /// nightBosses 中含该场合的组数（= roleSummary）。
    public let groups: Int
    public let variants: Int
    public let rows: Int
    /// 含该场合的夜王条数。
    public let nightlords: Int
    public let fights: Int
    public let fightRows: Int

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        groups = container.bossInt(.groups, default: 0)
        variants = container.bossInt(.variants, default: 0)
        rows = container.bossInt(.rows, default: 0)
        nightlords = container.bossInt(.nightlords, default: 0)
        fights = container.bossInt(.fights, default: 0)
        fightRows = container.bossInt(.fightRows, default: 0)
    }
}

/// 一条场合出处：哪一个原始行、在哪张地图 MSB、由哪张参数表的哪一行判定。
public struct BossRoleEvidence: Codable, Sendable, Hashable {
    /// 原始 NpcParam 行（合并行时可能不是代表行）。
    public let npcId: Int?
    /// 地图 MSB 名（入侵者 / 未放置为 nil）。
    public let msb: String?
    /// MSB part 名与 entityId，可为空串。
    public let part: String
    public let table: String
    public let row: String
    public let note: String

    public init(npcId: Int?, msb: String?, part: String = "", table: String, row: String, note: String) {
        self.npcId = npcId
        self.msb = msb
        self.part = part
        self.table = table
        self.row = row
        self.note = note
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        npcId = container.bossOptionalInt(.npcId)
        msb = container.bossOptionalString(.msb)
        part = container.bossString(.part)
        table = container.bossString(.table)
        row = container.bossString(.row)
        note = container.bossString(.note)
    }

    /// 出处摘要：「表名 行 · 地图」。两端同一口径（Windows 端 `evidenceSummary()`）：
    ///   * row 为空或「—」（未放置那种占位）时只写表名；
    ///   * msb 为空、或与 row 相同（「其他地图」那种 row 就是地图名）时不重复写地图。
    /// note 不进摘要（最长 500 多字），页面放在摘要下面的小字里。
    public var summary: String {
        var head = table
        if !row.isEmpty, row != "—" {
            head = head.isEmpty ? row : head + " " + row
        }
        var parts: [String] = head.isEmpty ? [] : [head]
        if let msb, !msb.isEmpty, msb != row { parts.append(msb) }
        return parts.isEmpty ? BossRoleText.evidenceMissing : parts.joined(separator: " · ")
    }
}

/// 出场场合的全局口径：排列顺序、默认隐藏的场合、每个场合落在哪个分组。
///
/// 数据集的 roles 是开放取值（生成器以后可能再加场合），这里只列已知的 14 个；
/// 未知场合一律排在已知场合后面、归入「其它场合」分组，不丢、不报错。
public enum BossRoleCatalog {
    /// roleNames 的键序，也是 roles 数组的规范顺序。
    public static let order: [String] = [
        "night", "prelude", "field", "stronghold", "mine", "evergaol", "tower",
        "raid", "invader", "event", "nightlord", "summon", "other", "unplaced",
    ]

    /// 默认隐藏的场合（沿用「显示隐藏实体」开关）：只出现在这两个场合的组 / 行默认不显示。
    public static let hiddenRoles: Set<String> = ["summon", "unplaced"]

    /// 合并进「其它场合」分组的已知场合（按规范顺序）。
    /// 高塔 / 突袭 / 入侵 / 事件是任务书点名的四个；守夜前哨、坑道精英、其他地图
    /// 三个同样不属于任何独立分组，一并放进来（否则这些组在默认视图里无处可去）。
    public static let otherGroupRoles: [String] = [
        "prelude", "mine", "tower", "raid", "invader", "event", "other",
    ]

    /// 在规范顺序里的位置；未知场合排在最后。
    public static func rank(_ role: String) -> Int {
        order.firstIndex(of: role) ?? order.count
    }

    /// 去重 + 按规范顺序排（未知场合按键名排在已知场合之后），去掉空串。
    public static func normalized(_ roles: [String]) -> [String] {
        Array(Set(roles.filter { !$0.isEmpty })).sorted { lhs, rhs in
            let left = rank(lhs), right = rank(rhs)
            return left == right ? lhs < rhs : left < right
        }
    }

    /// 组级 roles：数据集给了就用（再规范化一次），没给就取各行 roles 的并集。
    static func groupRoles(declared: [String], rows: [BossFight]) -> [String] {
        let normalizedDeclared = normalized(declared)
        if !normalizedDeclared.isEmpty { return normalizedDeclared }
        return normalized(rows.flatMap(\.roles))
    }
}

/// 「首领数据」页按出场场合分组的文案（两端逐字一致，对应 Windows 端
/// `pages/bosses.js` 的 `ROLE_TEXT` 表）。集中在一张表里，RelicCoreChecks 逐条断言。
public enum BossRoleText {
    /// 分组标题。前五个与数据集 roleNames 的中文名一致（夜王分组不叫「夜王战」），
    /// 「其它场合」是合并分组的名字，不是某个场合。
    public static let groupNightlord = "夜王"
    public static let groupNight = "守夜首领"
    public static let groupStronghold = "据点首领"
    public static let groupField = "场景头目"
    public static let groupEvergaol = "封印监牢"
    public static let groupOther = "其它场合"
    public static let groupSummon = "随从/召唤物"
    public static let groupUnplaced = "未放置"

    /// roleNames 缺失时的内置中文名（与 v4 数据集 roleNames.*.zh 逐字相同）。
    public static let builtinRoleNames: [String: String] = [
        "night": "守夜首领",
        "prelude": "守夜前哨",
        "field": "场景头目",
        "stronghold": "据点首领",
        "mine": "坑道精英",
        "evergaol": "封印监牢",
        "tower": "大空洞高塔首领",
        "raid": "突袭事件",
        "invader": "黑夜入侵者",
        "event": "地图事件",
        "nightlord": "夜王战",
        "summon": "随从/召唤物",
        "other": "其他地图",
        "unplaced": "未放置",
    ]

    /// 展开区小字的前缀：tier / threat 只是多人缩放档位。
    public static let threatTierLabel = "威胁档位"
    /// 展开区一次性的说明：为什么「威胁档位」和分组对不上。
    public static let threatTierNote =
        "威胁档位只是多人缩放档位（Field / Night Boss Threat），不代表出场场合；分组按地图放置判定的出场场合"
    /// 行 / 组没有 roles（旧版数据集）时的徽标。
    public static let rolesMissing = "出场场合：数据未内置"
    /// 某个场合没有出处明细时的占位。
    public static let evidenceMissing = "出处：数据未内置"
    /// 展开区每行「出场场合」小节的标题与说明。
    public static let roleSectionTitle = "出场场合"
    public static let roleSectionDetail = "按地图放置与抽选参数判定；分组看这里，不看威胁档位"
    /// 出处多于一条时的展开 / 收起按钮。
    public static let evidenceExpand = "展开全部出处"
    public static let evidenceCollapse = "只看每个场合的第一条出处"
    /// 底部说明里标在默认隐藏分组后面的注记。
    public static let hiddenGroupMark = "（默认隐藏）"
    /// 底部「出场场合说明」折叠块的标题。
    public static func overviewTitle(_ count: Int) -> String { "出场场合说明（\(count) 种）" }
    /// 底部 notes.roleAudit.summary 的小标题。
    public static func auditTitle(_ count: Int) -> String {
        "与威胁档位的对照（数据集 notes.roleAudit，\(count) 条）"
    }
    /// 底部场合说明表里的计数：「40 组」「1 组 · 夜王 6」「夜王 18」。
    /// 夜王战只有夜王有（守夜 / 野外首领 0 组），不写成「0 组 · 夜王 18」。
    public static func roleCountText(groups: Int, nightlords: Int) -> String {
        var parts: [String] = []
        if groups > 0 || nightlords == 0 { parts.append("\(groups) 组") }
        if nightlords > 0 { parts.append("夜王 \(nightlords)") }
        return parts.joined(separator: " · ")
    }

    /// 卡头计数：显示的行数，另有默认隐藏的行时补一句。
    public static func rowCount(visible: Int, hidden: Int) -> String {
        let base = BossRowText.rowCount(visible)
        return hidden > 0 ? base + "（另 \(hidden) 条已隐藏）" : base
    }
    /// 合并行各原始行场合不同时的小标题。
    public static let rowRolesTitle = "逐行场合"
    /// 分组筛选器的提示。
    public static let groupPickerHelp = "按出场场合分组；一组首领可以同时出现在多个分组里"
    /// 显示隐藏实体开关的补充说明（开关原有的 help 文案保持不变）。
    public static let hiddenToggleRoleHelp = "也控制「未放置」「随从/召唤物」两个场合（分组与展开区的行）"

    /// 「另有 N 条出处」。
    public static func evidenceMore(_ count: Int) -> String { "另有 \(count) 条出处" }

    /// 展开区底部：默认隐藏掉的行数。
    public static func hiddenRows(_ count: Int) -> String {
        "另有 \(count) 条「\(groupUnplaced)」/「\(groupSummon)」行已隐藏，打开「\(BossRowText.hiddenToggleTitle)」查看"
    }

    /// 「威胁档位 · 守夜首领威胁档 / 野外首领威胁档」。取值 night / field 翻成档位组名
    /// （与 `BossScalingGroup.title(for:)` 同一套：Night Boss Threat → 守夜首领威胁档），
    /// 未知取值原样写；去重保序；一个都没有时返回「威胁档位 · 无」。
    public static func threatTierCaption(_ threats: [String]) -> String {
        var seen: Set<String> = []
        let titles = threats.filter { !$0.isEmpty && seen.insert($0).inserted }.map { threat -> String in
            switch threat {
            case "night": return BossScalingGroup.title(for: "Night Boss Threat")
            case "field": return BossScalingGroup.title(for: "Field Boss Threat")
            default: return threat
            }
        }
        return threatTierLabel + " · " + (titles.isEmpty ? "无" : titles.joined(separator: " / "))
    }

    /// 底部说明：同时出现在多个分组的组数。名字最多列 `multiGroupNameLimit` 个，
    /// 其余写「等」（当前数据 49 组，全列出来是一整屏）。
    public static let multiGroupNameLimit = 12

    public static func multiGroupNote(count: Int, names: [String]) -> String {
        var list = names.prefix(multiGroupNameLimit).joined(separator: "、")
        if names.count > multiGroupNameLimit { list += " 等" }
        return "有 \(count) 组首领按出场场合同时属于多个分组（\(list)），"
            + "它们在各个分组下都会出现：卡头列出全部场合，折叠态代表行跟着当前分组走，"
            + "展开后每行标了自己的场合与出处。"
    }
}

// MARK: - 数据集

public struct BossDataset: Codable, Sendable {
    public let schemaVersion: Int
    public let gameVersion: String
    public let dataVersion: String
    public let generatedAt: String
    public let sources: [BossSource]
    public let affinityNames: [String: BossLocalizedName]
    public let scalingTiers: [String: BossScalingGroup]
    public let permanentScaling: [String: BossPermanentEffect]
    /// 数据集自带的取舍说明，页面底部原样展示。
    public let caveats: [String]
    public let nightlords: [BossNightlord]
    public let nightBosses: [BossNightBoss]
    public let notes: BossNotes?
    /// 深夜 / 深度 / 变异个体的游戏内简中原文。
    public let deepOfNightText: BossDeepOfNightText
    /// 深度 1…5 的全局控制（诅咒遗物率、地图挑战权重、天变数量权重）。
    public let deepOfNightDepths: [Int: BossDepthInfo]
    /// ChaosMatchingCorrectParam 各档位在 5 个深度上的倍率（22 档）。
    public let deepOfNightTiers: [String: BossDepthTier]
    /// 变异个体的 10 个档位。
    public let mutations: [Int: BossMutation]
    /// 各地图 × 各类敌人 × 各深度的变异只数（46 行）。
    public let mutationCategories: [BossMutationCategory]
    /// 出场场合的中文名 / 英文名 / 判定说明（schemaVersion 4，14 个键）。
    /// 缺失时页面退回 `BossRoleText.builtinRoleNames`。
    public let roleNames: [String: BossRoleName]
    /// nightBosses 中含该场合的组数。
    public let roleSummary: [String: Int]
    /// 每个场合的组 / 变体 / 行 / 夜王 / 战斗行计数。
    public let roleSummaryDetail: [String: BossRoleSummaryDetail]

    private enum CodingKeys: String, CodingKey {
        case schemaVersion = "bossesSchemaVersion"
        case gameVersion, dataVersion, generatedAt, sources, affinityNames
        case scalingTiers, permanentScaling, caveats, nightlords, nightBosses, notes
        case deepOfNightText, deepOfNightDepths, deepOfNightTiers, mutations, mutationCategories
        case roleNames, roleSummary, roleSummaryDetail
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = container.bossInt(.schemaVersion, default: 0)
        gameVersion = container.bossString(.gameVersion, default: "未知")
        dataVersion = container.bossString(.dataVersion, default: "未知")
        generatedAt = container.bossString(.generatedAt)
        sources = container.bossArray(.sources)
        affinityNames = container.bossDictionary(.affinityNames)
        let rawTiers: [String: BossScalingGroup] = container.bossDictionary(.scalingTiers)
        scalingTiers = rawTiers.reduce(into: [:]) { result, entry in
            result[entry.key] = entry.value.withID(Int(entry.key) ?? 0)
        }
        let rawPermanent: [String: BossPermanentEffect] = container.bossDictionary(.permanentScaling)
        permanentScaling = rawPermanent.reduce(into: [:]) { result, entry in
            result[entry.key] = entry.value.withID(Int(entry.key) ?? 0)
        }
        caveats = container.bossArray(.caveats)
        nightlords = container.bossArray(.nightlords)
        nightBosses = container.bossArray(.nightBosses)
        notes = try? container.decodeIfPresent(BossNotes.self, forKey: .notes)
        deepOfNightText = container.bossValue(.deepOfNightText, default: BossDeepOfNightText.fallback)
        deepOfNightDepths = container.bossNumberKeyedDictionary(.deepOfNightDepths)
        let rawDepthTiers: [String: BossDepthTier] = container.bossDictionary(.deepOfNightTiers)
        deepOfNightTiers = rawDepthTiers.reduce(into: [:]) { result, entry in
            result[entry.key] = entry.value.withID(Int(entry.key) ?? 0)
        }
        let rawMutations: [String: BossMutation] = container.bossDictionary(.mutations)
        mutations = rawMutations.reduce(into: [:]) { result, entry in
            guard let id = Int(entry.key) else { return }
            result[id] = entry.value.withID(id)
        }
        mutationCategories = container.bossArray(.mutationCategories)
        roleNames = container.bossDictionary(.roleNames)
        let rawSummary: [String: Double] = container.bossDictionary(.roleSummary)
        roleSummary = rawSummary.mapValues { Int($0.rounded()) }
        roleSummaryDetail = container.bossDictionary(.roleSummaryDetail)
    }

    /// 场合的中文名：优先取数据集 roleNames（游戏文本 / 生成器口径），缺失时退回
    /// 内置表，再不行原样显示键名——未知的新场合也不能渲染成空白徽标。
    public func roleTitle(_ role: String) -> String {
        if let name = roleNames[role], !name.zh.isEmpty { return name.zh }
        if let builtin = BossRoleText.builtinRoleNames[role] { return builtin }
        if let name = roleNames[role], !name.en.isEmpty { return name.en }
        return role
    }

    /// 场合的判定说明（roleNames.*.description）；缺失时为空串。
    public func roleDescription(_ role: String) -> String {
        roleNames[role]?.description ?? ""
    }

    /// 合并行的「逐行场合」：「逐行场合：夜王战 75000020 / 75002020；未放置 75001020」。
    /// 同一组场合用「 + 」连接（「守夜首领 + 大空洞高塔首领 31000020」）。
    /// 各原始行场合都一样（或没有 rowRoles）时返回 nil——页面不写这一行。
    public func rowRolesSummary(_ row: BossFight) -> String? {
        guard row.hasMixedRowRoles else { return nil }
        let text = row.rowRoleGroups.map { group in
            group.roles.map { roleTitle($0) }.joined(separator: " + ")
                + " " + group.npcIds.map(String.init).joined(separator: " / ")
        }.joined(separator: "；")
        return BossRoleText.rowRolesTitle + "：" + text
    }

    /// 页面要列出的全部场合：内置顺序在前，数据集里多出来的未知场合按键名排在后面。
    public var orderedRoles: [String] {
        let extra = Set(roleNames.keys).union(roleSummary.keys).subtracting(BossRoleCatalog.order)
        return BossRoleCatalog.order + extra.sorted()
    }

    /// 从原始 JSON 解码；顶层不是对象时抛 `BossDataError.notAnObject`，
    /// 其他失败抛 `BossDataError.undecodable`（带 codingPath 与原始描述，便于排障）。
    public static func decode(from data: Data) throws -> BossDataset {
        do {
            return try JSONDecoder().decode(BossDataset.self, from: data)
        } catch let error as DecodingError {
            if case .typeMismatch(_, let context) = error, context.codingPath.isEmpty {
                throw BossDataError.notAnObject
            }
            throw BossDataError.undecodable(describe(error))
        } catch {
            throw BossDataError.undecodable(String(describing: error))
        }
    }

    /// 把 `DecodingError` 压成一句能定位问题的中文说明。
    static func describe(_ error: DecodingError) -> String {
        func render(_ kind: String, _ context: DecodingError.Context) -> String {
            let path = context.codingPath.map(\.stringValue).filter { !$0.isEmpty }.joined(separator: ".")
            return "\(kind)（位置：\(path.isEmpty ? "顶层" : path)）：\(context.debugDescription)"
        }
        switch error {
        case .typeMismatch(let type, let context): return render("字段类型不符（期望 \(type)）", context)
        case .valueNotFound(let type, let context): return render("缺少必需的值（期望 \(type)）", context)
        case .keyNotFound(let key, let context): return render("缺少键「\(key.stringValue)」", context)
        case .dataCorrupted(let context): return render("数据损坏", context)
        @unknown default: return String(describing: error)
        }
    }

    public func permanentEffect(_ id: Int) -> BossPermanentEffect? {
        permanentScaling[String(id)]
    }

    /// 属性中文名：优先用数据集自带的 `affinityNames`（官方文本），缺失时退回内置文案，
    /// 避免页面硬编码与数据集漂移。物理四种没有 affinity 码，恒用内置文案。
    public func title(for kind: BossDamageKind) -> String {
        guard let code = kind.affinityCode,
              let name = affinityNames[String(code)],
              !name.display.isEmpty
        else { return kind.titleZh }
        return name.display
    }

    public func title(for kind: BossAilmentKind) -> String {
        guard let name = affinityNames[String(kind.affinityCode)], !name.display.isEmpty else {
            return kind.titleZh
        }
        return name.display
    }

    public func scalingGroup(_ id: Int) -> BossScalingGroup? {
        scalingTiers[String(id)]
    }

    public func mutation(_ id: Int) -> BossMutation? { mutations[id] }

    /// 某一行能选的变异档位（按 ID 升序），查不到明细的档位直接略过。
    public func mutations(for row: BossFight) -> [BossMutation] {
        row.mutationPool.sorted().compactMap { mutations[$0] }
    }

    public func depthTier(_ id: Int) -> BossDepthTier? { deepOfNightTiers[String(id)] }

    public func depthInfo(_ depth: Int) -> BossDepthInfo? { deepOfNightDepths[depth] }

    /// 深度 1…5 的全局控制，按深度升序。
    public var orderedDepthInfos: [BossDepthInfo] {
        deepOfNightDepths.keys.sorted().compactMap { deepOfNightDepths[$0] }
    }

    /// 变异只数表：按 (categoryId, mapId) 稳定排序，页面按类别分块。
    public var orderedMutationCategories: [BossMutationCategory] {
        mutationCategories.sorted {
            $0.categoryId == $1.categoryId ? $0.mapId < $1.mapId : $0.categoryId < $1.categoryId
        }
    }

    /// 页面模式选择器的标题：用 `deepOfNightText` 的游戏文本拼「深夜 · 深度 N」。
    public func title(for mode: BossNightMode) -> String {
        BossNightMode.title(
            depth: mode.depth,
            deepOfNight: deepOfNightText.deepOfNightTitle,
            depthWord: deepOfNightText.depthTitle
        )
    }

    /// 「变异个体」的游戏文本词。
    public var mutationTitle: String { deepOfNightText.mutationTitle }
}

// MARK: - 页面用的统一卡片模型

/// 搜索折叠：与词条库一致（大小写 / 全半角 / 变音不敏感，去空格）。
public func bossFoldForSearch(_ text: String) -> String {
    text.foldedForSearch
}

/// 名字缺失时的灰色徽标。原有四种取值与 Windows 端 `nameBadge()` 一一对应，文案必须相同；
/// schemaVersion 3 增加了 `community`（社区资料认出的身份）。
public enum BossNameBadge: String, Sendable, Hashable {
    /// nameSource = english-only：游戏文本里只有英文名。
    case englishOnly
    /// nameSource = chrid-fallback：游戏文本与 Paramdex 都没有名字，只能用 chrId 兜底。
    case noGameName
    /// nameSource = manual：按 Elden Ring 官方简中手工补录，不是本作游戏内文本。
    /// schemaVersion 3 起不再产出，但仍是合法取值，留着以免旧数据掉进 default 分支。
    case manual
    /// nameInferred：名字是按 ID 结构推断的（借兄弟行 / 序号对应）。
    case inferred
    /// nameSource = community / community-npcname：身份来自社区资料（4laric 的敌人表）。
    case community
    /// nameApprox：游戏文本不是逐字命中，靠中心词 / 唯一词条匹配上的。
    case approx
    /// 主标题取自 nameZhFallback（《艾尔登法环》官方简中的参考译名，不是本作文本）。
    case fallback

    public var text: String {
        switch self {
        case .englishOnly: return "仅英文名"
        case .noGameName: return "无游戏内名称"
        case .manual: return "名称手工补录"
        case .inferred: return "名称按 ID 推断"
        case .community: return "社区资料"
        case .approx: return BossRowText.nameApproxBadge
        case .fallback: return BossRowText.nameFallbackBadge
        }
    }
}

/// 一张卡片里有多少行带某类深夜数值。只看代表行会把「首条代表行没有、其余行有」的
/// 卡片判错，所以一律扫描整卡。取值与 Windows 端 `deepCoverage()` 一致。
///
/// **两套口径，别混用**（schemaVersion 3）：
///   * `BossCard.deepCoverage` 数的是 `hasDepthStats`——「深度模式下这张卡的数值变不变」，
///     用 `badgeText`（「深夜数值」）；v3 数据里 394 行全部有 depthStats，所以实际恒为 `.all`。
///   * `BossCard.deepOfNightCoverage` 数的是 `hasDeepOfNight`——「有没有额外那组深夜专属
///     常驻修正」，用 `exclusiveBadgeText`（「深夜专属修正」）；只有 31 行有。
public enum BossDeepCoverage: String, Sendable, Hashable {
    case none
    case some
    case all

    /// 深度模式下挂在卡头的「这张卡有深夜数值」徽标；none 不挂徽标。
    public var badgeText: String? {
        switch self {
        case .none: return nil
        case .some: return "部分行有深夜数值"
        case .all: return BossRowText.deepRowBadge
        }
    }

    /// 深度模式下挂在卡头的「深夜专属修正」徽标（deepOfNight 口径）；none 不挂徽标。
    public var exclusiveBadgeText: String? {
        switch self {
        case .none: return nil
        case .some: return "部分行有" + BossRowText.deepExclusiveBadge
        case .all: return BossRowText.deepExclusiveBadge
        }
    }
}

public struct BossCard: Identifiable, Sendable, Hashable {
    /// 页面的分组筛选（schemaVersion 4 起按出场场合 roles，不再按 tier）。
    ///
    /// # 分组规则（两端唯一正式版本，Windows 端 `GROUPS` / `itemGroups()` 必须照抄）
    ///
    ///   * 夜王：夜王卡片（nightlords）固定只进这一组；它们的突袭 / 地图事件 / 未放置
    ///     场合只作卡头徽标。roleSummary 本来就只数 nightBosses，这样守夜 / 野外那些
    ///     分组的计数才能与 roleSummary 逐项相等。
    ///   * 守夜首领 / 据点首领 / 场景头目 / 封印监牢：各对应一个场合（night / stronghold /
    ///     field / evergaol）。
    ///   * 其它场合：守夜前哨 / 坑道精英 / 大空洞高塔首领 / 突袭事件 / 黑夜入侵者 /
    ///     地图事件 / 其他地图，以及数据集以后新增的未知场合。没有 roles 的组
    ///     （旧版数据集）也放这里，卡头写「出场场合：数据未内置」。
    ///   * 随从/召唤物、未放置：默认隐藏，打开「显示隐藏实体」才出现在筛选里。
    ///
    /// 守夜 / 野外首领卡片的 roles 与哪个分组有交集就出现在哪个分组，可以同时出现在多个。
    public enum Group: String, CaseIterable, Identifiable, Sendable {
        case nightlord
        case night
        case stronghold
        case field
        case evergaol
        case other
        case summon
        case unplaced

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .nightlord: return BossRoleText.groupNightlord
            case .night: return BossRoleText.groupNight
            case .stronghold: return BossRoleText.groupStronghold
            case .field: return BossRoleText.groupField
            case .evergaol: return BossRoleText.groupEvergaol
            case .other: return BossRoleText.groupOther
            case .summon: return BossRoleText.groupSummon
            case .unplaced: return BossRoleText.groupUnplaced
            }
        }

        public var symbol: String {
            switch self {
            case .nightlord: return "crown"
            case .night: return "moon.stars"
            case .stronghold: return "building.columns"
            case .field: return "map"
            case .evergaol: return "lock.shield"
            case .other: return "square.grid.2x2"
            case .summon: return "person.2"
            case .unplaced: return "questionmark.square.dashed"
            }
        }

        /// 这个分组直接对应的场合；「其它场合」是补集，返回 nil。
        public var role: String? {
            switch self {
            case .nightlord: return "nightlord"
            case .night: return "night"
            case .stronghold: return "stronghold"
            case .field: return "field"
            case .evergaol: return "evergaol"
            case .summon: return "summon"
            case .unplaced: return "unplaced"
            case .other: return nil
            }
        }

        /// 「随从/召唤物」「未放置」默认隐藏，打开「显示隐藏实体」才出现在筛选里。
        public var isHiddenByDefault: Bool {
            self == .summon || self == .unplaced
        }

        /// 某个场合落在这个分组里吗。
        public func contains(role: String) -> Bool {
            if let own = self.role { return own == role }
            return Self.forRole(role) == .other
        }

        /// 场合 → 分组。有独立分组的场合各归各组，其余一律「其它场合」。
        public static func forRole(_ role: String) -> Group {
            for group in allCases where group != .other && group.role == role {
                return group
            }
            return .other
        }

        /// 筛选器里可选的分组：默认隐藏的两个只在打开开关时出现。
        public static func visibleCases(includeHidden: Bool) -> [Group] {
            allCases.filter { includeHidden || !$0.isHiddenByDefault }
        }

        /// 「其它场合」分组里合并的场合（已知部分），按规范顺序。
        public static var otherRoles: [String] { BossRoleCatalog.otherGroupRoles }
    }

    /// 夜王卡片 / 守夜·野外首领卡片。显示逻辑（远征名、官方弱点、名字徽标、深度权重）
    /// 按它分支，不按「当前在哪个分组」分支——一张首领卡片可以出现在五六个分组里。
    public enum Kind: String, Sendable, Hashable {
        case nightlord
        case boss
    }

    public let id: String
    public let kind: Kind
    /// 主分组：卡片所属分组里排在最前的那个。决定这张卡的 `primaryRow`。
    public let group: Group
    /// 该卡片应出现在哪些分组筛选里（按 `Group.allCases` 顺序）：夜王固定 [.nightlord]；
    /// 守夜 / 野外首领按 roles 算，可以同时属于多个分组（见 `Group` 的规则）。
    public let groups: [Group]
    /// 出场场合（规范顺序），卡头逐个挂徽标。
    public let roles: [String]
    /// 威胁档位（守夜 / 野外首领的 tiers；缺失时退回 tier），只作展开区小字。
    public let tiers: [String]
    public let nameZh: String
    public let nameEn: String
    /// 夜王远征名（守夜 / 野外为空）。
    public let expeditionZh: String
    public let expeditionEn: String
    /// 变体名：永夜之王 / 救世旗手（普通形态为空）。
    public let variantNameZh: String
    public let variantNameEn: String
    public let isEverdark: Bool
    /// 菜单参数标注的官方弱点。
    public let weakness: [BossWeakness]
    public let descriptionZh: String
    /// 守夜 / 野外首领的名字来源，"english-only" 等表示不是游戏内简中文本。
    public let nameSource: String
    public let nameInferred: Bool
    /// 名字不是逐字命中游戏文本，靠中心词 / 唯一词条匹配上的。
    public let nameApprox: Bool
    /// 取名过程的说明（展开区小字）。
    public let nameNote: String
    public let nameSourceUrl: String
    /// 被移出 nameZh 的旧手工译名；当主标题时必须挂「参考译名 · 非本作游戏文本」。
    public let nameZhFallback: String
    public let nameZhFallbackNote: String
    /// 占位名「未知敌人 cXXXX」（生成器按 chrId 拼的，只有 c7931 / c7932 两组非空）。
    public let displayFallbackZh: String
    public let nameEvidence: BossNameEvidence?
    public let nameZhRejected: BossNameEvidence?
    /// 召唤物 / 投射物等非首领实体，默认不显示。
    public let hidden: Bool
    /// 整组不掉任何奖励（只作展开区小字，不影响是否显示）。
    public let noReward: Bool
    /// 夜王的 NightBossMenuParam 行号（守夜 / 野外为 nil）。
    /// 页面要拿它回查 depthChanceWeights，从卡片 id 里抠字符串太脆。
    public let menuId: Int?
    /// 守夜 / 野外首领的 chrId（对着 Paramdex / 存档工具查行时最常用）。
    public let chrIds: [Int]
    /// 守夜 / 野外首领的 NpcName 文本 ID。
    public let npcNameId: Int?
    /// 夜王的 fights / 守夜 · 野外的 variants。
    public let rows: [BossFight]
    /// 折叠后的搜索串（只含文本，不含分组名与数字行号）。
    public let searchKey: String
    /// 可按行号搜索的数字：全部 npcIds（含被合并掉的行）+ chrIds + npcNameId。
    public let numberKeys: [String]

    /// 主标题的四级回退（两端唯一正式版本，Windows 端 `displayName()` 必须照抄）：
    ///
    ///   1. `nameZh` —— 本作游戏文本里的简中名，不挂任何名字徽标；
    ///   2. `nameZhFallback` —— 《艾尔登法环》官方简中的参考译名，挂
    ///      `BossRowText.nameFallbackBadge`「参考译名 · 非本作游戏文本」；
    ///   3. `displayFallbackZh` —— 生成器用 chrId 拼的占位名「未知敌人 cXXXX」，
    ///      挂 `BossNameBadge.noGameName`「无游戏内名称」（nameSource = chrid-fallback）；
    ///   4. `nameEn` —— 只有英文名时就显示英文名。
    ///
    /// 四项都空才自己拼「未知敌人 cXXXX」——数据集里不存在这种组（nameEn 恒非空），
    /// 留着只是不让标题渲染成空白。
    ///
    /// 上一版把 nameZhFallback 压到副标题，理由是「参考译名不能冒充游戏里的名字」。
    /// 改成主标题是因为那个理由已经由徽标承担：14 组让出 nameZh 的首领在列表里全是
    /// 一串英文，中文用户扫不过来；徽标逐条写明「非本作游戏文本」，比整行英文更诚实。
    public var displayName: String {
        if !nameZh.isEmpty { return nameZh }
        if !nameZhFallback.isEmpty { return nameZhFallback }
        if !displayFallbackZh.isEmpty { return displayFallbackZh }
        if !nameEn.isEmpty { return nameEn }
        if let chrId = chrIds.first { return "未知敌人 c\(chrId)" }
        return "未知敌人"
    }

    /// 主标题用的是 `nameZhFallback`（第 2 级）。为真时徽标里必须有
    /// `BossRowText.nameFallbackBadge`，否则参考译名会被当成游戏里的名字。
    public var usesNameFallback: Bool { nameZh.isEmpty && !nameZhFallback.isEmpty }

    /// 主标题用的是 `displayFallbackZh`（第 3 级）——占位名，徽标是「无游戏内名称」。
    public var usesDisplayFallback: Bool {
        nameZh.isEmpty && nameZhFallback.isEmpty && !displayFallbackZh.isEmpty
    }

    /// 副标题：主标题不是英文名时把英文名显示出来（英文名恒非空，是最稳的对照键）。
    public var subtitleName: String? {
        guard !nameEn.isEmpty, nameEn != displayName else { return nil }
        return nameEn
    }

    /// 名字缺失 / 非游戏内文本时的灰色徽标；夜王的名字一定来自菜单参数，不挂徽标。
    ///
    /// **两层，不是一条链**——这两件事互相独立，挤进一条 if-else 链就必然丢信息：
    ///   1. 「名字本身缺不缺」：沿用 Windows 端 `nameBadge()` 的四档同序判定
    ///      （chrid-fallback → nameZh 空 → manual → inferred）。用户问题 ① 最关心的
    ///      「这只首领在本作游戏文本里根本没有简中名」就落在这一层，不能被别的分支抢走。
    ///   2. 「身份是谁认出来的」：nameSource 以 community 打头时追加「社区资料」。
    ///      但 nameZh 已经是货真价实的游戏文本时（community-npcname 且有 nameEvidence，
    ///      例如挖石山妖 NpcName 904600320）不挂——社区资料只定了「这个 chrId 是谁」，
    ///      挂上去会和展开区同时显示的「游戏文本依据」自相矛盾。
    ///
    /// 于是 Elder Dragon Greyoll / Storm King / Centipede Grub 这三组会同时挂
    /// 「无游戏内名称 + 社区资料」，两件事都说清楚。
    ///
    /// 第 3、4 层是「这个标题是怎么来的」：`nameApprox` → 近似匹配；主标题取自
    /// `nameZhFallback` → 参考译名。四层的顺序就是渲染顺序，Windows 端
    /// `nameBadges()` 逐项同序同文案。
    public var nameBadges: [BossNameBadge] {
        guard kind == .boss else { return [] }
        var badges: [BossNameBadge] = []
        if nameSource == "chrid-fallback" {
            badges.append(.noGameName)
        } else if nameZh.isEmpty {
            badges.append(nameSource == "english-only" ? .englishOnly : .noGameName)
        } else if nameSource == "manual" {
            badges.append(.manual)
        } else if nameInferred {
            badges.append(.inferred)
        }
        if nameSource.hasPrefix("community"), nameEvidence == nil {
            badges.append(.community)
        }
        if nameApprox { badges.append(.approx) }
        if usesNameFallback { badges.append(.fallback) }
        return badges
    }

    /// 只要一个徽标时取第一条（= 上面第 1 层的结论）。
    public var nameBadge: BossNameBadge? { nameBadges.first }

    /// 近似匹配徽标；夜王不挂。已并入 `nameBadges`，留着给旧调用点。
    public var showsApproxBadge: Bool { kind == .boss && nameApprox }

    /// 展开区那块「名字来历 + 组级不掉奖励」小字整体显不显示。
    ///
    /// 放在纯逻辑层是因为它真的漏过一次：`noReward` 的小字写在这块**里面**，外层条件却
    /// 只数五个名字字段，于是 Giant Skeleton Torso（chrIds [4960]，noReward = true、
    /// 五个名字字段全空）展开后永远看不到「该组不掉任何奖励」。条件写在视图里就没法断言。
    public var showsNameNotes: Bool {
        guard kind == .boss else { return false }
        return !nameNote.isEmpty || !nameZhFallbackNote.isEmpty || nameEvidence != nil
            || nameZhRejected != nil || !nameSourceUrl.isEmpty || noReward
    }

    /// 整张卡片有没有「深夜数值」（扫描全部行，不只看代表行）。
    ///
    /// 判据是 `hasDepthStats`：深度模式下变的是 depthStats 里的血量 / 攻击倍率 /
    /// 承受削韧，**每一条有 depthStats 的行都变**。早先按 `hasDeepOfNight` 数，会让
    /// 只有部分行带深夜专属常驻修正的卡片挂上「部分行有深夜数值」，等于告诉用户
    /// 「其余行在深夜下数值不变」——在深度模式下这是一句明确的错话。
    public var deepCoverage: BossDeepCoverage {
        coverage(of: \.hasDepthStats)
    }

    /// 整张卡片有没有「深夜专属常驻修正」（deepOfNight）。这是 depthStats 之外**另加**
    /// 的一组：削韧恢复倍率 / 异常发动基准 / 常驻 SpEffect 清单在深夜下换一套。
    public var deepOfNightCoverage: BossDeepCoverage {
        coverage(of: \.hasDeepOfNight)
    }

    private func coverage(of flag: KeyPath<BossFight, Bool>) -> BossDeepCoverage {
        guard !rows.isEmpty else { return .none }
        let hit = rows.filter { $0[keyPath: flag] }.count
        if hit == 0 { return .none }
        return hit == rows.count ? .all : .some
    }

    /// 全部主战行。**`isMain` 不唯一**：多阶段 / 多体夜王（玛利斯·永夜之王、
    /// 救世旗手、格诺斯塔…）会有 2～5 条，折叠态必须把这件事说清楚。
    public var mainRows: [BossFight] { rows.filter(\.isMain) }

    /// 某个分组下参与「代表行」评选的候选行。
    ///
    /// # 代表行规则（两端唯一正式版本，Windows 端 `representativeEntry()` 必须照抄）
    ///
    /// 四步依次过滤，**任何一步会把候选池清空，就跳过那一步**（跳过是规则的一部分，
    /// 不是容错）：
    ///   1. `roles`：先留下场合落在当前分组里的行（`BossFight.belongs(to:)`）——同一组
    ///      首领可能守夜 / 场景头目 / 据点各有一行，在「场景头目」下就该看场景头目那几行，
    ///      而不是血量更高的守夜行。夜王分组同样过滤（场合 nightlord），救世旗手的
    ///      「哈尔莫妮亚 · 蠕虫」46410000 虽是 isMain，却是未放置行，代表位让给实战的
    ///      「救世旗手 · 二阶段」76200210。schemaVersion 3 以前这一步按 `threat` 过滤，
    ///      但 threat 只是缩放档位（铃珠猎人野外版挂的就是 Night Boss Threat），已废弃；
    ///   2. `isMain`：收敛到主战行（夜王有；守夜 / 野外的 variants 没有这个字段）；
    ///   3. `isStagingRow`：排掉登场演出 / 血条实体 / 教程这类演出行；
    ///   4. `noReward`：排掉不掉奖励的行，免得 Paramdex 模板行抢走代表位。
    ///
    /// 然后在剩下的候选里取 1 人基准血量最高的一条，同血量取 npcId 较小者。
    ///
    /// ## 为什么第 4 步在 isMain **之后**
    ///
    /// 早先的版本把 noReward 写在 isMain 之前。按那个顺序实现会让 **11 张夜王卡**的
    /// 代表行退化成参数标签行：夜王收敛到 isMain 后候选池整池都是 noReward
    /// （格拉狄乌斯 75000020 等远征首领行本身不掉奖励，奖励挂在别处），先排 noReward
    /// 就把它们全踢掉，代表位落到「格拉狄乌斯（常驻缩放 ×3.54）」75000000 这类
    /// 只用来记参数的行上。`isMain` 是人工确认过的实战行，优先级本就比「掉不掉奖励」高。
    ///
    /// **这一版顺序即为两端的正式规则**，`BossDataChecks` 的 `representativeCases`
    /// 表（与 `windows/tests/bosses.test.mjs` 同一张）逐条钉住「卡片 + 分组 → 代表行
    /// npcId」，任一端改了顺序都会立刻红。
    ///
    /// ## 第 3 步为什么不能并进第 4 步
    ///
    /// 演出行不一定 noReward：`鲜血君王 · 登场演出` 35500020 与巨鸦群的 `血条实体`
    /// 45601020 都是 noReward = false，noReward 那层拦不住，只能单独认标签。
    ///
    /// 两步谁先谁后在 v3 数据上结果完全一样（脚本逐卡逐分组比对过 0 处差异），
    /// 但顺序仍要钉死：一旦出现「演出行掉奖励、实战行不掉奖励」的组合，先排谁就会
    /// 决定代表位归谁。这里按「先把打不到的行排掉，再谈奖励」取，与 Windows 端
    /// `candidateEntries()` 同序。
    public func rows(in group: Group) -> [BossFight] {
        var pool = rows
        let byRole = pool.filter { $0.belongs(to: group) }
        if !byRole.isEmpty { pool = byRole }
        let mains = pool.filter(\.isMain)
        if !mains.isEmpty { pool = mains }
        let playable = pool.filter { !$0.isStagingRow }
        if !playable.isEmpty { pool = playable }
        let rewarding = pool.filter { !$0.noReward }
        if !rewarding.isEmpty { pool = rewarding }
        return pool
    }

    /// 折叠态头条用的行：候选行里**血量最高**的一条（同血量取 npcId 较小者）。
    /// 排序用 1 人基准血量，与当前人数 / 模式无关，保证头条行不会跟着设置跳。
    public func representativeRow(in group: Group) -> BossFight? {
        rows(in: group).sorted { lhs, rhs in
            lhs.hp == rhs.hp ? lhs.npcId < rhs.npcId : lhs.hp > rhs.hp
        }.first
    }

    /// 卡片自身主分组下的代表行。
    public var primaryRow: BossFight? { representativeRow(in: group) }

    /// 主战行不止一条时，折叠态要并列展示全部主战血量。
    public var hasMultipleMainRows: Bool { mainRows.count > 1 }

    public func belongs(to group: Group) -> Bool { groups.contains(group) }

    /// 夜王卡片。
    public var isNightlord: Bool { kind == .nightlord }

    /// 有没有出场场合数据（旧版数据集没有；页面此时写「出场场合：数据未内置」）。
    public var hasRoles: Bool { !roles.isEmpty }

    /// 默认不显示的卡片：`hidden`（召唤物 / 投射物等非首领实体），或者全部场合都是
    /// 默认隐藏的「未放置」「随从/召唤物」。打开「显示隐藏实体」后才出现。
    public var isHiddenByDefault: Bool {
        if hidden { return true }
        return hasRoles && roles.allSatisfy { BossRoleCatalog.hiddenRoles.contains($0) }
    }

    /// 同时属于多个**默认可见**分组（一组首领多个出场场合）。
    public var hasMultipleGroups: Bool {
        groups.filter { !$0.isHiddenByDefault }.count > 1
    }

    /// 展开区要逐行列出的行：默认藏掉只出现在「未放置」「随从/召唤物」的行。
    /// 整卡都是这种行（只有打开开关才看得到的卡）时全部列出，免得展开后是空的。
    public func displayRows(includeHidden: Bool) -> [BossFight] {
        guard !includeHidden else { return rows }
        let shown = rows.filter { !$0.isHiddenByDefault }
        return shown.isEmpty ? rows : shown
    }

    /// 默认藏掉的行数（展开区底部写「另有 N 条……已隐藏」）。
    public func hiddenRowCount(includeHidden: Bool) -> Int {
        rows.count - displayRows(includeHidden: includeHidden).count
    }

    public init(
        id: String, kind: Kind? = nil, group: Group, groups: [Group]? = nil,
        roles: [String] = [], roleSearchTerms: [String] = [], tiers: [String] = [],
        nameZh: String, nameEn: String,
        expeditionZh: String, expeditionEn: String = "", variantNameZh: String,
        variantNameEn: String = "", isEverdark: Bool, weakness: [BossWeakness],
        descriptionZh: String, nameSource: String, nameInferred: Bool,
        nameApprox: Bool = false, nameNote: String = "", nameSourceUrl: String = "",
        nameZhFallback: String = "", nameZhFallbackNote: String = "",
        displayFallbackZh: String = "",
        nameEvidence: BossNameEvidence? = nil, nameZhRejected: BossNameEvidence? = nil,
        hidden: Bool = false, noReward: Bool = false, menuId: Int? = nil,
        chrIds: [Int] = [], npcNameId: Int? = nil, rows: [BossFight]
    ) {
        self.id = id
        self.kind = kind ?? (group == .nightlord ? .nightlord : .boss)
        self.group = group
        self.groups = groups ?? [group]
        self.roles = BossRoleCatalog.normalized(roles)
        self.tiers = tiers
        self.nameZh = nameZh
        self.nameEn = nameEn
        self.expeditionZh = expeditionZh
        self.expeditionEn = expeditionEn
        self.variantNameZh = variantNameZh
        self.variantNameEn = variantNameEn
        self.isEverdark = isEverdark
        self.weakness = weakness
        self.descriptionZh = descriptionZh
        self.nameSource = nameSource
        self.nameInferred = nameInferred
        self.nameApprox = nameApprox
        self.nameNote = nameNote
        self.nameSourceUrl = nameSourceUrl
        self.nameZhFallback = nameZhFallback
        self.nameZhFallbackNote = nameZhFallbackNote
        self.displayFallbackZh = displayFallbackZh
        self.nameEvidence = nameEvidence
        self.nameZhRejected = nameZhRejected
        self.hidden = hidden
        self.noReward = noReward
        self.menuId = menuId
        self.chrIds = chrIds
        self.npcNameId = npcNameId
        self.rows = rows
        // 搜索串的组成两端必须一致：中英文名 + 参考译名 + 占位名 + 远征名 + 变体名
        // + 官方弱点 + 每行标签 + 出场场合名（roleNames 的中英文）。
        // nameZhFallback 也算进来：用户就是照着「河马」「山妖」这些旧译名找的，
        // 搜不到等于名字改动把人挡在门外。displayFallbackZh 同理——它现在就写在卡头上，
        // 页面上看得见的名字必须搜得到。
        // schemaVersion 4：场合名写在卡头徽标上，「高塔」「突袭」「入侵者」都得搜得到
        // （它们合并在「其它场合」分组里，没有自己的筛选项）。合并分组的名字「其它场合」
        // 本身不是场合，不进；nameSource / threat / variantKey 这类内部枚举值同样不进。
        var parts = [
            nameZh, nameEn, nameZhFallback, displayFallbackZh,
            expeditionZh, expeditionEn, variantNameZh, variantNameEn,
        ]
        parts.append(contentsOf: weakness.map(\.display))
        parts.append(contentsOf: rows.map(\.displayLabel))
        parts.append(contentsOf: rows.map(\.labelEn))
        parts.append(contentsOf: roleSearchTerms)
        searchKey = bossFoldForSearch(parts.joined(separator: " "))

        // 行号单独收，且收录被合并掉的 npcIds（搜索框承诺的「或 npcId」）。
        var numbers: [String] = []
        var seen: Set<String> = []
        for text in rows.flatMap(\.npcIds).map(String.init)
            + chrIds.map(String.init)
            + (npcNameId.map { [String($0)] } ?? [])
        where seen.insert(text).inserted {
            numbers.append(text)
        }
        numberKeys = numbers
    }

    public func matches(foldedQuery: String) -> Bool {
        guard !foldedQuery.isEmpty else { return true }
        // 纯数字按行号前缀匹配：npcId / chrId 是 4～9 位数，contains 会让「1」「50」命中全表。
        if foldedQuery.allSatisfy(\.isNumber) {
            return numberKeys.contains { $0.hasPrefix(foldedQuery) }
        }
        return searchKey.contains(foldedQuery)
    }
}

/// 解码 + 分组 + 搜索索引，一次构建好交给视图。
public struct BossDataIndex: Sendable {
    public let dataset: BossDataset
    public let cards: [BossCard]

    public init(dataset: BossDataset) throws {
        self.dataset = dataset
        var cards: [BossCard] = []
        cards.reserveCapacity(dataset.nightlords.count + dataset.nightBosses.count)

        for lord in dataset.nightlords {
            cards.append(
                BossCard(
                    id: "nightlord-\(lord.menuId)",
                    kind: .nightlord,
                    group: .nightlord,
                    groups: [.nightlord],
                    roles: lord.roles,
                    roleSearchTerms: Self.roleSearchTerms(lord.roles, dataset: dataset),
                    nameZh: lord.nameZh,
                    nameEn: lord.nameEn,
                    expeditionZh: lord.expeditionZh,
                    expeditionEn: lord.expeditionEn,
                    variantNameZh: lord.variantNameZh,
                    variantNameEn: lord.variantNameEn,
                    isEverdark: lord.isEverdark,
                    weakness: lord.weakness,
                    descriptionZh: lord.descriptionZh,
                    nameSource: "",
                    nameInferred: false,
                    menuId: lord.menuId,
                    rows: lord.fights
                )
            )
        }

        for boss in dataset.nightBosses {
            let groups = Self.groups(forRoles: boss.roles)
            cards.append(
                BossCard(
                    id: "boss-\(boss.id)",
                    kind: .boss,
                    group: groups.first ?? .other,
                    groups: groups,
                    roles: boss.roles,
                    roleSearchTerms: Self.roleSearchTerms(boss.roles, dataset: dataset),
                    tiers: boss.tiers.isEmpty ? (boss.tier.isEmpty ? [] : [boss.tier]) : boss.tiers,
                    nameZh: boss.nameZh,
                    nameEn: boss.nameEn,
                    expeditionZh: "",
                    variantNameZh: "",
                    isEverdark: false,
                    weakness: [],
                    descriptionZh: "",
                    nameSource: boss.nameSource,
                    nameInferred: boss.nameInferred,
                    nameApprox: boss.nameApprox,
                    nameNote: boss.nameNote,
                    nameSourceUrl: boss.nameSourceUrl,
                    nameZhFallback: boss.nameZhFallback,
                    nameZhFallbackNote: boss.nameZhFallbackNote,
                    displayFallbackZh: boss.displayFallbackZh,
                    nameEvidence: boss.nameEvidence,
                    nameZhRejected: boss.nameZhRejected,
                    hidden: boss.hidden,
                    noReward: boss.noReward,
                    chrIds: boss.chrIds,
                    npcNameId: boss.npcNameId,
                    rows: boss.variants
                )
            )
        }

        guard !cards.isEmpty else { throw BossDataError.empty }
        self.cards = cards
    }

    public init(data: Data) throws {
        try self.init(dataset: BossDataset.decode(from: data))
    }

    /// 一组守夜 / 野外首领按 roles 归入哪些分组（按 `Group.allCases` 顺序、去重）。
    ///
    /// * 场合与分组的对应见 `BossCard.Group.forRole`；
    /// * 「夜王」分组只收夜王卡片：守夜 / 野外首领万一带了 nightlord 场合（当前数据没有），
    ///   归入「其它场合」，免得夜王分组混进非夜王；
    /// * 没有 roles（旧版数据集）时归「其它场合」，卡头写「出场场合：数据未内置」——
    ///   **不**退回 tier：tier 只是缩放档位，用它分组正是用户反馈的那个错。
    static func groups(forRoles roles: [String]) -> [BossCard.Group] {
        guard !roles.isEmpty else { return [.other] }
        let hit = Set(roles.map { role -> BossCard.Group in
            let group = BossCard.Group.forRole(role)
            return group == .nightlord ? .other : group
        })
        return BossCard.Group.allCases.filter { hit.contains($0) }
    }

    /// 搜索索引里的场合名：每个场合的中文名 + roleNames 的英文名。
    static func roleSearchTerms(_ roles: [String], dataset: BossDataset) -> [String] {
        roles.flatMap { role -> [String] in
            var terms = [dataset.roleTitle(role)]
            if let en = dataset.roleNames[role]?.en, !en.isEmpty { terms.append(en) }
            return terms
        }
    }

    /// 按分组返回卡片。`includeHidden = false`（默认）时：
    ///   * 「随从/召唤物」「未放置」两个分组整组不显示；
    ///   * 其余分组滤掉 `isHiddenByDefault` 的卡片（hidden 的非首领实体，
    ///     或全部场合都是那两个默认隐藏场合的组）。
    public func cards(in group: BossCard.Group, includeHidden: Bool = false) -> [BossCard] {
        if group.isHiddenByDefault && !includeHidden { return [] }
        return cards.filter { $0.belongs(to: group) && (includeHidden || !$0.isHiddenByDefault) }
    }

    /// 按分组返回过滤后的卡片；`query` 会自动折叠。
    public func cards(
        in group: BossCard.Group, query: String, includeHidden: Bool = false
    ) -> [BossCard] {
        let needle = bossFoldForSearch(query)
        return cards(in: group, includeHidden: includeHidden).filter { $0.matches(foldedQuery: needle) }
    }

    /// `hidden = true` 的组（召唤物 / 投射物等非首领实体）。
    public var hiddenCards: [BossCard] { cards.filter(\.hidden) }

    /// 默认不显示的全部卡片：hidden 的组 + 只出现在「未放置」「随从/召唤物」的组。
    public var hiddenByDefaultCards: [BossCard] { cards.filter(\.isHiddenByDefault) }

    /// 同时属于多个默认可见分组的组（一组首领多个出场场合）。
    public var multiGroupCards: [BossCard] { cards.filter(\.hasMultipleGroups) }

    /// 某个场合在分组视图里的卡片数（含隐藏）：守夜 / 野外首领里 roles 含它的组。
    /// 与数据集的 roleSummary 同口径（roleSummary 只数 nightBosses）。
    public func bossCardCount(role: String) -> Int {
        cards.filter { !$0.isNightlord && $0.roles.contains(role) }.count
    }

    public func permanentEffects(_ ids: [Int]) -> [BossPermanentEffect] {
        ids.compactMap { dataset.permanentEffect($0) }
    }

    /// 查不到明细的常驻缩放 SpEffect ID（页面要标成「缺少明细」）。
    public func missingPermanentEffectIDs(_ ids: [Int]) -> [Int] {
        ids.filter { dataset.permanentEffect($0) == nil }
    }

    /// 底部「缩放档位说明」用：按档位 ID 升序。
    public var scalingGroups: [BossScalingGroup] {
        dataset.scalingTiers.values.sorted { $0.id < $1.id }
    }

    /// 顶部胶囊与底部「收录」统计说的都是**数据集收录了多少**，因此一律含隐藏实体，
    /// 不跟着「显示隐藏实体」开关变；当前列表里有多少条由页脚的「当前显示 …」负责。
    public var summary: String {
        let lords = cards.filter(\.isNightlord).count
        let bosses = cards.count - lords
        let multi = multiGroupCards.count
        var text = "\(lords) 位夜王 · \(bosses) 组首领按出场场合分组"
        if multi > 0 { text += "（\(multi) 组属于多个场合）" }
        return text
    }

    /// 「数据版本与来源」区块里的收录统计：每个分组（含默认隐藏的两个）的卡片数，
    /// 措辞与 Windows 端 versionBlock 的「收录」一行一致。
    public var inventorySummary: String {
        let counts = BossCard.Group.allCases.map { "\($0.title) \(cards(in: $0, includeHidden: true).count)" }
        let multi = multiGroupCards.count
        let rows = cards.reduce(0) { $0 + $1.rows.count }
        var text = counts.joined(separator: " · ")
        if multi > 0 { text += "（含 \(multi) 组同时属于多个分组）" }
        text += " · 数值行 \(rows)"
        return text
    }

    /// 隐藏实体的说明（底部「数据说明」用）。没有默认隐藏的组时为 nil。
    public var hiddenSummary: String? {
        let flagged = hiddenCards
        let roleOnly = hiddenByDefaultCards.filter { !$0.hidden }
        guard !flagged.isEmpty || !roleOnly.isEmpty else { return nil }
        var parts: [String] = []
        if !flagged.isEmpty {
            parts.append(
                "\(flagged.count) 组被判定为非首领实体（\(flagged.map(\.displayName).joined(separator: "、"))），"
                    + "判据是整组不掉任何奖励，且不吃削韧 / 连社区资料都认不出 / 社区标为杂兵"
            )
        }
        if !roleOnly.isEmpty {
            parts.append(
                "\(roleOnly.count) 组只出现在「\(BossRoleText.groupUnplaced)」「\(BossRoleText.groupSummon)」"
                    + "两个场合（\(roleOnly.map(\.displayName).joined(separator: "、"))）"
            )
        }
        return "另有 " + parts.joined(separator: "；另有 ") + "。它们默认不在列表里，"
            + "展开区里只出现在这两个场合的数值行也默认隐藏；"
            + "需要时打开工具条的「\(BossRowText.hiddenToggleTitle)」，"
            + "分组筛选里会多出「\(BossRoleText.groupSummon)」「\(BossRoleText.groupUnplaced)」两项。"
    }
}
