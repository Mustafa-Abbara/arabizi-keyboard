import Foundation

/// Invisible marks that keep a sentence mixing Arabic and English in its reading order in any app.
///
/// An app lays a line out left to right when it is a left-to-right field (Notepad, Word, most text boxes) or when the
/// line starts with a Latin letter (apps that take the direction from the first letter: WhatsApp, browsers). Then
/// `ok منشوف ال meeting بكرا` shows its Arabic and English pieces left to right, out of order for an Arabic reader.
/// A right-to-left embedding (RLE … PDF) makes the sentence one right-to-left run in any layout, and a right-to-left
/// mark (RLM) in front makes apps that look at the first letter take the line as right to left. Text without both
/// Arabic and Latin letters is left as it is.
public enum DirectionMarks {
    static let rightToLeftMark: Unicode.Scalar = "\u{200F}"
    static let rightToLeftEmbedding: Unicode.Scalar = "\u{202B}"
    static let popDirectionalFormatting: Unicode.Scalar = "\u{202C}"
    static let all: Set<Unicode.Scalar> = [rightToLeftMark, rightToLeftEmbedding, popDirectionalFormatting]

    /// The text with the marks around it when it mixes Arabic and Latin letters; otherwise unchanged (any old marks
    /// removed, so marking twice gives the same text).
    public static func marked(_ text: String) -> String {
        let plain = removed(text)
        guard mixesScripts(plain) else { return plain }
        return String(rightToLeftMark) + String(rightToLeftEmbedding) + plain + String(popDirectionalFormatting)
    }

    /// The text without these marks.
    public static func removed(_ text: String) -> String {
        guard text.unicodeScalars.contains(where: all.contains) else { return text }
        return String(String.UnicodeScalarView(text.unicodeScalars.filter { !all.contains($0) }))
    }

    /// True when the text has both an Arabic letter and a Latin letter.
    static func mixesScripts(_ text: String) -> Bool {
        var arabic = false, latin = false
        for scalar in text.unicodeScalars {
            if (0x0621...0x064A).contains(scalar.value) || (0x0671...0x06D3).contains(scalar.value) { arabic = true }
            if scalar.isASCII && scalar.properties.isAlphabetic { latin = true }
            if arabic && latin { return true }
        }
        return false
    }
}
