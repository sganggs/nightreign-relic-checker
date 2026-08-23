package com.nightreign.relicchecker.catalog

import com.nightreign.relicchecker.rules.Affix
import kotlinx.serialization.SerializationException
import kotlinx.serialization.json.Json

object CatalogLoader {
    const val ASSET_FILE_NAME = "nightreign-affixes-v1.03.4.json"

    private val json = Json {
        ignoreUnknownKeys = true
        isLenient = false
    }

    fun parse(text: String): AffixCatalog {
        val dto = try {
            json.decodeFromString<AffixCatalogDto>(text)
        } catch (error: SerializationException) {
            throw CatalogFormatException("无法读取词条库文件", error)
        }

        if (dto.schemaVersion != 1) {
            throw CatalogFormatException("不支持的词条库版本：${dto.schemaVersion}")
        }

        val duplicateIds = dto.affixes.groupingBy(AffixDto::effectId)
            .eachCount()
            .filterValues { it > 1 }
            .keys
            .sorted()
        if (duplicateIds.isNotEmpty()) {
            throw CatalogFormatException("词条库包含重复 ID：${duplicateIds.joinToString()}")
        }

        // 与桌面端一致：非诅咒词条不足三条的词条库在加载期拒绝
        if (dto.affixes.count { !it.isCurse } < 3) {
            throw CatalogFormatException("词条库中的有效正面词条不足三个")
        }

        return AffixCatalog(
            schemaVersion = dto.schemaVersion,
            gameVersion = dto.gameVersion,
            dataVersion = dto.dataVersion,
            generatedAt = dto.generatedAt,
            sources = dto.sources.map { source ->
                CatalogSource(
                    name = source.name,
                    url = source.url,
                    revision = source.revision,
                    license = source.license,
                )
            },
            affixes = dto.affixes.map { affix ->
                Affix(
                    effectId = affix.effectId,
                    name = affix.name,
                    aliases = affix.aliases,
                    category = affix.category,
                    explanation = affix.explanation,
                    superposability = affix.superposability,
                    compatibilityId = affix.compatibilityId,
                    sortId = affix.sortId,
                    poolIds = affix.poolIds,
                    isCurse = affix.isCurse,
                    requiresCurse = affix.requiresCurse,
                    popularity = affix.popularity,
                    source = affix.source,
                )
            },
        )
    }
}
