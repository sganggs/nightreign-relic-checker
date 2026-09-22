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
    // schemaVersion 3：cards(in:) 默认滤掉 hidden 的组，统计「收录了多少」时要显式带上。
    let lords = index.cards(in: .nightlord, includeHidden: true)
    let night = index.cards(in: .night, includeHidden: true)
    let field = index.cards(in: .field, includeHidden: true)
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
    //     schemaVersion 3 第二轮核验：16 → 12 条。两类原本混在一起，现在拆开：
    //     - unmatchedNames = **游戏文本里查无此名**的组（12 条，Putrid Flesh /
    //       Giant Skeleton Torso / 四个 Fire Knight …），页面可以说「游戏里没有这个名字」；
    //     - nameCollisions = **匹配到了文本、但因为两张卡会顶同一个中文名而让出**的组
    //       （4 条：雪花石之王 / 缟玛瑙之王 / 大型黄金河马 / 废弃物蚯蚓脸），
    //       它们的候选词条与裁决理由完整记在 notes.nameCollisions 里。
    //     两者都退回 nameSource = english-only，旧译名都在 nameZhFallback 里，
    //     但「查无此名」和「有名字但让出」是两回事，不该合并计数。
    try bossExpect(
        (dataset.notes?.unmatchedNames.count ?? 0) == 12,
        "notes.unmatchedNames 应有 12 条（Putrid Flesh / Giant Skeleton Torso 等游戏文本里查无此名的组）",
        counter: &count
    )

    // 9g. 守夜 / 野外的代表行必须跟着分组走（Windows 侧遗留问题：恒取 variants[0]）
    //     同一组首领可能两种档位都有，野外分组下就该看野外那几行。
    guard let apostleNight = apostle.representativeRow(in: .night),
          let apostleField = apostle.representativeRow(in: .field)
    else {
        throw CheckFailure(description: "首领数据：神皮使徒在两个分组下都应有代表行")
    }
    // schemaVersion 3：35600900「基准（行 35600900）」是 noReward = true 的 Paramdex 模板行，
    // 血量最高却不掉任何奖励，代表位让给真正能打到的「最古老的牢狱」35600110。
    try bossExpect(
        apostleNight.npcId == 35600110 && apostleNight.threat == "night",
        "神皮使徒在守夜分组下的代表行应是 npcId 35600110，实际 \(apostleNight.npcId)",
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
    // schemaVersion 3：c4504 被社区资料认出是 Elder Dragon Greyoll，不再是 chrid-fallback；
    // 现在只剩 c7931 / c7932 这两组连社区也认不出的实体。
    let chrFallback = try cardForBoss("Unknown Enemy (c7931)@7931")
    try bossExpect(
        chrFallback.nameBadge == .noGameName && chrFallback.nameBadge?.text == "无游戏内名称",
        "chrid-fallback 应挂「无游戏内名称」徽标",
        counter: &count
    )
    // schemaVersion 3 第二轮核验：「未知敌人 cXXXX」是生成器用 chrId 拼出来的占位串，
    // 不是游戏文本，留在 nameZh 里与数据集自己的「简中名只来自游戏文本」相矛盾，
    // 已挪到新字段 displayFallbackZh（与 nameZhFallback 的「旧译名」是两回事，见 caveats）。
    // 因此 nameZh 为空、displayName 落到英文名那一支；徽标看的是 nameSource，没变。
    // 页面侧把 displayFallbackZh 接进显示名之后，这里的期望值再改回「未知敌人 c7931」。
    try bossExpect(chrFallback.nameZh.isEmpty, "chrid-fallback 的 nameZh 应为空（占位名不进 nameZh）", counter: &count)
    try bossExpect(
        chrFallback.displayName == "Unknown Enemy (c7931)",
        "nameZh 为空时显示名回退到英文名",
        counter: &count
    )
    // schemaVersion 3：nameSource = manual 不再产出。Cemetery Shade 的手工译名「墓地幽魂」
    // 已移出 nameZh（进 nameZhFallback），徽标从「名称手工补录」变成「仅英文名」——
    // nameZh 为空的分支优先于 nameInferred，徽标优先级仍然在这里验。
    let fallbackCard = try cardForBoss("Cemetery Shade@3664")
    try bossExpect(
        fallbackCard.nameSource == "english-only" && fallbackCard.nameInferred,
        "Cemetery Shade 现在是 english-only 且 nameInferred，用来验证徽标优先级",
        counter: &count
    )
    try bossExpect(
        fallbackCard.nameBadge == .englishOnly && fallbackCard.nameBadge?.text == "仅英文名",
        "nameZh 为空优先于 nameInferred，文案应为「仅英文名」",
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

    // 9j. 深夜覆盖度扫描整张卡，不只看代表行。
    //     schemaVersion 3 起分成两套口径，卡头挂的是两个不同的徽标：
    //       * deepCoverage（hasDepthStats）→「深夜数值」：深度模式下这张卡的血量 /
    //         攻击倍率变不变。v3 里 394 行全部有 depthStats，所以每张卡都是 .all。
    //       * deepOfNightCoverage（hasDeepOfNight）→「深夜专属修正」：有没有额外那组
    //         深夜专属常驻修正（削韧恢复 / 异常发动基准 / 常驻 SpEffect 另一套），只有 31 行有。
    //     早先两者都按 hasDeepOfNight 判，于是深度模式下 18 张卡会写「部分行有深夜数值」、
    //     另外 112 张一个徽标都不挂——在功能核心模式下这是明确的错误陈述。
    try bossExpect(
        index.cards.allSatisfy { $0.deepCoverage == .all },
        "v3 每条数值行都有 depthStats，深度模式下每张卡都应判为「深夜数值」，实际有 "
            + "\(index.cards.filter { $0.deepCoverage != .all }.count) 张不是",
        counter: &count
    )
    try bossExpect(
        index.cards.first?.deepCoverage.badgeText == BossRowText.deepRowBadge,
        "整卡都有深度数值时徽标为「深夜数值」",
        counter: &count
    )
    try bossExpect(
        bossAllRows(dataset).allSatisfy(\.hasDepthStats),
        "「深夜数值」徽标的判据是 hasDepthStats，数据里不应有缺 depthStats 的行",
        counter: &count
    )
    try bossExpect(
        gnoster.deepOfNightCoverage == .some,
        "格诺斯塔 · 永夜之王 6 条 fights 里 3 条有 deepOfNight，整卡应判为「部分行有深夜专属修正」",
        counter: &count
    )
    try bossExpect(
        gnoster.deepOfNightCoverage.exclusiveBadgeText == "部分行有深夜专属修正",
        "「部分行有深夜专属修正」的徽标文案两端一致",
        counter: &count
    )
    try bossExpect(
        gnoster.deepCoverage == .all && gnoster.deepCoverage.badgeText == BossRowText.deepRowBadge,
        "同一张卡的「深夜数值」仍是整卡命中——深夜专属修正只有部分行，不代表其余行数值不变",
        counter: &count
    )
    // 只看代表行会判错的卡：代表行没有 deepOfNight，卡里其余行却有。
    let misjudged = index.cards.filter { card in
        card.deepOfNightCoverage != .none && card.representativeRow(in: card.group)?.hasDeepOfNight != true
    }
    try bossExpect(
        Set(misjudged.map(\.id)) == [
            "nightlord-18", "boss-Dreg Wormface@7660", "boss-Curseblade@5040", "boss-Death Knight@5070",
        ],
        "靠扫描整卡才判得对的应是这 4 张（代表行换成有奖励的行之后多了咒剑与死亡骑士），"
            + "实际 \(misjudged.map(\.id).sorted())",
        counter: &count
    )
    let deepCards = index.cards.filter { $0.deepOfNightCoverage != .none }
    try bossExpect(deepCards.count == 22, "应有 22 张卡片带深夜专属修正，实际 \(deepCards.count)", counter: &count)
    try bossExpect(
        index.cards.filter { $0.deepOfNightCoverage == .all }.count == 4,
        "其中 4 张整卡每行都有深夜专属修正",
        counter: &count
    )
    try bossExpect(
        deepCards.contains { $0.group != .nightlord },
        "深夜专属修正不是夜王独有，守夜 / 野外也有",
        counter: &count
    )
    try bossExpect(
        index.cards.first(where: { $0.deepOfNightCoverage == .all })?.deepOfNightCoverage.exclusiveBadgeText
            == BossRowText.deepExclusiveBadge,
        "整卡都有深夜专属修正时徽标为「深夜专属修正」",
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
    // schemaVersion 3：守夜 51 → 50（c7711 与 c7712 被社区资料认出是同一只 Centipede Grub，
    // 两组合并），数值行 384 → 394（merge_key 加入 chaosCorrectId / mutationSetId 后拆分，
    // 再扣掉 10 条 Paramdex 模板行）。与 Windows 端 bosses.test.mjs 的同名断言保持一致。
    try bossExpect(
        index.inventorySummary == "夜王 18 · 守夜 50 · 野外 72（含 6 组两边都出现） · 数值行 394",
        "收录统计文案应为「夜王 18 · 守夜 50 · 野外 72（含 6 组两边都出现） · 数值行 394」，实际「\(index.inventorySummary)」",
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

    // 11. 深夜 · 深度：depthStats 才是深夜的真数值
    //     v2 只算到「深夜修正」（deepOfNight），缺了最后一层深度倍率，于是深度 1 与深度 5
    //     在页面上是同一个数——正是用户说的「深夜不同深度的属性没展示」。
    let deepRows = bossAllRows(dataset).filter(\.hasDeepOfNight)
    try bossExpect(!deepRows.isEmpty, "应存在带深夜专属缩放的行", counter: &count)
    try bossExpect(
        bossAllRows(dataset).allSatisfy(\.hasDepthStats),
        "当前数据里每条数值行都应有 depthStats",
        counter: &count
    )
    try bossExpect(
        bossAllRows(dataset).allSatisfy { $0.availableDepths == [1, 2, 3, 4, 5] },
        "depthStats 的键应正好是深度 1…5",
        counter: &count
    )
    try bossExpect(main.hp(for: .solo, mode: .normal) == main.hp, "常规模式应取常规血量", counter: &count)
    for depth in 1...5 {
        let mode = BossNightMode.depth(depth)
        try bossExpect(
            main.hp(for: .solo, mode: mode) == main.depthStats[depth]?.hp,
            "深度 \(depth) 的单人血量应直接取 depthStats[\(depth)].hp",
            counter: &count
        )
        try bossExpect(
            main.hp(for: .trio, mode: mode) == (main.depthStats[depth]?.hp ?? 0) * 3,
            "深度 \(depth) 的三人血量应是深度血量 × 3（最终 Boss 档三人 ×3）",
            counter: &count
        )
        try bossExpectClose(
            main.effectivePoise(for: .solo, mode: mode),
            main.poise / (main.depthStats[depth]?.poiseTakenBase ?? 1),
            "深度 \(depth) 的有效韧性分母应取 depthStats[\(depth)].poiseTakenBase",
            tolerance: 0.0001, counter: &count
        )
    }
    // 格拉狄乌斯 · 远征首领：深度 1→5 的血量与攻击力倍率（Tier 3f 档位）
    try bossExpect(
        (1...5).map { main.hp(for: .solo, mode: .depth($0)) } == [14160, 15859, 17785, 22090, 24468],
        "格拉狄乌斯远征首领深度 1–5 的单人血量应为 14160 / 15859 / 17785 / 22090 / 24468，"
            + "实际 \((1...5).map { main.hp(for: .solo, mode: .depth($0)) })",
        counter: &count
    )
    try bossExpectClose(
        main.attackRate(for: .solo, mode: .normal), 3.36,
        "格拉狄乌斯常规攻击力倍率应为 3.36", tolerance: 0.0001, counter: &count
    )
    try bossExpectClose(
        main.attackRate(for: .solo, mode: .depth1), 4.2,
        "深度 1 攻击力倍率应为 3.36 × 1.25", tolerance: 0.0001, counter: &count
    )
    try bossExpectClose(
        main.attackRate(for: .solo, mode: .depth5), 11.1216,
        "深度 5 攻击力倍率应为 11.1216", tolerance: 0.0001, counter: &count
    )
    // 攻击力涨得比血量快得多：深度 5 的伤害是深度 1 的 2.27 倍，血量只有 1.73 倍。
    try bossExpectClose(
        main.attackRate(for: .solo, mode: .depth5) / main.attackRate(for: .solo, mode: .depth1),
        2.6480, "深度 5 / 深度 1 的攻击力比（含常驻基准）", tolerance: 0.001, counter: &count
    )
    // 全量行：血量与攻击力随深度单调不减（[Caligo Raid] 那种全 ×1 的档位也满足）
    try bossExpect(
        bossAllRows(dataset).allSatisfy { row in
            let hps = row.depthRows(for: .solo).map(\.hp)
            return zip(hps, hps.dropFirst()).allSatisfy { $0 <= $1 }
        },
        "同一行的深度血量应随深度单调不减",
        counter: &count
    )
    try bossExpect(
        bossAllRows(dataset).allSatisfy { row in
            let rates = row.depthRows(for: .solo).map(\.attackRate)
            return zip(rates, rates.dropFirst()).allSatisfy { $0 <= $1 + 0.000001 }
        },
        "同一行的深度攻击力倍率应随深度单调不减",
        counter: &count
    )
    // 深度小表与逐项换算必须同源：小表里的每一格都得等于对应 mode 的单点结果
    try bossExpect(
        bossAllRows(dataset).allSatisfy { row in
            row.depthRows(for: .duo).allSatisfy { item in
                item.hp == row.hp(for: .duo, mode: .depth(item.depth))
                    && abs(item.attackRate - row.attackRate(for: .duo, mode: .depth(item.depth))) < 0.000001
            }
        },
        "「深夜各深度」小表应与单点换算完全一致",
        counter: &count
    )
    // 没有 depthStats 的行要能说清楚「该行无深夜数值」，而不是悄悄退回常规值
    let noDepthJSON = """
    {"npcId": 7, "labelZh": "没有深夜数值的行", "hp": 1000, "hpBase": 1000, "hpMultiplier": 1,
     "poise": 100, "poiseRecover": 1, "poiseTakenBase": 1, "attackRateBase": 2,
     "scaling": {"duo": {"hp": 2}}}
    """
    let noDepthRow = try JSONDecoder().decode(BossFight.self, from: Data(noDepthJSON.utf8))
    try bossExpect(!noDepthRow.hasDepthStats, "缺 depthStats 的行应被识别出来", counter: &count)
    try bossExpect(noDepthRow.depthRows(for: .duo).isEmpty, "缺 depthStats 时小表应为空", counter: &count)
    try bossExpect(
        noDepthRow.stats(for: .duo, mode: .depth3).depthMissing,
        "缺 depthStats 时应标出 depthMissing，页面才写得出「该行无深夜数值」",
        counter: &count
    )
    try bossExpect(
        noDepthRow.hp(for: .duo, mode: .depth3) == noDepthRow.hp(for: .duo, mode: .normal),
        "缺 depthStats 时深度模式退回常规数值",
        counter: &count
    )
    try bossExpect(
        !main.stats(for: .duo, mode: .depth3).depthMissing,
        "有 depthStats 的行不应被标成 depthMissing",
        counter: &count
    )

    // 11b. 深度路径下的韧性 / 削韧恢复 / 异常倍率同样对硬编码期望值
    //      史柴格斯 · 远征首领 76100010：poise 150，常规 poiseTakenBase 0.88，
    //      深夜修正 0.99968，深度 1 的 poiseTakenBase = 0.99968 × 0.88 = 0.879718。
    guard let stray = dataset.nightlords.first(where: { $0.nameZh == "史柴格斯" && $0.variantKey == "normal" }),
          let strayMain = stray.fights.first(where: { $0.npcId == 76100010 }),
          let strayDeep = strayMain.deepOfNight
    else {
        throw CheckFailure(description: "首领数据：找不到史柴格斯的远征首领行（npcId 76100010）")
    }
    try bossExpect(strayMain.hp == 14443, "史柴格斯远征首领常规血量应为 14443，实际 \(strayMain.hp)", counter: &count)
    try bossExpect(strayDeep.hp == 11555, "深夜修正（不含深度）血量应为 11555，实际 \(strayDeep.hp)", counter: &count)
    try bossExpect(
        strayMain.depthStats[1]?.hp == 14443,
        "深度 1 血量 = 深夜修正 11555 × 深度倍率 1.25 = 14443，实际 \(strayMain.depthStats[1].map { String($0.hp) } ?? "nil")",
        counter: &count
    )
    try bossExpect(
        strayMain.hp(for: .trio, mode: .depth1) == 43329,
        "深度 1 三人血量应为 14443 × 3，实际 \(strayMain.hp(for: .trio, mode: .depth1))",
        counter: &count
    )
    try bossExpectClose(
        strayMain.effectivePoise(for: .trio, mode: .normal), 568.1818,
        "常规三人有效韧性应为 150 /（0.88 × 0.3）", tolerance: 0.01, counter: &count
    )
    try bossExpectClose(
        strayMain.effectivePoise(for: .trio, mode: .depth1), 568.363953,
        "深度 1 三人有效韧性应为 150 /（0.879718 × 0.3）", tolerance: 0.0001, counter: &count
    )
    try bossExpectClose(
        strayMain.poiseRecoverSpeed(for: .trio, mode: .depth1), 0.0174,
        "深度 1 三人削韧恢复应为 0.29 × 0.2 × 0.3（削韧恢复倍率取深夜那一组）",
        tolerance: 0.0001, counter: &count
    )
    try bossExpectClose(
        strayMain.ailmentDamageRate(for: .duo, mode: .depth1), 0.375,
        "深度 1 双人异常发动伤害应为 0.5 × 0.75", tolerance: 0.0001, counter: &count
    )
    // 深度模式下的常驻 SpEffect 清单取深夜那一组（多了 7397「深夜修正」）
    try bossExpect(
        strayMain.baseline(mode: .depth3).permScalingIds == strayDeep.permScalingIds,
        "深度模式的常驻缩放清单应取深夜那一组",
        counter: &count
    )
    try bossExpect(
        strayMain.baseline(mode: .normal).permScalingIds == strayMain.permScalingIds,
        "常规模式仍取常规清单",
        counter: &count
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
        /// 常规 / 深夜 · 深度 1…5。
        let mode: BossNightMode
        let hp: Int
        /// nil = 算不出有效韧性（不吃削韧 / 无削韧槽）。
        let effectivePoise: Double?
        let poiseKind: BossPoiseKind
        let poiseRecover: Double
        let ailmentDamageRate: Double
        let buildupRate: Double
        /// 叠加的变异档位（SpEffectSetParam 行号）；nil = 不叠加。
        var mutationId: Int? = nil
        /// 敌人攻击力倍率；nil = 这条用例不校验攻击力。
        var attackRate: Double? = nil
        /// 卢恩倍率（只有变异个体会动它）。
        var runeRate: Double? = nil
    }
    // 注意：这张表按 npcId 直接取行，断言的是**换算公式**，不是折叠态选中的那一行。
    // 标题里的「代表行」只是说明这一行同时也是代表行（35600900 不是，它是 noReward 的
    // Paramdex 模板行）。「哪一行会被选中」由后面 12e 的 representativeCases 钉住。
    let parityCases: [ParityCase] = [
        .init(title: "格拉狄乌斯 · 远征首领 / 1 人", npcId: 75000020, players: .solo, mode: .normal,
              hp: 11328, effectivePoise: 120, poiseKind: .value,
              poiseRecover: 0.058, ailmentDamageRate: 0.5, buildupRate: 1),
        .init(title: "格拉狄乌斯 · 远征首领 / 2 人", npcId: 75000020, players: .duo, mode: .normal,
              hp: 22656, effectivePoise: 218.181818, poiseKind: .value,
              poiseRecover: 0.0319, ailmentDamageRate: 0.375, buildupRate: 0.85),
        .init(title: "格拉狄乌斯 · 远征首领 / 3 人", npcId: 75000020, players: .trio, mode: .normal,
              hp: 33984, effectivePoise: 400, poiseKind: .value,
              poiseRecover: 0.0174, ailmentDamageRate: 0.25, buildupRate: 0.7),
        .init(title: "玛利斯 · 永夜之王 · 二阶段 / 2 人", npcId: 75410000, players: .duo, mode: .normal,
              hp: 58906, effectivePoise: 1090.909091, poiseKind: .value,
              poiseRecover: 0, ailmentDamageRate: 0.375, buildupRate: 0.85),
        // 深度 1 = 深夜修正 × 深度倍率。v2 只算到深夜修正（11555 × 3 = 34665），
        // 少乘一层 1.25，页面上就看不出深度的差别。
        .init(title: "史柴格斯 · 远征首领 / 3 人 · 深度 1", npcId: 76100010, players: .trio, mode: .depth1,
              hp: 43329, effectivePoise: 568.363953, poiseKind: .value,
              poiseRecover: 0.0174, ailmentDamageRate: 0.25, buildupRate: 0.7,
              attackRate: 4.2),
        .init(title: "神皮使徒 · 模板行 35600900（守夜档位）/ 2 人", npcId: 35600900, players: .duo, mode: .normal,
              hp: 9551, effectivePoise: 145.454545, poiseKind: .value,
              poiseRecover: 0.1595, ailmentDamageRate: 0.46, buildupRate: 0.955),
        .init(title: "神皮使徒 · 野外代表行 35600020 / 2 人", npcId: 35600020, players: .duo, mode: .normal,
              hp: 6535, effectivePoise: 106.666667, poiseKind: .value,
              poiseRecover: 0.2175, ailmentDamageRate: 0.82, buildupRate: 0.889),
        .init(title: "大型黄金河马 · 守夜代表行 50100010 / 3 人", npcId: 50100010, players: .trio, mode: .normal,
              hp: 17747, effectivePoise: 266.666667, poiseKind: .value,
              poiseRecover: 0.087, ailmentDamageRate: 0.315, buildupRate: 0.778),
        .init(title: "大型黄金河马 · 野外代表行 50100000 / 3 人", npcId: 50100000, players: .trio, mode: .normal,
              hp: 5606, effectivePoise: 160, poiseKind: .value,
              poiseRecover: 0.145, ailmentDamageRate: 0.95, buildupRate: 0.97),
        .init(title: "未知敌人 c7931（poise = 0）/ 2 人", npcId: 79310000, players: .duo, mode: .normal,
              hp: 6851, effectivePoise: nil, poiseKind: .zero,
              poiseRecover: 0.1595, ailmentDamageRate: 0.46, buildupRate: 0.955),
        .init(title: "鲜血君王的长枪 · 召唤物（poise = -1）/ 2 人", npcId: 48010010, players: .duo, mode: .normal,
              hp: 674, effectivePoise: nil, poiseKind: .none,
              poiseRecover: 0.0319, ailmentDamageRate: 0.375, buildupRate: 0.85),
        // schemaVersion 3 的三组新口径，两端对同一组输入必须给同样的数：
        // ① 格拉狄乌斯 3 人 · 深度 5；② 野外 Boss 2 人 · 深度 3 · 变异档位；③ 同一行不叠变异作对照。
        .init(title: "格拉狄乌斯 · 远征首领 / 3 人 · 深度 5", npcId: 75000020, players: .trio, mode: .depth5,
              hp: 73404, effectivePoise: 476.190476, poiseKind: .value,
              poiseRecover: 0.0174, ailmentDamageRate: 0.25, buildupRate: 0.7,
              attackRate: 11.1216, runeRate: 1),
        .init(title: "神皮使徒 · 封印监牢（野外）/ 2 人 · 深度 3", npcId: 35600020, players: .duo, mode: .depth3,
              hp: 9723, effectivePoise: 124.031008, poiseKind: .value,
              poiseRecover: 0.2175, ailmentDamageRate: 0.82, buildupRate: 0.889,
              attackRate: 5.46777, runeRate: 1),
        .init(title: "神皮使徒 · 封印监牢（野外）/ 2 人 · 深度 3 · 变异 #113140",
              npcId: 35600020, players: .duo, mode: .depth3,
              hp: 11182, effectivePoise: 124.031008, poiseKind: .value,
              poiseRecover: 0.2175, ailmentDamageRate: 0.82, buildupRate: 0.889,
              mutationId: 113140, attackRate: 6.2879355, runeRate: 1.35),
    ]
    let rowsByNpcId = Dictionary(bossAllRows(dataset).map { ($0.npcId, $0) }, uniquingKeysWith: { first, _ in first })
    for item in parityCases {
        guard let row = rowsByNpcId[item.npcId] else {
            throw CheckFailure(description: "首领数据：对照表找不到 npcId \(item.npcId)（\(item.title)）")
        }
        let mutation = item.mutationId.flatMap { dataset.mutation($0) }
        if let mutationId = item.mutationId {
            try bossExpect(mutation != nil, "对照表 \(item.title)：查不到变异档位明细", counter: &count)
            try bossExpect(
                row.mutationPool.contains(mutationId),
                "对照表 \(item.title)：该行的 mutationPool 里应有这个档位",
                counter: &count
            )
        }
        let got = row.stats(for: item.players, mode: item.mode, mutation: mutation)
        try bossExpect(got.hp == item.hp, "对照表 \(item.title)：血量应为 \(item.hp)，实际 \(got.hp)", counter: &count)
        if let expected = item.attackRate {
            try bossExpectClose(
                got.attackRate, expected, "对照表 \(item.title)：攻击力倍率",
                tolerance: 0.000001, counter: &count
            )
        }
        if let expected = item.runeRate {
            try bossExpectClose(
                got.runeRate, expected, "对照表 \(item.title)：卢恩倍率",
                tolerance: 0.000001, counter: &count
            )
        }
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
        parityCases.contains { $0.mode == .depth5 } && parityCases.contains { $0.mutationId != nil },
        "对照表必须覆盖「深度」与「变异个体」两条新路径",
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

    // 12c. 名字：主标题 / 参考译名副标题 / 徽标 / 搜索索引
    //      用户的第一条抱怨是「有的首领只有英文名、有的翻译不对、还有未知敌人」。
    //      数据层已经把 14 条手工译名移出 nameZh，页面这边必须做到三件事：
    //      主标题只用游戏文本、参考译名带「非本作游戏文本」的说明、旧译名仍然搜得到。
    let troll = try cardForBoss("Troll@4600")
    try bossExpect(troll.nameZh.isEmpty, "Troll 的 nameZh 应已清空（游戏文本里查无此名）", counter: &count)
    try bossExpect(troll.displayName == "Troll", "nameZh 为空时主标题用英文名，不能用参考译名", counter: &count)
    try bossExpect(troll.fallbackSubtitle == "山妖", "参考译名应作副标题给出，实际 \(troll.fallbackSubtitle ?? "nil")", counter: &count)
    try bossExpect(troll.nameBadge == .englishOnly, "Troll 应挂「仅英文名」徽标", counter: &count)
    try bossExpect(
        index.cards(in: .field, query: "山妖").contains { $0.id == troll.id },
        "按旧译名「山妖」仍应能搜到 Troll（nameZhFallback 要进搜索索引）",
        counter: &count
    )
    let hippoGroup = try cardForBoss("Large Golden Hippopotamus@5010")
    try bossExpect(
        hippoGroup.fallbackSubtitle == "大型黄金河马",
        "大型黄金河马的参考译名应作副标题",
        counter: &count
    )
    try bossExpect(
        index.cards(in: .night, query: "河马").contains { $0.id == hippoGroup.id },
        "用户搜「河马」仍要能搜到它",
        counter: &count
    )
    try bossExpect(
        index.cards.first(where: { $0.nameZh == "黄金河马" }) != nil,
        "拿到游戏文本的那一组仍叫「黄金河马」",
        counter: &count
    )
    // nameZh 非空的组不给副标题：主标题已经是游戏文本，再挂参考译名只会让人以为有两个名字。
    try bossExpect(
        index.cards.allSatisfy { $0.nameZh.isEmpty || $0.fallbackSubtitle == nil },
        "有简中名的组不应再显示参考译名副标题",
        counter: &count
    )
    let fallbackCards = index.cards.filter { $0.fallbackSubtitle != nil }
    try bossExpect(
        fallbackCards.count == 14,
        "当前数据里应有 14 组带参考译名，实际 \(fallbackCards.count)",
        counter: &count
    )
    try bossExpect(
        fallbackCards.allSatisfy { !$0.nameZhFallbackNote.isEmpty },
        "每条参考译名都应带来源说明（不是本作游戏内文本）",
        counter: &count
    )
    // 近似匹配：游戏文本不是逐字命中，页面要挂「近似匹配」并给出 nameNote / 证据。
    let approxCards = index.cards.filter(\.showsApproxBadge)
    try bossExpect(approxCards.count == 7, "当前数据里应有 7 组近似匹配，实际 \(approxCards.count)", counter: &count)
    let wormface = try cardForBoss("Large Wormface@4580")
    try bossExpect(wormface.nameApprox && wormface.showsApproxBadge, "蚯蚓脸应挂「近似匹配」徽标", counter: &count)
    try bossExpect(wormface.nameEvidence != nil, "近似匹配的组应带上命中的游戏文本词条", counter: &count)
    try bossExpect(
        index.cards(in: .nightlord).allSatisfy { !$0.showsApproxBadge },
        "夜王的名字来自菜单参数，不挂近似匹配徽标",
        counter: &count
    )
    // 让出同名词条的 4 组要能说清楚「为什么没有中文名」
    let rejected = index.cards.filter { $0.nameZhRejected != nil }
    try bossExpect(rejected.count == 4, "应有 4 组记录了被挡下的候选词条，实际 \(rejected.count)", counter: &count)
    try bossExpect(
        rejected.allSatisfy { !$0.nameNote.isEmpty && $0.nameZh.isEmpty },
        "被挡下候选词条的组应 nameZh 为空且带说明",
        counter: &count
    )
    // 社区资料认出身份的组：新增「社区资料」徽标。但「社区认出了它是谁」与
    // 「本作游戏文本里没有它的简中名」是两件事，两个徽标要同时挂 —— 只挂「社区资料」
    // 就把用户问题 ① 最关心的那条信息（没有简中名）从页面上抹掉了。
    let greyoll = try cardForBoss("Elder Dragon Greyoll@4504")
    try bossExpect(greyoll.nameSource == "community", "桂奥尔的名字来源应是 community", counter: &count)
    try bossExpect(
        greyoll.nameBadges == [.noGameName, .community],
        "nameZh 为空 + community：应同时挂「无游戏内名称」与「社区资料」，实际 \(greyoll.nameBadges)",
        counter: &count
    )
    try bossExpect(
        greyoll.nameBadge == .noGameName && greyoll.nameBadge?.text == "无游戏内名称",
        "第一条徽标仍是「名字缺不缺」那一层，与 Windows 端四档同序",
        counter: &count
    )
    try bossExpect(greyoll.displayName == "Elder Dragon Greyoll", "社区认出的英文名应当主标题", counter: &count)
    try bossExpect(!greyoll.nameSourceUrl.isEmpty, "社区来源应带出处链接", counter: &count)
    try bossExpect(
        index.cards.filter { $0.nameSource.hasPrefix("community") && $0.nameZh.isEmpty }
            .allSatisfy { $0.nameBadges == [.noGameName, .community] },
        "3 组 community 且无简中名的卡片都应同时挂两个徽标",
        counter: &count
    )
    let digger = try cardForBoss("Stonedigger Troll@4603")
    try bossExpect(
        digger.nameSource == "community-npcname" && digger.nameEvidence != nil,
        "挖石山妖的身份来自社区资料，简中名却是货真价实的游戏文本（NpcName）",
        counter: &count
    )
    try bossExpect(
        digger.nameBadges.isEmpty,
        "nameZh 已是游戏文本时不挂「社区资料」—— 挂了会和展开区同时显示的「游戏文本依据」自相矛盾，实际 \(digger.nameBadges)",
        counter: &count
    )
    try bossExpect(digger.displayName == "挖石山妖", "社区认身份 + 游戏文本取名的组应显示简中名", counter: &count)
    try bossExpect(
        BossNameBadge.community.text == "社区资料"
            && BossNameBadge.englishOnly.text == "仅英文名"
            && BossNameBadge.noGameName.text == "无游戏内名称"
            && BossNameBadge.manual.text == "名称手工补录"
            && BossNameBadge.inferred.text == "名称按 ID 推断",
        "名字徽标沿用原有四档并新增 community",
        counter: &count
    )
    // 「未知敌人 cXXXX」只在三个名字都没有时兜底
    let noNameJSON = """
    {"nightBosses": [{"nameEn": "", "chrIds": [4242], "tier": "field",
      "variants": [{"npcId": 1, "labelZh": "甲"}]}]}
    """
    let noName = try BossDataIndex(data: Data(noNameJSON.utf8))
    try bossExpect(
        noName.cards.first?.displayName == "未知敌人 c4242",
        "三个名字都没有时才兜底成「未知敌人 cXXXX」，实际 \(noName.cards.first?.displayName ?? "nil")",
        counter: &count
    )

    // 12d. 隐藏实体：默认不显示，开关打开后才出现
    let hidden = index.hiddenCards
    try bossExpect(hidden.count == 4, "应有 4 组被判定为非首领实体，实际 \(hidden.count)", counter: &count)
    try bossExpect(
        Set(hidden.map(\.id)) == [
            "boss-Centipede Grub@7711", "boss-Lord of Blood Spear@4801",
            "boss-Unknown Enemy (c7931)@7931", "boss-Unknown Enemy (c7932)@7932",
        ],
        "隐藏的应是百足幼虫 / 蒙格的长枪 / 两组无法确认的实体，实际 \(hidden.map(\.id).sorted())",
        counter: &count
    )
    try bossExpect(
        index.cards(in: .night).count == 46 && index.cards(in: .night, includeHidden: true).count == 50,
        "守夜分组默认 46 张、打开开关 50 张，实际 \(index.cards(in: .night).count) / \(index.cards(in: .night, includeHidden: true).count)",
        counter: &count
    )
    try bossExpect(
        index.cards(in: .field).count == 72 && index.cards(in: .field, includeHidden: true).count == 72,
        "4 组隐藏实体都在守夜档，野外分组不受开关影响",
        counter: &count
    )
    try bossExpect(
        index.cards(in: .night, query: "").count == 46
            && index.cards(in: .night, query: "", includeHidden: true).count == 50,
        "带搜索的那条路径也要认隐藏开关",
        counter: &count
    )
    // 「Centipede」会命中可见的百足恶魔，所以这里用只属于幼虫那一组的词。
    try bossExpect(
        index.cards(in: .night, query: "Centipede Grub").isEmpty
            && index.cards(in: .night, query: "Centipede Grub", includeHidden: true).count == 1,
        "隐藏的组默认连搜都搜不出来，打开开关才出现",
        counter: &count
    )
    try bossExpect(
        (index.hiddenSummary ?? "").contains(BossRowText.hiddenToggleTitle),
        "底部说明要告诉用户去哪打开隐藏实体",
        counter: &count
    )
    // 收录统计说的是「数据集收录了多少」，不跟着开关变
    try bossExpect(
        index.inventorySummary == "夜王 18 · 守夜 50 · 野外 72（含 6 组两边都出现） · 数值行 394",
        "收录统计应含隐藏实体，实际「\(index.inventorySummary)」",
        counter: &count
    )
    // noReward 只作小字，不影响显示：Storm King / 蚯蚓脸 / 巨大骸骨躯干不掉奖励但仍在列表里
    let visibleNoReward = index.cards.filter { $0.noReward && !$0.hidden }
    try bossExpect(
        Set(visibleNoReward.map(\.id)) == [
            "boss-Storm King@7910", "boss-Dreg Wormface@7660", "boss-Giant Skeleton Torso@4960",
        ],
        "不掉奖励但仍应显示的是这 3 组，实际 \(visibleNoReward.map(\.id).sorted())",
        counter: &count
    )
    // 组级「该组不掉任何奖励」小字与名字来历共用展开区的同一块，noReward 必须进那块的
    // 外层显示条件。巨大骸骨躯干五个名字字段全空 + noReward = true，正好落在这个空档上：
    // 少了这一条，它展开后永远看不到那行小字。
    let torso = try cardForBoss("Giant Skeleton Torso@4960")
    try bossExpect(
        torso.noReward && !torso.hidden && torso.nameNote.isEmpty && torso.nameZhFallbackNote.isEmpty
            && torso.nameEvidence == nil && torso.nameZhRejected == nil && torso.nameSourceUrl.isEmpty,
        "巨大骸骨躯干应是「不掉奖励 + 五个名字字段全空」的那组边界数据",
        counter: &count
    )
    try bossExpect(
        torso.showsNameNotes,
        "只有 noReward 时展开区那块也必须显示，否则「该组不掉任何奖励」小字永远看不到",
        counter: &count
    )
    try bossExpect(
        index.cards.allSatisfy { card in
            card.group == .nightlord || !card.noReward || card.showsNameNotes
        },
        "每一组 noReward 的守夜 / 野外卡片都应显示展开区的小字块",
        counter: &count
    )
    try bossExpect(
        index.cards(in: .nightlord).allSatisfy { !$0.showsNameNotes },
        "夜王的名字来自菜单参数，不显示名字来历块",
        counter: &count
    )

    // 12e. 代表行：分组过滤 → isMain → 排掉无奖励行 → 排掉演出行 → 血量最高
    //      顺序很要紧。18 张夜王卡片的候选池（收敛到 isMain 之后）**整池都是 noReward**，
    //      要是把「排掉无奖励行」放在 isMain 前面，11 张夜王卡的代表行都会被换成
    //      「格拉狄乌斯（常驻缩放 ×3.54）」75000000 这种参数标签行。所以 isMain 先、
    //      noReward 后，且整池都无奖励时不排。这一版顺序就是两端的正式规则，
    //      规则正文写在 BossCard.rows(in:) 的文档注释里。
    //
    //      下面的 representativeCases 是**两端共享的对照表**（同一张也要写进
    //      windows/tests/bosses.test.mjs）：ParityCase 那张表全部按 npcId 直接取行，
    //      断言的是换算公式，钉不住「折叠态会选中哪一行」；任一端把过滤顺序改回
    //      任务书的字面顺序，这里必须立刻红。
    struct RepresentativeCase {
        let title: String
        let cardId: String
        let group: BossCard.Group
        let npcId: Int
    }
    let representativeCases: [RepresentativeCase] = [
        // 夜王：整池都 noReward，先排 noReward 会退化成 75000000 参数标签行
        .init(title: "格拉狄乌斯 · 夜王", cardId: "nightlord-0", group: .nightlord, npcId: 75000020),
        .init(title: "玛利斯 · 夜王", cardId: "nightlord-3", group: .nightlord, npcId: 75400020),
        .init(title: "卡莉果 · 夜王", cardId: "nightlord-6", group: .nightlord, npcId: 49000010),
        // 同一张卡的两个分组给两条不同的代表行；河马的野外行整池都 noReward，不排
        .init(title: "大型黄金河马 · 守夜", cardId: "boss-Large Golden Hippopotamus@5010", group: .night, npcId: 50100010),
        .init(title: "大型黄金河马 · 野外", cardId: "boss-Large Golden Hippopotamus@5010", group: .field, npcId: 50100000),
        // noReward 那一层：血量最高的 35600900 是 Paramdex 模板行，让位给打得到的 35600110
        .init(title: "神皮使徒 · 守夜", cardId: "boss-Godskin Apostle@3560", group: .night, npcId: 35600110),
        .init(title: "神皮使徒 · 野外", cardId: "boss-Godskin Apostle@3560", group: .field, npcId: 35600020),
        // isStagingRow 那一层：这两行都 noReward = false，只能靠标签认出来
        .init(title: "鲜血贵族 · 野外", cardId: "boss-Sanguine Noble@3550", group: .field, npcId: 35500030),
        .init(title: "巨鸦群 · 野外", cardId: "boss-Giant Crow@4560", group: .field, npcId: 45600000),
    ]
    for item in representativeCases {
        guard let card = index.cards.first(where: { $0.id == item.cardId }) else {
            throw CheckFailure(description: "首领数据：代表行对照表找不到卡片 \(item.cardId)（\(item.title)）")
        }
        let actual = card.representativeRow(in: item.group)?.npcId
        try bossExpect(
            actual == item.npcId,
            "代表行对照表：\(item.title) 应取 npcId \(item.npcId)，实际 \(actual.map(String.init) ?? "nil")",
            counter: &count
        )
    }
    try bossExpect(
        index.cards(in: .nightlord).allSatisfy { card in
            card.rows(in: .nightlord).allSatisfy(\.noReward)
        },
        "夜王收敛到 isMain 之后候选池整池都是 noReward —— 正因如此不能先排 noReward",
        counter: &count
    )
    try bossExpect(
        gladiusCard.representativeRow(in: .nightlord)?.npcId == 75000020,
        "格拉狄乌斯的代表行仍应是「远征首领」75000020，而不是同血量的参数标签行 75000000",
        counter: &count
    )
    try bossExpect(
        index.cards(in: .nightlord, includeHidden: true).allSatisfy { card in
            card.representativeRow(in: .nightlord)?.isMain == true
        },
        "每张夜王卡片的代表行都应是 isMain 行",
        counter: &count
    )
    // 守夜 / 野外没有 isMain，这一层就由 noReward 兜底：模板行 / 登场演出 / 血条实体不再抢代表位
    try bossExpect(
        index.cards.allSatisfy { card in
            card.groups.allSatisfy { group in
                let pool = card.rows(in: group)
                guard let primary = card.representativeRow(in: group) else { return false }
                return !primary.noReward || pool.allSatisfy(\.noReward)
            }
        },
        "代表行只有在整池都无奖励时才允许是 noReward 行",
        counter: &count
    )
    try bossExpect(
        apostle.representativeRow(in: .field)?.npcId == 35600020,
        "神皮使徒野外分组的代表行不受影响，仍是封印监牢 35600020",
        counter: &count
    )
    let sanguine = try cardForBoss("Sanguine Noble@3550")
    try bossExpect(
        sanguine.representativeRow(in: .field)?.npcId == 35500030,
        "鲜血贵族排掉无奖励的 35500015 之后，35500020 / 35500030 / 35500040 三行同为 920 血，"
            + "代表位应给「基准」35500030，而不是「鲜血君王 · 登场演出」35500020，实际 "
            + (sanguine.representativeRow(in: .field).map { String($0.npcId) } ?? "nil"),
        counter: &count
    )
    let chariot = try cardForBoss("Flame Chariot@4460")
    try bossExpect(
        chariot.representativeRow(in: .field)?.npcId == 44600010,
        "火焰战车的代表行应从「营地 · 血条实体」换成真正的「营地」行",
        counter: &count
    )
    // isStagingRow 这一层：演出行不一定 noReward，noReward 那层拦不住
    let crow = try cardForBoss("Giant Crow@4560")
    try bossExpect(
        crow.representativeRow(in: .field)?.npcId == 45600000,
        "巨鸦群的代表行应是「基准」45600000，而不是血量更高（2117）但只是挂血条的「血条实体」45601020，实际 "
            + (crow.representativeRow(in: .field).map { String($0.npcId) } ?? "nil"),
        counter: &count
    )
    try bossExpect(
        index.cards.allSatisfy { card in
            card.groups.allSatisfy { group in
                let pool = card.rows(in: group)
                guard let primary = card.representativeRow(in: group) else { return false }
                return !primary.isStagingRow || pool.allSatisfy(\.isStagingRow)
            }
        },
        "代表行只有在整池都是演出行时才允许是登场演出 / 血条实体 / 教程行",
        counter: &count
    )

    // 12f. 变异个体（游戏内简中正式叫法；社区俗称「红化」）
    try bossExpect(dataset.mutations.count == 10, "变异档位应有 10 档，实际 \(dataset.mutations.count)", counter: &count)
    try bossExpect(
        dataset.mutations.allSatisfy { key, value in key == value.id },
        "mutations 的 id 应回填为 key",
        counter: &count
    )
    try bossExpect(
        bossAllRows(dataset).allSatisfy { row in
            row.mutationPool.allSatisfy { dataset.mutation($0) != nil }
        },
        "每个 mutationPool 里的档位都应查得到明细",
        counter: &count
    )
    guard let mutation = dataset.mutation(113240) else {
        throw CheckFailure(description: "首领数据：找不到变异档位 #113240")
    }
    try bossExpect(mutation.nameZh == "变异个体", "变异档位的中文名应用游戏文本「变异个体」", counter: &count)
    try bossExpectClose(mutation.hp, 1.15, "#113240 血量倍率", tolerance: 0.0001, counter: &count)
    try bossExpectClose(mutation.attackRate, 1.15, "#113240 攻击力倍率", tolerance: 0.0001, counter: &count)
    try bossExpectClose(mutation.runeRate, 1.35, "#113240 卢恩倍率", tolerance: 0.0001, counter: &count)
    try bossExpect(
        mutation.summary == "血量 ×1.15 · 攻击 ×1.15 · 卢恩 ×1.35",
        "变异档位摘要文案，实际 \(mutation.summary)",
        counter: &count
    )
    // 变异倍率是在其它缩放之上再乘一层（spCategory 203，与深度 0 / 人数 140 都不同）
    guard let mutableRow = bossAllRows(dataset).first(where: { $0.npcId == 35600020 }),
          let apostleMutation = dataset.mutation(113140)
    else {
        throw CheckFailure(description: "首领数据：找不到神皮使徒封印监牢行或它的变异档位")
    }
    for players in BossPartySize.allCases {
        for mode in BossNightMode.allCases {
            let plain = mutableRow.stats(for: players, mode: mode)
            let mutated = mutableRow.stats(for: players, mode: mode, mutation: apostleMutation)
            try bossExpect(
                mutated.hp == Int((Double(mutableRow.baseline(mode: mode).hp)
                                   * mutableRow.tier(for: players).hp * apostleMutation.hp).rounded()),
                "变异血量应在人数缩放之上再乘一层",
                counter: &count
            )
            try bossExpectClose(
                mutated.attackRate, plain.attackRate * apostleMutation.attackRate,
                "变异攻击力应在当前数值上再乘一层", tolerance: 0.000001, counter: &count
            )
            // 变异只改血量 / 攻击 / 卢恩，不碰削韧与异常
            try bossExpect(
                mutated.effectivePoise == plain.effectivePoise
                    && mutated.ailmentDamageRate == plain.ailmentDamageRate
                    && mutated.ailmentBuildupRate == plain.ailmentBuildupRate,
                "变异不应改动削韧与异常相关倍率",
                counter: &count
            )
        }
    }
    try bossExpect(
        mutableRow.canMutate && dataset.mutations(for: mutableRow).map(\.id) == [113140],
        "神皮使徒封印监牢行的可选变异档位应是 #113140",
        counter: &count
    )
    // 两端最容易对不上的一点：mutationPool / mutations 的 key 是 **SpEffectSetParam 行号**
    // （113xxx），不是数值档位 SpEffect 行号（72xx）。下拉框按前者选，倍率来自后者。
    try bossExpect(
        dataset.mutations.keys.allSatisfy { $0 >= 113000 && $0 < 114000 },
        "mutations 的 key 应是 SpEffectSetParam 行号（113xxx）",
        counter: &count
    )
    try bossExpect(
        Set(dataset.mutations.values.compactMap(\.statSpEffectId)) == [7220, 7230, 7240, 7241],
        "数值档位 SpEffect 应是 7220 / 7230 / 7240 / 7241，实际 "
            + "\(Set(dataset.mutations.values.compactMap(\.statSpEffectId)).sorted())",
        counter: &count
    )
    try bossExpect(
        apostleMutation.statSpEffectId == 7240,
        "对照表用的 #113140 对应数值档位 7240（×1.15 血 ×1.15 伤害 ×1.35 卢恩）",
        counter: &count
    )
    try bossExpect(
        dataset.mutations.values.allSatisfy { $0.hp >= 1 && $0.attackRate >= 1 && $0.runeRate >= 1 },
        "变异档位的三个倍率都不应小于 1",
        counter: &count
    )
    let mutableRows = bossAllRows(dataset).filter(\.canMutate)
    try bossExpect(mutableRows.count == 327, "应有 327 条数值行能变异，实际 \(mutableRows.count)", counter: &count)
    try bossExpect(
        bossAllRows(dataset).allSatisfy { row in
            row.canMutate || dataset.mutations(for: row).isEmpty
        },
        "不能变异的行不应给出变异档位",
        counter: &count
    )
    // 变异只数表：这是「有几只」，不是概率；野外首领与封印监牢首领深度 1 全是 0
    try bossExpect(
        dataset.mutationCategories.count == 46,
        "变异只数表应有 46 行，实际 \(dataset.mutationCategories.count)",
        counter: &count
    )
    try bossExpect(
        dataset.mutationCategories.filter { $0.categoryId == 120 }.allSatisfy { $0.count(atDepth: 1) == 0 },
        "深度 1 不会遇到变异的野外首领",
        counter: &count
    )
    try bossExpect(
        dataset.mutationCategories.filter { $0.categoryId == 160 }.allSatisfy { $0.count(atDepth: 1) == 0 },
        "深度 1 也不会遇到变异的封印监牢首领",
        counter: &count
    )
    try bossExpect(
        dataset.mutationCategories.filter { $0.categoryId == 120 }.contains { $0.count(atDepth: 2) > 0 },
        "深度 2 起野外首领才会有变异个体",
        counter: &count
    )
    try bossExpect(
        dataset.orderedMutationCategories.count == dataset.mutationCategories.count,
        "排序后的变异只数表不应丢行",
        counter: &count
    )
    try bossExpect(
        BossRowText.mutationCountNote.contains("不是百分比概率"),
        "变异只数的说明必须点明它不是概率",
        counter: &count
    )

    // 12g. 多人：攻击力列与「不是简单乘倍」的结论
    let attackTiers = index.scalingGroups.filter { ($0.duo?.raisesAttack ?? false) || ($0.trio?.raisesAttack ?? false) }
    try bossExpect(
        attackTiers.map(\.id).sorted() == [7744, 7753, 7754, 7758],
        "多人会让敌人攻击力上浮的应是 7744 / 7753 / 7754 / 7758，实际 \(attackTiers.map(\.id).sorted())",
        counter: &count
    )
    try bossExpect(
        attackTiers.allSatisfy { $0.duo?.attackRate == 1.1 && $0.trio?.attackRate == 1.2 },
        "这四档应是双人 ×1.1、三人 ×1.2",
        counter: &count
    )
    try bossExpect(
        dataset.scalingGroup(7767)?.duo?.attackRate == 1
            && dataset.scalingGroup(7767)?.trio?.attackRate == 1,
        "最终 Boss 档的多人攻击力不变",
        counter: &count
    )
    try bossExpect(
        index.scalingGroups.allSatisfy { ($0.duo?.staminaAttackRate ?? 1) == 1 && ($0.trio?.staminaAttackRate ?? 1) == 1 },
        "人数缩放行里对玩家耐力的削减倍率恒为 1",
        counter: &count
    )
    try bossExpect(BossRowText.attackRateText(1) == "不变", "攻击力 1 倍写「不变」", counter: &count)
    try bossExpect(BossRowText.attackRateText(1.1) == "×1.1", "攻击力 1.1 倍写「×1.1」", counter: &count)
    try bossExpect(BossRowText.attackRateText(1.2) == "×1.2", "攻击力 1.2 倍写「×1.2」", counter: &count)
    try bossExpect(
        BossRowText.multiplayerAttackBadge(1.1) == "多人攻击 ×1.1"
            && BossRowText.multiplayerAttackBadge(1.2) == "多人攻击 ×1.2",
        "血量旁的多人攻击徽标文案",
        counter: &count
    )
    try bossExpect(!BossScalingTier.identity.raisesAttack, "单人基准不算攻击力上浮", counter: &count)
    // 同一条守夜行：三人血量 ×2.48 之外，攻击力还要 ×1.2
    guard let nightRow = bossAllRows(dataset).first(where: { $0.scalingId == 7753 }) else {
        throw CheckFailure(description: "首领数据：找不到 7753 档的数值行")
    }
    try bossExpectClose(
        nightRow.attackRate(for: .trio) / nightRow.attackRate(for: .solo), 1.2,
        "7753 档三人攻击力应比单人高 20%", tolerance: 0.000001, counter: &count
    )
    try bossExpect(
        nightRow.stats(for: .solo).attackRate == nightRow.attackRateBase,
        "单人攻击力倍率就是常驻基准",
        counter: &count
    )
    let audit = dataset.notes?.multiplayerScalingAudit ?? []
    try bossExpect(audit.count == 9, "notes.multiplayerScalingAudit 应有 9 条，实际 \(audit.count)", counter: &count)
    try bossExpect(
        (dataset.notes?.deepOfNightAudit.count ?? 0) == 11,
        "notes.deepOfNightAudit 应有 11 条",
        counter: &count
    )
    try bossExpect(
        BossRowText.multiplayerAuditSummary.contains("不是简单乘倍"),
        "底部结论必须直说「不是简单乘倍」",
        counter: &count
    )
    try bossExpect(
        BossRowText.multiplayerAuditSummary.contains("上浮 10% / 20%"),
        "底部结论要写出攻击力上浮的幅度",
        counter: &count
    )
    try bossExpect(
        BossRowText.multiplayerAuditSummary.contains("防御、卢恩与掉落、异常触发阈值三项人数缩放一概不碰"),
        "底部结论要写清楚哪些字段人数缩放不碰",
        counter: &count
    )
    // 常驻攻击缩放：上一版只看四项数值会把「只改攻击力」的常驻档位当成中性行
    let attackOnlyEffects = dataset.permanentScaling.values.filter { $0.attackRate != 1 }
    try bossExpect(
        attackOnlyEffects.count == 47,
        "应有 47 个常驻档位带攻击力倍率，实际 \(attackOnlyEffects.count)",
        counter: &count
    )
    try bossExpect(
        dataset.permanentEffect(16178).map { !$0.attackRates.isUniform } == true,
        "16178 是「只加物理」的常驻档位，五属性攻击力倍率不同",
        counter: &count
    )

    // 12h. 深夜 / 深度 / 变异个体的游戏文本与深度概览
    let text = dataset.deepOfNightText
    try bossExpect(text.deepOfNightTitle == "深夜", "深夜的游戏文本词，实际 \(text.deepOfNightTitle)", counter: &count)
    try bossExpect(text.depthTitle == "深度", "深度的游戏文本词，实际 \(text.depthTitle)", counter: &count)
    try bossExpect(text.mutationTitle == "变异个体", "变异个体的游戏文本词（不是社区叫法「红化」）", counter: &count)
    try bossExpect(text.deepOfNight.textId == 131150 && text.depth.textId == 131011, "游戏文本 ID", counter: &count)
    try bossExpect(!text.description.zh.isEmpty, "深夜说明文本应存在（页面顶部要展示）", counter: &count)
    try bossExpect(dataset.title(for: .normal) == "常规", "常规模式标题", counter: &count)
    try bossExpect(
        dataset.title(for: .depth3) == "深夜 · 深度 3",
        "深度模式标题应由游戏文本拼出，实际 \(dataset.title(for: .depth3))",
        counter: &count
    )
    try bossExpect(BossNightMode.normal.builtinTitle == "常规", "数据缺失时的兜底标题", counter: &count)
    try bossExpect(BossNightMode.depth5.builtinTitle == "深夜 · 深度 5", "兜底标题也要带深度", counter: &count)
    try bossExpect(BossNightMode.allCases.count == 6, "模式选择应是常规 + 5 个深度", counter: &count)
    try bossExpect(
        BossNightMode.allCases.map(\.depth) == [nil, 1, 2, 3, 4, 5],
        "模式与深度的对应关系",
        counter: &count
    )
    try bossExpect(!BossNightMode.normal.isDeepOfNight && BossNightMode.depth1.isDeepOfNight, "深夜判定", counter: &count)
    try bossExpect(
        dataset.deepOfNightDepths.count == 5 && dataset.orderedDepthInfos.map(\.rankId) == [1, 2, 3, 4, 5],
        "深度概览应有 5 档并按深度升序",
        counter: &count
    )
    guard let depth5 = dataset.depthInfo(5), let depth1 = dataset.depthInfo(1) else {
        throw CheckFailure(description: "首领数据：缺少深度 1 / 5 的全局控制行")
    }
    try bossExpect(depth1.title == "深度 1" && depth5.title == "深度 5", "深度标签", counter: &count)
    try bossExpectClose(depth1.cursedUncommonRate, 25, "诅咒遗物（罕见）率全深度不变", tolerance: 0.0001, counter: &count)
    try bossExpectClose(depth5.cursedRareRate, 40, "诅咒遗物（稀有）率全深度不变", tolerance: 0.0001, counter: &count)
    try bossExpectClose(depth1.mapChallengeWeight.none, 100, "深度 1 的地图挑战权重全在「无」上", tolerance: 0.0001, counter: &count)
    try bossExpectClose(depth5.mapChallengeWeight.map, 10, "深度 5 的地图挑战权重", tolerance: 0.0001, counter: &count)
    try bossExpect(depth5.cataclysmWeight[2] == 95, "深度 5 的天变数量权重", counter: &count)
    // 深度档位表（ChaosMatchingCorrectParam）
    try bossExpect(
        dataset.deepOfNightTiers.count == 22,
        "深度档位表应有 22 档，实际 \(dataset.deepOfNightTiers.count)",
        counter: &count
    )
    guard let finalTier = dataset.depthTier(7760) else {
        throw CheckFailure(description: "首领数据：找不到最终 Boss 的深度档位 7760")
    }
    try bossExpect(finalTier.tier == "Tier 3f", "7760 应是 Tier 3f", counter: &count)
    try bossExpectClose(finalTier.depths[5]?.hp, 1.718, "Tier 3f 深度 5 血量倍率", tolerance: 0.0001, counter: &count)
    try bossExpectClose(finalTier.depths[5]?.attackRate, 2.947, "Tier 3f 深度 5 攻击力倍率", tolerance: 0.0001, counter: &count)
    try bossExpect(
        bossAllRows(dataset).allSatisfy { row in
            row.chaosCorrectId == nil || dataset.depthTier(row.chaosCorrectId ?? 0) != nil
        },
        "每条行的 chaosCorrectId 都应能查到深度档位",
        counter: &count
    )
    let mismatched = bossAllRows(dataset).filter { $0.chaosCorrectId != nil && $0.chaosCorrectId != $0.scalingId }
    try bossExpect(
        mismatched.count == 14,
        "深度档位与人数档位不是同一行的应有 14 条，实际 \(mismatched.count)",
        counter: &count
    )
    // 夜王各深度出现权重：深度 1 打不到永夜之王 / 救世旗手
    try bossExpect(
        dataset.nightlords.allSatisfy(\.hasDepthChanceWeights),
        "每位夜王都应有各深度出现权重",
        counter: &count
    )
    try bossExpect(
        dataset.nightlords.filter { $0.variantKey != "normal" }.allSatisfy { $0.depthChanceWeights[1] == 0 },
        "永夜之王与救世旗手在深度 1 的权重应为 0",
        counter: &count
    )
    try bossExpect(
        dataset.nightlords.filter { $0.variantKey == "normal" }.allSatisfy { ($0.depthChanceWeights[1] ?? 0) > 0 },
        "本体夜王在深度 1 都打得到",
        counter: &count
    )
    try bossExpect(
        gladius.orderedDepthChanceWeights.map(\.weight) == [1000, 800, 650, 500, 500],
        "格拉狄乌斯的各深度出现权重",
        counter: &count
    )
    try bossExpect(
        BossRowText.depthWeightText(0) == "该深度不会出现" && BossRowText.depthWeightText(500) == "权重 500",
        "出现权重的文案",
        counter: &count
    )
    try bossExpect(
        BossRowText.hiddenToggleTitle == "显示隐藏实体"
            && BossRowText.nameFallbackBadge == "参考译名 · 非本作游戏文本"
            && BossRowText.nameApproxBadge == "近似匹配"
            && BossRowText.noDepthStatsText == "该行无深夜数值"
            && BossRowText.mutationPickerTitle == "按变异个体计算"
            && BossRowText.mutationPickerNone == "无",
        "schemaVersion 3 新增的几串文案两端必须逐字一致",
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
    try bossExpect(BossRowText.deepExclusiveBadge == "深夜专属修正", "深夜专属修正徽标文案", counter: &count)
    try bossExpect(
        BossDeepCoverage.all.badgeText == BossRowText.deepRowBadge,
        "卡头深夜徽标与行内徽标同一套说法",
        counter: &count
    )
    try bossExpect(
        BossDeepCoverage.some.badgeText == "部分行有深夜数值",
        "部分行有深夜数值的卡头徽标（v3 数据里不会出现，留着以防后续有行没有 depthStats）",
        counter: &count
    )
    try bossExpect(
        BossDeepCoverage.all.exclusiveBadgeText == BossRowText.deepExclusiveBadge
            && BossDeepCoverage.some.exclusiveBadgeText == "部分行有深夜专属修正"
            && BossDeepCoverage.none.exclusiveBadgeText == nil,
        "深夜专属修正的三档卡头徽标文案",
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
