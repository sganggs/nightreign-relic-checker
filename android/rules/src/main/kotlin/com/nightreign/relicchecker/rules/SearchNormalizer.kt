package com.nightreign.relicchecker.rules

import java.text.Normalizer
import java.util.Locale

// Java 正则的 \p{M} 按码点匹配，增补平面的组合符也能剥离，
// 与 core.js 的 /\p{M}/gu 等价。
private val COMBINING_MARKS = "\\p{M}+".toRegex()

fun String.foldedForSearch(): String = Normalizer.normalize(this, Normalizer.Form.NFKD)
    .replace(COMBINING_MARKS, "")
    .replace(" ", "")
    .replace("，", ",")
    .replace("＋", "+")
    .lowercase(Locale.ROOT)

fun Affix.matchesSearch(query: String): Boolean {
    val needle = query.foldedForSearch()
    return needle.isEmpty() || searchableText.contains(needle)
}
