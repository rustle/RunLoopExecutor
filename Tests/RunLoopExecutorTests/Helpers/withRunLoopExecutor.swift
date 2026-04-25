//
//  withRunLoopExecutor.swift
//
//  Copyright © 2026 Doug Russell. All rights reserved.
//

import Foundation
import RunLoopExecutor

func withRunLoopExecutor(
    name: String = "rlx-test",
    qualityOfService: QualityOfService = .default,
    _ body: (RunLoopExecutor) async throws -> Void
) async rethrows {
    let executor = RunLoopExecutor(
        name: name,
        qualityOfService: qualityOfService
    )
    executor.start()
    try await body(executor)
    executor.stop()
}
