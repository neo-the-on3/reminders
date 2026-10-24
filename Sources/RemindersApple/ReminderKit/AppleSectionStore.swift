import RemindersCore

/// Sections on macOS, through ReminderKit, with Reminders' database as the fallback for reads.
///
/// Creating, deleting and moving reminders between sections go through ReminderKit only, so Reminders writes the
/// data and its checksum and iCloud syncs them; nothing here writes the database. Every change is read back
/// afterwards, and one that isn't there is reported as ``RemindersError/Code/writeNotApplied``, never as success.
///
/// Reads go through ReminderKit too when it exposes what's asked for, which needs no Full Disk Access. Where it
/// can't answer (a part missing on this macOS version, any error, or memberships it doesn't expose), they come from
/// the database, which does need Full Disk Access.
public struct AppleSectionStore: SectionStore {
  /// Receives one line per read saying where it came from (for `REMINDERS_DEBUG`).
  public typealias Diagnostics = ReminderKitDiagnostics

  private let database: any SectionStore
  private let reminderKit: any ReminderKitBridge
  private let readsThroughReminderKit: Bool
  private let diagnostics: Diagnostics?
  private let checkDelays: [Duration]

  /// - Parameters:
  ///   - readsThroughReminderKit: False to read only from the database, as before ReminderKit reads.
  ///   - checkDelays: The waits before each read-back of a change after the first, giving Reminders time to store it.
  public init(
    database: any SectionStore, reminderKit: any ReminderKitBridge, readsThroughReminderKit: Bool = true,
    diagnostics: Diagnostics? = nil,
    checkDelays: [Duration] = [.milliseconds(250), .milliseconds(500), .seconds(1), .seconds(2)]
  ) {
    self.database = database
    self.reminderKit = reminderKit
    self.readsThroughReminderKit = readsThroughReminderKit
    self.diagnostics = diagnostics
    self.checkDelays = checkDelays
  }

  // MARK: Reading

  public func sections(in list: ReminderList) async throws(RemindersError) -> [Section] {
    guard let fetched = read("sections", { () throws(RemindersError) in try reminderKit.sections(in: list) }) else {
      diagnostics?("sections: database")
      return try await database.sections(in: list)
    }
    let (arranged, order) = await arrange(fetched, in: list)
    diagnostics?("sections: reminderkit \(fetched.fetchSelector); order: \(order)")
    return arranged.enumerated().map { order, section in
      Section(id: section.id, displayName: section.displayName, listName: list.title, sortOrder: order)
    }
  }

  /// ReminderKit's sections in the order the user sees, and how that order was found.
  ///
  /// The list's stored order comes first. Sections it doesn't name (all of them when it's NULL, as for a list whose
  /// sections were never rearranged) go in creation order, as Reminders shows them: by creation date when
  /// ReminderKit exposes one, else as the database orders them (by `Z_PK`), else in reverse fetch order. The last
  /// rests on what the Mac showed: with a NULL stored order, `fetchListSectionsInList:error:` returned Grocery's
  /// four sections exactly newest first.
  private func arrange(_ fetched: ReminderKitSections, in list: ReminderList) async -> ([ReminderKitSection], String) {
    let named = Set(fetched.storedOrder.map { $0.uppercased() })
    let stored = fetched.storedOrderSelector ?? "none"
    guard fetched.sections.contains(where: { !named.contains($0.id.uppercased()) }) else {
      return (DatabaseRows.arranged(fetched.sections, by: fetched.storedOrder, identifier: \.id), stored)
    }
    let byCreation: [ReminderKitSection]
    let creation: String
    if let key = fetched.creationDateSelector, fetched.sections.allSatisfy({ $0.createdAt != nil }) {
      byCreation = fetched.sections.enumerated().sorted {
        ($0.element.createdAt ?? .distantPast, $0.offset) < ($1.element.createdAt ?? .distantPast, $1.offset)
      }.map(\.element)
      creation = "creation date (\(key))"
    } else if let saved = try? await database.sections(in: list) {
      byCreation = DatabaseRows.arranged(fetched.sections, by: saved.map(\.id), identifier: \.id)
      creation = "database order (Z_PK)"
    } else {
      byCreation = fetched.sections.reversed()
      creation = "reversed fetch order"
    }
    return (DatabaseRows.arranged(byCreation, by: fetched.storedOrder, identifier: \.id), "\(stored), then \(creation)")
  }

  public func memberships(of list: ReminderList) async throws(RemindersError) -> StoredMemberships {
    let found = read("memberships", { () throws(RemindersError) in try reminderKit.memberships(in: list) })
    if let found {
      diagnostics?("memberships: reminderkit \(found.selector)")
      return found.value
    }
    diagnostics?("memberships: database")
    return try await database.memberships(of: list)
  }

  /// The list's manual reminder order from ReminderKit, or nil when it isn't sorted manually or ReminderKit
  /// doesn't say.
  public func manualReminderOrder(of list: ReminderList) async -> [String]? {
    let found = read("manual order", { () throws(RemindersError) in try reminderKit.manualReminderOrder(in: list) })
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
    // The current memberships go with the change (see ``ReminderKitBridge/assign(reminderID:toSectionID:in:keeping:)``),
    // and are needed to read it back, so a list whose memberships can't be read isn't changed.
    let current = try SectionMemberships(storedData: await memberships(of: list).data).current
    try reminderKit.assign(reminderID: reminderID, toSectionID: section.id, in: list, keeping: current)
    _ = try await confirm("the reminder isn't in section \"\(section.displayName)\" after saving") {
      () async throws(RemindersError) in
      let now = try SectionMemberships(storedData: await memberships(of: list).data)
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

  /// A ReminderKit read, or nil to fall back to the database: when reads through ReminderKit are off, it doesn't
  /// expose the value, or it fails in any way. Reads never change anything, so the database's answer (or error)
  /// is as good.
  private func read<T>(_ what: String, _ body: () throws(RemindersError) -> T?) -> T? {
    guard readsThroughReminderKit else {
      diagnostics?("\(what): reminderkit off (\(RemindersPlatform.sectionsFromDatabaseVariable)=1)")
      return nil
    }
    do throws(RemindersError) {
      let value = try body()
      if value == nil { diagnostics?("\(what): reminderkit exposes no getter") }
      return value
    } catch {
      diagnostics?("\(what): reminderkit failed (\(error.code.rawValue): \(error.message))")
      return nil
    }
  }
}
