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
    var itemContains: String? = nil
    var nameContains: String? = nil
    var hasDate = false
}

struct Case {
    let input: String
    let expected: String
    let category: String
    var expect = Expect()
}

// expected = the single tool that input should route to. For multi-intent the
// first action is expected (the app does one tool per turn).
let cases: [Case] = [
    // reminders (a task to do / remember)
    Case(input: "remind me to call mom tomorrow at 9am", expected: "create_reminder", category: "reminder", expect: Expect(titleContains: "mom", hasDate: true)),
    Case(input: "remind me to take my meds at 8pm", expected: "create_reminder", category: "reminder", expect: Expect(titleContains: "meds", hasDate: true)),
    Case(input: "don't let me forget to feed the dogs at 6am", expected: "create_reminder", category: "reminder", expect: Expect(titleContains: "dog", hasDate: true)),
    Case(input: "remember to pay rent on the 1st", expected: "create_reminder", category: "reminder", expect: Expect(titleContains: "rent", hasDate: true)),
    Case(input: "ping me to stretch in 2 hours", expected: "create_reminder", category: "reminder", expect: Expect(titleContains: "stretch", hasDate: true)),
    // calendar (something at a scheduled time)
    Case(input: "set up a dentist appointment friday at 2pm", expected: "create_calendar_event", category: "calendar", expect: Expect(titleContains: "dentist", hasDate: true)),
    Case(input: "schedule a meeting with sara monday 10am", expected: "create_calendar_event", category: "calendar", expect: Expect(titleContains: "sara", hasDate: true)),
    Case(input: "add a lunch event tomorrow at noon", expected: "create_calendar_event", category: "calendar", expect: Expect(titleContains: "lunch", hasDate: true)),
    Case(input: "book a haircut saturday 11am", expected: "create_calendar_event", category: "calendar", expect: Expect(titleContains: "haircut", hasDate: true)),
    Case(input: "dentist fri 2pm", expected: "create_calendar_event", category: "calendar", expect: Expect(titleContains: "dentist", hasDate: true)),
    Case(input: "i have a doctor visit july 3rd at 3pm", expected: "create_calendar_event", category: "calendar", expect: Expect(titleContains: "doctor", hasDate: true)),
    // lists
    Case(input: "add bread to my groceries", expected: "add_to_list", category: "list", expect: Expect(listContains: "grocer", itemContains: "bread")),
    Case(input: "put milk on the shopping list", expected: "add_to_list", category: "list", expect: Expect(listContains: "shopping", itemContains: "milk")),
    Case(input: "add socks to my packing list", expected: "add_to_list", category: "list", expect: Expect(listContains: "packing", itemContains: "socks")),
    Case(input: "throw eggs on the grocery list", expected: "add_to_list", category: "list", expect: Expect(listContains: "grocer", itemContains: "eggs")),
    // save file
    Case(input: "save a note called ideas with my startup thoughts", expected: "save_file", category: "save", expect: Expect(nameContains: "ideas")),
    Case(input: "save my packing list to a file", expected: "save_file", category: "save", expect: Expect(nameContains: "packing")),
    Case(input: "write a draft to a file named letter.txt", expected: "save_file", category: "save", expect: Expect(nameContains: "letter")),
    // read file
    Case(input: "read my shopping list file", expected: "read_file", category: "read"),
    Case(input: "open my notes file", expected: "read_file", category: "read"),
    Case(input: "what's in my todo file", expected: "read_file", category: "read"),
    // query calendar
    Case(input: "what's on my calendar today", expected: "query_calendar", category: "query_cal"),
    Case(input: "do I have anything tomorrow", expected: "query_calendar", category: "query_cal"),
    Case(input: "what events do I have this week", expected: "query_calendar", category: "query_cal"),
    Case(input: "am I free tomorrow afternoon", expected: "query_calendar", category: "query_cal"),
    Case(input: "show me my schedule for today", expected: "query_calendar", category: "query_cal"),
    // query reminders
    Case(input: "what reminders do I have", expected: "query_reminders", category: "query_rem"),
    Case(input: "show me my to-do list", expected: "query_reminders", category: "query_rem"),
    Case(input: "what's on my groceries list", expected: "query_reminders", category: "query_rem"),
    Case(input: "do I have any pending reminders", expected: "query_reminders", category: "query_rem"),
    Case(input: "what do I need to do today", expected: "query_reminders", category: "query_rem"),
    // unsupported actions → respond (self-awareness)
    Case(input: "create a new folder called log", expected: "respond", category: "unsupported"),
    Case(input: "send an email to john", expected: "respond", category: "unsupported"),
    Case(input: "text my wife i'm running late", expected: "respond", category: "unsupported"),
    Case(input: "set an alarm for 7am", expected: "respond", category: "unsupported"),
    Case(input: "start a 10 minute timer", expected: "respond", category: "unsupported"),
    Case(input: "play some music", expected: "respond", category: "unsupported"),
    Case(input: "call mom right now", expected: "respond", category: "unsupported"),
    Case(input: "search the web for pizza places", expected: "respond", category: "unsupported"),
    Case(input: "translate hello to spanish", expected: "respond", category: "unsupported"),
    Case(input: "what's 15% of 200", expected: "respond", category: "unsupported"),
    Case(input: "delete my dentist reminder", expected: "respond", category: "unsupported"),
    Case(input: "mark the milk reminder done", expected: "respond", category: "unsupported"),
    // info questions the app can't answer (must NOT misroute to read_file)
    Case(input: "do you have the time and the weather", expected: "respond", category: "unsupported"),
    Case(input: "what's the weather today", expected: "respond", category: "unsupported"),
    Case(input: "what time is it", expected: "respond", category: "unsupported"),
    Case(input: "do you know the weather tomorrow", expected: "respond", category: "unsupported"),
    // chit-chat → respond
    Case(input: "hi", expected: "respond", category: "chitchat"),
    Case(input: "thanks!", expected: "respond", category: "chitchat"),
    Case(input: "what can you do?", expected: "respond", category: "chitchat"),
    Case(input: "how are you?", expected: "respond", category: "chitchat"),
]

// MARK: - Per-call accessors / arg checks

func titleOf(_ call: AssistantToolCall) -> String? {
    switch call {
    case let .createReminder(t, _, _, _): return t
    case let .createCalendarEvent(t, _, _, _, _): return t
    default: return nil
    }
}
func dateOf(_ call: AssistantToolCall) -> Date? {
    switch call {
    case let .createReminder(_, due, _, _): return due
    case let .createCalendarEvent(_, start, _, _, _): return start
    default: return nil
    }
}
func listItemOf(_ call: AssistantToolCall) -> (list: String, item: String)? {
    if case let .addToList(l, i) = call { return (l, i) }
    return nil
}
func fileNameOf(_ call: AssistantToolCall) -> String? {
    if case let .saveFile(name, _) = call { return name }
    return nil
}

func argFailures(_ call: AssistantToolCall, _ e: Expect) -> [String] {
    func has(_ hay: String?, _ needle: String) -> Bool {
        (hay ?? "").lowercased().contains(needle.lowercased())
    }
    var fails: [String] = []
    if let t = e.titleContains, !has(titleOf(call), t) { fails.append("title!~“\(t)”") }
    if let l = e.listContains, !has(listItemOf(call)?.list, l) { fails.append("list!~“\(l)”") }
    if let i = e.itemContains, !has(listItemOf(call)?.item, i) { fails.append("item!~“\(i)”") }
    if let n = e.nameContains, !has(fileNameOf(call), n) { fails.append("name!~“\(n)”") }
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
        "create_calendar_event": "cal", "create_reminder": "rem", "add_to_list": "list",
        "save_file": "save", "read_file": "read", "query_calendar": "qcal",
        "query_reminders": "qrem", "respond": "resp", "NONE": "—",
    ][tool] ?? tool
}
let actionTools: Set<String> = ["create_calendar_event", "create_reminder", "add_to_list", "save_file", "read_file", "query_calendar", "query_reminders"]

struct RunResult {
    let category: String
    let expected: String
    let routed: String
    let conf: ParseConfidence?
    let valid: Bool          // parsed AND (respond OR validates) — the first-try-valid signal
    let endToEndOK: Bool     // action case: right tool + valid + args
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
        let routedCorrect = routed == c.expected

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
        if !routedCorrect {
            detail = "  [\(short(c.expected))→\(short(routed))] \"\(c.input)\""
        } else if actionTools.contains(c.expected) {
            if let call = validatedCall {
                let fails = argFailures(call, c.expect)
                endToEndOK = fails.isEmpty
                if !fails.isEmpty { detail = "  [\(short(c.expected))] \"\(c.input)\" → \(fails.joined(separator: ", "))" }
            } else {
                detail = "  [\(short(c.expected))] \"\(c.input)\" → routed right but failed validation"
            }
        }

        results.append(RunResult(category: c.category, expected: c.expected, routed: routed,
                                  conf: conf, valid: valid, endToEndOK: endToEndOK, detail: detail))
    }
}

// MARK: - Report

func pct(_ ok: Int, _ n: Int) -> String { n == 0 ? "  —  " : String(format: "%5.1f%%", 100.0 * Double(ok) / Double(n)) }
func line(_ label: String, _ ok: Int, _ n: Int) -> String {
    String(format: "  %-13@ %3d/%-3d  %@\n", label as NSString, ok, n, pct(ok, n) as NSString)
}

let catOrder = ["reminder", "calendar", "list", "save", "read", "query_cal", "query_rem", "unsupported", "chitchat"]
var report = "\n===== kodai-route-eval  (K=\(K), \(cases.count) cases, \(results.count) runs) =====\n"

// 1. Routing accuracy
report += "\n-- Routing accuracy (right tool chosen) --\n"
var rOK = 0
for cat in catOrder {
    let runs = results.filter { $0.category == cat }
    guard !runs.isEmpty else { continue }
    let ok = runs.filter { $0.routed == $0.expected }.count
    report += line(cat, ok, runs.count)
    rOK += ok
}
report += line("OVERALL", rOK, results.count)

// 2. First-try-valid
let validOK = results.filter { $0.valid }.count
report += "\n-- First-try-valid (parsed + validated, zero retries) --\n"
report += line("OVERALL", validOK, results.count)

// 3. End-to-end correctness for action tools (right tool + valid + right args)
report += "\n-- End-to-end correct (action tools: tool + valid + args) --\n"
var eOK = 0, eN = 0
for cat in ["reminder", "calendar", "list", "save", "read", "query_cal", "query_rem"] {
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

// 5. Confusion matrix (rows = expected, cols = routed)
let routedLabels = ["create_calendar_event", "create_reminder", "add_to_list", "save_file", "read_file", "query_calendar", "query_reminders", "respond", "NONE"]
report += "\n-- Confusion matrix (row = expected, col = routed) --\n"
report += "  " + String(format: "%-6@", "exp\\got" as NSString)
for col in routedLabels { report += String(format: "%5@", short(col) as NSString) }
report += "\n"
for row in ["create_calendar_event", "create_reminder", "add_to_list", "save_file", "read_file", "query_calendar", "query_reminders", "respond"] {
    let runs = results.filter { $0.expected == row }
    guard !runs.isEmpty else { continue }
    report += "  " + String(format: "%-6@", short(row) as NSString)
    for col in routedLabels {
        let n = runs.filter { $0.routed == col }.count
        report += String(format: "%5@", (n == 0 ? "." : String(n)) as NSString)
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
