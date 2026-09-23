package com.nightreign.relicchecker.ui.bosses

import com.nightreign.relicchecker.gamedata.bosses.BossPageText
import com.nightreign.relicchecker.gamedata.bosses.BossRoleText
import com.nightreign.relicchecker.gamedata.bosses.BossRowText
import java.io.File
import java.lang.reflect.Modifier
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * 文案表里的串必须真的用在页面上，别留成只给测试看的摆设（Windows 端 bosses.test.mjs
 * 「双端文案表」与 bosses_roles.test.mjs「场合文案都来自常量表，并且真的用在了页面上」的同一口径）。
 *
 * 「用上」= 页面源码（ui/bosses）或 :gamedata 的展示逻辑（bosses 包）里出现 `对象名.成员名` 的限定引用；
 * 只在文案表内部被别的文案函数拼进去的几个成员列在 [internalOnly] 里。
 */
class BossesTextUsageTest {
    private val pageSources: String by lazy { sources("src/main/kotlin/com/nightreign/relicchecker/ui/bosses") }
    private val gamedataSources: String by lazy {
        sources("../gamedata/src/main/kotlin/com/nightreign/relicchecker/gamedata/bosses")
    }

    private fun sources(path: String): String {
        val dir = File(path)
        assertTrue("找不到源码目录 ${dir.absolutePath}", dir.isDirectory)
        return dir.walkTopDown().filter { it.isFile && it.extension == "kt" }.joinToString("\n") { it.readText() }
    }

    /** 对象上的全部公开成员名：const 字段、属性 getter 对应的名字、函数名。 */
    private fun memberNames(type: Class<*>): Set<String> {
        val fields = type.declaredFields
            .filter { Modifier.isStatic(it.modifiers) && it.name != "INSTANCE" && !it.isSynthetic }
            .map { it.name }
        val methods = type.declaredMethods
            .filter { Modifier.isPublic(it.modifiers) && !it.isSynthetic && !it.name.contains('$') }
            .map { method ->
                if (method.name.startsWith("get") && method.parameterCount == 0 && method.name.length > 3) {
                    method.name.removePrefix("get").replaceFirstChar { it.lowercase() }
                } else {
                    method.name
                }
            }
        return (fields + methods).toSet()
    }

    private val internalOnly = setOf(
        // 只在 threatTierCaption / multiGroupNote / poiseCaption / attackRateText / depthWeightText 内部拼进去
        "BossRoleText.threatTierLabel",
        "BossRoleText.multiGroupNameLimit",
        "BossRowText.abnormalPoiseTakenCaption",
        "BossRowText.attackRateUnchanged",
        "BossRowText.depthWeightZero",
    )

    @Test
    fun everyTextTableEntryIsUsedByThePage() {
        val tables = listOf(BossRowText::class.java, BossRoleText::class.java, BossPageText::class.java)
        val unused = tables.flatMap { type ->
            memberNames(type).map { "${type.simpleName}.$it" }
        }.filter { name ->
            name !in internalOnly && !pageSources.contains(name) && !gamedataSources.contains(name)
        }
        assertTrue("文案表里定义了却没有用到：$unused", unused.isEmpty())
        // 表确实被读到了（反射没把成员全漏掉）
        assertTrue(memberNames(BossRoleText::class.java).containsAll(listOf("threatTierNote", "hiddenSummary", "builtinRoleNames")))
        assertTrue(memberNames(BossRowText::class.java).containsAll(listOf("mutationStackNote", "poiseCaption")))
    }

    @Test
    fun pageTextComesFromTheTablesNotStaleWording() {
        // 上一版自拟、两端都已删掉的说法不能再出现；分组名不再写「野外首领」（游戏文本是「场景头目」）
        listOf("标签存疑", "场合依据", "全部依据", "两边都出现", "\"野外首领\"").forEach { stale ->
            assertFalse("旧文案「$stale」还在页面源码里", pageSources.contains(stale))
        }
        // 分组标题只从 BossGroup / BossRoleText 取，页面里不另写分组名字面量
        listOf("\"守夜首领\"", "\"据点首领\"", "\"场景头目\"", "\"封印监牢\"", "\"其它场合\"").forEach { literal ->
            assertFalse("页面源码里不应直接写分组名 $literal", pageSources.contains(literal))
        }
    }
}
