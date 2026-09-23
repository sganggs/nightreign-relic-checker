package com.nightreign.relicchecker.gamedata.bosses

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

/**
 * 双端文案表（macOS 的 checkBossDataParityText：BossRowText / BossRoleText / BossNameBadge /
 * BossDeepCoverage；Windows 的 TEXT / ROLE_TEXT）。这里各自写死同一批字面量，任一端改文案立刻红。
 */
class BossTextTest {
    @Test
    fun `BossRowText 文案表逐字一致`() {
        val expected = listOf(
            "labelUncertainBadge" to (BossRowText.labelUncertainBadge to "标签为社区推测"),
            "deepRowBadge" to (BossRowText.deepRowBadge to "深夜数值"),
            "deepRowBadgePartial" to (BossDeepCoverage.SOME.badgeText.orEmpty() to "部分行有深夜数值"),
            "deepExclusiveBadge" to (BossRowText.deepExclusiveBadge to "深夜专属修正"),
            "deepExclusiveBadgePartial" to (BossDeepCoverage.SOME.exclusiveBadgeText.orEmpty() to "部分行有深夜专属修正"),
            "nameFallbackBadge" to (BossRowText.nameFallbackBadge to "参考译名 · 非本作游戏文本"),
            "nameApproxBadge" to (BossRowText.nameApproxBadge to "近似匹配"),
            "nameEnglishOnlyBadge" to (BossNameBadge.ENGLISH_ONLY.text to "仅英文名"),
            "nameNoGameNameBadge" to (BossNameBadge.NO_GAME_NAME.text to "无游戏内名称"),
            "nameManualBadge" to (BossNameBadge.MANUAL.text to "名称手工补录"),
            "nameInferredBadge" to (BossNameBadge.INFERRED.text to "名称按 ID 推断"),
            "nameCommunityBadge" to (BossNameBadge.COMMUNITY.text to "社区资料"),
            "hiddenToggleTitle" to (BossRowText.hiddenToggleTitle to "显示隐藏实体"),
            "hiddenToggleHelp" to (BossRowText.hiddenToggleHelp to "召唤物 / 投射物等非首领实体"),
            "noRewardGroupNote" to (BossRowText.noRewardGroupNote to "该组不掉任何奖励（getSoul / 掉落表全为 0 或 -1）"),
            "noRewardRowNote" to (BossRowText.noRewardRowNote to "该行不掉任何奖励"),
            "noDepthStatsText" to (BossRowText.noDepthStatsText to "该行无深夜数值"),
            "mutationTitle" to (BossTestData.dataset.mutationTitle to "变异个体"),
            "mutationPickerTitle" to (BossRowText.mutationPickerTitle to "按变异个体计算"),
            "mutationPickerNone" to (BossRowText.mutationPickerNone to "无"),
            "mutationStackNote" to (BossRowText.mutationStackNote to "变异倍率在其它缩放之上再乘一层，按参数结构推断"),
            "mutationCountNote" to (BossRowText.mutationCountNote to "表里是「有几只被变异」的只数，不是百分比概率"),
            "attackRateUnchanged" to (BossRowText.attackRateUnchanged to "不变"),
            "depthWeightZero" to (BossRowText.depthWeightZero to "该深度不会出现"),
            "multiplayerAuditSummary" to (
                BossRowText.multiplayerAuditSummary to
                    "多人不是简单乘倍：血量按档位从 ×1 到 ×3 不等（最终 Boss 档才是 ×2 / ×3，" +
                    "野外常见档 7740 只有 ×1.1 / ×1.2，突袭档 98810 / 98815 完全不加血）；" +
                    "7744 / 7753 / 7754 / 7758 四档的敌人攻击力还会上浮 10% / 20%；" +
                    "防御、卢恩与掉落、异常触发阈值三项人数缩放一概不碰，" +
                    "变的只是异常累积量与发动伤害倍率（都往下走，人越多越难上异常）。"
                ),
        )
        expected.forEach { (key, pair) -> assertEquals(pair.second, pair.first, "双端文案 $key") }
        assertEquals("多人攻击 ×1.1", BossRowText.multiplayerAttackBadge(1.1))
        assertEquals("权重 1600", BossRowText.depthWeightText(1600))
        assertEquals("5 条数值行", BossRowText.rowCount(5))
        assertEquals("1 条数值行", BossRowText.rowCount(1))
        assertEquals("承受削韧倍率异常（0）", BossRowText.abnormalPoiseTakenCaption(0.0))
    }

    @Test
    fun `BossRoleText 文案表逐字一致`() {
        val expected = listOf(
            "groupNightlord" to (BossGroup.NIGHTLORD.title to "夜王"),
            "groupNight" to (BossGroup.NIGHT.title to "守夜首领"),
            "groupStronghold" to (BossGroup.STRONGHOLD.title to "据点首领"),
            "groupField" to (BossGroup.FIELD.title to "场景头目"),
            "groupEvergaol" to (BossGroup.EVERGAOL.title to "封印监牢"),
            "groupOther" to (BossGroup.OTHER.title to "其它场合"),
            "groupSummon" to (BossGroup.SUMMON.title to "随从/召唤物"),
            "groupUnplaced" to (BossGroup.UNPLACED.title to "未放置"),
            "threatTierLabel" to (BossRoleText.threatTierLabel to "威胁档位"),
            "threatTierNote" to (
                BossRoleText.threatTierNote to
                    "威胁档位只是多人缩放档位（Field / Night Boss Threat），不代表出场场合；分组按地图放置判定的出场场合"
                ),
            "rolesMissing" to (BossRoleText.rolesMissing to "出场场合：数据未内置"),
            "evidenceMissing" to (BossRoleText.evidenceMissing to "出处：数据未内置"),
            "roleSectionTitle" to (BossRoleText.roleSectionTitle to "出场场合"),
            "roleSectionDetail" to (BossRoleText.roleSectionDetail to "按地图放置与抽选参数判定；分组看这里，不看威胁档位"),
            "rowRolesTitle" to (BossRoleText.rowRolesTitle to "逐行场合"),
            "evidenceExpand" to (BossRoleText.evidenceExpand to "展开全部出处"),
            "evidenceCollapse" to (BossRoleText.evidenceCollapse to "只看每个场合的第一条出处"),
            "hiddenGroupMark" to (BossRoleText.hiddenGroupMark to "（默认隐藏）"),
            "groupPickerHelp" to (BossRoleText.groupPickerHelp to "按出场场合分组；一组首领可以同时出现在多个分组里"),
            "hiddenToggleRoleHelp" to (BossRoleText.hiddenToggleRoleHelp to "也控制「未放置」「随从/召唤物」两个场合（分组与展开区的行）"),
            "evidenceMore" to (BossRoleText.evidenceMore(3) to "另有 3 条出处"),
            "hiddenRows" to (BossRoleText.hiddenRows(2) to "另有 2 条「未放置」/「随从/召唤物」行已隐藏，打开「显示隐藏实体」查看"),
            "rowCountVisible" to (BossRoleText.rowCount(4, 0) to "4 条数值行"),
            "rowCountHidden" to (BossRoleText.rowCount(4, 1) to "4 条数值行（另 1 条已隐藏）"),
            "overviewTitle" to (BossRoleText.overviewTitle(14) to "出场场合说明（14 种）"),
            "roleCountBosses" to (BossRoleText.roleCountText(40, 0) to "40 组"),
            "roleCountBoth" to (BossRoleText.roleCountText(1, 6) to "1 组 · 夜王 6"),
            "roleCountLords" to (BossRoleText.roleCountText(0, 18) to "夜王 18"),
            "roleCountNone" to (BossRoleText.roleCountText(0, 0) to "0 组"),
            "auditTitle" to (BossRoleText.auditTitle(4) to "与威胁档位的对照（数据集 notes.roleAudit，4 条）"),
            "multiGroupNote" to (
                BossRoleText.multiGroupNote(2, listOf("甲", "乙")) to
                    "有 2 组首领按出场场合同时属于多个分组（甲、乙），它们在各个分组下都会出现：" +
                    "卡头列出全部场合，折叠态代表行跟着当前分组走，展开后每行标了自己的场合与出处。"
                ),
            "hiddenSummaryBoth" to (
                BossRoleText.hiddenSummary(listOf("甲", "乙"), listOf("丙")) to
                    "另有 2 组被判定为非首领实体（甲、乙），判据是整组不掉任何奖励，且不吃削韧 / 连社区资料都认不出 / 社区标为杂兵；" +
                    "另有 1 组只出现在「未放置」「随从/召唤物」两个场合（丙）。它们默认不在列表里，" +
                    "展开区里只出现在这两个场合的数值行也默认隐藏；" +
                    "需要时打开工具条的「显示隐藏实体」，分组筛选里会多出「随从/召唤物」「未放置」两项。"
                ),
            "hiddenSummaryNone" to (BossRoleText.hiddenSummary(emptyList(), emptyList()) to ""),
        )
        expected.forEach { (key, pair) -> assertEquals(pair.second, pair.first, "双端文案 $key") }
        val many = (1..13).map { "名$it" }
        assertTrue(BossRoleText.multiGroupNote(13, many).contains("名12 等）"))
        assertFalse(BossRoleText.multiGroupNote(13, many).contains("名13"))
        assertEquals(
            mapOf(
                "night" to "守夜首领", "prelude" to "守夜前哨", "field" to "场景头目", "stronghold" to "据点首领",
                "mine" to "坑道精英", "evergaol" to "封印监牢", "tower" to "大空洞高塔首领", "raid" to "突袭事件",
                "invader" to "黑夜入侵者", "event" to "地图事件", "nightlord" to "夜王战", "summon" to "随从/召唤物",
                "other" to "其他地图", "unplaced" to "未放置",
            ),
            BossRoleText.builtinRoleNames,
        )
        assertEquals("场景头目 · 2 行", BossPageText.roleRowsChip("场景头目", 2))
    }

    @Test
    fun `数字格式 两位小数 四舍六入与 C printf 同口径`() {
        assertEquals("1.23", BossFormat.decimal(1.2345, 2))
        assertEquals("1.01", BossFormat.decimal(1.006, 2))
        assertEquals("1.1", BossFormat.decimal(1.1, 2))
        assertEquals("1.235", BossFormat.decimal(1.2346, 3))
        assertEquals("—", BossFormat.decimal(Double.POSITIVE_INFINITY))
        assertEquals("2", BossFormat.decimal(2.0))
        assertEquals("120", BossFormat.decimal(120.0, 0))
        assertEquals("0", BossFormat.decimal(0.0, 3))
        // 二进制下 1.005 实际略小于 1.005，C printf 给 1.00 → 去零后 1（Java String.format 会给 1.01）
        assertEquals("1", BossFormat.decimal(1.005, 2))
        assertEquals("0.12", BossFormat.decimal(0.125, 2), "正好落在 .5 上时五成双")
        assertEquals("-1", BossFormat.decimal(-1.0, 0))
        assertEquals("×1.35", BossFormat.multiplier(1.35))
        assertEquals("0", BossFormat.integer(0))
        assertEquals("-1,234", BossFormat.integer(-1234))
        assertEquals("999", BossFormat.integer(999))
        assertEquals("1,000", BossFormat.integer(1000))
    }

    @Test
    fun `档位说明 scalingCaption 三支`() {
        assertEquals("无缩放档位", BossRowText.scalingCaption(null, null))
        assertEquals("档位 #98815", BossRowText.scalingCaption(98815, null))
        assertEquals("档位 #98815", BossRowText.scalingCaption(98815, ""))
        assertEquals("档位 #98815 · 其它档位", BossRowText.scalingCaption(98815, "其它档位"))
    }

    @Test
    fun `页面小字 captions 与 macOS 同文案`() {
        val dataset = BossTestData.dataset
        val gladius = BossTestData.lord(0)
        val main = BossTestData.row(75000020)
        assertEquals("主战血量", BossCaptions.hpMetricTitle(gladius))
        assertEquals("主战血量 · 最高", BossCaptions.hpMetricTitle(BossTestData.lord(13)))
        assertEquals("血量", BossCaptions.hpMetricTitle(BossTestData.boss("Bell Bearing Hunter@3100")))
        assertEquals("含常驻缩放", BossCaptions.summaryHp(main, BossPartySize.SOLO, BossNightMode.NORMAL, "深度", null))
        assertEquals("1 人 11,328", BossCaptions.summaryHp(main, BossPartySize.DUO, BossNightMode.NORMAL, "深度", null))
        assertEquals("深度 3 数值", BossCaptions.summaryHp(main, BossPartySize.SOLO, BossNightMode.DEPTH3, "深度", null))
        assertEquals("深度 5 · 1 人 24,468", BossCaptions.summaryHp(main, BossPartySize.TRIO, BossNightMode.DEPTH5, "深度", null))
        val hunter = BossTestData.row(31000020)
        val mutation = dataset.mutation(113140)!!
        assertEquals(
            "深度 3 · 1 人 5,877 · 变异 ×1.15",
            BossCaptions.summaryHp(hunter, BossPartySize.TRIO, BossNightMode.DEPTH3, "深度", mutation),
        )
        assertEquals("常驻基准", BossCaptions.summaryAttack(BossNightMode.NORMAL))
        assertEquals("含深度倍率", BossCaptions.summaryAttack(BossNightMode.DEPTH1))
        assertEquals(
            "参数原值 3,200 · 总倍率 ×3.54",
            BossCaptions.rowHp(main, main.stats(BossPartySize.SOLO), "深度"),
        )
        assertEquals(
            "参数原值 3,200 · 总倍率 ×7.6464 · 深度 5",
            BossCaptions.rowHp(main, main.stats(BossPartySize.TRIO, BossNightMode.DEPTH5), "深度"),
        )
        val hunterStats = hunter.stats(BossPartySize.TRIO, BossNightMode.DEPTH3, mutation)
        assertTrue(BossCaptions.rowHp(hunter, hunterStats, "深度").endsWith(" · 深度 3 · 变异 ×1.15"))
        assertEquals("基准 ×3.36", BossCaptions.rowAttack(main, main.stats(BossPartySize.TRIO)))
        val evergaol = BossTestData.row(35600110)
        assertEquals("基准 ×3 · 多人 ×1.1", BossCaptions.rowAttack(evergaol, evergaol.stats(BossPartySize.DUO)))
        assertEquals(
            "基准 " + BossFormat.multiplier(hunter.depthStats.getValue(3).attackRateBase, 3) + " · 变异 ×1.15",
            BossCaptions.rowAttack(hunter, hunterStats),
        )
        assertEquals("韧性 120 ÷ 承受削韧 0.55", BossCaptions.rowPoise(main, main.stats(BossPartySize.DUO)))
        assertEquals("按 2 人换算 · 已含常驻缩放、深夜修正与深度倍率", BossCaptions.depthTable(BossPartySize.DUO, null))
        assertEquals("按 3 人换算 · 含变异 #113140 · 已含常驻缩放、深夜修正与深度倍率", BossCaptions.depthTable(BossPartySize.TRIO, mutation))
        assertEquals(
            "该行有深夜数值：深度 5 血量 24,468（1 人）、攻击 ×11.122，可用顶部的模式选择切换。",
            BossCaptions.deepNote(main, BossNightMode.NORMAL, "深度"),
        )
        assertEquals(
            "当前为深夜数值；常规数值：血量 11,328（1 人）、攻击 ×3.36。",
            BossCaptions.deepNote(main, BossNightMode.DEPTH2, "深度"),
        )
        assertEquals(BossRowText.noDepthStatsText, BossCaptions.deepNote(BossesParser.parseFight("""{"npcId":1}"""), BossNightMode.DEPTH2, "深度"))
        val mismatched = BossTestData.allRows.first { it.chaosCorrectId != null && it.chaosCorrectId != it.scalingId }
        assertTrue(BossCaptions.chaosMismatch(mismatched)!!.startsWith("深度档位取 ChaosMatchingCorrectParam #${mismatched.chaosCorrectId}"))
        assertEquals(null, BossCaptions.chaosMismatch(main))
        // 折叠态「头条数值取自哪一行」
        val (marisNote, marisWarn) = BossCaptions.primaryRowNote(BossTestData.lord(13), BossGroup.NIGHTLORD, BossPartySize.SOLO, BossNightMode.NORMAL, 2)!!
        assertTrue(marisWarn)
        assertTrue(marisNote.startsWith("2 条主战行，上方取血量最高的一条："), marisNote)
        val hunterCard = BossTestData.boss("Bell Bearing Hunter@3100")
        val (fieldNote, fieldWarn) = BossCaptions.primaryRowNote(hunterCard, BossGroup.FIELD, BossPartySize.SOLO, BossNightMode.NORMAL, 4)!!
        assertTrue(fieldWarn)
        assertTrue(fieldNote.startsWith("该分组 2 条数值行，上方取血量最高的一条："), fieldNote)
        assertEquals(
            "代表行：格拉狄乌斯 · 远征首领（共 2 组，展开看全部）" to false,
            BossCaptions.primaryRowNote(gladius, BossGroup.NIGHTLORD, BossPartySize.SOLO, BossNightMode.NORMAL, 2),
        )
        assertEquals(null, BossCaptions.primaryRowNote(gladius, BossGroup.NIGHTLORD, BossPartySize.SOLO, BossNightMode.NORMAL, 1))
    }
}
