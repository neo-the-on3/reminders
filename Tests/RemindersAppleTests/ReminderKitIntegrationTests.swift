#if os(macOS)
  import Foundation
  import Testing

  @testable import RemindersApple
  @testable import RemindersCore

  /// Whether to touch the real Reminders: only with `REMINDERS_INTEGRATION=1`, on a Mac where the test runner has
  /// Reminders access and Full Disk Access.
  let integrationEnabled = ProcessInfo.processInfo.environment["REMINDERS_INTEGRATION"] == "1"

  /// A throwaway list, `_reminders_test_<random>`, created for one test and deleted by identifier afterwards, so
  /// nothing else is ever changed.
  struct ThrowawayList {
    static let sectionName = "_sections_test"

    let store = RemindersPlatform.makeStore()
    let list: ReminderList

    static func make() async throws -> ThrowawayList {
      let store = RemindersPlatform.makeStore()
      let title = "_reminders_test_\(UUID().uuidString.prefix(8))"
      let id = try await store.createList(title: title)
      return ThrowawayList(list: ReminderList(id: id, title: title))
    }

    func delete() async {
      try? await store.deleteList(id: list.id)
    }

    /// Polls `condition` for up to ten seconds: Reminders saves to its database a moment after a change.
    static func eventually(_ condition: () async throws -> Bool) async throws -> Bool {
      for _ in 0..<20 {
        if try await condition() { return true }
        try await Task.sleep(for: .milliseconds(500))
      }
      return false
    }
  }

  @Suite(
    "ReminderKit against this Mac's Reminders (REMINDERS_INTEGRATION=1)", .serialized,
    .enabled(if: integrationEnabled))
  struct ReminderKitIntegrationTests {
    @Test("a section is created and deleted in a throwaway list, as ReminderKit and the database see it")
    func createAndDelete() async throws {
      let throwaway = try await ThrowawayList.make()
      do {
        try await createAndDelete(in: throwaway)
      } catch {
        await throwaway.delete()
        throw error
      }
      await throwaway.delete()
    }

    private func createAndDelete(in throwaway: ThrowawayList) async throws {
      let service = RemindersPlatform.makeService()
      let title = throwaway.list.title
      let name = ThrowawayList.sectionName
      #expect(try await ThrowawayList.eventually { (try? await service.sections(ofList: title)) != nil })

      let created = try await service.createSection(named: name, inList: title)
      let id = try #require(created.id)
      #expect(try RuntimeReminderKit().sections(in: throwaway.list).contains { $0.id == id })
      #expect(
        try await ThrowawayList.eventually {
          try await service.sections(ofList: title).sections.contains { $0.id == id && $0.displayName == name }
        })
      #expect(try await service.createSection(named: name, inList: title).id == id)

      _ = try await service.deleteSection(named: name, inList: title)
      #expect(try !RuntimeReminderKit().sections(in: throwaway.list).contains { $0.id == id })
      #expect(try await ThrowawayList.eventually { try await service.sections(ofList: title).sections.isEmpty })
    }
  }
#endif
