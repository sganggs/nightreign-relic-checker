package com.nightreign.relicchecker.gamedata.lookup

import com.nightreign.relicchecker.catalog.AffixCatalog
import com.nightreign.relicchecker.catalog.CatalogSource
import com.nightreign.relicchecker.rules.CheckMode
import com.nightreign.relicchecker.rules.foldedForSearch

// 词条反查：把「词条库 + 遗物物品表」翻转成「词条 → 能在哪出」与「遗物 → 槽位池成员」
// 两个方向的索引。逐条移植 macOS RelicCore/AffixLookup.swift（与 Windows pages/lookup.js
// 互相对拍过的口径），纯 Kotlin、无 Android 依赖：页面在 IO 线程构建一次（进程级缓存），
// 之后的查询都是 Map 命中。

// MARK: - 池与口径

/** 深夜正面词条池（A / B / C），顺序即展示顺序。 */
val DEEP_POSITIVE_LOOKUP_POOLS: List<Int> = listOf(2_000_000, 2_100_000, 2_200_000)

/** 深夜诅咒（负面词条）池。 */
const val DEEP_CURSE_LOOKUP_POOL: Int = 3_000_000

/** 反查页展示的口径：「顺序/互斥」不涉及槽池，不参与反查。 */
val AFFIX_LOOKUP_MODES: List<CheckMode> =
    listOf(CheckMode.CURRENT_NORMAL, CheckMode.LEGACY_NORMAL, CheckMode.DEEP_POSITIVE)

/** 互斥组默认列出多少条（最大的互斥组有 102 条，超出部分就地展开）。 */
const val AFFIX_LOOKUP_CONFLICT_LIMIT: Int = 24

/** 「能在哪出」的遗物列表默认列出多少件（超出部分就地展开）。与 macOS 同值。 */
const val AFFIX_LOOKUP_ROW_LIMIT: Int = 120

/** 「按遗物查」里每个槽位池预览多少条词条（两端同值）。 */
const val AFFIX_LOOKUP_SLOT_PREVIEW_LIMIT: Int = 10

/** 列表默认只列前 [limit] 条、可就地展开时，实际渲染的那一段（macOS `expanded ? hits : prefix(limit)`）。 */
fun <T> affixLookupShown(items: List<T>, expanded: Boolean, limit: Int): List<T> =
    if (expanded || items.size <= limit) items else items.subList(0, maxOf(0, limit))

/**
 * 「互斥组」一栏走哪一支（与 macOS AffixConflictBranch、Windows conflictBranch 同一条链）。
 * 前两支的顺序不能反：不可达优先于 compatibilityId == -1。
 */
enum class AffixConflictBranch {
    /** 进不了任何槽位池 → [LookupCopy.UNREACHABLE_CONFLICT_NOTE] */
    UNREACHABLE,

    /** compatibilityId == -1 → [LookupCopy.NO_CONFLICT_GROUP_NOTE] */
    NO_GROUP,

    /** 有互斥对象 → 互斥组列表 */
    PEERS,

    /** 互斥池里只有自己 → [affixLookupLoneConflictNote] */
    LONE;

    companion object {
        fun of(reachable: Boolean, compatibilityId: Int, peerCount: Int): AffixConflictBranch = when {
            !reachable -> UNREACHABLE
            compatibilityId == -1 -> NO_GROUP
            peerCount > 0 -> PEERS
            else -> LONE
        }
    }
}

/** 「按词条查」的范围（macOS AffixLookupView.AffixScope）。 */
enum class AffixLookupScope(val title: String) {
    ALL("全部"),
    CATALOG("词条库"),
    EXTRAS("物品表补充"),
}

// MARK: - 条目模型

/**
 * 反查用的词条条目：词条库 ∪ 遗物物品表的 extraAffixes。
 * [inCatalog] 为 false 的条目只在物品表里有名字，没有说明 / 分类 / 叠加性。
 */
data class LookupAffix(
    val effectId: Int,
    val name: String,
    val category: String,
    val explanation: String,
    val superposability: String,
    val compatibilityId: Int,
    val sortId: Int,
    /** 词条库声明的槽位池（extraAffixes 条目为空）。遗物物品表缺失时用它兜底。 */
    val poolIds: List<Int>,
    val isCurse: Boolean,
    val requiresCurse: Boolean,
    val inCatalog: Boolean,
    /** 预先折叠好的搜索键（名称 / 分类 / effectId / 别名）。 */
    val searchText: String,
    /**
     * 能不能真的出现在某件遗物上：词条库词条，或被某个槽位池引用的 extraAffixes。
     * 不可达的效果既不进别人的互斥组，自己也不反查出互斥对象（互斥组对称）。
     */
    val appearsOnRelic: Boolean = true,
) {
    val displayName: String get() = name.ifEmpty { "未命名词条 #$effectId" }
}

/** 槽位的正 / 负面区分。 */
enum class RelicSlotRole(val title: String) {
    POSITIVE("正面槽"),
    CURSE("诅咒槽"),
}

/** 「某条词条能在这件遗物上出」的一条命中记录（已按遗物 + 正负面去重）。 */
data class RelicLookupHit(
    val relicId: Int,
    val relicName: String,
    val kindLabel: String,
    val colorLabel: String,
    val color: Int,
    val deep: Boolean,
    val slotCount: Int,
    /** 命中的槽位池 id（升序）。不给「第几槽」：槽序号与孔数层池、深夜实际生成都对不上。 */
    val poolIds: List<Int>,
    val role: RelicSlotRole,
    /** 命中的池里有单词条固定池 → 这件遗物必定带这条词条。 */
    val isFixed: Boolean,
) {
    val key: String get() = "$relicId-${role.name}"
}

/** 一条槽位池的命中情况。 */
data class LookupPoolHit(
    val poolId: Int,
    val contains: Boolean,
    val memberCount: Int,
    val relicCount: Int,
) {
    val label: String get() = affixPoolLabel(poolId)
    val detail: String get() = affixPoolDetail(poolId)
}

/** 一种口径下的槽位池命中（池按 id 升序）。 */
data class LookupModeHit(
    val mode: CheckMode,
    val pools: List<LookupPoolHit>,
) {
    val isAvailable: Boolean get() = pools.any { it.contains }
    val hitPools: List<LookupPoolHit> get() = pools.filter { it.contains }
}

/** 按遗物种类聚合的命中件数。 */
data class LookupKindCount(val kind: String, val count: Int)

/** 一次词条反查的完整结果。 */
data class AffixLookupReport(
    val affix: LookupAffix,
    /** 同互斥组的其它词条（compatibilityId 相同且不为 -1），按 (sortId, effectId) 升序。 */
    val conflicts: List<LookupAffix>,
    /** 三种口径的普通随机遗物槽位。 */
    val modeHits: List<LookupModeHit>,
    /** 深夜 A / B / C 池。 */
    val deepHits: List<LookupPoolHit>,
    /** 深夜诅咒池。 */
    val cursePoolHit: LookupPoolHit,
    /** 含该词条的全部槽位池（升序）。 */
    val poolIds: List<Int>,
    /** 固定出：命中的池只有这一条词条。按遗物 id 升序。 */
    val fixedRelics: List<RelicLookupHit>,
    /** 随机出：命中的池是多词条随机池。按遗物 id 升序。 */
    val randomRelics: List<RelicLookupHit>,
    /** 按遗物种类聚合（固定 + 随机），件数降序、同数按种类名升序。 */
    val kindCounts: List<LookupKindCount>,
    /** 被过滤掉的条数：超范围 / 无名参数行、作弊器区段遗物、槽位池为空的脏数据。 */
    val hiddenRelicCount: Int,
    /** 遗物物品表是否可用；为 false 时遗物相关字段一律为空。 */
    val hasRelicData: Boolean,
    /** 真正有正常遗物在用的槽位池数（详情页「所在槽位池」）；没有物品表时为 [poolIds] 条数。 */
    val livePoolCount: Int,
) {
    val totalRelicCount: Int get() = fixedRelics.size + randomRelics.size

    /** 「互斥组」一栏走哪一支。 */
    val conflictBranch: AffixConflictBranch
        get() = AffixConflictBranch.of(affix.appearsOnRelic, affix.compatibilityId, conflicts.size)

    /** 深夜遗物一栏的结论文案。 */
    val deepNote: String
        get() = affixLookupDeepNote(
            isCurse = affix.isCurse,
            requiresCurse = affix.requiresCurse,
            inAnyPool = deepHits.any { it.contains } || cursePoolHit.contains,
            cursePoolId = DEEP_CURSE_LOOKUP_POOL,
            curseCount = cursePoolHit.memberCount,
        )
}

/** 一件遗物的单个槽位概览。 */
data class RelicSlotSummary(
    val slotIndex: Int,
    val poolId: Int,
    val poolSize: Int,
    val cursePoolId: Int,
    val cursePoolSize: Int,
    /** 池成员预览（固定池即唯一成员；随机池取排序后的前若干条）。 */
    val previewEffectIds: List<Int>,
) {
    val isEmpty: Boolean get() = poolId == -1
    val isFixed: Boolean get() = poolId != -1 && poolSize == 1
    val hasCurse: Boolean get() = cursePoolId != -1

    /** 声明了池、但池在数据集里没有成员（Windows `empty`）。 */
    val isEmptyPool: Boolean get() = poolId != -1 && poolSize == 0
}

/** 深夜遗物按池归并后的一组：同池的槽位只展示一次，写「本件 N 条」。 */
data class DeepPoolGroup(val slot: RelicSlotSummary, val count: Int) {
    val poolId: Int get() = slot.poolId
}

/** 反查用的遗物条目。 */
data class RelicLookupEntry(
    val info: RelicInfo,
    val displayName: String,
    val kindLabel: String,
    val colorLabel: String,
    val isUnique: Boolean,
    /** 恒为 3 条，空槽的 `isEmpty == true`。 */
    val slots: List<RelicSlotSummary>,
    /** 全部非空槽都是单词条固定池时的官方固定词条（按 (sortId, effectId) 升序补 -1 到 3 位）。 */
    val fixedEffectIds: List<Int>?,
    val searchText: String,
) {
    val id: Int get() = info.id
    val deep: Boolean get() = info.deep
    val slotCount: Int = slots.count { !it.isEmpty }
    val curseSlotCount: Int = slots.count { it.hasCurse }

    /** 「正常游玩拿不到」的原因（与 Windows unobtainableReasonFor 同序同文案）；空串表示正常可获得。 */
    val unobtainableReason: String = when {
        info.id in CHEAT_RELIC_ID_RANGE -> "作弊器常用 ID 区段（20000–30035）"
        info.id !in OBTAINABLE_RELIC_ID_RANGE -> "超出合法 ID 区间（100–2013322）"
        info.name.isEmpty() -> "参数表内部条目（没有官方名称）"
        slots.none { !it.isEmpty && it.poolSize > 0 } -> "槽位池在数据集中是空池"
        else -> ""
    }

    /**
     * 正常游玩能拿到：ID 在合法区间内、不在作弊器区段、有官方名称，
     * 且至少有一个槽位池真的有成员（macOS isObtainable 同口径）。
     */
    val isObtainable: Boolean get() = unobtainableReason.isEmpty()

    /** 深夜遗物的池构成：按池 id 升序归并，不按参数表的行序（不打槽序号）；非深夜遗物为 null。 */
    val deepPoolGroups: List<DeepPoolGroup>? by lazy {
        if (!info.deep) return@lazy null
        val counts = sortedMapOf<Int, Int>()
        val first = HashMap<Int, RelicSlotSummary>()
        slots.filter { !it.isEmpty }.forEach { slot ->
            counts[slot.poolId] = (counts[slot.poolId] ?: 0) + 1
            first.putIfAbsent(slot.poolId, slot)
        }
        counts.map { (poolId, count) -> DeepPoolGroup(first.getValue(poolId), count) }
    }
}

// MARK: - 索引

/**
 * 词条反查的反向索引。构建一次即可反复查询；实例不可变，可跨线程共享。
 *
 * [relicData] 为 null 时退化为只有词条库的索引（macOS 的降级模式）：
 * 只能回答词条说明、互斥组与词条库自带的 poolIds。
 */
class AffixLookupIndex(catalog: AffixCatalog, relicData: RelicCatalog?) {
    /** 可搜索的词条条目，按 (sortId, effectId) 升序。 */
    val affixes: List<LookupAffix>

    /** 可搜索的遗物条目，按 id 升序（含不可获得的参数行，搜索默认过滤）。 */
    val relics: List<RelicLookupEntry>

    /** 遗物物品表是否可用。 */
    val hasRelicData: Boolean = relicData != null

    /** 池 → 成员 effectId（去重，按 (sortId, effectId) 升序）。 */
    val poolMembers: Map<Int, List<Int>>

    /** 池 → 使用该池的遗物件数（只数正常可获得的遗物，正面槽 + 诅咒槽按遗物去重）。 */
    val relicCountByPool: Map<Int, Int>

    /** 正常可获得的遗物件数（页面状态标签「可查遗物 N 件」）。 */
    val obtainableRelicCount: Int

    val catalogSources: List<CatalogSource> = catalog.sources
    val relicSources: List<CatalogSource> = relicData?.sources.orEmpty()
    val relicGameVersion: String = relicData?.gameVersion.orEmpty()

    private val affixById: Map<Int, LookupAffix>
    private val relicById: Map<Int, RelicLookupEntry>

    /** effectId → 含它的池 id（升序）。 */
    internal val poolsByEffect: Map<Int, List<Int>>

    /** 池 id → 使用该池的遗物槽位。 */
    internal val slotsByPool: Map<Int, List<SlotRef>>

    /** compatibilityId → 该互斥组的 effectId（按 (sortId, effectId) 升序）。 */
    private val conflictGroups: Map<Int, List<Int>>

    internal data class SlotRef(val relicId: Int, val slotIndex: Int, val role: RelicSlotRole)

    init {
        // 1. 词条条目：词条库优先，extraAffixes 补齐物品表里出现过、词条库没有的 id
        val entries = LinkedHashMap<Int, LookupAffix>()
        catalog.affixes.forEach { affix ->
            entries[affix.effectId] = LookupAffix(
                effectId = affix.effectId,
                name = affix.name,
                category = affix.category,
                explanation = affix.explanation,
                superposability = affix.superposability,
                compatibilityId = affix.compatibilityId,
                sortId = affix.sortId,
                poolIds = affix.poolIds.sorted(),
                isCurse = affix.isCurse,
                requiresCurse = affix.requiresCurse,
                inCatalog = true,
                searchText = affix.searchableText,
            )
        }
        val extraCategory = AffixLookupScope.EXTRAS.title
        relicData?.extraAffixes?.forEach { extra ->
            if (!entries.containsKey(extra.effectId)) {
                entries[extra.effectId] = LookupAffix(
                    effectId = extra.effectId,
                    name = extra.name,
                    category = extraCategory,
                    explanation = "",
                    superposability = "未知",
                    compatibilityId = extra.compatibilityId,
                    sortId = extra.sortId,
                    poolIds = emptyList(),
                    isCurse = false,
                    requiresCurse = false,
                    inCatalog = false,
                    // 搜索框写的是「词条名、别名、分类或 effectId」，分类也要能搜到
                    searchText = "${extra.name} $extraCategory ${extra.effectId}".foldedForSearch(),
                )
            }
        }

        if (relicData == null) {
            // 没有物品表时只剩词条库条目，它们本来就都能出现在遗物上
            affixes = sortedAffixes(entries.values)
            affixById = entries
            conflictGroups = conflictGroupsOf(affixes) { true }
            relics = emptyList()
            relicById = emptyMap()
            poolMembers = emptyMap()
            relicCountByPool = emptyMap()
            poolsByEffect = emptyMap()
            slotsByPool = emptyMap()
            obtainableRelicCount = 0
        } else {
            // 2. 池成员与 effectId → 池 的反向索引
            val sortKey = { effectId: Int -> entries[effectId]?.sortId ?: Int.MAX_VALUE }
            val memberComparator = compareBy<Int>(sortKey).thenBy { it }
            val members = LinkedHashMap<Int, List<Int>>(relicData.pools.size * 2)
            val byEffect = HashMap<Int, MutableList<Int>>()
            relicData.pools.forEach { (poolId, effectIds) ->
                val unique = effectIds.toSortedSet().sortedWith(memberComparator)
                members[poolId] = unique
                unique.forEach { effectId -> byEffect.getOrPut(effectId) { ArrayList(4) }.add(poolId) }
            }
            byEffect.values.forEach { it.sort() }
            poolMembers = members
            poolsByEffect = byEffect

            // 3. 互斥组：只算真正能出现在遗物上的词条（先把这一位写回条目，两个方向同一位判断）
            entries.entries.forEach { entry ->
                val affix = entry.value
                if (!affix.inCatalog && !byEffect.containsKey(affix.effectId)) {
                    entry.setValue(affix.copy(appearsOnRelic = false))
                }
            }
            affixes = sortedAffixes(entries.values)
            affixById = entries
            conflictGroups = conflictGroupsOf(affixes) { it.appearsOnRelic }

            // 4. 遗物 → 槽位池概览，以及池 → 遗物槽位
            val refs = HashMap<Int, MutableList<SlotRef>>()
            val relicCounts = HashMap<Int, Int>()
            val entryList = ArrayList<RelicLookupEntry>(relicData.relics.size)
            relicData.relics.sortedBy { it.id }.forEach { info ->
                val summaries = ArrayList<RelicSlotSummary>(3)
                val usedPools = LinkedHashSet<Int>()
                for (slotIndex in 0 until 3) {
                    val poolId = slotValue(info.slots, slotIndex)
                    val cursePoolId = slotValue(info.curseSlots, slotIndex)
                    val poolList = if (poolId == -1) emptyList() else members[poolId].orEmpty()
                    val cursePoolSize = if (cursePoolId == -1) 0 else members[cursePoolId]?.size ?: 0
                    summaries += RelicSlotSummary(
                        slotIndex = slotIndex,
                        poolId = poolId,
                        poolSize = poolList.size,
                        cursePoolId = cursePoolId,
                        cursePoolSize = cursePoolSize,
                        previewEffectIds = poolList.take(AFFIX_LOOKUP_SLOT_PREVIEW_LIMIT),
                    )
                    if (poolId != -1) {
                        refs.getOrPut(poolId) { ArrayList() }.add(SlotRef(info.id, slotIndex, RelicSlotRole.POSITIVE))
                        usedPools += poolId
                    }
                    if (cursePoolId != -1) {
                        refs.getOrPut(cursePoolId) { ArrayList() }.add(SlotRef(info.id, slotIndex, RelicSlotRole.CURSE))
                        usedPools += cursePoolId
                    }
                }
                val name = relicDisplayName(info.id, info)
                val kind = relicKindLabel(info.id, info)
                val entry = RelicLookupEntry(
                    info = info,
                    displayName = name,
                    kindLabel = kind,
                    colorLabel = relicColorLabel(info.color),
                    isUnique = isUniqueRelicId(info.id),
                    slots = summaries,
                    fixedEffectIds = fixedEffects(info.slots, members, entries),
                    searchText = "$name $kind ${info.id}".foldedForSearch(),
                )
                // 可获得性只有 RelicLookupEntry.isObtainable 一个判定点
                if (entry.isObtainable) {
                    usedPools.forEach { poolId -> relicCounts[poolId] = (relicCounts[poolId] ?: 0) + 1 }
                }
                entryList += entry
            }
            relics = entryList
            // 与 Swift uniquingKeysWith: { first, _ in first } 一致：重复 id 保留第一件
            relicById = HashMap<Int, RelicLookupEntry>(entryList.size * 2).also { map ->
                entryList.forEach { map.putIfAbsent(it.id, it) }
            }
            slotsByPool = refs
            relicCountByPool = relicCounts
            obtainableRelicCount = entryList.count { it.isObtainable }
        }
    }

    // MARK: 查询

    fun affix(effectId: Int): LookupAffix? = affixById[effectId]

    fun relic(relicId: Int): RelicLookupEntry? = relicById[relicId]

    /** 词条名；未知 id 回退为「未知词条 #id」。 */
    fun affixName(effectId: Int): String = affixById[effectId]?.displayName ?: "未知词条 #$effectId"

    /** 按名称 / 分类 / effectId / 别名搜索词条；[query] 为空时返回范围内全部。 */
    fun searchAffixes(
        query: String,
        includeCurses: Boolean = true,
        scope: AffixLookupScope = AffixLookupScope.ALL,
    ): List<LookupAffix> {
        val needle = query.foldedForSearch()
        return affixes.filter { affix ->
            when {
                !includeCurses && affix.isCurse -> false
                scope == AffixLookupScope.CATALOG && !affix.inCatalog -> false
                scope == AffixLookupScope.EXTRAS && affix.inCatalog -> false
                else -> needle.isEmpty() || affix.searchText.contains(needle)
            }
        }
    }

    /** 按遗物名 / 种类 / id 搜索遗物；默认只给正常可获得的遗物。 */
    fun searchRelics(
        query: String,
        onlyObtainable: Boolean = true,
        onlyDeep: Boolean = false,
    ): List<RelicLookupEntry> {
        val needle = query.foldedForSearch()
        return relics.filter { entry ->
            when {
                onlyObtainable && !entry.isObtainable -> false
                onlyDeep && !entry.deep -> false
                else -> needle.isEmpty() || entry.searchText.contains(needle)
            }
        }
    }

    /**
     * 同互斥组的其它词条。互斥组对称：查询方自己也要过「能出现在遗物上」这道关，
     * 否则不可达词条会反查出整组互斥对象，而那一组里没有一条认它。
     */
    fun conflicts(effectId: Int): List<LookupAffix> {
        val affix = affixById[effectId] ?: return emptyList()
        if (affix.compatibilityId == -1 || !affix.appearsOnRelic) return emptyList()
        return conflictGroups[affix.compatibilityId].orEmpty()
            .filter { it != effectId }
            .mapNotNull { affixById[it] }
    }

    /** 深夜诅咒池的全部成员（按 (sortId, effectId) 升序）；A 池词条配诅咒时的候选。 */
    fun curseAffixes(): List<LookupAffix> =
        poolMembers[DEEP_CURSE_LOOKUP_POOL].orEmpty().mapNotNull { affixById[it] }

    /** 完整反查结果；未知 effectId 返回 null。 */
    fun report(effectId: Int): AffixLookupReport? {
        val affix = affixById[effectId] ?: return null
        // 有遗物物品表时以池表为准；没有时退回词条库自带的 poolIds，「在哪个池里」至少还能回答
        val pools = if (hasRelicData) poolsByEffect[effectId].orEmpty() else affix.poolIds
        val poolSet = pools.toHashSet()

        val modeHits = AFFIX_LOOKUP_MODES.map { mode ->
            LookupModeHit(mode, mode.eligiblePoolIds.sorted().map { poolHit(it, poolSet) })
        }
        val deepHits = DEEP_POSITIVE_LOOKUP_POOLS.map { poolHit(it, poolSet) }
        val curseHit = poolHit(DEEP_CURSE_LOOKUP_POOL, poolSet)
        val conflictList = conflicts(effectId)

        if (!hasRelicData) {
            return AffixLookupReport(
                affix = affix,
                conflicts = conflictList,
                modeHits = modeHits,
                deepHits = deepHits,
                cursePoolHit = curseHit,
                poolIds = pools,
                fixedRelics = emptyList(),
                randomRelics = emptyList(),
                kindCounts = emptyList(),
                hiddenRelicCount = 0,
                hasRelicData = false,
                livePoolCount = pools.size,
            )
        }

        // 同一件遗物可能有多个槽位命中同一条词条，按 (遗物, 正/负面) 去重
        class Bucket(val pools: MutableSet<Int> = sortedSetOf(), var isFixed: Boolean = false)
        val buckets = LinkedHashMap<Pair<Int, RelicSlotRole>, Bucket>()
        pools.forEach { poolId ->
            val poolSize = poolMembers[poolId]?.size ?: 0
            slotsByPool[poolId].orEmpty().forEach { ref ->
                val bucket = buckets.getOrPut(ref.relicId to ref.role) { Bucket() }
                bucket.pools += poolId
                if (poolSize == 1) bucket.isFixed = true
            }
        }

        val fixed = ArrayList<RelicLookupHit>()
        val random = ArrayList<RelicLookupHit>()
        val kindTally = HashMap<String, Int>()
        var hidden = 0
        buckets.forEach { (key, bucket) ->
            val entry = relicById[key.first] ?: return@forEach
            // 超范围 / 无名的参数行、作弊器区段遗物不展示，只计数
            if (!entry.isObtainable) {
                hidden += 1
                return@forEach
            }
            val hit = RelicLookupHit(
                relicId = entry.id,
                relicName = entry.displayName,
                kindLabel = entry.kindLabel,
                colorLabel = entry.colorLabel,
                color = entry.info.color,
                deep = entry.deep,
                slotCount = entry.slotCount,
                poolIds = bucket.pools.toList(),
                role = key.second,
                isFixed = bucket.isFixed,
            )
            if (hit.isFixed) fixed += hit else random += hit
            kindTally[entry.kindLabel] = (kindTally[entry.kindLabel] ?: 0) + 1
        }
        val byRelic = compareBy<RelicLookupHit>({ it.relicId }, { it.role.ordinal })
        fixed.sortWith(byRelic)
        random.sortWith(byRelic)

        return AffixLookupReport(
            affix = affix,
            conflicts = conflictList,
            modeHits = modeHits,
            deepHits = deepHits,
            cursePoolHit = curseHit,
            poolIds = pools,
            fixedRelics = fixed,
            randomRelics = random,
            kindCounts = kindTally.map { LookupKindCount(it.key, it.value) }
                .sortedWith(compareByDescending<LookupKindCount> { it.count }.thenBy { it.kind }),
            hiddenRelicCount = hidden,
            hasRelicData = true,
            livePoolCount = pools.count { (relicCountByPool[it] ?: 0) > 0 },
        )
    }

    private fun poolHit(poolId: Int, pools: Set<Int>): LookupPoolHit = LookupPoolHit(
        poolId = poolId,
        contains = poolId in pools,
        memberCount = poolMembers[poolId]?.size ?: 0,
        relicCount = relicCountByPool[poolId] ?: 0,
    )

    companion object {
        /** rememberGameData 用的解析器标识：RELICS 文件 → AffixLookupIndex。 */
        const val PARSER_ID = "lookup.index.v1"

        /** 解码遗物物品表并与词条库一起建好反向索引（在后台线程调用）。 */
        fun parse(catalog: AffixCatalog, relicsJson: String): AffixLookupIndex =
            AffixLookupIndex(catalog, RelicCatalogParser.parse(relicsJson))

        private val affixOrder = compareBy<LookupAffix>({ it.sortId }, { it.effectId })

        private fun sortedAffixes(values: Collection<LookupAffix>): List<LookupAffix> = values.sortedWith(affixOrder)

        /** 互斥组（口径与 RelicAuditor 第 6 条一致）：只收能出现在遗物上的词条。 */
        private fun conflictGroupsOf(
            affixes: List<LookupAffix>,
            isRelicReachable: (LookupAffix) -> Boolean,
        ): Map<Int, List<Int>> {
            val groups = HashMap<Int, MutableList<Int>>()
            affixes.forEach { affix ->
                if (affix.compatibilityId != -1 && isRelicReachable(affix)) {
                    groups.getOrPut(affix.compatibilityId) { ArrayList() }.add(affix.effectId)
                }
            }
            return groups
        }

        /** 槽位值；越界或 ≤ 0 一律当作没有这个槽（-1）。 */
        private fun slotValue(slots: List<Int>, index: Int): Int {
            val raw = slots.getOrNull(index) ?: return -1
            return if (raw <= 0) -1 else raw
        }

        /**
         * 与 RelicAuditor 的 officialFixedEffects 同规则：全部非空槽都是单词条固定池、
         * 且成员都能在词条索引里查到时可完全确定，按 (sortId, effectId) 升序补 -1 到 3 位；否则 null。
         */
        private fun fixedEffects(
            slots: List<Int>,
            members: Map<Int, List<Int>>,
            affixes: Map<Int, LookupAffix>,
        ): List<Int>? {
            val ids = ArrayList<Int>(3)
            for (index in 0 until 3) {
                val poolId = slotValue(slots, index)
                if (poolId == -1) continue
                val list = members[poolId]
                if (list == null || list.size != 1) return null
                ids += list[0]
            }
            if (ids.isEmpty() || ids.any { !affixes.containsKey(it) }) return null
            val ordered = ids.sortedWith(
                compareBy<Int>({ affixes[it]?.sortId ?: Int.MAX_VALUE }, { it }),
            ).toMutableList()
            while (ordered.size < 3) ordered += -1
            return ordered
        }
    }
}
