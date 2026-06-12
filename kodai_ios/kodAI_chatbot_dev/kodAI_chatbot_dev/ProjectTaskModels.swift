//
//  ProjectTaskModels.swift
//  kodAI_chatbot_dev
//
//  The lightweight project/task vocabulary now lives in KodaiKernel as
//  shared value types. These typealiases keep the existing iOS code and
//  the Projects.json shape stable (CodingKeys are identical in-kernel).
//

import Foundation
import KodaiKernel

typealias TaskPriorityLite = KodaiTaskPriority
typealias KodaiTaskLite = KodaiTaskValue
typealias KodaiProjectLite = KodaiProjectValue
typealias DueTaskItem = DueTaskValue
