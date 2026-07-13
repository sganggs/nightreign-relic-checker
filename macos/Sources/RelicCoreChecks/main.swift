import Foundation
import RelicCore

struct CheckFailure: Error, CustomStringConvertible {
    let description: String
}

var passed = 0

func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    guard condition() else { throw CheckFailure(description: message) }
    passed += 1
}

func makeAffix(
    id: Int,
    compatibility: Int,
    sort: Int,
    pools: [Int] = [110, 210, 310],
    requiresCurse: Bool = false
) -> Affix {
    Affix(
        effectID: id,
        name: "词条 \(id)",
        compatibilityID: compatibility,
        sortID: sort,
        poolIDs: pools,
        requiresCurse: requiresCurse
    )
}

let checker = LegalityChecker()

let valid = checker.check([
    makeAffix(id: 10, compatibility: 1, sort: 100),
    makeAffix(id: 20, compatibility: 2, sort: 200),
    makeAffix(id: 30, compatibility: -1, sort: 300)
], mode: .currentNormal)
try expect(valid.status == .valid, "合法且有序的组合应通过")

let wrongOrder = checker.check([
    makeAffix(id: 30, compatibility: 3, sort: 300),
    makeAffix(id: 10, compatibility: 1, sort: 100),
    makeAffix(id: 20, compatibility: 2, sort: 200)
], mode: .currentNormal)
try expect(wrongOrder.status == .wrongOrder, "乱序组合应报告顺序错误")
try expect(wrongOrder.orderedAffixes.map(\.effectID) == [10, 20, 30], "应返回规范顺序")

let tieBreak = checker.canonicalOrder([
    makeAffix(id: 12, compatibility: 1, sort: 100),
    makeAffix(id: 10, compatibility: 2, sort: 100),
    makeAffix(id: 11, compatibility: 3, sort: 100)
])
try expect(tieBreak.map(\.effectID) == [10, 11, 12], "sortId 相同时应按 effectId 排序")

let duplicate = makeAffix(id: 10, compatibility: -1, sort: 100)
let duplicateResult = checker.check([
    duplicate,
    duplicate,
    makeAffix(id: 30, compatibility: -1, sort: 300)
], mode: .currentNormal)
try expect(duplicateResult.status == .invalid, "重复 effectId 应非法")
try expect(duplicateResult.issues.contains { $0.kind == .duplicate }, "应给出重复原因")

let conflict = checker.check([
    makeAffix(id: 10, compatibility: 100, sort: 100),
    makeAffix(id: 20, compatibility: 100, sort: 200),
    makeAffix(id: 30, compatibility: -1, sort: 300)
], mode: .currentNormal)
try expect(conflict.status == .invalid, "compatibilityId 冲突应非法")
try expect(conflict.issues.contains { $0.kind == .conflict }, "应给出互斥池原因")

let minusOne = checker.check([
    makeAffix(id: 10, compatibility: -1, sort: 100),
    makeAffix(id: 20, compatibility: -1, sort: 200),
    makeAffix(id: 30, compatibility: -1, sort: 300)
], mode: .currentNormal)
try expect(minusOne.status == .valid, "compatibilityId -1 允许重复")

let unavailable = checker.check([
    makeAffix(id: 10, compatibility: 1, sort: 100),
    makeAffix(id: 20, compatibility: 2, sort: 200),
    makeAffix(id: 30, compatibility: 3, sort: 300, pools: [2_000_000])
], mode: .currentNormal)
try expect(unavailable.status == .invalid, "不在当前非零权重池应非法")
try expect(unavailable.issues.contains { $0.kind == .unavailable }, "应给出出货池原因")

let deepPoolTemplates = [
    [2_000_000, 2_000_000, 2_000_000],
    [2_000_000, 2_000_000, 2_100_000],
    [2_000_000, 2_100_000, 2_100_000],
    [2_100_000, 2_100_000, 2_100_000],
    [2_000_000, 2_000_000, 2_200_000],
    [2_000_000, 2_200_000, 2_200_000],
    [2_200_000, 2_200_000, 2_200_000]
]
try expect(CheckMode.deepPositive.slotPoolSequences == deepPoolTemplates, "深夜模式应使用七种真实三词条槽池模板")
try expect(CheckMode.deepPositive.eligiblePoolIDs == [2_000_000, 2_100_000, 2_200_000], "深夜候选筛选应保留 A/B/C 池并集")

for (templateIndex, template) in deepPoolTemplates.enumerated() {
    let affixes = template.enumerated().map { affixIndex, poolID in
        makeAffix(
            id: 10_000 + templateIndex * 10 + affixIndex,
            compatibility: 100 + affixIndex,
            sort: 100 + affixIndex,
            pools: [poolID],
            requiresCurse: poolID == 2_000_000
        )
    }
    let result = checker.check(affixes, mode: .deepPositive)
    try expect(result.status == .valid, "深夜真实模板 \(template) 应通过正面预检")
    try expect(result.warnings.contains { $0.kind == .cursePairing }, "深夜真实模板必须提示完整诅咒验证范围")
}

let impossibleDeepABC = checker.check([
    makeAffix(id: 20_010, compatibility: 1, sort: 100, pools: [2_000_000], requiresCurse: true),
    makeAffix(id: 20_020, compatibility: 2, sort: 200, pools: [2_100_000]),
    makeAffix(id: 20_030, compatibility: 3, sort: 300, pools: [2_200_000])
], mode: .deepPositive)
try expect(impossibleDeepABC.status == .invalid, "原始参数中不存在的深夜 A/B/C 三槽模板应判非法")
try expect(
    impossibleDeepABC.issues.contains { $0.kind == .unavailable && $0.title == "不符合当前槽池模板" },
    "A/B/C 组合应明确报告槽池模板不匹配"
)

let sourceFile = URL(fileURLWithPath: #filePath)
let projectRoot = sourceFile.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
let catalogURL = projectRoot.appendingPathComponent("Sources/NightreignRelicChecker/Resources/affixes.json")
let catalog = try CatalogLoader.load(from: catalogURL)

try expect(catalog.affixes.count == 527, "总记录数应为 527")
try expect(catalog.affixes.filter { !$0.isCurse }.count == 503, "正面词条应为 503")
try expect(catalog.affixes.filter { $0.poolIDs.contains(110) }.count == 340, "当前普通池应为 340")
try expect(catalog.affixes.filter { $0.poolIDs.contains(100) }.count == 290, "旧普通池应为 290")
try expect(Set(catalog.affixes.map(\.effectID)).count == catalog.affixes.count, "effectId 必须唯一")
try expect(catalog.affixes.filter { $0.popularity != nil }.count == 19, "应恢复 19 条热门度")

let reportedDeepIDs = [6_005_601, 6_610_400, 6_611_002]
let reportedDeepAffixes = reportedDeepIDs.compactMap { effectID in
    catalog.affixes.first { $0.effectID == effectID }
}
try expect(reportedDeepAffixes.count == 3, "截图中的三个真实深夜词条必须存在于词条库")
try expect(reportedDeepAffixes.allSatisfy { $0.poolIDs == [2_000_000] && $0.requiresCurse }, "截图词条应全部为需要诅咒的 A-only 词条")

let reportedDeepResult = checker.check(reportedDeepAffixes, mode: .deepPositive)
try expect(reportedDeepResult.status == .valid, "截图中的 A/A/A 深夜正面组合应通过")
try expect(reportedDeepResult.orderedAffixes.map(\.effectID) == reportedDeepIDs, "截图中的深夜词条顺序应正确")
try expect(reportedDeepResult.issues.isEmpty, "截图中的深夜正面组合不应报告非法原因")
guard let reportedWarning = reportedDeepResult.warnings.first(where: { $0.kind == .cursePairing }) else {
    throw CheckFailure(description: "截图中的深夜组合缺少诅咒验证警告")
}
try expect(reportedWarning.effectIDs == reportedDeepIDs, "诅咒警告应标记全部三个 A-only 词条")
try expect(reportedWarning.detail.contains("3 条为仅 A 池词条"), "诅咒警告应明确 A-only 词条数量")
try expect(reportedWarning.detail.contains("至少需要 3 个对应诅咒槽"), "诅咒警告应明确完整遗物所需最低诅咒槽数量")
try expect(reportedDeepResult.message.contains("不等同"), "深夜正面通过不得冒充完整遗物合法")

let current = catalog.affixes.filter { $0.poolIDs.contains(110) }
try expect(current.allSatisfy { $0.poolIDs.contains(210) && $0.poolIDs.contains(310) }, "当前普通三槽候选集合应相等")

let legacy = catalog.affixes.filter { $0.poolIDs.contains(100) }
try expect(legacy.allSatisfy { $0.poolIDs.contains(200) && $0.poolIDs.contains(300) }, "旧普通三槽候选集合应相等")

let attackGroup = current.filter { $0.compatibilityID == 100 }
try expect(attackGroup.count > 2, "攻击力互斥池应含多条词条")
guard let unrestricted = current.first(where: { $0.compatibilityID != 100 }) else {
    throw CheckFailure(description: "当前池缺少攻击池以外的测试词条")
}
let realConflictSample = checker.canonicalOrder(Array(attackGroup.prefix(2)) + [unrestricted])
try expect(checker.check(realConflictSample, mode: .currentNormal).status == .invalid, "真实数据中的同池组合应非法")

if let random = checker.randomCombination(from: catalog.affixes, mode: .currentNormal) {
    try expect(checker.check(random, mode: .currentNormal).status == .valid, "随机生成结果必须合法")
} else {
    throw CheckFailure(description: "无法从真实词条库生成合法组合")
}

print("RelicCoreChecks: \(passed) checks passed")
