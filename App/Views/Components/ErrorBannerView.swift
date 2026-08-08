import SwiftUI

struct ErrorBannerView: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "exclamationmark.triangle")
            .font(ApexTheme.Typography.caption)
            .foregroundStyle(ApexTheme.Colors.danger)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(ApexTheme.Spacing.medium)
            .background(
                ApexTheme.Colors.dangerSoft,
                in: RoundedRectangle(
                    cornerRadius: ApexTheme.Radius.innerCard,
                    style: .continuous
                )
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius: ApexTheme.Radius.innerCard,
                    style: .continuous
                )
                .stroke(ApexTheme.Colors.danger.opacity(0.35), lineWidth: 1)
            }
            .accessibilityElement(children: .combine)
    }
}
