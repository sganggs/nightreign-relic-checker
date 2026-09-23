package com.nightreign.relicchecker.ui.bosses

import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * 工具条排法按页面尺寸选（BossToolbarLayout）。页面尺寸 = 屏幕 − 状态栏 − 底栏 64dp − 手势条，
 * 宽度再受 720dp 内容列限宽。几种典型设备都写成断言，免得阈值被改动后横屏又退回「列表 0 高度」。
 */
class BossToolbarLayoutTest {
    /** 屏幕尺寸 → 页面尺寸（状态栏 24、手势条 24、底栏 64；宽度限 720）。 */
    private fun page(screenWidth: Int, screenHeight: Int): Pair<Dp, Dp> =
        (screenHeight - 24 - 24 - 64).dp to minOf(screenWidth, 720).dp

    private fun layoutFor(screenWidth: Int, screenHeight: Int): BossToolbarLayout {
        val (height, width) = page(screenWidth, screenHeight)
        return BossToolbarLayout.of(pageHeight = height, pageWidth = width)
    }

    @Test
    fun portraitPhonesKeepTheFullStickyToolbar() {
        assertEquals(BossToolbarLayout.FULL, layoutFor(411, 914)) // Medium Phone 竖屏
        assertEquals(BossToolbarLayout.FULL, layoutFor(393, 851)) // Pixel 5
        assertEquals(BossToolbarLayout.FULL, layoutFor(360, 740))
        assertEquals(BossToolbarLayout.FULL, layoutFor(1280, 800)) // 平板横屏：页面 688dp 高
        assertFalse(BossToolbarLayout.FULL.compact)
    }

    @Test
    fun landscapePhonesPutSearchAndSettingsOnOneRow() {
        // Medium Phone 横屏：页面 914×411 → 299dp 高、720dp 宽
        assertEquals(BossToolbarLayout.COMPACT_ONE_ROW, layoutFor(914, 411))
        assertEquals(BossToolbarLayout.COMPACT_ONE_ROW, layoutFor(640, 360))
        assertEquals(BossToolbarLayout.COMPACT_ONE_ROW, layoutFor(851, 393))
        assertTrue(BossToolbarLayout.COMPACT_ONE_ROW.compact)
    }

    @Test
    fun shortNarrowWindowsUseTwoStickyRows() {
        assertEquals(BossToolbarLayout.COMPACT_TWO_ROWS, layoutFor(360, 640)) // 小屏手机竖屏：页面 528dp 高
        assertEquals(BossToolbarLayout.COMPACT_TWO_ROWS, layoutFor(411, 450)) // 分屏上半
        assertTrue(BossToolbarLayout.COMPACT_TWO_ROWS.compact)
    }

    @Test
    fun thresholdsAreInclusiveAtTheBoundary() {
        assertEquals(BossToolbarLayout.FULL, BossToolbarLayout.of(600.dp, 360.dp))
        assertEquals(BossToolbarLayout.COMPACT_TWO_ROWS, BossToolbarLayout.of(599.dp, 559.dp))
        assertEquals(BossToolbarLayout.COMPACT_ONE_ROW, BossToolbarLayout.of(599.dp, 560.dp))
        // 约束无上限（测量时高度为 Infinity）按完整排法处理，不误判成紧凑
        assertEquals(BossToolbarLayout.FULL, BossToolbarLayout.of(Dp.Infinity, 400.dp))
    }
}
