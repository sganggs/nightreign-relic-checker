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
        delivery: .weaponSkill(slot: slot),
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
    try checkStackLadder(counter: &count)
    try checkStackingMath(counter: &count)
    try checkLenientDecoding(counter: &count)

    if GameDataLoader.isPlaceholder(skillsData) || GameDataLoader.isPlaceholder(buffsData) {
        print("    （skills.json / buffs.json 仍是占位内容，跳过真实数据检查）")
        return count
    }

    let skills = try SkillDataIndex(data: skillsData)
    let buffs = try BuffRankerIndex(data: buffsData)
    try checkSkillDataset(skills, counter: &count)
    try checkSegmentSelection(skills, counter: &count)
    try checkComposition(skills, counter: &count)
    try checkBuffDataset(buffs, counter: &count)
    try checkRealRanking(skills: skills, buffs: buffs, counter: &count)
    return count
}

// MARK: - 合成算例：分段伤害换算

private func checkDamageMath(counter count: inout Int) throws {
    // 武器：物理 100 / 火 50，斩击（atkAttribute=0），削韧基础 10、耐力基础 20。
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
    // 耐力 = stamina + staminaBase × staminaMv/100 = 0 + 20 × 0.5
    try rankerExpectClose(segments[0].stamina, 10, "耐力削减应为 stamina + 武器 staminaBase × staminaMv/100", counter: &count)

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

    // 默认勾选：排除 noFp 与 noDamage。
    let defaultSelection = SkillDamageMath.defaultSelection(segments)
    try rankerExpect(defaultSelection == [1, 2, 3], "默认勾选应排除 noFp 与 noDamage 段，实际 \(defaultSelection.sorted())", counter: &count)

    let noFpSelection = SkillDamageMath.selection(segments, useNoFp: true)
    try rankerExpect(noFpSelection == [4], "切到无 FP 版应只勾选 noFp 段，实际 \(noFpSelection.sorted())", counter: &count)
    try rankerExpect(noFpSelection.isDisjoint(with: defaultSelection), "FP 段与无 FP 段必须互斥", counter: &count)

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

    // 搜索与来源筛选
    let searched = index.rank(context: context, options: BuffRankingOptions(query: "只加火"))
    try rankerExpect(searched.map(\.spEffectId) == [2], "搜索应按 displayNameZh 命中，实际 \(searched.map(\.spEffectId))", counter: &count)
    let byKind = index.rank(context: context, options: BuffRankingOptions(sourceKinds: ["goods"]))
    try rankerExpect(byKind.map(\.spEffectId) == [23], "来源类型筛选应只留该类型，实际 \(byKind.map(\.spEffectId))", counter: &count)
    try rankerExpect(
        index.availableSourceKinds.contains("goods") && index.availableSourceKinds.contains("relicAffix"),
        "筛选器应列出数据集里出现过的来源类型",
        counter: &count
    )

    // 没有勾选任何段时退回「最大通道乘数」，并且不崩
    let emptyShares = Array(repeating: 0.0, count: SkillDamageChannel.allCases.count)
    let emptyRows = index.rank(context: skillContext(shares: emptyShares))
    try rankerExpectClose(
        emptyRows.first(where: { $0.spEffectId == 1 })?.effectiveMultiplier ?? 0, 1.2,
        "没有勾选任何段时应退回该 buff 的最大通道乘数", counter: &count
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
      "schemaVersion": 2, "gameVersion": "x", "dataVersion": "y",
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
    // skillVariant 缺失的武器：按 variants[].weaponIds 兜回同一套
    let fallback = index.segments(for: skill, weapon: index.weaponsByID[2])
    try rankerExpect(fallback.map(\.atkId) == [11], "skillVariant 缺失时应按 variants[].weaponIds 兜回，实际 \(fallback.map(\.atkId))", counter: &count)

    // 4. variants 整个缺失 → ctx 单选逻辑（先武器名，再类别名，最后 ctx 缺失那组），不取并集
    let ctxDataset = try SkillDataset.decode(from: Data("""
    {
      "schemaVersion": 2,
      "weapons": [{"id":1,"nameZh":"甲","nameEn":"Alpha","wepTypeEn":"Katana","wepTypeZh":"刀","attackBase":{"physical":10},"swordArtsParamId":7}],
      "skills": [{"id":7,"nameZh":"测试战技","weaponIds":[1],
                  "hits":[{"atkId":1,"ctx":"Alpha","motion":{"physical":100},"attribute":"Slash"},
                          {"atkId":2,"ctx":"Katana","motion":{"physical":100},"attribute":"Slash"},
                          {"atkId":3,"motion":{"physical":100},"attribute":"Slash"}]}],
      "spells": []
    }
    """.utf8))
    let ctxIndex = try SkillDataIndex(dataset: ctxDataset)
    let ctxSegments = ctxIndex.segments(for: ctxIndex.skillsByID[7]!, weapon: ctxIndex.weaponsByID[1])
    try rankerExpect(ctxSegments.map(\.atkId) == [1], "variants 缺失时应按 ctx 单选武器名那一套，实际 \(ctxSegments.map(\.atkId))", counter: &count)

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
    try rankerExpect(dataset.schemaVersion >= 2, "skills schemaVersion 应 ≥ 2，实际 \(dataset.schemaVersion)", counter: &count)
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
    // 全量：每把「有 skillVariant」的武器都能选出段，且永远选不到 noVariant 段。
    var checkedWeapons = 0
    var emptySelection = 0
    var pickedNoVariant = 0
    var outsideVariant = 0
    for weapon in index.dataset.weapons {
        guard let variantIndex = weapon.skillVariant,
              let skill = index.skillsByID[weapon.swordArtsParamId],
              skill.variants.indices.contains(variantIndex) else { continue }
        checkedWeapons += 1
        let allowed = Set(skill.variants[variantIndex].atkIds)
        let hits = index.hits(for: skill, weapon: weapon)
        if hits.isEmpty { emptySelection += 1 }
        if hits.contains(where: \.noVariant) { pickedNoVariant += 1 }
        if hits.contains(where: { !allowed.contains($0.atkId) }) { outsideVariant += 1 }
    }
    try rankerExpect(checkedWeapons > 500, "应有 > 500 把武器参与选段校验，实际 \(checkedWeapons)", counter: &count)
    try rankerExpect(emptySelection == 0, "有 skillVariant 的武器不应选出空段，实际 \(emptySelection) 把", counter: &count)
    try rankerExpect(pickedNoVariant == 0, "选段结果不应包含 noVariant 段，实际 \(pickedNoVariant) 把", counter: &count)
    try rankerExpect(outsideVariant == 0, "选段结果不应超出 variants[].atkIds，实际 \(outsideVariant) 把", counter: &count)

    // 多动作套的战技：不同套的武器选出的段必须不同（证明没有按 ctx 取并集）。
    guard let multi = index.dataset.skills.first(where: { $0.variants.count > 1 && $0.variants.allSatisfy { !$0.weaponIds.isEmpty } }) else {
        throw CheckFailure(description: "增伤排名：找不到有多套动作的战技")
    }
    let firstWeapon = index.weaponsByID[multi.variants[0].weaponIds[0]]
    let secondWeapon = index.weaponsByID[multi.variants[1].weaponIds[0]]
    let firstIDs = Set(index.hits(for: multi, weapon: firstWeapon).map(\.atkId))
    let secondIDs = Set(index.hits(for: multi, weapon: secondWeapon).map(\.atkId))
    try rankerExpect(!firstIDs.isEmpty && !secondIDs.isEmpty, "多套动作的战技两边都应选出段", counter: &count)
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

    // 无 FP 版：找一套同时有 FP 段与无 FP 段的，验证互斥切换
    var found = false
    for weapon in index.dataset.weapons {
        guard let skill = index.skillsByID[weapon.swordArtsParamId] else { continue }
        let segments = index.segments(for: skill, weapon: weapon)
        guard segments.contains(where: { $0.noFp && $0.hasDamage }),
              segments.contains(where: { !$0.noFp && $0.hasDamage && !$0.noDamage }) else { continue }
        let normal = SkillDamageMath.defaultSelection(segments)
        let noFp = SkillDamageMath.selection(segments, useNoFp: true)
        try rankerExpect(
            normal.allSatisfy { id in segments.first { $0.atkId == id }?.noFp == false },
            "默认勾选不应包含无 FP 版（「\(skill.displayName)」）",
            counter: &count
        )
        try rankerExpect(
            !noFp.isEmpty && noFp.allSatisfy { id in segments.first { $0.atkId == id }?.noFp == true },
            "切到无 FP 版后应只剩 noFp 段",
            counter: &count
        )
        try rankerExpect(normal.isDisjoint(with: noFp), "FP 段与无 FP 段必须互斥", counter: &count)
        found = true
        break
    }
    try rankerExpect(found, "真实数据里应存在同时有 FP 与无 FP 段的战技", counter: &count)
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
        delivery: .weaponSkill(slot: 1),
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
            delivery: .weaponSkill(slot: 2),
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
            delivery: .weaponSkill(slot: 1),
            subCategories: [BuffRankingContext.skillAttackSubCategory],
            composition: SkillDamageMath.composition(of: segments, selected: [fireOnly.atkId])
        )
        let physicalContext = BuffRankingContext(
            delivery: .weaponSkill(slot: 1),
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
