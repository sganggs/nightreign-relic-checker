package com.nightreign.relicchecker.gamedata.bosses

// 出场场合（bossesSchemaVersion 4 的 roles）与页面分组。
// 规则正文是 macOS 端 RelicCore 的 BossRoleCatalog / BossCard.Group（两端唯一正式版本），这里照抄。

/** 出场场合的全局口径：排列顺序、默认隐藏的场合、每个场合落在哪个分组。 */
object BossRoleCatalog {
    /** roleNames 的键序，也是 roles 数组的规范顺序。 */
    val order: List<String> = listOf(
        "night", "prelude", "field", "stronghold", "mine", "evergaol", "tower",
        "raid", "invader", "event", "nightlord", "summon", "other", "unplaced",
    )

    /** 默认隐藏的场合（沿用「显示隐藏实体」开关）。 */
    val hiddenRoles: Set<String> = setOf("summon", "unplaced")

    /** 合并进「其它场合」分组的已知场合（按规范顺序）。 */
    val otherGroupRoles: List<String> = listOf("prelude", "mine", "tower", "raid", "invader", "event", "other")

    /** 在规范顺序里的位置；未知场合排在最后。 */
    fun rank(role: String): Int = order.indexOf(role).let { if (it < 0) order.size else it }

    /** 去重 + 按规范顺序排（未知场合按键名排在已知场合之后），去掉空串。 */
    fun normalized(roles: List<String>): List<String> =
        roles.filter { it.isNotEmpty() }.toSet()
            .sortedWith(compareBy<String> { rank(it) }.thenBy { it })

    /** 只出现在默认隐藏场合（「未放置」「随从/召唤物」）的场合表；空表不算（缺数据不能被当成「未放置」藏起来）。 */
    fun onlyHidden(roles: List<String>): Boolean {
        val list = normalized(roles)
        return list.isNotEmpty() && list.all { it in hiddenRoles }
    }

    /** 组级 roles：数据集给了就用（再规范化一次），没给就取各行 roles 的并集。 */
    fun groupRoles(declared: List<String>, rows: List<BossFight>): List<String> {
        val normalizedDeclared = normalized(declared)
        if (normalizedDeclared.isNotEmpty()) return normalizedDeclared
        return normalized(rows.flatMap { it.roles })
    }
}

/**
 * 页面的分组筛选（按出场场合 roles，不按 tier）：
 *   * 夜王：夜王卡片固定只进这一组；
 *   * 守夜首领 / 据点首领 / 场景头目 / 封印监牢：各对应一个场合；
 *   * 其它场合：守夜前哨 / 坑道精英 / 大空洞高塔首领 / 突袭事件 / 黑夜入侵者 / 地图事件 / 其他地图，
 *     以及未知场合；没有 roles 的组（旧版数据集）也放这里；
 *   * 随从/召唤物、未放置：默认隐藏，打开「显示隐藏实体」才出现在筛选里。
 * 守夜 / 野外首领卡片的 roles 与哪个分组有交集就出现在哪个分组，可以同时出现在多个。
 */
enum class BossGroup(val key: String, val title: String, val role: String?) {
    NIGHTLORD("nightlord", BossRoleText.groupNightlord, "nightlord"),
    NIGHT("night", BossRoleText.groupNight, "night"),
    STRONGHOLD("stronghold", BossRoleText.groupStronghold, "stronghold"),
    FIELD("field", BossRoleText.groupField, "field"),
    EVERGAOL("evergaol", BossRoleText.groupEvergaol, "evergaol"),
    OTHER("other", BossRoleText.groupOther, null),
    SUMMON("summon", BossRoleText.groupSummon, "summon"),
    UNPLACED("unplaced", BossRoleText.groupUnplaced, "unplaced"),
    ;

    /** 「随从/召唤物」「未放置」默认隐藏。 */
    val isHiddenByDefault: Boolean get() = this == SUMMON || this == UNPLACED

    /** 某个场合落在这个分组里吗。 */
    fun contains(role: String): Boolean {
        val own = this.role
        if (own != null) return own == role
        return forRole(role) == OTHER
    }

    /** 一组场合里落在这个分组的那几个（规范顺序）。 */
    fun rolesIn(roles: List<String>): List<String> = BossRoleCatalog.normalized(roles).filter(::contains)

    companion object {
        /** 场合 → 分组。有独立分组的场合各归各组，其余一律「其它场合」。 */
        fun forRole(role: String): BossGroup =
            entries.firstOrNull { it != OTHER && it.role == role } ?: OTHER

        /** 筛选器里可选的分组：默认隐藏的两个只在打开开关时出现。 */
        fun visibleCases(includeHidden: Boolean): List<BossGroup> =
            entries.filter { includeHidden || !it.isHiddenByDefault }

        /** 「其它场合」分组里合并的场合（已知部分），按规范顺序。 */
        val otherRoles: List<String> get() = BossRoleCatalog.otherGroupRoles
    }
}

/** 一条场合出处：哪一个原始行、在哪张地图 MSB、由哪张参数表的哪一行判定。 */
data class BossRoleEvidence(
    /** 原始 NpcParam 行（合并行时可能不是代表行）。 */
    val npcId: Int?,
    /** 地图 MSB 名（入侵者 / 未放置为 null）。 */
    val msb: String?,
    val part: String = "",
    val table: String,
    val row: String,
    val note: String,
) {
    /**
     * 出处摘要「表名 行 · 地图」（两端同一口径）：
     *   * row 为空或「—」（未放置那种占位）时只写表名；
     *   * msb 为空、或与 row 相同（「其他地图」那种 row 就是地图名）时不重复写地图。
     */
    val summary: String
        get() {
            var head = table
            if (row.isNotEmpty() && row != "—") {
                head = if (head.isEmpty()) row else "$head $row"
            }
            val parts = mutableListOf<String>()
            if (head.isNotEmpty()) parts += head
            if (!msb.isNullOrEmpty() && msb != row) parts += msb
            return if (parts.isEmpty()) BossRoleText.evidenceMissing else parts.joinToString(" · ")
        }
}
