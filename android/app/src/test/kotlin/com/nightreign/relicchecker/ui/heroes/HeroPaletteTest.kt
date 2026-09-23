package com.nightreign.relicchecker.ui.heroes

import com.nightreign.relicchecker.gamedata.heroes.HeroDeltaTone
import com.nightreign.relicchecker.gamedata.heroes.HeroModifierSource
import com.nightreign.relicchecker.ui.theme.NightColors
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Test

class HeroPaletteTest {
    @Test
    fun sourceTagsUseThreeDistinctColorsLikeTheDesktopApps() {
        // 锚点绿 / 推算琥珀 / 沿用蓝：「词条沿用 12 级锚点」不能和「词条锚点」同色（桌面端曾经踩过）
        assertEquals(NightColors.Green, HeroPalette.source(HeroModifierSource.ANCHOR))
        assertEquals(NightColors.Amber, HeroPalette.source(HeroModifierSource.INFERRED))
        assertEquals(HeroPalette.SourceBlue, HeroPalette.source(HeroModifierSource.CARRIED))
        assertEquals(3, HeroModifierSource.entries.map(HeroPalette::source).toSet().size)
    }

    @Test
    fun deltaTonesAndRelicColorsAreDistinct() {
        assertEquals(NightColors.Green, HeroPalette.tone(HeroDeltaTone.UP))
        assertEquals(NightColors.Red, HeroPalette.tone(HeroDeltaTone.DOWN))
        assertEquals(NightColors.TextSecondary, HeroPalette.tone(HeroDeltaTone.FLAT))
        assertEquals(5, (0..4).map(HeroPalette::relic).toSet().size)
        assertNotEquals(HeroPalette.relic(1), HeroPalette.SourceBlue)
        assertEquals(NightColors.TextSecondary, HeroPalette.relic(-1))
    }
}
