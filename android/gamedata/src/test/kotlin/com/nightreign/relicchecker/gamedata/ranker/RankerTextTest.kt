package com.nightreign.relicchecker.gamedata.ranker

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

// 文案常量表与数值格式化（windows/tests/ranker.test.mjs 的「TEXT」「格式化」「fmtFlat」各节，
// ranker_crosscheck.test.mjs 的「两端逐字一致：文案常量表」）。
class RankerTextTest {
    private companion object {
        /** 类型开关三档那一版新增的键（前缀）。 */
        val MEANS_KIND_ADDED = listOf("meansKind.", "meansCard.", "meansSearch.", "meansSpellFlatNote")

        /** 那一版改值的两句的旧值（Windows ranker_crosscheck.test.mjs 的 MEANS_KIND_RESTORE）。 */
        val MEANS_KIND_RESTORE = mapOf(
            "pageSubtitle" to "选一个战技／法术，再自己组一套局内配置：武器词条、遗物、护符与其它增益，看总增伤",
            "otherInnateNoWeapon" to "法术没有出手武器，这里只有需手动勾选的固有效果",
        )
    }

    @Test
    fun `text table is the same table as both desktop ends - 346 entries, digest 446c874b`() {
        // skills schemaVersion 3 多了武器来源标记 weaponSource.*（332 → 336 条，854da404 → 07a69c5e）；
        // buffs v6 修订的道具等级再多 goodsLevel.*（336 → 339 条，07a69c5e → 41e2ae25）；
        // 输出手段类型开关拆成三档（战技 / 魔法 / 祷告）再多七个键、改两句「法术」（339 → 346 条，41e2ae25 → 446c874b）。
        assertEquals(346, RankerText.table.size)
        assertEquals("446c874b", RankerCrossCheck.textTableDigest(), "文案常量表摘要（两端 TEXT_TABLE_DIGEST 同一个值）")
        assertEquals(RankerText.table.keys.sorted(), RankerText.table.keys.toList(), "按点号路径排序存放")
        RankerText.table.forEach { (key, value) -> assertTrue(value.isNotEmpty(), "$key 应是非空文案") }
        // 任何一处改动都会让摘要分叉。
        val tampered = RankerText.table + ("reasonNeutral" to RankerText.t("reasonNeutral") + "。")
        assertFalse(RankerCrossCheck.textTableDigest(tampered) == "446c874b")
        // 这一版只多了七个类型开关的键、改了 pageSubtitle / otherInnateNoWeapon 两句：去掉新键、换回旧值回到上一版
        // （其余文案一字未动）；再去掉 goodsLevel.* 回到 v3 那一版，再去掉 weaponSource.* 回到 v2 时的那张表。
        val beforeMeansKind = RankerText.table.filterKeys { key -> MEANS_KIND_ADDED.none { key.startsWith(it) } } + MEANS_KIND_RESTORE
        assertEquals(339, beforeMeansKind.size)
        assertEquals("41e2ae25", RankerCrossCheck.textTableDigest(beforeMeansKind))
        val beforeGoodsLevel = beforeMeansKind.filterKeys { !it.startsWith("goodsLevel.") }
        assertEquals(336, beforeGoodsLevel.size)
        assertEquals("07a69c5e", RankerCrossCheck.textTableDigest(beforeGoodsLevel))
        assertEquals("854da404", RankerCrossCheck.textTableDigest(beforeGoodsLevel.filterKeys { !it.startsWith("weaponSource.") }))
    }

    @Test
    fun `means kind texts are word for word the same as the desktop TEXT meansKind`() {
        // 类型开关三档（游戏里魔法与祷告是两类）、卡片副标题、检索框、空列表与选中魔法／祷告时的标记，三端同名同值。
        assertEquals(
            mapOf(
                "meansCard.subtitle" to "搜索战技、魔法或祷告（中文／英文名都可）；战技再选一把武器",
                "meansKind.incantation" to "祷告",
                "meansKind.skill" to "战技",
                "meansKind.sorcery" to "魔法",
                "meansSearch.empty" to "没有匹配的输出手段",
                "meansSearch.placeholder" to "搜索战技 / 魔法 / 祷告名称",
                "meansSpellFlatNote" to "魔法／祷告的段只用固定值",
            ),
            RankerText.table.filterKeys { key -> MEANS_KIND_ADDED.any { key.startsWith(it) } },
        )
        assertEquals("选一个战技、魔法或祷告，再自己组一套局内配置：武器词条、遗物、护符与其它增益，看总增伤", RankerText.t("pageSubtitle"))
        assertEquals("魔法与祷告没有出手武器，这里只有需手动勾选的固有效果", RankerText.t("otherInnateNoWeapon"))

        // 三档：展示顺序战技 → 魔法 → 祷告，默认战技；与 OutputClass 一一对应、键同名。
        assertEquals(listOf("skill", "sorcery", "incantation"), MeansKind.entries.map { it.key })
        assertEquals(listOf("战技", "魔法", "祷告"), MeansKind.entries.map { it.titleZh })
        assertEquals(MeansKind.SKILL, MeansKind.DEFAULT)
        MeansKind.entries.forEach { kind ->
            assertEquals(kind.key, kind.outputClass.key)
            assertEquals(kind, MeansKind.of(kind.outputClass))
            assertEquals(kind, MeansKind.fromKey(kind.key))
            assertEquals(kind.outputClass.titleZh, kind.titleZh, "与 outputClass.* 同值")
        }
        // 认不出的档位（含旧的二档取值 spell）回落到战技；没有选中的输出手段也是战技。
        assertEquals(MeansKind.SKILL, MeansKind.fromKey("spell"))
        assertEquals(MeansKind.SKILL, MeansKind.fromKey(null))
        assertEquals(MeansKind.SKILL, MeansKind.of(null as SkillOutput?))
        // 开关与标记上不再出现「法术」。
        MeansKind.entries.forEach { assertFalse("法术" in it.titleZh) }
        assertFalse(RankerText.table.filterKeys { key -> MEANS_KIND_ADDED.any { key.startsWith(it) } }.values.any { "法术" in it })
        // 法术的类别标记缺 kindZh 时按类别补上同一档的文案。
        assertEquals("魔法", SpellEntry(kind = "sorcery").kindLabelZh)
        assertEquals("祷告", SpellEntry(kind = "incantation").kindLabelZh)
        assertEquals("祷告", SpellEntry(kind = "incantation", kindZh = "祷告").kindLabelZh)
    }

    @Test
    fun `goods level texts are word for word the same as the desktop TEXT goodsLevel`() {
        assertEquals(
            mapOf(
                "goodsLevel.hint" to "学者的能力「携物知识」把道具提升到这一级后才有这条效果；其它角色只有 1 级。",
                "goodsLevel.note" to "道具的 2／3 级效果来自学者的能力「携物知识」，未升级的道具只有 1 级效果。",
                "goodsLevel.tag" to "携物知识 {0} 级",
            ),
            RankerText.table.filterKeys { it.startsWith("goodsLevel.") },
        )
        // 标记只给 2／3 级；1 级、缺省（0）与负数一律为空串。
        assertEquals("携物知识 2 级", LoadoutText.goodsLevelTag(2))
        assertEquals("携物知识 3 级", LoadoutText.goodsLevelTag(3))
        listOf(1, 0, -1).forEach { assertEquals("", LoadoutText.goodsLevelTag(it), "$it 级不标") }
        assertEquals("", LoadoutText.goodsLevelTag(null as BuffRankerEntry?))
    }

    @Test
    fun `weapon source texts are word for word the same as the desktop TEXT weaponSource`() {
        assertEquals(
            mapOf(
                "weaponSource.fixed" to "固定战技",
                "weaponSource.note" to "武器列表含固定带这个战技的武器与局内战技池能抽到它的武器；动作套按这一把武器实解。",
                "weaponSource.pool" to "局内可抽到",
                "weaponSource.poolHint" to "局内掉落的这把武器有机会抽到这个战技（按战技池权重）",
            ),
            RankerText.table.filterKeys { it.startsWith("weaponSource.") },
        )
        WeaponSourceKind.entries.forEach { assertEquals(RankerText.t(it.textKey), it.title) }
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
