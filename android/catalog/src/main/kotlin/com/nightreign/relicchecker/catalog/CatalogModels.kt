package com.nightreign.relicchecker.catalog

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

// 全部字段必填（popularity 允许显式 null），与桌面端强校验口径一致：
// 字段缺失即拒绝加载。
@Serializable
internal data class AffixCatalogDto(
    val schemaVersion: Int,
    val gameVersion: String,
    val dataVersion: String,
    val generatedAt: String,
    val sources: List<CatalogSourceDto>,
    val affixes: List<AffixDto>,
)

@Serializable
internal data class CatalogSourceDto(
    val name: String,
    val url: String,
    val revision: String,
    val license: String,
)

@Serializable
internal data class AffixDto(
    val effectId: Int,
    val name: String,
    val aliases: List<String>,
    val category: String,
    val explanation: String,
    val superposability: String,
    val compatibilityId: Int,
    val sortId: Int,
    val poolIds: List<Int>,
    val isCurse: Boolean,
    val requiresCurse: Boolean,
    val popularity: Int?,
    val source: String,
)

data class CatalogSource(
    val name: String,
    val url: String,
    val revision: String,
    val license: String,
)
