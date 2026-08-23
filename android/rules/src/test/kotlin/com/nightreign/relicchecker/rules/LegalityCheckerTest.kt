package com.nightreign.relicchecker.rules

import kotlin.random.Random
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertTrue

class LegalityCheckerTest {
    private val checker = LegalityChecker()

    @Test
    fun `valid ordered current combination passes`() {
        val result = checker.check(
            listOf(
                affix(10, compatibility = 1, sort = 100),
                affix(20, compatibility = 2, sort = 200),
                affix(30, compatibility = -1, sort = 300),
            ),
            CheckMode.CURRENT_NORMAL,
        )

        assertEquals(CheckStatus.VALID, result.status)
        assertTrue(result.issues.isEmpty())
    }

    @Test
    fun `effect id duplicate is invalid`() {
        val duplicate = affix(10, compatibility = -1, sort = 100)
        val result = checker.check(
            listOf(duplicate, duplicate, affix(30, compatibility = -1, sort = 300)),
            CheckMode.CURRENT_NORMAL,
        )

        assertEquals(CheckStatus.INVALID, result.status)
        assertTrue(result.issues.any { it.kind == IssueKind.DUPLICATE })
    }

    @Test
    fun `non minus one compatibility id conflicts while minus one is exempt`() {
        val conflict = checker.check(
            listOf(
                affix(10, compatibility = 100, sort = 100),
                affix(20, compatibility = 100, sort = 200),
                affix(30, compatibility = -1, sort = 300),
            ),
            CheckMode.CURRENT_NORMAL,
        )
        val unrestricted = checker.check(
            listOf(
                affix(10, compatibility = -1, sort = 100),
                affix(20, compatibility = -1, sort = 200),
                affix(30, compatibility = -1, sort = 300),
            ),
            CheckMode.CURRENT_NORMAL,
        )

        assertEquals(CheckStatus.INVALID, conflict.status)
        assertTrue(conflict.issues.any { it.kind == IssueKind.CONFLICT })
        assertEquals(CheckStatus.VALID, unrestricted.status)
    }

    @Test
    fun `pool membership uses one to one slot assignment`() {
        val assignable = listOf(
            affix(1, 1, 1, pools = listOf(210)),
            affix(2, 2, 2, pools = listOf(310)),
            affix(3, 3, 3, pools = listOf(110)),
        )
        val impossible = listOf(
            affix(11, 11, 11, pools = listOf(110)),
            affix(12, 12, 12, pools = listOf(110)),
            affix(13, 13, 13, pools = listOf(210, 310)),
        )

        assertTrue(checker.hasPoolAssignment(assignable, listOf(110, 210, 310)))
        val requiresBacktracking = listOf(
            affix(21, 21, 21, pools = listOf(110, 210)),
            affix(22, 22, 22, pools = listOf(110)),
            affix(23, 23, 23, pools = listOf(310)),
        )
        assertTrue(checker.hasPoolAssignment(requiresBacktracking, listOf(110, 210, 310)))
        assertEquals(CheckStatus.VALID, checker.check(assignable, CheckMode.CURRENT_NORMAL).status)
        val result = checker.check(impossible, CheckMode.CURRENT_NORMAL)
        assertEquals(CheckStatus.INVALID, result.status)
        assertTrue(result.issues.any {
            it.kind == IssueKind.UNAVAILABLE && it.title == "不符合当前槽池模板"
        })
    }

    @Test
    fun `affix outside selected pool is reported`() {
        val result = checker.check(
            listOf(
                affix(10, 1, 100),
                affix(20, 2, 200),
                affix(30, 3, 300, pools = listOf(2_000_000)),
            ),
            CheckMode.CURRENT_NORMAL,
        )

        assertEquals(CheckStatus.INVALID, result.status)
        assertTrue(result.issues.any {
            it.kind == IssueKind.UNAVAILABLE && it.title == "不在当前出货池"
        })
    }

    @Test
    fun `canonical order compares sort id then effect id`() {
        val ordered = checker.canonicalOrder(
            listOf(
                affix(12, 1, 100),
                affix(10, 2, 100),
                affix(11, 3, 100),
            ),
        )
        assertEquals(listOf(10, 11, 12), ordered.map(Affix::effectId))

        val result = checker.check(
            listOf(
                affix(30, 3, 300),
                affix(10, 1, 100),
                affix(20, 2, 200),
            ),
            CheckMode.CURRENT_NORMAL,
        )
        assertEquals(CheckStatus.WRONG_ORDER, result.status)
        assertEquals(listOf(10, 20, 30), result.orderedAffixes.map(Affix::effectId))
    }

    @Test
    fun `all seven real deep templates pass`() {
        assertEquals(
            listOf(
                listOf(2_000_000, 2_000_000, 2_000_000),
                listOf(2_000_000, 2_000_000, 2_100_000),
                listOf(2_000_000, 2_100_000, 2_100_000),
                listOf(2_100_000, 2_100_000, 2_100_000),
                listOf(2_000_000, 2_000_000, 2_200_000),
                listOf(2_000_000, 2_200_000, 2_200_000),
                listOf(2_200_000, 2_200_000, 2_200_000),
            ),
            CheckMode.DEEP_POSITIVE.slotPoolSequences,
        )

        CheckMode.DEEP_POSITIVE.slotPoolSequences.forEachIndexed { templateIndex, template ->
            val combination = template.mapIndexed { affixIndex, poolId ->
                affix(
                    id = 10_000 + templateIndex * 10 + affixIndex,
                    compatibility = 100 + affixIndex,
                    sort = 100 + affixIndex,
                    pools = listOf(poolId),
                    requiresCurse = poolId == 2_000_000,
                )
            }
            val result = checker.check(combination, CheckMode.DEEP_POSITIVE)
            assertEquals(CheckStatus.VALID, result.status, "template=$template")
            assertEquals(1, result.warnings.count { it.kind == IssueKind.CURSE_PAIRING })
        }
    }

    @Test
    fun `nonexistent deep ABC template is invalid`() {
        val result = checker.check(
            listOf(
                affix(1, 1, 1, listOf(2_000_000), requiresCurse = true),
                affix(2, 2, 2, listOf(2_100_000)),
                affix(3, 3, 3, listOf(2_200_000)),
            ),
            CheckMode.DEEP_POSITIVE,
        )

        assertEquals(CheckStatus.INVALID, result.status)
        assertTrue(result.issues.any { it.title == "不符合当前槽池模板" })
        assertEquals(1, result.warnings.count { it.kind == IssueKind.CURSE_PAIRING })
    }

    @Test
    fun `deep complete checks always warn and count A only entries`() {
        val incomplete = checker.check(emptyList(), CheckMode.DEEP_POSITIVE)
        assertEquals(CheckStatus.INCOMPLETE, incomplete.status)
        assertTrue(incomplete.warnings.isEmpty())

        val affixes = listOf(
            affix(1, 1, 1, listOf(2_000_000), requiresCurse = true),
            affix(2, 2, 2, listOf(2_000_000), requiresCurse = true),
            affix(3, 3, 3, listOf(2_100_000)),
        )
        val result = checker.check(affixes, CheckMode.DEEP_POSITIVE)
        val warning = result.warnings.single()
        assertEquals(listOf(1, 2), warning.effectIds)
        assertTrue(warning.detail.contains("2 条为仅 A 池词条"))
        assertTrue(warning.detail.contains("至少需要 2 个对应诅咒槽"))
        assertTrue(result.message.contains("不等同"))

        val wrongOrder = checker.check(affixes.reversed(), CheckMode.DEEP_POSITIVE)
        assertEquals(CheckStatus.WRONG_ORDER, wrongOrder.status)
        assertEquals(1, wrongOrder.warnings.count { it.kind == IssueKind.CURSE_PAIRING })
    }

    @Test
    fun `compatibility only skips pool membership but still checks conflicts`() {
        val result = checker.check(
            listOf(
                affix(1, 1, 1, pools = emptyList()),
                affix(2, 2, 2, pools = emptyList()),
                affix(3, 3, 3, pools = emptyList()),
            ),
            CheckMode.COMPATIBILITY_ONLY,
        )
        assertEquals(CheckStatus.VALID, result.status)
    }

    @Test
    fun `random output is canonical and legal`() {
        val candidates = (1..12).map { index ->
            affix(
                id = index,
                compatibility = index,
                sort = 20 - index,
            )
        }
        val random = assertNotNull(
            checker.randomCombination(candidates, CheckMode.CURRENT_NORMAL, Random(42)),
        )
        assertEquals(CheckStatus.VALID, checker.check(random, CheckMode.CURRENT_NORMAL).status)
        assertEquals(checker.canonicalOrder(random), random)
    }

    private fun affix(
        id: Int,
        compatibility: Int,
        sort: Int,
        pools: List<Int> = listOf(110, 210, 310),
        requiresCurse: Boolean = false,
    ) = Affix(
        effectId = id,
        name = "词条 $id",
        compatibilityId = compatibility,
        sortId = sort,
        poolIds = pools,
        requiresCurse = requiresCurse,
    )
}
