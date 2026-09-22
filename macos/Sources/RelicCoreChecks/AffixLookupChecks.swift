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
        ("孔数层池与可获得性", checkPoolTiersAndObtainability)
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
