package com.nightreign.relicchecker.gamedata.ranker

// 整套配置的计算（Windows 端 ranker.js collectSources / mergeSources / evaluateMerged / dedupeItems /
// columnSummary / evaluateConfig / totalOf / configWarnings / configViolations / candidateScore / recommendFill，
// macOS 端 LoadoutEvaluator，两端同一口径）：
//   ① 展开来源（两端同一顺序）：武器词条（AttachEffect id 升序）→ 遗物格 → 护符格 → 当前武器固有 → 其它栏勾选
//      （spEffectId 升序）；同一 spEffectId 从多处来的合并成一条（份数相加、来源并列），不合法自组遗物里的单独成条；
//   ② 逐条评估（BuffRankerIndex.evaluate）：生效判定、作用对象、减益、累积阶梯选层、叠层层数、确认、份数；
//   ③ 按 stacking.exclusiveKey 去重：同键只留一份——两边都是 applyHighest 且 categoryPriority 不同 → 取数值小的；
//      否则有效倍率高的；再比加算；再取 spEffectId 小的（完全并列时先出现的留下）；
//   ④ 总倍率＝留下的条目逐伤害类型连乘，再按伤害构成占比加权；各栏小计同法只算本栏；攻击力加算只按占比加权展示；
//   ⑤ 按推荐填满：只填空槽、不改已选；武器词条 → 遗物逐格（最好的固定遗物与贪心自组比较，同分取固定）→ 护符；
//      每一步取推荐口径（strict）总倍率增幅最大的候选，同增幅取 ID 小的，增幅 ≤ 1e-9 就停。

/** 配置展开出来的一个来源（还没评估）。[key] 是移除按钮用的来源键（见 [LoadoutIndex.removeSource]）。 */
data class ConfigSource(
    val entry: BuffRankerEntry,
    val column: SummaryColumn,
    val copies: Int,
    val label: String,
    val key: String,
    val autoConfirm: Boolean = false,
    val auto: Boolean = false,
    /** 来自不合法的自组遗物（整件不计入）。 */
    val invalid: Boolean = false,
)

/** 同一个 spEffectId 合并后的来源。 */
data class MergedSource(
    val entry: BuffRankerEntry,
    val column: SummaryColumn,
    val copies: Int,
    val labels: List<String>,
    val keys: List<String>,
    val autoConfirm: Boolean,
    val auto: Boolean,
    val invalid: Boolean,
) {
    fun toEvalSource(): EvalSource = EvalSource(column, copies, autoConfirm, auto, labels, keys)
}

/** collectSources 的结果：来源清单、每张遗物卡的检查结果（按格位，长度＝caps.relics）、槽位上限。 */
data class CollectedSources(val sources: List<ConfigSource>, val relicChecks: List<RelicCheck>, val caps: SlotCaps)

/** 一栏（或全部）的汇总：条数、逐类型连乘表、按构成加权的倍率（没有构成时为 null）、加权后的攻击力加算。 */
data class ColumnSummary(val count: Int, val table: List<Double>, val multiplier: Double?, val flat: Double)

data class SlotCount(val used: Int, val cap: Int) {
    val isOver: Boolean get() = used > cap
    val text: String get() = "$used/$cap"
}

data class SlotUsage(val weaponAffix: WeaponAffixUsage, val relic: SlotCount, val accessory: SlotCount)

/** 汇总里的一条提示（kind：priority / duplicate / copiesSingle / copiesStackSelf / tiers / ladders / exclusivity / fixedDuplicate）。 */
data class LoadoutWarning(val kind: String, val text: String)

/** 整套配置的评估结果（Windows evaluateConfig 的返回值）。 */
class LoadoutEvaluation internal constructor(
    /** 全部条目（合并后的来源顺序，不合法自组遗物里的在最后），去重后被压掉的为 DUPLICATE。 */
    val items: List<EvaluatedEntry>,
    /** 计入的条目（去重后留下的，按互斥键第一次出现的顺序）。 */
    val counted: List<EvaluatedEntry>,
    /** 四栏小计（本栏单独连乘加权）。 */
    val byColumn: Map<SummaryColumn, ColumnSummary>,
    val total: ColumnSummary,
    val caps: SlotCaps,
    /** 每张遗物卡（按格位，长度＝caps.relics）的检查结果。 */
    val relicChecks: List<RelicCheck>,
    val slots: SlotUsage,
    val warnings: List<LoadoutWarning>,
    /** 超限与不合法（正常操作到不了，程序化构造的配置才会出现；不合法的自组遗物也列在这里）。 */
    val violations: List<String>,
    val hasComposition: Boolean,
    /** 被压掉的条目 → 留下的那一条（按 items 下标）。 */
    private val duplicateOf: Map<Int, EvaluatedEntry>,
) {
    /** 总倍率；没有构成时为 null（页面显示「—」）。 */
    val totalMultiplier: Double? get() = total.multiplier

    /** 对当前输出不生效（或要勾攻击情境）的条数（汇总里「另有 N 条对当前输出不生效」）。 */
    val hiddenCount: Int get() = items.count { it.state == EntryState.NO || it.state == EntryState.CONTEXT }

    fun column(column: SummaryColumn): ColumnSummary = byColumn.getValue(column)

    /** 被压掉的这一条（DUPLICATE）是被谁压掉的。 */
    fun duplicateWinner(item: EvaluatedEntry): EvaluatedEntry? =
        items.indexOfFirst { it === item }.takeIf { it >= 0 }?.let { duplicateOf[it] }

    /** 某个来源键（relic:3 / acc:0 …）带进来的条目。 */
    fun itemsFrom(keyPrefix: String): List<EvaluatedEntry> =
        items.filter { item -> item.keys.any { it == keyPrefix || it.startsWith("$keyPrefix:") } }
}

/** 一项候选单独放进来的评估（Windows candidateScore）。 */
data class CandidateScore(
    val items: List<EvaluatedEntry>,
    /** 按当前的确认／层数／选层／选档，单独选它时的有效倍率（没有构成时为 1）。 */
    val score: Double,
    /** 条件全部成立时（叠层取一局实际上限、没有就 1 层，阶梯取最高层）的有效倍率。 */
    val potential: Double,
    /** 条件全部成立时按占比加权的攻击力加算（只展示）。 */
    val flat: Double,
    /** 最接近生效的那一条的状态与原因。 */
    val state: EntryState,
    val reasons: List<String>,
    val applicable: Boolean,
    /** 还有条件没确认（或层数为 0、未选层）。 */
    val needsConfirmation: Boolean,
    /** 潜在倍率里有叠层条目没有「实际上限」、也还没填层数，只按 1 层算（页面要写明）。 */
    val assumesOneStack: Boolean,
) {
    /** 对当前输出有收益：条件成立时倍率 > 1 或有正的攻击力加算；没有构成时一律算有（Windows rowUseful）。 */
    fun isUseful(hasComposition: Boolean): Boolean =
        !hasComposition || (applicable && (potential > USEFUL_EPSILON || flat > 0.0))

    val blockedReason: String? get() = if (applicable) null else reasons.firstOrNull() ?: RankerText.t("verdictNoFallback")
}

/** 各栏候选行共有的排序字段。 */
interface ScoredRow {
    val score: CandidateScore
    val sortId: Int
}

data class WeaponAffixRow(
    val affix: WeaponAffixOption,
    val count: Int,
    /** 已选、但不在当前类别过滤里（仍列出，否则减不掉）。 */
    val outsideFilter: Boolean,
    val can: AddCheck,
    override val score: CandidateScore,
) : ScoredRow {
    override val sortId: Int get() = affix.id
}

data class RelicAffixRow(val option: RelicAffixOption, override val score: CandidateScore) : ScoredRow {
    override val sortId: Int get() = option.id
}

data class FixedRelicRow(val relic: FixedRelicOption, override val score: CandidateScore) : ScoredRow {
    override val sortId: Int get() = relic.relicIds.firstOrNull() ?: 0
}

data class TalismanRow(val talisman: TalismanOption, override val score: CandidateScore) : ScoredRow {
    override val sortId: Int get() = talisman.id
}

data class OtherRowScore(
    val row: OtherRow,
    /** 当前武器自带（自动列入，勾掉＝排除）。 */
    val auto: Boolean,
    val selected: Boolean,
    override val score: CandidateScore,
) : ScoredRow {
    override val sortId: Int get() = row.key
}

/** 推荐填满加进来的一项（「已按推荐填入 N 项」）。 */
data class FillAddition(val column: SummaryColumn, val label: String)

data class FillResult(val config: LoadoutConfig, val added: List<FillAddition>)

/**
 * 绑定一个输出手段的计算器。建一次会把能进计算的条目逐条判定并缓存（换战技 / 武器 / 手 / 攻击情境 / 构成时新建）。
 * 线程安全：内部只有不可变缓存与线程安全的遗物检查缓存，可以在 Dispatchers.Default 上跑 [recommendFill]。
 */
class LoadoutEvaluator(val index: LoadoutIndex, val output: RankerOutput) {
    val ranker: BuffRankerIndex get() = index.ranker

    private val verdicts: Map<Int, AppliesVerdict> =
        HashMap<Int, AppliesVerdict>(index.ranker.listableEntries.size * 2).also { map ->
            for (entry in index.ranker.listableEntries) map[entry.id] = index.ranker.verdict(entry, output)
        }

    /** 当前武器的固有效果（自动列入）。 */
    val currentInnateEntries: List<BuffRankerEntry> = index.currentInnateEntries(output)
    private val currentInnateIds: Set<Int> = currentInnateEntries.mapTo(HashSet()) { it.id }

    val hasComposition: Boolean get() = output.hasComposition

    fun verdict(entry: BuffRankerEntry): AppliesVerdict = verdicts[entry.id] ?: ranker.verdict(entry, output)

    /** 单条评估（判定走缓存）。 */
    fun evaluateEntry(
        entry: BuffRankerEntry,
        config: LoadoutConfig,
        options: EvalOptions = EvalOptions.STANDARD,
        source: EvalSource = EvalSource(),
    ): EvaluatedEntry = ranker.evaluate(entry, output, config, options, source, verdict(entry))

    // ============================================================ 展开与合并

    /** 把配置展开成「来源 → 条目」（两端同一顺序）。 */
    fun collectSources(config: LoadoutConfig): CollectedSources {
        val caps = index.caps(config.runMode)
        val list = ArrayList<ConfigSource>()
        val relicChecks = ArrayList<RelicCheck>(caps.relics)
        for (id in config.weaponAffixes.keys.sorted()) {
            val count = config.weaponAffixes[id] ?: 0
            val affix = index.weaponAffixById[id] ?: continue
            if (count <= 0 || !affix.isAvailable(config.runMode)) continue
            val label = affix.label + if (count > 1) " ×$count" else ""
            for (entry in affix.entries) list += ConfigSource(entry, SummaryColumn.WEAPON_AFFIX, count, label, "wa:${affix.id}")
        }
        for (cardIndex in 0 until caps.relics) {
            val card = config.relic(cardIndex)
            val kind = caps.relicKind(cardIndex)
            val cardLabel = caps.relicCardLabel(cardIndex)
            when (card.type) {
                RelicCardType.FIXED -> {
                    val fixed = card.fixedKey?.let { index.fixedRelicByKey[it] }
                    relicChecks += if (fixed != null) RelicCheck.FIXED else RelicCheck.EMPTY
                    if (fixed == null) continue
                    for (entry in fixed.entries) {
                        list += ConfigSource(entry, SummaryColumn.RELIC, 1, cardLabel + "：" + fixed.nameZh, "relic:$cardIndex")
                    }
                }
                RelicCardType.CUSTOM -> {
                    val check = index.checkCustomRelic(card, kind)
                    relicChecks += check
                    val invalid = check.isInvalid
                    for (row in check.rows) {
                        val affix = row.affix ?: continue
                        for (entry in index.relicAffixEntries[affix.effectId].orEmpty()) {
                            list += ConfigSource(
                                entry, SummaryColumn.RELIC, 1, cardLabel + "：" + affix.name,
                                "relic:$cardIndex:${row.row}", invalid = invalid,
                            )
                        }
                    }
                }
                RelicCardType.EMPTY -> relicChecks += RelicCheck.EMPTY
            }
        }
        config.accessories.take(caps.accessory).forEachIndexed { slot, id ->
            val talisman = id?.let { index.talismanById[it] } ?: return@forEachIndexed
            for (entry in talisman.entries) list += ConfigSource(entry, SummaryColumn.ACCESSORY, 1, talisman.nameZh, "acc:$slot")
        }
        // 当前武器固有：自动列入，但不算用户确认——条件型默认未确认、叠层默认 0 层（notes.ranking ③）。
        for (entry in currentInnateEntries) {
            if (entry.id in config.innateOff) continue
            list += ConfigSource(
                entry, SummaryColumn.OTHER, 1, RankerText.t("otherAutoInnate"), "innate:${entry.id}", auto = true,
            )
        }
        val picked = ArrayList<ConfigSource>()
        for (slot in LoadoutIndex.OTHER_SLOTS) {
            for (row in index.otherRows[slot].orEmpty()) {
                if (row.key !in config.others) continue
                for (entry in row.entries) {
                    if (entry.id in currentInnateIds) continue
                    picked += ConfigSource(
                        entry, SummaryColumn.OTHER, 1, RankerText.t("otherGroups.$slot"), "other:${row.key}", autoConfirm = true,
                    )
                }
            }
        }
        return CollectedSources(list + picked.sortedBy { it.entry.id }, relicChecks, caps)
    }

    // ============================================================ 整套配置

    /** 整套配置的评估（汇总面板、各栏计入情况、提示与超限都从这里取）。 */
    fun evaluate(config: LoadoutConfig, options: EvalOptions = EvalOptions.STANDARD): LoadoutEvaluation {
        val collected = collectSources(config)
        val evaluated = evaluateMerged(mergeSources(collected.sources), config, options)
        val deduped = dedupeItems(evaluated)
        val winners = deduped.winners
        val shares = output.shares
        val byColumn = SummaryColumn.entries.associateWith { column ->
            columnSummary(winners.filter { it.column == column }, shares)
        }
        val total = columnSummary(winners, shares)
        val caps = collected.caps
        val weaponUsage = index.weaponAffixUsage(config)
        val relicUsed = (0 until caps.relics).count { config.relic(it).isFilled }
        val accessories = config.accessories.take(caps.accessory).filterNotNull()
        val slots = SlotUsage(weaponUsage, SlotCount(relicUsed, caps.relics), SlotCount(accessories.size, caps.accessory))
        return LoadoutEvaluation(
            items = deduped.items,
            counted = winners,
            byColumn = byColumn,
            total = total,
            caps = caps,
            relicChecks = collected.relicChecks,
            slots = slots,
            warnings = configWarnings(deduped, config, caps),
            violations = configViolations(collected, slots, accessories),
            hasComposition = output.hasComposition,
            duplicateOf = deduped.duplicateOf,
        )
    }

    /** 只算总倍率（「按推荐填满」的内层循环用；strict＝推荐口径）；没有构成时为 1。 */
    fun totalOf(config: LoadoutConfig, strict: Boolean = false): Double {
        val collected = collectSources(config)
        val options = if (strict) EvalOptions.STRICT else EvalOptions.STANDARD
        val winners = dedupeItems(evaluateMerged(mergeSources(collected.sources), config, options)).winners
        return TypeTables.weighted(productTable(winners), output.shares) ?: 1.0
    }

    private fun evaluateMerged(merged: List<MergedSource>, config: LoadoutConfig, options: EvalOptions): List<EvaluatedEntry> =
        merged.map { source ->
            val item = evaluateEntry(source.entry, config, options, source.toEvalSource())
            if (source.invalid) {
                item.copy(state = EntryState.RELIC_INVALID, reasons = listOf(RankerText.t("reasonRelicInvalid")))
            } else {
                item
            }
        }

    // ============================================================ 提示与超限

    /**
     * 提示（两端同一顺序）：互斥键压掉 → 同一效果多份只算一份 → stackSelf 多份相乘 → 同族不同档位相乘
     * → 不同叠层阶梯相乘 → 遗物 exclusivityId → 同一件固定遗物装了两件。
     */
    private fun configWarnings(deduped: Deduped, config: LoadoutConfig, caps: SlotCaps): List<LoadoutWarning> {
        val warnings = ArrayList<LoadoutWarning>()
        val items = deduped.items
        val winners = deduped.winners
        val losersByKey = LinkedHashMap<String, MutableList<Int>>()
        items.forEachIndexed { position, item ->
            if (item.state == EntryState.DUPLICATE) losersByKey.getOrPut(item.entry.key) { ArrayList() } += position
        }
        for ((key, losers) in losersByKey) {
            val winner = deduped.duplicateOf[losers.first()] ?: continue
            val names = ArrayList<String>()
            losers.forEach { position -> items[position].entry.name.let { if (it !in names) names += it } }
            if (losers.all { isPriorityWin(winner, items[it]) }) {
                warnings += LoadoutWarning("priority", RankerText.f("warnPriority", key, winner.entry.name, names.joinToString("、")))
            } else {
                val all = arrayListOf(winner.entry.name)
                names.forEach { if (it !in all) all += it }
                warnings += LoadoutWarning(
                    "duplicate", RankerText.f("warnDuplicateKey", key, losers.size + 1, all.joinToString("、")),
                )
            }
        }
        val single = winners.filter { it.copies > 1 && it.countedCopies == 1 }
        if (single.isNotEmpty()) {
            warnings += LoadoutWarning("copiesSingle", RankerText.f("warnCopiesSingle", single.joinToString("、") { it.entry.name }))
        }
        val multiplied = winners.filter { it.countedCopies > 1 }
        if (multiplied.isNotEmpty()) {
            warnings += LoadoutWarning(
                "copiesStackSelf",
                RankerText.f("warnCopiesStackSelf", multiplied.joinToString("、") { it.entry.name + " ×" + it.countedCopies }),
            )
        }
        val byFamily = LinkedHashMap<String, MutableList<EvaluatedEntry>>()
        winners.forEach { byFamily.getOrPut(it.entry.family) { ArrayList() } += it }
        for (group in byFamily.values) {
            if (group.map { it.entry.key }.toSet().size < 2) continue
            warnings += LoadoutWarning(
                "tiers",
                RankerText.f("warnTiers", LoadoutText.familyName(group.first().entry.name), group.joinToString("、") { it.entry.name }),
            )
        }
        val ladders = winners.filter { it.entry.stackInput?.isLadder == true }
        if (ladders.map { it.entry.key }.toSet().size >= 2) {
            warnings += LoadoutWarning("ladders", RankerText.f("warnLadders", ladders.joinToString("、") { it.entry.name }))
        }
        // relicAffixes[].exclusivityId（已装备的几件遗物之间互斥）：同组不同词条同时计入时提示。
        val exclusivityAttach = LinkedHashMap<Int, MutableSet<Int>>()
        val exclusivityNames = HashMap<Int, MutableList<String>>()
        for (item in winners) {
            if (item.column != SummaryColumn.RELIC) continue
            for (exclusivityId in item.entry.exclusivityIds) {
                val attach = exclusivityAttach.getOrPut(exclusivityId) { LinkedHashSet() }
                val names = exclusivityNames.getOrPut(exclusivityId) { ArrayList() }
                attach += item.entry.relicAttachIds
                if (item.entry.name !in names) names += item.entry.name
            }
        }
        for ((exclusivityId, attach) in exclusivityAttach) {
            if (attach.size < 2) continue
            warnings += LoadoutWarning(
                "exclusivity",
                RankerText.f("warnExclusivity", exclusivityNames[exclusivityId].orEmpty().joinToString("、"), exclusivityId),
            )
        }
        val seenFixed = HashSet<String>()
        val reported = HashSet<String>()
        for (card in config.relics.take(caps.relics)) {
            if (card.type != RelicCardType.FIXED) continue
            val key = card.fixedKey ?: continue
            if (key in seenFixed && reported.add(key)) {
                val name = index.fixedRelicByKey[key]?.nameZh ?: key
                warnings += LoadoutWarning("fixedDuplicate", RankerText.f("warnFixedDuplicate", name))
            }
            seenFixed += key
        }
        return warnings
    }

    /** 超限（武器词条总数、深夜专属、护符数与重复）与不合法的自组遗物。 */
    private fun configViolations(collected: CollectedSources, slots: SlotUsage, accessories: List<Int>): List<String> {
        val list = ArrayList<String>()
        val caps = collected.caps
        val usage = slots.weaponAffix
        if (usage.used > usage.cap) list += RankerText.f("violationWeaponAffix", usage.used, caps.runMode.titleZh, usage.cap)
        if (usage.deepOnlyUsed > usage.deepOnlyCap) {
            list += if (caps.runMode == RunMode.NORMAL) {
                RankerText.f("violationDeepOnlyInNormal", usage.deepOnlyUsed)
            } else {
                RankerText.f("violationDeepOnly", usage.deepOnlyUsed, usage.deepOnlyCap)
            }
        }
        if (accessories.size > slots.accessory.cap) list += RankerText.f("violationAccessory", accessories.size, slots.accessory.cap)
        if (accessories.toSet().size != accessories.size) list += RankerText.t("violationAccessoryDuplicate")
        collected.relicChecks.forEachIndexed { cardIndex, check ->
            if (check.isInvalid) list += RankerText.f("violationRelic", caps.relicCardLabel(cardIndex), check.message)
        }
        return list
    }

    // ============================================================ 候选

    /** 一项候选（一条词条 / 一件遗物 / 一个护符 / 一行其它增益）单独放进来的评估。 */
    fun candidateScore(
        entries: List<BuffRankerEntry>,
        column: SummaryColumn,
        auto: Boolean,
        config: LoadoutConfig,
    ): CandidateScore {
        val source = EvalSource(column = column, copies = 1, autoConfirm = column == SummaryColumn.OTHER && !auto, auto = auto)
        fun run(options: EvalOptions): Triple<List<EvaluatedEntry>, Double?, Double> {
            val deduped = dedupeItems(entries.map { evaluateEntry(it, config, options, source) })
            val flat = deduped.winners.sumOf { it.flat }
            return Triple(deduped.items, TypeTables.weighted(productTable(deduped.winners), output.shares), flat)
        }
        val (items, currentTotal, _) = run(EvalOptions.STANDARD)
        val (potentialItems, potentialTotal, potentialFlat) = run(EvalOptions(assumeAll = true))
        var best: EntryState? = null
        var reasons: List<String> = emptyList()
        for (item in items) {
            val current = best
            if (current == null || stateRank(item.state) < stateRank(current)) {
                best = item.state
                reasons = item.reasons
            }
        }
        val applicable = items.any {
            it.state != EntryState.NO && it.state != EntryState.CONTEXT && it.state != EntryState.VARIANT_OFF &&
                it.state != EntryState.NO_DAMAGE
        }
        val needs = items.any {
            it.state == EntryState.PENDING || it.state == EntryState.ZERO_STACKS || it.state == EntryState.TIER_OFF
        }
        val oneStack = potentialItems.any { it.assumedOneStack && it.state == EntryState.COUNTED }
        val score = currentTotal ?: 1.0
        val potential = potentialTotal ?: 1.0
        return CandidateScore(
            items = items, score = score, potential = potential, flat = potentialFlat,
            state = best ?: EntryState.NO_DAMAGE, reasons = reasons, applicable = applicable, needsConfirmation = needs,
            assumesOneStack = oneStack && Math.abs(potential - score) > RANK_EPSILON,
        )
    }

    /** 武器词条栏的行：[filterType]＝null 表示「全部类别」；已选的一律列出。按有效倍率排序。 */
    fun weaponAffixRows(config: LoadoutConfig, filterType: Int?): List<WeaponAffixRow> {
        val rows = ArrayList<WeaponAffixRow>()
        for (affix in index.weaponAffixes) {
            val count = config.weaponAffixCount(affix.id)
            if (count == 0 && !affix.isAvailable(config.runMode)) continue
            val matches = affix.matchesType(config.runMode, filterType)
            if (count == 0 && !matches) continue
            rows += WeaponAffixRow(
                affix, count, outsideFilter = count > 0 && !matches, can = index.canAddWeaponAffix(config, affix.id),
                score = candidateScore(affix.entries, SummaryColumn.WEAPON_AFFIX, false, config),
            )
        }
        return sortRowsByScore(rows)
    }

    /** 自组遗物某一行的候选词条（按口径过滤），按有效倍率排序。 */
    fun relicAffixRows(config: LoadoutConfig, kind: RelicKind): List<RelicAffixRow> = sortRowsByScore(
        index.relicCandidates[kind].orEmpty().map { RelicAffixRow(it, candidateScore(it.entries, SummaryColumn.RELIC, false, config)) },
    )

    /** 固定遗物候选（普通遗物格只列普通固定遗物，深夜格只列深夜固定遗物）。 */
    fun fixedRelicRows(config: LoadoutConfig, kind: RelicKind): List<FixedRelicRow> = sortRowsByScore(
        index.fixedRelics.filter { it.isDeepRelic == (kind == RelicKind.DEEP) }
            .map { FixedRelicRow(it, candidateScore(it.entries, SummaryColumn.RELIC, false, config)) },
    )

    fun talismanRows(config: LoadoutConfig): List<TalismanRow> = sortRowsByScore(
        index.talismans.map { TalismanRow(it, candidateScore(it.entries, SummaryColumn.ACCESSORY, false, config)) },
    )

    /** 其它增益某一分栏的行（当前武器固有标 auto；勾掉＝排除）。 */
    fun otherRowsFor(config: LoadoutConfig, slot: String): List<OtherRowScore> = sortRowsByScore(
        index.otherRows[slot].orEmpty().map { row ->
            val auto = row.entries.any { it.id in currentInnateIds }
            val selected = if (auto) !row.entries.all { it.id in config.innateOff } else row.key in config.others
            OtherRowScore(row, auto, selected, candidateScore(row.entries, SummaryColumn.OTHER, auto, config))
        },
    )

    /**
     * 其它增益某一分栏实际列出的行（Windows otherListHtml 的筛选与排序）：选中的一律列出；没选的按「对当前输出
     * 有收益」过滤（[showInactive] 时不过滤）与搜索词（[foldedQuery] 已 foldedForSearch）过滤；角色栏按角色名分组
     * （组内当前倍率降序、再按行键），武器固有栏当前武器自带的在前。分组标题见 [otherRowGroup]。
     */
    fun shownOtherRows(
        config: LoadoutConfig,
        slot: String,
        foldedQuery: String = "",
        showInactive: Boolean = false,
    ): List<OtherRowScore> {
        val shown = otherRowsFor(config, slot).filter { row ->
            when {
                row.selected -> true
                !showInactive && !row.score.isUseful(output.hasComposition) -> false
                else -> row.row.matches(foldedQuery)
            }
        }
        return when (slot) {
            "character" -> shown.stableSortedWith { a, b ->
                val ga = otherRowGroup(a, slot).orEmpty()
                val gb = otherRowGroup(b, slot).orEmpty()
                when {
                    ga != gb -> ga.compareTo(gb)
                    b.score.score != a.score.score -> b.score.score.compareTo(a.score.score)
                    else -> a.row.key.compareTo(b.row.key)
                }
            }
            "weaponInnate" -> shown.stableSortedWith { a, b -> if (a.auto == b.auto) 0 else if (a.auto) -1 else 1 }
            else -> shown
        }
    }

    /** 其它增益行的分组标题：角色栏＝角色名（characterNames.*）；武器固有栏＝当前武器自带 / 其它武器；其余为 null。 */
    fun otherRowGroup(row: OtherRowScore, slot: String = row.row.slot): String? = when (slot) {
        "character" -> BuffRankerIndex.characterLabel(row.row.first.character)
        "weaponInnate" -> RankerText.t(if (row.auto) "groupAutoInnate" else "groupOtherInnate")
        else -> null
    }

    /**
     * 勾选 / 取消其它增益栏的一行。当前武器固有：勾掉＝排除。勾上不占槽位的叠层 / 累积阶梯时，没填过层数就先填
     * 一局实际上限（没有就 1 层），没选过层就先选数据里收录的最高层（两端同一口径）。
     */
    fun toggleOtherRow(config: LoadoutConfig, rowKey: Int, checked: Boolean): LoadoutConfig {
        val row = index.otherRow(rowKey) ?: return config
        if (row.entries.any { it.id in currentInnateIds }) {
            val ids = row.entries.map { it.id }
            return config.copy(innateOff = if (checked) config.innateOff - ids.toSet() else config.innateOff + ids)
        }
        if (!checked) return config.copy(others = config.others - rowKey)
        var next = config.copy(others = config.others + rowKey)
        for (entry in row.entries) {
            val input = entry.stackInput ?: continue
            if (next.stacks(entry.id) <= 0) next = next.copy(stackCounts = next.stackCounts + (entry.id to input.defaultStacks))
        }
        val first = row.entries.first()
        val group = first.ladderGroup
        if (first.accLadder != null && group != null && ranker.selectedLadderTier(first, next).id == null) {
            index.ladderTopTier(group)?.let { next = next.withLadderTier(group, it.id) }
        }
        return next
    }

    /** 累积阶梯的选层控件只放在一行上：有计入的那一层就放在那一层，否则放在第 1 层（两端同一口径）。 */
    fun isLadderOwner(item: EvaluatedEntry, config: LoadoutConfig): Boolean {
        val entry = item.entry
        if (entry.accLadder == null) return false
        val members = index.ranker.ladderMembers(entry.ladderGroup)
        val picked = entry.ladderGroup?.let { config.ladderChoice(it) }
        if (members.any { it.id == picked }) return picked == entry.id
        return members.firstOrNull()?.id?.let { it == entry.id } ?: true
    }

    /** 某一处列出的条目：未选的档（variantOff）与不含伤害的不列，累积阶梯没选层时只留放选层控件的那一行。 */
    fun visibleItems(items: List<EvaluatedEntry>, config: LoadoutConfig): List<EvaluatedEntry> = items.filter { item ->
        when (item.state) {
            EntryState.VARIANT_OFF, EntryState.NO_DAMAGE -> false
            EntryState.TIER_OFF -> isLadderOwner(item, config)
            else -> true
        }
    }

    /** 「全部增益一览」（与配置无关）。 */
    fun overview(): List<OverviewRow> = ranker.overview(output)

    fun attackContextOptions(): List<AttackContextOption> = ranker.attackContextOptions(output.outputClass)

    // ============================================================ 按推荐填满

    /** 这项候选在推荐口径下能不能贡献（有没有一条会计入）：没有的不必试（结果不变，只为快）。 */
    private fun strictCounts(entries: List<BuffRankerEntry>, column: SummaryColumn, config: LoadoutConfig): Boolean =
        entries.any { evaluateEntry(it, config, EvalOptions.STRICT, EvalSource(column = column)).state == EntryState.COUNTED }

    /**
     * 按推荐填满（两端同一口径）：只填空槽、不改已选；顺序 武器词条 → 遗物逐格 → 护符；每一步取让推荐口径总倍率
     * 增幅最大的候选，同增幅取 ID 小的，增幅 ≤ 1e-9 就停。推荐口径不计条件型、要确认的、叠层与累积阶梯。
     * [filterType]：武器词条按类别过滤（null＝全部；页面默认传 output.attackWepType）。没有构成时什么都不做。
     */
    fun recommendFill(config: LoadoutConfig, filterType: Int?): FillResult {
        var next = config
        val added = ArrayList<FillAddition>()
        if (!output.hasComposition) return FillResult(next, added)
        var best = totalOf(next, strict = true)
        val caps = index.caps(next.runMode)

        // ① 武器词条：可以同一条多份（stackSelf 的各份相乘），受总上限与深夜专属上限约束。
        val weaponPool = index.weaponAffixes.filter { affix ->
            affix.isAvailable(next.runMode) && affix.matchesType(next.runMode, filterType) &&
                strictCounts(affix.entries, SummaryColumn.WEAPON_AFFIX, next)
        }
        while (true) {
            var choice: Pair<WeaponAffixOption, Double>? = null
            for (affix in weaponPool) {
                if (!index.canAddWeaponAffix(next, affix.id).ok) continue
                val value = totalOf(index.stepWeaponAffix(next, affix.id, 1), strict = true)
                if (value > (choice?.second ?: best) + RANK_EPSILON) choice = affix to value
            }
            val picked = choice ?: break
            next = index.stepWeaponAffix(next, picked.first.id, 1)
            best = picked.second
            added += FillAddition(SummaryColumn.WEAPON_AFFIX, picked.first.label)
        }

        // ② 遗物：逐个空格比较「最好的固定遗物」与「贪心自组」，分数相同取固定遗物。
        for (cardIndex in 0 until caps.relics) {
            if (next.relic(cardIndex).isFilled) continue
            val kind = caps.relicKind(cardIndex)
            val usedFixed = (0 until caps.relics).mapNotNullTo(HashSet()) { i ->
                next.relic(i).takeIf { it.type == RelicCardType.FIXED }?.fixedKey
            }
            var cardBest: Triple<RelicCard, Double, String>? = null
            for (relic in index.fixedRelics) {
                if (relic.isDeepRelic != (kind == RelicKind.DEEP) || relic.key in usedFixed) continue
                if (!strictCounts(relic.entries, SummaryColumn.RELIC, next)) continue
                val card = RelicCard.fixed(relic.key)
                val value = totalOf(next.withRelic(cardIndex, card), strict = true)
                if (value > (cardBest?.second ?: best) + RANK_EPSILON) cardBest = Triple(card, value, relic.nameZh)
            }
            val custom = greedyCustomRelic(next, cardIndex, kind, best)
            if (custom != null && custom.second > (cardBest?.second ?: best) + RANK_EPSILON) cardBest = custom
            val chosen = cardBest ?: continue
            next = next.withRelic(cardIndex, chosen.first)
            best = chosen.second
            added += FillAddition(SummaryColumn.RELIC, caps.relicCardLabel(cardIndex) + "：" + chosen.third)
        }

        // ③ 护符：不重复，取增幅最大的，填进第一个空格。
        while (true) {
            val slots = next.accessories.take(caps.accessory)
            var slot = slots.indexOf(null)
            if (slot == -1 && slots.size < caps.accessory) slot = slots.size
            if (slot == -1) break
            var pick: Pair<TalismanOption, Double>? = null
            for (talisman in index.talismans) {
                if (talisman.id in next.accessories) continue
                if (!strictCounts(talisman.entries, SummaryColumn.ACCESSORY, next)) continue
                val value = totalOf(next.withAccessory(slot, talisman.id), strict = true)
                if (value > (pick?.second ?: best) + RANK_EPSILON) pick = talisman to value
            }
            val chosen = pick ?: break
            next = next.withAccessory(slot, chosen.first.id)
            best = chosen.second
            added += FillAddition(SummaryColumn.ACCESSORY, chosen.first.nameZh)
        }
        return FillResult(next, added)
    }

    /**
     * 贪心自组一件遗物：逐行挑「加进去后仍合法（或预检通过）、且总倍率增幅最大」的词条（同增幅取 ID 小的），
     * 深夜需诅咒的词条先配一条诅咒（pickCurse），最多三行；没有正增益就停。
     */
    private fun greedyCustomRelic(config: LoadoutConfig, cardIndex: Int, kind: RelicKind, base: Double): Triple<RelicCard, Double, String>? {
        val candidates = index.relicCandidates[kind].orEmpty().filter { strictCounts(it.entries, SummaryColumn.RELIC, config) }
        if (candidates.isEmpty()) return null
        var card = RelicCard.custom()
        var total = base
        val names = ArrayList<String>()
        for (row in 0 until RelicCard.ROWS) {
            var step: Triple<RelicCard, Double, String>? = null
            for (candidate in candidates) {
                if (candidate.id in card.customAffixIds) continue
                var trialCard = card.withRow(row, candidate.id, card.curseAt(row))
                if (kind == RelicKind.DEEP && candidate.affix.requiresCurse) {
                    val curse = index.pickCurse(trialCard, row) ?: continue
                    trialCard = trialCard.withCurse(row, curse)
                }
                if (index.checkCustomRelic(trialCard, kind).isInvalid) continue
                val value = totalOf(config.withRelic(cardIndex, trialCard), strict = true)
                if (value > (step?.second ?: total) + RANK_EPSILON) step = Triple(trialCard, value, candidate.name)
            }
            val chosen = step ?: break
            card = chosen.first
            total = chosen.second
            names += chosen.third
        }
        if (names.isEmpty()) return null
        return Triple(card, total, names.joinToString("＋"))
    }

    // ============================================================ 小工具

    internal class Deduped(
        val items: List<EvaluatedEntry>,
        val winners: List<EvaluatedEntry>,
        /** 被压掉的（items 下标）→ 留下的那一条。 */
        val duplicateOf: Map<Int, EvaluatedEntry>,
    )

    companion object {
        /** 候选行「最接近生效」的状态排序（Windows STATE_RANK）。 */
        private val STATE_RANK: Map<EntryState, Int> = mapOf(
            EntryState.COUNTED to 0, EntryState.PENDING to 1, EntryState.ZERO_STACKS to 2, EntryState.TIER_OFF to 3,
            EntryState.CONTEXT to 4, EntryState.NEUTRAL to 5, EntryState.DUPLICATE to 6, EntryState.NO to 7,
            EntryState.VARIANT_OFF to 8, EntryState.RELIC_INVALID to 9, EntryState.NO_DAMAGE to 10,
        )

        private fun stateRank(state: EntryState): Int = STATE_RANK[state] ?: 99

        /** 同一个 spEffectId 从多处来的合并成一条（份数相加、来源并列）；不合法自组遗物里的单独成条（放在最后）。 */
        fun mergeSources(sources: List<ConfigSource>): List<MergedSource> {
            val merged = ArrayList<MergedSource>()
            val position = HashMap<Int, Int>()
            val invalid = ArrayList<MergedSource>()
            for (source in sources) {
                if (source.invalid) {
                    invalid += MergedSource(
                        source.entry, source.column, maxOf(1, source.copies), listOf(source.label), listOf(source.key),
                        autoConfirm = false, auto = false, invalid = true,
                    )
                    continue
                }
                val at = position[source.entry.id]
                if (at == null) {
                    position[source.entry.id] = merged.size
                    merged += MergedSource(
                        source.entry, source.column, maxOf(1, source.copies), listOf(source.label), listOf(source.key),
                        autoConfirm = source.autoConfirm, auto = source.auto, invalid = false,
                    )
                } else {
                    val one = merged[at]
                    merged[at] = one.copy(
                        copies = one.copies + maxOf(1, source.copies),
                        labels = if (source.label in one.labels) one.labels else one.labels + source.label,
                        keys = if (source.key in one.keys) one.keys else one.keys + source.key,
                        autoConfirm = one.autoConfirm || source.autoConfirm,
                        auto = one.auto && source.auto,
                    )
                }
            }
            return merged + invalid
        }

        /**
         * 同键谁留下：两边都是 applyHighest 且 categoryPriority 不同 → 数值小的；否则有效倍率高的；再比加算；
         * 再比 spEffectId 小的；完全并列时先出现的留下。
         */
        fun prefers(candidate: EvaluatedEntry, current: EvaluatedEntry): Boolean {
            val a = candidate.entry
            val b = current.entry
            if (a.behavior == "applyHighest" && b.behavior == "applyHighest" && a.categoryPriority != b.categoryPriority) {
                return a.categoryPriority < b.categoryPriority
            }
            val am = candidate.multiplier ?: 1.0
            val bm = current.multiplier ?: 1.0
            if (Math.abs(am - bm) > RANK_EPSILON) return am > bm
            if (Math.abs(candidate.flat - current.flat) > RANK_EPSILON) return candidate.flat > current.flat
            if (a.id != b.id) return a.id < b.id
            return false
        }

        fun isPriorityWin(winner: EvaluatedEntry, loser: EvaluatedEntry): Boolean =
            winner.entry.behavior == "applyHighest" && loser.entry.behavior == "applyHighest" &&
                winner.entry.categoryPriority != loser.entry.categoryPriority

        /** 按 exclusiveKey 去重：被压掉的改成 DUPLICATE 并写明原因；返回全部条目与留下的（按互斥键第一次出现的顺序）。 */
        internal fun dedupeItems(items: List<EvaluatedEntry>): Deduped {
            val winnerIndex = LinkedHashMap<String, Int>()
            items.forEachIndexed { position, item ->
                if (item.state != EntryState.COUNTED) return@forEachIndexed
                val current = winnerIndex[item.entry.key]
                if (current == null || prefers(item, items[current])) winnerIndex[item.entry.key] = position
            }
            val out = items.toMutableList()
            val duplicateOf = HashMap<Int, EvaluatedEntry>()
            items.forEachIndexed { position, item ->
                if (item.state != EntryState.COUNTED) return@forEachIndexed
                val key = item.entry.key
                val winnerAt = winnerIndex.getValue(key)
                if (winnerAt == position) return@forEachIndexed
                val winner = items[winnerAt]
                val reason = if (isPriorityWin(winner, item)) {
                    RankerText.f(
                        "reasonDupPriority", winner.entry.name, key, winner.entry.categoryPriority, item.entry.categoryPriority,
                    )
                } else {
                    RankerText.f("reasonDupKey", winner.entry.name, key)
                }
                out[position] = item.copy(state = EntryState.DUPLICATE, reasons = listOf(reason))
                duplicateOf[position] = winner
            }
            return Deduped(out, winnerIndex.values.map { out[it] }, duplicateOf)
        }

        internal fun productTable(items: List<EvaluatedEntry>): List<Double> {
            val table = TypeTables.filled(1.0)
            for (item in items) for (i in 0 until DamageType.COUNT) table[i] *= item.table[i]
            return table.asList()
        }

        /** 一栏的汇总：计入条目逐类型连乘后按构成加权，加算逐类型相加后按占比加权。 */
        fun columnSummary(items: List<EvaluatedEntry>, shares: List<Double>): ColumnSummary {
            val counted = items.filter { it.state == EntryState.COUNTED }
            val table = productTable(counted)
            val flat = TypeTables.filled(0.0)
            for (item in counted) for (i in 0 until DamageType.COUNT) flat[i] += item.flatTable[i]
            return ColumnSummary(counted.size, table, TypeTables.weighted(table, shares), TypeTables.weightedFlat(flat.asList(), shares))
        }

        /** 排序（两端同一口径）：生效的在前 → 当前倍率降序 → 条件成立时倍率降序 → ID 升序（稳定）。 */
        fun <T : ScoredRow> sortRowsByScore(rows: List<T>): List<T> = rows.stableSortedWith { a, b ->
            val sa = a.score
            val sb = b.score
            when {
                sa.applicable != sb.applicable -> if (sa.applicable) -1 else 1
                Math.abs(sb.score - sa.score) > RANK_EPSILON -> if (sb.score > sa.score) 1 else -1
                Math.abs(sb.potential - sa.potential) > RANK_EPSILON -> if (sb.potential > sa.potential) 1 else -1
                else -> a.sortId.compareTo(b.sortId)
            }
        }
    }
}
