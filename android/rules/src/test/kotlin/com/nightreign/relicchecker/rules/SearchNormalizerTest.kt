package com.nightreign.relicchecker.rules

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class SearchNormalizerTest {
    @Test
    fun `normalization folds width case accents spaces and punctuation`() {
        assertEquals("cafe,+3", "ＣＡＦÉ ， ＋３".foldedForSearch())
    }

    @Test
    fun `search covers only name category id and aliases`() {
        val affix = Affix(
            effectId = 7_000_000,
            name = "生命力＋１",
            aliases = listOf("生命力+１"),
            category = "能力",
            explanation = "只在说明里的关键字",
            sortId = 100,
        )

        assertTrue(affix.matchesSearch("生命 力+1"))
        assertTrue(affix.matchesSearch("能力"))
        assertTrue(affix.matchesSearch("7000000"))
        assertFalse(affix.matchesSearch("关键字"))
    }
}
