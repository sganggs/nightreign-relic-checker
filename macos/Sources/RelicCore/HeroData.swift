import Foundation

// 「角色属性」页的数据模型与换算函数。
//
// 数据来源：Resources/heroes.json（schemaVersion = 1，datasetId = "heroes"），经
// `GameDataLoader.dataIfAvailable(for: .heroes)` 读取原始 Data 后在这里解码。
//
// 解码原则（数据集由另一条流水线维护，字段随时可能增删）：
//   * 未知字段一律忽略；
//   * 已知字段缺失、类型不符时退回默认值，**不抛错**；
//   * 数组 / 字典逐元素解码，坏元素跳过而不是整份失败。
// 只有「顶层不是 JSON 对象」「一个角色都没有」这种读不懂的情况才抛 `HeroDataError`。
//
// 纯逻辑（派生值插值、修饰叠加、钳位、对比表排序）全部放在本文件，UI 只做展示，
// 自检（RelicCoreChecks/HeroStatsChecks.swift）直接断言这里的函数。

// MARK: - 错误

public enum HeroDataError: LocalizedError {
    case notAnObject
    /// 其他解码失败（JSON 截断 / 编码损坏 / 字段结构彻底对不上），带上原始错误说明。
    case undecodable(String)
    case empty

    public var errorDescription: String? {
        switch self {
        case .notAnObject: return "角色属性数据不是合法的 JSON 对象"
        case .undecodable(let detail): return "角色属性数据无法解码：" + detail
        case .empty: return "角色属性数据里没有任何角色记录"
        }
    }
}

// MARK: - 宽容解码辅助

/// 逐元素解码用的包装：单个元素解不出来时置 nil，由调用方过滤掉。
struct HeroFailable<T: Decodable>: Decodable {
    let value: T?

    init(from decoder: Decoder) throws {
        value = try? T(from: decoder)
    }
}

extension KeyedDecodingContainer {
    func heroInt(_ key: Key, default fallback: Int) -> Int {
        if let value = try? decodeIfPresent(Int.self, forKey: key) { return value }
        if let value = try? decodeIfPresent(Double.self, forKey: key), value.isFinite {
            return Int(value.rounded())
        }
        if let text = try? decodeIfPresent(String.self, forKey: key), let value = Int(text) { return value }
        return fallback
    }

    func heroString(_ key: Key, default fallback: String = "") -> String {
        if let value = try? decodeIfPresent(String.self, forKey: key) { return value }
        if let value = try? decodeIfPresent(Int.self, forKey: key) { return String(value) }
        return fallback
    }

    func heroBool(_ key: Key, default fallback: Bool = false) -> Bool {
        if let value = try? decodeIfPresent(Bool.self, forKey: key) { return value }
        if let value = try? decodeIfPresent(Int.self, forKey: key) { return value != 0 }
        return fallback
    }

    /// 逐元素宽容解码；键缺失或不是数组时返回空数组。
    func heroArray<T: Decodable>(_ key: Key) -> [T] {
        guard let wrapped = try? decodeIfPresent([HeroFailable<T>].self, forKey: key) else { return [] }
        return wrapped.compactMap(\.value)
    }

    func heroStringArray(_ key: Key) -> [String] {
        heroArray(key)
    }

    func heroDoubleArray(_ key: Key) -> [Double] {
        let numbers: [Double] = heroArray(key)
        return numbers
    }

    func heroIntArray(_ key: Key) -> [Int] {
        let numbers: [Double] = heroArray(key)
        return numbers.map { Int($0.rounded()) }
    }

    /// 逐值宽容解码的字典；键缺失或不是对象时返回空字典。
    func heroDictionary<T: Decodable>(_ key: Key) -> [String: T] {
        guard let wrapped = try? decodeIfPresent([String: HeroFailable<T>].self, forKey: key) else { return [:] }
        return wrapped.compactMapValues(\.value)
    }

    /// 属性 / 增减量字典：值可能写成浮点，一律取整。
    func heroIntDictionary(_ key: Key) -> [String: Int] {
        let numbers: [String: Double] = heroDictionary(key)
        return numbers.mapValues { Int($0.rounded()) }
    }

    func heroDoubleDictionary(_ key: Key) -> [String: Double] {
        heroDictionary(key)
    }
}

// MARK: - 属性名

/// 数据集 `statNames.attributes[]` 的一项。中文名一律以数据集为准，不在代码里硬编码。
public struct HeroStatName: Codable, Sendable, Hashable, Identifiable {
    public let key: String
    public let zh: String
    public let en: String

    public var id: String { key }
    public var display: String { zh.isEmpty ? en : zh }

    public init(key: String, zh: String, en: String) {
        self.key = key
        self.zh = zh
        self.en = en
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        key = container.heroString(.key)
        zh = container.heroString(.zh)
        en = container.heroString(.en)
    }
}

/// 数据集 `statNames.derived[]` 的一项：派生值 + 它依赖的属性与 CalcCorrectGraph 行号。
public struct HeroDerivedName: Codable, Sendable, Hashable, Identifiable {
    public let key: String
    public let zh: String
    public let en: String
    public let fromStat: String
    public let graphId: Int
    /// 游戏内有对应 UI 标签（血量 / 专注值 / 精力有，负重上限没有）。
    public let inGameLabel: Bool
    /// 结果必为整数（血量 / 专注值 / 精力）；负重上限带指数，保留 1 位小数。
    public let integer: Bool

    public var id: String { key }
    public var display: String { zh.isEmpty ? en : zh }

    public init(key: String, zh: String, en: String, fromStat: String, graphId: Int, inGameLabel: Bool, integer: Bool) {
        self.key = key
        self.zh = zh
        self.en = en
        self.fromStat = fromStat
        self.graphId = graphId
        self.inGameLabel = inGameLabel
        self.integer = integer
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        key = container.heroString(.key)
        zh = container.heroString(.zh)
        en = container.heroString(.en)
        fromStat = container.heroString(.fromStat)
        graphId = container.heroInt(.graphId, default: 0)
        inGameLabel = container.heroBool(.inGameLabel, default: true)
        integer = container.heroBool(.integer, default: true)
    }
}

/// 属性 / 派生值的中文名与展示顺序。
public struct HeroStatNames: Codable, Sendable, Hashable {
    public let attributeOrder: [String]
    public let derivedOrder: [String]
    public let attributes: [HeroStatName]
    public let derived: [HeroDerivedName]

    public init(attributeOrder: [String], derivedOrder: [String], attributes: [HeroStatName], derived: [HeroDerivedName]) {
        self.attributeOrder = attributeOrder
        self.derivedOrder = derivedOrder
        self.attributes = attributes
        self.derived = derived
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        attributeOrder = container.heroStringArray(.attributeOrder)
        derivedOrder = container.heroStringArray(.derivedOrder)
        attributes = container.heroArray(.attributes)
        derived = container.heroArray(.derived)
    }

    /// 按 `attributeOrder` 排好的 8 项属性；顺序表缺失时退回数组自身顺序。
    public var orderedAttributes: [HeroStatName] {
        guard !attributeOrder.isEmpty else { return attributes }
        let byKey = Dictionary(attributes.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
        var result = attributeOrder.compactMap { byKey[$0] }
        for attribute in attributes where !attributeOrder.contains(attribute.key) {
            result.append(attribute)
        }
        return result
    }

    /// 按 `derivedOrder` 排好的派生值。
    public var orderedDerived: [HeroDerivedName] {
        guard !derivedOrder.isEmpty else { return derived }
        let byKey = Dictionary(derived.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
        var result = derivedOrder.compactMap { byKey[$0] }
        for item in derived where !derivedOrder.contains(item.key) {
            result.append(item)
        }
        return result
    }

    public var attributeKeys: [String] { orderedAttributes.map(\.key) }
    public var derivedKeys: [String] { orderedDerived.map(\.key) }

    /// 属性中文名；数据集没有这一项时原样回显 key（页面不硬编码中文名）。
    public func attributeTitle(_ key: String) -> String {
        orderedAttributes.first { $0.key == key }?.display ?? key
    }

    public func derivedTitle(_ key: String) -> String {
        orderedDerived.first { $0.key == key }?.display ?? key
    }

    public func derivedEntry(_ key: String) -> HeroDerivedName? {
        derived.first { $0.key == key }
    }

    public var isEmpty: Bool { attributes.isEmpty && derived.isEmpty }
}

// MARK: - CalcCorrectGraph

/// 派生值换算表（CalcCorrectGraph 的一行）。
///
/// 求值规则与《艾尔登法环》通用公式一致：落在第 i 段 [stageMaxVal[i], stageMaxVal[i+1]]
/// 时，用 `adjPt[i]`（下段下标）作指数；`adjPt == 1` 即纯线性。
public struct HeroGrowthGraph: Codable, Sendable, Hashable, Identifiable {
    public let id: Int
    public let name: String
    public let stageMaxVal: [Double]
    public let stageMaxGrowVal: [Double]
    public let adjPt: [Double]
    public let linear: Bool
    public let usedFor: [String]

    public init(
        id: Int, name: String, stageMaxVal: [Double], stageMaxGrowVal: [Double],
        adjPt: [Double], linear: Bool, usedFor: [String]
    ) {
        self.id = id
        self.name = name
        self.stageMaxVal = stageMaxVal
        self.stageMaxGrowVal = stageMaxGrowVal
        self.adjPt = adjPt
        self.linear = linear
        self.usedFor = usedFor
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = container.heroInt(.id, default: 0)
        name = container.heroString(.name)
        stageMaxVal = container.heroDoubleArray(.stageMaxVal)
        stageMaxGrowVal = container.heroDoubleArray(.stageMaxGrowVal)
        adjPt = container.heroDoubleArray(.adjPt)
        let stages = stageMaxVal.count
        linear = container.heroBool(.linear, default: adjPt.allSatisfy { $0 == 1 } && stages > 0)
        usedFor = container.heroStringArray(.usedFor)
    }

    /// 至少两段、三个数组等长才能求值。
    public var isUsable: Bool {
        stageMaxVal.count >= 2
            && stageMaxGrowVal.count == stageMaxVal.count
            && adjPt.count == stageMaxVal.count
    }

    /// value 落在哪一段（返回下段下标 i，区间 [x[i], x[i+1]]）。
    func segmentIndex(for value: Double) -> Int {
        let last = stageMaxVal.count - 2
        guard last >= 0 else { return 0 }
        for index in 0...last where value <= stageMaxVal[index + 1] {
            return index
        }
        return last
    }

    /// 浮点求值：负重上限（带指数的 220）用这个。
    public func value(at stat: Int) -> Double {
        guard isUsable else { return 0 }
        let value = Double(stat)
        guard let firstX = stageMaxVal.first, let lastX = stageMaxVal.last,
              let firstY = stageMaxGrowVal.first, let lastY = stageMaxGrowVal.last else { return 0 }
        if value <= firstX { return firstY }
        if value >= lastX { return lastY }
        let index = segmentIndex(for: value)
        let x0 = stageMaxVal[index], x1 = stageMaxVal[index + 1]
        let y0 = stageMaxGrowVal[index], y1 = stageMaxGrowVal[index + 1]
        guard x1 > x0 else { return y0 }
        let adjustment = adjPt[index]
        if adjustment == 1 {
            return y0 + (y1 - y0) * (value - x0) / (x1 - x0)
        }
        let ratio = (value - x0) / (x1 - x0)
        let growth = adjustment > 0 ? pow(ratio, adjustment) : 1 - pow(1 - ratio, abs(adjustment))
        return y0 + (y1 - y0) * growth
    }

    /// 整数求值（向下取整）。
    ///
    /// 血量 / 专注值 / 精力所在的 100 / 101 / 104 三行端点都是整数且 adjPt 全为 1，
    /// 这里用整数除法精确算 floor，避免浮点误差把 240 变成 239。
    public func integerValue(at stat: Int) -> Int {
        guard isUsable else { return 0 }
        let input = Double(stat)
        guard let firstX = stageMaxVal.first, let lastX = stageMaxVal.last,
              let firstY = stageMaxGrowVal.first, let lastY = stageMaxGrowVal.last else { return 0 }
        if input <= firstX { return Int(firstY.rounded(.down)) }
        if input >= lastX { return Int(lastY.rounded(.down)) }
        let index = segmentIndex(for: input)
        let x0 = stageMaxVal[index], x1 = stageMaxVal[index + 1]
        let y0 = stageMaxGrowVal[index], y1 = stageMaxGrowVal[index + 1]
        guard x1 > x0 else { return Int(y0.rounded(.down)) }
        if adjPt[index] == 1,
           x0 == x0.rounded(), x1 == x1.rounded(), y0 == y0.rounded(), y1 == y1.rounded() {
            let numerator = (Int(y1) - Int(y0)) * (stat - Int(x0))
            let denominator = Int(x1) - Int(x0)
            return Int(y0) + HeroStatsMath.floorDivide(numerator, denominator)
        }
        // 端点不是整数 / 这一段带指数时退回浮点：先抹掉 1e-9 以下的尾巴再 floor，
        // 否则 239.99999999 会被取成 239。与 Windows 端 normalize() 同一口径。
        return Int(HeroStatsMath.normalize(value(at: stat)).rounded(.down))
    }
}

// MARK: - 纯换算

public enum HeroStatsMath {
    /// 属性下限：转职遗物把某项减到 0 或负数时钳到 1。
    public static let minimumStat = 1

    /// 向下取整的整数除法（Swift 的 / 是向零取整）。
    public static func floorDivide(_ numerator: Int, _ denominator: Int) -> Int {
        guard denominator != 0 else { return 0 }
        let quotient = numerator / denominator
        let remainder = numerator % denominator
        if remainder != 0 && ((remainder < 0) != (denominator < 0)) { return quotient - 1 }
        return quotient
    }

    /// 浮点噪声归一：CalcCorrectGraph 的分段斜率都是有理数，真值离整数至少 0.01，
    /// 先抹掉 1e-9 以下的尾巴再 floor，结果与整数精确运算逐格一致。
    /// Windows 端 `normalize()` 是同一条公式，两端的取整边界因此不会漂。
    public static func normalize(_ value: Double) -> Double {
        guard value.isFinite else { return value }
        return (value * 1e9).rounded() / 1e9
    }

    /// 保留若干位小数（四舍五入、远离零），负重上限用 1 位。
    public static func round(_ value: Double, digits: Int) -> Double {
        guard digits >= 0, value.isFinite else { return value }
        let scale = pow(10.0, Double(digits))
        return (value * scale).rounded() / scale
    }

    /// 一整套属性的派生值：每项派生值只吃一项属性（血量←生命力、专注值←集中力、
    /// 精力 / 负重上限←耐力），走各自的 CalcCorrectGraph 分段线性插值。
    /// 整数项向下取整，负重上限保留 1 位小数。
    public static func derivedValues(
        for stats: [String: Int],
        names: HeroStatNames,
        graphs: [Int: HeroGrowthGraph]
    ) -> [String: Double] {
        var result: [String: Double] = [:]
        for entry in names.orderedDerived {
            guard let graph = graphs[entry.graphId], graph.isUsable else { continue }
            guard let source = stats[entry.fromStat] else { continue }
            if entry.integer {
                result[entry.key] = Double(graph.integerValue(at: source))
            } else {
                result[entry.key] = round(graph.value(at: source), digits: 1)
            }
        }
        return result
    }

    /// 把若干条转职遗物的增减量叠加到基础属性上。
    ///
    /// 多条词条同时生效时增减量直接相加；结果小于 1 的属性钳到 1，并在
    /// `clamped` 里列出被钳的属性（页面要注明），`clampedFrom` 保留钳位前的原值
    /// （页面上写「原为 0，已钳到最低 1」要用）。
    ///
    /// `order` 是页面上的属性展示顺序（8 项）：`clamped` 按它排，页面的钳位汇总
    /// 才与属性卡片同序。缺省（纯函数测试直接调用时）退回 key 字典序。
    public static func apply(
        deltas: [[String: Int]],
        to base: [String: Int],
        order: [String] = []
    ) -> (stats: [String: Int], requested: [String: Int], clamped: [String], clampedFrom: [String: Int]) {
        var requested: [String: Int] = [:]
        for delta in deltas {
            for (key, value) in delta {
                requested[key, default: 0] += value
            }
        }
        var stats = base
        var clampedFrom: [String: Int] = [:]
        for (key, change) in requested {
            // 基础表里根本没有这一项时不编一个数字出来：页面显示破折号，也不记钳位
            // （0 是真实数值，破折号才是「没有」）。Windows 端 applyDeltas 同一条。
            guard let baseValue = base[key] else { continue }
            let raw = baseValue + change
            if raw < minimumStat {
                stats[key] = minimumStat
                clampedFrom[key] = raw
            } else {
                stats[key] = raw
            }
        }
        var clamped = order.filter { clampedFrom[$0] != nil }
        for key in clampedFrom.keys.sorted() where !clamped.contains(key) {
            clamped.append(key)
        }
        return (stats, requested, clamped, clampedFrom)
    }
}

// MARK: - 角色 / 等级

/// 参数表里真实存在的一行（Level 1 / 2 / 12 / 15）。
public struct HeroAnchorRow: Codable, Sendable, Hashable {
    public let level: Int
    public let rowId: Int
    public let rowName: String
    public let stats: [String: Int]

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        level = container.heroInt(.level, default: 0)
        rowId = container.heroInt(.rowId, default: 0)
        rowName = container.heroString(.rowName)
        stats = container.heroIntDictionary(.stats)
    }
}

/// 一个等级的完整属性行。
public struct HeroLevelRow: Codable, Sendable, Hashable, Identifiable {
    public let level: Int
    /// 参数表锚点（1 / 2 / 12 / 15），其余等级是插值推算。
    public let isAnchor: Bool
    public let stats: [String: Int]
    public let derived: [String: Double]
    public let abilityReinforce: Int

    public var id: Int { level }

    public init(level: Int, isAnchor: Bool, stats: [String: Int], derived: [String: Double], abilityReinforce: Int = 0) {
        self.level = level
        self.isAnchor = isAnchor
        self.stats = stats
        self.derived = derived
        self.abilityReinforce = abilityReinforce
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        level = container.heroInt(.level, default: 0)
        isAnchor = container.heroBool(.isAnchor)
        stats = container.heroIntDictionary(.stats)
        derived = container.heroDoubleDictionary(.derived)
        abilityReinforce = container.heroInt(.abilityReinforce, default: max(0, container.heroInt(.level, default: 1) - 1))
    }
}

/// 一位渡夜者。
public struct HeroEntry: Codable, Sendable, Hashable, Identifiable {
    public let id: Int
    public let key: String
    public let nameZh: String
    public let nameEn: String
    public let heroStatusParamId: Int
    public let anchors: [HeroAnchorRow]
    public let levels: [HeroLevelRow]

    public var display: String { nameZh.isEmpty ? nameEn : nameZh }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = container.heroInt(.id, default: 0)
        key = container.heroString(.key)
        nameZh = container.heroString(.nameZh)
        nameEn = container.heroString(.nameEn)
        heroStatusParamId = container.heroInt(.heroStatusParamId, default: 0)
        anchors = container.heroArray(.anchors)
        levels = container.heroArray(.levels).sorted { $0.level < $1.level }
    }

    public func level(_ level: Int) -> HeroLevelRow? {
        levels.first { $0.level == level }
    }

    public var maxLevel: Int { levels.map(\.level).max() ?? 0 }
    public var anchorLevels: [Int] { levels.filter(\.isAnchor).map(\.level) }
}

// MARK: - 转职遗物词条

/// 携带某条转职词条的遗物。
public struct HeroRelicItem: Codable, Sendable, Hashable, Identifiable {
    public let id: Int
    public let nameZh: String
    public let nameEn: String
    public let color: Int
    public let colorZh: String
    public let colorEn: String
    public let deep: Bool

    public var display: String { nameZh.isEmpty ? nameEn : nameZh }

    /// 颜色文案。数据集给的 `colorZh` 是「红 / 蓝 / 黄 / 绿」，而遗物卡 / 报告 / CSV
    /// （`relicColorLabel` + `SaveScanReport.AuditedRelic.colorText`）统一用「红色 / 蓝色 / …」，
    /// 这里跟着走同一份口径，避免同一个颜色在两个页面上写法不同。
    public var colorText: String {
        switch color {
        case 0...4: return relicColorLabel(color) + "色"
        default: return colorZh.isEmpty ? (colorEn.isEmpty ? "颜色未知" : colorEn) : colorZh
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = container.heroInt(.id, default: 0)
        nameZh = container.heroString(.nameZh)
        nameEn = container.heroString(.nameEn)
        color = container.heroInt(.color, default: -1)
        colorZh = container.heroString(.colorZh)
        colorEn = container.heroString(.colorEn)
        deep = container.heroBool(.deep)
    }
}

/// 转职词条某一级的增减量。
public struct HeroModifierLevel: Codable, Sendable, Hashable, Identifiable {
    public let level: Int
    /// 参数表锚点（1 / 12）。
    public let isAnchor: Bool
    /// 非锚点等级（2–11 插值、13–15 沿用 12 级）都是推算值。
    public let inferred: Bool
    public let delta: [String: Int]
    /// 取整方向换成 floor 时结果不同的属性（只含不同的项）。
    public let deltaFloorAlt: [String: Int]

    public var id: Int { level }

    public init(level: Int, isAnchor: Bool, inferred: Bool, delta: [String: Int], deltaFloorAlt: [String: Int] = [:]) {
        self.level = level
        self.isAnchor = isAnchor
        self.inferred = inferred
        self.delta = delta
        self.deltaFloorAlt = deltaFloorAlt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        level = container.heroInt(.level, default: 0)
        isAnchor = container.heroBool(.isAnchor)
        inferred = container.heroBool(.inferred, default: !container.heroBool(.isAnchor))
        delta = container.heroIntDictionary(.delta)
        deltaFloorAlt = container.heroIntDictionary(.deltaFloorAlt)
    }
}

/// 一条转职遗物词条（每个角色 2 条）。
public struct HeroStatModifier: Codable, Sendable, Hashable, Identifiable {
    public let affixId: Int
    public let nameZh: String
    public let nameEn: String
    public let heroId: Int
    public let heroKey: String
    public let heroNameZh: String
    public let affectedStats: [String]
    public let anchors: [HeroModifierAnchor]
    public let levels: [HeroModifierLevel]
    public let relicItems: [HeroRelicItem]
    public let rollablePoolIds: [Int]
    /// 只靠 DLC 权重才掉得出来的词条（全库 4 条）。
    public let dlcOnly: Bool

    public var id: Int { affixId }
    public var display: String { nameZh.isEmpty ? nameEn : nameZh }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        affixId = container.heroInt(.affixId, default: 0)
        nameZh = container.heroString(.nameZh)
        nameEn = container.heroString(.nameEn)
        heroId = container.heroInt(.heroId, default: 0)
        heroKey = container.heroString(.heroKey)
        heroNameZh = container.heroString(.heroNameZh)
        affectedStats = container.heroStringArray(.affectedStats)
        anchors = container.heroArray(.anchors)
        levels = container.heroArray(.levels).sorted { $0.level < $1.level }
        relicItems = container.heroArray(.relicItems)
        rollablePoolIds = container.heroIntArray(.rollablePoolIds)
        dlcOnly = container.heroBool(.dlcOnly)
    }

    public func level(_ level: Int) -> HeroModifierLevel? {
        levels.first { $0.level == level }
    }

    /// 词条名去掉开头的「【角色】」，页面在角色卡片下展示时不必重复角色名。
    public var shortName: String {
        guard nameZh.hasPrefix("【"), let end = nameZh.firstIndex(of: "】") else { return display }
        return String(nameZh[nameZh.index(after: end)...])
    }
}

/// 转职词条的参数锚点行（Level 1 / 12）。
public struct HeroModifierAnchor: Codable, Sendable, Hashable {
    public let level: Int
    public let rowId: Int
    public let rowName: String
    public let delta: [String: Int]

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        level = container.heroInt(.level, default: 0)
        rowId = container.heroInt(.rowId, default: 0)
        rowName = container.heroString(.rowName)
        delta = container.heroIntDictionary(.delta)
    }
}

// MARK: - 利普拉的交易

/// 利普拉的交易（5 套整表替换，不分角色）。
public struct HeroLibraRespec: Codable, Sendable, Hashable, Identifiable {
    public let key: String
    public let nameZh: String
    public let nameEn: String
    public let effectNameZh: String
    public let effectInfoZh: String
    /// 游戏里真正能看到的逐笔文案（对话选项），页面优先展示这一条。
    public let dealLineZh: String
    public let statKey: String
    public let statNameZh: String
    public let heroStatusId: Int
    public let anchors: [HeroAnchorRow]
    public let levels: [HeroLevelRow]

    public var id: String { key }
    public var display: String { dealLineZh.isEmpty ? (nameZh.isEmpty ? nameEn : nameZh) : dealLineZh }
    /// 下拉里的短标签：用属性名（力气 / 灵巧 / 智力 / 信仰 / 感应）。
    public var shortTitle: String { statNameZh.isEmpty ? (nameZh.isEmpty ? key : nameZh) : statNameZh }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        key = container.heroString(.key)
        nameZh = container.heroString(.nameZh)
        nameEn = container.heroString(.nameEn)
        effectNameZh = container.heroString(.effectNameZh)
        effectInfoZh = container.heroString(.effectInfoZh)
        dealLineZh = container.heroString(.dealLineZh)
        statKey = container.heroString(.statKey)
        statNameZh = container.heroString(.statNameZh)
        heroStatusId = container.heroInt(.heroStatusId, default: 0)
        anchors = container.heroArray(.anchors)
        levels = container.heroArray(.levels).sorted { $0.level < $1.level }
    }

    public func level(_ level: Int) -> HeroLevelRow? {
        levels.first { $0.level == level }
    }
}

// MARK: - 说明 / 出处

public struct HeroSource: Codable, Sendable, Hashable {
    public let name: String
    public let url: String
    public let revision: String
    public let license: String
    public let usage: String

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = container.heroString(.name)
        url = container.heroString(.url)
        revision = container.heroString(.revision)
        license = container.heroString(.license)
        usage = container.heroString(.usage)
    }
}

public struct HeroCrossCheckMismatch: Codable, Sendable, Hashable {
    public let level: Int
    public let field: String
    public let external: Int
    public let ours: Int

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        level = container.heroInt(.level, default: 0)
        field = container.heroString(.field)
        external = container.heroInt(.external, default: 0)
        ours = container.heroInt(.ours, default: 0)
    }
}

/// 与外部 wiki 的逐格对照结果。
public struct HeroCrossCheck: Codable, Sendable, Hashable, Identifiable {
    public let heroKey: String
    public let heroNameZh: String
    public let cellsCompared: Int
    public let mismatchCount: Int
    public let mismatches: [HeroCrossCheckMismatch]
    /// 差异以哪一边为准（当前数据集一律是 "params"，页面据此写「本页以参数为准」）。
    public let authoritative: String
    public let note: String

    public var id: String { heroKey }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        heroKey = container.heroString(.heroKey)
        heroNameZh = container.heroString(.heroNameZh)
        cellsCompared = container.heroInt(.cellsCompared, default: 0)
        mismatchCount = container.heroInt(.mismatchCount, default: 0)
        mismatches = container.heroArray(.mismatches)
        authoritative = container.heroString(.authoritative)
        note = container.heroString(.note)
    }
}

/// 底部折叠区要逐条展示的一段说明。
public struct HeroNote: Sendable, Hashable, Identifiable {
    public let title: String
    public let text: String

    public var id: String { title }

    public init(title: String, text: String) {
        self.title = title
        self.text = text
    }
}

/// 插值 / 验证口径。
public struct HeroInterpolation: Codable, Sendable, Hashable {
    /// 整段 interpolation 缺失时的兜底（全部字段留空，页面据此不显示任何说明）。
    public static let empty = HeroInterpolation()

    public init(
        baseAnchorLevels: [Int] = [], modifierAnchorLevels: [Int] = [], maxLevel: Int = 0,
        baseRule: String = "", baseRounding: String = "", baseVerified: Bool = false,
        baseVerification: String = "", derivedRule: String = "", modifierRule: String = "",
        modifierRounding: String = "", modifierVerified: Bool = false, modifierVerifiedNote: String = "",
        modifierAnchorVerified: Bool = false, modifierAnchorVerification: String = "",
        modifierMidLevelsVerified: Bool = false, modifierInference: String = "", libraRule: String = ""
    ) {
        self.baseAnchorLevels = baseAnchorLevels
        self.modifierAnchorLevels = modifierAnchorLevels
        self.maxLevel = maxLevel
        self.baseRule = baseRule
        self.baseRounding = baseRounding
        self.baseVerified = baseVerified
        self.baseVerification = baseVerification
        self.derivedRule = derivedRule
        self.modifierRule = modifierRule
        self.modifierRounding = modifierRounding
        self.modifierVerified = modifierVerified
        self.modifierVerifiedNote = modifierVerifiedNote
        self.modifierAnchorVerified = modifierAnchorVerified
        self.modifierAnchorVerification = modifierAnchorVerification
        self.modifierMidLevelsVerified = modifierMidLevelsVerified
        self.modifierInference = modifierInference
        self.libraRule = libraRule
    }

    public let baseAnchorLevels: [Int]
    public let modifierAnchorLevels: [Int]
    public let maxLevel: Int
    public let baseRule: String
    public let baseRounding: String
    public let baseVerified: Bool
    public let baseVerification: String
    public let derivedRule: String
    public let modifierRule: String
    public let modifierRounding: String
    /// 兼容字段：等于 `modifierMidLevelsVerified` 的保守合取，页面请读下面两个细分字段。
    public let modifierVerified: Bool
    public let modifierVerifiedNote: String
    /// L1 / L12 锚点 + 「13–15 沿用 L12」已由实测确认。
    public let modifierAnchorVerified: Bool
    public let modifierAnchorVerification: String
    /// 2–11 级的逐级数值与取整方向仍未实测。
    public let modifierMidLevelsVerified: Bool
    public let modifierInference: String
    public let libraRule: String

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        baseAnchorLevels = container.heroIntArray(.baseAnchorLevels)
        modifierAnchorLevels = container.heroIntArray(.modifierAnchorLevels)
        // 缺这一项时留 0，**不要**假装数据集声明了 15：由 HeroStatsIndex.maxLevel
        // 退回「各角色 levels 里的最大等级」（Windows 端 maxLevelOf 同一条兜底）。
        maxLevel = container.heroInt(.maxLevel, default: 0)
        baseRule = container.heroString(.baseRule)
        baseRounding = container.heroString(.baseRounding)
        baseVerified = container.heroBool(.baseVerified)
        baseVerification = container.heroString(.baseVerification)
        derivedRule = container.heroString(.derivedRule)
        modifierRule = container.heroString(.modifierRule)
        modifierRounding = container.heroString(.modifierRounding)
        modifierVerified = container.heroBool(.modifierVerified)
        modifierVerifiedNote = container.heroString(.modifierVerifiedNote)
        modifierAnchorVerified = container.heroBool(.modifierAnchorVerified)
        modifierAnchorVerification = container.heroString(.modifierAnchorVerification)
        modifierMidLevelsVerified = container.heroBool(.modifierMidLevelsVerified)
        modifierInference = container.heroString(.modifierInference)
        libraRule = container.heroString(.libraRule)
    }

    /// 底部「插值说明」折叠区逐条展示（正文为空的条目跳过）。
    ///
    /// 标题与两条拼装出来的正文都走 `HeroStatsCopy`，Windows 端
    /// `renderer/pages/heroes.js` 的 `interpolationNotes(data)` 拼的是同一组条目、
    /// 同一个顺序 —— 折叠区标题里的「N 条」因此两端必然相同。
    public var notes: [HeroNote] {
        let titles = HeroStatsCopy.interpolationNoteTitles
        let candidates: [(String, String)] = [
            (titles[0], baseAnchorLevels.isEmpty
                ? ""
                : HeroStatsCopy.interpolationAnchorNote(
                    baseAnchorLevels: baseAnchorLevels, modifierAnchorLevels: modifierAnchorLevels)),
            (titles[1], baseRule),
            (titles[2], baseVerification),
            (titles[3], derivedRule),
            (titles[4], modifierRule),
            (titles[5], modifierAnchorVerification),
            (titles[6], modifierInference),
            (titles[7], HeroStatsCopy.interpolationRoundingNote(base: baseRounding, modifier: modifierRounding)),
            (titles[8], modifierVerifiedNote),
            (titles[9], libraRule)
        ]
        return candidates.filter { !$0.1.isEmpty }.map { HeroNote(title: $0.0, text: $0.1) }
    }
}

// MARK: - 数据集

public struct HeroDataset: Sendable {
    public let schemaVersion: Int
    public let datasetId: String
    public let gameVersion: String
    public let dataVersion: String
    public let generatedAt: String
    public let statNames: HeroStatNames
    /// CalcCorrectGraph 行号 → 行。
    public let growthGraphs: [Int: HeroGrowthGraph]
    public let interpolation: HeroInterpolation
    public let caveats: [String]
    public let counts: [String: Int]
    public let heroes: [HeroEntry]
    public let statModifiers: [HeroStatModifier]
    public let libraRespecs: [HeroLibraRespec]
    public let crossChecks: [HeroCrossCheck]
    public let sources: [HeroSource]
}

extension HeroDataset: Decodable {
    private enum CodingKeys: String, CodingKey {
        case schemaVersion, datasetId, gameVersion, dataVersion, generatedAt
        case statNames, growthGraphs, interpolation, caveats, counts
        case heroes, statModifiers, libraRespecs, crossChecks, sources
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = container.heroInt(.schemaVersion, default: 0)
        datasetId = container.heroString(.datasetId)
        gameVersion = container.heroString(.gameVersion)
        dataVersion = container.heroString(.dataVersion)
        generatedAt = container.heroString(.generatedAt)
        let names = try? container.decode(HeroStatNames.self, forKey: .statNames)
        statNames = names ?? HeroStatNames(attributeOrder: [], derivedOrder: [], attributes: [], derived: [])
        let graphs: [String: HeroGrowthGraph] = container.heroDictionary(.growthGraphs)
        var byId: [Int: HeroGrowthGraph] = [:]
        for (key, graph) in graphs {
            byId[graph.id != 0 ? graph.id : (Int(key) ?? 0)] = graph
        }
        growthGraphs = byId
        interpolation = (try? container.decode(HeroInterpolation.self, forKey: .interpolation)) ?? .empty
        caveats = container.heroStringArray(.caveats)
        counts = container.heroDictionary(.counts)
        heroes = container.heroArray(.heroes)
        statModifiers = container.heroArray(.statModifiers)
        libraRespecs = container.heroArray(.libraRespecs)
        crossChecks = container.heroArray(.crossChecks)
        sources = container.heroArray(.sources)
    }
}

// MARK: - 对比表

/// 「同级对比」表的可排序列。
public enum HeroComparisonColumn: Sendable, Hashable {
    case hero
    case stat(String)
    case derived(String)
}

/// 「同级对比」表的一行。
public struct HeroComparisonRow: Sendable, Hashable, Identifiable {
    public let heroKey: String
    public let heroId: Int
    public let nameZh: String
    public let nameEn: String
    public let level: Int
    public let stats: [String: Int]
    public let derived: [String: Double]

    public var id: String { heroKey }

    public init(
        heroKey: String, heroId: Int, nameZh: String, nameEn: String,
        level: Int, stats: [String: Int], derived: [String: Double]
    ) {
        self.heroKey = heroKey
        self.heroId = heroId
        self.nameZh = nameZh
        self.nameEn = nameEn
        self.level = level
        self.stats = stats
        self.derived = derived
    }

    /// 排序用的数值；角色列没有数值（按数据集顺序 / 名字排）。
    public func value(for column: HeroComparisonColumn) -> Double? {
        switch column {
        case .hero: return nil
        case .stat(let key): return stats[key].map(Double.init)
        case .derived(let key): return derived[key]
        }
    }
}

public enum HeroComparison {
    /// 按列排序。数值相同（或该列缺数据）时一律退回数据集顺序（heroId），也就是**稳定排序**：
    /// 平手的几行在升序和降序里保持同一个相对顺序，因此数值列上点两次列头得到的
    /// **不是**严格反序（只有「角色」列没有平手，反过来点才是严格反序）。
    /// 例如 15 级集中力一列守护者 / 铁之眼 / 送葬者同为 14，两个方向都按数据集顺序排；
    /// 15 级的 12 列里有 9 列存在平手。
    /// 自检 checkHeroComparison 断言的也正是这条（单调性 + 平手退回数据集顺序），
    /// Windows 端照抄时别写成 `asc == desc.reversed()`。
    public static func sorted(
        _ rows: [HeroComparisonRow],
        by column: HeroComparisonColumn,
        ascending: Bool
    ) -> [HeroComparisonRow] {
        rows.sorted { lhs, rhs in
            if case .hero = column {
                if lhs.heroId != rhs.heroId { return ascending ? lhs.heroId < rhs.heroId : lhs.heroId > rhs.heroId }
                return lhs.heroKey < rhs.heroKey
            }
            let left = lhs.value(for: column)
            let right = rhs.value(for: column)
            if let left, let right {
                if left != right { return ascending ? left < right : left > right }
            } else if left != nil {
                return true             // 有数据的排在缺数据的前面
            } else if right != nil {
                return false
            }
            return lhs.heroId < rhs.heroId
        }
    }
}

// MARK: - 单角色快照

/// 某个角色在某一级、叠加若干条转职遗物（可选利普拉替换）后的完整属性。
public struct HeroStatsSnapshot: Sendable, Hashable {
    public let heroKey: String
    public let heroNameZh: String
    public let heroNameEn: String
    public let level: Int
    /// 基础表是不是参数锚点等级。
    public let isAnchorLevel: Bool
    /// 选中的利普拉交易（整表替换）；nil 表示没选。
    public let libraKey: String?
    /// 基础属性（利普拉替换之后、转职遗物之前）。
    public let baseStats: [String: Int]
    /// 最终属性（叠加转职遗物并钳位之后）。
    public let finalStats: [String: Int]
    /// 转职遗物给出的原始增减量之和（未钳位）。
    public let requestedDelta: [String: Int]
    /// 被钳到 1 的属性，按页面上的属性展示顺序排。
    public let clampedStats: [String]
    /// 被钳属性钳位前的原值（页面写「原为 0，已钳到最低 1」）。
    public let clampedFrom: [String: Int]
    public let baseDerived: [String: Double]
    public let finalDerived: [String: Double]
    /// 生效的词条（按数据集顺序）。
    public let activeModifiers: [HeroStatModifier]
    /// 这一级增减量的来历（锚点 / 推算 / 沿用最后一个锚点）；没勾词条时为 nil。
    /// 页面上的徽标、表里的备注列都读它，**别再另算一份**，否则标记会和这里对不上。
    public let modifierSource: HeroModifierSourceTag?

    /// 生效词条里有「推算」等级（锚点之间的 2–11 级）。
    public var hasInferredDelta: Bool { modifierSource?.source == .inferred }
    /// 当前等级在最后一个锚点之后，增减量沿用那个锚点。
    public var carriesAnchorDelta: Bool { modifierSource?.source == .carried }

    public var hasModifier: Bool { !activeModifiers.isEmpty }
    public var isModified: Bool { hasModifier || libraKey != nil }

    /// 实际生效的增减量（钳位之后的差值）。
    public func effectiveDelta(_ key: String) -> Int {
        (finalStats[key] ?? 0) - (baseStats[key] ?? 0)
    }

    public func derivedDelta(_ key: String) -> Double {
        (finalDerived[key] ?? 0) - (baseDerived[key] ?? 0)
    }
}

// MARK: - 索引

/// 页面用的数据索引：解码一次，之后所有换算都走这里的纯函数。
public struct HeroStatsIndex: Sendable {
    public let dataset: HeroDataset
    private let heroesByKey: [String: HeroEntry]
    private let modifiersByHero: [String: [HeroStatModifier]]
    private let libraByKey: [String: HeroLibraRespec]

    public init(data: Data) throws {
        guard let object = try? JSONSerialization.jsonObject(with: data), object is [String: Any] else {
            throw HeroDataError.notAnObject
        }
        let decoded: HeroDataset
        do {
            decoded = try JSONDecoder().decode(HeroDataset.self, from: data)
        } catch {
            throw HeroDataError.undecodable(String(describing: error))
        }
        guard !decoded.heroes.isEmpty else { throw HeroDataError.empty }
        self.init(dataset: decoded)
    }

    public init(dataset: HeroDataset) {
        self.dataset = dataset
        heroesByKey = Dictionary(dataset.heroes.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
        var grouped: [String: [HeroStatModifier]] = [:]
        for modifier in dataset.statModifiers {
            grouped[modifier.heroKey, default: []].append(modifier)
        }
        modifiersByHero = grouped
        libraByKey = Dictionary(dataset.libraRespecs.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
    }

    public var heroes: [HeroEntry] { dataset.heroes }
    public var statNames: HeroStatNames { dataset.statNames }
    public var libraRespecs: [HeroLibraRespec] { dataset.libraRespecs }

    /// 数据集声明的最大等级；没声明（或声明成 0）时退回各角色 levels 里的最大等级，
    /// 再没有才退回 15。Windows 端 `maxLevelOf(data)` 是同一条，两端的等级选择器、
    /// 表体行数、标题与汇总因此一起跟着数据集走。
    public var maxLevel: Int {
        let declared = dataset.interpolation.maxLevel
        if declared > 0 { return declared }
        return dataset.heroes.map(\.maxLevel).max() ?? 15
    }

    public var levelRange: [Int] { Array(1...max(1, maxLevel)) }

    public func hero(_ key: String) -> HeroEntry? { heroesByKey[key] }

    public func modifiers(for heroKey: String) -> [HeroStatModifier] {
        modifiersByHero[heroKey] ?? []
    }

    public func libra(_ key: String?) -> HeroLibraRespec? {
        guard let key else { return nil }
        return libraByKey[key]
    }

    /// 某个角色与外部 wiki 的逐格对照；**只有真有差异时**才返回（0 差异不必打扰用户）。
    public func crossCheck(for heroKey: String) -> HeroCrossCheck? {
        dataset.crossChecks.first { $0.heroKey == heroKey && $0.mismatchCount > 0 }
    }

    public var summary: String {
        "\(dataset.heroes.count) 位渡夜者 · 1–\(maxLevel) 级"
    }

    /// 基础属性表：选了利普拉的交易就整套换成对应的表（heroStatusId 替换）。
    public func baseLevels(heroKey: String, libraKey: String?) -> [HeroLevelRow] {
        if let libra = libra(libraKey) { return libra.levels }
        return hero(heroKey)?.levels ?? []
    }

    public func baseLevel(heroKey: String, level: Int, libraKey: String?) -> HeroLevelRow? {
        baseLevels(heroKey: heroKey, libraKey: libraKey).first { $0.level == level }
    }

    /// 派生值：一律按 growthGraphs 现算（与数据集自带的 derived 逐格一致，见自检）。
    public func derivedValues(for stats: [String: Int]) -> [String: Double] {
        HeroStatsMath.derivedValues(for: stats, names: dataset.statNames, graphs: dataset.growthGraphs)
    }

    /// 某个角色在某一级、叠加若干条词条后的完整属性。
    public func snapshot(
        heroKey: String,
        level: Int,
        modifierIDs: Set<Int> = [],
        libraKey: String? = nil
    ) -> HeroStatsSnapshot? {
        guard let hero = hero(heroKey) else { return nil }
        guard let baseRow = baseLevel(heroKey: heroKey, level: level, libraKey: libraKey) else { return nil }
        let active = modifiers(for: heroKey).filter { modifierIDs.contains($0.affixId) }
        let rows = active.compactMap { $0.level(level) }
        let applied = HeroStatsMath.apply(
            deltas: rows.map(\.delta), to: baseRow.stats, order: dataset.statNames.attributeKeys
        )
        let anchorLevels = dataset.interpolation.modifierAnchorLevels
        return HeroStatsSnapshot(
            heroKey: hero.key,
            heroNameZh: hero.nameZh,
            heroNameEn: hero.nameEn,
            level: level,
            isAnchorLevel: baseRow.isAnchor,
            libraKey: libra(libraKey)?.key,
            baseStats: baseRow.stats,
            finalStats: applied.stats,
            requestedDelta: applied.requested,
            clampedStats: applied.clamped,
            clampedFrom: applied.clampedFrom,
            baseDerived: derivedValues(for: baseRow.stats),
            finalDerived: derivedValues(for: applied.stats),
            activeModifiers: active,
            // 没勾词条就没有「增减量来历」可言；勾了就一律走同一条判定（页面徽标读的也是它）。
            modifierSource: active.isEmpty
                ? nil
                : HeroStatsText.modifierSource(level: level, anchorLevels: anchorLevels)
        )
    }

    /// 「全部等级」表：1–15 级逐行（同样支持词条叠加与利普拉替换）。
    public func snapshots(
        heroKey: String,
        modifierIDs: Set<Int> = [],
        libraKey: String? = nil
    ) -> [HeroStatsSnapshot] {
        levelRange.compactMap {
            snapshot(heroKey: heroKey, level: $0, modifierIDs: modifierIDs, libraKey: libraKey)
        }
    }

    /// 全部等级表的钳位汇总：按**行**聚合成「等级 → 被钳属性中文名」。
    /// 表里一次能看到 1–15 行，汇总也要覆盖这 15 行，不能只报当前等级那一行。
    public func clampedByLevel(_ snapshots: [HeroStatsSnapshot]) -> [(level: Int, names: [String])] {
        snapshots
            .filter { !$0.clampedStats.isEmpty }
            .sorted { $0.level < $1.level }
            .map { snapshot in
                (snapshot.level, snapshot.clampedStats.map { dataset.statNames.attributeTitle($0) })
            }
    }

    /// 「同级对比」表：当前等级下 10 个角色的基础属性与派生值（不含转职遗物 / 利普拉）。
    public func comparisonRows(level: Int) -> [HeroComparisonRow] {
        dataset.heroes.compactMap { hero in
            guard let row = hero.level(level) else { return nil }
            return HeroComparisonRow(
                heroKey: hero.key,
                heroId: hero.id,
                nameZh: hero.nameZh,
                nameEn: hero.nameEn,
                level: level,
                stats: row.stats,
                derived: derivedValues(for: row.stats)
            )
        }
    }
}

// MARK: - 文案

public enum HeroStatsText {
    /// 去掉多余 0 的小数：74.10 → 74.1，45.0 → 45。
    public static func decimal(_ value: Double, digits: Int = 1) -> String {
        guard value.isFinite else { return "—" }
        var text = String(format: "%.\(max(0, digits))f", value)
        if text.contains(".") {
            while text.hasSuffix("0") { text.removeLast() }
            if text.hasSuffix(".") { text.removeLast() }
        }
        return text == "-0" ? "0" : text
    }

    /// 带符号的增减量：+5 / -3 / 0。
    public static func signed(_ value: Int) -> String {
        value > 0 ? "+\(value)" : String(value)
    }

    public static func signed(_ value: Double, digits: Int = 1) -> String {
        let text = decimal(abs(value), digits: digits)
        if value > 0 { return "+" + text }
        if value < 0 { return "-" + text }
        return "0"
    }

    /// 属性值：没有数值时给破折号，不要退回 0。
    public static func statText(_ value: Int?) -> String {
        guard let value else { return HeroStatsCopy.missing }
        return String(value)
    }

    /// 派生值：整数项直接显示，负重上限**固定**保留 1 位小数；缺 growthGraph 或
    /// 缺来源属性时给破折号 —— 退回 0 会让「数据缺失」看起来像「真的是 0」。
    ///
    /// 这里不走 `decimal`（它会去掉末尾的 0）：整列都是 1 位小数时，45.0 写成「45」
    /// 会在 74.1 旁边看着像整数，一列小数点也对不齐。`decimal` 仍用于增减量
    /// （「+3」比「+3.0」读着顺），两者口径不同是故意的。
    public static func derivedText(_ value: Double?, integer: Bool) -> String {
        guard let value, value.isFinite else { return HeroStatsCopy.missing }
        return integer ? String(Int(value.rounded())) : String(format: "%.1f", value)
    }

    /// 某一级的转职遗物增减量来源：锚点 / 推算 / 沿用最后一个锚点。
    /// 锚点等级一律读数据集的 `interpolation.modifierAnchorLevels`，两端都不写死 1 / 12。
    /// 数据里没有锚点信息时返回 nil（页面此时什么都不标，而不是瞎标「推算」）。
    public static func modifierSource(level: Int, anchorLevels: [Int]) -> HeroModifierSourceTag? {
        guard let last = anchorLevels.max() else { return nil }
        if anchorLevels.contains(level) { return HeroModifierSourceTag(source: .anchor, label: "词条锚点") }
        if level > last { return HeroModifierSourceTag(source: .carried, label: "词条沿用 \(last) 级锚点") }
        return HeroModifierSourceTag(source: .inferred, label: "词条推算")
    }
}

/// 转职遗物增减量在某一级的来历。
public enum HeroModifierSource: String, Sendable, Hashable {
    /// 参数表原值（1 / 12 级）。
    case anchor
    /// 锚点之间的线性插值推算（2–11 级）。
    case inferred
    /// 沿用最后一个锚点（13–15 级）。
    case carried

    /// 三档三色，两端同一张表（Windows 端 heroes.js 的 `SOURCE_PILL`）。
    /// 颜色名放在 RelicCore 而不是视图层，是为了让自检能把「来源 → 配色」钉死：
    /// 上一轮 macOS 把 `.carried` 和 `.anchor` 画成同一个绿底 + 同一个对勾，
    /// 页面上「词条锚点」与「词条沿用 12 级锚点」只有文字不同，而 Windows 是绿 vs 蓝。
    public var colorToken: String {
        switch self {
        case .anchor: return "green"
        case .inferred: return "amber"
        case .carried: return "blue"
        }
    }

    /// macOS 端徽标用的 SF Symbol；三档同样各有各的图标（Windows 端只靠颜色区分）。
    public var symbolName: String {
        switch self {
        case .anchor: return "checkmark.seal"
        case .inferred: return "exclamationmark.triangle"
        case .carried: return "arrow.right.circle"
        }
    }
}

public struct HeroModifierSourceTag: Sendable, Hashable {
    public let source: HeroModifierSource
    public let label: String

    public init(source: HeroModifierSource, label: String) {
        self.source = source
        self.label = label
    }
}

// MARK: - 双端共用文案

/// 「角色属性」页两端必须逐字相同的文案。
///
/// Windows 端 `renderer/pages/heroes.js` 里有一份同名同结构的 `COPY`，两端的
/// 测试 / 自检各自把下面这些字符串钉死 —— 只要一端改字、另一端没跟上，两边的
/// 用例就会各自红一片（上一轮两端各写各的字面量、注释却都声称「逐字一致」，
/// 就是这么漂掉的）。改文案时请两端 + 两份用例一起改。
public enum HeroStatsCopy {
    /// 没有数值时统一显示破折号，**不要**退回 0（0 是真实数值，破折号才是「没有」）。
    public static let missing = "—"

    // 视图
    public static let viewSingle = "单角色"
    public static let viewCompare = "同级对比"

    // 基础表的等级来源
    public static func baseLevelBadge(level: Int, isAnchor: Bool) -> String {
        isAnchor ? "\(level) 级是参数锚点" : "\(level) 级为插值推算"
    }
    public static let baseAnchorTag = "参数锚点"
    public static let baseInterpolatedTag = "插值推算"
    public static func allLevelsCaption(anchorLevels: [Int]) -> String {
        "加粗行是参数表里的锚点（" + anchorLevels.map(String.init).joined(separator: " / ")
            + " 级），其余等级按相邻锚点线性插值后向下取整。"
    }

    // 转职遗物
    public static func modifierCountBadge(_ count: Int) -> String { "转职遗物 \(count) 条" }
    public static let modifierSubtitle = "勾选后在基础属性上加减（可同时勾选，效果相加）；派生值按 CalcCorrectGraph 重算"
    public static let dlcOnlyTag = "仅 DLC 池可掉"
    public static let noDeltaAtLevel = "本级无增减"
    public static let noModifierData = "数据未内置该角色的转职遗物词条"

    /// 「生命力 -5、集中力 +10」：增减量摘要，按属性展示顺序排、跳过 0。
    public static func deltaSummary(_ delta: [String: Int], names: HeroStatNames) -> String {
        names.attributeKeys
            .filter { (delta[$0] ?? 0) != 0 }
            .map { names.attributeTitle($0) + " " + HeroStatsText.signed(delta[$0] ?? 0) }
            .joined(separator: "、")
    }

    /// `deltaFloorAlt` 只含「换成 floor 取整后结果不同」的项，而这些项恒为负
    /// （floor 与 trunc 只在负数上差 1）。所以文案要写清楚这是**负向项**的替换，
    /// 而不是整条词条改成这几项。
    public static func floorAlt(_ summary: String) -> String {
        "若按 floor 取整，负向项改为：" + summary + "（其余项不变）"
    }

    // 钳位
    public static let clampCellTag = "钳"
    public static let clampRowTag = "已钳位"
    public static var clampTail: String { "已钳到最低 \(HeroStatsMath.minimumStat)" }
    public static func clampedFromNote(_ raw: Int) -> String { "原为 \(raw)，" + clampTail }
    /// 卡片上的大数字是**生效**增减量（最终 − 基础）；被钳位时请求值与生效值不一样，
    /// 请求值只在这句小字 / tooltip 里出现（「词条请求 -9，已钳到最低 1」）。
    /// 上一轮 Windows 的卡片写请求值 -9、macOS 写生效值 -8，同一输入两端两个数字。
    public static func clampRequestedNote(_ requested: Int) -> String {
        "词条请求 " + HeroStatsText.signed(requested) + "，" + clampTail
    }
    public static func clampSummary(_ names: [String]) -> String {
        names.joined(separator: "、") + " 叠加后不足 \(HeroStatsMath.minimumStat)，" + clampTail
            + "（游戏里属性不会低于 \(HeroStatsMath.minimumStat)）"
    }
    /// 全部等级视图的钳位汇总：**按行聚合**（每一级各列哪些属性被钳），
    /// 而不是只报当前等级那一行 —— 表里一次能看到 15 行，汇总也要对得上 15 行。
    public static func clampSummaryByLevel(_ rows: [(level: Int, names: [String])], maxLevel: Int) -> String {
        guard !rows.isEmpty else { return "" }
        let body = rows
            .map { "\($0.level) 级 " + $0.names.joined(separator: "、") }
            .joined(separator: "；")
        return "1–\(maxLevel) 级里有 \(rows.count) 级叠加后不足 \(HeroStatsMath.minimumStat)："
            + body + "；" + clampTail + "（游戏里属性不会低于 \(HeroStatsMath.minimumStat)）"
    }

    // 利普拉的交易
    public static let libraSwapTag = "整套替换"
    public static let libraHint = "利普拉的交易把整套基础属性表替换掉；能否与转职遗物叠加是按参数字段结构推断的，未实测"
    public static let libraEmptyHint = "选中后基础表整套换成对应的替换表，转职遗物仍可叠加。"
    public static func libraBadge(_ statName: String) -> String { "利普拉：" + statName }

    // 与外部 wiki 的逐格对照
    public static func crossCheckNote(count: Int, note: String) -> String {
        "与外部 wiki 有 \(count) 格差异，本页以参数为准" + (note.isEmpty ? "" : "：" + note)
    }
    /// 做了利普拉的交易之后，基础表已经不是该角色的原表，wiki 差异提示无从谈起。
    public static let libraCrossCheckNote = "已做利普拉的交易，基础表整套替换，与外部 wiki 的角色原表差异不再适用"

    // 负重上限：遗留列
    public static let legacyMark = "*"
    public static func legacyHeader(_ title: String) -> String { title + " " + legacyMark }
    public static let equipLoadHint = "本作装备没有重量，负重上限是《艾尔登法环》继承下来的遗留列，未经实测"
    public static let equipLoadFootnote = legacyMark
        + " 负重上限是《艾尔登法环》继承下来的遗留列：本作装备没有重量、界面也没有负重条，未经实测，仅供参考。"

    // 同级对比
    public static let compareCaption = "对比表只用各角色的基础表：利普拉的交易不分角色（叠上去每行都一样），"
        + "转职遗物是逐角色的词条，都不进对比。"

    // 底部折叠区
    //
    // 「插值与验证口径」两端渲染的是同一组说明（同序、同标题、同正文，见
    // `HeroInterpolation.notes` 与 Windows 端 `interpolationNotes(data)`），标题里的
    // N 因此两端必然相同 —— 上一轮一端数 interpolation 的**字段数**（17）、另一端数
    // 拼出来的**条目数**（10），同一份数据在两端的页面上写着两个数字。
    public static let interpolationNoteTitles = [
        "参数锚点", "基础属性插值", "基础表验证", "派生值换算", "转职遗物插值",
        "转职遗物锚点验证", "转职遗物中间等级", "取整方向", "兼容字段说明", "利普拉的交易"
    ]
    public static func interpolationAnchorNote(baseAnchorLevels: [Int], modifierAnchorLevels: [Int]) -> String {
        let base: String = baseAnchorLevels.map(String.init).joined(separator: " / ")
        let modifier: String = modifierAnchorLevels.map(String.init).joined(separator: " / ")
        return "基础属性表只有 \(base) 级是参数原值，转职遗物只有 \(modifier) 级是参数原值。"
    }
    public static func roundingTerm(_ raw: String) -> String {
        switch raw {
        case "floor": return "向下取整（floor）"
        case "trunc": return "向零取整（trunc）"
        case "round": return "四舍五入（round）"
        default: return raw
        }
    }
    /// `baseRounding` / `modifierRounding` 这两条口径页面也要看得见：floor 与 trunc
    /// 只在**负**增减量上差 1，正是 caveats 点名的歧义来源，数据集为此对受影响的等级
    /// 另给了 `deltaFloorAlt`。两个字段都缺时返回空串（整条说明不出现，不硬造）。
    public static func interpolationRoundingNote(base: String, modifier: String) -> String {
        var parts: [String] = []
        if !base.isEmpty { parts.append("基础属性表按" + roundingTerm(base)) }
        if !modifier.isEmpty { parts.append("转职遗物增减量按" + roundingTerm(modifier)) }
        guard !parts.isEmpty else { return "" }
        var note = parts.joined(separator: "，") + "。"
        if base != modifier && !base.isEmpty && !modifier.isEmpty {
            note += "两种取整只在负的增减量上差 1；"
        }
        note += "换成另一种取整后结果不同的等级，数据集在 statModifiers[].levels[].deltaFloorAlt 里另给了一份备用值，"
            + "本页展示的一律是上面这一种。"
        return note
    }
    public static func interpolationTitle(_ count: Int) -> String { "插值与验证口径（\(count) 条）" }
    public static func caveatsTitle(_ count: Int) -> String { "已知取舍（\(count) 条）" }
    public static func sourcesTitle(_ count: Int) -> String { "数据出处（\(count) 条）与外部对照" }
    public static let versionLabels = ["游戏版本", "数据版本", "生成时间", "数据集结构版本", "收录"]
    public static func contentSummary(heroes: Int, maxLevel: Int, modifiers: Int, libra: Int) -> String {
        "\(heroes) 位渡夜者 × \(maxLevel) 级 · \(modifiers) 条转职遗物词条 · \(libra) 笔利普拉交易"
    }
    public static let emptyData = "数据未内置"
}
