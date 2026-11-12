import Foundation
import Testing
@testable import ArabiziEngineClient

struct ModelDownloadTests {
    private func folders() throws -> (app: URL, cache: URL) {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let app = root.appending(path: "ArabiziIME.app")
        let cache = root.appending(path: "cache")
        let files = FileManager.default
        try files.createDirectory(at: app.appending(path: "Contents/Resources"), withIntermediateDirectories: true)
        try files.createDirectory(at: app.appending(path: "Contents/XPCServices/ArabiziEngineXPC.xpc/Contents/Resources"),
                                  withIntermediateDirectories: true)
        try files.createDirectory(at: cache, withIntermediateDirectories: true)
        try "MODEL_ASSET=\"m.gguf\"\nMODEL_SIZE=\"1000\"\n"
            .write(to: app.appending(path: "Contents/Resources/model-download.txt"), atomically: true, encoding: .utf8)
        return (app, cache)
    }

    @Test func aModelInsideTheEngineIsReady() throws {
        let (app, cache) = try folders()
        try Data().write(to: app.appending(path: "Contents/XPCServices/ArabiziEngineXPC.xpc/Contents/Resources/x.gguf"))
        #expect(ModelDownload.state(app: app, cache: cache) == .ready)
    }

    @Test func partsWrittenJustNowAreADownloadGoingOn() throws {
        let (app, cache) = try folders()
        try Data(count: 300).write(to: cache.appending(path: "m.gguf.part01"))
        try Data(count: 100).write(to: cache.appending(path: "m.gguf.part02"))
        #expect(ModelDownload.state(app: app, cache: cache) == .downloading(fraction: 0.4))
    }

    @Test func partsLeftAloneMeanTheInstallerWasClosed() throws {
        let (app, cache) = try folders()
        try Data(count: 500).write(to: cache.appending(path: "m.gguf.part01"))
        #expect(ModelDownload.state(app: app, cache: cache, now: Date().addingTimeInterval(600)) == .stopped(fraction: 0.5))
        #expect(ModelDownload.state(app: app, cache: cache.appending(path: "none")) == .stopped(fraction: 0))
    }
}
