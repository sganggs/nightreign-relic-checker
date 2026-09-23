package com.nightreign.relicchecker.gamedata.lookup

import com.nightreign.relicchecker.catalog.CatalogSource
import com.nightreign.relicchecker.gamedata.GameDataJson
import com.nightreign.relicchecker.gamedata.GameDataKey
import kotlinx.serialization.Serializable

// 遗物物品表（nightreign-relics-v1.03.4.json）。结构与 macOS RelicCore/RelicData.swift 的
// RelicCatalog / RelicInfo / ExtraAffix 一一对应；DTO 只声明反查要用的字段，
// sources 里的 usage 之类说明字段在解码时跳过。

@Serializable
internal data class RelicCatalogDto(
    val relicsSchemaVersion: Int? = null,
    val gameVersion: String = "",
    val dataVersion: String = "",
    val generatedAt: String = "",
    val sources: List<RelicSourceDto> = emptyList(),
    val relics: List<RelicInfoDto> = emptyList(),
    val pools: Map<String, List<Int>> = emptyMap(),
    val extraAffixes: List<ExtraAffixDto> = emptyList(),
)

@Serializable
internal data class RelicSourceDto(
    val name: String = "",
    val url: String = "",
    val revision: String = "",
    val license: String = "",
)

@Serializable
internal data class RelicInfoDto(
    val id: Int = 0,
    val name: String = "",
    val color: Int = -1,
    val deep: Boolean = false,
    val slots: List<Int> = emptyList(),
    val curseSlots: List<Int> = emptyList(),
)

@Serializable
internal data class ExtraAffixDto(
    val effectId: Int = 0,
    val name: String = "",
    val sortId: Int = 0,
    val compatibilityId: Int = -1,
)

/** 物品表里的一件遗物（或一条参数行）。[slots] / [curseSlots] 是槽位池 id，-1 表示没有这个槽。 */
data class RelicInfo(
    val id: Int,
    val name: String,
    val color: Int,
    val deep: Boolean,
    val slots: List<Int>,
    val curseSlots: List<Int>,
)

/** 物品表里出现过、词条库没有收录的效果（多为角色专属词条与各种「庇佑」）。 */
data class ExtraAffix(
    val effectId: Int,
    val name: String,
    val sortId: Int,
    val compatibilityId: Int,
)

/**
 * 遗物物品表。[pools] 的键已从 JSON 的字符串转成池 id；无法转成整数的键与 macOS
 * `AffixLookupIndex` 一样直接跳过。
 */
data class RelicCatalog(
    val relicsSchemaVersion: Int,
    val gameVersion: String,
    val dataVersion: String,
    val generatedAt: String,
    val sources: List<CatalogSource>,
    val relics: List<RelicInfo>,
    val pools: Map<Int, List<Int>>,
    val extraAffixes: List<ExtraAffix>,
)

object RelicCatalogParser {
    /** 解码遗物物品表并校验 relicsSchemaVersion；版本不符或格式错误抛 GameDataFormatException。 */
    fun parse(text: String): RelicCatalog {
        val dto = GameDataJson.decode<RelicCatalogDto>(GameDataKey.RELICS, text)
        GameDataJson.requireVersion(GameDataKey.RELICS, dto.relicsSchemaVersion)
        val pools = LinkedHashMap<Int, List<Int>>(dto.pools.size * 2)
        dto.pools.forEach { (key, members) ->
            key.toIntOrNull()?.let { pools[it] = members }
        }
        return RelicCatalog(
            relicsSchemaVersion = dto.relicsSchemaVersion ?: GameDataKey.RELICS.expectedVersion,
            gameVersion = dto.gameVersion,
            dataVersion = dto.dataVersion,
            generatedAt = dto.generatedAt,
            sources = dto.sources.map { CatalogSource(it.name, it.url, it.revision, it.license) },
            relics = dto.relics.map { RelicInfo(it.id, it.name, it.color, it.deep, it.slots, it.curseSlots) },
            pools = pools,
            extraAffixes = dto.extraAffixes.map { ExtraAffix(it.effectId, it.name, it.sortId, it.compatibilityId) },
        )
    }
}

// MARK: 遗物标签（与 macOS RelicCore/RelicAudit.swift、Windows core.js 同口径）

/** 正常游玩能拿到的遗物 ID 区间（RelicAudit 第 3 条规则）。 */
val OBTAINABLE_RELIC_ID_RANGE: IntRange = 100..2_013_322

/** 作弊器常用 ID 区段（RelicAudit 第 2 条规则）：正常游玩不会获得。 */
val CHEAT_RELIC_ID_RANGE: IntRange = 20_000..30_035

/** 遗物种类判定用的唯一遗物 ID 区段。 */
fun isUniqueRelicId(id: Int): Boolean = id in 1000..2100 || id in 10000..19999

fun relicKindLabel(id: Int, info: RelicInfo?): String = when {
    info?.deep == true -> "深夜遗物"
    isUniqueRelicId(id) -> "唯一遗物"
    id in 100..199 -> "商店遗物（旧版）"
    id in 200..299 -> "商店遗物"
    id in 1_000_000..1_009_999 -> "对局奖励"
    else -> "遗物"
}

fun relicColorLabel(color: Int): String = when (color) {
    0 -> "红"
    1 -> "蓝"
    2 -> "黄"
    3 -> "绿"
    4 -> "白"
    else -> "未知"
}

fun relicDisplayName(id: Int, info: RelicInfo?): String = when {
    info == null -> "未知遗物 #$id"
    info.name.isEmpty() -> "未命名遗物 #$id"
    else -> info.name
}
