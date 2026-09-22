import Foundation

// 「首领数据」页的数据模型与换算函数。
//
// 数据来源：Resources/bosses.json（bossesSchemaVersion = 2），经
// `GameDataLoader.dataIfAvailable(for: .bosses)` 读取原始 Data 后在这里解码。
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
    public var weakKinds: [BossDamageKind] {
        BossDamageKind.allCases.filter { value(for: $0) > 1 }
            .sorted { value(for: $0) > value(for: $1) }
    }

    /// 倍率 < 1 的属性（按倍率升序），即抗性。
    public var resistantKinds: [BossDamageKind] {
        BossDamageKind.allCases.filter { value(for: $0) < 1 }
            .sorted { value(for: $0) < value(for: $1) }
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

    /// 单人（不做任何人数缩放）。
    public static let identity = BossScalingTier(
        hp: 1, poiseTaken: 1, poiseRecover: 1, ailmentDamageRate: 1, poisonRate: 1, buildupRate: 1
    )

    public init(
        hp: Double, poiseTaken: Double, poiseRecover: Double,
        ailmentDamageRate: Double, poisonRate: Double, buildupRate: Double
    ) {
        self.hp = hp
        self.poiseTaken = poiseTaken
        self.poiseRecover = poiseRecover
        self.ailmentDamageRate = ailmentDamageRate
        self.poisonRate = poisonRate
        self.buildupRate = buildupRate
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        hp = container.bossDouble(.hp, default: 1)
        poiseTaken = container.bossDouble(.poiseTaken, default: 1)
        poiseRecover = container.bossDouble(.poiseRecover, default: 1)
        ailmentDamageRate = container.bossDouble(.ailmentDamageRate, default: 1)
        poisonRate = container.bossDouble(.poisonRate, default: 1)
        buildupRate = container.bossDouble(.buildupRate, default: 1)
    }
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
    public let id: Int
    public let group: String?
    public let duo: BossScalingTier?
    public let trio: BossScalingTier?

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
    /// true 表示只在「深夜」模式生效。
    public let deepOfNight: Bool

    private enum CodingKeys: String, CodingKey {
        case nameEn, nameZh, hp, poiseTaken, poiseRecover, ailmentDamageRate, deepOfNight
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
        deepOfNight = container.bossBool(.deepOfNight)
    }

    public init(
        id: Int, nameEn: String?, nameZh: String, hp: Double, poiseTaken: Double,
        poiseRecover: Double, ailmentDamageRate: Double, deepOfNight: Bool
    ) {
        self.id = id
        self.nameEn = nameEn
        self.nameZh = nameZh
        self.hp = hp
        self.poiseTaken = poiseTaken
        self.poiseRecover = poiseRecover
        self.ailmentDamageRate = ailmentDamageRate
        self.deepOfNight = deepOfNight
    }

    /// `permanentScaling` 的 key 才是 SpEffect ID，解码后补上。
    public func withID(_ id: Int) -> BossPermanentEffect {
        BossPermanentEffect(
            id: id, nameEn: nameEn, nameZh: nameZh, hp: hp, poiseTaken: poiseTaken,
            poiseRecover: poiseRecover, ailmentDamageRate: ailmentDamageRate, deepOfNight: deepOfNight
        )
    }

    public var displayName: String {
        if !nameZh.isEmpty { return nameZh }
        if let nameEn, !nameEn.isEmpty { return nameEn }
        return "常驻缩放 #\(id)"
    }
}

// MARK: - 战斗行（夜王 fight / 守夜·野外 variant 共用同一套数值字段）

/// 「深夜」模式下的同一组基准数值。
public struct BossDeepOfNightStats: Codable, Sendable, Hashable {
    public let hp: Int
    public let hpMultiplier: Double
    public let poiseTakenBase: Double
    public let poiseRecoverMultiplier: Double
    public let ailmentDamageRateBase: Double
    public let permScalingIds: [Int]

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        hp = container.bossInt(.hp, default: 0)
        hpMultiplier = container.bossDouble(.hpMultiplier, default: 1)
        poiseTakenBase = container.bossDouble(.poiseTakenBase, default: 1)
        poiseRecoverMultiplier = container.bossDouble(.poiseRecoverMultiplier, default: 1)
        ailmentDamageRateBase = container.bossDouble(.ailmentDamageRateBase, default: 1)
        permScalingIds = container.bossIntArray(.permScalingIds)
    }
}

/// 一条战斗记录换算到指定人数 / 模式后的结果。
public struct BossComputedStats: Sendable, Hashable {
    /// 玩家真正要打掉的血量。
    public let hp: Int
    /// 有效韧性 = poise / (poiseTakenBase × tier.poiseTaken)；nil 表示不吃削韧。
    public let effectivePoise: Double?
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

    public var id: Int { npcId }

    private enum CodingKeys: String, CodingKey {
        case npcId, npcIds, paramdexName, labelZh, labelEn, labelUncertain, isMain, threat
        case hp, hpBase, hpMultiplier, poise, poiseRecover, poiseTakenBase, poiseRecoverMultiplier
        case damageRates, ailmentDamageRateBase, resist, immune, permScalingIds
        case deepOfNight, scalingId, scaling
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
    }

    /// 显示用标签：labelZh 为空时依次回退 labelEn / paramdexName / npcId。
    public var displayLabel: String {
        if !labelZh.isEmpty { return labelZh }
        if !labelEn.isEmpty { return labelEn }
        if let paramdexName, !paramdexName.isEmpty { return paramdexName }
        return "行 \(npcId)"
    }

    /// 该行是否有「深夜」专属缩放；没有时深夜数值与常规相同。
    public var hasDeepOfNight: Bool { deepOfNight != nil }

    /// 该行威胁档位的短标签（守夜 / 野外）；夜王的 fight 没有 threat，返回 nil。
    /// 同一组首领可能同时有守夜与野外变体，逐行标出来才分得清。
    public var threatTitle: String? {
        guard let threat, !threat.isEmpty else { return nil }
        switch threat {
        case "night": return "守夜"
        case "field": return "野外"
        default: return threat
        }
    }

    public func immuneKinds() -> [BossAilmentKind] {
        let declared = Set(immune)
        let byFlag = BossAilmentKind.allCases.filter { declared.contains($0.rawValue) }
        return byFlag.isEmpty ? resist.immuneKinds : byFlag
    }

    // MARK: 换算

    /// 基准数值：深夜模式且该行有深夜专属缩放时改用深夜那一组。
    private func baseline(deepOfNight useDeep: Bool) -> (
        hp: Int, hpMultiplier: Double, poiseTakenBase: Double,
        poiseRecoverMultiplier: Double, ailmentDamageRateBase: Double, permScalingIds: [Int]
    ) {
        if useDeep, let deep = deepOfNight {
            return (deep.hp, deep.hpMultiplier, deep.poiseTakenBase,
                    deep.poiseRecoverMultiplier, deep.ailmentDamageRateBase, deep.permScalingIds)
        }
        return (hp, hpMultiplier, poiseTakenBase, poiseRecoverMultiplier, ailmentDamageRateBase, permScalingIds)
    }

    public func tier(for players: BossPartySize) -> BossScalingTier {
        scaling?.tier(for: players) ?? .identity
    }

    /// 指定人数下玩家要打掉的血量 = hp × 人数档血量倍率。
    public func hp(for players: BossPartySize, deepOfNight useDeep: Bool = false) -> Int {
        let base = baseline(deepOfNight: useDeep)
        let scaled = Double(base.hp) * tier(for: players).hp
        guard scaled.isFinite else { return base.hp }
        return Int(scaled.rounded())
    }

    /// 有效韧性 = poise / (poiseTakenBase × 人数档承受削韧倍率)；
    /// poise < 0（不吃削韧）或分母为 0 时返回 nil。
    public func effectivePoise(for players: BossPartySize, deepOfNight useDeep: Bool = false) -> Double? {
        guard poise >= 0 else { return nil }
        let base = baseline(deepOfNight: useDeep)
        let factor = base.poiseTakenBase * tier(for: players).poiseTaken
        guard factor > 0, factor.isFinite else { return nil }
        return poise / factor
    }

    /// 削韧恢复速度 = saRecoveryRate × 常驻恢复倍率 × 人数档恢复倍率。
    public func poiseRecoverSpeed(for players: BossPartySize, deepOfNight useDeep: Bool = false) -> Double {
        let base = baseline(deepOfNight: useDeep)
        return poiseRecover * base.poiseRecoverMultiplier * tier(for: players).poiseRecover
    }

    /// 异常发动伤害倍率。
    public func ailmentDamageRate(for players: BossPartySize, deepOfNight useDeep: Bool = false) -> Double {
        let base = baseline(deepOfNight: useDeep)
        return base.ailmentDamageRateBase * tier(for: players).ailmentDamageRate
    }

    /// Boss 承受的异常累积量倍率（越小越难打出异常）。
    public func ailmentBuildupRate(for players: BossPartySize) -> Double {
        tier(for: players).buildupRate
    }

    /// 一次算齐所有换算结果。
    public func stats(for players: BossPartySize, deepOfNight useDeep: Bool = false) -> BossComputedStats {
        let base = baseline(deepOfNight: useDeep)
        let tier = tier(for: players)
        return BossComputedStats(
            hp: hp(for: players, deepOfNight: useDeep),
            effectivePoise: effectivePoise(for: players, deepOfNight: useDeep),
            poiseRecover: poiseRecoverSpeed(for: players, deepOfNight: useDeep),
            ailmentDamageRate: ailmentDamageRate(for: players, deepOfNight: useDeep),
            ailmentBuildupRate: tier.buildupRate,
            poisonDamageRate: tier.poisonRate,
            tier: tier,
            permScalingIds: base.permScalingIds,
            hpMultiplier: base.hpMultiplier,
            poiseTakenBase: base.poiseTakenBase
        )
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

    public var id: Int { menuId }

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
    /// "night" | "field"。
    public let tier: String
    public let tiers: [String]
    public let variants: [BossFight]

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
    }
}

public struct BossNotes: Codable, Sendable {
    public let unmatchedNames: [BossUnmatchedName]

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        unmatchedNames = container.bossArray(.unmatchedNames)
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

    private enum CodingKeys: String, CodingKey {
        case schemaVersion = "bossesSchemaVersion"
        case gameVersion, dataVersion, generatedAt, sources, affinityNames
        case scalingTiers, permanentScaling, caveats, nightlords, nightBosses, notes
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
}

// MARK: - 页面用的统一卡片模型

/// 搜索折叠：与词条库一致（大小写 / 全半角 / 变音不敏感，去空格）。
public func bossFoldForSearch(_ text: String) -> String {
    text.foldedForSearch
}

public struct BossCard: Identifiable, Sendable, Hashable {
    public enum Group: String, CaseIterable, Identifiable, Sendable {
        case nightlord
        case night
        case field

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .nightlord: return "夜王"
            case .night: return "守夜首领"
            case .field: return "野外首领"
            }
        }

        public var symbol: String {
            switch self {
            case .nightlord: return "crown"
            case .night: return "moon.stars"
            case .field: return "map"
            }
        }
    }

    public let id: String
    /// 主分组：夜王，或该组首领的 `tier`。决定折叠态徽标顺序。
    public let group: Group
    /// 该卡片应出现在哪些分组筛选里。守夜 / 野外档位都有变体的组会同时属于两个分组，
    /// 来源是 `nightBosses.tiers`（而不是单值的 `tier`）。
    public let groups: [Group]
    public let nameZh: String
    public let nameEn: String
    /// 夜王远征名（守夜 / 野外为空）。
    public let expeditionZh: String
    /// 变体名：永夜之王 / 救世旗手（普通形态为空）。
    public let variantNameZh: String
    public let isEverdark: Bool
    /// 菜单参数标注的官方弱点。
    public let weakness: [BossWeakness]
    public let descriptionZh: String
    /// 守夜 / 野外首领的名字来源，"manual" 等表示不是游戏内文本。
    public let nameSource: String
    public let nameInferred: Bool
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

    public var displayName: String { nameZh.isEmpty ? nameEn : nameZh }

    /// 全部主战行。**`isMain` 不唯一**：多阶段 / 多体夜王（玛利斯·永夜之王、
    /// 救世旗手、格诺斯塔…）会有 2～5 条，折叠态必须把这件事说清楚。
    public var mainRows: [BossFight] { rows.filter(\.isMain) }

    /// 折叠态头条用的行：主战行里**血量最高**的一条（同血量取 npcId 较小者）；
    /// 没有主战行时取第一行（守夜 / 野外的 variants 已按 hp 降序排好）。
    /// 排序用 1 人基准血量，与当前人数 / 深夜开关无关，保证头条行不会跟着设置跳。
    public var primaryRow: BossFight? {
        let mains = mainRows
        guard !mains.isEmpty else { return rows.first }
        return mains.sorted { lhs, rhs in
            lhs.hp == rhs.hp ? lhs.npcId < rhs.npcId : lhs.hp > rhs.hp
        }.first
    }

    /// 主战行不止一条时，折叠态要并列展示全部主战血量。
    public var hasMultipleMainRows: Bool { mainRows.count > 1 }

    public func belongs(to group: Group) -> Bool { groups.contains(group) }

    public init(
        id: String, group: Group, groups: [Group]? = nil, nameZh: String, nameEn: String,
        expeditionZh: String, variantNameZh: String, isEverdark: Bool, weakness: [BossWeakness],
        descriptionZh: String, nameSource: String, nameInferred: Bool,
        chrIds: [Int] = [], npcNameId: Int? = nil, rows: [BossFight]
    ) {
        self.id = id
        self.group = group
        self.groups = groups ?? [group]
        self.nameZh = nameZh
        self.nameEn = nameEn
        self.expeditionZh = expeditionZh
        self.variantNameZh = variantNameZh
        self.isEverdark = isEverdark
        self.weakness = weakness
        self.descriptionZh = descriptionZh
        self.nameSource = nameSource
        self.nameInferred = nameInferred
        self.chrIds = chrIds
        self.npcNameId = npcNameId
        self.rows = rows
        // 分组名不进搜索串：分组已有独立筛选器，混进来会让「野外」命中全部野外卡。
        var parts = [nameZh, nameEn, expeditionZh, variantNameZh]
        parts.append(contentsOf: weakness.map(\.display))
        parts.append(contentsOf: rows.map(\.displayLabel))
        parts.append(contentsOf: rows.map(\.labelEn))
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
                    group: .nightlord,
                    nameZh: lord.nameZh,
                    nameEn: lord.nameEn,
                    expeditionZh: lord.expeditionZh,
                    variantNameZh: lord.variantNameZh,
                    isEverdark: lord.isEverdark,
                    weakness: lord.weakness,
                    descriptionZh: lord.descriptionZh,
                    nameSource: "",
                    nameInferred: false,
                    rows: lord.fights
                )
            )
        }

        for boss in dataset.nightBosses {
            let primary: BossCard.Group = boss.tier == "night" ? .night : .field
            cards.append(
                BossCard(
                    id: "boss-\(boss.id)",
                    group: primary,
                    groups: Self.groups(for: boss, primary: primary),
                    nameZh: boss.nameZh,
                    nameEn: boss.nameEn,
                    expeditionZh: "",
                    variantNameZh: "",
                    isEverdark: false,
                    weakness: [],
                    descriptionZh: "",
                    nameSource: boss.nameSource,
                    nameInferred: boss.nameInferred,
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

    /// 一组守夜 / 野外首领应归入哪些分组：按 `tiers`（可能同时含 field 与 night），
    /// 缺失时退回单值的 `tier`。主分组排在最前。
    static func groups(for boss: BossNightBoss, primary: BossCard.Group) -> [BossCard.Group] {
        let declared = Set(boss.tiers)
        var result: [BossCard.Group] = []
        if declared.contains("night") { result.append(.night) }
        if declared.contains("field") { result.append(.field) }
        if result.isEmpty { return [primary] }
        if let index = result.firstIndex(of: primary), index != 0 {
            result.remove(at: index)
            result.insert(primary, at: 0)
        }
        return result
    }

    public func cards(in group: BossCard.Group) -> [BossCard] {
        cards.filter { $0.belongs(to: group) }
    }

    /// 按分组返回过滤后的卡片；`query` 会自动折叠。
    public func cards(in group: BossCard.Group, query: String) -> [BossCard] {
        let needle = bossFoldForSearch(query)
        return cards.filter { $0.belongs(to: group) && $0.matches(foldedQuery: needle) }
    }

    /// 同时有守夜与野外变体的组：在两个分组筛选下都能找到。
    public var dualTierCards: [BossCard] {
        cards.filter { $0.belongs(to: .night) && $0.belongs(to: .field) }
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

    public var summary: String {
        let lords = cards(in: .nightlord).count
        let night = cards(in: .night).count
        let field = cards(in: .field).count
        let dual = dualTierCards.count
        var text = "\(lords) 位夜王 · \(night) 个守夜首领 · \(field) 个野外首领"
        if dual > 0 { text += "（其中 \(dual) 组两种档位都有）" }
        return text
    }
}
