import CoreGraphics
import Testing
import ArabiziEngineClient

private let top: CGFloat = 1_000
private let preview: CGFloat = 40, chips: CGFloat = 70

@Test func withRoomThePreviewIsAboveTheLineAndTheChipsAboveIt() {
    let line = CGRect(x: 100, y: 300, width: 400, height: 20)
    let y = StackPlacement.y(for: line, height: preview, reserve: chips, top: top)
    #expect(y == line.maxY + StackPlacement.gap)
    let box = CGRect(x: 100, y: y, width: 300, height: preview)
    #expect(StackPlacement.y(beside: box, of: line, height: chips) == box.maxY + StackPlacement.gap)
}

@Test func whenThePreviewFitsAboveButNotTheChipsBothGoBelow() {
    // Room for the preview alone above the line, not for the chips over it: before, the chips fell back over
    // the preview and the text; now both go below the line, the chips under the preview.
    let line = CGRect(x: 100, y: top - 80, width: 400, height: 20)
    #expect(StackPlacement.fitsAbove(line, height: preview, reserve: 0, top: top))
    let y = StackPlacement.y(for: line, height: preview, reserve: chips, top: top)
    #expect(y == line.minY - preview - StackPlacement.gap)
    let box = CGRect(x: 100, y: y, width: 300, height: preview)
    let chipsY = StackPlacement.y(beside: box, of: line, height: chips)
    #expect(chipsY + chips + StackPlacement.gap == box.minY)
    #expect(chipsY + chips < line.minY)  // never over the text
}

@Test func aSideChosenWhenTheListOpenedIsKeptWhateverTheNextBoxNeeds() {
    let line = CGRect(x: 100, y: 500, width: 300, height: 20)
    // A tall box would not fit above under a top at 600, a short one would: the chosen side wins for both.
    #expect(StackPlacement.y(for: line, height: 200, top: 600, above: true) == line.maxY + StackPlacement.gap)
    #expect(StackPlacement.y(for: line, height: 20, top: 600, above: false) == line.minY - 20 - StackPlacement.gap)
    #expect(StackPlacement.isAbove(CGRect(x: 0, y: line.maxY + 6, width: 10, height: 10), line))
    #expect(!StackPlacement.isAbove(CGRect(x: 0, y: line.minY - 30, width: 10, height: 10), line))
}
