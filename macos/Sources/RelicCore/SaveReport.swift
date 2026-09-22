import Foundation

/// 存档报告的导出格式。
public enum SaveReportFormat: String, CaseIterable, Identifiable, Sendable {
    /// 人读的文本报告：按角色列出每件非法遗物的种类、词条与问题。
    case text
    /// 表格：每行一件遗物，便于在表格软件里排序筛选。
    case csv

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .text: return "文本报告（.txt）"
        case .csv: return "表格（.csv）"
        }
    }

    public var fileExtension: String {
        switch self {
        case .text: return "txt"
        case .csv: return "csv"
        }
    }
}

/// 报告抬头里的「词条库」一行所需的信息。
///
/// 存档审计本身不读这些字段，只是把「用哪一份数据判的」写进报告，便于事后复核。
public struct SaveReportCatalogInfo: Sendable {
    /// 数据来源文案（「内置数据」/「自定义数据」，与设置页同一份写法）。
    public let origin: String
    public let gameVersion: String
    public let dataVersion: String

    public init(origin: String, gameVersion: String, dataVersion: String) {
        self.origin = origin
        self.gameVersion = gameVersion
        self.dataVersion = dataVersion
    }

    /// 「内置数据 · 1.03（数据 2026-01-01）」。
    public var line: String {
        var text = (origin.isEmpty ? "内置数据" : origin) + " · "
            + (gameVersion.isEmpty ? "未知版本" : gameVersion)
        if !dataVersion.isEmpty { text += "（数据 \(dataVersion)）" }
        return text
    }
}

/// 把一份已审计的存档渲染成可导出的报告（纯字符串生成，无任何 I/O）。
///
/// 口径与 Windows 端 `renderer/savereport.js` 逐行一致（同一份存档在两端导出
/// 的 TXT / CSV 应当逐行相同），改一处必须改另一处：
///   * 抬头固定：标题 / 分隔线 / 存档文件 / 生成时间（可省）/ 存档校验和 /
///     汇总 / 词条库（可省）/ 说明；
///   * 「警告」当前不会被 `RelicAuditor` 产出，恒为 0 的字段不写进报告，免得
///     读者误以为「已检查过、没有告警」；
///   * 存档判定走 `RelicAuditor`（不接受 `CheckMode`），与词条组合检查页顶部的
///     「校验口径」无关，说明行里明确写出来。
public enum SaveReportBuilder {
    /// 抬头 / 角色分段的分隔线宽度（ASCII，记事本与表格软件里都不会错位）。
    static let ruleWidth = 46
    static var heavyRule: String { String(repeating: "=", count: ruleWidth) }
    static var lightRule: String { String(repeating: "-", count: ruleWidth) }

    /// CSV 表头（与 `csv(for:)` 的列顺序一致）。
    public static let csvHeader = [
        "角色", "槽位", "遗物名", "遗物ID", "种类", "颜色", "状态",
        "词条1", "词条2", "词条3", "诅咒1", "诅咒2", "诅咒3", "问题摘要"
    ]

    /// 解析失败的槽位在「状态」列里的标记（CSV 里没有遗物行，用它留痕）。
    public static let csvParseErrorStatus = "槽位解析失败"

    /// 抬头里的说明行：存档判定与顶部「校验口径」无关。
    public static let disclaimer =
        "说明：存档判定只依据内置的词条库与遗物表，不受顶部「校验口径」影响"
        + "（口径只作用于词条组合检查页）；本报告由离线社区工具生成，不构成官方判定。"

    public static func content(
        for save: AuditedSave,
        format: SaveReportFormat,
        generatedAt: Date? = nil,
        catalog: SaveReportCatalogInfo? = nil
    ) -> String {
        switch format {
        case .text: return text(for: save, generatedAt: generatedAt, catalog: catalog)
        case .csv: return csv(for: save)
        }
    }

    // MARK: - 文本报告

    public static func text(
        for save: AuditedSave,
        generatedAt: Date? = nil,
        catalog: SaveReportCatalogInfo? = nil
    ) -> String {
        var lines: [String] = []
        lines.append("夜幕验物 · 存档检查报告")
        lines.append(heavyRule)
        lines.append("存档文件：" + (save.fileName.isEmpty ? "未知" : save.fileName))
        if let generatedAt {
            lines.append("生成时间：\(timestamp(generatedAt))")
        }
        lines.append("存档校验和：" + (save.checksumOk ? "通过" : "异常（结果仅供参考）"))
        lines.append("角色 \(save.characters.count) 个 · "
            + countsText(total: save.relicCount, invalid: save.invalidCount, warning: save.warningCount))
        if let catalog {
            lines.append("词条库：" + catalog.line)
        }
        lines.append(disclaimer)
        lines.append("")

        if save.characters.isEmpty {
            lines.append("未在该存档中找到已占用的角色槽位。")
        }

        for character in save.characters {
            lines.append(lightRule)
            lines.append(character.displayName)
            if let parseError = character.parseError {
                lines.append("  该槽位解析失败：\(parseError)")
                lines.append("")
                continue
            }

            let flagged = character.relics.filter { $0.statusLabel != "合法" }
            lines.append("  " + countsText(
                total: character.relics.count,
                invalid: character.invalidCount,
                warning: character.warningCount
            ))
            if flagged.isEmpty {
                lines.append(character.relics.isEmpty ? "  该角色没有持有任何遗物。" : "  未发现不合法遗物。")
            }
            for relic in flagged {
                lines.append("")
                lines.append(contentsOf: relicLines(relic, save: save))
            }
            lines.append("")
        }

        // 落盘时统一 CRLF，与 Windows 端（savefile.NormalizeCRLF）字节一致。
        return lines.joined(separator: "\r\n") + "\r\n"
    }

    /// 「遗物 N 件 · 非法 M 件[ · 警告 K 件]」：警告恒为 0 时不写这一段。
    private static func countsText(total: Int, invalid: Int, warning: Int) -> String {
        var text = "遗物 \(total) 件 · 非法 \(invalid) 件"
        if warning > 0 { text += " · 警告 \(warning) 件" }
        return text
    }

    private static func relicLines(_ relic: AuditedSave.AuditedRelic, save: AuditedSave) -> [String] {
        var lines: [String] = []
        lines.append("  [\(relic.statusLabel)] \(relic.displayName)（ID \(relic.relic.itemID)）")
        // kindLabel 在 info.deep 时本身就是「深夜遗物」，不再重复追加标签。
        lines.append("    种类：\(relic.kindLabel) · \(relic.colorText) · 存档内第 \(relic.relic.index + 1) 件")

        for row in 0..<3 {
            let effect = value(relic.relic.effects, row)
            let curse = value(relic.relic.curses, row)
            guard effect != -1 || curse != -1 else { continue }
            var line = "    词条\(row + 1)：" + save.affixLabel(effect)
            if curse != -1 {
                line += "｜诅咒：" + save.affixLabel(curse)
            }
            lines.append(line)
        }

        for issue in relic.result.issues {
            lines.append("    ✗ \(issue.title)：\(issue.detail)")
        }
        for warning in relic.result.warnings {
            lines.append("    ! \(warning.title)：\(warning.detail)")
        }
        if let official = relic.result.officialEffects {
            let text = official.filter { $0 != -1 }.map { save.affixLabel($0) }.joined(separator: "、")
            if !text.isEmpty {
                lines.append("    官方固定词条（可据此改回）：\(text)")
            }
        }
        if let ordered = relic.result.orderedEffects {
            let text = ordered.map { save.affixLabel($0) }.joined(separator: "、")
            lines.append("    正确的词条顺序：\(text)")
        }
        return lines
    }

    // MARK: - CSV

    public static func csv(for save: AuditedSave) -> String {
        var rows: [String] = [csvHeader.map(csvField).joined(separator: ",")]
        for character in save.characters {
            let slot = String(character.slot + 1)
            let name = character.name.isEmpty ? "未命名" : character.name
            // 槽位解密失败时 relics 为空，若不补一行，拿 CSV 做统计的人会整段漏掉这个角色。
            if let parseError = character.parseError {
                var fields = [name, slot, "", "", "", "", csvParseErrorStatus]
                fields += Array(repeating: "", count: 6)
                fields.append(parseError)
                rows.append(fields.map(csvField).joined(separator: ","))
            }
            for relic in character.relics {
                var fields = [
                    name,
                    slot,
                    relic.displayName,
                    String(relic.relic.itemID),
                    relic.kindLabel,
                    relic.colorText,
                    relic.statusLabel
                ]
                fields += (0..<3).map { affixCell(value(relic.relic.effects, $0), save: save) }
                fields += (0..<3).map { affixCell(value(relic.relic.curses, $0), save: save) }
                fields.append(issueSummary(relic))
                rows.append(fields.map(csvField).joined(separator: ","))
            }
        }
        // RFC 4180 的 CRLF，表格软件（含 Excel）识别最稳。
        return rows.joined(separator: "\r\n") + "\r\n"
    }

    /// 单件遗物的问题摘要：「标题：说明」用「；」串起来，警告加「警告：」前缀。
    public static func issueSummary(_ relic: AuditedSave.AuditedRelic) -> String {
        let issues = relic.result.issues.map { "\($0.title)：\($0.detail)" }
        let warnings = relic.result.warnings.map { "警告：\($0.title)：\($0.detail)" }
        return (issues + warnings).joined(separator: "；")
    }

    private static func affixCell(_ effectID: Int, save: AuditedSave) -> String {
        effectID == -1 ? "" : save.affixLabel(effectID)
    }

    /// CSV 字段转义：含分隔符/引号/换行时加引号并把引号翻倍；
    /// 以 `= + - @` 开头的字段（角色名是玩家可控内容）前面补一个撇号，
    /// 避免被表格软件当成公式执行。纯数字（含负数）不加撇号：遗物 ID 与槽位号
    /// 要保持数值列。
    public static func csvField(_ value: String) -> String {
        var text = value
        if let first = text.first, "=+-@\t\r".contains(first), !isPlainNumber(text) {
            text = "'" + text
        }
        guard text.contains(where: { ",\"\n\r".contains($0) }) else { return text }
        return "\"" + text.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    /// `-?\d+(\.\d+)?` 的手写版（避免为一个小判断引入 NSRegularExpression）。
    private static func isPlainNumber(_ value: String) -> Bool {
        var rest = Substring(value)
        if rest.first == "-" { rest = rest.dropFirst() }
        guard !rest.isEmpty else { return false }
        let parts = rest.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count <= 2 else { return false }
        return parts.allSatisfy { !$0.isEmpty && $0.allSatisfy(\.isASCII) && $0.allSatisfy(\.isNumber) }
    }

    // MARK: - 文件名

    /// 建议的导出文件名：`夜幕验物-存档报告-NR0000-20260922-120000.txt`。
    public static func suggestedFileName(
        for save: AuditedSave,
        format: SaveReportFormat,
        date: Date? = nil
    ) -> String {
        let base = (save.fileName as NSString).deletingPathExtension
            .trimmingCharacters(in: .whitespaces)
        let safeBase = base.isEmpty ? "存档" : sanitized(base)
        var name = "夜幕验物-存档报告-\(safeBase)"
        if let date { name += "-" + fileTimestamp(date) }
        return name + "." + format.fileExtension
    }

    private static func sanitized(_ value: String) -> String {
        let replaced = String(value.map { "/\\:".contains($0) ? "-" : $0 })
            .trimmingCharacters(in: .whitespaces)
        return replaced.isEmpty ? "存档" : replaced
    }

    private static func value(_ values: [Int], _ index: Int) -> Int {
        guard values.indices.contains(index) else { return -1 }
        let raw = values[index]
        return (raw <= 0 || raw == 0xFFFF_FFFF) ? -1 : raw
    }

    private static func formatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = format
        return formatter
    }

    private static func timestamp(_ date: Date) -> String {
        formatter("yyyy-MM-dd HH:mm:ss").string(from: date)
    }

    private static func fileTimestamp(_ date: Date) -> String {
        formatter("yyyyMMdd-HHmmss").string(from: date)
    }
}
