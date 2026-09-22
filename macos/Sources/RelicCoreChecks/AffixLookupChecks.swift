import Foundation
import RelicCore

// 「词条反查」的自检：全部用内置 Resources 里的真实 affixes.json / relics.json，
// 不造假数据。失败时 throw CheckFailure。

/// 内置资源目录（macos/Sources/NightreignRelicChecker/Resources）。
private var lookupResourcesDirectory: URL {
    URL(fileURLWithPath: #filePath)          // …/Sources/RelicCoreChecks/AffixLookupChecks.swift
        .deletingLastPathComponent()         // …/Sources/RelicCoreChecks
        .deletingLastPathComponent()         // …/Sources
        .deletingLastPathComponent()         // …/macos
        .appendingPathComponent("Sources/NightreignRelicChecker/Resources", isDirectory: true)
}

private func lookupExpect(_ condition: Bool, _ message: String) throws {
    guard condition else { throw CheckFailure(description: message) }
}

/// 「词条反查」的全部检查；在 GameDataChecks 的列表里只占一行。
func runAffixLookupChecks() throws -> Int {
    let checks: [(name: String, run: () throws -> Int)] = [
        ("深夜 A 池与诅咒配对", checkAffixLookupDeepPoolA),
        ("深夜遗物模板的诅咒行", checkDeepCursePairing),
        ("唯一遗物固定词条", checkUniqueRelicFixedAffixes),
        ("索引与搜索一致性", checkAffixLookupIndexIntegrity),
        ("孔数层池与可获得性", checkPoolTiersAndObtainability),
        ("互斥组口径", checkConflictGroupScope),
        ("与 Windows 端对照", checkWindowsParitySamples),
        ("双端口径：互斥组对称 / 截断提示 / 深夜池说明 / 预览条数", checkAffixLookupParity)
    ]
    var total = 0
    for check in checks {
        let count = try check.run()
        total += count
        print("      · \(check.name)：\(count) 项")
    }
    return total
}

/// 真实内置数据 + 反向索引；四项检查共用，只载入并构建一次。
private struct LookupFixtures {
    let catalog: AffixCatalog
    let relicData: RelicCatalog
    let index: AffixLookupIndex
}

private var cachedLookupFixtures: LookupFixtures?

private func lookupFixtures() throws -> LookupFixtures {
    if let cachedLookupFixtures { return cachedLookupFixtures }
    let catalog = try CatalogLoader.load(
        from: lookupResourcesDirectory.appendingPathComponent("affixes.json")
    )
    let relicData = try RelicDataLoader.load(
        from: lookupResourcesDirectory.appendingPathComponent("relics.json")
    )
    let fixtures = LookupFixtures(
        catalog: catalog,
        relicData: relicData,
        index: AffixLookupIndex(catalog: catalog, relicData: relicData)
    )
    cachedLookupFixtures = fixtures
    return fixtures
}

/// 「提升物理攻击力＋３」（6001400）：深夜 A 池独占、需要诅咒、普通口径出不了。
private func checkAffixLookupDeepPoolA() throws -> Int {
    let fixtures = try lookupFixtures()
    let relicData = fixtures.relicData
    let index = fixtures.index
    var count = 0

    guard let report = index.report(for: 6_001_400) else {
        throw CheckFailure(description: "反查不到 effectId 6001400")
    }
    try lookupExpect(report.affix.name == "提升物理攻击力＋３",
                     "6001400 名称应为「提升物理攻击力＋３」，实际「\(report.affix.name)」")
    try lookupExpect(report.affix.requiresCurse, "6001400 应标记 requiresCurse")
    try lookupExpect(!report.affix.isCurse, "6001400 是正面词条，不应标记 isCurse")
    count += 3

    let deepByPool = Dictionary(report.deepHits.map { ($0.poolID, $0) }, uniquingKeysWith: { first, _ in first })
    try lookupExpect(deepByPool[2_000_000]?.contains == true, "6001400 应在深夜 A 池（2000000）")
    try lookupExpect(deepByPool[2_100_000]?.contains == false, "6001400 不应在深夜 B 池（2100000）")
    try lookupExpect(deepByPool[2_200_000]?.contains == false, "6001400 不应在深夜 C 池（2200000）")
    try lookupExpect(!report.cursePoolHit.contains, "6001400 是正面词条，不应在深夜诅咒池")
    count += 4

    let modes = Dictionary(report.modeHits.map { ($0.mode, $0) }, uniquingKeysWith: { first, _ in first })
    try lookupExpect(modes[.deepPositive]?.isAvailable == true, "6001400 应在「深夜正面」口径下可出")
    try lookupExpect(modes[.currentNormal]?.isAvailable == false, "6001400 不应在「普通 1.03」口径下可出")
    try lookupExpect(modes[.legacyNormal]?.isAvailable == false, "6001400 不应在「普通旧池」口径下可出")
    count += 3

    // 深夜 A 池只出现在深夜遗物上，且是 49 条成员的随机池：没有遗物固定带它
    try lookupExpect(report.fixedRelics.isEmpty, "6001400 不应有固定出它的正常遗物")
    try lookupExpect(!report.randomRelics.isEmpty, "6001400 应能在深夜遗物的随机池里出")
    try lookupExpect(report.randomRelics.allSatisfy(\.deep), "6001400 只应出现在深夜遗物上")
    try lookupExpect(report.randomRelics.allSatisfy { $0.role == .positive }, "6001400 应命中正面槽")
    try lookupExpect(report.hiddenRelicCount > 0,
                     "6001400 在物品表里另有超范围参数行（池 6001400），应被计入 hiddenRelicCount")
    count += 5

    // 与原始 JSON 对账：含 6001400 的池 == 手工扫描结果
    let rawPools = relicData.pools
        .filter { $0.value.contains(6_001_400) }
        .compactMap { Int($0.key) }
        .sorted()
    try lookupExpect(report.poolIDs == rawPools,
                     "6001400 命中的池应为 \(rawPools)，实际 \(report.poolIDs)")
    try lookupExpect(rawPools == [6_001_400, 2_000_000].sorted(),
                     "按当前数据，6001400 出现在深夜 A 池和同名的单条参数池里")
    count += 2

    // 深夜 A 池的 49 条成员应当全部标记 requiresCurse
    let poolA = index.poolMembers[2_000_000] ?? []
    try lookupExpect(poolA.count == 49, "深夜 A 池应有 49 条成员，实际 \(poolA.count)")
    try lookupExpect(poolA.allSatisfy { index.affix($0)?.requiresCurse == true },
                     "深夜 A 池的成员应全部需要诅咒")
    let poolB = index.poolMembers[2_100_000] ?? []
    let poolC = index.poolMembers[2_200_000] ?? []
    try lookupExpect(poolB.allSatisfy { index.affix($0)?.requiresCurse == false },
                     "深夜 B 池的成员不应需要诅咒")
    try lookupExpect(poolC.allSatisfy { index.affix($0)?.requiresCurse == false },
                     "深夜 C 池的成员不应需要诅咒")
    count += 4

    return count
}

/// 深夜遗物模板实证：某一行有诅咒槽 ⇔ 该行的正面槽是 A 池（2000000）。
/// 页面上「A 池 = 必定配一条诅咒」的说法依赖这一点。
private func checkDeepCursePairing() throws -> Int {
    let relicData = try lookupFixtures().relicData
    var deepCount = 0
    for relic in relicData.relics where relic.deep {
        deepCount += 1
        for row in 0..<3 {
            let slot = relic.slots.indices.contains(row) ? relic.slots[row] : -1
            let curse = relic.curseSlots.indices.contains(row) ? relic.curseSlots[row] : -1
            let isPoolA = slot == 2_000_000
            let hasCurse = curse != -1
            try lookupExpect(isPoolA == hasCurse,
                             "深夜遗物 \(relic.id) 第 \(row + 1) 行：A 池与诅咒槽应一一对应"
                                + "（slot=\(slot), curseSlot=\(curse)）")
            if hasCurse {
                try lookupExpect(curse == 3_000_000,
                                 "深夜遗物 \(relic.id) 第 \(row + 1) 行的诅咒槽应为 3000000，实际 \(curse)")
            }
        }
    }
    try lookupExpect(deepCount == 222, "深夜遗物应为 222 件，实际 \(deepCount)")
    return deepCount
}

/// 唯一遗物的固定词条：能正向拿到、也能被反查回来，且与审计器口径一致。
private func checkUniqueRelicFixedAffixes() throws -> Int {
    let fixtures = try lookupFixtures()
    let catalog = fixtures.catalog
    let relicData = fixtures.relicData
    let index = fixtures.index
    var count = 0

    // 1000「细腻的火燃情景」：单槽固定池 707121100 → 7121100「出击时，会持有“火焰壶”」
    guard let entry = index.relic(1000) else { throw CheckFailure(description: "遗物 1000 不在索引里") }
    try lookupExpect(entry.isUnique, "遗物 1000 应判定为唯一遗物")
    try lookupExpect(entry.kindLabel == "唯一遗物", "遗物 1000 的种类标签应为「唯一遗物」")
    try lookupExpect(entry.displayName == "细腻的火燃情景", "遗物 1000 名称应为「细腻的火燃情景」")
    try lookupExpect(entry.slots[0].poolID == 707_121_100 && entry.slots[0].isFixed,
                     "遗物 1000 第 1 槽应是单词条固定池 707121100")
    try lookupExpect(entry.fixedEffectIDs == [7_121_100, -1, -1],
                     "遗物 1000 的固定词条应为 [7121100, -1, -1]，实际 \(String(describing: entry.fixedEffectIDs))")
    count += 5

    // 反查方向：7121100 能查到遗物 1000 固定出
    guard let report = index.report(for: 7_121_100) else {
        throw CheckFailure(description: "反查不到 effectId 7121100")
    }
    try lookupExpect(report.affix.name == "出击时，会持有“火焰壶”",
                     "7121100 名称应为「出击时，会持有“火焰壶”」，实际「\(report.affix.name)」")
    try lookupExpect(report.fixedRelics.contains { $0.relicID == 1000 },
                     "7121100 的固定遗物列表里应含遗物 1000")
    try lookupExpect(report.randomRelics.contains { $0.relicID == 202 },
                     "7121100 也应能在普通商店遗物 202 的随机池里出")
    try lookupExpect(report.fixedRelics.allSatisfy { $0.isFixed },
                     "固定遗物列表里的命中都应标记 isFixed")
    try lookupExpect(report.randomRelics.allSatisfy { !$0.isFixed },
                     "随机遗物列表里的命中都不应标记 isFixed")
    count += 5

    // 每件唯一遗物都应能算出固定词条，且与 RelicAuditor 的 officialEffects 完全一致
    let auditContext = RelicAuditContext(catalog: catalog, relicData: relicData)
    let auditor = RelicAuditor()
    var uniqueCount = 0
    for entry in index.relics where entry.isUnique {
        uniqueCount += 1
        guard let fixed = entry.fixedEffectIDs else {
            throw CheckFailure(description: "唯一遗物 \(entry.id) 算不出固定词条")
        }
        // 把词条全部清空 → 审计必然失败并给出官方固定词条
        let tampered = SaveRelic(index: 0, itemID: entry.id, effects: [-1, -1, -1], curses: [-1, -1, -1])
        let result = auditor.audit(tampered, context: auditContext)
        try lookupExpect(result.status == .invalid, "唯一遗物 \(entry.id) 清空词条后应判为非法")
        try lookupExpect(result.officialEffects == fixed,
                         "唯一遗物 \(entry.id) 的固定词条应与审计器一致："
                            + "索引 \(fixed)，审计器 \(String(describing: result.officialEffects))")
    }
    try lookupExpect(uniqueCount == 120, "唯一遗物应为 120 件，实际 \(uniqueCount)")
    count += uniqueCount + 1

    return count
}

/// 索引与搜索的基本一致性，以及遗物物品表缺失时的降级行为。
private func checkAffixLookupIndexIntegrity() throws -> Int {
    let fixtures = try lookupFixtures()
    let catalog = fixtures.catalog
    let relicData = fixtures.relicData
    let index = fixtures.index
    var count = 0

    try lookupExpect(index.hasRelicData, "有遗物物品表时 hasRelicData 应为 true")
    try lookupExpect(index.relics.count == relicData.relics.count,
                     "索引遗物件数应与物品表一致")
    try lookupExpect(index.poolMembers.count == relicData.pools.count,
                     "索引池数应与物品表一致")
    try lookupExpect(index.affixes.count == catalog.affixes.count + relicData.extraAffixes.count,
                     "词条条目应为 词条库 ∪ extraAffixes，实际 \(index.affixes.count)")
    try lookupExpect(index.affixes.contains { !$0.inCatalog },
                     "应存在只来自 extraAffixes 的条目")
    count += 5

    // 排序：按 (sortId, effectId) 升序
    var previous: (Int, Int)? = nil
    for affix in index.affixes {
        if let previous {
            let ordered = previous.0 < affix.sortID || (previous.0 == affix.sortID && previous.1 < affix.effectID)
            try lookupExpect(ordered, "词条条目应按 (sortId, effectId) 升序，\(previous) 之后出现 \(affix.effectID)")
        }
        previous = (affix.sortID, affix.effectID)
    }
    count += 1

    // 搜索：折叠后能命中（全角＋、大小写、空格）
    try lookupExpect(index.searchAffixes("提升物理攻击力").contains { $0.effectID == 6_001_400 },
                     "按名称搜索应命中 6001400")
    try lookupExpect(index.searchAffixes("6001400").contains { $0.effectID == 6_001_400 },
                     "按 effectId 搜索应命中 6001400")
    try lookupExpect(index.searchAffixes("提升物理攻击力+3").contains { $0.effectID == 6_001_400 },
                     "半角 + 与阿拉伯数字应能折叠命中全角写法")
    try lookupExpect(index.searchRelics("细腻的火燃情景").contains { $0.id == 1000 },
                     "按遗物名搜索应命中遗物 1000")
    let obtainable = index.searchRelics("")
    try lookupExpect(obtainable.count == 768,
                     "正常可获得的遗物应为 768 件（1397 件里滤掉超范围 / 无名参数行与"
                        + "20000-30035 作弊器区段），实际 \(obtainable.count)")
    // 可获得的遗物不允许有空成员的槽位池，否则详情面板会渲染出「随机 0 条」的空面板
    for entry in obtainable {
        try lookupExpect(entry.slots.contains { !$0.isEmpty && $0.poolSize > 0 },
                         "可查遗物 \(entry.id)「\(entry.displayName)」至少要有一个非空槽位池")
        for slot in entry.slots where !slot.isEmpty {
            try lookupExpect(slot.poolSize > 0,
                             "可查遗物 \(entry.id)「\(entry.displayName)」第 \(slot.slotIndex + 1) 槽"
                                + "指向空池 \(slot.poolID)")
        }
    }
    // 作弊器区段（RelicAudit 第 2 条）：物品表里确实有这些遗物，但一律不可查
    let cheats = index.relics.filter { cheatRelicIDRange.contains($0.id) }
    try lookupExpect(cheats.count == 72, "物品表里 20000-30035 区段应有 72 件，实际 \(cheats.count)")
    try lookupExpect(cheats.allSatisfy { !$0.isObtainable },
                     "作弊器区段的遗物不应判为正常可获得")
    try lookupExpect(cheats.allSatisfy { !$0.info.name.isEmpty },
                     "作弊器区段的遗物有名字，单靠「有没有名字」滤不掉，必须显式排除区段")
    try lookupExpect(index.searchRelics("", onlyObtainable: false).contains { $0.id == 20_000 },
                     "关闭过滤后仍应能看到作弊器区段的遗物")
    try lookupExpect(index.searchRelics("", onlyObtainable: false).count == index.relics.count,
                     "关闭过滤后应返回物品表全部条目")
    try lookupExpect(index.searchRelics("", onlyDeep: true).allSatisfy(\.deep),
                     "onlyDeep 应只保留深夜遗物")
    count += 11 + obtainable.count

    // 搜索框写的是「词条名、别名、分类或 effectId」：物品表补充条目也要能按分类搜到
    let extras = index.affixes.filter { !$0.inCatalog }
    try lookupExpect(!extras.isEmpty, "应存在只来自 extraAffixes 的条目")
    try lookupExpect(index.searchAffixes("物品表补充").count == extras.count,
                     "按分类「物品表补充」应搜到全部 \(extras.count) 条补充词条，"
                        + "实际 \(index.searchAffixes("物品表补充").count)")
    count += 2

    // 互斥组：6001400 的同组词条都应有相同 compatibilityId，且不含自己
    let conflicts = index.conflicts(with: 6_001_400)
    try lookupExpect(!conflicts.isEmpty, "6001400 应有互斥组成员")
    try lookupExpect(conflicts.allSatisfy { $0.compatibilityID == 100 },
                     "6001400 的互斥组成员 compatibilityId 应都为 100")
    try lookupExpect(!conflicts.contains { $0.effectID == 6_001_400 }, "互斥组不应包含自己")
    // compatibilityId == -1 不成组
    try lookupExpect(index.conflicts(with: 7_121_100).isEmpty || index.affix(7_121_100)?.compatibilityID != -1,
                     "compatibilityId 为 -1 的词条不应有互斥组")
    count += 4

    // 诅咒词条：应命中深夜诅咒池，并挂在深夜遗物的诅咒槽上
    guard let curse = index.affixes.first(where: { $0.isCurse }),
          let curseReport = index.report(for: curse.effectID) else {
        throw CheckFailure(description: "词条库里应至少有一条负面词条")
    }
    try lookupExpect(curseReport.cursePoolHit.contains,
                     "负面词条 \(curse.effectID) 应在深夜诅咒池里")
    try lookupExpect(curseReport.randomRelics.allSatisfy { $0.role == .curse && $0.deep },
                     "负面词条只应挂在深夜遗物的诅咒槽上")
    count += 2

    // 降级：没有遗物物品表时只剩词条说明
    let bare = AffixLookupIndex(catalog: catalog, relicData: nil)
    try lookupExpect(!bare.hasRelicData, "没有遗物物品表时 hasRelicData 应为 false")
    try lookupExpect(bare.relics.isEmpty, "没有遗物物品表时遗物列表应为空")
    try lookupExpect(bare.affixes.count == catalog.affixes.count,
                     "没有遗物物品表时词条条目应只有词条库的 \(catalog.affixes.count) 条")
    guard let bareReport = bare.report(for: 6_001_400) else {
        throw CheckFailure(description: "降级模式下也应能反查到 6001400 的说明")
    }
    try lookupExpect(!bareReport.hasRelicData, "降级模式的报告 hasRelicData 应为 false")
    try lookupExpect(bareReport.totalRelicCount == 0, "降级模式不应给出任何遗物")
    try lookupExpect(!bareReport.conflicts.isEmpty, "降级模式仍应能给出互斥组")
    // 没有物品表时用词条库自带的 poolIds 兜底，「在哪个池里」仍能回答
    try lookupExpect(bareReport.poolIDs == [2_000_000],
                     "降级模式应退回词条库的 poolIds，实际 \(bareReport.poolIDs)")
    try lookupExpect(bareReport.deepHits.first(where: { $0.poolID == 2_000_000 })?.contains == true,
                     "降级模式下 6001400 仍应判定在深夜 A 池")
    try lookupExpect(bareReport.deepHits.allSatisfy { $0.memberCount == 0 },
                     "降级模式不知道池有多大，memberCount 应为 0")
    count += 9

    return count
}

/// 孔数层池的实证：100/200/300（以及 110/210/310）是按「孔数」分层的嵌套池，
/// 不是「第 1/2/3 槽」——3 孔遗物的 slots 数组恰好是倒过来的 [300, 200, 100]。
/// 页面上的池标签因此只能写「N 孔层」，写「第 N 槽」会和槽序号自相矛盾。
private func checkPoolTiersAndObtainability() throws -> Int {
    let fixtures = try lookupFixtures()
    let index = fixtures.index
    var count = 0

    for tiers in [[100, 200, 300], [110, 210, 310]] {
        let sets = tiers.map { Set(index.poolMembers[$0] ?? []) }
        try lookupExpect(sets.allSatisfy { !$0.isEmpty }, "孔数层池 \(tiers) 都应有成员")
        try lookupExpect(sets[0].isSubset(of: sets[1]) && sets[1].isSubset(of: sets[2]),
                         "孔数层池应嵌套：\(tiers[0]) ⊆ \(tiers[1]) ⊆ \(tiers[2])")
        count += 2
    }

    // 3 孔遗物的槽位顺序与孔数层正好相反：第 1 个槽位用的是 3 孔层池
    var threeSlotCount = 0
    for entry in index.searchRelics("") where !entry.deep {
        let pools = entry.slots.filter { !$0.isEmpty }.map(\.poolID)
        guard pools.count == 3, pools.allSatisfy({ [100, 200, 300, 110, 210, 310].contains($0) }) else { continue }
        threeSlotCount += 1
        try lookupExpect(pools == [300, 200, 100] || pools == [310, 210, 110],
                         "3 孔遗物 \(entry.id) 的 slots 应为 [300,200,100] / [310,210,110]，实际 \(pools)")
    }
    try lookupExpect(threeSlotCount > 0, "应存在使用孔数层池的 3 孔遗物")
    count += threeSlotCount + 1

    // 池标签不能带槽序号，否则会和 RelicSlotRow 的「第 N 槽」撞车
    for poolID in [100, 200, 300, 110, 210, 310] {
        let label = affixPoolLabel(poolID)
        try lookupExpect(!label.contains("槽"), "孔数层池 \(poolID) 的标签不应含「槽」，实际「\(label)」")
        try lookupExpect(label.contains("孔层"), "孔数层池 \(poolID) 的标签应写「N 孔层」，实际「\(label)」")
        count += 2
    }

    return count
}

/// 互斥组的范围：只算「能出现在遗物上」的词条，与 `RelicAuditor` 第 6 条同口径。
/// 物品表里有一千多条从不进任何槽位池的效果共用 compatibilityId 100，
/// 算进来会把最大互斥组从 102 条撑到 1128 条。
private func checkConflictGroupScope() throws -> Int {
    let fixtures = try lookupFixtures()
    let catalog = fixtures.catalog
    let index = fixtures.index
    var count = 0

    // 最大互斥组：词条库里 compatibilityId 100 有 102 条
    var catalogGroupSizes: [Int: Int] = [:]
    for affix in catalog.affixes where affix.compatibilityID != -1 {
        catalogGroupSizes[affix.compatibilityID, default: 0] += 1
    }
    guard let biggest = catalogGroupSizes.max(by: { $0.value < $1.value }) else {
        throw CheckFailure(description: "词条库里应存在互斥组")
    }
    try lookupExpect(biggest.key == 100 && biggest.value == 102,
                     "最大互斥组应为 compatibilityId 100 的 102 条，实际 \(biggest)")
    try lookupExpect(biggest.value > affixLookupConflictLimit,
                     "最大互斥组超过页面默认列出的 \(affixLookupConflictLimit) 条，必须能就地展开")
    count += 2

    let conflicts = index.conflicts(with: 6_001_400)
    try lookupExpect(conflicts.count + 1 == 102,
                     "6001400 的互斥组应为 102 条（含自己），实际 \(conflicts.count + 1)")
    count += 1

    // 池里从没出现过的 extraAffixes 不算互斥对象
    var pooled: Set<Int> = []
    for members in index.poolMembers.values { pooled.formUnion(members) }
    let catalogIDs = Set(catalog.affixes.map(\.effectID))
    let strays = index.affixes.filter {
        $0.compatibilityID == 100 && !$0.inCatalog && !pooled.contains($0.effectID)
    }
    try lookupExpect(strays.count > 900,
                     "物品表里应有大量不进池、却挂着 compatibilityId 100 的效果，实际 \(strays.count)")
    let conflictIDs = Set(conflicts.map(\.effectID))
    try lookupExpect(strays.allSatisfy { !conflictIDs.contains($0.effectID) },
                     "不进任何槽位池的效果不应出现在互斥组里")
    count += 2

    // 反过来：进了池的 extraAffixes 必须算进互斥组（存档审计会判它们互斥）
    var checkedPairs = 0
    for affix in index.affixes where !affix.inCatalog && affix.compatibilityID != -1 && pooled.contains(affix.effectID) {
        guard let host = catalog.affixes.first(where: { $0.compatibilityID == affix.compatibilityID }) else { continue }
        checkedPairs += 1
        try lookupExpect(index.conflicts(with: host.effectID).contains { $0.effectID == affix.effectID },
                         "池内的物品表词条 \(affix.effectID) 应算进互斥组 \(affix.compatibilityID)")
    }
    try lookupExpect(checkedPairs > 0, "应存在与词条库共组的池内 extraAffixes")
    count += checkedPairs + 1

    // 全库兜底：互斥组成员要么在词条库里，要么被某个槽位池引用
    for affix in index.affixes where affix.compatibilityID != -1 {
        for peer in index.conflicts(with: affix.effectID) {
            try lookupExpect(catalogIDs.contains(peer.effectID) || pooled.contains(peer.effectID),
                             "互斥组不应包含既不在词条库、也不进任何池的词条 \(peer.effectID)")
        }
    }
    count += 1

    // 没有物品表时退回词条库内的同组词条
    let bare = AffixLookupIndex(catalog: catalog, relicData: nil)
    try lookupExpect(bare.conflicts(with: 6_001_400).count + 1 == 102,
                     "降级模式下互斥组仍应是词条库里的 102 条")
    count += 1

    return count
}

// MARK: - 双端对照

/// 一条词条在反查页上的全部结论，两端必须逐字段相同。
private struct AffixParitySample {
    let effectID: Int
    let name: String
    /// [普通 1.03, 普通旧池, 深夜正面] 的可掉落判定
    let modes: [Bool]
    /// 深夜 [A, B, C] 池归属
    let deepPools: [Bool]
    let inCursePool: Bool
    let requiresCurse: Bool
    let isCurse: Bool
    /// 固定出这条词条的遗物 ID（正常可获得的）
    let fixedRelicIDs: [Int]
    let randomRelicCount: Int
    /// 不会正常获得、因而未列出的命中条数
    let hiddenCount: Int
    /// 互斥组条数（含自己）；无互斥组为 0
    let conflictGroupSize: Int
}

/// 一件遗物在反查页上的全部结论，两端必须逐字段相同。
private struct RelicParitySample {
    let relicID: Int
    let name: String
    let kindLabel: String
    let colorLabel: String
    let deep: Bool
    let isUnique: Bool
    let slotCount: Int
    let curseSlotCount: Int
    /// 三个正面槽的池 id（空槽为 -1）
    let slotPools: [Int]
    let slotLabels: [String]
    let slotSizes: [Int]
    /// 深夜遗物按池归并后的 [池 id, 本件条数]；非深夜遗物为 nil
    let deepGroups: [[Int]]?
    let fixedEffectIDs: [Int]?
}

/// 与 Windows 端 `renderer/pages/lookup.js` 对照的固定样本（5 条词条 + 3 件遗物）。
///
/// 同一份内置数据，两端对同一输入必须给出同样的结论：三种口径的可掉落判定、
/// 深夜 A/B/C 池说明、固定 vs 随机池可出的区分、遗物种类/颜色标签、孔数层池标签、
/// 深夜遗物的按池归并，以及「不会正常获得」的剔除条数。
/// Windows 端在 `tests/lookup_index.test.mjs` 的同名用例里断言同一张表。
private func checkWindowsParitySamples() throws -> Int {
    let index = try lookupFixtures().index
    var count = 0

    let affixSamples: [AffixParitySample] = [
        AffixParitySample(
            effectID: 7_000_000, name: "生命力＋１",
            modes: [true, true, false], deepPools: [false, false, false],
            inCursePool: false, requiresCurse: false, isCurse: false,
            fixedRelicIDs: [10002, 11003], randomRelicCount: 432,
            hiddenCount: 1, conflictGroupSize: 4
        ),
        AffixParitySample(
            effectID: 6_001_400, name: "提升物理攻击力＋３",
            modes: [false, false, true], deepPools: [true, false, false],
            inCursePool: false, requiresCurse: true, isCurse: false,
            fixedRelicIDs: [], randomRelicCount: 144,
            hiddenCount: 1, conflictGroupSize: 102
        ),
        AffixParitySample(
            effectID: 6_003_000, name: "提升对中毒的抵抗力＋１",
            modes: [false, false, true], deepPools: [false, true, true],
            inCursePool: false, requiresCurse: false, isCurse: false,
            fixedRelicIDs: [], randomRelicCount: 144,
            hiddenCount: 1, conflictGroupSize: 3
        ),
        AffixParitySample(
            effectID: 6_820_000, name: "受到损伤时，会累积中毒量表",
            modes: [false, false, false], deepPools: [false, false, false],
            inCursePool: true, requiresCurse: false, isCurse: true,
            fixedRelicIDs: [], randomRelicCount: 144,
            hiddenCount: 1, conflictGroupSize: 1
        ),
        AffixParitySample(
            effectID: 7_121_100, name: "出击时，会持有“火焰壶”",
            modes: [true, true, false], deepPools: [false, false, false],
            inCursePool: false, requiresCurse: false, isCurse: false,
            fixedRelicIDs: [1000], randomRelicCount: 432,
            hiddenCount: 2, conflictGroupSize: 1
        )
    ]

    let modeOrder: [CheckMode] = [.currentNormal, .legacyNormal, .deepPositive]
    try lookupExpect(affixLookupModes == modeOrder,
                     "反查页应按「普通 1.03 / 普通旧池 / 深夜正面」三种口径展示")
    count += 1

    for sample in affixSamples {
        guard let report = index.report(for: sample.effectID) else {
            throw CheckFailure(description: "反查不到 effectId \(sample.effectID)")
        }
        try lookupExpect(report.affix.name == sample.name,
                         "\(sample.effectID) 名称应为「\(sample.name)」，实际「\(report.affix.name)」")
        let modeHits = Dictionary(report.modeHits.map { ($0.mode, $0.isAvailable) },
                                  uniquingKeysWith: { first, _ in first })
        try lookupExpect(modeOrder.map { modeHits[$0] ?? false } == sample.modes,
                         "\(sample.effectID) 的三口径可掉落判定应为 \(sample.modes)")
        let deepByPool = Dictionary(report.deepHits.map { ($0.poolID, $0.contains) },
                                    uniquingKeysWith: { first, _ in first })
        try lookupExpect(deepPositiveLookupPools.map { deepByPool[$0] ?? false } == sample.deepPools,
                         "\(sample.effectID) 的深夜 A/B/C 归属应为 \(sample.deepPools)")
        try lookupExpect(report.cursePoolHit.contains == sample.inCursePool,
                         "\(sample.effectID) 的诅咒池归属应为 \(sample.inCursePool)")
        try lookupExpect(report.affix.requiresCurse == sample.requiresCurse,
                         "\(sample.effectID) 的 requiresCurse 应为 \(sample.requiresCurse)")
        try lookupExpect(report.affix.isCurse == sample.isCurse,
                         "\(sample.effectID) 的 isCurse 应为 \(sample.isCurse)")
        try lookupExpect(report.fixedRelics.map(\.relicID) == sample.fixedRelicIDs,
                         "\(sample.effectID) 的固定出处应为 \(sample.fixedRelicIDs)，"
                            + "实际 \(report.fixedRelics.map(\.relicID))")
        try lookupExpect(report.randomRelics.count == sample.randomRelicCount,
                         "\(sample.effectID) 的随机池出处应为 \(sample.randomRelicCount) 件，"
                            + "实际 \(report.randomRelics.count)")
        try lookupExpect(report.hiddenRelicCount == sample.hiddenCount,
                         "\(sample.effectID) 被剔除的不可正常获得条目应为 \(sample.hiddenCount) 条，"
                            + "实际 \(report.hiddenRelicCount)")
        let groupSize = report.affix.compatibilityID == -1 ? 0 : report.conflicts.count + 1
        try lookupExpect(groupSize == sample.conflictGroupSize,
                         "\(sample.effectID) 的互斥组应为 \(sample.conflictGroupSize) 条，实际 \(groupSize)")
        // 列出来的遗物一律是正常可获得的
        for hit in report.fixedRelics + report.randomRelics {
            try lookupExpect(index.relic(hit.relicID)?.isObtainable == true,
                             "\(sample.effectID) 列出了不会正常获得的遗物 \(hit.relicID)")
        }
        count += 10
    }

    let relicSamples: [RelicParitySample] = [
        RelicParitySample(
            relicID: 202, name: "辽阔的火燃情景", kindLabel: "商店遗物", colorLabel: "红",
            deep: false, isUnique: false, slotCount: 3, curseSlotCount: 0,
            slotPools: [310, 210, 110],
            slotLabels: ["1.03 · 3 孔层", "1.03 · 2 孔层", "1.03 · 1 孔层"],
            slotSizes: [340, 340, 340], deepGroups: nil, fixedEffectIDs: nil
        ),
        RelicParitySample(
            relicID: 1000, name: "细腻的火燃情景", kindLabel: "唯一遗物", colorLabel: "红",
            deep: false, isUnique: true, slotCount: 1, curseSlotCount: 0,
            slotPools: [707_121_100, -1, -1],
            slotLabels: ["池 707121100", "", ""],
            slotSizes: [1, 0, 0], deepGroups: nil, fixedEffectIDs: [7_121_100]
        ),
        RelicParitySample(
            relicID: 2_000_002, name: "辽阔的火燃暗淡情景", kindLabel: "深夜遗物", colorLabel: "红",
            deep: true, isUnique: false, slotCount: 3, curseSlotCount: 1,
            slotPools: [2_000_000, 2_100_000, 2_100_000],
            slotLabels: ["深夜 A 池", "深夜 B 池", "深夜 B 池"],
            slotSizes: [49, 277, 277],
            deepGroups: [[2_000_000, 1], [2_100_000, 2]], fixedEffectIDs: nil
        )
    ]

    for sample in relicSamples {
        guard let entry = index.relic(sample.relicID) else {
            throw CheckFailure(description: "索引里没有遗物 \(sample.relicID)")
        }
        try lookupExpect(entry.displayName == sample.name,
                         "遗物 \(sample.relicID) 名称应为「\(sample.name)」")
        try lookupExpect(entry.kindLabel == sample.kindLabel,
                         "遗物 \(sample.relicID) 的种类标签应为「\(sample.kindLabel)」")
        try lookupExpect(entry.colorLabel == sample.colorLabel,
                         "遗物 \(sample.relicID) 的颜色标签应为「\(sample.colorLabel)」")
        try lookupExpect(entry.deep == sample.deep && entry.isUnique == sample.isUnique,
                         "遗物 \(sample.relicID) 的深夜 / 唯一标记两端不一致")
        try lookupExpect(entry.isObtainable, "遗物 \(sample.relicID) 应判为正常可获得")
        try lookupExpect(entry.slotCount == sample.slotCount,
                         "遗物 \(sample.relicID) 应有 \(sample.slotCount) 孔")
        try lookupExpect(entry.slots.filter(\.hasCurse).count == sample.curseSlotCount,
                         "遗物 \(sample.relicID) 的诅咒槽数应为 \(sample.curseSlotCount)")
        try lookupExpect(entry.slots.map(\.poolID) == sample.slotPools,
                         "遗物 \(sample.relicID) 的槽位池应为 \(sample.slotPools)")
        try lookupExpect(
            entry.slots.map { $0.isEmpty ? "" : affixPoolLabel($0.poolID) } == sample.slotLabels,
            "遗物 \(sample.relicID) 的槽位池标签应为 \(sample.slotLabels)"
        )
        try lookupExpect(entry.slots.map(\.poolSize) == sample.slotSizes,
                         "遗物 \(sample.relicID) 的槽位池成员数应为 \(sample.slotSizes)")
        try lookupExpect(entry.fixedEffectIDs?.filter { $0 != -1 } == sample.fixedEffectIDs,
                         "遗物 \(sample.relicID) 的固定词条应为 \(String(describing: sample.fixedEffectIDs))")
        count += 11

        // 深夜遗物：按池归并，不给槽序号
        if let expected = sample.deepGroups {
            var tally: [Int: Int] = [:]
            for slot in entry.slots where !slot.isEmpty { tally[slot.poolID, default: 0] += 1 }
            let groups = tally.keys.sorted().map { [$0, tally[$0] ?? 0] }
            try lookupExpect(groups == expected,
                             "深夜遗物 \(sample.relicID) 的按池归并应为 \(expected)，实际 \(groups)")
            // 槽位模板只保证 A 槽数 = 诅咒槽数
            let aCount = entry.slots.filter { $0.poolID == 2_000_000 }.count
            try lookupExpect(aCount == sample.curseSlotCount,
                             "深夜遗物 \(sample.relicID) 的 A 槽数应等于诅咒槽数")
            count += 2
        }
    }

    try lookupExpect(index.searchRelics("").count == 768,
                     "两端的「可查遗物」件数都应是 768 件")
    count += 1

    return count
}

// MARK: - 双端口径 / 文案一致性（与 Windows 端 pages/lookup.js 逐字对照）

/// ④ 互斥组的对称性、⑤ 截断提示、⑥ 深夜池说明与槽位池预览条数。
func checkAffixLookupParity() throws -> Int {
    let fixtures = try lookupFixtures()
    let index = fixtures.index
    var count = 0

    // ④ 互斥组必须对称：A 在 B 的组里 ⇔ B 在 A 的组里。
    //    「不会出现在任何遗物槽位池里」的词条，两个方向都不算互斥对象。
    let unreachable = index.affixes.filter { $0.compatibilityID != -1 && !$0.appearsOnRelic }
    try lookupExpect(
        unreachable.count > 900,
        "物品表里应有大量不进池、却挂着 compatibilityId 的效果，实际 \(unreachable.count)"
    )
    count += 1
    for affix in unreachable.prefix(40) {
        try lookupExpect(
            index.conflicts(with: affix.effectID).isEmpty,
            "不可达词条 \(affix.effectID) 不该反查出互斥对象"
        )
        count += 1
    }
    let reachable = index.affixes.filter { $0.compatibilityID != -1 && $0.appearsOnRelic }
    for affix in reachable.prefix(60) {
        for peer in index.conflicts(with: affix.effectID).prefix(6) {
            try lookupExpect(
                index.conflicts(with: peer.effectID).contains { $0.effectID == affix.effectID },
                "互斥组不对称：\(affix.effectID) 的组里有 \(peer.effectID)，反过来没有"
            )
            count += 1
        }
    }
    // 修正之后互斥池 100 仍是 102 条（不可达的那一千多条没有被塞回来）
    try lookupExpect(
        index.conflicts(with: 6_001_400).count + 1 == 102,
        "6001400 的互斥组仍应是 102 条（含自己）"
    )
    // 没有遗物物品表时只剩词条库条目，它们本来就都能出现在遗物上
    let catalogOnly = AffixLookupIndex(catalog: fixtures.catalog, relicData: nil)
    try lookupExpect(
        catalogOnly.affixes.allSatisfy(\.appearsOnRelic),
        "没有物品表时全部词条库条目都应算「能出现在遗物上」"
    )
    try lookupExpect(
        !catalogOnly.conflicts(with: 6_001_400).isEmpty,
        "没有物品表时仍应能给出词条库内的互斥组"
    )
    count += 3

    // ④ 「互斥组」一栏四支的文案与分支顺序（Windows 端 conflictBranch / 三串文案）。
    //    这几串此前只在 Windows 端被断言，Swift 这边单方面改一个字也不会被拦住。
    try lookupExpect(
        affixLookupUnreachableConflictNote
            == "这条词条不会出现在任何遗物的槽位池里，不参与互斥判定：互斥只约束「能同时出现在一件遗物上」的词条。",
        "不可达词条的说明，实际 \(affixLookupUnreachableConflictNote)"
    )
    try lookupExpect(
        affixLookupNoConflictGroupNote == "该词条没有互斥组，可与任意其他词条同时出现（仍不能与自身重复）。",
        "compatibilityID = -1 的说明，实际 \(affixLookupNoConflictGroupNote)"
    )
    try lookupExpect(
        affixLookupLoneConflictNote(100) == "互斥池 100 内只有这一条词条，没有互斥对象。",
        "互斥池里只有自己时的说明，实际 \(affixLookupLoneConflictNote(100))"
    )
    count += 3

    // 分支顺序：不可达优先于 compatibilityID == -1。两者同时成立的效果，
    // 上一轮 macOS 说「不参与互斥判定」、Windows 说「可与任意其他词条同时出现」，
    // 正好是相反的口径；这一支此前两端的测试都没覆盖。
    let unreachableNoGroup = index.affixes.filter { $0.compatibilityID == -1 && !$0.appearsOnRelic }
    try lookupExpect(
        unreachableNoGroup.count > 100,
        "物品表里应有上百条「不可达且没有互斥池」的效果，实际 \(unreachableNoGroup.count)"
    )
    try lookupExpect(
        unreachableNoGroup.contains { $0.effectID == 11001 },
        "effectId 11001（使用圣杯瓶时，连同恢复周围我方人物）应在这一支里"
    )
    count += 2
    for affix in unreachableNoGroup.prefix(40) {
        try lookupExpect(
            AffixConflictBranch.of(
                reachable: affix.appearsOnRelic,
                compatibilityID: affix.compatibilityID,
                peerCount: index.conflicts(with: affix.effectID).count
            ) == .unreachable,
            "\(affix.effectID)「不可达 + compatibilityID = -1」应走不可达那一支"
        )
        count += 1
    }
    // 其余三支也各取一条真实数据验一遍
    if let loner = index.affixes.first(where: { $0.compatibilityID == -1 && $0.appearsOnRelic }) {
        try lookupExpect(
            AffixConflictBranch.of(
                reachable: true, compatibilityID: loner.compatibilityID,
                peerCount: index.conflicts(with: loner.effectID).count
            ) == .noGroup,
            "\(loner.effectID)「能出现在遗物上 + compatibilityID = -1」应走「没有互斥组」"
        )
        count += 1
    }
    if let grouped = index.affixes.first(where: { $0.effectID == 6_001_400 }) {
        try lookupExpect(
            AffixConflictBranch.of(
                reachable: grouped.appearsOnRelic,
                compatibilityID: grouped.compatibilityID,
                peerCount: index.conflicts(with: grouped.effectID).count
            ) == .peers,
            "6001400 应走互斥组列表那一支"
        )
        try lookupExpect(
            AffixConflictBranch.of(
                reachable: true, compatibilityID: grouped.compatibilityID, peerCount: 0
            ) == .lone,
            "同一个互斥池里只剩自己时应走 lone"
        )
        count += 2
    }

    // ⑤ 截断提示文案（Windows 端 hitCountText）
    try lookupExpect(
        affixLookupHitCountText(total: 7, shown: 7) == "共 7 件 · 已显示全部 7 件",
        "全部显示时的提示文案"
    )
    try lookupExpect(
        affixLookupHitCountText(total: 0, shown: 0) == "共 0 件 · 已显示全部 0 件",
        "空结果的提示文案"
    )
    try lookupExpect(
        affixLookupHitCountText(total: 300, shown: 120) == "共 300 件 · 已显示 120 件（另有 180 件未列出）",
        "截断时的提示文案，实际 \(affixLookupHitCountText(total: 300, shown: 120))"
    )
    try lookupExpect(
        affixLookupHitCountText(total: 300, shown: 900) == "共 300 件 · 已显示全部 300 件",
        "显示数不会超过总数"
    )
    try lookupExpect(
        affixLookupHitCountText(total: 300, shown: -5) == "共 300 件 · 已显示 0 件（另有 300 件未列出）",
        "负数按 0 处理"
    )
    count += 5
    // 真实数据：生命力＋１ 的随机池命中超过一屏，提示得说清楚被截断了多少
    if let report = index.report(for: 7_000_000) {
        let total = report.randomRelics.count
        try lookupExpect(total > affixLookupRowLimit, "生命力＋１ 的随机池命中应超过默认列出的件数")
        try lookupExpect(
            affixLookupHitCountText(total: total, shown: affixLookupRowLimit)
                == "共 \(total) 件 · 已显示 \(affixLookupRowLimit) 件（另有 \(total - affixLookupRowLimit) 件未列出）",
            "真实截断时的提示文案"
        )
        count += 2
    }

    // ⑥ 深夜 A/B/C 池说明与结论文案（Windows 端 deepNoteText）
    let curseCount = index.poolMembers[deepCurseLookupPool]?.count ?? 0
    try lookupExpect(curseCount > 0, "诅咒池应有成员")
    try lookupExpect(
        affixLookupDeepNote(isCurse: true, requiresCurse: false, inAnyPool: true,
                            cursePoolID: deepCurseLookupPool, curseCount: curseCount)
            == "负面词条：只出现在深夜遗物带诅咒的那一行，与同一行的 A 池正面词条配对；诅咒池（3000000）共 \(curseCount) 条。",
        "负面词条的结论文案"
    )
    try lookupExpect(
        affixLookupDeepNote(isCurse: false, requiresCurse: true, inAnyPool: true,
                            cursePoolID: deepCurseLookupPool, curseCount: curseCount)
            == "A 池词条：出货时这一行必定同时带一条深夜诅咒（诅咒池 3000000，共 \(curseCount) 条）。存档里这条词条没配诅咒即为改动。",
        "A 池词条的结论文案"
    )
    try lookupExpect(
        affixLookupDeepNote(isCurse: false, requiresCurse: false, inAnyPool: true,
                            cursePoolID: deepCurseLookupPool, curseCount: curseCount)
            == "B / C 池词条：深夜遗物可出，所在行不带诅咒。",
        "B / C 池词条的结论文案"
    )
    try lookupExpect(
        affixLookupDeepNote(isCurse: false, requiresCurse: false, inAnyPool: false,
                            cursePoolID: deepCurseLookupPool, curseCount: curseCount)
            == "这条词条不在任何深夜词条池里，深夜遗物不会出它。",
        "不在深夜池时的结论文案"
    )
    count += 5

    // 深夜三池 + 诅咒池的补充说明两端同表，且都非空（Windows 端此前算了不画）
    for poolID in deepPositiveLookupPools + [deepCurseLookupPool] {
        try lookupExpect(!affixPoolDetail(poolID).isEmpty, "深夜池 \(poolID) 应有补充说明")
        count += 1
    }
    try lookupExpect(affixPoolDetail(2_000_000) == "强力正面词条：同一行必定配一条深夜诅咒", "A 池说明")
    try lookupExpect(affixPoolDetail(2_100_000) == "普通正面词条：同一行不带诅咒", "B 池说明")
    try lookupExpect(affixPoolDetail(2_200_000) == "普通正面词条：同一行不带诅咒", "C 池说明")
    try lookupExpect(affixPoolDetail(3_000_000) == "深夜遗物负面词条的唯一来源", "诅咒池说明")
    try lookupExpect(affixPoolDetail(110).isEmpty, "孔数层池没有补充说明")
    count += 5

    // 兜底标签「池 <id>」旁边不该再打一遍 id（两端同一条判断）
    var fallbackPools: Set<Int> = []
    for relic in fixtures.relicData.relics {
        for poolID in relic.slots + relic.curseSlots where poolID > 0 {
            if affixPoolLabel(poolID) == "池 \(poolID)" { fallbackPools.insert(poolID) }
        }
    }
    try lookupExpect(fallbackPools.count > 100, "确实有大量没有中文短名的槽位池，实际 \(fallbackPools.count)")
    count += 1

    // ⑥ 槽位池词条预览条数两端都是 10
    try lookupExpect(affixLookupSlotPreviewLimit == 10, "槽位池预览条数应为 10")
    count += 1
    var checkedSlots = 0
    for entry in index.relics where entry.isObtainable {
        for slot in entry.slots where !slot.isEmpty {
            try lookupExpect(
                slot.previewEffectIDs.count == min(affixLookupSlotPreviewLimit, slot.poolSize),
                "遗物 \(entry.id) 的槽位池预览应是 min(10, 池成员数)，实际 \(slot.previewEffectIDs.count)"
            )
            checkedSlots += 1
        }
        if checkedSlots > 200 { break }
    }
    count += checkedSlots

    return count
}
