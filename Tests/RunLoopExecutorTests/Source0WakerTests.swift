//
//  Source0WakerTests.swift
//
//  Copyright © 2026 Doug Russell. All rights reserved.
//

//  Waker-specific tests for the version-0 CFRunLoopSource that backs the wake
//  signal. The general executor behavior — ordering, coalescing, lifecycle traps,
//  post-stop discard — is covered by RunLoopExecutorTests; these assert the
//  lower-level invariant that the doorbell source is live while the executor runs
//  and invalidated on teardown, across repeated lifecycles (so nothing dangles).

import Foundation
import Testing
@testable import RunLoopExecutor

// Actor pinned to a caller-supplied executor; used only to confirm the thread is
// live (so the source is genuinely installed) before asserting on teardown.
private actor PinnedActor {
    nonisolated let executor: RunLoopExecutor
    nonisolated var unownedExecutor: UnownedSerialExecutor {
        executor.asUnownedSerialExecutor()
    }
    init(executor: RunLoopExecutor) {
        self.executor = executor
    }
    func ping() {}
}

@Suite struct Source0WakerTests {
    // While running the doorbell source is valid; after a synchronous stop() it
    // must be invalidated and cleared.
    @Test func sourceIsValidWhileRunningAndInvalidAfterStop() async {
        let executor = RunLoopExecutor(name: "s0-leak")
        executor.start()
        await PinnedActor(executor: executor).ping()   // ensure the thread is live
        #expect(executor.waker.sourceIsValid)          // ...and the source is real
        executor.stop()
        #expect(!executor.waker.sourceIsValid)         // torn down deterministically
    }

    // Many full lifecycles must not leave dangling valid sources.
    @Test func repeatedLifecyclesTearDownTheSource() async {
        for i in 0..<100 {
            let executor = RunLoopExecutor(name: "s0-leak-\(i)")
            executor.start()
            await PinnedActor(executor: executor).ping()
            executor.stop()
            #expect(!executor.waker.sourceIsValid)
        }
    }

    // An executor that is never started never installs a source.
    @Test func unstartedExecutorHasNoSource() {
        let executor = RunLoopExecutor(name: "s0-unstarted")
        #expect(!executor.waker.sourceIsValid)
    }   // executor has no other owner (never started) -> deinit runs here cleanly
}
