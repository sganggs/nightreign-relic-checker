import Foundation
import RelicCore

// 存档页优化（自动定位 / 报告导出 / 存档对比）的自检。
//
// 覆盖 RelicCore 里的三块纯逻辑：`SaveLocator`（CrossOver bottle 扫描，用临时
// 目录造结构）、`SaveReportBuilder`（文本 / CSV 报告）、`SaveComparator`
// （按角色槽位对比遗物多重集）。审计结论一律走 `SaveAuditPipeline`，
// 与存档检查页同一口径。

/// 本文件内的断言计数器（`main.swift` 的全局 `expect` 会重复计数，这里自己数）。
private struct CheckRun {
    private(set) var count = 0

    mutating func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw CheckFailure(description: message) }
        count += 1
    }
}

/// 由 `GameDataChecks.swift` 的列表调用；返回本组校验的条数。
func checkSaveScanFeatures() throws -> Int {
    var run = CheckRun()
    try checkSaveLocator(&run)
    let fixtures = try SaveFixtures()
    try checkSaveReport(&run, fixtures: fixtures)
    try checkSaveCompare(&run, fixtures: fixtures)
    return run.count
}

// MARK: - 自动定位（SaveLocator）

private func checkSaveLocator(_ run: inout CheckRun) throws {
    let fileManager = FileManager.default
    let root = fileManager.temporaryDirectory
        .appendingPathComponent("nightreign-locator-\(UUID().uuidString)", isDirectory: true)
    defer { try? fileManager.removeItem(at: root) }

    let bottles = root.appendingPathComponent("Bottles", isDirectory: true)

    /// 造一份 bottle 里的存档文件。
    @discardableResult
    func makeSave(
        bottle: String,
        user: String,
        account: String?,
        fileName: String,
        byteCount: Int,
        modified: Date
    ) throws -> URL {
        var directory = bottles
            .appendingPathComponent(bottle, isDirectory: true)
            .appendingPathComponent("drive_c", isDirectory: true)
            .appendingPathComponent("users", isDirectory: true)
            .appendingPathComponent(user, isDirectory: true)
            .appendingPathComponent("AppData", isDirectory: true)
            .appendingPathComponent("Roaming", isDirectory: true)
            .appendingPathComponent("Nightreign", isDirectory: true)
        if let account { directory = directory.appendingPathComponent(account, isDirectory: true) }
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(fileName)
        try Data(repeating: 0x41, count: byteCount).write(to: url)
        try fileManager.setAttributes([.modificationDate: modified], ofItemAtPath: url.path)
        return url
    }

    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let sl2 = try makeSave(
        bottle: "Nightreign", user: "crossover", account: "76561198000000000",
        fileName: "NR0000.sl2", byteCount: 32, modified: now.addingTimeInterval(-3600)
    )
    let co2 = try makeSave(
        bottle: "Nightreign", user: "crossover", account: "76561198000000000",
        fileName: "NR0000.co2", byteCount: 64, modified: now
    )
    let other = try makeSave(
        bottle: "Steam", user: "wineuser", account: "12345",
        fileName: "NR0000.sl2", byteCount: 16, modified: now.addingTimeInterval(-7200)
    )
    // 没有账号子目录的装法也要认。
    let loose = try makeSave(
        bottle: "Steam", user: "wineuser", account: nil,
        fileName: "NR0001.sl2", byteCount: 8, modified: now.addingTimeInterval(-10800)
    )
    // 大小写不敏感回退：bottle 里的 drive_c / users / AppData 写法取决于 Wine 版本，
    // 在大小写敏感的卷上只有回退分支能命中（这里用变体目录名把它走一遍）。
    let variantDirectory = bottles
        .appendingPathComponent("大小写变体", isDirectory: true)
        .appendingPathComponent("Drive_C", isDirectory: true)
        .appendingPathComponent("Users", isDirectory: true)
        .appendingPathComponent("crossover", isDirectory: true)
        .appendingPathComponent("appdata", isDirectory: true)
        .appendingPathComponent("roaming", isDirectory: true)
        .appendingPathComponent("NIGHTREIGN", isDirectory: true)
        .appendingPathComponent("76561198000000001", isDirectory: true)
    try fileManager.createDirectory(at: variantDirectory, withIntermediateDirectories: true)
    let variant = variantDirectory.appendingPathComponent("NR0000.sl2")
    try Data(repeating: 0x43, count: 24).write(to: variant)
    try fileManager.setAttributes(
        [.modificationDate: now.addingTimeInterval(-14400)],
        ofItemAtPath: variant.path
    )

    // 干扰项：备份与文本文件不是存档；结构不全的 bottle 要跳过。
    try Data([0x42]).write(to: sl2.deletingLastPathComponent().appendingPathComponent("NR0000.sl2.bak"))
    try Data([0x42]).write(to: sl2.deletingLastPathComponent().appendingPathComponent("readme.txt"))
    try fileManager.createDirectory(
        at: bottles.appendingPathComponent("空瓶/drive_c", isDirectory: true),
        withIntermediateDirectories: true
    )

    let found = SaveLocator.scan(bottlesRoot: bottles)
    // /var 与 /private/var 的符号链接差异不参与比较
    func resolved(_ url: URL) -> String { url.resolvingSymlinksInPath().path }

    try run.expect(found.count == 5, "应找到 5 份存档，实际 \(found.count)：\(found.map(\.fileName))")
    try run.expect(
        found.map { resolved($0.url) } == [co2, sl2, other, loose, variant].map(resolved),
        "结果应按修改时间倒序，实际 \(found.map { resolved($0.url) })"
    )
    try run.expect(
        found[4].bottleName == "大小写变体" && found[4].accountName == "76561198000000001",
        "目录名大小写变体（Drive_C / Users / appdata / roaming / NIGHTREIGN）也应扫到，实际 "
            + "\(found[4].bottleName) / \(found[4].accountName)"
    )
    try run.expect(found[0].isCoop, "NR0000.co2 应标记为无缝联机存档")
    try run.expect(!found[1].isCoop, "NR0000.sl2 不应标记为无缝联机存档")
    try run.expect(found[1].byteSize == 32, "应读出文件大小，实际 \(found[1].byteSize)")
    try run.expect(found[1].modifiedAt != nil, "应读出修改时间")
    try run.expect(
        found[1].bottleName == "Nightreign" && found[1].accountName == "76561198000000000",
        "应还原 bottle 名与账号目录，实际 \(found[1].bottleName) / \(found[1].accountName)"
    )
    try run.expect(
        found[1].locationLabel == "Nightreign · 76561198000000000",
        "定位标签应是「bottle · 账号」，实际 \(found[1].locationLabel)"
    )
    try run.expect(found[3].accountName.isEmpty, "没有账号子目录时 accountName 应为空")
    try run.expect(
        found[3].locationLabel == "Steam",
        "缺账号时定位标签应只剩 bottle，实际 \(found[3].locationLabel)"
    )
    try run.expect(
        !found.contains { $0.fileName.hasSuffix(".bak") || $0.fileName.hasSuffix(".txt") },
        "非 .sl2 / .co2 的文件不应出现在结果里"
    )
    try run.expect(found.map(\.id).count == Set(found.map(\.id)).count, "结果不应有重复路径")

    // 目录不存在只是没有结果，不应抛错
    let missing = SaveLocator.scan(bottlesRoot: root.appendingPathComponent("不存在的目录"))
    try run.expect(missing.isEmpty, "扫描不存在的目录应返回空数组")

    try run.expect(
        SaveLocator.isSaveFile(URL(fileURLWithPath: "/tmp/NR0000.SL2"))
            && SaveLocator.isSaveFile(URL(fileURLWithPath: "/tmp/save.co2"))
            && !SaveLocator.isSaveFile(URL(fileURLWithPath: "/tmp/save.txt")),
        "扩展名判定应忽略大小写并只认 .sl2 / .co2"
    )

    let home = URL(fileURLWithPath: "/Users/tester", isDirectory: true)
    try run.expect(
        SaveLocator.defaultBottlesRoot(homeDirectory: home).path
            == "/Users/tester/Library/Application Support/CrossOver/Bottles",
        "默认 bottles 根目录拼接错误：\(SaveLocator.defaultBottlesRoot(homeDirectory: home).path)"
    )
    try run.expect(
        SaveLocator.pathHint.contains("AppData/Roaming/Nightreign")
            && SaveLocator.pathHint.contains("选择存档文件"),
        "找不到存档时的提示应包含路径规则与手动选择兜底"
    )
}

// MARK: - 报告导出（SaveReportBuilder）

private func checkSaveReport(_ run: inout CheckRun, fixtures: SaveFixtures) throws {
    let save = fixtures.base
    let text = SaveReportBuilder.text(for: save, generatedAt: Date(timeIntervalSince1970: 0))

    try run.expect(text.contains("夜幕验物 · 存档检查报告"), "文本报告应有标题")
    try run.expect(text.contains("存档文件：NR0000.sl2"), "文本报告应写明存档文件名")
    try run.expect(text.contains("生成时间："), "传入时间时文本报告应写明生成时间")
    try run.expect(text.contains("存档校验和：正常"), "文本报告应写明校验和状态")
    try run.expect(
        text.contains("角色 2 个 · 遗物 4 件 · 非法 1 件"),
        "文本报告的汇总行不正确：\(text.split(separator: "\n").prefix(6).joined(separator: " / "))"
    )
    try run.expect(text.contains("角色：槽位 1 · 夜巫"), "文本报告应按角色分段")
    try run.expect(text.contains("[非法] 未知遗物 #424242（ID 424242）"), "文本报告应列出非法遗物与 ID")
    try run.expect(text.contains("种类：遗物"), "文本报告应写出遗物种类")
    try run.expect(text.contains("✗ 未知遗物 ID："), "文本报告应列出问题标题与说明")
    try run.expect(!text.contains("辽阔的火燃情景"), "文本报告只列非法/警告遗物，不应出现合法遗物")
    try run.expect(text.contains("未发现不合法遗物"), "全部合法的角色应显式说明")
    try run.expect(text.contains(SaveReportBuilder.disclaimer), "文本报告结尾应有口径说明")
    try run.expect(
        SaveReportBuilder.text(for: save).contains("生成时间：") == false,
        "不传时间时文本报告不应出现生成时间行"
    )

    let csv = SaveReportBuilder.csv(for: save)
    let lines = csv.components(separatedBy: "\r\n").filter { !$0.isEmpty }
    try run.expect(lines.count == 5, "CSV 应为 1 行表头 + 4 行遗物，实际 \(lines.count) 行")
    try run.expect(
        lines[0] == SaveReportBuilder.csvHeader.joined(separator: ","),
        "CSV 表头不正确：\(lines[0])"
    )
    try run.expect(
        lines[0] == "角色,遗物名,遗物ID,种类,颜色,状态,词条1,词条2,词条3,诅咒1,诅咒2,诅咒3,问题摘要",
        "CSV 列顺序应为 角色/遗物名/ID/种类/颜色/状态/词条1-3/诅咒1-3/问题摘要"
    )
    try run.expect(
        lines[1].hasPrefix("槽位 1 · 夜巫,辽阔的火燃情景,202,商店遗物,红,合法,"),
        "CSV 首行应写出角色、遗物、种类、颜色与状态：\(lines[1])"
    )
    try run.expect(lines[1].contains("（6630000）"), "CSV 词条列应是「词条名（ID）」：\(lines[1])")
    try run.expect(
        lines[1].hasSuffix(",,,,"),
        "无诅咒且无问题的遗物，诅咒列与问题摘要列应为空：\(lines[1])"
    )
    try run.expect(
        lines[3].contains(",非法,") && lines[3].contains("未知遗物 ID"),
        "CSV 应带出非法状态与问题摘要：\(lines[3])"
    )

    let deepCSV = SaveReportBuilder.csv(for: fixtures.other)
    try run.expect(
        deepCSV.contains("受到损伤时，会累积中毒量表（6820000）"),
        "CSV 的诅咒列应写出负面词条"
    )
    try run.expect(deepCSV.contains(",深夜遗物,"), "CSV 的种类列应区分深夜遗物")

    try run.expect(SaveReportBuilder.csvField("普通") == "普通", "普通字段不应加引号")
    try run.expect(SaveReportBuilder.csvField("a,b") == "\"a,b\"", "含逗号的字段应加引号")
    try run.expect(SaveReportBuilder.csvField("a\"b") == "\"a\"\"b\"", "字段内的引号应翻倍")
    try run.expect(SaveReportBuilder.csvField("=1+1") == "'=1+1", "以公式符号开头的字段应加撇号（防表格软件执行）")

    let date = Date(timeIntervalSince1970: 1_700_000_000)
    let fileName = SaveReportBuilder.suggestedFileName(for: save, format: .csv, date: date)
    try run.expect(
        fileName.hasPrefix("夜幕验物-存档报告-NR0000-") && fileName.hasSuffix(".csv"),
        "建议文件名不正确：\(fileName)"
    )
    try run.expect(
        SaveReportBuilder.suggestedFileName(for: save, format: .text).hasSuffix(".txt"),
        "文本报告的建议文件名应以 .txt 结尾"
    )
    try run.expect(
        SaveReportBuilder.content(for: save, format: .csv) == csv
            && SaveReportBuilder.content(for: save, format: .text, generatedAt: nil)
                == SaveReportBuilder.text(for: save),
        "content(for:format:) 应与 csv/text 一致"
    )

    // 深夜遗物的「种类」行不应把「深夜遗物」写两遍（kindLabel 本身就是「深夜遗物」）
    let deepSave = fixtures.deepFlagged
    try run.expect(
        deepSave.characters[0].relics[0].isDeep && deepSave.invalidCount == 1,
        "夹具前提：该件应是被判非法的深夜遗物"
    )
    let deepText = SaveReportBuilder.text(for: deepSave)
    guard let kindLine = deepText.split(separator: "\n").first(where: { $0.contains("种类：") }) else {
        throw CheckFailure(description: "深夜遗物的文本报告里应有「种类：」行")
    }
    try run.expect(
        kindLine.contains("深夜遗物"),
        "深夜遗物的种类行应写出「深夜遗物」：\(kindLine)"
    )
    try run.expect(
        kindLine.components(separatedBy: "深夜遗物").count == 2,
        "种类行不应重复输出「深夜遗物」：\(kindLine)"
    )

    // 「警告」等级当前不会被产出，恒为 0 的字段不应出现在报告里
    try run.expect(
        !text.contains("警告 0 件") && !deepText.contains("警告 0 件"),
        "没有警告时不应输出「警告 0 件」"
    )
    try run.expect(
        SaveReportBuilder.disclaimer.contains("只给出「非法」判定"),
        "口径说明应点明当前版本只产出「非法」判定"
    )

    // 解析失败的槽位在 CSV 里要留痕，否则拿 CSV 统计的人会整段漏掉这个角色
    let damagedCSV = SaveReportBuilder.csv(for: fixtures.damaged)
    let damagedLines = damagedCSV.components(separatedBy: "\r\n").filter { !$0.isEmpty }
    try run.expect(
        damagedLines.count == 5,
        "CSV 应为 1 行表头 + 3 行遗物 + 1 行解析失败占位，实际 \(damagedLines.count) 行"
    )
    guard let damagedRow = damagedLines.first(where: { $0.contains(SaveReportBuilder.csvParseErrorStatus) }) else {
        throw CheckFailure(description: "解析失败的槽位应在 CSV 里留一行占位：\(damagedLines)")
    }
    try run.expect(
        damagedRow.hasPrefix("槽位 2 · 槽位 2,,,,,\(SaveReportBuilder.csvParseErrorStatus),"),
        "占位行应写出角色与「槽位解析失败」状态，遗物列留空：\(damagedRow)"
    )
    try run.expect(
        damagedRow.contains("该槽位解密失败"),
        "占位行的问题摘要应带出 parseError：\(damagedRow)"
    )

    // SaveAuditPipeline 的 context 重载必须显式接收词条说明（漏传会让界面的 ⓘ 静默消失）
    let explanations = SaveAuditPipeline.explanations(from: fixtures.catalog)
    try run.expect(
        explanations[7_000_000] == "+1点生命力（固定+20点生命值上限）",
        "explanations(from:) 应收录词条库里的 explanation"
    )
    try run.expect(
        explanations[424_242] == nil,
        "explanations(from:) 不应凭空造出未收录词条的说明"
    )
    let context = RelicAuditContext(catalog: fixtures.catalog, relicData: fixtures.relicData)
    let viaContext = SaveAuditPipeline.audit(
        fixtures.baseParsed,
        context: context,
        affixExplanations: explanations
    )
    try run.expect(
        viaContext.affixExplanation(7_000_000) == save.affixExplanation(7_000_000),
        "context 重载传入说明后应与 catalog 重载口径一致"
    )
    try run.expect(
        viaContext.relicCount == save.relicCount && viaContext.invalidCount == save.invalidCount,
        "两个重载的审计结论应一致"
    )
}

// MARK: - 存档对比（SaveComparator）

private func checkSaveCompare(_ run: inout CheckRun, fixtures: SaveFixtures) throws {
    let result = SaveComparator.compare(base: fixtures.base, other: fixtures.other)

    try run.expect(result.baseFileName == "NR0000.sl2" && result.otherFileName == "备份.sl2", "应记录两份存档的文件名")
    try run.expect(result.characters.map(\.slot) == [0, 1, 2], "应按槽位升序列出两份存档槽位的并集")

    let slot0 = result.characters[0]
    try run.expect(slot0.baseTotal == 3 && slot0.otherTotal == 3, "槽位 1 的两侧遗物数应为 3 / 3")
    try run.expect(slot0.removed.count == 1 && slot0.removed[0].count == 1, "槽位 1 应少掉 1 件重复的商店遗物")
    try run.expect(slot0.removed[0].identity.itemID == 202, "减少的应是 ID 202 的遗物")
    try run.expect(slot0.removed[0].relic.result.status == .valid, "减少项应带审计结论（合法）")
    try run.expect(slot0.removed[0].relic.statusLabel == "合法", "减少项的状态文案应为「合法」")
    try run.expect(slot0.added.count == 1 && slot0.added[0].count == 1, "槽位 1 应新增 1 件深夜遗物")
    try run.expect(slot0.added[0].relic.relic.itemID == 2_000_002, "新增的应是 ID 2000002 的深夜遗物")
    try run.expect(slot0.added[0].relic.isDeep, "新增项应识别为深夜遗物")
    try run.expect(slot0.added[0].relic.result.status == .valid, "新增的深夜遗物审计应为合法")
    try run.expect(slot0.presenceNote == nil, "两侧同名角色不应有额外提示")
    try run.expect(!slot0.isIdentical, "有增减的槽位 isIdentical 应为 false")

    // 424242 两侧各一件：不该出现在增减里
    try run.expect(
        !slot0.added.contains { $0.identity.itemID == 424_242 }
            && !slot0.removed.contains { $0.identity.itemID == 424_242 },
        "两侧数量相同的遗物不应出现在增减列表里"
    )

    let slot1 = result.characters[1]
    try run.expect(slot1.otherName == nil && slot1.removedCount == 1, "只在基准存档存在的槽位应整槽记为减少")
    try run.expect(slot1.presenceNote == "该槽位只在基准存档中存在", "应提示槽位只在基准存档存在")
    let slot2 = result.characters[2]
    try run.expect(slot2.baseName == nil && slot2.addedCount == 1, "只在对比存档存在的槽位应整槽记为新增")
    try run.expect(slot2.presenceNote == "该槽位只在对比存档中存在", "应提示槽位只在对比存档存在")

    try run.expect(result.totalAdded == 2 && result.totalRemoved == 2, "总计应为新增 2 件、减少 2 件")
    try run.expect(result.summaryText == "新增 2 件 · 减少 2 件", "汇总文案不正确：\(result.summaryText)")
    try run.expect(result.hasDifferences, "两份不同的存档应判定为有差异")

    let self1 = SaveComparator.compare(base: fixtures.base, other: fixtures.base)
    try run.expect(!self1.hasDifferences, "同一份存档自比应没有差异")
    try run.expect(self1.characters.allSatisfy(\.isIdentical), "同一份存档自比每个槽位都应一致")

    // 身份口径：行序不计入差异，配对关系计入
    let a = SaveRelicIdentity(SaveRelic(index: 0, itemID: 202, effects: [1, 2, 3], curses: [-1, -1, -1]))
    let b = SaveRelicIdentity(SaveRelic(index: 9, itemID: 202, effects: [3, 1, 2], curses: [-1, -1, -1]))
    let c = SaveRelicIdentity(SaveRelic(index: 0, itemID: 202, effects: [1, 2, 3], curses: [7, -1, -1]))
    let d = SaveRelicIdentity(SaveRelic(index: 0, itemID: 203, effects: [1, 2, 3], curses: [-1, -1, -1]))
    let e = SaveRelicIdentity(SaveRelic(index: 0, itemID: 202, effects: [1, 2, 3, 4], curses: [0, 0xFFFF_FFFF]))
    try run.expect(a == b, "行序不同、内容相同的遗物应视为同一件")
    try run.expect(a != c, "带诅咒与不带诅咒应视为不同的遗物")
    try run.expect(a != d, "遗物 ID 不同应视为不同的遗物")
    try run.expect(a == e, "多余的第 4 条词条应被截断，0 / 0xFFFFFFFF 应归一化为空")
    try run.expect(a.key == "202|1:-1|2:-1|3:-1", "身份键不正确：\(a.key)")
    try run.expect(d > a, "身份排序应先比遗物 ID")

    // 审计管线产出的展示数据
    try run.expect(fixtures.base.relicCount == 4 && fixtures.base.invalidCount == 1, "审计汇总应为 4 件 / 1 件非法")
    try run.expect(fixtures.base.characters[0].displayName == "槽位 1 · 夜巫", "角色显示名不正确")
    try run.expect(fixtures.base.affixLabel(-1) == "（空）", "空词条标签应为「（空）」")
    try run.expect(
        fixtures.base.affixLabel(7_000_000) == "生命力＋１（7000000）",
        "词条标签应为「名称（ID）」：\(fixtures.base.affixLabel(7_000_000))"
    )
    try run.expect(
        fixtures.base.affixExplanation(7_000_000) == "+1点生命力（固定+20点生命值上限）",
        "应带出词条库里的 explanation"
    )
    try run.expect(fixtures.base.affixExplanation(424_242) == nil, "没有说明的词条应返回 nil")
    try run.expect(fixtures.base.affixName(424_242) == "未知词条 #424242", "未知词条应有兜底名称")

    // 解密失败的槽位不能被当成空槽位整槽报成「减少 N 件」
    let damagedResult = SaveComparator.compare(base: fixtures.base, other: fixtures.damaged)
    guard let damagedSlot = damagedResult.characters.first(where: { $0.slot == 1 }) else {
        throw CheckFailure(description: "对比结果里应有槽位 2")
    }
    try run.expect(damagedSlot.baseParseError == nil, "基准存档的槽位 2 解析正常")
    try run.expect(
        damagedSlot.otherParseError?.contains("解密失败") == true,
        "对比存档的解析错误应透传到对比结果，实际 \(String(describing: damagedSlot.otherParseError))"
    )
    try run.expect(damagedSlot.hasParseError, "有一侧解析失败的槽位应标记 hasParseError")
    guard let parseNote = damagedSlot.parseNote else {
        throw CheckFailure(description: "解析失败的槽位应给出提示，而不是只显示「减少 1 件」")
    }
    try run.expect(
        parseNote.contains("解析失败") && parseNote.contains("不可信") && parseNote.contains("对比存档"),
        "解析失败提示应说明是哪一侧、且数字不可信：\(parseNote)"
    )
    try run.expect(damagedSlot.removedCount == 1, "槽位内的原始差值仍然算得出来")
    try run.expect(
        damagedResult.totalRemoved == 0 && damagedResult.totalAdded == 0,
        "解析失败槽位的增减不应计入总数，实际 \(damagedResult.summaryText)"
    )
    try run.expect(
        damagedResult.hasUnreliableSlots && damagedResult.unreliableCharacters.map(\.slot) == [1],
        "对比结果应能列出解析失败的槽位"
    )
    try run.expect(
        damagedResult.hasDifferences,
        "总数被排除后仍有解析失败的槽位，不能对外宣称「完全一致」"
    )
    try run.expect(damagedSlot.hasAnyDifference, "解析失败的槽位不应被「只看有差异的角色」过滤掉")

    // 只改角色名的槽位：遗物一致，但提示不能被「只看有差异的角色」吞掉
    let renameResult = SaveComparator.compare(base: fixtures.base, other: fixtures.renamed)
    let renamedSlot = renameResult.characters[0]
    try run.expect(renamedSlot.isIdentical, "只改名的槽位遗物多重集仍然一致")
    try run.expect(
        renamedSlot.presenceNote == "两份存档的同一槽位角色名不同：夜巫 → 追踪者",
        "应提示两侧角色名不同，实际 \(String(describing: renamedSlot.presenceNote))"
    )
    try run.expect(renamedSlot.hasAnyDifference, "改名的槽位不应被判为「没有差异」而隐藏")
    try run.expect(
        renameResult.characters[1].hasAnyDifference == false,
        "既没改名也没增减的槽位仍应被判为没有差异"
    )
    try run.expect(
        renameResult.hasDifferences && renameResult.hasPresenceNotes,
        "只有改名差异时面板不应写「两份存档的遗物完全一致」"
    )
    try run.expect(
        renameResult.totalAdded == 0 && renameResult.totalRemoved == 0,
        "改名不应产生遗物增减"
    )
}

// MARK: - 夹具

/// 用真实词条库 / 遗物表审计出的两份存档（不读真实存档文件，直接合成解析结果）。
private struct SaveFixtures {
    let catalog: AffixCatalog
    let relicData: RelicCatalog
    let baseParsed: SaveParseResult
    let base: AuditedSave
    let other: AuditedSave
    /// 与 `base` 只差「槽位 2 解密失败」的一份：用来验证解析失败不被当成空槽位。
    let damaged: AuditedSave
    /// 与 `base` 只差「槽位 1 角色改名」的一份。
    let renamed: AuditedSave
    /// 含一件非法深夜遗物：用来检查文本报告的「种类」行。
    let deepFlagged: AuditedSave

    init() throws {
        let resources = URL(fileURLWithPath: #filePath)  // …/Sources/RelicCoreChecks/SaveCompareChecks.swift
            .deletingLastPathComponent()                 // …/Sources/RelicCoreChecks
            .deletingLastPathComponent()                 // …/Sources
            .deletingLastPathComponent()                 // …/macos
            .appendingPathComponent("Sources/NightreignRelicChecker/Resources", isDirectory: true)
        let catalog = try CatalogLoader.load(from: resources.appendingPathComponent("affixes.json"))
        let relicData = try RelicDataLoader.load(from: resources.appendingPathComponent("relics.json"))

        func relic(_ index: Int, _ itemID: Int, _ effects: [Int], _ curses: [Int] = [-1, -1, -1]) -> SaveRelic {
            SaveRelic(index: index, itemID: itemID, effects: effects, curses: curses)
        }

        let shop = [6_630_000, 7_000_000, 7_000_100]
        let baseParsed = SaveParseResult(
            fileName: "NR0000.sl2",
            checksumOk: true,
            characters: [
                SaveCharacter(slot: 0, name: "夜巫", parseError: nil, relics: [
                    relic(0, 202, shop),
                    relic(1, 202, shop),
                    relic(2, 424_242, [-1, -1, -1])
                ]),
                SaveCharacter(slot: 1, name: "追踪者", parseError: nil, relics: [relic(0, 202, shop)])
            ]
        )
        let otherParsed = SaveParseResult(
            fileName: "备份.sl2",
            checksumOk: true,
            characters: [
                SaveCharacter(slot: 0, name: "夜巫", parseError: nil, relics: [
                    // 同一件遗物，只是保存顺序不同：不应算作差异
                    relic(0, 202, [7_000_000, 6_630_000, 7_000_100]),
                    relic(1, 424_242, [-1, -1, -1]),
                    relic(2, 2_000_002, [6_005_601, 6_003_000, 6_003_100], [6_820_000, -1, -1])
                ]),
                SaveCharacter(slot: 2, name: "复仇者", parseError: nil, relics: [relic(0, 202, shop)])
            ]
        )

        // 槽位解密失败：SaveFileParser 仍然产出一个 SaveCharacter，只是 parseError 非空、relics 为空
        let damagedParsed = SaveParseResult(
            fileName: "损坏.sl2",
            checksumOk: true,
            characters: [
                baseParsed.characters[0],
                SaveCharacter(
                    slot: 1,
                    name: "槽位 2",
                    parseError: "该槽位解密失败：条目密文长度不是 16 的倍数",
                    relics: []
                )
            ]
        )
        let renamedParsed = SaveParseResult(
            fileName: "改名.sl2",
            checksumOk: true,
            characters: [
                SaveCharacter(slot: 0, name: "追踪者", parseError: nil, relics: baseParsed.characters[0].relics),
                baseParsed.characters[1]
            ]
        )
        // 深夜遗物 + 普通池词条、没有诅咒：审计必判非法，才会被文本报告列出来
        let deepFlaggedParsed = SaveParseResult(
            fileName: "深夜.sl2",
            checksumOk: true,
            characters: [
                SaveCharacter(slot: 0, name: "无赖", parseError: nil, relics: [
                    relic(0, 2_000_002, [7_000_000, -1, -1])
                ])
            ]
        )

        self.catalog = catalog
        self.relicData = relicData
        self.baseParsed = baseParsed
        base = SaveAuditPipeline.audit(baseParsed, catalog: catalog, relicData: relicData)
        other = SaveAuditPipeline.audit(otherParsed, catalog: catalog, relicData: relicData)
        damaged = SaveAuditPipeline.audit(damagedParsed, catalog: catalog, relicData: relicData)
        renamed = SaveAuditPipeline.audit(renamedParsed, catalog: catalog, relicData: relicData)
        deepFlagged = SaveAuditPipeline.audit(deepFlaggedParsed, catalog: catalog, relicData: relicData)
    }
}
