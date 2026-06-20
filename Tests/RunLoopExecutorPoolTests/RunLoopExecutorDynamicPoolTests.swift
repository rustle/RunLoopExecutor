//
//  RunLoopExecutorDynamicPoolTests.swift
//
//  Copyright © 2026 Doug Russell. All rights reserved.
//

import Foundation
import Testing
@testable import RunLoopExecutorPool
import os
import RunLoopExecutor

@Suite struct RunLoopExecutorDynamicPoolTests {
    @Test func basicExecution() async {
        let pool = RunLoopExecutorDynamicPool(maximumWidth: 2)
        let result = await pool.withRunLoopExecutor { executor in
            await TestPoolActor(executor: executor).ping()
        }
        #expect(result)
    }

    @Test func idleExecutorIsReusedAfterRelease() async {
        let pool = RunLoopExecutorDynamicPool(maximumWidth: 4)
        let first = await pool.withRunLoopExecutor {
            ObjectIdentifier($0)
        }
        let second = await pool.withRunLoopExecutor {
            ObjectIdentifier($0)
        }
        #expect(first == second)
    }

    // Releasing a lease must NOT stop the executor — it returns to the idle
    // list still running. Under the executor's lifecycle contract, enqueuing on
    // a stopped executor traps, so if `release` ever stopped it the actor job in
    // the second lease would crash. Reuse identity alone (above) wouldn't catch
    // that; this runs a real job on the reused executor.
    @Test func reusedIdleExecutorStillRunsJobsAfterRelease() async {
        let pool = RunLoopExecutorDynamicPool(maximumWidth: 4)
        let first = await pool.withRunLoopExecutor { executor in
            await TestPoolActor(executor: executor).executorID()
        }
        let (second, ran) = await pool.withRunLoopExecutor { executor in
            let actor = TestPoolActor(executor: executor)
            return (await actor.executorID(), await actor.ping())
        }
        #expect(first == second)   // same executor, reused from idle
        #expect(ran)               // ...and it still runs jobs after release
    }

    @Test func growsUpToMaximumWidth() async {
        let maxWidth = 3
        let pool = RunLoopExecutorDynamicPool(maximumWidth: maxWidth)
        let ids = OSAllocatedUnfairLock<Set<ObjectIdentifier>>(initialState: [])
        let ready = OSAllocatedUnfairLock<Int>(initialState: 0)

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<maxWidth {
                group.addTask {
                    await pool.withRunLoopExecutor { executor in
                        _ = ids.withLock { $0.insert(ObjectIdentifier(executor)) }
                        ready.withLock { $0 += 1 }
                        while ready.withLock({ $0 }) < maxWidth {
                            await Task.yield()
                        }
                    }
                }
            }
        }

        #expect(ids.withLock { $0 }.count == maxWidth)
    }

    @Test func capsAtMaximumWidth() async {
        let maxWidth = 2
        let pool = RunLoopExecutorDynamicPool(maximumWidth: maxWidth)
        let ids = OSAllocatedUnfairLock<Set<ObjectIdentifier>>(initialState: [])
        let ready = OSAllocatedUnfairLock<Int>(initialState: 0)
        let totalTasks = maxWidth + 2

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<totalTasks {
                group.addTask {
                    await pool.withRunLoopExecutor { executor in
                        _ = ids.withLock { $0.insert(ObjectIdentifier(executor)) }
                        ready.withLock { $0 += 1 }
                        while ready.withLock({ $0 }) < totalTasks {
                            await Task.yield()
                        }
                    }
                }
            }
        }

        #expect(ids.withLock { $0 }.count <= maxWidth)
    }

    @Test func errorPropagatesAndPoolRemainsUsable() async throws {
        let pool = RunLoopExecutorDynamicPool(maximumWidth: 2)
        struct Kaboom: Error {}

        await #expect(throws: Kaboom.self) {
            try await pool.withRunLoopExecutor { _ in
                throw Kaboom()
            }
        }

        // Pool must still be usable after an error
        let result = await pool.withRunLoopExecutor { executor in
            await TestPoolActor(executor: executor).ping()
        }
        #expect(result)
    }

    @Test func serialWidthOneSerializesWork() async {
        let pool = RunLoopExecutorDynamicPool(maximumWidth: 1)
        let log = OSAllocatedUnfairLock<[Int]>(initialState: [])
        for i in 0..<5 {
            await pool.withRunLoopExecutor { _ in
                log.withLock { $0.append(i) }
            }
        }
        #expect(log.withLock { $0 } == [0, 1, 2, 3, 4])
    }
}
