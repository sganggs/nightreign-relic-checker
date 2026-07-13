import AppKit
import SwiftUI
import UniformTypeIdentifiers
import RelicCore

struct DataSettingsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 14) {
                    LogoMark(size: 40)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("数据设置")
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                        Text("词条库随应用离线保存，也可导入更新后的 JSON 数据")
                            .font(.caption)
                            .foregroundStyle(AppTheme.secondaryText)
                    }
                }

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 18) {
                    catalogCard
                    actionsCard
                }

                modeCard
                sourcesCard
                disclaimerCard
            }
            .padding(26)
            .frame(maxWidth: 1180)
            .frame(maxWidth: .infinity)
        }
    }

    private var catalogCard: some View {
        VStack(alignment: .leading, spacing: 17) {
            SectionHeading(
                title: "当前词条库",
                subtitle: "以 effectId 为主键，名称差异会保留为别名",
                symbol: "externaldrive.fill",
                tint: AppTheme.green
            )

            DataLine(label: "来源", value: model.catalogOrigin)
            DataLine(label: "游戏数据", value: model.catalog.gameVersion)
            DataLine(label: "数据修订", value: model.catalog.dataVersion)
            DataLine(label: "内容", value: model.catalogSummary)
            DataLine(label: "生成时间", value: model.catalog.generatedAt)

            HStack(spacing: 8) {
                Pill(text: "Schema v\(model.catalog.schemaVersion)", color: AppTheme.purpleSoft)
                Pill(text: "本地 JSON", color: AppTheme.green)
            }
        }
        .appCard()
        .frame(maxWidth: .infinity, minHeight: 290, alignment: .top)
    }

    private var actionsCard: some View {
        VStack(alignment: .leading, spacing: 17) {
            SectionHeading(
                title: "更新与备份",
                subtitle: "导入前会验证 schema、重复 ID 与基本完整性",
                symbol: "arrow.triangle.2.circlepath"
            )

            Button(action: chooseImport) {
                Label("导入词条库 JSON", systemImage: "square.and.arrow.down")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButtonStyle())

            Button(action: chooseExport) {
                Label("导出当前词条库", systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(SecondaryButtonStyle())

            Button(action: model.resetCatalog) {
                Label("恢复内置数据", systemImage: "arrow.counterclockwise")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(SecondaryButtonStyle())

            if !model.dataMessage.isEmpty {
                Text(model.dataMessage)
                    .font(.caption)
                    .foregroundStyle(model.dataMessage.contains("失败") ? AppTheme.red : AppTheme.green)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text("后续拿到旧版顺序表时，可先按当前 JSON schema 合并 ID、互斥池和排序键，再从这里直接替换。")
                .font(.caption)
                .foregroundStyle(AppTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .appCard()
        .frame(maxWidth: .infinity, minHeight: 290, alignment: .top)
    }

    private var modeCard: some View {
        VStack(alignment: .leading, spacing: 17) {
            SectionHeading(
                title: "四种校验口径",
                subtitle: "普通遗物按版本严格校验；深夜模式会额外标注诅咒配对风险",
                symbol: "slider.horizontal.3"
            )

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(CheckMode.allCases) { mode in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: model.mode == mode ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(model.mode == mode ? AppTheme.purpleSoft : AppTheme.secondaryText)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(mode.title).font(.subheadline.weight(.semibold))
                            Text(mode.detail)
                                .font(.caption)
                                .foregroundStyle(AppTheme.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(12)
                    .background(AppTheme.field, in: RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(model.mode == mode ? AppTheme.purple.opacity(0.7) : AppTheme.border, lineWidth: 1)
                    )
                    .contentShape(Rectangle())
                    .onTapGesture { model.mode = mode }
                }
            }
        }
        .appCard()
    }

    private var sourcesCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeading(
                title: "数据来源与许可",
                subtitle: "发行包内保留第三方许可与具体修订号",
                symbol: "link"
            )

            ForEach(model.catalog.sources, id: \.url) { source in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "doc.text")
                        .foregroundStyle(AppTheme.purpleSoft)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(source.name).font(.subheadline.weight(.semibold))
                        Text(source.url)
                            .font(.caption.monospaced())
                            .foregroundStyle(AppTheme.secondaryText)
                            .textSelection(.enabled)
                        HStack(spacing: 8) {
                            if !source.revision.isEmpty { Pill(text: String(source.revision.prefix(10)), color: AppTheme.purpleSoft) }
                            if !source.license.isEmpty { Pill(text: source.license, color: AppTheme.green) }
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(12)
                .background(AppTheme.field, in: RoundedRectangle(cornerRadius: 10))
            }
        }
        .appCard()
    }

    private var disclaimerCard: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.shield")
                .foregroundStyle(AppTheme.amber)
            VStack(alignment: .leading, spacing: 5) {
                Text("非官方社区工具").font(.subheadline.weight(.semibold))
                Text("本软件不修改存档，不连接游戏服务器，也不构成官方判定。词条名称与游戏文本权利归其权利方所有；数据可能随更新变化。GPL-3.0 数据增强内容及 MIT 规则实现均已在发行包中保留来源。")
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .appCard(padding: 16)
    }

    private func chooseImport() {
        let panel = NSOpenPanel()
        panel.title = "导入词条库"
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        model.importCatalog(from: url)
    }

    private func chooseExport() {
        let panel = NSSavePanel()
        panel.title = "导出当前词条库"
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "nightreign-affixes-\(model.catalog.dataVersion.replacingOccurrences(of: " ", with: "-")).json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        model.exportCatalog(to: url)
    }
}

private struct DataLine: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.caption)
                .foregroundStyle(AppTheme.secondaryText)
                .frame(width: 72, alignment: .leading)
            Text(value.isEmpty ? "—" : value)
                .font(.caption.monospaced())
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
    }
}
