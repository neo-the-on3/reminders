import RemindersCore

/// Sections read straight from Reminders' SQLite databases, which EventKit doesn't expose.
///
/// Every call opens the databases read-only and closes them again, so it sees what Reminders last saved and never
/// changes anything. Reading needs Full Disk Access for the app running `reminders`. Changing sections isn't
/// available yet.
public struct DatabaseSectionStore: SectionStore {
  private let system: any SystemProbe
  private let permissions: PermissionGuidance

  public init(system: any SystemProbe, permissions: PermissionGuidance) {
    self.system = system
    self.permissions = permissions
  }

  public func sections(in list: ReminderList) throws(RemindersError) -> [Section] {
    let (database, row) = try locate(list)
    let sections = try database.rows(
      "SELECT Z_PK, ZIDENTIFIER, ZDISPLAYNAME, ZMARKEDFORDELETION FROM ZREMCDBASESECTION WHERE ZLIST = ?",
      .integer(row.key)
    ).map { columns in
      DatabaseRows.Section(
        key: columns[0].integer ?? 0, identifier: columns[1].bytes.flatMap(DatabaseRows.identifier),
        displayName: columns[2].string, isMarkedForDeletion: (columns[3].integer ?? 0) != 0)
    }
    return DatabaseRows.sections(sections, inList: list.title)
  }

  public func memberships(of list: ReminderList) throws(RemindersError) -> StoredMemberships {
    let (database, row) = try locate(list)
    let columns = try database.rows(
      """
      SELECT ZMEMBERSHIPSOFREMINDERSINSECTIONSASDATA, ZMEMBERSHIPSOFREMINDERSINSECTIONSCHECKSUM,
        ZRESOLUTIONTOKENMAP_V3_JSONDATA
      FROM ZREMCDBASELIST WHERE Z_PK = ?
      """, .integer(row.key)
    ).first
    return StoredMemberships(data: columns?[0].string, checksum: columns?[1].string, tokenMap: columns?[2].string)
  }

  public func createSection(named name: String, in list: ReminderList) throws(RemindersError) -> Section {
    throw Self.readOnly
  }

  public func deleteSection(_ section: Section, in list: ReminderList) throws(RemindersError) {
    throw Self.readOnly
  }

  public func replaceMemberships(
    of list: ReminderList, with new: StoredMemberships, ifUnchangedFrom old: StoredMemberships
  ) throws(RemindersError) {
    throw Self.readOnly
  }

  private static let readOnly = RemindersError.notImplemented("Changing sections")

  // MARK: Finding the list

  /// The database holding `list` and its row there. Reminders keeps a database per account, so each is searched.
  private func locate(_ list: ReminderList) throws(RemindersError) -> (SQLiteDatabase, DatabaseRows.List) {
    var databases: [String: SQLiteDatabase] = [:]
    var rows: [DatabaseRows.List] = []
    for path in try databaseFiles() {
      let database: SQLiteDatabase
      do {
        database = try SQLiteDatabase(readOnlyAt: path)
      } catch {
        throw error.code == .permissionDenied ? permissions.fullDiskAccessError : error
      }
      // A file without Reminders' tables isn't a Reminders database; skip it.
      guard
        let found = try? database.rows(
          "SELECT Z_PK, ZIDENTIFIER, ZNAME FROM ZREMCDBASELIST WHERE ZMARKEDFORDELETION = 0 AND ZNAME IS NOT NULL")
      else { continue }
      databases[path] = database
      rows += found.map { columns in
        DatabaseRows.List(
          key: columns[0].integer ?? 0, identifier: columns[1].bytes.flatMap(DatabaseRows.identifier),
          name: columns[2].string ?? "", database: path)
      }
    }
    guard let row = DatabaseRows.row(for: list, in: rows), let database = databases[row.database] else {
      throw RemindersError(
        .listNotFound, "List \"\(list.title)\" not found in the Reminders database",
        suggestion: "If it was just created or renamed, wait a moment for Reminders to save it and try again")
    }
    return (database, row)
  }

  private func databaseFiles() throws(RemindersError) -> [String] {
    do {
      return try system.remindersDatabaseFiles()
    } catch  where error.code == .permissionDenied {
      throw permissions.fullDiskAccessError
    }
  }
}
