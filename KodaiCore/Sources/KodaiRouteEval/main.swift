//
//  kodai-route-eval
//
//  Committed regression eval for the kodai-consumer agent. Runs labelled inputs
//  through the real LFM2 using the EXACT shipped routing config + parse/validate
//  path (KodaiKernel.ConsumerToolRouting / ToolCallParser / ToolCallValidator),
//  and reports the metrics that back the product's core claim — "a 1.2B reliably
//  emits the right JSON on the first try":
//
//    1. Routing accuracy    — did it pick the right tool?            (by category)
//    2. First-try-valid     — did the single emission parse AND validate,
//                             with zero retries?                     (overall)
//    3. End-to-end correct  — right tool + valid + right arguments?  (action tools)
//    4. Confidence mix      — native / json / low / none.
//    5. Confusion matrix    — expected tool × routed tool.
//
//  v2 surface: 20 tools across 7 domains + respond. Cases where more than one
//  first move is defensible (e.g. "cancel my 3pm meeting" needs an ID from
//  calendar_list_events first) list the alternates in `alsoOK`.
//
//  Local-only (needs the gitignored GGUF):
//
//      swift run -c release kodai-route-eval --model-path <path-to.gguf> [--k 2]
//

import Foundation
import KodaiKernel
import KodaiRuntime

struct FileResolver: ModelFileResolver {
    let path: String
    func resolve(configuration: LocalModelConfiguration) throws -> URL {
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw LocalModelRuntimeError.modelFileMissing(expectedFileName: url.lastPathComponent)
        }
        return url
    }
}

func flag(_ name: String) -> String? {
    let a = CommandLine.arguments
    guard let i = a.firstIndex(of: name), i + 1 < a.count else { return nil }
    return a[i + 1]
}

guard let modelPath = flag("--model-path") else {
    FileHandle.standardError.write("Usage: kodai-route-eval --model-path <gguf> [--k <runs-per-case>]\n".data(using: .utf8)!)
    exit(2)
}
let K = Int(flag("--k") ?? "1") ?? 1

// MARK: - Cases

/// Loose argument expectations. Keep them conservative — distinctive keyword
/// substrings, not exact strings — so the harness is a regression signal, not a
/// brittle oracle. `hasDate` asserts the validated call carries a (future) date,
/// which catches the real failure of the model dropping the time it was given.
struct Expect {
    var titleContains: String? = nil
    var listContains: String? = nil
    var pathContains: String? = nil
    var queryContains: String? = nil
    var nameContains: String? = nil
    var contentContains: String? = nil
    var urlContains: String? = nil
    var hasDate = false
}

struct Case {
    let input: String
    let expected: String
    let category: String
    var alsoOK: Set<String> = []
    var expect = Expect()
}

// expected = the best single first tool for the input (the app does one tool per
// turn). alsoOK = alternates that are also correct behavior, counted as routed-OK
// but excluded from argument checks.
let cases: [Case] = [
    // reminders_create (a task to do / remember)
    Case(input: "remind me to call mom tomorrow at 9am", expected: "reminders_create", category: "reminder", expect: Expect(titleContains: "mom", hasDate: true)),
    Case(input: "remind me to take my meds at 8pm", expected: "reminders_create", category: "reminder", expect: Expect(titleContains: "meds", hasDate: true)),
    Case(input: "don't let me forget to feed the dogs at 6am", expected: "reminders_create", category: "reminder", expect: Expect(titleContains: "dog", hasDate: true)),
    Case(input: "remember to pay rent on the 1st", expected: "reminders_create", category: "reminder", expect: Expect(titleContains: "rent")),
    Case(input: "ping me to stretch in 2 hours", expected: "reminders_create", category: "reminder", expect: Expect(titleContains: "stretch", hasDate: true)),
    Case(input: "add a to-do: renew my passport", expected: "reminders_create", category: "reminder", expect: Expect(titleContains: "passport")),

    // reminders_create with list_name (list items)
    Case(input: "add bread to my groceries", expected: "reminders_create", category: "list", expect: Expect(titleContains: "bread", listContains: "grocer")),
    Case(input: "put milk on the shopping list", expected: "reminders_create", category: "list", expect: Expect(titleContains: "milk", listContains: "shopping")),
    Case(input: "add socks to my packing list", expected: "reminders_create", category: "list", expect: Expect(titleContains: "socks", listContains: "packing")),
    Case(input: "throw eggs on the grocery list", expected: "reminders_create", category: "list", expect: Expect(titleContains: "eggs", listContains: "grocer")),

    // calendar_create_event (something at a scheduled time)
    Case(input: "set up a dentist appointment friday at 2pm", expected: "calendar_create_event", category: "calendar", expect: Expect(titleContains: "dentist", hasDate: true)),
    Case(input: "schedule a meeting with sara monday 10am", expected: "calendar_create_event", category: "calendar", expect: Expect(titleContains: "sara", hasDate: true)),
    Case(input: "add a lunch event tomorrow at noon", expected: "calendar_create_event", category: "calendar", expect: Expect(titleContains: "lunch", hasDate: true)),
    Case(input: "book a haircut saturday 11am", expected: "calendar_create_event", category: "calendar", expect: Expect(titleContains: "haircut", hasDate: true)),
    Case(input: "dentist fri 2pm", expected: "calendar_create_event", category: "calendar", expect: Expect(titleContains: "dentist", hasDate: true)),
    Case(input: "i have a doctor visit july 3rd at 3pm", expected: "calendar_create_event", category: "calendar", expect: Expect(titleContains: "doctor", hasDate: true)),

    // calendar_list_events (what's scheduled)
    Case(input: "what's on my calendar today", expected: "calendar_list_events", category: "qcal"),
    Case(input: "do I have anything tomorrow", expected: "calendar_list_events", category: "qcal"),
    Case(input: "what events do I have this week", expected: "calendar_list_events", category: "qcal"),
    Case(input: "am I free tomorrow afternoon", expected: "calendar_list_events", category: "qcal"),
    Case(input: "show me my schedule for today", expected: "calendar_list_events", category: "qcal"),

    // reminders_list (what do I need to do)
    Case(input: "what reminders do I have", expected: "reminders_list", category: "qrem"),
    Case(input: "show me my to-do list", expected: "reminders_list", category: "qrem"),
    Case(input: "what's on my groceries list", expected: "reminders_list", category: "qrem"),
    Case(input: "do I have any pending reminders", expected: "reminders_list", category: "qrem"),
    Case(input: "what do I need to do today", expected: "reminders_list", category: "qrem"),

    // ID-dependent flows: the right FIRST move is the list call that yields the ID.
    Case(input: "delete my dentist appointment from the calendar", expected: "calendar_list_events", category: "id_flow", alsoOK: ["respond"]),
    Case(input: "cancel my 3pm meeting tomorrow", expected: "calendar_list_events", category: "id_flow", alsoOK: ["respond", "calendar_delete_event"]),
    Case(input: "mark the milk reminder as done", expected: "reminders_list", category: "id_flow", alsoOK: ["respond", "reminders_complete"]),
    Case(input: "complete my passport to-do", expected: "reminders_list", category: "id_flow", alsoOK: ["respond", "reminders_complete"]),

    // contacts_search
    Case(input: "find john's phone number", expected: "contacts_search", category: "contacts_q", expect: Expect(queryContains: "john")),
    Case(input: "look up sarah in my contacts", expected: "contacts_search", category: "contacts_q", expect: Expect(queryContains: "sarah")),
    Case(input: "what's mike's email address", expected: "contacts_search", category: "contacts_q", expect: Expect(queryContains: "mike")),
    Case(input: "do I have a contact for dr patel", expected: "contacts_search", category: "contacts_q", expect: Expect(queryContains: "patel")),

    // contacts_create
    Case(input: "add a contact for jane doe, 555-1234", expected: "contacts_create", category: "contacts_w", expect: Expect(nameContains: "jane")),
    Case(input: "save bob to my contacts, his number is 415-222-3333", expected: "contacts_create", category: "contacts_w", expect: Expect(nameContains: "bob")),
    Case(input: "new contact: amy chen, amy@example.com", expected: "contacts_create", category: "contacts_w", expect: Expect(nameContains: "amy")),

    // files_create
    Case(input: "save a note called ideas with my startup thoughts", expected: "files_create", category: "files_w", expect: Expect(pathContains: "idea")),
    Case(input: "write a draft to a file named letter.txt", expected: "files_create", category: "files_w", expect: Expect(pathContains: "letter")),
    Case(input: "save 'buy milk, eggs, bread' to shopping.txt", expected: "files_create", category: "files_w", expect: Expect(pathContains: "shopping")),

    // files_read
    Case(input: "read my shopping list file", expected: "files_read", category: "files_r"),
    Case(input: "open my notes file", expected: "files_read", category: "files_r"),
    Case(input: "what's in my todo file", expected: "files_read", category: "files_r"),

    // files_list
    Case(input: "what files do I have in icloud", expected: "files_list", category: "files_l"),
    Case(input: "list the files in my documents folder", expected: "files_list", category: "files_l"),
    Case(input: "show me my saved files", expected: "files_list", category: "files_l"),

    // files_create_folder (supported in v2!)
    Case(input: "create a new folder called logs", expected: "files_create_folder", category: "folder", expect: Expect(pathContains: "log")),
    Case(input: "make a folder named receipts in icloud", expected: "files_create_folder", category: "folder", expect: Expect(pathContains: "receipt")),

    // files_delete
    Case(input: "delete my old notes file", expected: "files_delete", category: "files_d", alsoOK: ["files_list"]),
    Case(input: "remove draft.txt", expected: "files_delete", category: "files_d", expect: Expect(pathContains: "draft")),

    // clipboard
    Case(input: "what's on my clipboard", expected: "clipboard_read", category: "clip_r"),
    Case(input: "read what I just copied", expected: "clipboard_read", category: "clip_r"),
    Case(input: "copy 'be right there' to the clipboard", expected: "clipboard_write", category: "clip_w", expect: Expect(contentContains: "right there")),
    Case(input: "put my wifi password hunter2 on the clipboard", expected: "clipboard_write", category: "clip_w", expect: Expect(contentContains: "hunter2")),

    // notifications (explicit notification phrasing — reminder phrasing routes to reminders)
    Case(input: "send me a notification at 5pm that says leave now", expected: "notification_schedule", category: "notif", alsoOK: ["reminders_create"], expect: Expect(hasDate: true)),
    Case(input: "pop up a notification tomorrow morning: check the oven", expected: "notification_schedule", category: "notif", alsoOK: ["reminders_create"], expect: Expect(hasDate: true)),

    // web_fetch / open_url
    Case(input: "fetch https://example.com and tell me what it says", expected: "web_fetch", category: "web", expect: Expect(urlContains: "example.com")),
    Case(input: "get the text from https://news.ycombinator.com", expected: "web_fetch", category: "web", expect: Expect(urlContains: "ycombinator")),
    Case(input: "open apple.com", expected: "open_url", category: "url", expect: Expect(urlContains: "apple.com")),
    Case(input: "open maps", expected: "open_url", category: "url", alsoOK: ["respond"]),

    // unsupported actions → respond (self-awareness)
    Case(input: "send an email to john", expected: "respond", category: "unsupported", alsoOK: ["contacts_search"]),
    Case(input: "text my wife i'm running late", expected: "respond", category: "unsupported", alsoOK: ["contacts_search"]),
    Case(input: "set an alarm for 7am", expected: "respond", category: "unsupported", alsoOK: ["reminders_create", "notification_schedule"]),
    Case(input: "start a 10 minute timer", expected: "respond", category: "unsupported", alsoOK: ["notification_schedule"]),
    Case(input: "play some music", expected: "respond", category: "unsupported"),
    Case(input: "call mom right now", expected: "respond", category: "unsupported", alsoOK: ["contacts_search", "open_url"]),
    Case(input: "translate hello to spanish", expected: "respond", category: "unsupported"),
    Case(input: "what's 15% of 200", expected: "respond", category: "unsupported"),
    Case(input: "turn on do not disturb", expected: "respond", category: "unsupported"),
    Case(input: "take a photo", expected: "respond", category: "unsupported"),

    // info questions the app can't answer (must NOT misroute to files_read)
    Case(input: "do you have the time and the weather", expected: "respond", category: "unsupported"),
    Case(input: "what's the weather today", expected: "respond", category: "unsupported"),
    Case(input: "what time is it", expected: "respond", category: "unsupported"),
    Case(input: "do you know the weather tomorrow", expected: "respond", category: "unsupported"),

    // chit-chat → respond
    Case(input: "hi", expected: "respond", category: "chitchat"),
    Case(input: "thanks!", expected: "respond", category: "chitchat"),
    Case(input: "what can you do?", expected: "respond", category: "chitchat"),
    Case(input: "how are you?", expected: "respond", category: "chitchat"),
    Case(input: "good morning", expected: "respond", category: "chitchat"),
]

// MARK: - Per-call accessors / arg checks

func titleOf(_ call: AssistantToolCall) -> String? {
    switch call {
    case let .remindersCreate(t, _, _, _, _): return t
    case let .calendarCreateEvent(t, _, _, _, _, _, _): return t
    case let .notificationSchedule(t, _, _, _): return t
    default: return nil
    }
}
func dateOf(_ call: AssistantToolCall) -> Date? {
    switch call {
    case let .remindersCreate(_, due, _, _, _): return due
    case let .calendarCreateEvent(_, start, _, _, _, _, _): return start
    case let .notificationSchedule(_, _, trigger, _): return trigger
    default: return nil
    }
}
func listNameOf(_ call: AssistantToolCall) -> String? {
    switch call {
    case let .remindersCreate(_, _, _, list, _): return list
    case let .remindersList(list, _): return list
    default: return nil
    }
}
func pathOf(_ call: AssistantToolCall) -> String? {
    switch call {
    case let .filesList(p), let .filesRead(p), let .filesCreate(p, _),
         let .filesCreateFolder(p), let .filesDelete(p):
        return p
    default: return nil
    }
}
func queryOf(_ call: AssistantToolCall) -> String? {
    if case let .contactsSearch(q) = call { return q }
    return nil
}
func firstNameOf(_ call: AssistantToolCall) -> String? {
    if case let .contactsCreate(f, l, _, _, _, _) = call { return [f, l].compactMap { $0 }.joined(separator: " ") }
    return nil
}
func contentOf(_ call: AssistantToolCall) -> String? {
    switch call {
    case let .clipboardWrite(c): return c
    case let .filesCreate(_, c): return c
    default: return nil
    }
}
func urlOf(_ call: AssistantToolCall) -> String? {
    switch call {
    case let .webFetch(u), let .openUrl(u): return u
    default: return nil
    }
}

func argFailures(_ call: AssistantToolCall, _ e: Expect) -> [String] {
    func has(_ hay: String?, _ needle: String) -> Bool {
        (hay ?? "").lowercased().contains(needle.lowercased())
    }
    var fails: [String] = []
    if let t = e.titleContains, !has(titleOf(call), t) { fails.append("title!~“\(t)”") }
    if let l = e.listContains, !has(listNameOf(call), l) { fails.append("list!~“\(l)”") }
    if let p = e.pathContains, !has(pathOf(call), p) { fails.append("path!~“\(p)”") }
    if let q = e.queryContains, !has(queryOf(call), q) { fails.append("query!~“\(q)”") }
    if let n = e.nameContains, !has(firstNameOf(call), n) { fails.append("name!~“\(n)”") }
    if let c = e.contentContains, !has(contentOf(call), c) { fails.append("content!~“\(c)”") }
    if let u = e.urlContains, !has(urlOf(call), u) { fails.append("url!~“\(u)”") }
    if e.hasDate, dateOf(call) == nil { fails.append("missing date") }
    return fails
}

// MARK: - Run

let runtime = LocalModelRuntime(modelFileResolver: FileResolver(path: modelPath))
var knobs = LocalModelConfiguration.lfm2_5_1_2B_Instruct_Q4_K_M.defaultSamplerKnobs
knobs.temperature = 0.3
knobs.maxOutputTokens = 200
let system = ConsumerToolRouting.systemPrompt()
let primer = ConsumerToolRouting.toolCallPrimer
let parser = ToolCallParser()
let validator = ToolCallValidator()

func confLabel(_ c: ParseConfidence?) -> String {
    switch c {
    case .native: return "native"
    case .json: return "json"
    case .low: return "low"
    case nil: return "none"
    }
}
func short(_ tool: String) -> String {
    [
        "calendar_create_event": "cal+", "calendar_list_events": "cal?", "calendar_delete_event": "cal-",
        "reminders_create": "rem+", "reminders_list": "rem?", "reminders_complete": "rem✓",
        "contacts_search": "con?", "contacts_create": "con+",
        "files_list": "fil?", "files_read": "filr", "files_create": "fil+",
        "files_create_folder": "dir+", "files_delete": "fil-",
        "clipboard_read": "clp?", "clipboard_write": "clp+",
        "notification_schedule": "not+", "notification_cancel": "not-",
        "web_fetch": "web", "open_url": "url",
        "respond": "resp", "NONE": "—",
    ][tool] ?? tool
}

struct RunResult {
    let category: String
    let expected: String
    let routed: String
    let routedOK: Bool
    let conf: ParseConfidence?
    let valid: Bool          // parsed AND (respond OR validates) — the first-try-valid signal
    let endToEndOK: Bool     // action case: primary tool + valid + args
    let detail: String?      // misroute / arg-fail line for the report
}

var results: [RunResult] = []

for c in cases {
    for _ in 0..<K {
        let stream = await runtime.generate(
            messages: [KodaiRuntimeMessage(role: .user, text: c.input)],
            systemPrompt: system, samplerKnobs: knobs, assistantPrimer: primer
        )
        var out = ""
        for try await event in stream { if case let .token(t, _) = event { out += t } }

        let parsed = parser.parse(out)
        let routed = parsed?.0.name ?? "NONE"
        let conf = parsed?.1
        let routedOK = routed == c.expected || c.alsoOK.contains(routed)

        // First-try-valid: the single emission must parse and either be `respond`
        // (a legitimate terminal) or validate as a real action call — no retry.
        var validatedCall: AssistantToolCall? = nil
        var valid = false
        if let raw = parsed?.0 {
            if raw.name == ConsumerToolRouting.respondToolName {
                valid = true
            } else if case let .success(call) = validator.validate(raw, userInput: c.input) {
                valid = true
                validatedCall = call
            }
        }

        var endToEndOK = false
        var detail: String? = nil
        if !routedOK {
            detail = "  [\(short(c.expected))→\(short(routed))] \"\(c.input)\""
        } else if routed == c.expected, c.expected != "respond" {
            if let call = validatedCall {
                let fails = argFailures(call, c.expect)
                endToEndOK = fails.isEmpty
                if !fails.isEmpty { detail = "  [\(short(c.expected))] \"\(c.input)\" → \(fails.joined(separator: ", "))" }
            } else {
                detail = "  [\(short(c.expected))] \"\(c.input)\" → routed right but failed validation"
            }
        } else {
            // alsoOK alternate or respond: routed acceptably, args not asserted.
            endToEndOK = valid
        }

        results.append(RunResult(category: c.category, expected: c.expected, routed: routed,
                                  routedOK: routedOK, conf: conf, valid: valid,
                                  endToEndOK: endToEndOK, detail: detail))
    }
}

// MARK: - Report

func pct(_ ok: Int, _ n: Int) -> String { n == 0 ? "  —  " : String(format: "%5.1f%%", 100.0 * Double(ok) / Double(n)) }
func line(_ label: String, _ ok: Int, _ n: Int) -> String {
    String(format: "  %-13@ %3d/%-3d  %@\n", label as NSString, ok, n, pct(ok, n) as NSString)
}

var catOrder: [String] = []
for c in cases where !catOrder.contains(c.category) { catOrder.append(c.category) }

var report = "\n===== kodai-route-eval  (K=\(K), \(cases.count) cases, \(results.count) runs) =====\n"

// 1. Routing accuracy
report += "\n-- Routing accuracy (right tool chosen, alternates OK) --\n"
var rOK = 0
for cat in catOrder {
    let runs = results.filter { $0.category == cat }
    guard !runs.isEmpty else { continue }
    let ok = runs.filter { $0.routedOK }.count
    report += line(cat, ok, runs.count)
    rOK += ok
}
report += line("OVERALL", rOK, results.count)

// 2. First-try-valid
let validOK = results.filter { $0.valid }.count
report += "\n-- First-try-valid (parsed + validated, zero retries) --\n"
report += line("OVERALL", validOK, results.count)

// 3. End-to-end correctness (right tool + valid + right args)
report += "\n-- End-to-end correct (tool + valid + args) --\n"
var eOK = 0, eN = 0
for cat in catOrder where cat != "chitchat" && cat != "unsupported" {
    let runs = results.filter { $0.category == cat }
    guard !runs.isEmpty else { continue }
    let ok = runs.filter { $0.endToEndOK }.count
    report += line(cat, ok, runs.count)
    eOK += ok; eN += runs.count
}
report += line("ACTIONS", eOK, eN)

// 4. Parse-confidence mix
report += "\n-- Parse-confidence mix --\n"
for conf in ["native", "json", "low", "none"] {
    let n = results.filter { confLabel($0.conf) == conf }.count
    if n > 0 { report += line(conf, n, results.count) }
}

// 5. Confusion matrix (rows = expected, cols = routed), built from observed labels
var expLabels: [String] = []
for c in cases where !expLabels.contains(c.expected) { expLabels.append(c.expected) }
var gotLabels = expLabels
for r in results where !gotLabels.contains(r.routed) { gotLabels.append(r.routed) }
report += "\n-- Confusion matrix (row = expected, col = routed) --\n"
report += "  " + String(format: "%-6@", "e\\g" as NSString)
for col in gotLabels { report += String(format: "%6@", short(col) as NSString) }
report += "\n"
for row in expLabels {
    let runs = results.filter { $0.expected == row }
    guard !runs.isEmpty else { continue }
    report += "  " + String(format: "%-6@", short(row) as NSString)
    for col in gotLabels {
        let n = runs.filter { $0.routed == col }.count
        report += String(format: "%6@", (n == 0 ? "." : String(n)) as NSString)
    }
    report += "\n"
}

// 6. Failure detail
let fails = results.compactMap { $0.detail }
if !fails.isEmpty {
    report += "\n-- Misroutes & argument failures --\n"
    // De-dup identical lines (common when K>1) with a count suffix.
    var counts: [String: Int] = [:]
    var order: [String] = []
    for f in fails { if counts[f] == nil { order.append(f) }; counts[f, default: 0] += 1 }
    for f in order { report += f + (counts[f]! > 1 ? "  (×\(counts[f]!))" : "") + "\n" }
}

print(report)
fflush(stdout)  // llama.cpp aborts on Metal teardown at exit; flush so the report survives
