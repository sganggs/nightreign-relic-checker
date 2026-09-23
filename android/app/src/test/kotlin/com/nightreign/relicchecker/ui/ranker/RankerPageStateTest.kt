package com.nightreign.relicchecker.ui.ranker

import androidx.compose.runtime.saveable.SaverScope
import com.nightreign.relicchecker.catalog.CatalogLoader
import com.nightreign.relicchecker.gamedata.GameDataKey
import com.nightreign.relicchecker.gamedata.ranker.EntryState
import com.nightreign.relicchecker.gamedata.ranker.LoadoutConfig
import com.nightreign.relicchecker.gamedata.ranker.LoadoutIndex
import com.nightreign.relicchecker.gamedata.ranker.MeansSelection
import com.nightreign.relicchecker.gamedata.ranker.OutputClass
import com.nightreign.relicchecker.gamedata.ranker.RankerParsers
import com.nightreign.relicchecker.gamedata.ranker.RankerText
import com.nightreign.relicchecker.gamedata.ranker.RelicCardType
import com.nightreign.relicchecker.gamedata.ranker.RunMode
import com.nightreign.relicchecker.gamedata.ranker.SkillDataIndex
import java.io.File
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

// 「增伤排名」页的状态类与列表构建（纯 JVM，读仓库根 data/ 的真实数据）：
//   · 各种开合 / 搜索 / 配置下，LazyColumn 的 key 一律唯一（重复 key 会让页面直接崩溃）；
//   · 汇总清单与评估结果一致，推荐填满、切模式、换输出手段的提示与桌面端同一口径；
//   · rememberSaveable 的存取往返不丢状态；
//   · 页面用到的 RankerText 键都在文案表里（缺键时 RankerText.t 会原样显示键名）。
class RankerPageStateTest {
    private object Data {
        private fun read(name: String): String {
            val file = listOf(File("../../data/$name"), File("../data/$name"), File("data/$name")).firstOrNull { it.isFile }
            return requireNotNull(file) { "找不到数据文件 $name" }.readText(Charsets.UTF_8)
        }

        val skills: SkillDataIndex by lazy { RankerParsers.skills(read(GameDataKey.SKILLS.fileName)) }
        val index: LoadoutIndex by lazy {
            val catalog = CatalogLoader.parse(read(CatalogLoader.ASSET_FILE_NAME))
            LoadoutIndex(RankerParsers.buffs(read(GameDataKey.BUFFS.fileName)), catalog.affixes)
        }
    }

    private fun newState(): RankerPageState = RankerPageState.create(Data.skills, Data.index)

    private fun rowsOf(state: RankerPageState): RankerRows =
        computeRankerRows(state.evaluator, state.config, state.waFilterType, state.showInactive)

    private fun items(
        state: RankerPageState,
        closed: Set<String> = emptySet(),
        open: Set<String> = emptySet(),
        waQuery: String = "",
        otherQuery: String = "",
        loading: Boolean = false,
    ): List<RankerItem> = buildItems(
        state, if (loading) null else rowsOf(state), RankerToggles(closed), RankerToggles(open), waQuery, otherQuery,
    )

    private fun assertUniqueKeys(label: String, list: List<RankerItem>) {
        val duplicates = list.groupBy { it.key }.filterValues { it.size > 1 }.keys
        assertTrue("$label：重复的 key $duplicates", duplicates.isEmpty())
    }

    private val everythingOpen: Set<String> by lazy {
        buildSet {
            LoadoutIndex.OTHER_SLOTS.forEach { add(RankerKeys.otherSlot(it)) }
            add(RankerKeys.SUM_UNCOUNTED)
            add(RankerKeys.HITS_DETAIL)
            listOf("brief", "questions", "caveats", "stacking", "version").forEach { add(RankerKeys.note(it)) }
            add(RankerKeys.note("buffs-notes"))
        }
    }

    private fun fill(state: RankerPageState) = runBlocking { state.fill(this) }

    @Test
    fun keysAreUniqueInEveryLayout() {
        val state = newState()
        assertUniqueKeys("默认", items(state))
        assertUniqueKeys("加载中", items(state, loading = true))
        assertUniqueKeys("全部展开", items(state, open = everythingOpen))
        state.updateShowInactive(true)
        assertUniqueKeys("显示不生效项", items(state, open = everythingOpen))
        state.updateShowInactive(false)
        assertUniqueKeys("搜索其它增益", items(state, open = everythingOpen, otherQuery = "攻击"))
        assertUniqueKeys("搜索武器词条", items(state, waQuery = "战技"))

        fill(state)
        assertUniqueKeys("常规推荐填满", items(state, open = everythingOpen))
        state.setRunMode(RunMode.DEEP)
        state.updateWaFilterAll(true)
        fill(state)
        assertUniqueKeys("深夜推荐填满", items(state, open = everythingOpen))
        state.updateShowInactive(true)
        assertUniqueKeys("深夜 + 显示不生效项", items(state, open = everythingOpen))

        val comet = requireNotNull(Data.skills.output("sorcery-4021"))
        state.selectOutput(comet)
        assertUniqueKeys("法术", items(state, open = everythingOpen))

        val collapsed = setOf(RankerKeys.OUTPUT, RankerKeys.MODE, RankerKeys.WEAPON, RankerKeys.RELIC, RankerKeys.TALISMAN,
            RankerKeys.OTHER, RankerKeys.SUMMARY, RankerKeys.NOTES)
        val folded = items(state, closed = collapsed)
        assertUniqueKeys("全部折叠", folded)
        assertEquals(
            listOf("output", "mode", "wa-header", "relic-header", "acc-header", "other-header", "summary", "notes"),
            folded.map { it.key },
        )
    }

    @Test
    fun sectionsFollowSlotCaps() {
        val state = newState()
        fun count(type: String) = items(state).count { it.type == type }
        assertEquals(3, count("relic-card"))
        assertEquals(2, count("acc-slot"))
        assertTrue(items(state).any { it === RankerItem.SummaryHeader })
        state.setRunMode(RunMode.DEEP)
        assertEquals(6, count("relic-card"))
        assertEquals(12, state.caps.weaponAffix)
        assertEquals(6, state.caps.deepOnly)
    }

    @Test
    fun otherSearchSpansAllSlotsAndReportsNoMatch() {
        val state = newState()
        val searched = items(state, otherQuery = "攻击")
        val slots = searched.filterIsInstance<RankerItem.OtherSlot>()
        assertTrue("搜索跨分栏：至少两栏有匹配", slots.size >= 2)
        assertTrue(slots.all { it.searching })
        assertTrue(searched.filterIsInstance<RankerItem.OtherRow>().isNotEmpty())

        val none = items(state, otherQuery = "zzzz不存在的增益")
        assertTrue(none.filterIsInstance<RankerItem.OtherSlot>().isEmpty())
        val plain = none.filterIsInstance<RankerItem.Plain>().firstOrNull { it.key == "other-nomatch" }
        assertEquals(RankerText.t("overviewNoMatch"), plain?.text)

        // 不搜索时各分栏默认折叠：只有分栏标题，没有行
        val folded = items(state)
        assertEquals(LoadoutIndex.OTHER_SLOTS.size, folded.count { it is RankerItem.OtherSlot })
        assertTrue(folded.none { it is RankerItem.OtherRow })
    }

    @Test
    fun summaryListMatchesEvaluation() {
        val state = newState()
        fill(state)
        val result = state.evaluation
        assertTrue(result.counted.isNotEmpty())
        val list = items(state)
        val countedRows = list.filterIsInstance<RankerItem.SummaryRow>().filter { it.item.state == EntryState.COUNTED }
        assertEquals(result.counted.size, countedRows.size)
        val label = list.filterIsInstance<RankerItem.SummaryLabel>().first()
        assertEquals(RankerText.f("summaryCounted", result.counted.size), label.text)
        // 汇总默认只展开「生效条目」；「选了但未计入」默认折叠
        assertTrue(list.filterIsInstance<RankerItem.SummaryRow>().all { it.item.state == EntryState.COUNTED })
    }

    @Test
    fun fillModeAndOutputNoticesFollowDesktop() {
        val state = newState()
        val expected = state.evaluator.recommendFill(LoadoutConfig(), state.output.attackWepType)
        fill(state)
        assertEquals(expected.config, state.config)
        assertEquals(RankerText.f("fillDone", expected.added.size), state.notice)
        assertFalse(state.filling)

        // 再填一次：没有空槽可填
        fill(state)
        assertEquals(RankerText.t("fillNothing"), state.notice)

        // 任何配置改动都清掉提示
        state.stepWeaponAffix(state.config.weaponAffixes.keys.first(), -1)
        assertNull(state.notice)

        // 深夜填满后切回常规：去掉超出常规上限的武器词条并提示条数
        state.clear()
        state.setRunMode(RunMode.DEEP)
        fill(state)
        val before = state.config
        state.setRunMode(RunMode.NORMAL)
        val trimmed = state.index.trimmedCount(before, state.config)
        assertTrue(trimmed > 0)
        assertEquals(RankerText.f("modeTrimmed", trimmed), state.notice)
        assertTrue(state.config.relics.drop(3).all { it.type == RelicCardType.EMPTY })

        // 换输出手段清掉「已按推荐填入」提示，配置保留
        fill(state)
        assertNotNull(state.notice)
        val config = state.config
        state.selectOutput(requireNotNull(Data.skills.output("incantation-5040")))
        assertNull(state.notice)
        assertEquals(config, state.config)
        assertEquals(OutputClass.INCANTATION, state.output.outputClass)
        assertEquals(61, state.output.attackWepType)
    }

    @Test
    fun outputChangesRebuildEvaluatorOnlyWhenOutputChanges() {
        val state = newState()
        val evaluator = state.evaluator
        state.update(state.config.copy(ticks = setOf(1)))
        assertTrue("改配置不重建计算器", evaluator === state.evaluator)
        state.setHand(2)
        assertTrue("换手重建计算器", evaluator !== state.evaluator)
        assertEquals(2, state.output.hand)
        val handTwo = state.evaluator
        state.setHand(2)
        assertTrue("同值不重建", handTwo === state.evaluator)

        // 不属于当前输出类别的攻击情境不交给计算器
        state.toggleContext("definitely-not-a-context")
        assertFalse("definitely-not-a-context" in state.output.attackContexts)
        assertTrue("definitely-not-a-context" in state.means.attackContexts)
    }

    @Test
    fun saverRoundTrip() {
        val state = newState()
        fill(state)
        state.setHand(2)
        state.updateShowInactive(true)
        state.updateWaFilterAll(true)
        val saver = RankerPageState.saver(Data.skills, Data.index)
        val scope = object : SaverScope {
            override fun canBeSaved(value: Any): Boolean = true
        }
        val saved = requireNotNull(with(saver) { scope.save(state) })
        val restored = requireNotNull(saver.restore(saved))
        assertEquals(state.means, restored.means)
        assertEquals(state.config, restored.config)
        assertEquals(state.notice, restored.notice)
        assertTrue(restored.showInactive)
        assertTrue(restored.waFilterAll)
        assertEquals(state.evaluation.totalMultiplier, restored.evaluation.totalMultiplier)

        // 读不回来时退回默认
        val broken = requireNotNull(saver.restore(listOf("{bad", "{bad", false, false, "")))
        assertEquals(MeansSelection.initial(Data.skills), broken.means)
        assertEquals(LoadoutConfig(), broken.config)
    }

    @Test
    fun sheetTargetsRoundTrip() {
        val sheets = listOf(
            RankerSheet.Output, RankerSheet.Weapon, RankerSheet.Fixed(2), RankerSheet.Affix(4, 1),
            RankerSheet.Curse(5, 2), RankerSheet.Talisman(1),
        )
        sheets.forEach { assertEquals(it, RankerSheet.decode(it.encode())) }
        assertNull(RankerSheet.decode(null))
        assertNull(RankerSheet.decode("affix:1"))
        assertNull(RankerSheet.decode("nope"))
    }

    @Test
    fun rankerTextKeysUsedByPageExist() {
        val dir = listOf(
            File("src/main/kotlin/com/nightreign/relicchecker/ui/ranker"),
            File("app/src/main/kotlin/com/nightreign/relicchecker/ui/ranker"),
        ).first { it.isDirectory }
        // RankerText.t("key") / RankerText.f("key", …)，以及 RankerText.t(if (…) "a" else "b") 两种写法
        val direct = Regex("RankerText\\.[tf]\\(\\s*\"([^\"]+)\"")
        val conditional = Regex("RankerText\\.[tf]\\(\\s*if \\([^)]*\\)\\s*\"([^\"]+)\"\\s*else\\s*\"([^\"]+)\"")
        val missing = sortedSetOf<String>()
        var checked = 0
        dir.listFiles { file -> file.extension == "kt" }!!.forEach { file ->
            val text = file.readText()
            val keys = direct.findAll(text).map { it.groupValues[1] } +
                conditional.findAll(text).flatMap { sequenceOf(it.groupValues[1], it.groupValues[2]) }
            keys.forEach { key ->
                checked += 1
                if (key !in RankerText.table) missing += key
            }
        }
        assertTrue("检查到的文案键太少（$checked）", checked > 80)
        assertTrue("页面用到了文案表里没有的键：$missing", missing.isEmpty())
    }
}
