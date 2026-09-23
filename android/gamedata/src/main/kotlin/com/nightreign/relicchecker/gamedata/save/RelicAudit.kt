package com.nightreign.relicchecker.gamedata.save

import com.nightreign.relicchecker.catalog.AffixCatalog

// 单件遗物审计：逐条移植 macOS 端 RelicCore/RelicAudit.swift（文案以 macOS 为准），
// kind 序列与 Windows 端 renderer/core.js 的 auditRelic 一致（testdata/audit_cases.json 对拍）。

enum class RelicAuditStatus(val raw: String) { VALID("valid"), INVALID("invalid") }

/** 问题种类；[raw] 与桌面端 / 对拍用例里的字符串一致。 */
enum class RelicIssueKind(val raw: String) {
    UNKNOWN_ITEM("unknownItem"),
    ILLEGAL_RANGE("illegalRange"),
    OUT_OF_RANGE("outOfRange"),
    UNKNOWN_EFFECT("unknownEffect"),
    DUPLICATE("duplicate"),
    CONFLICT("conflict"),
    EFFECT_UNEXPECTED("effectUnexpected"),
    EFFECT_MISSING("effectMissing"),
    SLOT_MISMATCH("slotMismatch"),
    CURSE_UNEXPECTED("curseUnexpected"),
    CURSE_MISSING("curseMissing"),
    CURSE_MISMATCH("curseMismatch"),
    WRONG_ORDER("wrongOrder"),
    UNIQUE_DUPLICATE("uniqueDuplicate"),
}

data class RelicAuditIssue(
    val kind: RelicIssueKind,
    val title: String,
    val detail: String,
    val effectIds: List<Long>,
)

data class RelicAuditResult(
    val status: RelicAuditStatus,
    val issues: List<RelicAuditIssue> = emptyList(),
    val warnings: List<RelicAuditIssue> = emptyList(),
    /** 保存顺序错误时给出的规范顺序（补 -1 到 3 位）。 */
    val orderedEffects: List<Long>? = null,
    /** 唯一遗物被改动时给出的官方固定词条（按保存顺序，补 -1 到 3 位）。 */
    val officialEffects: List<Long>? = null,
)

/** 审计所需的词条索引条目（词条库 ∪ extraAffixes）。 */
data class AuditAffix(
    val effectId: Long,
    val name: String,
    val sortId: Int,
    val compatibilityId: Int,
    val isCurse: Boolean,
    val requiresCurse: Boolean,
)

class RelicAuditContext(catalog: AffixCatalog, relicData: RelicDataSet) {
    val relicsById: Map<Int, RelicInfo> = relicData.relicsById
    val pools: Map<Int, Set<Long>> = relicData.pools
    val affixIndex: Map<Long, AuditAffix>
    val deepUnionPool: Set<Long>

    /** effectId → 词条名（报告与页面共用，只建一次）。 */
    val affixNames: Map<Long, String>

    init {
        val index = HashMap<Long, AuditAffix>(catalog.affixes.size + relicData.extraAffixes.size)
        catalog.affixes.forEach { affix ->
            index[affix.effectId.toLong()] = AuditAffix(
                effectId = affix.effectId.toLong(),
                name = affix.name,
                sortId = affix.sortId,
                compatibilityId = affix.compatibilityId,
                isCurse = affix.isCurse,
                requiresCurse = affix.requiresCurse,
            )
        }
        relicData.extraAffixes.forEach { extra ->
            if (extra.effectId !in index) {
                index[extra.effectId] = AuditAffix(
                    effectId = extra.effectId,
                    name = extra.name,
                    sortId = extra.sortId,
                    compatibilityId = extra.compatibilityId,
                    isCurse = false,
                    requiresCurse = false,
                )
            }
        }
        affixIndex = index
        affixNames = index.mapValues { it.value.name }
        deepUnionPool = DEEP_POSITIVE_POOL_IDS.flatMapTo(HashSet()) { pools[it].orEmpty() }
    }

    companion object {
        val DEEP_POSITIVE_POOL_IDS: List<Int> = listOf(2_000_000, 2_100_000, 2_200_000)
        const val DEEP_CURSE_POOL_ID = 3_000_000
    }
}

/** 唯一遗物 ID 区段。 */
fun isUniqueRelicId(id: Int): Boolean = id in 1000..2100 || id in 10000..19999

/** 遗物种类文案（按优先级）。 */
fun relicKindLabel(id: Int, info: RelicInfo?): String = when {
    info?.deep == true -> "深夜遗物"
    isUniqueRelicId(id) -> "唯一遗物"
    id in 100..199 -> "商店遗物（旧版）"
    id in 200..299 -> "商店遗物"
    id in 1_000_000..1_009_999 -> "对局奖励"
    else -> "遗物"
}

/** 颜色文案（0 红 1 蓝 2 黄 3 绿 4 白）。 */
fun relicColorLabel(color: Int): String = when (color) {
    0 -> "红"
    1 -> "蓝"
    2 -> "黄"
    3 -> "绿"
    4 -> "白"
    else -> "未知"
}

fun relicDisplayName(id: Int, info: RelicInfo?): String = when {
    info == null -> "未知遗物 #$id"
    info.name.isEmpty() -> "未命名遗物 #$id"
    else -> info.name
}

/** 空哨兵归一化（0 / 0xFFFFFFFF / 负值 → -1）；审计、报告、对比三处同一条规则。 */
fun normalizeEffectId(raw: Long): Long = if (raw <= 0L || raw == 0xFFFFFFFFL) -1L else raw

/** 补齐到 3 位并归一化空哨兵。 */
fun normalizedTriple(values: List<Long>): List<Long> = List(3) { normalizeEffectId(values.getOrElse(it) { -1L }) }

class RelicAuditor {
    private class SlotProblem(val kind: RelicIssueKind, val rank: Int, val pairIndex: Int, val effectId: Long?)

    fun audit(relic: SaveRelic, context: RelicAuditContext): RelicAuditResult {
        val issues = ArrayList<RelicAuditIssue>()
        var orderedEffects: List<Long>? = null
        var officialEffects: List<Long>? = null

        val effects = normalizedTriple(relic.effects)
        val curses = normalizedTriple(relic.curses)
        val itemId = relic.itemId

        // 1. 未知遗物 ID：无法继续，跳过其余检查
        val info = context.relicsById[itemId]
        if (info == null) {
            issues += RelicAuditIssue(
                RelicIssueKind.UNKNOWN_ITEM,
                "未知遗物 ID",
                "遗物 ID $itemId 不在遗物数据表中，无法继续校验词条。",
                emptyList(),
            )
            return RelicAuditResult(RelicAuditStatus.INVALID, issues)
        }

        // 2. 作弊器常用区段
        if (itemId in 20000..30035) {
            issues += RelicAuditIssue(
                RelicIssueKind.ILLEGAL_RANGE,
                "处于作弊器常用 ID 区段",
                "遗物 ID $itemId 落在 20000-30035 区段，正常游玩不会获得。",
                emptyList(),
            )
        }

        // 3. 合法 ID 范围
        if (itemId < 100 || itemId > 2_013_322) {
            issues += RelicAuditIssue(
                RelicIssueKind.OUT_OF_RANGE,
                "超出合法遗物 ID 范围",
                "遗物 ID $itemId 不在 100-2013322 的合法范围内。",
                emptyList(),
            )
        }

        // 4. 未知词条：无法继续词条级检查
        val all = effects + curses
        val unknownIds = all.filter { it != -1L && it !in context.affixIndex }.distinct()
        if (unknownIds.isNotEmpty()) {
            issues += RelicAuditIssue(
                RelicIssueKind.UNKNOWN_EFFECT,
                "存在未知词条 ID",
                "以下词条 ID 不在词条索引中：" + unknownIds.joinToString("、"),
                unknownIds,
            )
            return RelicAuditResult(RelicAuditStatus.INVALID, issues)
        }

        val nonEmptyAll = all.filter { it != -1L }

        // 5. 词条重复
        val counts = nonEmptyAll.groupingBy { it }.eachCount()
        val duplicated = nonEmptyAll.filter { counts.getValue(it) > 1 }.distinct()
        if (duplicated.isNotEmpty()) {
            issues += RelicAuditIssue(
                RelicIssueKind.DUPLICATE,
                "词条重复",
                "同一词条在这件遗物上出现多次：" + duplicated.joinToString("、") { affixLabel(it, context) },
                duplicated,
            )
        }

        // 6. 互斥词条（compatibilityId == -1 豁免）
        val compatibility = { id: Long -> context.affixIndex[id]?.compatibilityId ?: -1 }
        val groupSizes = nonEmptyAll.filter { compatibility(it) != -1 }.groupingBy(compatibility).eachCount()
        val conflicting = nonEmptyAll.filter { compatibility(it) != -1 && groupSizes.getValue(compatibility(it)) > 1 }.distinct()
        if (conflicting.isNotEmpty()) {
            issues += RelicAuditIssue(
                RelicIssueKind.CONFLICT,
                "互斥词条同时出现",
                conflicting.joinToString("、") { affixLabel(it, context) } + " 属于同一互斥组，不能同时出现。",
                conflicting,
            )
        }

        // 7. 槽池与诅咒配对：深夜遗物按行配对；非深夜遗物（含唯一遗物）按参数行模板做 6 种排列匹配
        if (info.deep) {
            auditDeepRelic(effects, curses, info, context, issues)
        } else {
            var bestProblems: List<SlotProblem>? = null
            for (permutation in PAIR_PERMUTATIONS) {
                val problems = slotProblems(effects, curses, info, permutation, context)
                if (problems.isEmpty()) {
                    bestProblems = null
                    break
                }
                if (bestProblems == null || problems.size < bestProblems.size) bestProblems = problems
            }
            if (bestProblems != null) {
                bestProblems
                    .sortedWith(compareBy<SlotProblem>({ it.rank }, { it.pairIndex }))
                    .forEach { issues += issueFor(it, context) }
                // 唯一遗物被改动时给出官方固定词条，便于改回
                if (isUniqueRelicId(itemId)) officialEffects = officialFixedEffects(info, context)
            }
        }

        // 10. 保存顺序（仅当没有别的问题时评估）
        if (issues.isEmpty()) {
            val canonical = canonicalEffectOrder(effects, context)
            if (canonical != effects) {
                orderedEffects = canonical
                issues += RelicAuditIssue(
                    RelicIssueKind.WRONG_ORDER,
                    "保存顺序错误",
                    "正面词条未按 (sortId, effectId) 升序保存，空槽应排在最后。",
                    effects.filter { it != -1L },
                )
            }
        }

        return RelicAuditResult(
            status = if (issues.isEmpty()) RelicAuditStatus.VALID else RelicAuditStatus.INVALID,
            issues = issues,
            warnings = emptyList(),
            orderedEffects = orderedEffects,
            officialEffects = officialEffects,
        )
    }

    /**
     * 按角色的整体检查：唯一遗物重复持有。同一 ID 的多件里，首件合法者豁免，其余逐件追加
     * uniqueDuplicate 并转为非法。返回新的结果列表（入参不变）。
     */
    fun applyUniqueDuplicates(results: List<RelicAuditResult>, relics: List<SaveRelic>): List<RelicAuditResult> {
        if (results.size != relics.size) return results
        val groups = LinkedHashMap<Int, MutableList<Int>>()
        relics.forEachIndexed { index, relic ->
            if (isUniqueRelicId(relic.itemId)) groups.getOrPut(relic.itemId) { ArrayList() } += index
        }
        val updated = results.toMutableList()
        for (itemId in groups.keys.sorted()) {
            val indices = groups.getValue(itemId)
            if (indices.size <= 1) continue
            val exempt = indices.firstOrNull { results[it].status == RelicAuditStatus.VALID }
            for (index in indices) {
                if (index == exempt) continue
                updated[index] = updated[index].copy(
                    status = RelicAuditStatus.INVALID,
                    issues = updated[index].issues + RelicAuditIssue(
                        RelicIssueKind.UNIQUE_DUPLICATE,
                        "唯一遗物重复持有",
                        "同一角色持有多件唯一遗物（ID $itemId），仅首件合法者视为正常。",
                        emptyList(),
                    ),
                )
            }
        }
        return updated
    }

    /** 规范顺序：非空词条按 (sortId, effectId) 升序，空槽补在最后。 */
    fun canonicalEffectOrder(effects: List<Long>, context: RelicAuditContext): List<Long> {
        val sorted = effects.filter { it != -1L }.sortedWith(
            compareBy<Long>({ context.affixIndex[it]?.sortId ?: Int.MAX_VALUE }, { it }),
        )
        return sorted + List(effects.size - sorted.size) { -1L }
    }

    /** 唯一遗物的官方固定词条：各槽池都是单词条固定池时可完全确定。 */
    private fun officialFixedEffects(info: RelicInfo, context: RelicAuditContext): List<Long>? {
        val ids = ArrayList<Long>()
        for (pool in info.slots) {
            if (pool == -1) continue
            val members = context.pools[pool] ?: return null
            if (members.size != 1) return null
            ids += members.first()
        }
        if (ids.isEmpty() || !ids.all { it in context.affixIndex }) return null
        val ordered = canonicalEffectOrder(ids + List(3 - ids.size) { -1L }, context).toMutableList()
        while (ordered.size < 3) ordered += -1L
        return ordered
    }

    private fun slotProblems(
        effects: List<Long>,
        curses: List<Long>,
        info: RelicInfo,
        permutation: IntArray,
        context: RelicAuditContext,
    ): List<SlotProblem> {
        val problems = ArrayList<SlotProblem>()
        for (pairIndex in 0 until 3) {
            val slotIndex = permutation[pairIndex]
            val slotPool = info.slots.getOrElse(slotIndex) { -1 }
            val cursePool = info.curseSlots.getOrElse(slotIndex) { -1 }
            val effect = effects[pairIndex]
            val curse = curses[pairIndex]

            if (slotPool == -1) {
                if (effect != -1L) problems += SlotProblem(RelicIssueKind.EFFECT_UNEXPECTED, 0, pairIndex, effect)
            } else if (effect == -1L) {
                problems += SlotProblem(RelicIssueKind.EFFECT_MISSING, 1, pairIndex, null)
            } else if (effect !in rollable(slotPool, context)) {
                problems += SlotProblem(RelicIssueKind.SLOT_MISMATCH, 2, pairIndex, effect)
            }

            if (cursePool == -1) {
                if (curse != -1L) problems += SlotProblem(RelicIssueKind.CURSE_UNEXPECTED, 3, pairIndex, curse)
            } else if (curse == -1L) {
                problems += SlotProblem(RelicIssueKind.CURSE_MISSING, 4, pairIndex, effect.takeIf { it != -1L })
            } else if (curse !in rollable(cursePool, context)) {
                problems += SlotProblem(RelicIssueKind.CURSE_MISMATCH, 5, pairIndex, curse)
            }
        }
        return problems
    }

    private fun rollable(poolId: Int, context: RelicAuditContext): Set<Long> = context.pools[poolId].orEmpty()

    /**
     * 深夜遗物按行配对模型：词条数 = 槽数；正面词条 ∈ A/B/C 池并集；
     * 第 i 行「需诅咒」⇔ 第 i 行有负面词条；负面词条 ∈ 诅咒池。
     */
    private fun auditDeepRelic(
        effects: List<Long>,
        curses: List<Long>,
        info: RelicInfo,
        context: RelicAuditContext,
        issues: MutableList<RelicAuditIssue>,
    ) {
        val slotCount = info.slots.count { it != -1 }
        val effectCount = effects.count { it != -1L }
        if (effectCount < slotCount) {
            issues += RelicAuditIssue(
                RelicIssueKind.EFFECT_MISSING,
                "正面词条数量不足",
                "该遗物应有 $slotCount 条正面词条，实有 $effectCount 条",
                emptyList(),
            )
        } else if (effectCount > slotCount) {
            issues += RelicAuditIssue(
                RelicIssueKind.EFFECT_UNEXPECTED,
                "正面词条数量超出",
                "该遗物应有 $slotCount 条正面词条，实有 $effectCount 条",
                emptyList(),
            )
        }
        for (row in 0 until 3) {
            val effect = effects[row]
            if (effect != -1L && effect !in context.deepUnionPool) {
                issues += RelicAuditIssue(
                    RelicIssueKind.SLOT_MISMATCH,
                    "正面词条不在深夜词条池",
                    "第 ${row + 1} 行的正面词条不在深夜词条池中：${affixLabel(effect, context)}",
                    listOf(effect),
                )
            }
        }
        for (row in 0 until 3) {
            val effect = effects[row]
            val curse = curses[row]
            val needsCurse = effect != -1L && context.affixIndex[effect]?.requiresCurse == true
            if (needsCurse && curse == -1L) {
                issues += RelicAuditIssue(
                    RelicIssueKind.CURSE_MISSING,
                    "需诅咒的词条缺少负面词条",
                    "第 ${row + 1} 行的正面词条需要配对负面词条：${affixLabel(effect, context)}",
                    listOf(effect),
                )
            } else if (!needsCurse && curse != -1L) {
                issues += RelicAuditIssue(
                    RelicIssueKind.CURSE_UNEXPECTED,
                    "多余的负面词条",
                    "第 ${row + 1} 行的正面词条不需要负面词条，却携带负面词条：${affixLabel(curse, context)}",
                    listOf(curse),
                )
            }
        }
        for (row in 0 until 3) {
            val curse = curses[row]
            if (curse != -1L && curse !in rollable(RelicAuditContext.DEEP_CURSE_POOL_ID, context)) {
                issues += RelicAuditIssue(
                    RelicIssueKind.CURSE_MISMATCH,
                    "负面词条不在诅咒池",
                    "第 ${row + 1} 行的负面词条不在诅咒池：${affixLabel(curse, context)}",
                    listOf(curse),
                )
            }
        }
    }

    private fun issueFor(problem: SlotProblem, context: RelicAuditContext): RelicAuditIssue {
        val row = problem.pairIndex + 1
        val label = problem.effectId?.let { affixLabel(it, context) } ?: ""
        val ids = listOfNotNull(problem.effectId)
        return when (problem.kind) {
            RelicIssueKind.EFFECT_UNEXPECTED -> RelicAuditIssue(
                problem.kind, "多余的正面词条", "第 $row 行对应的模板槽位不存在，却出现正面词条 $label。", ids,
            )
            RelicIssueKind.EFFECT_MISSING -> RelicAuditIssue(
                problem.kind, "正面词条缺失", "第 $row 行对应的模板槽位需要正面词条，但该行为空。", ids,
            )
            RelicIssueKind.SLOT_MISMATCH -> RelicAuditIssue(
                problem.kind, "正面词条不在对应槽池", "第 $row 行的正面词条 $label 不在对应槽位的可掉落池中。", ids,
            )
            RelicIssueKind.CURSE_UNEXPECTED -> RelicAuditIssue(
                problem.kind, "多余的负面词条", "第 $row 行对应的诅咒槽不存在，却出现负面词条 $label。", ids,
            )
            RelicIssueKind.CURSE_MISSING -> RelicAuditIssue(
                problem.kind,
                "需诅咒的词条缺少负面词条",
                "第 $row 行的诅咒槽不允许为空" + if (label.isEmpty()) "。" else "：$label。",
                ids,
            )
            RelicIssueKind.CURSE_MISMATCH -> RelicAuditIssue(
                problem.kind, "负面词条不在诅咒池", "第 $row 行的负面词条 $label 不在诅咒池的可掉落集合中。", ids,
            )
            else -> RelicAuditIssue(problem.kind, "", "", ids)
        }
    }

    private fun affixLabel(effectId: Long, context: RelicAuditContext): String {
        val name = context.affixIndex[effectId]?.name
        return if (!name.isNullOrEmpty()) "$name（$effectId）" else effectId.toString()
    }

    companion object {
        /** 排列 p 表示存档第 j 对放进模板槽位 p[j]；顺序与契约一致。 */
        private val PAIR_PERMUTATIONS: List<IntArray> = listOf(
            intArrayOf(0, 1, 2), intArrayOf(0, 2, 1), intArrayOf(1, 0, 2),
            intArrayOf(1, 2, 0), intArrayOf(2, 0, 1), intArrayOf(2, 1, 0),
        )
    }
}
