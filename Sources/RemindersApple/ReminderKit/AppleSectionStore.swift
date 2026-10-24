import RemindersCore

/// Sections on macOS, through ReminderKit only.
///
/// Reading, creating, deleting and moving reminders between sections all go through ReminderKit, so Reminders reads
/// and writes its own data (the memberships, their checksum and the sync metadata) and iCloud syncs the changes.
/// Nothing here touches Reminders' database, so no Full Disk Access is needed. Every change is read back afterwards,
/// and one that isn't there is reported as ``RemindersError/Code/writeNotApplied``, never as success. Where
/// ReminderKit can't answer, the error says so (``RemindersError/Code/reminderKitUnavailable``).
public struct AppleSectionStore: SectionStore {
  /// Receives one line per read saying where it came from (for `REMINDERS_DEBUG`).
  public typealias Diagnostics = ReminderKitDiagnostics

  private let reminderKit: any ReminderKitBridge
  private let diagnostics: Diagnostics?
  private let checkDelays: [Duration]

  /// - Parameter checkDelays: The waits before each read-back of a change after the first, giving Reminders time to
  ///   store it.
  public init(
    reminderKit: any ReminderKitBridge, diagnostics: Diagnostics? = nil,
    checkDelays: [Duration] = [.milliseconds(250), .milliseconds(500), .seconds(1), .seconds(2)]
  ) {
    self.reminderKit = reminderKit
    self.diagnostics = diagnostics
    self.checkDelays = checkDelays
  }

  // MARK: Reading

  public func sections(in list: ReminderList) async throws(RemindersError) -> [Section] {
    let fetched = try reminderKit.sections(in: list)
    let (arranged, order) = Self.arrange(fetched)
    diagnostics?("sections: reminderkit \(fetched.fetchSelector); order: \(order)")
    return arranged.enumerated().map { order, section in
      Section(id: section.id, displayName: section.displayName, listName: list.title, sortOrder: order)
    }
  }

  /// ReminderKit's sections in the order the user sees, and where that order came from.
  ///
  /// 1. The list's stored order, when a ReminderKit property of the list (or its storage) has it. None did on
  ///    macOS 27.0.1; sections it doesn't name follow, arranged as in 2.
  /// 2. Otherwise the fetch order. `fetchListSectionsInList:error:` already applies the order the user arranged
  ///    (on the Mac, the reordered scratch list came back Gamma, Alpha, Beta, as stored). With nothing stored it
  ///    returns them oldest first while the app shows newest first (Grocery), so a fetch order that is exactly
  ///    ascending `creationDate` is reversed.
  ///
  /// Edge case: a stored order that happens to be oldest first can't be told from no stored order, so it's shown
  /// newest first. Without creation dates the fetch order is kept as is.
  static func arrange(_ fetched: ReminderKitSections) -> ([ReminderKitSection], String) {
    let probed = fetched.orderProbes.isEmpty ? "" : " [probed: \(fetched.orderProbes.joined(separator: ", "))]"
    let rest: [ReminderKitSection]
    let source: String
    let dates = fetched.sections.compactMap(\.createdAt)
    if let key = fetched.creationDateSelector, dates.count == fetched.sections.count, dates.count > 1,
      zip(dates, dates.dropFirst()).allSatisfy({ $0 <= $1 })
    {
      rest = fetched.sections.reversed()
      source = "fetch order reversed (ascending \(key), so none arranged)"
    } else {
      rest = fetched.sections
      source = "fetch order"
    }
    guard let stored = fetched.storedOrderSelector else { return (rest, source + probed) }
    let order = SectionOrdering.arranged(rest, by: fetched.storedOrder, identifier: \.id)
    return (order, "reminderkit \(stored), then \(source)" + probed)
  }

  public func memberships(of list: ReminderList, reminderIDs: [String]) async throws(RemindersError)
    -> StoredMemberships
  {
    let found = try reminderKit.memberships(in: list, reminderIDs: reminderIDs)
    diagnostics?("memberships: reminderkit \(found.selector)")
    return StoredMemberships(entries: found.value)
  }

  /// The list's manual reminder order from ReminderKit, or nil when it isn't sorted manually or ReminderKit
  /// doesn't say.
  public func manualReminderOrder(of list: ReminderList) async -> [String]? {
    let found: ReminderKitRead<[String]?>?
    do throws(RemindersError) {
      found = try reminderKit.manualReminderOrder(in: list)
    } catch {
      diagnostics?("manual order: reminderkit failed (\(error.code.rawValue): \(error.message))")
      return nil
    }
    diagnostics?("manual order: " + (found.map { "reminderkit \($0.selector)" } ?? "none"))
    return found?.value
  }

  // MARK: Changing

  public func createSection(named name: String, in list: ReminderList) async throws(RemindersError) -> Section {
    let created = try reminderKit.createSection(named: name, in: list)
    let saved = try await confirm("section \"\(name)\" isn't in \"\(list.title)\" after saving") {
      () async throws(RemindersError) in
      let sections = try await sections(in: list)
      return sections.contains { $0.id.caseInsensitiveCompare(created.id) == .orderedSame } ? sections : nil
    }
    return saved.first { $0.id.caseInsensitiveCompare(created.id) == .orderedSame }
      ?? Section(id: created.id, displayName: created.displayName, listName: list.title, sortOrder: saved.count)
  }

  public func deleteSection(_ section: Section, in list: ReminderList) async throws(RemindersError) {
    try reminderKit.deleteSection(id: section.id, in: list)
    _ = try await confirm("section \"\(section.displayName)\" is still in \"\(list.title)\" after saving") {
      () async throws(RemindersError) in
      try await sections(in: list).contains { $0.id.caseInsensitiveCompare(section.id) == .orderedSame } ? nil : true
    }
  }

  public func assign(reminderID: String, to section: Section, in list: ReminderList) async throws(RemindersError) {
    try reminderKit.assign(reminderID: reminderID, toSectionID: section.id, in: list)
    _ = try await confirm("the reminder isn't in section \"\(section.displayName)\" after saving") {
      () async throws(RemindersError) in
      let now = try SectionMemberships(storedData: await memberships(of: list, reminderIDs: [reminderID]).data)
      return now.section(of: reminderID)?.caseInsensitiveCompare(section.id) == .orderedSame ? true : nil
    }
  }

  /// Reads a change back until `check` finds it, waiting between tries; ``RemindersError/writeNotApplied(_:)`` when
  /// it never does.
  private func confirm<T>(_ missing: String, _ check: () async throws(RemindersError) -> T?)
    async throws(RemindersError)
    -> T
  {
    for (attempt, delay) in ([nil] + checkDelays.map(Optional.some)).enumerated() {
      if let delay { try? await Task.sleep(for: delay) }
      if let found = try await check() {
        diagnostics?("write: read back, applied (check \(attempt + 1))")
        return found
      }
    }
    diagnostics?("write: read back, NOT applied after \(checkDelays.count + 1) checks")
    throw .writeNotApplied(missing)
  }
}
