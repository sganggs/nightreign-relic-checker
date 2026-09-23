package com.nightreign.relicchecker.gamedata.bosses

import com.nightreign.relicchecker.gamedata.GameDataFormatException
import com.nightreign.relicchecker.gamedata.GameDataJson
import com.nightreign.relicchecker.gamedata.GameDataKey
import kotlinx.serialization.SerializationException

/**
 * 首领数据页的解析入口：`rememberGameData(GameDataKey.BOSSES, BossesParser.PARSER_ID, BossesParser::parse)`。
 *
 * 直接解码到 DTO（只声明页面用得到的字段），再一次性转换成不可变的领域模型并建好
 * 卡片、分组与搜索索引；全部在调用方的后台线程里完成。
 */
object BossesParser {
    const val PARSER_ID = "bosses.page.v1"

    fun parse(text: String): BossDataIndex {
        val dto = decodeFile(text)
        GameDataJson.requireVersion(GameDataKey.BOSSES, dto.bossesSchemaVersion)
        return BossDataIndex(dataset(dto))
    }

    /** 不校验版本号的解码（测试里用构造出来的小 JSON 验证宽容解码与分组规则）。 */
    fun parseUnchecked(text: String): BossDataIndex = BossDataIndex(dataset(decodeFile(text)))

    /**
     * 快路径：流式解码到 DTO（不建 JSON 树）。只有它失败时才走 [BossesTolerant] 的逐元素回退
     * （与 macOS `BossFailable` 同口径，坏元素只丢它自己）；回退也救不回来（JSON 语法错、
     * 顶层不是对象）时报快路径的原始错误，带上文件名。
     */
    internal fun decodeFile(text: String): BossesFileDto =
        try {
            GameDataJson.lenient.decodeFromString(BossesFileDto.serializer(), text)
        } catch (strict: SerializationException) {
            BossesTolerant.decode(text)
                ?: throw GameDataFormatException("无法解析 ${GameDataKey.BOSSES.fileName}：${strict.message}", strict)
        }

    /** 单独解码一条数值行（测试里构造边界数据用）。 */
    fun parseFight(text: String): BossFight = fight(GameDataJson.decode<BossFightDto>(GameDataKey.BOSSES, text))

    internal fun dataset(dto: BossesFileDto): BossDataset = BossDataset(
        schemaVersion = dto.bossesSchemaVersion ?: 0,
        gameVersion = dto.gameVersion,
        dataVersion = dto.dataVersion,
        generatedAt = dto.generatedAt,
        sources = dto.sources.map { BossSource(it.name, it.url, it.revision, it.license, it.usage) },
        affinityNames = dto.affinityNames.mapKeysToInt().mapValues { (_, name) -> name.zh to name.en },
        scalingTiers = dto.scalingTiers.mapKeysToInt().mapValues { (id, group) ->
            BossScalingGroup(id, group.group?.takeIf { it.isNotEmpty() }, group.duo?.let(::tier), group.trio?.let(::tier))
        },
        permanentScaling = dto.permanentScaling.mapKeysToInt().mapValues { (id, effect) ->
            BossPermanentEffect(
                id = id,
                nameEn = effect.nameEn?.takeIf { it.isNotEmpty() },
                nameZh = effect.nameZh,
                hp = effect.hp,
                poiseTaken = effect.poiseTaken,
                poiseRecover = effect.poiseRecover,
                ailmentDamageRate = effect.ailmentDamageRate,
                attackRate = effect.attackRate,
                attackRates = attackRates(effect.attackRates),
                staminaAttackRate = effect.staminaAttackRate,
                deepOfNight = effect.deepOfNight,
            )
        },
        caveats = dto.caveats,
        nightlords = dto.nightlords.map(::nightlord),
        nightBosses = dto.nightBosses.map(::nightBoss),
        notes = dto.notes?.let { notes ->
            BossNotes(
                unmatchedNames = notes.unmatchedNames.map { BossUnmatchedName(it.nameEn, it.chrId.roundHalfAway()) },
                nameCollisionCount = notes.nameCollisions.size,
                multiplayerScalingAudit = notes.multiplayerScalingAudit,
                deepOfNightAudit = notes.deepOfNightAudit,
                roleAuditSummary = notes.roleAudit?.summary.orEmpty(),
            )
        },
        deepOfNightText = deepOfNightText(dto.deepOfNightText),
        deepOfNightDepths = dto.deepOfNightDepths.mapKeysToInt().mapValues { (_, info) ->
            BossDepthInfo(
                rankId = info.rankId.roundHalfAway(),
                paramdexName = info.paramdexName?.takeIf { it.isNotEmpty() },
                labelZh = info.labelZh,
                labelEn = info.labelEn,
                cursedUncommonRate = info.cursedUncommonRate,
                cursedRareRate = info.cursedRareRate,
                mapChallengeWeight = info.mapChallengeWeight?.let {
                    BossMapChallengeWeight(it.map, it.nightlord, it.none)
                } ?: BossMapChallengeWeight(),
                cataclysmWeight = info.cataclysmWeight.intMap(),
            )
        },
        deepOfNightTiers = dto.deepOfNightTiers.mapKeysToInt().mapValues { (id, tier) ->
            BossDepthTier(
                id = id,
                group = tier.group?.takeIf { it.isNotEmpty() },
                tier = tier.tier?.takeIf { it.isNotEmpty() },
                depths = tier.depths.mapKeysToInt().mapValues { (_, stats) ->
                    BossDepthTierStats(
                        spEffectId = stats.spEffectId?.roundHalfAway(),
                        nameEn = stats.nameEn?.takeIf { it.isNotEmpty() },
                        hp = stats.hp,
                        attackRate = stats.attackRate,
                        poiseTaken = stats.poiseTaken,
                        staminaAttackRate = stats.staminaAttackRate,
                    )
                },
            )
        },
        mutations = dto.mutations.mapKeysToInt().mapValues { (id, mutation) ->
            BossMutation(
                id = id,
                nameZh = mutation.nameZh,
                nameEn = mutation.nameEn,
                setNameEn = mutation.setNameEn?.takeIf { it.isNotEmpty() },
                vfxSpEffectIds = mutation.vfxSpEffectIds.ints(),
                vfxTier = mutation.vfxTier?.roundHalfAway(),
                statSpEffectId = mutation.statSpEffectId?.roundHalfAway(),
                statNameEn = mutation.statNameEn?.takeIf { it.isNotEmpty() },
                hp = mutation.hp,
                attackRate = mutation.attackRate,
                runeRate = mutation.runeRate,
            )
        },
        mutationCategories = dto.mutationCategories.map {
            BossMutationCategory(
                rowId = it.rowId.roundHalfAway(),
                categoryId = it.categoryId.roundHalfAway(),
                categoryZh = it.categoryZh,
                categoryEn = it.categoryEn,
                mapId = it.mapId.roundHalfAway(),
                mapZh = it.mapZh,
                mapEn = it.mapEn,
                mutatedCount = it.mutatedCount.intMap(),
            )
        },
        roleNames = dto.roleNames.mapValues { (_, name) -> BossRoleName(name.zh, name.en, name.description) },
        roleSummary = dto.roleSummary.mapValues { (_, value) -> value.roundHalfAway() },
        roleSummaryDetail = dto.roleSummaryDetail.mapValues { (_, detail) ->
            BossRoleSummaryDetail(
                groups = detail.groups.roundHalfAway(),
                variants = detail.variants.roundHalfAway(),
                rows = detail.rows.roundHalfAway(),
                nightlords = detail.nightlords.roundHalfAway(),
                fights = detail.fights.roundHalfAway(),
                fightRows = detail.fightRows.roundHalfAway(),
            )
        },
        placementMaps = dto.placementMaps.mapValues { (_, map) ->
            BossPlacementMap(map.paramdexName?.takeIf { it.isNotEmpty() }, map.tileVariant?.zh.orEmpty())
        },
    )

    private fun nightlord(dto: BossNightlordDto): BossNightlord {
        val fights = dto.fights.map(::fight)
        return BossNightlord(
            menuId = dto.menuId.roundHalfAway(),
            paramdexName = dto.paramdexName,
            nameZh = dto.nameZh,
            nameEn = dto.nameEn,
            expeditionZh = dto.expeditionZh,
            expeditionEn = dto.expeditionEn,
            everdark = dto.everdark,
            variantKey = dto.variantKey,
            variantNameZh = dto.variantNameZh,
            variantNameEn = dto.variantNameEn,
            sortId = dto.sortId.roundHalfAway(),
            weakness = dto.weakness.map { BossWeakness(it.code.roundHalfAway(), it.zh, it.en) },
            descriptionZh = dto.descriptionZh,
            fights = fights,
            depthChanceWeights = dto.depthChanceWeights.intMap(),
            roles = BossRoleCatalog.groupRoles(dto.roles, fights),
        )
    }

    private fun nightBoss(dto: BossNightBossDto): BossNightBoss {
        val chrIds = dto.chrIds.ints()
        val variants = dto.variants.map(::fight)
        val id = when {
            dto.id.isNotEmpty() -> dto.id
            chrIds.isNotEmpty() -> "${dto.nameEn}@${chrIds.first()}"
            else -> dto.nameEn
        }
        return BossNightBoss(
            id = id,
            nameEn = dto.nameEn,
            nameZh = dto.nameZh,
            nameSource = dto.nameSource,
            nameInferred = dto.nameInferred,
            npcNameId = dto.npcNameId?.roundHalfAway(),
            chrIds = chrIds,
            tier = dto.tier,
            tiers = dto.tiers,
            variants = variants,
            roles = BossRoleCatalog.groupRoles(dto.roles, variants),
            nameApprox = dto.nameApprox,
            nameEvidence = dto.nameEvidence?.let(::nameEvidence),
            nameNote = dto.nameNote,
            nameSourceUrl = dto.nameSourceUrl,
            nameZhFallback = dto.nameZhFallback,
            nameZhFallbackNote = dto.nameZhFallbackNote,
            displayFallbackZh = dto.displayFallbackZh,
            nameZhRejected = dto.nameZhRejected?.let(::nameEvidence),
            hidden = dto.hidden,
            noReward = dto.noReward,
        )
    }

    private fun nameEvidence(dto: BossNameEvidenceDto) = BossNameEvidence(dto.fmg, dto.id, dto.en, dto.zh, dto.reason)

    internal fun fight(dto: BossFightDto): BossFight {
        val npcId = dto.npcId.roundHalfAway()
        val ids = dto.npcIds.ints()
        return BossFight(
            npcId = npcId,
            npcIds = ids.ifEmpty { listOf(npcId) },
            paramdexName = dto.paramdexName?.takeIf { it.isNotEmpty() },
            labelZh = dto.labelZh,
            labelEn = dto.labelEn,
            labelUncertain = dto.labelUncertain,
            isMain = dto.isMain,
            threat = dto.threat?.takeIf { it.isNotEmpty() },
            hp = dto.hp.roundHalfAway(),
            hpBase = dto.hpBase.roundHalfAway(),
            hpMultiplier = dto.hpMultiplier,
            poise = dto.poise,
            poiseRecover = dto.poiseRecover,
            poiseTakenBase = dto.poiseTakenBase,
            poiseRecoverMultiplier = dto.poiseRecoverMultiplier,
            damageRates = dto.damageRates?.let {
                BossDamageRates(it.standard, it.slash, it.strike, it.pierce, it.magic, it.fire, it.lightning, it.holy)
            } ?: BossDamageRates.NEUTRAL,
            ailmentDamageRateBase = dto.ailmentDamageRateBase,
            resist = dto.resist?.let {
                BossResistances(
                    it.poison.roundHalfAway(), it.rot.roundHalfAway(), it.bleed.roundHalfAway(),
                    it.frost.roundHalfAway(), it.sleep.roundHalfAway(), it.madness.roundHalfAway(),
                    it.death.roundHalfAway(),
                )
            } ?: BossResistances(),
            immune = dto.immune,
            permScalingIds = dto.permScalingIds.ints(),
            deepOfNight = dto.deepOfNight?.let {
                BossDeepOfNightStats(
                    hp = it.hp.roundHalfAway(),
                    hpMultiplier = it.hpMultiplier,
                    poiseTakenBase = it.poiseTakenBase,
                    poiseRecoverMultiplier = it.poiseRecoverMultiplier,
                    ailmentDamageRateBase = it.ailmentDamageRateBase,
                    attackRateBase = it.attackRateBase,
                    permScalingIds = it.permScalingIds.ints(),
                )
            },
            scalingId = dto.scalingId?.roundHalfAway(),
            scaling = dto.scaling?.let { BossScalingPair(it.duo?.let(::tier), it.trio?.let(::tier)) },
            attackRateBase = dto.attackRateBase,
            chaosCorrectId = dto.chaosCorrectId?.roundHalfAway(),
            depthStats = dto.depthStats.orEmpty().mapKeysToInt().mapValues { (_, stats) ->
                BossDepthStats(
                    hp = stats.hp.roundHalfAway(),
                    hpMultiplier = stats.hpMultiplier,
                    poiseTakenBase = stats.poiseTakenBase,
                    attackRateBase = stats.attackRateBase,
                )
            },
            mutationPool = dto.mutationPool.ints(),
            noReward = dto.noReward,
            roles = BossRoleCatalog.normalized(dto.roles),
            roleEvidence = dto.roleEvidence.mapValues { (_, list) ->
                list.map {
                    BossRoleEvidence(
                        npcId = it.npcId?.roundHalfAway(),
                        msb = it.msb?.takeIf { msb -> msb.isNotEmpty() },
                        part = it.part,
                        table = it.table,
                        row = it.row,
                        note = it.note,
                    )
                }
            },
            rowRoles = dto.rowRoles.mapKeysToInt().mapValues { (_, roles) -> BossRoleCatalog.normalized(roles) },
        )
    }

    private fun tier(dto: BossScalingTierDto) = BossScalingTier(
        hp = dto.hp,
        poiseTaken = dto.poiseTaken,
        poiseRecover = dto.poiseRecover,
        ailmentDamageRate = dto.ailmentDamageRate,
        poisonRate = dto.poisonRate,
        buildupRate = dto.buildupRate,
        attackRate = dto.attackRate,
        staminaAttackRate = dto.staminaAttackRate,
    )

    private fun attackRates(dto: BossAttackRatesDto?): BossAttackRates =
        dto?.let { BossAttackRates(it.physical, it.magic, it.fire, it.lightning, it.holy) } ?: BossAttackRates.NEUTRAL

    private fun gameText(dto: BossGameTextDto?, fallback: BossGameText): BossGameText =
        dto?.let { BossGameText(it.zh, it.en, it.textId?.roundHalfAway()) } ?: fallback

    private fun deepOfNightText(dto: BossDeepOfNightTextDto?): BossDeepOfNightText {
        val fallback = BossDeepOfNightText.FALLBACK
        if (dto == null) return fallback
        return BossDeepOfNightText(
            deepOfNight = gameText(dto.deepOfNight, fallback.deepOfNight),
            depth = gameText(dto.depth, fallback.depth),
            mutation = gameText(dto.mutation, fallback.mutation),
            mutationCount = gameText(dto.mutationCount, BossGameText.EMPTY),
            description = gameText(dto.description, BossGameText.EMPTY),
        )
    }

    /** 键是数字字符串的字典，转成 Int 键；转不了的键丢掉（与 macOS 的 bossNumberKeyedDictionary 一致）。 */
    private fun <V> Map<String, V>.mapKeysToInt(): Map<Int, V> {
        val out = LinkedHashMap<Int, V>(size)
        forEach { (key, value) -> key.trim().toIntOrNull()?.let { out[it] = value } }
        return out
    }

    private fun Map<String, Double>.intMap(): Map<Int, Int> = mapKeysToInt().mapValues { (_, value) -> value.roundHalfAway() }

    private fun List<Double>.ints(): List<Int> = map { it.roundHalfAway() }
}
