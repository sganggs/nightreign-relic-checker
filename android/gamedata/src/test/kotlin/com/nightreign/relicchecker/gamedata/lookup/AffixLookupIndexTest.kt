package com.nightreign.relicchecker.gamedata.lookup

import com.nightreign.relicchecker.catalog.AffixCatalog
import com.nightreign.relicchecker.gamedata.lookup.LookupFixtures.CURSE_EFFECT
import com.nightreign.relicchecker.gamedata.lookup.LookupFixtures.DEEP_A_EFFECT
import com.nightreign.relicchecker.gamedata.lookup.LookupFixtures.DEEP_BC_EFFECT
import com.nightreign.relicchecker.gamedata.lookup.LookupFixtures.FIXED_RELIC_ID
import com.nightreign.relicchecker.gamedata.lookup.LookupFixtures.NORMAL_EFFECT
import com.nightreign.relicchecker.gamedata.lookup.LookupFixtures.RANDOM_RELIC_ID
import com.nightreign.relicchecker.gamedata.lookup.LookupFixtures.affixById
import com.nightreign.relicchecker.gamedata.lookup.LookupFixtures.bare
import com.nightreign.relicchecker.gamedata.lookup.LookupFixtures.catalog
import com.nightreign.relicchecker.gamedata.lookup.LookupFixtures.index
import com.nightreign.relicchecker.gamedata.lookup.LookupFixtures.relicData
import com.nightreign.relicchecker.rules.CheckMode
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * 与 Windows `tests/lookup_index.test.mjs` 逐条对应：测试名后的引号里是那边的用例名。
 * 口径以 macOS RelicCore/AffixLookup.swift 为准（两端互相对拍过）；Windows 端的分页 / 行数上限
 * 属于渲染层，手机端与 macOS 一样「默认列前 N 条 + 就地展开」，对应断言写在 affixLookupShown 上。
 */
class AffixLookupIndexTest {
    private fun modeHits(effectId: Int) = index.report(effectId)!!.modeHits.associateBy { it.mode }

    @Test
    fun `reverse index covers every pool member and every slot (buildLookupIndex)`() {
        assertEquals(relicData.relics.size, index.relics.size)
        assertEquals(relicData.pools.size, index.poolMembers.size)

        // effectId → 池 覆盖每个池的全部成员
        val memberTotal = relicData.pools.values.sumOf { it.toSet().size }
        assertEquals(memberTotal, index.poolsByEffect.values.sumOf { it.size })

        // 池 → 槽位 覆盖每个遗物的每个非空槽（含诅咒槽）
        val slotRefs = relicData.relics.sumOf { relic ->
            relic.slots.count { it != -1 } + relic.curseSlots.count { it != -1 }
        }
        assertEquals(slotRefs, index.slotsByPool.values.sumOf { it.size })

        // 遗物行按 ID 升序，且带好标签
        val ids = index.relics.map { it.id }
        assertEquals(ids.sorted(), ids)
        val unique = index.relic(FIXED_RELIC_ID)!!
        assertEquals("唯一遗物", unique.kindLabel)
        assertTrue(unique.isUnique)
        assertEquals("红", unique.colorLabel)
    }

    @Test
    fun `degraded index keeps affix facts when the relic table is missing (buildLookupIndex throws)`() {
        assertFalse(bare.hasRelicData)
        assertTrue(bare.relics.isEmpty())
        assertEquals(catalog.affixes.size, bare.affixes.size)
        assertEquals(0, bare.obtainableRelicCount)
        val report = bare.report(DEEP_A_EFFECT)!!
        assertFalse(report.hasRelicData)
        assertEquals(0, report.totalRelicCount)
        assertTrue(report.conflicts.isNotEmpty())
        // 没有物品表时用词条库自带的 poolIds 兜底
        assertEquals(listOf(2_000_000), report.poolIds)
        assertEquals(1, report.livePoolCount)
        assertTrue(report.deepHits.first { it.poolId == 2_000_000 }.contains)
        assertTrue(report.deepHits.all { it.memberCount == 0 }, "降级模式不知道池有多大")
        assertEquals("池 2000000", LookupCopy.poolRowMeta(2_000_000, 0, 0))
    }

    @Test
    fun `searchAffixes matches name alias category and effectId with folding`() {
        assertTrue(index.searchAffixes("生命力＋１").any { it.effectId == NORMAL_EFFECT })
        assertTrue(index.searchAffixes(NORMAL_EFFECT.toString()).any { it.effectId == NORMAL_EFFECT })
        // 大小写 / 空格 / 全半角差异不影响命中
        assertTrue(index.searchAffixes("  生命力 ＋１ ").any { it.effectId == NORMAL_EFFECT })
        assertTrue(index.searchAffixes("生命力+1").any { it.effectId == NORMAL_EFFECT })
        assertTrue(index.searchAffixes("提升物理攻击力+3").any { it.effectId == DEEP_A_EFFECT })
        assertTrue(index.searchAffixes("攻击力", scope = AffixLookupScope.CATALOG).size > 10)
        // 别名也能搜到
        val aliased = catalog.affixes.first { it.aliases.isNotEmpty() }
        assertTrue(index.searchAffixes(aliased.aliases.first()).any { it.effectId == aliased.effectId })

        // 词条库范围：全部 527 条，按 (sortId, effectId) 升序
        val all = index.searchAffixes("", scope = AffixLookupScope.CATALOG)
        assertEquals(catalog.affixes.size, all.size)
        all.zipWithNext { prev, cur ->
            assertTrue(prev.sortId < cur.sortId || (prev.sortId == cur.sortId && prev.effectId < cur.effectId))
        }

        // 可排除负面词条
        val positives = index.searchAffixes("", includeCurses = false, scope = AffixLookupScope.CATALOG)
        assertEquals(catalog.affixes.count { !it.isCurse }, positives.size)

        // 全部 = 词条库 ∪ 物品表补充；物品表补充按分类也能搜到
        assertEquals(527 + 1552, index.searchAffixes("").size)
        val extras = index.searchAffixes("", scope = AffixLookupScope.EXTRAS)
        assertEquals(1552, extras.size)
        assertTrue(extras.none { it.inCatalog })
        assertEquals(extras.size, index.searchAffixes("物品表补充").size)
    }

    @Test
    fun `compatibilityPeers lists the other members of the group and -1 has none`() {
        val peers = index.conflicts(NORMAL_EFFECT)
        val affix = affixById.getValue(NORMAL_EFFECT)
        assertTrue(peers.isNotEmpty())
        assertTrue(peers.all { it.compatibilityId == affix.compatibilityId })
        assertTrue(peers.none { it.effectId == affix.effectId })
        peers.zipWithNext { a, b -> assertTrue(a.sortId <= b.sortId) }

        val loner = catalog.affixes.first { it.compatibilityId == -1 }
        assertTrue(index.conflicts(loner.effectId).isEmpty())

        // 遗物物品表不可用时退回词条库内的同组词条
        assertTrue(bare.conflicts(NORMAL_EFFECT).all { affixById.containsKey(it.effectId) })
        assertEquals(peers.map { it.effectId }, bare.conflicts(NORMAL_EFFECT).map { it.effectId })
    }

    @Test
    fun `compatibilityPeers only counts affixes that can appear on a relic`() {
        val sample = catalog.affixes.first { it.compatibilityId == 100 }
        val peers = index.conflicts(sample.effectId)
        assertEquals(102, catalog.affixes.count { it.compatibilityId == 100 })
        assertEquals(102, peers.size + 1, "互斥池 100 共 102 条，不含从不进池的参数表效果")

        val pooled = index.poolsByEffect.keys
        val strays = index.affixes.filter { it.compatibilityId == 100 && !it.inCatalog && it.effectId !in pooled }
        assertTrue(strays.size > 900, "数据里确实有大量不进池、却挂着 compatibilityId 100 的效果")
        val peerIds = peers.map { it.effectId }.toSet()
        assertTrue(strays.none { it.effectId in peerIds })

        // 反过来：进了池的 extraAffixes 必须算进互斥组（存档审计会判它们互斥）
        val catalogGroups = catalog.affixes.map { it.compatibilityId }.toSet()
        val pooledExtra = index.affixes.firstOrNull {
            !it.inCatalog && it.effectId in pooled && it.compatibilityId != -1 && it.compatibilityId in catalogGroups
        }
        assertNotNull(pooledExtra, "应存在与词条库共组的池内 extraAffixes")
        val host = catalog.affixes.first { it.compatibilityId == pooledExtra.compatibilityId }
        assertTrue(index.conflicts(host.effectId).any { it.effectId == pooledExtra.effectId })
    }

    @Test
    fun `modeSources reports availability and candidate pools per mode without slot numbers`() {
        val normal = index.report(NORMAL_EFFECT)!!.modeHits
        assertEquals(listOf(CheckMode.CURRENT_NORMAL, CheckMode.LEGACY_NORMAL, CheckMode.DEEP_POSITIVE), normal.map { it.mode })
        assertEquals(AFFIX_LOOKUP_MODES, normal.map { it.mode })
        assertTrue(normal.none { it.mode == CheckMode.COMPATIBILITY_ONLY }, "顺序/互斥口径不算掉落来源")

        val current = normal.first { it.mode == CheckMode.CURRENT_NORMAL }
        assertTrue(current.isAvailable)
        assertEquals(listOf(110, 210, 310), current.pools.map { it.poolId }, "候选池按 id 升序")
        assertTrue(current.pools.all { it.contains && it.memberCount == 340 })
        assertTrue(current.pools.all { it.relicCount > 0 })

        val legacy = normal.first { it.mode == CheckMode.LEGACY_NORMAL }
        assertEquals(listOf(100, 200, 300), legacy.pools.map { it.poolId })
        assertTrue(legacy.pools.all { it.contains })

        // 深夜 A 池词条不会从普通遗物掉落
        val deepOnly = modeHits(DEEP_A_EFFECT)
        assertFalse(deepOnly.getValue(CheckMode.CURRENT_NORMAL).isAvailable)
        assertFalse(deepOnly.getValue(CheckMode.LEGACY_NORMAL).isAvailable)
        val deepMode = deepOnly.getValue(CheckMode.DEEP_POSITIVE)
        assertTrue(deepMode.isAvailable)
        assertEquals(listOf(2_000_000, 2_100_000, 2_200_000), deepMode.pools.map { it.poolId })
        assertEquals(listOf(true, false, false), deepMode.pools.map { it.contains })
        assertEquals(listOf(2_000_000), deepMode.hitPools.map { it.poolId })
    }

    @Test
    fun `poolLabel uses hole tiers never slot numbers (same table as macOS)`() {
        assertEquals("旧池 · 1 孔层", affixPoolLabel(100))
        assertEquals("旧池 · 2 孔层", affixPoolLabel(200))
        assertEquals("旧池 · 3 孔层", affixPoolLabel(300))
        assertEquals("1.03 · 1 孔层", affixPoolLabel(110))
        assertEquals("1.03 · 2 孔层", affixPoolLabel(210))
        assertEquals("1.03 · 3 孔层", affixPoolLabel(310))
        assertEquals("深夜 A 池", affixPoolLabel(2_000_000))
        assertEquals("深夜 B 池", affixPoolLabel(2_100_000))
        assertEquals("深夜 C 池", affixPoolLabel(2_200_000))
        assertEquals("深夜诅咒池", affixPoolLabel(3_000_000))
        assertEquals("池 707121100", affixPoolLabel(707_121_100))
        listOf(100, 200, 300, 110, 210, 310).forEach { poolId ->
            assertFalse(affixPoolLabel(poolId).contains("槽"), "池 $poolId 的标签不应含「槽」")
            assertTrue(affixPoolLabel(poolId).contains("孔层"))
        }
        assertTrue(affixPoolDetail(2_000_000).contains("同一行"))
        assertEquals("", affixPoolDetail(707_121_100))
    }

    @Test
    fun `hole tier pools nest and three hole relics start with the three hole tier`() {
        listOf(listOf(100, 200, 300), listOf(110, 210, 310)).forEach { tiers ->
            val sets = tiers.map { index.poolMembers[it].orEmpty().toSet() }
            assertTrue(sets.all { it.isNotEmpty() })
            assertTrue(sets[1].containsAll(sets[0]), "${tiers[0]} 应 ⊆ ${tiers[1]}")
            assertTrue(sets[2].containsAll(sets[1]), "${tiers[1]} 应 ⊆ ${tiers[2]}")
        }
        var threeSlot = 0
        index.searchRelics("").filter { !it.deep }.forEach { entry ->
            val pools = entry.slots.filter { !it.isEmpty }.map { it.poolId }
            if (pools.size != 3 || !pools.all { it in listOf(100, 200, 300, 110, 210, 310) }) return@forEach
            threeSlot += 1
            assertTrue(pools == listOf(300, 200, 100) || pools == listOf(310, 210, 110), "3 孔遗物 ${entry.id}：$pools")
        }
        assertTrue(threeSlot > 0, "应存在使用孔数层池的 3 孔遗物")
    }

    @Test
    fun `modeSources agrees with Affix isEligible for every catalog affix`() {
        catalog.affixes.forEach { affix ->
            index.report(affix.effectId)!!.modeHits.forEach { hit ->
                assertEquals(
                    affix.isEligible(hit.mode),
                    hit.isAvailable,
                    "词条 ${affix.effectId} 在口径 ${hit.mode} 的判定与 Affix.isEligible 不一致",
                )
            }
        }
    }

    @Test
    fun `deepSources gives A B C membership and curse pairing`() {
        val poolA = index.report(DEEP_A_EFFECT)!!
        assertEquals(listOf(true, false, false), poolA.deepHits.map { it.contains })
        assertEquals(listOf("深夜 A 池", "深夜 B 池", "深夜 C 池"), poolA.deepHits.map { it.label })
        assertEquals(3_000_000, poolA.cursePoolHit.poolId)
        assertFalse(poolA.cursePoolHit.contains)
        assertEquals(relicData.pools.getValue(3_000_000).size, poolA.cursePoolHit.memberCount)
        assertTrue(poolA.cursePoolHit.relicCount > 0, "诅咒池应有正常可获得的深夜遗物在用")
        assertTrue(poolA.affix.requiresCurse)
        assertFalse(poolA.affix.isCurse)
        val curses = index.curseAffixes()
        assertEquals(relicData.pools.getValue(3_000_000).size, curses.size)
        assertTrue(curses.all { it.isCurse })
        curses.zipWithNext { a, b -> assertTrue(a.sortId <= b.sortId) }

        val poolBC = index.report(DEEP_BC_EFFECT)!!
        assertEquals(listOf(false, true, true), poolBC.deepHits.map { it.contains })
        assertFalse(poolBC.affix.requiresCurse)

        val curse = index.report(CURSE_EFFECT)!!
        assertTrue(curse.affix.isCurse)
        assertTrue(curse.deepHits.none { it.contains }, "诅咒词条不在 A/B/C 正面池里")
        assertTrue(curse.cursePoolHit.contains)

        // 数据集里「A 池成员」与「requiresCurse」完全一致
        val poolAIds = relicData.pools.getValue(2_000_000).toSet()
        val requiresCurseIds = catalog.affixes.filter { it.requiresCurse }.map { it.effectId }.toSet()
        assertEquals(requiresCurseIds, poolAIds)
    }

    @Test
    fun `relicSourcesFor separates fixed and random hits`() {
        val fixedEffectId = relicData.pools.getValue(relicData.relics.first { it.id == FIXED_RELIC_ID }.slots[0])[0]
        val sources = index.report(fixedEffectId)!!
        val fixedRow = sources.fixedRelics.firstOrNull { it.relicId == FIXED_RELIC_ID }
        assertNotNull(fixedRow, "唯一遗物 1660 应作为固定词条来源出现")
        assertEquals("唯一遗物", fixedRow.kindLabel)
        assertEquals("红", fixedRow.colorLabel)
        assertEquals(RelicSlotRole.POSITIVE, fixedRow.role)
        assertTrue(fixedRow.poolIds.all { index.poolMembers.getValue(it).size == 1 })
        assertTrue(sources.randomRelics.isNotEmpty(), "该词条同时在深夜 B/C 随机池里")
        assertEquals(sources.fixedRelics.size + sources.randomRelics.size, sources.totalRelicCount)
        // 同一词条重复查询结果一致（页面按 effectId remember）
        assertEquals(sources, index.report(fixedEffectId))

        // 普通随机词条：商店遗物 202 从随机池出
        val normal = index.report(NORMAL_EFFECT)!!
        val shopRow = normal.randomRelics.firstOrNull { it.relicId == RANDOM_RELIC_ID }
        assertNotNull(shopRow)
        assertEquals("商店遗物", shopRow.kindLabel)
        assertEquals(RelicSlotRole.POSITIVE, shopRow.role)
        // 命中记录只报池、按 id 升序，不报槽序号（3 孔遗物的 slots 是 [310, 210, 110]）
        assertEquals(listOf(110, 210, 310), shopRow.poolIds)
        // 同一条词条也是唯一遗物 10002 / 11003 的固定词条；池 7000000 的无名参数行只计 hidden
        assertEquals(listOf(10002, 11003), normal.fixedRelics.map { it.relicId })
        assertTrue(normal.fixedRelics.all { index.relic(it.relicId)!!.isObtainable })
        assertTrue(normal.hiddenRelicCount > 0, "无名称参数行应计入 hidden 而不是列出来")
        assertTrue(normal.randomRelics.none { it.relicId == 10002 }, "同一件遗物不会同时出现在两个分组里")

        // 诅咒词条只挂在正常可获得的深夜遗物的诅咒槽上
        val curse = index.report(CURSE_EFFECT)!!
        assertTrue(curse.totalRelicCount > 0)
        val curseRows = curse.fixedRelics + curse.randomRelics
        assertTrue(curseRows.all { it.role == RelicSlotRole.CURSE })
        assertTrue(curseRows.all { it.deep && index.relic(it.relicId)!!.isObtainable })

        // 出处行按 ID 升序
        val ids = normal.randomRelics.map { it.relicId }
        assertEquals(ids.sorted(), ids)
    }

    @Test
    fun `cheat range out of range and unnamed rows are never listed, only counted as hidden`() {
        val cheats = index.relics.filter { it.id in CHEAT_RELIC_ID_RANGE }
        assertEquals(72, cheats.size)
        assertTrue(cheats.all { it.info.name.isNotEmpty() }, "作弊器区段的遗物都有名字")
        assertTrue(cheats.none { it.isObtainable })
        assertTrue(cheats.all { it.unobtainableReason.contains("作弊器") })
        // 它们的槽位池是空池 1，当成正常遗物展示只会渲染出「随机 0 条」
        assertTrue(cheats.all { entry -> entry.slots.all { it.isEmpty || it.poolSize == 0 } })

        // 逐条词条兜底：列出来的行必须全部是正常可获得的遗物
        catalog.affixes.forEach { affix ->
            val report = index.report(affix.effectId)!!
            (report.fixedRelics + report.randomRelics).forEach { hit ->
                val entry = index.relic(hit.relicId)!!
                assertTrue(entry.isObtainable, "词条 ${affix.effectId} 列出了不会正常获得的遗物 ${hit.relicId}")
                assertTrue(hit.relicId in OBTAINABLE_RELIC_ID_RANGE)
                assertFalse(hit.relicId in CHEAT_RELIC_ID_RANGE)
            }
        }

        // 超范围但有名字的参数行（10 暗痕 / 11 为王之证 / 20 情景原石）同样排除
        listOf(10, 11, 20).forEach { relicId ->
            val entry = index.relic(relicId)!!
            assertTrue(entry.info.name.isNotEmpty() && !entry.isObtainable)
            assertTrue(entry.unobtainableReason.contains("超出合法 ID 区间"))
        }
        // 判定顺序与 Windows 一致：区段 → 区间 → 无名 → 空池
        assertEquals("超出合法 ID 区间（100–2013322）", index.relic(1)!!.unobtainableReason)
        // 真实数据里合法区间内没有无名 / 空池行；用构造数据验后两支
        val synthetic = AffixLookupIndex(
            catalog,
            RelicCatalog(
                1, "", "", "", emptyList(),
                relics = listOf(
                    RelicInfo(1500, "", 0, false, listOf(900_001, -1, -1), listOf(-1, -1, -1)),
                    RelicInfo(1501, "空池遗物", 0, false, listOf(900_002, -1, -1), listOf(-1, -1, -1)),
                    RelicInfo(1502, "正常遗物", 0, false, listOf(900_001, -1, -1), listOf(-1, -1, -1)),
                ),
                pools = mapOf(900_001 to listOf(NORMAL_EFFECT), 900_002 to emptyList()),
                extraAffixes = emptyList(),
            ),
        )
        assertEquals("参数表内部条目（没有官方名称）", synthetic.relic(1500)!!.unobtainableReason)
        assertEquals("槽位池在数据集中是空池", synthetic.relic(1501)!!.unobtainableReason)
        assertTrue(synthetic.relic(1502)!!.isObtainable)
        assertEquals(listOf(1502), synthetic.report(NORMAL_EFFECT)!!.fixedRelics.map { it.relicId })
        assertEquals(1, synthetic.report(NORMAL_EFFECT)!!.hiddenRelicCount)
    }

    @Test
    fun `relicSlotSummary gives pool sizes and previews for three slots plus curse slots`() {
        val shop = index.relic(RANDOM_RELIC_ID)!!
        assertEquals(3, shop.slotCount)
        assertEquals(0, shop.curseSlotCount)
        assertNull(shop.deepPoolGroups, "非深夜遗物按槽位展示，不做按池归并")
        assertEquals(listOf(310, 210, 110), shop.slots.map { it.poolId })
        // 槽序号与孔数层：第 1 槽用的是 3 孔层池，标签只能写孔数层
        assertEquals(listOf("1.03 · 3 孔层", "1.03 · 2 孔层", "1.03 · 1 孔层"), shop.slots.map { affixPoolLabel(it.poolId) })
        assertTrue(shop.slots.all { it.poolSize == 340 && !it.isFixed })
        assertEquals(AFFIX_LOOKUP_SLOT_PREVIEW_LIMIT, shop.slots[0].previewEffectIds.size)
        assertEquals(330, shop.slots[0].poolSize - shop.slots[0].previewEffectIds.size)
        assertNull(shop.fixedEffectIds, "随机池遗物没有固定词条")
        assertTrue(shop.slots.all { it.cursePoolId == -1 && it.cursePoolSize == 0 })

        // 唯一遗物：各槽池均为单成员 → 直接给出固定词条（按 (sortId, effectId) 升序）
        val unique = index.relic(FIXED_RELIC_ID)!!
        assertTrue(unique.isUnique)
        assertTrue(unique.slots.all { it.isFixed })
        assertEquals(listOf(6_641_000, 7_000_302, 7_000_402), unique.fixedEffectIds)
        assertTrue(unique.fixedEffectIds!!.all { index.affixName(it).isNotEmpty() && index.affix(it) != null })

        assertNull(index.relic(999_999_999))
    }

    @Test
    fun `deep relics are grouped by pool without slot numbers`() {
        val deepRelic = relicData.relics.first { relic -> relic.deep && relic.curseSlots.any { it != -1 } }
        val deep = index.relic(deepRelic.id)!!
        assertTrue(deep.deep)
        val groups = assertNotNull(deep.deepPoolGroups)
        assertTrue(groups.isNotEmpty())
        assertEquals(groups.map { it.poolId }.sorted(), groups.map { it.poolId }, "按池 id 升序")
        assertEquals(deep.slotCount, groups.sumOf { it.count }, "归并后的条数之和应等于孔数")
        assertTrue(groups.all { it.poolId in DEEP_POSITIVE_LOOKUP_POOLS })

        // A 池的那一组带诅咒池信息；数据集里 A 槽数 = 诅咒槽数
        val groupA = groups.first { it.poolId == 2_000_000 }
        assertEquals(3_000_000, groupA.slot.cursePoolId)
        assertEquals(relicData.pools.getValue(3_000_000).size, groupA.slot.cursePoolSize)
        assertEquals(groupA.count, deep.curseSlotCount, "槽位模板只保证 A 槽数 = 诅咒槽数")

        // 全库兜底：每件深夜遗物的 A 槽数都等于诅咒槽数，诅咒槽只会是 3000000
        index.relics.filter { it.deep }.forEach { entry ->
            val aCount = entry.info.slots.count { it == 2_000_000 }
            val curseCount = entry.info.curseSlots.count { it != -1 }
            assertEquals(aCount, curseCount, "深夜遗物 ${entry.id} 的 A 槽数应等于诅咒槽数")
            assertTrue(entry.info.curseSlots.all { it == -1 || it == 3_000_000 })
        }
        // 非深夜遗物一律没有诅咒槽
        assertTrue(index.relics.all { it.deep || it.info.curseSlots.all { pool -> pool == -1 } })
    }

    @Test
    fun `slots pointing at an empty pool are never treated as fixed`() {
        val emptyPoolRelic = relicData.relics.first { relic ->
            relic.slots.any { it != -1 && relicData.pools.getValue(it).isEmpty() }
        }
        val summary = index.relic(emptyPoolRelic.id)!!
        val emptySlot = summary.slots.first { it.poolId != -1 && it.poolSize == 0 }
        assertTrue(emptySlot.isEmptyPool)
        assertFalse(emptySlot.isFixed)
        assertNull(summary.fixedEffectIds)
    }

    private fun synthetic(slots: List<Int>, pools: Map<Int, List<Int>>) = AffixLookupIndex(
        catalog,
        RelicCatalog(
            relicsSchemaVersion = 1,
            gameVersion = "",
            dataVersion = "",
            generatedAt = "",
            sources = emptyList(),
            relics = listOf(RelicInfo(1500, "对拍用遗物", 0, false, slots, listOf(-1, -1, -1))),
            pools = pools,
            extraAffixes = emptyList(),
        ),
    ).relic(1500)!!.fixedEffectIds

    @Test
    fun `fixed effect rule matches core officialFixedEffects`() {
        // 对照组：单槽单成员池 → 词条完全确定
        assertEquals(listOf(7_000_000, -1, -1), synthetic(listOf(900_001, -1, -1), mapOf(900_001 to listOf(7_000_000))))
        // 边界 1：还有一个已声明但池为空的槽 → 不算固定
        assertNull(synthetic(listOf(900_001, 900_002, -1), mapOf(900_001 to listOf(7_000_000), 900_002 to emptyList())))
        // 边界 2：单成员池里的 effectId 查不到 → 不算固定
        assertNull(synthetic(listOf(900_001, -1, -1), mapOf(900_001 to listOf(999_999_901))))
        // 边界 3：槽池 ID 指向不存在的池 → 不算固定
        assertNull(synthetic(listOf(900_001, 900_009, -1), mapOf(900_001 to listOf(7_000_000))))
        // 多槽固定时按 (sortId, effectId) 升序
        assertEquals(
            listOf(6_641_000, 7_000_302, 7_000_402),
            synthetic(listOf(3, 2, 1), mapOf(1 to listOf(7_000_402), 2 to listOf(7_000_302), 3 to listOf(6_641_000))),
        )

        // 随包数据逐件对拍：固定与否与 core.js 规则一致
        index.relics.forEach { entry ->
            val declared = entry.info.slots.filter { it != -1 }
            val coreFixed = declared.isNotEmpty() && declared.all { pool ->
                val members = index.poolMembers[pool]
                members != null && members.size == 1 && index.affix(members[0]) != null
            }
            assertEquals(coreFixed, entry.fixedEffectIds != null, "遗物 ${entry.id} 的固定词条判定与 core.js 口径不一致")
            if (coreFixed) assertEquals(declared.size, entry.fixedEffectIds!!.count { it != -1 })
        }
    }

    @Test
    fun `extra affixes are told apart from catalog affixes (isCatalogAffix)`() {
        assertTrue(index.affix(NORMAL_EFFECT)!!.inCatalog)
        val watchAffix = assertNotNull(index.affix(10000), "extraAffixes 仍并进索引")
        assertFalse(watchAffix.inCatalog, "10000 是角色专属词条，只在 extraAffixes 里")
        assertEquals("物品表补充", watchAffix.category)
        assertNull(index.affix(-1))
        assertEquals("未知词条 #-1", index.affixName(-1))

        // 池成员里确实存在词条库查不到的 ID（角色专属词条）
        val outsiders = index.poolsByEffect.keys.filter { index.affix(it)?.inCatalog != true }
        assertTrue(outsiders.isNotEmpty())
        assertTrue(outsiders.none { affixById.containsKey(it) })

        // 老旧怀表：第 1 槽固定为词条 10000，另一槽是词条库词条
        val watch = index.relic(10000)!!
        assertEquals(10000, watch.slots[0].previewEffectIds[0])
        assertFalse(index.affix(watch.slots[0].previewEffectIds[0])!!.inCatalog)
        val fixed = watch.fixedEffectIds!!.filter { it != -1 }
        assertTrue(fixed.any { it == 10000 && !index.affix(it)!!.inCatalog })
        assertTrue(fixed.any { index.affix(it)!!.inCatalog }, "同一件遗物也有词条库里的词条")

        val shop = index.relic(RANDOM_RELIC_ID)!!
        assertTrue(shop.slots.all { slot -> slot.previewEffectIds.all { index.affix(it)!!.inCatalog } })
    }

    @Test
    fun `the biggest conflict group can be listed in full and expanded in place`() {
        val groups = catalog.affixes.filter { it.compatibilityId != -1 }.groupingBy { it.compatibilityId }.eachCount()
        val (biggestId, biggestSize) = groups.maxBy { it.value }
        assertTrue(biggestSize > AFFIX_LOOKUP_CONFLICT_LIMIT, "存在超过 24 条的互斥组，页面必须能展开全部")
        assertEquals(102, biggestSize, "最大互斥组 102 条")
        assertEquals(100, biggestId)

        val sample = catalog.affixes.first { it.compatibilityId == biggestId }
        val peers = index.conflicts(sample.effectId)
        assertEquals(biggestSize - 1, peers.size, "conflicts 不截断，截断只发生在渲染层")
        assertTrue(peers.all { it.compatibilityId == biggestId })
        assertTrue(peers.size > AFFIX_LOOKUP_CONFLICT_LIMIT)
        assertEquals(AFFIX_LOOKUP_CONFLICT_LIMIT, affixLookupShown(peers, expanded = false, limit = AFFIX_LOOKUP_CONFLICT_LIMIT).size)
        assertEquals(peers.size, affixLookupShown(peers, expanded = true, limit = AFFIX_LOOKUP_CONFLICT_LIMIT).size)

        // searchableText 不含 compatibilityId：词条库页搜互斥池 ID 搜不出这一组，只能在本页展开
        assertFalse(sample.searchableText.contains(biggestId.toString()))
    }

    @Test
    fun `searchRelics defaults to obtainable relics only (same as macOS onlyObtainable)`() {
        val obtainable = index.searchRelics("")
        assertEquals(768, obtainable.size, "1397 件里滤掉超范围 / 无名参数行与 20000-30035 作弊器区段后应剩 768 件")
        assertEquals(obtainable.size, index.obtainableRelicCount)
        assertTrue(obtainable.all { it.isObtainable })
        // 可查遗物不允许有空成员的槽位池
        obtainable.forEach { entry ->
            assertTrue(entry.slots.any { !it.isEmpty && it.poolSize > 0 })
            entry.slots.filter { !it.isEmpty }.forEach { slot ->
                assertTrue(slot.poolSize > 0, "可查遗物 ${entry.id} 第 ${slot.slotIndex + 1} 槽指向空池 ${slot.poolId}")
            }
        }
        assertTrue(obtainable.none { it.id in CHEAT_RELIC_ID_RANGE })

        val all = index.searchRelics("", onlyObtainable = false)
        assertEquals(relicData.relics.size, all.size)
        assertTrue(all.any { it.id == 20_000 }, "关掉过滤后仍能取到作弊器区段的遗物")

        assertTrue(index.searchRelics(FIXED_RELIC_ID.toString()).any { it.id == FIXED_RELIC_ID })
        val byName = index.searchRelics("辽阔的火燃情景")
        assertTrue(byName.any { it.id == RANDOM_RELIC_ID })
        assertTrue(byName.none { it.id in CHEAT_RELIC_ID_RANGE }, "作弊器区段里也有同名遗物，不能混进结果")
        assertTrue(index.searchRelics("细腻的火燃情景").any { it.id == 1000 })

        val byKind = index.searchRelics("深夜遗物")
        assertTrue(byKind.size > 100)
        assertTrue(byKind.all { it.deep })

        val onlyDeep = index.searchRelics("", onlyDeep = true)
        assertEquals(216, onlyDeep.size)
        assertTrue(onlyDeep.all { it.deep && it.isObtainable })
    }

    @Test
    fun `shown slice is bounded like paginate`() {
        // Windows 翻页（paginate），手机与 macOS 一样默认列前 N 条 + 展开全部
        val rows = List(450) { it }
        assertEquals(200, affixLookupShown(rows, expanded = false, limit = 200).size)
        assertEquals(450, affixLookupShown(rows, expanded = true, limit = 200).size)
        assertEquals(50, affixLookupShown(rows.take(50), expanded = false, limit = 200).size)
        assertEquals(0, affixLookupShown(emptyList<Int>(), expanded = false, limit = 200).size)
        assertEquals(0, affixLookupShown(rows, expanded = false, limit = -5).size)
        assertEquals(AFFIX_LOOKUP_ROW_LIMIT, 120)
        assertEquals(AFFIX_LOOKUP_CONFLICT_LIMIT, 24)
    }

    @Test
    fun `unique relic id range matches the kind label for every non deep relic`() {
        index.relics.filter { !it.deep }.forEach { entry ->
            assertEquals(isUniqueRelicId(entry.id), entry.kindLabel == "唯一遗物", "遗物 ${entry.id} 的种类标签与唯一 ID 区间不一致")
            assertEquals(isUniqueRelicId(entry.id), entry.isUnique)
        }
    }

    @Test
    fun `conflict groups are symmetric and unreachable affixes list no peers`() {
        val unreachable = index.affixes.filter { it.compatibilityId != -1 && !it.appearsOnRelic }
        assertTrue(unreachable.size > 900, "数据里确实有大量不进池、却挂着 compatibilityId 的效果")
        assertEquals(1305, unreachable.size)
        unreachable.take(40).forEach { affix ->
            assertTrue(index.conflicts(affix.effectId).isEmpty(), "不可达词条 ${affix.effectId} 不该反查出互斥对象")
        }
        // 对称性：A 在 B 的组里 ⇔ B 在 A 的组里
        index.affixes.filter { it.compatibilityId != -1 && it.appearsOnRelic }.take(60).forEach { affix ->
            index.conflicts(affix.effectId).take(6).forEach { peer ->
                assertTrue(
                    index.conflicts(peer.effectId).any { it.effectId == affix.effectId },
                    "互斥组不对称：${affix.effectId} 的组里有 ${peer.effectId}，反过来没有",
                )
            }
        }
        // 全库对称（手机端索引一次建好，全量对拍也很快）
        val reachable = index.affixes.filter { it.compatibilityId != -1 && it.appearsOnRelic }
        reachable.forEach { affix ->
            index.conflicts(affix.effectId).forEach { peer ->
                assertTrue(peer.appearsOnRelic)
                assertEquals(affix.compatibilityId, peer.compatibilityId)
            }
        }
        val host = catalog.affixes.first { it.compatibilityId == 100 }
        assertEquals(102, index.conflicts(host.effectId).size + 1)

        // 没有遗物物品表时只剩词条库词条，它们本来就都能出现在遗物上
        assertTrue(bare.affixes.all { it.appearsOnRelic })
        assertTrue(bare.conflicts(host.effectId).isNotEmpty())
        assertEquals(
            "这条词条不会出现在任何遗物的槽位池里，不参与互斥判定：互斥只约束「能同时出现在一件遗物上」的词条。",
            LookupCopy.UNREACHABLE_CONFLICT_NOTE,
        )
    }

    @Test
    fun `conflict branch puts unreachable before compatibilityId -1`() {
        val unreachableNoGroup = index.affixes.filter { it.compatibilityId == -1 && !it.appearsOnRelic }
        assertTrue(unreachableNoGroup.size > 100, "应有上百条「不可达且没有互斥池」的效果，实际 ${unreachableNoGroup.size}")
        assertEquals(148, unreachableNoGroup.size)
        assertTrue(unreachableNoGroup.any { it.effectId == 11001 }, "effectId 11001 应在这一支里")
        unreachableNoGroup.take(40).forEach { affix ->
            assertEquals(AffixConflictBranch.UNREACHABLE, index.report(affix.effectId)!!.conflictBranch)
        }

        val loner = catalog.affixes.first { it.compatibilityId == -1 && index.affix(it.effectId)!!.appearsOnRelic }
        assertEquals(AffixConflictBranch.NO_GROUP, AffixConflictBranch.of(true, loner.compatibilityId, 0))
        assertEquals(AffixConflictBranch.NO_GROUP, index.report(loner.effectId)!!.conflictBranch)
        val host = catalog.affixes.first { it.compatibilityId == 100 }
        assertEquals(AffixConflictBranch.PEERS, index.report(host.effectId)!!.conflictBranch)
        assertEquals(AffixConflictBranch.LONE, AffixConflictBranch.of(true, host.compatibilityId, 0))
        // 真实数据里的 lone：诅咒 6820000 自成一池
        assertEquals(AffixConflictBranch.LONE, index.report(CURSE_EFFECT)!!.conflictBranch)

        assertEquals("该词条没有互斥组，可与任意其他词条同时出现（仍不能与自身重复）。", LookupCopy.NO_CONFLICT_GROUP_NOTE)
        assertEquals("互斥池 100 内只有这一条词条，没有互斥对象。", affixLookupLoneConflictNote(100))
    }

    @Test
    fun `hitCountText is word for word the same as macOS`() {
        assertEquals("共 7 件 · 已显示全部 7 件", affixLookupHitCountText(7, 7))
        assertEquals("共 0 件 · 已显示全部 0 件", affixLookupHitCountText(0, 0))
        assertEquals("共 300 件 · 已显示 200 件（另有 100 件未列出）", affixLookupHitCountText(300, 200))
        assertEquals("共 300 件 · 已显示 120 件（另有 180 件未列出）", affixLookupHitCountText(300, 120))
        assertEquals("共 300 件 · 已显示全部 300 件", affixLookupHitCountText(300, 900), "显示数不会超过总数")
        assertEquals("共 300 件 · 已显示 0 件（另有 300 件未列出）", affixLookupHitCountText(300, -5))

        // 真实数据：生命力＋１ 的随机池命中超过默认列出的件数
        val random = index.report(NORMAL_EFFECT)!!.randomRelics
        val total = random.size
        assertTrue(total > AFFIX_LOOKUP_ROW_LIMIT)
        val shown = affixLookupShown(random, expanded = false, limit = AFFIX_LOOKUP_ROW_LIMIT)
        assertEquals(
            "共 $total 件 · 已显示 $AFFIX_LOOKUP_ROW_LIMIT 件（另有 ${total - AFFIX_LOOKUP_ROW_LIMIT} 件未列出）",
            affixLookupHitCountText(total, shown.size),
        )
        val expanded = affixLookupShown(random, expanded = true, limit = AFFIX_LOOKUP_ROW_LIMIT)
        assertEquals("共 $total 件 · 已显示全部 $total 件", affixLookupHitCountText(total, expanded.size))
        assertEquals(
            "共 432 件 · 已显示 120 件（另有 312 件未列出）；上面的种类统计是全部命中的分布",
            LookupCopy.hitExpandHint(total, shown.size),
        )
    }

    @Test
    fun `deepNoteText has four branches in the same order as macOS`() {
        val curseCount = index.poolMembers.getValue(DEEP_CURSE_LOOKUP_POOL).size
        assertTrue(curseCount > 0)
        assertEquals(
            "负面词条：只出现在深夜遗物带诅咒的那一行，与同一行的 A 池正面词条配对；诅咒池（3000000）共 $curseCount 条。",
            index.report(CURSE_EFFECT)!!.deepNote,
        )
        assertEquals(
            "A 池词条：出货时这一行必定同时带一条深夜诅咒（诅咒池 3000000，共 $curseCount 条）。存档里这条词条没配诅咒即为改动。",
            index.report(DEEP_A_EFFECT)!!.deepNote,
        )
        assertEquals("B / C 池词条：深夜遗物可出，所在行不带诅咒。", index.report(DEEP_BC_EFFECT)!!.deepNote)
        assertEquals("这条词条不在任何深夜词条池里，深夜遗物不会出它。", index.report(NORMAL_EFFECT)!!.deepNote)
        assertEquals(
            "这条词条不在任何深夜词条池里，深夜遗物不会出它。",
            affixLookupDeepNote(false, false, false, DEEP_CURSE_LOOKUP_POOL, 0),
        )
    }

    @Test
    fun `deep pool details are rendered and match macOS`() {
        index.report(DEEP_A_EFFECT)!!.deepHits.forEach { assertTrue(it.detail.isNotEmpty(), "深夜池 ${it.poolId} 应有说明") }
        assertEquals("强力正面词条：同一行必定配一条深夜诅咒", affixPoolDetail(2_000_000))
        assertEquals("普通正面词条：同一行不带诅咒", affixPoolDetail(2_100_000))
        assertEquals("普通正面词条：同一行不带诅咒", affixPoolDetail(2_200_000))
        assertEquals("深夜遗物负面词条的唯一来源", affixPoolDetail(3_000_000))
        assertEquals("", affixPoolDetail(110), "孔数层池没有补充说明")
    }

    @Test
    fun `fallback pool labels are not printed twice`() {
        assertFalse(affixPoolLabelIsFallback(110))
        assertFalse(affixPoolLabelIsFallback(2_000_000))
        assertFalse(affixPoolLabelIsFallback(3_000_000))
        val fallbackPools = relicData.relics.flatMap { it.slots + it.curseSlots }
            .filter { it != -1 && affixPoolLabelIsFallback(it) }
            .toSet()
        assertTrue(fallbackPools.size > 100, "确实有大量没有中文短名的槽位池")
        fallbackPools.forEach { assertEquals("池 $it", affixPoolLabel(it), "兜底标签里已经带了 id") }
    }

    @Test
    fun `slot previews hold ten affixes on both ends`() {
        assertEquals(10, AFFIX_LOOKUP_SLOT_PREVIEW_LIMIT)
        index.relics.filter { it.isObtainable }.forEach { entry ->
            entry.slots.filter { !it.isEmpty }.forEach { slot ->
                assertEquals(minOf(10, slot.poolSize), slot.previewEffectIds.size, "遗物 ${entry.id} 的槽位预览")
            }
        }
    }

    @Test
    fun `catalog ids and catalog type stay the same object the page passes in`() {
        // 页面直接用启动时载入的词条库：索引不另读 JSON
        val rebuilt = AffixLookupIndex(catalog, relicData)
        assertEquals(index.affixes, rebuilt.affixes)
        assertEquals(catalog.sources, rebuilt.catalogSources)
        assertTrue(rebuilt.relicGameVersion.startsWith("v1.03.4"))
        val emptyCatalog = AffixCatalog(1, "", "", "", emptyList(), emptyList())
        val onlyExtras = AffixLookupIndex(emptyCatalog, relicData)
        assertEquals(1552, onlyExtras.affixes.size)
    }
}
