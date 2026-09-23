package com.nightreign.relicchecker.gamedata.bosses

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * windows/tests/bosses_roles.test.mjs 的逐条对应（按出场场合分组），外加 macOS
 * BossDataChecks.swift 的 checkBossRoleGrouping 与宽容样本断言。
 */
class BossRolesTest {
    private val index get() = BossTestData.index
    private val dataset get() = BossTestData.dataset
    private val rows get() = BossTestData.allRows

    private val single = mapOf(
        BossGroup.NIGHT to "night", BossGroup.STRONGHOLD to "stronghold", BossGroup.FIELD to "field",
        BossGroup.EVERGAOL to "evergaol", BossGroup.SUMMON to "summon", BossGroup.UNPLACED to "unplaced",
    )

    private fun fight(json: String) = BossesParser.parseFight(json)

    /** 没有 roleNames 的空数据集（验证「缺 roleNames 时退内置中文名」）。 */
    private val bareDataset: BossDataset by lazy {
        BossTestData.indexOf("""{"nightlords":[{"menuId":1,"fights":[{"npcId":1}]}]}""").dataset
    }

    @Test
    fun `场合常量表与数据集 roleNames 对得上 取值 顺序 中文名 分组`() {
        assertEquals(4, dataset.schemaVersion)
        assertEquals(BossRoleCatalog.order, dataset.roleNames.keys.toList(), "规范顺序 = roleNames 的键序")
        assertEquals(14, BossRoleCatalog.order.size)
        BossRoleCatalog.order.forEach { role ->
            assertEquals(dataset.roleNames.getValue(role).zh, BossRoleText.builtinRoleNames[role], role)
            assertEquals(dataset.roleNames.getValue(role).zh, dataset.roleTitle(role), role)
            assertEquals(dataset.roleNames.getValue(role).zh, bareDataset.roleTitle(role), "$role：数据缺 roleNames 时走内置表")
        }
        assertEquals("场景头目", dataset.roleNames.getValue("field").zh)
        assertEquals(
            listOf("nightlord", "night", "stronghold", "field", "evergaol", "other", "summon", "unplaced"),
            BossGroup.entries.map { it.key },
        )
        assertEquals(listOf(BossGroup.SUMMON, BossGroup.UNPLACED), BossGroup.entries.filter { it.isHiddenByDefault })
        assertEquals(
            listOf(BossGroup.NIGHTLORD, BossGroup.NIGHT, BossGroup.STRONGHOLD, BossGroup.FIELD, BossGroup.EVERGAOL, BossGroup.OTHER),
            BossGroup.visibleCases(false),
        )
        assertEquals(BossGroup.entries, BossGroup.visibleCases(true))
        single.forEach { (group, role) -> assertEquals(dataset.roleNames.getValue(role).zh, group.title, group.key) }
        assertEquals("夜王", BossGroup.NIGHTLORD.title)
        assertEquals("其它场合", BossGroup.OTHER.title)
        assertEquals(
            mapOf(
                "nightlord" to BossGroup.NIGHTLORD, "night" to BossGroup.NIGHT, "stronghold" to BossGroup.STRONGHOLD,
                "field" to BossGroup.FIELD, "evergaol" to BossGroup.EVERGAOL, "summon" to BossGroup.SUMMON,
                "unplaced" to BossGroup.UNPLACED, "prelude" to BossGroup.OTHER, "mine" to BossGroup.OTHER,
                "tower" to BossGroup.OTHER, "raid" to BossGroup.OTHER, "invader" to BossGroup.OTHER,
                "event" to BossGroup.OTHER, "other" to BossGroup.OTHER,
            ),
            BossRoleCatalog.order.associateWith { BossGroup.forRole(it) },
        )
        assertEquals(listOf("prelude", "mine", "tower", "raid", "invader", "event", "other"), BossGroup.otherRoles)
        assertEquals(setOf("summon", "unplaced"), BossRoleCatalog.hiddenRoles)
        assertEquals(BossGroup.OTHER, BossGroup.forRole("brandNew"))
        assertEquals("brandNew", dataset.roleTitle("brandNew"))
        val english = BossTestData.indexOf(
            """{"roleNames":{"brandNew":{"zh":"","en":"Brand New"}},"nightlords":[{"menuId":1,"fights":[{"npcId":1}]}]}""",
        ).dataset
        assertEquals("Brand New", english.roleTitle("brandNew"))
    }

    @Test
    fun `normalizeRoles roleGroups 规范顺序 去重 多重归属与默认隐藏`() {
        assertEquals(listOf("night", "unplaced", "aaa", "zzz"), BossRoleCatalog.normalized(listOf("unplaced", "night", "", "night", "zzz", "aaa")))
        assertEquals(listOf("night", "tower", "unplaced"), BossRoleCatalog.normalized(listOf("unplaced", "tower", "night", "tower")))
        assertEquals(emptyList(), BossRoleCatalog.normalized(emptyList()))
        assertEquals(
            listOf(BossGroup.NIGHT, BossGroup.FIELD, BossGroup.OTHER, BossGroup.UNPLACED),
            BossDataIndex.groups(listOf("tower", "night", "night", "unplaced", "field", "futureRole")),
        )
        assertFalse(BossRoleCatalog.onlyHidden(listOf("tower", "night", "unplaced", "field", "futureRole")))
        BossRoleCatalog.otherGroupRoles.forEach { role -> assertEquals(listOf(BossGroup.OTHER), BossDataIndex.groups(listOf(role)), role) }
        assertEquals(listOf(BossGroup.UNPLACED), BossDataIndex.groups(listOf("unplaced")))
        assertTrue(BossRoleCatalog.onlyHidden(listOf("unplaced")))
        assertEquals(listOf(BossGroup.SUMMON, BossGroup.UNPLACED), BossDataIndex.groups(listOf("summon", "unplaced")))
        assertTrue(BossRoleCatalog.onlyHidden(listOf("summon", "unplaced")))
        assertEquals(listOf(BossGroup.NIGHT, BossGroup.UNPLACED), BossDataIndex.groups(listOf("night", "unplaced")))
        assertFalse(BossRoleCatalog.onlyHidden(listOf("night", "unplaced")))
        // 守夜 / 野外首领万一带了 nightlord 场合，归「其它场合」
        assertEquals(listOf(BossGroup.FIELD, BossGroup.OTHER), BossDataIndex.groups(listOf("nightlord", "field")))
        assertEquals(listOf(BossGroup.OTHER), BossDataIndex.groups(emptyList()))
        assertFalse(BossRoleCatalog.onlyHidden(emptyList()), "缺数据不能被当成「未放置」藏起来")
        assertTrue(BossRoleCatalog.onlyHidden(listOf("summon")))
        assertEquals(listOf("tower", "raid"), BossGroup.OTHER.rolesIn(listOf("night", "tower", "raid", "unplaced")))
        assertEquals(listOf("unplaced"), BossGroup.UNPLACED.rolesIn(listOf("summon", "unplaced")))
        assertEquals(listOf("nightlord"), BossGroup.NIGHTLORD.rolesIn(listOf("nightlord", "raid")))
        // 夜王卡恒只在「夜王」：突袭 / 事件 / 未放置只挂徽标
        index.cards.filter { it.isNightlord }.forEach { assertEquals(listOf(BossGroup.NIGHTLORD), it.groups) }
    }

    @Test
    fun `数据侧前提 组级 roles = 各行 roles 的并集 行级 roles = rowRoles 的并集`() {
        BossTestData.dto.nightBosses.forEach { boss ->
            val union = BossRoleCatalog.normalized(boss.variants.flatMap { it.roles })
            assertEquals(union, BossRoleCatalog.normalized(boss.roles), boss.id)
            assertEquals(union, BossTestData.boss(boss.id).roles, boss.id)
        }
        BossTestData.dto.nightlords.forEach { lord ->
            assertEquals(BossRoleCatalog.normalized(lord.fights.flatMap { it.roles }), BossRoleCatalog.normalized(lord.roles), lord.nameZh)
        }
        BossTestData.dto.nightlords.flatMap { it.fights }.plus(BossTestData.dto.nightBosses.flatMap { it.variants }).forEach { raw ->
            assertEquals(BossRoleCatalog.normalized(raw.roles), raw.roles, "npcId ${raw.npcId} 的 roles 已是规范顺序")
        }
        rows.forEach { row ->
            assertEquals(row.roles, BossRoleCatalog.normalized(row.rowRoles.values.flatten()), "npcId ${row.npcId}")
            assertEquals(row.roles.toSet(), row.roleEvidence.keys, "npcId ${row.npcId} 每个场合都有证据")
            assertTrue(row.hasRoles && row.roles.all { row.evidence(it).isNotEmpty() })
        }
        // 卡头 / 行内徽标的场合顺序是规范顺序
        assertTrue(index.cards.all { card -> card.roles == card.roles.sortedBy { BossRoleCatalog.rank(it) } })
        assertTrue(rows.all { row -> row.roles == row.roles.sortedBy { BossRoleCatalog.rank(it) } })
    }

    @Test
    fun `分组计数与 roleSummary 一致 含开关前后的条数`() {
        single.forEach { (group, role) ->
            val cards = index.cards(group, includeHidden = true)
            assertEquals(dataset.roleSummary[role], cards.size, group.key)
            assertEquals(dataset.roleSummaryDetail.getValue(role).groups, cards.size, "${group.key}：roleSummaryDetail.groups")
            assertTrue(cards.all { !it.isNightlord && role in it.roles }, group.key)
            assertEquals(dataset.roleTitle(role), group.title)
        }
        assertEquals(
            listOf(40, 51, 35, 10, 11, 93),
            listOf("night", "stronghold", "field", "evergaol", "summon", "unplaced").map { dataset.roleSummary.getValue(it) },
        )
        BossRoleCatalog.order.forEach { role ->
            val recount = dataset.nightBosses.count { role in it.roles }
            assertEquals(recount, dataset.roleSummary[role], role)
            assertEquals(recount, dataset.roleSummaryDetail.getValue(role).groups, role)
        }
        val other = index.cards(BossGroup.OTHER, includeHidden = true)
        val union = dataset.nightBosses.filter { boss -> boss.roles.any { it in BossRoleCatalog.otherGroupRoles } }
        assertEquals(45, other.size)
        assertEquals(union.map { "boss-${it.id}" }.sorted(), other.map { it.id }.sorted())
        BossRoleCatalog.otherGroupRoles.forEach { role ->
            assertEquals(dataset.roleSummary[role], other.count { role in it.roles }, role)
        }
        val lords = index.cards(BossGroup.NIGHTLORD, includeHidden = true)
        assertEquals(dataset.roleSummaryDetail.getValue("nightlord").nightlords, lords.size)
        assertTrue(lords.all { it.isNightlord && "nightlord" in it.roles })
        BossGroup.entries.filter { it != BossGroup.NIGHTLORD }.forEach { group ->
            assertTrue(index.cards(group, includeHidden = true).none { it.isNightlord }, group.key)
        }
        index.cards.filter { !it.isNightlord }.forEach { card ->
            assertEquals(card.roles.map { BossGroup.forRole(it) }.toSet(), card.groups.toSet(), card.id)
        }
        val shown = BossGroup.entries.flatMap { g -> index.cards(g, includeHidden = true).map { it.id } }.toSet()
        assertEquals(index.cards.size, shown.size, "打开隐藏开关后，每张卡都至少出现在一个分组里")
        assertEquals(
            mapOf(
                BossGroup.NIGHTLORD to 18, BossGroup.NIGHT to 40, BossGroup.STRONGHOLD to 51, BossGroup.FIELD to 35,
                BossGroup.EVERGAOL to 10, BossGroup.OTHER to 45,
            ),
            index.groupCounts("", includeHidden = false),
        )
        assertEquals(
            mapOf(
                BossGroup.NIGHTLORD to 18, BossGroup.NIGHT to 40, BossGroup.STRONGHOLD to 51, BossGroup.FIELD to 35,
                BossGroup.EVERGAOL to 10, BossGroup.OTHER to 45, BossGroup.SUMMON to 11, BossGroup.UNPLACED to 93,
            ),
            index.groupCounts("", includeHidden = true),
        )
        listOf(false, true).forEach { hidden ->
            val counts = index.groupCounts("", hidden)
            BossGroup.visibleCases(hidden).forEach { group ->
                assertEquals(index.cards(group, "", hidden).size, counts.getValue(group), "${group.key} / $hidden")
            }
        }
    }

    @Test
    fun `未放置 随从召唤物默认隐藏 分组 卡片 搜索都沿用隐藏开关`() {
        assertEquals(
            listOf(
                "boss-Borealis the Freezing Fog@4503", "boss-Centipede Grub@7711", "boss-Decaying Ekzykes@4501",
                "boss-Dreg Wormface@7660", "boss-Elder Dragon Greyoll@4504", "boss-Funeral Steed@3160",
                "boss-Giant Skeleton Torso@4960", "boss-Lake Glintstone Dragon@4502", "boss-Lord of Blood Spear@4801",
                "boss-Storm King@7910", "boss-Unknown Enemy (c7931)@7931", "boss-Unknown Enemy (c7932)@7932",
            ),
            index.hiddenByDefaultCards.map { it.id }.sorted(),
        )
        assertTrue(index.cards.filter { it.hidden }.all { BossRoleCatalog.onlyHidden(it.roles) })
        index.hiddenByDefaultCards.forEach { card -> assertTrue(card.groups.all { it.isHiddenByDefault }, card.id) }
        assertEquals(0, index.cards(BossGroup.SUMMON, "").size)
        assertEquals(11, index.cards(BossGroup.SUMMON, "", includeHidden = true).size)
        assertEquals(0, index.cards(BossGroup.UNPLACED, "铃珠猎人").size)
        assertEquals(1, index.cards(BossGroup.UNPLACED, "铃珠猎人", includeHidden = true).size)
        BossGroup.entries.forEach { group -> assertEquals(0, index.cards(group, "Centipede Grub").size, group.key) }
        assertEquals(1, index.cards(BossGroup.SUMMON, "Centipede Grub", includeHidden = true).size)
        assertEquals(listOf("boss-Elder Dragon Greyoll@4504"), index.cards(BossGroup.UNPLACED, "Greyoll", includeHidden = true).map { it.id })
        val flying = BossTestData.boss("Flying Dragon@4500")
        assertEquals(listOf("field", "unplaced"), flying.roles)
        assertEquals(listOf(BossGroup.FIELD, BossGroup.UNPLACED), flying.groups)
        assertFalse(flying.isHiddenByDefault)
        assertEquals(1, index.cards(BossGroup.FIELD, "丘陵飞龙").size)
        assertEquals(0, index.cards(BossGroup.OTHER, "丘陵飞龙", includeHidden = true).size, "不会因为未放置行跑进「其它场合」")
        assertEquals("", BossPageText.hiddenCountText(0, false))
        assertEquals("已隐藏 12 组（未放置 / 随从 / 非首领实体）", BossPageText.hiddenCountText(12, false))
        assertEquals("含隐藏 12 组", BossPageText.hiddenCountText(12, true))
        // 默认视图 6 个分组的并集里没有一张默认隐藏的卡
        val visible = index.filter("", includeHidden = false).uniqueCards
        assertTrue(visible.none { it.isHiddenByDefault })
    }

    @Test
    fun `底部隐藏说明 非首领实体 + 只有未放置随从场合的组 与 macOS 的 hiddenSummary 同一句`() {
        val expected = "另有 4 组被判定为非首领实体（Centipede Grub、鲜血君王的长枪、未知敌人 c7931、未知敌人 c7932），" +
            "判据是整组不掉任何奖励，且不吃削韧 / 连社区资料都认不出 / 社区标为杂兵；" +
            "另有 8 组只出现在「未放置」「随从/召唤物」两个场合（“冻结冰雾”玻列琉斯、步入腐败仇恨龙、" +
            "Elder Dragon Greyoll、湖之辉石龙、Storm King、废弃物蚯蚓脸、葬送战马、Giant Skeleton Torso）。" +
            "它们默认不在列表里，展开区里只出现在这两个场合的数值行也默认隐藏；" +
            "需要时打开工具条的「显示隐藏实体」，分组筛选里会多出「随从/召唤物」「未放置」两项。"
        assertEquals(expected, index.hiddenSummary)
        val flagged = index.cards.filter { it.hidden }
        val roleOnly = index.cards.filter { !it.hidden && it.isHiddenByDefault }
        assertEquals(index.hiddenByDefaultCards.size, flagged.size + roleOnly.size)
        assertEquals(
            BossRoleText.hiddenSummary(flagged.map { it.displayName }, roleOnly.map { it.displayName }),
            index.hiddenSummary,
        )
        assertEquals(
            "另有 1 组只出现在「未放置」「随从/召唤物」两个场合（丙）。它们默认不在列表里，" +
                "展开区里只出现在这两个场合的数值行也默认隐藏；" +
                "需要时打开工具条的「显示隐藏实体」，分组筛选里会多出「随从/召唤物」「未放置」两项。",
            BossRoleText.hiddenSummary(emptyList(), listOf("丙")),
        )
        assertEquals("", BossRoleText.hiddenSummary(emptyList(), emptyList()))
        assertNull(BossTestData.indexOf("""{"nightlords":[{"menuId":1,"fights":[{"npcId":1,"roles":["nightlord"]}]}]}""").hiddenSummary)
        val summary = index.hiddenSummary.orEmpty()
        assertTrue(summary.contains(BossRowText.hiddenToggleTitle) && summary.contains(BossRoleText.groupUnplaced) && summary.contains(BossRoleText.groupSummon))
    }

    @Test
    fun `救世旗手 nl 18 按场合过滤后代表行由未放置的蠕虫行换成二阶段行`() {
        val bearers = BossTestData.lord(18)
        assertEquals("救世旗手", bearers.variantNameZh)
        assertEquals(listOf(BossGroup.NIGHTLORD), bearers.groups)
        assertEquals(listOf("nightlord", "unplaced"), bearers.roles)
        assertEquals(listOf(46410000, 76200210, 76200310), bearers.mainRows.map { it.npcId })
        assertEquals(listOf("unplaced"), BossTestData.row(46410000).roles)
        assertEquals(46410000, bearers.representativeRow(null)!!.npcId, "旧口径（不按场合过滤）取的是蠕虫行")
        assertEquals(listOf(76200210, 76200310), bearers.rows(BossGroup.NIGHTLORD).map { it.npcId })
        assertTrue(bearers.rows(BossGroup.NIGHTLORD).all { it.noReward })
        assertEquals(76200210, bearers.representativeRow(BossGroup.NIGHTLORD)!!.npcId)
        assertEquals(76200210, bearers.primaryRow!!.npcId)
        assertTrue(bearers.hasMultipleMainRows)
        assertEquals(1, bearers.hiddenRowCount(false))
        assertEquals(
            "3 条数值行（另 1 条已隐藏）",
            BossRoleText.rowCount(bearers.displayRows(false).size, bearers.hiddenRowCount(false)),
        )
    }

    @Test
    fun `展开区默认收起只有未放置随从召唤物场合的行`() {
        var hiddenTotal = 0
        var shownTotal = 0
        index.cards.forEach { card ->
            hiddenTotal += card.hiddenRowCount(false)
            shownTotal += card.displayRows(false).size
            assertEquals(card.rows.size, card.displayRows(true).size, "打开开关全部列出")
            assertEquals(0, card.hiddenRowCount(true))
            assertTrue(card.displayRows(false).isNotEmpty())
            assertTrue(card.displayRows(false).none { it.isHiddenByDefault } || card.isHiddenByDefault)
        }
        assertEquals(148, hiddenTotal)
        assertEquals(246, shownTotal)
        assertEquals(394, hiddenTotal + shownTotal)
        val hunter = BossTestData.boss("Bell Bearing Hunter@3100")
        assertEquals(listOf(31000010, 31000020, 31000030, 31000040), hunter.displayRows(false).map { it.npcId }.sorted())
        assertEquals(1, hunter.hiddenRowCount(false), "未放置的 31000000 默认收起")
        val greyoll = BossTestData.boss("Elder Dragon Greyoll@4504")
        assertEquals(greyoll.rows.size, greyoll.displayRows(false).size)
        assertEquals(0, greyoll.hiddenRowCount(false))
        val gladius = BossTestData.lord(0)
        assertEquals(listOf(75000020, 75001110), gladius.displayRows(false).map { it.npcId })
        assertEquals(2, gladius.hiddenRowCount(false))
        val sample = listOf(
            fight("""{"npcId":10,"roles":["tower","night"]}"""),
            fight("""{"npcId":11,"roles":["unplaced","field"]}"""),
            fight("""{"npcId":13,"roles":["unplaced"]}"""),
            fight("""{"npcId":14,"roles":["futureRole"]}"""),
            fight("""{"npcId":15}"""),
        )
        assertEquals(listOf(10, 11, 14, 15), BossCard.displayRows(sample, false).map { it.npcId })
        assertEquals(1, sample.size - BossCard.displayRows(sample, false).size)
        assertEquals("4 条数值行（另 1 条已隐藏）", BossRoleText.rowCount(4, 1))
        assertEquals("4 条数值行", BossRoleText.rowCount(4, 0))
        assertEquals("另有 1 条「未放置」/「随从/召唤物」行已隐藏，打开「显示隐藏实体」查看", BossRoleText.hiddenRows(1))
    }

    @Test
    fun `铃珠猎人四行的 roles 各不相同 且都能在对应分组搜到`() {
        val raw = BossTestData.dto.nightBosses.first { it.id == "Bell Bearing Hunter@3100" }
        assertEquals("night", raw.tier)
        val card = BossTestData.boss("Bell Bearing Hunter@3100")
        assertEquals(listOf("night"), card.tiers)
        assertEquals("威胁档位 · 守夜首领威胁档", BossRoleText.threatTierCaption(card.tiers))
        assertEquals(listOf("night", "field", "stronghold", "tower", "unplaced"), card.roles)
        assertEquals(listOf(BossGroup.NIGHT, BossGroup.STRONGHOLD, BossGroup.FIELD, BossGroup.OTHER, BossGroup.UNPLACED), card.groups)
        assertEquals(
            mapOf(
                31000020 to listOf("night", "tower"), 31000010 to listOf("field"), 31000030 to listOf("field"),
                31000040 to listOf("stronghold"), 31000000 to listOf("unplaced"),
            ),
            card.rows.associate { it.npcId to it.roles },
        )
        assertTrue(card.rows.all { it.threat == "night" }, "五行的 threat 都是 night——不能拿来分组")
        val four = listOf(31000020, 31000010, 31000040, 31000000).map { BossTestData.row(it).roles }
        assertEquals(4, four.toSet().size)
        card.rows.forEach { row ->
            row.roles.forEach { role ->
                val group = BossGroup.forRole(role)
                assertTrue(
                    index.cards(group, row.npcId.toString(), group.isHiddenByDefault).any { it.id == card.id },
                    "${row.npcId} / ${group.key}",
                )
                assertTrue(card.rows(group).any { it.npcId == row.npcId }, "${row.npcId} 在 ${group.key} 的候选里")
            }
            assertEquals(row.roles.map { dataset.roleNames.getValue(it).zh }, dataset.roleBadges(row.roles).map { it.title })
        }
        assertEquals(
            listOf(31000020, 31000010, 31000040, 31000020, 31000000),
            listOf(BossGroup.NIGHT, BossGroup.FIELD, BossGroup.STRONGHOLD, BossGroup.OTHER, BossGroup.UNPLACED).map { card.representativeRow(it)!!.npcId },
        )
        listOf(BossGroup.NIGHT, BossGroup.STRONGHOLD, BossGroup.FIELD, BossGroup.OTHER).forEach { group ->
            assertTrue(index.cards(group, "铃珠猎人").any { it.id == card.id }, group.key)
        }
        assertEquals(0, index.cards(BossGroup.EVERGAOL, "铃珠猎人").size)
        assertTrue(index.cards(BossGroup.STRONGHOLD, "场景头目").any { it.id == card.id })
        assertEquals(listOf(31000010, 31000030), card.rows(BossGroup.FIELD).map { it.npcId })
    }

    @Test
    fun `多重归属的组在各分组都出现 卡头徽标列出全部场合`() {
        val sentinel = BossTestData.boss("Tree Sentinel@3251")
        assertEquals(listOf(BossGroup.NIGHT, BossGroup.STRONGHOLD, BossGroup.FIELD, BossGroup.OTHER, BossGroup.UNPLACED), sentinel.groups)
        sentinel.groups.filter { !it.isHiddenByDefault }.forEach { group ->
            assertTrue(index.cards(group).any { it.id == sentinel.id }, "大树守卫应出现在 ${group.key}")
        }
        assertFalse(index.cards(BossGroup.EVERGAOL).any { it.id == sentinel.id })
        assertEquals(
            listOf(
                Triple("守夜首领", false, false), Triple("场景头目", true, false), Triple("据点首领", false, false),
                Triple("大空洞高塔首领", false, false), Triple("未放置", false, true),
            ),
            dataset.roleBadges(sentinel.roles, BossGroup.FIELD).map { Triple(it.title, it.current, it.hidden) },
        )
        assertEquals(listOf("大空洞高塔首领"), dataset.roleBadges(sentinel.roles, BossGroup.OTHER).filter { it.current }.map { it.title })
        assertTrue(dataset.roleBadges(sentinel.roles, null).all { it.current }, "不传分组时全部着色")

        val multi = index.multiGroupCards
        assertEquals(49, multi.size)
        assertTrue(multi.any { it.id == "boss-Bell Bearing Hunter@3100" })
        assertTrue(multi.all { it.hasMultipleGroups && !it.isNightlord })
        multi.forEach { card ->
            card.groups.filter { !it.isHiddenByDefault }.forEach { group -> assertTrue(index.cards(group).any { it.id == card.id }) }
        }
        val visible = BossGroup.visibleCases(false)
        assertEquals(199, visible.sumOf { index.cards(it).size })
        assertEquals(122, visible.flatMap { g -> index.cards(g).map { it.id } }.toSet().size)

        val flyingRow = BossTestData.row(45000010)
        assertEquals(7753, flyingRow.scalingId)
        assertEquals("night", flyingRow.threat)
        assertEquals(listOf("field"), flyingRow.roles)
        assertEquals(0, index.cards(BossGroup.NIGHT, "丘陵飞龙").size, "不再出现在守夜首领")
        assertEquals(1, index.cards(BossGroup.FIELD, "丘陵飞龙").size)

        val lipra = BossTestData.lord(4)
        assertEquals(listOf(BossGroup.NIGHTLORD), lipra.groups)
        assertEquals(
            listOf("突袭事件" to false, "地图事件" to false, "夜王战" to true, "未放置" to false),
            dataset.roleBadges(lipra.roles, BossGroup.NIGHTLORD).map { it.title to it.current },
        )
        assertEquals(listOf("boss-Morgott@2130"), index.cards(BossGroup.OTHER, "突袭").map { it.id })
        assertEquals(
            listOf("nightlord-0", "nightlord-2", "nightlord-3", "nightlord-4", "nightlord-6", "nightlord-8"),
            index.cards(BossGroup.NIGHTLORD, "突袭事件").map { it.id },
        )
        // 神皮使徒：六个场合、五个分组
        val apostle = BossTestData.boss("Godskin Apostle@3560")
        assertEquals(listOf("night", "stronghold", "evergaol", "tower", "event", "unplaced"), apostle.roles)
        assertEquals(listOf(BossGroup.NIGHT, BossGroup.STRONGHOLD, BossGroup.EVERGAOL, BossGroup.OTHER, BossGroup.UNPLACED), apostle.groups)
        listOf(BossGroup.NIGHT, BossGroup.STRONGHOLD, BossGroup.EVERGAOL, BossGroup.OTHER).forEach { group ->
            assertTrue(index.cards(group, "神皮使徒").any { it.id == apostle.id }, group.key)
        }
    }

    @Test
    fun `出处摘要 表名 行 · 地图 与 macOS 的 BossRoleEvidence summary 同一口径`() {
        val cases = listOf(
            Triple(31000020, "night", "LotResultPlayAreaParam bossId1 = 4924 · m49_24_00_00"),
            Triple(31000020, "tower", "LotResultSmallBaseAndSpot smallBaseMapId = 4924 · m49_24_00_00"),
            Triple(31000010, "field", "ChaosMatchingMutationEnemyTableParam 46560000 · m46_56_00_00"),
            Triple(31000040, "stronghold", "SmallBaseMapVariationParam 5380 · m53_80_00_00"),
            Triple(31000000, "unplaced", "MSB"),
            Triple(21300520, "other", "MSB m35_90_00_00"),
            Triple(600030010, "invader", "SmallbaseInvationNpcParam 100"),
        )
        cases.forEach { (npcId, role, expected) ->
            assertEquals(expected, BossTestData.row(npcId).evidence(role).first().summary, "$npcId / $role")
        }
        assertEquals(BossRoleText.evidenceMissing, BossRoleEvidence(1, null, "", "", "—", "").summary)
        assertEquals("出处：数据未内置", BossRoleEvidence(null, null, "", "", "", "").summary)
        val stronghold = dataset.evidenceLines(BossTestData.row(31000040), false).first()
        assertEquals("SmallBaseMapVariationParam 5380 · m53_80_00_00", stronghold.items.first().summary)
        assertEquals("Eastern Underground Fort (Icon) - Rot", stronghold.items.first().note)
        assertTrue(stronghold.items.first().hint.startsWith("m53_80_00_00："), stronghold.items.first().hint)
        val night = dataset.evidenceLines(BossTestData.row(31000020), false).first()
        assertEquals(
            "m49_24_00_00：Night Boss - Bell-bearing Hunter (Elemer) · c3100_9000（entityId 49240800）",
            night.items.first().hint,
        )
    }

    @Test
    fun `展开区出场场合小节 每个场合第一条出处 另有几条 展开全部 出处来自哪条原始行`() {
        val gladius = BossTestData.row(75000020)
        assertEquals(listOf(75000020, 75001020, 75002020, 75003020), gladius.npcIds)
        val lines = dataset.evidenceLines(gladius, false)
        assertEquals(
            listOf(listOf("夜王战", 3, 1, 2), listOf("未放置", 1, 1, 0)),
            lines.map { listOf(it.title, it.total, it.items.size, it.more) },
        )
        assertNull(lines[0].items[0].npcId, "出处就是本行时不标「行 N」")
        assertEquals(75001020, lines[1].items[0].npcId, "出处来自被合并掉的原始行时标出来")
        assertEquals("另有 2 条出处", BossRoleText.evidenceMore(lines[0].more))
        assertTrue(gladius.hasMoreEvidence)
        assertEquals(listOf(3 to 0, 1 to 0), dataset.evidenceLines(gladius, true).map { it.items.size to it.more })
        assertFalse(BossTestData.row(31000020).hasMoreEvidence)

        val broken = fight(
            """{"npcId":10,"roles":["tower","night","night"],"roleEvidence":{"night":[{"npcId":10,"msb":"m49_24_00_00",
               "table":"LotResultPlayAreaParam","row":"bossId1 = 4924","note":"测试"}]}}""",
        )
        val brokenLines = dataset.evidenceLines(broken, false)
        assertEquals(listOf("night" to false, "tower" to true), brokenLines.map { it.role to it.missing })
        assertEquals("LotResultPlayAreaParam bossId1 = 4924 · m49_24_00_00", brokenLines[0].items[0].summary)
        assertTrue(dataset.evidenceLines(fight("""{"npcId":2}"""), false).isEmpty(), "没有 roles 的行页面写「出场场合：数据未内置」")
        rows.forEach { row ->
            dataset.evidenceLines(row, true).forEach { line ->
                assertFalse(line.missing, "npcId ${row.npcId} / ${line.role}")
                line.items.forEach { item ->
                    assertTrue(item.summary.isNotEmpty() && !item.summary.contains("null"), "npcId ${row.npcId}：${item.summary}")
                }
            }
        }
    }

    @Test
    fun `合并行的逐行场合 macOS 的 rowRolesSummary`() {
        assertEquals(
            "逐行场合：夜王战 75000020 / 75002020 / 75003020；未放置 75001020",
            dataset.rowRolesSummary(BossTestData.row(75000020)),
        )
        val withLines = rows.filter { dataset.rowRolesSummary(it) != null }
        assertEquals(50, withLines.size, "各原始行场合不同的合并行 50 个")
        assertEquals(withLines.size, rows.count { row -> row.rowRoles.values.toSet().size > 1 })
        assertNull(dataset.rowRolesSummary(BossTestData.row(31000020)))
        val row10 = fight("""{"npcId":10,"roles":["night","tower"],"rowRoles":{"10":["night","tower"],"x":["field"]}}""")
        assertEquals(listOf(listOf("night", "tower") to listOf(10)), row10.rowRoleGroups)
        assertEquals(mapOf(10 to listOf("night", "tower")), row10.rowRoles, "rowRoles 里转不成 npcId 的键丢掉")
        assertNull(bareDataset.rowRolesSummary(row10))
        val row11 = fight("""{"npcId":11,"npcIds":[11,12],"roles":["field","unplaced"],"rowRoles":{"11":["field"],"12":["unplaced"]}}""")
        assertTrue(row11.hasMixedRowRoles)
        assertEquals("逐行场合：场景头目 11；未放置 12", bareDataset.rowRolesSummary(row11))
        val combo = fight("""{"npcId":1,"npcIds":[1,2],"rowRoles":{"1":["tower","night"],"2":["unplaced"]}}""")
        assertEquals("逐行场合：守夜首领 + 大空洞高塔首领 1；未放置 2", dataset.rowRolesSummary(combo))
    }

    @Test
    fun `卡片级场合一览与威胁档位小字`() {
        val sentinel = BossTestData.boss("Tree Sentinel@3251")
        assertEquals(
            listOf("night" to 1, "field" to 1, "stronghold" to 1, "tower" to 1, "unplaced" to 4),
            sentinel.roleRowCounts(),
        )
        assertEquals("场景头目 · 2 行", BossPageText.roleRowsChip("场景头目", 2))
        val tiers = BossTestData.indexOf(
            """{"nightBosses":[
                {"nameEn":"A","chrIds":[1],"tier":"night","tiers":["field","night"],"variants":[{"npcId":1}]},
                {"nameEn":"B","chrIds":[2],"tier":"night","tiers":[],"variants":[{"npcId":2}]},
                {"nameEn":"C","chrIds":[3],"variants":[{"npcId":3}]},
                {"nameEn":"D","chrIds":[4],"tier":"","variants":[{"npcId":4}]}]}""",
        ).cards.map { it.tiers }
        assertEquals(listOf(listOf("field", "night"), listOf("night"), listOf("field"), emptyList()), tiers)
        assertEquals(listOf("field", "night"), BossTestData.boss("Large Golden Hippopotamus@5010").tiers)
        assertEquals(emptyList(), BossTestData.lord(0).tiers, "夜王没有 tier")
        index.cards.filter { !it.isNightlord }.forEach { assertTrue(it.tiers.isNotEmpty(), "${it.id} 应有威胁档位小字") }
        assertEquals("威胁档位 · 守夜首领威胁档", BossRoleText.threatTierCaption(listOf("night")))
        assertEquals("威胁档位 · 守夜首领威胁档 / 野外首领威胁档", BossRoleText.threatTierCaption(listOf("night", "field", "night")))
        assertEquals("威胁档位 · 无", BossRoleText.threatTierCaption(emptyList()))
        assertEquals("威胁档位 · brandNew", BossRoleText.threatTierCaption(listOf("brandNew")))
        assertTrue(index.cards.filter { !it.isNightlord }.all { card -> card.rows.all { it.threatTierCaption != null } })
        assertTrue(dataset.threatRoleMismatch(BossTestData.row(31000010)), "铃珠猎人野外版挂 7753")
        assertFalse(dataset.threatRoleMismatch(BossTestData.row(31000020)), "守夜行挂守夜档，不补")
        assertFalse(dataset.threatRoleMismatch(BossTestData.row(31000000)), "默认收起的未放置行不补")
        assertFalse(dataset.threatRoleMismatch(fight("""{"npcId":1,"scalingId":7753}""")), "没有 roles 的行不补")
        assertEquals(45, rows.count { dataset.threatRoleMismatch(it) })
        val crucible = BossTestData.boss("Crucible Knight@2500")
        assertTrue(crucible.rows.any { dataset.threatRoleMismatch(it) && "night" in it.roles })
        val carian = BossTestData.boss("Royal Carian Knight@3252")
        assertEquals("威胁档位 · 守夜首领威胁档", BossRoleText.threatTierCaption(carian.tiers))
    }

    @Test
    fun `搜索索引收全部场合的 roleNames 中英文名 不收取值 key 与判定口径`() {
        assertEquals(listOf("守夜首领", "Night Boss", "未放置", "Not Placed"), BossDataIndex.roleSearchTerms(listOf("unplaced", "night"), dataset))
        assertEquals(listOf("大空洞高塔首领"), BossDataIndex.roleSearchTerms(listOf("tower"), bareDataset), "缺 roleNames 时退内置中文名，没有英文名就不收")
        assertEquals(index.cards(BossGroup.EVERGAOL).size, index.cards(BossGroup.EVERGAOL, "EVERGAOL").size)
        val towerCards = index.cards(BossGroup.OTHER).filter { "tower" in it.roles }
        assertTrue(towerCards.isNotEmpty())
        assertEquals(towerCards.size, index.cards(BossGroup.OTHER, "高塔").count { "tower" in it.roles })
        assertEquals(towerCards.size, index.cards(BossGroup.OTHER, "Great Hollow Tower").size)
        assertEquals(0, index.cards(BossGroup.NIGHT, "LotResultPlayAreaParam").size)
        BossGroup.entries.forEach { group -> assertEquals(0, index.cards(group, "unplaced", includeHidden = true).size, group.key) }
        val unplacedHits = index.cards(BossGroup.NIGHT, "未放置")
        assertTrue(unplacedHits.isNotEmpty())
        unplacedHits.forEach { card ->
            assertTrue(dataset.roleBadges(card.roles, BossGroup.NIGHT).any { it.title == "未放置" }, card.id)
        }
        assertEquals(18, index.cards(BossGroup.NIGHTLORD, "nightlord battle").size)
        assertTrue(index.cards.filter { it.isNightlord }.all { card -> dataset.roleBadges(card.roles, BossGroup.NIGHTLORD).any { it.title == "夜王战" } })
        val gladius = BossTestData.lord(0)
        assertTrue(gladius.matches("夜王战") && gladius.matches("突袭事件"))
        assertTrue(index.cards.all { !it.searchKey.contains("其它场合") })
        assertEquals(
            listOf("boss-Stonedigger Troll@4603", "boss-Troll@4600"),
            index.cards(BossGroup.OTHER, "坑道精英").map { it.id },
        )
    }

    @Test
    fun `代表行第一步按当前分组过滤 roles 其后四步顺序不变`() {
        val sample = listOf(
            fight("""{"npcId":1,"hp":9000,"roles":["night"]}"""),
            fight("""{"npcId":2,"hp":5000,"roles":["field"],"labelZh":"血条实体"}"""),
            fight("""{"npcId":3,"hp":4000,"roles":["field"],"noReward":true}"""),
            fight("""{"npcId":4,"hp":3000,"roles":["field"]}"""),
            fight("""{"npcId":5,"hp":2000,"roles":["stronghold","unplaced"]}"""),
            fight("""{"npcId":6,"hp":9999,"roles":["unplaced"]}"""),
        )
        assertEquals(1, BossCard.representativeRow(sample, BossGroup.NIGHT)!!.npcId)
        assertEquals(4, BossCard.representativeRow(sample, BossGroup.FIELD)!!.npcId, "排掉演出行与无奖励行")
        assertEquals(5, BossCard.representativeRow(sample, BossGroup.STRONGHOLD)!!.npcId)
        assertEquals(listOf(5, 6), BossCard.candidateRows(sample, BossGroup.UNPLACED).map { it.npcId })
        assertEquals(6, BossCard.representativeRow(sample, BossGroup.UNPLACED)!!.npcId)
        assertEquals(6, BossCard.representativeRow(sample, BossGroup.EVERGAOL)!!.npcId, "分组里一行都对不上时整池放行")
        assertEquals(6, BossCard.representativeRow(sample, null)!!.npcId, "不带分组时不按场合过滤")
        val mains = listOf(
            fight("""{"npcId":10,"hp":100,"roles":["nightlord"],"isMain":true}"""),
            fight("""{"npcId":11,"hp":900,"roles":["unplaced"],"isMain":true}"""),
            fight("""{"npcId":12,"hp":500,"roles":["nightlord"]}"""),
        )
        assertEquals(10, BossCard.representativeRow(mains, BossGroup.NIGHTLORD)!!.npcId)
        assertTrue(BossTestData.row(35600900).noReward)
        assertEquals(35600000, BossTestData.boss("Godskin Apostle@3560").representativeRow(BossGroup.UNPLACED)!!.npcId)
    }

    @Test
    fun `roles 缺失时页面照常出卡 写出场场合数据未内置而不是按 tier 猜`() {
        val legacy = BossTestData.indexOf(
            """{"nightlords":[{"menuId":1,"nameZh":"旧夜王","fights":[{"npcId":1,"hp":100,"isMain":true}]}],
                "nightBosses":[{"id":"Old@1","nameEn":"Old","tier":"night","tiers":["night"],"chrIds":[1],"variants":[{"npcId":2,"hp":50}]}]}""",
        )
        assertEquals(
            listOf(Triple("nightlord-1", listOf(BossGroup.NIGHTLORD), false), Triple("boss-Old@1", listOf(BossGroup.OTHER), false)),
            legacy.cards.map { Triple(it.id, it.groups, it.hasRoles) },
        )
        assertTrue(legacy.cards.none { it.isHiddenByDefault })
        assertEquals(0, legacy.cards(BossGroup.NIGHT).size, "tier = night 不再把它塞进守夜首领")
        assertEquals(1, legacy.cards(BossGroup.OTHER).size)
        assertEquals(listOf("night"), legacy.cards[1].tiers)
        assertEquals("出场场合：数据未内置", BossRoleText.rolesMissing)
        assertEquals(1, legacy.cards[1].displayRows(false).size)

        val dual = BossTestData.indexOf(
            """{"nightBosses":[{"id":"Dual Boss@4600","nameEn":"Dual Boss","chrIds":[4600],"tier":"night","tiers":["field","night"],
                "npcNameId":12345,
                "variants":[
                  {"npcId":10,"hp":100,"threat":"night","roles":["tower","night","night"],
                   "roleEvidence":{"night":[{"npcId":10,"msb":"m49_24_00_00","table":"LotResultPlayAreaParam","row":"bossId1 = 4924","note":"测试"}]},
                   "rowRoles":{"10":["night","tower"],"x":["field"]}},
                  {"npcId":11,"npcIds":[11,12],"hp":90,"threat":"night","roles":["unplaced","field"],"rowRoles":{"11":["field"],"12":["unplaced"]}},
                  {"npcId":13,"hp":80,"threat":"field","roles":["unplaced"]},
                  {"npcId":14,"hp":70,"roles":["futureRole"]}]}]}""",
        )
        val card = dual.cards.single()
        assertEquals(listOf("night", "field", "tower", "unplaced", "futureRole"), card.roles)
        assertEquals(listOf(BossGroup.NIGHT, BossGroup.FIELD, BossGroup.OTHER, BossGroup.UNPLACED), card.groups)
        assertEquals(BossGroup.NIGHT, card.group, "主分组取第一个")
        assertEquals(11, card.representativeRow(BossGroup.FIELD)!!.npcId, "它的 threat 是 night 也不影响")
        assertEquals(10, card.representativeRow(BossGroup.NIGHT)!!.npcId)
        assertEquals(listOf(10, 11, 14), card.displayRows(false).map { it.npcId })
        assertEquals(1, card.hiddenRowCount(false))
        assertEquals(4, card.displayRows(true).size)
        assertEquals(listOf(card.id), dual.cards(BossGroup.FIELD).map { it.id })
        assertEquals(listOf(card.id), dual.cards(BossGroup.NIGHT).map { it.id })
        assertEquals(listOf("守夜", "守夜", "野外"), card.rows.mapNotNull { it.threatTitle })
        assertEquals("威胁档位 · 守夜首领威胁档", card.rows.firstNotNullOf { it.threatTierCaption })
        assertEquals("futureRole", dual.dataset.roleTitle("futureRole"))
        assertEquals("场景头目", dual.dataset.roleTitle("field"))
        assertTrue(dual.cards(BossGroup.FIELD, "12345").any { it.id == card.id }, "npcNameId 也应能搜到")
        assertTrue(dual.cards(BossGroup.FIELD, "11").any { it.id == card.id }, "按变体 npcId 应能搜到")
        val row10 = card.rows.first { it.npcId == 10 }
        assertEquals(listOf("night", "tower"), row10.roles)
        assertEquals(1, row10.evidence("night").size)
        assertTrue(row10.evidence("tower").isEmpty())
    }

    @Test
    fun `底部出场场合说明 场合 → 分组 卡片计数 默认隐藏的分组标注`() {
        val rowsOverview = index.roleOverviewRows()
        assertEquals(14, rowsOverview.size)
        assertEquals("出场场合说明（14 种）", BossRoleText.overviewTitle(rowsOverview.size))
        assertEquals(
            mapOf(
                "night" to ("守夜首领" to "40 组"),
                "prelude" to ("其它场合" to "6 组"),
                "field" to ("场景头目" to "35 组"),
                "stronghold" to ("据点首领" to "51 组"),
                "mine" to ("其它场合" to "2 组"),
                "evergaol" to ("封印监牢" to "10 组"),
                "tower" to ("其它场合" to "26 组"),
                "raid" to ("其它场合" to "1 组 · 夜王 6"),
                "invader" to ("其它场合" to "10 组"),
                "event" to ("其它场合" to "5 组 · 夜王 1"),
                "nightlord" to ("夜王" to "夜王 18"),
                "summon" to ("随从/召唤物（默认隐藏）" to "11 组"),
                "other" to ("其它场合" to "8 组"),
                "unplaced" to ("未放置（默认隐藏）" to "93 组 · 夜王 15"),
            ),
            rowsOverview.associate { it.role to (it.groupText to it.countText) },
        )
        BossRoleCatalog.order.forEach { role ->
            val row = rowsOverview.first { it.role == role }
            assertEquals(
                BossRoleText.roleCountText(dataset.roleSummary.getValue(role), dataset.roleSummaryDetail.getValue(role).nightlords),
                row.countText,
                role,
            )
            assertTrue(row.description.isNotEmpty())
        }
        val extra = BossTestData.indexOf(
            """{"roleNames":{"zeta":{},"alpha":{}},"roleSummary":{"beta":1},"nightlords":[{"menuId":1,"fights":[{"npcId":1}]}]}""",
        ).dataset
        assertEquals(listOf("alpha", "beta", "zeta"), extra.orderedRoles.drop(14))
        assertEquals("与威胁档位的对照（数据集 notes.roleAudit，4 条）", BossRoleText.auditTitle(dataset.notes!!.roleAuditSummary.size))
    }
}
