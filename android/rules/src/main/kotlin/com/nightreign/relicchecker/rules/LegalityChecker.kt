package com.nightreign.relicchecker.rules

import kotlin.random.Random

enum class CheckStatus {
    INCOMPLETE,
    VALID,
    WRONG_ORDER,
    INVALID,
}

enum class IssueKind {
    DUPLICATE,
    CONFLICT,
    UNAVAILABLE,
    CURSE_PAIRING,
}

data class CheckIssue(
    val kind: IssueKind,
    val title: String,
    val detail: String,
    val effectIds: List<Int>,
)

data class CheckResult(
    val status: CheckStatus,
    val message: String,
    val orderedAffixes: List<Affix> = emptyList(),
    val issues: List<CheckIssue> = emptyList(),
    val warnings: List<CheckIssue> = emptyList(),
)

class LegalityChecker {
    fun check(affixes: List<Affix>, mode: CheckMode): CheckResult {
        if (affixes.size != SLOT_COUNT) {
            return CheckResult(
                status = CheckStatus.INCOMPLETE,
                message = "请选择三个词条",
            )
        }
        val warnings = deepWarnings(affixes, mode)

        val issues = mutableListOf<CheckIssue>()

        affixes.groupBy(Affix::effectId)
            .values
            .filter { it.size > 1 }
            .forEach { group ->
                issues += CheckIssue(
                    kind = IssueKind.DUPLICATE,
                    title = "词条重复",
                    detail = "同一个效果不能在一件遗物上出现两次：${group.first().name}",
                    effectIds = group.map(Affix::effectId),
                )
            }

        affixes.filter { it.compatibilityId != -1 }
            .groupBy(Affix::compatibilityId)
            .values
            .filter { it.size > 1 }
            .forEach { group ->
                issues += CheckIssue(
                    kind = IssueKind.CONFLICT,
                    title = "同一互斥池",
                    detail = group.joinToString("、", transform = Affix::name) + " 不能同时出现",
                    effectIds = group.map(Affix::effectId),
                )
            }

        if (
            mode != CheckMode.COMPATIBILITY_ONLY &&
            !hasPoolPatternAssignment(affixes, mode.slotPoolSequences)
        ) {
            val unavailable = affixes.filter { affix ->
                affix.poolIds.none(mode.eligiblePoolIds::contains)
            }
            val affected = unavailable.ifEmpty { affixes }
            val isPatternMismatch = unavailable.isEmpty()
            issues += CheckIssue(
                kind = IssueKind.UNAVAILABLE,
                title = if (isPatternMismatch) "不符合当前槽池模板" else "不在当前出货池",
                detail = affected.joinToString("、", transform = Affix::name) +
                    if (isPatternMismatch) {
                        " 无法分配到任一真实的三词条槽池模板"
                    } else {
                        " 不属于当前校验口径的非零权重出货池"
                    },
                effectIds = affected.map(Affix::effectId),
            )
        }

        val ordered = canonicalOrder(affixes)
        if (issues.isNotEmpty()) {
            return CheckResult(
                status = CheckStatus.INVALID,
                message = "该三词条组合不合法",
                orderedAffixes = ordered,
                issues = issues,
                warnings = warnings,
            )
        }

        if (ordered.map(Affix::effectId) != affixes.map(Affix::effectId)) {
            return CheckResult(
                status = CheckStatus.WRONG_ORDER,
                message = "组合本身可成立，但词条顺序错误",
                orderedAffixes = ordered,
                warnings = warnings,
            )
        }

        return CheckResult(
            status = CheckStatus.VALID,
            message = if (mode == CheckMode.DEEP_POSITIVE) {
                "正面词条预检通过；不等同于完整深夜遗物合法"
            } else {
                "该三词条组合合法，顺序正确"
            },
            orderedAffixes = ordered,
            warnings = warnings,
        )
    }

    fun canonicalOrder(affixes: List<Affix>): List<Affix> =
        affixes.sortedWith(compareBy(Affix::sortId, Affix::effectId))

    fun hasPoolAssignment(affixes: List<Affix>, slotPools: List<Int>): Boolean {
        if (affixes.size != slotPools.size) return false
        if (slotPools.isEmpty()) return true

        val used = BooleanArray(affixes.size)
        fun assign(slotIndex: Int): Boolean {
            if (slotIndex == slotPools.size) return true
            for (affixIndex in affixes.indices) {
                if (!used[affixIndex] && slotPools[slotIndex] in affixes[affixIndex].poolIds) {
                    used[affixIndex] = true
                    if (assign(slotIndex + 1)) return true
                    used[affixIndex] = false
                }
            }
            return false
        }
        return assign(0)
    }

    fun hasPoolPatternAssignment(
        affixes: List<Affix>,
        slotPoolSequences: List<List<Int>>,
    ): Boolean = slotPoolSequences.any { hasPoolAssignment(affixes, it) }

    fun randomCombination(
        catalog: List<Affix>,
        mode: CheckMode,
        random: Random = Random.Default,
    ): List<Affix>? {
        val candidates = catalog.filter { it.isEligible(mode) }
        if (candidates.size < SLOT_COUNT) return null

        repeat(MAX_RANDOM_ATTEMPTS) {
            val sample = candidates.shuffled(random).take(SLOT_COUNT)
            val ordered = canonicalOrder(sample)
            if (check(ordered, mode).status == CheckStatus.VALID) return ordered
        }
        return null
    }

    private fun deepWarnings(affixes: List<Affix>, mode: CheckMode): List<CheckIssue> {
        if (mode != CheckMode.DEEP_POSITIVE) return emptyList()
        val curseBound = affixes.filter(Affix::requiresCurse)
        val curseRequirement = if (curseBound.isEmpty()) {
            "其中没有仅 A 池词条；"
        } else {
            "其中 ${curseBound.size} 条为仅 A 池词条，至少需要 ${curseBound.size} 个对应诅咒槽；"
        }
        val curseNames = curseBound.joinToString("、", transform = Affix::name)
        return listOf(
            CheckIssue(
                kind = IssueKind.CURSE_PAIRING,
                title = "深夜模式仅作预检",
                detail = curseRequirement +
                    "当前仅预检三条正面效果，完整深夜遗物仍需结合具体遗物 ID、实际槽池模板与负面词条验证。" +
                    if (curseNames.isEmpty()) "" else "仅 A 池词条：$curseNames",
                effectIds = curseBound.map(Affix::effectId),
            ),
        )
    }

    private companion object {
        const val SLOT_COUNT = 3
        const val MAX_RANDOM_ATTEMPTS = 6_000
    }
}
