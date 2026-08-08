import SwiftUI
import UIKit

/// Apex Aspire tokens adapted for a native, data-dense product surface.
/// Apex Gauge uses the Apex Core / Apex Dev indigo register throughout.
enum ApexTheme {
    enum Colors {
        static let background = dynamic(light: 0xEEE9F2, dark: 0x15111F)
        static let surface = dynamic(light: 0xFFFFFF, dark: 0x211A2D)
        static let surfaceRaised = dynamic(light: 0xF8F6FA, dark: 0x2A2238)

        static let inkPrimary = dynamic(light: 0x2E1B5A, dark: 0xF7F3FA)
        static let inkSecondary = dynamic(light: 0x685A74, dark: 0xC9C0D0)
        static let inkTertiary = dynamic(light: 0x75677F, dark: 0xAFA3B9)
        static let inverseInk = Color.white

        static let accent = dynamic(light: 0x5E2B81, dark: 0xB89BDA)
        static let accentSoft = dynamic(light: 0xEEE7F4, dark: 0x382B49)
        static let border = dynamic(light: 0xD9D0E3, dark: 0x493C58)
        static let borderStrong = dynamic(light: 0x8E7CC3, dark: 0x74658C)

        static let success = dynamic(light: 0x287A50, dark: 0x69D19B)
        static let successSoft = dynamic(light: 0xE6F3EC, dark: 0x183A2B)
        static let warning = dynamic(light: 0x9A651C, dark: 0xE9B964)
        static let warningSoft = dynamic(light: 0xFBF0DE, dark: 0x43331D)
        static let danger = dynamic(light: 0xB73535, dark: 0xFF9292)
        static let dangerSoft = dynamic(light: 0xFBE8E8, dark: 0x472424)

        private static func dynamic(light: UInt32, dark: UInt32) -> Color {
            Color(uiColor: UIColor { traits in
                UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
            })
        }
    }

    enum Typography {
        static let displayLarge = Font.system(.largeTitle, design: .serif).weight(.regular)
        static let display = Font.system(.title, design: .serif).weight(.regular)
        static let displaySmall = Font.system(.headline, design: .rounded).weight(.semibold)
        static let metric = Font.system(.subheadline, design: .rounded).weight(.semibold).monospacedDigit()

        static let bodyLarge = Font.system(.title3, design: .default).weight(.regular)
        static let body = Font.system(.body, design: .default).weight(.regular)
        static let label = Font.system(.subheadline, design: .default).weight(.semibold)
        static let compact = Font.system(.subheadline, design: .default).weight(.medium)
        static let caption = Font.system(.caption, design: .default).weight(.regular)
        static let dataCaption = Font.system(.caption, design: .rounded).weight(.medium).monospacedDigit()
        static let eyebrow = Font.system(.caption2, design: .default).weight(.semibold)
        static let mono = Font.system(.footnote, design: .monospaced).weight(.regular)
    }

    enum Spacing {
        static let xSmall: CGFloat = 4
        static let small: CGFloat = 8
        static let medium: CGFloat = 12
        static let standard: CGFloat = 16
        static let large: CGFloat = 24
        static let xLarge: CGFloat = 32
        static let section: CGFloat = 48
        static let xxLarge: CGFloat = 64
        static let pageSection: CGFloat = 96
        static let heroSection: CGFloat = 128
    }

    enum Radius {
        static let xSmall: CGFloat = 4
        static let small: CGFloat = 6
        static let control: CGFloat = 8
        static let innerCard: CGFloat = 12
        static let card: CGFloat = 16
        static let featureCard: CGFloat = 20
        static let full: CGFloat = 9_999
    }

    enum Shadow {
        static let xSmallColor = Color.black.opacity(0.04)
        static let xSmallRadius: CGFloat = 1
        static let xSmallY: CGFloat = 1

        static let smallColor = Color.black.opacity(0.05)
        static let smallRadius: CGFloat = 3
        static let smallY: CGFloat = 2

        static let mediumColor = Color.black.opacity(0.06)
        static let mediumRadius: CGFloat = 16
        static let mediumY: CGFloat = 12

        static let largeColor = Color.black.opacity(0.08)
        static let largeRadius: CGFloat = 24
        static let largeY: CGFloat = 24
    }
}

private extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

private struct ApexSurfaceModifier: ViewModifier {
    let cornerRadius: CGFloat
    let elevated: Bool

    func body(content: Content) -> some View {
        content
            .background(ApexTheme.Colors.surface)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(ApexTheme.Colors.border, lineWidth: 1)
            }
            .shadow(
                color: elevated ? ApexTheme.Shadow.smallColor : .clear,
                radius: elevated ? ApexTheme.Shadow.smallRadius : 0,
                y: elevated ? ApexTheme.Shadow.smallY : 0
            )
    }
}

extension View {
    func apexSurface(
        cornerRadius: CGFloat = ApexTheme.Radius.card,
        elevated: Bool = true
    ) -> some View {
        modifier(ApexSurfaceModifier(cornerRadius: cornerRadius, elevated: elevated))
    }

    func apexFormStyle() -> some View {
        scrollContentBackground(.hidden)
            .background(ApexTheme.Colors.background)
            .tint(ApexTheme.Colors.accent)
    }

    func apexListRow() -> some View {
        listRowBackground(ApexTheme.Colors.surface)
    }
}
