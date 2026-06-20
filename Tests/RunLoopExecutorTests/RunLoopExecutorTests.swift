//
//  RunLoopExecutorTests.swift
//
//  Copyright © 2026 Doug Russell. All rights reserved.
//

import Foundation
import os
import Testing
@testable import RunLoopExecutor

/// Actor pinned to a caller-supplied RunLoopExecutor.
/// 
/// Used to observe job execution and to drive stop() from the executor's own isolation domain.
private actor PinnedActor {
    nonisolated let executor: RunLoopExecutor
    nonisolated var unownedExecutor: UnownedSerialExecutor {
        executor.asUnownedSerialExecutor()
    }
    var count = 0
    init(executor: RunLoopExecutor) {
        self.executor = executor
    }
    func increment() {
        count += 1
    }
    func value() -> Int {
        count
    }
    // Calls stop() from the executor's own thread.
    func stopExecutor() {
        executor.stop()
    }
}

@Suite struct RunLoopExecutorTests {
    // MARK: - Thread identity

    @Test func runsOnDedicatedThread() async {
        let name = "rlx-test-\(Int.random(in: 0..<100_000))"
        let executor = RunLoopExecutor(name: name)
        executor.start()
        let actor = ExecutorActor(executor: executor)
        let threadName = await actor.currentThreadName()
        #expect(threadName == name)
        executor.stop()
    }

    @Test func twoExecutorsRunOnDifferentThreads() async {
        let e1 = RunLoopExecutor(name: "rlx-t1")
        let e2 = RunLoopExecutor(name: "rlx-t2")
        e1.start()
        e2.start()
        let a1 = ExecutorActor(executor: e1)
        let a2 = ExecutorActor(executor: e2)
        async let n1 = a1.currentThreadName()
        async let n2 = a2.currentThreadName()
        let (name1, name2) = await (n1, n2)
        #expect(name1 != name2)
        e1.stop()
        e2.stop()
    }

    // MARK: - Serial ordering

    @Test func sequentialAppendsPreserveOrder() async {
        let executor = RunLoopExecutor(name: "rlx-order")
        executor.start()
        let actor = ExecutorActor(executor: executor)
        for i in 0..<20 {
            await actor.append(i)
        }
        let result = await actor.all()
        #expect(result == Array(0..<20))
        executor.stop()
    }

    // MARK: - Actor isolation under concurrent access

    @Test func concurrentIncrementsReachCorrectTotal() async {
        let executor = RunLoopExecutor(name: "rlx-concurrent")
        executor.start()
        let counter = Counter(executor: executor)
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<100 {
                group.addTask { await counter.increment() }
            }
        }
        #expect(await counter.value() == 100)
        executor.stop()
    }

    // MARK: - Quality of service

    @Test func qualityOfServiceIsSetOnThread() async {
        let executor = RunLoopExecutor(
            name: "rlx-qos",
            qualityOfService: .userInteractive
        )
        executor.start()
        #expect(await QoSActor(executor: executor).currentQoS() == .userInteractive)
        executor.stop()
    }

    // MARK: - RunLoop source callback

    // Demonstrates that a CFRunLoopSource callback fires on the RunLoopExecutor's
    // thread and can signal a waiting actor via `suspendAwaitingThrow`. The callback
    // cancels the Task that is suspended in `installAndWait(source:)`, which throws
    // CancellationError.
    @Test func runLoopSourceCallbackHandledWithoutSuspending() async {
        await withRunLoopExecutor(name: "rlx-source") { executor in
            let actor = SourceActor(executor: executor)
            // Stuff the task ref so we can grab it in the SignalSource closure.
            let taskBox = OSAllocatedUnfairLock<Task<Bool, Never>?>(initialState: nil)
            let source = SignalSource {
                let task = taskBox.withLock { $0 }
                // Fired on the RunLoopExecutor's thread. Task.cancel() is safe
                // to call from any context — no active Swift Task required.
                task?.cancel()
            }
            let task = Task {
                await actor.installAndWait(source: source)
                return await actor.didFire()
            }
            taskBox.withLock {
                $0 = task
            }
            #expect(await task.value)
        }
    }

    // MARK: - Same-executor cross-actor calls

    // Two actors sharing a RunLoopExecutor occupy the same isolation domain.
    // assumeIsolated lets one call the other synchronously — no await, no
    // suspension, no thread hop.
    @Test func sameExecutorActorsCallEachOtherWithoutSuspending() async {
        let executor = RunLoopExecutor(name: "rlx-shared")
        executor.start()

        let greeter = Greeter(executor: executor)
        let requester = Requester(executor: executor)

        #expect(await requester.requestGreeting(with: greeter) == "hello, world.")

        let (myThread, theirThread) = await requester.threadNameViaBoth(with: greeter)
        #expect(myThread == theirThread)

        executor.stop()
    }

    // MARK: - Coalescing under burst load

    // A large, fast burst exercises the wake coalescing: at most one `perform`
    // hop is ever in flight, yet every job still runs. If wakeups were lost the
    // total would come up short.
    @Test func burstOfManyJobsAllRun() async {
        await withRunLoopExecutor(name: "rlx-burst") { executor in
            let actor = PinnedActor(executor: executor)
            await withTaskGroup(of: Void.self) { group in
                for _ in 0..<5_000 {
                    group.addTask { await actor.increment() }
                }
            }
            #expect(await actor.value() == 5_000)
        }
    }

    // MARK: - Lifecycle precondition traps (verified via exit tests)

    @Test func stopBeforeStartTraps() async {
        await #expect(processExitsWith: .failure) {
            let executor = RunLoopExecutor(name: "rlx-stop-before-start")
            executor.stop()
        }
    }

    @Test func doubleStopTraps() async {
        await #expect(processExitsWith: .failure) {
            let executor = RunLoopExecutor(name: "rlx-double-stop")
            executor.start()
            executor.stop()
            executor.stop()
        }
    }

    @Test func selfStopTraps() async {
        await #expect(processExitsWith: .failure) {
            let executor = RunLoopExecutor(name: "rlx-self-stop")
            executor.start()
            await PinnedActor(executor: executor).stopExecutor()
        }
    }

    @Test func doubleStartTraps() async {
        await #expect(processExitsWith: .failure) {
            let executor = RunLoopExecutor(name: "rlx-double-start")
            executor.start()
            executor.start()
        }
    }

    @Test func enqueueBeforeStartTraps() async {
        await #expect(processExitsWith: .failure) {
            let executor = RunLoopExecutor(name: "rlx-enqueue-before-start")
            _ = await PinnedActor(executor: executor).value()   // enqueues before start()
        }
    }

    @Test func enqueueAfterStopTraps() async {
        await #expect(processExitsWith: .failure) {
            let executor = RunLoopExecutor(name: "rlx-enqueue-after-stop")
            executor.start()
            executor.stop()
            _ = await PinnedActor(executor: executor).value()   // enqueues after stop()
        }
    }
}
