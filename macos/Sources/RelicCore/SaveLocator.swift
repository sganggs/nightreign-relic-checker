import Foundation

/// 自动定位到的一份候选存档。
///
/// 纯数据结构：路径、大小、修改时间与「在哪个 bottle / 哪个账号目录下」，
/// 展示层自行决定怎么格式化（大小 / 时间的本地化留给视图）。
public struct SaveFileCandidate: Identifiable, Hashable, Sendable {
    /// 存档文件路径。
    public let url: URL
    /// CrossOver 的 bottle 名（不是 bottle 结构时为空串）。
    public let bottleName: String
    /// `Nightreign/` 下的账号目录名（通常是 SteamID；存档直接放在 `Nightreign/` 下时为空串）。
    public let accountName: String
    /// 文件字节数；读不到时为 0。
    public let byteSize: Int64
    /// 文件修改时间；读不到时为 nil。
    public let modifiedAt: Date?

    public var id: String { url.path }

    public var fileName: String { url.lastPathComponent }

    /// 无缝联机（Seamless Co-op）存档。
    public var isCoop: Bool { url.pathExtension.lowercased() == "co2" }

    /// 「bottle · 账号」定位标签；两段都为空时退回上级目录名。
    public var locationLabel: String {
        let parts = [bottleName, accountName].filter { !$0.isEmpty }
        if parts.isEmpty { return url.deletingLastPathComponent().lastPathComponent }
        return parts.joined(separator: " · ")
    }

    public init(url: URL, bottleName: String, accountName: String, byteSize: Int64, modifiedAt: Date?) {
        self.url = url
        self.bottleName = bottleName
        self.accountName = accountName
        self.byteSize = byteSize
        self.modifiedAt = modifiedAt
    }
}

/// 在 CrossOver 的 bottle 目录里查找《黑夜君临》存档。
///
/// macOS 上游戏通常跑在 CrossOver / Wine 里，存档落在 bottle 的模拟
/// Windows 盘上：
///
/// ```
/// ~/Library/Application Support/CrossOver/Bottles/<bottle>/drive_c/users/<用户名>/AppData/Roaming/Nightreign/<SteamID>/NR0000.sl2
/// ```
///
/// 扫描入口一律接收「bottles 根目录」，检查用临时目录即可完整覆盖，
/// 不依赖本机是否真的装了 CrossOver。
public enum SaveLocator {
    /// 认得的存档扩展名（小写）。
    public static let supportedExtensions: Set<String> = ["sl2", "co2"]

    /// bottles 根目录相对于用户主目录的位置。
    public static let bottlesRelativePath = "Library/Application Support/CrossOver/Bottles"

    /// 展示用的根目录写法。
    public static var displayBottlesPath: String { "~/" + bottlesRelativePath }

    /// 找不到存档时展示的路径规则说明。
    public static let pathHint = """
        没有在 CrossOver 的 bottle 里找到存档。路径规则：
        \(displayBottlesPath)/<bottle>/drive_c/users/<用户名>/AppData/Roaming/Nightreign/<SteamID>/NR0000.sl2
        无缝联机存档（.co2）在同一个目录下。
        其它运行方式（Whisky、Parallels、从 Windows 机器拷来的存档）请用「选择存档文件」手动指定。
        """

    /// 本机默认的 bottles 根目录。
    public static func defaultBottlesRoot(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL {
        bottlesRelativePath.split(separator: "/").reduce(homeDirectory) { url, component in
            url.appendingPathComponent(String(component), isDirectory: true)
        }
    }

    /// 扫描一个 bottles 根目录，返回全部候选存档（按修改时间倒序）。
    ///
    /// 目录不存在、没有权限或结构不符都只会少返回结果，不抛错。
    public static func scan(bottlesRoot: URL, fileManager: FileManager = .default) -> [SaveFileCandidate] {
        var found: [SaveFileCandidate] = []
        for bottle in subdirectories(of: bottlesRoot, fileManager: fileManager) {
            guard let users = descend(from: bottle, path: ["drive_c", "users"], fileManager: fileManager) else {
                continue
            }
            for user in subdirectories(of: users, fileManager: fileManager) {
                guard let nightreign = descend(
                    from: user,
                    path: ["AppData", "Roaming", "Nightreign"],
                    fileManager: fileManager
                ) else { continue }

                // 少数装法会把存档直接放在 Nightreign/ 下，没有账号子目录。
                for file in saveFiles(in: nightreign, fileManager: fileManager) {
                    found.append(makeCandidate(
                        url: file,
                        bottleName: bottle.lastPathComponent,
                        accountName: "",
                        fileManager: fileManager
                    ))
                }
                for account in subdirectories(of: nightreign, fileManager: fileManager) {
                    for file in saveFiles(in: account, fileManager: fileManager) {
                        found.append(makeCandidate(
                            url: file,
                            bottleName: bottle.lastPathComponent,
                            accountName: account.lastPathComponent,
                            fileManager: fileManager
                        ))
                    }
                }
            }
        }
        return sortedForDisplay(found)
    }

    /// 排序口径：修改时间倒序（无时间的排最后），同时间按路径升序，保证结果稳定。
    public static func sortedForDisplay(_ candidates: [SaveFileCandidate]) -> [SaveFileCandidate] {
        var seen = Set<String>()
        let unique = candidates.filter { seen.insert($0.url.path).inserted }
        return unique.sorted { lhs, rhs in
            switch (lhs.modifiedAt, rhs.modifiedAt) {
            case let (left?, right?):
                if left != right { return left > right }
            case (nil, _?):
                return false
            case (_?, nil):
                return true
            case (nil, nil):
                break
            }
            return lhs.url.path < rhs.url.path
        }
    }

    /// 文件名看起来是不是存档（扩展名 .sl2 / .co2）。
    public static func isSaveFile(_ url: URL) -> Bool {
        supportedExtensions.contains(url.pathExtension.lowercased())
    }

    // MARK: - 目录遍历

    private static func makeCandidate(
        url: URL,
        bottleName: String,
        accountName: String,
        fileManager: FileManager
    ) -> SaveFileCandidate {
        let attributes = try? fileManager.attributesOfItem(atPath: url.path)
        let size = (attributes?[.size] as? NSNumber)?.int64Value ?? 0
        let modified = attributes?[.modificationDate] as? Date
        return SaveFileCandidate(
            url: url,
            bottleName: bottleName,
            accountName: accountName,
            byteSize: size,
            modifiedAt: modified
        )
    }

    /// 按名字逐级往下走，任何一级找不到就返回 nil。
    private static func descend(from root: URL, path: [String], fileManager: FileManager) -> URL? {
        var current = root
        for component in path {
            guard let next = child(of: current, named: component, fileManager: fileManager) else { return nil }
            current = next
        }
        return current
    }

    /// 取指定名字的子目录；先按原名命中，再退回大小写不敏感匹配
    /// （bottle 里的 `drive_c` / `users` 大小写取决于 Wine 版本与卷的大小写敏感性）。
    private static func child(of directory: URL, named name: String, fileManager: FileManager) -> URL? {
        let direct = directory.appendingPathComponent(name, isDirectory: true)
        if isDirectory(direct, fileManager: fileManager) { return direct }
        let lowercased = name.lowercased()
        return subdirectories(of: directory, fileManager: fileManager)
            .first { $0.lastPathComponent.lowercased() == lowercased }
    }

    private static func subdirectories(of directory: URL, fileManager: FileManager) -> [URL] {
        contents(of: directory, fileManager: fileManager).filter { isDirectory($0, fileManager: fileManager) }
    }

    private static func saveFiles(in directory: URL, fileManager: FileManager) -> [URL] {
        contents(of: directory, fileManager: fileManager).filter { url in
            isSaveFile(url) && !isDirectory(url, fileManager: fileManager)
        }
    }

    private static func contents(of directory: URL, fileManager: FileManager) -> [URL] {
        guard let items = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return items.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private static func isDirectory(_ url: URL, fileManager: FileManager) -> Bool {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return false }
        return isDirectory.boolValue
    }
}
