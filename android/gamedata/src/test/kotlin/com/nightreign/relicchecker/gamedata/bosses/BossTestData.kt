package com.nightreign.relicchecker.gamedata.bosses

import com.nightreign.relicchecker.gamedata.GameDataJson
import com.nightreign.relicchecker.gamedata.GameDataKey
import kotlin.test.assertNotNull
import kotlin.test.assertTrue

/** 首领数据测试共用：真实数据集（仓库根 data/）只读一次、解析一次。 */
internal object BossTestData {
    val text: String by lazy {
        val stream = assertNotNull(
            javaClass.classLoader.getResourceAsStream(GameDataKey.BOSSES.fileName),
            "data/ 下缺少 ${GameDataKey.BOSSES.fileName}",
        )
        stream.bufferedReader(Charsets.UTF_8).use { it.readText() }
    }

    val index: BossDataIndex by lazy { BossesParser.parse(text) }

    val dataset: BossDataset get() = index.dataset

    /** 原始 DTO（校验「组级 roles = 各行并集」这类数据侧前提时用，解码后的模型已经规范化过）。 */
    val dto: BossesFileDto by lazy { GameDataJson.decode<BossesFileDto>(GameDataKey.BOSSES, text) }

    val allRows: List<BossFight> get() = dataset.allRows

    fun card(id: String): BossCard = assertNotNull(index.cards.firstOrNull { it.id == id }, "找不到卡片 $id")

    fun boss(id: String): BossCard = card("boss-$id")

    fun lord(menuId: Int): BossCard = card("nightlord-$menuId")

    fun row(npcId: Int): BossFight = assertNotNull(allRows.firstOrNull { it.npcId == npcId }, "找不到数值行 $npcId")

    /** 一条只含 nightBosses 的构造数据集（组级 roles 缺失时取各行并集等宽容规则用）。 */
    fun indexOf(json: String): BossDataIndex = BossesParser.parseUnchecked(json)
}

internal fun assertClose(expected: Double, actual: Double?, message: String, tolerance: Double = 1e-6) {
    assertNotNull(actual, "$message：实际为 null")
    assertTrue(kotlin.math.abs(expected - actual) <= tolerance, "$message：期望 $expected，实际 $actual")
}
