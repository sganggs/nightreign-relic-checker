package com.nightreign.relicchecker.gamedata.ranker

import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive

// buffs 数据集顶层：解码用的 DTO（internal）与页面直接用的不可变模型 [BuffDataset]。
// 顶层只声明要用的键；diagnostics（68 KB）/ schemaChangelog（16 KB）/ sources / conditionFields / chainFields /
// weaponAffixPools 不声明，解码时跳过。notes 需要原文展示（页面底部折叠区），按对象解码后只留字符串与 userQuestions。

@Serializable
internal data class BuffsFileDto(
    val schemaVersion: Int? = null,
    val gameVersion: String = "",
    val dataVersion: String = "",
    val generatedAt: String = "",
    val notes: JsonObject? = null,
    val stackingRules: BuffZhNote = BuffZhNote(),
    val rateFields: List<BuffRateField> = emptyList(),
    val rateFieldGroups: List<BuffRateFieldGroup> = emptyList(),
    val enums: BuffEnumsDto = BuffEnumsDto(),
    val counts: BuffCounts = BuffCounts(),
    val slotRules: BuffSlotRules? = null,
    val weaponAffixes: List<BuffWeaponAffixInfo> = emptyList(),
    val fixedRelics: List<BuffFixedRelic> = emptyList(),
    val attackIndex: BuffAttackIndexDto = BuffAttackIndexDto(),
    val buffs: List<BuffEntry> = emptyList(),
)

@Serializable
internal data class LabelDto(val zh: String? = null, val en: String? = null, val note: String? = null)

@Serializable
internal data class BehaviorDto(val code: String = "unknown", val zh: String = "")

@Serializable
internal data class BuffEnumsDto(
    val attackContext: Map<String, LabelDto> = emptyMap(),
    val wepType: Map<String, LabelDto> = emptyMap(),
    val atkSubCategory: Map<String, LabelDto> = emptyMap(),
    val sourceSlot: Map<String, LabelDto> = emptyMap(),
    val sourceKind: Map<String, String> = emptyMap(),
    val activation: Map<String, LabelDto> = emptyMap(),
    val exclusiveScope: Map<String, String> = emptyMap(),
    val stateInfo: Map<String, LabelDto> = emptyMap(),
    val target: Map<String, LabelDto> = emptyMap(),
    val wepParamChange: Map<String, LabelDto> = emptyMap(),
    val spAttribute: Map<String, LabelDto> = emptyMap(),
    val spCategoryBehavior: List<BehaviorDto> = emptyList(),
)

@Serializable
internal data class BuffAttackIndexDto(
    val skills: Map<String, BuffAttackIndexEntry> = emptyMap(),
    val spells: Map<String, BuffAttackIndexEntry> = emptyMap(),
    val melee: List<BuffSubCategorySet> = emptyList(),
    val ranged: List<BuffSubCategorySet> = emptyList(),
)

/** counts 里页面「数据版本与来源」要显示的几项。 */
@Serializable
data class BuffCounts(
    val buffs: Int = 0,
    val weaponAffixes: Int = 0,
    val fixedRelics: Int = 0,
    val buffsWithStackInput: Int = 0,
    val exclusiveKeys: Int = 0,
)

/** notes.userQuestions 的一问一答（Q1…Q5）。 */
data class BuffUserQuestion(val key: String, val question: String, val answer: String)

/** enums 块里页面要用的几张表（只取中文名）。 */
data class BuffEnums(
    /** 攻击情境键 → 中文名（criticalHit → 致命一击／处决）。 */
    val attackContext: Map<String, String>,
    /** wepType → 中文名（1 短剑、57 手杖、61 圣印记…）。 */
    val wepType: Map<Int, String>,
    /** 攻击子类别 → 中文名（112 战技攻击…）。 */
    val atkSubCategory: Map<Int, String>,
    /** sourceSlot → 中文名 / 说明。 */
    val sourceSlot: Map<String, String>,
    val sourceSlotNote: Map<String, String>,
    /** 来源类型 → 中文名（relicAffix → 遗物词条）。 */
    val sourceKind: Map<String, String>,
    /** activation → 中文说明。 */
    val activation: Map<String, String>,
    /** exclusiveScope → 中文说明。 */
    val exclusiveScope: Map<String, String>,
    /** SP_EFFECT_TYPE → 中文名。 */
    val stateInfo: Map<Int, String>,
    /** target → 中文说明。 */
    val target: Map<String, String>,
    /** wepParamChange（武器槽）→ 中文名。 */
    val wepParamChange: Map<Int, String>,
    /** spAttribute → 中文名。 */
    val spAttribute: Map<Int, String>,
    /** spCategoryBehavior 代码 → 中文说明。 */
    val spCategoryBehavior: Map<String, String>,
)

/** attackIndex：每个战技／法术实际命中段的子类别集合（appliesTo=conditional 且带 subCategoriesAny 时用）。 */
data class BuffAttackIndex(
    val skills: Map<Int, List<BuffSubCategorySet>>,
    val spells: Map<Int, List<BuffSubCategorySet>>,
    /** 近战普通攻击／弓弩射击的子类别人口（只用 subs）。 */
    val melee: List<BuffSubCategorySet>,
    val ranged: List<BuffSubCategorySet>,
)

/** buffs 数据集（解码后的不可变模型）。 */
class BuffDataset internal constructor(
    val schemaVersion: Int?,
    val gameVersion: String,
    val dataVersion: String,
    val generatedAt: String,
    /** notes 里的字符串原文（ranking / appliesTo / sourceSlot …），页面底部原样展示；键按数据顺序。 */
    val notes: Map<String, String>,
    /** notes.userQuestions（按 Q1、Q2…Q10 的自然顺序）。 */
    val userQuestions: List<BuffUserQuestion>,
    val stackingRulesZh: String,
    val rateFields: List<BuffRateField>,
    val rateFieldGroups: List<BuffRateFieldGroup>,
    val enums: BuffEnums,
    val counts: BuffCounts,
    /** 缺失时为 null（页面显示「数据未内置」），计算用 [slotRulesOrFallback]。 */
    val slotRules: BuffSlotRules?,
    val weaponAffixes: List<BuffWeaponAffixInfo>,
    val fixedRelics: List<BuffFixedRelic>,
    val attackIndex: BuffAttackIndex,
    val buffs: List<BuffEntry>,
) {
    val slotRulesOrFallback: BuffSlotRules get() = slotRules ?: BuffSlotRules()

    fun rateField(key: String): BuffRateField? = rateFields.firstOrNull { it.key == key }

    /** 攻击情境的中文名；数据集没给标签时退回原始键。 */
    fun attackContextLabel(key: String): String = enums.attackContext[key]?.takeIf { it.isNotEmpty() } ?: key

    fun sourceKindLabel(kind: String): String = enums.sourceKind[kind] ?: kind

    fun sourceSlotLabel(slot: String): String = enums.sourceSlot[slot]?.takeIf { it.isNotEmpty() } ?: slot

    /** 叠加组 stateInfo 的中文名；缺标签时退回裸数字（「强化致命一击（367）」）。 */
    fun stateInfoLabel(value: Int): String {
        val label = enums.stateInfo[value]
        return if (label.isNullOrEmpty()) value.toString() else "$label（$value）"
    }

    companion object {
        internal fun from(dto: BuffsFileDto): BuffDataset {
            val notes = LinkedHashMap<String, String>()
            val questions = ArrayList<BuffUserQuestion>()
            dto.notes?.forEach { (key, value) ->
                when {
                    value is JsonPrimitive && value.isString -> notes[key] = value.content
                    key == "userQuestions" && value is JsonObject -> value.forEach { (qKey, qValue) ->
                        val one = qValue as? JsonObject ?: return@forEach
                        val question = (one["question"] as? JsonPrimitive)?.takeIf { it.isString }?.content.orEmpty()
                        val answer = (one["answer"] as? JsonPrimitive)?.takeIf { it.isString }?.content.orEmpty()
                        if (question.isNotEmpty() || answer.isNotEmpty()) questions += BuffUserQuestion(qKey, question, answer)
                    }
                }
            }
            questions.sortWith(compareBy<BuffUserQuestion> { it.key.length }.thenBy { it.key })
            val enums = dto.enums
            return BuffDataset(
                schemaVersion = dto.schemaVersion,
                gameVersion = dto.gameVersion,
                dataVersion = dto.dataVersion,
                generatedAt = dto.generatedAt,
                notes = notes,
                userQuestions = questions,
                stackingRulesZh = dto.stackingRules.zh,
                rateFields = dto.rateFields,
                rateFieldGroups = dto.rateFieldGroups,
                enums = BuffEnums(
                    attackContext = enums.attackContext.zhByKey(),
                    wepType = enums.wepType.zhByInt(),
                    atkSubCategory = enums.atkSubCategory.zhByInt(),
                    sourceSlot = enums.sourceSlot.zhByKey(),
                    sourceSlotNote = enums.sourceSlot.mapNotNull { (key, label) ->
                        label.note?.takeIf { it.isNotEmpty() }?.let { key to it }
                    }.toMap(),
                    sourceKind = enums.sourceKind,
                    activation = enums.activation.zhByKey(),
                    exclusiveScope = enums.exclusiveScope,
                    stateInfo = enums.stateInfo.zhByInt(),
                    target = enums.target.zhByKey(),
                    wepParamChange = enums.wepParamChange.zhByInt(),
                    spAttribute = enums.spAttribute.zhByInt(),
                    spCategoryBehavior = enums.spCategoryBehavior.associate { it.code to it.zh },
                ),
                counts = dto.counts,
                slotRules = dto.slotRules,
                weaponAffixes = dto.weaponAffixes,
                fixedRelics = dto.fixedRelics,
                attackIndex = BuffAttackIndex(
                    skills = dto.attackIndex.skills.setsByInt(),
                    spells = dto.attackIndex.spells.setsByInt(),
                    melee = dto.attackIndex.melee,
                    ranged = dto.attackIndex.ranged,
                ),
                buffs = dto.buffs,
            )
        }

        private fun Map<String, LabelDto>.zhByKey(): Map<String, String> =
            mapNotNull { (key, label) -> label.zh?.let { key to it } }.toMap()

        private fun Map<String, LabelDto>.zhByInt(): Map<Int, String> =
            mapNotNull { (key, label) -> key.toIntOrNull()?.let { id -> label.zh?.let { id to it } } }.toMap()

        private fun Map<String, BuffAttackIndexEntry>.setsByInt(): Map<Int, List<BuffSubCategorySet>> =
            mapNotNull { (key, entry) -> key.toIntOrNull()?.let { it to entry.subCategorySets } }.toMap()
    }
}
