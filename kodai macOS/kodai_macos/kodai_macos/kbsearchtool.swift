//
//  kbsearchtool.swift
//  kodai_macos
//
//  kb_search — read-only retrieval over the ~/life knowledge base
//  (kb_chunks table in ~/life/data/life.db, embedded by `life index`).
//  Query embeddings come from local Ollama (nomic-embed-text) so they match
//  the corpus vectors; if Ollama is unreachable the tool falls back to
//  keyword scoring instead of failing. Read-only, so no confirm gate.
//

import Foundation
import FoundationModels
import SQLite3

@Generable(description: "A query against the user's personal knowledge base")
struct KBSearchRequest {
    @Guide(description: "What to look for, e.g. 'MemoRx monetization plan' or 'KodAi provider decision'")
    var query: String
}

struct SearchKnowledgeBaseTool: Tool {
    typealias Arguments = KBSearchRequest

    var name: String { "kb_search" }

    var description: String {
        "Search the user's local knowledge base (~/life/kb): their projects (MemoRx, Urge Surfin, KodAi, Clockd, CTXA website, WGU), company notes, R&D entries, plans and decisions. Read-only. Use it whenever the user asks about their own projects, plans, decisions or notes. Cite the returned [source: …] paths in your answer and never invent content that is not in the results."
    }

    func call(arguments: KBSearchRequest) async throws -> String {
        let query = arguments.query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return "error: empty query" }
        return await LifeKnowledgeBase.search(query: query, limit: 4)
    }
}

enum LifeKnowledgeBase {
    struct Chunk {
        let path: String
        let heading: String
        let content: String
        let embedding: [Double]
    }

    private struct EmbedResponse: Decodable {
        let embeddings: [[Double]]
    }

    static var databaseURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("life/data/life.db")
    }

    static func search(query: String, limit: Int) async -> String {
        let chunks: [Chunk]
        do {
            chunks = try loadChunks()
        } catch {
            return "error: knowledge base unavailable — \(error.localizedDescription)"
        }
        guard !chunks.isEmpty else {
            return "error: knowledge base index is empty — run `life index` in ~/life"
        }

        var mode = "semantic"
        var ranked: [(score: Double, chunk: Chunk)]
        if let queryVector = await embedQuery(query) {
            ranked = chunks.map { (cosine(queryVector, $0.embedding), $0) }
        } else {
            mode = "keyword (ollama offline)"
            ranked = chunks.map { (keywordScore(query: query, text: $0.content), $0) }
        }
        ranked.sort { $0.score > $1.score }

        let top = ranked.prefix(limit).filter { $0.score > 0 }
        guard !top.isEmpty else {
            return "no matches in the knowledge base for: \(query)"
        }

        var output = "retrieval mode: \(mode)\n"
        for (score, chunk) in top {
            let heading = chunk.heading.isEmpty ? "" : " › \(chunk.heading)"
            output += "\n[source: \(chunk.path)\(heading)] (score \(String(format: "%.2f", score)))\n"
            output += String(chunk.content.prefix(700))
            output += "\n"
        }
        return output
    }

    // MARK: - SQLite (read-only)

    private enum KBError: LocalizedError {
        case cannotOpen(String)

        var errorDescription: String? {
            switch self {
            case .cannotOpen(let path): "cannot open \(path); does ~/life exist?"
            }
        }
    }

    private static func loadChunks() throws -> [Chunk] {
        var db: OpaquePointer?
        guard sqlite3_open_v2(databaseURL.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            sqlite3_close(db)
            throw KBError.cannotOpen(databaseURL.path)
        }
        defer { sqlite3_close(db) }

        var statement: OpaquePointer?
        let sql = "SELECT path, heading, content, embedding FROM kb_chunks"
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw KBError.cannotOpen("kb_chunks table (run `life index`)")
        }
        defer { sqlite3_finalize(statement) }

        let decoder = JSONDecoder()
        var chunks: [Chunk] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let path = sqlite3_column_text(statement, 0).map { String(cString: $0) } ?? ""
            let heading = sqlite3_column_text(statement, 1).map { String(cString: $0) } ?? ""
            let content = sqlite3_column_text(statement, 2).map { String(cString: $0) } ?? ""
            let embeddingJSON = sqlite3_column_text(statement, 3).map { String(cString: $0) } ?? "[]"
            let embedding = (try? decoder.decode([Double].self, from: Data(embeddingJSON.utf8))) ?? []
            chunks.append(Chunk(path: path, heading: heading, content: content, embedding: embedding))
        }
        return chunks
    }

    // MARK: - Query embedding (Ollama, matches corpus model)

    private static func embedQuery(_ query: String) async -> [Double]? {
        guard let url = URL(string: "http://localhost:11434/api/embed") else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "model": "nomic-embed-text",
            // nomic-embed-text uses asymmetric task prefixes; the corpus side
            // is stored with "search_document: " by `life index`.
            "input": ["search_query: \(query)"],
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: body) else { return nil }
        request.httpBody = data

        guard let (responseData, _) = try? await URLSession.shared.data(for: request),
              let decoded = try? JSONDecoder().decode(EmbedResponse.self, from: responseData),
              let vector = decoded.embeddings.first
        else {
            return nil
        }
        return vector
    }

    // MARK: - Scoring

    private static func cosine(_ a: [Double], _ b: [Double]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot = 0.0, normA = 0.0, normB = 0.0
        for index in a.indices {
            dot += a[index] * b[index]
            normA += a[index] * a[index]
            normB += b[index] * b[index]
        }
        let denominator = (normA.squareRoot() * normB.squareRoot())
        return denominator > 0 ? dot / denominator : 0
    }

    private static func keywordScore(query: String, text: String) -> Double {
        let haystack = text.lowercased()
        let terms = query.lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
            .filter { $0.count > 2 }
        guard !terms.isEmpty else { return 0 }
        var score = 0.0
        for term in terms where haystack.contains(term) {
            score += 1
        }
        return score / Double(terms.count)
    }
}
