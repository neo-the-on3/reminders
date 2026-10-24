import Foundation
import Testing

@testable import RemindersCore

private typealias Fixture = SectionFixtures

/// The service on the fixture list: Milk in Dairy, Apples in Produce, Bread in no section.
private func makeService(
  memberships: StoredMemberships = Fixture.stored, sections: [Section] = Fixture.sections
) -> (RemindersService, InMemoryReminderStore, InMemorySectionStore) {
  let store = InMemoryReminderStore(lists: [Fixture.groceries], reminders: Fixture.reminders, now: { referenceInstant })
  let sectionStore = InMemorySectionStore(
    sections: [Fixture.groceries.id: sections], memberships: [Fixture.groceries.id: memberships])
  return (RemindersService(store: store, sections: sectionStore, clock: utcClock), store, sectionStore)
}

private func storedEntries(_ sectionStore: InMemorySectionStore) async throws -> [SectionMemberships.Entry] {
  try SectionMemberships(storedData: await sectionStore.memberships(of: Fixture.groceries).data).entries
}

@Suite("Sections: reading")
struct SectionReadingTests {
  @Test("sections are listed in order with their incomplete reminder counts")
  func sections() async throws {
    let (service, _, _) = makeService()
    let listing = try await service.sections(ofList: "groc")
    #expect(listing.sections.map(\.displayName) == ["Dairy", "Produce"])
    #expect(listing.counts == ["Dairy": 1, "Produce": 1])
  }

  @Test("list tags reminders with their section; --section keeps only that section")
  func listing() async throws {
    let (service, _, _) = makeService()
    let all = try await service.contents(ofList: "Groceries")
    #expect(
      Dictionary(uniqueKeysWithValues: all.reminders.map { ($0.title, $0.section) }) == [
        "Milk": "Dairy", "Bread": nil, "Apples": "Produce",
      ])
    let dairy = try await service.contents(ofList: "Groceries", section: "dai")
    #expect(dairy.reminders.map(\.title) == ["Milk"])
    #expect(dairy.heading == "Groceries › Dairy")
    await #expect(throws: RemindersError.self) { try await service.contents(ofList: "Groceries", section: "Frozen") }
  }

  @Test("memberships of deleted sections and lowercase identifiers are handled")
  func staleEntries() async throws {
    let lowercase = Fixture.memberships.replacingOccurrences(of: Fixture.milkID, with: Fixture.milkID.lowercased())
    let (service, _, _) = makeService(memberships: StoredMemberships(data: lowercase), sections: [Fixture.sections[1]])
    let all = try await service.contents(ofList: "Groceries")
    #expect(all.reminders.first { $0.title == "Milk" }?.section == nil)  // Dairy no longer exists
    #expect(all.reminders.first { $0.title == "Apples" }?.section == "Produce")
  }

  @Test("without a section store the list still shows, but --section and sections fail")
  func noSectionStore() async throws {
    let store = InMemoryReminderStore(lists: [Fixture.groceries], reminders: Fixture.reminders)
    let service = RemindersService(store: store, clock: utcClock)
    #expect(try await service.contents(ofList: "Groceries").reminders.count == 3)
    await #expect(throws: RemindersError.notImplemented("Sections")) {
      try await service.contents(ofList: "Groceries", section: "Dairy")
    }
    await #expect(throws: RemindersError.notImplemented("Sections")) { try await service.sections(ofList: "Groceries") }
  }
  @Test("list groups reminders in section order, whatever order the store returns them in")
  func sectionOrder() async throws {
    // As captured on a Mac: EventKit returned Gamma's reminder first, then Beta's, then Alpha's, then the ungrouped.
    let list = ReminderList(id: "LIST-PORT", title: "Port")
    let sectionIDs = (0..<3).map { "00000000-0000-4000-8000-00000000000\($0)" }
    let sections = zip(["Alpha", "Beta", "Gamma"], sectionIDs).enumerated().map { order, pair in
      Section(id: pair.1, displayName: pair.0, listName: list.title, sortOrder: order)
    }
    let reminderIDs = (1...5).map { "00000000-0000-4000-9000-00000000000\($0)" }
    let memberships = zip(reminderIDs.prefix(4), [0, 0, 1, 2]).map { reminder, section in
      #"{"memberID":"\#(reminder)","groupID":"\#(sectionIDs[section])","modifiedOn":782900000}"#
    }
    let data = #"{"minimumSupportedVersion":20230430,"memberships":["# + memberships.joined(separator: ",") + "]}"
    let reminders = [4, 3, 1, 2, 5].map { number in
      Reminder(id: reminderIDs[number - 1], title: "Port test \(number)", listID: list.id, listName: list.title)
    }
    let store = InMemoryReminderStore(lists: [list], reminders: reminders, now: { referenceInstant })
    let sectionStore = InMemorySectionStore(
      sections: [list.id: sections], memberships: [list.id: StoredMemberships(data: data)])
    let service = RemindersService(store: store, sections: sectionStore, clock: utcClock)

    let listing = try await service.contents(ofList: "Port")
    #expect(listing.reminders.map(\.title) == (1...5).map { "Port test \($0)" })
    #expect(listing.reminders.map(\.section) == ["Alpha", "Alpha", "Beta", "Gamma", nil])

    let (console, output, _) = makeConsole()
    console.show(listing)
    let groups = ["Alpha", "Beta", "Gamma", "Others"]
    let headings = output.text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
    #expect(headings.filter(groups.contains) == groups)
  }
}

@Suite("Sections: changes")
struct SectionEditTests {
  @Test("move hands one assignment to the section store, which writes the memberships")
  func move() async throws {
    let (service, _, sectionStore) = makeService()
    let result = try await service.move(ReminderReference(list: "Groceries", title: "Bread"), toSection: "Produce")
    #expect(result.message == "Moved \"Bread\" to section \"Produce\" in \"Groceries\"")
    let assignments = await sectionStore.assignments
    #expect(assignments.map(\.reminderID) == [Fixture.breadID])
    #expect(assignments.map(\.sectionID) == [Fixture.produceID])
    let bread = try await service.contents(ofList: "Groceries").reminders.first { $0.title == "Bread" }
    #expect(bread?.section == "Produce")
  }

  @Test("moving a reminder to the section it is in changes nothing")
  func moveNoOp() async throws {
    let (service, _, sectionStore) = makeService()
    let result = try await service.move(ReminderReference(list: "Groceries", title: "Milk"), toSection: "Dairy")
    #expect(result.message == "\"Milk\" is already in section \"Dairy\" in \"Groceries\"")
    #expect(await sectionStore.assignments.isEmpty)
    #expect(await sectionStore.memberships(of: Fixture.groceries) == Fixture.stored)
  }

  @Test("moving takes the reminder out of its old section")
  func moveBetweenSections() async throws {
    let (service, _, sectionStore) = makeService()
    _ = try await service.move(ReminderReference(list: "Groceries", title: "Milk"), toSection: "Produce")
    let entries = try await storedEntries(sectionStore)
    #expect(entries.filter { $0.reminderID == Fixture.milkID }.map(\.sectionID) == [Fixture.produceID])
  }

  @Test("an unknown section or reminder changes nothing")
  func movePreconditions() async throws {
    let (service, _, sectionStore) = makeService()
    await #expect(throws: RemindersError.self) {
      try await service.move(ReminderReference(list: "Groceries", title: "Bread"), toSection: "Frozen")
    }
    await #expect(throws: RemindersError.self) {
      try await service.move(ReminderReference(list: "Groceries", title: "Caviar"), toSection: "Dairy")
    }
    #expect(await sectionStore.assignments.isEmpty)
  }

  @Test("add --section creates the reminder and puts it in the section; a bad section adds nothing")
  func addToSection() async throws {
    let (service, store, sectionStore) = makeService()
    let added = try await service.add(NewReminderRequest(list: "Groceries", title: "Cheese", section: "dairy"))
    #expect(added.message == "Added \"Cheese\" to \"Groceries\" in section \"Dairy\"")
    let id = try #require(added.id)
    #expect(await sectionStore.assignments.last?.reminderID == id.uppercased())

    await #expect(throws: RemindersError.self) {
      try await service.add(NewReminderRequest(list: "Groceries", title: "Ice", section: "Frozen"))
    }
    #expect(await store.allReminders.count == 4)
  }

  @Test("when the section can't be set, add says the reminder was added and how to finish")
  func addToSectionFailure() async throws {
    let (service, store, sectionStore) = makeService()
    await sectionStore.failNextAssignment(with: RemindersError(.reminderKitUnavailable, "missing"))
    do {
      _ = try await service.add(NewReminderRequest(list: "Groceries", title: "Cheese", section: "Dairy"))
      Issue.record("expected an error")
    } catch {
      #expect(error.code == .reminderKitUnavailable)
      #expect(error.message.hasPrefix("Added \"Cheese\" to \"Groceries\", but not to section \"Dairy\""))
      #expect(error.suggestion?.contains("move") == true)
    }
    #expect(await store.allReminders.count == 4)
  }

  @Test("deleting a section leaves memberships to Reminders")
  func deleteSection() async throws {
    let (service, _, sectionStore) = makeService()
    let result = try await service.deleteSection(named: "Dairy", inList: "Groceries")
    #expect(result.message == "Deleted section \"Dairy\" from \"Groceries\"")
    #expect(await sectionStore.sections(in: Fixture.groceries).map(\.displayName) == ["Produce"])
    // Milk's entry for the gone section stays, and is ignored when reading.
    #expect(await sectionStore.memberships(of: Fixture.groceries) == Fixture.stored)
    #expect(await sectionStore.assignments.isEmpty)
    let milk = try await service.contents(ofList: "Groceries").reminders.first { $0.title == "Milk" }
    #expect(milk?.section == nil)
  }

  @Test("delete-section with an unknown list or section deletes nothing")
  func deleteSectionPreconditions() async throws {
    let (service, _, sectionStore) = makeService()
    await #expect(throws: RemindersError.self) { try await service.deleteSection(named: "Frozen", inList: "Groceries") }
    await #expect(throws: RemindersError.self) { try await service.deleteSection(named: "Dairy", inList: "Nope") }
    #expect(await sectionStore.sections(in: Fixture.groceries).map(\.displayName) == ["Dairy", "Produce"])
  }

  @Test("creating a section reuses one with exactly that name")
  func createSection() async throws {
    let (service, _, sectionStore) = makeService()
    let again = try await service.createSection(named: "Dairy", inList: "Groceries")
    #expect(again.id == Fixture.dairyID)
    let frozen = try await service.createSection(named: "Frozen", inList: "Groceries")
    #expect(frozen.id != nil && frozen.id != Fixture.dairyID)
    #expect(await sectionStore.sections(in: Fixture.groceries).map(\.displayName) == ["Dairy", "Produce", "Frozen"])
  }
}
