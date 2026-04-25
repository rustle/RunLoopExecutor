//
//  ExecutorActor.swift
//
//  Copyright © 2026 Doug Russell. All rights reserved.
//

import Foundation
import RunLoopExecutor

// Helper actor that runs on a caller-supplied RunLoopExecutor.
actor ExecutorActor {
    nonisolated let executor: RunLoopExecutor
    nonisolated var unownedExecutor: UnownedSerialExecutor {
        executor.asUnownedSerialExecutor()
    }
    var log: [Int] = []
    init(executor: RunLoopExecutor) {
        self.executor = executor
    }
    func currentThreadName() -> String? {
        Thread.current.name
    }
    func append(_ value: Int) {
        log.append(value)
    }
    func all() -> [Int] {
        log
    }
}
