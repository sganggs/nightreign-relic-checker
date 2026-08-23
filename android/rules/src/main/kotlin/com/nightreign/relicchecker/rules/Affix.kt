package com.nightreign.relicchecker.rules

data class Affix(
    val effectId: Int,
    val name: String,
    val aliases: List<String> = emptyList(),
    val category: String = "未分类",
    val explanation: String = "",
    val superposability: String = "未知",
    val compatibilityId: Int = -1,
    val sortId: Int,
    val poolIds: List<Int> = emptyList(),
    val isCurse: Boolean = false,
    val requiresCurse: Boolean = false,
    val popularity: Int? = null,
    val source: String = "",
) {
    val searchableText: String
        get() = (listOf(name, category, effectId.toString()) + aliases)
            .joinToString(" ")
            .foldedForSearch()

    fun isEligible(mode: CheckMode): Boolean {
        if (isCurse) return false
        if (mode == CheckMode.COMPATIBILITY_ONLY) return true
        return poolIds.any(mode.eligiblePoolIds::contains)
    }
}
