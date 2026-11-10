import Foundation

/// How sure the model was of each word of the last few conversions, by the text shown (words joined by one space,
/// without direction marks): the engine's `wordConfidence`, kept while the user may still press ↑, so the fix starts
/// on the least sure word. Only kept when there is one value per word. In memory only, the last 32.
public final class WordConfidences: @unchecked Sendable {  // `items` is behind `lock`
    private let lock = NSLock()
    private var items: [(text: String, confidence: [Double])] = []

    public init() {}

    public func remember(_ shown: String, _ confidence: [Double]?) {
        let key = Self.key(shown)
        guard let confidence, confidence.count == key.split(separator: " ").count else { return }
        lock.withLock {
            items.removeAll { $0.text == key }
            items.append((key, confidence))
            if items.count > 32 { items.removeFirst() }
        }
    }

    public func of(_ converted: String) -> [Double]? {
        let key = Self.key(converted)
        return lock.withLock { items.last { $0.text == key }?.confidence }
    }

    private static func key(_ text: String) -> String {
        DirectionMarks.removed(text).split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
