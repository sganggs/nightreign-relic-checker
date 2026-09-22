import SwiftUI
import UniformTypeIdentifiers

struct RootView: View {
    @EnvironmentObject private var model: AppModel

    /// 存档页自己有一层 `.onDrop`（`SaveScanView`），落在它上面的拖拽由它接手；
    /// 这里只在**不在存档页**时注册，接住落点不对的存档文件并给出提示，
    /// 免得用户以为拖拽功能坏了。传空类型数组等于不注册，保证在存档页上这一层
    /// 永远不会和页面自己的拖拽抢落点。
    private var strayDropTypes: [UTType] { model.page == .saveScan ? [] : [.fileURL] }

    var body: some View {
        VStack(spacing: 0) {
            TopBar()
            Group {
                switch model.page {
                case .checker: CheckerView()
                case .library: AffixLibraryView()
                case .data: DataSettingsView()
                case .saveScan: SaveScanView()
                // 以下四页各自一个文件，页面状态自持（见各文件顶部说明）。
                case .bosses: BossDataView()
                case .heroes: HeroStatsView()
                case .lookup: AffixLookupView()
                case .ranker: BuffRankerView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(AppTheme.background.ignoresSafeArea())
        .tint(AppTheme.purpleSoft)
        .onDrop(of: strayDropTypes, isTargeted: nil, perform: handleStrayDrop)
        .overlay(alignment: .top) {
            if !model.strayDropHint.isEmpty {
                StrayDropBanner(text: model.strayDropHint)
            }
        }
        .overlay {
            if let error = model.loadError {
                EmptyStateView(title: "词条库载入失败", symbol: "exclamationmark.triangle", detail: error)
                .padding(36)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
            }
        }
    }

    /// 落点不在存档页：只提示，不偷偷替用户切页载入（与 Windows 端一致）。
    private func handleStrayDrop(_ providers: [NSItemProvider]) -> Bool {
        let identifier = UTType.fileURL.identifier
        guard providers.contains(where: { $0.hasItemConformingToTypeIdentifier(identifier) }) else {
            return false
        }
        model.strayDropHint = "请切到「存档检查」页，再把存档文件松开"
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_200_000_000)
            model.strayDropHint = ""
        }
        return false
    }
}

/// 落点提示条（Windows 端是 toast，这里用顶部浮条，几秒后自己消失）。
private struct StrayDropBanner: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(AppTheme.amber.opacity(0.45), lineWidth: 1))
            .shadow(color: .black.opacity(0.35), radius: 14, y: 6)
            .padding(.top, 78)
            .transition(.move(edge: .top).combined(with: .opacity))
            .allowsHitTesting(false)
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
