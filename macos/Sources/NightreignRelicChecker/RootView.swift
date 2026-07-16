import SwiftUI

struct RootView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            TopBar()
            Group {
                switch model.page {
                case .checker: CheckerView()
                case .library: AffixLibraryView()
                case .data: DataSettingsView()
                case .saveScan: SaveScanView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(AppTheme.background.ignoresSafeArea())
        .tint(AppTheme.purpleSoft)
        .overlay {
            if let error = model.loadError {
                EmptyStateView(title: "词条库载入失败", symbol: "exclamationmark.triangle", detail: error)
                .padding(36)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
            }
        }
    }
}

private struct TopBar: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(spacing: 18) {
            HStack(spacing: 11) {
                LogoMark(size: 36)
                VStack(alignment: .leading, spacing: 1) {
                    Text("夜幕验物")
                        .font(.system(size: 18, weight: .black, design: .rounded))
                    Text("黑夜君临 · 离线遗物检查器")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(AppTheme.secondaryText)
                }
            }

            Rectangle()
                .fill(AppTheme.border)
                .frame(width: 1, height: 30)

            HStack(spacing: 5) {
                ForEach(AppModel.Page.allCases) { page in
                    Button {
                        withAnimation(.easeOut(duration: 0.16)) { model.page = page }
                    } label: {
                        Label(page.title, systemImage: page.symbol)
                            .font(.system(size: 13, weight: .semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .foregroundStyle(model.page == page ? Color.white : AppTheme.secondaryText)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(model.page == page ? AppTheme.purple : Color.clear)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer()

            HStack(spacing: 8) {
                Pill(text: model.catalog.gameVersion, color: AppTheme.green, symbol: "checkmark.circle")
                Pill(text: "完全离线", color: AppTheme.purpleSoft, symbol: "wifi.slash")
            }
        }
        .padding(.leading, 76)
        .padding(.trailing, 18)
        .frame(height: 66)
        .background(AppTheme.elevated.opacity(0.97))
        .overlay(alignment: .bottom) {
            Rectangle().fill(AppTheme.border).frame(height: 1)
        }
    }
}

struct LogoMark: View {
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [AppTheme.purpleSoft.opacity(0.35), AppTheme.purple.opacity(0.06)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .trim(from: 0.08, to: 0.47)
                    .stroke(AppTheme.purpleSoft, style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
                    .rotationEffect(.degrees(Double(index) * 120 + 10))
                    .padding(2)
            }
            Image(systemName: "checkmark")
                .font(.system(size: size * 0.34, weight: .black))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
        .shadow(color: AppTheme.purple.opacity(0.48), radius: 12)
    }
}
