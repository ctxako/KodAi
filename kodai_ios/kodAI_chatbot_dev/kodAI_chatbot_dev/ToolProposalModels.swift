//
//  ToolProposalModels.swift
//  kodAI_chatbot_dev
//
//  Tool proposal value models now live in KodaiKernel. These typealiases
//  keep existing call sites stable; proposal execution and the confirmation
//  card UI remain iOS-owned.
//

import Foundation
import KodaiKernel

typealias ToolProposalKindLite = KodaiToolProposalKind
typealias CreateTaskProposalLite = KodaiCreateTaskProposalValue
typealias PendingToolProposalLite = KodaiPendingToolProposalValue
