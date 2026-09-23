package com.nightreign.relicchecker.gamedata

import kotlinx.serialization.SerializationException
import kotlinx.serialization.json.Json

/**
 * 各数据页共用的 JSON 配置。
 *
 * - `ignoreUnknownKeys`：DTO 只声明页面真正用到的字段，其余（`diagnostics`、`schemaChangelog`、
 *   `notes` 之类）在解码时直接跳过，不建对象；
 * - `coerceInputValues`：字段为 `null` 或枚举值未知时回落到 DTO 的默认值，而不是整份失败；
 * - `isLenient = false`：数据集是生成脚本产出的严格 JSON，不接受宽松语法。
 */
object GameDataJson {
    val lenient: Json = Json {
        ignoreUnknownKeys = true
        isLenient = false
        coerceInputValues = true
    }

    /** 按 [lenient] 解码，并把序列化异常包成带文件名的 [GameDataFormatException]。 */
    inline fun <reified T> decode(key: GameDataKey, text: String): T =
        try {
            lenient.decodeFromString<T>(text)
        } catch (error: SerializationException) {
            throw GameDataFormatException("无法解析 ${key.fileName}：${error.message}", error)
        }

    /** 校验顶层版本键；不一致时抛出，页面会显示失败原因而不是按错误口径展示数据。 */
    fun requireVersion(key: GameDataKey, actual: Int?) {
        if (actual != key.expectedVersion) {
            throw GameDataFormatException(
                "${key.fileName} 的 ${key.versionField} 为 ${actual ?: "缺失"}，" +
                    "本应用只支持 ${key.expectedVersion}",
            )
        }
    }
}

class GameDataFormatException(message: String, cause: Throwable? = null) :
    IllegalArgumentException(message, cause)
