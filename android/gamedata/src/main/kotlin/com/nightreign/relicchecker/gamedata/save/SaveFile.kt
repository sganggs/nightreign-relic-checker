package com.nightreign.relicchecker.gamedata.save

import java.io.InputStream
import java.security.MessageDigest
import javax.crypto.Cipher
import javax.crypto.spec.IvParameterSpec
import javax.crypto.spec.SecretKeySpec
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/**
 * 《黑夜君临》存档（.sl2 / .co2）的只读解析：BND4 容器 + 每条目 AES-128-CBC。
 *
 * 逐行移植 Windows 端 `windows/internal/savefile/savefile.go`（与 macOS 端
 * `RelicCore/SaveFile.swift` 互相对拍过）：
 * - 结构性损坏（魔数、条目头越界）整体失败，抛 [SaveFileException]；
 * - 单个条目的问题（密文长度、槽位数据截断）隔离到该角色的 [SaveCharacter.parseError]；
 * - 每条目 MD5 校验不符只把 [SaveParseResult.checksumOk] 置 false，不阻断解析；
 * - USERDATA_10 里找不到占用标志时按 10 个槽位全占用处理；
 * - 物品状态区里未被物品条目区引用的遗物是已删除残留（幽灵遗物），过滤掉；
 * - 空词条（0 / 0xFFFFFFFF）归一化为 -1。
 *
 * 词条 ID 用 [Long]：存档里是 u32，与 Go 的 int64 / Swift 的 Int 一致，坏值不会被截成负数。
 * 本文件不做任何写入。
 */
class SaveFileException(message: String) : Exception(message)

/** 一件遗物的物品状态。[effects] 与 [curses] 恒为 3 位，空槽为 -1。 */
@Serializable
data class SaveRelic(
    val index: Int,
    @SerialName("itemId") val itemId: Int,
    val effects: List<Long>,
    val curses: List<Long>,
)

/** 一个已占用的角色槽位（USERDATA_0..9）。 */
@Serializable
data class SaveCharacter(
    val slot: Int,
    val name: String,
    val parseError: String?,
    val relics: List<SaveRelic>,
)

/** 解析结果；JSON 形状与桌面端桥接契约一致（见 [SaveFileParser] 的测试）。 */
@Serializable
data class SaveParseResult(
    val fileName: String,
    val checksumOk: Boolean,
    val characters: List<SaveCharacter>,
)

object SaveFileParser {
    private const val BND4_HEADER_LEN = 64
    private const val BND4_ENTRY_HEADER_LEN = 32
    private const val IV_SIZE = 16
    private const val AES_BLOCK = 16

    // 每条目完整性：MD5(plain[4 : L-28]) 存在 plain[L-28 : L-12]，其后 12 字节填充
    internal const val CHECKSUM_START = 4
    internal const val CHECKSUM_TRAILER = 28

    internal const val CHARACTER_SLOTS = 10 // USERDATA_0..9 是角色槽位；USERDATA_10 是共享数据
    internal const val STATE_SLOT_COUNT = 5120 // 物品状态区固定 5120 条变长记录
    internal const val STATE_START = 0x14 // 物品状态区起点
    internal const val NAME_GAP = 0x94 // 状态区结束到角色名的间隔
    internal const val NAME_MAX_UNITS = 16 // 角色名：UTF-16LE，最多 16 个单元，NUL 结尾

    // 物品条目区：角色名后 0x5B8 处的 u32 计数 + 3065 条 14 字节记录
    internal const val ENTRY_SLOT_COUNT = 3065
    internal const val ENTRY_RECORD_LEN = 14
    internal const val ENTRY_COUNT_GAP = 0x5B8

    internal val BND4_MAGIC = byteArrayOf(0x42, 0x4E, 0x44, 0x34) // "BND4"
    internal val ENTRY_MAGIC = byteArrayOf(0x40, 0x00, 0x00, 0x00, -1, -1, -1, -1)

    // USERDATA_10 里 FACE 魔数前 61 字节是 10 个槽位的占用标志
    internal val FACE_MAGIC = byteArrayOf(0x27, 0x00, 0x00, 0x46, 0x41, 0x43, 0x45)

    // 所有条目共用的 AES-128 密钥（"DS2 key"）
    internal val AES_KEY = byteArrayOf(
        0x18, 0xF6.toByte(), 0x32, 0x66, 0x05, 0xBD.toByte(), 0x17, 0x8A.toByte(),
        0x55, 0x24, 0x52, 0x3A, 0xC0.toByte(), 0xA0.toByte(), 0xC6.toByte(), 0x09,
    )

    /** 与桌面端同一句话。 */
    const val NOT_A_SAVE_FILE = "不是有效的存档文件"

    private class EntryRef(val size: Int, val dataOffset: Int)

    /**
     * 解析整份存档。结构性损坏抛 [SaveFileException]；单个槽位的失败写进该角色的 parseError，
     * 其余槽位照常解析。
     */
    fun parse(data: ByteArray, fileName: String): SaveParseResult {
        if (data.size < BND4_MAGIC.size || !data.regionEquals(0, BND4_MAGIC)) {
            throw SaveFileException(NOT_A_SAVE_FILE)
        }
        if (data.size < BND4_HEADER_LEN) {
            throw SaveFileException("存档文件损坏：文件头不完整")
        }
        val entryCount = readInt32(data, 12)
        if (entryCount <= 0) {
            throw SaveFileException("存档文件损坏：条目数无效（$entryCount）")
        }

        // 只解码本功能读取的条目：USERDATA_0..9 是角色槽位，USERDATA_10 是共享账号数据
        val parsed = minOf(entryCount, CHARACTER_SLOTS + 1)

        // 结构检查：本功能读取的每个条目头都必须完整
        val refs = List(parsed) { readEntryHeader(data, it) }

        // 从这里起条目级失败一律隔离：共享条目坏了按全占用处理，角色槽位坏了写进 parseError
        var checksumOk = true
        fun decrypt(index: Int): ByteArray {
            val plain = decryptEntry(data, refs[index])
            if (!verifyChecksum(plain)) checksumOk = false
            return plain
        }

        var occupied = allOccupied()
        if (parsed > CHARACTER_SLOTS) {
            runCatching { decrypt(CHARACTER_SLOTS) }.getOrNull()?.let { occupied = slotFlags(it) }
        }

        val characters = ArrayList<SaveCharacter>(CHARACTER_SLOTS)
        for (slot in 0 until minOf(CHARACTER_SLOTS, parsed)) {
            if (!occupied[slot]) continue
            val plain = try {
                decrypt(slot)
            } catch (error: Exception) {
                characters += SaveCharacter(
                    slot = slot,
                    name = fallbackName(slot),
                    parseError = "该槽位解密失败：${error.message ?: error::class.java.simpleName}",
                    relics = emptyList(),
                )
                continue
            }
            characters += parseCharacter(slot, plain)
        }
        return SaveParseResult(fileName = fileName, checksumOk = checksumOk, characters = characters)
    }

    /** 条目 i 的头部（魔数与越界检查）；写法不会溢出。 */
    private fun readEntryHeader(data: ByteArray, index: Int): EntryRef {
        val pos = BND4_HEADER_LEN + BND4_ENTRY_HEADER_LEN * index
        if (pos + BND4_ENTRY_HEADER_LEN > data.size) {
            throw SaveFileException("存档文件损坏：条目 $index 头部越界")
        }
        if (!data.regionEquals(pos, ENTRY_MAGIC)) {
            throw SaveFileException("存档文件损坏：条目 $index 魔数不符")
        }
        val size = readInt32(data, pos + 8)
        val dataOffset = readInt32(data, pos + 16)
        if (size < 0 || dataOffset <= 0 || dataOffset > data.size - size) {
            throw SaveFileException("存档文件损坏：条目 $index 数据越界")
        }
        return EntryRef(size, dataOffset)
    }

    /** 解密一个条目（IV 前缀 + AES-128-CBC，无填充）。失败只影响该条目。 */
    private fun decryptEntry(data: ByteArray, ref: EntryRef): ByteArray {
        if (ref.size <= IV_SIZE || (ref.size - IV_SIZE) % AES_BLOCK != 0) {
            throw SaveFileException("加密数据长度无效")
        }
        val cipher = Cipher.getInstance("AES/CBC/NoPadding")
        cipher.init(
            Cipher.DECRYPT_MODE,
            SecretKeySpec(AES_KEY, "AES"),
            IvParameterSpec(data, ref.dataOffset, IV_SIZE),
        )
        return cipher.doFinal(data, ref.dataOffset + IV_SIZE, ref.size - IV_SIZE)
    }

    /** MD5(plain[4 : L-28]) 是否等于 plain[L-28 : L-12]。 */
    internal fun verifyChecksum(plain: ByteArray): Boolean {
        if (plain.size < CHECKSUM_START + CHECKSUM_TRAILER) return false
        val end = plain.size - CHECKSUM_TRAILER
        val digest = MessageDigest.getInstance("MD5").apply { update(plain, CHECKSUM_START, end - CHECKSUM_START) }.digest()
        return plain.regionEquals(end, digest)
    }

    private fun allOccupied(): BooleanArray = BooleanArray(CHARACTER_SLOTS) { true }

    /** 在 USERDATA_10 里找占用标志（FACE 魔数前 61 字节）；找不到时按全占用。 */
    private fun slotFlags(shared: ByteArray): BooleanArray {
        var pos = 0
        while (pos + FACE_MAGIC.size <= shared.size) {
            val hit = shared.indexOf(FACE_MAGIC, pos)
            if (hit < 0) break
            val start = hit - 61
            if (start >= 0 && start + CHARACTER_SLOTS <= shared.size &&
                (0 until CHARACTER_SLOTS).all { shared[start + it].toInt() and 0xFF <= 1 }
            ) {
                return BooleanArray(CHARACTER_SLOTS) { shared[start + it].toInt() == 1 }
            }
            pos = hit + 1
        }
        return allOccupied()
    }

    /**
     * 扫描一个已解密的角色槽位：0x14 起 5120 条变长物品记录，状态区结束后 0x94 处是角色名。
     * 截断写进 parseError（保留已解析出的遗物），不抛异常。
     */
    internal fun parseCharacter(slot: Int, plain: ByteArray): SaveCharacter {
        val relics = ArrayList<SaveRelic>()
        val gaHandles = ArrayList<Long>()
        fun fail(message: String) = SaveCharacter(slot, fallbackName(slot), message, relics.toList())

        var off = STATE_START
        for (record in 0 until STATE_SLOT_COUNT) {
            if (off + 8 > plain.size) return fail("存档数据截断：第 $record 条物品记录越界")
            val gaHandle = readUInt32(plain, off)
            val itemId = readUInt32(plain, off + 4)

            // 按类型半字节决定记录长度；未知的非空类型（例如 0xB 物品）只占 8 字节头
            val size = when (gaHandle and 0xF0000000L) {
                0x80000000L -> 88 // 武器
                0x90000000L -> 16 // 防具
                0xC0000000L -> 80 // 遗物
                else -> 8
            }
            if (off + size > plain.size) return fail("存档数据截断：第 $record 条物品记录不完整")
            if (gaHandle and 0xF0000000L == 0xC0000000L) {
                gaHandles += gaHandle
                relics += SaveRelic(
                    index = relics.size,
                    itemId = (itemId and 0x00FFFFFFL).toInt(),
                    effects = listOf(affixAt(plain, off + 16), affixAt(plain, off + 20), affixAt(plain, off + 24)),
                    curses = listOf(affixAt(plain, off + 56), affixAt(plain, off + 60), affixAt(plain, off + 64)),
                )
            }
            off += size
        }

        val nameOff = off + NAME_GAP
        val name = readName(plain, nameOff) ?: fallbackName(slot)
        return SaveCharacter(slot, name, null, filterOwnedRelics(plain, nameOff, relics, gaHandles))
    }

    /**
     * 只保留被物品条目区引用的遗物：已删除遗物会在状态区留下残留记录。
     * 条目区不可读时原样返回。
     */
    private fun filterOwnedRelics(
        plain: ByteArray,
        nameOff: Int,
        relics: List<SaveRelic>,
        gaHandles: List<Long>,
    ): List<SaveRelic> {
        val countOff = nameOff + ENTRY_COUNT_GAP
        if (countOff < 0 || countOff + 4 > plain.size) return relics
        val owned = HashSet<Long>()
        var readable = false
        for (slot in 0 until ENTRY_SLOT_COUNT) {
            val pos = countOff + 4 + slot * ENTRY_RECORD_LEN
            if (pos + ENTRY_RECORD_LEN > plain.size) break
            readable = true
            val ga = readUInt32(plain, pos)
            if (ga and 0xF0000000L == 0xC0000000L) owned += ga
        }
        if (!readable) return relics
        val kept = ArrayList<SaveRelic>(relics.size)
        relics.forEachIndexed { index, relic ->
            if (gaHandles[index] in owned) kept += relic.copy(index = kept.size)
        }
        return kept
    }

    /** 读不出真实名字时的显示名；从 1 开始编号，与界面一致。 */
    fun fallbackName(slot: Int): String = "槽位 ${slot + 1}"

    /** 读一个词条 ID，两种空哨兵（0xFFFFFFFF 与 0）都归一化为 -1。 */
    private fun affixAt(plain: ByteArray, off: Int): Long {
        val value = readUInt32(plain, off)
        return if (value == 0xFFFFFFFFL || value == 0L) -1L else value
    }

    /** UTF-16LE 角色名（至多 16 单元，NUL 结尾）；区域不可读或为空时返回 null。允许截断。 */
    private fun readName(plain: ByteArray, off: Int): String? {
        if (off < 0 || off + 2 > plain.size) return null
        var units = 0
        while (units < NAME_MAX_UNITS) {
            val p = off + 2 * units
            if (p + 2 > plain.size) break
            if (plain[p].toInt() == 0 && plain[p + 1].toInt() == 0) break
            units++
        }
        if (units == 0) return null
        return String(plain, off, units * 2, Charsets.UTF_16LE)
    }

    internal fun readUInt32(bytes: ByteArray, offset: Int): Long =
        (bytes[offset].toLong() and 0xFF) or
            ((bytes[offset + 1].toLong() and 0xFF) shl 8) or
            ((bytes[offset + 2].toLong() and 0xFF) shl 16) or
            ((bytes[offset + 3].toLong() and 0xFF) shl 24)

    private fun readInt32(bytes: ByteArray, offset: Int): Int = readUInt32(bytes, offset).toInt()

    private fun ByteArray.regionEquals(offset: Int, other: ByteArray): Boolean {
        if (offset < 0 || offset + other.size > size) return false
        for (i in other.indices) if (this[offset + i] != other[i]) return false
        return true
    }

    private fun ByteArray.indexOf(needle: ByteArray, from: Int): Int {
        var i = from
        while (i + needle.size <= size) {
            if (regionEquals(i, needle)) return i
            i++
        }
        return -1
    }
}

/**
 * 从 Storage Access Framework 读到的原始输入的防御：大小上限、空文件、文件名回显。
 * 与 Windows 端 `export.go` / `parsedata.go` 的同名防御一致（手机上没有拖拽，文件名占位改为「所选存档」）。
 */
object SaveFileInput {
    /** 允许读取的存档大小上限；正常存档只有几十 MB。 */
    const val MAX_SAVE_BYTES: Int = 96 shl 20

    const val EMPTY_INPUT = "没有读到文件内容"
    val TOO_LARGE: String = "文件过大：超过 ${MAX_SAVE_BYTES shr 20} MB 的上限"

    /** 文件名回显：去掉可能带的路径（同时认 / 与 \），拿不到名字时给占位。 */
    fun displayFileName(name: String?): String {
        var trimmed = name.orEmpty().trim()
        val cut = trimmed.lastIndexOfAny(charArrayOf('/', '\\'))
        if (cut >= 0) trimmed = trimmed.substring(cut + 1)
        trimmed = trimmed.trim()
        return if (trimmed.isEmpty() || trimmed == "." || trimmed == "..") "所选存档" else trimmed
    }

    /** 读完输入流，超过 [limit] 字节或读到空内容时抛 [SaveFileException]；不会先把超大文件整个读进内存。 */
    fun readLimited(input: InputStream, limit: Int = MAX_SAVE_BYTES): ByteArray {
        val buffer = java.io.ByteArrayOutputStream()
        val chunk = ByteArray(64 * 1024)
        var total = 0L
        while (true) {
            val read = input.read(chunk)
            if (read < 0) break
            total += read
            if (total > limit) throw SaveFileException(TOO_LARGE)
            buffer.write(chunk, 0, read)
        }
        if (total == 0L) throw SaveFileException(EMPTY_INPUT)
        return buffer.toByteArray()
    }

    /** 已知大小时先挡一道，免得打开超大文件。 */
    fun checkDeclaredSize(size: Long?) {
        if (size != null && size > MAX_SAVE_BYTES) throw SaveFileException(TOO_LARGE)
    }
}
