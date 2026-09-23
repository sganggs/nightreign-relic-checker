package com.nightreign.relicchecker.gamedata.save

import com.nightreign.relicchecker.gamedata.save.SaveFileParser.CHECKSUM_START
import com.nightreign.relicchecker.gamedata.save.SaveFileParser.CHECKSUM_TRAILER
import com.nightreign.relicchecker.gamedata.save.SaveFileParser.ENTRY_COUNT_GAP
import com.nightreign.relicchecker.gamedata.save.SaveFileParser.ENTRY_RECORD_LEN
import com.nightreign.relicchecker.gamedata.save.SaveFileParser.NAME_GAP
import com.nightreign.relicchecker.gamedata.save.SaveFileParser.NAME_MAX_UNITS
import com.nightreign.relicchecker.gamedata.save.SaveFileParser.STATE_SLOT_COUNT
import com.nightreign.relicchecker.gamedata.save.SaveFileParser.STATE_START
import java.io.ByteArrayOutputStream
import java.security.MessageDigest
import javax.crypto.Cipher
import javax.crypto.spec.IvParameterSpec
import javax.crypto.spec.SecretKeySpec

/**
 * 合成存档夹具：逐个移植 windows/internal/savefile/savefile_test.go 的构造器
 * （emptyState / weaponState / armorState / goodsState / relicState / sealPlain /
 * characterPlain / characterPlainWithEntries / sharedPlain / encryptEntry / buildSave /
 * fixtureSlot0 / fixtureSlot2 / minimalPlain / buildFixture）。
 */
internal object SaveFixtures {
    private const val BND4_HEADER_LEN = 64
    private const val BND4_ENTRY_HEADER_LEN = 32
    private const val IV_SIZE = 16
    private const val AES_BLOCK = 16
    const val EMPTY = 0xFFFFFFFFL

    fun putU32(buffer: ByteArray, offset: Int, value: Long) {
        buffer[offset] = (value and 0xFF).toByte()
        buffer[offset + 1] = ((value shr 8) and 0xFF).toByte()
        buffer[offset + 2] = ((value shr 16) and 0xFF).toByte()
        buffer[offset + 3] = ((value shr 24) and 0xFF).toByte()
    }

    private fun putU16(buffer: ByteArray, offset: Int, value: Int) {
        buffer[offset] = (value and 0xFF).toByte()
        buffer[offset + 1] = ((value shr 8) and 0xFF).toByte()
    }

    /** 一条空记录：ga_handle 0，item_id 0xFFFFFFFF。 */
    fun emptyState(): ByteArray = byteArrayOf(0, 0, 0, 0, -1, -1, -1, -1)

    /** 88 字节武器记录（类型半字节 0x8）。 */
    fun weaponState(instance: Long): ByteArray = ByteArray(88).also {
        putU32(it, 0, 0x80000000L or instance)
        putU32(it, 4, 0x80000000L or 1_000_000L)
    }

    /** 16 字节防具记录（类型半字节 0x9）。 */
    fun armorState(instance: Long): ByteArray = ByteArray(16).also {
        putU32(it, 0, 0x90000000L or instance)
        putU32(it, 4, 0x90000000L or 40_000L)
    }

    /** 8 字节未知类型记录（类型半字节 0xB），扫描器只跳过 8 字节头。 */
    fun goodsState(instance: Long): ByteArray = ByteArray(8).also {
        putU32(it, 0, 0xB0000000L or instance)
        putU32(it, 4, 0xB0000000L or 9_600L)
    }

    /** 80 字节遗物记录，词条写原始值（未归一化），用来覆盖两种空哨兵。 */
    fun relicState(instance: Long, realId: Long, effects: LongArray, curses: LongArray): ByteArray = ByteArray(80).also {
        putU32(it, 0, 0xC0000000L or instance)
        putU32(it, 4, 0x80000000L or realId)
        putU32(it, 8, 0x80000000L or realId) // 耐久镜像 item_id
        putU32(it, 12, EMPTY) // unk_1
        effects.forEachIndexed { index, value -> putU32(it, 16 + 4 * index, value) }
        curses.forEachIndexed { index, value -> putU32(it, 56 + 4 * index, value) }
        putU32(it, 68, EMPTY) // unk_2
    }

    /** 补齐到 AES 块大小并追加 28 字节尾：MD5(plain[4 : L-28]) 在 [L-28 : L-12]，再补 12 字节。 */
    fun sealPlain(content: ByteArray): ByteArray {
        var body = content
        val rem = (body.size + CHECKSUM_TRAILER) % AES_BLOCK
        if (rem != 0) body += ByteArray(AES_BLOCK - rem)
        val plain = body + ByteArray(CHECKSUM_TRAILER)
        val end = plain.size - CHECKSUM_TRAILER
        val digest = MessageDigest.getInstance("MD5").apply { update(plain, CHECKSUM_START, end - CHECKSUM_START) }.digest()
        digest.copyInto(plain, end)
        return plain
    }

    private fun characterBody(name: String, records: List<ByteArray>): ByteArrayOutputStream {
        val body = ByteArrayOutputStream()
        body.write(ByteArray(STATE_START))
        records.forEach { body.write(it) }
        repeat(STATE_SLOT_COUNT - records.size) { body.write(emptyState()) }
        body.write(ByteArray(NAME_GAP))
        val nameBuf = ByteArray(NAME_MAX_UNITS * 2)
        name.take(NAME_MAX_UNITS).forEachIndexed { index, char -> putU16(nameBuf, 2 * index, char.code) }
        body.write(nameBuf)
        return body
    }

    /** 一个角色槽位的明文：0x14 头、记录（补空到 5120 条）、0x94 间隔、UTF-16LE 名字、校验尾。 */
    fun characterPlain(name: String, records: List<ByteArray>): ByteArray =
        sealPlain(characterBody(name, records).toByteArray())

    /** characterPlain + 只引用给定 gaHandle 的物品条目区（用于幽灵遗物过滤）。 */
    fun characterPlainWithEntries(name: String, records: List<ByteArray>, owned: List<Long>): ByteArray {
        val body = characterBody(name, records)
        body.write(ByteArray(ENTRY_COUNT_GAP - NAME_MAX_UNITS * 2))
        body.write(ByteArray(4).also { putU32(it, 0, owned.size.toLong()) })
        owned.forEach { ga ->
            body.write(ByteArray(ENTRY_RECORD_LEN).also {
                putU32(it, 0, ga)
                putU32(it, 4, ga and 0x00FFFFFFL)
            })
        }
        return sealPlain(body.toByteArray())
    }

    /** USERDATA_10：withMagic 时 10 个占用标志位于 FACE 魔数前 61 字节。 */
    fun sharedPlain(flags: IntArray, withMagic: Boolean): ByteArray {
        val buf = ByteArray(128)
        if (withMagic) {
            flags.forEachIndexed { index, flag -> buf[16 + index] = flag.toByte() }
            SaveFileParser.FACE_MAGIC.copyInto(buf, 16 + 61)
        }
        return sealPlain(buf)
    }

    /** IV + AES-128-CBC 密文。 */
    fun encryptEntry(plain: ByteArray, seed: Int): ByteArray {
        require(plain.size % AES_BLOCK == 0) { "fixture plaintext not block aligned: ${plain.size} bytes" }
        val iv = ByteArray(IV_SIZE) { seed.toByte() }
        val cipher = Cipher.getInstance("AES/CBC/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, SecretKeySpec(SaveFileParser.AES_KEY, "AES"), IvParameterSpec(iv))
        return iv + cipher.doFinal(plain)
    }

    /** 把加密条目装进 BND4 容器。 */
    fun buildSave(entries: List<ByteArray>): ByteArray {
        val out = ByteArrayOutputStream()
        val header = ByteArray(BND4_HEADER_LEN)
        SaveFileParser.BND4_MAGIC.copyInto(header)
        putU32(header, 12, entries.size.toLong())
        out.write(header)
        var offset = BND4_HEADER_LEN + BND4_ENTRY_HEADER_LEN * entries.size
        entries.forEach { entry ->
            val h = ByteArray(BND4_ENTRY_HEADER_LEN)
            SaveFileParser.ENTRY_MAGIC.copyInto(h)
            putU32(h, 8, entry.size.toLong())
            putU32(h, 16, offset.toLong())
            out.write(h)
            offset += entry.size
        }
        entries.forEach { out.write(it) }
        return out.toByteArray()
    }

    fun longs(vararg values: Long): LongArray = values

    /** 两件遗物夹在空 / 武器 / 防具 / 物品记录之间；空词条两种哨兵都有。 */
    fun fixtureSlot0(): ByteArray = characterPlain(
        "夜巡者",
        listOf(
            emptyState(),
            weaponState(0x54),
            relicState(0x100, 2_000_002, longs(6_001_400, 6_600_000, EMPTY), longs(6_800_000, 0, EMPTY)),
            armorState(0x55),
            goodsState(0x56),
            relicState(0x101, 150, longs(7_000_000, 0, EMPTY), longs(EMPTY, EMPTY, 0)),
            emptyState(),
        ),
    )

    fun fixtureSlot2(): ByteArray = characterPlain(
        "Knight-02",
        listOf(relicState(0x200, 1001, longs(7_000_000, EMPTY, EMPTY), longs(EMPTY, EMPTY, EMPTY))),
    )

    /** 最小的合法槽位明文：按角色解析会立刻截断，但校验和能通过。 */
    fun minimalPlain(): ByteArray = sealPlain(ByteArray(STATE_START))

    /** 标准 11 条目存档：槽位 0 与 2 已占用，其余是最小占位数据。 */
    fun buildFixture(): ByteArray = buildSave(standardEntries())

    fun standardEntries(slot0: ByteArray = fixtureSlot0()): MutableList<ByteArray> {
        val entries = MutableList(11) { index -> if (index < 10) encryptEntry(minimalPlain(), index + 1) else ByteArray(0) }
        entries[0] = encryptEntry(slot0, 0xA0)
        entries[2] = encryptEntry(fixtureSlot2(), 0xA2)
        entries[10] = encryptEntry(sharedPlain(intArrayOf(1, 0, 1, 0, 0, 0, 0, 0, 0, 0), true), 0xAA)
        return entries
    }
}
