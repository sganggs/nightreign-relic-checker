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

/// 把一份已审计的存档渲染成可导出的报告（纯字符串生成，无任何 I/O）。
public enum SaveReportBuilder {
    /// CSV 表头（与 `csv(for:)` 的列顺序一致）。
    public static let csvHeader = [
        "角色", "遗物名", "遗物ID", "种类", "颜色", "状态",
        "词条1", "词条2", "词条3", "诅咒1", "诅咒2", "诅咒3", "问题摘要"
    ]

    /// 报告末尾的口径说明（两种格式共用）。
    public static let disclaimer =
        "本报告由夜幕验物离线生成：判定只依据内置的词条库与遗物表，"
        + "数据版本与游戏版本不一致时结论可能有偏差，请以游戏内实际表现为准。"
        + "当前版本的存档审计只给出「非法」判定，没有单独的「警告」等级。"

    public static func content(for save: AuditedSave, format: SaveReportFormat, generatedAt: Date? = nil) -> String {
        switch format {
        case .text: return text(for: save, generatedAt: generatedAt)
        case .csv: return csv(for: save)
        }
    }

    // MARK: - 文本报告

    public static func text(for save: AuditedSave, generatedAt: Date? = nil) -> String {
        var lines: [String] = []
        lines.append("夜幕验物 · 存档检查报告")
        lines.append(String(repeating: "=", count: 46))
        lines.append("存档文件：\(save.fileName)")
        if let generatedAt {
            lines.append("生成时间：\(timestamp(generatedAt))")
        }
        lines.append("存档校验和：" + (save.checksumOk ? "正常" : "异常（结果仅供参考）"))
        lines.append("角色 \(save.characters.count) 个 · 遗物 \(save.relicCount) 件 · 非法 \(save.invalidCount) 件")
        lines.append("")

        if save.characters.isEmpty {
            lines.append("未在该存档中找到已占用的角色槽位。")
        }

        for character in save.characters {
            lines.append(String(repeating: "-", count: 46))
            lines.append("角色：\(character.displayName)")
            if let parseError = character.parseError {
                lines.append("  该槽位解析异常：\(parseError)")
            }
            // 「警告」等级当前不会被 RelicAuditor 产出，恒为 0 的字段不往报告里写，
            // 免得读者误以为「已检查过、没有告警」。
            var summary = "  遗物 \(character.relics.count) 件 · 非法 \(character.invalidCount) 件"
            if character.warningCount > 0 { summary += " · 警告 \(character.warningCount) 件" }
            lines.append(summary)

            let flagged = character.relics.filter {
                $0.result.status == .invalid || !$0.result.warnings.isEmpty
            }
            if flagged.isEmpty {
                lines.append(character.relics.isEmpty ? "  该角色没有持有任何遗物。" : "  未发现不合法遗物。")
            }
            for relic in flagged {
                lines.append("")
                lines.append(contentsOf: relicLines(relic, save: save))
            }
            lines.append("")
        }

        lines.append(String(repeating: "-", count: 46))
        lines.append(disclaimer)
        return lines.joined(separator: "\n") + "\n"
    }

    private static func relicLines(_ relic: AuditedSave.AuditedRelic, save: AuditedSave) -> [String] {
        var lines: [String] = []
        lines.append("  [\(relic.statusLabel)] \(relic.displayName)（ID \(relic.relic.itemID)）")

        // kindLabel 在 info.deep 时本身就是「深夜遗物」，不再重复追加标签。
        var tags = [relic.kindLabel]
        if let color = relic.colorLabel { tags.append("颜色：\(color)") }
        lines.append("    种类：" + tags.joined(separator: " · "))

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
            lines.append("    正确的保存顺序：\(text)")
        }
        return lines
    }

    // MARK: - CSV

    /// 解析失败的槽位在「状态」列里的标记（CSV 里没有遗物行，用它留痕）。
    public static let csvParseErrorStatus = "槽位解析失败"

    public static func csv(for save: AuditedSave) -> String {
        var rows: [String] = [csvHeader.map(csvField).joined(separator: ",")]
        for character in save.characters {
            // 槽位解密失败时 relics 为空，若不补一行，拿 CSV 做统计的人会整段漏掉这个角色。
            if let parseError = character.parseError {
                var fields = [character.displayName, "", "", "", "", csvParseErrorStatus]
                fields += Array(repeating: "", count: 6)
                fields.append(parseError)
                rows.append(fields.map(csvField).joined(separator: ","))
            }
            for relic in character.relics {
                var fields = [
                    character.displayName,
                    relic.displayName,
                    String(relic.relic.itemID),
                    relic.kindLabel,
                    relic.colorLabel ?? "",
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

    /// 单件遗物的问题摘要：问题标题用「；」串起来，警告加「警告：」前缀。
    public static func issueSummary(_ relic: AuditedSave.AuditedRelic) -> String {
        let issues = relic.result.issues.map(\.title)
        let warnings = relic.result.warnings.map { "警告：" + $0.title }
        return (issues + warnings).joined(separator: "；")
    }

    private static func affixCell(_ effectID: Int, save: AuditedSave) -> String {
        effectID == -1 ? "" : save.affixLabel(effectID)
    }

    /// CSV 字段转义：含分隔符/引号/换行时加引号并把引号翻倍；
    /// 以 `= + - @` 开头的字段（角色名是玩家可控内容）前面补一个撇号，
    /// 避免被表格软件当成公式执行。
    public static func csvField(_ value: String) -> String {
        var text = value
        if let first = text.first, "=+-@\t\r".contains(first) {
            text = "'" + text
        }
        guard text.contains(where: { ",\"\n\r".contains($0) }) else { return text }
        return "\"" + text.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    // MARK: - 文件名

    /// 建议的导出文件名：`夜幕验物-存档报告-NR0000-20260922-120000.txt`。
    public static func suggestedFileName(
        for save: AuditedSave,
        format: SaveReportFormat,
        date: Date? = nil
    ) -> String {
        let base = (save.fileName as NSString).deletingPathExtension
        let safeBase = base.isEmpty ? "存档" : sanitized(base)
        var name = "夜幕验物-存档报告-\(safeBase)"
        if let date { name += "-" + fileTimestamp(date) }
        return name + "." + format.fileExtension
    }

    private static func sanitized(_ value: String) -> String {
        String(value.map { "/\\:".contains($0) ? "-" : $0 })
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
