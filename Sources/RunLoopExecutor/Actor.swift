//
//  Actor.swift
//
//  Copyright © 2026 Doug Russell. All rights reserved.
//

import os

public extension Actor {
    static func suspendAwaitingThrow() async throws {
        let state = OSAllocatedUnfairLock<CheckedContinuation<Void, Error>?>(initialState: nil)
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                guard !Task.isCancelled else {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                state.withLock {
                    $0 = continuation
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
