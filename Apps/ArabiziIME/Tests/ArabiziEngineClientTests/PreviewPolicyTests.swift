import Testing
@testable import ArabiziEngineClient

@Test func withThePreviewOffTheKeyboardStillConvertsAhead() {
    // Enter then sends a ready answer instead of waiting for the engine.
    #expect(PreviewPolicy.convertsAhead("shu 3am ta3mel ", fixing: false))
    #expect(!PreviewPolicy.shows(livePreview: false, fixing: false))
}

@Test func nothingIsConvertedAheadWithoutLettersOrWhileFixing() {
    #expect(!PreviewPolicy.convertsAhead("123 😂", fixing: false))
    #expect(!PreviewPolicy.convertsAhead("shu", fixing: true))
    #expect(!PreviewPolicy.shows(livePreview: true, fixing: true))
    #expect(PreviewPolicy.shows(livePreview: true, fixing: false))
}
