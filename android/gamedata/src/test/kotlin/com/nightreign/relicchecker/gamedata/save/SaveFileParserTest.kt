package com.nightreign.relicchecker.gamedata.save

import com.nightreign.relicchecker.gamedata.save.SaveFixtures.EMPTY
import com.nightreign.relicchecker.gamedata.save.SaveFixtures.buildFixture
import com.nightreign.relicchecker.gamedata.save.SaveFixtures.buildSave
import com.nightreign.relicchecker.gamedata.save.SaveFixtures.characterPlainWithEntries
import com.nightreign.relicchecker.gamedata.save.SaveFixtures.encryptEntry
import com.nightreign.relicchecker.gamedata.save.SaveFixtures.fixtureSlot0
import com.nightreign.relicchecker.gamedata.save.SaveFixtures.fixtureSlot2
import com.nightreign.relicchecker.gamedata.save.SaveFixtures.longs
import com.nightreign.relicchecker.gamedata.save.SaveFixtures.minimalPlain
import com.nightreign.relicchecker.gamedata.save.SaveFixtures.relicState
import com.nightreign.relicchecker.gamedata.save.SaveFixtures.sealPlain
import com.nightreign.relicchecker.gamedata.save.SaveFixtures.sharedPlain
import com.nightreign.relicchecker.gamedata.save.SaveFixtures.standardEntries
import java.io.ByteArrayInputStream
import kotlin.test.Test
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json

/** 逐条移植 windows/internal/savefile/savefile_test.go（每个 Go Test 一条）。 */
class SaveFileParserTest {
    private fun relic(index: Int, itemId: Int, effects: List<Long>, curses: List<Long>) =
        SaveRelic(index, itemId, effects, curses)

    // TestParseFixture
    @Test
    fun `parse fixture yields both occupied slots with normalized affixes`() {
        val payload = SaveFileParser.parse(buildFixture(), "NR0000.sl2")
        assertEquals("NR0000.sl2", payload.fileName)
        assertTrue(payload.checksumOk)
        assertEquals(2, payload.characters.size)

        val c0 = payload.characters[0]
        assertEquals(0, c0.slot)
        assertEquals("夜巡者", c0.name)
        assertNull(c0.parseError)
        assertEquals(
            listOf(
                relic(0, 2_000_002, listOf(6_001_400, 6_600_000, -1), listOf(6_800_000, -1, -1)),
                relic(1, 150, listOf(7_000_000, -1, -1), listOf(-1, -1, -1)),
            ),
            c0.relics,
        )

        val c2 = payload.characters[1]
        assertEquals(2, c2.slot)
        assertEquals("Knight-02", c2.name)
        assertNull(c2.parseError)
        assertEquals(listOf(relic(0, 1001, listOf(7_000_000, -1, -1), listOf(-1, -1, -1))), c2.relics)
    }

    // TestPayloadWireShape：与桌面端桥接的 JSON 逐字一致
    @Test
    fun `payload json matches the desktop wire shape byte for byte`() {
        val payload = SaveParseResult(
            fileName = "NR0000.sl2",
            checksumOk = true,
            characters = listOf(
                SaveCharacter(
                    slot = 0,
                    name = "甲",
                    parseError = null,
                    relics = listOf(relic(0, 2_000_002, listOf(6_001_400, 6_600_000, -1), listOf(6_800_000, -1, -1))),
                ),
                SaveCharacter(slot = 3, name = "槽位 4", parseError = "槽位数据损坏", relics = emptyList()),
            ),
        )
        val want = """{"fileName":"NR0000.sl2","checksumOk":true,"characters":[""" +
            """{"slot":0,"name":"甲","parseError":null,"relics":[""" +
            """{"index":0,"itemId":2000002,"effects":[6001400,6600000,-1],"curses":[6800000,-1,-1]}]},""" +
            """{"slot":3,"name":"槽位 4","parseError":"槽位数据损坏","relics":[]}]}"""
        assertEquals(want, Json.encodeToString(payload))
    }

    // TestParseRejectsBadInput
    @Test
    fun `structurally broken input is rejected`() {
        val good = buildFixture()
        val corruptEntryMagic = good.copyOf().also { it[64] = 0x41 }
        val zeroEntries = good.copyOf().also { SaveFixtures.putU32(it, 12, 0) }
        val cases = listOf(
            "空输入" to ByteArray(0),
            "非 BND4" to ("XXXX".toByteArray() + ByteArray(96)),
            "BND4 头截断" to "BND4".toByteArray(),
            "条目头越界" to good.copyOfRange(0, 64 + 8),
            "条目数据越界" to good.copyOfRange(0, good.size - 31),
            "条目魔数不符" to corruptEntryMagic,
            "条目数为零" to zeroEntries,
        )
        for ((name, data) in cases) {
            assertFailsWith<SaveFileException>(name) { SaveFileParser.parse(data, "bad.sl2") }
        }
        assertEquals(
            "存档文件损坏：文件头不完整",
            assertFailsWith<SaveFileException> { SaveFileParser.parse("BND4".toByteArray(), "bad.sl2") }.message,
        )
        assertEquals(
            "存档文件损坏：条目数无效（0）",
            assertFailsWith<SaveFileException> { SaveFileParser.parse(zeroEntries, "bad.sl2") }.message,
        )
        assertEquals(
            "存档文件损坏：条目 0 魔数不符",
            assertFailsWith<SaveFileException> { SaveFileParser.parse(corruptEntryMagic, "bad.sl2") }.message,
        )
        assertEquals(
            "存档文件损坏：条目 0 头部越界",
            assertFailsWith<SaveFileException> { SaveFileParser.parse(good.copyOfRange(0, 72), "bad.sl2") }.message,
        )
        assertEquals(
            "存档文件损坏：条目 10 数据越界",
            assertFailsWith<SaveFileException> { SaveFileParser.parse(good.copyOfRange(0, good.size - 31), "bad.sl2") }.message,
        )
    }

    // TestBadCipherLengthIsIsolated：密文长度不是 16 的倍数只隔离为该槽位的 parseError
    @Test
    fun `bad cipher length is isolated to the slot`() {
        val save = buildSave(listOf(ByteArray(16) { 1 } + ByteArray(24) { 2 }))
        val payload = SaveFileParser.parse(save, "bad.sl2")
        assertEquals(1, payload.characters.size)
        val c = payload.characters[0]
        assertTrue(c.parseError!!.contains("解密失败"), c.parseError)
        assertEquals("该槽位解密失败：加密数据长度无效", c.parseError)
        assertEquals("槽位 1", c.name)
        assertTrue(c.relics.isEmpty())
    }

    // TestNotSaveFileMessage
    @Test
    fun `non save file reports the shared message`() {
        val error = assertFailsWith<SaveFileException> {
            SaveFileParser.parse(byteArrayOf(0x50, 0x4B, 0x03, 0x04) + "junk".toByteArray(), "bad.sl2")
        }
        assertEquals("不是有效的存档文件", error.message)
    }

    // TestChecksumMismatchDegrades：MD5 不符只翻转 checksumOk，不阻断解析
    @Test
    fun `checksum mismatch degrades without blocking the parse`() {
        val slot0 = fixtureSlot0().also { it[it.size - 20] = (it[it.size - 20].toInt() xor 0xFF).toByte() }
        val payload = SaveFileParser.parse(buildSave(standardEntries(slot0)), "NR0000.sl2")
        assertFalse(payload.checksumOk)
        assertEquals(2, payload.characters.size)
        assertEquals(2, payload.characters[0].relics.size)
    }

    // TestSlotParseErrorIsIsolated：截断的槽位只影响自己
    @Test
    fun `truncated slot only poisons itself`() {
        val entries = standardEntries()
        entries[0] = encryptEntry(sealPlain(ByteArray(SaveFileParser.STATE_START + 64)), 0xA0)
        val payload = SaveFileParser.parse(buildSave(entries), "NR0000.sl2")
        assertEquals(2, payload.characters.size)
        val c0 = payload.characters[0]
        assertNotNull(c0.parseError)
        assertTrue(c0.parseError!!.startsWith("存档数据截断："), c0.parseError)
        assertEquals("槽位 1", c0.name)
        val c2 = payload.characters[1]
        assertNull(c2.parseError)
        assertEquals(1, c2.relics.size)
    }

    // TestTruncatedRelicRecord：80 字节遗物记录越过明文末尾应报 parseError，而不是崩溃
    @Test
    fun `truncated relic record yields a parse error`() {
        val content = ByteArray(SaveFileParser.STATE_START) +
            relicState(0x100, 2_000_002, longs(6_001_400, EMPTY, EMPTY), longs(EMPTY, EMPTY, EMPTY)).copyOfRange(0, 8)
        val payload = SaveFileParser.parse(buildSave(listOf(encryptEntry(sealPlain(content), 0x01))), "NR0000.sl2")
        assertEquals(1, payload.characters.size)
        assertNotNull(payload.characters[0].parseError)
    }

    // TestMissingSlotFlagsAssumesAllOccupied
    @Test
    fun `missing slot flags assume every slot occupied`() {
        val entries = MutableList(11) { index -> if (index < 10) encryptEntry(minimalPlain(), index + 1) else ByteArray(0) }
        entries[2] = encryptEntry(fixtureSlot2(), 0xA2)
        entries[10] = encryptEntry(sharedPlain(IntArray(10), withMagic = false), 0xAA)
        val payload = SaveFileParser.parse(buildSave(entries), "NR0000.sl2")
        assertEquals(10, payload.characters.size)
        payload.characters.forEach { c ->
            if (c.slot == 2) {
                assertNull(c.parseError)
                assertEquals(1, c.relics.size)
            } else {
                assertNotNull(c.parseError, "slot ${c.slot}: placeholder data should yield parseError")
            }
        }
    }

    // TestFewerEntriesThanSlots：条目数以外的槽位直接跳过；没有 USERDATA_10 时按全占用
    @Test
    fun `slots beyond the entry count are skipped`() {
        val entries = listOf(
            encryptEntry(fixtureSlot0(), 0xA0),
            encryptEntry(minimalPlain(), 0x01),
            encryptEntry(fixtureSlot2(), 0xA2),
        )
        val payload = SaveFileParser.parse(buildSave(entries), "NR0000.co2")
        assertEquals(3, payload.characters.size)
        assertEquals("夜巡者", payload.characters[0].name)
        assertEquals("Knight-02", payload.characters[2].name)
        assertNotNull(payload.characters[1].parseError)
    }

    // TestGhostRelicsFilteredByEntryArea：未被物品条目区引用的遗物是已删除残留，必须过滤
    @Test
    fun `ghost relics are filtered by the item entry area`() {
        val empty = longs(EMPTY, EMPTY, EMPTY)
        val records = listOf(
            relicState(1, 2071, longs(7_006_600, 7_006_700, 7_037_800), empty),
            relicState(2, 2071, longs(7_006_600, 7_006_700, 7_037_800), empty), // 幽灵残留
            relicState(3, 150, longs(6_630_000, EMPTY, EMPTY), empty),
        )
        val plain = characterPlainWithEntries("甲", records, listOf(0xC0000001L, 0xC0000003L))
        val payload = SaveFileParser.parse(buildSave(listOf(encryptEntry(plain, 7))), "s.sl2")
        val relics = payload.characters[0].relics
        assertEquals(2, relics.size, "ghost filtered")
        assertEquals(listOf(2071, 150), relics.map { it.itemId })
        assertEquals(listOf(0, 1), relics.map { it.index }, "indexes resequenced")
    }

    // zz_verify_truncname_test.go：名字区在第 4 个完整 UTF-16 单元后截断，仍读出部分名字
    @Test
    fun `truncated name region still recovers the partial name`() {
        val nameOff = SaveFileParser.STATE_START + SaveFileParser.STATE_SLOT_COUNT * 8 + SaveFileParser.NAME_GAP
        assertEquals(41128, nameOff)
        val plain = ByteArray(nameOff + 8)
        assertEquals(0, plain.size % 16)
        "TEST".forEachIndexed { index, char -> plain[nameOff + 2 * index] = char.code.toByte() }
        val character = SaveFileParser.parseCharacter(3, plain)
        assertEquals("TEST", character.name)
        assertNull(character.parseError)
    }

    // ---- SAF 输入的防御（对应 export.go / parsedata_test.go 里与手机相关的部分） ----

    @Test
    fun `display file name strips directories and falls back when blank`() {
        assertEquals("NR0000.sl2", SaveFileInput.displayFileName("""C:\Users\a\AppData\Roaming\Nightreign\1\NR0000.sl2"""))
        assertEquals("NR0000.co2", SaveFileInput.displayFileName("/tmp/NR0000.co2"))
        assertEquals("NR0000.sl2", SaveFileInput.displayFileName("  NR0000.sl2  "))
        assertEquals("所选存档", SaveFileInput.displayFileName(""))
        assertEquals("所选存档", SaveFileInput.displayFileName("   "))
        assertEquals("所选存档", SaveFileInput.displayFileName(null))
    }

    @Test
    fun `read limited rejects empty and oversize input and round trips the fixture`() {
        val fixture = buildFixture()
        val read = SaveFileInput.readLimited(ByteArrayInputStream(fixture))
        assertContentEquals(fixture, read)
        assertEquals(SaveFileParser.parse(fixture, "a.sl2"), SaveFileParser.parse(read, "a.sl2"))

        assertEquals(
            "没有读到文件内容",
            assertFailsWith<SaveFileException> { SaveFileInput.readLimited(ByteArrayInputStream(ByteArray(0))) }.message,
        )
        val tooLarge = assertFailsWith<SaveFileException> {
            SaveFileInput.readLimited(ByteArrayInputStream(ByteArray(1025)), limit = 1024)
        }
        assertTrue(tooLarge.message!!.startsWith("文件过大"))
        assertEquals("文件过大：超过 96 MB 的上限", SaveFileInput.TOO_LARGE)
        assertFailsWith<SaveFileException> { SaveFileInput.checkDeclaredSize(SaveFileInput.MAX_SAVE_BYTES + 1L) }
        SaveFileInput.checkDeclaredSize(null)
        SaveFileInput.checkDeclaredSize(1024)
    }

    @Test
    fun `checksum helper verifies sealed plaintext only`() {
        val sealed = sealPlain(ByteArray(40) { it.toByte() })
        assertTrue(SaveFileParser.verifyChecksum(sealed))
        assertFalse(SaveFileParser.verifyChecksum(sealed.copyOf().also { it[5] = 99 }))
        assertFalse(SaveFileParser.verifyChecksum(ByteArray(10)))
    }
}
