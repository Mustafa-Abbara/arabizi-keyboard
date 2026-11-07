import Foundation
#if os(Windows)
import WinSDK
#endif

#if canImport(ObjectiveC)
/// The keyboard's link to the sandboxed engine service (roadmap P5 step 5, ADR 0020). Messages are the JSON forms of
/// ConvertRequest and ConvertResponse, so the XPC boundary uses the same versioned contracts as arabizi-cli.
@objc public protocol ArabiziEngineServiceProtocol {
    /// A JSON ConvertRequest in; a JSON ConvertResponse out (empty Data if the request could not be read).
    func convert(_ request: Data, reply: @escaping @Sendable (Data) -> Void)
    /// A JSON object about the service: model state, whether it is still loading, and a network probe that must fail
    /// (the service has no network entitlement). Never contains user text.
    func status(reply: @escaping @Sendable (Data) -> Void)
}
#endif

public enum EngineService {
    /// The service's bundle identifier; it lives in the keyboard app at Contents/XPCServices/.
    public static let name = "lb.aub.arabizi.inputmethod.ArabiziIME.Engine"

    /// The Windows engine's named pipe (ADR 0032) for the account with this SID (`S-1-5-21-…`): one engine process
    /// per account. Each message is one line of JSON: a ConvertRequest in, its ConvertResponse out. A SID, unlike a
    /// user name, is unique and never needs cleaning; the keyboard still checks who owns the pipe before writing.
    public static func pipeName(sid: String) -> String {
        #"\\.\pipe\harfi-engine-"# + sid
    }

    #if os(Windows)
    /// The pipe of the account this process runs as; nil if its SID cannot be read.
    public static var pipeName: String? { currentSID.map(pipeName(sid:)) }

    /// The SID of the account this process runs as (the same for its elevated and normal processes).
    public static var currentSID: String? {
        var token: HANDLE?
        guard OpenProcessToken(GetCurrentProcess(), DWORD(TOKEN_QUERY), &token), let token else { return nil }
        defer { CloseHandle(token) }
        return sid(of: token)
    }

    /// The SID of the account the process `process` runs as; nil if it cannot be read.
    public static func sid(ofProcess process: HANDLE) -> String? {
        var token: HANDLE?
        guard OpenProcessToken(process, DWORD(TOKEN_QUERY), &token), let token else { return nil }
        defer { CloseHandle(token) }
        return sid(of: token)
    }

    private static func sid(of token: HANDLE) -> String? {
        var size: DWORD = 0
        GetTokenInformation(token, TokenUser, nil, 0, &size)
        guard size > 0 else { return nil }
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: 8)
        defer { buffer.deallocate() }
        guard GetTokenInformation(token, TokenUser, buffer, size, &size) else { return nil }
        let user = buffer.load(as: TOKEN_USER.self)
        var text: LPWSTR?
        guard ConvertSidToStringSidW(user.User.Sid, &text), let text else { return nil }
        defer { LocalFree(text) }
        return String(decodingCString: text, as: UTF16.self)
    }
    #endif
}
