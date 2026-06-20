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
    // defer so a throwing `body` still stops the executor; otherwise it would
    // deinit while `.running` and trip the deinit precondition, crashing the
    // test process and masking the original error.
    defer { executor.stop() }
    try await body(executor)
}
