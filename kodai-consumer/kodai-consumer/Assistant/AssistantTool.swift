//
//  AssistantTool.swift
//  kodai-consumer
//
//  The v1 tool surface (3 create actions, all writes → confirm). The call value
//  types and the parse/validate path now live in KodaiKernel (so the shipped
//  config is exercised verbatim by `kodai-route-eval`); the app re-exports them
//  under their established names so existing call sites stay unchanged.
//

import Foundation
import KodaiKernel

/// v1 tool names. Kept tiny on purpose — a small, closed routing surface is
/// what makes a 1.2B reliable. (Canonical definition in KodaiKernel.)
typealias AssistantToolName = KodaiKernel.AssistantToolName

/// A tool call as emitted by the model and extracted by `ToolCallParser`:
/// a name plus flat string arguments. `ToolCallValidator` turns this into a
/// typed, checked `AssistantToolCall`.
typealias RawToolCall = KodaiKernel.RawToolCall

/// A validated, typed tool call — ready to render in a confirm card and execute
/// against EventKit / the Files app.
typealias AssistantToolCall = KodaiKernel.AssistantToolCall

/// Thin façade over the canonical routing config in KodaiKernel
/// (`ConsumerToolRouting`), kept so existing call sites stay unchanged while the
/// catalog/prompt/primer live in one shared place the routing eval also reads.
enum AssistantToolCatalog {
    static var respondToolName: String { ConsumerToolRouting.respondToolName }
    static var toolDefinitionsJSON: String { ConsumerToolRouting.toolDefinitionsJSON }
}
