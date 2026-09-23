package com.nightreign.relicchecker.gamedata.save

import com.nightreign.relicchecker.catalog.AffixCatalog
import com.nightreign.relicchecker.rules.foldedForSearch

// 解析结果 → 审计结果（移植 macOS 端 RelicCore/SaveAudit.swift）。
// 存档检查页、报告导出与存档对比共用 AuditedSave，构造只走 SaveAuditPipeline，保证三处口径一致。

/** 一件遗物 + 它的审计结论。 */
class AuditedRelic(
    val relic: SaveRelic,
    val info: RelicInfo?,
    val result: RelicAuditResult,
    /** 预先折叠好的搜索文本（遗物名、ID、种类、全部正负词条名与 ID），由审计管线在后台线程算好。 */
    val searchText: String = "",
) {
    val isDeep: Boolean get() = info?.deep == true
    val displayName: String get() = relicDisplayName(relic.itemId, info)
    val kindLabel: String get() = relicKindLabel(relic.itemId, info)

    /** 颜色文案；遗物表里查不到时写「颜色未知」（遗物卡、TXT、CSV 同一写法）。 */
    val colorText: String get() = info?.let { relicColorLabel(it.color) + "色" } ?: "颜色未知"

    val isInvalid: Boolean get() = result.status == RelicAuditStatus.INVALID

    /** 「非法 / 警告 / 合法」三态（页面与报告同一口径）。 */
    val statusLabel: String
        get() = when {
            isInvalid -> "非法"
            result.warnings.isEmpty() -> "合法"
            else -> "警告"
        }
}

/** 一个角色槽位。 */
class AuditedCharacter(
    val slot: Int,
    val name: String,
    val parseError: String?,
    val relics: List<AuditedRelic>,
) {
    /** 「槽位 N · 角色名」；读不出名字时写「未命名」。 */
    val displayName: String get() = "槽位 ${slot + 1} · ${name.ifEmpty { "未命名" }}"

    val invalidCount: Int = relics.count { it.isInvalid }
    val warningCount: Int = relics.count { !it.isInvalid && it.result.warnings.isNotEmpty() }
    val deepCount: Int = relics.count { it.isDeep }

    /** 空白 parseError 不算解析失败（与 Windows 端 parseErrorOf 一致）。 */
    val hasParseError: Boolean get() = !parseError.isNullOrBlank()
}

/** 一份存档的完整审计结果：解析结果 + 逐件审计 + 展示用的词条名与说明。 */
class AuditedSave(
    val fileName: String,
    val checksumOk: Boolean,
    /** effectId → 词条名（词条库 ∪ extraAffixes）。 */
    val affixNames: Map<Long, String>,
    /** effectId → 词条说明（只收录词条库里非空的 explanation）。 */
    val affixExplanations: Map<Long, String> = emptyMap(),
    val characters: List<AuditedCharacter>,
) {
    val relicCount: Int = characters.sumOf { it.relics.size }
    val invalidCount: Int = characters.sumOf { it.invalidCount }

    /** 「警告」件数；当前审计器不产出警告，恒为 0，报告据此省略该字段。 */
    val warningCount: Int = characters.sumOf { it.warningCount }

    fun affixName(id: Long): String = affixNames[id]?.takeIf { it.isNotEmpty() } ?: "未知词条 #$id"

    /** 词条说明；没有收录时为 null（页面据此不显示 ⓘ）。 */
    fun affixExplanation(id: Long): String? = affixExplanations[id]?.takeIf { it.isNotEmpty() }

    /** 「词条名（ID）」，报告与对比统一写法；空词条写「（空）」。 */
    fun affixLabel(id: Long): String {
        val normalized = normalizeEffectId(id)
        return if (normalized == -1L) "（空）" else "${affixName(normalized)}（$normalized）"
    }
}

object SaveAuditPipeline {
    /** effectId → 词条说明（只收录非空的 explanation）。 */
    fun explanations(catalog: AffixCatalog): Map<Long, String> =
        catalog.affixes.filter { it.explanation.isNotEmpty() }.associate { it.effectId.toLong() to it.explanation }

    /** 用词条库与遗物表审计一份已解析的存档（测试与一次性调用用；页面复用 [SaveAuditData]）。 */
    fun audit(parsed: SaveParseResult, catalog: AffixCatalog, relicData: RelicDataSet): AuditedSave =
        audit(parsed, RelicAuditContext(catalog, relicData), explanations(catalog))

    fun audit(parsed: SaveParseResult, data: SaveAuditData): AuditedSave =
        audit(parsed, data.context, data.explanations)

    /**
     * 复用已经建好的审计上下文（对比两份存档时避免重复建索引）。
     * [affixExplanations] 必填：漏传会让界面上的词条说明（ⓘ）静默消失。
     */
    fun audit(parsed: SaveParseResult, context: RelicAuditContext, affixExplanations: Map<Long, String>): AuditedSave {
        val auditor = RelicAuditor()
        val names = context.affixNames
        val characters = parsed.characters.map { character ->
            val results = auditor.applyUniqueDuplicates(
                character.relics.map { auditor.audit(it, context) },
                character.relics,
            )
            AuditedCharacter(
                slot = character.slot,
                name = character.name,
                parseError = character.parseError,
                relics = character.relics.mapIndexed { index, relic ->
                    val info = context.relicsById[relic.itemId]
                    AuditedRelic(relic, info, results[index], searchText(relic, info, names))
                },
            )
        }
        return AuditedSave(
            fileName = parsed.fileName,
            checksumOk = parsed.checksumOk,
            affixNames = names,
            affixExplanations = affixExplanations,
            characters = characters,
        )
    }

    /** 遗物卡搜索文本：名称、ID、种类、全部正负词条名与 ID（与桌面端一致），预先折叠。 */
    fun searchText(relic: SaveRelic, info: RelicInfo?, affixNames: Map<Long, String>): String {
        val parts = mutableListOf(relicDisplayName(relic.itemId, info), relic.itemId.toString(), relicKindLabel(relic.itemId, info))
        for (id in relic.effects + relic.curses) {
            if (id == -1L) continue
            parts += affixNames[id]?.takeIf { it.isNotEmpty() } ?: "未知词条 #$id"
            parts += id.toString()
        }
        return parts.joinToString(" ").foldedForSearch()
    }
}

/** 存档检查页的过滤（与桌面端「全部 / 仅非法 / 深夜遗物」一致）。 */
enum class SaveFilter(val title: String) {
    ALL("全部"),
    INVALID_ONLY("仅非法"),
    DEEP_ONLY("深夜遗物"),
    ;

    fun apply(relics: List<AuditedRelic>, query: String): List<AuditedRelic> {
        val needle = query.foldedForSearch()
        return relics.filter { relic ->
            val kept = when (this) {
                ALL -> true
                INVALID_ONLY -> relic.isInvalid
                DEEP_ONLY -> relic.isDeep
            }
            kept && (needle.isEmpty() || relic.searchText.contains(needle))
        }
    }

    /** 过滤后为空时的标题与说明（与桌面端同一套文案）。 */
    fun emptyTitle(): String = if (this == INVALID_ONLY) "🎉 未发现不合法遗物" else "没有符合条件的遗物"

    fun emptyDetail(character: AuditedCharacter): String = when {
        this == DEEP_ONLY -> "该角色没有持有深夜遗物。"
        character.relics.isEmpty() -> "该角色没有持有任何遗物。"
        else -> "当前过滤条件下没有可显示的遗物。"
    }
}
