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

  /// ReminderKit's sections in the order the user sees, and where that order came from.
  ///
  /// 1. The list's stored order through ReminderKit, when a property of the list (or its storage) has it.
  /// 2. Otherwise the database, when it can be read: its `ZSECTIONIDSORDERINGASDATA`, then creation order (`Z_PK`).
  ///    This also places sections a ReminderKit order doesn't name.
  /// 3. Otherwise newest `creationDate` first, then reverse fetch order. Both match what the Mac showed for a list
  ///    without a stored order: the app's order (the database's `Z_PK` order) was the exact reverse of ReminderKit's
  ///    fetch order and of ascending `creationDate`.
  private func arrange(_ fetched: ReminderKitSections, in list: ReminderList) async -> ([ReminderKitSection], String) {
    let named = Set(fetched.storedOrder.map { $0.uppercased() })
    let stored = fetched.storedOrderSelector.map { "reminderkit \($0)" }
    if let stored, !fetched.sections.contains(where: { !named.contains($0.id.uppercased()) }) {
      return (DatabaseRows.arranged(fetched.sections, by: fetched.storedOrder, identifier: \.id), stored)
    }
    let probed = fetched.orderProbes.isEmpty ? "" : " [probed: \(fetched.orderProbes.joined(separator: ", "))]"
    let rest: [ReminderKitSection]
    let source: String
    if let saved = try? await database.sections(in: list) {
      rest = DatabaseRows.arranged(fetched.sections, by: saved.map(\.id), identifier: \.id)
      source = "database (ZSECTIONIDSORDERINGASDATA, then Z_PK)"
    } else if let key = fetched.creationDateSelector, fetched.sections.allSatisfy({ $0.createdAt != nil }) {
      rest = fetched.sections.enumerated().sorted { first, second in
        let (earlier, later) = (first.element.createdAt ?? .distantPast, second.element.createdAt ?? .distantPast)
        return earlier != later ? earlier > later : first.offset < second.offset
      }.map(\.element)
      source = "reminderkit \(key), newest first (database unreadable)"
    } else {
      rest = fetched.sections.reversed()
      source = "reversed fetch order (database unreadable)"
    }
    let order = DatabaseRows.arranged(rest, by: fetched.storedOrder, identifier: \.id)
    return (order, (stored.map { "\($0), then " } ?? "none in reminderkit, ") + source + probed)
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
