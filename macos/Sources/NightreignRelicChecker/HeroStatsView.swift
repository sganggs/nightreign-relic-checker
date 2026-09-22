import SwiftUI
import RelicCore

/// 角色属性页（占位实现）。
///
/// 由「角色属性」功能开发者独占：只改本文件、以及自己新增的 RelicCore 文件与
/// RelicCoreChecks 检查文件；**不需要再改 AppModel / RootView**。
/// 因此页面状态请全部放在本视图内（`@State` / `@StateObject`）。
///
/// 数据：`GameDataLoader.dataIfAvailable(for: .heroes)` → `Resources/heroes.json`
/// 的原始 JSON；未内置（文件缺失或仍是占位内容）时为 nil，页面需降级显示。
struct HeroStatsView: View {
    private enum DataStatus {
        case loading
        case missing
        case available(byteCount: Int)
    }

    @State private var status: DataStatus = .loading

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
                Text("角色属性")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                Text("《黑夜君临》各夜行者逐等级属性，以及装备转职遗物后的属性")
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
            }
        }
    }

    private var placeholderCard: some View {
        VStack(alignment: .leading, spacing: 15) {
            SectionHeading(
                title: "功能开发中",
                subtitle: "页面脚手架已就绪，业务逻辑请在 HeroStatsView.swift 内实现",
                symbol: "person.text.rectangle"
            )

            HStack(spacing: 8) {
                switch status {
                case .loading:
                    Pill(text: "正在检查数据文件…", color: AppTheme.purpleSoft)
                case .missing:
                    Pill(text: "数据未内置", color: AppTheme.amber, symbol: "exclamationmark.triangle")
                    Text("尚未提供 Resources/heroes.json，运行 scripts/sync-data.sh 同步后重新构建")
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                case .available(let byteCount):
                    Pill(text: "数据已内置", color: AppTheme.green, symbol: "checkmark.circle")
                    Text("heroes.json · \(byteCount) 字节")
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                }
            }

            Text("数据文件：Resources/heroes.json，通过 GameDataLoader.dataIfAvailable(for: .heroes) 读取；"
                 + "加载器只返回原始 Data，业务模型请在自己的文件里定义。")
                .font(.caption2)
                .foregroundStyle(AppTheme.tertiaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .appCard()
    }

    private func reload() {
        if let data = GameDataLoader.dataIfAvailable(for: .heroes) {
            status = .available(byteCount: data.count)
        } else {
            status = .missing
        }
    }
}
