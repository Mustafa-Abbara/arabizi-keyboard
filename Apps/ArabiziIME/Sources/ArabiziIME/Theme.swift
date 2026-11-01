import AppKit

/// The "Cedar and sand" colours (design/palette.json, same values), each following the system light or dark
/// appearance.
enum Theme {
    static let background = color(light: 0xF6F3EC, dark: 0x151B19)
    static let surface = color(light: 0xFFFFFF, dark: 0x1D2522)
    static let text = color(light: 0x1E2A25, dark: 0xE9EEEB)
    static let textMuted = color(light: 0x6B756F, dark: 0x93A099)
    static let border = color(light: 0xE4DFD4, dark: 0x2C3632)
    static let accent = color(light: 0x2F6B5A, dark: 0x7DBBA5)
    static let accentSoft = color(light: 0xE2EEE8, dark: 0x21392F)

    private static func color(light: UInt32, dark: UInt32) -> NSColor {
        NSColor(name: nil) { appearance in
            let hex = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255,
                           blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        }
    }
}
