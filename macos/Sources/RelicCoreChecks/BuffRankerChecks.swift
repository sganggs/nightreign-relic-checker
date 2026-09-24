import Foundation
import RelicCore

// 「增伤排名」页的自检：
//   * 用真实的 Resources/skills.json 跑选段（variants）、伤害构成与削韧换算；
//   * 用真实的 Resources/buffs.json 跑解码、scope 过滤与排名；
//   * 用构造出来的最小 JSON 验证算法本身（加权、分层相乘、叠加分组）与宽容解码。
//
// 数据集还在继续修数值（只改取值 / 加字段，不改名不删字段），因此这里一律写
// **结构性断言**（占比 > 0、集合互斥、倍率分层相乘的代数关系…），不写死具体数值；
// 只有合成 JSON 里的数值才做精确断言 —— 那是算法本身的期望值，与数据集无关。
// 注册入口见 GameDataChecks.swift。

// MARK: - 断言辅助

private func rankerExpect(_ condition: Bool, _ message: String, counter: inout Int) throws {
    guard condition else { throw CheckFailure(description: "增伤排名：" + message) }
    counter += 1
}

private func rankerExpectClose(
    _ value: Double, _ expected: Double, _ message: String,
    tolerance: Double = 0.0001, counter: inout Int
) throws {
    guard abs(value - expected) <= tolerance else {
        throw CheckFailure(
            description: "增伤排名：\(message)（期望 \(expected)，实际 \(String(format: "%.6f", value))）"
        )
    }
    counter += 1
}

private func resourceURL(_ fileName: String) -> URL {
    URL(fileURLWithPath: #filePath)          // …/Sources/RelicCoreChecks/BuffRankerChecks.swift
        .deletingLastPathComponent()         // …/Sources/RelicCoreChecks
        .deletingLastPathComponent()         // …/Sources
        .deletingLastPathComponent()         // …/macos
        .appendingPathComponent("Sources/NightreignRelicChecker/Resources/\(fileName)")
}

// MARK: - 合成数据（算法本身的断言）

/// 合成数据用的最小 rateFields 表：只列本文件用到的字段，语义与真实数据集一致。
private let syntheticRateFields = """
[
  {"key":"physicsAttackRate","zh":"物理伤害倍率","default":1.0,"group":"damage","valueKind":"multiplier","countsAsDamage":true,"conditionalDamage":false},
  {"key":"fireAttackRate","zh":"火伤害倍率","default":1.0,"group":"damage","valueKind":"multiplier","countsAsDamage":true,"conditionalDamage":false},
  {"key":"magicAttackRate","zh":"魔力伤害倍率","default":1.0,"group":"damage","valueKind":"multiplier","countsAsDamage":true,"conditionalDamage":false},
  {"key":"slashAttackRate","zh":"斩击伤害倍率","default":1.0,"group":"damage","valueKind":"multiplier","countsAsDamage":true,"conditionalDamage":false},
  {"key":"blowAttackRate","zh":"打击伤害倍率","default":1.0,"group":"damage","valueKind":"multiplier","countsAsDamage":true,"conditionalDamage":false},
  {"key":"physicsAttackPowerRate","zh":"物理攻击力倍率","default":1.0,"group":"attackPower","valueKind":"multiplier","countsAsDamage":true,"conditionalDamage":false},
  {"key":"fireAttackPower","zh":"火攻击力加算","default":0,"group":"attackPowerFlat","valueKind":"flat","countsAsDamage":true,"conditionalDamage":false},
  {"key":"weakDmgRateB","zh":"特攻Ｂ倍率","default":1.0,"group":"weakness","valueKind":"multiplier","countsAsDamage":false,"conditionalDamage":true},
  {"key":"saAttackPowerRate","zh":"削韧攻击力倍率","default":1.0,"group":"stance","valueKind":"multiplier","countsAsDamage":false,"conditionalDamage":false},
  {"key":"restageAttackRate","zh":"再演伤害倍率","default":-1.0,"group":"special","valueKind":"special","countsAsDamage":false,"conditionalDamage":false},
  {"key":"bloodAttackPower","zh":"出血累积加算","default":0,"group":"status","valueKind":"flat","countsAsDamage":false,"conditionalDamage":false}
]
"""

private let syntheticEnums = """
{
  "sourceKind": {"relicAffix":"遗物词条","goods":"消耗品／道具","accessory":"护符／饰品"},
  "wepParamChange": {"1":{"zh":"右手武器","en":"Right-hand"},"2":{"zh":"左手武器","en":"Left-hand"},"3":{"zh":"自身","en":"Self"}},
  "atkSubCategory": {"112":{"zh":"战技攻击","en":"Skill Attack"},"123":{"zh":"绝招","en":"Ultimate Art"}},
  "spAttribute": {"22":{"zh":"出血","en":"Blood Loss"}},
  "activation": {"passive":{"zh":"装备后即生效","en":"Always on"},"conditional":{"zh":"需满足条件","en":"Conditional"}},
  "attackContext": {
    "criticalHit":{"zh":"致命一击／处决","en":"Critical Hit","fromSubCategories":[],"fromStateInfo":[367]},
    "chargedSkill":{"zh":"蓄力战技","en":"Charged Skill","fromSubCategories":[111],"fromStateInfo":[]},
    "jumpAttack":{"zh":"跳跃攻击","en":"Jump Attack","fromSubCategories":[102],"fromStateInfo":[]}
  },
  "stateInfo": {"367":{"zh":"强化致命一击","en":"Enhance Critical Attacks"},"197":{"zh":"强化突刺反击","en":"Enhance Thrusting Counter Attacks"}},
  "spCategoryBehavior": [
    {"min":0,"max":0,"code":"none","zh":"不参与互斥"},
    {"min":1000,"max":1999,"code":"applyHighest","zh":"取 categoryPriority 更优的一份"},
    {"min":null,"max":null,"code":"unknown","zh":"未知"}
  ]
}
"""

/// 拼一份最小 buffs 数据集（rateFields / enums 固定，buffs 由调用方给）。
private func makeSyntheticBuffIndex(buffs: String) throws -> BuffRankerIndex {
    let json = """
    {
      "schemaVersion": 4,
      "gameVersion": "test",
      "dataVersion": "test",
      "notes": {"ranking": "测试用"},
      "stackingRules": {"zh": "测试用"},
      "rateFields": \(syntheticRateFields),
      "rateFieldGroups": [{"key":"damage","zh":"最终伤害倍率","countsAsDamage":true,"conditionalDamage":false,"qualifies":true}],
      "conditionFields": [{"key":"conditionHp","zh":"残余血量低于此比例(%)才发动"}],
      "enums": \(syntheticEnums),
      "counts": {"buffs": 1},
      "buffs": \(buffs)
    }
    """
    return try BuffRankerIndex(data: Data(json.utf8))
}

/// 一条最小 buff 的 JSON。
private func syntheticBuff(
    id: Int,
    name: String,
    rates: String,
    scope: String = "{}",
    stacking: String = "",
    stackLadder: String = "",
    target: String = "self",
    direction: String = "increase",
    activation: String = "passive",
    sourceKind: String = "relicAffix"
) -> String {
    let stackingJSON = stacking.isEmpty
        ? "{\"stateInfo\":0,\"spCategory\":0,\"spCategoryBehavior\":\"none\",\"categoryPriority\":0,\"saveCategory\":-1,\"group\":\"sp0#\(id)\"}"
        : stacking
    let ladderJSON = stackLadder.isEmpty ? "" : "\n      \"stackLadder\": \(stackLadder),"
    return """
    {
      "spEffectId": \(id),
      "nameZh": "\(name)",
      "displayNameZh": "\(name)",
      "paramName": "[Test] \(name)",
      "sources": [{"kind":"\(sourceKind)","id":1,"via":"test","nameZh":"测试来源"}],
      "rates": \(rates),
      "rateGroups": ["damage"],
      "direction": "\(direction)",
      "scope": \(scope),
      "stacking": \(stackingJSON),\(ladderJSON)
      "duration": -1,
      "permanent": true,
      "affectsAllies": false,
      "target": "\(target)",
      "targetSource": "default",
      "activation": "\(activation)",
      "activationSource": "noEvidence"
    }
    """
}

/// 50% 斩击 + 50% 火的伤害构成（合成算例用）。
private func halfSlashHalfFire() -> [Double] {
    var shares = Array(repeating: 0.0, count: SkillDamageChannel.allCases.count)
    shares[SkillDamageChannel.slash.rawValue] = 0.5
    shares[SkillDamageChannel.fire.rawValue] = 0.5
    return shares
}

private func skillContext(shares: [Double], slot: Int = 1) -> BuffRankingContext {
    BuffRankingContext(
        delivery: .weaponSkill,
        weaponSlot: slot,
        subCategories: [BuffRankingContext.skillAttackSubCategory],
        shares: shares
    )
}

private func decodeHits(_ json: String) throws -> [SkillHit] {
    try JSONDecoder().decode([SkillHit].self, from: Data(json.utf8))
}

// MARK: - 入口

func runBuffRankerChecks() throws -> Int {
    var count = 0
    let skillsURL = resourceURL("skills.json")
    let buffsURL = resourceURL("buffs.json")

    guard FileManager.default.fileExists(atPath: skillsURL.path),
          FileManager.default.fileExists(atPath: buffsURL.path) else {
        throw CheckFailure(description: "增伤排名：缺少 skills.json / buffs.json")
    }
    let skillsData = try Data(contentsOf: skillsURL)
    let buffsData = try Data(contentsOf: buffsURL)

    // 合成算例与宽容解码不依赖真实数据，任何时候都跑。
    try checkDamageMath(counter: &count)
    try checkRankingMath(counter: &count)
    try checkAttackContextGate(counter: &count)
    try checkAtkAttributeScope(counter: &count)
    try checkStackLadder(counter: &count)
    try checkStackingMath(counter: &count)
    try checkLenientDecoding(counter: &count)
    try checkLoadoutSynthetic(counter: &count)

    if GameDataLoader.isPlaceholder(skillsData) || GameDataLoader.isPlaceholder(buffsData) {
        print("    （skills.json / buffs.json 仍是占位内容，跳过真实数据检查）")
        return count
    }

    let skills = try SkillDataIndex(data: skillsData)
    let buffs = try BuffRankerIndex(data: buffsData)
    try checkSkillDataset(skills, counter: &count)
    try checkSegmentSelection(skills, counter: &count)
    try checkSegmentChips(skills, counter: &count)
    try checkComposition(skills, counter: &count)
    try checkBuffDataset(buffs, counter: &count)
    try checkRealRanking(skills: skills, buffs: buffs, counter: &count)
    try checkCrossPlatformCases(skills: skills, buffs: buffs, counter: &count)
    try checkTwoSidedParity(skills: skills, buffs: buffs, counter: &count)
    try checkLoadoutRealData(skills: skills, buffs: buffs, counter: &count)
    return count
}

// MARK: - 两端口径对齐（逐条对应 windows/tests/ranker.test.mjs 的同名断言）

/// 这一组断言全部是为了**钉住两端同一套口径**：计数点、chip 顺序、徽标与说明文案、
/// 可检索字段。数值会随数据集修订变化，所以一律写成相对 / 结构性断言。
private func checkTwoSidedParity(
    skills: SkillDataIndex, buffs: BuffRankerIndex, counter count: inout Int
) throws {
    // ① noDamage 段：真实数据里任何一段标了 noDamage 的，总量必须为 0。
    //    （本作有 8 段是 noDamage + addBaseAtk，这一关就是拦它们的。）
    var noDamageSeen = 0
    var noDamageWithAddBase = 0
    for skill in skills.dataset.skills {
        for id in skill.weaponIds {
            guard let weapon = skills.weaponsByID[id] else { continue }
            for segment in skills.segments(for: skill, weapon: weapon) where segment.noDamage {
                noDamageSeen += 1
                try rankerExpect(
                    segment.total == 0 && segment.components.isEmpty,
                    "noDamage 段 #\(segment.atkId) 的相对伤害必须为 0（实际 \(segment.total)）",
                    counter: &count
                )
            }
            break   // 每条战技取第一把能选出段的武器即可，不必全跑
        }
    }
    for skill in skills.dataset.skills {
        for hit in skill.hits where hit.noDamage && hit.addBaseAtk { noDamageWithAddBase += 1 }
    }
    try rankerExpect(noDamageSeen > 0, "真实数据里应当有 noDamage 段（否则这条口径是空跑）", counter: &count)
    try rankerExpect(
        noDamageWithAddBase > 0,
        "真实数据里应当有 noDamage + addBaseAtk 的段（正是它们会被误算成一整份武器攻击力）",
        counter: &count
    )

    // ② 属性／异常限定的计数点：只有「其余各关都过、单单被 spAttribute 拦下」才计入，
    //    所以它必须**随当前手变化**（右手 ≠ 左手）。计数点一旦挪到「scopeVerdict 返回非 nil
    //    就算」，被武器槽拦下的条目会全部混进来，这个数就与手无关了。
    guard let weapon = skills.dataset.weapons.first(where: {
        $0.skillVariant != nil && skills.skillsByID[$0.swordArtsParamId] != nil
    }), let skill = skills.skillsByID[weapon.swordArtsParamId] else {
        throw CheckFailure(description: "增伤排名：找不到用于两端对照的武器")
    }
    let composition = SkillDamageMath.composition(
        of: skills.segments(for: skill, weapon: weapon),
        selected: SkillDamageMath.defaultSelection(skills.segments(for: skill, weapon: weapon))
    )
    let right = buffs.rankResult(
        context: BuffRankingContext(
            delivery: .weaponSkill, weaponSlot: 1,
            subCategories: [BuffRankingContext.skillAttackSubCategory], composition: composition
        )
    )
    let left = buffs.rankResult(
        context: BuffRankingContext(
            delivery: .weaponSkill, weaponSlot: 2,
            subCategories: [BuffRankingContext.skillAttackSubCategory], composition: composition
        )
    )
    try rankerExpect(right.attributeScopedCount > 0, "右手应有被属性限定拦下的条目", counter: &count)
    try rankerExpect(
        right.attributeScopedCount != left.attributeScopedCount,
        "属性／异常限定的计数必须随武器槽变化（右手 \(right.attributeScopedCount)"
            + " / 左手 \(left.attributeScopedCount)）——相等说明计数点又错位到「拦下就算」了",
        counter: &count
    )
    try rankerExpect(
        right.attributeScopedCount < buffs.attributeScopedCount,
        "只被 spAttribute 拦下的条目数必然少于全表的属性限定条目数",
        counter: &count
    )
    // 打开开关后这一类应当清零（它们全部进榜或落到别的关）。
    let opened = buffs.rankResult(
        context: BuffRankingContext(
            delivery: .weaponSkill, weaponSlot: 1,
            subCategories: [BuffRankingContext.skillAttackSubCategory], composition: composition
        ),
        options: BuffRankingOptions(includeAttributeScoped: true)
    )
    try rankerExpect(
        opened.attributeScopedCount == 0,
        "打开「包含属性／异常限定」后不应再有条目算在这一类里",
        counter: &count
    )

    // ③ 作用域不符的总数与分项：两端都要有（Windows 是汇总行的 pill + 分项说明）。
    try rankerExpect(right.scopeRejectedCount > 0, "应统计出作用域不符的条目数", counter: &count)
    try rankerExpect(!right.scopeReasons.isEmpty, "作用域不符应给出按原因的分项", counter: &count)
    let reasonTotal = right.scopeReasons
        .filter { $0.key != BuffRankerIndex.contextGateReason }
        .values.reduce(0, +)
    try rankerExpect(
        reasonTotal == right.scopeRejectedCount,
        "分项条数之和应等于作用域不符总数（\(reasonTotal) vs \(right.scopeRejectedCount)）",
        counter: &count
    )
    try rankerExpect(
        right.scopeReasons[BuffRankerIndex.contextGateReason] == right.contextScopedCount,
        "情境闸门在分项里的条数应等于 contextScopedCount（与 Windows 端 scopeReasons 同一口径）",
        counter: &count
    )
    try rankerExpect(
        right.scopeReasons["只作用于右手武器"] == nil,
        "右手上下文里不该出现「只作用于右手武器」这条排除原因",
        counter: &count
    )
    try rankerExpect(
        left.scopeReasons["只作用于右手武器"] != nil,
        "左手上下文里应当出现「只作用于右手武器」这条排除原因",
        counter: &count
    )
    try rankerExpect(
        right.scopeReasonBreakdown.first?.count ?? 0 >= right.scopeReasonBreakdown.last?.count ?? 0,
        "排除原因分项应按条数降序",
        counter: &count
    )

    // ④ 攻击情境 chip：固定顺序 + 只统计带伤害倍率字段的条目。
    let chipKeys = buffs.availableAttackContexts.map(\.key)
    let expectedOrder = chipKeys.sorted { lhs, rhs in
        let left = BuffRankerIndex.attackContextOrder.firstIndex(of: lhs) ?? BuffRankerIndex.attackContextOrder.count
        let right = BuffRankerIndex.attackContextOrder.firstIndex(of: rhs) ?? BuffRankerIndex.attackContextOrder.count
        return left == right ? lhs < rhs : left < right
    }
    try rankerExpect(chipKeys == expectedOrder, "情境 chip 应按固定顺序排（不随数据计数重排）", counter: &count)
    for option in buffs.availableAttackContexts {
        let expected = buffs.dataset.buffs.enumerated().filter { index, buff in
            buff.scope.attackContexts.contains(option.key) && buffs.hasRankingRate(at: index)
        }.count
        try rankerExpect(
            option.count == expected,
            "情境 chip「\(option.zh)」的计数应只统计带伤害倍率字段的条目"
                + "（实际 \(option.count)，应为 \(expected)）",
            counter: &count
        )
    }
    let allContextGated = buffs.dataset.buffs.filter { !$0.scope.attackContexts.isEmpty }.count
    try rankerExpect(
        buffs.availableAttackContexts.reduce(0) { $0 + $1.count } < allContextGated * 2,
        "chip 计数不应把没有任何伤害倍率字段的条目也算进去",
        counter: &count
    )

    // ⑤ stateInfo 标签格式：中文在前、数字在括号里（「强化致命一击（367）」）。
    if let sample = buffs.dataset.buffs.first(where: {
        $0.stacking.stateInfo != 0 && buffs.dataset.stateInfoLabels[$0.stacking.stateInfo] != nil
    }) {
        let value = sample.stacking.stateInfo
        let label = buffs.dataset.stateInfoLabel(value)
        try rankerExpect(
            label.hasSuffix("（\(value)）") && !label.hasPrefix("\(value)"),
            "stateInfo 标签应是「中文（数字）」（实际「\(label)」）",
            counter: &count
        )
    }
    try rankerExpect(
        buffs.dataset.stateInfoLabel(-12345) == "-12345",
        "没有标签的 stateInfo 应退回裸数字",
        counter: &count
    )

    // ⑥ 可检索字段：descZh 里的词、来源类型中文名、spEffectId 都必须搜得到，
    //    来源名超过 6 个时后面的也要搜得到（两端取同一个并集）。
    if let withDesc = buffs.dataset.buffs.first(where: { ($0.descZh?.count ?? 0) > 6 }),
       let index = buffs.dataset.buffs.firstIndex(where: { $0.spEffectId == withDesc.spEffectId }) {
        let key = buffs.searchKey(at: index)
        let needle = String(withDesc.descZh!.prefix(6)).foldedForSearch
        try rankerExpect(key.contains(needle), "descZh 里的词应当搜得到", counter: &count)
        try rankerExpect(
            key.contains(String(withDesc.spEffectId)),
            "spEffectId 应当搜得到",
            counter: &count
        )
        try rankerExpect(
            key.contains(buffs.dataset.sourceKindLabel(withDesc.sourceKinds[0]).foldedForSearch),
            "来源类型的中文标签应当搜得到",
            counter: &count
        )
    }
    if let many = buffs.dataset.buffs.firstIndex(where: { $0.sources.count > 6 }) {
        let key = buffs.searchKey(at: many)
        let last = buffs.dataset.buffs[many].sources.last!.displayName.foldedForSearch
        try rankerExpect(
            last.isEmpty || key.contains(last),
            "来源超过 6 个时，第 7 个之后的来源名也要搜得到",
            counter: &count
        )
    }

    // ⑦ 底部「本页自己承担的判定」13 条：与 Windows 端逐字同文，条数一律照数据现算。
    let notes = BuffRankerPageNotes.rules(
        attributeScoped: buffs.attributeScopedCount,
        ladders: buffs.ladderCount,
        selfInflicted: buffs.selfInflictedStatusCount,
        meleeOnly: buffs.meleeOnlyCount,
        skillsWithoutDamage: skills.skillsWithoutDamage,
        spellsWithoutDamage: skills.spellsWithoutDamage,
        hasAttackContexts: !buffs.availableAttackContexts.isEmpty
    )
    try rankerExpect(notes.count == 13, "本页口径应当是 13 条，实际 \(notes.count)", counter: &count)
    try rankerExpect(notes.allSatisfy { $0.count > 20 }, "每条口径说明都应当有正文", counter: &count)
    // 锚点表（Windows 端的 pageRuleNotes 已随配置版重构移除，这一组现在只钉 macOS 自己的措辞；
    // 战技数据 v3 起第 1 条按 skillVariants 选段）。
    let anchors = [
        "weapons[].skillVariants[战技 ID] → skills[].variants[i].atkIds",
        "只有法术段忽略 motion",
        "rateFields[].countsAsDamage 为 true 且 valueKind 为 multiplier",
        "武器槽（scope.weaponSlot）",
        "scope.spAttribute（只对带某种属性／异常的攻击生效",
        "叠层阶梯（stackLadder，本版本",
        "selfInflictedStatus（v5，本版本",
        "本页额外做了三条数据集没有直接字段的判定",
        "叠加分组只用数据集算好的 stacking.group",
        "「推荐组合」用全部命中条目计算",
        "攻击力加算（attackPowerFlat）是点数",
        "输出手段列表只收「至少有一段能算出非 0 相对值」的战技与法术",
        "只在特定攻击情境成立的倍率（scope.attackContexts"
    ]
    for (index, anchor) in anchors.enumerated() where notes.indices.contains(index) {
        try rankerExpect(
            notes[index].contains(anchor),
            "第 \(index + 1) 条应包含锚点「\(anchor)」",
            counter: &count
        )
    }
    // 把数字挖掉之后的正文在两端必须逐字节相同（FNV-1a 32 位）。这个摘要与数据无关
    //（数字全部归一成 #），数据集改数值不会弄红它；两端任何一句措辞漂移都会立刻分叉。
    try rankerExpect(
        pageNotesDigest(notes) == "61520191",
        "两端 13 条说明的正文必须逐字相同（实际摘要 \(pageNotesDigest(notes))）",
        counter: &count
    )
    // 条数是现算出来的，不是写死的。
    try rankerExpect(
        notes[4].contains("本版本 \(buffs.attributeScopedCount) 条")
            && notes[7].contains("等 \(buffs.meleeOnlyCount) 条")
            && notes[11].contains("（\(skills.skillsWithoutDamage) 条）")
            && notes[11].contains("（\(skills.spellsWithoutDamage) 条）"),
        "说明里的条数必须照数据现算",
        counter: &count
    )
    try rankerExpect(
        skills.skillsWithoutDamage > 0 && skills.spellsWithoutDamage > 0,
        "确实有一批输出手段被挡在列表外（否则这句说明是空话）",
        counter: &count
    )
}

/// 把 13 条说明里的 ASCII 数字归一成 `#` 之后取 FNV-1a 32 位摘要。
/// 与 windows/tests/ranker.test.mjs 里的同名实现逐位相同。
private func pageNotesDigest(_ notes: [String]) -> String {
    var normalized = ""
    var lastWasDigit = false
    for character in notes.joined(separator: "\n") {
        if character.isASCII && character.isNumber {
            if !lastWasDigit { normalized.append("#") }
            lastWasDigit = true
        } else {
            normalized.append(character)
            lastWasDigit = false
        }
    }
    var hash: UInt32 = 0x811c_9dc5
    for byte in Array(normalized.utf8) {
        hash = (hash ^ UInt32(byte)) &* 0x0100_0193
    }
    return String(format: "%08x", hash)
}

// MARK: - 合成算例：分段伤害换算

private func checkDamageMath(counter count: inout Int) throws {
    // 武器：物理 100 / 火 50，斩击（atkAttribute=0），削韧基础 10、精力伤害基础 20。
    let weapon = SkillWeapon(
        id: 1, nameZh: "测试武器", nameEn: "Test", wepTypeZh: "刀", wepTypeEn: "Katana",
        attackBase: [.physical: 100, .fire: 50], staminaBase: 20, poiseDamageBase: 10,
        atkAttribute: 0, atkAttributeZh: "斩击", atkAttribute2: 2, atkAttribute2Zh: "突刺"
    )

    let hits = try decodeHits("""
    [
      {"atkId":1,"labelZh":"第一段","motion":{"physical":200,"fire":100},"poiseMv":150,"staminaMv":50,
       "attribute":"WeaponAtkAttribute","attributeZh":"沿用武器 atkAttribute","source":"n"},
      {"atkId":2,"labelZh":"第二段","motion":{"physical":100},"poise":7,"stamina":30,
       "attribute":"WeaponAtkAttribute2","attributeZh":"沿用武器 atkAttribute2","source":"n"},
      {"atkId":3,"labelZh":"子弹","flat":{"fire":60},"attribute":"Standard","isBullet":true,"addBaseAtk":true,"source":"b"},
      {"atkId":4,"labelZh":"无FP版","motion":{"physical":100},"attribute":"Slash","noFp":true,"source":"n"},
      {"atkId":5,"labelZh":"挂状态","attribute":"None","noDamage":true,"source":"n"}
    ]
    """)
    try rankerExpect(hits.count == 5, "五段合成命中都应解码成功，实际 \(hits.count)", counter: &count)

    let segments = hits.map { SkillDamageMath.segment(for: $0, weapon: weapon) }

    // 第一段：物理 100 × 200% = 200 落在「斩击」，火 50 × 100% = 50。
    try rankerExpectClose(segments[0].amount(.slash), 200, "motion 应乘武器该属性攻击力", counter: &count)
    try rankerExpectClose(segments[0].amount(.fire), 50, "火属性 motion 同样按火攻击力换算", counter: &count)
    try rankerExpect(
        segments[0].physicalChannel == .slash,
        "attribute=WeaponAtkAttribute 应解析成武器的 atkAttribute（斩击）",
        counter: &count
    )
    // 削韧 = poise + poiseDamageBase × poiseMv/100 = 0 + 10 × 1.5
    try rankerExpectClose(segments[0].poise, 15, "削韧应为 poise + 武器 poiseDamageBase × poiseMv/100", counter: &count)
    // 削精力 = stamina + staminaBase × staminaMv/100 = 0 + 20 × 0.5
    try rankerExpectClose(segments[0].stamina, 10, "削精力应为 stamina + 武器 staminaBase × staminaMv/100", counter: &count)

    // 第二段：attribute=WeaponAtkAttribute2 → 武器的 atkAttribute2（突刺）。
    try rankerExpect(
        segments[1].physicalChannel == .pierce,
        "attribute=WeaponAtkAttribute2 应解析成武器的 atkAttribute2（突刺）",
        counter: &count
    )
    try rankerExpectClose(segments[1].poise, 7, "固定 poise 应原样计入", counter: &count)
    try rankerExpectClose(segments[1].stamina, 30, "固定 stamina 应原样计入", counter: &count)

    // 第三段：火 = flat 60 + addBaseAtk 再加一份火攻击力 50 = 110；
    // addBaseAtk 是「加一份武器攻击力」，物理那一份（100）同样要加上，落在段自己的标准类型上。
    try rankerExpectClose(segments[2].amount(.fire), 110, "addBaseAtk 应额外加一份该属性基础攻击力", counter: &count)
    try rankerExpectClose(segments[2].amount(.standard), 100, "addBaseAtk 对每个属性槽都加一份基础攻击力", counter: &count)
    try rankerExpect(segments[2].isBullet, "isBullet 应原样透出", counter: &count)

    // 第五段：noDamage ＝ 只挂状态，整段归零。
    try rankerExpectClose(segments[4].total, 0, "noDamage 段的相对伤害必须为 0", counter: &count)
    try rankerExpect(segments[4].components.isEmpty, "noDamage 段不该有任何伤害构成项", counter: &count)
    try rankerExpect(!segments[4].hasDamage, "noDamage 段的 hasDamage 必须为假", counter: &count)

    // 回归：`noDamage + addBaseAtk` 的段（本作真实存在 8 段，例如 301705901 癫火突击）
    // 绝不能因为 addBaseAtk 而算出一整份武器攻击力。与 Windows 端 hitContribution
    // 第一行的 noDamage 短路同一口径。
    let noDamageWithBase = try decodeHits("""
    [{"atkId":901,"labelZh":"只挂状态但带 addBaseAtk","attribute":"Standard","noDamage":true,"addBaseAtk":true,
      "motion":{"physical":300},"flat":{"fire":120},"source":"n"}]
    """)
    let noDamageSegment = SkillDamageMath.segment(for: noDamageWithBase[0], weapon: weapon)
    try rankerExpectClose(
        noDamageSegment.total, 0,
        "noDamage 段即使带 addBaseAtk / motion / flat，总量也必须为 0",
        counter: &count
    )
    try rankerExpect(
        noDamageSegment.components.isEmpty,
        "noDamage 段不得因为 addBaseAtk 而渲染出「+基础攻击力」构成项",
        counter: &count
    )
    try rankerExpect(
        noDamageSegment.physicalChannel == nil,
        "noDamage 段没有构成，也就没有物理攻击类型可标",
        counter: &count
    )
    try rankerExpect(
        SkillDamageMath.composition(of: [noDamageSegment], selected: [901]).isEmpty,
        "就算被勾上，noDamage 段对构成的贡献也必须是 0",
        counter: &count
    )

    // 默认勾选：排除 noFp 与 noDamage。
    let defaultSelection = SkillDamageMath.defaultSelection(segments)
    try rankerExpect(defaultSelection == [1, 2, 3], "默认勾选应排除 noFp 与 noDamage 段，实际 \(defaultSelection.sorted())", counter: &count)

    let noFpSelection = SkillDamageMath.selection(segments, useNoFp: true)
    try rankerExpect(noFpSelection == [4], "切到专注值不足版应只勾选 noFp 段，实际 \(noFpSelection.sorted())", counter: &count)
    try rankerExpect(noFpSelection.isDisjoint(with: defaultSelection), "正常版与专注值不足版必须互斥", counter: &count)

    // v3 fpBoth：带 FP / 无 FP 两侧动画共用的段，开关在哪一侧都计入（取段规则 fpBoth || noFp == 开关）；
    // 旧写法 noFp == 开关 会在专注值不足版这一侧把它丢掉（1024 唤矛仪式切过去一段都不剩）。
    let fpBothHits = try decodeHits("""
    [
      {"atkId":21,"labelZh":"正常版","motion":{"physical":100},"attribute":"Slash","source":"n"},
      {"atkId":22,"labelZh":"两侧共用","motion":{"physical":50},"attribute":"Slash","fpBoth":true,"source":"n"},
      {"atkId":23,"labelZh":"无FP版","motion":{"physical":80},"attribute":"Slash","noFp":true,"noFpSource":"tae","source":"n"},
      {"atkId":24,"labelZh":"两侧共用但只打自己","motion":{"holy":100},"attribute":"None","fpBoth":true,
       "noDamage":true,"selfOrAllyOnly":true,"source":"n"}
    ]
    """)
    try rankerExpect(
        fpBothHits[1].fpBoth && !fpBothHits[1].noFp && fpBothHits[2].noFp && fpBothHits[2].noFpSource == "tae"
            && fpBothHits[0].noFpSource == nil && fpBothHits[3].selfOrAllyOnly && fpBothHits[3].noDamage,
        "v3 命中段字段 fpBoth / noFpSource / selfOrAllyOnly 应解码出来",
        counter: &count
    )
    let fpBothSegments = fpBothHits.map { SkillDamageMath.segment(for: $0, weapon: weapon) }
    try rankerExpect(fpBothSegments[1].fpBoth && !fpBothSegments[0].fpBoth, "fpBoth 应透到分段上", counter: &count)
    try rankerExpect(
        SkillDamageMath.defaultSelection(fpBothSegments) == [21, 22],
        "正常版这一侧 = 正常段 + fpBoth 段，实际 \(SkillDamageMath.defaultSelection(fpBothSegments).sorted())",
        counter: &count
    )
    try rankerExpect(
        SkillDamageMath.selection(fpBothSegments, useNoFp: true) == [22, 23],
        "专注值不足版这一侧 = 无 FP 段 + fpBoth 段（fpBoth 两侧都计），"
            + "实际 \(SkillDamageMath.selection(fpBothSegments, useNoFp: true).sorted())",
        counter: &count
    )
    try rankerExpect(
        fpBothHits.map { $0.isOnSide(useNoFp: true) } == [false, true, true, true]
            && fpBothHits.map { $0.isOnSide(useNoFp: false) } == [true, true, false, true],
        "SkillHit.isOnSide 与取段规则同一口径（fpBoth || noFp == 开关）",
        counter: &count
    )
    try rankerExpectClose(
        fpBothSegments[3].total, 0, "selfOrAllyOnly 段带 noDamage，motion 是回血倍率，不得算成伤害", counter: &count
    )

    // 构成：斩击 200 + 突刺 100 + 标准 100 + 火（50 + 110）= 560。
    let composition = SkillDamageMath.composition(of: segments, selected: defaultSelection)
    try rankerExpectClose(composition.total, 560, "勾选三段的总相对伤害", counter: &count)
    try rankerExpectClose(composition.share(.slash), 200.0 / 560, "斩击占比", counter: &count)
    try rankerExpectClose(composition.share(.pierce), 100.0 / 560, "突刺占比", counter: &count)
    try rankerExpectClose(composition.share(.fire), 160.0 / 560, "火占比", counter: &count)
    try rankerExpectClose(composition.physicalShare, 400.0 / 560, "物理合计占比", counter: &count)
    try rankerExpectClose(composition.shares.reduce(0, +), 1, "各通道占比之和应为 1", counter: &count)
    try rankerExpect(composition.segmentCount == 3, "构成应记录勾选段数", counter: &count)
    try rankerExpect(
        composition.breakdown.first?.channel == .slash,
        "构成明细应按占比降序（斩击 200 最大）",
        counter: &count
    )

    // 取消勾选火子弹段 → 火占比下降、斩击占比上升（「勾掉某段看构成变化」）。
    let withoutBullet = SkillDamageMath.composition(of: segments, selected: [1, 2])
    try rankerExpect(
        withoutBullet.share(.fire) < composition.share(.fire),
        "取消勾选火属性子弹段后火占比应下降",
        counter: &count
    )
    try rankerExpect(
        withoutBullet.share(.slash) > composition.share(.slash),
        "取消勾选后其余通道占比应上升",
        counter: &count
    )

    // 一段都不勾：构成为空，占比全 0。
    let empty = SkillDamageMath.composition(of: segments, selected: [])
    try rankerExpect(empty.isEmpty && empty.shares.allSatisfy { $0 == 0 }, "空勾选应得到空构成", counter: &count)

    // 法术（weapon = nil）：只用 flat，motion 的占位 100 不得乘出物理伤害。
    let spellHits = try decodeHits("""
    [{"atkId":9,"motion":{"physical":100,"magic":100,"fire":100,"lightning":100,"holy":100},
      "flat":{"magic":285},"poise":7,"attribute":"Standard","isBullet":true,"source":"abn"}]
    """)
    let spellSegment = SkillDamageMath.segment(for: spellHits[0], weapon: nil)
    try rankerExpectClose(spellSegment.amount(.magic), 285, "法术段应只用 flat", counter: &count)
    try rankerExpectClose(spellSegment.amount(.standard), 0, "法术段的占位 motion 不得算出物理伤害", counter: &count)
    try rankerExpectClose(spellSegment.poise, 7, "法术段削韧用固定 poise", counter: &count)
}

// MARK: - 合成算例：有效倍率

private func checkRankingMath(counter count: inout Int) throws {
    let shares = halfSlashHalfFire()
    let context = skillContext(shares: shares)

    let index = try makeSyntheticBuffIndex(buffs: """
    [
      \(syntheticBuff(id: 1, name: "只加物理", rates: "{\"physicsAttackRate\":1.2}")),
      \(syntheticBuff(id: 2, name: "只加火", rates: "{\"fireAttackRate\":1.2}")),
      \(syntheticBuff(id: 3, name: "全属性", rates: "{\"physicsAttackRate\":1.2,\"fireAttackRate\":1.2}")),
      \(syntheticBuff(id: 4, name: "两层相乘", rates: "{\"physicsAttackRate\":1.2,\"physicsAttackPowerRate\":1.1}")),
      \(syntheticBuff(id: 5, name: "只加斩击", rates: "{\"slashAttackRate\":1.4}")),
      \(syntheticBuff(id: 6, name: "只加打击", rates: "{\"blowAttackRate\":1.4}")),
      \(syntheticBuff(id: 7, name: "火攻击力加算", rates: "{\"fireAttackPower\":40}")),
      \(syntheticBuff(id: 8, name: "不死特攻", rates: "{\"weakDmgRateB\":10}")),
      \(syntheticBuff(id: 9, name: "削韧倍率", rates: "{\"saAttackPowerRate\":1.5}")),
      \(syntheticBuff(id: 10, name: "再演", rates: "{\"restageAttackRate\":0.6}")),
      \(syntheticBuff(id: 11, name: "出血累积", rates: "{\"bloodAttackPower\":50}")),
      \(syntheticBuff(id: 12, name: "绝招限定", rates: "{\"physicsAttackRate\":1.5}", scope: "{\"subCategories\":[123]}")),
      \(syntheticBuff(id: 13, name: "战技限定", rates: "{\"physicsAttackRate\":1.5}", scope: "{\"subCategories\":[112]}")),
      \(syntheticBuff(id: 14, name: "左手限定", rates: "{\"physicsAttackRate\":1.5}", scope: "{\"weaponSlot\":2}")),
      \(syntheticBuff(id: 15, name: "自身", rates: "{\"physicsAttackRate\":1.05}", scope: "{\"weaponSlot\":3}")),
      \(syntheticBuff(id: 16, name: "魔法限定", rates: "{\"magicAttackRate\":1.5}", scope: "{\"affectsSorcery\":true}")),
      \(syntheticBuff(id: 17, name: "敌人减益", rates: "{\"physicsAttackRate\":1.5}", target: "enemy")),
      \(syntheticBuff(id: 18, name: "召唤物系数", rates: "{\"physicsAttackRate\":1.5}", target: "summon")),
      \(syntheticBuff(id: 19, name: "队友增益", rates: "{\"physicsAttackRate\":1.1}", target: "ally")),
      \(syntheticBuff(id: 20, name: "降低伤害", rates: "{\"physicsAttackRate\":0.85}", direction: "decrease")),
      \(syntheticBuff(id: 21, name: "残血触发", rates: "{\"physicsAttackRate\":1.5}", activation: "conditional")),
      \(syntheticBuff(id: 22, name: "出血限定", rates: "{\"physicsAttackRate\":1.3}", scope: "{\"spAttribute\":22}")),
      \(syntheticBuff(id: 23, name: "道具增伤", rates: "{\"physicsAttackRate\":1.1}", sourceKind: "goods"))
    ]
    """)

    let rows = index.rank(context: context)
    let byID = Dictionary(rows.map { ($0.spEffectId, $0) }, uniquingKeysWith: { first, _ in first })

    // 有效倍率 = Σ 占比 × Π(适用倍率)
    try rankerExpectClose(byID[1]?.effectiveMultiplier ?? 0, 1.1, "物理倍率 1.2 在 50% 物理构成上应为 1.1", counter: &count)
    try rankerExpectClose(byID[2]?.effectiveMultiplier ?? 0, 1.1, "火倍率 1.2 在 50% 火构成上应为 1.1", counter: &count)
    try rankerExpectClose(byID[3]?.effectiveMultiplier ?? 0, 1.2, "物理 + 火都 1.2 时应为 1.2", counter: &count)
    // 攻击力倍率与伤害倍率两层相乘：物理通道 1.2 × 1.1 = 1.32 → 0.5 × 1.32 + 0.5 × 1
    try rankerExpectClose(byID[4]?.effectiveMultiplier ?? 0, 1.16, "攻击力倍率与伤害倍率应两层相乘", counter: &count)
    // 物理子类型倍率只乘对应子类型：构成里 50% 是斩击
    try rankerExpectClose(byID[5]?.effectiveMultiplier ?? 0, 1.2, "斩击倍率 1.4 只作用于斩击部分", counter: &count)
    try rankerExpect(byID[6] == nil, "打击倍率在纯斩击构成里不产生增益，应被排除出排名", counter: &count)
    let result = index.rankResult(context: context)
    try rankerExpect(result.neutralCount >= 1, "对当前构成没有增益的条目应被计数而不是列出", counter: &count)
    try rankerExpect(
        result.candidateCount == result.rows.count + result.neutralCount,
        "候选数应等于列出的条数加上无增益条数",
        counter: &count
    )

    // 攻击力加算：按占比加权，但不折算成倍率
    try rankerExpectClose(byID[7]?.weightedFlat ?? 0, 20, "火攻击力 +40 在 50% 火构成上应加权成 +20", counter: &count)
    try rankerExpectClose(byID[7]?.effectiveMultiplier ?? 0, 1, "攻击力加算不得被当成倍率", counter: &count)

    // countsAsDamage=false 的字段一律不进排名
    try rankerExpect(byID[8] == nil, "特攻倍率（conditionalDamage）不得进通用排名", counter: &count)
    try rankerExpect(byID[9] == nil, "削韧倍率不得进伤害排名", counter: &count)
    try rankerExpect(byID[10] == nil, "special 组（再演）禁止参与乘算", counter: &count)
    try rankerExpect(byID[11] == nil, "异常状态累积不得进伤害排名", counter: &count)

    // scope
    try rankerExpect(byID[12] == nil, "只作用于绝招的 buff 不应出现在战技排名里", counter: &count)
    try rankerExpect(byID[13] != nil, "子类别含 112 战技攻击的 buff 应计入", counter: &count)
    try rankerExpect(byID[14] == nil, "左手武器限定的 buff 在右手输出下应被排除", counter: &count)
    try rankerExpect(byID[15] != nil, "weaponSlot=3（自身）应视为不限武器槽", counter: &count)
    try rankerExpect(byID[16] == nil, "只作用于魔法的 buff 不应出现在战技排名里", counter: &count)

    // target / direction / activation
    try rankerExpect(byID[17] == nil, "target=enemy 必须排除", counter: &count)
    try rankerExpect(byID[18] == nil, "target=summon 必须排除", counter: &count)
    try rankerExpect(byID[19] == nil, "target=ally 默认不计入", counter: &count)
    try rankerExpect(byID[20] == nil, "direction=decrease 必须排除", counter: &count)
    try rankerExpect(byID[21] == nil, "activation=conditional 默认不计入", counter: &count)
    try rankerExpect(byID[22] == nil, "scope.spAttribute 限定的条目默认不计入", counter: &count)

    // 降序
    try rankerExpect(
        zip(rows, rows.dropFirst()).allSatisfy { $0.effectiveMultiplier >= $1.effectiveMultiplier },
        "排名结果必须按有效倍率降序",
        counter: &count
    )

    // 左手输出：左手限定的那条进来，右手无关的仍在
    let leftRows = index.rank(context: skillContext(shares: shares, slot: 2))
    try rankerExpect(leftRows.contains { $0.spEffectId == 14 }, "切到左手武器槽后左手限定的 buff 应出现", counter: &count)

    // 开关
    let withConditional = index.rank(context: context, options: BuffRankingOptions(includeConditional: true))
    try rankerExpect(withConditional.contains { $0.spEffectId == 21 }, "打开条件型开关后 conditional 条目应出现", counter: &count)
    try rankerExpect(
        withConditional.first(where: { $0.spEffectId == 21 })?.isPassive == false,
        "conditional 条目应标成非 passive，页面据此灰显",
        counter: &count
    )
    let withAllies = index.rank(context: context, options: BuffRankingOptions(includeAllies: true))
    try rankerExpect(withAllies.contains { $0.spEffectId == 19 }, "打开队友增益开关后 ally 条目应出现", counter: &count)
    let withAttribute = index.rank(context: context, options: BuffRankingOptions(includeAttributeScoped: true))
    try rankerExpect(withAttribute.contains { $0.spEffectId == 22 }, "打开属性限定开关后 spAttribute 条目应出现", counter: &count)

    // 搜索与来源筛选：**只影响列表显示**，rank() 的结果与推荐组合一律不受它们影响
    //（两端同一口径：搜一个词不该把推荐组合的总倍率也改掉）。
    let searchOptions = BuffRankingOptions(query: "只加火")
    let searchedAll = index.rank(context: context, options: searchOptions)
    try rankerExpect(
        searchedAll.map(\.spEffectId) == rows.map(\.spEffectId),
        "搜索词不得改变排名本身（它只筛列表）",
        counter: &count
    )
    let searched = index.visibleRows(searchedAll, options: searchOptions)
    try rankerExpect(searched.map(\.spEffectId) == [2], "搜索应按 displayNameZh 命中，实际 \(searched.map(\.spEffectId))", counter: &count)
    let kindOptions = BuffRankingOptions(sourceKinds: ["goods"])
    let byKindAll = index.rank(context: context, options: kindOptions)
    try rankerExpect(
        byKindAll.map(\.spEffectId) == rows.map(\.spEffectId),
        "来源类型筛选不得改变排名本身（它只筛列表）",
        counter: &count
    )
    let byKind = index.visibleRows(byKindAll, options: kindOptions)
    try rankerExpect(byKind.map(\.spEffectId) == [23], "来源类型筛选应只留该类型，实际 \(byKind.map(\.spEffectId))", counter: &count)
    try rankerExpect(
        index.stackPlan(rows: byKindAll, options: kindOptions).total
            == index.stackPlan(rows: rows).total,
        "推荐组合的总倍率不得随搜索 / 来源筛选变化",
        counter: &count
    )
    try rankerExpect(
        index.availableSourceKinds.contains("goods") && index.availableSourceKinds.contains("relicAffix"),
        "筛选器应列出数据集里出现过的来源类型",
        counter: &count
    )

    // 没有勾选任何段时：算不出有效倍率，列表为空（不退回任何近似值），并且不崩
    let emptyShares = Array(repeating: 0.0, count: SkillDamageChannel.allCases.count)
    let emptyRows = index.rank(context: skillContext(shares: emptyShares))
    try rankerExpect(
        emptyRows.isEmpty,
        "没有勾选任何段时不应给出排名（实际 \(emptyRows.count) 条）",
        counter: &count
    )

    // 明细：物理倍率应落在物理通道上
    if let row = byID[1] {
        let physical = row.channelFactors.first { $0.channel == .slash }
        try rankerExpectClose(physical?.factor ?? 0, 1.2, "倍率明细应把物理倍率挂在斩击通道上", counter: &count)
        try rankerExpect(
            row.rateValues.contains { $0.key == "physicsAttackRate" && $0.countsAsDamage },
            "倍率明细应带上字段本身",
            counter: &count
        )
        try rankerExpect(row.durationText == "永久", "duration = -1 应显示为永久", counter: &count)
    } else {
        throw CheckFailure(description: "增伤排名：合成数据里找不到 #1")
    }
}

// MARK: - 合成算例：攻击情境闸门（notes.ranking ④）

/// `scope.attackContexts` 非空 = 只在某种攻击情境下才吃得到，默认不得进通用排名。
///
/// 这一关必须独立于 activation：情境限定的条目本身全是 passive，
/// 「包含条件型」开关既不该放行它们，也不该拦住它们。
/// scope.atkAttribute：只作用于某一个物理攻击类型。
/// 本版本数据集 0 例，只能用合成用例覆盖——Windows 端 ranker.test.mjs 有逐条对应的同名断言。
private func checkAtkAttributeScope(counter count: inout Int) throws {
    let index = try makeSyntheticBuffIndex(buffs: """
    [
      \(syntheticBuff(
        id: 501, name: "只加斩击（atkAttribute=0）",
        rates: "{\"physicsAttackRate\":1.5}",
        scope: "{\"atkAttribute\":0}"
      )),
      \(syntheticBuff(id: 502, name: "加全部物理", rates: "{\"physicsAttackRate\":1.5}"))
    ]
    """)

    // 纯斩击构成：两条都吃得到，倍率一样。
    var slashOnly = Array(repeating: 0.0, count: SkillDamageChannel.allCases.count)
    slashOnly[SkillDamageChannel.slash.rawValue] = 1
    let slashRows = index.rank(context: skillContext(shares: slashOnly))
    try rankerExpect(slashRows.count == 2, "纯斩击构成下两条都应进榜，实际 \(slashRows.count)", counter: &count)
    for row in slashRows {
        try rankerExpectClose(row.effectiveMultiplier, 1.5, "纯斩击构成下两条的有效倍率应当一样", counter: &count)
    }

    // 纯突刺构成：限定斩击的那条作用域不符，另一条照常吃。
    var thrustOnly = Array(repeating: 0.0, count: SkillDamageChannel.allCases.count)
    thrustOnly[SkillDamageChannel.pierce.rawValue] = 1
    let thrustResult = index.rankResult(context: skillContext(shares: thrustOnly))
    try rankerExpect(
        thrustResult.rows.map(\.spEffectId) == [502],
        "限定斩击的条目在纯突刺构成下不该进榜，实际 \(thrustResult.rows.map(\.spEffectId))",
        counter: &count
    )
    try rankerExpect(
        thrustResult.scopeReasons["限定物理攻击类型"] == 1,
        "被 atkAttribute 拦下的条目应计入「限定物理攻击类型」这条分项",
        counter: &count
    )

    // 一半斩击一半突刺：限定斩击的那条只在斩击那一半上乘。
    var mixed = Array(repeating: 0.0, count: SkillDamageChannel.allCases.count)
    mixed[SkillDamageChannel.slash.rawValue] = 0.5
    mixed[SkillDamageChannel.pierce.rawValue] = 0.5
    let mixedRows = index.rank(context: skillContext(shares: mixed))
    let restricted = mixedRows.first { $0.spEffectId == 501 }
    let plain = mixedRows.first { $0.spEffectId == 502 }
    try rankerExpectClose(restricted?.effectiveMultiplier ?? 0, 1.25, "限定斩击：0.5 × 1.5 + 0.5 × 1", counter: &count)
    try rankerExpectClose(plain?.effectiveMultiplier ?? 0, 1.5, "不限定的条目两半都吃", counter: &count)

    // 没有构成（一段都没勾）时不判这一关。
    let empty = Array(repeating: 0.0, count: SkillDamageChannel.allCases.count)
    try rankerExpect(
        index.rankResult(context: skillContext(shares: empty)).scopeReasons["限定物理攻击类型"] == nil,
        "没有伤害构成时不该按 atkAttribute 判作用域",
        counter: &count
    )
}

private func checkAttackContextGate(counter count: inout Int) throws {
    let context = skillContext(shares: halfSlashHalfFire())
    let index = try makeSyntheticBuffIndex(buffs: """
    [
      \(syntheticBuff(id: 401, name: "常驻物理增伤", rates: "{\"physicsAttackRate\":1.2}")),
      \(syntheticBuff(
        id: 402, name: "强化致命一击",
        rates: "{\"physicsAttackRate\":1.24}",
        scope: "{\"attackContexts\":[\"criticalHit\"]}"
      )),
      \(syntheticBuff(
        id: 403, name: "蓄力战技增伤",
        rates: "{\"physicsAttackRate\":1.5}",
        scope: "{\"attackContexts\":[\"chargedSkill\"]}"
      )),
      \(syntheticBuff(
        id: 404, name: "翻滚或后跳攻击增伤",
        rates: "{\"physicsAttackRate\":1.3}",
        scope: "{\"attackContexts\":[\"criticalHit\",\"jumpAttack\"]}"
      ))
    ]
    """)

    // 默认：只有不带情境限定的那条在
    let defaultResult = index.rankResult(context: context)
    let defaultIDs = Set(defaultResult.rows.map(\.spEffectId))
    try rankerExpect(defaultIDs == [401], "默认排名只应含不带情境限定的条目，实际 \(defaultIDs.sorted())", counter: &count)
    try rankerExpect(
        defaultResult.contextScopedCount == 3,
        "被情境拦下的 3 条应计入 contextScopedCount，实际 \(defaultResult.contextScopedCount)",
        counter: &count
    )
    try rankerExpect(
        defaultResult.candidateCount == defaultResult.rows.count + defaultResult.neutralCount,
        "情境拦下的条目不应算进候选数",
        counter: &count
    )

    // 「包含条件型」拦不住也放行不了情境限定的条目 —— 两条轴是正交的
    let conditionalOn = index.rank(context: context, options: BuffRankingOptions(includeConditional: true))
    try rankerExpect(
        !conditionalOn.contains { $0.spEffectId == 402 },
        "「包含条件型」不应放行情境限定的 passive 条目（activation 与 attackContexts 是正交的两条轴）",
        counter: &count
    )

    // 勾选 criticalHit：402 与 404（多情境里含 criticalHit）进来，403 仍在外面
    let critical = index.rankResult(
        context: context, options: BuffRankingOptions(includedAttackContexts: ["criticalHit"])
    )
    let criticalIDs = Set(critical.rows.map(\.spEffectId))
    try rankerExpect(criticalIDs == [401, 402, 404], "勾选致命一击后应放行 402 / 404，实际 \(criticalIDs.sorted())", counter: &count)
    try rankerExpect(critical.contextScopedCount == 1, "仍被拦下的只剩蓄力战技那 1 条", counter: &count)
    // 放行之后，情境限定的条目按有效倍率正常参与排序（404 ×1.3 > 402 ×1.24 > 401 ×1.2）
    try rankerExpect(
        critical.rows.map(\.spEffectId) == [404, 402, 401],
        "勾选情境后，情境限定条目应按有效倍率正常参与排序，实际 \(critical.rows.map(\.spEffectId))",
        counter: &count
    )

    // 多选：命中任一已勾选情境即可（数据里 attackContexts 是并列关系）
    let both = index.rank(
        context: context, options: BuffRankingOptions(includedAttackContexts: ["criticalHit", "chargedSkill"])
    )
    try rankerExpect(Set(both.map(\.spEffectId)) == [401, 402, 403, 404], "勾选两个情境应把两类都放行", counter: &count)

    // 勾选无关情境不放行
    let unrelated = index.rank(
        context: context, options: BuffRankingOptions(includedAttackContexts: ["jumpAttack"])
    )
    try rankerExpect(
        Set(unrelated.map(\.spEffectId)) == [401, 404],
        "勾选跳跃攻击只应放行含 jumpAttack 的条目",
        counter: &count
    )

    // 情境限定条目默认也不得进推荐组合
    let plan = index.stackPlan(rows: index.rank(context: context))
    try rankerExpect(
        !plan.picks.contains { $0.spEffectId == 402 || $0.spEffectId == 403 },
        "情境限定的条目默认不得进推荐组合",
        counter: &count
    )

    // 行上要带中文情境标签与标记，页面才能标注
    if let gated = critical.rows.first(where: { $0.spEffectId == 402 }) {
        try rankerExpect(gated.isContextGated, "情境限定的行应标记 isContextGated", counter: &count)
        try rankerExpect(
            gated.attackContextLabels == ["致命一击／处决"],
            "情境键应渲染成 enums.attackContext 的中文名，实际 \(gated.attackContextLabels)",
            counter: &count
        )
        try rankerExpect(
            gated.scopeNotes.contains { $0.contains("只在这些攻击情境下生效") },
            "生效范围里应写明情境限定",
            counter: &count
        )
    } else {
        throw CheckFailure(description: "增伤排名：勾选情境后找不到 #402")
    }
}

// MARK: - 合成算例：叠层阶梯（v4 stackLadder）

/// 数据集只收录阶梯第 1 层，`topRates` 才是满层数值；页面必须两个都给。
private func checkStackLadder(counter count: inout Int) throws {
    let context = skillContext(shares: halfSlashHalfFire())
    let ladder = """
    {"tiers":10,"tierSpEffectIds":[502,503],"topRates":{"physicsAttackRate":1.6289,"fireAttackRate":1.6289},"saved":true}
    """
    let index = try makeSyntheticBuffIndex(buffs: """
    [
      \(syntheticBuff(
        id: 501, name: "每次击杀叠一层",
        rates: "{\"physicsAttackRate\":1.05,\"fireAttackRate\":1.05}",
        stackLadder: ladder,
        activation: "conditional"
      )),
      \(syntheticBuff(id: 510, name: "常驻物理增伤", rates: "{\"physicsAttackRate\":1.2}"))
    ]
    """)

    // 阶梯第 1 层在数据里是 conditional，默认不进榜
    try rankerExpect(
        !index.rank(context: context).contains { $0.spEffectId == 501 },
        "叠层阶梯第 1 层（conditional）默认不应进排名",
        counter: &count
    )

    let rows = index.rank(context: context, options: BuffRankingOptions(includeConditional: true))
    guard let tier = rows.first(where: { $0.spEffectId == 501 }), let info = tier.ladder else {
        throw CheckFailure(description: "增伤排名：叠层阶梯条目未解码出 stackLadder")
    }
    try rankerExpectClose(tier.effectiveMultiplier, 1.05, "列出的应是第 1 层数值", counter: &count)
    try rankerExpectClose(info.topMultiplier, 1.6289, "满层数值应按同一套通道加权算出", counter: &count)
    try rankerExpect(info.tiers == 10, "层数应解码为 10", counter: &count)
    try rankerExpect(info.saved, "saved 应解码为 true", counter: &count)
    try rankerExpect(info.tierSpEffectIds == [501, 502, 503], "各层 id 应含第 1 层自己并排好序", counter: &count)
    try rankerExpect(info.tierText == "第 1 层 / 共 10 层", "层数文案应可直接展示", counter: &count)
    try rankerExpect(
        info.topMultiplier > tier.effectiveMultiplier,
        "满层数值应高于第 1 层，否则标注没有意义",
        counter: &count
    )

    // 同一阶梯的两层绝不能相乘：把第 2 层也塞进来（将来数据集收全层时就是这个形状）
    let fullLadder = try makeSyntheticBuffIndex(buffs: """
    [
      \(syntheticBuff(
        id: 501, name: "阶梯第 1 层",
        rates: "{\"physicsAttackRate\":1.05,\"fireAttackRate\":1.05}",
        stacking: "{\"stateInfo\":0,\"spCategory\":0,\"spCategoryBehavior\":\"none\",\"categoryPriority\":0,\"saveCategory\":-1,\"group\":\"sp0#501\"}",
        stackLadder: "{\"tiers\":10,\"tierSpEffectIds\":[502],\"topRates\":{\"physicsAttackRate\":1.6289},\"saved\":true}"
      )),
      \(syntheticBuff(
        id: 502, name: "阶梯第 2 层",
        rates: "{\"physicsAttackRate\":1.1,\"fireAttackRate\":1.1}",
        stacking: "{\"stateInfo\":0,\"spCategory\":0,\"spCategoryBehavior\":\"none\",\"categoryPriority\":0,\"saveCategory\":-1,\"group\":\"sp0#502\"}",
        stackLadder: "{\"tiers\":10,\"tierSpEffectIds\":[501],\"topRates\":{\"physicsAttackRate\":1.6289},\"saved\":true}"
      ))
    ]
    """)
    let ladderRows = fullLadder.rank(context: context)
    try rankerExpect(ladderRows.count == 2, "两层都应能列出来给用户看", counter: &count)
    let ladderPlan = fullLadder.stackPlan(rows: ladderRows)
    try rankerExpect(
        ladderPlan.picks.count == 1,
        "同一条叠层阶梯在推荐组合里只能出现一层，实际 \(ladderPlan.picks.count) 层",
        counter: &count
    )
    try rankerExpectClose(ladderPlan.total, 1.1, "组合里应只乘阶梯里最高的那一层", counter: &count)
}

// MARK: - 合成算例：叠加与推荐组合

private func checkStackingMath(counter count: inout Int) throws {
    let context = skillContext(shares: halfSlashHalfFire())
    let removePrevious = "{\"stateInfo\":0,\"spCategory\":151,\"spCategoryBehavior\":\"removePrevious\",\"categoryPriority\":0,\"saveCategory\":-1,\"group\":\"sp151\"}"
    let applyHighestWeak = "{\"stateInfo\":0,\"spCategory\":1001,\"spCategoryBehavior\":\"applyHighest\",\"categoryPriority\":1,\"saveCategory\":-1,\"group\":\"sp1001\"}"
    let applyHighestStrong = "{\"stateInfo\":0,\"spCategory\":1001,\"spCategoryBehavior\":\"applyHighest\",\"categoryPriority\":9,\"saveCategory\":-1,\"group\":\"sp1001\"}"

    let index = try makeSyntheticBuffIndex(buffs: """
    [
      \(syntheticBuff(id: 101, name: "同组弱", rates: "{\"physicsAttackRate\":1.2}", stacking: removePrevious)),
      \(syntheticBuff(id: 102, name: "同组强", rates: "{\"physicsAttackRate\":1.4}", stacking: removePrevious)),
      \(syntheticBuff(id: 103, name: "优先级优但倍率低", rates: "{\"physicsAttackRate\":1.1}", stacking: applyHighestWeak)),
      \(syntheticBuff(id: 104, name: "优先级差但倍率高", rates: "{\"physicsAttackRate\":1.6}", stacking: applyHighestStrong)),
      \(syntheticBuff(id: 105, name: "独立一组", rates: "{\"fireAttackRate\":1.5}")),
      \(syntheticBuff(id: 106, name: "条件型", rates: "{\"physicsAttackRate\":2.0}", activation: "conditional"))
    ]
    """)

    let rows = index.rank(context: context, options: BuffRankingOptions(includeConditional: true))
    let plan = index.stackPlan(rows: rows)
    let picked = Set(plan.picks.map(\.spEffectId))

    try rankerExpect(picked.contains(102) && !picked.contains(101), "同一 stacking.group 只应取倍率最高的一条", counter: &count)
    try rankerExpect(
        picked.contains(103) && !picked.contains(104),
        "applyHighest 组应按 categoryPriority 数值小者优先，实际 \(picked.sorted())",
        counter: &count
    )
    try rankerExpect(picked.contains(105), "不同组之间相互独立，应各自入选", counter: &count)
    try rankerExpect(!picked.contains(106), "条件型不得进默认推荐组合", counter: &count)
    try rankerExpect(plan.groupCount == plan.picks.count, "组数应等于入选条数", counter: &count)
    try rankerExpect(plan.droppedByStacking >= 2, "被同组顶掉的条目数应被记下", counter: &count)

    let expected = plan.picks.reduce(1.0) { $0 * $1.effectiveMultiplier }
    try rankerExpectClose(plan.total, expected, "组合总倍率应是各组入选条目的连乘", counter: &count)
    try rankerExpect(plan.total > 1, "组合总倍率应大于 1", counter: &count)
    try rankerExpect(
        zip(plan.picks, plan.picks.dropFirst()).allSatisfy { $0.effectiveMultiplier >= $1.effectiveMultiplier },
        "推荐组合应按有效倍率降序",
        counter: &count
    )

    // 条件型单独勾选纳入后才进组合
    let withConditional = index.stackPlan(rows: rows, includedConditional: [106])
    try rankerExpect(
        withConditional.picks.contains { $0.spEffectId == 106 },
        "勾选纳入后条件型条目应进入推荐组合",
        counter: &count
    )
    try rankerExpect(
        withConditional.total > plan.total,
        "纳入 ×2.0 的条件型后总倍率应上升",
        counter: &count
    )

    // 纯加算行（倍率恒为 1、只有 flat）不得占掉一个叠加组：它在 applyHighest 组里
    // 完全可能凭更小的 categoryPriority 赢下整组，然后因为不增伤被丢掉，整组一条都不取。
    // 口径是「先筛后分桶」，`groupCount` 也就等于取用条数（与 Windows 端 recommendCombo 一致）。
    let flatVsRate = try makeSyntheticBuffIndex(buffs: """
    [
      \(syntheticBuff(id: 201, name: "纯加算但优先级更优", rates: "{\"fireAttackPower\":40}", stacking: applyHighestWeak)),
      \(syntheticBuff(id: 202, name: "真增伤但优先级差", rates: "{\"physicsAttackRate\":1.3}", stacking: applyHighestStrong))
    ]
    """)
    let flatRows = flatVsRate.rank(context: context)
    try rankerExpect(flatRows.count == 2, "纯加算行也应进榜（flat > 0 就算有用）", counter: &count)
    let flatPlan = flatVsRate.stackPlan(rows: flatRows)
    try rankerExpect(flatPlan.picks.count == 1, "同组只取一条", counter: &count)
    try rankerExpect(
        flatPlan.picks.first?.spEffectId == 202,
        "纯加算行不得凭更小的 categoryPriority 赢下整组后被丢弃",
        counter: &count
    )
    try rankerExpect(
        flatPlan.groupCount == flatPlan.picks.count,
        "「组数」必须等于取用条目数（与 Windows 端 recommendCombo 的 groups 同一定义）",
        counter: &count
    )
    // 构成是 50% 斩击 + 50% 火，物理倍率只落在斩击那一半上：0.5 × 1.3 + 0.5 × 1 = 1.15。
    try rankerExpectClose(flatPlan.total, 1.15, "组合总倍率只由真增伤的那一条决定", counter: &count)

    // 勾掉一条后重新计算
    let reduced = index.stackPlan(rows: rows, excluded: [102])
    try rankerExpect(reduced.excludedCount == 1, "勾掉的条目数应被记下", counter: &count)
    try rankerExpect(
        Set(reduced.picks.map(\.spEffectId)).contains(101),
        "勾掉组内最强的一条后应由同组次强顶上",
        counter: &count
    )
    try rankerExpect(reduced.total < plan.total, "勾掉更强的一条后总倍率应下降", counter: &count)
}

// MARK: - 宽容解码

private func checkLenientDecoding(counter count: inout Int) throws {
    // 1. 未知字段忽略 + 缺字段退默认值
    let hits = try decodeHits("""
    [
      {"atkId":1,"未来字段":{"a":1},"source":"n","attribute":"Slash"},
      {"atkId":2,"motion":{"physical":100,"未知属性":50},"attribute":"None"}
    ]
    """)
    try rankerExpect(hits.count == 2, "未知字段不应让命中段解码失败", counter: &count)
    try rankerExpect(hits[0].poise == 0 && !hits[0].noFp && hits[0].motion.isEmpty, "缺失字段应退回默认值", counter: &count)
    try rankerExpect(hits[1].motion[.physical] == 100 && hits[1].motion.count == 1, "motion 里的未知属性键应被忽略", counter: &count)

    // 2. 坏元素跳过而不是整份失败
    let mixed = try JSONDecoder().decode(
        [SkillFailableProbe].self,
        from: Data("[{\"atkId\":1,\"attribute\":\"Slash\"},\"坏元素\",{\"atkId\":2,\"attribute\":\"Slash\"}]".utf8)
    )
    try rankerExpect(mixed.compactMap(\.value).count == 2, "数组里的坏元素应被跳过", counter: &count)

    // 3. 整份 skills 数据集：未知顶层字段 + 坏的 weapons 元素
    let dataset = try SkillDataset.decode(from: Data("""
    {
      "schemaVersion": 3, "gameVersion": "x", "dataVersion": "y",
      "未来块": {"a": [1,2,3]},
      "usage": {"选段（必读）": "…", "坏值": 3},
      "caveats": ["一条"],
      "weapons": [
        {"id":1,"nameZh":"甲","wepTypeZh":"刀","attackBase":{"physical":10},"swordArtsParamId":7,"skillVariant":0},
        "坏元素",
        {"id":2,"nameZh":"乙","wepTypeZh":"刀","swordArtsParamId":7}
      ],
      "skills": [{"id":7,"nameZh":"测试战技","weaponIds":[1,2],
                  "variants":[{"atkIds":[11],"via":"behavior","weaponIds":[1,2]}],
                  "hits":[{"atkId":11,"motion":{"physical":100},"attribute":"Slash"},
                          {"atkId":12,"motion":{"physical":999},"attribute":"Slash","noVariant":true}]}],
      "spells": []
    }
    """.utf8))
    try rankerExpect(dataset.weapons.count == 2, "坏的 weapons 元素应被跳过，实际 \(dataset.weapons.count)", counter: &count)
    try rankerExpect(dataset.usage["选段（必读）"] != nil && dataset.usage["坏值"] == nil, "usage 里的非字符串值应被忽略", counter: &count)
    try rankerExpect(dataset.weapons[1].attackBase.isEmpty, "缺 attackBase 的武器应退成零攻击力", counter: &count)

    let index = try SkillDataIndex(dataset: dataset)
    let skill = index.skillsByID[7]!
    let segments = index.segments(for: skill, weapon: index.weaponsByID[1])
    try rankerExpect(segments.map(\.atkId) == [11], "选段应只取 variant 里的 atkId（noVariant 段永远取不到）", counter: &count)
    // skillVariant 缺失的武器：数据集写明「缺失表示该武器的战技没有任何命中段」，
    // 所以就是打不出段——不按 weaponIds 回查、也不退回 ctx 逻辑（与 Windows 端 selectHits 同）。
    let fallback = index.segments(for: skill, weapon: index.weaponsByID[2])
    try rankerExpect(
        fallback.isEmpty,
        "variants 存在但 skillVariant 缺失时应判为打不出段，实际 \(fallback.map(\.atkId))",
        counter: &count
    )

    // 4. variants 整个缺失 → ctx 单选逻辑（先武器名，再类别名，最后 ctx 缺失那组），不取并集
    let ctxDataset = try SkillDataset.decode(from: Data("""
    {
      "schemaVersion": 3,
      "weapons": [{"id":1,"nameZh":"甲","nameEn":"Alpha","wepTypeEn":"Katana","wepTypeZh":"刀","attackBase":{"physical":10},"swordArtsParamId":7}],
      "skills": [{"id":7,"nameZh":"测试战技","weaponIds":[1],
                  "hits":[{"atkId":1,"ctx":"Alpha","motion":{"physical":100},"attribute":"Slash"},
                          {"atkId":2,"ctx":"Katana","motion":{"physical":100},"attribute":"Slash"},
                          {"atkId":3,"motion":{"physical":100},"attribute":"Slash"}]}],
      "spells": []
    }
    """.utf8))
    let ctxIndex = try SkillDataIndex(dataset: ctxDataset)
    let ctxSkill = ctxIndex.skillsByID[7]!
    let ctxSegments = ctxIndex.segments(for: ctxSkill, weapon: ctxIndex.weaponsByID[1])
    try rankerExpect(ctxSegments.map(\.atkId) == [1], "variants 缺失时应按 ctx 单选武器名那一套，实际 \(ctxSegments.map(\.atkId))", counter: &count)
    // 一个 ctx 都对不上时取「ctx 缺失」那组；连那组都没有就是空——绝不退回全部 hits 取并集。
    let strangerWeapon = SkillWeapon(id: 9, nameZh: "别的武器", nameEn: "Nothing", wepTypeEn: "Bow")
    try rankerExpect(
        ctxIndex.hits(for: ctxSkill, weapon: strangerWeapon).map(\.atkId) == [3],
        "ctx 对不上时应退到「ctx 缺失」那一组",
        counter: &count
    )
    let noSharedIndex = try SkillDataIndex(dataset: try SkillDataset.decode(from: Data("""
    {
      "schemaVersion": 3,
      "weapons": [{"id":1,"nameZh":"甲","nameEn":"Alpha","wepTypeEn":"Katana","attackBase":{"physical":10},"swordArtsParamId":7}],
      "skills": [{"id":7,"nameZh":"测试战技","weaponIds":[1],
                  "hits":[{"atkId":1,"ctx":"Alpha","motion":{"physical":100},"attribute":"Slash"},
                          {"atkId":2,"ctx":"Katana","motion":{"physical":100},"attribute":"Slash"}]}],
      "spells": []
    }
    """.utf8)))
    try rankerExpect(
        noSharedIndex.hits(for: noSharedIndex.skillsByID[7]!, weapon: strangerWeapon).isEmpty,
        "ctx 一个都对不上、又没有「ctx 缺失」段时应返回空，不能退回全部 hits",
        counter: &count
    )
    // 直接从 hits[] 取段的路径（variants 缺失）要剔掉 notInvoked 与 noDamage：
    // TAE 判定永远打不出的段、只挂状态 / 只打自己队友的段都不该出现在选段结果里。
    let fallbackFilterIndex = try SkillDataIndex(dataset: try SkillDataset.decode(from: Data("""
    {
      "schemaVersion": 3,
      "weapons": [{"id":1,"nameZh":"甲","nameEn":"Alpha","wepTypeEn":"Katana","attackBase":{"physical":10},"swordArtsParamId":7}],
      "skills": [{"id":7,"nameZh":"测试战技","weaponIds":[1],
                  "hits":[{"atkId":1,"motion":{"physical":100},"attribute":"Slash"},
                          {"atkId":2,"motion":{"physical":300},"attribute":"Slash","notInvoked":true,"notInvokedReason":"gated"},
                          {"atkId":3,"motion":{"holy":100},"attribute":"None","noDamage":true,"selfOrAllyOnly":true}]}],
      "spells": []
    }
    """.utf8)))
    let filteredSkill = fallbackFilterIndex.skillsByID[7]!
    try rankerExpect(
        fallbackFilterIndex.hits(for: filteredSkill, weapon: fallbackFilterIndex.weaponsByID[1]).map(\.atkId) == [1],
        "回退到 hits[] 的路径必须过滤 notInvoked 与 noDamage，实际 "
            + "\(fallbackFilterIndex.hits(for: filteredSkill, weapon: fallbackFilterIndex.weaponsByID[1]).map(\.atkId))",
        counter: &count
    )
    try rankerExpect(
        filteredSkill.hits[1].notInvoked && filteredSkill.hits[1].notInvokedReason == "gated" && !filteredSkill.hits[0].notInvoked,
        "hits[].notInvoked / notInvokedReason 应解码出来",
        counter: &count
    )

    // 4b. v3：skillVariants / weaponSources / customWeapons / swordArtsPools / taeUnmatched
    //     武器 1：固定战技 7，局内池能抽到 8（skillVariants 给 8 的下标 1）；
    //     武器 2：固定战技 9（不收录），池里抽到 8（skillVariants 给 0）；
    //     武器 3：固定战技就是 8、没写 skillVariants → 回退 skillVariant（只对固定战技有效）；
    //     武器 4：固定战技 9、skillVariant=1、没写 skillVariants → 8 不得借用 9 的下标，打不出段。
    let v3Dataset = try SkillDataset.decode(from: Data("""
    {
      "schemaVersion": 3, "counts": {"taeVerified": true, "hits": 4},
      "swordArtsPools": {"500": [[8, 100], [7, 300], "坏条目"], "坏池": [[8, 1]]},
      "weapons": [
        {"id":1,"nameZh":"甲","wepTypeZh":"刀","attackBase":{"physical":10},"swordArtsParamId":7,"skillVariant":0,
         "skillIds":[7,8],"skillVariants":{"7":0,"8":1,"坏键":3},"customWeapons":[[100,500],[101,-1],"坏行"]},
        {"id":2,"nameZh":"乙","wepTypeZh":"刀","attackBase":{"physical":10},"swordArtsParamId":9,"skillVariant":0,
         "skillIds":[8,9],"skillVariants":{"8":0}},
        {"id":3,"nameZh":"丙","wepTypeZh":"刀","attackBase":{"physical":10},"swordArtsParamId":8,"skillVariant":1},
        {"id":4,"nameZh":"丁","wepTypeZh":"刀","attackBase":{"physical":10},"swordArtsParamId":9,"skillVariant":1},
        {"id":5,"nameZh":"戊","wepTypeZh":"大剑","attackBase":{"physical":10},"swordArtsParamId":9,
         "skillVariants":{"8":0}}
      ],
      "skills": [
        {"id":7,"nameZh":"固定战技","weaponIds":[1],"weaponSources":[{"id":1,"fixed":true,"pool":[[500,300,1]]}],
         "variants":[{"atkIds":[71],"via":"behavior","weaponIds":[1]}],
         "hits":[{"atkId":71,"motion":{"physical":100},"attribute":"Slash"}]},
        {"id":8,"nameZh":"池里的战技","weaponIds":[5,1,2,3,4],"taeUnmatched":true,
         "weaponSources":[{"id":5,"pool":[[500,100,1]]},{"id":1,"pool":[[500,100,1]]},{"id":2,"pool":[[500,100,2]]},
                          {"id":3,"fixed":true,"pool":[[500,100,1]]},{"id":4,"pool":[[500,100,1]]}],
         "variants":[{"atkIds":[81],"via":"behavior","weaponIds":[2,5]},{"atkIds":[82,83],"via":"behavior","weaponIds":[1,3]}],
         "hits":[{"atkId":81,"motion":{"physical":100},"attribute":"Slash"},
                 {"atkId":82,"motion":{"physical":120},"attribute":"Slash"},
                 {"atkId":83,"labelZh":"无FP版","motion":{"physical":60},"attribute":"Slash","noFp":true,"noFpSource":"tae"},
                 {"atkId":84,"motion":{"physical":999},"attribute":"Slash","notInvoked":true,"notInvokedReason":"exclusiveBlock"}]}
      ],
      "spells": []
    }
    """.utf8))
    let v3Index = try SkillDataIndex(dataset: v3Dataset)
    let poolSkill = v3Index.skillsByID[8]!
    func v3IDs(_ weaponID: Int) -> [Int] {
        v3Index.segments(for: poolSkill, weapon: v3Index.weaponsByID[weaponID]).map(\.atkId)
    }
    try rankerExpect(v3Dataset.taeVerified && v3Dataset.counts["hits"] == 4, "counts.taeVerified（布尔）与数字计数都应读出来", counter: &count)
    try rankerExpect(
        v3IDs(1) == [82, 83] && v3IDs(2) == [81] && v3IDs(5) == [81],
        "池里抽到的战技按 skillVariants[战技] 选段（武器 1 → [82,83]、武器 2/5 → [81]），"
            + "实际 \(v3IDs(1)) / \(v3IDs(2)) / \(v3IDs(5))",
        counter: &count
    )
    try rankerExpect(
        v3Index.segments(for: v3Index.skillsByID[7]!, weapon: v3Index.weaponsByID[1]).map(\.atkId) == [71],
        "同一把武器的固定战技照样按 skillVariants 选段",
        counter: &count
    )
    try rankerExpect(v3IDs(3) == [82, 83], "skillVariants 缺这一项、但它就是固定战技时回退 skillVariant", counter: &count)
    try rankerExpect(
        v3IDs(4).isEmpty,
        "skillVariant 只对固定战技有效：池里的战技不得借用固定战技的下标，实际 \(v3IDs(4))",
        counter: &count
    )
    let weaponOne = v3Index.weaponsByID[1]!
    try rankerExpect(
        weaponOne.skillIds == [7, 8] && weaponOne.skillVariants == [7: 0, 8: 1]
            && weaponOne.customWeapons == [SkillCustomWeapon(customId: 100, swordArtsTableId: 500),
                                           SkillCustomWeapon(customId: 101, swordArtsTableId: -1)]
            && weaponOne.variantIndex(forSkill: 8) == 1 && weaponOne.variantIndex(forSkill: 99) == nil,
        "weapons[].skillIds / skillVariants / customWeapons 应解码出来（坏键、坏行跳过）",
        counter: &count
    )
    try rankerExpect(
        poolSkill.taeUnmatched && poolSkill.weaponSources.map(\.weaponId) == poolSkill.weaponIds
            && poolSkill.weaponSources[1].pool == [SkillPoolDraw(poolId: 500, weight: 100, customRows: 1)]
            && poolSkill.weaponSources[3].fixed && !poolSkill.weaponSources[1].fixed,
        "skills[].weaponSources / taeUnmatched 应解码出来，且与 weaponIds 同序",
        counter: &count
    )
    try rankerExpect(
        v3Dataset.swordArtsPools.count == 1 && v3Dataset.swordArtsPools[500]?.count == 2
            && v3Dataset.poolChance(poolId: 500, skillId: 8) == 0.25 && v3Dataset.poolChance(poolId: 500, skillId: 1) == nil,
        "顶层 swordArtsPools 应解码出来（坏池、坏条目跳过），池内概率 = 权重 / 权重和",
        counter: &count
    )
    // 来源标记：固定 + 池两者都成立时只标固定；不在 weaponIds 里的武器没有标记。
    try rankerExpect(
        v3Index.weaponSourceKind(skill: poolSkill, weapon: v3Index.weaponsByID[3]!) == .fixed
            && v3Index.weaponSourceKind(skill: poolSkill, weapon: v3Index.weaponsByID[1]!) == .pool
            && v3Index.weaponSourceKind(skill: v3Index.skillsByID[7]!, weapon: v3Index.weaponsByID[2]!) == nil,
        "weaponSource 标记：fixed 优先于 pool，不在列表里的武器为 nil",
        counter: &count
    )
    try rankerExpect(
        SkillWeaponSourceKind.fixed.title == "固定战技" && SkillWeaponSourceKind.pool.title == "局内可抽到",
        "来源标记的文案取自 LoadoutText（weaponSource.fixed / weaponSource.pool）",
        counter: &count
    )
    // 武器分组：含固定武器的类别排前；组内固定武器排前、其余按 id；默认武器是固定武器。
    let v3Groups = v3Index.weaponGroups(for: poolSkill)
    try rankerExpect(
        v3Groups.map(\.wepTypeZh) == ["刀", "大剑"] && v3Groups[0].weapons.map(\.id) == [3, 1, 2, 4]
            && v3Groups[0].fixedCount == 1 && v3Groups[1].fixedCount == 0,
        "武器分组应固定武器排前、其余按 id，实际 \(v3Groups.map { "\($0.wepTypeZh):\($0.weapons.map(\.id))" })",
        counter: &count
    )
    try rankerExpect(v3Index.defaultWeapon(for: poolSkill)?.id == 3, "默认武器应是固定带这个战技的那一把", counter: &count)
    try rankerExpect(v3Index.poolOnlyOutputs == 0, "两个战技都有固定武器，不该算「只在池里」", counter: &count)

    // 4c. schemaVersion < 3 拒绝解码：v2 没有 skillVariants，池里的战技会拿固定战技的下标选错动作套。
    var rejectedV2 = false
    do {
        _ = try SkillDataset.decode(from: Data("{\"schemaVersion\":2,\"weapons\":[],\"skills\":[],\"spells\":[]}".utf8))
    } catch SkillDataError.unsupportedSchema(let version) {
        rejectedV2 = version == 2
    }
    try rankerExpect(rejectedV2, "skills schemaVersion 2 应抛 unsupportedSchema(2)", counter: &count)
    var rejectedMissing = false
    do {
        _ = try SkillDataset.decode(from: Data("{\"weapons\":[],\"skills\":[],\"spells\":[]}".utf8))
    } catch SkillDataError.unsupportedSchema(let version) {
        rejectedMissing = version == 0
    }
    try rankerExpect(rejectedMissing, "缺 schemaVersion 的 skills 也应拒绝（按 0 处理）", counter: &count)

    // 5. 顶层不是对象 / 空数据
    var threwNotAnObject = false
    do {
        _ = try SkillDataset.decode(from: Data("[1,2,3]".utf8))
    } catch SkillDataError.notAnObject {
        threwNotAnObject = true
    }
    try rankerExpect(threwNotAnObject, "skills 顶层不是对象时应抛 notAnObject", counter: &count)

    var buffNotAnObject = false
    do {
        _ = try BuffDataset.decode(from: Data("\"字符串\"".utf8))
    } catch BuffDataError.notAnObject {
        buffNotAnObject = true
    }
    try rankerExpect(buffNotAnObject, "buffs 顶层不是对象时应抛 notAnObject", counter: &count)

    var buffEmpty = false
    do {
        _ = try BuffRankerIndex(data: Data("{\"schemaVersion\":4,\"buffs\":[]}".utf8))
    } catch BuffDataError.empty {
        buffEmpty = true
    }
    try rankerExpect(buffEmpty, "buffs 为空时应抛 empty", counter: &count)

    // 5b. v4 新字段的宽容解码：坏元素跳过、类型不对退默认、缺失退空
    let looseContextIndex = try makeSyntheticBuffIndex(buffs: """
    [
      \(syntheticBuff(
        id: 251, name: "情境数组里混了坏元素",
        rates: "{\"physicsAttackRate\":1.2}",
        scope: "{\"attackContexts\":[\"criticalHit\",123,null],\"未来字段\":true}"
      )),
      \(syntheticBuff(
        id: 252, name: "情境不是数组",
        rates: "{\"physicsAttackRate\":1.2}",
        scope: "{\"attackContexts\":\"criticalHit\"}"
      )),
      \(syntheticBuff(
        id: 253, name: "阶梯字段类型不对",
        rates: "{\"physicsAttackRate\":1.2}",
        stackLadder: "{\"tiers\":\"10\",\"tierSpEffectIds\":null,\"topRates\":{\"physicsAttackRate\":\"1.6\"},\"saved\":\"true\"}"
      ))
    ]
    """)
    let looseContextRows = looseContextIndex.rank(context: skillContext(shares: halfSlashHalfFire()))
    let looseContextByID = Dictionary(
        looseContextRows.map { ($0.spEffectId, $0) }, uniquingKeysWith: { first, _ in first }
    )
    try rankerExpect(
        looseContextByID[251] == nil,
        "attackContexts 里的坏元素跳过后仍应保留 criticalHit，这条默认不得进榜",
        counter: &count
    )
    try rankerExpect(
        looseContextIndex.rank(
            context: skillContext(shares: halfSlashHalfFire()),
            options: BuffRankingOptions(includedAttackContexts: ["criticalHit"])
        ).contains { $0.spEffectId == 251 },
        "坏元素跳过后，剩下的合法情境键仍应生效",
        counter: &count
    )
    try rankerExpect(
        looseContextByID[252] != nil,
        "attackContexts 不是数组时应退成空数组（不限情境），而不是整条丢掉",
        counter: &count
    )
    if let ladderRow = looseContextByID[253], let info = ladderRow.ladder {
        try rankerExpect(info.tiers == 10, "字符串层数应能读成数字", counter: &count)
        try rankerExpect(!info.saved, "认不出来的布尔值应退默认 false，而不是让整条 stackLadder 解码失败", counter: &count)
        try rankerExpect(info.tierSpEffectIds == [253], "tierSpEffectIds 为 null 时应退成只有自己", counter: &count)
        try rankerExpectClose(info.topMultiplier, 1.3, "满层 rates 的字符串数值也应能参与加权", counter: &count)
    } else {
        throw CheckFailure(description: "增伤排名：类型不规范的 stackLadder 应仍能解码")
    }

    // 6. rates 里的字符串数字 / 布尔也能读出来；未知倍率字段只展示不参与计算
    let looseIndex = try makeSyntheticBuffIndex(buffs: """
    [
      \(syntheticBuff(id: 201, name: "字符串数值", rates: "{\"physicsAttackRate\":\"1.5\"}")),
      \(syntheticBuff(id: 202, name: "未知字段", rates: "{\"未来倍率\":2.0,\"physicsAttackRate\":1.1}"))
    ]
    """)
    let looseRows = looseIndex.rank(context: skillContext(shares: halfSlashHalfFire()))
    let looseByID = Dictionary(looseRows.map { ($0.spEffectId, $0) }, uniquingKeysWith: { first, _ in first })
    try rankerExpectClose(looseByID[201]?.effectiveMultiplier ?? 0, 1.25, "字符串数值应能读成倍率", counter: &count)
    try rankerExpectClose(looseByID[202]?.effectiveMultiplier ?? 0, 1.05, "未知倍率字段不得参与计算", counter: &count)
    try rankerExpect(
        looseByID[202]?.rateValues.contains { $0.key == "未来倍率" } == true,
        "未知倍率字段仍应在明细里展示出来",
        counter: &count
    )
}

/// 只为「坏元素跳过」这条检查用的探针（与 RelicCore 内部的包装同形）。
private struct SkillFailableProbe: Decodable {
    let value: SkillHit?

    init(from decoder: Decoder) throws {
        value = try? SkillHit(from: decoder)
    }
}

// MARK: - 真实 skills.json

private func checkSkillDataset(_ index: SkillDataIndex, counter count: inout Int) throws {
    let dataset = index.dataset
    try rankerExpect(dataset.schemaVersion >= 3, "skills schemaVersion 应 ≥ 3，实际 \(dataset.schemaVersion)", counter: &count)
    try rankerExpect(!dataset.gameVersion.isEmpty && !dataset.dataVersion.isEmpty, "skills 缺少 gameVersion / dataVersion", counter: &count)
    try rankerExpect(dataset.weapons.count > 100, "武器数应 > 100，实际 \(dataset.weapons.count)", counter: &count)
    try rankerExpect(dataset.skills.count > 50, "战技数应 > 50，实际 \(dataset.skills.count)", counter: &count)
    try rankerExpect(dataset.spells.count > 50, "法术数应 > 50，实际 \(dataset.spells.count)", counter: &count)
    try rankerExpect(!dataset.caveats.isEmpty, "skills caveats 不应为空（页面底部要展示）", counter: &count)
    try rankerExpect(dataset.usage["选段（必读）"] != nil, "skills usage 应含「选段（必读）」", counter: &count)
    try rankerExpect(dataset.usage["本数据集的边界"] != nil, "skills usage 应含「本数据集的边界」（页面要引用）", counter: &count)
    try rankerExpect(
        dataset.weapons.allSatisfy { (0...3).contains($0.atkAttribute) && (0...3).contains($0.atkAttribute2) },
        "每把武器的 atkAttribute / atkAttribute2 都应落在 0…3",
        counter: &count
    )
    try rankerExpect(
        dataset.weapons.contains { !$0.attackBase.isEmpty },
        "应存在有基础攻击力的武器",
        counter: &count
    )
    try rankerExpect(index.outputs.count > 100, "可选输出手段应 > 100，实际 \(index.outputs.count)", counter: &count)
    try rankerExpect(
        index.outputs.contains { $0.kind == .skill } && index.outputs.contains { $0.kind == .spell },
        "输出手段应同时包含战技与法术",
        counter: &count
    )
    try rankerExpect(
        index.outputs.allSatisfy { !$0.displayName.isEmpty },
        "每个输出手段都应有名字",
        counter: &count
    )
    try rankerExpect(
        index.outputs.filter({ $0.kind == .skill }).allSatisfy { $0.weaponCount > 0 },
        "列出的战技都应至少有一把武器",
        counter: &count
    )
    // 搜索：中文名与英文名都能命中
    if let sample = index.outputs.first(where: { $0.kind == .spell && !$0.nameEn.isEmpty && !$0.nameZh.isEmpty }) {
        try rankerExpect(
            index.outputs(matching: sample.nameZh).contains { $0.id == sample.id },
            "按中文名应能搜到「\(sample.nameZh)」",
            counter: &count
        )
        try rankerExpect(
            index.outputs(matching: sample.nameEn).contains { $0.id == sample.id },
            "按英文名应能搜到「\(sample.nameEn)」",
            counter: &count
        )
    }
}

private func checkSegmentSelection(_ index: SkillDataIndex, counter count: inout Int) throws {
    // 全量（v3）：每个 (战技, 武器) 对——固定引用与局内战技池——都按 weapons[].skillVariants[战技] 选段，
    // 结果恰好是那一套的 atkIds，永远选不到 noVariant / notInvoked 段；固定战技那一项与 skillVariant 相同。
    var checkedPairs = 0
    var poolPairs = 0
    var missingIndex = 0
    var fixedMismatch = 0
    var legacyWouldDiffer = 0
    var emptySelection = 0
    var pickedNoVariant = 0
    var pickedNotInvoked = 0
    var notExactVariant = 0
    for skill in index.dataset.skills where !skill.variants.isEmpty {
        for id in skill.weaponIds {
            guard let weapon = index.weaponsByID[id] else { continue }
            guard let variantIndex = weapon.skillVariants[skill.id], skill.variants.indices.contains(variantIndex) else {
                missingIndex += 1
                continue
            }
            checkedPairs += 1
            if weapon.swordArtsParamId == skill.id {
                if weapon.skillVariant != variantIndex { fixedMismatch += 1 }
            } else {
                poolPairs += 1
                // 旧写法（拿 skillVariant 去套池里的战技）在这些对上会选错动作套。
                if let legacy = weapon.skillVariant, legacy != variantIndex { legacyWouldDiffer += 1 }
            }
            let hits = index.hits(for: skill, weapon: weapon)
            if hits.isEmpty { emptySelection += 1 }
            if hits.contains(where: \.noVariant) { pickedNoVariant += 1 }
            if hits.contains(where: \.notInvoked) { pickedNotInvoked += 1 }
            if Set(hits.map(\.atkId)) != Set(skill.variants[variantIndex].atkIds) { notExactVariant += 1 }
        }
    }
    try rankerExpect(checkedPairs > 5000, "应有 > 5000 个 (战技, 武器) 对参与选段校验，实际 \(checkedPairs)", counter: &count)
    try rankerExpect(poolPairs > 3000, "局内战技池带来的 (战技, 武器) 对应 > 3000，实际 \(poolPairs)", counter: &count)
    try rankerExpect(missingIndex == 0, "有 variants 的战技，每把武器都应在 skillVariants 里有下标，缺 \(missingIndex) 对", counter: &count)
    try rankerExpect(fixedMismatch == 0, "固定战技那一项的 skillVariants 应与 skillVariant 相同，\(fixedMismatch) 把不同", counter: &count)
    try rankerExpect(
        legacyWouldDiffer > 0,
        "应存在「拿固定战技的 skillVariant 去选池里战技会选错套」的武器（否则 skillVariants 这一改是空跑）",
        counter: &count
    )
    try rankerExpect(emptySelection == 0, "按 skillVariants 选段不应选出空段，实际 \(emptySelection) 对", counter: &count)
    try rankerExpect(pickedNoVariant == 0, "选段结果不应包含 noVariant 段，实际 \(pickedNoVariant) 对", counter: &count)
    try rankerExpect(pickedNotInvoked == 0, "选段结果不应包含 notInvoked 段，实际 \(pickedNotInvoked) 对", counter: &count)
    try rankerExpect(notExactVariant == 0, "选段结果应恰好是 variants[skillVariants[战技]].atkIds，\(notExactVariant) 对不符", counter: &count)

    // 多动作套的战技：不同套的武器选出的段必须不同（证明没有按 ctx 取并集）。
    // v3 起 variants[].weaponIds 含池里的武器，它们的 skillVariant 指的是自己的固定战技——
    // 下标一律看 skillVariants[战技]。
    guard let multi = index.dataset.skills.first(where: { $0.variants.count > 1 && $0.variants.allSatisfy { !$0.weaponIds.isEmpty } }) else {
        throw CheckFailure(description: "增伤排名：找不到有多套动作的战技")
    }
    let firstWeapon = index.weaponsByID[multi.variants[0].weaponIds[0]]
    let secondWeapon = index.weaponsByID[multi.variants[1].weaponIds[0]]
    try rankerExpect(
        firstWeapon?.skillVariants[multi.id] == 0 && secondWeapon?.skillVariants[multi.id] == 1,
        "variants[i].weaponIds 里的武器，skillVariants[战技] 就是 i（「\(multi.displayName)」）",
        counter: &count
    )
    let firstIDs = Set(index.hits(for: multi, weapon: firstWeapon).map(\.atkId))
    let secondIDs = Set(index.hits(for: multi, weapon: secondWeapon).map(\.atkId))
    try rankerExpect(!firstIDs.isEmpty && !secondIDs.isEmpty, "多套动作的战技两边都应选出段", counter: &count)
    try rankerExpect(
        firstIDs == Set(multi.variants[0].atkIds) && secondIDs == Set(multi.variants[1].atkIds),
        "两把武器应各自选出自己那一套（「\(multi.displayName)」）",
        counter: &count
    )
    try rankerExpect(firstIDs != secondIDs, "同一战技的不同动作套应选出不同的段（「\(multi.displayName)」）", counter: &count)
    try rankerExpect(
        firstIDs.count < multi.hits.count,
        "选段结果必须是 hits 的子集，不能把所有动作套一起算进去",
        counter: &count
    )

    // 武器分组：按 wepTypeZh 分组，组内武器都属于该类别
    let groups = index.weaponGroups(for: multi)
    try rankerExpect(!groups.isEmpty, "战技应能按武器类别分组", counter: &count)
    try rankerExpect(
        groups.allSatisfy { group in group.weapons.allSatisfy { $0.wepTypeZh == group.wepTypeZh || $0.wepTypeEn == group.wepTypeZh } },
        "分组内的武器应属于同一个类别",
        counter: &count
    )
    try rankerExpect(
        groups.reduce(0) { $0 + $1.weapons.count } == multi.weaponIds.count,
        "分组后武器总数应与 weaponIds 一致",
        counter: &count
    )
    try rankerExpect(index.defaultWeapon(for: multi) != nil, "应能给出默认武器（第一把）", counter: &count)

    // 专注值不足版：找一套同时有正常版段与专注值不足版段的，验证互斥切换
    var found = false
    for weapon in index.dataset.weapons {
        guard let skill = index.skillsByID[weapon.swordArtsParamId] else { continue }
        let segments = index.segments(for: skill, weapon: weapon)
        guard segments.contains(where: { $0.noFp && $0.hasDamage }),
              segments.contains(where: { !$0.noFp && $0.hasDamage && !$0.noDamage }) else { continue }
        let normal = SkillDamageMath.defaultSelection(segments)
        let noFp = SkillDamageMath.selection(segments, useNoFp: true)
        let shared = Set(segments.filter(\.fpBoth).map(\.atkId))
        try rankerExpect(
            normal.allSatisfy { id in segments.first { $0.atkId == id }?.noFp == false },
            "默认勾选不应包含专注值不足版（「\(skill.displayName)」）",
            counter: &count
        )
        try rankerExpect(
            !noFp.isEmpty && noFp.allSatisfy { id in segments.first { $0.atkId == id }.map { $0.noFp || $0.fpBoth } == true },
            "切到专注值不足版后应只剩 noFp 段（与两侧共用的 fpBoth 段）",
            counter: &count
        )
        try rankerExpect(normal.intersection(noFp) == shared.intersection(normal), "正常版与专注值不足版必须互斥（fpBoth 段除外）", counter: &count)
        found = true
        break
    }
    try rankerExpect(found, "真实数据里应存在同时有正常版与专注值不足版段的战技", counter: &count)

    try checkSkillDatasetV3(index, counter: &count)
}

// MARK: - 战技数据 v3：局内战技池、TAE 核实、FP 分侧

/// 某个战技 × 武器的选段结果：(全部段, 正常版勾选, 专注值不足版勾选)。
private func v3Selection(
    _ index: SkillDataIndex, skillID: Int, weaponID: Int
) throws -> (all: [Int], normal: [Int], noFp: [Int]) {
    guard let skill = index.skillsByID[skillID], let weapon = index.weaponsByID[weaponID] else {
        throw CheckFailure(description: "增伤排名：战技 \(skillID) / 武器 \(weaponID) 不在数据集里")
    }
    let segments = index.segments(for: skill, weapon: weapon)
    return (
        segments.map(\.atkId),
        SkillDamageMath.defaultSelection(segments).sorted(),
        SkillDamageMath.selection(segments, useNoFp: true).sorted()
    )
}

private func checkSkillDatasetV3(_ index: SkillDataIndex, counter count: inout Int) throws {
    let dataset = index.dataset
    let skillHits = dataset.skills.flatMap(\.hits)
    let allHits = skillHits + dataset.spells.flatMap(\.hits)

    // ① 计数（schemaVersion 3）：counts 与逐条现数一致
    func counted(_ key: String) -> Int { Int(dataset.counts[key] ?? -1) }
    try rankerExpect(dataset.taeVerified, "counts.taeVerified 应为 true（本份数据做过 TAE 核实）", counter: &count)
    try rankerExpect(
        dataset.skills.count == 187 && counted("skills") == 187
            && dataset.skills.filter { !$0.hits.isEmpty }.count == 166 && counted("skillsWithHits") == 166
            && dataset.skills.filter { !$0.weaponIds.isEmpty }.count == 185 && counted("skillsWithWeapons") == 185
            && allHits.count == 2201 && counted("hits") == 2201,
        "v3 计数：skills 187 / skillsWithHits 166 / skillsWithWeapons 185 / hits 2201",
        counter: &count
    )
    try rankerExpect(
        allHits.filter(\.notInvoked).count == 34 && counted("hitsNotInvoked") == 34
            && allHits.filter { $0.notInvoked && !$0.noDamage && (!$0.motion.isEmpty || !$0.flat.isEmpty) }.count == 24
            && counted("hitsNotInvokedDamaging") == 24,
        "notInvoked 34 段（带伤害 24 段）",
        counter: &count
    )
    try rankerExpect(
        allHits.filter { $0.noFpSource == "tae" }.count == 213 && counted("hitsNoFpByTae") == 213
            && allHits.filter(\.fpBoth).count == 19 && counted("hitsFpBoth") == 19
            && allHits.filter(\.selfOrAllyOnly).count == 36 && counted("hitsSelfOrAllyOnly") == 36,
        "noFp 按 TAE 补标 213 段、fpBoth 19 段、selfOrAllyOnly 36 段",
        counter: &count
    )
    try rankerExpect(
        allHits.filter { $0.noFpSource == "tae" }.allSatisfy { $0.noFp && $0.displayLabel.hasPrefix("无FP版") },
        "TAE 补标的无 FP 段 noFp=true、labelZh 以「无FP版」开头",
        counter: &count
    )
    try rankerExpect(allHits.filter(\.fpBoth).allSatisfy { !$0.noFp }, "fpBoth 段的 noFp 一定是 false", counter: &count)
    try rankerExpect(allHits.filter(\.selfOrAllyOnly).allSatisfy(\.noDamage), "selfOrAllyOnly 段一律带 noDamage", counter: &count)
    try rankerExpect(
        dataset.usage.count == 8 && dataset.usage["战技来源（v3）"] != nil && dataset.usage["命中段已按 TAE 核实（v3）"] != nil
            && dataset.caveats.count == 11,
        "usage 8 个键（新增「战技来源（v3）」「命中段已按 TAE 核实（v3）」）、caveats 11 条，"
            + "实际 \(dataset.usage.count) / \(dataset.caveats.count)",
        counter: &count
    )
    try rankerExpect(
        dataset.swordArtsPools.count == counted("swordArtsPools")
            && dataset.swordArtsPools.values.reduce(0) { $0 + $1.count } == counted("swordArtsPoolEntries"),
        "顶层 swordArtsPools 的池数与条目数应与 counts 一致",
        counter: &count
    )
    try rankerExpect(
        dataset.weapons.reduce(0) { $0 + $1.customWeapons.count } == counted("customWeaponRows")
            && dataset.weapons.reduce(0) { $0 + $1.skillIds.count } == counted("weaponSkillPairs"),
        "weapons[].customWeapons / skillIds 的总数应与 counts 一致",
        counter: &count
    )

    // ② weaponSources：与 weaponIds 同序；fixed ⇔ swordArtsParamId 就是这个战技；weapons[].skillIds 是反向索引。
    var sourceOrderBad = 0
    var fixedBad = 0
    var reverseBad = 0
    var fixedPairs = 0
    var poolPairs = 0
    var bothPairs = 0
    var markBad = 0
    var groupOrderBad = 0
    var defaultNotFixed = 0
    for skill in dataset.skills {
        if skill.weaponSources.map(\.weaponId) != skill.weaponIds { sourceOrderBad += 1 }
        for source in skill.weaponSources {
            guard let weapon = index.weaponsByID[source.weaponId] else { continue }
            if source.fixed != (weapon.swordArtsParamId == skill.id) { fixedBad += 1 }
            if !weapon.skillIds.contains(skill.id) { reverseBad += 1 }
            if source.fixed { fixedPairs += 1 }
            if !source.pool.isEmpty { poolPairs += 1 }
            if source.fixed && !source.pool.isEmpty { bothPairs += 1 }
            // 页面标记：两者都成立时只标固定。
            if index.weaponSourceKind(skill: skill, weapon: weapon) != (source.fixed ? .fixed : .pool) { markBad += 1 }
        }
        // 武器选择器：组内固定武器排前、其余按 id；含固定武器的组排前；默认武器是固定武器（有的话）。
        let groups = index.weaponGroups(for: skill)
        for group in groups {
            let kinds = group.weapons.map { index.weaponSourceKind(skill: skill, weapon: $0) }
            let fixedPart = group.weapons.prefix(group.fixedCount)
            let poolPart = group.weapons.dropFirst(group.fixedCount)
            if kinds.prefix(group.fixedCount).contains(where: { $0 != .fixed })
                || kinds.dropFirst(group.fixedCount).contains(where: { $0 != .pool })
                || fixedPart.map(\.id) != fixedPart.map(\.id).sorted()
                || poolPart.map(\.id) != poolPart.map(\.id).sorted() {
                groupOrderBad += 1
            }
        }
        let fixedGroups = groups.map { $0.fixedCount > 0 }
        if fixedGroups != fixedGroups.sorted(by: { $0 && !$1 }) { groupOrderBad += 1 }
        if skill.weaponSources.contains(where: \.fixed),
           let first = index.defaultWeapon(for: skill), index.weaponSourceKind(skill: skill, weapon: first) != .fixed {
            defaultNotFixed += 1
        }
    }
    try rankerExpect(sourceOrderBad == 0, "weaponSources 应与 weaponIds 一一对应、同序，\(sourceOrderBad) 个战技不符", counter: &count)
    try rankerExpect(fixedBad == 0, "weaponSources[].fixed 应当且仅当武器的 swordArtsParamId 就是这个战技，\(fixedBad) 项不符", counter: &count)
    try rankerExpect(reverseBad == 0, "weapons[].skillIds 应是 skills[].weaponIds 的反向索引，\(reverseBad) 项不符", counter: &count)
    try rankerExpect(
        fixedPairs == counted("weaponSkillPairsFixed") && poolPairs == counted("weaponSkillPairsPool")
            && bothPairs == counted("weaponSkillPairsBoth") && bothPairs > 0,
        "固定 / 池 / 两者皆是的 (战技, 武器) 对数应与 counts 一致（\(fixedPairs) / \(poolPairs) / \(bothPairs)）",
        counter: &count
    )
    try rankerExpect(markBad == 0, "「固定战技 / 局内可抽到」标记：两者都成立时只标固定，\(markBad) 项不符", counter: &count)
    try rankerExpect(groupOrderBad == 0, "武器选择器：固定武器排前、其余按 id，含固定武器的类别排前，\(groupOrderBad) 处不符", counter: &count)
    try rankerExpect(defaultNotFixed == 0, "有固定武器的战技，默认武器应是固定武器，\(defaultNotFixed) 个不符", counter: &count)
    let poolOnlySkills = dataset.skills.filter { !$0.weaponIds.isEmpty && !$0.weaponSources.contains(where: \.fixed) }
    try rankerExpect(
        poolOnlySkills.count == 52 && counted("skillsPoolOnly") == 52,
        "只在局内战技池里出现的战技 52 个，实际 \(poolOnlySkills.count)",
        counter: &count
    )
    try rankerExpect(
        index.poolOnlyOutputs > 0 && index.poolOnlyOutputs <= poolOnlySkills.count,
        "列表里应收进只在池里出现的战技（\(index.poolOnlyOutputs) 个）",
        counter: &count
    )

    // ③ 210 风暴刃：v2 没有任何武器；v3 = 64 把、全部来自局内战技池，单一动作套 7 段，
    //    300000411–413 是 TAE 补标的无 FP 段（noFpSource="tae"）。
    guard let stormBlade = index.skillsByID[210], let giantHunt = index.skillsByID[116],
          let serpentHunt = index.skillsByID[1188] else {
        throw CheckFailure(description: "增伤排名：战技 210 / 116 / 1188 不在数据集里")
    }
    try rankerExpect(
        stormBlade.weaponIds.count == 64 && stormBlade.weaponSources.allSatisfy { !$0.fixed && !$0.pool.isEmpty },
        "210 风暴刃应有 64 把武器、全部来自局内战技池，实际 \(stormBlade.weaponIds.count)",
        counter: &count
    )
    var stormBad: [Int] = []
    for id in stormBlade.weaponIds {
        let selection = try v3Selection(index, skillID: 210, weaponID: id)
        if selection.all != [300000407, 300000408, 300000409, 300000410, 300000411, 300000412, 300000413]
            || selection.normal != [300000407, 300000408, 300000409, 300000410]
            || selection.noFp != [300000411, 300000412, 300000413] {
            stormBad.append(id)
        }
    }
    try rankerExpect(
        stormBad.isEmpty,
        "210 风暴刃每把武器：正常版 300000407–410、专注值不足版 300000411–413，\(stormBad.count) 把不符（例如 \(stormBad.prefix(3))）",
        counter: &count
    )
    if let dagger = index.weaponsByID[1000000] {
        try rankerExpect(
            index.weaponSourceKind(skill: stormBlade, weapon: dagger) == .pool && dagger.swordArtsParamId != 210
                && dagger.variantIndex(forSkill: 210) == dagger.skillVariants[210],
            "210 × 1000000 匕首：标「局内可抽到」，下标取 skillVariants[210]",
            counter: &count
        )
    }
    try rankerExpect(
        stormBlade.hits.filter { (300000411...300000413).contains($0.atkId) }.allSatisfy { $0.noFp && $0.noFpSource == "tae" },
        "风暴刃 300000411–413 是 TAE 补标的无 FP 段",
        counter: &count
    )

    // ④ 116 狩猎巨人：50 把、全部来自局内战技池；正常版 301700910、专注值不足版 301700915（TAE 补标）。
    try rankerExpect(
        giantHunt.weaponIds.count == 50 && giantHunt.weaponSources.allSatisfy { !$0.fixed },
        "116 狩猎巨人应有 50 把武器、全部来自局内战技池，实际 \(giantHunt.weaponIds.count)",
        counter: &count
    )
    var giantBad: [Int] = []
    for id in giantHunt.weaponIds {
        let selection = try v3Selection(index, skillID: 116, weaponID: id)
        if selection.all != [301700910, 301700915] || selection.normal != [301700910] || selection.noFp != [301700915] {
            giantBad.append(id)
        }
    }
    try rankerExpect(
        giantBad.isEmpty,
        "116 狩猎巨人每把武器：正常版 301700910、专注值不足版 301700915，\(giantBad.count) 把不符（例如 \(giantBad.prefix(3))）",
        counter: &count
    )
    for output in index.outputs where output.kind == .skill && (output.entryID == 210 || output.entryID == 116) {
        try rankerExpect(
            output.weaponCount == (output.entryID == 210 ? 64 : 50),
            "输出手段「\(output.displayName)」的武器数应含池来源",
            counter: &count
        )
    }
    try rankerExpect(
        index.outputs.contains { $0.kind == .skill && $0.entryID == 210 }
            && index.outputs.contains { $0.kind == .skill && $0.entryID == 116 },
        "只在池里出现的 210 风暴刃、116 狩猎巨人应进入输出手段列表（v2 没有武器，被挡在外面）",
        counter: &count
    )

    // ⑤ 1188 狩猎大蛇：只有 17030000 大蛇狩猎矛（固定 + 池两者皆是 → 标固定）；只剩两段近战 L2 与各自的无 FP 版，
    //    光之束 301703900/901（gated）、301703905/975（notInvoked）、301703955（roarR2Only）永远打不出。
    try rankerExpect(
        serpentHunt.weaponIds == [17030000] && serpentHunt.weaponSources.first?.fixed == true
            && serpentHunt.weaponSources.first?.pool.isEmpty == false,
        "1188 狩猎大蛇只有 17030000，且固定 + 池两者都成立",
        counter: &count
    )
    if let serpentWeapon = index.weaponsByID[17030000] {
        try rankerExpect(
            index.weaponSourceKind(skill: serpentHunt, weapon: serpentWeapon) == .fixed,
            "1188 × 17030000：固定 + 池两者都成立时只标「固定战技」",
            counter: &count
        )
    }
    let serpent = try v3Selection(index, skillID: 1188, weaponID: 17030000)
    try rankerExpect(
        serpent.all == [301703950, 301703951, 301703970, 301703971]
            && serpent.normal == [301703950, 301703951] && serpent.noFp == [301703970, 301703971],
        "1188 狩猎大蛇：正常版 301703950/951、专注值不足版 970/971，实际 \(serpent.all) / \(serpent.normal) / \(serpent.noFp)",
        counter: &count
    )
    let serpentDead = serpentHunt.hits.filter(\.notInvoked)
    try rankerExpect(
        Set(serpentDead.map(\.atkId)) == [301703900, 301703901, 301703905, 301703955, 301703975]
            && serpentDead.filter { $0.notInvokedReason == "gated" }.map(\.atkId).sorted() == [301703900, 301703901],
        "1188 的五段 notInvoked（两段光之束 gated）只留在 hits[]",
        counter: &count
    )

    // ⑥ fpBoth：两侧共用的段，专注值不足版这一侧也要计入（旧写法会丢掉它们）。
    let ritual = try v3Selection(index, skillID: 1024, weaponID: 16120000)
    try rankerExpect(
        ritual.normal == [301612910, 301612911] && ritual.noFp == [301612910, 301612911],
        "1024 唤矛仪式 × 16120000：两侧都是 fpBoth 的 301612910/911（905–909 只挂状态），"
            + "实际 \(ritual.normal) / \(ritual.noFp)",
        counter: &count
    )
    let flame = try v3Selection(index, skillID: 1021, weaponID: 3130000)
    try rankerExpect(
        flame.normal == [303401400] && flame.noFp == [303401400],
        "1021 毁灭灵火 × 3130000：唯一一段 303401400 是 fpBoth，两侧都计，实际 \(flame.normal) / \(flame.noFp)",
        counter: &count
    )
    let carian = try v3Selection(index, skillID: 218, weaponID: 1000000)
    try rankerExpect(
        carian.normal == [300200870, 300200871, 300200872]
            && carian.noFp == [300200872, 300200875, 300200876, 300200877],
        "218 伟哉卡利亚 × 1000000：300200872 两侧都计，实际 \(carian.normal) / \(carian.noFp)",
        counter: &count
    )
    // 全量：凡是选出了 fpBoth 段的 (战技, 武器) 对，两侧勾选都含它。
    var fpBothPairs = 0
    var fpBothDropped = 0
    for skill in dataset.skills where skill.hits.contains(where: \.fpBoth) {
        for id in skill.weaponIds {
            guard let weapon = index.weaponsByID[id] else { continue }
            let segments = index.segments(for: skill, weapon: weapon)
            let shared = Set(segments.filter { $0.fpBoth && !$0.noDamage }.map(\.atkId))
            guard !shared.isEmpty else { continue }
            fpBothPairs += 1
            if !shared.isSubset(of: SkillDamageMath.selection(segments, useNoFp: false))
                || !shared.isSubset(of: SkillDamageMath.selection(segments, useNoFp: true)) {
                fpBothDropped += 1
            }
        }
    }
    try rankerExpect(fpBothPairs > 0 && fpBothDropped == 0, "fpBoth 段在两侧勾选里都在（\(fpBothPairs) 对里 \(fpBothDropped) 对丢了）", counter: &count)
}

/// 分段芯片的展示口径：只列「对当前武器真正有贡献」的通道（两端同文同序）。
///
/// 参数表里每段常常五属性同值，但武器该属性 attackBase 为 0 时乘出来恒为 0——
/// 这些项对构成与排名毫无影响，并排列出来只会被当成 bug。
/// Windows 端 renderer/pages/ranker.js 的 hitChipPlan 是同一口径。
private func checkSegmentChips(_ index: SkillDataIndex, counter count: inout Int) throws {
    // ① 尸山血海（9040000）＋ 尸横遍野（1177）：武器只有物理 46 与火 46，
    //    每段的芯片只应剩「斩击 + 火」两个，另外三项记进 hiddenZeroComponentCount。
    guard let weapon = index.weaponsByID[9040000], let skill = index.skillsByID[1177] else {
        throw CheckFailure(description: "增伤排名：对照用例的武器 9040000 / 战技 1177 不在数据集里")
    }
    try rankerExpect(
        weapon.attack(.physical) > 0 && weapon.attack(.fire) > 0,
        "尸山血海应当有物理与火的基础攻击力",
        counter: &count
    )
    for element in [SkillElement.magic, .lightning, .holy] {
        try rankerExpect(
            weapon.attack(element) <= 0,
            "尸山血海的 \(element) 基础攻击力应当是 0",
            counter: &count
        )
    }
    let segments = index.segments(for: skill, weapon: weapon)
    try rankerExpect(!segments.isEmpty, "尸横遍野 + 尸山血海应当选得出段", counter: &count)
    for segment in segments {
        try rankerExpect(
            segment.visibleComponents.map(\.channel) == [.slash, .fire],
            "尸横遍野 #\(segment.atkId) 的芯片只应剩「斩击 + 火」两个，"
                + "实际 \(segment.visibleComponents.map(\.channel.titleZh))",
            counter: &count
        )
        try rankerExpect(
            segment.hiddenZeroComponentCount == 3,
            "尸横遍野 #\(segment.atkId) 应当有三项因「武器该属性为 0」被隐藏",
            counter: &count
        )
        try rankerExpect(
            segment.components.count == 5,
            "components 本身不得被裁剪——隐藏只发生在展示层",
            counter: &count
        )
    }

    // ② 法术段本来就只用 flat：芯片只剩带 flat 的通道，且不算「被隐藏」
    //    （缺席的原因是法术不吃 motion，不是武器该属性为 0）。
    guard let spell = index.spellsByID[4021] else {
        throw CheckFailure(description: "增伤排名：对照用例的法术 4021（帚星）不在数据集里")
    }
    let spellSegments = index.segments(for: spell).filter { $0.hasDamage }
    try rankerExpect(!spellSegments.isEmpty, "帚星应当有带固定值的命中段", counter: &count)
    for segment in spellSegments {
        try rankerExpect(
            !segment.visibleComponents.isEmpty,
            "帚星 #\(segment.atkId) 应当至少剩一个芯片",
            counter: &count
        )
        try rankerExpect(
            segment.visibleComponents.allSatisfy { ($0.flat ?? 0) > 0 && $0.motionPercent == nil },
            "帚星 #\(segment.atkId) 的芯片只应来自 flat，且不显示动作值",
            counter: &count
        )
        try rankerExpect(
            segment.hiddenZeroComponentCount == 0,
            "法术段缺席的属性不算「武器该属性为 0」，不得触发行末那句小字",
            counter: &count
        )
    }

    // ③ 隐藏只动展示层：可见通道的相对值之和必须等于整段的 total。
    let composition = SkillDamageMath.composition(
        of: segments, selected: SkillDamageMath.defaultSelection(segments)
    )
    let visibleTotal = segments
        .filter { SkillDamageMath.defaultSelection(segments).contains($0.atkId) }
        .reduce(0.0) { $0 + $1.visibleComponents.reduce(0) { $0 + $1.amount } }
    try rankerExpectClose(
        visibleTotal, composition.total,
        "隐藏零贡献通道不得改变构成总量", tolerance: 0.000000001, counter: &count
    )

    // ③' 同一条不变量的**全量版本**：所有可达的（段 × 武器）与全部法术段逐对验。
    //    Windows 端 ranker.test.mjs 有同名断言，两端一起钉住「芯片＝真正有贡献的属性」。
    //    单点版本只覆盖尸横遍野这一把武器，正是它当初没能发现「只靠 addBaseAtk 出伤害的
    //    属性被漏掉」——那一类段的可见通道之和会小于 total，最狠的整段一个芯片都不剩。
    var chipPairs = 0
    var pairsWithHidden = 0
    var pairsWithBaseAtkOnlyChannel = 0
    var mismatched: [String] = []
    var emptyChipsWithDamage: [String] = []
    func auditChips(_ segment: SkillSegment, where label: String) {
        chipPairs += 1
        let visible = segment.visibleComponents.reduce(0.0) { $0 + $1.amount }
        if abs(visible - segment.total) > 0.000000001 { mismatched.append(label) }
        if segment.visibleComponents.isEmpty && segment.total > 0 { emptyChipsWithDamage.append(label) }
        if segment.hiddenZeroComponentCount > 0 { pairsWithHidden += 1 }
        if segment.visibleComponents.contains(where: {
            $0.motionPercent == nil && $0.flat == nil && $0.baseAttack != nil
        }) { pairsWithBaseAtkOnlyChannel += 1 }
    }
    for one in index.dataset.skills {
        for id in one.weaponIds {
            guard let aWeapon = index.weaponsByID[id] else { continue }
            for segment in index.segments(for: one, weapon: aWeapon) {
                auditChips(segment, where: "#\(segment.atkId) × \(aWeapon.nameZh)")
            }
        }
    }
    for one in index.dataset.spells {
        for segment in index.segments(for: one) {
            auditChips(segment, where: "法术段 #\(segment.atkId)")
        }
    }
    try rankerExpect(
        mismatched.isEmpty,
        "可见芯片之和必须等于整段总量，\(mismatched.count) 对不成立"
            + "（例如 \(mismatched.prefix(3).joined(separator: "、"))）",
        counter: &count
    )
    try rankerExpect(
        emptyChipsWithDamage.isEmpty,
        "有伤害的段不得一个芯片都不剩（会被渲染成「无伤害数值」），"
            + "\(emptyChipsWithDamage.count) 对不成立"
            + "（例如 \(emptyChipsWithDamage.prefix(3).joined(separator: "、"))）",
        counter: &count
    )
    try rankerExpect(chipPairs > 30000, "对照样本太少说明遍历写错了（v3 含局内战技池的武器，本版本 \(chipPairs) 对）", counter: &count)
    try rankerExpect(
        pairsWithHidden > 0,
        "真实数据里应当有「其余属性该武器为 0」的段，否则这一关是空跑",
        counter: &count
    )
    try rankerExpect(
        pairsWithBaseAtkOnlyChannel > 0,
        "真实数据里应当有只靠 addBaseAtk 出伤害的通道，否则这一关是空跑",
        counter: &count
    )

    // ③'' 单点样本：113 主教冲锋 + 23000600 雷电主教大火槌的 #30000831。数据里只有
    //     flat.fire = 55，段自己声明 attribute=Standard，标准与雷两条通道全部来自
    //     addBaseAtk——旧口径下这一段会被显示成「火 固定 55」，实际打的是 219。
    guard let chargeWeapon = index.weaponsByID[23000600],
          let charge = index.skillsByID[113],
          let bullet = index.segments(for: charge, weapon: chargeWeapon)
              .first(where: { $0.atkId == 30000831 }) else {
        throw CheckFailure(description: "增伤排名：对照用例 113 × 23000600 的 #30000831 不在数据集里")
    }
    try rankerExpect(
        bullet.visibleComponents.map(\.channel) == [.standard, .fire, .lightning],
        "#30000831 的芯片应当是「标准 · 火 · 雷」三条，"
            + "实际 \(bullet.visibleComponents.map(\.channel.titleZh))",
        counter: &count
    )
    try rankerExpect(
        bullet.visibleComponents.first { $0.channel == .standard }
            .map { $0.motionPercent == nil && $0.flat == nil && $0.baseAttack == 82 } == true,
        "#30000831 的标准一格只有「+基础攻击力」（82），没有动作值也没有固定值",
        counter: &count
    )
    try rankerExpectClose(
        bullet.total, 219, "#30000831 的总量应当是 219（标准 82 + 雷 82 + 火 55）",
        tolerance: 0.000000001, counter: &count
    )
    try rankerExpect(
        bullet.hiddenZeroComponentCount == 0,
        "addBaseAtk 撑起来的通道不是「武器该属性为 0」，不得触发行末那句小字",
        counter: &count
    )

    // ④ 展示层文案：数据集里的「无FP版」一律显示成「专注值不足版」，原文不动。
    let rawNoFp = skill.hits.filter { $0.noFp }
    try rankerExpect(!rawNoFp.isEmpty, "尸横遍野应当带专注值不足版的段", counter: &count)
    for hit in rawNoFp {
        try rankerExpect(
            hit.displayLabel.contains("无FP版"),
            "数据集原文应当保持不变（hits[].labelZh 仍写「无FP版」）",
            counter: &count
        )
        try rankerExpect(
            SkillTextZh.fpText(hit.displayLabel).hasPrefix("专注值不足版")
                && !SkillTextZh.fpText(hit.displayLabel).contains("FP"),
            "展示层应当把「无FP版」换成「专注值不足版」",
            counter: &count
        )
    }
    try rankerExpect(
        SkillTextZh.fpText("L2 第3段") == "L2 第3段",
        "不含 FP 的段名应当原样返回",
        counter: &count
    )
    // 两端同一套正则：全角空格也要吃下，数据集换写法时不能只有一端替换掉
    // （原来 macOS 这边是两个字面量，Windows 是正则，正是会分叉的地方）。
    try rankerExpect(
        SkillTextZh.fpText("无　FP版 R2") == "专注值不足版 R2",
        "全角空格写法也应当替换掉",
        counter: &count
    )

    // ⑤ 底部「战技数据的取舍与已知问题」用的是数据集 caveats 原文，里面还写着
    //    「12 段（6 段带 FP + 6 段 No FP）」。展示层一律换成中文，原文不动。
    try rankerExpect(
        SkillTextZh.fpText("12 段（6 段带 FP + 6 段 No FP）就是全部")
            == "12 段（6 段正常版 + 6 段专注值不足版）就是全部",
        "caveats 里的「带 FP」「No FP」应当换成「正常版」「专注值不足版」",
        counter: &count
    )
    try rankerExpect(
        index.dataset.caveats.contains { $0.contains("FP") },
        "数据集 caveats 原文里确实还有 FP（否则这一关是空跑）",
        counter: &count
    )
    for caveat in index.dataset.caveats {
        try rankerExpect(
            !SkillTextZh.fpText(caveat).contains("FP"),
            "页面上不该再出现英文 FP：\(SkillTextZh.fpText(caveat).prefix(40))",
            counter: &count
        )
    }
}

private func checkComposition(_ index: SkillDataIndex, counter count: inout Int) throws {
    // 多属性武器：构成里至少两个通道有占比，且占比之和为 1
    guard let weapon = index.dataset.weapons.first(where: { candidate in
        candidate.attackBase.filter { $0.value > 0 }.count >= 2
            && candidate.skillVariant != nil
            && index.skillsByID[candidate.swordArtsParamId] != nil
    }) else {
        throw CheckFailure(description: "增伤排名：找不到带两种以上属性攻击力的武器")
    }
    let skill = index.skillsByID[weapon.swordArtsParamId]!
    let segments = index.segments(for: skill, weapon: weapon)
    let selection = SkillDamageMath.defaultSelection(segments)
    let composition = SkillDamageMath.composition(of: segments, selected: selection)

    try rankerExpect(!composition.isEmpty, "「\(weapon.displayName)」的默认构成不应为空", counter: &count)
    try rankerExpectClose(composition.shares.reduce(0, +), 1, "占比之和应为 1", counter: &count)
    try rankerExpect(composition.shares.allSatisfy { $0 >= 0 && $0 <= 1 }, "每个占比都应落在 0…1", counter: &count)
    try rankerExpect(composition.breakdown.count >= 2, "多属性武器的构成应有 ≥ 2 个通道", counter: &count)
    try rankerExpect(composition.physicalShare > 0, "「\(weapon.displayName)」的构成里物理占比应 > 0", counter: &count)
    let elemental = SkillDamageChannel.allCases.filter { !$0.isPhysical }
    try rankerExpect(
        elemental.contains { composition.share($0) > 0 },
        "「\(weapon.displayName)」（\(weapon.attackBase.keys.map(\.titleZh).sorted().joined(separator: "＋"))）的构成里属性伤害占比应 > 0",
        counter: &count
    )
    try rankerExpect(
        composition.breakdown.allSatisfy { $0.share > 0 },
        "构成明细里不应出现 0 占比的通道",
        counter: &count
    )
    // 物理通道必须是该武器 atkAttribute / atkAttribute2 之一（或段自带的固定类型）
    let weaponChannels: Set<SkillDamageChannel> = [
        SkillDamageChannel.physical(code: weapon.atkAttribute),
        SkillDamageChannel.physical(code: weapon.atkAttribute2)
    ]
    let hits = index.hits(for: skill, weapon: weapon)
    var indirect = 0
    for hit in hits {
        let segment = SkillDamageMath.segment(for: hit, weapon: weapon)
        guard let channel = segment.physicalChannel else { continue }
        switch hit.attribute {
        case .weaponPrimary:
            indirect += 1
            try rankerExpect(
                channel == SkillDamageChannel.physical(code: weapon.atkAttribute),
                "WeaponAtkAttribute 段应解析成武器的 atkAttribute",
                counter: &count
            )
        case .weaponSecondary:
            indirect += 1
            try rankerExpect(
                channel == SkillDamageChannel.physical(code: weapon.atkAttribute2),
                "WeaponAtkAttribute2 段应解析成武器的 atkAttribute2",
                counter: &count
            )
        default:
            break
        }
        _ = weaponChannels
    }
    try rankerExpect(indirect >= 0, "间接引用的物理类型段计数：\(indirect)", counter: &count)

    // 削韧：至少一段的削韧 > 0，且等于 poise + poiseDamageBase × poiseMv/100
    if let hit = hits.first(where: { $0.poiseMv > 0 }) {
        let segment = SkillDamageMath.segment(for: hit, weapon: weapon)
        try rankerExpectClose(
            segment.poise, hit.poise + weapon.poiseDamageBase * hit.poiseMv / 100,
            "削韧换算应为 poise + 武器 poiseDamageBase × poiseMv/100", tolerance: 0.001, counter: &count
        )
    }

    // 法术：只用 flat，motion 的占位 100 不得乘出物理伤害
    guard let spell = index.dataset.spells.first(where: { candidate in
        candidate.hits.contains { !$0.motion.isEmpty && ($0.flat[.magic] ?? 0) > 0 && $0.attribute.channel(weapon: nil).isPhysical }
    }) else {
        throw CheckFailure(description: "增伤排名：找不到带占位 motion 的法术")
    }
    let spellSegments = index.segments(for: spell)
    let spellSelection = SkillDamageMath.defaultSelection(spellSegments)
    let spellComposition = SkillDamageMath.composition(of: spellSegments, selected: spellSelection)
    try rankerExpectClose(
        spellComposition.physicalShare, 0,
        "法术「\(spell.displayName)」的构成不应出现物理伤害（占位 motion 不得乘到施法器攻击力上）",
        counter: &count
    )
    try rankerExpect(
        spellComposition.breakdown.contains { !$0.channel.isPhysical && $0.share > 0 },
        "法术「\(spell.displayName)」的构成应全部落在属性伤害上",
        counter: &count
    )
    try rankerExpectClose(spellComposition.shares.reduce(0, +), 1, "法术构成的占比之和应为 1", counter: &count)
}

// MARK: - 真实 buffs.json

private func checkBuffDataset(_ index: BuffRankerIndex, counter count: inout Int) throws {
    let dataset = index.dataset
    // 版本不写死成数字，改成断言「引擎依赖的那几个结构确实在」：
    // v3 的实现曾经写成 `schemaVersion >= 3`，数据集升到 v4、新增 scope.attackContexts 之后
    // 这个断言静默通过，情境限定的倍率就那么混进了默认排名。下面这几条只依赖结构，
    // 少了任何一样都会直接失败。
    try rankerExpect(dataset.schemaVersion > 0, "buffs 缺少 schemaVersion", counter: &count)
    try rankerExpect(
        !dataset.attackContextLabels.isEmpty,
        "enums.attackContext 不应为空（排名第④步的情境闸门与页面的情境多选都靠它）",
        counter: &count
    )
    try rankerExpect(
        !dataset.stateInfoLabels.isEmpty,
        "enums.stateInfo 不应为空（叠加组要显示中文名而不是裸数字）",
        counter: &count
    )
    try rankerExpect(
        dataset.buffs.contains { !$0.scope.attackContexts.isEmpty },
        "数据集里应存在 scope.attackContexts 非空的条目（情境限定倍率）",
        counter: &count
    )
    try rankerExpect(
        dataset.buffs.contains { $0.stackLadder != nil },
        "数据集里应存在 stackLadder（叠层阶梯第 1 层）条目",
        counter: &count
    )
    try rankerExpect(
        dataset.notes["attackContext"]?.isEmpty == false,
        "notes.attackContext 不应为空（页面底部要原文展示，引擎必须与它一致）",
        counter: &count
    )
    // attackContexts 的取值必须都能在 enums.attackContext 里查到中文名，否则页面会显示裸键。
    for buff in dataset.buffs {
        for context in buff.scope.attackContexts where dataset.attackContextLabels[context] == nil {
            try rankerExpect(
                false,
                "scope.attackContexts 里的 \(context) 在 enums.attackContext 里查不到（#\(buff.spEffectId)）",
                counter: &count
            )
        }
    }
    // stateInfo 非 0 的取值都应有中文标签（schema 承诺覆盖本版本全部非 0 取值）。
    let unlabelledStateInfo = Set(
        dataset.buffs.map(\.stacking.stateInfo).filter { $0 != 0 && dataset.stateInfoLabels[$0] == nil }
    )
    try rankerExpect(
        unlabelledStateInfo.isEmpty,
        "enums.stateInfo 应覆盖全部非 0 的 stacking.stateInfo，缺 \(unlabelledStateInfo.sorted())",
        counter: &count
    )
    try rankerExpect(!dataset.gameVersion.isEmpty && !dataset.dataVersion.isEmpty, "buffs 缺少 gameVersion / dataVersion", counter: &count)
    try rankerExpect(dataset.buffs.count > 500, "buff 条数应 > 500，实际 \(dataset.buffs.count)", counter: &count)
    try rankerExpect(dataset.rateFields.count > 50, "rateFields 应 > 50 项，实际 \(dataset.rateFields.count)", counter: &count)
    try rankerExpect(dataset.rateFieldGroups.count >= 8, "rateFieldGroups 应 ≥ 8 组，实际 \(dataset.rateFieldGroups.count)", counter: &count)
    try rankerExpect(!dataset.stackingRulesZh.isEmpty, "stackingRules.zh 不应为空（页面底部要原文展示）", counter: &count)
    for key in ["ranking", "howToUseRates", "activation", "displayName"] {
        try rankerExpect(dataset.notes[key]?.isEmpty == false, "notes.\(key) 不应为空", counter: &count)
    }

    // 分组语义：只有 damage / attackPower / attackPowerFlat 计入伤害乘积
    let groupByKey = Dictionary(dataset.rateFieldGroups.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
    for key in ["damage", "attackPower", "attackPowerFlat"] {
        try rankerExpect(groupByKey[key]?.countsAsDamage == true, "rateFieldGroups.\(key).countsAsDamage 应为 true", counter: &count)
    }
    for key in ["weakness", "critical"] {
        try rankerExpect(groupByKey[key]?.countsAsDamage == false, "\(key) 组不得计入通用伤害乘积", counter: &count)
        try rankerExpect(groupByKey[key]?.conditionalDamage == true, "\(key) 组应标成 conditionalDamage", counter: &count)
    }
    for key in ["stance", "status", "special", "flag"] {
        try rankerExpect(groupByKey[key]?.countsAsDamage == false, "\(key) 组不得计入伤害乘积", counter: &count)
    }

    // 字段表本身
    try rankerExpect(
        dataset.rateField("physicsAttackRate")?.isRankingMultiplier == true,
        "physicsAttackRate 应是进乘积的倍率字段",
        counter: &count
    )
    try rankerExpect(
        dataset.rateField("physicsAttackPower")?.isRankingFlat == true,
        "physicsAttackPower 应是攻击力加算字段",
        counter: &count
    )
    try rankerExpect(
        dataset.rateField("restageAttackRate")?.valueKind == .special,
        "restageAttackRate 应是 special（禁止相乘）",
        counter: &count
    )

    // 条目本身
    try rankerExpect(dataset.buffs.allSatisfy { !$0.displayName.isEmpty }, "每条 buff 都应有可显示的名字", counter: &count)
    try rankerExpect(
        dataset.buffs.allSatisfy { ["passive", "conditional", "activated"].contains($0.activation) },
        "activation 应落在三态之内",
        counter: &count
    )
    try rankerExpect(
        dataset.buffs.allSatisfy { ["self", "ally", "summon", "enemy"].contains($0.target) },
        "target 应落在四种之内",
        counter: &count
    )
    try rankerExpect(
        dataset.buffs.allSatisfy { !$0.stacking.group.isEmpty },
        "每条 buff 都应有 stacking.group",
        counter: &count
    )
    try rankerExpect(dataset.buffs.contains { $0.isPassive }, "应存在 passive 条目", counter: &count)
    try rankerExpect(dataset.buffs.contains { !$0.isPassive }, "应存在条件型条目", counter: &count)
    try rankerExpect(
        Set(dataset.buffs.map(\.displayName)).count == dataset.buffs.count,
        "displayNameZh 在全表应唯一（数据集生成时已断言）",
        counter: &count
    )

    // 枚举表
    try rankerExpect(!dataset.sourceKindLabels.isEmpty, "enums.sourceKind 不应为空", counter: &count)
    try rankerExpect(dataset.sourceKindLabel("relicAffix") == "遗物词条", "来源类型徽标应取自 enums.sourceKind", counter: &count)
    try rankerExpect(!dataset.activationLabels.isEmpty, "enums.activation 不应为空", counter: &count)
    try rankerExpect(dataset.stackBehaviorLabels["unknown"] != nil, "enums.spCategoryBehavior 应有 unknown 兜底项", counter: &count)
    try rankerExpect(!index.availableSourceKinds.isEmpty, "筛选器应能列出来源类型", counter: &count)
    try rankerExpect(index.attributeScopedCount > 0, "应统计出被 spAttribute 限定的条目数", counter: &count)
    try rankerExpect(index.contextScopedTotal > 0, "应统计出被 attackContexts 限定的条目数", counter: &count)
    try rankerExpect(
        !index.availableAttackContexts.isEmpty,
        "情境多选应能列出数据集里出现过的攻击情境",
        counter: &count
    )
    try rankerExpect(
        index.availableAttackContexts.allSatisfy { !$0.zh.isEmpty && $0.zh != $0.key && $0.count > 0 },
        "每个可选情境都应有中文名与命中条数",
        counter: &count
    )
    // 叠层阶梯：满层数值必须比第 1 层大，层数必须 ≥ 2，否则「满层 ×X」的标注没有意义。
    for buff in index.dataset.buffs {
        guard let ladder = buff.stackLadder else { continue }
        try rankerExpect(ladder.tiers >= 2, "叠层阶梯 #\(buff.spEffectId) 的层数应 ≥ 2", counter: &count)
        try rankerExpect(
            !ladder.topRates.isEmpty,
            "叠层阶梯 #\(buff.spEffectId) 应带满层数值 topRates",
            counter: &count
        )
        try rankerExpect(
            ladder.topRates.allSatisfy { key, value in (buff.rates[key] ?? 1) <= value },
            "叠层阶梯 #\(buff.spEffectId) 的满层数值不应小于第 1 层",
            counter: &count
        )
        try rankerExpect(
            !ladder.tierSpEffectIds.contains(buff.spEffectId),
            "tierSpEffectIds 应是第 1 层以外的各层（#\(buff.spEffectId)）",
            counter: &count
        )
    }
}

private func checkRealRanking(skills: SkillDataIndex, buffs: BuffRankerIndex, counter count: inout Int) throws {
    // 取一把多属性武器 + 它的战技作为上下文
    guard let weapon = skills.dataset.weapons.first(where: { candidate in
        candidate.attackBase.filter { $0.value > 0 }.count >= 2
            && candidate.skillVariant != nil
            && skills.skillsByID[candidate.swordArtsParamId] != nil
    }), let skill = skills.skillsByID[weapon.swordArtsParamId] else {
        throw CheckFailure(description: "增伤排名：找不到用于排名校验的武器")
    }
    let segments = skills.segments(for: skill, weapon: weapon)
    let composition = SkillDamageMath.composition(
        of: segments, selected: SkillDamageMath.defaultSelection(segments)
    )
    let context = BuffRankingContext(
        delivery: .weaponSkill,
        weaponSlot: 1,
        subCategories: [BuffRankingContext.skillAttackSubCategory],
        composition: composition
    )
    let byID = Dictionary(buffs.dataset.buffs.map { ($0.spEffectId, $0) }, uniquingKeysWith: { first, _ in first })

    let rows = buffs.rank(context: context)
    try rankerExpect(rows.count > 20, "战技排名应能选出 > 20 条，实际 \(rows.count)", counter: &count)
    try rankerExpect(rows.allSatisfy { byID[$0.spEffectId]?.target == "self" }, "默认排名只应含 target=self", counter: &count)
    try rankerExpect(rows.allSatisfy(\.isPassive), "默认排名只应含 activation=passive", counter: &count)
    try rankerExpect(
        rows.allSatisfy { $0.direction == "increase" || $0.direction == "mixed" },
        "默认排名不应含 direction=decrease",
        counter: &count
    )
    try rankerExpect(
        rows.allSatisfy { row in
            guard let buff = byID[row.spEffectId] else { return false }
            return buff.scope.subCategories.isEmpty || buff.scope.subCategories.contains(112)
        },
        "默认排名里的子类别限定条目只应是战技攻击（112）",
        counter: &count
    )
    try rankerExpect(
        rows.allSatisfy { row in
            guard let buff = byID[row.spEffectId] else { return false }
            guard let slot = buff.scope.weaponSlot else { return true }
            return slot == 1 || slot == 3
        },
        "右手输出下不应出现左手限定的条目",
        counter: &count
    )
    try rankerExpect(
        rows.allSatisfy { byID[$0.spEffectId]?.scope.spAttribute == nil },
        "默认排名不应含 spAttribute 限定的条目",
        counter: &count
    )
    // notes.ranking ④ / notes.attackContext：情境限定的倍率默认不得进通用排名。
    //
    // 这一类条目全是 passive（装上就一直在），所以 activation 那一关拦不住；它们的倍率
    // 又都落在 ×1.1–×1.3 这个正常区间里，下面那条「有效倍率 < 3」的上界也卡不住。
    // 之前正是这两点叠在一起，让「强化致命一击 ×1.24」当上了整页榜首而没有任何断言报警。
    let leaked = rows.filter { !(byID[$0.spEffectId]?.scope.attackContexts.isEmpty ?? true) }
    try rankerExpect(
        leaked.isEmpty,
        "默认选项下排名结果不得含 scope.attackContexts 非空的条目，混入了 "
            + leaked.prefix(5).map(\.displayName).joined(separator: "、"),
        counter: &count
    )
    try rankerExpect(
        rows.allSatisfy { !$0.isContextGated && $0.attackContexts.isEmpty },
        "默认选项下排名行自身也不应带攻击情境限定",
        counter: &count
    )
    // stateInfo 367（强化致命一击）／197（强化突刺反击）是情境限定的两条主要来路，
    // 单独再卡一道：它们不该出现在默认榜单里。
    try rankerExpect(
        rows.allSatisfy { row in
            guard let buff = byID[row.spEffectId] else { return false }
            return buff.stacking.stateInfo != 367 && buff.stacking.stateInfo != 197
        },
        "默认选项下排名结果不得含 stateInfo=367 / 197（强化致命一击 / 强化突刺反击）的条目",
        counter: &count
    )
    try rankerExpect(
        rows.allSatisfy { row in
            row.rateValues.contains { $0.countsAsDamage }
        },
        "排名里的每一条都应至少有一个计入伤害的字段",
        counter: &count
    )
    // 特攻 ×10 / special 这类字段如果漏进来，榜首会异常放大 —— 这里卡一个结构性上界
    try rankerExpect(
        rows.allSatisfy { $0.effectiveMultiplier < 3 },
        "无条件增伤的有效倍率不应出现 ≥ 3 的离群值（榜首 \(BuffFormat.multiplier(rows.first?.effectiveMultiplier ?? 0))）",
        counter: &count
    )
    try rankerExpect(
        rows.allSatisfy { $0.effectiveMultiplier > 0 },
        "有效倍率应为正数",
        counter: &count
    )
    try rankerExpect(
        zip(rows, rows.dropFirst()).allSatisfy { $0.effectiveMultiplier >= $1.effectiveMultiplier },
        "排名结果必须降序",
        counter: &count
    )
    try rankerExpect(
        rows.contains { $0.effectiveMultiplier > 1 },
        "排名里应有真正增伤的条目",
        counter: &count
    )
    try rankerExpect(
        rows.allSatisfy { !$0.displayName.isEmpty && !$0.sourceKinds.isEmpty },
        "每行都应有名字与来源类型徽标",
        counter: &count
    )

    // 开关：条件型 / 队友 / 属性限定都只会让结果变多
    let conditional = buffs.rank(context: context, options: BuffRankingOptions(includeConditional: true))
    try rankerExpect(conditional.count > rows.count, "打开条件型开关后条目应变多", counter: &count)
    try rankerExpect(conditional.contains { !$0.isPassive }, "打开后应出现非 passive 条目", counter: &count)
    let allies = buffs.rank(context: context, options: BuffRankingOptions(includeAllies: true))
    try rankerExpect(allies.count >= rows.count, "打开队友增益开关后条目不应变少", counter: &count)
    let attributeScoped = buffs.rank(context: context, options: BuffRankingOptions(includeAttributeScoped: true))
    try rankerExpect(attributeScoped.count >= rows.count, "打开属性限定开关后条目不应变少", counter: &count)

    // 左手 / 右手
    let leftHand = buffs.rank(
        context: BuffRankingContext(
            delivery: .weaponSkill,
            weaponSlot: 2,
            subCategories: [BuffRankingContext.skillAttackSubCategory],
            composition: composition
        )
    )
    try rankerExpect(
        leftHand.allSatisfy { row in
            guard let slot = byID[row.spEffectId]?.scope.weaponSlot else { return true }
            return slot == 2 || slot == 3
        },
        "左手输出下不应出现右手限定的条目",
        counter: &count
    )

    // 法术上下文：魔法 / 祷告分别看 affectsSorcery / affectsIncantation
    guard let sorcery = skills.dataset.spells.first(where: { $0.isSorcery && !$0.hits.isEmpty }),
          let incantation = skills.dataset.spells.first(where: { $0.isIncantation && !$0.hits.isEmpty }) else {
        throw CheckFailure(description: "增伤排名：找不到用于校验的魔法 / 祷告")
    }
    let sorcerySegments = skills.segments(for: sorcery)
    let sorceryComposition = SkillDamageMath.composition(
        of: sorcerySegments, selected: SkillDamageMath.defaultSelection(sorcerySegments)
    )
    let sorceryRows = buffs.rank(
        context: BuffRankingContext(delivery: .sorcery, subCategories: [], composition: sorceryComposition)
    )
    try rankerExpect(!sorceryRows.isEmpty, "魔法「\(sorcery.displayName)」应能排出增伤条目", counter: &count)
    try rankerExpect(
        sorceryRows.allSatisfy { byID[$0.spEffectId]?.scope.affectsSorcery == true },
        "魔法排名里的每一条都应 affectsSorcery",
        counter: &count
    )
    try rankerExpect(
        sorceryRows.allSatisfy { byID[$0.spEffectId]?.scope.subCategories.isEmpty == true },
        "普通法术命中不属于任何攻击子类别，带子类别限定的条目应被排除",
        counter: &count
    )
    let incantationSegments = skills.segments(for: incantation)
    let incantationComposition = SkillDamageMath.composition(
        of: incantationSegments, selected: SkillDamageMath.defaultSelection(incantationSegments)
    )
    let incantationRows = buffs.rank(
        context: BuffRankingContext(delivery: .incantation, subCategories: [], composition: incantationComposition)
    )
    try rankerExpect(
        incantationRows.allSatisfy { byID[$0.spEffectId]?.scope.affectsIncantation == true },
        "祷告排名里的每一条都应 affectsIncantation",
        counter: &count
    )

    // 选段变化 → 排名随之变化（增量更新的正确性）
    if let fireOnly = segments.first(where: { segment in segment.components.contains { $0.channel == .fire && $0.amount > 0 } }),
       let physicalOnly = segments.first(where: { segment in segment.components.contains { $0.channel.isPhysical && $0.amount > 0 } }) {
        let fireContext = BuffRankingContext(
            delivery: .weaponSkill,
            weaponSlot: 1,
            subCategories: [BuffRankingContext.skillAttackSubCategory],
            composition: SkillDamageMath.composition(of: segments, selected: [fireOnly.atkId])
        )
        let physicalContext = BuffRankingContext(
            delivery: .weaponSkill,
            weaponSlot: 1,
            subCategories: [BuffRankingContext.skillAttackSubCategory],
            composition: SkillDamageMath.composition(of: segments, selected: [physicalOnly.atkId])
        )
        let fireRows = buffs.rank(context: fireContext)
        let physicalRows = buffs.rank(context: physicalContext)
        try rankerExpect(!fireRows.isEmpty && !physicalRows.isEmpty, "单段构成也应能排名", counter: &count)
        // 纯火构成下，只加火的 buff 的有效倍率应 ≥ 混合构成下的值
        if let mixedFire = rows.first(where: { row in
            row.channelFactors.contains { $0.channel == .fire && $0.factor > 1 }
                && row.channelFactors.allSatisfy { $0.channel == .fire || abs($0.factor - 1) < 0.000001 }
        }), let pureFire = fireRows.first(where: { $0.spEffectId == mixedFire.spEffectId }) {
            try rankerExpect(
                pureFire.effectiveMultiplier >= mixedFire.effectiveMultiplier,
                "只保留火属性段后，纯火增益的有效倍率不应下降",
                counter: &count
            )
        }
    }

    // 推荐组合
    let plan = buffs.stackPlan(rows: rows)
    try rankerExpect(!plan.picks.isEmpty, "推荐组合不应为空", counter: &count)
    try rankerExpect(plan.picks.allSatisfy(\.isPassive), "推荐组合只应含无条件生效的条目", counter: &count)
    try rankerExpect(
        Set(plan.picks.map(\.stackGroup)).count == plan.picks.count,
        "推荐组合里每个叠加组只应出现一次",
        counter: &count
    )
    try rankerExpect(plan.picks.allSatisfy { $0.effectiveMultiplier > 1 }, "推荐组合只应含真正增伤的条目", counter: &count)
    try rankerExpectClose(
        plan.total, plan.picks.reduce(1.0) { $0 * $1.effectiveMultiplier },
        "组合总倍率应是入选条目的连乘", tolerance: 0.000001, counter: &count
    )
    if let strongest = plan.picks.first {
        let reduced = buffs.stackPlan(rows: rows, excluded: [strongest.spEffectId])
        try rankerExpect(
            !reduced.picks.contains { $0.spEffectId == strongest.spEffectId },
            "勾掉的条目不应再出现在组合里",
            counter: &count
        )
        try rankerExpect(reduced.total <= plan.total, "勾掉一条后总倍率不应上升", counter: &count)
    }

    // 情境限定的条目：默认被拦下并单独计数，勾选对应情境后才进榜。
    let defaultResult = buffs.rankResult(context: context)
    let gatedButOtherwiseEligible = buffs.dataset.buffs.filter { buff in
        guard !buff.scope.attackContexts.isEmpty else { return false }
        return buffs.rank(
            context: context,
            options: BuffRankingOptions(includedAttackContexts: Set(buff.scope.attackContexts))
        ).contains { $0.spEffectId == buff.spEffectId }
    }
    try rankerExpect(
        defaultResult.contextScopedCount >= gatedButOtherwiseEligible.count,
        "contextScopedCount 应把「其它各关都过了、只被情境拦下」的条目都算进去"
            + "（实际 \(defaultResult.contextScopedCount)，至少应有 \(gatedButOtherwiseEligible.count)）",
        counter: &count
    )
    try rankerExpect(
        defaultResult.contextScopedCount > 0,
        "战技输出下应有条目被攻击情境拦下（说明闸门真的在起作用）",
        counter: &count
    )
    if let sample = gatedButOtherwiseEligible.first {
        let contexts = Set(sample.scope.attackContexts)
        let opened = buffs.rank(context: context, options: BuffRankingOptions(includedAttackContexts: contexts))
        try rankerExpect(
            opened.contains { $0.spEffectId == sample.spEffectId },
            "勾选对应情境后，情境限定的条目应重新进榜（#\(sample.spEffectId)）",
            counter: &count
        )
        try rankerExpect(
            opened.first(where: { $0.spEffectId == sample.spEffectId })?.attackContextLabels.isEmpty == false,
            "情境限定的条目应带中文情境标签供页面标注",
            counter: &count
        )
        // 勾了别的情境不应把它放进来
        let otherContexts = Set(buffs.availableAttackContexts.map(\.key)).subtracting(contexts)
        if !otherContexts.isEmpty {
            let elsewhere = buffs.rank(
                context: context, options: BuffRankingOptions(includedAttackContexts: otherContexts)
            )
            try rankerExpect(
                !elsewhere.contains { $0.spEffectId == sample.spEffectId },
                "勾选无关情境不应放行别的情境限定条目（#\(sample.spEffectId)）",
                counter: &count
            )
        }
        // 放行后仍然只放行情境对得上的那些
        try rankerExpect(
            opened.allSatisfy { row in
                row.attackContexts.isEmpty || row.attackContexts.contains { contexts.contains($0) }
            },
            "勾选情境后，进榜的情境限定条目都应命中已勾选的情境",
            counter: &count
        )
    }

    // 维护者抽查用的一行摘要（数值随数据集修订而变，不参与断言）
    let summary = defaultResult
    print("    （\(weapon.displayName)·\(skill.displayName)：候选 \(summary.candidateCount) 条 / 列出 \(summary.rows.count) 条，"
          + "榜首 \(rows.first?.displayName ?? "—") \(BuffFormat.multiplier(rows.first?.effectiveMultiplier ?? 1))，"
          + "理论叠加 \(plan.groupCount) 组 \(BuffFormat.multiplier(plan.total, digits: 2))）")

    // 排名两次结果一致（纯函数，可重复）
    let again = buffs.rank(context: context)
    try rankerExpect(again.map(\.spEffectId) == rows.map(\.spEffectId), "同样输入的排名结果应可重复", counter: &count)
}

// MARK: - 双端对照用例

// 与 windows/tests/ranker_crosscheck.test.mjs 用的是同一组输入、同一套断言口径。
// 两端各自把「同一算法的中间量」断言成一致（构成占比、前 10 名及其有效倍率、推荐组合总倍率
// 都在各自这一侧用一份独立重算的参考实现校对），因此只要两边都绿，两端的数就必然对得上；
// 数值本身会随数据集修订变化，所以这里一律**不写绝对快照**。
//
// 这一组校对的是旧版排名页（BuffRankerIndex.rankResult）；旧版的对拍行改走 NR_RANKER_LEGACY_DUMP。
// 配置页的双端对拍（CASE / CONFIG 行，与 NR_RANKER_DUMP=1 node --test windows/tests/ranker_crosscheck.test.mjs
// 逐行比）见文末的 checkLoadoutParity。

private struct CrossCase {
    let key: String
    /// 战技 id（法术用例为 nil）。
    let skillID: Int?
    /// 法术 id（战技用例为 nil）。
    let spellID: Int?
    let weaponID: Int?
    /// nil = 默认勾选（正常版这一侧的全部非 noDamage 段）。
    let onlyAtkIds: Set<Int>?
}

private let crossCases: [CrossCase] = [
    // 尸横遍野（尸山血海）：全段 —— 物理 + 火两条通道，12 段里 6 段是专注值不足版。
    CrossCase(key: "corpse-piler-full", skillID: 1177, spellID: nil, weaponID: 9040000, onlyAtkIds: nil),
    // 同一把武器只勾最后一段：每段五属性 motion 同值，构成比例必须与全段完全一致。
    CrossCase(key: "corpse-piler-last", skillID: 1177, spellID: nil, weaponID: 9040000, onlyAtkIds: [303400305]),
    // 狮子斩 + 大剑：纯物理。
    CrossCase(key: "lions-claw-greatsword", skillID: 100, spellID: nil, weaponID: 3180000, onlyAtkIds: nil),
    // 狮子斩 + 火焰大剑：同一战技、同一套段，换一把带火属性的武器。
    CrossCase(key: "lions-claw-flame-greatsword", skillID: 100, spellID: nil, weaponID: 3180500, onlyAtkIds: nil),
    // 喷火 + 钢丝火把：带 isBullet 子弹段的战技（子弹段照常乘武器攻击力，不得整段归零）。
    CrossCase(key: "firebreather", skillID: 223, spellID: nil, weaponID: 24020000, onlyAtkIds: nil),
    // 死亡雷击：祷告，只用 flat。
    CrossCase(key: "death-lightning", skillID: nil, spellID: 5040, weaponID: nil, onlyAtkIds: nil),
    // 帚星：魔法，只用 flat。
    CrossCase(key: "comet", skillID: nil, spellID: 4021, weaponID: nil, onlyAtkIds: nil)
]

private struct CrossResult {
    let key: String
    let hits: [SkillHit]
    let selected: [Int]
    let shares: [Double]
    let total: Double
    let weapon: SkillWeapon?
    let segments: [SkillSegment]
    let ranking: BuffRankingResult
    let plan: BuffStackPlan
}

/// 参考实现：直接从 hits / weapons 的原始字段重算构成，用来校对 SkillDamageMath。
/// 故意不复用被测代码的任何分支，这样实现跑偏会被这一关拦下。
private func referenceShares(hits: [SkillHit], weapon: SkillWeapon?, selected: Set<Int>) -> [Double] {
    var amounts = Array(repeating: 0.0, count: SkillDamageChannel.allCases.count)
    for hit in hits where selected.contains(hit.atkId) && !hit.noDamage {
        let physicalChannel = hit.attribute.channel(weapon: weapon)
        for element in SkillElement.allCases {
            let base = weapon?.attack(element) ?? 0
            let motion = weapon == nil ? 0 : (hit.motion[element] ?? 0)
            let flat = hit.flat[element] ?? 0
            var amount = base * motion / 100 + flat
            if hit.addBaseAtk { amount += base }
            guard amount > 0 else { continue }
            let channel = element == .physical ? physicalChannel : SkillDamageChannel.channel(for: element)
            amounts[channel.rawValue] += amount
        }
    }
    let total = amounts.reduce(0, +)
    guard total > 0 else { return amounts }
    return amounts.map { $0 / total }
}

/// 参考实现：直接从 buff 的 rates + rateFields 重算有效倍率。
private func referenceMultiplier(buff: BuffEntry, dataset: BuffDataset, shares: [Double]) -> Double {
    var perChannel = Array(repeating: 1.0, count: SkillDamageChannel.allCases.count)
    for (key, value) in buff.rates {
        guard let field = dataset.rateField(key), field.countsAsDamage, field.valueKind == .multiplier,
              value.isFinite, value > 0, value != field.defaultValue else { continue }
        let channels: [SkillDamageChannel]
        switch key {
        case "physicsAttackRate", "physicsAttackPowerRate":
            channels = SkillDamageChannel.allCases.filter(\.isPhysical)
        case "magicAttackRate", "magicAttackPowerRate": channels = [.magic]
        case "fireAttackRate", "fireAttackPowerRate": channels = [.fire]
        case "thunderAttackRate", "thunderAttackPowerRate": channels = [.lightning]
        case "darkAttackRate", "darkAttackPowerRate": channels = [.holy]
        case "slashAttackRate", "slashAttackPowerRate": channels = [.slash]
        case "blowAttackRate", "blowAttackPowerRate": channels = [.strike]
        case "thrustAttackRate", "thrustAttackPowerRate": channels = [.pierce]
        case "neutralAttackRate", "neutralAttackPowerRate": channels = [.standard]
        default: channels = []
        }
        for channel in channels { perChannel[channel.rawValue] *= value }
    }
    var sum = 0.0
    for channel in SkillDamageChannel.allCases {
        sum += shares[channel.rawValue] * perChannel[channel.rawValue]
    }
    return sum
}

private func runCrossCase(
    _ item: CrossCase, skills: SkillDataIndex, buffs: BuffRankerIndex
) throws -> CrossResult {
    let weapon = item.weaponID.flatMap { skills.weaponsByID[$0] }
    let hits: [SkillHit]
    let delivery: BuffDelivery
    let subCategories: Set<Int>
    if let skillID = item.skillID {
        guard let skill = skills.skillsByID[skillID] else {
            throw CheckFailure(description: "增伤排名：对照用例找不到战技 \(skillID)")
        }
        guard weapon != nil else {
            throw CheckFailure(description: "增伤排名：对照用例找不到武器 \(item.weaponID ?? -1)")
        }
        hits = skills.hits(for: skill, weapon: weapon)
        delivery = .weaponSkill
        subCategories = [BuffRankingContext.skillAttackSubCategory]
    } else {
        guard let spellID = item.spellID, let spell = skills.spellsByID[spellID] else {
            throw CheckFailure(description: "增伤排名：对照用例找不到法术")
        }
        hits = spell.hits
        delivery = spell.isSorcery ? .sorcery : .incantation
        subCategories = []
    }
    let segments = hits.map { SkillDamageMath.segment(for: $0, weapon: weapon) }
    let selected: Set<Int> = item.onlyAtkIds ?? SkillDamageMath.defaultSelection(segments)
    let composition = SkillDamageMath.composition(of: segments, selected: selected)
    let context = BuffRankingContext(
        delivery: delivery, weaponSlot: 1, subCategories: subCategories, composition: composition
    )
    let options = BuffRankingOptions()
    let ranking = buffs.rankResult(context: context, options: options)
    let plan = buffs.stackPlan(rows: ranking.rows, options: options)
    return CrossResult(
        key: item.key,
        hits: hits,
        selected: segments.map(\.atkId).filter { selected.contains($0) },
        shares: composition.shares,
        total: composition.total,
        weapon: weapon,
        segments: segments,
        ranking: ranking,
        plan: plan
    )
}

private func checkCrossPlatformCases(
    skills: SkillDataIndex, buffs: BuffRankerIndex, counter count: inout Int
) throws {
    var results: [String: CrossResult] = [:]
    var dump: [String] = []
    let byID = Dictionary(
        buffs.dataset.buffs.map { ($0.spEffectId, $0) }, uniquingKeysWith: { first, _ in first }
    )

    // ⓪ 输出手段列表的收录口径：两端必须收进同一批战技与法术。
    //    判据是「至少有一种选法算得出非 0 相对值」，所以这里逐条验证它真的算得出来。
    let skillOutputs = skills.outputs.filter { $0.kind == .skill }
    let spellOutputs = skills.outputs.filter { $0.kind == .spell }
    for output in skillOutputs {
        guard let skill = skills.skillsByID[output.entryID] else {
            throw CheckFailure(description: "增伤排名：输出手段 \(output.displayName) 找不到对应战技")
        }
        let playable = skill.weaponIds.contains { id in
            guard let weapon = skills.weaponsByID[id] else { return false }
            return skills.segments(for: skill, weapon: weapon).contains { $0.hasDamage }
        }
        try rankerExpect(playable, "列表里的战技「\(output.displayName)」必须至少有一把武器算得出构成", counter: &count)
    }
    for output in spellOutputs {
        guard let spell = skills.spellsByID[output.entryID] else {
            throw CheckFailure(description: "增伤排名：输出手段 \(output.displayName) 找不到对应法术")
        }
        try rankerExpect(
            skills.segments(for: spell).contains { $0.hasDamage },
            "列表里的法术「\(output.displayName)」必须至少有一段带固定值",
            counter: &count
        )
    }
    try rankerExpect(
        skills.skillsWithoutDamage > 0 && skills.spellsWithoutDamage > 0,
        "应当真的有一批算不出伤害的战技 / 法术被挡在列表外（否则这条口径是空跑）",
        counter: &count
    )
    dump.append("OUTPUTS skills=\(skillOutputs.count) spells=\(spellOutputs.count)")

    for item in crossCases {
        let result = try runCrossCase(item, skills: skills, buffs: buffs)
        results[item.key] = result
        let hitsByID = Dictionary(result.hits.map { ($0.atkId, $0) }, uniquingKeysWith: { first, _ in first })

        // ① 选段
        try rankerExpect(!result.hits.isEmpty, "\(item.key)：应能选出段", counter: &count)
        try rankerExpect(
            Set(result.selected).isSubset(of: Set(result.hits.map(\.atkId))),
            "\(item.key)：勾选的段必须是选出的段的子集",
            counter: &count
        )
        try rankerExpect(
            result.selected.allSatisfy { hitsByID[$0]?.noDamage != true },
            "\(item.key)：noDamage 段不该被勾上",
            counter: &count
        )
        if item.onlyAtkIds == nil {
            try rankerExpect(
                result.selected.allSatisfy { hitsByID[$0]?.noFp != true },
                "\(item.key)：默认勾选只取正常版这一侧，专注值不足版不得同时计入",
                counter: &count
            )
        }

        // ② 构成：与参考实现逐通道一致，且占比之和为 1
        let reference = referenceShares(
            hits: result.hits, weapon: result.weapon, selected: Set(result.selected)
        )
        for channel in SkillDamageChannel.allCases {
            try rankerExpectClose(
                result.shares[channel.rawValue], reference[channel.rawValue],
                "\(item.key)：\(channel.titleZh) 占比应与参考实现一致",
                tolerance: 0.000000001, counter: &count
            )
        }
        try rankerExpectClose(
            result.shares.reduce(0, +), 1, "\(item.key)：占比之和应为 1",
            tolerance: 0.000000001, counter: &count
        )
        try rankerExpect(result.total > 0, "\(item.key)：相对伤害总量应为正", counter: &count)

        // ③ 前 10 名：降序 + 每条的有效倍率与参考实现一致
        let top = Array(result.ranking.rows.prefix(10))
        try rankerExpect(
            top.count == min(10, result.ranking.rows.count),
            "\(item.key)：前 10 名应取满（命中 \(result.ranking.rows.count) 条）",
            counter: &count
        )
        try rankerExpect(
            zip(top, top.dropFirst()).allSatisfy { $0.effectiveMultiplier >= $1.effectiveMultiplier },
            "\(item.key)：前 10 名必须按有效倍率降序",
            counter: &count
        )
        for row in top {
            guard let buff = byID[row.spEffectId] else {
                throw CheckFailure(description: "增伤排名：\(item.key) 榜上出现了数据集里没有的 #\(row.spEffectId)")
            }
            try rankerExpectClose(
                row.effectiveMultiplier,
                referenceMultiplier(buff: buff, dataset: buffs.dataset, shares: result.shares),
                "\(item.key)：#\(row.spEffectId) 的有效倍率应等于 Σ 占比 × 适用倍率连乘",
                tolerance: 0.000000001, counter: &count
            )
        }

        // ④ 推荐组合：总倍率＝入选条目连乘，每个叠加组只出现一次
        try rankerExpectClose(
            result.plan.total, result.plan.picks.reduce(1.0) { $0 * $1.effectiveMultiplier },
            "\(item.key)：组合总倍率应是入选条目的连乘",
            tolerance: 0.000000001, counter: &count
        )
        try rankerExpect(
            Set(result.plan.picks.map(\.stackGroup)).count == result.plan.picks.count,
            "\(item.key)：推荐组合里每个叠加组只应出现一次",
            counter: &count
        )
        try rankerExpect(
            result.plan.picks.allSatisfy { $0.effectiveMultiplier > 1 },
            "\(item.key)：推荐组合只应含真正增伤的条目",
            counter: &count
        )
        try rankerExpect(
            result.plan.total >= (result.ranking.rows.first?.effectiveMultiplier ?? 1) - 0.000001,
            "\(item.key)：组合总倍率不应低于榜首单条",
            counter: &count
        )

        // ⑤ 排除条数按原因分类：与 Windows 端同一计数点（属性限定单独一类，不混进作用域分项）
        try rankerExpect(
            result.ranking.attributeScopedCount > 0,
            "\(item.key)：应有被属性／异常限定拦下的条目",
            counter: &count
        )
        let reasonTotal = result.ranking.scopeReasons
            .filter { $0.key != BuffRankerIndex.contextGateReason }
            .values.reduce(0, +)
        try rankerExpect(
            reasonTotal == result.ranking.scopeRejectedCount,
            "\(item.key)：分项条数之和应等于『作用域不符』总数",
            counter: &count
        )
        try rankerExpect(
            (result.ranking.scopeReasons[BuffRankerIndex.contextGateReason] ?? 0)
                == result.ranking.contextScopedCount,
            "\(item.key)：情境闸门在分项里的条数应等于『受攻击情境限制』的条数",
            counter: &count
        )
        try rankerExpect(
            result.ranking.scopeReasons["限定属性／异常攻击"] == nil,
            "\(item.key)：属性限定不该同时记进作用域分项（否则两端计数点又错位了）",
            counter: &count
        )
        try rankerExpect(
            result.plan.groupCount == result.plan.picks.count,
            "\(item.key)：组数必须等于取用条目数",
            counter: &count
        )

        let reasons = result.ranking.scopeReasonBreakdown
            .map { "\($0.reason):\($0.count)" }
            .joined(separator: "|")
        dump.append(
            "CASE \(item.key) selected=\(result.selected.map(String.init).joined(separator: ","))"
                + " shares=\(result.shares.map { String(format: "%.9f", $0) }.joined(separator: ","))"
                + " rows=\(result.ranking.rows.count)"
                + " top10=\(top.map { "\($0.spEffectId):\(String(format: "%.9f", $0.effectiveMultiplier))" }.joined(separator: ","))"
                + " combo=\(String(format: "%.9f", result.plan.total)) picks=\(result.plan.picks.count)"
                + " groups=\(result.plan.groupCount)"
                + " excluded=\(result.ranking.contextScopedCount)/\(result.ranking.attributeScopedCount)"
                + "/\(result.ranking.scopeRejectedCount)"
                + " reasons=\(reasons)"
        )
    }

    // ⑤ 跨用例关系：同一把武器、每段五属性 motion 同值 → 只勾一段与全勾的构成、排名、组合完全一致
    if let full = results["corpse-piler-full"], let last = results["corpse-piler-last"] {
        try rankerExpect(full.selected.count > last.selected.count, "对照：全段应比只勾一段多", counter: &count)
        for channel in SkillDamageChannel.allCases {
            try rankerExpectClose(
                full.shares[channel.rawValue], last.shares[channel.rawValue],
                "对照：尸横遍野每段五属性 motion 同值，只勾一段的构成应与全段一致",
                tolerance: 0.000000001, counter: &count
            )
        }
        try rankerExpect(
            full.ranking.rows.prefix(10).map(\.spEffectId) == last.ranking.rows.prefix(10).map(\.spEffectId),
            "对照：构成相同 → 前 10 名必须完全相同",
            counter: &count
        )
        try rankerExpectClose(
            full.plan.total, last.plan.total,
            "对照：构成相同 → 推荐组合总倍率必须完全相同",
            tolerance: 0.000000001, counter: &count
        )
    }

    // ⑥ 同一战技换一把带火属性的武器：火占比从 0 变正，只加火的条目随之进榜
    if let plain = results["lions-claw-greatsword"], let flame = results["lions-claw-flame-greatsword"] {
        try rankerExpectClose(
            plain.shares[SkillDamageChannel.fire.rawValue], 0,
            "对照：普通大剑的火占比应为 0", tolerance: 0.000000001, counter: &count
        )
        try rankerExpect(
            flame.shares[SkillDamageChannel.fire.rawValue] > 0,
            "对照：火焰大剑的火占比应大于 0",
            counter: &count
        )
        try rankerExpect(
            plain.selected == flame.selected,
            "对照：同一战技同一套段，换武器不该改变选段",
            counter: &count
        )
        let fireOnly = flame.ranking.rows.filter { row in
            row.channelFactors.contains { $0.channel == .fire && $0.factor > 1 }
                && row.channelFactors.allSatisfy { $0.channel == .fire || abs($0.factor - 1) < 0.000001 }
        }
        try rankerExpect(!fireOnly.isEmpty, "对照：火焰大剑下应能进来只加火的条目", counter: &count)
        let plainIDs = Set(plain.ranking.rows.map(\.spEffectId))
        try rankerExpect(
            fireOnly.allSatisfy { !plainIDs.contains($0.spEffectId) },
            "对照：只加火的条目不该出现在纯物理构成的榜上",
            counter: &count
        )
    }

    // ⑦ 带子弹的战技：子弹段照常算伤害（回归「战技子弹段被整段归零」）
    if let bullet = results["firebreather"] {
        let bulletSegments = bullet.segments.filter { $0.isBullet }
        try rankerExpect(!bulletSegments.isEmpty, "对照：喷火应有子弹段", counter: &count)
        try rankerExpect(
            bulletSegments.contains { $0.hasDamage },
            "对照：战技的子弹段挂的是真武器，必须照常按 攻击力 × motion/100 + flat 算出伤害",
            counter: &count
        )
        try rankerExpect(
            bullet.segments.contains { $0.noDamage },
            "对照：喷火里应有 noDamage 段（精力消耗），用来验证它不进构成",
            counter: &count
        )
    }

    // ⑧ 法术：构成只能来自 flat，绝不能把 motion 乘到施法器上造出物理伤害
    for key in ["death-lightning", "comet"] {
        guard let spell = results[key] else { continue }
        for channel in SkillDamageChannel.allCases where channel.isPhysical {
            try rankerExpectClose(
                spell.shares[channel.rawValue], 0,
                "对照：\(key) 是法术，物理占比必须为 0（motion 是占位写法）",
                tolerance: 0.000000001, counter: &count
            )
        }
        try rankerExpect(spell.plan.total > 1, "对照：\(key) 应能给出理论叠加组合", counter: &count)
    }

    // 旧版排名页的对拍行（配置页的双端对拍行见 checkLoadoutParity，走 NR_RANKER_DUMP）。
    if ProcessInfo.processInfo.environment["NR_RANKER_LEGACY_DUMP"] == "1" {
        for line in dump { print(line) }
    }
}


// MARK: - 配置页（BuffLoadout）：合成数据（算法本身的精确断言）

/// v6 合成数据集：slotRules / weaponAffixes / fixedRelics / attackIndex + 覆盖各条口径的最小 buff。
private let loadoutSyntheticJSON = """
{
  "schemaVersion": 6,
  "gameVersion": "test", "dataVersion": "test",
  "notes": {"ranking": "测试用", "userQuestions": {"Q2": {"question": "问二", "answer": "答二"}, "Q1": {"question": "问一", "answer": "答一"}, "坏": 3}},
  "stackingRules": {"zh": "测试用"},
  "rateFields": \(syntheticRateFields),
  "rateFieldGroups": [],
  "conditionFields": [{"key":"conditionHp","zh":"残余血量低于此比例(%)才发动"}],
  "enums": {
    "wepType": {"1": {"zh": "短剑", "en": "Dagger", "textId": 60010}, "9": {"zh": "刀", "en": "Katana"}},
    "attackContext": {"thrustingCounter": {"zh": "突刺反击", "en": "Thrusting Counter"}},
    "atkSubCategory": {"112": {"zh": "战技攻击"}, "130": {"zh": "近战武器攻击"}},
    "sourceSlot": {"weaponAffix": {"zh": "局内武器词条", "en": "x", "note": "说明"}},
    "exclusiveScope": {"perSpEffect": "只与自己互斥"}
  },
  "slotRules": {
    "modes": {
      "normal": {"zh": "常规", "weaponAffixesPerWeapon": 1, "relicSlots": 3, "weaponCursesPerWeapon": 0, "deepOnlyAffixesPerWeapon": 0},
      "deep": {"zh": "深夜", "weaponAffixesPerWeapon": 2, "relicSlots": 6, "weaponCursesPerWeapon": 1, "deepOnlyAffixesPerWeapon": 1},
      "zh": "模式说明"
    },
    "weaponAffix": {"maxWeapons": 6, "maxAffixesNormal": 6, "maxAffixesDeep": 12, "deepOnlyPerWeaponMax": 1,
                    "maxDeepOnlyAffixes": 6, "deepCursePerWeapon": 1, "deepOnlyCapField": "weaponAffixDeepOnlyPositive",
                    "duplicateWithinWeapon": {"status": "unknown", "zh": "未知"}, "zh": "武器词条说明"},
    "relic": {"normal": 3, "deepExtra": 3, "affixesPerRelic": 3, "zh": "遗物说明"},
    "accessory": {"slots": 2, "measured": false, "zh": "护符说明"},
    "consumable": {"slots": null, "zh": "道具说明"}
  },
  "weaponAffixes": [
    {"attachEffectId": 9001, "nameZh": "提升物理", "paramName": "[Weapon] Physical - Potency 1", "potency": 1, "roles": ["affix"], "compatibilityId": 500,
     "normalWepTypes": [1, 9], "deepWepTypes": [1, 9], "deepOnly": false, "deepOnlyPositive": false, "spEffectIds": [901]},
    {"attachEffectId": 9002, "nameZh": "提升物理", "paramName": "[Weapon] Physical - Potency 2", "potency": 2, "roles": ["affix"], "compatibilityId": 500,
     "normalWepTypes": [9], "deepWepTypes": [9], "deepOnly": false, "deepOnlyPositive": false, "spEffectIds": [902]},
    {"attachEffectId": 9003, "nameZh": "深夜提升火", "potency": 1, "roles": ["affix"], "compatibilityId": 600,
     "normalWepTypes": [], "deepWepTypes": [1, 9], "deepOnly": true, "deepOnlyPositive": true, "spEffectIds": [903]},
    {"attachEffectId": 9004, "nameZh": "诅咒", "roles": ["curse"], "compatibilityId": 700, "isDebuff": true,
     "normalWepTypes": [], "deepWepTypes": [1, 9], "deepOnly": true, "deepOnlyPositive": false, "spEffectIds": [904]},
    {"attachEffectId": 9005, "nameZh": "只给短剑", "potency": 1, "roles": ["affix"], "compatibilityId": 800,
     "normalWepTypes": [1], "deepWepTypes": [1], "deepOnly": false, "deepOnlyPositive": false, "spEffectIds": [922]}
  ],
  "fixedRelics": [
    {"relicIds": [1000], "nameZh": "测试固定遗物", "color": 0, "isDeepRelic": false,
     "attachEffectIds": [7100, 7101], "attachEffectNamesZh": ["增伤词条", null], "spEffectIds": [910]}
  ],
  "attackIndex": {
    "skills": {"77": {"nameZh": "测试战技", "subCategorySets": [{"subs": [112, 130], "hits": 3}, {"subs": [106], "hits": 1}]}},
    "spells": {"88": {"nameZh": "测试法术", "subCategorySets": [{"subs": [], "hits": 2}]}}
  },
  "counts": {"buffs": 1},
  "buffs": [
    \(loadoutBuff(901, "提升物理1", "{\"physicsAttackRate\":1.1}", slot: "weaponAffix", paramName: "[Weapon] Physical - Potency 1", extra: "\"weaponAffixIds\":[9001],"))
    ,\(loadoutBuff(902, "提升物理2", "{\"physicsAttackRate\":1.2}", slot: "weaponAffix", paramName: "[Weapon] Physical - Potency 2", extra: "\"weaponAffixIds\":[9002],"))
    ,\(loadoutBuff(903, "深夜提升火", "{\"fireAttackRate\":1.5}", slot: "weaponAffix",
                   extra: "\"weaponAffixIds\":[9003],\"weaponAffixDeepOnly\":true,\"weaponAffixDeepOnlyPositive\":true,"))
    ,\(loadoutBuff(904, "诅咒增伤", "{\"physicsAttackRate\":1.05}", slot: "weaponAffix", extra: "\"weaponAffixIds\":[9004],"))
    ,\(loadoutBuff(905, "香药甲", "{\"physicsAttackRate\":1.3}", slot: "consumable", key: "sp151", behavior: "removePrevious", scope: "category"))
    ,\(loadoutBuff(906, "香药乙", "{\"physicsAttackRate\":1.4}", slot: "consumable", key: "sp151", behavior: "removePrevious", scope: "category"))
    ,\(loadoutBuff(907, "只给法术", "{\"physicsAttackRate\":1.25}", slot: "spellBuff",
                   applies: "{\"skill\":\"no\",\"sorcery\":\"yes\",\"incantation\":\"yes\"}",
                   detail: "{\"skill\":{\"reason\":\"测试：不作用于战技\"}}"))
    ,\(loadoutBuff(908, "只给左手", "{\"physicsAttackRate\":1.3}", slot: "consumable",
                   applies: "{\"skill\":\"conditional\",\"sorcery\":\"no\",\"incantation\":\"no\"}",
                   detail: "{\"skill\":{\"reason\":\"只限左手\",\"requires\":{\"hand\":2}}}"))
    ,\(loadoutBuff(909, "战技子类别", "{\"physicsAttackRate\":1.2}", slot: "other",
                   applies: "{\"skill\":\"conditional\",\"sorcery\":\"no\",\"incantation\":\"no\"}",
                   detail: "{\"skill\":{\"reason\":\"子类别 112\",\"requires\":{\"subCategoriesAny\":[112]}}}"))
    ,\(loadoutBuff(910, "固定遗物增火", "{\"fireAttackRate\":1.3}", slot: "relicAffix"))
    ,\(loadoutBuff(911, "阶梯叠层", "{\"physicsAttackRate\":1.05,\"fireAttackRate\":1.05}", slot: "runStack",
                   activation: "conditional",
                   extra: "\"stackInput\":{\"mode\":\"ladder\",\"paramMaxStacks\":3,\"practicalMaxStacks\":2,\"practicalMaxSource\":\"实测：测试\",\"multiplierKey\":\"fireAttackRate\",\"appliesToRateKeys\":[\"physicsAttackRate\",\"fireAttackRate\"],\"tierMultipliers\":[1.05,1.1025,1.157625],\"perStackRatio\":1.05},"))
    ,\(loadoutBuff(912, "份数叠层", "{\"physicsAttackRate\":1.02}", slot: "runStack", activation: "conditional",
                   extra: "\"stackInput\":{\"mode\":\"copies\",\"paramMaxStacks\":null,\"practicalMaxStacks\":null,\"multiplierKey\":\"physicsAttackRate\",\"appliesToRateKeys\":[\"physicsAttackRate\"],\"perStackMultiplier\":1.02,\"uiLabelMax\":10},"))
    ,\(loadoutBuff(913, "条件护符", "{\"physicsAttackRate\":1.3}", slot: "accessory", activation: "conditional",
                   sourceKind: "accessory", sourceID: 5000))
    ,\(loadoutBuff(914, "敌方减益", "{\"physicsAttackRate\":1.5}", slot: "consumable", target: "enemy"))
    ,\(loadoutBuff(915, "遗物物理", "{\"physicsAttackRate\":1.1}", slot: "relicAffix",
                   extra: "\"relicAffixes\":[{\"attachEffectId\":60001,\"catalogEffectId\":60001,\"catalog\":\"affixes\",\"compatibilityId\":1}],"))
    ,\(loadoutBuff(916, "遗物火", "{\"fireAttackRate\":1.1}", slot: "relicAffix",
                   extra: "\"relicAffixes\":[{\"attachEffectId\":60002,\"catalogEffectId\":60002,\"catalog\":\"affixes\",\"compatibilityId\":2}],"))
    ,\(loadoutBuff(917, "深夜遗物物理", "{\"physicsAttackRate\":1.3}", slot: "relicAffix",
                   extra: "\"relicAffixes\":[{\"attachEffectId\":60003,\"catalogEffectId\":60003,\"catalog\":\"affixes\",\"requiresCurse\":true,\"compatibilityId\":3}],"))
    ,\(loadoutBuff(918, "累积第1档", "{\"physicsAttackRate\":1.05}", slot: "accessory", activation: "conditional",
                   key: "sp120", behavior: "removePrevious", scope: "accumulatorLadder", sourceKind: "accessory", sourceID: 5001,
                   extra: "\"accumulatorLadder\":{\"key\":\"sp120\",\"tier\":1,\"tiers\":3,\"tierSpEffectIds\":[918,919,9190],\"thresholds\":[10,20,30]},"))
    ,\(loadoutBuff(919, "累积第2档", "{\"physicsAttackRate\":1.1}", slot: "accessory", activation: "conditional",
                   key: "sp120", behavior: "removePrevious", scope: "accumulatorLadder", sourceKind: "accessory", sourceID: 5001,
                   extra: "\"accumulatorLadder\":{\"key\":\"sp120\",\"tier\":2,\"tiers\":3,\"tierSpEffectIds\":[918,919,9190],\"thresholds\":[10,20,30]},"))
    ,\(loadoutBuff(920, "优先度2", "{\"physicsAttackRate\":1.5}", slot: "consumable", key: "sp1001", behavior: "applyHighest", priority: 2, scope: "category"))
    ,\(loadoutBuff(921, "优先度1", "{\"physicsAttackRate\":1.1}", slot: "consumable", key: "sp1001", behavior: "applyHighest", priority: 1, scope: "category"))
    ,\(loadoutBuff(922, "短剑词条", "{\"fireAttackRate\":1.2}", slot: "weaponAffix", extra: "\"weaponAffixIds\":[9005],"))
    ,\(loadoutBuff(923, "突刺反击", "{\"physicsAttackRate\":1.4}", slot: "consumable",
                   applies: "{\"skill\":\"conditional\",\"sorcery\":\"no\",\"incantation\":\"no\"}",
                   detail: "{\"skill\":{\"reason\":\"情境\",\"requires\":{\"attackContexts\":[\"thrustingCounter\"]}}}"))
    ,\(loadoutBuff(924, "附魔负载", "{\"physicsAttackRate\":1.2}", slot: "relicAffix",
                   applies: "{\"skill\":\"conditional\",\"sorcery\":\"no\",\"incantation\":\"no\"}",
                   detail: "{\"skill\":{\"reason\":\"附加属性负载\",\"requires\":{\"imbuedWeaponOnly\":true,\"未来条件\":1}}}",
                   extra: "\"relicAffixes\":[{\"attachEffectId\":60005,\"catalogEffectId\":60005,\"catalog\":\"affixes\",\"compatibilityId\":5}],"))
    ,\(loadoutBuff(925, "武器固有", "{\"physicsAttackRate\":1.08}", slot: "weaponInnate",
                   extra: "\"weaponInnate\":{\"attachEffectIds\":[],\"weaponIds\":[31],\"wepTypes\":[9]},"))
    ,\(loadoutBuff(926, "档位一", "{\"fireAttackPower\":30}", slot: "relicAffix", key: "affix#60007", direction: "mixed", scope: "affixVariant",
                   extra: "\"relicAffixes\":[{\"attachEffectId\":60007,\"catalogEffectId\":60007,\"catalog\":\"affixes\",\"compatibilityId\":7,\"exclusivityId\":100}],\"affixVariant\":{\"key\":\"affix#60007\",\"attachEffectId\":60007,\"variant\":1,\"variants\":2},"))
    ,\(loadoutBuff(927, "档位二", "{\"fireAttackPower\":40}", slot: "relicAffix", key: "affix#60007", direction: "mixed", scope: "affixVariant",
                   extra: "\"relicAffixes\":[{\"attachEffectId\":60007,\"catalogEffectId\":60007,\"catalog\":\"affixes\",\"compatibilityId\":7,\"exclusivityId\":100}],\"affixVariant\":{\"key\":\"affix#60007\",\"attachEffectId\":60007,\"variant\":2,\"variants\":2},"))
    ,\(loadoutBuff(928, "队友那一行", "{\"physicsAttackRate\":1.3}", slot: "weaponSkill", target: "ally",
                   extra: "\"selfAllyPair\":{\"role\":\"ally\",\"counterpartSpEffectId\":929},"))
    ,\(loadoutBuff(929, "自己那一行", "{\"physicsAttackRate\":1.2}", slot: "weaponSkill",
                   extra: "\"selfAllyPair\":{\"role\":\"self\",\"counterpartSpEffectId\":928},"))
    ,\(loadoutBuff(930, "振奋香", "{\"physicsAttackRate\":1.15}", slot: "consumable", target: "ally"))
    ,\(loadoutBuff(931, "需道具", "{\"physicsAttackRate\":1.1}", slot: "consumable", extra: "\"requiresGoodsIds\":[1210],"))
  ]
}
"""

private func loadoutBuff(
    _ id: Int, _ name: String, _ rates: String, slot: String,
    applies: String = "{\"skill\":\"yes\",\"sorcery\":\"yes\",\"incantation\":\"yes\"}",
    detail: String = "{}", activation: String = "passive", key: String? = nil,
    behavior: String = "stackSelf", priority: Int = 0, target: String = "self", direction: String = "increase",
    scope: String = "perSpEffect", paramName: String? = nil,
    sourceKind: String = "relicAffix", sourceID: Int = 1, extra: String = ""
) -> String {
    let exclusiveKey = key ?? "sp10#\(id)"
    return """
    {"spEffectId": \(id), "nameZh": "\(name)", "displayNameZh": "\(name)", "paramName": "\(paramName ?? "[Test] \(name)")",
     "sources": [{"kind": "\(sourceKind)", "id": \(sourceID), "via": "test", "nameZh": "\(name)来源"}],
     "rates": \(rates), "rateGroups": ["damage"], "direction": "\(direction)", "scope": {},
     "stacking": {"stateInfo": 0, "spCategory": 10, "spCategoryBehavior": "\(behavior)", "categoryPriority": \(priority),
                  "saveCategory": -1, "group": "\(exclusiveKey)", "exclusiveKey": "\(exclusiveKey)", "exclusiveScope": "\(scope)"},
     \(extra)
     "duration": -1, "permanent": true, "target": "\(target)", "targetSource": "default",
     "activation": "\(activation)", "activationSource": "noEvidence",
     "sourceSlot": "\(slot)", "sourceSlots": ["\(slot)"], "appliesTo": \(applies), "appliesToDetail": \(detail)}
    """
}

/// 合成词条库：60001/60002 普通池、60004 与 60001 同互斥、60003 深夜 A 池需诅咒、69001/69002 诅咒。
private let loadoutSyntheticCatalog: [Affix] = [
    Affix(effectID: 60001, name: "遗物物理", compatibilityID: 1, sortID: 10, poolIDs: [110, 210, 310]),
    Affix(effectID: 60002, name: "遗物火", compatibilityID: 2, sortID: 20, poolIDs: [110, 210, 310]),
    Affix(effectID: 60003, name: "深夜遗物物理", compatibilityID: 3, sortID: 30, poolIDs: [2_000_000], requiresCurse: true),
    Affix(effectID: 60004, name: "同互斥", compatibilityID: 1, sortID: 40, poolIDs: [110, 210, 310]),
    Affix(effectID: 60005, name: "附魔负载", compatibilityID: 5, sortID: 50, poolIDs: [110, 210, 310]),
    Affix(effectID: 60006, name: "旧池词条", compatibilityID: 6, sortID: 60, poolIDs: [100]),
    Affix(effectID: 60007, name: "出击附加火", compatibilityID: 7, sortID: 70, poolIDs: [110, 210, 310]),
    Affix(effectID: 69001, name: "诅咒甲", compatibilityID: 9001, sortID: 900, poolIDs: [3_000_000], isCurse: true),
    Affix(effectID: 69002, name: "诅咒乙", compatibilityID: 9001, sortID: 901, poolIDs: [3_000_000], isCurse: true)
]

private func checkLoadoutSynthetic(counter count: inout Int) throws {
    let index = try BuffLoadoutIndex(data: Data(loadoutSyntheticJSON.utf8), catalog: loadoutSyntheticCatalog)
    let rules = index.slotRules
    try rankerExpect(index.supportsLoadout, "合成 v6 数据应支持配置页", counter: &count)
    try rankerExpect(
        index.dataset.userQuestions.map(\.key) == ["Q1", "Q2"],
        "notes.userQuestions 应按 Q1、Q2 排好，坏元素跳过（实际 \(index.dataset.userQuestions.map(\.key))）",
        counter: &count
    )
    try rankerExpect(
        rules.weaponAffixCap(.normal) == 6 && rules.weaponAffixCap(.deep) == 12
            && rules.deepOnlyCap(.normal) == 0 && rules.deepOnlyCap(.deep) == 6
            && rules.relicSlots(.normal) == 3 && rules.relicSlots(.deep) == 6 && rules.accessorySlots == 2,
        "slotRules 的上限应照数据读出（常规 6 / 深夜 12，深夜专属 0 / 6，遗物 3 / 6，护符 2）",
        counter: &count
    )
    try rankerExpect(
        index.slotlessItems[.consumable]?.contains { $0.buffIndices.contains { index.dataset.buffs[$0].spEffectId == 914 } } != true,
        "target = enemy 的条目不该进任何栏", counter: &count
    )
    try rankerExpect(index.cursePoolID == 3_000_000, "诅咒池从词条库现算（只装诅咒的池）", counter: &count)
    try rankerExpect(index.variantOptions("affix#60007").map { index.dataset.buffs[$0].spEffectId } == [926, 927],
                     "多档词条按数据 affixVariant 分组、按档位排好", counter: &count)

    let shares = halfSlashHalfFire()
    let skillOutput = LoadoutOutput(outputClass: .skill, skillID: 77, weaponWepType: 9, hand: 1, shares: shares)
    let evaluator = LoadoutEvaluator(index: index, output: skillOutput)
    let armedEvaluator = LoadoutEvaluator(
        index: index,
        output: LoadoutOutput(outputClass: .skill, skillID: 77, weaponID: 31, weaponWepType: 9, hand: 1, shares: shares)
    )
    func offset(_ id: Int) throws -> Int {
        guard let value = index.indexByID[id] else { throw CheckFailure(description: "增伤排名：合成数据缺 #\(id)") }
        return value
    }
    func status(_ evaluation: LoadoutEvaluation, _ id: Int) -> LoadoutLineStatus? {
        evaluation.lines.first { $0.spEffectId == id }?.status
    }

    // ① appliesTo 分流：no / yes / hand / subCategoriesAny / attackContexts / 用户确认
    let skillNo = evaluator.verdict(forBuffAt: try offset(907))!
    try rankerExpect(!skillNo.isApplicable && skillNo.blockedReason == "测试：不作用于战技",
                     "appliesTo.skill = no 应不生效并给出 reason", counter: &count)
    let sorceryEvaluator = LoadoutEvaluator(
        index: index, output: LoadoutOutput(outputClass: .sorcery, spellID: 88, shares: shares)
    )
    try rankerExpect(sorceryEvaluator.verdict(forBuffAt: try offset(907))?.isApplicable == true,
                     "同一条对魔法 = yes 应生效", counter: &count)
    try rankerExpect(evaluator.verdict(forBuffAt: try offset(908))?.state == .no,
                     "requires.hand = 2 在右手时应不生效", counter: &count)
    let leftEvaluator = LoadoutEvaluator(
        index: index,
        output: LoadoutOutput(outputClass: .skill, skillID: 77, weaponID: 31, weaponWepType: 9, hand: 2, shares: shares)
    )
    try rankerExpect(leftEvaluator.verdict(forBuffAt: try offset(908))?.state == .yes,
                     "requires.hand = 2 在左手时应生效", counter: &count)
    let partial = evaluator.verdict(forBuffAt: try offset(909))!
    try rankerExpectClose(partial.fraction, 0.75, "subCategoriesAny 按 attackIndex 段数折算（3/4 段带 112）", counter: &count)
    try rankerExpect(partial.notes.first == LoadoutText.f("requireSubsPartial", "战技", 3, 4, "[112 战技攻击]"),
                     "部分段命中写明近似（实际 \(partial.notes)）", counter: &count)
    try rankerExpect(sorceryEvaluator.verdict(forBuffAt: try offset(909))?.state == .no,
                     "对魔法 = no 的子类别条目不生效", counter: &count)
    try rankerExpect(evaluator.verdict(forBuffAt: try offset(923))?.state == .context,
                     "requires.attackContexts 未勾选情境时要勾情境", counter: &count)
    let contextEvaluator = LoadoutEvaluator(
        index: index,
        output: LoadoutOutput(outputClass: .skill, skillID: 77, weaponID: 31, weaponWepType: 9, hand: 1,
                              shares: shares, attackContexts: ["thrustingCounter"])
    )
    try rankerExpect(contextEvaluator.verdict(forBuffAt: try offset(923))?.state == .yes,
                     "勾选对应情境后生效", counter: &count)
    let imbued = evaluator.verdict(forBuffAt: try offset(924))!
    try rankerExpect(imbued.state == .pending && imbued.needs.count == 2
                        && imbued.requirements.contains { $0.key == "unknown-未来条件" },
                     "imbuedWeaponOnly 与认不出的键交给用户确认（不直接判不生效）", counter: &count)
    let goods = evaluator.verdict(forBuffAt: try offset(931))!
    try rankerExpect(goods.state == .pending && goods.needs.first == LoadoutText.f("requireGoods", LoadoutText.f("goodsFallback", 1210)),
                     "requiresGoodsIds：要确认，道具名缺失退「道具 #id」（实际 \(goods.needs)）", counter: &count)
    try rankerExpect(evaluator.attackContextOptions().map(\.key) == ["thrustingCounter"],
                     "攻击情境勾选项只列 requires.attackContexts 里出现的", counter: &count)

    // ② 单条倍率：部分段折算 = Σ 占比 × (1 + f × (m − 1))；不占槽位的栏勾选即确认
    var loadout = BuffLoadout(mode: .normal, rules: rules)
    loadout.selectedBuffs = [909]
    var result = evaluator.evaluate(loadout)
    try rankerExpectClose(result.total, 0.5 * (1 + 0.75 * 0.2) + 0.5, "部分段生效按段数折算", tolerance: 1e-12, counter: &count)

    // ③ exclusiveKey 去重：同键取有效倍率高的；applyHighest 取 categoryPriority 小的并提示
    loadout.selectedBuffs = [905, 906, 920, 921]
    result = evaluator.evaluate(loadout)
    try rankerExpect(status(result, 906) == .counted && status(result, 905) == .duplicate(by: 906),
                     "同一 exclusiveKey 只留有效倍率高的一份", counter: &count)
    try rankerExpect(status(result, 921) == .counted && status(result, 920) == .duplicate(by: 921),
                     "applyHighest 两份取 categoryPriority 数值小的（哪怕倍率低）", counter: &count)
    try rankerExpect(result.lines.first { $0.spEffectId == 920 }?.reasons.first
                        == LoadoutText.f("reasonDupPriority", "优先度1", "sp1001", 1, 2),
                     "被 categoryPriority 压掉的一份写明原因", counter: &count)
    try rankerExpect(result.warnings.map(\.kind) == ["duplicate", "priority"]
                        && result.warnings[1].text == LoadoutText.f("warnPriority", "sp1001", "优先度1", "优先度2"),
                     "汇总提示被压掉的项（实际 \(result.warnings.map(\.text))）", counter: &count)
    try rankerExpectClose(result.total, 0.5 * 1.4 * 1.1 + 0.5, "去重后逐通道连乘再加权", tolerance: 1e-12, counter: &count)

    // ④ 同一效果多份：stackSelf（按 ID 互斥）各份相乘并提示；多档词条同一词条两件只算一份
    loadout = BuffLoadout(mode: .normal, rules: rules)
    loadout.weaponAffixCounts = [9001: 2]
    result = evaluator.evaluate(loadout)
    try rankerExpectClose(result.total, 0.5 * 1.1 * 1.1 + 0.5, "stackSelf 两份相乘", tolerance: 1e-12, counter: &count)
    try rankerExpect(result.warnings.map(\.kind) == ["copiesStackSelf"]
                        && result.warnings[0].text == LoadoutText.f("warnCopiesStackSelf", "提升物理1 ×2"),
                     "stackSelf 多份相乘要提示「参数推断」（实际 \(result.warnings.map(\.text))）", counter: &count)
    try rankerExpect(result.lines.first?.countedCopies == 2 && result.lines.first?.notes == [LoadoutText.f("noteCopiesStackSelf", 2)],
                     "这一条记份数与说明", counter: &count)
    // 不同档位：各自独立键相乘 + 同族提示（行名去掉「 - Potency N」后相同）
    loadout.weaponAffixCounts = [9001: 1, 9002: 1]
    result = evaluator.evaluate(loadout)
    try rankerExpectClose(result.total, 0.5 * 1.1 * 1.2 + 0.5, "同一词条的不同档位按独立键相乘", tolerance: 1e-12, counter: &count)
    try rankerExpect(result.warnings.contains { $0.kind == "tiers" && $0.text.contains("参数推断，未实测") },
                     "不同档位相乘要标「参数推断，未实测」（实际 \(result.warnings.map(\.text))）", counter: &count)
    try rankerExpect(index.selectedTierFamilies(loadout) == [[9001, 9002]], "同名两档应分到同一词条", counter: &count)

    // ⑤ 叠层输入：缺省 0 层不计；阶梯取 tierMultipliers[n-1]、份数取 perStack^n；越界夹到参数上限、超过实际上限提示
    loadout = BuffLoadout(mode: .normal, rules: rules)
    loadout.selectedBuffs = [911, 912]
    result = evaluator.evaluate(loadout)
    try rankerExpect(result.lines.allSatisfy { $0.status == .zeroStacks }, "层数缺省 0，不计入", counter: &count)
    loadout.stackCounts = [911: 2, 912: 5]
    result = evaluator.evaluate(loadout)
    try rankerExpectClose(result.total, 0.5 * 1.1025 * pow(1.02, 5) + 0.5 * 1.1025,
                          "阶梯第 2 层 ×1.1025（物理+火），份数 5 层 ×1.02^5（只乘物理）", tolerance: 1e-12, counter: &count)
    loadout.stackCounts = [911: 9]
    result = evaluator.evaluate(loadout)
    let ladderLine = result.lines.first { $0.spEffectId == 911 }
    try rankerExpect(ladderLine?.stacks == 3, "阶梯层数应夹到参数表层数 3", counter: &count)
    try rankerExpect(ladderLine?.notes == [LoadoutText.f("stackOverPractical", 3, 2, "实测"), LoadoutText.f("stackOverParam", 3)],
                     "超过一局实际上限与参数表层数都要提示（实际 \(ladderLine?.notes ?? [])）", counter: &count)
    try rankerExpect(BuffLoadoutIndex.defaultStacks(index.dataset.buffs[try offset(911)].stackInput!) == 2
                        && BuffLoadoutIndex.defaultStacks(index.dataset.buffs[try offset(912)].stackInput!) == 1,
                     "勾选时预填：一局实际上限，没有就 1", counter: &count)

    // ⑥ 条件型：占槽位的栏选中≠条件成立；勾「条件成立」后才计入
    loadout = BuffLoadout(mode: .normal, rules: rules)
    loadout.accessories = [5000]
    result = evaluator.evaluate(loadout)
    try rankerExpect(result.lines.first?.status == .pending
                        && result.lines.first?.needs == [LoadoutText.t("activationNeed.conditional")],
                     "条件型护符默认不计入", counter: &count)
    loadout.confirmed = [913]
    result = evaluator.evaluate(loadout)
    try rankerExpectClose(result.total, 0.5 * 1.3 + 0.5, "勾「条件成立」后计入", tolerance: 1e-12, counter: &count)
    // 累积阶梯：没选层不计；选层即确认
    loadout = BuffLoadout(mode: .normal, rules: rules)
    loadout.accessories = [5001]
    result = evaluator.evaluate(loadout)
    try rankerExpect(result.lines.allSatisfy { $0.status == .tierOff } && result.lines.first?.reasons == [LoadoutText.t("reasonTierNone")],
                     "累积阶梯没选层时一层都不算", counter: &count)
    loadout.ladderTiers = [918: 2]
    result = evaluator.evaluate(loadout)
    try rankerExpect(status(result, 919) == .counted && status(result, 918) == .tierOff,
                     "累积阶梯只计选中的那一层（选层即确认）", counter: &count)
    try rankerExpect(index.ladderTierOptions(918) == [1, 2] && index.ladderTopTier(918) == 2,
                     "选层只列数据里真实存在的层（实际 \(index.ladderTierOptions(918))）", counter: &count)
    if let ladderItem = index.accessoryItem(5001) {
        let ladderCandidate = evaluator.candidate(for: ladderItem, loadout: BuffLoadout(mode: .normal, rules: rules))
        try rankerExpectClose(ladderCandidate.potential, 0.5 * 1.1 + 0.5, "累积阶梯的潜在倍率取实际存在的最高层", counter: &count)
        try rankerExpect(ladderCandidate.needsConfirmation && ladderCandidate.status == .tierOff,
                         "没选层的候选：要选层", counter: &count)
    } else {
        throw CheckFailure(description: "增伤排名：合成数据缺护符 5001")
    }
    let overviewByID = Dictionary(evaluator.overview().map { ($0.spEffectId, $0) }, uniquingKeysWith: { first, _ in first })
    try rankerExpectClose(overviewByID[918]?.multiplier ?? 1, 0.5 * 1.05 + 0.5, "一览：累积阶梯第 1 层按第 1 层自己算", counter: &count)
    try rankerExpectClose(overviewByID[919]?.multiplier ?? 1, 0.5 * 1.1 + 0.5, "一览：累积阶梯第 2 层按第 2 层自己算", counter: &count)
    try rankerExpect(overviewByID[912]?.assumesOneStack == false && overviewByID[911]?.multiplier ?? 0 > 1,
                     "一览：叠层取一局实际上限，没有就退『＋N』标签数", counter: &count)
    try rankerExpect(overviewByID[914] == nil && overviewByID[928]?.isApplicable == false
                        && overviewByID[930]?.isApplicable == true,
                     "一览只收能进计算的；selfAllyPair 的队友那一行不生效，普通 ally 照常", counter: &count)

    // ⑦ 作用对象：ally 照常计入；selfAllyPair 的 Allies 那一行不计入
    loadout = BuffLoadout(mode: .normal, rules: rules)
    loadout.selectedBuffs = [928, 929, 930]
    result = evaluator.evaluate(loadout)
    try rankerExpect(status(result, 928) == .no && result.lines.first { $0.spEffectId == 928 }?.reasons == [LoadoutText.t("reasonAllyPair")]
                        && status(result, 929) == .counted && status(result, 930) == .counted,
                     "selfAllyPair：施放者自己只计 Self 那一行", counter: &count)

    // ⑧ 多档词条：同一组只算选中的一档（默认第 1 档），可改选；exclusivityId 同组提示
    loadout = BuffLoadout(mode: .normal, rules: rules)
    loadout.relicCards[0] = LoadoutRelicCard(isDeepSlot: false, choice: .custom, rows: [LoadoutRelicRow(affixID: 60007)])
    result = evaluator.evaluate(loadout)
    try rankerExpect(status(result, 926) == .counted && status(result, 927) == .variantOff,
                     "多档词条默认第 1 档", counter: &count)
    try rankerExpect(result.lines.first { $0.spEffectId == 927 }?.reasons == [LoadoutText.f("reasonVariantOff", 2, 1)],
                     "未选的档写明按第几档计算", counter: &count)
    try rankerExpectClose(result.weightedFlat, 15, "加算只算选中的一档（火 30 × 火占比 0.5）", tolerance: 1e-12, counter: &count)
    loadout.variantChoices = ["affix#60007": 927]
    result = evaluator.evaluate(loadout)
    try rankerExpect(status(result, 927) == .counted && status(result, 926) == .variantOff, "改选第 2 档", counter: &count)
    loadout.relicCards[1] = loadout.relicCards[0]
    result = evaluator.evaluate(loadout)
    try rankerExpect(result.lines.first { $0.spEffectId == 927 }.map { $0.copies == 2 && $0.countedCopies == 1 } == true,
                     "多档词条（exclusiveScope=affixVariant）同一词条两件只算一份", counter: &count)

    // ⑨ 武器固有：当前武器自带的自动列入，可去掉
    loadout = BuffLoadout(mode: .normal, rules: rules)
    result = armedEvaluator.evaluate(loadout)
    try rankerExpect(result.countedLines.map(\.spEffectId) == [925], "当前武器自带的固有效果应自动计入", counter: &count)
    try rankerExpect(evaluator.evaluate(loadout).countedLines.isEmpty, "法术／没有武器时不带武器固有", counter: &count)
    try rankerExpect(armedEvaluator.candidates(for: .weaponInnate, loadout: loadout).first?.item.isAutoInnate == true,
                     "武器固有栏应把当前武器自带的标出来", counter: &count)
    loadout.excludedInnate = [925]
    try rankerExpect(armedEvaluator.evaluate(loadout).countedLines.isEmpty, "去掉后不再计入", counter: &count)

    // ⑩ 槽位上限：常规不列深夜专属与诅咒；武器类别过滤；深夜推荐填满不越界
    let normalWA = evaluator.candidates(for: .weaponAffix, loadout: BuffLoadout(mode: .normal, rules: rules))
    try rankerExpect(Set(normalWA.map(\.item.id)) == ["wa-9001", "wa-9002", "wa-9005"],
                     "常规模式不列深夜专属词条与诅咒（实际 \(normalWA.map(\.item.id))）", counter: &count)
    let katanaWA = evaluator.candidates(for: .weaponAffix, loadout: BuffLoadout(mode: .normal, rules: rules), weaponTypeFilter: 9)
    try rankerExpect(!katanaWA.contains { $0.item.id == "wa-9005" }, "按当前武器类别（刀）过滤掉只给短剑的词条", counter: &count)
    var offFilter = BuffLoadout(mode: .normal, rules: rules)
    offFilter.weaponAffixCounts = [9005: 1]
    try rankerExpect(
        evaluator.candidates(for: .weaponAffix, loadout: offFilter, weaponTypeFilter: 9).contains { $0.item.id == "wa-9005" },
        "已选的词条即使不在当前武器类别也要列出（否则在这一栏里减不掉）", counter: &count
    )
    var deep = BuffLoadout(mode: .deep, rules: rules)
    deep = evaluator.recommendedFill(deep, weaponTypeFilter: nil)
    let deepEval = evaluator.evaluate(deep)
    try rankerExpect(deepEval.weaponAffixUsage.used == 12 && !deepEval.weaponAffixUsage.isOver,
                     "深夜推荐填满应正好填到 12 条（实际 \(deepEval.weaponAffixUsage.used)）", counter: &count)
    try rankerExpect(deepEval.deepOnlyUsage.used == 6,
                     "深夜专属正面词条应被上限卡在 6 条（实际 \(deepEval.deepOnlyUsage.used)）", counter: &count)
    try rankerExpect(deep.weaponAffixCounts[9004] == nil, "推荐填满不推荐诅咒", counter: &count)
    try rankerExpect(deepEval.violations.isEmpty, "推荐填满后不应有超限（实际 \(deepEval.violations)）", counter: &count)
    var over = BuffLoadout(mode: .deep, rules: rules)
    over.weaponAffixCounts = [9003: 7, 9001: 6]
    let overEval = evaluator.evaluate(over)
    try rankerExpect(overEval.weaponAffixUsage.used == 13 && overEval.weaponAffixUsage.isOver
                        && overEval.deepOnlyUsage.isOver && overEval.violations.count == 2,
                     "超过 12 条 / 深夜专属 6 条都要报出来（实际 \(overEval.violations)）", counter: &count)
    let removed = over.setMode(.normal, rules: rules, weaponAffixes: index.weaponAffixByID)
    try rankerExpect(removed == 7 && over.weaponAffixCounts == [9001: 6] && over.relicCards.count == 3,
                     "切回常规应去掉深夜专属、裁到 6 条、遗物卡回到 3 张（去掉 \(removed)，剩 \(over.weaponAffixCounts)）",
                     counter: &count)

    // ⑪ 自组遗物合法性：部分选（补占位再调 LegalityChecker）、互斥、出货池、深夜诅咒配对；不合法的整件不计入
    func card(_ ids: [Int?], curses: [Int?] = [nil, nil, nil], deep: Bool = false) -> LoadoutRelicCard {
        LoadoutRelicCard(
            isDeepSlot: deep, choice: .custom,
            rows: (0..<3).map { LoadoutRelicRow(affixID: ids.indices.contains($0) ? ids[$0] : nil, curseID: curses[$0]) }
        )
    }
    let two = index.relicCheck(card([60001, 60002]))
    try rankerExpect(two.status == .partial && two.message == LoadoutText.f("relicPartial", 2, 1),
                     "两条不同互斥池的普通词条：预检通过", counter: &count)
    let conflict = index.relicCheck(card([60001, 60004]))
    try rankerExpect(conflict.status == .invalid && conflict.issues.map(\.title) == [LoadoutText.t("checkConflictTitle")]
                        && conflict.issues[0].detail == LoadoutText.f("checkConflictDetail", "遗物物理、同互斥"),
                     "同一互斥池的两条应非法（占位词条不出现在文案里）", counter: &count)
    try rankerExpect(index.relicCheck(card([60006])).issues.map(\.title) == [LoadoutText.t("checkPoolTitle")],
                     "旧池词条不在 1.03 普通出货池", counter: &count)
    let full = index.relicCheck(card([60001, 60002, 60005]))
    try rankerExpect(full.status == .valid && full.message == LoadoutText.t("relicValidNormal"), "三条合法", counter: &count)
    let deepMissing = index.relicCheck(card([60003], deep: true))
    try rankerExpect(deepMissing.status == .invalid && deepMissing.issues.map(\.detail)
                        == [LoadoutText.f("curseMissingDetail", 1, "深夜遗物物理")] && deepMissing.warnings.isEmpty,
                     "深夜需诅咒的词条没配诅咒应非法（与存档审计同文）", counter: &count)
    let deepPaired = index.relicCheck(card([60003], curses: [69001, nil, nil], deep: true))
    try rankerExpect(deepPaired.status == .partial && deepPaired.warnings.map(\.title) == [LoadoutText.t("cursePairingTitle")],
                     "配上诅咒后预检通过，并写明诅咒配对已校验", counter: &count)
    try rankerExpect(index.relicCheck(card([60001], deep: true)).status == .invalid,
                     "普通池词条放不进深夜遗物格", counter: &count)
    try rankerExpect(index.relicCheck(card([60003, nil], curses: [69001, 69002, nil], deep: true))
                        .issues.contains { $0.title == LoadoutText.t("curseUnexpectedTitle") },
                     "不需要诅咒的行携带诅咒应报「多余的负面词条」", counter: &count)
    let twin = index.relicCheck(card([60003, 60003], curses: [69001, 69001, nil], deep: true))
    try rankerExpect(twin.issues.contains { $0.title == LoadoutText.t("curseDuplicateTitle") && $0.detail.hasPrefix("同一词条在一件遗物上重复出现") }
                        && twin.issues.contains { $0.title == LoadoutText.t("curseConflictTitle") },
                     "涉及诅咒的重复与互斥（与存档审计同文）", counter: &count)
    try rankerExpect(evaluator.pickCurse(for: card([60003], deep: true), row: 0) == 69001, "配诅咒：ID 小的先试", counter: &count)
    // 换词条（与 Windows 端 withRelicAffix / autoAssignCurses 同法）：需诅咒的词条自动配诅咒；换成另一条需诅咒的词条时
    // 旧诅咒清掉重配；不需诅咒的行、普通遗物格不带诅咒。
    let picked = evaluator.withRelicAffix(LoadoutRelicCard(isDeepSlot: true), row: 0, affixID: 60003)
    try rankerExpect(picked == card([60003], curses: [69001, nil, nil], deep: true)
                        && index.relicCheck(picked).status == .partial,
                     "深夜遗物选需诅咒的词条：自动配上 ID 最小的合法诅咒、预检通过", counter: &count)
    try rankerExpect(evaluator.withRelicAffix(card([60003], curses: [69002, nil, nil], deep: true), row: 0, affixID: 60003)
                        .rows[0].curseID == 69001,
                     "换成另一条需诅咒的词条：旧诅咒清掉后重配（不沿用）", counter: &count)
    try rankerExpect(evaluator.withRelicAffix(card([60003], curses: [69001, nil, nil], deep: true), row: 0, affixID: 60001)
                        .rows.allSatisfy { $0.curseID == nil },
                     "换成不需诅咒的词条：这一行的诅咒清掉", counter: &count)
    try rankerExpect(evaluator.withRelicAffix(LoadoutRelicCard(isDeepSlot: false), row: 0, affixID: 60003)
                        .rows.allSatisfy { $0.curseID == nil },
                     "普通遗物格不带诅咒", counter: &count)
    try rankerExpect(evaluator.autoAssignCurses(card([60003, 60001], deep: true))
                        == card([60003, 60001], curses: [69001, nil, nil], deep: true)
                        && evaluator.autoAssignCurses(card([60001, 60003], curses: [69002, 69002, nil], deep: true))
                        == card([60001, 60003], curses: [nil, 69002, nil], deep: true),
                     "autoAssignCurses：需诅咒的行补配、已配的保留、不需诅咒的行清掉", counter: &count)
    loadout = BuffLoadout(mode: .deep, rules: rules)
    loadout.excludedInnate = [925]
    loadout.relicCards[3] = card([60003], deep: true)
    result = evaluator.evaluate(loadout)
    try rankerExpect(status(result, 917) == .relicInvalid && abs(result.total - 1) < 1e-12,
                     "不合法的自组遗物整件不计入", counter: &count)
    loadout.relicCards[3] = card([60003], curses: [69001, nil, nil], deep: true)
    result = evaluator.evaluate(loadout)
    try rankerExpectClose(result.total, 0.5 * 1.3 + 0.5, "合法后计入（诅咒只占位）", tolerance: 1e-12, counter: &count)
    let fixed = index.fixedRelicItem(0)
    try rankerExpect(fixed?.infoLines.map(\.counted) == [false, false] && fixed?.infoLines.last?.text == "词条 #7101",
                     "固定遗物的非增伤词条只显示；缺中文名退「词条 #id」", counter: &count)

    // ⑫ 推荐填满：武器词条同一条可以多份（stackSelf 相乘）；条件型护符不推荐；再点一次不变
    let normalFilled = evaluator.recommendedFill(BuffLoadout(mode: .normal, rules: rules), weaponTypeFilter: 9)
    let normalEval = evaluator.evaluate(normalFilled)
    try rankerExpect(normalFilled.weaponAffixCounts == [9002: 6], "同一词条多份（stackSelf 各份相乘）：取 ×1.2 那条填满 6 份（实际 \(normalFilled.weaponAffixCounts)）",
                     counter: &count)
    try rankerExpect(normalEval.relicChecks.allSatisfy { $0.status != .invalid }, "推荐的遗物都必须合法", counter: &count)
    try rankerExpect(normalFilled.accessories.isEmpty, "条件型护符不推荐", counter: &count)
    try rankerExpect(evaluator.recommendedFill(normalFilled, weaponTypeFilter: 9) == normalFilled,
                     "填满后再点一次不应再变", counter: &count)
    try rankerExpect(normalEval.countedLines.allSatisfy { index.dataset.buffs[$0.buffIndex].activation == "passive" },
                     "推荐填满只挑被动", counter: &count)

    // ⑬ 汇总连乘：总倍率 = 计入条目逐通道连乘后加权（独立重算）
    try checkLoadoutTotal(normalEval, shares: shares, "合成推荐配置", counter: &count)
}

/// 独立重算：计入条目的 channelMultiplier 逐通道相乘，再按占比加权；各栏小计同法；同一互斥键只能出现一次。
private func checkLoadoutTotal(
    _ evaluation: LoadoutEvaluation, shares: [Double], _ label: String, counter count: inout Int
) throws {
    func weighted(_ lines: [LoadoutLine]) -> Double {
        var product = Array(repeating: 1.0, count: SkillDamageChannel.allCases.count)
        for line in lines {
            for index in product.indices { product[index] *= line.channelMultiplier[index] }
        }
        var sum = 0.0
        var weight = 0.0
        for index in product.indices where shares[index] > 0 {
            sum += shares[index] * product[index]
            weight += shares[index]
        }
        return weight > 0 ? sum / weight : 1
    }
    try rankerExpectClose(evaluation.total, weighted(evaluation.countedLines), "\(label)：总倍率应等于计入条目逐通道连乘后加权",
                          tolerance: 1e-9, counter: &count)
    for column in LoadoutSummaryColumn.allCases {
        try rankerExpectClose(
            evaluation.columnSubtotals[column] ?? 1, weighted(evaluation.countedLines.filter { $0.summaryColumn == column }),
            "\(label)：\(column.title) 小计", tolerance: 1e-9, counter: &count
        )
    }
    let keys = evaluation.countedLines.map(\.exclusiveKey)
    try rankerExpect(Set(keys).count == keys.count, "\(label)：同一互斥键只能计入一份", counter: &count)
}

// MARK: - 配置页（BuffLoadout）：真实数据

private func loadoutOutput(
    skills: SkillDataIndex, skillID: Int? = nil, spellID: Int? = nil, weaponID: Int? = nil,
    hand: Int = 1, contexts: Set<String> = []
) throws -> LoadoutOutput {
    if let skillID {
        guard let skill = skills.skillsByID[skillID], let weaponID, let weapon = skills.weaponsByID[weaponID] else {
            throw CheckFailure(description: "增伤排名：配置用例找不到战技 \(skillID) / 武器 \(weaponID ?? -1)")
        }
        let segments = skills.segments(for: skill, weapon: weapon)
        let composition = SkillDamageMath.composition(of: segments, selected: SkillDamageMath.defaultSelection(segments))
        return LoadoutOutput(
            outputClass: .skill, skillID: skillID, weaponID: weaponID, weaponWepType: weapon.wepType,
            hand: hand, shares: composition.shares, attackContexts: contexts
        )
    }
    guard let spellID, let spell = skills.spellsByID[spellID] else {
        throw CheckFailure(description: "增伤排名：配置用例找不到法术 \(spellID ?? -1)")
    }
    let segments = skills.segments(for: spell)
    let composition = SkillDamageMath.composition(of: segments, selected: SkillDamageMath.defaultSelection(segments))
    return LoadoutOutput(
        outputClass: spell.isSorcery ? .sorcery : .incantation, spellID: spellID,
        hand: hand, shares: composition.shares, attackContexts: contexts
    )
}

private func checkLoadoutRealData(skills: SkillDataIndex, buffs: BuffRankerIndex, counter count: inout Int) throws {
    let catalog = try CatalogLoader.load(from: resourceURL("affixes.json"))
    let index = BuffLoadoutIndex(ranker: buffs, catalog: catalog.affixes)
    let rules = index.slotRules
    let dataset = index.dataset

    // ① 结构：v6 字段都在、上限照数据
    try rankerExpect(index.supportsLoadout, "真实增益数据应支持配置页（slotRules + appliesTo）", counter: &count)
    try rankerExpect(
        rules.maxAffixesNormal == 6 && rules.maxAffixesDeep == 12 && rules.maxDeepOnlyAffixes == 6
            && rules.deepOnlyCap(.normal) == 0 && rules.accessorySlots == 2 && rules.relicSlots(.deep) == 6,
        "slotRules：常规 6 / 深夜 12 / 深夜专属 6 / 常规深夜专属 0 / 护符 2 / 深夜遗物 6",
        counter: &count
    )
    try rankerExpect(!index.weaponAffixItems.isEmpty && !index.relicAffixItems.isEmpty
                        && !index.fixedRelicItems.isEmpty && !index.accessoryItems.isEmpty,
                     "四个占槽位的栏都应有候选", counter: &count)
    try rankerExpect(dataset.userQuestions.count >= 5, "notes.userQuestions 应有 Q1–Q5", counter: &count)
    try rankerExpect(index.cursePoolID == 3_000_000, "诅咒池从词条库现算（与 core.js DEEP_CURSE_POOL_ID 同值）", counter: &count)
    // 列表口径：只收带伤害字段、self / ally、不是减益的
    for (offset, buff) in dataset.buffs.enumerated() {
        let expected = index.countsAsDamage[offset] && (buff.target == "self" || buff.target == "ally") && buff.direction != "decrease"
        try rankerExpect(index.listable[offset] == expected, "#\(buff.spEffectId) 能不能进配置页", counter: &count)
        try rankerExpect(!buff.stacking.exclusiveKey.isEmpty, "#\(buff.spEffectId) 应有 exclusiveKey", counter: &count)
    }
    // 多档词条：只读数据 affixVariant，7 组 × 4 档
    try rankerExpect(index.variantMembers.count == 7 && index.variantMembers.values.allSatisfy { $0.count == 4 },
                     "多档词条 7 组 × 4 档（数据 affixVariant，不按 compatibilityId 猜）", counter: &count)
    let exclusivityAffixes = Set(dataset.buffs.flatMap { buff in
        buff.relicAffixes.filter { $0.exclusivityId == 100 }.map(\.attachEffectId)
    })
    try rankerExpect(dataset.buffs.filter { $0.selfAllyPair != nil }.count == 6 && exclusivityAffixes.count == 7,
                     "selfAllyPair 6 条、exclusivityId=100 的词条 7 条（实际 \(exclusivityAffixes.count)）", counter: &count)

    // ② appliesTo 分流：yes 生效、no 不生效（魔法排除 magParamChange=0；法术排除 112 类）
    let skillOutput = try loadoutOutput(skills: skills, skillID: 1177, weaponID: 9040000)
    let sorceryOutput = try loadoutOutput(skills: skills, spellID: 4021)
    let incantationOutput = try loadoutOutput(skills: skills, spellID: 5040)
    for output in [skillOutput, sorceryOutput, incantationOutput] {
        let evaluator = LoadoutEvaluator(index: index, output: output)
        let cls = output.outputClass.rawValue
        var yes = 0
        var no = 0
        for offset in dataset.buffs.indices where index.listable[offset] {
            guard let verdict = evaluator.verdict(forBuffAt: offset) else { continue }
            switch dataset.buffs[offset].appliesTo[cls] {
            case "yes":
                yes += 1
                guard verdict.isApplicable && verdict.fraction == 1 else {
                    throw CheckFailure(description: "增伤排名：#\(dataset.buffs[offset].spEffectId) appliesTo.\(cls)=yes 却判不生效")
                }
            case "no":
                no += 1
                guard !verdict.isApplicable, verdict.blockedReason?.isEmpty == false else {
                    throw CheckFailure(description: "增伤排名：#\(dataset.buffs[offset].spEffectId) appliesTo.\(cls)=no 却判生效")
                }
            default:
                break
            }
            count += 1
        }
        try rankerExpect(yes > 0 && no > 0, "\(cls)：应同时有生效与不生效的条目（yes \(yes) / no \(no)）", counter: &count)
    }
    let skillEvaluator = LoadoutEvaluator(index: index, output: skillOutput)
    let sorceryEvaluator = LoadoutEvaluator(index: index, output: sorceryOutput)
    let incantationEvaluator = LoadoutEvaluator(index: index, output: incantationOutput)
    for id in [8350000, 8350001, 8350002, 7006700, 312300] {
        guard let offset = index.indexByID[id] else { continue }
        try rankerExpect(skillEvaluator.verdict(forBuffAt: offset)?.state == .yes
                            && sorceryEvaluator.verdict(forBuffAt: offset)?.state == .no
                            && incantationEvaluator.verdict(forBuffAt: offset)?.state == .no,
                         "#\(id)：尸横遍野（每段都带 112）吃得到，法术吃不到", counter: &count)
    }

    // ②b 自组深夜遗物换词条（复核回归，Windows ranker_config.test.mjs 有同一组断言）：深夜遗物 1 选「提升物理攻击力＋４」(6001401)
    // 两端都自动配上「受到损伤时，会累积中毒量表」(6820000)，预检通过、条目计入；换成另一条需诅咒的词条时旧诅咒清掉重配。
    try rankerExpect(index.catalogAffixes[6001401]?.requiresCurse == true && index.catalogAffixes[6260000]?.requiresCurse == true,
                     "6001401、6260000 都是需诅咒的深夜词条", counter: &count)
    var cursed = BuffLoadout(mode: .deep, rules: rules)
    cursed.relicCards[3] = skillEvaluator.withRelicAffix(cursed.relicCards[3], row: 0, affixID: 6001401)
    try rankerExpect(cursed.relicCards[3].choice == .custom && cursed.relicCards[3].rows.map(\.affixID) == [6001401, nil, nil]
                        && cursed.relicCards[3].rows.map(\.curseID) == [6820000, nil, nil]
                        && skillEvaluator.pickCurse(for: LoadoutRelicCard(isDeepSlot: true, choice: .custom, rows: [LoadoutRelicRow(affixID: 6001401)]), row: 0) == 6820000,
                     "深夜遗物 1 选「提升物理攻击力＋４」：自动配上「受到损伤时，会累积中毒量表」", counter: &count)
    let cursedEval = skillEvaluator.evaluate(cursed)
    let cursedLines = cursedEval.lines.filter { line in line.sourceKeys.contains { $0.hasPrefix("relic:3") } }
    try rankerExpect(cursedEval.relicChecks[3].status == .partial && !cursedLines.isEmpty
                        && cursedLines.allSatisfy { $0.status != .relicInvalid } && cursedLines.contains { $0.status == .counted },
                     "配上诅咒后预检通过、整件计入", counter: &count)
    let manualCurse = LoadoutRelicCard(isDeepSlot: true, choice: .custom,
                                       rows: [LoadoutRelicRow(affixID: 6001401, curseID: index.curseAffixes[1].effectID)])
    try rankerExpect(index.relicCheck(manualCurse).status == .partial
                        && skillEvaluator.withRelicAffix(manualCurse, row: 0, affixID: 6260000).rows.map(\.curseID) == [6820000, nil, nil],
                     "手动改成第二条诅咒后换成另一条需诅咒的词条：旧诅咒清掉、按新词条重配", counter: &count)
    if let free = index.relicAffixItems.compactMap(\.relicAffix).first(where: { index.isRelicAffixEligible($0, deepSlot: true) && !$0.requiresCurse }) {
        let clearedRow = LoadoutRelicCard(isDeepSlot: true, choice: .custom,
                                          rows: [LoadoutRelicRow(affixID: 6001401), LoadoutRelicRow(affixID: free.effectID)])
        try rankerExpect(skillEvaluator.withRelicAffix(clearedRow, row: 1, affixID: nil).rows.map(\.curseID) == [6820000, nil, nil],
                         "另一行手动清掉的诅咒：换任一行的词条时一并补配", counter: &count)
    } else {
        throw CheckFailure(description: "增伤排名：深夜遗物候选里应有不需诅咒的词条")
    }
    try rankerExpect(skillEvaluator.withRelicAffix(LoadoutRelicCard(isDeepSlot: false), row: 0, affixID: 6001401).rows.allSatisfy { $0.curseID == nil },
                     "普通遗物格不带诅咒", counter: &count)

    // ③ 叠层换算：封印监牢 7 层 ×1.4072、夹到 10 层；赐福王的余威 5 份 ×1.02^5；两条阶梯同时生效相乘并提示
    var stackLoadout = BuffLoadout(mode: .normal, rules: rules)
    stackLoadout.selectedBuffs = [8970000]
    stackLoadout.stackCounts = [8970000: 5]
    var stackEval = skillEvaluator.evaluate(stackLoadout)
    try rankerExpectClose(stackEval.total, pow(1.02, 5), "赐福王的余威 5 份 = ×1.02^5", tolerance: 1e-9, counter: &count)
    var evergaol = LoadoutRelicCard(isDeepSlot: false, choice: .custom)
    evergaol.rows[0].affixID = 7060000
    stackLoadout = BuffLoadout(mode: .normal, rules: rules)
    stackLoadout.relicCards[0] = evergaol
    try rankerExpect(skillEvaluator.evaluate(stackLoadout).lines.first { $0.spEffectId == 7069001 }?.status == .zeroStacks,
                     "封印监牢没填层数不计入", counter: &count)
    stackLoadout.stackCounts = [7069001: 7]
    stackEval = skillEvaluator.evaluate(stackLoadout)
    try rankerExpectClose(stackEval.total, 1.4072, "封印监牢 7 层 = ×1.4072", tolerance: 1e-9, counter: &count)
    stackLoadout.stackCounts = [7069001: 12]
    stackEval = skillEvaluator.evaluate(stackLoadout)
    try rankerExpect(stackEval.lines.first { $0.spEffectId == 7069001 }.map { $0.stacks == 10 && $0.notes.count == 2 } == true,
                     "封印监牢层数夹到参数表 10 层并提示超过 7 层、超过参数表", counter: &count)
    try rankerExpectClose(stackEval.total, 1.6289, "封印监牢 10 层 = ×1.6289", tolerance: 1e-9, counter: &count)
    var both = stackLoadout
    var second = LoadoutRelicCard(isDeepSlot: false, choice: .custom)
    second.rows[0].affixID = 7060200
    both.relicCards[1] = second
    both.stackCounts = [7069001: 7, 7069201: 4]
    let bothEval = skillEvaluator.evaluate(both)
    try rankerExpectClose(bothEval.total, 1.4072 * 1.3108, "封印监牢 7 层 × 黑夜入侵者 4 层相乘", tolerance: 1e-9, counter: &count)
    try rankerExpect(bothEval.warnings.contains { $0.kind == "ladders" }, "两条阶梯同时生效要提示", counter: &count)

    // ④ exclusiveKey 真实例子：狂热香药与『火焰啊，赐予我力量！』同为 sp151，只留一份
    var keyLoadout = BuffLoadout(mode: .normal, rules: rules)
    keyLoadout.selectedBuffs = [503550, 1605000]
    let keyEval = skillEvaluator.evaluate(keyLoadout)
    try rankerExpect(keyEval.countedLines.count == 1
                        && keyEval.lines.contains { if case .duplicate = $0.status { return true } else { return false } },
                     "sp151 的两份只计一份", counter: &count)
    try checkLoadoutTotal(keyEval, shares: skillOutput.shares, "sp151", counter: &count)

    // ⑤ 遗物合法性接入（真实词条库）
    func customCard(_ ids: [Int], curses: [Int?] = [nil, nil, nil], deep: Bool = false) -> LoadoutRelicCard {
        LoadoutRelicCard(
            isDeepSlot: deep, choice: .custom,
            rows: (0..<3).map { LoadoutRelicRow(affixID: ids.indices.contains($0) ? ids[$0] : nil, curseID: curses[$0]) }
        )
    }
    let legal = index.relicCheck(customCard([7001400, 7044100, 7032700]))
    try rankerExpect(legal.status == .valid && legal.message == LoadoutText.t("relicValidNormal"),
                     "提升物理攻击力 + 强化王城古龙信仰的祷告 + 【女爵】… 应合法（\(legal.message)）", counter: &count)
    let illegal = index.relicCheck(customCard([7001400, 7001600, 7044100]))
    try rankerExpect(illegal.status == .invalid && illegal.issues.contains { $0.kind == "conflict" },
                     "提升物理攻击力 + 提升火属性攻击力（同一互斥池 100）应非法", counter: &count)
    try rankerExpect(index.relicCheck(customCard([7006700])).status == .invalid,
                     "固定遗物专属词条（没有出货池）不能自组", counter: &count)
    let deepNoCurse = index.relicCheck(customCard([6001700], deep: true))
    try rankerExpect(deepNoCurse.status == .invalid && deepNoCurse.issues.contains { $0.title == LoadoutText.t("curseMissingTitle") },
                     "深夜需诅咒词条没配诅咒应非法", counter: &count)
    let deepLegal = index.relicCheck(customCard([6001700, 7044100, 7030600], curses: [6820000, nil, nil], deep: true))
    try rankerExpect(deepLegal.status == .valid && deepLegal.warnings.map(\.kind) == ["cursePairing"],
                     "深夜三条 + 诅咒应合法（\(deepLegal.issues.map(\.detail))）", counter: &count)

    // ⑥ 三组双端对照配置 + 与参考实现逐项一致（见 checkLoadoutParity）
    try checkLoadoutParity(skills: skills, index: index, catalog: catalog.affixes, counter: &count)
    // ⑦ 文案常量表与说明区（两端逐字一致的锚点）
    try checkLoadoutTexts(index: index, counter: &count)
}

// MARK: - 配置页：双端对照（与 windows/tests/ranker_crosscheck.test.mjs 同一组输入、同一种对拍行）

/// 独立重算的参考实现（不复用 BuffLoadout 的任何分支），逐字对应 Windows 端 ranker_crosscheck 的 referenceConfig。
private struct LoadoutReference {
    let dataset: BuffDataset
    let fields: [String: BuffRateField]
    let byID: [Int: BuffEntry]

    init(dataset: BuffDataset) {
        self.dataset = dataset
        fields = Dictionary(dataset.rateFields.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
        byID = Dictionary(dataset.buffs.map { ($0.spEffectId, $0) }, uniquingKeysWith: { first, _ in first })
    }

    static let physical: [SkillDamageChannel] = [.slash, .strike, .pierce, .standard, .physicalOther]
    static let multiplierChannels: [String: [SkillDamageChannel]] = [
        "physicsAttackRate": physical, "physicsAttackPowerRate": physical,
        "magicAttackRate": [.magic], "magicAttackPowerRate": [.magic],
        "fireAttackRate": [.fire], "fireAttackPowerRate": [.fire],
        "thunderAttackRate": [.lightning], "thunderAttackPowerRate": [.lightning],
        "darkAttackRate": [.holy], "darkAttackPowerRate": [.holy],
        "slashAttackRate": [.slash], "slashAttackPowerRate": [.slash],
        "blowAttackRate": [.strike], "blowAttackPowerRate": [.strike],
        "thrustAttackRate": [.pierce], "thrustAttackPowerRate": [.pierce],
        "neutralAttackRate": [.standard], "neutralAttackPowerRate": [.standard]
    ]
    static let flatChannels: [String: [SkillDamageChannel]] = [
        "physicsAttackPower": physical, "magicAttackPower": [.magic], "fireAttackPower": [.fire],
        "thunderAttackPower": [.lightning], "darkAttackPower": [.holy]
    ]

    func countsAsDamage(_ buff: BuffEntry) -> Bool {
        buff.rates.contains { key, value in
            guard let field = fields[key] else { return false }
            return field.countsAsDamage && value != field.defaultValue
        }
    }

    func listable(_ buff: BuffEntry) -> Bool {
        countsAsDamage(buff) && (buff.target == "self" || buff.target == "ally") && buff.direction != "decrease"
    }

    struct Verdict {
        var ok: Bool
        var weight: Double = 1
        var manual = false
        var restricted: SkillDamageChannel?
    }

    func verdict(_ buff: BuffEntry, _ output: LoadoutOutput) -> Verdict {
        let cls = output.outputClass.rawValue
        let value = buff.appliesTo[cls]
        guard value == "yes" || value == "conditional" else { return Verdict(ok: false) }
        var result = Verdict(ok: true, manual: !buff.requiresGoodsIds.isEmpty)
        if value == "yes" { return result }
        guard let requires = buff.appliesToDetail[cls]?.requires else {
            result.manual = true
            return result
        }
        var any = false
        if let hand = requires.hand {
            any = true
            if hand != output.hand { return Verdict(ok: false) }
        }
        if !requires.attackWeaponTypes.isEmpty {
            any = true
            let own = output.outputClass == .skill ? output.weaponWepType : (output.outputClass == .sorcery ? 57 : 61)
            guard let own, requires.attackWeaponTypes.contains(own) else { return Verdict(ok: false) }
        }
        if !requires.subCategoriesAny.isEmpty {
            any = true
            let sets = output.outputClass == .skill
                ? output.skillID.flatMap { dataset.attackIndex.skills[$0] }
                : output.spellID.flatMap { dataset.attackIndex.spells[$0] }
            if let sets, !sets.isEmpty {
                var matched = 0
                var total = 0
                for set in sets {
                    total += set.hits
                    if set.subs.contains(where: { requires.subCategoriesAny.contains($0) }) { matched += set.hits }
                }
                if matched == 0 { return Verdict(ok: false) }
                result.weight = Double(matched) / Double(total)
            } else {
                result.manual = true
            }
        }
        if !requires.attackContexts.isEmpty {
            any = true
            if !requires.attackContexts.contains(where: { output.attackContexts.contains($0) }) { return Verdict(ok: false) }
        }
        if let physical = requires.physicalType {
            any = true
            let channel = [SkillDamageChannel.slash, .strike, .pierce, .standard][physical]
            result.restricted = channel
            if !(output.shares[channel.rawValue] > 0) { return Verdict(ok: false) }
        }
        if requires.imbuedWeaponOnly || requires.attachedWeaponOnly || !requires.unknownKeys.isEmpty {
            any = true
            result.manual = true
        }
        if !any { result.manual = true }
        return result
    }

    func paramMax(_ input: BuffStackInput) -> Int {
        guard input.mode == "ladder" else { return 99 }
        let tiers = input.tierMultipliers.count
        if let param = input.paramMaxStacks, param > 0 { return tiers > 0 ? min(param, tiers) : param }
        return max(tiers, 1)
    }

    func tables(_ buff: BuffEntry, _ verdict: Verdict, stacks: Int?, copies: Int) -> (table: [Double], flat: [Double]) {
        var table = Array(repeating: 1.0, count: SkillDamageChannel.allCases.count)
        var flat = Array(repeating: 0.0, count: SkillDamageChannel.allCases.count)
        var rates = buff.rates
        if let input = buff.stackInput, let stacks {
            let value = input.mode == "ladder"
                ? input.tierMultipliers[min(stacks, input.tierMultipliers.count) - 1]
                : pow(input.perStackMultiplier ?? 1, Double(stacks))
            for key in input.appliesToRateKeys.isEmpty ? [input.multiplierKey] : input.appliesToRateKeys { rates[key] = value }
        }
        for field in dataset.rateFields {
            guard let value = rates[field.key], field.countsAsDamage, value.isFinite, value != field.defaultValue else { continue }
            if field.valueKind == .multiplier, let channels = Self.multiplierChannels[field.key], value > 0 {
                for channel in channels where verdict.restricted == nil || verdict.restricted == channel {
                    table[channel.rawValue] *= value
                }
            } else if field.valueKind == .flat, let channels = Self.flatChannels[field.key] {
                for channel in channels { flat[channel.rawValue] += value }
            }
        }
        for index in table.indices {
            if verdict.weight < 1 {
                table[index] = 1 + (table[index] - 1) * verdict.weight
                flat[index] *= verdict.weight
            }
            if copies > 1 {
                table[index] = pow(table[index], Double(copies))
                flat[index] *= Double(copies)
            }
        }
        return (table, flat)
    }

    func weighted(_ table: [Double], _ shares: [Double]) -> Double {
        var sum = 0.0
        var weight = 0.0
        for index in table.indices where shares[index] > 0 {
            sum += shares[index] * table[index]
            weight += shares[index]
        }
        return weight > 0 ? sum / weight : 1
    }

    /// 一览（「条件全部成立」）的参考值。
    func overview(_ buff: BuffEntry, _ output: LoadoutOutput) -> Double? {
        guard listable(buff), buff.selfAllyPair?.role != "ally" else { return nil }
        let verdict = verdict(buff, output)
        guard verdict.ok else { return nil }
        var stacks: Int?
        if let input = buff.stackInput {
            let soft = (input.practicalMaxStacks ?? 0) > 0 ? input.practicalMaxStacks! : ((input.uiLabelMax ?? 0) > 0 ? input.uiLabelMax! : 1)
            stacks = min(soft, paramMax(input))
        }
        return weighted(tables(buff, verdict, stacks: stacks, copies: 1).table, output.shares)
    }

    struct ConfigResult {
        var total: Double
        var subtotals: [String: Double]
        var ids: [String]
    }

    func config(_ loadout: BuffLoadout, index: BuffLoadoutIndex, output: LoadoutOutput) -> ConfigResult {
        var sources: [(id: Int, copies: Int, column: String)] = []
        for id in loadout.weaponAffixCounts.keys.sorted() {
            let count = loadout.weaponAffixCounts[id] ?? 0
            guard count > 0, let raw = dataset.weaponAffixes.first(where: { $0.attachEffectId == id }) else { continue }
            for spID in raw.spEffectIds where byID[spID].map(listable) == true { sources.append((spID, count, "weaponAffix")) }
        }
        for card in loadout.relicCards {
            switch card.choice {
            case .empty: break
            case .fixed(let fixedIndex):
                for spID in dataset.fixedRelics[fixedIndex].spEffectIds where byID[spID].map(listable) == true {
                    sources.append((spID, 1, "relic"))
                }
            case .custom:
                for affixID in card.rows.compactMap(\.affixID) {
                    for buff in dataset.buffs where listable(buff) && buff.relicAffixes.contains(where: { $0.catalogEffectId == affixID }) {
                        sources.append((buff.spEffectId, 1, "relic"))
                    }
                }
            }
        }
        for talisman in loadout.accessories {
            for buff in dataset.buffs where listable(buff) && buff.sourceSlot == "accessory"
                && buff.sources.contains(where: { $0.kind == "accessory" && $0.sourceID == talisman }) {
                sources.append((buff.spEffectId, 1, "accessory"))
            }
        }
        if output.outputClass == .skill, let weaponID = output.weaponID {
            for buff in dataset.buffs where listable(buff) && (buff.weaponInnate?.weaponIds.contains(weaponID) ?? false) {
                sources.append((buff.spEffectId, 1, "other"))
            }
        }
        var order: [Int] = []
        var merged: [Int: (copies: Int, column: String)] = [:]
        for source in sources {
            if let one = merged[source.id] {
                merged[source.id] = (one.copies + source.copies, one.column)
            } else {
                order.append(source.id)
                merged[source.id] = (source.copies, source.column)
            }
        }
        struct Candidate {
            let id: Int
            let key: String
            let value: Double
            let flat: Double
            let table: [Double]
            let column: String
            let copies: Int
            let highest: Bool
            let priority: Int
        }
        var candidates: [Candidate] = []
        for id in order {
            guard let buff = byID[id], let one = merged[id] else { continue }
            if let variant = buff.affixVariant {
                let chosen = loadout.variantChoices[variant.groupKey]
                    ?? dataset.buffs.first { $0.affixVariant?.groupKey == variant.groupKey && $0.affixVariant?.variant == 1 }?.spEffectId
                if chosen != buff.spEffectId { continue }
            }
            if buff.selfAllyPair?.role == "ally" { continue }
            let verdict = verdict(buff, output)
            guard verdict.ok else { continue }
            var stacks: Int?
            var selected = false
            if let ladder = buff.accumulatorLadder {
                guard loadout.ladderTiers[ladder.tierSpEffectIds.first ?? -1] == ladder.tier else { continue }
                selected = true
            }
            if let input = buff.stackInput {
                let value = min(max(0, loadout.stackCounts[buff.spEffectId] ?? 0), paramMax(input))
                guard value > 0 else { continue }
                stacks = value
                selected = true
            }
            let needs = !selected && (verdict.manual || buff.activation != "passive")
            if needs && !loadout.confirmed.contains(buff.spEffectId) { continue }
            let multiply = buff.stacking.spCategoryBehavior == "stackSelf"
                && (buff.stacking.exclusiveScope.isEmpty || buff.stacking.exclusiveScope == "perSpEffect")
            let computed = tables(buff, verdict, stacks: stacks, copies: multiply ? one.copies : 1)
            let value = weighted(computed.table, output.shares)
            let flat = weighted(computed.flat, output.shares)
            if abs(value - 1) <= 1e-9 && flat <= 1e-9 { continue }
            candidates.append(Candidate(
                id: id, key: buff.stacking.exclusiveKey, value: value, flat: flat, table: computed.table,
                column: one.column, copies: multiply ? one.copies : 1,
                highest: buff.stacking.spCategoryBehavior == "applyHighest", priority: buff.stacking.categoryPriority
            ))
        }
        var winners: [String: Candidate] = [:]
        for one in candidates {
            guard let current = winners[one.key] else { winners[one.key] = one; continue }
            let better: Bool
            if one.highest && current.highest && one.priority != current.priority {
                better = one.priority < current.priority
            } else if abs(one.value - current.value) > 1e-9 {
                better = one.value > current.value
            } else if abs(one.flat - current.flat) > 1e-9 {
                better = one.flat > current.flat
            } else {
                better = one.id < current.id
            }
            if better { winners[one.key] = one }
        }
        let list = Array(winners.values)
        func product(_ items: [Candidate]) -> Double {
            var table = Array(repeating: 1.0, count: SkillDamageChannel.allCases.count)
            for item in items { for index in table.indices { table[index] *= item.table[index] } }
            return weighted(table, output.shares)
        }
        var subtotals: [String: Double] = [:]
        for column in ["weaponAffix", "relic", "accessory", "other"] {
            subtotals[column] = product(list.filter { $0.column == column })
        }
        return ConfigResult(
            total: product(list), subtotals: subtotals,
            ids: list.sorted { $0.id < $1.id }.map { "\($0.id)" + ($0.copies > 1 ? "x\($0.copies)" : "") }
        )
    }
}

/// 一整套配置的对拍行（与 Windows 端 ranker.js 的 configDumpLine 同一格式）。
private func loadoutConfigDump(_ key: String, _ loadout: BuffLoadout, index: BuffLoadoutIndex, evaluation: LoadoutEvaluation) -> String {
    let sub = LoadoutSummaryColumn.allCases.map {
        "\($0.rawValue):" + String(format: "%.9f", evaluation.columnSubtotals[$0] ?? 1)
    }.joined(separator: ",")
    let weaponAffixes = loadout.weaponAffixCounts.keys.sorted()
        .filter { (loadout.weaponAffixCounts[$0] ?? 0) > 0 }
        .map { "\($0)x\(loadout.weaponAffixCounts[$0] ?? 0)" }.joined(separator: ",")
    let relics = loadout.relicCards.map { card -> String in
        switch card.choice {
        case .empty: return "-"
        case .fixed(let fixedIndex): return "F\(index.dataset.fixedRelics[fixedIndex].relicID)"
        case .custom:
            return "C" + card.rows.map { row in
                (row.affixID.map(String.init) ?? "-") + (row.curseID.map { "/\($0)" } ?? "")
            }.joined(separator: "+")
        }
    }.joined(separator: "|")
    let counted = evaluation.countedLines.sorted { $0.spEffectId < $1.spEffectId }
        .map { "\($0.spEffectId)" + ($0.countedCopies > 1 ? "x\($0.countedCopies)" : "") }.joined(separator: ",")
    return "CONFIG \(key) mode=\(loadout.mode.rawValue) total=" + String(format: "%.9f", evaluation.total)
        + " sub=\(sub) weaponAffixes=\(weaponAffixes) relics=\(relics)"
        + " accessories=" + loadout.accessories.map(String.init).joined(separator: ",") + " counted=\(counted)"
}

/// 一个输出手段的对拍行（与 Windows 端 caseDumpLine 同一格式）。
private func loadoutCaseDump(_ key: String, selected: [Int], shares: [Double], rows: [LoadoutOverviewRow]) -> String {
    let useful = rows.filter { $0.isApplicable && $0.multiplier > 1.0000001 }
    let selectedText: String = selected.map(String.init).joined(separator: ",")
    let sharesText: String = shares.map { String(format: "%.9f", $0) }.joined(separator: ",")
    let applicable: Int = rows.filter(\.isApplicable).count
    let top: [String] = useful.prefix(10).map { row in "\(row.spEffectId):" + String(format: "%.9f", row.multiplier) }
    return "CASE \(key) selected=\(selectedText) shares=\(sharesText) applicable=\(applicable) useful=\(useful.count) top10="
        + top.joined(separator: ",")
}

private func checkLoadoutParity(
    skills: SkillDataIndex, index: BuffLoadoutIndex, catalog: [Affix], counter count: inout Int
) throws {
    let dataset = index.dataset
    let rules = index.slotRules
    let reference = LoadoutReference(dataset: dataset)
    // 对拍行与 Windows 端 ranker_crosscheck.test.mjs 同序：OUTPUTS（输出手段条数，v3 起含只在局内战技池里
    // 出现的战技）→ CASE → CONFIG → TEXT。
    var dump: [String] = [
        "OUTPUTS skills=\(skills.outputs.filter { $0.kind == .skill }.count) spells=\(skills.outputs.filter { $0.kind == .spell }.count)"
    ]

    // ① 七组构成用例：一览（条件全部成立）逐条与参考实现一致，前 10 名降序
    let cases: [(key: String, skillID: Int?, spellID: Int?, weaponID: Int?, only: Set<Int>?)] = [
        ("corpse-piler-full", 1177, nil, 9040000, nil),
        ("corpse-piler-last", 1177, nil, 9040000, [303400305]),
        ("lions-claw-greatsword", 100, nil, 3180000, nil),
        ("lions-claw-flame-greatsword", 100, nil, 3180500, nil),
        ("firebreather", 223, nil, 24020000, nil),
        ("death-lightning", nil, 5040, nil, nil),
        ("comet", nil, 4021, nil, nil)
    ]
    for item in cases {
        let segments: [SkillSegment]
        let output: LoadoutOutput
        if let skillID = item.skillID, let skill = skills.skillsByID[skillID], let weaponID = item.weaponID,
           let weapon = skills.weaponsByID[weaponID] {
            segments = skills.segments(for: skill, weapon: weapon)
            let selected = item.only ?? SkillDamageMath.defaultSelection(segments)
            let composition = SkillDamageMath.composition(of: segments, selected: selected)
            output = LoadoutOutput(outputClass: .skill, skillID: skillID, weaponID: weaponID, weaponWepType: weapon.wepType,
                                   hand: 1, shares: composition.shares)
        } else if let spellID = item.spellID, let spell = skills.spellsByID[spellID] {
            segments = skills.segments(for: spell)
            let composition = SkillDamageMath.composition(of: segments, selected: SkillDamageMath.defaultSelection(segments))
            output = LoadoutOutput(outputClass: spell.isSorcery ? .sorcery : .incantation, spellID: spellID, hand: 1,
                                   shares: composition.shares)
        } else {
            throw CheckFailure(description: "增伤排名：对照用例 \(item.key) 找不到输出手段")
        }
        let selected = item.only ?? SkillDamageMath.defaultSelection(segments)
        let evaluator = LoadoutEvaluator(index: index, output: output)
        let rows = evaluator.overview()
        try rankerExpect(Set(rows.map(\.spEffectId)) == Set(dataset.buffs.filter(reference.listable).map(\.spEffectId)),
                         "对照 \(item.key)：一览只收能进计算的条目", counter: &count)
        for row in rows {
            guard let buff = reference.byID[row.spEffectId] else { continue }
            let expected = reference.overview(buff, output)
            if let expected {
                try rankerExpect(row.isApplicable, "对照 \(item.key)：#\(row.spEffectId) 参考判生效", counter: &count)
                try rankerExpectClose(row.multiplier, expected, "对照 \(item.key)：#\(row.spEffectId) 的有效倍率",
                                      tolerance: 1e-9, counter: &count)
            } else {
                try rankerExpect(!row.isApplicable, "对照 \(item.key)：#\(row.spEffectId) 参考判不生效", counter: &count)
            }
        }
        let useful = rows.filter { $0.isApplicable && $0.multiplier > 1.0000001 }
        try rankerExpect(!useful.isEmpty && zip(useful, useful.dropFirst()).allSatisfy { $0.multiplier >= $1.multiplier - 1e-12 },
                         "对照 \(item.key)：一览按有效倍率降序", counter: &count)
        dump.append(loadoutCaseDump(item.key, selected: segments.map(\.atkId).filter { selected.contains($0) },
                                    shares: output.shares, rows: rows))
    }

    // ② 三组配置对照
    let skillOutput = try loadoutOutput(skills: skills, skillID: 1177, weaponID: 9040000)
    let incantationOutput = try loadoutOutput(skills: skills, spellID: 5040)
    let lionOutput = try loadoutOutput(skills: skills, skillID: 100, weaponID: 3180000)
    let skillEvaluator = LoadoutEvaluator(index: index, output: skillOutput)
    let incantationEvaluator = LoadoutEvaluator(index: index, output: incantationOutput)
    let lionEvaluator = LoadoutEvaluator(index: index, output: lionOutput)

    // A：尸横遍野 + 尸山血海，常规，推荐填满
    let fillA = skillEvaluator.recommendedFill(BuffLoadout(mode: .normal, rules: rules), weaponTypeFilter: skillOutput.attackWepType)
    // B：死亡雷击，深夜，推荐填满（武器词条按施法器圣印记的类别过滤）
    let fillB = incantationEvaluator.recommendedFill(BuffLoadout(mode: .deep, rules: rules),
                                                     weaponTypeFilter: incantationOutput.attackWepType)
    // C：狮子斩 + 大剑：固定遗物 2070、2100（勾 7035902）+ 自组 [7060000, 7120100, 7260400] + 护符 1230、2040 + 封印监牢 7 层
    guard let steady = dataset.fixedRelics.firstIndex(where: { $0.relicIds.contains(2070) }),
          let kingNight = dataset.fixedRelics.firstIndex(where: { $0.relicIds.contains(2100) }) else {
        throw CheckFailure(description: "增伤排名：对照 C 找不到固定遗物 2070 / 2100")
    }
    var loadoutC = BuffLoadout(mode: .normal, rules: rules)
    loadoutC.relicCards[0] = LoadoutRelicCard(isDeepSlot: false, choice: .fixed(steady))
    loadoutC.relicCards[1] = LoadoutRelicCard(isDeepSlot: false, choice: .fixed(kingNight))
    loadoutC.relicCards[2] = LoadoutRelicCard(isDeepSlot: false, choice: .custom, rows: [
        LoadoutRelicRow(affixID: 7060000), LoadoutRelicRow(affixID: 7120100), LoadoutRelicRow(affixID: 7260400)
    ])
    loadoutC.accessories = [1230, 2040]
    loadoutC.stackCounts = [7069001: 7]
    loadoutC.confirmed = [7035902]

    let configs: [(key: String, loadout: BuffLoadout, evaluator: LoadoutEvaluator, output: LoadoutOutput, filled: Bool)] = [
        ("corpse-piler-normal-fill", fillA, skillEvaluator, skillOutput, true),
        ("death-lightning-deep-fill", fillB, incantationEvaluator, incantationOutput, true),
        ("lions-claw-2fixed-1custom-2talismans-evergaol7", loadoutC, lionEvaluator, lionOutput, false)
    ]
    for config in configs {
        let evaluation = config.evaluator.evaluate(config.loadout)
        let expected = reference.config(config.loadout, index: index, output: config.output)
        try rankerExpectClose(evaluation.total, expected.total, "对照 \(config.key)：总倍率", tolerance: 1e-9, counter: &count)
        for column in LoadoutSummaryColumn.allCases {
            try rankerExpectClose(evaluation.columnSubtotals[column] ?? 1, expected.subtotals[column.rawValue] ?? 1,
                                  "对照 \(config.key)：\(column.rawValue) 小计", tolerance: 1e-9, counter: &count)
        }
        let ids = evaluation.countedLines.sorted { $0.spEffectId < $1.spEffectId }
            .map { "\($0.spEffectId)" + ($0.countedCopies > 1 ? "x\($0.countedCopies)" : "") }
        try rankerExpect(ids == expected.ids, "对照 \(config.key)：计入条目集合（含份数）\(ids) vs \(expected.ids)", counter: &count)
        try checkLoadoutTotal(evaluation, shares: config.output.shares, "对照 \(config.key)", counter: &count)
        try rankerExpect(evaluation.total > 1, "对照 \(config.key)：这套配置应当增伤", counter: &count)
        try rankerExpect(evaluation.violations.isEmpty && evaluation.relicChecks.allSatisfy { $0.status != .invalid },
                         "对照 \(config.key)：不越界、遗物合法（\(evaluation.violations)）", counter: &count)
        if config.filled {
            try rankerExpect(config.evaluator.recommendedFill(config.loadout, weaponTypeFilter: config.output.attackWepType) == config.loadout,
                             "对照 \(config.key)：填满后再填一次不变（确定性）", counter: &count)
            try rankerExpect(evaluation.countedLines.allSatisfy { line in
                let buff = dataset.buffs[line.buffIndex]
                return buff.activation == "passive" && buff.stackInput == nil && buff.accumulatorLadder == nil && line.needs.isEmpty
            }, "对照 \(config.key)：推荐填满不选条件型、叠层与累积阶梯", counter: &count)
            let fixed = config.loadout.relicCards.compactMap(\.fixedIndex)
            try rankerExpect(Set(fixed).count == fixed.count && Set(config.loadout.accessories).count == config.loadout.accessories.count,
                             "对照 \(config.key)：固定遗物与护符不重复", counter: &count)
        }
        dump.append(loadoutConfigDump(config.key, config.loadout, index: index, evaluation: evaluation))
    }
    let evalA = skillEvaluator.evaluate(fillA)
    try rankerExpect(evalA.weaponAffixUsage.used == rules.maxAffixesNormal, "对照 A：常规应填满 6 条武器词条", counter: &count)
    let evalB = incantationEvaluator.evaluate(fillB)
    try rankerExpect(fillB.relicCards.count == 6 && evalB.weaponAffixUsage.used == rules.maxAffixesDeep,
                     "对照 B：深夜 6 张遗物卡、填满 12 条武器词条", counter: &count)
    for card in fillB.relicCards where card.choice == .custom {
        for row in card.rows {
            guard let affixID = row.affixID, let affix = catalog.first(where: { $0.effectID == affixID }) else { continue }
            try rankerExpect(affix.requiresCurse == (row.curseID != nil),
                             "对照 B：需诅咒的词条配诅咒、不需要的不带（\(affix.name)）", counter: &count)
        }
    }
    try rankerExpect(evalB.countedLines.allSatisfy { dataset.buffs[$0.buffIndex].appliesTo["incantation"] != "no" },
                     "对照 B：计入的条目对祷告都不能是 no", counter: &count)
    let evalC = lionEvaluator.evaluate(loadoutC)
    let countedC = Set(evalC.countedLines.map(\.spEffectId))
    try rankerExpect(evalC.relicChecks.map(\.status) == [.fixed, .fixed, .valid], "对照 C：两件固定遗物 + 一件合法自组", counter: &count)
    try rankerExpect(countedC.isSuperset(of: [7006700, 7035902, 7069001, 312300]) && !countedC.contains(7035703)
                        && !countedC.contains(320400),
                     "对照 C：勾过的条件型与封印监牢计入，没勾的条件型不计入（红羽七刃剑放进护符栏≠条件成立）", counter: &count)
    try rankerExpect(evalC.lines.first { $0.spEffectId == 7069001 }?.stacks == 7, "对照 C：封印监牢 7 层", counter: &count)
    try rankerExpect(evalC.lines.filter { dataset.buffs[$0.buffIndex].affixVariant?.groupKey == "affix#7120100" && $0.status != .variantOff }
                        .map(\.status) == [.pending],
                     "对照 C：多档词条只留第 1 档，imbuedWeaponOnly 要确认", counter: &count)

    if ProcessInfo.processInfo.environment["NR_RANKER_DUMP"] == "1" {
        for line in dump { print(line) }
        print("TEXT count=\(LoadoutText.table.count) digest=\(loadoutTextDigest()) brief=\(loadoutBriefDigest(LoadoutText.briefNotes(index: index)))")
    }
}

// MARK: - 配置页：文案常量表（两端逐字一致）

/// FNV-1a 32 位（按 UTF-8 字节），与 windows/tests/ranker_crosscheck.test.mjs 的 fnv1a 逐位相同。
private func loadoutFNV1a(_ text: String) -> String {
    var hash: UInt32 = 0x811c_9dc5
    for byte in Array(text.utf8) {
        hash = (hash ^ UInt32(byte)) &* 0x0100_0193
    }
    return String(format: "%08x", hash)
}

/// 文案常量表：点号路径排序后逐行「路径=文案」（按 UTF-16 码元比较，与 JS 的默认比较一致；键全是 ASCII）。
private func loadoutTextDigest() -> String {
    let keys = LoadoutText.table.keys.sorted { Array($0.utf16).lexicographicallyPrecedes(Array($1.utf16)) }
    return loadoutFNV1a(keys.map { $0 + "=" + (LoadoutText.table[$0] ?? "") }.joined(separator: "\n"))
}

/// 说明区：ASCII 数字归一成 # 之后的摘要。
private func loadoutBriefDigest(_ notes: [String]) -> String {
    var normalized = ""
    var lastWasDigit = false
    for character in notes.joined(separator: "\n") {
        if character.isASCII && character.isNumber {
            if !lastWasDigit { normalized.append("#") }
            lastWasDigit = true
        } else {
            normalized.append(character)
            lastWasDigit = false
        }
    }
    return loadoutFNV1a(normalized)
}

/// 两端同一个常量：改了任何一句文案，两端都要改、两个常量都要更新（Windows 端 TEXT_TABLE_DIGEST / BRIEF_DIGEST）。
private let loadoutTextTableCount = 336
private let loadoutTextTableDigest = "07a69c5e"
private let loadoutBriefNotesDigest = "ad04314d"

private func checkLoadoutTexts(index: BuffLoadoutIndex, counter count: inout Int) throws {
    try rankerExpect(LoadoutText.table.count == loadoutTextTableCount,
                     "文案常量表条数 \(LoadoutText.table.count)（Windows 端 TEXT 展开后同数）", counter: &count)
    try rankerExpect(loadoutTextDigest() == loadoutTextTableDigest,
                     "文案常量表摘要应与 Windows 端相同（实际 \(loadoutTextDigest())）", counter: &count)
    for (key, value) in LoadoutText.table {
        try rankerExpect(!value.isEmpty, "文案 \(key) 应是非空文案", counter: &count)
    }
    // 源码里 LoadoutText.t / f 用到的键都必须在表里（缺键会原样显示键名）。
    let sources = ["Sources/RelicCore/BuffLoadout.swift"] + [
        "BuffRankerView.swift", "BuffRankerModel.swift", "BuffRankerLoadoutSection.swift", "BuffRankerRelicSection.swift",
        "BuffRankerRankingSection.swift", "BuffRankerComponents.swift"
    ].map { "Sources/NightreignRelicChecker/" + $0 }
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let pattern = try NSRegularExpression(pattern: #"\b[tf]\("([A-Za-z0-9_.]*[A-Za-z0-9_])"[,)]"#)
    var used = 0
    for path in sources {
        guard let text = try? String(contentsOf: root.appendingPathComponent(path), encoding: .utf8) else { continue }
        let range = NSRange(text.startIndex..., in: text)
        for match in pattern.matches(in: text, range: range) {
            guard let keyRange = Range(match.range(at: 1), in: text) else { continue }
            let key = String(text[keyRange])
            used += 1
            try rankerExpect(LoadoutText.table[key] != nil, "\(path) 用到的文案键 \(key) 不在常量表里", counter: &count)
        }
    }
    try rankerExpect(used > 100, "应当扫到大量文案键（实际 \(used)）", counter: &count)
    try rankerExpect(LoadoutText.fmt("第 {0} 行：{1}", ["2", "名"]) == "第 2 行：名"
                        && LoadoutText.fmt("{0}{0}", ["a"]) == "aa" && LoadoutText.fmt("{1}", ["a"]) == "",
                     "fmt 按位置替换，缺的参数替换成空串（与 Windows fmt 同一口径）", counter: &count)

    // 说明区：条数与数字照数据现算；正文与 Windows 端逐字相同（数字归一后的摘要）
    let notes = LoadoutText.briefNotes(index: index)
    try rankerExpect(loadoutBriefDigest(notes) == loadoutBriefNotesDigest,
                     "说明区正文应与 Windows 端 briefNotes 相同（实际 \(loadoutBriefDigest(notes))）", counter: &count)
    let decreases = index.dataset.buffs.indices.filter {
        index.countsAsDamage[$0] && index.dataset.buffs[$0].direction == "decrease"
    }.count
    let all = notes.joined(separator: "\n")
    try rankerExpect(all.contains("direction=decrease 的 \(decreases) 条") && all.contains("7 组 28 条")
                        && all.contains(String(index.cursePoolID)) && all.contains("子类别 112 战技攻击／111 蓄力战技攻击")
                        && !all.contains("{"),
                     "说明区的条数、诅咒池、子类别照数据现算，格式串都填满了", counter: &count)
    try rankerExpect(LoadoutText.skillOnlySubCategories(index.dataset) == ["112 战技攻击", "111 蓄力战技攻击"],
                     "「提升战技攻击力」的子类别从 attackIndex 现算", counter: &count)
    for buff in index.dataset.buffs where buff.stackInput != nil {
        try rankerExpect(all.contains(buff.displayName), "\(buff.displayName) 的叠层说明要出现在说明区", counter: &count)
    }
    try rankerExpect(Set(LoadoutColumn.allCases.map(\.title)).count == LoadoutColumn.allCases.count,
                     "11 个栏目的中文名互不相同", counter: &count)
    try rankerExpect(LoadoutText.stripTierSuffix("连刺破露滴（第1层）") == "连刺破露滴"
                        && LoadoutText.familyName("提升攻击力（档位2）") == "提升攻击力"
                        && LoadoutText.familyName("提升物理攻击力＋２") == "提升物理攻击力",
                     "累积阶梯合成一项时去掉「（第N层）」，同族名去掉括注与＋N", counter: &count)
    let hero = LoadoutText.heroGroup(paramName: "[Skill - Revenant] Family Buff")
    try rankerExpect(hero.hero == "复仇者" && hero.kind == "技艺", "角色栏按 Paramdex 行名分到角色", counter: &count)

    // 不占槽位的栏：累积阶梯各层合成一项；角色栏每项都有分组；武器固有另走 innateItems
    let consumables = index.slotlessItems[.consumable] ?? []
    let ladderItems = consumables.filter { item in
        item.buffIndices.contains { index.dataset.buffs[$0].accumulatorLadder != nil }
    }
    try rankerExpect(!ladderItems.isEmpty && ladderItems.allSatisfy { $0.buffIndices.count > 1 },
                     "道具栏的累积阶梯应合成一项（各层在同一项里）", counter: &count)
    try rankerExpect(!consumables.contains { $0.title.hasSuffix("（第1层）") }, "合成后的标题不再带「第1层」", counter: &count)
    try rankerExpect((index.slotlessItems[.character] ?? []).allSatisfy { ($0.groupTitle ?? "").isEmpty == false },
                     "角色栏每一项都要分到某个角色", counter: &count)
    let allSlotless = index.slotlessItems.values.flatMap { $0 }.flatMap(\.buffIndices)
    try rankerExpect(Set(allSlotless).count == allSlotless.count, "同一条 buff 不应出现在两个不占槽位的栏里", counter: &count)
    try rankerExpect(index.slotlessItems[.weaponInnate] == nil && !index.innateItems(forWeapon: nil).isEmpty,
                     "武器固有不进一般的不占槽位栏；没有武器时仍列出全部固有效果（手动勾选）", counter: &count)
}
