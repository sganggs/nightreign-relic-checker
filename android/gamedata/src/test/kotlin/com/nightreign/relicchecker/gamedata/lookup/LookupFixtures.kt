package com.nightreign.relicchecker.gamedata.lookup

import com.nightreign.relicchecker.catalog.AffixCatalog
import com.nightreign.relicchecker.catalog.CatalogLoader
import com.nightreign.relicchecker.gamedata.GameDataKey

/**
 * 真实数据（仓库根 data/，经 test resources 读入）+ 反向索引；各测试类共用，只载入并构建一次。
 * 与 macOS AffixLookupChecks 的 LookupFixtures 同一思路：不造假数据。
 */
internal object LookupFixtures {
    private fun readText(fileName: String): String {
        val stream = requireNotNull(javaClass.classLoader.getResourceAsStream(fileName)) { "data/ 下缺少 $fileName" }
        return stream.bufferedReader(Charsets.UTF_8).use { it.readText() }
    }

    val relicsJson: String by lazy { readText(GameDataKey.RELICS.fileName) }
    val catalog: AffixCatalog by lazy { CatalogLoader.parse(readText(CatalogLoader.ASSET_FILE_NAME)) }
    val relicData: RelicCatalog by lazy { RelicCatalogParser.parse(relicsJson) }
    val index: AffixLookupIndex by lazy { AffixLookupIndex(catalog, relicData) }

    /** 没有遗物物品表时的降级索引。 */
    val bare: AffixLookupIndex by lazy { AffixLookupIndex(catalog, null) }

    val affixById by lazy { catalog.affixes.associateBy { it.effectId } }

    // 用作样本的真实数据（与 Windows tests/lookup_index.test.mjs 同一批）
    const val NORMAL_EFFECT = 7_000_000 // 生命力＋１：100/110/200/210/300/310 六池
    const val DEEP_A_EFFECT = 6_001_400 // 提升物理攻击力＋３：深夜 A 池，requiresCurse
    const val DEEP_BC_EFFECT = 6_003_000 // 提升对中毒的抵抗力＋１：深夜 B/C 池
    const val CURSE_EFFECT = 6_820_000 // 受到损伤时，会累积中毒量表：诅咒池
    const val FIXED_RELIC_ID = 1660 // 辽阔的火燃情景（唯一遗物，三槽均为单成员池）
    const val RANDOM_RELIC_ID = 202 // 辽阔的火燃情景（商店遗物，三槽 310/210/110）
}
