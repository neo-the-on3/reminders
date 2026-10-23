import Foundation
import Testing

@testable import RemindersCore

private func day(_ text: String) -> CalendarDay { CalendarDay(text)! }

/// Groceries and Work, with reminders overdue, due today, tomorrow, next week, undated and completed.
/// "Today" is 2026-10-23 (UTC).
private func makeStore(access: ReminderAccess = .fullAccess) -> InMemoryReminderStore {
  InMemoryReminderStore(
    lists: [ReminderList(id: "W", title: "Work"), ReminderList(id: "G", title: "Groceries")],
    reminders: [
      Reminder(id: "G1", title: "Buy milk", listID: "G", listName: "Groceries", dueDate: day("2026-10-23")),
      Reminder(id: "G2", title: "Buy bread", listID: "G", listName: "Groceries", dueDate: day("2026-10-20")),
      Reminder(id: "G3", title: "Buy eggs", isCompleted: true, listID: "G", listName: "Groceries"),
      Reminder(
        id: "W1", title: "Write report", listID: "W", listName: "Work", dueDate: day("2026-10-24"),
        notes: "Quarterly NUMBERS"),
      Reminder(id: "W2", title: "Plan offsite", listID: "W", listName: "Work", dueDate: day("2026-10-30")),
      Reminder(id: "W3", title: "Inbox zero", listID: "W", listName: "Work"),
    ], access: access, now: { referenceInstant })
}

private func makeService(_ store: InMemoryReminderStore) -> RemindersService {
  RemindersService(store: store, clock: utcClock)
}

@Suite("Reminders service: queries")
struct ServiceQueryTests {
  @Test("lists are sorted by title with incomplete and overdue counts")
  func lists() async throws {
    let lists = try await makeService(makeStore()).lists()
    #expect(lists.map(\.title) == ["Groceries", "Work"])
    #expect(lists.map(\.reminderCount) == [2, 3])
    // Only "Buy bread" (due 2026-10-20) is overdue; "Buy milk" is due today.
    #expect(lists.map(\.overdueCount) == [1, 0])
  }

  @Test("list counts, overdue and today agree on what is overdue, at any time of day")
  func overdueAgrees() async throws {
    for hour in [0, 10, 23] {
      let now = Date(timeIntervalSince1970: 1_792_713_600 + Double(hour) * 3600)  // 2026-10-23 at `hour` UTC
      let store = makeStore()
      let service = RemindersService(store: store, clock: DayClock(now: now, timeZone: .gmt))
      let counted = try await service.lists().reduce(0) { $0 + $1.overdueCount }
      let overdue = try await service.overdue().reminders.map(\.id)
      #expect(counted == overdue.count, "at \(hour):00")
      #expect(overdue == ["G2"], "at \(hour):00")
      #expect(try await service.dueToday().reminders.map(\.id) == ["G1"], "at \(hour):00")
    }
  }

  @Test("list shows incomplete reminders, then completed ones on request")
  func contents() async throws {
    let service = makeService(makeStore())
    let open = try await service.contents(ofList: "groc")
    #expect(open.heading == "Groceries")
    // Earliest due first, as in the text output.
    #expect(open.reminders.map(\.id) == ["G2", "G1"])
    let all = try await service.contents(ofList: "Groceries", includeCompleted: true)
    #expect(all.reminders.map(\.id) == ["G2", "G1", "G3"])
  }

  @Test("today, overdue and upcoming select by due day")
  func dueFilters() async throws {
    let service = makeService(makeStore())
    #expect(try await service.dueToday().reminders.map(\.id) == ["G1"])
    #expect(try await service.overdue().reminders.map(\.id) == ["G2"])
    let week = try await service.upcoming(days: 7)
    #expect(week.heading == "Due today and the next 7 days")
    #expect(try await service.upcoming(days: 0).heading == "Due today")
    #expect(try await service.upcoming(days: 1).heading == "Due today or tomorrow")
    #expect(Set(week.reminders.map(\.id)) == ["G1", "W1", "W2"])
    #expect(Set(try await service.upcoming(days: 1).reminders.map(\.id)) == ["G1", "W1"])
  }

  @Test("upcoming runs from today through today + N days, without overdue reminders", arguments: [0, 1, 6])
  func upcomingBoundaries(days: Int) async throws {
    let today = utcClock.today
    let due = [
      ("yesterday", today.adding(days: -1)), ("today", today), ("last day", today.adding(days: days)),
      ("day after", today.adding(days: days + 1)),
    ]
    let store = InMemoryReminderStore(
      lists: [ReminderList(id: "L", title: "Inbox")],
      reminders: due.map { Reminder(id: $0.0, title: $0.0, listID: "L", listName: "Inbox", dueDate: $0.1) },
      now: { referenceInstant })
    let upcoming = try await makeService(store).upcoming(days: days)
    #expect(Set(upcoming.reminders.map(\.id)) == ["today", "last day"])
    #expect(try await makeService(store).overdue().reminders.map(\.id) == ["yesterday"])
  }

  @Test("upcoming rejects a negative number of days")
  func upcomingNegative() async throws {
    await #expect(throws: RemindersError.self) { try await makeService(makeStore()).upcoming(days: -1) }
  }

  @Test("search matches titles and notes, ignoring case, incomplete only")
  func search() async throws {
    let service = makeService(makeStore())
    #expect(try await service.search("BUY").reminders.map(\.id) == ["G2", "G1"])
    #expect(try await service.search("numbers").reminders.map(\.id) == ["W1"])
    #expect(try await service.search("eggs").reminders.isEmpty)
    #expect(try await service.search("x").heading == "Search: \"x\"")
  }

  @Test("an unknown list is LIST_NOT_FOUND")
  func unknownList() async {
    await #expect(throws: RemindersError.self) { try await makeService(makeStore()).contents(ofList: "Garden") }
    do {
      _ = try await makeService(makeStore()).contents(ofList: "Garden")
    } catch {
      #expect(error.code == .listNotFound)
    }
  }
}

@Suite("Reminders service: changes")
struct ServiceChangeTests {
  @Test("add resolves the list, parses the due date and recurrence, and returns the new id")
  func add() async throws {
    let store = makeStore()
    let confirmation = try await makeService(store).add(
      NewReminderRequest(list: "work", title: "Ship it", due: "tomorrow", priority: .high, repeatRule: "weekly"))
    #expect(confirmation.message == "Added \"Ship it\" to \"Work\" (repeats weekly)")
    let added = try #require(await store.allReminders.first { $0.id == confirmation.id })
    #expect(added.listID == "W")
    #expect(added.dueDate == day("2026-10-24"))
    #expect(added.priority == .high)
    #expect(added.recurrence == Recurrence(.weekly))
  }

  @Test("add rejects a bad due date before creating anything")
  func addInvalidDate() async {
    let store = makeStore()
    await #expect(throws: RemindersError.self) {
      try await makeService(store).add(NewReminderRequest(list: "Work", title: "X", due: "2026-02-30"))
    }
    #expect(await store.allReminders.count == 6)
  }

  @Test("complete finds by title and marks the reminder done")
  func complete() async throws {
    let store = makeStore()
    let confirmation = try await makeService(store).complete(ReminderReference(list: "Groceries", title: "milk"))
    #expect(confirmation.message == "Completed \"Buy milk\" in \"Groceries\"")
    let milk = try #require(await store.allReminders.first { $0.id == "G1" })
    #expect(milk.isCompleted)
    #expect(milk.completionDate == referenceInstant)
  }

  @Test("update changes only the given fields, and --clear-due removes the date")
  func update() async throws {
    let store = makeStore()
    let service = makeService(store)
    let confirmation = try await service.update(
      ReminderReference(list: "Work", title: "Write report"), ReminderEdit(title: "Write the report", priority: .low))
    #expect(confirmation.message == "Updated \"Write report\" in \"Work\"")
    var report = try #require(await store.allReminders.first { $0.id == "W1" })
    #expect(report.title == "Write the report")
    #expect(report.priority == .low)
    #expect(report.dueDate == day("2026-10-24"))
    #expect(report.notes == "Quarterly NUMBERS")

    _ = try await service.update(
      ReminderReference(list: "Work", title: "Write the report"), ReminderEdit(clearDue: true))
    report = try #require(await store.allReminders.first { $0.id == "W1" })
    #expect(report.dueDate == nil)
  }

  @Test("delete finds completed reminders too, and by ID prefix")
  func delete() async throws {
    let store = makeStore()
    let service = makeService(store)
    let confirmation = try await service.delete(ReminderReference(list: "Groceries", title: "Buy eggs"))
    #expect(confirmation.message == "Deleted \"Buy eggs\" from \"Groceries\"")
    _ = try await service.delete(ReminderReference(list: "Groceries", title: "anything", id: "g2"))
    #expect(await store.allReminders.map(\.id) == ["G1", "W1", "W2", "W3"])
  }

  @Test("create-list reuses a list with exactly that title")
  func createList() async throws {
    let store = makeStore()
    let service = makeService(store)
    let existing = try await service.createList(named: "Work")
    #expect(existing.id == "W")
    let new = try await service.createList(named: "work")
    #expect(new.message == "Created list \"work\"")
    #expect(new.id != "W")
    #expect(try await store.lists().count == 3)
  }

  @Test("delete-list removes the list and its reminders")
  func deleteList() async throws {
    let store = makeStore()
    let confirmation = try await makeService(store).deleteList(named: "groceries")
    #expect(confirmation.message == "Deleted list \"Groceries\"")
    #expect(try await store.lists().map(\.id) == ["W"])
    #expect(await store.allReminders.allSatisfy { $0.listID == "W" })
  }
}

@Suite("Reminders service: access")
struct ServiceAccessTests {
  @Test("an undecided user is asked, and the answer is kept")
  func prompts() async throws {
    let store = makeStore(access: .notDetermined)
    #expect(try await makeService(store).lists().count == 2)
    #expect(await store.accessStatus() == .fullAccess)
  }

  @Test("anything but full access is PERMISSION_DENIED, sending the user to System Settings for the host app")
  func denied() async {
    let claude = PermissionGuidance(host: HostApplication(name: "Claude", bundlePath: "/Applications/Claude.app"))
    let expected: [(ReminderAccess, String, String)] = [
      (.denied, "Denied for Claude", "Enable Claude in System Settings > Privacy & Security > Reminders"),
      (.restricted, "Restricted for Claude", "device management or Screen Time"),
      (.writeOnly, "Write-only for Claude", "Choose Full Access for Claude in System Settings"),
    ]
    for (access, status, remedy) in expected {
      do {
        _ = try await RemindersService(store: makeStore(access: access), clock: utcClock, permissions: claude)
          .dueToday()
        Issue.record("expected PERMISSION_DENIED for \(access)")
      } catch {
        #expect(error.code == .permissionDenied)
        #expect(error.message.contains(status), "\(error.message)")
        #expect(error.suggestion?.contains(remedy) == true, "\(error.suggestion ?? "")")
        #expect(error.suggestion?.contains("Run: reminders authorize") == false)
      }
    }
  }

  @Test("a refused prompt is PERMISSION_DENIED; without a known host the terminal app is named")
  func refusedPrompt() async {
    let store = InMemoryReminderStore(access: .notDetermined, promptAnswer: .denied)
    do {
      _ = try await makeService(store).lists()
      Issue.record("expected PERMISSION_DENIED")
    } catch {
      #expect(error.code == .permissionDenied)
      #expect(error.suggestion?.hasPrefix("Enable your terminal app in System Settings") == true)
    }
  }

  @Test("a request macOS never answers is PERMISSION_DENIED naming the app that couldn't ask")
  func unprompted() async {
    let claude = PermissionGuidance(host: HostApplication(name: "Claude", bundlePath: "/Applications/Claude.app"))
    let store = InMemoryReminderStore(access: .notDetermined, promptAnswer: .notDetermined)
    do {
      _ = try await RemindersService(store: store, clock: utcClock, permissions: claude).lists()
      Issue.record("expected PERMISSION_DENIED")
    } catch {
      #expect(error.code == .permissionDenied)
      #expect(error.message == "Reminders access not granted (macOS didn't show the prompt for Claude)")
      #expect(error.suggestion?.hasPrefix("Enable Claude in System Settings > Privacy & Security > Reminders") == true)
    }
  }

  @Test("a platform without Reminders is UNSUPPORTED_PLATFORM")
  func unavailable() async {
    await #expect(throws: RemindersError.unsupportedPlatform) {
      try await makeService(makeStore(access: .unavailable)).lists()
    }
  }
}
