//
//  SourceActor.swift
//
//  Copyright © 2026 Doug Russell. All rights reserved.
//

import Foundation
import RunLoopExecutor

actor SourceActor {
    nonisolated let executor: RunLoopExecutor
    nonisolated var unownedExecutor: UnownedSerialExecutor {
        executor.asUnownedSerialExecutor()
    }
    private(set) var fired = false
    init(executor: RunLoopExecutor) {
        self.executor = executor
    }

    // Schedules the source from the RunLoop thread,
    // sets a timer to signal the source, then suspends.
    // The source callback cancels this task, waking us here.
    func installAndWait(source: SignalSource) async {
        source.schedule()
        Timer.scheduledTimer(withTimeInterval: 0.0,
                             repeats: false) { _ in
            source.signal()
        }
        do {
            try await Self.suspendAwaitingThrow()
        } catch is CancellationError {
            fired = true
        } catch {}
    }

    func didFire() -> Bool {
        fired
    }
}
