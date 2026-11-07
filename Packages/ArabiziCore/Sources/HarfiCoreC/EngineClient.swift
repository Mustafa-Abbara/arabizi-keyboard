#if os(Windows)
import ArabiziContracts
import ArabiziCore
import Foundation
import WinSDK

/// The keyboard's side of harfi-engine on Windows (ADR 0032), as the Mac keyboard's EngineClient is for its XPC
/// service: send the Latin text, wait at most the deadline plus a margin, and return the converted text, or nil so
/// the keyboard uses its own rules. When no engine is running it starts one (harfi-engine.exe next to the keyboard)
/// and uses the rules this time; the engine loads the model in the background. Never logs or keeps the text.
final class EngineClient: @unchecked Sendable {  // `lastStart` is behind `lock`
    /// How long past the deadline the keyboard waits for the reply (the rule fallback inside the engine).
    static let replyMarginMs = 500
    /// At most one start attempt this often, so a missing or crashing engine never slows typing down.
    static let startEverySeconds: TimeInterval = 15

    private let config: EngineConfig
    private let engine: URL
    private let pipeName: String
    private let lock = NSLock()
    private var lastStart: Date?

    /// nil without the config or harfi-engine.exe: the keyboard then keeps to its own rules.
    init?(folder: URL) {
        let engine = folder.appending(path: "harfi-engine.exe")
        guard FileManager.default.fileExists(atPath: engine.path),
              let config = try? EngineConfig(configDirectory: folder.appending(path: "config")) else { return nil }
        self.config = config
        self.engine = engine
        pipeName = EngineService.pipeName(user: Self.userName())
    }

    /// Starts the engine early, when the keyboard is first used, so the model is loaded before the first Enter.
    func warmUp() {
        if let pipe = open() { CloseHandle(pipe) } else { start() }
    }

    func convert(_ text: String) -> String? {
        let deadlineMs = config.deadlineMs(for: text)  // longer messages get longer (ADR 0025)
        guard var request = try? Contract.encoder().encode(ConvertRequest(text: text, deadlineMs: deadlineMs)) else {
            return nil
        }
        guard let pipe = open() else {
            start()
            return nil
        }
        defer { CloseHandle(pipe) }
        request.append(10)
        let started = Date()
        guard write(request, to: pipe),
              let line = readLine(from: pipe, within: deadlineMs + Self.replyMarginMs, since: started),
              let response = try? JSONDecoder().decode(ConvertResponse.self, from: line) else { return nil }
        return response.text
    }

    // MARK: - the pipe

    private static var invalid: HANDLE? { HANDLE(bitPattern: -1) }  // INVALID_HANDLE_VALUE

    private static func userName() -> String {
        var name = [WCHAR](repeating: 0, count: 257)
        var size = DWORD(name.count)
        guard GetUserNameW(&name, &size), size > 0 else { return "user" }
        return String(decoding: name[..<Int(size - 1)], as: UTF16.self)
    }

    /// A connection to the running engine, or nil when there is none (or it stays busy).
    private func open() -> HANDLE? {
        for _ in 0..<2 {
            let handle = pipeName.withCString(encodedAs: UTF16.self) {
                CreateFileW($0, DWORD(GENERIC_READ) | DWORD(GENERIC_WRITE), 0, nil, DWORD(OPEN_EXISTING),
                            DWORD(FILE_FLAG_OVERLAPPED), nil)
            }
            if let handle, handle != Self.invalid { return handle }
            guard GetLastError() == DWORD(ERROR_PIPE_BUSY) else { return nil }
            _ = pipeName.withCString(encodedAs: UTF16.self) { WaitNamedPipeW($0, 200) }
        }
        return nil
    }

    /// Runs harfi-engine.exe on its own (no window, outside the app's job when allowed), at most once per interval.
    private func start() {
        let due = lock.withLock { () -> Bool in
            if let last = lastStart, Date().timeIntervalSince(last) < Self.startEverySeconds { return false }
            lastStart = Date()
            return true
        }
        guard due else { return }
        var command = Array("\"\(engine.path)\"".utf16) + [0]
        let directory = Array(engine.deletingLastPathComponent().path.utf16) + [0]
        for flags in [DWORD(DETACHED_PROCESS | CREATE_NO_WINDOW | CREATE_BREAKAWAY_FROM_JOB),
                      DWORD(DETACHED_PROCESS | CREATE_NO_WINDOW)] {
            var startup = STARTUPINFOW()
            startup.cb = DWORD(MemoryLayout<STARTUPINFOW>.size)
            var process = PROCESS_INFORMATION()
            let started = directory.withUnsafeBufferPointer { folder in
                CreateProcessW(nil, &command, nil, nil, false, flags, nil, folder.baseAddress, &startup, &process)
            }
            if started {
                CloseHandle(process.hThread)
                CloseHandle(process.hProcess)
                return
            }
        }
    }

    private func write(_ data: Data, to pipe: HANDLE) -> Bool {
        guard let event = CreateEventW(nil, true, false, nil) else { return false }
        defer { CloseHandle(event) }
        var overlapped = OVERLAPPED()
        overlapped.hEvent = event
        return data.withUnsafeBytes { bytes -> Bool in
            if !WriteFile(pipe, bytes.baseAddress, DWORD(bytes.count), nil, &overlapped),
               GetLastError() != DWORD(ERROR_IO_PENDING) { return false }
            var written: DWORD = 0
            return GetOverlappedResult(pipe, &overlapped, &written, true) && Int(written) == bytes.count
        }
    }

    /// One reply line, or nil when it does not come within `milliseconds` of `since`.
    private func readLine(from pipe: HANDLE, within milliseconds: Int, since: Date) -> Data? {
        guard let event = CreateEventW(nil, true, false, nil) else { return nil }
        defer { CloseHandle(event) }
        let size = 65_536
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: size)
        defer { buffer.deallocate() }
        var line = Data()
        while true {
            let left = milliseconds - Int(Date().timeIntervalSince(since) * 1000)
            guard left > 0 else { return nil }
            var overlapped = OVERLAPPED()
            overlapped.hEvent = event
            ResetEvent(event)
            var read: DWORD = 0
            if !ReadFile(pipe, buffer, DWORD(size), nil, &overlapped) {
                guard GetLastError() == DWORD(ERROR_IO_PENDING) else { return nil }
                if WaitForSingleObject(event, DWORD(left)) != WAIT_OBJECT_0 {
                    CancelIoEx(pipe, &overlapped)
                    GetOverlappedResult(pipe, &overlapped, &read, true)  // the buffer is free only once it is done
                    return nil
                }
            }
            guard GetOverlappedResult(pipe, &overlapped, &read, false), read > 0 else { return nil }
            line.append(buffer, count: Int(read))
            if let newline = line.firstIndex(of: 10) { return Data(line[line.startIndex..<newline]) }
        }
    }
}

/// The engine's conversions made ahead for the live preview, by the exact Latin text, as on the Mac (PreviewCache and
/// PreviewWork): one worker converts the newest request, then any newer one, so the preview catches up with fast
/// typing; Enter takes a ready one instead of asking again. Kept in memory only, the last few.
final class PreviewConversions: @unchecked Sendable {  // everything is behind `lock`
    private let lock = NSLock()
    private let engine: EngineClient
    private var items: [(latin: String, arabic: String)] = []
    private var failed: Set<String> = []  // not asked again, so a missing engine never keeps the preview waiting
    private var pending: String?
    private var running = false

    init(engine: EngineClient) { self.engine = engine }

    func arabic(for latin: String) -> String? {
        lock.withLock { items.last { $0.latin == latin }?.arabic }
    }

    /// Asks for `latin` in the background unless it is ready, failed or already asked; true while it is coming.
    func request(_ latin: String) -> Bool {
        let start = lock.withLock { () -> Bool? in
            if items.contains(where: { $0.latin == latin }) || failed.contains(latin) { return nil }
            if pending == latin { return false }
            pending = latin
            if running { return false }
            running = true
            return true
        }
        guard let start else { return false }
        if start { Thread.detachNewThread { [self] in work() } }
        return true
    }

    private func work() {
        while let next = lock.withLock({ () -> String? in
            guard let latin = pending else {
                running = false
                return nil
            }
            pending = nil
            return latin
        }) {
            let arabic = engine.convert(next)
            lock.withLock {
                if let arabic {
                    items.removeAll { $0.latin == next }
                    items.append((next, arabic))
                    if items.count > 16 { items.removeFirst() }
                } else {
                    if failed.count > 64 { failed.removeAll() }
                    failed.insert(next)
                }
            }
        }
    }
}
#endif
