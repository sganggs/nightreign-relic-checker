package com.nightreign.relicchecker.gamedata.ranker

import com.nightreign.relicchecker.gamedata.GameDataJson
import com.nightreign.relicchecker.rules.CheckMode
import kotlinx.serialization.Serializable
import kotlinx.serialization.SerializationException

// 「增伤排名」配置页：用户自己组的一套局内配置（不可变值，页面状态、推荐填满与测试共用）。
//
// 形状与 Windows 端 ranker.js 的 emptyConfig / cloneConfig 一一对应（macOS 端 BuffLoadout 同义）：
//   · 局内武器词条：AttachEffect id → 份数（占几个武器词条槽；计算一律按 id 升序展开）；
//   · 遗物卡：始终 6 张（常规只用前 3 张，深夜另用后 3 张深夜遗物格），每张 空 / 固定遗物（按 relicIds 键）/
//     自组（三行词条，深夜遗物每行可配一条诅咒）；
//   · 护符：按格位（2 格，空格为 null）；
//   · 其它增益：勾选的行键（spEffectId；累积阶梯＝第 1 层的 spEffectId），勾选即确认；
//   · 当前武器固有里被用户排除的、勾了「条件成立」的、叠层层数、累积阶梯选中的层、多档词条选中的档。
// 本类实现 [EntrySelections]，直接交给 BuffRankerIndex.evaluate。修改一律返回新实例（copy / with…）。

/** 出击模式：常规 / 深夜（slotRules.modes）。 */
@Serializable
enum class RunMode(val key: String) {
    NORMAL("normal"),
    DEEP("deep"),
    ;

    /** 「常规」「深夜」。 */
    val titleZh: String get() = RankerText.t("runMode.$key")

    companion object {
        fun fromKey(key: String?): RunMode = if (key == "deep") DEEP else NORMAL
    }
}

/** 遗物格的口径：普通遗物格走「普通 1.03」，深夜遗物格走「深夜正面」＋诅咒配对（Windows relicKindForCard）。 */
enum class RelicKind(val key: String, val checkMode: CheckMode) {
    NORMAL("normal", CheckMode.CURRENT_NORMAL),
    DEEP("deep", CheckMode.DEEP_POSITIVE),
}

/** 遗物卡的来源：空 / 官方固定词条遗物 / 自组（文案 relicType.*）。 */
@Serializable
enum class RelicCardType(val key: String) {
    EMPTY("empty"),
    FIXED("fixed"),
    CUSTOM("custom"),
    ;

    val titleZh: String get() = RankerText.t("relicType.$key")
}

/**
 * 一张遗物卡。固定遗物按 [fixedKey]（BuffFixedRelic.key，relicIds 用「-」连接）；自组按三行 [affixIds] 与
 * 每行配的诅咒 [curseIds]（深夜遗物格才有诅咒；普通遗物格带诅咒会被判「多余的负面词条」）。
 */
@Serializable
data class RelicCard(
    val type: RelicCardType = RelicCardType.EMPTY,
    val fixedKey: String? = null,
    val affixIds: List<Int?> = EMPTY_ROWS,
    val curseIds: List<Int?> = EMPTY_ROWS,
) {
    fun affixAt(row: Int): Int? = affixIds.getOrNull(row)

    fun curseAt(row: Int): Int? = curseIds.getOrNull(row)

    /**
     * 这一格算不算「用上了」（Windows relicCardFilled、macOS !isEmpty）：固定遗物要选中一件，
     * 自组要至少有一条词条或诅咒。「按推荐填满」只填没用上的格。
     */
    val isFilled: Boolean
        get() = when (type) {
            RelicCardType.FIXED -> fixedKey != null
            RelicCardType.CUSTOM -> (0 until ROWS).any { affixAt(it) != null || curseAt(it) != null }
            RelicCardType.EMPTY -> false
        }

    /** 自组里选了的词条（按行序，跳过空行）。 */
    val customAffixIds: List<Int> get() = (0 until ROWS).mapNotNull { affixAt(it) }

    /** 改一行（行号越界时原样返回）；类型改成自组，固定遗物键清掉。 */
    fun withRow(row: Int, affixId: Int?, curseId: Int?): RelicCard {
        if (row !in 0 until ROWS) return this
        return RelicCard(
            type = RelicCardType.CUSTOM,
            fixedKey = null,
            affixIds = padded(affixIds).toMutableList().also { it[row] = affixId },
            curseIds = padded(curseIds).toMutableList().also { it[row] = curseId },
        )
    }

    /** 只改一行的诅咒。 */
    fun withCurse(row: Int, curseId: Int?): RelicCard = withRow(row, affixAt(row), curseId)

    companion object {
        /** 每件遗物最多 3 条词条（slotRules.relic.affixesPerRelic）。 */
        const val ROWS: Int = 3

        private val EMPTY_ROWS: List<Int?> = listOf(null, null, null)

        val EMPTY: RelicCard = RelicCard()

        fun fixed(key: String): RelicCard = RelicCard(RelicCardType.FIXED, key)

        fun custom(affixIds: List<Int?> = emptyList(), curseIds: List<Int?> = emptyList()): RelicCard =
            RelicCard(RelicCardType.CUSTOM, null, padded(affixIds), padded(curseIds))

        internal fun padded(ids: List<Int?>): List<Int?> = List(ROWS) { ids.getOrNull(it) }
    }
}

/**
 * 一套配置（Windows emptyConfig 的字段一一对应）。默认值＝空配置：常规、6 张空遗物卡、2 个空护符格。
 *
 * 计算入口在 [LoadoutEvaluator]（`index.evaluator(output).evaluate(config)`）；按武器词条上限步进、切模式、
 * 勾选其它增益这类要查索引的修改在 [LoadoutIndex] / [LoadoutEvaluator] 上。
 */
@Serializable
data class LoadoutConfig(
    val runMode: RunMode = RunMode.NORMAL,
    /** AttachEffect id → 份数（> 0；0 份的键会被移除）。 */
    val weaponAffixes: Map<Int, Int> = emptyMap(),
    /** 遗物卡（按格位；普通 3 张在前，深夜 3 张在后）。 */
    val relics: List<RelicCard> = List(DEFAULT_RELIC_CARDS) { RelicCard.EMPTY },
    /** 护符（EquipParamAccessory id，按格位；空格为 null）。 */
    val accessories: List<Int?> = List(DEFAULT_ACCESSORY_SLOTS) { null },
    /** 其它增益栏勾选的行键（勾选即确认）。 */
    val others: Set<Int> = emptySet(),
    /** 当前武器固有里被用户排除的 spEffectId。 */
    val innateOff: Set<Int> = emptySet(),
    /** 勾了「条件成立」的 spEffectId。 */
    val ticks: Set<Int> = emptySet(),
    /** 叠层层数（spEffectId → 层数；缺省 0＝不计入）。 */
    val stackCounts: Map<Int, Int> = emptyMap(),
    /** 累积阶梯（组 id＝第 1 层 spEffectId）→ 选中那一层的 spEffectId（缺省＝不计）。 */
    val tiers: Map<Int, Int> = emptyMap(),
    /** 多档词条（组键 affix#…）→ 选中那一档的 spEffectId（缺省＝第 1 档）。 */
    val variants: Map<String, Int> = emptyMap(),
) : EntrySelections {
    override fun stacks(spEffectId: Int): Int = maxOf(0, stackCounts[spEffectId] ?: 0)

    override fun ladderChoice(ladderId: Int): Int? = tiers[ladderId]

    override fun variantChoice(groupKey: String): Int? = variants[groupKey]

    override fun isConfirmed(spEffectId: Int): Boolean = spEffectId in ticks

    fun weaponAffixCount(attachEffectId: Int): Int = maxOf(0, weaponAffixes[attachEffectId] ?: 0)

    fun relic(cardIndex: Int): RelicCard = relics.getOrNull(cardIndex) ?: RelicCard.EMPTY

    fun accessory(slot: Int): Int? = accessories.getOrNull(slot)

    /** 换一张遗物卡（格位越界时补空卡）。 */
    fun withRelic(cardIndex: Int, card: RelicCard): LoadoutConfig {
        if (cardIndex < 0) return this
        val list = relics.toMutableList()
        while (list.size <= cardIndex) list += RelicCard.EMPTY
        list[cardIndex] = card
        return copy(relics = list)
    }

    /** 换一个护符格（null＝清空）。 */
    fun withAccessory(slot: Int, id: Int?): LoadoutConfig {
        if (slot < 0) return this
        val list = accessories.toMutableList()
        while (list.size <= slot) list += null
        list[slot] = id
        return copy(accessories = list)
    }

    /** 勾 / 取消「条件成立」。 */
    fun withTick(spEffectId: Int, ticked: Boolean): LoadoutConfig =
        copy(ticks = if (ticked) ticks + spEffectId else ticks - spEffectId)

    /** 累积阶梯选层（null＝不计）。 */
    fun withLadderTier(ladderId: Int, spEffectId: Int?): LoadoutConfig =
        copy(tiers = if (spEffectId == null) tiers - ladderId else tiers + (ladderId to spEffectId))

    /** 多档词条选档（null＝恢复第 1 档）。 */
    fun withVariant(groupKey: String, spEffectId: Int?): LoadoutConfig =
        copy(variants = if (spEffectId == null) variants - groupKey else variants + (groupKey to spEffectId))

    /** 保存用（rememberSaveable 存字符串）：默认值不写出。 */
    fun encode(): String = GameDataJson.lenient.encodeToString(serializer(), this)

    companion object {
        /** 遗物卡张数（深夜 3 普通 + 3 深夜）。常规只用前 slotRules.relic.normal 张。 */
        const val DEFAULT_RELIC_CARDS: Int = 6
        const val DEFAULT_ACCESSORY_SLOTS: Int = 2

        val EMPTY: LoadoutConfig = LoadoutConfig()

        /** [encode] 的逆；读不出（版本变了、被截断）时返回 null，页面退回空配置。 */
        fun decode(text: String?): LoadoutConfig? {
            if (text.isNullOrEmpty()) return null
            return try {
                GameDataJson.lenient.decodeFromString(serializer(), text)
            } catch (_: SerializationException) {
                null
            } catch (_: IllegalArgumentException) {
                null
            }
        }
    }
}
