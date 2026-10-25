/// Character classes exactly as Python's `re` module sees them, so the Swift rule fallback splits text the same
/// way as the Python reference (eval/src/arabizi_eval/b0.py). Python works on code points, so these work on
/// Unicode scalars, never on Swift's grapheme clusters (Characters).
extension Unicode.Scalar {
    /// Python `\w` on a str: `_` or `str.isalnum()` (any letter category, or any character with a numeric value).
    var isPythonWord: Bool {
        if self == "_" { return true }
        switch properties.generalCategory {
        case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter:
            return true
        default:
            return properties.numericType != nil
        }
    }

    /// Python `\s` on a str: `str.isspace()`, which adds the file/group/record/unit separators to White_Space.
    var isPythonSpace: Bool {
        properties.isWhitespace || (0x1C...0x1F).contains(value)
    }
}

extension StringProtocol {
    var isPythonASCII: Bool { unicodeScalars.allSatisfy(\.isASCII) }
}
