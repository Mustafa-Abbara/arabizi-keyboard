import Testing

// Fails on purpose: this branch only shows that a pull request with a failing required check cannot be merged.
@Test func aFailingCheckBlocksTheMerge() {
    #expect(1 == 2)
}
