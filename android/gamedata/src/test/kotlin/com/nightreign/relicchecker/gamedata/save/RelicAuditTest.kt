package com.nightreign.relicchecker.gamedata.save

import com.nightreign.relicchecker.gamedata.GameDataFormatException
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

/**
 * 单件遗物审计：macOS RelicCoreChecks/main.swift 的断言、Windows tests/core_audit.test.mjs，
 * 以及两端共用的对拍用例 testdata/audit_cases.json（status 与 issue kind 序列必须逐字一致）。
 */
class RelicAuditTest {
    private val context get() = SaveTestData.context
    private val auditor = RelicAuditor()

    private fun relic(itemId: Int, effects: List<Long>, curses: List<Long> = listOf(-1, -1, -1), index: Int = 0) =
        SaveRelic(index, itemId, effects, curses)

    private fun audit(itemId: Int, effects: List<Long>, curses: List<Long> = listOf(-1, -1, -1)) =
        auditor.audit(relic(itemId, effects, curses), context)

    private fun kinds(result: RelicAuditResult) = result.issues.map { it.kind.raw }

    // ---- 遗物表解析 ----

    @Test
    fun `relic table facts match the desktop checks`() {
        val data = SaveTestData.relicData
        assertEquals(1397, data.relics.size, "遗物应为 1397 件")
        assertEquals(598, data.pools.size, "槽池应为 598 个")
        assertEquals(1552, data.extraAffixes.size, "extraAffixes 应为 1552 条")
        assertEquals(13496, data.pools.values.sumOf { it.size }, "槽池成员总数")
        assertEquals("v1.03.4 + DLC1", data.gameVersion)
        assertEquals("Param 0d2ad149", data.dataVersion)
        assertTrue(data.relics.all { it.slots.size == 3 && it.curseSlots.size == 3 })

        val deep = data.relicsById.getValue(2_000_002)
        assertEquals("辽阔的火燃暗淡情景", deep.name)
        assertTrue(deep.deep)
        assertEquals(listOf(2_000_000, 2_100_000, 2_100_000), deep.slots)
        assertEquals(listOf(3_000_000, -1, -1), deep.curseSlots)
        assertEquals(listOf(310, 210, 110), data.relicsById.getValue(202).slots)
    }

    @Test
    fun `relic table with a wrong schema version is rejected`() {
        assertFailsWith<GameDataFormatException> { RelicDataSet.parse("""{"relicsSchemaVersion":2,"relics":[]}""") }
        assertFailsWith<GameDataFormatException> { RelicDataSet.parse("""{"relics":[]}""") }
        assertFailsWith<GameDataFormatException> { RelicDataSet.parse("""{"relicsSchemaVersion":""") }
    }

    // core_audit.test.mjs「buildRelicIndex: 索引结构完整」
    @Test
    fun `audit index merges catalog and extra affixes`() {
        val catalog = SaveTestData.catalog
        val data = SaveTestData.relicData
        assertEquals(data.relics.size, context.relicsById.size)
        assertEquals(527, catalog.affixes.size)
        assertEquals(catalog.affixes.size + data.extraAffixes.size, context.affixIndex.size)
        val extra = context.affixIndex.getValue(data.extraAffixes.first().effectId)
        assertFalse(extra.isCurse)
        assertFalse(extra.requiresCurse)
        for (poolId in RelicAuditContext.DEEP_POSITIVE_POOL_IDS) {
            data.pools.getValue(poolId).forEach { assertTrue(it in context.deepUnionPool, "deepUnionPool 缺少 $it") }
        }
        assertEquals("+1点生命力（固定+20点生命值上限）", SaveTestData.auditData.explanations[7_000_000])
        assertNull(SaveTestData.auditData.explanations[424_242])
    }

    // core_audit.test.mjs「relicKindLabel / relicColorLabel」+ main.swift §3
    @Test
    fun `kind colour and display labels`() {
        val byId = context.relicsById
        assertEquals("深夜遗物", relicKindLabel(2_000_002, byId[2_000_002]))
        assertEquals("唯一遗物", relicKindLabel(1000, byId[1000]))
        assertEquals("唯一遗物", relicKindLabel(10000, byId[10000]))
        assertEquals("唯一遗物", relicKindLabel(1040, byId[1040]))
        assertEquals("商店遗物（旧版）", relicKindLabel(100, byId[100]))
        assertEquals("商店遗物（旧版）", relicKindLabel(150, null))
        assertEquals("商店遗物", relicKindLabel(202, byId[202]))
        assertEquals("商店遗物", relicKindLabel(250, null))
        assertEquals("对局奖励", relicKindLabel(1_000_000, byId[1_000_000]))
        assertEquals("对局奖励", relicKindLabel(1_000_005, null))
        assertEquals("遗物", relicKindLabel(6_001_400, byId[6_001_400]))
        assertEquals("遗物", relicKindLabel(424_242, null))
        assertEquals(listOf("红", "蓝", "黄", "绿", "白"), (0..4).map(::relicColorLabel))
        assertEquals("未知", relicColorLabel(9))
        assertEquals("辽阔的火燃暗淡情景", relicDisplayName(2_000_002, byId[2_000_002]))
        assertEquals("未命名遗物 #1", relicDisplayName(1, byId[1]))
        assertEquals("未知遗物 #424242", relicDisplayName(424_242, null))
    }

    // core_audit.test.mjs「0 与 0xFFFFFFFF 归一化为空词条」
    @Test
    fun `empty sentinels normalize to empty slots`() {
        val result = audit(202, listOf(6_630_000, 7_000_000, 7_000_100), listOf(0, 0xFFFFFFFFL, 0))
        assertEquals(RelicAuditStatus.VALID, result.status)
        assertTrue(result.issues.isEmpty())
        assertEquals(listOf(-1L, -1L, -1L), normalizedTriple(listOf(0, -5, 0xFFFFFFFFL, 7)))
        assertEquals(listOf(7L, -1L, -1L), normalizedTriple(listOf(7)))
    }

    // main.swift 的逐条 expectAudit
    @Test
    fun `macos audit expectations`() {
        fun expect(itemId: Int, effects: List<Long>, curses: List<Long>, status: RelicAuditStatus, expected: List<String>, label: String) {
            val result = audit(itemId, effects, curses)
            assertEquals(status, result.status, label)
            assertEquals(expected, kinds(result), label)
            assertTrue(result.warnings.isEmpty(), label)
        }
        val none = listOf(-1L, -1L, -1L)
        val ok = RelicAuditStatus.VALID
        val bad = RelicAuditStatus.INVALID
        expect(202, listOf(6_630_000, 7_000_000, 7_000_100), none, ok, emptyList(), "普通商店遗物合法组合")
        expect(2_000_002, listOf(6_005_601, 6_003_000, 6_003_100), listOf(6_820_000, -1, -1), ok, emptyList(), "深夜遗物严格口径合法组合")
        expect(424_242, none, none, bad, listOf("unknownItem"), "未知遗物 ID")
        expect(20_000, none, none, bad, listOf("illegalRange", "effectMissing"), "作弊器 ID 区段")
        expect(1, listOf(8_100_100, -1, -1), none, bad, listOf("outOfRange"), "超出合法 ID 范围")
        expect(202, listOf(7_000_000, 999_999, 7_000_100), none, bad, listOf("unknownEffect"), "未知词条 ID")
        expect(202, listOf(7_001_400, 7_001_400, 7_000_000), none, bad, listOf("duplicate", "conflict"), "词条重复")
        expect(202, listOf(7_001_400, 7_001_401, 7_000_000), none, bad, listOf("conflict"), "互斥词条同时出现")
        expect(2_000_000, listOf(6_005_601, 6_003_000, -1), listOf(6_820_000, -1, -1), bad, listOf("effectUnexpected"), "多余的正面词条")
        expect(2_000_002, listOf(6_005_601, -1, -1), listOf(6_820_000, -1, -1), bad, listOf("effectMissing"), "正面词条数量不足")
        expect(2_000_002, listOf(6_005_601, 7_000_000, 6_003_000), listOf(6_820_000, -1, -1), bad, listOf("slotMismatch"), "正面词条不在深夜池")
        expect(2_000_002, listOf(6_005_601, 6_003_000, 6_003_100), listOf(6_820_000, 6_820_100, -1), bad, listOf("curseUnexpected"), "多余的负面词条")
        expect(2_000_002, listOf(6_005_601, 6_003_000, 6_003_100), none, bad, listOf("curseMissing"), "需诅咒词条缺少负面词条")
        expect(2_000_002, listOf(6_003_000, 6_003_100, 6_003_200), none, ok, emptyList(), "全部不需诅咒且无负面词条")
        expect(2_000_002, listOf(6_005_601, 6_003_000, 6_003_100), listOf(7_000_000, -1, -1), bad, listOf("curseMismatch"), "负面词条不在诅咒池")
        expect(2_000_002, listOf(6_005_601, 6_003_000, 6_610_400), listOf(6_820_000, -1, -1), bad, listOf("curseMissing"), "第 3 行缺少负面词条")
        expect(2_000_002, listOf(6_003_000, -1, -1), none, bad, listOf("effectMissing"), "深夜正面词条数量不足")
        expect(1_660, listOf(7_031_300, 7_060_200, 7_000_802), none, bad, listOf("slotMismatch", "slotMismatch", "slotMismatch"), "唯一遗物固定词条被修改")
        expect(1_660, listOf(6_641_000, 7_000_302, 7_000_402), none, ok, emptyList(), "唯一遗物官方固定词条")
    }

    // 固定词条不符：唯一遗物被改动时给出官方固定词条，合法时不给
    @Test
    fun `modified unique relic reports its official fixed affixes`() {
        val modified = audit(1_660, listOf(7_031_300, 7_060_200, 7_000_802))
        assertEquals(listOf(6_641_000L, 7_000_302L, 7_000_402L), modified.officialEffects)
        assertEquals("正面词条不在对应槽池", modified.issues.first().title)
        assertTrue(modified.issues.first().detail.startsWith("第 1 行的正面词条 "), modified.issues.first().detail)
        assertTrue(modified.issues.first().detail.endsWith(" 不在对应槽位的可掉落池中。"))
        assertNull(audit(1_660, listOf(6_641_000, 7_000_302, 7_000_402)).officialEffects)
    }

    @Test
    fun `wrong save order gives the canonical order`() {
        val result = audit(202, listOf(7_000_000, 6_630_000, 7_000_100))
        assertEquals(RelicAuditStatus.INVALID, result.status)
        assertEquals(listOf("wrongOrder"), kinds(result))
        assertEquals(listOf(6_630_000L, 7_000_000L, 7_000_100L), result.orderedEffects)
        assertEquals("保存顺序错误", result.issues.single().title)
        assertEquals("正面词条未按 (sortId, effectId) 升序保存，空槽应排在最后。", result.issues.single().detail)
    }

    // 深夜遗物正负配对（按行配对，macOS 文案）
    @Test
    fun `deep relic pairs each row's curse with its positive affix`() {
        val missing = audit(2_000_002, listOf(6_005_601, 7_040_300, 7_040_400))
        val issue = missing.issues.single()
        assertEquals(RelicIssueKind.CURSE_MISSING, issue.kind)
        assertEquals("需诅咒的词条缺少负面词条", issue.title)
        assertTrue(issue.detail.startsWith("第 1 行的正面词条需要配对负面词条："), issue.detail)
        assertEquals(listOf(6_005_601L), issue.effectIds)

        val unexpected = audit(2_000_002, listOf(7_040_300, 7_040_400, 7_031_900), listOf(6_820_000, -1, -1)).issues.single()
        assertEquals(RelicIssueKind.CURSE_UNEXPECTED, unexpected.kind)
        assertEquals("第 1 行的正面词条不需要负面词条，却携带负面词条：受到损伤时，会累积中毒量表（6820000）", unexpected.detail)

        val count = audit(2_000_002, listOf(7_040_300, -1, -1)).issues.single()
        assertEquals("正面词条数量不足", count.title)
        assertEquals("该遗物应有 3 条正面词条，实有 1 条", count.detail)

        // 真实存档：参数行为 CCC 无诅咒槽，但按行配对合法
        assertEquals(
            RelicAuditStatus.VALID,
            audit(2_013_212, listOf(6_005_601, 6_610_400, 6_611_002), listOf(6_850_900, 6_830_200, 6_820_000)).status,
        )
    }

    // main.swift「跨端 payload 一致性」P2
    @Test
    fun `conflict ids are listed once in order of appearance`() {
        val p2 = audit(2_000_002, listOf(6_001_400, 7_120_000, 6_001_401), listOf(7_120_100, -1, -1))
        assertEquals(listOf("conflict", "slotMismatch", "curseMissing", "curseMismatch"), kinds(p2))
        assertEquals(listOf(6_001_400L, 7_120_000L, 6_001_401L, 7_120_100L), p2.issues.first { it.kind == RelicIssueKind.CONFLICT }.effectIds)
        assertNull(p2.orderedEffects)
    }

    @Test
    fun `unknown item and unknown effect texts follow macos`() {
        val unknown = audit(424_242, listOf(7_000_000, -1, -1)).issues.single()
        assertEquals("未知遗物 ID", unknown.title)
        assertEquals("遗物 ID 424242 不在遗物数据表中，无法继续校验词条。", unknown.detail)
        val effect = audit(202, listOf(7_000_000, 99_999_999, -1)).issues.single()
        assertEquals("存在未知词条 ID", effect.title)
        assertEquals("以下词条 ID 不在词条索引中：99999999", effect.detail)
        // u32 大值不会被截断成负数而漏报
        val huge = audit(202, listOf(7_000_000, 0x80000001L, -1)).issues.single()
        assertEquals(RelicIssueKind.UNKNOWN_EFFECT, huge.kind)
        assertEquals(listOf(2_147_483_649L), huge.effectIds)
    }

    // 唯一遗物重复持有（含首件非法时豁免转移）
    @Test
    fun `unique relic duplicates exempt the first valid copy`() {
        var relics = listOf(
            relic(1040, listOf(7_040_300, 7_040_400, -1), index = 0),
            relic(1040, listOf(7_040_300, 7_040_400, -1), index = 1),
        )
        var results = auditor.applyUniqueDuplicates(relics.map { auditor.audit(it, context) }, relics)
        assertEquals(emptyList(), kinds(results[0]))
        assertEquals(listOf("uniqueDuplicate"), kinds(results[1]))
        assertEquals(RelicAuditStatus.INVALID, results[1].status)
        assertEquals("唯一遗物重复持有", results[1].issues.single().title)
        assertEquals("同一角色持有多件唯一遗物（ID 1040），仅首件合法者视为正常。", results[1].issues.single().detail)

        relics = listOf(
            relic(1040, listOf(7_040_400, 7_040_300, -1), index = 0),
            relic(1040, listOf(7_040_300, 7_040_400, -1), index = 1),
        )
        results = auditor.applyUniqueDuplicates(relics.map { auditor.audit(it, context) }, relics)
        assertEquals(listOf("wrongOrder", "uniqueDuplicate"), kinds(results[0]))
        assertEquals(emptyList(), kinds(results[1]))
    }

    // ---- testdata/audit_cases.json 对拍 ----

    @Serializable
    private data class CaseRelic(val itemId: Int, val effects: List<Long>, val curses: List<Long>)

    @Serializable
    private data class AuditCase(
        val name: String,
        val relic: CaseRelic,
        val expectStatus: String,
        val expectIssueKinds: List<String>,
        val expectWarningKinds: List<String>? = null,
        val expectOrderedEffects: List<Long>? = null,
    )

    @Serializable
    private data class UniqueCase(val name: String? = null, val relics: List<CaseRelic>, val expectKindsPerRelic: List<List<String>>)

    @Serializable
    private data class CaseFile(val cases: List<AuditCase>, val uniqueCases: List<UniqueCase> = emptyList())

    private val caseFile: CaseFile by lazy {
        CASE_JSON.decodeFromString(SaveTestData.repoFile("testdata/audit_cases.json").readText())
    }

    private companion object {
        val CASE_JSON = Json { ignoreUnknownKeys = true }
    }

    @Test
    fun `audit cases match the desktop parity file`() {
        assertTrue(caseFile.cases.size >= 14, "对拍用例应不少于 14 例")
        for (case in caseFile.cases) {
            val result = auditor.audit(SaveRelic(0, case.relic.itemId, case.relic.effects, case.relic.curses), context)
            assertEquals(case.expectStatus, result.status.raw, "${case.name}：status")
            assertEquals(case.expectIssueKinds, kinds(result), "${case.name}：issue kinds")
            assertEquals(case.expectWarningKinds.orEmpty(), result.warnings.map { it.kind.raw }, "${case.name}：warning kinds")
            case.expectOrderedEffects?.let { assertEquals(it, result.orderedEffects, "${case.name}：orderedEffects") }
            result.issues.forEach { assertTrue(it.title.isNotEmpty() && it.detail.isNotEmpty(), case.name) }
        }
    }

    @Test
    fun `unique cases match the desktop parity file`() {
        assertEquals(4, caseFile.uniqueCases.size)
        for (case in caseFile.uniqueCases) {
            val relics = case.relics.mapIndexed { index, it -> SaveRelic(index, it.itemId, it.effects, it.curses) }
            val results = auditor.applyUniqueDuplicates(relics.map { auditor.audit(it, context) }, relics)
            assertEquals(case.expectKindsPerRelic, results.map(::kinds), case.name)
            results.forEach {
                assertEquals(if (it.issues.isEmpty()) RelicAuditStatus.VALID else RelicAuditStatus.INVALID, it.status)
            }
        }
    }

    @Test
    fun `parity cases cover every issue kind`() {
        val covered = HashSet<String>()
        caseFile.cases.forEach { covered += it.expectIssueKinds; covered += it.expectWarningKinds.orEmpty() }
        caseFile.uniqueCases.forEach { case -> case.expectKindsPerRelic.forEach { covered += it } }
        RelicIssueKind.entries.forEach { assertTrue(it.raw in covered, "用例未覆盖 kind：${it.raw}") }
    }
}
