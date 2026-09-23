package com.nightreign.relicchecker.gamedata.save

import java.time.LocalDateTime
import kotlin.test.Test
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertTrue

/**
 * 存档报告：macOS SaveCompareChecks.swift 的 checkSaveReport（真实数据审计）与
 * Windows tests/save_report.test.mjs（固定名称表）的关键断言。
 */
class SaveReportTest {
    private val heavy = "=".repeat(46)
    private val light = "-".repeat(46)
    private val catalogInfo = SaveReportCatalogInfo("内置数据", SaveTestData.catalog.gameVersion, SaveTestData.catalog.dataVersion)

    // ---- macOS checkSaveReport ----

    @Test
    fun `text header lines follow the fixed order`() {
        val save = SaveAuditFixtures.base
        val text = SaveReportBuilder.text(save, LocalDateTime.of(1970, 1, 1, 0, 0, 0), catalogInfo)
        assertFalse(text.replace("\r\n", "").contains("\n"), "文本报告的换行应全部是 CRLF")
        val lines = text.split("\r\n")
        assertEquals("夜幕验物 · 存档检查报告", lines[0])
        assertEquals(heavy, lines[1])
        assertEquals("存档文件：NR0000.sl2", lines[2])
        assertEquals("生成时间：1970-01-01 00:00:00", lines[3])
        assertEquals("存档校验和：通过", lines[4])
        assertEquals("角色 2 个 · 遗物 4 件 · 非法 1 件", lines[5])
        assertEquals("词条库：内置数据 · ${SaveTestData.catalog.gameVersion}（数据 ${SaveTestData.catalog.dataVersion}）", lines[6])
        assertEquals(SaveReportBuilder.DISCLAIMER, lines[7])
        assertTrue(SaveReportBuilder.DISCLAIMER.contains("不受顶部「校验口径」影响"))
        assertFalse(text.contains("校验口径：") || text.contains("当前口径"))
        assertFalse(SaveReportBuilder.text(save).contains("词条库："), "不传词条库信息时不写这一行")
        assertFalse(SaveReportBuilder.text(save).contains("生成时间："), "不传时间时不写生成时间")
    }

    @Test
    fun `text report lists only flagged relics per character`() {
        val save = SaveAuditFixtures.base
        val text = SaveReportBuilder.text(save, LocalDateTime.of(2026, 9, 22, 20, 33, 44), catalogInfo)
        assertTrue(text.contains("\r\n$light\r\n槽位 1 · 夜巫\r\n"), "按角色分段")
        assertTrue(text.contains("  遗物 3 件 · 非法 1 件"))
        assertTrue(text.contains("  [非法] 未知遗物 #424242（ID 424242）"))
        assertTrue(text.contains("    种类：遗物 · 颜色未知 · 存档内第 3 件"))
        assertTrue(text.contains("    ✗ 未知遗物 ID："))
        assertFalse(text.contains("辽阔的火燃情景"), "文本报告只列非法/警告遗物")
        assertTrue(text.contains("  未发现不合法遗物。"), "全部合法的角色要显式说明")
        assertFalse(text.contains("警告 0 件"))
        assertEquals(0, save.warningCount)
    }

    @Test
    fun `csv rows columns and escaping on real audit`() {
        val csv = SaveReportBuilder.csv(SaveAuditFixtures.base)
        val lines = csv.split("\r\n").filter { it.isNotEmpty() }
        assertEquals(5, lines.size, "1 行表头 + 4 行遗物")
        assertEquals("角色,槽位,遗物名,遗物ID,种类,颜色,状态,词条1,词条2,词条3,诅咒1,诅咒2,诅咒3,问题摘要", lines[0])
        assertEquals(SaveReportBuilder.CSV_HEADER.joinToString(","), lines[0])
        assertTrue(lines[1].startsWith("夜巫,1,辽阔的火燃情景,202,商店遗物,红色,合法,"), lines[1])
        assertTrue(lines[1].contains("（6630000）"))
        assertTrue(lines[1].endsWith(",,,,"), "无诅咒且无问题：诅咒列与问题摘要列为空")
        assertTrue(lines[3].contains(",非法,") && lines[3].contains("未知遗物 ID："), lines[3])
        assertTrue(csv.endsWith("\r\n"))

        val deepCsv = SaveReportBuilder.csv(SaveAuditFixtures.other)
        assertTrue(deepCsv.contains("受到损伤时，会累积中毒量表（6820000）"), "诅咒列写出负面词条")
        assertTrue(deepCsv.contains(",深夜遗物,"))
    }

    @Test
    fun `csv field escaping and formula guard`() {
        assertEquals("普通", SaveReportBuilder.csvField("普通"))
        assertEquals("\"a,b\"", SaveReportBuilder.csvField("a,b"))
        assertEquals("\"a\"\"b\"", SaveReportBuilder.csvField("a\"b"))
        assertEquals("'=1+1", SaveReportBuilder.csvField("=1+1"))
        assertEquals("-12", SaveReportBuilder.csvField("-12"))
        assertEquals("-12.5", SaveReportBuilder.csvField("-12.5"))
        assertEquals("'-a", SaveReportBuilder.csvField("-a"))
        assertEquals("'@x", SaveReportBuilder.csvField("@x"))
        assertEquals("\"line\nbreak\"", SaveReportBuilder.csvField("line\nbreak"))
    }

    @Test
    fun `suggested file names`() {
        val date = LocalDateTime.of(2026, 9, 22, 20, 33, 44)
        assertEquals("夜幕验物-存档报告-NR0000-20260922-203344.txt", SaveReportBuilder.suggestedFileName("NR0000.sl2", SaveReportFormat.TEXT, date))
        assertEquals("夜幕验物-存档报告-NR0000-20260922-203344.csv", SaveReportBuilder.suggestedFileName("NR0000.sl2", SaveReportFormat.CSV, date))
        assertEquals("夜幕验物-存档报告-NR0001-20260922-203344.txt", SaveReportBuilder.suggestedFileName("C:\\save\\NR0001.co2", SaveReportFormat.TEXT, date))
        assertEquals("夜幕验物-存档报告-存档-20260922-203344.txt", SaveReportBuilder.suggestedFileName("", SaveReportFormat.TEXT, date))
        assertEquals("夜幕验物-存档报告-NR0000.txt", SaveReportBuilder.suggestedFileName("NR0000.sl2", SaveReportFormat.TEXT, null))
        assertEquals("夜幕验物-存档报告-a-b.csv", SaveReportBuilder.suggestedFileName("a:b.sl2", SaveReportFormat.CSV))
        val save = SaveAuditFixtures.base
        assertTrue(SaveReportBuilder.suggestedFileName(save, SaveReportFormat.CSV, date).startsWith("夜幕验物-存档报告-NR0000-"))
        assertEquals(SaveReportBuilder.csv(save), SaveReportBuilder.content(save, SaveReportFormat.CSV))
        assertEquals(SaveReportBuilder.text(save), SaveReportBuilder.content(save, SaveReportFormat.TEXT))
    }

    @Test
    fun `deep relic kind line names deep only once`() {
        val deepSave = SaveAuditFixtures.deepFlagged
        assertTrue(deepSave.characters[0].relics[0].isDeep && deepSave.invalidCount == 1)
        val kindLine = assertNotNull(SaveReportBuilder.text(deepSave).split("\r\n").firstOrNull { it.contains("种类：") })
        assertEquals(2, kindLine.split("深夜遗物").size, kindLine)
    }

    @Test
    fun `parse failures leave a trace in text and csv`() {
        val damagedLines = SaveReportBuilder.csv(SaveAuditFixtures.damaged).split("\r\n").filter { it.isNotEmpty() }
        assertEquals(5, damagedLines.size, "表头 + 3 行遗物 + 1 行解析失败占位")
        val row = assertNotNull(damagedLines.firstOrNull { it.contains(SaveReportBuilder.CSV_PARSE_ERROR_STATUS) })
        assertTrue(row.startsWith("槽位 2,2,,,,,槽位解析失败,"), row)
        assertTrue(row.contains("该槽位解密失败"))
        val text = SaveReportBuilder.text(SaveAuditFixtures.damaged)
        assertTrue(text.contains("  该槽位解析失败：该槽位解密失败"))
        assertFalse(text.contains("槽位 2 · 槽位 2\r\n  遗物 0 件"))
    }

    @Test
    fun `pipeline explanations and labels`() {
        val save = SaveAuditFixtures.base
        assertEquals("+1点生命力（固定+20点生命值上限）", save.affixExplanation(7_000_000))
        assertEquals(null, save.affixExplanation(424_242))
        assertEquals("（空）", save.affixLabel(-1))
        assertEquals("（空）", save.affixLabel(0))
        assertEquals("（空）", save.affixLabel(-2))
        assertEquals("（空）", save.affixLabel(0xFFFFFFFFL))
        assertEquals("生命力＋１（7000000）", save.affixLabel(7_000_000))
        assertEquals("未知词条 #424242", save.affixName(424_242))
        assertEquals("槽位 1 · 夜巫", save.characters[0].displayName)
        assertEquals("红色", save.characters[0].relics[0].colorText)
        assertEquals("颜色未知", save.characters[0].relics[2].colorText)
        val viaCatalog = SaveAuditPipeline.audit(SaveAuditFixtures.baseParsed, SaveTestData.catalog, SaveTestData.relicData)
        assertEquals(save.relicCount, viaCatalog.relicCount)
        assertEquals(save.invalidCount, viaCatalog.invalidCount)
        assertEquals(save.affixExplanation(7_000_000), viaCatalog.affixExplanation(7_000_000))
    }

    @Test
    fun `official affixes come before the canonical order`() {
        val save = AuditedSave(
            fileName = "顺序.sl2",
            checksumOk = true,
            affixNames = mapOf(7_000_000L to "生命力＋１", 6_630_000L to "提升最大装备重量＋１"),
            characters = listOf(
                AuditedCharacter(
                    0, "夜巡者", null,
                    listOf(
                        AuditedRelic(
                            SaveRelic(0, 1000, listOf(7_000_000, 6_630_000, -1), listOf(-1, -1, -1)),
                            null,
                            RelicAuditResult(
                                RelicAuditStatus.INVALID,
                                issues = listOf(RelicAuditIssue(RelicIssueKind.EFFECT_UNEXPECTED, "词条不在槽位池", "合成用例", listOf(6_630_000))),
                                orderedEffects = listOf(6_630_000, 7_000_000, -1),
                                officialEffects = listOf(7_000_000, -1, -1),
                            ),
                        ),
                    ),
                ),
            ),
        )
        val lines = SaveReportBuilder.text(save).split("\r\n")
        val official = lines.indexOfFirst { it.contains("官方固定词条（可据此改回）") }
        val ordered = lines.indexOfFirst { it.contains("正确的词条顺序") }
        assertTrue(official >= 0 && ordered >= 0 && official < ordered, "$official / $ordered")
        assertEquals("    官方固定词条（可据此改回）：生命力＋１（7000000）", lines[official])
        assertEquals("    正确的词条顺序：提升最大装备重量＋１（6630000）、生命力＋１（7000000）、（空）", lines[ordered])
    }

    // ---- Windows save_report.test.mjs（固定名称表，不依赖真实数据的审计结论） ----

    private val names = mapOf(7_000_000L to "生命力＋１", 6_820_000L to "受到损伤时，会累积中毒量表")
    private val shop202 = RelicInfo(202, "辽阔的火燃情景", 0, false, listOf(310, 210, 110), listOf(-1, -1, -1))
    private val valid = RelicAuditResult(RelicAuditStatus.VALID)

    private fun invalid(vararg issues: RelicAuditIssue) = RelicAuditResult(RelicAuditStatus.INVALID, issues.toList())

    private fun issue(title: String, detail: String) = RelicAuditIssue(RelicIssueKind.UNKNOWN_ITEM, title, detail, emptyList())

    private fun relic(index: Int, itemId: Int, effects: List<Long> = emptyList(), curses: List<Long> = emptyList()) =
        SaveRelic(index, itemId, List(3) { effects.getOrElse(it) { -1 } }, List(3) { curses.getOrElse(it) { -1 } })

    private fun audited(relic: SaveRelic, result: RelicAuditResult) =
        AuditedRelic(relic, if (relic.itemId == 202) shop202 else null, result)

    private fun windowsSave(
        characters: List<AuditedCharacter>? = null,
        checksumOk: Boolean = true,
        fileName: String = "NR0000.sl2",
    ) = AuditedSave(
        fileName = fileName,
        checksumOk = checksumOk,
        affixNames = names,
        characters = characters ?: listOf(
            AuditedCharacter(
                0, "夜巫", null,
                listOf(
                    audited(relic(0, 202, listOf(7_000_000)), valid),
                    audited(relic(1, 202, listOf(7_000_000)), valid),
                    audited(relic(2, 424_242, curses = listOf(6_820_000)), invalid(issue("未知遗物 ID", "遗物 ID 424242 不在内置遗物表中"))),
                ),
            ),
            AuditedCharacter(1, "追踪者", null, listOf(audited(relic(0, 202, listOf(7_000_000)), valid))),
        ),
    )

    private val windowsCatalog = SaveReportCatalogInfo("内置数据", "v1.03.4", "Param 0d2ad1")
    private val windowsDate = LocalDateTime.of(2026, 9, 22, 20, 33, 44)

    @Test
    fun `windows text header seven lines`() {
        val lines = SaveReportBuilder.text(windowsSave(), windowsDate, windowsCatalog).split("\r\n")
        assertEquals(
            listOf(
                "夜幕验物 · 存档检查报告",
                heavy,
                "存档文件：NR0000.sl2",
                "生成时间：2026-09-22 20:33:44",
                "存档校验和：通过",
                "角色 2 个 · 遗物 4 件 · 非法 1 件",
                "词条库：内置数据 · v1.03.4（数据 Param 0d2ad1）",
                SaveReportBuilder.DISCLAIMER,
                "",
            ),
            lines.take(9),
        )
        val broken = SaveReportBuilder.text(windowsSave(checksumOk = false)).split("\r\n")
        assertEquals("存档校验和：异常（结果仅供参考）", broken[3])
        assertTrue(broken.none { it.startsWith("生成时间：") || it.startsWith("词条库：") })
    }

    @Test
    fun `windows text sections and relic entries`() {
        val text = SaveReportBuilder.text(windowsSave(), windowsDate, windowsCatalog)
        assertTrue(text.contains("\r\n$light\r\n槽位 1 · 夜巫\r\n"))
        assertTrue(text.contains("  遗物 3 件 · 非法 1 件"))
        assertTrue(text.contains("  [非法] 未知遗物 #424242（ID 424242）"))
        assertTrue(text.contains("    种类：遗物 · 颜色未知 · 存档内第 3 件"))
        assertTrue(text.contains("    词条1：（空）｜诅咒：受到损伤时，会累积中毒量表（6820000）"))
        assertTrue(text.contains("    ✗ 未知遗物 ID：遗物 ID 424242 不在内置遗物表中"))
        assertFalse(text.contains("辽阔的火燃情景"))
        assertTrue(text.contains("  未发现不合法遗物。"))
    }

    @Test
    fun `windows warnings only appear when present`() {
        val warned = valid.copy(warnings = listOf(RelicAuditIssue(RelicIssueKind.WRONG_ORDER, "留意", "说明", emptyList())))
        val save = windowsSave(
            listOf(
                AuditedCharacter(
                    0, "夜巫", null,
                    listOf(
                        audited(relic(0, 202, listOf(7_000_000)), warned),
                        audited(relic(1, 202, listOf(7_000_000)), valid),
                        audited(relic(2, 424_242, curses = listOf(6_820_000)), invalid(issue("未知遗物 ID", "x"))),
                    ),
                ),
                AuditedCharacter(1, "追踪者", null, listOf(audited(relic(0, 202, listOf(7_000_000)), valid))),
            ),
        )
        val lines = SaveReportBuilder.text(save).split("\r\n")
        assertEquals("角色 2 个 · 遗物 4 件 · 非法 1 件 · 警告 1 件", lines[4])
        assertTrue(lines.contains("    ! 留意：说明"))
        assertEquals("警告", save.characters[0].relics[0].statusLabel)
        assertEquals("警告：留意：说明", SaveReportBuilder.issueSummary(save.characters[0].relics[0]))
    }

    @Test
    fun `windows empty save damaged slot and empty character`() {
        val empty = SaveReportBuilder.text(windowsSave(emptyList(), fileName = "空.sl2"))
        assertTrue(empty.contains("未在该存档中找到已占用的角色槽位。"))

        val damaged = SaveReportBuilder.text(
            windowsSave(listOf(AuditedCharacter(1, "槽位 2", "该槽位解密失败：条目密文长度不是 16 的倍数", emptyList()))),
        )
        assertTrue(damaged.contains("  该槽位解析失败：该槽位解密失败：条目密文长度不是 16 的倍数"))
        assertFalse(damaged.contains("\r\n  遗物 0 件"))
        assertFalse(damaged.contains("该角色没有持有任何遗物"))

        val nothing = SaveReportBuilder.text(windowsSave(listOf(AuditedCharacter(0, "甲", null, emptyList()))))
        assertTrue(nothing.contains("  该角色没有持有任何遗物。"))
    }

    @Test
    fun `windows csv layout parse error row and formula injection`() {
        val rows = SaveReportBuilder.csv(windowsSave()).split("\r\n").filter { it.isNotEmpty() }
        assertEquals(5, rows.size)
        assertTrue(rows[1].startsWith("夜巫,1,辽阔的火燃情景,202,商店遗物,红色,合法,生命力＋１（7000000）,,,"), rows[1])
        assertTrue(rows[3].contains(",非法,"))
        assertTrue(rows[3].endsWith(",未知遗物 ID：遗物 ID 424242 不在内置遗物表中"), rows[3])
        assertTrue(rows[4].startsWith("追踪者,2,"))

        val multi = invalid(issue("甲", "说明甲"), issue("乙", "说明乙"))
            .copy(warnings = listOf(RelicAuditIssue(RelicIssueKind.WRONG_ORDER, "丙", "说明丙", emptyList())))
        assertEquals("甲：说明甲；乙：说明乙；警告：丙：说明丙", SaveReportBuilder.issueSummary(audited(relic(0, 1), multi)))

        val damagedRows = SaveReportBuilder.csv(
            windowsSave(
                listOf(
                    AuditedCharacter(1, "槽位 2", "该槽位解密失败", emptyList()),
                    AuditedCharacter(2, "丙", null, listOf(audited(relic(0, 202, listOf(7_000_000)), valid))),
                ),
            ),
        ).split("\r\n").filter { it.isNotEmpty() }
        assertEquals(3, damagedRows.size)
        assertEquals("槽位 2,2,,,,,槽位解析失败,,,,,,,该槽位解密失败", damagedRows[1])
        assertTrue(damagedRows[2].startsWith("丙,3,"))

        val injected = SaveReportBuilder.csv(
            windowsSave(listOf(AuditedCharacter(0, "=HYPERLINK(\"http://x\")", null, listOf(audited(relic(0, 202, listOf(7_000_000)), valid))))),
        ).split("\r\n")
        assertTrue(injected[1].startsWith("\"'=HYPERLINK(\"\"http://x\"\")\",1,"), injected[1])

        val csv = SaveReportBuilder.csv(windowsSave())
        assertTrue(csv.endsWith("\r\n"))
        assertFalse(Regex("[^\r]\n").containsMatchIn(csv), "不应出现裸 LF")
    }

    @Test
    fun `negative and zero affix ids are empty in report and csv`() {
        val junk = SaveRelic(0, 202, listOf(7_000_000, -2, 0), listOf(-1, -1, -1))
        val save = windowsSave(listOf(AuditedCharacter(0, "夜巡者", null, listOf(audited(junk, invalid(issue("问题", "说明")))))))
        val text = SaveReportBuilder.text(save)
        assertFalse(text.contains("-2"))
        assertTrue(text.contains("词条1：生命力＋１（7000000）"))
        val cells = SaveReportBuilder.csv(save).split("\r\n")[1].split(",")
        assertEquals("", cells[8])
        assertEquals("", cells[9])
    }

    @Test
    fun `status labels three states`() {
        assertEquals("非法", audited(relic(0, 1), RelicAuditResult(RelicAuditStatus.INVALID)).statusLabel)
        assertEquals("警告", audited(relic(0, 1), valid.copy(warnings = listOf(issue("x", "y")))).statusLabel)
        assertEquals("合法", audited(relic(0, 1), valid).statusLabel)
    }

    @Test
    fun `file bytes add a bom only for csv and normalize line endings`() {
        val bom = byteArrayOf(0xEF.toByte(), 0xBB.toByte(), 0xBF.toByte())
        val csv = SaveReportBuilder.fileBytes(SaveReportFormat.CSV, "a,b\nc\r\n")
        assertContentEquals(bom + "a,b\r\nc\r\n".toByteArray(), csv)
        val text = SaveReportBuilder.fileBytes(SaveReportFormat.TEXT, "甲\r乙\n")
        assertContentEquals("甲\r\n乙\r\n".toByteArray(Charsets.UTF_8), text)
        assertEquals("text/csv", SaveReportFormat.CSV.mimeType)
        assertEquals("text/plain", SaveReportFormat.TEXT.mimeType)
    }
}
