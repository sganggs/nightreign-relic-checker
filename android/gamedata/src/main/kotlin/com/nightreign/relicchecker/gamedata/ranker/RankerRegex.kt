package com.nightreign.relicchecker.gamedata.ranker

/**
 * 正则的跨平台写法。
 *
 * Android 的 java.util.regex 基于 ICU，**不支持** `(?U)`（UNICODE_CHARACTER_CLASS）：带它的 Pattern 一编译就抛异常，
 * 放在 object / companion 的初始化里会变成 ExceptionInInitializerError，整份数据解析失败。另外两个平台的 `\s` / `\d`
 * 含义也不同：桌面 JVM 默认只认 ASCII，ICU 按 Unicode。这里一律写成显式字符类，与 JS 的 `\s`（Unicode 空白，
 * 含全角空格 U+3000）和 `\d`（只认 ASCII 数字）逐字符相同，三端（Windows JS、macOS、Android）同一口径。
 */
internal object RankerRegex {
    /** JS `\s`：ASCII 空白 + U+00A0、U+1680、U+2000–U+200A、U+2028、U+2029、U+202F、U+205F、U+3000、U+FEFF。 */
    const val WS: String = "[\\t\\n\\u000B\\f\\r \\u00A0\\u1680\\u2000-\\u200A\\u2028\\u2029\\u202F\\u205F\\u3000\\uFEFF]"

    /** JS `\d`：只认 ASCII 数字。 */
    const val DIGIT: String = "[0-9]"
}
