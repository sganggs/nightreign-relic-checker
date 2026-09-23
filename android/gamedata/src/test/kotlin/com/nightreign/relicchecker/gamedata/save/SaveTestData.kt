package com.nightreign.relicchecker.gamedata.save

import com.nightreign.relicchecker.catalog.AffixCatalog
import com.nightreign.relicchecker.catalog.CatalogLoader
import com.nightreign.relicchecker.gamedata.GameDataKey
import java.io.File

/** 测试共用的真实数据（test resources 指向仓库根 data/），整个测试 JVM 只解析一次。 */
internal object SaveTestData {
    fun readResource(name: String): String {
        val stream = checkNotNull(javaClass.classLoader.getResourceAsStream(name)) { "data/ 下缺少 $name" }
        return stream.bufferedReader(Charsets.UTF_8).use { it.readText() }
    }

    val catalog: AffixCatalog by lazy { CatalogLoader.parse(readResource(CatalogLoader.ASSET_FILE_NAME)) }
    val relicText: String by lazy { readResource(GameDataKey.RELICS.fileName) }
    val relicData: RelicDataSet by lazy { RelicDataSet.parse(relicText) }
    val auditData: SaveAuditData by lazy { SaveAuditData.build(relicData, catalog) }
    val context: RelicAuditContext get() = auditData.context

    /** 仓库根 testdata/ 下的对拍文件（桌面双端共用）；从测试工作目录向上找仓库根。 */
    fun repoFile(relative: String): File {
        var dir: File? = File(System.getProperty("user.dir")).absoluteFile
        while (dir != null) {
            val candidate = File(dir, relative)
            if (candidate.isFile) return candidate
            dir = dir.parentFile
        }
        error("找不到仓库文件 $relative（测试工作目录 ${System.getProperty("user.dir")}）")
    }
}
