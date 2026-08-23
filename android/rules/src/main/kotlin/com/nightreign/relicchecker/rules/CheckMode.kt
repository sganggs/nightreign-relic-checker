package com.nightreign.relicchecker.rules

enum class CheckMode(
    val title: String,
    val shortTitle: String,
    val detail: String,
    val slotPoolSequences: List<List<Int>>,
) {
    CURRENT_NORMAL(
        title = "普通 1.03",
        shortTitle = "1.03",
        detail = "严格检查 1.03 / DLC 后普通大遗物的非零权重词条池。",
        slotPoolSequences = listOf(listOf(110, 210, 310)),
    ),
    LEGACY_NORMAL(
        title = "普通旧池",
        shortTitle = "旧池",
        detail = "严格检查 1.02 及更早的普通大遗物词条池。",
        slotPoolSequences = listOf(listOf(100, 200, 300)),
    ),
    DEEP_POSITIVE(
        title = "深夜正面",
        shortTitle = "深夜",
        detail = "按真实七种三槽模板预检深夜正面词条、互斥与顺序；不替代具体遗物 ID 与负面词条配对校验。",
        slotPoolSequences = listOf(
            listOf(2_000_000, 2_000_000, 2_000_000),
            listOf(2_000_000, 2_000_000, 2_100_000),
            listOf(2_000_000, 2_100_000, 2_100_000),
            listOf(2_100_000, 2_100_000, 2_100_000),
            listOf(2_000_000, 2_000_000, 2_200_000),
            listOf(2_000_000, 2_200_000, 2_200_000),
            listOf(2_200_000, 2_200_000, 2_200_000),
        ),
    ),
    COMPATIBILITY_ONLY(
        title = "顺序/互斥",
        shortTitle = "通用",
        detail = "只检查词条是否重复、互斥，以及保存顺序；适合固定遗物或来源不明的组合。",
        slotPoolSequences = emptyList(),
    );

    val eligiblePoolIds: Set<Int> = slotPoolSequences.flatten().toSortedSet()
}
