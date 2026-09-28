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

        /** skills v4 蓄力开关那一版：新增 chargedToggle.* 四个键，brief.partial 改值（旧值用来回到上一版的摘要）。 */
        const val BRIEF_PARTIAL_BEFORE_CHARGED =
            "子类别只有部分段命中（requires.subCategoriesAny）时按近似加权：每个伤害类型取 1＋(倍率−1)×命中段占比，" +
                "占比＝attackIndex 里所选战技／法术带该子类别的段数÷总段数；attackIndex 只给整招各子类别组合的段数、" +
                "没有逐段对应，所以占比不随上方的分段勾选变化。"

        /** 收尾那一版改值的两句（requireSubsPartial / brief.appliesTo）的旧值（Windows 的 SUBS_RESTORE）。 */
        val SUBS_RESTORE = mapOf(
            "requireSubsPartial" to "所选{0}只有 {1}/{2} 段带子类别 {3}：按 1＋(倍率−1)×{1}/{2} 近似加权（段数取 attackIndex 对整招的统计，与上方分段勾选无关）",
            "brief.appliesTo" to "生效判定一律按数据的 appliesTo：战技（含战技射出的子弹段）看 skill、魔法看 sorcery、祷告看 incantation。conditional 的机读条件里，持武器的手、出手武器类别（法术按施法器：魔法＝手杖、祷告＝圣印记）、物理攻击类型按当前输出自动判定；子类别按 attackIndex 对所选战技／法术判定；攻击情境用上方的情境勾选；附魔武器限定、需同时使用道具等无法自动判定的要手动确认。",
        )

        /** 那一版改值的两句的旧值（Windows ranker_crosscheck.test.mjs 的 MEANS_KIND_RESTORE）。 */
        val MEANS_KIND_RESTORE = mapOf(
            "pageSubtitle" to "选一个战技／法术，再自己组一套局内配置：武器词条、遗物、护符与其它增益，看总增伤",
            "otherInnateNoWeapon" to "法术没有出手武器，这里只有需手动勾选的固有效果",
        )
    }

    @Test
    fun `text table is the same table as both desktop ends - 350 entries, digest 43bf0705`() {
        // skills schemaVersion 3 多了武器来源标记 weaponSource.*（332 → 336 条，854da404 → 07a69c5e）；
        // buffs v6 修订的道具等级再多 goodsLevel.*（336 → 339 条，07a69c5e → 41e2ae25）；
        // 输出手段类型开关拆成三档（战技 / 魔法 / 祷告）再多七个键、改两句「法术」（339 → 346 条，41e2ae25 → 446c874b）；
        // skills v4 的蓄力开关再多 chargedToggle.* 四个键、brief.partial 改值（346 → 350 条，446c874b → 591c0f7f）。
        assertEquals(350, RankerText.table.size)
        // 收尾：requireSubsPartial / brief.appliesTo 改为逐段判定的说法（条数不变，591c0f7f → 43bf0705）。
        assertEquals("43bf0705", RankerCrossCheck.textTableDigest(), "文案常量表摘要（两端 TEXT_TABLE_DIGEST 同一个值）")
        val beforeSubs = RankerText.table + SUBS_RESTORE
        assertEquals("591c0f7f", RankerCrossCheck.textTableDigest(beforeSubs))
        assertEquals(RankerText.table.keys.sorted(), RankerText.table.keys.toList(), "按点号路径排序存放")
        RankerText.table.forEach { (key, value) -> assertTrue(value.isNotEmpty(), "$key 应是非空文案") }
        // 任何一处改动都会让摘要分叉。
        val tampered = RankerText.table + ("reasonNeutral" to RankerText.t("reasonNeutral") + "。")
        assertFalse(RankerCrossCheck.textTableDigest(tampered) == "43bf0705")
        // 蓄力开关那一版：去掉 chargedToggle.*、换回 brief.partial 旧值回到上一版（其余文案一字未动）。
        val beforeCharged = beforeSubs.filterKeys { !it.startsWith("chargedToggle.") } +
            ("brief.partial" to BRIEF_PARTIAL_BEFORE_CHARGED)
        assertEquals(346, beforeCharged.size)
        assertEquals("446c874b", RankerCrossCheck.textTableDigest(beforeCharged))
        // 类型开关那一版只多了七个键、改了 pageSubtitle / otherInnateNoWeapon 两句：去掉新键、换回旧值回到上一版
        // （其余文案一字未动）；再去掉 goodsLevel.* 回到 v3 那一版，再去掉 weaponSource.* 回到 v2 时的那张表。
        val beforeMeansKind = beforeCharged.filterKeys { key -> MEANS_KIND_ADDED.none { key.startsWith(it) } } + MEANS_KIND_RESTORE
        assertEquals(339, beforeMeansKind.size)
        assertEquals("41e2ae25", RankerCrossCheck.textTableDigest(beforeMeansKind))
        val beforeGoodsLevel = beforeMeansKind.filterKeys { !it.startsWith("goodsLevel.") }
        assertEquals(336, beforeGoodsLevel.size)
        assertEquals("07a69c5e", RankerCrossCheck.textTableDigest(beforeGoodsLevel))
        assertEquals("854da404", RankerCrossCheck.textTableDigest(beforeGoodsLevel.filterKeys { !it.startsWith("weaponSource.") }))
    }

    @Test
    fun `charged toggle texts are word for word the same as the desktop TEXT chargedToggle`() {
        // skills v4 的「蓄力」开关（放在「专注值不足版」开关旁），三端同名同值。
        assertEquals(
            mapOf(
                "chargedToggle.hint" to "打开只计蓄力段（蓄力法术 / 蓄力战技 / 蓄力强攻击），关闭只计非蓄力段；两者是同一招的互斥两侧，不能相加",
                "chargedToggle.label" to "蓄力",
                "chargedToggle.onlyCharged" to "这一招只有蓄力段",
                "chargedToggle.unavailable" to "这一招没有蓄力段",
            ),
            RankerText.table.filterKeys { it.startsWith("chargedToggle.") },
        )
        assertEquals(
            "子类别限定（requires.subCategoriesAny）按当前勾选的段逐段判定：每个伤害类型取「命中该子类别的段的相对值占比」加权，" +
                "即 1＋(倍率−1)×占比；勾选的段全部命中即全额，没有段命中即不生效。蓄力开关决定勾选的是蓄力段还是非蓄力段，" +
                "所以蓄力类增益在蓄力施放下拿到全额。",
            RankerText.t("brief.partial"),
        )
        // requireSubsPartial 未改值（三端同文），页面只引用冒号前的半句。
        val half = RankerTestData.buffs.subsPartialText("祷告", 1, 2, "[110 蓄力法术攻击]")
        assertEquals("所选祷告只有 1/2 段带子类别 [110 蓄力法术攻击]", half)
        assertTrue(RankerText.t("requireSubsPartial").startsWith("所选{0}只有 {1}/{2} 段带子类别 {3}："))
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
