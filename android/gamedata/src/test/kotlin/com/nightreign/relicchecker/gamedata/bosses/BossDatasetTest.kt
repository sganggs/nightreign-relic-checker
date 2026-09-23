package com.nightreign.relicchecker.gamedata.bosses

import com.nightreign.relicchecker.rules.foldedForSearch
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * windows/tests/bosses.test.mjs 的逐条对应（测试名即那边的 test 名），外加 macOS
 * BossDataChecks.swift 的数值 / 代表行 / 对照表断言。期望值都是两端对拍过的硬编码常数。
 */
class BossDatasetTest {
    private val index get() = BossTestData.index
    private val dataset get() = BossTestData.dataset
    private val rows get() = BossTestData.allRows

    private fun fight(json: String) = BossesParser.parseFight(json)

    @Test
    fun `数据集本身就是 schema 4 且能被页面读懂`() {
        assertEquals(4, dataset.schemaVersion)
        assertTrue(dataset.nightlords.isNotEmpty() && dataset.nightBosses.isNotEmpty())
        assertTrue(dataset.caveats.isNotEmpty(), "页面底部要展示 caveats")
        assertTrue(dataset.scalingTiers.isNotEmpty())
        assertTrue(dataset.roleNames.isNotEmpty() && dataset.roleSummary.isNotEmpty(), "v4 的出场场合字段必须在")
        assertTrue(dataset.sources.isNotEmpty())
        assertTrue(dataset.gameVersion.startsWith("v1.03.5"))
        assertEquals("regulation 10350000", dataset.dataVersion)
        assertTrue(dataset.generatedAt.isNotEmpty())
        assertEquals(18, dataset.nightlords.size)
        assertEquals(116, dataset.nightBosses.size)
        assertEquals(index.cards.size, dataset.nightlords.size + dataset.nightBosses.size)
        assertEquals("18 位夜王 · 116 组首领按出场场合分组（49 组属于多个场合）", index.summary)
    }

    @Test
    fun `tierKey 1 人无缩放 2 3 人取 duo trio`() {
        val main = BossTestData.row(75000020)
        assertEquals(BossScalingTier.IDENTITY, main.tier(BossPartySize.SOLO))
        assertEquals(main.scaling!!.duo, main.tier(BossPartySize.DUO))
        assertEquals(main.scaling!!.trio, main.tier(BossPartySize.TRIO))
        assertEquals(BossPartySize.SOLO, BossPartySize.of(0))
        assertEquals(BossPartySize.TRIO, BossPartySize.of(3))
        assertEquals(listOf("1 人", "2 人", "3 人"), BossPartySize.entries.map { it.title })
        // 缺档时按单人处理
        val bare = fight("""{"npcId":1,"hp":1000,"scaling":{"duo":{"hp":2}}}""")
        assertEquals(BossScalingTier.IDENTITY, bare.tier(BossPartySize.TRIO))
        assertEquals(1000, bare.hp(BossPartySize.TRIO))
        assertEquals(2000, bare.hp(BossPartySize.DUO))
    }

    @Test
    fun `血量 1 人直接用 hp 多人 = hp × scaling hp`() {
        val main = BossTestData.lord(0).representativeRow(BossGroup.NIGHTLORD)!!
        assertTrue(main.isMain)
        assertEquals((main.hpBase * main.hpMultiplier).roundHalfAway(), main.hp)
        assertEquals(3200, main.hpBase)
        assertClose(3.54, main.hpMultiplier, "格拉狄乌斯常驻血量倍率")
        assertEquals(main.hp, main.stats(BossPartySize.SOLO).hp)
        assertEquals((main.hp * main.scaling!!.duo!!.hp).roundHalfAway(), main.stats(BossPartySize.DUO).hp)
        assertEquals((main.hp * main.scaling!!.trio!!.hp).roundHalfAway(), main.stats(BossPartySize.TRIO).hp)
        assertEquals(main.hp * 2, main.hp(BossPartySize.DUO))
        assertEquals(main.hp * 3, main.hp(BossPartySize.TRIO))
        assertClose(2.0, main.tier(BossPartySize.DUO).hp, "最终 Boss 档双人血量倍率")
        assertClose(0.3, main.tier(BossPartySize.TRIO).poiseTaken, "最终 Boss 档三人承受削韧")
        assertClose(0.85, main.tier(BossPartySize.DUO).buildupRate, "最终 Boss 档双人异常累积")
        rows.forEach { row -> assertEquals(row.hp, row.hp(BossPartySize.SOLO), "单人血量换算应恒等于 hp：${row.npcId}") }
        rows.forEach { row -> assertTrue(row.hp(BossPartySize.TRIO) >= row.hp(BossPartySize.SOLO)) }
    }

    @Test
    fun `有效韧性 = poise ÷ poiseTakenBase × scaling poiseTaken`() {
        val entry = rows.first { it.poise > 0 && it.scaling?.duo != null }
        val solo = entry.stats(BossPartySize.SOLO)
        val duo = entry.stats(BossPartySize.DUO)
        assertEquals(entry.poise / entry.poiseTakenBase, solo.effectivePoise)
        assertEquals(entry.poise / (entry.poiseTakenBase * entry.scaling!!.duo!!.poiseTaken), duo.effectivePoise)
        assertTrue(duo.effectivePoise!! > solo.effectivePoise!!, "多人承受削韧变低 → 有效韧性变高")
        val main = BossTestData.row(75000020)
        assertClose(120.0, main.effectivePoise(BossPartySize.SOLO), "单人有效韧性")
        assertClose(120 / 0.55, main.effectivePoise(BossPartySize.DUO), "双人有效韧性", 0.05)
        assertClose(400.0, main.effectivePoise(BossPartySize.TRIO), "三人有效韧性", 0.05)
    }

    @Test
    fun `poise = -1 不吃削韧时有效韧性为 null`() {
        val entry = rows.first { it.poise == -1.0 }
        val stats = entry.stats(BossPartySize.DUO)
        assertNull(stats.effectivePoise)
        assertEquals(BossPoiseKind.NONE, stats.poiseKind)
        assertEquals("不吃削韧", stats.poiseKind.placeholder)
        rows.forEach { row ->
            assertEquals(row.poiseKind == BossPoiseKind.VALUE, row.effectivePoise(BossPartySize.SOLO) != null, "${row.npcId}")
            assertTrue(row.poise >= 0 || row.effectivePoise(BossPartySize.DUO) == null)
        }
    }

    @Test
    fun `削韧恢复 异常发动伤害 异常累积按人数叠乘`() {
        val entry = rows.first { it.scaling?.trio != null && it.poiseRecover > 0 }
        val trio = entry.stats(BossPartySize.TRIO)
        val tier = entry.scaling!!.trio!!
        assertEquals(entry.poiseRecover * entry.poiseRecoverMultiplier * tier.poiseRecover, trio.poiseRecover)
        assertEquals(entry.ailmentDamageRateBase * tier.ailmentDamageRate, trio.ailmentDamageRate)
        assertEquals(tier.buildupRate, trio.ailmentBuildupRate)
        assertEquals(1.0, entry.stats(BossPartySize.SOLO).ailmentBuildupRate, "1 人时异常累积倍率为 1")
        // 硬编码期望值（公式被改坏时要能红）：格拉狄乌斯 0.29 × 0.2 × 档位倍率、0.5 × 档位倍率
        val main = BossTestData.row(75000020)
        assertClose(0.058, main.poiseRecoverSpeed(BossPartySize.SOLO), "单人削韧恢复", 1e-4)
        assertClose(0.0319, main.poiseRecoverSpeed(BossPartySize.DUO), "双人削韧恢复", 1e-4)
        assertClose(0.0174, main.poiseRecoverSpeed(BossPartySize.TRIO), "三人削韧恢复", 1e-4)
        assertClose(0.5, main.ailmentDamageRate(BossPartySize.SOLO), "单人异常发动伤害", 1e-4)
        assertClose(0.375, main.ailmentDamageRate(BossPartySize.DUO), "双人异常发动伤害", 1e-4)
        assertClose(0.25, main.ailmentDamageRate(BossPartySize.TRIO), "三人异常发动伤害", 1e-4)
        assertClose(0.7, main.ailmentBuildupRate(BossPartySize.TRIO), "三人异常累积", 1e-4)
        val stats = main.stats(BossPartySize.DUO)
        assertEquals(22656, stats.hp)
        assertClose(218.1818, stats.effectivePoise, "stats 双人有效韧性", 0.01)
        assertClose(1.0, stats.poisonDamageRate, "中毒 / 腐败发动倍率当前应为 1")
    }

    @Test
    fun `深夜 模式换成深度 1–5 血量直接取 depthStats N hp`() {
        assertEquals(listOf(null, 1, 2, 3, 4, 5), BossNightMode.entries.map { it.depth })
        assertEquals(BossNightMode.DEPTH3, BossNightMode.depth(3))
        assertEquals(BossNightMode.NORMAL, BossNightMode.depth(0))
        assertEquals(BossNightMode.NORMAL, BossNightMode.depth(9))
        assertFalse(BossNightMode.NORMAL.isDeepOfNight)
        assertTrue(BossNightMode.DEPTH1.isDeepOfNight)

        assertTrue(rows.all { it.hasDepthStats }, "394 条数值行全都有 depthStats")
        assertTrue(rows.all { it.availableDepths == listOf(1, 2, 3, 4, 5) })
        rows.forEach { row ->
            (1..5).forEach { depth ->
                val stats = row.stats(BossPartySize.SOLO, BossNightMode.depth(depth))
                assertEquals(depth, stats.mode.depth)
                assertFalse(stats.depthMissing)
                assertEquals(row.depthStats.getValue(depth).hp, stats.hp, "npcId ${row.npcId} 深度 $depth")
                assertEquals(row.depthStats.getValue(depth).attackRateBase, stats.attackRate)
            }
        }
        val deepEntry = rows.first { it.hasDeepOfNight }
        assertTrue(deepEntry.hp(BossPartySize.SOLO, BossNightMode.DEPTH1) > deepEntry.deepOfNight!!.hp)

        // 没有 depthStats 的行回落到常规值并标 depthMissing；小表为空（页面写「该行无深夜数值」）
        val bare = fight("""{"hp":1000,"hpBase":1000,"hpMultiplier":1,"poise":100,"poiseTakenBase":1}""")
        val bareStats = bare.stats(BossPartySize.SOLO, BossNightMode.DEPTH4)
        assertTrue(bareStats.depthMissing)
        assertEquals(1000, bareStats.hp)
        assertTrue(bare.depthRows(BossPartySize.SOLO).isEmpty())
        assertFalse(BossTestData.row(75000020).stats(BossPartySize.DUO, BossNightMode.DEPTH3).depthMissing)

        // 史柴格斯：深度 1 = 深夜修正 11555 × 1.25 = 14443
        val stray = BossTestData.row(76100010)
        assertEquals(14443, stray.hp)
        assertEquals(11555, stray.deepOfNight!!.hp)
        assertEquals(14443, stray.depthStats.getValue(1).hp)
        assertEquals(43329, stray.hp(BossPartySize.TRIO, BossNightMode.DEPTH1))
        assertClose(568.1818, stray.effectivePoise(BossPartySize.TRIO), "常规三人有效韧性", 0.01)
        assertClose(568.363953, stray.effectivePoise(BossPartySize.TRIO, BossNightMode.DEPTH1), "深度 1 三人有效韧性", 1e-4)
        assertClose(0.0174, stray.poiseRecoverSpeed(BossPartySize.TRIO, BossNightMode.DEPTH1), "深度 1 三人削韧恢复", 1e-4)
        assertClose(0.375, stray.ailmentDamageRate(BossPartySize.DUO, BossNightMode.DEPTH1), "深度 1 双人异常发动", 1e-4)
        assertEquals(stray.deepOfNight!!.permScalingIds, stray.baseline(BossNightMode.DEPTH3).permScalingIds)
        assertEquals(stray.permScalingIds, stray.baseline(BossNightMode.NORMAL).permScalingIds)
    }

    @Test
    fun `深夜 深度换算后再乘人数 有效韧性分母换成 depthStats N poiseTakenBase`() {
        val gladius = BossTestData.row(75000020)
        val depth5 = gladius.depthStats.getValue(5)
        val solo = gladius.stats(BossPartySize.SOLO, BossNightMode.DEPTH5)
        val trio = gladius.stats(BossPartySize.TRIO, BossNightMode.DEPTH5)
        assertEquals(depth5.hp, solo.hp)
        assertEquals((depth5.hp * gladius.scaling!!.trio!!.hp).roundHalfAway(), trio.hp)
        assertEquals(73404, trio.hp)
        assertEquals(24468, solo.hp)
        assertClose(gladius.poise / depth5.poiseTakenBase, solo.effectivePoise, "深度 5 单人有效韧性", 1e-9)
        assertClose(
            gladius.poise / (depth5.poiseTakenBase * gladius.scaling!!.trio!!.poiseTaken),
            trio.effectivePoise, "深度 5 三人有效韧性", 1e-9,
        )
        assertEquals(depth5.attackRateBase, trio.attackRate, "格拉狄乌斯档位多人不加攻击力")
        val d1 = gladius.stats(BossPartySize.SOLO, BossNightMode.DEPTH1)
        assertTrue(solo.attackRate / d1.attackRate > 2.2)
        assertTrue(solo.hp.toDouble() / d1.hp < 1.8)
        assertClose(2.6480, solo.attackRate / d1.attackRate, "深度 5 / 深度 1 的攻击力比", 1e-3)
        assertClose(3.36, gladius.attackRate(BossPartySize.SOLO), "格拉狄乌斯常规攻击力倍率", 1e-4)
        assertClose(4.2, gladius.attackRate(BossPartySize.SOLO, BossNightMode.DEPTH1), "深度 1 攻击力倍率", 1e-4)
        assertClose(11.1216, gladius.attackRate(BossPartySize.SOLO, BossNightMode.DEPTH5), "深度 5 攻击力倍率", 1e-4)
        (1..5).forEach { depth ->
            val mode = BossNightMode.depth(depth)
            assertEquals(gladius.depthStats.getValue(depth).hp * 3, gladius.hp(BossPartySize.TRIO, mode))
            assertClose(gladius.poise / gladius.depthStats.getValue(depth).poiseTakenBase, gladius.effectivePoise(BossPartySize.SOLO, mode), "深度 $depth 有效韧性", 1e-4)
        }
        val normal = gladius.stats(BossPartySize.SOLO, BossNightMode.NORMAL)
        assertNull(normal.mode.depth)
        assertFalse(normal.depthMissing)
        assertEquals(gladius.hp, normal.hp)
        assertEquals(gladius.attackRateBase, normal.attackRate)
    }

    @Test
    fun `深夜各深度小表 五行都按当前人数换算 当前深度可高亮`() {
        val bird = BossTestData.row(49800030)
        val table = bird.depthRows(BossPartySize.DUO)
        assertEquals(5, table.size)
        table.forEachIndexed { i, row ->
            assertEquals(i + 1, row.depth)
            assertEquals(bird.stats(BossPartySize.DUO, BossNightMode.depth(row.depth)).hp, row.hp)
            assertEquals(bird.depthStats.getValue(row.depth).attackRateBase * bird.scaling!!.duo!!.attackRate, row.attackRate)
            assertEquals(bird.depthStats.getValue(row.depth).poiseTakenBase * bird.scaling!!.duo!!.poiseTaken, row.poiseTaken)
        }
        for (i in 1 until table.size) {
            assertTrue(table[i].hp >= table[i - 1].hp)
            assertTrue(table[i].attackRate > table[i - 1].attackRate)
        }
        // 全量：单调不减，且小表与单点换算同源
        rows.forEach { row ->
            val solo = row.depthRows(BossPartySize.SOLO)
            solo.zipWithNext().forEach { (a, b) ->
                assertTrue(a.hp <= b.hp, "${row.npcId} 血量单调")
                assertTrue(a.attackRate <= b.attackRate + 1e-6, "${row.npcId} 攻击单调")
            }
            row.depthRows(BossPartySize.DUO).forEach { item ->
                assertEquals(row.hp(BossPartySize.DUO, BossNightMode.depth(item.depth)), item.hp)
                assertClose(row.attackRate(BossPartySize.DUO, BossNightMode.depth(item.depth)), item.attackRate, "小表攻击")
                assertEquals(row.effectivePoise(BossPartySize.DUO, BossNightMode.depth(item.depth)), item.effectivePoise)
            }
        }
    }

    @Test
    fun `变异个体 选中档位后在其它缩放之上再乘一层`() {
        assertEquals(10, dataset.mutations.size)
        assertTrue(dataset.mutations.all { (key, value) -> key == value.id })
        assertTrue(dataset.mutations.keys.all { it in 113000 until 114000 })
        assertEquals(setOf(7220, 7230, 7240, 7241), dataset.mutations.values.mapNotNull { it.statSpEffectId }.toSet())
        val withPool = rows.filter { it.canMutate }
        assertEquals(327, withPool.size, "327 条数值行能变异")
        withPool.forEach { row -> row.mutationPool.forEach { assertNotNull(dataset.mutation(it), "缺少档位 $it") } }
        assertTrue(rows.all { it.canMutate || dataset.mutations(it).isEmpty() })

        val bird = BossTestData.row(49800030)
        val mutation = dataset.mutation(113340)!!
        assertEquals(listOf(1.15, 1.15, 1.35), listOf(mutation.hp, mutation.attackRate, mutation.runeRate))
        val plain = bird.stats(BossPartySize.DUO, BossNightMode.DEPTH3)
        val mutated = bird.stats(BossPartySize.DUO, BossNightMode.DEPTH3, mutation)
        assertNull(plain.mutation)
        assertEquals(mutation, mutated.mutation)
        assertEquals((bird.depthStats.getValue(3).hp * bird.scaling!!.duo!!.hp * mutation.hp).roundHalfAway(), mutated.hp)
        assertEquals(5770, mutated.hp)
        assertClose(plain.attackRate * mutation.attackRate, mutated.attackRate, "变异攻击再乘一层")
        assertEquals(1.35, mutated.runeRate)
        assertEquals(1.0, plain.runeRate, "没选变异时卢恩倍率是 1")
        assertEquals(plain.effectivePoise, mutated.effectivePoise)
        assertEquals(plain.ailmentBuildupRate, mutated.ailmentBuildupRate)
        assertEquals(plain.ailmentDamageRate, mutated.ailmentDamageRate)

        // 选择器的编码 / 解码（rememberSaveable 存字符串）
        assertEquals(BossMutationChoice.Tier(113340), BossMutationChoice.decode("113340"))
        assertEquals(BossMutationChoice.None, BossMutationChoice.decode(""))
        assertEquals(BossMutationChoice.None, BossMutationChoice.decode(null))
        assertEquals(BossMutationChoice.Own, BossMutationChoice.decode(BossMutationChoice.Own.encode()))
        assertEquals("113340", BossMutationChoice.Tier(113340).encode())
        assertNull(dataset.mutation(999999))

        val m = dataset.mutation(113240)!!
        assertEquals("变异个体", m.nameZh)
        assertEquals("血量 ×1.15 · 攻击 ×1.15 · 卢恩 ×1.35", m.summary)
        assertEquals("#113240 · 血量 ×1.15 · 攻击 ×1.15 · 卢恩 ×1.35", m.pickerTitle)

        // 神皮使徒封印监牢行：全部人数 × 全部模式，变异只动血量 / 攻击 / 卢恩
        val apostleRow = BossTestData.row(35600020)
        val apostleMutation = dataset.mutation(113140)!!
        assertEquals(listOf(113140), dataset.mutations(apostleRow).map { it.id })
        assertEquals(7240, apostleMutation.statSpEffectId)
        BossPartySize.entries.forEach { players ->
            BossNightMode.entries.forEach { mode ->
                val p = apostleRow.stats(players, mode)
                val mm = apostleRow.stats(players, mode, apostleMutation)
                assertEquals((apostleRow.baseline(mode).hp * apostleRow.tier(players).hp * apostleMutation.hp).roundHalfAway(), mm.hp)
                assertClose(p.attackRate * apostleMutation.attackRate, mm.attackRate, "变异攻击")
                assertEquals(p.effectivePoise, mm.effectivePoise)
                assertEquals(p.ailmentDamageRate, mm.ailmentDamageRate)
                assertEquals(p.ailmentBuildupRate, mm.ailmentBuildupRate)
            }
        }
        // 各档位覆盖的行数（工具条选择器上的数字）
        val counts = index.mutationRowCounts()
        assertEquals(10, counts.size)
        assertEquals(327, counts.values.sum())
        assertEquals(80, counts[113240])
        assertEquals(26, counts[113140])
    }

    @Test
    fun `隐藏实体 默认不显示 开关打开后才出现`() {
        val hidden = index.hiddenCards
        assertEquals(
            listOf(
                "boss-Centipede Grub@7711", "boss-Lord of Blood Spear@4801",
                "boss-Unknown Enemy (c7931)@7931", "boss-Unknown Enemy (c7932)@7932",
            ),
            hidden.map { it.id }.sorted(),
        )
        hidden.forEach { card ->
            assertTrue(BossGroup.SUMMON in card.groups, "${card.id} 在「随从/召唤物」")
            assertTrue(card.groups.all { it.isHiddenByDefault })
            assertTrue(BossRoleCatalog.onlyHidden(card.roles))
            assertTrue(card.isHiddenByDefault)
        }
        BossGroup.visibleCases(false).forEach { group ->
            assertEquals(index.cards(group).size, index.cards(group, includeHidden = true).size, group.title)
        }
        assertEquals(0, index.cards(BossGroup.SUMMON, "7931").size)
        assertEquals(1, index.cards(BossGroup.SUMMON, "7931", includeHidden = true).size)
        val noRewardVisible = index.cards.filter { it.noReward && !it.hidden }
        assertEquals(
            listOf("boss-Dreg Wormface@7660", "boss-Giant Skeleton Torso@4960", "boss-Storm King@7910"),
            noRewardVisible.map { it.id }.sorted(),
        )
        assertTrue(noRewardVisible.all { it.isHiddenByDefault && BossRoleCatalog.onlyHidden(it.roles) })
    }

    @Test
    fun `承伤倍率分类 大于 1 弱点 小于 1 抗性 等于 1 正常`() {
        assertEquals(BossRateClass.WEAK, BossFormat.rateClass(1.35))
        assertEquals("弱点", BossFormat.rateClass(1.35).tag)
        assertEquals(BossRateClass.RESIST, BossFormat.rateClass(0.5))
        assertEquals("抗性", BossFormat.rateClass(0.5).tag)
        assertEquals(BossRateClass.FLAT, BossFormat.rateClass(1.0))
        assertNull(BossFormat.rateClass(1.0).tag)
        val main = BossTestData.row(75000020)
        assertClose(1.35, main.damageRates.holy, "格拉狄乌斯圣属性倍率")
        assertClose(0.5, main.damageRates.fire, "格拉狄乌斯火属性倍率")
        assertEquals(BossRateClass.WEAK, BossFormat.rateClass(main.damageRates.holy))
        assertEquals(BossRateClass.RESIST, BossFormat.rateClass(main.damageRates.fire))
        assertTrue(BossDamageKind.HOLY in main.damageRates.weakKinds)
        assertEquals(BossDamageKind.HOLY, main.damageRates.weakKinds.first())
        assertTrue(BossDamageKind.FIRE in main.damageRates.resistantKinds)
        val tie = BossDamageRates(standard = 1.2, slash = 1.2, fire = 1.2)
        assertEquals(listOf(BossDamageKind.STANDARD, BossDamageKind.SLASH, BossDamageKind.FIRE), tie.weakKinds)
        assertEquals("圣", dataset.title(BossDamageKind.HOLY))
        assertEquals("猩红腐败", dataset.title(BossAilmentKind.ROT))
        assertEquals(BossDamageKind.STANDARD.titleZh, dataset.title(BossDamageKind.STANDARD))
    }

    @Test
    fun `异常抗性 999 判为免疫 并与 immune 列表一致`() {
        val resist = BossResistances(madness = 999, bleed = 542)
        assertTrue(resist.isImmune(BossAilmentKind.MADNESS))
        assertFalse(resist.isImmune(BossAilmentKind.BLEED))
        rows.forEach { row ->
            val immune = BossAilmentKind.entries.filter { row.resist.isImmune(it) }.map { it.key }.sorted()
            assertEquals(row.immune.sorted(), immune, "immune 列表应等于 resist 里 999 的项：${row.npcId}")
            assertEquals(row.immune.sorted(), row.immuneKinds().map { it.key }.sorted())
        }
        val main = BossTestData.row(75000020)
        assertEquals(setOf(BossAilmentKind.MADNESS, BossAilmentKind.DEATH), main.immuneKinds().toSet())
    }

    @Test
    fun `名字四级回退 nameZh → nameZhFallback → displayFallbackZh → nameEn`() {
        val zhNamed = index.cards.first { !it.isNightlord && it.nameZh.isNotEmpty() && it.nameSource == "npcname" }
        assertEquals(zhNamed.nameZh, zhNamed.displayName)
        assertEquals(zhNamed.nameEn, zhNamed.subtitleName)
        assertFalse(zhNamed.usesNameFallback || zhNamed.usesDisplayFallback)
        assertTrue(zhNamed.nameBadges.isEmpty() || zhNamed.nameInferred || zhNamed.nameApprox)

        val hippo = BossTestData.boss("Large Golden Hippopotamus@5010")
        assertEquals("", hippo.nameZh)
        assertEquals("大型黄金河马", hippo.nameZhFallback)
        assertEquals("大型黄金河马", hippo.displayName)
        assertEquals("Large Golden Hippopotamus", hippo.subtitleName)
        assertTrue(hippo.usesNameFallback)
        assertEquals(listOf(BossNameBadge.ENGLISH_ONLY, BossNameBadge.FALLBACK), hippo.nameBadges)
        assertTrue(index.cards.any { it.nameZh == "黄金河马" })

        val placeholder = index.cards.filter { it.usesDisplayFallback }
        assertEquals(listOf("boss-Unknown Enemy (c7931)@7931", "boss-Unknown Enemy (c7932)@7932"), placeholder.map { it.id }.sorted())
        val unknown = BossTestData.boss("Unknown Enemy (c7931)@7931")
        assertEquals("", unknown.nameZh)
        assertEquals("未知敌人 c7931", unknown.displayFallbackZh)
        assertEquals("未知敌人 c7931", unknown.displayName)
        assertEquals("Unknown Enemy (c7931)", unknown.subtitleName)
        assertFalse(unknown.usesNameFallback)
        assertEquals(listOf(BossNameBadge.NO_GAME_NAME), unknown.nameBadges)
        assertEquals("无游戏内名称", unknown.nameBadge?.text)

        val greyoll = BossTestData.boss("Elder Dragon Greyoll@4504")
        assertEquals("Elder Dragon Greyoll", greyoll.displayName)
        assertNull(greyoll.subtitleName)

        // 四级全空才自己拼 chrId
        val blank = BossTestData.indexOf("""{"nightBosses":[{"nameEn":"","chrIds":[4242],"tier":"field","variants":[{"npcId":1,"labelZh":"甲"}]}]}""")
        assertEquals("未知敌人 c4242", blank.cards.single().displayName)
        val none = BossTestData.indexOf("""{"nightBosses":[{"nameEn":"","variants":[{"npcId":1}]}]}""")
        assertEquals("未知敌人", none.cards.single().displayName)

        index.cards.filter { !it.isNightlord }.forEach { card ->
            val expected = listOf(card.nameZh, card.nameZhFallback, card.displayFallbackZh, card.nameEn).first { it.isNotEmpty() }
            assertEquals(expected, card.displayName, card.id)
            assertEquals(if (card.nameEn == expected) null else card.nameEn, card.subtitleName, card.id)
        }
        val fallbackCards = index.cards.filter { it.usesNameFallback }
        assertEquals(14, fallbackCards.size, "14 组走参考译名那一级")
        assertTrue(fallbackCards.all { it.nameZhFallbackNote.isNotEmpty() && it.displayName == it.nameZhFallback })
        assertTrue(index.cards.all { it.nameZh.isEmpty() || !it.usesNameFallback })
        val englishTitled = index.cards.filter {
            !it.isNightlord && it.nameZh.isEmpty() && it.nameZhFallback.isEmpty() && it.displayFallbackZh.isEmpty()
        }
        assertEquals(5, englishTitled.size, "5 组只剩英文名")
        assertTrue(englishTitled.all { it.displayName == it.nameEn && it.subtitleName == null })
        val putrid = BossTestData.boss("Putrid Flesh@4171")
        assertEquals(BossNameBadge.ENGLISH_ONLY, putrid.nameBadge)
        assertEquals("Putrid Flesh", putrid.displayName)
        val troll = BossTestData.boss("Troll@4600")
        assertEquals("山妖", troll.displayName)
        assertEquals("Troll", troll.subtitleName)
        assertEquals(listOf(BossNameBadge.ENGLISH_ONLY, BossNameBadge.FALLBACK), troll.nameBadges)
    }

    @Test
    fun `名称徽标 两层判定 名字缺不缺 身份谁认的 + 近似匹配 + 参考译名`() {
        val storm = BossTestData.boss("Storm King@7910")
        assertEquals("community", storm.nameSource)
        assertEquals("", storm.nameZh)
        assertEquals(listOf(BossNameBadge.NO_GAME_NAME, BossNameBadge.COMMUNITY), storm.nameBadges)
        listOf("Elder Dragon Greyoll@4504", "Centipede Grub@7711").forEach { id ->
            assertEquals(listOf("无游戏内名称", "社区资料"), BossTestData.boss(id).nameBadges.map { it.text }, id)
        }
        assertTrue(
            index.cards.filter { it.nameSource.startsWith("community") && it.nameZh.isEmpty() }
                .all { it.nameBadges == listOf(BossNameBadge.NO_GAME_NAME, BossNameBadge.COMMUNITY) },
        )
        val greyoll = BossTestData.boss("Elder Dragon Greyoll@4504")
        assertTrue(greyoll.nameSourceUrl.isNotEmpty())

        val digger = BossTestData.boss("Stonedigger Troll@4603")
        assertEquals("挖石山妖", digger.nameZh)
        assertEquals("community-npcname", digger.nameSource)
        assertNotNull(digger.nameEvidence)
        assertTrue(digger.nameBadges.isEmpty())

        assertEquals(7, index.cards.count { it.showsApproxBadge })
        val dragon = BossTestData.boss("Flying Dragon@4500")
        assertTrue(dragon.nameApprox)
        assertEquals(listOf(BossNameBadge.APPROX), dragon.nameBadges)
        assertNotNull(dragon.nameEvidence)
        val wormface = BossTestData.boss("Large Wormface@4580")
        assertTrue(wormface.showsApproxBadge && wormface.nameEvidence != null)

        val inferred = BossTestData.indexOf(
            """{"nightBosses":[{"nameZh":"某某","nameEn":"Whoever","nameSource":"npcname","nameInferred":true,"chrIds":[1],"variants":[{"npcId":1}]}]}""",
        ).cards.single()
        assertEquals(listOf(BossNameBadge.INFERRED), inferred.nameBadges)
        assertEquals(listOf(BossNameBadge.INFERRED), BossTestData.boss("Horned Warrior@5250").nameBadges)
        val manual = BossTestData.indexOf(
            """{"nightBosses":[{"nameZh":"某某","nameEn":"Whoever","nameSource":"manual","chrIds":[1],"variants":[{"npcId":1}]}]}""",
        ).cards.single()
        assertEquals(listOf(BossNameBadge.MANUAL), manual.nameBadges)

        val shade = BossTestData.boss("Cemetery Shade@3664")
        assertEquals("english-only", shade.nameSource)
        assertTrue(shade.nameInferred)
        assertEquals(listOf("仅英文名", "参考译名 · 非本作游戏文本"), shade.nameBadges.map { it.text })

        index.cards.forEach { card ->
            assertEquals(card.usesNameFallback, BossNameBadge.FALLBACK in card.nameBadges, card.id)
        }
        assertTrue(index.cards(BossGroup.NIGHTLORD, includeHidden = true).all { it.nameBadges.isEmpty() && !it.showsApproxBadge })
        assertNull(index.cards(BossGroup.NIGHT).first { it.nameSource == "npcname" && !it.nameInferred && !it.nameApprox }.nameBadge)
        val hippo = BossTestData.boss("Large Golden Hippopotamus@5010")
        assertTrue(hippo.nameNote.isNotEmpty(), "让出 nameZh 的原因要能显示在展开区")
        val rejected = index.cards.filter { it.nameZhRejected != null }
        assertEquals(4, rejected.size)
        assertTrue(rejected.all { it.nameNote.isNotEmpty() && it.nameZh.isEmpty() })
    }

    @Test
    fun `搜索索引收进 nameZhFallback 搜河马仍能搜到让出中文名的那一组`() {
        assertTrue(index.cards(BossGroup.STRONGHOLD, "河马").any { it.id == "boss-Large Golden Hippopotamus@5010" })
        assertTrue(index.cards(BossGroup.STRONGHOLD, "山妖").any { it.id == "boss-Troll@4600" })
        val withFallback = index.cards.filter { it.nameZhFallback.isNotEmpty() }
        assertEquals(14, withFallback.size)
        withFallback.forEach { card ->
            val found = index.cards(card.groups.first(), card.nameZhFallback, includeHidden = true)
            assertTrue(found.any { it.id == card.id }, "搜不到参考译名：${card.nameZhFallback}")
        }
    }

    @Test
    fun `buildItems 夜王与首领组各一张卡片 主键用 id 而不是 nameEn`() {
        assertEquals(dataset.nightlords.size + dataset.nightBosses.size, index.cards.size)
        assertEquals(index.cards.size, index.cards.map { it.id }.toSet().size, "id 必须唯一")
        assertEquals(dataset.nightBosses.size, dataset.nightBosses.map { it.id }.toSet().size)
        index.cards.forEach { card ->
            assertTrue(card.groups.isNotEmpty(), "${card.id} 至少属于一个分组")
            assertEquals(card.group, card.groups.first())
            assertEquals(card.isNightlord, card.group == BossGroup.NIGHTLORD, card.id)
            assertNotNull(card.primaryRow, "每张卡片都要有代表数值行：${card.id}")
        }
        assertEquals(dataset.nightlords.size, index.cards.count { it.group == BossGroup.NIGHTLORD })
        assertEquals(dataset.nightBosses.size, index.cards.count { it.kind == BossCardKind.BOSS })
        val nameEn = dataset.nightBosses.map { it.nameEn }
        assertTrue(nameEn.toSet().size < nameEn.size, "nameEn 本就不唯一")
        assertTrue(dataset.nightBosses.all { it.tier == "night" || it.tier == "field" })
        assertTrue(dataset.nightBosses.all { it.variants.isNotEmpty() })
        assertTrue(dataset.nightlords.all { it.fights.isNotEmpty() })
    }

    @Test
    fun `夜王卡片带远征名与变体名 永夜之王用 variantKey 判定`() {
        val everdark = dataset.nightlords.first { it.variantKey == "everdark" }
        val card = BossTestData.lord(everdark.menuId)
        assertEquals(everdark.variantNameZh, card.variantNameZh)
        assertEquals("永夜之王", card.variantNameZh)
        assertTrue(card.isEverdark)
        assertEquals(everdark.expeditionZh, card.expeditionZh)
        val bearers = dataset.nightlords.first { it.variantKey == "standardBearers" }
        assertFalse(bearers.everdark)
        assertEquals("救世旗手", BossTestData.lord(bearers.menuId).variantNameZh)
        assertFalse(BossTestData.lord(bearers.menuId).isEverdark)
        val normal = BossTestData.lord(0)
        assertEquals("", normal.variantNameZh)
        assertEquals("三头野兽", normal.expeditionZh)
        assertTrue(dataset.nightlords.any { it.isEverdark })
    }

    @Test
    fun `filterItems 按分组过滤 中文英文名都能搜到`() {
        assertEquals(dataset.nightlords.size, index.cards(BossGroup.NIGHTLORD).size)
        val zh = index.cards(BossGroup.NIGHTLORD, "格拉狄乌斯")
        assertTrue(zh.size >= 2, "普通形态与永夜之王都应命中")
        assertTrue(zh.all { it.displayName == "格拉狄乌斯" })
        assertEquals(zh.size, index.cards(BossGroup.NIGHTLORD, "GLADIUS").size, "英文名大小写不敏感")
        assertTrue(index.cards(BossGroup.NIGHTLORD, " Gladius ").any { it.nameEn == "Gladius" })
        assertTrue(index.cards(BossGroup.NIGHTLORD, "格拉").any { it.nameZh == "格拉狄乌斯" })
        assertTrue(index.cards(BossGroup.NIGHTLORD, "三头野兽").isNotEmpty(), "远征名也应可搜")
        assertEquals(0, index.cards(BossGroup.FIELD, "绝无此物").size)
        assertTrue(index.cards(BossGroup.NIGHTLORD, "不存在的首领名").isEmpty())
    }

    @Test
    fun `数字格式化`() {
        assertEquals("11,328", BossFormat.integer(11328))
        assertEquals("176", BossFormat.integer(176))
        assertEquals("1,234,567", BossFormat.integer(1234567))
        assertEquals("0.5", BossFormat.decimal(0.5, 2))
        assertEquals("1.35", BossFormat.decimal(1.35, 2))
        assertEquals("—", BossFormat.decimal(Double.NaN, 2))
        assertEquals("×2", BossFormat.multiplier(2.0))
        assertEquals("×0.889", BossFormat.multiplier(0.889))
        assertEquals("218.2", BossFormat.decimal(218.18181818, 1))
    }

    @Test
    fun `每条数值行都能算出有限的血量 且档位 id 能查到 scalingTiers`() {
        assertTrue(rows.size >= 300)
        rows.forEach { row ->
            BossPartySize.entries.forEach { players ->
                val stats = row.stats(players)
                assertTrue(stats.hp > 0, "血量必须是正数：${row.npcId}")
                assertTrue(stats.ailmentDamageRate.isFinite())
            }
            row.scalingId?.let { assertNotNull(dataset.scalingGroup(it), "scalingTiers 缺少档位 $it") }
            assertTrue(row.displayLabel.isNotEmpty())
            assertTrue(row.hp >= 0)
            row.chaosCorrectId?.let { assertNotNull(dataset.depthTier(it), "深度档位缺少 $it") }
        }
        assertEquals(14, rows.count { it.chaosCorrectId != null && it.chaosCorrectId != it.scalingId })
    }

    @Test
    fun `weakness 只有夜王有 守夜野外 Boss 不得被写成官方标注无弱点`() {
        index.cards.forEach { card ->
            if (card.isNightlord) {
                assertNotNull(card.menuId)
            } else {
                assertTrue(card.weakness.isEmpty(), "守夜 / 野外 Boss 没有官方弱点数据")
                assertNull(card.depthChanceWeights)
            }
        }
        val gladius = dataset.nightlords.first { it.nameZh == "格拉狄乌斯" && !it.isEverdark }
        assertTrue(gladius.weakness.any { it.zh == "圣" })
        assertEquals("本作只给夜王官方弱点标注；展开看承伤倍率", BossPageText.nightlordOnlyWeakness)
        assertEquals("官方标注：无弱点", BossPageText.noOfficialWeakness)
    }

    @Test
    fun `承伤偏高 代表行 damageRates 大于 1 的属性按倍率降序取前几个`() {
        val card = index.cards.first()
        val row = fight("""{"npcId":1,"damageRates":{"standard":1,"fire":2,"holy":1.4,"magic":0.5}}""")
        assertEquals(listOf(BossDamageKind.FIRE to 2.0, BossDamageKind.HOLY to 1.4), card.hotRates(row))
        assertTrue(card.hotRates(fight("""{"npcId":1,"damageRates":{"standard":1,"fire":0.9}}""")).isEmpty())
        assertTrue(card.hotRates(null).isEmpty())
        val hot = index.cards.filter { !it.isNightlord && it.hotRates(it.primaryRow).isNotEmpty() }
        assertTrue(hot.size > 60, "代表行承伤 > 1 的 Boss 应该很多，实际 ${hot.size}")
    }

    @Test
    fun `深夜徽标扫描整张卡 代表行没有深夜值不等于整张卡没有`() {
        val gnoster = BossTestData.lord(12)
        assertEquals(BossDeepCoverage.SOME, gnoster.deepOfNightCoverage)
        assertEquals("部分行有深夜专属修正", gnoster.deepOfNightCoverage.exclusiveBadgeText)
        assertEquals(BossDeepCoverage.ALL, gnoster.deepCoverage)
        assertEquals(BossRowText.deepRowBadge, gnoster.deepCoverage.badgeText)
        val allDeep = index.cards.first { it.rows.isNotEmpty() && it.rows.all { r -> r.hasDeepOfNight } }
        assertEquals(BossDeepCoverage.ALL, allDeep.deepOfNightCoverage)
        assertEquals(BossRowText.deepExclusiveBadge, allDeep.deepOfNightCoverage.exclusiveBadgeText)
        val noDeep = index.cards.first { it.rows.isNotEmpty() && it.rows.none { r -> r.hasDeepOfNight } }
        assertEquals(BossDeepCoverage.NONE, noDeep.deepOfNightCoverage)

        val misjudged = index.cards.filter { card ->
            card.deepOfNightCoverage != BossDeepCoverage.NONE && card.groups.any { group ->
                !group.isHiddenByDefault && card.representativeRow(group)?.hasDeepOfNight != true
            }
        }
        assertEquals(
            listOf("boss-Curseblade@5040", "boss-Death Knight@5070", "boss-Divine Beast Warrior@5250"),
            misjudged.map { it.id }.sorted(),
        )
        misjudged.forEach { assertEquals(false, it.representativeRow(BossGroup.STRONGHOLD)?.hasDeepOfNight, it.id) }
        listOf("boss-Curseblade@5040" to 50400120, "boss-Death Knight@5070" to 50701010, "nightlord-18" to 76200210).forEach { (id, npcId) ->
            val card = BossTestData.card(id)
            val main = card.representativeRow(card.group)!!
            assertEquals(npcId, main.npcId, id)
            assertTrue(main.hasDeepOfNight, "$id 的代表行自己带深夜修正")
        }
        assertEquals(22, index.cards.count { it.deepOfNightCoverage != BossDeepCoverage.NONE })
        assertEquals(4, index.cards.count { it.deepOfNightCoverage == BossDeepCoverage.ALL })
        assertEquals("深夜数值", BossDeepCoverage.ALL.badgeText)
        assertEquals("部分行有深夜数值", BossDeepCoverage.SOME.badgeText)
        assertNull(BossDeepCoverage.NONE.badgeText)
        assertEquals("深夜专属修正", BossDeepCoverage.ALL.exclusiveBadgeText)
        assertEquals("部分行有深夜专属修正", BossDeepCoverage.SOME.exclusiveBadgeText)
        assertNull(BossDeepCoverage.NONE.exclusiveBadgeText)
    }

    @Test
    fun `深夜数值并非夜王独有 守夜首领据点首领里也有带 deepOfNight 的条目`() {
        assertTrue(dataset.nightBosses.flatMap { it.variants }.any { it.hasDeepOfNight })
        val deepBossCards = index.cards.filter { !it.isNightlord && it.deepOfNightCoverage != BossDeepCoverage.NONE }
        assertEquals(12, deepBossCards.size)
        assertTrue(deepBossCards.any { BossGroup.NIGHT in it.groups })
        assertTrue(deepBossCards.any { BossGroup.STRONGHOLD in it.groups })
    }

    @Test
    fun `分组不再看 tiers tier 只是缩放档位 与出场场合对不上`() {
        assertEquals(listOf(BossGroup.STRONGHOLD), BossDataIndex.groups(listOf("stronghold")))
        assertEquals(listOf(BossGroup.NIGHT, BossGroup.OTHER), BossDataIndex.groups(listOf("night", "tower")))
        assertEquals(listOf(BossGroup.OTHER), BossDataIndex.groups(emptyList()))

        val flying = BossTestData.boss("Flying Dragon@4500")
        assertEquals(listOf("night"), flying.tiers)
        assertEquals(listOf(BossGroup.FIELD), flying.groups.filter { !it.isHiddenByDefault })
        assertEquals(listOf(BossGroup.STRONGHOLD), BossTestData.boss("Putrid Avatar@4811").groups.filter { !it.isHiddenByDefault })
        val carian = BossTestData.boss("Royal Carian Knight@3252")
        assertEquals(listOf("night"), carian.tiers)
        assertEquals(listOf(BossGroup.FIELD, BossGroup.UNPLACED), carian.groups)
        assertTrue(index.cards(BossGroup.NIGHT, includeHidden = true).none { it.id == carian.id })
        val crucible = BossTestData.boss("Crucible Knight@2500")
        assertEquals(listOf("field"), crucible.tiers)
        assertEquals(
            listOf(BossGroup.NIGHT, BossGroup.STRONGHOLD, BossGroup.EVERGAOL, BossGroup.OTHER),
            crucible.groups.filter { !it.isHiddenByDefault },
        )
        assertFalse(BossGroup.FIELD in crucible.groups)
        val large = BossTestData.boss("Large Golden Hippopotamus@5010")
        assertEquals(listOf("field", "night"), large.tiers)
        assertEquals(listOf(BossGroup.STRONGHOLD, BossGroup.UNPLACED), large.groups)
        assertTrue(index.cards(BossGroup.STRONGHOLD, "Golden Hippopotamus").any { it.id == large.id })
        assertEquals("", large.nameZh)
        assertEquals("english-only", large.nameSource)
        assertEquals("大型黄金河马", large.nameZhFallback)
        // 神皮使徒：4 条变体 threat = field，却没有一行的场合是场景头目
        val apostle = BossTestData.boss("Godskin Apostle@3560")
        assertEquals(4, apostle.rows.count { it.threat == "field" })
        assertTrue(index.cards(BossGroup.FIELD, "神皮使徒").none { it.id == apostle.id })
    }

    @Test
    fun `搜索串不含 nameSource 内部枚举值`() {
        listOf("npcname", "chrid-fallback", "npcparam-nameid", "english-only").forEach { token ->
            assertEquals(0, index.cards(BossGroup.NIGHT, token).size, "「$token」是内部枚举值")
        }
        assertTrue(index.cards(BossGroup.NIGHT, "7800").isNotEmpty(), "chrId 仍可搜")
        val zhNamed = index.cards.first { !it.isNightlord && it.nameZh.isNotEmpty() && it.nameSource != "chrid-fallback" }
        assertTrue(index.cards(BossGroup.NIGHT, zhNamed.nameZh).size + index.cards(BossGroup.FIELD, zhNamed.nameZh).size > 0)
    }

    @Test
    fun `poise = 0 与 poise = -1 语义分开 无削韧槽 ≠ 不吃削韧`() {
        val zeroRows = rows.filter { it.poise == 0.0 }
        assertEquals(2, zeroRows.size)
        assertEquals(5, rows.count { it.poise < 0 })
        val zero = BossTestData.row(79310000)
        assertEquals(BossPoiseKind.ZERO, zero.poiseKind)
        assertNull(zero.effectivePoise(BossPartySize.DUO))
        assertNull(zero.stats(BossPartySize.DUO).effectivePoise)
        assertEquals("无削韧槽", zero.poiseKind.placeholder)
        val negative = rows.first { it.poise == -1.0 }
        assertEquals(BossPoiseKind.NONE, negative.poiseKind)
        assertEquals("不吃削韧", negative.poiseKind.placeholder)
        assertEquals(BossPoiseKind.VALUE, rows.first { it.poise > 0 }.poiseKind)
    }

    @Test
    fun `夜王代表行取主战行里血量最高的一条 而不是第一条`() {
        val multiMain = index.cards(BossGroup.NIGHTLORD, includeHidden = true).filter { it.hasMultipleMainRows }
        assertEquals(5, multiMain.size)
        multiMain.forEach { card ->
            val mains = card.mainRows.filter { "nightlord" in it.roles }
            val rep = card.representativeRow(BossGroup.NIGHTLORD)!!
            assertTrue(rep.isMain)
            assertEquals(mains.maxOf { it.hp }, rep.hp, card.displayName)
        }
        val bearers = BossTestData.lord(18)
        assertEquals(listOf("unplaced"), bearers.rows.first { it.npcId == 46410000 }.roles)
        assertEquals(76200210, bearers.representativeRow(BossGroup.NIGHTLORD)!!.npcId)
        val maris = BossTestData.lord(13)
        assertEquals("玛利斯", maris.nameZh)
        assertEquals("永夜之王", maris.variantNameZh)
        assertEquals(2, maris.mainRows.size)
        assertEquals(3172, maris.mainRows.first().hp, "首条 isMain 确实是血量更低的一阶段")
        assertEquals(75410000, maris.representativeRow(BossGroup.NIGHTLORD)!!.npcId)
        assertEquals(29453, maris.primaryRow!!.hp)
        val gnoster = BossTestData.lord(12)
        assertEquals(5, gnoster.mainRows.size)
        assertEquals(8564, gnoster.representativeRow(BossGroup.NIGHTLORD)!!.hp)
        assertEquals(2, maris.rows(BossGroup.NIGHTLORD).size)
        assertEquals(1, BossTestData.lord(0).rows(BossGroup.NIGHTLORD).size)

        val tie = listOf(
            fight("""{"npcId":20,"hp":100,"isMain":true}"""),
            fight("""{"npcId":10,"hp":100,"isMain":true}"""),
            fight("""{"npcId":1,"hp":90,"isMain":true}"""),
        )
        assertEquals(10, BossCard.representativeRow(tie, BossGroup.NIGHTLORD)!!.npcId, "同血量按 npcId 升序兜底")
    }

    @Test
    fun `首领卡片的代表行随分组切换 按 roles 过滤 不再恒取 variants 0`() {
        val apostle = BossTestData.boss("Godskin Apostle@3560")
        assertEquals(35600900, apostle.rows.first().npcId, "rows[0] 是未放置的模板行")
        assertEquals("night", apostle.rows.first().threat)
        assertTrue(apostle.rows.first { it.npcId == 35600900 }.noReward)
        val night = apostle.representativeRow(BossGroup.NIGHT)!!
        assertEquals(35600010, night.npcId)
        assertEquals(listOf("night", "tower"), night.roles)
        val evergaol = apostle.representativeRow(BossGroup.EVERGAOL)!!
        assertEquals(35600110, evergaol.npcId)
        assertEquals("night", evergaol.threat, "封印监牢行挂的是守夜档位——threat 不能拿来分组")
        assertEquals(35600050, apostle.representativeRow(BossGroup.STRONGHOLD)!!.npcId)
        assertEquals("field", apostle.representativeRow(BossGroup.STRONGHOLD)!!.threat)
        assertEquals(
            listOf(35600010, 35600050, 35600110, 35600000),
            listOf(BossGroup.NIGHT, BossGroup.STRONGHOLD, BossGroup.EVERGAOL, BossGroup.UNPLACED).map { apostle.representativeRow(it)!!.npcId },
        )
        index.cards.forEach { card ->
            card.groups.forEach { group ->
                val rep = assertNotNull(card.representativeRow(group), "${card.id} / ${group.title}")
                assertTrue(group.rolesIn(rep.roles).isNotEmpty() || card.rows.none { it.belongs(group) }, "${card.id} / ${group.title} → ${rep.npcId}")
            }
        }
        val single = index.cards.first { card ->
            !card.isNightlord && card.roles.size == 1 && card.rows.size > 1 &&
                card.rows.all { !it.noReward && !it.isStagingRow && !it.isMain }
        }
        assertEquals(single.rows.maxOf { it.hp }, single.representativeRow(single.group)!!.hp)
        assertEquals(2, apostle.rows(BossGroup.STRONGHOLD).size, "据点首领两行")
        assertEquals(listOf(35600020, 35600110), apostle.rows(BossGroup.EVERGAOL).map { it.npcId }.sorted())
        assertEquals(apostle.rows.size - 2, apostle.rows(BossGroup.NIGHTLORD).size, "分组里没有一行对得上时整池放行（再排掉 2 条无奖励行）")
        assertEquals(2, BossTestData.lord(13).rows(BossGroup.NIGHTLORD).size)
    }

    @Test
    fun `代表行第三步 排掉登场演出 血条实体 教程行`() {
        assertEquals(listOf("登场演出", "血条实体", "教程"), BossFight.STAGING_LABEL_KEYWORDS)
        val staging = rows.filter { it.isStagingRow }
        assertEquals(
            listOf(21300520, 35500020, 36000010, 36001010, 42600110, 44600015, 45050020, 45601020, 46300030, 71000115),
            staging.map { it.npcId }.sorted(),
            "数据里共 10 条演出行",
        )
        assertEquals(7, staging.count { !it.noReward }, "其中 7 条照样掉奖励")
        val crow = BossTestData.boss("Giant Crow@4560")
        val crowStaging = crow.rows.first { it.npcId == 45601020 }
        assertEquals("血条实体", crowStaging.labelZh)
        assertFalse(crowStaging.noReward)
        assertEquals(2117, crowStaging.hp)
        assertEquals(listOf("field"), crowStaging.roles)
        assertEquals(45601010, crow.representativeRow(BossGroup.FIELD)!!.npcId)
        assertEquals(1779, crow.representativeRow(BossGroup.FIELD)!!.hp)
        val sanguine = BossTestData.boss("Sanguine Noble@3550")
        val sanguineStaging = sanguine.rows.first { it.npcId == 35500020 }
        assertEquals("鲜血君王 · 登场演出", sanguineStaging.labelZh)
        assertEquals(listOf("prelude"), sanguineStaging.roles)
        assertEquals(35500020, sanguine.representativeRow(BossGroup.OTHER)!!.npcId)
        assertTrue(sanguine.rows(BossGroup.OTHER).all { it.isStagingRow })
        assertEquals(35500040, sanguine.representativeRow(BossGroup.STRONGHOLD)!!.npcId)
        assertTrue(crow.rows.any { it.npcId == 45601020 }, "展开区不隐藏演出行")

        val allStaging = listOf(
            fight("""{"npcId":2,"hp":100,"labelZh":"教程"}"""),
            fight("""{"npcId":1,"hp":300,"labelZh":"血条实体"}"""),
        )
        assertEquals(2, BossCard.candidateRows(allStaging, null).size)
        assertEquals(1, BossCard.representativeRow(allStaging, null)!!.npcId)

        index.cards.forEach { card ->
            card.groups.forEach { group ->
                val pool = card.rows(group)
                val primary = card.representativeRow(group)!!
                assertTrue(!primary.isStagingRow || pool.all { it.isStagingRow }, "${card.id} / ${group.title}")
                assertTrue(!primary.noReward || pool.all { it.noReward }, "${card.id} / ${group.title}")
            }
        }
    }

    @Test
    fun `代表行对照表 卡片 + 分组 → npcId 与 macOS 的 representativeCases 同一张`() {
        val cases = listOf(
            Triple("nightlord-0", BossGroup.NIGHTLORD, 75000020),
            Triple("nightlord-3", BossGroup.NIGHTLORD, 75400020),
            Triple("nightlord-6", BossGroup.NIGHTLORD, 49000010),
            Triple("nightlord-7", BossGroup.NIGHTLORD, 75802010),
            Triple("nightlord-18", BossGroup.NIGHTLORD, 76200210),
            Triple("boss-Bell Bearing Hunter@3100", BossGroup.NIGHT, 31000020),
            Triple("boss-Bell Bearing Hunter@3100", BossGroup.FIELD, 31000010),
            Triple("boss-Bell Bearing Hunter@3100", BossGroup.STRONGHOLD, 31000040),
            Triple("boss-Bell Bearing Hunter@3100", BossGroup.OTHER, 31000020),
            Triple("boss-Bell Bearing Hunter@3100", BossGroup.UNPLACED, 31000000),
            Triple("boss-Large Golden Hippopotamus@5010", BossGroup.STRONGHOLD, 50100010),
            Triple("boss-Large Golden Hippopotamus@5010", BossGroup.UNPLACED, 50100000),
            Triple("boss-Godskin Apostle@3560", BossGroup.NIGHT, 35600010),
            Triple("boss-Godskin Apostle@3560", BossGroup.STRONGHOLD, 35600050),
            Triple("boss-Godskin Apostle@3560", BossGroup.EVERGAOL, 35600110),
            Triple("boss-Godskin Apostle@3560", BossGroup.UNPLACED, 35600000),
            Triple("boss-Giant Crow@4560", BossGroup.FIELD, 45601010),
            Triple("boss-Morgott@2130", BossGroup.OTHER, 21300510),
            Triple("boss-Morgott@2130", BossGroup.NIGHT, 21300510),
            Triple("boss-Sanguine Noble@3550", BossGroup.OTHER, 35500020),
            Triple("boss-Sanguine Noble@3550", BossGroup.STRONGHOLD, 35500040),
            Triple("boss-Flame Chariot@4460", BossGroup.STRONGHOLD, 44600010),
            Triple("boss-Flame Chariot@4460", BossGroup.FIELD, 44600000),
            Triple("boss-Flame Chariot@4460", BossGroup.UNPLACED, 44600000),
            Triple("boss-Death Rite Bird@4980", BossGroup.FIELD, 49801040),
            Triple("boss-Death Rite Bird@4980", BossGroup.STRONGHOLD, 49801040),
            Triple("boss-Death Rite Bird@4980", BossGroup.EVERGAOL, 49801030),
            Triple("boss-Death Rite Bird@4980", BossGroup.NIGHT, 49801010),
            Triple("boss-Sanguine Noble@3550", BossGroup.UNPLACED, 35500030),
        )
        assertEquals(29, cases.size, "与 macOS 的 representativeCases 同样 29 条")
        cases.forEach { (id, group, npcId) ->
            val card = BossTestData.card(id)
            assertTrue(group in card.groups, "$id 确实出现在 ${group.title}")
            assertEquals(npcId, card.representativeRow(group)?.npcId, "$id / ${group.title}")
        }
        // 独立重写一遍规则顺序（场合 → 分组的对应不借用 belongs）
        val roleToGroup = mapOf(
            "nightlord" to BossGroup.NIGHTLORD, "night" to BossGroup.NIGHT, "stronghold" to BossGroup.STRONGHOLD,
            "field" to BossGroup.FIELD, "evergaol" to BossGroup.EVERGAOL, "summon" to BossGroup.SUMMON,
            "unplaced" to BossGroup.UNPLACED,
        )
        index.cards.forEach { card ->
            card.groups.forEach { group ->
                var pool = card.rows
                pool.filter { row -> row.roles.any { (roleToGroup[it] ?: BossGroup.OTHER) == group } }.takeIf { it.isNotEmpty() }?.let { pool = it }
                pool.filter { it.isMain }.takeIf { it.isNotEmpty() }?.let { pool = it }
                pool.filter { !it.isStagingRow }.takeIf { it.isNotEmpty() }?.let { pool = it }
                pool.filter { !it.noReward }.takeIf { it.isNotEmpty() }?.let { pool = it }
                assertEquals(pool.map { it.npcId }.sorted(), card.rows(group).map { it.npcId }.sorted(), "${card.id} / ${group.title}")
            }
        }
    }

    @Test
    fun `代表行先排掉 noReward 但必须排在 isMain 之后`() {
        val gladiusMain = BossTestData.lord(0).representativeRow(BossGroup.NIGHTLORD)!!
        assertEquals(75000020, gladiusMain.npcId)
        assertTrue(gladiusMain.noReward)
        assertEquals(11328, gladiusMain.hp)
        assertEquals(12687, BossTestData.lord(3).representativeRow(BossGroup.NIGHTLORD)!!.hp)
        val morgott = BossTestData.boss("Morgott@2130")
        val tutorial = morgott.rows.first { it.npcId == 21300520 }
        assertEquals(9920, tutorial.hp)
        assertTrue(tutorial.noReward)
        assertEquals(listOf("other"), tutorial.roles)
        assertEquals(21300510, morgott.representativeRow(BossGroup.OTHER)!!.npcId)
        assertEquals(21300510, morgott.representativeRow(BossGroup.NIGHT)!!.npcId)
        val apostle = BossTestData.boss("Godskin Apostle@3560")
        val template = apostle.rows.first { it.npcId == 35600900 }
        assertTrue(template.noReward)
        assertEquals(listOf("unplaced"), template.roles)
        assertEquals(35600000, apostle.representativeRow(BossGroup.UNPLACED)!!.npcId)
        val chariot = BossTestData.boss("Flame Chariot@4460")
        val bar = chariot.rows.first { it.npcId == 44600015 }
        assertTrue(bar.noReward)
        assertEquals(listOf("unplaced"), bar.roles)
        assertEquals(44600010, chariot.representativeRow(BossGroup.STRONGHOLD)!!.npcId)
        assertEquals(44600000, chariot.representativeRow(BossGroup.FIELD)!!.npcId)
        val allNoReward = listOf(
            fight("""{"npcId":2,"hp":100,"noReward":true}"""),
            fight("""{"npcId":1,"hp":300,"noReward":true}"""),
        )
        assertEquals(1, BossCard.representativeRow(allNoReward, null)!!.npcId)
        assertEquals(2, BossCard.candidateRows(allNoReward, null).size)
        index.cards(BossGroup.NIGHTLORD, includeHidden = true).forEach { card ->
            val rep = card.representativeRow(BossGroup.NIGHTLORD)!!
            assertTrue(rep.isMain, "${card.displayName} 的代表行仍必须是主战行")
            assertTrue(card.rows(BossGroup.NIGHTLORD).all { it.noReward }, "夜王候选池整池 noReward")
        }
        val sanguine = BossTestData.boss("Sanguine Noble@3550")
        assertEquals(35500030, sanguine.representativeRow(BossGroup.UNPLACED)!!.npcId)
    }

    @Test
    fun `搜索 纯数字按行号前缀匹配 文本串收场合名 不收内部枚举值`() {
        val gladiusMain = BossTestData.row(75000020)
        assertTrue(gladiusMain.npcIds.size > 1)
        assertTrue(index.cards(BossGroup.NIGHTLORD, "75001020").any { it.displayName == "格拉狄乌斯" })
        assertTrue(index.cards(BossGroup.NIGHTLORD, "75000020").any { it.displayName == "格拉狄乌斯" })
        assertEquals(0, index.cards(BossGroup.NIGHTLORD, "1").size)
        assertTrue(index.cards(BossGroup.NIGHT, "7800").isNotEmpty())
        val withNameId = index.cards.first { it.npcNameId != null }
        assertTrue(index.cards(withNameId.groups.first(), withNameId.npcNameId.toString(), includeHidden = true).any { it.id == withNameId.id })
        val apostle = BossTestData.boss("Godskin Apostle@3560")
        assertTrue(index.cards(BossGroup.NIGHT, apostle.chrIds.first().toString()).any { it.id == apostle.id })
        val fieldCount = index.cards(BossGroup.FIELD).size
        assertEquals(fieldCount, index.cards(BossGroup.FIELD, "场景头目").size)
        assertEquals(0, index.cards(BossGroup.OTHER, "其它场合").size)
        assertTrue(index.cards(BossGroup.NIGHTLORD, "圣").isNotEmpty())
        val gladius = BossTestData.lord(0)
        assertTrue(gladius.matches(""))
        assertTrue(gladius.matches("7500"))
        assertFalse(gladius.matches("5000"), "数字只按前缀匹配")
        assertTrue(gladius.matches("三头"))
    }

    /**
     * 手机端独有的断言（桌面两端的测试里没有同名用例）：搜索串各段用换行拼接，与 Windows
     * `joinSearch` 同口径；macOS 用空格拼接、折叠时空格被删，跨两段的查询会命中。差异记在
     * BossCard.searchKey 的注释里，这里把它钉住，免得哪天被悄悄改掉。
     */
    @Test
    fun `搜索串分段用换行 跨段查询不命中 单段内照常命中`() {
        val gladius = BossTestData.lord(0)
        assertEquals("格拉狄乌斯", gladius.nameZh)
        assertEquals("Gladius", gladius.nameEn)
        assertTrue(gladius.searchKey.contains("格拉狄乌斯\ngladius"), "中文名与英文名之间应以换行分段")
        val hit = { query: String -> gladius.matches(query.foldedForSearch()) }
        assertTrue(hit("狄乌斯") && hit("GLAD") && hit("三头野兽"), "单段内的查询照常命中")
        // macOS 口径（空格拼接后折叠）下「斯glad」会跨段命中；这里不命中
        assertTrue(listOf(gladius.nameZh, gladius.nameEn).joinToString(" ").foldedForSearch().contains("斯glad"))
        assertFalse(hit("斯Glad"), "跨中文名 / 英文名两段的查询不应命中")
        assertTrue(index.filter("斯Glad", includeHidden = true).uniqueCards.isEmpty(), "跨段查询在全部分组里都不命中")
        assertFalse(hit("dius三头"), "跨英文名 / 远征名的查询同样不命中")
    }

    private data class Parity(
        val title: String,
        val npcId: Int,
        val players: BossPartySize,
        val mode: BossNightMode,
        val mutationId: Int?,
        val hp: Int,
        val poise: Double?,
        val kind: BossPoiseKind,
        val recover: Double,
        val ailment: Double,
        val buildup: Double,
        val attack: Double?,
        val rune: Double? = null,
    )

    @Test
    fun `双端对照表 同一条行 + 同一组输入 五个数值必须与 macOS 完全一致`() {
        val byId = rows.associateBy { it.npcId }
        assertEquals(rows.size, byId.size, "npcId 在全量行里唯一，对照表才能按它定位")
        val s = BossPartySize.SOLO
        val d = BossPartySize.DUO
        val t = BossPartySize.TRIO
        val n = BossNightMode.NORMAL
        val v = BossPoiseKind.VALUE
        val cases = listOf(
            // Windows bosses.test.mjs 的对照表
            Parity("格拉狄乌斯 1 人", 75000020, s, n, null, 11328, 120.0, v, 0.058, 0.5, 1.0, 3.36),
            Parity("格拉狄乌斯 2 人", 75000020, d, n, null, 22656, 218.181818, v, 0.0319, 0.375, 0.85, 3.36),
            Parity("格拉狄乌斯 3 人", 75000020, t, n, null, 33984, 400.0, v, 0.0174, 0.25, 0.7, 3.36),
            Parity("格拉狄乌斯 3 人 深度 5", 75000020, t, BossNightMode.DEPTH5, null, 73404, 476.190476, v, 0.0174, 0.25, 0.7, 11.1216, 1.0),
            Parity("格拉狄乌斯 1 人 深度 1", 75000020, s, BossNightMode.DEPTH1, null, 14160, 136.363636, v, 0.058, 0.5, 1.0, 4.2),
            Parity("玛利斯二阶段 2 人", 75410000, d, n, null, 58906, 1090.909091, v, 0.0, 0.375, 0.85, 3.864),
            Parity("史柴格斯 3 人 深度 3", 76100010, t, BossNightMode.DEPTH3, null, 54423, 581.58132, v, 0.0174, 0.25, 0.7, 6.4512),
            Parity("史柴格斯 3 人 深度 1", 76100010, t, BossNightMode.DEPTH1, null, 43329, 568.363953, v, 0.0174, 0.25, 0.7, 4.2),
            Parity("神皮使徒 最古老的牢狱 2 人", 35600110, d, n, null, 7687, 145.454545, v, 0.1595, 0.41, 0.889, 3.3),
            Parity("神皮使徒 模板行 2 人", 35600900, d, n, null, 9551, 145.454545, v, 0.1595, 0.46, 0.955, null),
            Parity("神皮使徒 封印监牢 2 人", 35600020, d, n, null, 6535, 106.666667, v, 0.2175, 0.82, 0.889, 2.97),
            Parity("神皮使徒 封印监牢 2 人 深度 3", 35600020, d, BossNightMode.DEPTH3, null, 9723, 124.031008, v, 0.2175, 0.82, 0.889, 5.46777, 1.0),
            Parity("神皮使徒 封印监牢 2 人 深度 3 变异 113140", 35600020, d, BossNightMode.DEPTH3, 113140, 11182, 124.031008, v, 0.2175, 0.82, 0.889, 6.2879355, 1.35),
            Parity("死亡仪式鸟 2 人 深度 3", 49800030, d, BossNightMode.DEPTH3, null, 5017, 186.046512, v, 0.2175, 0.98, 0.985, 2.7615, 1.0),
            Parity("死亡仪式鸟 2 人 深度 3 变异 113340", 49800030, d, BossNightMode.DEPTH3, 113340, 5770, 186.046512, v, 0.2175, 0.98, 0.985, 3.175725, 1.35),
            Parity("大型黄金河马 据点首领 3 人", 50100010, t, n, null, 17747, 266.666667, v, 0.087, 0.315, 0.778, 3.672),
            Parity("大型黄金河马 未放置 3 人", 50100000, t, n, null, 5606, 160.0, v, 0.145, 0.95, 0.97, 1.5),
            Parity("未知敌人 c7931 poise 0 2 人", 79310000, d, n, null, 6851, null, BossPoiseKind.ZERO, 0.1595, 0.46, 0.955, 1.75),
            Parity("鲜血君王的长枪 poise -1 2 人", 48010010, d, n, null, 674, null, BossPoiseKind.NONE, 0.0319, 0.375, 0.85, 3.64),
            Parity("贪食魔龙 1 人", 77000000, s, n, null, 5399, 120.0, v, 0.29, 0.5, 1.0, 1.75, 1.0),
            Parity("神皮贵族 守夜双人组 1 人", 35700010, s, n, null, 5549, 80.0, v, 0.058, 0.5, 1.0, 2.8, 1.0),
        )
        cases.forEach { c ->
            val row = assertNotNull(byId[c.npcId], "对照表找不到 npcId ${c.npcId}")
            val mutation = c.mutationId?.let { id ->
                assertTrue(id in row.mutationPool, "${c.title}：mutationPool 里应有这个档位")
                assertNotNull(dataset.mutation(id))
            }
            val got = row.stats(c.players, c.mode, mutation)
            assertEquals(c.hp, got.hp, "${c.title}：血量")
            assertEquals(c.kind, got.poiseKind, "${c.title}：削韧槽语义")
            if (c.poise == null) assertNull(got.effectivePoise, "${c.title}：有效韧性应算不出来")
            else assertClose(c.poise, got.effectivePoise, "${c.title}：有效韧性", 1e-4)
            assertClose(c.recover, got.poiseRecover, "${c.title}：削韧恢复")
            assertClose(c.ailment, got.ailmentDamageRate, "${c.title}：异常发动伤害")
            assertClose(c.buildup, got.ailmentBuildupRate, "${c.title}：异常累积")
            c.attack?.let { assertClose(it, got.attackRate, "${c.title}：攻击力倍率") }
            c.rune?.let { assertClose(it, got.runeRate, "${c.title}：卢恩倍率") }
        }
        assertEquals(50100010, BossTestData.boss("Large Golden Hippopotamus@5010").representativeRow(BossGroup.STRONGHOLD)!!.npcId)
        assertEquals(75000020, BossTestData.lord(0).representativeRow(BossGroup.NIGHTLORD)!!.npcId)
        assertEquals(75410000, BossTestData.lord(13).representativeRow(BossGroup.NIGHTLORD)!!.npcId)
        assertEquals(35600110, BossTestData.boss("Godskin Apostle@3560").representativeRow(BossGroup.EVERGAOL)!!.npcId)
        assertTrue(BossTestData.boss("Death Rite Bird@4980").rows(BossGroup.STRONGHOLD).any { it.npcId == 49800030 })
        // 隐藏开关前后八个分组的条数
        assertEquals(
            listOf(18 to 18, 40 to 40, 51 to 51, 35 to 35, 10 to 10, 45 to 45, 0 to 11, 0 to 93),
            BossGroup.entries.map { index.cards(it).size to index.cards(it, includeHidden = true).size },
        )
    }

    @Test
    fun `收录统计与 macOS 的 inventorySummary 是同一组数字`() {
        assertEquals(18, dataset.nightlords.size)
        assertEquals(
            mapOf(
                BossGroup.NIGHTLORD to 18, BossGroup.NIGHT to 40, BossGroup.STRONGHOLD to 51, BossGroup.FIELD to 35,
                BossGroup.EVERGAOL to 10, BossGroup.OTHER to 45, BossGroup.SUMMON to 11, BossGroup.UNPLACED to 93,
            ),
            index.groupCounts("", includeHidden = true),
        )
        assertEquals(49, index.multiGroupCards.size)
        assertEquals(394, index.rowCount)
        assertEquals(
            "夜王 18 · 守夜首领 40 · 据点首领 51 · 场景头目 35 · 封印监牢 10 · 其它场合 45 · " +
                "随从/召唤物 11 · 未放置 93（含 49 组同时属于多个分组） · 数值行 394",
            index.inventorySummary,
        )
    }

    @Test
    fun `GROUP_LABELS 覆盖数据集里出现的全部档位分组`() {
        val groups = dataset.scalingTiers.values.mapNotNull { it.group }.toSet()
        groups.forEach { group -> assertTrue(BossScalingGroup.title(group) != group, "档位分组缺少中文标签：$group") }
        assertEquals("野外首领威胁档", BossScalingGroup.title("Field Boss Threat"))
        assertEquals("守夜首领威胁档", BossScalingGroup.title("Night Boss Threat"))
        assertEquals("最终首领威胁档", BossScalingGroup.title("Final Boss Threat"))
        assertTrue(dataset.scalingTiers.values.any { it.group == null }, "数据里存在 group = null 的档位")
        assertTrue(index.scalingGroups.all { it.title.isNotEmpty() })
        assertEquals(index.scalingGroups.map { it.id }.sorted(), index.scalingGroups.map { it.id })
    }

    @Test
    fun `分组名与 macOS 的 BossCard Group title 一致`() {
        assertEquals(
            listOf("夜王", "守夜首领", "据点首领", "场景头目", "封印监牢", "其它场合", "随从/召唤物", "未放置"),
            BossGroup.entries.map { it.title },
        )
        assertEquals(
            listOf(
                BossRoleText.groupNightlord, BossRoleText.groupNight, BossRoleText.groupStronghold, BossRoleText.groupField,
                BossRoleText.groupEvergaol, BossRoleText.groupOther, BossRoleText.groupSummon, BossRoleText.groupUnplaced,
            ),
            BossGroup.entries.map { it.title },
        )
    }

    @Test
    fun `group = null 的 4 个档位写其它档位 展开态与底部档位表同名`() {
        val nullIds = dataset.scalingTiers.values.filter { it.group == null }.map { it.id }.sorted()
        assertEquals(listOf(98810, 98815, 98818, 98822), nullIds)
        assertEquals("其它档位", BossScalingGroup.title(null))
        assertEquals("其它档位", BossScalingGroup.title(""))
        assertEquals("最终首领威胁档", BossScalingGroup.title("Final Boss Threat"))
        assertEquals("Brand New Threat", BossScalingGroup.title("Brand New Threat"))
        nullIds.forEach { id ->
            assertEquals("档位 #$id · 其它档位", BossRowText.scalingCaption(id, dataset.scalingGroup(id)?.title))
            assertEquals("其它档位", dataset.scalingGroup(id)!!.title)
        }
        assertEquals("无缩放档位", BossRowText.scalingCaption(null, null))
        assertEquals("无缩放档位", dataset.scalingCaption(fight("""{"npcId":1}""")))
        assertEquals("档位 #4040404", BossRowText.scalingCaption(4040404, dataset.scalingGroup(4040404)?.title))
    }

    @Test
    fun `每条数值行的 scalingId 都能查到档位 且档位名非空`() {
        rows.forEach { row ->
            val id = row.scalingId ?: return@forEach
            val caption = dataset.scalingCaption(row)
            assertTrue(caption.startsWith("档位 #$id"), caption)
            assertTrue(caption.contains(" · "), "档位 $id 少了分组名：$caption")
        }
    }

    @Test
    fun `行内徽标 卡头计数文案与 macOS 逐字一致`() {
        val uncertain = rows.first { it.labelUncertain }
        val badges = uncertain.statusBadges(BossNightMode.NORMAL, false).map { it.text }
        assertTrue("标签为社区推测" in badges)
        assertFalse("标签存疑" in badges)
        val deepEntry = rows.first { it.hasDeepOfNight }
        val deepBadges = deepEntry.statusBadges(BossNightMode.DEPTH4, false).map { it.text }
        assertTrue("深夜数值" in deepBadges)
        assertTrue("深夜专属修正" in deepBadges)
        assertFalse(deepBadges.any { Regex("深夜 \\d").containsMatchIn(it) }, "徽标里不写深度数字")
        val plainDepth = rows.first { it.hasDepthStats && !it.hasDeepOfNight }
        val plainBadges = plainDepth.statusBadges(BossNightMode.DEPTH4, false).map { it.text }
        assertTrue("深夜数值" in plainBadges)
        assertFalse("深夜专属修正" in plainBadges)
        assertFalse(deepEntry.statusBadges(BossNightMode.NORMAL, false).any { it.text.startsWith("深夜") }, "常规模式下不挂深夜徽标")
        val mutable = rows.first { it.canMutate }
        assertTrue(BossRowBadge.MUTATION in mutable.statusBadges(BossNightMode.NORMAL, true))
        assertFalse(BossRowBadge.MUTATION in mutable.statusBadges(BossNightMode.NORMAL, false))
        assertEquals(dataset.mutationTitle, BossRowBadge.MUTATION.text)
        assertTrue(rows.any { it.threat == "night" })
        assertEquals("威胁档位 · 守夜首领威胁档", BossRoleText.threatTierCaption(listOf("night")))
        assertEquals("威胁档位 · 野外首领威胁档", BossRoleText.threatTierCaption(listOf("field")))
        val order = fight("""{"npcId":1,"isMain":true,"labelUncertain":true,"threat":"night","depthStats":{"1":{"hp":1}},"deepOfNight":{"hp":1}}""")
        assertEquals(
            listOf(BossRowBadge.MAIN, BossRowBadge.UNCERTAIN, BossRowBadge.DEPTH, BossRowBadge.EXCLUSIVE, BossRowBadge.MUTATION),
            order.statusBadges(BossNightMode.DEPTH1, true),
        )
        assertEquals(listOf("主战"), fight("""{"npcId":1,"threat":"night","isMain":true}""").statusBadges(BossNightMode.NORMAL, false).map { it.text })
        assertEquals("5 条数值行", BossRowText.rowCount(5))
        assertEquals("1 条数值行", BossRowText.rowCount(1))
        assertEquals("5 条数值行", BossRoleText.rowCount(5, 0))
        assertEquals("4 条数值行（另 1 条已隐藏）", BossRoleText.rowCount(4, 1))
    }

    @Test
    fun `代表行承伤偏高 倍率统一两位小数`() {
        assertEquals("×1.235", BossFormat.multiplier(1.2346))
        assertEquals("×1.23", BossFormat.multiplier(1.2345, 2))
        assertEquals("×1.1", BossFormat.multiplier(1.1, 2))
        assertEquals("×1.01", BossFormat.multiplier(1.006, 2))
        index.cards.filter { !it.isNightlord }.forEach { card ->
            card.hotRates(card.primaryRow).forEach { (_, rate) ->
                val text = BossFormat.multiplier(rate, 2)
                val decimals = text.substringAfter('.', "").length
                assertTrue(decimals <= 2, "承伤徽标小数位过多：$text")
            }
        }
    }

    @Test
    fun `poise 大于 0 但承受削韧倍率为 0 两端都显示 — 与异常说明`() {
        val broken = fight(
            """{"npcId":1,"labelZh":"坏行","isMain":true,"hp":1000,"hpBase":1000,"hpMultiplier":1,"poise":120,
               "poiseRecover":1,"poiseTakenBase":0,"poiseRecoverMultiplier":1,"ailmentDamageRateBase":0,
               "scaling":{"duo":{"hp":2,"poiseTaken":0.55,"poiseRecover":0.55,"buildupRate":1,"ailmentDamageRate":1}}}""",
        )
        val stats = broken.stats(BossPartySize.DUO)
        assertEquals(0.0, broken.poiseTakenBase, "数据里的 0 不能被改写成 1")
        assertEquals(BossPoiseKind.VALUE, stats.poiseKind)
        assertEquals(0.0, stats.poiseTakenTotal)
        assertNull(stats.effectivePoise)
        assertEquals("—", stats.poiseKind.placeholder)
        assertEquals("承受削韧倍率异常（0）", BossCaptions.rowPoise(broken, stats))
        assertEquals("无削韧槽", BossPoiseKind.ZERO.placeholder)
        assertEquals("不吃削韧", BossPoiseKind.NONE.placeholder)
        val normal = rows.first { it.poise > 0 && it.scaling?.duo != null }
        assertTrue(normal.stats(BossPartySize.DUO).effectivePoise!! > 0)
    }

    @Test
    fun `有效韧性小字的四支都与 macOS 的 poiseCaption 逐字一致`() {
        assertEquals("韧性 120 ÷ 承受削韧 0.55", BossRowText.poiseCaption(120.0, 0.55, BossPoiseKind.VALUE, true))
        assertEquals("superArmorDurability = 0，该实体没有削韧槽", BossRowText.poiseCaption(0.0, 1.0, BossPoiseKind.ZERO, false))
        assertEquals("superArmorDurability = -1", BossRowText.poiseCaption(-1.0, 1.0, BossPoiseKind.NONE, false))
        assertEquals("承受削韧倍率异常（0）", BossRowText.poiseCaption(120.0, 0.0, BossPoiseKind.VALUE, false))
        val noPoise = rows.first { it.poise < 0 }
        val noStats = noPoise.stats(BossPartySize.SOLO)
        assertEquals(BossPoiseKind.NONE, noStats.poiseKind)
        assertEquals("superArmorDurability = ${BossFormat.decimal(noPoise.poise, 0)}", BossCaptions.rowPoise(noPoise, noStats))
        val normal = rows.first { it.poise > 0 && it.scaling?.duo != null }
        val ok = normal.stats(BossPartySize.DUO)
        assertEquals(
            "韧性 ${BossFormat.decimal(normal.poise, 0)} ÷ 承受削韧 ${BossFormat.decimal(ok.poiseTakenTotal, 3)}",
            BossCaptions.rowPoise(normal, ok),
        )
        assertEquals(-1.0, fight("{}").poise, "缺字段时回落到 -1")
    }

    @Test
    fun `numberOr 只在缺字段 null 时回落 真实的 0 照原样用`() {
        val zeroed = fight(
            """{"hp":1000,"hpBase":1000,"hpMultiplier":0,"poise":120,"poiseRecover":2,"poiseTakenBase":1,
               "poiseRecoverMultiplier":0,"ailmentDamageRateBase":2,
               "scaling":{"duo":{"hp":0,"poiseTaken":1,"poiseRecover":0,"buildupRate":0,"ailmentDamageRate":0}}}""",
        )
        val stats = zeroed.stats(BossPartySize.DUO)
        assertEquals(0, stats.hp, "tier.hp 为 0 时不该被改写成 1")
        assertEquals(0.0, stats.poiseRecover)
        assertEquals(0.0, stats.ailmentDamageRate)
        assertEquals(0.0, stats.ailmentBuildupRate)
        val nulled = fight(
            """{"hp":1000,"hpBase":1000,"hpMultiplier":null,"poise":120,"poiseRecover":1,"poiseTakenBase":null,
               "poiseRecoverMultiplier":1,"ailmentDamageRateBase":1,
               "scaling":{"duo":{"hp":null,"poiseTaken":null,"poiseRecover":1,"buildupRate":1,"ailmentDamageRate":1}}}""",
        )
        val nullStats = nulled.stats(BossPartySize.DUO)
        assertEquals(1.0, nullStats.poiseTakenTotal, "poiseTakenBase / tier.poiseTaken 为 null 时回落到 1")
        assertEquals(1000, nullStats.hp, "tier.hp 为 null 时回落到 1")
        assertEquals(1.0, nulled.hpMultiplier)
        // 带引号的数字也能读（macOS 的 bossDouble / bossInt 同支）
        assertEquals(4200, fight("""{"npcId":"7","hp":"4200"}""").hp)
    }

    @Test
    fun `多人缩放明细多一列攻击力 1 时写不变 四个档位真会上浮`() {
        assertEquals("不变", BossRowText.attackRateText(1.0))
        assertEquals("×1.1", BossRowText.attackRateText(1.1))
        assertEquals("×1.2", BossRowText.attackRateText(1.2))
        assertEquals("—", BossRowText.attackRateText(Double.NaN))
        val raised = index.scalingGroups.filter { (it.duo?.raisesAttack ?: false) || (it.trio?.raisesAttack ?: false) }
        assertEquals(listOf(7744, 7753, 7754, 7758), raised.map { it.id })
        raised.forEach {
            assertEquals(1.1, it.duo!!.attackRate)
            assertEquals(1.2, it.trio!!.attackRate)
        }
        assertEquals(1.0, dataset.scalingGroup(7767)!!.duo!!.attackRate)
        assertEquals(1.0, dataset.scalingGroup(7767)!!.trio!!.attackRate)
        index.scalingGroups.forEach { tier ->
            assertEquals(1.0, tier.duo?.staminaAttackRate ?: 1.0)
            assertEquals(1.0, tier.trio?.staminaAttackRate ?: 1.0)
        }
        assertFalse(BossScalingTier.IDENTITY.raisesAttack)
        val apostle = BossTestData.boss("Godskin Apostle@3560")
        val evergaol = apostle.representativeRow(BossGroup.EVERGAOL)!!
        assertEquals(7754, evergaol.scalingId)
        assertEquals(1.0, evergaol.stats(BossPartySize.SOLO).tier.attackRate)
        assertEquals(1.1, evergaol.stats(BossPartySize.DUO).tier.attackRate)
        assertEquals(1.2, evergaol.stats(BossPartySize.TRIO).tier.attackRate)
        assertClose(evergaol.attackRateBase * 1.2, evergaol.stats(BossPartySize.TRIO).attackRate, "多人攻击力乘在常驻攻击倍率之上")
        assertEquals(1.0, BossTestData.row(75000020).stats(BossPartySize.TRIO).tier.attackRate)
        assertEquals(1.1, dataset.scalingGroup(7740)!!.duo!!.hp, "野外常见档只加 10% 血")
        assertEquals(1.0, dataset.scalingGroup(98810)!!.duo!!.hp, "突袭档完全不加血")
        val nightRow = rows.first { it.scalingId == 7753 }
        assertClose(1.2, nightRow.attackRate(BossPartySize.TRIO) / nightRow.attackRate(BossPartySize.SOLO), "7753 档三人攻击力比单人高 20%")
        assertEquals(nightRow.attackRateBase, nightRow.stats(BossPartySize.SOLO).attackRate)
        assertEquals("多人攻击 ×1.1", BossRowText.multiplayerAttackBadge(1.1))
        assertEquals("多人攻击 ×1.2", BossRowText.multiplayerAttackBadge(1.2))
        // 常驻档位：47 个带攻击力倍率，16178 只加物理
        assertEquals(47, dataset.permanentScaling.values.count { it.attackRate != 1.0 })
        assertFalse(dataset.permanentEffect(16178)!!.attackRates.isUniform)
        assertTrue(dataset.permanentScaling.all { (key, value) -> key == value.id })
        val main = BossTestData.row(75000020)
        assertEquals(main.permScalingIds.size, index.permanentEffects(main.permScalingIds).size)
        assertTrue(index.missingPermanentEffectIds(main.permScalingIds).isEmpty())
        assertEquals(listOf(4040404), index.missingPermanentEffectIds(listOf(4040404)))
    }

    @Test
    fun `底部人数缩放说明带上 notes multiplayerScalingAudit 的核实结论`() {
        val audit = dataset.notes!!.multiplayerScalingAudit
        assertEquals(9, audit.size)
        assertTrue(audit.first().contains("不是"))
        assertTrue(audit.any { it.contains("攻击力上浮") })
        assertTrue(audit.any { it.contains("防御") })
        assertTrue(audit.any { it.contains("阈值") })
        assertTrue(audit.all { it.isNotEmpty() })
        assertEquals(11, dataset.notes!!.deepOfNightAudit.size)
        assertEquals(4, dataset.notes!!.roleAuditSummary.size)
        assertTrue(BossRowText.multiplayerAuditSummary.contains("不是简单乘倍"))
        assertTrue(BossRowText.multiplayerAuditSummary.contains("上浮 10% / 20%"))
        assertTrue(BossRowText.multiplayerAuditSummary.contains("防御、卢恩与掉落、异常触发阈值三项人数缩放一概不碰"))
    }

    @Test
    fun `深夜 深度 变异个体的中文一律取游戏文本`() {
        val text = dataset.deepOfNightText
        assertEquals("深夜", text.deepOfNightTitle)
        assertEquals("深度", text.depthTitle)
        assertEquals("变异个体", text.mutationTitle, "不是社区叫法「红化」")
        assertEquals("变异个体", dataset.mutationTitle)
        assertEquals(131150, text.deepOfNight.textId)
        assertEquals(131011, text.depth.textId)
        assertEquals(338806, text.mutation.textId)
        assertTrue(text.description.zh.contains("深夜"))
        assertEquals("常规", dataset.title(BossNightMode.NORMAL))
        assertEquals("深夜 · 深度 3", dataset.title(BossNightMode.DEPTH3))
        assertEquals("常规", BossNightMode.NORMAL.builtinTitle)
        assertEquals("深夜 · 深度 5", BossNightMode.DEPTH5.builtinTitle)
        assertEquals("深度", BossDeepOfNightText.FALLBACK.depthTitle)
        val bare = BossTestData.indexOf("""{"nightlords":[{"menuId":1,"fights":[{"npcId":1}]}]}""").dataset
        assertEquals("深夜 · 深度 5", bare.title(BossNightMode.DEPTH5))
        assertEquals("变异个体", bare.mutationTitle)
    }

    @Test
    fun `底部 深夜各深度概览与变异个体出现只数 是只数不是概率`() {
        assertEquals(listOf(1, 2, 3, 4, 5), dataset.orderedDepthInfos.map { it.rankId })
        assertEquals(5, dataset.deepOfNightDepths.size)
        dataset.deepOfNightDepths.forEach { (key, info) -> assertEquals(key, info.rankId) }
        assertEquals(BossMapChallengeWeight(0.0, 0.0, 100.0), dataset.depthInfo(1)!!.mapChallengeWeight)
        assertEquals(BossMapChallengeWeight(10.0, 10.0, 80.0), dataset.depthInfo(3)!!.mapChallengeWeight)
        val depth1 = dataset.depthInfo(1)!!
        val depth5 = dataset.depthInfo(5)!!
        assertEquals("深度 1", depth1.title)
        assertEquals("深度 5", depth5.title)
        assertEquals(25.0, depth1.cursedUncommonRate)
        assertEquals(40.0, depth5.cursedRareRate)
        assertEquals(95, depth5.cataclysmWeight[2])
        val categories = dataset.mutationCategories
        assertEquals(46, categories.size)
        assertEquals(46, dataset.orderedMutationCategories.size)
        val fieldBoss = categories.filter { it.categoryId == 120 }
        assertTrue(fieldBoss.isNotEmpty())
        fieldBoss.forEach {
            assertEquals(0, it.count(1), "深度 1 不会遇到变异的野外首领")
            assertTrue(it.count(2) > 0)
        }
        assertTrue(categories.filter { it.categoryId == 160 }.all { it.count(1) == 0 })
        categories.forEach { row -> (1..5).forEach { assertTrue(row.count(it) >= 0) } }
        assertTrue(BossRowText.mutationCountNote.contains("不是百分比概率"))
        assertEquals(22, dataset.deepOfNightTiers.size)
        val finalTier = dataset.depthTier(7760)!!
        assertEquals("Tier 3f", finalTier.tier)
        assertClose(1.718, finalTier.depths.getValue(5).hp, "Tier 3f 深度 5 血量倍率", 1e-4)
        assertClose(2.947, finalTier.depths.getValue(5).attackRate, "Tier 3f 深度 5 攻击倍率", 1e-4)
    }

    @Test
    fun `夜王卡片带各深度出现权重 0 表示该深度不会出现`() {
        dataset.nightlords.forEach { lord ->
            val card = BossTestData.lord(lord.menuId)
            assertEquals(lord.orderedDepthChanceWeights, card.depthChanceWeights)
            assertTrue(lord.hasDepthChanceWeights)
        }
        assertTrue(index.cards.filter { !it.isNightlord }.all { it.depthChanceWeights == null })
        val gladius = dataset.nightlords.first { it.menuId == 0 }
        assertEquals(listOf(1000, 800, 650, 500, 500), gladius.orderedDepthChanceWeights.map { it.second })
        val everdark = dataset.nightlords.filter { it.variantKey != "normal" }
        assertTrue(everdark.isNotEmpty())
        everdark.forEach { assertEquals(0, it.depthChanceWeights[1], "${it.nameZh} 深度 1 不该出现") }
        assertTrue(dataset.nightlords.filter { it.variantKey == "normal" }.all { (it.depthChanceWeights[1] ?: 0) > 0 })
        assertEquals("该深度不会出现", BossRowText.depthWeightText(0))
        assertEquals("权重 500", BossRowText.depthWeightText(500))
        assertEquals("权重 1600", BossRowText.depthWeightText(1600), "不加千位分隔符")
    }

    @Test
    fun `buildItems 带齐 schemaVersion 3 的展示字段`() {
        val hidden = index.cards.filter { it.hidden }
        assertEquals(4, hidden.size)
        assertTrue(hidden.count { it.nameNote.isNotEmpty() } >= 3)
        assertTrue(BossTestData.boss("Storm King@7910").nameSourceUrl.startsWith("https://"))
        val lord = index.cards.first { it.isNightlord }
        assertTrue(lord.nameBadges.isEmpty())
        assertFalse(lord.hidden)
        assertFalse(lord.showsNameNotes)
        // 组级「不掉奖励」小字：巨大骸骨躯干五个名字字段全空，只有 noReward 撑起展开区那块
        val torso = BossTestData.boss("Giant Skeleton Torso@4960")
        assertTrue(torso.noReward && !torso.hidden && torso.nameNote.isEmpty() && torso.nameZhFallbackNote.isEmpty())
        assertTrue(torso.nameEvidence == null && torso.nameZhRejected == null && torso.nameSourceUrl.isEmpty())
        assertTrue(torso.showsNameNotes)
        assertTrue(index.cards.all { it.isNightlord || !it.noReward || it.showsNameNotes })
    }

    @Test
    fun `数值行标签的四级回退与 macOS 的 displayLabel 一致`() {
        assertEquals("甲", fight("""{"npcId":1,"labelZh":"甲","labelEn":"A","paramdexName":"P"}""").displayLabel)
        assertEquals("A", fight("""{"npcId":1,"labelZh":"","labelEn":"A","paramdexName":"P"}""").displayLabel)
        assertEquals("P", fight("""{"npcId":1,"labelZh":"","labelEn":"","paramdexName":"P"}""").displayLabel)
        assertEquals("行 12345", fight("""{"npcId":12345}""").displayLabel)
        assertTrue(rows.all { it.labelZh.isNotEmpty() })
    }

    @Test
    fun `最新数据集的两个取整事实 hp +1 的 4 行 unmatchedNames 12 条`() {
        val bumped = listOf(
            Triple("boss-Gaping Dragon@7700", 77000000, 5399),
            Triple("boss-Gaping Dragon@7700", 77000010, 5399),
            Triple("boss-Gaping Dragon@7700", 77009010, 5399),
            Triple("boss-Godskin Noble@3570", 35700010, 5549),
        )
        bumped.forEach { (id, npcId, hp) ->
            val row = BossTestData.card(id).rows.first { it.npcId == npcId }
            assertEquals(hp, row.hp, "$id / $npcId")
            assertEquals(hp - 0.5, row.hpBase * row.hpMultiplier, "乘积正好落在 .5 上")
            assertEquals(hp, row.stats(BossPartySize.SOLO).hp, "1 人常规血量直接取 hp，不重算")
        }
        val halves = rows.filter { kotlin.math.abs(hpProduct(it) % 1.0) == 0.5 }
        assertEquals(4, halves.size)
        assertTrue(rows.all { (it.hpBase * it.hpMultiplier).roundHalfAway() == it.hp })
        assertEquals(12, dataset.notes!!.unmatchedNames.size)
        assertEquals(4, dataset.notes!!.nameCollisionCount)
        assertTrue(dataset.notes!!.unmatchedNames.all { it.nameEn.isNotEmpty() && it.chrId > 0 })
    }

    private fun hpProduct(fight: BossFight): Double = fight.hpBase * fight.hpMultiplier

    @Test
    fun `深度缺失退常规 + 异常发动伤害基准缺字段回落 1`() {
        val noDepthJson =
            """{"npcId":1,"hp":1000,"hpBase":1000,"hpMultiplier":1,"poise":100,"poiseTakenBase":1,"poiseRecover":1,
                "poiseRecoverMultiplier":1,"ailmentDamageRateBase":0.5,"attackRateBase":2,
                "deepOfNight":{"hp":700,"hpMultiplier":0.7,"poiseTakenBase":0.8,"attackRateBase":1.4,
                  "poiseRecoverMultiplier":0.2,"ailmentDamageRateBase":0.25,"permScalingIds":[999]}"""
        val noDepth = fight("$noDepthJson}")
        val stats = noDepth.stats(BossPartySize.SOLO, BossNightMode.DEPTH3)
        assertTrue(stats.depthMissing)
        assertEquals(1000, stats.hp, "退回常规血量，不是 deepOfNight 的 700")
        assertEquals(2.0, stats.attackRate)
        assertEquals(1.0, stats.poiseTakenTotal)
        assertEquals(1.0, stats.poiseRecover, "削韧恢复倍率也退回常规")
        assertEquals(0.5, stats.ailmentDamageRate)
        assertEquals(emptyList(), stats.permScalingIds)
        assertEquals(BossRowText.noDepthStatsText, BossCaptions.rowHp(noDepth, stats, "深度"))

        val withDepth = fight(
            "$noDepthJson,\"depthStats\":{\"3\":{\"hp\":2000,\"hpMultiplier\":2,\"poiseTakenBase\":0.86,\"attackRateBase\":5,\"depthSpEffectId\":7}}}",
        )
        val deep = withDepth.stats(BossPartySize.SOLO, BossNightMode.DEPTH3)
        assertFalse(deep.depthMissing)
        assertEquals(2000, deep.hp)
        assertEquals(0.86, deep.poiseTakenTotal)
        assertClose(0.2, deep.poiseRecover, "削韧恢复倍率取 deepOfNight")
        assertEquals(0.25, deep.ailmentDamageRate)
        assertEquals(listOf(999), deep.permScalingIds)

        val bare = fight("""{"npcId":2,"hp":100,"hpBase":100,"hpMultiplier":1,"poise":10,"poiseTakenBase":1}""")
        assertEquals(1.0, bare.stats(BossPartySize.SOLO).ailmentDamageRate)
    }

    @Test
    fun `搜索索引收进 displayFallbackZh 卡头上写着的占位名必须搜得到`() {
        assertEquals(
            listOf("boss-Unknown Enemy (c7931)@7931", "boss-Unknown Enemy (c7932)@7932"),
            index.cards(BossGroup.SUMMON, "未知敌人", includeHidden = true).map { it.id }.sorted(),
        )
        assertEquals(0, index.cards(BossGroup.SUMMON, "未知敌人").size)
        val card = BossTestData.boss("Unknown Enemy (c7931)@7931")
        assertEquals("未知敌人 c7931", card.displayFallbackZh)
        assertEquals("未知敌人 c7931", card.displayName)
        assertEquals("Unknown Enemy (c7931)", card.nameEn)
    }

    @Test
    fun `深度覆盖 394 条数值行全有 depthStats 卡片一律判 all`() {
        assertTrue(index.cards.all { it.deepCoverage == BossDeepCoverage.ALL })
        val mixed = BossTestData.indexOf(
            """{"nightBosses":[{"nameEn":"X","chrIds":[1],"variants":[{"npcId":1,"depthStats":{"1":{"hp":1}}},{"npcId":2}]},
                {"nameEn":"Y","chrIds":[2],"variants":[{"npcId":3},{"npcId":4}]}]}""",
        )
        assertEquals(BossDeepCoverage.SOME, mixed.cards[0].deepCoverage)
        assertEquals(BossDeepCoverage.NONE, mixed.cards[1].deepCoverage)
    }
}
