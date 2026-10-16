import Foundation

/// The keyboard's link to the sandboxed engine service (roadmap P5 step 5, ADR 0020). Messages are the JSON forms of
/// ConvertRequest and ConvertResponse, so the XPC boundary uses the same versioned contracts as arabizi-cli.
@objc public protocol ArabiziEngineServiceProtocol {
    /// A JSON ConvertRequest in; a JSON ConvertResponse out (empty Data if the request could not be read).
    func convert(_ request: Data, reply: @escaping @Sendable (Data) -> Void)
    /// A JSON object about the service: model state, whether it is still loading, and a network probe that must fail
    /// (the service has no network entitlement). Never contains user text.
    func status(reply: @escaping @Sendable (Data) -> Void)
}

public enum EngineService {
    /// The service's bundle identifier; it lives in the keyboard app at Contents/XPCServices/.
    public static let name = "lb.aub.arabizi.inputmethod.ArabiziIME.Engine"
}
