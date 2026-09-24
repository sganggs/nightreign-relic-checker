package com.nightreign.relicchecker.gamedata.ranker

/**
 * 三端对拍钩子：与 Windows 端 ranker.js 的 caseDumpLine、macOS 端 BuffRankerChecks.swift 的 loadoutCaseDump
 * 同一格式的 CASE 行。固定输入 [CASES] 与 windows/tests/ranker_crosscheck.test.mjs 的 CASES 逐项相同。
 *
 * 行格式：`CASE <key> selected=<atkId,…> shares=<九类占比 %.9f，按 DamageType 顺序> applicable=<一览生效条数>
 * useful=<生效且有效倍率 > 1.0000001 的条数> top10=<id:有效倍率 %.9f，…>`。
 */
object RankerCrossCheck {
    /** 一组构成用例：战技（+ 武器）或法术；[only] 非空时只勾这些段，否则按默认勾选（正常版这一侧）。 */
    data class CompositionCase(
        val key: String,
        val outputClass: OutputClass,
        val id: Int,
        val weaponId: Int? = null,
        val only: List<Int>? = null,
    )

    /** 一个用例跑出来的中间量。 */
    data class CaseRun(
        val case: CompositionCase,
        val weapon: SkillWeapon?,
        /** 选出的段（数据顺序）。 */
        val hits: List<SkillHit>,
        /** 勾上的段（数据顺序）。 */
        val selected: List<SkillHit>,
        val composition: DamageComposition,
        val output: RankerOutput,
        val rows: List<OverviewRow>,
    ) {
        val useful: List<OverviewRow> get() = rows.filter { it.isUseful }
        val dumpLine: String get() = caseDumpLine(case.key, selected.map { it.atkId }, composition.shares, rows)
    }

    /** 两端同一组输入（任务清单里的七组构成用例）。 */
    val CASES: List<CompositionCase> = listOf(
        // 尸横遍野（尸山血海）：全段 —— 物理 + 火两条通道，12 段里 6 段是专注值不足版。
        CompositionCase("corpse-piler-full", OutputClass.SKILL, 1177, 9040000),
        // 同一把武器只勾最后一段：每段五属性 motion 同值，构成比例必须与全段完全一致。
        CompositionCase("corpse-piler-last", OutputClass.SKILL, 1177, 9040000, only = listOf(303400305)),
        // 狮子斩 + 大剑：纯物理。
        CompositionCase("lions-claw-greatsword", OutputClass.SKILL, 100, 3180000),
        // 狮子斩 + 火焰大剑：同一战技、同一套段，换一把带火属性的武器。
        CompositionCase("lions-claw-flame-greatsword", OutputClass.SKILL, 100, 3180500),
        // 喷火 + 钢丝火把：带子弹段的战技（子弹段照常乘武器攻击力，不得整段归零）。
        CompositionCase("firebreather", OutputClass.SKILL, 223, 24020000),
        // 死亡雷击：祷告，只用 flat。
        CompositionCase("death-lightning", OutputClass.INCANTATION, 5040),
        // 帚星：魔法，只用 flat。
        CompositionCase("comet", OutputClass.SORCERY, 4021),
    )

    /** 一个用例的输出手段（不算一览）：选段 → 默认勾选 → 构成 → 输出手段（右手、不勾攻击情境）。 */
    data class Composed(
        val weapon: SkillWeapon?,
        val hits: List<SkillHit>,
        val selected: List<SkillHit>,
        val composition: DamageComposition,
        val output: RankerOutput,
    )

    /**
     * 选段 → 默认勾选（正常版这一侧，两侧共用的 fpBoth 段也算；[CompositionCase.only] 非空时只勾这些段）→ 构成 →
     * 输出手段。找不到时抛 IllegalArgumentException。
     */
    fun compose(skills: SkillDataIndex, case: CompositionCase): Composed {
        val isSpell = case.outputClass != OutputClass.SKILL
        val weapon = case.weaponId?.let { requireNotNull(skills.weaponsById[it]) { "${case.key}：找不到武器 $it" } }
        val hits: List<SkillHit>
        if (isSpell) {
            val spell = requireNotNull(skills.spellsById[case.id]) { "${case.key}：找不到法术 ${case.id}" }
            hits = skills.spellHits(spell)
        } else {
            val skill = requireNotNull(skills.skillsById[case.id]) { "${case.key}：找不到战技 ${case.id}" }
            hits = skills.hits(skill, weapon)
        }
        val selected = hits.filter { hit ->
            when {
                hit.noDamage -> false
                case.only != null -> hit.atkId in case.only
                else -> hit.isOnSide(useNoFp = false)
            }
        }
        val composition = SkillDamageMath.composition(selected, weapon, isSpell)
        val output = RankerOutput(
            outputClass = case.outputClass,
            meansId = case.id,
            weaponId = weapon?.id,
            weaponWepType = weapon?.wepType,
            hand = 1,
            shares = composition.shares,
        )
        return Composed(weapon, hits, selected, composition, output)
    }

    /** 跑一个构成用例：[compose] → 一览。找不到输出手段时抛 IllegalArgumentException。 */
    fun run(skills: SkillDataIndex, buffs: BuffRankerIndex, case: CompositionCase): CaseRun {
        val composed = compose(skills, case)
        return CaseRun(
            case, composed.weapon, composed.hits, composed.selected, composed.composition, composed.output,
            buffs.overview(composed.output),
        )
    }

    /** 对拍行（格式见类注释）。 */
    fun caseDumpLine(key: String, selectedIds: List<Int>, shares: List<Double>, rows: List<OverviewRow>): String {
        val useful = rows.filter { it.isUseful }
        return "CASE " + key +
            " selected=" + selectedIds.joinToString(",") +
            " shares=" + DamageType.entries.joinToString(",") { BuffFormat.fixed(shares.getOrElse(it.ordinal) { 0.0 }, 9) } +
            " applicable=" + rows.count { it.applicable } +
            " useful=" + useful.size +
            " top10=" + useful.take(10).joinToString(",") { it.id.toString() + ":" + BuffFormat.fixed(it.multiplier ?: 1.0, 9) }
    }

    // ============================================================ 配置对照（CONFIG 行）

    /**
     * 一组整套配置的对照用例（三端同一组输入，windows/tests/ranker_crosscheck.test.mjs 的 CONFIG_CASES）。
     * [build] 拿到索引与绑定了输出手段的计算器，返回要评估的配置；[filled]＝按推荐填满得到的配置。
     */
    class ConfigCase(
        val key: String,
        val output: CompositionCase,
        val filled: Boolean,
        val build: (LoadoutIndex, LoadoutEvaluator) -> LoadoutConfig,
    )

    /** 一组配置用例跑出来的结果。 */
    data class ConfigRun(
        val case: ConfigCase,
        val output: RankerOutput,
        val evaluator: LoadoutEvaluator,
        val config: LoadoutConfig,
        val result: LoadoutEvaluation,
    ) {
        val dumpLine: String get() = configDumpLine(case.key, config, result)
    }

    /**
     * 三组配置：
     *   A 尸横遍野 + 尸山血海，常规模式：按推荐填满（武器词条按出手武器类别过滤）；
     *   B 死亡雷击，深夜模式：按推荐填满（武器词条按施法器圣印记的类别过滤）；
     *   C 狮子斩 + 大剑：固定遗物 2070（安定者的遗志）、2100（王的黑夜，勾「切换武器时，能提升物理攻击力」7035902）
     *     ＋ 自组遗物（封印监牢 7060000 / 出击时附加火 7120100 / 对陷入冻伤的敌人 7260400）
     *     ＋ 护符 1230（战士壶碎片）、2040（红羽七刃剑，条件型未勾）＋ 封印监牢 7 层。
     */
    val CONFIG_CASES: List<ConfigCase> = listOf(
        ConfigCase("corpse-piler-normal-fill", CASES[0], filled = true) { _, evaluator ->
            evaluator.recommendFill(LoadoutConfig(), evaluator.output.attackWepType).config
        },
        ConfigCase("death-lightning-deep-fill", CASES[5], filled = true) { _, evaluator ->
            evaluator.recommendFill(LoadoutConfig(runMode = RunMode.DEEP), evaluator.output.attackWepType).config
        },
        ConfigCase(
            "lions-claw-2fixed-1custom-2talismans-evergaol7",
            CompositionCase("lions-claw-greatsword", OutputClass.SKILL, 100, 3180000),
            filled = false,
        ) { _, _ ->
            LoadoutConfig()
                .withRelic(0, RelicCard.fixed("2070"))
                .withRelic(1, RelicCard.fixed("2100"))
                .withRelic(2, RelicCard.custom(listOf(7060000, 7120100, 7260400)))
                .copy(accessories = listOf(1230, 2040), stackCounts = mapOf(7069001 to 7), ticks = setOf(7035902))
        },
    )

    /** 跑一组配置用例：输出手段（默认勾选）→ 计算器 → 配置 → 评估。 */
    fun runConfig(skills: SkillDataIndex, index: LoadoutIndex, case: ConfigCase): ConfigRun {
        val output = compose(skills, case.output).output
        val evaluator = index.evaluator(output)
        val config = case.build(index, evaluator)
        return ConfigRun(case, output, evaluator, config, evaluator.evaluate(config))
    }

    /**
     * 一整套配置的对拍行（Windows configDumpLine、macOS loadoutConfigDump 同一格式）：
     * `CONFIG <key> mode=<normal|deep> total=<%.9f> sub=<四栏:%.9f> weaponAffixes=<id x 份数，id 升序>
     * relics=<每格：- 空 / F<relicId> 固定 / C<词条[/诅咒]>+… 自组，用 | 分隔> accessories=<id,…> counted=<计入的 id[x 份数]，id 升序>`。
     * 没有构成时倍率按 1 打印。
     */
    fun configDumpLine(key: String, config: LoadoutConfig, result: LoadoutEvaluation): String {
        val caps = result.caps
        fun fixed9(value: Double?): String = BuffFormat.fixed(value ?: 1.0, 9)
        val relics = config.relics.take(caps.relics).joinToString("|") { card ->
            when (card.type) {
                RelicCardType.EMPTY -> "-"
                RelicCardType.FIXED -> card.fixedKey?.let { "F" + it.split("-")[0] } ?: "-"
                RelicCardType.CUSTOM -> "C" + (0 until RelicCard.ROWS).joinToString("+") { row ->
                    (card.affixAt(row)?.toString() ?: "-") + (card.curseAt(row)?.let { "/$it" } ?: "")
                }
            }
        }
        val weaponAffixes = config.weaponAffixes.entries.sortedBy { it.key }.joinToString(",") { "${it.key}x${it.value}" }
        val accessories = config.accessories.take(caps.accessory).filterNotNull().joinToString(",")
        val counted = result.counted.sortedBy { it.id }.joinToString(",") { item ->
            item.id.toString() + if (item.countedCopies > 1) "x${item.countedCopies}" else ""
        }
        val subtotals = SummaryColumn.entries.joinToString(",") { it.key + ":" + fixed9(result.column(it).multiplier) }
        return "CONFIG " + key + " mode=" + config.runMode.key + " total=" + fixed9(result.totalMultiplier) +
            " sub=" + subtotals + " weaponAffixes=" + weaponAffixes + " relics=" + relics +
            " accessories=" + accessories + " counted=" + counted
    }

    /** 说明区的摘要：正文逐行拼接、ASCII 数字串归一成「#」后按 UTF-8 做 FNV-1a（两端 briefDigest / loadoutBriefDigest）。 */
    fun briefDigest(notes: List<String>): String = fnv1a(notes.joinToString("\n").replace(DIGITS, "#"))

    private val DIGITS = Regex("[0-9]+")

    /** 「OUTPUTS skills=155 spells=121」：输出手段列表的条数（Windows 端 buildMeansItems；skills v3 含局内战技池）。 */
    fun outputsDumpLine(skills: SkillDataIndex): String =
        "OUTPUTS skills=${skills.skillOutputCount} spells=${skills.spellOutputCount}"

    /** FNV-1a 32 位（按 UTF-8 字节），与两端 fnv1a / loadoutFNV1a 逐位相同。 */
    fun fnv1a(text: String): String {
        var hash = 0x811c9dc5L
        for (byte in text.toByteArray(Charsets.UTF_8)) {
            hash = hash xor (byte.toLong() and 0xff)
            hash = (hash * 0x01000193L) and 0xffffffffL
        }
        return hash.toString(16).padStart(8, '0')
    }

    /** 文案常量表的摘要：点号路径排序后逐行「路径=文案」（两端 textTableDigest / loadoutTextDigest）。 */
    fun textTableDigest(table: Map<String, String> = RankerText.table): String =
        fnv1a(table.keys.sorted().joinToString("\n") { it + "=" + table.getValue(it) })
}
