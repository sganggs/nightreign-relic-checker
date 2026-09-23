package com.nightreign.relicchecker.gamedata.save

import java.time.LocalDateTime
import java.time.format.DateTimeFormatter

/** 存档报告的导出格式。 */
enum class SaveReportFormat(val title: String, val fileExtension: String, val mimeType: String) {
    /** 人读的文本报告：按角色列出每件非法遗物的种类、词条与问题。 */
    TEXT("文本报告（.txt）", "txt", "text/plain"),

    /** 表格：每行一件遗物，便于在表格软件里排序筛选。 */
    CSV("表格（.csv）", "csv", "text/csv"),
}

/** 报告抬头里「词条库」一行所需的信息（只写进报告，审计本身不读）。 */
data class SaveReportCatalogInfo(
    /** 数据来源文案（「内置数据」/「自定义数据」）。 */
    val origin: String,
    val gameVersion: String,
    val dataVersion: String,
) {
    /** 「内置数据 · v1.03.4（数据 2026-01-01）」。 */
    val line: String
        get() {
            var text = origin.ifEmpty { "内置数据" } + " · " + gameVersion.ifEmpty { "未知版本" }
            if (dataVersion.isNotEmpty()) text += "（数据 $dataVersion）"
            return text
        }
}

/**
 * 把一份已审计的存档渲染成可导出的报告（纯字符串生成，无 I/O）。
 *
 * 逐行移植 macOS 端 RelicCore/SaveReport.swift（与 Windows 端 renderer/savereport.js 逐行一致）：
 * 抬头固定；「警告」恒为 0 时不写；审计文案（title / detail）原样输出，报告层不做任何改写；
 * 换行统一 CRLF。
 */
object SaveReportBuilder {
    const val RULE_WIDTH = 46
    val HEAVY_RULE: String = "=".repeat(RULE_WIDTH)
    val LIGHT_RULE: String = "-".repeat(RULE_WIDTH)

    /** CSV 表头（与 [csv] 的列顺序一致）。 */
    val CSV_HEADER: List<String> = listOf(
        "角色", "槽位", "遗物名", "遗物ID", "种类", "颜色", "状态",
        "词条1", "词条2", "词条3", "诅咒1", "诅咒2", "诅咒3", "问题摘要",
    )

    /** 解析失败的槽位在「状态」列里的标记。 */
    const val CSV_PARSE_ERROR_STATUS = "槽位解析失败"

    /** 抬头里的说明行：存档判定与顶部「校验口径」无关。 */
    const val DISCLAIMER =
        "说明：存档判定只依据内置的词条库与遗物表，不受顶部「校验口径」影响" +
            "（口径只作用于词条组合检查页）；本报告由离线社区工具生成，不构成官方判定。"

    private const val CRLF = "\r\n"
    private val TIMESTAMP = DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss")
    private val FILE_TIMESTAMP = DateTimeFormatter.ofPattern("yyyyMMdd-HHmmss")
    private val PLAIN_NUMBER = Regex("^-?[0-9]+(\\.[0-9]+)?$")

    fun content(
        save: AuditedSave,
        format: SaveReportFormat,
        generatedAt: LocalDateTime? = null,
        catalog: SaveReportCatalogInfo? = null,
    ): String = when (format) {
        SaveReportFormat.TEXT -> text(save, generatedAt, catalog)
        SaveReportFormat.CSV -> csv(save)
    }

    // ---- 文本报告 ----

    fun text(save: AuditedSave, generatedAt: LocalDateTime? = null, catalog: SaveReportCatalogInfo? = null): String {
        val lines = ArrayList<String>()
        lines += "夜幕验物 · 存档检查报告"
        lines += HEAVY_RULE
        lines += "存档文件：" + save.fileName.ifEmpty { "未知" }
        if (generatedAt != null) lines += "生成时间：" + TIMESTAMP.format(generatedAt)
        lines += "存档校验和：" + if (save.checksumOk) "通过" else "异常（结果仅供参考）"
        lines += "角色 ${save.characters.size} 个 · " + countsText(save.relicCount, save.invalidCount, save.warningCount)
        if (catalog != null) lines += "词条库：" + catalog.line
        lines += DISCLAIMER
        lines += ""

        if (save.characters.isEmpty()) lines += "未在该存档中找到已占用的角色槽位。"

        for (character in save.characters) {
            lines += LIGHT_RULE
            lines += character.displayName
            if (character.hasParseError) {
                lines += "  该槽位解析失败：${character.parseError}"
                lines += ""
                continue
            }
            val flagged = character.relics.filter { it.statusLabel != "合法" }
            lines += "  " + countsText(character.relics.size, character.invalidCount, character.warningCount)
            if (flagged.isEmpty()) {
                lines += if (character.relics.isEmpty()) "  该角色没有持有任何遗物。" else "  未发现不合法遗物。"
            }
            for (relic in flagged) {
                lines += ""
                lines += relicLines(relic, save)
            }
            lines += ""
        }
        return lines.joinToString(CRLF) + CRLF
    }

    /** 「遗物 N 件 · 非法 M 件[ · 警告 K 件]」：警告为 0 时不写。 */
    private fun countsText(total: Int, invalid: Int, warning: Int): String {
        var text = "遗物 $total 件 · 非法 $invalid 件"
        if (warning > 0) text += " · 警告 $warning 件"
        return text
    }

    private fun relicLines(relic: AuditedRelic, save: AuditedSave): List<String> {
        val lines = ArrayList<String>()
        lines += "  [${relic.statusLabel}] ${relic.displayName}（ID ${relic.relic.itemId}）"
        // kindLabel 对深夜遗物本身就是「深夜遗物」，不再重复追加
        lines += "    种类：${relic.kindLabel} · ${relic.colorText} · 存档内第 ${relic.relic.index + 1} 件"
        for (row in 0 until 3) {
            val effect = value(relic.relic.effects, row)
            val curse = value(relic.relic.curses, row)
            if (effect == -1L && curse == -1L) continue
            var line = "    词条${row + 1}：" + save.affixLabel(effect)
            if (curse != -1L) line += "｜诅咒：" + save.affixLabel(curse)
            lines += line
        }
        relic.result.issues.forEach { lines += "    ✗ ${it.title}：${it.detail}" }
        relic.result.warnings.forEach { lines += "    ! ${it.title}：${it.detail}" }
        relic.result.officialEffects?.let { official ->
            val text = official.filter { normalizeEffectId(it) != -1L }.joinToString("、") { save.affixLabel(it) }
            if (text.isNotEmpty()) lines += "    官方固定词条（可据此改回）：$text"
        }
        relic.result.orderedEffects?.let { ordered ->
            lines += "    正确的词条顺序：" + ordered.joinToString("、") { save.affixLabel(it) }
        }
        return lines
    }

    // ---- CSV ----

    fun csv(save: AuditedSave): String {
        val rows = ArrayList<String>()
        rows += csvRow(CSV_HEADER)
        for (character in save.characters) {
            val slot = (character.slot + 1).toString()
            val name = character.name.ifEmpty { "未命名" }
            // 槽位解密失败时 relics 为空，不补一行的话拿 CSV 统计的人会整段漏掉这个角色
            if (character.hasParseError) {
                rows += csvRow(
                    listOf(name, slot, "", "", "", "", CSV_PARSE_ERROR_STATUS) + List(6) { "" } + character.parseError.orEmpty(),
                )
            }
            for (relic in character.relics) {
                rows += csvRow(
                    listOf(
                        name,
                        slot,
                        relic.displayName,
                        relic.relic.itemId.toString(),
                        relic.kindLabel,
                        relic.colorText,
                        relic.statusLabel,
                    ) + (0 until 3).map { affixCell(value(relic.relic.effects, it), save) } +
                        (0 until 3).map { affixCell(value(relic.relic.curses, it), save) } +
                        issueSummary(relic),
                )
            }
        }
        // RFC 4180 的 CRLF，表格软件（含 Excel）识别最稳
        return rows.joinToString(CRLF) + CRLF
    }

    /** 单件遗物的问题摘要：「标题：说明」用「；」串起来，警告加「警告：」前缀。 */
    fun issueSummary(relic: AuditedRelic): String =
        (relic.result.issues.map { "${it.title}：${it.detail}" } +
            relic.result.warnings.map { "警告：${it.title}：${it.detail}" }).joinToString("；")

    private fun affixCell(effectId: Long, save: AuditedSave): String =
        if (effectId == -1L) "" else save.affixLabel(effectId)

    private fun csvRow(fields: List<String>): String = fields.joinToString(",") { csvField(it) }

    /**
     * CSV 字段转义：含分隔符 / 引号 / 换行时加引号并把引号翻倍；以 `= + - @` 开头的字段
     * （角色名是玩家可控内容）前面补一个撇号，避免被表格软件当成公式执行。纯数字（含负数）不加撇号。
     */
    fun csvField(value: String): String {
        var text = value
        val first = text.firstOrNull()
        if (first != null && first in "=+-@\t\r" && !PLAIN_NUMBER.matches(text)) text = "'$text"
        if (text.none { it in ",\"\n\r" }) return text
        return "\"" + text.replace("\"", "\"\"") + "\""
    }

    // ---- 文件名与落盘字节 ----

    /** 建议的导出文件名：`夜幕验物-存档报告-NR0000-20260922-120000.txt`。 */
    fun suggestedFileName(saveFileName: String, format: SaveReportFormat, date: LocalDateTime? = null): String {
        var base = saveFileName
        val cut = base.lastIndexOfAny(charArrayOf('/', '\\'))
        if (cut >= 0) base = base.substring(cut + 1)
        val dot = base.lastIndexOf('.')
        if (dot >= 0) base = base.substring(0, dot)
        val safe = base.trim().map { if (it in "/\\:") '-' else it }.joinToString("").trim()
        var name = "夜幕验物-存档报告-" + safe.ifEmpty { "存档" }
        if (date != null) name += "-" + FILE_TIMESTAMP.format(date)
        return name + "." + format.fileExtension
    }

    fun suggestedFileName(save: AuditedSave, format: SaveReportFormat, date: LocalDateTime? = null): String =
        suggestedFileName(save.fileName, format, date)

    /**
     * 写盘用的字节：换行统一 CRLF（报告本身已是 CRLF，这里兜底），CSV 额外加 UTF-8 BOM
     * （表格软件才会按 UTF-8 打开中文）。与 Windows 端 savefile.TextFileBytes 一致。
     */
    fun fileBytes(format: SaveReportFormat, content: String): ByteArray {
        val body = normalizeCrlf(content).toByteArray(Charsets.UTF_8)
        return if (format == SaveReportFormat.CSV) UTF8_BOM + body else body
    }

    /** 把混杂的换行统一成 CRLF。 */
    fun normalizeCrlf(content: String): String =
        content.replace("\r\n", "\n").replace("\r", "\n").replace("\n", CRLF)

    private val UTF8_BOM = byteArrayOf(0xEF.toByte(), 0xBB.toByte(), 0xBF.toByte())

    private fun value(values: List<Long>, index: Int): Long = normalizeEffectId(values.getOrElse(index) { -1L })
}
