import Foundation

/// 新页面（首领数据 / 角色属性 / 词条反查 / 增伤排名）使用的游戏数据文件。
///
/// 加载器只负责找到文件并返回原始 `Data`，**不解析、不定义业务模型**：各功能
/// 自行在自己的文件里定义 `Codable` 模型再解码，互不影响。
public enum GameDataResource: String, CaseIterable, Sendable {
    case bosses
    case skills
    case buffs
    case heroes

    /// 不带扩展名的资源名。
    public var baseName: String { rawValue }

    /// 内置资源目录里的文件名。
    public var fileName: String { rawValue + ".json" }
}

public enum GameDataError: LocalizedError {
    case missing(GameDataResource)
    case unreadable(GameDataResource)

    public var errorDescription: String? {
        switch self {
        case .missing(let resource):
            return "未找到数据文件 \(resource.fileName)：应用未内置该数据"
        case .unreadable(let resource):
            return "无法读取数据文件 \(resource.fileName)"
        }
    }
}

/// 供 RelicCore 定位应用目标资源包的锚点类型（见 `GameDataLoader.searchBundles`）。
private final class GameDataBundleToken {}

public enum GameDataLoader {
    /// 查找顺序：`Bundle.main`（打包后的 .app，Scripts/build_app.sh 会把 json
    /// 拷到 Contents/Resources）→ 应用目标的 SwiftPM 资源包（`swift run` 场景，
    /// 等价于 `Bundle.module`；RelicCore 自身没有资源，SwiftPM 不会为它生成
    /// `Bundle.module`，因此这里按 SwiftPM 的命名约定去可执行文件旁查找）。
    private static var searchBundles: [Bundle] {
        var bundles: [Bundle] = [.main]
        let token = Bundle(for: GameDataBundleToken.self)
        let roots: [URL?] = [
            Bundle.main.resourceURL,
            Bundle.main.bundleURL,
            token.resourceURL,
            token.bundleURL.deletingLastPathComponent()
        ]
        for root in roots.compactMap({ $0 }) {
            let url = root.appendingPathComponent("NightreignRelicChecker_NightreignRelicChecker.bundle")
            guard let bundle = Bundle(url: url) else { continue }
            if !bundles.contains(where: { $0.bundleURL == bundle.bundleURL }) {
                bundles.append(bundle)
            }
        }
        return bundles
    }

    /// 数据文件的位置；未内置时为 nil。
    public static func url(for resource: GameDataResource) -> URL? {
        for bundle in searchBundles {
            if let url = bundle.url(forResource: resource.baseName, withExtension: "json") {
                return url
            }
        }
        return nil
    }

    /// 读取原始 JSON 数据；未内置或读取失败时抛出可读错误。
    public static func data(for resource: GameDataResource) throws -> Data {
        guard let url = url(for: resource) else { throw GameDataError.missing(resource) }
        guard let data = try? Data(contentsOf: url) else { throw GameDataError.unreadable(resource) }
        return data
    }

    /// 是否是脚手架占位文件（顶层 `{"placeholder": true}`）。
    ///
    /// 真实数据由另一条流水线生成，未生成前 Resources/ 下放的是最小占位 JSON
    /// （两端都需要「文件必须存在」），占位内容一律视同「数据未内置」。
    public static func isPlaceholder(_ data: Data) -> Bool {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any] else { return false }
        return dictionary["placeholder"] as? Bool == true
    }

    /// 可用的数据：未内置、占位或读取失败时返回 nil（不抛错），
    /// 页面据此降级显示「数据未内置」。
    public static func dataIfAvailable(for resource: GameDataResource) -> Data? {
        guard let data = try? data(for: resource), !isPlaceholder(data) else { return nil }
        return data
    }
}
