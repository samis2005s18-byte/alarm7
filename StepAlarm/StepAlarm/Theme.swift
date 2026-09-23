import SwiftUI
import UIKit

/// The app's whole design system in one place: colors, spacing, radii, and
/// haptics. Colors are system-adaptive (light + dark mode) except the single
/// accent red, which stays constant so it reads as *the* brand color in
/// either appearance rather than shifting per mode.
enum Theme {
    // MARK: Colors
    static let background = Color(.systemBackground)
    static let surface = Color(.secondarySystemBackground)
    /// A vibrant, saturated red — matches the onboarding flow's red exactly
    /// (#FF3B30) so the whole app reads as one consistent brand color.
    /// Reserved for the Wake Up screen's step ring and error/warning text;
    /// everything else in the app stays monochrome.
    static let accent = Color(red: 1, green: 0.231, blue: 0.188)    // #FF3B30
    /// The "active" color for toggles, selected states, and primary
    /// buttons everywhere except the step ring — keeps the rest of the
    /// app black/white/gray instead of sprinkling the accent around.
    static let neutralActive = Color(.systemGray)
    static let textPrimary = Color(.label)
    static let textSecondary = Color(.secondaryLabel)
    static let textDisabled = Color(.tertiaryLabel)
    /// Hairline edge that keeps a flat card from reading as a dead
    /// rectangle against the background, in either appearance.
    static let cardStroke = Color.primary.opacity(0.08)

    // MARK: Spacing — 8pt grid
    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 16
        static let lg: CGFloat = 24
        static let xl: CGFloat = 32
    }

    // MARK: Shape
    static let cardRadius: CGFloat = 20
    static let chipRadius: CGFloat = 14
    /// Apple HIG minimum — every tappable control should be at least this big.
    static let minTapTarget: CGFloat = 44

    // MARK: Haptics
    /// A single light tap, used consistently anywhere a control's state
    /// changes from a direct touch (toggle, selection, step change).
    static func tap() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    /// A stronger confirmation, used for things that finish or commit
    /// (alarm saved, alarm dismissed by walking).
    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}

/// Every tappable control in the app uses this so press feedback feels the
/// same everywhere: a quick, subtle scale-down rather than nothing at all.
struct PressableButtonStyle: ButtonStyle {
    var scale: CGFloat = 0.97

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PressableButtonStyle {
    static var pressable: PressableButtonStyle { PressableButtonStyle() }
}
