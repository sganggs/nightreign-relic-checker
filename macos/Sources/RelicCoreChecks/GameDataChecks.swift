import Foundation
import RelicCore

// 新页面（首领数据 / 词条反查 / 增伤排名）的自检入口。
//
// 功能开发者：请把自己的检查写成独立文件里的 `() throws -> Int` 函数
// （返回本次校验的条数，失败时 `throw CheckFailure(description:)`），
// 然后只在下面的列表里加一行，不要改动别人的行。

/// 检查项列表：名称 + 检查函数（返回校验条数）。
private let gameDataChecks: [(name: String, run: () throws -> Int)] = [
    ("新页面数据资源存在且是合法 JSON", checkGameDataResourcesArePresent),
    ("GameDataLoader 能定位已构建的资源包", checkGameDataLoaderResolvesBundledResources),
    ("首领数据字段完整性", checkBossData),
    ("首领数据：双端文案（档位分组名 / 行内徽标 / 韧性占位符）", checkBossDataParityText),
    ("词条反查", runAffixLookupChecks),
    ("存档页：自动定位 / 报告导出 / 存档对比", checkSaveScanFeatures),
    ("增伤排名：选段 / 伤害构成 / 倍率排名 / 叠加组合", runBuffRankerChecks),
]

/// 由 main.swift 在全部既有检查之后调用；返回新增的校验条数。
func runGameDataChecks() throws -> Int {
    var total = 0
    for check in gameDataChecks {
        let count = try check.run()
        total += count
        print("  ✓ \(check.name)：\(count) 项")
    }
    return total
}

/// 内置资源目录（macos/Sources/NightreignRelicChecker/Resources）。
/// 以源码路径定位，`swift run RelicCoreChecks` 不依赖应用目标是否已构建。
private var resourcesDirectory: URL {
    URL(fileURLWithPath: #filePath)          // …/Sources/RelicCoreChecks/GameDataChecks.swift
        .deletingLastPathComponent()         // …/Sources/RelicCoreChecks
        .deletingLastPathComponent()         // …/Sources
        .deletingLastPathComponent()         // …/macos
        .appendingPathComponent("Sources/NightreignRelicChecker/Resources", isDirectory: true)
}

/// 三个资源文件都存在且是合法 JSON（脚手架占位内容也算合法）。
private func checkGameDataResourcesArePresent() throws -> Int {
    var count = 0
    for resource in GameDataResource.allCases {
        let url = resourcesDirectory.appendingPathComponent(resource.fileName)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw CheckFailure(
                description: "缺少内置数据文件 \(resource.fileName)（\(url.path)）；"
                    + "真实数据未就绪时也必须保留最小占位 JSON"
            )
        }
        let data = try Data(contentsOf: url)
        guard (try? JSONSerialization.jsonObject(with: data)) != nil else {
            throw CheckFailure(description: "\(resource.fileName) 不是合法 JSON")
        }
        count += 1
    }
    return count
}

/// `GameDataLoader` 能在应用目标的 SwiftPM 资源包里定位三个资源。
///
/// `swift run RelicCoreChecks` 只构建 RelicCoreChecks，可执行文件旁不一定有
/// 应用目标的资源包；此时跳过（返回 0 项）。完整 `swift build` 之后这项会真正
/// 校验 Bundle 查找路径。
private func checkGameDataLoaderResolvesBundledResources() throws -> Int {
    guard GameDataLoader.url(for: .bosses) != nil else {
        print("    （应用资源包未构建，跳过 GameDataLoader 定位检查）")
        return 0
    }
    var count = 0
    for resource in GameDataResource.allCases {
        guard let url = GameDataLoader.url(for: resource) else {
            throw CheckFailure(description: "GameDataLoader 未能定位 \(resource.fileName)")
        }
        guard (try? Data(contentsOf: url)) != nil else {
            throw CheckFailure(description: "GameDataLoader 定位到的 \(resource.fileName) 无法读取")
        }
        count += 1
    }
    return count
}
