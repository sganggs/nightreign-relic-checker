package com.nightreign.relicchecker.gamedata.ranker

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

/**
 * 对拍测试共用的**独立参考实现**（故意不复用被测代码的分支；Windows ranker_crosscheck.test.mjs 的 referenceShares /
 * referenceHitAmounts / referenceSelection / referenceSegments）：取段（usage「蓄力段（v4）」）、单段相对值、
 * 逐段判定用的段与参考输出。RankerCrossCheckTest（一览）与 LoadoutCrossCheckTest（整套配置）都用它。
 */
internal object RankerReference {
    /** 三项由蓄力开关派生的攻击情境（参考实现自己写一遍，不读被测代码的常量）。 */
    val CHARGED_CONTEXTS: Set<String> = setOf("chargedHeavyAttack", "chargedSkill", "chargedSpell")

    /** 逐段判定用的一段：子类别 = hits[].subCategories ∪ 法术流派，[amounts] 是九类相对值。 */
    class Segment(val subs: List<Int>, val amounts: DoubleArray, val total: Double)

    /**
     * 参考输出：[segs] 是逐段判定用的段（相对值 > 0 的勾选段），[contexts] 是成立的攻击情境（蓄力开 = 三项蓄力情境）。
     */
    class Output(
        val outputClass: OutputClass,
        val meansId: Int,
        val hand: Int,
        val weaponWepType: Int?,
        val shares: List<Double>,
        val contexts: Set<String>,
        val segs: List<Segment>,
    ) {
        val hasComposition: Boolean get() = shares.any { it > 0.0 }

        fun share(type: DamageType): Double = shares[type.ordinal]
    }

    /** 取段结果：勾上的段与蓄力开关实际生效的一侧。 */
    class Selection(val hits: List<SkillHit>, val chargedOn: Boolean)

    /** 法术流派：直接读 buffs 原文的 attackIndex.spells[id].magicSubCategories（不经被测代码的解码）。 */
    val magicSubs: Map<Int, List<Int>> by lazy {
        val spells = Json.parseToJsonElement(RankerTestData.buffsText).jsonObject.getValue("attackIndex").jsonObject
            .getValue("spells").jsonObject
        spells.mapNotNull { (key, value) ->
            val list = value.jsonObject["magicSubCategories"]?.jsonArray?.map { it.jsonPrimitive.int } ?: return@mapNotNull null
            key.toInt() to list
        }.toMap()
    }

    /** 单段在九类上的相对值（攻击力 × motion/100 + flat，addBaseAtk 再加一份；法术 weapon=null：只剩 flat）。 */
    fun amounts(hit: SkillHit, weapon: SkillWeapon?): DoubleArray {
        val amounts = DoubleArray(DamageType.COUNT)
        if (hit.noDamage) return amounts
        val physType = when (hit.attribute) {
            "Slash" -> DamageType.SLASH
            "Strike" -> DamageType.BLOW
            "Pierce" -> DamageType.THRUST
            "Standard" -> DamageType.NEUTRAL
            "WeaponAtkAttribute" -> DamageType.physical(weapon?.atkAttribute ?: -1)
            "WeaponAtkAttribute2" -> DamageType.physical(weapon?.atkAttribute2 ?: -1)
            else -> DamageType.PHYS_NONE
        }
        for (element in SkillElement.entries) {
            val base = weapon?.attackBase?.get(element.key) ?: 0.0
            val motion = if (weapon != null) hit.motion[element.key] ?: 0.0 else 0.0
            var amount = base * motion / 100 + (hit.flat[element.key] ?: 0.0)
            if (hit.addBaseAtk) amount += base
            if (!(amount > 0)) continue
            val type = if (element == SkillElement.PHYSICAL) physType else DamageType.entries.first { it.element == element }
            amounts[type.ordinal] += amount
        }
        return amounts
    }

    /**
     * 取段（usage「蓄力段（v4）」，独立重写）：[pool] 是这一招会打出的段（战技 = variants 选段；法术 = hits 去掉
     * notInvoked），去掉 noDamage；② 专注值开关关的一侧（fpBoth 或不是 noFp）；③ ② 里有 chargeBranch=charged 才分侧，
     * 开取 charged / both、关取 uncharged / both（partial 两侧都不取），没有就全取。
     */
    fun selection(pool: List<SkillHit>, charged: Boolean): Selection {
        val side = pool.filter { !it.noDamage && (it.fpBoth || !it.noFp) }
        if (side.none { it.chargeBranch == "charged" }) return Selection(side, chargedOn = false)
        val keep = if (charged) listOf("charged", "both") else listOf("uncharged", "both")
        return Selection(side.filter { it.chargeBranch in keep }, chargedOn = charged)
    }

    /** 这个用例的段池（不经被测代码）：法术直接读 spells[].hits 去掉 notInvoked，战技用选段结果 [skillHits]。 */
    fun pool(case: RankerCrossCheck.CompositionCase, skillHits: List<SkillHit>): List<SkillHit> =
        if (case.outputClass == OutputClass.SKILL) {
            skillHits
        } else {
            RankerTestData.skills.dataset.spells.first { it.id == case.id }.hits.filter { !it.notInvoked }
        }

    /** 参考输出：构成与逐段判定用同一批段 [selected]，三项蓄力情境按 [chargedOn]。 */
    fun output(case: RankerCrossCheck.CompositionCase, weapon: SkillWeapon?, selected: List<SkillHit>, chargedOn: Boolean): Output {
        val isSpell = case.outputClass != OutputClass.SKILL
        val own = if (isSpell) null else weapon
        val amounts = DoubleArray(DamageType.COUNT)
        val segs = ArrayList<Segment>()
        val extra = if (isSpell) magicSubs[case.id].orEmpty() else emptyList()
        for (hit in selected) {
            val one = amounts(hit, own)
            for (i in amounts.indices) amounts[i] += one[i]
            val total = one.sum()
            if (total > 0) segs += Segment(hit.subCategories + extra, one, total)
        }
        val total = amounts.sum()
        return Output(
            outputClass = case.outputClass,
            meansId = case.id,
            hand = 1,
            weaponWepType = own?.wepType,
            shares = amounts.map { if (total > 0) it / total else 0.0 },
            contexts = if (chargedOn) CHARGED_CONTEXTS else emptySet(),
            segs = segs,
        )
    }

    /** 一个构成用例的参考取段与参考输出（[RankerCrossCheck.CompositionCase.only] 非空时只勾那些段）。 */
    fun case(case: RankerCrossCheck.CompositionCase, weapon: SkillWeapon?, skillHits: List<SkillHit>): Pair<Selection, Output> {
        val pool = pool(case, skillHits)
        val selection = selection(pool, case.charged)
        val only = case.only
        val picked = if (only != null) pool.filter { !it.noDamage && it.atkId in only } else selection.hits
        return selection to output(case, weapon, picked, selection.chargedOn)
    }

    /**
     * 子类别限定的参考判定（usage「蓄力段（v4）」）：返回 null＝不生效；[Weights.weights] 为 null＝全额，否则是部分段
     * 命中时逐类型的命中占比（分母为 0 的类型填全部类型合计的占比）。没有勾选带伤害的段时只看 attackIndex 整招有没有
     * 这类段（[attackIndexSets]），不加权；整招也查不到时 [Weights.manual]＝要用户确认。
     */
    class Weights(val weights: DoubleArray?, val manual: Boolean)

    fun subCategories(need: List<Int>, out: Output, attackIndexSets: List<BuffSubCategorySet>?): Weights? {
        if (out.segs.isEmpty()) {
            if (attackIndexSets == null) return Weights(null, manual = true)
            if (attackIndexSets.none { set -> set.subs.any { it in need } }) return null
            return Weights(null, manual = false)
        }
        val hitSegs = out.segs.filter { segment -> segment.subs.any { it in need } }
        if (hitSegs.isEmpty()) return null
        if (hitSegs.size == out.segs.size) return Weights(null, manual = false)
        val all = out.segs.sumOf { it.total }
        val hit = hitSegs.sumOf { it.total }
        return Weights(
            DoubleArray(DamageType.COUNT) { i ->
                val denominator = out.segs.sumOf { it.amounts[i] }
                if (denominator > 0) hitSegs.sumOf { it.amounts[i] } / denominator else hit / all
            },
            manual = false,
        )
    }
}
