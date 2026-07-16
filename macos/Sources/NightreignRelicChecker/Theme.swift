import SwiftUI

enum AppTheme {
    static let background = Color(red: 0.035, green: 0.039, blue: 0.050)
    static let elevated = Color(red: 0.055, green: 0.059, blue: 0.074)
    static let card = Color(red: 0.065, green: 0.069, blue: 0.086)
    static let field = Color(red: 0.085, green: 0.090, blue: 0.110)
    static let border = Color.white.opacity(0.11)
    static let borderStrong = Color.white.opacity(0.18)
    static let purple = Color(red: 0.40, green: 0.30, blue: 0.91)
    static let purpleSoft = Color(red: 0.49, green: 0.39, blue: 0.98)
    static let green = Color(red: 0.22, green: 0.78, blue: 0.49)
    static let amber = Color(red: 0.95, green: 0.67, blue: 0.22)
    static let red = Color(red: 0.95, green: 0.35, blue: 0.39)
    static let secondaryText = Color.white.opacity(0.68)
    static let tertiaryText = Color.white.opacity(0.48)
}

struct CardModifier: ViewModifier {
    var padding: CGFloat = 20

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(AppTheme.card)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(AppTheme.border, lineWidth: 1)
                    )
            )
    }
}

extension View {
    func appCard(padding: CGFloat = 20) -> some View {
        modifier(CardModifier(padding: padding))
    }
}

struct Pill: View {
    let text: String
    var color: Color = AppTheme.purple
    var symbol: String? = nil

    var body: some View {
        HStack(spacing: 5) {
            if let symbol { Image(systemName: symbol).font(.caption2) }
            Text(text)
                .font(.caption.weight(.semibold))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(color.opacity(0.12), in: Capsule())
        .overlay(Capsule().stroke(color.opacity(0.22), lineWidth: 1))
    }
}

struct SectionHeading: View {
    let title: String
    let subtitle: String
    let symbol: String
    var tint: Color = AppTheme.purpleSoft

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }
}

struct EmptyStateView: View {
    let title: String
    let symbol: String
    let detail: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 42, weight: .light))
                .foregroundStyle(AppTheme.purpleSoft.opacity(0.72))
            Text(title).font(.title3.weight(.semibold))
            Text(detail)
                .font(.callout)
                .foregroundStyle(AppTheme.secondaryText)
                .multilineTextAlignment(.center)
        }
        .padding(28)
    }
}
