import SwiftUI

/// Shared visual language for WeighTrace: one accent, one surface language, one page backdrop.
enum AppTheme {
    static let accent = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(red: 0.39, green: 0.85, blue: 0.65, alpha: 1)
            : UIColor(red: 0.06, green: 0.40, blue: 0.29, alpha: 1)
    })
    static let secondaryAccent = Color.cyan
    static let warning = Color.orange
    static let canvas = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(red: 0.055, green: 0.075, blue: 0.065, alpha: 1)
            : UIColor(red: 0.96, green: 0.955, blue: 0.935, alpha: 1)
    })
    static let surface = Color(uiColor: .secondarySystemGroupedBackground)
    static let hero = Color(red: 0.065, green: 0.18, blue: 0.145)

    static var heroGradient: LinearGradient {
        LinearGradient(
            colors: [accent.opacity(0.32), secondaryAccent.opacity(0.10), accent.opacity(0.04)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

extension View {
    /// Full-page tinted backdrop. Apply to the scroll container's background.
    func appScreenBackground() -> some View {
        self.background(AppTheme.canvas.ignoresSafeArea())
    }

    /// Standard elevated card: soft fill, hairline border, no heavy shadow.
    func appCard(padding: CGFloat = 18) -> some View {
        self
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(.primary.opacity(0.06)))
    }

    /// Hero card for the main number of the page.
    func appHeroCard(padding: CGFloat = 22) -> some View {
        self
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppTheme.heroGradient, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(AppTheme.accent.opacity(0.22)))
    }

    /// Compact tile inside a grid.
    func appTile() -> some View {
        self
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(.primary.opacity(0.06)))
    }

    /// Keep content readable on wide windows (iPad / Mac Catalyst).
    func appContentWidth(_ width: CGFloat = 720) -> some View {
        self.frame(maxWidth: width).frame(maxWidth: .infinity)
    }
}

/// Small capsule used for tags, ADC indicators and statuses.
struct AppBadge: View {
    let title: String
    var systemImage: String? = nil
    var tint: Color = AppTheme.accent

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage { Image(systemName: systemImage) }
            Text(title)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(tint)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(tint.opacity(0.12), in: Capsule())
    }
}
