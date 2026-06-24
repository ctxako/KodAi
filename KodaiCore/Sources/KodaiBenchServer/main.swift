import Foundation

let args = CommandLine.arguments
let port: UInt16 = {
    if let idx = args.firstIndex(of: "--port"), idx + 1 < args.count,
       let p = UInt16(args[idx + 1]) { return p }
    return 8788
}()

if #available(macOS 26.0, *) {
    let runner = LiveRunner()
    let server = BenchServer(port: port, runner: runner)
    try server.start()
    print("bench-server: Apple Foundation Models live runner")
    print("bench-server: POST http://localhost:\(port)/run  {\"prompt\":\"...\"}")
    RunLoop.main.run()
} else {
    fputs("bench-server requires macOS 26.0+\n", stderr)
    exit(1)
}
