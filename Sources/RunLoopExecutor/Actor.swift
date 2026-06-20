//
//  Actor.swift
//
//  Copyright © 2026 Doug Russell. All rights reserved.
//

import os

public extension Actor {
    /// Park and wait for `Task.cancel()`
    static func suspendAwaitingThrow() async throws {
        let state = OSAllocatedUnfairLock<CheckedContinuation<Void, Error>?>(initialState: nil)
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                let shouldResumeImmediately = state.withLock { stored -> Bool in
                    if Task.isCancelled {
                        return true
                    }
                    stored = continuation
                    return false
                }
                if shouldResumeImmediately {
                    continuation.resume(throwing: CancellationError())
                }
            }
        } onCancel: {
            let continuation = state.withLock {
                let continuation = $0
                $0 = nil
                return continuation
            }
            continuation?.resume(throwing: CancellationError())
        }
    }
}
