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

    public init() {}

    public func sections(in list: ReminderList) throws(RemindersError) -> [ReminderKitSection] {
      try withSession { session throws(RemindersError) in
        let storage = try session.storage(of: list).list
        let sections = try session.sections(of: storage).compactMap(ReminderKitSession.section)
        return DatabaseRows.arranged(sections, by: ReminderKitSession.sectionOrder(of: storage), identifier: \.id)
      }
    }

    public func memberships(in list: ReminderList) throws(RemindersError) -> StoredMemberships? {
      try withSession { session throws(RemindersError) in
        ReminderKitSession.memberships(of: try session.storage(of: list).list)
      }
    }

    public func manualReminderOrder(in list: ReminderList) throws(RemindersError) -> [String]? {
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

    public func assign(reminderID: String, toSectionID sectionID: String, in list: ReminderList)
      throws(RemindersError)
    {
      try withSession { session throws(RemindersError) in
        try session.assign(reminderID: reminderID, toSectionID: sectionID, in: list)
      }
    }

    /// Runs `body` on a fresh session, draining what ReminderKit autoreleases.
    private func withSession<T>(_ body: (ReminderKitSession) throws(RemindersError) -> T) throws(RemindersError)
      -> T
    {
      let result: Result<T, RemindersError> = autoreleasepool {
        do throws(RemindersError) {
          return .success(try body(try ReminderKitSession()))
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

    init() throws(RemindersError) {
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
      guard let id = Runtime.identifier(of: object) else { return nil }
      return ReminderKitSection(id: id, displayName: Runtime.string(object, "displayName") ?? "")
    }

    /// The section identifiers in the list's arranged order, from whichever form this ReminderKit exposes: the
    /// stored JSON or the identifiers themselves. Empty when it exposes neither; the sections then keep the order
    /// they were fetched in.
    static func sectionOrder(of list: NSObject) -> [String] {
      if let data = Runtime.object(list, "sectionIDsOrderingAsData") as? NSData {
        return DatabaseRows.sectionOrder([UInt8](data as Data))
      }
      return Runtime.object(list, "sectionIDsOrdering").map(Runtime.identifiers) ?? []
    }

    /// The list's memberships, from the stored JSON or from `REMMemberships`, whichever this ReminderKit exposes;
    /// nil when it exposes neither, or a shape this doesn't know.
    static func memberships(of list: NSObject) -> StoredMemberships? {
      let dataKey = "membershipsOfRemindersInSectionsAsData"
      if list.responds(to: NSSelectorFromString(dataKey)) {
        guard let data = Runtime.object(list, dataKey) as? NSData else { return StoredMemberships() }
        return String(data: data as Data, encoding: .utf8).map { StoredMemberships(data: $0) }
      }
      let objectKey = "membershipsOfRemindersInSections"
      guard list.responds(to: NSSelectorFromString(objectKey)) else { return nil }
      guard let memberships = Runtime.object(list, objectKey) else { return StoredMemberships() }
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
      return StoredMemberships(entries: entries)
    }

    /// `reminderIDsOrdering` when the list's `sortingStyle` says it's sorted manually; nil otherwise, including
    /// when this ReminderKit has neither.
    static func manualReminderOrder(of list: NSObject) -> [String]? {
      guard let style = Runtime.string(list, "sortingStyle"), style.lowercased() == "manual",
        let ordering = Runtime.object(list, "reminderIDsOrdering")
      else { return nil }
      let identifiers = Runtime.identifiers(in: ordering)
      return identifiers.isEmpty ? nil : identifiers
    }

    // MARK: Changing

    func createSection(named name: String, in list: ReminderList) throws(RemindersError) -> ReminderKitSection {
      let (storage, account) = try storage(of: list)
      let before = Set(try sections(of: storage).compactMap(Self.section).map(\.id))
      let request = try Runtime.make("REMSaveRequest", initWithStore: store)
      let listChange = try Runtime.listChangeItem(
        request: request, storage: storage, capabilities: Runtime.object(account, "capabilities"))
      guard let sectionsContext = try Runtime.send("sectionsContextChangeItem", to: listChange) else {
        throw RemindersError.reminderKitFailed("create section \"\(name)\"", "the list has no sections context")
      }
      let added = try Runtime.send(
        "addListSectionWithDisplayName:toListSectionContextChangeItem:", to: request, name as NSString,
        sectionsContext)
      try Runtime.save(request, "create section \"\(name)\" in \"\(list.title)\"")
      if let added, let section = Self.section(added) { return section }
      // Not every version returns the new section; then it's the one with that name that wasn't there before.
      let after = try sections(of: storage).compactMap(Self.section)
      guard let section = after.first(where: { $0.displayName == name && !before.contains($0.id) }) else {
        throw RemindersError.reminderKitFailed(
          "find the new section \"\(name)\" in \"\(list.title)\"", "it was saved but isn't listed")
      }
      return section
    }

    func deleteSection(id: String, in list: ReminderList) throws(RemindersError) {
      let storage = try storage(of: list).list
      guard let section = try sections(of: storage).first(where: { Runtime.identifier(of: $0) == id.uppercased() })
      else {
        throw RemindersError(.sectionNotFound, "ReminderKit has no section \(id) in \"\(list.title)\"")
      }
      let request = try Runtime.make("REMSaveRequest", initWithStore: store)
      // Everything the deletion needs is checked before it's staged; nothing is saved until the one save at the end.
      try Runtime.require(["updateListSection:", "saveSynchronouslyWithError:"], on: request)
      // A tracked change, so the deletion syncs; removing the object alone wouldn't.
      guard let change = try Runtime.send("updateListSection:", to: request, section) else {
        throw RemindersError.reminderKitFailed("delete the section", "updateListSection: returned nothing")
      }
      try Runtime.require(["removeFromList"], on: change)
      _ = try Runtime.send("removeFromList", to: change)
      try Runtime.save(request, "delete the section from \"\(list.title)\"")
    }
  }

  extension ReminderKitSession {
    /// Puts a reminder in a section the way the Reminders app does: a membership handed to the list's sections
    /// context in one save request. Reminders merges it into the list's membership data (the newest membership of
    /// a reminder wins), writes that data's checksum, and syncs it.
    func assign(reminderID: String, toSectionID sectionID: String, in list: ReminderList) throws(RemindersError) {
      guard let member = UUID(uuidString: reminderID), let group = UUID(uuidString: sectionID) else {
        throw RemindersError(.invalidArgument, "Not a reminder and section identifier: \(reminderID), \(sectionID)")
      }
      let (storage, account) = try storage(of: list)
      guard try sections(of: storage).contains(where: { Runtime.identifier(of: $0) == group.uuidString }) else {
        throw RemindersError(.sectionNotFound, "ReminderKit has no section \(sectionID) in \"\(list.title)\"")
      }
      // Everything is checked and built before the one save; a failure on the way saves nothing.
      let membership = try Runtime.membership(member: member, group: group, modifiedOn: Date())
      let memberships = try Runtime.make("REMMemberships", "initWithMemberships:", [membership] as NSArray)
      let request = try Runtime.make("REMSaveRequest", initWithStore: store)
      try Runtime.require(["saveSynchronouslyWithError:"], on: request)
      let listChange = try Runtime.listChangeItem(
        request: request, storage: storage, capabilities: Runtime.object(account, "capabilities"))
      guard let sectionsContext = try Runtime.send("sectionsContextChangeItem", to: listChange) else {
        throw RemindersError.reminderKitFailed("move the reminder", "the list has no sections context")
      }
      try Runtime.require(["setUnsavedMembershipsOfRemindersInSections:"], on: sectionsContext)
      _ = try Runtime.send("setUnsavedMembershipsOfRemindersInSections:", to: sectionsContext, memberships)
      try Runtime.save(request, "move the reminder to the section in \"\(list.title)\"")
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

    /// Saves `request`, waiting until Reminders has it.
    static func save(_ request: NSObject, _ action: String) throws(RemindersError) {
      let (selector, imp) = try implementation("saveSynchronouslyWithError:", on: request)
      typealias Save = @convention(c) (AnyObject, Selector, AutoreleasingUnsafeMutablePointer<NSError?>) -> ObjCBool
      var error: NSError?
      guard unsafeBitCast(imp, to: Save.self)(request, selector, &error).boolValue else {
        throw .reminderKitFailed(action, error?.localizedDescription ?? "the save failed")
      }
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
