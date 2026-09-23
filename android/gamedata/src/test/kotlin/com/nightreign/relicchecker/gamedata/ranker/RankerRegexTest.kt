package com.nightreign.relicchecker.gamedata.ranker

import java.io.File
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

// 正则的跨平台口径（Android 真机上发现的问题）：ICU 正则不支持 `(?U)`，带它的 Pattern 放在 object / companion 初始化里
// 会让 buffs 解析直接抛 ExceptionInInitializerError（页面只剩「无法载入游戏数据」）。改成显式字符类后，
// 空白按 JS 的 \s（含全角空格）、数字按 JS 的 \d（只认 ASCII）匹配，桌面 JVM 与 Android 结果相同。
class RankerRegexTest {
    @Test
    fun `源码里不再出现 Android 不支持的 (?U)`() {
        val dir = listOf(
            File("src/main/kotlin/com/nightreign/relicchecker/gamedata"),
            File("gamedata/src/main/kotlin/com/nightreign/relicchecker/gamedata"),
        ).first { it.isDirectory }
        val offenders = dir.walkTopDown().filter { it.extension == "kt" }
            .filter { file -> file.readLines().any { line -> "(?U)" in line && "Regex(" in line } }
            .map { it.name }.toList()
        assertTrue(offenders.isEmpty(), "这些文件还在用 (?U)：$offenders")
    }

    @Test
    fun `空白按 JS 的 s，数字只认 ASCII`() {
        val ws = Regex("^${RankerRegex.WS}+$")
        listOf(" ", "\t", "\n", "\u000B", " ", " ", "　", "﻿").forEach { assertTrue(ws.matches(it), "空白 U+%04X".format(it[0].code)) }
        listOf("a", "_", "0", "​").forEach { assertTrue(!ws.matches(it), "不是空白：$it") }
        val digit = Regex("^${RankerRegex.DIGIT}+$")
        assertTrue(digit.matches("0123456789"))
        assertTrue(!digit.matches("３"), "全角数字不算 \\d（与 JS 一致）")
    }

    @Test
    fun `各处用到的正则在全角空格与大小写下照常工作`() {
        assertEquals("专注值不足版 R2", SkillTextZh.fpText("无　FP　版 R2"))
        assertEquals("专注值不足版", SkillTextZh.fpText("　No　FP"))
        assertEquals("[Weapon] X", BuffRankerIndex.familyKey(BuffEntry(paramName = "[Weapon] X　-　potency 2")))
        assertEquals("[Relic] X", BuffRankerIndex.familyKey(BuffEntry(paramName = "[Relic] X　+3")))
        assertEquals("[Item] X", BuffRankerIndex.familyKey(BuffEntry(paramName = "[Item - Level 3]　X")))
        assertEquals("Revenant", BuffRankerIndex.characterKey(BuffEntry(paramName = "[Skill -　Revenant　] X")))
        assertEquals("连刺破露滴", LoadoutText.stripTierSuffix("连刺破露滴（第2层）"))
        assertEquals("连刺破露滴（第２层）", LoadoutText.stripTierSuffix("连刺破露滴（第２层）"), "全角数字不是档位后缀（与 JS 一致）")
        assertEquals("提升攻击力", LoadoutText.familyName("提升攻击力　＋２"))
        val info = BuffWeaponAffixInfo(attachEffectId = 1, paramName = "Improved Skill Attack Power　-　Potency 3")
        assertEquals("param:Improved Skill Attack Power", LoadoutIndex.weaponAffixFamilyKey(info))
    }
}
