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
        try session.sections(of: session.storage(of: list).list).compactMap(ReminderKitSession.section)
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

    /// An object's identifier, `objectID.uuid`, as an upper-case dashed UUID.
    static func identifier(of object: NSObject) -> String? {
      guard let objectID = self.object(object, "objectID"), let uuid = self.object(objectID, "uuid") as? NSUUID
      else { return nil }
      return uuid.uuidString.uppercased()
    }
  }
#endif
