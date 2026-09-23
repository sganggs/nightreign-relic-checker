package com.nightreign.relicchecker.gamedata.bosses

import kotlinx.serialization.Serializable

// nightreign-bosses-v1.03.5.json（bossesSchemaVersion 4）的解码结构。
//
// 只声明页面要用的字段；diagnostics / schemaChangelog、notes 里的大块明细、
// scalingTiers[].fullEffects、placementMaps[].evidence 之类一律不声明，解码时直接跳过。
// 所有字段都有默认值（配合 GameDataJson.lenient 的 coerceInputValues：null 退默认值），
// 默认值与 macOS 端 RelicCore/BossData.swift 的 `bossXxx(.key, default:)` 逐项一致。
//
// 数值字段一律按 Double 解码（整数、小数、带引号的数字都能读），进领域模型时再取整，
// 口径同 macOS 的 bossInt（四舍五入到最近整数，.5 远离 0）。
//
// 解析耗时：debug 包在模拟器上首次解码是冷代码（解释执行），耗时随解码的字段数线性增长。
// 数值行 / depthStats / deepOfNight 里的 attackRatesBase（五属性攻击倍率）与 staminaAttackRateBase
// 页面从不显示（两端桌面也只在常驻缩放明细里用 attackRates），约占全部数值的三成，因此不声明；
// depthStats[N].depthSpEffectId 与 mutationSetId（mutationPool 已含它）同样不显示，也不声明；
// 常驻缩放 permanentScaling 的 attackRates / staminaAttackRate 仍然解码（16178「只加物理」要写出来）。

@Serializable
internal class BossesFileDto(
    val bossesSchemaVersion: Int? = null,
    val gameVersion: String = "未知",
    val dataVersion: String = "未知",
    val generatedAt: String = "",
    val sources: List<BossSourceDto> = emptyList(),
    val affinityNames: Map<String, BossLocalizedNameDto> = emptyMap(),
    val scalingTiers: Map<String, BossScalingGroupDto> = emptyMap(),
    val permanentScaling: Map<String, BossPermanentEffectDto> = emptyMap(),
    val caveats: List<String> = emptyList(),
    val nightlords: List<BossNightlordDto> = emptyList(),
    val nightBosses: List<BossNightBossDto> = emptyList(),
    val notes: BossNotesDto? = null,
    val deepOfNightText: BossDeepOfNightTextDto? = null,
    val deepOfNightDepths: Map<String, BossDepthInfoDto> = emptyMap(),
    val deepOfNightTiers: Map<String, BossDepthTierDto> = emptyMap(),
    val mutations: Map<String, BossMutationDto> = emptyMap(),
    val mutationCategories: List<BossMutationCategoryDto> = emptyList(),
    val roleNames: Map<String, BossRoleNameDto> = emptyMap(),
    val roleSummary: Map<String, Double> = emptyMap(),
    val roleSummaryDetail: Map<String, BossRoleSummaryDetailDto> = emptyMap(),
    val placementMaps: Map<String, BossPlacementMapDto> = emptyMap(),
)

@Serializable
internal class BossSourceDto(
    val name: String = "",
    val url: String = "",
    val revision: String = "",
    val license: String = "",
    val usage: String = "",
)

@Serializable
internal class BossLocalizedNameDto(val zh: String = "", val en: String = "")

@Serializable
internal class BossWeaknessDto(val code: Double = -1.0, val zh: String = "", val en: String = "")

@Serializable
internal class BossDamageRatesDto(
    val standard: Double = 1.0,
    val slash: Double = 1.0,
    val strike: Double = 1.0,
    val pierce: Double = 1.0,
    val magic: Double = 1.0,
    val fire: Double = 1.0,
    val lightning: Double = 1.0,
    val holy: Double = 1.0,
)

@Serializable
internal class BossResistDto(
    val poison: Double = 0.0,
    val rot: Double = 0.0,
    val bleed: Double = 0.0,
    val frost: Double = 0.0,
    val sleep: Double = 0.0,
    val madness: Double = 0.0,
    val death: Double = 0.0,
)

@Serializable
internal class BossAttackRatesDto(
    val physical: Double = 1.0,
    val magic: Double = 1.0,
    val fire: Double = 1.0,
    val lightning: Double = 1.0,
    val holy: Double = 1.0,
)

@Serializable
internal class BossScalingTierDto(
    val hp: Double = 1.0,
    val poiseTaken: Double = 1.0,
    val poiseRecover: Double = 1.0,
    val ailmentDamageRate: Double = 1.0,
    val poisonRate: Double = 1.0,
    val buildupRate: Double = 1.0,
    val attackRate: Double = 1.0,
    val staminaAttackRate: Double = 1.0,
)

@Serializable
internal class BossScalingPairDto(
    val duo: BossScalingTierDto? = null,
    val trio: BossScalingTierDto? = null,
)

@Serializable
internal class BossScalingGroupDto(
    val group: String? = null,
    val duo: BossScalingTierDto? = null,
    val trio: BossScalingTierDto? = null,
)

@Serializable
internal class BossPermanentEffectDto(
    val nameEn: String? = null,
    val nameZh: String = "",
    val hp: Double = 1.0,
    val poiseTaken: Double = 1.0,
    val poiseRecover: Double = 1.0,
    val ailmentDamageRate: Double = 1.0,
    val attackRate: Double = 1.0,
    val attackRates: BossAttackRatesDto? = null,
    val staminaAttackRate: Double = 1.0,
    val deepOfNight: Boolean = false,
)

@Serializable
internal class BossDeepOfNightDto(
    val hp: Double = 0.0,
    val hpMultiplier: Double = 1.0,
    val poiseTakenBase: Double = 1.0,
    val poiseRecoverMultiplier: Double = 1.0,
    val ailmentDamageRateBase: Double = 1.0,
    val attackRateBase: Double = 1.0,
    val permScalingIds: List<Double> = emptyList(),
)

@Serializable
internal class BossDepthStatsDto(
    val hp: Double = 0.0,
    val hpMultiplier: Double = 1.0,
    val poiseTakenBase: Double = 1.0,
    val attackRateBase: Double = 1.0,
)

@Serializable
internal class BossRoleEvidenceDto(
    val npcId: Double? = null,
    val msb: String? = null,
    val part: String = "",
    val table: String = "",
    val row: String = "",
    val note: String = "",
)

/** 夜王的 fight 与守夜 / 野外首领的 variant 共用这一套数值字段。 */
@Serializable
internal class BossFightDto(
    val npcId: Double = 0.0,
    val npcIds: List<Double> = emptyList(),
    val paramdexName: String? = null,
    val labelZh: String = "",
    val labelEn: String = "",
    val labelUncertain: Boolean = false,
    val isMain: Boolean = false,
    val threat: String? = null,
    val hp: Double = 0.0,
    val hpBase: Double = 0.0,
    val hpMultiplier: Double = 1.0,
    val poise: Double = -1.0,
    val poiseRecover: Double = 0.0,
    val poiseTakenBase: Double = 1.0,
    val poiseRecoverMultiplier: Double = 1.0,
    val damageRates: BossDamageRatesDto? = null,
    val ailmentDamageRateBase: Double = 1.0,
    val resist: BossResistDto? = null,
    val immune: List<String> = emptyList(),
    val permScalingIds: List<Double> = emptyList(),
    val deepOfNight: BossDeepOfNightDto? = null,
    val scalingId: Double? = null,
    val scaling: BossScalingPairDto? = null,
    val attackRateBase: Double = 1.0,
    val chaosCorrectId: Double? = null,
    val depthStats: Map<String, BossDepthStatsDto>? = null,
    val mutationPool: List<Double> = emptyList(),
    val noReward: Boolean = false,
    val roles: List<String> = emptyList(),
    val roleEvidence: Map<String, List<BossRoleEvidenceDto>> = emptyMap(),
    val rowRoles: Map<String, List<String>> = emptyMap(),
)

@Serializable
internal class BossNightlordDto(
    val menuId: Double = 0.0,
    val paramdexName: String = "",
    val nameZh: String = "",
    val nameEn: String = "",
    val expeditionZh: String = "",
    val expeditionEn: String = "",
    val everdark: Boolean = false,
    val variantKey: String = "normal",
    val variantNameZh: String = "",
    val variantNameEn: String = "",
    val sortId: Double = 0.0,
    val weakness: List<BossWeaknessDto> = emptyList(),
    val descriptionZh: String = "",
    val fights: List<BossFightDto> = emptyList(),
    val depthChanceWeights: Map<String, Double> = emptyMap(),
    val roles: List<String> = emptyList(),
)

@Serializable
internal class BossNameEvidenceDto(
    val fmg: String = "",
    val id: String = "",
    val en: String = "",
    val zh: String = "",
    val reason: String = "",
)

@Serializable
internal class BossNightBossDto(
    val id: String = "",
    val nameEn: String = "",
    val nameZh: String = "",
    val nameSource: String = "",
    val nameInferred: Boolean = false,
    val npcNameId: Double? = null,
    val chrIds: List<Double> = emptyList(),
    val tier: String = "field",
    val tiers: List<String> = emptyList(),
    val variants: List<BossFightDto> = emptyList(),
    val roles: List<String> = emptyList(),
    val nameApprox: Boolean = false,
    val nameEvidence: BossNameEvidenceDto? = null,
    val nameNote: String = "",
    val nameSourceUrl: String = "",
    val nameZhFallback: String = "",
    val nameZhFallbackNote: String = "",
    val displayFallbackZh: String = "",
    val nameZhRejected: BossNameEvidenceDto? = null,
    val hidden: Boolean = false,
    val noReward: Boolean = false,
)

@Serializable
internal class BossUnmatchedNameDto(val nameEn: String = "", val chrId: Double = 0.0)

@Serializable
internal class BossNameCollisionDto(val nameZh: String = "")

@Serializable
internal class BossRoleAuditDto(val summary: List<String> = emptyList())

@Serializable
internal class BossNotesDto(
    val unmatchedNames: List<BossUnmatchedNameDto> = emptyList(),
    val nameCollisions: List<BossNameCollisionDto> = emptyList(),
    val multiplayerScalingAudit: List<String> = emptyList(),
    val deepOfNightAudit: List<String> = emptyList(),
    val roleAudit: BossRoleAuditDto? = null,
)

@Serializable
internal class BossGameTextDto(val zh: String = "", val en: String = "", val textId: Double? = null)

@Serializable
internal class BossDeepOfNightTextDto(
    val deepOfNight: BossGameTextDto? = null,
    val depth: BossGameTextDto? = null,
    val mutation: BossGameTextDto? = null,
    val mutationCount: BossGameTextDto? = null,
    val description: BossGameTextDto? = null,
)

@Serializable
internal class BossMapChallengeWeightDto(
    val map: Double = 0.0,
    val nightlord: Double = 0.0,
    val none: Double = 0.0,
)

@Serializable
internal class BossDepthInfoDto(
    val rankId: Double = 0.0,
    val paramdexName: String? = null,
    val labelZh: String = "",
    val labelEn: String = "",
    val cursedUncommonRate: Double = 0.0,
    val cursedRareRate: Double = 0.0,
    val mapChallengeWeight: BossMapChallengeWeightDto? = null,
    val cataclysmWeight: Map<String, Double> = emptyMap(),
)

@Serializable
internal class BossDepthTierStatsDto(
    val spEffectId: Double? = null,
    val nameEn: String? = null,
    val hp: Double = 1.0,
    val attackRate: Double = 1.0,
    val poiseTaken: Double = 1.0,
    val staminaAttackRate: Double = 1.0,
)

@Serializable
internal class BossDepthTierDto(
    val group: String? = null,
    val tier: String? = null,
    val depths: Map<String, BossDepthTierStatsDto> = emptyMap(),
)

@Serializable
internal class BossMutationDto(
    val nameZh: String = "变异个体",
    val nameEn: String = "Variant",
    val setNameEn: String? = null,
    val vfxSpEffectIds: List<Double> = emptyList(),
    val vfxTier: Double? = null,
    val statSpEffectId: Double? = null,
    val statNameEn: String? = null,
    val hp: Double = 1.0,
    val attackRate: Double = 1.0,
    val runeRate: Double = 1.0,
)

@Serializable
internal class BossMutationCategoryDto(
    val rowId: Double = 0.0,
    val categoryId: Double = 0.0,
    val categoryZh: String = "",
    val categoryEn: String = "",
    val mapId: Double = 0.0,
    val mapZh: String = "",
    val mapEn: String = "",
    val mutatedCount: Map<String, Double> = emptyMap(),
)

@Serializable
internal class BossRoleNameDto(val zh: String = "", val en: String = "", val description: String = "")

@Serializable
internal class BossRoleSummaryDetailDto(
    val groups: Double = 0.0,
    val variants: Double = 0.0,
    val rows: Double = 0.0,
    val nightlords: Double = 0.0,
    val fights: Double = 0.0,
    val fightRows: Double = 0.0,
)

@Serializable
internal class BossTileVariantDto(val zh: String = "", val en: String = "")

/** placementMaps 只取地图的 Paramdex 名 / 开放地块的地形名（出处摘要下的补充小字用）。 */
@Serializable
internal class BossPlacementMapDto(
    val paramdexName: String? = null,
    val tileVariant: BossTileVariantDto? = null,
)
