package com.nightreign.relicchecker.gamedata.ranker

import java.math.BigDecimal
import java.math.RoundingMode

/**
 * 「增伤排名」配置部分的文案（与桌面端同一张表，见 [RANKER_TEXT_TABLE]）。
 *
 * - [t]：按点号路径取一条（缺键时退回键名，测试会拦下）；
 * - [fmt] / [f]：按位置替换 `{n}`，缺的参数替换成空串（Windows fmt、macOS LoadoutText.fmt 同一口径）。
 *   数字参数按 JS 的 `String(value)` 写法输出（整数不带「.0」），保证三端拼出来的句子逐字一致。
 */
object RankerText {
    val table: Map<String, String> get() = RANKER_TEXT_TABLE

    fun t(key: String): String = RANKER_TEXT_TABLE[key] ?: key

    fun fmt(template: String, vararg args: Any?): String {
        val out = StringBuilder(template.length + 16)
        var index = 0
        while (index < template.length) {
            val char = template[index]
            if (char == '{') {
                val close = template.indexOf('}', index + 1)
                val number = if (close > index + 1) template.substring(index + 1, close).toIntOrNull() else null
                if (number != null && template.substring(index + 1, close).all { it in '0'..'9' }) {
                    out.append(if (number < args.size) display(args[number]) else "")
                    index = close + 1
                    continue
                }
            }
            out.append(char)
            index += 1
        }
        return out.toString()
    }

    fun f(key: String, vararg args: Any?): String = fmt(t(key), *args)

    /** 参数的文字形式：null → 空串；浮点数按 JS 的 String(number)（1.0 → "1"）。 */
    internal fun display(value: Any?): String = when (value) {
        null -> ""
        is Double -> jsNumber(value)
        is Float -> jsNumber(value.toDouble())
        else -> value.toString()
    }

    /** JS `String(number)` 的常见情形：整数值不带小数点，其余取最短往返表示。 */
    fun jsNumber(value: Double): String {
        if (value.isNaN()) return "NaN"
        if (value.isInfinite()) return if (value > 0) "Infinity" else "-Infinity"
        if (value == Math.floor(value) && Math.abs(value) < 1e21) {
            return BigDecimal(value).setScale(0, RoundingMode.UNNECESSARY).toPlainString().let { if (it == "-0") "0" else it }
        }
        return value.toString()
    }
}
