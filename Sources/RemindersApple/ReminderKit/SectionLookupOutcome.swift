/// What `REMListSectionsDataView fetchListSectionWithReminderID:error:` said about one reminder.
enum SectionLookupOutcome: Equatable, Sendable {
  case inSection(String)
  /// The reminder is in no section.
  case notInSection
  /// A real failure, as `domain code`.
  case failed(String)

  /// ReminderKit's error domain.
  static let reminderKitDomain = "com.apple.reminderkit"
  /// The code ReminderKit answers with for a reminder in no section (seen on macOS 27.0.1).
  static let notInSectionCode = -3009

  /// - Parameters:
  ///   - sectionID: The returned section's identifier, if a section came back.
  ///   - error: The error's domain and code, if one was set.
  init(sectionID: String?, error: (domain: String, code: Int)?) {
    if let sectionID {
      self = .inSection(sectionID)
    } else if let error, error.domain == Self.reminderKitDomain && error.code == Self.notInSectionCode {
      self = .notInSection
    } else if let error {
      self = .failed("\(error.domain) \(error.code)")
    } else {
      self = .notInSection
    }
  }
}
