import Foundation
import RelicCore

// 「角色属性」页的自检：用真实的 Resources/heroes.json 跑解码、派生值重算、
// 转职遗物叠加、钳位与对比表排序，另外用几份构造出来的 JSON 验证「宽容解码」
// （未知字段忽略、缺字段退默认值、坏元素跳过）。注册入口见 GameDataChecks.swift。
//
// 结构性断言的三条主线（与 Windows 端 tests/heroes.test.mjs 同口径）：
//   ① 每个角色每一级，用 growthGraphs 重算的派生值必须等于数据集的 derived；
//   ② 某条词条在 12 级的叠加结果必须等于 stats + delta（12 级是参数锚点）；
//   ③ 属性被减到 0 或负数时钳到 1 —— 注意这条要连同「利普拉 + 转职遗物」一起扫：
//      不选利普拉时当前数据集确实一次都不触发，但选了利普拉之后钳位是常态
//      （实测 750 组「5 套利普拉 × 两条词条全勾」里 313 组会钳位），页面上的
//      「已钳到最低 1」注记因此是用户真看得到的东西，不是防御性代码。
//
// 最后两段（⑩ ⑪）是「双端对照基线」：6 组真实数据与一整份共用文案，Windows 端
// tests/heroes.test.mjs 用同一张表、同一批期望值跑同一批断言。改这里请连同那边一起改，
// 否则两端会各自红一片 —— 这正是它们存在的意义（注释互相声称「逐字一致」不算数）。

/// 内置资源目录下的 heroes.json（以源码路径定位，不依赖应用目标是否已构建）。
private var heroesResourceURL: URL {
    URL(fileURLWithPath: #filePath)          // …/Sources/RelicCoreChecks/HeroStatsChecks.swift
        .deletingLastPathComponent()         // …/Sources/RelicCoreChecks
        .deletingLastPathComponent()         // …/Sources
        .deletingLastPathComponent()         // …/macos
        .appendingPathComponent("Sources/NightreignRelicChecker/Resources/heroes.json")
}

private func heroExpect(_ condition: Bool, _ message: String, counter: inout Int) throws {
    guard condition else { throw CheckFailure(description: "角色属性：" + message) }
    counter += 1
}

private func heroExpectClose(
    _ value: Double, _ expected: Double, _ message: String, tolerance: Double = 0.0001, counter: inout Int
) throws {
    guard abs(value - expected) <= tolerance else {
        throw CheckFailure(
            description: "角色属性：\(message)（期望 \(expected)，实际 \(value)）"
        )
    }
    counter += 1
}

func runHeroStatsChecks() throws -> Int {
    var count = 0

    let url = heroesResourceURL
    guard FileManager.default.fileExists(atPath: url.path) else {
        throw CheckFailure(description: "角色属性：缺少 \(url.path)")
    }
    let data = try Data(contentsOf: url)
    if GameDataLoader.isPlaceholder(data) {
        print("    （heroes.json 仍是占位内容，跳过角色属性检查）")
        return 0
    }

    let index = try HeroStatsIndex(data: data)
    count += try checkHeroDataset(index)
    count += try checkHeroDerivedRecomputation(index)
    count += try checkHeroModifierAnchors(index)
    count += try checkHeroModifierLevels(index)
    count += try checkHeroClamping(index)
    count += try checkHeroLibra(index)
    count += try checkHeroComparison(index)
    count += try checkHeroText(index)
    count += try checkHeroCrossEndFixtures(index)
    count += try checkHeroCrossEndCopy(index)
    count += try checkHeroCrossEndParity(index)
    count += try checkHeroIntegerValuePaths(index)
    count += try checkHeroLenientDecoding()
    return count
}

// MARK: - ① 数据集骨架

private func checkHeroDataset(_ index: HeroStatsIndex) throws -> Int {
    var count = 0
    let dataset = index.dataset

    try heroExpect(dataset.schemaVersion >= 1, "schemaVersion 应 ≥ 1，实际 \(dataset.schemaVersion)", counter: &count)
    try heroExpect(dataset.datasetId == "heroes", "datasetId 应为 heroes，实际 \(dataset.datasetId)", counter: &count)
    try heroExpect(
        !dataset.gameVersion.isEmpty && !dataset.dataVersion.isEmpty && !dataset.generatedAt.isEmpty,
        "缺少 gameVersion / dataVersion / generatedAt（页面底部要展示）",
        counter: &count
    )
    try heroExpect(!dataset.caveats.isEmpty, "caveats 不应为空（页面底部要展示）", counter: &count)
    try heroExpect(!dataset.sources.isEmpty, "sources 不应为空", counter: &count)
    try heroExpect(dataset.heroes.count == 10, "应有 10 位夜行者，实际 \(dataset.heroes.count)", counter: &count)
    try heroExpect(dataset.statModifiers.count == 20, "应有 20 条转职遗物词条，实际 \(dataset.statModifiers.count)", counter: &count)
    try heroExpect(dataset.libraRespecs.count == 5, "利普拉的交易应有 5 套，实际 \(dataset.libraRespecs.count)", counter: &count)
    try heroExpect(index.maxLevel == 15, "最大等级应为 15，实际 \(index.maxLevel)", counter: &count)

    // statNames：8 项属性 + 4 项派生值，顺序表与明细一一对应，中文名齐全
    let names = dataset.statNames
    try heroExpect(names.attributeKeys.count == 8, "应有 8 项属性，实际 \(names.attributeKeys.count)", counter: &count)
    try heroExpect(names.derivedKeys.count == 4, "应有 4 项派生值，实际 \(names.derivedKeys.count)", counter: &count)
    try heroExpect(
        names.attributeKeys == ["vigor", "mind", "endurance", "strength", "dexterity", "intelligence", "faith", "arcane"],
        "属性顺序应与数据集 attributeOrder 一致，实际 \(names.attributeKeys)",
        counter: &count
    )
    try heroExpect(
        names.derivedKeys == ["hp", "fp", "stamina", "equipLoad"],
        "派生值顺序应与数据集 derivedOrder 一致，实际 \(names.derivedKeys)",
        counter: &count
    )
    for key in names.attributeKeys {
        try heroExpect(!names.attributeTitle(key).isEmpty && names.attributeTitle(key) != key,
                       "属性 \(key) 应有中文名", counter: &count)
    }
    for key in names.derivedKeys {
        try heroExpect(!names.derivedTitle(key).isEmpty && names.derivedTitle(key) != key,
                       "派生值 \(key) 应有中文名", counter: &count)
    }
    // 页面文案直接取数据集的中文名，这里钉死几项，避免数据集改名后页面悄悄跟着变
    try heroExpect(names.attributeTitle("vigor") == "生命力", "vigor 应写「生命力」", counter: &count)
    try heroExpect(names.attributeTitle("mind") == "集中力", "mind 应写「集中力」", counter: &count)
    try heroExpect(names.attributeTitle("arcane") == "感应", "arcane 应写「感应」", counter: &count)
    try heroExpect(names.derivedTitle("fp") == "专注值", "fp 应写「专注值」（与增伤排名页一致）", counter: &count)
    try heroExpect(names.derivedTitle("hp") == "血量", "hp 应写「血量」", counter: &count)
    try heroExpect(names.derivedTitle("equipLoad") == "负重上限", "equipLoad 应写「负重上限」", counter: &count)

    // 每位角色 15 级、等级连续、锚点为 1/2/12/15、名字齐全
    for hero in dataset.heroes {
        try heroExpect(hero.levels.count == 15, "\(hero.display) 应有 15 级，实际 \(hero.levels.count)", counter: &count)
        try heroExpect(hero.levels.map(\.level) == Array(1...15), "\(hero.display) 等级应为 1–15 连续", counter: &count)
        try heroExpect(hero.anchorLevels == [1, 2, 12, 15], "\(hero.display) 锚点应为 1/2/12/15，实际 \(hero.anchorLevels)", counter: &count)
        try heroExpect(!hero.nameZh.isEmpty && !hero.nameEn.isEmpty, "\(hero.key) 应有中英文名", counter: &count)
        try heroExpect(hero.anchors.count == 4, "\(hero.display) 应有 4 行参数锚点", counter: &count)
        for row in hero.levels {
            try heroExpect(
                Set(row.stats.keys) == Set(names.attributeKeys),
                "\(hero.display) \(row.level) 级属性项应齐全（8 项）",
                counter: &count
            )
        }
        // 每位角色恰好 2 条转职词条
        try heroExpect(
            index.modifiers(for: hero.key).count == 2,
            "\(hero.display) 应有 2 条转职遗物词条，实际 \(index.modifiers(for: hero.key).count)",
            counter: &count
        )
    }

    // growthGraphs：派生值用到的 4 行都在，且端点数组等长
    for entry in names.orderedDerived {
        guard let graph = dataset.growthGraphs[entry.graphId] else {
            throw CheckFailure(description: "角色属性：缺少派生值 \(entry.key) 用的 CalcCorrectGraph \(entry.graphId)")
        }
        try heroExpect(graph.isUsable, "CalcCorrectGraph \(entry.graphId) 的端点数组应等长且至少两段", counter: &count)
        try heroExpect(graph.usedFor.contains(entry.key), "CalcCorrectGraph \(entry.graphId) 的 usedFor 应含 \(entry.key)", counter: &count)
        try heroExpect(
            dataset.statNames.attributeKeys.contains(entry.fromStat),
            "派生值 \(entry.key) 的来源属性 \(entry.fromStat) 应是 8 项属性之一",
            counter: &count
        )
    }
    // 血量 / 专注值 / 精力必为整数、负重上限带指数
    try heroExpect(dataset.growthGraphs[100]?.linear == true, "CalcCorrectGraph 100 应为纯线性", counter: &count)
    try heroExpect(dataset.growthGraphs[101]?.linear == true, "CalcCorrectGraph 101 应为纯线性", counter: &count)
    try heroExpect(dataset.growthGraphs[104]?.linear == true, "CalcCorrectGraph 104 应为纯线性", counter: &count)
    try heroExpect(dataset.growthGraphs[220]?.linear == false, "CalcCorrectGraph 220 带指数，linear 应为 false", counter: &count)

    // 插值口径：底部说明要能逐条展示
    let interpolation = dataset.interpolation
    try heroExpect(interpolation.baseAnchorLevels == [1, 2, 12, 15], "基础锚点应为 1/2/12/15", counter: &count)
    try heroExpect(interpolation.modifierAnchorLevels == [1, 12], "词条锚点应为 1/12", counter: &count)
    try heroExpect(interpolation.baseVerified, "基础表应标为已验证", counter: &count)
    try heroExpect(interpolation.modifierAnchorVerified, "词条锚点应标为已验证", counter: &count)
    try heroExpect(!interpolation.modifierMidLevelsVerified, "词条中间等级应仍标为未实测", counter: &count)
    try heroExpect(interpolation.notes.count >= 6, "底部插值说明应有 ≥ 6 条，实际 \(interpolation.notes.count)", counter: &count)
    try heroExpect(!interpolation.libraRule.isEmpty, "利普拉叠加口径说明不应为空", counter: &count)

    // 取整方向（floor vs trunc）是 caveats 点名的歧义来源，底部说明必须写出来用的是哪一种
    try heroExpect(interpolation.baseRounding == "floor", "基础表取整应为 floor，实际 \(interpolation.baseRounding)", counter: &count)
    try heroExpect(interpolation.modifierRounding == "trunc", "词条取整应为 trunc，实际 \(interpolation.modifierRounding)", counter: &count)
    guard let roundingNote = interpolation.notes.first(where: { $0.title == "取整方向" }) else {
        throw CheckFailure(description: "角色属性：底部插值说明缺少「取整方向」一条")
    }
    count += 1
    try heroExpect(roundingNote.text.contains("floor") && roundingNote.text.contains("trunc"),
                   "「取整方向」应同时写出基础表与词条的取整口径，实际 \(roundingNote.text)", counter: &count)
    try heroExpect(roundingNote.text.contains("deltaFloorAlt"),
                   "「取整方向」应提到 deltaFloorAlt 这份备用值", counter: &count)
    try heroExpect(
        HeroInterpolation(baseRule: "x").notes.allSatisfy { $0.title != "取整方向" },
        "取整字段缺失时不应硬造「取整方向」说明",
        counter: &count
    )

    return count
}

// MARK: - ② 派生值重算 = 数据集 derived

private func checkHeroDerivedRecomputation(_ index: HeroStatsIndex) throws -> Int {
    var count = 0
    let keys = index.statNames.derivedKeys

    // 每个角色每一级：用 growthGraphs 重算的血量 / 专注值 / 精力 / 负重上限
    // 必须逐格等于数据集里的 derived（10 × 15 × 4 = 600 格）。
    for hero in index.heroes {
        for row in hero.levels {
            let recomputed = index.derivedValues(for: row.stats)
            for key in keys {
                guard let expected = row.derived[key] else {
                    throw CheckFailure(description: "角色属性：\(hero.display) \(row.level) 级缺少派生值 \(key)")
                }
                guard let actual = recomputed[key] else {
                    throw CheckFailure(description: "角色属性：\(hero.display) \(row.level) 级无法重算派生值 \(key)")
                }
                try heroExpectClose(
                    actual, expected,
                    "\(hero.display) \(row.level) 级 \(index.statNames.derivedTitle(key)) 重算值应等于数据集",
                    counter: &count
                )
            }
        }
    }

    // 利普拉的 5 套表同样逐格重算（5 × 15 × 4 = 300 格）
    for respec in index.libraRespecs {
        for row in respec.levels {
            let recomputed = index.derivedValues(for: row.stats)
            for key in keys {
                guard let expected = row.derived[key], let actual = recomputed[key] else {
                    throw CheckFailure(description: "角色属性：利普拉 \(respec.shortTitle) \(row.level) 级派生值 \(key) 缺失")
                }
                try heroExpectClose(
                    actual, expected,
                    "利普拉 \(respec.shortTitle) \(row.level) 级 \(index.statNames.derivedTitle(key)) 重算值应等于数据集",
                    counter: &count
                )
            }
        }
    }

    // 几个手算常数，防止「实现和它自己比」：
    // 血量 = 20 × 生命力 + 80、专注值 = 5 × 集中力 + 45、精力 = 2 × 耐力 + 48。
    guard let hp = index.dataset.growthGraphs[100],
          let fp = index.dataset.growthGraphs[101],
          let stamina = index.dataset.growthGraphs[104],
          let load = index.dataset.growthGraphs[220] else {
        throw CheckFailure(description: "角色属性：缺少 CalcCorrectGraph 100/101/104/220")
    }
    for vigor in [1, 8, 25, 40, 52, 60] {
        try heroExpect(
            hp.integerValue(at: vigor) == 20 * vigor + 80,
            "血量在生命力 \(vigor) 上应为 \(20 * vigor + 80)，实际 \(hp.integerValue(at: vigor))",
            counter: &count
        )
    }
    for mind in [1, 4, 19, 31, 45] {
        try heroExpect(
            fp.integerValue(at: mind) == 5 * mind + 45,
            "专注值在集中力 \(mind) 上应为 \(5 * mind + 45)，实际 \(fp.integerValue(at: mind))",
            counter: &count
        )
    }
    for endurance in [1, 3, 21, 24, 27, 40] {
        try heroExpect(
            stamina.integerValue(at: endurance) == 2 * endurance + 48,
            "精力在耐力 \(endurance) 上应为 \(2 * endurance + 48)，实际 \(stamina.integerValue(at: endurance))",
            counter: &count
        )
    }
    // 12 级追踪者的精力：外部 wiki 写 92（与 11 级重复），按参数应为 96
    guard let wylder = index.hero("wylder"), let level12 = wylder.level(12) else {
        throw CheckFailure(description: "角色属性：找不到追踪者 12 级")
    }
    try heroExpectClose(index.derivedValues(for: level12.stats)["stamina"] ?? 0, 96,
                        "追踪者 12 级精力应为 96（耐力 24）", counter: &count)
    try heroExpectClose(index.derivedValues(for: level12.stats)["hp"] ?? 0, 1000,
                        "追踪者 12 级血量应为 1000（生命力 46）", counter: &count)
    // 负重上限：耐力 ≤ 8 时恒为 45（第一段是平的），27 点落在带指数的 [25,60] 段
    try heroExpectClose(HeroStatsMath.round(load.value(at: 3), digits: 1), 45, "耐力 3 的负重上限应为 45", counter: &count)
    try heroExpectClose(HeroStatsMath.round(load.value(at: 8), digits: 1), 45, "耐力 8 的负重上限应为 45", counter: &count)
    guard let wylder15 = wylder.level(15) else {
        throw CheckFailure(description: "角色属性：找不到追踪者 15 级")
    }
    try heroExpectClose(index.derivedValues(for: wylder15.stats)["equipLoad"] ?? 0, 74.1,
                        "追踪者 15 级负重上限应为 74.1（耐力 27）", counter: &count)

    // floor 的整数除法在负数上也必须向下取整
    try heroExpect(HeroStatsMath.floorDivide(7, 2) == 3, "floorDivide(7,2) 应为 3", counter: &count)
    try heroExpect(HeroStatsMath.floorDivide(-7, 2) == -4, "floorDivide(-7,2) 应为 -4", counter: &count)
    try heroExpect(HeroStatsMath.floorDivide(-6, 2) == -3, "floorDivide(-6,2) 应为 -3", counter: &count)
    try heroExpect(HeroStatsMath.floorDivide(5, 0) == 0, "除数为 0 时应返回 0 而不是崩", counter: &count)

    return count
}

// MARK: - ③ 12 级锚点：叠加结果 = stats + delta

private func checkHeroModifierAnchors(_ index: HeroStatsIndex) throws -> Int {
    var count = 0
    let attributeKeys = index.statNames.attributeKeys

    for modifier in index.dataset.statModifiers {
        guard let hero = index.hero(modifier.heroKey) else {
            throw CheckFailure(description: "角色属性：词条 \(modifier.display) 指向不存在的角色 \(modifier.heroKey)")
        }
        try heroExpect(!modifier.affectedStats.isEmpty, "\(modifier.display) 应至少影响一项属性", counter: &count)
        try heroExpect(
            modifier.affectedStats.allSatisfy { attributeKeys.contains($0) },
            "\(modifier.display) 的 affectedStats 应都是 8 项属性之一",
            counter: &count
        )
        try heroExpect(!modifier.relicItems.isEmpty, "\(modifier.display) 应给出携带它的遗物", counter: &count)
        for item in modifier.relicItems {
            try heroExpect(!item.display.isEmpty, "\(modifier.display) 的遗物应有名字", counter: &count)
            try heroExpect(!item.colorText.isEmpty, "\(modifier.display) 的遗物应有颜色", counter: &count)
            try heroExpect(item.colorText == relicColorLabel(item.color) + "色",
                           "遗物颜色文案应与遗物卡 / 报告 / CSV 一致（「红色」而不是「红」），实际 \(item.colorText)",
                           counter: &count)
        }
        try heroExpect(modifier.anchors.count == 2, "\(modifier.display) 应有 2 行参数锚点（1 / 12 级）", counter: &count)
        try heroExpect(modifier.shortName != modifier.display || !modifier.nameZh.hasPrefix("【"),
                       "\(modifier.display) 的短名应去掉【角色】前缀", counter: &count)

        // 锚点等级（1 / 12）：叠加结果必须等于「基础属性 + 参数原始 delta」
        for anchor in modifier.anchors {
            guard let baseRow = hero.level(anchor.level) else {
                throw CheckFailure(description: "角色属性：\(hero.display) 缺少 \(anchor.level) 级")
            }
            guard let snapshot = index.snapshot(
                heroKey: hero.key, level: anchor.level, modifierIDs: [modifier.affixId]
            ) else {
                throw CheckFailure(description: "角色属性：无法计算 \(hero.display) \(anchor.level) 级快照")
            }
            for key in attributeKeys {
                let base = baseRow.stats[key] ?? 0
                let expected = max(HeroStatsMath.minimumStat, base + (anchor.delta[key] ?? 0))
                try heroExpect(
                    snapshot.finalStats[key] == expected,
                    "\(modifier.display) \(anchor.level) 级 \(index.statNames.attributeTitle(key)) 叠加结果应为 \(expected)，"
                        + "实际 \(snapshot.finalStats[key] ?? -1)",
                    counter: &count
                )
            }
            // 逐级表里的 delta 必须等于参数锚点行
            try heroExpect(
                modifier.level(anchor.level)?.delta == anchor.delta,
                "\(modifier.display) \(anchor.level) 级逐级 delta 应等于参数锚点行",
                counter: &count
            )
            try heroExpect(
                modifier.level(anchor.level)?.isAnchor == true && modifier.level(anchor.level)?.inferred == false,
                "\(modifier.display) \(anchor.level) 级应标为锚点、非推算",
                counter: &count
            )
            // 派生值必须跟着改后的属性走
            let recomputed = index.derivedValues(for: snapshot.finalStats)
            for key in index.statNames.derivedKeys {
                try heroExpectClose(
                    snapshot.finalDerived[key] ?? 0, recomputed[key] ?? 0,
                    "\(modifier.display) \(anchor.level) 级 \(index.statNames.derivedTitle(key)) 应按改后属性重算",
                    counter: &count
                )
            }
        }
    }

    // 手算一组：复仇者 305001（生命力 +5 / 耐力 +5 / 集中力 −11）在 15 级
    // 应得到 生命力 40 / 集中力 20 / 耐力 26 → 血量 880 / 专注值 145 / 精力 100。
    guard let revenantModifier = index.modifiers(for: "revenant").first(where: {
        ($0.anchors.last?.delta["mind"] ?? 0) < 0
    }) else {
        throw CheckFailure(description: "角色属性：找不到复仇者「提升生命力、耐力，但降低集中力」")
    }
    guard let snapshot = index.snapshot(
        heroKey: "revenant", level: 15, modifierIDs: [revenantModifier.affixId]
    ) else {
        throw CheckFailure(description: "角色属性：无法计算复仇者 15 级快照")
    }
    try heroExpect(snapshot.finalStats["vigor"] == 40, "复仇者 15 级叠加后生命力应为 40，实际 \(snapshot.finalStats["vigor"] ?? -1)", counter: &count)
    try heroExpect(snapshot.finalStats["mind"] == 20, "复仇者 15 级叠加后集中力应为 20，实际 \(snapshot.finalStats["mind"] ?? -1)", counter: &count)
    try heroExpect(snapshot.finalStats["endurance"] == 26, "复仇者 15 级叠加后耐力应为 26，实际 \(snapshot.finalStats["endurance"] ?? -1)", counter: &count)
    try heroExpectClose(snapshot.finalDerived["hp"] ?? 0, 880, "复仇者 15 级叠加后血量应为 880", counter: &count)
    try heroExpectClose(snapshot.finalDerived["fp"] ?? 0, 145, "复仇者 15 级叠加后专注值应为 145", counter: &count)
    try heroExpectClose(snapshot.finalDerived["stamina"] ?? 0, 100, "复仇者 15 级叠加后精力应为 100", counter: &count)
    try heroExpect(snapshot.carriesAnchorDelta, "15 级应标为「沿用 12 级锚点」", counter: &count)
    try heroExpect(!snapshot.hasInferredDelta, "15 级不再标「推算」（走沿用锚点的说法）", counter: &count)

    // 两条词条同时勾选：增减量相加
    let both = index.modifiers(for: "wylder")
    try heroExpect(both.count == 2, "追踪者应有 2 条词条", counter: &count)
    guard let combined = index.snapshot(
        heroKey: "wylder", level: 12, modifierIDs: Set(both.map(\.affixId))
    ), let wylder12 = index.hero("wylder")?.level(12) else {
        throw CheckFailure(description: "角色属性：无法计算追踪者 12 级双词条快照")
    }
    for key in attributeKeys {
        let sum = both.reduce(0) { $0 + ($1.level(12)?.delta[key] ?? 0) }
        let expected = max(HeroStatsMath.minimumStat, (wylder12.stats[key] ?? 0) + sum)
        try heroExpect(
            combined.finalStats[key] == expected,
            "追踪者 12 级双词条 \(index.statNames.attributeTitle(key)) 应为 \(expected)，实际 \(combined.finalStats[key] ?? -1)",
            counter: &count
        )
        try heroExpect(
            combined.requestedDelta[key] ?? 0 == sum,
            "追踪者 12 级双词条 \(index.statNames.attributeTitle(key)) 的原始增减量应为 \(sum)",
            counter: &count
        )
    }
    try heroExpect(combined.activeModifiers.count == 2, "双词条快照应记录 2 条生效词条", counter: &count)
    try heroExpect(combined.isAnchorLevel, "12 级应标为参数锚点", counter: &count)

    return count
}

// MARK: - ④ 逐级 delta 的结构

private func checkHeroModifierLevels(_ index: HeroStatsIndex) throws -> Int {
    var count = 0
    let anchorLevels = index.dataset.interpolation.modifierAnchorLevels
    let lastAnchor = anchorLevels.max() ?? 12

    for modifier in index.dataset.statModifiers {
        try heroExpect(modifier.levels.count == 15, "\(modifier.display) 应有 15 级 delta，实际 \(modifier.levels.count)", counter: &count)
        try heroExpect(modifier.levels.map(\.level) == Array(1...15), "\(modifier.display) 等级应为 1–15 连续", counter: &count)
        guard let anchorDelta = modifier.level(lastAnchor)?.delta else {
            throw CheckFailure(description: "角色属性：\(modifier.display) 缺少 \(lastAnchor) 级 delta")
        }
        for row in modifier.levels {
            let shouldBeAnchor = anchorLevels.contains(row.level)
            try heroExpect(row.isAnchor == shouldBeAnchor, "\(modifier.display) \(row.level) 级 isAnchor 应为 \(shouldBeAnchor)", counter: &count)
            try heroExpect(row.inferred == !shouldBeAnchor, "\(modifier.display) \(row.level) 级 inferred 应为 \(!shouldBeAnchor)", counter: &count)
            try heroExpect(
                Set(row.delta.keys).isSubset(of: Set(modifier.affectedStats)),
                "\(modifier.display) \(row.level) 级 delta 的属性应都在 affectedStats 里",
                counter: &count
            )
            // 13–15 级沿用 12 级锚点：delta 必须恒等
            if row.level > lastAnchor {
                try heroExpect(row.delta == anchorDelta, "\(modifier.display) \(row.level) 级 delta 应沿用 \(lastAnchor) 级锚点", counter: &count)
            }
            // 增减量单调不减地逼近锚点（|delta| 随等级不减），中间等级是 1→12 线性插值
            if row.level > 1 && row.level <= lastAnchor {
                for (key, value) in row.delta {
                    let previous = modifier.level(row.level - 1)?.delta[key] ?? 0
                    try heroExpect(
                        abs(value) >= abs(previous) && (value == 0 || previous == 0 || (value > 0) == (previous > 0)),
                        "\(modifier.display) \(key) 在 \(row.level) 级的增减量应不小于上一级（同号且绝对值不减）",
                        counter: &count
                    )
                }
            }
            // 取整歧义只出现在非锚点等级
            if !row.deltaFloorAlt.isEmpty {
                try heroExpect(row.inferred, "\(modifier.display) \(row.level) 级有 deltaFloorAlt，应是推算等级", counter: &count)
                for (key, alt) in row.deltaFloorAlt {
                    try heroExpect(alt != (row.delta[key] ?? 0), "\(modifier.display) \(row.level) 级 deltaFloorAlt.\(key) 应与 delta 不同", counter: &count)
                    try heroExpect(alt == (row.delta[key] ?? 0) - 1, "\(modifier.display) \(row.level) 级 floor 版本应恰好小 1", counter: &count)
                }
            }
        }

        // 快照上的「推算 / 沿用锚点」标记
        for level in [1, 6, 12, 15] {
            guard let snapshot = index.snapshot(
                heroKey: modifier.heroKey, level: level, modifierIDs: [modifier.affixId]
            ) else {
                throw CheckFailure(description: "角色属性：无法计算 \(modifier.heroNameZh) \(level) 级快照")
            }
            let expectInferred = level != 1 && level != lastAnchor && level < lastAnchor
            try heroExpect(snapshot.hasInferredDelta == expectInferred,
                           "\(modifier.display) \(level) 级「推算」标记应为 \(expectInferred)", counter: &count)
            try heroExpect(snapshot.carriesAnchorDelta == (level > lastAnchor),
                           "\(modifier.display) \(level) 级「沿用锚点」标记应为 \(level > lastAnchor)", counter: &count)
        }
    }

    // 没勾任何词条时：最终值等于基础值，也不带任何推算标记
    for hero in index.heroes {
        for level in [1, 7, 15] {
            guard let snapshot = index.snapshot(heroKey: hero.key, level: level) else {
                throw CheckFailure(description: "角色属性：无法计算 \(hero.display) \(level) 级基础快照")
            }
            try heroExpect(snapshot.finalStats == snapshot.baseStats, "\(hero.display) \(level) 级未勾词条时最终值应等于基础值", counter: &count)
            try heroExpect(snapshot.requestedDelta.isEmpty, "\(hero.display) \(level) 级未勾词条时不应有增减量", counter: &count)
            try heroExpect(!snapshot.hasModifier && !snapshot.carriesAnchorDelta && !snapshot.hasInferredDelta,
                           "\(hero.display) \(level) 级未勾词条时不应有任何词条标记", counter: &count)
            try heroExpect(snapshot.clampedStats.isEmpty, "\(hero.display) \(level) 级未勾词条时不应有钳位", counter: &count)
        }
    }

    return count
}

// MARK: - ⑤ 钳位

/// 一轮「角色 × 等级 × 利普拉 × 词条组合」扫描的汇总。
private struct HeroClampScan {
    var combinations = 0
    /// 至少有一项属性被钳到 1 的组合数。
    var clampedCombinations = 0
    /// 被钳到 1 的属性格子总数。
    var clampedCells = 0
    /// 第一处对不上的地方（nil 表示逐格都对）。只记第一处，错一片时消息才读得懂。
    var firstMismatch: String?

    mutating func note(_ message: @autoclosure () -> String) {
        if firstMismatch == nil { firstMismatch = message() }   // heroExpect 会补「角色属性：」前缀
    }

    mutating func merge(_ other: HeroClampScan) {
        combinations += other.combinations
        clampedCombinations += other.clampedCombinations
        clampedCells += other.clampedCells
        if firstMismatch == nil { firstMismatch = other.firstMismatch }
    }
}

/// 扫一遍「全角色 × 1–15 级 × 指定利普拉 × 若干词条组合」，逐格核对钳位口径。
private func scanHeroClamping(
    _ index: HeroStatsIndex,
    libraKey: String?,
    groups: (HeroEntry) -> [(label: String, ids: Set<Int>)]
) throws -> HeroClampScan {
    var scan = HeroClampScan()
    let libraLabel = libraKey.map { "利普拉（\(index.libra($0)?.shortTitle ?? $0)）" } ?? "不选利普拉"

    for hero in index.heroes {
        for group in groups(hero) {
            for level in index.levelRange {
                guard let snapshot = index.snapshot(
                    heroKey: hero.key, level: level, modifierIDs: group.ids, libraKey: libraKey
                ) else {
                    throw CheckFailure(
                        description: "角色属性：无法计算 \(hero.display) \(level) 级 \(libraLabel) + \(group.label) 快照"
                    )
                }
                scan.combinations += 1
                let place = "\(hero.display) \(level) 级 · \(libraLabel) · \(group.label)"

                // 最终值必须逐格等于 max(1, 基础 + 请求增减量)，clampedStats 与之一致。
                // clampedStats 按**页面上的属性展示顺序**排（不是 key 字典序）：页面的
                // 钳位汇总「生命力、集中力 叠加后不足 1」要与上面 8 张属性卡片同序。
                var expectedStats = snapshot.baseStats
                var expectedClampedFrom: [String: Int] = [:]
                for (key, change) in snapshot.requestedDelta {
                    let raw = (snapshot.baseStats[key] ?? 0) + change
                    expectedStats[key] = max(HeroStatsMath.minimumStat, raw)
                    if raw < HeroStatsMath.minimumStat { expectedClampedFrom[key] = raw }
                }
                let expectedClamped = index.statNames.attributeKeys.filter { expectedClampedFrom[$0] != nil }

                if snapshot.finalStats != expectedStats {
                    scan.note("\(place) 最终属性应为 max(1, 基础 + 增减量) = \(expectedStats)，实际 \(snapshot.finalStats)")
                }
                if snapshot.clampedStats != expectedClamped {
                    scan.note("\(place) 钳位列表应为 \(expectedClamped)（按属性展示顺序），实际 \(snapshot.clampedStats)")
                }
                if snapshot.clampedFrom != expectedClampedFrom {
                    scan.note("\(place) 钳位前的原值应为 \(expectedClampedFrom)，实际 \(snapshot.clampedFrom)")
                }
                for key in snapshot.clampedStats where (snapshot.clampedFrom[key] ?? 1) >= HeroStatsMath.minimumStat {
                    scan.note("\(place) 的 \(key) 被记成钳位，但原值 \(snapshot.clampedFrom[key] ?? 0) 并不小于 1")
                }
                if !snapshot.finalStats.values.allSatisfy({ $0 >= HeroStatsMath.minimumStat }) {
                    scan.note("\(place) 最终属性出现 < 1 的值：\(snapshot.finalStats)")
                }
                if !snapshot.finalDerived.values.allSatisfy({ $0 >= 0 }) {
                    scan.note("\(place) 派生值出现负数：\(snapshot.finalDerived)")
                }

                // 钳位之后派生值也要按钳位后的属性重算（不能拿未钳位的值去算）
                let recomputed = index.derivedValues(for: snapshot.finalStats)
                for key in index.statNames.derivedKeys
                where abs((snapshot.finalDerived[key] ?? 0) - (recomputed[key] ?? 0)) > 0.0001 {
                    scan.note(
                        "\(place) 的 \(index.statNames.derivedTitle(key)) 应按钳位后的属性重算"
                            + "（期望 \(recomputed[key] ?? 0)，实际 \(snapshot.finalDerived[key] ?? 0)）"
                    )
                }

                if !snapshot.clampedStats.isEmpty {
                    scan.clampedCombinations += 1
                    scan.clampedCells += snapshot.clampedStats.count
                }
            }
        }
    }
    return scan
}

private func checkHeroClamping(_ index: HeroStatsIndex) throws -> Int {
    var count = 0

    // 纯函数层：减到 0 / 负数都钳到 1，并在 clamped 里列出
    let base = ["vigor": 3, "mind": 1, "endurance": 10]
    let applied = HeroStatsMath.apply(deltas: [["vigor": -3, "mind": -5, "endurance": -2]], to: base)
    try heroExpect(applied.stats["vigor"] == 1, "生命力 3 − 3 应钳到 1，实际 \(applied.stats["vigor"] ?? -1)", counter: &count)
    try heroExpect(applied.stats["mind"] == 1, "集中力 1 − 5 应钳到 1，实际 \(applied.stats["mind"] ?? -1)", counter: &count)
    try heroExpect(applied.stats["endurance"] == 8, "耐力 10 − 2 应为 8（不触发钳位）", counter: &count)
    try heroExpect(applied.clamped == ["mind", "vigor"], "被钳的属性应为 mind / vigor，实际 \(applied.clamped)", counter: &count)
    try heroExpect(applied.requested["vigor"] == -3, "原始增减量应保留 −3（不被钳位改写）", counter: &count)

    // 多条叠加后才跌破下限
    let stacked = HeroStatsMath.apply(deltas: [["vigor": -2], ["vigor": -2]], to: ["vigor": 3])
    try heroExpect(stacked.requested["vigor"] == -4, "两条 −2 应叠成 −4", counter: &count)
    try heroExpect(stacked.stats["vigor"] == 1, "3 − 4 应钳到 1", counter: &count)
    try heroExpect(stacked.clamped == ["vigor"], "叠加后触发的钳位也要记录", counter: &count)

    // 正好等于下限不算钳位
    let exact = HeroStatsMath.apply(deltas: [["vigor": -2]], to: ["vigor": 3])
    try heroExpect(exact.stats["vigor"] == 1 && exact.clamped.isEmpty, "结果正好为 1 时不算钳位", counter: &count)

    // 真实数据扫描：全角色 × 1–15 级 ×（不选利普拉 + 5 套利普拉）×（两条词条全勾 / 各自单勾）。
    //
    // 页面上「选利普拉 + 勾转职遗物」是一条真实主路径，而**钳位在这条路径上是常态、
    // 不是防御性代码**：利普拉把非目标属性压到个位数，转职遗物的负增减量就会把它减到 0
    // 以下。下面把每一档的实测值钉成回归基线（不选利普拉时确实一次都不触发）。
    // 扫描逐格核对「最终值 == max(1, 基础 + 请求增减量)」、clampedStats 与之一致、
    // 派生值按钳位后的属性重算；出错只报第一处，错一片时消息才读得懂。
    let libraKeys: [String?] = [nil] + index.libraRespecs.map { Optional($0.key) }

    func bothGroups(_ hero: HeroEntry) -> [(label: String, ids: Set<Int>)] {
        [("两条词条全勾", Set(index.modifiers(for: hero.key).map(\.affixId)))]
    }
    func singleGroups(_ hero: HeroEntry) -> [(label: String, ids: Set<Int>)] {
        index.modifiers(for: hero.key).map { ($0.shortName, [$0.affixId]) }
    }

    var plainBoth = HeroClampScan()
    var plainSingle = HeroClampScan()
    var libraBoth = HeroClampScan()
    var libraSingle = HeroClampScan()
    for libraKey in libraKeys {
        let both = try scanHeroClamping(index, libraKey: libraKey, groups: bothGroups)
        let single = try scanHeroClamping(index, libraKey: libraKey, groups: singleGroups)
        if libraKey == nil {
            plainBoth.merge(both)
            plainSingle.merge(single)
        } else {
            libraBoth.merge(both)
            libraSingle.merge(single)
        }
    }

    for scan in [plainBoth, plainSingle, libraBoth, libraSingle] {
        try heroExpect(scan.firstMismatch == nil, scan.firstMismatch ?? "钳位扫描通过", counter: &count)
        // 逐格核对过的组合每组算一项（每组内部还核了最终值 / 钳位列表 / 派生值重算四件事，
        // 这里只按组计数，保守一点）。
        count += scan.combinations
    }

    // 覆盖面：别因为改了循环就悄悄少扫一批组合
    try heroExpect(plainBoth.combinations == 150, "不选利普拉 + 全勾应扫 150 组，实际 \(plainBoth.combinations)", counter: &count)
    try heroExpect(plainSingle.combinations == 300, "不选利普拉 + 单勾应扫 300 组，实际 \(plainSingle.combinations)", counter: &count)
    try heroExpect(libraBoth.combinations == 750, "5 套利普拉 + 全勾应扫 750 组，实际 \(libraBoth.combinations)", counter: &count)
    try heroExpect(libraSingle.combinations == 1500, "5 套利普拉 + 单勾应扫 1500 组，实际 \(libraSingle.combinations)", counter: &count)

    // ① 不选利普拉：当前数据集一次都不触发钳位
    try heroExpect(
        plainBoth.clampedCombinations == 0 && plainSingle.clampedCombinations == 0,
        "不选利普拉时不应触发钳位（全勾 \(plainBoth.clampedCombinations) 组 / 单勾 \(plainSingle.clampedCombinations) 组）",
        counter: &count
    )

    // ② 选了利普拉：钳位是常态，按实测值钉死。数据集换代后这里会红，
    //    说明要重新核一遍页面上「已钳到最低 1」那批数字（这是用户真看得到的一批）。
    try heroExpect(
        libraBoth.clampedCombinations == 313,
        "利普拉 + 两条词条全勾应有 313 组触发钳位，实际 \(libraBoth.clampedCombinations)",
        counter: &count
    )
    try heroExpect(
        libraBoth.clampedCells == 389,
        "利普拉 + 两条词条全勾应有 389 格被钳到 1，实际 \(libraBoth.clampedCells)",
        counter: &count
    )
    try heroExpect(
        libraSingle.clampedCombinations == 458,
        "利普拉 + 单条词条应有 458 组触发钳位，实际 \(libraSingle.clampedCombinations)",
        counter: &count
    )
    try heroExpect(
        libraSingle.clampedCells == 512,
        "利普拉 + 单条词条应有 512 格被钳到 1，实际 \(libraSingle.clampedCells)",
        counter: &count
    )

    // ③ 一个逐格钉死的具体例子（页面上真会出现的那种）：
    //    铁之眼 15 级 + 利普拉（力气）后灵巧只剩 9，「提升感应，但降低灵巧」是 −9 → 钳到 1。
    guard let ironeye = index.modifiers(for: "ironeye").first(where: { $0.affixId == 6_642_000 }),
          let libraRow = index.libra("strength")?.level(15),
          let delta = ironeye.level(15)?.delta,
          let clampedSnapshot = index.snapshot(
              heroKey: "ironeye", level: 15, modifierIDs: [ironeye.affixId], libraKey: "strength"
          ) else {
        throw CheckFailure(description: "角色属性：无法计算铁之眼 15 级「利普拉（力气）+ 降低灵巧」快照")
    }
    try heroExpect(libraRow.stats["dexterity"] == 9, "利普拉（力气）15 级灵巧应为 9，实际 \(libraRow.stats["dexterity"] ?? -1)", counter: &count)
    try heroExpect(delta["dexterity"] == -9, "\(ironeye.shortName) 15 级灵巧增减量应为 −9，实际 \(delta["dexterity"] ?? 0)", counter: &count)
    try heroExpect(clampedSnapshot.requestedDelta["dexterity"] == -9, "原始增减量应保留 −9（不被钳位改写）", counter: &count)
    try heroExpect(clampedSnapshot.finalStats["dexterity"] == 1,
                   "9 − 9 = 0 应钳到 1，实际 \(clampedSnapshot.finalStats["dexterity"] ?? -1)", counter: &count)
    try heroExpect(clampedSnapshot.clampedStats == ["dexterity"],
                   "钳位列表应只有 dexterity，实际 \(clampedSnapshot.clampedStats)", counter: &count)
    try heroExpect(clampedSnapshot.effectiveDelta("dexterity") == -8,
                   "实际生效的增减量应是 −8（钳位吃掉 1 点），实际 \(clampedSnapshot.effectiveDelta("dexterity"))", counter: &count)

    return count
}

// MARK: - ⑥ 利普拉的交易

private func checkHeroLibra(_ index: HeroStatsIndex) throws -> Int {
    var count = 0

    let keys = index.libraRespecs.map(\.key)
    try heroExpect(
        Set(keys) == Set(["strength", "dexterity", "intelligence", "faith", "arcane"]),
        "利普拉的 5 笔交易应覆盖 力气/灵巧/智力/信仰/感应，实际 \(keys)",
        counter: &count
    )
    for respec in index.libraRespecs {
        try heroExpect(!respec.dealLineZh.isEmpty, "利普拉 \(respec.key) 应有对话文案 dealLineZh", counter: &count)
        try heroExpect(!respec.nameZh.isEmpty, "利普拉 \(respec.key) 应有中文名", counter: &count)
        try heroExpect(respec.shortTitle == index.statNames.attributeTitle(respec.statKey),
                       "利普拉 \(respec.key) 的短标签应等于属性中文名", counter: &count)
        try heroExpect(respec.levels.count == 15, "利普拉 \(respec.shortTitle) 应有 15 级", counter: &count)
        try heroExpect(respec.levels.map(\.level) == Array(1...15), "利普拉 \(respec.shortTitle) 等级应为 1–15 连续", counter: &count)
        try heroExpect(respec.display == respec.dealLineZh, "利普拉展示文案应优先用 dealLine", counter: &count)

        // 选中后基础表整套替换：与角色自身的表无关，10 个角色得到同一张基础表
        for hero in ["wylder", "recluse"] {
            for level in [1, 8, 15] {
                guard let snapshot = index.snapshot(heroKey: hero, level: level, libraKey: respec.key),
                      let expected = respec.level(level) else {
                    throw CheckFailure(description: "角色属性：无法计算 \(hero) \(level) 级利普拉快照")
                }
                try heroExpect(snapshot.baseStats == expected.stats,
                               "\(hero) \(level) 级选 \(respec.shortTitle) 后基础属性应整套替换", counter: &count)
                try heroExpect(snapshot.libraKey == respec.key, "快照应记录选中的利普拉交易", counter: &count)
                try heroExpect(snapshot.isModified, "选了利普拉应算「已修改」", counter: &count)
            }
        }
    }

    // 利普拉 + 转职遗物同时生效（按 libraRule 的推断）：在替换后的表上加减
    guard let respec = index.libra("strength"),
          let modifier = index.modifiers(for: "guardian").first,
          let snapshot = index.snapshot(
              heroKey: "guardian", level: 12, modifierIDs: [modifier.affixId], libraKey: "strength"
          ), let libraRow = respec.level(12), let delta = modifier.level(12)?.delta else {
        throw CheckFailure(description: "角色属性：无法计算守护者 12 级「利普拉 + 转职遗物」快照")
    }
    for key in index.statNames.attributeKeys {
        let expected = max(HeroStatsMath.minimumStat, (libraRow.stats[key] ?? 0) + (delta[key] ?? 0))
        try heroExpect(
            snapshot.finalStats[key] == expected,
            "守护者 12 级「利普拉（力气）+ \(modifier.shortName)」的 \(index.statNames.attributeTitle(key)) 应为 \(expected)，"
                + "实际 \(snapshot.finalStats[key] ?? -1)",
            counter: &count
        )
    }
    let recomputed = index.derivedValues(for: snapshot.finalStats)
    for key in index.statNames.derivedKeys {
        try heroExpectClose(snapshot.finalDerived[key] ?? 0, recomputed[key] ?? 0,
                            "利普拉叠加词条后的 \(index.statNames.derivedTitle(key)) 应按最终属性重算", counter: &count)
    }

    // 不选利普拉时用角色自己的表
    guard let plain = index.snapshot(heroKey: "guardian", level: 12),
          let guardian12 = index.hero("guardian")?.level(12) else {
        throw CheckFailure(description: "角色属性：无法计算守护者 12 级基础快照")
    }
    try heroExpect(plain.baseStats == guardian12.stats, "不选利普拉时基础表应是角色自己的", counter: &count)
    try heroExpect(plain.libraKey == nil, "不选利普拉时 libraKey 应为 nil", counter: &count)
    try heroExpect(index.libra(nil) == nil && index.libra("不存在") == nil, "未知利普拉 key 应返回 nil", counter: &count)

    return count
}

// MARK: - ⑦ 同级对比表与排序

private func checkHeroComparison(_ index: HeroStatsIndex) throws -> Int {
    var count = 0

    for level in [1, 12, 15] {
        let rows = index.comparisonRows(level: level)
        try heroExpect(rows.count == 10, "\(level) 级对比表应有 10 行，实际 \(rows.count)", counter: &count)
        try heroExpect(rows.allSatisfy { $0.level == level }, "对比表每行都应是 \(level) 级", counter: &count)
        try heroExpect(Set(rows.map(\.heroKey)).count == 10, "对比表不应有重复角色", counter: &count)
        for row in rows {
            guard let hero = index.hero(row.heroKey), let expected = hero.level(level) else {
                throw CheckFailure(description: "角色属性：对比表里的 \(row.heroKey) 找不到对应角色")
            }
            try heroExpect(row.stats == expected.stats, "\(row.nameZh) \(level) 级对比行属性应等于数据集", counter: &count)
            for key in index.statNames.derivedKeys {
                try heroExpectClose(row.derived[key] ?? 0, expected.derived[key] ?? 0,
                                    "\(row.nameZh) \(level) 级对比行 \(index.statNames.derivedTitle(key)) 应等于数据集", counter: &count)
            }
        }

        // 排序：升序 / 降序在每一列上都必须单调
        for key in index.statNames.attributeKeys {
            let column = HeroComparisonColumn.stat(key)
            let ascending = HeroComparison.sorted(rows, by: column, ascending: true)
            let descending = HeroComparison.sorted(rows, by: column, ascending: false)
            try heroExpect(ascending.count == rows.count && descending.count == rows.count,
                           "排序不应丢行（\(key)）", counter: &count)
            try heroExpect(Set(ascending.map(\.heroKey)) == Set(rows.map(\.heroKey)), "排序不应改变成员（\(key)）", counter: &count)
            let ascendingValues = ascending.compactMap { $0.value(for: column) }
            let descendingValues = descending.compactMap { $0.value(for: column) }
            try heroExpect(ascendingValues == ascendingValues.sorted(), "\(key) 升序应单调不减", counter: &count)
            try heroExpect(descendingValues == descendingValues.sorted(by: >), "\(key) 降序应单调不增", counter: &count)
        }
        for key in index.statNames.derivedKeys {
            let column = HeroComparisonColumn.derived(key)
            let descending = HeroComparison.sorted(rows, by: column, ascending: false)
            let values = descending.compactMap { $0.value(for: column) }
            try heroExpect(values == values.sorted(by: >), "\(key) 降序应单调不增", counter: &count)
        }

        // 角色列：升序 = 数据集顺序，降序 = 严格反序
        let byHero = HeroComparison.sorted(rows, by: .hero, ascending: true)
        try heroExpect(byHero.map(\.heroId) == index.heroes.map(\.id), "角色列升序应等于数据集顺序", counter: &count)
        let byHeroDescending = HeroComparison.sorted(rows, by: .hero, ascending: false)
        try heroExpect(byHeroDescending.map(\.heroId) == index.heroes.map(\.id).reversed(), "角色列降序应是反序", counter: &count)
    }

    // 平手时退回数据集顺序（稳定排序）：15 级感应有多组相同值
    let rows = index.comparisonRows(level: 15)
    let column = HeroComparisonColumn.stat("arcane")
    let sorted = HeroComparison.sorted(rows, by: column, ascending: true)
    for (left, right) in zip(sorted, sorted.dropFirst()) where left.stats["arcane"] == right.stats["arcane"] {
        try heroExpect(left.heroId < right.heroId, "平手时应按数据集顺序排（\(left.nameZh) / \(right.nameZh)）", counter: &count)
    }
    // 稳定排序的直接后果：数值列上「点两次列头」**不是**严格反序（平手行不翻面）。
    // HeroData.swift 的文档注释与 Windows 端 heroes.test.mjs 都按这条写，别钉成 asc == desc.reversed()。
    let mind = HeroComparisonColumn.stat("mind")
    let mindAscending = HeroComparison.sorted(rows, by: mind, ascending: true)
    let mindDescending = HeroComparison.sorted(rows, by: mind, ascending: false)
    try heroExpect(
        mindAscending.map(\.heroKey) != mindDescending.reversed().map(\.heroKey),
        "15 级集中力一列有平手（守护者 / 铁之眼 / 送葬者 同为 14），降序不应是升序的严格反转",
        counter: &count
    )
    for direction in [mindAscending, mindDescending] {
        let tied = direction.filter { $0.stats["mind"] == 14 }
        try heroExpect(tied.map(\.heroId) == tied.map(\.heroId).sorted(),
                       "平手的几行在两个方向上都应保持数据集顺序，实际 \(tied.map(\.nameZh))", counter: &count)
    }

    // 缺数据的列：所有行都没有这一列时顺序退回数据集顺序
    let unknown = HeroComparison.sorted(rows, by: .stat("nope"), ascending: false)
    try heroExpect(unknown.map(\.heroId) == index.heroes.map(\.id), "未知列应退回数据集顺序", counter: &count)

    // 超出范围的等级：没有对应行，返回空表而不是崩
    try heroExpect(index.comparisonRows(level: 99).isEmpty, "99 级应没有对比行", counter: &count)
    try heroExpect(index.snapshot(heroKey: "wylder", level: 99) == nil, "99 级快照应为 nil", counter: &count)
    try heroExpect(index.snapshot(heroKey: "不存在", level: 1) == nil, "未知角色快照应为 nil", counter: &count)
    try heroExpect(index.snapshots(heroKey: "wylder").count == 15, "全部等级表应有 15 行", counter: &count)

    return count
}

// MARK: - ⑧ 页面文案

private func checkHeroText(_ index: HeroStatsIndex) throws -> Int {
    var count = 0

    try heroExpect(HeroStatsText.signed(5) == "+5", "正增减量应带 +", counter: &count)
    try heroExpect(HeroStatsText.signed(-3) == "-3", "负增减量应带 -", counter: &count)
    try heroExpect(HeroStatsText.signed(0) == "0", "0 不加符号", counter: &count)
    try heroExpect(HeroStatsText.signed(2.5) == "+2.5", "正的小数增减量应带 +", counter: &count)
    try heroExpect(HeroStatsText.signed(-0.5) == "-0.5", "负的小数增减量应带 -", counter: &count)
    try heroExpect(HeroStatsText.decimal(74.1) == "74.1", "74.1 应原样显示", counter: &count)
    try heroExpect(HeroStatsText.decimal(45.0) == "45", "45.0 应去掉小数点", counter: &count)
    try heroExpect(HeroStatsText.decimal(1120) == "1120", "整数派生值不带小数点", counter: &count)

    let anchors = index.dataset.interpolation.modifierAnchorLevels
    // 三种来源都要有话说：锚点也标出来（上一轮锚点级什么都不标，页面上「勾了词条但
    // 没有任何来源标记」与「没勾词条」长得一样）。锚点等级一律读数据集，不写死 1 / 12。
    try heroExpect(HeroStatsText.modifierSource(level: 1, anchorLevels: anchors)?.source == .anchor,
                   "1 级应判为词条锚点", counter: &count)
    try heroExpect(HeroStatsText.modifierSource(level: 1, anchorLevels: anchors)?.label == "词条锚点",
                   "1 级应标「词条锚点」", counter: &count)
    try heroExpect(HeroStatsText.modifierSource(level: 12, anchorLevels: anchors)?.label == "词条锚点",
                   "12 级应标「词条锚点」", counter: &count)
    try heroExpect(HeroStatsText.modifierSource(level: 6, anchorLevels: anchors)?.source == .inferred,
                   "2–11 级应判为推算", counter: &count)
    try heroExpect(HeroStatsText.modifierSource(level: 6, anchorLevels: anchors)?.label == "词条推算",
                   "2–11 级应标「词条推算」", counter: &count)
    try heroExpect(HeroStatsText.modifierSource(level: 15, anchorLevels: anchors)?.source == .carried,
                   "13–15 级应判为沿用锚点", counter: &count)
    try heroExpect(HeroStatsText.modifierSource(level: 15, anchorLevels: anchors)?.label == "词条沿用 12 级锚点",
                   "13–15 级应标「词条沿用 12 级锚点」", counter: &count)
    try heroExpect(HeroStatsText.modifierSource(level: 3, anchorLevels: []) == nil, "没有锚点信息时不标记", counter: &count)
    // 锚点表换一组数字，标记要跟着走（不能写死 12）
    try heroExpect(HeroStatsText.modifierSource(level: 9, anchorLevels: [1, 8])?.label == "词条沿用 8 级锚点",
                   "沿用文案里的等级应取自数据集锚点表", counter: &count)

    // 缺数值时一律破折号，不要退回 0（0 是真实数值）
    try heroExpect(HeroStatsText.statText(nil) == HeroStatsCopy.missing, "缺属性值应显示破折号", counter: &count)
    try heroExpect(HeroStatsText.statText(0) == "0", "属性值 0 应原样显示", counter: &count)
    try heroExpect(HeroStatsText.derivedText(nil, integer: true) == HeroStatsCopy.missing,
                   "缺派生值应显示破折号", counter: &count)
    try heroExpect(HeroStatsText.derivedText(0, integer: true) == "0", "派生值 0 应原样显示", counter: &count)
    try heroExpect(HeroStatsText.derivedText(74.1, integer: false) == "74.1", "负重上限保留 1 位小数", counter: &count)
    // 固定 1 位小数：45.0 不能写成「45」，否则整列小数点对不齐（Windows 端 fmtDerived 同口径）
    try heroExpect(HeroStatsText.derivedText(45, integer: false) == "45.0", "负重上限固定 1 位小数", counter: &count)
    try heroExpect(HeroStatsText.derivedText(72, integer: false) == "72.0", "负重上限固定 1 位小数（整数值）", counter: &count)
    try heroExpect(HeroStatsText.derivedText(1120, integer: true) == "1120", "整数派生值不带小数点", counter: &count)

    try heroExpect(index.summary.contains("10 位夜行者"), "页面摘要应写角色数，实际 \(index.summary)", counter: &count)
    try heroExpect(index.summary.contains("1–15 级"), "页面摘要应写等级范围，实际 \(index.summary)", counter: &count)

    return count
}

// MARK: - ⑨ 宽容解码

private func checkHeroLenientDecoding() throws -> Int {
    var count = 0

    func index(_ json: String) throws -> HeroStatsIndex {
        try HeroStatsIndex(data: Data(json.utf8))
    }

    // 顶层不是对象 / 没有角色：抛可读错误
    do {
        _ = try index("[]")
        throw CheckFailure(description: "角色属性：数组顶层应抛 notAnObject")
    } catch is HeroDataError {
        count += 1
    }
    do {
        _ = try index("{\"heroes\":[]}")
        throw CheckFailure(description: "角色属性：空角色表应抛 empty")
    } catch is HeroDataError {
        count += 1
    }
    try heroExpect(HeroDataError.notAnObject.errorDescription?.isEmpty == false, "错误应有中文描述", counter: &count)
    try heroExpect(HeroDataError.empty.errorDescription?.isEmpty == false, "空数据错误应有中文描述", counter: &count)
    try heroExpect(HeroDataError.undecodable("x").errorDescription?.contains("x") == true, "解码错误应带上细节", counter: &count)

    // 未知字段忽略、缺字段退默认值、坏元素跳过
    let json = """
    {
      "schemaVersion": 1,
      "brandNewTopLevelField": {"whatever": true},
      "statNames": {
        "attributeOrder": ["vigor", "mind"],
        "derivedOrder": ["hp"],
        "attributes": [
          {"key": "vigor", "zh": "生命力", "en": "Vigor", "futureField": 1},
          "坏元素",
          {"key": "mind", "zh": "集中力", "en": "Mind"}
        ],
        "derived": [{"key": "hp", "zh": "血量", "en": "HP", "fromStat": "vigor", "graphId": 100, "integer": true}]
      },
      "growthGraphs": {
        "100": {"id": 100, "name": "HP", "stageMaxVal": [1, 25], "stageMaxGrowVal": [100, 580], "adjPt": [1, 1], "linear": true, "usedFor": ["hp"]},
        "999": "坏元素"
      },
      "heroes": [
        {"id": 1, "key": "wylder", "nameZh": "追踪者", "nameEn": "Wylder",
         "levels": [
           {"level": 2, "isAnchor": true, "stats": {"vigor": 16, "mind": 6}, "derived": {"hp": 400}},
           {"level": 1, "isAnchor": true, "stats": {"vigor": 8, "mind": 4}, "derived": {"hp": 240}},
           "坏元素"
         ]},
        "坏元素"
      ],
      "statModifiers": [
        {"affixId": 6640000, "nameZh": "【追踪者】提升集中力，但降低生命力", "heroKey": "wylder",
         "affectedStats": ["vigor", "mind"],
         "levels": [{"level": 1, "isAnchor": true, "inferred": false, "delta": {"vigor": -1, "mind": 1}}]}
      ],
      "libraRespecs": ["坏元素"]
    }
    """
    let decoded = try index(json)
    try heroExpect(decoded.heroes.count == 1, "坏的角色元素应被跳过，实际 \(decoded.heroes.count)", counter: &count)
    try heroExpect(decoded.heroes[0].levels.count == 2, "坏的等级元素应被跳过", counter: &count)
    try heroExpect(decoded.heroes[0].levels.map(\.level) == [1, 2], "等级应按 level 排序", counter: &count)
    try heroExpect(decoded.statNames.attributes.count == 2, "坏的属性名元素应被跳过", counter: &count)
    try heroExpect(decoded.statNames.attributeTitle("vigor") == "生命力", "属性中文名应解出来", counter: &count)
    try heroExpect(decoded.dataset.growthGraphs.count == 1, "坏的 growthGraph 应被跳过", counter: &count)
    try heroExpect(decoded.dataset.libraRespecs.isEmpty, "坏的利普拉元素应被跳过", counter: &count)
    try heroExpect(decoded.dataset.gameVersion.isEmpty, "缺失的 gameVersion 应退回空串而不是抛错", counter: &count)
    try heroExpect(decoded.dataset.caveats.isEmpty, "缺失的 caveats 应退回空数组", counter: &count)
    try heroExpect(decoded.dataset.interpolation.maxLevel == 0,
                   "缺失的 interpolation 不该假装声明了最大等级", counter: &count)
    try heroExpect(decoded.dataset.interpolation.notes.isEmpty, "缺失的 interpolation 不应生成说明条目", counter: &count)
    // 缺 interpolation 时最大等级退回角色表（这份样本只有 1–2 级），而不是硬写 15
    try heroExpect(decoded.maxLevel == 2, "缺失 interpolation 时应退回角色表的最大等级，实际 \(decoded.maxLevel)",
                   counter: &count)
    try heroExpect(decoded.levelRange == [1, 2], "等级范围同样跟着角色表走", counter: &count)

    // 缺 growthGraph 的派生值：跳过而不是算出 0
    let derived = decoded.derivedValues(for: ["vigor": 8, "mind": 4])
    try heroExpectClose(derived["hp"] ?? 0, 240, "重算血量应为 240", counter: &count)
    try heroExpect(derived["equipLoad"] == nil, "没有 220 行时不应编出负重上限", counter: &count)

    // 单条词条只有 1 级：其他等级的快照不带增减量，也不应崩
    guard let level1 = decoded.snapshot(heroKey: "wylder", level: 1, modifierIDs: [6640000]),
          let level2 = decoded.snapshot(heroKey: "wylder", level: 2, modifierIDs: [6640000]) else {
        throw CheckFailure(description: "角色属性：宽容解码样本的快照不应为 nil")
    }
    try heroExpect(level1.finalStats["vigor"] == 7 && level1.finalStats["mind"] == 5, "1 级应叠加 −1 / +1", counter: &count)
    try heroExpect(level2.finalStats == level2.baseStats, "缺少 2 级 delta 时应保持基础值", counter: &count)
    try heroExpect(level2.activeModifiers.count == 1, "词条仍算生效（只是没有该级数据）", counter: &count)

    // 图表端点非法时求值返回 0 而不是崩
    let brokenGraph = HeroGrowthGraph(
        id: 1, name: "broken", stageMaxVal: [1], stageMaxGrowVal: [], adjPt: [], linear: true, usedFor: []
    )
    try heroExpect(!brokenGraph.isUsable, "端点数组不等长应判为不可用", counter: &count)
    try heroExpect(brokenGraph.value(at: 10) == 0 && brokenGraph.integerValue(at: 10) == 0, "不可用图表应返回 0", counter: &count)

    return count
}

// MARK: - ⑩ 双端对照基线

/// 一组双端对照用例：同样的角色 / 等级 / 词条 / 利普拉，两端钉死同一批期望值。
///
/// Windows 端 `tests/heroes.test.mjs` 里有一张一模一样的 `FIXTURES` 表，跑的是同一批
/// 断言（绝对值 + 相对关系）。任何一端的纯逻辑漂了，两端的用例会各自红 —— 这就是
/// 「双端一致」的可执行定义，而不是靠注释互相声称。
private struct HeroFixture {
    let name: String
    let heroKey: String
    let level: Int
    let modifierIDs: [Int]
    let libraKey: String?
    let isAnchor: Bool
    /// 按 statNames.attributeOrder 排的 8 项。
    let baseStats: [Int]
    let baseDerived: [String: Double]
    let delta: [String: Int]
    /// 卡片 / 表格里真正显示的那个数：**生效**增减量（最终 − 基础）。
    /// 没钳位时与 delta 相同；被钳时比 delta 小（请求 -9、生效 -8）。
    /// Windows 端 FIXTURES 里有同名同值的一张表。
    let cardDelta: [String: Int]
    /// nil = 没勾词条，不该产生「修改后」的表。
    let finalStats: [Int]?
    let finalDerived: [String: Double]?
    let clampedFrom: [String: Int]
    var clampSummary: String? = nil
    /// 被钳位的卡片上那行小字（请求值只出现在这里）。
    var clampRequestedText: String? = nil
    var floorAlt: [String: Int]? = nil
    var floorAltText: String? = nil
    var sourceLabel: String? = nil
    var source: HeroModifierSource? = nil
}

private let heroFixtures: [HeroFixture] = [
    HeroFixture(
        name: "追踪者 15 级：两条词条全勾",
        heroKey: "wylder", level: 15, modifierIDs: [6_640_000, 6_640_100], libraKey: nil,
        isAnchor: true,
        baseStats: [52, 19, 27, 50, 40, 15, 15, 10],
        baseDerived: ["hp": 1120, "fp": 140, "stamina": 102, "equipLoad": 74.1],
        delta: ["vigor": -5, "mind": 10, "strength": -7, "dexterity": -5, "intelligence": 15, "faith": 15],
        cardDelta: ["vigor": -5, "mind": 10, "strength": -7, "dexterity": -5, "intelligence": 15, "faith": 15],
        finalStats: [47, 29, 27, 43, 35, 30, 30, 10],
        finalDerived: ["hp": 1020, "fp": 190, "stamina": 102, "equipLoad": 74.1],
        clampedFrom: [:],
        sourceLabel: "词条沿用 12 级锚点", source: .carried
    ),
    HeroFixture(
        name: "铁之眼 15 级：利普拉（力气）+ 降灵巧词条（会钳位）",
        heroKey: "ironeye", level: 15, modifierIDs: [6_642_000], libraKey: "strength",
        isAnchor: true,
        baseStats: [47, 6, 23, 73, 9, 3, 3, 3],
        baseDerived: ["hp": 1020, "fp": 75, "stamina": 94, "equipLoad": 68.8],
        delta: ["dexterity": -9, "arcane": 15],
        // 灵巧被钳到 1：词条请求 -9，真正生效的只有 -8。卡片上的大数字写 -8，
        // 请求值 -9 只出现在小字里 —— 上一轮 Windows 写 -9、macOS 写 -8。
        cardDelta: ["dexterity": -8, "arcane": 15],
        finalStats: [47, 6, 23, 73, 1, 3, 3, 18],
        finalDerived: ["hp": 1020, "fp": 75, "stamina": 94, "equipLoad": 68.8],
        clampedFrom: ["dexterity": 0],
        clampSummary: "灵巧 叠加后不足 1，已钳到最低 1（游戏里属性不会低于 1）",
        clampRequestedText: "词条请求 -9，已钳到最低 1",
        sourceLabel: "词条沿用 12 级锚点", source: .carried
    ),
    HeroFixture(
        name: "学者 5 级：第 2 条词条（有 deltaFloorAlt）",
        heroKey: "scholar", level: 5, modifierIDs: [6_647_300], libraKey: nil,
        isAnchor: false,
        baseStats: [20, 9, 10, 5, 7, 12, 6, 50],
        baseDerived: ["hp": 480, "fp": 90, "stamina": 68, "equipLoad": 48.2],
        delta: ["endurance": 2, "dexterity": 18, "intelligence": -2, "arcane": -10],
        cardDelta: ["endurance": 2, "dexterity": 18, "intelligence": -2, "arcane": -10],
        finalStats: [20, 9, 12, 5, 25, 10, 6, 40],
        finalDerived: ["hp": 480, "fp": 90, "stamina": 72, "equipLoad": 51.4],
        clampedFrom: [:],
        floorAlt: ["intelligence": -3, "arcane": -11],
        floorAltText: "若按 floor 取整，负向项改为：智力 -3、感应 -11（其余项不变）",
        sourceLabel: "词条推算", source: .inferred
    ),
    HeroFixture(
        name: "女爵 12 级：不勾词条",
        heroKey: "duchess", level: 12, modifierIDs: [], libraKey: nil,
        isAnchor: true,
        baseStats: [35, 24, 14, 9, 38, 36, 24, 11],
        baseDerived: ["hp": 780, "fp": 165, "stamina": 76, "equipLoad": 54.5],
        delta: [:], cardDelta: [:], finalStats: nil, finalDerived: nil, clampedFrom: [:]
    ),
    HeroFixture(
        name: "送葬者 1 级：不勾词条",
        heroKey: "undertaker", level: 1, modifierIDs: [], libraKey: nil,
        isAnchor: true,
        baseStats: [7, 4, 3, 5, 2, 2, 5, 10],
        baseDerived: ["hp": 220, "fp": 65, "stamina": 54, "equipLoad": 45],
        delta: [:], cardDelta: [:], finalStats: nil, finalDerived: nil, clampedFrom: [:]
    )
]

private func checkHeroCrossEndFixtures(_ index: HeroStatsIndex) throws -> Int {
    var count = 0
    let names = index.statNames
    let keys = names.attributeKeys
    let anchors = index.dataset.interpolation.modifierAnchorLevels

    for fixture in heroFixtures {
        guard let snapshot = index.snapshot(
            heroKey: fixture.heroKey, level: fixture.level,
            modifierIDs: Set(fixture.modifierIDs), libraKey: fixture.libraKey
        ) else {
            throw CheckFailure(description: "角色属性：\(fixture.name) 应能算出快照")
        }
        try heroExpect(snapshot.isAnchorLevel == fixture.isAnchor,
                       "\(fixture.name)：基础表锚点标记应为 \(fixture.isAnchor)", counter: &count)
        let base = keys.map { snapshot.baseStats[$0] ?? -1 }
        try heroExpect(base == fixture.baseStats,
                       "\(fixture.name)：基础属性应为 \(fixture.baseStats)，实际 \(base)", counter: &count)
        for key in names.derivedKeys {
            try heroExpectClose(snapshot.baseDerived[key] ?? .nan, fixture.baseDerived[key] ?? .nan,
                                "\(fixture.name)：基础 \(names.derivedTitle(key))", counter: &count)
        }

        guard let expectedFinal = fixture.finalStats, let expectedFinalDerived = fixture.finalDerived else {
            try heroExpect(!snapshot.hasModifier, "\(fixture.name)：没勾词条就不该有生效词条", counter: &count)
            try heroExpect(snapshot.finalStats == snapshot.baseStats,
                           "\(fixture.name)：没勾词条时最终属性应等于基础属性", counter: &count)
            try heroExpect(snapshot.requestedDelta.isEmpty, "\(fixture.name)：没勾词条就没有增减量", counter: &count)
            try heroExpect(snapshot.clampedStats.isEmpty && snapshot.clampedFrom.isEmpty,
                           "\(fixture.name)：没勾词条不会钳位", counter: &count)
            continue
        }

        for key in keys {
            try heroExpect((snapshot.requestedDelta[key] ?? 0) == (fixture.delta[key] ?? 0),
                           "\(fixture.name)：\(names.attributeTitle(key)) 增减量应为 \(fixture.delta[key] ?? 0)，"
                               + "实际 \(snapshot.requestedDelta[key] ?? 0)", counter: &count)
        }
        // 卡片 / 表格上真正显示的那个数是**生效值**（最终 − 基础）：钳位时它比请求值小。
        // Windows 端 FIXTURES 的 cardDelta 是同一张表，两端不可能再一个写 -9、一个写 -8。
        for key in keys {
            try heroExpect(snapshot.effectiveDelta(key) == (fixture.cardDelta[key] ?? 0),
                           "\(fixture.name)：\(names.attributeTitle(key)) 卡片上显示的增减量（生效值）应为 "
                               + "\(fixture.cardDelta[key] ?? 0)，实际 \(snapshot.effectiveDelta(key))", counter: &count)
        }
        let final = keys.map { snapshot.finalStats[$0] ?? -1 }
        try heroExpect(final == expectedFinal,
                       "\(fixture.name)：最终属性应为 \(expectedFinal)，实际 \(final)", counter: &count)
        for key in names.derivedKeys {
            try heroExpectClose(snapshot.finalDerived[key] ?? .nan, expectedFinalDerived[key] ?? .nan,
                                "\(fixture.name)：最终 \(names.derivedTitle(key))", counter: &count)
        }
        try heroExpect(snapshot.clampedFrom == fixture.clampedFrom,
                       "\(fixture.name)：钳位前原值应为 \(fixture.clampedFrom)，实际 \(snapshot.clampedFrom)",
                       counter: &count)
        // 钳位列表按属性展示顺序（与页面上 8 张卡片同序）
        let expectedClamped = keys.filter { fixture.clampedFrom[$0] != nil }
        try heroExpect(snapshot.clampedStats == expectedClamped,
                       "\(fixture.name)：钳位列表应为 \(expectedClamped)，实际 \(snapshot.clampedStats)",
                       counter: &count)

        let tag = HeroStatsText.modifierSource(level: fixture.level, anchorLevels: anchors)
        try heroExpect(tag?.label == fixture.sourceLabel,
                       "\(fixture.name)：增减量来源文案应为 \(fixture.sourceLabel ?? "—")，实际 \(tag?.label ?? "—")",
                       counter: &count)
        try heroExpect(tag?.source == fixture.source, "\(fixture.name)：增减量来源分类", counter: &count)

        // 相对断言①：最终值恒等于 max(1, 基础 + 增减量)
        for key in keys {
            let raw = (snapshot.baseStats[key] ?? 0) + (snapshot.requestedDelta[key] ?? 0)
            try heroExpect(snapshot.finalStats[key] == max(HeroStatsMath.minimumStat, raw),
                           "\(fixture.name)：\(names.attributeTitle(key)) 钳位口径", counter: &count)
            try heroExpect((snapshot.clampedFrom[key] != nil) == (raw < HeroStatsMath.minimumStat),
                           "\(fixture.name)：\(names.attributeTitle(key)) 是否记为钳位", counter: &count)
        }
        // 相对断言②：派生值一律由最终属性复算，而不是拿未钳位的属性算
        let recomputed = index.derivedValues(for: snapshot.finalStats)
        for key in names.derivedKeys {
            try heroExpectClose(snapshot.finalDerived[key] ?? .nan, recomputed[key] ?? .nan,
                                "\(fixture.name)：\(names.derivedTitle(key)) 应按钳位后的属性重算", counter: &count)
        }

        if let expectedNote = fixture.clampRequestedText {
            // 卡片小字：请求值只出现在这里，大数字写的是生效值
            try heroExpect(snapshot.clampedStats.count == 1, "\(fixture.name)：本组只应有一项被钳", counter: &count)
            guard let clampedKey = snapshot.clampedStats.first else {
                throw CheckFailure(description: "角色属性：\(fixture.name) 应有一项被钳")
            }
            let note = HeroStatsCopy.clampRequestedNote(snapshot.requestedDelta[clampedKey] ?? 0)
            try heroExpect(note == expectedNote,
                           "\(fixture.name)：钳位小字应为「\(expectedNote)」，实际「\(note)」", counter: &count)
            try heroExpect(snapshot.effectiveDelta(clampedKey) != (snapshot.requestedDelta[clampedKey] ?? 0),
                           "\(fixture.name)：被钳的那一项，生效值与请求值本来就不该相等", counter: &count)
        }
        if let expected = fixture.clampSummary {
            let text = HeroStatsCopy.clampSummary(snapshot.clampedStats.map { names.attributeTitle($0) })
            try heroExpect(text == expected,
                           "\(fixture.name)：钳位汇总文案应为「\(expected)」，实际「\(text)」", counter: &count)
        }
        if let expectedAlt = fixture.floorAlt, let expectedText = fixture.floorAltText {
            guard let affixID = fixture.modifierIDs.first,
                  let modifier = index.modifiers(for: fixture.heroKey).first(where: { $0.affixId == affixID }),
                  let row = modifier.level(fixture.level) else {
                throw CheckFailure(description: "角色属性：\(fixture.name) 找不到词条的这一级")
            }
            try heroExpect(row.deltaFloorAlt == expectedAlt,
                           "\(fixture.name)：deltaFloorAlt 应为 \(expectedAlt)，实际 \(row.deltaFloorAlt)", counter: &count)
            let text = HeroStatsCopy.floorAlt(HeroStatsCopy.deltaSummary(row.deltaFloorAlt, names: names))
            try heroExpect(text == expectedText,
                           "\(fixture.name)：deltaFloorAlt 文案应为「\(expectedText)」，实际「\(text)」", counter: &count)
            // deltaFloorAlt 恒为负向项、且恰好比 trunc 少 1（floor 与 trunc 只在负数上差 1）
            for (key, value) in row.deltaFloorAlt {
                try heroExpect(value < 0, "\(fixture.name)：deltaFloorAlt 只会出现在负向项上（\(key) = \(value)）",
                               counter: &count)
                try heroExpect(value == (row.delta[key] ?? 0) - 1,
                               "\(fixture.name)：\(key) 的 floor 版应比 trunc 版少 1", counter: &count)
            }
        }
    }

    // 第 6 组：同级对比 10 级按血量降序，前三名与兜底顺序
    let rows = index.comparisonRows(level: 10)
    try heroExpect(rows.count == 10, "10 级对比表应有 10 行，实际 \(rows.count)", counter: &count)
    let byHP = HeroComparison.sorted(rows, by: .derived("hp"), ascending: false)
    let topNames = byHP.prefix(3).map(\.nameZh)
    try heroExpect(topNames == ["守护者", "无赖", "追踪者"],
                   "10 级血量前三名应是 守护者 / 无赖 / 追踪者，实际 \(topNames)", counter: &count)
    let topHP = byHP.prefix(3).compactMap { $0.derived["hp"] }
    try heroExpect(topHP == [1020, 940, 880], "10 级血量前三名应是 1020 / 940 / 880，实际 \(topHP)", counter: &count)
    let topVigor = byHP.prefix(3).compactMap { $0.stats["vigor"] }
    try heroExpect(topVigor == [47, 43, 40], "10 级血量前三名的生命力应是 47 / 43 / 40，实际 \(topVigor)", counter: &count)
    // 相对断言：降序单调不增，且血量恒等于 20 × 生命力 + 80（CalcCorrectGraph 100 的斜率）
    let hpValues = byHP.compactMap { $0.derived["hp"] }
    try heroExpect(hpValues == hpValues.sorted(by: >), "血量降序应单调不增", counter: &count)
    for row in byHP {
        try heroExpectClose(row.derived["hp"] ?? .nan, Double(20 * (row.stats["vigor"] ?? 0) + 80),
                            "\(row.nameZh) 的血量应等于 20 × 生命力 + 80", counter: &count)
    }

    return count
}

// MARK: - ⑪ 双端共用文案

/// 两端必须逐字相同的那批字符串。Windows 端 `tests/heroes.test.mjs` 的
/// 「双端共用文案 COPY」用例逐条断言同一批字面量。
private func checkHeroCrossEndCopy(_ index: HeroStatsIndex) throws -> Int {
    var count = 0
    let names = index.statNames

    try heroExpect(HeroStatsCopy.missing == "—", "缺值占位符", counter: &count)
    try heroExpect(HeroStatsCopy.emptyData == "数据未内置", "数据未内置", counter: &count)
    try heroExpect(HeroStatsCopy.viewSingle == "单角色", "单角色视图名", counter: &count)
    try heroExpect(HeroStatsCopy.viewCompare == "同级对比", "同级对比视图名", counter: &count)

    try heroExpect(HeroStatsCopy.baseLevelBadge(level: 15, isAnchor: true) == "15 级是参数锚点",
                   "锚点等级徽标", counter: &count)
    try heroExpect(HeroStatsCopy.baseLevelBadge(level: 7, isAnchor: false) == "7 级为插值推算",
                   "插值等级徽标", counter: &count)
    try heroExpect(HeroStatsCopy.baseAnchorTag == "参数锚点", "表内锚点标记", counter: &count)
    try heroExpect(HeroStatsCopy.baseInterpolatedTag == "插值推算", "表内插值标记", counter: &count)
    try heroExpect(
        HeroStatsCopy.allLevelsCaption(anchorLevels: [1, 2, 12, 15])
            == "加粗行是参数表里的锚点（1 / 2 / 12 / 15 级），其余等级按相邻锚点线性插值后向下取整。",
        "全部等级表脚注", counter: &count
    )

    try heroExpect(HeroStatsCopy.modifierCountBadge(2) == "转职遗物 2 条", "词条条数徽标", counter: &count)
    try heroExpect(
        HeroStatsCopy.modifierSubtitle == "勾选后在基础属性上加减（可同时勾选，效果相加）；派生值按 CalcCorrectGraph 重算",
        "转职遗物卡片副标题", counter: &count
    )
    try heroExpect(HeroStatsCopy.dlcOnlyTag == "仅 DLC 池可掉", "DLC 词条标记", counter: &count)
    try heroExpect(HeroStatsCopy.noDeltaAtLevel == "本级无增减", "本级无增减", counter: &count)
    try heroExpect(HeroStatsCopy.noModifierData == "数据未内置该角色的转职遗物词条", "缺词条数据", counter: &count)
    try heroExpect(
        HeroStatsCopy.floorAlt("智力 -3、感应 -11") == "若按 floor 取整，负向项改为：智力 -3、感应 -11（其余项不变）",
        "deltaFloorAlt 文案", counter: &count
    )

    try heroExpect(HeroStatsCopy.clampCellTag == "钳", "表内钳位角标", counter: &count)
    try heroExpect(HeroStatsCopy.clampRowTag == "已钳位", "表内钳位行标", counter: &count)
    try heroExpect(HeroStatsCopy.clampedFromNote(0) == "原为 0，已钳到最低 1", "钳位前原值（0）", counter: &count)
    try heroExpect(HeroStatsCopy.clampedFromNote(-3) == "原为 -3，已钳到最低 1", "钳位前原值（负）", counter: &count)
    try heroExpect(HeroStatsCopy.clampRequestedNote(-9) == "词条请求 -9，已钳到最低 1", "钳位小字（请求值）", counter: &count)
    try heroExpect(HeroStatsCopy.clampRequestedNote(-13) == "词条请求 -13，已钳到最低 1",
                   "钳位小字（请求值，另一条词条）", counter: &count)
    try heroExpect(
        HeroStatsCopy.clampSummary(["生命力", "集中力"]) == "生命力、集中力 叠加后不足 1，已钳到最低 1（游戏里属性不会低于 1）",
        "单等级钳位汇总", counter: &count
    )
    try heroExpect(
        HeroStatsCopy.clampSummaryByLevel([(13, ["灵巧"]), (15, ["灵巧", "感应"])], maxLevel: 15)
            == "1–15 级里有 2 级叠加后不足 1：13 级 灵巧；15 级 灵巧、感应；已钳到最低 1（游戏里属性不会低于 1）",
        "全部等级钳位汇总（按行聚合）", counter: &count
    )
    try heroExpect(HeroStatsCopy.clampSummaryByLevel([], maxLevel: 15).isEmpty, "没钳位时不写汇总", counter: &count)

    try heroExpect(HeroStatsCopy.libraSwapTag == "整套替换", "利普拉整套替换标记", counter: &count)
    try heroExpect(
        HeroStatsCopy.libraHint == "利普拉的交易把整套基础属性表替换掉；能否与转职遗物叠加是按参数字段结构推断的，未实测",
        "利普拉提示", counter: &count
    )
    try heroExpect(HeroStatsCopy.libraEmptyHint == "选中后基础表整套换成对应的替换表，转职遗物仍可叠加。",
                   "未选利普拉时的提示", counter: &count)
    try heroExpect(HeroStatsCopy.libraBadge("力气") == "利普拉：力气", "利普拉徽标", counter: &count)
    try heroExpect(
        HeroStatsCopy.libraCrossCheckNote == "已做利普拉的交易，基础表整套替换，与外部 wiki 的角色原表差异不再适用",
        "选了利普拉后的 wiki 差异说明", counter: &count
    )
    try heroExpect(
        HeroStatsCopy.crossCheckNote(count: 14, note: "补丁 1.02.2") == "与外部 wiki 有 14 格差异，本页以参数为准：补丁 1.02.2",
        "wiki 差异提示", counter: &count
    )
    try heroExpect(
        HeroStatsCopy.crossCheckNote(count: 14, note: "") == "与外部 wiki 有 14 格差异，本页以参数为准",
        "wiki 差异提示（无补充说明）", counter: &count
    )

    try heroExpect(HeroStatsCopy.legacyMark == "*", "遗留列注记符", counter: &count)
    try heroExpect(HeroStatsCopy.legacyHeader("负重上限") == "负重上限 *", "遗留列列头", counter: &count)
    try heroExpect(
        HeroStatsCopy.equipLoadHint == "本作装备没有重量，负重上限是《艾尔登法环》继承下来的遗留列，未经实测",
        "负重上限小字", counter: &count
    )
    try heroExpect(
        HeroStatsCopy.equipLoadFootnote
            == "* 负重上限是《艾尔登法环》继承下来的遗留列：本作装备没有重量、界面也没有负重条，未经实测，仅供参考。",
        "负重上限脚注", counter: &count
    )

    try heroExpect(
        HeroStatsCopy.compareCaption
            == "对比表只用各角色的基础表：利普拉的交易不分角色（叠上去每行都一样），转职遗物是逐角色的词条，都不进对比。",
        "对比表脚注", counter: &count
    )

    // 折叠区标题里的 N 两端必须是同一个数：两端渲染的都是 notes 那 10 条
    // （Windows 端 interpolationNotes(data) 同序同文），不再是一端数字段、一端数条目。
    try heroExpect(HeroStatsCopy.interpolationTitle(10) == "插值与验证口径（10 条）", "折叠区标题①", counter: &count)
    try heroExpect(
        HeroStatsCopy.interpolationTitle(index.dataset.interpolation.notes.count) == "插值与验证口径（10 条）",
        "折叠区标题①的 N 就是实际渲染的条数", counter: &count
    )
    try heroExpect(HeroStatsCopy.caveatsTitle(13) == "已知取舍（13 条）", "折叠区标题②", counter: &count)
    try heroExpect(HeroStatsCopy.sourcesTitle(10) == "数据出处（10 条）与外部对照", "折叠区标题③", counter: &count)
    try heroExpect(HeroStatsCopy.versionLabels == ["游戏版本", "数据版本", "生成时间", "数据集结构版本", "收录"],
                   "数据版本块的 5 行标签", counter: &count)
    try heroExpect(
        HeroStatsCopy.contentSummary(heroes: 10, maxLevel: 15, modifiers: 20, libra: 5)
            == "10 位夜行者 × 15 级 · 20 条转职遗物词条 · 5 笔利普拉交易",
        "数据版本块的「收录」", counter: &count
    )

    // 增减量摘要：按属性展示顺序、跳过 0、带正负号
    guard let wylder = index.modifiers(for: "wylder").first(where: { $0.affixId == 6_640_000 }),
          let row12 = wylder.level(12) else {
        throw CheckFailure(description: "角色属性：找不到【追踪者】提升集中力但降低生命力 的 12 级行")
    }
    try heroExpect(HeroStatsCopy.deltaSummary(row12.delta, names: names) == "生命力 -5、集中力 +10",
                   "增减量摘要应按属性顺序并带符号", counter: &count)
    try heroExpect(HeroStatsCopy.deltaSummary([:], names: names).isEmpty, "空增减量摘要为空串", counter: &count)
    try heroExpect(HeroStatsCopy.deltaSummary(["vigor": 0, "mind": 3], names: names) == "集中力 +3",
                   "增减量摘要应跳过 0 项", counter: &count)

    // 遗留列当前只有负重上限，且页面靠 inGameLabel 判定（不写死 key）
    let legacy = names.derivedKeys.filter { names.derivedEntry($0)?.inGameLabel == false }
    try heroExpect(legacy == ["equipLoad"], "遗留列当前只有负重上限，实际 \(legacy)", counter: &count)

    // 与外部 wiki 的逐格对照：只有真有差异的角色才返回
    try heroExpect(index.crossCheck(for: "duchess")?.mismatchCount == 14, "女爵应有 14 格差异", counter: &count)
    try heroExpect(index.crossCheck(for: "duchess")?.authoritative == "params", "差异以参数为准", counter: &count)
    try heroExpect(index.crossCheck(for: "wylder") == nil, "追踪者 0 差异，不必提示", counter: &count)
    try heroExpect(index.crossCheck(for: "executor") == nil, "执行者 0 差异，不必提示", counter: &count)
    try heroExpect(index.crossCheck(for: "不存在") == nil, "未知角色没有对照结果", counter: &count)

    // 全部等级表的钳位汇总按行聚合：与逐行的 clampedStats 对得上
    let snapshots = index.snapshots(heroKey: "ironeye", modifierIDs: [6_642_000], libraKey: "strength")
    try heroExpect(snapshots.count == 15, "全部等级表应有 15 行", counter: &count)
    let clampedRows = index.clampedByLevel(snapshots)
    try heroExpect(clampedRows.count > 1, "这一组合应有多级触发钳位（否则「按行聚合」没意义）", counter: &count)
    let expectedRows = snapshots.filter { !$0.clampedStats.isEmpty }
    try heroExpect(clampedRows.map(\.level) == expectedRows.map(\.level), "聚合结果应覆盖所有被钳的行", counter: &count)
    for (aggregated, snapshot) in zip(clampedRows, expectedRows) {
        try heroExpect(aggregated.names == snapshot.clampedStats.map { names.attributeTitle($0) },
                       "\(snapshot.level) 级的聚合属性名应与该行的 clampedStats 一致", counter: &count)
    }
    let summary = HeroStatsCopy.clampSummaryByLevel(clampedRows, maxLevel: index.maxLevel)
    try heroExpect(summary.hasPrefix("1–15 级里有 \(clampedRows.count) 级叠加后不足 1："),
                   "钳位汇总应写清有几级被钳，实际 \(summary)", counter: &count)
    for entry in clampedRows {
        try heroExpect(summary.contains("\(entry.level) 级 " + entry.names.joined(separator: "、")),
                       "钳位汇总应逐行列出 \(entry.level) 级", counter: &count)
    }
    try heroExpect(index.clampedByLevel(index.snapshots(heroKey: "ironeye")).isEmpty,
                   "不勾词条时没有任何钳位", counter: &count)

    return count
}

// MARK: - ⑫ 本轮补的双端对称断言

/// 上一轮两端「各写各的」而任何一端的用例都抓不到的几处，逐条补上对称断言。
/// Windows 端 `tests/heroes.test.mjs` 末尾有同名同结构的一组用例。
private func checkHeroCrossEndParity(_ index: HeroStatsIndex) throws -> Int {
    var count = 0
    let dataset = index.dataset
    let names = index.statNames

    // ① 折叠区「插值与验证口径（N 条）」：两端渲染同一组 10 条说明
    let notes = dataset.interpolation.notes
    try heroExpect(notes.count == 10, "真实数据集应拼出 10 条插值说明，实际 \(notes.count)", counter: &count)
    try heroExpect(notes.map(\.title) == HeroStatsCopy.interpolationNoteTitles,
                   "10 条说明的标题与顺序应与共用文案一致，实际 \(notes.map(\.title))", counter: &count)
    try heroExpect(
        notes[0].text == "基础属性表只有 1 / 2 / 12 / 15 级是参数原值，转职遗物只有 1 / 12 级是参数原值。",
        "锚点一条应由数据集的两组锚点拼出，实际 \(notes[0].text)", counter: &count
    )
    try heroExpect(
        HeroStatsCopy.interpolationAnchorNote(baseAnchorLevels: [1, 8], modifierAnchorLevels: [1, 6])
            == "基础属性表只有 1 / 8 级是参数原值，转职遗物只有 1 / 6 级是参数原值。",
        "锚点文案里的等级应跟着数据集走", counter: &count
    )
    try heroExpect(notes[1].text == dataset.interpolation.baseRule, "正文应直接取数据集那一段", counter: &count)
    try heroExpect(notes[2].text == dataset.interpolation.baseVerification, "基础表验证正文", counter: &count)
    try heroExpect(notes[9].text == dataset.interpolation.libraRule, "利普拉一条的正文", counter: &count)
    try heroExpect(notes[7].text.hasPrefix("基础属性表按向下取整（floor）"), "取整方向应写出 floor", counter: &count)
    try heroExpect(notes[7].text.contains("转职遗物增减量按向零取整（trunc）"), "取整方向应写出 trunc", counter: &count)
    try heroExpect(notes[7].text.contains("两种取整只在负的增减量上差 1；"), "取整方向应点明两者的差别", counter: &count)
    try heroExpect(HeroStatsCopy.roundingTerm("floor") == "向下取整（floor）", "取整术语①", counter: &count)
    try heroExpect(HeroStatsCopy.roundingTerm("round") == "四舍五入（round）", "取整术语②", counter: &count)
    try heroExpect(HeroStatsCopy.roundingTerm("别的") == "别的", "未知取整名原样回显", counter: &count)
    try heroExpect(HeroStatsCopy.interpolationRoundingNote(base: "", modifier: "").isEmpty,
                   "两个取整字段都缺时整条说明不出现", counter: &count)
    try heroExpect(HeroInterpolation(baseRule: "x").notes.map(\.title) == ["基础属性插值"],
                   "只有一个字段时只出一条说明", counter: &count)

    // ② 最大等级一律读数据集：maxLevel = 20 时等级范围 / 表体行数 / 汇总一起变。
    //    用构造出来的 JSON 走一遍真实解码路径（页面拿到的也是这条路径的产物）。
    func levelsJSON(_ top: Int) -> String {
        (1...top).map { level -> String in
            let anchor = (level == 1 || level == top) ? "true" : "false"
            return "{\"level\": \(level), \"isAnchor\": \(anchor), \"stats\": {\"vigor\": \(level + 5)}}"
        }.joined(separator: ",")
    }
    func datasetJSON(levels: Int, declaredMaxLevel: Int?) -> String {
        let declared: String = declaredMaxLevel.map { ", \"maxLevel\": \($0)" } ?? ""
        let names = "\"statNames\": {\"attributeOrder\": [\"vigor\"], \"derivedOrder\": [], \"derived\": [],"
            + " \"attributes\": [{\"key\": \"vigor\", \"zh\": \"生命力\", \"en\": \"Vigor\"}]}"
        let interpolation = "\"interpolation\": {\"baseAnchorLevels\": [1, 2]" + declared + "}"
        let heroes = "\"heroes\": [{\"id\": 1, \"key\": \"wylder\", \"nameZh\": \"追踪者\", \"nameEn\": \"Wylder\","
            + " \"levels\": [" + levelsJSON(levels) + "]}]"
        return "{\"schemaVersion\": 1, " + names + ", " + interpolation + ", " + heroes + "}"
    }
    let big = try HeroStatsIndex(data: Data(datasetJSON(levels: 20, declaredMaxLevel: 20).utf8))
    try heroExpect(big.maxLevel == 20, "声明 maxLevel = 20 时最大等级应为 20，实际 \(big.maxLevel)", counter: &count)
    try heroExpect(big.levelRange == Array(1...20), "等级选择器的范围应是 1–20，实际 \(big.levelRange.count) 项",
                   counter: &count)
    try heroExpect(big.snapshots(heroKey: "wylder").count == 20, "全部等级表应有 20 行", counter: &count)
    try heroExpect(big.snapshot(heroKey: "wylder", level: 20)?.baseStats["vigor"] == 25,
                   "20 级应算得出快照", counter: &count)
    try heroExpect(big.summary.contains("1–20 级"), "页面摘要应写 1–20 级，实际 \(big.summary)", counter: &count)
    try heroExpect(
        HeroStatsCopy.clampSummaryByLevel([(20, ["灵巧"])], maxLevel: big.maxLevel)
            == "1–20 级里有 1 级叠加后不足 1：20 级 灵巧；已钳到最低 1（游戏里属性不会低于 1）",
        "钳位汇总里的范围同样是 1–20", counter: &count
    )
    try heroExpect(
        HeroStatsCopy.contentSummary(heroes: 1, maxLevel: big.maxLevel, modifiers: 0, libra: 0)
            == "1 位夜行者 × 20 级 · 0 条转职遗物词条 · 0 笔利普拉交易",
        "版本块的「收录」同样是 20 级", counter: &count
    )
    // 没声明 maxLevel 时退回各角色 levels 的最大等级（Windows 端 maxLevelOf 同一条兜底）
    let undeclared = try HeroStatsIndex(data: Data(datasetJSON(levels: 20, declaredMaxLevel: nil).utf8))
    try heroExpect(undeclared.dataset.interpolation.maxLevel == 0, "没声明时不该假装声明了 15", counter: &count)
    try heroExpect(undeclared.maxLevel == 20, "没声明 maxLevel 时应退回角色表的最大等级，实际 \(undeclared.maxLevel)",
                   counter: &count)
    try heroExpect(undeclared.levelRange.count == 20, "等级范围同样跟着角色表走", counter: &count)
    // 声明值与角色表不一致时以声明为准（数据集自己说了算）
    let declaredShort = try HeroStatsIndex(data: Data(datasetJSON(levels: 20, declaredMaxLevel: 12).utf8))
    try heroExpect(declaredShort.maxLevel == 12, "声明 12 级时以声明为准，实际 \(declaredShort.maxLevel)", counter: &count)
    try heroExpect(declaredShort.snapshots(heroKey: "wylder").count == 12, "表体同样只到 12 行", counter: &count)
    try heroExpect(index.maxLevel == 15, "真实数据集仍是 15 级", counter: &count)

    // ③ 词条来源三档三色：来源 → 配色名两端钉同一张表
    try heroExpect(HeroModifierSource.anchor.colorToken == "green", "锚点应为绿", counter: &count)
    try heroExpect(HeroModifierSource.inferred.colorToken == "amber", "推算应为琥珀", counter: &count)
    try heroExpect(HeroModifierSource.carried.colorToken == "blue", "沿用应为蓝", counter: &count)
    try heroExpect(HeroModifierSource.carried.colorToken != HeroModifierSource.anchor.colorToken,
                   "「沿用锚点」与「锚点」不能同色，否则页面上只有文字能区分", counter: &count)
    try heroExpect(HeroModifierSource.carried.symbolName != HeroModifierSource.anchor.symbolName,
                   "「沿用锚点」与「锚点」也不该是同一个图标", counter: &count)
    let anchors = dataset.interpolation.modifierAnchorLevels
    for (level, token) in [(1, "green"), (6, "amber"), (15, "blue")] {
        try heroExpect(HeroStatsText.modifierSource(level: level, anchorLevels: anchors)?.source.colorToken == token,
                       "\(level) 级的来源配色应是 \(token)", counter: &count)
    }

    // ④ 属性缺失给破折号，且不编一个最终值出来
    let holed = HeroLevelRow(
        level: 1, isAnchor: true,
        stats: names.attributeKeys.filter { $0 != "arcane" }.reduce(into: [:]) { $0[$1] = 10 },
        derived: [:]
    )
    let applied = HeroStatsMath.apply(
        deltas: [["arcane": -20, "vigor": -20]], to: holed.stats, order: names.attributeKeys
    )
    try heroExpect(applied.stats["arcane"] == nil, "基础表没有的属性不该被编出一个最终值", counter: &count)
    try heroExpect(!applied.clamped.contains("arcane"), "缺项不记钳位", counter: &count)
    try heroExpect(applied.clampedFrom["arcane"] == nil, "缺项没有钳位前原值", counter: &count)
    try heroExpect(applied.stats["vigor"] == HeroStatsMath.minimumStat, "有基础值的那一项照常钳位", counter: &count)
    try heroExpect(HeroStatsText.statText(applied.stats["arcane"]) == HeroStatsCopy.missing,
                   "缺属性的格子应显示破折号", counter: &count)
    try heroExpect(HeroStatsText.statText(0) == "0", "0 是真实数值，照常显示", counter: &count)

    // ⑤ growthGraph 的「可用性」：三个数组必须等长（Windows 端 isUsableGraph 同一条）
    let shortAdj = HeroGrowthGraph(id: 9001, name: "adjPt 残缺", stageMaxVal: [1, 10],
                                   stageMaxGrowVal: [0, 90], adjPt: [1], linear: true, usedFor: [])
    try heroExpect(!shortAdj.isUsable, "adjPt 比端点少一项就算不可用", counter: &count)
    try heroExpect(shortAdj.value(at: 5) == 0 && shortAdj.integerValue(at: 5) == 0,
                   "不可用图表一律返回 0，由调用方跳过（页面破折号）", counter: &count)
    let longY = HeroGrowthGraph(id: 9002, name: "ys 偏长", stageMaxVal: [1, 10],
                                stageMaxGrowVal: [0, 90, 100], adjPt: [1, 1], linear: true, usedFor: [])
    try heroExpect(!longY.isUsable, "ys 比 xs 长同样不可用", counter: &count)
    try heroExpect(
        HeroStatsMath.derivedValues(for: ["vigor": 20], names: names, graphs: [100: shortAdj])["hp"] == nil,
        "图表不可用时不该算出派生值（页面给破折号）", counter: &count
    )

    return count
}

// MARK: - ⑬ 整数求值的逐格兜底

/// `integerValue` 的两条路径都要跑到：端点全为整数且 adjPt == 1 时走精确整数除法，
/// 其余情况退回 `normalize + floor`。Windows 端 tests/heroes.test.mjs 有 1..99 的逐格
/// 对照，这里补上同构的一份，并用构造出来的图表把兜底分支真跑一遍
/// （真实数据集的 100 / 101 / 104 三行端点全是整数，这条分支一行都执行不到）。
private func checkHeroIntegerValuePaths(_ index: HeroStatsIndex) throws -> Int {
    var count = 0

    guard let hp = index.dataset.growthGraphs[100],
          let fp = index.dataset.growthGraphs[101],
          let stamina = index.dataset.growthGraphs[104] else {
        throw CheckFailure(description: "角色属性：缺少 CalcCorrectGraph 100/101/104")
    }
    for graph in [hp, fp, stamina] {
        for stat in 1...99 {
            let expected = Int(HeroStatsMath.normalize(graph.value(at: stat)).rounded(.down))
            try heroExpect(
                graph.integerValue(at: stat) == expected,
                "CalcCorrectGraph \(graph.id) 在 \(stat) 上的整数求值应与 normalize + floor 一致"
                    + "（期望 \(expected)，实际 \(graph.integerValue(at: stat))）",
                counter: &count
            )
        }
    }

    // 端点非整数：走不了整数除法，只能退回 normalize + floor
    let fractional = HeroGrowthGraph(
        id: 9101, name: "端点非整数", stageMaxVal: [1, 10], stageMaxGrowVal: [0.5, 100.25],
        adjPt: [1, 1], linear: true, usedFor: []
    )
    try heroExpect(fractional.isUsable, "构造的图表应可用", counter: &count)
    for stat in 1...12 {
        let expected = Int(HeroStatsMath.normalize(fractional.value(at: stat)).rounded(.down))
        try heroExpect(fractional.integerValue(at: stat) == expected,
                       "端点非整数时 \(stat) 应退回 normalize + floor（期望 \(expected)，"
                           + "实际 \(fractional.integerValue(at: stat))）", counter: &count)
    }
    // 手算一格：0.5 + (100.25 − 0.5) × (5 − 1) / 9 = 44.8333… → 44
    try heroExpect(fractional.integerValue(at: 5) == 44, "端点非整数的 5 应取到 44，实际 \(fractional.integerValue(at: 5))",
                   counter: &count)

    // 带指数的一段：同样走兜底，且 normalize 把 1e-9 以下的尾巴抹掉后才 floor。
    // 端点取成「真值恰好是整数、浮点上差一丁点」的一组：ratio^2 在 x = 5 上是 0.25，
    // y = 0 + 240 × 0.25 = 60，没有 normalize 的话浮点可能给 59.999999999。
    let curved = HeroGrowthGraph(
        id: 9102, name: "带指数", stageMaxVal: [1, 9], stageMaxGrowVal: [0, 240],
        adjPt: [2, 2], linear: false, usedFor: []
    )
    try heroExpect(curved.integerValue(at: 5) == 60, "带指数的一段应取到 60，实际 \(curved.integerValue(at: 5))",
                   counter: &count)
    for stat in 1...9 {
        let expected = Int(HeroStatsMath.normalize(curved.value(at: stat)).rounded(.down))
        try heroExpect(curved.integerValue(at: stat) == expected,
                       "带指数时 \(stat) 应退回 normalize + floor", counter: &count)
    }
    try heroExpect(HeroStatsMath.normalize(59.9999999999).rounded(.down) == 60,
                   "normalize 应把 1e-9 以下的尾巴抹掉再取整（否则 59.9999999999 会被取成 59）", counter: &count)
    try heroExpect(HeroStatsMath.normalize(59.99).rounded(.down) == 59,
                   "normalize 不该把真实的 0.01 差距也抹掉", counter: &count)

    return count
}
