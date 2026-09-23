package com.nightreign.relicchecker.gamedata.bosses

import com.nightreign.relicchecker.gamedata.GameDataFormatException
import com.nightreign.relicchecker.gamedata.GameDataKey
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertNull
import kotlin.test.assertTrue

/** 移植任务里列出的固定事实（与 macOS BossDataChecks / Windows bosses*.test.mjs 同一批数）。 */
class BossFixedFactsTest {
    private val index get() = BossTestData.index

    @Test
    fun `parser id and schema version are pinned`() {
        assertEquals("bosses.page.v1", BossesParser.PARSER_ID)
        assertEquals(4, GameDataKey.BOSSES.expectedVersion)
        assertEquals(4, index.dataset.schemaVersion)
        assertFailsWith<GameDataFormatException> {
            BossesParser.parse("""{"bossesSchemaVersion":3,"nightlords":[{"menuId":1,"fights":[]}]}""")
        }
    }

    @Test
    fun `group counts with the hidden toggle on and row total`() {
        val counts = BossGroup.entries.map { it.title to index.cards(it, includeHidden = true).size }
        assertEquals(
            listOf(
                "夜王" to 18, "守夜首领" to 40, "据点首领" to 51, "场景头目" to 35, "封印监牢" to 10,
                "其它场合" to 45, "随从/召唤物" to 11, "未放置" to 93,
            ),
            counts,
        )
        assertEquals(394, index.rowCount)
        assertEquals(394, index.dataset.allRows.size)
        assertEquals(
            "夜王 18 · 守夜首领 40 · 据点首领 51 · 场景头目 35 · 封印监牢 10 · 其它场合 45 · " +
                "随从/召唤物 11 · 未放置 93（含 49 组同时属于多个分组） · 数值行 394",
            index.inventorySummary,
        )
    }

    @Test
    fun `bell bearing hunter sits in four visible groups`() {
        val hunter = BossTestData.boss("Bell Bearing Hunter@3100")
        val visible = hunter.groups.filter { !it.isHiddenByDefault }
        assertEquals(listOf(BossGroup.NIGHT, BossGroup.STRONGHOLD, BossGroup.FIELD, BossGroup.OTHER), visible)
        listOf(BossGroup.NIGHT, BossGroup.STRONGHOLD, BossGroup.FIELD, BossGroup.OTHER).forEach { group ->
            assertTrue(index.cards(group, "铃珠猎人").any { it.id == hunter.id }, "${group.title} 应能搜到铃珠猎人")
        }
        assertTrue(index.cards(BossGroup.EVERGAOL, "铃珠猎人").none { it.id == hunter.id })
    }

    @Test
    fun `bell bearing hunter night row scales by party, depth and mutation`() {
        val hunter = BossTestData.boss("Bell Bearing Hunter@3100")
        val night = hunter.representativeRow(BossGroup.NIGHT)!!
        assertEquals(31000020, night.npcId)
        assertEquals(3457, night.hp(BossPartySize.SOLO))
        assertEquals(10371, night.hp(BossPartySize.TRIO))
        assertEquals("3,457", BossFormat.integer(night.hp(BossPartySize.SOLO)))
        assertEquals("10,371", BossFormat.integer(night.hp(BossPartySize.TRIO)))
        assertEquals(17631, night.hp(BossPartySize.TRIO, BossNightMode.DEPTH3))
        assertEquals("17,631", BossFormat.integer(night.stats(BossPartySize.TRIO, BossNightMode.DEPTH3).hp))

        val mutation = index.dataset.mutation(113140)!!
        assertEquals(listOf(113140), night.mutationPool)
        assertEquals(20276, night.hp(BossPartySize.TRIO, BossNightMode.DEPTH3, mutation))
        // 工具条的两种选法落到这一行上是同一个档位
        val own = index.dataset.mutationFor(night, BossMutationChoice.Own)
        val tier = index.dataset.mutationFor(night, BossMutationChoice.Tier(113140))
        assertEquals(mutation, own)
        assertEquals(mutation, tier)
        assertNull(index.dataset.mutationFor(night, BossMutationChoice.Tier(113240)), "池里没有的档位不作用于这一行")
        assertNull(index.dataset.mutationFor(night, BossMutationChoice.None))
        assertEquals("20,276", BossFormat.integer(night.stats(BossPartySize.TRIO, BossNightMode.DEPTH3, own).hp))
    }

    @Test
    fun `gladius main fight hp for one two and three players`() {
        val gladius = BossTestData.lord(0)
        val main = gladius.representativeRow(BossGroup.NIGHTLORD)!!
        assertEquals(75000020, main.npcId)
        assertEquals(
            listOf(11328, 22656, 33984),
            BossPartySize.entries.map { main.hp(it) },
        )
        assertEquals(listOf("11,328", "22,656", "33,984"), BossPartySize.entries.map { BossFormat.integer(main.hp(it)) })
    }

    @Test
    fun `effective poise is null when poise is minus one`() {
        val negative = index.dataset.allRows.filter { it.poise < 0 }
        assertEquals(5, negative.size)
        negative.forEach { row ->
            BossPartySize.entries.forEach { players ->
                BossNightMode.entries.forEach { mode ->
                    assertNull(row.effectivePoise(players, mode), "${row.npcId} ${players.title} ${mode.name}")
                    assertNull(row.stats(players, mode).effectivePoise)
                }
            }
            assertEquals(BossPoiseKind.NONE, row.poiseKind)
        }
    }

    @Test
    fun `nightlord battle tier 4a depth multipliers`() {
        val tier = index.dataset.depthTier(7767)!!
        assertEquals("Tier 4a", tier.tier)
        assertEquals("最终首领威胁档", tier.title)
        val hp = (1..5).map { tier.depths.getValue(it).hp }
        assertEquals(listOf(1.25, 1.4, 1.57, 1.95, 2.16), hp)
        // 格拉狄乌斯远征首领挂的就是这一档：深度血量 = 常规血量 × 该档倍率（四舍五入）
        val main = BossTestData.row(75000020)
        assertEquals(7767, main.chaosCorrectId)
        assertEquals(
            listOf(14160, 15859, 17785, 22090, 24468),
            (1..5).map { main.hp(BossPartySize.SOLO, BossNightMode.depth(it)) },
        )
        (1..5).forEach { depth ->
            val expected = (main.hp * hp[depth - 1]).roundHalfAway()
            assertTrue(kotlin.math.abs(expected - main.depthStats.getValue(depth).hp) <= 1, "深度 $depth")
        }
    }

    @Test
    fun `search updates every group count and counts match the list`() {
        listOf("", "铃珠猎人", "场景头目", "Gladius", "75001020", "7800", "未放置", "不存在的首领名").forEach { query ->
            listOf(false, true).forEach { hidden ->
                val result = index.filter(query, hidden)
                result.sections.forEach { (group, cards) ->
                    assertEquals(index.cards(group, query, hidden).size, cards.size, "$query / ${group.title}")
                    assertEquals(cards.size, result.counts.getValue(group))
                }
                assertEquals(BossGroup.visibleCases(hidden), result.sections.map { it.first })
                // 只看某一个分组时，那个分组的列表与全量筛选里的同一分组完全一致
                BossGroup.visibleCases(hidden).forEach { group ->
                    val single = index.filter(query, hidden, only = group)
                    assertEquals(listOf(group), single.sections.map { it.first })
                    assertEquals(result.sections.first { it.first == group }.second, single.sections.single().second)
                }
            }
        }
        // 搜索确实改变各分组计数（桌面端的已知缺陷：计数不跟搜索走）
        val hunter = index.groupCounts("铃珠猎人", includeHidden = false)
        assertEquals(
            mapOf(
                BossGroup.NIGHTLORD to 0, BossGroup.NIGHT to 1, BossGroup.STRONGHOLD to 1,
                BossGroup.FIELD to 1, BossGroup.EVERGAOL to 0, BossGroup.OTHER to 1,
            ),
            hunter,
        )
        val hunterHidden = index.groupCounts("铃珠猎人", includeHidden = true)
        assertEquals(1, hunterHidden[BossGroup.UNPLACED])
        assertEquals(0, hunterHidden[BossGroup.SUMMON])
        assertEquals(1, index.filter("铃珠猎人", false).uniqueCards.size)
        assertTrue(index.filter("不存在的首领名", true).isEmpty)
        assertEquals(122, index.filter("", false).uniqueCards.size)
    }
}
