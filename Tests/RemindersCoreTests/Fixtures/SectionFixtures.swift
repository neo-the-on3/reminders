// Section data as Reminders stores it on a list.
//
// SYNTHETIC: these values follow the documented formats of Reminders' membership data
// (MembershipsOfRemindersInSectionsAsData) and resolution token map.

import Foundation

@testable import RemindersCore

enum SectionFixtures {
  static let groceries = ReminderList(id: "LIST-GROCERIES", title: "Groceries")

  /// Section identifiers: dashed upper-case UUIDs, as in `groupID`.
  static let dairyID = "2F1C9A0E-6B7D-4E21-9C35-0A8B7D6E5F41"
  static let produceID = "8D4E2B1A-3C5F-4A60-B7E9-1F2D3C4B5A69"

  /// Reminder identifiers: EventKit's `calendarItemIdentifier`, which membership data spells as `memberID`.
  static let milkID = "5A0B1C2D-3E4F-4A5B-8C6D-7E8F9A0B1C2D"
  static let breadID = "6B1C2D3E-4F5A-4B6C-9D7E-8F9A0B1C2D3E"
  static let applesID = "7C2D3E4F-5A6B-4C7D-8E8F-9A0B1C2D3E4F"

  static let sections = [
    Section(id: dairyID, displayName: "Dairy", listName: "Groceries", sortOrder: 0),
    Section(id: produceID, displayName: "Produce", listName: "Groceries", sortOrder: 1),
  ]

  /// Milk in Dairy, apples in Produce. Compact JSON in Reminders' key order, `modifiedOn` in seconds since 2001.
  static let memberships =
    #"{"minimumSupportedVersion":20230430,"memberships":[{"memberID":"\#(milkID)","groupID":"\#(dairyID)","modifiedOn":782900000.123456},{"memberID":"\#(applesID)","groupID":"\#(produceID)","modifiedOn":782900100}]}"#

  static var stored: StoredMemberships { StoredMemberships(data: memberships) }

  static let reminders = [
    Reminder(id: milkID, title: "Milk", listID: groceries.id, listName: "Groceries"),
    Reminder(id: breadID, title: "Bread", listID: groceries.id, listName: "Groceries"),
    Reminder(id: applesID, title: "Apples", listID: groceries.id, listName: "Groceries"),
  ]
}
