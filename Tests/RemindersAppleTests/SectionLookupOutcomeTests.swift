import Testing

@testable import RemindersApple

@Suite("Each reminder's section from ReminderKit")
struct SectionLookupOutcomeTests {
  @Test("a returned section wins, even with an error set")
  func inSection() {
    #expect(SectionLookupOutcome(sectionID: "A", error: nil) == .inSection("A"))
    #expect(SectionLookupOutcome(sectionID: "A", error: ("com.apple.reminderkit", -3009)) == .inSection("A"))
  }

  @Test("ReminderKit's -3009, or no section and no error, means the reminder is in no section")
  func notInSection() {
    #expect(SectionLookupOutcome(sectionID: nil, error: ("com.apple.reminderkit", -3009)) == .notInSection)
    #expect(SectionLookupOutcome(sectionID: nil, error: nil) == .notInSection)
  }

  @Test("any other error is a real failure")
  func failed() {
    #expect(
      SectionLookupOutcome(sectionID: nil, error: ("com.apple.reminderkit", -3000))
        == .failed("com.apple.reminderkit -3000"))
    #expect(
      SectionLookupOutcome(sectionID: nil, error: ("NSCocoaErrorDomain", -3009)) == .failed("NSCocoaErrorDomain -3009"))
  }
}
