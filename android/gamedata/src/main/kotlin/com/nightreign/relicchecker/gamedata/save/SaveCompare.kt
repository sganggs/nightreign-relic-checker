package com.nightreign.relicchecker.gamedata.save

import com.nightreign.relicchecker.rules.foldedForSearch

// 两份存档按角色槽位对比遗物多重集：移植 macOS 端 RelicCore/SaveCompare.swift
// （与 Windows 端 renderer/savediff.js 同一口径）。

/**
 * 遗物身份：itemId + 三条正面词条 + 三条诅咒，都按存档里的顺序（不含存档内序号 index）。
 *
 * 词条顺序会影响合法性判定（审计器会报「保存顺序错误」），换序后的遗物可能一件合法一件非法，
 * 所以换序算不同的遗物；行内的正负配对同样保留。
 */
data class SaveRelicIdentity(val itemId: Int, val rows: List<Row>) : Comparable<SaveRelicIdentity> {
    /** 一行：正面词条与同一行的负面词条（空为 -1）。 */
    data class Row(val effect: Long, val curse: Long) : Comparable<Row> {
        override fun compareTo(other: Row): Int =
            if (effect != other.effect) effect.compareTo(other.effect) else curse.compareTo(other.curse)
    }

    /** 稳定的字符串键，例如 `202|1:-1|2:-1|3:-1`。 */
    val key: String get() = (listOf(itemId.toString()) + rows.map { "${it.effect}:${it.curse}" }).joinToString("|")

    override fun compareTo(other: SaveRelicIdentity): Int {
        if (itemId != other.itemId) return itemId.compareTo(other.itemId)
        for (index in rows.indices) {
            val left = rows[index]
            val right = other.rows.getOrNull(index) ?: return 1
            if (left != right) return left.compareTo(right)
        }
        return 0
    }

    companion object {
        fun of(relic: SaveRelic): SaveRelicIdentity {
            val effects = normalizedTriple(relic.effects)
            val curses = normalizedTriple(relic.curses)
            return SaveRelicIdentity(relic.itemId, List(3) { Row(effects[it], curses[it]) })
        }
    }
}

/** 对比结果里的一项：某个身份的遗物多出 / 少掉了几件。 */
class SaveCompareEntry(
    val identity: SaveRelicIdentity,
    /** 代表件（带审计结论，用于展示合法性状态）。 */
    val relic: AuditedRelic,
    /** 数量差（恒 ≥ 1）。 */
    val count: Int,
) {
    val id: String get() = identity.key
}

/** 一个角色槽位的对比结果。 */
class SaveCompareCharacter(
    val slot: Int,
    /** 当前存档里的角色名；该槽位在当前存档中不存在时为 null。 */
    val baseName: String?,
    /** 对比存档里的角色名；该槽位在对比存档中不存在时为 null。 */
    val otherName: String?,
    val baseParseError: String? = null,
    val otherParseError: String? = null,
    val baseTotal: Int,
    val otherTotal: Int,
    /** 对比存档多出的遗物；任一侧解析失败时恒为空（读不出来不等于一件不剩）。 */
    val added: List<SaveCompareEntry>,
    /** 对比存档少掉的遗物；任一侧解析失败时恒为空。 */
    val removed: List<SaveCompareEntry>,
) {
    val addedCount: Int get() = added.sumOf { it.count }
    val removedCount: Int get() = removed.sumOf { it.count }

    /** 只看遗物多重集：两侧完全相同。 */
    val isIdentical: Boolean get() = added.isEmpty() && removed.isEmpty()

    /** 至少有一侧解析失败：只提示、不产出增减。 */
    val hasParseError: Boolean get() = !baseParseError.isNullOrBlank() || !otherParseError.isNullOrBlank()

    /** 算不算「有差异的角色」（解析失败不算，它只是读不出来）。 */
    val isChanged: Boolean get() = !hasParseError && !isIdentical

    /** 有任何值得展示的差异（遗物增减 / 角色名变化 / 解析失败）。 */
    val hasAnyDifference: Boolean get() = !isIdentical || presenceNote != null || hasParseError

    val displayName: String
        get() {
            val name = baseName ?: otherName ?: ""
            return if (name.isEmpty()) "槽位 ${slot + 1}" else "槽位 ${slot + 1} · $name"
        }

    /** 只在一侧存在，或两侧角色名不同时的提示。 */
    val presenceNote: String?
        get() = when {
            baseName == null -> "该槽位只在对比存档中存在"
            otherName == null -> "该槽位只在当前存档中存在"
            baseName != otherName -> "两份存档的同一槽位角色名不同：$baseName → $otherName"
            else -> null
        }

    /** 遗物没有任何增减时的那一句话；读不出遗物的槽位不给。 */
    val identicalNote: String?
        get() = if (isIdentical && !hasParseError) "该角色的遗物与当前存档一致。" else null

    /** 解析失败提示。 */
    val parseNote: String?
        get() {
            val sides = listOfNotNull(
                baseParseError?.takeIf { it.isNotBlank() }?.let { "当前存档：$it" },
                otherParseError?.takeIf { it.isNotBlank() }?.let { "对比存档：$it" },
            )
            return if (sides.isEmpty()) null else "该槽位解析失败，无法对比（" + sides.joinToString("；") + "）"
        }
}

/** 差异方向筛选（与桌面端「全部 / 只看新增 / 只看减少」一致）。 */
enum class SaveCompareDirection(val title: String) {
    ALL("全部"),
    ADDED("只看新增"),
    REMOVED("只看减少"),
}

/** 一个槽位 + 它在当前筛选条件下的增减条目（展示用）。 */
class SaveCompareBlock(
    val character: SaveCompareCharacter,
    val added: List<SaveCompareEntry>,
    val removed: List<SaveCompareEntry>,
)

/** 两份存档的对比结果。 */
class SaveCompareResult(
    val baseFileName: String,
    val otherFileName: String,
    /** 两份存档槽位的并集，按槽位升序。 */
    val characters: List<SaveCompareCharacter>,
) {
    val totalAdded: Int get() = characters.sumOf { it.addedCount }
    val totalRemoved: Int get() = characters.sumOf { it.removedCount }
    val totalBase: Int get() = characters.sumOf { it.baseTotal }
    val totalOther: Int get() = characters.sumOf { it.otherTotal }
    val changedCharacters: Int get() = characters.count { it.isChanged }
    val unreliableCharacters: List<SaveCompareCharacter> get() = characters.filter { it.hasParseError }
    val hasUnreliableSlots: Boolean get() = characters.any { it.hasParseError }
    val hasPresenceNotes: Boolean get() = characters.any { it.presenceNote != null }

    /** 除遗物增减外，改名与解析失败也算差异（否则面板会误称「完全一致」）。 */
    val hasDifferences: Boolean
        get() = totalAdded > 0 || totalRemoved > 0 || hasPresenceNotes || hasUnreliableSlots

    /** 汇总文案：「新增 N 件 · 减少 M 件」。 */
    val summaryText: String get() = "新增 $totalAdded 件 · 减少 $totalRemoved 件"

    /** 差异列表一条都没画出来时的那一句话（只有这一个出口）。 */
    val emptyListNote: String get() = if (hasDifferences) "没有符合筛选条件的差异" else "两份存档的遗物完全一致"

    /**
     * 当前方向与搜索条件下要展示的槽位（与 macOS 端 SaveCompareSection.visibleBlocks 一致）：
     * 没有任何差异的槽位不展示；搜索 / 方向把条目滤空的槽位也不展示，但改名与解析失败这两类
     * 只有提示、本来就没有条目的槽位要留下。
     */
    fun visibleBlocks(direction: SaveCompareDirection, query: String): List<SaveCompareBlock> {
        val needle = query.foldedForSearch()
        fun filtered(entries: List<SaveCompareEntry>) =
            if (needle.isEmpty()) entries else entries.filter { it.relic.searchText.contains(needle) }
        return characters.mapNotNull { character ->
            if (!character.hasAnyDifference) return@mapNotNull null
            val added = if (direction == SaveCompareDirection.REMOVED) emptyList() else filtered(character.added)
            val removed = if (direction == SaveCompareDirection.ADDED) emptyList() else filtered(character.removed)
            if (!character.hasParseError && !character.isIdentical && added.isEmpty() && removed.isEmpty()) {
                return@mapNotNull null
            }
            SaveCompareBlock(character, added, removed)
        }
    }

    companion object {
        /** 对比说明（与桌面端同一段文案）。 */
        const val FOOTNOTE =
            "对比以「遗物 ID + 三条正面词条 + 三条诅咒」为一件遗物的身份（都按存档里的顺序，" +
                "顺序本身会影响合法性判定），按角色槽位分别统计；任一边解析失败的槽位只提示、不计入增减。" +
                "新增/减少遗物的合法性状态由当前词条库判定，取自该遗物所在存档的整体检查结果。"

        /** 有槽位解析失败时的总提示。 */
        const val UNRELIABLE_NOTE = "有槽位在某一侧解析失败，该槽位读不出遗物；只作提示，不计入上面的增减。"
    }
}

object SaveComparator {
    /**
     * [base] 是当前载入的存档，[other] 是选来对比的另一份：[other] 相对 [base] 多出的记为「新增」，
     * 少掉的记为「减少」。任一侧槽位解析失败时不产出增减。
     */
    fun compare(base: AuditedSave, other: AuditedSave): SaveCompareResult {
        val baseBySlot = LinkedHashMap<Int, AuditedCharacter>().also { map -> base.characters.forEach { map.putIfAbsent(it.slot, it) } }
        val otherBySlot = LinkedHashMap<Int, AuditedCharacter>().also { map -> other.characters.forEach { map.putIfAbsent(it.slot, it) } }
        val slots = (baseBySlot.keys + otherBySlot.keys).toSortedSet()

        val characters = slots.map { slot ->
            val baseCharacter = baseBySlot[slot]
            val otherCharacter = otherBySlot[slot]
            val baseRelics = baseCharacter?.relics.orEmpty()
            val otherRelics = otherCharacter?.relics.orEmpty()
            val added = ArrayList<SaveCompareEntry>()
            val removed = ArrayList<SaveCompareEntry>()
            val unreadable = baseCharacter?.hasParseError == true || otherCharacter?.hasParseError == true
            if (!unreadable) {
                val baseGroups = baseRelics.groupBy { SaveRelicIdentity.of(it.relic) }
                val otherGroups = otherRelics.groupBy { SaveRelicIdentity.of(it.relic) }
                for (identity in (baseGroups.keys + otherGroups.keys).toSortedSet()) {
                    val baseItems = baseGroups[identity].orEmpty()
                    val otherItems = otherGroups[identity].orEmpty()
                    if (otherItems.size > baseItems.size) {
                        added += SaveCompareEntry(identity, otherItems.first(), otherItems.size - baseItems.size)
                    } else if (baseItems.size > otherItems.size) {
                        removed += SaveCompareEntry(identity, baseItems.first(), baseItems.size - otherItems.size)
                    }
                }
            }
            SaveCompareCharacter(
                slot = slot,
                baseName = baseCharacter?.name,
                otherName = otherCharacter?.name,
                baseParseError = baseCharacter?.parseError,
                otherParseError = otherCharacter?.parseError,
                baseTotal = baseRelics.size,
                otherTotal = otherRelics.size,
                added = added,
                removed = removed,
            )
        }
        return SaveCompareResult(base.fileName, other.fileName, characters)
    }
}
