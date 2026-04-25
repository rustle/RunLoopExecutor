//
//  QoSActor.swift
//
//  Copyright © 2026 Doug Russell. All rights reserved.
//

import Foundation
import RunLoopExecutor

actor QoSActor {
    nonisolated let executor: RunLoopExecutor
    nonisolated var unownedExecutor: UnownedSerialExecutor {
        executor.asUnownedSerialExecutor()
    }
    init(executor: RunLoopExecutor) {
        self.executor = executor
    }
    func currentQoS() -> QualityOfService {
        Thread.current.qualityOfService
    }
}
