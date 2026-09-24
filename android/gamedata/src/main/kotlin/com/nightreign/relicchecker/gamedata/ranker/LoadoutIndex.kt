package com.nightreign.relicchecker.gamedata.ranker

import com.nightreign.relicchecker.rules.Affix
import com.nightreign.relicchecker.rules.foldedForSearch
import java.util.concurrent.ConcurrentHashMap

// 配置页的索引（只建一次，与输出手段无关；Windows 端 buildConfigIndex、macOS 端 BuffLoadoutIndex）：
//   · 局内武器词条（按 AttachEffect id 升序；诅咒 / 减益不进正面词条栏；只收带能进计算条目的）；
//   · 官方固定词条遗物（按 relicIds[0] 升序，整件的 spEffectIds 里能进计算的计入，其余词条只显示）；
//   · 遗物词条（词条库 effectId → 能进计算的条目），按普通 / 深夜口径列出可自组的候选；
//   · 护符（主槽位 accessory 的条目按护符 id 归组）；
//   · 其它增益各分栏（累积阶梯的各层合成一行，行键＝第 1 层 spEffectId）；
//   · 词条库索引与诅咒池（深夜遗物配诅咒）、自组遗物合法性（见 RelicLegality.kt）。
// 以及只改配置、要查索引的操作：武器词条步进与上限、切常规 / 深夜、叠层填层数、按来源键移除。

/** 槽位上限（Windows slotCaps；数值取 slotRules，缺字段时退回与桌面端同值的兜底）。 */
data class SlotCaps(
    val runMode: RunMode,
    val maxWeapons: Int,
    /** 正面武器词条总数上限：常规 6 / 深夜 12。 */
    val weaponAffix: Int,
    /** 深夜专属正面词条上限：常规 0 / 深夜 6。 */
    val deepOnly: Int,
    val relicNormal: Int,
    val relicDeep: Int,
    /** 这个模式下用到的遗物格数（常规 3 / 深夜 6）。 */
    val relics: Int,
    val accessory: Int,
) {
    /** 第几格是普通遗物格还是深夜遗物格。 */
    fun relicKind(cardIndex: Int): RelicKind = if (cardIndex < relicNormal) RelicKind.NORMAL else RelicKind.DEEP

    /** 「普通遗物 N」「深夜遗物 N」（深夜格从 1 数起）。 */
    fun relicCardLabel(cardIndex: Int): String = LoadoutText.relicCardLabel(cardIndex, relicNormal)

    companion object {
        fun of(rules: BuffSlotRules, mode: RunMode): SlotCaps {
            val wa = rules.weaponAffix
            val deep = mode == RunMode.DEEP
            val relicNormal = rules.relic.normal
            val relicDeep = if (deep) rules.relic.deepExtra else 0
            return SlotCaps(
                runMode = mode,
                maxWeapons = wa.maxWeapons,
                weaponAffix = if (deep) wa.maxAffixesDeep else wa.maxAffixesNormal,
                deepOnly = if (deep) wa.maxDeepOnlyAffixes else wa.maxWeapons * rules.modes.normal.deepOnlyAffixesPerWeapon,
                relicNormal = relicNormal,
                relicDeep = relicDeep,
                relics = relicNormal + relicDeep,
                accessory = rules.accessory.slots,
            )
        }
    }
}

/** 局内武器词条栏的一项（Windows cfgIndex.weaponAffixes 的一项）。 */
class WeaponAffixOption internal constructor(
    val info: BuffWeaponAffixInfo,
    /** 能进计算的条目（spEffectIds 里 listable 的，去重、按数据顺序）。 */
    val entries: List<BuffRankerEntry>,
    /** 正面深夜专属（深夜每把最多 1 条、合计 ≤ 6 的计数口径）。 */
    val deepOnlyPositive: Boolean,
) {
    val id: Int get() = info.attachEffectId
    val nameZh: String get() = info.nameZh.ifEmpty { info.nameEn.ifEmpty { "#$id" } }
    val potency: Int? get() = info.potency
    val normalWepTypes: List<Int> get() = info.normalWepTypes

    /** 深夜能出现的类别：deepWepTypes，缺失时退常规的类别表（两端同一口径）。 */
    val deepWepTypes: List<Int> get() = info.deepWepTypes.ifEmpty { info.normalWepTypes }

    /** 「提升战技攻击力（档位3）」（汇总与来源标签）。 */
    val label: String = nameZh + (potency?.let { "（" + RankerText.f("badges.potency", it) + "）" } ?: "")

    /** 档位 / 深夜专属 / 武器赐福 / 固定词条。 */
    val badges: List<String> = buildList {
        potency?.let { add(RankerText.f("badges.potency", it)) }
        if (deepOnlyPositive) add(RankerText.t("badges.deepOnly"))
        if (info.isBlessing) add(RankerText.t("badges.blessing"))
        if ("fixed" in info.roles) add(RankerText.t("badges.fixed"))
    }

    internal val searchKey: String =
        listOf(info.nameZh, info.nameEn, info.paramName.orEmpty(), id.toString()).joinToString(" ").foldedForSearch()

    fun matches(foldedQuery: String): Boolean = foldedQuery.isEmpty() || searchKey.contains(foldedQuery)

    /** 这个模式下能不能出现：常规看 normalWepTypes 且不出深夜专属，深夜看 deepWepTypes。 */
    fun isAvailable(mode: RunMode): Boolean =
        if (mode == RunMode.DEEP) deepWepTypes.isNotEmpty() else !info.deepOnly && normalWepTypes.isNotEmpty()

    fun weaponTypes(mode: RunMode): List<Int> = if (mode == RunMode.DEEP) deepWepTypes else normalWepTypes

    /** 武器类别过滤（null＝全部类别）。 */
    fun matchesType(mode: RunMode, wepType: Int?): Boolean = wepType == null || wepType in weaponTypes(mode)

    override fun toString(): String = "WeaponAffixOption(#$id $label)"
}

/** 固定遗物的一行词条：非增伤词条只显示、不计入。 */
data class FixedRelicEffectLine(val text: String, val counted: Boolean)

/** 官方固定词条遗物（整件占一个遗物格）。 */
class FixedRelicOption internal constructor(
    val relic: BuffFixedRelic,
    val entries: List<BuffRankerEntry>,
    /** 逐条词条（缺中文名退「词条 #id」）。 */
    val effectLines: List<FixedRelicEffectLine>,
) {
    val key: String get() = relic.key
    val relicIds: List<Int> get() = relic.relicIds
    val nameZh: String get() = relic.nameZh.ifEmpty { relic.nameEn.ifEmpty { key } }
    val isDeepRelic: Boolean get() = relic.isDeepRelic
    val hasDamage: Boolean get() = entries.isNotEmpty()
    val effectNames: List<String> get() = effectLines.map { it.text }

    /** 「红色 · 遗物 #2070」（颜色缺失退「#2070」）。 */
    val subtitle: String get() = LoadoutText.fixedRelicSubtitle(relic.relicId, relic.color)

    internal val searchKey: String =
        (listOf(nameZh, relic.nameEn, relic.relicId.toString()) + effectLines.map { it.text }).joinToString(" ").foldedForSearch()

    fun matches(foldedQuery: String): Boolean = foldedQuery.isEmpty() || searchKey.contains(foldedQuery)

    override fun toString(): String = "FixedRelicOption($key $nameZh)"
}

/** 可自组的遗物词条（词条库里的一条，带能进计算的条目）。 */
class RelicAffixOption internal constructor(
    val affix: Affix,
    val entries: List<BuffRankerEntry>,
) {
    val id: Int get() = affix.effectId
    val name: String get() = affix.name
    val requiresCurse: Boolean get() = affix.requiresCurse

    fun matches(foldedQuery: String): Boolean = foldedQuery.isEmpty() || affix.searchableText.contains(foldedQuery)

    override fun toString(): String = "RelicAffixOption(#$id $name)"
}

/** 护符（同一护符的几档 / 几条效果合成一项）。 */
class TalismanOption internal constructor(
    val id: Int,
    val nameZh: String,
    val entries: List<BuffRankerEntry>,
) {
    /** 多条效果时「N 条效果」。 */
    val subtitle: String get() = if (entries.size > 1) RankerText.f("accEffectCount", entries.size) else ""

    internal val searchKey: String =
        (listOf(nameZh, id.toString()) + entries.map { it.name }).joinToString(" ").foldedForSearch()

    fun matches(foldedQuery: String): Boolean = foldedQuery.isEmpty() || searchKey.contains(foldedQuery)

    override fun toString(): String = "TalismanOption(#$id $nameZh)"
}

/**
 * 其它增益栏的一行（不占槽位，勾选即确认）。累积阶梯的各层合成一行：[key]＝第 1 层 spEffectId，
 * [entries]＝按层排好的各层，[name] 去掉「（第N层）」。
 */
class OtherRow internal constructor(
    /** 所在分栏（sourceSlot：consumable / spellBuff / weaponSkill / weaponInnate / character / permanent / runStack / other）。 */
    val slot: String,
    val key: Int,
    val entries: List<BuffRankerEntry>,
    val ladder: Boolean,
    val name: String,
    /** 分组标题：角色栏按角色、战技自增益按战技名、道具 / 增益法术按物品名；其余为 null。 */
    val groupTitle: String?,
    /** 角色栏：技艺 / 绝招 / 被动；累积阶梯：「共 N 层，选中后选层」。 */
    val subtitle: String,
    val badges: List<String>,
) {
    val first: BuffRankerEntry get() = entries.first()

    /** 道具等级（取第一条；累积阶梯各层同一道具。Windows otherRows 行的 goodsLevel）：缺省＝1 级。 */
    val goodsLevel: Int get() = first.goodsLevel

    /** 名字旁的等级标记「携物知识 N 级」；1 级为空串（[LoadoutText.goodsLevelTag]）。 */
    val goodsLevelTag: String get() = LoadoutText.goodsLevelTag(goodsLevel)

    fun matches(foldedQuery: String): Boolean = foldedQuery.isEmpty() || entries.any { it.matches(foldedQuery) }

    override fun toString(): String = "OtherRow($slot:$key $name)"
}

/** 词条库索引：effectId → 词条；诅咒池里的诅咒按 effectId 升序（配诅咒时 ID 小的先试）。 */
class RelicCatalogIndex internal constructor(affixes: List<Affix>) {
    val available: Boolean = affixes.isNotEmpty()
    val byId: Map<Int, Affix> = affixes.associateByFirst { it.effectId }

    /** 深夜遗物的负面词条池：只装诅咒词条的池（成员最多、再取 ID 小的）；算不出退 3000000。 */
    val cursePoolId: Int = cursePoolOf(affixes)

    /** 能配给深夜遗物的诅咒（isCurse 且在诅咒池），按 effectId 升序。 */
    val curses: List<Affix> = affixes.filter { it.isCurse && cursePoolId in it.poolIds }.sortedBy { it.effectId }

    companion object {
        /** 深夜遗物负面词条池的兜底值（与 core.js DEEP_CURSE_POOL_ID 同值）。 */
        const val DEEP_CURSE_POOL_ID: Int = 3_000_000

        fun cursePoolOf(affixes: List<Affix>): Int {
            val curseCount = HashMap<Int, Int>()
            val mixed = HashSet<Int>()
            for (affix in affixes) {
                for (pool in affix.poolIds) {
                    if (affix.isCurse) curseCount[pool] = (curseCount[pool] ?: 0) + 1 else mixed += pool
                }
            }
            var best: Int? = null
            for ((pool, count) in curseCount) {
                if (pool in mixed) continue
                val current = best
                if (current == null) {
                    best = pool
                    continue
                }
                val currentCount = curseCount[current] ?: 0
                if (count > currentCount || (count == currentCount && pool < current)) best = pool
            }
            return best ?: DEEP_CURSE_POOL_ID
        }
    }
}

/** 武器词条槽位的用量（Windows weaponAffixUsage）。 */
data class WeaponAffixUsage(val used: Int, val cap: Int, val deepOnlyUsed: Int, val deepOnlyCap: Int) {
    val isOver: Boolean get() = used > cap
    val isDeepOnlyOver: Boolean get() = deepOnlyUsed > deepOnlyCap
}

/** 能不能再加一份武器词条；不能时 [reason] 是给用户看的原因（waNotInMode / waCapReached / waDeepOnlyCapReached）。 */
data class AddCheck(val ok: Boolean, val reason: String)

/**
 * 配置页索引。[catalog] 是词条库（`AffixCatalog.affixes`）；空列表时自组遗物不可用（检查结果为「词条库未载入」）。
 * 建索引一次即可（与输出手段无关，可在 IO / Default 线程建好再交给页面）；换输出手段只需 [evaluator]。
 */
class LoadoutIndex(val ranker: BuffRankerIndex, catalog: List<Affix> = emptyList()) {
    val dataset: BuffDataset get() = ranker.dataset

    /** slotRules（缺失时用与桌面端同值的兜底，页面另按 [supportsLoadout] 提示「数据未内置」）。 */
    val slotRules: BuffSlotRules = ranker.dataset.slotRulesOrFallback

    /** 数据集带 slotRules 且 buffs 带 appliesTo（schemaVersion ≥ 6）；否则配置页显示 loadoutMissing。 */
    val supportsLoadout: Boolean =
        ranker.dataset.slotRules != null && ranker.dataset.buffs.any { it.appliesTo != null }

    val catalog: RelicCatalogIndex = RelicCatalogIndex(catalog)

    /** 累积阶梯：组 id → 能进计算的各层（按层升序）。 */
    val ladders: Map<Int, List<BuffRankerEntry>> get() = ranker.ladders

    val weaponAffixes: List<WeaponAffixOption>
    val weaponAffixById: Map<Int, WeaponAffixOption>
    val fixedRelics: List<FixedRelicOption>
    val fixedRelicByKey: Map<String, FixedRelicOption>

    /** 词条库 effectId → 能进计算的条目（按数据顺序、去重）。 */
    val relicAffixEntries: Map<Int, List<BuffRankerEntry>>

    /** 可自组的遗物词条候选（普通口径 / 深夜口径），按 effectId 升序。 */
    val relicCandidates: Map<RelicKind, List<RelicAffixOption>>
    val talismans: List<TalismanOption>
    val talismanById: Map<Int, TalismanOption>

    /** 其它增益各分栏（[OTHER_SLOTS] 的顺序，每栏按数据顺序）。 */
    val otherRows: Map<String, List<OtherRow>>
    private val otherRowByKey: Map<Int, OtherRow>

    /** 自组遗物检查的缓存（「按推荐填满」会对同一张卡反复检查）；线程安全。 */
    internal val relicCheckCache = ConcurrentHashMap<String, RelicCheck>()

    init {
        val byId = ranker.byId
        fun listableOf(ids: List<Int>): List<BuffRankerEntry> {
            val seen = HashSet<Int>()
            return ids.mapNotNull { byId[it] }.filter { it.listable && seen.add(it.id) }
        }

        // 局内武器词条（按 AttachEffect 升序；诅咒 / 减益不进正面词条栏）。
        val weaponList = ArrayList<WeaponAffixOption>()
        for (info in dataset.weaponAffixes.sortedBy { it.attachEffectId }) {
            if (info.isCurse || info.isDebuff) continue
            val own = listableOf(info.spEffectIds)
            if (own.isEmpty()) continue
            val deepOnlyPositive = info.deepOnlyPositive || own.any { it.buff.weaponAffixDeepOnlyPositive }
            weaponList += WeaponAffixOption(info, own, deepOnlyPositive)
        }
        weaponAffixes = weaponList
        weaponAffixById = weaponList.associateByFirst { it.id }

        // 官方固定词条遗物（按 relicIds[0] 升序）。
        val fixedList = ArrayList<FixedRelicOption>()
        for (relic in dataset.fixedRelics.sortedBy { it.relicIds.firstOrNull() ?: 0 }) {
            val own = listableOf(relic.spEffectIds)
            val counted = own.flatMap { entry -> entry.buff.relicAffixes.map { it.attachEffectId } }.toHashSet()
            val lines = relic.attachEffectIds.mapIndexed { position, attachId ->
                val name = relic.attachEffectNamesZh.getOrNull(position)?.takeIf { it.isNotEmpty() }
                    ?: RankerText.f("relicUnnamedEffect", attachId)
                FixedRelicEffectLine(name, attachId in counted)
            }
            fixedList += FixedRelicOption(relic, own, lines)
        }
        fixedRelics = fixedList
        fixedRelicByKey = fixedList.associateByFirst { it.key }

        // 遗物词条：词条库 effectId → 条目（只收能进计算的）。
        val relicMap = LinkedHashMap<Int, MutableList<BuffRankerEntry>>()
        for (entry in ranker.entries) {
            if (!entry.listable) continue
            for (link in entry.buff.relicAffixes) {
                val effectId = link.catalogEffectId ?: continue
                val list = relicMap.getOrPut(effectId) { ArrayList() }
                if (entry !in list) list += entry
            }
        }
        relicAffixEntries = relicMap
        relicCandidates = RelicKind.entries.associateWith { kind ->
            if (!this.catalog.available) {
                emptyList()
            } else {
                relicMap.mapNotNull { (effectId, own) ->
                    val affix = this.catalog.byId[effectId] ?: return@mapNotNull null
                    if (affix.isCurse || own.isEmpty() || !affix.isEligible(kind.checkMode)) return@mapNotNull null
                    RelicAffixOption(affix, own)
                }.sortedBy { it.id }
            }
        }

        // 护符：主槽位是 accessory 的条目按护符（sources[].kind=accessory 的 id）分组，按 id 升序。
        val talismanNames = LinkedHashMap<Int, String>()
        val talismanEntries = LinkedHashMap<Int, MutableList<BuffRankerEntry>>()
        for (entry in ranker.entries) {
            if (!entry.listable || entry.slot != "accessory") continue
            for (source in entry.buff.sources) {
                if (source.kind != "accessory") continue
                val id = source.id ?: continue
                if (id !in talismanNames) {
                    talismanNames[id] = source.nameZh?.takeIf { it.isNotEmpty() }
                        ?: source.nameEn?.takeIf { it.isNotEmpty() } ?: "#$id"
                }
                val list = talismanEntries.getOrPut(id) { ArrayList() }
                if (entry !in list) list += entry
            }
        }
        talismans = talismanNames.keys.sorted().map { id ->
            TalismanOption(id, talismanNames.getValue(id), talismanEntries[id].orEmpty())
        }
        talismanById = talismans.associateByFirst { it.id }

        // 其它增益：按主槽位分组；累积阶梯合成一行（行键＝阶梯第 1 层 id）。
        val rows = LinkedHashMap<String, MutableList<OtherRow>>()
        OTHER_SLOTS.forEach { rows[it] = ArrayList() }
        val seenLadder = HashSet<Int>()
        for (entry in ranker.entries) {
            if (!entry.listable) continue
            val slot = entry.slot
            val bucket = rows[slot] ?: continue
            val group = entry.ladderGroup
            if (group != null) {
                if (!seenLadder.add(group)) continue
                val members = ranker.ladders[group] ?: listOf(entry)
                bucket += otherRow(slot, members.first().id, members, ladder = true)
                continue
            }
            bucket += otherRow(slot, entry.id, listOf(entry), ladder = false)
        }
        otherRows = rows
        otherRowByKey = rows.values.flatten().associateByFirst { it.key }
    }

    private fun otherRow(slot: String, key: Int, members: List<BuffRankerEntry>, ladder: Boolean): OtherRow {
        val first = members.first()
        val buff = first.buff
        var group: String? = null
        var subtitle = ""
        when (slot) {
            "character" -> {
                val hero = LoadoutText.heroGroup(buff.paramName)
                group = hero.first
                subtitle = hero.second
            }
            "weaponSkill" -> group = buff.sources.firstNotNullOfOrNull { it.artsNameZh } ?: RankerText.t("groupUnknownSkill")
            "consumable" -> group = buff.sources.firstOrNull { it.kind == "goods" }?.nameZh
            "spellBuff" -> group = buff.sources.firstOrNull { it.kind == "spell" }?.nameZh
        }
        if (ladder) subtitle = RankerText.f("ladderTierCount", members.size)
        val name = if (ladder) LoadoutText.stripTierSuffix(first.name) else first.name
        return OtherRow(slot, key, members, ladder, name, group, subtitle, LoadoutText.entryBadges(first))
    }

    // ============================================================ 查询

    fun caps(mode: RunMode): SlotCaps = SlotCaps.of(slotRules, mode)

    fun otherRow(key: Int): OtherRow? = otherRowByKey[key]

    /**
     * 「其它增益」某个分栏的道具等级说明（Windows goodsLevelNoteFor）：这一栏里有携物知识 2／3 级的行才给
     * goodsLevel.note（本版本只有「道具」栏），否则为 null。
     */
    fun goodsLevelNote(slot: String): String? =
        if (otherRows[slot].orEmpty().any { it.goodsLevelTag.isNotEmpty() }) RankerText.t("goodsLevel.note") else null

    /** 这条累积阶梯实际收录的最高层（勾选预填与「条件成立时」都取它）。 */
    fun ladderTopTier(groupId: Int?): BuffRankerEntry? = ranker.ladderTopTier(groupId)

    /** 绑定一个输出手段的计算器（判定按条目缓存；换战技 / 武器 / 手 / 攻击情境时新建一个）。 */
    fun evaluator(output: RankerOutput): LoadoutEvaluator = LoadoutEvaluator(this, output)

    /** 当前武器的固有效果（weaponInnate.weaponIds 含当前武器）；法术没有武器 → 空。 */
    fun currentInnateEntries(output: RankerOutput): List<BuffRankerEntry> {
        if (output.outputClass != OutputClass.SKILL) return emptyList()
        val weaponId = output.weaponId ?: return emptyList()
        return ranker.entries.filter { entry -> entry.listable && entry.innate?.weaponIds?.contains(weaponId) == true }
    }

    // ============================================================ 武器词条

    fun weaponAffixUsage(config: LoadoutConfig): WeaponAffixUsage {
        val caps = caps(config.runMode)
        var used = 0
        var deepOnly = 0
        for ((id, count) in config.weaponAffixes) {
            val affix = weaponAffixById[id] ?: continue
            if (count <= 0) continue
            used += count
            if (affix.deepOnlyPositive) deepOnly += count
        }
        return WeaponAffixUsage(used, caps.weaponAffix, deepOnly, caps.deepOnly)
    }

    /** 能不能再加一份：模式可用、总数未满、深夜专属未满。 */
    fun canAddWeaponAffix(config: LoadoutConfig, id: Int): AddCheck {
        val affix = weaponAffixById[id] ?: return AddCheck(false, "")
        if (!affix.isAvailable(config.runMode)) return AddCheck(false, RankerText.t("waNotInMode"))
        val usage = weaponAffixUsage(config)
        if (usage.used >= usage.cap) return AddCheck(false, RankerText.t("waCapReached"))
        if (affix.deepOnlyPositive && usage.deepOnlyUsed >= usage.deepOnlyCap) {
            return AddCheck(false, RankerText.t("waDeepOnlyCapReached"))
        }
        return AddCheck(true, "")
    }

    /** 数量步进：[delta] = +1 / -1。加不进去（越界）时原样返回。 */
    fun stepWeaponAffix(config: LoadoutConfig, id: Int, delta: Int): LoadoutConfig {
        val count = config.weaponAffixCount(id)
        return when {
            delta > 0 -> if (canAddWeaponAffix(config, id).ok) config.copy(weaponAffixes = config.weaponAffixes + (id to count + 1)) else config
            delta < 0 && count > 0 -> config.copy(
                weaponAffixes = if (count - 1 <= 0) config.weaponAffixes - id else config.weaponAffixes + (id to count - 1),
            )
            else -> config
        }
    }

    /**
     * 切常规 / 深夜（两端同一口径）：去掉新模式下不存在的词条，深夜专属超限的按 AttachEffect id 从大到小削，
     * 总数超限的再按 id 从大到小削；切到常规时深夜遗物格清空。
     */
    fun applyRunMode(config: LoadoutConfig, mode: RunMode): LoadoutConfig {
        val counts = LinkedHashMap<Int, Int>()
        for ((id, count) in config.weaponAffixes) {
            val affix = weaponAffixById[id] ?: continue
            if (count > 0 && affix.isAvailable(mode)) counts[id] = count
        }
        var next = config.copy(runMode = mode, weaponAffixes = counts)
        val caps = caps(mode)
        fun trim(onlyDeep: Boolean, capacity: Int) {
            val usage = weaponAffixUsage(next)
            var excess = (if (onlyDeep) usage.deepOnlyUsed else usage.used) - capacity
            val map = LinkedHashMap(next.weaponAffixes)
            for (id in map.keys.sortedDescending()) {
                if (excess <= 0) break
                if (onlyDeep && weaponAffixById[id]?.deepOnlyPositive != true) continue
                val count = map[id] ?: 0
                val cut = minOf(count, excess)
                if (count - cut <= 0) map.remove(id) else map[id] = count - cut
                excess -= cut
            }
            next = next.copy(weaponAffixes = map)
        }
        trim(onlyDeep = true, capacity = caps.deepOnly)
        trim(onlyDeep = false, capacity = caps.weaponAffix)
        if (mode == RunMode.NORMAL) {
            next = next.copy(relics = next.relics.mapIndexed { index, card -> if (index >= caps.relicNormal) RelicCard.EMPTY else card })
        }
        return next
    }

    /** 切模式去掉的武器词条条数（「切到常规：已去掉 N 条…」的提示用）。 */
    fun trimmedCount(before: LoadoutConfig, after: LoadoutConfig): Int =
        weaponAffixUsage(before).used - weaponAffixUsage(after).used

    /** 已选的武器词条里，同一词条同时选了 ≥ 2 个档位的各组（组内按 id 升序，组按首个 id 升序）。 */
    fun selectedTierFamilies(config: LoadoutConfig): List<List<Int>> {
        val families = LinkedHashMap<String, MutableList<Int>>()
        for ((id, count) in config.weaponAffixes) {
            if (count <= 0) continue
            val affix = weaponAffixById[id] ?: continue
            families.getOrPut(weaponAffixFamilyKey(affix.info)) { ArrayList() } += id
        }
        return families.values.map { it.sorted() }.filter { it.size > 1 }.sortedBy { it.first() }
    }

    // ============================================================ 叠层与移除

    /** 填层数：截到 0…参数表上限（份数型 0…99）；0 就是不计入。 */
    fun setStacks(config: LoadoutConfig, entry: BuffRankerEntry, value: Int): LoadoutConfig {
        val input = entry.stackInput ?: return config
        return config.copy(stackCounts = config.stackCounts + (entry.id to value.coerceIn(0, input.paramMax)))
    }

    /**
     * 按来源键移除：`wa:<词条>`（减一份）/ `relic:<格>`（整件清空）/ `relic:<格>:<行>`（清掉这一行的词条与诅咒）/
     * `acc:<格>` / `innate:<spEffectId>`（排除当前武器固有）/ `other:<行键>`（取消勾选）。
     */
    fun removeSource(config: LoadoutConfig, key: String): LoadoutConfig {
        val parts = key.split(':')
        val id = parts.getOrNull(1)?.toIntOrNull() ?: return config
        return when (parts[0]) {
            "wa" -> stepWeaponAffix(config, id, -1)
            "relic" -> {
                if (id !in config.relics.indices) return config
                val card = config.relic(id)
                val row = parts.getOrNull(2)?.toIntOrNull()
                if (row != null && card.type == RelicCardType.CUSTOM) {
                    config.withRelic(id, card.withRow(row, null, null))
                } else {
                    config.withRelic(id, RelicCard.EMPTY)
                }
            }
            "acc" -> if (id in config.accessories.indices) config.withAccessory(id, null) else config
            "innate" -> config.copy(innateOff = config.innateOff + id)
            "other" -> config.copy(others = config.others - id)
            else -> config
        }
    }

    // ============================================================ 自组遗物（见 RelicLegality.kt）

    /** 这张卡的合法性（固定遗物 → fixed / 选了不存在的键 → empty；自组 → [checkCustomRelic]；空 → empty）。 */
    fun relicCheck(card: RelicCard, kind: RelicKind): RelicCheck = when (card.type) {
        RelicCardType.FIXED -> if (card.fixedKey?.let { fixedRelicByKey[it] } != null) RelicCheck.FIXED else RelicCheck.EMPTY
        RelicCardType.CUSTOM -> checkCustomRelic(card, kind)
        RelicCardType.EMPTY -> RelicCheck.EMPTY
    }

    fun checkCustomRelic(card: RelicCard, kind: RelicKind): RelicCheck = RelicLegality.check(this, card, kind)

    /** 给这一行挑一条诅咒：诅咒池里按 effectId 升序，取第一条不会让这件遗物因它出问题的；配不上返回 null。 */
    fun pickCurse(card: RelicCard, row: Int): Int? = RelicLegality.pickCurse(this, card, row)

    /** 需诅咒的词条自动配诅咒、不需要的行清掉诅咒、已配的保留；普通遗物格不带诅咒。 */
    fun autoAssignCurses(card: RelicCard, kind: RelicKind): RelicCard = RelicLegality.autoAssignCurses(this, card, kind)

    /** 自组遗物某一行换词条：这一行的旧诅咒先清掉，再 [autoAssignCurses]（Windows withRelicAffix、macOS 同法）。 */
    fun withRelicAffix(card: RelicCard, kind: RelicKind, row: Int, affixId: Int?): RelicCard {
        if (row !in 0 until RelicCard.ROWS) return card
        return autoAssignCurses(card.withRow(row, affixId, null), kind)
    }

    companion object {
        /** 其它增益栏的分组（sourceSlot 主槽位）与展示顺序。 */
        val OTHER_SLOTS: List<String> = listOf(
            "consumable", "spellBuff", "weaponSkill", "weaponInnate", "character", "permanent", "runStack", "other",
        )

        /**
         * 局内武器词条的「词条本身」：paramName 去掉末尾的「 - Potency N」；没有 paramName 时退中文名。
         * 同一个键下的不同 AttachEffect＝同一词条的不同档位（只做提示，不参与计算）。
         */
        fun weaponAffixFamilyKey(info: BuffWeaponAffixInfo): String {
            val param = info.paramName?.trim().orEmpty()
            if (param.isNotEmpty()) return "param:" + POTENCY_SUFFIX.replace(param, "")
            return "zh:" + info.nameZh.ifEmpty { info.nameEn.ifEmpty { "#${info.attachEffectId}" } }
        }

        private val POTENCY_SUFFIX = Regex("${RankerRegex.WS}*-${RankerRegex.WS}*Potency${RankerRegex.WS}*${RankerRegex.DIGIT}+${RankerRegex.WS}*$", RegexOption.IGNORE_CASE)
    }
}
