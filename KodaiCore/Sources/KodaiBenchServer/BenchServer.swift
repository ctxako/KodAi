import Foundation
import Network

@available(macOS 26.0, *)
final class BenchServer: @unchecked Sendable {
    let port: UInt16
    let runner: LiveRunner
    private var listener: NWListener?

    init(port: UInt16, runner: LiveRunner) {
        self.port = port
        self.runner = runner
    }

    func start() throws {
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        let listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: port)!)
        self.listener = listener

        listener.newConnectionHandler = { [weak self] conn in
            self?.handleConnection(conn)
        }
        listener.stateUpdateHandler = { state in
            switch state {
            case .ready:
                print("bench-server: listening on http://localhost:\(self.port)")
            case .failed(let err):
                print("bench-server: listener failed — \(err)")
            default: break
            }
        }
        listener.start(queue: .main)
    }

    private func handleConnection(_ conn: NWConnection) {
        conn.start(queue: .global(qos: .userInitiated))
        conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, _, err in
            guard let self, let data, err == nil else {
                conn.cancel()
                return
            }
            let raw = String(data: data, encoding: .utf8) ?? ""
            self.route(raw: raw, conn: conn)
        }
    }

    private func route(raw: String, conn: NWConnection) {
        let firstLine = raw.prefix(while: { $0 != "\r" && $0 != "\n" })
        let parts = firstLine.split(separator: " ")
        let method = parts.count > 0 ? String(parts[0]) : ""
        let path = parts.count > 1 ? String(parts[1]) : ""

        if method == "OPTIONS" {
            sendCORS(conn: conn)
            return
        }

        if method == "GET" && path == "/health" {
            sendJSON(conn: conn, status: "200 OK", body: #"{"status":"ok"}"#)
            return
        }

        if method == "POST" && path == "/run" {
            let bodyStart = raw.range(of: "\r\n\r\n") ?? raw.range(of: "\n\n")
            let bodyStr = bodyStart.map { String(raw[$0.upperBound...]) } ?? ""
            handleRun(body: bodyStr, conn: conn)
            return
        }

        sendJSON(conn: conn, status: "404 Not Found", body: #"{"error":"not found"}"#)
    }

    private func handleRun(body: String, conn: NWConnection) {
        guard let data = body.data(using: .utf8),
              let req = try? JSONDecoder().decode(RunRequest.self, from: data) else {
            sendJSON(conn: conn, status: "400 Bad Request", body: #"{"error":"invalid JSON — need {\"prompt\":\"...\"}}"#)
            return
        }

        let header = """
        HTTP/1.1 200 OK\r
        Content-Type: text/event-stream\r
        Cache-Control: no-cache\r
        Connection: keep-alive\r
        Access-Control-Allow-Origin: *\r
        Access-Control-Allow-Headers: Content-Type\r
        \r

        """
        let headerData = header.data(using: .utf8)!
        conn.send(content: headerData, completion: .contentProcessed({ _ in }))

        Task {
            do {
                let stream = try await runner.run(
                    prompt: req.prompt,
                    system: req.system ?? "You are a helpful assistant.",
                    experimentId: req.experiment_id,
                    endpoint: req.endpoint.flatMap(URL.init(string:)),
                    token: req.token
                )
                for try await event in stream {
                    let json = try JSONEncoder().encode(event)
                    let sse = "data: \(String(data: json, encoding: .utf8)!)\n\n"
                    conn.send(content: sse.data(using: .utf8), completion: .contentProcessed({ _ in }))
                }
            } catch {
                let errSSE = "data: {\"error\":\"\(error.localizedDescription)\"}\n\n"
                conn.send(content: errSSE.data(using: .utf8), completion: .contentProcessed({ _ in }))
            }
            conn.send(content: nil, contentContext: .finalMessage, isComplete: true, completion: .contentProcessed({ _ in
                conn.cancel()
            }))
        }
    }

    private func sendCORS(conn: NWConnection) {
        let resp = """
        HTTP/1.1 204 No Content\r
        Access-Control-Allow-Origin: *\r
        Access-Control-Allow-Methods: POST, GET, OPTIONS\r
        Access-Control-Allow-Headers: Content-Type\r
        Content-Length: 0\r
        \r

        """
        conn.send(content: resp.data(using: .utf8), completion: .contentProcessed({ _ in conn.cancel() }))
    }

    private func sendJSON(conn: NWConnection, status: String, body: String) {
        let resp = """
        HTTP/1.1 \(status)\r
        Content-Type: application/json\r
        Access-Control-Allow-Origin: *\r
        Content-Length: \(body.utf8.count)\r
        \r
        \(body)
        """
        conn.send(content: resp.data(using: .utf8), completion: .contentProcessed({ _ in conn.cancel() }))
    }
}

struct RunRequest: Codable {
    let prompt: String
    let system: String?
    let experiment_id: String?
    let endpoint: String?
    let token: String?
}
