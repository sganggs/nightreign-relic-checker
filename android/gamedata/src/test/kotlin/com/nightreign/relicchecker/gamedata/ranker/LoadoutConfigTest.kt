package com.nightreign.relicchecker.gamedata.ranker

import com.nightreign.relicchecker.gamedata.ranker.RankerTestData.assertClose
import com.nightreign.relicchecker.rules.CheckMode
import com.nightreign.relicchecker.rules.CheckStatus
import com.nightreign.relicchecker.rules.LegalityChecker
import com.nightreign.relicchecker.rules.foldedForSearch
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonPrimitive
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

// 「自己组一套配置」的整套口径（真实数据）：windows/tests/ranker_config.test.mjs 的每个 test 在这里都有同名对应
// （反引号里的测试名就是那边的需求清单），外加 macOS 端 BuffRankerChecks.checkLoadoutRealData 的固定事实。
// 数值会随数据集修订变化，这里一律按「数据里的字段」现算期望值，只有桌面端写死过的几个倍率（封印监牢 ×1.4072 等）照抄。
class LoadoutConfigTest {
    private val index get() = RankerTestData.loadout
    private val ranker get() = RankerTestData.buffs
    private val dataset get() = RankerTestData.buffs.dataset
    private val skills get() = RankerTestData.skills
    private val rules: BuffSlotRules get() = dataset.slotRules!!

    private val corpse get() = Outputs.corpse
    private val lion get() = Outputs.lion
    private val comet get() = Outputs.comet
    private val lightning get() = Outputs.lightning

    /** 各测试共用（判定按输出手段缓存，推荐填满只跑一次）。 */
    private object Outputs {
        val corpse: RankerOutput by lazy { RankerTestData.output(OutputClass.SKILL, 1177, 9040000) }       // 尸横遍野 + 尸山血海（刀）
        val lion: RankerOutput by lazy { RankerTestData.output(OutputClass.SKILL, 100, 3180000) }          // 狮子斩 + 大剑
        val comet: RankerOutput by lazy { RankerTestData.output(OutputClass.SORCERY, 4021) }               // 帚星
        val lightning: RankerOutput by lazy { RankerTestData.output(OutputClass.INCANTATION, 5040) }       // 死亡雷击
        val mohg: RankerOutput by lazy {
            val skill = RankerTestData.skills.dataset.skills.first { it.nameZh == "授血仪式" }
            val weapon = RankerTestData.skills.dataset.weapons.first { it.nameZh == "蒙格温圣矛" }
            RankerTestData.output(OutputClass.SKILL, skill.id, weapon.id)
        }

        private val evaluators = HashMap<RankerOutput, LoadoutEvaluator>()

        @Synchronized
        fun evaluator(output: RankerOutput): LoadoutEvaluator =
            evaluators.getOrPut(output) { RankerTestData.loadout.evaluator(output) }

        /** 四种输出 × 常规 / 深夜 × 按类别过滤 / 全部类别 的推荐填满。 */
        val fills: List<Triple<String, RankerOutput, Pair<Int?, FillResult>>> by lazy {
            val list = ArrayList<Triple<String, RankerOutput, Pair<Int?, FillResult>>>()
            for (output in listOf(corpse, lion, comet, lightning)) {
                for (mode in RunMode.entries) {
                    for (filter in listOf(output.attackWepType, null)) {
                        val label = "${output.outputClass.key}/${output.meansId}/${mode.key}/$filter"
                        list += Triple(label, output, filter to evaluator(output).recommendFill(LoadoutConfig(runMode = mode), filter))
                    }
                }
            }
            list
        }
    }

    private fun ev(output: RankerOutput): LoadoutEvaluator = Outputs.evaluator(output)

    private fun evaluate(output: RankerOutput, config: LoadoutConfig): LoadoutEvaluation = ev(output).evaluate(config)

    private fun withAffixes(ids: List<Int>, mode: RunMode = RunMode.NORMAL): LoadoutConfig {
        var config = LoadoutConfig(runMode = mode)
        ids.forEach { config = index.stepWeaponAffix(config, it, 1) }
        return config
    }

    private fun custom(affixIds: List<Int?>, curseIds: List<Int?> = emptyList()): RelicCard = RelicCard.custom(affixIds, curseIds)

    private fun check(card: RelicCard, kind: RelicKind): RelicCheck = index.checkCustomRelic(card, kind)

    private fun entry(id: Int): BuffRankerEntry = ranker.byId.getValue(id)

    private fun verdict(id: Int, output: RankerOutput): VerdictState = ev(output).verdict(entry(id)).state

    // ------------------------------------------------------------------ 武器词条槽位

    @Test
    fun `常规：武器词条总数不超过 slotRules_weaponAffix_maxAffixesNormal，满了步进就停`() {
        val normalIds = index.weaponAffixes.filter { it.isAvailable(RunMode.NORMAL) }.map { it.id }
        assertTrue(normalIds.size > rules.weaponAffix.maxAffixesNormal)
        var config = LoadoutConfig()
        normalIds.forEach { config = index.stepWeaponAffix(config, it, 1) }
        val usage = index.weaponAffixUsage(config)
        assertEquals(rules.weaponAffix.maxAffixesNormal, usage.used)
        assertEquals(rules.weaponAffix.maxAffixesNormal, usage.cap)
        assertEquals(6, usage.cap)
        val blocked = index.canAddWeaponAffix(config, normalIds.last())
        assertFalse(blocked.ok)
        assertEquals(RankerText.t("waCapReached"), blocked.reason)
        assertEquals(config, index.stepWeaponAffix(config, normalIds.last(), 1), "满了步进就停（原样返回）")
        // 同一条词条也能叠数量（只是同键只计一份），减到 0 就从配置里移除。
        var one = index.stepWeaponAffix(LoadoutConfig(), normalIds[0], 1)
        one = index.stepWeaponAffix(one, normalIds[0], 1)
        assertEquals(2, one.weaponAffixCount(normalIds[0]))
        one = index.stepWeaponAffix(index.stepWeaponAffix(one, normalIds[0], -1), normalIds[0], -1)
        assertTrue(one.weaponAffixes.isEmpty())
    }

    @Test
    fun `常规：深夜专属词条不可用；深夜：总数 ≤ maxAffixesDeep，深夜专属正面词条 ≤ maxDeepOnlyAffixes`() {
        val deepOnly = index.weaponAffixes.filter { it.deepOnlyPositive }
        assertTrue(deepOnly.isNotEmpty())
        deepOnly.forEach {
            assertFalse(it.isAvailable(RunMode.NORMAL), "${it.id} 常规模式不该出现")
            assertTrue(it.isAvailable(RunMode.DEEP))
        }
        val normalBlocked = index.canAddWeaponAffix(LoadoutConfig(), deepOnly[0].id)
        assertFalse(normalBlocked.ok)
        assertEquals(RankerText.t("waNotInMode"), normalBlocked.reason)

        var config = LoadoutConfig(runMode = RunMode.DEEP)
        repeat(3) { deepOnly.forEach { config = index.stepWeaponAffix(config, it.id, 1) } }
        val usage = index.weaponAffixUsage(config)
        assertEquals(rules.weaponAffix.maxDeepOnlyAffixes, usage.deepOnlyUsed, "深夜专属按 weaponAffixDeepOnlyPositive 计数、到上限为止")
        assertEquals(rules.weaponAffix.maxDeepOnlyAffixes, usage.deepOnlyCap)
        assertEquals(6, usage.deepOnlyCap)
        assertEquals(RankerText.t("waDeepOnlyCapReached"), index.canAddWeaponAffix(config, deepOnly[0].id).reason)
        // 深夜专属满了仍可加普通词条，直到总上限。
        index.weaponAffixes.filter { !it.deepOnlyPositive }.forEach { config = index.stepWeaponAffix(config, it.id, 1) }
        val full = index.weaponAffixUsage(config)
        assertEquals(rules.weaponAffix.maxAffixesDeep, full.used)
        assertEquals(12, full.cap)
        assertTrue(full.deepOnlyUsed <= full.deepOnlyCap)
        assertEquals(emptyList<String>(), evaluate(corpse, config).violations, "推到上限为止，不会超限")
    }

    @Test
    fun `诅咒不进正面词条栏，也不计入深夜专属上限（deepOnlyCapCountsCurses=false）`() {
        assertFalse(rules.weaponAffix.deepOnlyCapCountsCurses)
        val curses = dataset.weaponAffixes.filter { "curse" in it.roles }
        assertTrue(curses.isNotEmpty())
        curses.forEach { assertNull(index.weaponAffixById[it.attachEffectId], "${it.attachEffectId} 是诅咒") }
        dataset.weaponAffixes.filter { it.isDebuff }.forEach { assertNull(index.weaponAffixById[it.attachEffectId]) }
    }

    @Test
    fun `深夜切回常规：去掉深夜专属，再按 AttachEffect id 从大到小削到常规上限，深夜遗物格清空`() {
        var config = LoadoutConfig(runMode = RunMode.DEEP)
        val deepOnly = index.weaponAffixes.filter { it.deepOnlyPositive }.take(2)
        val normal = index.weaponAffixes.filter { it.isAvailable(RunMode.NORMAL) }.take(9)
        (deepOnly + normal).forEach { config = index.stepWeaponAffix(config, it.id, 1) }
        config = config.withRelic(0, custom(listOf(7001402))).withRelic(3, custom(listOf(7001402)))
        assertEquals(11, index.weaponAffixUsage(config).used)
        val back = index.applyRunMode(config, RunMode.NORMAL)
        val usage = index.weaponAffixUsage(back)
        assertEquals(RunMode.NORMAL, back.runMode)
        assertEquals(rules.weaponAffix.maxAffixesNormal, usage.used)
        assertEquals(0, usage.deepOnlyUsed)
        assertEquals(normal.map { it.id }.sorted().take(usage.cap), back.weaponAffixes.keys.sorted(), "保留 id 小的")
        assertEquals(11 - usage.cap, index.trimmedCount(config, back))
        assertEquals(11, index.weaponAffixUsage(config).used, "不改原配置")
        assertEquals(RelicCard.EMPTY, back.relic(3), "深夜遗物格清空")
        assertEquals(config.relic(0), back.relic(0), "普通遗物格保留")
        assertEquals("切到常规：已去掉 5 条深夜专属／超出常规上限的武器词条，深夜遗物格已清空", RankerText.f("modeTrimmed", 11 - usage.cap))
        // 同一组（macOS setMode）：深夜 13 条超限 → 两条超限提示；切回常规去掉 7 条。
        var over = LoadoutConfig(runMode = RunMode.DEEP, weaponAffixes = mapOf(deepOnly[0].id to 7, normal[0].id to 6))
        val overEval = evaluate(corpse, over)
        assertTrue(overEval.slots.weaponAffix.isOver && overEval.slots.weaponAffix.isDeepOnlyOver)
        assertEquals(2, overEval.violations.size, overEval.violations.toString())
        over = index.applyRunMode(over, RunMode.NORMAL)
        assertEquals(mapOf(normal[0].id to 6), over.weaponAffixes)
        // 常规模式里程序化塞进深夜专属：超限提示用常规的写法。
        val sneaky = evaluate(corpse, LoadoutConfig(weaponAffixes = mapOf(deepOnly[0].id to 1)))
        assertEquals(listOf(RankerText.f("violationDeepOnlyInNormal", 1)), sneaky.violations)
    }

    @Test
    fun `武器类别过滤：默认按当前武器的 wepType（常规看 normalWepTypes、深夜看 deepWepTypes），已选的始终显示`() {
        val katana = corpse.weaponWepType!!
        val rows = ev(corpse).weaponAffixRows(LoadoutConfig(), katana)
        assertTrue(rows.isNotEmpty())
        rows.forEach { assertTrue(katana in it.affix.normalWepTypes, "${it.affix.id} 不能出现在刀上") }
        val all = ev(corpse).weaponAffixRows(LoadoutConfig(), null)
        assertTrue(all.size >= rows.size)
        val foreign = index.weaponAffixes.first { it.isAvailable(RunMode.NORMAL) && katana !in it.normalWepTypes }
        val picked = ev(corpse).weaponAffixRows(withAffixes(listOf(foreign.id)), katana)
        assertTrue(picked.any { it.affix.id == foreign.id && it.count == 1 && it.outsideFilter }, "已选的不被类别过滤藏起来")
        // 行按有效倍率降序。
        rows.zipWithNext().forEach { (a, b) -> if (a.score.applicable == b.score.applicable) assertTrue(a.score.score >= b.score.score - 1e-9) }
        // 深夜看 deepWepTypes。
        val deepRows = ev(corpse).weaponAffixRows(LoadoutConfig(runMode = RunMode.DEEP), katana)
        deepRows.forEach { assertTrue(katana in it.affix.deepWepTypes) }
        assertTrue(deepRows.size >= rows.size)
    }

    @Test
    fun `武器类别过滤：按 normalWepTypes ／ deepWepTypes 过滤与按 scope_rollableWeaponTypes 过滤结果一致`() {
        // DTO 不声明 scope.rollableWeaponTypes（运行时用不到），这里直接读原始 JSON 对照。
        val raw = RankerTestData.readText(com.nightreign.relicchecker.gamedata.GameDataKey.BUFFS.fileName)
        val root = com.nightreign.relicchecker.gamedata.GameDataJson.lenient.parseToJsonElement(raw) as JsonObject
        val rollable = HashMap<Int, List<Int>>()
        (root["buffs"] as JsonArray).forEach { element ->
            val buff = element as JsonObject
            val scope = buff["scope"] as? JsonObject ?: return@forEach
            val types = scope["rollableWeaponTypes"] as? JsonArray ?: return@forEach
            rollable[buff["spEffectId"]!!.jsonPrimitive.int] = types.map { it.jsonPrimitive.int }
        }
        index.weaponAffixes.forEach { affix ->
            val fromScope = affix.entries.flatMap { rollable[it.id].orEmpty() }.toSortedSet()
            val union = (affix.normalWepTypes + affix.deepWepTypes).toSortedSet()
            assertEquals(fromScope.toList(), union.toList(), "${affix.id} 的可出现类别")
            if (affix.isAvailable(RunMode.NORMAL)) {
                assertEquals(union.toList(), affix.normalWepTypes.sorted(), "${affix.id} 常规可出的词条，常规与深夜的类别应当相同")
            }
        }
    }

    // ------------------------------------------------------------------ exclusiveKey 去重

    @Test
    fun `同一词条放两份：stackSelf（按 ID 互斥）的各份相乘并提示「参数推断」，照样占两个槽位`() {
        val skillAttack = assertNotNull(index.weaponAffixById[8350002], "提升战技攻击力（档位3）")
        val own = skillAttack.entries[0]
        assertTrue(own.copiesMultiply, "spCategory 10 stackSelf、exclusiveScope=perSpEffect")
        val single = evaluate(corpse, withAffixes(listOf(8350002)))
        val twice = evaluate(corpse, withAffixes(listOf(8350002, 8350002)))
        val item = twice.counted.first { it.id == own.id }
        assertEquals(2, item.copies)
        assertEquals(2, item.countedCopies)
        val one = single.counted.first { it.id == own.id }
        DamageType.entries.forEach { assertClose(Math.pow(one.table[it.ordinal], 2.0), item.table[it.ordinal], 1e-9, "${it.key} 两份相乘") }
        assertTrue(twice.totalMultiplier!! > single.totalMultiplier!!)
        assertEquals(0, twice.items.count { it.state == EntryState.DUPLICATE }, "同一 spEffectId 合并成一条，不是互斥键去重")
        assertTrue(twice.warnings.any { it.kind == "copiesStackSelf" && it.text.contains("未实测") })
        assertEquals(2, index.weaponAffixUsage(withAffixes(listOf(8350002, 8350002))).used, "多份照样占槽位")
        assertEquals(listOf("提升战技攻击力（档位3） ×2"), twice.items.first { it.id == own.id }.labels)
        // 多档词条（exclusiveScope=affixVariant）同一词条装两件只算一份（notes.affixVariant），即使 spCategory 是 10。
        assertEquals("stackSelf", entry(7120001).behavior)
        assertFalse(entry(7120001).copiesMultiply)
    }

    @Test
    fun `不同档位（档位1／2／3）是不同互斥键：各自计入相乘，并标注「参数推断，未实测」`() {
        val result = evaluate(corpse, withAffixes(listOf(8350000, 8350001, 8350002)))
        assertEquals(3, result.counted.size)
        val product = result.counted.fold(1.0) { acc, item -> acc * item.multiplier!! }
        assertClose(product, result.totalMultiplier, 1e-9, "都是全属性同倍率时总倍率等于三条连乘")
        assertTrue(result.warnings.any { it.kind == "tiers" && it.text.contains("未实测") })
        assertEquals(listOf(listOf(8350000, 8350001, 8350002)), index.selectedTierFamilies(withAffixes(listOf(8350000, 8350001, 8350002))))
    }

    @Test
    fun `跨栏同键：不同物品的累积阶梯共用 sp120 时只留倍率高的那份`() {
        // 累积阶梯的各档（米莉森的义手、带翼剑徽章、连续攻击遗物…）共用 sp120。
        val config = LoadoutConfig(accessories = listOf(1250, 2080))
            .withLadderTier(312505, index.ladderTopTier(312505)!!.id)
            .withLadderTier(320804, index.ladderTopTier(320804)!!.id)
        val result = evaluate(corpse, config)
        val counted = result.counted.filter { it.entry.key == "sp120" }
        assertEquals(1, counted.size, "两个护符的累积阶梯同键，只计一份")
        val dup = result.items.filter { it.entry.key == "sp120" && it.state == EntryState.DUPLICATE }
        assertEquals(1, dup.size)
        assertTrue(counted[0].multiplier!! >= dup[0].multiplier!!)
        assertTrue(result.warnings.any { it.kind == "duplicate" && it.text.contains("sp120") })
        assertEquals(counted[0], result.duplicateWinner(dup[0]))
        assertTrue(dup[0].reasons.single().contains("sp120"))
    }

    // ------------------------------------------------------------------ 遗物合法性

    @Test
    fun `自组普通遗物：一组合法示例走 LegalityChecker（currentNormal），文案取本页常量表`() {
        val ids = listOf(7001402, 7260400, 7120100)
        val result = check(custom(ids), RelicKind.NORMAL)
        val checker = LegalityChecker()
        val direct = checker.check(checker.canonicalOrder(ids.map { id -> RankerTestData.catalog.affixes.first { it.effectId == id } }), CheckMode.CURRENT_NORMAL)
        assertEquals(CheckStatus.VALID, direct.status)
        assertEquals(RelicCheckStatus.VALID, result.status)
        assertEquals(RankerText.t("relicValidNormal"), result.message, "三端同一句（不直接用 LegalityChecker 的 message）")
        assertTrue(result.issues.isEmpty())
        // macOS 端的合法 / 非法示例。
        val legal = check(custom(listOf(7001400, 7044100, 7032700)), RelicKind.NORMAL)
        assertEquals(RelicCheckStatus.VALID, legal.status, legal.issues.toString())
        val illegal = check(custom(listOf(7001400, 7001600, 7044100)), RelicKind.NORMAL)
        assertTrue(illegal.isInvalid && illegal.issues.any { it.kind == "conflict" }, "提升物理攻击力 + 提升火属性攻击力（同一互斥池 100）")
    }

    @Test
    fun `自组普通遗物：一组非法示例（同一互斥池）沿用 LegalityChecker 的问题文案，整件不计入`() {
        val card = custom(listOf(7001400, 7001600))
        val result = check(card, RelicKind.NORMAL)
        assertEquals(RelicCheckStatus.INVALID, result.status)
        val conflict = assertNotNull(result.issues.firstOrNull { it.kind == "conflict" }, "应当报互斥")
        assertEquals("同一互斥池", conflict.title)
        assertTrue(conflict.detail.contains("提升物理攻击力") && conflict.detail.contains("不能同时出现"), conflict.detail)
        assertTrue(conflict.effectIds.all { it > 0 })
        val evaluation = evaluate(corpse, LoadoutConfig().withRelic(0, card))
        val relicItems = evaluation.items.filter { it.column == SummaryColumn.RELIC }
        assertTrue(relicItems.isNotEmpty())
        relicItems.forEach { assertEquals(EntryState.RELIC_INVALID, it.state) }
        relicItems.forEach { assertEquals(listOf(RankerText.t("reasonRelicInvalid")), it.reasons) }
        assertEquals(0, evaluation.column(SummaryColumn.RELIC).count)
        assertEquals(listOf(RankerText.f("violationRelic", "普通遗物 1", RankerText.t("relicInvalid"))), evaluation.violations)
    }

    @Test
    fun `自组遗物：不足三条时用占位词条补足预检；词条重复与不在出货池同样按 LegalityChecker 报错`() {
        val partial = check(custom(listOf(7001402)), RelicKind.NORMAL)
        assertEquals(RelicCheckStatus.PARTIAL, partial.status)
        assertEquals(RankerText.f("relicPartial", 1, 2), partial.message)
        val dup = check(custom(listOf(7001402, 7001402)), RelicKind.NORMAL)
        assertEquals(RelicCheckStatus.INVALID, dup.status)
        assertTrue(dup.issues.any { it.kind == "duplicate" && it.title == "词条重复" })
        val fixedOnly = check(custom(listOf(7006700)), RelicKind.NORMAL)
        assertEquals(RelicCheckStatus.INVALID, fixedOnly.status, "只出现在固定遗物上的词条不能自组")
        assertTrue(fixedOnly.issues.any { it.kind == "unavailable" })
        assertTrue(fixedOnly.issues.all { issue -> issue.effectIds.all { it > 0 } }, "占位词条不出现在问题的词条 ID 里")
        assertFalse(fixedOnly.issues.any { it.detail.contains(RankerText.t("relicPlaceholderAffix")) })
        val unknown = check(custom(listOf(123456789)), RelicKind.NORMAL)
        assertEquals(RelicCheckStatus.INVALID, unknown.status)
        assertEquals(RankerText.t("relicUnknownEffectTitle"), unknown.issues[0].title)
        assertEquals(RelicCheckStatus.EMPTY, index.relicCheck(RelicCard.EMPTY, RelicKind.NORMAL).status)
        assertEquals(RelicCheckStatus.EMPTY, check(custom(emptyList()), RelicKind.NORMAL).status)
        // 普通遗物格没有诅咒槽：带诅咒是多余的负面词条。
        val curse = index.catalog.curses.first()
        assertTrue(check(custom(listOf(7001402), listOf(curse.effectId)), RelicKind.NORMAL).issues.any { it.kind == "curseUnexpected" })
        // 没有词条库时自组遗物不可用。
        val bare = LoadoutIndex(ranker)
        assertEquals(RankerText.t("relicNoCatalog"), bare.checkCustomRelic(custom(listOf(7001402)), RelicKind.NORMAL).message)
        assertTrue(bare.relicCandidates.values.all { it.isEmpty() })
        assertTrue(LoadoutText.briefNotes(bare).any { it.contains(RankerText.t("noData")) })
    }

    @Test
    fun `自组深夜遗物：requiresCurse 的词条必须配诅咒；诅咒不计增伤但要占位；文案与深夜遗物审计同文`() {
        val deep = index.relicCandidates.getValue(RelicKind.DEEP)
        val needsCurse = deep.first { it.affix.requiresCurse }
        val free = deep.first { !it.affix.requiresCurse && it.affix.compatibilityId != needsCurse.affix.compatibilityId }
        val missing = check(custom(listOf(needsCurse.id)), RelicKind.DEEP)
        assertEquals(RelicCheckStatus.INVALID, missing.status)
        val issue = missing.issues.first { it.kind == "curseMissing" }
        assertEquals("需诅咒的词条缺少负面词条", issue.title)
        assertEquals("第 1 行的正面词条需要配对负面词条：" + needsCurse.affix.name, issue.detail)
        // 与存档检查的深夜遗物审计（core.js auditDeepRelic）同一句逐字相同。
        assertEquals("多余的负面词条", RankerText.t("curseUnexpectedTitle"))
        assertEquals("第 {0} 行的正面词条不需要负面词条，却携带负面词条：{1}", RankerText.t("curseUnexpectedDetail"))
        assertEquals("负面词条不在诅咒池", RankerText.t("curseMismatchTitle"))
        assertEquals("第 {0} 行的负面词条不在诅咒池：{1}", RankerText.t("curseMismatchDetail"))

        val assigned = index.autoAssignCurses(custom(listOf(needsCurse.id, free.id)), RelicKind.DEEP)
        assertEquals(index.catalog.curses[0].effectId, assigned.curseAt(0), "自动配上 effectId 最小的合法诅咒")
        assertNull(assigned.curseAt(1), "不需诅咒的那行不配")
        assertEquals(assigned.curseAt(0), index.pickCurse(custom(listOf(needsCurse.id)), 0))
        val ok = check(assigned, RelicKind.DEEP)
        assertEquals(RelicCheckStatus.PARTIAL, ok.status)
        assertEquals(1, ok.warnings.size, "LegalityChecker 的「深夜模式仅作预检」在本页做完配对后不再照抄")
        assertEquals(RankerText.t("cursePairingTitle"), ok.warnings[0].title)
        assertTrue(ok.warnings[0].detail.contains(index.catalog.cursePoolId.toString()))
        assertEquals(0, missing.warnings.size, "配对没过时不说已校验")

        val curseId = assigned.curseAt(0)!!
        val extra = check(custom(listOf(free.id), listOf(curseId)), RelicKind.DEEP)
        assertTrue(extra.issues.any { it.kind == "curseUnexpected" && it.title == "多余的负面词条" })
        val notCurse = check(custom(listOf(needsCurse.id), listOf(free.id)), RelicKind.DEEP)
        assertTrue(notCurse.issues.any { it.kind == "curseMismatch" }, "正面词条当诅咒用要报「不在诅咒池」")
        // 只有诅咒、没有正面词条的行：也是多余的负面词条（与存档审计同一口径）。
        val orphan = check(custom(listOf(null), listOf(curseId)), RelicKind.DEEP)
        assertEquals(RelicCheckStatus.INVALID, orphan.status)
        assertTrue(orphan.issues.any { it.kind == "curseUnexpected" })
        // 两行配同一条诅咒：词条重复（与存档审计同文）。
        val other = deep.firstOrNull {
            it.affix.requiresCurse && it.affix.compatibilityId != needsCurse.affix.compatibilityId && it.id != needsCurse.id
        }
        if (other != null) {
            val dupCheck = check(custom(listOf(needsCurse.id, other.id), listOf(curseId, curseId)), RelicKind.DEEP)
            assertTrue(dupCheck.issues.any { it.title == RankerText.t("curseDuplicateTitle") && it.detail.startsWith("同一词条在一件遗物上重复出现") })
        }

        // 诅咒本身不计增伤：配置里只算正面词条的条目。
        val config = LoadoutConfig(runMode = RunMode.DEEP).withRelic(3, assigned)
        val result = evaluate(lightning, config)
        val relicIds = result.items.filter { it.column == SummaryColumn.RELIC }.map { it.id }.toSet()
        index.relicAffixEntries[curseId].orEmpty().forEach { assertFalse(it.id in relicIds, "诅咒的效果不进增伤") }
        // macOS 端的深夜示例：需诅咒的没配 → 非法；三条 + 诅咒 → 合法并写明诅咒配对已校验。
        val deepNoCurse = check(custom(listOf(6001700)), RelicKind.DEEP)
        assertTrue(deepNoCurse.isInvalid && deepNoCurse.issues.any { it.title == RankerText.t("curseMissingTitle") })
        val deepLegal = check(custom(listOf(6001700, 7044100, 7030600), listOf(6820000)), RelicKind.DEEP)
        assertEquals(RelicCheckStatus.VALID, deepLegal.status, deepLegal.issues.toString())
        assertEquals(listOf("cursePairing"), deepLegal.warnings.map { it.kind })
        assertEquals(RankerText.t("relicValidDeep"), deepLegal.message)
    }

    @Test
    fun `深夜遗物格只在深夜模式计入；普通格用普通口径、深夜格用深夜口径`() {
        val config = LoadoutConfig().withRelic(3, custom(listOf(7001402)))
        val normal = evaluate(corpse, config)
        assertEquals(rules.modes.normal.relicSlots, normal.caps.relics)
        assertEquals(3, normal.relicChecks.size)
        assertEquals(0, normal.items.count { it.column == SummaryColumn.RELIC }, "常规模式没有第 4 格")
        assertEquals(0, normal.slots.relic.used)
        val deep = evaluate(corpse, config.copy(runMode = RunMode.DEEP))
        assertEquals(rules.modes.deep.relicSlots, deep.caps.relics)
        assertEquals(RelicKind.DEEP, deep.caps.relicKind(3))
        assertEquals(RelicKind.NORMAL, deep.caps.relicKind(2))
        assertNotEquals(RelicCheckStatus.EMPTY, deep.relicChecks[3].status)
        assertEquals("深夜遗物 1", deep.caps.relicCardLabel(3))
        assertEquals("普通遗物 3", deep.caps.relicCardLabel(2))
        // 7001402（＋２）同时在普通池与深夜 B／C 池：深夜格按深夜正面口径预检通过，深夜模式下计入。
        assertEquals(RelicCheckStatus.PARTIAL, deep.relicChecks[3].status)
        assertTrue(deep.itemsFrom("relic:3").any { it.state == EntryState.COUNTED })
        // 7001400 只在普通池：普通格预检通过，深夜格报「不在当前出货池」、整件不计入。
        assertEquals(RelicCheckStatus.PARTIAL, check(custom(listOf(7001400)), RelicKind.NORMAL).status)
        val deepOnlyNormal = evaluate(corpse, LoadoutConfig(runMode = RunMode.DEEP).withRelic(3, custom(listOf(7001400))))
        assertEquals(RelicCheckStatus.INVALID, deepOnlyNormal.relicChecks[3].status)
        assertEquals(RankerText.t("checkPoolTitle"), deepOnlyNormal.relicChecks[3].issues.single().title)
        assertTrue(deepOnlyNormal.itemsFrom("relic:3").all { it.state == EntryState.RELIC_INVALID })
    }

    @Test
    fun `固定遗物：整件的词条按 spEffectIds 计入；条件型默认未确认，勾选「条件成立」后计入`() {
        val relic = assertNotNull(index.fixedRelicByKey["2070"], "安定者的遗志（提升近战攻击力 + 提升战技攻击力）")
        val result = evaluate(corpse, LoadoutConfig().withRelic(0, RelicCard.fixed("2070")))
        val ids = result.counted.filter { it.column == SummaryColumn.RELIC }.map { it.id }.sorted()
        assertEquals(relic.entries.filter { it.countsAsDamage }.map { it.id }.sorted(), ids)
        assertEquals(RelicCheckStatus.FIXED, result.relicChecks[0].status)

        val conditionalRelic = index.fixedRelics.first { one ->
            one.entries.any { it.countsAsDamage && it.activation != "passive" && it.stackInput == null && it.buff.appliesTo?.skill == "yes" }
        }
        val target = conditionalRelic.entries.first {
            it.countsAsDamage && it.activation != "passive" && it.stackInput == null && it.buff.appliesTo?.skill == "yes"
        }
        val config = LoadoutConfig().withRelic(0, RelicCard.fixed(conditionalRelic.key))
        assertEquals(EntryState.PENDING, evaluate(corpse, config).items.first { it.id == target.id }.state)
        val after = evaluate(corpse, config.withTick(target.id, true)).items.first { it.id == target.id }
        assertTrue(after.state == EntryState.COUNTED || after.state == EntryState.DUPLICATE, after.state.key)
        assertTrue(after.ticked)
        // 固定遗物的逐条词条：计入的标出来，缺中文名退「词条 #id」。
        assertTrue(relic.effectLines.any { it.counted })
        index.fixedRelics.forEach { one -> one.effectLines.forEach { assertTrue(it.text.isNotEmpty()) } }
    }

    // ------------------------------------------------------------------ appliesTo 分流

    @Test
    fun `appliesTo 分流：魔法／祷告排除「提升战技攻击力」类（112），战技照样吃`() {
        listOf(8350000, 8350001, 8350002, 7006700, 312300).forEach { id ->
            assertEquals(VerdictState.NO, verdict(id, comet), "$id 对魔法不生效")
            assertEquals(VerdictState.NO, verdict(id, lightning), "$id 对祷告不生效")
            assertEquals(VerdictState.YES, verdict(id, corpse), "$id 对尸横遍野（全段带 112）生效")
        }
    }

    @Test
    fun `appliesTo 分流：数据判 magParamChange=0 的条目对魔法一律不生效，wepParamChange=3 的对战技不生效`() {
        var magZero = 0
        ranker.entries.forEach { entry ->
            val reason = entry.buff.appliesToDetail.sorcery?.reason.orEmpty()
            if (!reason.startsWith("magParamChange=0")) return@forEach
            magZero += 1
            assertEquals(VerdictState.NO, ev(comet).verdict(entry).state, "${entry.id} magParamChange=0 却对魔法生效")
        }
        assertTrue(magZero > 0)
        assertEquals(VerdictState.NO, verdict(8330000, corpse), "强化魔法（武器词条）对战技不生效")
        assertEquals(VerdictState.YES, verdict(8330000, comet))
    }

    @Test
    fun `appliesTo 分流：战技的子类别限定按 attackIndex 对所选战技判定（咆哮类没有 112 段就不吃）`() {
        val skillsIndex = dataset.attackIndex.skills
        val roarId = skillsIndex.entries.first { (_, sets) -> sets.all { 112 !in it.subs && 111 !in it.subs } }.key
        val roar = RankerOutput(OutputClass.SKILL, meansId = roarId, shares = corpse.shares)
        assertEquals(VerdictState.NO, ranker.verdict(entry(8350000), roar).state)
        val partialId = skillsIndex.entries.first { (_, sets) ->
            sets.any { 112 in it.subs } && sets.any { 112 !in it.subs && 111 !in it.subs }
        }.key
        val partial = ranker.verdict(entry(8350000), RankerOutput(OutputClass.SKILL, meansId = partialId, shares = corpse.shares))
        assertEquals(VerdictState.YES, partial.state)
        assertTrue(partial.weight > 0 && partial.weight < 1, "部分段命中按段数加权")
    }

    @Test
    fun `appliesTo 分流：持武器的手、出手武器类别、攻击情境各走各的判定`() {
        assertEquals(VerdictState.YES, verdict(8980002, corpse), "提升魔力属性攻击力（右手武器・武器固有）")
        assertEquals(VerdictState.NO, verdict(8980002, RankerTestData.output(OutputClass.SKILL, 1177, 9040000, hand = 2)))
        assertEquals(VerdictState.NO, verdict(8160000, corpse), "刀不是短剑")
        // 短剑 + 它能带的任一战技（skills v3：固定或局内战技池，动作套读 skillVariants[战技 ID]）。
        fun daggerPlayable(skill: SkillEntry, weapon: SkillWeapon?): Boolean =
            weapon != null && weapon.wepType == 1 && weapon.variantIndex(skill.id) != null && skills.hits(skill, weapon).any { !it.noDamage }
        val daggerSkill = skills.dataset.skills.first { skill -> skill.weaponIds.any { daggerPlayable(skill, skills.weaponsById[it]) } }
        val daggerWeapon = daggerSkill.weaponIds.mapNotNull { skills.weaponsById[it] }.first { daggerPlayable(daggerSkill, it) }
        assertEquals(VerdictState.YES, verdict(8160000, RankerTestData.output(OutputClass.SKILL, daggerSkill.id, daggerWeapon.id)))
        assertEquals(VerdictState.CONTEXT, verdict(320600, corpse), "矛护符：强化突刺反击")
        assertEquals(
            VerdictState.YES,
            verdict(320600, RankerTestData.output(OutputClass.SKILL, 1177, 9040000, contexts = setOf("thrustingCounter"))),
        )
        assertTrue(ev(corpse).attackContextOptions().any { it.key == "thrustingCounter" })
    }

    @Test
    fun `配置里所有计入的条目：appliesTo 对当前输出类别不是 no`() {
        for ((label, output, fill) in Outputs.fills) {
            ev(output).evaluate(fill.second.config).counted.forEach { item ->
                assertNotEquals("no", item.entry.buff.appliesTo?.get(output.outputClass), "$label：${item.id} 不生效却计入了")
            }
        }
    }

    // ------------------------------------------------------------------ 叠层输入

    @Test
    fun `叠层：封印监牢（ladder）按层数取 tierMultipliers，赐福王的余威（copies）按份数取乘方`() {
        val evergaol = entry(7069001)
        val grace = entry(8970000)
        val config = LoadoutConfig(others = setOf(8970000), stackCounts = mapOf(8970000 to 4))
        val graceItem = evaluate(corpse, config).items.first { it.id == 8970000 }
        assertEquals(EntryState.COUNTED, graceItem.state, "填了层数就等于条件成立")
        assertClose(Math.pow(grace.stackInput!!.perStackMultiplier!!, 4.0), graceItem.table[DamageType.FIRE.ordinal], 1e-9, "4 份")

        val stacked = LoadoutConfig(stackCounts = mapOf(7069001 to 5))
        val ladderItem = ev(corpse).evaluateEntry(evergaol, stacked)
        assertClose(evergaol.stackInput!!.tierMultipliers[4], ladderItem.table[DamageType.SLASH.ordinal], 1e-9, "第 5 层")
        assertEquals(EntryState.ZERO_STACKS, ev(corpse).evaluateEntry(evergaol, LoadoutConfig(stackCounts = mapOf(7069001 to 0))).state)
    }

    @Test
    fun `叠层：赐福王的余威手填份数，每份 ×1_02、N 份按 1_02^N 相乘（参数表无上限，份数按 99 截断）`() {
        val grace = entry(8970000)
        val input = grace.stackInput!!
        assertEquals("copies", input.mode)
        assertEquals(1.02, input.perStackMultiplier)
        assertNull(input.practicalMaxStacks)
        assertEquals(BuffStackInput.COPIES_CEILING, input.paramMax)
        assertEquals(1, input.defaultStacks, "没有实测上限：勾选时先填 1 份")
        assertTrue(LoadoutText.isGraceStack(grace), "层数按本局新发现的赐福数计")
        assertTrue(LoadoutText.stackHints(grace).contains(RankerText.t("stackHintGrace")))
        assertEquals(RankerText.t("stackLabelCopies"), LoadoutText.stackLabel(grace))
        for (n in listOf(1, 3, 5, 20)) {
            val result = evaluate(corpse, LoadoutConfig(others = setOf(8970000), stackCounts = mapOf(8970000 to n)))
            assertClose(Math.pow(1.02, n.toDouble()), result.totalMultiplier, 1e-9, "赐福王的余威 $n 份")
        }
        // 份数填 0 不计入；填超过 99 按 99 算并提示。
        val zero = evaluate(corpse, LoadoutConfig(others = setOf(8970000), stackCounts = mapOf(8970000 to 0)))
        assertEquals(EntryState.ZERO_STACKS, zero.items.first { it.id == 8970000 }.state)
        val huge = evaluate(corpse, LoadoutConfig(others = setOf(8970000), stackCounts = mapOf(8970000 to 150)))
        val hugeItem = huge.items.first { it.id == 8970000 }
        assertEquals(99, hugeItem.stacks)
        assertTrue(hugeItem.stackWarnings.contains(RankerText.f("stackOverCeiling", 99)))
        assertEquals(99, index.setStacks(LoadoutConfig(), grace, 150).stacks(8970000), "输入框截到 99")
        assertEquals(0, index.setStacks(LoadoutConfig(), grace, -3).stacks(8970000))
    }

    @Test
    fun `叠层：封印监牢 7 层 ×1_4072、夹到参数表 10 层，黑夜入侵者 4 层 ×1_3108，两条阶梯同时生效相乘`() {
        // macOS checkLoadoutRealData ③ 的同一组数。
        val evergaolCard = custom(listOf(7060000))
        var config = LoadoutConfig().withRelic(0, evergaolCard)
        assertEquals(EntryState.ZERO_STACKS, evaluate(corpse, config).items.first { it.id == 7069001 }.state, "封印监牢没填层数不计入")
        config = config.copy(stackCounts = mapOf(7069001 to 7))
        assertClose(1.4072, evaluate(corpse, config).totalMultiplier, 1e-9, "封印监牢 7 层 = ×1.4072")
        config = config.copy(stackCounts = mapOf(7069001 to 12))
        val clamped = evaluate(corpse, config)
        val line = clamped.items.first { it.id == 7069001 }
        assertEquals(10, line.stacks, "层数夹到参数表 10 层")
        assertEquals(2, line.notes.size, "超过一局实际上限 7 层、超过参数表 10 层各一条提示：${line.notes}")
        assertEquals(RankerText.f("stackOverPractical", 10, 7, "实测"), line.notes[0])
        assertEquals(RankerText.f("stackOverParam", 10), line.notes[1])
        assertClose(1.6289, clamped.totalMultiplier, 1e-9, "封印监牢 10 层 = ×1.6289")
        assertEquals(7, entry(7069001).stackInput!!.defaultStacks)
        assertEquals(10, index.setStacks(LoadoutConfig(), entry(7069001), 12).stacks(7069001))

        val both = config.withRelic(1, custom(listOf(7060200))).copy(stackCounts = mapOf(7069001 to 7, 7069201 to 4))
        val bothEval = evaluate(corpse, both)
        assertClose(1.3108, entry(7069201).stackInput!!.tierMultipliers[3], 1e-12, "黑夜入侵者第 4 层")
        assertClose(1.4072 * 1.3108, bothEval.totalMultiplier, 1e-9, "封印监牢 7 层 × 黑夜入侵者 4 层相乘")
        assertTrue(bothEval.warnings.any { it.kind == "ladders" }, "两条阶梯同时生效要提示")
        assertEquals(4, entry(7069201).stackInput!!.practicalMaxStacks)
    }

    @Test
    fun `叠层：不同存档阶梯（sp204 不同优先度）可同时计入并相乘，汇总给出未实测提示`() {
        fun relicWith(spId: Int) = index.relicCandidates.getValue(RelicKind.NORMAL).first { candidate -> candidate.entries.any { it.id == spId } }
        val evergaol = relicWith(7069001)
        val invader = relicWith(7069201)
        var config = LoadoutConfig().withRelic(0, custom(listOf(evergaol.id))).withRelic(1, custom(listOf(invader.id)))
        val sp204 = Regex("^sp204@p")
        val unset = evaluate(corpse, config)
        assertEquals(0, unset.counted.count { sp204.containsMatchIn(it.entry.key) }, "没填层数就不计入")
        config = config.copy(stackCounts = mapOf(7069001 to 7, 7069201 to 4))
        val result = evaluate(corpse, config)
        assertEquals(2, result.counted.count { sp204.containsMatchIn(it.entry.key) }, "exclusiveKey 不同，两条都计入")
        assertTrue(result.warnings.any { it.kind == "ladders" && it.text.contains("未实测") })
        assertClose(
            entry(7069001).stackInput!!.tierMultipliers[6] * entry(7069201).stackInput!!.tierMultipliers[3],
            result.totalMultiplier, 1e-9, "封印监牢 7 层 × 黑夜入侵者 4 层（五种伤害都乘，对尸横遍野的斩＋火构成就是两者之积）",
        )
    }

    // ------------------------------------------------------------------ 汇总连乘

    @Test
    fun `汇总：总倍率 = Σ 占比 × 各类型上全部计入条目的倍率连乘；各栏小计只取本栏`() {
        val filled = ev(lion).recommendFill(LoadoutConfig(), lion.weaponWepType).config
        val config = filled.copy(others = filled.others + 3558)
        val result = evaluate(lion, config)
        fun weighted(items: List<EvaluatedEntry>): Double {
            val table = DoubleArray(DamageType.COUNT) { 1.0 }
            items.forEach { item -> for (i in table.indices) table[i] *= item.table[i] }
            return DamageType.entries.sumOf { lion.share(it) * table[it.ordinal] } / DamageType.entries.sumOf { lion.share(it) }
        }
        assertClose(weighted(result.counted), result.totalMultiplier, 1e-9, "总倍率")
        SummaryColumn.entries.forEach { column ->
            val items = result.counted.filter { it.column == column }
            assertClose(weighted(items), result.column(column).multiplier, 1e-9, "${column.key} 小计")
            assertEquals(items.size, result.column(column).count)
        }
        assertTrue(result.totalMultiplier!! > 1)
        val keys = result.counted.map { it.entry.key }
        assertEquals(keys.size, keys.toSet().size)
    }

    @Test
    fun `汇总：纯物理倍率对纯魔力法术等于 ×1；攻击力加算只展示、不进连乘`() {
        val result = evaluate(comet, LoadoutConfig().withRelic(0, custom(listOf(7001402))))
        assertClose(1.0, result.totalMultiplier, 1e-9, "物理 +6% 对帚星（纯魔力）没有收益")
        assertTrue(result.items.filter { it.column == SummaryColumn.RELIC }.all { it.state == EntryState.NO || it.state == EntryState.NEUTRAL })
        val flatOnly = index.relicCandidates.getValue(RelicKind.NORMAL).firstOrNull { candidate ->
            candidate.entries.all { !it.hasMultiplier && it.hasFlat }
        }
        if (flatOnly != null) {
            val flat = evaluate(corpse, LoadoutConfig().withRelic(0, custom(listOf(flatOnly.id))))
            assertClose(1.0, flat.totalMultiplier, 1e-9, "只有加算的条目不改变总倍率")
        }
    }

    @Test
    fun `汇总：没有构成时算不出倍率，推荐填满什么都不做`() {
        val empty = corpse.copy(shares = List(DamageType.COUNT) { 0.0 })
        val evaluator = index.evaluator(empty)
        val result = evaluator.evaluate(withAffixes(listOf(8350002)))
        assertNull(result.totalMultiplier)
        assertFalse(result.hasComposition)
        val fill = evaluator.recommendFill(LoadoutConfig(), null)
        assertEquals(0, fill.added.size)
        assertEquals(LoadoutConfig(), fill.config)
        assertEquals("CONFIG x mode=normal total=1.000000000", RankerCrossCheck.configDumpLine("x", LoadoutConfig(), result).substringBefore(" sub="))
    }

    // ------------------------------------------------------------------ 推荐填满

    @Test
    fun `推荐填满：不越界（武器词条总数／深夜专属／遗物格／护符格），自组遗物全部合法或预检通过`() {
        for ((label, output, pair) in Outputs.fills) {
            val (filterType, fill) = pair
            val result = ev(output).evaluate(fill.config)
            val wa = result.slots.weaponAffix
            assertTrue(wa.used <= wa.cap, "$label 武器词条越界")
            assertTrue(wa.deepOnlyUsed <= wa.deepOnlyCap, "$label 深夜专属越界")
            assertTrue(result.slots.relic.used <= result.slots.relic.cap, "$label 遗物越界")
            assertTrue(result.slots.accessory.used <= result.slots.accessory.cap, "$label 护符越界")
            result.relicChecks.forEachIndexed { i, check -> assertFalse(check.isInvalid, "$label 第 ${i + 1} 格遗物不合法：${check.issues}") }
            val keys = result.counted.map { it.entry.key }
            assertEquals(keys.size, keys.toSet().size, "$label 同一互斥键出现了两次")
            assertEquals(0, result.items.count { it.state == EntryState.DUPLICATE }, "$label 推荐不该挑出重复的键")
            if (filterType != null) {
                fill.config.weaponAffixes.keys.forEach { id ->
                    assertTrue(index.weaponAffixById.getValue(id).matchesType(fill.config.runMode, filterType), "$label 越过了类别过滤")
                }
            }
            assertTrue(fill.added.isNotEmpty(), "$label 应当填进东西")
            assertTrue(result.totalMultiplier!! >= 1, label)
            assertEquals(emptyList<String>(), result.violations, label)
        }
    }

    @Test
    fun `推荐填满：只挑被动、自动判定生效、无需确认、不需要层数的条目；只填空槽、重复点击不再加东西`() {
        val katana = corpse.weaponWepType
        val fill = ev(corpse).recommendFill(LoadoutConfig(), katana)
        val result = evaluate(corpse, fill.config)
        result.counted.forEach { item ->
            assertEquals("passive", item.entry.activation, "${item.id} 不是被动")
            assertTrue(item.needs.isEmpty(), "${item.id} 需要确认")
            assertNull(item.entry.stackInput)
        }
        val again = ev(corpse).recommendFill(fill.config, katana)
        assertEquals(0, again.added.size, "已经填满，再点不该有变化")
        assertEquals(fill.config, again.config)
        assertEquals(RankerText.f("fillDone", fill.added.size), "已按推荐填入 ${fill.added.size} 项")

        // 已选的不动：先放一件固定遗物与一个护符，再填。
        val seeded = LoadoutConfig().withRelic(1, RelicCard.fixed("2070")).withAccessory(0, 2020)
        val kept = ev(corpse).recommendFill(seeded, katana).config
        assertEquals("2070", kept.relic(1).fixedKey)
        assertEquals(2020, kept.accessory(0))
        assertTrue(kept.relic(0).type != RelicCardType.EMPTY || kept.relic(2).type != RelicCardType.EMPTY)
    }

    @Test
    fun `推荐填满：同一件固定遗物不会放进两格，同一护符不会装两个`() {
        for (output in listOf(corpse, lion)) {
            val config = Outputs.fills.first { it.second == output && it.third.first == null && it.third.second.config.runMode == RunMode.NORMAL }
                .third.second.config
            val fixedKeys = config.relics.filter { it.type == RelicCardType.FIXED }.map { it.fixedKey }
            assertEquals(fixedKeys.size, fixedKeys.toSet().size)
            val talismans = config.accessories.filterNotNull()
            assertEquals(talismans.size, talismans.toSet().size)
        }
    }

    // ------------------------------------------------------------------ 其它栏

    @Test
    fun `当前武器的固有效果自动列入（可排除）但不算用户确认：条件型默认未确认，换一把武器就没有`() {
        val innateEntry = ranker.entries.first { entry ->
            entry.innate != null && entry.listable && entry.innate!!.weaponIds.isNotEmpty() &&
                entry.buff.appliesTo?.skill != "no" && entry.stackInput == null
        }
        val weapon = assertNotNull(skills.weaponsById[innateEntry.innate!!.weaponIds[0]])
        assertNotNull(weapon.variantIndex(weapon.swordArtsParamId), "固有效果的武器用它自己的固定战技")
        val skill = skills.skillsById.getValue(weapon.swordArtsParamId)
        val output = RankerTestData.output(OutputClass.SKILL, skill.id, weapon.id)
        assertTrue(innateEntry in index.currentInnateEntries(output))
        val result = evaluate(output, LoadoutConfig())
        val item = result.items.first { it.id == innateEntry.id }
        assertTrue(item.auto && !item.autoConfirm, "当前武器固有：自动列入，但不算用户确认")
        assertEquals(listOf("innate:${innateEntry.id}"), item.keys)
        if (innateEntry.activation != "passive") {
            assertEquals(EntryState.PENDING, item.state, "条件型固有效果默认不计入（notes.ranking ③）")
            val after = evaluate(output, LoadoutConfig().withTick(innateEntry.id, true)).items.first { it.id == innateEntry.id }
            assertTrue(after.state == EntryState.COUNTED || after.state == EntryState.NEUTRAL, "勾选「条件成立」后计入")
        }
        val off = index.removeSource(LoadoutConfig(), "innate:${innateEntry.id}")
        assertFalse(evaluate(output, off).items.any { it.id == innateEntry.id })
        val back = ev(output).toggleOtherRow(off, innateEntry.ladderGroup ?: innateEntry.id, true)
        assertFalse(innateEntry.id in back.innateOff, "在其它栏重新勾上就恢复")
        assertFalse(innateEntry in index.currentInnateEntries(corpse))
        assertTrue(index.currentInnateEntries(comet).isEmpty(), "法术没有武器")
    }

    // ------------------------------------------------------------------ 复核回归：多档词条 / 减益 / 固有效果

    @Test
    fun `回归：蒙格温圣矛的条件型固有效果不会在空配置里自动计入（空配置 ×1），勾选后才计入`() {
        val mohg = Outputs.mohg
        val empty = evaluate(mohg, LoadoutConfig())
        assertClose(1.0, empty.totalMultiplier, 1e-9, "空配置不该有增伤")
        val bleed = empty.items.first { it.id == 8981903 }
        assertTrue(bleed.auto, "周围陷入出血时提升攻击力：当前武器固有，自动列入")
        assertEquals(EntryState.PENDING, bleed.state)
        val on = evaluate(mohg, LoadoutConfig().withTick(8981903, true))
        val item = on.items.first { it.id == 8981903 }
        assertEquals(EntryState.COUNTED, item.state)
        assertClose(item.multiplier!!, on.totalMultiplier, 1e-9, "勾选后总倍率等于这一条")
        // 其它栏的这一行：当前按「未确认」（×1），条件成立时的倍率是确认后能拿到的。
        val row = ev(mohg).otherRowsFor(LoadoutConfig(), "weaponInnate").first { it.row.key == 8981903 }
        assertTrue(row.auto && row.selected)
        assertEquals(EntryState.PENDING, row.score.state)
        assertClose(1.0, row.score.score, 1e-9, "未确认时当前倍率 ×1")
        assertClose(item.multiplier!!, row.score.potential, 1e-9, "条件成立时的倍率＝确认后的倍率")
        // 叠层类固有效果（玛雷家的庇佑 / 复仇的庇佑）自动列入时默认 0 层。
        listOf(8988200, 8998000).forEach { id ->
            val entry = entry(id)
            assertTrue(entry.stackInput != null && entry.innate != null)
            assertEquals(0, LoadoutConfig().stacks(id))
        }
        val stackWeapon = skills.weaponsById[entry(8988200).innate!!.weaponIds[0]]
        if (stackWeapon?.variantIndex(stackWeapon.swordArtsParamId) != null && skills.skillsById[stackWeapon.swordArtsParamId] != null) {
            val output = RankerTestData.output(OutputClass.SKILL, stackWeapon.swordArtsParamId, stackWeapon.id)
            val stackItem = evaluate(output, LoadoutConfig()).items.first { it.id == 8988200 }
            assertNotEquals(EntryState.COUNTED, stackItem.state, "叠层固有效果默认 0 层、不计入")
        }
    }

    @Test
    fun `回归：一件自组遗物只带「附加异常状态出血」(7120600)，总倍率不因它下降（减益不进配置页）`() {
        val mohg = Outputs.mohg
        val ticked = LoadoutConfig().withTick(8981903, true)
        val base = evaluate(mohg, ticked).totalMultiplier!!
        listOf(7120400, 7120500, 7120600).forEach { affixId ->
            assertNull(index.relicAffixEntries[affixId], "$affixId 的四档都是 ×0.85 减益，不进配置页")
            val result = evaluate(mohg, ticked.withRelic(0, custom(listOf(affixId))))
            assertFalse(result.relicChecks[0].isInvalid)
            assertClose(base, result.totalMultiplier, 1e-9, "$affixId 的 ×0.85 是减益（direction=decrease），不进增伤")
            assertEquals(0, result.items.count { it.column == SummaryColumn.RELIC })
            assertFalse(result.warnings.any { it.kind == "tiers" }, "不再提示「不同档位同时计入」")
        }
        // 自组下拉里也没有这条（没有能进计算的条目）。
        assertFalse(ev(mohg).relicAffixRows(ticked, RelicKind.NORMAL).any { it.option.id == 7120600 })
        // 减益在「逐条评估」里仍判「不生效」并写明原因。
        val state = ranker.evaluate(entry(7120601), mohg, LoadoutConfig(), EvalOptions(ownVariant = true), EvalSource(column = SummaryColumn.RELIC))
        assertEquals(EntryState.NO, state.state)
        assertEquals(RankerText.t("reasonDecrease"), state.reasons[0])
    }

    @Test
    fun `回归：「附加魔力属性攻击力」四档只算选中的一档，加算不再四档相加；两件同一词条只算一份`() {
        val members = ranker.variants.getValue("affix#7120000")
        var config = LoadoutConfig().withRelic(0, custom(listOf(7120000))).copy(ticks = members.map { it.id }.toSet())   // imbuedWeaponOnly：要确认
        val result = evaluate(corpse, config)
        val own = result.items.filter { it.column == SummaryColumn.RELIC && it.entry.variantGroup == "affix#7120000" }
        assertEquals(4, own.size)
        val chosen = own.filter { it.state != EntryState.VARIANT_OFF }
        assertEquals(1, chosen.size)
        assertEquals(members[0].id, chosen[0].id, "默认第 1 档")
        assertClose(1.0, result.totalMultiplier, 1e-9, "加算不进连乘")
        own.filter { it.state == EntryState.VARIANT_OFF }.forEach { assertEquals(listOf(RankerText.f("reasonVariantOff", 4, 1)), it.reasons) }
        config = config.withVariant("affix#7120000", members[3].id)
        val fourth = evaluate(corpse, config)
        assertEquals(
            listOf(members[3].id),
            fourth.items.filter { it.entry.variantGroup == "affix#7120000" && it.state != EntryState.VARIANT_OFF }.map { it.id },
        )
        // 同一词条放在两件遗物上：同一 spEffectId 合并，exclusiveScope=affixVariant → 只算一份。
        val both = evaluate(corpse, config.withRelic(1, custom(listOf(7120000))))
        val merged = both.items.filter { it.id == members[3].id }
        assertEquals(1, merged.size)
        assertEquals(2, merged[0].copies)
        assertEquals(1, merged[0].countedCopies)
        // 固定遗物整件带进来的多档同样只留一档（且 imbuedWeaponOnly 默认未确认）。
        val water = index.fixedRelics.first { relic -> relic.entries.any { it.id == 7120001 } }
        val fixedOwn = evaluate(Outputs.mohg, LoadoutConfig().withRelic(0, RelicCard.fixed(water.key)))
            .items.filter { it.entry.variantGroup == "affix#7120000" }
        assertEquals(1, fixedOwn.count { it.state != EntryState.VARIANT_OFF })
        assertEquals(EntryState.PENDING, fixedOwn.first { it.state != EntryState.VARIANT_OFF }.state)
        // 7 条「出击时的武器，附加…」同属 exclusivityId=100：两条不同词条同时计入时提示。
        val pair = LoadoutConfig().withRelic(0, custom(listOf(7120000))).withRelic(1, custom(listOf(7120100)))
            .copy(ticks = setOf(7120001, 7120101))
        val flame = RankerTestData.output(OutputClass.SKILL, 100, 3180500)
        val warned = evaluate(flame, pair)
        if (warned.counted.count { it.column == SummaryColumn.RELIC } >= 2) {
            assertTrue(warned.warnings.any { it.kind == "exclusivity" })
        }
    }

    @Test
    fun `自组深夜遗物换词条：需诅咒的词条自动配诅咒，换成另一条需诅咒的词条时清掉旧诅咒重配（与 macOS withRelicAffix 同法）`() {
        assertTrue(index.catalog.byId.getValue(6001401).requiresCurse)
        val picked = index.withRelicAffix(RelicCard.EMPTY, RelicKind.DEEP, 0, 6001401)
        assertEquals(RelicCardType.CUSTOM, picked.type)
        assertEquals(listOf(6001401, null, null), picked.affixIds)
        assertEquals(listOf(6820000, null, null), picked.curseIds, "自动配上「受到损伤时，会累积中毒量表」")
        assertEquals(picked.curseAt(0), index.pickCurse(custom(listOf(6001401)), 0))
        assertEquals(RelicCheckStatus.PARTIAL, check(picked, RelicKind.DEEP).status)
        val config = LoadoutConfig(runMode = RunMode.DEEP).withRelic(3, picked)
        val result = evaluate(corpse, config)
        assertEquals(RelicCheckStatus.PARTIAL, result.relicChecks[3].status)
        val fromCard = result.itemsFrom("relic:3")
        assertTrue(fromCard.isNotEmpty() && fromCard.none { it.state == EntryState.RELIC_INVALID }, "配上诅咒后整件计入")
        assertTrue(fromCard.any { it.state == EntryState.COUNTED })
        // 用户手动改成第二条诅咒，再把这一行换成另一条需诅咒的词条：旧诅咒清掉、按新词条重配。
        val manual = custom(listOf(6001401), listOf(index.catalog.curses[1].effectId))
        assertEquals(RelicCheckStatus.PARTIAL, check(manual, RelicKind.DEEP).status)
        val swapped = index.withRelicAffix(manual, RelicKind.DEEP, 0, 6260000)
        assertTrue(index.catalog.byId.getValue(6260000).requiresCurse)
        assertEquals(listOf(6820000, null, null), swapped.curseIds, "换词条后重配，不沿用旧诅咒")
        // 换成不需诅咒的词条：这一行的诅咒清掉；普通遗物格不带诅咒。
        val free = index.relicCandidates.getValue(RelicKind.DEEP).first { !it.affix.requiresCurse }
        assertEquals(listOf(null, null, null), index.withRelicAffix(swapped, RelicKind.DEEP, 0, free.id).curseIds)
        assertEquals(listOf(null, null, null), index.withRelicAffix(RelicCard.EMPTY, RelicKind.NORMAL, 0, 6001401).curseIds)
        // 另一行手动清掉的诅咒：换任一行的词条时一并补配（autoAssignCurses 逐行补）。
        val cleared = custom(listOf(6001401, free.id))
        assertEquals(listOf(6820000, null, null), index.withRelicAffix(cleared, RelicKind.DEEP, 1, null).curseIds)
    }

    @Test
    fun `回归：深夜遗物「【无赖】技艺命中敌人时，能降低对方的攻击力」(6500400 → 7500401) 不进增伤`() {
        val config = LoadoutConfig(runMode = RunMode.DEEP)
            .withRelic(3, index.autoAssignCurses(custom(listOf(6500400)), RelicKind.DEEP))
        val result = evaluate(corpse, config)
        assertFalse(result.relicChecks[3].isInvalid)
        assertFalse(result.items.any { it.id == 7500401 }, "减益不进配置页")
        assertClose(1.0, result.totalMultiplier, 1e-9)
        assertFalse(ev(corpse).relicAffixRows(config, RelicKind.DEEP).any { it.option.id == 6500400 })
    }

    @Test
    fun `其它栏：勾选即视为条件成立；累积阶梯一行、勾上时先选最高层，只算选中的那层；叠层勾上时先填一局实际上限`() {
        val config = ev(corpse).toggleOtherRow(LoadoutConfig(), 3558, true)
        assertEquals(index.ladderTopTier(3558)!!.id, config.tiers[3558], "预选最高层")
        val result = evaluate(corpse, config)
        val ladder = result.items.filter { it.entry.ladderGroup == 3558 }
        assertTrue(ladder.size >= 2)
        assertEquals(1, ladder.count { it.state == EntryState.COUNTED })
        assertEquals(ladder.size - 1, ladder.count { it.state == EntryState.TIER_OFF })
        assertEquals(1, ev(corpse).visibleItems(ladder, config).size, "累积阶梯只列选中的那一层")
        val rows = ev(corpse).otherRowsFor(config, "consumable")
        val row = rows.first { it.row.key == 3558 }
        assertTrue(row.selected)
        assertTrue(row.row.ladder && row.row.subtitle == RankerText.f("ladderTierCount", row.row.entries.size))
        rows.zipWithNext().forEach { (a, b) ->
            if (a.score.applicable == b.score.applicable) assertTrue(a.score.score >= b.score.score - 1e-9)
        }
        val unticked = ev(corpse).toggleOtherRow(config, 3558, false)
        assertFalse(3558 in unticked.others)
        val grace = ev(corpse).toggleOtherRow(LoadoutConfig(), 8970000, true)
        assertEquals(1, grace.stacks(8970000), "赐福王的余威没有实测上限：先填 1 份")
        assertEquals(EntryState.COUNTED, evaluate(corpse, grace).items.first { it.id == 8970000 }.state)
        assertEquals(emptySet<Int>(), index.removeSource(grace, "other:8970000").others)
        // 没选层的累积阶梯（取消预选）：一层都不算，选层控件留在第 1 层。
        val noTier = config.withLadderTier(3558, null)
        val noTierItems = evaluate(corpse, noTier).items.filter { it.entry.ladderGroup == 3558 }
        assertTrue(noTierItems.all { it.state == EntryState.TIER_OFF })
        assertEquals(listOf(RankerText.t("reasonTierNone")), noTierItems.first().reasons)
        assertEquals(listOf(index.ladders.getValue(3558).first().id), ev(corpse).visibleItems(noTierItems, noTier).map { it.id })
    }

    @Test
    fun `其它栏的列出口径：选中的一律列出、没收益的默认隐藏、角色栏按角色分组、武器固有栏当前武器自带的在前`() {
        val evaluator = ev(Outputs.mohg)
        val innate = evaluator.shownOtherRows(LoadoutConfig(), "weaponInnate", showInactive = true)
        assertTrue(innate.first().auto, "当前武器自带的在前")
        val firstOther = innate.indexOfFirst { !it.auto }
        assertTrue(firstOther > 0 && innate.drop(firstOther).none { it.auto })
        assertEquals(RankerText.t("groupAutoInnate"), evaluator.otherRowGroup(innate.first()))
        assertEquals(RankerText.t("groupOtherInnate"), evaluator.otherRowGroup(innate[firstOther]))
        val characters = ev(corpse).shownOtherRows(LoadoutConfig(), "character", showInactive = true)
        assertEquals(index.otherRows.getValue("character").size, characters.size)
        val groups = characters.map { ev(corpse).otherRowGroup(it)!! }
        assertEquals(groups.sorted(), groups, "角色栏按角色名分组")
        val useful = ev(corpse).shownOtherRows(LoadoutConfig(), "consumable")
        assertTrue(useful.all { it.score.isUseful(true) }, "没收益的默认隐藏")
        val all = ev(corpse).shownOtherRows(LoadoutConfig(), "consumable", showInactive = true)
        assertTrue(all.size > useful.size)
        val useless = all.first { !it.score.isUseful(true) }
        val picked = ev(corpse).toggleOtherRow(LoadoutConfig(), useless.row.key, true)
        assertTrue(ev(corpse).shownOtherRows(picked, "consumable").any { it.row.key == useless.row.key }, "选中的一律列出")
        val query = "赐福".foldedForSearch()
        val found = ev(corpse).shownOtherRows(LoadoutConfig(), "runStack", query, showInactive = true)
        assertEquals(listOf(8970000), found.map { it.row.key })
    }

    @Test
    fun `护符与遗物候选行：按有效倍率降序，状态取「最接近生效」的那一条`() {
        val talismans = ev(comet).talismanRows(LoadoutConfig())
        talismans.zipWithNext().forEach { (a, b) -> if (a.score.applicable == b.score.applicable) assertTrue(a.score.score >= b.score.score) }
        val sorceryTalisman = assertNotNull(talismans.firstOrNull { it.talisman.id == 3000 }, "魔法师球护符")
        assertEquals(EntryState.COUNTED, sorceryTalisman.score.state)
        assertTrue(sorceryTalisman.score.score > 1)
        val fixed = ev(corpse).fixedRelicRows(LoadoutConfig(), RelicKind.NORMAL)
        assertEquals(index.fixedRelics.count { !it.isDeepRelic }, fixed.size)
        // score 按「随整件带入」口径（条件型未确认），potential 按全部确认；减益两种口径都不计入，所以 potential ≥ score。
        fixed.forEach { row -> assertTrue(row.score.score > 0 && row.score.potential >= row.score.score - 1e-12, "${row.relic.key} 确认条件后不该更低") }
        val withPending = fixed.first { row ->
            row.relic.entries.any { it.countsAsDamage && it.activation != "passive" && it.stackInput == null && it.buff.appliesTo?.skill == "yes" }
        }
        assertTrue(withPending.score.potential != withPending.score.score, "有条件型效果的固定遗物，两种口径应当不同")
        assertTrue(ev(lightning).relicAffixRows(LoadoutConfig(), RelicKind.DEEP).isNotEmpty())
    }

    @Test
    fun `遗物格：切成「固定遗物／自组」但还没选东西的格不算占用，推荐填满也会填它`() {
        val config = LoadoutConfig().withRelic(0, RelicCard(RelicCardType.FIXED, null)).withRelic(1, custom(emptyList()))
        assertFalse(config.relic(0).isFilled)
        assertFalse(config.relic(1).isFilled)
        assertTrue(custom(listOf(7001402)).isFilled)
        assertEquals(0, evaluate(corpse, config).slots.relic.used)
        val filled = ev(corpse).recommendFill(config, corpse.weaponWepType).config
        assertTrue(filled.relic(0).isFilled && filled.relic(1).isFilled)
    }

    // ------------------------------------------------------------------ macOS 端的固定事实

    @Test
    fun `真实数据的结构事实：slotRules 上限、诅咒池、多档词条、selfAllyPair、exclusivityId`() {
        assertTrue(index.supportsLoadout)
        val normal = index.caps(RunMode.NORMAL)
        val deep = index.caps(RunMode.DEEP)
        assertEquals(listOf(6, 0, 3, 2), listOf(normal.weaponAffix, normal.deepOnly, normal.relics, normal.accessory))
        assertEquals(listOf(12, 6, 6, 2), listOf(deep.weaponAffix, deep.deepOnly, deep.relics, deep.accessory))
        assertTrue(index.weaponAffixes.isNotEmpty() && index.fixedRelics.isNotEmpty() && index.talismans.isNotEmpty())
        assertTrue(index.relicCandidates.getValue(RelicKind.NORMAL).isNotEmpty() && index.relicCandidates.getValue(RelicKind.DEEP).isNotEmpty())
        assertEquals(3_000_000, index.catalog.cursePoolId, "诅咒池从词条库现算（与 core.js DEEP_CURSE_POOL_ID 同值）")
        assertTrue(index.catalog.curses.isNotEmpty() && index.catalog.curses.zipWithNext().all { (a, b) -> a.effectId < b.effectId })
        assertEquals(6820000, index.catalog.curses.first().effectId)
        assertEquals(7, ranker.variants.size)
        assertTrue(ranker.variants.values.all { it.size == 4 }, "多档词条 7 组 × 4 档")
        assertEquals(6, dataset.buffs.count { it.selfAllyPair != null })
        val exclusivityAffixes = dataset.buffs.flatMap { buff -> buff.relicAffixes.filter { it.exclusivityId == 100 }.map { it.attachEffectId } }.toSet()
        assertEquals(7, exclusivityAffixes.size)
        dataset.buffs.forEach { assertTrue(it.stacking.exclusiveKey.isNotEmpty(), "#${it.spEffectId} 应有 exclusiveKey") }
        // 其它增益：各分栏齐全，累积阶梯合成一行，行键全局唯一。
        assertEquals(LoadoutIndex.OTHER_SLOTS, index.otherRows.keys.toList())
        val keys = index.otherRows.values.flatten().map { it.key }
        assertEquals(keys.size, keys.toSet().size)
        index.otherRows.getValue("character").forEach { assertTrue(it.groupTitle != null) }
        assertEquals("复仇者" to "技艺", LoadoutText.heroGroup("[Skill - Revenant] Family Buff"))
        assertEquals("连刺破露滴", LoadoutText.stripTierSuffix("连刺破露滴（第1层）"))
        assertEquals("提升攻击力", LoadoutText.familyName("提升攻击力（档位2）"))
        assertEquals("提升物理攻击力", LoadoutText.familyName("提升物理攻击力＋２"))
    }

    @Test
    fun `exclusiveKey 真实例子：狂热香药与『火焰啊，赐予我力量！』同为 sp151，只留一份`() {
        val result = evaluate(corpse, LoadoutConfig(others = setOf(503550, 1605000)))
        assertEquals(1, result.counted.size, result.items.map { "${it.id}:${it.state.key}" }.toString())
        assertEquals(1, result.items.count { it.state == EntryState.DUPLICATE })
        assertEquals("sp151", result.counted.single().entry.key)
    }

    @Test
    fun `配置能存成字符串再读回（rememberSaveable 用）`() {
        val fill = Outputs.fills.first { it.third.second.config.runMode == RunMode.DEEP }.third.second.config
        val config = fill.copy(others = setOf(3558), tiers = mapOf(3558 to 3561), variants = mapOf("affix#7120000" to 7120004), ticks = setOf(1, 2))
        assertEquals(config, LoadoutConfig.decode(config.encode()))
        assertEquals(LoadoutConfig(), LoadoutConfig.decode(LoadoutConfig().encode()))
        assertNull(LoadoutConfig.decode("{broken"))
        assertNull(LoadoutConfig.decode(null))
    }

    // ------------------------------------------------------------------ 道具等级（携物知识）与纯魔法输出

    @Test
    fun `勇者肉块对纯魔法输出：1、2 级只加物理＝对当前构成无增益（默认隐藏），3 级（携物知识 3 级）按魔力倍率计入，名字写明物理与属性`() {
        assertClose(1.0, comet.shares[DamageType.MAGIC.ordinal], 1e-9, "帚星是纯魔法输出")
        val raw = dataset.buffs.associateBy { it.spEffectId }
        val rows = ev(comet).otherRowsFor(LoadoutConfig(), "consumable").associateBy { it.row.key }
        val shown = ev(comet).shownOtherRows(LoadoutConfig(), "consumable").map { it.row.key }.toSet()

        // 1 级 3950（物理 ×1.2）、2 级 708420（物理 ×1.3）：rates 只有物理，对纯魔法 ×1。
        listOf(3950, 708420).forEach { id ->
            assertEquals(listOf("physicsAttackRate"), raw.getValue(id).rates.keys.toList(), "$id 只提高物理")
            val row = assertNotNull(rows[id], "$id 应在「道具」栏")
            assertEquals(EntryState.NEUTRAL, row.score.state)
            assertEquals("对当前构成无增益", row.score.state.label)
            assertClose(1.0, row.score.score, 1e-9, "$id 当前倍率")
            assertClose(1.0, row.score.potential, 1e-9, "$id 条件成立时倍率")
            assertFalse(row.score.isUseful(comet.hasComposition), "$id 默认隐藏（打开「显示不生效项」才看得到）")
            assertFalse(id in shown, "$id 默认不列出")
        }
        assertEquals("", rows.getValue(3950).row.goodsLevelTag, "1 级不标等级")
        assertEquals("携物知识 2 级", rows.getValue(708420).row.goodsLevelTag)

        // 3 级 708421：物理 ×1.3 之外魔力／火／雷／圣 ×1.2，纯魔法上按魔力那一项计入。
        val top = rows.getValue(708421)
        val magicRate = assertNotNull(raw.getValue(708421).rates["magicAttackRate"])
        assertClose(1.2, magicRate, 1e-12, "3 级的魔力倍率")
        assertEquals(EntryState.COUNTED, top.score.state)
        assertClose(magicRate, top.score.score, 1e-9, "纯魔法输出上按魔力倍率计入")
        assertTrue(top.score.isUseful(comet.hasComposition))
        assertTrue(708421 in shown, "默认列出")
        assertTrue(top.row.name.contains("属性"), "名字写明也加属性：${top.row.name}")
        assertFalse(top.row.name.contains("提升物理攻击力"), "不再只说物理：${top.row.name}")
        assertEquals("提升物理攻击力", raw.getValue(708421).nameZh, "游戏文本 nameZh 原样保留，页面显示的是 displayNameZh")
        assertEquals(3, top.row.goodsLevel)
        assertEquals("携物知识 3 级", top.row.goodsLevelTag)
        assertEquals(RankerText.t("goodsLevel.note"), index.goodsLevelNote("consumable"), "「道具」分栏说明区给出等级来源")

        // 放进配置：总倍率就是 ×1.2；1 级与 3 级同互斥键（同一道具换等级只是换一行），同时勾只算 3 级那一份。
        var config = ev(comet).toggleOtherRow(LoadoutConfig(), 708421, true)
        var result = evaluate(comet, config)
        assertClose(magicRate, result.totalMultiplier, 1e-9, "只勾 3 级")
        assertEquals(listOf(708421), result.counted.map { it.id })
        config = ev(comet).toggleOtherRow(config, 3950, true)
        result = evaluate(comet, config)
        assertEquals(ranker.byId.getValue(3950).key, ranker.byId.getValue(708421).key, "各级同一个互斥键")
        assertClose(magicRate, result.totalMultiplier, 1e-9, "1 级与 3 级同时勾，仍是 ×1.2")
        assertEquals(listOf(708421), result.counted.map { it.id })
    }

    @Test
    fun `道具等级：其它增益各栏按数据的 goodsLevel 标「携物知识 N 级」，只有「道具」栏有等级行、也只有它给说明`() {
        var tagged = 0
        LoadoutIndex.OTHER_SLOTS.forEach { slot ->
            index.otherRows[slot].orEmpty().forEach { row ->
                val level = row.first.buff.goodsLevel
                val expected = if (level != null && level >= 2) "携物知识 $level 级" else ""
                assertEquals(expected, row.goodsLevelTag, "${row.key} 的等级标记")
                if (expected.isNotEmpty()) {
                    tagged += 1
                    assertEquals("consumable", slot, "${row.key} 是道具等级行，应在「道具」栏")
                    assertTrue(row.name.contains("携物知识$level"), "${row.key} 的显示名应写明同一等级：${row.name}")
                }
            }
            val expectedNote = if (slot == "consumable") RankerText.t("goodsLevel.note") else null
            assertEquals(expectedNote, index.goodsLevelNote(slot), "$slot 的等级说明")
        }
        val listableLevelRows = ranker.entries.count { it.listable && it.goodsLevel >= 2 && it.accLadder == null }
        assertTrue(tagged > 0 && tagged == listableLevelRows, "能进配置页的等级行都标上了（$tagged 行）")
        assertNull(index.goodsLevelNote("missing"), "没有的分栏不给说明")

        // 旧数据没有 goodsLevel：一行都不标，也不给说明；合成一条 2 级行就给。
        val plain = LoadoutIndex(RankerTestData.miniIndex(listOf(RankerTestData.synthBuff(-93) { it.copy(sourceSlot = "consumable") })))
        assertEquals("", plain.otherRows.getValue("consumable").single().goodsLevelTag)
        assertNull(plain.goodsLevelNote("consumable"))
        val leveled = LoadoutIndex(
            RankerTestData.miniIndex(listOf(RankerTestData.synthBuff(-94) { it.copy(sourceSlot = "consumable", goodsLevel = 2) })),
        )
        assertEquals("携物知识 2 级", leveled.otherRows.getValue("consumable").single().goodsLevelTag)
        assertEquals(RankerText.t("goodsLevel.note"), leveled.goodsLevelNote("consumable"))
    }
}
