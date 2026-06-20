//
//  RunLoopExecutorFixedPool.swift
//
//  Copyright © 2017-2026 Doug Russell. All rights reserved.
//

import Foundation
import RunLoopExecutor
import Synchronization

/// Rudimentary thread pool allocating via round-robin.
public final class RunLoopExecutorFixedPool: Sendable {
    private let executors: [RunLoopExecutor]
    private let index = Atomic<Int>(0)

    public init(
        name: String? = nil,
        qualityOfService: QualityOfService = .default,
        count: Int = ProcessInfo.processInfo.activeProcessorCount
    ) {
        executors = (0..<count).map { _ in
            let executor = RunLoopExecutor(
                name: "\(name ?? "RunLoopExecutor")-\(count)",
                qualityOfService: qualityOfService
            )
            executor.start()
            return executor
        }
    }

    deinit {
        executors.forEach { $0.stop() }
    }

    public func next() -> RunLoopExecutor {
        let i = index.wrappingAdd(1, ordering: .relaxed).newValue
        return executors[i % executors.count]
    }
}
