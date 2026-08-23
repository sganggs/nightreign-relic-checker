package com.nightreign.relicchecker.catalog

import com.nightreign.relicchecker.rules.Affix

data class AffixCatalog(
    val schemaVersion: Int,
    val gameVersion: String,
    val dataVersion: String,
    val generatedAt: String,
    val sources: List<CatalogSource>,
    val affixes: List<Affix>,
)

class CatalogFormatException(message: String, cause: Throwable? = null) :
    IllegalArgumentException(message, cause)
