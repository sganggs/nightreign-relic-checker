package com.nightreign.relicchecker.gamedata.bosses

import com.nightreign.relicchecker.gamedata.GameDataJson
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject

/**
 * 宽容回退：流式解码（[BossesParser.decodeFile] 的快路径）失败时才走这里；随 APK 打包的
 * 数据集永远走快路径，这里不多花一毫秒。
 *
 * 与 macOS `BossFailable` / `bossArray` / `bossDictionary` / `bossValue(default:)` 同口径——
 * 坏的东西只丢它自己，不连累整份数据：
 * - 数组（nightlords、nightBosses、fights、variants、roleEvidence 的出处列表、weakness、immune……）
 *   里解不出来的元素丢掉，其余照常；
 * - 字典（scalingTiers、permanentScaling、roleEvidence、depthStats……）里解不出来的项丢掉；
 * - 对象里类型不对的字段丢掉，退回 DTO 默认值（默认值与 macOS 的 `bossXxx(default:)` 逐项一致）。
 *
 * 做法：先看整块能不能解；不能就逐个子项试（子项单独放回原位置、其余字段取默认值），
 * 能解的留下、解不了的往下一层继续拆，拆到叶子还不行就丢掉。只在失败的那条路径上往下拆，
 * 能解的兄弟节点原样保留。
 *
 * 只有这里会把整份文本建成 JSON 树（PAGES.md §7 不许在正常路径上这么做）；数据坏了才付这个代价。
 *
 * 与 macOS 仍有的差别：macOS 的 `bossString` 会把数字读成字符串、`bossBool` 会把 0 / 1 读成布尔，
 * 这里这类「能凑合读」的值按类型不符丢掉、退回默认值。
 */
internal object BossesTolerant {
    private val json get() = GameDataJson.lenient

    /** 按上面的规则清洗后解码；连 JSON 语法都不对、或顶层不是对象时返回 null（调用方报快路径的原始错误）。 */
    fun decode(text: String): BossesFileDto? {
        val root = try {
            json.parseToJsonElement(text)
        } catch (_: IllegalArgumentException) {
            return null
        }
        if (root !is JsonObject) return null
        val fitsFile = { element: JsonElement -> decodes(element) }
        val cleaned = salvage(root, fitsFile) ?: return null
        return try {
            json.decodeFromJsonElement(BossesFileDto.serializer(), cleaned)
        } catch (_: IllegalArgumentException) {
            null
        }
    }

    /**
     * 让 [value] 在它的位置上解得出来：[fits] 判断「把这个值放回原位置、其余一律取默认值」能否解码。
     * 本身能解就原样返回；对象逐项（字段 / 字典项）、数组逐元素往下拆，留下能解的；救不回来返回 null。
     */
    private fun salvage(value: JsonElement, fits: (JsonElement) -> Boolean): JsonElement? {
        if (fits(value)) return value
        val repaired = when (value) {
            is JsonObject -> {
                val kept = LinkedHashMap<String, JsonElement>(value.size)
                value.forEach { (key, child) ->
                    salvage(child) { fits(JsonObject(mapOf(key to it))) }?.let { kept[key] = it }
                }
                JsonObject(kept)
            }
            is JsonArray -> JsonArray(value.mapNotNull { child -> salvage(child) { fits(JsonArray(listOf(it))) } })
            else -> return null
        }
        return repaired.takeIf(fits)
    }

    private fun decodes(file: JsonElement): Boolean =
        try {
            json.decodeFromJsonElement(BossesFileDto.serializer(), file)
            true
        } catch (_: IllegalArgumentException) {
            false // SerializationException 与数字解析失败都是 IllegalArgumentException 的子类
        }
}
