#if os(macOS)
  import Foundation
  import ObjectiveC
  import RemindersCore

  /// Checked Objective-C runtime calls.
  enum Runtime {
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

    /// A `REMMembership`: the reminder `member` in the section `group` (or, when `isObsolete`, no longer in it), set
    /// at `modifiedOn`.
    static func membership(member: UUID, group: UUID, isObsolete: Bool, modifiedOn: Date) throws(RemindersError)
      -> NSObject
    {
      let name = "initWithMemberIdentifier:groupIdentifier:isObsolete:modifiedOn:"
      let allocated = try allocate("REMMembership")
      let (selector, imp) = try implementation(name, on: allocated)
      typealias Initializer =
        @convention(c) (AnyObject, Selector, AnyObject, AnyObject, ObjCBool, AnyObject) -> AnyObject?
      let initialize = unsafeBitCast(imp, to: Initializer.self)
      guard
        let membership = initialize(
          allocated, selector, member as NSUUID, group as NSUUID, ObjCBool(isObsolete), modifiedOn as NSDate)
          as? NSObject
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

    /// What an `...error:` fetch taking one argument returns, which may be nothing, and the error it set.
    static func fetchOptionalObject(_ name: String, on object: NSObject, _ argument: NSObject) -> (NSObject?, NSError?)
    {
      guard let (selector, imp) = try? implementation(name, on: object) else { return (nil, nil) }
      var error: NSError?
      typealias Fetch =
        @convention(c) (AnyObject, Selector, AnyObject, AutoreleasingUnsafeMutablePointer<NSError?>) -> AnyObject?
      let result = unsafeBitCast(imp, to: Fetch.self)(object, selector, argument, &error) as? NSObject
      return (result, error)
    }

    /// Every reminder in a list, completed ones and subtasks included
    /// (`fetchRemindersWithListID:includingSubtasks:includingCompleted:error:`).
    static func fetchReminders(in listID: NSObject, on view: NSObject) throws(RemindersError) -> [NSObject] {
      let name = "fetchRemindersWithListID:includingSubtasks:includingCompleted:error:"
      let (selector, imp) = try implementation(name, on: view)
      typealias Fetch =
        @convention(c) (
          AnyObject, Selector, AnyObject, ObjCBool, ObjCBool, AutoreleasingUnsafeMutablePointer<NSError?>
        ) -> AnyObject?
      var error: NSError?
      let result = unsafeBitCast(imp, to: Fetch.self)(view, selector, listID, true, true, &error)
      guard let reminders = result as? [NSObject] else {
        throw .reminderKitFailed(
          "read the list's reminders (\(name))", error?.localizedDescription ?? "nothing came back")
      }
      return reminders
    }

    /// A reminder's `REMObjectID` from its UUID (`REMReminder objectIDWithUUID:`).
    static func reminderObjectID(_ uuid: UUID) throws(RemindersError) -> NSObject {
      let reminder = try type("REMReminder")
      let selector = NSSelectorFromString("objectIDWithUUID:")
      guard reminder.responds(to: selector),
        let objectID = reminder.perform(selector, with: uuid as NSUUID)?.takeUnretainedValue() as? NSObject
      else { throw .reminderKitUnavailable("REMReminder doesn't respond to objectIDWithUUID:") }
      return objectID
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
