import AppKit
import SwiftUI
import UniformTypeIdentifiers
import RelicCore

/// 存档检查页。
///
/// 页面自己持有的状态（自动查找结果、拖拽高亮、对比结果、导出提示）全部放在
/// 本视图的 `@State` 里；跨页面需要保留的存档报告仍在 `AppModel`。
/// 纯逻辑（自动定位 / 报告文本 / 存档对比）都在 RelicCore：
/// `SaveLocator`、`SaveReportBuilder`、`SaveComparator`。
struct SaveScanView: View {
    @EnvironmentObject private var model: AppModel

    @State private var candidates: [SaveFileCandidate] = []
    @State private var didScan = false
    @State private var isScanning = false
    @State private var isDropTargeted = false
    @State private var dropMessage = ""
    @State private var exportMessage = ""
    @State private var compareMessage = ""
    @State private var compare: SaveCompareResult?
    /// 本页这次载入的存档路径（存档文件名大多都叫 NR0000.sl2，只能按路径标「已载入」）。
    @State private var loadedURL: URL?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                pickCard

                if didScan {
                    locatorCard
                }

                if let report = model.saveReport {
                    if !report.checksumOk {
                        checksumBanner
                    }
                    if let compare {
                        SaveCompareSection(result: compare, report: report) {
                            self.compare = nil
                        }
                    }
                    if let character = selectedCharacter(in: report) {
                        controlCard(report: report, character: character)
                        characterContent(report: report, character: character)
                    } else {
                        EmptyStateView(
                            title: "存档中没有角色",
                            symbol: "person.crop.circle.badge.questionmark",
                            detail: "未在该存档中找到已占用的角色槽位。"
                        )
                        .frame(maxWidth: .infinity)
                        .appCard()
                    }
                }
            }
            .padding(26)
            .frame(maxWidth: 1180)
            .frame(maxWidth: .infinity)
        }
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted, perform: handleDrop)
        .overlay {
            if isDropTargeted { dropOverlay }
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            LogoMark(size: 40)
            VStack(alignment: .leading, spacing: 4) {
                Text("存档检查")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                Text("读取《黑夜君临》存档（.sl2 / .co2），逐件校验全部角色的遗物合法性")
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
            }
        }
    }

    // MARK: - 选择存档

    private var pickCard: some View {
        VStack(alignment: .leading, spacing: 15) {
            SectionHeading(
                title: "选择存档文件",
                subtitle: "支持 .sl2 与 .co2（无缝联机）存档；可以自动查找 CrossOver 的 bottle，"
                    + "也可以把存档文件直接拖到本页任意位置；"
                    + "Windows 默认位于 %APPDATA%\\Nightreign\\<SteamID>\\NR0000.sl2",
                symbol: "externaldrive.badge.checkmark"
            )

            HStack(spacing: 10) {
                Button(action: chooseSaveFile) {
                    Label("选择存档文件", systemImage: "folder")
                }
                .buttonStyle(PrimaryButtonStyle())

                Button(action: runAutoScan) {
                    Label(isScanning ? "查找中…" : "自动查找", systemImage: "sparkle.magnifyingglass")
                }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(isScanning)

                if model.saveReport != nil {
                    Menu {
                        ForEach(SaveReportFormat.allCases) { format in
                            Button(format.title) { exportReport(format) }
                        }
                    } label: {
                        Label("导出报告", systemImage: "square.and.arrow.up")
                    }
                    .menuStyle(.borderlessButton)
                    .frame(width: 120)

                    Button(action: chooseCompareFile) {
                        Label("对比另一份存档", systemImage: "arrow.left.arrow.right")
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }

                Spacer(minLength: 0)
            }

            if let report = model.saveReport {
                HStack(spacing: 8) {
                    Pill(text: report.fileName, color: AppTheme.purpleSoft, symbol: "doc")
                    Pill(
                        text: "角色 \(report.characters.count) · 遗物 \(report.relicCount)",
                        color: AppTheme.purpleSoft,
                        symbol: "person.2"
                    )
                    Spacer(minLength: 0)
                }
            }

            ForEach(Array(messages.enumerated()), id: \.offset) { _, message in
                Text(message.text)
                    .font(.caption)
                    .foregroundStyle(message.isError ? AppTheme.red : AppTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 8) {
                Pill(text: "只读解析，不修改存档", color: AppTheme.green, symbol: "lock.shield")
                Pill(text: "完全离线本地解析，不上传任何数据", color: AppTheme.purpleSoft, symbol: "wifi.slash")
            }
        }
        .appCard()
    }

    private var messages: [(text: String, isError: Bool)] {
        var items: [(text: String, isError: Bool)] = []
        if !model.saveMessage.isEmpty { items.append((model.saveMessage, true)) }
        if !dropMessage.isEmpty { items.append((dropMessage, true)) }
        if !compareMessage.isEmpty { items.append((compareMessage, true)) }
        if !exportMessage.isEmpty { items.append((exportMessage, exportMessage.hasPrefix("导出失败"))) }
        return items
    }

    // MARK: - 自动查找结果

    private var locatorCard: some View {
        VStack(alignment: .leading, spacing: 13) {
            SectionHeading(
                title: "自动查找到的存档",
                subtitle: "扫描范围：\(SaveLocator.displayBottlesPath)/<bottle>/drive_c/users/<用户名>/AppData/Roaming/Nightreign/<SteamID>/",
                symbol: "folder.badge.questionmark"
            )

            if candidates.isEmpty {
                Text(SaveLocator.pathHint)
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AppTheme.field.opacity(0.7), in: RoundedRectangle(cornerRadius: 10))
            } else {
                VStack(spacing: 8) {
                    ForEach(candidates) { candidate in
                        SaveCandidateRow(
                            candidate: candidate,
                            isCurrent: model.saveReport != nil && candidate.url == loadedURL
                        ) {
                            loadSave(from: candidate.url)
                        }
                    }
                }
            }
        }
        .appCard()
    }

    private var dropOverlay: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .stroke(AppTheme.purpleSoft, style: StrokeStyle(lineWidth: 2, dash: [7, 5]))
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(AppTheme.purple.opacity(0.10))
            )
            .overlay {
                VStack(spacing: 10) {
                    Image(systemName: "arrow.down.doc")
                        .font(.system(size: 34, weight: .light))
                        .foregroundStyle(AppTheme.purpleSoft)
                    Text("松手即可解析存档")
                        .font(.headline)
                    Text("支持 .sl2 / .co2")
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                }
            }
            .padding(10)
            .allowsHitTesting(false)
    }

    private var checksumBanner: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(AppTheme.amber)
                .padding(.top, 1)
            Text("存档校验和异常，结果仅供参考")
                .font(.caption.weight(.bold))
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(AppTheme.amber.opacity(0.08), in: RoundedRectangle(cornerRadius: 11))
        .overlay(RoundedRectangle(cornerRadius: 11).stroke(AppTheme.amber.opacity(0.32), lineWidth: 1))
    }

    private func controlCard(report: SaveScanReport, character: SaveScanReport.Character) -> some View {
        let total = character.relics.count
        let invalid = character.relics.filter { $0.result.status == .invalid }.count

        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                Picker("角色", selection: $model.saveSelectedSlot) {
                    ForEach(report.characters) { character in
                        Text("槽位 \(character.slot + 1) · \(character.name)")
                            .tag(Optional(character.slot))
                    }
                }
                .frame(maxWidth: 320)

                Spacer(minLength: 0)

                Picker("过滤", selection: $model.saveFilter) {
                    ForEach(AppModel.SaveFilter.allCases) { filter in
                        Text(filter.title).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 300)
            }

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(AppTheme.secondaryText)
                TextField("搜索遗物名、词条名或 ID", text: $model.saveQuery)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 12)
            .frame(height: 34)
            .background(AppTheme.field, in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(AppTheme.border, lineWidth: 1))

            HStack(spacing: 8) {
                Pill(text: "遗物总数 \(total)", color: AppTheme.purpleSoft, symbol: "shippingbox")
                Pill(text: "合法 \(total - invalid)", color: AppTheme.green, symbol: "checkmark.circle")
                Pill(text: "非法 \(invalid)", color: AppTheme.red, symbol: "xmark.octagon")
                Spacer(minLength: 0)
            }
        }
        .appCard(padding: 16)
    }

    @ViewBuilder
    private func characterContent(report: SaveScanReport, character: SaveScanReport.Character) -> some View {
        if let parseError = character.parseError {
            EmptyStateView(
                title: "该槽位解析失败",
                symbol: "exclamationmark.triangle",
                detail: parseError
            )
            .frame(maxWidth: .infinity)
            .appCard()
        } else {
            let filtered = filteredRelics(character.relics)
            let invalidCount = character.relics.filter { $0.result.status == .invalid }.count

            if invalidCount == 0 && !character.relics.isEmpty {
                HStack(spacing: 9) {
                    Text("🎉")
                    Text("未发现不合法遗物")
                        .font(.caption.weight(.bold))
                    Spacer(minLength: 0)
                }
                .padding(12)
                .background(AppTheme.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 11))
                .overlay(RoundedRectangle(cornerRadius: 11).stroke(AppTheme.green.opacity(0.32), lineWidth: 1))
            }

            if filtered.isEmpty {
                EmptyStateView(
                    title: model.saveFilter == .invalidOnly ? "🎉 未发现不合法遗物" : "没有符合条件的遗物",
                    symbol: model.saveFilter == .invalidOnly ? "checkmark.seal" : "shippingbox",
                    detail: model.saveFilter == .deepOnly
                        ? "该角色没有持有深夜遗物。"
                        : (character.relics.isEmpty ? "该角色没有持有任何遗物。" : "当前过滤条件下没有可显示的遗物。")
                )
                .frame(maxWidth: .infinity)
                .appCard()
            } else {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 330), spacing: 16, alignment: .top)],
                    alignment: .leading,
                    spacing: 16
                ) {
                    ForEach(filtered) { relic in
                        SaveRelicCard(relic: relic, report: report)
                    }
                }
            }
        }
    }

    private func selectedCharacter(in report: SaveScanReport) -> SaveScanReport.Character? {
        report.characters.first { $0.slot == model.saveSelectedSlot } ?? report.characters.first
    }

    private func filteredRelics(_ relics: [SaveScanReport.AuditedRelic]) -> [SaveScanReport.AuditedRelic] {
        var result: [SaveScanReport.AuditedRelic]
        switch model.saveFilter {
        case .all: result = relics
        case .invalidOnly: result = relics.filter { $0.result.status == .invalid }
        case .deepOnly: result = relics.filter(\.isDeep)
        }
        let needle = model.saveQuery.foldedForSearch
        guard !needle.isEmpty, let report = model.saveReport else { return result }
        return result.filter { searchText(for: $0, report: report).contains(needle) }
    }

    /// 遗物卡搜索文本：名称、种类、ID、全部正负词条名与 ID（与 Windows 端一致）
    private func searchText(for relic: SaveScanReport.AuditedRelic, report: SaveScanReport) -> String {
        var parts = [relic.displayName, String(relic.relic.itemID), relic.kindLabel]
        for effectID in relic.relic.effects + relic.relic.curses where effectID != -1 {
            parts.append(report.affixName(effectID))
            parts.append(String(effectID))
        }
        return parts.joined(separator: " ").foldedForSearch
    }

    // MARK: - 载入存档

    private func chooseSaveFile() {
        guard let url = runOpenPanel(title: "选择存档文件") else { return }
        loadSave(from: url)
    }

    /// 全部载入路径（按钮 / 自动查找列表 / 拖拽）都走这里，顺便清掉上一次的对比与提示。
    private func loadSave(from url: URL) {
        dropMessage = ""
        exportMessage = ""
        compareMessage = ""
        compare = nil
        model.importSave(from: url)
        loadedURL = model.saveReport == nil ? nil : url
    }

    private func runOpenPanel(title: String) -> URL? {
        let panel = NSOpenPanel()
        panel.title = title
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        let saveTypes = SaveLocator.supportedExtensions.sorted().compactMap { UTType(filenameExtension: $0) }
        panel.allowedContentTypes = saveTypes.isEmpty ? [.data] : saveTypes
        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }

    // MARK: - 自动查找

    private func runAutoScan() {
        isScanning = true
        dropMessage = ""
        let root = SaveLocator.defaultBottlesRoot()
        Task {
            let found = await Task.detached(priority: .userInitiated) {
                SaveLocator.scan(bottlesRoot: root)
            }.value
            await MainActor.run {
                candidates = found
                didScan = true
                isScanning = false
            }
        }
    }

    // MARK: - 拖拽

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        let identifier = UTType.fileURL.identifier
        guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(identifier) }) else {
            dropMessage = "拖入的内容不是文件"
            return false
        }
        provider.loadDataRepresentation(forTypeIdentifier: identifier) { data, _ in
            guard let data, let url = URL(dataRepresentation: data, relativeTo: nil) else {
                Task { @MainActor in dropMessage = "无法读取拖入的文件路径" }
                return
            }
            Task { @MainActor in acceptDropped(url) }
        }
        return true
    }

    @MainActor
    private func acceptDropped(_ url: URL) {
        guard SaveLocator.isSaveFile(url) else {
            dropMessage = "只支持 .sl2 / .co2 存档文件：\(url.lastPathComponent)"
            return
        }
        loadSave(from: url)
    }

    // MARK: - 导出报告

    private func exportReport(_ format: SaveReportFormat) {
        guard let report = model.saveReport else { return }
        let now = Date()
        let panel = NSSavePanel()
        panel.title = "导出存档检查报告"
        panel.nameFieldStringValue = SaveReportBuilder.suggestedFileName(for: report, format: format, date: now)
        panel.allowedContentTypes = [format == .csv ? .commaSeparatedText : .plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let body = SaveReportBuilder.content(for: report, format: format, generatedAt: now)
        // CSV 前置 BOM，表格软件才会按 UTF-8 打开中文。
        let content = format == .csv ? "\u{FEFF}" + body : body
        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
            exportMessage = "已导出：\(url.lastPathComponent)"
        } catch {
            exportMessage = "导出失败：\(error.localizedDescription)"
        }
    }

    // MARK: - 对比另一份存档

    private func chooseCompareFile() {
        guard let base = model.saveReport else { return }
        guard let url = runOpenPanel(title: "选择要对比的存档") else { return }
        do {
            let other = try model.auditedSave(from: url)
            compare = SaveComparator.compare(base: base, other: other)
            compareMessage = ""
        } catch {
            compare = nil
            compareMessage = "对比失败：\(error.localizedDescription)"
        }
    }
}

/// 自动查找结果里的一行。
private struct SaveCandidateRow: View {
    let candidate: SaveFileCandidate
    let isCurrent: Bool
    let open: () -> Void

    private static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        formatter.countStyle = .file
        return formatter
    }()

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }()

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: candidate.isCoop ? "person.2.badge.gearshape" : "doc")
                .foregroundStyle(AppTheme.purpleSoft)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 7) {
                    Text(candidate.fileName)
                        .font(.subheadline.weight(.semibold))
                    if candidate.isCoop {
                        Pill(text: "无缝联机", color: AppTheme.amber)
                    }
                    if isCurrent {
                        Pill(text: "已载入", color: AppTheme.green, symbol: "checkmark")
                    }
                }
                Text(candidate.locationLabel)
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
                Text(candidate.url.path)
                    .font(.caption2.monospaced())
                    .foregroundStyle(AppTheme.tertiaryText)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                HStack(spacing: 10) {
                    Text(Self.byteFormatter.string(fromByteCount: candidate.byteSize))
                    if let modified = candidate.modifiedAt {
                        Text("修改于 " + Self.dateFormatter.string(from: modified))
                    }
                }
                .font(.caption2)
                .foregroundStyle(AppTheme.tertiaryText)
            }

            Spacer(minLength: 8)

            Button("打开", action: open)
                .buttonStyle(SecondaryButtonStyle())
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.field.opacity(0.7), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isCurrent ? AppTheme.green.opacity(0.35) : AppTheme.border, lineWidth: 1)
        )
    }
}
