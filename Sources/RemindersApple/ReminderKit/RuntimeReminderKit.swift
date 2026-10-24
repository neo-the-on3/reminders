#if os(macOS)
  import Foundation
  import ObjectiveC
  import RemindersCore

  /// ``ReminderKitBridge`` on the real framework, loaded through the Objective-C runtime when first used.
  ///
  /// Nothing links against ReminderKit, so `reminders` starts, and everything but sections works, even where it's
  /// missing or different. Each call checks every class and method it's about to use and reports a missing one as
  /// ``RemindersError/Code/reminderKitUnavailable``. The calls are the ones the Reminders app makes: a `REMStore`
  /// with data views to find accounts, lists and sections, and a `REMSaveRequest` to change them.
  public struct RuntimeReminderKit: ReminderKitBridge {
    static let frameworkPath = "/System/Library/PrivateFrameworks/ReminderKit.framework"

    private let diagnostics: ReminderKitDiagnostics?

    /// - Parameter diagnostics: Receives each write step: the selectors sent, the classes they returned, and the
    ///   save's result and error.
    public init(diagnostics: ReminderKitDiagnostics? = nil) {
      self.diagnostics = diagnostics
    }

    public func sections(in list: ReminderList) throws(RemindersError) -> ReminderKitSections {
      try withSession { session throws(RemindersError) in
        let storage = try session.storage(of: list).list
        let objects = try session.sections(of: storage)
        let dateKey = ReminderKitSession.creationDateKey(of: objects)
        var probes: [String] = []
        let order = ReminderKitSession.sectionOrder(of: storage, probes: &probes)
        return ReminderKitSections(
          sections: objects.compactMap { ReminderKitSession.section($0, creationDateKey: dateKey) },
          storedOrder: order?.value ?? [], storedOrderSelector: order?.selector, creationDateSelector: dateKey,
          orderProbes: probes)
      }
    }

    public func memberships(in list: ReminderList, reminderIDs: [String]?) throws(RemindersError)
      -> ReminderKitRead<[SectionMemberships.Entry]>
    {
      try withSession { session throws(RemindersError) in
        try session.memberships(of: try session.storage(of: list).list, reminderIDs: reminderIDs)
      }
    }

    public func manualReminderOrder(in list: ReminderList) throws(RemindersError) -> ReminderKitRead<[String]?>? {
      try withSession { session throws(RemindersError) in
        ReminderKitSession.manualReminderOrder(of: try session.storage(of: list).list)
      }
    }

    public func createSection(named name: String, in list: ReminderList) throws(RemindersError)
      -> ReminderKitSection
    {
      try withSession { session throws(RemindersError) in try session.createSection(named: name, in: list) }
    }

    public func deleteSection(id: String, in list: ReminderList, clearing members: [String]) throws(RemindersError) {
      try withSession { session throws(RemindersError) in
        try session.deleteSection(id: id, in: list, clearing: members)
      }
    }

    public func assign(reminderID: String, toSectionID sectionID: String, in list: ReminderList)
      throws(RemindersError)
    {
      try withSession { session throws(RemindersError) in
        try session.assign(reminderID: reminderID, toSectionID: sectionID, in: list)
      }
    }

    /// Runs `body` on a fresh session, draining what ReminderKit autoreleases.
    func withSession<T>(_ body: (ReminderKitSession) throws(RemindersError) -> T) throws(RemindersError)
      -> T
    {
      let result: Result<T, RemindersError> = autoreleasepool {
        do throws(RemindersError) {
          return .success(try body(try ReminderKitSession(log: diagnostics)))
        } catch {
          return .failure(error)
        }
      }
      return try result.get()
    }
  }

  /// One connection to Reminders' store, with the data views that read it.
  struct ReminderKitSession {
    let store: NSObject
    let accountsView: NSObject
    let listsView: NSObject
    let sectionsView: NSObject
    let log: ReminderKitDiagnostics?

    init(log: ReminderKitDiagnostics? = nil) throws(RemindersError) {
      self.log = log
      try Runtime.loadFramework()
      store = try Runtime.make("REMStore")
      accountsView = try Runtime.make("REMAccountsDataView", initWithStore: store)
      listsView = try Runtime.make("REMListsDataView", initWithStore: store)
      sectionsView = try Runtime.make("REMListSectionsDataView", initWithStore: store)
    }

    // MARK: Reading

    /// The list's ReminderKit object and its account: matched by identifier, or else by a name only one list has.
    func storage(of list: ReminderList) throws(RemindersError) -> (list: NSObject, account: NSObject) {
      var candidates: [(list: NSObject, account: NSObject)] = []
      for account in try Runtime.fetch("fetchAllAccountsWithError:", on: accountsView) {
        for storage in try Runtime.fetch("fetchListsInAccount:error:", on: listsView, account) {
          if Runtime.identifier(of: storage) == list.id.uppercased() { return (storage, account) }
          if Runtime.string(storage, "displayName") == list.title { candidates.append((storage, account)) }
        }
      }
      guard candidates.count == 1, let only = candidates.first else {
        throw RemindersError(
          .listNotFound, "ReminderKit can't find exactly one list \"\(list.title)\"",
          suggestion: "If it was just created or renamed, wait a moment for Reminders to save it and try again")
      }
      return only
    }

    func sections(of list: NSObject) throws(RemindersError) -> [NSObject] {
      try Runtime.fetch("fetchListSectionsInList:error:", on: sectionsView, list)
    }

    static func section(_ object: NSObject) -> ReminderKitSection? {
      section(object, creationDateKey: nil)
    }

    static func section(_ object: NSObject, creationDateKey: String?) -> ReminderKitSection? {
      guard let id = Runtime.identifier(of: object) else { return nil }
      return ReminderKitSection(
        id: id, displayName: Runtime.string(object, "displayName") ?? "",
        createdAt: creationDateKey.flatMap { Runtime.object(object, $0) as? NSDate }.map { $0 as Date })
    }

    /// The creation-date property every one of `sections` responds to, if there is one.
    static func creationDateKey(of sections: [NSObject]) -> String? {
      ["creationDate", "createdDate", "dateCreated"].first { key in
        !sections.isEmpty && sections.allSatisfy { $0.responds(to: NSSelectorFromString(key)) }
      }
    }

    /// Properties that may hold a list's arranged section order, tried in turn on the list and on its `storage`.
    static let sectionOrderKeys = [
      "sectionIDsOrderingAsData", "sectionIDsOrdering", "sectionsOrdering", "orderedSectionIDs",
      "sectionIDsOrderingData", "listSectionIDsOrdering",
    ]

    /// The section identifiers in the list's arranged order, from the first candidate property that has one (as
    /// stored JSON, an `{orderedIdentifiers}` object, or a collection of identifiers), with where it came from
    /// (`storage.` marks the list's storage object). Nil when none has an order, as when the stored ordering is
    /// NULL. `probes` records what each candidate gave, for `REMINDERS_DEBUG`.
    static func sectionOrder(of list: NSObject, probes: inout [String]) -> ReminderKitRead<[String]>? {
      var owners: [(prefix: String, object: NSObject)] = [("", list)]
      if let storage = Runtime.object(list, "storage") { owners.append(("storage.", storage)) }
      for (prefix, owner) in owners {
        for key in sectionOrderKeys {
          guard owner.responds(to: NSSelectorFromString(key)) else { continue }
          let value = Runtime.object(owner, key)
          let order = value.map(orderedIdentifiers) ?? []
          probes.append("\(prefix)\(key)=\(value.map(Runtime.className) ?? "nil")[\(order.count)]")
          if !order.isEmpty { return ReminderKitRead(order, via: prefix + key) }
        }
      }
      return nil
    }

    /// Section identifiers from an ordering value: stored JSON (`{"orderedIdentifiers": [...]}`), an object with
    /// `orderedIdentifiers`, or a collection of identifiers.
    static func orderedIdentifiers(_ value: NSObject) -> [String] {
      if let data = value as? NSData { return SectionOrdering.identifiers([UInt8](data as Data)) }
      if let string = value as? String { return SectionOrdering.identifiers(Array(string.utf8)) }
      if let inner = Runtime.object(value, "orderedIdentifiers") { return Runtime.identifiers(in: inner) }
      return Runtime.identifiers(in: value)
    }

    /// The section each reminder is in, through ReminderKit only.
    ///
    /// Reminders' client side of ReminderKit (macOS 26.4 and 27 alike) has no getter for a list's stored
    /// memberships: `REMList` and `REMListStorage` only carry the unsaved ones a change stages. So, unless a later
    /// version adds a getter on the list (tried first), each reminder's section is asked for in turn with
    /// `REMListSectionsDataView fetchListSectionWithReminderID:error:`, which Reminders answers from the stored
    /// memberships. Reminders in no section are left out.
    ///
    /// - Parameter reminderIDs: Upper-case dashed reminder UUIDs; nil for every reminder in the list, completed ones
    ///   included (fetched with `REMRemindersDataView`).
    func memberships(of list: NSObject, reminderIDs: [String]?) throws(RemindersError)
      -> ReminderKitRead<[SectionMemberships.Entry]>
    {
      if let stored = Self.storedMemberships(of: list) {
        let wanted = reminderIDs.map { Set($0.map { $0.uppercased() }) }
        return ReminderKitRead(
          stored.value.filter { wanted?.contains($0.reminderID) ?? true }, via: stored.selector)
      }
      let fetch = "fetchListSectionWithReminderID:error:"
      try Runtime.require([fetch], on: sectionsView)
      var reminders: [NSObject] = []
      if let reminderIDs {
        for case let uuid? in reminderIDs.map(UUID.init(uuidString:)) {
          reminders.append(try Runtime.reminderObjectID(uuid))
        }
      } else {
        reminders = try reminderObjectIDs(in: list)
      }
      var entries: [SectionMemberships.Entry] = []
      var unsectioned = 0
      var failures: [String] = []
      for objectID in reminders {
        guard let reminder = (Runtime.object(objectID, "uuid") as? NSUUID)?.uuidString.uppercased() else { continue }
        let (section, error) = Runtime.fetchOptionalObject(fetch, on: sectionsView, objectID)
        switch SectionLookupOutcome(
          sectionID: section.flatMap(Runtime.identifier(of:)), error: error.map { ($0.domain, $0.code) })
        {
        case .inSection(let sectionID):
          entries.append(SectionMemberships.Entry(reminderID: reminder, sectionID: sectionID))
        case .notInSection:
          unsectioned += 1
        case .failed(let detail):
          failures.append("\(reminder): \(detail)")
        }
      }
      log?(
        "memberships: \(fetch) x\(reminders.count), \(entries.count) in a section, \(unsectioned) in none, "
          + "\(failures.count) errors")
      // A failed lookup leaves that reminder out of every section; any failure means the answer is incomplete.
      if !failures.isEmpty {
        throw RemindersError.reminderKitFailed(
          "read which section each reminder is in (\(fetch))", failures.prefix(3).joined(separator: "; "))
      }
      return ReminderKitRead(entries, via: "\(fetch) x\(reminders.count)")
    }

    /// Object identifiers of every reminder in the list, completed ones and subtasks included.
    func reminderObjectIDs(in list: NSObject) throws(RemindersError) -> [NSObject] {
      guard let listID = Runtime.object(list, "objectID") else {
        throw RemindersError.reminderKitUnavailable("REMList has no objectID")
      }
      let view = try Runtime.make("REMRemindersDataView", initWithStore: store)
      let reminders = try Runtime.fetchReminders(in: listID, on: view)
      return reminders.compactMap { Runtime.object($0, "objectID") }
    }

    /// The list's stored memberships from a getter on the list itself, should a ReminderKit version have one (as
    /// stored JSON or as `REMMemberships`); nil when it has neither, or a shape this doesn't know.
    static func storedMemberships(of list: NSObject) -> ReminderKitRead<[SectionMemberships.Entry]>? {
      let dataKey = "membershipsOfRemindersInSectionsAsData"
      if list.responds(to: NSSelectorFromString(dataKey)) {
        guard let data = Runtime.object(list, dataKey) as? NSData else { return ReminderKitRead([], via: dataKey) }
        guard let json = String(data: data as Data, encoding: .utf8),
          let memberships = try? SectionMemberships(storedData: json)
        else { return nil }
        return ReminderKitRead(memberships.current, via: dataKey)
      }
      let objectKey = "membershipsOfRemindersInSections"
      guard list.responds(to: NSSelectorFromString(objectKey)) else { return nil }
      guard let memberships = Runtime.object(list, objectKey) else { return ReminderKitRead([], via: objectKey) }
      guard let all = Runtime.object(memberships, "memberships").flatMap(Runtime.elements) else { return nil }
      var entries: [SectionMemberships.Entry] = []
      for case let membership as NSObject in all {
        guard let member = Runtime.object(membership, "memberIdentifier") as? NSUUID,
          let group = Runtime.object(membership, "groupIdentifier") as? NSUUID
        else { return nil }
        // An obsolete membership no longer puts the reminder in that section.
        if (Runtime.object(membership, "isObsolete") as? NSNumber)?.boolValue == true { continue }
        entries.append(
          SectionMemberships.Entry(
            reminderID: member.uuidString.uppercased(), sectionID: group.uuidString.uppercased(),
            modifiedOn: (Runtime.object(membership, "modifiedOn") as? NSDate)?.timeIntervalSinceReferenceDate))
      }
      return ReminderKitRead(SectionMemberships(entries: entries).current, via: "\(objectKey).memberships")
    }

    /// `reminderIDsOrdering` when the list's `sortingStyle` says it's sorted manually, nil inside when it says it
    /// isn't; nil when this ReminderKit has either property missing or of an unknown type.
    static func manualReminderOrder(of list: NSObject) -> ReminderKitRead<[String]?>? {
      guard list.responds(to: NSSelectorFromString("reminderIDsOrdering")),
        let style = Runtime.string(list, "sortingStyle")
      else { return nil }
      guard style.lowercased() == "manual" else { return ReminderKitRead(nil, via: "sortingStyle") }
      guard let ordering = Runtime.object(list, "reminderIDsOrdering") else {
        return ReminderKitRead(nil, via: "sortingStyle, reminderIDsOrdering")
      }
      let identifiers = Runtime.identifiers(in: ordering)
      return ReminderKitRead(identifiers.isEmpty ? nil : identifiers, via: "sortingStyle, reminderIDsOrdering")
    }

    // MARK: Changing

    /// Logs one write step.
    func step(_ line: @autoclosure () -> String) {
      log?("write: " + line())
    }

    /// A new save request on this session's store, checked for the save it ends with.
    func saveRequest() throws(RemindersError) -> NSObject {
      let request = try Runtime.make("REMSaveRequest", initWithStore: store)
      step("REMSaveRequest initWithStore: -> \(Runtime.className(request))")
      try Runtime.require(["saveSynchronouslyWithError:"], on: request)
      return request
    }

    /// The list's change item, tracked by `request` so what's staged on it is saved.
    ///
    /// As remctl does it: the list fetched as a `REMList` (`REMStore fetchListWithObjectID:error:`) and handed to
    /// `REMSaveRequest updateList:`, which registers the change item with the request. A change item made with
    /// `REMListChangeItem initWithSaveRequest:storage:...` isn't registered: memberships staged on it were dropped
    /// on the Mac, saving nothing. That path is used only when `allowUntracked` (creating a section, which the
    /// request itself tracks) and `updateList:` is missing.
    func trackedListChange(
      request: NSObject, storage: NSObject, account: NSObject, allowUntracked: Bool
    ) throws(RemindersError) -> NSObject {
      let fetchList = "fetchListWithObjectID:error:"
      if request.responds(to: NSSelectorFromString("updateList:")), store.responds(to: NSSelectorFromString(fetchList)),
        let objectID = Runtime.object(storage, "objectID")
      {
        let list = try Runtime.fetchObject(fetchList, on: store, objectID)
        step("REMStore \(fetchList) \(Runtime.className(objectID)) -> \(Runtime.className(list))")
        guard let change = try Runtime.send("updateList:", to: request, list) else {
          throw RemindersError.reminderKitFailed("change the list", "updateList: returned nothing")
        }
        step("REMSaveRequest updateList: -> \(Runtime.className(change))")
        return change
      }
      guard allowUntracked else {
        throw RemindersError.reminderKitUnavailable(
          "REMSaveRequest updateList: or REMStore \(fetchList) is missing")
      }
      let change = try Runtime.listChangeItem(
        request: request, storage: storage, capabilities: Runtime.object(account, "capabilities"))
      step(
        "updateList: unavailable; REMListChangeItem initWithSaveRequest:storage:accountCapabilities:"
          + "observeInitialValues: -> \(Runtime.className(change))")
      return change
    }

    /// The list change's sections context.
    func sectionsContext(of listChange: NSObject, for action: String) throws(RemindersError) -> NSObject {
      guard let context = try Runtime.send("sectionsContextChangeItem", to: listChange) else {
        throw RemindersError.reminderKitFailed(action, "the list has no sections context")
      }
      step("sectionsContextChangeItem -> \(Runtime.className(context))")
      return context
    }

    func save(_ request: NSObject, _ action: String) throws(RemindersError) {
      do throws(RemindersError) {
        let warning = try Runtime.save(request, action)
        step("saveSynchronouslyWithError: -> true, error: \(warning.map { "\($0.domain) \($0.code)" } ?? "nil")")
      } catch {
        step("saveSynchronouslyWithError: -> false, error: \(error.message)")
        throw error
      }
    }

    func createSection(named name: String, in list: ReminderList) throws(RemindersError) -> ReminderKitSection {
      let (storage, account) = try storage(of: list)
      step("create section: list \(Runtime.className(storage)) \(Runtime.identifier(of: storage) ?? "?")")
      let before = Set(try sections(of: storage).compactMap(Self.section).map(\.id))
      let request = try saveRequest()
      let listChange = try trackedListChange(request: request, storage: storage, account: account, allowUntracked: true)
      let context = try sectionsContext(of: listChange, for: "create section \"\(name)\"")
      let added = try Runtime.send(
        "addListSectionWithDisplayName:toListSectionContextChangeItem:", to: request, name as NSString, context)
      step("addListSectionWithDisplayName:toListSectionContextChangeItem: -> \(added.map(Runtime.className) ?? "nil")")
      try save(request, "create section \"\(name)\" in \"\(list.title)\"")
      if let added, let section = Self.section(added) { return section }
      // Not every version returns the new section; then it's the one with that name that wasn't there before.
      let after = try sections(of: storage).compactMap(Self.section)
      guard let section = after.first(where: { $0.displayName == name && !before.contains($0.id) }) else {
        throw RemindersError.writeNotApplied("section \"\(name)\" was saved but isn't listed in \"\(list.title)\"")
      }
      return section
    }

    /// Deletes the section and, in the same save, takes `members` (the reminders in it) out of it.
    ///
    /// Reminders merges the memberships a change hands it into the stored ones, newest per reminder winning, and
    /// keeps a deleted section's memberships (for undo). Left alone, they'd stay in the list's data pointing at a
    /// section that's gone. Each member gets an obsolete membership instead, which is how ReminderKit records "in
    /// no section"; leaving members out of the change wouldn't remove anything from a merge.
    func deleteSection(id: String, in list: ReminderList, clearing members: [String]) throws(RemindersError) {
      let (storage, account) = try storage(of: list)
      guard let section = try sections(of: storage).first(where: { Runtime.identifier(of: $0) == id.uppercased() })
      else {
        throw RemindersError(.sectionNotFound, "ReminderKit has no section \(id) in \"\(list.title)\"")
      }
      guard let group = UUID(uuidString: id) else {
        throw RemindersError(.invalidArgument, "Not a section identifier: \(id)")
      }
      step("delete section: \(Runtime.className(section)) \(group.uuidString)")
      // Everything is built and checked before the one save at the end; a failure on the way saves nothing.
      var obsolete: [NSObject] = []
      for case let member? in members.map(UUID.init(uuidString:)) {
        obsolete.append(try Runtime.membership(member: member, group: group, isObsolete: true, modifiedOn: Date()))
      }
      let request = try saveRequest()
      try Runtime.require(["updateListSection:"], on: request)
      // A tracked change, so the deletion syncs; removing the object alone wouldn't.
      guard let change = try Runtime.send("updateListSection:", to: request, section) else {
        throw RemindersError.reminderKitFailed("delete the section", "updateListSection: returned nothing")
      }
      step("REMSaveRequest updateListSection: -> \(Runtime.className(change))")
      try Runtime.require(["removeFromList"], on: change)
      _ = try Runtime.send("removeFromList", to: change)
      step("removeFromList")
      if !obsolete.isEmpty {
        try stageMemberships(obsolete, request: request, storage: storage, account: account, for: "delete the section")
        step("setUnsavedMembershipsOfRemindersInSections: \(obsolete.count) obsolete (\(group.uuidString))")
      }
      try save(request, "delete the section from \"\(list.title)\"")
    }
  }

  extension ReminderKitSession {
    /// Puts a reminder in a section the way the Reminders app (and remctl) does: one membership handed to the
    /// sections context of the list's tracked change item, in one save request. Reminders merges it into the
    /// stored memberships (the newest per reminder wins) and writes the data, its checksum and sync metadata itself.
    func assign(reminderID: String, toSectionID sectionID: String, in list: ReminderList) throws(RemindersError) {
      guard let member = UUID(uuidString: reminderID), let group = UUID(uuidString: sectionID) else {
        throw RemindersError(.invalidArgument, "Not a reminder and section identifier: \(reminderID), \(sectionID)")
      }
      let (storage, account) = try storage(of: list)
      step("move: list \(Runtime.className(storage)) \(Runtime.identifier(of: storage) ?? "?")")
      guard try sections(of: storage).contains(where: { Runtime.identifier(of: $0) == group.uuidString }) else {
        throw RemindersError(.sectionNotFound, "ReminderKit has no section \(sectionID) in \"\(list.title)\"")
      }
      // Everything is checked and built before the one save; a failure on the way saves nothing.
      let membership = try Runtime.membership(member: member, group: group, isObsolete: false, modifiedOn: Date())
      let request = try saveRequest()
      try stageMemberships([membership], request: request, storage: storage, account: account, for: "move the reminder")
      step("setUnsavedMembershipsOfRemindersInSections: (\(member.uuidString) -> \(group.uuidString))")
      try save(request, "move the reminder to the section in \"\(list.title)\"")
    }

    /// Hands `memberships` to the sections context of the list's tracked change item in `request`.
    func stageMemberships(
      _ memberships: [NSObject], request: NSObject, storage: NSObject, account: NSObject, for action: String
    ) throws(RemindersError) {
      let set = try Runtime.make("REMMemberships", "initWithMemberships:", memberships as NSArray)
      step(
        "REMMembership initWithMemberIdentifier:groupIdentifier:isObsolete:modifiedOn: x\(memberships.count), "
          + "REMMemberships initWithMemberships: -> \(Runtime.className(set))")
      let listChange = try trackedListChange(
        request: request, storage: storage, account: account, allowUntracked: false)
      let context = try sectionsContext(of: listChange, for: action)
      try Runtime.require(["setUnsavedMembershipsOfRemindersInSections:"], on: context)
      _ = try Runtime.send("setUnsavedMembershipsOfRemindersInSections:", to: context, set)
    }
  }
#endif
