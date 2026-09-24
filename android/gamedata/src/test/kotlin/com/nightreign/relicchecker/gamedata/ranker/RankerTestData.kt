package com.nightreign.relicchecker.gamedata.ranker

import com.nightreign.relicchecker.catalog.AffixCatalog
import com.nightreign.relicchecker.catalog.CatalogLoader
import com.nightreign.relicchecker.gamedata.GameDataKey
import kotlin.test.assertNotNull
import kotlin.test.assertTrue

/** 测试共用：从 test resources（指向仓库根 data/）读真实数据集，解析一次、各测试类共用。 */
internal object RankerTestData {
    fun readText(name: String): String {
        val stream = assertNotNull(javaClass.classLoader.getResourceAsStream(name), "test resources 里缺少 $name")
        return stream.bufferedReader(Charsets.UTF_8).use { it.readText() }
    }

    val skillsText: String by lazy { readText(GameDataKey.SKILLS.fileName) }
    val buffsText: String by lazy { readText(GameDataKey.BUFFS.fileName) }

    var skillsParseMillis: Long = -1
        private set
    var buffsParseMillis: Long = -1
        private set

    val skills: SkillDataIndex by lazy {
        val started = System.nanoTime()
        val index = RankerParsers.skills(skillsText)
        skillsParseMillis = (System.nanoTime() - started) / 1_000_000
        index
    }

    val buffs: BuffRankerIndex by lazy {
        val started = System.nanoTime()
        val index = RankerParsers.buffs(buffsText)
        buffsParseMillis = (System.nanoTime() - started) / 1_000_000
        index
    }

    val plan: RateFieldPlan get() = buffs.plan

    /** 词条库（与 :app 启动时加载的是同一份 data/nightreign-affixes-v1.03.4.json）。 */
    val catalog: AffixCatalog by lazy { CatalogLoader.parse(readText(CatalogLoader.ASSET_FILE_NAME)) }

    /** 配置页索引（真实增益数据 + 词条库）。 */
    val loadout: LoadoutIndex by lazy { LoadoutIndex(buffs, catalog.affixes) }

    /**
     * 真实数据的输出手段（Windows ranker_config.test.mjs 的 outputFor）：选段后去掉 noDamage，只留正常版这一侧
     * （hit.fpBoth || noFp 与开关同侧，开关默认关），按构成建输出（默认右手、不勾攻击情境）。
     */
    fun output(
        outputClass: OutputClass,
        id: Int,
        weaponId: Int? = null,
        hand: Int = 1,
        contexts: Set<String> = emptySet(),
    ): RankerOutput {
        val composed = RankerCrossCheck.compose(skills, RankerCrossCheck.CompositionCase("test", outputClass, id, weaponId))
        return composed.output.copy(hand = hand, attackContexts = contexts)
    }

    /** 按类型写的占比表（没写的为 0）。 */
    fun shares(vararg pairs: Pair<DamageType, Double>): List<Double> {
        val values = DoubleArray(DamageType.COUNT)
        for ((type, share) in pairs) values[type.ordinal] = share
        return values.toList()
    }

    /** 当前输出（默认：战技、右手、纯斩击构成、不勾攻击情境）。 */
    fun out(
        outputClass: OutputClass = OutputClass.SKILL,
        meansId: Int? = null,
        weapon: SkillWeapon? = null,
        hand: Int = 1,
        shares: List<Double> = shares(DamageType.SLASH to 1.0),
        contexts: Set<String> = emptySet(),
    ): RankerOutput = RankerOutput(
        outputClass = outputClass,
        meansId = meansId,
        weaponId = weapon?.id,
        weaponWepType = weapon?.wepType,
        hand = hand,
        shares = shares,
        attackContexts = contexts,
    )

    /** 合成一条 buff（默认：物理 ×1.2、对三类输出都 yes、被动、stackSelf、按 ID 互斥）；与 Windows 测试的 synth 同形。 */
    fun synthBuff(id: Int, transform: (BuffEntry) -> BuffEntry = { it }): BuffEntry = transform(
        BuffEntry(
            spEffectId = id,
            rates = mapOf("physicsAttackRate" to 1.2),
            target = "self",
            activation = "passive",
            direction = "increase",
            appliesTo = BuffAppliesTo(skill = "yes", sorcery = "yes", incantation = "yes"),
            stacking = BuffStacking(spCategory = 10, spCategoryBehavior = "stackSelf", exclusiveKey = "sp10#$id"),
        ),
    )

    fun synth(id: Int, transform: (BuffEntry) -> BuffEntry = { it }): BuffRankerEntry =
        BuffRankerIndex.indexEntry(synthBuff(id, transform), plan)

    /** 用真实数据集的枚举表、换一组 buffs / attackIndex 建一个小索引（合成用例用）。 */
    fun miniIndex(
        buffs: List<BuffEntry>,
        attackIndex: BuffAttackIndex = RankerTestData.buffs.dataset.attackIndex,
        weaponAffixes: List<BuffWeaponAffixInfo> = emptyList(),
        fixedRelics: List<BuffFixedRelic> = emptyList(),
    ): BuffRankerIndex {
        val real = RankerTestData.buffs.dataset
        return BuffRankerIndex(
            BuffDataset(
                schemaVersion = 6, gameVersion = real.gameVersion, dataVersion = real.dataVersion,
                generatedAt = real.generatedAt, notes = emptyMap(), userQuestions = emptyList(),
                stackingRulesZh = "", rateFields = real.rateFields, rateFieldGroups = real.rateFieldGroups,
                enums = real.enums, counts = BuffCounts(), slotRules = real.slotRules,
                weaponAffixes = weaponAffixes, fixedRelics = fixedRelics, attackIndex = attackIndex, buffs = buffs,
            ),
        )
    }

    fun assertClose(expected: Double, actual: Double?, tolerance: Double = 1e-9, message: String = "") {
        assertNotNull(actual, "$message：值为 null")
        assertTrue(Math.abs(expected - actual) <= tolerance, "$message（期望 $expected，实际 $actual）")
    }
}
