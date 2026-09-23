package com.nightreign.relicchecker.gamedata.heroes

import com.nightreign.relicchecker.gamedata.GameDataFormatException
import com.nightreign.relicchecker.gamedata.GameDataJson
import com.nightreign.relicchecker.gamedata.GameDataKey

/**
 * 「角色属性」页的解析入口：`rememberGameData(GameDataKey.HEROES, HeroesParser.PARSER_ID, HeroesParser::parse)`。
 *
 * 在后台线程里把 JSON 直接解码成 DTO（只声明页面用到的字段），校验 schemaVersion，
 * 再转成不可变模型并建好索引（角色 / 词条 / 利普拉按 key 查找、等级行排序）。
 */
object HeroesParser {
    /** rememberGameData 的缓存键；DTO 结构变了就把版本号加一。 */
    const val PARSER_ID = "heroes.page.v1"

    fun parse(text: String): HeroStatsIndex {
        val dto = GameDataJson.decode<HeroesFileDto>(GameDataKey.HEROES, text)
        GameDataJson.requireVersion(GameDataKey.HEROES, dto.schemaVersion)
        val dataset = dto.toModel()
        if (dataset.heroes.isEmpty()) {
            throw GameDataFormatException("${GameDataKey.HEROES.fileName}：角色属性数据里没有任何角色记录")
        }
        return HeroStatsIndex(dataset)
    }

    private fun HeroesFileDto.toModel(): HeroDataset {
        val graphs = LinkedHashMap<Int, HeroGrowthGraph>()
        growthGraphs.orEmpty().forEach { (key, graph) ->
            val id = if (graph.id != 0) graph.id else key.toIntOrNull() ?: 0
            graphs[id] = HeroGrowthGraph(
                id = id,
                name = graph.name,
                stageMaxVal = graph.stageMaxVal,
                stageMaxGrowVal = graph.stageMaxGrowVal,
                adjPt = graph.adjPt,
                linear = graph.linear ?: (graph.adjPt.all { it == 1.0 } && graph.stageMaxVal.isNotEmpty()),
                usedFor = graph.usedFor,
            )
        }
        return HeroDataset(
            schemaVersion = schemaVersion ?: 0,
            datasetId = datasetId,
            gameVersion = gameVersion,
            dataVersion = dataVersion,
            generatedAt = generatedAt,
            statNames = HeroStatNames(
                attributeOrder = statNames.attributeOrder,
                derivedOrder = statNames.derivedOrder,
                attributes = statNames.attributes.map { HeroStatName(it.key, it.zh, it.en) },
                derived = statNames.derived.map {
                    HeroDerivedName(it.key, it.zh, it.en, it.fromStat, it.graphId, it.inGameLabel, it.integer)
                },
            ),
            growthGraphs = graphs,
            growthGraphsDeclared = growthGraphs != null,
            interpolation = interpolation.toModel(),
            caveats = caveats,
            counts = counts,
            heroes = heroes.map { it.toModel() },
            statModifiers = statModifiers.map { it.toModel() },
            libraRespecs = libraRespecs.map { it.toModel() },
            crossChecks = crossChecks.map { check ->
                HeroCrossCheck(
                    heroKey = check.heroKey,
                    heroNameZh = check.heroNameZh,
                    cellsCompared = check.cellsCompared,
                    mismatchCount = check.mismatchCount,
                    mismatches = check.mismatches.map { HeroCrossCheckMismatch(it.level, it.field, it.external, it.ours) },
                    authoritative = check.authoritative,
                    note = check.note,
                )
            },
            sources = sources.map { HeroSource(it.name, it.url, it.revision, it.license, it.usage) },
        )
    }

    private fun HeroInterpolationDto.toModel() = HeroInterpolation(
        baseAnchorLevels = baseAnchorLevels,
        modifierAnchorLevels = modifierAnchorLevels,
        maxLevel = maxLevel,
        baseRule = baseRule,
        baseRounding = baseRounding,
        baseVerified = baseVerified,
        baseVerification = baseVerification,
        derivedRule = derivedRule,
        modifierRule = modifierRule,
        modifierRounding = modifierRounding,
        modifierVerified = modifierVerified,
        modifierVerifiedNote = modifierVerifiedNote,
        modifierAnchorVerified = modifierAnchorVerified,
        modifierAnchorVerification = modifierAnchorVerification,
        modifierMidLevelsVerified = modifierMidLevelsVerified,
        modifierInference = modifierInference,
        libraRule = libraRule,
    )

    private fun HeroDto.toModel() = HeroEntry(
        id = id,
        key = key,
        nameZh = nameZh,
        nameEn = nameEn,
        heroStatusParamId = heroStatusParamId,
        anchors = anchors.map { it.toModel() },
        levels = levels.map { it.toModel() }.sortedBy { it.level },
    )

    private fun HeroAnchorRowDto.toModel() = HeroAnchorRow(level, rowId, rowName, stats.toIntMap())

    private fun HeroLevelRowDto.toModel() = HeroLevelRow(
        level = level,
        isAnchor = isAnchor,
        stats = stats.toIntMap(),
        derived = derived.toDoubleMap(),
    )

    private fun HeroStatModifierDto.toModel() = HeroStatModifier(
        affixId = affixId,
        nameZh = nameZh,
        nameEn = nameEn,
        heroId = heroId,
        heroKey = heroKey,
        heroNameZh = heroNameZh,
        affectedStats = affectedStats,
        anchors = anchors.map { HeroModifierAnchor(it.level, it.rowId, it.rowName, it.delta.toIntMap()) },
        levels = levels.map {
            HeroModifierLevel(
                level = it.level,
                isAnchor = it.isAnchor,
                inferred = it.inferred ?: !it.isAnchor,
                delta = it.delta.toIntMap(),
                deltaFloorAlt = it.deltaFloorAlt.toIntMap(),
            )
        }.sortedBy { it.level },
        relicItems = relicItems.map { HeroRelicItem(it.id, it.nameZh, it.nameEn, it.color, it.colorZh, it.colorEn, it.deep) },
        rollablePoolIds = rollablePoolIds,
        dlcOnly = dlcOnly,
    )

    private fun HeroLibraRespecDto.toModel() = HeroLibraRespec(
        key = key,
        nameZh = nameZh,
        nameEn = nameEn,
        effectNameZh = effectNameZh,
        effectInfoZh = effectInfoZh,
        dealLineZh = dealLineZh,
        statKey = statKey,
        statNameZh = statNameZh,
        heroStatusId = heroStatusId,
        anchors = anchors.map { it.toModel() },
        levels = levels.map { it.toModel() }.sortedBy { it.level },
    )

    /** 属性 / 增减量：值可能写成浮点，一律四舍五入取整；写成 null 的项视为「没有」。 */
    private fun Map<String, Double?>.toIntMap(): Map<String, Int> {
        val result = LinkedHashMap<String, Int>()
        for ((key, value) in this) {
            if (value != null && value.isFinite()) result[key] = HeroStatsMath.roundHalfAwayFromZero(value).toInt()
        }
        return result
    }

    private fun Map<String, Double?>.toDoubleMap(): Map<String, Double> {
        val result = LinkedHashMap<String, Double>()
        for ((key, value) in this) {
            if (value != null && value.isFinite()) result[key] = value
        }
        return result
    }
}
