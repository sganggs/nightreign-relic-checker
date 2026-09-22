import SwiftUI
import RelicCore

/// 词条反查页（占位实现）。
///
/// 由「词条反查」功能开发者独占：只改本文件、以及自己新增的 RelicCore 文件与
/// RelicCoreChecks 检查文件；**不需要再改 AppModel / RootView**。
/// 因此页面状态请全部放在本视图内（`@State` / `@StateObject`）。
///
/// 数据：本页不需要新增数据文件，只读现有的
/// `model.catalog`（词条库）与 `model.relicData`（遗物物品表，可能为 nil）。
/// 需要索引时用 `RelicAuditContext(catalog:relicData:)`。
struct AffixLookupView: View {
    /// 只读地访问已载入的词条库 / 遗物物品表；请不要往 AppModel 上加本页状态。
    @EnvironmentObject private var model: AppModel

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
    }

    private var header: some View {
        HStack(spacing: 14) {
            LogoMark(size: 40)
            VStack(alignment: .leading, spacing: 4) {
                Text("词条反查")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                Text("由词条反查可能出现它的遗物与出货池")
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
            }
        }
    }

    private var placeholderCard: some View {
        VStack(alignment: .leading, spacing: 15) {
            SectionHeading(
                title: "功能开发中",
                subtitle: "页面脚手架已就绪，业务逻辑请在 AffixLookupView.swift 内实现",
                symbol: "magnifyingglass.circle"
            )

            HStack(spacing: 8) {
                Pill(
                    text: "词条库 \(model.catalog.affixes.count) 条",
                    color: model.catalog.affixes.isEmpty ? AppTheme.amber : AppTheme.green,
                    symbol: "checkmark.circle"
                )
                if model.relicData != nil {
                    Pill(text: "遗物物品表已内置", color: AppTheme.green, symbol: "checkmark.circle")
                } else {
                    Pill(text: "遗物物品表不可用", color: AppTheme.amber, symbol: "exclamationmark.triangle")
                }
            }

            Text("数据来源：model.catalog（affixes.json）与 model.relicData（relics.json）；"
                 + "两者都已由 AppModel 在启动时载入，本页只读不写。")
                .font(.caption2)
                .foregroundStyle(AppTheme.tertiaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .appCard()
    }
}
