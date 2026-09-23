package com.nightreign.relicchecker.gamedata.save

/**
 * 用真实词条库 / 遗物表审计出的几份存档（不读真实存档文件，直接合成解析结果）。
 * 逐个移植 macOS 端 RelicCoreChecks/SaveCompareChecks.swift 的 SaveFixtures。
 */
internal object SaveAuditFixtures {
    private val shop = listOf(6_630_000L, 7_000_000L, 7_000_100L)
    private val none = listOf(-1L, -1L, -1L)

    private fun relic(index: Int, itemId: Int, effects: List<Long>, curses: List<Long> = none) =
        SaveRelic(index, itemId, effects, curses)

    private fun audit(parsed: SaveParseResult): AuditedSave = SaveAuditPipeline.audit(parsed, SaveTestData.auditData)

    val baseParsed = SaveParseResult(
        fileName = "NR0000.sl2",
        checksumOk = true,
        characters = listOf(
            SaveCharacter(
                0, "夜巫", null,
                listOf(relic(0, 202, shop), relic(1, 202, shop), relic(2, 424_242, none)),
            ),
            SaveCharacter(1, "追踪者", null, listOf(relic(0, 202, shop))),
        ),
    )

    private val otherParsed = SaveParseResult(
        fileName = "备份.sl2",
        checksumOk = true,
        characters = listOf(
            SaveCharacter(
                0, "夜巫", null,
                listOf(
                    // 与 base 的第一件完全相同（含词条顺序）：不应算作差异
                    relic(0, 202, shop),
                    relic(1, 424_242, none),
                    relic(2, 2_000_002, listOf(6_005_601, 6_003_000, 6_003_100), listOf(6_820_000, -1, -1)),
                ),
            ),
            SaveCharacter(2, "复仇者", null, listOf(relic(0, 202, shop))),
        ),
    )

    // 槽位解密失败：解析器仍然产出一个角色，只是 parseError 非空、relics 为空
    private val damagedParsed = SaveParseResult(
        fileName = "损坏.sl2",
        checksumOk = true,
        characters = listOf(
            baseParsed.characters[0],
            SaveCharacter(1, "槽位 2", "该槽位解密失败：条目密文长度不是 16 的倍数", emptyList()),
        ),
    )

    // 只把一件遗物的三条正面词条换序：身份口径按存档顺序，应报成一减一增
    private val reorderedParsed = SaveParseResult(
        fileName = "换序.sl2",
        checksumOk = true,
        characters = listOf(
            SaveCharacter(
                0, "夜巫", null,
                listOf(relic(0, 202, listOf(7_000_000, 6_630_000, 7_000_100)), relic(1, 202, shop), relic(2, 424_242, none)),
            ),
            baseParsed.characters[1],
        ),
    )

    private val renamedParsed = SaveParseResult(
        fileName = "改名.sl2",
        checksumOk = true,
        characters = listOf(
            SaveCharacter(0, "追踪者", null, baseParsed.characters[0].relics),
            baseParsed.characters[1],
        ),
    )

    // 深夜遗物 + 普通池词条、没有诅咒：审计必判非法，才会被文本报告列出来
    private val deepFlaggedParsed = SaveParseResult(
        fileName = "深夜.sl2",
        checksumOk = true,
        characters = listOf(SaveCharacter(0, "无赖", null, listOf(relic(0, 2_000_002, listOf(7_000_000, -1, -1))))),
    )

    val base: AuditedSave by lazy { audit(baseParsed) }
    val other: AuditedSave by lazy { audit(otherParsed) }

    /** 与 base 只差「槽位 2 解密失败」。 */
    val damaged: AuditedSave by lazy { audit(damagedParsed) }

    /** 与 base 只差「槽位 1 的一件遗物词条换序」。 */
    val reordered: AuditedSave by lazy { audit(reorderedParsed) }

    /** 与 base 只差「槽位 1 角色改名」。 */
    val renamed: AuditedSave by lazy { audit(renamedParsed) }

    /** 含一件非法深夜遗物。 */
    val deepFlagged: AuditedSave by lazy { audit(deepFlaggedParsed) }
}
