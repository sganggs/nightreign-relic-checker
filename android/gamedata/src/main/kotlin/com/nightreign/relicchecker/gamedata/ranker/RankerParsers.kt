package com.nightreign.relicchecker.gamedata.ranker

import com.nightreign.relicchecker.gamedata.GameDataJson
import com.nightreign.relicchecker.gamedata.GameDataKey

/**
 * 「增伤排名」两份数据集的解析入口（给 `rememberGameData` 用，在 IO 线程执行）：
 *
 * ```kotlin
 * val skills = rememberGameData(GameDataKey.SKILLS, RankerParsers.SKILLS_ID, RankerParsers::skills)
 * val buffs = rememberGameData(GameDataKey.BUFFS, RankerParsers.BUFFS_ID, RankerParsers::buffs)
 * GameDataScreenScaffold(..., state = skills.zip(buffs)) { (skillIndex, buffIndex) -> ... }
 * ```
 *
 * 解码后直接建好索引（按 id 查表、输出手段列表、每条 buff 的九类倍率表），页面只做与交互相关的加权。
 * DTO 结构变了就把 parserId 的版本号加一（进程级缓存按 parserId 取回后直接转型）。
 */
object RankerParsers {
    const val SKILLS_ID: String = "ranker.skills.v1"
    const val BUFFS_ID: String = "ranker.buffs.v1"

    /** skills 数据集 → [SkillDataIndex]（版本不符或读不出任何输出手段时抛 GameDataFormatException）。 */
    fun skills(text: String): SkillDataIndex {
        val dataset = GameDataJson.decode<SkillDataset>(GameDataKey.SKILLS, text)
        GameDataJson.requireVersion(GameDataKey.SKILLS, dataset.schemaVersion)
        return SkillDataIndex(dataset)
    }

    /** buffs 数据集 → [BuffRankerIndex]（跳过 diagnostics / schemaChangelog 等说明块）。 */
    fun buffs(text: String): BuffRankerIndex {
        val dto = GameDataJson.decode<BuffsFileDto>(GameDataKey.BUFFS, text)
        GameDataJson.requireVersion(GameDataKey.BUFFS, dto.schemaVersion)
        return BuffRankerIndex(BuffDataset.from(dto))
    }
}
