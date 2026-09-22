import SwiftUI
import RelicCore

/// 增伤排名页（占位实现）。
///
/// 由「增伤排名」功能开发者独占：只改本文件、以及自己新增的 RelicCore 文件与
/// RelicCoreChecks 检查文件；**不需要再改 AppModel / RootView**。
/// 因此页面状态请全部放在本视图内（`@State` / `@StateObject`）。
///
/// 数据：`GameDataLoader.dataIfAvailable(for: .skills)` 与 `… (for: .buffs)`
/// → `Resources/skills.json`、`Resources/buffs.json` 的原始 JSON；
/// 未内置（文件缺失或仍是占位内容）时为 nil，页面需降级显示。
struct BuffRankerView: View {
    private struct ResourceStatus: Identifiable {
        let resource: GameDataResource
        let byteCount: Int?

        var id: String { resource.rawValue }
        var isAvailable: Bool { byteCount != nil }
    }

    @State private var statuses: [ResourceStatus] = []

    private static let usedResources: [GameDataResource] = [.skills, .buffs]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                placeholderCard
            }
            .padding(26)
            .frame(maxWidth: 1180)
            .frame(maxWidth: .infinity)
        }
        .onAppear(perform: reload)
    }

    private var header: some View {
        HStack(spacing: 14) {
            LogoMark(size: 40)
            VStack(alignment: .leading, spacing: 4) {
                Text("增伤排名")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                Text("按技能与增益数据排列词条的增伤收益")
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
            }
        }
    }

    private var placeholderCard: some View {
        VStack(alignment: .leading, spacing: 15) {
            SectionHeading(
                title: "功能开发中",
                subtitle: "页面脚手架已就绪，业务逻辑请在 BuffRankerView.swift 内实现",
                symbol: "chart.bar.xaxis"
            )

            HStack(spacing: 8) {
                if statuses.isEmpty {
                    Pill(text: "正在检查数据文件…", color: AppTheme.purpleSoft)
                }
                ForEach(statuses) { status in
                    if let byteCount = status.byteCount {
                        Pill(
                            text: "\(status.resource.fileName) · \(byteCount) 字节",
                            color: AppTheme.green,
                            symbol: "checkmark.circle"
                        )
                    } else {
                        Pill(
                            text: "\(status.resource.fileName) 未内置",
                            color: AppTheme.amber,
                            symbol: "exclamationmark.triangle"
                        )
                    }
                }
            }

            if !statuses.isEmpty && statuses.contains(where: { !$0.isAvailable }) {
                Text("运行 scripts/sync-data.sh 同步 data/ 下的源文件后重新构建即可。")
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
            }

            Text("数据文件：Resources/skills.json 与 Resources/buffs.json，"
                 + "通过 GameDataLoader.dataIfAvailable(for:) 读取；"
                 + "加载器只返回原始 Data，业务模型请在自己的文件里定义。")
                .font(.caption2)
                .foregroundStyle(AppTheme.tertiaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .appCard()
    }

    private func reload() {
        statuses = Self.usedResources.map { resource in
            ResourceStatus(
                resource: resource,
                byteCount: GameDataLoader.dataIfAvailable(for: resource)?.count
            )
        }
    }
}
