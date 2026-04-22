import SwiftUI
import AppKit
import CoreText

// MARK: - Theme

enum KinTheme: String, CaseIterable {
    case dark, light

    var label: String {
        switch self {
        case .dark:  "Dark"
        case .light: "Light"
        }
    }

    // Fixed preview colors for swatch cards (always static regardless of current theme)
    var previewSidebar: Color {
        switch self {
        case .dark:  Color(hex: "#000000")!
        case .light: Color(hex: "#F3F3F4")!
        }
    }

    var previewContent: Color {
        switch self {
        case .dark:  Color(hex: "#0d0d12")!
        case .light: Color(hex: "#f5f5ff")!
        }
    }
}

// MARK: - Kin design tokens

enum Kin {
    // Resolved at draw time via NSColor's dynamic provider — updates automatically
    // when .preferredColorScheme(.dark/.light) is set on any ancestor view.
    private static func adaptive(dark: String, light: String) -> Color {
        Color(nsColor: NSColor(name: nil) { trait in
            NSColor(srgbHex: trait.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? dark : light)!
        })
    }

    // Surfaces & containers
    static let bg               = adaptive(dark: "#0d0d12", light: "#f5f5ff")  // main content area
    static let sidebarBg        = adaptive(dark: "#000000", light: "#F3F3F4")  // channel sidebar
    static let serverBg         = adaptive(dark: "#000000", light: "#E8E8EA")  // 72px server strip
    static let surface          = adaptive(dark: "#1a1a22", light: "#ebebf7")  // cards, code blocks
    static let surfaceHover     = adaptive(dark: "#252530", light: "#dededf")  // hover states
    static let profileBar       = adaptive(dark: "#090910", light: "#dcdcea")  // profile bar bg
    static let inputBg          = adaptive(dark: "#13131a", light: "#ededfa")  // chat input bg
    static let searchBarBg      = adaptive(dark: "#0a0a10", light: "#e4e4f0")  // sidebar search pill
    static let chatSearchBg     = adaptive(dark: "#09090e", light: "#f0f0fc")  // chat header search
    static let avatarBg         = adaptive(dark: "#22222e", light: "#c4c4d8")  // default avatar circle

    // Borders
    static let border           = adaptive(dark: "#18181f", light: "#d8d8e8")  // dividers
    static let chatBorder       = adaptive(dark: "#1e1e28", light: "#dedeed")  // chat header border
    static let chatSearchBorder = adaptive(dark: "#1a1a28", light: "#d0d0e0")  // chat search border

    // Accent & selection
    static let accent           = adaptive(dark: "#949CF7", light: "#6c74f0")  // blurple CTA
    static let sidebarSelected  = adaptive(dark: "#1a1a24", light: "#d0d0e4")  // selected row bg

    // Text hierarchy
    static let textPrimary      = adaptive(dark: "#dcddde", light: "#111111")  // body text
    static let textSecondary    = adaptive(dark: "#b9bbbe", light: "#444444")  // muted labels
    static let textTertiary     = adaptive(dark: "#8e9297", light: "#666666")  // timestamps
    static let textQuaternary   = adaptive(dark: "#72767d", light: "#888888")  // placeholders
    static let codeText         = adaptive(dark: "#c9d1d9", light: "#1a1a2e")  // code mono text

    // Fixed status colors — universal across themes
    static let statusOnline     = Color(hex: "#3BA55D")!
    static let statusSnooze     = Color(hex: "#FAA61A")!
    static let statusOffline    = Color(hex: "#ED4245")!

    static var errorBg: Color   { Color.red.opacity(0.06) }

    // MARK: - Inter variable font

    static func inter(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        let variationKey = NSFontDescriptor.AttributeName(rawValue: kCTFontVariationAttribute as String)
        let descriptor = NSFontDescriptor(fontAttributes: [
            .name: "InterVariable",
            variationKey: [2003265652: interWght(weight)]   // 0x77676874 = 'wght' tag
        ])
        if let nsFont = NSFont(descriptor: descriptor, size: size) {
            return Font(nsFont)
        }
        return .system(size: size)
    }

    private static func interWght(_ weight: Font.Weight) -> Double {
        switch weight {
        case .ultraLight: return 100
        case .thin:       return 200
        case .light:      return 300
        case .regular:    return 400
        case .medium:     return 500
        case .semibold:   return 600
        case .bold:       return 700
        case .heavy:      return 800
        case .black:      return 900
        default:          return 400
        }
    }
}

// MARK: - Color hex init

extension Color {
    init?(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        guard Scanner(string: hex).scanHexInt64(&int) else { return nil }
        switch hex.count {
        case 6:
            self.init(
                red: Double((int >> 16) & 0xFF) / 255,
                green: Double((int >> 8) & 0xFF) / 255,
                blue: Double(int & 0xFF) / 255
            )
        default:
            return nil
        }
    }
}

// MARK: - NSColor sRGB hex init (used by adaptive helper above)

extension NSColor {
    convenience init?(srgbHex hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        guard Scanner(string: hex).scanHexInt64(&int), hex.count == 6 else { return nil }
        self.init(
            srgbRed: Double((int >> 16) & 0xFF) / 255,
            green:   Double((int >> 8)  & 0xFF) / 255,
            blue:    Double(int         & 0xFF) / 255,
            alpha:   1
        )
    }
}

// MARK: - NSVisualEffectView wrapper

struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

// MARK: - Dual-layer shadows

extension View {
    func shadowSm() -> some View {
        self
            .shadow(color: .black.opacity(0.04), radius: 0.5, y: 0.5)
            .shadow(color: .black.opacity(0.06), radius: 1.5, y: 1)
    }

    func shadowMd() -> some View {
        self
            .shadow(color: .black.opacity(0.04), radius: 1, y: 1)
            .shadow(color: .black.opacity(0.08), radius: 8, y: 4)
    }

    func shadowLg() -> some View {
        self
            .shadow(color: .black.opacity(0.03), radius: 2, y: 2)
            .shadow(color: .black.opacity(0.10), radius: 16, y: 8)
    }
}

// MARK: - Stagger reveal

struct StaggerReveal: ViewModifier {
    let index: Int
    let delay: Double
    @State private var visible = false

    func body(content: Content) -> some View {
        content
            .opacity(visible ? 1.0 : 0.0)
            .offset(y: visible ? 0 : 12)
            .animation(
                .spring(response: 0.4, dampingFraction: 0.85)
                    .delay(Double(index) * delay),
                value: visible
            )
            .onAppear { visible = true }
    }
}

extension View {
    func staggerReveal(index: Int, delay: Double = 0.05) -> some View {
        modifier(StaggerReveal(index: index, delay: delay))
    }
}

// MARK: - Conditional modifier

extension View {
    @ViewBuilder
    func `if`<Transform: View>(_ condition: Bool, transform: (Self) -> Transform) -> some View {
        if condition { transform(self) } else { self }
    }
}

// MARK: - Agent presence status

enum AgentStatus {
    case online   // active in last 5 min — green
    case snooze   // inactive 5–10 min — yellow moon
    case offline  // no messages or > 10 min — red
}

// MARK: - Press scale button style

struct PressScaleButtonStyle: ButtonStyle {
    var scale: CGFloat = 0.94
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(.spring(response: 0.2, dampingFraction: 0.72), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PressScaleButtonStyle {
    static var pressScale: Self { .init() }
}
