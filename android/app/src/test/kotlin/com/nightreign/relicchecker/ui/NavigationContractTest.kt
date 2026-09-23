package com.nightreign.relicchecker.ui

import com.nightreign.relicchecker.ui.gamedata.GameDataState
import com.nightreign.relicchecker.ui.gamedata.map
import com.nightreign.relicchecker.ui.gamedata.zip
import org.junit.Assert.assertEquals
import org.junit.Assert.assertSame
import org.junit.Test

class NavigationContractTest {
    @Test
    fun bottomBarOrderPutsLookupRightAfterChecker() {
        assertEquals(
            listOf("检查", "反查", "词条库", "数据", "设置"),
            AppDestination.entries.map(AppDestination::label),
        )
        assertEquals(
            listOf("CHECKER", "LOOKUP", "CATALOG", "DATA", "SETTINGS"),
            AppDestination.entries.map(AppDestination::name),
        )
    }

    @Test
    fun dataHubListsFourPagesWithSaveInItsOwnSection() {
        assertEquals(
            listOf("首领数据", "角色属性", "增伤排名", "存档检查"),
            DataPage.entries.map(DataPage::title),
        )
        assertEquals(listOf(DataPage.SAVE), DataPage.entries.filter { it.section == DataSection.SAVE })
    }

    @Test
    fun gameDataStateCombinatorsPropagateLoadingAndFailure() {
        val ready: GameDataState<Int> = GameDataState.Ready(2)
        val failure = GameDataState.Failed(IllegalStateException("x"))
        val loading: GameDataState<Int> = GameDataState.Loading

        assertEquals(GameDataState.Ready(4), ready.map { it * 2 })
        assertSame(GameDataState.Loading, loading.map { it * 2 })
        assertEquals(GameDataState.Ready(2 to "a"), ready.zip(GameDataState.Ready("a")))
        assertEquals(failure, ready.zip(failure))
        assertEquals(failure, loading.zip(failure))
        assertSame(GameDataState.Loading, ready.zip(loading))
    }
}
