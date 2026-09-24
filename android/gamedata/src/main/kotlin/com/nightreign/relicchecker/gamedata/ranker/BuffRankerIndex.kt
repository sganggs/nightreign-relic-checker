package com.nightreign.relicchecker.gamedata.ranker

import com.nightreign.relicchecker.gamedata.GameDataFormatException
import com.nightreign.relicchecker.rules.foldedForSearch

// 增伤排名的核心：每条 buff 的预计算（BuffRankerEntry）、对当前输出手段的 appliesTo 判定（verdict）、
// 单条评估（evaluate）与「全部增益一览」（overview）。
//
// **两端同一口径**（macOS：RelicCore/BuffLoadout.swift 的 BuffLoadoutIndex.verdict / LoadoutEvaluator.evaluate /
// overview；Windows：renderer/pages/ranker.js 的 indexBuff / appliesVerdict / evaluateEntry / overviewRows）：
//   · 生效判定一律用 buffs[].appliesTo[输出类别]（战技 → skill，含子弹段；魔法 → sorcery；祷告 → incantation）。
//     conditional 看 requires：hand / attackWeaponTypes（法术按施法器）/ physicalType 自动判定，subCategoriesAny
//     用 attackIndex 判定（部分段命中按 1＋(倍率−1)×命中段占比近似），attackContexts 用「攻击情境」勾选，
//     imbuedWeaponOnly / attachedWeaponOnly / requiresGoodsIds / 认不出的键要用户确认。
//   · 作用对象只留 self / ally（selfAllyPair 的 Allies 那一行不算施放者自己）；direction=decrease 一律不计入。
//   · activation ≠ passive 与要确认的条件默认不计入（占槽位的栏放进来 ≠ 条件成立）；叠层填层数、累积阶梯选层同样算确认。
//   · 多档词条（affixVariant）只算选中的一档（默认第 1 档）。
//   · 有效倍率 = Σ 占比_type × 倍率_type / Σ 占比（攻击力倍率层与最终伤害倍率层相乘，物理子类型倍率只乘对应那一部分）。
// 每条 buff 的九类倍率表与加算表只跟它自己的 rates 有关，建索引时一次算好；换输出手段只做判定与 9 格加权。

/** 一条 buff 与输出手段无关的预计算结果（Windows indexBuff）。 */
class BuffRankerEntry internal constructor(
    val buff: BuffEntry,
    /** 九类伤害上的倍率（damage 层 × attackPower 层；scope.atkAttribute 限定时只落在那一个物理通道）。 */
    val multiplier: List<Double>,
    /** 九类伤害上的攻击力加算点数。 */
    val flat: List<Double>,
    val usedMultiplier: List<RateUse>,
    val usedFlat: List<RateUse>,
    /** 不 countsAsDamage 的字段（「另有不计入伤害的字段」提示用）。 */
    val otherRateKeys: List<String>,
    val hasMultiplier: Boolean,
    val hasFlat: Boolean,
    /** scope.atkAttribute（0–3）：倍率只落在这一个物理通道。 */
    val scopeRestricted: DamageType?,
    /** 同族键（Paramdex 行名去掉档位后缀）：只用来提示「不同档位同时计入」，不参与去重。 */
    val family: String,
    /** 角色分组键（[Skill - Revenant] → Revenant）；不是 character 栏的为空串。 */
    val character: String,
    /** 列表搜索用的折叠串（显示层过滤，不参与计算）。 */
    val searchText: String,
) {
    val id: Int get() = buff.spEffectId

    /** 列表一律显示 displayNameZh（notes.displayName：nameZh 重名极多）。 */
    val name: String get() = buff.displayName
    val paramName: String get() = buff.paramName.orEmpty()
    val rates: Map<String, Double> get() = buff.rates

    /** 带 countsAsDamage 的倍率或加算字段。 */
    val countsAsDamage: Boolean get() = hasMultiplier || hasFlat
    val target: String get() = buff.target
    val activation: String get() = buff.activation
    val direction: String get() = buff.direction
    val duration: Double get() = buff.duration

    /** 能进配置页各栏与一览的条目：带伤害倍率字段、作用于自己或队友、不是减益。 */
    val listable: Boolean = countsAsDamage && (buff.target == "self" || buff.target == "ally") && buff.direction != "decrease"

    val slot: String get() = buff.sourceSlot.ifEmpty { "other" }
    val slots: List<String> get() = buff.sourceSlots.ifEmpty { listOf(slot) }

    /** 互斥键（stacking.exclusiveKey；缺失时退回 group，再退回 sp<cat>#<id>）。 */
    val key: String get() = buff.exclusiveKey
    val exclusiveScope: String get() = buff.stacking.exclusiveScope
    val behavior: String get() = buff.stacking.spCategoryBehavior
    val spCategory: Int get() = buff.stacking.spCategory
    val categoryPriority: Int get() = buff.stacking.categoryPriority

    /**
     * 同一 spEffectId 多份：stackSelf 且按 ID 互斥（exclusiveScope=perSpEffect）的各份相乘；多档词条
     * （exclusiveScope=affixVariant）同一词条装两件也只算一份（notes.affixVariant）。
     */
    val copiesMultiply: Boolean
        get() = behavior == "stackSelf" && (exclusiveScope.isEmpty() || exclusiveScope == "perSpEffect")

    val stackInput: BuffStackInput? get() = buff.stackInput
    val accLadder: BuffAccumulatorLadder? get() = buff.accumulatorLadder

    /** 累积阶梯组 id（第 1 层的 spEffectId）；不是累积阶梯为 null。 */
    val ladderGroup: Int? get() = buff.accumulatorLadder?.ladderId
    val ladderTier: Int get() = buff.accumulatorLadder?.tier ?: 0
    val innate: BuffWeaponInnate? get() = buff.weaponInnate

    /** 多档词条的组键（affixVariant.key）；不是多档词条为 null。 */
    val variantGroup: String? get() = buff.affixVariant?.groupKey
    val variantTier: Int get() = buff.affixVariant?.variant ?: 0

    /** selfAllyPair 的角色：self / ally；不成对为 null。 */
    val pairRole: String? get() = buff.selfAllyPair?.role?.takeIf { it == "self" || it == "ally" }
    val goodsIds: List<Int> get() = buff.requiresGoodsIds

    /**
     * 道具等级（v6 goodsLevel，缺省＝1 级；Windows indexBuff 的 goodsLevel）：2／3 级只来自学者的能力「携物知识」，
     * 只用来标「携物知识 N 级」（[LoadoutText.goodsLevelTag]），不参与计算。
     */
    val goodsLevel: Int get() = buff.goodsLevel ?: 1

    /** 「装备 N 把以上 X 类武器」（scope.weaponTypes.mode=equippedCount）。 */
    val equipped: BuffWeaponTypes? get() = buff.scope.weaponTypes?.takeIf { it.mode == "equippedCount" }
    val relicAttachIds: List<Int> get() = buff.relicAffixes.map { it.attachEffectId }
    val exclusivityIds: List<Int> get() = buff.relicAffixes.map { it.exclusivityId }.filter { it >= 0 }
    val hasInferredSource: Boolean get() = buff.hasInferredSource
    val selfInflictedStatus: Boolean get() = buff.selfInflictedStatus

    fun matches(foldedQuery: String): Boolean = foldedQuery.isEmpty() || searchText.contains(foldedQuery)

    override fun toString(): String = "BuffRankerEntry(#$id $name)"
}

/**
 * buffs 数据集的索引（一次建好、不可变；解析在 IO 线程完成）。换输出手段只调 [verdict] / [evaluate] / [overview]。
 */
class BuffRankerIndex(val dataset: BuffDataset) {
    val plan: RateFieldPlan = RateFieldPlan.from(dataset.rateFields)
    val entries: List<BuffRankerEntry>
    val byId: Map<Int, BuffRankerEntry>

    /** 多档词条：组键 → 按档位（再按 id）排好序的整组（只读数据的 affixVariant，不按 compatibilityId 或行名猜）。 */
    val variants: Map<String, List<BuffRankerEntry>>

    /** 累积阶梯：组 id（第 1 层的 spEffectId）→ 能进计算的各层（按层、再按 id 升序）。 */
    val ladders: Map<Int, List<BuffRankerEntry>>

    /** requiresGoodsIds 的道具名：取 sources[].kind=goods 且 id 相同的中文名。 */
    val goodsNames: Map<Int, String>

    init {
        if (dataset.buffs.isEmpty()) throw GameDataFormatException("增益数据里没有任何 buff 记录")
        val list = dataset.buffs.map { indexEntry(it, plan) }
        entries = list
        byId = list.associateByFirst { it.id }

        val variantGroups = LinkedHashMap<String, MutableList<BuffRankerEntry>>()
        val ladderGroups = LinkedHashMap<Int, MutableList<BuffRankerEntry>>()
        val goods = LinkedHashMap<Int, String>()
        for (entry in list) {
            entry.variantGroup?.let { variantGroups.getOrPut(it) { ArrayList() } += entry }
            val group = entry.ladderGroup
            if (group != null && entry.listable) ladderGroups.getOrPut(group) { ArrayList() } += entry
            for (source in entry.buff.sources) {
                val id = source.id ?: continue
                val name = source.nameZh ?: continue
                if (source.kind == "goods" && name.isNotEmpty() && id !in goods) goods[id] = name
            }
        }
        variants = variantGroups.mapValues { (_, members) ->
            members.sortedWith(compareBy<BuffRankerEntry> { it.variantTier }.thenBy { it.id })
        }
        ladders = ladderGroups.mapValues { (_, members) ->
            members.sortedWith(compareBy<BuffRankerEntry> { it.ladderTier }.thenBy { it.id })
        }
        goodsNames = goods
    }

    /** 能进计算的条目（配置页各栏与一览只收这些）。 */
    val listableEntries: List<BuffRankerEntry> by lazy(LazyThreadSafetyMode.PUBLICATION) { entries.filter { it.listable } }

    fun entry(spEffectId: Int): BuffRankerEntry? = byId[spEffectId]

    fun variantMembers(entry: BuffRankerEntry): List<BuffRankerEntry> =
        entry.variantGroup?.let { variants[it] }.orEmpty()

    fun ladderMembers(groupId: Int?): List<BuffRankerEntry> = groupId?.let { ladders[it] }.orEmpty()

    /** 这条累积阶梯实际收录的最高层（「条件成立时」与勾选预填都取它）。 */
    fun ladderTopTier(groupId: Int?): BuffRankerEntry? = ladderMembers(groupId).lastOrNull()

    // ============================================================ 文案小工具

    fun wepTypeLabel(wepType: Int): String =
        dataset.enums.wepType[wepType]?.takeIf { it.isNotEmpty() } ?: RankerText.f("wepTypeFallback", wepType)

    /** 「[111 蓄力战技攻击、112 战技攻击]」。 */
    fun subCategoryLabel(subs: List<Int>): String = "[" + subs.joinToString("、") { sub ->
        val label = dataset.enums.atkSubCategory[sub]
        if (label.isNullOrEmpty()) sub.toString() else "$sub $label"
    } + "]"

    fun handName(hand: Int): String = RankerText.t(if (hand == 2) "hand.2" else "hand.1")

    fun goodsName(id: Int): String = goodsNames[id] ?: RankerText.f("goodsFallback", id)

    /** 发动条件的说明：发动型 / 条件型；「装备三把以上 X」写出数量与类别；被动为 null。 */
    fun activationNote(entry: BuffRankerEntry): String? {
        if (entry.activation == "passive") return null
        if (entry.activation == "activated") return RankerText.t("activationNeed.activated")
        val equipped = entry.equipped
        if (equipped != null) {
            val names = equipped.namesZh.ifEmpty { equipped.wepTypes.map { wepTypeLabel(it) } }
            return RankerText.f("activationNeed.equipped", equipped.count ?: 3, names.joinToString("／"))
        }
        return RankerText.t("activationNeed.conditional")
    }

    // ============================================================ appliesTo 判定（notes.appliesTo）

    /** attackIndex 对所选战技／法术的逐段判定：(有交集的段数, 总段数)；拿不到返回 null。 */
    fun subCategoryMatch(output: RankerOutput, subs: List<Int>): Pair<Int, Int>? {
        val meansId = output.meansId ?: return null
        val table = if (output.outputClass == OutputClass.SKILL) dataset.attackIndex.skills else dataset.attackIndex.spells
        val sets = table[meansId] ?: return null
        var matched = 0
        var total = 0
        for (set in sets) {
            val hits = maxOf(0, set.hits)
            total += hits
            if (set.subs.any { it in subs }) matched += hits
        }
        return if (total > 0) matched to total else null
    }

    /** 按 appliesTo / appliesToDetail 判定一条 buff 对当前输出手段是否生效（两端同一口径、同一文案）。 */
    fun verdict(entry: BuffRankerEntry, output: RankerOutput): AppliesVerdict {
        val buff = entry.buff
        val activationNote = activationNote(entry)
        val cls = output.outputClass
        val raw = buff.appliesTo?.get(cls)?.takeIf { it.isNotEmpty() }
        val detail = buff.appliesToDetail[cls]
        val value = when (raw) {
            "yes" -> VerdictValue.YES
            "conditional" -> VerdictValue.CONDITIONAL
            null -> VerdictValue.MISSING
            else -> VerdictValue.NO
        }
        val needs = ArrayList<String>()
        val requirements = ArrayList<Requirement>()
        fun need(key: String, text: String) {
            needs += text
            requirements += Requirement(key, text, RequirementState.NEEDS_USER)
        }
        fun make(
            state: VerdictState,
            reasons: List<String> = emptyList(),
            notes: List<String> = emptyList(),
            weight: Double = 1.0,
            restricted: DamageType? = null,
            contexts: List<String> = emptyList(),
        ) = AppliesVerdict(
            value = value, state = state, reasons = reasons,
            needs = if (state == VerdictState.NO) emptyList() else needs.toList(),
            notes = notes, weight = weight, restrictedType = restricted, requirements = requirements.toList(),
            contexts = contexts, activation = buff.activation, activationNote = activationNote,
        )

        if (value != VerdictValue.YES && value != VerdictValue.CONDITIONAL) {
            val fallback = RankerText.t(if (value == VerdictValue.MISSING) "verdictMissing" else "verdictNoFallback")
            return make(VerdictState.NO, reasons = listOf(detail?.reason?.takeIf { it.isNotEmpty() } ?: fallback))
        }
        if (entry.goodsIds.isNotEmpty()) {
            need("goods", RankerText.f("requireGoods", entry.goodsIds.joinToString("／") { goodsName(it) }))
        }
        if (value == VerdictValue.YES) {
            return make(if (needs.isEmpty()) VerdictState.YES else VerdictState.PENDING)
        }

        val reason = detail?.reason.orEmpty()
        val reasonList = if (reason.isEmpty()) emptyList() else listOf(reason)
        val requires = detail?.requires
        if (requires == null || !requires.hasAnyKey) {
            need("detail", RankerText.f("requireManual", reason))
            return make(VerdictState.PENDING, reasons = reasonList)
        }
        val fails = ArrayList<String>()
        var contexts: List<String> = emptyList()
        var weight = 1.0
        val notes = ArrayList<String>()
        var restricted: DamageType? = null
        val clsTitle = cls.titleZh

        requires.hand?.let { hand ->
            val text = RankerText.f("requireHand", handName(hand), handName(output.normalizedHand))
            val ok = hand == output.normalizedHand
            requirements += Requirement("hand", text, if (ok) RequirementState.MET else RequirementState.UNMET)
            if (!ok) fails += text
        }
        if (requires.attackWeaponTypes.isNotEmpty()) {
            val names = requires.attackWeaponTypes.joinToString("／") { wepTypeLabel(it) }
            val own = output.attackWepType
            val text = if (own == null) {
                RankerText.f("requireWepTypeNoWeapon", names)
            } else {
                RankerText.f("requireWepType", names, wepTypeLabel(own))
            }
            val ok = own != null && own in requires.attackWeaponTypes
            requirements += Requirement("attackWeaponTypes", text, if (ok) RequirementState.MET else RequirementState.UNMET)
            if (!ok) fails += text
        }
        requires.physicalType?.let { code ->
            val type = DamageType.physicalOrNull(code)
            if (type != null) {
                restricted = type
                val present = !output.hasComposition || output.share(type) > 0.0
                val text = RankerText.f(if (present) "requirePhysical" else "requirePhysicalFail", type.titleZh)
                requirements += Requirement("physicalType", text, if (present) RequirementState.MET else RequirementState.UNMET)
                if (!present) fails += text
            } else {
                need("physicalType", RankerText.f("requireUnknown", "physicalType=$code"))
            }
        }
        if (requires.subCategoriesAny.isNotEmpty()) {
            val label = subCategoryLabel(requires.subCategoriesAny)
            val match = subCategoryMatch(output, requires.subCategoriesAny)
            when {
                match == null -> need("subCategoriesAny", RankerText.f("requireSubsUnknown", clsTitle, label))
                match.first == 0 -> {
                    val text = RankerText.f("requireSubsFail", clsTitle, label)
                    requirements += Requirement("subCategoriesAny", text, RequirementState.UNMET)
                    fails += text
                }
                match.first < match.second -> {
                    weight = match.first.toDouble() / match.second.toDouble()
                    val text = RankerText.f("requireSubsPartial", clsTitle, match.first, match.second, label)
                    requirements += Requirement("subCategoriesAny", text, RequirementState.PARTIAL, weight)
                    notes += text
                }
                else -> {
                    val text = RankerText.f("requireSubsAll", clsTitle, match.second, label)
                    requirements += Requirement("subCategoriesAny", text, RequirementState.MET)
                }
            }
        }
        if (requires.attackContexts.isNotEmpty()) {
            val names = requires.attackContexts.joinToString("／") { dataset.attackContextLabel(it) }
            val picked = requires.attackContexts.any { it in output.attackContexts }
            val text = RankerText.f("requireContext", names)
            requirements += Requirement("attackContexts", text, if (picked) RequirementState.MET else RequirementState.UNMET)
            if (!picked) contexts = requires.attackContexts
        }
        if (requires.imbuedWeaponOnly) need("imbuedWeaponOnly", RankerText.t("requireImbued"))
        if (requires.attachedWeaponOnly) need("attachedWeaponOnly", RankerText.t("requireAttached"))
        for (key in requires.unknownKeys) need("unknown-$key", RankerText.f("requireUnknown", key))

        if (fails.isNotEmpty()) {
            return make(VerdictState.NO, reasons = fails + reasonList, restricted = restricted)
        }
        if (contexts.isNotEmpty()) {
            val names = contexts.joinToString("／") { dataset.attackContextLabel(it) }
            return make(
                VerdictState.CONTEXT,
                reasons = listOf(RankerText.f("requireContext", names)),
                restricted = restricted,
                contexts = contexts,
            )
        }
        if (needs.isNotEmpty()) {
            return make(VerdictState.PENDING, reasons = reasonList, notes = notes, weight = weight, restricted = restricted)
        }
        return make(VerdictState.YES, notes = notes, weight = weight, restricted = restricted)
    }

    // ============================================================ 叠层

    /** 叠层条目的提示：超过一局实际上限、超过参数表／页面上限、超过游戏文本备好的『＋N』。 */
    fun stackWarnings(input: BuffStackInput, raw: Int, stacks: Int): List<String> {
        if (stacks <= 0) return emptyList()
        val warnings = ArrayList<String>()
        val practical = input.practicalMaxStacks
        if (practical != null && practical > 0 && stacks > practical) {
            // practicalMaxSource 的短来源（「实测」「用户反馈」…）：取第一个冒号／括号之前的部分。
            val label = input.practicalMaxSource.orEmpty().split('：', ':', '（', '(').first()
            warnings += RankerText.f("stackOverPractical", stacks, practical, label.ifEmpty { "practicalMaxStacks" })
        }
        val max = input.paramMax
        if (raw > max) warnings += RankerText.f(if (input.isLadder) "stackOverParam" else "stackOverCeiling", max)
        val label = input.uiLabelMax
        if (!input.isLadder && label != null && stacks > label) warnings += RankerText.f("stackOverLabel", label)
        return warnings
    }

    /**
     * 叠层后的 rates：ladder 第 n 层取 tierMultipliers[n-1]（超出按最后一层；没有表时 perStackRatio^n），
     * copies 取 perStackMultiplier^n；都替换 appliesToRateKeys（缺失时退回 multiplierKey）。
     * [stacks] ≤ 0 返回 null（不计入）；算不出倍率时 rates 原样返回。
     */
    fun stackedRates(entry: BuffRankerEntry, stacks: Int?): Map<String, Double>? {
        val input = entry.stackInput ?: return entry.rates
        if (stacks == null) return entry.rates
        if (stacks <= 0) return null
        val value = input.multiplier(stacks) ?: return entry.rates
        val copy = LinkedHashMap(entry.rates)
        for (key in input.rateKeys) if (key.isNotEmpty()) copy[key] = value
        return copy
    }

    /**
     * 这一条在九类伤害上的倍率表与加算表（Windows entryTables、macOS BuffLoadoutIndex.tables）：
     *   · 叠层条目按层数替换 rates；[restrictedType]（requires.physicalType）缺失时退回 scope.atkAttribute；
     *   · [weight] < 1（子类别只有部分段命中）：每类按 1 + (m − 1) × weight 近似，加算 × weight；
     *   · [copies] > 1（stackSelf 多份）：再按份数乘方，加算 × 份数。
     */
    fun tables(
        entry: BuffRankerEntry,
        restrictedType: DamageType?,
        weight: Double,
        stacks: Int?,
        copies: Int,
    ): Pair<List<Double>, List<Double>> {
        val rates = if (entry.stackInput != null) stackedRates(entry, stacks) else entry.rates
        if (rates == null) return TypeTables.filled(1.0).asList() to TypeTables.filled(0.0).asList()
        val restricted = restrictedType ?: entry.scopeRestricted
        val table = if (rates === entry.rates && restricted == entry.scopeRestricted) {
            entry.multiplier.toDoubleArray()
        } else {
            plan.multiplierTable(rates, restricted)
        }
        val flat = if (rates === entry.rates) entry.flat.toDoubleArray() else plan.flatTable(rates)
        val w = if (weight >= 0.0 && weight < 1.0) weight else 1.0
        val n = if (copies > 1) copies else 1
        for (index in 0 until DamageType.COUNT) {
            if (w < 1.0) {
                table[index] = 1.0 + (table[index] - 1.0) * w
                flat[index] = flat[index] * w
            }
            if (n > 1) {
                table[index] = Math.pow(table[index], n.toDouble())
                flat[index] = flat[index] * n
            }
        }
        return table.asList() to flat.asList()
    }

    // ============================================================ 单条评估

    /**
     * 单条评估（Windows evaluateEntry、macOS LoadoutEvaluator.evaluate）。判定顺序：
     * 不含伤害 → 多档只留选中的一档 → 作用对象（notes.ranking ①，含 selfAllyPair）→ 减益（②）→ appliesTo
     * → 累积阶梯选层 → 叠层层数 → 发动条件与手动确认（③）→ 份数 → 对当前构成有没有增益。
     *
     * [verdict] 可由调用方缓存后传入（同一输出手段下每条只判一次）。
     */
    fun evaluate(
        entry: BuffRankerEntry,
        output: RankerOutput,
        selections: EntrySelections = EntrySelections.NONE,
        options: EvalOptions = EvalOptions.STANDARD,
        source: EvalSource = EvalSource(),
        verdict: AppliesVerdict = verdict(entry, output),
    ): EvaluatedEntry {
        val copies = if (source.copies > 1) source.copies else 1
        val input = entry.stackInput
        var raw: Int? = null
        var assumedOneStack = false
        if (input != null) {
            var value = maxOf(0, selections.stacks(entry.id))
            if (options.assumeAll) {
                val soft = input.softMax
                if (soft == null && value <= 0) assumedOneStack = true
                value = maxOf(value, minOf(soft ?: 1, input.paramMax))
            }
            raw = value
        }
        val stacks = if (input != null && raw != null) minOf(raw, input.paramMax) else null
        val warnings = if (input != null && raw != null && stacks != null) stackWarnings(input, raw, stacks) else emptyList()
        val activationNote = verdict.activationNote
        val hasComposition = output.hasComposition
        val baseNotes = verdict.notes

        fun build(
            state: EntryState,
            reasons: List<String>,
            tablesFor: Pair<List<Double>, List<Double>>,
            notes: List<String> = baseNotes,
            needs: List<String> = emptyList(),
            ticked: Boolean = false,
            countedCopies: Int = 1,
            tier: TierPick? = null,
            variant: TierPick? = null,
        ): EvaluatedEntry {
            val (table, flatTable) = tablesFor
            return EvaluatedEntry(
                entry = entry, column = source.column, labels = source.labels, keys = source.keys,
                copies = copies, countedCopies = countedCopies, autoConfirm = source.autoConfirm, auto = source.auto,
                verdict = verdict, label = verdict.label, activationNote = activationNote, needs = needs,
                ticked = ticked, stacks = stacks, stackWarnings = warnings, assumedOneStack = assumedOneStack,
                tier = tier, variant = variant, state = state, reasons = reasons, notes = notes,
                table = table, flatTable = flatTable,
                multiplier = if (hasComposition) TypeTables.weighted(table, output.shares) else null,
                flat = if (hasComposition) TypeTables.weightedFlat(flatTable, output.shares) else 0.0,
            )
        }

        // 不计入的也给出「单独看这一条」的倍率，列表展示用（不进汇总）。
        fun finish(
            state: EntryState,
            reasons: List<String>,
            needs: List<String> = emptyList(),
            tier: TierPick? = null,
            variant: TierPick? = null,
        ): EvaluatedEntry = build(
            state, reasons, tables(entry, verdict.restrictedType, verdict.weight, stacks, 1),
            needs = needs, tier = tier, variant = variant,
        )

        if (!entry.countsAsDamage) return finish(EntryState.NO_DAMAGE, listOf(RankerText.t("reasonNoDamage")))

        var variant: TierPick? = null
        if (entry.variantGroup != null) {
            val members = variantMembers(entry)
            variant = if (options.ownVariant) {
                TierPick(entry.id, entry.variantTier, members.size)
            } else {
                selectedVariant(entry, selections)
            }
            if (variant.id != entry.id) {
                return finish(
                    EntryState.VARIANT_OFF,
                    listOf(RankerText.f("reasonVariantOff", variant.tiers, variant.tier)),
                    variant = variant,
                )
            }
        }
        if (entry.pairRole == "ally") {
            return finish(EntryState.NO, listOf(RankerText.t("reasonAllyPair")), variant = variant)
        }
        if (entry.target != "self" && entry.target != "ally") {
            return finish(EntryState.NO, listOf(RankerText.f("reasonTarget", entry.target)), variant = variant)
        }
        if (entry.direction == "decrease") {
            return finish(EntryState.NO, listOf(RankerText.t("reasonDecrease")), variant = variant)
        }
        when (verdict.state) {
            VerdictState.NO -> return finish(EntryState.NO, verdict.reasons, variant = variant)
            VerdictState.CONTEXT -> return finish(EntryState.CONTEXT, verdict.reasons, variant = variant)
            else -> Unit
        }

        var selectionConfirms = false
        var tier: TierPick? = null
        if (entry.accLadder != null) {
            val members = ladderMembers(entry.ladderGroup)
            val pick = when {
                options.ownTier -> TierPick(entry.id, entry.ladderTier, members.size)
                options.assumeAll -> {
                    val top = members.lastOrNull()
                    TierPick(top?.id ?: entry.id, top?.ladderTier ?: entry.ladderTier, members.size)
                }
                else -> selectedLadderTier(entry, selections)
            }
            tier = pick
            if (pick.id == null) {
                return finish(EntryState.TIER_OFF, listOf(RankerText.t("reasonTierNone")), tier = pick, variant = variant)
            }
            if (pick.id != entry.id) {
                return finish(
                    EntryState.TIER_OFF, listOf(RankerText.f("reasonTierOff", pick.tier)), tier = pick, variant = variant,
                )
            }
            selectionConfirms = true
        }
        if (input != null) {
            if (stacks == null || stacks <= 0) {
                return finish(EntryState.ZERO_STACKS, listOf(RankerText.t("reasonZeroStacks")), tier = tier, variant = variant)
            }
            selectionConfirms = true
        }

        val needs = ArrayList<String>()
        if (!selectionConfirms) {
            if (activationNote != null) needs += activationNote
            needs += verdict.needs
        }
        if (options.strict && (needs.isNotEmpty() || selectionConfirms)) {
            return finish(
                EntryState.PENDING, if (needs.isNotEmpty()) needs.toList() else listOf(RankerText.t("fillNote")),
                needs = needs, tier = tier, variant = variant,
            )
        }
        var ticked = false
        if (needs.isNotEmpty() && !options.assumeAll) {
            ticked = selections.isConfirmed(entry.id) || source.autoConfirm
            if (!ticked) return finish(EntryState.PENDING, needs.toList(), needs = needs, tier = tier, variant = variant)
        }

        val notes = ArrayList(baseNotes)
        var countedCopies = 1
        if (copies > 1) {
            if (entry.copiesMultiply) {
                countedCopies = copies
                notes += RankerText.f("noteCopiesStackSelf", copies)
            } else {
                notes += RankerText.f("noteCopiesSingle", copies)
            }
        }
        notes += warnings
        val result = build(
            EntryState.COUNTED, emptyList(),
            tables(entry, verdict.restrictedType, verdict.weight, stacks, countedCopies),
            notes = notes, needs = needs, ticked = ticked, countedCopies = countedCopies, tier = tier, variant = variant,
        )
        val multiplier = result.multiplier
        if (hasComposition && multiplier != null &&
            Math.abs(multiplier - 1.0) <= RANK_EPSILON && result.flat <= RANK_EPSILON
        ) {
            return result.copy(state = EntryState.NEUTRAL, reasons = listOf(RankerText.t("reasonNeutral")))
        }
        return result
    }

    /** 多档词条选中的那一档：用户选过的，否则第 1 档（参数里没有按武器类别选档的列，只能让用户选）。 */
    fun selectedVariant(entry: BuffRankerEntry, selections: EntrySelections): TierPick {
        val members = variantMembers(entry)
        val chosen = entry.variantGroup?.let { selections.variantChoice(it) }
        val pick = members.firstOrNull { it.id == chosen } ?: members.firstOrNull() ?: entry
        val position = members.indexOf(pick)
        val tier = pick.variantTier.takeIf { it > 0 } ?: (position + 1).takeIf { it > 0 } ?: 1
        return TierPick(pick.id, tier, members.size.takeIf { it > 0 } ?: 1)
    }

    /** 累积阶梯选中的那一层；没选层（或选了不存在的层）时 id 为 null（一层都不算，选层即确认）。 */
    fun selectedLadderTier(entry: BuffRankerEntry, selections: EntrySelections): TierPick {
        val members = ladderMembers(entry.ladderGroup)
        val chosen = entry.ladderGroup?.let { selections.ladderChoice(it) }
        val pick = members.firstOrNull { it.id == chosen }
        return TierPick(pick?.id, pick?.let { it.ladderTier.takeIf { tier -> tier > 0 } ?: 1 } ?: 0, members.size)
    }

    // ============================================================ 全部增益一览

    /**
     * 能进计算的条目逐条单独评估（两端同一口径）：「条件全部成立」——要确认的当成立，叠层取一局实际上限
     * （没有就退『＋N』标签数，再没有 1 层），累积阶梯与多档词条按这一条自己的层／档；与当前配置无关。
     * 生效的在前，按有效倍率降序（差不超过 1e-9 视为相同），再按 spEffectId 升序。
     */
    fun overview(output: RankerOutput): List<OverviewRow> {
        val rows = ArrayList<OverviewRow>(listableEntries.size)
        for (entry in listableEntries) {
            val item = evaluate(entry, output, EntrySelections.NONE, EvalOptions.OVERVIEW, EvalSource())
            val applicable = item.state != EntryState.NO && item.state != EntryState.CONTEXT
            val multiplier = if (applicable) item.multiplier else if (output.hasComposition) 1.0 else null
            rows += OverviewRow(item, applicable, multiplier)
        }
        return rows.stableSortedWith { a, b ->
            when {
                a.applicable != b.applicable -> if (a.applicable) -1 else 1
                else -> {
                    val am = a.multiplier ?: 1.0
                    val bm = b.multiplier ?: 1.0
                    when {
                        Math.abs(bm - am) > RANK_EPSILON -> if (bm > am) 1 else -1
                        else -> a.id.compareTo(b.id)
                    }
                }
            }
        }
    }

    /**
     * 当前输出类别下，数据里实际要求过的攻击情境（appliesTo[类别]=conditional 的 requires.attackContexts），
     * 只统计能进计算的条目，按固定顺序（Windows availableContexts、macOS attackContextOptions）。
     */
    fun attackContextOptions(outputClass: OutputClass): List<AttackContextOption> {
        val counts = LinkedHashMap<String, Int>()
        for (entry in listableEntries) {
            if (entry.buff.appliesTo?.get(outputClass) != "conditional") continue
            val contexts = entry.buff.appliesToDetail[outputClass]?.requires?.attackContexts ?: continue
            for (key in contexts) counts[key] = (counts[key] ?: 0) + 1
        }
        return counts.map { (key, count) -> AttackContextOption(key, dataset.attackContextLabel(key), count) }
            .sortedWith(
                compareBy<AttackContextOption> { option ->
                    ATTACK_CONTEXT_ORDER.indexOf(option.key).let { if (it < 0) ATTACK_CONTEXT_ORDER.size else it }
                }.thenBy { it.key },
            )
    }

    /** 「874 条增益 · 其中 353 条无条件生效」。 */
    val summary: String
        get() = "${dataset.buffs.size} 条增益 · 其中 ${dataset.buffs.count { it.isPassive }} 条无条件生效"

    companion object {
        /** 攻击情境的固定顺序（enums.attackContext 的 15 个键；数据里没用到的不显示）。两端逐项相同。 */
        val ATTACK_CONTEXT_ORDER: List<String> = listOf(
            "criticalHit", "thrustingCounter", "guardCounter", "chainFinisher",
            "chargedHeavyAttack", "chargedSkill", "chargedSpell",
            "jumpAttack", "dashAttack", "rollingAttack", "backstepAttack",
            "initialAttack", "horsebackAttack", "twoHanded", "dualWield",
        )

        private val BRACKET_PATTERN = Regex("^\\[([^\\]]*)\\]${RankerRegex.WS}*(.*)$")
        private val TIER_SUFFIX = Regex("${RankerRegex.WS}*-${RankerRegex.WS}*(?:Potency|Level|Tier)${RankerRegex.WS}*${RankerRegex.DIGIT}+${RankerRegex.WS}*$", RegexOption.IGNORE_CASE)
        private val PLUS_SUFFIX = Regex("${RankerRegex.WS}*\\+${RankerRegex.DIGIT}+${RankerRegex.WS}*$")
        private val CHARACTER_PATTERN = Regex("^\\[[^\\]]*?-${RankerRegex.WS}*([^\\]]+?)${RankerRegex.WS}*\\]")

        /**
         * 同族＝Paramdex 行名去掉档位后缀后相同（`[Item - Level 3] X` → `[Item] X`，`[Weapon] X - Potency 2` →
         * `[Weapon] X`，`[Relic] X +3` → `[Relic] X`）。只用来提示「不同档位同时计入」，不参与去重。
         */
        fun familyKey(buff: BuffEntry): String {
            val name = buff.paramName
            if (name.isNullOrEmpty()) return "id#${buff.spEffectId}"
            var text: String = name
            BRACKET_PATTERN.find(text)?.let { match ->
                text = "[" + match.groupValues[1].split(" - ")[0].trim() + "] " + match.groupValues[2]
            }
            text = TIER_SUFFIX.replace(text, "")
            text = PLUS_SUFFIX.replace(text, "")
            return text.trim().ifEmpty { "id#${buff.spEffectId}" }
        }

        /** 角色分组键：[Skill - Revenant] → Revenant；拿不到为空串。 */
        fun characterKey(buff: BuffEntry): String =
            CHARACTER_PATTERN.find(buff.paramName.orEmpty())?.groupValues?.get(1).orEmpty()

        /** 角色的中文名（文案常量表 characterNames.*；拿不到归「其他角色」）。 */
        fun characterLabel(key: String): String {
            if (key.isEmpty()) return RankerText.t("characterOther")
            return RANKER_TEXT_TABLE["characterNames.$key"] ?: key
        }

        /** 预计算一条 buff（Windows indexBuff）。合成数据的测试也用它。 */
        fun indexEntry(buff: BuffEntry, plan: RateFieldPlan): BuffRankerEntry {
            val scopeRestricted = DamageType.physicalOrNull(buff.scope.atkAttribute)
            val usedMultiplier = ArrayList<RateUse>()
            val usedFlat = ArrayList<RateUse>()
            val multiplier = plan.multiplierTable(buff.rates, scopeRestricted, usedMultiplier)
            val flat = plan.flatTable(buff.rates, usedFlat)
            val others = buff.rates.keys.filter { key -> plan.byKey[key]?.countsAsDamage != true }
            val hasMultiplier = multiplier.any { it != 1.0 }
            val hasFlat = flat.any { it != 0.0 }
            val searchParts = listOf(
                buff.displayNameZh, buff.nameZh, buff.displayNameEn, buff.nameEn, buff.suggestedNameZh,
                buff.paramName, buff.descZh,
                buff.sources.joinToString(" ") { source ->
                    listOf(source.nameZh, source.nameEn, source.effectNameZh, source.artsNameZh).joinToString(" ") { it.orEmpty() }
                },
                buff.spEffectId.toString(),
            )
            return BuffRankerEntry(
                buff = buff,
                multiplier = multiplier.asList(),
                flat = flat.asList(),
                usedMultiplier = usedMultiplier,
                usedFlat = usedFlat,
                otherRateKeys = others,
                hasMultiplier = hasMultiplier,
                hasFlat = hasFlat,
                scopeRestricted = scopeRestricted,
                family = familyKey(buff),
                character = if (buff.sourceSlot == "character") characterKey(buff) else "",
                searchText = searchParts.joinToString(" ") { it.orEmpty() }.foldedForSearch(),
            )
        }
    }
}

/** 稳定归并排序：比较器带容差时也不会像 TimSort 那样因「违反比较约定」抛异常。 */
internal fun <T> List<T>.stableSortedWith(comparator: (T, T) -> Int): List<T> {
    if (size < 2) return toList()
    var source: MutableList<T> = ArrayList(this)
    var target: MutableList<T> = ArrayList(this)
    var width = 1
    while (width < size) {
        var start = 0
        while (start < size) {
            val middle = minOf(start + width, size)
            val end = minOf(start + 2 * width, size)
            var left = start
            var right = middle
            var out = start
            while (left < middle && right < end) {
                if (comparator(source[right], source[left]) < 0) {
                    target[out++] = source[right++]
                } else {
                    target[out++] = source[left++]
                }
            }
            while (left < middle) target[out++] = source[left++]
            while (right < end) target[out++] = source[right++]
            start = end
        }
        val swap = source
        source = target
        target = swap
        width *= 2
    }
    return source
}
