import Foundation
import RemindersCore

#if os(macOS)
  import ObjectiveC
#endif

/// `reminders debug-reminderkit`: what this Mac's ReminderKit offers for sections, to find which private getters
/// hold a list's memberships and section order.
///
/// Read-only. It lists classes, methods and properties through the Objective-C runtime, reads properties of one
/// list, its sections and its reminders, and asks each reminder's section. With ``Options/changeItem`` it also builds
/// a list change the way a move does, reads what it starts with, and drops it without saving.
public enum ReminderKitProbe {
  public struct Options: Sendable {
    /// Every method and property of the classes, not just those about sections, memberships and order.
    public var allSelectors = false
    /// Also build (and never save) a `REMSaveRequest` list change, to read the values it starts with.
    public var changeItem = false
    /// The most reminders to ask about, one ReminderKit call each.
    public var reminderLimit = 200

    public init(allSelectors: Bool = false, changeItem: Bool = false, reminderLimit: Int = 200) {
      self.allSelectors = allSelectors
      self.changeItem = changeItem
      self.reminderLimit = reminderLimit
    }
  }

  /// Writes the report on `list`, a line at a time.
  public static func run(on list: ReminderList, options: Options, write: @escaping (String) -> Void)
    throws(RemindersError)
  {
    #if os(macOS)
      let result: Result<Void, RemindersError> = autoreleasepool {
        do throws(RemindersError) {
          return .success(try Report(options: options, write: write).run(on: list))
        } catch {
          return .failure(error)
        }
      }
      try result.get()
    #else
      throw RemindersError.unsupportedPlatform
    #endif
  }
}

#if os(macOS)
  extension ReminderKitProbe {
    /// The classes whose methods and properties are listed.
    static let classes = [
      "REMStore", "REMList", "REMListStorage", "REMListSectionContext", "REMListChangeItem",
      "REMListSectionContextChangeItem", "REMListSection", "REMListSectionStorage", "REMBaseSection",
      "REMBaseSectionStorage", "REMListSectionsDataView", "REMRemindersDataView", "REMReminder", "REMReminderStorage",
      "REMMemberships", "REMMembership", "REMSaveRequest", "REMManualOrdering", "REMResolutionTokenMap",
    ]

    /// Names worth listing from those classes (unless every name is asked for).
    static let classFilter = "section|member|order|sort|group|ordering"

    /// Names searched for across every class in ReminderKit.
    static let imageFilter =
      "membership|sectionIDsOrdering|sectionsOrdering|ListSectionWithReminder|orderedIdentifiers|reminderIDsOrdering"

    /// Getters tried on the list, its storage, its section context and (with ``Options/changeItem``) a list change.
    static let listKeys = [
      "membershipsOfRemindersInSections", "membershipsOfRemindersInSectionsAsData",
      "membershipsOfRemindersInSectionsChecksum", "unsavedMembershipsOfRemindersInSections", "sectionIDsOrdering",
      "sectionIDsOrderingAsData", "unsavedSectionIDsOrdering", "shouldUpdateSectionsOrdering", "sectionIDsToUndelete",
      "hasSections", "sortingStyle", "reminderIDsOrdering", "reminderIDsMergeableOrdering",
      "reminderIDsMergeableOrderingData", "reminderIDsOrderingHints", "manualOrdering", "minimumSupportedVersion",
      "effectiveMinimumSupportedVersion",
    ]

    /// Getters tried on each section and its storage.
    static let sectionKeys = [
      "displayName", "canonicalName", "creationDate", "lastModifiedDate", "listID", "ordering", "sortOrder",
      "displayOrder", "isMarkedForDeletion", "minimumSupportedVersion",
    ]

    /// Getters tried on each reminder, in case one names its section.
    static let reminderKeys = ["listSectionID", "sectionID", "sectionIdentifier", "parentSectionID", "groupIdentifier"]

    struct Report {
      let options: Options
      let write: (String) -> Void

      func run(on list: ReminderList) throws(RemindersError) {
        let session = try ReminderKitSession()
        heading("ReminderKit")
        write("framework: \(RuntimeReminderKit.frameworkPath)")
        write("macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)")
        write("missing for section commands: \(RuntimeReminderKit.missingPart() ?? "nothing")")
        for name in ReminderKitProbe.classes { dumpClass(name) }
        scanImage()
        let storage = try session.storage(of: list).list
        probeList(storage, session: session)
        try probeSections(of: storage, session: session)
        try probeReminders(of: storage, session: session)
        if options.changeItem { try probeChangeItem(of: storage, session: session) }
        heading("Done (nothing was saved)")
      }

      func heading(_ title: String) {
        write("\n== \(title)")
      }

      func matches(_ name: String, _ pattern: String) -> Bool {
        name.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
      }

      // MARK: Classes

      func dumpClass(_ name: String) {
        heading("class \(name)")
        guard var current: AnyClass = NSClassFromString(name) else {
          write("  missing")
          return
        }
        while ObjectIdentifier(current) != ObjectIdentifier(NSObject.self) {
          let image = class_getImageName(current).map { String(cString: $0) } ?? "?"
          write("  \(NSStringFromClass(current)) (\(image))")
          for line in members(of: current) where options.allSelectors || matches(line, ReminderKitProbe.classFilter) {
            write("    " + line)
          }
          guard let superclass = class_getSuperclass(current) else { break }
          current = superclass
        }
      }

      /// `@property name attributes`, `- selector types` and `+ selector types` lines for one class (not its
      /// superclasses).
      func members(of type: AnyClass) -> [String] {
        var lines: [String] = []
        var count: UInt32 = 0
        if let properties = class_copyPropertyList(type, &count) {
          for property in UnsafeBufferPointer(start: properties, count: Int(count)) {
            let attributes = property_getAttributes(property).map { String(cString: $0) } ?? ""
            lines.append("@property \(String(cString: property_getName(property))) \(attributes)")
          }
          free(properties)
        }
        let owners: [(String, AnyClass?)] = [("-", type), ("+", object_getClass(type))]
        for (prefix, owner) in owners {
          guard let owner, let methods = class_copyMethodList(owner, &count) else { continue }
          for method in UnsafeBufferPointer(start: methods, count: Int(count)) {
            let types = method_getTypeEncoding(method).map { String(cString: $0) } ?? ""
            lines.append("\(prefix) \(NSStringFromSelector(method_getName(method))) \(types)")
          }
          free(methods)
        }
        return lines.sorted()
      }

      /// Every class in ReminderKit's image with a method or property matching ``imageFilter``.
      func scanImage() {
        heading("ReminderKit classes with membership or ordering names")
        guard let anchor = NSClassFromString("REMStore"), let image = class_getImageName(anchor) else {
          write("  REMStore's image is unknown")
          return
        }
        var count: UInt32 = 0
        guard let names = objc_copyClassNamesForImage(image, &count) else {
          write("  no classes in \(String(cString: image))")
          return
        }
        defer { free(names) }
        write("  image: \(String(cString: image)), \(count) classes")
        let all = UnsafeBufferPointer(start: names, count: Int(count)).map { String(cString: $0) }.sorted()
        for name in all {
          guard let type = NSClassFromString(name) else { continue }
          for line in members(of: type) where matches(line, ReminderKitProbe.imageFilter) {
            write("  \(name) \(line)")
          }
        }
      }

      // MARK: The list

      func probeList(_ list: NSObject, session: ReminderKitSession) {
        heading("list \(Runtime.className(list)) \(Runtime.identifier(of: list) ?? "?")")
        probe(list, label: "list", keys: ReminderKitProbe.listKeys)
        if let storage = Runtime.object(list, "storage") {
          write("  storage: \(Runtime.className(storage))")
          probe(storage, label: "storage", keys: ReminderKitProbe.listKeys)
          if let map = Runtime.object(storage, "cdKeyToStorageKeyMap") as? NSDictionary {
            write("  storage.cdKeyToStorageKeyMap (\(map.count) keys), matching:")
            for (key, value) in map {
              let line = "\(key) -> \(value)"
              if options.allSelectors || matches(line, ReminderKitProbe.classFilter) { write("    " + line) }
            }
          }
        }
        if let context = Runtime.object(list, "sectionContext") {
          write("  sectionContext: \(Runtime.className(context))")
          probe(context, label: "sectionContext", keys: ReminderKitProbe.listKeys)
        }
        var probes: [String] = []
        let order = ReminderKitSession.sectionOrder(of: list, probes: &probes)
        write("  section order used: \(order.map { "\($0.selector) \($0.value)" } ?? "none")")
        write("  section order probes: \(probes.isEmpty ? "none" : probes.joined(separator: ", "))")
        let manual = ReminderKitSession.manualReminderOrder(of: list)
        write("  manual reminder order: \(manual.map { "\($0.selector) \($0.value?.count ?? 0) ids" } ?? "none")")
      }

      /// Each of `keys` the object responds to, with its value.
      func probe(_ object: NSObject, label: String, keys: [String]) {
        for key in keys where object.responds(to: NSSelectorFromString(key)) {
          write("  \(label).\(key) = \(Self.describe(object.value(forKey: key)))")
        }
      }

      // MARK: Sections

      func probeSections(of list: NSObject, session: ReminderKitSession) throws(RemindersError) {
        let sections = try session.sections(of: list)
        heading("sections, in fetchListSectionsInList:error: order (\(sections.count))")
        for (index, section) in sections.enumerated() {
          write("  [\(index)] \(Runtime.identifier(of: section) ?? "?") \(Runtime.className(section))")
          probe(section, label: "  section", keys: ReminderKitProbe.sectionKeys)
          if let storage = Runtime.object(section, "storage") {
            probe(storage, label: "  storage", keys: ReminderKitProbe.sectionKeys)
          }
        }
      }

      // MARK: Reminders

      func probeReminders(of list: NSObject, session: ReminderKitSession) throws(RemindersError) {
        guard let listID = Runtime.object(list, "objectID") else { return }
        let view = try Runtime.make("REMRemindersDataView", initWithStore: session.store)
        let reminders = try Runtime.fetchReminders(in: listID, on: view)
        let fetch = "fetchListSectionWithReminderID:error:"
        heading("reminders (\(reminders.count), asking \(min(reminders.count, options.reminderLimit))) and \(fetch)")
        guard session.sectionsView.responds(to: NSSelectorFromString(fetch)) else {
          write("  REMListSectionsDataView doesn't respond to \(fetch)")
          return
        }
        var counts = (inSection: 0, inNone: 0, errors: 0)
        for reminder in reminders.prefix(options.reminderLimit) {
          let title = Runtime.string(reminder, "titleAsString") ?? "?"
          let completed = (Runtime.object(reminder, "completed") as? NSNumber)?.boolValue == true ? " (completed)" : ""
          var line = "  \(Runtime.identifier(of: reminder) ?? "?") \"\(title)\"\(completed) -> "
          if let objectID = Runtime.object(reminder, "objectID") {
            let (section, error) = Runtime.fetchOptionalObject(fetch, on: session.sectionsView, objectID)
            let outcome = SectionLookupOutcome(
              sectionID: section.flatMap(Runtime.identifier(of:)), error: error.map { ($0.domain, $0.code) })
            switch outcome {
            case .inSection(let id):
              counts.inSection += 1
              line += "\(id) \"\(section.flatMap { Runtime.string($0, "displayName") } ?? "?")\""
            case .notInSection:
              counts.inNone += 1
              line += "no section" + (error.map { " (\($0.domain) \($0.code))" } ?? "")
            case .failed:
              counts.errors += 1
              line += "ERROR" + (error.map { " \($0.domain) \($0.code): \($0.localizedDescription)" } ?? "")
            }
          }
          write(line)
          probe(reminder, label: "    reminder", keys: ReminderKitProbe.reminderKeys)
        }
        write("  asked: \(counts.inSection) in a section, \(counts.inNone) in none, \(counts.errors) errors")
        do throws(RemindersError) {
          let read = try session.memberships(of: list, reminderIDs: nil)
          write("  membership reader: \(read.value.count) in a section via \(read.selector)")
        } catch {
          write("  membership reader failed: \(error.code.rawValue) \(error.message)")
        }
      }

      // MARK: An unsaved change

      /// Builds the list change a move would, reads it and its sections context, and drops it unsaved.
      func probeChangeItem(of list: NSObject, session: ReminderKitSession) throws(RemindersError) {
        heading("unsaved list change (never saved)")
        guard let objectID = Runtime.object(list, "objectID") else { return }
        let request = try Runtime.make("REMSaveRequest", initWithStore: session.store)
        let fetched = try Runtime.fetchObject("fetchListWithObjectID:error:", on: session.store, objectID)
        guard let change = try Runtime.send("updateList:", to: request, fetched) else {
          write("  updateList: returned nothing")
          return
        }
        write("  change: \(Runtime.className(change))")
        probe(change, label: "change", keys: ReminderKitProbe.listKeys)
        if let context = Runtime.object(change, "sectionsContextChangeItem") {
          write("  sectionsContextChangeItem: \(Runtime.className(context))")
          probe(context, label: "sectionsContext", keys: ReminderKitProbe.listKeys)
        }
      }

      // MARK: Values

      /// A short, readable form of any value ReminderKit returns.
      static func describe(_ value: Any?, depth: Int = 0) -> String {
        guard let value else { return "nil" }
        let limit = 40
        switch value {
        case let data as Data:
          let text = String(data: data.prefix(600), encoding: .utf8)
          return "Data[\(data.count)] "
            + (text.map { "\"\($0)\"" } ?? data.prefix(64).map { String(format: "%02x", $0) }.joined())
        case let string as String:
          return "\"\(string.prefix(600))\""
        case let number as NSNumber:
          return number.stringValue
        case let uuid as NSUUID:
          return uuid.uuidString
        case let date as Date:
          return date.description
        default:
          break
        }
        guard let object = value as? NSObject else { return String(describing: value).prefix(600).description }
        let name = Runtime.className(object)
        if let uuid = Runtime.object(object, "uuid") as? NSUUID, object.responds(to: NSSelectorFromString("entityName"))
        {
          return "\(name)(\(uuid.uuidString) \(Runtime.string(object, "entityName") ?? ""))"
        }
        if depth < 2, let elements = Runtime.elements(object) {
          let shown = elements.prefix(limit).map { describe($0, depth: depth + 1) }
          return "\(name)[\(elements.count)] [" + shown.joined(separator: ", ")
            + (elements.count > limit ? ", ..." : "") + "]"
        }
        if depth < 2, let dictionary = object as? NSDictionary {
          let shown = dictionary.allKeys.prefix(limit).map { key in
            "\(describe(key, depth: depth + 1)): \(describe(dictionary[key], depth: depth + 1))"
          }
          return "\(name){\(dictionary.count)} {" + shown.joined(separator: ", ") + "}"
        }
        if depth < 2, object.responds(to: NSSelectorFromString("memberIdentifier")) {
          let parts = ["memberIdentifier", "groupIdentifier", "isObsolete", "modifiedOn"].map { key in
            "\(key)=\(describe(Runtime.object(object, key), depth: depth + 1))"
          }
          return "\(name)(" + parts.joined(separator: " ") + ")"
        }
        if depth < 2, object.responds(to: NSSelectorFromString("membershipByMemberIdentifier")) {
          return "\(name) membershipByMemberIdentifier="
            + describe(Runtime.object(object, "membershipByMemberIdentifier"), depth: depth + 1)
        }
        return "\(name) " + String(describing: object).prefix(600)
      }
    }
  }
#endif
