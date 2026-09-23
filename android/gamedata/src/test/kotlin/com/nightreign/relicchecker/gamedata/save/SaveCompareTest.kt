package com.nightreign.relicchecker.gamedata.save

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * 存档对比：macOS SaveCompareChecks.swift 的 checkSaveCompare 与 Windows tests/save_diff.test.mjs
 * 的关键断言（身份归一、多重集差、按槽位配对、解析失败不计入增减、改名提示、空列表文案）。
 */
class SaveCompareTest {
    private val none = listOf(-1L, -1L, -1L)

    private fun identity(itemId: Int, effects: List<Long>, curses: List<Long> = none, index: Int = 0) =
        SaveRelicIdentity.of(SaveRelic(index, itemId, effects, curses))

    @Test
    fun `compare base with backup yields added removed and presence notes`() {
        val result = SaveComparator.compare(SaveAuditFixtures.base, SaveAuditFixtures.other)
        assertEquals("NR0000.sl2", result.baseFileName)
        assertEquals("备份.sl2", result.otherFileName)
        assertEquals(listOf(0, 1, 2), result.characters.map { it.slot })

        val slot0 = result.characters[0]
        assertEquals(3, slot0.baseTotal)
        assertEquals(3, slot0.otherTotal)
        assertEquals(1, slot0.removed.size)
        assertEquals(1, slot0.removed[0].count)
        assertEquals(202, slot0.removed[0].identity.itemId)
        assertEquals(RelicAuditStatus.VALID, slot0.removed[0].relic.result.status)
        assertEquals("合法", slot0.removed[0].relic.statusLabel)
        assertEquals(1, slot0.added.size)
        assertEquals(2_000_002, slot0.added[0].relic.relic.itemId)
        assertTrue(slot0.added[0].relic.isDeep)
        assertEquals(RelicAuditStatus.VALID, slot0.added[0].relic.result.status)
        assertNull(slot0.presenceNote)
        assertTrue(!slot0.isIdentical && slot0.isChanged)
        assertFalse(slot0.added.any { it.identity.itemId == 424_242 } || slot0.removed.any { it.identity.itemId == 424_242 })

        val slot1 = result.characters[1]
        assertNull(slot1.otherName)
        assertEquals(1, slot1.removedCount)
        assertEquals("该槽位只在当前存档中存在", slot1.presenceNote)
        val slot2 = result.characters[2]
        assertNull(slot2.baseName)
        assertEquals(1, slot2.addedCount)
        assertEquals("该槽位只在对比存档中存在", slot2.presenceNote)

        assertEquals(2, result.totalAdded)
        assertEquals(2, result.totalRemoved)
        assertEquals(4, result.totalBase)
        assertEquals(4, result.totalOther)
        assertEquals(3, result.changedCharacters)
        assertEquals("新增 2 件 · 减少 2 件", result.summaryText)
        assertTrue(result.hasDifferences)
        assertEquals("没有符合筛选条件的差异", result.emptyListNote)
        assertNull(result.characters[0].identicalNote)
    }

    @Test
    fun `self compare has no differences`() {
        val result = SaveComparator.compare(SaveAuditFixtures.base, SaveAuditFixtures.base)
        assertFalse(result.hasDifferences)
        assertTrue(result.characters.all { it.isIdentical && !it.hasAnyDifference })
        assertEquals(0, result.changedCharacters)
        assertEquals("两份存档的遗物完全一致", result.emptyListNote)
        assertTrue(result.visibleBlocks(SaveCompareDirection.ALL, "").isEmpty())
    }

    @Test
    fun `identity uses item id and ordered rows`() {
        val a = identity(202, listOf(1, 2, 3))
        assertNotEquals(a, identity(202, listOf(3, 1, 2), index = 9), "换序算不同的遗物")
        assertNotEquals(a, identity(202, listOf(1, 2, 3), listOf(7, -1, -1)), "带诅咒与不带诅咒不同")
        assertNotEquals(a, identity(203, listOf(1, 2, 3)), "遗物 ID 不同")
        assertEquals(a, identity(202, listOf(1, 2, 3, 4), listOf(0, 0xFFFFFFFFL)), "第 4 条截断，0 / 0xFFFFFFFF 归一为空")
        assertEquals(a, identity(202, listOf(1, 2, 3), listOf(-5, 0, -1)), "负值也算空")
        assertEquals(a, identity(202, listOf(1, 2, 3), index = 3), "与存档内序号无关")
        assertEquals("202|1:-1|2:-1|3:-1", a.key)
        assertTrue(identity(203, listOf(1, 2, 3)) > a, "先比遗物 ID")
        assertEquals("1|-1:-1|-1:-1|-1:-1", identity(1, listOf(0, -1, 0xFFFFFFFFL)).key)
    }

    @Test
    fun `reordered affixes count as one removed plus one added`() {
        val slot = SaveComparator.compare(SaveAuditFixtures.base, SaveAuditFixtures.reordered).characters[0]
        assertEquals(1, slot.addedCount)
        assertEquals(1, slot.removedCount)
        assertEquals(202, slot.added[0].identity.itemId)
        assertEquals(202, slot.removed[0].identity.itemId)
        assertEquals("非法", slot.added[0].relic.statusLabel, "换序后的那件保存顺序错误")
    }

    @Test
    fun `unreadable slots never produce added or removed entries`() {
        val damaged = SaveComparator.compare(SaveAuditFixtures.base, SaveAuditFixtures.damaged)
        val slot = damaged.characters.first { it.slot == 1 }
        assertNull(slot.baseParseError)
        assertTrue(slot.otherParseError!!.contains("解密失败"))
        assertTrue(slot.hasParseError)
        assertTrue(slot.added.isEmpty() && slot.removed.isEmpty())
        assertFalse(slot.isChanged)
        assertTrue(slot.parseNote!!.startsWith("该槽位解析失败，无法对比（") && slot.parseNote!!.contains("对比存档："))
        assertEquals(0, damaged.totalAdded)
        assertEquals(0, damaged.totalRemoved)
        assertEquals(0, damaged.changedCharacters)
        assertEquals(listOf(1), damaged.unreliableCharacters.map { it.slot })
        assertTrue(damaged.hasDifferences)
        assertTrue(slot.hasAnyDifference)
        assertNull(slot.identicalNote)
        assertTrue(damaged.characters.first { it.slot == 0 }.isIdentical)
        assertEquals("没有符合筛选条件的差异", damaged.emptyListNote)

        val reversed = SaveComparator.compare(SaveAuditFixtures.damaged, SaveAuditFixtures.base)
        val reversedSlot = reversed.characters.first { it.slot == 1 }
        assertEquals(0, reversedSlot.addedCount)
        assertEquals(0, reversed.totalAdded)
        assertTrue(reversedSlot.parseNote!!.contains("当前存档："))

        // 解析失败的槽位即使被搜索滤空也要留在可见列表里
        assertEquals(listOf(1), damaged.visibleBlocks(SaveCompareDirection.ADDED, "不存在的关键字").map { it.character.slot })
    }

    @Test
    fun `renamed slot keeps its note visible and says relics are unchanged`() {
        val result = SaveComparator.compare(SaveAuditFixtures.base, SaveAuditFixtures.renamed)
        val slot = result.characters[0]
        assertTrue(slot.isIdentical)
        assertEquals("两份存档的同一槽位角色名不同：夜巫 → 追踪者", slot.presenceNote)
        assertTrue(slot.hasAnyDifference)
        assertFalse(result.characters[1].hasAnyDifference)
        assertTrue(result.hasDifferences && result.hasPresenceNotes)
        assertEquals(0, result.totalAdded + result.totalRemoved)
        assertEquals("该角色的遗物与当前存档一致。", slot.identicalNote)
        assertEquals("该角色的遗物与当前存档一致。", result.characters[1].identicalNote)
        assertEquals("没有符合筛选条件的差异", result.emptyListNote)
        assertEquals(listOf(0), result.visibleBlocks(SaveCompareDirection.ALL, "").map { it.character.slot })
    }

    @Test
    fun `direction and search filter the visible blocks`() {
        val result = SaveComparator.compare(SaveAuditFixtures.base, SaveAuditFixtures.other)
        val all = result.visibleBlocks(SaveCompareDirection.ALL, "")
        assertEquals(listOf(0, 1, 2), all.map { it.character.slot })
        val addedOnly = result.visibleBlocks(SaveCompareDirection.ADDED, "")
        assertEquals(listOf(0, 2), addedOnly.map { it.character.slot }, "只看新增时只减少的槽位被滤掉")
        assertTrue(addedOnly.all { it.removed.isEmpty() })
        val removedOnly = result.visibleBlocks(SaveCompareDirection.REMOVED, "")
        assertEquals(listOf(0, 1), removedOnly.map { it.character.slot })
        val deep = result.visibleBlocks(SaveCompareDirection.ALL, "暗淡")
        assertEquals(listOf(0), deep.map { it.character.slot })
        assertEquals(2_000_002, deep.single().added.single().relic.relic.itemId)
        assertTrue(result.visibleBlocks(SaveCompareDirection.ALL, "6820000").single().added.isNotEmpty(), "按诅咒词条 ID 搜索")
    }

    // ---- Windows save_diff.test.mjs：纯合成数据的多重集差 ----

    private fun synthetic(fileName: String, vararg characters: AuditedCharacter) =
        AuditedSave(fileName, true, emptyMap(), emptyMap(), characters.toList())

    private fun character(slot: Int, name: String, vararg relics: SaveRelic, parseError: String? = null) =
        AuditedCharacter(slot, name, parseError, relics.map { AuditedRelic(it, null, RelicAuditResult(RelicAuditStatus.VALID)) })

    private fun r(itemId: Int, vararg effects: Long) = SaveRelic(0, itemId, List(3) { effects.getOrElse(it) { -1 } }, none)

    @Test
    fun `multiset difference counts duplicates`() {
        val result = SaveComparator.compare(
            synthetic("a.sl2", character(0, "甲", r(202, 1), r(202, 1), r(300, 2), r(400, 3))),
            synthetic("b.sl2", character(0, "甲", r(202, 1), r(300, 2), r(300, 2), r(500, 4))),
        )
        val slot = result.characters.single()
        assertEquals(4, slot.baseTotal)
        assertEquals(4, slot.otherTotal)
        assertEquals(listOf(300 to 1, 500 to 1), slot.added.map { it.identity.itemId to it.count })
        assertEquals(listOf(202 to 1, 400 to 1), slot.removed.map { it.identity.itemId to it.count })
        assertEquals(2, slot.addedCount)
        assertEquals(2, slot.removedCount)
    }

    @Test
    fun `slots pair up and whole characters count as added or removed`() {
        val result = SaveComparator.compare(
            synthetic("NR0000.sl2", character(0, "夜巡者", r(202, 1), r(300, 2)), character(2, "追踪者", r(400, 3))),
            synthetic(
                "NR0000.co2",
                character(0, "夜巡者", r(202, 1), r(500, 9)),
                character(2, "追踪者", r(400, 3)),
                character(5, "复仇者", r(600, 7), r(600, 7)),
            ),
        )
        assertEquals(listOf(0, 2, 5), result.characters.map { it.slot })
        val slot0 = result.characters[0]
        assertEquals(500, slot0.added.single().identity.itemId)
        assertEquals(300, slot0.removed.single().identity.itemId)
        assertTrue(slot0.isChanged)
        assertFalse(result.characters[1].isChanged)
        val slot5 = result.characters[2]
        assertNull(slot5.baseName)
        assertEquals("复仇者", slot5.otherName)
        assertEquals(2, slot5.addedCount, "只存在于对比存档的角色，整份算新增")
        assertEquals(3, result.totalBase)
        assertEquals(5, result.totalOther)
        assertEquals(3, result.totalAdded)
        assertEquals(1, result.totalRemoved)
        assertEquals(2, result.changedCharacters)
        assertEquals(0, result.unreliableCharacters.size)

        val onlyBase = SaveComparator.compare(synthetic("a.sl2", character(1, "甲", r(202), r(203))), synthetic("b.sl2"))
        assertEquals(2, onlyBase.characters.single().removedCount)
        assertEquals(2, onlyBase.totalRemoved)
    }

    @Test
    fun `broken slot on either side does not skew other slots`() {
        val result = SaveComparator.compare(
            synthetic("a.sl2", character(0, "夜巡者", parseError = "槽位数据损坏"), character(1, "追踪者", r(400), r(401))),
            synthetic("b.sl2", character(0, "夜巡者", r(202)), character(1, "追踪者", r(400), r(402))),
        )
        assertTrue(result.characters[0].hasParseError)
        assertFalse(result.characters[1].hasParseError)
        assertEquals(1, result.characters[1].addedCount)
        assertEquals(1, result.characters[1].removedCount)
        assertEquals(1, result.totalAdded)
        assertEquals(1, result.totalRemoved)
        assertEquals(1, result.changedCharacters)
        assertEquals(1, result.unreliableCharacters.size)
    }

    @Test
    fun `blank parse error is not a parse failure`() {
        val result = SaveComparator.compare(
            synthetic("a.sl2", character(0, "甲", r(202), parseError = "")),
            synthetic("b.sl2", character(0, "甲", parseError = "   ")),
        )
        assertFalse(result.characters[0].hasParseError)
        assertEquals(1, result.characters[0].removedCount)
    }

    @Test
    fun `save filter matches desktop semantics`() {
        val character = SaveAuditFixtures.base.characters[0]
        assertEquals(3, SaveFilter.ALL.apply(character.relics, "").size)
        assertEquals(listOf(424_242), SaveFilter.INVALID_ONLY.apply(character.relics, "").map { it.relic.itemId })
        assertTrue(SaveFilter.DEEP_ONLY.apply(character.relics, "").isEmpty())
        assertEquals(2, SaveFilter.ALL.apply(character.relics, "火燃").size, "按遗物名搜索")
        assertEquals(2, SaveFilter.ALL.apply(character.relics, "生命力+1").size, "按词条名搜索（全角＋折叠为 +）")
        assertEquals(1, SaveFilter.ALL.apply(character.relics, "424242").size, "按遗物 ID 搜索")
        assertEquals("该角色没有持有深夜遗物。", SaveFilter.DEEP_ONLY.emptyDetail(character))
        assertEquals("🎉 未发现不合法遗物", SaveFilter.INVALID_ONLY.emptyTitle())
        assertEquals("没有符合条件的遗物", SaveFilter.ALL.emptyTitle())
        assertEquals(listOf("全部", "仅非法", "深夜遗物"), SaveFilter.entries.map { it.title })
        assertEquals(listOf("全部", "只看新增", "只看减少"), SaveCompareDirection.entries.map { it.title })
    }
}
