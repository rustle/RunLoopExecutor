//
//  PoolActor.swift
//
//  Copyright © 2026 Doug Russell. All rights reserved.
//

import RunLoopExecutor

// Actor that runs on a given RunLoopExecutor — used to verify executor
// identity and exercise execution on a pool-vended executor.
actor TestPoolActor {
    nonisolated let executor: RunLoopExecutor
    nonisolated var unownedExecutor: UnownedSerialExecutor {
        executor.asUnownedSerialExecutor()
    }
    init(executor: RunLoopExecutor) {
        self.executor = executor
    }
    func ping() -> Bool {
        true
    }
    func executorID() -> ObjectIdentifier {
        ObjectIdentifier(executor)
    }
}
