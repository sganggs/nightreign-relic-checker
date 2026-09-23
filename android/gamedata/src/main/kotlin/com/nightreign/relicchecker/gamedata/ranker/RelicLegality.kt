package com.nightreign.relicchecker.gamedata.ranker

import com.nightreign.relicchecker.rules.Affix
import com.nightreign.relicchecker.rules.CheckIssue
import com.nightreign.relicchecker.rules.CheckMode
import com.nightreign.relicchecker.rules.CheckStatus
import com.nightreign.relicchecker.rules.IssueKind
import com.nightreign.relicchecker.rules.LegalityChecker

// 自组遗物的合法性（Windows 端 ranker.js checkCustomRelic / curseIssues / pickCurse / autoAssignCurses，
// macOS 端 BuffLoadoutIndex.relicCheck / curseIssues、LoadoutEvaluator.pickCurse / autoAssignCurses，同一口径、同一文案）：
//   · 正面词条一律走 :rules 的 LegalityChecker：普通遗物格按「普通 1.03」（CheckMode.CURRENT_NORMAL），
//     深夜遗物格按「深夜正面」（CheckMode.DEEP_POSITIVE）；不足三条时用「可落任一槽池、不参与互斥、排在最后」的
//     占位词条补足再检查；判出的问题按类型改用本页文案，只列真实词条。
//   · 深夜遗物另按存档检查的深夜遗物审计查诅咒配对：逐行「需诅咒 ⇔ 带诅咒」、诅咒须在诅咒池；另查涉及诅咒的
//     重复与互斥。普通遗物格带诅咒一律是多余的负面词条。
//   · 不合法的整件不计入（配置引擎把它的条目标成 relicInvalid）。
// 注：存档检查车道也要做深夜诅咒逐行配对，并行车道之间不能互相依赖，这里按 PAGES.md 的约定在本包里单独实现，
// 收尾时再合并。

/** 自组遗物检查的结果状态（文案 relicStatus.*）。 */
enum class RelicCheckStatus(val key: String) {
    EMPTY("empty"),
    FIXED("fixed"),
    PARTIAL("partial"),
    VALID("valid"),
    INVALID("invalid"),
    ;

    val titleZh: String get() = RankerText.t("relicStatus.$key")
}

/** 一条问题或提示（kind 与 Windows 端 issue.kind 同名：duplicate / conflict / unavailable / curseMissing …）。 */
data class RelicIssue(val kind: String, val title: String, val detail: String, val effectIds: List<Int>)

/** 一行（row 从 0 数起）：正面词条与这一行配的诅咒（没有词条也没有诅咒的行不列）。 */
data class RelicRowAffixes(val row: Int, val affix: Affix?, val curse: Affix?)

data class RelicCheck(
    val status: RelicCheckStatus,
    val message: String,
    val issues: List<RelicIssue> = emptyList(),
    val warnings: List<RelicIssue> = emptyList(),
    val rows: List<RelicRowAffixes> = emptyList(),
) {
    val isInvalid: Boolean get() = status == RelicCheckStatus.INVALID

    /** 正面词条条数。 */
    val affixCount: Int get() = rows.count { it.affix != null }

    companion object {
        val EMPTY: RelicCheck = RelicCheck(RelicCheckStatus.EMPTY, RankerText.t("relicEmpty"))
        val FIXED: RelicCheck = RelicCheck(RelicCheckStatus.FIXED, RankerText.t("relicFixedValid"))
    }
}

internal object RelicLegality {
    private val checker = LegalityChecker()
    private val KIND_ORDER = listOf("duplicate", "conflict", "unavailable")
    private const val CACHE_LIMIT = 5000

    fun check(index: LoadoutIndex, card: RelicCard, kind: RelicKind): RelicCheck {
        val catalog = index.catalog
        if (!catalog.available) {
            val text = RankerText.t("relicNoCatalog")
            return RelicCheck(RelicCheckStatus.INVALID, text, issues = listOf(RelicIssue("noCatalog", text, "", emptyList())))
        }
        val cacheKey = kind.key + "|" + (0 until RelicCard.ROWS).joinToString(",") { card.affixAt(it)?.toString().orEmpty() } +
            "|" + (0 until RelicCard.ROWS).joinToString(",") { card.curseAt(it)?.toString().orEmpty() }
        index.relicCheckCache[cacheKey]?.let { return it }
        val result = compute(catalog, card, kind)
        if (index.relicCheckCache.size > CACHE_LIMIT) index.relicCheckCache.clear()
        index.relicCheckCache[cacheKey] = result
        return result
    }

    private fun compute(catalog: RelicCatalogIndex, card: RelicCard, kind: RelicKind): RelicCheck {
        val rows = ArrayList<RelicRowAffixes>()
        val unknown = ArrayList<Int>()
        for (position in 0 until RelicCard.ROWS) {
            val id = card.affixAt(position)
            val curseId = card.curseAt(position)
            var affix: Affix? = null
            var curse: Affix? = null
            if (id != null) {
                affix = catalog.byId[id]
                if (affix == null && id !in unknown) unknown += id
            }
            if (curseId != null) {
                curse = catalog.byId[curseId]
                if (curse == null && curseId !in unknown) unknown += curseId
            }
            if (affix != null || curse != null) rows += RelicRowAffixes(position, affix, curse)
        }
        if (unknown.isNotEmpty()) {
            return RelicCheck(
                RelicCheckStatus.INVALID, RankerText.t("relicInvalid"),
                issues = listOf(
                    RelicIssue(
                        "unknownEffect", RankerText.t("relicUnknownEffectTitle"),
                        RankerText.f("relicUnknownEffectDetail", unknown.joinToString("、")), unknown.toList(),
                    ),
                ),
                rows = rows,
            )
        }
        if (rows.isEmpty()) return RelicCheck.EMPTY
        val mode = kind.checkMode
        val affixes = rows.mapNotNull { it.affix }
        val issues = ArrayList<RelicIssue>()
        if (affixes.isNotEmpty()) {
            val padded = ArrayList(affixes)
            while (padded.size < RelicCard.ROWS) padded += placeholderAffix(padded.size, mode)
            val ordered = checker.canonicalOrder(padded)
            val checked = checker.check(ordered, mode)
            if (checked.status == CheckStatus.INVALID) issues += checkerIssues(checked.issues, ordered, mode)
        }
        val warnings = ArrayList<RelicIssue>()
        val before = issues.size
        if (kind == RelicKind.DEEP) {
            issues += curseIssues(rows, catalog.cursePoolId)
            if (issues.size == before) {
                warnings += RelicIssue(
                    "cursePairing", RankerText.t("cursePairingTitle"),
                    RankerText.f("cursePairingDetail", catalog.cursePoolId), emptyList(),
                )
            }
        } else {
            // 普通遗物没有诅咒槽：带了诅咒一律是多余的。
            for (row in rows) {
                val curse = row.curse ?: continue
                issues += RelicIssue(
                    "curseUnexpected", RankerText.t("curseUnexpectedTitle"),
                    RankerText.f("curseUnexpectedDetail", row.row + 1, curse.name), listOf(curse.effectId),
                )
            }
        }
        return when {
            issues.isNotEmpty() -> RelicCheck(RelicCheckStatus.INVALID, RankerText.t("relicInvalid"), issues, warnings, rows)
            affixes.size < RelicCard.ROWS -> RelicCheck(
                RelicCheckStatus.PARTIAL, RankerText.f("relicPartial", affixes.size, RelicCard.ROWS - affixes.size),
                issues, warnings, rows,
            )
            else -> RelicCheck(
                RelicCheckStatus.VALID,
                RankerText.t(if (kind == RelicKind.DEEP) "relicValidDeep" else "relicValidNormal"),
                issues, warnings, rows,
            )
        }
    }

    /** 不足三条时补的占位词条：能落进该模式的任一槽池、不参与互斥、排在最后（effectId 为负，不出现在文案里）。 */
    fun placeholderAffix(position: Int, mode: CheckMode): Affix = Affix(
        effectId = -(position + 1),
        name = RankerText.t("relicPlaceholderAffix"),
        compatibilityId = -1,
        sortId = Int.MAX_VALUE,
        poolIds = mode.eligiblePoolIds.toList(),
        isCurse = false,
        requiresCurse = false,
    )

    /**
     * LegalityChecker 判出的问题按类型改用本页文案（三端逐字一致），只列真实词条；
     * 排序：重复 → 互斥 → 出货池／槽池模板，同类按涉及词条的规范顺序。
     */
    fun checkerIssues(raw: List<CheckIssue>, ordered: List<Affix>, mode: CheckMode): List<RelicIssue> {
        val position = HashMap<Int, Int>()
        ordered.forEachIndexed { i, affix -> if (affix.effectId !in position) position[affix.effectId] = i }
        val byId = ordered.associateByFirst { it.effectId }
        val real = ordered.filter { it.effectId > 0 }
        val pools = mode.eligiblePoolIds
        val out = ArrayList<Pair<Int, RelicIssue>>()
        for (issue in raw) {
            val kind = when (issue.kind) {
                IssueKind.DUPLICATE -> "duplicate"
                IssueKind.CONFLICT -> "conflict"
                else -> "unavailable"
            }
            var affected = ArrayList<Affix>()
            for (id in issue.effectIds) {
                val affix = byId[id] ?: continue
                if (affix.effectId <= 0 || affected.any { it.effectId == id }) continue
                affected += affix
            }
            affected.sortBy { position[it.effectId] ?: 0 }
            val title: String
            val detail: String
            when (kind) {
                "duplicate" -> {
                    title = RankerText.t("checkDuplicateTitle")
                    detail = RankerText.f("checkDuplicateDetail", (affected.firstOrNull() ?: real.firstOrNull())?.name.orEmpty())
                }
                "conflict" -> {
                    title = RankerText.t("checkConflictTitle")
                    detail = RankerText.f("checkConflictDetail", affected.joinToString("、") { it.name })
                }
                else -> {
                    val outside = real.filter { affix -> affix.poolIds.none { it in pools } }
                    if (outside.isNotEmpty()) {
                        affected = ArrayList(outside)
                        title = RankerText.t("checkPoolTitle")
                        detail = RankerText.f("checkPoolDetail", outside.joinToString("、") { it.name })
                    } else {
                        affected = ArrayList(real)
                        title = RankerText.t("checkTemplateTitle")
                        detail = RankerText.f("checkTemplateDetail", real.joinToString("、") { it.name })
                    }
                }
            }
            val order = KIND_ORDER.indexOf(kind) * 10 + (affected.firstOrNull()?.let { position[it.effectId] } ?: 9)
            out += order to RelicIssue(kind, title, detail, affected.map { it.effectId })
        }
        return out.stableSortedWith { a, b -> a.first.compareTo(b.first) }.map { it.second }
    }

    /**
     * 深夜诅咒配对（与存档检查的深夜遗物审计同一口径、同一文案）：逐行「需诅咒 ⇔ 带诅咒」、诅咒须在诅咒池；
     * 另查涉及诅咒的重复与互斥（正面词条之间的已由 LegalityChecker 查过），词条按出现顺序（先三行正面、再三行诅咒）。
     */
    fun curseIssues(rows: List<RelicRowAffixes>, poolId: Int): List<RelicIssue> {
        val issues = ArrayList<RelicIssue>()
        for (row in rows) {
            val affix = row.affix
            val needsCurse = affix?.requiresCurse == true
            val curse = row.curse
            if (affix != null && needsCurse && curse == null) {
                issues += RelicIssue(
                    "curseMissing", RankerText.t("curseMissingTitle"),
                    RankerText.f("curseMissingDetail", row.row + 1, affix.name), listOf(affix.effectId),
                )
            } else if (!needsCurse && curse != null) {
                issues += RelicIssue(
                    "curseUnexpected", RankerText.t("curseUnexpectedTitle"),
                    RankerText.f("curseUnexpectedDetail", row.row + 1, curse.name), listOf(curse.effectId),
                )
            }
        }
        for (row in rows) {
            val curse = row.curse ?: continue
            if (curse.isCurse && poolId in curse.poolIds) continue
            issues += RelicIssue(
                "curseMismatch", RankerText.t("curseMismatchTitle"),
                RankerText.f("curseMismatchDetail", row.row + 1, curse.name), listOf(curse.effectId),
            )
        }
        val all = ArrayList<Pair<Affix, Boolean>>()
        rows.forEach { row -> row.affix?.let { all += it to false } }
        rows.forEach { row -> row.curse?.let { all += it to true } }
        val dupIds = ArrayList<Int>()
        for ((affix, _) in all) {
            val id = affix.effectId
            if (id in dupIds) continue
            val same = all.filter { it.first.effectId == id }
            if (same.size > 1 && same.any { it.second }) dupIds += id
        }
        if (dupIds.isNotEmpty()) {
            val names = dupIds.map { id -> all.first { it.first.effectId == id }.first.name }
            issues += RelicIssue(
                "duplicate", RankerText.t("curseDuplicateTitle"),
                RankerText.f("curseDuplicateDetail", names.joinToString("、")), dupIds.toList(),
            )
        }
        val conflicting = ArrayList<Affix>()
        for ((affix, _) in all) {
            val compat = affix.compatibilityId
            if (compat == -1) continue
            val group = all.filter { it.first.compatibilityId == compat }
            if (group.size < 2 || group.none { it.second }) continue
            if (conflicting.none { it === affix }) conflicting += affix
        }
        if (conflicting.isNotEmpty()) {
            issues += RelicIssue(
                "conflict", RankerText.t("curseConflictTitle"),
                RankerText.f("curseConflictDetail", conflicting.joinToString("、") { it.name }),
                conflicting.map { it.effectId },
            )
        }
        return issues
    }

    fun pickCurse(index: LoadoutIndex, card: RelicCard, row: Int): Int? {
        if (row !in 0 until RelicCard.ROWS) return null
        for (curse in index.catalog.curses) {
            val trial = RelicCard.custom(card.affixIds, card.curseIds).withCurse(row, curse.effectId)
            val probe = check(index, trial, RelicKind.DEEP)
            if (probe.issues.none { curse.effectId in it.effectIds }) return curse.effectId
        }
        return null
    }

    fun autoAssignCurses(index: LoadoutIndex, card: RelicCard, kind: RelicKind): RelicCard {
        val affixes = RelicCard.padded(card.affixIds)
        if (kind != RelicKind.DEEP) return card.copy(affixIds = affixes, curseIds = RelicCard.padded(emptyList()))
        var next = card.copy(affixIds = affixes, curseIds = RelicCard.padded(card.curseIds))
        for (position in 0 until RelicCard.ROWS) {
            val affix = next.affixAt(position)?.let { index.catalog.byId[it] }
            if (affix == null || !affix.requiresCurse) {
                next = next.copy(curseIds = next.curseIds.toMutableList().also { it[position] = null })
                continue
            }
            if (next.curseAt(position) != null) continue
            val curse = pickCurse(index, next, position)
            next = next.copy(curseIds = next.curseIds.toMutableList().also { it[position] = curse })
        }
        return next
    }
}
