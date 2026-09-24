package com.nightreign.relicchecker.gamedata.ranker

// 配置页文案的常用组合（macOS 端 LoadoutText 的 columnTitle / relicCardTitle / fixedRelicSubtitle / familyName /
// stripTierSuffix / entryBadges / heroGroup / stackHints / isGraceStack / skillOnlySubCategories / briefNotes，
// 道具等级标记 goodsLevelTag，
// Windows 端 ranker.js 的同名函数）。文案本身一律取自 RankerText（RANKER_TEXT_TABLE，三端同一张表）。

object LoadoutText {
    /** 「普通遗物 N」「深夜遗物 N」（深夜格从 1 数起，Windows relicCardLabel）。 */
    fun relicCardLabel(cardIndex: Int, normalCount: Int): String =
        if (cardIndex >= normalCount) {
            RankerText.f("relicCardDeep", cardIndex - normalCount + 1)
        } else {
            RankerText.f("relicCardNormal", cardIndex + 1)
        }

    /** 「红色 · 遗物 #2070」；颜色缺失时「#2070」。 */
    fun fixedRelicSubtitle(relicId: Int, color: Int): String {
        val colorName = RankerText.table["relicColors.$color"] ?: return "#$relicId"
        return RankerText.f("relicFixedSubtitle", colorName, relicId)
    }

    /** 其它增益分栏的中文名（otherGroups.<slot>；占槽位的栏取 columns.*）。 */
    fun slotTitle(slot: String): String =
        RankerText.table["otherGroups.$slot"] ?: RankerText.table["columns.$slot"] ?: slot

    private val FAMILY_PAREN = Regex("（[^（）]*）$")
    private val FAMILY_PLUS = Regex("${RankerRegex.WS}*[＋+]${RankerRegex.WS}*[0-9０-９]+$")
    private val TIER_SUFFIX = Regex("（第${RankerRegex.DIGIT}+[层档]）$")

    /** 同族提示里的名字：显示名去掉末尾的全角括注与「＋N」。 */
    fun familyName(name: String): String = FAMILY_PLUS.replace(FAMILY_PAREN.replace(name, ""), "")

    /** 「连刺破露滴（第1层）」→「连刺破露滴」（累积阶梯合成一行时的名字）。 */
    fun stripTierSuffix(name: String): String = TIER_SUFFIX.replace(name, "")

    /** 一条增益的徽标：条件型 / 发动型 / 叠层或按份数叠加 / 累积阶梯 / 按武器类别取一档 / 来源为推断 / 队友。 */
    fun entryBadges(entry: BuffRankerEntry): List<String> = buildList {
        if (entry.activation == "conditional") add(RankerText.t("badges.conditional"))
        if (entry.activation == "activated") add(RankerText.t("badges.activated"))
        entry.stackInput?.let { add(RankerText.t(if (it.isLadder) "badges.ladder" else "badges.copies")) }
        if (entry.accLadder != null) add(RankerText.t("badges.accLadder"))
        if (entry.variantGroup != null) add(RankerText.t("badges.variant"))
        if (entry.hasInferredSource) add(RankerText.t("badges.inferredSource"))
        if (entry.pairRole == "ally") {
            add(RankerText.t("badges.allyPair"))
        } else if (entry.target == "ally") {
            add(RankerText.t("badges.ally"))
        }
    }

    /**
     * 道具等级标记（Windows goodsLevelTag）：buffs v6 的 goodsLevel ≥ 2 标「携物知识 N 级」（goodsLevel.tag），
     * 1 级（含缺省与各级共用的 1 级行）为空串。2／3 级只来自学者的能力「携物知识」（notes.goodsLevel）。
     */
    fun goodsLevelTag(level: Int): String = if (level >= 2) RankerText.f("goodsLevel.tag", level) else ""

    fun goodsLevelTag(entry: BuffRankerEntry?): String = goodsLevelTag(entry?.goodsLevel ?: 0)

    /** 角色栏分组：Paramdex 行名 `[Skill - Revenant] …` →（复仇者, 技艺）；拿不到角色归「其他角色」。 */
    fun heroGroup(paramName: String?): Pair<String, String> {
        val name = paramName.orEmpty()
        val close = name.indexOf(']')
        if (!name.startsWith("[") || close < 0) return RankerText.t("characterOther") to ""
        val parts = name.substring(1, close).split(" - ")
        val rawKind = parts.first().trim()
        val kind = RankerText.table["characterKinds.$rawKind"] ?: rawKind
        if (parts.size < 2) return RankerText.t("characterOther") to kind
        val english = parts[1].trim()
        return (RankerText.table["characterNames.$english"] ?: english) to kind
    }

    /** 层数的计数单位以游戏文本为准：descZh 写着「赐福」的按本局新发现的赐福数提示。 */
    fun isGraceStack(entry: BuffRankerEntry): Boolean = entry.stackInput != null && entry.buff.descZh.orEmpty().contains("赐福")

    /** 叠层输入框的提示（阶梯 / 份数 + 一局实际上限或『＋N』标签 + 赐福数）。 */
    fun stackHints(entry: BuffRankerEntry): List<String> {
        val input = entry.stackInput ?: return emptyList()
        val hints = ArrayList<String>()
        if (input.isLadder) {
            hints += RankerText.f("stackHintLadder", input.paramMax)
        } else {
            hints += RankerText.f("stackHintCopies", BuffFormat.trim(input.perStackMultiplier ?: 0.0, 4))
        }
        val practical = input.practicalMaxStacks
        val label = input.uiLabelMax
        if (practical != null) {
            hints += RankerText.f("stackHintPractical", practical)
        } else if (label != null) {
            hints += RankerText.f("stackHintLabel", label)
        }
        if (isGraceStack(entry)) hints += RankerText.t("stackHintGrace")
        return hints
    }

    /** 叠层输入框的标签：份数型「份数」，阶梯「层数」。 */
    fun stackLabel(entry: BuffRankerEntry): String =
        RankerText.t(if (entry.stackInput?.isLadder == false) "stackLabelCopies" else "stackLabel")

    /** 累积阶梯某一层的选项文字：「第 N 层」或带累积阈值的「第 N 层（累积 X）」（两端同一写法）。 */
    fun tierLabel(entry: BuffRankerEntry): String {
        val ladder = entry.accLadder ?: return RankerText.f("tierLabel", entry.ladderTier)
        val threshold = ladder.thresholds.getOrNull(ladder.tier - 1)
        return if (threshold != null) {
            RankerText.f("tierLabelThreshold", ladder.tier, BuffFormat.trim(threshold, 0))
        } else {
            RankerText.f("tierLabel", ladder.tier)
        }
    }

    /** 多档词条某一档的选项文字：「第 N 档（物理攻击力 ×1.1、火属性攻击力 +30）」。 */
    fun variantOption(entry: BuffRankerEntry, position: Int): String {
        val parts = entry.usedMultiplier.map { it.zh + " ×" + BuffFormat.trim(it.value, 3) } +
            entry.usedFlat.map { it.zh + " " + BuffFormat.flat(it.value, 0) }
        val tier = entry.variantTier.takeIf { it > 0 } ?: (position + 1)
        return RankerText.f("variantOption", tier, if (parts.isEmpty()) "" else RankerText.f("variantRates", parts.joinToString("、")))
    }

    /**
     * 「提升战技攻击力」类的子类别：appliesTo 为 skill=conditional、sorcery=no、incantation=no 的
     * requires.subCategoriesAny 里，没有在任何法术、近战普通攻击、弓弩射击命中段出现过的那些（attackIndex 人口统计），
     * 按编号降序，写成「112 战技攻击」。
     */
    fun skillOnlySubCategories(dataset: BuffDataset): List<String> {
        val seen = HashSet<Int>()
        dataset.attackIndex.spells.values.forEach { sets -> sets.forEach { seen += it.subs } }
        (dataset.attackIndex.melee + dataset.attackIndex.ranged).forEach { seen += it.subs }
        val found = HashSet<Int>()
        for (buff in dataset.buffs) {
            val applies = buff.appliesTo ?: continue
            if (applies.skill != "conditional" || applies.sorcery != "no" || applies.incantation != "no") continue
            val subs = buff.appliesToDetail.skill?.requires?.subCategoriesAny.orEmpty()
            if (subs.isEmpty() || subs.any { it in seen }) continue
            found += subs
        }
        return found.sortedDescending().map { sub ->
            val label = dataset.enums.atkSubCategory[sub]
            if (label.isNullOrEmpty()) sub.toString() else "$sub $label"
        }
    }

    /**
     * 说明区「口径说明」（三端同一顺序、同一文案，数字照数据现算；Windows briefNotes、macOS LoadoutText.briefNotes）。
     * 数字归一成「#」后的摘要＝ad04314d（RankerCrossCheck.briefDigest）。
     */
    fun briefNotes(index: LoadoutIndex): List<String> {
        val dataset = index.dataset
        val entries = index.ranker.entries
        val deepCaps = index.caps(RunMode.DEEP)
        val dupStatus = index.slotRules.weaponAffix.duplicateWithinWeapon.status.ifEmpty { "unknown" }
        val stackTexts = ArrayList<String>()
        for (entry in entries) {
            val input = entry.stackInput ?: continue
            var text: String
            if (input.isLadder) {
                text = RankerText.f("briefStack.ladder", BuffFormat.trim(input.perStackRatio ?: 0.0, 4), input.paramMax)
                val practical = input.practicalMaxStacks
                if (practical != null && practical > 0 && input.tierMultipliers.isNotEmpty()) {
                    val tier = input.tierMultipliers[minOf(practical, input.tierMultipliers.size) - 1]
                    text += RankerText.f("briefStack.practical", practical, BuffFormat.trim(tier, 4))
                }
            } else {
                text = RankerText.f("briefStack.copies", BuffFormat.trim(input.perStackMultiplier ?: 0.0, 4))
                if (isGraceStack(entry)) text += RankerText.f("briefStack.unit", RankerText.t("stackHintGrace"))
            }
            stackTexts += RankerText.f("briefStack.item", entry.name, text)
        }
        val decreaseCount = entries.count { it.countsAsDamage && it.direction == "decrease" }
        val variantGroups = index.ranker.variants
        val variantMembers = variantGroups.values.sumOf { it.size }
        val skillSubs = skillOnlySubCategories(dataset)
        val notes = arrayListOf(
            RankerText.t("brief.appliesTo"),
            RankerText.t("brief.formula"),
            RankerText.t("brief.partial"),
            RankerText.f("brief.direction", decreaseCount),
            RankerText.t("brief.target"),
            RankerText.t("brief.activation"),
            RankerText.t("brief.stacking"),
        )
        if (variantGroups.isNotEmpty()) notes += RankerText.f("brief.affixVariant", variantGroups.size, variantMembers)
        notes += listOf(
            RankerText.t("brief.tiers"),
            RankerText.f("brief.deepWeapon", deepCaps.deepOnly, dupStatus),
            RankerText.f("brief.relic", if (index.catalog.available) index.catalog.cursePoolId.toString() else RankerText.t("noData")),
            RankerText.f("brief.skillAttack", if (skillSubs.isEmpty()) RankerText.t("noData") else skillSubs.joinToString("／")),
            RankerText.t("brief.equipped"),
            RankerText.t("brief.innate"),
            RankerText.f(
                "brief.runStack",
                if (stackTexts.isEmpty()) RankerText.t("noData") else stackTexts.joinToString(RankerText.t("briefStack.separator")),
            ),
            RankerText.t("brief.fill"),
            RankerText.t("brief.throwInferred"),
        )
        return notes
    }
}
