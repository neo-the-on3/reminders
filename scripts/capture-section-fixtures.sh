#!/usr/bin/env bash
# Captures one list's section data from Apple Reminders as test fixtures, without touching the real database.
#
#   scripts/capture-section-fixtures.sh "<list name>" [output-dir]
#
# It copies the Reminders SQLite files (with their -wal and -shm) to a temporary directory, reads only that copy
# with `sqlite3 -readonly`, and deletes the copy afterwards. Nothing is ever opened for writing in
# ~/Library/Group Containers/group.com.apple.reminders. Needs Full Disk Access for the terminal app.
#
# Use a throwaway list (for example one made with `reminders create-list`): the output contains that list's
# section names, reminder titles and identifiers.
set -euo pipefail

list=${1:?usage: $0 "<list name>" [output-dir]}
out=${2:-section-fixtures}
stores="$HOME/Library/Group Containers/group.com.apple.reminders/Container_v1/Stores"

[[ -d $stores ]] || { echo "No Reminders data at $stores" >&2; exit 1; }
ls "$stores" >/dev/null 2>&1 || { echo "Cannot read $stores: grant Full Disk Access to this terminal" >&2; exit 1; }

snapshot=$(mktemp -d)
trap 'rm -rf "$snapshot"' EXIT
# -p keeps timestamps; the copies are what sqlite3 opens, never the originals.
for file in "$stores"/*.sqlite "$stores"/*.sqlite-wal "$stores"/*.sqlite-shm; do
  [[ -e $file ]] && cp -p "$file" "$snapshot/"
done

query() { sqlite3 -readonly -bail "$1" "$2"; }
quote() { printf "%s" "$1" | sed "s/'/''/g"; }

found=""
for db in "$snapshot"/*.sqlite; do
  count=$(query "$db" "SELECT count(*) FROM ZREMCDBASELIST WHERE ZNAME = '$(quote "$list")' AND ZMARKEDFORDELETION = 0" 2>/dev/null || echo 0)
  if [[ $count == 1 ]]; then found=$db; break; fi
  if [[ $count -gt 1 ]]; then echo "Several lists are named \"$list\" in $(basename "$db"); rename one" >&2; exit 1; fi
done
[[ -n $found ]] || { echo "No list named \"$list\"" >&2; exit 1; }

mkdir -p "$out"
db=$found
pk=$(query "$db" "SELECT Z_PK FROM ZREMCDBASELIST WHERE ZNAME = '$(quote "$list")' AND ZMARKEDFORDELETION = 0")
echo "Capturing \"$list\" (Z_PK $pk) from $(basename "$db") into $out/"

# Exact stored bytes, as hex, so nothing is re-encoded on the way out.
query "$db" "SELECT hex(ZMEMBERSHIPSOFREMINDERSINSECTIONSASDATA) FROM ZREMCDBASELIST WHERE Z_PK = $pk" | xxd -r -p >"$out/memberships.json"
query "$db" "SELECT hex(ZRESOLUTIONTOKENMAP_V3_JSONDATA) FROM ZREMCDBASELIST WHERE Z_PK = $pk" | xxd -r -p >"$out/tokenmap.json"
query "$db" "SELECT ZMEMBERSHIPSOFREMINDERSINSECTIONSCHECKSUM FROM ZREMCDBASELIST WHERE Z_PK = $pk" >"$out/checksum.txt"
query "$db" "SELECT typeof(ZMEMBERSHIPSOFREMINDERSINSECTIONSASDATA), typeof(ZMEMBERSHIPSOFREMINDERSINSECTIONSCHECKSUM), typeof(ZRESOLUTIONTOKENMAP_V3_JSONDATA) FROM ZREMCDBASELIST WHERE Z_PK = $pk" >"$out/column-types.txt"

# The list's identifiers, to compare with `reminders --json lists` (EventKit's calendarIdentifier).
query "$db" "SELECT hex(ZIDENTIFIER), ZCKIDENTIFIER FROM ZREMCDBASELIST WHERE Z_PK = $pk" >"$out/list-identifiers.txt" 2>/dev/null \
  || query "$db" "SELECT hex(ZIDENTIFIER) FROM ZREMCDBASELIST WHERE Z_PK = $pk" >"$out/list-identifiers.txt"

query "$db" "SELECT Z_PK, hex(ZIDENTIFIER), ZDISPLAYNAME, ZMARKEDFORDELETION FROM ZREMCDBASESECTION WHERE ZLIST = $pk ORDER BY Z_PK" >"$out/sections.txt"
query "$db" "SELECT hex(ZIDENTIFIER), ZTITLE, ZCOMPLETED FROM ZREMCDREMINDER WHERE ZLIST = $pk AND ZMARKEDFORDELETION = 0 ORDER BY Z_PK" >"$out/reminders.txt"

# Column layouts, to check the schema the reader expects.
for table in ZREMCDBASELIST ZREMCDBASESECTION ZREMCDREMINDER; do
  query "$db" "PRAGMA table_info($table)" >"$out/schema-$table.txt"
done
sw_vers >"$out/macos.txt"

stored=$(tr -d '[:space:]' <"$out/checksum.txt")
computed=$(shasum -a 512 "$out/memberships.json" | cut -d' ' -f1)
if [[ -z $stored ]]; then
  echo "No checksum stored (the list has no section memberships yet)."
elif [[ $(tr '[:upper:]' '[:lower:]' <<<"$stored") == "$computed" ]]; then
  echo "Checksum matches SHA-512 of the stored membership bytes."
else
  echo "WARNING: stored checksum differs from SHA-512 of the stored bytes:" >&2
  echo "  stored   $stored" >&2
  echo "  computed $computed" >&2
fi
echo "Done. Send $out/ back; the originals were not opened."
