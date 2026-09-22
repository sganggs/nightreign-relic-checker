import Foundation

// 词条反查：把「词条库 + 遗物物品表」翻转成「词条 → 能在哪出」与
// 「遗物 → 槽位池成员」两个方向的索引。
//
// 纯逻辑、无 SwiftUI 依赖：视图一次构建（`AffixLookupIndex(catalog:relicData:)`）
// 并缓存在 `@State` 里即可，后续查询都是字典命中。

// MARK: - 池与口径

/// 深夜正面词条池（A / B / C），顺序即展示顺序。
public let deepPositiveLookupPools: [Int] = [2_000_000, 2_100_000, 2_200_000]

/// 深夜诅咒（负面词条）池。
public let deepCurseLookupPool = 3_000_000

/// 反查页展示的口径：「顺序/互斥」不涉及槽池，不参与反查。
public let affixLookupModes: [CheckMode] = [.currentNormal, .legacyNormal, .deepPositive]

/// 槽位池的中文短名；未知池回退为「池 <id>」。
///
/// 普通大遗物的槽位池按孔数分层（真实物品表：1 孔 = [100]，2 孔 = [200, 100]，
/// 3 孔 = [300, 200, 100]；1.03 之后同构为 110 / 210 / 310）。
///
/// 注意三层与「第几槽」不是一回事：3 孔遗物的 slots 数组是 [300, 200, 100]，
/// 第 1 个槽位用的是 3 孔层池。这里一律按孔数层命名，避免和槽序号撞车。
/// 三层是嵌套关系（1 孔层 ⊆ 2 孔层 ⊆ 3 孔层；当前数据里三层成员完全相同）。
public func affixPoolLabel(_ poolID: Int) -> String {
    switch poolID {
    case 100: return "旧池 · 1 孔层"
    case 200: return "旧池 · 2 孔层"
    case 300: return "旧池 · 3 孔层"
    case 110: return "1.03 · 1 孔层"
    case 210: return "1.03 · 2 孔层"
    case 310: return "1.03 · 3 孔层"
    case 2_000_000: return "深夜 A 池"
    case 2_100_000: return "深夜 B 池"
    case 2_200_000: return "深夜 C 池"
    case 3_000_000: return "深夜诅咒池"
    default: return "池 \(poolID)"
    }
}

/// 槽位池的补充说明；没有则为空串。
public func affixPoolDetail(_ poolID: Int) -> String {
    switch poolID {
    case 2_000_000: return "强力正面词条：同一行必定配一条深夜诅咒"
    case 2_100_000, 2_200_000: return "普通正面词条：同一行不带诅咒"
    case 3_000_000: return "深夜遗物负面词条的唯一来源"
    default: return ""
    }
}

// MARK: - 条目模型

/// 反查用的词条条目：词条库（affixes.json）∪ 遗物物品表的 extraAffixes。
///
/// `inCatalog == false` 的条目只在物品表里有名字，没有说明 / 分类 / 叠加性。
public struct LookupAffix: Identifiable, Hashable, Sendable {
    public let effectID: Int
    public let name: String
    public let category: String
    public let explanation: String
    public let superposability: String
    public let compatibilityID: Int
    public let sortID: Int
    /// 词条库声明的槽位池（extraAffixes 条目为空）。遗物物品表缺失时用它兜底。
    public let poolIDs: [Int]
    public let isCurse: Bool
    public let requiresCurse: Bool
    public let inCatalog: Bool
    public let searchText: String

    public var id: Int { effectID }
    public var displayName: String { name.isEmpty ? "未命名词条 #\(effectID)" : name }

    public init(
        effectID: Int,
        name: String,
        category: String,
        explanation: String,
        superposability: String,
        compatibilityID: Int,
        sortID: Int,
        poolIDs: [Int],
        isCurse: Bool,
        requiresCurse: Bool,
        inCatalog: Bool,
        searchText: String
    ) {
        self.effectID = effectID
        self.name = name
        self.category = category
        self.explanation = explanation
        self.superposability = superposability
        self.compatibilityID = compatibilityID
        self.sortID = sortID
        self.poolIDs = poolIDs
        self.isCurse = isCurse
        self.requiresCurse = requiresCurse
        self.inCatalog = inCatalog
        self.searchText = searchText
    }
}

/// 槽位的正 / 负面区分。
public enum RelicSlotRole: String, Hashable, Sendable {
    case positive
    case curse

    public var title: String {
        switch self {
        case .positive: return "正面槽"
        case .curse: return "诅咒槽"
        }
    }
}

/// 正常游玩能拿到的遗物 ID 区间（与 `RelicAuditor` 的合法区间一致，RelicAudit 第 3 条规则）。
/// 物品表里另有 554 条超出该区间、且没有名字的参数行（调试 / 未启用条目），
/// 反查时一律不展示，否则会让人误以为某条词条「有遗物固定带」。
public let obtainableRelicIDRange: ClosedRange<Int> = 100...2_013_322

/// 作弊器常用 ID 区段（与 `RelicAuditor` 第 2 条规则一致）：正常游玩不会获得。
/// 内置物品表里这 72 件的槽位池全是空池 1，当成正常遗物展示会渲染出「随机 0 条」的空面板。
public let cheatRelicIDRange: ClosedRange<Int> = 20_000...30_035

/// 「某条词条能在这件遗物上出」的一条命中记录（已按遗物去重）。
public struct RelicLookupHit: Identifiable, Hashable, Sendable {
    public let relicID: Int
    public let relicName: String
    public let kindLabel: String
    public let colorLabel: String
    public let deep: Bool
    public let slotCount: Int
    /// 命中的槽位池 id（升序）。
    ///
    /// 不给「命中第几槽」：物品表的槽序号对普通遗物与孔数层池对不上号
    /// （3 孔遗物的 slots 是 [300, 200, 100]），对深夜遗物更是与游戏实际生成不符
    /// （见 RelicAudit 第 7 条），展示出来只会误导。
    public let poolIDs: [Int]
    public let role: RelicSlotRole
    /// 命中的池是单词条固定池 → 这件遗物必定带这条词条。
    public let isFixed: Bool

    public var id: String { "\(relicID)-\(role.rawValue)" }
}

/// 一条槽位池的命中情况（口径 / 深夜池展示用）。
public struct LookupPoolHit: Identifiable, Hashable, Sendable {
    public let poolID: Int
    public let contains: Bool
    public let memberCount: Int
    public let relicCount: Int

    public var id: Int { poolID }
    public var label: String { affixPoolLabel(poolID) }
    public var detail: String { affixPoolDetail(poolID) }
}

/// 一种口径下的槽位池命中。
public struct LookupModeHit: Identifiable, Hashable, Sendable {
    public let mode: CheckMode
    public let pools: [LookupPoolHit]

    public var id: String { mode.rawValue }
    public var isAvailable: Bool { pools.contains { $0.contains } }
    public var hitPools: [LookupPoolHit] { pools.filter(\.contains) }
}

/// 按遗物种类聚合的命中件数。
public struct LookupKindCount: Identifiable, Hashable, Sendable {
    public let kind: String
    public let count: Int

    public var id: String { kind }
}

/// 一次词条反查的完整结果。
public struct AffixLookupReport: Sendable {
    public let affix: LookupAffix
    /// 同互斥组的其它词条（compatibilityId 相同且不为 -1）。
    public let conflicts: [LookupAffix]
    /// 三种口径的普通随机遗物槽位。
    public let modeHits: [LookupModeHit]
    /// 深夜 A / B / C 池。
    public let deepHits: [LookupPoolHit]
    /// 深夜诅咒池（该词条是负面词条时才有意义）。
    public let cursePoolHit: LookupPoolHit
    /// 含该词条的全部槽位池（升序）。
    public let poolIDs: [Int]
    /// 固定出：命中的池只有这一条词条。
    public let fixedRelics: [RelicLookupHit]
    /// 随机出：命中的池是多词条随机池。
    public let randomRelics: [RelicLookupHit]
    /// 按遗物种类聚合（固定 + 随机）。
    public let kindCounts: [LookupKindCount]
    /// 被过滤掉的条数：超范围 / 无名参数行、作弊器区段遗物、槽位池为空的脏数据
    /// （见 `RelicLookupEntry.isObtainable`）。
    public let hiddenRelicCount: Int
    /// 遗物物品表是否可用；为 false 时遗物相关字段一律为空。
    public let hasRelicData: Bool

    public var totalRelicCount: Int { fixedRelics.count + randomRelics.count }
}

/// 一件遗物的单个槽位概览。
public struct RelicSlotSummary: Identifiable, Hashable, Sendable {
    public let slotIndex: Int
    public let poolID: Int
    public let poolSize: Int
    public let cursePoolID: Int
    public let cursePoolSize: Int
    /// 池成员预览（固定池即唯一成员；随机池取排序后的前若干条）。
    public let previewEffectIDs: [Int]

    public var id: Int { slotIndex }
    public var isEmpty: Bool { poolID == -1 }
    public var isFixed: Bool { poolID != -1 && poolSize == 1 }
    public var hasCurse: Bool { cursePoolID != -1 }
}

/// 反查用的遗物条目。
public struct RelicLookupEntry: Identifiable, Hashable, Sendable {
    public let info: RelicInfo
    public let displayName: String
    public let kindLabel: String
    public let colorLabel: String
    public let isUnique: Bool
    /// 恒为 3 条，空槽的 `isEmpty == true`。
    public let slots: [RelicSlotSummary]
    /// 全部非空槽都是单词条固定池时的官方固定词条（按 (sortId, effectId) 升序补 -1 到 3 位）；
    /// 与 `RelicAuditor` 给出的 `officialEffects` 同规则。
    public let fixedEffectIDs: [Int]?
    public let searchText: String

    public var id: Int { info.id }
    public var slotCount: Int { slots.filter { !$0.isEmpty }.count }
    public var deep: Bool { info.deep }
    /// 正常游玩能拿到：ID 在合法区间内、不在作弊器区段、有官方名称，
    /// 且至少有一个槽位池真的有成员（防同类脏数据渲染出空面板）。
    public var isObtainable: Bool {
        obtainableRelicIDRange.contains(info.id)
            && !cheatRelicIDRange.contains(info.id)
            && !info.name.isEmpty
            && slots.contains { !$0.isEmpty && $0.poolSize > 0 }
    }
}

// MARK: - 索引

/// 词条反查的反向索引。构建一次即可反复查询。
public struct AffixLookupIndex: Sendable {
    /// 可搜索的词条条目，按 (sortId, effectId) 升序。
    public let affixes: [LookupAffix]
    /// 可搜索的遗物条目，按 id 升序。
    public let relics: [RelicLookupEntry]
    /// 遗物物品表是否可用。
    public let hasRelicData: Bool
    /// 池 → 成员 effectId（按 (sortId, effectId) 升序）。
    public let poolMembers: [Int: [Int]]
    /// 池 → 使用该池的遗物件数（只数正常可获得的遗物）。
    public let relicCountByPool: [Int: Int]

    private let affixByID: [Int: LookupAffix]
    private let relicByID: [Int: RelicLookupEntry]
    /// effectId → 含它的池 id（升序）。
    private let poolsByEffect: [Int: [Int]]
    /// 池 id → 使用该池的遗物槽位。
    private let slotsByPool: [Int: [SlotRef]]
    /// compatibilityId → 该互斥组的 effectId。
    private let conflictGroups: [Int: [Int]]

    private struct SlotRef: Hashable, Sendable {
        let relicID: Int
        let slotIndex: Int
        let role: RelicSlotRole
    }

    private struct HitKey: Hashable {
        let relicID: Int
        let role: RelicSlotRole
    }

    public init(catalog: AffixCatalog, relicData: RelicCatalog?) {
        // 1. 词条条目：词条库优先，extraAffixes 补齐物品表里出现过、词条库没有的 id
        var entries: [Int: LookupAffix] = [:]
        for affix in catalog.affixes {
            entries[affix.effectID] = LookupAffix(
                effectID: affix.effectID,
                name: affix.name,
                category: affix.category,
                explanation: affix.explanation,
                superposability: affix.superposability,
                compatibilityID: affix.compatibilityID,
                sortID: affix.sortID,
                poolIDs: affix.poolIDs.sorted(),
                isCurse: affix.isCurse,
                requiresCurse: affix.requiresCurse,
                inCatalog: true,
                searchText: affix.searchableText
            )
        }
        let extraCategory = "物品表补充"
        for extra in relicData?.extraAffixes ?? [] where entries[extra.effectID] == nil {
            entries[extra.effectID] = LookupAffix(
                effectID: extra.effectID,
                name: extra.name,
                category: extraCategory,
                explanation: "",
                superposability: "未知",
                compatibilityID: extra.compatibilityID,
                sortID: extra.sortID,
                poolIDs: [],
                isCurse: false,
                requiresCurse: false,
                inCatalog: false,
                // 搜索框写的是「词条名、别名、分类或 effectId」，分类也要能搜到
                searchText: "\(extra.name) \(extraCategory) \(extra.effectID)".foldedForSearch
            )
        }
        affixByID = entries
        let sortedAffixes = entries.values.sorted { lhs, rhs in
            lhs.sortID == rhs.sortID ? lhs.effectID < rhs.effectID : lhs.sortID < rhs.sortID
        }
        affixes = sortedAffixes

        // 2. 互斥组
        var groups: [Int: [Int]] = [:]
        for affix in sortedAffixes where affix.compatibilityID != -1 {
            groups[affix.compatibilityID, default: []].append(affix.effectID)
        }
        conflictGroups = groups

        guard let relicData else {
            hasRelicData = false
            relics = []
            relicByID = [:]
            poolMembers = [:]
            relicCountByPool = [:]
            poolsByEffect = [:]
            slotsByPool = [:]
            return
        }
        hasRelicData = true

        // 3. 池成员与 effectId → 池 的反向索引
        var members: [Int: [Int]] = [:]
        var byEffect: [Int: [Int]] = [:]
        members.reserveCapacity(relicData.pools.count)
        for (key, effectIDs) in relicData.pools {
            guard let poolID = Int(key) else { continue }
            let unique = Set(effectIDs).sorted { lhs, rhs in
                let sortL = entries[lhs]?.sortID ?? Int.max
                let sortR = entries[rhs]?.sortID ?? Int.max
                return sortL == sortR ? lhs < rhs : sortL < sortR
            }
            members[poolID] = unique
            for effectID in unique {
                byEffect[effectID, default: []].append(poolID)
            }
        }
        for key in byEffect.keys {
            byEffect[key]?.sort()
        }
        poolMembers = members
        poolsByEffect = byEffect

        // 4. 遗物 → 槽位池概览，以及池 → 遗物槽位
        var refs: [Int: [SlotRef]] = [:]
        var relicCounts: [Int: Int] = [:]
        var entryList: [RelicLookupEntry] = []
        entryList.reserveCapacity(relicData.relics.count)

        for info in relicData.relics.sorted(by: { $0.id < $1.id }) {
            var summaries: [RelicSlotSummary] = []
            var usedPools: Set<Int> = []
            for slotIndex in 0..<3 {
                let poolID = Self.slotValue(info.slots, slotIndex)
                let cursePoolID = Self.slotValue(info.curseSlots, slotIndex)
                let poolList = poolID == -1 ? [] : (members[poolID] ?? [])
                let cursePoolSize = cursePoolID == -1 ? 0 : (members[cursePoolID]?.count ?? 0)
                summaries.append(RelicSlotSummary(
                    slotIndex: slotIndex,
                    poolID: poolID,
                    poolSize: poolList.count,
                    cursePoolID: cursePoolID,
                    cursePoolSize: cursePoolSize,
                    previewEffectIDs: Array(poolList.prefix(8))
                ))
                if poolID != -1 {
                    refs[poolID, default: []].append(
                        SlotRef(relicID: info.id, slotIndex: slotIndex, role: .positive)
                    )
                    usedPools.insert(poolID)
                }
                if cursePoolID != -1 {
                    refs[cursePoolID, default: []].append(
                        SlotRef(relicID: info.id, slotIndex: slotIndex, role: .curse)
                    )
                    usedPools.insert(cursePoolID)
                }
            }
            let name = relicDisplayName(id: info.id, info: info)
            let kind = relicKindLabel(id: info.id, info: info)
            let entry = RelicLookupEntry(
                info: info,
                displayName: name,
                kindLabel: kind,
                colorLabel: relicColorLabel(info.color),
                isUnique: isUniqueRelicID(info.id),
                slots: summaries,
                fixedEffectIDs: Self.fixedEffects(slots: info.slots, members: members, affixes: entries),
                searchText: "\(name) \(kind) \(info.id)".foldedForSearch
            )
            // 可获得性只有 RelicLookupEntry.isObtainable 一个判定点
            if entry.isObtainable {
                for poolID in usedPools {
                    relicCounts[poolID, default: 0] += 1
                }
            }
            entryList.append(entry)
        }
        relics = entryList
        relicByID = Dictionary(entryList.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        slotsByPool = refs
        relicCountByPool = relicCounts
    }

    // MARK: 查询

    public func affix(_ effectID: Int) -> LookupAffix? { affixByID[effectID] }

    public func relic(_ relicID: Int) -> RelicLookupEntry? { relicByID[relicID] }

    /// 词条名；未知 id 回退为「未知词条 #id」。
    public func affixName(_ effectID: Int) -> String {
        affixByID[effectID]?.displayName ?? "未知词条 #\(effectID)"
    }

    /// 按名称 / 分类 / effectId / 别名搜索词条；`query` 为空时返回全部。
    public func searchAffixes(
        _ query: String,
        includeCurses: Bool = true,
        catalogOnly: Bool = false
    ) -> [LookupAffix] {
        let needle = query.foldedForSearch
        return affixes.filter { affix in
            if !includeCurses && affix.isCurse { return false }
            if catalogOnly && !affix.inCatalog { return false }
            return needle.isEmpty || affix.searchText.contains(needle)
        }
    }

    /// 按遗物名 / 种类 / id 搜索遗物；默认只给正常可获得的遗物。
    public func searchRelics(
        _ query: String,
        onlyObtainable: Bool = true,
        onlyDeep: Bool = false
    ) -> [RelicLookupEntry] {
        let needle = query.foldedForSearch
        return relics.filter { entry in
            if onlyObtainable && !entry.isObtainable { return false }
            if onlyDeep && !entry.deep { return false }
            return needle.isEmpty || entry.searchText.contains(needle)
        }
    }

    /// 同互斥组的其它词条。
    public func conflicts(with effectID: Int) -> [LookupAffix] {
        guard let affix = affixByID[effectID], affix.compatibilityID != -1 else { return [] }
        return (conflictGroups[affix.compatibilityID] ?? [])
            .filter { $0 != effectID }
            .compactMap { affixByID[$0] }
    }

    /// 完整反查结果；未知 effectId 返回 nil。
    public func report(for effectID: Int) -> AffixLookupReport? {
        guard let affix = affixByID[effectID] else { return nil }
        // 有遗物物品表时以池表为准；没有时退回词条库自带的 poolIds，
        // 这样「在哪个池里」至少还能回答。
        let pools = hasRelicData ? (poolsByEffect[effectID] ?? []) : affix.poolIDs

        let modeHits = affixLookupModes.map { mode in
            LookupModeHit(mode: mode, pools: mode.eligiblePoolIDs.map { poolHit($0, in: pools) })
        }
        let deepHits = deepPositiveLookupPools.map { poolHit($0, in: pools) }
        let curseHit = poolHit(deepCurseLookupPool, in: pools)
        let conflictList = conflicts(with: effectID)

        guard hasRelicData else {
            return AffixLookupReport(
                affix: affix,
                conflicts: conflictList,
                modeHits: modeHits,
                deepHits: deepHits,
                cursePoolHit: curseHit,
                poolIDs: pools,
                fixedRelics: [],
                randomRelics: [],
                kindCounts: [],
                hiddenRelicCount: 0,
                hasRelicData: false
            )
        }

        // 同一件遗物可能有多个槽位命中同一条词条，按 (遗物, 正/负面) 去重
        var buckets: [HitKey: (pools: Set<Int>, isFixed: Bool)] = [:]
        var order: [HitKey] = []
        for poolID in pools {
            let poolSize = poolMembers[poolID]?.count ?? 0
            for ref in slotsByPool[poolID] ?? [] {
                let key = HitKey(relicID: ref.relicID, role: ref.role)
                if buckets[key] == nil {
                    buckets[key] = (pools: [], isFixed: false)
                    order.append(key)
                }
                buckets[key]?.pools.insert(poolID)
                if poolSize == 1 { buckets[key]?.isFixed = true }
            }
        }

        var fixed: [RelicLookupHit] = []
        var random: [RelicLookupHit] = []
        var kindTally: [String: Int] = [:]
        var hidden = 0
        for key in order {
            guard let bucket = buckets[key], let entry = relicByID[key.relicID] else { continue }
            // 超范围 / 无名的参数行、作弊器区段遗物不展示，只计数
            guard entry.isObtainable else {
                hidden += 1
                continue
            }
            let hit = RelicLookupHit(
                relicID: entry.info.id,
                relicName: entry.displayName,
                kindLabel: entry.kindLabel,
                colorLabel: entry.colorLabel,
                deep: entry.deep,
                slotCount: entry.slotCount,
                poolIDs: bucket.pools.sorted(),
                role: key.role,
                isFixed: bucket.isFixed
            )
            if hit.isFixed { fixed.append(hit) } else { random.append(hit) }
            kindTally[entry.kindLabel, default: 0] += 1
        }
        fixed.sort { $0.relicID < $1.relicID }
        random.sort { $0.relicID < $1.relicID }

        return AffixLookupReport(
            affix: affix,
            conflicts: conflictList,
            modeHits: modeHits,
            deepHits: deepHits,
            cursePoolHit: curseHit,
            poolIDs: pools,
            fixedRelics: fixed,
            randomRelics: random,
            kindCounts: kindTally
                .map { LookupKindCount(kind: $0.key, count: $0.value) }
                .sorted { $0.count == $1.count ? $0.kind < $1.kind : $0.count > $1.count },
            hiddenRelicCount: hidden,
            hasRelicData: true
        )
    }

    private func poolHit(_ poolID: Int, in pools: [Int]) -> LookupPoolHit {
        LookupPoolHit(
            poolID: poolID,
            contains: pools.contains(poolID),
            memberCount: poolMembers[poolID]?.count ?? 0,
            relicCount: relicCountByPool[poolID] ?? 0
        )
    }

    // MARK: 构建辅助

    private static func slotValue(_ slots: [Int], _ index: Int) -> Int {
        guard slots.indices.contains(index) else { return -1 }
        let raw = slots[index]
        return raw <= 0 ? -1 : raw
    }

    /// 与 `RelicAuditor` 的 `officialFixedEffects` 同规则：全部非空槽都是单词条
    /// 固定池时可完全确定，按 (sortId, effectId) 升序补 -1 到 3 位；否则 nil。
    private static func fixedEffects(
        slots: [Int],
        members: [Int: [Int]],
        affixes: [Int: LookupAffix]
    ) -> [Int]? {
        var ids: [Int] = []
        for index in 0..<3 {
            let poolID = slotValue(slots, index)
            guard poolID != -1 else { continue }
            guard let list = members[poolID], list.count == 1 else { return nil }
            ids.append(list[0])
        }
        guard !ids.isEmpty, ids.allSatisfy({ affixes[$0] != nil }) else { return nil }
        var ordered = ids.sorted { lhs, rhs in
            let sortL = affixes[lhs]?.sortID ?? Int.max
            let sortR = affixes[rhs]?.sortID ?? Int.max
            return sortL == sortR ? lhs < rhs : sortL < sortR
        }
        while ordered.count < 3 { ordered.append(-1) }
        return ordered
    }
}
