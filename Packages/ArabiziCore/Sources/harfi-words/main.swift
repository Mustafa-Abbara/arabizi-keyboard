// The user's own words (ADR 0033), until the keyboard has a settings window ("Your words" on the Mac): the habits the
// keyboard has learned from repeated corrections, and the ones refused. Reads the same encrypted store as the
// keyboard, on this computer, and prints to the user's own terminal only.
//
//   harfi-words                 the habits in force, the refused ones, and how many fixes are recorded
//   harfi-words forget WORD     forgets every fix of the typed word (its habit goes with them)
//   harfi-words refuse WORD     stops the typed word's habit (it is not learned again until allowed)
//   harfi-words allow WORD      undoes a refusal
//   harfi-words wipe            forgets every fix and refusal
import ArabiziCore
import Foundation

func storeFolder() -> URL? {
    #if os(Windows)
    guard let local = ProcessInfo.processInfo.environment["LOCALAPPDATA"] else { return nil }
    return URL(fileURLWithPath: local).appending(path: "Harfi").appending(path: "words")
    #else
    return nil  // the Mac keyboard's own folder (CorrectionStore.standard)
    #endif
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

guard let store = CorrectionStore.standard(folder: storeFolder()) else { fail("The record of your words cannot be opened.") }
let arguments = Array(CommandLine.arguments.dropFirst())
let fixes = store.all()
let refused = store.refused()
let habits = Habits.learned(from: fixes)
let typed = arguments.count > 1 ? WordParts(arguments[1]).core.lowercased() : ""

switch arguments.first {
case nil, "list":
    let inForce = habits.filter { !refused.contains($0) }
    print(inForce.isEmpty ? "No habits yet: a word becomes one after you fix it the same way \(Habits.minimumPicks) times on \(Habits.minimumDays) days."
                          : "Harfi writes these your way:")
    for habit in inForce {
        let count = fixes.filter { WordParts($0.latin).core.lowercased() == habit.latin && $0.chosen == habit.spelling }.count
        print("  \(habit.latin)  →  \(habit.spelling)   (\(count) fixes)")
    }
    if !refused.isEmpty {
        print("Refused (not applied):")
        for habit in refused.sorted(by: { $0.latin < $1.latin }) { print("  \(habit.latin)  →  \(habit.spelling)") }
    }
    print("\(fixes.count) fixes recorded in the last 30 days.")
case "forget":
    guard arguments.count == 2 else { fail("Usage: harfi-words forget WORD") }
    let spellings = Set(fixes.filter { WordParts($0.latin).core.lowercased() == typed }.map(\.chosen))
    guard !spellings.isEmpty else { fail("No fixes of \(arguments[1]) are recorded.") }
    for spelling in spellings { try store.forget(latin: typed, chosen: spelling) }
    print("Forgot every fix of \(typed).")
case "refuse":
    guard arguments.count == 2, let habit = habits.first(where: { $0.latin == typed }) else {
        fail("\(arguments.dropFirst().first ?? "That word") has no habit.")
    }
    try store.refuse(habit)
    print("Harfi will not write \(habit.latin) as \(habit.spelling).")
case "allow":
    guard arguments.count == 2, let habit = refused.first(where: { $0.latin == typed }) else {
        fail("\(arguments.dropFirst().first ?? "That word") is not refused.")
    }
    try store.allow(habit)
    print("\(habit.latin) can be learned again.")
case "wipe":
    try store.wipe()
    print("Every fix and refusal is forgotten.")
default:
    fail("Usage: harfi-words [list | forget WORD | refuse WORD | allow WORD | wipe]")
}
