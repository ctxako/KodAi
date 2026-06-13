import Foundation

public final class ContextAssembler {
    private let budget: TokenBudget

    public init(budget: TokenBudget = TokenBudget()) {
        self.budget = budget
    }

    // MARK: - Block-first assembly (callers build blocks directly; session-based
    // provider assembly lives in KodaiPersistence)

    public func assemble(blocks rawBlocks: [ContextBlock]) -> (prompt: String, manifest: ContextManifest) {
        let sorted = rawBlocks.sorted { $0.priority < $1.priority }
        return applyBudget(to: sorted)
    }

    // MARK: - Shared budget logic

    private func applyBudget(
        to rawBlocks: [ContextBlock]
    ) -> (prompt: String, manifest: ContextManifest) {
        // Apply per-block token caps, trimming content to fit.
        let capped: [(block: ContextBlock, wasTruncated: Bool)] = rawBlocks.map { block in
            if let cap = budget.cap(for: block.kind), block.tokenEstimate > cap {
                var trimmed = block
                trimmed.content = trim(block.content, to: cap)
                trimmed.tokenEstimate = TokenEstimator.estimate(trimmed.content)
                return (block: trimmed, wasTruncated: true)
            }
            return (block: block, wasTruncated: false)
        }

        // Persona and time are never excluded regardless of budget.
        let neverDrop: Set<String> = ["persona", "time"]
        var included: [(block: ContextBlock, wasTruncated: Bool)] = []
        var excluded: [ContextBlock] = []
        var remaining = budget.total

        for entry in capped {
            if neverDrop.contains(entry.block.kind) {
                included.append(entry)
                remaining -= entry.block.tokenEstimate
            } else if entry.block.tokenEstimate <= remaining {
                included.append(entry)
                remaining -= entry.block.tokenEstimate
            } else {
                excluded.append(entry.block)
            }
        }

        var records: [ContextBlockRecord] = included.map { entry in
            ContextBlockRecord(
                kind: entry.block.kind,
                sourceID: entry.block.sourceID,
                tokenEstimate: entry.block.tokenEstimate,
                status: entry.wasTruncated ? .truncated : .included
            )
        }
        records += excluded.map { block in
            ContextBlockRecord(
                kind: block.kind,
                sourceID: block.sourceID,
                tokenEstimate: block.tokenEstimate,
                status: .excluded,
                reason: "budget_exceeded"
            )
        }

        let totalUsed = included.reduce(0) { $0 + $1.block.tokenEstimate }
        let prompt = included.map { $0.block.content }.joined(separator: "\n\n")

        let manifest = ContextManifest(
            blocks: records,
            totalTokens: totalUsed,
            budgetLimit: budget.total,
            promptVersion: Prompts.version
        )

        return (prompt, manifest)
    }

    private func trim(_ content: String, to tokenCap: Int) -> String {
        let targetChars = tokenCap * 4
        guard content.count > targetChars else { return content }
        return String(content.prefix(targetChars)) + "…"
    }
}
