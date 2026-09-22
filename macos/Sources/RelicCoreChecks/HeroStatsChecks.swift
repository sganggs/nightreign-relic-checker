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
//      「已钳到下限 1」注记因此是用户真看得到的东西，不是防御性代码。

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

                // 最终值必须逐格等于 max(1, 基础 + 请求增减量)，clampedStats 与之一致
                var expectedStats = snapshot.baseStats
                var expectedClamped: [String] = []
                for (key, change) in snapshot.requestedDelta {
                    let raw = (snapshot.baseStats[key] ?? 0) + change
                    expectedStats[key] = max(HeroStatsMath.minimumStat, raw)
                    if raw < HeroStatsMath.minimumStat { expectedClamped.append(key) }
                }
                expectedClamped.sort()

                if snapshot.finalStats != expectedStats {
                    scan.note("\(place) 最终属性应为 max(1, 基础 + 增减量) = \(expectedStats)，实际 \(snapshot.finalStats)")
                }
                if snapshot.clampedStats != expectedClamped {
                    scan.note("\(place) 钳位列表应为 \(expectedClamped)，实际 \(snapshot.clampedStats)")
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
    //    说明要重新核一遍页面上「已钳到下限 1」那批数字（这是用户真看得到的一批）。
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
    try heroExpect(HeroStatsText.inferenceTag(level: 1, anchorLevels: anchors) == nil, "1 级是锚点，不标记", counter: &count)
    try heroExpect(HeroStatsText.inferenceTag(level: 12, anchorLevels: anchors) == nil, "12 级是锚点，不标记", counter: &count)
    try heroExpect(HeroStatsText.inferenceTag(level: 6, anchorLevels: anchors) == "推算", "2–11 级应标「推算」", counter: &count)
    try heroExpect(HeroStatsText.inferenceTag(level: 15, anchorLevels: anchors) == "沿用 12 级锚点",
                   "13–15 级应标「沿用 12 级锚点」", counter: &count)
    try heroExpect(HeroStatsText.inferenceTag(level: 3, anchorLevels: []) == nil, "没有锚点信息时不标记", counter: &count)

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
    try heroExpect(decoded.dataset.interpolation.maxLevel == 15, "缺失的 interpolation 应退回默认值", counter: &count)
    try heroExpect(decoded.dataset.interpolation.notes.isEmpty, "缺失的 interpolation 不应生成说明条目", counter: &count)
    try heroExpect(decoded.maxLevel == 15, "缺失 interpolation 时最大等级应退回 15", counter: &count)

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
