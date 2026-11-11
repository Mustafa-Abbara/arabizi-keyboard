import Testing
@testable import ArabiziEngineClient

private func cache() -> PreviewCache { PreviewCache(isClitic: { ["el", "w", "b"].contains($0) }) }

@Test func aRuleFallbackIsShownButNeverSentByEnter() {
    let previews = cache()
    previews.store("shu 3am ", "شو عم", fromModel: false)  // the model was still loading
    #expect(previews.display(for: "shu 3am ta3")?.arabic == "شو عم")  // shown in the box meanwhile
    #expect(previews.arabic(for: "shu 3am ") == nil)  // Enter asks the engine again
}

@Test func theModelsAnswerReplacesAFallbackAndAFallbackNeverReplacesIt() {
    let previews = cache()
    previews.store("kifak ", "كفك", fromModel: false)
    previews.store("kifak ", "كيفك", fromModel: true)
    #expect(previews.arabic(for: "kifak ") == "كيفك")
    previews.store("kifak ", "كفك", fromModel: false)  // a later fallback for the same text
    #expect(previews.arabic(for: "kifak ") == "كيفك")
}
