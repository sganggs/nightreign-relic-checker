package com.nightreign.relicchecker.gamedata.ranker

// 倍率字段表：rateFields[] 里哪些字段进伤害乘积、落在哪几类伤害上（Windows 端 parseRateFieldKey / rateFieldPlan /
// multiplierMap / flatMap，macOS 端 BuffLoadoutIndex 的 multiplierFields / flatFields / channelTable / flatTable）。
//
// 只收 countsAsDamage 的字段：valueKind=multiplier 的进乘积（damage 层与 attackPower 层都乘，两层相乘），
// valueKind=flat 的是攻击力加算点数（只按占比加权展示）；weakness / critical（conditionalDamage）、stance / status /
// special / flag / economy 一律不参与伤害乘算。

/** 字段作用在哪一层：最终伤害倍率（…AttackRate）、攻击力倍率（…AttackPowerRate）、攻击力加算（…AttackPower）。 */
enum class RateLayer { DAMAGE, ATTACK_POWER, FLAT }

/** 解析出来的字段键：前缀 + 作用层 + 落在哪几类伤害上。 */
data class ParsedRateKey(val prefix: String, val layer: RateLayer, val types: List<DamageType>)

/** 进计算的一个字段。[fallback] 是字段默认值（等于它的取值不参与计算）。 */
data class RatePlanField(
    val key: String,
    val zh: String,
    val layer: RateLayer,
    val types: List<DamageType>,
    val fallback: Double,
)

/** 一条 buff 实际用上的字段（详情展示用）。 */
data class RateUse(
    val key: String,
    val zh: String,
    val layer: RateLayer,
    val value: Double,
    val types: List<DamageType>,
)

class RateFieldPlan private constructor(
    /** 进乘积的字段（rateFields 顺序，乘法按这个顺序做，与两端一致）。 */
    val multiplier: List<RatePlanField>,
    /** 攻击力加算字段。 */
    val flat: List<RatePlanField>,
    val byKey: Map<String, BuffRateField>,
    /** 不 countsAsDamage 的字段键。 */
    val skipped: List<String>,
    /** countsAsDamage 却解析不了的字段键（数据集改了命名时这里会非空）。 */
    val unmapped: List<String>,
) {
    /**
     * 把一组 rates 折成「伤害类型 → 倍率」的 9 格表：取值必须是有限正数且不等于该字段的默认值。
     * [restrictedType] 非空（requires.physicalType / scope.atkAttribute）时倍率只落在那一个物理通道上。
     */
    fun multiplierTable(
        rates: Map<String, Double>,
        restrictedType: DamageType? = null,
        used: MutableList<RateUse>? = null,
    ): DoubleArray {
        val table = TypeTables.filled(1.0)
        for (field in multiplier) {
            val value = rates[field.key] ?: continue
            if (!value.isFinite() || value <= 0.0 || value == field.fallback) continue
            val types = if (restrictedType != null) field.types.filter { it == restrictedType } else field.types
            if (types.isEmpty()) continue
            used?.add(RateUse(field.key, field.zh, field.layer, value, types))
            for (type in types) table[type.ordinal] *= value
        }
        return table
    }

    /** 攻击力加算的 9 格表（物理加算铺到五个物理子类型）。 */
    fun flatTable(rates: Map<String, Double>, used: MutableList<RateUse>? = null): DoubleArray {
        val table = TypeTables.filled(0.0)
        for (field in flat) {
            val value = rates[field.key] ?: continue
            if (!value.isFinite() || value == field.fallback) continue
            used?.add(RateUse(field.key, field.zh, field.layer, value, field.types))
            for (type in field.types) table[type.ordinal] += value
        }
        return table
    }

    companion object {
        private val KEY_PATTERN = Regex("^([a-z]+)Attack(PowerRate|Power|Rate)$")

        private val PREFIX_ELEMENT = mapOf(
            "physics" to SkillElement.PHYSICAL,
            "magic" to SkillElement.MAGIC,
            "fire" to SkillElement.FIRE,
            "thunder" to SkillElement.LIGHTNING,
            "dark" to SkillElement.HOLY,
        )

        private val PREFIX_PHYSICAL = mapOf(
            "slash" to DamageType.SLASH,
            "blow" to DamageType.BLOW,
            "thrust" to DamageType.THRUST,
            "neutral" to DamageType.NEUTRAL,
        )

        /**
         * physicsAttackRate / physicsAttackPowerRate / physicsAttackPower → 前缀 + 作用层 + 伤害类型。
         * physics 覆盖全部物理子类型；dark 槽位在本作＝圣。认不出（saAttackPowerRate 削韧、bowDistRate…）返回 null。
         */
        fun parseKey(key: String): ParsedRateKey? {
            val match = KEY_PATTERN.matchEntire(key) ?: return null
            val prefix = match.groupValues[1]
            val types = PREFIX_ELEMENT[prefix]?.damageTypes ?: PREFIX_PHYSICAL[prefix]?.let { listOf(it) } ?: return null
            val layer = when (match.groupValues[2]) {
                "Rate" -> RateLayer.DAMAGE
                "PowerRate" -> RateLayer.ATTACK_POWER
                else -> RateLayer.FLAT
            }
            return ParsedRateKey(prefix, layer, types)
        }

        fun from(fields: List<BuffRateField>): RateFieldPlan {
            val multiplier = ArrayList<RatePlanField>()
            val flat = ArrayList<RatePlanField>()
            val byKey = LinkedHashMap<String, BuffRateField>()
            val skipped = ArrayList<String>()
            val unmapped = ArrayList<String>()
            for (field in fields) {
                byKey[field.key] = field
                if (!field.countsAsDamage) {
                    skipped += field.key
                    continue
                }
                val parsed = parseKey(field.key)
                if (parsed == null) {
                    unmapped += field.key
                    continue
                }
                val fallback = field.default ?: if (parsed.layer == RateLayer.FLAT) 0.0 else 1.0
                val entry = RatePlanField(field.key, field.zh.ifEmpty { field.key }, parsed.layer, parsed.types, fallback)
                when {
                    field.valueKind == "multiplier" && parsed.layer != RateLayer.FLAT -> multiplier += entry
                    field.valueKind == "flat" && parsed.layer == RateLayer.FLAT -> flat += entry
                    else -> unmapped += field.key
                }
            }
            return RateFieldPlan(multiplier, flat, byKey, skipped, unmapped)
        }
    }
}
