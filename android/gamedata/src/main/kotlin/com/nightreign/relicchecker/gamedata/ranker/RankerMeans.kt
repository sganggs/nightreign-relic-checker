package com.nightreign.relicchecker.gamedata.ranker

import com.nightreign.relicchecker.gamedata.GameDataJson
import kotlinx.serialization.Serializable
import kotlinx.serialization.SerializationException

// 页面上半部分（输出手段 → 武器 → 持武器的手 → 分段勾选 → 攻击情境）的选择状态与派生量。
//
// 与 Windows 端 ranker.js 的 state.selection / hand / noFp / charged / hitOverrides / contexts 与 applySelection /
// hitEnabled / currentComposition / currentOutput，macOS 端 BuffRankerModel 的 select(output:) / select(weapon:) /
// toggleSegment / setUseNoFp / loadoutOutput 一一对应：
//   · 换输出手段：战技默认选分组后第一组的第一把武器（SkillDataIndex.defaultWeapon，有固定武器时就是固定武器），
//     法术没有武器；分段勾选回到默认，专注值不足版与蓄力两个开关关掉；持武器的手与攻击情境保留；
//   · 换武器：分段勾选回到默认、两个开关关掉（macOS 同法：新武器不一定有专注值不足版的段，
//     保留开关会让默认勾选一段都不剩）；
//   · 分段勾选：用户点过的段写进 hitOverrides，没点过的按默认勾选（SkillDamageMath.defaultSelection：非 noDamage、
//     与专注值不足版开关同侧（fpBoth 段两侧都算）、在蓄力开关这一侧（chargeBranch：开取 charged / both、关取
//     uncharged / both，partial 两侧都不取；专注值分侧后没有蓄力段时开关不适用））；noDamage 段不可勾；
//   · 蓄力开关（skills v4，usage「蓄力段（v4）」）：与专注值不足版一样是同一招的互斥两侧，切换时手动勾选清掉；
//     没有蓄力段的招恒为关（开关禁用），只有蓄力段的招恒为开（[ResolvedMeans.chargedOn]）；
//   · 武器列表（skills schemaVersion 3）：skills[].weaponIds = 固定引用 ∪ 局内战技池，每把武器带来源标记
//     （[ResolvedMeans.weaponSource]）；选段按这一把武器实解（weapons[].skillVariants[战技 ID]）；
//   · 攻击情境：只把当前输出类别下数据里实际要求过的情境交给计算器（切到别的类别时不显示的勾选不影响结果）；
//     其中蓄力强攻击 / 蓄力战技 / 蓄力法术三项不单独勾，由蓄力开关派生（SkillDamageMath.chargedContexts）；
//   · 子类别限定的增益按当前勾选的段逐段判定：交给计算器的输出带上这批段（RankerOutput.segments）。
// 本类是不可变值，修改一律返回新实例；页面用 [encode] / [decode] 存进 rememberSaveable。

/** 输出手段的选择（不可变）。[outputId] 是 SkillOutput.id（`skill-1177`、`sorcery-4021`）。 */
@Serializable
data class MeansSelection(
    val outputId: String? = null,
    val weaponId: Int? = null,
    /** 1 右手 / 2 左手（appliesToDetail.requires.hand 按它判定；法术的施法器同样占左右手之一）。 */
    val hand: Int = 1,
    /** 当前勾的是专注值不足版（正常版与专注值不足版互为替代，整体切换）。 */
    val useNoFp: Boolean = false,
    /**
     * 「蓄力」开关（用户的选择；skills v4）：开只计蓄力段、关只计非蓄力段，同一招的互斥两侧，整体切换。
     * 不适用 / 只有蓄力段时实际生效的一侧见 [ResolvedMeans.chargedOn]。
     */
    val charged: Boolean = false,
    /** 用户手动点过的段：atkId → 勾 / 不勾。 */
    val hitOverrides: Map<Int, Boolean> = emptyMap(),
    /** 勾选的攻击情境（enums.attackContext 的键；不含由蓄力开关派生的三项）。 */
    val attackContexts: Set<String> = emptySet(),
) {
    /** 换输出手段（战技带上默认武器）；持武器的手与攻击情境保留，两个开关关掉。 */
    fun select(skills: SkillDataIndex, output: SkillOutput): MeansSelection {
        val weapon = if (output.isSkill) skills.skillsById[output.entryId]?.let { skills.defaultWeapon(it) } else null
        return copy(outputId = output.id, weaponId = weapon?.id, useNoFp = false, charged = false, hitOverrides = emptyMap())
    }

    /** 换武器（只对战技有意义）：分段勾选回到默认、两个开关关掉。 */
    fun withWeapon(weaponId: Int): MeansSelection =
        if (weaponId == this.weaponId) {
            this
        } else {
            copy(weaponId = weaponId, useNoFp = false, charged = false, hitOverrides = emptyMap())
        }

    fun withHand(hand: Int): MeansSelection = copy(hand = if (hand == 2) 2 else 1)

    /** 正常版 / 专注值不足版整体切换：手动勾选清掉，按新的一侧默认勾选。 */
    fun withNoFp(value: Boolean): MeansSelection =
        if (value == useNoFp) this else copy(useNoFp = value, hitOverrides = emptyMap())

    /**
     * 蓄力 / 不蓄力整体切换（换一侧就是换一批段，与专注值开关同理）：手动勾选清掉，派生的三项攻击情境随之改变。
     * 开关禁用（不适用 / 只有蓄力段）时页面不调用；调用了也只改用户的选择，实际一侧仍按 [ResolvedMeans.chargedOn]。
     */
    fun withCharged(value: Boolean): MeansSelection =
        if (value == charged) this else copy(charged = value, hitOverrides = emptyMap())

    /** 勾 / 不勾某一段（noDamage 段不可勾，原样返回）。 */
    fun withHit(hit: SkillHit, on: Boolean): MeansSelection =
        if (hit.noDamage) this else copy(hitOverrides = hitOverrides + (hit.atkId to on))

    /** 分段列表工具条：全选（两个开关当前这一侧）/ 全不选 / 恢复默认。 */
    fun withHitAction(hits: List<SkillHit>, action: HitAction): MeansSelection =
        copy(hitOverrides = SkillDamageMath.hitOverridesFor(hits, action, useNoFp, charged))

    /** 勾 / 不勾一项攻击情境；蓄力强攻击 / 蓄力战技 / 蓄力法术三项由蓄力开关派生，不接受单独勾选（原样返回）。 */
    fun toggleContext(key: String): MeansSelection {
        if (key in SkillDamageMath.CHARGED_CONTEXTS) return this
        return copy(attackContexts = if (key in attackContexts) attackContexts - key else attackContexts + key)
    }

    /** 按 skills 数据集解析出页面要用的全部派生量。 */
    fun resolve(skills: SkillDataIndex): ResolvedMeans = ResolvedMeans(skills, this)

    /**
     * 读回来的状态对不上当前数据（输出手段不存在、武器不属于这个战技）时改回可用的值：
     * 输出手段退回 [initial]，武器退回这个战技的默认武器。
     */
    fun sanitized(skills: SkillDataIndex): MeansSelection {
        // 旧版本存下的三项蓄力情境（那时可以单独勾）：现在由蓄力开关派生，读回时去掉。
        val base = if (attackContexts.any { it in SkillDamageMath.CHARGED_CONTEXTS }) {
            copy(attackContexts = attackContexts - SkillDamageMath.CHARGED_CONTEXTS.toSet())
        } else {
            this
        }
        return base.sanitizedOutput(skills)
    }

    private fun sanitizedOutput(skills: SkillDataIndex): MeansSelection {
        val output = outputId?.let { skills.output(it) } ?: return initial(skills).copy(hand = hand, attackContexts = attackContexts)
        if (!output.isSkill) return if (weaponId == null) this else copy(weaponId = null)
        val skill = skills.skillsById[output.entryId] ?: return select(skills, output)
        if (weaponId != null && weaponId in skill.weaponIds && skills.weaponsById.containsKey(weaponId)) return this
        return select(skills, output)
    }

    /** 保存用（rememberSaveable 存字符串）。 */
    fun encode(): String = GameDataJson.lenient.encodeToString(serializer(), this)

    companion object {
        /** 页面打开时的默认：第一条输出手段（战技在前；Windows renderData 取 means[0]、macOS 取第一条战技）。 */
        fun initial(skills: SkillDataIndex): MeansSelection {
            val first = skills.outputs.firstOrNull { it.isSkill } ?: skills.outputs.first()
            return MeansSelection().select(skills, first)
        }

        /** [encode] 的逆；读不出时返回 null（页面退回 [initial]）。 */
        fun decode(text: String?): MeansSelection? {
            if (text.isNullOrEmpty()) return null
            return try {
                GameDataJson.lenient.decodeFromString(serializer(), text)
            } catch (_: SerializationException) {
                null
            } catch (_: IllegalArgumentException) {
                null
            }
        }
    }
}

/**
 * [MeansSelection] 解析后的派生量（不可变）：所选输出手段、战技 / 法术、武器与武器分组、实际打出的段、
 * 分段芯片、蓄力开关的可用性、勾中的段、伤害构成，以及交给配置引擎的 [RankerOutput]。
 */
class ResolvedMeans internal constructor(val skills: SkillDataIndex, val selection: MeansSelection) {
    val output: SkillOutput? = selection.outputId?.let { skills.output(it) }
    val skill: SkillEntry? = output?.takeIf { it.isSkill }?.let { skills.skillsById[it.entryId] }
    val spell: SpellEntry? = output?.takeIf { !it.isSkill }?.let { skills.spellsById[it.entryId] }

    /** 当前武器（法术为 null；战技选了不属于它的武器时也按 null 处理）。 */
    val weapon: SkillWeapon? = skill?.let { entry ->
        selection.weaponId?.takeIf { it in entry.weaponIds }?.let { skills.weaponsById[it] }
    }

    /** 这个战技可选的武器（固定 ∪ 局内战技池，按类别分组、固定武器排前）；法术为空。 */
    val weaponGroups: List<SkillWeaponGroup> = skill?.let { skills.weaponGroups(it) }.orEmpty()

    /** 各来源的武器数（武器选择器的小标签）：固定战技 N、局内可抽到 N。 */
    val weaponSourceCounts: Map<WeaponSourceKind, Int> = skill?.let { entry ->
        weaponGroups.flatMap { it.weapons }.mapNotNull { skills.weaponSourceKind(entry, it) }.groupingBy { it }.eachCount()
    }.orEmpty()

    /** 这把武器带当前战技的来源（固定战技 / 局内可抽到，两者都成立只算固定）；法术或判不出时为 null。 */
    fun weaponSource(weapon: SkillWeapon): WeaponSourceKind? = skill?.let { skills.weaponSourceKind(it, weapon) }

    /** 这把武器在战技里用的那一套动作（按 skillVariants[战技 ID] 实解；缺失 / 越界时为 null）。 */
    val variant: SkillVariant? = skill?.let { skills.selectVariant(it, weapon) }

    val outputClass: OutputClass = output?.outputClass ?: OutputClass.SKILL
    val isSpell: Boolean get() = outputClass.isSpell

    /**
     * 实际打出的段（战技按选段规则只从 variants 取；法术直接读 hits[]，剔掉施法动画不会发射的 notInvoked 段）。
     * 专注值两侧、蓄力两侧都在，勾哪些按两个开关（[selectedHits]）。
     */
    val hits: List<SkillHit> = when {
        skill != null -> skills.hits(skill, weapon)
        spell != null -> skills.spellHits(spell)
        else -> emptyList()
    }

    /** 分段芯片（已按所选武器换算）。与 [hits] 一一对应、同序。 */
    val segments: List<SkillSegment> = hits.map { SkillDamageMath.segment(it, weapon, isSpell = isSpell) }

    /**
     * 「蓄力」开关对这一招（当前专注值一侧）的可用性：[ChargeInfo.applicable]＝有蓄力段（否则开关禁用、显示
     * chargedToggle.unavailable），[ChargeInfo.onlyCharged]＝只有蓄力段（开关强制打开、显示 chargedToggle.onlyCharged）。
     */
    val chargeInfo: ChargeInfo = SkillDamageMath.chargeInfo(hits, selection.useNoFp)

    /** 蓄力开关实际生效的一侧（派生三项蓄力攻击情境、默认勾选都看它）：不适用 → 关；只有蓄力段 → 开。 */
    val chargedOn: Boolean = chargeInfo.effective(selection.charged)

    /** 默认勾选的段（两个开关同侧，[SkillDamageMath.defaultSelection]）；用户点过的段按 hitOverrides。 */
    val defaultIds: Set<Int> = SkillDamageMath.defaultSelection(hits, selection.useNoFp, selection.charged)

    /** 当前勾中的段（数据顺序）。 */
    val selectedHits: List<SkillHit> = hits.filter { SkillDamageMath.isHitEnabled(it, selection.hitOverrides, defaultIds) }
    val selectedIds: Set<Int> = selectedHits.mapTo(LinkedHashSet()) { it.atkId }

    val composition: DamageComposition = SkillDamageMath.composition(selectedHits, weapon, isSpell)

    /** 这套动作里有专注值不足版的段（才显示「使用专注值不足版本」开关）。 */
    val hasNoFpVariant: Boolean = hits.any { it.noFp }

    /** 施法动画不会发射、没列出的段数（法术 hits[] 里的 notInvoked，v4；战技为 0）。 */
    val spellNotInvokedCount: Int = spell?.hits?.count { it.notInvoked } ?: 0

    fun isEnabled(hit: SkillHit): Boolean = SkillDamageMath.isHitEnabled(hit, selection.hitOverrides, defaultIds)

    /**
     * 交给配置引擎的输出手段：战技带武器与武器类别，法术按施法器；构成与逐段判定用同一批勾选的段
     * （[RankerOutput.segments]）。攻击情境＝用户勾的（[validContexts] 非空时只保留当前输出类别下数据里实际要求过的，
     * null＝不过滤）＋ 蓄力开关派生的三项（[chargedOn] 时同时成立）。
     */
    fun rankerOutput(validContexts: Set<String>? = null): RankerOutput {
        val picked = if (validContexts == null) selection.attackContexts else selection.attackContexts.intersect(validContexts)
        return RankerOutput(
            outputClass = outputClass,
            meansId = output?.entryId,
            weaponId = weapon?.id,
            weaponWepType = weapon?.wepType,
            hand = selection.hand,
            shares = composition.shares,
            attackContexts = SkillDamageMath.chargedContexts(picked, chargedOn),
            segments = SkillDamageMath.outputSegments(selectedHits, weapon, isSpell),
        )
    }
}
