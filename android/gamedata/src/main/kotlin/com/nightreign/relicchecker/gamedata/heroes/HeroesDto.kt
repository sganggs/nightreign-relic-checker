package com.nightreign.relicchecker.gamedata.heroes

import kotlinx.serialization.Serializable

// 「角色属性」页读 data/nightreign-heroes-v1.03.5.json（schemaVersion 1）用的 DTO。
//
// 只声明页面用得到的字段，其余（relicPools、poolWeights、spEffectId、abilityReinforce 等）
// 由 GameDataJson.lenient 的 ignoreUnknownKeys 直接跳过，不建对象。所有字段都给默认值：
// 缺字段或写成 null 时退回默认值（coerceInputValues），而不是整份失败 —— 与 macOS 端
// HeroData.swift「已知字段缺失、类型不符时退回默认值」同一原则。
//
// 属性 / 增减量字典的值按 Double? 读（数据集里偶有写成浮点的可能），转模型时四舍五入取整、
// 丢掉 null（macOS heroIntDictionary 同一口径：值写成 null 等于「没有这一项」，页面给破折号）。

@Serializable
internal data class HeroesFileDto(
    val schemaVersion: Int? = null,
    val datasetId: String = "",
    val gameVersion: String = "",
    val dataVersion: String = "",
    val generatedAt: String = "",
    val sources: List<HeroSourceDto> = emptyList(),
    val statNames: HeroStatNamesDto = HeroStatNamesDto(),
    val crossChecks: List<HeroCrossCheckDto> = emptyList(),
    /** null = 数据集根本没给 growthGraphs（Windows hasHeroData 据此判「数据未内置」）。 */
    val growthGraphs: Map<String, HeroGrowthGraphDto>? = null,
    val interpolation: HeroInterpolationDto = HeroInterpolationDto(),
    val counts: Map<String, Int> = emptyMap(),
    val caveats: List<String> = emptyList(),
    val heroes: List<HeroDto> = emptyList(),
    val statModifiers: List<HeroStatModifierDto> = emptyList(),
    val libraRespecs: List<HeroLibraRespecDto> = emptyList(),
)

@Serializable
internal data class HeroStatNamesDto(
    val attributeOrder: List<String> = emptyList(),
    val derivedOrder: List<String> = emptyList(),
    val attributes: List<HeroStatNameDto> = emptyList(),
    val derived: List<HeroDerivedNameDto> = emptyList(),
)

@Serializable
internal data class HeroStatNameDto(
    val key: String = "",
    val zh: String = "",
    val en: String = "",
)

@Serializable
internal data class HeroDerivedNameDto(
    val key: String = "",
    val zh: String = "",
    val en: String = "",
    val fromStat: String = "",
    val graphId: Int = 0,
    val inGameLabel: Boolean = true,
    val integer: Boolean = true,
)

@Serializable
internal data class HeroGrowthGraphDto(
    val id: Int = 0,
    val name: String = "",
    val stageMaxVal: List<Double> = emptyList(),
    val stageMaxGrowVal: List<Double> = emptyList(),
    val adjPt: List<Double> = emptyList(),
    val linear: Boolean? = null,
    val usedFor: List<String> = emptyList(),
)

@Serializable
internal data class HeroInterpolationDto(
    val baseAnchorLevels: List<Int> = emptyList(),
    val modifierAnchorLevels: List<Int> = emptyList(),
    val maxLevel: Int = 0,
    val baseRule: String = "",
    val baseRounding: String = "",
    val baseVerified: Boolean = false,
    val baseVerification: String = "",
    val derivedRule: String = "",
    val modifierRule: String = "",
    val modifierRounding: String = "",
    val modifierVerified: Boolean = false,
    val modifierVerifiedNote: String = "",
    val modifierAnchorVerified: Boolean = false,
    val modifierAnchorVerification: String = "",
    val modifierMidLevelsVerified: Boolean = false,
    val modifierInference: String = "",
    val libraRule: String = "",
)

@Serializable
internal data class HeroDto(
    val id: Int = 0,
    val key: String = "",
    val nameZh: String = "",
    val nameEn: String = "",
    val heroStatusParamId: Int = 0,
    val anchors: List<HeroAnchorRowDto> = emptyList(),
    val levels: List<HeroLevelRowDto> = emptyList(),
)

@Serializable
internal data class HeroAnchorRowDto(
    val level: Int = 0,
    val rowId: Int = 0,
    val rowName: String = "",
    val stats: Map<String, Double?> = emptyMap(),
)

@Serializable
internal data class HeroLevelRowDto(
    val level: Int = 0,
    val isAnchor: Boolean = false,
    val stats: Map<String, Double?> = emptyMap(),
    val derived: Map<String, Double?> = emptyMap(),
)

@Serializable
internal data class HeroStatModifierDto(
    val affixId: Int = 0,
    val nameZh: String = "",
    val nameEn: String = "",
    val heroId: Int = 0,
    val heroKey: String = "",
    val heroNameZh: String = "",
    val affectedStats: List<String> = emptyList(),
    val anchors: List<HeroModifierAnchorDto> = emptyList(),
    val levels: List<HeroModifierLevelDto> = emptyList(),
    val relicItems: List<HeroRelicItemDto> = emptyList(),
    val rollablePoolIds: List<Int> = emptyList(),
    val dlcOnly: Boolean = false,
)

@Serializable
internal data class HeroModifierAnchorDto(
    val level: Int = 0,
    val rowId: Int = 0,
    val rowName: String = "",
    val delta: Map<String, Double?> = emptyMap(),
)

@Serializable
internal data class HeroModifierLevelDto(
    val level: Int = 0,
    val isAnchor: Boolean = false,
    /** 缺失时按「非锚点即推算」补（macOS 同一条默认值）。 */
    val inferred: Boolean? = null,
    val delta: Map<String, Double?> = emptyMap(),
    val deltaFloorAlt: Map<String, Double?> = emptyMap(),
)

@Serializable
internal data class HeroRelicItemDto(
    val id: Int = 0,
    val nameZh: String = "",
    val nameEn: String = "",
    val color: Int = -1,
    val colorZh: String = "",
    val colorEn: String = "",
    val deep: Boolean = false,
)

@Serializable
internal data class HeroLibraRespecDto(
    val key: String = "",
    val nameZh: String = "",
    val nameEn: String = "",
    val effectNameZh: String = "",
    val effectInfoZh: String = "",
    val dealLineZh: String = "",
    val statKey: String = "",
    val statNameZh: String = "",
    val heroStatusId: Int = 0,
    val anchors: List<HeroAnchorRowDto> = emptyList(),
    val levels: List<HeroLevelRowDto> = emptyList(),
)

@Serializable
internal data class HeroCrossCheckDto(
    val heroKey: String = "",
    val heroNameZh: String = "",
    val cellsCompared: Int = 0,
    val mismatchCount: Int = 0,
    val mismatches: List<HeroCrossCheckMismatchDto> = emptyList(),
    val authoritative: String = "",
    val note: String = "",
)

@Serializable
internal data class HeroCrossCheckMismatchDto(
    val level: Int = 0,
    val field: String = "",
    val external: Int = 0,
    val ours: Int = 0,
)

@Serializable
internal data class HeroSourceDto(
    val name: String = "",
    val url: String = "",
    val revision: String = "",
    val license: String = "",
    val usage: String = "",
)
