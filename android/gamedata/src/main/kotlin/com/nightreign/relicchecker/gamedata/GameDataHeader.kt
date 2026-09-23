package com.nightreign.relicchecker.gamedata

import kotlinx.serialization.Serializable

/**
 * 各数据集共有的顶层元数据（版本键 + 游戏版本 + 数据版本 + 生成时间）。
 *
 * 页面自己的根 DTO 通常会顺带声明这些字段；本类用于只想展示数据集来源、
 * 或校验 asset 是否可读的场合（占位页就用它）。解码时其余字段全部跳过。
 */
@Serializable
data class GameDataHeader(
    val schemaVersion: Int? = null,
    val bossesSchemaVersion: Int? = null,
    val relicsSchemaVersion: Int? = null,
    val gameVersion: String = "",
    val dataVersion: String = "",
    val generatedAt: String = "",
) {
    /** 按 [GameDataKey.versionField] 取该文件的版本号。 */
    fun versionOf(key: GameDataKey): Int? = when (key.versionField) {
        "bossesSchemaVersion" -> bossesSchemaVersion
        "relicsSchemaVersion" -> relicsSchemaVersion
        else -> schemaVersion
    }

    companion object {
        /** rememberGameData 用的解析器标识（所有页面共用同一份缓存）。 */
        const val PARSER_ID = "common.header.v1"

        fun parse(key: GameDataKey, text: String): GameDataHeader {
            val header = GameDataJson.decode<GameDataHeader>(key, text)
            GameDataJson.requireVersion(key, header.versionOf(key))
            return header
        }
    }
}
