/// A deliberately tiny letter-by-letter converter for the P1 spike, so the keyboard has something to insert.
/// It is NOT the rule baseline (B0, P3) or the model (P4–P5): it converts English words too and ignores context.
public enum ToyTransliterator {
    static let digraphs: [String: String] = [
        "sh": "ش", "ch": "ش", "kh": "خ", "gh": "غ", "th": "ت",
        "aa": "ا", "ee": "ي", "ei": "ي", "ay": "ي", "oo": "و", "ou": "و",
    ]
    static let consonants: [Character: String] = [
        "b": "ب", "t": "ت", "j": "ج", "g": "ج", "d": "د", "r": "ر", "z": "ز", "s": "س", "f": "ف",
        "q": "ق", "k": "ك", "c": "ك", "l": "ل", "m": "م", "n": "ن", "h": "ه", "w": "و", "y": "ي",
        "v": "ف", "p": "ب", "x": "كس",
        "2": "ء", "3": "ع", "5": "خ", "6": "ط", "7": "ح", "8": "ق", "9": "ص",
    ]
    static let punctuation: [Character: Character] = ["?": "؟", ",": "،", ";": "؛"]
    static let trimmable = Set("?,;!.:\"'()")

    public static func convert(_ text: String) -> String {
        text.split(separator: " ", omittingEmptySubsequences: false)
            .map { convertToken(String($0)) }
            .joined(separator: " ")
    }

    static func convertToken(_ token: String) -> String {
        var core = Substring(token)
        var tail = ""
        while let last = core.last, trimmable.contains(last) {
            tail = String(punctuation[last] ?? last) + tail
            core = core.dropLast()
        }
        var head = ""
        while let first = core.first, trimmable.contains(first) {
            head += String(punctuation[first] ?? first)
            core = core.dropFirst()
        }
        // A standalone number (100, 2pm is not one: it has letters) is kept as typed.
        let keep = core.isEmpty || !core.contains(where: \.isLetter)
        return head + (keep ? String(core) : convertWord(core.lowercased())) + tail
    }

    static func convertWord(_ word: String) -> String {
        let chars = Array(word)
        var out = ""
        var i = 0
        while i < chars.count {
            let isFirst = i == 0
            if i + 1 < chars.count, let mapped = digraphs[String(chars[i...i + 1])] {
                out += isFirst && "ae".contains(chars[i]) ? (chars[i] == "a" ? "أ" : "إ") : mapped
                i += 2
                continue
            }
            let char = chars[i]
            let isLast = i == chars.count - 1
            switch char {
            case "a":
                out += isFirst ? "أ" : (isLast ? "ا" : "")
            case "e":
                out += isFirst ? "إ" : (isLast ? "ي" : "")
            case "i":
                out += isFirst ? "إ" : "ي"
            case "o", "u":
                out += isFirst ? "أ" : "و"
            default:
                if let mapped = consonants[char] {
                    let doubled = i > 0 && chars[i - 1] == char
                    out += doubled ? "" : mapped
                } else {
                    out.append(char)
                }
            }
            i += 1
        }
        return out
    }
}
