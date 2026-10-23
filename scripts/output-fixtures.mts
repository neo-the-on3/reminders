// Regenerates Tests/RemiCoreTests/OutputFixtures.swift from remi's own src/cli/output.ts.
//
// Usage (from a checkout of https://github.com/mattheworiordan/remi with `npm ci` done):
//   TZ=UTC npx tsx /path/to/reminders/scripts/output-fixtures.mts > OutputFixtures.swift
// The clock is frozen at 2026-10-23T10:00:00Z and chalk is forced to colour level 0 and 3.
import { pathToFileURL } from "node:url";

const FIXED = Date.parse("2026-10-23T10:00:00Z");
const RealDate = Date;
// @ts-ignore - freeze "now" for remi's relative-date formatting
globalThis.Date = class extends RealDate {
	constructor(...args: unknown[]) {
		// @ts-ignore
		super(...(args.length ? args : [FIXED]));
	}
	static now() {
		return FIXED;
	}
};

const root = pathToFileURL(`${process.cwd()}/`).href;
const chalk = (await import(new URL("node_modules/chalk/source/index.js", root).href)).default;
const out = await import(new URL("src/cli/output.ts", root).href);

// remi's reminders/lists arrive from its Swift helper with sorted keys (JSONEncoder .sortedKeys);
// `section`/`flagged` are added afterwards by the TypeScript.
function helperOrder<T extends Record<string, unknown>>(o: T): T {
	const late = ["section", "flagged"];
	const keys = Object.keys(o).filter((k) => !late.includes(k)).sort();
	const out: Record<string, unknown> = {};
	for (const k of [...keys, ...late.filter((k) => k in o)]) out[k] = o[k];
	return out as T;
}

const reminders = [
	{ id: "A1", title: "Buy milk", isCompleted: false, listID: "L1", listName: "Groceries", priority: "high", dueDate: "2026-10-23", notes: "Organic only, the big bottle from the shop round the corner please", section: "Dairy", flagged: true },
	{ id: "A2", title: "Pay rent", isCompleted: false, listID: "L2", listName: "Home", priority: "medium", dueDate: "2026-10-20", isRecurring: true, recurrence: "monthly" },
	{ id: "A3", title: "Call mum", isCompleted: true, listID: "L2", listName: "Home", priority: "none", dueDate: "2026-10-22", completionDate: "2026-10-22" },
	{ id: "A4", title: "Dentist", isCompleted: false, listID: "L2", listName: "Home", priority: "low", dueDate: "2026-10-24", isRecurring: true },
	{ id: "A5", title: "Renew passport", isCompleted: false, listID: "L2", listName: "Home", priority: "none", dueDate: "2026-11-15" },
	{ id: "A6", title: "File taxes", isCompleted: false, listID: "L3", listName: "Admin", priority: "none", dueDate: "2027-04-01", section: "Money" },
	{ id: "A7", title: "Read book", isCompleted: false, listID: "L3", listName: "Admin", priority: "none", notes: "Short note" },
	{ id: "A8", title: "Soon", isCompleted: false, listID: "L3", listName: "Admin", priority: "none", dueDate: "2026-10-28", section: "Dairy" },
].map(helperOrder);
const lists = [
	{ id: "L1", title: "Groceries", reminderCount: 12, overdueCount: 0 },
	{ id: "L2", title: "Home 🏠", reminderCount: 3, overdueCount: 2 },
	{ id: "L3", title: "Ad", reminderCount: 0, overdueCount: 0 },
].map(helperOrder);
const sections = [
	{ id: "S1", displayName: "Dairy", listName: "Groceries", sortOrder: 0 },
	{ id: "S2", displayName: "Produce", listName: "Groceries", sortOrder: 1 },
];

type Case = [string, () => void];
const cases: Case[] = [
	["lists", () => out.outputLists(lists)],
	["listsEmpty", () => out.outputLists([])],
	["remindersPlain", () => out.outputReminders(reminders)],
	["remindersEmpty", () => out.outputReminders([], "Groceries")],
	["remindersList", () => out.outputReminders(reminders, "Groceries", { context: "list", groupBySections: true })],
	["remindersToday", () => out.outputReminders(reminders, undefined, { context: "today", showList: true, sortByDate: true })],
	["remindersOverdue", () => out.outputReminders(reminders, undefined, { context: "overdue", showList: true })],
	["remindersSorted", () => out.outputReminders(reminders, "All", { sortByDate: true })],
	["sections", () => out.outputSections(sections, "Groceries", new Map([["Dairy", 3]]))],
	["sectionsEmpty", () => out.outputSections([], "Groceries")],
	["message", () => out.outputMessage("Created reminder")],
	["error", () => out.outputError({ code: "LIST_NOT_FOUND", message: "No list matching \"x\"", suggestion: "Available lists:\n  - A\n  - B" })],
];

function capture(fn: () => void): [string, string] {
	let stdout = "";
	let stderr = "";
	const ow = process.stdout.write.bind(process.stdout);
	const ew = process.stderr.write.bind(process.stderr);
	// @ts-ignore
	process.stdout.write = (d: string) => ((stdout += d), true);
	// @ts-ignore
	process.stderr.write = (d: string) => ((stderr += d), true);
	try {
		fn();
	} finally {
		process.stdout.write = ow;
		process.stderr.write = ew;
	}
	return [stdout, stderr];
}

const swift = (s: string) => JSON.stringify(s).replace(/\\u001b/g, "\\u{1B}").replace(/\\u([0-9a-f]{4})/g, "\\u{$1}");
const lines: string[] = [];
for (const verbose of [false, true]) {
	out.setVerboseMode(verbose);
	for (const level of [0, 3]) {
		chalk.level = level;
		for (const json of [false, true]) {
			out.setJsonMode(json);
			for (const [name, fn] of cases) {
				const [o, e] = capture(fn);
				lines.push(`  OutputCase(${swift(name)}, verbose: ${verbose}, color: ${level === 3}, json: ${json}, stdout: ${swift(o)}, stderr: ${swift(e)}),`);
			}
		}
	}
}
console.log(`// Generated by scripts/output-fixtures.mts from remi's src/cli/output.ts (TZ=UTC, now = 2026-10-23T10:00:00Z).
// Do not edit by hand.

let outputCases: [OutputCase] = [
${lines.join("\n")}
]`);
