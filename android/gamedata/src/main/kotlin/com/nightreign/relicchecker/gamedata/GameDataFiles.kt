package com.nightreign.relicchecker.gamedata

/**
 * 仓库根 `data/` 下各数据集的文件名，与磁盘上的文件逐字一致。
 *
 * `:app` 把 `data/` 整个目录作为 assets 打进 APK，`:gamedata` 的测试把它作为 test resources，
 * 两边都按这里的名字读取。数据集升级（改名）时只改这一处，并同步 [GameDataKey] 的版本期望。
 * 词条库 `nightreign-affixes-v1.03.4.json` 由 `:catalog` 的 `CatalogLoader.ASSET_FILE_NAME` 负责，不在此列。
 */
object GameDataFiles {
    /** 首领数据：夜王与首领的战斗数值、深夜深度、变异与多人缩放。 */
    const val BOSSES = "nightreign-bosses-v1.03.5.json"

    /** 战技 / 法术 / 武器：增伤排名的输出手段与伤害构成。 */
    const val SKILLS = "nightreign-skills-v1.03.5.json"

    /** 增伤手段：局内武器词条、固定遗物、护符与其它增益。 */
    const val BUFFS = "nightreign-buffs-v1.03.5.json"

    /** 角色属性：10 个渡夜者 1–15 级属性、转职遗物与利普拉的交易。 */
    const val HEROES = "nightreign-heroes-v1.03.5.json"

    /** 遗物物品表：词条反查与存档检查用的遗物、槽池与额外词条。 */
    const val RELICS = "nightreign-relics-v1.03.4.json"

    val all: List<String> = listOf(BOSSES, SKILLS, BUFFS, HEROES, RELICS)
}

/**
 * 数据集标识。[versionField] 是该文件顶层的版本键，[expectedVersion] 是本应用支持的版本；
 * 各页解析器应在根 DTO 里带上这个字段，并用 [GameDataJson.requireVersion] 校验。
 */
enum class GameDataKey(
    val fileName: String,
    val versionField: String,
    val expectedVersion: Int,
) {
    BOSSES(GameDataFiles.BOSSES, "bossesSchemaVersion", 4),
    SKILLS(GameDataFiles.SKILLS, "schemaVersion", 2),
    BUFFS(GameDataFiles.BUFFS, "schemaVersion", 6),
    HEROES(GameDataFiles.HEROES, "schemaVersion", 1),
    RELICS(GameDataFiles.RELICS, "relicsSchemaVersion", 1),
}
