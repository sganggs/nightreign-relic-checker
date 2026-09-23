package com.nightreign.relicchecker.gamedata.save

import com.nightreign.relicchecker.catalog.AffixCatalog
import com.nightreign.relicchecker.gamedata.GameDataJson
import com.nightreign.relicchecker.gamedata.GameDataKey
import kotlinx.serialization.Serializable

// 遗物物品表（nightreign-relics-v1.03.4.json）的存档检查专用解析。
//
// 词条反查车道也会解析同一个文件，但两边各写一份 DTO（并行车道不能互相依赖未合并的代码），
// 合并时再统一。这里只声明审计要用的字段：sources 之类的说明字段不声明，解码时跳过。

@Serializable
internal data class RelicsFileDto(
    val relicsSchemaVersion: Int? = null,
    val gameVersion: String = "",
    val dataVersion: String = "",
    val relics: List<RelicDto> = emptyList(),
    val pools: Map<String, List<Long>> = emptyMap(),
    val extraAffixes: List<ExtraAffixDto> = emptyList(),
)

@Serializable
internal data class RelicDto(
    val id: Int? = null,
    val name: String = "",
    val color: Int = -1,
    val deep: Boolean = false,
    val slots: List<Int> = emptyList(),
    val curseSlots: List<Int> = emptyList(),
)

@Serializable
internal data class ExtraAffixDto(
    val effectId: Long? = null,
    val name: String = "",
    val sortId: Int = 0,
    val compatibilityId: Int = -1,
)

/** 遗物表里的一件遗物。[slots] / [curseSlots] 恒为 3 位，缺失补 -1（与 Windows 端的防御一致）。 */
data class RelicInfo(
    val id: Int,
    val name: String,
    val color: Int,
    val deep: Boolean,
    val slots: List<Int>,
    val curseSlots: List<Int>,
)

/** 词条库之外的补充词条（AttachEffectParam 全量补充）。 */
data class ExtraAffix(
    val effectId: Long,
    val name: String,
    val sortId: Int,
    val compatibilityId: Int,
)

/** 解析好的遗物表：遗物、槽池（effectId 集合）与补充词条。 */
class RelicDataSet(
    val gameVersion: String,
    val dataVersion: String,
    val relics: List<RelicInfo>,
    val pools: Map<Int, Set<Long>>,
    val extraAffixes: List<ExtraAffix>,
) {
    /** 同一 ID 出现多次时取第一条（与桌面端 uniquingKeysWith first 一致）。 */
    val relicsById: Map<Int, RelicInfo> = LinkedHashMap<Int, RelicInfo>().also { map ->
        relics.forEach { map.putIfAbsent(it.id, it) }
    }

    companion object {
        fun parse(text: String): RelicDataSet {
            val dto = GameDataJson.decode<RelicsFileDto>(GameDataKey.RELICS, text)
            GameDataJson.requireVersion(GameDataKey.RELICS, dto.relicsSchemaVersion)
            return RelicDataSet(
                gameVersion = dto.gameVersion,
                dataVersion = dto.dataVersion,
                relics = dto.relics.mapNotNull { relic ->
                    val id = relic.id ?: return@mapNotNull null
                    RelicInfo(
                        id = id,
                        name = relic.name,
                        color = relic.color,
                        deep = relic.deep,
                        slots = relic.slots.triple(),
                        curseSlots = relic.curseSlots.triple(),
                    )
                },
                pools = dto.pools.entries.mapNotNull { (key, members) ->
                    key.toIntOrNull()?.let { it to members.toHashSet() as Set<Long> }
                }.toMap(),
                extraAffixes = dto.extraAffixes.mapNotNull { extra ->
                    val effectId = extra.effectId ?: return@mapNotNull null
                    ExtraAffix(effectId, extra.name, extra.sortId, extra.compatibilityId)
                },
            )
        }

        private fun List<Int>.triple(): List<Int> = List(3) { getOrNull(it) ?: -1 }
    }
}

/**
 * 存档检查页用的全部静态数据：遗物表 + 审计上下文 + 词条说明。
 *
 * 在 `rememberGameData` 的后台线程里一次建好（索引约两千词条、六百个槽池），
 * 页面与「对比另一份存档」共用同一份，不再每份存档重复建索引。
 */
class SaveAuditData(
    val relicData: RelicDataSet,
    val context: RelicAuditContext,
    /** effectId → 词条说明（只收录词条库里非空的 explanation）。 */
    val explanations: Map<Long, String>,
) {
    companion object {
        /** rememberGameData 的解析器标识：返回类型为 [SaveAuditData]。 */
        const val PARSER_ID = "save.audit.v1"

        fun build(text: String, catalog: AffixCatalog): SaveAuditData = build(RelicDataSet.parse(text), catalog)

        fun build(relicData: RelicDataSet, catalog: AffixCatalog): SaveAuditData = SaveAuditData(
            relicData = relicData,
            context = RelicAuditContext(catalog, relicData),
            explanations = SaveAuditPipeline.explanations(catalog),
        )
    }
}
