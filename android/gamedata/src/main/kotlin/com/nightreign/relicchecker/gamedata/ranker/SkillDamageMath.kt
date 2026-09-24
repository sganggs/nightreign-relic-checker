package com.nightreign.relicchecker.gamedata.ranker

// 选段、单段相对伤害、伤害构成、削韧／削精力与分段勾选（严格按 skills 数据集的 usage 块）：
//   · 选段：weapons[].skillVariants[战技 ID] → skills[].variants[i].atkIds，**不要**按 ctx 取并集；
//   · 正常版 / 专注值不足版：取段规则是「hit.fpBoth 或 noFp 与开关同侧」（[SkillHit.isOnSide]，fpBoth 段两侧都计）；
//   · 近战武器段（含战技的子弹段）：该属性伤害 ≈ 武器该属性攻击力 × motion/100 + flat（addBaseAtk 再加一份基础攻击力）；
//   · 法术段：只用 flat（motion 的五属性同值 100 是占位写法）；
//   · 伤害类型：attribute 为 WeaponAtkAttribute / WeaponAtkAttribute2 时回 weapons[] 取 atkAttribute / atkAttribute2。
// 与 Windows 端 selectVariant / selectHits / hitContribution / hitChipPlan / composition / hitPoise / hitStamina /
// hitOverridesFor，macOS 端 SkillDamageMath / SkillDataIndex.hits(for:weapon:) 逐条对应。

/** 一段命中在某类伤害上的贡献（分段芯片用）。`motionPercent` / `flat` 原样来自数据集（没声明就是 null）。 */
data class SegmentComponent(
    val type: DamageType,
    val motionPercent: Double?,
    val flat: Double?,
    /** addBaseAtk 额外加的那一份武器基础攻击力（「+基础攻击力」芯片）。 */
    val baseAttack: Double?,
    val amount: Double,
)

/** 一段命中（已按所选武器算好相对伤害）。 */
data class SkillSegment(
    val atkId: Int,
    /** 数据集原文的段名（未做 FP 替换）。 */
    val labelZh: String,
    val labelEn: String,
    val components: List<SegmentComponent>,
    /** 单段削韧 = poise + 武器 poiseDamageBase × poiseMv / 100。 */
    val poise: Double,
    /** 单段削精力（对格挡敌人精力条的削减）= stamina + 武器 staminaBase × staminaMv / 100。 */
    val stamina: Double,
    val isBullet: Boolean,
    val noFp: Boolean,
    val noDamage: Boolean,
    val attributeZh: String,
    /** 这一段的物理伤害类型（attribute 已解析到武器的 atkAttribute / atkAttribute2）；没有物理贡献时为 null。 */
    val physicalType: DamageType?,
    val total: Double,
) {
    val hasDamage: Boolean get() = total > 0.0

    /** 展示层的段名：「无FP版」→「专注值不足版」。 */
    val displayLabelZh: String get() = SkillTextZh.fpText(labelZh)

    /**
     * 芯片行要显示的通道：**只留对当前武器真正有贡献的那些**（amount > 0）。
     * addBaseAtk 单独也算一条通道，所以「可见芯片之和 == total」恒成立。
     */
    val visibleComponents: List<SegmentComponent> get() = components.filter { it.amount > 0.0 }

    /** 被隐藏的「动作值声明了、但武器该属性攻击力为 0」的通道数（行末补一句「其余属性该武器为 0」）。 */
    val hiddenZeroComponentCount: Int
        get() = components.count { it.amount <= 0.0 && (it.motionPercent ?: 0.0) > 0.0 }

    fun amount(type: DamageType): Double = components.firstOrNull { it.type == type }?.amount ?: 0.0
}

/** 构成明细里的一格。 */
data class DamageShare(val type: DamageType, val share: Double, val amount: Double)

/** 勾选的段汇总出的相对伤害构成。 */
data class DamageComposition(
    /** 按 [DamageType.ordinal] 索引的相对伤害量。 */
    val amounts: List<Double>,
    val total: Double,
    val segmentCount: Int,
) {
    val hasDamage: Boolean get() = total > 0.0
    val isEmpty: Boolean get() = !hasDamage

    fun amount(type: DamageType): Double = amounts.getOrElse(type.ordinal) { 0.0 }

    /** 占比（0…1）；总量为 0 时一律 0。 */
    fun share(type: DamageType): Double = if (total > 0.0) amount(type) / total else 0.0

    /** 按 [DamageType.ordinal] 索引的占比，排名引擎直接加权用。 */
    val shares: List<Double> by lazy(LazyThreadSafetyMode.PUBLICATION) {
        DamageType.entries.map { share(it) }
    }

    /** 有占比的类型，按占比降序（相同占比按类型顺序）。 */
    val breakdown: List<DamageShare>
        get() = DamageType.entries
            .map { DamageShare(it, share(it), amount(it)) }
            .filter { it.share > 0.0000001 }
            .sortedWith(compareByDescending<DamageShare> { it.share }.thenBy { it.type.ordinal })

    val physicalShare: Double get() = DamageType.PHYSICAL.sumOf { share(it) }

    companion object {
        val EMPTY = DamageComposition(List(DamageType.COUNT) { 0.0 }, 0.0, 0)
    }
}

/** 分段列表工具条的三个动作（Windows 端 hitOverridesFor 的 action）。 */
enum class HitAction { ALL, NONE, RESET }

object SkillDamageMath {
    /**
     * 只有法术段忽略 motion：usage「法术 / 子弹段」的结论是「motion 只在施法器该属性 attackBase 非 0 时才有意义」，
     * 法术走「没有武器」这一路；战技的子弹段挂的是真武器、motion 是真实动作值，照常乘。
     */
    fun usesMotion(isSpell: Boolean): Boolean = !isSpell

    /** 这一段的物理攻击类型；WeaponAtkAttribute / WeaponAtkAttribute2 要回查武器（没有武器时退成「物理（无类型）」）。 */
    fun physicalTypeFor(hit: SkillHit, weapon: SkillWeapon?): DamageType = when (hit.attribute) {
        "Slash" -> DamageType.SLASH
        "Strike" -> DamageType.BLOW
        "Pierce" -> DamageType.THRUST
        "Standard" -> DamageType.NEUTRAL
        "WeaponAtkAttribute" -> if (weapon == null) DamageType.PHYS_NONE else DamageType.physical(weapon.atkAttribute)
        "WeaponAtkAttribute2" -> if (weapon == null) DamageType.PHYS_NONE else DamageType.physical(weapon.atkAttribute2)
        else -> DamageType.PHYS_NONE
    }

    /**
     * 单段在九类伤害上的相对数值（不含强化、补正，只做配比用）：
     * 攻击力 × motion/100 + flat，addBaseAtk 再加一份攻击力；noDamage 段整段为 0。
     */
    fun hitContribution(hit: SkillHit, weapon: SkillWeapon?, isSpell: Boolean): List<Double> {
        val out = DoubleArray(DamageType.COUNT)
        if (hit.noDamage) return out.asList()
        val motionOn = usesMotion(isSpell)
        val physType = physicalTypeFor(hit, weapon)
        for (element in SkillElement.entries) {
            val attack = weapon?.attack(element) ?: 0.0
            val motion = if (motionOn) hit.motionOf(element) ?: 0.0 else 0.0
            val flat = hit.flatOf(element) ?: 0.0
            var value = attack * motion / 100.0 + flat
            // addBaseAtk 是「再加一份武器该属性攻击力」，与 motion 是两回事，不受 motion 开关影响。
            if (hit.addBaseAtk) value += attack
            if (!(value > 0.0)) continue
            val type = if (element == SkillElement.PHYSICAL) physType else channelOf(element)
            out[type.ordinal] += value
        }
        return out.asList()
    }

    /**
     * 把一段命中换算成分段芯片与相对伤害（macOS 端 SkillDamageMath.segment）。
     * [isSpell] 缺省按「没有武器即法术」处理。
     */
    fun segment(hit: SkillHit, weapon: SkillWeapon?, isSpell: Boolean = weapon == null): SkillSegment {
        val physType = physicalTypeFor(hit, weapon)
        val motionOn = usesMotion(isSpell)
        val components = ArrayList<SegmentComponent>(SkillElement.entries.size)
        if (!hit.noDamage) {
            for (element in SkillElement.entries) {
                val base = weapon?.attack(element) ?: 0.0
                val motion = hit.motionOf(element)
                val flat = hit.flatOf(element)
                val baseAttack = if (hit.addBaseAtk && base > 0.0) base else null
                if (motion == null && flat == null && baseAttack == null) continue
                var amount = 0.0
                if (motionOn && motion != null) amount += base * motion / 100.0
                if (flat != null) amount += flat
                if (baseAttack != null) amount += baseAttack
                val type = if (element == SkillElement.PHYSICAL) physType else channelOf(element)
                components += SegmentComponent(
                    type = type,
                    motionPercent = if (motionOn) motion else null,
                    flat = flat,
                    baseAttack = baseAttack,
                    amount = maxOf(0.0, amount),
                )
            }
        }
        components.sortBy { it.type.ordinal }
        val total = components.sumOf { it.amount }
        return SkillSegment(
            atkId = hit.atkId,
            labelZh = hit.displayLabel,
            labelEn = hit.label.orEmpty(),
            components = components,
            poise = hitPoise(hit, weapon),
            stamina = hitStamina(hit, weapon),
            isBullet = hit.isBullet,
            noFp = hit.noFp,
            noDamage = hit.noDamage,
            attributeZh = hit.attributeZh,
            physicalType = if (components.any { it.type.isPhysical }) physType else null,
            total = total,
        )
    }

    /** 勾选中的段汇总成构成。total 是相对值，没有绝对意义。 */
    fun composition(hits: List<SkillHit>, weapon: SkillWeapon?, isSpell: Boolean): DamageComposition {
        val parts = DoubleArray(DamageType.COUNT)
        var total = 0.0
        var count = 0
        for (hit in hits) {
            count += 1
            val one = hitContribution(hit, weapon, isSpell)
            for (index in 0 until DamageType.COUNT) {
                val value = one[index]
                if (value == 0.0) continue
                parts[index] += value
                total += value
            }
        }
        return DamageComposition(parts.asList(), total, count)
    }

    /** 按已换算好的段汇总（macOS 端 SkillDamageMath.composition(of:selected:)）。 */
    fun composition(segments: List<SkillSegment>, selected: Set<Int>): DamageComposition {
        val parts = DoubleArray(DamageType.COUNT)
        var total = 0.0
        var count = 0
        for (segment in segments) {
            if (segment.atkId !in selected) continue
            count += 1
            for (component in segment.components) {
                parts[component.type.ordinal] += component.amount
                total += component.amount
            }
        }
        return DamageComposition(parts.asList(), total, count)
    }

    /** 单段削韧 = poise + 武器 poiseDamageBase × poiseMv / 100。 */
    fun hitPoise(hit: SkillHit, weapon: SkillWeapon?): Double =
        finite(hit.poise) + finite(weapon?.poiseDamageBase ?: 0.0) * finite(hit.poiseMv) / 100.0

    /** 单段削精力（对格挡敌人精力条的削减）= stamina + 武器 staminaBase × staminaMv / 100。 */
    fun hitStamina(hit: SkillHit, weapon: SkillWeapon?): Double =
        finite(hit.stamina) + finite(weapon?.staminaBase ?: 0.0) * finite(hit.staminaMv) / 100.0

    /** 这条输出手段至少有一段能算出非 0 的相对值吗？算不出来的选中后构成恒为 0，是死路。 */
    fun hasAnyDamage(hits: List<SkillHit>, weapon: SkillWeapon?, isSpell: Boolean): Boolean =
        hits.any { hit -> hitContribution(hit, weapon, isSpell).any { it > 0.0 } }

    // ---- 分段勾选 ----------------------------------------------------------

    /**
     * 默认勾选：与「使用专注值不足版本」开关同侧、非 noDamage 的段；两侧共用的 fpBoth 段恒勾（[SkillHit.isOnSide]）。
     * 两侧互为替代，一起勾会把同一击算两遍；数值为 0 但没标 noDamage 的段照样勾上（它对构成的贡献本来就是 0）。
     */
    fun defaultSelection(hits: List<SkillHit>, useNoFp: Boolean = false): Set<Int> =
        hits.filter { !it.noDamage && it.isOnSide(useNoFp) }.mapTo(LinkedHashSet()) { it.atkId }

    /** 用户手动勾选写进 overrides（atkId → 勾 / 不勾）；没写的按 [defaultSelection] 的规则。 */
    fun isHitEnabled(hit: SkillHit, overrides: Map<Int, Boolean>, useNoFp: Boolean): Boolean {
        if (hit.noDamage) return false
        return overrides[hit.atkId] ?: hit.isOnSide(useNoFp)
    }

    /** 当前勾中的段（保持数据顺序）。 */
    fun selectedHits(hits: List<SkillHit>, overrides: Map<Int, Boolean>, useNoFp: Boolean): List<SkillHit> =
        hits.filter { isHitEnabled(it, overrides, useNoFp) }

    /**
     * 分段列表工具条的三个动作，返回完整的 override 表（[HitAction.RESET]＝清空，退回默认规则）。
     * 「全选」只勾**当前这一侧**的段：正常版与专注值不足版互为替代，两边一起勾会把同一击算两遍；
     * 两侧共用的 fpBoth 段在哪一侧都勾上。
     */
    fun hitOverridesFor(hits: List<SkillHit>, action: HitAction, useNoFp: Boolean): Map<Int, Boolean> {
        if (action == HitAction.RESET) return emptyMap()
        val overrides = LinkedHashMap<Int, Boolean>()
        for (hit in hits) {
            if (hit.noDamage) continue
            overrides[hit.atkId] = action == HitAction.ALL && hit.isOnSide(useNoFp)
        }
        return overrides
    }

    internal fun channelOf(element: SkillElement): DamageType = when (element) {
        SkillElement.PHYSICAL -> DamageType.PHYS_NONE
        SkillElement.MAGIC -> DamageType.MAGIC
        SkillElement.FIRE -> DamageType.FIRE
        SkillElement.LIGHTNING -> DamageType.LIGHTNING
        SkillElement.HOLY -> DamageType.HOLY
    }

    private fun finite(value: Double): Double = if (value.isFinite()) value else 0.0
}
