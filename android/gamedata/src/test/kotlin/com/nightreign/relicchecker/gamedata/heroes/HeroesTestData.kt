package com.nightreign.relicchecker.gamedata.heroes

import com.nightreign.relicchecker.gamedata.GameDataKey
import kotlin.test.assertEquals
import kotlin.test.assertNotNull

/** 测试共用：真实数据集只读一次、解析一次（test resources 指向仓库根 data/）。 */
internal object HeroesTestData {
    val text: String by lazy {
        val stream = assertNotNull(
            HeroesTestData::class.java.classLoader.getResourceAsStream(GameDataKey.HEROES.fileName),
            "data/ 下缺少 ${GameDataKey.HEROES.fileName}",
        )
        stream.bufferedReader(Charsets.UTF_8).use { it.readText() }
    }

    val index: HeroStatsIndex by lazy { HeroesParser.parse(text) }

    val attributeKeys: List<String> get() = index.statNames.attributeKeys
    val derivedKeys: List<String> get() = index.statNames.derivedKeys
    val levels: List<Int> = (1..15).toList()
}

internal fun assertClose(expected: Double, actual: Double?, message: String, tolerance: Double = 0.0001) {
    assertNotNull(actual, "$message（缺值）")
    assertEquals(expected, actual, tolerance, message)
}

internal fun HeroStatsIndex.snap(
    heroKey: String,
    level: Int,
    modifierIds: Collection<Int> = emptyList(),
    libraKey: String? = null,
): HeroStatsSnapshot = assertNotNull(
    snapshot(heroKey, level, modifierIds.toSet(), libraKey),
    "应能算出 $heroKey $level 级快照（词条 $modifierIds，利普拉 $libraKey）",
)

internal fun HeroStatsIndex.modifier(affixId: Int): HeroStatModifier =
    assertNotNull(dataset.statModifiers.firstOrNull { it.affixId == affixId }, "找不到词条 $affixId")
