import SwiftUI
import AppKit

/// Step 7 (plans/voxflow-windowed-ui.md): the visual direction Mihir picked
/// from the design canvas ("Direction D") — A's restrained blue accent and
/// neutral background, combined with B's warmer, more personal card
/// treatment. Tokens below are lifted directly from that mockup's color
/// values (light/dark pairs), not re-derived. One substitution from the
/// mockup: B's heading font was Google's Lora (a bundled web font); here
/// we use macOS's own native serif (New York, via SwiftUI's `.serif` font
/// design) instead of embedding a third-party font file — same "warm serif
/// heading" effect, zero asset/licensing overhead, and it's already on
/// every Mac.
enum VoxFlowTheme {
    static let accent = Color(light: Color(hex: 0x0A5FD6), dark: Color(hex: 0x6EA8E8))
    static let pageBackground = Color(light: Color(hex: 0xEEF0F4), dark: Color(hex: 0x1C1E22))
    static let sidebarBackground = Color(light: Color(hex: 0xF2F3F6), dark: Color(hex: 0x1E2024))
    static let contentBackground = Color(light: Color(hex: 0xFFFFFF), dark: Color(hex: 0x16171A))
    static let primaryText = Color(light: Color(hex: 0x1C1E24), dark: Color(hex: 0xF0F1F3))
    static let secondaryText = Color(light: Color(hex: 0x696D76), dark: Color(hex: 0x9A9EA6))
    static let labelText = Color(light: Color(hex: 0x8A8E96), dark: Color(hex: 0x7A7E86))
    // Concrete (non-dynamic) tints on each side, not derived from `accent`
    // itself — wrapping one dynamic Color inside another's light/dark
    // arms doesn't reliably stay dynamic through the NSColor conversion.
    static let cardBackground = Color(light: Color(hex: 0x0A5FD6).opacity(0.06), dark: Color.white.opacity(0.05))
    static let selectedBackground = Color(light: Color(hex: 0x0A5FD6).opacity(0.09), dark: Color.white.opacity(0.08))
    static let streakBackground = Color(light: Color(hex: 0x0A5FD6), dark: Color(hex: 0x26344A))
    static let onAccentText = Color(hex: 0xF5F8FF)
    static let cardCornerRadius: CGFloat = 12

    /// The mockup's serif heading voice, applied via SwiftUI's built-in
    /// serif design (New York) rather than a bundled font — see the enum
    /// doc comment.
    static func heading(_ size: CGFloat = 22, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }
}

private extension Color {
    init(hex: UInt32) {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >> 8) & 0xFF) / 255
        let b = Double(hex & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }

    /// Adapts automatically to the system's light/dark appearance — backed
    /// by `NSColor`'s dynamic-provider mechanism (the standard way to do
    /// this on macOS/AppKit-hosted SwiftUI), not a static value.
    init(light: Color, dark: Color) {
        self.init(NSColor(name: nil, dynamicProvider: { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                ? NSColor(dark)
                : NSColor(light)
        }))
    }
}
