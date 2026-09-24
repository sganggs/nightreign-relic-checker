package com.nightreign.relicchecker.gamedata.ranker

import com.nightreign.relicchecker.gamedata.GameDataFormatException
import com.nightreign.relicchecker.gamedata.GameDataJson
import com.nightreign.relicchecker.gamedata.ranker.RankerTestData.assertClose
import com.nightreign.relicchecker.gamedata.ranker.RankerTestData.out
import com.nightreign.relicchecker.gamedata.ranker.RankerTestData.shares
import com.nightreign.relicchecker.gamedata.ranker.RankerTestData.synth
import com.nightreign.relicchecker.gamedata.ranker.RankerTestData.synthBuff
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertNotEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

// buffs 数据集、字段表、每条 buff 的预计算、appliesTo 判定与单条评估（对应 windows/tests/ranker.test.mjs 的
// 倍率字段 / v6 索引字段 / 多档词条 / 减益 / appliesTo 判定 / 叠层 / 单条评估各节，以及 macOS checkBuffDataset）。
class BuffRankerIndexTest {
    private val buffs get() = RankerTestData.buffs
    private val dataset get() = buffs.dataset
    private val plan get() = RankerTestData.plan

    private fun eval(
        entry: BuffRankerEntry,
        output: RankerOutput = out(),
        selections: EntrySelections = EntrySelections.NONE,
        options: EvalOptions = EvalOptions.STANDARD,
        source: EvalSource = EvalSource(),
        index: BuffRankerIndex = buffs,
    ): EvaluatedEntry = index.evaluate(entry, output, selections, options, source)

    private fun conditional(reason: String, requires: BuffRequirement?): (BuffEntry) -> BuffEntry = {
        it.copy(
            appliesTo = BuffAppliesTo(skill = "conditional"),
            appliesToDetail = BuffAppliesDetails(skill = BuffAppliesDetail(reason = reason, requires = requires)),
        )
    }

    // ------------------------------------------------------------------ 数据集与固定事实

    @Test
    fun `dataset carries the v6 structures the page depends on`() {
        assertEquals(6, dataset.schemaVersion)
        assertTrue(dataset.gameVersion.startsWith("v1.03.5"))
        assertEquals(874, dataset.buffs.size)
        assertEquals(76, dataset.rateFields.size)
        assertEquals(10, dataset.rateFieldGroups.size)
        assertEquals(874, dataset.counts.buffs)
        assertEquals(146, dataset.counts.weaponAffixes)
        assertEquals(120, dataset.counts.fixedRelics)
        assertEquals(5, dataset.counts.buffsWithStackInput)
        assertEquals(442, dataset.counts.exclusiveKeys)
        assertEquals(146, dataset.weaponAffixes.size)
        assertEquals(120, dataset.fixedRelics.size)
        for (key in listOf("ranking", "appliesTo", "sourceSlot", "weaponAffix", "relicAffix", "stackInput", "activation", "attackContext", "howToUseRates", "target", "displayName", "zh")) {
            assertTrue(dataset.notes[key].orEmpty().isNotBlank(), "notes.$key")
        }
        assertFalse("userQuestions" in dataset.notes, "userQuestions 是对象，单独解析")
        assertEquals(listOf("Q1", "Q2", "Q3", "Q4", "Q5"), dataset.userQuestions.map { it.key })
        assertTrue(dataset.userQuestions.all { it.question.isNotBlank() && it.answer.isNotBlank() })
        assertTrue(dataset.stackingRulesZh.isNotBlank())
        // slotRules（常规 3 件遗物 / 深夜 6 件，武器词条 6 / 12 条，深夜专属最多 6 条，护符 2 个）
        val rules = assertNotNull(dataset.slotRules)
        assertEquals(3, rules.modes.normal.relicSlots)
        assertEquals(6, rules.modes.deep.relicSlots)
        assertEquals(6, rules.weaponAffix.maxAffixesNormal)
        assertEquals(12, rules.weaponAffix.maxAffixesDeep)
        assertEquals(6, rules.weaponAffix.maxDeepOnlyAffixes)
        assertEquals("unknown", rules.weaponAffix.duplicateWithinWeapon.status)
        assertEquals(2, rules.accessory.slots)
        assertEquals(3, rules.relic.affixesPerRelic)
        assertEquals(7, rules.slotlessZh.size)
        // 枚举与 attackIndex
        assertEquals("手杖", dataset.enums.wepType[57])
        assertEquals("圣印记", dataset.enums.wepType[61])
        assertEquals("遗物词条", dataset.sourceKindLabel("relicAffix"))
        assertEquals("突刺反击（被打断攻击后的突刺）", dataset.attackContextLabel("thrustingCounter"))
        assertEquals("局内武器词条", dataset.sourceSlotLabel("weaponAffix"))
        assertEquals(listOf(BuffSubCategorySet(subs = listOf(112, 130), hits = 12)), dataset.attackIndex.skills[1177])
        assertEquals(2, dataset.attackIndex.spells[5040]?.size)
        assertTrue(dataset.attackIndex.melee.isNotEmpty() && dataset.attackIndex.melee.all { it.rows > 0 })
        // 每条都有三类输出的 appliesTo、互斥键与来源槽位
        dataset.buffs.forEach { buff ->
            val applies = assertNotNull(buff.appliesTo, "${buff.spEffectId} 缺 appliesTo")
            OutputClass.entries.forEach { cls -> assertTrue(applies[cls] in setOf("yes", "no", "conditional"), "${buff.spEffectId}.${cls.key}") }
            assertTrue(buff.stacking.exclusiveKey.isNotEmpty(), "${buff.spEffectId} 缺 exclusiveKey")
            assertTrue(buff.sourceSlot.isNotEmpty())
            assertTrue(buff.activation in setOf("passive", "conditional", "activated"))
            assertTrue(buff.target in setOf("self", "ally", "summon", "enemy"))
        }
        assertEquals("874 条增益 · 其中 353 条无条件生效", buffs.summary)
    }

    @Test
    fun `wrong schema version is rejected`() {
        assertFailsWith<GameDataFormatException> { RankerParsers.buffs("""{"schemaVersion":5,"buffs":[]}""") }
        assertFailsWith<GameDataFormatException> { RankerParsers.buffs("""{"schemaVersion":6,"buffs":[]}""") }
    }

    @Test
    fun `display names are displayNameZh and unique across the table`() {
        assertEquals("提升战技攻击力（档位1）", buffs.byId.getValue(8350000).name)
        assertEquals("每次打倒封印监牢里的囚犯，能提升攻击力", buffs.byId.getValue(7069001).name)
        val withDisplay = dataset.buffs.first { !it.displayNameZh.isNullOrEmpty() }
        assertEquals(withDisplay.displayNameZh, withDisplay.displayName)
        val names = buffs.entries.map { it.name }
        assertEquals(names.size, names.toSet().size, "displayNameZh 在全表唯一，列表不该出现重名")
        assertEquals("#-5", BuffEntry(spEffectId = -5).displayName)
        assertEquals("Only English", BuffEntry(spEffectId = -6, nameEn = "Only English").displayName)
    }

    // ------------------------------------------------------------------ 倍率字段

    @Test
    fun `parseRateFieldKey recognizes damage, attack power and flat layers`() {
        assertEquals(RateLayer.DAMAGE, RateFieldPlan.parseKey("physicsAttackRate")?.layer)
        assertEquals(RateLayer.ATTACK_POWER, RateFieldPlan.parseKey("physicsAttackPowerRate")?.layer)
        assertEquals(RateLayer.FLAT, RateFieldPlan.parseKey("physicsAttackPower")?.layer)
        assertEquals(DamageType.PHYSICAL, RateFieldPlan.parseKey("physicsAttackRate")?.types)
        assertEquals(listOf(DamageType.SLASH), RateFieldPlan.parseKey("slashAttackRate")?.types)
        assertEquals(listOf(DamageType.HOLY), RateFieldPlan.parseKey("darkAttackRate")?.types, "dark 槽位在本作＝圣")
        assertEquals(listOf(DamageType.LIGHTNING), RateFieldPlan.parseKey("thunderAttackPowerRate")?.types)
        assertNull(RateFieldPlan.parseKey("saAttackPowerRate"), "削韧不在伤害轴上")
        assertNull(RateFieldPlan.parseKey("bowDistRate"))
    }

    @Test
    fun `rate field plan parses every countsAsDamage field and keeps conditional damage out`() {
        assertEquals(emptyList(), plan.unmapped, "countsAsDamage 字段出现了解析不了的 key")
        assertEquals(18, plan.multiplier.size)
        assertEquals(5, plan.flat.size)
        assertEquals(dataset.rateFields.count { it.countsAsDamage }, plan.multiplier.size + plan.flat.size)
        plan.skipped.forEach { assertNotEquals(true, plan.byKey[it]?.countsAsDamage) }
        val conditional = dataset.rateFields.filter { it.conditionalDamage }
        assertTrue(conditional.isNotEmpty())
        conditional.forEach { field -> assertTrue(plan.multiplier.none { it.key == field.key }, "${field.key} 不得无条件相乘") }
        assertEquals(true, dataset.rateField("physicsAttackRate")?.isRankingMultiplier)
        assertEquals(true, dataset.rateField("physicsAttackPower")?.isRankingFlat)
        assertEquals("special", dataset.rateField("restageAttackRate")?.valueKind)
        val groups = dataset.rateFieldGroups.associateBy { it.key }
        listOf("damage", "attackPower", "attackPowerFlat").forEach { assertEquals(true, groups[it]?.countsAsDamage, it) }
        listOf("weakness", "critical").forEach {
            assertEquals(false, groups[it]?.countsAsDamage, it)
            assertEquals(true, groups[it]?.conditionalDamage, it)
        }
    }

    @Test
    fun `physical rates fan out to every physical type, elemental rates stay in their own cell`() {
        fun entry(rates: Map<String, Double>) = BuffRankerIndex.indexEntry(BuffEntry(spEffectId = -1, rates = rates), plan)
        val physOnly = entry(mapOf("physicsAttackRate" to 1.2))
        DamageType.PHYSICAL.forEach { assertTrue(physOnly.multiplier[it.ordinal] > 1, "${it.key} 应当吃到物理倍率") }
        listOf(DamageType.MAGIC, DamageType.FIRE, DamageType.LIGHTNING, DamageType.HOLY).forEach {
            assertEquals(1.0, physOnly.multiplier[it.ordinal])
        }
        val fireOnly = entry(mapOf("fireAttackRate" to 1.5))
        assertEquals(1.5, fireOnly.multiplier[DamageType.FIRE.ordinal])
        assertEquals(1.0, fireOnly.multiplier[DamageType.SLASH.ordinal])
        // 斩击倍率与物理倍率同时生效、相乘（stackingRules 第 5 条）。
        val both = entry(mapOf("physicsAttackRate" to 2.0, "slashAttackRate" to 3.0))
        assertEquals(6.0, both.multiplier[DamageType.SLASH.ordinal])
        assertEquals(2.0, both.multiplier[DamageType.BLOW.ordinal])
        // 攻击力倍率与最终伤害倍率是两层，两层相乘。
        assertEquals(6.0, entry(mapOf("fireAttackRate" to 2.0, "fireAttackPowerRate" to 3.0)).multiplier[DamageType.FIRE.ordinal])
        // 点数加算不折成倍率，单独进 flat 表。
        val flatOnly = entry(mapOf("fireAttackPower" to 35.0))
        assertEquals(1.0, flatOnly.multiplier[DamageType.FIRE.ordinal])
        assertEquals(35.0, flatOnly.flat[DamageType.FIRE.ordinal])
        assertTrue(flatOnly.hasFlat)
        assertFalse(flatOnly.hasMultiplier)
        assertEquals(listOf("fireAttackPower"), flatOnly.usedFlat.map { it.key })
    }

    @Test
    fun `poise, status, special and flag fields never enter the damage table`() {
        val noise = BuffRankerIndex.indexEntry(
            BuffEntry(
                spEffectId = -6,
                rates = mapOf("saAttackPowerRate" to 2.0, "bloodAttackPower" to 50.0, "restageAttackRate" to 0.6, "isUseAtkParamAtkPowerCorrect" to 1.0),
            ),
            plan,
        )
        assertFalse(noise.countsAsDamage, "这些字段不改变血量伤害")
        assertEquals(4, noise.otherRateKeys.size, "但要能提示『另有不计入伤害的字段』")
    }

    @Test
    fun `multiplier table only takes countsAsDamage multipliers that differ from the default`() {
        val table = plan.multiplierTable(
            mapOf(
                "physicsAttackRate" to 1.1, "magicAttackRate" to 1.0, "saAttackPowerRate" to 2.0,
                "bloodAttackPower" to 30.0, "weakDmgRateB" to 10.0, "restageAttackRate" to 0.6,
            ),
        )
        DamageType.PHYSICAL.forEach { assertClose(1.1, table[it.ordinal], 1e-9, it.key) }
        assertEquals(1.0, table[DamageType.MAGIC.ordinal])
        assertEquals(1.0, table[DamageType.FIRE.ordinal])
        assertEquals(1.0, table[DamageType.HOLY.ordinal])
        val used = ArrayList<RateUse>()
        plan.multiplierTable(mapOf("fireAttackRate" to 1.25, "physicsAttackRate" to 0.0), null, used)
        assertEquals(listOf("fireAttackRate"), used.map { it.key }, "0 不是合法乘数，必须跳过")
    }

    // ------------------------------------------------------------------ v6 索引字段

    @Test
    fun `index carries v6 source slot, appliesTo, exclusive key, stack input and accumulator ladder`() {
        val skillAttack = buffs.byId.getValue(8350000)
        assertEquals("weaponAffix", skillAttack.slot)
        assertEquals("sp10#8350000", skillAttack.key)
        assertEquals("conditional", skillAttack.buff.appliesTo?.skill)
        val evergaol = buffs.byId.getValue(7069001)
        assertEquals("ladder", evergaol.stackInput?.mode)
        val grace = buffs.byId.getValue(8970000)
        assertEquals("copies", grace.stackInput?.mode)
        assertEquals("runStack", grace.slot)
        val prosthesis = buffs.byId.getValue(312506)
        assertNotNull(prosthesis.accLadder, "米莉森的义手是累积阶梯")
        assertEquals(312505, prosthesis.ladderGroup, "阶梯组 id 取第 1 档")
        assertEquals(2, prosthesis.ladderTier)
        assertEquals(dataset.buffs.size, buffs.entries.size, "索引应当覆盖全表")
        buffs.entries.forEach { entry ->
            assertEquals(entry.buff.stacking.exclusiveKey, entry.key, "${entry.id} 的互斥键必须原样取 exclusiveKey")
            val listable = entry.countsAsDamage && (entry.target == "self" || entry.target == "ally") && entry.direction != "decrease"
            assertEquals(listable, entry.listable, "${entry.id} 能不能进配置页")
        }
        assertEquals("self", buffs.byId.getValue(1876).pairRole)
        assertEquals("ally", buffs.byId.getValue(1877).pairRole)
        assertEquals("ally", buffs.byId.getValue(1877).target)
        assertEquals(listOf(1210), buffs.byId.getValue(7050301).goodsIds, "requiresGoodsIds 原样带出")
        assertEquals("勇者肉块", buffs.goodsName(1210))
        // 固定事实：能进计算 496 条（带伤害字段 560 条）；三对 selfAllyPair；四条累积阶梯；五条叠层输入。
        assertEquals(560, buffs.entries.count { it.countsAsDamage })
        assertEquals(496, buffs.listableEntries.size)
        assertEquals(
            listOf(1835 to "self", 1836 to "ally", 1870 to "self", 1871 to "ally", 1876 to "self", 1877 to "ally"),
            buffs.entries.filter { it.pairRole != null }.map { it.id to it.pairRole },
        )
        assertEquals(
            mapOf(
                3558 to listOf(3558, 3559, 3560, 3561),
                312505 to listOf(312505, 312506, 312507, 312508),
                320804 to listOf(320804, 320805, 320806, 320807),
                7037604 to listOf(7037604, 7037605, 7037606),
            ),
            buffs.ladders.mapValues { (_, members) -> members.map { it.id } }.toSortedMap(),
        )
        val stackInputs = buffs.entries.filter { it.stackInput != null }.associate { entry ->
            val input = entry.stackInput!!
            entry.id to Triple(input.mode, input.paramMax, input.softMax)
        }
        assertEquals(
            mapOf(
                7069001 to Triple("ladder", 10, 7),
                7069201 to Triple("ladder", 10, 4),
                8970000 to Triple("copies", 99, 10),
                8988200 to Triple("ladder", 100, null),
                8998000 to Triple("ladder", 100, null),
            ),
            stackInputs,
        )
    }

    // ------------------------------------------------------------------ 道具等级（v6 修订 goodsLevel，携物知识）

    @Test
    fun `goods level - Bagcraft level 2 and 3 rows carry goodsLevel and are tagged, level 1 rows are not`() {
        // 勇者肉块三行：3950（1 级，物理 ×1.2）、708420（2 级，物理 ×1.3）、708421（3 级，物理 ×1.3 + 四属性 ×1.2）。
        val base = buffs.byId.getValue(3950)
        val level2 = buffs.byId.getValue(708420)
        val level3 = buffs.byId.getValue(708421)
        assertEquals(listOf(1, 2, 3), listOf(base, level2, level3).map { it.goodsLevel })
        assertNull(base.buff.goodsLevel, "1 级行不写 goodsLevel（缺省＝1 级）")
        assertEquals(listOf("", "携物知识 2 级", "携物知识 3 级"), listOf(base, level2, level3).map { LoadoutText.goodsLevelTag(it) })
        listOf(level2, level3).forEach { entry ->
            assertEquals(3950, entry.buff.goodsBaseSpEffectId, "${entry.id} 的 1 级行")
            assertEquals("学者能力「携物知识」（CL_MenuText 20020）", entry.buff.goodsLevelSource)
            assertEquals(base.key, entry.key, "同一道具各级同一个互斥键（换等级只是换一行）")
        }
        // 3 级比 1、2 级多出四属性：名字前缀写真（notes.displayName），nameZh 仍是游戏文本。
        assertEquals(mapOf("physicsAttackRate" to 1.2), base.rates)
        assertEquals(mapOf("physicsAttackRate" to 1.3), level2.rates)
        listOf(DamageType.MAGIC, DamageType.FIRE, DamageType.LIGHTNING, DamageType.HOLY).forEach { type ->
            assertClose(1.2, level3.multiplier[type.ordinal], 1e-12, "708421 的 ${type.key} 倍率")
            assertClose(1.0, base.multiplier[type.ordinal], 1e-12, "3950 不提高 ${type.key}")
        }
        assertEquals("提升物理与属性攻击力（勇者肉块・携物知识3级）", level3.name)
        assertEquals("提升物理攻击力", level3.buff.nameZh)
        assertTrue(level2.name.contains("携物知识2级") && !level2.name.contains("属性"), level2.name)

        // 全表：72 条等级行（2 级 45、3 级 27），都在「道具」栏；等级来源都是携物知识。
        val levelRows = buffs.entries.filter { it.goodsLevel >= 2 }
        assertEquals(72, levelRows.size)
        assertEquals(45, levelRows.count { it.goodsLevel == 2 })
        assertEquals(27, levelRows.count { it.goodsLevel == 3 })
        levelRows.forEach { entry ->
            assertEquals("consumable", entry.slot, "${entry.id} 是道具等级行")
            assertTrue(entry.buff.goodsLevelSource.orEmpty().contains("携物知识"), "${entry.id} 的等级来源")
            assertEquals("携物知识 ${entry.goodsLevel} 级", LoadoutText.goodsLevelTag(entry))
        }
        assertEquals(67, levelRows.count { it.buff.goodsBaseSpEffectId != null })
        assertTrue(buffs.entries.filter { it.goodsLevel < 2 }.all { LoadoutText.goodsLevelTag(it).isEmpty() })

        // 2、3 级共用的行按最低那一级标；各级共用的 1 级行（500925 粪便壶自身中毒 [1, 2, 3]）不标。
        assertEquals(listOf(1, 2, 3), buffs.byId.getValue(500925).buff.goodsLevels)
        assertEquals("", LoadoutText.goodsLevelTag(buffs.byId.getValue(500925)))
        assertEquals("携物知识 2 级", LoadoutText.goodsLevelTag(synth(-90) { it.copy(goodsLevel = 2, goodsLevels = listOf(2, 3)) }))
        assertEquals("", LoadoutText.goodsLevelTag(synth(-91) { it.copy(goodsLevels = listOf(1, 2, 3)) }))
        assertEquals(1, synth(-92).goodsLevel, "旧数据没有 goodsLevel：一律按 1 级")
    }

    @Test
    fun `names that only say physical attack up never raise an affinity`() {
        // 名字只说「提升物理攻击力」的条目若也加属性，在法术上增伤会被误读成只加物理（数据车道已把这类名字改写）。
        val affinities = listOf(DamageType.MAGIC, DamageType.FIRE, DamageType.LIGHTNING, DamageType.HOLY)
        val physicalOnly = buffs.listableEntries.filter { it.name.startsWith("提升物理攻击力") }
        assertTrue(physicalOnly.isNotEmpty(), "数据里仍有只加物理的条目")
        physicalOnly.forEach { entry ->
            affinities.forEach { type ->
                assertFalse(
                    entry.multiplier[type.ordinal] > 1.0 || entry.flat[type.ordinal] > 0.0,
                    "${entry.id}「${entry.name}」名字只说物理，却提高 ${type.key}",
                )
            }
        }
        // 数据车道改过名、对法术适用的 9 条（nameZh 都是「提升物理攻击力」）：名字写明属性，确实提高属性，法术上照常判 yes。
        listOf(708421, 1605000, 7031202, 7031302, 7032202, 7032704, 7032706, 7032903, 7260803).forEach { id ->
            val entry = assertNotNull(buffs.byId[id], "$id 在数据里")
            assertEquals("提升物理攻击力", entry.buff.nameZh, "$id 的游戏文本不变")
            assertTrue(entry.name.contains("属性"), "$id「${entry.name}」")
            assertFalse(entry.name.startsWith("提升物理攻击力"), "$id「${entry.name}」")
            assertTrue(affinities.any { entry.multiplier[it.ordinal] > 1.0 }, "$id 确实提高属性")
            assertEquals("yes", entry.buff.appliesTo?.sorcery, "$id 对魔法生效")
            assertEquals("yes", entry.buff.appliesTo?.incantation, "$id 对祷告生效")
        }
    }

    // ------------------------------------------------------------------ 多档词条（affixVariant）

    @Test
    fun `affix variants come only from data - exactly 7 groups x 4 tiers`() {
        assertEquals(28, dataset.buffs.count { it.affixVariant != null })
        val expected = listOf(7120000, 7120100, 7120200, 7120300, 7120400, 7120500, 7120600)
        assertEquals(expected.map { "affix#$it" }.toSet(), buffs.variants.keys)
        expected.forEach { attachId ->
            val members = buffs.variants.getValue("affix#$attachId")
            assertEquals((1..4).map { attachId + it }, members.map { it.id }, "$attachId 的四档")
            members.forEachIndexed { i, entry ->
                assertEquals(i + 1, entry.variantTier)
                assertEquals(entry.buff.affixVariant?.key, entry.variantGroup)
                assertEquals("affix#$attachId", entry.key, "互斥键原样取数据的 exclusiveKey")
                assertEquals(members, buffs.variantMembers(entry))
            }
        }
        assertNull(buffs.byId.getValue(7120405).variantGroup, "状态负载行不是档位")
        listOf(7037604, 7069001, 8885220, 8885221).forEach { assertNull(buffs.byId.getValue(it).variantGroup, "$it 不是多档词条") }
    }

    @Test
    fun `only the selected variant tier counts, default is the first tier`() {
        val members = buffs.variants.getValue("affix#7120000")
        val mixed = out(shares = shares(DamageType.SLASH to 0.5, DamageType.MAGIC to 0.5))
        val source = EvalSource(autoConfirm = true)
        val first = members.map { eval(it, mixed, source = source) }
        assertNotEquals(EntryState.VARIANT_OFF, first[0].state, "第 1 档是选中的那一档")
        assertEquals(List(3) { EntryState.VARIANT_OFF }, first.drop(1).map { it.state })
        assertTrue(first[1].reasons[0].contains("第 1 档") && first[1].reasons[0].contains("affixVariant"))
        val third = object : EntrySelections {
            override fun variantChoice(groupKey: String): Int? = if (groupKey == "affix#7120000") members[2].id else null
        }
        assertEquals(
            listOf(true, true, false, true),
            members.map { eval(it, mixed, third, source = source).state == EntryState.VARIANT_OFF },
        )
        assertEquals(3, buffs.selectedVariant(members[0], third).tier)
        assertEquals(4, buffs.selectedVariant(members[0], EntrySelections.NONE).tiers)
        assertTrue(RankerText.t("variantNoMapping").contains("映射"), "选档控件写明参数里查不到武器类别 → 档位的映射")
    }

    @Test
    fun `entries without affixVariant never form a variant group`() {
        fun relic(id: Int, name: String, rate: Double, key: String, variant: BuffAffixVariant?, compat: Int = -1) =
            synthBuff(id) {
                it.copy(
                    paramName = name, rates = mapOf("physicsAttackRate" to rate),
                    relicAffixes = listOf(BuffRelicAffixRef(attachEffectId = id / 10 * 10, compatibilityId = compat)),
                    stacking = BuffStacking(exclusiveKey = key), affixVariant = variant,
                )
            }
        val list = listOf(
            relic(11, "[Relic] A - Potency 1", 1.1, "affix#10", BuffAffixVariant("affix#10", 10, 1, 2)),
            relic(12, "[Relic] A - Potency 2", 1.2, "affix#10", BuffAffixVariant("affix#10", 10, 2, 2)),
            relic(21, "[Relic] B - Potency 1", 1.1, "sp10#21", null, compat = 5),
            relic(22, "[Relic] B - Potency 2", 1.2, "sp10#22", null, compat = 5),
        )
        val own = RankerTestData.miniIndex(list)
        assertEquals(setOf("affix#10"), own.variants.keys)
        assertEquals(2, own.byId.getValue(12).variantTier)
        assertNull(own.byId.getValue(21).variantGroup)
        assertEquals("sp10#21", own.byId.getValue(21).key)
        val bare = RankerTestData.miniIndex(list.drop(2))
        assertTrue(bare.variants.isEmpty(), "没有 affixVariant 就没有多档组")
        assertEquals("sp10#22", bare.byId.getValue(22).key)
        assertEquals(own.byId.getValue(11).family, own.byId.getValue(12).family, "同族键去掉 Potency 后缀")
    }

    // ------------------------------------------------------------------ 减益与作用对象（notes.ranking ①②）

    @Test
    fun `direction decrease never counts, mixed still counts`() {
        val debuff = synth(-40) { it.copy(rates = mapOf("physicsAttackRate" to 0.87), direction = "decrease") }
        val item = eval(debuff, source = EvalSource(autoConfirm = true))
        assertEquals(EntryState.NO, item.state)
        assertEquals(RankerText.t("reasonDecrease"), item.reasons[0])
        assertFalse(debuff.listable, "减益不进配置页各栏")
        val mixed = synth(-41) { it.copy(rates = mapOf("physicsAttackPower" to 30.0, "magicAttackPower" to 33.0), direction = "mixed") }
        assertEquals(EntryState.COUNTED, eval(mixed, source = EvalSource(autoConfirm = true)).state)
        // 真实数据：【无赖】技艺命中敌人时降低对方攻击力（7500401），target=self、appliesTo.skill=yes，但它是减益。
        val raider = buffs.byId.getValue(7500401)
        assertEquals("decrease", raider.direction)
        assertEquals("yes", raider.buff.appliesTo?.skill)
        assertEquals(EntryState.NO, eval(raider, source = EvalSource(autoConfirm = true)).state)
        buffs.entries.filter { it.direction == "decrease" }.forEach { entry ->
            val state = eval(entry, source = EvalSource(autoConfirm = true)).state
            assertNotEquals(EntryState.COUNTED, state, "${entry.id} 是减益，不能计入")
            assertNotEquals(EntryState.PENDING, state, "${entry.id} 是减益，不该等用户确认")
        }
    }

    @Test
    fun `only self and ally count, the Allies row of a self ally pair does not count for the caster`() {
        val confirm = EvalSource(autoConfirm = true)
        assertEquals(EntryState.COUNTED, eval(synth(-13) { it.copy(target = "ally") }, source = confirm).state, "ally＝自己与／或附近队友")
        val pairAlly = synth(-27) { it.copy(target = "ally", selfAllyPair = BuffSelfAllyPair("ally", -28)) }
        val pairItem = eval(pairAlly, source = confirm)
        assertEquals(EntryState.NO, pairItem.state)
        assertEquals(RankerText.t("reasonAllyPair"), pairItem.reasons[0])
        assertEquals(EntryState.COUNTED, eval(synth(-28) { it.copy(selfAllyPair = BuffSelfAllyPair("self", -27)) }, source = confirm).state)
        assertEquals(EntryState.NO, eval(synth(-14) { it.copy(target = "enemy") }, source = confirm).state)
        assertEquals(EntryState.NO, eval(synth(-15) { it.copy(target = "summon") }, source = confirm).state)
        assertEquals(RankerText.f("reasonTarget", "summon"), eval(synth(-15) { it.copy(target = "summon") }, source = confirm).reasons[0])
        assertEquals(EntryState.NO_DAMAGE, eval(synth(-16) { it.copy(rates = mapOf("saAttackPowerRate" to 2.0)) }).state)
        // 真实数据：共享圣律 1877（队友那一行）不计入。
        val holy = out(OutputClass.INCANTATION, shares = shares(DamageType.HOLY to 1.0))
        assertEquals(EntryState.NO, eval(buffs.byId.getValue(1877), holy, source = confirm).state)
    }

    @Test
    fun `exclusive key falls back to stacking group, then sp category and id`() {
        assertEquals("sp204@p11", BuffEntry(spEffectId = 5, stacking = BuffStacking(exclusiveKey = "sp204@p11", group = "sp204")).exclusiveKey)
        assertEquals("sp160", BuffEntry(spEffectId = 5, stacking = BuffStacking(group = "sp160")).exclusiveKey)
        assertEquals("sp20#5", BuffEntry(spEffectId = 5, stacking = BuffStacking(spCategory = 20)).exclusiveKey)
    }

    @Test
    fun `character key groups by the Paramdex bracket and names match the heroes dataset`() {
        assertEquals("Revenant", BuffRankerIndex.characterKey(BuffEntry(paramName = "[Skill - Revenant] Spirit Stat Change - Level 2")))
        assertEquals("Executor", BuffRankerIndex.characterKey(BuffEntry(paramName = "[Ultimate - Executor] Beast Depth 1")))
        assertEquals("", BuffRankerIndex.characterKey(BuffEntry(paramName = "Magic Cocktail")))
        assertEquals("复仇者", BuffRankerIndex.characterLabel("Revenant"))
        assertEquals("其他角色", BuffRankerIndex.characterLabel(""))
        val heroes = GameDataJson.lenient.parseToJsonElement(RankerTestData.readText("nightreign-heroes-v1.03.5.json"))
            .jsonObject.getValue("heroes").jsonArray
        assertEquals(10, heroes.size)
        heroes.forEach { hero ->
            val obj = hero.jsonObject
            assertEquals(obj.getValue("nameZh").jsonPrimitive.content, BuffRankerIndex.characterLabel(obj.getValue("nameEn").jsonPrimitive.content))
        }
        assertEquals("[Weapon] Improved Skill Attack Power", BuffRankerIndex.familyKey(BuffEntry(paramName = "[Weapon] Improved Skill Attack Power - Potency 2")))
        assertEquals("[Item] X", BuffRankerIndex.familyKey(BuffEntry(paramName = "[Item - Level 3] X")))
        assertEquals("[Relic] X", BuffRankerIndex.familyKey(BuffEntry(paramName = "[Relic] X +3")))
        assertEquals("id#7", BuffRankerIndex.familyKey(BuffEntry(spEffectId = 7)))
    }

    @Test
    fun `attack weapon type is the chosen weapon for skills, staff for sorcery and seal for incantation`() {
        val weapon = RankerTestData.skills.weaponsById.getValue(9040000)
        assertEquals(weapon.wepType, out(weapon = weapon).attackWepType)
        assertNull(out(weapon = null).attackWepType)
        assertEquals(57, out(OutputClass.SORCERY).attackWepType)
        assertEquals(61, out(OutputClass.INCANTATION).attackWepType)
        assertEquals("手杖", buffs.wepTypeLabel(OutputClass.SORCERY.casterWepType!!))
        assertEquals("圣印记", buffs.wepTypeLabel(OutputClass.INCANTATION.casterWepType!!))
        assertEquals("类别 999", buffs.wepTypeLabel(999))
    }

    // ------------------------------------------------------------------ appliesTo 判定

    @Test
    fun `verdict - yes applies directly, no carries the data reason, missing is no`() {
        assertEquals(VerdictState.YES, buffs.verdict(synth(-1), out()).state)
        val no = synth(-2) {
            it.copy(
                appliesTo = BuffAppliesTo(skill = "no", sorcery = "yes", incantation = "yes"),
                appliesToDetail = BuffAppliesDetails(skill = BuffAppliesDetail(reason = "wepParamChange=3（自身）：不作用于武器攻击")),
            )
        }
        val verdict = buffs.verdict(no, out())
        assertEquals(VerdictState.NO, verdict.state)
        assertEquals(listOf("wepParamChange=3（自身）：不作用于武器攻击"), verdict.reasons)
        assertEquals(RankerText.t("verdict.no"), verdict.label)
        assertEquals(VerdictState.YES, buffs.verdict(no, out(OutputClass.SORCERY)).state, "换输出类别就换 appliesTo 的键")
        val missing = buffs.verdict(synth(-3) { it.copy(appliesTo = null) }, out())
        assertEquals(VerdictState.NO, missing.state, "没有 appliesTo 的数据按不生效处理")
        assertEquals(VerdictValue.MISSING, missing.value)
        assertEquals(listOf(RankerText.t("verdictMissing")), missing.reasons)
    }

    @Test
    fun `verdict - requires hand is judged against the current hand`() {
        val right = synth(-4, conditional("wepParamChange=1", BuffRequirement(hand = 1)))
        assertEquals(VerdictState.YES, buffs.verdict(right, out(hand = 1)).state)
        assertEquals(RankerText.t("verdict.conditionalMet"), buffs.verdict(right, out(hand = 1)).label)
        val left = buffs.verdict(right, out(hand = 2))
        assertEquals(VerdictState.NO, left.state)
        assertTrue(left.reasons[0].contains("右手") && left.reasons[0].contains("左手"))
        assertEquals("wepParamChange=1", left.reasons.last(), "不生效时把数据给的 reason 附在最后")
        assertEquals(RequirementState.UNMET, left.requirements.single { it.key == "hand" }.state)
    }

    @Test
    fun `verdict - requires attackWeaponTypes uses the weapon, spells use the caster`() {
        val dagger = synth(-5) {
            it.copy(
                appliesTo = BuffAppliesTo(skill = "conditional", sorcery = "conditional"),
                appliesToDetail = BuffAppliesDetails(
                    skill = BuffAppliesDetail("triggerOnWepType=1", BuffRequirement(attackWeaponTypes = listOf(1))),
                    sorcery = BuffAppliesDetail("triggerOnWepType=57", BuffRequirement(attackWeaponTypes = listOf(57))),
                ),
            )
        }
        assertEquals(VerdictState.YES, buffs.verdict(dagger, out(weapon = SkillWeapon(id = 1, wepType = 1))).state)
        val katana = buffs.verdict(dagger, out(weapon = SkillWeapon(id = 2, wepType = 13)))
        assertEquals(VerdictState.NO, katana.state)
        assertTrue(katana.reasons[0].contains("短剑") && katana.reasons[0].contains("刀"), "类别名取 enums.wepType")
        assertEquals(VerdictState.NO, buffs.verdict(dagger, out(weapon = null)).state, "没有武器就对不上出手武器类别")
        assertEquals(RankerText.f("requireWepTypeNoWeapon", "短剑"), buffs.verdict(dagger, out(weapon = null)).reasons[0])
        assertEquals(VerdictState.YES, buffs.verdict(dagger, out(OutputClass.SORCERY)).state, "魔法由手杖施放")
    }

    @Test
    fun `verdict - requires physicalType restricts to that channel and fails without it`() {
        val pierce = synth(-6, conditional("atkAttribute=2", BuffRequirement(physicalType = 2)))
        val mixed = out(shares = shares(DamageType.SLASH to 0.5, DamageType.THRUST to 0.5))
        val verdict = buffs.verdict(pierce, mixed)
        assertEquals(VerdictState.YES, verdict.state)
        assertEquals(DamageType.THRUST, verdict.restrictedType)
        val (table, _) = buffs.tables(pierce, verdict.restrictedType, verdict.weight, null, 1)
        assertEquals(1.2, table[DamageType.THRUST.ordinal])
        assertEquals(1.0, table[DamageType.SLASH.ordinal], "只乘对应的那一格")
        assertEquals(VerdictState.NO, buffs.verdict(pierce, out(shares = shares(DamageType.SLASH to 1.0))).state)
        assertEquals(RankerText.f("requirePhysicalFail", "突刺"), buffs.verdict(pierce, out()).reasons[0])
        // 没有构成时不拦（算不出，交给加权）。
        assertEquals(VerdictState.YES, buffs.verdict(pierce, out(shares = shares())).state)
    }

    @Test
    fun `verdict - requires subCategoriesAny is judged per hit through attackIndex`() {
        val attackIndex = BuffAttackIndex(
            skills = mapOf(
                1 to listOf(BuffSubCategorySet(subs = listOf(112, 130), hits = 4)),
                2 to listOf(BuffSubCategorySet(subs = listOf(106, 130), hits = 3)),
                3 to listOf(BuffSubCategorySet(subs = listOf(112), hits = 1), BuffSubCategorySet(subs = listOf(130), hits = 3)),
            ),
            spells = emptyMap(), melee = emptyList(), ranged = emptyList(),
        )
        val buff = synthBuff(-7, conditional("子类别限定 [112]", BuffRequirement(subCategoriesAny = listOf(111, 112))))
        val index = RankerTestData.miniIndex(listOf(buff), attackIndex)
        val entry = index.byId.getValue(-7)
        assertEquals(VerdictState.YES, index.verdict(entry, out(meansId = 1)).state)
        val none = index.verdict(entry, out(meansId = 2))
        assertEquals(VerdictState.NO, none.state)
        assertTrue(none.reasons[0].contains("112"))
        val partial = index.verdict(entry, out(meansId = 3))
        assertEquals(VerdictState.YES, partial.state)
        assertEquals(0.25, partial.weight, "4 段里 1 段带 112")
        assertTrue(partial.notes[0].contains("1/4"))
        assertEquals(RankerText.t("verdict.partial"), partial.label)
        val (table, _) = index.tables(entry, null, partial.weight, null, 1)
        assertClose(1 + 0.2 * 0.25, table[DamageType.SLASH.ordinal], 1e-12, "按段加权：1 + (m − 1) × 命中段占比")
        assertEquals(VerdictState.PENDING, index.verdict(entry, out(meansId = 99)).state, "attackIndex 里查不到就要用户确认")
        // 真实数据：尸横遍野 12 段全带 112 → 生效；死亡雷击是祷告，8350000 对祷告是 no。
        val real = buffs.byId.getValue(8350000)
        val onSkill = buffs.verdict(real, out(meansId = 1177))
        assertEquals(VerdictState.YES, onSkill.state)
        assertEquals(RequirementState.MET, onSkill.requirements.single().state)
        assertEquals(RankerText.f("requireSubsAll", "战技", 12, "[111 蓄力战技攻击、112 战技攻击]"), onSkill.requirements.single().text)
    }

    @Test
    fun `verdict - attack contexts need the context ticked, imbued weapon and unknown keys need confirmation`() {
        val counter = synth(-8, conditional("stateInfo=197", BuffRequirement(attackContexts = listOf("thrustingCounter"))))
        val unchecked = buffs.verdict(counter, out())
        assertEquals(VerdictState.CONTEXT, unchecked.state)
        assertTrue(unchecked.reasons[0].contains("突刺反击"), "情境中文名取 enums.attackContext")
        assertEquals(listOf("thrustingCounter"), unchecked.contexts)
        assertEquals(VerdictState.YES, buffs.verdict(counter, out(contexts = setOf("thrustingCounter"))).state)

        val imbued = synth(-9, conditional("spAttribute=10", BuffRequirement(imbuedWeaponOnly = true)))
        val pending = buffs.verdict(imbued, out())
        assertEquals(VerdictState.PENDING, pending.state)
        assertEquals(RankerText.t("requireImbued"), pending.needs[0])
        assertEquals(listOf("spAttribute=10"), pending.reasons)

        val bare = synth(-10) {
            it.copy(appliesTo = BuffAppliesTo(skill = "conditional"), appliesToDetail = BuffAppliesDetails(skill = BuffAppliesDetail("看战技")))
        }
        val bareVerdict = buffs.verdict(bare, out())
        assertEquals(VerdictState.PENDING, bareVerdict.state, "conditional 却没有机读条件 → 要确认")
        assertEquals(RankerText.f("requireManual", "看战技"), bareVerdict.needs.single())

        // 数据新增的 requires 键不能被静默放行：解码时认出来，判定时要确认。
        val detail = GameDataJson.lenient.decodeFromString(
            BuffAppliesDetail.serializer(), """{"reason":"x","requires":{"someNewKey":1,"hand":2,"attackContexts":["guardCounter"]}}""",
        )
        val requires = assertNotNull(detail.requires)
        assertEquals(listOf("someNewKey"), requires.unknownKeys)
        assertEquals(2, requires.hand)
        assertEquals(listOf("guardCounter"), requires.attackContexts)
        val odd = synth(-11, conditional("x", BuffRequirement(unknownKeys = listOf("someNewKey"))))
        val oddVerdict = buffs.verdict(odd, out())
        assertEquals(VerdictState.PENDING, oddVerdict.state)
        assertEquals(RankerText.f("requireUnknown", "someNewKey"), oddVerdict.needs.single())
    }

    @Test
    fun `verdict - real data samples match the desktop wording`() {
        val weapon = RankerTestData.skills.weaponsById.getValue(9040000)
        val corpse = out(meansId = 1177, weapon = weapon, shares = shares(DamageType.SLASH to 0.5, DamageType.FIRE to 0.5))
        fun verdictOf(id: Int, output: RankerOutput = corpse) = buffs.verdict(buffs.byId.getValue(id), output)
        assertEquals(VerdictState.YES, verdictOf(8350000).state)
        assertEquals("生效（条件已满足）", verdictOf(8350000).label)
        assertEquals("生效（条件已满足）", verdictOf(7006700).label)
        assertEquals("条件生效", verdictOf(7035902).label, "条件型（切换武器时）要用户确认")
        assertEquals("条件生效", verdictOf(7069001).label)
        val goods = verdictOf(7050301)
        assertEquals(VerdictState.PENDING, goods.state)
        assertEquals(listOf("需同时使用道具：勇者肉块，需确认"), goods.needs)
        val incantation = out(OutputClass.INCANTATION, meansId = 5040, shares = shares(DamageType.LIGHTNING to 1.0))
        val onIncantation = verdictOf(8350000, incantation)
        assertEquals(VerdictState.NO, onIncantation.state)
        assertEquals(
            listOf("miracleParamChange=0：参数声明不作用于祷告；子类别限定 [111 蓄力战技攻击、112 战技攻击]：祷告的命中段都不带这类子类别"),
            onIncantation.reasons,
        )
        assertEquals(RankerText.t("activationNeed.conditional"), buffs.activationNote(buffs.byId.getValue(7035902)))
        assertEquals(RankerText.t("activationNeed.activated"), buffs.activationNote(buffs.byId.getValue(1877)))
        assertNull(buffs.activationNote(buffs.byId.getValue(8350000)))
    }

    // ------------------------------------------------------------------ 叠层与累积阶梯

    @Test
    fun `stacked rates - ladder takes tierMultipliers n-1, copies take perStackMultiplier to the n`() {
        val evergaol = buffs.byId.getValue(7069001)
        val input = assertNotNull(evergaol.stackInput)
        assertTrue(input.tierMultipliers.size > 1)
        val seven = assertNotNull(buffs.stackedRates(evergaol, 7))
        input.appliesToRateKeys.forEach { assertEquals(input.tierMultipliers[6], seven[it]) }
        assertEquals(1.4072, input.tierMultipliers[6])
        assertEquals(input.tierMultipliers.last(), buffs.stackedRates(evergaol, 99)?.get(input.multiplierKey), "超出按最后一层")
        assertNull(buffs.stackedRates(evergaol, 0), "0 层 = 不计入")
        assertEquals(input.tierMultipliers[0], buffs.stackedRates(evergaol, 1)?.get(input.multiplierKey))
        val grace = buffs.byId.getValue(8970000)
        val graceInput = assertNotNull(grace.stackInput)
        val per = assertNotNull(graceInput.perStackMultiplier)
        assertClose(Math.pow(per, 3.0), buffs.stackedRates(grace, 3)?.get(graceInput.multiplierKey), 1e-12, "copies")
        assertEquals(per, grace.rates[graceInput.multiplierKey], "原 rates 不被改写")
    }

    @Test
    fun `stack inputs - default stacks, param max and warnings`() {
        val evergaol = assertNotNull(buffs.byId.getValue(7069001).stackInput)
        val grace = assertNotNull(buffs.byId.getValue(8970000).stackInput)
        assertEquals(evergaol.practicalMaxStacks, evergaol.defaultStacks, "预填一局实际上限")
        assertEquals(7, evergaol.defaultStacks)
        assertEquals(1, grace.defaultStacks, "参数表无上限、也没有实测上限的预填 1 份")
        assertEquals(0, EntrySelections.NONE.stacks(7069001), "没填过层数就是 0")
        assertEquals(0, buffs.stackWarnings(evergaol, 7, 7).size)
        assertTrue(buffs.stackWarnings(evergaol, 8, 8)[0].contains("7"), "超过一局实际上限要提示")
        assertTrue(buffs.stackWarnings(evergaol, 8, 8)[0].contains("实测"), "来源取冒号前的短标签")
        assertEquals(2, buffs.stackWarnings(evergaol, 12, evergaol.paramMax).size, "超过参数表层数再多一条")
        assertTrue(buffs.stackWarnings(grace, 11, 11)[0].contains("10"), "copies 超过游戏文本备好的＋N 标签要提示")
        assertEquals(evergaol.paramMaxStacks, evergaol.paramMax)
        assertEquals(BuffStackInput.COPIES_CEILING, grace.paramMax, "份数型参数表无上限，页面按 99 截断误输入")
    }

    @Test
    fun `stack inputs - zero stacks do not count, filling stacks counts as confirmation`() {
        val evergaol = buffs.byId.getValue(7069001)
        val zero = eval(evergaol, source = EvalSource(column = SummaryColumn.RELIC))
        assertEquals(EntryState.ZERO_STACKS, zero.state)
        assertEquals(RankerText.t("reasonZeroStacks"), zero.reasons[0])
        val seven = object : EntrySelections {
            override fun stacks(spEffectId: Int): Int = if (spEffectId == 7069001) 7 else 0
        }
        val counted = eval(evergaol, selections = seven, source = EvalSource(column = SummaryColumn.RELIC))
        assertEquals(EntryState.COUNTED, counted.state, "填层数即视为条件成立（不用再勾「条件成立」）")
        assertEquals(7, counted.stacks)
        assertClose(1.4072, counted.multiplier, 1e-12, "封印监牢 7 层")
        val over = object : EntrySelections {
            override fun stacks(spEffectId: Int): Int = 12
        }
        val capped = eval(evergaol, selections = over)
        assertEquals(10, capped.stacks, "按参数表上限截断")
        assertEquals(2, capped.stackWarnings.size)
        assertTrue(capped.notes.containsAll(capped.stackWarnings))
        // 「条件全部成立」口径：没有实际上限的按 1 层并标出来。
        val noCap = eval(buffs.byId.getValue(8988200), options = EvalOptions.OVERVIEW)
        assertEquals(1, noCap.stacks)
        assertTrue(noCap.assumedOneStack)
        assertEquals(10, eval(buffs.byId.getValue(8970000), options = EvalOptions.OVERVIEW).stacks, "退『＋N』标签数")
        assertEquals(EntryState.PENDING, eval(evergaol, selections = seven, options = EvalOptions.STRICT).state, "推荐口径不选叠层")
    }

    @Test
    fun `accumulator ladder - only the selected tier counts, no tier selected counts nothing`() {
        val members = buffs.ladders.getValue(312505)
        assertTrue(members.size >= 3)
        val top = members.last()
        members.forEach { entry ->
            val item = eval(entry, source = EvalSource(column = SummaryColumn.ACCESSORY))
            assertEquals(EntryState.TIER_OFF, item.state, "${entry.id} 没选层时不计入")
            assertEquals(RankerText.t("reasonTierNone"), item.reasons[0])
        }
        val chooseFirst = object : EntrySelections {
            override fun ladderChoice(ladderId: Int): Int? = if (ladderId == 312505) members[0].id else null
        }
        assertEquals(EntryState.COUNTED, eval(members[0], selections = chooseFirst, source = EvalSource(column = SummaryColumn.ACCESSORY)).state, "选层即视为条件成立")
        val topItem = eval(top, selections = chooseFirst, source = EvalSource(column = SummaryColumn.ACCESSORY))
        assertEquals(EntryState.TIER_OFF, topItem.state)
        assertEquals(RankerText.f("reasonTierOff", 1), topItem.reasons[0])
        assertEquals(1, buffs.selectedLadderTier(top, chooseFirst).tier)
        assertEquals(top.id, buffs.ladderTopTier(312505)?.id)
        // 「条件全部成立」取最高层；一览按每一层自己算。
        assertEquals(EntryState.COUNTED, eval(top, options = EvalOptions(assumeAll = true)).state)
        assertEquals(EntryState.TIER_OFF, eval(members[0], options = EvalOptions(assumeAll = true)).state)
        assertEquals(EntryState.COUNTED, eval(members[0], options = EvalOptions.OVERVIEW).state)
    }

    // ------------------------------------------------------------------ 单条评估

    @Test
    fun `conditional entries - slotted columns need a tick, the other column confirms by selection`() {
        val conditional = synth(-12) { it.copy(activation = "conditional") }
        val slotted = eval(conditional, source = EvalSource(column = SummaryColumn.RELIC))
        assertEquals(EntryState.PENDING, slotted.state)
        assertEquals(listOf(RankerText.t("activationNeed.conditional")), slotted.needs)
        val slotless = eval(conditional, source = EvalSource(column = SummaryColumn.OTHER, autoConfirm = true))
        assertEquals(EntryState.COUNTED, slotless.state)
        assertTrue(slotless.ticked)
        val ticked = object : EntrySelections {
            override fun isConfirmed(spEffectId: Int): Boolean = spEffectId == -12
        }
        assertEquals(EntryState.COUNTED, eval(conditional, selections = ticked, source = EvalSource(column = SummaryColumn.WEAPON_AFFIX)).state, "勾了就计入")
        val strict = eval(conditional, selections = ticked, options = EvalOptions.STRICT, source = EvalSource(autoConfirm = true))
        assertEquals(EntryState.PENDING, strict.state, "推荐口径不计条件型")
        assertEquals(EntryState.COUNTED, eval(conditional, options = EvalOptions(assumeAll = true), source = EvalSource(column = SummaryColumn.RELIC)).state, "「条件全部成立」口径当成立")
        val equipped = synth(-19) {
            it.copy(
                activation = "conditional",
                scope = BuffScope(weaponTypes = BuffWeaponTypes(mode = "equippedCount", wepTypes = listOf(1), namesZh = listOf("短剑"), count = 3)),
            )
        }
        assertEquals(RankerText.f("activationNeed.equipped", 3, "短剑"), buffs.activationNote(equipped))
        val goods = buffs.verdict(synth(-18) { it.copy(requiresGoodsIds = listOf(1210)) }, out())
        assertEquals(VerdictState.PENDING, goods.state)
        assertTrue(goods.needs[0].contains("道具"))
    }

    @Test
    fun `effective multiplier is share weighted, attack power and damage layers multiply, flat is only weighted`() {
        val both = synth(-17) { it.copy(rates = mapOf("fireAttackRate" to 1.5, "fireAttackPowerRate" to 1.2, "physicsAttackPower" to 30.0)) }
        val half = out(shares = shares(DamageType.SLASH to 0.5, DamageType.FIRE to 0.5))
        val item = eval(both, half)
        assertClose(1.8, item.table[DamageType.FIRE.ordinal], 1e-12, "两层相乘 1.5 × 1.2")
        assertEquals(1.0, item.table[DamageType.SLASH.ordinal])
        assertClose(0.5 * 1 + 0.5 * 1.8, item.multiplier, 1e-12, "有效倍率")
        assertClose(15.0, item.flat, 1e-12, "物理加算 30 × 物理占比 0.5")
        val none = eval(both, out(shares = shares()))
        assertNull(none.multiplier, "没有构成就算不出倍率")
        assertEquals(0.0, none.flat)
        // 同一效果多份：stackSelf 各份相乘并提示「参数推断」，其余只算一份。
        val copies = eval(synth(-30), source = EvalSource(copies = 2))
        assertEquals(2, copies.countedCopies)
        assertClose(1.44, copies.multiplier, 1e-12, "1.2²")
        assertTrue(copies.notes.contains(RankerText.f("noteCopiesStackSelf", 2)))
        val single = eval(synth(-31) { it.copy(stacking = BuffStacking(spCategoryBehavior = "resetOnApply", exclusiveKey = "sp20#-31")) }, source = EvalSource(copies = 3))
        assertEquals(1, single.countedCopies)
        assertTrue(single.notes.contains(RankerText.f("noteCopiesSingle", 3)))
        // 对当前构成没有增益：火倍率碰上纯斩击构成。
        val neutral = eval(synth(-32) { it.copy(rates = mapOf("fireAttackRate" to 1.5)) })
        assertEquals(EntryState.NEUTRAL, neutral.state)
        assertEquals(RankerText.t("reasonNeutral"), neutral.reasons[0])
    }

    @Test
    fun `attack context options only count contexts really required for the output class`() {
        val skill = buffs.attackContextOptions(OutputClass.SKILL)
        assertEquals(listOf(AttackContextOption("thrustingCounter", "突刺反击（被打断攻击后的突刺）", 5)), skill)
        skill.forEach { assertEquals(dataset.attackContextLabel(it.key), it.zh) }
        assertEquals(emptyList(), buffs.attackContextOptions(OutputClass.INCANTATION), "祷告没有要求攻击情境的条目")
        assertEquals(emptyList(), buffs.attackContextOptions(OutputClass.SORCERY))
        assertEquals(15, BuffRankerIndex.ATTACK_CONTEXT_ORDER.size)
    }

    @Test
    fun `overview lists every listable entry once, applicable first, by multiplier then id`() {
        val weapon = RankerTestData.skills.weaponsById.getValue(9040000)
        val output = out(meansId = 1177, weapon = weapon, shares = shares(DamageType.SLASH to 0.5, DamageType.FIRE to 0.5))
        val started = System.nanoTime()
        val rows = buffs.overview(output)
        val millis = (System.nanoTime() - started) / 1_000_000
        assertTrue(millis < 2_000, "一览应当很快（实际 $millis ms）")
        assertEquals(buffs.listableEntries.map { it.id }.toSet(), rows.map { it.id }.toSet())
        assertEquals(rows.size, rows.map { it.id }.toSet().size)
        val firstBlocked = rows.indexOfFirst { !it.applicable }
        assertTrue(firstBlocked > 0 && rows.drop(firstBlocked).none { it.applicable }, "生效的在前")
        rows.take(firstBlocked).zipWithNext().forEach { (a, b) ->
            val am = a.multiplier ?: 1.0
            val bm = b.multiplier ?: 1.0
            assertTrue(am >= bm - RANK_EPSILON, "按有效倍率降序：#${a.id} $am / #${b.id} $bm")
            if (Math.abs(am - bm) <= RANK_EPSILON) assertTrue(a.id < b.id, "同倍率按 id")
        }
        rows.filter { !it.applicable }.forEach {
            assertEquals(1.0, it.multiplier)
            assertTrue(it.state == EntryState.NO || it.state == EntryState.CONTEXT)
        }
        // 没有构成：倍率一律算不出（null）。
        assertTrue(buffs.overview(out(shares = shares())).all { it.multiplier == null })
        // 封印监牢一览按一局实际上限 7 层算。
        assertClose(1.4072, rows.first { it.id == 7069001 }.multiplier, 1e-12, "封印监牢")
        val flame = rows.first { it.id == 8988200 }
        assertTrue(flame.assumesOneStack, "没有实际上限的叠层按 1 层并写明")
        // 显示用的搜索键
        assertTrue(buffs.byId.getValue(8350000).matches("提升战技攻击力"))
        assertTrue(buffs.byId.getValue(8350000).matches("8350000"))
        assertTrue(buffs.byId.getValue(8350000).matches("improvedskill"))
    }

    @Test
    fun `parse timing is recorded`() {
        // 触发解析并记下耗时（只作参考，不设硬门槛：JVM 冷启动与 CI 机器差别很大）。
        assertTrue(buffs.entries.isNotEmpty() && RankerTestData.skills.outputs.isNotEmpty())
        println("ranker parse: skills ${RankerTestData.skillsParseMillis} ms, buffs ${RankerTestData.buffsParseMillis} ms")
    }
}
