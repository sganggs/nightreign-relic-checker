package com.nightreign.relicchecker.gamedata.heroes

import java.math.BigDecimal
import java.math.RoundingMode
import kotlin.math.abs
import kotlin.math.floor
import kotlin.math.pow
import kotlin.math.sign
import kotlin.math.truncate

/**
 * 派生值换算表（CalcCorrectGraph 的一行）。
 *
 * 求值规则与《艾尔登法环》通用公式一致：落在第 i 段 [stageMaxVal[i], stageMaxVal[i+1]]
 * 时，用 `adjPt[i]`（下段下标）作指数；`adjPt == 1` 即纯线性。逐行移植 macOS
 * HeroGrowthGraph（value / integerValue 两条路径、端点钳位、可用性判定都相同）。
 */
data class HeroGrowthGraph(
    val id: Int,
    val name: String = "",
    val stageMaxVal: List<Double>,
    val stageMaxGrowVal: List<Double>,
    val adjPt: List<Double>,
    val linear: Boolean = adjPt.isNotEmpty() && adjPt.all { it == 1.0 },
    val usedFor: List<String> = emptyList(),
) {
    /** 至少两段、三个数组等长才能求值（Windows isUsableGraph 同一条）。 */
    val isUsable: Boolean
        get() = stageMaxVal.size >= 2 &&
            stageMaxGrowVal.size == stageMaxVal.size &&
            adjPt.size == stageMaxVal.size

    /** value 落在哪一段（返回下段下标 i，区间 [x[i], x[i+1]]）。 */
    internal fun segmentIndex(value: Double): Int {
        val last = stageMaxVal.size - 2
        if (last < 0) return 0
        for (index in 0..last) {
            if (value <= stageMaxVal[index + 1]) return index
        }
        return last
    }

    /** 浮点求值：负重上限（带指数的 220）用这个；不可用的图表返回 0，由调用方跳过。 */
    fun value(stat: Int): Double {
        if (!isUsable) return 0.0
        val value = stat.toDouble()
        val firstX = stageMaxVal.first()
        val lastX = stageMaxVal.last()
        if (value <= firstX) return stageMaxGrowVal.first()
        if (value >= lastX) return stageMaxGrowVal.last()
        val index = segmentIndex(value)
        val x0 = stageMaxVal[index]
        val x1 = stageMaxVal[index + 1]
        val y0 = stageMaxGrowVal[index]
        val y1 = stageMaxGrowVal[index + 1]
        if (!(x1 > x0)) return y0
        val adjustment = adjPt[index]
        if (adjustment == 1.0) {
            return y0 + (y1 - y0) * (value - x0) / (x1 - x0)
        }
        val ratio = (value - x0) / (x1 - x0)
        val growth = if (adjustment > 0) ratio.pow(adjustment) else 1 - (1 - ratio).pow(abs(adjustment))
        return y0 + (y1 - y0) * growth
    }

    /**
     * 整数求值（向下取整）。血量 / 专注值 / 精力所在的 100 / 101 / 104 三行端点都是整数且
     * adjPt 全为 1，这里用整数除法精确算 floor，避免浮点误差把 240 变成 239；
     * 端点不是整数 / 这一段带指数时退回 normalize + floor。
     */
    fun integerValue(stat: Int): Int {
        if (!isUsable) return 0
        val input = stat.toDouble()
        val firstX = stageMaxVal.first()
        val lastX = stageMaxVal.last()
        if (input <= firstX) return floor(stageMaxGrowVal.first()).toInt()
        if (input >= lastX) return floor(stageMaxGrowVal.last()).toInt()
        val index = segmentIndex(input)
        val x0 = stageMaxVal[index]
        val x1 = stageMaxVal[index + 1]
        val y0 = stageMaxGrowVal[index]
        val y1 = stageMaxGrowVal[index + 1]
        if (!(x1 > x0)) return floor(y0).toInt()
        if (adjPt[index] == 1.0 && x0.isWhole() && x1.isWhole() && y0.isWhole() && y1.isWhole()) {
            val numerator = (y1.toInt() - y0.toInt()) * (stat - x0.toInt())
            val denominator = x1.toInt() - x0.toInt()
            return y0.toInt() + HeroStatsMath.floorDivide(numerator, denominator)
        }
        return floor(HeroStatsMath.normalize(value(stat))).toInt()
    }

    private fun Double.isWhole(): Boolean = this == floor(this)
}

/** HeroStatsMath.apply 的结果。 */
data class HeroApplyResult(
    /** 叠加并钳位后的属性。 */
    val stats: Map<String, Int>,
    /** 各词条增减量之和（未钳位的请求值）。 */
    val requested: Map<String, Int>,
    /** 被钳到 1 的属性，按展示顺序排。 */
    val clamped: List<String>,
    /** 被钳属性钳位前的原值。 */
    val clampedFrom: Map<String, Int>,
)

/** 纯换算（逐条移植 macOS HeroStatsMath）。 */
object HeroStatsMath {
    /** 属性下限：转职遗物把某项减到 0 或负数时钳到 1。 */
    const val MINIMUM_STAT = 1

    /** 向下取整的整数除法；除数为 0 时返回 0 而不是崩。 */
    fun floorDivide(numerator: Int, denominator: Int): Int =
        if (denominator == 0) 0 else Math.floorDiv(numerator, denominator)

    /**
     * 四舍五入到整数、0.5 远离零（Swift `.rounded()` 的默认口径）。
     * x − trunc(x) 在 IEEE 754 下是精确的，所以这里没有「先加 0.5 再 floor」的边界误差。
     */
    fun roundHalfAwayFromZero(value: Double): Double {
        if (!value.isFinite()) return value
        val whole = truncate(value)
        val fraction = value - whole
        return if (abs(fraction) >= 0.5) whole + sign(value) else whole
    }

    /**
     * 浮点噪声归一：CalcCorrectGraph 的分段斜率都是有理数，真值离整数至少 0.01，
     * 先抹掉 1e-9 以下的尾巴再 floor，结果与整数精确运算逐格一致（macOS / Windows 同一条公式）。
     */
    fun normalize(value: Double): Double {
        if (!value.isFinite()) return value
        return roundHalfAwayFromZero(value * 1e9) / 1e9
    }

    /** 保留若干位小数（四舍五入、远离零），负重上限用 1 位。 */
    fun round(value: Double, digits: Int): Double {
        if (digits < 0 || !value.isFinite()) return value
        val scale = 10.0.pow(digits)
        return roundHalfAwayFromZero(value * scale) / scale
    }

    /**
     * 一整套属性的派生值：每项派生值只吃一项属性（血量←生命力、专注值←集中力、
     * 精力 / 负重上限←耐力），走各自的 CalcCorrectGraph。整数项向下取整，负重上限保留 1 位小数。
     * 缺 growthGraph、图表不可用或缺来源属性时**不写这一项**（页面给破折号，而不是 0）。
     */
    fun derivedValues(
        stats: Map<String, Int>,
        names: HeroStatNames,
        graphs: Map<Int, HeroGrowthGraph>,
    ): Map<String, Double> {
        val result = LinkedHashMap<String, Double>()
        for (entry in names.orderedDerived) {
            val graph = graphs[entry.graphId] ?: continue
            if (!graph.isUsable) continue
            val source = stats[entry.fromStat] ?: continue
            result[entry.key] = if (entry.integer) {
                graph.integerValue(source).toDouble()
            } else {
                round(graph.value(source), 1)
            }
        }
        return result
    }

    /**
     * 把若干条转职遗物的增减量叠加到基础属性上。多条词条同时生效时增减量直接相加；
     * 结果小于 1 的属性钳到 1，`clamped` 按 [order]（页面属性展示顺序）列出被钳的属性，
     * `clampedFrom` 保留钳位前的原值。基础表里根本没有的属性不编一个数字出来，也不记钳位。
     */
    fun apply(
        deltas: List<Map<String, Int>>,
        base: Map<String, Int>,
        order: List<String> = emptyList(),
    ): HeroApplyResult {
        val requested = LinkedHashMap<String, Int>()
        for (delta in deltas) {
            for ((key, value) in delta) {
                requested[key] = (requested[key] ?: 0) + value
            }
        }
        val stats = LinkedHashMap(base)
        val clampedFrom = LinkedHashMap<String, Int>()
        for ((key, change) in requested) {
            val baseValue = base[key] ?: continue
            val raw = baseValue + change
            if (raw < MINIMUM_STAT) {
                stats[key] = MINIMUM_STAT
                clampedFrom[key] = raw
            } else {
                stats[key] = raw
            }
        }
        val clamped = order.filter { it in clampedFrom }.toMutableList()
        clampedFrom.keys.sorted().forEach { if (it !in clamped) clamped.add(it) }
        return HeroApplyResult(stats, requested, clamped, clampedFrom)
    }

    /**
     * 与 C / Swift `String(format: "%.Nf")` 同口径的定点格式化：按 double 的**精确二进制值**
     * 做 half-even 舍入（Java 的 String.format 会先取最短十进制表示再 half-up，个别边界不同）。
     */
    internal fun fixed(value: Double, digits: Int): String =
        BigDecimal(value).setScale(digits.coerceAtLeast(0), RoundingMode.HALF_EVEN).toPlainString()
}
