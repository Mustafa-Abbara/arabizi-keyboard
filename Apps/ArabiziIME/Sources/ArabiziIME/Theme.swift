import AppKit
import CoreText

/// The "Cedar and sand" colours (design/palette.json, same values), each following the system light or dark
/// appearance.
enum Theme {
    static let background = color(light: 0xF6F3EC, dark: 0x151B19)
    static let surface = color(light: 0xFFFFFF, dark: 0x1D2522)
    static let text = color(light: 0x1E2A25, dark: 0xE9EEEB)
    static let textMuted = color(light: 0x6B756F, dark: 0x93A099, contrast: (0x3A4440, 0xC9D2CD))
    static let border = color(light: 0xE4DFD4, dark: 0x2C3632, contrast: (0x6B756F, 0x93A099))
    static let accent = color(light: 0x2F6B5A, dark: 0x7DBBA5)
    static let accentSoft = color(light: 0xE2EEE8, dark: 0x21392F)
    static let warning = color(light: 0x9A6A1F, dark: 0xE0B062, contrast: (0x744D10, 0xF0C77E))

    /// "Larger text" in Harfi's window: the preview and the chips grow by this much.
    static var scale: CGFloat { Settings.largerText ? 1.3 : 1 }

    /// The Arabic of the preview, chips and window: Noto Naskh Arabic from Resources/Fonts (loaded for this app
    /// only), the system font if it cannot be loaded. Latin letters in it fall back to the system font.
    static func arabic(_ size: CGFloat) -> NSFont {
        _ = fontLoaded
        let descriptor = NSFontDescriptor(fontAttributes: [.family: "Noto Naskh Arabic"])
        return NSFont(descriptor: descriptor, size: size) ?? .systemFont(ofSize: size)
    }

    private static let fontLoaded: Bool = {
        guard let url = Bundle.main.url(forResource: "NotoNaskhArabic-Variable", withExtension: "ttf",
                                        subdirectory: "Fonts") else { return false }
        return CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    }()

    /// `contrast`: stronger light and dark values used when "Increase contrast" is on in macOS.
    private static func color(light: UInt32, dark: UInt32, contrast: (UInt32, UInt32)? = nil) -> NSColor {
        NSColor(name: nil) { appearance in
            let match = appearance.bestMatch(from: [.aqua, .darkAqua, .accessibilityHighContrastAqua,
                                                    .accessibilityHighContrastDarkAqua])
            let isDark = match == .darkAqua || match == .accessibilityHighContrastDarkAqua
            let strong = match == .accessibilityHighContrastAqua || match == .accessibilityHighContrastDarkAqua
            let hex = strong && contrast != nil ? (isDark ? contrast!.1 : contrast!.0) : (isDark ? dark : light)
            return NSColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255,
                           blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        }
    }
}
