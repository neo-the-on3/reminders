#if os(macOS)
  import Foundation
  import ObjectiveC
  import RemindersCore

  /// ``ReminderKitBridge`` on the real framework, loaded through the Objective-C runtime when first used.
  ///
  /// Nothing links against ReminderKit, so `reminders` starts, and lists sections, even where it's missing or
  /// different. Each call checks every class and method it's about to use and reports a missing one as
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

    public func memberships(in list: ReminderList) throws(RemindersError) -> ReminderKitRead<StoredMemberships>? {
      try withSession { session throws(RemindersError) in
        ReminderKitSession.memberships(of: try session.storage(of: list).list)
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

    public func deleteSection(id: String, in list: ReminderList) throws(RemindersError) {
      try withSession { session throws(RemindersError) in try session.deleteSection(id: id, in: list) }
    }

    public func assign(
      reminderID: String, toSectionID sectionID: String, in list: ReminderList,
      keeping existing: [SectionMemberships.Entry]
    ) throws(RemindersError) {
      try withSession { session throws(RemindersError) in
        try session.assign(reminderID: reminderID, toSectionID: sectionID, in: list, keeping: existing)
      }
    }

    /// Runs `body` on a fresh session, draining what ReminderKit autoreleases.
    private func withSession<T>(_ body: (ReminderKitSession) throws(RemindersError) -> T) throws(RemindersError)
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
  private struct ReminderKitSession {
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
      if let data = value as? NSData { return DatabaseRows.sectionOrder([UInt8](data as Data)) }
      if let string = value as? String { return DatabaseRows.sectionOrder(Array(string.utf8)) }
      if let inner = Runtime.object(value, "orderedIdentifiers") { return Runtime.identifiers(in: inner) }
      return Runtime.identifiers(in: value)
    }

    /// The list's memberships, from the stored JSON or from `REMMemberships`, whichever this ReminderKit exposes;
    /// nil when it exposes neither, or a shape this doesn't know.
    static func memberships(of list: NSObject) -> ReminderKitRead<StoredMemberships>? {
      let dataKey = "membershipsOfRemindersInSectionsAsData"
      if list.responds(to: NSSelectorFromString(dataKey)) {
        guard let data = Runtime.object(list, dataKey) as? NSData else {
          return ReminderKitRead(StoredMemberships(), via: dataKey)
        }
        return String(data: data as Data, encoding: .utf8).map {
          ReminderKitRead(StoredMemberships(data: $0), via: dataKey)
        }
      }
      let objectKey = "membershipsOfRemindersInSections"
      guard list.responds(to: NSSelectorFromString(objectKey)) else { return nil }
      guard let memberships = Runtime.object(list, objectKey) else {
        return ReminderKitRead(StoredMemberships(), via: objectKey)
      }
      guard let all = Runtime.object(memberships, "memberships").flatMap(Runtime.elements) else { return nil }
      var entries: [SectionMemberships.Entry] = []
      for case let membership as NSObject in all {
        guard let member = Runtime.object(membership, "memberIdentifier") as? NSUUID,
          let group = Runtime.object(membership, "groupIdentifier") as? NSUUID
        else { return nil }
        // An obsolete membership no longer puts the reminder in that section.
        let isObsolete = (Runtime.object(membership, "isObsolete") as? NSNumber)?.boolValue ?? false
        entries.append(
          SectionMemberships.Entry(
            reminderID: member.uuidString.uppercased(), sectionID: isObsolete ? "" : group.uuidString.uppercased(),
            modifiedOn: (Runtime.object(membership, "modifiedOn") as? NSDate)?.timeIntervalSinceReferenceDate))
      }
      return ReminderKitRead(StoredMemberships(entries: entries), via: "\(objectKey).memberships")
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

    func deleteSection(id: String, in list: ReminderList) throws(RemindersError) {
      let storage = try storage(of: list).list
      guard let section = try sections(of: storage).first(where: { Runtime.identifier(of: $0) == id.uppercased() })
      else {
        throw RemindersError(.sectionNotFound, "ReminderKit has no section \(id) in \"\(list.title)\"")
      }
      step("delete section: \(Runtime.className(section)) \(id.uppercased())")
      let request = try saveRequest()
      // Everything the deletion needs is checked before it's staged; nothing is saved until the one save at the end.
      try Runtime.require(["updateListSection:"], on: request)
      // A tracked change, so the deletion syncs; removing the object alone wouldn't.
      guard let change = try Runtime.send("updateListSection:", to: request, section) else {
        throw RemindersError.reminderKitFailed("delete the section", "updateListSection: returned nothing")
      }
      step("REMSaveRequest updateListSection: -> \(Runtime.className(change))")
      try Runtime.require(["removeFromList"], on: change)
      _ = try Runtime.send("removeFromList", to: change)
      step("removeFromList")
      try save(request, "delete the section from \"\(list.title)\"")
    }
  }

  extension ReminderKitSession {
    /// Puts a reminder in a section the way the Reminders app (and remctl) does: memberships handed to the sections
    /// context of the list's tracked change item, in one save request. Reminders writes the membership data, its
    /// checksum and sync metadata itself.
    ///
    /// The list's current memberships go with the new one (each with its own time), so the result is the same
    /// whether ReminderKit merges what it's given into the stored set or replaces the set with it.
    func assign(
      reminderID: String, toSectionID sectionID: String, in list: ReminderList,
      keeping existing: [SectionMemberships.Entry]
    ) throws(RemindersError) {
      guard let member = UUID(uuidString: reminderID), let group = UUID(uuidString: sectionID) else {
        throw RemindersError(.invalidArgument, "Not a reminder and section identifier: \(reminderID), \(sectionID)")
      }
      let (storage, account) = try storage(of: list)
      step("move: list \(Runtime.className(storage)) \(Runtime.identifier(of: storage) ?? "?")")
      guard try sections(of: storage).contains(where: { Runtime.identifier(of: $0) == group.uuidString }) else {
        throw RemindersError(.sectionNotFound, "ReminderKit has no section \(sectionID) in \"\(list.title)\"")
      }
      // Everything is checked and built before the one save; a failure on the way saves nothing.
      var memberships: [NSObject] = []
      for entry in existing where entry.reminderID.uppercased() != member.uuidString {
        guard let other = UUID(uuidString: entry.reminderID), let otherGroup = UUID(uuidString: entry.sectionID) else {
          continue
        }
        memberships.append(
          try Runtime.membership(
            member: other, group: otherGroup,
            modifiedOn: Date(timeIntervalSinceReferenceDate: entry.modifiedOn ?? 0)))
      }
      memberships.append(try Runtime.membership(member: member, group: group, modifiedOn: Date()))
      let set = try Runtime.make("REMMemberships", "initWithMemberships:", memberships as NSArray)
      step(
        "REMMembership initWithMemberIdentifier:groupIdentifier:isObsolete:modifiedOn: x\(memberships.count), "
          + "REMMemberships initWithMemberships: -> \(Runtime.className(set))")
      let request = try saveRequest()
      let listChange = try trackedListChange(
        request: request, storage: storage, account: account, allowUntracked: false)
      let context = try sectionsContext(of: listChange, for: "move the reminder")
      try Runtime.require(["setUnsavedMembershipsOfRemindersInSections:"], on: context)
      _ = try Runtime.send("setUnsavedMembershipsOfRemindersInSections:", to: context, set)
      step("setUnsavedMembershipsOfRemindersInSections: (\(member.uuidString) -> \(group.uuidString))")
      try save(request, "move the reminder to the section in \"\(list.title)\"")
    }
  }

  /// Checked Objective-C runtime calls.
  private enum Runtime {
    static func loadFramework() throws(RemindersError) {
      let path = RuntimeReminderKit.frameworkPath
      guard let bundle = Bundle(path: path) else { throw .reminderKitUnavailable("\(path) doesn't exist") }
      guard bundle.isLoaded || bundle.load() else { throw .reminderKitUnavailable("\(path) didn't load") }
    }

    static func type(_ name: String) throws(RemindersError) -> NSObject.Type {
      guard let type = NSClassFromString(name) as? NSObject.Type else {
        throw .reminderKitUnavailable("the class \(name) is missing")
      }
      return type
    }

    static func implementation(_ name: String, on object: NSObject) throws(RemindersError) -> (Selector, IMP) {
      let selector = NSSelectorFromString(name)
      guard let method = class_getInstanceMethod(Swift.type(of: object), selector) else {
        throw .reminderKitUnavailable("\(Swift.type(of: object)) has no method \(name)")
      }
      return (selector, method_getImplementation(method))
    }

    /// A new instance of class `name`, initialised with `init`.
    static func make(_ name: String) throws(RemindersError) -> NSObject {
      try type(name).init()
    }

    /// A new instance of class `name`, initialised with `initWithStore:`.
    static func make(_ name: String, initWithStore store: NSObject) throws(RemindersError) -> NSObject {
      let allocated = try allocate(name)
      guard let object = try send("initWithStore:", to: allocated, store) else {
        throw .reminderKitUnavailable("\(name) refused initWithStore:")
      }
      return object
    }

    /// A new instance of class `name`, initialised with `initializer`, which takes one object.
    static func make(_ name: String, _ initializer: String, _ argument: AnyObject) throws(RemindersError) -> NSObject {
      let allocated = try allocate(name)
      guard let object = try send(initializer, to: allocated, argument) else {
        throw .reminderKitUnavailable("\(name) refused \(initializer)")
      }
      return object
    }

    /// A `REMMembership`: the reminder `member` in the section `group`, set at `modifiedOn`.
    static func membership(member: UUID, group: UUID, modifiedOn: Date) throws(RemindersError) -> NSObject {
      let name = "initWithMemberIdentifier:groupIdentifier:isObsolete:modifiedOn:"
      let allocated = try allocate("REMMembership")
      let (selector, imp) = try implementation(name, on: allocated)
      typealias Initializer =
        @convention(c) (AnyObject, Selector, AnyObject, AnyObject, ObjCBool, AnyObject) -> AnyObject?
      let initialize = unsafeBitCast(imp, to: Initializer.self)
      guard
        let membership = initialize(
          allocated, selector, member as NSUUID, group as NSUUID, false, modifiedOn as NSDate) as? NSObject
      else { throw .reminderKitUnavailable("REMMembership refused \(name)") }
      return membership
    }

    private static func allocate(_ name: String) throws(RemindersError) -> NSObject {
      guard let object = try type(name).perform(NSSelectorFromString("alloc"))?.takeUnretainedValue() as? NSObject
      else { throw .reminderKitUnavailable("\(name) can't be allocated") }
      return object
    }

    /// The change item that edits a list, which owns the list's sections context.
    static func listChangeItem(request: NSObject, storage: NSObject, capabilities: NSObject?) throws(RemindersError)
      -> NSObject
    {
      let name = "initWithSaveRequest:storage:accountCapabilities:observeInitialValues:"
      let allocated = try allocate("REMListChangeItem")
      let (selector, imp) = try implementation(name, on: allocated)
      typealias Initializer =
        @convention(c) (AnyObject, Selector, AnyObject, AnyObject, AnyObject?, ObjCBool)
        -> AnyObject?
      let initialize = unsafeBitCast(imp, to: Initializer.self)
      guard let item = initialize(allocated, selector, request, storage, capabilities, false) as? NSObject else {
        throw .reminderKitUnavailable("REMListChangeItem refused \(name)")
      }
      return item
    }

    /// Throws ``RemindersError/Code/reminderKitUnavailable`` unless `object` responds to every one of `names`.
    static func require(_ names: [String], on object: NSObject) throws(RemindersError) {
      for name in names where !object.responds(to: NSSelectorFromString(name)) {
        throw .reminderKitUnavailable("\(Swift.type(of: object)) doesn't respond to \(name)")
      }
    }

    /// Sends a message taking up to two objects and returning one (or nothing).
    @discardableResult
    static func send(_ name: String, to object: NSObject, _ arguments: AnyObject...) throws(RemindersError)
      -> NSObject?
    {
      guard object.responds(to: NSSelectorFromString(name)) else {
        throw .reminderKitUnavailable("\(Swift.type(of: object)) doesn't respond to \(name)")
      }
      let selector = NSSelectorFromString(name)
      let result: Unmanaged<AnyObject>? =
        switch arguments.count {
        case 0: object.perform(selector)
        case 1: object.perform(selector, with: arguments[0])
        default: object.perform(selector, with: arguments[0], with: arguments[1])
        }
      return result?.takeUnretainedValue() as? NSObject
    }

    /// The objects an `...error:` fetch returns, with its argument if it takes one.
    static func fetch(_ name: String, on object: NSObject, _ argument: NSObject? = nil) throws(RemindersError)
      -> [NSObject]
    {
      let (selector, imp) = try implementation(name, on: object)
      var error: NSError?
      let result: AnyObject?
      if let argument {
        typealias Fetch =
          @convention(c) (AnyObject, Selector, AnyObject, AutoreleasingUnsafeMutablePointer<NSError?>)
          -> AnyObject?
        result = unsafeBitCast(imp, to: Fetch.self)(object, selector, argument, &error)
      } else {
        typealias Fetch =
          @convention(c) (AnyObject, Selector, AutoreleasingUnsafeMutablePointer<NSError?>) -> AnyObject?
        result = unsafeBitCast(imp, to: Fetch.self)(object, selector, &error)
      }
      guard let objects = result as? [NSObject] else {
        throw .reminderKitFailed("read its data (\(name))", error?.localizedDescription ?? "nothing came back")
      }
      return objects
    }

    /// The one object an `...error:` fetch taking one argument returns.
    static func fetchObject(_ name: String, on object: NSObject, _ argument: NSObject) throws(RemindersError)
      -> NSObject
    {
      let (selector, imp) = try implementation(name, on: object)
      var error: NSError?
      typealias Fetch =
        @convention(c) (AnyObject, Selector, AnyObject, AutoreleasingUnsafeMutablePointer<NSError?>) -> AnyObject?
      guard let result = unsafeBitCast(imp, to: Fetch.self)(object, selector, argument, &error) as? NSObject else {
        throw .reminderKitFailed("read its data (\(name))", error?.localizedDescription ?? "nothing came back")
      }
      return result
    }

    static func className(_ object: NSObject) -> String {
      NSStringFromClass(Swift.type(of: object))
    }

    /// Saves `request`, waiting until Reminders has it. Returns the error ReminderKit set even though the save
    /// succeeded, if it set one.
    @discardableResult
    static func save(_ request: NSObject, _ action: String) throws(RemindersError) -> NSError? {
      let (selector, imp) = try implementation("saveSynchronouslyWithError:", on: request)
      typealias Save = @convention(c) (AnyObject, Selector, AutoreleasingUnsafeMutablePointer<NSError?>) -> ObjCBool
      var error: NSError?
      guard unsafeBitCast(imp, to: Save.self)(request, selector, &error).boolValue else {
        let detail = error.map { "\($0.domain) \($0.code): \($0.localizedDescription)" } ?? "the save failed"
        throw .reminderKitFailed(action, detail)
      }
      return error
    }

    // MARK: Properties

    /// A property read with key-value coding, or nil when the object has no such property. (Asking for a missing
    /// key would raise an Objective-C exception, which Swift can't catch.)
    static func object(_ object: NSObject, _ key: String) -> NSObject? {
      guard object.responds(to: NSSelectorFromString(key)) else { return nil }
      return object.value(forKey: key) as? NSObject
    }

    static func string(_ object: NSObject, _ key: String) -> String? {
      self.object(object, key) as? String
    }

    /// The members of an array, ordered set or set; nil for anything else.
    static func elements(_ collection: NSObject) -> [Any]? {
      if let array = collection as? NSArray { return array as? [Any] }
      if let ordered = collection as? NSOrderedSet { return ordered.array }
      if let set = collection as? NSSet { return set.allObjects }
      return nil
    }

    /// Upper-case dashed UUIDs from a collection of `REMObjectID`s, `NSUUID`s or strings, skipping anything else.
    static func identifiers(in collection: NSObject) -> [String] {
      (elements(collection) ?? []).compactMap { element -> String? in
        switch element {
        case let uuid as NSUUID: uuid.uuidString.uppercased()
        case let string as String: UUID(uuidString: string)?.uuidString.uppercased()
        case let object as NSObject: (self.object(object, "uuid") as? NSUUID)?.uuidString.uppercased()
        default: nil
        }
      }
    }

    /// An object's identifier, `objectID.uuid`, as an upper-case dashed UUID.
    static func identifier(of object: NSObject) -> String? {
      guard let objectID = self.object(object, "objectID"), let uuid = self.object(objectID, "uuid") as? NSUUID
      else { return nil }
      return uuid.uuidString.uppercased()
    }
  }
#endif
