//
//  ToolCallValidator.swift
//  kodai-consumer
//
//  The validator now lives in KodaiKernel so `kodai-route-eval` runs the EXACT
//  shipped validation path (no drifting copy). Re-exported here under its
//  established names so existing call sites and tests stay unchanged.
//

import KodaiKernel

typealias ToolValidationError = KodaiKernel.ToolValidationError
typealias ToolCallValidator = KodaiKernel.ToolCallValidator
