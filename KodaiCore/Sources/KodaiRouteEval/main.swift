//
//  kodai-route-eval
//
//  Committed regression eval for the kodai-consumer agent's *tool choosing*.
//  Runs labelled inputs through the real LFM2 using the EXACT shipped routing
//  config (KodaiKernel.ConsumerToolRouting), and reports how often each input
//  routes to the expected tool. Local-only (needs the gitignored GGUF):
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

struct Case { let input: String; let expected: String; let category: String }
// expected = the single tool that input should route to. For multi-intent the
// first action is expected (the app does one tool per turn).
let cases: [Case] = [
    // reminders (a task to do / remember)
    Case(input: "remind me to call mom tomorrow at 9am", expected: "create_reminder", category: "reminder"),
    Case(input: "remind me to take my meds at 8pm", expected: "create_reminder", category: "reminder"),
    Case(input: "don't let me forget to feed the dogs at 6am", expected: "create_reminder", category: "reminder"),
    Case(input: "remember to pay rent on the 1st", expected: "create_reminder", category: "reminder"),
    Case(input: "ping me to stretch in 2 hours", expected: "create_reminder", category: "reminder"),
    // calendar (something at a scheduled time)
    Case(input: "set up a dentist appointment friday at 2pm", expected: "create_calendar_event", category: "calendar"),
    Case(input: "schedule a meeting with sara monday 10am", expected: "create_calendar_event", category: "calendar"),
    Case(input: "add a lunch event tomorrow at noon", expected: "create_calendar_event", category: "calendar"),
    Case(input: "book a haircut saturday 11am", expected: "create_calendar_event", category: "calendar"),
    Case(input: "dentist fri 2pm", expected: "create_calendar_event", category: "calendar"),
    Case(input: "i have a doctor visit july 3rd at 3pm", expected: "create_calendar_event", category: "calendar"),
    // lists
    Case(input: "add bread to my groceries", expected: "add_to_list", category: "list"),
    Case(input: "put milk on the shopping list", expected: "add_to_list", category: "list"),
    Case(input: "add socks to my packing list", expected: "add_to_list", category: "list"),
    Case(input: "throw eggs on the grocery list", expected: "add_to_list", category: "list"),
    // save file
    Case(input: "save a note called ideas with my startup thoughts", expected: "save_file", category: "save"),
    Case(input: "save my packing list to a file", expected: "save_file", category: "save"),
    Case(input: "write a draft to a file named letter.txt", expected: "save_file", category: "save"),
    // read file
    Case(input: "read my shopping list file", expected: "read_file", category: "read"),
    Case(input: "open my notes file", expected: "read_file", category: "read"),
    Case(input: "what's in my todo file", expected: "read_file", category: "read"),
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
    // chit-chat → respond
    Case(input: "hi", expected: "respond", category: "chitchat"),
    Case(input: "thanks!", expected: "respond", category: "chitchat"),
    Case(input: "what can you do?", expected: "respond", category: "chitchat"),
    Case(input: "how are you?", expected: "respond", category: "chitchat"),
]

let toolNames = ["create_calendar_event", "create_reminder", "add_to_list", "save_file", "read_file", "respond"]
func routedTool(_ s: String) -> String? {
    for t in toolNames where s.contains("\(t)(") || s.contains("\"\(t)\"") { return t }
    return nil
}

let runtime = LocalModelRuntime(modelFileResolver: FileResolver(path: modelPath))
var knobs = LocalModelConfiguration.lfm2_5_1_2B_Instruct_Q4_K_M.defaultSamplerKnobs
knobs.temperature = 0.3
knobs.maxOutputTokens = 200
let system = ConsumerToolRouting.systemPrompt()
let primer = ConsumerToolRouting.toolCallPrimer

let catOrder = ["reminder", "calendar", "list", "save", "read", "unsupported", "chitchat"]
var byCat: [String: (ok: Int, n: Int)] = [:]
var misroutes: [String] = []
for c in cases {
    for _ in 0..<K {
        let stream = await runtime.generate(messages: [KodaiRuntimeMessage(role: .user, text: c.input)], systemPrompt: system, samplerKnobs: knobs, assistantPrimer: primer)
        var out = ""
        for try await event in stream { if case let .token(t, _) = event { out += t } }
        let routed = routedTool(out) ?? "NONE"
        var cat = byCat[c.category] ?? (0, 0)
        cat.n += 1; if routed == c.expected { cat.ok += 1 }
        byCat[c.category] = cat
        if routed != c.expected { misroutes.append("  [\(c.expected)] \"\(c.input)\" -> \(routed)") }
    }
}

var report = "\n===== TOOL ROUTING ACCURACY (K=\(K), \(cases.count) cases) =====\n"
var totalOK = 0, total = 0
for cat in catOrder {
    guard let c = byCat[cat] else { continue }
    report += String(format: "  %-12@ %d/%d\n", cat as NSString, c.ok, c.n)
    totalOK += c.ok; total += c.n
}
report += String(format: "  %-12@ %d/%d\n", "OVERALL" as NSString, totalOK, total)
if !misroutes.isEmpty { report += "\n  MISROUTES:\n" + misroutes.joined(separator: "\n") + "\n" }
print(report)
fflush(stdout)  // llama.cpp aborts on Metal teardown at exit; flush so the report survives
