import Foundation

/// The conversions made ahead for the live preview: the last few, by the exact Latin text. A conversion is final
/// (the model's, which Enter may use) or quick (the rules', shown only until the model's arrives).
public final class PreviewCache: @unchecked Sendable {  // `items` is behind `lock`
    private let lock = NSLock()
    private var items: [(latin: String, arabic: String, final: Bool)] = []
    private let isClitic: @Sendable (String) -> Bool

    public init(isClitic: @escaping @Sendable (String) -> Bool) { self.isClitic = isClitic }

    /// A conversion made ahead: final (Enter may send it) only when the model made it. A rule fallback is shown
    /// until the model's answer arrives, and Enter asks the engine again instead of sending the rules' Arabic.
    public func store(_ latin: String, _ arabic: String, fromModel: Bool) {
        set(latin, arabic, final: fromModel)
    }

    public func set(_ latin: String, _ arabic: String, final: Bool = true) {
        lock.withLock {
            if !final, items.contains(where: { $0.latin == latin && $0.final }) { return }
            items.removeAll { $0.latin == latin }
            items.append((latin, arabic, final))
            if items.count > 16 { items.removeFirst() }
        }
    }

    /// The final Arabic for exactly this text.
    public func arabic(for latin: String) -> String? {
        lock.withLock { items.last { $0.latin == latin && $0.final }?.arabic }
    }

    /// True when the last word of `latin` is a small word whose Arabic depends on the next one (el, w, b).
    public func endsWithClitic(_ latin: String) -> Bool {
        guard let last = latin.split(whereSeparator: \.isWhitespace).last else { return false }
        return isClitic(String(last))
    }

    /// What the preview window shows for the text typed so far: the Arabic of the longest converted start that ends
    /// at a word boundary, then the Latin typed since. A start ending in a small word (el, w, b) is not used, so
    /// a lone ال never shows before its word. nil when no start of the text is converted yet.
    public func display(for buffer: String) -> (arabic: String, latin: String, typedSince: Int)? {
        lock.withLock {
            let starts = items.filter { item in
                guard buffer.hasPrefix(item.latin), !endsWithClitic(item.latin) || item.latin.count == buffer.count
                else { return false }
                if item.latin.count == buffer.count || item.latin.last?.isWhitespace == true { return true }
                return buffer[buffer.index(buffer.startIndex, offsetBy: item.latin.count)].isWhitespace
            }
            guard let best = starts.max(by: { ($0.latin.count, $0.final ? 1 : 0) < ($1.latin.count, $1.final ? 1 : 0) })
            else { return nil }
            let head = best.arabic.trimmingCharacters(in: .whitespaces)
            let rest = String(buffer.dropFirst(best.latin.count)).trimmingCharacters(in: .whitespaces)
            return (head, rest, buffer.count - best.latin.count)
        }
    }
}
