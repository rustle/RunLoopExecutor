//
//  Counter.swift
//
//  Copyright © 2026 Doug Russell. All rights reserved.
//

import Foundation
import RunLoopExecutor

actor Counter {
    nonisolated let executor: RunLoopExecutor
    nonisolated var unownedExecutor: UnownedSerialExecutor {
        executor.asUnownedSerialExecutor()
    }
    var count = 0
    init(executor: RunLoopExecutor) {
        self.executor = executor
    }
    func increment() {
        count += 1
    }
    func value() -> Int {
        count
    }
}
