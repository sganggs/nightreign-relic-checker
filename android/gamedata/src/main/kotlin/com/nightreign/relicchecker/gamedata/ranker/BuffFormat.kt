package com.nightreign.relicchecker.gamedata.ranker

import java.math.BigDecimal
import java.math.RoundingMode

/**
 * 数值格式化（macOS 端 BuffFormat、Windows 端 fmtNumber / fmtMultiplier / fmtGain / fmtPercent / fmtFlat / fmtDuration）。
 *
 * 一律按十进制精确值「四舍五入、半数进位」，与 JS 的 toFixed 同一取舍，不受系统语言（小数点写成逗号）影响。
 * 页面约定倍率写「×1.25」（去掉多余的 0，[multiplier]）；对拍行与需要定宽的地方用 [fixed]。
 */
object BuffFormat {
    /** 固定小数位（JS `toFixed`，负数保留负号：-0.04 → "-0.0"）：1.25 → "1.250"（digits = 3）。 */
    fun fixed(value: Double, digits: Int): String {
        if (!value.isFinite()) return "—"
        if (value < 0.0) return "-" + fixed(-value, digits)
        return BigDecimal(value).setScale(digits, RoundingMode.HALF_UP).toPlainString()
    }

    /** 去掉多余 0：1.250 → 1.25、2.0 → 2（Windows fmtNumber、macOS BuffFormat.trim）。 */
    fun trim(value: Double, digits: Int = 3): String {
        if (!value.isFinite()) return "—"
        var text = fixed(value, digits)
        if (text.contains('.')) {
            text = text.trimEnd('0').trimEnd('.')
        }
        return text.ifEmpty { "0" }
    }

    /** 「×1.25」。没有构成（null）时写「—」。 */
    fun multiplier(value: Double?, digits: Int = 3): String = if (value == null) "—" else "×" + trim(value, digits)

    /** 定宽的「×1.250」（Windows fmtMultiplier；汇总表需要对齐时用）。 */
    fun multiplierFixed(value: Double?): String = if (value == null) "—" else "×" + fixed(value, 3)

    /** 相对增幅：1.153 → +15.3%。 */
    fun gain(value: Double?): String {
        if (value == null || !value.isFinite()) return "—"
        val percent = (value - 1.0) * 100.0
        return (if (percent >= 0.0) "+" else "") + fixed(percent, 1) + "%"
    }

    /** 占比：0.5 → 50.0%。 */
    fun percent(share: Double, digits: Int = 1): String = fixed(share * 100.0, digits) + "%"

    /** 攻击力加算带符号：正数写「+」，负数照常是「-」，四舍五入后为 0 写「0」（Windows fmtFlat）。 */
    fun flat(value: Double, digits: Int = 1): String {
        var text = trim(value, digits)
        if (text == "-0") text = "0"
        return if (value > 0.0 && text != "0") "+$text" else text
    }

    /** 加算是否值得显示：四舍五入到一位小数后不为 0。 */
    fun hasFlat(value: Double): Boolean = Math.abs(value) >= 0.05

    /** 持续时间：-1（或 permanent）→ 永久，0 → 瞬间，其余「30 秒」。 */
    fun duration(seconds: Double, permanent: Boolean = false): String = when {
        permanent || seconds < 0.0 -> "永久"
        seconds == 0.0 -> "瞬间"
        else -> trim(seconds, 1) + " 秒"
    }
}
