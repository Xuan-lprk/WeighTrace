import SwiftUI

struct AppPageHeader: View {
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("WEIGHTRACE").font(.caption2.weight(.bold)).tracking(3).foregroundStyle(AppTheme.accent)
            Text(title).font(.system(.largeTitle, design: .rounded, weight: .bold))
            Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 8)
    }
}

struct AppRouteCard<Destination: View>: View {
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    let icon: String
    @ViewBuilder let destination: Destination
    var body: some View {
        NavigationLink { destination } label: {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: icon).font(.title3).foregroundStyle(AppTheme.accent)
                    .frame(width: 42, height: 42)
                    .background(AppTheme.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 14))
                VStack(alignment: .leading, spacing: 6) {
                    Text(title).font(.headline).foregroundStyle(.primary)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right").font(.caption.weight(.semibold)).foregroundStyle(AppTheme.accent)
            }.appCard()
        }.buttonStyle(.plain)
    }
}

struct EmptyStateView: View {
    let title: LocalizedStringKey
    let icon: String
    let message: LocalizedStringKey
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 30))
                .foregroundStyle(AppTheme.accent)
                .frame(width: 64, height: 64)
                .background(AppTheme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            Text(title).font(.headline)
            Text(message).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 32)
    }
}

struct MetricTile: View {
    let title: LocalizedStringKey; let valueString: String; let icon: String
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(AppTheme.accent)
                .frame(width: 30, height: 30)
                .background(AppTheme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(valueString).font(.system(.headline, design: .rounded, weight: .bold))
        }
        .appTile()
    }
}
