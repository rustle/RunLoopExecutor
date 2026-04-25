//
//  RunLoopExecutorFixedPoolTests.swift
//
//  Copyright © 2026 Doug Russell. All rights reserved.
//

import Foundation
import Testing
@testable import RunLoopExecutorPool
import os
import RunLoopExecutor

@Suite struct RunLoopExecutorFixedPoolTests {
    @Test func executorsAreStarted() async {
        let pool = RunLoopExecutorFixedPool(count: 2)
        #expect(await TestPoolActor(executor: pool.next()).ping())
    }

    @Test func nextCyclesThroughAllExecutors() {
        let count = 4
        let pool = RunLoopExecutorFixedPool(count: count)
        var seen: Set<ObjectIdentifier> = []
        for _ in 0..<count {
            seen.insert(ObjectIdentifier(pool.next()))
        }
        #expect(seen.count == count)
    }

    @Test func nextWrapsAroundRoundRobin() {
        let count = 3
        let pool = RunLoopExecutorFixedPool(count: count)
        let firstRound = (0..<count).map { _ in ObjectIdentifier(pool.next()) }
        let secondRound = (0..<count).map { _ in ObjectIdentifier(pool.next()) }
        #expect(firstRound == secondRound)
    }

    @Test func defaultCountMatchesActiveProcessors() {
        let pool = RunLoopExecutorFixedPool()
        let processorCount = ProcessInfo.processInfo.activeProcessorCount
        var seen: Set<ObjectIdentifier> = []
        for _ in 0..<processorCount {
            seen.insert(ObjectIdentifier(pool.next()))
        }
        #expect(seen.count == processorCount)
    }

    @Test func concurrentExecutionAcrossPool() async {
        let pool = RunLoopExecutorFixedPool(count: 4)
        let results = await withTaskGroup(of: Bool.self, returning: [Bool].self) { group in
            for _ in 0..<20 {
                let executor = pool.next()
                group.addTask {
                    await TestPoolActor(executor: executor).ping()
                }
            }
            var all: [Bool] = []
            for await result in group {
                all.append(result)
            }
            return all
        }
        #expect(results.count == 20)
        #expect(results.allSatisfy { $0 })
    }
}
