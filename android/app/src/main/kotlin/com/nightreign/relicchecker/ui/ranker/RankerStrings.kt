package com.nightreign.relicchecker.ui.ranker

// 页面上不在配置文案常量表（RankerText / RANKER_TEXT_TABLE）里的文字：输出手段、分段命中、伤害构成与底部说明。
// 逐字取自桌面端的写死文案（Windows renderer/pages/ranker.js 的 pickerHtml / weaponPickerHtml / hitsHtml /
// compositionHtml / footerHtml，macOS BuffRankerView.swift / BuffRankerComponents.swift / BuffRankerRankingSection.swift），
// 不另起说法。配置部分（武器词条、遗物、护符、其它增益、汇总、口径说明）一律走 RankerText.t / f 与 LoadoutText。
// 例外：输出手段的类型开关三档（战技 / 魔法 / 祷告，MeansKind.titleZh ← meansKind.*）、卡片与抽屉的副标题
// （meansCard.subtitle）、检索框与空列表（meansSearch.placeholder / empty）、选中魔法／祷告时的标记（meansSpellFlatNote）
// 三端同名同值，放在文案常量表里，这里不再写死。
internal object RankerStrings {
    const val LOADING = "正在载入战技与增益数据…"

    // ---- 输出手段（Windows pickerHtml / weaponPickerHtml）
    const val OUTPUT_TITLE = "输出手段"
    const val NO_SELECTION = "尚未选择输出手段。"
    const val WEAPON_LABEL = "武器"
    const val NO_WEAPON = "这个战技没有可用武器"
    const val SPARRING = "训练场可用"
    const val PHYS_ATTACK_TYPE = "物理攻击类型"
    const val POISE_BASE = "削韧基础"
    const val NO_BASE_ATTACK = "无基础攻击力"

    fun weaponsAvailable(count: Int) = "$count 把武器可用"

    /** 武器词条行的份数（任务清单写明的行内格式「名字 · 倍率 · 已用 n」）。 */
    fun usedCount(count: Int) = "已用 $count"
    fun weaponCount(count: Int) = "$count 把武器"
    fun mpCost(mp: Int) = "专注值 $mp"

    /** 武器抽屉的来源小计：「固定战技 8」「局内可抽到 68」（Windows weaponPickerHtml 的 pill 同一写法）。 */
    fun sourceCount(title: String, count: Int) = "$title $count"

    /** macOS BuffRankerOutputSection.weaponPicker 的说明。 */
    const val WEAPON_NOTE = "基础攻击力取自 EquipParamWeapon，不含强化等级、亲和与词条加成；本页只做相对构成，绝对伤害不在范围内。"

    /** Windows weaponPickerHtml 的法术说明（施法器按魔法＝手杖、祷告＝圣印记）。 */
    fun spellNote(incantation: Boolean) =
        "法术没有武器动作套：按 usage「法术 / 子弹段」只取每段的固定伤害值（flat），不把 motion 乘到施法器攻击力上。" +
            "武器槽用于匹配 appliesTo 的 requires.hand——施法器同样占左右手之一；武器词条栏按" +
            (if (incantation) "圣印记" else "手杖") + "的类别过滤。"

    // ---- 分段命中（Windows hitsHtml、macOS RankerSegmentRow）
    const val HITS_TITLE = "分段命中"
    const val HITS_SUBTITLE = "勾掉不打的段即可（例如只算刀气那一段）"
    const val HITS_EMPTY_SKILL = "按 usage 的选段规则，这把武器在这个战技上没有任何命中段（weapons[].skillVariants 里没有这个战技）。"
    const val HITS_EMPTY_SPELL = "这条魔法／祷告没有带数值的命中段。"
    const val HITS_ALL = "全选（当前版本）"
    const val HITS_ALL_HELP = "只勾当前这一侧的段：正常版与专注值不足版互为替代，两边一起勾会把同一击算两遍"
    const val HITS_NONE = "全不选"
    const val HITS_RESET = "恢复默认"
    const val NO_FP_SWITCH = "使用专注值不足版本"
    const val NO_FP_HELP = "没蓝时打出的弱化版战技：正常版与专注值不足版互斥，这里整体切换"
    const val MARK_NO_FP = "专注值不足版"
    /** fpBoth 段：正常版与专注值不足版两侧都计（与 Windows 的行内标记同文）。 */
    const val MARK_FP_BOTH = "两版共用"
    const val MARK_BULLET = "子弹"
    const val MARK_NO_DAMAGE = "只挂状态"
    const val MARK_ADD_BASE = "额外加一份攻击力"
    const val NO_DAMAGE_HELP = "这一段只挂状态、不产生伤害，不能计入构成"
    const val CHIP_FLAT = "固定 "
    const val CHIP_BASE_ATTACK = "+基础攻击力"
    const val NO_DAMAGE_VALUE = "无伤害数值"
    const val OTHER_ZERO = "其余属性该武器为 0"
    const val POISE = "削韧"
    const val STAMINA = "削精力"
    const val PHYS_TYPE = "物理类型"
    const val POISE_HELP = "削韧：对敌人韧性（削韧槽）的削减量；削精力：对格挡中敌人精力条的削减量（武器基础精力伤害 × 动作值），与角色自己的精力无关"
    const val SEGMENT_DETAIL = "分段明细（伤害数值、削韧、削精力）"

    fun hitsCount(on: Int, total: Int) = "已勾选 $on / $total 段"

    fun variantNote(context: String, via: String, count: Int) =
        "动作套：$context（来源 ${if (via == "behavior") "BehaviorParam_PC 实解" else "按 ctx 单选"}，共 $count 段）。"

    // ---- 伤害构成（Windows compositionHtml）
    const val COMP_TITLE = "伤害构成"
    const val COMP_SUBTITLE = "勾选段的相对占比，用来给每条增益加权"
    const val COMP_EMPTY = "当前没有勾选任何带伤害的段，无法计算构成。"
    const val COMP_NOTE_PREFIX = "这里只是"
    const val COMP_NOTE_STRONG = "相对构成"
    const val COMP_NOTE_SUFFIX = "：不含强化等级、亲和、能力值补正与 AttackElementCorrectParam，绝对伤害不在本页范围。"
    const val BOUNDARY_LABEL = "数据集说明 · 本数据集的边界"

    fun physicalTotal(text: String) = "物理合计 $text"
    fun elementTotal(text: String) = "属性合计 $text"
    fun relativeTotal(text: String) = "相对值合计 $text"

    // ---- 底部说明（Windows footerHtml / NOTE_ORDER，macOS BuffRankerNotesSection）
    const val CAVEATS_TITLE = "战技数据的已知取舍"
    const val STACKING_TITLE = "叠加规则（buffs stackingRules）"
    const val VERSION_TITLE = "数据版本与来源"
    const val RAW = "原文"

    /** 战技数据集 usage「战技来源（v3）」一节：武器抽屉的固定战技 / 局内可抽到标记的依据。 */
    const val SOURCES_TITLE = "战技来源：固定战技与局内战技池"
    const val SOURCES_NOTE = "武器抽屉列出能带这个战技的全部武器：固定带它的武器（EquipParamWeapon.swordArtsParamId）" +
        "标「固定战技」，局内掉落时战技池能抽到它的武器标「局内可抽到」，两者都成立只标固定；动作套按所选那一把武器实解" +
        "（weapons[].skillVariants）。来源：战技数据集 usage「战技来源（v3）」。"

    /** 战技数据集 usage「命中段已按 TAE 核实（v3）」一节（Windows taeUsageHtml）。 */
    const val TAE_TITLE = "命中段已按 TAE 核实"
    const val TAE_VERIFIED = "已核实"
    const val TAE_UNVERIFIED = "未核实"
    const val TAE_NOTE = "分段命中只从 variants[].atkIds 取段：那里已按动画事件（TAE）剔掉本作打不出的段；" +
        "hits[] 里保留的这类段标了 notInvoked，本页不列出。来源：战技数据集 usage「命中段已按 TAE 核实（v3）」。"

    /** 「数据版本与来源」skills 一行的 TAE 注记（Windows versionHtml）。 */
    fun taeVersion(notInvoked: Int) = " · 命中段已按 TAE 核实（打不出的 $notInvoked 段不列出）"

    fun countPill(count: Int) = "$count 条"

    /** macOS BuffRankerNotesSection 的折叠标题。 */
    fun notesTitle(count: Int) = "排名算法与数据取舍（增益数据集 notes 原文，$count 段）"

    val NOTE_ORDER: List<Pair<String, String>> = listOf(
        "ranking" to "排名步骤",
        "appliesTo" to "生效范围 appliesTo",
        "sourceSlot" to "来源槽位 sourceSlot",
        "weaponAffix" to "局内武器词条",
        "relicAffix" to "遗物词条",
        "stackInput" to "叠层输入",
        "activation" to "发动条件",
        "attackContext" to "攻击情境",
        "howToUseRates" to "倍率怎么用",
        "target" to "作用目标",
        "displayName" to "显示名",
        "zh" to "数据集总说明",
    )

    fun noteTitle(key: String): String {
        val zh = NOTE_ORDER.firstOrNull { it.first == key }?.second
        return if (zh != null) "$zh（buffs notes.$key）" else "buffs notes.$key"
    }
}
