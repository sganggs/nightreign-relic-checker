import Foundation
import RelicCore

// 「首领数据」页的自检：用真实的 Resources/bosses.json 跑解码、换算与分组，
// 另外用几份构造出来的 JSON 验证「宽容解码」（未知字段忽略、缺字段退默认值、
// 坏元素跳过）。注册入口见 GameDataChecks.swift。

/// 内置资源目录下的 bosses.json（以源码路径定位，不依赖应用目标是否已构建）。
private var bossesResourceURL: URL {
    URL(fileURLWithPath: #filePath)          // …/Sources/RelicCoreChecks/BossDataChecks.swift
        .deletingLastPathComponent()         // …/Sources/RelicCoreChecks
        .deletingLastPathComponent()         // …/Sources
        .deletingLastPathComponent()         // …/macos
        .appendingPathComponent("Sources/NightreignRelicChecker/Resources/bosses.json")
}

/// 夜王 fight + 守夜 / 野外 variant 的全部数值行。
private func bossAllRows(_ dataset: BossDataset) -> [BossFight] {
    dataset.nightlords.flatMap(\.fights) + dataset.nightBosses.flatMap(\.variants)
}

private func bossExpect(_ condition: Bool, _ message: String, counter: inout Int) throws {
    guard condition else { throw CheckFailure(description: "首领数据：" + message) }
    counter += 1
}

private func bossExpectClose(
    _ value: Double?, _ expected: Double, _ message: String, tolerance: Double = 0.01, counter: inout Int
) throws {
    guard let value, abs(value - expected) <= tolerance else {
        let shown = value.map { String(format: "%.4f", $0) } ?? "nil"
        throw CheckFailure(description: "首领数据：\(message)（期望 \(expected)，实际 \(shown)）")
    }
    counter += 1
}

func checkBossData() throws -> Int {
    var count = 0

    // 1. 真实文件能解码
    let url = bossesResourceURL
    guard FileManager.default.fileExists(atPath: url.path) else {
        throw CheckFailure(description: "首领数据：缺少 \(url.path)")
    }
    let data = try Data(contentsOf: url)
    if GameDataLoader.isPlaceholder(data) {
        print("    （bosses.json 仍是占位内容，跳过首领数据字段检查）")
        return 0
    }

    let index = try BossDataIndex(data: data)
    let dataset = index.dataset
    try bossExpect(dataset.schemaVersion >= 2, "bossesSchemaVersion 应 ≥ 2，实际 \(dataset.schemaVersion)", counter: &count)
    try bossExpect(!dataset.gameVersion.isEmpty && !dataset.dataVersion.isEmpty, "缺少 gameVersion / dataVersion", counter: &count)
    try bossExpect(!dataset.caveats.isEmpty, "caveats 不应为空（页面底部要展示）", counter: &count)
    try bossExpect(!dataset.sources.isEmpty, "sources 不应为空", counter: &count)

    // 2. 夜王 ≥ 10、每位夜王至少一条 fight
    try bossExpect(dataset.nightlords.count >= 10, "夜王应 ≥ 10 条，实际 \(dataset.nightlords.count)", counter: &count)
    try bossExpect(dataset.nightlords.allSatisfy { !$0.fights.isEmpty }, "每位夜王都应至少有一条 fight", counter: &count)
    try bossExpect(
        dataset.nightlords.contains { $0.isEverdark },
        "应存在永夜之王形态（variantKey = everdark）",
        counter: &count
    )

    // 3. 格拉狄乌斯主战行的血量与承伤倍率
    guard let gladius = dataset.nightlords.first(where: { $0.nameZh == "格拉狄乌斯" && !$0.isEverdark }) else {
        throw CheckFailure(description: "首领数据：找不到夜王「格拉狄乌斯」")
    }
    guard let main = gladius.fights.first(where: { $0.isMain }) else {
        throw CheckFailure(description: "首领数据：格拉狄乌斯没有主战（isMain）行")
    }
    try bossExpect(main.hp == 11328, "格拉狄乌斯主战 1 人血量应为 11328，实际 \(main.hp)", counter: &count)
    try bossExpect(main.hpBase == 3200, "格拉狄乌斯主战 hpBase 应为 3200，实际 \(main.hpBase)", counter: &count)
    try bossExpectClose(main.hpMultiplier, 3.54, "格拉狄乌斯常驻血量倍率应为 3.54", counter: &count)
    try bossExpectClose(main.damageRates.holy, 1.35, "格拉狄乌斯圣属性倍率应为 1.35", counter: &count)
    try bossExpectClose(main.damageRates.fire, 0.5, "格拉狄乌斯火属性倍率应为 0.5", counter: &count)
    try bossExpect(main.damageRates.weakKinds.contains(.holy), "圣应被判为数值弱点（倍率 > 1）", counter: &count)
    try bossExpect(main.damageRates.resistantKinds.contains(.fire), "火应被判为抗性（倍率 < 1）", counter: &count)
    try bossExpect(
        gladius.weakness.contains { $0.zh == "圣" },
        "格拉狄乌斯的官方弱点标注应包含「圣」",
        counter: &count
    )

    // 4. 多人血量换算 = hp × 档位倍率
    try bossExpect(main.hp(for: .solo) == 11328, "单人血量换算应等于 hp", counter: &count)
    try bossExpect(main.hp(for: .duo) == 22656, "双人血量应为 11328 × 2，实际 \(main.hp(for: .duo))", counter: &count)
    try bossExpect(main.hp(for: .trio) == 33984, "三人血量应为 11328 × 3，实际 \(main.hp(for: .trio))", counter: &count)
    try bossExpectClose(main.tier(for: .duo).hp, 2, "最终 Boss 档双人血量倍率应为 2", counter: &count)
    try bossExpectClose(main.tier(for: .trio).poiseTaken, 0.3, "最终 Boss 档三人承受削韧应为 0.3", counter: &count)
    try bossExpectClose(main.tier(for: .duo).buildupRate, 0.85, "最终 Boss 档双人异常累积倍率应为 0.85", counter: &count)

    // 5. 有效韧性 = poise /（poiseTakenBase × 承受削韧倍率）
    try bossExpectClose(main.effectivePoise(for: .solo), 120, "单人有效韧性应为 120", counter: &count)
    try bossExpectClose(main.effectivePoise(for: .duo), 120 / 0.55, "双人有效韧性应为 120 / 0.55", tolerance: 0.05, counter: &count)
    try bossExpectClose(main.effectivePoise(for: .trio), 400, "三人有效韧性应为 120 / 0.3", tolerance: 0.05, counter: &count)
    // 削韧恢复 / 异常倍率一律用硬编码期望值（0.29 × 0.2 × 档位倍率、0.5 × 档位倍率），
    // 不拿实现和它自己比，公式被改坏时要能红。
    try bossExpectClose(
        main.poiseRecoverSpeed(for: .solo), 0.058,
        "单人削韧恢复应为 0.29 × 0.2", tolerance: 0.0001, counter: &count
    )
    try bossExpectClose(
        main.poiseRecoverSpeed(for: .duo), 0.0319,
        "双人削韧恢复应为 0.29 × 0.2 × 0.55", tolerance: 0.0001, counter: &count
    )
    try bossExpectClose(
        main.poiseRecoverSpeed(for: .trio), 0.0174,
        "三人削韧恢复应为 0.29 × 0.2 × 0.3", tolerance: 0.0001, counter: &count
    )
    try bossExpectClose(main.ailmentDamageRate(for: .solo), 0.5, "单人异常发动伤害应为 0.5", tolerance: 0.0001, counter: &count)
    try bossExpectClose(main.ailmentDamageRate(for: .duo), 0.375, "双人异常发动伤害应为 0.5 × 0.75", tolerance: 0.0001, counter: &count)
    try bossExpectClose(main.ailmentDamageRate(for: .trio), 0.25, "三人异常发动伤害应为 0.5 × 0.5", tolerance: 0.0001, counter: &count)
    try bossExpectClose(main.ailmentBuildupRate(for: .trio), 0.7, "最终 Boss 档三人异常累积倍率应为 0.7", counter: &count)

    // 6. 一次性算齐的 stats 同样对期望常数，而不是对自己
    let stats = main.stats(for: .duo)
    try bossExpect(stats.hp == 22656, "stats 双人血量应为 22656，实际 \(stats.hp)", counter: &count)
    try bossExpectClose(stats.effectivePoise, 218.1818, "stats 双人有效韧性应为 120 / 0.55", tolerance: 0.01, counter: &count)
    try bossExpectClose(stats.poiseRecover, 0.0319, "stats 双人削韧恢复应为 0.0319", tolerance: 0.0001, counter: &count)
    try bossExpectClose(stats.ailmentDamageRate, 0.375, "stats 双人异常发动伤害应为 0.375", tolerance: 0.0001, counter: &count)
    try bossExpectClose(stats.ailmentBuildupRate, 0.85, "stats 双人异常累积倍率应为 0.85", tolerance: 0.0001, counter: &count)
    try bossExpectClose(stats.poisonDamageRate, 1, "stats 中毒 / 腐败发动倍率当前应为 1", tolerance: 0.0001, counter: &count)

    // 7. 异常抗性：999 视为免疫
    try bossExpect(main.resist.isImmune(to: .madness), "格拉狄乌斯应免疫发狂（999）", counter: &count)
    try bossExpect(main.resist.isImmune(to: .death), "格拉狄乌斯应免疫死亡（999）", counter: &count)
    try bossExpect(!main.resist.isImmune(to: .bleed), "格拉狄乌斯不应被判为免疫出血", counter: &count)
    try bossExpect(Set(main.immuneKinds()) == Set([.madness, .death]), "免疫列表应为发狂 + 死亡", counter: &count)

    // 8. 守夜 / 野外首领：主键唯一、分组正确、变体非空
    try bossExpect(dataset.nightBosses.count >= 50, "守夜 / 野外首领应 ≥ 50 组，实际 \(dataset.nightBosses.count)", counter: &count)
    try bossExpect(
        Set(dataset.nightBosses.map(\.id)).count == dataset.nightBosses.count,
        "nightBosses 的 id 应唯一",
        counter: &count
    )
    try bossExpect(
        dataset.nightBosses.allSatisfy { $0.tier == "night" || $0.tier == "field" },
        "nightBosses 的 tier 只应是 night / field",
        counter: &count
    )
    try bossExpect(dataset.nightBosses.allSatisfy { !$0.variants.isEmpty }, "每组守夜 / 野外首领都应至少有一个变体", counter: &count)

    // 9. 分组与搜索折叠
    let lords = index.cards(in: .nightlord)
    let night = index.cards(in: .night)
    let field = index.cards(in: .field)
    try bossExpect(lords.count == dataset.nightlords.count, "夜王卡片数应等于 nightlords 条数", counter: &count)
    // tiers 同时含 field 与 night 的组会同时出现在两个分组里，因此是「之和 - 重复数」
    let dual = index.dualTierCards
    try bossExpect(
        night.count + field.count - dual.count == dataset.nightBosses.count,
        "守夜 + 野外卡片数（去掉两种档位都有的重复）应等于 nightBosses 条数",
        counter: &count
    )
    try bossExpect(!night.isEmpty && !field.isEmpty, "守夜与野外分组都不应为空", counter: &count)
    try bossExpect(
        index.cards(in: .nightlord, query: "格拉").contains { $0.nameZh == "格拉狄乌斯" },
        "搜索「格拉」应命中格拉狄乌斯",
        counter: &count
    )
    try bossExpect(
        index.cards(in: .nightlord, query: " Gladius ").contains { $0.nameEn == "Gladius" },
        "搜索折叠应忽略空格与大小写",
        counter: &count
    )
    try bossExpect(index.cards(in: .nightlord, query: "不存在的首领名").isEmpty, "无匹配时应返回空列表", counter: &count)
    try bossExpect(lords.allSatisfy { $0.primaryRow != nil }, "每张夜王卡片都应能确定主战行", counter: &count)

    // 9b. isMain 不唯一：头条行必须是主战行里血量最高的那条，且能并列展示全部主战行
    let multiMain = lords.filter(\.hasMultipleMainRows)
    try bossExpect(
        multiMain.count == 5,
        "当前数据里应有 5 张夜王卡片带多条 isMain 行，实际 \(multiMain.count)",
        counter: &count
    )
    try bossExpect(
        lords.allSatisfy { card in
            guard let primary = card.primaryRow, !card.mainRows.isEmpty else { return true }
            return primary.hp == card.mainRows.map(\.hp).max()
        },
        "夜王头条行应是主战行里血量最高的一条",
        counter: &count
    )
    guard let maris = lords.first(where: { $0.nameZh == "玛利斯" && $0.variantNameZh == "永夜之王" }) else {
        throw CheckFailure(description: "首领数据：找不到夜王卡片「玛利斯 · 永夜之王」")
    }
    try bossExpect(maris.mainRows.count == 2, "玛利斯 · 永夜之王应有 2 条主战行，实际 \(maris.mainRows.count)", counter: &count)
    try bossExpect(
        maris.primaryRow?.hp == 29453,
        "玛利斯 · 永夜之王头条血量应取二阶段 29453（而不是一阶段 3172），实际 \(maris.primaryRow.map { String($0.hp) } ?? "nil")",
        counter: &count
    )
    try bossExpect(
        maris.primaryRow?.npcId == 75410000,
        "玛利斯 · 永夜之王头条行应是 npcId 75410000",
        counter: &count
    )
    guard let gnoster = lords.first(where: { $0.nameZh == "格诺斯塔" && $0.variantNameZh == "永夜之王" }) else {
        throw CheckFailure(description: "首领数据：找不到夜王卡片「格诺斯塔 · 永夜之王」")
    }
    try bossExpect(gnoster.mainRows.count == 5, "格诺斯塔 · 永夜之王应有 5 条主战行", counter: &count)
    try bossExpect(
        gnoster.primaryRow?.hp == 8564,
        "格诺斯塔 · 永夜之王头条血量应取最高的 8564，实际 \(gnoster.primaryRow.map { String($0.hp) } ?? "nil")",
        counter: &count
    )

    // 9c. tiers 多值：同时有守夜与野外变体的组，在两个分组筛选下都应能被检索到
    try bossExpect(dual.count == 6, "当前数据里应有 6 组同时含守夜与野外变体，实际 \(dual.count)", counter: &count)
    try bossExpect(
        dual.allSatisfy { card in
            card.rows.contains { $0.threat == "night" } && card.rows.contains { $0.threat == "field" }
        },
        "这些组的变体里应同时存在 threat = night 与 field 的行",
        counter: &count
    )
    try bossExpect(
        dual.allSatisfy { $0.rows.allSatisfy { $0.threatTitle != nil } },
        "守夜 / 野外的每一行都应能渲染威胁档位标记",
        counter: &count
    )
    guard let apostle = dual.first(where: { $0.nameZh == "神皮使徒" }) else {
        throw CheckFailure(description: "首领数据：神皮使徒应是同时含守夜与野外变体的组")
    }
    try bossExpect(
        index.cards(in: .field, query: "神皮使徒").contains { $0.id == apostle.id },
        "「野外首领」筛选下应能搜到神皮使徒（它的 tier 是 night，但有 4 条野外变体）",
        counter: &count
    )
    try bossExpect(
        index.cards(in: .night, query: "神皮使徒").contains { $0.id == apostle.id },
        "「守夜首领」筛选下同样应能搜到神皮使徒",
        counter: &count
    )
    try bossExpect(
        apostle.rows.filter { $0.threat == "field" }.count == 4,
        "神皮使徒应有 4 条野外变体",
        counter: &count
    )

    // 9d. 搜索串：不混分组名、收录被合并掉的 npcId、纯数字走前缀匹配
    try bossExpect(
        index.cards(in: .field, query: "野外").count < field.count,
        "搜索「野外」不应命中全部野外卡片（分组名不进搜索串）",
        counter: &count
    )
    guard let gladiusCard = lords.first(where: { $0.nameZh == "格拉狄乌斯" && $0.variantNameZh.isEmpty }) else {
        throw CheckFailure(description: "首领数据：找不到夜王卡片「格拉狄乌斯」")
    }
    try bossExpect(
        !gladiusCard.searchKey.contains(bossFoldForSearch("夜王")),
        "分组名「夜王」不应出现在搜索串里",
        counter: &count
    )
    try bossExpect(
        main.npcIds.count > 1,
        "格拉狄乌斯主战行应是合并行（npcIds 不止一条）",
        counter: &count
    )
    try bossExpect(
        index.cards(in: .nightlord, query: "75001020").contains { $0.nameZh == "格拉狄乌斯" },
        "按被合并掉的 npcId 75001020 应能搜到格拉狄乌斯",
        counter: &count
    )
    try bossExpect(
        index.cards(in: .nightlord, query: "75000020").contains { $0.nameZh == "格拉狄乌斯" },
        "按代表行 npcId 也应能搜到",
        counter: &count
    )
    try bossExpect(
        index.cards(in: .nightlord, query: "1").isEmpty,
        "纯数字按行号前缀匹配：「1」不应命中任何夜王（npcId 都以 75/76/46 开头）",
        counter: &count
    )
    try bossExpect(
        index.cards(in: .field, query: String(apostle.chrIds[0])).contains { $0.id == apostle.id },
        "按 chrId 也应能搜到首领",
        counter: &count
    )

    // 9e. 属性名优先取数据集的 affinityNames，不硬编码
    try bossExpect(dataset.title(for: .holy) == "圣", "affinityNames 里的圣属性名应为「圣」", counter: &count)
    try bossExpect(dataset.title(for: .rot) == "猩红腐败", "affinityNames 里的腐败名应为「猩红腐败」", counter: &count)
    try bossExpect(dataset.title(for: .standard) == BossDamageKind.standard.titleZh, "物理属性没有 affinity 码，应退回内置文案", counter: &count)

    // 9f. notes.unmatchedNames 要能取到（页面底部「数据说明」要展示）
    try bossExpect(
        (dataset.notes?.unmatchedNames.count ?? 0) == 2,
        "notes.unmatchedNames 应有 2 条（Putrid Flesh / Giant Skeleton Torso）",
        counter: &count
    )

    // 9g. 守夜 / 野外的代表行必须跟着分组走（Windows 侧遗留问题：恒取 variants[0]）
    //     同一组首领可能两种档位都有，野外分组下就该看野外那几行。
    guard let apostleNight = apostle.representativeRow(in: .night),
          let apostleField = apostle.representativeRow(in: .field)
    else {
        throw CheckFailure(description: "首领数据：神皮使徒在两个分组下都应有代表行")
    }
    try bossExpect(
        apostleNight.npcId == 35600900 && apostleNight.threat == "night",
        "神皮使徒在守夜分组下的代表行应是 npcId 35600900，实际 \(apostleNight.npcId)",
        counter: &count
    )
    try bossExpect(
        apostleField.npcId == 35600020 && apostleField.threat == "field",
        "神皮使徒在野外分组下的代表行应是「封印监牢」npcId 35600020（不是血量更高的守夜行），实际 \(apostleField.npcId)",
        counter: &count
    )
    try bossExpect(
        apostle.rows.first?.npcId == 35600900,
        "变体已按守夜优先 + 血量降序排好，rows[0] 是守夜行——正因如此不能拿它当野外分组的代表行",
        counter: &count
    )
    try bossExpect(
        dual.allSatisfy { card in
            guard let night = card.representativeRow(in: .night),
                  let field = card.representativeRow(in: .field) else { return false }
            return night.threat == "night" && field.threat == "field"
        },
        "6 组双档位首领在各自分组下的代表行都应来自该档位",
        counter: &count
    )
    try bossExpect(
        index.cards.allSatisfy { card in
            card.groups.allSatisfy { card.representativeRow(in: $0) != nil }
        },
        "每张卡片在它所属的每个分组下都应能确定代表行",
        counter: &count
    )
    try bossExpect(
        maris.rows(in: .nightlord).count == 2 && gladiusCard.rows(in: .nightlord).count == 1,
        "夜王分组下的候选行应收敛到 isMain",
        counter: &count
    )

    // 9h. poise = 0 与 poise = -1 语义分开：无削韧槽 ≠ 不吃削韧，两者都不能显示成「有效韧性 0」
    let zeroPoiseRows = bossAllRows(dataset).filter { $0.poise == 0 }
    let negativePoiseRows = bossAllRows(dataset).filter { $0.poise < 0 }
    try bossExpect(zeroPoiseRows.count == 2, "数据里应有 2 条 poise = 0 的行，实际 \(zeroPoiseRows.count)", counter: &count)
    try bossExpect(negativePoiseRows.count == 5, "数据里应有 5 条 poise = -1 的行，实际 \(negativePoiseRows.count)", counter: &count)
    guard let zeroRow = zeroPoiseRows.first(where: { $0.npcId == 79310000 }) else {
        throw CheckFailure(description: "首领数据：找不到 poise = 0 的行 npcId 79310000")
    }
    try bossExpect(zeroRow.poiseKind == .zero, "poise = 0 应判为「无削韧槽」", counter: &count)
    try bossExpect(
        zeroRow.effectivePoise(for: .duo) == nil && zeroRow.stats(for: .duo).effectivePoise == nil,
        "poise = 0 不能算成「有效韧性 0」",
        counter: &count
    )
    try bossExpect(zeroRow.poiseKind.placeholder == "无削韧槽", "poise = 0 的文案应为「无削韧槽」", counter: &count)
    guard let negativeRow = negativePoiseRows.first else {
        throw CheckFailure(description: "首领数据：找不到 poise = -1 的行")
    }
    try bossExpect(negativeRow.poiseKind == .none, "poise = -1 应判为「不吃削韧」", counter: &count)
    try bossExpect(negativeRow.poiseKind.placeholder == "不吃削韧", "poise = -1 的文案应为「不吃削韧」", counter: &count)
    try bossExpect(main.poiseKind == .value, "poise > 0 的行应能算出有效韧性", counter: &count)
    try bossExpect(
        bossAllRows(dataset).allSatisfy { row in
            (row.poiseKind == .value) == (row.effectivePoise(for: .solo) != nil)
        },
        "有效韧性是否为 nil 应与 poiseKind 完全对应",
        counter: &count
    )

    // 9i. 名字缺失回退的四种徽标：仅英文名 / 无游戏内名称 / 名称手工补录 / 名称按 ID 推断
    func cardForBoss(_ id: String) throws -> BossCard {
        guard let card = index.cards.first(where: { $0.id == "boss-" + id }) else {
            throw CheckFailure(description: "首领数据：找不到卡片 \(id)")
        }
        return card
    }
    let englishOnly = try cardForBoss("Putrid Flesh@4171")
    try bossExpect(englishOnly.nameBadge == .englishOnly, "english-only 应挂「仅英文名」徽标", counter: &count)
    try bossExpect(englishOnly.nameBadge?.text == "仅英文名", "徽标文案应为「仅英文名」", counter: &count)
    try bossExpect(englishOnly.displayName == "Putrid Flesh", "没有简中名时显示英文名", counter: &count)
    let chrFallback = try cardForBoss("Unknown Enemy (c4504)@4504")
    try bossExpect(
        chrFallback.nameBadge == .noGameName && chrFallback.nameBadge?.text == "无游戏内名称",
        "chrid-fallback 应挂「无游戏内名称」徽标（它的 nameZh 是生成器兜底的「未知敌人 cXXXX」）",
        counter: &count
    )
    try bossExpect(chrFallback.displayName == "未知敌人 c4504", "chrid-fallback 的显示名应是「未知敌人 c4504」", counter: &count)
    let manualCard = try cardForBoss("Cemetery Shade@3664")
    try bossExpect(
        manualCard.nameSource == "manual" && manualCard.nameInferred,
        "Cemetery Shade 同时是 manual 与 nameInferred，用来验证徽标优先级",
        counter: &count
    )
    try bossExpect(
        manualCard.nameBadge == .manual && manualCard.nameBadge?.text == "名称手工补录",
        "manual 优先于 nameInferred，文案应为「名称手工补录」",
        counter: &count
    )
    let inferredCard = try cardForBoss("Horned Warrior@5250")
    try bossExpect(
        inferredCard.nameBadge == .inferred && inferredCard.nameBadge?.text == "名称按 ID 推断",
        "nameInferred 且非手工补录的组应挂「名称按 ID 推断」",
        counter: &count
    )
    try bossExpect(
        index.cards(in: .nightlord).allSatisfy { $0.nameBadge == nil },
        "夜王的名字来自菜单参数，不应挂名称徽标",
        counter: &count
    )
    try bossExpect(
        index.cards(in: .night).first(where: { $0.nameSource == "npcname" && !$0.nameInferred })?.nameBadge == nil,
        "正常 npcname 的组不挂徽标",
        counter: &count
    )

    // 9j. 深夜覆盖度扫描整张卡，不只看代表行
    try bossExpect(
        gnoster.deepCoverage == .some,
        "格诺斯塔 · 永夜之王 6 条 fights 里 3 条有深夜值，整卡应判为「部分行有深夜数值」",
        counter: &count
    )
    try bossExpect(
        gnoster.deepCoverage.badgeText == "部分行有深夜数值",
        "「部分行有深夜数值」的徽标文案两端一致",
        counter: &count
    )
    // 只看代表行会判错的两张卡：哈尔莫妮亚 · 救世旗手与废弃物蚯蚓脸，
    // 代表行没有深夜值，卡里其余行却有。
    let misjudged = index.cards.filter { card in
        card.deepCoverage != .none && card.representativeRow(in: card.group)?.hasDeepOfNight != true
    }
    try bossExpect(
        Set(misjudged.map(\.id)) == ["nightlord-18", "boss-Dreg Wormface@7660"],
        "靠扫描整卡才判得对的应是哈尔莫妮亚 · 救世旗手与废弃物蚯蚓脸，实际 \(misjudged.map(\.id).sorted())",
        counter: &count
    )
    let deepCards = index.cards.filter { $0.deepCoverage != .none }
    try bossExpect(deepCards.count == 22, "应有 22 张卡片带深夜专属数值，实际 \(deepCards.count)", counter: &count)
    try bossExpect(
        index.cards.filter { $0.deepCoverage == .all }.count == 4,
        "其中 4 张整卡每行都有深夜值",
        counter: &count
    )
    try bossExpect(
        deepCards.contains { $0.group != .nightlord },
        "深夜数值不是夜王独有，守夜 / 野外也有",
        counter: &count
    )
    try bossExpect(
        index.cards.first(where: { $0.deepCoverage == .all })?.deepCoverage.badgeText == "深夜数值",
        "整卡都有深夜值时徽标为「深夜数值」",
        counter: &count
    )

    // 9k. 档位分组中文名与收录统计：与 Windows 端同文案
    try bossExpect(
        BossScalingGroup.title(for: "Final Boss Threat") == "最终首领威胁档"
            && BossScalingGroup.title(for: "Night Boss Threat") == "守夜首领威胁档"
            && BossScalingGroup.title(for: "Field Boss Threat") == "野外首领威胁档"
            && BossScalingGroup.title(for: nil) == "其它档位",
        "档位分组的中文标签应与 Windows 端 GROUP_LABELS 一致",
        counter: &count
    )
    try bossExpect(
        index.scalingGroups.allSatisfy { !$0.title.isEmpty },
        "每个档位都应有可显示的分组名",
        counter: &count
    )
    try bossExpect(
        index.inventorySummary == "夜王 18 · 守夜 51 · 野外 72（含 6 组两边都出现） · 数值行 384",
        "收录统计文案应为「夜王 18 · 守夜 51 · 野外 72（含 6 组两边都出现） · 数值行 384」，实际「\(index.inventorySummary)」",
        counter: &count
    )

    // 9l. 承伤偏高的属性排序：同倍率按 DAMAGE_TYPES 声明顺序兜底，两端结果一致
    try bossExpect(
        main.damageRates.weakKinds.first == .holy,
        "格拉狄乌斯承伤最高的属性应是圣",
        counter: &count
    )
    let tieRates = BossDamageRates(standard: 1.2, slash: 1.2, strike: 1, pierce: 1, magic: 1, fire: 1.2, lightning: 1, holy: 1)
    try bossExpect(
        tieRates.weakKinds == [.standard, .slash, .fire],
        "同倍率时应按标准 / 斩击 / 打击 / 突刺 / 魔力 / 火 / 雷 / 圣 的顺序排",
        counter: &count
    )

    // 10. 常驻缩放 / 缩放档位能按 ID 反查，且 ID 已从 key 回填
    try bossExpect(!dataset.permanentScaling.isEmpty, "permanentScaling 不应为空", counter: &count)
    try bossExpect(!index.scalingGroups.isEmpty, "scalingTiers 不应为空", counter: &count)
    try bossExpect(
        dataset.permanentScaling.allSatisfy { key, value in Int(key) == value.id },
        "permanentScaling 的 id 应回填为 key",
        counter: &count
    )
    try bossExpect(
        index.permanentEffects(main.permScalingIds).count == main.permScalingIds.count,
        "格拉狄乌斯主战行的 permScalingIds 应都能查到明细",
        counter: &count
    )
    if let scalingId = main.scalingId {
        try bossExpect(dataset.scalingGroup(scalingId) != nil, "主战行的 scalingId 应能查到档位", counter: &count)
    }

    // 11. 深夜：有专属缩放的行按深夜血量换算
    let deepRows = dataset.nightlords.flatMap(\.fights).filter(\.hasDeepOfNight)
        + dataset.nightBosses.flatMap(\.variants).filter(\.hasDeepOfNight)
    try bossExpect(!deepRows.isEmpty, "应存在带深夜专属缩放的行", counter: &count)
    if let deepRow = deepRows.first, let deep = deepRow.deepOfNight {
        try bossExpect(
            deepRow.hp(for: .solo, deepOfNight: true) == deep.hp,
            "深夜单人血量应取 deepOfNight.hp",
            counter: &count
        )
        try bossExpect(
            deepRow.hp(for: .solo, deepOfNight: false) == deepRow.hp,
            "非深夜时应取常规血量",
            counter: &count
        )
    }
    try bossExpect(
        main.hp(for: .duo, deepOfNight: true) == main.hp(for: .duo, deepOfNight: main.hasDeepOfNight),
        "没有深夜专属缩放的行，深夜数值应与常规一致",
        counter: &count
    )

    // 11b. 深夜路径下的韧性 / 削韧恢复 / 异常倍率也要有硬编码期望值
    //      （史柴格斯 · 远征首领 76100010：poise 150，常规 poiseTakenBase 0.88，深夜 0.99968）
    guard let stray = dataset.nightlords.first(where: { $0.nameZh == "史柴格斯" && $0.variantKey == "normal" }),
          let strayMain = stray.fights.first(where: { $0.npcId == 76100010 }),
          let strayDeep = strayMain.deepOfNight
    else {
        throw CheckFailure(description: "首领数据：找不到史柴格斯的远征首领行（npcId 76100010）")
    }
    try bossExpect(strayMain.hp == 14443, "史柴格斯远征首领常规血量应为 14443，实际 \(strayMain.hp)", counter: &count)
    try bossExpect(strayDeep.hp == 11555, "史柴格斯远征首领深夜血量应为 11555，实际 \(strayDeep.hp)", counter: &count)
    try bossExpect(
        strayMain.hp(for: .trio, deepOfNight: true) == 34665,
        "深夜三人血量应为 11555 × 3，实际 \(strayMain.hp(for: .trio, deepOfNight: true))",
        counter: &count
    )
    try bossExpectClose(
        strayMain.effectivePoise(for: .trio, deepOfNight: false), 568.1818,
        "常规三人有效韧性应为 150 /（0.88 × 0.3）", tolerance: 0.01, counter: &count
    )
    try bossExpectClose(
        strayMain.effectivePoise(for: .trio, deepOfNight: true), 500.16,
        "深夜三人有效韧性应为 150 /（0.99968 × 0.3）", tolerance: 0.01, counter: &count
    )
    try bossExpectClose(
        strayMain.poiseRecoverSpeed(for: .trio, deepOfNight: true), 0.0174,
        "深夜三人削韧恢复应为 0.29 × 0.2 × 0.3", tolerance: 0.0001, counter: &count
    )
    try bossExpectClose(
        strayMain.ailmentDamageRate(for: .duo, deepOfNight: true), 0.375,
        "深夜双人异常发动伤害应为 0.5 × 0.75", tolerance: 0.0001, counter: &count
    )

    // 12. 全量行：血量非负、单人换算等于 hp、不吃削韧的行有效韧性为 nil
    let allRows = dataset.nightlords.flatMap(\.fights) + dataset.nightBosses.flatMap(\.variants)
    try bossExpect(allRows.count >= 300, "战斗行总数应 ≥ 300，实际 \(allRows.count)", counter: &count)
    try bossExpect(allRows.allSatisfy { $0.hp >= 0 }, "不应出现负血量", counter: &count)
    try bossExpect(allRows.allSatisfy { $0.hp(for: .solo) == $0.hp }, "单人血量换算应恒等于 hp", counter: &count)
    try bossExpect(allRows.allSatisfy { $0.hp(for: .trio) >= $0.hp(for: .solo) }, "三人血量不应低于单人", counter: &count)
    try bossExpect(
        allRows.allSatisfy { $0.poise >= 0 || $0.effectivePoise(for: .duo) == nil },
        "poise = -1（不吃削韧）的行有效韧性应为 nil",
        counter: &count
    )
    try bossExpect(allRows.allSatisfy { !$0.displayLabel.isEmpty }, "每行都应有可显示的标签", counter: &count)

    // 12b. 双端对照表：同一条行、同一组输入（人数 + 深夜开关）下的五个数值。
    //      同一张表也写在 windows/tests/bosses.test.mjs 里，两端都对这些硬编码常数，
    //      任一端的公式或代表行选取被改动都会立刻红。
    struct ParityCase {
        let title: String
        let npcId: Int
        let players: BossPartySize
        let deep: Bool
        let hp: Int
        /// nil = 算不出有效韧性（不吃削韧 / 无削韧槽）。
        let effectivePoise: Double?
        let poiseKind: BossPoiseKind
        let poiseRecover: Double
        let ailmentDamageRate: Double
        let buildupRate: Double
    }
    let parityCases: [ParityCase] = [
        .init(title: "格拉狄乌斯 · 远征首领 / 1 人", npcId: 75000020, players: .solo, deep: false,
              hp: 11328, effectivePoise: 120, poiseKind: .value,
              poiseRecover: 0.058, ailmentDamageRate: 0.5, buildupRate: 1),
        .init(title: "格拉狄乌斯 · 远征首领 / 2 人", npcId: 75000020, players: .duo, deep: false,
              hp: 22656, effectivePoise: 218.181818, poiseKind: .value,
              poiseRecover: 0.0319, ailmentDamageRate: 0.375, buildupRate: 0.85),
        .init(title: "格拉狄乌斯 · 远征首领 / 3 人", npcId: 75000020, players: .trio, deep: false,
              hp: 33984, effectivePoise: 400, poiseKind: .value,
              poiseRecover: 0.0174, ailmentDamageRate: 0.25, buildupRate: 0.7),
        .init(title: "玛利斯 · 永夜之王 · 二阶段 / 2 人", npcId: 75410000, players: .duo, deep: false,
              hp: 58906, effectivePoise: 1090.909091, poiseKind: .value,
              poiseRecover: 0, ailmentDamageRate: 0.375, buildupRate: 0.85),
        .init(title: "史柴格斯 · 远征首领 / 3 人 · 深夜", npcId: 76100010, players: .trio, deep: true,
              hp: 34665, effectivePoise: 500.160051, poiseKind: .value,
              poiseRecover: 0.0174, ailmentDamageRate: 0.25, buildupRate: 0.7),
        .init(title: "神皮使徒 · 守夜代表行 / 2 人", npcId: 35600900, players: .duo, deep: false,
              hp: 9551, effectivePoise: 145.454545, poiseKind: .value,
              poiseRecover: 0.1595, ailmentDamageRate: 0.46, buildupRate: 0.955),
        .init(title: "神皮使徒 · 野外代表行 / 2 人", npcId: 35600020, players: .duo, deep: false,
              hp: 6535, effectivePoise: 106.666667, poiseKind: .value,
              poiseRecover: 0.2175, ailmentDamageRate: 0.82, buildupRate: 0.889),
        .init(title: "大型黄金河马 · 守夜代表行 / 3 人", npcId: 50100010, players: .trio, deep: false,
              hp: 17747, effectivePoise: 266.666667, poiseKind: .value,
              poiseRecover: 0.087, ailmentDamageRate: 0.315, buildupRate: 0.778),
        .init(title: "大型黄金河马 · 野外代表行 / 3 人", npcId: 50100000, players: .trio, deep: false,
              hp: 5606, effectivePoise: 160, poiseKind: .value,
              poiseRecover: 0.145, ailmentDamageRate: 0.95, buildupRate: 0.97),
        .init(title: "未知敌人 c7931（poise = 0）/ 2 人", npcId: 79310000, players: .duo, deep: false,
              hp: 6851, effectivePoise: nil, poiseKind: .zero,
              poiseRecover: 0.1595, ailmentDamageRate: 0.46, buildupRate: 0.955),
        .init(title: "鲜血君王的长枪 · 召唤物（poise = -1）/ 2 人", npcId: 48010010, players: .duo, deep: false,
              hp: 674, effectivePoise: nil, poiseKind: .none,
              poiseRecover: 0.0319, ailmentDamageRate: 0.375, buildupRate: 0.85),
    ]
    let rowsByNpcId = Dictionary(bossAllRows(dataset).map { ($0.npcId, $0) }, uniquingKeysWith: { first, _ in first })
    for item in parityCases {
        guard let row = rowsByNpcId[item.npcId] else {
            throw CheckFailure(description: "首领数据：对照表找不到 npcId \(item.npcId)（\(item.title)）")
        }
        let got = row.stats(for: item.players, deepOfNight: item.deep)
        try bossExpect(got.hp == item.hp, "对照表 \(item.title)：血量应为 \(item.hp)，实际 \(got.hp)", counter: &count)
        try bossExpect(got.poiseKind == item.poiseKind, "对照表 \(item.title)：削韧槽语义不符", counter: &count)
        if let expected = item.effectivePoise {
            try bossExpectClose(got.effectivePoise, expected, "对照表 \(item.title)：有效韧性", tolerance: 0.0001, counter: &count)
        } else {
            try bossExpect(got.effectivePoise == nil, "对照表 \(item.title)：有效韧性应算不出来", counter: &count)
        }
        try bossExpectClose(got.poiseRecover, item.poiseRecover, "对照表 \(item.title)：削韧恢复", tolerance: 0.000001, counter: &count)
        try bossExpectClose(got.ailmentDamageRate, item.ailmentDamageRate, "对照表 \(item.title)：异常发动伤害", tolerance: 0.000001, counter: &count)
        try bossExpectClose(got.ailmentBuildupRate, item.buildupRate, "对照表 \(item.title)：异常累积", tolerance: 0.000001, counter: &count)
    }
    // 对照表里的代表行必须就是页面折叠态会选中的那一行
    guard let hippo = index.cards.first(where: { $0.id == "boss-Large Golden Hippopotamus@5010" }) else {
        throw CheckFailure(description: "首领数据：对照表锚点卡片「大型黄金河马」缺失")
    }
    try bossExpect(
        rowsByNpcId.count == bossAllRows(dataset).count,
        "代表行 npcId 在全量行里应唯一，对照表才能按 npcId 定位",
        counter: &count
    )
    try bossExpect(
        gladiusCard.representativeRow(in: .nightlord)?.npcId == 75000020
            && maris.representativeRow(in: .nightlord)?.npcId == 75410000,
        "对照表里的夜王代表行应与折叠态一致",
        counter: &count
    )
    try bossExpect(
        hippo.representativeRow(in: .night)?.npcId == 50100010
            && hippo.representativeRow(in: .field)?.npcId == 50100000,
        "对照表里的大型黄金河马代表行应与折叠态一致",
        counter: &count
    )

    // 13. 宽容解码：未知字段忽略 + 缺字段退默认值 + 坏元素跳过
    let lenientJSON = """
    {
      "bossesSchemaVersion": 2,
      "futureTopLevelField": {"whatever": [1, 2, 3]},
      "caveats": ["测试"],
      "scalingTiers": {"7760": {"group": "X", "duo": {"hp": 2}}},
      "permanentScaling": {"7767": {"nameZh": "测试缩放", "hp": 1.5, "deepOfNight": true}},
      "nightlords": [
        12345,
        {
          "menuId": 1,
          "nameZh": "测试夜王",
          "brandNewField": "忽略我",
          "fights": [
            {"npcId": 1, "labelZh": "甲", "hp": "4200", "poise": 100, "unknown": true,
             "damageRates": {"holy": 2}, "resist": {"madness": 999},
             "scaling": {"duo": {"hp": 2, "poiseTaken": 0.5}}},
            "这一行不是对象"
          ]
        }
      ],
      "nightBosses": [
        {"nameEn": "Test Boss", "chrIds": [4500], "tier": "field",
         "variants": [{"npcId": 9, "labelZh": "乙"}]},
        {"nameEn": "Dual Boss", "chrIds": [4600], "tier": "night", "tiers": ["field", "night"],
         "npcNameId": 12345,
         "variants": [{"npcId": 10, "labelZh": "丙", "threat": "night"},
                      {"npcId": 11, "labelZh": "丁", "threat": "field"}]}
      ]
    }
    """
    let lenient = try BossDataIndex(data: Data(lenientJSON.utf8))
    try bossExpect(lenient.dataset.nightlords.count == 1, "坏的 nightlord 元素应被跳过", counter: &count)
    guard let testLord = lenient.dataset.nightlords.first, let testFight = testLord.fights.first else {
        throw CheckFailure(description: "首领数据：宽容解码样本里应保留 1 位夜王与 1 条 fight")
    }
    try bossExpect(testLord.fights.count == 1, "坏的 fight 元素应被跳过", counter: &count)
    try bossExpect(testLord.nameEn.isEmpty && testLord.expeditionZh.isEmpty, "缺失的字符串字段应退为空串", counter: &count)
    try bossExpect(testLord.weakness.isEmpty && testLord.variantKey == "normal", "缺失的数组 / 变体字段应有默认值", counter: &count)
    try bossExpect(testFight.hp == 4200, "字符串形式的数字也应能解出", counter: &count)
    try bossExpect(testFight.hp(for: .duo) == 8400, "缺档的字段不应影响换算", counter: &count)
    try bossExpectClose(testFight.effectivePoise(for: .duo), 200, "poiseTakenBase 缺失时应按 1 处理", counter: &count)
    try bossExpect(testFight.damageRates.standard == 1, "缺失的承伤倍率应退为 1", counter: &count)
    try bossExpect(testFight.resist.isImmune(to: .madness), "只给一项的 resist 也应能解出", counter: &count)
    try bossExpect(testFight.immuneKinds() == [.madness], "immune 缺失时应按 999 回推免疫列表", counter: &count)
    try bossExpect(testFight.deepOfNight == nil && !testFight.hasDeepOfNight, "缺 deepOfNight 时应为 nil", counter: &count)
    try bossExpect(lenient.dataset.scalingGroup(7760)?.duo?.hp == 2, "scalingTiers 应能按 ID 反查", counter: &count)
    try bossExpect(lenient.dataset.permanentEffect(7767)?.deepOfNight == true, "permanentScaling 应能按 ID 反查", counter: &count)
    try bossExpect(lenient.dataset.nightBosses.first?.id == "Test Boss@4500", "缺 id 时应按 nameEn@chrId 回填", counter: &count)
    try bossExpect(lenient.cards(in: .field).count == 2, "宽容样本应产出 2 张野外卡片（含 tiers 多值的那组）", counter: &count)
    try bossExpect(lenient.cards(in: .night).count == 1, "宽容样本应产出 1 张守夜卡片", counter: &count)
    try bossExpect(lenient.dualTierCards.count == 1, "tiers 同时含 field 与 night 的组应被识别出来", counter: &count)
    guard let dualCard = lenient.dualTierCards.first else {
        throw CheckFailure(description: "首领数据：宽容样本里应有一张两种档位都有的卡片")
    }
    try bossExpect(dualCard.group == .night, "主分组应仍按 tier 取 night", counter: &count)
    try bossExpect(dualCard.groups.first == .night, "主分组应排在 groups 最前", counter: &count)
    try bossExpect(dualCard.rows.compactMap(\.threatTitle) == ["守夜", "野外"], "每行都应能取到威胁档位标记", counter: &count)
    try bossExpect(
        lenient.cards(in: .field, query: "12345").contains { $0.id == dualCard.id },
        "npcNameId 也应能搜到",
        counter: &count
    )
    try bossExpect(
        lenient.cards(in: .field, query: "11").contains { $0.id == dualCard.id },
        "按变体 npcId 应能搜到",
        counter: &count
    )

    // 14. 空数据 / 非对象应报错而不是崩溃
    do {
        _ = try BossDataIndex(data: Data("[]".utf8))
        throw CheckFailure(description: "首领数据：顶层不是对象时应抛错")
    } catch BossDataError.notAnObject {
        count += 1
    }
    do {
        _ = try BossDataIndex(data: Data("{}".utf8))
        throw CheckFailure(description: "首领数据：没有任何首领记录时应抛错")
    } catch BossDataError.empty {
        count += 1
    }
    // 截断 / 损坏的 JSON 要带上原始错误，不能一律吞成「不是合法的 JSON 对象」
    do {
        _ = try BossDataIndex(data: Data("{\"nightlords\": [".utf8))
        throw CheckFailure(description: "首领数据：截断的 JSON 应抛错")
    } catch BossDataError.undecodable(let detail) {
        try bossExpect(!detail.isEmpty, "截断的 JSON 应带上原始错误说明", counter: &count)
        try bossExpect(
            (BossDataError.undecodable(detail).errorDescription ?? "").contains(detail),
            "错误文案应包含原始错误说明，便于排障",
            counter: &count
        )
    }
    do {
        _ = try BossDataIndex(data: Data([0xFF, 0xFE, 0x00, 0x01]))
        throw CheckFailure(description: "首领数据：非法编码应抛错")
    } catch BossDataError.undecodable {
        count += 1
    }

    return count
}

// MARK: - 双端文案一致性（与 Windows 端 pages/bosses.js 逐字对照）

/// 展开态「多人缩放明细」的档位说明。视图层与这里都调 `BossRowText.scalingCaption`，
/// Windows 端 `pages/bosses.js` 的 `scalingCaption()` 是同一组分支、同一串文案——
/// 上一轮两端各自把不同的字面量写死（这边 `档位 #98815`、那边 `档位 98815`），
/// 两份注释却都声称「逐字一致」。现在串只有一份，注释才名副其实。
private func bossScalingCaption(_ scalingID: Int?, dataset: BossDataset) -> String {
    BossRowText.scalingCaption(
        scalingID: scalingID,
        groupTitle: scalingID.flatMap { dataset.scalingGroup($0)?.title }
    )
}

/// 首领数据页两端必须逐字相同的文案：档位分组名、行内徽标、数值行计数、
/// 承受削韧倍率异常时的占位符与小字。
func checkBossDataParityText() throws -> Int {
    var count = 0

    let url = bossesResourceURL
    guard FileManager.default.fileExists(atPath: url.path) else {
        throw CheckFailure(description: "首领数据文案：缺少 \(url.path)")
    }
    let data = try Data(contentsOf: url)
    if GameDataLoader.isPlaceholder(data) {
        print("    （bosses.json 仍是占位内容，跳过首领数据文案检查）")
        return 0
    }
    let dataset = try BossDataIndex(data: data).dataset

    // ① group = null 的档位一律写「其它档位」，展开态与底部档位表同名
    try bossExpect(BossScalingGroup.title(for: nil) == "其它档位", "group = nil 应写「其它档位」", counter: &count)
    try bossExpect(BossScalingGroup.title(for: "") == "其它档位", "group = 空串也算缺失", counter: &count)
    try bossExpect(
        BossScalingGroup.title(for: "Final Boss Threat") == "最终首领威胁档",
        "已知分组名应翻译",
        counter: &count
    )
    try bossExpect(
        BossScalingGroup.title(for: "Brand New Threat") == "Brand New Threat",
        "未知分组名照原样显示",
        counter: &count
    )
    let nullGroupIDs = dataset.scalingTiers.values.filter { $0.group == nil }.map(\.id).sorted()
    try bossExpect(
        nullGroupIDs == [98810, 98815, 98818, 98822],
        "数据里 group = null 的档位应是 98810/98815/98818/98822，实际 \(nullGroupIDs)",
        counter: &count
    )
    for id in nullGroupIDs {
        let caption = bossScalingCaption(id, dataset: dataset)
        try bossExpect(
            caption == "档位 #\(id) · 其它档位",
            "档位 \(id) 的展开态标题应写「其它档位」，实际 \(caption)",
            counter: &count
        )
    }
    try bossExpect(bossScalingCaption(nil, dataset: dataset) == "无缩放档位", "没有档位时的文案", counter: &count)
    try bossExpect(
        bossScalingCaption(4_040_404, dataset: dataset) == "档位 #4040404",
        "查不到的档位只写档位号",
        counter: &count
    )
    // 每条数值行的档位都查得到，且都有分组名
    for row in bossAllRows(dataset) {
        guard let id = row.scalingId else { continue }
        let caption = bossScalingCaption(id, dataset: dataset)
        try bossExpect(caption.contains(" · "), "档位 \(id) 少了分组名：\(caption)", counter: &count)
    }

    // ② 行内徽标 / 卡头计数的统一文案
    try bossExpect(BossRowText.labelUncertainBadge == "标签为社区推测", "labelUncertain 徽标文案", counter: &count)
    try bossExpect(BossRowText.deepRowBadge == "深夜数值", "深夜行徽标文案", counter: &count)
    try bossExpect(BossRowText.rowCount(5) == "5 条数值行", "数值行计数文案", counter: &count)
    try bossExpect(BossRowText.rowCount(1) == "1 条数值行", "数值行计数文案（单数也不变）", counter: &count)
    try bossExpect(
        BossDeepCoverage.all.badgeText == BossRowText.deepRowBadge,
        "卡头深夜徽标与行内徽标同一套说法",
        counter: &count
    )
    try bossExpect(
        BossDeepCoverage.some.badgeText == "部分行有深夜数值",
        "部分行有深夜数值的卡头徽标",
        counter: &count
    )
    try bossExpect(
        bossAllRows(dataset).contains { $0.labelUncertain },
        "数据集里应存在 labelUncertain 的行（徽标文案才有意义）",
        counter: &count
    )

    // ③a 承伤倍率徽标两位小数
    try bossExpect(BossRowText.decimal(1.2345, digits: 2) == "1.23", "两位小数", counter: &count)
    try bossExpect(BossRowText.decimal(1.006, digits: 2) == "1.01", "两位小数进位", counter: &count)
    try bossExpect(BossRowText.decimal(1.1, digits: 2) == "1.1", "去掉多余的 0", counter: &count)
    try bossExpect(BossRowText.decimal(1.2346, digits: 3) == "1.235", "默认三位仍可用", counter: &count)
    try bossExpect(BossRowText.decimal(.infinity) == "—", "非有限数给占位符", counter: &count)

    // ③b poise > 0 但承受削韧倍率为 0 / 非有限
    try bossExpect(BossPoiseKind.value.placeholder == "—", "算不出有效韧性时的占位符", counter: &count)
    try bossExpect(BossPoiseKind.zero.placeholder == "无削韧槽", "poise = 0 的占位符", counter: &count)
    try bossExpect(BossPoiseKind.none.placeholder == "不吃削韧", "poise < 0 的占位符", counter: &count)
    try bossExpect(
        BossRowText.abnormalPoiseTakenCaption(0) == "承受削韧倍率异常（0）",
        "承受削韧异常时的小字，实际 \(BossRowText.abnormalPoiseTakenCaption(0))",
        counter: &count
    )
    let brokenJSON = """
    {"npcId": 1, "labelZh": "坏行", "isMain": true, "hp": 1000, "hpBase": 1000,
     "hpMultiplier": 1, "poise": 120, "poiseRecover": 1, "poiseTakenBase": 0,
     "poiseRecoverMultiplier": 1, "ailmentDamageRateBase": 0,
     "scaling": {"duo": {"hp": 2, "poiseTaken": 0.55, "poiseRecover": 0.55,
                         "buildupRate": 1, "ailmentDamageRate": 1}}}
    """
    let brokenRow = try JSONDecoder().decode(BossFight.self, from: Data(brokenJSON.utf8))
    let brokenStats = brokenRow.stats(for: .duo)
    try bossExpect(brokenRow.poiseTakenBase == 0, "数据里的 0 不能被改写成 1", counter: &count)
    try bossExpect(brokenRow.poiseKind == .value, "poise = 120 仍是「有削韧槽」", counter: &count)
    try bossExpect(brokenStats.effectivePoise == nil, "分母为 0 时算不出有效韧性", counter: &count)
    try bossExpect(
        brokenStats.poiseKind.placeholder == "—",
        "poise > 0 而分母异常时显示「—」，不能写成「不吃削韧」",
        counter: &count
    )
    try bossExpect(
        BossRowText.abnormalPoiseTakenCaption(brokenStats.poiseTakenBase * brokenStats.tier.poiseTaken)
            == "承受削韧倍率异常（0）",
        "异常小字取的是 poiseTakenBase × 档位倍率",
        counter: &count
    )

    // ③ 有效韧性小字的另外三支也必须两端逐字一致（上一轮只统一了异常那一支）
    try bossExpect(
        BossRowText.poiseCaption(poise: 120, poiseTakenTotal: 0.55, kind: .value, hasEffectivePoise: true)
            == "韧性 120 ÷ 承受削韧 0.55",
        "能算出有效韧性时的小字，实际 "
            + BossRowText.poiseCaption(poise: 120, poiseTakenTotal: 0.55, kind: .value, hasEffectivePoise: true),
        counter: &count
    )
    try bossExpect(
        BossRowText.poiseCaption(poise: 0, poiseTakenTotal: 1, kind: .zero, hasEffectivePoise: false)
            == "superArmorDurability = 0，该实体没有削韧槽",
        "poise = 0 时的小字",
        counter: &count
    )
    try bossExpect(
        BossRowText.poiseCaption(poise: -1, poiseTakenTotal: 1, kind: .none, hasEffectivePoise: false)
            == "superArmorDurability = -1",
        "poise < 0 时的小字",
        counter: &count
    )
    try bossExpect(
        BossRowText.poiseCaption(poise: 120, poiseTakenTotal: 0, kind: .value, hasEffectivePoise: false)
            == "承受削韧倍率异常（0）",
        "倍率异常时的小字仍走 abnormalPoiseTakenCaption",
        counter: &count
    )
    try bossExpect(
        BossRowText.poiseCaption(
            poise: brokenRow.poise,
            poiseTakenTotal: brokenStats.poiseTakenBase * brokenStats.tier.poiseTaken,
            kind: brokenStats.poiseKind,
            hasEffectivePoise: brokenStats.effectivePoise != nil
        ) == "承受削韧倍率异常（0）",
        "真实换算结果也走同一支",
        counter: &count
    )

    return count
}
