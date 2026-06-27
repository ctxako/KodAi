//
//  ToolCallParser.swift
//  kodai-consumer
//
//  The parser now lives in KodaiKernel so `kodai-route-eval` runs the EXACT
//  shipped extraction path (no drifting copy). Re-exported here under its
//  established names so existing call sites and tests stay unchanged.
//

import KodaiKernel

typealias ParseConfidence = KodaiKernel.ParseConfidence
typealias ToolCallParser = KodaiKernel.ToolCallParser
