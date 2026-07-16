import AppKit
import SwiftUI
import UniformTypeIdentifiers
import RelicCore

struct SaveScanView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
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

                pickCard

                if let report = model.saveReport {
                    if !report.checksumOk {
                        checksumBanner
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
    }

    private var pickCard: some View {
        VStack(alignment: .leading, spacing: 15) {
            SectionHeading(
                title: "选择存档文件",
                subtitle: "支持 .sl2 与 .co2（无缝联机）存档；Windows 默认位于 %APPDATA%\\Nightreign\\<SteamID>\\NR0000.sl2",
                symbol: "externaldrive.badge.checkmark"
            )

            HStack(spacing: 10) {
                Button(action: chooseSaveFile) {
                    Label("选择存档文件", systemImage: "folder")
                }
                .buttonStyle(PrimaryButtonStyle())

                if let report = model.saveReport {
                    Pill(text: report.fileName, color: AppTheme.purpleSoft, symbol: "doc")
                }
                Spacer(minLength: 0)
            }

            if !model.saveMessage.isEmpty {
                Text(model.saveMessage)
                    .font(.caption)
                    .foregroundStyle(AppTheme.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 8) {
                Pill(text: "只读解析，不修改存档", color: AppTheme.green, symbol: "lock.shield")
                Pill(text: "完全离线本地解析，不上传任何数据", color: AppTheme.purpleSoft, symbol: "wifi.slash")
            }
        }
        .appCard()
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
                        RelicCard(relic: relic, report: report)
                    }
                }
            }
        }
    }

    private func selectedCharacter(in report: SaveScanReport) -> SaveScanReport.Character? {
        report.characters.first { $0.slot == model.saveSelectedSlot } ?? report.characters.first
    }

    private func filteredRelics(_ relics: [SaveScanReport.AuditedRelic]) -> [SaveScanReport.AuditedRelic] {
        switch model.saveFilter {
        case .all: return relics
        case .invalidOnly: return relics.filter { $0.result.status == .invalid }
        case .deepOnly: return relics.filter(\.isDeep)
        }
    }

    private func chooseSaveFile() {
        let panel = NSOpenPanel()
        panel.title = "选择存档文件"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        let saveTypes = ["sl2", "co2"].compactMap { UTType(filenameExtension: $0) }
        panel.allowedContentTypes = saveTypes.isEmpty ? [.data] : saveTypes
        guard panel.runModal() == .OK, let url = panel.url else { return }
        model.importSave(from: url)
    }
}

private struct RelicCard: View {
    let relic: SaveScanReport.AuditedRelic
    let report: SaveScanReport

    private static let curseText = Color(red: 0.55, green: 0.64, blue: 0.82)

    private var statusText: String {
        if relic.result.status == .invalid { return "非法" }
        return relic.result.warnings.isEmpty ? "合法" : "警告"
    }

    private var statusColor: Color {
        if relic.result.status == .invalid { return AppTheme.red }
        return relic.result.warnings.isEmpty ? AppTheme.green : AppTheme.amber
    }

    private var statusSymbol: String {
        if relic.result.status == .invalid { return "xmark.octagon.fill" }
        return relic.result.warnings.isEmpty ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
    }

    private var colorPill: (text: String, color: Color)? {
        guard let info = relic.info else { return nil }
        let label = relicColorLabel(info.color)
        switch info.color {
        case 0: return (label, AppTheme.red)
        case 1: return (label, Color(red: 0.38, green: 0.60, blue: 0.98))
        case 2: return (label, AppTheme.amber)
        case 3: return (label, AppTheme.green)
        case 4: return (label, Color.white.opacity(0.72))
        default: return (label, AppTheme.secondaryText)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .top, spacing: 8) {
                Text(relic.displayName)
                    .font(.subheadline.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                Pill(text: statusText, color: statusColor, symbol: statusSymbol)
            }

            HStack(spacing: 6) {
                Pill(text: relic.kindLabel, color: AppTheme.purpleSoft)
                if let colorPill {
                    Pill(text: colorPill.text, color: colorPill.color)
                }
                if relic.isDeep {
                    Pill(text: "深夜", color: AppTheme.purple, symbol: "moon.stars")
                }
                Text("ID \(relic.relic.itemID)")
                    .font(.caption2.monospaced())
                    .foregroundStyle(AppTheme.tertiaryText)
                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: 6) {
                ForEach(0..<3, id: \.self) { row in
                    if relic.relic.effects[row] != -1 || relic.relic.curses[row] != -1 {
                        affixLine(row: row)
                    }
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppTheme.field.opacity(0.6), in: RoundedRectangle(cornerRadius: 9))

            ForEach(relic.result.issues) { issue in
                SaveIssueRow(issue: issue, warning: false)
            }
            ForEach(relic.result.warnings) { issue in
                SaveIssueRow(issue: issue, warning: true)
            }

            if let ordered = relic.result.orderedEffects {
                VStack(alignment: .leading, spacing: 4) {
                    Text("正确的保存顺序")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(AppTheme.purpleSoft)
                    ForEach(Array(ordered.enumerated()), id: \.offset) { index, effectID in
                        Text("\(index + 1). " + (effectID == -1 ? "（空）" : report.affixName(effectID)))
                            .font(.caption)
                            .foregroundStyle(AppTheme.secondaryText)
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AppTheme.purple.opacity(0.06), in: RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(AppTheme.purple.opacity(0.18), lineWidth: 1))
            }
        }
        .appCard(padding: 14)
    }

    private func affixLine(row: Int) -> some View {
        let effect = relic.relic.effects[row]
        let curse = relic.relic.curses[row]
        return HStack(alignment: .top, spacing: 0) {
            Text(effect == -1 ? "（空）" : report.affixName(effect))
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
            if curse != -1 {
                Text("｜" + report.affixName(curse))
                    .font(.caption)
                    .foregroundStyle(Self.curseText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }
}

private struct SaveIssueRow: View {
    let issue: RelicAuditIssue
    let warning: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: warning ? "exclamationmark.triangle.fill" : "xmark.circle.fill")
                .foregroundStyle(warning ? AppTheme.amber : AppTheme.red)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 3) {
                Text(issue.title).font(.caption.weight(.bold))
                Text(issue.detail)
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.field.opacity(0.75), in: RoundedRectangle(cornerRadius: 9))
    }
}
