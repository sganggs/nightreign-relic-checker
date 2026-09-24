package com.nightreign.relicchecker.ui.ranker

import androidx.compose.runtime.Composable
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.Stable
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.saveable.Saver
import androidx.compose.runtime.saveable.listSaver
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshots.Snapshot
import androidx.compose.runtime.structuralEqualityPolicy
import com.nightreign.relicchecker.gamedata.ranker.AttackContextOption
import com.nightreign.relicchecker.gamedata.ranker.BuffRankerEntry
import com.nightreign.relicchecker.gamedata.ranker.EvaluatedEntry
import com.nightreign.relicchecker.gamedata.ranker.HitAction
import com.nightreign.relicchecker.gamedata.ranker.LoadoutConfig
import com.nightreign.relicchecker.gamedata.ranker.LoadoutEvaluation
import com.nightreign.relicchecker.gamedata.ranker.LoadoutEvaluator
import com.nightreign.relicchecker.gamedata.ranker.LoadoutIndex
import com.nightreign.relicchecker.gamedata.ranker.LoadoutText
import com.nightreign.relicchecker.gamedata.ranker.MeansKind
import com.nightreign.relicchecker.gamedata.ranker.MeansSelection
import com.nightreign.relicchecker.gamedata.ranker.OtherRowScore
import com.nightreign.relicchecker.gamedata.ranker.OutputClass
import com.nightreign.relicchecker.gamedata.ranker.RankerOutput
import com.nightreign.relicchecker.gamedata.ranker.RankerText
import com.nightreign.relicchecker.gamedata.ranker.RelicCard
import com.nightreign.relicchecker.gamedata.ranker.RelicCardType
import com.nightreign.relicchecker.gamedata.ranker.ResolvedMeans
import com.nightreign.relicchecker.gamedata.ranker.RunMode
import com.nightreign.relicchecker.gamedata.ranker.SkillDataIndex
import com.nightreign.relicchecker.gamedata.ranker.SkillHit
import com.nightreign.relicchecker.gamedata.ranker.SkillOutput
import com.nightreign.relicchecker.gamedata.ranker.SlotCaps
import com.nightreign.relicchecker.gamedata.ranker.WeaponAffixRow
import java.util.EnumMap
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/** 配置页索引的解析 id：buffs 解析 + 与词条库对照建好的 LoadoutIndex（词条库在应用启动时加载一次，之后不变）。 */
internal const val RANKER_LOADOUT_PARSER_ID = "ranker.loadout.v1"

/**
 * 「增伤排名」页的全部状态与增量计算（视图只读不算；纯计算在 :gamedata 的 ranker 包）：
 *   * 换输出手段 / 换武器 / 勾选段 / 换手 / 勾攻击情境 → [means] 变 → 重新选段、重算构成 → 重建计算器；
 *   * 改配置（武器词条、遗物、护符、其它增益、条件、层数…）→ 只有 [config] 变 → 只重算汇总；
 *   * 各栏候选的排序分数（每条候选单独评估两次）放到后台线程算，见 [rememberRankerRows]。
 * 派生量都是 derivedStateOf：同一输入只算一次，重组时直接取缓存。
 * 状态经 [saver] 存进 rememberSaveable（输出手段与配置编码成字符串），切底栏、返回枢纽再进入都保留。
 * 输出手段抽屉的类型开关（[meansKind]：战技 / 魔法 / 祷告三档，默认战技）也在这里，与 Windows 的 state.meansKind 同一口径：
 * 只换抽屉列出的那一档，不改已选的输出手段。
 */
@Stable
internal class RankerPageState(
    val skills: SkillDataIndex,
    val index: LoadoutIndex,
    // 构造参数一律带 initial 前缀：属性初始化里的 lambda（derivedStateOf）若同名，会捕获参数而不是状态。
    initialMeans: MeansSelection,
    initialConfig: LoadoutConfig,
    initialShowInactive: Boolean,
    initialWaFilterAll: Boolean,
    initialNotice: String?,
    initialMeansKind: MeansKind = MeansKind.DEFAULT,
) {
    var means: MeansSelection by mutableStateOf(initialMeans)
        private set
    var config: LoadoutConfig by mutableStateOf(initialConfig)
        private set

    /** 「已按推荐填入 N 项」「切到常规：已去掉…」之类的一句话提示；下一次改配置或换输出手段时清掉。 */
    var notice: String? by mutableStateOf(initialNotice)
        private set

    /** 显示 appliesTo 判为不生效的条目（虚化 + 原因）。 */
    var showInactive: Boolean by mutableStateOf(initialShowInactive)
        private set

    /** 武器词条栏：true＝全部类别，false＝当前出手武器的类别。 */
    var waFilterAll: Boolean by mutableStateOf(initialWaFilterAll)
        private set

    /**
     * 输出手段抽屉的类型开关当前档（战技 / 魔法 / 祷告，默认「战技」；游戏里魔法与祷告是两类）。
     * 只是界面层的过滤：换档不改 [means]，已选的输出手段（哪怕在另一档）原样保留。
     */
    var meansKind: MeansKind by mutableStateOf(initialMeansKind)
        private set

    /** 「按推荐填满」正在后台计算。 */
    var filling: Boolean by mutableStateOf(false)
        private set

    private val contextCache = EnumMap<OutputClass, List<AttackContextOption>>(OutputClass::class.java)

    /** 当前输出类别下数据里实际要求过的攻击情境（按类别缓存，只在主线程读）。 */
    fun contextOptionsFor(outputClass: OutputClass): List<AttackContextOption> =
        contextCache.getOrPut(outputClass) { index.ranker.attackContextOptions(outputClass) }

    val resolved: ResolvedMeans by derivedStateOf { means.resolve(skills) }

    val contextOptions: List<AttackContextOption> get() = contextOptionsFor(resolved.outputClass)

    /** 交给配置引擎的输出手段（值相等时下游不重算）。 */
    val output: RankerOutput by derivedStateOf(structuralEqualityPolicy()) {
        val current = resolved
        current.rankerOutput(contextOptionsFor(current.outputClass).mapTo(HashSet()) { it.key })
    }

    /** 绑定当前输出手段的计算器（逐条判定在构造时缓存；换输出手段才重建）。 */
    val evaluator: LoadoutEvaluator by derivedStateOf { index.evaluator(output) }

    /** 整套配置的评估（汇总、各栏计入情况、提示与超限）。 */
    val evaluation: LoadoutEvaluation by derivedStateOf { evaluator.evaluate(config) }

    val caps: SlotCaps get() = evaluation.caps

    /** 说明区「口径说明」（与配置无关，数字照数据现算；只算一次）。 */
    val briefNotes: List<String> by lazy(LazyThreadSafetyMode.PUBLICATION) { LoadoutText.briefNotes(index) }
    val hasComposition: Boolean get() = output.hasComposition

    /** 武器词条栏与推荐填满的武器类别过滤（null＝全部类别）。 */
    val waFilterType: Int? get() = if (waFilterAll) null else output.attackWepType

    // ============================================================ 修改
    //
    // 一律在独立的可变快照里写（Snapshot.withMutableSnapshot）：写入总是生成新的状态记录，派生量（derivedStateOf）
    // 在任何线程、任何时机读都能看到；若直接在全局快照里连写两次，第二次会原地覆盖第一次的记录，
    // 中间读过的派生量会把旧结果当成仍然有效。

    private inline fun mutate(crossinline block: () -> Unit) {
        Snapshot.withMutableSnapshot { block() }
    }

    fun updateShowInactive(value: Boolean) = mutate { showInactive = value }

    fun updateWaFilterAll(value: Boolean) = mutate { waFilterAll = value }

    // ---- 输出手段

    /** 类型开关换档：只换抽屉的列表。 */
    fun updateMeansKind(kind: MeansKind) = mutate { meansKind = kind }

    /** 输出手段抽屉的列表：只列类型开关当前档里匹配 [query] 的条目（数据顺序）。 */
    fun meansRows(query: String): List<OutputPickRowModel> = outputPickRows(skills, meansKind, query)

    fun selectOutput(output: SkillOutput) = mutate {
        means = means.select(skills, output)
        // 「已按推荐填入 N 项」之类的提示只对填入时的那一招有意义，换招就清掉（两端同一口径）。
        notice = null
    }

    fun selectWeapon(weaponId: Int) = mutate { means = means.withWeapon(weaponId) }

    fun setHand(hand: Int) = mutate { means = means.withHand(hand) }

    fun setNoFp(value: Boolean) = mutate { means = means.withNoFp(value) }

    fun setHit(hit: SkillHit, on: Boolean) = mutate { means = means.withHit(hit, on) }

    fun hitAction(action: HitAction) = mutate { means = means.withHitAction(means.resolve(skills).hits, action) }

    fun toggleContext(key: String) = mutate { means = means.toggleContext(key) }

    // ---- 配置

    /** 改配置：一律清掉上一句提示（Windows updateConfig 同一口径），[message] 非空时换成新的提示。 */
    fun update(next: LoadoutConfig, message: String? = null) = mutate {
        config = next
        notice = message
    }

    fun setRunMode(mode: RunMode) {
        val before = config
        if (mode == before.runMode) return
        val switched = index.applyRunMode(before, mode)
        val trimmed = index.trimmedCount(before, switched)
        update(
            switched,
            if (before.runMode == RunMode.DEEP && mode == RunMode.NORMAL && trimmed > 0) RankerText.f("modeTrimmed", trimmed) else null,
        )
    }

    fun stepWeaponAffix(id: Int, delta: Int) = update(index.stepWeaponAffix(config, id, delta))

    /** 遗物卡换来源：类型真的变了才换成新的空卡（固定遗物先不选件，自组三行全空）。 */
    fun setRelicType(cardIndex: Int, type: RelicCardType) {
        val current = config
        if (current.relic(cardIndex).type == type) return
        val card = when (type) {
            RelicCardType.EMPTY -> RelicCard.EMPTY
            RelicCardType.FIXED -> RelicCard(type = RelicCardType.FIXED)
            RelicCardType.CUSTOM -> RelicCard.custom()
        }
        update(current.withRelic(cardIndex, card))
    }

    fun setFixedRelic(cardIndex: Int, key: String?) =
        update(config.withRelic(cardIndex, if (key == null) RelicCard(type = RelicCardType.FIXED) else RelicCard.fixed(key)))

    /** 自组遗物某一行换词条：这一行的旧诅咒清掉，深夜遗物需诅咒的词条自动配诅咒（可再改）。 */
    fun setRelicAffix(cardIndex: Int, row: Int, affixId: Int?) {
        val current = config
        val kind = index.caps(current.runMode).relicKind(cardIndex)
        update(current.withRelic(cardIndex, index.withRelicAffix(current.relic(cardIndex), kind, row, affixId)))
    }

    fun setRelicCurse(cardIndex: Int, row: Int, curseId: Int?) =
        update(config.withRelic(cardIndex, config.relic(cardIndex).withCurse(row, curseId)))

    fun setAccessory(slot: Int, id: Int?) = update(config.withAccessory(slot, id))

    fun toggleOther(rowKey: Int, checked: Boolean) = update(evaluator.toggleOtherRow(config, rowKey, checked))

    fun setTick(spEffectId: Int, ticked: Boolean) = update(config.withTick(spEffectId, ticked))

    fun setStacks(entry: BuffRankerEntry, value: Int) = update(index.setStacks(config, entry, value))

    fun setTier(ladderId: Int, spEffectId: Int?) = update(config.withLadderTier(ladderId, spEffectId))

    fun setVariant(groupKey: String, spEffectId: Int) = update(config.withVariant(groupKey, spEffectId))

    fun removeSource(key: String) = update(index.removeSource(config, key))

    /** 清空配置（保留常规 / 深夜）。 */
    fun clear() = update(LoadoutConfig(runMode = config.runMode))

    /**
     * 按推荐填满：在 Dispatchers.Default 上算（贪心逐项试，手机上可能要几十毫秒），算完时配置与输出手段都没变才应用。
     */
    fun fill(scope: CoroutineScope) {
        if (filling || !hasComposition) return
        val ev = evaluator
        val start = config
        val filter = waFilterType
        mutate { filling = true }
        scope.launch {
            val result = try {
                withContext(Dispatchers.Default) { ev.recommendFill(start, filter) }
            } finally {
                mutate { filling = false }
            }
            if (config == start && evaluator === ev) {
                update(
                    result.config,
                    if (result.added.isNotEmpty()) RankerText.f("fillDone", result.added.size) else RankerText.t("fillNothing"),
                )
            }
        }
    }

    // ============================================================ 查询

    /** 某个来源键（relic:3 / acc:0 / wa:… / other:…）带进来的条目。 */
    fun itemsFrom(key: String): List<EvaluatedEntry> = evaluation.itemsFrom(key)

    /** 其它增益一行在汇总里的逐条（当前武器固有按 innate:<id>，其余按 other:<行键>）。 */
    fun itemsForOtherRow(row: OtherRowScore): List<EvaluatedEntry> =
        if (row.auto) row.row.entries.flatMap { itemsFrom("innate:${it.id}") } else itemsFrom("other:${row.row.key}")

    /** 其它增益一行当前是否选中（直接看配置，不等后台的候选分数）。 */
    fun isOtherSelected(row: OtherRowScore): Boolean =
        if (row.auto) !row.row.entries.all { it.id in config.innateOff } else row.row.key in config.others

    companion object {
        fun create(skills: SkillDataIndex, index: LoadoutIndex): RankerPageState = RankerPageState(
            skills, index, MeansSelection.initial(skills), LoadoutConfig(),
            initialShowInactive = false, initialWaFilterAll = false, initialNotice = null,
        )

        /**
         * rememberSaveable 用：输出手段与配置编码成字符串，类型开关存档位的键；读不回来时退回默认
         * （没存档位时落在所选输出手段的那一档，认不出的档位回落到「战技」）。
         */
        fun saver(skills: SkillDataIndex, index: LoadoutIndex): Saver<RankerPageState, Any> = listSaver(
            save = { state ->
                listOf(
                    state.means.encode(), state.config.encode(), state.showInactive, state.waFilterAll, state.notice.orEmpty(),
                    state.meansKind.key,
                )
            },
            restore = { saved ->
                val means = MeansSelection.decode(saved.getOrNull(0) as? String)?.sanitized(skills) ?: MeansSelection.initial(skills)
                RankerPageState(
                    skills = skills,
                    index = index,
                    initialMeans = means,
                    initialConfig = LoadoutConfig.decode(saved.getOrNull(1) as? String) ?: LoadoutConfig(),
                    initialShowInactive = saved.getOrNull(2) as? Boolean ?: false,
                    initialWaFilterAll = saved.getOrNull(3) as? Boolean ?: false,
                    initialNotice = (saved.getOrNull(4) as? String)?.takeIf { it.isNotEmpty() },
                    initialMeansKind = (saved.getOrNull(5) as? String)?.let { MeansKind.fromKey(it) }
                        ?: MeansKind.of(means.outputId?.let { skills.output(it) }),
                )
            },
        )
    }
}

/**
 * 各栏候选（每条候选单独放进来评估两次）的排序结果，在后台线程算好（手机上一次要十几到几十毫秒，不能卡住点按）。
 * 计算期间页面继续显示上一份结果；数量、勾选状态、能否再加一份一律直接看当前配置，不等这里。
 */
@Immutable
internal class RankerRows(
    val weaponRows: List<WeaponAffixRow>,
    /** 其它增益各分栏实际列出的行（ev.shownOtherRows，搜索词在主线程过滤）。 */
    val otherRows: Map<String, List<OtherRowScore>>,
)

@Composable
internal fun rememberRankerRows(state: RankerPageState): RankerRows? {
    val evaluator = state.evaluator
    val config = state.config
    val filter = state.waFilterType
    val showInactive = state.showInactive
    return produceState<RankerRows?>(null, evaluator, config, filter, showInactive) {
        value = withContext(Dispatchers.Default) { computeRankerRows(evaluator, config, filter, showInactive) }
    }.value
}

/** 各栏候选的排序结果（纯计算，后台线程调用；测试直接调用）。 */
internal fun computeRankerRows(
    evaluator: LoadoutEvaluator,
    config: LoadoutConfig,
    filter: Int?,
    showInactive: Boolean,
): RankerRows = RankerRows(
    weaponRows = evaluator.weaponAffixRows(config, filter),
    otherRows = LoadoutIndex.OTHER_SLOTS.associateWith { slot -> evaluator.shownOtherRows(config, slot, "", showInactive) },
)
