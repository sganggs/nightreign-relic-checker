package com.nightreign.relicchecker.gamedata.ranker

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

// 文案常量表与数值格式化（windows/tests/ranker.test.mjs 的「TEXT」「格式化」「fmtFlat」各节，
// ranker_crosscheck.test.mjs 的「两端逐字一致：文案常量表」）。
class RankerTextTest {
    @Test
    fun `text table is the same table as both desktop ends - 332 entries, digest 854da404`() {
        assertEquals(332, RankerText.table.size)
        assertEquals("854da404", RankerCrossCheck.textTableDigest(), "文案常量表摘要（两端 TEXT_TABLE_DIGEST 同一个值）")
        assertEquals(RankerText.table.keys.sorted(), RankerText.table.keys.toList(), "按点号路径排序存放")
        RankerText.table.forEach { (key, value) -> assertTrue(value.isNotEmpty(), "$key 应是非空文案") }
        // 任何一处改动都会让摘要分叉。
        val tampered = RankerText.table + ("reasonNeutral" to RankerText.t("reasonNeutral") + "。")
        assertFalse(RankerCrossCheck.textTableDigest(tampered) == "854da404")
    }

    @Test
    fun `fnv1a matches the desktop implementation`() {
        assertEquals("811c9dc5", RankerCrossCheck.fnv1a(""))
        assertEquals("e40c292c", RankerCrossCheck.fnv1a("a"))
        assertEquals("bf9cf968", RankerCrossCheck.fnv1a("foobar"))
    }

    @Test
    fun `fmt replaces placeholders by position, missing arguments become empty`() {
        assertEquals("第 2 行：名", RankerText.fmt("第 {0} 行：{1}", 2, "名"))
        assertEquals("aa", RankerText.fmt("{0}{0}", "a"))
        assertEquals("", RankerText.fmt("{1}", "a"), "缺的参数替换成空串")
        assertEquals("{x}", RankerText.fmt("{x}", "a"), "非数字占位原样保留")
        assertEquals("每份 ×1.1", RankerText.fmt("每份 ×{0}", 1.1))
        assertEquals("3 层", RankerText.fmt("{0} 层", 3.0), "整数值的浮点数按 JS 写法不带 .0")
        assertEquals("只作用于右手武器（当前为左手）", RankerText.f("requireHand", "右手", "左手"))
        SummaryColumn.entries.forEach { assertTrue(RankerText.table.containsKey("columns.${it.key}")) }
        listOf("consumable", "spellBuff", "weaponSkill", "weaponInnate", "character", "permanent", "runStack", "other")
            .forEach { assertTrue(RankerText.table.containsKey("otherGroups.$it")) }
        EntryState.entries.forEach { assertTrue(RankerText.table.containsKey("states.${it.key}"), it.key) }
        OutputClass.entries.forEach { assertTrue(RankerText.table.containsKey("outputClass.${it.key}"), it.key) }
        assertEquals("战技", OutputClass.SKILL.titleZh)
        assertEquals("对当前构成无增益", EntryState.NEUTRAL.label)
        assertEquals("局内武器词条", SummaryColumn.WEAPON_AFFIX.titleZh)
        assertEquals("missing.key", RankerText.t("missing.key"), "缺键退回键名")
    }

    @Test
    fun `number formats follow the desktop rounding and wording`() {
        assertEquals("×1.25", BuffFormat.multiplier(1.25))
        assertEquals("×1.250", BuffFormat.multiplierFixed(1.25))
        assertEquals("—", BuffFormat.multiplier(null), "没有构成时倍率显示成「—」")
        assertEquals("+25.0%", BuffFormat.gain(1.25))
        assertEquals("-10.0%", BuffFormat.gain(0.9))
        assertEquals("50.0%", BuffFormat.percent(0.5))
        assertEquals("永久", BuffFormat.duration(-1.0))
        assertEquals("永久", BuffFormat.duration(30.0, permanent = true))
        assertEquals("瞬间", BuffFormat.duration(0.0))
        assertEquals("30 秒", BuffFormat.duration(30.0))
        assertEquals("1.5 秒", BuffFormat.duration(1.5))
        assertEquals("46", BuffFormat.trim(46.0, 1))
        assertEquals("1.0725", BuffFormat.trim(1.0725, 4))
        assertEquals("0.352941176", BuffFormat.fixed(6.0 / 17.0, 9))
        assertEquals("3.550000000", BuffFormat.fixed(3.55, 9))
        assertEquals("-0.0", BuffFormat.fixed(-0.04, 1), "与 JS toFixed 一样保留负号")
        // 攻击力加算按数值带符号，不会出现「+-」。
        assertEquals("-76.9", BuffFormat.flat(-76.86486))
        assertEquals("+12.3", BuffFormat.flat(12.34))
        assertEquals("0", BuffFormat.flat(-0.04))
        assertEquals("+66", BuffFormat.flat(66.0, 0))
        assertTrue(BuffFormat.hasFlat(-12.8))
        assertFalse(BuffFormat.hasFlat(0.01))
        assertFalse(BuffFormat.hasFlat(0.0))
    }
}
