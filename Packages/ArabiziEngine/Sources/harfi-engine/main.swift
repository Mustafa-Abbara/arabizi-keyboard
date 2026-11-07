// The engine for the Windows keyboard (ADR 0032): the same Engine as the Mac's XPC service, in a process of its own,
// so the model is loaded once and never inside the apps the keyboard runs in. The keyboard's core (HarfiCoreC) starts
// it when it finds none. It answers on the rules at once and loads the model in the background (its SHA-256 check
// reads the whole file). Requests arrive on a named pipe (EngineService.pipeName), one JSON line each: a
// ConvertRequest in, its ConvertResponse out; the line `status` gets the model state. One engine per user: a second
// one finds the pipe taken and quits. After half an hour without a request it quits, which frees the model's memory;
// the next conversion starts it again. Never logs user text: only states, outcomes and timings (engine.log).
import ArabiziContracts
import ArabiziCore
import ArabiziEngine
import Foundation
import WinSDK

/// What every thread of the engine shares (static constants: made once, safe from any thread).
enum Setup {
    /// The folder of harfi-engine.exe: config\, rules\ and models\ are next to it (Apps/HarfiWindows/install.ps1).
    static let folder: URL = {
        var path = [WCHAR](repeating: 0, count: 32_768)
        let length = Int(GetModuleFileNameW(nil, &path, DWORD(path.count)))
        return URL(fileURLWithPath: String(decoding: path[..<length], as: UTF16.self)).deletingLastPathComponent()
    }()
    /// The account this engine runs as (the same SID whether it was started from an elevated app or not).
    static let sid = EngineService.currentSID
    static let pipeName = sid.map(EngineService.pipeName(sid:))
    static let idleLimit: Duration = .seconds(30 * 60)
}

func log(_ message: String) {
    let stamp = ISO8601DateFormatter().string(from: Date())
    let line = Data("\(stamp) \(message)\n".utf8)
    let file = Setup.folder.appending(path: "engine.log")
    if let handle = try? FileHandle(forWritingTo: file) {
        handle.seekToEndOfFile()
        handle.write(line)
        try? handle.close()
    } else {
        try? line.write(to: file)
    }
}

final class Host: @unchecked Sendable {  // `engine`, `loading` and `lastUse` are behind `lock`
    private let lock = NSLock()
    private var engine: Engine
    private var loading = true
    private var lastUse = ContinuousClock.now
    private let decoder = JSONDecoder()

    init(rulesOnly: Engine) {
        engine = rulesOnly
        Thread.detachNewThread { [self] in
            let started = ContinuousClock.now
            do {
                let full = try Engine.load(configDirectory: Setup.folder.appending(path: "config"),
                                           rulesDirectory: Setup.folder.appending(path: "rules"),
                                           modelsDirectory: Setup.folder.appending(path: "models"))
                lock.withLock {
                    engine = full
                    loading = false
                }
                log("engine ready: \(full.modelState) in \(ContinuousClock.now - started)")
            } catch {
                lock.withLock { loading = false }
                log("engine failed to load, staying on the rules: \(error)")
            }
        }
    }

    /// The reply to one line: a ConvertResponse, the status, or an empty object for a line that cannot be read.
    func answer(_ line: Data) -> Data {
        let (current, stillLoading) = lock.withLock {
            lastUse = .now
            return (engine, loading)
        }
        if String(decoding: line, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines) == "status" {
            var status: [String: Any] = ["loading": stillLoading]
            switch current.modelState {
            case .off: status["state"] = "off"
            case .ready(let id): status["state"] = "ready"; status["model"] = id
            case .unavailable(let id, let reason):
                status["state"] = "unavailable"; status["model"] = id; status["reason"] = reason
            }
            return (try? JSONSerialization.data(withJSONObject: status, options: [.sortedKeys])) ?? Data("{}".utf8)
        }
        guard let request = try? decoder.decode(ConvertRequest.self, from: line) else { return Data("{}".utf8) }
        let response = current.convert(request)
        log("converted: \(response.outcome.rawValue) in \(response.latencyMs) ms")
        return (try? Contract.encoder().encode(response)) ?? Data("{}".utf8)
    }

    var idle: Bool { lock.withLock { ContinuousClock.now - lastUse > Setup.idleLimit } }
}

/// A pipe handle handed to the thread that serves it.
struct Pipe: @unchecked Sendable { let handle: HANDLE }

/// One instance of the pipe; `first` fails when another engine already owns the name. The account itself (by SID, so
/// an engine started from an elevated app still serves the account's normal apps), the system and app containers
/// (Store apps, the Start menu search box) may connect, from low integrity too; never from the network.
func makePipe(first: Bool) -> Pipe? {
    guard let sid = Setup.sid, let name = Setup.pipeName else { return nil }
    let rules = "D:(A;;GA;;;\(sid))(A;;GA;;;SY)(A;;GRGW;;;AC)S:(ML;;NW;;;LW)"
    var descriptor: PSECURITY_DESCRIPTOR?
    let described = rules.withCString(encodedAs: UTF16.self) {
        ConvertStringSecurityDescriptorToSecurityDescriptorW($0, DWORD(SDDL_REVISION_1), &descriptor, nil)
    }
    defer { if let descriptor { LocalFree(descriptor) } }
    var attributes = SECURITY_ATTRIBUTES(nLength: DWORD(MemoryLayout<SECURITY_ATTRIBUTES>.size),
                                         lpSecurityDescriptor: described ? descriptor : nil, bInheritHandle: false)
    var openMode = DWORD(PIPE_ACCESS_DUPLEX)
    if first { openMode |= DWORD(FILE_FLAG_FIRST_PIPE_INSTANCE) }
    let pipeMode = DWORD(PIPE_TYPE_BYTE | PIPE_READMODE_BYTE | PIPE_WAIT | PIPE_REJECT_REMOTE_CLIENTS)
    let handle = name.withCString(encodedAs: UTF16.self) {
        CreateNamedPipeW($0, openMode, pipeMode, DWORD(PIPE_UNLIMITED_INSTANCES), 65_536, 65_536, 0, &attributes)
    }
    guard let handle, handle != HANDLE(bitPattern: -1) else { return nil }  // INVALID_HANDLE_VALUE
    return Pipe(handle: handle)
}

/// Answers the lines one app sends until it disconnects.
func serve(_ pipe: Pipe, host: Host) {
    defer {
        DisconnectNamedPipe(pipe.handle)
        CloseHandle(pipe.handle)
    }
    var pending = Data()
    var buffer = [UInt8](repeating: 0, count: 65_536)
    while true {
        var read: DWORD = 0
        guard ReadFile(pipe.handle, &buffer, DWORD(buffer.count), &read, nil), read > 0 else { return }
        pending.append(contentsOf: buffer[..<Int(read)])
        while let newline = pending.firstIndex(of: 10) {
            let line = Data(pending[pending.startIndex..<newline])
            pending = Data(pending[pending.index(after: newline)...])
            var reply = host.answer(line)
            reply.append(10)
            let written = reply.withUnsafeBytes { bytes -> Bool in
                var done: DWORD = 0
                return WriteFile(pipe.handle, bytes.baseAddress, DWORD(bytes.count), &done, nil)
            }
            guard written else { return }
        }
    }
}

// Rules only until the model has loaded: the same config with the model switched off.
let rulesOnly: Engine
do {
    let config = Setup.folder.appending(path: "config")
    var json = try JSONSerialization.jsonObject(with: Data(contentsOf: config.appending(path: "engine.json")))
        as? [String: Any] ?? [:]
    json["features"] = ["use_model": false]
    let rulesConfig = try EngineConfig(engine: JSONSerialization.data(withJSONObject: json),
                                       models: Data(contentsOf: config.appending(path: "models.json")))
    rulesOnly = try Engine.load(config: rulesConfig, rulesDirectory: Setup.folder.appending(path: "rules"),
                                modelsDirectory: Setup.folder.appending(path: "models"))
} catch {
    log("engine cannot start (config or rule files missing): \(error)")
    exit(1)
}

guard let firstPipe = makePipe(first: true) else {
    let error = GetLastError()
    // Taken: another engine already runs for this account. Anything else is a real failure: say which.
    if error != DWORD(ERROR_ACCESS_DENIED) && error != DWORD(ERROR_PIPE_BUSY) {
        log("engine cannot open its pipe (error \(error)\(Setup.sid == nil ? ", no SID" : "")): quitting")
    }
    exit(0)
}
log("engine started on the rules; loading the model in the background")
let host = Host(rulesOnly: rulesOnly)

Thread.detachNewThread { [host] in
    while true {
        Thread.sleep(forTimeInterval: 60)
        if host.idle {
            log("idle for \(Setup.idleLimit): quitting")
            exit(0)
        }
    }
}

var next: Pipe? = firstPipe
while true {
    guard let pipe = next ?? makePipe(first: false) else {
        Thread.sleep(forTimeInterval: 1)
        continue
    }
    next = nil
    if ConnectNamedPipe(pipe.handle, nil) || GetLastError() == DWORD(ERROR_PIPE_CONNECTED) {
        Thread.detachNewThread { [host] in serve(pipe, host: host) }
    } else {
        CloseHandle(pipe.handle)
    }
}
