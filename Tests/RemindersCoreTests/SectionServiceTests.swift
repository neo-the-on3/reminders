import Foundation
import Synchronization
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

@Suite("Sections: membership edits")
struct SectionEditTests {
  @Test("move writes new memberships, their checksum and a bumped token map in one replacement")
  func move() async throws {
    let (service, _, sectionStore) = makeService()
    let result = try await service.move(ReminderReference(list: "Groceries", title: "Bread"), toSection: "Produce")
    #expect(result.message == "Moved \"Bread\" to section \"Produce\" in \"Groceries\"")
    #expect(await sectionStore.writeCount == 1)

    let stored = await sectionStore.memberships(of: Fixture.groceries)
    let data = try #require(stored.data)
    #expect(stored.checksum == SHA512Digest.hex(of: data.utf8))
    // The existing entries stay byte for byte; the new one is appended with the current time.
    #expect(
      data
        == Fixture.memberships.dropLast(2)
        + #",{"memberID":"\#(Fixture.breadID)","groupID":"\#(Fixture.produceID)","modifiedOn":\#(PersistedJSON.format(referenceInstant.timeIntervalSinceReferenceDate))}]}"#
    )
    let tokens = ResolutionTokenMap(storedData: stored.tokenMap)
    #expect(tokens.counter(of: .memberships) == 4)
    #expect(tokens.counter(of: .ordering) == 8)
    #expect(tokens.replicaID(of: .memberships) == "0D5E8F4A-1B2C-4D3E-9F5A-6B7C8D9E0F1A")
    #expect(stored.tokenMap?.contains(#""name":{"counter":1,"modificationTime":780000000"#) == true)
  }

  @Test("moving a reminder to the section it is in writes nothing")
  func moveNoOp() async throws {
    let (service, _, sectionStore) = makeService()
    let result = try await service.move(ReminderReference(list: "Groceries", title: "Milk"), toSection: "Dairy")
    #expect(result.message == "\"Milk\" is already in section \"Dairy\" in \"Groceries\"")
    #expect(await sectionStore.writeCount == 0)
    #expect(await sectionStore.memberships(of: Fixture.groceries) == Fixture.stored)
  }

  @Test("moving takes the reminder out of its old section")
  func moveBetweenSections() async throws {
    let (service, _, sectionStore) = makeService()
    _ = try await service.move(ReminderReference(list: "Groceries", title: "Milk"), toSection: "Produce")
    let entries = try await storedEntries(sectionStore)
    #expect(entries.filter { $0.reminderID == Fixture.milkID }.map(\.sectionID) == [Fixture.produceID])
  }

  @Test("the first membership of a list starts a fresh document and token map")
  func firstMembership() async throws {
    let (service, _, sectionStore) = makeService(memberships: StoredMemberships())
    _ = try await service.move(ReminderReference(list: "Groceries", title: "Bread"), toSection: "Dairy")
    let stored = await sectionStore.memberships(of: Fixture.groceries)
    #expect(stored.data?.hasPrefix(#"{"minimumSupportedVersion":20230430,"memberships":[{"memberID":""#) == true)
    #expect(ResolutionTokenMap(storedData: stored.tokenMap).counter(of: .memberships) == 1)
    #expect(ResolutionTokenMap(storedData: stored.tokenMap).counter(of: .ordering) == nil)
  }

  @Test("add --section creates the reminder and puts it in the section; a bad section adds nothing")
  func addToSection() async throws {
    let (service, store, sectionStore) = makeService()
    let added = try await service.add(NewReminderRequest(list: "Groceries", title: "Cheese", section: "dairy"))
    #expect(added.message == "Added \"Cheese\" to \"Groceries\" in section \"Dairy\"")
    let id = try #require(added.id)
    #expect(try await storedEntries(sectionStore).last?.reminderID == id.uppercased())

    await #expect(throws: RemindersError.self) {
      try await service.add(NewReminderRequest(list: "Groceries", title: "Ice", section: "Frozen"))
    }
    #expect(await store.allReminders.count == 4)
  }

  @Test("deleting a section removes its memberships")
  func deleteSection() async throws {
    let (service, _, sectionStore) = makeService()
    let result = try await service.deleteSection(named: "Dairy", inList: "Groceries")
    #expect(result.message == "Deleted section \"Dairy\" from \"Groceries\"")
    #expect(await sectionStore.sections(in: Fixture.groceries).map(\.displayName) == ["Produce"])
    #expect(try await storedEntries(sectionStore).map(\.reminderID) == [Fixture.applesID])
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

  @Test("a concurrent change is retried on the new data, and reported after repeated conflicts")
  func conflicts() async throws {
    let (service, _, sectionStore) = makeService()
    // Reminders moves Apples out of Produce once, just before our write.
    let changed = Fixture.memberships.replacingOccurrences(
      of: #",{"memberID":"\#(Fixture.applesID)","groupID":"\#(Fixture.produceID)","modifiedOn":782900100}"#, with: "")
    let once = OnceFlag()
    await sectionStore.interfere { _ in once.take() ? StoredMemberships(data: changed, tokenMap: Fixture.tokenMap) : nil
    }
    _ = try await service.move(ReminderReference(list: "Groceries", title: "Bread"), toSection: "Dairy")
    let entries = try await storedEntries(sectionStore)
    #expect(entries.map(\.reminderID) == [Fixture.milkID, Fixture.breadID])  // built on Reminders' change, not over it

    // Reminders changes the data before every attempt.
    let writes = Mutex(0)
    await sectionStore.interfere { _ in
      StoredMemberships(
        data: changed
          + String(
            repeating: " ",
            count: writes.withLock {
              $0 += 1; return $0
            }))
    }
    await #expect(throws: RemindersError.membershipConflict) {
      try await service.move(ReminderReference(list: "Groceries", title: "Apples"), toSection: "Dairy")
    }
  }

  @Test("data whose checksum doesn't match is never edited")
  func corrupt() async throws {
    let (service, _, sectionStore) = makeService(
      memberships: StoredMemberships(data: Fixture.memberships, checksum: String(repeating: "0", count: 128)))
    do {
      _ = try await service.move(ReminderReference(list: "Groceries", title: "Bread"), toSection: "Dairy")
      Issue.record("expected the edit to be refused")
    } catch {
      #expect(error.code == .storeFailure)
    }
    #expect(await sectionStore.writeCount == 0)
    // Reading still works, and an upper-case checksum counts as matching.
    let upper = StoredMemberships(data: Fixture.memberships, checksum: Fixture.stored.checksum?.uppercased())
    #expect(!SectionMemberships.isCorrupt(upper))
  }
}

/// True the first time it is taken.
private final class OnceFlag: Sendable {
  private let taken = Mutex(false)
  func take() -> Bool {
    taken.withLock { value in
      defer { value = true }; return !value
    }
  }
}
